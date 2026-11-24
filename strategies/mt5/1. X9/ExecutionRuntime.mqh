//+------------------------------------------------------------------+
//|                                             ExecutionRuntime.mqh |
//|        Copyright 2026-2027, Osamwonyi Eric (@You_FoundEric)      |
//|                                      https://x.com/You_FoundEric |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026-2027, Osamwonyi Eric (@You_FoundEric)"
#property link      "https://x.com/You_FoundEric"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\PositionInfo.mqh>

// ===== CLK-ADAPTER 1.4 BEGIN ================================================================================
// STANDARD BLOCK - paste verbatim below CLK-CORE. Do not edit per EA.
//
// ZERO CONFIGURATION. There are no clock inputs. The EA must not ask the operator what time it is, what
// the broker's offset is, or which DST rule the broker follows: it derives all of it from evidence it
// already has (the price series it trades, the server clock, and a learned per-server profile), and it
// never consults the PC clock for anything but a sanity bound.
//
//   no inputs, no files to edit, nothing to set in the tester or on a live chart.
//   an integrator who must pin a broker can #define CLK_FORCE_RULE / CLK_FORCE_BASE_MINUTES before this
//   block is included. That is a code decision recorded in the source, never a user-facing toggle.
//
// Public API (everything else is internal):
//   int      ClkInit()                    reset state, seed the compiled/scheduled clock if any  -> INIT_* code
//   void     ClkRefresh(datetime nowSrv)  call first on every tick/timer pass: resolves, cross-checks, sets flags
//   datetime ClkNowServer()               current server time (tester: TimeCurrent, live: TimeTradeServer)
//   datetime ClkNowUtc(datetime nowSrv)   current UTC; 0 only while unresolved
//   datetime ClkStampToUtc(datetime s)    UTC of a past server stamp (bar/position/deal); fold -> first occurrence
//   datetime ClkUtcToServerTime(datetime) server wall time of a UTC instant (chart objects, expirations)
//   bool     ClkOK()                      mapping is trustworthy. false = genuine conflict: flatten owned risk
//   bool     ClkEntryOK()                 new signals allowed (ClkOK and no transition-skew wait)
//   bool     ClkGaveUp()                  tester only: the clock can never resolve; the EA should ExpertRemove() (fail fast)
//   string   ClkText() / ClkNote() / ClkSource() / ClkAnchorAudit() / int ClkRule() / int ClkBase()  for panels and journals
//
// Resolution ladder (first hit wins; the source is always labelled; a resolved mapping is frozen, never re-sampled):
//   COMPILED  CLK_FORCE_RULE was defined in this EA's source: an explicit, dated code decision. Outranks everything.
//   PROFILE   Common\Files\clock_profiles.csv: lines  pattern,rule,baseMinutes  (pattern = lowercase substring of
//             "server company"; rule = NONE|US|EU). Broker knowledge lives in DATA, never in the code.
//   LEARNED   a profile any standard EA wrote here: Common\Files\clock_profile_<hash>.txt (live/demo run on this server)
//   LIVE      live only: rule proven from weekly-open history, base from TimeTradeServer()-TimeGMT(), PC clock only as
//             a sanity bound. Thin history gives LIVE_PROVISIONAL, which needs no trading pause.
//   ANCHORED  tester: base from the weekly CLOSE constant assuming the weekly close is Friday 17:00 NY, accepted only
//   ANCHORED-REF tester: same anchor, but proved on a standard-hours series on the same server because the
//             traded symbol cannot prove it (European-hours index, early-close index, 24/7 crypto)
//             if the open constant agrees under a 17:00 or 18:00 NY open. A labelled assumption; a profile outranks it.
//   SEGMENTED tester: the broker changed its clock during the sample, so no single constant fits. Weekly evidence is
//             grouped into dated (rule, base) segments; the absolute base still rests on the labelled open-hour
//             assumption, the CHANGES between segments are measured. Every segment needs >= CLK_SEG_MIN_WEEKS weeks.
//   none      unresolved: no entries, no default offset. The EA says why once, then refuses to guess.
//
// ANCHOR AUDIT. The tester's only unprovable fact is "the weekly close is Friday 17:00 NY". A live/demo run knows the
// broker's real offset, so every LIVE resolution also computes what the close anchor WOULD have produced and records
// the verdict (agree / DISAGREE / n/a) in the log and in the learned profile's 9th field. `tools/clk_audit_report.py`
// summarises the profiles: any DISAGREE broker needs a clock_profiles.csv line, because its tester runs would be
// shifted. That turns "assumed" into "audited on N brokers" without asking anyone for anything.
#define CLK_ADAPTER_VERSION "1.9"

// ---- configuration, in code, not in the UI -------------------------------------------------------------
// Optional: #define CLK_FORCE_RULE CLK_RULE_US and CLK_FORCE_BASE_MINUTES 120 before this block to pin a
// broker in an EA's source. Left undefined, the adapter resolves by itself.
#ifdef CLK_FORCE_RULE
const int  ClkCfgForcedRule  = CLK_FORCE_RULE;
#ifndef CLK_FORCE_BASE_MINUTES
#define CLK_FORCE_BASE_MINUTES 0
#endif
const int  ClkCfgForcedBase  = CLK_FORCE_BASE_MINUTES;
const bool ClkCfgForced      = true;
#else
const int  ClkCfgForcedRule  = CLK_RULE_NONE;
const int  ClkCfgForcedBase  = CLK_BASE_INVALID;
const bool ClkCfgForced      = false;
#endif
// The mapping is never taken from the operator: AUTO mode, anchored in the tester, evidence symbol = the chart.
const int  ClkCfgMode        = CLK_MODE_AUTO;
const int  ClkCfgAnchor      = CLK_ANCHOR_AUTO;
#define CLK_BARS_LOOKBACK   40000          // M15 bars (~83 weeks) of history used as evidence
#define CLK_TOL_SEC         300
#define CLK_SKEW_HOURS      12

int      clkRule=CLK_RULE_NONE;
int      clkBase=0;
int      clkCandRule[];
int      clkCandBase[];
int      clkCandN=0;
bool     clkResolved=false;
bool     clkProvisional=false;
bool     clkOkFlag=false;
bool     clkSkew=false;
bool     clkIgnoreProfile=false;
bool     clkGaveUp=false;
string   clkSource="none";
string   clkNote="not resolved";
datetime clkRetry=0;
datetime clkLastUtc=0;
datetime clkLogAt=0;
string   clkLogLast="";
int      clkEvWeeks=0;
int      clkEvHits=0;
int      clkEvMargin=0;
long     clkFoldFirstCount=0;
long     clkGapCount=0;
datetime clkSegFrom[]; int clkSegRule[]; int clkSegBase[]; int clkSegWeeksArr[]; int clkSegN=0;

void ClkLog(string msg)
{
   datetime t=TimeLocal();
   if(msg==clkLogLast && t-clkLogAt<60) return;
   clkLogLast=msg; clkLogAt=t; Print(msg);
}
uint ClkHash(string s)
{
   uint h=2166136261;
   for(int i=0;i<StringLen(s);i++) h=(h^(uint)StringGetCharacter(s,i))*16777619;
   return h;
}
bool     ClkOK()      { return clkResolved && clkOkFlag; }
bool     ClkEntryOK() { return clkResolved && clkOkFlag && !clkSkew; }
bool     ClkGaveUp()  { return clkGaveUp; }
int      ClkRule()    { return clkRule; }
int      ClkBase()    { return clkBase; }
string   ClkSource()  { return clkSource; }
string   ClkNote()    { return clkNote; }
string   ClkText()
{
   if(!clkResolved) return "UNRESOLVED";
   string clkTxt=StringFormat("%s %+dm [%s]",clkRule==CLK_RULE_US?"US-DST":clkRule==CLK_RULE_EU?"EU-DST":"fixed",clkBase,clkSource);
   return (clkSegN>1) ? StringFormat("%s x%d",clkTxt,clkSegN) : clkTxt;
}
datetime ClkNowServer()
{
   if(MQLInfoInteger(MQL_TESTER)) return TimeCurrent();
   return (datetime)MathMax((long)TimeCurrent(),(long)TimeTradeServer());
}
int ClkInit()
{
   if(ClkCfgForced && (ClkCfgForcedBase<-720 || ClkCfgForcedBase>840 || (ClkCfgForcedBase%15)!=0 || ClkCfgForcedRule<0 || ClkCfgForcedRule>2))
   { Print("CLK_INIT_FAIL CLK_FORCE_BASE_MINUTES must be a multiple of 15 in [-720,840] and CLK_FORCE_RULE 0..2"); return INIT_PARAMETERS_INCORRECT; }
   clkGaveUp=false; clkResolved=false; clkProvisional=false; clkOkFlag=false; clkSkew=false; clkIgnoreProfile=false;
#ifdef CLK_TEST_IGNORE_PROFILE
   clkIgnoreProfile=true;                 // TEST BUILDS ONLY: isolate a rung that a learned profile would shadow
#endif
   clkSource="none"; clkNote="not resolved"; clkAnchorAudit=""; clkRetry=0; clkLastUtc=0; clkCandN=0;
   clkEvWeeks=0; clkEvHits=0; clkEvMargin=0; clkFoldFirstCount=0; clkGapCount=0; clkSegN=0;
   return INIT_SUCCEEDED;
}
string clkAnchorAudit="";                       // "agree" | "DISAGREE" | "n/a" | "" (not a live resolution)
string   ClkAnchorAudit() { return clkAnchorAudit; }

// ---- candidate bookkeeping ----------------------------------------------------------------------------------------
void ClkSetCandidates(int n,int &rules[],int &bases[])
{
   clkSegN=0;
   ArrayResize(clkCandRule,n); ArrayResize(clkCandBase,n); clkCandN=n;
   for(int i=0;i<n;i++) { clkCandRule[i]=rules[i]; clkCandBase[i]=bases[i]; }
   clkRule=clkCandRule[0]; clkBase=clkCandBase[0]; clkResolved=true;
}
void ClkSetSingle(int rule,int base,string source)
{
   int r[]; int b[];
   ArrayResize(r,1); ArrayResize(b,1); r[0]=rule; b[0]=base;
   ClkSetCandidates(1,r,b);
   clkSource=source; clkProvisional=false; clkOkFlag=true; clkSkew=false;
}
// A dated schedule is the only resolution that can describe a broker whose clock changed mid-sample. The absolute base
// still rests on one labelled assumption (the feed's weekly open hour); the changes between segments are measured.
void ClkSetSegments(datetime &from[],int &rules[],int &bases[],int &weeks[],int n,int covered,int openNY)
{
   ArrayResize(clkSegFrom,n); ArrayResize(clkSegRule,n); ArrayResize(clkSegBase,n); ArrayResize(clkSegWeeksArr,n);
   for(int i=0;i<n;i++) { clkSegFrom[i]=from[i]; clkSegRule[i]=rules[i]; clkSegBase[i]=bases[i]; clkSegWeeksArr[i]=weeks[i]; }
   int rr[]; int bb[];
   ArrayResize(rr,1); ArrayResize(bb,1); rr[0]=rules[n-1]; bb[0]=bases[n-1];
   ClkSetCandidates(1,rr,bb);
   clkSegN=n;                                   // ClkSetCandidates clears the schedule; restore it
   clkSource="SEGMENTED"; clkProvisional=false; clkOkFlag=true; clkSkew=false;
   clkNote=StringFormat("%d dated segments (%d weeks); absolute base assumes the feed opens %02d:00 NY",n,covered,openNY);
   ClkJournal(StringFormat("CLK_ASSUMPTION %s; a live/registry profile outranks this",ClkText()));
}
bool ClkTrySchedule(datetime &opens[],datetime &closes[])
{
   if(ArraySize(opens)<CLK_SEG_MIN_WEEKS*2) return false;
   datetime f[]; int r[]; int b[]; int w[]; int covered=0;
   int n=ClkScheduleFromEvidence(opens,ArraySize(opens),closes,ArraySize(closes),18,f,r,b,w,covered);
   int openNY=18;
   if(n<2)
   {
      n=ClkScheduleFromEvidence(opens,ArraySize(opens),closes,ArraySize(closes),17,f,r,b,w,covered);
      openNY=17;
   }
   if(n<2) return false;
   ClkSetSegments(f,r,b,w,n,covered,openNY);
   return true;
}
// ---- evidence ---------------------------------------------------------------------------------------------------
string clkEvSymbol="";                              // the series that proved the clock ("" = chart symbol)
string ClkEvidenceSymbolName() { return clkEvSymbol!="" ? clkEvSymbol : _Symbol; }
// Candidate evidence series, in order: the traded symbol first, then standard-hours feeds on the same server.
// The broker's offset is a property of the server, so a standard FX/US-hours series proves it for every symbol.
// Candidate evidence series, chosen by INSTRUMENT CLASS so no broker's symbol naming can break it
// ("EURUSDm", "EURUSD.r", "USTEC" vs "NAS100" all resolve to the same classes). The broker's offset is a
// property of the server, so any standard-hours feed on this server proves it for every instrument.
void ClkBuildEvidenceRefs(string &out[])
{
   int total=SymbolsTotal(false);
   int n=0;
   ArrayResize(out,0);
   for(int pass=0;pass<2 && n<6;pass++)                 // pass 0: FX majors, pass 1: any FX pair
      for(int i=0;i<total && n<6;i++)
      {
         string sym=SymbolName(i,false);
         if(SymbolInfoInteger(sym,SYMBOL_TRADE_CALC_MODE)!=SYMBOL_CALC_MODE_FOREX) continue;
         string path=SymbolInfoString(sym,SYMBOL_PATH);
         if(pass==0 && StringFind(path,"Major")<0) continue;
         bool dup=false;
         for(int k=0;k<n;k++) if(out[k]==sym) { dup=true; break; }
         if(dup) continue;
         ArrayResize(out,n+1); out[n++]=sym;
      }
}
string ClkEvidenceSymbolAt(int attempt)
{
   if(attempt==0) return _Symbol;
   static string refs[];
   static bool built=false;
   if(!built) { ClkBuildEvidenceRefs(refs); built=true; }
   return (attempt-1<ArraySize(refs)) ? refs[attempt-1] : "";
}
int ClkEvidenceFor(string sym,int &rule,int &modeOpen,int &modeClose,datetime &opensOut[],datetime &closesOut[])
{
   datetime bars[];
   datetime opens[];
   datetime closes[];
   clkEvWeeks=0; clkEvHits=0; clkEvMargin=0; rule=-1; modeOpen=0; modeClose=0;
   ArrayResize(opensOut,0); ArrayResize(closesOut,0);
   if(sym!=_Symbol) SymbolSelect(sym,true);
   datetime touch[];
   CopyTime(sym,PERIOD_M15,0,1,touch);                       // queues the sync; the copy below may still be short
   int got=CopyTime(sym,PERIOD_M15,0,CLK_BARS_LOOKBACK,bars);
   if(got<4000) return -1;
   clkEvWeeks=ClkWeekOpens(bars,got,opens);
   int nClose=ClkWeekCloses(bars,got,closes);
   ArrayCopy(opensOut,opens);
   ArrayCopy(closesOut,closes);
   return ClkInferRule(opens,clkEvWeeks,closes,nClose,rule,clkEvHits,clkEvMargin,modeOpen,modeClose);
}
int ClkEvidence(int &rule,int &modeOpen,int &modeClose,datetime &opensOut[],datetime &closesOut[])
{
   return ClkEvidenceFor(ClkEvidenceSymbolName(),rule,modeOpen,modeClose,opensOut,closesOut);
}
int ClkEvidence(int &rule,int &modeOpen,int &modeClose) { datetime eo[],ec[]; return ClkEvidence(rule,modeOpen,modeClose,eo,ec); }

// Tester anchor, with the server treated as the thing being proved rather than the symbol:
// own series first (unchanged behaviour for every feed that can prove itself), then a standard-hours
// reference, then nothing. Returns the base, the implied open hour and the series that proved it.
int clkRefPos=0;            // round-robin cursor over the candidate series
bool clkRefPending=false;   // true: some candidate had no history yet, so waiting is right, giving up is not

int ClkAnchorBase(int &rule,int &modeOpen,int &modeClose,int &openNY,string &usedSym)
{
   openNY=0; usedSym=""; clkRefPending=false;
   // In the Strategy Tester, touching another symbol makes the agent try to synchronise it; when that fails
   // the whole test ends ("symbol EURUSD synchronization error ... unexpected end of testing"). So the tester
   // proves the clock from the traded feed only, or from a profile / clock_profiles.csv / a source pin.
   if(MQLInfoInteger(MQL_TESTER)) return CLK_BASE_INVALID;
   bool anyHistory=false;
   for(int tried=0;tried<8;tried++)
   {
      string sym=ClkEvidenceSymbolAt(clkRefPos);
      clkRefPos=(clkRefPos+1)%8;
      if(sym=="") continue;
      datetime eo[],ec[];
      int st=ClkEvidenceFor(sym,rule,modeOpen,modeClose,eo,ec);
      if(st<0) { clkRefPending=true; continue; }              // history still arriving on this terminal
      anyHistory=true;
      int b=ClkBaseFromCloseAnchor(modeOpen,modeClose,openNY);
      if(st!=1 || b==CLK_BASE_INVALID) continue;              // has history, cannot prove it: next candidate
      usedSym=sym; clkRefPending=false;
      return b;
   }
   if(!anyHistory) clkRefPending=true;                        // nothing read yet: try again on the next tick
   return CLK_BASE_INVALID;
}
bool ClkLiveOffset(int &obsSec)                    // server-minus-UTC on the 15-minute grid, with a PC-clock sanity bound
{
   if(MQLInfoInteger(MQL_TESTER) || !TerminalInfoInteger(TERMINAL_CONNECTED)) return false;
   datetime ts=TimeTradeServer(), gmt=TimeGMT();
   if(ts<=0 || gmt<=0) return false;
   long raw=(long)(ts-gmt);
   long r=(long)MathRound((double)raw/900.0)*900;
   if(MathAbs(raw-r)>CLK_TOL_SEC)
   { clkNote=StringFormat("PC clock is %d s off the server's 15-minute grid: fix PC time/timezone",(int)(raw-r)); return false; }
   obsSec=(int)r;
   return true;
}
// ---- data files -------------------------------------------------------------------------------------------------
string ClkServerKey()
{
   string s=AccountInfoString(ACCOUNT_SERVER);
   StringReplace(s,",",";");
   return s;
}
string ClkProfileFile() { return "clock_profile_"+IntegerToString(ClkHash(AccountInfoString(ACCOUNT_SERVER)))+".txt"; }
// ---- one journal slot per machine ---------------------------------------------------------------------
// The clock belongs to the server, so its announcement belongs to the server too. The first EA to resolve a
// decision claims the slot; every other EA on the same server is silent about that same decision.
string ClkJournalFile() { return "clock_journal_"+IntegerToString(ClkHash(AccountInfoString(ACCOUNT_SERVER)))+".txt"; }
bool ClkJournalClaim(string decision)
{
   string want=decision+","+TimeToString(TimeGMT(),TIME_DATE);
   int h=FileOpen(ClkJournalFile(),FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h!=INVALID_HANDLE)
   {
      string line="";
      if(!FileIsEnding(h)) line=FileReadString(h);
      FileClose(h);
      StringTrimLeft(line); StringTrimRight(line);
      if(line==want) return false;                       // another EA already announced this decision today
   }
   h=FileOpen(ClkJournalFile(),FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h==INVALID_HANDLE) return true;                    // cannot claim: speak rather than hide a decision
   FileWriteString(h,want+"\r\n");
   FileClose(h);
   return true;
}
void ClkJournal(string text) { if(ClkJournalClaim(ClkText())) Print(text); }
void ClkJournalFmt(string fmt) { if(ClkJournalClaim(ClkText())) Print(fmt); }
bool ClkReadLine(int h,string &line)
{
   while(!FileIsEnding(h))
   {
      line=FileReadString(h);
      StringTrimLeft(line); StringTrimRight(line);
      if(line!="" && StringGetCharacter(line,0)!='#') return true;
   }
   return false;
}
int ClkParseRule(string s)
{
   StringTrimLeft(s); StringTrimRight(s); StringToUpper(s);
   if(s=="US") return CLK_RULE_US;
   if(s=="EU") return CLK_RULE_EU;
   if(s=="NONE" || s=="FIXED") return CLK_RULE_NONE;
   return -1;
}
bool ClkProfileLookup(int &rule,int &base,string &pattern)     // registry: first matching line wins
{
   int h=FileOpen("clock_profiles.csv",FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h==INVALID_HANDLE) return false;
   string id=AccountInfoString(ACCOUNT_SERVER)+" "+AccountInfoString(ACCOUNT_COMPANY);
   StringToLower(id);
   bool found=false; string line;
   while(!found && ClkReadLine(h,line))
   {
      string f[];
      if(StringSplit(line,',',f)<3) continue;
      string p=f[0]; StringTrimLeft(p); StringTrimRight(p); StringToLower(p);
      int rr=ClkParseRule(f[1]); int bb=(int)StringToInteger(f[2]);
      if(p=="" || StringFind(id,p)<0 || rr<0 || bb<-720 || bb>840 || (bb%15)!=0) continue;
      rule=rr; base=bb; pattern=p; found=true;
   }
   FileClose(h);
   return found;
}
void ClkLearnedWrite()                              // live: hand the verified clock to the tester (shared by every EA on this machine)
{
#ifdef CLK_TRACE_WRITER
   PrintFormat("CLK_WRITE tester=%d prog=%s symbol=%s base=%d src=%s",MQLInfoInteger(MQL_TESTER),MQLInfoString(MQL_PROGRAM_NAME),_Symbol,clkBase,clkSource);
#endif
   int h=FileOpen(ClkProfileFile(),FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h==INVALID_HANDLE) return;
   FileWriteString(h,StringFormat("%s,%d,%d,%s,%I64d,%d,%d,%d,%s\r\n",ClkServerKey(),clkRule,clkBase,clkSource,(long)TimeGMT(),clkEvWeeks,clkEvHits,clkEvMargin,clkAnchorAudit));
   FileClose(h);
}
bool ClkLearnedRead(int &rule,int &base)
{
   int h=FileOpen(ClkProfileFile(),FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h==INVALID_HANDLE) return false;
   string line; bool ok=false;
   if(ClkReadLine(h,line))
   {
      string f[];
      if(StringSplit(line,',',f)>=3 && f[0]==ClkServerKey())
      {
         int rr=(int)StringToInteger(f[1]); int bb=(int)StringToInteger(f[2]);
         int nf=StringSplit(line,',',f);
         long written=(nf>=5) ? (long)StringToInteger(f[4]) : 0;          // when the live proof was written
         bool stale=(written>0 && (long)TimeGMT()-written>180*86400);
         if(stale) ClkLog("CLK_PROFILE_STALE the learned profile is older than 180 days; ignoring it for this run");
         else if(rr>=0 && rr<=2 && bb>=-720 && bb<=840 && (bb%15)==0) { rule=rr; base=bb; ok=true; }
      }
   }
   FileClose(h);
   return ok;
}
// ---- resolution ---------------------------------------------------------------------------------------------------
void ClkResolve(datetime nowSrv)
{
   if((clkResolved && !clkProvisional) || nowSrv<clkRetry) return;
   clkRetry=nowSrv+(clkProvisional?300:30);
   bool tester=(MQLInfoInteger(MQL_TESTER)!=0);
   if(ClkCfgForced) { ClkSetSingle(ClkCfgForcedRule,ClkCfgForcedBase,"COMPILED"); clkNote="pinned in source (CLK_FORCE_RULE)"; return; }
   int rule=-1, mo=0, mc=0;
   datetime evOpen[], evClose[];
   int st=ClkEvidence(rule,mo,mc,evOpen,evClose);
   int prule=0, pbase=0; string ppat="";
   if(!clkIgnoreProfile && ClkProfileLookup(prule,pbase,ppat))
   {
      if(st==1 && rule!=prule)
      { clkNote="PROFILE_CONFLICT: weekly-open history disagrees with registry entry '"+ppat+"'"; ClkLog("CLK "+clkNote); return; }
      ClkSetSingle(prule,pbase,"PROFILE"); clkNote="registry entry '"+ppat+"'";
      ClkJournal(StringFormat("CLK_PROFILE %s from registry entry '%s' (%s); no anchor needed",ClkText(),ppat,ClkProfileFile()));
      return;
   }
   if(tester)
   {
      int lrule=0, lbase=0;
      if(!clkIgnoreProfile && ClkLearnedRead(lrule,lbase))   // a stale learned profile must be ignorable too
      {
         if(st==1 && rule!=lrule) { clkNote="LEARNED_CONFLICT: learned profile disagrees with tester history; delete "+ClkProfileFile(); ClkLog("CLK "+clkNote); return; }
         ClkSetSingle(lrule,lbase,"LEARNED"); clkNote="profile learned by a live run";
         ClkJournal(StringFormat("CLK_LEARNED %s from a profile written by an earlier run on this server",ClkText()));
         return;
      }
      {
         if(st!=1)
         {
            // No single constant fits: either the history is still thin, or the broker changed its clock mid-sample.
            // A dated schedule resolves the second case; short history still just waits.
            if(ClkTrySchedule(evOpen,evClose)) return;
            clkNote=StringFormat("waiting for weekly history to prove the DST rule (%d weeks, status %d)",clkEvWeeks,st);
            return;
         }
         int ab=CLK_BASE_INVALID, on=0; string used="";
         ab=ClkBaseFromCloseAnchor(mo,mc,on);
         if(ab!=CLK_BASE_INVALID) used=_Symbol;
         if(ab==CLK_BASE_INVALID) ab=ClkAnchorBase(rule,mo,mc,on,used);   // a standard-hours series on this server
         string src=(used!="" && used!=_Symbol) ? "ANCHORED-REF" : "ANCHORED";
         if(ab==CLK_BASE_INVALID && clkRefPending)
         {
            clkNote="waiting for a reference series to synchronise (the traded feed cannot prove the clock)";
            return;
         }
         if(ab==CLK_BASE_INVALID)
         {
            clkNote="tester clock anchor failed (see Experts log)"; clkGaveUp=true;
            ClkLog(StringFormat("CLK_GIVE_UP the weekly open/close history is not consistent with a 17:00 NY close (implied base %+dm from the close, %+dm from the open at 18:00 NY). Tried the traded feed and up to eight standard-hours FX references on this server, chosen by instrument class. Nothing to configure: either history is thin, or a clock_profiles.csv line / one live run on this server will pin it. Pinning in source is possible but is a code decision, not a setting.",ClkBaseFromAnchor(mc,17),ClkBaseFromAnchor(mo,18)));
            return;
         }
         ClkSetSingle(rule,ab,src);
         clkNote=(used==_Symbol)
            ? StringFormat("ASSUMPTION: weekly close 17:00 NY, feed opens %d:00 NY; confirm with a live profile",on)
            : StringFormat("ASSUMPTION: proved on %s (standard hours on this server), traded feed cannot prove it",used);
         if(used!=_Symbol && used!="")
            ClkJournal(StringFormat("CLK_REFERENCE %s proved the %s clock (traded feed %s has no usable weekly shape)",used,AccountInfoString(ACCOUNT_SERVER),_Symbol));
         ClkJournal(StringFormat("CLK_ASSUMPTION %s base %+dm; a live/registry profile outranks this",ClkText(),ab));
         return;
      }
   }
   // The traded feed may be structurally unable to prove the rule: an index tracks its own exchange calendar,
   // so on a fixed server its week open still moves with US DST and the shape reads as "DST-shaped with base 0",
   // which is not a clock any ladder can confirm. A standard-hours FX series on the same server can prove it -
   // it opens at a fixed New York hour every week, so its shape reads the server offset directly. Ask a reference
   // before settling for a provisional guess (Exness: EURJPY proved fixed +0 while USTEC could not).
   if(st!=1)
   {
      int rref=rule, moRef=0, mcRef=0, onRef=0; string usedRef="";
      int bref=ClkAnchorBase(rref,moRef,mcRef,onRef,usedRef);
      if(bref!=CLK_BASE_INVALID && usedRef!="")
      {
         ClkSetSingle(rref,bref,"ANCHORED-REF");
         clkNote=StringFormat("traded feed %s cannot prove the clock; reference %s proved rule %d base %+dm",
                              _Symbol,usedRef,rref,bref);
         ClkJournal(StringFormat("CLK_ANCHOR_REF %s proves rule=%d base=%+dm for %s on %s",
                                 usedRef,rref,bref,_Symbol,AccountInfoString(ACCOUNT_SERVER)));
         return;
      }
   }
   int obs=0;
   if(!ClkLiveOffset(obs)) { if(clkNote=="" || clkNote=="not resolved") clkNote="live server offset not observable yet"; return; }
   datetime gmt=TimeGMT();
   if(st==1)
   {
      int base=ClkBaseFromLive(obs,rule,gmt);
      if(base==CLK_BASE_INVALID) { clkNote="observed offset does not fit the inferred rule on a 15-minute grid"; return; }
      int b17=ClkBaseFromAnchor(mo,17), b18=ClkBaseFromAnchor(mo,18);       // independent guard against a wrong PC timezone
      if(base!=b17 && base!=b18)
      { clkNote=StringFormat("live base %+dm contradicts the weekly-open anchor (%+dm @17NY, %+dm @18NY): check PC timezone",base,b17,b18); ClkLog("CLK "+clkNote); return; }
      ClkSetSingle(rule,base,"LIVE"); clkNote=StringFormat("rule inferred from %d weekly opens",clkEvWeeks);
      // Audit the tester's assumption against reality, on this broker, for free.
      { int anOpen=0; int anBase=ClkBaseFromCloseAnchor(mo,mc,anOpen);
        clkAnchorAudit=(anBase==CLK_BASE_INVALID) ? "n/a" : (anBase==base ? "agree" : "DISAGREE");
        ClkJournal(StringFormat("CLK_ANCHOR_AUDIT live=%+dm anchor=%s verdict=%s",base,
                    (anBase==CLK_BASE_INVALID)?"n/a":StringFormat("%+dm",anBase),clkAnchorAudit)); }
      ClkLearnedWrite();
      ClkJournal(StringFormat("CLK_RESOLVED %s weeks=%d hits=%d margin=%d",ClkText(),clkEvWeeks,clkEvHits,clkEvMargin));
      return;
   }
   if(clkResolved) return;                                  // provisional stays as learned; only resolved evidence replaces it
   int rs[]; int bs[];
   ArrayResize(rs,3); ArrayResize(bs,3);
   for(int i=0;i<3;i++)
   {
      rs[i]=i; bs[i]=ClkBaseFromLive(obs,i,gmt);
      if(bs[i]==CLK_BASE_INVALID) { clkNote="observed offset not on a 15-minute grid"; return; }
   }
   ClkSetCandidates(3,rs,bs);
   clkSource="LIVE_PROVISIONAL"; clkProvisional=true; clkOkFlag=true; clkSkew=false;
   clkNote=StringFormat("rule not yet proven (%d weeks, status %d): live offset narrows candidates",clkEvWeeks,st);
   ClkLog("CLK "+clkNote);
}
// Call first on every pass. Resolves, then (live) cross-checks the model against the observed server-minus-UTC offset.
//   consistent                       -> ok
//   inconsistent by exactly +-1h within 12h of the rule's DST change (broker switched at a different instant than the rule):
//                                       transition-skew wait: entries paused, nothing flattened, clears itself
//   inconsistent otherwise           -> genuine conflict: ClkOK()=false (EA flattens owned risk and stops entries)
bool clkAnnounced=false;
void ClkRefresh(datetime nowSrv)
{
   ClkResolve(nowSrv);
   if(!clkResolved) { clkOkFlag=false; clkSkew=false; return; }
   if(!clkAnnounced)                     // one line per EA process: an EA's own log can always prove its clock
   {
      clkAnnounced=true;
      PrintFormat("CLK_EA %s symbol=%s clock=%s source=%s server=%s",
                  MQLInfoString(MQL_PROGRAM_NAME),_Symbol,ClkText(),clkSource,AccountInfoString(ACCOUNT_SERVER));
   }
   if(MQLInfoInteger(MQL_TESTER) || !TerminalInfoInteger(TERMINAL_CONNECTED)) return;       // tester: nothing to observe; offline: keep verdict
   datetime ts=TimeTradeServer(), gmt=TimeGMT();
   if(ts<=0 || gmt<=0) return;
   long observed=(long)(ts-gmt);
   int kr[]; int kb[];
   ArrayResize(kr,3); ArrayResize(kb,3);
   int keep=0;
   for(int i=0;i<clkCandN && i<3;i++)
   {
      long diff=observed-(long)(ClkUtcToServer(gmt,clkCandRule[i],clkCandBase[i])-gmt);
      if(diff>=-CLK_TOL_SEC && diff<=CLK_TOL_SEC) { kr[keep]=clkCandRule[i]; kb[keep]=clkCandBase[i]; keep++; }
   }
   if(keep>0)
   {
      clkOkFlag=true; clkSkew=false;
      if(keep<clkCandN || kr[0]!=clkRule || kb[0]!=clkBase)
      {
         ClkSetCandidates(keep,kr,kb);
         clkProvisional=(keep>1);
         ClkJournal(StringFormat("CLK_NARROWED live offset leaves %d candidate(s): %s",keep,ClkText()));
      }
      return;
   }
   long dprim=observed-(long)(ClkUtcToServer(gmt,clkRule,clkBase)-gmt);
   long adprim=(dprim<0)?-dprim:dprim;
   if(adprim>=3600-CLK_TOL_SEC && adprim<=3600+CLK_TOL_SEC && ClkNearTransition(gmt,clkRule,CLK_SKEW_HOURS))
   {
      clkOkFlag=true; clkSkew=true;
      clkNote="transition skew: broker switched DST at a different instant than the rule; entries paused until the offset matches";
      ClkLog("CLK_SKEW "+clkNote);
      return;
   }
   clkOkFlag=false; clkSkew=false;
   clkNote=StringFormat("live offset %+dm matches no candidate clock (%s)",(int)(observed/60),ClkText());
   ClkLog("CLK_MISMATCH "+clkNote);
   if(clkSource=="LIVE" || clkProvisional) { clkResolved=false; clkProvisional=false; clkRetry=nowSrv+30; }
   else if(clkSource=="PROFILE") { clkResolved=false; clkIgnoreProfile=true; clkRetry=nowSrv+30; ClkLog("CLK_PROFILE_OVERRIDDEN registry entry contradicts the live offset; re-deriving from live evidence"); }
}
// ---- conversions ---------------------------------------------------------------------------------------------------
// Current UTC from the current server time. Fold hour: resolved with a lower bound (tester: previous resolved UTC;
// live: PC clock minus 2 min). Gap hour: deterministic and flagged. Never halts.
datetime ClkNowUtc(datetime nowSrv)
{
   if(!clkResolved || nowSrv<=0) return 0;
   datetime lb=MQLInfoInteger(MQL_TESTER) ? clkLastUtc : (datetime)(TimeGMT()-120);
   int conv;
   datetime u=(clkSegN>1) ? ClkServerToUtcSeg(nowSrv,clkSegFrom,clkSegRule,clkSegBase,clkSegN,lb,conv)
                          : ClkServerToUtc(nowSrv,clkRule,clkBase,lb,conv);
   if(conv==CLK_CONV_GAP) { clkGapCount++; ClkLog("CLK_GAP server time does not exist under the model; read with the pre-transition offset"); }
   else if(conv==CLK_CONV_FOLD_FIRST) clkFoldFirstCount++;
   clkLastUtc=u;
   return u;
}
// UTC of a PAST server stamp (position open time, bar time, deal time). A stamp inside a fold hour is ambiguous in
// principle; the first occurrence is returned (documented, deterministic).
datetime ClkStampToUtc(datetime stamp)
{
   if(!clkResolved || stamp<=0) return 0;
   int conv;
   if(clkSegN>1) return ClkServerToUtcSeg(stamp,clkSegFrom,clkSegRule,clkSegBase,clkSegN,0,conv);
   return ClkServerToUtc(stamp,clkRule,clkBase,0,conv);
}
datetime ClkUtcToServerTime(datetime utc)
{
   if(!clkResolved || utc<=0) return 0;
   if(clkSegN>1) return ClkUtcToServerSeg(utc,clkSegFrom,clkSegRule,clkSegBase,clkSegN);
   return ClkUtcToServer(utc,clkRule,clkBase);
}
// ===== CLK-ADAPTER 1.2 END ==================================================================================

// Global Trade Objects
CTrade         trade;
COrderInfo     ordinfo;
CPositionInfo  posinfo;

// Previous X9 magic base. Kept only to recognise (and refuse to adopt) tickets from that range.
#define X9_LEGACY_MAGIC 647873

// Global News State
datetime g_newsEvents[];
datetime g_newsWeek = 0;
bool     g_newsReady = false;
ulong    g_newsSuccessMs = 0;
ulong    g_newsAttemptMs = 0;
bool     g_newsLaunchLogged = false;
bool     g_newsBlocked = false;
bool     g_newsFlattenActive = false;
ulong    g_newsActionAttemptMs = 0;
bool     g_nettingCloseLogged = false;

// Global Drawdown State
double   g_dailyStartBasis = 0.0;
double   g_peakBasis = 0.0;
double   g_staticFloorBasis = 0.0;
int      g_lastDailyDay = -1;
bool     g_dailyBreached = false;
bool     g_totalBreached = false;
int      g_lastTotalDDResetID = -1;
string   g_totalDDLatchKey = "";

// ===== NEWS-FEED 1.0 BEGIN ===================================================================================
#define NF_VERSION        "1.0"
#define NF_TTL_FRESH      3600        // seconds a payload is considered current
#define NF_RETRY          300         // seconds between failed attempts
#define NF_STALE_MAX      604800      // one week: the calendar itself is weekly
#define NF_URL            "https://nfs.faireconomy.media/ff_calendar_thisweek.json"
#define NF_BODY           "NewsFeed_ff_weekly.json"
#define NF_META           "NewsFeed_ff_weekly.meta"

// Reads the shared snapshot. Returns true when a payload no older than NF_STALE_MAX is present.
bool NewsFeedReadCache(string &json, datetime &fetchedUtc, long &retryUntil)
{
   json = "";
   fetchedUtc = 0;
   retryUntil = 0;
   int meta = FileOpen(NF_META, FILE_READ | FILE_TXT | FILE_COMMON);
   if(meta != INVALID_HANDLE)
   {
      string line = FileReadString(meta);
      FileClose(meta);
      long stamp = (long)StringToInteger(line);
      if(stamp > 0) fetchedUtc = (datetime)stamp;
   }
   int body = FileOpen(NF_BODY, FILE_READ | FILE_BIN | FILE_COMMON);
   if(body != INVALID_HANDLE)
   {
      ulong size = FileSize(body);
      if(size > 8 && size < 4000000)
      {
         uchar raw[];
         ArrayResize(raw, (int)size);
         if(FileReadArray(body, raw, 0, (int)size) == (int)size)
            json = CharArrayToString(raw, 0, (int)size, CP_UTF8);
      }
      FileClose(body);
   }
   if(StringLen(json) < 8)
   {
      json = "";
      return false;
   }
   return(fetchedUtc > 0 && TimeGMT() >= fetchedUtc && TimeGMT() - fetchedUtc <= NF_STALE_MAX);
}

// Stores a payload plus its fetch time. Best effort: a read-only sandbox must not break the EA.
void NewsFeedWriteCache(const string json, const datetime fetchedUtc)
{
   if(StringLen(json) < 8) return;
   int body = FileOpen(NF_BODY, FILE_WRITE | FILE_BIN | FILE_COMMON);
   if(body == INVALID_HANDLE) return;
   uchar raw[];
   int len = StringToCharArray(json, raw, 0, -1, CP_UTF8);
   if(len > 1) FileWriteArray(body, raw, 0, len - 1);   // drop the terminating zero
   FileClose(body);
   int meta = FileOpen(NF_META, FILE_WRITE | FILE_TXT | FILE_COMMON);
   if(meta == INVALID_HANDLE) return;
   FileWriteString(meta, IntegerToString((long)fetchedUtc));
   FileClose(meta);
}

// One accessor for every EA. Never halts, never blocks longer than the request timeout.
int NewsFeedGet(string &json, datetime &fetchedUtc, bool &fromCache, bool allowCacheInTester)
{
   json = "";
   fromCache = false;
   long retryUntil = 0;
   bool haveCache = NewsFeedReadCache(json, fetchedUtc, retryUntil);

   bool tester = (bool)MQLInfoInteger(MQL_TESTER) || (bool)MQLInfoInteger(MQL_OPTIMIZATION);
   if(tester)
   {
      // The tester forbids WebRequest. Only an explicit opt-in makes backtests news-aware, and then
      // the snapshot is a fixed input: same file, same result, every run.
      if(haveCache && allowCacheInTester)
      {
         fromCache = true;
         return(200);
      }
      json = "";
      return(0);
   }

   datetime now = TimeGMT();
   if(haveCache && now >= fetchedUtc && now - fetchedUtc < NF_TTL_FRESH)
      return(200);                                   // current: no request at all
   if(now < retryUntil)
   {
      if(haveCache)
      {
         fromCache = true;
         return(200);
      }
      return(-1);
   }

   if(!(bool)TerminalInfoInteger(TERMINAL_CONNECTED))
   {
      if(haveCache)
      {
         fromCache = true;
         return(200);
      }
      return(0);
   }

   char request[], response[];
   string headers;
   ResetLastError();
   int status = WebRequest("GET", NF_URL, "User-Agent: Mozilla/5.0\r\nAccept: application/json\r\n",
                           5000, request, response, headers);
   int requestError = GetLastError();
   if(status == 200 && ArraySize(response) > 8)
   {
      string payload = CharArrayToString(response, 0, -1, CP_UTF8);
      if(StringLen(payload) > 8)
      {
         json = payload;
         fetchedUtc = TimeGMT();
         NewsFeedWriteCache(payload, fetchedUtc);
         return(200);
      }
   }

   // Failure: back off, and serve the snapshot if there is one. A stale-but-real calendar is better
   // than no calendar, and the EA's own policy decides what to do with it.
   int backoff = FileOpen(NF_META, FILE_WRITE | FILE_TXT | FILE_COMMON);
   if(backoff != INVALID_HANDLE)
   {
      FileWriteString(backoff, IntegerToString((long)(haveCache && fetchedUtc > 0 ? fetchedUtc : now)));
      FileClose(backoff);
   }
   if(haveCache)
   {
      fromCache = true;
      return(200);
   }
   json = "";
   return(status > 0 ? status : -requestError);
}
// ===== NEWS-FEED 1.0 END =====================================================================================

//+------------------------------------------------------------------+
//| X9 Magic Fence Check                                             |
//+------------------------------------------------------------------+
bool IsX9Magic(long magic) {
    return (magic >= InpMagic && magic <= InpMagic + 20);
}

// The magic base moved to 647900 so that strategy N owns base+N (last digit = strategy number).
// Tickets from the old 647873+N range are NOT owned any more: report them so the operator flattens
// the account instead of relying on adoption that silently reassigns the slot.
int X9LegacyMagicTickets()
{
   int found = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posinfo.SelectByIndex(i)) continue;
      long magic = posinfo.Magic();
      if(magic >= X9_LEGACY_MAGIC && magic <= X9_LEGACY_MAGIC + 20 && !IsX9Magic(magic)) found++;
   }
   for(int j = OrdersTotal() - 1; j >= 0; j--)
   {
      if(!ordinfo.SelectByIndex(j)) continue;
      long magic = ordinfo.Magic();
      if(magic >= X9_LEGACY_MAGIC && magic <= X9_LEGACY_MAGIC + 20 && !IsX9Magic(magic)) found++;
   }
   return found;
}

// A pending order deleted by the terminal operator (or mobile/web) is restored on
// the next timer pass when its original setup still reproduces the same stop price.
ulong g_x9ManualCancels[];

void X9QueueManualCancel(ulong ticket) {
    if (ticket == 0) return;
    int size = ArraySize(g_x9ManualCancels);
    for (int i = 0; i < size; i++) if (g_x9ManualCancels[i] == ticket) return;
    if (size >= 64) return;
    ArrayResize(g_x9ManualCancels, size + 1);
    g_x9ManualCancels[size] = ticket;
}

void X9RemoveManualCancel(int index) {
    int size = ArraySize(g_x9ManualCancels);
    for (int i = index; i < size - 1; i++) g_x9ManualCancels[i] = g_x9ManualCancels[i + 1];
    ArrayResize(g_x9ManualCancels, size - 1);
}

void X9NoteOrderDeleted(ulong ticket) {
    if (ticket == 0 || !HistoryOrderSelect(ticket)) return;
    if (HistoryOrderGetInteger(ticket, ORDER_STATE) != ORDER_STATE_CANCELED) return;

    long type = HistoryOrderGetInteger(ticket, ORDER_TYPE);
    if (type != ORDER_TYPE_BUY_STOP && type != ORDER_TYPE_SELL_STOP) return;
    long reason = HistoryOrderGetInteger(ticket, ORDER_REASON);
    if (reason != ORDER_REASON_CLIENT && reason != ORDER_REASON_MOBILE && reason != ORDER_REASON_WEB) return;
    if (!IsX9Magic(HistoryOrderGetInteger(ticket, ORDER_MAGIC))) return;
    if (HistoryOrderGetString(ticket, ORDER_SYMBOL) != TradeSym) return;
    X9QueueManualCancel(ticket);
}

bool X9RestoreCancelledPendingOrders() {
    bool restored = false;
    for (int i = ArraySize(g_x9ManualCancels) - 1; i >= 0; i--) {
        ulong ticket = g_x9ManualCancels[i];
        int slot;
        long magic, type;
        double price;

        if (!HistoryOrderSelect(ticket)) { X9RemoveManualCancel(i); continue; }
        magic = HistoryOrderGetInteger(ticket, ORDER_MAGIC);
        type = HistoryOrderGetInteger(ticket, ORDER_TYPE);
        if (type != ORDER_TYPE_BUY_STOP && type != ORDER_TYPE_SELL_STOP) { X9RemoveManualCancel(i); continue; }
        price = HistoryOrderGetDouble(ticket, ORDER_PRICE_OPEN);
        slot = -1;
        for (int strategy = 0; strategy < 9; strategy++) {
            SetupStrategyParams(strategy + 1);
            if (ActiveMagic == magic) { slot = strategy; break; }
        }
        if (slot < 0 || !StratEnabled[slot]) { X9RemoveManualCancel(i); continue; }
        if (!CanPlaceNewX9Entries()) continue;

        StrategyIdx = slot;
        SetupStrategyParams(slot + 1);
        ActivateStrategyContext(slot);
        CalculateLotSize();
        if (StrategyLots[slot] > MaxLotCap) StrategyLots[slot] = MaxLotCap;

        bool isBuy = (type == ORDER_TYPE_BUY_STOP);
        double swing = FindSwingPoint(FractalTf, isBuy);
        double desired = NormalizeDouble(isBuy ? swing + BuyEntryOffset * PipFactor : swing - SellEntryOffset * PipFactor, SymDigits);
        if (swing <= 0.0) { X9RemoveManualCancel(i); continue; }
        if (MathAbs(desired - price) > SymbolInfoDouble(TradeSym, SYMBOL_TRADE_TICK_SIZE) * 0.5) { X9RemoveManualCancel(i); continue; }
        if (PlaceEntry(isBuy)) {
            X9RemoveManualCancel(i);
            restored = true;
        }
    }
    return restored;
}

string X9TotalDDLatchKey() {
    return StringFormat("X9DD_%I64d_%s_%d", AccountInfoInteger(ACCOUNT_LOGIN), TradeSym, InpMagic);
}

void X9PersistTotalDDLatch() {
    if (g_totalDDLatchKey == "") g_totalDDLatchKey = X9TotalDDLatchKey();
    GlobalVariableSet(g_totalDDLatchKey, g_totalBreached ? 1.0 : 0.0);
}

void X9LoadTotalDDLatch() {
    g_totalDDLatchKey = X9TotalDDLatchKey();
    g_totalBreached = GlobalVariableCheck(g_totalDDLatchKey) && GlobalVariableGet(g_totalDDLatchKey) > 0.5;
    g_lastTotalDDResetID = InpTotalDDResetID;
    if (g_totalBreached) {
        PrintFormat("[X9_DD] Persistent TOTAL DD lock active. Increase InpTotalDDResetID to explicitly re-arm; current ID=%d.", InpTotalDDResetID);
    }
}

//+------------------------------------------------------------------+
//| Exact US DST UTC Offset Calculation (2007+ Rules)                |
//+------------------------------------------------------------------+

string GetNYTimeString() {
    // One clock for the whole EA: the server stamp goes through the standard adapter, so tester and live
    // read the same New York wall time and neither depends on the PC clock.
    datetime utc = ClkNowUtc(ClkNowServer());
    if (utc <= 0) return "clock unresolved";
    return TimeToString(ClkUtcToNy(utc), TIME_MINUTES) + " NY";
}

//+------------------------------------------------------------------+
//| ForexFactory JSON News Parser & Refresh Engine                   |
//+------------------------------------------------------------------+
datetime NewsNY(datetime utc) { return utc + ClkNyUtcOffset(utc); }

datetime NewsWeek(datetime ny) {
    MqlDateTime d; TimeToStruct(ny, d);
    return (datetime)((long)ny / 86400 * 86400) - d.day_of_week * 86400;
}

bool NewsValid() {
    return g_newsReady && (GetTickCount64() - g_newsSuccessMs < 3600000)
           && g_newsWeek == NewsWeek(NewsNY(TimeGMT()));
}

bool NewsImpactAllowed(string title, string impact) {
    StringToUpper(title);
    StringToUpper(impact);

    if (News_Impact == NEWS_RED_ONLY) return (impact == "HIGH");
    if (News_Impact == NEWS_RED_YELLOW) return (impact == "HIGH" || impact == "MEDIUM");
    if (News_Impact == NEWS_ALL) return (impact == "HIGH" || impact == "MEDIUM" || impact == "LOW");
    return false;
}

string NewsField(string row, string key) {
    int pos = StringFind(row, "\"" + key + "\"");
    if (pos < 0) return "";
    int colon = StringFind(row, ":", pos);
    if (colon < 0) return "";
    int quote1 = StringFind(row, "\"", colon);
    if (quote1 < 0) return "";
    int quote2 = StringFind(row, "\"", quote1 + 1);
    if (quote2 < 0) return "";
    return StringSubstr(row, quote1 + 1, quote2 - quote1 - 1);
}

bool NewsParseISO(string stamp, datetime &utc) {
    int n = StringLen(stamp);
    if (n != 20 && n != 25) return false;
    if (StringSubstr(stamp, 4, 1) != "-" || StringSubstr(stamp, 7, 1) != "-" ||
        StringSubstr(stamp, 10, 1) != "T" || StringSubstr(stamp, 13, 1) != ":" ||
        StringSubstr(stamp, 16, 1) != ":") return false;

    MqlDateTime d; ZeroMemory(d);
    d.year = (int)StringToInteger(StringSubstr(stamp, 0, 4));
    d.mon  = (int)StringToInteger(StringSubstr(stamp, 5, 2));
    d.day  = (int)StringToInteger(StringSubstr(stamp, 8, 2));
    d.hour = (int)StringToInteger(StringSubstr(stamp, 11, 2));
    d.min  = (int)StringToInteger(StringSubstr(stamp, 14, 2));
    d.sec  = (int)StringToInteger(StringSubstr(stamp, 17, 2));

    if (d.year < 2020 || d.mon < 1 || d.mon > 12 || d.day < 1 || d.day > 31 ||
        d.hour > 23 || d.min > 59 || d.sec > 59) return false;

    datetime local = StructToTime(d);
    MqlDateTime check; TimeToStruct(local, check);
    if (check.year != d.year || check.mon != d.mon || check.day != d.day) return false;

    int offset = 0;
    if (n == 20) {
        if (StringSubstr(stamp, 19, 1) != "Z") return false;
    } else {
        ushort sign = StringGetCharacter(stamp, 19);
        if ((sign != '+' && sign != '-') || StringSubstr(stamp, 22, 1) != ":") return false;
        int h = (int)StringToInteger(StringSubstr(stamp, 20, 2));
        int m = (int)StringToInteger(StringSubstr(stamp, 23, 2));
        if (h > 14 || m > 59) return false;
        offset = (h * 60 + m) * 60 * (sign == '+' ? 1 : -1);
    }
    utc = local - offset;
    return true;
}

bool NewsParseJSON(string json, datetime week, datetime &events[]) {
    ArrayResize(events, 0);
    StringTrimLeft(json); StringTrimRight(json);
    int size = StringLen(json);
    if (size < 2 || StringGetCharacter(json, 0) != '[' || StringGetCharacter(json, size - 1) != ']') return false;

    int start = -1;
    bool quoted = false, escape = false;

    for (int i = 1; i < size - 1; i++) {
        ushort c = StringGetCharacter(json, i);
        if (escape) { escape = false; continue; }
        if (c == '\\') { escape = true; continue; }
        if (c == '"') { quoted = !quoted; continue; }
        if (quoted) continue;

        if (c == '{') { start = i; continue; }
        if (c == '}' && start >= 0) {
            string row = StringSubstr(json, start, i - start + 1);
            start = -1;
            string title = NewsField(row, "title");
            string country = NewsField(row, "country");
            string impact = NewsField(row, "impact");
            string dateStr = NewsField(row, "date");

            if (country == "USD" && NewsImpactAllowed(title, impact)) {
                datetime utc = 0;
                if (NewsParseISO(dateStr, utc)) {
                    datetime ny = NewsNY(utc);
                    if (NewsWeek(ny) == week) {
                        int count = ArraySize(events);
                        bool dup = false;
                        for (int k = 0; k < count; k++) {
                            if (events[k] == ny) { dup = true; break; }
                        }
                        if (!dup) {
                            ArrayResize(events, count + 1);
                            events[count] = ny;
                        }
                    }
                }
            }
        }
    }
    return (ArraySize(events) >= 0);
}

void RefreshNewsFeed() {
    if (News_Impact == NEWS_DISABLED) return;
    if ((bool)MQLInfoInteger(MQL_TESTER)) {
        if (!g_newsLaunchLogged) {
            Print("[X9_NEWS] Historical news is unavailable in Strategy Tester; entry blocking stays fail-closed when enabled. Use Disabled for parity runs.");
            g_newsLaunchLogged = true;
        }
        return;
    }
    if (!(bool)TerminalInfoInteger(TERMINAL_CONNECTED)) return;

    ulong tick = GetTickCount64();
    if (g_newsAttemptMs > 0 && tick - g_newsAttemptMs < (ulong)(NewsValid() ? 1800000 : 300000)) return;

    g_newsAttemptMs = tick;
    string payload;
    datetime fetchedUtc = 0;
    bool fromCache = false;
    int status = NewsFeedGet(payload, fetchedUtc, fromCache, InpNewsCacheInTester);

    if (status != 200 || StringLen(payload) < 8) {
        if (!g_newsLaunchLogged) {
            PrintFormat("[X9_NEWS] ForexFactory unavailable (status %d); no saved snapshot yet; check the WebRequest allowlist for %s", status, NF_URL);
            g_newsLaunchLogged = true;
        }
        return;
    }

    datetime week = NewsWeek(NewsNY(TimeGMT()));
    datetime found[];

    if (!NewsParseJSON(payload, week, found)) {
        if (!g_newsLaunchLogged) Print("[X9_NEWS] ForexFactory payload invalid or wrong week");
        g_newsLaunchLogged = true;
        return;
    }

    ArraySort(found);
    ArrayCopy(g_newsEvents, found);
    g_newsWeek = week;
    g_newsReady = true;
    g_newsSuccessMs = tick;

    if (!g_newsLaunchLogged) {
        PrintFormat("[X9_NEWS] ForexFactory USD news ready: %d release events loaded for current week", ArraySize(g_newsEvents));
        g_newsLaunchLogged = true;
    }
}

bool IsInNewsBlackoutWindow(datetime nowNY) {
    if (News_Impact == NEWS_DISABLED || !NewsValid()) return false;
    if (g_newsWeek != NewsWeek(nowNY)) return false;

    // Fixed 10-minute blackout: 300 seconds before & 300 seconds after
    int windowSec = 300;

    for (int i = 0; i < ArraySize(g_newsEvents); i++) {
        if (nowNY >= g_newsEvents[i] - windowSec && nowNY <= g_newsEvents[i] + windowSec) {
            return true;
        }
    }
    return false;
}

bool IsInX9NewsFlattenWindow(datetime nowNY) {
    if (News_Impact == NEWS_DISABLED || !News_Flatten_Before || !NewsValid()) return false;
    if (g_newsWeek != NewsWeek(nowNY) || News_Flatten_Min < 0) return false;
    long leadSec = (long)News_Flatten_Min * 60;
    for (int i = 0; i < ArraySize(g_newsEvents); i++) {
        if (nowNY >= g_newsEvents[i] - leadSec && nowNY <= g_newsEvents[i]) return true;
    }
    return false;
}

bool IsX9NewsManagementFrozen() {
    return News_Impact != NEWS_DISABLED && News_Freeze_Management && IsInNewsBlackoutWindow(NewsNY(TimeGMT()));
}

void EvaluateNewsControls() {
    if (News_Impact == NEWS_DISABLED) {
        g_newsBlocked = false;
        g_newsFlattenActive = false;
        return;
    }
    // Compare feed and current time in the same live UTC-derived NY clock.
    datetime nowNY = NewsNY(TimeGMT());
    g_newsBlocked = IsInNewsBlackoutWindow(nowNY);
    g_newsFlattenActive = IsInX9NewsFlattenWindow(nowNY);
    bool cancelPending = (g_newsBlocked && News_Cancel_Pending) || g_newsFlattenActive;
    if (!cancelPending && !g_newsFlattenActive) return;

    // Retry rejected/partial actions against current inventory, at most once/sec.
    ulong tick = GetTickCount64();
    if (g_newsActionAttemptMs > 0 && tick - g_newsActionAttemptMs < 1000) return;
    g_newsActionAttemptMs = tick;
    if (cancelPending) CancelAllX9PendingOrders();
    if (g_newsFlattenActive) CloseAllX9OpenPositions();
}

//+------------------------------------------------------------------+
//| Drawdown Controls & Actions Engine                               |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Market session gate                                              |
//| A closed market is not a failed order. Management and entries     |
//| refuse quietly - one line per session change, never per ticket - |
//| and the intent survives: the next tick after the open acts again.|
//+------------------------------------------------------------------+
datetime g_mktClosedLoggedDate = 0;
bool X9MarketOpen() {
    MqlDateTime dt;
    TimeToStruct(TimeTradeServer(), dt);
    datetime from = 0, to = 0;
    if(!SymbolInfoSessionTrade(TradeSym, (ENUM_DAY_OF_WEEK)dt.day_of_week, 0, from, to))
        return false;                                  // no session declared today
    long sec = (long)dt.hour * 3600 + dt.min * 60 + dt.sec;
    return (sec >= (long)from && sec <= (long)to);
}
void X9NoteClosed(string what, int pending) {
    MqlDateTime dt;
    TimeToStruct(TimeTradeServer(), dt);
    datetime day = (datetime)dt.year * 10000 + dt.mon * 100 + dt.day;
    if(g_mktClosedLoggedDate == day) return;            // one line per day, not per attempt
    g_mktClosedLoggedDate = day;
    PrintFormat("[X9_SESSION] market closed: %s deferred, %d item(s) retained; retried after the open", what, pending);
}

void CancelAllX9PendingOrders() {
    if (!X9MarketOpen()) { X9NoteClosed("pending cancel", OrdersTotal()); return; }
    for (int i = OrdersTotal() - 1; i >= 0; i--) {
        if (ordinfo.SelectByIndex(i)) {
            if (IsX9Magic(ordinfo.Magic()) && ordinfo.Symbol() == TradeSym) {
                ulong ticket = ordinfo.Ticket();
                bool submitted = trade.OrderDelete(ticket);
                uint result = trade.ResultRetcode();
                if (!submitted || result != TRADE_RETCODE_DONE) {
                    PrintFormat("[X9_ACTION] Pending cancel #%I64u not confirmed: %u %s", ticket,
                                result, trade.ResultRetcodeDescription());
                }
            }
        }
    }
}

void CloseAllX9OpenPositions() {
    if (!X9MarketOpen()) { X9NoteClosed("position close", PositionsTotal()); return; }
    // Netting merges symbol exposure: a position magic cannot prove ownership.
    if (AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING) {
        if (!g_nettingCloseLogged) {
            Print("[X9_ACTION] Position flattening skipped: X9 close controls require a hedging account; netting ownership is not isolated.");
            g_nettingCloseLogged = true;
        }
        return;
    }
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        if (posinfo.SelectByIndex(i)) {
            if (IsX9Magic(posinfo.Magic()) && posinfo.Symbol() == TradeSym) {
                ulong ticket = posinfo.Ticket();
                trade.SetExpertMagicNumber((ulong)posinfo.Magic());
                bool submitted = trade.PositionClose(ticket);
                uint result = trade.ResultRetcode();
                if (!submitted || (result != TRADE_RETCODE_DONE && result != TRADE_RETCODE_DONE_PARTIAL)) {
                    PrintFormat("[X9_ACTION] Position close #%I64u not confirmed: %u %s", ticket,
                                result, trade.ResultRetcodeDescription());
                }
            }
        }
    }
}

void EvaluateDrawdownControls() {
    double currentVal = (DDBasis == DD_BASIS_EQUITY) ? AccountInfoDouble(ACCOUNT_EQUITY) : AccountInfoDouble(ACCOUNT_BALANCE);

    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);

    // 1. Daily Reset Check
    int currentDayKey = dt.year * 10000 + dt.mon * 100 + dt.day;
    if (currentDayKey != g_lastDailyDay) {
        g_lastDailyDay = currentDayKey;
        g_dailyStartBasis = currentVal;
        g_dailyBreached = false;
    }

    if (g_dailyStartBasis <= 0.0) g_dailyStartBasis = currentVal;

    // Exclude signed deposits, withdrawals, and broker corrections from daily/total basis shifts if needed,
    // but here we keep breach latches and use currentVal.
    // 2. Daily Drawdown Check
    if (MaxDailyDDPercent > 0.0 && g_dailyStartBasis > 0.0) {
        double dailyDropPct = (g_dailyStartBasis - currentVal) / g_dailyStartBasis * 100.0;
        if (dailyDropPct >= MaxDailyDDPercent) {
            if (!g_dailyBreached) {
                g_dailyBreached = true;
                PrintFormat("[X9_DD] DAILY DD BREACH: Drop %.2f%% >= Max %.2f%% | Basis=%.2f -> Current=%.2f",
                            dailyDropPct, MaxDailyDDPercent, g_dailyStartBasis, currentVal);

                if (DDAction == DD_ACTION_CLOSE_EVERYTHING) {
                    CancelAllX9PendingOrders();
                    CloseAllX9OpenPositions();
                } else if (DDAction == DD_ACTION_NO_NEW_TRADES) {
                    CancelAllX9PendingOrders();
                }
            }
        }
    }

    // 3. Total Drawdown Check
    if (InpTotalDDResetID != g_lastTotalDDResetID) {
        g_lastTotalDDResetID = InpTotalDDResetID;
        if (g_totalBreached) {
            g_totalBreached = false;
            X9PersistTotalDDLatch();
            PrintFormat("[X9_DD] Persistent TOTAL DD lock explicitly reset. Reset ID=%d.", InpTotalDDResetID);
        }
    }
    if (MaxTotalDDPercent > 0.0 && !g_totalBreached) {
        double referenceBasis = 0.0;

        if (DDMode == DD_MODE_DYNAMIC) {
            if (currentVal > g_peakBasis) g_peakBasis = currentVal;
            referenceBasis = g_peakBasis;
        } else { // Static
            if (StaticDDBalance > 0.0) {
                referenceBasis = StaticDDBalance;
            } else {
                if (g_staticFloorBasis <= 0.0) g_staticFloorBasis = currentVal;
                referenceBasis = g_staticFloorBasis;
            }
        }

        if (referenceBasis > 0.0) {
            double totalDropPct = (referenceBasis - currentVal) / referenceBasis * 100.0;
            if (totalDropPct >= MaxTotalDDPercent) {
                if (!g_totalBreached) {
                    g_totalBreached = true;
                    X9PersistTotalDDLatch();
                    PrintFormat("[X9_DD] TOTAL DD BREACH: Drop %.2f%% >= Max %.2f%% | RefBasis=%.2f -> Current=%.2f",
                                totalDropPct, MaxTotalDDPercent, referenceBasis, currentVal);

                    if (DDAction == DD_ACTION_CLOSE_EVERYTHING) {
                        CancelAllX9PendingOrders();
                        CloseAllX9OpenPositions();
                    } else if (DDAction == DD_ACTION_NO_NEW_TRADES) {
                        CancelAllX9PendingOrders();
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Master Entry Permission Gate                                     |
//+------------------------------------------------------------------+
bool CanPlaceNewX9Entries() {
    if (!X9MarketOpen()) { X9NoteClosed("new entries", 0); return false; }
    RefreshNewsFeed();
    EvaluateNewsControls();
    EvaluateDrawdownControls();

    if (g_dailyBreached || g_totalBreached) return false;

    // Flatten includes cancel/block so the EA cannot reopen before the release.
    if (g_newsFlattenActive) return false;
    if (News_Impact != NEWS_DISABLED && News_Block_Entries && (!NewsValid() || g_newsBlocked)) return false;

    return true;
}
