#ifndef GF_EXECUTION_RUNTIME
#define GF_EXECUTION_RUNTIME
// ExecutionRuntime.mqh - Gotobi Fix
// Author: Osamwonyi Eric (@You_FoundEric)
// Copyright 2026-2027, Osamwonyi Eric (@You_FoundEric)
//
// Market-access adapter. Everything that touches the terminal lives here: standard clock adapter (CLK-ADAPTER),
// ownership, sizing validation, order send/confirm, exact-position closes, recovery, journal.
// Requires the shell's inputs (declared in GotobiFix.mq5 before this include).
#include "StrategyEngine.mqh"

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

// ---- state --------------------------------------------------------------------------------------------
int      gfLease=INVALID_HANDLE;
bool     gfRecoveryReady=false;
datetime gfRecoveryRetry=0;
bool     gfTxDirty=true;
bool     gfStorageFault=false;
string   gfNote="";                     // last status for the panel
datetime gfLogAt=0; string gfLogLast="";

int      gfLegYmd[2];                   // Tokyo gotobi date each leg state belongs to
int      gfLegState[2];                 // 0 idle, 1 request in flight/unresolved, 2 filled, 9 blocked for the day
datetime gfLegTime[2];                  // server time of the last request
int      gfLegAttempts[2];
datetime gfLegNextTry[2];
int      gfFixLogYmd=0;

ulong    gfOwned[];                     // owned position tickets on this symbol
int      gfOwnedN=0;
double   gfOwnedVol=0;
bool     gfScanOK=true;

struct GfTrack
{
   ulong    ticket;  ulong id;  int leg;  int ymd;
   datetime sentServer;  double model;  double spreadPts;  int lateSec;
   string   reason;  int slTries;
};
GfTrack gfTrk[];
struct GfSend { bool valid; int leg; int ymd; datetime sentServer; double model; double spreadPts; int lateSec; };
GfSend gfLastSend[2];

// ---- small helpers ---------------------------------------------------------------------------------------
void GfLog(string msg)                       // de-duplicated journal line
{
   datetime t=TimeLocal();
   if(msg==gfLogLast && t-gfLogAt<60) return;
   gfLogLast=msg; gfLogAt=t; Print(msg);
}
uint GfHash(string s)
{ uint h=2166136261; for(int i=0;i<StringLen(s);i++) h=(h^(uint)StringGetCharacter(s,i))*16777619; return h; }
string GfScope()
{
   return "GF."+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+"."+
          IntegerToString(GfHash(AccountInfoString(ACCOUNT_SERVER)+"|"+_Symbol))+"."+IntegerToString(Magic);
}
bool GfPersist(string key,double value)
{
   if(GlobalVariableSet(key,value)==0){ gfStorageFault=true; GfLog("GF_STORAGE_FAILED key="+key); return false; }
   return true;
}
double GfPipSize() { return (_Digits==3 || _Digits==5) ? 10.0*_Point : _Point; }
double GfSnap(double price,int dir)          // dir +1 up, -1 down, 0 nearest; snaps to the trade tick grid
{
   double ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(ts<=0) return 0;
   double n=price/ts;
   n = dir>0 ? MathCeil(n-1e-9) : dir<0 ? MathFloor(n+1e-9) : MathRound(n);
   return NormalizeDouble(n*ts,_Digits);
}
bool GfQuoteFresh(MqlTick &q)
{
   if(!SymbolInfoTick(_Symbol,q) || q.bid<=0 || q.ask<q.bid || q.time<=0) return false;
   if(MQLInfoInteger(MQL_TESTER)) return true;
   datetime now=TimeTradeServer();
   return now>=q.time && now-q.time<=15;
}
bool GfSymbolMetaOK()
{
   return SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE)>0 && SymbolInfoDouble(_Symbol,SYMBOL_POINT)>0 &&
          SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP)>0 && SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN)>0 &&
          SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX)>0 && _Digits>0;
}
// Fixed lots must be finite, positive, inside min/max and exactly on the volume grid. Never rounded.
bool GfLotsValid(double lots)
{
   if(!MathIsValidNumber(lots) || lots<=0 || !GfSymbolMetaOK()) return false;
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double mn=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN), mx=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   if(lots<mn-1e-12 || lots>mx+1e-12) return false;
   double k=(lots-mn)/step;
   return MathAbs(k-MathRound(k))<1e-6;
}
bool GfDefinitiveReject(uint rc)
{
   return rc==TRADE_RETCODE_REQUOTE || rc==TRADE_RETCODE_REJECT || rc==TRADE_RETCODE_CANCEL || rc==TRADE_RETCODE_PRICE_CHANGED ||
          rc==TRADE_RETCODE_PRICE_OFF || rc==TRADE_RETCODE_INVALID || rc==TRADE_RETCODE_INVALID_VOLUME ||
          rc==TRADE_RETCODE_INVALID_PRICE || rc==TRADE_RETCODE_INVALID_STOPS || rc==TRADE_RETCODE_TRADE_DISABLED ||
          rc==TRADE_RETCODE_MARKET_CLOSED || rc==TRADE_RETCODE_NO_MONEY || rc==TRADE_RETCODE_TOO_MANY_REQUESTS ||
          rc==TRADE_RETCODE_INVALID_FILL || rc==TRADE_RETCODE_CLOSE_ONLY || rc==TRADE_RETCODE_LIMIT_ORDERS ||
          rc==TRADE_RETCODE_LIMIT_VOLUME || rc==TRADE_RETCODE_FROZEN || rc==TRADE_RETCODE_INVALID_EXPIRATION;
}
bool GfCheckOK(MqlTradeCheckResult &ck) { return ck.retcode==0 || ck.retcode==TRADE_RETCODE_DONE; }
// Choose a filling mode the symbol supports AND that OrderCheck accepts for this exact request.
bool GfPickFilling(MqlTradeRequest &rq,bool mustPass)
{
   int fm=(int)SymbolInfoInteger(_Symbol,SYMBOL_FILLING_MODE);
   long exe=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_EXEMODE);
   ENUM_ORDER_TYPE_FILLING cand[3]; int n=0;
   if((fm & SYMBOL_FILLING_FOK)!=0) cand[n++]=ORDER_FILLING_FOK;
   if((fm & SYMBOL_FILLING_IOC)!=0) cand[n++]=ORDER_FILLING_IOC;
   if(exe!=SYMBOL_TRADE_EXECUTION_MARKET && n<3) cand[n++]=ORDER_FILLING_RETURN;
   if(n==0) return false;
   for(int i=0;i<n;i++)
   {
      rq.type_filling=cand[i];
      MqlTradeCheckResult ck; ZeroMemory(ck);
      if(OrderCheck(rq,ck) && GfCheckOK(ck)) return true;
   }
   if(!mustPass) { rq.type_filling=cand[0]; return true; }   // closes: always attempt with a supported mode
   return false;
}
// ---- ownership ----------------------------------------------------------------------------------------------------
// Hedging accounts only (enforced at init): every position is its own ticket, so ownership is exact: this symbol +
// our magic. Other EAs' positions on the same symbol are independent and never touched.
void GfScan()
{
   ArrayResize(gfOwned,0); gfOwnedN=0; gfOwnedVol=0; gfScanOK=true;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t==0) { gfScanOK=false; continue; }
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol || (ulong)PositionGetInteger(POSITION_MAGIC)!=(ulong)Magic) continue;
      ArrayResize(gfOwned,gfOwnedN+1); gfOwned[gfOwnedN++]=t; gfOwnedVol+=PositionGetDouble(POSITION_VOLUME);
   }
}
int GfFindTrack(ulong ticket)
{
   for(int i=0;i<ArraySize(gfTrk);i++) if(gfTrk[i].ticket==ticket) return i;
   return -1;
}
void GfSetReason(ulong ticket,string why)
{
   int k=GfFindTrack(ticket);
   if(k>=0 && gfTrk[k].reason=="") gfTrk[k].reason=why;
}
// Start tracking owned positions we have not seen (fresh fills, or positions found after a restart).
void GfAdopt()
{
   for(int i=0;i<gfOwnedN;i++)
   {
      ulong t=gfOwned[i];
      if(GfFindTrack(t)>=0 || !PositionSelectByTicket(t)) continue;
      GfTrack k;
      k.ticket=t; k.id=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
      k.leg=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)?0:1;
      datetime opened=(datetime)PositionGetInteger(POSITION_TIME);
      datetime u=ClkStampToUtc(opened);
      k.ymd=u>0?GfTokyoYmd(u):0;
      k.reason=""; k.slTries=0; k.model=0; k.spreadPts=0; k.lateSec=-1; k.sentServer=0;
      if(gfLastSend[k.leg].valid && gfLastSend[k.leg].ymd==k.ymd && opened>=gfLastSend[k.leg].sentServer-2)
      {
         k.model=gfLastSend[k.leg].model; k.spreadPts=gfLastSend[k.leg].spreadPts;
         k.lateSec=gfLastSend[k.leg].lateSec; k.sentServer=gfLastSend[k.leg].sentServer;
      }
      int n=ArraySize(gfTrk); ArrayResize(gfTrk,n+1); gfTrk[n]=k;
      PrintFormat("GF_ADOPT ticket=%I64u id=%I64u leg=%s tokyo=%d volume=%.2f",t,k.id,k.leg==0?"LONG":"SHORT",k.ymd,PositionGetDouble(POSITION_VOLUME));
   }
}
// ---- leg state (persisted) -----------------------------------------------------------------------------------
string GfLegKey(int leg) { return GfScope()+".leg"+IntegerToString(leg); }
void GfLegSave(int leg)
{
   GfPersist(GfLegKey(leg),(double)gfLegYmd[leg]*10.0+gfLegState[leg]);
   GfPersist(GfLegKey(leg)+".t",(double)gfLegTime[leg]);
   GlobalVariablesFlush();
}
void GfLegLoad()
{
   for(int l=0;l<2;l++)
   {
      gfLegYmd[l]=0; gfLegState[l]=0; gfLegTime[l]=0; gfLegAttempts[l]=0; gfLegNextTry[l]=0; gfLastSend[l].valid=false;
      if(GlobalVariableCheck(GfLegKey(l)))
      {
         double v=GlobalVariableGet(GfLegKey(l));
         gfLegYmd[l]=(int)MathFloor(v/10.0); gfLegState[l]=(int)MathRound(v-gfLegYmd[l]*10.0);
         gfLegTime[l]=(datetime)GlobalVariableGet(GfLegKey(l)+".t");
      }
   }
}
void GfLegRollover(int ymd)                  // a new Tokyo gotobi date starts both legs clean
{
   for(int l=0;l<2;l++)
      if(gfLegYmd[l]!=ymd) { gfLegYmd[l]=ymd; gfLegState[l]=0; gfLegAttempts[l]=0; gfLegNextTry[l]=0; gfLegTime[l]=0; GfLegSave(l); }
}
// ---- exact-position close with persisted intent ------------------------------------------------------------------
// A timeout or missing acknowledgement never authorises a second close request: the position stays "in flight"
// until history proves the close order settled.
string GfCloseKey(ulong id) { return GfScope()+".C"+IntegerToString((long)id); }
bool GfCloseSettled(string key,double vol,ulong id)
{
   ulong order=((ulong)(uint)GlobalVariableGet(key+".hi")<<32)|(ulong)(uint)GlobalVariableGet(key+".lo");
   if(!HistorySelectByPosition(id)) return false;
   if(order==0)
   {
      long since=(long)GlobalVariableGet(key+".time");
      for(int i=0;i<HistoryDealsTotal();i++)
      {
         ulong deal=HistoryDealGetTicket(i);
         long kind=HistoryDealGetInteger(deal,DEAL_ENTRY);
         if((kind!=DEAL_ENTRY_OUT && kind!=DEAL_ENTRY_OUT_BY) || (ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=(ulong)Magic ||
            HistoryDealGetInteger(deal,DEAL_TIME_MSC)<since) continue;
         ulong found=(ulong)HistoryDealGetInteger(deal,DEAL_ORDER);
         if(order!=0 && order!=found) return false;
         order=found;
      }
      if(order>0) { GfPersist(key+".hi",(double)(uint)(order>>32)); GfPersist(key+".lo",(double)(uint)order); GlobalVariablesFlush(); }
   }
   if(order==0 || OrderSelect(order) || !HistoryOrderSelect(order)) return false;
   if(HistoryOrderGetString(order,ORDER_SYMBOL)!=_Symbol || (ulong)HistoryOrderGetInteger(order,ORDER_MAGIC)!=(ulong)Magic ||
      (ulong)HistoryOrderGetInteger(order,ORDER_POSITION_ID)!=id) return false;
   long st=HistoryOrderGetInteger(order,ORDER_STATE);
   if(st!=ORDER_STATE_FILLED && st!=ORDER_STATE_CANCELED && st!=ORDER_STATE_REJECTED && st!=ORDER_STATE_EXPIRED) return false;
   double filled=HistoryOrderGetDouble(order,ORDER_VOLUME_INITIAL)-HistoryOrderGetDouble(order,ORDER_VOLUME_CURRENT);
   return vol<=GlobalVariableGet(key+".volume")-filled+SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP)*0.5;
}
void GfClose(ulong ticket,string why)
{
   if(gfStorageFault) { GfLog("GF_CLOSE_BLOCKED durable storage fault; manual flatten required"); return; }
   if(!PositionSelectByTicket(ticket)) return;
   ulong id=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
   double vol=PositionGetDouble(POSITION_VOLUME);
   long ptype=PositionGetInteger(POSITION_TYPE);
   string key=GfCloseKey(id);
   if(GlobalVariableCheck(key+".active"))
   {
      if(!GfCloseSettled(key,vol,id))
      { GfLog(StringFormat("GF_CLOSE_UNRESOLVED position=%I64u awaiting proof of prior close request; NO duplicate sent",id)); return; }
      GlobalVariableDel(key+".active"); GlobalVariablesFlush();
   }
   MqlTick q;
   if(!SymbolInfoTick(_Symbol,q) || q.bid<=0 || q.ask<=0) return;
   MqlTradeRequest rq; MqlTradeResult rs; ZeroMemory(rq); ZeroMemory(rs);
   rq.action=TRADE_ACTION_DEAL; rq.symbol=_Symbol; rq.volume=vol; rq.position=ticket; rq.magic=(ulong)Magic;
   rq.type=(ptype==POSITION_TYPE_BUY)?ORDER_TYPE_SELL:ORDER_TYPE_BUY;
   rq.price=(ptype==POSITION_TYPE_BUY)?q.bid:q.ask;
   rq.deviation=(ulong)DeviationPts; rq.comment="GF close "+why;
   GfPickFilling(rq,false);
   GfSetReason(ticket,why);
   if(!GfPersist(key+".time",(double)q.time_msc) || !GfPersist(key+".volume",vol) || !GfPersist(key+".hi",0) ||
      !GfPersist(key+".lo",0) || !GfPersist(key+".active",1)) return;
   GlobalVariablesFlush();                      // intent precedes submission
   bool sent=OrderSend(rq,rs);
   uint rc=rs.retcode;
   if(rs.order>0) { GfPersist(key+".hi",(double)(uint)(rs.order>>32)); GfPersist(key+".lo",(double)(uint)rs.order); }
   bool done=(rc==TRADE_RETCODE_DONE || rc==TRADE_RETCODE_DONE_PARTIAL);
   bool ambiguous=(rc==0 || rc==TRADE_RETCODE_TIMEOUT || rc==TRADE_RETCODE_CONNECTION || rc==TRADE_RETCODE_PLACED || rc==TRADE_RETCODE_ERROR);
   if(!done && !ambiguous) GlobalVariableDel(key+".active");   // definitive failure: next pass may retry
   GlobalVariablesFlush();
   if(!MQLInfoInteger(MQL_TESTER) || !(sent && done))
      PrintFormat("GF_CLOSE_%s position=%I64u reason=%s retcode=%u detail=%s",(sent&&done)?"REQUEST":"RETRY",id,why,rc,rs.comment);
}
// ---- exits ---------------------------------------------------------------------------------------------------
// Optional broker-side catastrophic stop (DisasterStopPips>0). The strategy itself has no stop: this exists only
// so an EA/VPS outage cannot leave an unbounded position. Verified by readback; unattachable -> flatten.
bool GfDisasterStopFor(bool isLong,double ref,double &sl)
{
   double dist=DisasterStopPips*GfPipSize();
   sl=isLong?GfSnap(ref-dist,-1):GfSnap(ref+dist,+1);
   return sl>0;
}
void GfEnsureProtection(ulong ticket)
{
   if(DisasterStopPips<=0 || !PositionSelectByTicket(ticket)) return;
   double cur=PositionGetDouble(POSITION_SL);
   if(cur>0) return;
   bool isLong=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
   double sl; if(!GfDisasterStopFor(isLong,PositionGetDouble(POSITION_PRICE_OPEN),sl)) return;
   int k=GfFindTrack(ticket);
   if(k>=0 && gfTrk[k].slTries>=3) { GfClose(ticket,"protect_fail"); return; }   // explicit fail-safe: no protection -> flat
   MqlTradeRequest rq; MqlTradeResult rs; ZeroMemory(rq); ZeroMemory(rs);
   rq.action=TRADE_ACTION_SLTP; rq.symbol=_Symbol; rq.position=ticket; rq.sl=sl; rq.tp=PositionGetDouble(POSITION_TP); rq.magic=(ulong)Magic;
   bool sent=OrderSend(rq,rs);
   if(k>=0) gfTrk[k].slTries++;
   PrintFormat("GF_PROTECT ticket=%I64u sl=%.5f sent=%d retcode=%u",ticket,sl,sent,rs.retcode);
}
void GfManageExits(datetime nowS,datetime nowUtc)
{
   for(int i=0;i<gfOwnedN;i++)
   {
      ulong t=gfOwned[i];
      if(!PositionSelectByTicket(t)) continue;
      bool isLong=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      datetime openUtc=ClkStampToUtc((datetime)PositionGetInteger(POSITION_TIME));
      string why="";
      if(!ClkOK() || nowUtc<=0 || openUtc<=0)      why="clock_unverified";            // genuine clock conflict: flat is the fail-safe
      else if(!GfIsGotobiUtc(openUtc))              why="orphan";
      else if(nowUtc>=GfLegDeadlineUtc(openUtc,isLong)) why=isLong?"fix_0955":"flat_1030";
      else if(MaxFloatingLossMoney>0 && PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP)<=-MaxFloatingLossMoney)
                                                    why="risk_cap";
      if(why!="")
      {
         if(why=="risk_cap") { for(int l=0;l<2;l++) { gfLegState[l]=9; GfLegSave(l); } GfLog("GF_RISK_CAP floating loss cap hit; both legs blocked for the day"); }
         GfClose(t,why);
      }
      else GfEnsureProtection(t);
   }
}
// ---- leg reconciliation -------------------------------------------------------------------------------------------
void GfReconcileLegs(datetime nowS)
{
   for(int l=0;l<2;l++)
   {
      if(gfLegState[l]!=1) continue;
      bool found=false;
      for(int i=0;i<gfOwnedN && !found;i++)
         if(PositionSelectByTicket(gfOwned[i]) && (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)==(l==0) &&
            (datetime)PositionGetInteger(POSITION_TIME)>=gfLegTime[l]-5) found=true;
      if(!found && nowS-gfLegTime[l]>=90 && HistorySelect(gfLegTime[l]-60,nowS+3600))
         for(int i=0;i<HistoryDealsTotal() && !found;i++)
         {
            ulong d=HistoryDealGetTicket(i);
            if(d==0 || HistoryDealGetString(d,DEAL_SYMBOL)!=_Symbol || (ulong)HistoryDealGetInteger(d,DEAL_MAGIC)!=(ulong)Magic ||
               HistoryDealGetInteger(d,DEAL_ENTRY)!=DEAL_ENTRY_IN) continue;
            long ty=HistoryDealGetInteger(d,DEAL_TYPE);
            if((l==0 && ty==DEAL_TYPE_BUY) || (l==1 && ty==DEAL_TYPE_SELL)) found=true;
         }
      if(found) { gfLegState[l]=2; GfLegSave(l); }
      else if(nowS-gfLegTime[l]>=90 && gfScanOK)
      {
         gfLegState[l]=9; GfLegSave(l);
         GfLog(StringFormat("GF_LEG_UNRESOLVED leg=%s no fill evidence 90s after request; blocked for this gotobi day (no duplicate)",l==0?"LONG":"SHORT"));
      }
   }
}
// ---- entries -------------------------------------------------------------------------------------------------------
bool GfTradingAllowed()
{
   if(!EnableTrading) { gfNote="trading disabled by input"; return false; }
   if(!MQLInfoInteger(MQL_TESTER))
   {
      if(!TerminalInfoInteger(TERMINAL_CONNECTED)) { gfNote="terminal disconnected"; return false; }
      if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED)) { gfNote="algo trading off"; return false; }
      if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) || !AccountInfoInteger(ACCOUNT_TRADE_EXPERT)) { gfNote="account/expert trading not allowed"; return false; }
   }
   if(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_MODE)!=SYMBOL_TRADE_MODE_FULL) { gfNote="symbol not fully tradable"; return false; }
   if(!GfSymbolMetaOK()) { gfNote="symbol metadata invalid"; return false; }
   return true;
}
bool GfEnter(int leg,int ymd,datetime nowS,datetime windowStartUtc,datetime nowUtc)
{
   bool isLong=(leg==0);
   MqlTick q;
   if(!GfQuoteFresh(q)) { gfNote="no fresh quote"; return false; }
   if(!GfLotsValid(Lots)) { gfNote="Lots invalid for symbol grid"; GfLog("GF_ENTRY_SKIP Lots not on the volume grid/min/max"); return false; }
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(gfOwnedVol+Lots>MaxExposureLots+step*0.5) { gfNote="exposure guard"; GfLog("GF_ENTRY_SKIP exposure guard"); return false; }
   int lateSec=(int)(nowUtc-windowStartUtc);
   if(MaxLateEntrySec>0 && lateSec>MaxLateEntrySec) { gfNote="late-entry cap"; return false; }
   double spreadPts=(q.ask-q.bid)/_Point;
   if(MaxEntrySpreadPips>0 && spreadPts>MaxEntrySpreadPips*GfPipSize()/_Point) { gfNote="spread above cap"; return false; }
   MqlTradeRequest rq; MqlTradeResult rs; ZeroMemory(rq); ZeroMemory(rs);
   rq.action=TRADE_ACTION_DEAL; rq.symbol=_Symbol; rq.volume=Lots; rq.magic=(ulong)Magic;
   rq.type=isLong?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   rq.price=isLong?q.ask:q.bid; rq.deviation=(ulong)DeviationPts;
   rq.comment=StringFormat("GF %s %d",isLong?"L":"S",ymd);
   if(DisasterStopPips>0)
   {
      double sl; if(!GfDisasterStopFor(isLong,rq.price,sl)) { gfNote="stop calc failed"; return false; }
      double lvl=(double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point, frz=(double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL)*_Point;
      double dist=isLong?(q.bid-sl):(sl-q.ask);
      if(dist<MathMax(lvl,frz)) { gfNote="disaster stop inside broker stops level"; GfLog("GF_ENTRY_SKIP DisasterStopPips violates stops/freeze level; not widened"); return false; }
      rq.sl=sl;
   }
   double margin=0;
   if(!OrderCalcMargin(rq.type,_Symbol,Lots,rq.price,margin) || margin<=0) { gfNote="margin calc unavailable"; gfLegNextTry[leg]=nowS+5; return false; }
   if(margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE)) { gfNote="insufficient free margin"; GfLog("GF_ENTRY_SKIP free margin below required margin"); gfLegNextTry[leg]=nowS+5; return false; }
   if(!GfPickFilling(rq,true)) { gfNote="OrderCheck rejected request"; gfLegNextTry[leg]=nowS+5; return false; }

   gfLegYmd[leg]=ymd; gfLegState[leg]=1; gfLegTime[leg]=nowS; GfLegSave(leg);      // intent precedes submission
   gfLastSend[leg].valid=true; gfLastSend[leg].leg=leg; gfLastSend[leg].ymd=ymd; gfLastSend[leg].sentServer=nowS;
   gfLastSend[leg].model=rq.price; gfLastSend[leg].spreadPts=spreadPts; gfLastSend[leg].lateSec=lateSec;
   bool sent=OrderSend(rq,rs);
   uint rc=rs.retcode;
   PrintFormat("GF_ENTRY_%s leg=%s tokyo=%d lots=%.2f price=%.5f spreadPts=%.1f lateSec=%d retcode=%u detail=%s",
               (sent&&(rc==TRADE_RETCODE_DONE||rc==TRADE_RETCODE_DONE_PARTIAL))?"FILLED":"RESULT",isLong?"LONG":"SHORT",ymd,Lots,rq.price,spreadPts,lateSec,rc,rs.comment);
   if(rc==TRADE_RETCODE_DONE || rc==TRADE_RETCODE_DONE_PARTIAL) { gfLegState[leg]=2; GfLegSave(leg); return true; }
   if(GfDefinitiveReject(rc))
   {
      gfLegState[leg]=0; gfLegAttempts[leg]++; gfLegNextTry[leg]=nowS+2;
      if(gfLegAttempts[leg]>=3) { gfLegState[leg]=9; GfLog("GF_LEG_BLOCKED max definitive rejections; blocked for the day"); }
      GfLegSave(leg); return false;
   }
   return true;                                  // PLACED / timeout / unknown: stays in flight (state 1) until history proves it
}
void GfEntries(datetime nowS,datetime nowUtc)
{
   if(!ClkEntryOK() || nowUtc<=0) { gfNote=ClkNote(); return; }
   int ymd=0; int phase=GfSignalPhase(nowUtc,ymd);
   if(phase==GF_PHASE_UNKNOWN) { gfNote="calendar year unsupported"; GfLog("GF_CALENDAR_UNSUPPORTED year outside 2007-2099; entries disabled"); return; }
   GfLegRollover(ymd);
   if(phase==GF_PHASE_IDLE) { gfNote="idle"; return; }
   if(phase==GF_PHASE_SHORT && gfFixLogYmd!=ymd)
   {
      gfFixLogYmd=ymd; MqlTick qs;
      if(SymbolInfoTick(_Symbol,qs)) PrintFormat("GF_FIX_SPREAD tokyo=%d spreadPts=%.1f server=%s",ymd,(qs.ask-qs.bid)/_Point,TimeToString(nowS,TIME_DATE|TIME_SECONDS));
   }
   if(!gfRecoveryReady) { gfNote="recovery: waiting for owned history"; return; }
   if(!GfTradingAllowed()) return;
   if(!gfScanOK) { gfNote="position scan incomplete"; return; }
   if(gfStorageFault) { gfNote="durable storage fault"; return; }
   int leg=(phase==GF_PHASE_LONG)?0:1;
   if(leg==0 && Legs==GF_LEGS_SHORT) { gfNote="long leg disabled"; return; }
   if(leg==1 && Legs==GF_LEGS_LONG)  { gfNote="short leg disabled"; return; }
   if(gfLegState[leg]!=0) { gfNote=StringFormat("%s leg state %d",leg==0?"LONG":"SHORT",gfLegState[leg]); return; }
   if(nowS<gfLegNextTry[leg]) return;
   if(leg==1 && gfOwnedN>0) { gfNote="waiting for long to close before short"; return; }   // never flip into a net position
   if(leg==0 && gfOwnedN>0) { gfNote="owned exposure already open"; return; }
   datetime start=GfTokyoToUtc(ymd,leg==0?GF_LONG_MIN:GF_FIX_MIN);
   GfEnter(leg,ymd,nowS,start,nowUtc);
}
// ---- journal -------------------------------------------------------------------------------------------------------
string GfPx(double v) { return DoubleToString(v,_Digits); }
string GfSrvStr(datetime server) { return TimeToString(server,TIME_DATE|TIME_SECONDS); }
string GfUtcStr(datetime server)
{ datetime u=ClkStampToUtc(server); return u>0?TimeToString(u,TIME_DATE|TIME_SECONDS):"unresolved"; }
string GfTokyoStr(datetime server)
{ datetime u=ClkStampToUtc(server); return u>0?TimeToString(u+GF_JST_SEC,TIME_DATE|TIME_SECONDS):"unresolved"; }
string GfJournalName() { return JournalFile+(MQLInfoInteger(MQL_TESTER)?".tester":"")+".csv"; }
void GfJournalWrite(GfTrack &k,datetime openT,datetime closeT,double vol,double openPx,double closePx,double profit,double comm,double swap)
{
   int h=FileOpen(GfJournalName(),FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ,',');
   if(h==INVALID_HANDLE) { PrintFormat("GF_JOURNAL_FAILED error=%d",GetLastError()); return; }
   if(FileSize(h)==0)
      FileWrite(h,"version","symbol","magic","clock_rule","clock_base_min","clock_source","tokyo_gotobi_date","leg","position_id","open_server","open_utc","open_tokyo",
                "close_server","close_utc","close_tokyo","volume","model_open","fill_open","fill_close","spread_pts_at_send","late_entry_sec",
                "exit_reason","commission","swap","gross_profit","net_profit","account_ccy");
   FileSeek(h,0,SEEK_END);
   FileWrite(h,"1.00",_Symbol,Magic,ClkRule(),ClkBase(),ClkSource(),k.ymd,k.leg==0?"LONG":"SHORT",(long)k.id,GfSrvStr(openT),GfUtcStr(openT),GfTokyoStr(openT),GfSrvStr(closeT),GfUtcStr(closeT),GfTokyoStr(closeT),
             DoubleToString(vol,2),k.model>0?GfPx(k.model):"",GfPx(openPx),GfPx(closePx),DoubleToString(k.spreadPts,1),
             k.lateSec,k.reason==""?"unrecorded":k.reason,DoubleToString(comm,2),DoubleToString(swap,2),DoubleToString(profit,2),
             DoubleToString(profit+comm+swap,2),AccountInfoString(ACCOUNT_CURRENCY));
   FileClose(h);
}
// Position gone from the terminal: write one row once history shows full entry AND exit volume. History lag keeps
// the record pending, never drops it.
void GfJournalPass()
{
   for(int i=ArraySize(gfTrk)-1;i>=0;i--)
   {
      if(PositionSelectByTicket(gfTrk[i].ticket) && (ulong)PositionGetInteger(POSITION_IDENTIFIER)==gfTrk[i].id) continue;
      if(!HistorySelectByPosition(gfTrk[i].id)) { gfTxDirty=true; continue; }
      double vin=0,vout=0,pin=0,pout=0,profit=0,comm=0,swap=0; datetime tin=0,tout=0;
      for(int j=0;j<HistoryDealsTotal();j++)
      {
         ulong d=HistoryDealGetTicket(j);
         if(d==0) continue;
         long kind=HistoryDealGetInteger(d,DEAL_ENTRY); double v=HistoryDealGetDouble(d,DEAL_VOLUME),p=HistoryDealGetDouble(d,DEAL_PRICE);
         profit+=HistoryDealGetDouble(d,DEAL_PROFIT); comm+=HistoryDealGetDouble(d,DEAL_COMMISSION); swap+=HistoryDealGetDouble(d,DEAL_SWAP);
         if(kind==DEAL_ENTRY_IN) { pin+=p*v; vin+=v; if(tin==0) tin=(datetime)HistoryDealGetInteger(d,DEAL_TIME); }
         else if(kind==DEAL_ENTRY_OUT || kind==DEAL_ENTRY_OUT_BY) { pout+=p*v; vout+=v; tout=(datetime)HistoryDealGetInteger(d,DEAL_TIME); }
      }
      double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
      if(vin<=0 || tout<=0 || MathAbs(vin-vout)>step*0.5) { gfTxDirty=true; continue; }
      GfJournalWrite(gfTrk[i],tin,tout,vin,pin/vin,pout/vout,profit,comm,swap);
      string key=GfCloseKey(gfTrk[i].id);
      GlobalVariableDel(key+".active"); GlobalVariableDel(key+".time"); GlobalVariableDel(key+".volume"); GlobalVariableDel(key+".hi"); GlobalVariableDel(key+".lo");
      for(int m=i;m<ArraySize(gfTrk)-1;m++) gfTrk[m]=gfTrk[m+1];
      ArrayResize(gfTrk,ArraySize(gfTrk)-1);
   }
}
// ---- startup / recovery ---------------------------------------------------------------------------------------------
bool GfLeaseAcquire()
{
   if(MQLInfoInteger(MQL_TESTER)) return true;
   gfLease=FileOpen(GfScope()+".lock",FILE_COMMON|FILE_READ|FILE_WRITE|FILE_BIN);
   if(gfLease==INVALID_HANDLE) { Print("GF executor already active (or ownership lease unavailable) for this account/symbol/magic"); return false; }
   return true;
}
void GfLeaseRelease() { if(gfLease!=INVALID_HANDLE) { FileClose(gfLease); gfLease=INVALID_HANDLE; } }
// Owned history must be readable, the position scan complete, and any stray pending orders of ours removed before
// the first entry. Owned positions are managed (and flattened on deadline) throughout.
void GfRecoveryStep(datetime nowS)
{
   if(gfRecoveryReady) return;
   if(MQLInfoInteger(MQL_TESTER)) { gfRecoveryReady=true; return; }
   if(!TerminalInfoInteger(TERMINAL_CONNECTED) || nowS<gfRecoveryRetry) return;
   gfRecoveryRetry=nowS+30;
   if(!HistorySelect(0,TimeCurrent()+86400)) { GfLog("GF_RECOVERY history not available yet"); return; }
   GfScan();
   if(!gfScanOK) { GfLog("GF_RECOVERY position scan incomplete"); return; }
   for(int i=OrdersTotal()-1;i>=0;i--)          // this strategy never rests orders: remove ours, leave foreign orders alone
   {
      ulong o=OrderGetTicket(i);
      if(o==0 || OrderGetString(ORDER_SYMBOL)!=_Symbol || (ulong)OrderGetInteger(ORDER_MAGIC)!=(ulong)Magic) continue;
      MqlTradeRequest rq; MqlTradeResult rs; ZeroMemory(rq); ZeroMemory(rs);
      rq.action=TRADE_ACTION_REMOVE; rq.order=o;
      bool sent=OrderSend(rq,rs);
      if(!sent || rs.retcode!=TRADE_RETCODE_DONE)
         PrintFormat("GF_RECOVERY could not remove stray pending order %I64u retcode=%u",o,rs.retcode);
      else
         PrintFormat("GF_RECOVERY removed stray pending order %I64u retcode=%u",o,rs.retcode);
   }
   gfRecoveryReady=true;
   PrintFormat("GF_RECOVERY_READY owned=%d volume=%.2f",gfOwnedN,gfOwnedVol);
}
void GfParseExtraHolidays()
{
   GfExtraCount=0;
   string parts[]; int n=StringSplit(ExtraHolidays,',',parts);
   for(int i=0;i<n && GfExtraCount<GF_EXTRA_MAX;i++)
   {
      string s=parts[i]; StringTrimLeft(s); StringTrimRight(s);
      if(StringLen(s)!=8) continue;
      int v=(int)StringToInteger(s);
      if(v>=20070101 && v<=20991231) GfExtraHol[GfExtraCount++]=v;
   }
}
int GfRuntimeInit()
{
   if(!GfSymbolMetaOK()) { Print("GF_INIT_FAIL symbol metadata missing or invalid"); return INIT_FAILED; }
   if(!AllowOtherSymbols && StringFind(_Symbol,"USDJPY")<0 && StringFind(_Symbol,"EURJPY")<0 && StringFind(_Symbol,"GBPJPY")<0)
   { Print("GF_INIT_FAIL strategy is specified for USDJPY, EURJPY, GBPJPY only (AllowOtherSymbols=false)"); return INIT_PARAMETERS_INCORRECT; }
   if(!GfLotsValid(Lots)) { Print("GF_INIT_FAIL Lots is not on this symbol's volume grid/min/max (never rounded)"); return INIT_PARAMETERS_INCORRECT; }
   if(MaxExposureLots<Lots) { Print("GF_INIT_FAIL MaxExposureLots below Lots"); return INIT_PARAMETERS_INCORRECT; }
   if(DisasterStopPips<0 || MaxFloatingLossMoney<0 || MaxEntrySpreadPips<0 || MaxLateEntrySec<0) return INIT_PARAMETERS_INCORRECT;
   int ck=ClkInit(); if(ck!=INIT_SUCCEEDED) return ck;
   if(DisasterStopPips>0)
   {
      double lvl=(double)MathMax(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL))*_Point;
      if(DisasterStopPips*GfPipSize()<=lvl) { Print("GF_INIT_FAIL DisasterStopPips inside broker stops/freeze level"); return INIT_PARAMETERS_INCORRECT; }
   }
   if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   { Print("GF_INIT_FAIL account is not a hedging account: GotobiFix keeps a long and a short as separate tickets and requires hedging"); return INIT_FAILED; }
   GfParseExtraHolidays();
   if(!GfLeaseAcquire()) return INIT_FAILED;
   GfLegLoad();
   ArrayResize(gfTrk,0);
   ClkRefresh(ClkNowServer());
   if(ClkGaveUp()) { Print("GF_INIT_FAIL the broker clock cannot be resolved in the tester: ",ClkNote()); return INIT_FAILED; }
   PrintFormat("GF_INIT symbol=%s account=%s hedging clock=%s (%s) lots=%.2f legs=%d disasterStopPips=%.1f tester=%d",
               _Symbol,AccountInfoString(ACCOUNT_SERVER),ClkText(),ClkNote(),Lots,(int)Legs,DisasterStopPips,MQLInfoInteger(MQL_TESTER));
   int ny,nm,nd; datetime nowS=ClkNowServer(); datetime u=ClkNowUtc(nowS);
   if(u>0) { int ymd=GfTokyoYmd(u); if(GfNextGotobi(ymd/10000,(ymd/100)%100,ymd%100,ny,nm,nd)) PrintFormat("GF_NEXT_GOTOBI %04d-%02d-%02d (Tokyo)",ny,nm,nd); }
   return INIT_SUCCEEDED;
}
// One pass: used by OnTick and by the live timer.
void GfProcess()
{
   datetime nowS=ClkNowServer();
   ClkRefresh(nowS);
   datetime nowUtc=ClkNowUtc(nowS);
   GfScan();
   GfRecoveryStep(nowS);
   GfAdopt();
   GfManageExits(nowS,nowUtc);
   GfScan();
   GfAdopt();
   GfReconcileLegs(nowS);
   if(gfTxDirty || ArraySize(gfTrk)>0) { gfTxDirty=false; GfJournalPass(); }
   GfEntries(nowS,nowUtc);
}
#endif
