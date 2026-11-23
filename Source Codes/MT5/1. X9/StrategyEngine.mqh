//+------------------------------------------------------------------+
//|                                               StrategyEngine.mqh |
//|        Copyright 2026-2027, Osamwonyi Eric (@You_FoundEric)      |
//|                                      https://x.com/You_FoundEric |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026-2027, Osamwonyi Eric (@You_FoundEric)"
#property link      "https://x.com/You_FoundEric"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\PositionInfo.mqh>

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

extern CTrade         trade;
extern COrderInfo     ordinfo;
extern CPositionInfo  posinfo;

bool CanPlaceNewX9Entries();
bool IsX9NewsManagementFrozen();
void X9NoteOrderDeleted(ulong ticket);
bool X9RestoreCancelledPendingOrders();

//====================================================================
struct StrategyPreset {
   ENUM_TIMEFRAMES fractalTf;
   ENUM_TIMEFRAMES rescanTf;
   int             fractalRight;
   int             fractalLeft;
   int             fractalMaxSearch;
   int             maxPending;
   int             pendExpiryHrs;
   ENUM_TIMEFRAMES exitScanTf;
   int             maxPositions;
   int             magicOffset;
   double          fractalMinDistPct;
   double          pendDedupDist;
   double          buyEntryPct;
   double          sellEntryPct;
   double          slPct;
   double          tpPct;
   double          trailPct;
   double          trailMinProfitPct;
   double          trailMaxSLPct;
   double          salvageTriggerPct;
   double          salvageExitPct;
   double          beTriggerPct;
   double          beLockPct;
   double          riskWeight;
};

StrategyPreset StrategyPresets[9] = {
   // Strategy 1
   {
      PERIOD_D1, PERIOD_M15, 3, 25, 100, 5, 35, PERIOD_M1, 5, 1,
      0.02, 30.0, -0.14, -0.14, 3.00, 0.75, 0.90, 0.90, 2.50, 0.80, 0.35, 0.45, 0.06, 0.60
   },
   // Strategy 2
   {
      PERIOD_D1, PERIOD_M15, 3, 15, 200, 1, 500, PERIOD_M1, 10, 2,
      0.28, 500.0, -0.085, -0.085, 0.50, 2.00, 0.25, 0.70, 2.50, 0.80, 0.20, 0.25, 0.05, 0.3333
   },
   // Strategy 3
   {
      PERIOD_D1, PERIOD_H1, 2, 7, 20, 1, 400, PERIOD_M1, 10, 3,
      0.125, 1000.0, -0.065, -0.065, 0.30, 1.65, 0.25, 0.20, 2.50, 0.50, 1.00, 0.20, 0.00, 0.1714
   },
   // Strategy 4
   {
      PERIOD_H4, PERIOD_M15, 8, 12, 100, 2, 200, PERIOD_M5, 10, 4,
      0.66, 130.0, -0.025, -0.0625, 0.44, 3.10, 0.81, 0.91, 1.25, 0.90, 0.125, 0.33, 0.125, 0.1346
   },
   // Strategy 5
   {
      PERIOD_H1, PERIOD_M15, 19, 30, 100, 3, 30, PERIOD_M1, 10, 5,
      0.05, 50.0, -0.045, -0.045, 2.00, 0.35, 0.20, 0.15, 1.90, 0.70, 0.10, 0.10, 0.05, 0.48182
   },
   // Strategy 6
   {
      PERIOD_H1, PERIOD_M5, 25, 25, 150, 5, 20, PERIOD_M1, 5, 6,
      0.05, 50.0, -0.060, -0.060, 4.20, 0.33, 0.20, 0.50, 2.10, 0.80, 0.15, 0.15, 0.0333, 0.7214
   },
   // Strategy 7
   {
      PERIOD_H1, PERIOD_M5, 23, 25, 150, 5, 60, PERIOD_M1, 5, 7,
      0.005, 90.0, -0.055, -0.055, 0.87, 0.56, 0.175, 0.35, 1.90, 1.10, 0.15, 0.13, 0.01, 0.20
   },
   // Strategy 8
   {
      PERIOD_H1, PERIOD_M15, 20, 25, 250, 5, 55, PERIOD_M1, 10, 8,
      0.03, 5.0, -0.060, -0.060, 0.68, 0.43, 0.45, 0.23, 1.40, 0.70, 0.10, 0.10, 0.00, 0.14615
   },
   // Strategy 9
   {
      PERIOD_H1, PERIOD_M15, 5, 5, 200, 3, 15, PERIOD_M1, 10, 9,
      0.02, 5.0, -0.080, -0.080, 2.00, 0.70, 0.20, 0.20, 1.00, 1.00, 0.15, 0.10, 0.025, 0.055
   }
};

//====================================================================
// GLOBAL VARIABLES
//====================================================================
double              TieredLotEff;
double              CurrSpread;
ENUM_TIMEFRAMES     FractalTf;
ENUM_TIMEFRAMES     RescanTf;
int                 FractalRight;
int                 FractalLeft;
int                 FractalMaxSearch;
int                 MaxPendingOrders;
int                 MaxPositions;
double              PendingDedupDist;
int                 PendingExpiryHrs;
int                 ActiveMagic;
ENUM_TIMEFRAMES     ExitScanTf;
int                 SymDigits;
double              StopLevelDist;
double              PipFactor;
double              FreezeLevelDist;
string              ActiveComment;
string              TradeSym;
double              SymPoint;

int                 DayswitchBufferMin = 30;
double              FractalMinDist;
double              BuyEntryOffset;
double              SellEntryOffset;
bool                Virtual_expiration = true;

double              SLDist;
double              TPDist;
double              TrailDist;
double              TrailMinProfit;
double              TrailMaxSL;
double              TrailStep = 0.1;
double              SalvageExitDist;
double              SalvageTrigger;
double              BeTrigger;
double              BeLockDist;

double              MaxLotCap = 100.0;
double              WeightedRiskDivisor = 1.0;
double              DDTierDivisor = 1.0;
double              RiskWeight = 0.0;

double              LastSwingHigh = 0.0;
double              LastSwingLow = 0.0;
double              VirtualSL = 0.0;

double              VirtualSLStore[20][2];
double              OrderPriceMap[100][2];
int                 VirtualSLStoreSize = 20;

double              StrategyLots[9];
bool                g_unitUnknownLogged = false;
double              SepStrategyLots[9];
int                 LastTradeTicket = 0;
int                 PendingExpirySeconds;

double              SwingLow = 0.0;
double              SwingHigh = 0.0;

int                 LastHour = 0;
datetime            PendingExpiry = 0;
int                 PerStrategyRescanBars[9];
int                 PerStrategyPendingRescanBars[9];

bool                StratEnabled[9];
int                 StrategyIdx = 0;
bool                SymInitOk = false;

// Active parameter cache from preset
double              FractalMinDistPct;
double              BuyEntryPct;
double              SellEntryPct;
double              SlPct;
double              TpPct;
double              TrailPct;
double              TrailMinProfitPct;
double              TrailMaxSLPct;
double              SalvageTriggerPct;
double              SalvageExitDistPct;
double              BeTriggerPct;
double              BeLockPct;

//====================================================================
void SetupStrategyParams(int stratNum) {
    StrategyPreset preset = StrategyPresets[stratNum - 1];

    FractalTf          = preset.fractalTf;
    RescanTf           = preset.rescanTf;
    FractalRight       = preset.fractalRight;
    FractalLeft        = preset.fractalLeft;
    FractalMaxSearch   = preset.fractalMaxSearch;
    FractalMinDistPct  = preset.fractalMinDistPct;
    BuyEntryPct        = preset.buyEntryPct;
    SellEntryPct       = preset.sellEntryPct;
    MaxPendingOrders   = preset.maxPending;
    PendingDedupDist   = preset.pendDedupDist;
    PendingExpiryHrs   = preset.pendExpiryHrs;
    ExitScanTf         = preset.exitScanTf;
    SlPct              = preset.slPct;
    TpPct              = preset.tpPct;
    TrailPct           = preset.trailPct;
    TrailMinProfitPct  = preset.trailMinProfitPct;
    TrailMaxSLPct      = preset.trailMaxSLPct;
    SalvageTriggerPct  = preset.salvageTriggerPct;
    SalvageExitDistPct = preset.salvageExitPct;
    BeTriggerPct       = preset.beTriggerPct;
    BeLockPct          = preset.beLockPct;
    MaxPositions       = preset.maxPositions;
    ActiveComment      = TradeComment + IntegerToString(stratNum);   // X9S1..X9S9: strategy N <=> magic base+N
    ActiveMagic        = InpMagic + preset.magicOffset;
    RiskWeight         = preset.riskWeight;
}

//+------------------------------------------------------------------+
//| Activate Strategy Context                                        |
//+------------------------------------------------------------------+
void ActivateStrategyContext(int strategyIndex) {
    StrategyIdx = strategyIndex;

    CurrSpread          = SymbolInfoDouble(TradeSym, SYMBOL_ASK) - SymbolInfoDouble(TradeSym, SYMBOL_BID);
    StopLevelDist       = (double)SymbolInfoInteger(TradeSym, SYMBOL_TRADE_STOPS_LEVEL) * SymPoint;
    FreezeLevelDist     = (double)SymbolInfoInteger(TradeSym, SYMBOL_TRADE_FREEZE_LEVEL) * SymPoint;
    PendingExpirySeconds = PendingExpiryHrs * 60 * 60;

    double currentRefPrice = SymbolInfoDouble(TradeSym, SYMBOL_BID);

    FractalMinDist      = FractalMinDistPct / 100.0 * currentRefPrice / PipFactor;
    BuyEntryOffset      = AdjustEntry + NormalizeDouble(BuyEntryPct / 100.0 * currentRefPrice / PipFactor, 0);
    SellEntryOffset     = AdjustEntry + NormalizeDouble(SellEntryPct / 100.0 * currentRefPrice / PipFactor, 0);
    SLDist              = AdjustSL + SlPct / 100.0 * currentRefPrice / PipFactor;
    TPDist              = AdjustTP + TpPct / 100.0 * currentRefPrice / PipFactor;
    TrailDist           = AdjustTrailSL + TrailPct / 100.0 * currentRefPrice / PipFactor;
    TrailMinProfit      = TrailMinProfitPct / 100.0 * currentRefPrice / PipFactor;
    TrailMaxSL          = TrailMaxSLPct / 100.0 * currentRefPrice / PipFactor;
    SalvageExitDist     = AdjustSalvageExit + SalvageExitDistPct / 100.0 * currentRefPrice / PipFactor;
    SalvageTrigger      = SalvageTriggerPct / 100.0 * currentRefPrice / PipFactor;
    BeTrigger           = BeTriggerPct / 100.0 * currentRefPrice / PipFactor;
    BeLockDist          = AdjustBreakEven + BeLockPct / 100.0 * currentRefPrice / PipFactor;
    if ( BeLockPct == 0.0 && BeLockDist == 0.0 && BeTrigger > 0.0 ){
        BeLockDist = 1.0 * SymPoint / PipFactor;
    }

    if ( BeLockDist > BeTrigger ){
        BeLockDist = BeTrigger / 2.0;
    }
}

//+------------------------------------------------------------------+
//| Remove own pending orders when order-shaping inputs change       |
//+------------------------------------------------------------------+
int X9StrategyMagic(int strategy) {
    return InpMagic + StrategyPresets[strategy - 1].magicOffset;
}

ulong X9ConfigSignature(int strategy) {
    StrategyPreset preset = StrategyPresets[strategy - 1];
    string config = TradeSym + "|" + IntegerToString(InpMagic) + "|" + IntegerToString(strategy) + "|" +
        (StratEnabled[strategy - 1] ? "1" : "0") + "|" +
        IntegerToString((int)TradeFrequency) + "|" + IntegerToString((int)Lotsizing_Method) + "|" +
        DoubleToString(TieredLot, 16) + "|" + DoubleToString(TieredLotEff, 16) + "|" + DoubleToString(RiskScaling, 16) + "|" +
        DoubleToString(MaxLotCap, 16) + "|" +
        DoubleToString(InpFixedBalance, 16) + "|" + DoubleToString(FixedLots, 16) + "|" +
        (SepLotSize ? "1" : "0") + "|" +
        DoubleToString(SepStrategyLots[strategy - 1], 16) + "|" +
        DoubleToString(DDTierDivisor, 16) + "|" + DoubleToString(AdjustEntry, 16) + "|" +
        DoubleToString(AdjustSL, 16) + "|" + DoubleToString(AdjustTP, 16) + "|" +
        IntegerToString((int)preset.fractalTf) + "|" + IntegerToString((int)preset.rescanTf) + "|" +
        IntegerToString(preset.fractalRight) + "|" + IntegerToString(preset.fractalLeft) + "|" +
        IntegerToString(preset.fractalMaxSearch) + "|" + IntegerToString(preset.maxPending) + "|" +
        IntegerToString(preset.pendExpiryHrs) + "|" + IntegerToString((int)preset.exitScanTf) + "|" +
        IntegerToString(preset.maxPositions) + "|" + IntegerToString(preset.magicOffset) + "|" +
        DoubleToString(preset.fractalMinDistPct, 16) + "|" + DoubleToString(preset.pendDedupDist, 16) + "|" +
        DoubleToString(preset.buyEntryPct, 16) + "|" + DoubleToString(preset.sellEntryPct, 16) + "|" +
        DoubleToString(preset.slPct, 16) + "|" + DoubleToString(preset.tpPct, 16) + "|" +
        DoubleToString(preset.trailPct, 16) + "|" + DoubleToString(preset.trailMinProfitPct, 16) + "|" +
        DoubleToString(preset.trailMaxSLPct, 16) + "|" + DoubleToString(preset.salvageTriggerPct, 16) + "|" +
        DoubleToString(preset.salvageExitPct, 16) + "|" + DoubleToString(preset.beTriggerPct, 16) + "|" +
        DoubleToString(preset.beLockPct, 16) + "|" + DoubleToString(preset.riskWeight, 16);
    if (SepLotSize) {
        switch (strategy) {
            case 1: config += "|" + DoubleToString(Strat1Lots, 16); break;
            case 2: config += "|" + DoubleToString(Strat2Lots, 16); break;
            case 3: config += "|" + DoubleToString(Strat3Lots, 16); break;
            case 4: config += "|" + DoubleToString(Strat4Lots, 16); break;
            case 5: config += "|" + DoubleToString(Strat5Lots, 16); break;
            case 6: config += "|" + DoubleToString(Strat6Lots, 16); break;
            case 7: config += "|" + DoubleToString(Strat7Lots, 16); break;
            case 8: config += "|" + DoubleToString(Strat8Lots, 16); break;
            case 9: config += "|" + DoubleToString(Strat9Lots, 16); break;
        }
    }
    ulong hash = 5381;
    for (int i = 0; i < StringLen(config); i++) hash = (hash * 33 + StringGetCharacter(config, i)) % 2147483647;
    return hash;
}

string X9OrderConfigKey(string symbol, int magic, int strategy) {
    return "X9CFG_" + IntegerToString((int)AccountInfoInteger(ACCOUNT_LOGIN)) + "_" +
           IntegerToString((int)ChartID()) + "_" + symbol + "_" + IntegerToString(magic) + "_" + IntegerToString(strategy);
}

void X9CancelStrategyPendingOrders(string symbol, int magic) {
    for (int i = OrdersTotal() - 1; i >= 0; i--) {
        if (!ordinfo.SelectByIndex(i) || ordinfo.Symbol() != symbol || ordinfo.Magic() != magic) continue;
        trade.OrderDelete(ordinfo.Ticket());
    }
}

bool X9OrderConfigChanged() {
    for (int strategy = 1; strategy <= 9; strategy++) {
        string key = X9OrderConfigKey(TradeSym, InpMagic, strategy);
        if (!GlobalVariableCheck(key) || GlobalVariableGet(key) != (double)X9ConfigSignature(strategy)) return true;
    }
    return false;
}

void X9SaveOrderConfig() {
    for (int strategy = 1; strategy <= 9; strategy++)
        GlobalVariableSet(X9OrderConfigKey(TradeSym, InpMagic, strategy), (double)X9ConfigSignature(strategy));
}

bool X9ReconcilePendingOrders() {
    bool changed = false;
    string prefix = "X9CFG_" + IntegerToString((int)AccountInfoInteger(ACCOUNT_LOGIN)) + "_" + IntegerToString((int)ChartID()) + "_";
    for (int variable = GlobalVariablesTotal() - 1; variable >= 0; variable--) {
        string key = GlobalVariableName(variable);
        if (StringFind(key, prefix) != 0) continue;
        int lastSep = -1, priorSep = -1;
        for (int ch = 0; ch < StringLen(key); ch++) {
            if (StringGetCharacter(key, ch) != '_') continue;
            priorSep = lastSep;
            lastSep = ch;
        }
        if (priorSep < 0 || lastSep < 0) continue;
        string oldSymbol = StringSubstr(key, StringLen(prefix), priorSep - StringLen(prefix));
        int oldMagic = (int)StringToInteger(StringSubstr(key, priorSep + 1, lastSep - priorSep - 1));
        if (oldSymbol == TradeSym && oldMagic == InpMagic) continue;
        for (int strategy = 1; strategy <= 9; strategy++) {
            SetupStrategyParams(strategy);
            X9CancelStrategyPendingOrders(oldSymbol, oldMagic + ActiveMagic - InpMagic);
        }
        GlobalVariableDel(key);
        changed = true;
    }
    for (int strategy = 1; strategy <= 9; strategy++) {
        string key = X9OrderConfigKey(TradeSym, InpMagic, strategy);
        double signature = (double)X9ConfigSignature(strategy);
        if (GlobalVariableCheck(key) && GlobalVariableGet(key) != signature) {
            SetupStrategyParams(strategy);
            X9CancelStrategyPendingOrders(TradeSym, ActiveMagic);
            changed = true;
        }
        GlobalVariableSet(key, signature);
    }
    ArrayResize(g_x9ManualCancels, 0);
    for (int i = 0; i < 9; i++) PerStrategyPendingRescanBars[i] = 0;
    return changed;
}

//+------------------------------------------------------------------+
//| RunStrategyTick (Per-Strategy Execution)                         |
//+------------------------------------------------------------------+
int RunStrategyTick(int stratIdx) {
    bool        anyOrderModified;
    MqlDateTime nowDt;
    int         buyPendingCount;
    int         buyPendingCountScanIdx;
    double      highestBuyPendingPrice;
    long        highestBuyPendingTicket;
    int         buyPendingWorstScanIdx;
    long        deletedBuyTicket;
    int         buyMapClearIdx;
    int         sellPendingCount;
    int         sellPendingCountScanIdx;
    double      lowestSellPendingPrice;
    long        lowestSellPendingTicket;
    int         sellPendingWorstScanIdx;
    long        deletedSellTicket;
    int         sellMapClearIdx;
    bool        orderMapEntryStillOpen;
    int         orderMapScanIdx;
    long        mapStoredTicket;
    int         orderMapTicketScanIdx;
    long        currentScanTicket;
    int         pendingLoopCounter;

    TimeToStruct(TimeCurrent(), nowDt);
    anyOrderModified = false;
    bool freezeManagement = IsX9NewsManagementFrozen();

    //--- Manage open orders based on ExitScanTf
    if ( !freezeManagement && ExitScanTf == PERIOD_CURRENT ){
        if ( ManageOrders(true) ){
            anyOrderModified = true;
        }
        if ( ManageOrders(false) ){
            anyOrderModified = true;
        }
        if ( anyOrderModified ){
            return(0);
        }
    }
    else{
        if ( !freezeManagement && PerStrategyRescanBars[stratIdx] != iBars(TradeSym, ExitScanTf) ){
            PerStrategyRescanBars[stratIdx] = iBars(TradeSym, ExitScanTf);
            if ( ManageOrders(true) ){
                anyOrderModified = true;
            }
            if ( ManageOrders(false) ){
                anyOrderModified = true;
            }
            if ( anyOrderModified ){
                return(0);
            }
        }
    }

    //--- Day-switch rollover filter (minute-based window around midnight)
    if ( (nowDt.hour == 0  && nowDt.min <  DayswitchBufferMin) ||
         (nowDt.hour == 23 && nowDt.min >= 60 - DayswitchBufferMin) ){
        return(0);
    }

    CurrSpread = SymbolInfoDouble(TradeSym, SYMBOL_ASK) - SymbolInfoDouble(TradeSym, SYMBOL_BID);

    //--- Scan Buy Pending Orders and prune worst if > MaxPendingOrders
    buyPendingCount = 0;
    for (buyPendingCountScanIdx = 0; ordinfo.SelectByIndex(buyPendingCountScanIdx); buyPendingCountScanIdx++){
        if ( ordinfo.Magic() != ActiveMagic ||
             ordinfo.Symbol() != TradeSym ||
             ordinfo.OrderType() != ORDER_TYPE_BUY_STOP )
            continue;
        buyPendingCount = buyPendingCount + 1;
    }

    if ( !freezeManagement && buyPendingCount > MaxPendingOrders ){
        highestBuyPendingPrice = 0.0;
        highestBuyPendingTicket = 0;
        for (buyPendingWorstScanIdx = 0; ordinfo.SelectByIndex(buyPendingWorstScanIdx); buyPendingWorstScanIdx++){
            if ( ordinfo.Magic() != ActiveMagic ||
                 ordinfo.Symbol() != TradeSym ||
                 ordinfo.OrderType() != ORDER_TYPE_BUY_STOP ||
                 !(ordinfo.PriceOpen() > highestBuyPendingPrice) )
                continue;
            highestBuyPendingTicket = (long)ordinfo.Ticket();
            highestBuyPendingPrice = ordinfo.PriceOpen();
        }
        if ( highestBuyPendingTicket != 0 ){
            if ( InpEnableAuditLog )
                PrintFormat("[AUDIT] Pruning worst Buy Pending #%I64d at %.2f (count %d > max %d)",
                            highestBuyPendingTicket, highestBuyPendingPrice, buyPendingCount, MaxPendingOrders);
            trade.OrderDelete(highestBuyPendingTicket);
                        deletedBuyTicket = highestBuyPendingTicket;
            for (buyMapClearIdx = 0; buyMapClearIdx < 100; buyMapClearIdx = buyMapClearIdx + 1){
                if ( !(OrderPriceMap[buyMapClearIdx][0] == (double)deletedBuyTicket) ) continue;
                OrderPriceMap[buyMapClearIdx][0] = 0.0;
                OrderPriceMap[buyMapClearIdx][1] = 0.0;
                break;
            }
        }
    }

    //--- Scan Sell Pending Orders and prune worst if > MaxPendingOrders
    sellPendingCount = 0;
    for (sellPendingCountScanIdx = 0; ordinfo.SelectByIndex(sellPendingCountScanIdx); sellPendingCountScanIdx++){
        if ( ordinfo.Magic() != ActiveMagic ||
             ordinfo.Symbol() != TradeSym ||
             ordinfo.OrderType() != ORDER_TYPE_SELL_STOP )
            continue;
        sellPendingCount = sellPendingCount + 1;
    }

    if ( !freezeManagement && sellPendingCount > MaxPendingOrders ){
        lowestSellPendingPrice = DBL_MAX;
        lowestSellPendingTicket = 0;
        for (sellPendingWorstScanIdx = 0; ordinfo.SelectByIndex(sellPendingWorstScanIdx); sellPendingWorstScanIdx++){
            if ( ordinfo.Magic() != ActiveMagic ||
                 ordinfo.Symbol() != TradeSym ||
                 ordinfo.OrderType() != ORDER_TYPE_SELL_STOP ||
                 !(ordinfo.PriceOpen() < lowestSellPendingPrice) )
                continue;
            lowestSellPendingTicket = (long)ordinfo.Ticket();
            lowestSellPendingPrice = ordinfo.PriceOpen();
        }
        if ( lowestSellPendingTicket != 0 ){
            if ( InpEnableAuditLog )
                PrintFormat("[AUDIT] Pruning worst Sell Pending #%I64d at %.2f (count %d > max %d)",
                            lowestSellPendingTicket, lowestSellPendingPrice, sellPendingCount, MaxPendingOrders);
            trade.OrderDelete(lowestSellPendingTicket);
                        deletedSellTicket = lowestSellPendingTicket;
            for (sellMapClearIdx = 0; sellMapClearIdx < 100; sellMapClearIdx = sellMapClearIdx + 1){
                if ( !(OrderPriceMap[sellMapClearIdx][0] == (double)deletedSellTicket) ) continue;
                OrderPriceMap[sellMapClearIdx][0] = 0.0;
                OrderPriceMap[sellMapClearIdx][1] = 0.0;
                break;
            }
        }
    }

    //--- Rescan TF entry burst
    if ( PerStrategyPendingRescanBars[stratIdx] != iBars(TradeSym, RescanTf) ){
        PerStrategyPendingRescanBars[stratIdx] = iBars(TradeSym, RescanTf);
        for (pendingLoopCounter = 0; pendingLoopCounter < MaxPendingOrders; pendingLoopCounter++){
            ProcessStrategyEntries();
        }
    }

    //--- Hourly cleanup of OrderPriceMap for closed orders
    if ( LastHour != nowDt.hour ){
        LastHour = nowDt.hour;
        orderMapEntryStillOpen = false;
        for (orderMapScanIdx = 0; orderMapScanIdx < 100; orderMapScanIdx = orderMapScanIdx + 1){
            mapStoredTicket = (long)OrderPriceMap[orderMapScanIdx][0];
            if ( mapStoredTicket == 0 ) continue;
            orderMapEntryStillOpen = false;
            for (orderMapTicketScanIdx = 0; posinfo.SelectByIndex(orderMapTicketScanIdx); orderMapTicketScanIdx++){
                currentScanTicket = (long)posinfo.Ticket();
                if ( mapStoredTicket != currentScanTicket ) continue;
                orderMapEntryStillOpen = true;
                break;
            }
            if ( !orderMapEntryStillOpen ){
                for (orderMapTicketScanIdx = 0; ordinfo.SelectByIndex(orderMapTicketScanIdx); orderMapTicketScanIdx++){
                    currentScanTicket = (long)ordinfo.Ticket();
                    if ( mapStoredTicket != currentScanTicket ) continue;
                    orderMapEntryStillOpen = true;
                    break;
                }
            }
            if ( orderMapEntryStillOpen ) continue;
            OrderPriceMap[orderMapScanIdx][0] = 0.0;
            OrderPriceMap[orderMapScanIdx][1] = 0.0;
        }
    }

    return(0);
}

//+------------------------------------------------------------------+
//| FindSwingPoint (Fractal Detection)                               |
//+------------------------------------------------------------------+
double FindSwingPoint(ENUM_TIMEFRAMES timeframe, bool findHigh) {
    bool        found = false;
    bool        leftOk = false;
    bool        rightOk = false;
    int         barIdx;
    int         rightScan;
    int         leftScan;
    double      candidateExtreme;
    int         candidateBar;
    double      historicalExtreme;
    int         histIdx;
    double      normalizedPrice;
    int         ordIdx;
    bool        dupFound;
    double      result;

    barIdx = FractalRight + 1;

    do{
        leftOk = true;
        rightOk = true;

        for (rightScan = barIdx; rightScan >= barIdx - FractalRight; rightScan--){
            if ( findHigh ? (iHigh(TradeSym, timeframe, rightScan) > iHigh(TradeSym, timeframe, barIdx)) :
                            (iLow(TradeSym, timeframe, rightScan) < iLow(TradeSym, timeframe, barIdx)) ){
                rightOk = false;
            }
        }

        for (leftScan = barIdx; leftScan <= barIdx + FractalLeft; leftScan++){
            if ( findHigh ? (iHigh(TradeSym, timeframe, leftScan) > iHigh(TradeSym, timeframe, barIdx)) :
                            (iLow(TradeSym, timeframe, leftScan) < iLow(TradeSym, timeframe, barIdx)) ){
                leftOk = false;
            }
        }

        if ( rightOk && leftOk && ( findHigh ?
            (iHigh(TradeSym, timeframe, barIdx) > FractalMinDist * PipFactor + SymbolInfoDouble(TradeSym, SYMBOL_ASK)) :
            (iLow(TradeSym, timeframe, barIdx) < SymbolInfoDouble(TradeSym, SYMBOL_BID) - FractalMinDist * PipFactor) ) ){

            candidateExtreme = findHigh ? iHigh(TradeSym, timeframe, barIdx) :
                                          iLow(TradeSym, timeframe, barIdx);

            candidateBar = barIdx;

            historicalExtreme = findHigh ? iHigh(TradeSym, FractalTf, 0) :
                                           iLow(TradeSym, FractalTf, 0);

            for (histIdx = 1; histIdx <= candidateBar; histIdx = histIdx + 1){
                if ( findHigh ? (iHigh(TradeSym, FractalTf, histIdx) > historicalExtreme) :
                                (iLow(TradeSym, FractalTf, histIdx) < historicalExtreme) ){
                    historicalExtreme = findHigh ? iHigh(TradeSym, FractalTf, histIdx) :
                                                   iLow(TradeSym, FractalTf, histIdx);
                }
            }

            if ( findHigh ? (candidateExtreme >= historicalExtreme) :
                            (candidateExtreme <= historicalExtreme) ){

                normalizedPrice = NormalizeDouble(candidateExtreme, SymDigits);
                dupFound = false;

                for (ordIdx = 0; ordinfo.SelectByIndex(ordIdx); ordIdx++){
                    if ( findHigh ){
                        if ( ordinfo.Magic() != ActiveMagic ||
                             ordinfo.Symbol() != TradeSym ||
                             ordinfo.OrderType() != ORDER_TYPE_BUY_STOP ||
                             !(MathAbs(ordinfo.PriceOpen() - (BuyEntryOffset * PipFactor + normalizedPrice)) < PendingDedupDist * PipFactor) )
                            continue;
                    }
                    else{
                        if ( ordinfo.Magic() != ActiveMagic ||
                             ordinfo.Symbol() != TradeSym ||
                             ordinfo.OrderType() != ORDER_TYPE_SELL_STOP ||
                             !(MathAbs(ordinfo.PriceOpen() - (normalizedPrice - SellEntryOffset * PipFactor)) < PendingDedupDist * PipFactor) )
                            continue;
                    }

                    dupFound = true;
                    break;
                }

                if ( !(dupFound) ){
                    found = true;
                    result = normalizedPrice;
                    if ( findHigh ){
                        SwingHigh = result;
                    }
                    else{
                        SwingLow = result;
                    }
                    break;
                }
            }
        }

        barIdx++;

        if ( barIdx <= FractalMaxSearch ) continue;

        if ( findHigh ){
            SwingHigh = 0.0;
        }
        else{
            SwingLow = 0.0;
        }
        break;

    }
    while(!(found));

    return( findHigh ? SwingHigh : SwingLow );
}

//+------------------------------------------------------------------+
//| Account cash per 1 USD of risk (denomination scale, not contract) |
//|                                                                   |
//| Tick value is always reported in the ACCOUNT's own cash, and a     |
//| symbol whose PROFIT currency is USD therefore gives the scale:     |
//|   tv / (tickSize * contractSize)                                  |
//| On a USD account this is 1.0; on a cent account (USC, or any       |
//| cent variant) it is 100.0; on a EUR/GBP/JPY account it is that     |
//| currency's value of one USD. No currency table, no cent flag, no   |
//| 100-oz contract anchor, so the same code is correct on every       |
//| denomination instead of only on XAUUSD.                            |
//+------------------------------------------------------------------+
double X9CashPerUSD() {
    string sym = "";
    if ( SymbolInfoString(TradeSym, SYMBOL_CURRENCY_PROFIT) == "USD" ) sym = TradeSym;
    if ( sym == "" ) {
        int total = SymbolsTotal(true);                 // Market Watch only: never silently select symbols
        for ( int i = 0; i < total; i++ ) {
            string cand = SymbolName(i, true);
            if ( SymbolInfoString(cand, SYMBOL_CURRENCY_PROFIT) != "USD" ) continue;
            sym = cand;
            break;
        }
    }
    if ( sym == "" ) return 0.0;
    double tickVal = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
    double tickSz  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
    double contract = SymbolInfoDouble(sym, SYMBOL_TRADE_CONTRACT_SIZE);
    if ( !MathIsValidNumber(tickVal) || !MathIsValidNumber(tickSz) || !MathIsValidNumber(contract) ) return 0.0;
    if ( tickVal <= 0.0 || tickSz <= 0.0 || contract <= 0.0 ) return 0.0;
    double rate = tickVal / (tickSz * contract);
    return ( MathIsValidNumber(rate) && rate > 0.0 ) ? rate : 0.0;
}
// The Part 3 formula already assumes 100 cash units per price unit per lot.
// Convert that anchor using THIS symbol's cash-per-price-unit-per-lot, not
// X9CashPerUSD(): contract size varies independently of account denomination.
double X9CurrencyFactor(const string symbol) {
    double tickVal = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSz = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
    if (!MathIsValidNumber(tickVal) || !MathIsValidNumber(tickSz) || tickVal <= 0.0 || tickSz <= 0.0) return 0.0;
    double factor = (tickVal / tickSz) / 100.0;
    return (MathIsValidNumber(factor) && factor > 0.0) ? factor : 0.0;
}

//+------------------------------------------------------------------+
//| CalculateLotSize (Part 3 Multi-Strategy Weighted Sizing)         |
//+------------------------------------------------------------------+
void CalculateLotSize() {
    double calculatedLots = StrategyLots[StrategyIdx];

    if ( Lotsizing_Method == Manual_Lotsize ){
        calculatedLots = SepLotSize ? SepStrategyLots[StrategyIdx] : FixedLots;
        if ( calculatedLots < SymbolInfoDouble(TradeSym, SYMBOL_VOLUME_MIN) ){
            calculatedLots = SymbolInfoDouble(TradeSym, SYMBOL_VOLUME_MIN);
        }
        StrategyLots[StrategyIdx] = calculatedLots;
        return;
    }

    double slDollars = SLDist * PipFactor;
    double riskDivisorValue = 0.0;

    if ( Lotsizing_Method == Tiered_Lotsizing ){
        WeightedRiskDivisor = TieredLotEff / DDTierDivisor;
        riskDivisorValue = WeightedRiskDivisor;
    }

    if ( Lotsizing_Method == RiskScaleFactor ){
        riskDivisorValue = RiskScaling;
    }

    if ( ( Lotsizing_Method == Tiered_Lotsizing || Lotsizing_Method == RiskScaleFactor ) && slDollars > 0.0 ){
        double effectiveBalance = (InpFixedBalance > 0.0) ? InpFixedBalance : AccountInfoDouble(ACCOUNT_BALANCE);
        calculatedLots = riskDivisorValue * effectiveBalance * 0.0001 * RiskWeight / slDollars;
    }

    double currencyFactor = X9CurrencyFactor(TradeSym);
    if ( currencyFactor > 0.0 ) {
        calculatedLots /= currencyFactor;
    }
    else {
        StrategyLots[StrategyIdx] = 0.0;
        if ( !g_unitUnknownLogged ) {
            g_unitUnknownLogged = true;
            PrintFormat("[X9_SIZE] LOT_VALUE_UNKNOWN: invalid tick value/size on %s; new entry sizing blocked (%s)",
                        TradeSym, AccountInfoString(ACCOUNT_CURRENCY));
        }
        return; // Sizing failure must not invent unscaled volume; owned management is separate.
    }
    double rawLots = calculatedLots;

    if ( calculatedLots < SymbolInfoDouble(TradeSym, SYMBOL_VOLUME_STEP) ){
        calculatedLots = SymbolInfoDouble(TradeSym, SYMBOL_VOLUME_STEP);
    }

    // Denomination-neutral minimum-lot policy: a budget below one broker lot is NOT silently
    // rounded up (that multiplies the real risk on a cent account by the cent factor). The entry
    // is skipped and tagged, unless the operator explicitly opts into the minimum-lot override.
    double brokerMinLot = SymbolInfoDouble(TradeSym, SYMBOL_VOLUME_MIN);
    if ( brokerMinLot > 0.0 && calculatedLots + 1e-10 < brokerMinLot ){
        if ( !InpAllowMinLotOverride ){
            StrategyLots[StrategyIdx] = 0.0;              // the entry guard refuses volume < minimum
            if ( InpEnableAuditLog ){
                PrintFormat("[X9_SIZE] RISK_BELOW_MIN_LOT: sized %.8f lots < broker minimum %.8f on %s %s; entry skipped",
                            calculatedLots, brokerMinLot, AccountInfoString(ACCOUNT_CURRENCY),
                            AccountInfoString(ACCOUNT_SERVER));
            }
            return;
        }
        PrintFormat("[X9_SIZE] MIN_LOT_OVERRIDE: sized %.8f lots raised to broker minimum %.8f on %s; real risk exceeds the budget",
                    calculatedLots, brokerMinLot, AccountInfoString(ACCOUNT_CURRENCY));
    }

    if ( calculatedLots > MaxLotCap ){
        calculatedLots = MaxLotCap;
    }

    if ( calculatedLots < SymbolInfoDouble(TradeSym, SYMBOL_VOLUME_MIN) ){
        calculatedLots = SymbolInfoDouble(TradeSym, SYMBOL_VOLUME_MIN);
    }

    if ( calculatedLots > SymbolInfoDouble(TradeSym, SYMBOL_VOLUME_MAX) && SymbolInfoDouble(TradeSym, SYMBOL_VOLUME_MAX) != 0.0 ){
        calculatedLots = SymbolInfoDouble(TradeSym, SYMBOL_VOLUME_MAX);
    }

    if ( SymbolInfoDouble(TradeSym, SYMBOL_VOLUME_STEP) == 0.1 ){
        StrategyLots[StrategyIdx] = NormalizeDouble((MathFloor(calculatedLots * 10.0)) / 10.0, 1);
    }
    else{
        StrategyLots[StrategyIdx] = NormalizeDouble(MathFloor(calculatedLots * 100.0) / 100.0, 2);
    }

    if ( InpEnableAuditLog ){
        ulong nowMs = GetTickCount64();
        // Per strategy, or the nine strategies share one clock and the first one starves the rest.
        // Static, because the throttle was a local variable: it reset to 0 on every call, so the log
        // printed several times per tick per strategy instead of once every few seconds.
        static ulong lastAuditLogMs[16];
        int auditSlot = (StrategyIdx >= 0 && StrategyIdx < 16) ? StrategyIdx : 0;
        if ( nowMs - lastAuditLogMs[auditSlot] >= 5000 ){
            lastAuditLogMs[auditSlot] = nowMs;
            double effBal = (InpFixedBalance > 0.0) ? InpFixedBalance : AccountInfoDouble(ACCOUNT_BALANCE);
            PrintFormat("[LOT_AUDIT] Strat %d | Bal=%.2f %s | Tiered=%.2f | PortfolioDiv=%.2f | SLDist=%.2f | CashPerPriceLot=%.6f | RawLots=%.8f | Lots=%.2f | MinLot=%.2f | RiskWeight=%.4f | ImpliedRisk=%.2f %s",
                        StrategyIdx + 1, effBal, AccountInfoString(ACCOUNT_CURRENCY), TieredLotEff, DDTierDivisor,
                        slDollars, currencyFactor * 100.0, rawLots, StrategyLots[StrategyIdx], brokerMinLot, RiskWeight,
                        StrategyLots[StrategyIdx] * slDollars * currencyFactor * 100.0, AccountInfoString(ACCOUNT_CURRENCY));
        }
    }
}

//+------------------------------------------------------------------+
//| ProcessStrategyEntries                                           |
//+------------------------------------------------------------------+
void ProcessStrategyEntries() {
    int        expireIdx;
    datetime   nowTime;
    datetime   orderExpireTime;
    int        buyPosCount;
    int        buyPosScanIdx;
    int        buyPendDeleteIdx;
    int        sellPosCount;
    int        sellPosScanIdx;
    int        sellPendDeleteIdx;
    bool       deleteThisOrder;
    bool       freezeManagement = IsX9NewsManagementFrozen();

    CalculateLotSize();

    if ( StrategyLots[StrategyIdx] > MaxLotCap ){
        StrategyLots[StrategyIdx] = MaxLotCap;
    }

    //--- Virtual Expiration handling
    if ( !freezeManagement && Virtual_expiration ){
        expireIdx = 0;
        while ( ordinfo.SelectByIndex(expireIdx) ){
            deleteThisOrder = false;
            if ( ordinfo.Magic() == ActiveMagic && ordinfo.Symbol() == TradeSym ){
                nowTime = TimeCurrent();
                orderExpireTime = ordinfo.TimeSetup() + PendingExpirySeconds;
                if ( nowTime >= orderExpireTime ){
                    if ( InpEnableAuditLog )
                        PrintFormat("[AUDIT] Pending order #%I64u expired (setup=%s, now=%s, limit=%ds)",
                                    ordinfo.Ticket(), TimeToString(ordinfo.TimeSetup()), TimeToString(nowTime), PendingExpirySeconds);
                    ulong expiredTicket = ordinfo.Ticket();
                    deleteThisOrder = trade.OrderDelete(expiredTicket);
                }
            }
            if ( !deleteThisOrder ) expireIdx++;
        }
    }

    //--- Count Buy Positions and enforce MaxPositions
    buyPosCount = 0;
    for (buyPosScanIdx = 0; posinfo.SelectByIndex(buyPosScanIdx); buyPosScanIdx++){
        if ( posinfo.Magic() != ActiveMagic ||
             posinfo.Symbol() != TradeSym ||
             posinfo.PositionType() != POSITION_TYPE_BUY )
            continue;
        buyPosCount = buyPosCount + 1;
    }

    if ( buyPosCount < MaxPositions ){
        PlaceEntry(true);
    }
    else if ( !freezeManagement ){
        buyPendDeleteIdx = 0;
        while ( ordinfo.SelectByIndex(buyPendDeleteIdx) ){
            deleteThisOrder = false;
            if ( ordinfo.Magic() == ActiveMagic &&
                 ordinfo.Symbol() == TradeSym &&
                 ordinfo.OrderType() == ORDER_TYPE_BUY_STOP ){
                if ( InpEnableAuditLog )
                    PrintFormat("[AUDIT] Deleting Buy Stop #%I64u (MaxPositions reached: %d >= %d)",
                                ordinfo.Ticket(), buyPosCount, MaxPositions);
                ulong removedTicket = ordinfo.Ticket();
                deleteThisOrder = trade.OrderDelete(removedTicket);
            }
            if ( !deleteThisOrder ) buyPendDeleteIdx++;
        }
    }

    //--- Count Sell Positions and enforce MaxPositions
    sellPosCount = 0;
    for (sellPosScanIdx = 0; posinfo.SelectByIndex(sellPosScanIdx); sellPosScanIdx++){
        if ( posinfo.Magic() != ActiveMagic ||
             posinfo.Symbol() != TradeSym ||
             posinfo.PositionType() != POSITION_TYPE_SELL )
            continue;
        sellPosCount = sellPosCount + 1;
    }

    if ( sellPosCount < MaxPositions ){
        PlaceEntry(false);
    }
    else if ( !freezeManagement ){
        sellPendDeleteIdx = 0;
        while ( ordinfo.SelectByIndex(sellPendDeleteIdx) ){
            deleteThisOrder = false;
            if ( ordinfo.Magic() == ActiveMagic &&
                 ordinfo.Symbol() == TradeSym &&
                 ordinfo.OrderType() == ORDER_TYPE_SELL_STOP ){
                if ( InpEnableAuditLog )
                    PrintFormat("[AUDIT] Deleting Sell Stop #%I64u (MaxPositions reached: %d >= %d)",
                                ordinfo.Ticket(), sellPosCount, MaxPositions);
                ulong removedTicket = ordinfo.Ticket();
                deleteThisOrder = trade.OrderDelete(removedTicket);
            }
            if ( !deleteThisOrder ) sellPendDeleteIdx++;
        }
    }
}

//+------------------------------------------------------------------+
//| ManageOrders (Position Management & Protection)                  |
//+------------------------------------------------------------------+
bool ManageOrders(bool isBuy) {
    bool      modified = false;
    bool      orderModified = false;
    double    effectiveSL;
    double    tpRefPrice;
    int       orderIdx;
    double    currentSL;
    double    currentTP;
    long      orderTicket;
    double    openPrice;
    double    orderLots;
    datetime  openTime;
    int       orderType;
    int       orderMagic;
    string    orderSymbol;
    double    entryRefPrice;
    int       digitsTemp;
    long      mapTicket;
    int       mapScanIdx;
    double    mapPrice;
    double    entryPriceForMap;
    long      newMapTicket;
    int       mapSlotIdx;
    long      adaptTrailTicket;
    double    adaptTrailDistParam;
    double    adaptTrailRefPrice;
    int       adaptTrailDirection;
    double    adaptTrailComputed;
    bool      adaptTrailFound;
    int       adaptTrailScanIdx;
    int       adaptTrailSaveScanIdx;
    double    newVSlValue;
    long      newVSlTicket;
    int       vSlSaveIdx;

    ulong closeDeviation = (ulong)(CurrSpread);

    effectiveSL = 0.0;
    tpRefPrice = 0.0;

    for (orderIdx = 0; posinfo.SelectByIndex(orderIdx); orderIdx++){
        modified = false;

        currentSL = NormalizeDouble(posinfo.StopLoss(), SymDigits);
        currentTP = NormalizeDouble(posinfo.TakeProfit(), SymDigits);
        orderTicket = (long)posinfo.Ticket();
        openPrice = NormalizeDouble(posinfo.PriceOpen(), SymDigits);
        orderLots = posinfo.Volume();
        openTime = (datetime)posinfo.Time();
        orderType = (int)posinfo.PositionType();
        orderMagic = (int)posinfo.Magic();
        orderSymbol = posinfo.Symbol();

        if ( orderType == (isBuy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL) &&
             orderMagic == ActiveMagic &&
             orderSymbol == TradeSym ){

            //--- 1. Initialize SL if missing
            if ( currentSL == 0.0 ){
                currentSL = isBuy ? NormalizeDouble(openPrice - SLDist * PipFactor, SymDigits) :
                                    NormalizeDouble(SLDist * PipFactor + openPrice, SymDigits);
                if ( InpEnableAuditLog )
                    PrintFormat("[AUDIT] PositionModify #%I64d | Reason: InitialSL | SL: 0 -> %.2f | TP: %.2f",
                                orderTicket, currentSL, currentTP);
                trade.PositionModify(orderTicket, currentSL, currentTP);
            }

            //--- 2. Initialize TP if missing
            if ( currentTP == 0.0 ){
                currentTP = isBuy ? NormalizeDouble(TPDist * PipFactor + openPrice, SymDigits) :
                                    NormalizeDouble(openPrice - TPDist * PipFactor, SymDigits);
                if ( InpEnableAuditLog )
                    PrintFormat("[AUDIT] PositionModify #%I64d | Reason: InitialTP | SL: %.2f | TP: 0 -> %.2f",
                                orderTicket, currentSL, currentTP);
                trade.PositionModify(orderTicket, currentSL, currentTP);
            }

            //--- 3. Lookup or record mapped entry reference price
            digitsTemp = SymDigits;
            mapTicket = orderTicket;
            mapPrice = 0.0;

            for (mapScanIdx = 0; mapScanIdx < 100; mapScanIdx = mapScanIdx + 1){
                if ( !(OrderPriceMap[mapScanIdx][0] == (double)mapTicket) ) continue;
                mapPrice = OrderPriceMap[mapScanIdx][1];
                break;
            }

            entryRefPrice = NormalizeDouble(mapPrice, digitsTemp);

            if ( entryRefPrice == 0.0 ){
                entryPriceForMap = openPrice;
                newMapTicket = orderTicket;
                for (mapSlotIdx = 0; mapSlotIdx < 100; mapSlotIdx = mapSlotIdx + 1){
                    if ( !(OrderPriceMap[mapSlotIdx][0] == 0.0) ) continue;
                    OrderPriceMap[mapSlotIdx][0] = (double)newMapTicket;
                    OrderPriceMap[mapSlotIdx][1] = entryPriceForMap;
                    break;
                }
                entryRefPrice = openPrice;
            }

            tpRefPrice = entryRefPrice;

            //--- 4. Spread-adjusted SL modification
            double spreadSL = isBuy ? NormalizeDouble(openPrice - SLDist * PipFactor - CurrSpread, SymDigits) :
                                      NormalizeDouble(SLDist * PipFactor + openPrice + CurrSpread, SymDigits);
            // Part 3 accepts a one-tick protective improvement. Both prices
            // already normalized above; a full-tick strict gap skips that move.
            bool spreadSlNeedsMod = isBuy ? (spreadSL > currentSL + Point() / 2.0) :
                                            (spreadSL < currentSL - Point() / 2.0);
            if ( spreadSlNeedsMod ){
                double oldSL = currentSL;
                currentSL = spreadSL;
                if ( InpEnableAuditLog )
                    PrintFormat("[AUDIT] PositionModify #%I64d | Reason: SpreadAdjSL | SL: %.2f -> %.2f | CurrSpread: %.2f",
                                orderTicket, oldSL, currentSL, CurrSpread);
                trade.PositionModify(orderTicket, currentSL, currentTP);
            }

            //--- 5. Spread-adjusted SL market close
            if ( isBuy ? (SymbolInfoDouble(TradeSym, SYMBOL_BID) < openPrice - SLDist * PipFactor - CurrSpread) :
                         (SymbolInfoDouble(TradeSym, SYMBOL_ASK) > SLDist * PipFactor + openPrice + CurrSpread) ){
                if ( InpEnableAuditLog )
                    PrintFormat("[AUDIT] PositionClose #%I64d | Reason: SpreadSLHit | Quote: %.2f | Thresh: %.2f",
                                orderTicket,
                                isBuy ? SymbolInfoDouble(TradeSym, SYMBOL_BID) : SymbolInfoDouble(TradeSym, SYMBOL_ASK),
                                isBuy ? (openPrice - SLDist * PipFactor - CurrSpread) : (SLDist * PipFactor + openPrice + CurrSpread));
                trade.PositionClose(orderTicket, closeDeviation);
                return(true);
            }

            //--- 6. Virtual SL store lookup
            adaptTrailTicket = orderTicket;
            adaptTrailDistParam = SLDist;
            adaptTrailRefPrice = openPrice;
            adaptTrailDirection = isBuy ? 1 : 2;
            adaptTrailComputed = 0.0;
            adaptTrailFound = false;

            for (adaptTrailScanIdx = 0; adaptTrailScanIdx < VirtualSLStoreSize; adaptTrailScanIdx++){
                if ( VirtualSLStore[adaptTrailScanIdx][0] == (double)adaptTrailTicket ){
                    adaptTrailComputed = VirtualSLStore[adaptTrailScanIdx][1];
                    adaptTrailFound = true;
                    break;
                }
            }

            if ( !(adaptTrailFound) ){
                if ( adaptTrailDirection == 1 ){
                    adaptTrailComputed = NormalizeDouble(adaptTrailRefPrice - adaptTrailDistParam * PipFactor, SymDigits);
                }
                if ( adaptTrailDirection == 2 ){
                    adaptTrailComputed = NormalizeDouble(adaptTrailDistParam * PipFactor + adaptTrailRefPrice, SymDigits);
                }

                for (adaptTrailSaveScanIdx = 0; adaptTrailSaveScanIdx < VirtualSLStoreSize; adaptTrailSaveScanIdx++){
                    if ( VirtualSLStore[adaptTrailSaveScanIdx][0] == 0.0 ){
                        VirtualSLStore[adaptTrailSaveScanIdx][0] = (double)adaptTrailTicket;
                        VirtualSLStore[adaptTrailSaveScanIdx][1] = adaptTrailComputed;
                        break;
                    }
                }
            }

            VirtualSL = adaptTrailComputed;
            effectiveSL = VirtualSL;

            //--- 7. Virtual SL market close
            if ( isBuy ? (SymbolInfoDouble(TradeSym, SYMBOL_BID) < effectiveSL) :
                         (SymbolInfoDouble(TradeSym, SYMBOL_ASK) > effectiveSL) ){
                if ( InpEnableAuditLog )
                    PrintFormat("[AUDIT] PositionClose #%I64d | Reason: VirtualSLHit | Quote: %.2f | VirtualSL: %.2f",
                                orderTicket,
                                isBuy ? SymbolInfoDouble(TradeSym, SYMBOL_BID) : SymbolInfoDouble(TradeSym, SYMBOL_ASK),
                                effectiveSL);
                trade.PositionClose(orderTicket, closeDeviation);
                return(true);
            }

            double Bid = SymbolInfoDouble(TradeSym, SYMBOL_BID);
            double Ask = SymbolInfoDouble(TradeSym, SYMBOL_ASK);

            //--- 8. Adaptive Trailing SL
            if ( TrailDist > 0.0 && ( isBuy ?
                (Bid > (TrailDist + TrailStep) * PipFactor + currentSL &&
                 Bid > TrailMinProfit * PipFactor + tpRefPrice &&
                 Bid < currentTP - FreezeLevelDist &&
                 currentSL < TrailMaxSL * PipFactor + openPrice) :

                (Ask < currentSL - (TrailDist + TrailStep) * PipFactor &&
                 Ask < tpRefPrice - TrailMinProfit * PipFactor &&
                 Ask > currentTP + FreezeLevelDist &&
                 currentSL > openPrice - TrailMaxSL * PipFactor)
            )){
                double newSL = isBuy ? NormalizeDouble(Bid - TrailDist * PipFactor, SymDigits) :
                                       NormalizeDouble(Ask + TrailDist * PipFactor, SymDigits);

                bool slImproved = isBuy ? (newSL > currentSL + Point() / 2.0) :
                                          (newSL < currentSL - Point() / 2.0);

                if ( slImproved && (isBuy ? (newSL < Bid - StopLevelDist) : (newSL > Ask + StopLevelDist)) ){
                    if ( InpEnableAuditLog )
                        PrintFormat("[AUDIT] PositionModify #%I64d | Reason: TrailSL | SL: %.2f -> %.2f | Price: %.2f",
                                    orderTicket, currentSL, newSL, isBuy ? Bid : Ask);
                    currentSL = newSL;
                    trade.PositionModify(orderTicket, currentSL, currentTP);
                    modified = true;
                }
            }

            //--- 9. Salvage Exit TP Modification
            if ( SalvageExitDist > 0.0 && ( isBuy ?
                (Ask < currentTP - SalvageExitDist * PipFactor &&
                 Ask < tpRefPrice - SalvageTrigger * PipFactor &&
                 Bid < currentTP - FreezeLevelDist) :

                (Bid > currentTP + SalvageExitDist * PipFactor &&
                 Bid > tpRefPrice + SalvageTrigger * PipFactor &&
                 Ask > currentTP + FreezeLevelDist)
            )){
                double sellSalvagePrice = SymbolInfoDouble(TradeSym, SYMBOL_BID);

                double newTP = isBuy ? NormalizeDouble(SymbolInfoDouble(TradeSym, SYMBOL_BID) + SalvageExitDist * PipFactor, SymDigits) :
                                       NormalizeDouble(sellSalvagePrice - SalvageExitDist * PipFactor, SymDigits);

                bool salvageValid = isBuy ? (newTP > Bid + StopLevelDist) :
                                            (newTP < Ask - StopLevelDist);

                if ( salvageValid ){
                    if ( InpEnableAuditLog )
                        PrintFormat("[AUDIT] PositionModify #%I64d | Reason: SalvageTP | TP: %.2f -> %.2f | tpRefPrice: %.2f",
                                    orderTicket, currentTP, newTP, tpRefPrice);
                    currentTP = newTP;
                    trade.PositionModify(orderTicket, currentSL, currentTP);
                    modified = true;
                }
            }

            //--- 10. Breakeven SL (fixed: normalize before comparing against currentSL to eliminate invalid stops)
            if ( BeTrigger > 0.0 && ( isBuy ?
                (Bid > BeTrigger * PipFactor + openPrice &&
                 Bid > BeLockDist * PipFactor + openPrice + StopLevelDist &&
                 Bid < currentTP - FreezeLevelDist) :

                (Ask < openPrice - BeTrigger * PipFactor &&
                 Ask < openPrice - BeLockDist * PipFactor - StopLevelDist &&
                 Ask > currentTP + FreezeLevelDist)
            )){
                double newSL = isBuy ? NormalizeDouble(BeLockDist * PipFactor + openPrice, SymDigits) :
                                       NormalizeDouble(openPrice - BeLockDist * PipFactor, SymDigits);

                bool slImproved = isBuy ? (newSL > currentSL + Point() / 2.0) :
                                          (newSL < currentSL - Point() / 2.0);

                if ( slImproved && (isBuy ? (newSL < Bid - StopLevelDist) : (newSL > Ask + StopLevelDist)) ){
                    if ( InpEnableAuditLog )
                        PrintFormat("[AUDIT] PositionModify #%I64d | Reason: Breakeven | SL: %.2f -> %.2f | LockDist: %.2f",
                                    orderTicket, currentSL, newSL, BeLockDist * PipFactor);
                    currentSL = newSL;
                    trade.PositionModify(orderTicket, currentSL, currentTP);
                    modified = true;
                }
            }

            //--- 11. Market close if price touches currentSL
            VirtualSL = currentSL;

            if ( isBuy ? (SymbolInfoDouble(TradeSym, SYMBOL_BID) < currentSL) :
                         (SymbolInfoDouble(TradeSym, SYMBOL_ASK) > currentSL) ){
                if ( InpEnableAuditLog )
                    PrintFormat("[AUDIT] PositionClose #%I64d | Reason: TrailedSLHit | Quote: %.2f | SL: %.2f",
                                orderTicket,
                                isBuy ? SymbolInfoDouble(TradeSym, SYMBOL_BID) : SymbolInfoDouble(TradeSym, SYMBOL_ASK),
                                currentSL);
                trade.PositionClose(orderTicket, closeDeviation);
                return(true);
            }

            //--- 12. Update VirtualSLStore if changed
            if ( NormalizeDouble(effectiveSL, SymDigits) != NormalizeDouble(VirtualSL, SymDigits) ){
                newVSlValue = NormalizeDouble(VirtualSL, SymDigits);
                newVSlTicket = orderTicket;

                for (vSlSaveIdx = 0; vSlSaveIdx < VirtualSLStoreSize; vSlSaveIdx = vSlSaveIdx + 1){
                    if ( VirtualSLStore[vSlSaveIdx][0] == (double)newVSlTicket ){
                        VirtualSLStore[vSlSaveIdx][1] = newVSlValue;
                        break;
                    }
                }
            }

            if ( modified ){
                orderModified = true;
            }
        }
    }

    return(orderModified);
}

//+------------------------------------------------------------------+
//| PlaceEntry                                                       |
//+------------------------------------------------------------------+
bool PlaceEntry(bool isBuy) {
    if (!CanPlaceNewX9Entries()) return false;
    double intentSwing = isBuy ? SwingHigh : SwingLow;
    bool swingFound;
    double entryPrice;
    double slippageEntryPrice;
    double slPrice;
    double tpPrice;
    double swingPrice;
    int pendIdx;
    bool dupFound;
    int pendCount;
    int pendCountIdx;
    double worstPendingPrice;
    int pendScanIdx;
    double entryPriceCheck;
    int pendScanIdx2;
    bool betterPendingExists;
    bool volumeValid;
    int maxOrdersLimit;
    bool orderLimitOk;
    int lastErrorCode;
    double filledEntryPrice;
    long newTicket;
    ENUM_ORDER_TYPE_TIME pendTimeType;
    int mapSlot;
    int pendType;

    pendType = (int)(isBuy ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP);

    if ( isBuy ){
        FindSwingPoint(FractalTf, true);
        swingPrice = SwingHigh;
    }
    else{
        FindSwingPoint(FractalTf, false);
        swingPrice = SwingLow;
    }

    swingFound = false;
    dupFound = false;

    for (pendIdx = 0; ordinfo.SelectByIndex(pendIdx); pendIdx = pendIdx + 1){
        if ( ordinfo.Magic() != ActiveMagic ||
             ordinfo.Symbol() != TradeSym ||
             (int)ordinfo.OrderType() != pendType ||
             !(MathAbs(ordinfo.PriceOpen() - (isBuy ? (BuyEntryOffset * PipFactor + swingPrice) :
                      (swingPrice - SellEntryOffset * PipFactor))) < PendingDedupDist * PipFactor) )
            continue;
        dupFound = true;
        break;
    }

    if ( !(dupFound) ){
        pendCount = 0;

        for (pendCountIdx = 0; ordinfo.SelectByIndex(pendCountIdx); pendCountIdx = pendCountIdx + 1){
            if ( ordinfo.Magic() != ActiveMagic ||
                 ordinfo.Symbol() != TradeSym ||
                 (int)ordinfo.OrderType() != pendType )
                continue;
            pendCount = pendCount + 1;
        }

        if ( pendCount == MaxPendingOrders ){
            worstPendingPrice = isBuy ? DBL_MAX : 0.0;
            for (pendScanIdx = 0; ordinfo.SelectByIndex(pendScanIdx); pendScanIdx = pendScanIdx + 1){
                if ( ordinfo.Magic() != ActiveMagic ||
                     ordinfo.Symbol() != TradeSym ||
                     (int)ordinfo.OrderType() != pendType ||
                     (isBuy ? !(ordinfo.PriceOpen() < worstPendingPrice) :
                              !(ordinfo.PriceOpen() > worstPendingPrice)) )
                    continue;
                worstPendingPrice = ordinfo.PriceOpen();
            }
            if ( isBuy ){
                if ( SwingHigh > worstPendingPrice ){
                    return(false);
                }
            }
            else{
                if ( SwingLow < worstPendingPrice ){
                    return(false);
                }
            }
        }

        if ( isBuy ){
            swingFound = true;
            LastSwingHigh = NormalizeDouble(SwingHigh, SymDigits);
        }
        else{
            swingFound = true;
            LastSwingLow = NormalizeDouble(SwingLow, SymDigits);
        }
    }

    if ( isBuy ){
        if ( LastSwingHigh == 0.0 ){
            return(false);
        }
    }
    else{
        if ( LastSwingLow == 0.0 ){
            return(false);
        }
    }

    if ( swingFound ){
        if ( isBuy ){
            entryPrice = NormalizeDouble(LastSwingHigh + BuyEntryOffset * PipFactor, SymDigits);
        }
        else{
            entryPrice = NormalizeDouble(LastSwingLow - SellEntryOffset * PipFactor, SymDigits);
        }

        entryPriceCheck = entryPrice;
        betterPendingExists = false;

        for (pendScanIdx2 = 0; ordinfo.SelectByIndex(pendScanIdx2); pendScanIdx2 = pendScanIdx2 + 1){
            if ( ordinfo.Magic() != ActiveMagic ||
                 ordinfo.Symbol() != TradeSym ||
                 (int)ordinfo.OrderType() != pendType ||
                 (isBuy ? !(ordinfo.PriceOpen() <= entryPriceCheck) :
                          !(ordinfo.PriceOpen() >= entryPriceCheck)) )
                continue;
            betterPendingExists = true;
            break;
        }

        if ( betterPendingExists ){
            return(false);
        }

        ENUM_ORDER_TYPE marginOrderType = (isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
        double marginPrice = (isBuy ? SymbolInfoDouble(TradeSym, SYMBOL_ASK) :
                                      SymbolInfoDouble(TradeSym, SYMBOL_BID));
        double marginRequired = 0.0;

        if ( !OrderCalcMargin(marginOrderType, TradeSym, StrategyLots[StrategyIdx], marginPrice, marginRequired) ||
             AccountInfoDouble(ACCOUNT_MARGIN_FREE) - marginRequired <= 0.0 ){
            return(false);
        }

        if ( isBuy ){
            slippageEntryPrice = entryPrice;
            slPrice = NormalizeDouble(entryPrice - SLDist * PipFactor, SymDigits);
            tpPrice = NormalizeDouble(TPDist * PipFactor + entryPrice, SymDigits);
        }
        else{
            slippageEntryPrice = entryPrice;
            slPrice = NormalizeDouble(SLDist * PipFactor + entryPrice, SymDigits);
            tpPrice = NormalizeDouble(entryPrice - TPDist * PipFactor, SymDigits);
        }

        if ( StrategyLots[StrategyIdx] < SymbolInfoDouble(TradeSym, SYMBOL_VOLUME_MIN) ){
            volumeValid = false;
        }
        else{
            if ( StrategyLots[StrategyIdx] > SymbolInfoDouble(TradeSym, SYMBOL_VOLUME_MAX) ){
                volumeValid = false;
            }
            else{
                if ( MathAbs(NormalizeDouble(StrategyLots[StrategyIdx] / SymbolInfoDouble(TradeSym, SYMBOL_VOLUME_STEP), 0) *
                             SymbolInfoDouble(TradeSym, SYMBOL_VOLUME_STEP) - StrategyLots[StrategyIdx]) > 0.0000001 ){
                    volumeValid = false;
                }
                else{
                    volumeValid = true;
                }
            }
        }

        maxOrdersLimit = (int)AccountInfoInteger(ACCOUNT_LIMIT_ORDERS);
        if ( maxOrdersLimit == 0 ){
            orderLimitOk = true;
        }
        else{
            orderLimitOk = (PositionsTotal() + OrdersTotal()) < maxOrdersLimit;
        }

        if ( !(volumeValid) || !(orderLimitOk) ){
            return(false);
        }

        double fzDist = FreezeLevelDist;
        double stDist = StopLevelDist;

        if ( ( isBuy ? (SymbolInfoDouble(TradeSym, SYMBOL_ASK) < slippageEntryPrice - fzDist &&
                        SymbolInfoDouble(TradeSym, SYMBOL_ASK) < slippageEntryPrice - stDist) :

                       (SymbolInfoDouble(TradeSym, SYMBOL_BID) > fzDist + slippageEntryPrice &&
                        SymbolInfoDouble(TradeSym, SYMBOL_BID) > stDist + slippageEntryPrice) ) ){

            trade.SetExpertMagicNumber(ActiveMagic);
            trade.SetTypeFilling(ORDER_FILLING_RETURN);

            if ( PendingExpiryHrs > 0 ){
                PendingExpiry = TimeCurrent() + PendingExpirySeconds;
            }
            else{
                PendingExpiry = 0;
            }
            if ( Virtual_expiration ){
                PendingExpiry = 0;
            }

            pendTimeType = (PendingExpiry > 0) ? ORDER_TIME_SPECIFIED : ORDER_TIME_GTC;

            if ( trade.OrderOpen(TradeSym, isBuy ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP, StrategyLots[StrategyIdx], 0, slippageEntryPrice,
                                slPrice, tpPrice, pendTimeType, PendingExpiry, ActiveComment) ){
                LastTradeTicket = (int)trade.ResultOrder();
                if ( InpEnableAuditLog )
                    PrintFormat("[AUDIT] Placed %s Stop #%d | Vol: %.2f | Price: %.2f | SL: %.2f | TP: %.2f | Magic: %d",
                                isBuy ? "BUY" : "SELL", LastTradeTicket, StrategyLots[StrategyIdx], slippageEntryPrice, slPrice, tpPrice, ActiveMagic);
            }
            else{
                LastTradeTicket = -1;
            }

            if ( LastTradeTicket <= 0 ){
                lastErrorCode = GetLastError();
                if ( lastErrorCode == 132 ){
                    ResetLastError();
                }
            }
            else{
                filledEntryPrice = entryPrice;
                newTicket = LastTradeTicket;

                for (mapSlot = 0; mapSlot < 100; mapSlot = mapSlot + 1){
                    if ( !(OrderPriceMap[mapSlot][0] == 0.0) ) continue;
                    OrderPriceMap[mapSlot][0] = (double)newTicket;
                    OrderPriceMap[mapSlot][1] = filledEntryPrice;
                    break;
                }
            }
        }
        return(true);
    }
    return(false);
}
//+------------------------------------------------------------------+
