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
// Embedded installed platform trade implementation; no external include dependency.
// Native request boundary: account-scoped restriction and exact-position close intent.
// Kept inside each strategy module; no companion runtime dependency.
bool StrategyStorageFault=false;
int StrategyLease=INVALID_HANDLE;
uint StrategyScopeHash(string value)
{uint h=2166136261;for(int i=0;i<StringLen(value);i++)h=(h^(uint)StringGetCharacter(value,i))*16777619;return h;}
string StrategyScope(ulong magic)
{return "TT."+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+"."+IntegerToString(StrategyScopeHash(AccountInfoString(ACCOUNT_SERVER)+"|"+_Symbol))+"."+IntegerToString((long)magic);}
bool StrategyPersist(string key,double value)
{if(GlobalVariableSet(key,value)==0){StrategyStorageFault=true;Print("TT_STORAGE_FAILED; broker protection retained");return false;}return true;}
bool StrategyLeaseAcquire(ulong magic)
{
   if(MQLInfoInteger(MQL_TESTER))return true;
   StrategyLease=FileOpen(StrategyScope(magic)+".lock",FILE_COMMON|FILE_READ|FILE_WRITE|FILE_BIN);
   if(StrategyLease==INVALID_HANDLE){Print("TT executor already active or ownership lease unavailable");return false;}
   return true;
}
bool StrategyOwnedPosition(ulong ticket,ulong magic,ulong &id,double &volume)
{
   if(!PositionSelectByTicket(ticket) || PositionGetString(POSITION_SYMBOL)!=_Symbol || (ulong)PositionGetInteger(POSITION_MAGIC)!=magic)return false;
   id=(ulong)PositionGetInteger(POSITION_IDENTIFIER);volume=PositionGetDouble(POSITION_VOLUME);
   if(id==0 || !HistorySelectByPosition(id))return false;
   double entered=0,exited=0;
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong deal=HistoryDealGetTicket(i);long kind=HistoryDealGetInteger(deal,DEAL_ENTRY);
      if(deal==0 || (ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID)!=id || HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol || kind==DEAL_ENTRY_INOUT)return false;
      if(kind==DEAL_ENTRY_IN){if((ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=magic)return false;entered+=HistoryDealGetDouble(deal,DEAL_VOLUME);}
      else if(kind==DEAL_ENTRY_OUT || kind==DEAL_ENTRY_OUT_BY)exited+=HistoryDealGetDouble(deal,DEAL_VOLUME);
   }
   return entered>0 && MathAbs(entered-exited-volume)<=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP)*.5;
}
bool StrategyRestriction(uint code,string comment)
{
   StringToLower(comment);
   return code==TRADE_RETCODE_TRADE_DISABLED || code==TRADE_RETCODE_SERVER_DISABLES_AT || code==TRADE_RETCODE_CLOSE_ONLY ||
      StringFind(comment,"liquidation only")>=0 || StringFind(comment,"liquidation-only")>=0 ||
      StringFind(comment,"account restricted")>=0 || StringFind(comment,"no trading permissions")>=0;
}
bool StrategyCloseSettled(string key,double volume,ulong id,ulong magic)
{
   ulong order=((ulong)(uint)GlobalVariableGet(key+".hi")<<32)|(ulong)(uint)GlobalVariableGet(key+".lo");
   if(order==0 && HistorySelectByPosition(id))
   {
      for(int i=0;i<HistoryDealsTotal();i++)
      {
         ulong deal=HistoryDealGetTicket(i);long kind=HistoryDealGetInteger(deal,DEAL_ENTRY);
         if((kind!=DEAL_ENTRY_OUT && kind!=DEAL_ENTRY_OUT_BY) || (ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=magic ||
            HistoryDealGetInteger(deal,DEAL_TIME_MSC)<(long)GlobalVariableGet(key+".time"))continue;
         ulong found=(ulong)HistoryDealGetInteger(deal,DEAL_ORDER);
         if(order!=0 && order!=found)return false;
         order=found;
      }
      if(order>0){StrategyPersist(key+".hi",(double)(uint)(order>>32));StrategyPersist(key+".lo",(double)(uint)order);GlobalVariablesFlush();}
   }
   if(order==0 || OrderSelect(order) || !HistoryOrderSelect(order))return false;
   if(HistoryOrderGetString(order,ORDER_SYMBOL)!=_Symbol || (ulong)HistoryOrderGetInteger(order,ORDER_MAGIC)!=magic ||
      (ulong)HistoryOrderGetInteger(order,ORDER_POSITION_ID)!=id)return false;
   long state=HistoryOrderGetInteger(order,ORDER_STATE);
   if(state!=ORDER_STATE_FILLED && state!=ORDER_STATE_CANCELED && state!=ORDER_STATE_REJECTED && state!=ORDER_STATE_EXPIRED)return false;
   double filled=HistoryOrderGetDouble(order,ORDER_VOLUME_INITIAL)-HistoryOrderGetDouble(order,ORDER_VOLUME_CURRENT);
   return volume<=GlobalVariableGet(key+".volume")-filled+SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP)*.5;
}
bool StrategyOrderSend(const MqlTradeRequest &request,MqlTradeResult &result,bool async)
{
   if(MQLInfoInteger(MQL_TESTER))return async ? ::OrderSendAsync(request,result) : ::OrderSend(request,result);
   string scope=StrategyScope(request.magic),pending="";
   if(StrategyStorageFault || GlobalVariableCheck(scope+".restricted"))
   {ZeroMemory(result);result.retcode=TRADE_RETCODE_TRADE_DISABLED;result.comment="TT durable broker restriction; protection retained";return false;}
   if(request.position>0)
   {
      ulong id=0;double volume=0;
      if(!StrategyOwnedPosition(request.position,request.magic,id,volume))
      {ZeroMemory(result);result.retcode=TRADE_RETCODE_LOCKED;result.comment="Waiting for exact owned position/history";return false;}
      pending=scope+".C"+IntegerToString((long)id);
      if(GlobalVariableCheck(pending+".active"))
      {
         if(!StrategyCloseSettled(pending,volume,id,request.magic))
         {ZeroMemory(result);result.retcode=TRADE_RETCODE_LOCKED;result.comment="Waiting for prior owned close acknowledgement";return false;}
         GlobalVariableDel(pending+".active");GlobalVariablesFlush();
      }
      if(request.action==TRADE_ACTION_DEAL)
      {
         MqlTick quote;if(!SymbolInfoTick(_Symbol,quote))return false;
         if(!StrategyPersist(pending+".time",(double)quote.time_msc) || !StrategyPersist(pending+".volume",volume) || !StrategyPersist(pending+".hi",0) || !StrategyPersist(pending+".lo",0) || !StrategyPersist(pending+".active",1))return false;
         GlobalVariablesFlush(); // Intent precedes submission. Unknown acknowledgements never duplicate a close.
      }
      else pending="";
   }
   bool sent=async ? ::OrderSendAsync(request,result) : ::OrderSend(request,result);
   if(pending!="")
   {
      if(result.order>0){StrategyPersist(pending+".hi",(double)(uint)(result.order>>32));StrategyPersist(pending+".lo",(double)(uint)result.order);}
      bool ambiguous=result.retcode==0 || result.retcode==TRADE_RETCODE_TIMEOUT || result.retcode==TRADE_RETCODE_CONNECTION || result.retcode==TRADE_RETCODE_PLACED;
      if(!sent && !ambiguous)GlobalVariableDel(pending+".active");
      else if(result.retcode!=TRADE_RETCODE_DONE && result.retcode!=TRADE_RETCODE_DONE_PARTIAL && !ambiguous)GlobalVariableDel(pending+".active");
      GlobalVariablesFlush();
   }
   if(StrategyRestriction(result.retcode,result.comment))
   {StrategyPersist(scope+".restricted",(double)result.retcode);GlobalVariablesFlush();PrintFormat("TT_BROKER_RESTRICTED code=%u detail=%s; protection retained",result.retcode,result.comment);}
   return sent;
}
// BEGIN EMBEDDED SDK: Trade/Trade.mqh
//+------------------------------------------------------------------+
//|                                                        Trade.mqh |
//|                             Copyright 2000-2026, MetaQuotes Ltd. |
//|                                                     www.mql5.com |
//+------------------------------------------------------------------+
// BEGIN EMBEDDED SDK: Object.mqh
//+------------------------------------------------------------------+
//|                                                       Object.mqh |
//|                             Copyright 2000-2026, MetaQuotes Ltd. |
//|                                                     www.mql5.com |
//+------------------------------------------------------------------+
// BEGIN EMBEDDED SDK: StdLibErr.mqh
//+------------------------------------------------------------------+
//|                                                    StdLibErr.mqh |
//|                             Copyright 2000-2026, MetaQuotes Ltd. |
//|                                                     www.mql5.com |
//+------------------------------------------------------------------+
#define ERR_USER_INVALID_HANDLE                            1
#define ERR_USER_INVALID_BUFF_NUM                          2
#define ERR_USER_ITEM_NOT_FOUND                            3
#define ERR_USER_ARRAY_IS_EMPTY                            1000
//+------------------------------------------------------------------+

// END EMBEDDED SDK: StdLibErr.mqh

//+------------------------------------------------------------------+
//| Class CObject.                                                   |
//| Purpose: Base class for storing elements.                        |
//+------------------------------------------------------------------+
class CObject
  {
private:
   CObject          *m_prev;               // previous item of list
   CObject          *m_next;               // next item of list

public:
                     CObject(void): m_prev(NULL),m_next(NULL)            {                 }
                    ~CObject(void)                                       {                 }
   //--- methods to access protected data
   CObject          *Prev(void)                                    const { return(m_prev); }
   void              Prev(CObject *node)                                 { m_prev=node;    }
   CObject          *Next(void)                                    const { return(m_next); }
   void              Next(CObject *node)                                 { m_next=node;    }
   //--- methods for working with files
   virtual bool      Save(const int file_handle)                         { return(true);   }
   virtual bool      Load(const int file_handle)                         { return(true);   }
   //--- method of identifying the object
   virtual int       Type(void)                                    const { return(0);      }
   //--- method of comparing the objects
   virtual int       Compare(const CObject *node,const int mode=0) const { return(0);      }
  };
//+------------------------------------------------------------------+

// END EMBEDDED SDK: Object.mqh

// BEGIN EMBEDDED SDK: Trade/OrderInfo.mqh
//+------------------------------------------------------------------+
//|                                                    OrderInfo.mqh |
//|                             Copyright 2000-2026, MetaQuotes Ltd. |
//|                                                     www.mql5.com |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Class COrderInfo.                                                |
//| Appointment: Class for access to order info.                     |
//|              Derives from class CObject.                         |
//+------------------------------------------------------------------+
class COrderInfo : public CObject
  {
protected:
   ulong             m_ticket;
   ENUM_ORDER_TYPE   m_type;
   ENUM_ORDER_STATE  m_state;
   datetime          m_expiration;
   double            m_volume_curr;
   double            m_price_open;
   double            m_stop_loss;
   double            m_take_profit;

public:
                     COrderInfo(void);
                    ~COrderInfo(void);
   //--- methods of access to protected data
   ulong             Ticket(void) const { return(m_ticket); }
   //--- fast access methods to the integer order propertyes
   datetime          TimeSetup(void) const;
   ulong             TimeSetupMsc(void) const;
   datetime          TimeDone(void) const;
   ulong             TimeDoneMsc(void) const;
   ENUM_ORDER_TYPE   OrderType(void) const;
   string            TypeDescription(void) const;
   ENUM_ORDER_STATE  State(void) const;
   string            StateDescription(void) const;
   datetime          TimeExpiration(void) const;
   ENUM_ORDER_TYPE_FILLING TypeFilling(void) const;
   string            TypeFillingDescription(void) const;
   ENUM_ORDER_TYPE_TIME TypeTime(void) const;
   string            TypeTimeDescription(void) const;
   long              Magic(void) const;
   long              PositionId(void) const;
   long              PositionById(void) const;
   //--- fast access methods to the double order propertyes
   double            VolumeInitial(void) const;
   double            VolumeCurrent(void) const;
   double            PriceOpen(void) const;
   double            StopLoss(void) const;
   double            TakeProfit(void) const;
   double            PriceCurrent(void) const;
   double            PriceStopLimit(void) const;
   //--- fast access methods to the string order propertyes
   string            Symbol(void) const;
   string            Comment(void) const;
   string            ExternalId(void) const;
   //--- access methods to the API MQL5 functions
   bool              InfoInteger(const ENUM_ORDER_PROPERTY_INTEGER prop_id,long &var) const;
   bool              InfoDouble(const ENUM_ORDER_PROPERTY_DOUBLE prop_id,double &var) const;
   bool              InfoString(const ENUM_ORDER_PROPERTY_STRING prop_id,string &var) const;
   //--- info methods
   string            FormatType(string &str,const uint type) const;
   string            FormatStatus(string &str,const uint status) const;
   string            FormatTypeFilling(string &str,const uint type) const;
   string            FormatTypeTime(string &str,const uint type) const;
   string            FormatOrder(string &str) const;
   string            FormatPrice(string &str,const double price_order,const double price_trigger,const uint digits) const;
   //--- method for select order
   bool              Select(void);
   bool              Select(const ulong ticket);
   bool              SelectByIndex(const int index);
   //--- additional methods
   void              StoreState(void);
   bool              CheckState(void);
  };
//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
COrderInfo::COrderInfo(void) : m_ticket(ULONG_MAX),
                               m_type(WRONG_VALUE),
                               m_state(WRONG_VALUE),
                               m_expiration(0),
                               m_volume_curr(0.0),
                               m_price_open(0.0),
                               m_stop_loss(0.0),
                               m_take_profit(0.0)
  {
  }
//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
COrderInfo::~COrderInfo(void)
  {
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TIME_SETUP"                        |
//+------------------------------------------------------------------+
datetime COrderInfo::TimeSetup(void) const
  {
   return((datetime)OrderGetInteger(ORDER_TIME_SETUP));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TIME_SETUP_MSC"                    |
//+------------------------------------------------------------------+
ulong COrderInfo::TimeSetupMsc(void) const
  {
   return(OrderGetInteger(ORDER_TIME_SETUP_MSC));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TIME_DONE"                         |
//+------------------------------------------------------------------+
datetime COrderInfo::TimeDone(void) const
  {
   return((datetime)OrderGetInteger(ORDER_TIME_DONE));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TIME_DONE_MSC"                     |
//+------------------------------------------------------------------+
ulong COrderInfo::TimeDoneMsc(void) const
  {
   return(OrderGetInteger(ORDER_TIME_DONE_MSC));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TYPE"                              |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE COrderInfo::OrderType(void) const
  {
   return((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TYPE" as string                    |
//+------------------------------------------------------------------+
string COrderInfo::TypeDescription(void) const
  {
   string str;
//---
   return(FormatType(str,OrderType()));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_STATE"                             |
//+------------------------------------------------------------------+
ENUM_ORDER_STATE COrderInfo::State(void) const
  {
   return((ENUM_ORDER_STATE)OrderGetInteger(ORDER_STATE));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_STATE" as string                   |
//+------------------------------------------------------------------+
string COrderInfo::StateDescription(void) const
  {
   string str;
//---
   return(FormatStatus(str,State()));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TIME_EXPIRATION"                   |
//+------------------------------------------------------------------+
datetime COrderInfo::TimeExpiration(void) const
  {
   return((datetime)OrderGetInteger(ORDER_TIME_EXPIRATION));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TYPE_FILLING"                      |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING COrderInfo::TypeFilling(void) const
  {
   return((ENUM_ORDER_TYPE_FILLING)OrderGetInteger(ORDER_TYPE_FILLING));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TYPE_FILLING" as string            |
//+------------------------------------------------------------------+
string COrderInfo::TypeFillingDescription(void) const
  {
   string str;
//---
   return(FormatTypeFilling(str,TypeFilling()));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TYPE_TIME"                         |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_TIME COrderInfo::TypeTime(void) const
  {
   return((ENUM_ORDER_TYPE_TIME)OrderGetInteger(ORDER_TYPE_TIME));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TYPE_TIME" as string               |
//+------------------------------------------------------------------+
string COrderInfo::TypeTimeDescription(void) const
  {
   string str;
//---
   return(FormatTypeTime(str,TypeFilling()));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_MAGIC"                             |
//+------------------------------------------------------------------+
long COrderInfo::Magic(void) const
  {
   return(OrderGetInteger(ORDER_MAGIC));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_POSITION_ID"                       |
//+------------------------------------------------------------------+
long COrderInfo::PositionId(void) const
  {
   return(OrderGetInteger(ORDER_POSITION_ID));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_POSITION_BY_ID"                    |
//+------------------------------------------------------------------+
long COrderInfo::PositionById(void) const
  {
   return(OrderGetInteger(ORDER_POSITION_BY_ID));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_VOLUME_INITIAL"                    |
//+------------------------------------------------------------------+
double COrderInfo::VolumeInitial(void) const
  {
   return(OrderGetDouble(ORDER_VOLUME_INITIAL));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_VOLUME_CURRENT"                    |
//+------------------------------------------------------------------+
double COrderInfo::VolumeCurrent(void) const
  {
   return(OrderGetDouble(ORDER_VOLUME_CURRENT));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_PRICE_OPEN"                        |
//+------------------------------------------------------------------+
double COrderInfo::PriceOpen(void) const
  {
   return(OrderGetDouble(ORDER_PRICE_OPEN));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_SL"                                |
//+------------------------------------------------------------------+
double COrderInfo::StopLoss(void) const
  {
   return(OrderGetDouble(ORDER_SL));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TP"                                |
//+------------------------------------------------------------------+
double COrderInfo::TakeProfit(void) const
  {
   return(OrderGetDouble(ORDER_TP));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_PRICE_CURRENT"                     |
//+------------------------------------------------------------------+
double COrderInfo::PriceCurrent(void) const
  {
   return(OrderGetDouble(ORDER_PRICE_CURRENT));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_PRICE_STOPLIMIT"                   |
//+------------------------------------------------------------------+
double COrderInfo::PriceStopLimit(void) const
  {
   return(OrderGetDouble(ORDER_PRICE_STOPLIMIT));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_SYMBOL"                            |
//+------------------------------------------------------------------+
string COrderInfo::Symbol(void) const
  {
   return(OrderGetString(ORDER_SYMBOL));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_COMMENT"                           |
//+------------------------------------------------------------------+
string COrderInfo::Comment(void) const
  {
   return(OrderGetString(ORDER_COMMENT));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_EXTERNAL_ID"                       |
//+------------------------------------------------------------------+
string COrderInfo::ExternalId(void) const
  {
   return(OrderGetString(ORDER_EXTERNAL_ID));
  }
//+------------------------------------------------------------------+
//| Access functions OrderGetInteger(...)                            |
//+------------------------------------------------------------------+
bool COrderInfo::InfoInteger(const ENUM_ORDER_PROPERTY_INTEGER prop_id,long &var) const
  {
   return(OrderGetInteger(prop_id,var));
  }
//+------------------------------------------------------------------+
//| Access functions OrderGetDouble(...)                             |
//+------------------------------------------------------------------+
bool COrderInfo::InfoDouble(const ENUM_ORDER_PROPERTY_DOUBLE prop_id,double &var) const
  {
   return(OrderGetDouble(prop_id,var));
  }
//+------------------------------------------------------------------+
//| Access functions OrderGetString(...)                             |
//+------------------------------------------------------------------+
bool COrderInfo::InfoString(const ENUM_ORDER_PROPERTY_STRING prop_id,string &var) const
  {
   return(OrderGetString(prop_id,var));
  }
//+------------------------------------------------------------------+
//| Converts the order type to text                                  |
//+------------------------------------------------------------------+
string COrderInfo::FormatType(string &str,const uint type) const
  {
//--- see the type
   switch(type)
     {
      case ORDER_TYPE_BUY:
         str="buy";
         break;
      case ORDER_TYPE_SELL:
         str="sell";
         break;
      case ORDER_TYPE_BUY_LIMIT:
         str="buy limit";
         break;
      case ORDER_TYPE_SELL_LIMIT:
         str="sell limit";
         break;
      case ORDER_TYPE_BUY_STOP:
         str="buy stop";
         break;
      case ORDER_TYPE_SELL_STOP:
         str="sell stop";
         break;
      case ORDER_TYPE_BUY_STOP_LIMIT:
         str="buy stop limit";
         break;
      case ORDER_TYPE_SELL_STOP_LIMIT:
         str="sell stop limit";
         break;
      case ORDER_TYPE_CLOSE_BY:
         str="close by";
         break;
      default :
         str="unknown order type "+(string)type;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the order status to text                                |
//+------------------------------------------------------------------+
string COrderInfo::FormatStatus(string &str,const uint status) const
  {
//--- see the type
   switch(status)
     {
      case ORDER_STATE_STARTED:
         str="started";
         break;
      case ORDER_STATE_PLACED:
         str="placed";
         break;
      case ORDER_STATE_CANCELED:
         str="canceled";
         break;
      case ORDER_STATE_PARTIAL:
         str="partial";
         break;
      case ORDER_STATE_FILLED:
         str="filled";
         break;
      case ORDER_STATE_REJECTED:
         str="rejected";
         break;
      case ORDER_STATE_EXPIRED:
         str="expired";
         break;
      case ORDER_STATE_REQUEST_ADD:
         str="request adding";
         break;
      case ORDER_STATE_REQUEST_MODIFY:
         str="request modifying";
         break;
      case ORDER_STATE_REQUEST_CANCEL:
         str="request cancelling";
         break;
      default :
         str="unknown order status "+(string)status;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the order filling type to text                          |
//+------------------------------------------------------------------+
string COrderInfo::FormatTypeFilling(string &str,const uint type) const
  {
//--- see the type
   switch(type)
     {
      case ORDER_FILLING_RETURN:
         str="return remainder";
         break;
      case ORDER_FILLING_IOC:
         str="cancel remainder";
         break;
      case ORDER_FILLING_FOK:
         str="fill or kill";
         break;
      default:
         str="unknown type filling "+(string)type;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the type of order by expiration to text                 |
//+------------------------------------------------------------------+
string COrderInfo::FormatTypeTime(string &str,const uint type) const
  {
//--- see the type
   switch(type)
     {
      case ORDER_TIME_GTC:
         str="gtc";
         break;
      case ORDER_TIME_DAY:
         str="day";
         break;
      case ORDER_TIME_SPECIFIED:
         str="specified";
         break;
      case ORDER_TIME_SPECIFIED_DAY:
         str="specified day";
         break;
      default:
         str="unknown type time "+(string)type;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the order parameters to text                            |
//+------------------------------------------------------------------+
string COrderInfo::FormatOrder(string &str) const
  {
   string type,price;
   long   tmp_long;
//--- set up
   string symbol_name=this.Symbol();
   int    digits=_Digits;
   if(SymbolInfoInteger(symbol_name,SYMBOL_DIGITS,tmp_long))
      digits=(int)tmp_long;
//--- form the order description
   str=StringFormat("#%I64u %s %s %s",
                    Ticket(),
                    FormatType(type,OrderType()),
                    DoubleToString(VolumeInitial(),2),
                    symbol_name);
//--- receive the price of the order
   FormatPrice(price,PriceOpen(),PriceStopLimit(),digits);
//--- if there is price, write it
   if(price!="")
     {
      str+=" at ";
      str+=price;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the order prices to text                                |
//+------------------------------------------------------------------+
string COrderInfo::FormatPrice(string &str,const double price_order,const double price_trigger,const uint digits) const
  {
   string price,trigger;
//--- Is there its trigger price?
   if(price_trigger)
     {
      price  =DoubleToString(price_order,digits);
      trigger=DoubleToString(price_trigger,digits);
      str    =StringFormat("%s (%s)",price,trigger);
     }
   else
      str=DoubleToString(price_order,digits);
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Selecting an order to access                                     |
//+------------------------------------------------------------------+
bool COrderInfo::Select(void)
  {
   return(OrderSelect(m_ticket));
  }
//+------------------------------------------------------------------+
//| Selecting an order to access                                     |
//+------------------------------------------------------------------+
bool COrderInfo::Select(const ulong ticket)
  {
   if(OrderSelect(ticket))
     {
      m_ticket=ticket;
      return(true);
     }
   m_ticket=ULONG_MAX;
//---
   return(false);
  }
//+------------------------------------------------------------------+
//| Select an order by the index                                     |
//+------------------------------------------------------------------+
bool COrderInfo::SelectByIndex(const int index)
  {
   ulong ticket=OrderGetTicket(index);
   if(ticket==0)
     {
      m_ticket=ULONG_MAX;
      return(false);
     }
   m_ticket=ticket;
//---
   return(true);
  }
//+------------------------------------------------------------------+
//| Stored order's current state                                     |
//+------------------------------------------------------------------+
void COrderInfo::StoreState(void)
  {
   m_type       =OrderType();
   m_state      =State();
   m_expiration =TimeExpiration();
   m_volume_curr=VolumeCurrent();
   m_price_open =PriceOpen();
   m_stop_loss  =StopLoss();
   m_take_profit=TakeProfit();
  }
//+------------------------------------------------------------------+
//| Check order change                                               |
//+------------------------------------------------------------------+
bool COrderInfo::CheckState(void)
  {
   if(m_type==OrderType()            &&
      m_state==State()               &&
      m_expiration==TimeExpiration() &&
      m_volume_curr==VolumeCurrent() &&
      m_price_open==PriceOpen()      &&
      m_stop_loss==StopLoss()        &&
      m_take_profit==TakeProfit())
      return(false);
//---
   return(true);
  }
//+------------------------------------------------------------------+

// END EMBEDDED SDK: Trade/OrderInfo.mqh

// BEGIN EMBEDDED SDK: Trade/HistoryOrderInfo.mqh
//+------------------------------------------------------------------+
//|                                             HistoryOrderInfo.mqh |
//|                             Copyright 2000-2026, MetaQuotes Ltd. |
//|                                                     www.mql5.com |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Class CHistoryOrderInfo.                                         |
//| Appointment: Class for access to history order info.             |
//|              Derives from class CObject.                         |
//+------------------------------------------------------------------+
class CHistoryOrderInfo : public CObject
  {
protected:
   ulong             m_ticket;             // ticket of history order
public:
                     CHistoryOrderInfo(void);
                    ~CHistoryOrderInfo(void);
   //--- methods of access to protected data
   void              Ticket(const ulong ticket) { m_ticket=ticket;  }
   ulong             Ticket(void)         const { return(m_ticket); }
   //--- fast access methods to the integer order propertyes
   datetime          TimeSetup(void) const;
   ulong             TimeSetupMsc(void) const;
   datetime          TimeDone(void) const;
   ulong             TimeDoneMsc(void) const;
   ENUM_ORDER_TYPE   OrderType(void) const;
   string            TypeDescription(void) const;
   ENUM_ORDER_STATE  State(void) const;
   string            StateDescription(void) const;
   datetime          TimeExpiration(void) const;
   ENUM_ORDER_TYPE_FILLING TypeFilling(void) const;
   string            TypeFillingDescription(void) const;
   ENUM_ORDER_TYPE_TIME TypeTime(void) const;
   string            TypeTimeDescription(void) const;
   long              Magic(void) const;
   long              PositionId(void) const;
   long              PositionById(void) const;
   //--- fast access methods to the double order propertyes
   double            VolumeInitial(void) const;
   double            VolumeCurrent(void) const;
   double            PriceOpen(void) const;
   double            StopLoss(void) const;
   double            TakeProfit(void) const;
   double            PriceCurrent(void) const;
   double            PriceStopLimit(void) const;
   //--- fast access methods to the string order propertyes
   string            Symbol(void) const;
   string            Comment(void) const;
   string            ExternalId(void) const;
   //--- access methods to the API MQL5 functions
   bool              InfoInteger(const ENUM_ORDER_PROPERTY_INTEGER prop_id,long &var) const;
   bool              InfoDouble(const ENUM_ORDER_PROPERTY_DOUBLE prop_id,double &var) const;
   bool              InfoString(const ENUM_ORDER_PROPERTY_STRING prop_id,string &var) const;
   //--- info methods
   string            FormatType(string &str,const uint type) const;
   string            FormatStatus(string &str,const uint status) const;
   string            FormatTypeFilling(string &str,const uint type) const;
   string            FormatTypeTime(string &str,const uint type) const;
   string            FormatOrder(string &str) const;
   string            FormatPrice(string &str,const double price_order,const double price_trigger,const uint digits) const;
   //--- method for select history order
   bool              SelectByIndex(const int index);
  };
//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CHistoryOrderInfo::CHistoryOrderInfo(void) : m_ticket(0)
  {
  }
//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CHistoryOrderInfo::~CHistoryOrderInfo(void)
  {
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TIME_SETUP"                        |
//+------------------------------------------------------------------+
datetime CHistoryOrderInfo::TimeSetup(void) const
  {
   return((datetime)HistoryOrderGetInteger(m_ticket,ORDER_TIME_SETUP));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TIME_SETUP_MSC"                    |
//+------------------------------------------------------------------+
ulong CHistoryOrderInfo::TimeSetupMsc(void) const
  {
   return(HistoryOrderGetInteger(m_ticket,ORDER_TIME_SETUP_MSC));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TIME_DONE"                         |
//+------------------------------------------------------------------+
datetime CHistoryOrderInfo::TimeDone(void) const
  {
   return((datetime)HistoryOrderGetInteger(m_ticket,ORDER_TIME_DONE));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TIME_DONE_MSC"                     |
//+------------------------------------------------------------------+
ulong CHistoryOrderInfo::TimeDoneMsc(void) const
  {
   return(HistoryOrderGetInteger(m_ticket,ORDER_TIME_DONE_MSC));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TYPE"                              |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE CHistoryOrderInfo::OrderType(void) const
  {
   return((ENUM_ORDER_TYPE)HistoryOrderGetInteger(m_ticket,ORDER_TYPE));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TYPE" as string                    |
//+------------------------------------------------------------------+
string CHistoryOrderInfo::TypeDescription(void) const
  {
   string str;
//---
   return(FormatType(str,OrderType()));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_STATE"                             |
//+------------------------------------------------------------------+
ENUM_ORDER_STATE CHistoryOrderInfo::State(void) const
  {
   return((ENUM_ORDER_STATE)HistoryOrderGetInteger(m_ticket,ORDER_STATE));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_STATE" as string                   |
//+------------------------------------------------------------------+
string CHistoryOrderInfo::StateDescription(void) const
  {
   string str;
//---
   return(FormatStatus(str,State()));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TIME_EXPIRATION"                   |
//+------------------------------------------------------------------+
datetime CHistoryOrderInfo::TimeExpiration(void) const
  {
   return((datetime)HistoryOrderGetInteger(m_ticket,ORDER_TIME_EXPIRATION));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TYPE_FILLING"                      |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING CHistoryOrderInfo::TypeFilling(void) const
  {
   return((ENUM_ORDER_TYPE_FILLING)HistoryOrderGetInteger(m_ticket,ORDER_TYPE_FILLING));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TYPE_FILLING" as string            |
//+------------------------------------------------------------------+
string CHistoryOrderInfo::TypeFillingDescription(void) const
  {
   string str;
//---
   return(FormatTypeFilling(str,TypeFilling()));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TYPE_TIME"                         |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_TIME CHistoryOrderInfo::TypeTime(void) const
  {
   return((ENUM_ORDER_TYPE_TIME)HistoryOrderGetInteger(m_ticket,ORDER_TYPE_TIME));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TYPE_TIME" as string               |
//+------------------------------------------------------------------+
string CHistoryOrderInfo::TypeTimeDescription(void) const
  {
   string str;
//---
   return(FormatTypeTime(str,TypeTime()));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_EXPERT"                            |
//+------------------------------------------------------------------+
long CHistoryOrderInfo::Magic(void) const
  {
   return(HistoryOrderGetInteger(m_ticket,ORDER_MAGIC));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_POSITION_ID"                       |
//+------------------------------------------------------------------+
long CHistoryOrderInfo::PositionId(void) const
  {
   return(HistoryOrderGetInteger(m_ticket,ORDER_POSITION_ID));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_POSITION_BY_ID"                    |
//+------------------------------------------------------------------+
long CHistoryOrderInfo::PositionById(void) const
  {
   return(HistoryOrderGetInteger(m_ticket,ORDER_POSITION_BY_ID));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_VOLUME_INITIAL"                    |
//+------------------------------------------------------------------+
double CHistoryOrderInfo::VolumeInitial(void) const
  {
   return(HistoryOrderGetDouble(m_ticket,ORDER_VOLUME_INITIAL));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_VOLUME_CURRENT"                    |
//+------------------------------------------------------------------+
double CHistoryOrderInfo::VolumeCurrent(void) const
  {
   return(HistoryOrderGetDouble(m_ticket,ORDER_VOLUME_CURRENT));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_PRICE_OPEN"                        |
//+------------------------------------------------------------------+
double CHistoryOrderInfo::PriceOpen(void) const
  {
   return(HistoryOrderGetDouble(m_ticket,ORDER_PRICE_OPEN));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_SL"                                |
//+------------------------------------------------------------------+
double CHistoryOrderInfo::StopLoss(void) const
  {
   return(HistoryOrderGetDouble(m_ticket,ORDER_SL));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TP"                                |
//+------------------------------------------------------------------+
double CHistoryOrderInfo::TakeProfit(void) const
  {
   return(HistoryOrderGetDouble(m_ticket,ORDER_TP));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_PRICE_CURRENT"                     |
//+------------------------------------------------------------------+
double CHistoryOrderInfo::PriceCurrent(void) const
  {
   return(HistoryOrderGetDouble(m_ticket,ORDER_PRICE_CURRENT));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_PRICE_STOPLIMIT"                   |
//+------------------------------------------------------------------+
double CHistoryOrderInfo::PriceStopLimit(void) const
  {
   return(HistoryOrderGetDouble(m_ticket,ORDER_PRICE_STOPLIMIT));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_SYMBOL"                            |
//+------------------------------------------------------------------+
string CHistoryOrderInfo::Symbol(void) const
  {
   return(HistoryOrderGetString(m_ticket,ORDER_SYMBOL));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_COMMENT"                           |
//+------------------------------------------------------------------+
string CHistoryOrderInfo::Comment(void) const
  {
   return(HistoryOrderGetString(m_ticket,ORDER_COMMENT));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_EXTERNAL_ID"                       |
//+------------------------------------------------------------------+
string CHistoryOrderInfo::ExternalId(void) const
  {
   return(HistoryOrderGetString(m_ticket,ORDER_EXTERNAL_ID));
  }
//+------------------------------------------------------------------+
//| Access functions OrderGetInteger(...)                            |
//+------------------------------------------------------------------+
bool CHistoryOrderInfo::InfoInteger(const ENUM_ORDER_PROPERTY_INTEGER prop_id,long &var) const
  {
   return(HistoryOrderGetInteger(m_ticket,prop_id,var));
  }
//+------------------------------------------------------------------+
//| Access functions OrderGetDouble(...)                             |
//+------------------------------------------------------------------+
bool CHistoryOrderInfo::InfoDouble(const ENUM_ORDER_PROPERTY_DOUBLE prop_id,double &var) const
  {
   return(HistoryOrderGetDouble(m_ticket,prop_id,var));
  }
//+------------------------------------------------------------------+
//| Access functions OrderGetString(...)                             |
//+------------------------------------------------------------------+
bool CHistoryOrderInfo::InfoString(const ENUM_ORDER_PROPERTY_STRING prop_id,string &var) const
  {
   return(HistoryOrderGetString(m_ticket,prop_id,var));
  }
//+------------------------------------------------------------------+
//| Converts the order type to text                                  |
//+------------------------------------------------------------------+
string CHistoryOrderInfo::FormatType(string &str,const uint type) const
  {
//--- see the type
   switch(type)
     {
      case ORDER_TYPE_BUY:
         str="buy";
         break;
      case ORDER_TYPE_SELL:
         str="sell";
         break;
      case ORDER_TYPE_BUY_LIMIT:
         str="buy limit";
         break;
      case ORDER_TYPE_SELL_LIMIT:
         str="sell limit";
         break;
      case ORDER_TYPE_BUY_STOP:
         str="buy stop";
         break;
      case ORDER_TYPE_SELL_STOP:
         str="sell stop";
         break;
      case ORDER_TYPE_BUY_STOP_LIMIT:
         str="buy stop limit";
         break;
      case ORDER_TYPE_SELL_STOP_LIMIT:
         str="sell stop limit";
         break;
      case ORDER_TYPE_CLOSE_BY:
         str="close by";
         break;
      default:
         str="unknown order type "+(string)type;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the order status to text                                |
//+------------------------------------------------------------------+
string CHistoryOrderInfo::FormatStatus(string &str,const uint status) const
  {
//--- see the type
   switch(status)
     {
      case ORDER_STATE_STARTED:
         str="started";
         break;
      case ORDER_STATE_PLACED:
         str="placed";
         break;
      case ORDER_STATE_CANCELED:
         str="canceled";
         break;
      case ORDER_STATE_PARTIAL:
         str="partial";
         break;
      case ORDER_STATE_FILLED:
         str="filled";
         break;
      case ORDER_STATE_REJECTED:
         str="rejected";
         break;
      case ORDER_STATE_EXPIRED:
         str="expired";
         break;
      default:
         str="unknown order status "+(string)status;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the order filling type to text                          |
//+------------------------------------------------------------------+
string CHistoryOrderInfo::FormatTypeFilling(string &str,const uint type) const
  {
//--- see the type
   switch(type)
     {
      case ORDER_FILLING_RETURN:
         str="return remainder";
         break;
      case ORDER_FILLING_IOC:
         str="cancel remainder";
         break;
      case ORDER_FILLING_FOK:
         str="fill or kill";
         break;
      default:
         str="unknown type filling "+(string)type;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the type of order by expiration to text                 |
//+------------------------------------------------------------------+
string CHistoryOrderInfo::FormatTypeTime(string &str,const uint type) const
  {
//--- see the type
   switch(type)
     {
      case ORDER_TIME_GTC:
         str="gtc";
         break;
      case ORDER_TIME_DAY:
         str="day";
         break;
      case ORDER_TIME_SPECIFIED:
         str="specified";
         break;
      case ORDER_TIME_SPECIFIED_DAY:
         str="specified day";
         break;
      default:
         str="unknown type time "+(string)type;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the order parameters to text                            |
//+------------------------------------------------------------------+
string CHistoryOrderInfo::FormatOrder(string &str) const
  {
   string type,price;
   long   tmp_long;
//--- set up
   string symbol_name=this.Symbol();
   int    digits=_Digits;
   if(SymbolInfoInteger(symbol_name,SYMBOL_DIGITS,tmp_long))
      digits=(int)tmp_long;
//--- form the order description
   str=StringFormat("#%I64u %s %s %s",
                    Ticket(),
                    FormatType(type,OrderType()),
                    DoubleToString(VolumeInitial(),2),
                    symbol_name);
//--- receive the price of the order
   FormatPrice(price,PriceOpen(),PriceStopLimit(),digits);
//--- if there is price, write it
   if(price!="")
     {
      str+=" at ";
      str+=price;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the order prices to text                                |
//+------------------------------------------------------------------+
string CHistoryOrderInfo::FormatPrice(string &str,const double price_order,const double price_trigger,const uint digits) const
  {
   string price,trigger;
//--- Is there its trigger price?
   if(price_trigger)
     {
      price  =DoubleToString(price_order,digits);
      trigger=DoubleToString(price_trigger,digits);
      str    =StringFormat("%s (%s)",price,trigger);
     }
   else
      str=DoubleToString(price_order,digits);
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Select a history order on the index                              |
//+------------------------------------------------------------------+
bool CHistoryOrderInfo::SelectByIndex(const int index)
  {
   ulong ticket=HistoryOrderGetTicket(index);
   if(ticket==0)
      return(false);
   Ticket(ticket);
//---
   return(true);
  }
//+------------------------------------------------------------------+

// END EMBEDDED SDK: Trade/HistoryOrderInfo.mqh

// BEGIN EMBEDDED SDK: Trade/PositionInfo.mqh
//+------------------------------------------------------------------+
//|                                                 PositionInfo.mqh |
//|                             Copyright 2000-2026, MetaQuotes Ltd. |
//|                                                     www.mql5.com |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Class CPositionInfo.                                             |
//| Appointment: Class for access to position info.                  |
//|              Derives from class CObject.                         |
//+------------------------------------------------------------------+
class CPositionInfo : public CObject
  {
protected:
   ENUM_POSITION_TYPE m_type;
   double            m_volume;
   double            m_price;
   double            m_stop_loss;
   double            m_take_profit;

public:
                     CPositionInfo(void);
                    ~CPositionInfo(void);
   //--- fast access methods to the integer position propertyes
   ulong             Ticket(void) const;
   datetime          Time(void) const;
   ulong             TimeMsc(void) const;
   datetime          TimeUpdate(void) const;
   ulong             TimeUpdateMsc(void) const;
   ENUM_POSITION_TYPE PositionType(void) const;
   string            TypeDescription(void) const;
   long              Magic(void) const;
   long              Identifier(void) const;
   //--- fast access methods to the double position propertyes
   double            Volume(void) const;
   double            PriceOpen(void) const;
   double            StopLoss(void) const;
   double            TakeProfit(void) const;
   double            PriceCurrent(void) const;
   double            Commission(void) const;
   double            Swap(void) const;
   double            Profit(void) const;
   //--- fast access methods to the string position propertyes
   string            Symbol(void) const;
   string            Comment(void) const;
   //--- access methods to the API MQL5 functions
   bool              InfoInteger(const ENUM_POSITION_PROPERTY_INTEGER prop_id,long &var) const;
   bool              InfoDouble(const ENUM_POSITION_PROPERTY_DOUBLE prop_id,double &var) const;
   bool              InfoString(const ENUM_POSITION_PROPERTY_STRING prop_id,string &var) const;
   //--- info methods
   string            FormatType(string &str,const uint type) const;
   string            FormatPosition(string &str) const;
   //--- methods for select position
   bool              Select(const string symbol);
   bool              SelectByMagic(const string symbol,const ulong magic);
   bool              SelectByTicket(const ulong ticket);
   bool              SelectByIndex(const int index);
   //---
   void              StoreState(void);
   bool              CheckState(void);
  };
//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CPositionInfo::CPositionInfo(void) : m_type(WRONG_VALUE),
                                     m_volume(0.0),
                                     m_price(0.0),
                                     m_stop_loss(0.0),
                                     m_take_profit(0.0)
  {
  }
//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CPositionInfo::~CPositionInfo(void)
  {
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_TICKET"                         |
//+------------------------------------------------------------------+
ulong CPositionInfo::Ticket(void) const
  {
   return((ulong)PositionGetInteger(POSITION_TICKET));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_TIME"                           |
//+------------------------------------------------------------------+
datetime CPositionInfo::Time(void) const
  {
   return((datetime)PositionGetInteger(POSITION_TIME));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_TIME_MSC"                       |
//+------------------------------------------------------------------+
ulong CPositionInfo::TimeMsc(void) const
  {
   return((ulong)PositionGetInteger(POSITION_TIME_MSC));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_TIME_UPDATE"                    |
//+------------------------------------------------------------------+
datetime CPositionInfo::TimeUpdate(void) const
  {
   return((datetime)PositionGetInteger(POSITION_TIME_UPDATE));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_TIME_UPDATE_MSC"                |
//+------------------------------------------------------------------+
ulong CPositionInfo::TimeUpdateMsc(void) const
  {
   return((ulong)PositionGetInteger(POSITION_TIME_UPDATE_MSC));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_TYPE"                           |
//+------------------------------------------------------------------+
ENUM_POSITION_TYPE CPositionInfo::PositionType(void) const
  {
   return((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_TYPE" as string                 |
//+------------------------------------------------------------------+
string CPositionInfo::TypeDescription(void) const
  {
   string str;
//---
   return(FormatType(str,PositionType()));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_MAGIC"                          |
//+------------------------------------------------------------------+
long CPositionInfo::Magic(void) const
  {
   return(PositionGetInteger(POSITION_MAGIC));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_IDENTIFIER"                     |
//+------------------------------------------------------------------+
long CPositionInfo::Identifier(void) const
  {
   return(PositionGetInteger(POSITION_IDENTIFIER));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_VOLUME"                         |
//+------------------------------------------------------------------+
double CPositionInfo::Volume(void) const
  {
   return(PositionGetDouble(POSITION_VOLUME));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_PRICE_OPEN"                     |
//+------------------------------------------------------------------+
double CPositionInfo::PriceOpen(void) const
  {
   return(PositionGetDouble(POSITION_PRICE_OPEN));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_SL"                             |
//+------------------------------------------------------------------+
double CPositionInfo::StopLoss(void) const
  {
   return(PositionGetDouble(POSITION_SL));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_TP"                             |
//+------------------------------------------------------------------+
double CPositionInfo::TakeProfit(void) const
  {
   return(PositionGetDouble(POSITION_TP));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_PRICE_CURRENT"                  |
//+------------------------------------------------------------------+
double CPositionInfo::PriceCurrent(void) const
  {
   return(PositionGetDouble(POSITION_PRICE_CURRENT));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_COMMISSION"                     |
//+------------------------------------------------------------------+
double CPositionInfo::Commission(void) const
  {
//--- property POSITION_COMMISSION is deprecated
   SetUserError(ERR_FUNCTION_NOT_ALLOWED);
   return(0);
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_SWAP"                           |
//+------------------------------------------------------------------+
double CPositionInfo::Swap(void) const
  {
   return(PositionGetDouble(POSITION_SWAP));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_PROFIT"                         |
//+------------------------------------------------------------------+
double CPositionInfo::Profit(void) const
  {
   return(PositionGetDouble(POSITION_PROFIT));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_SYMBOL"                         |
//+------------------------------------------------------------------+
string CPositionInfo::Symbol(void) const
  {
   return(PositionGetString(POSITION_SYMBOL));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_COMMENT"                        |
//+------------------------------------------------------------------+
string CPositionInfo::Comment(void) const
  {
   return(PositionGetString(POSITION_COMMENT));
  }
//+------------------------------------------------------------------+
//| Access functions PositionGetInteger(...)                         |
//+------------------------------------------------------------------+
bool CPositionInfo::InfoInteger(const ENUM_POSITION_PROPERTY_INTEGER prop_id,long &var) const
  {
   return(PositionGetInteger(prop_id,var));
  }
//+------------------------------------------------------------------+
//| Access functions PositionGetDouble(...)                          |
//+------------------------------------------------------------------+
bool CPositionInfo::InfoDouble(const ENUM_POSITION_PROPERTY_DOUBLE prop_id,double &var) const
  {
   return(PositionGetDouble(prop_id,var));
  }
//+------------------------------------------------------------------+
//| Access functions PositionGetString(...)                          |
//+------------------------------------------------------------------+
bool CPositionInfo::InfoString(const ENUM_POSITION_PROPERTY_STRING prop_id,string &var) const
  {
   return(PositionGetString(prop_id,var));
  }
//+------------------------------------------------------------------+
//| Converts the position type to text                               |
//+------------------------------------------------------------------+
string CPositionInfo::FormatType(string &str,const uint type) const
  {
//--- see the type
   switch(type)
     {
      case POSITION_TYPE_BUY:
         str="buy";
         break;
      case POSITION_TYPE_SELL:
         str="sell";
         break;
      default:
         str="unknown position type "+(string)type;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the position parameters to text                         |
//+------------------------------------------------------------------+
string CPositionInfo::FormatPosition(string &str) const
  {
   string tmp,type;
   long   tmp_long;
   ENUM_ACCOUNT_MARGIN_MODE margin_mode=(ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
//--- set up
   string symbol_name=this.Symbol();
   int    digits=_Digits;
   if(SymbolInfoInteger(symbol_name,SYMBOL_DIGITS,tmp_long))
      digits=(int)tmp_long;
//--- form the position description
   if(margin_mode==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      str=StringFormat("#%I64u %s %s %s %s",
                       Ticket(),
                       FormatType(type,PositionType()),
                       DoubleToString(Volume(),2),
                       symbol_name,
                       DoubleToString(PriceOpen(),digits+3));
   else
      str=StringFormat("%s %s %s %s",
                       FormatType(type,PositionType()),
                       DoubleToString(Volume(),2),
                       symbol_name,
                       DoubleToString(PriceOpen(),digits+3));
//--- add stops if there are any
   double sl=StopLoss();
   double tp=TakeProfit();
   if(sl!=0.0)
     {
      tmp=StringFormat(" sl: %s",DoubleToString(sl,digits));
      str+=tmp;
     }
   if(tp!=0.0)
     {
      tmp=StringFormat(" tp: %s",DoubleToString(tp,digits));
      str+=tmp;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Access functions PositionSelect(...)                             |
//+------------------------------------------------------------------+
bool CPositionInfo::Select(const string symbol)
  {
   return(PositionSelect(symbol));
  }
//+------------------------------------------------------------------+
//| Access functions PositionSelect(...)                             |
//+------------------------------------------------------------------+
bool CPositionInfo::SelectByMagic(const string symbol,const ulong magic)
  {
   bool res=false;
   uint total=PositionsTotal();
//---
   for(uint i=0; i<total; i++)
     {
      string position_symbol=PositionGetSymbol(i);
      if(position_symbol==symbol && magic==PositionGetInteger(POSITION_MAGIC))
        {
         res=true;
         break;
        }
     }
//---
   return(res);
  }
//+------------------------------------------------------------------+
//| Access functions PositionSelectByTicket(...)                     |
//+------------------------------------------------------------------+
bool CPositionInfo::SelectByTicket(const ulong ticket)
  {
   return(PositionSelectByTicket(ticket));
  }
//+------------------------------------------------------------------+
//| Select a position on the index                                   |
//+------------------------------------------------------------------+
bool CPositionInfo::SelectByIndex(const int index)
  {
   ulong ticket=PositionGetTicket(index);
   return(ticket>0);
  }
//+------------------------------------------------------------------+
//| Stored position's current state                                  |
//+------------------------------------------------------------------+
void CPositionInfo::StoreState(void)
  {
   m_type       =PositionType();
   m_volume     =Volume();
   m_price      =PriceOpen();
   m_stop_loss  =StopLoss();
   m_take_profit=TakeProfit();
  }
//+------------------------------------------------------------------+
//| Check position change                                            |
//+------------------------------------------------------------------+
bool CPositionInfo::CheckState(void)
  {
   if(m_type==PositionType()  &&
      m_volume==Volume()      &&
      m_price==PriceOpen()    &&
      m_stop_loss==StopLoss() &&
      m_take_profit==TakeProfit())
      return(false);
//---
   return(true);
  }
//+------------------------------------------------------------------+

// END EMBEDDED SDK: Trade/PositionInfo.mqh

// BEGIN EMBEDDED SDK: Trade/DealInfo.mqh
//+------------------------------------------------------------------+
//|                                                     DealInfo.mqh |
//|                             Copyright 2000-2026, MetaQuotes Ltd. |
//|                                                     www.mql5.com |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Class CDealInfo.                                                 |
//| Appointment: Class for access to history deal info.              |
//|              Derives from class CObject.                         |
//+------------------------------------------------------------------+
class CDealInfo : public CObject
  {
protected:
   ulong             m_ticket;             // ticket of history order

public:
                     CDealInfo(void);
                    ~CDealInfo(void);
   //--- methods of access to protected data
   void              Ticket(const ulong ticket)   { m_ticket=ticket;  }
   ulong             Ticket(void)           const { return(m_ticket); }
   //--- fast access methods to the integer position propertyes
   long              Order(void) const;
   datetime          Time(void) const;
   ulong             TimeMsc(void) const;
   ENUM_DEAL_TYPE    DealType(void) const;
   string            TypeDescription(void) const;
   ENUM_DEAL_ENTRY   Entry(void) const;
   string            EntryDescription(void) const;
   long              Magic(void) const;
   long              PositionId(void) const;
   //--- fast access methods to the double position propertyes
   double            Volume(void) const;
   double            Price(void) const;
   double            Commission(void) const;
   double            Swap(void) const;
   double            Profit(void) const;
   //--- fast access methods to the string position propertyes
   string            Symbol(void) const;
   string            Comment(void) const;
   string            ExternalId(void) const;
   //--- access methods to the API MQL5 functions
   bool              InfoInteger(ENUM_DEAL_PROPERTY_INTEGER prop_id,long &var) const;
   bool              InfoDouble(ENUM_DEAL_PROPERTY_DOUBLE prop_id,double &var) const;
   bool              InfoString(ENUM_DEAL_PROPERTY_STRING prop_id,string &var) const;
   //--- info methods
   string            FormatAction(string &str,const uint action) const;
   string            FormatEntry(string &str,const uint entry) const;
   string            FormatDeal(string &str) const;
   //--- method for select deal
   bool              SelectByIndex(const int index);
  };
//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CDealInfo::CDealInfo(void)
  {
  }
//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CDealInfo::~CDealInfo(void)
  {
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_ORDER"                              |
//+------------------------------------------------------------------+
long CDealInfo::Order(void) const
  {
   return(HistoryDealGetInteger(m_ticket,DEAL_ORDER));
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_TIME"                               |
//+------------------------------------------------------------------+
datetime CDealInfo::Time(void) const
  {
   return((datetime)HistoryDealGetInteger(m_ticket,DEAL_TIME));
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_TIME_MSC"                           |
//+------------------------------------------------------------------+
ulong CDealInfo::TimeMsc(void) const
  {
   return(HistoryDealGetInteger(m_ticket,DEAL_TIME_MSC));
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_TYPE"                               |
//+------------------------------------------------------------------+
ENUM_DEAL_TYPE CDealInfo::DealType(void) const
  {
   return((ENUM_DEAL_TYPE)HistoryDealGetInteger(m_ticket,DEAL_TYPE));
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_TYPE" as string                     |
//+------------------------------------------------------------------+
string CDealInfo::TypeDescription(void) const
  {
   string str;
//---
   switch(DealType())
     {
      case DEAL_TYPE_BUY:
         str="Buy type";
         break;
      case DEAL_TYPE_SELL:
         str="Sell type";
         break;
      case DEAL_TYPE_BALANCE:
         str="Balance type";
         break;
      case DEAL_TYPE_CREDIT:
         str="Credit type";
         break;
      case DEAL_TYPE_CHARGE:
         str="Charge type";
         break;
      case DEAL_TYPE_CORRECTION:
         str="Correction type";
         break;
      case DEAL_TYPE_BONUS:
         str="Bonus type";
         break;
      case DEAL_TYPE_COMMISSION:
         str="Commission type";
         break;
      case DEAL_TYPE_COMMISSION_DAILY:
         str="Daily Commission type";
         break;
      case DEAL_TYPE_COMMISSION_MONTHLY:
         str="Monthly Commission type";
         break;
      case DEAL_TYPE_COMMISSION_AGENT_DAILY:
         str="Daily Agent Commission type";
         break;
      case DEAL_TYPE_COMMISSION_AGENT_MONTHLY:
         str="Monthly Agent Commission type";
         break;
      case DEAL_TYPE_INTEREST:
         str="Interest Rate type";
         break;
      case DEAL_TYPE_BUY_CANCELED:
         str="Canceled Buy type";
         break;
      case DEAL_TYPE_SELL_CANCELED:
         str="Canceled Sell type";
         break;
      default:
         str="Unknown type";
     }
//---
   return(str);
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_ENTRY"                              |
//+------------------------------------------------------------------+
ENUM_DEAL_ENTRY CDealInfo::Entry(void) const
  {
   return((ENUM_DEAL_ENTRY)HistoryDealGetInteger(m_ticket,DEAL_ENTRY));
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_ENTRY" as string                    |
//+------------------------------------------------------------------+
string CDealInfo::EntryDescription(void) const
  {
   string str;
//---
   switch(CDealInfo::Entry())
     {
      case DEAL_ENTRY_IN:
         str="In entry";
         break;
      case DEAL_ENTRY_OUT:
         str="Out entry";
         break;
      case DEAL_ENTRY_INOUT:
         str="InOut entry";
         break;
      case DEAL_ENTRY_STATE:
         str="Status record";
         break;
      case DEAL_ENTRY_OUT_BY:
         str="Out By entry";
         break;
      default:
         str="Unknown entry";
     }
//---
   return(str);
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_MAGIC"                              |
//+------------------------------------------------------------------+
long CDealInfo::Magic(void) const
  {
   return(HistoryDealGetInteger(m_ticket,DEAL_MAGIC));
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_POSITION_ID"                        |
//+------------------------------------------------------------------+
long CDealInfo::PositionId(void) const
  {
   return(HistoryDealGetInteger(m_ticket,DEAL_POSITION_ID));
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_VOLUME"                             |
//+------------------------------------------------------------------+
double CDealInfo::Volume(void) const
  {
   return(HistoryDealGetDouble(m_ticket,DEAL_VOLUME));
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_PRICE_OPEN"                         |
//+------------------------------------------------------------------+
double CDealInfo::Price(void) const
  {
   return(HistoryDealGetDouble(m_ticket,DEAL_PRICE));
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_COMMISSION"                         |
//+------------------------------------------------------------------+
double CDealInfo::Commission(void) const
  {
   return(HistoryDealGetDouble(m_ticket,DEAL_COMMISSION));
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_SWAP"                               |
//+------------------------------------------------------------------+
double CDealInfo::Swap(void) const
  {
   return(HistoryDealGetDouble(m_ticket,DEAL_SWAP));
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_PROFIT"                             |
//+------------------------------------------------------------------+
double CDealInfo::Profit(void) const
  {
   return(HistoryDealGetDouble(m_ticket,DEAL_PROFIT));
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_SYMBOL"                             |
//+------------------------------------------------------------------+
string CDealInfo::Symbol(void) const
  {
   return(HistoryDealGetString(m_ticket,DEAL_SYMBOL));
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_COMMENT"                            |
//+------------------------------------------------------------------+
string CDealInfo::Comment(void) const
  {
   return(HistoryDealGetString(m_ticket,DEAL_COMMENT));
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_EXTERNAL_ID"                        |
//+------------------------------------------------------------------+
string CDealInfo::ExternalId(void) const
  {
   return(HistoryDealGetString(m_ticket,DEAL_EXTERNAL_ID));
  }
//+------------------------------------------------------------------+
//| Access functions HistoryDealGetInteger(...)                      |
//+------------------------------------------------------------------+
bool CDealInfo::InfoInteger(ENUM_DEAL_PROPERTY_INTEGER prop_id,long &var) const
  {
   return(HistoryDealGetInteger(m_ticket,prop_id,var));
  }
//+------------------------------------------------------------------+
//| Access functions HistoryDealGetDouble(...)                       |
//+------------------------------------------------------------------+
bool CDealInfo::InfoDouble(ENUM_DEAL_PROPERTY_DOUBLE prop_id,double &var) const
  {
   return(HistoryDealGetDouble(m_ticket,prop_id,var));
  }
//+------------------------------------------------------------------+
//| Access functions HistoryDealGetString(...)                       |
//+------------------------------------------------------------------+
bool CDealInfo::InfoString(ENUM_DEAL_PROPERTY_STRING prop_id,string &var) const
  {
   return(HistoryDealGetString(m_ticket,prop_id,var));
  }
//+------------------------------------------------------------------+
//| Converths the type of a  deal to text                            |
//+------------------------------------------------------------------+
string CDealInfo::FormatAction(string &str,const uint action) const
  {
//--- see the type
   switch(action)
     {
      case DEAL_TYPE_BUY:
         str="buy";
         break;
      case DEAL_TYPE_SELL:
         str="sell";
         break;
      case DEAL_TYPE_BALANCE:
         str="balance";
         break;
      case DEAL_TYPE_CREDIT:
         str="credit";
         break;
      case DEAL_TYPE_CHARGE:
         str="charge";
         break;
      case DEAL_TYPE_CORRECTION:
         str="correction";
         break;
      case DEAL_TYPE_BONUS:
         str="bonus";
         break;
      case DEAL_TYPE_COMMISSION:
         str="commission";
         break;
      case DEAL_TYPE_COMMISSION_DAILY:
         str="daily commission";
         break;
      case DEAL_TYPE_COMMISSION_MONTHLY:
         str="monthly commission";
         break;
      case DEAL_TYPE_COMMISSION_AGENT_DAILY:
         str="daily agent commission";
         break;
      case DEAL_TYPE_COMMISSION_AGENT_MONTHLY:
         str="monthly agent commission";
         break;
      case DEAL_TYPE_INTEREST:
         str="interest rate";
         break;
      case DEAL_TYPE_BUY_CANCELED:
         str="canceled buy";
         break;
      case DEAL_TYPE_SELL_CANCELED:
         str="canceled sell";
         break;
      default:
         str="unknown deal type "+(string)action;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the deal direction to text                              |
//+------------------------------------------------------------------+
string CDealInfo::FormatEntry(string &str,const uint entry) const
  {
//--- see the type
   switch(entry)
     {
      case DEAL_ENTRY_IN:
         str="in";
         break;
      case DEAL_ENTRY_OUT:
         str="out";
         break;
      case DEAL_ENTRY_INOUT:
         str="in/out";
         break;
      case DEAL_ENTRY_OUT_BY:
         str="out by";
         break;
      default:
         str="unknown deal entry "+(string)entry;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the deal parameters to text                             |
//+------------------------------------------------------------------+
string CDealInfo::FormatDeal(string &str) const
  {
   string type;
   long   tmp_long;
//--- set up
   string symbol_name=this.Symbol();
   int    digits=_Digits;
   if(SymbolInfoInteger(symbol_name,SYMBOL_DIGITS,tmp_long))
      digits=(int)tmp_long;
//--- form the description of the deal
   switch(DealType())
     {
      //--- Buy-Sell
      case DEAL_TYPE_BUY:
      case DEAL_TYPE_SELL:
         str=StringFormat("#%I64u %s %s %s at %s",
                          Ticket(),
                          FormatAction(type,DealType()),
                          DoubleToString(Volume(),2),
                          symbol_name,
                          DoubleToString(Price(),digits));
         break;

      //--- balance operations
      case DEAL_TYPE_BALANCE:
      case DEAL_TYPE_CREDIT:
      case DEAL_TYPE_CHARGE:
      case DEAL_TYPE_CORRECTION:
      case DEAL_TYPE_BONUS:
      case DEAL_TYPE_COMMISSION:
      case DEAL_TYPE_COMMISSION_DAILY:
      case DEAL_TYPE_COMMISSION_MONTHLY:
      case DEAL_TYPE_COMMISSION_AGENT_DAILY:
      case DEAL_TYPE_COMMISSION_AGENT_MONTHLY:
      case DEAL_TYPE_INTEREST:
         str=StringFormat("#%I64u %s %s [%s]",
                          Ticket(),
                          FormatAction(type,DealType()),
                          DoubleToString(Profit(),2),
                          this.Comment());
         break;

      default:
         str="unknown deal type "+(string)DealType();
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Select a deal on the index                                       |
//+------------------------------------------------------------------+
bool CDealInfo::SelectByIndex(const int index)
  {
   ulong ticket=HistoryDealGetTicket(index);
   if(ticket==0)
      return(false);
   Ticket(ticket);
//---
   return(true);
  }
//+------------------------------------------------------------------+

// END EMBEDDED SDK: Trade/DealInfo.mqh

//+------------------------------------------------------------------+
//| enumerations                                                     |
//+------------------------------------------------------------------+
enum ENUM_LOG_LEVELS
  {
   LOG_LEVEL_NO    =0,
   LOG_LEVEL_ERRORS=1,
   LOG_LEVEL_ALL   =2
  };
//+------------------------------------------------------------------+
//| Class CTrade.                                                    |
//| Appointment: Class trade operations.                             |
//|              Derives from class CObject.                         |
//+------------------------------------------------------------------+
class CTrade : public CObject
  {
protected:
   MqlTradeRequest   m_request;              // request data
   MqlTradeResult    m_result;               // result data
   MqlTradeCheckResult m_check_result;       // result check data
   bool              m_async_mode;           // trade mode
   ulong             m_magic;                // expert magic number
   ulong             m_deviation;            // deviation default
   ENUM_ORDER_TYPE_FILLING m_type_filling;
   ENUM_ACCOUNT_MARGIN_MODE m_margin_mode;
   //---
   ENUM_LOG_LEVELS   m_log_level;

public:
                     CTrade(void);
                    ~CTrade(void);
   //--- methods of access to protected data
   void              LogLevel(const ENUM_LOG_LEVELS log_level) { m_log_level=log_level; }
   void              Request(MqlTradeRequest &request) const;
   ENUM_TRADE_REQUEST_ACTIONS RequestAction(void)   const { return(m_request.action);       }
   string            RequestActionDescription(void) const;
   ulong             RequestMagic(void)             const { return(m_request.magic);        }
   ulong             RequestOrder(void)             const { return(m_request.order);        }
   ulong             RequestPosition(void)          const { return(m_request.position);     }
   ulong             RequestPositionBy(void)        const { return(m_request.position_by);  }
   string            RequestSymbol(void)            const { return(m_request.symbol);       }
   double            RequestVolume(void)            const { return(m_request.volume);       }
   double            RequestPrice(void)             const { return(m_request.price);        }
   double            RequestStopLimit(void)         const { return(m_request.stoplimit);    }
   double            RequestSL(void)                const { return(m_request.sl);           }
   double            RequestTP(void)                const { return(m_request.tp);           }
   ulong             RequestDeviation(void)         const { return(m_request.deviation);    }
   ENUM_ORDER_TYPE   RequestType(void)              const { return(m_request.type);         }
   string            RequestTypeDescription(void) const;
   ENUM_ORDER_TYPE_FILLING RequestTypeFilling(void) const { return(m_request.type_filling); }
   string            RequestTypeFillingDescription(void) const;
   ENUM_ORDER_TYPE_TIME RequestTypeTime(void)       const { return(m_request.type_time);    }
   string            RequestTypeTimeDescription(void) const;
   datetime          RequestExpiration(void)        const { return(m_request.expiration);   }
   string            RequestComment(void)           const { return(m_request.comment);      }
   //---
   void              Result(MqlTradeResult &result) const;
   uint              ResultRetcode(void)         const { return(m_result.retcode);          }
   string            ResultRetcodeDescription(void) const;
   int               ResultRetcodeExternal(void) const { return(m_result.retcode_external); }
   ulong             ResultDeal(void)            const { return(m_result.deal);             }
   ulong             ResultOrder(void)           const { return(m_result.order);            }
   double            ResultVolume(void)          const { return(m_result.volume);           }
   double            ResultPrice(void)           const { return(m_result.price);            }
   double            ResultBid(void)             const { return(m_result.bid);              }
   double            ResultAsk(void)             const { return(m_result.ask);              }
   string            ResultComment(void)         const { return(m_result.comment);          }
   //---
   void              CheckResult(MqlTradeCheckResult &check_result) const;
   uint              CheckResultRetcode(void)     const { return(m_check_result.retcode);      }
   string            CheckResultRetcodeDescription(void) const;
   double            CheckResultBalance(void)     const { return(m_check_result.balance);      }
   double            CheckResultEquity(void)      const { return(m_check_result.equity);       }
   double            CheckResultProfit(void)      const { return(m_check_result.profit);       }
   double            CheckResultMargin(void)      const { return(m_check_result.margin);       }
   double            CheckResultMarginFree(void)  const { return(m_check_result.margin_free);  }
   double            CheckResultMarginLevel(void) const { return(m_check_result.margin_level); }
   string            CheckResultComment(void)     const { return(m_check_result.comment);      }
   //--- trade methods
   void              SetAsyncMode(const bool mode)               { m_async_mode=mode;                }
   void              SetExpertMagicNumber(const ulong magic)     { m_magic=magic;                    }
   void              SetDeviationInPoints(const ulong deviation) { m_deviation=deviation;            }
   void              SetTypeFilling(const ENUM_ORDER_TYPE_FILLING filling) { m_type_filling=filling; }
   bool              SetTypeFillingBySymbol(const string symbol);
   void              SetMarginMode(void) { m_margin_mode=(ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE); }
   //--- methods for working with positions
   bool              PositionOpen(const string symbol,const ENUM_ORDER_TYPE order_type,const double volume,
                                  const double price,const double sl,const double tp,const string comment="");
   bool              PositionModify(const string symbol,const double sl,const double tp);
   bool              PositionModify(const ulong ticket,const double sl,const double tp);
   bool              PositionClose(const string symbol,const ulong deviation=ULONG_MAX);
   bool              PositionClose(const ulong ticket,const ulong deviation=ULONG_MAX);
   bool              PositionCloseBy(const ulong ticket,const ulong ticket_by);
   bool              PositionClosePartial(const string symbol,const double volume,const ulong deviation=ULONG_MAX);
   bool              PositionClosePartial(const ulong ticket,const double volume,const ulong deviation=ULONG_MAX);
   //--- methods for working with pending orders
   bool              OrderOpen(const string symbol,const ENUM_ORDER_TYPE order_type,const double volume,
                               const double limit_price,const double price,const double sl,const double tp,
                               ENUM_ORDER_TYPE_TIME type_time=ORDER_TIME_GTC,const datetime expiration=0,
                               const string comment="");
   bool              OrderModify(const ulong ticket,const double price,const double sl,const double tp,
                                 const ENUM_ORDER_TYPE_TIME type_time,const datetime expiration,const double stoplimit=0.0);
   bool              OrderDelete(const ulong ticket);
   //--- additions methods
   bool              Buy(const double volume,const string symbol=NULL,double price=0.0,const double sl=0.0,const double tp=0.0,const string comment="");
   bool              Sell(const double volume,const string symbol=NULL,double price=0.0,const double sl=0.0,const double tp=0.0,const string comment="");
   bool              BuyLimit(const double volume,const double price,const string symbol=NULL,const double sl=0.0,const double tp=0.0,
                              const ENUM_ORDER_TYPE_TIME type_time=ORDER_TIME_GTC,const datetime expiration=0,const string comment="");
   bool              BuyStop(const double volume,const double price,const string symbol=NULL,const double sl=0.0,const double tp=0.0,
                             const ENUM_ORDER_TYPE_TIME type_time=ORDER_TIME_GTC,const datetime expiration=0,const string comment="");
   bool              SellLimit(const double volume,const double price,const string symbol=NULL,const double sl=0.0,const double tp=0.0,
                               const ENUM_ORDER_TYPE_TIME type_time=ORDER_TIME_GTC,const datetime expiration=0,const string comment="");
   bool              SellStop(const double volume,const double price,const string symbol=NULL,const double sl=0.0,const double tp=0.0,
                              const ENUM_ORDER_TYPE_TIME type_time=ORDER_TIME_GTC,const datetime expiration=0,const string comment="");
   //--- method check
   virtual double    CheckVolume(const string symbol,double volume,double price,ENUM_ORDER_TYPE order_type);
   virtual bool      OrderCheck(const MqlTradeRequest &request,MqlTradeCheckResult &check_result);
   virtual bool      OrderSend(const MqlTradeRequest &request,MqlTradeResult &result);
   //--- info methods
   void              PrintRequest(void) const;
   void              PrintResult(void) const;
   //--- positions
   string            FormatPositionType(string &str,const uint type) const;
   //--- orders
   string            FormatOrderType(string &str,const uint type) const;
   string            FormatOrderStatus(string &str,const uint status) const;
   string            FormatOrderTypeFilling(string &str,const uint type) const;
   string            FormatOrderTypeTime(string &str,const uint type) const;
   string            FormatOrderPrice(string &str,const double price_order,const double price_trigger,const uint digits) const;
   //--- trade request
   string            FormatRequest(string &str,const MqlTradeRequest &request) const;
   string            FormatRequestResult(string &str,const MqlTradeRequest &request,const MqlTradeResult &result) const;

protected:
   bool              FillingCheck(const string symbol);
   bool              ExpirationCheck(const string symbol);
   bool              OrderTypeCheck(const string symbol);
   void              ClearStructures(void);
   bool              IsStopped(const string function);
   bool              IsHedging(void) const { return(m_margin_mode==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING); }
   //--- position select depending on netting or hedging
   bool              SelectPosition(const string symbol);
  };
//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CTrade::CTrade(void) : m_async_mode(false),
                       m_magic(0),
                       m_deviation(10),
                       m_type_filling(ORDER_FILLING_FOK),
                       m_log_level(LOG_LEVEL_ERRORS)
  {
   SetMarginMode();
//--- initialize protected data
   ClearStructures();
//--- check programm mode
   if(MQLInfoInteger(ENUM_MQL_INFO_INTEGER::MQL_TESTER))
      m_log_level=LOG_LEVEL_ALL;
   if(MQLInfoInteger(ENUM_MQL_INFO_INTEGER::MQL_OPTIMIZATION))
      m_log_level=LOG_LEVEL_NO;
  }
//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CTrade::~CTrade(void)
  {
  }
//+------------------------------------------------------------------+
//| Get the request structure                                        |
//+------------------------------------------------------------------+
void CTrade::Request(MqlTradeRequest &request) const
  {
   request.action      =m_request.action;
   request.magic       =m_request.magic;
   request.order       =m_request.order;
   request.symbol      =m_request.symbol;
   request.volume      =m_request.volume;
   request.price       =m_request.price;
   request.stoplimit   =m_request.stoplimit;
   request.sl          =m_request.sl;
   request.tp          =m_request.tp;
   request.deviation   =m_request.deviation;
   request.type        =m_request.type;
   request.type_filling=m_request.type_filling;
   request.type_time   =m_request.type_time;
   request.expiration  =m_request.expiration;
   request.comment     =m_request.comment;
   request.position    =m_request.position;
   request.position_by =m_request.position_by;
  }
//+------------------------------------------------------------------+
//| Get the trade action as string                                   |
//+------------------------------------------------------------------+
string CTrade::RequestActionDescription(void) const
  {
   string str;
//---
   FormatRequest(str,m_request);
//---
   return(str);
  }
//+------------------------------------------------------------------+
//| Get the order type as string                                     |
//+------------------------------------------------------------------+
string CTrade::RequestTypeDescription(void) const
  {
   string str;
//---
   FormatOrderType(str,(uint)m_request.order);
//---
   return(str);
  }
//+------------------------------------------------------------------+
//| Get the order type filling as string                             |
//+------------------------------------------------------------------+
string CTrade::RequestTypeFillingDescription(void) const
  {
   string str;
//---
   FormatOrderTypeFilling(str,m_request.type_filling);
//---
   return(str);
  }
//+------------------------------------------------------------------+
//| Get the order type time as string                                |
//+------------------------------------------------------------------+
string CTrade::RequestTypeTimeDescription(void) const
  {
   string str;
//---
   FormatOrderTypeTime(str,m_request.type_time);
//---
   return(str);
  }
//+------------------------------------------------------------------+
//| Get the result structure                                         |
//+------------------------------------------------------------------+
void CTrade::Result(MqlTradeResult &result) const
  {
   result.retcode   =m_result.retcode;
   result.deal      =m_result.deal;
   result.order     =m_result.order;
   result.volume    =m_result.volume;
   result.price     =m_result.price;
   result.bid       =m_result.bid;
   result.ask       =m_result.ask;
   result.comment   =m_result.comment;
   result.request_id=m_result.request_id;
   result.retcode_external=m_result.retcode_external;
  }
//+------------------------------------------------------------------+
//| Get the retcode value as string                                  |
//+------------------------------------------------------------------+
string CTrade::ResultRetcodeDescription(void) const
  {
   string str;
//---
   FormatRequestResult(str,m_request,m_result);
//---
   return(str);
  }
//+------------------------------------------------------------------+
//| Get the check result structure                                   |
//+------------------------------------------------------------------+
void CTrade::CheckResult(MqlTradeCheckResult &check_result) const
  {
//--- copy structure
   check_result.retcode     =m_check_result.retcode;
   check_result.balance     =m_check_result.balance;
   check_result.equity      =m_check_result.equity;
   check_result.profit      =m_check_result.profit;
   check_result.margin      =m_check_result.margin;
   check_result.margin_free =m_check_result.margin_free;
   check_result.margin_level=m_check_result.margin_level;
   check_result.comment     =m_check_result.comment;
  }
//+------------------------------------------------------------------+
//| Get the check retcode value as string                            |
//+------------------------------------------------------------------+
string CTrade::CheckResultRetcodeDescription(void) const
  {
   string         str;
   MqlTradeResult result;
//---
   result.retcode=m_check_result.retcode;
   FormatRequestResult(str,m_request,result);
//---
   return(str);
  }
//+------------------------------------------------------------------+
//| Open position                                                    |
//+------------------------------------------------------------------+
bool CTrade::PositionOpen(const string symbol,const ENUM_ORDER_TYPE order_type,const double volume,
                          const double price,const double sl,const double tp,const string comment)
  {
//--- check stopped
   if(IsStopped(__FUNCTION__))
      return(false);
//--- clean
   ClearStructures();
//--- check
   if(order_type!=ORDER_TYPE_BUY && order_type!=ORDER_TYPE_SELL)
     {
      m_result.retcode=TRADE_RETCODE_INVALID;
      m_result.comment="Invalid order type";
      return(false);
     }
//--- setting request
   m_request.action   =TRADE_ACTION_DEAL;
   m_request.symbol   =symbol;
   m_request.magic    =m_magic;
   m_request.volume   =volume;
   m_request.type     =order_type;
   m_request.price    =price;
   m_request.sl       =sl;
   m_request.tp       =tp;
   m_request.deviation=m_deviation;
//--- check order type
   if(!OrderTypeCheck(symbol))
      return(false);
//--- check filling
   if(!FillingCheck(symbol))
      return(false);
   m_request.comment=comment;
//--- action and return the result
   return(OrderSend(m_request,m_result));
  }
//+------------------------------------------------------------------+
//| Modify specified opened position                                 |
//+------------------------------------------------------------------+
bool CTrade::PositionModify(const string symbol,const double sl,const double tp)
  {
//--- check stopped
   if(IsStopped(__FUNCTION__))
      return(false);
//--- check position existence
   if(!SelectPosition(symbol))
      return(false);
//--- clean
   ClearStructures();
//--- setting request
   m_request.action  =TRADE_ACTION_SLTP;
   m_request.symbol  =symbol;
   m_request.magic   =m_magic;
   m_request.sl      =sl;
   m_request.tp      =tp;
   m_request.position=PositionGetInteger(POSITION_TICKET);
//--- action and return the result
   return(OrderSend(m_request,m_result));
  }
//+------------------------------------------------------------------+
//| Modify specified opened position                                 |
//+------------------------------------------------------------------+
bool CTrade::PositionModify(const ulong ticket,const double sl,const double tp)
  {
//--- check stopped
   if(IsStopped(__FUNCTION__))
      return(false);
//--- check position existence
   if(!PositionSelectByTicket(ticket))
      return(false);
//--- clean
   ClearStructures();
//--- setting request
   m_request.action  =TRADE_ACTION_SLTP;
   m_request.position=ticket;
   m_request.symbol  =PositionGetString(POSITION_SYMBOL);
   m_request.magic   =m_magic;
   m_request.sl      =sl;
   m_request.tp      =tp;
//--- action and return the result
   return(OrderSend(m_request,m_result));
  }
//+------------------------------------------------------------------+
//| Close specified opened position                                  |
//+------------------------------------------------------------------+
bool CTrade::PositionClose(const string symbol,const ulong deviation)
  {
   bool partial_close=false;
   int  retry_count  =10;
   uint retcode      =TRADE_RETCODE_REJECT;
//--- check stopped
   if(IsStopped(__FUNCTION__))
      return(false);
//--- clean
   ClearStructures();
//--- check filling
   if(!FillingCheck(symbol))
      return(false);
   do
     {
      //--- check
      if(SelectPosition(symbol))
        {
         if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)
           {
            //--- prepare request for close BUY position
            m_request.type =ORDER_TYPE_SELL;
            m_request.price=SymbolInfoDouble(symbol,SYMBOL_BID);
           }
         else
           {
            //--- prepare request for close SELL position
            m_request.type =ORDER_TYPE_BUY;
            m_request.price=SymbolInfoDouble(symbol,SYMBOL_ASK);
           }
        }
      else
        {
         //--- position not found
         m_result.retcode=retcode;
         return(false);
        }
      //--- setting request
      m_request.action   =TRADE_ACTION_DEAL;
      m_request.symbol   =symbol;
      m_request.volume   =PositionGetDouble(POSITION_VOLUME);
      m_request.magic    =m_magic;
      m_request.deviation=(deviation==ULONG_MAX) ? m_deviation : deviation;
      m_request.position =PositionGetInteger(POSITION_TICKET);
      //--- check volume
      double max_volume=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
      if(m_request.volume>max_volume)
        {
         m_request.volume=max_volume;
         partial_close=true;
        }
      else
         partial_close=false;
      //--- hedging? just send order
      if(IsHedging())
         return(OrderSend(m_request,m_result));
      //--- order send
      if(!OrderSend(m_request,m_result))
        {
         if(--retry_count!=0)
            continue;
         if(retcode==TRADE_RETCODE_DONE_PARTIAL)
            m_result.retcode=retcode;
         return(false);
        }
      //--- WARNING. If position volume exceeds the maximum volume allowed for deal,
      //--- and when the asynchronous trade mode is on, for safety reasons, position is closed not completely,
      //--- but partially. It is decreased by the maximum volume allowed for deal.
      if(m_async_mode)
         break;
      retcode=TRADE_RETCODE_DONE_PARTIAL;
      if(partial_close)
         Sleep(1000);
     }
   while(partial_close);
//--- succeed
   return(true);
  }
//+------------------------------------------------------------------+
//| Close specified opened position                                  |
//+------------------------------------------------------------------+
bool CTrade::PositionClose(const ulong ticket,const ulong deviation)
  {
//--- check stopped
   if(IsStopped(__FUNCTION__))
      return(false);
//--- check position existence
   if(!PositionSelectByTicket(ticket))
      return(false);
   string symbol=PositionGetString(POSITION_SYMBOL);
//--- clean
   ClearStructures();
//--- check filling
   if(!FillingCheck(symbol))
      return(false);
//--- check
   if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)
     {
      //--- prepare request for close BUY position
      m_request.type =ORDER_TYPE_SELL;
      m_request.price=SymbolInfoDouble(symbol,SYMBOL_BID);
     }
   else
     {
      //--- prepare request for close SELL position
      m_request.type =ORDER_TYPE_BUY;
      m_request.price=SymbolInfoDouble(symbol,SYMBOL_ASK);
     }
//--- setting request
   m_request.action   =TRADE_ACTION_DEAL;
   m_request.position =ticket;
   m_request.symbol   =symbol;
   m_request.volume   =PositionGetDouble(POSITION_VOLUME);
   m_request.magic    =m_magic;
   m_request.deviation=(deviation==ULONG_MAX) ? m_deviation : deviation;
//--- close position
   return(OrderSend(m_request,m_result));
  }
//+------------------------------------------------------------------+
//| Close one position by other                                      |
//+------------------------------------------------------------------+
bool CTrade::PositionCloseBy(const ulong ticket,const ulong ticket_by)
  {
//--- check stopped
   if(IsStopped(__FUNCTION__))
      return(false);
//--- check hedging mode
   if(!IsHedging())
      return(false);
//--- check position existence
   if(!PositionSelectByTicket(ticket))
      return(false);
   string symbol=PositionGetString(POSITION_SYMBOL);
   ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   if(!PositionSelectByTicket(ticket_by))
      return(false);
   string symbol_by=PositionGetString(POSITION_SYMBOL);
   ENUM_POSITION_TYPE type_by=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
//--- check positions
   if(type==type_by)
      return(false);
   if(symbol!=symbol_by)
      return(false);
//--- clean
   ClearStructures();
//--- check filling
   if(!FillingCheck(symbol))
      return(false);
//--- setting request
   m_request.action     =TRADE_ACTION_CLOSE_BY;
   m_request.position   =ticket;
   m_request.position_by=ticket_by;
   m_request.magic      =m_magic;
//--- close position
   return(OrderSend(m_request,m_result));
  }
//+------------------------------------------------------------------+
//| Partial close specified opened position (for hedging mode only)  |
//+------------------------------------------------------------------+
bool CTrade::PositionClosePartial(const string symbol,const double volume,const ulong deviation)
  {
   uint retcode=TRADE_RETCODE_REJECT;
//--- check stopped
   if(IsStopped(__FUNCTION__))
      return(false);
//--- for hedging mode only
   if(!IsHedging())
      return(false);
//--- clean
   ClearStructures();
//--- check filling
   if(!FillingCheck(symbol))
      return(false);
//--- check
   if(SelectPosition(symbol))
     {
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)
        {
         //--- prepare request for close BUY position
         m_request.type =ORDER_TYPE_SELL;
         m_request.price=SymbolInfoDouble(symbol,SYMBOL_BID);
        }
      else
        {
         //--- prepare request for close SELL position
         m_request.type =ORDER_TYPE_BUY;
         m_request.price=SymbolInfoDouble(symbol,SYMBOL_ASK);
        }
     }
   else
     {
      //--- position not found
      m_result.retcode=retcode;
      return(false);
     }
//--- check volume
   double position_volume=PositionGetDouble(POSITION_VOLUME);
   if(position_volume>volume)
      position_volume=volume;
//--- setting request
   m_request.action   =TRADE_ACTION_DEAL;
   m_request.symbol   =symbol;
   m_request.volume   =position_volume;
   m_request.magic    =m_magic;
   m_request.deviation=(deviation==ULONG_MAX) ? m_deviation : deviation;
   m_request.position =PositionGetInteger(POSITION_TICKET);
//--- hedging? just send order
   return(OrderSend(m_request,m_result));
  }
//+------------------------------------------------------------------+
//| Partial close specified opened position (for hedging mode only)  |
//+------------------------------------------------------------------+
bool CTrade::PositionClosePartial(const ulong ticket,const double volume,const ulong deviation)
  {
//--- check stopped
   if(IsStopped(__FUNCTION__))
      return(false);
//--- for hedging mode only
   if(!IsHedging())
      return(false);
//--- check position existence
   if(!PositionSelectByTicket(ticket))
      return(false);
   string symbol=PositionGetString(POSITION_SYMBOL);
//--- clean
   ClearStructures();
//--- check filling
   if(!FillingCheck(symbol))
      return(false);
//--- check
   if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)
     {
      //--- prepare request for close BUY position
      m_request.type =ORDER_TYPE_SELL;
      m_request.price=SymbolInfoDouble(symbol,SYMBOL_BID);
     }
   else
     {
      //--- prepare request for close SELL position
      m_request.type =ORDER_TYPE_BUY;
      m_request.price=SymbolInfoDouble(symbol,SYMBOL_ASK);
     }
//--- check volume
   double position_volume=PositionGetDouble(POSITION_VOLUME);
   if(position_volume>volume)
      position_volume=volume;
//--- setting request
   m_request.action   =TRADE_ACTION_DEAL;
   m_request.position =ticket;
   m_request.symbol   =symbol;
   m_request.volume   =position_volume;
   m_request.magic    =m_magic;
   m_request.deviation=(deviation==ULONG_MAX) ? m_deviation : deviation;
//--- close position
   return(OrderSend(m_request,m_result));
  }
//+------------------------------------------------------------------+
//| Installation pending order                                       |
//+------------------------------------------------------------------+
bool CTrade::OrderOpen(const string symbol,const ENUM_ORDER_TYPE order_type,const double volume,const double limit_price,
                       const double price,const double sl,const double tp,
                       ENUM_ORDER_TYPE_TIME type_time,const datetime expiration,const string comment)
  {
//--- check stopped
   if(IsStopped(__FUNCTION__))
      return(false);
//--- clean
   ClearStructures();
//--- check filling
   if(!FillingCheck(symbol))
      return(false);
//--- check order type
   if(order_type==ORDER_TYPE_BUY || order_type==ORDER_TYPE_SELL)
     {
      m_result.retcode=TRADE_RETCODE_INVALID;
      m_result.comment="Invalid order type";
      return(false);
     }
//--- check order expiration
   if(type_time==ORDER_TIME_GTC && expiration==0)
     {
      int exp=(int)SymbolInfoInteger(symbol,SYMBOL_EXPIRATION_MODE);
      if((exp&SYMBOL_EXPIRATION_GTC)!=SYMBOL_EXPIRATION_GTC)
        {
         //--- if you place order for an unlimited time and if placing of such orders is prohibited
         //--- try to place order with expiration at the end of the day
         if((exp&SYMBOL_EXPIRATION_DAY)!=SYMBOL_EXPIRATION_DAY)
           {
            //--- if even this is not possible - error
            Print(__FUNCTION__,": Error: Unable to place order without explicitly specified expiration time");
            m_result.retcode=TRADE_RETCODE_INVALID_EXPIRATION;
            m_result.comment="Invalid expiration type";
            return(false);
           }
         type_time=ORDER_TIME_DAY;
        }
     }
//--- setting request
   m_request.action      =TRADE_ACTION_PENDING;
   m_request.symbol      =symbol;
   m_request.magic       =m_magic;
   m_request.volume      =volume;
   m_request.type        =order_type;
   m_request.stoplimit   =limit_price;
   m_request.price       =price;
   m_request.sl          =sl;
   m_request.tp          =tp;
   m_request.type_time   =type_time;
   m_request.expiration  =expiration;
//--- check order type
   if(!OrderTypeCheck(symbol))
      return(false);
//--- check filling
   if(!FillingCheck(symbol))
     {
      m_result.retcode=TRADE_RETCODE_INVALID_FILL;
      Print(__FUNCTION__+": Invalid filling type");
      return(false);
     }
//--- check expiration
   if(!ExpirationCheck(symbol))
     {
      m_result.retcode=TRADE_RETCODE_INVALID_EXPIRATION;
      Print(__FUNCTION__+": Invalid expiration type");
      return(false);
     }
   m_request.comment=comment;
//--- action and return the result
   return(OrderSend(m_request,m_result));
  }
//+------------------------------------------------------------------+
//| Modify specified pending order                                   |
//+------------------------------------------------------------------+
bool CTrade::OrderModify(const ulong ticket,const double price,const double sl,const double tp,
                         const ENUM_ORDER_TYPE_TIME type_time,const datetime expiration,const double stoplimit)
  {
//--- check stopped
   if(IsStopped(__FUNCTION__))
      return(false);
//--- check order existence
   if(!OrderSelect(ticket))
      return(false);
//--- clean
   ClearStructures();
//--- setting request
   m_request.symbol      =OrderGetString(ORDER_SYMBOL);
   m_request.action      =TRADE_ACTION_MODIFY;
   m_request.magic       =m_magic;
   m_request.order       =ticket;
   m_request.price       =price;
   m_request.stoplimit   =stoplimit;
   m_request.sl          =sl;
   m_request.tp          =tp;
   m_request.type_time   =type_time;
   m_request.expiration  =expiration;
//--- action and return the result
   return(OrderSend(m_request,m_result));
  }
//+------------------------------------------------------------------+
//| Delete specified pending order                                   |
//+------------------------------------------------------------------+
bool CTrade::OrderDelete(const ulong ticket)
  {
//--- check stopped
   if(IsStopped(__FUNCTION__))
      return(false);
//--- clean
   ClearStructures();
//--- setting request
   m_request.action    =TRADE_ACTION_REMOVE;
   m_request.magic     =m_magic;
   m_request.order     =ticket;
//--- action and return the result
   return(OrderSend(m_request,m_result));
  }
//+------------------------------------------------------------------+
//| Output full information of request to log                        |
//+------------------------------------------------------------------+
void CTrade::PrintRequest(void) const
  {
   if(m_log_level<LOG_LEVEL_ALL)
      return;
//---
   string str;
   PrintFormat("%s",FormatRequest(str,m_request));
  }
//+------------------------------------------------------------------+
//| Output full information of result to log                         |
//+------------------------------------------------------------------+
void CTrade::PrintResult(void) const
  {
   if(m_log_level<LOG_LEVEL_ALL)
      return;
//---
   string str;
   PrintFormat("%s",FormatRequestResult(str,m_request,m_result));
  }
//+------------------------------------------------------------------+
//| Clear structures m_request,m_result and m_check_result           |
//+------------------------------------------------------------------+
void CTrade::ClearStructures(void)
  {
   ZeroMemory(m_request);
   ZeroMemory(m_result);
   ZeroMemory(m_check_result);
  }
//+------------------------------------------------------------------+
//| Checks forced shutdown of MQL5-program                           |
//+------------------------------------------------------------------+
bool CTrade::IsStopped(const string function)
  {
   if(!::IsStopped())
      return(false);
//--- MQL5 program is stopped
   PrintFormat("%s: MQL5 program is stopped. Trading is disabled",function);
   m_result.retcode=TRADE_RETCODE_CLIENT_DISABLES_AT;
   return(true);
  }
//+------------------------------------------------------------------+
//| Buy operation                                                    |
//+------------------------------------------------------------------+
bool CTrade::Buy(const double volume,const string symbol=NULL,double price=0.0,const double sl=0.0,const double tp=0.0,const string comment="")
  {
//--- check volume
   if(volume<=0.0)
     {
      m_result.retcode=TRADE_RETCODE_INVALID_VOLUME;
      return(false);
     }
//--- check symbol
   string symbol_name=(symbol==NULL) ? _Symbol : symbol;
//--- check price
   if(price==0.0)
      price=SymbolInfoDouble(symbol_name,SYMBOL_ASK);
//---
   return(PositionOpen(symbol_name,ORDER_TYPE_BUY,volume,price,sl,tp,comment));
  }
//+------------------------------------------------------------------+
//| Sell operation                                                   |
//+------------------------------------------------------------------+
bool CTrade::Sell(const double volume,const string symbol=NULL,double price=0.0,const double sl=0.0,const double tp=0.0,const string comment="")
  {
//--- check volume
   if(volume<=0.0)
     {
      m_result.retcode=TRADE_RETCODE_INVALID_VOLUME;
      return(false);
     }
//--- check symbol
   string symbol_name=(symbol==NULL) ? _Symbol : symbol;
//--- check price
   if(price==0.0)
      price=SymbolInfoDouble(symbol_name,SYMBOL_BID);
//---
   return(PositionOpen(symbol_name,ORDER_TYPE_SELL,volume,price,sl,tp,comment));
  }
//+------------------------------------------------------------------+
//| Send BUY_LIMIT order                                             |
//+------------------------------------------------------------------+
bool CTrade::BuyLimit(const double volume,const double price,const string symbol=NULL,const double sl=0.0,const double tp=0.0,
                      const ENUM_ORDER_TYPE_TIME type_time=ORDER_TIME_GTC,const datetime expiration=0,const string comment="")
  {
   string symbol_name;
//--- check volume
   if(volume<=0.0)
     {
      m_result.retcode=TRADE_RETCODE_INVALID_VOLUME;
      return(false);
     }
//--- check symbol
   symbol_name=(symbol==NULL)?Symbol():symbol;
//--- send "BUY_LIMIT" order
   return(OrderOpen(symbol_name,ORDER_TYPE_BUY_LIMIT,volume,0.0,price,sl,tp,type_time,expiration,comment));
  }
//+------------------------------------------------------------------+
//| Send BUY_STOP order                                              |
//+------------------------------------------------------------------+
bool CTrade::BuyStop(const double volume,const double price,const string symbol=NULL,const double sl=0.0,const double tp=0.0,
                     const ENUM_ORDER_TYPE_TIME type_time=ORDER_TIME_GTC,const datetime expiration=0,const string comment="")
  {
   string symbol_name;
//--- check volume
   if(volume<=0.0)
     {
      m_result.retcode=TRADE_RETCODE_INVALID_VOLUME;
      return(false);
     }
//--- check symbol
   symbol_name=(symbol==NULL)?Symbol():symbol;
//--- send "BUY_STOP" order
   return(OrderOpen(symbol_name,ORDER_TYPE_BUY_STOP,volume,0.0,price,sl,tp,type_time,expiration,comment));
  }
//+------------------------------------------------------------------+
//| Send SELL_LIMIT order                                            |
//+------------------------------------------------------------------+
bool CTrade::SellLimit(const double volume,const double price,const string symbol=NULL,const double sl=0.0,const double tp=0.0,
                       const ENUM_ORDER_TYPE_TIME type_time=ORDER_TIME_GTC,const datetime expiration=0,const string comment="")
  {
   string symbol_name;
//--- check volume
   if(volume<=0.0)
     {
      m_result.retcode=TRADE_RETCODE_INVALID_VOLUME;
      return(false);
     }
//--- check symbol
   symbol_name=(symbol==NULL)?Symbol():symbol;
//--- send "SELL_LIMIT" order
   return(OrderOpen(symbol_name,ORDER_TYPE_SELL_LIMIT,volume,0.0,price,sl,tp,type_time,expiration,comment));
  }
//+------------------------------------------------------------------+
//| Send SELL_STOP order                                             |
//+------------------------------------------------------------------+
bool CTrade::SellStop(const double volume,const double price,const string symbol=NULL,const double sl=0.0,const double tp=0.0,
                      const ENUM_ORDER_TYPE_TIME type_time=ORDER_TIME_GTC,const datetime expiration=0,const string comment="")
  {
   string symbol_name;
//--- check volume
   if(volume<=0.0)
     {
      m_result.retcode=TRADE_RETCODE_INVALID_VOLUME;
      return(false);
     }
//--- check symbol
   symbol_name=(symbol==NULL)?Symbol():symbol;
//--- send "SELL_STOP" order
   return(OrderOpen(symbol_name,ORDER_TYPE_SELL_STOP,volume,0.0,price,sl,tp,type_time,expiration,comment));
  }
//+------------------------------------------------------------------+
//| Converts the position type to text                               |
//+------------------------------------------------------------------+
string CTrade::FormatPositionType(string &str,const uint type) const
  {
//--- see the type
   switch(type)
     {
      case POSITION_TYPE_BUY:
         str="buy";
         break;
      case POSITION_TYPE_SELL:
         str="sell";
         break;
      default:
         str="unknown position type "+(string)type;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the order type to text                                  |
//+------------------------------------------------------------------+
string CTrade::FormatOrderType(string &str,const uint type) const
  {
//--- see the type
   switch(type)
     {
      case ORDER_TYPE_BUY:
         str="buy";
         break;
      case ORDER_TYPE_SELL:
         str="sell";
         break;
      case ORDER_TYPE_BUY_LIMIT:
         str="buy limit";
         break;
      case ORDER_TYPE_SELL_LIMIT:
         str="sell limit";
         break;
      case ORDER_TYPE_BUY_STOP:
         str="buy stop";
         break;
      case ORDER_TYPE_SELL_STOP:
         str="sell stop";
         break;
      case ORDER_TYPE_BUY_STOP_LIMIT:
         str="buy stop limit";
         break;
      case ORDER_TYPE_SELL_STOP_LIMIT:
         str="sell stop limit";
         break;
      default:
         str="unknown order type "+(string)type;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the order filling type to text                          |
//+------------------------------------------------------------------+
string CTrade::FormatOrderTypeFilling(string &str,const uint type) const
  {
//--- see the type
   switch(type)
     {
      case ORDER_FILLING_RETURN:
         str="return remainder";
         break;
      case ORDER_FILLING_IOC:
         str="cancel remainder";
         break;
      case ORDER_FILLING_FOK:
         str="fill or kill";
         break;
      default:
         str="unknown type filling "+(string)type;
         break;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the type of order by expiration to text                 |
//+------------------------------------------------------------------+
string CTrade::FormatOrderTypeTime(string &str,const uint type) const
  {
//--- see the type
   switch(type)
     {
      case ORDER_TIME_GTC:
         str="gtc";
         break;
      case ORDER_TIME_DAY:
         str="day";
         break;
      case ORDER_TIME_SPECIFIED:
         str="specified";
         break;
      case ORDER_TIME_SPECIFIED_DAY:
         str="specified day";
         break;
      default:
         str="unknown type time "+(string)type;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the order prices to text                                |
//+------------------------------------------------------------------+
string CTrade::FormatOrderPrice(string &str,const double price_order,const double price_trigger,const uint digits) const
  {
   string price,trigger;
//--- Is there its trigger price?
   if(price_trigger)
     {
      price  =DoubleToString(price_order,digits);
      trigger=DoubleToString(price_trigger,digits);
      str    =StringFormat("%s (%s)",price,trigger);
     }
   else
      str=DoubleToString(price_order,digits);
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the parameters of a trade request to text               |
//+------------------------------------------------------------------+
string CTrade::FormatRequest(string &str,const MqlTradeRequest &request) const
  {
   string type,price,price_new;
   string tmp_string;
   long   tmp_long;
//--- clean
   str="";
//--- set up
   string symbol_name=(request.symbol==NULL) ? _Symbol : request.symbol;
   int    digits=_Digits;
   ENUM_SYMBOL_TRADE_EXECUTION trade_execution=0;
   if(SymbolInfoInteger(symbol_name,SYMBOL_DIGITS,tmp_long))
      digits=(int)tmp_long;
   if(SymbolInfoInteger(symbol_name,SYMBOL_TRADE_EXEMODE,tmp_long))
      trade_execution=(ENUM_SYMBOL_TRADE_EXECUTION)tmp_long;
//--- see what is wanted
   switch(request.action)
     {
      //--- instant execution of a deal
      case TRADE_ACTION_DEAL:
         switch(trade_execution)
           {
            //--- request execution
            case SYMBOL_TRADE_EXECUTION_REQUEST:
               if(IsHedging() && request.position!=0)
                  str=StringFormat("request %s %s position #%I64u %s at %s",
                                   FormatOrderType(type,request.type),
                                   DoubleToString(request.volume,2),
                                   request.position,
                                   request.symbol,
                                   DoubleToString(request.price,digits));
               else
                  str=StringFormat("request %s %s %s at %s",
                                   FormatOrderType(type,request.type),
                                   DoubleToString(request.volume,2),
                                   request.symbol,
                                   DoubleToString(request.price,digits));
               //--- Is there SL or TP?
               if(request.sl!=0.0)
                 {
                  tmp_string=StringFormat(" sl: %s",DoubleToString(request.sl,digits));
                  str+=tmp_string;
                 }
               if(request.tp!=0.0)
                 {
                  tmp_string=StringFormat(" tp: %s",DoubleToString(request.tp,digits));
                  str+=tmp_string;
                 }
               break;
            //--- instant execution
            case SYMBOL_TRADE_EXECUTION_INSTANT:
               if(IsHedging() && request.position!=0)
                  str=StringFormat("instant %s %s position #%I64u %s at %s",
                                   FormatOrderType(type,request.type),
                                   DoubleToString(request.volume,2),
                                   request.position,
                                   request.symbol,
                                   DoubleToString(request.price,digits));
               else
                  str=StringFormat("instant %s %s %s at %s",
                                   FormatOrderType(type,request.type),
                                   DoubleToString(request.volume,2),
                                   request.symbol,
                                   DoubleToString(request.price,digits));
               //--- Is there SL or TP?
               if(request.sl!=0.0)
                 {
                  tmp_string=StringFormat(" sl: %s",DoubleToString(request.sl,digits));
                  str+=tmp_string;
                 }
               if(request.tp!=0.0)
                 {
                  tmp_string=StringFormat(" tp: %s",DoubleToString(request.tp,digits));
                  str+=tmp_string;
                 }
               break;
            //--- market execution
            case SYMBOL_TRADE_EXECUTION_MARKET:
               if(IsHedging() && request.position!=0)
                  str=StringFormat("market %s %s position #%I64u %s",
                                   FormatOrderType(type,request.type),
                                   DoubleToString(request.volume,2),
                                   request.position,
                                   request.symbol);
               else
                  str=StringFormat("market %s %s %s",
                                   FormatOrderType(type,request.type),
                                   DoubleToString(request.volume,2),
                                   request.symbol);
               //--- Is there SL or TP?
               if(request.sl!=0.0)
                 {
                  tmp_string=StringFormat(" sl: %s",DoubleToString(request.sl,digits));
                  str+=tmp_string;
                 }
               if(request.tp!=0.0)
                 {
                  tmp_string=StringFormat(" tp: %s",DoubleToString(request.tp,digits));
                  str+=tmp_string;
                 }
               break;
            //--- exchange execution
            case SYMBOL_TRADE_EXECUTION_EXCHANGE:
               if(IsHedging() && request.position!=0)
                  str=StringFormat("exchange %s %s position #%I64u %s",
                                   FormatOrderType(type,request.type),
                                   DoubleToString(request.volume,2),
                                   request.position,
                                   request.symbol);
               else
                  str=StringFormat("exchange %s %s %s",
                                   FormatOrderType(type,request.type),
                                   DoubleToString(request.volume,2),
                                   request.symbol);
               //--- Is there SL or TP?
               if(request.sl!=0.0)
                 {
                  tmp_string=StringFormat(" sl: %s",DoubleToString(request.sl,digits));
                  str+=tmp_string;
                 }
               if(request.tp!=0.0)
                 {
                  tmp_string=StringFormat(" tp: %s",DoubleToString(request.tp,digits));
                  str+=tmp_string;
                 }
               break;
           }
         //--- end of TRADE_ACTION_DEAL processing
         break;

      //--- setting a pending order
      case TRADE_ACTION_PENDING:
         str=StringFormat("%s %s %s at %s",
                          FormatOrderType(type,request.type),
                          DoubleToString(request.volume,2),
                          request.symbol,
                          FormatOrderPrice(price,request.price,request.stoplimit,digits));
         //--- Is there SL or TP?
         if(request.sl!=0.0)
           {
            tmp_string=StringFormat(" sl: %s",DoubleToString(request.sl,digits));
            str+=tmp_string;
           }
         if(request.tp!=0.0)
           {
            tmp_string=StringFormat(" tp: %s",DoubleToString(request.tp,digits));
            str+=tmp_string;
           }
         break;

      //--- Setting SL/TP
      case TRADE_ACTION_SLTP:
         if(IsHedging() && request.position!=0)
            str=StringFormat("modify position #%I64u %s (sl: %s, tp: %s)",
                             request.position,
                             request.symbol,
                             DoubleToString(request.sl,digits),
                             DoubleToString(request.tp,digits));
         else
            str=StringFormat("modify %s (sl: %s, tp: %s)",
                             request.symbol,
                             DoubleToString(request.sl,digits),
                             DoubleToString(request.tp,digits));
         break;

      //--- modifying a pending order
      case TRADE_ACTION_MODIFY:
         str=StringFormat("modify #%I64u at %s (sl: %s tp: %s)",
                          request.order,
                          FormatOrderPrice(price_new,request.price,request.stoplimit,digits),
                          DoubleToString(request.sl,digits),
                          DoubleToString(request.tp,digits));
         break;

      //--- deleting a pending order
      case TRADE_ACTION_REMOVE:
         str=StringFormat("cancel #%I64u",request.order);
         break;

      //--- close by
      case TRADE_ACTION_CLOSE_BY:
         if(IsHedging() && request.position!=0)
            str=StringFormat("close position #%I64u by #%I64u",request.position,request.position_by);
         else
            str=StringFormat("wrong action close by (#%I64u by #%I64u)",request.position,request.position_by);
         break;

      default:
         str="unknown action "+(string)request.action;
         break;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the result of a request to text                         |
//+------------------------------------------------------------------+
string CTrade::FormatRequestResult(string &str,const MqlTradeRequest &request,const MqlTradeResult &result) const
  {
//--- set up
   string symbol_name=(request.symbol==NULL) ? _Symbol : request.symbol;
   int    digits=_Digits;
   long   tmp_long;
   ENUM_SYMBOL_TRADE_EXECUTION trade_execution=0;
   if(SymbolInfoInteger(symbol_name,SYMBOL_DIGITS,tmp_long))
      digits=(int)tmp_long;
   if(SymbolInfoInteger(symbol_name,SYMBOL_TRADE_EXEMODE,tmp_long))
      trade_execution=(ENUM_SYMBOL_TRADE_EXECUTION)tmp_long;
//--- see the response code
   switch(result.retcode)
     {
      case TRADE_RETCODE_REQUOTE:
         str=StringFormat("requote (%s/%s)",
                          DoubleToString(result.bid,digits),
                          DoubleToString(result.ask,digits));
         break;

      case TRADE_RETCODE_DONE:
         if(request.action==TRADE_ACTION_DEAL &&
            (trade_execution==SYMBOL_TRADE_EXECUTION_REQUEST ||
             trade_execution==SYMBOL_TRADE_EXECUTION_INSTANT ||
             trade_execution==SYMBOL_TRADE_EXECUTION_MARKET))
            str=StringFormat("done at %s",DoubleToString(result.price,digits));
         else
            str="done";
         break;

      case TRADE_RETCODE_DONE_PARTIAL:
         if(request.action==TRADE_ACTION_DEAL &&
            (trade_execution==SYMBOL_TRADE_EXECUTION_REQUEST ||
             trade_execution==SYMBOL_TRADE_EXECUTION_INSTANT ||
             trade_execution==SYMBOL_TRADE_EXECUTION_MARKET))
            str=StringFormat("done partially %s at %s",
                             DoubleToString(result.volume,2),
                             DoubleToString(result.price,digits));
         else
            str=StringFormat("done partially %s",
                             DoubleToString(result.volume,2));
         break;

      case TRADE_RETCODE_REJECT:
         str="rejected";
         break;
      case TRADE_RETCODE_CANCEL:
         str="canceled";
         break;
      case TRADE_RETCODE_PLACED:
         str="placed";
         break;
      case TRADE_RETCODE_ERROR:
         str="common error";
         break;
      case TRADE_RETCODE_TIMEOUT:
         str="timeout";
         break;
      case TRADE_RETCODE_INVALID:
         str="invalid request";
         break;
      case TRADE_RETCODE_INVALID_VOLUME:
         str="invalid volume";
         break;
      case TRADE_RETCODE_INVALID_PRICE:
         str="invalid price";
         break;
      case TRADE_RETCODE_INVALID_STOPS:
         str="invalid stops";
         break;
      case TRADE_RETCODE_TRADE_DISABLED:
         str="trade disabled";
         break;
      case TRADE_RETCODE_MARKET_CLOSED:
         str="market closed";
         break;
      case TRADE_RETCODE_NO_MONEY:
         str="not enough money";
         break;
      case TRADE_RETCODE_PRICE_CHANGED:
         str="price changed";
         break;
      case TRADE_RETCODE_PRICE_OFF:
         str="off quotes";
         break;
      case TRADE_RETCODE_INVALID_EXPIRATION:
         str="invalid expiration";
         break;
      case TRADE_RETCODE_ORDER_CHANGED:
         str="order changed";
         break;
      case TRADE_RETCODE_TOO_MANY_REQUESTS:
         str="too many requests";
         break;
      case TRADE_RETCODE_NO_CHANGES:
         str="no changes";
         break;
      case TRADE_RETCODE_SERVER_DISABLES_AT:
         str="auto trading disabled by server";
         break;
      case TRADE_RETCODE_CLIENT_DISABLES_AT:
         str="auto trading disabled by client";
         break;
      case TRADE_RETCODE_LOCKED:
         str="locked";
         break;
      case TRADE_RETCODE_FROZEN:
         str="frozen";
         break;
      case TRADE_RETCODE_INVALID_FILL:
         str="invalid fill";
         break;
      case TRADE_RETCODE_CONNECTION:
         str="no connection";
         break;
      case TRADE_RETCODE_ONLY_REAL:
         str="only real";
         break;
      case TRADE_RETCODE_LIMIT_ORDERS:
         str="limit orders";
         break;
      case TRADE_RETCODE_LIMIT_VOLUME:
         str="limit volume";
         break;
      case TRADE_RETCODE_POSITION_CLOSED:
         str="position closed";
         break;
      case TRADE_RETCODE_INVALID_ORDER:
         str="invalid order";
         break;
      case TRADE_RETCODE_CLOSE_ORDER_EXIST:
         str="close order already exists";
         break;
      case TRADE_RETCODE_LIMIT_POSITIONS:
         str="limit positions";
         break;
      default:
         str="unknown retcode "+(string)result.retcode;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double CTrade::CheckVolume(const string symbol,double volume,double price,ENUM_ORDER_TYPE order_type)
  {
//--- check
   if(order_type!=ORDER_TYPE_BUY && order_type!=ORDER_TYPE_SELL)
      return(0.0);
   double free_margin=AccountInfoDouble(ENUM_ACCOUNT_INFO_DOUBLE::ACCOUNT_MARGIN_FREE);
   if(free_margin<=0.0)
      return(0.0);
//--- clean
   ClearStructures();
//--- setting request
   m_request.action=TRADE_ACTION_DEAL;
   m_request.symbol=symbol;
   m_request.volume=volume;
   m_request.type  =order_type;
   m_request.price =price;
//--- action and return the result
   if(!::OrderCheck(m_request,m_check_result) && m_check_result.margin_free<0.0)
     {
      double coeff=free_margin/(free_margin-m_check_result.margin_free);
      double lots=NormalizeDouble(volume*coeff,2);
      if(lots<volume)
        {
         //--- normalize and check limits
         double stepvol=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
         if(stepvol>0.0)
            volume=stepvol*(MathFloor(lots/stepvol)-1);
         //---
         double minvol=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
         if(volume<minvol)
            volume=0.0;
        }
     }
   return(volume);
  }
//+------------------------------------------------------------------+
//| Checks if the m_request structure is filled correctly            |
//+------------------------------------------------------------------+
bool CTrade::OrderCheck(const MqlTradeRequest &request,MqlTradeCheckResult &check_result)
  {
//--- action and return the result
   return(::OrderCheck(request,check_result));
  }
//+------------------------------------------------------------------+
//| Set order filling type according to symbol filling mode          |
//+------------------------------------------------------------------+
bool CTrade::SetTypeFillingBySymbol(const string symbol)
  {
//--- get possible filling policy types by symbol
   uint filling=(uint)SymbolInfoInteger(symbol,SYMBOL_FILLING_MODE);
   if((filling&SYMBOL_FILLING_FOK)==SYMBOL_FILLING_FOK)
     {
      m_type_filling=ORDER_FILLING_FOK;
      return(true);
     }
   if((filling&SYMBOL_FILLING_IOC)==SYMBOL_FILLING_IOC)
     {
      m_type_filling=ORDER_FILLING_IOC;
      return(true);
     }
//---
   return(false);
  }
//+------------------------------------------------------------------+
//| Checks and corrects type of filling policy                       |
//+------------------------------------------------------------------+
bool CTrade::FillingCheck(const string symbol)
  {
//--- get execution mode of orders by symbol
   ENUM_SYMBOL_TRADE_EXECUTION exec=(ENUM_SYMBOL_TRADE_EXECUTION)SymbolInfoInteger(symbol,SYMBOL_TRADE_EXEMODE);
//--- check execution mode
   if(exec==SYMBOL_TRADE_EXECUTION_REQUEST || exec==SYMBOL_TRADE_EXECUTION_INSTANT)
     {
      //--- neccessary filling type will be placed automatically
      return(true);
     }
//--- get possible filling policy types by symbol
   uint filling=(uint)SymbolInfoInteger(symbol,SYMBOL_FILLING_MODE);
//--- check execution mode again
   if(exec==SYMBOL_TRADE_EXECUTION_MARKET)
     {
      //--- for the MARKET execution mode
      //--- analyze order
      if(m_request.action!=TRADE_ACTION_PENDING)
        {
         //--- in case of instant execution order
         //--- if the required filling policy is supported, add it to the request
         if((filling&SYMBOL_FILLING_FOK)==SYMBOL_FILLING_FOK)
           {
            m_type_filling=ORDER_FILLING_FOK;
            m_request.type_filling=m_type_filling;
            return(true);
           }
         if((filling&SYMBOL_FILLING_IOC)==SYMBOL_FILLING_IOC)
           {
            m_type_filling=ORDER_FILLING_IOC;
            m_request.type_filling=m_type_filling;
            return(true);
           }
         //--- wrong filling policy, set error code
         m_result.retcode=TRADE_RETCODE_INVALID_FILL;
         return(false);
        }
      return(true);
     }
//--- EXCHANGE execution mode
   switch(m_type_filling)
     {
      case ORDER_FILLING_FOK:
         //--- analyze order
         if(m_request.action==TRADE_ACTION_PENDING)
           {
            //--- in case of pending order
            //--- add the expiration mode to the request
            if(!ExpirationCheck(symbol))
               m_request.type_time=ORDER_TIME_DAY;
            //--- stop order?
            if(m_request.type==ORDER_TYPE_BUY_STOP || m_request.type==ORDER_TYPE_SELL_STOP ||
               m_request.type==ORDER_TYPE_BUY_LIMIT || m_request.type==ORDER_TYPE_SELL_LIMIT)
              {
               //--- in case of stop order
               //--- add the corresponding filling policy to the request
               m_request.type_filling=ORDER_FILLING_RETURN;
               return(true);
              }
           }
         //--- in case of limit order or instant execution order
         //--- if the required filling policy is supported, add it to the request
         if((filling&SYMBOL_FILLING_FOK)==SYMBOL_FILLING_FOK)
           {
            m_request.type_filling=m_type_filling;
            return(true);
           }
         //--- wrong filling policy, set error code
         m_result.retcode=TRADE_RETCODE_INVALID_FILL;
         return(false);
      case ORDER_FILLING_IOC:
         //--- analyze order
         if(m_request.action==TRADE_ACTION_PENDING)
           {
            //--- in case of pending order
            //--- add the expiration mode to the request
            if(!ExpirationCheck(symbol))
               m_request.type_time=ORDER_TIME_DAY;
            //--- stop order?
            if(m_request.type==ORDER_TYPE_BUY_STOP || m_request.type==ORDER_TYPE_SELL_STOP ||
               m_request.type==ORDER_TYPE_BUY_LIMIT || m_request.type==ORDER_TYPE_SELL_LIMIT)
              {
               //--- in case of stop order
               //--- add the corresponding filling policy to the request
               m_request.type_filling=ORDER_FILLING_RETURN;
               return(true);
              }
           }
         //--- in case of limit order or instant execution order
         //--- if the required filling policy is supported, add it to the request
         if((filling&SYMBOL_FILLING_IOC)==SYMBOL_FILLING_IOC)
           {
            m_request.type_filling=m_type_filling;
            return(true);
           }
         //--- wrong filling policy, set error code
         m_result.retcode=TRADE_RETCODE_INVALID_FILL;
         return(false);
      case ORDER_FILLING_RETURN:
         //--- add filling policy to the request
         m_request.type_filling=m_type_filling;
         return(true);
     }
//--- unknown execution mode, set error code
   m_result.retcode=TRADE_RETCODE_ERROR;
   return(false);
  }
//+------------------------------------------------------------------+
//| Check expiration type of pending order                           |
//+------------------------------------------------------------------+
bool CTrade::ExpirationCheck(const string symbol)
  {
//--- check symbol
   string symbol_name=(symbol==NULL) ? _Symbol : symbol;
//--- get flags
   long tmp_long;
   int  flags=0;
   if(SymbolInfoInteger(symbol_name,SYMBOL_EXPIRATION_MODE,tmp_long))
      flags=(int)tmp_long;
//--- check type
   switch(m_request.type_time)
     {
      case ORDER_TIME_GTC:
         if((flags&SYMBOL_EXPIRATION_GTC)!=0)
            return(true);
         break;
      case ORDER_TIME_DAY:
         if((flags&SYMBOL_EXPIRATION_DAY)!=0)
            return(true);
         break;
      case ORDER_TIME_SPECIFIED:
         if((flags&SYMBOL_EXPIRATION_SPECIFIED)!=0)
            return(true);
         break;
      case ORDER_TIME_SPECIFIED_DAY:
         if((flags&SYMBOL_EXPIRATION_SPECIFIED_DAY)!=0)
            return(true);
         break;
      default:
         Print(__FUNCTION__+": Unknown expiration type");
     }
//--- failed
   return(false);
  }
//+------------------------------------------------------------------+
//| Checks order                                                     |
//+------------------------------------------------------------------+
bool CTrade::OrderTypeCheck(const string symbol)
  {
   bool res=false;
//--- check symbol
   string symbol_name=(symbol==NULL) ? _Symbol : symbol;
//--- get flags of allowed trade orders
   long tmp_long;
   int  flags=0;
   if(SymbolInfoInteger(symbol_name,SYMBOL_ORDER_MODE,tmp_long))
      flags=(int)tmp_long;
//--- depending on the type of order in request
   switch(m_request.type)
     {
      case ORDER_TYPE_BUY:
      case ORDER_TYPE_SELL:
         //--- check possibility of execution
         res=((flags&SYMBOL_ORDER_MARKET)!=0);
         break;
      case ORDER_TYPE_BUY_LIMIT:
      case ORDER_TYPE_SELL_LIMIT:
         //--- check possibility of execution
         res=((flags&SYMBOL_ORDER_LIMIT)!=0);
         break;
      case ORDER_TYPE_BUY_STOP:
      case ORDER_TYPE_SELL_STOP:
         //--- check possibility of execution
         res=((flags&SYMBOL_ORDER_STOP)!=0);
         break;
      case ORDER_TYPE_BUY_STOP_LIMIT:
      case ORDER_TYPE_SELL_STOP_LIMIT:
         //--- check possibility of execution
         res=((flags&SYMBOL_ORDER_STOP_LIMIT)!=0);
         break;
     }
//--- check res
   if(res)
     {
      //--- trading order is valid
      //--- check if we need and able to set protective orders
      if(m_request.sl!=0.0 || m_request.tp!=0.0)
        {
         if((flags&SYMBOL_ORDER_SL)==0)
            m_request.sl=0.0;
         if((flags&SYMBOL_ORDER_TP)==0)
            m_request.tp=0.0;
        }
     }
   else
     {
      //--- trading order is not valid
      //--- set error
      m_result.retcode=TRADE_RETCODE_INVALID_ORDER;
      Print(__FUNCTION__+": Invalid order type");
     }
//--- result
   return(res);
  }
//+------------------------------------------------------------------+
//| Send order                                                       |
//+------------------------------------------------------------------+
bool CTrade::OrderSend(const MqlTradeRequest &request,MqlTradeResult &result)
  {
   bool   res;
   string action="";
   string fmt   ="";
//--- action
   if(m_async_mode)
      res=StrategyOrderSend(request,result,true);
   else
      res=StrategyOrderSend(request,result,false);
//--- check
   if(res)
     {
      if(m_log_level>LOG_LEVEL_ERRORS)
         PrintFormat(__FUNCTION__+": %s [%s]",FormatRequest(action,request),FormatRequestResult(fmt,request,result));
     }
   else
     {
      if(m_log_level>LOG_LEVEL_NO)
         PrintFormat(__FUNCTION__+": %s [%s]",FormatRequest(action,request),FormatRequestResult(fmt,request,result));
     }
//--- return the result
   return(res);
  }
//+------------------------------------------------------------------+
//| Position select depending on netting or hedging                  |
//+------------------------------------------------------------------+
bool CTrade::SelectPosition(const string symbol)
  {
   bool res=false;
//---
   if(IsHedging())
     {
      uint total=PositionsTotal();
      for(uint i=0; i<total; i++)
        {
         string position_symbol=PositionGetSymbol(i);
         if(position_symbol==symbol && m_magic==PositionGetInteger(POSITION_MAGIC))
           {
            res=true;
            break;
           }
        }
     }
   else
      res=PositionSelect(symbol);
//---
   return(res);
  }
//+------------------------------------------------------------------+

// END EMBEDDED SDK: Trade/Trade.mqh

#ifndef TT_STRATEGY_ENGINE
#define TT_STRATEGY_ENGINE

enum TTModel
{
   T1_OnePercentDrop=1,           // T1 - Mon <= -1% vs Fri; exit Tue close
   T2_BearishLowIBS=2,            // T2 - Bearish Mon, IBS < 0.20; exit Tue close
   T3_WeakMondayFourSessions=3,   // T3 - Mon < Fri, IBS < 0.50; exit fourth close
   T4_WeakMondayAdaptiveExit=4    // T4 - same entry; close > prior high or fourth close
};
enum TTRiskMode
{
   Fixed_Lots=0,       // Fixed lots
   Cash_Risk_Budget=1  // Cash risk budget
};
enum TTNewsImpact
{
   News_Off=0,
   News_Red_Only=1,
   News_Red_Yellow=2,
   News_All=3
};
enum TTNewsWindow
{
   News_Custom=0,
   News_5_Minutes=5,
   News_10_Minutes=10,
   News_14_Minutes=14,
   News_20_Minutes=20
};

input group "==========  1 - Strategy  =========="
input bool       EnableTrading=true;
input TTModel    Model=T1_OnePercentDrop; // research candidates: NQ/MNQ T1; ES/MES T4 (manual selection)
input string     AssetRoot="AUTO"; // AUTO, ES, NQ, MES or MNQ

input group " "
input group "==========  2 - Risk  =========="
input TTRiskMode Sizing=Fixed_Lots;
input double     FixedVolume=1.0;
input double     RiskMoney=500.0;
input double     CostPerContract=0.0; // legacy total-cost override; 0 learns commission then adds slippage
input double     AssumedSlippageTicksPerSide=1.0;

input group "  "
input group "==========  3 - Exit  =========="
input bool       EnableFixedSelfClose=false;
input int        FixedSelfCloseHHMMSS=164455; // New York time
input int        BaseCloseHHMMSS=165955;       // executable proxy before 17:00 New York

input group "   "
input group "==========  4 - News  =========="
input bool       EnableNewsFilter=true;
input TTNewsImpact NewsImpact=News_Red_Only;
input TTNewsWindow NewsWindow=News_10_Minutes;
input double     CustomNewsMinutesBefore=5.0;
input double     CustomNewsMinutesAfter=5.0;
input string     NewsCurrencies="USD";
input bool       CancelPendingAtBlackout=true;
input bool       FreezeTrailingDuringNews=true;
input bool       FlattenAtBlackout=false;
input bool       MoveToCostCoveredBEAtBlackout=true;
input string     HistoricalNewsCsv=""; // Common Files CSV for tester: UTC time,currency,impact,title

input group "    "
input group "==========  5 - Display & Audit  =========="
input bool       ShowVisuals=true;
input bool       WriteAuditLog=false;
input ulong      MagicBase=91008010; // effective magic = base + model; use another base for duplicate instances

ulong Magic=0;
const string TTName="Tuesday Turnaround";
CTrade trade;

struct TTDailyBar { datetime day; double open,high,low,close; };
TTDailyBar ttFriday,ttMonday;
datetime ttCurrentD1=0,ttEntryTime=0,ttMondayDay=0;
double ttStop=0,ttEntry=0,ttInitialRisk=0;
int ttHeldSessions=0;
bool ttArmed=false,ttBreakEven=false,ttNewsBlocked=false,ttFlattenRequested=false,ttMondaySignalConsumed=false;
string ttStatus="Starting";
int ttAudit=INVALID_HANDLE;

// RBE/Vault clock: live server/GMT calibration; tester/historical weekly-opening anchor.
const int TT_CLOCK_UNKNOWN=100000;
int ttClockServerNY=0;
bool ttClockReady=false;
datetime ttClockObserved=0;
datetime ttClockWeeks[];
int ttClockWeekOffsets[];
int TTNthSunday(int year,int month,int nth)
{
   MqlDateTime d={};d.year=year;d.mon=month;d.day=1;datetime first=StructToTime(d);TimeToStruct(first,d);
   return 1+((7-d.day_of_week)%7)+7*(nth-1);
}
// Server offset in whole hours at this UTC instant, from the resolved standard clock. Was a
// hard-coded 3/2 US-DST table; any broker, any rule, and a dated schedule all work now.
int TTExpectedBrokerUTC(datetime utc)
{
   // Before the adapter resolves (OnInit self-tests, a chart with no history yet) answer with the
   // US rule the strategy was written against; the resolved clock takes over from the first tick.
   if(!ClkOK()) return ClkNyUtcOffset(utc)==-4*3600 ? 3 : 2;
   return (int)(((long)ClkUtcToServer(utc,ClkRule(),ClkBase())-(long)utc)/3600);
}
// Seconds the server clock is ahead of New York at this stamp: the standard adapter owns the
// server -> UTC mapping, so this is the only clock decision left in the EA.
int TTServerNYOffsetSec(datetime stamp)
{
   if(!ClkOK()) return CLOCK_UNKNOWN;
   datetime utc=ClkStampToUtc(stamp);
   if(utc<=0) return CLOCK_UNKNOWN;
   return (int)((long)stamp-(long)ClkUtcToNy(utc));
}
bool TTClockRefresh(datetime stamp)
{
   ClkRefresh(stamp);
   bool ready=ClkOK();
   int offset=ready ? TTServerNYOffsetSec(stamp) : CLOCK_UNKNOWN;
   if(offset==CLOCK_UNKNOWN) ready=false;
   bool announce=!ttClockReady || offset!=ttClockServerNY;
   ttClockReady=ready;
   if(!ready) return false;
   if(announce) PrintFormat("TT_CLOCK_READY serverAheadOfNYMinutes=%d source=%s",offset/60,ClkSource());
   ttClockServerNY=offset;ttClockObserved=stamp;return true;
}
datetime TTNewYorkAtOffset(datetime server,int offset){return server-offset;}
datetime TTNewYork(datetime server){int offset=TTServerNYOffsetSec(server);return offset==TT_CLOCK_UNKNOWN?0:TTNewYorkAtOffset(server,offset);}
datetime TTClockUTC(datetime server){return ClkStampToUtc(server);}
int TTClock(datetime ny){MqlDateTime p;TimeToStruct(ny,p);return p.hour*10000+p.min*100+p.sec;}
datetime TTDate(datetime t){MqlDateTime p;TimeToStruct(t,p);p.hour=0;p.min=0;p.sec=0;return StructToTime(p);}
int TTWeekday(datetime t){MqlDateTime p;TimeToStruct(t,p);return p.day_of_week;}
bool TTValidClock(int hhmmss)
{
   int h=hhmmss/10000,m=(hhmmss/100)%100,s=hhmmss%100;
   return h>=0&&h<18&&m>=0&&m<60&&s>=0&&s<60;
}
bool TTIsPrecedingFriday(datetime friday,datetime monday)
{
   // Compare calendar dates, not raw source timestamps; D1 feeds can stamp bars with non-midnight seconds.
   datetime f=TTDate(friday),m=TTDate(monday);
   return TTWeekday(f)==5&&TTWeekday(m)==1&&TimeToString(f,TIME_DATE)==TimeToString(m-3*86400,TIME_DATE);
}

double TTIBS(TTDailyBar &b){double r=b.high-b.low;return r>0 ? (b.close-b.low)/r : -1;}
string TTModelLabel()
{
   if(Model==T1_OnePercentDrop)return "T1 - 1% Monday Drop";
   if(Model==T2_BearishLowIBS)return "T2 - Bearish + IBS < 0.20";
   if(Model==T3_WeakMondayFourSessions)return "T3 - Weak Monday / 4 Sessions";
   return "T4 - Weak Monday / Adaptive Exit";
}
string TTSizingLabel(){return Sizing==Fixed_Lots?StringFormat("Fixed %.2f lots",FixedVolume):StringFormat("Cash risk %.2f",RiskMoney);}
bool TTSignal(TTModel model,TTDailyBar &friday,TTDailyBar &monday)
{
   if(TTWeekday(monday.day)!=1 || !TTIsPrecedingFriday(friday.day,monday.day)) return false;
   double ibs=TTIBS(monday);
   if(model==T1_OnePercentDrop) return monday.close<=.99*friday.close;
   if(model==T2_BearishLowIBS) return monday.close<monday.open && ibs<.20;
   return monday.close<friday.close && ibs<.50;
}
string TTRoot()
{
   string r=AssetRoot;StringToUpper(r);if(r!="AUTO") return r;
   string s=_Symbol;StringToUpper(s);
   if(StringFind(s,"MNQ")>=0) return "MNQ";
   if(StringFind(s,"MES")>=0) return "MES";
   if(StringFind(s,"NQ")>=0 || StringFind(s,"USTEC")>=0 || StringFind(s,"NAS")>=0) return "NQ";
   if(StringFind(s,"ES")>=0 || StringFind(s,"US500")>=0 || StringFind(s,"SPX")>=0) return "ES";
   return "";
}
double TTFallbackCommission()
{
   string r=TTRoot();
   if(r=="MES"||r=="MNQ")return 1.82;
   if(r=="ES"||r=="NQ")return 5.76;
   return 0;
}
double TTCommissionEstimate()
{
   datetime to=TimeTradeServer(),from=to-180*86400;if(to<=0||!HistorySelect(from,to))return TTFallbackCommission();
   double charges=0,entryLots=0;
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong ticket=HistoryDealGetTicket(i);if(ticket==0)continue;
      if(HistoryDealGetString(ticket,DEAL_SYMBOL)!=_Symbol||(ulong)HistoryDealGetInteger(ticket,DEAL_MAGIC)!=Magic)continue;
      charges+=MathAbs(HistoryDealGetDouble(ticket,DEAL_COMMISSION))+MathAbs(HistoryDealGetDouble(ticket,DEAL_FEE));
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket,DEAL_ENTRY)==DEAL_ENTRY_IN)entryLots+=HistoryDealGetDouble(ticket,DEAL_VOLUME);
   }
   return entryLots>0&&charges>0?charges/entryLots:TTFallbackCommission();
}
double TTModeledCost(double commission,double tickCash,double slipTicksPerSide)
{return commission+2.0*MathMax(0.0,slipTicksPerSide)*MathMax(0.0,tickCash);}
double TTCost()
{
   if(CostPerContract>0)return CostPerContract;
   MqlTick q;double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE),cash=0;
   if(!SymbolInfoTick(_Symbol,q)||tick<=0||!OrderCalcProfit(ORDER_TYPE_BUY,_Symbol,1.0,q.ask,q.ask+tick,cash))cash=0;
   return TTModeledCost(TTCommissionEstimate(),MathAbs(cash),AssumedSlippageTicksPerSide);
}
double TTRoundDown(double p){double t=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);return NormalizeDouble(MathFloor(p/t+1e-9)*t,_Digits);}
double TTRoundUp(double p){double t=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);return NormalizeDouble(MathCeil(p/t-1e-9)*t,_Digits);}
double TTStopPrice(TTDailyBar &monday)
{
   string r=TTRoot();double range=monday.high-monday.low,tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double k=r=="MNQ"?.75:(r=="ES" || r=="MES")?.50:0;
   return TTRoundDown(k>0 ? monday.low-k*range : monday.low-tick);
}
bool TTUsesBE(){return TTRoot()=="NQ";}
bool TTFixedCloseDue(datetime server)
{
   if(!EnableFixedSelfClose) return false;
   datetime ny=TTNewYork(server);int clock=TTClock(ny);
   return clock>=FixedSelfCloseHHMMSS && clock<180000;
}
bool TTBaseCloseDue(datetime server)
{
   int clock=TTClock(TTNewYork(server));
   if(clock<BaseCloseHHMMSS || clock>=180000) return false;
   if(Model==T1_OnePercentDrop || Model==T2_BearishLowIBS) return ttHeldSessions==0;
   return ttHeldSessions>=3;
}
bool TTClockSelfTest()
{
   return TTNewYorkAtOffset(D'2022.01.24 08:00',7*3600)==D'2022.01.24 01:00'
      && (int)(((long)ClkUtcToServer(D'2026.03.08 06:59:59',CLK_RULE_US,120)-(long)D'2026.03.08 06:59:59')/3600)==2
      && (int)(((long)ClkUtcToServer(D'2026.03.08 07:00:00',CLK_RULE_US,120)-(long)D'2026.03.08 07:00:00')/3600)==3
      && (int)(((long)ClkUtcToServer(D'2026.11.01 05:59:59',CLK_RULE_US,120)-(long)D'2026.11.01 05:59:59')/3600)==3
      && (int)(((long)ClkUtcToServer(D'2026.11.01 06:00:00',CLK_RULE_US,120)-(long)D'2026.11.01 06:00:00')/3600)==2;
}
bool TTModelSelfTest()
{
   TTDailyBar f={D'2023.01.27',4100,4110,4070,4084};
   TTDailyBar m={D'2023.01.30',4077,4086,4029.5,4039.75};
   double r=m.high-m.low;
   return TTSignal(T1_OnePercentDrop,f,m) && TTSignal(T2_BearishLowIBS,f,m) && TTSignal(T3_WeakMondayFourSessions,f,m)
      && MathAbs((m.low-.5*r)-4001.25)<1e-8
      && MathAbs((m.low-.75*r)-3987.125)<1e-8
      && MathAbs((m.low-.25)-4029.25)<1e-8
      && MathAbs(TTModeledCost(5.76,5.0,1.0)-15.76)<1e-8
      && TTClockSelfTest();
}
bool TTReadD1(int shift,TTDailyBar &b)
{
   MqlRates x[];ArraySetAsSeries(x,true);
   if(CopyRates(_Symbol,PERIOD_D1,shift,1,x)!=1) return false;
   b.day=TTDate(x[0].time);b.open=x[0].open;b.high=x[0].high;b.low=x[0].low;b.close=x[0].close;return true;
}

#include "ExecutionRuntime.mqh"
#include "ChartVisuals.mqh"

void TTProcessCompletedDay(datetime now,int shift=1,bool allowEntry=true)
{
   TTDailyBar closed,prior;if(!TTReadD1(shift,closed)) return;
   if(TTOwnPosition())
   {
      int entryShift=iBarShift(_Symbol,PERIOD_D1,ttEntryTime,false);
      if(entryShift<shift){TTRecoveryBlocked=true;ttStatus="Entry daily history missing; management blocked";return;}
      ttHeldSessions=MathMax(ttHeldSessions,entryShift-shift+1);
      TTStateSave();
      if(Model==T4_WeakMondayAdaptiveExit && TTReadD1(shift+1,prior) && closed.close>prior.high && ttHeldSessions<4)
         TTCloseOwned("CLOSE_GT_PRIOR_HIGH");
      return; // A subsequent Monday never replaces the geometry of an unresolved trade.
   }
   if(TTRecoveryBlocked||TTWeekday(closed.day)!=1 || !TTReadD1(shift+1,prior)) return;
   if(closed.day==ttMondayDay&&ttMondaySignalConsumed)return;
   ObjectDelete(0,TTPrefix()+"Preview");
   ttFriday=prior;ttMonday=closed;ttMondayDay=closed.day;
   bool signal=TTSignal(Model,prior,closed);
   TTAudit(signal?"SIGNAL":"REJECT",signal?"RULE_MET":"RULE_NOT_MET",closed.close);
   ttMondaySignalConsumed=!allowEntry;ttArmed=signal && allowEntry && !TTOwnPosition();ttStop=TTStopPrice(closed);ttHeldSessions=0;TTStateSave();
   if(!signal){TTCancelOwnedOrders("MONDAY_REJECT");ttStatus="Monday rejected";return;}
   ttStatus="Signal armed for Tuesday open";
   if(allowEntry && EnableTrading && !TTNewsBlackout(now)) TTOpenLong();
   else if(TTNewsBlackout(now)){ttArmed=false;ttMondaySignalConsumed=true;TTStateSave();TTCancelOwnedOrders("NEWS_AT_ENTRY");ttStatus="Signal consumed by news; no refill";}
}
void TTReplayCompletedDays(datetime now)
{
   datetime current=iTime(_Symbol,PERIOD_D1,0);if(current<=0)return;
   if(ttCurrentD1==0){ttCurrentD1=current;TTStateSave();return;}
   if(current==ttCurrentD1)return;
   int missed=iBarShift(_Symbol,PERIOD_D1,ttCurrentD1,true);
   if(missed<1){TTRecoveryBlocked=true;ttStatus="Missing daily recovery history; entries blocked";return;}
   for(int shift=missed;shift>=1;shift--)
   {
      TTProcessCompletedDay(now,shift,missed==1&&now-current<=60);
      ttCurrentD1=iTime(_Symbol,PERIOD_D1,shift-1);TTStateSave();
   }
}
void TTManage(datetime now)
{
   if(!TTTradeConnectionReady()){ttStatus="Disconnected; management pending";return;}
   if(TTRecoveryBlocked)return;
   if(now!=ttLastReconcile){ttLastReconcile=now;TTReconcileOwned();}
   if(TTRecoveryBlocked||ttRecoveryPending)return;
   TTReplayCompletedDays(now);
   if(TTRecoveryBlocked)return;
   bool blocked=TTNewsBlackout(now);
   bool selectedPreEvent=blocked&&ttNewsActive!=""&&ttNewsPreEvent;
   if(blocked && !ttNewsBlocked)
   {
      int newsBefore=0,newsAfter=0;TTNewsWindowSeconds(newsBefore,newsAfter);
      if(CancelPendingAtBlackout){ttCancelBlackout=true;ttCancelGuardUntil=now+newsBefore+newsAfter+60;if(ttArmed){ttArmed=false;ttMondaySignalConsumed=true;}TTStateSave();TTCancelOwnedOrders("NEWS_BLACKOUT");}
      ttNewsBlocked=true;
      TTAudit("NEWS_START",TTNewsSummary(),0);
   }
   if(!blocked && ttNewsBlocked) TTAudit("NEWS_END","RESUME",0);
   if(!blocked&&ttCancelBlackout&&now>ttCancelGuardUntil&&!TTOwnPosition()&&OrdersTotal()==0)ttCancelBlackout=false;
   ttNewsBlocked=blocked;
   if(!TTOwnPosition()) return;
   if(ttFlattenRequested){TTCloseOwned("RECOVERY_DEFERRED_EXIT");return;}
   // Position actions require a real selected event and only run before its release.
   // Missing calendar data remains fail-closed for entries/cancellation but never moves or flattens a position.
   if(selectedPreEvent && FlattenAtBlackout){ttFlattenRequested=true;TTCloseOwned("NEWS_BLACKOUT");return;}
   if(selectedPreEvent && MoveToCostCoveredBEAtBlackout && !ttBreakEven && PositionSelectByTicket(TTOwnPositionTicket()))
   {
      double unit=TTMoneyPerPriceUnit();
      if(unit>0)
      {
         double be=TTRoundUp(PositionGetDouble(POSITION_PRICE_OPEN)+TTCost()/unit);
         if(TTModifyOwnedStop(be)){ttBreakEven=true;TTStateSave();TTAudit("STOP_MOVE","NEWS_COST_BE",be);}
      }
   }
    if(TTFixedCloseDue(now)||(EnableFixedSelfClose&&ttHeldSessions>=1)){TTCloseOwned("FIXED_SELF_CLOSE");return;}
   if(TTBaseCloseDue(now)){TTCloseOwned((Model==T1_OnePercentDrop||Model==T2_BearishLowIBS)?"FIRST_SESSION_CLOSE":"FOURTH_SESSION_CLOSE");return;}
   // Recovery only: if the terminal missed the intended closing clock, close on the next quote.
   if((Model==T1_OnePercentDrop || Model==T2_BearishLowIBS) && ttHeldSessions>=1){TTCloseOwned("FIRST_SESSION_CLOSE");return;}
   if((Model==T3_WeakMondayFourSessions || Model==T4_WeakMondayAdaptiveExit) && ttHeldSessions>=4){TTCloseOwned("FOURTH_SESSION_CLOSE");return;}
   if(TTUsesBE() && !ttBreakEven && !(blocked && FreezeTrailingDuringNews))
   {
      MqlTick q;if(SymbolInfoTick(_Symbol,q) && q.bid>=ttEntry+1.5*ttInitialRisk)
      {
         double be=TTRoundUp(ttEntry+TTCost()/TTMoneyPerPriceUnit());
         if(TTModifyOwnedStop(be)){ttBreakEven=true;TTStateSave();TTAudit("STOP_MOVE","NQ_BE_1.5R",be);}
      }
   }
}
int OnInit()
{
   { int clockInit=ClkInit(); if(clockInit!=INIT_SUCCEEDED) return clockInit; }
   ClkRefresh(ClkNowServer());   // resolve before any self-test, panel or session read
   Magic=MagicBase+(ulong)Model;
   if(!StrategyLeaseAcquire(Magic))return INIT_FAILED;
   if(!TTModelSelfTest()||!TTNewsSelfTest()){Print("TT_SELFTEST_FAILED");return INIT_FAILED;}
   if(TTRoot()=="" || MagicBase==0 || FixedVolume<=0 || RiskMoney<=0 || AssumedSlippageTicksPerSide<0 || CustomNewsMinutesBefore<0 || CustomNewsMinutesAfter<0)
      return INIT_PARAMETERS_INCORRECT;
   if(!TTValidClock(FixedSelfCloseHHMMSS)||!TTValidClock(BaseCloseHHMMSS)) return INIT_PARAMETERS_INCORRECT;
   trade.SetExpertMagicNumber(Magic);trade.SetTypeFillingBySymbol(_Symbol);trade.SetAsyncMode(false);
   ttCurrentD1=iTime(_Symbol,PERIOD_D1,0);
   TTInitAudit();TTNewsInit();TTStateRestore();TTRecoverOwned();TTInitVisuals();EventSetTimer(1);
   if(!TTRecoveryBlocked&&!TTOwnPosition())ttStatus="Live; waiting for fresh completed Monday";Print("TT_SELFTEST_PASS");return INIT_SUCCEEDED;
}
void OnTick()
{
   datetime now=TimeTradeServer();
   if(!TTClockRefresh(now)){ttStatus="Waiting for automatic NY clock history";TTUpdateVisuals(now);return;}
   if(!TTTradeConnectionReady()){ttStatus="Disconnected; daily boundary pending";TTUpdateVisuals(now);return;}
   TTManage(now);TTUpdateVisuals(now);
}
void OnTimer(){datetime now=TimeTradeServer();TTNewsRefresh(now);if(TTClockRefresh(now))TTManage(now);else ttStatus="Waiting for automatic NY clock history";TTUpdateVisuals(now);}
void OnTradeTransaction(const MqlTradeTransaction &tx,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   if(tx.type!=TRADE_TRANSACTION_DEAL_ADD || !HistoryDealSelect(tx.deal)) return;
   if((ulong)HistoryDealGetInteger(tx.deal,DEAL_MAGIC)!=Magic || HistoryDealGetString(tx.deal,DEAL_SYMBOL)!=_Symbol) return;
   long e=HistoryDealGetInteger(tx.deal,DEAL_ENTRY);
   if(e==DEAL_ENTRY_IN)
   {
      if(ttPositionId==0)
      {
         ttPositionId=(ulong)HistoryDealGetInteger(tx.deal,DEAL_POSITION_ID);
         ttEntry=HistoryDealGetDouble(tx.deal,DEAL_PRICE);ttEntryTime=(datetime)HistoryDealGetInteger(tx.deal,DEAL_TIME);
         ttInitialRisk=ttEntry-ttOriginalStop;ttBreakEven=false;
      }
      TTStateSave();
      // A fill can arrive after a cancel request because the server serializes two already-in-flight requests.
      if(ttCancelBlackout){ttFlattenRequested=true;TTCloseOwned("LATE_FILL_DURING_CANCEL");}
      TTAudit("ENTRY_FILL","OWNED",ttEntry);
   }
   else if(e==DEAL_ENTRY_OUT || e==DEAL_ENTRY_OUT_BY)
    {TTAudit("EXIT_FILL",IntegerToString((int)HistoryDealGetInteger(tx.deal,DEAL_REASON)),HistoryDealGetDouble(tx.deal,DEAL_PRICE));TTReconcileOwned();}
}
double OnTester(){return TesterStatistics(STAT_PROFIT);}
void OnDeinit(const int reason){TTStateSave();EventKillTimer();TTNewsShutdown();if(ttAudit!=INVALID_HANDLE)FileClose(ttAudit);TTDeinitVisuals(reason);if(StrategyLease!=INVALID_HANDLE){FileClose(StrategyLease);StrategyLease=INVALID_HANDLE;}}
#endif
