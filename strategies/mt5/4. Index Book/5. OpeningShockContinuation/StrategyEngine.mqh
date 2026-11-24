#property strict
#property tester_no_cache
#property version "1.00"
#property description "Independent USTEC strategy. Completed-bar decisions, cost-inclusive cash risk and owned-position recovery."
#include <Trade/Trade.mqh>
#ifndef OS_STRATEGY_CORE
#define OS_STRATEGY_CORE
// ORB_Scalper clock: live server/GMT detection; tester weekly-open anchor.
// No broker whitelist or fixed tester fallback.
const int CLOCK_UNKNOWN=100000;
int clockServerNY=0;
bool clockReady=false;
datetime clockObserved=0;
datetime clockWeeks[];
int clockWeekOffsets[];
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

datetime ClockNewYorkStamp(datetime srvTime)   // CSV/panel display only: the clock the strategy reasons in
{
   datetime utc=ClkStampToUtc(srvTime);
   return utc>0 ? ClkUtcToNy(utc) : srvTime;
}


// Seconds the server clock is ahead of New York at this stamp: the standard adapter owns the
// server -> UTC mapping, so this is the only clock decision left in the EA.
int OSServerNYOffsetSec(datetime stamp)
{
   if(!ClkOK()) return CLOCK_UNKNOWN;
   datetime utc=ClkStampToUtc(stamp);
   if(utc<=0) return CLOCK_UNKNOWN;
   return (int)((long)stamp-(long)ClkUtcToNy(utc));
}
bool OSClockRefresh(datetime stamp)
{
   ClkRefresh(stamp);
   bool ready=ClkOK();
   int offset=ready ? OSServerNYOffsetSec(stamp) : CLOCK_UNKNOWN;
   if(offset==CLOCK_UNKNOWN) ready=false;
   bool announce=!clockReady || offset!=clockServerNY;
   clockReady=ready;
   if(!ready) return false;
   if(announce) PrintFormat("OS_CLOCK_READY serverAheadOfNYMinutes=%d source=%s",offset/60,ClkSource());
   clockServerNY=offset;clockObserved=stamp;return true;
}
datetime OSNewYorkAtOffset(datetime server,int offset){return server-offset;}
datetime OSSessionAtOffset(datetime centralDay,int minute,int offset){return centralDay+offset+3600+minute*60;}
datetime OSNewYork(datetime server)
{
   int offset=OSServerNYOffsetSec(server);
   return offset==CLOCK_UNKNOWN ? 0 : OSNewYorkAtOffset(server,offset);
}
datetime OSNewYorkUTC(datetime utc){return ClkUtcToNy(utc);}
datetime OSCentralUTC(datetime utc){return utc+ClkNyUtcOffset(utc-3600)-3600;}
datetime OSClockUTC(datetime server){return ClkStampToUtc(server);}
datetime OSCentral(datetime server){datetime utc=OSClockUTC(server);return utc>0 ? OSCentralUTC(utc) : 0;}
datetime OSSessionTime(datetime centralDay,int minute=0)
{
   int offset=OSServerNYOffsetSec(centralDay+minute*60+clockServerNY+3600);
   if(offset==CLOCK_UNKNOWN && clockReady && MathAbs((double)(centralDay-TimeCurrent()))<3*86400) offset=clockServerNY;
   if(offset==CLOCK_UNKNOWN) return 0;
   datetime result=OSSessionAtOffset(centralDay,minute,offset);
   int resolved=OSServerNYOffsetSec(result);
   return OSSessionAtOffset(centralDay,minute,resolved==CLOCK_UNKNOWN ? offset : resolved);
}

datetime OSDay(datetime server)
{
   MqlDateTime p; TimeToStruct(OSCentral(server),p);
   p.hour=0; p.min=0; p.sec=0;
   return StructToTime(p);
}
int OSMinute(datetime server)
{
   MqlDateTime p; TimeToStruct(OSCentral(server),p);
   return p.hour*60+p.min;
}
bool OSAllowed(datetime server) {return server>0;} // No research-date lock
bool OSEligible(int minute,int cutoff) {return minute>=0 && minute<cutoff;}
datetime OSCalendarDate(int y,int m,int d)
{
   MqlDateTime p={};p.year=y;p.mon=m;p.day=d;return StructToTime(p);
}
int OSCalendarWeekday(datetime t){MqlDateTime p;TimeToStruct(t,p);return p.day_of_week;}
datetime OSObserved(datetime t)
{
   int w=OSCalendarWeekday(t);return t+(w==6 ? -86400 : w==0 ? 86400 : 0);
}
datetime OSMonday(int y,int month,int n)
{
   datetime t=OSCalendarDate(y,month,1);
   return t+((8-OSCalendarWeekday(t))%7+7*(n-1))*86400;
}
bool OSFutureSpecialDay(datetime d)
{
   MqlDateTime p;TimeToStruct(d,p);int y=p.year;
   datetime mayEnd=OSCalendarDate(y,6,1)-86400;
   datetime memorial=mayEnd-((OSCalendarWeekday(mayEnd)+6)%7)*86400;
   // Gregorian Easter, then Good Friday. Calendar-only; no market-data inputs.
   int a=y%19,b=y/100,c=y%100,e=b%4,f=(b+8)/25,g=(b-f+1)/3;
   int h=(19*a+b-b/4-g+15)%30,i=c/4,k=c%4,l=(32+2*e+2*i-h-k)%7;
   int m=(a+11*h+22*l)/451,n=h+l-7*m+114;
   datetime friday=OSCalendarDate(y,n/31,n%31+1)-2*86400;
   datetime nov=OSCalendarDate(y,11,1);
   datetime thanks=nov+((11-OSCalendarWeekday(nov))%7+21)*86400;
   return d==OSObserved(OSCalendarDate(y,1,1)) || d==OSMonday(y,1,3)
      || d==OSMonday(y,2,3) || d==friday || d==memorial
      || d==OSObserved(OSCalendarDate(y,6,19)) || d==OSCalendarDate(y,7,3)
      || d==OSObserved(OSCalendarDate(y,7,4)) || d==OSMonday(y,9,1)
      || d==thanks || d==thanks+86400 || d==OSCalendarDate(y,12,24)
      || d==OSObserved(OSCalendarDate(y,12,25)) || d==OSCalendarDate(y,12,31);
}
// The US DST rule is owned by CLK-CORE 1.2, not by this EA. The standard implements the same rule
// this function used to hand-write (2nd Sunday March 07:00 UTC .. 1st Sunday November 06:00 UTC) and
// is verified against 60 IANA transitions 2006-2036 in EA_Standards/tests/mql5. Keeping the name
// leaves every call site untouched; the value is 2 (winter) or 3 (summer) exactly as before.
// Server offset in whole hours at this UTC instant, from the resolved standard clock. Was a
// hard-coded 3/2 US-DST table; any broker, any rule, and a dated schedule all work now.
int OSExpectedBrokerUTC(datetime utc)
{
   // Before the adapter resolves (OnInit self-tests, a chart with no history yet) answer with the
   // US rule the strategy was written against; the resolved clock takes over from the first tick.
   if(!ClkOK()) return ClkNyUtcOffset(utc)==-4*3600 ? 3 : 2;
   return (int)(((long)ClkUtcToServer(utc,ClkRule(),ClkBase())-(long)utc)/3600);
}
bool OSCalendarSelfTest()
{
   return OSNewYorkAtOffset(D'2022.01.24 08:00',7*3600)==D'2022.01.24 01:00'
      && OSNewYorkAtOffset(D'2022.01.24 08:00',8*3600)==D'2022.01.24 00:00'
      && OSNewYorkAtOffset(D'2022.07.12 08:00',7*3600)==D'2022.07.12 01:00'
      && OSNewYorkAtOffset(D'2022.07.12 08:00',8*3600)==D'2022.07.12 00:00'
      && OSSessionAtOffset(D'2022.01.24',510,7*3600)==D'2022.01.24 16:30'
      && OSSessionAtOffset(D'2022.07.12',600,7*3600)==D'2022.07.12 18:00'
      && OSSessionAtOffset(D'2022.07.12',870,7*3600)==D'2022.07.12 22:30'
      && OSSessionAtOffset(D'2022.07.12',0,7*3600)==D'2022.07.12 08:00'
      && OSFutureSpecialDay(D'2026.04.03') && OSFutureSpecialDay(D'2027.03.26')
      && OSFutureSpecialDay(D'2026.11.26') && OSFutureSpecialDay(D'2026.11.27')
      && !OSFutureSpecialDay(D'2026.11.25')
      && (int)(((long)ClkUtcToServer(D'2026.03.08 06:59:59',CLK_RULE_US,120)-(long)D'2026.03.08 06:59:59')/3600)==2
      && (int)(((long)ClkUtcToServer(D'2026.03.08 07:00:00',CLK_RULE_US,120)-(long)D'2026.03.08 07:00:00')/3600)==3
      && (int)(((long)ClkUtcToServer(D'2026.11.01 05:59:59',CLK_RULE_US,120)-(long)D'2026.11.01 05:59:59')/3600)==3
      && (int)(((long)ClkUtcToServer(D'2026.11.01 06:00:00',CLK_RULE_US,120)-(long)D'2026.11.01 06:00:00')/3600)==2
      && OSNewYorkUTC(D'2026.03.08 06:59:59')==D'2026.03.08 01:59:59'
      && OSNewYorkUTC(D'2026.03.08 07:00:00')==D'2026.03.08 03:00:00'
      && OSCentralUTC(D'2026.03.08 07:59:59')==D'2026.03.08 01:59:59'
      && OSCentralUTC(D'2026.03.08 08:00:00')==D'2026.03.08 03:00:00'
      && OSNewYorkUTC(D'2026.11.01 06:00:00')==D'2026.11.01 01:00:00'
      && OSCentralUTC(D'2026.11.01 07:00:00')==D'2026.11.01 01:00:00';
}
int OSSessionCutoff(datetime server,int model)
{
   // Policy v1: 11:55 Central on published US cash-market holidays/early
   // closes, plus conservative Christmas Eve and year-end handling.
   // This is an earlier research deadline, not the CFD's exact close time.
   string dates=
      "|2020.01.01|2020.01.20|2020.02.17|2020.04.10|2020.05.25|2020.07.03|2020.09.07|2020.11.26|2020.11.27|2020.12.24|2020.12.25|2020.12.31"
      "|2021.01.01|2021.01.18|2021.02.15|2021.04.02|2021.05.31|2021.07.05|2021.09.06|2021.11.25|2021.11.26|2021.12.24|2021.12.31"
      "|2022.01.17|2022.02.21|2022.04.15|2022.05.30|2022.06.20|2022.07.04|2022.09.05|2022.11.24|2022.11.25|2022.12.24|2022.12.26|2022.12.31"
      "|2023.01.02|2023.01.16|2023.02.20|2023.04.07|2023.05.29|2023.06.19|2023.07.03|2023.07.04|2023.09.04|2023.11.23|2023.11.24|2023.12.24|2023.12.25|2023.12.31"
      "|2024.01.01|2024.01.15|2024.02.19|2024.03.29|2024.05.27|2024.06.19|2024.07.03|2024.07.04|2024.09.02|2024.11.28|2024.11.29|2024.12.24|2024.12.25|2024.12.31"
      "|2025.01.01|2025.01.09|2025.01.20|2025.02.17|2025.04.18|2025.05.26|2025.06.19|2025.07.03|2025.07.04|2025.09.01|2025.11.27|2025.11.28|2025.12.24|2025.12.25|2025.12.31|";
   if(StringFind(dates,"|"+TimeToString(OSDay(server),TIME_DATE)+"|")>=0) return 715;
   if(OSDay(server)>=D'2026.01.01' && OSFutureSpecialDay(OSDay(server))) return 715;
   return model==3 ? 895 : model==4 ? 1440 : model==1 ? 955 : 870;
}
int OSBias(double open,double low,double high)
{
   if(high<=low || open<=low || open>=high) return 0;
   if(open>low+2*(high-low)/3) return 1;
   if(open<low+(high-low)/3) return -1;
   return 0;
}
bool OSBracket(int side,double entry,double stop,double target)
{
   return side*(entry-stop)>0 && side*(target-entry)>0;
}
int OSTradeCap(int model) {return model==2 ? 1 : 3;}
// Closed M1 long-side path. A double touch resolves as stop first.
int OSVirtualExit(double low,double high,double stop,double target)
{
   if(low<=stop) return -1;
   if(high>=target) return 1;
   return 0;
}
bool OSCanEnter(int minute,int start,int cutoff,int count,int cap)
{
   return minute>=start && OSEligible(minute,cutoff) && count<cap;
}
int OSSignalSide(int model,int direction,double close,double high,double low,double adx)
{
   if(model!=2 || adx<=20) return 0;
   if(direction==1 && close>high) return 1;
   if(direction==-1 && close<low) return -1;
   return 0;
}
#endif
#ifndef OS_STRATEGY_BAR_TRAIL
#define OS_STRATEGY_BAR_TRAIL
// Original R = actual fill to original stop. Only completed M1 closes advance peak.
bool OSBarTrailLock(double peakR,double activateR,double distanceR,double stepR,double &lockR)
{
   if(activateR<=0 || distanceR<=0 || stepR<=0 || peakR<activateR) return false;
   lockR=activateR+MathFloor((peakR-activateR)/stepR+1e-9)*stepR-distanceR;
   return true;
}
bool OSBarTrailSelfTest()
{
   double lock=0;
   if(OSBarTrailLock(1.499,1.5,1.5,.5,lock)) return false;
   double peaks[]={1.5,1.999,2.0,2.499,2.5,3.0};
   double expected[]={0.0,0.0,.5,.5,1.0,1.5};
   for(int i=0;i<ArraySize(peaks);i++)
      if(!OSBarTrailLock(peaks[i],1.5,1.5,.5,lock) || MathAbs(lock-expected[i])>1e-9) return false;
   return !OSBarTrailLock(2.0,1.5,1.5,0,lock)
      && OSVirtualExit(99,111,100,110)==-1
      && OSVirtualExit(100,109,100,110)==-1
      && OSVirtualExit(101,110,100,110)==1
      && OSVirtualExit(101,109,100,110)==0;
}
#endif

enum OSModel { VaultBreak=0, VWAPPullback=1, OvernightBiasRangeBreakout=2, OpeningShock=3, PostCloseFade=4 };
enum OSGeometry { SourceGeometry=0, ATRGeometry=1 };
enum OSManagement { FixedBracket=0, VWAPClose=1, CostCoveredBE=2, ATRTrail=3, M1RStep=4 };
const OSModel Model=OpeningShock;
#ifndef OS_STRATEGY_PRODUCTION_INPUTS
#define OS_STRATEGY_PRODUCTION_INPUTS

input group "==========  1 - Trading  =========="
input bool   EnableTrading       = false; // v7: paper/test only until explicitly enabled  // Enable new trades (open trades stay protected when off)

input group " "
input group "==========  2 - Risk  =========="
input double RiskMoney           = 100.0; // Risk per trade, including costs (account currency)
input bool   UseFixedSize        = false; // Use fixed lots instead of the cash risk budget
input double FixedLots           = 1.0;   // Lots per trade when fixed sizing is enabled
input bool   EnforceFixedSizeRiskCap = true; // Fixed lots also subject to RiskMoney; prevents accidental oversizing

input group "  "
input group "==========  3 - Trading Costs  =========="
input double CommissionPerLot    = 7.0;   // Fallback round-trip commission per lot until broker history is available
input int    SlippagePoints      = 3;     // Slippage/side (3=0.03 if broker Point=0.01)

// Frozen strategy rules: not user-facing options or alternate models.
const int ATRPeriod=15,ADXPeriod=14;
const double NoiseFraction=0.30,StopPoints=60.0,TargetPoints=40.0,TargetR=0.6666666666666666;
const int OvernightStart=0,VaultAttemptCap=3,OSStateRevision=2;
const bool SyntheticFirst=false;
const OSManagement Management=FixedBracket;
const double BarTrailActivateR=1.5,BarTrailDistanceR=1.5;
const string OSDisplayName="Opening Shock Continuation";

input group "   "
input group "==========  4 - Display  =========="
input bool   ShowVisuals         = true;  // Show chart levels, trade markers and information

input group "    "
input group "==========  5 - Execution & Logging  =========="
const ulong  MagicNumber         = 91008031; // Fixed model identity; preserves owned-position recovery
input bool   WriteTradeLog       = false; // Write a detailed trade and decision log


// Private adapter to the existing, validated execution engine.
const int StartMinute=540;
const double RiskCash=RiskMoney,CommissionRTPerLot=CommissionPerLot,SlipPrice=SlippagePoints*_Point;
const ulong Magic=MagicNumber;
const bool DetailedLog=WriteTradeLog;
const OSGeometry Geometry=SourceGeometry;
const double BreakEvenR=0.5,TrailR=1.0,BarTrailStepR=0.5;
string RunId="";
#endif

const string OSOutputFamily="OpeningShock";
const string OSOutputRoot=OSOutputFamily+"/logs";
void OSPrepareOutput()
{
   FolderCreate(OSOutputFamily,FILE_COMMON);
   FolderCreate(OSOutputRoot,FILE_COMMON);
}

CTrade trade;
int atrHandle=INVALID_HANDLE, adxHandle=INVALID_HANDLE, ledger=INVALID_HANDLE;
ENUM_TIMEFRAMES sourceTF=PERIOD_M30;
datetime lastMinute=0,lastSignal=0,day=0;
double averageATR=0,midnight=0,orHigh=0,orLow=0,overnightHigh=0,overnightLow=0;
double sumPV=0,sumV=0,vwap=0,initialRisk=0,modelCost=0,totalCost=0;
double modelCostPerLot=0,entryCommissionPerLot=0;
datetime lastVWAP=0;
datetime ownedEntryTime=0;
int overnightExits=0;
string carryDetails="";
int bias=0,entries=0,daysReady=0,daysRejected=0,invalidBrackets=0,failedOrders=0;
bool rangeReady=false,armed=false,touched=false,waitingFresh=false,dayValid=false,beDone=false;
bool previousORAbove=false;
bool dayWaiting=false,dayRejected=false;
string dataWaitReason="";
bool virtualActive=false;
double virtualStop=0,virtualTarget=0;
datetime virtualStart=0;
datetime virtualLastBar=0;
int virtualStarts=0,virtualStops=0,virtualTargets=0,virtualCollisions=0;
int virtualExpired=0,virtualGaps=0;
double barPeakR=0;
double yearProfit[7],worstRisk=0,netWins=0,netLosses=0,adjustedPeak=0,adjustedDD=0;
int yearTrades[7];
int resultsFile=INVALID_HANDLE;
double dailyNet[2557];
string rejectedDetails="";
#ifdef OS_VISUAL_PROBE
bool osPreviewRequested=false;
ulong osPreviewRequestedMs=0;
#endif
#include "ChartVisuals.mqh"
#include "ExecutionRuntime.mqh"

bool OwnPosition()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket>0 && PositionGetString(POSITION_SYMBOL)==_Symbol && (ulong)PositionGetInteger(POSITION_MAGIC)==Magic)
         return true;
   }
   return false;
}
bool DateAllowed(datetime t)
{
   return true; // Tester dates belong to MT5; live operation has no research-stage lock.
}
double RoundPrice(double price)
{
   double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   return NormalizeDouble(MathRound(price/tick)*tick,_Digits);
}
void CloseOwned(string why)
{
   if(!MQLInfoInteger(MQL_TESTER) && !OSRuntimeAccountContextValid()){OSDraw();return;}
   if(!MQLInfoInteger(MQL_TESTER) && !TerminalInfoInteger(TERMINAL_CONNECTED)) return;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket>0 && PositionGetString(POSITION_SYMBOL)==_Symbol && (ulong)PositionGetInteger(POSITION_MAGIC)==Magic)
      {
         if(!RecoveryCloseBegin(OSStateKey(),ticket))continue;
         bool closed=trade.PositionClose(ticket);uint ret=trade.ResultRetcode();
         RecoveryCloseResult(OSStateKey(),ret,trade.ResultOrder());
         if(!closed || (ret!=TRADE_RETCODE_DONE && ret!=TRADE_RETCODE_DONE_PARTIAL))
         { failedOrders++; PrintFormat("OS_CLOSE_REJECT %s ret=%u",why,trade.ResultRetcode()); }
      }
   }
}
void Note(string kind,string text)
{
   if(kind=="RECOVERY_BLOCK")Print("VB RECOVERY ATTENTION: ",text);
   if(DetailedLog && ledger!=INVALID_HANDLE)
   {
      FileWrite(ledger,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),kind,text);
      FileFlush(ledger); // Make decision events readable during visual tester diagnostics too.
   }
}
bool M1HistoryAvailable(datetime from)
{
   if(!MQLInfoInteger(MQL_TESTER) && !TerminalInfoInteger(TERMINAL_CONNECTED)) return false;
   long first=SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_FIRSTDATE);
   if(first<=0 || first>from || !SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_SYNCHRONIZED))
   {
      MqlRates preceding[];
      CopyRates(_Symbol,PERIOD_M1,from-86400,from,preceding); // Request the boundary's preceding history; retry asynchronously.
      return false;
   }
   return SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_SYNCHRONIZED) && first>0 && first<=from;
}
bool NativeBarsValid(MqlRates &bars[],datetime from,datetime to)
{
   int n=ArraySize(bars);
   if(n<=0 || bars[0].time<from || bars[n-1].time>=to) return false;
   for(int i=0;i<n;i++)
   {
      if((i>0 && bars[i].time<=bars[i-1].time) || !MathIsValidNumber(bars[i].open)
         || !MathIsValidNumber(bars[i].high) || !MathIsValidNumber(bars[i].low)
         || !MathIsValidNumber(bars[i].close) || bars[i].low>bars[i].high
         || bars[i].open<bars[i].low || bars[i].open>bars[i].high
         || bars[i].close<bars[i].low || bars[i].close>bars[i].high) return false;
   }
   return true;
}
bool Window(datetime from,datetime to,MqlRates &bars[],int minimum)
{
   ArraySetAsSeries(bars,false);
   if(to<=from || !M1HistoryAvailable(from)) return false;
   int n=CopyRates(_Symbol,PERIOD_M1,from,to-60,bars);
   // Native minute series omit minutes without a trade/quote. Use observed bars only.
   return n>0 && NativeBarsValid(bars,from,to);
}
bool OpeningPrice(datetime anchor,int minutes,double &price)
{
   if(!M1HistoryAvailable(anchor)) return false;
   datetime last=(datetime)MathMin((double)(anchor+(minutes-1)*60),(double)((long)TimeCurrent()/60*60));
   if(last<anchor) return false;
   MqlRates bars[];ArraySetAsSeries(bars,false);
   int n=CopyRates(_Symbol,PERIOD_M1,anchor,last,bars);
   if(n<=0 || !NativeBarsValid(bars,anchor,anchor+minutes*60)) return false;
   price=bars[0].open; // First observed trade in the nominal opening interval.
   return true;
}
bool RejectDay(string reason)
{
   if(!dayRejected){dayRejected=true;daysRejected++;}
   dayWaiting=true;
   if(dataWaitReason!=reason)
   {
      dataWaitReason=reason;
      rejectedDetails+=TimeToString(day,TIME_DATE)+","+reason+"\r\n";
      PrintFormat("VB DATA_WAIT day=%s reason=%s synchronized=%d firstM1=%s; retrying, protection active",
         TimeToString(day,TIME_DATE),reason,(int)SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_SYNCHRONIZED),
         TimeToString((datetime)SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_FIRSTDATE),TIME_DATE|TIME_MINUTES));
   }
   return false;
}
void ResetDay(datetime now)
{
   day=OSDay(now); entries=0; rangeReady=false; armed=false; touched=false;
   osLastEntry=0;osLastStop=0;osLastTarget=0;osLastBracketTime=0;
   if(OSVisualEnabled()) ObjectsDeleteAll(0,OSVisualPrefix());
   waitingFresh=false; previousORAbove=false; bias=0; beDone=false;
   virtualActive=false;virtualStart=0;virtualLastBar=0;vbVirtualExitTime=0;
   sumPV=0;sumV=0;vwap=0;lastVWAP=0;lastSignal=0;averageATR=0;
   dayValid=false;dayRejected=false;dataWaitReason=""; // Preserve an outstanding history/connection wait across the day boundary.
}
// Model daily candles end at 17:00 New York, independent of broker midnight.
bool OSATRMean(MqlRates &daily[],int period,double &mean)
{
   int n=ArraySize(daily);mean=0;
   if(n<period+15) return false;
   for(int end=n-1;end>=n-15;end--)
   {
      double atr=0;
      for(int i=end-period+1;i<=end;i++)
      {
         if(daily[i].high<daily[i].low || daily[i-1].close<=0) return false;
         double tr=MathMax(daily[i].high-daily[i].low,
            MathMax(MathAbs(daily[i].high-daily[i-1].close),MathAbs(daily[i].low-daily[i-1].close)));
         if(!MathIsValidNumber(tr)) return false;
         atr+=tr/period;
      }
      mean+=atr/15.0;
   }
   return mean>0 && MathIsValidNumber(mean);
}
bool OSSessionATRMean(datetime sessionDay,double &mean,bool datedVisual=false)
{
   static datetime cachedDay=0;
   static double cachedMean=0;
   if(!datedVisual && cachedDay==sessionDay && cachedMean>0){mean=cachedMean;return true;}
   // Preserve native results on feeds whose D1 candles already use the model close.
   bool aligned=true;
   for(int i=1;i<=ATRPeriod+15;i++)
   {
      datetime open=iTime(_Symbol,PERIOD_D1,i),ny=OSNewYork(open);
      if(open<=0 || ny<=0 || (long)ny%86400!=17*3600){aligned=false;break;}
   }
   if(aligned)
   {
      double values[];mean=0;
      int shift=datedVisual ? iBarShift(_Symbol,PERIOD_D1,OSSessionTime(sessionDay),false)+1 : 1;
      if(shift<1 || CopyBuffer(atrHandle,0,shift,15,values)!=15) return false;
      for(int i=0;i<15;i++)
      {
         if(values[i]<=0 || !MathIsValidNumber(values[i])) return false;
         mean+=values[i]/15.0;
      }
   }
   else
   {
      // H1 OHLC preserves a daily high/low/close at an hour-aligned rollover.
      // Use M1 on fractional-hour server zones so no bar crosses that rollover.
      ENUM_TIMEFRAMES tf=clockServerNY%3600==0 ? PERIOD_H1 : PERIOD_M1;
      datetime finish=OSSessionTime(sessionDay-86400,960);
      datetime begin=finish-90*86400;
      if(begin<=0 || finish<=begin) return false;
      MqlRates source[],daily[];ArraySetAsSeries(source,false);
      int count=CopyRates(_Symbol,tf,begin,finish-1,source);
      if(count<=0 || !SeriesInfoInteger(_Symbol,tf,SERIES_SYNCHRONIZED)) return false;
      datetime previous=0;
      for(int i=0;i<count;i++)
      {
         datetime local=OSCentral(source[i].time);
         if(local<=0) return false;
         MqlDateTime d;TimeToStruct(local,d);
         bool afterClose=d.hour>=16;d.hour=0;d.min=0;d.sec=0;
         datetime key=StructToTime(d)+(afterClose ? 86400 : 0);
         if(key>=sessionDay) continue;
         if(key!=previous)
         {
            int n=ArraySize(daily);ArrayResize(daily,n+1);
            daily[n]=source[i];daily[n].time=key;previous=key;
         }
         else
         {
            int n=ArraySize(daily)-1;
            daily[n].high=MathMax(daily[n].high,source[i].high);
            daily[n].low=MathMin(daily[n].low,source[i].low);daily[n].close=source[i].close;
         }
      }
      // The first bucket may start partway through a day; only its closing price seeds TR.
      if(!OSATRMean(daily,ATRPeriod,mean)) return false;
   }
   if(!datedVisual){cachedDay=sessionDay;cachedMean=mean;}return true;
}
// Rolling historical RTH range. All bars must precede today's signal.
// A second one-session lag is applied to the post-close model.
bool OSResearchRange(datetime sessionDay,int lookback,int extraLag,double &result)
{
   double ranges[];ArrayResize(ranges,0);
   for(int days=1;days<=75 && ArraySize(ranges)<lookback+extraLag;days++)
   {
      datetime d=sessionDay-days*86400;MqlDateTime dt;TimeToStruct(d,dt);
      if(dt.day_of_week==0 || dt.day_of_week==6)continue;
      datetime from=OSSessionTime(d,510),to=OSSessionTime(d,900);
      if(from<=0 || to<=from)continue;
      MqlRates bars[];ArraySetAsSeries(bars,false);
      int n=CopyRates(_Symbol,PERIOD_M1,from,to-60,bars);
      // Full 09:30-16:00 ET RTH only. A missing minute makes the daily reference ineligible.
      if(n!=390 || bars[0].time!=from || bars[389].time!=to-60 || !NativeBarsValid(bars,from,to))continue;
      bool complete=true;
      for(int k=1;k<390;k++) if(bars[k].time != bars[k-1].time+60){complete=false;break;}
      if(!complete)continue;
      double high=bars[0].high,low=bars[0].low;
      for(int k=1;k<n;k++){high=MathMax(high,bars[k].high);low=MathMin(low,bars[k].low);}
      if(high<=low)continue;
      int z=ArraySize(ranges);ArrayResize(ranges,z+1);ranges[z]=high-low;
   }
   if(ArraySize(ranges)<(lookback==20 ? 15 : lookback+extraLag))return false;
   int used=MathMin(lookback,ArraySize(ranges)-extraLag);
   double sum=0;for(int i=extraLag;i<extraLag+used;i++)sum+=ranges[i];
   result=sum/used;return result>0;
}

// Return the completed 1-minute close at one specified Central civil minute.
bool OSResearchClose(datetime d,int minute,double &value)
{
   datetime time=OSSessionTime(d,minute);
   MqlRates b[];if(time<=0 || CopyRates(_Symbol,PERIOD_M1,time,1,b)!=1 || b[0].time!=time)return false;
   value=b[0].close;return true;
}

bool NewDay(datetime now)
{
   averageATR=0;
   int need=(Model==OpeningShock ? 20 : 15),lag=(Model==OpeningShock ? 0 : 1);
   if(!OSResearchRange(day,need,lag,averageATR))return RejectDay("RTH_RANGE_HISTORY_NOT_READY");
   datetime anchor=OSSessionTime(day,510);
   if(!OpeningPrice(anchor,2,midnight))return RejectDay("RTH_OPEN_NOT_READY");
   Note("DAY",StringFormat("referenceRange=%f RTH=%f model=%d",averageATR,midnight,(int)Model));
   if(dayRejected){daysRejected--;dayRejected=false;}
   dayWaiting=false;dataWaitReason="";return true;
}

void UpdateVWAP(datetime now)
{
   datetime begin=(lastVWAP>0 ? lastVWAP+60 : OSSessionTime(day));
   if(begin>now-60) return;
   MqlRates b[];ArraySetAsSeries(b,false);
   int n=CopyRates(_Symbol,PERIOD_M1,begin,now-60,b);
   if(n<=0) return;
   for(int i=0;i<n;i++)
   {
      double volume=(double)(b[i].real_volume>0 ? b[i].real_volume : b[i].tick_volume);
      sumPV+=(b[i].high+b[i].low+b[i].close)/3.0*volume;sumV+=volume;
      lastVWAP=b[i].time;
      // Plot at the completed candle's chart timestamp; this does not advance its signal availability.
      if(sumV>0) OSDrawVWAP(b[i].time,sumPV/sumV);
   }
   if(sumV>0) vwap=sumPV/sumV;
}
bool SetRange(datetime now)
{
   // Neither strategy uses a constructed breakout band; trade setup has its own deterministic window.
   return true;
}

double OSRequestedVolume(bool fixedSize,double lots,double budget,double unitRisk,double step,double minimum,double maximum)
{
   if(unitRisk<=0 || !MathIsValidNumber(unitRisk) || step<=0 || minimum<=0 || maximum<minimum) return 0;
   if(fixedSize)
   {
      if(!MathIsValidNumber(lots) || lots<minimum || lots>maximum || MathAbs(lots/step-MathRound(lots/step))>1e-7) return 0;
      return lots;
   }
   return MathMin(MathFloor(budget/unitRisk/step+1e-9)*step,maximum);
}
string OSSizingLabel()
{return UseFixedSize ? "Lots "+DoubleToString(FixedLots,4) : "Risk "+DoubleToString(RiskMoney,2);}
bool Open(int side,double stop,double target,double distance)
{
   MqlTick q;if(!SymbolInfoTick(_Symbol,q)) return false;
   double entry=(side==1 ? q.ask : q.bid);
   if(distance>0) {stop=entry-side*distance;target=entry+side*distance*TargetR;}
   stop=RoundPrice(stop);target=RoundPrice(target);
   if(!OSBracket(side,entry,stop,target)) {invalidBrackets++;Note("INVALID_BRACKET",StringFormat("%d %f %f %f",side,entry,stop,target));return false;}
   double loss=0;
   if(!OrderCalcProfit(side==1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,_Symbol,1.0,entry,stop,loss)) return false;
   double commission=OSCommissionEstimate();
   double friction=commission;
   double slipLoss=0;
   if(!OrderCalcProfit(ORDER_TYPE_BUY,_Symbol,1.0,entry,entry-2*SlipPrice,slipLoss)) return false;
   friction+=MathAbs(slipLoss);
   double unitRisk=MathAbs(loss)+friction;
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP),minimum=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   if(unitRisk<=0 || !MathIsValidNumber(unitRisk) || step<=0 || minimum<=0) {Note("RISK_INVALID","Invalid cash risk or volume contract");return false;}
   double volume=OSRequestedVolume(UseFixedSize,FixedLots,RiskCash,unitRisk,step,minimum,SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX));
   if(volume<minimum || unitRisk<=0) {Note(UseFixedSize ? "FIXED_LOTS_INVALID" : "RISK_TOO_SMALL",DoubleToString(unitRisk*minimum,2));return false;}
   if(UseFixedSize && EnforceFixedSizeRiskCap && volume*unitRisk>RiskCash+0.01)
   {Note("FIXED_RISK_REJECT",StringFormat("planned=%.2f budget=%.2f",volume*unitRisk,RiskCash));return false;}
   double stops=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
   if(side*(entry-stop)<stops || side*(target-entry)<stops){invalidBrackets++;return false;}
   entryCommissionPerLot=commission;modelCostPerLot=friction;
   if(!OSRuntimeEntryAllowed(entry,stop,target,volume,side)) {Note("ENTRY_BLOCK","EA safety, clock, margin or terminal gate");return false;}
   string comment=MQLInfoInteger(MQL_TESTER) ? OSDisplayName : "VB#"+IntegerToString((long)runtimeIntentNonce);
   bool ok=(side==1 ? trade.Buy(volume,_Symbol,0,stop,target,comment) : trade.Sell(volume,_Symbol,0,stop,target,comment));
   uint ret=trade.ResultRetcode();
   if(!ok || (ret!=TRADE_RETCODE_DONE && ret!=TRADE_RETCODE_DONE_PARTIAL))
   {
      failedOrders++;Note("ENTRY_REJECT",IntegerToString((int)ret));
      if(!MQLInfoInteger(MQL_TESTER)){entries++;runtimeBlocked=true;OSStateSave();}
      return false;
   }
   initialRisk=MathAbs(trade.ResultPrice()-stop);beDone=false;barPeakR=0;
   double filledVolume=trade.ResultVolume()>0 ? trade.ResultVolume() : volume;
   entryCommissionPerLot=commission;modelCostPerLot=friction;modelCost=friction*filledVolume;totalCost+=modelCost;ownedEntryTime=TimeCurrent();
   entries++;worstRisk=MathMax(worstRisk,unitRisk*volume);
   OSRememberBracket(trade.ResultPrice(),stop,target);
   OSDrawFill(side,TimeCurrent(),trade.ResultPrice(),"Entry");
   OSRuntimeFilled(side,stop,friction);
   Note("ENTRY",StringFormat("model=%d side=%d lots=%f fill=%f sl=%f tp=%f vwap=%f atr=%f count=%d modeledCost=%f",Model,side,volume,trade.ResultPrice(),stop,target,vwap,averageATR,entries,modelCost));
   return true;
}
void Manage()
{
   if(Management==M1RStep) return;
   if(Management<CostCoveredBE || !OwnPosition() || initialRisk<=0) return;
   MqlTick q;SymbolInfoTick(_Symbol,q);
   int side=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY ? 1 : -1);
   double entry=PositionGetDouble(POSITION_PRICE_OPEN),sl=PositionGetDouble(POSITION_SL),tp=PositionGetDouble(POSITION_TP);
   double current=(side==1 ? q.bid : q.ask);
   double favorable=side*(current-entry);
   double desired=sl;
   if(Management==CostCoveredBE && !beDone && favorable>=BreakEvenR*initialRisk)
   {
      double volume=PositionGetDouble(POSITION_VOLUME),unit=0;
      if(!OrderCalcProfit(ORDER_TYPE_BUY,_Symbol,1.0,entry,entry+1,unit)) return;
      desired=entry+side*(unit!=0 ? modelCost/volume/MathAbs(unit) : 0);
   }
   if(Management==ATRTrail && favorable>=TrailR*initialRisk) desired=current-side*averageATR*NoiseFraction;
   desired=RoundPrice(desired);
   if(side*(desired-sl)<=0 || side*(current-desired)<=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point) return;
   if(trade.PositionModify((ulong)PositionGetInteger(POSITION_TICKET),desired,tp)) {beDone=true;Note("STOP_CHANGE",DoubleToString(desired,_Digits));}
}
void ManageClosedMinute()
{
   if(Management!=M1RStep || !OwnPosition() || initialRisk<=0) return;
   MqlRates b[];
   if(CopyRates(_Symbol,PERIOD_M1,1,1,b)!=1 || b[0].time+60<=ownedEntryTime) return;
   int side=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY ? 1 : -1;
   double entry=PositionGetDouble(POSITION_PRICE_OPEN);
   double sl=PositionGetDouble(POSITION_SL),tp=PositionGetDouble(POSITION_TP);
   ulong ticket=(ulong)PositionGetInteger(POSITION_TICKET);
   barPeakR=MathMax(barPeakR,side*(b[0].close-entry)/initialRisk);
   OSStateSave();
   double lockR=0;
   if(!OSBarTrailLock(barPeakR,BarTrailActivateR,BarTrailDistanceR,BarTrailStepR,lockR)) return;
   double desired=RoundPrice(entry+side*lockR*initialRisk);
   if(side*(desired-sl)<=0) return;
   MqlTick q;if(!SymbolInfoTick(_Symbol,q)) return;
   double current=side==1 ? q.bid : q.ask;
   if(side*(current-desired)<=0) {CloseOwned("M1_TRAIL_CROSSED");return;}
   double bound=MathMax(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL))*_Point;
   if(side*(current-desired)<=bound) return;
   if(trade.PositionModify(ticket,desired,tp) && trade.ResultRetcode()==TRADE_RETCODE_DONE)
      Note("M1_STOP_CHANGE",StringFormat("bar=%s peakR=%f lockR=%f stop=%f",TimeToString(b[0].time,TIME_DATE|TIME_SECONDS),barPeakR,lockR,desired));
   else {failedOrders++;Note("M1_STOP_REJECT",IntegerToString((int)trade.ResultRetcode()));}
}

bool OsEnsureIndicators()   // created on demand: a symbol whose history is not cached yet must not block start-up
{
   if(atrHandle==INVALID_HANDLE) atrHandle=iATR(_Symbol,PERIOD_D1,ATRPeriod);
   if(adxHandle==INVALID_HANDLE) adxHandle=iADXWilder(_Symbol,sourceTF,ADXPeriod);
   return (atrHandle!=INVALID_HANDLE && adxHandle!=INVALID_HANDLE);
}
int OnInit()
{
   { int clockInit=ClkInit(); if(clockInit!=INIT_SUCCEEDED) return clockInit; }
   ClkRefresh(ClkNowServer());   // resolve before any self-test, panel or session read
#ifdef OS_VISUAL_PROBE
   if(!MQLInfoInteger(MQL_TESTER)) return INIT_FAILED;
#endif
#ifdef OS_LIFECYCLE_PROBE
   if(!MQLInfoInteger(MQL_TESTER)) return INIT_FAILED;
#endif
   if(!OSBarTrailSelfTest() || !OSCalendarSelfTest()) {Print("OS_CALC_SELFTEST_FAILED");return INIT_FAILED;}
   Print("OS_CALC_SELFTEST_PASS virtual collision/equality and M1 R milestones");
   RunId=OSOutputFamily+(MQLInfoInteger(MQL_TESTER) ? "_test_"+IntegerToString((long)GetTickCount64()) : "_trades");
   if(ATRPeriod<2 || ADXPeriod<2 || ((!UseFixedSize || EnforceFixedSizeRiskCap) && RiskCash<=0) || (UseFixedSize && FixedLots<=0) || NoiseFraction<=0 || TargetR<=0 || StopPoints<=0 || TargetPoints<=0 || CommissionRTPerLot<0 || SlipPrice<0 || Magic==0) return INIT_PARAMETERS_INCORRECT;
   if(VaultAttemptCap<2 || VaultAttemptCap>4 || (SyntheticFirst && (Model!=VaultBreak || Geometry!=SourceGeometry || Management!=FixedBracket))) return INIT_PARAMETERS_INCORRECT;
   if(Management==M1RStep && (Model!=OvernightBiasRangeBreakout || BarTrailActivateR<=0 || BarTrailDistanceR<=0 || BarTrailStepR<=0)) return INIT_PARAMETERS_INCORRECT;
   OSClockRefresh(TimeCurrent());
   sourceTF=PERIOD_M1;
   if(!OsEnsureIndicators())
      PrintFormat("OS_INIT_INDICATORS_PENDING symbol=%s D1/ADX history not ready; creating handles on the first tick",_Symbol);
   if(MQLInfoInteger(MQL_TESTER) && !OSRuntimeSelfTest()) return INIT_FAILED;
   if(!OSRuntimeInit()) return INIT_FAILED;
   trade.SetExpertMagicNumber(Magic);trade.SetTypeFillingBySymbol(_Symbol);trade.SetDeviationInPoints(30);
   OSInitVisual();
   if(DetailedLog)
   {
      OSPrepareOutput();
      string name=OSOutputRoot+"/ledger_"+RunId+".csv";
      bool append=false;
      if(!MQLInfoInteger(MQL_TESTER))
      {append=true;name=OSOutputRoot+"/ledger_"+RunId+"_"+IntegerToString(runtimeAccountId)+"_"+IntegerToString((long)Magic)+".csv";}
      ledger=FileOpen(name,FILE_COMMON|FILE_WRITE|FILE_SHARE_READ|(append ? FILE_READ : 0)|FILE_CSV|FILE_ANSI,',');
      if(ledger==INVALID_HANDLE){Print("OS_LOG_BLOCK: requested ledger unavailable");return INIT_FAILED;}
      if(!append || FileSize(ledger)==0) FileWrite(ledger,"server_time","event","detail");
      else FileSeek(ledger,0,SEEK_END);
   }
   PrintFormat("%s ready | new trades=%s | %s | clock=automatic server/GMT or tester weekly anchor",OSDisplayName,EnableTrading ? "enabled" : "disabled",OSSizingLabel());
   PrintFormat("OS_SPEC tick=%f tickvalue=%f minlot=%f contract=%f",SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE),SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE),SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),SymbolInfoDouble(_Symbol,SYMBOL_TRADE_CONTRACT_SIZE));
   OSRefreshLiveVisuals(TimeTradeServer());OSDraw();
   return INIT_SUCCEEDED;
}
void OnTick()
{
   if(!MQLInfoInteger(MQL_TESTER) && !OSRuntimeAccountContextValid())return;
   if(!OsEnsureIndicators()) return;                 // history may still be arriving: wait, never fail the run
   datetime now=TimeCurrent();
   OSDraw();
   if(!OSClockRefresh(now))return;
   if(!DateAllowed(now)){CloseOwned("PHASE_LOCK");return;}
   double eq=AccountInfoDouble(ACCOUNT_EQUITY)-totalCost;
   adjustedPeak=MathMax(adjustedPeak,eq);adjustedDD=MathMax(adjustedDD,adjustedPeak-eq);
   int minute=OSMinute(now);
   // 00:00 Central == 01:00 New York (DST independent) for the fade exit.
   if(Model==PostCloseFade && minute<30 && OwnPosition()){CloseOwned("FADE_0100_NY");return;}
   if(Model==OpeningShock && OwnPosition())
   {
      datetime positionTime=(datetime)PositionGetInteger(POSITION_TIME);
      if(now-positionTime>=3600){CloseOwned("SHOCK_60_MINUTES");return;}
      if(minute>=895){CloseOwned("RTH_1555_NY");return;}
   }
   if(Model==PostCloseFade && OwnPosition())
   {
      datetime positionTime=(datetime)PositionGetInteger(POSITION_TIME);
      if(OSDay(positionTime)<OSDay(now)){CloseOwned("FADE_NEXT_CENTRAL_DAY");return;}
   }
   if(OwnPosition()) Manage();
   if(!OSRuntimeHistoryReady())return;
   datetime m=iTime(_Symbol,PERIOD_M1,0);
   if(m<=0 || m==lastMinute)return;
   lastMinute=m;ManageClosedMinute();
   datetime tradeDay=OSDay(now);
   if(tradeDay!=day){ResetDay(now);OSStateRestore(now);}
   int required=(Model==OpeningShock ? 540 : 900);
   if(minute<required || minute>required+2)return;
   if(!dayValid){dayValid=NewDay(now);if(dayValid)daysReady++;}
   if(!dayValid)return;
   if(!EnableTrading || OwnPosition() || entries>=1 || runtimeBlocked || runtimeRecoveryHold)return;
   // The model's only entry event is the first NEW minute after the timed close.
   if(lastSignal==day)return;
   if(Model==PostCloseFade)
   {
      MqlDateTime weekday;TimeToStruct(day,weekday);
      if(weekday.day_of_week==5 || weekday.day_of_week==6)return;
   }
   if(minute!=required)return;
   int start=(Model==OpeningShock ? 510 : 870);
   double first=0,last=0;
   if(Model==OpeningShock)
   {
      datetime from=OSSessionTime(day,start),to=OSSessionTime(day,540);
      MqlRates candles[];if(!Window(from,to,candles,30) || ArraySize(candles)!=30 || candles[0].time!=from || candles[29].time!=to-60)return;
      first=candles[0].open;last=candles[ArraySize(candles)-1].close;
   }
   else
   {
      if(!OSResearchClose(day,869,first) || !OSResearchClose(day,899,last))return;
   }
   double delta=last-first;
   if(!MathIsValidNumber(delta) || MathAbs(delta)<(Model==OpeningShock ? 0.30 : 0.20)*averageATR)return;
   int side=(delta>0 ? 1 : -1)*(Model==OpeningShock ? 1 : -1);
   lastSignal=day;OSStateSave();
   double stopDistance=(Model==OpeningShock ? 0.30 : 0.30)*averageATR;
   Note("SIGNAL",StringFormat("side=%d delta=%f lagRange=%f",side,delta,averageATR));
   Open(side,0,0,stopDistance);
}

void OnTradeTransaction(const MqlTradeTransaction &tx,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   if(tx.type!=TRADE_TRANSACTION_DEAL_ADD || !HistoryDealSelect(tx.deal)) return;
   if((ulong)HistoryDealGetInteger(tx.deal,DEAL_MAGIC)!=Magic || HistoryDealGetString(tx.deal,DEAL_SYMBOL)!=_Symbol) return;
   vbBrokerVisualDirty=true;
   long entry=HistoryDealGetInteger(tx.deal,DEAL_ENTRY);
   if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY) return;
   datetime t=(datetime)HistoryDealGetInteger(tx.deal,DEAL_TIME);MqlDateTime p;TimeToStruct(OSDay(t),p);
   if(ownedEntryTime>0 && OSDay(t)!=OSDay(ownedEntryTime))
   {
      overnightExits++;
      carryDetails+=TimeToString(ClockNewYorkStamp(ownedEntryTime),TIME_DATE|TIME_SECONDS)+","+TimeToString(ClockNewYorkStamp(t),TIME_DATE|TIME_SECONDS)+"\r\n";
   }
   int y=p.year-2020;
   double qty=HistoryDealGetDouble(tx.deal,DEAL_VOLUME),exitPrice=HistoryDealGetDouble(tx.deal,DEAL_PRICE);
   int exitReason=(int)HistoryDealGetInteger(tx.deal,DEAL_REASON);
   int exitSide=HistoryDealGetInteger(tx.deal,DEAL_TYPE)==DEAL_TYPE_BUY ? 1 : -1;
   ulong pid=(ulong)HistoryDealGetInteger(tx.deal,DEAL_POSITION_ID);
   double exitCharges=HistoryDealGetDouble(tx.deal,DEAL_COMMISSION)+HistoryDealGetDouble(tx.deal,DEAL_FEE);
   double brokerNet=HistoryDealGetDouble(tx.deal,DEAL_PROFIT)+exitCharges+HistoryDealGetDouble(tx.deal,DEAL_SWAP);
   double entryCharges=OSEntryChargesPerLot(pid)*qty;
   double slipCost=MathMax(0,modelCostPerLot-entryCommissionPerLot)*qty;
   double extraCommission=MQLInfoInteger(MQL_TESTER) ? MathMax(0,entryCommissionPerLot*qty-entryCharges+exitCharges) : 0;
   // Broker-net already contains exit charges; include allocated entry charges once.
   double net=brokerNet-entryCharges-slipCost-extraCommission;
   if(MQLInfoInteger(MQL_TESTER)) totalCost-=MathMin(entryCommissionPerLot*qty,MathMax(0,entryCharges-exitCharges));
   OSStateSave();
   if(y>=0 && y<7){yearProfit[y]+=net;yearTrades[y]++;}
   int di=(int)((OSDay(t)-D'2020.01.01')/86400);
   if(di>=0 && di<ArraySize(dailyNet)) dailyNet[di]+=net;
   if(net>0)netWins+=net;else netLosses-=net;
   Note("EXIT",StringFormat("ticket=%I64u price=%f netAdjusted=%f reason=%d",tx.deal,exitPrice,net,exitReason));
   OSDrawFill(exitSide,t,exitPrice,"Exit");
}
double OnTester()
{
#ifdef OS_LIFECYCLE_PROBE
   return 0;
#endif
   double net=TesterStatistics(STAT_PROFIT)-totalCost;
   double pf=netLosses>0 ? netWins/netLosses : 0;
   OSPrepareOutput();
   string path=OSOutputRoot+"/"+RunId+".csv";
   int out=FileOpen(path,FILE_COMMON|FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(out==INVALID_HANDLE) return -1000000;
   FileWrite(out,"model","net","pf","equityDD","trades","days","rejectedDays","invalidBrackets","failedOrders","worstRisk");
   FileWrite(out,Model,net,pf,adjustedDD,TesterStatistics(STAT_TRADES),daysReady,daysRejected,invalidBrackets,failedOrders,worstRisk);
   FileClose(out);
   bool exported=!DetailedLog || OSExportTrades(path+".trades.csv");
   PrintFormat("%s TESTER_RESULT net=%.2f PF=%.6f trades=%d export=%s path=%s",OSDisplayName,net,pf,(int)TesterStatistics(STAT_TRADES),!DetailedLog ? "DISABLED" : exported ? "PASS" : "FAIL",path);
   return exported && failedOrders==0 && invalidBrackets==0 ? (adjustedDD>0 ? net/adjustedDD : 0) : -1000000;
}
void OnDeinit(const int reason)
{
   OSStateSave();EventKillTimer();
   if(runtimeLockFile!=INVALID_HANDLE) FileClose(runtimeLockFile);
   // A timeframe reload must not erase the M1-derived VWAP while history warms up.
   if(reason!=REASON_CHARTCHANGE || ChartSymbol(0)!=_Symbol || !ShowVisuals)
      ObjectsDeleteAll(0,OSVisualPrefix());
   if(osPane!=INVALID_HANDLE)
   {
      for(int window=(int)ChartGetInteger(0,CHART_WINDOWS_TOTAL)-1;window>=1;window--) ChartIndicatorDelete(0,window,osPaneName);
      IndicatorRelease(osPane);
   }
   if(ledger!=INVALID_HANDLE) FileClose(ledger);
   if(atrHandle!=INVALID_HANDLE) IndicatorRelease(atrHandle);
   if(adxHandle!=INVALID_HANDLE) IndicatorRelease(adxHandle);
}
