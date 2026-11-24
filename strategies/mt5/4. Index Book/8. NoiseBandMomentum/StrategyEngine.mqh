//+------------------------------------------------------------------+
//| StrategyEngine.mqh - Noise Band Momentum: session, signal, size   |
//|                                                                  |
//|  Pure decision layer: no order is sent from this file. It answers |
//|  "what is the reference, what is the band, what is the side, what |
//|  is the stop distance, what is the lot" and hands that to the     |
//|  runtime. Every input it reads is declared in the .mq5 above the  |
//|  include, so the numbers here are exactly what the user set.      |
//+------------------------------------------------------------------+
#ifndef NBM_STRATEGY_ENGINE
#define NBM_STRATEGY_ENGINE

#define TF PERIOD_M30

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

// Per-symbol state. One entry per tradable symbol in InpSymbols.
string   g_sym[];        // symbols actually traded
int      g_atr[];        // ATR handle per symbol
datetime g_lastBar[];    // last 30-minute candle that was evaluated
datetime g_entryTime[];  // open time of the entry candle
double   g_stopDist[];   // initial stop distance in price (= 1 R)
double   g_best[];       // best price since entry (for trailing)
datetime g_lastTrail[];  // last trailing update
// Per-symbol state is mirrored to terminal GlobalVariables so a restart resumes, not restarts.


//+------------------------------------------------------------------+
//| Session helpers - every session boundary is a New York wall time  |
//|                                                                  |
//|  The clock adapter turns a server stamp into UTC, so the session  |
//|  is expressed as minutes after New York midnight (570 = 09:30 NY) |
//|  instead of a server hour that only means 09:30 on a broker at    |
//|  New York + 7 h, and only until that broker changes its offset.   |
//|  This is the only place the EA learns what time it is.            |
//+------------------------------------------------------------------+
// Checkpoint index K (1..InpCheckpoints) when the closed candle opens exactly on a half hour
// after the New York open; 0 when this candle is not a checkpoint.
int NBMCheckpoint(const string sym)
{
   datetime barOpen = iTime(sym, TF, 1);
   if(barOpen <= 0)
      return(0);
   // The checkpoint must be the bar that has just closed. After a data hole the newest closed bar
   // is hours old; acting on it enters a stale signal outside the session (seen on a USTEC hole
   // 2024.05.27 20:00-01:00, which entered checkpoint 7 at 18:00 New York).
   if(iTime(sym, TF, 0) - barOpen != PeriodSeconds(TF))
      return(0);
   datetime utc = ClkStampToUtc(barOpen);
   if(utc <= 0)
      return(0);
   int since = ClkNyMinute(utc) - InpOpenNYMinute;
   if(since < 0 || since % 30 != 0)
      return(0);
   int k = since / 30 + 1;
   return(k <= InpCheckpoints ? k : 0);
}

// Band width for checkpoint K, rounded to 0.05 ATR exactly as the original implementation.
double NBMThreshold(const int k)
{
   return(MathRound(InpBandK * MathSqrt(k) * 20.0) / 20.0);
}

//+------------------------------------------------------------------+
//| ATR access                                                       |
//+------------------------------------------------------------------+
double NBMAtr(const int i, const int shift)
{
   double buf[1];
   if(CopyBuffer(g_atr[i], 0, shift, 1, buf) != 1)
      return(0.0);
   return(buf[0]);
}

//+------------------------------------------------------------------+
//| Sizing: lot whose stop costs InpRiskPercent of the balance       |
//| Account-currency safe: the platform prices the loss, so no       |
//| denomination factor is applied here.                             |
//+------------------------------------------------------------------+
double NBMLotFor(const string sym, const double stopDist)
{
   double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
   double price     = SymbolInfoDouble(sym, SYMBOL_ASK);
   double loss      = 0.0;
   if(!OrderCalcProfit(ORDER_TYPE_BUY, sym, 1.0, price, price - stopDist, loss) || loss >= 0.0)
   {
      double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
      if(tickValue <= 0.0 || tickSize <= 0.0)
         return(0.0);
      loss = -stopDist / tickSize * tickValue;
   }
   double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   double minL = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double maxL = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   if(!MathIsValidNumber(riskMoney) || riskMoney <= 0.0 || !MathIsValidNumber(loss) || loss >= 0.0 ||
      !MathIsValidNumber(step) || step <= 0.0 || !MathIsValidNumber(minL) || minL <= 0.0 ||
      !MathIsValidNumber(maxL) || maxL < minL)
      return(0.0);
   double lot = MathFloor(MathMin(riskMoney / -loss, maxL) / step + 1e-9) * step;
   if(lot < minL)
   {
      // Standard volume rule: the operator decides once, the EA never rounds risk up silently.
      if(!InpAllowMinLotOverride)
      {
         PrintFormat("%s: RISK_BELOW_MIN_LOT budget=%.2f < broker minimum %.8f lots; entry skipped",
                     sym, riskMoney, minL);
         return(0.0);
      }
      lot = minL;
      PrintFormat("%s: MIN_LOT_OVERRIDE broker minimum exceeds intended risk; lots=%.8f estimatedRisk=%.2f intendedRisk=%.2f %s",
                  sym, lot, lot * -loss, riskMoney, AccountInfoString(ACCOUNT_CURRENCY));
   }
   return(NormalizeDouble(lot, 8));
}

//+------------------------------------------------------------------+
//| Entry evaluation: once per new candle, and only on a checkpoint  |
//+------------------------------------------------------------------+
void NBMTryEntry(const int i)
{
   string   sym = g_sym[i];
   datetime bar = iTime(sym, TF, 0);
   if(bar == 0 || bar == g_lastBar[i])
      return;
   g_lastBar[i] = bar;
   if(NBMHasPosition(sym))
      return;

   int k = NBMCheckpoint(sym);
   if(k == 0)
      return;

   double atr = NBMAtr(i, 1);
   if(atr <= 0.0)
      return;
   double close     = iClose(sym, TF, 1);
   double reference = iClose(sym, TF, 1 + k);   // close of the candle before the open
   if(close <= 0.0 || reference <= 0.0)
      return;
   double move      = (close - reference) / atr;
   double threshold = NBMThreshold(k);

   int dir = 0;
   if(move > threshold)
      dir = 1;
   else if(move < -threshold)
      dir = -1;
   if(dir == 0)
      return;

   double stopDist = InpStopAtr * atr;
   double lot      = NBMLotFor(sym, stopDist);
   if(lot <= 0.0)
   {
      PrintFormat("%s: signal, but sizing inputs or broker volume contract are invalid for %.2f %% risk - no trade.",
                  sym, InpRiskPercent);
      return;
   }

   double entry = (dir == 1) ? SymbolInfoDouble(sym, SYMBOL_ASK) : SymbolInfoDouble(sym, SYMBOL_BID);
   if(NBMSendEntry(i, dir, lot, stopDist, entry))
   {
      g_entryTime[i] = bar;
      g_stopDist[i]  = stopDist;
      g_best[i]      = entry;
      g_lastTrail[i] = 0;
      NBMStateSave(i);
      PrintFormat("%s %s at checkpoint %d: move %.2f ATR, threshold %.2f, lot %.2f",
                  sym, (dir == 1 ? "BUY" : "SELL"), k, move, threshold, lot);
   }
   else
      PrintFormat("%s: order failed, retcode %u", sym, NBMLastRetcode());
}

//+------------------------------------------------------------------+
//| Forward declarations: the runtime (ExecutionRuntime.mqh) is included after the input block,
//| because the clock inputs are enum-typed and the enums come from CLK-CORE above.
//+------------------------------------------------------------------+
bool   NBMHasPosition(const string sym);
void   NBMManage(const int i);
bool   NBMSendEntry(const int i, const int dir, const double lot, const double stopDist, const double entry);
uint   NBMLastRetcode();
void   NBMConfigureTrade(const long magic, const int slippage);

//+------------------------------------------------------------------+
//| Restart-idempotent per-symbol state                               |
//|                                                                   |
//|  A restart must not restart the trade. Entry time, initial risk,  |
//|  best price and the last trailing update are mirrored to terminal |
//|  GlobalVariables keyed by magic+symbol, so after a restart the    |
//|  trailing stop resumes from the true best price instead of        |
//|  re-arming at the entry. State is cleared when the position ends. |
//+------------------------------------------------------------------+
string NBMStateKey(const string sym, const string field)
{
   return("NBM_" + IntegerToString((int)InpMagic) + "_" + sym + "_" + field);
}

void NBMStateSave(const int i)
{
   string sym = g_sym[i];
   GlobalVariableSet(NBMStateKey(sym, "entry"), (double)g_entryTime[i]);
   GlobalVariableSet(NBMStateKey(sym, "risk"),  g_stopDist[i]);
   GlobalVariableSet(NBMStateKey(sym, "best"),  g_best[i]);
   GlobalVariableSet(NBMStateKey(sym, "trail"), (double)g_lastTrail[i]);
}

bool NBMStateRestore(const int i, const double open, const double sl)
{
   string sym = g_sym[i];
   string kEntry = NBMStateKey(sym, "entry");
   if(!GlobalVariableCheck(kEntry))
      return(false);
   datetime entry = (datetime)GlobalVariableGet(kEntry);
   double   risk  = GlobalVariableGet(NBMStateKey(sym, "risk"));
   double   best  = GlobalVariableGet(NBMStateKey(sym, "best"));
   double   trail = GlobalVariableGet(NBMStateKey(sym, "trail"));
   if(entry <= 0 || risk <= 0.0 || best <= 0.0)
      return(false);
   // Reject a stale key from an earlier trade on the same symbol.
   datetime posTime = (datetime)PositionGetInteger(POSITION_TIME);
   if(posTime > 0 && entry > posTime + 3600)
      return(false);
   g_entryTime[i] = entry;
   g_stopDist[i]  = risk;
   g_best[i]      = best;
   g_lastTrail[i] = (datetime)trail;
   return(true);
}

void NBMStateClear(const int i)
{
   string sym = g_sym[i];
   GlobalVariableDel(NBMStateKey(sym, "entry"));
   GlobalVariableDel(NBMStateKey(sym, "risk"));
   GlobalVariableDel(NBMStateKey(sym, "best"));
   GlobalVariableDel(NBMStateKey(sym, "trail"));
   g_entryTime[i] = 0;
   g_stopDist[i]  = 0.0;
   g_best[i]      = 0.0;
   g_lastTrail[i] = 0;
}

//+------------------------------------------------------------------+
//| Lifecycle                                                        |
//+------------------------------------------------------------------+
int NBMInit()
{
   int clockInit = ClkInit();
   if(clockInit != INIT_SUCCEEDED)
      return(clockInit);
   NBMConfigureTrade(InpMagic, InpSlippage);

   string parts[];
   int n = StringSplit(InpSymbols, ',', parts);
   int used = 0;
   for(int i = 0; i < n; i++)
   {
      string s = parts[i];
      StringTrimLeft(s);
      StringTrimRight(s);
      if(s == "")
         continue;
      if(!SymbolSelect(s, true))
      {
         PrintFormat("Symbol %s not found at this broker - skipped. Check the exact name in Market Watch.", s);
         continue;
      }
      int h = iATR(s, TF, InpAtrPeriod);
      if(h == INVALID_HANDLE)
      {
         PrintFormat("No ATR for %s - skipped.", s);
         continue;
      }
      used++;
      ArrayResize(g_sym, used);
      ArrayResize(g_atr, used);
      ArrayResize(g_lastBar, used);
      ArrayResize(g_entryTime, used);
      ArrayResize(g_stopDist, used);
      ArrayResize(g_best, used);
      ArrayResize(g_lastTrail, used);
      int k = used - 1;
      g_sym[k] = s;
      g_atr[k] = h;
      g_lastBar[k] = 0;
      g_entryTime[k] = 0;
      g_stopDist[k] = 0.0;
      g_best[k] = 0.0;
      g_lastTrail[k] = 0;
   }
   if(used == 0)
   {
      Print("No tradable symbol in InpSymbols. Example: NAS100,SP500 or US100.cash,US500.cash");
      return(INIT_PARAMETERS_INCORRECT);
   }
   PrintFormat("Noise Band Momentum: %d symbol(s), k = %.2f, session %02d:%02d-%02d:%02d New York.",
               used, InpBandK, InpOpenNYMinute / 60, InpOpenNYMinute % 60,
               InpCloseNYMinute / 60, InpCloseNYMinute % 60);
   return(INIT_SUCCEEDED);
}

void NBMDeinit()
{
   for(int i = 0; i < ArraySize(g_atr); i++)
      IndicatorRelease(g_atr[i]);
}

// Every tick: manage what is open, then look for an entry on a new candle.
void NBMTick()
{
   datetime nowServer = ClkNowServer();
   ClkRefresh(nowServer);
   for(int i = 0; i < ArraySize(g_sym); i++)
   {
      if(NBMHasPosition(g_sym[i]))
         NBMManage(i);
      else if(g_entryTime[i] != 0)
         NBMStateClear(i);          // the trade is closed: drop its state, never reuse it
      NBMTryEntry(i);
   }
   if(ClkGaveUp())                  // tester only: the broker clock cannot be proven
   {
      Print("NBM_STOPPED: broker clock unresolved: ", ClkNote());
      ExpertRemove();
   }
}

#endif // NBM_STRATEGY_ENGINE
