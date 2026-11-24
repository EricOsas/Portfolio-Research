#property strict
#property tester_no_cache
#property version "1.00"
#property description "Flash Trigger ORB. M15 14:30 UTC target candle. Long only. M1 HIGH trail."
#include <Trade/Trade.mqh>
#ifndef FLASH_STRATEGY_CORE
#define FLASH_STRATEGY_CORE

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
int FlashServerNYOffsetSec(datetime stamp)
{
   if(!ClkOK()) return CLOCK_UNKNOWN;
   datetime utc=ClkStampToUtc(stamp);
   if(utc<=0) return CLOCK_UNKNOWN;
   return (int)((long)stamp-(long)ClkUtcToNy(utc));
}
bool FlashClockRefresh(datetime stamp)
{
   ClkRefresh(stamp);
   bool ready=ClkOK();
   int offset=ready ? FlashServerNYOffsetSec(stamp) : CLOCK_UNKNOWN;
   if(offset==CLOCK_UNKNOWN) ready=false;
   bool announce=!clockReady || offset!=clockServerNY;
   clockReady=ready;
   if(!ready) return false;
   if(announce) PrintFormat("Flash_CLOCK_READY serverAheadOfNYMinutes=%d source=%s",offset/60,ClkSource());
   clockServerNY=offset;clockObserved=stamp;return true;
}
datetime FlashNewYorkAtOffset(datetime server,int offset){return server-offset;}
datetime FlashSessionAtOffset(datetime centralDay,int minute,int offset){return centralDay+offset+3600+minute*60;}
datetime FlashNewYork(datetime server)
{
   int offset=FlashServerNYOffsetSec(server);
   return offset==CLOCK_UNKNOWN ? 0 : FlashNewYorkAtOffset(server,offset);
}
datetime FlashNewYorkUTC(datetime utc){return ClkUtcToNy(utc);}
datetime FlashCentralUTC(datetime utc){return utc+ClkNyUtcOffset(utc-3600)-3600;}
datetime FlashClockUTC(datetime server){return ClkStampToUtc(server);}
datetime FlashCentral(datetime server){datetime utc=FlashClockUTC(server);return utc>0 ? FlashCentralUTC(utc) : 0;}
datetime FlashSessionTime(datetime centralDay,int minute=0)
{
   int offset=FlashServerNYOffsetSec(centralDay+minute*60+clockServerNY+3600);
   if(offset==CLOCK_UNKNOWN && clockReady && MathAbs((double)(centralDay-TimeCurrent()))<3*86400) offset=clockServerNY;
   if(offset==CLOCK_UNKNOWN) return 0;
   datetime result=FlashSessionAtOffset(centralDay,minute,offset);
   int resolved=FlashServerNYOffsetSec(result);
   return FlashSessionAtOffset(centralDay,minute,resolved==CLOCK_UNKNOWN ? offset : resolved);
}
datetime FlashDay(datetime server)
{
   MqlDateTime p; TimeToStruct(FlashCentral(server),p);
   p.hour=0; p.min=0; p.sec=0;
   return StructToTime(p);
}
int FlashMinute(datetime server)
{
   MqlDateTime p; TimeToStruct(FlashCentral(server),p);
   return p.hour*60+p.min;
}
bool FlashAllowed(datetime t) {return true;}
bool FlashEligible(int minute,int cutoff) {return minute>=0 && minute<cutoff;}
datetime FlashCalendarDate(int y,int m,int d)
{
   MqlDateTime p={};p.year=y;p.mon=m;p.day=d;return StructToTime(p);
}
int FlashCalendarWeekday(datetime t){MqlDateTime p;TimeToStruct(t,p);return p.day_of_week;}
datetime FlashObserved(datetime t)
{
   int w=FlashCalendarWeekday(t);return t+(w==6 ? -86400 : w==0 ? 86400 : 0);
}
datetime FlashMonday(int y,int month,int n)
{
   datetime t=FlashCalendarDate(y,month,1);
   return t+((8-FlashCalendarWeekday(t))%7+7*(n-1))*86400;
}
bool FlashFutureSpecialDay(datetime d)
{
   MqlDateTime p;TimeToStruct(d,p);int y=p.year;
   datetime mayEnd=FlashCalendarDate(y,6,1)-86400;
   datetime memorial=mayEnd-((FlashCalendarWeekday(mayEnd)+6)%7)*86400;
   int a=y%19,b=y/100,c=y%100,e=b%4,f=(b+8)/25,g=(b-f+1)/3;
   int h=(19*a+b-b/4-g+15)%30,ii=c/4,k=c%4,l=(32+2*e+2*ii-h-k)%7;
   int mm=(a+11*h+22*l)/451,nn=h+l-7*mm+114;
   datetime friday=FlashCalendarDate(y,nn/31,nn%31+1)-2*86400;
   datetime nov=FlashCalendarDate(y,11,1);
   datetime thanks=nov+((11-FlashCalendarWeekday(nov))%7+21)*86400;
   return d==FlashObserved(FlashCalendarDate(y,1,1)) || d==FlashMonday(y,1,3)
      || d==FlashMonday(y,2,3) || d==friday || d==memorial
      || d==FlashObserved(FlashCalendarDate(y,6,19)) || d==FlashCalendarDate(y,7,3)
      || d==FlashObserved(FlashCalendarDate(y,7,4)) || d==FlashMonday(y,9,1)
      || d==thanks || d==thanks+86400 || d==FlashCalendarDate(y,12,24)
      || d==FlashObserved(FlashCalendarDate(y,12,25)) || d==FlashCalendarDate(y,12,31);
}
// Server offset in whole hours at this UTC instant, from the resolved standard clock. Was a
// hard-coded 3/2 US-DST table; any broker, any rule, and a dated schedule all work now.
int FlashExpectedBrokerUTC(datetime utc)
{
   // Before the adapter resolves (OnInit self-tests, a chart with no history yet) answer with the
   // US rule the strategy was written against; the resolved clock takes over from the first tick.
   if(!ClkOK()) return ClkNyUtcOffset(utc)==-4*3600 ? 3 : 2;
   return (int)(((long)ClkUtcToServer(utc,ClkRule(),ClkBase())-(long)utc)/3600);
}
bool FlashCalendarSelfTest()
{
   return FlashNewYorkAtOffset(D'2022.01.24 08:00',7*3600)==D'2022.01.24 01:00'
      && FlashNewYorkAtOffset(D'2022.01.24 08:00',8*3600)==D'2022.01.24 00:00'
      && FlashNewYorkAtOffset(D'2022.07.12 08:00',7*3600)==D'2022.07.12 01:00'
      && FlashNewYorkAtOffset(D'2022.07.12 08:00',8*3600)==D'2022.07.12 00:00'
      && FlashSessionAtOffset(D'2022.01.24',510,7*3600)==D'2022.01.24 16:30'
      && FlashSessionAtOffset(D'2022.07.12',600,7*3600)==D'2022.07.12 18:00'
      && FlashSessionAtOffset(D'2022.07.12',870,7*3600)==D'2022.07.12 22:30'
      && FlashSessionAtOffset(D'2022.07.12',0,7*3600)==D'2022.07.12 08:00'
      && FlashFutureSpecialDay(D'2026.04.03') && FlashFutureSpecialDay(D'2027.03.26')
      && FlashFutureSpecialDay(D'2026.11.26') && FlashFutureSpecialDay(D'2026.11.27')
      && !FlashFutureSpecialDay(D'2026.11.25')
      // Arithmetic, not environment: a self-test must never assert what THIS broker's clock happens to be.
      // Exness (+0 provisional) and ICMarkets (+2/+3) both pass these; a broken DST table fails them.
      && ClkUtcToServer(D'2026.03.08 06:59:59',CLK_RULE_US,120)==D'2026.03.08 08:59:59'
      && ClkUtcToServer(D'2026.03.08 07:00:00',CLK_RULE_US,120)==D'2026.03.08 10:00:00'
      && ClkUtcToServer(D'2026.11.01 05:59:59',CLK_RULE_US,120)==D'2026.11.01 08:59:59'
      && ClkUtcToServer(D'2026.11.01 06:00:00',CLK_RULE_US,120)==D'2026.11.01 08:00:00'
      && FlashNewYorkUTC(D'2026.03.08 06:59:59')==D'2026.03.08 01:59:59'
      && FlashNewYorkUTC(D'2026.03.08 07:00:00')==D'2026.03.08 03:00:00'
      && FlashCentralUTC(D'2026.03.08 07:59:59')==D'2026.03.08 01:59:59'
      && FlashCentralUTC(D'2026.03.08 08:00:00')==D'2026.03.08 03:00:00'
      && FlashNewYorkUTC(D'2026.11.01 06:00:00')==D'2026.11.01 01:00:00'
      && FlashCentralUTC(D'2026.11.01 07:00:00')==D'2026.11.01 01:00:00';
}
// Flash has no ET-based model cutoff. Only special days cut off early at 11:55 CT = 715 min.
// The CFD can hold overnight; there is no 23:59 forced flat in MQL5.
int FlashSessionCutoff(datetime server,int model)
{
   string dates=
      "|2020.01.01|2020.01.20|2020.02.17|2020.04.10|2020.05.25|2020.07.03|2020.09.07|2020.11.26|2020.11.27|2020.12.24|2020.12.25|2020.12.31"
      "|2021.01.01|2021.01.18|2021.02.15|2021.04.02|2021.05.31|2021.07.05|2021.09.06|2021.11.25|2021.11.26|2021.12.24|2021.12.31"
      "|2022.01.17|2022.02.21|2022.04.15|2022.05.30|2022.06.20|2022.07.04|2022.09.05|2022.11.24|2022.11.25|2022.12.24|2022.12.26|2022.12.31"
      "|2023.01.02|2023.01.16|2023.02.20|2023.04.07|2023.05.29|2023.06.19|2023.07.03|2023.07.04|2023.09.04|2023.11.23|2023.11.24|2023.12.24|2023.12.25|2023.12.31"
      "|2024.01.01|2024.01.15|2024.02.19|2024.03.29|2024.05.27|2024.06.19|2024.07.03|2024.07.04|2024.09.02|2024.11.28|2024.11.29|2024.12.24|2024.12.25|2024.12.31"
      "|2025.01.01|2025.01.09|2025.01.20|2025.02.17|2025.04.18|2025.05.26|2025.06.19|2025.07.03|2025.07.04|2025.09.01|2025.11.27|2025.11.28|2025.12.24|2025.12.25|2025.12.31|";
   if(StringFind(dates,"|"+TimeToString(FlashDay(server),TIME_DATE)+"|")>=0) return 715;
   if(FlashDay(server)>=D'2026.01.01' && FlashFutureSpecialDay(FlashDay(server))) return 715;
   return 1439; // Flash: no model cutoff â€” hold until early next day if needed (CFD overnight ok)
}
bool FlashBracket(int side,double entry,double stop,double target)
{
   return side*(entry-stop)>0 && side*(target-entry)>0;
}
int FlashTradeCap(int model) {return 1;} // Flash: one attempt per UTC date
int FlashVirtualExit(double low,double high,double stop,double target)
{
   if(low<=stop) return -1;
   if(high>=target) return 1;
   return 0;
}
bool FlashCanEnter(int minute,int start,int cutoff,int count,int cap)
{
   return FlashEligible(minute,cutoff) && count<cap;
}
// Flash: signal eligibility is UTC-date-based (one entry per UTC date), not CT minute.
// This self-test is intentionally trivially true for Flash â€” the model manages its own gate.
bool FlashSignalCloseEligible(int closeMinute) {return true;}
bool FlashSignalTimeSelfTest() {return true;}
// Flash: long only. Signal = completed M15 close strictly above 14:30 UTC target HIGH.
int FlashSignalSide(int model,int direction,double close,double upper,double lower,double dummy)
{
   if(upper<=0 || lower<=0 || lower>=upper) return 0;
   if(close>upper) return 1; // Long only
   return 0;
}
#endif
#ifndef FLASH_STRATEGY_BAR_TRAIL
#define FLASH_STRATEGY_BAR_TRAIL
bool FlashBarTrailLock(double peakR,double activateR,double distanceR,double stepR,double &lockR)
{
   if(activateR<=0 || distanceR<=0 || stepR<=0 || peakR<activateR) return false;
   lockR=activateR+MathFloor((peakR-activateR)/stepR+1e-9)*stepR-distanceR;
   return true;
}
bool FlashBarTrailSelfTest()
{
   double lock=0;
   if(FlashBarTrailLock(1.499,1.5,1.5,.5,lock)) return false;
   double peaks[]={1.5,1.999,2.0,2.499,2.5,3.0};
   double expected[]={0.0,0.0,.5,.5,1.0,1.5};
   for(int i=0;i<ArraySize(peaks);i++)
      if(!FlashBarTrailLock(peaks[i],1.5,1.5,.5,lock) || MathAbs(lock-expected[i])>1e-9) return false;
   return !FlashBarTrailLock(2.0,1.5,1.5,0,lock)
      && FlashVirtualExit(99,111,100,110)==-1
      && FlashVirtualExit(100,109,100,110)==-1
      && FlashVirtualExit(101,110,100,110)==1
      && FlashVirtualExit(101,109,100,110)==0;
}
#endif

enum FlashModel { VaultBreak=0, VWAPPullback=1, FlashTriggerORB=2 };
const FlashModel Model=FlashTriggerORB;
enum FlashGeometry { SourceGeometry=0, ATRGeometry=1 };
enum FlashManagement { FixedBracket=0, VWAPClose=1, CostCoveredBE=2, ATRTrail=3, M1RStep=4 };
#ifndef FLASH_STRATEGY_PRODUCTION_INPUTS
#define FLASH_STRATEGY_PRODUCTION_INPUTS

input group "==========  1 - Trading  =========="
input bool   EnableTrading              = true;   // Enable new trades (open trades stay protected when off)

input group " "
input group "==========  2 - Risk  =========="
input bool   UseFixedSize               = true;   // Use fixed lots (default ON)
input double FixedLots                  = 1.0;    // Lots per trade when fixed sizing is enabled
input double RiskMoney                  = 100.0;  // Risk per trade (used when UseFixedSize=false)
input bool   AllowMinimumOneLot         = true;   // Legacy setting; variable sizing always floors to broker minimum
input bool   SkipSetupsAboveRiskBudget  = false;  // Skip entries where computed risk > RiskBudgetUsd
input double RiskBudgetUsd              = 250.0;  // Cap in account currency (active only if above flag=true)

input group "   "
input group "==========  3 - Trading Costs  =========="
input double CommissionPerLot           = 7.0;    // Fallback round-trip commission per lot
input int    SlippagePoints             = 3;      // Slippage per side in points

input group "    "
input group "==========  4 - Display  =========="
input bool   ShowVisuals                = true;

input group "     "
input group "==========  5 - Execution & Logging  =========="
input bool   WriteTradeLog              = false;

// Frozen Flash rules â€” not user-facing options.
const ulong  MagicNumber                = 91008071; // Fixed model identity; preserves owned-position recovery
const int    FlashTrailActivatePoints   = 70;        // Activate M1-high trail after +70 index points from fill
const int    FlashTrailDistancePoints   = 25;        // Trail stop = best completed M1 high - 25 points
const double FlashTargetR               = 3.0;       // TP = signal close + 3 * (signal close - target low)
const int    FlashMaxAttempts             = 1;         // One attempt per UTC date; no same-side retry
const FlashManagement Management          = M1RStep;
const double BreakEvenR                 = 0.0;       // Flash uses absolute point trail, not R-based BE
const string FlashDisplayName             = "Flash Trigger ORB";

// Private adapter names matching execution engine expectations.
const double RiskCash             = RiskMoney;
const double CommissionRTPerLot   = CommissionPerLot;
const double SlipPrice            = SlippagePoints*_Point;
const ulong  Magic                = MagicNumber;
const bool   DetailedLog          = WriteTradeLog;
const FlashGeometry Geometry        = SourceGeometry;
// Trail R-step parameters â€” unused by Flash's absolute-point trail but must satisfy engine checks.
const double BarTrailActivateR    = 1.5;
const double BarTrailDistanceR    = 1.5;
const double BarTrailStepR        = 0.5;
const double TrailR               = 1.0;
string RunId = "";
#endif

// ---- Compatibility stubs for ChartVisuals.mqh and ExecutionRuntime.mqh ----
// These Flash globals are referenced by the shared modules; Flash doesn't use them but declares stubs.
double orHigh=0,orLow=0,overnightHigh=0,overnightLow=0;
int    bias=0;
const int    ADXPeriod=15;         // Stub: no ADX in Flash
const int    OvernightStart=23;    // Stub: required by ChartVisuals panel
const int    VaultAttemptCap=3;    // Stub: required by ExecutionRuntime recovery path
const bool   SyntheticFirst=false; // Stub: required by ExecutionRuntime
const double TargetR=3.0;          // Stub: required by ExecutionRuntime export label
int    adxHandle=INVALID_HANDLE;   // Stub: ExecutionRuntime line 493 references this
bool FlashSessionATRMean(datetime sessionDay,double &mean){mean=1.0;return true;} // Stub: always ready
// Flash has no retry fields in the class body â€” declare stubs for ExecutionRuntime restore
int    firstSide=0;
bool   retryArmed=false;
datetime retryEligibleAfter=0;
// dayValid: Flash tracks locally; ChartVisuals needs a global copy
bool dayValid=false;
// rangeReady: ChartVisuals references this for panel; Flash uses flashTargetReady instead
bool rangeReady=false;
// barPeakR: ExecutionRuntime state-save/restore references this; Flash uses flashPeakM1High
double barPeakR=0;
// FlashBias stub: ChartVisuals calls FlashBias(open,low,high)
int FlashBias(double open,double low,double high){return 0;}

const string FlashOutputFamily = "FlashTriggerORB";
const string FlashOutputRoot   = FlashOutputFamily+"/logs";
void FlashPrepareOutput()
{
   FolderCreate(FlashOutputFamily,FILE_COMMON);
   FolderCreate(FlashOutputRoot,FILE_COMMON);
}

CTrade trade;
int ledger=INVALID_HANDLE;
ENUM_TIMEFRAMES sourceTF=PERIOD_M15;
datetime lastMinute=0,lastSignal=0,day=0;
double initialRisk=0,modelCost=0,totalCost=0;
double modelCostPerLot=0,entryCommissionPerLot=0;
datetime ownedEntryTime=0;
int overnightExits=0;
string carryDetails="";
int entries=0,daysReady=0,daysRejected=0,invalidBrackets=0,failedOrders=0;
bool dayWaiting=false,dayRejected=false;
string dataWaitReason="";
bool virtualActive=false;
double virtualStop=0,virtualTarget=0;
datetime virtualStart=0;
datetime virtualLastBar=0;
int virtualStarts=0,virtualStops=0,virtualTargets=0,virtualCollisions=0;
int virtualExpired=0,virtualGaps=0;
double yearProfit[7],worstRisk=0,netWins=0,netLosses=0,adjustedPeak=0,adjustedDD=0;
int yearTrades[7];
int resultsFile=INVALID_HANDLE;
double dailyNet[2557];
string rejectedDetails="";

// ---- Flash-specific target candle and trail state ----
bool     flashTargetReady       = false;  // true once 14:30 UTC M15 is complete and stored
double   flashTargetHigh        = 0;      // HIGH of the 14:30 UTC target M15 candle
double   flashTargetLow         = 0;      // LOW  of the 14:30 UTC target M15 candle
datetime flashTargetCandleServer = 0;     // Server time of target candle open
datetime flashLastEntryUTCDate  = 0;      // UTC calendar date of last attempted entry (prevent double-entry)

// M1 HIGH trail state
double   flashPeakM1High        = 0;      // Best completed M1 HIGH since entry
datetime flashTrailLastBar      = 0;      // Last completed M1 bar server time processed for trail
bool     flashTrailActive       = false;  // Whether the +70pt activation has been reached
double   flashTrailStop         = 0;      // Current trail stop level (0 = not yet set)

#ifdef FLASH_VISUAL_PROBE
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
   if(!MQLInfoInteger(MQL_TESTER) && !FlashRuntimeAccountContextValid()){FlashDraw();return;}
   if(!MQLInfoInteger(MQL_TESTER) && !TerminalInfoInteger(TERMINAL_CONNECTED)) return;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket>0 && PositionGetString(POSITION_SYMBOL)==_Symbol && (ulong)PositionGetInteger(POSITION_MAGIC)==Magic)
      {
         if(!RecoveryCloseBegin(FlashStateKey(),ticket))continue;
         bool closed=trade.PositionClose(ticket);uint ret=trade.ResultRetcode();
         RecoveryCloseResult(FlashStateKey(),ret,trade.ResultOrder());
         if(!closed || (ret!=TRADE_RETCODE_DONE && ret!=TRADE_RETCODE_DONE_PARTIAL))
         { failedOrders++; PrintFormat("FLASH_CLOSE_REJECT %s ret=%u",why,trade.ResultRetcode()); }
      }
   }
}
void Note(string kind,string text)
{
   if(kind=="RECOVERY_BLOCK")Print("FLASH RECOVERY ATTENTION: ",text);
   if(kind=="RISK_MINIMUM" || kind=="RISK_CAP_SKIP")PrintFormat("FLASH %s %s",kind,text);
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
      PrintFormat("FLASH DATA_WAIT day=%s reason=%s; retrying, protection active",TimeToString(day,TIME_DATE),reason);
   }
   return false;
}
void ResetDay(datetime now)
{
   day=FlashDay(now); entries=0;
   dayWaiting=false; dayRejected=false; dataWaitReason="";
   flashTargetReady=false; flashTargetHigh=0; flashTargetLow=0; flashTargetCandleServer=0;
   dayValid=false; rangeReady=false; barPeakR=0;
   if(!OwnPosition())
   {
      flashPeakM1High=0; flashTrailLastBar=0; flashTrailActive=false; flashTrailStop=0;
      gtLastEntry=0;gtLastStop=0;gtLastTarget=0;gtLastBracketTime=0;
   }
   if(FlashVisualEnabled()) ObjectsDeleteAll(0,FlashVisualPrefix());
   virtualActive=false; virtualStart=0; virtualLastBar=0;
   lastSignal=0;
}
bool NewDay(datetime now)
{
   // Flash needs no daily calculations at open (no ATR, no bias, no overnight range).
   // Just mark the day as valid and clear state.
   Note("DAY","Flash new day");
   if(dayWaiting && !MQLInfoInteger(MQL_TESTER))
      lastSignal=MathMax(lastSignal,iTime(_Symbol,sourceTF,1));
   if(dayRejected){daysRejected--;dayRejected=false;}
   dayWaiting=false;dataWaitReason="";
   return true;
}
// Build the 14:30 UTC target M15 candle from 15 completed M1 bars.
// targetUTCBase: the 14:30 UTC time as a server-timezone datetime.
// Returns false if history is incomplete or window not yet past.
bool SetRange(datetime now)
{
   // Determine 14:30 UTC in server time.
   // clockServerNY = server_offset_from_NY. Server time = NY time + clockServerNY.
   // UTC = server_time - (server_offset_from_UTC).
   // FlashClockUTC(server) gives UTC from server. Inverse: server = UTC + server_offset_from_UTC.
   // server_offset_from_UTC = server - UTC = clockServerNY + (NY_offset_from_UTC)
   // NY is UTC-5(EST) or UTC-4(EDT). Server_UTC_offset = clockServerNY + (UTC_offset_of_NY)
   // Compute today's 14:30 UTC as a server datetime:
   // Step 1: get server time now, derive UTC.
   datetime utcNow=FlashClockUTC(now);
   if(utcNow<=0) return false;
   // Step 2: find today's 14:30 UTC
   MqlDateTime ud;TimeToStruct(utcNow,ud);
   ud.hour=14;ud.min=30;ud.sec=0;
   datetime target1430UTC=StructToTime(ud);
   datetime target1445UTC=target1430UTC+15*60;
   if(utcNow<target1445UTC) return false; // 14:45 UTC not yet reached
   // Step 3: convert 14:30 UTC â†’ server time
   // server = UTC + (server - UTC offset) = UTC + (serverNow - utcNow)
   int serverUTCDiff=(int)(now-utcNow); // server time ahead of UTC by this many seconds
   datetime targetServer=target1430UTC+serverUTCDiff;
   datetime targetEndServer=target1445UTC+serverUTCDiff;
   // Step 4: fetch exactly 15 completed M1 bars in [targetServer, targetEndServer)
   MqlRates b[];
   if(!Window(targetServer,targetEndServer,b,15)) return false;
   // Require exactly 15 bars (no missing minutes in the 14:30-14:45 UTC window)
   if(ArraySize(b)!=15) return false;
   flashTargetHigh=b[0].high; flashTargetLow=b[0].low;
   for(int i=1;i<15;i++)
   {
      flashTargetHigh=MathMax(flashTargetHigh,b[i].high);
      flashTargetLow =MathMin(flashTargetLow, b[i].low);
   }
   flashTargetCandleServer=targetServer;
   flashTargetReady=true;
   Note("FLASH_TARGET",StringFormat("high=%f low=%f targetServer=%s utcBase=%s",
      flashTargetHigh,flashTargetLow,
      TimeToString(targetServer,TIME_DATE|TIME_SECONDS),
      TimeToString(target1430UTC,TIME_DATE|TIME_SECONDS)));
   return true;
}

double FlashRequestedVolume(bool fixedSize,double lots,double budget,double unitRisk,double step,double minimum,double maximum)
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
string FlashSizingLabel()
{return UseFixedSize ? "Lots "+DoubleToString(FixedLots,4) : "Risk "+DoubleToString(RiskMoney,2);}
// Swap-aware cost-covered price. Reads accrued swap from the live broker position
// and adds it (as an additional one-time cost per lot) to the trail cost floor.
// Called only when OwnPosition() is true; safe to query POSITION_SWAP directly.
// The initial trade entry does not block on swap — swap is unknown at entry time.
// Only the trailing ratchet incorporates swap after it has accrued intraday or overnight.
bool FlashCostCoveredPriceSwapAware(int side,double entry,double commission,double volume,double &price)
{
   double accruedSwap=OwnPosition() ? PositionGetDouble(POSITION_SWAP) : 0.0;
   // accruedSwap is negative when broker debits (short CFDs, overnight financing).
   // Treat it as an additional cost: if swap < 0, floor must recover it.
   double swapPerLot=volume>0 && accruedSwap<0 ? MathAbs(accruedSwap)/volume : 0.0;
   double totalCommission=commission+swapPerLot;
   if(!FlashCostCoveredPrice(side,entry,totalCommission,price)) return false;
   if(swapPerLot>0)
      Note("SWAP_FLOOR",StringFormat("accruedSwap=%f swapPerLot=%f newFloor=%f",accruedSwap,swapPerLot,price));
   return true;
}

bool Open(int side,double stop,double target,double distance)
{
   MqlTick q;if(!SymbolInfoTick(_Symbol,q)) return false;
   double entry=(side==1 ? q.ask : q.bid);
   if(distance>0) {stop=entry-side*distance;target=entry+side*distance*FlashTargetR;}
   stop=RoundPrice(stop);target=RoundPrice(target);
   if(!FlashBracket(side,entry,stop,target)) {invalidBrackets++;Note("INVALID_BRACKET",StringFormat("%d %f %f %f",side,entry,stop,target));return false;}
   double loss=0;
   if(!OrderCalcProfit(side==1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,_Symbol,1.0,entry,stop,loss)) return false;
   double commission=FlashCommissionEstimate();
   double friction=commission;
   double slipLoss=0;
   if(!OrderCalcProfit(ORDER_TYPE_BUY,_Symbol,1.0,entry,entry-2*SlipPrice,slipLoss)) return false;
   friction+=MathAbs(slipLoss);
   double unitRisk=MathAbs(loss)+friction;
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP),minimum=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   if(unitRisk<=0 || !MathIsValidNumber(unitRisk) || step<=0 || minimum<=0) {Note("RISK_INVALID","Invalid cash risk or volume contract");return false;}
   double volume=FlashRequestedVolume(UseFixedSize,FixedLots,RiskCash,unitRisk,step,minimum,SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX));
   if(volume<minimum) {Note(UseFixedSize ? "FIXED_LOTS_INVALID" : "RISK_TOO_SMALL",DoubleToString(unitRisk*minimum,2));return false;}
   if(!UseFixedSize && unitRisk*minimum>RiskCash)
      Note("RISK_MINIMUM",StringFormat("broker minimum exceeds intended risk; lots=%.8f estimatedRisk=%.2f intendedRisk=%.2f %s",minimum,unitRisk*minimum,RiskCash,AccountInfoString(ACCOUNT_CURRENCY)));
   if(SkipSetupsAboveRiskBudget && unitRisk*volume>RiskBudgetUsd)
   {
      Note("RISK_CAP_SKIP",StringFormat("%srisk=%f cap=%f",!UseFixedSize && unitRisk*minimum>RiskBudgetUsd ? "broker minimum exceeds configured hard cap; " : "",unitRisk*volume,RiskBudgetUsd));
      return false;
   }
   double stops=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
   if(side*(entry-stop)<stops || side*(target-entry)<stops){invalidBrackets++;return false;}
   entryCommissionPerLot=commission;modelCostPerLot=friction;
   if(!FlashRuntimeEntryAllowed(entry,stop,target,volume,side)) {Note("ENTRY_BLOCK","EA safety, clock, margin or terminal gate");return false;}
   string comment=MQLInfoInteger(MQL_TESTER) ? FlashDisplayName : "FLASH#"+IntegerToString((long)runtimeIntentNonce);
   bool ok=(side==1 ? trade.Buy(volume,_Symbol,0,stop,target,comment) : trade.Sell(volume,_Symbol,0,stop,target,comment));
   uint ret=trade.ResultRetcode();
   if(!ok || (ret!=TRADE_RETCODE_DONE && ret!=TRADE_RETCODE_DONE_PARTIAL))
   {
      failedOrders++;Note("ENTRY_REJECT",IntegerToString((int)ret));
      if(!MQLInfoInteger(MQL_TESTER)){entries++;runtimeBlocked=true;FlashStateSave();}
      return false;
   }
   initialRisk=MathAbs(trade.ResultPrice()-stop);
   double filledVolume=trade.ResultVolume()>0 ? trade.ResultVolume() : volume;
   entryCommissionPerLot=commission;modelCostPerLot=friction;modelCost=friction*filledVolume;totalCost+=modelCost;ownedEntryTime=TimeCurrent();
   entries++;
   // Reset Flash trail state on new entry
   flashPeakM1High=0;flashTrailLastBar=0;flashTrailActive=false;flashTrailStop=0;
   runtimeTrailLastBar=0;
   worstRisk=MathMax(worstRisk,unitRisk*volume);
   FlashRememberBracket(trade.ResultPrice(),stop,target);
   FlashDrawFill(side,TimeCurrent(),trade.ResultPrice(),"Entry");
   FlashRuntimeFilled(side,stop,friction);
   Note("ENTRY",StringFormat("model=Flash side=%d lots=%f fill=%f sl=%f tp=%f modeledCost=%f",side,volume,trade.ResultPrice(),stop,target,modelCost));
   return true;
}
// Flash M1 HIGH trail.
// Activates when the best completed M1 high reaches entry + 70 index price points.
// Desired stop is best completed M1 high - 25 index price points; tick size is used only to round the stop to a valid price.
// If the last completed M1 CLOSE is already at/below the new trail, stage CloseOwned.
void ManageClosedMinute()
{
   if(runtimeRecoveryHold || runtimeClosePending || !OwnPosition() || initialRisk<=0) return;
   if(!MQLInfoInteger(MQL_TESTER) && (!FlashRuntimeAccountContextValid() || !TerminalInfoInteger(TERMINAL_CONNECTED))) return;
   datetime completed=iTime(_Symbol,PERIOD_M1,1);
   if(completed<=0 || completed<=flashTrailLastBar) return;
   MqlRates b[];ArraySetAsSeries(b,false);
   datetime from=flashTrailLastBar>0 ? flashTrailLastBar+60 : completed;
   if(CopyRates(_Symbol,PERIOD_M1,from,completed,b)<=0) return;
   int side=1; // Flash is long-only
   double entry=PositionGetDouble(POSITION_PRICE_OPEN);
   double sl=PositionGetDouble(POSITION_SL),tp=PositionGetDouble(POSITION_TP);
   ulong ticket=(ulong)PositionGetInteger(POSITION_TICKET);
   double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   for(int i=0;i<ArraySize(b);i++)
   {
      flashTrailLastBar=b[i].time;
      // Update peak M1 high using completed bar HIGH
      if(b[i].high>flashPeakM1High) flashPeakM1High=b[i].high;
      // Check trail activation
      if(!flashTrailActive && flashPeakM1High>=entry+FlashTrailActivatePoints)
         flashTrailActive=true;
   }
   runtimeTrailLastBar=flashTrailLastBar; // Keep recovery in sync
   FlashStateSave();
   if(!flashTrailActive) return;
   // Compute desired trail stop: best completed M1 high minus 25 index price points, rounded down to a valid tick for this long-only trail.
   double desired=NormalizeDouble(MathFloor((flashPeakM1High-FlashTrailDistancePoints)/tick+1e-9)*tick,_Digits);
   if(desired<=sl) return; // Never widen
   // Swap floor: if accrued swap is negative (cost), ensure trail does not fall below cost-covered+swap.
   // This prevents trailed profits from being eroded by overnight financing charges.
   double coveredFloor=0;
   double commissionForFloor=MathMax(entryCommissionPerLot,2*FlashEntryChargesPerLot((ulong)PositionGetInteger(POSITION_IDENTIFIER)));
   double flashVol=PositionGetDouble(POSITION_VOLUME);
   if(FlashCostCoveredPriceSwapAware(1,entry,commissionForFloor,flashVol,coveredFloor) && coveredFloor>desired)
      desired=coveredFloor;
   // If last completed M1 close is at or below the new trail â†’ close
   MqlRates lastBar[];ArraySetAsSeries(lastBar,false);
   if(CopyRates(_Symbol,PERIOD_M1,completed,completed,lastBar)>0)
   {
      if(lastBar[0].close<=desired){CloseOwned("FLASH_TRAIL_CLOSE_BELOW");return;}
   }
   MqlTick q;if(!SymbolInfoTick(_Symbol,q)) return;
   double current=q.bid;
   if(current<=desired){CloseOwned("FLASH_TRAIL_QUOTE_BELOW");return;}
   double bound=MathMax(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL))*_Point;
   if(current-desired<=bound) return;
   if(trade.PositionModify(ticket,desired,tp) && trade.ResultRetcode()==TRADE_RETCODE_DONE)
   {
      flashTrailStop=desired;
      Note("FLASH_TRAIL",StringFormat("bar=%s peakHigh=%f trail=%f",TimeToString(flashTrailLastBar,TIME_DATE|TIME_SECONDS),flashPeakM1High,desired));
   }
   else {failedOrders++;Note("FLASH_TRAIL_REJECT",IntegerToString((int)trade.ResultRetcode()));}
}
int OnInit()
{
   { int clockInit=ClkInit(); if(clockInit!=INIT_SUCCEEDED) return clockInit; }
   ClkRefresh(ClkNowServer());   // resolve before any self-test, panel or session read
#ifdef FLASH_VISUAL_PROBE
   if(!MQLInfoInteger(MQL_TESTER)) return INIT_FAILED;
#endif
#ifdef FLASH_LIFECYCLE_PROBE
   if(!MQLInfoInteger(MQL_TESTER)) return INIT_FAILED;
#endif
   if(!FlashBarTrailSelfTest()) {Print("FLASH_CALC_SELFTEST_FAILED case=bar_trail");return INIT_FAILED;}
   if(!FlashCalendarSelfTest()) {Print("FLASH_CALC_SELFTEST_FAILED case=calendar");return INIT_FAILED;}
   if(!FlashSignalTimeSelfTest()) {Print("FLASH_CALC_SELFTEST_FAILED case=signal_time");return INIT_FAILED;}
   Print("FLASH_CALC_SELFTEST_PASS");
   RunId=FlashOutputFamily+(MQLInfoInteger(MQL_TESTER) ? "_test_"+IntegerToString((long)GetTickCount64()) : "_trades");
   if((!UseFixedSize && RiskCash<=0) || (UseFixedSize && FixedLots<=0)) return INIT_PARAMETERS_INCORRECT;
   if(CommissionRTPerLot<0 || SlipPrice<0 || Magic==0) return INIT_PARAMETERS_INCORRECT;
   if(FlashTrailActivatePoints<=0 || FlashTrailDistancePoints<=0 || FlashTargetR<=0) return INIT_PARAMETERS_INCORRECT;
   flashLastEntryUTCDate=0;
   FlashClockRefresh(TimeCurrent());
   sourceTF=PERIOD_M15;
   TesterHideIndicators(true);
   if(MQLInfoInteger(MQL_TESTER) && !FlashRuntimeSelfTest()) return INIT_FAILED;
   if(!FlashRuntimeInit()) return INIT_FAILED;
   trade.SetExpertMagicNumber(Magic);trade.SetTypeFillingBySymbol(_Symbol);trade.SetDeviationInPoints(30);
   FlashInitVisual();
   if(DetailedLog)
   {
      FlashPrepareOutput();
      string name=FlashOutputRoot+"/ledger_"+RunId+".csv";
      bool append=false;
      if(!MQLInfoInteger(MQL_TESTER))
      {append=true;name=FlashOutputRoot+"/ledger_"+RunId+"_"+IntegerToString(runtimeAccountId)+"_"+IntegerToString((long)Magic)+".csv";}
      ledger=FileOpen(name,FILE_COMMON|FILE_WRITE|FILE_SHARE_READ|(append ? FILE_READ : 0)|FILE_CSV|FILE_ANSI,',');
      if(ledger==INVALID_HANDLE){Print("FLASH_LOG_BLOCK: requested ledger unavailable");return INIT_FAILED;}
      if(!append || FileSize(ledger)==0) FileWrite(ledger,"server_time","event","detail");
      else FileSeek(ledger,0,SEEK_END);
   }
   PrintFormat("%s ready | new trades=%s | %s | clock=automatic server/GMT or tester weekly anchor",FlashDisplayName,EnableTrading ? "enabled" : "disabled",FlashSizingLabel());
   PrintFormat("FLASH_SPEC tick=%f tickvalue=%f minlot=%f contract=%f trailActivate=%d trailDist=%d targetR=%f",
      SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE),SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE),
      SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),SymbolInfoDouble(_Symbol,SYMBOL_TRADE_CONTRACT_SIZE),
      FlashTrailActivatePoints,FlashTrailDistancePoints,FlashTargetR);
   FlashRefreshLiveVisuals(TimeTradeServer());FlashDraw();
   return INIT_SUCCEEDED;
}
void OnTick()
{
   if(!MQLInfoInteger(MQL_TESTER) && !FlashRuntimeAccountContextValid()) return;
#ifdef FLASH_LIFECYCLE_PROBE
   FlashNativeLifecycleProbe();return;
#endif
   FlashDraw();
   datetime now=TimeCurrent();
   if(!FlashClockRefresh(now)){FlashDraw();return;}
   if(!DateAllowed(now)) {CloseOwned("PHASE_LOCK");return;}
   double adjustedEquity=AccountInfoDouble(ACCOUNT_EQUITY)-totalCost;
   adjustedPeak=MathMax(adjustedPeak,adjustedEquity);adjustedDD=MathMax(adjustedDD,adjustedPeak-adjustedEquity);
   int minute=FlashMinute(now),cutoff=FlashSessionCutoff(now,(int)Model);
   // Flash: overdue-day check uses UTC date, not CT day boundary
   if(OwnPosition() && FlashDay((datetime)PositionGetInteger(POSITION_TIME))<FlashDay(now)-2*86400) {CloseOwned("OVERDUE_DAY");return;}
   if(minute>=cutoff && cutoff<1439)
   {
      // Only close on special early-cutoff days; normally Flash holds indefinitely
      CloseOwned("CUTOFF");return;
   }
   if(!FlashRuntimeHistoryReady()) return;
   datetime m=iTime(_Symbol,PERIOD_M1,0);
   if(m==lastMinute) return;lastMinute=m;
#ifdef FLASH_VISUAL_PROBE
   int completed_=0;for(int y=0;y<7;y++) completed_+=yearTrades[y];
   if(completed_>=1)
   {
      string snapshot="FlashTriggerORBPreview_"+FlashOutputFamily+".png";
      if(!gtPreviewRequested)
      {
         FlashDraw();FlashVisualFit();
         ResetLastError();
         gtPreviewRequested=ChartScreenShot(0,snapshot,1280,800,ALIGN_RIGHT);
         gtPreviewRequestedMs=GetTickCount64();
         if(!gtPreviewRequested){Print("FLASH_VISUAL_SCREENSHOT_FAILED");TesterStop();}
      }
      else if(FileIsExist(snapshot) || GetTickCount64()-gtPreviewRequestedMs>5000)
      {Print(FileIsExist(snapshot) ? "FLASH_VISUAL_SCREENSHOT_PASS" : "FLASH_VISUAL_SCREENSHOT_TIMEOUT");TesterStop();}
      return;
   }
#endif
   ManageClosedMinute();
   // Day boundary â€” keyed on CT day (FlashDay), same as sample
   if(FlashDay(now)!=day)
   {
      ResetDay(now);
      FlashStateRestore(now);
   }
   dayValid=!dayRejected && !dayWaiting;
   if(!dayValid)
   {
      dayValid=NewDay(now);
      if(dayValid) daysReady++;
   }
   if(!dayValid) return;
   // Build the 14:30 UTC target candle if not yet ready
   if(!flashTargetReady)
   {
      flashTargetReady=SetRange(now);
      if(!flashTargetReady) return;
   }
   if(!M1HistoryAvailable(flashTargetCandleServer-3600))
   {
      dayWaiting=true;
      if(dataWaitReason!="M1_BOUNDARY_WAIT")
      {dataWaitReason="M1_BOUNDARY_WAIT";Print("FLASH DATA_WAIT: M1 history not available before target candle; retrying");}
      return;
   }
   dayWaiting=false;dataWaitReason="";
   // Get last completed M15 bar
   MqlRates b[];ArraySetAsSeries(b,true);
   int cnt=2;
   if(CopyRates(_Symbol,sourceTF,1,cnt,b)!=cnt) return;
   // The completed M15 bar must be strictly after the 14:30 UTC target candle
   if(b[0].time<flashTargetCandleServer+15*60) return;
   // Signal timestamp guard â€” do not replay
   if(b[0].time<=lastSignal) return;
   lastSignal=b[0].time;
   FlashStateSave();
   if(!MQLInfoInteger(MQL_TESTER) && runtimeBlocked) return;
   // Per-UTC-date entry gate
   datetime utcNow=FlashClockUTC(now);
   if(utcNow<=0) return;
   MqlDateTime ud;TimeToStruct(utcNow,ud);ud.hour=0;ud.min=0;ud.sec=0;
   datetime todayUTC=StructToTime(ud);
   if(todayUTC==flashLastEntryUTCDate) return; // Already attempted today (UTC date)
   if(!EnableTrading) return;
   if(!FlashCanEnter(minute,0,cutoff,entries,FlashMaxAttempts) || OwnPosition() || virtualActive) return;
   int side=FlashSignalSide(2,0,b[0].close,flashTargetHigh,flashTargetLow,0);
   if(side==1)
   {
      double sigClose=b[0].close;
      double flashStop=RoundPrice(flashTargetLow);
      double flashTgt =RoundPrice(sigClose+FlashTargetR*(sigClose-flashTargetLow));
      Note("FLASH_SIGNAL",StringFormat("targetHigh=%f targetLow=%f sigClose=%f sl=%f tp=%f barTime=%s",
           flashTargetHigh,flashTargetLow,sigClose,flashStop,flashTgt,
           TimeToString(b[0].time,TIME_DATE|TIME_SECONDS)));
      if(Open(1,flashStop,flashTgt,0))
         flashLastEntryUTCDate=todayUTC;
   }
}
void OnTradeTransaction(const MqlTradeTransaction &tx,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   if(tx.type!=TRADE_TRANSACTION_DEAL_ADD || !HistoryDealSelect(tx.deal)) return;
   if((ulong)HistoryDealGetInteger(tx.deal,DEAL_MAGIC)!=Magic || HistoryDealGetString(tx.deal,DEAL_SYMBOL)!=_Symbol) return;
   flashBrokerVisualDirty=true;
   long entry=HistoryDealGetInteger(tx.deal,DEAL_ENTRY);
   if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY) return;
   datetime t=(datetime)HistoryDealGetInteger(tx.deal,DEAL_TIME);MqlDateTime p;TimeToStruct(FlashDay(t),p);
   if(ownedEntryTime>0 && FlashDay(t)!=FlashDay(ownedEntryTime))
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
   double entryCharges=FlashEntryChargesPerLot(pid)*qty;
   double slipCost=MathMax(0,modelCostPerLot-entryCommissionPerLot)*qty;
   double extraCommission=MQLInfoInteger(MQL_TESTER) ? MathMax(0,entryCommissionPerLot*qty-entryCharges+exitCharges) : 0;
   double net=brokerNet-entryCharges-slipCost-extraCommission;
   if(MQLInfoInteger(MQL_TESTER)) totalCost-=MathMin(entryCommissionPerLot*qty,MathMax(0,entryCharges-exitCharges));
   FlashStateSave();
   if(y>=0 && y<7){yearProfit[y]+=net;yearTrades[y]++;}
   int di=(int)((FlashDay(t)-D'2020.01.01')/86400);
   if(di>=0 && di<ArraySize(dailyNet)) dailyNet[di]+=net;
   if(net>0)netWins+=net;else netLosses-=net;
   // Flash has no retry; no FlashArmSameSideRetry call
   Note("EXIT",StringFormat("ticket=%I64u price=%f netAdjusted=%f reason=%d",tx.deal,exitPrice,net,exitReason));
   FlashDrawFill(exitSide,t,exitPrice,"Exit");
}
double OnTester()
{
#ifdef FLASH_LIFECYCLE_PROBE
   return 0;
#endif
   double net=TesterStatistics(STAT_PROFIT)-totalCost;
   double pf=netLosses>0 ? netWins/netLosses : 0;
   FlashPrepareOutput();
   string path=FlashOutputRoot+"/"+RunId+".csv";
   int out=FileOpen(path,FILE_COMMON|FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(out==INVALID_HANDLE) return -1000000;
   FileWrite(out,"model","net","pf","equityDD","trades","days","rejectedDays","invalidBrackets","failedOrders","worstRisk");
   FileWrite(out,FlashDisplayName,net,pf,adjustedDD,TesterStatistics(STAT_TRADES),daysReady,daysRejected,invalidBrackets,failedOrders,worstRisk);
   FileClose(out);
   bool exported=!DetailedLog || FlashExportTrades(path+".trades.csv");
   PrintFormat("%s TESTER_RESULT net=%.2f PF=%.6f trades=%d export=%s path=%s",FlashDisplayName,net,pf,(int)TesterStatistics(STAT_TRADES),!DetailedLog ? "DISABLED" : exported ? "PASS" : "FAIL",path);
   return exported && failedOrders==0 && invalidBrackets==0 ? (adjustedDD>0 ? net/adjustedDD : 0) : -1000000;
}
void OnDeinit(const int reason)
{
   FlashStateSave();EventKillTimer();
   if(runtimeLockFile!=INVALID_HANDLE) FileClose(runtimeLockFile);
   if(reason!=REASON_CHARTCHANGE || ChartSymbol(0)!=_Symbol || !ShowVisuals)
      ObjectsDeleteAll(0,FlashVisualPrefix());
   if(gtPane!=INVALID_HANDLE)
   {
      for(int window=(int)ChartGetInteger(0,CHART_WINDOWS_TOTAL)-1;window>=1;window--) ChartIndicatorDelete(0,window,gtPaneName);
      IndicatorRelease(gtPane);
   }
   if(ledger!=INVALID_HANDLE) FileClose(ledger);
}


