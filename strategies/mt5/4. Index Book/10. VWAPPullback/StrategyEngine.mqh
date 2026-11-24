#ifndef VWP_M1_CORE
#define VWP_M1_CORE
class VWPWilder
{
private:
   MqlRates previous;int index;double tr,plus,minus;
public:
   double Value,Previous,Atr;
   VWPWilder(){Reset();}
   void Reset(){index=-1;tr=plus=minus=Value=Previous=Atr=0;}
   bool Ready(){return index>=14;}
   bool Eligible(){return Ready() && Value>20 && Value<=Previous;}
   void Push(const MqlRates &b)
   {
      index++;Previous=Value;double raw=b.high-b.low;
      if(index==0){tr=raw;Value=50;Atr=raw;previous=b;return;}
      raw=MathMax(raw,MathMax(MathAbs(b.high-previous.close),MathAbs(b.low-previous.close)));
      double up=b.high-previous.high,down=previous.low-b.low;
      up=up>down && up>0?up:0;down=down>b.high-previous.high && down>0?down:0;
      int n=MathMin(index+1,14);Atr=((n-1)*Atr+raw)/n;
      if(index<14){tr+=raw;plus+=up;minus+=down;}
      else{tr=tr-tr/14+raw;plus=plus-plus/14+up;minus=minus-minus/14+down;}
      double dx=plus+minus>0?100*MathAbs(plus-minus)/(plus+minus):50;
      Value=plus+minus>0?(13*Value+dx)/14:50;previous=b;
   }
};
class VWPSetup
{
private:
   datetime session;double weighted,volume;int openingBars;bool ordered;
public:
   double High,Low,Vwap;bool H,V,R,Consumed;
   VWPSetup(){Reset();}
   void Reset(){session=0;weighted=volume=0;openingBars=0;ordered=true;High=-DBL_MAX;Low=DBL_MAX;Vwap=0;H=V=R=Consumed=false;}
   bool Ready(){return ordered && openingBars==30;}
   bool Observe(datetime ct,const MqlRates &b,double adx,double prior)
   {
      datetime d=(datetime)((long)ct/86400*86400);
      if(d!=session){Reset();session=d;}
      int m=(int)((long)ct%86400/60);if(m<510)return false;
      double q=b.real_volume>0?(double)b.real_volume:(double)b.tick_volume;
      weighted+=(b.high+b.low+b.close)/3*q;volume+=q;Vwap=volume>0?weighted/volume:0;
      if(m<540){ordered=ordered && m==510+openingBars;openingBars++;High=MathMax(High,b.high);Low=MathMin(Low,b.low);}
      if(!Ready() || m<590 || m>=954 || Consumed || Vwap<=0)return false;
      if(!H && b.close>High){H=true;return false;}
      V=V || (H && b.low<=Vwap && b.high>=Vwap);
      bool eligible=H && V && b.close>Vwap && adx>20 && adx<=prior;R=R || eligible;return eligible;
   }
};
#endif

#ifndef VWP_INDICATOR_CORE
#property strict
#property tester_no_cache
#property version "1.00"
#resource "ADXPane.ex5"
#property description "Independent USTEC strategy. Completed-bar decisions, cost-inclusive cash risk and owned-position recovery."
#include <Trade/Trade.mqh>
#ifndef VWP_STRATEGY_CORE
#define VWP_STRATEGY_CORE

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
// ORB_Scalper clock: live server/GMT detection; tester weekly-open anchor.
// No broker whitelist or fixed tester fallback.
const int CLOCK_UNKNOWN=100000;
int clockServerNY=0;
bool clockReady=false;
datetime clockObserved=0;
datetime clockWeeks[];
int clockWeekOffsets[];
// Seconds the server clock is ahead of New York at this stamp: the standard adapter owns the
// server -> UTC mapping, so this is the only clock decision left in the EA.
int VWPServerNYOffsetSec(datetime stamp)
{
   if(!ClkOK()) return CLOCK_UNKNOWN;
   datetime utc=ClkStampToUtc(stamp);
   if(utc<=0) return CLOCK_UNKNOWN;
   return (int)((long)stamp-(long)ClkUtcToNy(utc));
}
bool VWPClockRefresh(datetime stamp)
{
   ClkRefresh(stamp);
   bool ready=ClkOK();
   int offset=ready ? VWPServerNYOffsetSec(stamp) : CLOCK_UNKNOWN;
   if(offset==CLOCK_UNKNOWN) ready=false;
   bool announce=!clockReady || offset!=clockServerNY;
   clockReady=ready;
   if(!ready) return false;
   if(announce) PrintFormat("VWP_CLOCK_READY serverAheadOfNYMinutes=%d source=%s",offset/60,ClkSource());
   clockServerNY=offset;clockObserved=stamp;return true;
}
datetime VWPNewYorkAtOffset(datetime server,int offset){return server-offset;}
datetime VWPSessionAtOffset(datetime centralDay,int minute,int offset){return centralDay+offset+3600+minute*60;}
datetime VWPNewYork(datetime server)
{
   int offset=VWPServerNYOffsetSec(server);
   return offset==CLOCK_UNKNOWN ? 0 : VWPNewYorkAtOffset(server,offset);
}

datetime VWPCentralUTC(datetime utc){return utc+ClkNyUtcOffset(utc-3600)-3600;}
datetime VWPClockUTC(datetime server){return ClkStampToUtc(server);}
datetime VWPCentral(datetime server){datetime utc=VWPClockUTC(server);return utc>0 ? VWPCentralUTC(utc) : 0;}
datetime VWPSessionTime(datetime centralDay,int minute=0)
{
   int offset=VWPServerNYOffsetSec(centralDay+minute*60+clockServerNY+3600);
   if(offset==CLOCK_UNKNOWN && clockReady && MathAbs((double)(centralDay-TimeCurrent()))<3*86400) offset=clockServerNY;
   if(offset==CLOCK_UNKNOWN) return 0;
   datetime result=VWPSessionAtOffset(centralDay,minute,offset);
   int resolved=VWPServerNYOffsetSec(result);
   return VWPSessionAtOffset(centralDay,minute,resolved==CLOCK_UNKNOWN ? offset : resolved);
}

datetime VWPDay(datetime server)
{
   MqlDateTime p; TimeToStruct(VWPCentral(server),p);
   p.hour=0; p.min=0; p.sec=0;
   return StructToTime(p);
}
int VWPMinute(datetime server)
{
   MqlDateTime p; TimeToStruct(VWPCentral(server),p);
   return p.hour*60+p.min;
}


datetime VWPCalendarDate(int y,int m,int d)
{
   MqlDateTime p={};p.year=y;p.mon=m;p.day=d;return StructToTime(p);
}
int VWPCalendarWeekday(datetime t){MqlDateTime p;TimeToStruct(t,p);return p.day_of_week;}



// Server offset in whole hours at this UTC instant, from the resolved standard clock. Was a
// hard-coded 3/2 US-DST table; any broker, any rule, and a dated schedule all work now.
int VWPExpectedBrokerUTC(datetime utc)
{
   // Before the adapter resolves (OnInit self-tests, a chart with no history yet) answer with the
   // US rule the strategy was written against; the resolved clock takes over from the first tick.
   if(!ClkOK()) return ClkNyUtcOffset(utc)==-4*3600 ? 3 : 2;
   return (int)(((long)ClkUtcToServer(utc,ClkRule(),ClkBase())-(long)utc)/3600);
}

int VWPSessionCutoff(datetime server,int model){return 955;}

bool VWPBracket(int side,double entry,double stop,double target)
{
   return side*(entry-stop)>0 && side*(target-entry)>0;
}

// Closed M1 long-side path. A double touch resolves as stop first.





#endif
#ifndef VWP_STRATEGY_BAR_TRAIL
#define VWP_STRATEGY_BAR_TRAIL
// Original R = actual fill to original stop. Only completed M1 closes advance peak.


#endif

enum VWPModel { VaultBreak=0, VWAPPullback=1, OvernightBiasRangeBreakout=2 };
enum VWPGeometry { SourceGeometry=0, ATRGeometry=1 };
enum VWPManagement { FixedBracket=0, VWAPClose=1, CostCoveredBE=2, ATRTrail=3, M1RStep=4 };
const VWPModel Model=(VWPModel)1;
#ifndef VWP_STRATEGY_PRODUCTION_INPUTS
#define VWP_STRATEGY_PRODUCTION_INPUTS

input group "==========  1 - Trading  =========="
input bool   EnableTrading       = true;  // Enable new trades (open trades stay protected when off)
input bool   BlockOpposingExposure = true; // Block opposing chart-symbol / index exposure in this account

input group " "
input group "==========  2 - Risk  =========="
input double RiskMoney           = 100.0; // Risk per trade, including costs (account currency)
input bool   UseFixedSize        = false; // Use fixed lots instead of the cash risk budget
input double FixedLots           = 1.0;   // Lots per trade when fixed sizing is enabled

input group "  "
input group "==========  3 - Trading Costs  =========="
input double CommissionPerLot    = 7.0;   // Fallback round-trip commission per lot until broker history is available
input int    SlippagePoints      = 3;     // Slippage/side (x0.01; 3=0.03 price)

// Frozen strategy rules: not user-facing options or alternate models.
const int ATRPeriod=14,ADXPeriod=14,OvernightStart=23,VaultAttemptCap=3;
const double NoiseFraction=0.30,StopPoints=75.0,TargetPoints=40.0,TargetR=1.27;
const bool SyntheticFirst=false;
const VWPManagement Management=FixedBracket;
const double BarTrailActivateR=1.5,BarTrailDistanceR=1.5;
const double TrailActivationR=1.0,TrailDistanceR=0.25,TrailStepR=0.25;
const string VWPDisplayName="VWAP Pullback";

input group "   "
input group "==========  4 - Display  =========="
input bool   ShowVisuals         = true;  // Show chart levels, trade markers and information

input group "    "
input group "==========  5 - Execution & Logging  =========="
const ulong  MagicNumber         = 91008013; // Fixed model identity; preserves owned-position recovery
input bool   WriteTradeLog       = false; // Write a detailed trade and decision log


// Private adapter to the existing, validated execution engine.
const int StartMinute=590;
const double RiskCash=RiskMoney,CommissionRTPerLot=CommissionPerLot,SlipPrice=SlippagePoints*0.01;
const ulong Magic=MagicNumber;
const bool DetailedLog=WriteTradeLog;
const VWPGeometry Geometry=SourceGeometry;
const double BreakEvenR=0.5,TrailR=1.0,BarTrailStepR=0.5;
string RunId="";
#endif

const string VWPOutputFamily="VWAPPullback";
const string VWPOutputRoot=VWPOutputFamily+"/logs";
void VWPPrepareOutput()
{
   FolderCreate(VWPOutputFamily,FILE_COMMON);
   FolderCreate(VWPOutputRoot,FILE_COMMON);
}

CTrade trade;
int atrHandle=INVALID_HANDLE, adxHandle=INVALID_HANDLE, ledger=INVALID_HANDLE;
ENUM_TIMEFRAMES sourceTF=PERIOD_M1;
datetime lastMinute=0,lastSignal=0,day=0;
double averageATR=0,orHigh=0,orLow=0,overnightHigh=0,overnightLow=0;
double initialRisk=0,modelCost=0,totalCost=0;
double modelCostPerLot=0,entryCommissionPerLot=0;
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
double trailPeakClose=0;
int trailConfirmations=0;
bool trailArmed=false;
datetime trailLastBar=0;
double yearProfit[7],worstRisk=0,netWins=0,netLosses=0,adjustedPeak=0,adjustedDD=0;
int yearTrades[7];
int resultsFile=INVALID_HANDLE;
double dailyNet[2557];
string rejectedDetails="";
#ifdef VWP_VISUAL_PROBE
bool gtPreviewRequested=false;
ulong gtPreviewRequestedMs=0;
#endif
VWPWilder m1;
VWPSetup setup;
datetime modelLast=0,reconnectFloor=0;
datetime modelRetry=0;
datetime modelCurveTime=0;
double modelCurveValue=0;
bool modelBooted=false,modelDisconnected=false;
string modelStatus="Loading completed M1 data";
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

double RoundPrice(double price)
{
   double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   return NormalizeDouble(MathRound(price/tick)*tick,_Digits);
}
void CloseOwned(string why)
{
   if(!MQLInfoInteger(MQL_TESTER) && (!VWPRuntimeAccountContextValid() || !TerminalInfoInteger(TERMINAL_CONNECTED))) return;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket>0 && PositionGetString(POSITION_SYMBOL)==_Symbol && (ulong)PositionGetInteger(POSITION_MAGIC)==Magic)
      {
         if(!RecoveryCloseBegin(VWPStateKey(),ticket))continue;
         bool closed=trade.PositionClose(ticket);uint ret=trade.ResultRetcode();
         RecoveryCloseResult(VWPStateKey(),ret,trade.ResultOrder());
         if(!closed || (ret!=TRADE_RETCODE_DONE && ret!=TRADE_RETCODE_DONE_PARTIAL))
         { failedOrders++; PrintFormat("VWP_CLOSE_REJECT %s ret=%u",why,trade.ResultRetcode()); }
      }
   }
}
void Note(string kind,string text)
{
   if(kind=="RECOVERY_BLOCK")Print("VWP RECOVERY ATTENTION: ",text);
   if(DetailedLog && ledger!=INVALID_HANDLE)
   {
      FileWrite(ledger,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),kind,text);
      FileFlush(ledger); // Make decision events readable during visual tester diagnostics too.
   }
}






// Model daily candles end at 17:00 New York, independent of broker midnight.




double VWPRequestedVolume(bool fixedSize,double lots,double budget,double unitRisk,double step,double minimum,double maximum)
{
   if(unitRisk<=0 || !MathIsValidNumber(unitRisk) || step<=0 || minimum<=0 || maximum<minimum) return 0;
   if(fixedSize)
   {
      if(!MathIsValidNumber(lots) || lots<minimum || lots>maximum || MathAbs(lots/step-MathRound(lots/step))>1e-7) return 0;
      return lots;
   }
   return MathMin(MathFloor(budget/unitRisk/step+1e-9)*step,maximum);
}
string VWPSizingLabel()
{return UseFixedSize ? "Lots "+DoubleToString(FixedLots,4) : "Risk "+DoubleToString(RiskMoney,2);}
bool VWPEnsureFilledBracket(ulong ticket,int side,double fill,double stop,double target)
{
   if(!VWPBracket(side,fill,stop,target))return false;
   double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double existingStop=PositionGetDouble(POSITION_SL),existingTarget=PositionGetDouble(POSITION_TP);
   // The initial order may already carry the exact actual-fill bracket. Some
   // brokers reject redundant modifications; their existing protection is valid.
   if(tick>0 && MathAbs(existingStop-stop)<=tick*1e-6 && MathAbs(existingTarget-target)<=tick*1e-6)return true;
   bool modified=trade.PositionModify(ticket,stop,target);
   bool accepted=modified && (trade.ResultRetcode()==TRADE_RETCODE_DONE || trade.ResultRetcode()==TRADE_RETCODE_NO_CHANGES);
   if(!accepted)PrintFormat("VWP_FILL_BRACKET_REJECT ticket=%I64u fill=%.8f existingSL=%.8f existingTP=%.8f requestedSL=%.8f requestedTP=%.8f ret=%u",ticket,fill,existingStop,existingTarget,stop,target,trade.ResultRetcode());
   return accepted;
}
bool Open(int side,double stop,double target,double distance)
{
   MqlTick q;if(!SymbolInfoTick(_Symbol,q)) return false;
   double entry=(side==1 ? q.ask : q.bid);
   if(distance>0) {stop=entry-side*distance;target=entry+side*distance*TargetR;}
   double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tick<=0)return false;
   stop=NormalizeDouble(MathCeil(stop/tick-1e-9)*tick,_Digits);
   target=NormalizeDouble(MathFloor((entry+(entry-stop)*TargetR)/tick+1e-9)*tick,_Digits);
   if(!VWPBracket(side,entry,stop,target)) {invalidBrackets++;Note("INVALID_BRACKET",StringFormat("%d %f %f %f",side,entry,stop,target));return false;}
   double loss=0;
   if(!OrderCalcProfit(side==1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,_Symbol,1.0,entry,stop,loss)) return false;
   double commission=VWPCommissionEstimate();
   double friction=commission;
   double slipLoss=0;
   if(!OrderCalcProfit(ORDER_TYPE_BUY,_Symbol,1.0,entry,entry-2*SlipPrice,slipLoss)) return false;
   friction+=MathAbs(slipLoss);
   double unitRisk=MathAbs(loss)+friction;
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP),minimum=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   if(unitRisk<=0 || !MathIsValidNumber(unitRisk) || step<=0 || minimum<=0) {Note("RISK_INVALID","Invalid cash risk or volume contract");return false;}
   double volume=VWPRequestedVolume(UseFixedSize,FixedLots,RiskCash,unitRisk,step,minimum,SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX));
   if(volume<minimum || unitRisk<=0)
   {
      modelStatus=UseFixedSize?"Invalid fixed lot quantity":"Minimum lot risk "+DoubleToString(unitRisk*minimum,2);
      Note(UseFixedSize ? "FIXED_LOTS_INVALID" : "RISK_TOO_SMALL",DoubleToString(unitRisk*minimum,2));return false;
   }
   double stops=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
   if(side*(entry-stop)<stops || side*(target-entry)<stops){invalidBrackets++;return false;}
   entryCommissionPerLot=commission;modelCostPerLot=friction;
   if(!VWPRuntimeEntryAllowed(entry,stop,target,volume,side)) {Note("ENTRY_BLOCK","EA safety, clock, margin or terminal gate");return false;}
   string comment=MQLInfoInteger(MQL_TESTER) ? VWPDisplayName : "VWP#"+IntegerToString((long)runtimeIntentNonce);
   bool ok=(side==1 ? trade.Buy(volume,_Symbol,0,stop,target,comment) : trade.Sell(volume,_Symbol,0,stop,target,comment));
   uint ret=trade.ResultRetcode();
   if(!ok || (ret!=TRADE_RETCODE_DONE && ret!=TRADE_RETCODE_DONE_PARTIAL))
   {
      failedOrders++;Note("ENTRY_REJECT",IntegerToString((int)ret));
      if(!MQLInfoInteger(MQL_TESTER)){entries++;runtimeBlocked=true;VWPStateSave();}
      return false;
   }
   double fill=trade.ResultPrice(),entryVolume=trade.ResultVolume();
   if(distance>0 && OwnPosition())
   {
      fill=PositionGetDouble(POSITION_PRICE_OPEN);
      stop=NormalizeDouble(MathCeil((fill-distance)/tick-1e-9)*tick,_Digits);
      target=NormalizeDouble(MathFloor((fill+TargetR*(fill-stop))/tick+1e-9)*tick,_Digits);
      ulong ticket=(ulong)PositionGetInteger(POSITION_TICKET);
      if(!VWPRuntimeStageFilledBracket(side,stop,target,friction))return false;
      if(!VWPEnsureFilledBracket(ticket,side,fill,stop,target))
      {
         entries++;runtimeBlocked=true;CloseOwned("FILL_BRACKET_REJECT");VWPStateSave();return false;
      }
   }
   initialRisk=MathAbs(fill-stop);beDone=false;barPeakR=0;
   trailPeakClose=fill;trailConfirmations=0;trailArmed=false;trailLastBar=0;
   double filledVolume=entryVolume>0 ? entryVolume : volume;
   entryCommissionPerLot=commission;modelCostPerLot=friction;modelCost=friction*filledVolume;totalCost+=modelCost;ownedEntryTime=TimeCurrent();
   entries++;worstRisk=MathMax(worstRisk,unitRisk*volume);
   VWPRememberBracket(fill,stop,target);
   VWPDrawFill(side,TimeCurrent(),fill,"Entry");
   VWPRuntimeFilled(side,stop,friction);
   Note("ENTRY",StringFormat("model=%d side=%d lots=%f fill=%f sl=%f tp=%f atr=%f count=%d modeledCost=%f",Model,side,volume,fill,stop,target,averageATR,entries,modelCost));
   return true;
}

double VWPTrailLevel(double entry,double risk,double peak,double cost,double tick)
{
   return MathCeil(MathMax(entry+cost,peak-TrailDistanceR*risk)/tick-1e-9)*tick;
}
void VWPTrailObserve(double entry,double close)
{
   trailPeakClose=MathMax(trailPeakClose,close);
   trailConfirmations=close-entry>=TrailActivationR*initialRisk ? trailConfirmations+1 : 0;
   if(trailConfirmations>=2)trailArmed=true;
}
void VWPTrail(const MqlRates &bar,bool apply)
{
   if(runtimeRecoveryHold || runtimeClosePending || !OwnPosition() || initialRisk<=0 || ownedEntryTime<=0 || bar.time<=trailLastBar
      || bar.time<ownedEntryTime || PositionGetInteger(POSITION_TYPE)!=POSITION_TYPE_BUY)return;
   double entry=PositionGetDouble(POSITION_PRICE_OPEN);
   VWPTrailObserve(entry,bar.close);trailLastBar=bar.time;
   if(apply)VWPStateSave();
   // Reconstruct state from history, but amend protection only after the fresh M1 close.
   if(!apply || !trailArmed)return;
   if(!MQLInfoInteger(MQL_TESTER) && (!VWPRuntimeAccountContextValid() || !TerminalInfoInteger(TERMINAL_CONNECTED)))return;
   double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE),gain=0;
   if(tick<=0 || !OrderCalcProfit(ORDER_TYPE_BUY,_Symbol,1.0,entry,entry+tick,gain) || gain<=0)return;
   double cost=modelCostPerLot*tick/gain;
   double next=NormalizeDouble(VWPTrailLevel(entry,initialRisk,trailPeakClose,cost,tick),_Digits);
   double stop=PositionGetDouble(POSITION_SL),target=PositionGetDouble(POSITION_TP);
   if(stop<=0 || target<=0 || next-stop<TrailStepR*initialRisk-1e-9)return;
   MqlTick quote;if(!SymbolInfoTick(_Symbol,quote))return;
   if(next>=bar.close || next>=quote.bid){CloseOwned("TrailCrossed");return;}
   double minimum=MathMax(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),
                          SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL))*_Point;
   if(quote.bid-next<minimum)return; // Keep existing protection until the broker can accept the tighter stop.
   ulong ticket=(ulong)PositionGetInteger(POSITION_TICKET);
   if(!trade.PositionModify(ticket,next,target)
      || (trade.ResultRetcode()!=TRADE_RETCODE_DONE && trade.ResultRetcode()!=TRADE_RETCODE_NO_CHANGES))
   {Note("TRAIL_REJECT",StringFormat("stop=%f ret=%u",next,trade.ResultRetcode()));return;}
   VWPRememberBracket(entry,next,target);
   Note("TRAIL",StringFormat("source=%s stop=%f peakClose=%f",TimeToString(bar.time,TIME_DATE|TIME_SECONDS),next,trailPeakClose));
}


int OnInit()
{
   { int clockInit=ClkInit(); if(clockInit!=INIT_SUCCEEDED) return clockInit; }
   ClkRefresh(ClkNowServer());   // resolve before any self-test, panel or session read
   RunId=VWPOutputFamily+(MQLInfoInteger(MQL_TESTER)?"_test_"+IntegerToString((long)GetTickCount64()):"_trades");
   if((!UseFixedSize && (!MathIsValidNumber(RiskMoney) || RiskMoney<=0)) || (UseFixedSize && (!MathIsValidNumber(FixedLots) || FixedLots<=0))
      || CommissionPerLot<0 || SlippagePoints<0)return INIT_PARAMETERS_INCORRECT;
   sourceTF=PERIOD_M1;TesterHideIndicators(true);
   VWPClockRefresh(TimeCurrent());
   trade.SetExpertMagicNumber(Magic);trade.SetTypeFillingBySymbol(_Symbol);trade.SetDeviationInPoints(30);
   if(!VWPRuntimeInit())return INIT_FAILED;
   VWPInitVisual();
   if(DetailedLog)
   {
      VWPPrepareOutput();
      string path=VWPOutputRoot+"/"+RunId+"_"+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+".csv";
      ledger=FileOpen(path,FILE_COMMON|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_CSV|FILE_ANSI,',');
      if(ledger==INVALID_HANDLE)return INIT_FAILED;
      FileSeek(ledger,0,SEEK_END);
   }
   ModelUpdate(false);VWPDraw();
   Print("VWAP Pullback ready | 09:50 CT arm | M1 ADX14 | 3ATR14 stop / 1.27R + two-close trail | automatic clock");
   return INIT_SUCCEEDED;
}
void OnTick()
{
   if(!MQLInfoInteger(MQL_TESTER) && !VWPRuntimeAccountContextValid()){VWPDraw();return;}
   datetime now=TimeCurrent();
   if(!VWPClockRefresh(now)){VWPDraw();return;}
   if(OwnPosition() && (VWPDay((datetime)PositionGetInteger(POSITION_TIME))<VWPDay(now) || VWPMinute(now)>=955))
      CloseOwned("TIME_EXIT");
   if(!VWPRuntimeHistoryReady()){VWPDraw();return;}
   ModelUpdate(true);VWPDraw();
}
void ModelMark(string gate,const MqlRates &bar,int shift)
{
   if(!VWPVisualDataEnabled())return;
   string id=VWPVisualPrefix()+gate+"_"+IntegerToString((long)bar.time);
   if(ObjectFind(0,id)<0)ObjectCreate(0,id,OBJ_TEXT,0,bar.time,bar.low-shift*SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE));
   ObjectSetString(0,id,OBJPROP_TEXT,gate);ObjectSetString(0,id,OBJPROP_FONT,"Segoe UI");
   ObjectSetInteger(0,id,OBJPROP_FONTSIZE,8);ObjectSetInteger(0,id,OBJPROP_COLOR,clrDeepSkyBlue);
   ObjectSetInteger(0,id,OBJPROP_BACK,true);
}
void ModelCurve(datetime left,double a,datetime right,double b)
{
   if(!VWPVisualDataEnabled() || a<=0 || b<=0 || left<=0)return;
   string id=VWPVisualPrefix()+"VWAP_"+IntegerToString((long)left);
   if(ObjectFind(0,id)<0)ObjectCreate(0,id,OBJ_TREND,0,left,a,right,b);
   else{ObjectMove(0,id,0,left,a);ObjectMove(0,id,1,right,b);}
   ObjectSetInteger(0,id,OBJPROP_COLOR,clrDeepSkyBlue);ObjectSetInteger(0,id,OBJPROP_STYLE,STYLE_DOT);
   ObjectSetInteger(0,id,OBJPROP_BACK,true);
   ObjectSetInteger(0,id,OBJPROP_WIDTH,1);ObjectSetInteger(0,id,OBJPROP_RAY_RIGHT,false);
   ObjectSetInteger(0,id,OBJPROP_SELECTABLE,false);ObjectSetInteger(0,id,OBJPROP_HIDDEN,true);
}
void ModelUpdate(bool allowEntry)
{
   datetime current=iTime(_Symbol,PERIOD_M1,0);
   if(current<=0 || !clockReady)return;
   bool connected=MQLInfoInteger(MQL_TESTER) || TerminalInfoInteger(TERMINAL_CONNECTED);
   if(!connected){modelDisconnected=true;modelStatus="Disconnected | orders paused";return;}
   if(modelDisconnected){reconnectFloor=current;modelDisconnected=false;modelBooted=false;}
   if(!modelBooted && TimeCurrent()<modelRetry)return;
   if(modelBooted && current<=modelLast+60)return;
   MqlRates bars[];ArraySetAsSeries(bars,false);
   datetime from=modelBooted?modelLast+60:VWPSessionTime(VWPDay(current))-3*86400;
   int count=CopyRates(_Symbol,PERIOD_M1,from,current-60,bars);
   if(count<=0 || !SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_SYNCHRONIZED))return;
   if(!modelBooted)
   {
      m1.Reset();setup.Reset();
      modelCurveTime=0;modelCurveValue=0;
      day=VWPDay(current);rangeReady=dayValid=false;armed=touched=false;
      if(VWPVisualEnabled())ObjectsDeleteAll(0,VWPVisualPrefix()+"VWAP_");
      VWPStateRestore(current);
   }
   bool bootstrap=!modelBooted,triedEntry=false;
   for(int i=0;i<count;i++)
   {
      MqlRates b=bars[i];datetime ct=VWPCentral(b.time);
      if(ct<=0){modelStatus="Clock history loading";return;}
      datetime bd=VWPDay(b.time);
      if(bd==VWPDay(current) && modelLast>0 && b.time>modelLast+60
         && VWPDay(modelLast)==bd && VWPMinute(modelLast+60)>=510 && VWPMinute(modelLast+60)<955)
      {
         modelBooted=false;modelRetry=TimeCurrent()+30;
         modelStatus="Reloading missing M1 history";return;
      }
      if(bd!=day && bd==VWPDay(current))
      {
         entries=0;day=bd;VWPStateRestore(current);
         gtLastEntry=gtLastStop=gtLastTarget=0;
         if(VWPVisualEnabled())ObjectsDeleteAll(0,VWPVisualPrefix()+"VWAP_");
         modelCurveTime=0;modelCurveValue=0;
      }
      m1.Push(b);
      VWPTrail(b,b.time+60==current);
      bool h=setup.H,v=setup.V,r=setup.R;
      bool qualified=setup.Observe(ct,b,m1.Value,m1.Previous);
      modelLast=b.time;
      if(bd!=VWPDay(current))continue;
      averageATR=m1.Atr;orHigh=setup.High;orLow=setup.Low;
      rangeReady=dayValid=setup.Ready();armed=setup.H;touched=setup.V;bias=1;
      if(VWPMinute(b.time)>=510 && VWPMinute(b.time)<955)
      {ModelCurve(modelCurveTime,modelCurveValue,b.time+60,setup.Vwap);modelCurveValue=setup.Vwap;modelCurveTime=b.time+60;}
      if(!h && setup.H)ModelMark("H",b,2);
      if(!v && setup.V)ModelMark("V",b,4);
      if(!r && qualified)ModelMark("R",b,6);
      if((!h && setup.H) || (!v && setup.V) || (!r && qualified))
         Note("GATE",StringFormat("source=%s ct=%s H=%d V=%d R=%d close=%f high=%f low=%f volume=%I64d rangeHigh=%f vwap=%f adx=%f priorAdx=%f atr=%f",
              TimeToString(b.time,TIME_DATE|TIME_SECONDS),TimeToString(ct,TIME_DATE|TIME_SECONDS),setup.H,setup.V,setup.R,
              b.close,b.high,b.low,b.real_volume>0 ? b.real_volume : b.tick_volume,setup.High,setup.Vwap,m1.Value,m1.Previous,m1.Atr));
      if(qualified && (bootstrap || b.time+60<current || b.time+60<=reconnectFloor))
         setup.Consumed=true; // Do not turn a previously completed trigger into a late broker entry.
      bool fresh=b.time+60==current && b.time>lastSignal && b.time+60>reconnectFloor;
      if(qualified && allowEntry && !bootstrap && fresh && EnableTrading && !runtimeBlocked && entries<1
         && VWPMinute(current)<955 && !OwnPosition() && m1.Ready())
      {
         triedEntry=true;modelStatus="Entry blocked | broker/risk gate";
         lastSignal=b.time;VWPStateSave();
         if(Open(1,0,0,3*m1.Atr))setup.Consumed=true;
      }
   }
   modelBooted=true;lastSignal=MathMax(lastSignal,modelLast);
   if(!rangeReady && VWPMinute(current)>=540 && VWPMinute(current)<955)
   {
      modelBooted=false;modelRetry=TimeCurrent()+30;
      modelStatus="Reloading opening range history";return;
   }
   if(entries>0)setup.Consumed=true;
   if(triedEntry && !OwnPosition() && entries==0)return;
   modelStatus=OwnPosition()?"Broker position protected":entries>0?"Daily trade consumed":setup.Consumed?"Setup passed | no stale entry":!rangeReady?"Opening range forming":
      !setup.H?"Waiting for 09:50 range close":!setup.V?"H armed | waiting for VWAP":"Waiting for reclaim + ADX";
}
void OnTradeTransaction(const MqlTradeTransaction &tx,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   if(tx.type!=TRADE_TRANSACTION_DEAL_ADD || !HistoryDealSelect(tx.deal)) return;
   if((ulong)HistoryDealGetInteger(tx.deal,DEAL_MAGIC)!=Magic || HistoryDealGetString(tx.deal,DEAL_SYMBOL)!=_Symbol) return;
   vwpBrokerVisualDirty=true;
   long entry=HistoryDealGetInteger(tx.deal,DEAL_ENTRY);
   if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY) return;
   datetime t=(datetime)HistoryDealGetInteger(tx.deal,DEAL_TIME);MqlDateTime p;TimeToStruct(VWPDay(t),p);
   if(ownedEntryTime>0 && VWPDay(t)!=VWPDay(ownedEntryTime))
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
   double entryCharges=VWPEntryChargesPerLot(pid)*qty;
   double slipCost=MathMax(0,modelCostPerLot-entryCommissionPerLot)*qty;
   double extraCommission=MQLInfoInteger(MQL_TESTER) ? MathMax(0,entryCommissionPerLot*qty-entryCharges+exitCharges) : 0;
   // Broker-net already contains exit charges; include allocated entry charges once.
   double net=brokerNet-entryCharges-slipCost-extraCommission;
   if(MQLInfoInteger(MQL_TESTER)) totalCost-=MathMin(entryCommissionPerLot*qty,MathMax(0,entryCharges-exitCharges));
   VWPStateSave();
   if(y>=0 && y<7){yearProfit[y]+=net;yearTrades[y]++;}
   int di=(int)((VWPDay(t)-D'2020.01.01')/86400);
   if(di>=0 && di<ArraySize(dailyNet)) dailyNet[di]+=net;
   if(net>0)netWins+=net;else netLosses-=net;
   Note("EXIT",StringFormat("ticket=%I64u price=%f netAdjusted=%f reason=%d",tx.deal,exitPrice,net,exitReason));
   VWPDrawFill(exitSide,t,exitPrice,"Exit");
}
double OnTester()
{
#ifdef VWP_LIFECYCLE_PROBE
   return 0;
#endif
   double net=TesterStatistics(STAT_PROFIT)-totalCost;
   double pf=netLosses>0 ? netWins/netLosses : 0;
   VWPPrepareOutput();
   string path=VWPOutputRoot+"/"+RunId+".csv";
   int out=FileOpen(path,FILE_COMMON|FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(out==INVALID_HANDLE) return -1000000;
   FileWrite(out,"model","net","pf","equityDD","trades","days","rejectedDays","invalidBrackets","failedOrders","worstRisk");
   FileWrite(out,Model,net,pf,adjustedDD,TesterStatistics(STAT_TRADES),daysReady,daysRejected,invalidBrackets,failedOrders,worstRisk);
   FileClose(out);
   bool exported=!DetailedLog || VWPExportTrades(path+".trades.csv");
   PrintFormat("%s TESTER_RESULT net=%.2f PF=%.6f trades=%d export=%s path=%s",VWPDisplayName,net,pf,(int)TesterStatistics(STAT_TRADES),!DetailedLog ? "DISABLED" : exported ? "PASS" : "FAIL",path);
   return exported && failedOrders==0 && invalidBrackets==0 ? (adjustedDD>0 ? net/adjustedDD : 0) : -1000000;
}
void OnDeinit(const int reason)
{
   VWPStateSave();EventKillTimer();
   if(runtimeLockFile!=INVALID_HANDLE) FileClose(runtimeLockFile);
   // A timeframe reload must not erase the session levels while history warms up.
   if(reason!=REASON_CHARTCHANGE || ChartSymbol(0)!=_Symbol || !ShowVisuals)
      ObjectsDeleteAll(0,VWPVisualPrefix());
   if(gtPane!=INVALID_HANDLE)
   {
      for(int window=(int)ChartGetInteger(0,CHART_WINDOWS_TOTAL)-1;window>=1;window--) ChartIndicatorDelete(0,window,gtPaneName);
      IndicatorRelease(gtPane);
   }
   if(ledger!=INVALID_HANDLE) FileClose(ledger);
   if(atrHandle!=INVALID_HANDLE) IndicatorRelease(atrHandle);
   if(adxHandle!=INVALID_HANDLE) IndicatorRelease(adxHandle);
}


#endif

