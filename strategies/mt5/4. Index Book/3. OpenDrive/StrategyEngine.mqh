//+------------------------------------------------------------------+
//|                                               StrategyEngine.mqh |
//|                       OpenDrive — Nasdaq 9:30 AM Cash Open Drive |
//+------------------------------------------------------------------+
#ifndef OPENDRIVE_STRATEGY_ENGINE
#define OPENDRIVE_STRATEGY_ENGINE

#property copyright "OpenDrive"
#property version   "5.00"
#property strict

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

const int CLOCK_UNKNOWN=-999999;   // sentinel: the clock cannot answer for this stamp

//+------------------------------------------------------------------+
//| Strategy Enums                                                   |
//+------------------------------------------------------------------+
enum ENUM_RISK_MODE
{
   RISK_DYNAMIC_VOLATILITY = 0, // Dynamic Strength Scaling (Prop Firms: 0.33% / 0.50% / 1.00%)
   RISK_STATIC_FIXED       = 1  // Static Fixed Risk (Live Accounts: Fixed % per trade)
};

enum ENUM_ATR_MODE
{
   ATR_MT5    = 0, // MT5 Standard iATR (SMA)
   ATR_WILDER = 1  // Wilder RMA ATR (TradingView / Research Standard)
};

enum ENUM_NEWS_IMPACT
{
   NEWS_DISABLED   = 0, // Off
   NEWS_RED_ONLY   = 1, // Red folder only (High impact)
   NEWS_RED_YELLOW = 2, // Red and Orange/Medium folders
   NEWS_ALL        = 3  // All news folders
};

enum ENUM_NEWS_WINDOW
{
   NEWS_WINDOW_5  = 5,  // 5 min total: 2m30s before / after
   NEWS_WINDOW_10 = 10, // 10 min total: 5m before / after
   NEWS_WINDOW_14 = 14, // 14 min total: 7m before / after
   NEWS_WINDOW_20 = 20  // 20 min total: 10m before / after
};

//+------------------------------------------------------------------+
//| Input Parameters: Standard Numbered Sectioning                   |
//+------------------------------------------------------------------+

input group "==========  1 - Trading  =========="
input bool             EnableTrading       = true;  // Enable new entries (open trades stay protected when off)
input bool             AllowLong           = true;  // Allow Long entries
input bool             AllowShort          = true;  // Allow Short entries
input bool             BlockOpposingExposure = true; // Block opposing same-symbol / equity-index exposure

input group " "
input group "==========  2 - Risk & Sizing  =========="
input ENUM_RISK_MODE   RiskMode            = RISK_DYNAMIC_VOLATILITY; // Sizing Mode (Dynamic for Prop, Static for Live)
input double           RiskPercent         = 1.0;   // Maximum Risk % per trade (0.5% - 1.0%)
input double           RiskMoney           = 0.0;   // Fixed Dollar Risk per trade (0 = use RiskPercent)
input bool             UseFixedLots        = false; // Use fixed contracts instead of % risk
input double           FixedLots           = 1.0;   // Contract quantity when fixed sizing enabled
input bool             AllowMinLotFallback = true;  // Execute broker min lot if calculated lot is below minimum
input double           DailyLossLimitPct   = 0.0;   // Daily loss lock % of day-start balance (0 = off)

input group "  "
input group "==========  3 - Signal Core  =========="
input int              EmaPeriod           = 12;    // Opening Signal EMA (M5 close)
input int              EntryHourNY         = 9;     // Cash open hour (New York)
input int              EntryMinNY          = 30;    // Cash open minute (New York)

input group "   "
input group "==========  4 - Stops & Trailing  =========="
input int              AtrPeriod           = 14;    // Volatility ATR period
input ENUM_ATR_MODE    AtrMode             = ATR_WILDER; // ATR Calculation Mode
input double           StopATR             = 4.0;   // Hard stop distance (x ATR from fill)
input double           ActivateATR         = 0.25;  // Profit confirmation before trail (x ATR)
input double           TrailATR            = 3.0;   // Chandelier trailing distance (x ATR behind extreme)
input bool             FlatAtExit          = true;  // Close flat before session close (no overnight gap)
input int              ExitHourNY          = 16;    // Session exit hour (16:00 NY Cash Close)
input int              ExitMinNY           = 0;     // Session exit minute

input group "    "
input group "==========  5 - Costs & Execution  =========="
input int              BrokerServerGMTOffset = 99;    // Server GMT offset in Winter (99 = Auto-detect from chart)
input int              MaxSpreadPoints     = 0;     // Max allowed spread in points (0 = off)
input int              SlippagePoints      = 3;     // Slippage allowance in points
input double           CommissionPerLot    = 7.0;   // Fallback round-trip commission per lot ($)
input ulong            MagicNumber         = 93093001; // EA Magic Number
input string           TradeComment        = "OpenDrive"; // Trade Comment

input group "     "
input group "==========  6 - Display & Visuals  =========="
input bool             ShowVisuals         = true;  // Draw chart lines & markers
input bool             ShowPanel           = true;  // Display floating HUD panel
input bool             ShowExtras          = false; // Diagnostic signal boxes & arrows
input bool             WriteLog            = true;  // Print journal decision log

input group "      "
input group "==========  7 - News Guard  =========="
input bool             InpNewsCacheInTester   = false; // Use the last saved calendar snapshot in the tester (fixed input, deterministic)
input ENUM_NEWS_IMPACT News_Impact             = NEWS_RED_ONLY; // News impact filter (USD)
input ENUM_NEWS_WINDOW News_Window             = NEWS_WINDOW_10; // Blackout window around release
input bool             News_Cost_Covered_BE    = true;  // Move stop to cost-covered BE if in profit before news
input bool             News_Flatten_Before     = false; // Close position before news (strict prop rule)
input bool             News_Block_Modification = true;  // Block trade modifications during blackout (prop rule)

//+------------------------------------------------------------------+
//| New York Time & Daylight Saving Time Conversion                  |
//+------------------------------------------------------------------+
datetime MakeDT(int year, int mon, int day, int hour, int minute, int sec)
{
   MqlDateTime dt; ZeroMemory(dt);
   dt.year = year; dt.mon = mon; dt.day = day; dt.hour = hour; dt.min = minute; dt.sec = sec;
   return StructToTime(dt);
}

int NthSundayOfMonth(int year, int month, int nth)
{
   MqlDateTime dt; ZeroMemory(dt);
   dt.year = year; dt.mon = month; dt.day = 1;
   datetime firstDay = StructToTime(dt);
   TimeToStruct(firstDay, dt);
   int firstDow = dt.day_of_week;
   int firstSunday = 1 + ((7 - firstDow) % 7);
   return firstSunday + (nth - 1) * 7;
}

int NYUTCOffsetSeconds(datetime utcTime)
{
   MqlDateTime utc; TimeToStruct(utcTime, utc);
   int year = utc.year;
   int marchSunday    = NthSundayOfMonth(year, 3, 2);
   int novemberSunday = NthSundayOfMonth(year, 11, 1);

   MqlDateTime startUtc; ZeroMemory(startUtc);
   startUtc.year = year; startUtc.mon = 3;  startUtc.day = marchSunday;    startUtc.hour = 7;
   MqlDateTime endUtc;   ZeroMemory(endUtc);
   endUtc.year = year;   endUtc.mon = 11; endUtc.day = novemberSunday;   endUtc.hour = 6;

   datetime dstStart = StructToTime(startUtc);
   datetime dstEnd   = StructToTime(endUtc);
   return (utcTime >= dstStart && utcTime < dstEnd) ? -4 * 3600 : -5 * 3600;
}

int TesterAnchorOffsetSec(datetime atServer)
{
   if(atServer == 0) atServer = TimeCurrent();
   static datetime cachedWeek[6];
   static int cachedOffset[6];
   static int nextCache = 0;

   for(int c = 0; c < 6; c++)
   {
      if(cachedWeek[c] > 0 && atServer >= cachedWeek[c] && atServer < cachedWeek[c] + 7 * 86400)
         return cachedOffset[c];
   }

   // 1. Manual User Broker Offset Override (if supplied)
   if(BrokerServerGMTOffset != 99)
   {
      int srvUTC = BrokerServerGMTOffset * 3600;
      int nyOff  = NYUTCOffsetSeconds(atServer - srvUTC);
      int bDst   = (nyOff == -4 * 3600) ? 3600 : 0;
      return (srvUTC + bDst) - nyOff;
   }

   // 2. Universal Friday Close Market Anchor (Broker-Agnostic)
   // US Index and Equity markets close globally on Friday at 17:00 New York.
   int first = iBarShift(_Symbol, PERIOD_H1, atServer, false);
   if(first < 0 || iTime(_Symbol, PERIOD_H1, first) <= 0) return -999999;

   datetime newer = 0;
   for(int i = first; i < first + 500; i++)
   {
      datetime t = iTime(_Symbol, PERIOD_H1, i);
      if(t <= 0) break;
      if(newer > 0 && (newer - t) >= 40 * 3600)
      {
         datetime weekOpenServer  = newer;
         datetime weekCloseServer = t;
         MqlDateTime co; TimeToStruct(weekCloseServer, co);
         MqlDateTime op; TimeToStruct(weekOpenServer, op);
         if(co.day_of_week != 5 || (op.day_of_week != 0 && op.day_of_week != 1)) { newer = t; continue; }

         // The last H1 bar of Friday closes at weekCloseServer + 3600.
         datetime fridayCloseServer = weekCloseServer + 3600;
         int srvCloseSecDay = (int)((long)fridayCloseServer % 86400);
         int nyCloseSecDay  = 17 * 3600; // 17:00 NY Friday market close
         int diff = srvCloseSecDay - nyCloseSecDay;
         while(diff >  12 * 3600) diff -= 86400;
         while(diff < -12 * 3600) diff += 86400;
         int off = (int)(MathRound((double)diff / 3600.0) * 3600.0);

         if(off < -5 * 3600 || off > 12 * 3600) { newer = t; continue; }

         cachedWeek[nextCache]   = weekOpenServer;
         cachedOffset[nextCache] = off;
         nextCache = (nextCache + 1) % 6;
         return off;
      }
      newer = t;
   }
   return -999999;
}

// Seconds the server clock is ahead of New York at this stamp: the standard adapter owns the
// server -> UTC mapping, so this is the only clock decision left in the EA.
int GetServerNYOffsetSec(datetime stamp)
{
   if(!ClkOK()) return CLOCK_UNKNOWN;
   datetime utc=ClkStampToUtc(stamp);
   if(utc<=0) return CLOCK_UNKNOWN;
   return (int)((long)stamp-(long)ClkUtcToNy(utc));
}

datetime ConvertServerToNY(datetime serverTime)
{
   return serverTime - GetServerNYOffsetSec(serverTime);
}

datetime ConvertNYLocalToServer(int year, int mon, int day, int hour, int minute, int sec)
{
   datetime nyWall = MakeDT(year, mon, day, hour, minute, sec);
   datetime candidate = nyWall + GetServerNYOffsetSec(TimeCurrent());
   return nyWall + GetServerNYOffsetSec(candidate);
}

long BuildDayKey(datetime dt)
{
   MqlDateTime d; TimeToStruct(dt, d);
   return (long)d.year * 10000 + d.mon * 100 + d.day;
}

// Include Execution and Visual modules
#include "ExecutionRuntime.mqh"
#include "ChartVisuals.mqh"

// Indicators & Internal Engine Handles
int      hEma        = INVALID_HANDLE;
int      hAtr        = INVALID_HANDLE;
double   g_atrWilder = 0.0;
double   g_currentATR = 0.0;
datetime g_atrTime   = 0;
datetime g_lastBarTime = 0;

//+------------------------------------------------------------------+
//| Wilder RMA ATR Seeding & Updating                                |
//+------------------------------------------------------------------+
bool SeedWilderATR(int seedBars = 3000)
{
   MqlRates rates[]; ArraySetAsSeries(rates, false);
   int copied = CopyRates(_Symbol, PERIOD_M5, 1, seedBars, rates);
   if(copied < AtrPeriod + 5) return false;

   double sum = 0.0;
   for(int i = 1; i <= AtrPeriod; i++)
   {
      sum += MathMax(rates[i].high - rates[i].low, MathMax(MathAbs(rates[i].high - rates[i-1].close), MathAbs(rates[i].low - rates[i-1].close)));
   }
   double a = sum / AtrPeriod;
   for(int i = AtrPeriod + 1; i < copied; i++)
   {
      double tr = MathMax(rates[i].high - rates[i].low, MathMax(MathAbs(rates[i].high - rates[i-1].close), MathAbs(rates[i].low - rates[i-1].close)));
      a = (a * (AtrPeriod - 1) + tr) / AtrPeriod;
   }
   g_atrWilder = a;
   g_currentATR = a;
   g_atrTime   = rates[copied - 1].time;
   return true;
}

bool UpdateWilderATR(const MqlRates &b1, const MqlRates &b2)
{
   if(g_atrTime == b2.time)
   {
      double tr = MathMax(b1.high - b1.low, MathMax(MathAbs(b1.high - b2.close), MathAbs(b1.low - b2.close)));
      g_atrWilder = (g_atrWilder * (AtrPeriod - 1) + tr) / AtrPeriod;
      g_atrTime = b1.time;
      return true;
   }
   return SeedWilderATR();
}

//+------------------------------------------------------------------+
//| Expert Initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   { int clockInit=ClkInit(); if(clockInit!=INIT_SUCCEEDED) return clockInit; }
   ClkRefresh(ClkNowServer());   // resolve before any self-test, panel or session read
   if(!ODLoadState())
   {g_stateFault=true;Print("OpenDrive recovery: ",g_recoveryReason);return INIT_FAILED;}
   // OpenDrive calculations and signals run strictly on M5, but the EA can be attached to ANY timeframe chart (M1, M5, H1, H4, etc.)
   PrintFormat("OpenDrive: Initialized on %s (Chart TF: %s). Core calculations & execution strictly fitted to M5.", _Symbol, EnumToString(_Period));

   hEma = iMA(_Symbol, PERIOD_M5, EmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   hAtr = iATR(_Symbol, PERIOD_M5, AtrPeriod);
   if(hEma == INVALID_HANDLE || hAtr == INVALID_HANDLE)
   {
      Print("OpenDrive: Failed to create indicator handles.");
      return INIT_FAILED;
   }

   if(!SeedWilderATR())
   {
      Print("OpenDrive: ATR history pending; existing broker protection retained.");
   }

   g_lastBarTime = iTime(_Symbol, PERIOD_M5, 0);
   RestoreExecutionState();

   if(!MQLInfoInteger(MQL_TESTER))
   {
      if(News_Impact != NEWS_DISABLED)
      {
         PrintFormat("OpenDrive: News Guard ACTIVE [Impact: %d | Window: %d min | BE: %s | Flatten: %s | BlockMod: %s]",
                     News_Impact, News_Window, News_Cost_Covered_BE ? "ON" : "OFF",
                     News_Flatten_Before ? "ON" : "OFF", News_Block_Modification ? "ON" : "OFF");
         PrintFormat("OpenDrive: Please ensure '%s' is added to MT5 Allowed WebRequest URLs (Tools -> Options -> Expert Advisors).", NF_URL);
         ODNewsRefresh(TimeCurrent());
      }
      else
      {
         Print("OpenDrive: News Guard is DISABLED.");
      }
   }
   else if(News_Impact != NEWS_DISABLED)
   {
      Print("OpenDrive: Tester news guard omitted: ForexFactory has no historical WebRequest feed.");
   }

   if(ShowVisuals && (!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE)))
   {
      // 1. Attach EMA line to main price chart window (self-dependent visualization)
      if(hEma != INVALID_HANDLE)
      {
         ChartIndicatorAdd(0, 0, hEma);
      }
      // 2. Attach ATR indicator to a subwindow
      if(hAtr != INVALID_HANDLE)
      {
         int totalWindows = (int)ChartGetInteger(0, CHART_WINDOWS_TOTAL);
         ChartIndicatorAdd(0, totalWindows, hAtr);
      }
   }

   if(ShowPanel && (!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE)))
   {
      g_origForeground   = ChartGetInteger(0, CHART_FOREGROUND);
      g_origObjectEvents = ChartGetInteger(0, CHART_EVENT_OBJECT_CREATE);
      ChartSetInteger(0, CHART_FOREGROUND, false);
      ChartSetInteger(0, CHART_EVENT_OBJECT_CREATE, true);
      g_chartConfigured  = true;

      RenderHUDShell();
      UpdateHUD(TimeCurrent(), ConvertServerToNY(TimeCurrent()), 0.0, g_currentATR);
   }

   EventSetTimer(1); // reconciliation must also run with the panel disabled
   ChartRedraw(0);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert Deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   if(!g_stateFault && g_stateLease!=INVALID_HANDLE) ODSaveState();
   if(g_stateLease!=INVALID_HANDLE) {FileClose(g_stateLease);g_stateLease=INVALID_HANDLE;}
   CleanupVisuals();

   // Clean up attached indicators from chart
   int totalWindows = (int)ChartGetInteger(0, CHART_WINDOWS_TOTAL);
   for(int w = totalWindows - 1; w >= 0; w--)
   {
      int totalIndicators = ChartIndicatorsTotal(0, w);
      for(int i = totalIndicators - 1; i >= 0; i--)
      {
         string name = ChartIndicatorName(0, w, i);
         if(StringFind(name, "Moving Average") >= 0 || StringFind(name, "EMA") >= 0 || 
            StringFind(name, "Average True Range") >= 0 || StringFind(name, "ATR") >= 0)
         {
            ChartIndicatorDelete(0, w, name);
         }
      }
   }

   if(hEma != INVALID_HANDLE) IndicatorRelease(hEma);
   if(hAtr != INVALID_HANDLE) IndicatorRelease(hAtr);

   if(WriteLog)
   {
      PrintFormat("OpenDrive Deinit: Lifetime Trades -> Long: %d | Short: %d", g_dayBuyCount, g_daySellCount);
   }
}

//+------------------------------------------------------------------+
//| Timer Event (Live HUD Clock & Panel Restack)                     |
//+------------------------------------------------------------------+
void OnTimer()
{
   ODReconcile();
   ODProtectPosition();
   if(g_atrTime==0) SeedWilderATR();
   if(g_panelRestack)
   {
      g_panelRestack = false;
      ObjectsDeleteAll(0, ODPFX);
      RenderHUDShell();
   }

   datetime nowServer = TimeCurrent();
   datetime nowNY     = ConvertServerToNY(nowServer);

   // Evaluate News Guard in timer
   ODNewsGuard(nowServer);

   double emaVals[1];
   double liveEMA = (CopyBuffer(hEma, 0, 0, 1, emaVals) > 0) ? emaVals[0] : 0.0;

   UpdateHUD(nowServer, nowNY, liveEMA, g_currentATR);
}

//+------------------------------------------------------------------+
//| Chart Event (Handle HUD Button Click)                            |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CREATE && ShowPanel && StringFind(sparam, ODPFX) != 0)
   {
      g_panelRestack = true;
      return;
   }

   if(id == CHARTEVENT_OBJECT_CLICK && sparam == ODPFX + "BTN")
   {
      ObjectSetInteger(0, ODPFX + "BTN", OBJPROP_STATE, false);
      g_panelCollapsed = !g_panelCollapsed;
      RenderHUDShell();
      UpdateHUD(TimeCurrent(), ConvertServerToNY(TimeCurrent()), 0.0, g_currentATR);
      ChartRedraw(0);
   }
}

//+------------------------------------------------------------------+
//| Tick Event                                                       |
//+------------------------------------------------------------------+
void OnTick()
{
   ODReconcile();
   ODProtectPosition();
   datetime nowServer = TimeCurrent();
   CheckDailyGuard(nowServer);

   // News Guard protection check on every tick
   ODNewsGuard(nowServer);

   datetime bar0Time = iTime(_Symbol, PERIOD_M5, 0);
   if(bar0Time != g_lastBarTime)
   {
      g_lastBarTime = bar0Time;
      OnNewBar(nowServer);
   }
}

//+------------------------------------------------------------------+
//| New M5 Bar Event (Signal Check & Trailing Stop Updates)          |
//+------------------------------------------------------------------+
void OnNewBar(datetime nowServer)
{
   MqlRates rates[]; ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, PERIOD_M5, 0, 4, rates) < 4) return; // rates[0]=forming, rates[1]=last closed

   // Update ATR
   if(!UpdateWilderATR(rates[1], rates[2])) return;
   if(AtrMode == ATR_MT5)
   {
      double atrBuf[1];
      if(CopyBuffer(hAtr, 0, 1, 1, atrBuf) > 0 && atrBuf[0] > 0.0)
         g_currentATR = atrBuf[0];
   }
   else
   {
      g_currentATR = g_atrWilder;
   }

   // Fetch last closed EMA
   double emaBuf[2];
   if(CopyBuffer(hEma, 0, 1, 2, emaBuf) < 2) return;
   double closedEMA = emaBuf[1];

   datetime nyTimeBar0 = ConvertServerToNY(rates[0].time);
   datetime nyTimeBar1 = ConvertServerToNY(rates[1].time);
   MqlDateTime dt0, dt1;
   TimeToStruct(nyTimeBar0, dt0);
   TimeToStruct(nyTimeBar1, dt1);

   long dayKey1 = BuildDayKey(nyTimeBar1);
   bool pastExit = (dt0.hour > ExitHourNY) || (dt0.hour == ExitHourNY && dt0.min >= ExitMinNY);

   // 1. Session Lines Drawing
   if(ShowVisuals && (!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE)))
   {
      datetime sEntry = ConvertNYLocalToServer(dt0.year, dt0.mon, dt0.day, EntryHourNY, EntryMinNY, 0);
      DrawSessionLine("OD_LINE_OPEN_" + IntegerToString(dayKey1), sEntry, clrOrange, "09:30 NY Cash Open Drive");

      if(FlatAtExit)
      {
         datetime sExit = ConvertNYLocalToServer(dt0.year, dt0.mon, dt0.day, ExitHourNY, ExitMinNY, 0);
         DrawSessionLine("OD_LINE_EXIT_" + IntegerToString(dayKey1), sExit, clrSilver, "16:00 NY Cash Close Flat Exit");
      }
      PruneVisualObjects("OD_LINE_", 20);
      PruneVisualObjects("OD_SIG_",  30);
      PruneVisualObjects("OD_EXEC_", 30);
   }

   // 2. Active Position Management (Chandelier Trail & 16:00 Flat Exit)
   ManagePosition(rates[1], g_currentATR, pastExit);

   // 3. New Entry Signal Evaluation (At 09:35 NY open, evaluating 09:30 candle)
   bool is0930Candle = (dt1.hour == EntryHourNY && dt1.min == EntryMinNY);
   bool isWeekday    = (dt1.day_of_week >= 1 && dt1.day_of_week <= 5);

   if(is0930Candle && isWeekday && dayKey1 != g_evaluatedDayKey)
   {
      g_evaluatedDayKey = dayKey1;
      if(!ODSaveState() || !g_recoveryReady || g_entryPending || g_closePending) return;

      // Ensure no position is currently open before entering
      ulong tk = 0;
      ENUM_POSITION_TYPE pType;
      double sl = 0.0;
      if(OwnPosition(tk, pType, sl))
      {
         g_lastStatusText = "Position already open";
         return;
      }

      if(!EnableTrading)
      {
         g_lastStatusText = "Trading disabled by input";
         return;
      }

      // Check News Blackout Window Guard
      if(g_newsBlocked)
      {
         g_lastStatusText = "Blocked by News";
         if(WriteLog) PrintFormat("OpenDrive: 09:35 entry skipped due to active news blackout window (%s).", g_activeNewsTitle);
         return;
      }

      // Signal Direction: Close vs EMA12
      int signalDir = 0;
      if(rates[1].close > closedEMA)
         signalDir = 1;
      else if(rates[1].close < closedEMA)
         signalDir = -1;

      if(signalDir == 0)
      {
         g_lastStatusText = "Close == EMA (Tie)";
         return;
      }

      if((signalDir == 1 && !AllowLong) || (signalDir == -1 && !AllowShort))
      {
         g_lastStatusText = (signalDir == 1) ? "Longs blocked" : "Shorts blocked";
         return;
      }

      // Signal Conviction Distance in ATR
      double distATR = (g_currentATR > 0.0) ? (MathAbs(rates[1].close - closedEMA) / g_currentATR) : 0.0;

      // Visual annotations
      string sigInfo = StringFormat("%s C=%.2f EMA=%.2f Dist=%.2f ATR",
                                    signalDir == 1 ? "LONG" : "SHORT",
                                    rates[1].close,
                                    closedEMA,
                                    distATR);
      DrawSignalCandleBox(rates[1], signalDir, sigInfo);

      // Execute Trade
      bool executed = ExecuteEntry(signalDir, distATR, g_currentATR);
      if(executed)
      {
         DrawExecutionMarker(signalDir, rates[0].time, (signalDir == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID), sigInfo);
         g_lastStatusText = (signalDir == 1) ? "Traded LONG" : "Traded SHORT";
      }
      else
      {
         g_lastStatusText = "Entry rejected";
      }
   }

   UpdateHUD(nowServer, nyTimeBar0, closedEMA, g_currentATR);
}

//+------------------------------------------------------------------+
//| Tester Optimization Criterion                                    |
//+------------------------------------------------------------------+
double OnTester()
{
   double trades = TesterStatistics(STAT_TRADES);
   double dd     = TesterStatistics(STAT_EQUITY_DD);
   double profit = TesterStatistics(STAT_PROFIT);

   if(trades < 50 || dd <= 0.0) return 0.0;
   return (profit / dd) * MathSqrt(trades / 100.0);
}

#endif // OPENDRIVE_STRATEGY_ENGINE
