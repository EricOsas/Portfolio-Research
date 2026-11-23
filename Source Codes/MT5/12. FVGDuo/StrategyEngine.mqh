//+------------------------------------------------------------------+
//|                                             StrategyEngine.mqh   |
//| FVG Duo Strategy Engine (Opening Drive + Trend FVG)              |
//| Developed by Osamwonyi Eric (@You_FoundEric)                     |
//| Copyright 2026-2027, Osamwonyi Eric (@You_FoundEric)             |
//|                                                                  |
//| PARITY BUILD                                                     |
//| Event-driven on completed M1 bars. Mirrors the Python oracle in  |
//| tests/python/fvg_duo_engine.py:                                  |
//|   od_signal_for_date()      -> EvaluateOD()                      |
//|   compute_trend_signals()   -> PushM15() + EvaluateTrend()       |
//|   run_day()                 -> OnBarOpenM1() + HandleODSignal()  |
//|   simulate_trade()          -> broker SL/TP + session flatten    |
//|                                                                  |
//| The oracle exits are per M1 bar: gap through the level first     |
//| (fill at bar open), then the intrabar touch (fill at the level). |
//| A server side stop/limit reproduces exactly that, so exits are   |
//| delegated to the broker and journalled from deal history.        |
//+------------------------------------------------------------------+
#property strict
#property tester_no_cache

#include <Trade/Trade.mqh>

//--- Enums
enum ENUM_ATR_METHOD
{
   ATR_METHOD_SMA,       // Simple Moving Average (SMA)
   ATR_METHOD_RMA        // Wilder's Smoothed Average (RMA)
};

enum ENUM_ATR_REF
{
   ATR_REF_C2,           // ATR window includes c2 (bar k-1)
   ATR_REF_C1            // ATR window ends at c1 (bar k-2)
};

enum ENUM_SIZING_MODE
{
   SIZING_FIXED,            // Fixed Lots
   SIZING_PERCENT,          // Risk % of Live Equity
   SIZING_CASH,             // Fixed Cash Risk (USD)
   SIZING_PERCENT_BALANCE   // Risk % of Fixed Initial Balance (Non-compounding)
};

enum ENUM_MERGE_ANCHOR
{
   MERGE_TREND_ENTRY,    // Stop anchored to Trend entry price
   MERGE_OD_SIGNAL       // Stop anchored to OD signal bar open
};

//--- Fixed Strategy Parameters (Optimal B3a)
#define B3A_TREND_ATR_MULT       1.25
#define B3A_TREND_EMA_FAST       50
#define B3A_TREND_EMA_SLOW       100
#define B3A_OD_STOP_PCT          0.0125
#define B3A_TREND_AFTER_STOPOUT  true
#define B3A_ATR_METHOD           ATR_METHOD_SMA
#define B3A_ATR_REF              ATR_REF_C2

//--- Inputs
const bool   InpEnableOD = true;
const bool   InpEnableTrend = true;
const bool   InpFvgStrict = true;
const double InpTickSize = 0.0;
const double InpTrendRR = 3.0;
const ENUM_MERGE_ANCHOR InpMergeAnchor = MERGE_TREND_ENTRY;

input group "==========  1 - Sizing & Risk  =========="
input ENUM_SIZING_MODE  InpSizingMode          = SIZING_FIXED;       // Sizing Mode
input double            InpFixedLots           = 1.0;                // Fixed Lots
input double            InpRiskPercent         = 1.0;                // Risk % per Trade
input double            InpCashRisk         = 100.0;              // Cash risk per trade (account currency)
input double            InpFixedBalance     = 0.0;                // Fixed balance (account currency; 0 = derive from initial balance)
input int               InpRiskSlippageTicks   = 2;                  // Stressed Exit Slippage (ticks, reserved in risk)
input bool              InpAllowMinLotOverride = true;               // Take the broker minimum when the budget is below it (false = skip)

input group " "
input group "==========  2 - Costs & Execution  =========="
input ulong             InpMagic               = 909150;             // EA Magic Number
input ulong             InpDeviation           = 10;                 // Max Slippage Points
input double            InpCommissionRTPerLot  = 7.0;                // Round-turn Commission per Lot ($3.50 open + $3.50 close)

input group "  "
input group "==========  3 - Display & Visuals  =========="
input bool              ShowVisuals            = true;               // Draw FVG Boxes and Markers
input bool              ShowDashboard          = true;               // Display Performance HUD

// Forward includes
// ===== CLK-CORE 1.2 BEGIN ===================================================================================
// STANDARD BLOCK - paste verbatim. Do not edit per EA. Changes happen only in the standard, then re-splice every EA.
//
// Broker clock core. PURE: every function depends only on its arguments. No terminal, file, chart or market access,
// no static caches, no hidden "now". Same inputs give the same outputs in tester and live, at any call time.
//
// Model:   server = UTC + baseMin*60 + dst(rule, utc)
//   baseMin  server-minus-UTC in STANDARD (non-DST) time, minutes, multiple of 15, within [-720, +840]
//   rule     CLK_RULE_NONE (fixed offset) | CLK_RULE_US (server follows US DST) | CLK_RULE_EU (server follows EU DST)
//   DST dates: US 2nd Sun Mar 07:00 UTC -> 1st Sun Nov 06:00 UTC; EU last Sun Mar 01:00 UTC -> last Sun Oct 01:00 UTC
//   (valid 2007 onward; earlier years need historical rules and are out of scope).
//
// A broker can change its server offset or its DST behaviour during a sample. One (rule, base) cannot describe
// that history, so the core also carries a DATED SCHEDULE: an ordered list of segments, each a (rule, base) in
// force from a UTC instant. A one-segment schedule is identical to the single model, so nothing is special-cased.
//
// Internal time domain is UTC. Server time exists only at the boundary: ticks, bar and position stamps in, chart
// objects and order expirations out. Convert once at the boundary, then compare and schedule in UTC.
//
// Server wall time -> UTC is not always one-to-one. It is resolved, never halted:
//   FOLD  (clock falls back, wall time occurs twice): the caller supplies lowerBoundUtc, a known lower bound on the true
//         instant (previous resolved UTC in a tick stream, or the PC clock). The smallest candidate >= lowerBoundUtc
//         is returned. With no bound (<=0) the FIRST occurrence is returned. conv reports which rule applied.
//   GAP   (clock jumps forward, wall time never occurs): the wall time is read with the pre-transition offset, which
//         shifts it forward by the gap, the usual convention. conv = CLK_CONV_GAP. Real server stamps never fall in a gap.
#define CLK_CORE_VERSION   "1.2"
#define CLK_BASE_INVALID   (-999999)
#define CLK_MIN_WEEKS      40
#define CLK_MIN_MARGIN     3
#define CLK_MAX_WEEKS      256

enum ENUM_CLK_RULE { CLK_RULE_NONE=0, CLK_RULE_US=1, CLK_RULE_EU=2 };
enum ENUM_CLK_MODE { CLK_MODE_AUTO=0, CLK_MODE_MANUAL=1 };
enum ENUM_CLK_CONV { CLK_CONV_EXACT=0, CLK_CONV_FOLD_BOUND=1, CLK_CONV_FOLD_FIRST=2, CLK_CONV_GAP=3 };
enum ENUM_CLK_ANCHOR { CLK_ANCHOR_OFF=0, CLK_ANCHOR_AUTO=1, CLK_ANCHOR_OPEN17=2, CLK_ANCHOR_OPEN18=3 };

// ---- civil date arithmetic (proleptic Gregorian, integers only; days since 1970-01-01; years >= 1970) -------------------
int ClkDaysFromCivil(int y,int m,int d)
{
   if(m<=2) y--;
   int era=y/400;
   int yoe=y-era*400;
   int doy=(153*(m>2?m-3:m+9)+2)/5+d-1;
   int doe=yoe*365+yoe/4-yoe/100+doy;
   return era*146097+doe-719468;
}
void ClkCivilFromDays(int z,int &y,int &m,int &d)
{
   z+=719468;
   int era=z/146097;
   int doe=z-era*146097;
   int yoe=(doe-doe/1460+doe/36524-doe/146096)/365;
   y=yoe+era*400;
   int doy=doe-(365*yoe+yoe/4-yoe/100);
   int mp=(5*doy+2)/153;
   d=doy-(153*mp+2)/5+1;
   m=mp<10?mp+3:mp-9;
   if(m<=2) y++;
}
int ClkDayOfWeek(int days) { return ((days%7)+7+4)%7; }          // 0=Sunday ... 6=Saturday
int ClkDow(int y,int m,int d) { return ClkDayOfWeek(ClkDaysFromCivil(y,m,d)); }
int ClkDaysInMonth(int y,int m)
{
   int ny=(m==12)?y+1:y, nm=(m==12)?1:m+1;
   return ClkDaysFromCivil(ny,nm,1)-ClkDaysFromCivil(y,m,1);
}
int ClkNthWeekday(int y,int m,int nth,int dow)                   // day of month of the nth given weekday (nth 1..5)
{
   int first=ClkDow(y,m,1);
   return 1+(dow-first+7)%7+7*(nth-1);
}
datetime ClkUtcAt(int y,int m,int d,int hour) { return (datetime)((long)ClkDaysFromCivil(y,m,d)*86400+hour*3600); }

// ---- DST rules -------------------------------------------------------------------------------------------------------
int ClkNyUtcOffset(datetime utc)                                  // America/New_York: -4h in US DST, else -5h
{
   int y,m,d; ClkCivilFromDays((int)(utc/86400),y,m,d);
   datetime start=ClkUtcAt(y,3,ClkNthWeekday(y,3,2,0),7);
   datetime end  =ClkUtcAt(y,11,ClkNthWeekday(y,11,1,0),6);
   return (utc>=start && utc<end) ? -4*3600 : -5*3600;
}
int ClkEuUtcOffset(datetime utc)                                  // EU summer-time delta: 3600 in EU DST, else 0
{
   int y,m,d; ClkCivilFromDays((int)(utc/86400),y,m,d);
   int ms=ClkNthWeekday(y,3,5,0);  if(ms>ClkDaysInMonth(y,3))  ms-=7;
   int os=ClkNthWeekday(y,10,5,0); if(os>ClkDaysInMonth(y,10)) os-=7;
   return (utc>=ClkUtcAt(y,3,ms,1) && utc<ClkUtcAt(y,10,os,1)) ? 3600 : 0;
}
int ClkDstDelta(datetime utc,int rule)                            // seconds the server clock is ahead of its standard time
{
   if(rule==CLK_RULE_US) return ClkNyUtcOffset(utc)==-4*3600 ? 3600 : 0;
   if(rule==CLK_RULE_EU) return ClkEuUtcOffset(utc);
   return 0;
}
bool ClkNearTransition(datetime utc,int rule,int hours)           // a DST change of this rule lies within +-hours of utc
{
   return ClkDstDelta(utc-hours*3600,rule)!=ClkDstDelta(utc+hours*3600,rule);
}

// ---- broker server clock <-> UTC ----------------------------------------------------------------------------------
datetime ClkUtcToServer(datetime utc,int rule,int baseMin) { return utc+baseMin*60+ClkDstDelta(utc,rule); }   // always unique
datetime ClkServerToUtc(datetime server,int rule,int baseMin,datetime lowerBoundUtc,int &conv)
{
   conv=CLK_CONV_EXACT;
   datetime a=server-baseMin*60;                                   // read as standard time (later instant in a fold)
   if(rule==CLK_RULE_NONE) return a;
   datetime b=a-3600;                                              // read as DST (earlier instant in a fold)
   bool va=(ClkUtcToServer(a,rule,baseMin)==server);
   bool vb=(ClkUtcToServer(b,rule,baseMin)==server);
   if(va && !vb) return a;
   if(vb && !va) return b;
   if(va && vb)                                                     // fold
   {
      if(lowerBoundUtc<=0) { conv=CLK_CONV_FOLD_FIRST; return b; }
      conv=CLK_CONV_FOLD_BOUND;
      return (b>=lowerBoundUtc) ? b : a;
   }
   conv=CLK_CONV_GAP;                                              // gap
   return a;
}

// ---- America/New_York wall time <-> UTC (for strategies defined in New York time) -------------------------------------
datetime ClkUtcToNy(datetime utc) { return utc+ClkNyUtcOffset(utc); }
// nyWall = New York wall clock encoded as a datetime (as if UTC). Fold -> first occurrence. Gap -> shifted forward.
datetime ClkNyToUtc(datetime nyWall,int &conv)
{
   conv=CLK_CONV_EXACT;
   datetime d=nyWall+4*3600, s=nyWall+5*3600;                      // EDT reading is the earlier instant
   bool vd=(ClkNyUtcOffset(d)==-4*3600), vs=(ClkNyUtcOffset(s)==-5*3600);
   if(vd && !vs) return d;
   if(vs && !vd) return s;
   if(vd && vs) { conv=CLK_CONV_FOLD_FIRST; return d; }
   conv=CLK_CONV_GAP;
   return s;
}

int ClkNyYmd(datetime utc)                                         // New York calendar date of a UTC instant, YYYYMMDD
{
   int y,m,d; ClkCivilFromDays((int)(ClkUtcToNy(utc)/86400),y,m,d);
   return y*10000+m*100+d;
}
int ClkNyMinute(datetime utc) { return (int)((ClkUtcToNy(utc)%86400)/60); }          // New York minute-of-day 0..1439
// UTC instant of "minuteOfDay on New York date ymd" (e.g. 09:30 -> 570). Fold -> first occurrence, gap -> shifted forward.
datetime ClkNyYmdToUtc(int ymd,int minuteOfDay,int &conv)
{
   return ClkNyToUtc((datetime)((long)ClkDaysFromCivil(ymd/10000,(ymd/100)%100,ymd%100)*86400+minuteOfDay*60),conv);
}

// ---- weekly open/close evidence: infer a broker's DST rule (and, under one stated assumption, its base) ----------------
// The FX week opens and closes at fixed New York times, so the SERVER stamps of the first and last M15 bar of each week
// reveal how the server clock moves against New York. With r_w = Sunday 17:00 NY (opens) or Friday 16:45 NY (start of the
// last M15 bar before the 17:00 NY close), in UTC, and a hypothesised rule R:
//      dev_w(R) = stamp_w - r_w - dst(R, r_w)
// is constant across weeks iff R is the true rule. The constant is base plus the feed's convention; late holiday opens
// only add sporadic positive noise; a wrong rule leaves +-1h steps. Opens and closes are scored together (twice the
// evidence in the same history). The RULE is therefore provable from history alone.
// The absolute BASE is not: a feed shifted by one hour looks identical to a server shifted by one hour. Sources of the
// base, strongest first: live observation (TimeTradeServer-TimeGMT), a registry or learned profile, then - tester only -
// the CLOSE ANCHOR below, which rests on ONE stated assumption: the weekly close is Friday 17:00 NY (last M15 bar 16:45 NY).
// Use symbols that follow the global FX week (FX pairs, metals, US-hours indices); others fail the quality gates.
datetime ClkWeekRefUtc(datetime stamp)                            // Sunday 17:00 New York, UTC
{
   int z=(int)(stamp/86400), dw=ClkDayOfWeek(z);
   int sun=(dw>=4)?z+(7-dw):z-dw;
   datetime approx=(datetime)((long)sun*86400+22*3600);
   return (datetime)((long)sun*86400+17*3600-ClkNyUtcOffset(approx));
}
datetime ClkWeekCloseRefUtc(datetime stamp)                       // Friday 16:45 New York, UTC (start of the last M15 bar of the week)
{
   int z=(int)(stamp/86400), dw=ClkDayOfWeek(z);
   int fri=(dw==6)?z-1:z;
   datetime approx=(datetime)((long)fri*86400+21*3600);
   return (datetime)((long)fri*86400+16*3600+45*60-ClkNyUtcOffset(approx));
}
// First/last-bar-of-week stamps from ascending M15 bar stamps: a >=40h hole, last bar before on Fri/Sat, first after on Sun/Mon.
int ClkWeekOpens(datetime &bars[],int n,datetime &opens[])
{
   int c=0;
   for(int i=1;i<n;i++)
   {
      if(bars[i]-bars[i-1]<40*3600) continue;
      int dp=ClkDayOfWeek((int)(bars[i-1]/86400)), dn=ClkDayOfWeek((int)(bars[i]/86400));
      if((dp!=5 && dp!=6) || (dn!=0 && dn!=1)) continue;
      ArrayResize(opens,c+1); opens[c++]=bars[i];
   }
   return c;
}
int ClkWeekCloses(datetime &bars[],int n,datetime &closes[])
{
   int c=0;
   for(int i=1;i<n;i++)
   {
      if(bars[i]-bars[i-1]<40*3600) continue;
      int dp=ClkDayOfWeek((int)(bars[i-1]/86400)), dn=ClkDayOfWeek((int)(bars[i]/86400));
      if((dp!=5 && dp!=6) || (dn!=0 && dn!=1)) continue;
      ArrayResize(closes,c+1); closes[c++]=bars[i-1];
   }
   return c;
}
// How many weeks of one series sit on a single constant under rule r (tolerance 15 min); mode = that constant (seconds).
int ClkSeriesHits(datetime &st[],int n,int rule,bool isClose,long &mode)
{
   mode=0;
   if(n<=0) return 0;
   if(n>CLK_MAX_WEEKS) n=CLK_MAX_WEEKS;
   long dev[CLK_MAX_WEEKS];
   for(int w=0;w<n;w++)
   {
      datetime ref=isClose ? ClkWeekCloseRefUtc(st[w]) : ClkWeekRefUtc(st[w]);
      dev[w]=(long)st[w]-(long)ref-ClkDstDelta(ref,rule);
   }
   int h=0;
   for(int w=0;w<n;w++)
   {
      int c=0;
      for(int j=0;j<n;j++) if(MathAbs(dev[j]-dev[w])<=900) c++;
      if(c>h) { h=c; mode=dev[w]; }
   }
   return h;
}
// status: 1 resolved | 0 ambiguous | -1 insufficient history (<40 weekly opens). Resolved needs >=85% of all open+close
// observations on one constant per series, and the winner beating the runner-up by >=3 observations.
// nClose may be 0 (opens only). modeOpen/modeClose are the winning rule's constants in seconds.
int ClkInferRule(datetime &opens[],int nOpen,datetime &closes[],int nClose,int &rule,int &hits,int &margin,int &modeOpen,int &modeClose)
{
   rule=-1; hits=0; margin=0; modeOpen=0; modeClose=0;
   if(nOpen<CLK_MIN_WEEKS) return -1;
   if(nOpen>CLK_MAX_WEEKS) nOpen=CLK_MAX_WEEKS;
   if(nClose>CLK_MAX_WEEKS) nClose=CLK_MAX_WEEKS;
   int bestH=-1, secondH=-1, bestR=0; long bestMO=0, bestMC=0;
   for(int r=0;r<3;r++)
   {
      long mo=0, mc=0;
      int h=ClkSeriesHits(opens,nOpen,r,false,mo)+ClkSeriesHits(closes,nClose,r,true,mc);
      if(h>bestH) { secondH=bestH; bestH=h; bestR=r; bestMO=mo; bestMC=mc; }
      else if(h>secondH) secondH=h;
   }
   int total=nOpen+nClose;
   rule=bestR; hits=bestH; margin=bestH-(secondH<0?0:secondH); modeOpen=(int)bestMO; modeClose=(int)bestMC;
   return (bestH*100>=total*85 && margin>=CLK_MIN_MARGIN) ? 1 : 0;
}
// Base (minutes) implied by a live server-minus-UTC observation (seconds, rounded to 15 min) under a rule.
int ClkBaseFromLive(int observedSec,int rule,datetime utcNow)
{
   int adj=observedSec-ClkDstDelta(utcNow,rule);
   if(adj%900!=0) return CLK_BASE_INVALID;
   int m=adj/60;
   return (m<-720 || m>840) ? CLK_BASE_INVALID : m;
}
// Base from a weekly-open constant ONLY under an assumed feed open hour (17 or 18 NY). An assumption, not a proof.
int ClkBaseFromAnchor(int modeSec,int openNYHour)
{
   int adj=modeSec-(openNYHour-17)*3600;
   int r=(adj>=0) ? ((adj+450)/900)*900 : ((adj-450)/900)*900;
   if(MathAbs(adj-r)>300) return CLK_BASE_INVALID;
   int m=r/60;
   return (m<-720 || m>840) ? CLK_BASE_INVALID : m;
}
// CLOSE ANCHOR (tester): base from the weekly-close constant, assuming the weekly close is Friday 17:00 NY, accepted ONLY
// when the open constant agrees under a 17:00 or 18:00 NY open (that agreement is the consistency check) and the base is
// on the 15-minute grid. openNY returns 17 or 18. The accepted feed shapes are exactly (open=close) and (open=close+1h), so
// the single residual assumption is close = 17:00 NY: a feed whose close is at c NY is read as a server shifted by (c-17)h.
// That is why the result is labelled and a live/registry/learned profile always outranks it.
int ClkBaseFromCloseAnchor(int modeOpenSec,int modeCloseSec,int &openNY)
{
   openNY=0;
   int bc=ClkBaseFromAnchor(modeCloseSec,17);
   if(bc==CLK_BASE_INVALID) return CLK_BASE_INVALID;
   if(bc==ClkBaseFromAnchor(modeOpenSec,17)) { openNY=17; return bc; }
   if(bc==ClkBaseFromAnchor(modeOpenSec,18)) { openNY=18; return bc; }
   return CLK_BASE_INVALID;
}

// OPEN ANCHOR (tester): base from the weekly-open constant under an assumed feed open hour. Same class of assumption,
// independent of the close. Used when the close geometry does not validate, so a feed whose close is not 17:00 NY
// resolves with a labelled assumption instead of refusing to run.
int ClkBaseFromOpenAnchor(int modeOpenSec,int openNYHour) { return ClkBaseFromAnchor(modeOpenSec,openNYHour); }

// ---- dated schedule: (fromUtc, rule, baseMin) segments --------------------------------------------------------------
// A one-segment schedule reproduces the single model exactly. Segments are ordered by fromUtc and cover all instants:
// the first segment applies to everything before fromUtc[1].
#define CLK_SEG_MAX        64
#define CLK_SEG_MIN_WEEKS  8
int ClkSegIndex(datetime utc,datetime &from[],int n)
{
   if(n<=0) return -1;
   int i=n-1;
   while(i>0 && utc<from[i]) i--;
   return i;
}
datetime ClkUtcToServerSeg(datetime utc,datetime &from[],int &rule[],int &baseMin[],int n)
{
   int i=ClkSegIndex(utc,from,n);
   if(i<0) return 0;
   return ClkUtcToServer(utc,rule[i],baseMin[i]);
}
// Server stamp -> UTC against a schedule. The reading must be self-consistent: the instant it produces has to fall in
// the same segment that produced it, otherwise the next older segment is tried. Deterministic, no state.
datetime ClkServerToUtcSeg(datetime server,datetime &from[],int &rule[],int &baseMin[],int n,datetime lowerBoundUtc,int &conv)
{
   conv=CLK_CONV_EXACT;
   if(n<=0) return 0;
   for(int i=n-1;i>=0;i--)
   {
      int c;
      datetime u=ClkServerToUtc(server,rule[i],baseMin[i],lowerBoundUtc,c);
      if(ClkSegIndex(u,from,n)!=i) continue;
      if(ClkUtcToServerSeg(u,from,rule,baseMin,n)!=server) continue;
      conv=c;
      return u;
   }
   return 0;
}
// Per-range fit: does ONE (rule, base) describe this slice of weeks, proven by ClkInferRule?
// The base comes from the close anchor when that anchor validates, otherwise from the labelled open-hour assumption.
bool ClkFitRange(datetime &opens[],int oStart,int count,datetime &closes[],int openNYHour,
                 int &rule,int &baseMin,int &hits)
{
   if(count<CLK_SEG_MIN_WEEKS) return false;
   datetime o[CLK_MAX_WEEKS]; datetime c[CLK_MAX_WEEKS];
   int nc=(count<=CLK_MAX_WEEKS)?count:CLK_MAX_WEEKS;
   for(int i=0;i<nc;i++) { o[i]=opens[oStart+i]; c[i]=closes[oStart+i]; }
   int margin=0, mo=0, mc=0;
   if(ClkInferRule(o,nc,c,nc,rule,hits,margin,mo,mc)!=1) return false;
   int on=0;
   int b=ClkBaseFromCloseAnchor(mo,mc,on);
   if(b==CLK_BASE_INVALID) b=ClkBaseFromAnchor(mo,openNYHour);
   if(b==CLK_BASE_INVALID) return false;
   baseMin=b;
   return true;
}
// Recursive dated schedule. A range that one (rule, base) explains becomes one segment; otherwise the split that lets
// both halves be proven independently wins. Depth is bounded, so a pathological history returns 0 segments instead of
// inventing many.
int ClkSchedRange(datetime &opens[],int oStart,int count,datetime &closes[],int openNYHour,int depth,
                  datetime &from[],int &rule[],int &baseMin[],int &segWeeks[],int &covered)
{
   int r=0,h=0,b=0;
   if(ClkFitRange(opens,oStart,count,closes,openNYHour,r,b,h))
   {
      int n=ArraySize(from);
      ArrayResize(from,n+1); ArrayResize(rule,n+1); ArrayResize(baseMin,n+1); ArrayResize(segWeeks,n+1);
      from[n]=(n==0) ? 0 : ClkWeekRefUtc(opens[oStart]);
      rule[n]=r; baseMin[n]=b; segWeeks[n]=count;
      covered+=count;
      return n+1;
   }
   if(depth<=0 || count<2*CLK_SEG_MIN_WEEKS) return 0;
   int bestK=0,bestScore=-1;
   for(int k=CLK_SEG_MIN_WEEKS;k<=count-CLK_SEG_MIN_WEEKS;k++)
   {
      int r1=0,h1=0,b1=0,r2=0,h2=0,b2=0;
      if(!ClkFitRange(opens,oStart,k,closes,openNYHour,r1,b1,h1)) continue;
      if(!ClkFitRange(opens,oStart+k,count-k,closes,openNYHour,r2,b2,h2)) continue;
      if(b1==b2 && r1==r2) continue;                        // same clock on both sides: not a change point
      int score=h1+h2-(count-(h1+h2))*4;                    // prefer splits where both halves fit well
      if(score>bestScore) { bestScore=score; bestK=k; }
   }
   if(bestK==0) return 0;
   int a=ClkSchedRange(opens,oStart,bestK,closes,openNYHour,depth-1,from,rule,baseMin,segWeeks,covered);
   if(a<=0) return 0;
   int c2=ClkSchedRange(opens,oStart+bestK,count-bestK,closes,openNYHour,depth-1,from,rule,baseMin,segWeeks,covered);
   if(c2<=a) return 0;
   return c2;
}
// Build a dated schedule from weekly open/close evidence. openNYHour is the assumed feed open hour (17 or 18).
// The RULE and every CHANGE are proven by the same weekly-constant test the single model uses; only the absolute base
// rests on the labelled feed-geometry assumption. covered reports how many weeks the schedule actually explains.
int ClkScheduleFromEvidence(datetime &opens[],int nOpen,datetime &closes[],int nClose,int openNYHour,
                            datetime &from[],int &rule[],int &baseMin[],int &segWeeks[],int &covered)
{
   covered=0;
   ArrayResize(from,0); ArrayResize(rule,0); ArrayResize(baseMin,0); ArrayResize(segWeeks,0);
   if(nOpen<CLK_SEG_MIN_WEEKS) return 0;
   if(nClose<nOpen) nOpen=nClose;                      // opens and closes are produced in parallel
   if(nOpen>CLK_MAX_WEEKS) nOpen=CLK_MAX_WEEKS;
   int n=ClkSchedRange(opens,0,nOpen,closes,openNYHour,3,from,rule,baseMin,segWeeks,covered);
   if(n<=0) return 0;
   if(n>CLK_SEG_MAX) return 0;
   from[0]=0;                                          // the first segment covers the whole earlier history
   return n;
}
// ===== CLK-CORE 1.2 END =====================================================================================

#include "ExecutionRuntime.mqh"
#include "ChartVisuals.mqh"
#include "VisualRecovery.mqh"

//+------------------------------------------------------------------+
//| HISTORICAL NEW YORK CLOCK — VERIFIED WEEKLY REOPEN ANCHOR        |
//|                                                                  |
//| Infer an offset only from an observed Sunday 18:00 NY first M1   |
//| bar. Long midweek holiday/outage gaps are NOT weekly reopening.   |
//| Missing/late reopen evidence stays unknown; signal gating fails   |
//| closed while owned-position management remains independent.      |
//+------------------------------------------------------------------+
const int CLOCK_UNKNOWN = 100000;

datetime g_clockWeekKey = 0;
int      g_clockWeekOff = CLOCK_UNKNOWN;

int OffsetFromReopen(datetime reopen)
{
   int raw    = (int)((long)reopen % 86400) - 18 * 3600;
   int offset = (int)MathRound((double)raw / 3600.0) * 3600;
   while(offset >  14 * 3600) offset -= 86400;
   while(offset < -12 * 3600) offset += 86400;
   return offset;
}

bool IsWeeklyReopen(datetime reopen, int offset)
{
   MqlDateTime ny;
   TimeToStruct(reopen - offset, ny);
   return ny.day_of_week == 0 && ny.hour == 18 && ny.min == 0 && ny.sec == 0;
}




// The US DST rule is owned by CLK-CORE 1.2. The old body approximated the change with fixed dates
// ("summer from March 8 to November 6"), which is wrong for the 2nd Sunday of March when it falls
// later than the 8th and for the 1st Sunday of November when it falls earlier than the 7th: that is
// 4 253 wrong hours across 2007-2035. The standard computes the real 2nd-Sunday-March 07:00 UTC ..
// 1st-Sunday-November 06:00 UTC rule and is verified against 60 IANA transitions 2006-2036.
// Name and every call site are unchanged; the value is 2 (winter) or 3 (summer).
// Server offset in whole hours at this UTC instant, from the resolved standard clock. Was a
// hard-coded 3/2 US-DST table; any broker, any rule, and a dated schedule all work now.
int VBExpectedBrokerUTC(datetime utc)
{
   // Before the adapter resolves (OnInit self-tests, a chart with no history yet) answer with the
   // US rule the strategy was written against; the resolved clock takes over from the first tick.
   if(!ClkOK()) return ClkNyUtcOffset(utc)==-4*3600 ? 3 : 2;
   return (int)(((long)ClkUtcToServer(utc,ClkRule(),ClkBase())-(long)utc)/3600);
}

// Seconds the server clock is ahead of New York at this stamp: the standard adapter owns the
// server -> UTC mapping, so this is the only clock decision left in the EA.
int VBServerNYOffsetSec(datetime stamp)
{
   if(!ClkOK()) return CLOCK_UNKNOWN;
   datetime utc=ClkStampToUtc(stamp);
   if(utc<=0) return CLOCK_UNKNOWN;
   return (int)((long)stamp-(long)ClkUtcToNy(utc));
}

datetime NYTime(datetime serverTime)
{
   int offset = VBServerNYOffsetSec(serverTime);
   if(offset == CLOCK_UNKNOWN) return 0;
   return serverTime - offset;
}

//+------------------------------------------------------------------+
//| BROKER SESSION-END TABLE                                         |
//|                                                                  |
//| US half days do not produce a 16:00 bar, and the tester generates  |
//| no tick once the feed stops, so the flatten has to be driven from  |
//| the feed's own calendar instead of a clock. Each entry is the New  |
//| York minute-of-day of the last bar printed before 16:00 (derived   |
//| from the same M1 history the oracle ran on). Dates absent here     |
//| close normally at 16:00.                                          |
//+------------------------------------------------------------------+
const string SESSION_END_TABLE =
                 "20180115=779;20180219=779;20180528=779;20180703=794;20180704=779;20180903=779;"
                 "20181122=779;20181123=794;20181205=570;20181224=794;20181231=840;20190121=779;"
                 "20190218=779;20190527=779;20190703=794;20190704=779;20190902=779;20191128=779;"
                 "20191129=794;20191224=794;"
                 "20191231=839;20200120=779;20200217=779;20200525=779;20200703=779;20200907=779;"
                 "20201126=779;20201127=794;20201224=794;20201231=839;20210118=779;20210215=779;"
                 "20210402=554;20210531=779;20210705=779;20210906=779;20211125=779;20211126=794;"
                 "20211231=839;20220117=779;20220221=779;20220530=779;20220620=779;20220704=779;"
                 "20220905=779;20221124=779;20221125=794;20230116=779;20230220=779;20230529=779;"
                 "20230619=779;20230703=794;20230704=779;20230904=779;20231123=779;20231124=794;"
                 "20240115=779;20240219=779;20240527=779;20240619=779;20240703=795;20240704=779;"
                 "20240902=779;20241128=780;20241129=794;20241224=794;20250109=570;20250120=779;"
                 "20250217=779;20250526=779;20250619=779;20250703=794;20250704=779;20250901=779;"
                 "20251127=779;20251128=794;20251224=794;20260119=779;20260216=779;20260403=554;"
                 "20260525=779;20260619=779;20260703=779;20260907=779;";

string g_sessionKeys[];
int    g_sessionMins[];

void LoadSessionTable()
{
   string items[];
   int n = StringSplit(SESSION_END_TABLE, ';', items);
   ArrayResize(g_sessionKeys, 0);
   ArrayResize(g_sessionMins, 0);
   for(int i = 0; i < n; i++)
   {
      string item = items[i];
      if(StringLen(item) < 9) continue;
      int eq = StringFind(item, "=");
      if(eq != 8) continue;
      int k = ArraySize(g_sessionKeys);
      ArrayResize(g_sessionKeys, k + 1);
      ArrayResize(g_sessionMins, k + 1);
      g_sessionKeys[k] = StringSubstr(item, 0, 8);
      g_sessionMins[k] = (int)StringToInteger(StringSubstr(item, 9));
   }
}

// New York minute-of-day at which the session is flattened.
// 960 = 16:00 for a normal day.
int SessionEndMinute(datetime nyDay)
{
   MqlDateTime d;
   TimeToStruct(nyDay, d);
   string key = StringFormat("%04d%02d%02d", d.year, d.mon, d.day);
   for(int i = 0; i < ArraySize(g_sessionKeys); i++)
      if(g_sessionKeys[i] == key)
         return g_sessionMins[i];
   return 960;
}

//+------------------------------------------------------------------+
//| STATE                                                            |
//+------------------------------------------------------------------+
datetime g_lastM1Time      = 0;
datetime g_nyDay           = 0;
int      g_sessionEndMin   = 960;
ulong    g_sessionPositionId = 0;
datetime g_ownedSessionEndServer = 0;
double   g_dayStartBalance = 0.0;
// Non-compounding risk anchor. Resolved once in OnInit, never from live equity.
double   g_fixedBalanceBase = 0.0;
string   g_statusText      = "INITIALIZING";

// Opening Drive
bool     g_odCheck1Done    = false;
bool     g_odCheck2Done    = false;
bool     g_odFired         = false;
bool     g_odStoppedOut    = false;
datetime g_odTime          = 0;
double   g_odStop          = 0.0;

// Trend FVG: incremental M15 state, exactly the oracle's series
datetime g_m15Last         = 0;
int      g_m15Index        = -1;      // 0-based index of newest completed bar
double   g_emaFast         = 0.0;
double   g_emaSlow         = 0.0;
double   g_trPrevClose     = 0.0;
double   g_atrSum          = 0.0;
double   g_atr             = 0.0;
double   g_trRing[14];
int      g_trHead          = 0;
int      g_trCount         = 0;

// ring[0] = c3 (newest completed), ring[1] = c2, ring[2] = c1
datetime g_rTime[3];
double   g_rHigh[3];
double   g_rLow[3];
double   g_rAtr[3];

// exit sequencing (blocked_by_open_position rule)
int      g_seenExitSeq     = 0;

// A MERGE whose trim was not confirmed keeps the old stop; the request is
// retried every bar until the server confirms the reduction and the move.
bool     g_mergePending    = false;
double   g_mergePendingStop = 0.0;

// Active parameters resolved from preset
double          actTrendAtrMult;
int             actTrendEmaFast;
int             actTrendEmaSlow;
double          actODStopPct;
bool            actTrendAfterStopout;
ENUM_ATR_METHOD actAtrMethod;
ENUM_ATR_REF    actAtrRef;

// Strategy tick ("1 tick" of the stop rule). Resolved from the instrument so
// the same engine runs on 0.25 futures (ES/NQ), 0.1 gold and 0.1/0.01/0.001
// CFD grids. InpTickSize > 0 pins it explicitly.
double          g_modelTick = 0.25;

void ResolveTickGrid()
{
   g_symTick   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(g_symTick <= 0.0) g_symTick = _Point;
   if(g_symTick <= 0.0) g_symTick = 0.01;
   g_symDigits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(g_symDigits < 0) g_symDigits = 2;

   g_modelTick = (InpTickSize > 0.0) ? InpTickSize : g_symTick;
   if(g_modelTick <= 0.0) g_modelTick = g_symTick;

   PrintFormat("[FVG_DUO] symbol=%s digits=%d grid=%.6f strategyTick=%.6f stopsLevel=%.6f",
               _Symbol, g_symDigits, g_symTick, g_modelTick, MinStopDistance());
}

void ResolvePresets()
{
   actTrendAtrMult      = B3A_TREND_ATR_MULT;
   actTrendEmaFast      = B3A_TREND_EMA_FAST;
   actTrendEmaSlow      = B3A_TREND_EMA_SLOW;
   actODStopPct         = B3A_OD_STOP_PCT;
   actTrendAfterStopout = B3A_TREND_AFTER_STOPOUT;
   actAtrMethod         = B3A_ATR_METHOD;
   actAtrRef            = B3A_ATR_REF;
}

// Risk anchor is captured once. Using live equity here would compound risk.
void ResolveRiskAnchor()
{
   g_fixedBalanceBase = (InpFixedBalance > 0.0)
                        ? InpFixedBalance * AccountCashPerUnit()
                        : AccountInfoDouble(ACCOUNT_BALANCE);
   if(g_fixedBalanceBase <= 0.0) g_fixedBalanceBase = 10000.0;
   g_dashBalanceBase = g_fixedBalanceBase;

   if(InpSizingMode == SIZING_FIXED)              g_dashSizingText = "Fixed lots";
   else if(InpSizingMode == SIZING_PERCENT)       g_dashSizingText = "Risk % of live equity";
   else if(InpSizingMode == SIZING_CASH)          g_dashSizingText = "Fixed cash risk";
   else                                           g_dashSizingText = "Risk % of fixed balance";
}

double RoundTick(double price)
{
   double tick = g_modelTick;
   if(tick <= 0.0) return price;
   return MathFloor(price / tick + 0.5) * tick;
}

//+------------------------------------------------------------------+
//| M15 INDICATOR STATE (running, seeded on the first bar of data)    |
//+------------------------------------------------------------------+
void PushM15(datetime t, double h, double l, double c)
{
   double tr;
   if(g_m15Index < 0) tr = h - l;
   else tr = MathMax(h - l, MathMax(MathAbs(h - g_trPrevClose), MathAbs(l - g_trPrevClose)));

   double aF = 2.0 / (actTrendEmaFast + 1.0);
   double aS = 2.0 / (actTrendEmaSlow + 1.0);
   if(g_m15Index < 0)
   {
      g_emaFast = c;
      g_emaSlow = c;
   }
   else
   {
      g_emaFast = c * aF + g_emaFast * (1.0 - aF);
      g_emaSlow = c * aS + g_emaSlow * (1.0 - aS);
   }

   int idx = g_m15Index + 1;
   double atrVal = 0.0;
   if(actAtrMethod == ATR_METHOD_RMA)
   {
      if(idx < 13)      { g_atrSum += tr; atrVal = 0.0; }
      else if(idx == 13){ g_atrSum += tr; g_atr = g_atrSum / 14.0; atrVal = g_atr; }
      else              { g_atr = (g_atr * 13.0 + tr) / 14.0; atrVal = g_atr; }
   }
   else // SMA of the trailing 14 true ranges
   {
      g_trRing[g_trHead] = tr;
      g_trHead = (g_trHead + 1) % 14;
      if(g_trCount < 14) g_trCount++;
      if(g_trCount == 14)
      {
         double sum = 0.0;
         for(int i = 0; i < 14; i++) sum += g_trRing[i];
         g_atr = sum / 14.0;
      }
      atrVal = (g_trCount == 14) ? g_atr : 0.0;
   }

   g_trPrevClose = c;
   g_m15Index = idx;

   for(int k = 2; k > 0; k--)
   {
      g_rTime[k] = g_rTime[k - 1];
      g_rHigh[k] = g_rHigh[k - 1];
      g_rLow[k]  = g_rLow[k - 1];
      g_rAtr[k]  = g_rAtr[k - 1];
   }
   g_rTime[0] = t;
   g_rHigh[0] = h;
   g_rLow[0]  = l;
   g_rAtr[0]  = atrVal;
}

// Process every M15 bar that completed at or before barTime-1.
void UpdateM15(datetime barTime)
{
   datetime from = (g_m15Last > 0) ? g_m15Last + 1 : barTime - 400 * 86400;
   MqlRates r[];
   ArraySetAsSeries(r, false);
   int n = CopyRates(_Symbol, PERIOD_M15, from, barTime - 1, r);
   if(n <= 0) return;
   for(int i = 0; i < n; i++)
   {
      if(r[i].time <= g_m15Last) continue;
      datetime previousClose = g_m15Last + 900;
      double previousFast = g_emaFast, previousSlow = g_emaSlow;
      PushM15(r[i].time, r[i].high, r[i].low, r[i].close);
      if(g_m15Last > 0 && r[i].time - g_m15Last == 900 &&
         r[i].time >= barTime - 4 * 86400)
         ShowTrendAverages(previousClose, r[i].time + 900, previousFast, g_emaFast,
                            previousSlow, g_emaSlow);
      g_m15Last = r[i].time;
   }
}

//+------------------------------------------------------------------+
//| DAY / SESSION                                                    |
//+------------------------------------------------------------------+
void StartDay(datetime nyDay)
{
   if(g_fvgCandidateName != "")
   {
      ForgetVisualRecord(g_fvgCandidateName);
      ObjectDelete(0, g_fvgCandidateName);
   }
   g_fvgCandidateName = "";
   g_nyDay          = nyDay;
   g_odCheck1Done   = false;
   g_odCheck2Done   = false;
   g_odFired        = false;
   g_odStoppedOut   = false;
   g_odTime         = 0;
   g_mergePending   = false;
   g_mergePendingStop = 0.0;
   g_sessionEndMin  = SessionEndMinute(nyDay);
   g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_statusText     = "PRE-MARKET";
}

// Cache only an entry-date deadline established by the declared NY clock.
// A new signal date or a temporary clock gap must not postpone an open trade.
datetime OwnedSessionEndServer()
{
   if(!ownedActive || ownedPositionId == 0 || ownedEntryTime <= 0) return 0;
   if(g_sessionPositionId == ownedPositionId && g_ownedSessionEndServer > 0)
      return g_ownedSessionEndServer;
   datetime entryNy = NYTime(ownedEntryTime);
   if(entryNy <= 0) return 0;
   datetime day = (datetime)((long)entryNy - ((long)entryNy % 86400));
   g_ownedSessionEndServer = (datetime)((long)day + SessionEndMinute(day) * 60 +
                                       ((long)ownedEntryTime - entryNy));
   g_sessionPositionId = ownedPositionId;
   return g_ownedSessionEndServer;
}

// Passive geometry follows actual accepted position data and booked exits.
void SyncTradeVisuals(datetime barTime)
{
   if(!VisualsAllowed()) return;
   if(g_visualTradePositionId > 0 &&
      (!ownedActive || ownedPositionId != g_visualTradePositionId))
   {
      int i = JournalFind(g_visualTradePositionId);
      if(i >= 0 && j_exitServer[i] > 0 && j_exitPrice[i] > 0.0)
         FinishTradeGeometry(j_exitServer[i], j_exitPrice[i], j_exitReason[i]);
   }
   if(!ownedActive || ownedEntryTime <= 0 || ownedStopPrice <= 0.0) return;
   datetime end = barTime + 60;
   datetime planned = OwnedSessionEndServer();
   if(planned > end) end = planned;
   ShowTradeGeometry(ownedSide, ownedEntryTime, end, ownedEntryPrice,
                      ownedStopPrice, ownedTargetPrice, ownedPositionId, ownedSource);
}

//+------------------------------------------------------------------+
//| OPENING DRIVE                                                    |
//+------------------------------------------------------------------+
bool ODCheck(datetime barTime, int &side, double &entryPx, double &stopPx)
{
   datetime from = barTime - 1800;   // check1: 09:10 / check2: 09:20
   datetime to   = barTime - 60;
   MqlRates r[];
   ArraySetAsSeries(r, false);
   if(CopyRates(_Symbol, PERIOD_M10, from, to, r) != 3) return false;
   if(r[0].time != from || r[1].time != from + 600 || r[2].time != from + 1200) return false;

   double c1High = r[0].high, c1Low = r[0].low;
   double c3High = r[2].high, c3Low = r[2].low;

   bool bull, bear;
   if(InpFvgStrict)
   {
      bull = (c3Low > c1High);
      bear = (c3High < c1Low);
   }
   else
   {
      bull = (c3Low >= c1High);
      bear = (c3High <= c1Low);
   }
   if(!bull && !bear) return false;

   entryPx = iOpen(_Symbol, PERIOD_M1, 0);
   if(bull)
   {
      side   = 1;
      stopPx = RoundTick(entryPx * (1.0 - actODStopPct));
   }
   else
   {
      side   = -1;
      stopPx = RoundTick(entryPx * (1.0 + actODStopPct));
   }
   // C3 close, not C3 open: the box must cover the whole C1..C3 span.
   ShowFvgCandidate("OD", r[0].time, (bull ? c1High : c1Low), r[2].time + 600, (bull ? c3Low : c3High), bull);
   return true;
}

void EvaluateOD(datetime barTime, int tod)
{
   // Duo components remain enabled together; fixed model rule.
   if(tod != 9 * 60 + 40 && tod != 9 * 60 + 50) return;

   if(tod == 9 * 60 + 40)
   {
      if(g_odCheck1Done) return;
      g_odCheck1Done = true;
   }
   else
   {
      if(g_odCheck2Done) return;
      g_odCheck2Done = true;
   }
   if(g_odFired) return;

   int side;
   double entryPx, stopPx;
   if(!ODCheck(barTime, side, entryPx, stopPx)) return;

   g_odFired = true;
   g_odTime  = barTime;
   g_odStop  = stopPx;

   // 3b: flat -> simple OD entry
   if(!ownedActive)
   {
      if(ExecuteEntry(side, entryPx, stopPx, 0.0, "OD"))
      {
         g_statusText = (side > 0) ? "OD LONG ENTERED" : "OD SHORT ENTERED";
         MarkFvgCandidateTraded();
         SyncTradeVisuals(barTime);
      }
      return;
   }

   // An open position here can only be the long-only Trend trade.
   if(ownedSource != "TREND" || ownedSide <= 0) return;

   if(side > 0)
   {
      // 3c: MERGE — both long, fold the trend position into OD rules
      double anchor = (InpMergeAnchor == MERGE_TREND_ENTRY) ? ownedSignalEntry : entryPx;
      double mergeStop = RoundTick(anchor * (1.0 - actODStopPct));

      if(entryPx <= mergeStop)
      {
         // Already through the merged stop at the OD bar open: book the exit
         // at that open and do not open the OD trade.
         JournalUpdate(ownedPositionId, "MERGED", mergeStop, 0.0);
         ExecuteClose("STOP");
         g_mergePending = false;
         g_mergePendingStop = 0.0;
         g_statusText = "MERGED STOP AT OD OPEN";
         return;
      }
      if(ExecuteModify(mergeStop, 0.0, "MERGED"))
      {
         g_mergePending     = false;
         g_mergePendingStop = 0.0;
         g_statusText = "MERGED TO OD RULES";
         MarkFvgCandidateTraded();
      }
      else
      {
         // Trim or stop move unconfirmed: the old stop stays live and the
         // request is retried every bar until the server confirms both.
         g_mergePending     = true;
         g_mergePendingStop = mergeStop;
         g_statusText       = "MERGE PENDING CONFIRMATION";
      }
      return;
   }

   // 3d: FLIP - trend long against an OD short
   ExecuteClose("FLIP");
   if(ExecuteEntry(-1, entryPx, stopPx, 0.0, "OD"))
   {
      MarkFvgCandidateTraded();
      SyncTradeVisuals(barTime);
   }
   g_statusText = "FLIPPED TO OD SHORT";
}

//+------------------------------------------------------------------+
//| TREND FVG                                                        |
//+------------------------------------------------------------------+
void EvaluateTrend(datetime barTime, double barOpen, int tod)
{
   // Duo components remain enabled together; fixed model rule.
   if(g_m15Index < 1000) return;                 // oracle warmup_bars

   // c3 must be the bar that closed exactly at this M1 open
   if(g_rTime[0] + 900 != barTime) return;
   if(g_rTime[0] - g_rTime[1] != 900) return;
   if(g_rTime[1] - g_rTime[2] != 900) return;

   if(tod < 9 * 60 + 30 || tod > 15 * 60 + 30) return;

   // Rule b: bullish FVG, c3.low > c1.high
   if(InpFvgStrict)
   {
      if(g_rLow[0] <= g_rHigh[2]) return;
   }
   else
   {
      if(g_rLow[0] < g_rHigh[2]) return;
   }

   // Rule c: displacement, c2 range >= mult * ATR
   double atr = (actAtrRef == ATR_REF_C1) ? g_rAtr[2] : g_rAtr[1];
   if(atr <= 0.0) return;
   double c2Range = g_rHigh[1] - g_rLow[1];
   if(c2Range < actTrendAtrMult * atr) return;

   // Rule d: trend, EMA fast > EMA slow
   if(g_emaFast <= g_emaSlow) return;

   double stop = g_rLow[2] - g_modelTick;
   if(barOpen <= stop) return;

   // Arbitration gates (oracle run_day)
   if(ownedActive) return;
   if(barTime <= g_lastExitBar) return;
   if(g_odFired && barTime > g_odTime)
   {
      if(!(actTrendAfterStopout && g_odStoppedOut)) return;
   }

   double target = barOpen + InpTrendRR * (barOpen - stop);
   // Display only an eligible trigger candidate; its right bound is C3 open.
   ShowFvgCandidate("TREND", g_rTime[2], g_rHigh[2], g_rTime[0] + 900, g_rLow[0], true);
   if(ExecuteEntry(1, barOpen, stop, target, "TREND"))
   {
      g_statusText = "TREND LONG ENTERED";
      MarkFvgCandidateTraded();
      SyncTradeVisuals(barTime);
   }
}

//+------------------------------------------------------------------+
//| INITIALIZATION                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   { int clockInit=ClkInit(); if(clockInit!=INIT_SUCCEEDED) return clockInit; }
   ClkRefresh(ClkNowServer());   // resolve before any self-test, panel or session read
   ResolvePresets();
   ResolveTickGrid();
   ResolveRiskAnchor();
   LoadSessionTable();
   JournalOpen();
   ReconcileOwnedPosition();
   g_seenExitSeq = g_exitEventSeq;

   PrintFormat("[FVG_DUO] Initialized on %s. Model=Optimal_B3a Mult=%.2f FastEMA=%d SlowEMA=%d ODStop=%.4f Sessions=%d",
               _Symbol, actTrendAtrMult, actTrendEmaFast,
               actTrendEmaSlow, actODStopPct, ArraySize(g_sessionKeys));
   PrintFormat("[FVG_DUO] Sizing=%s RiskPct=%.2f FixedBalance=%.2f RiskCash=%.2f",
               g_dashSizingText, InpRiskPercent, g_fixedBalanceBase,
               g_fixedBalanceBase * InpRiskPercent / 100.0);
   if(VisualsAllowed() || DashboardAllowed())
   {
      ConfigurePanelLayering();
      EventSetTimer(1);
   }
   g_fvgVisualRepair = true;
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(VisualsAllowed()) CaptureVisualRecords();
   JournalCloser();
   // Completed visual tester charts keep their final drawings for inspection.
   if(!MQLInfoInteger(MQL_TESTER) || !MQLInfoInteger(MQL_VISUAL_MODE)) RemoveVisuals();
}

//+------------------------------------------------------------------+
//| ON TICK: act on the open of each new M1 bar                      |
//+------------------------------------------------------------------+
void RefreshFvgDisplay(datetime serverNow)
{
   MaintainFvgVisuals(serverNow);
   if(!DashboardAllowed()) return;
   datetime ny = NYTime(serverNow);
   if(ny <= 0) return;
   int minute = (int)((ny % 86400) / 60);
   string displayStatus = g_statusText;
   if(displayStatus == "PRE-MARKET" && minute >= 570 && minute < SessionEndMinute(ny))
      displayStatus = "WAITING";
   if(!ownedActive && minute >= SessionEndMinute(ny)) displayStatus = "SESSION CLOSED";
   string position = "FLAT";
   if(ownedActive)
      position = StringFormat("%s %s @ %.2f (SL: %.2f)", ownedSource,
                              ownedSide > 0 ? "LONG" : "SHORT", ownedEntryPrice, ownedStopPrice);
   UpdateDashboard(displayStatus, TimeToString(ny, TIME_SECONDS), position,
                    AccountInfoDouble(ACCOUNT_BALANCE) - g_dayStartBalance);
}

void OnTimer()
{
   datetime now = MQLInfoInteger(MQL_TESTER) ? TimeCurrent() : TimeTradeServer();
   if(now <= 0) now = TimeCurrent();
   RefreshFvgDisplay(now); // Display only: no signals, reconciliation, closes or order retries.
}

void OnTick()
{
   ClkRefresh(ClkNowServer());
   datetime m1Time = iTime(_Symbol, PERIOD_M1, 0);
   if(m1Time == 0) return;
   if(m1Time != g_lastM1Time)
   {
      g_lastM1Time = m1Time;
      OnBarOpenM1(m1Time);
   }
   RefreshFvgDisplay(TimeCurrent());
}

void OnBarOpenM1(datetime barTime)
{
   // Broker management precedes signal-clock gates. Keep the existing M1
   // request cadence; a missing tick cannot be turned into a synthetic fill.
   ReconcileOwnedPosition();
   datetime sessionEndServer = OwnedSessionEndServer();
   bool sessionExpired = (sessionEndServer > 0 && barTime >= sessionEndServer);
   string sessionCloseStatus = "";
   if(sessionExpired)
   {
      sessionCloseStatus = ExecuteClose("TIME") ? "SESSION CLOSED" : "TIME CLOSE PENDING";
      g_statusText = sessionCloseStatus;
   }
   SyncTradeVisuals(barTime);

   datetime ny = NYTime(barTime);
   if(ny <= 0) return;

   MqlDateTime dt;
   TimeToStruct(ny, dt);
   datetime nyDay = ny - (dt.hour * 3600 + dt.min * 60 + dt.sec);
   int tod = dt.hour * 60 + dt.min;

   PruneFvgVisuals(ny);
   if(nyDay != g_nyDay) StartDay(nyDay);
   if(sessionExpired) g_statusText = sessionCloseStatus;
   if(VisualsAllowed())
   {
      datetime previous = iTime(_Symbol, PERIOD_M1, 1);
      datetime previousNy = NYTime(previous);
      if(previousNy > 0)
         UpdateObservedSessionVisual(previous, previousNy, SessionEndMinute(previousNy),
                              iHigh(_Symbol, PERIOD_M1, 1), iLow(_Symbol, PERIOD_M1, 1));
   }

   // 2. Consume the broker-exit event already reconciled above.
   if(g_exitEventSeq != g_seenExitSeq)
   {
      g_seenExitSeq = g_exitEventSeq;
      if(g_exitEventSource == "OD" && g_exitEventReason == "STOP")
         g_odStoppedOut = true;
   }

   // 2b. Retry a MERGE the server has not confirmed yet. The trend stop stays
   //     where it is until the trim and the wider stop are both settled.
   if(g_mergePending)
   {
      if(!ownedActive || ownedSource != "TREND")
      {
         g_mergePending     = false;
         g_mergePendingStop = 0.0;
      }
      else if(ExecuteModify(g_mergePendingStop, 0.0, "MERGED"))
      {
         g_mergePending     = false;
         g_mergePendingStop = 0.0;
         g_statusText       = "MERGED TO OD RULES";
         MarkFvgCandidateTraded();
      }
   }

   // 3. Rolling M15 state (every completed 15m bar, all hours)
   if(g_m15Last == 0 || (barTime % 900) == 0)
      UpdateM15(barTime);

   double barOpen = iOpen(_Symbol, PERIOD_M1, 0);

   if(tod < g_sessionEndMin)
   {
      // 4. Opening Drive checks at 09:40 / 09:50 NY
      EvaluateOD(barTime, tod);

      // 5. Trend FVG on completed 15m bars
      if((barTime % 900) == 0)
         EvaluateTrend(barTime, barOpen, tod);
   }

   SyncTradeVisuals(barTime);

   // 6. HUD
   string posText = "FLAT";
   if(ownedActive)
      posText = StringFormat("%s %s @ %.2f (SL: %.2f)",
                             ownedSource, (ownedSide > 0 ? "LONG" : "SHORT"),
                             ownedEntryPrice, ownedStopPrice);
   double todayPnL = AccountInfoDouble(ACCOUNT_BALANCE) - g_dayStartBalance;
   UpdateDashboard(g_statusText, TimeToString(ny, TIME_SECONDS), posText, todayPnL);
}

//+------------------------------------------------------------------+
//| ON TESTER: DETAILED TRADE EXPORT & PARITY HARNESS                |
//+------------------------------------------------------------------+
double OnTester()
{
   JournalFlush();

   if(!HistorySelect(0, TimeCurrent())) return 0;

   FolderCreate("FVG_Duo", FILE_COMMON);
   FolderCreate("FVG_Duo/logs", FILE_COMMON);
   int handle = FileOpen("FVG_Duo/logs/trades_mt5.csv", FILE_COMMON | FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(handle == INVALID_HANDLE)
   {
      Print("[FVG_DUO] Failed to open Common/Files/FVG_Duo/logs/trades_mt5.csv");
      return 0;
   }

   FileWrite(handle, "trade_id", "date", "source", "side", "entry_server", "exit_server", "entry_ny", "exit_ny", "entry_price", "exit_price", "points", "commission", "gross_usd", "net_usd", "comment");

   int totalDeals = HistoryDealsTotal();
   int tradeCount = 0;
   double totalNet = 0.0;

   for(int i = 0; i < totalDeals; i++)
   {
      ulong exitTicket = HistoryDealGetTicket(i);
      if(exitTicket <= 0) continue;
      if(HistoryDealGetInteger(exitTicket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
      if(HistoryDealGetInteger(exitTicket, DEAL_MAGIC) != (long)InpMagic) continue;

      ulong posId = (ulong)HistoryDealGetInteger(exitTicket, DEAL_POSITION_ID);

      ulong entryTicket = 0;
      for(int j = 0; j < i; j++)
      {
         ulong dtick = HistoryDealGetTicket(j);
         if(HistoryDealGetInteger(dtick, DEAL_POSITION_ID) == (long)posId &&
            HistoryDealGetInteger(dtick, DEAL_ENTRY) == DEAL_ENTRY_IN)
         {
            entryTicket = dtick;
            break;
         }
      }

      if(entryTicket == 0) continue;

      tradeCount++;
      long dealType = HistoryDealGetInteger(entryTicket, DEAL_TYPE);
      string side = (dealType == DEAL_TYPE_BUY) ? "LONG" : "SHORT";

      datetime entryServer = (datetime)HistoryDealGetInteger(entryTicket, DEAL_TIME);
      datetime exitServer  = (datetime)HistoryDealGetInteger(exitTicket, DEAL_TIME);
      datetime entryNY     = NYTime(entryServer);
      datetime exitNY      = NYTime(exitServer);

      double entryPrice = HistoryDealGetDouble(entryTicket, DEAL_PRICE);
      double exitPrice  = HistoryDealGetDouble(exitTicket, DEAL_PRICE);

      double points = (side == "LONG") ? (exitPrice - entryPrice) : (entryPrice - exitPrice);
      double profit = HistoryDealGetDouble(exitTicket, DEAL_PROFIT);
      double comm   = HistoryDealGetDouble(entryTicket, DEAL_COMMISSION) + HistoryDealGetDouble(exitTicket, DEAL_COMMISSION);
      double swap   = HistoryDealGetDouble(exitTicket, DEAL_SWAP);
      double net    = profit + comm + swap;
      totalNet += net;

      string comment = HistoryDealGetString(exitTicket, DEAL_COMMENT);
      string entryComment = HistoryDealGetString(entryTicket, DEAL_COMMENT);
      string src = "OD";
      if(StringFind(entryComment, "TREND") >= 0) src = "TREND";
      if(StringFind(entryComment, "MERGED") >= 0 || StringFind(comment, "MERGED") >= 0) src = "MERGED";

      MqlDateTime dt;
      TimeToStruct(entryNY, dt);
      string dateStr = StringFormat("%04d-%02d-%02d", dt.year, dt.mon, dt.day);

      FileWrite(handle, tradeCount, dateStr, src, side,
                TimeToString(entryServer, TIME_DATE|TIME_SECONDS), TimeToString(exitServer, TIME_DATE|TIME_SECONDS),
                TimeToString(entryNY, TIME_DATE|TIME_SECONDS), TimeToString(exitNY, TIME_DATE|TIME_SECONDS),
                DoubleToString(entryPrice, 2), DoubleToString(exitPrice, 2),
                DoubleToString(points, 2), DoubleToString(comm, 2), DoubleToString(profit, 2), DoubleToString(net, 2),
                comment);
   }

   FileClose(handle);
   PrintFormat("[FVG_DUO] TESTER_COMPLETE: exported %d trades, Net P&L: %.2f USD", tradeCount, totalNet);
   return totalNet;
}
