#property strict
#property tester_no_cache
#property version "1.00"
#property description "Sigma N3/1.7 M30 band breakout. RTH 09:30-16:00 ET. Same-side retry. M1 R-step trail."
#include <Trade/Trade.mqh>
#ifndef SIGMA_STRATEGY_CORE
#define SIGMA_STRATEGY_CORE

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
// Clock: live server/GMT detection; tester weekly-open anchor.
// No broker whitelist or fixed tester fallback.
const int CLOCK_UNKNOWN=100000;
int clockServerNY=0;
bool clockReady=false;
datetime clockObserved=0;
datetime clockWeeks[];
int clockWeekOffsets[];
// Seconds the server clock is ahead of New York at this stamp: the standard adapter owns the
// server -> UTC mapping, so this is the only clock decision left in the EA.
int SigmaServerNYOffsetSec(datetime stamp)
{
   if(!ClkOK()) return CLOCK_UNKNOWN;
   datetime utc=ClkStampToUtc(stamp);
   if(utc<=0) return CLOCK_UNKNOWN;
   return (int)((long)stamp-(long)ClkUtcToNy(utc));
}
bool SigmaClockRefresh(datetime stamp)
{
   ClkRefresh(stamp);
   bool ready=ClkOK();
   int offset=ready ? SigmaServerNYOffsetSec(stamp) : CLOCK_UNKNOWN;
   if(offset==CLOCK_UNKNOWN) ready=false;
   bool announce=!clockReady || offset!=clockServerNY;
   clockReady=ready;
   if(!ready) return false;
   if(announce) PrintFormat("Sigma_CLOCK_READY serverAheadOfNYMinutes=%d source=%s",offset/60,ClkSource());
   clockServerNY=offset;clockObserved=stamp;return true;
}
datetime SigmaNewYorkAtOffset(datetime server,int offset){return server-offset;}
datetime SigmaSessionAtOffset(datetime centralDay,int minute,int offset){return centralDay+offset+3600+minute*60;}
datetime SigmaNewYork(datetime server)
{
   int offset=SigmaServerNYOffsetSec(server);
   return offset==CLOCK_UNKNOWN ? 0 : SigmaNewYorkAtOffset(server,offset);
}
datetime SigmaNewYorkUTC(datetime utc){return ClkUtcToNy(utc);}
datetime SigmaCentralUTC(datetime utc){return utc+ClkNyUtcOffset(utc-3600)-3600;}
datetime SigmaClockUTC(datetime server){return ClkStampToUtc(server);}
datetime SigmaCentral(datetime server){datetime utc=SigmaClockUTC(server);return utc>0 ? SigmaCentralUTC(utc) : 0;}
datetime SigmaSessionTime(datetime centralDay,int minute=0)
{
   int offset=SigmaServerNYOffsetSec(centralDay+minute*60+clockServerNY+3600);
   if(offset==CLOCK_UNKNOWN && clockReady && MathAbs((double)(centralDay-TimeCurrent()))<3*86400) offset=clockServerNY;
   if(offset==CLOCK_UNKNOWN) return 0;
   datetime result=SigmaSessionAtOffset(centralDay,minute,offset);
   int resolved=SigmaServerNYOffsetSec(result);
   return SigmaSessionAtOffset(centralDay,minute,resolved==CLOCK_UNKNOWN ? offset : resolved);
}
datetime SigmaDay(datetime server)
{
   MqlDateTime p; TimeToStruct(SigmaNewYork(server),p);
   p.hour=0; p.min=0; p.sec=0;
   return StructToTime(p);
}
int SigmaMinute(datetime server)
{
   MqlDateTime p; TimeToStruct(SigmaNewYork(server),p);
   return p.hour*60+p.min;
}
bool SigmaAllowed(datetime t) {return true;}
bool SigmaEligible(int minute,int cutoff) {return minute>=0 && minute<cutoff;}
datetime SigmaCalendarDate(int y,int m,int d)
{
   MqlDateTime p={};p.year=y;p.mon=m;p.day=d;return StructToTime(p);
}
int SigmaCalendarWeekday(datetime t){MqlDateTime p;TimeToStruct(t,p);return p.day_of_week;}
datetime SigmaObserved(datetime t)
{
   int w=SigmaCalendarWeekday(t);return t+(w==6 ? -86400 : w==0 ? 86400 : 0);
}
datetime SigmaMonday(int y,int month,int n)
{
   datetime t=SigmaCalendarDate(y,month,1);
   return t+((8-SigmaCalendarWeekday(t))%7+7*(n-1))*86400;
}
bool SigmaFutureSpecialDay(datetime d)
{
   MqlDateTime p;TimeToStruct(d,p);int y=p.year;
   datetime mayEnd=SigmaCalendarDate(y,6,1)-86400;
   datetime memorial=mayEnd-((SigmaCalendarWeekday(mayEnd)+6)%7)*86400;
   int a=y%19,b=y/100,c=y%100,e=b%4,f=(b+8)/25,g=(b-f+1)/3;
   int h=(19*a+b-b/4-g+15)%30,ii=c/4,k=c%4,l=(32+2*e+2*ii-h-k)%7;
   int mm=(a+11*h+22*l)/451,nn=h+l-7*mm+114;
   datetime friday=SigmaCalendarDate(y,nn/31,nn%31+1)-2*86400;
   datetime nov=SigmaCalendarDate(y,11,1);
   datetime thanks=nov+((11-SigmaCalendarWeekday(nov))%7+21)*86400;
   return d==SigmaObserved(SigmaCalendarDate(y,1,1)) || d==SigmaMonday(y,1,3)
      || d==SigmaMonday(y,2,3) || d==friday || d==memorial
      || d==SigmaObserved(SigmaCalendarDate(y,6,19)) || d==SigmaCalendarDate(y,7,3)
      || d==SigmaObserved(SigmaCalendarDate(y,7,4)) || d==SigmaMonday(y,9,1)
      || d==thanks || d==thanks+86400 || d==SigmaCalendarDate(y,12,24)
      || d==SigmaObserved(SigmaCalendarDate(y,12,25)) || d==SigmaCalendarDate(y,12,31);
}
// Server offset in whole hours at this UTC instant, from the resolved standard clock. Was a
// hard-coded 3/2 US-DST table; any broker, any rule, and a dated schedule all work now.
int SigmaExpectedBrokerUTC(datetime utc)
{
   // Before the adapter resolves (OnInit self-tests, a chart with no history yet) answer with the
   // US rule the strategy was written against; the resolved clock takes over from the first tick.
   if(!ClkOK()) return ClkNyUtcOffset(utc)==-4*3600 ? 3 : 2;
   return (int)(((long)ClkUtcToServer(utc,ClkRule(),ClkBase())-(long)utc)/3600);
}
bool SigmaCalendarSelfTest()
{
   return SigmaNewYorkAtOffset(D'2022.01.24 08:00',7*3600)==D'2022.01.24 01:00'
      && SigmaNewYorkAtOffset(D'2022.01.24 08:00',8*3600)==D'2022.01.24 00:00'
      && SigmaNewYorkAtOffset(D'2022.07.12 08:00',7*3600)==D'2022.07.12 01:00'
      && SigmaNewYorkAtOffset(D'2022.07.12 08:00',8*3600)==D'2022.07.12 00:00'
      && SigmaSessionAtOffset(D'2022.01.24',510,7*3600)==D'2022.01.24 16:30'
      && SigmaSessionAtOffset(D'2022.07.12',600,7*3600)==D'2022.07.12 18:00'
      && SigmaSessionAtOffset(D'2022.07.12',870,7*3600)==D'2022.07.12 22:30'
      && SigmaSessionAtOffset(D'2022.07.12',0,7*3600)==D'2022.07.12 08:00'
      && SigmaFutureSpecialDay(D'2026.04.03') && SigmaFutureSpecialDay(D'2027.03.26')
      && SigmaFutureSpecialDay(D'2026.11.26') && SigmaFutureSpecialDay(D'2026.11.27')
      && !SigmaFutureSpecialDay(D'2026.11.25')
      && (int)(((long)ClkUtcToServer(D'2026.03.08 06:59:59',CLK_RULE_US,120)-(long)D'2026.03.08 06:59:59')/3600)==2
      && (int)(((long)ClkUtcToServer(D'2026.03.08 07:00:00',CLK_RULE_US,120)-(long)D'2026.03.08 07:00:00')/3600)==3
      && (int)(((long)ClkUtcToServer(D'2026.11.01 05:59:59',CLK_RULE_US,120)-(long)D'2026.11.01 05:59:59')/3600)==3
      && (int)(((long)ClkUtcToServer(D'2026.11.01 06:00:00',CLK_RULE_US,120)-(long)D'2026.11.01 06:00:00')/3600)==2
      && SigmaNewYorkUTC(D'2026.03.08 06:59:59')==D'2026.03.08 01:59:59'
      && SigmaNewYorkUTC(D'2026.03.08 07:00:00')==D'2026.03.08 03:00:00'
      && SigmaCentralUTC(D'2026.03.08 07:59:59')==D'2026.03.08 01:59:59'
      && SigmaCentralUTC(D'2026.03.08 08:00:00')==D'2026.03.08 03:00:00'
      && SigmaNewYorkUTC(D'2026.11.01 06:00:00')==D'2026.11.01 01:00:00'
      && SigmaCentralUTC(D'2026.11.01 07:00:00')==D'2026.11.01 01:00:00';
}
// Sigma cutoff: 16:00 ET = 960 minutes CT. Special days cut off at 11:55 CT = 715 min.
// Note: NT8/Tradeify uses 15:44 ET (944 min) as a Tradeify platform rule; MQL5 uses true RTH close.
int SigmaSessionCutoff(datetime server,int model)
{
   string dates=
      "|2020.01.01|2020.01.20|2020.02.17|2020.04.10|2020.05.25|2020.07.03|2020.09.07|2020.11.26|2020.11.27|2020.12.24|2020.12.25|2020.12.31"
      "|2021.01.01|2021.01.18|2021.02.15|2021.04.02|2021.05.31|2021.07.05|2021.09.06|2021.11.25|2021.11.26|2021.12.24|2021.12.31"
      "|2022.01.17|2022.02.21|2022.04.15|2022.05.30|2022.06.20|2022.07.04|2022.09.05|2022.11.24|2022.11.25|2022.12.24|2022.12.26|2022.12.31"
      "|2023.01.02|2023.01.16|2023.02.20|2023.04.07|2023.05.29|2023.06.19|2023.07.03|2023.07.04|2023.09.04|2023.11.23|2023.11.24|2023.12.24|2023.12.25|2023.12.31"
      "|2024.01.01|2024.01.15|2024.02.19|2024.03.29|2024.05.27|2024.06.19|2024.07.03|2024.07.04|2024.09.02|2024.11.28|2024.11.29|2024.12.24|2024.12.25|2024.12.31"
      "|2025.01.01|2025.01.09|2025.01.20|2025.02.17|2025.04.18|2025.05.26|2025.06.19|2025.07.03|2025.07.04|2025.09.01|2025.11.27|2025.11.28|2025.12.24|2025.12.25|2025.12.31|";
   if(StringFind(dates,"|"+TimeToString(SigmaDay(server),TIME_DATE)+"|")>=0) return 715;
   if(SigmaDay(server)>=D'2026.01.01' && SigmaFutureSpecialDay(SigmaDay(server))) return 715;
   return 944; // 15:44 ET safety cutoff (Tradeify / NT8 parity) — MQL5 Sigma model cutoff
}
bool SigmaBracket(int side,double entry,double stop,double target)
{
   return side*(entry-stop)>0 && side*(target-entry)>0;
}
int SigmaTradeCap(int model) {return 1;} // Sigma: 1 initial + 1 retry = cap 2 enforced via SigmaMaxAttempts
// Closed M1 long-side path. A double touch resolves as stop first.
int SigmaVirtualExit(double low,double high,double stop,double target)
{
   if(low<=stop) return -1;
   if(high>=target) return 1;
   return 0;
}
bool SigmaCanEnter(int minute,int start,int cutoff,int count,int cap)
{
   return minute>=start && SigmaEligible(minute,cutoff) && count<cap;
}
bool SigmaSignalCloseEligible(int closeMinute)
{
   // Sigma: M30 bars. First complete M30 closes at 10:00 ET = minute 600 CT.
   return closeMinute>=600;
}
bool SigmaSignalTimeSelfTest()
{
   // Sigma M30: first complete M30 after 09:30 ET closes at 10:00 ET = 600 min CT.
   return !SigmaSignalCloseEligible(570) && !SigmaSignalCloseEligible(599)
      && SigmaSignalCloseEligible(600) && SigmaSignalCloseEligible(630);
}
// Sigma: close strictly above upper band = long; strictly below lower band = short.
// upper/lower are passed in from the band state variables.
int SigmaSignalSide(int model,int direction,double close,double upper,double lower,double dummy)
{
   if(upper<=lower || upper<=0) return 0;
   if(close>upper) return 1;
   if(close<lower) return -1;
   return 0;
}
#endif
#ifndef SIGMA_STRATEGY_BAR_TRAIL
#define SIGMA_STRATEGY_BAR_TRAIL
bool SigmaBarTrailLock(double peakR,double activateR,double distanceR,double stepR,double &lockR)
{
   if(activateR<=0 || distanceR<=0 || stepR<=0 || peakR<activateR) return false;
   lockR=activateR+MathFloor((peakR-activateR)/stepR+1e-9)*stepR-distanceR;
   return true;
}
bool SigmaBarTrailSelfTest()
{
   double lock=0;
   if(SigmaBarTrailLock(1.499,1.5,1.5,.5,lock)) return false;
   double peaks[]={1.5,1.999,2.0,2.499,2.5,3.0};
   double expected[]={0.0,0.0,.5,.5,1.0,1.5};
   for(int i=0;i<ArraySize(peaks);i++)
      if(!SigmaBarTrailLock(peaks[i],1.5,1.5,.5,lock) || MathAbs(lock-expected[i])>1e-9) return false;
   return !SigmaBarTrailLock(2.0,1.5,1.5,0,lock)
      && SigmaVirtualExit(99,111,100,110)==-1
      && SigmaVirtualExit(100,109,100,110)==-1
      && SigmaVirtualExit(101,110,100,110)==1
      && SigmaVirtualExit(101,109,100,110)==0;
}
#endif

enum SigmaModel { VaultBreak=0, VWAPPullback=1, SigmaBreakout=2 };
const SigmaModel Model=SigmaBreakout;
enum SigmaGeometry { SourceGeometry=0, ATRGeometry=1 };
enum SigmaManagement { FixedBracket=0, VWAPClose=1, CostCoveredBE=2, ATRTrail=3, M1RStep=4 };
#ifndef SIGMA_STRATEGY_PRODUCTION_INPUTS
#define SIGMA_STRATEGY_PRODUCTION_INPUTS

input group "==========  1 - Trading  =========="
input bool   EnableTrading             = true;   // Enable new trades (open trades stay protected when off)

input group " "
input group "==========  2 - Risk  =========="
input double SlPct                     = 0.0;    // Stop loss percentage (0 = no synthetic stop; flip/session exit)
input bool   UseFixedSize              = true;   // Use fixed lots (default ON for Sigma)
input double FixedLots                 = 1.0;    // Lots per trade when fixed sizing is enabled
input double RiskMoney                 = 250.0;  // Risk per trade in account currency (used when UseFixedSize=false)
input bool   SkipSetupsAboveRiskBudget = false;  // Skip entries where total initial risk > RiskBudgetUsd
input double RiskBudgetUsd             = 250.0;  // Cap (account currency); only active when SkipSetupsAboveRiskBudget=true

input group "  "
input group "==========  3 - Model Parameters  =========="
input int    N_Sigma                   = 3;      // Prior RTH sessions per slot for band calculation
input double BandMult                  = 1.7;    // Band multiplier applied to mean absolute deviation

input group "   "
input group "==========  4 - Trading Costs  =========="
input double CommissionPerLot          = 7.0;    // Fallback round-trip commission per lot
input int    SlippagePoints            = 3;      // Slippage per side in points

input group "    "
input group "==========  5 - Display  =========="
input bool   ShowVisuals               = true;   // Show chart levels, trade markers and information panel

input group "     "
input group "==========  6 - Execution & Logging  =========="
input bool   WriteTradeLog             = false;  // Write a detailed trade and decision log

// Frozen Sigma rules — not user-facing options.
const ulong  MagicNumber               = 91008061; // Fixed model identity; preserves owned-position recovery
const int    SigmaMaxAttempts            = 2;         // 1 initial entry + 1 same-side retry
const double SigmaRetryStopFraction      = 0.5;       // Retry stop = 50% of first-attempt original stop distance
const SigmaManagement Management         = FixedBracket;
const double BarTrailActivateR         = 1.5;
const double BarTrailDistanceR         = 1.5;
const double BarTrailStepR             = 0.5;
const double BreakEvenR                = 0.5;
const string SigmaDisplayName            = "Sigma Breakout N3/1.7";

// Private adapter names matching execution engine expectations.
const int    StartMinute               = 600;  // 10:00 ET — first complete M30 slot
const double RiskCash                  = RiskMoney;
const double CommissionRTPerLot        = CommissionPerLot;
const double SlipPrice                 = SlippagePoints*_Point;
const ulong  Magic                     = MagicNumber;
const bool   DetailedLog               = WriteTradeLog;
const SigmaGeometry Geometry             = SourceGeometry;
const double TrailR                    = 1.0;
const double BarTrailStepR_            = BarTrailStepR; // alias used by engine
string RunId = "";
#endif

// ---- Compatibility stubs for ChartVisuals.mqh and ExecutionRuntime.mqh ----
// These Sigma globals are referenced by the shared modules; Sigma doesn't use them but declares stubs.
double orHigh=0,orLow=0,overnightHigh=0,overnightLow=0;
int    bias=0;
const int    ADXPeriod=15;         // Stub: no ADX in Sigma; required by ChartVisuals panel header
const int    OvernightStart=23;    // Stub: required by ChartVisuals panel
const int    VaultAttemptCap=3;    // Stub: required by ExecutionRuntime recovery path
const bool   SyntheticFirst=false; // Stub: required by ExecutionRuntime
const double TargetR=3.0;          // Stub: required by ExecutionRuntime trade export label
int    adxHandle=INVALID_HANDLE;   // Stub: ExecutionRuntime history-ready check references this
bool SigmaSessionATRMean(datetime sessionDay,double &mean){mean=1.0;return true;} // Stub: always ready
// dayValid: Sigma tracks this as a local in OnTick; ChartVisuals needs a global copy.
bool dayValid=false;
int  sigmaFlipPendingSide=0;
// SigmaBias stub: ChartVisuals calls SigmaBias(open,low,high) — return 0 (no bias in Sigma)
int SigmaBias(double open,double low,double high){return 0;}

const string SigmaOutputFamily = "SigmaBreakout";
const string SigmaOutputRoot   = SigmaOutputFamily+"/logs";
void SigmaPrepareOutput()
{
   FolderCreate(SigmaOutputFamily,FILE_COMMON);
   FolderCreate(SigmaOutputRoot,FILE_COMMON);
}

CTrade trade;
int ledger=INVALID_HANDLE;
ENUM_TIMEFRAMES sourceTF=PERIOD_M30;
datetime lastMinute=0,lastSignal=0,day=0;
double initialRisk=0,modelCost=0,totalCost=0;
double modelCostPerLot=0,entryCommissionPerLot=0;
datetime ownedEntryTime=0;
int overnightExits=0;
string carryDetails="";
int entries=0,daysReady=0,daysRejected=0,invalidBrackets=0,failedOrders=0;
int firstSide=0;
double firstStopDistance=0;
bool retryArmed=false;
bool targetFilled=false;
datetime retryEligibleAfter=0;
bool rangeReady=false,armed=false,beDone=false;
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

// ---- Sigma-specific band state ----
double rthOpen=0;           // RTH 09:30 ET opening price
bool rthOpenReady=false;

// Per-slot history: 13 slots (slot 0=09:30-10:00, slot 1=10:00-10:30, ..., slot 12=15:30-16:00)
// slotObservations[slot*MAX_SLOTS_N + k] = k-th prior abs(M30close - rthOpen) for that slot
// slotCounts[slot] = number of valid observations recorded for that slot
const int MAX_SLOT_IDX    = 13;
double slotObservations[];  // size MAX_SLOT_IDX * N_Sigma
int    slotCounts[];        // size MAX_SLOT_IDX

// Current live band (recomputed per completed M30 slot during session)
double sigmaUpperBand=0;
double sigmaLowerBand=0;
bool   sigmaBandReady=false;
int    sigmaCurrentSlot=-1; // which slot (0-based) the band is current for

#ifdef SIGMA_VISUAL_PROBE
bool gtPreviewRequested=false;
ulong gtPreviewRequestedMs=0;
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
bool DateAllowed(datetime t) {return true;}
double RoundPrice(double price)
{
   double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   return NormalizeDouble(MathRound(price/tick)*tick,_Digits);
}
void CloseOwned(string why)
{
   if(!MQLInfoInteger(MQL_TESTER) && !SigmaRuntimeAccountContextValid()){SigmaDraw();return;}
   if(!MQLInfoInteger(MQL_TESTER) && !TerminalInfoInteger(TERMINAL_CONNECTED)) return;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket>0 && PositionGetString(POSITION_SYMBOL)==_Symbol && (ulong)PositionGetInteger(POSITION_MAGIC)==Magic)
      {
         if(!RecoveryCloseBegin(SigmaStateKey(),ticket))continue;
         bool closed=trade.PositionClose(ticket);uint ret=trade.ResultRetcode();
         RecoveryCloseResult(SigmaStateKey(),ret,trade.ResultOrder());
         if(!closed || (ret!=TRADE_RETCODE_DONE && ret!=TRADE_RETCODE_DONE_PARTIAL))
         { failedOrders++; PrintFormat("SIGMA_CLOSE_REJECT %s ret=%u",why,trade.ResultRetcode()); }
      }
   }
}
void Note(string kind,string text)
{
   if(kind=="RECOVERY_BLOCK")Print("SIGMA RECOVERY ATTENTION: ",text);
   if(kind=="RISK_MINIMUM" || kind=="RISK_CAP_SKIP")PrintFormat("SIGMA %s %s",kind,text);
   if(DetailedLog && ledger!=INVALID_HANDLE)
   {
      FileWrite(ledger,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),kind,text);
      FileFlush(ledger);
   }
}
bool M1HistoryAvailable(datetime from)
{
   if(!MQLInfoInteger(MQL_TESTER) && !TerminalInfoInteger(TERMINAL_CONNECTED)) return false;
   long first=SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_FIRSTDATE);
   if(first<=0 || first>from || !SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_SYNCHRONIZED))
   {
      MqlRates preceding[];
      CopyRates(_Symbol,PERIOD_M1,from-86400,from,preceding);
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
   price=bars[0].open;
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
      PrintFormat("SIGMA DATA_WAIT day=%s reason=%s synchronized=%d firstM1=%s; retrying, protection active",
         TimeToString(day,TIME_DATE),reason,(int)SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_SYNCHRONIZED),
         TimeToString((datetime)SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_FIRSTDATE),TIME_DATE|TIME_MINUTES));
   }
   return false;
}
void ResetDay(datetime now)
{
   day=SigmaDay(now); entries=0; firstSide=0; firstStopDistance=0; retryArmed=false; retryEligibleAfter=0;targetFilled=false;
   rangeReady=false; armed=false; beDone=false;
   rthOpenReady=false; rthOpen=0;
   dayValid=false;
   sigmaBandReady=false;sigmaFlipPendingSide=0; sigmaUpperBand=0; sigmaLowerBand=0; sigmaCurrentSlot=-1;
   gtLastEntry=0;gtLastStop=0;gtLastTarget=0;gtLastBracketTime=0;
   if(SigmaVisualEnabled()) ObjectsDeleteAll(0,SigmaVisualPrefix());
   dayWaiting=false; dayRejected=false; dataWaitReason="";
   virtualActive=false; virtualStart=0; virtualLastBar=0;
   lastSignal=0;
}

// Load prior-session slot observations for current day.
// Collects N_Sigma completed RTH sessions (working backwards) for each of 13 M30 slots.
// Slot s starts at server time = SigmaSessionTime(sessionDay, s*30)  [09:30 CT + s*30 min]
// Returns true when all 13 slots have N_Sigma observations.
bool LoadPriorSlotHistory(datetime today)
{
   ArrayInitialize(slotObservations,0.0);
   ArrayInitialize(slotCounts,0);
   int sessionsFound=0;
   datetime scan=today-86400;
   for(int attempt=0;attempt<30 && sessionsFound<N_Sigma;attempt++,scan-=86400)
   {
      // Skip weekends
      MqlDateTime wd;TimeToStruct(scan,wd);
      if(wd.day_of_week==0 || wd.day_of_week==6) continue;
      // Get RTH open for this session
      datetime rthOpenServer=SigmaSessionTime(scan,0); // 09:30 ET server time
      if(rthOpenServer<=0) continue;
      double sessOpen=0;
      if(!OpeningPrice(rthOpenServer,5,sessOpen)) continue;
      // Check all 13 slots are available
      bool sessionOk=true;
      double devs[13];
      for(int s=0;s<MAX_SLOT_IDX;s++)
      {
         datetime slotFrom=SigmaSessionTime(scan,s*30);      // slot start server time
         datetime slotTo  =slotFrom+30*60;
         MqlRates sb[];
         if(!Window(slotFrom,slotTo,sb,30)){sessionOk=false;break;}
         double m30Close=sb[ArraySize(sb)-1].close;
         devs[s]=MathAbs(m30Close-sessOpen);
      }
      if(!sessionOk) continue;
      // Store observation (append in discovery order — oldest first as we walk backwards)
      for(int s=0;s<MAX_SLOT_IDX;s++)
      {
         if(slotCounts[s]<N_Sigma)
         {
            slotObservations[s*N_Sigma+slotCounts[s]]=devs[s];
            slotCounts[s]++;
         }
      }
      sessionsFound++;
   }
   // All 13 slots must have N_Sigma observations
   for(int s=0;s<MAX_SLOT_IDX;s++)
      if(slotCounts[s]<N_Sigma) return false;
   return true;
}

// Compute band for slot s from stored observations. Returns true on success.
bool ComputeSlotBand(int s,double rthOpenPrice,double &upper,double &lower)
{
   if(s<0 || s>=MAX_SLOT_IDX || slotCounts[s]<N_Sigma) return false;
   double sum=0;
   for(int k=0;k<N_Sigma;k++)
      sum+=slotObservations[s*N_Sigma+k];
   double bandWidth=(sum/N_Sigma)*BandMult;
   if(bandWidth<=0 || !MathIsValidNumber(bandWidth)) return false;
   upper=rthOpenPrice+bandWidth;
   lower=rthOpenPrice-bandWidth;
   return true;
}

bool NewDay(datetime now)
{
   // Get RTH open (09:30 ET)
   datetime anchor=SigmaSessionTime(day,0);
   if(anchor<=0) return RejectDay("SESSION_TIME_UNAVAILABLE");
   rthOpenReady=false;
   rthOpen=0;
   if(!OpeningPrice(anchor,5,rthOpen)) return RejectDay("RTH_OPEN_UNAVAILABLE");
   rthOpenReady=true;
   // Load prior slot history (requires M1 history going back N_Sigma RTH sessions)
   if(!LoadPriorSlotHistory(day)) return RejectDay("SLOT_HISTORY_INCOMPLETE");
   sigmaBandReady=false;sigmaFlipPendingSide=0; sigmaUpperBand=0; sigmaLowerBand=0; sigmaCurrentSlot=-1;
   Note("DAY",StringFormat("rthOpen=%f N=%d mult=%f",rthOpen,N_Sigma,BandMult));
   if(dayWaiting && !MQLInfoInteger(MQL_TESTER))
      lastSignal=MathMax(lastSignal,iTime(_Symbol,sourceTF,1));
   if(dayRejected){daysRejected--;dayRejected=false;}
   dayWaiting=false;dataWaitReason="";
   return true;
}

// SetRange: for Sigma, update the live band for the most recently completed M30 slot.
bool SetRange(datetime now)
{
   // Sigma: source is M30 from 09:30 ET. Slot s corresponds to server window
   // [SigmaSessionTime(day, s*30), SigmaSessionTime(day, s*30)+30min).
   // We need at least one completed slot (minute >= 600 CT = 10:00 ET).
   int minute=SigmaMinute(now);
   if(minute<600) return false; // First M30 not yet complete
   // Which slot just completed?
   // Slot 0 completes at 10:00 ET = minute 600 CT; slot s completes at (600+s*30) min CT.
   int completedSlot=(minute-600)/30; // 0-based index of last fully completed slot
   if(completedSlot<0) return false;
   if(completedSlot>=MAX_SLOT_IDX) completedSlot=MAX_SLOT_IDX-1;
   if(completedSlot==sigmaCurrentSlot) return true; // Already set for this slot
   // Update band for completedSlot
   double upper=0,lower=0;
   if(!ComputeSlotBand(completedSlot,rthOpen,upper,lower)) return false;
   sigmaUpperBand=upper;
   sigmaLowerBand=lower;
   sigmaBandReady=true;
   sigmaCurrentSlot=completedSlot;
   Note("SIGMA_BAND",StringFormat("slot=%d upper=%f lower=%f",completedSlot,upper,lower));
   return true;
}

double SigmaRequestedVolume(bool fixedSize,double lots,double budget,double unitRisk,double step,double minimum,double maximum)
{
   if(unitRisk<=0 || !MathIsValidNumber(unitRisk) || step<=0 || minimum<=0 || maximum<minimum) return 0;
   if(fixedSize)
   {
      if(!MathIsValidNumber(lots) || lots<minimum || lots>maximum || MathAbs(lots/step-MathRound(lots/step))>1e-7) return 0;
      return lots;
   }
   if(!MathIsValidNumber(budget) || budget<=0) return 0;
   return MathMax(minimum,MathFloor(MathMin(budget/unitRisk,maximum)/step+1e-9)*step);
}
string SigmaSizingLabel()
{return UseFixedSize ? "Lots "+DoubleToString(FixedLots,4) : "Risk "+DoubleToString(RiskMoney,2);}
// Swap-aware cost-covered price. Reads accrued swap from the live broker position
// and adds it (as an additional one-time cost per lot) to the trail cost floor.
// Called only when OwnPosition() is true; safe to query POSITION_SWAP directly.
// The initial trade entry does not block on swap — swap is unknown at entry time.
// Only the trailing ratchet incorporates swap after it has accrued intraday or overnight.
bool SigmaCostCoveredPriceSwapAware(int side,double entry,double commission,double volume,double &price)
{
   double accruedSwap=OwnPosition() ? PositionGetDouble(POSITION_SWAP) : 0.0;
   // accruedSwap is negative when broker debits (short CFDs, overnight financing).
   // Treat it as an additional cost: if swap < 0, floor must recover it.
   double swapPerLot=volume>0 && accruedSwap<0 ? MathAbs(accruedSwap)/volume : 0.0;
   double totalCommission=commission+swapPerLot;
   if(!SigmaCostCoveredPrice(side,entry,totalCommission,price)) return false;
   if(swapPerLot>0)
      Note("SWAP_FLOOR",StringFormat("accruedSwap=%f swapPerLot=%f newFloor=%f",accruedSwap,swapPerLot,price));
   return true;
}

bool Open(int side,double stop,double target,double distance)
{
   MqlTick q;if(!SymbolInfoTick(_Symbol,q)) return false;
   double entry=(side==1 ? q.ask : q.bid);
   double commission=SigmaCommissionEstimate();
   double friction=commission;
   double slipLoss=0;
   if(!OrderCalcProfit(ORDER_TYPE_BUY,_Symbol,1.0,entry,entry-2*SlipPrice,slipLoss)) return false;
   friction+=MathAbs(slipLoss);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP),minimum=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   if(step<=0 || minimum<=0) {Note("RISK_INVALID","Invalid volume contract");return false;}
   
   double volume=1.0;
   double unitRisk=0;
   
   double stopDist = distance>0.0 ? distance : entry*(SlPct/100.0);
   if(stopDist>0.0)
   {
      stop = RoundPrice(entry - side * stopDist);
      target = RoundPrice(entry + side * stopDist * 3.0);
      if(!SigmaBracket(side,entry,stop,target)) {invalidBrackets++;Note("INVALID_BRACKET",StringFormat("%d %f %f %f",side,entry,stop,target));return false;}
      double loss=0;
      if(!OrderCalcProfit(side==1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,_Symbol,1.0,entry,stop,loss)) return false;
      unitRisk=MathAbs(loss)+friction;
      if(unitRisk<=0 || !MathIsValidNumber(unitRisk)) {Note("RISK_INVALID","Invalid cash risk");return false;}
      volume=SigmaRequestedVolume(UseFixedSize,FixedLots,RiskCash,unitRisk,step,minimum,SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX));
      if(volume<minimum || unitRisk<=0) {Note(UseFixedSize ? "FIXED_LOTS_INVALID" : "RISK_TOO_SMALL",DoubleToString(unitRisk*minimum,2));return false;}
      if(!UseFixedSize && unitRisk*minimum>RiskCash)
         Note("RISK_MINIMUM",StringFormat("broker minimum exceeds intended risk; lots=%.8f estimatedRisk=%.2f intendedRisk=%.2f %s",minimum,unitRisk*minimum,RiskCash,AccountInfoString(ACCOUNT_CURRENCY)));
      if(SkipSetupsAboveRiskBudget && unitRisk*volume>RiskBudgetUsd)
      {
         Note("RISK_CAP_SKIP",StringFormat("%srisk=%f cap=%f",!UseFixedSize && unitRisk*minimum>RiskBudgetUsd ? "broker minimum exceeds configured hard cap; " : "",unitRisk*volume,RiskBudgetUsd));
         return false;
      }
      double stops=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
      if(side*(entry-stop)<stops || side*(target-entry)<stops){invalidBrackets++;return false;}
   }
   else
   {
      stop=0;target=0;
      volume=UseFixedSize ? MathMax(minimum, FixedLots) : minimum;
      volume=NormalizeDouble(MathFloor(volume/step)*step, 2);
   }
   
   entryCommissionPerLot=commission;modelCostPerLot=friction;
   if(!SigmaRuntimeEntryAllowed(entry,stop,target,volume,side)) {Note("ENTRY_BLOCK","EA safety, clock, margin or terminal gate");return false;}
   string comment=MQLInfoInteger(MQL_TESTER) ? SigmaDisplayName : "SIGMA#"+IntegerToString((long)runtimeIntentNonce);
   bool ok=(side==1 ? trade.Buy(volume,_Symbol,0,stop,target,comment) : trade.Sell(volume,_Symbol,0,stop,target,comment));
   uint ret=trade.ResultRetcode();
   if(!ok || (ret!=TRADE_RETCODE_DONE && ret!=TRADE_RETCODE_DONE_PARTIAL))
   {
      failedOrders++;Note("ENTRY_REJECT",IntegerToString((int)ret));
      if(!MQLInfoInteger(MQL_TESTER)){entries++;runtimeBlocked=true;SigmaStateSave();}
      return false;
   }
   initialRisk=(stop>0 ? MathAbs(trade.ResultPrice()-stop) : 0);beDone=false;barPeakR=0;runtimeTrailLastBar=0;
   double filledVolume=trade.ResultVolume()>0 ? trade.ResultVolume() : volume;
   entryCommissionPerLot=commission;modelCostPerLot=friction;modelCost=friction*filledVolume;totalCost+=modelCost;ownedEntryTime=TimeCurrent();
   entries++;
   if(entries==1){firstSide=side;firstStopDistance=initialRisk;}
   retryArmed=false;retryEligibleAfter=0;targetFilled=false;
   worstRisk=MathMax(worstRisk,unitRisk*volume);
   SigmaRememberBracket(trade.ResultPrice(),stop,target);
   SigmaDrawFill(side,TimeCurrent(),trade.ResultPrice(),"Entry");
   SigmaRuntimeFilled(side,stop,friction);
   Note("ENTRY",StringFormat("model=Sigma side=%d lots=%f fill=%f sl=%f tp=%f count=%d modeledCost=%f",side,volume,trade.ResultPrice(),stop,target,entries,modelCost));
   return true;
}
void SigmaObserveRecoveryMinute(datetime source,double close,int side,double entry)
{
   if(initialRisk<=0 || source<=runtimeTrailLastBar || source+60<=ownedEntryTime) return;
   barPeakR=MathMax(barPeakR,side*(close-entry)/initialRisk);
   runtimeTrailLastBar=source;
}
void ManageClosedMinute()
{
   if(Management!=M1RStep || runtimeRecoveryHold || runtimeClosePending || !OwnPosition() || initialRisk<=0) return;
   if(!MQLInfoInteger(MQL_TESTER) && (!SigmaRuntimeAccountContextValid() || !TerminalInfoInteger(TERMINAL_CONNECTED))) return;
   MqlRates b[];
   datetime completed=iTime(_Symbol,PERIOD_M1,1);
   if(completed<=0 || completed<=runtimeTrailLastBar) return;
   ArraySetAsSeries(b,false);
   datetime from=runtimeTrailLastBar>0 ? runtimeTrailLastBar+60 : completed;
   if(CopyRates(_Symbol,PERIOD_M1,from,completed,b)<=0) return;
   int side=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY ? 1 : -1;
   double entry=PositionGetDouble(POSITION_PRICE_OPEN);
   double sl=PositionGetDouble(POSITION_SL),tp=PositionGetDouble(POSITION_TP);
   ulong ticket=(ulong)PositionGetInteger(POSITION_TICKET);
   for(int i=0;i<ArraySize(b);i++)
   {
      SigmaObserveRecoveryMinute(b[i].time,b[i].close,side,entry);
   }
   if(runtimeTrailLastBar!=completed) return;
   SigmaStateSave();
   if(entries==2){SigmaManageRetryBreakEven();return;}
   double lockR=0;
   if(!SigmaBarTrailLock(barPeakR,BarTrailActivateR,BarTrailDistanceR,BarTrailStepR,lockR)) return;
   double covered=0;
   double commission=MathMax(entryCommissionPerLot,2*SigmaEntryChargesPerLot((ulong)PositionGetInteger(POSITION_IDENTIFIER)));
   if(!SigmaCostCoveredPriceSwapAware(side,entry,commission,PositionGetDouble(POSITION_VOLUME),covered)){Note("M1_COST_INVALID","Cannot calculate a cost-covered stop");return;}
   double candidate=entry+side*lockR*initialRisk;
   double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double raw=side==1 ? MathMax(covered,candidate) : MathMin(covered,candidate);
   double desired=NormalizeDouble((side==1 ? MathCeil(raw/tick-1e-9) : MathFloor(raw/tick+1e-9))*tick,_Digits);
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
void SigmaManageRetryBreakEven()
{
   if(entries!=2 || barPeakR<BreakEvenR) return;
   int side=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY ? 1 : -1;
   double entry=PositionGetDouble(POSITION_PRICE_OPEN),sl=PositionGetDouble(POSITION_SL),tp=PositionGetDouble(POSITION_TP);
   double commission=MathMax(entryCommissionPerLot,2*SigmaEntryChargesPerLot((ulong)PositionGetInteger(POSITION_IDENTIFIER)));
   double covered=0;
   if(!SigmaCostCoveredPriceSwapAware(side,entry,commission,PositionGetDouble(POSITION_VOLUME),covered)){Note("RETRY_COST_INVALID","Cannot calculate retry cost-covered stop");return;}
   if(side*(covered-sl)<=0) return;
   MqlTick q;if(!SymbolInfoTick(_Symbol,q)) return;
   double current=side==1 ? q.bid : q.ask;
   if(side*(current-covered)<=0){CloseOwned("RETRY_BE_CROSSED");return;}
   double bound=MathMax(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL))*_Point;
   if(side*(current-covered)<=bound) return;
   ulong ticket=(ulong)PositionGetInteger(POSITION_TICKET);
   if(trade.PositionModify(ticket,covered,tp) && trade.ResultRetcode()==TRADE_RETCODE_DONE)
      Note("RETRY_BE","Cost-covered retry stop "+DoubleToString(covered,_Digits));
   else {failedOrders++;Note("RETRY_BE_REJECT",IntegerToString((int)trade.ResultRetcode()));}
}
int OnInit()
{
   { int clockInit=ClkInit(); if(clockInit!=INIT_SUCCEEDED) return clockInit; }
   ClkRefresh(ClkNowServer());   // resolve before any self-test, panel or session read
#ifdef SIGMA_VISUAL_PROBE
   if(!MQLInfoInteger(MQL_TESTER)) return INIT_FAILED;
#endif
#ifdef SIGMA_LIFECYCLE_PROBE
   if(!MQLInfoInteger(MQL_TESTER)) return INIT_FAILED;
#endif
   if(!SigmaBarTrailSelfTest() || !SigmaCalendarSelfTest() || !SigmaSignalTimeSelfTest()) {Print("SIGMA_CALC_SELFTEST_FAILED");return INIT_FAILED;}
   Print("SIGMA_CALC_SELFTEST_PASS");
   RunId=SigmaOutputFamily+(MQLInfoInteger(MQL_TESTER) ? "_test_"+IntegerToString((long)GetTickCount64()) : "_trades");
   // Parameter validation
   if(N_Sigma<1 || N_Sigma>10) return INIT_PARAMETERS_INCORRECT;
   if(BandMult<=0) return INIT_PARAMETERS_INCORRECT;
   if(!UseFixedSize && RiskCash<=0) return INIT_PARAMETERS_INCORRECT;
   if(UseFixedSize && FixedLots<=0) return INIT_PARAMETERS_INCORRECT;
   if(CommissionRTPerLot<0 || SlipPrice<0 || Magic==0) return INIT_PARAMETERS_INCORRECT;
   if(BarTrailActivateR<=0 || BarTrailDistanceR<=0 || BarTrailStepR<=0) return INIT_PARAMETERS_INCORRECT;
   // Allocate slot history arrays
   ArrayResize(slotObservations,MAX_SLOT_IDX*N_Sigma);
   ArrayInitialize(slotObservations,0.0);
   ArrayResize(slotCounts,MAX_SLOT_IDX);
   ArrayInitialize(slotCounts,0);
   SigmaClockRefresh(TimeCurrent());
   sourceTF=PERIOD_M30;
   TesterHideIndicators(true);
   if(MQLInfoInteger(MQL_TESTER) && !SigmaRuntimeSelfTest()) return INIT_FAILED;
   if(!SigmaRuntimeInit()) return INIT_FAILED;
   trade.SetExpertMagicNumber(Magic);trade.SetTypeFillingBySymbol(_Symbol);trade.SetDeviationInPoints(30);
   SigmaInitVisual();
   if(DetailedLog)
   {
      SigmaPrepareOutput();
      string name=SigmaOutputRoot+"/ledger_"+RunId+".csv";
      bool append=false;
      if(!MQLInfoInteger(MQL_TESTER))
      {append=true;name=SigmaOutputRoot+"/ledger_"+RunId+"_"+IntegerToString(runtimeAccountId)+"_"+IntegerToString((long)Magic)+".csv";}
      ledger=FileOpen(name,FILE_COMMON|FILE_WRITE|FILE_SHARE_READ|(append ? FILE_READ : 0)|FILE_CSV|FILE_ANSI,',');
      if(ledger==INVALID_HANDLE){Print("SIGMA_LOG_BLOCK: requested ledger unavailable");return INIT_FAILED;}
      if(!append || FileSize(ledger)==0) FileWrite(ledger,"server_time","event","detail");
      else FileSeek(ledger,0,SEEK_END);
   }
   PrintFormat("%s ready | new trades=%s | %s | clock=automatic server/GMT or tester weekly anchor",SigmaDisplayName,EnableTrading ? "enabled" : "disabled",SigmaSizingLabel());
   PrintFormat("SIGMA_SPEC tick=%f tickvalue=%f minlot=%f contract=%f N=%d mult=%f",SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE),SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE),SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),SymbolInfoDouble(_Symbol,SYMBOL_TRADE_CONTRACT_SIZE),N_Sigma,BandMult);
   SigmaRefreshLiveVisuals(TimeTradeServer());SigmaDraw();
   return INIT_SUCCEEDED;
}
void OnTick()
{
   if(!MQLInfoInteger(MQL_TESTER) && !SigmaRuntimeAccountContextValid()) return;
#ifdef SIGMA_LIFECYCLE_PROBE
   SigmaNativeLifecycleProbe();return;
#endif
   SigmaDraw();
   datetime now=TimeCurrent();
   if(!SigmaClockRefresh(now)){SigmaDraw();return;}
   if(!DateAllowed(now)) {CloseOwned("PHASE_LOCK");return;}
   double adjustedEquity=AccountInfoDouble(ACCOUNT_EQUITY)-totalCost;
   adjustedPeak=MathMax(adjustedPeak,adjustedEquity);adjustedDD=MathMax(adjustedDD,adjustedPeak-adjustedEquity);
   int minute=SigmaMinute(now),cutoff=SigmaSessionCutoff(now,(int)Model);
   if(OwnPosition() && SigmaDay((datetime)PositionGetInteger(POSITION_TIME))<SigmaDay(now)) {CloseOwned("OVERDUE_DAY");return;}
   if(minute>=cutoff)
   {
      if(virtualActive)
      {
         virtualActive=false;virtualExpired++;Note("VIRTUAL_CUTOFF","Unresolved first attempt expires without a broker trade");
         SigmaStateSave();
      }
      CloseOwned("CUTOFF");return;
   }
   if(!SigmaRuntimeHistoryReady()) return;
   datetime m=iTime(_Symbol,PERIOD_M1,0);
   if(m==lastMinute) return;lastMinute=m;
#ifdef SIGMA_VISUAL_PROBE
   int completed_=0;for(int y=0;y<7;y++) completed_+=yearTrades[y];
   if(completed_>=1)
   {
      string snapshot="SigmaBreakoutPreview_"+SigmaOutputFamily+".png";
      if(!gtPreviewRequested)
      {
         SigmaDraw();SigmaVisualFit();
         ResetLastError();
         gtPreviewRequested=ChartScreenShot(0,snapshot,1280,800,ALIGN_RIGHT);
         gtPreviewRequestedMs=GetTickCount64();
         PrintFormat("SIGMA_VISUAL_DIAG requested=%d error=%d chart=%I64d width=%d height=%d visual=%d path=%s",gtPreviewRequested,GetLastError(),ChartID(),ChartGetInteger(0,CHART_WIDTH_IN_PIXELS),ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS),MQLInfoInteger(MQL_VISUAL_MODE),TerminalInfoString(TERMINAL_DATA_PATH));
         if(!gtPreviewRequested){Print("SIGMA_VISUAL_SCREENSHOT_FAILED");TesterStop();}
      }
      else if(FileIsExist(snapshot) || GetTickCount64()-gtPreviewRequestedMs>5000)
      {Print(FileIsExist(snapshot) ? "SIGMA_VISUAL_SCREENSHOT_PASS" : "SIGMA_VISUAL_SCREENSHOT_TIMEOUT");TesterStop();}
      return;
   }
#endif
   ManageClosedMinute();
   if(virtualActive && SigmaDay(now)!=day){virtualActive=false;virtualExpired++;}
   if(virtualActive)
   {
      MqlRates closed[];ArraySetAsSeries(closed,false);
      datetime begin=virtualLastBar>0 ? virtualLastBar+60 : virtualStart;
      if(!M1HistoryAvailable(begin)) return;
      int count=CopyRates(_Symbol,PERIOD_M1,begin,m-60,closed);
      if(count<=0) return;
      if(!NativeBarsValid(closed,begin,m)) return;
      for(int i=0;i<count && virtualActive;i++)
      {
         virtualLastBar=closed[i].time;
         int outcome=SigmaVirtualExit(closed[i].low,closed[i].high,virtualStop,virtualTarget);
         if(outcome!=0)
         {
            if(closed[i].low<=virtualStop && closed[i].high>=virtualTarget) virtualCollisions++;
            if(outcome<0) virtualStops++;else virtualTargets++;
            virtualActive=false;
            Note("VIRTUAL_EXIT",StringFormat("bar=%s outcome=%d sl=%f tp=%f",TimeToString(closed[i].time,TIME_DATE|TIME_SECONDS),outcome,virtualStop,virtualTarget));
         }
      }
      SigmaStateSave();
   }
   // Sigma: M30 bars begin at 09:30 ET (minute=570 CT). First complete M30 = minute 600.
   if(minute<600) return;
   if(SigmaDay(now)!=day)
   {
      ResetDay(now); // resets dayValid=false via rthOpenReady=false
      SigmaStateRestore(now);
   }
   dayValid=rthOpenReady;
   if(!dayValid)
   {
      dayValid=NewDay(now);
      if(dayValid) daysReady++;
   }
   if(!dayValid) return;
   if(!M1HistoryAvailable(SigmaSessionTime(day)-3600))
   {
      dayWaiting=true;
      bool connected=MQLInfoInteger(MQL_TESTER) || TerminalInfoInteger(TERMINAL_CONNECTED);
      bool synchronized=SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_SYNCHRONIZED);
      string reason=!connected ? "CONNECTION_WAIT" : !synchronized ? "M1_SYNC_WAIT" : "M1_BOUNDARY_WAIT";
      if(dataWaitReason!=reason)
      {
         dataWaitReason=reason;
         PrintFormat("SIGMA DATA_WAIT: %s; firstM1=%s requiredFrom=%s; new entries paused, broker protection retained",reason,
            TimeToString((datetime)SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_FIRSTDATE),TIME_DATE|TIME_SECONDS),
            TimeToString(SigmaSessionTime(day)-3600,TIME_DATE|TIME_SECONDS));
      }
      return;
   }
   // Update the live band for the current slot
   if(!rangeReady)
   {
      rangeReady=SetRange(now);
      if(!rangeReady)
      {
         if(minute>=630)
         {
            dayWaiting=true;
            if(dataWaitReason!="SLOT_BAND_WAIT")
            {dataWaitReason="SLOT_BAND_WAIT";Print("SIGMA DATA_WAIT: slot band unavailable; retrying");}
         }
         return;
      }
   }
   else
   {
      // Keep band current as new slots complete
      SetRange(now);
   }
   if(dayWaiting && !MQLInfoInteger(MQL_TESTER))
      lastSignal=MathMax(lastSignal,iTime(_Symbol,sourceTF,1));
   dayWaiting=false;dataWaitReason="";
   // 1. Session Cutoff flatten at 16:00 ET (minute >= 960)
   if(OwnPosition() && minute>=cutoff)
   {
      CloseOwned("SIGMA_SESSION_CLOSE");
      return;
   }
   // 2. Band readiness and M30 signal
   if(!sigmaBandReady) return;
   MqlRates b[];ArraySetAsSeries(b,true);
   int count=2;
   if(CopyRates(_Symbol,sourceTF,1,count,b)!=count || b[0].time+PeriodSeconds(sourceTF)<=m-60) return;
   if(b[0].time<=lastSignal) return;lastSignal=b[0].time;
   SigmaStateSave();
   if(!MQLInfoInteger(MQL_TESTER) && runtimeBlocked) return;
   if(!SigmaSignalCloseEligible(SigmaMinute(b[0].time+PeriodSeconds(sourceTF)))) return;
   if(!EnableTrading) return;
   
   int side=SigmaSignalSide(2,0,b[0].close,sigmaUpperBand,sigmaLowerBand,0);
   
   // 3. Position Flip Check
   if(OwnPosition())
   {
      long posType=PositionGetInteger(POSITION_TYPE);
      if(posType==POSITION_TYPE_BUY && side==-1)
      {
         Note("SIGMA_FLIP_SIGNAL",StringFormat("Flip Long->Short at %f (lowerBand=%f)",b[0].close,sigmaLowerBand));
         sigmaFlipPendingSide=-1;
         CloseOwned("SIGMA_FLIP_CLOSE");
         return;
      }
      else if(posType==POSITION_TYPE_SELL && side==1)
      {
         Note("SIGMA_FLIP_SIGNAL",StringFormat("Flip Short->Long at %f (upperBand=%f)",b[0].close,sigmaUpperBand));
         sigmaFlipPendingSide=1;
         CloseOwned("SIGMA_FLIP_CLOSE");
         return;
      }
      return;
   }
   
   if(virtualActive) return;
   
   // 4. Pending Flip execution after flat
   if(sigmaFlipPendingSide!=0)
   {
      if(minute<cutoff)
      {
         int flip=sigmaFlipPendingSide;
         sigmaFlipPendingSide=0;
         Note("SIGMA_FLIP_EXEC",StringFormat("Executing flip entry side=%d",flip));
         Open(flip,0,0,0);
         return;
      }
      else
      {
         sigmaFlipPendingSide=0;
         return;
      }
   }
   
   // 5. Normal breakout entry
   datetime signalEnd=b[0].time+PeriodSeconds(sourceTF);
   bool retryEntry=entries==1 && retryArmed && SlPct>0.0 && firstStopDistance>0.0 && !targetFilled && side==firstSide && signalEnd>retryEligibleAfter;
   if(side!=0 && minute<cutoff && SigmaCanEnter(minute,StartMinute,cutoff,entries,SigmaMaxAttempts) && (entries==0 || retryEntry))
   {
      Note(retryEntry ? "SIGMA_RETRY_SIGNAL" : "SIGMA_SIGNAL",StringFormat("sourceOpen=%s sourceClose=%s close=%f upperBand=%f lowerBand=%f side=%d slot=%d",
           TimeToString(b[0].time,TIME_DATE|TIME_SECONDS),TimeToString(b[0].time+PeriodSeconds(sourceTF),TIME_DATE|TIME_SECONDS),
           b[0].close,sigmaUpperBand,sigmaLowerBand,side,sigmaCurrentSlot));
      Open(retryEntry ? firstSide : side,0,0,retryEntry ? firstStopDistance*SigmaRetryStopFraction : 0.0);
   }
}
void OnTradeTransaction(const MqlTradeTransaction &tx,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   if(tx.type!=TRADE_TRANSACTION_DEAL_ADD || !HistoryDealSelect(tx.deal)) return;
   if((ulong)HistoryDealGetInteger(tx.deal,DEAL_MAGIC)!=Magic || HistoryDealGetString(tx.deal,DEAL_SYMBOL)!=_Symbol) return;
   sigmaBrokerVisualDirty=true;
   long entry=HistoryDealGetInteger(tx.deal,DEAL_ENTRY);
   if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY) return;
   datetime t=(datetime)HistoryDealGetInteger(tx.deal,DEAL_TIME);MqlDateTime p;TimeToStruct(SigmaDay(t),p);
   if(ownedEntryTime>0 && SigmaDay(t)!=SigmaDay(ownedEntryTime))
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
   double entryCharges=SigmaEntryChargesPerLot(pid)*qty;
   double slipCost=MathMax(0,modelCostPerLot-entryCommissionPerLot)*qty;
   double extraCommission=MQLInfoInteger(MQL_TESTER) ? MathMax(0,entryCommissionPerLot*qty-entryCharges+exitCharges) : 0;
   double net=brokerNet-entryCharges-slipCost-extraCommission;
   if(MQLInfoInteger(MQL_TESTER)) totalCost-=MathMin(entryCommissionPerLot*qty,MathMax(0,entryCharges-exitCharges));
   SigmaStateSave();
   if(y>=0 && y<7){yearProfit[y]+=net;yearTrades[y]++;}
   int di=(int)((SigmaDay(t)-D'2020.01.01')/86400);
   if(di>=0 && di<ArraySize(dailyNet)) dailyNet[di]+=net;
   if(net>0)netWins+=net;else netLosses-=net;
   if(entries==1 && exitReason==DEAL_REASON_TP)
   {targetFilled=true;SigmaStateSave();}
   if(entries==1 && !OwnPosition() && exitReason==DEAL_REASON_SL && !targetFilled)
   {
      SigmaArmSameSideRetry(t,net<0,exitReason);
   }
   Note("EXIT",StringFormat("ticket=%I64u price=%f netAdjusted=%f reason=%d",tx.deal,exitPrice,net,exitReason));
   SigmaDrawFill(exitSide,t,exitPrice,"Exit");
}
void SigmaArmSameSideRetry(datetime t,bool losingExit,int exitReason)
{
   retryArmed=SlPct>0.0 && firstStopDistance>0.0 && entries==1 && firstSide!=0 && !targetFilled && losingExit && exitReason==DEAL_REASON_SL;
   retryEligibleAfter=retryArmed ? t : 0;
   if(retryArmed) Note("RETRY_ARMED",StringFormat("side=%d eligibleAfter=%s",firstSide,TimeToString(t,TIME_DATE|TIME_SECONDS)));
   SigmaStateSave();
}
double OnTester()
{
#ifdef SIGMA_LIFECYCLE_PROBE
   return 0;
#endif
   double net=TesterStatistics(STAT_PROFIT)-totalCost;
   double pf=netLosses>0 ? netWins/netLosses : 0;
   SigmaPrepareOutput();
   string path=SigmaOutputRoot+"/"+RunId+".csv";
   int out=FileOpen(path,FILE_COMMON|FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(out==INVALID_HANDLE) return -1000000;
   FileWrite(out,"model","net","pf","equityDD","trades","days","rejectedDays","invalidBrackets","failedOrders","worstRisk");
   FileWrite(out,SigmaDisplayName,net,pf,adjustedDD,TesterStatistics(STAT_TRADES),daysReady,daysRejected,invalidBrackets,failedOrders,worstRisk);
   FileClose(out);
   bool exported=!DetailedLog || SigmaExportTrades(path+".trades.csv");
   PrintFormat("%s TESTER_RESULT net=%.2f PF=%.6f trades=%d export=%s path=%s",SigmaDisplayName,net,pf,(int)TesterStatistics(STAT_TRADES),!DetailedLog ? "DISABLED" : exported ? "PASS" : "FAIL",path);
   return exported && failedOrders==0 && invalidBrackets==0 ? (adjustedDD>0 ? net/adjustedDD : 0) : -1000000;
}
void OnDeinit(const int reason)
{
   SigmaStateSave();EventKillTimer();
   if(runtimeLockFile!=INVALID_HANDLE) FileClose(runtimeLockFile);
   if(reason!=REASON_CHARTCHANGE || ChartSymbol(0)!=_Symbol || !ShowVisuals)
      ObjectsDeleteAll(0,SigmaVisualPrefix());
   if(gtPane!=INVALID_HANDLE)
   {
      for(int window=(int)ChartGetInteger(0,CHART_WINDOWS_TOTAL)-1;window>=1;window--) ChartIndicatorDelete(0,window,gtPaneName);
      IndicatorRelease(gtPane);
   }
   if(ledger!=INVALID_HANDLE) FileClose(ledger);
}
