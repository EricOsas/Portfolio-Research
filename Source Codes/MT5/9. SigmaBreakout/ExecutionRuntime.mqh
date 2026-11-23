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

 // Commission is learned only from a fully closed, owned broker position.
 // Tester fees are simulation settings, never evidence of a broker schedule.
 double SigmaEntryChargesPerLot(ulong positionId)
 {
    if(!HistorySelectByPosition(positionId)) return 0;
    double volume=0,charges=0;
    for(int i=0;i<HistoryDealsTotal();i++)
    {
       ulong d=HistoryDealGetTicket(i);
       if(HistoryDealGetInteger(d,DEAL_ENTRY)!=DEAL_ENTRY_IN) continue;
       volume+=HistoryDealGetDouble(d,DEAL_VOLUME);
       charges-=HistoryDealGetDouble(d,DEAL_COMMISSION)+HistoryDealGetDouble(d,DEAL_FEE);
    }
    return volume>0 ? MathMax(0,charges/volume) : 0;
 }
 double SigmaCommissionEstimate()
 {
    if(MQLInfoInteger(MQL_TESTER)) return CommissionRTPerLot;
    static datetime checked=0;static double observed=0;static bool known=false;
    static long login=0;static string server="";
    if(login!=AccountInfoInteger(ACCOUNT_LOGIN) || server!=AccountInfoString(ACCOUNT_SERVER))
    {login=AccountInfoInteger(ACCOUNT_LOGIN);server=AccountInfoString(ACCOUNT_SERVER);checked=0;known=false;observed=0;}
    datetime now=TimeCurrent();
    if(checked>0 && now-checked<60) return known ? observed : CommissionRTPerLot;
    checked=now;
    if(!HistorySelect(0,now+1)) return known ? observed : CommissionRTPerLot;
    ulong candidates[];int n=0;
    for(int i=HistoryDealsTotal()-1;i>=0 && n<128;i--)
    {
       ulong d=HistoryDealGetTicket(i);
       long direction=HistoryDealGetInteger(d,DEAL_ENTRY);
       if(HistoryDealGetString(d,DEAL_SYMBOL)!=_Symbol || (ulong)HistoryDealGetInteger(d,DEAL_MAGIC)!=Magic ||
          (direction!=DEAL_ENTRY_OUT && direction!=DEAL_ENTRY_OUT_BY)) continue;
       ulong id=(ulong)HistoryDealGetInteger(d,DEAL_POSITION_ID);bool duplicate=false;
       for(int j=0;j<n;j++) if(candidates[j]==id){duplicate=true;break;}
       if(!duplicate){ArrayResize(candidates,n+1);candidates[n++]=id;}
    }
    for(int j=0;j<n;j++)
    {
       if(!HistorySelectByPosition(candidates[j])) continue;
       double opened=0,closed=0,charges=0;bool valid=true;
       for(int i=0;i<HistoryDealsTotal();i++)
       {
          ulong d=HistoryDealGetTicket(i);long direction=HistoryDealGetInteger(d,DEAL_ENTRY);
          if(HistoryDealGetString(d,DEAL_SYMBOL)!=_Symbol || (ulong)HistoryDealGetInteger(d,DEAL_MAGIC)!=Magic){valid=false;break;}
          if(direction==DEAL_ENTRY_IN) opened+=HistoryDealGetDouble(d,DEAL_VOLUME);
          else if(direction==DEAL_ENTRY_OUT || direction==DEAL_ENTRY_OUT_BY) closed+=HistoryDealGetDouble(d,DEAL_VOLUME);
          else {valid=false;break;}
          charges-=HistoryDealGetDouble(d,DEAL_COMMISSION)+HistoryDealGetDouble(d,DEAL_FEE);
       }
       if(!valid || opened<=0 || MathAbs(opened-closed)>1e-8 || !MathIsValidNumber(charges)) continue;
       double rate=MathMax(0,charges/opened);
       if(!known || MathAbs(rate-observed)>1e-8)
          PrintFormat("SIGMA_COMMISSION_SOURCE broker completedPosition=%I64u roundTripPerLot=%.8f",candidates[j],rate);
       known=true;observed=rate;break; // Zero is a valid observed schedule.
    }
    return known ? observed : CommissionRTPerLot;
 }
 bool SigmaCostCoveredPrice(int side,double entry,double commission,double &price)
 {
    double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE),cash=0,slip=0;
    ENUM_ORDER_TYPE type=side==1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    if(tick<=0 || !OrderCalcProfit(type,_Symbol,1.0,entry,entry+side*tick,cash) ||
       !OrderCalcProfit(type,_Symbol,1.0,entry,entry-side*SlipPrice*(MQLInfoInteger(MQL_TESTER) ? 2.0 : 1.0),slip) ||
       cash<=0 || !MathIsValidNumber(cash) || commission<0 || !MathIsValidNumber(commission)) return false;
    double raw=entry+side*(commission+MathAbs(slip))*tick/cash;
    price=NormalizeDouble((side==1 ? MathCeil(raw/tick-1e-9) : MathFloor(raw/tick+1e-9))*tick,_Digits);
    return MathIsValidNumber(price);
 }

#ifndef SIGMA_STRATEGY_TRADE_EXPORT
#define SIGMA_STRATEGY_TRADE_EXPORT
datetime SigmaServerUTC(datetime server)
{
   return SigmaClockUTC(server);
}
bool SigmaExportTrades(string path)
{
   datetime begin=0,end=TimeCurrent()+1;
   string stage="TESTER";
   if(!HistorySelect(begin,end-1)) return false;
   int f=FileOpen(path,FILE_COMMON|FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(f==INVALID_HANDLE) return false;
   FileWrite(f,"model","variant","feed","stage","run_id","position_id","exit_deal","entry_server","exit_server","entry_utc","exit_utc","central_date","side","volume","entry_price","exit_price","original_sl","original_tp","broker_net","modeled_cost","adjusted_net","risk_budget_cash","net_over_budget","real_entry_ordinal","model_attempt","exit_reason");
   string variant=SyntheticFirst ? "synthetic_first_cap"+IntegerToString(VaultAttemptCap) : Management==M1RStep ? "M1_Rstep_TP"+DoubleToString(TargetR,1) : "fixed_baseline";
   datetime entryTime=0,previousDay=0;double entryPrice=0,entryVolume=0,sl=0,tp=0,costLot=0;
   long positionId=0;int side=0,ordinal=0,exits=0;double reconstructed=0;
   bool ok=true;
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong deal=HistoryDealGetTicket(i);
      if((ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=Magic || HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol) continue;
      long direction=HistoryDealGetInteger(deal,DEAL_ENTRY);
      datetime t=(datetime)HistoryDealGetInteger(deal,DEAL_TIME);
      double qty=HistoryDealGetDouble(deal,DEAL_VOLUME),price=HistoryDealGetDouble(deal,DEAL_PRICE);
      if(direction==DEAL_ENTRY_IN)
      {
         if(entryVolume>1e-8){ok=false;break;}
         entryTime=t;entryPrice=price;entryVolume=qty;
         positionId=HistoryDealGetInteger(deal,DEAL_POSITION_ID);
         side=HistoryDealGetInteger(deal,DEAL_TYPE)==DEAL_TYPE_BUY ? 1 : -1;
         ulong order=(ulong)HistoryDealGetInteger(deal,DEAL_ORDER);
         sl=HistoryOrderGetDouble(order,ORDER_SL);tp=HistoryOrderGetDouble(order,ORDER_TP);
         double slipLoss=0;
         if(!OrderCalcProfit(ORDER_TYPE_BUY,_Symbol,1.0,price,price-2*SlipPrice,slipLoss)){ok=false;break;}
         costLot=CommissionRTPerLot+MathAbs(slipLoss);
         datetime d=SigmaDay(t);if(d!=previousDay){ordinal=0;previousDay=d;}ordinal++;
      }
      else if(direction==DEAL_ENTRY_OUT || direction==DEAL_ENTRY_OUT_BY)
      {
         if(entryVolume<=0 || HistoryDealGetInteger(deal,DEAL_POSITION_ID)!=positionId || qty>entryVolume+1e-8 || SigmaDay(t)!=SigmaDay(entryTime)){ok=false;break;}
         double broker=HistoryDealGetDouble(deal,DEAL_PROFIT)+HistoryDealGetDouble(deal,DEAL_COMMISSION)+HistoryDealGetDouble(deal,DEAL_SWAP)+HistoryDealGetDouble(deal,DEAL_FEE);
         double entryCharge=SigmaEntryChargesPerLot((ulong)positionId)*qty;
         // The history helper changes selection: restore the full export window.
         HistorySelect(begin,end-1);
         double exitCharge=HistoryDealGetDouble(deal,DEAL_COMMISSION)+HistoryDealGetDouble(deal,DEAL_FEE);
         double nativeCommission=MathMax(0,entryCharge-exitCharge);
         double cost=costLot*qty-MathMin(CommissionRTPerLot*qty,nativeCommission),net=broker-entryCharge-cost;
         FileWrite(f,SigmaOutputFamily,variant,_Symbol,stage,RunId,positionId,deal,
            TimeToString(entryTime,TIME_DATE|TIME_SECONDS),TimeToString(t,TIME_DATE|TIME_SECONDS),
            TimeToString(SigmaServerUTC(entryTime),TIME_DATE|TIME_SECONDS),TimeToString(SigmaServerUTC(t),TIME_DATE|TIME_SECONDS),
            TimeToString(SigmaDay(t),TIME_DATE),side==1 ? "LONG" : "SHORT",qty,entryPrice,price,sl,tp,
            broker,cost,net,UseFixedSize ? 0 : RiskCash,UseFixedSize ? 0 : net/RiskCash,ordinal,ordinal+(SyntheticFirst ? 1 : 0),(int)HistoryDealGetInteger(deal,DEAL_REASON));
         entryVolume-=qty;exits++;reconstructed+=net;
      }
   }
   FileClose(f);
   double expected=TesterStatistics(STAT_PROFIT)-totalCost;
   ok=ok && entryVolume<1e-8 && exits==(int)TesterStatistics(STAT_TRADES) && MathAbs(reconstructed-expected)<.01;
   PrintFormat("SIGMA_TRADE_EXPORT_%s rows=%d net=%.2f expected=%.2f",ok ? "PASS" : "FAIL",exits,reconstructed,expected);
   return ok;
}
#endif

#ifndef SIGMA_STRATEGY_RUNTIME
#define SIGMA_STRATEGY_RUNTIME
// Owned-position lifecycle for production EAs and archived research fixtures.
bool runtimeBlocked=false;
bool runtimeRecoveryHold=false;
bool runtimeEntryPending=false;
datetime runtimeIntentTime=0;
ulong runtimeIntentNonce=0;
double runtimeIntentStop=0,runtimeIntentTarget=0;
bool SigmaRecoveryIntentMatches(bool pending,datetime sent,datetime filled,double plannedStop,double plannedTarget,double brokerStop,double brokerTarget,double tick)
{
   if(plannedStop==0 && plannedTarget==0)
      return pending && sent>0 && filled>=sent && filled<=sent+60 && tick>0 && brokerStop==0 && brokerTarget==0;
   return pending && sent>0 && filled>=sent && filled<=sent+60 && tick>0
      && plannedStop>0 && plannedTarget>0 && MathIsValidNumber(plannedStop) && MathIsValidNumber(plannedTarget)
      && MathAbs(plannedStop-brokerStop)<tick*1e-6 && MathAbs(plannedTarget-brokerTarget)<tick*1e-6;
}
bool SigmaRecoveryPositionMatches(double hi,double lo,ulong actual,datetime savedTime,datetime actualTime,double risk)
{
   return MathIsValidNumber(hi) && MathIsValidNumber(lo) && hi>=0 && hi<=4294967295.0 && lo>=0 && lo<=4294967295.0
      && hi==MathFloor(hi) && lo==MathFloor(lo) && actual>0 && (((ulong)hi<<32)|(ulong)lo)==actual
      && savedTime>0 && savedTime==actualTime && MathIsValidNumber(risk) && risk>=0;
}
datetime runtimeTrailLastBar=0;
bool runtimeJournalOK=true;
bool runtimeJournalTesting=false;
long runtimeAccountId=0;
long runtimeAccountMode=0;
string runtimeAccountServer="";
string runtimeAccountKey="";
int runtimeLockFile=INVALID_HANDLE;
datetime runtimeInitialSource=0;
bool runtimeHistoryReady=false;
string SigmaStateKey(){return runtimeJournalTesting ? "SIGMA.fixture."+RunId+"." : runtimeAccountKey;}
string SigmaRuntimeOwnershipKey(long login,string server,long mode,string symbol,ulong magic)
{
   string identity=StringFormat("%I64d|%s|%I64d|%s|%I64u",login,server,mode,symbol,magic);
   ulong hash=14695981039346656037;
   for(int i=0;i<StringLen(identity);i++){hash^=(ulong)StringGetCharacter(identity,i);hash*=1099511628211;}
   return "SIGMA."+StringFormat("%I64u",hash)+".";
}
void SigmaStatePut(string k,double value)
{
   if(GlobalVariableSet(k,value)==0){runtimeJournalOK=false;runtimeBlocked=true;Print("SIGMA JOURNAL WRITE FAILED: entries blocked");}
}
// BEGIN SELF-CONTAINED CLOSE RECOVERY
#ifndef NQ_CLOSE_RECOVERY
#define NQ_CLOSE_RECOVERY
// Exact-position close intents are separate from the original-risk checkpoint:
// a damaged risk journal must not erase an unacknowledged broker request.
bool runtimeClosePending=false,runtimeCloseAttention=false;
bool runtimeCloseRejected=false;
bool RecoveryClosePut(string key,double value)
{
   if(GlobalVariableSet(key,value)>0)return true;
   runtimeBlocked=true;runtimeCloseAttention=true;
   Print("RECOVERY ATTENTION: close-intent journal write failed; no unjournaled close request");
   return false;
}
bool RecoveryCloseReconcile(string stateKey)
{
   if(MQLInfoInteger(MQL_TESTER))return true;
   string k=stateKey+"close.";
   runtimeCloseRejected=GlobalVariableCheck(k+"retryafter") && GlobalVariableGet(k+"retryafter")>TimeCurrent();
   if(!GlobalVariableCheck(k+"valid") || GlobalVariableGet(k+"valid")==0)
   {runtimeClosePending=false;runtimeCloseAttention=false;return true;}
   runtimeClosePending=true;
   if(GlobalVariableGet(k+"valid")!=1){runtimeCloseAttention=true;return false;}
   string fields[]={"hi","lo","orderhi","orderlo","qty","time"};
   for(int i=0;i<ArraySize(fields);i++)if(!GlobalVariableCheck(k+fields[i])){runtimeCloseAttention=true;return false;}
   for(int i=0;i<4;i++)
   {
      double value=GlobalVariableGet(k+fields[i]);
      if(!MathIsValidNumber(value) || value<0 || value>4294967295.0 || value!=MathFloor(value))
      {runtimeCloseAttention=true;return false;}
   }
   double stamped=GlobalVariableGet(k+"time");
   if(!MathIsValidNumber(stamped) || stamped<=0 || stamped!=MathFloor(stamped))
   {runtimeCloseAttention=true;return false;}
   ulong position=((ulong)GlobalVariableGet(k+"hi")<<32)|(ulong)GlobalVariableGet(k+"lo");
   ulong order=((ulong)GlobalVariableGet(k+"orderhi")<<32)|(ulong)GlobalVariableGet(k+"orderlo");
   bool orderKnown=order>0;
   double requested=GlobalVariableGet(k+"qty"),remaining=0;
   long sent=(long)GlobalVariableGet(k+"time");bool present=false;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      if(PositionGetTicket(i)==0 || (ulong)PositionGetInteger(POSITION_IDENTIFIER)!=position)continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol || (ulong)PositionGetInteger(POSITION_MAGIC)!=Magic)return false;
      present=true;remaining=PositionGetDouble(POSITION_VOLUME);break;
   }
   bool verified=false;
   if(position>0 && requested>0 && MathIsValidNumber(requested) && sent>0 && HistorySelectByPosition(position))
   {
      double exited=0;bool found=false,ambiguous=false;
      for(int i=0;i<HistoryDealsTotal();i++)
      {
         ulong deal=HistoryDealGetTicket(i);
         if(HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol || HistoryDealGetInteger(deal,DEAL_ENTRY)!=DEAL_ENTRY_OUT
            || HistoryDealGetInteger(deal,DEAL_TIME_MSC)<sent)continue;
         if(!present){verified=true;break;}
         if((ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=Magic)continue;
         ulong candidate=(ulong)HistoryDealGetInteger(deal,DEAL_ORDER);
         if(orderKnown && candidate!=order)continue;
         if(!found){order=candidate;found=true;}
         else if(order!=candidate){ambiguous=true;break;}
         exited+=HistoryDealGetDouble(deal,DEAL_VOLUME);
      }
      if(present && found && !ambiguous)
      {
         long state=HistoryOrderGetInteger(order,ORDER_STATE);
         bool terminal=state==ORDER_STATE_FILLED || state==ORDER_STATE_CANCELED || state==ORDER_STATE_EXPIRED;
         double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
         verified=terminal && step>0 && exited>0 && exited<=requested+step*1e-6
            && remaining<=requested-exited+step*1e-6;
      }
      if(present && !ambiguous && orderKnown && order>0 && HistoryOrderSelect(order)
         && HistoryOrderGetInteger(order,ORDER_POSITION_ID)==(long)position
         && (HistoryOrderGetInteger(order,ORDER_STATE)==ORDER_STATE_REJECTED
            || HistoryOrderGetInteger(order,ORDER_STATE)==ORDER_STATE_CANCELED)
         && HistoryOrderGetDouble(order,ORDER_VOLUME_CURRENT)==HistoryOrderGetDouble(order,ORDER_VOLUME_INITIAL))verified=true;
   }
   if(verified && RecoveryClosePut(k+"valid",0))
   {GlobalVariablesFlush();runtimeClosePending=false;runtimeCloseAttention=false;return true;}
   if(!runtimeCloseAttention)Print("RECOVERY ATTENTION: pending close is unconfirmed; protection retained, no duplicate request");
   runtimeCloseAttention=true;return false;
}
bool RecoveryCloseBegin(string stateKey,ulong ticket)
{
   if(MQLInfoInteger(MQL_TESTER))return true;
   if(!TerminalInfoInteger(TERMINAL_CONNECTED) || !RecoveryCloseReconcile(stateKey) || runtimeCloseRejected || !PositionSelectByTicket(ticket))return false;
   if(PositionGetString(POSITION_SYMBOL)!=_Symbol || (ulong)PositionGetInteger(POSITION_MAGIC)!=Magic)return false;
   ulong position=(ulong)PositionGetInteger(POSITION_IDENTIFIER);string k=stateKey+"close.";
   bool ok=RecoveryClosePut(k+"valid",-1); // Interrupted intent construction must also fail closed.
   ok=RecoveryClosePut(k+"hi",(double)(position>>32)) && ok;ok=RecoveryClosePut(k+"lo",(double)(position&0xffffffff)) && ok;
   ok=RecoveryClosePut(k+"qty",PositionGetDouble(POSITION_VOLUME)) && ok;
   ok=RecoveryClosePut(k+"time",(double)((long)TimeCurrent()*1000)) && ok;
   ok=RecoveryClosePut(k+"orderhi",0) && ok;ok=RecoveryClosePut(k+"orderlo",0) && ok;
   if(ok)ok=RecoveryClosePut(k+"valid",1);
   GlobalVariablesFlush();runtimeClosePending=true;return ok;
}
void RecoveryCloseResult(string stateKey,uint ret,ulong order)
{
   if(MQLInfoInteger(MQL_TESTER))return;
   string k=stateKey+"close.";
   // Only explicit rejection retires intent immediately. Even DONE/partial
   // requires history and the position snapshot to acknowledge the quantity.
   bool terminal=ret==10004 || ret==10006 || ret==10007 || (ret>=10013 && ret<=10022)
      || ret==10024 || ret==10026 || ret==10027 || ret==10029 || ret==10030
      || ret==10032 || ret==10033 || ret==10034 || ret==10035 || ret==10038 || ret==10040;
   if(terminal && RecoveryClosePut(k+"valid",0))
   {
      if(ret!=TRADE_RETCODE_DONE && ret!=TRADE_RETCODE_DONE_PARTIAL && ret!=10036)
      {RecoveryClosePut(k+"retryafter",(double)(TimeCurrent()+5));runtimeCloseRejected=true;Print("CLOSE REJECTED: protection retained; retries paused for five seconds");}
      GlobalVariablesFlush();runtimeClosePending=false;runtimeCloseAttention=false;return;
   }
   RecoveryClosePut(k+"orderhi",(double)(order>>32));RecoveryClosePut(k+"orderlo",(double)(order&0xffffffff));GlobalVariablesFlush();
   RecoveryCloseReconcile(stateKey);
}
#endif
// END SELF-CONTAINED CLOSE RECOVERY
void SigmaStateSave(int reserved=-1)
{
   if(runtimeRecoveryHold) return;
   if((MQLInfoInteger(MQL_TESTER) && !runtimeJournalTesting) || day==0) return;
   if(!runtimeJournalTesting && !SigmaRuntimeAccountContextValid()) return;
   string k=SigmaStateKey();
   runtimeJournalOK=true;
   SigmaStatePut(k+"valid",0);
   SigmaStatePut(k+"day",(double)day);
   SigmaStatePut(k+"entries",reserved>=0 ? reserved : entries);
   SigmaStatePut(k+"firstside",firstSide);
   SigmaStatePut(k+"firststopdist",firstStopDistance);
   SigmaStatePut(k+"targetfilled",targetFilled ? 1 : 0);
   SigmaStatePut(k+"retryarmed",retryArmed ? 1 : 0);
   SigmaStatePut(k+"retryafter",(double)retryEligibleAfter);
   SigmaStatePut(k+"signal",(double)lastSignal);
   SigmaStatePut(k+"virtual",virtualActive ? 1 : 0);
   SigmaStatePut(k+"vstart",(double)virtualStart);
   SigmaStatePut(k+"vlast",(double)virtualLastBar);
   SigmaStatePut(k+"vsl",virtualStop);SigmaStatePut(k+"vtp",virtualTarget);
   SigmaStatePut(k+"risk",initialRisk);SigmaStatePut(k+"peak",barPeakR);
   SigmaStatePut(k+"costlot",modelCostPerLot);
   SigmaStatePut(k+"commlot",entryCommissionPerLot);
   SigmaStatePut(k+"entrytime",(double)ownedEntryTime);
   ulong position=(!runtimeEntryPending && OwnPosition()) ? (ulong)PositionGetInteger(POSITION_IDENTIFIER) : 0;
   SigmaStatePut(k+"poshi",(double)(position>>32));SigmaStatePut(k+"poslo",(double)(position&0xffffffff));
   SigmaStatePut(k+"pending",runtimeEntryPending ? 1 : 0);SigmaStatePut(k+"trailbar",(double)runtimeTrailLastBar);
   SigmaStatePut(k+"intenttime",(double)runtimeIntentTime);SigmaStatePut(k+"intentsl",runtimeIntentStop);SigmaStatePut(k+"intenttp",runtimeIntentTarget);
   SigmaStatePut(k+"intentnonce",(double)runtimeIntentNonce);
   SigmaStatePut(k+"blocked",runtimeBlocked ? 1 : 0);
   SigmaStatePut(k+"valid",runtimeJournalOK ? 1 : 0);GlobalVariablesFlush();
}
int SigmaHistoryEntries(datetime now)
{
   if(!HistorySelect(SigmaSessionTime(SigmaDay(now)),now)) return -1;
   ulong seen[];int n=0;
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong deal=HistoryDealGetTicket(i);
      if(HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol || (ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=Magic || HistoryDealGetInteger(deal,DEAL_ENTRY)!=DEAL_ENTRY_IN) continue;
      ulong order=(ulong)HistoryDealGetInteger(deal,DEAL_ORDER);bool found=false;
      for(int j=0;j<n;j++) if(seen[j]==order){found=true;break;}
      if(!found){ArrayResize(seen,n+1);seen[n++]=order;}
   }
   return n;
}
bool SigmaLegacyPositionRiskVerified()
{
   if(initialRisk<=0 || ownedEntryTime!=(datetime)PositionGetInteger(POSITION_TIME)) return false;
   ulong position=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
   double entry=PositionGetDouble(POSITION_PRICE_OPEN),tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tick<=0 || !HistorySelectByPosition(position)) return false;
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong deal=HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(deal,DEAL_ENTRY)!=DEAL_ENTRY_IN || HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol
         || (ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=Magic) continue;
      ulong order=(ulong)HistoryDealGetInteger(deal,DEAL_ORDER);
      double stop=HistoryOrderGetDouble(order,ORDER_SL);
      return stop>0 && MathAbs(MathAbs(entry-stop)-initialRisk)<tick*1e-6;
   }
   return false;
}
void SigmaStateRestore(datetime now)
{
   if(MQLInfoInteger(MQL_TESTER) && !runtimeJournalTesting) return;
   RecoveryCloseReconcile(SigmaStateKey());
   string k=SigmaStateKey();int actual=SigmaHistoryEntries(now);
   if(actual<0){runtimeBlocked=true;runtimeRecoveryHold=true;initialRisk=0;Note("RECOVERY_BLOCK","History unavailable; broker protection retained");return;}
   bool same=GlobalVariableCheck(k+"day") && (datetime)GlobalVariableGet(k+"day")==day;
   if(same)
   {
      string fields[]={"valid","entries","signal","virtual","vstart","vlast","vsl","vtp","risk","peak","costlot","entrytime","blocked"};
      for(int i=0;i<ArraySize(fields);i++)
         if(!GlobalVariableCheck(k+fields[i]))
         {runtimeBlocked=true;runtimeRecoveryHold=true;initialRisk=0;Note("RECOVERY_BLOCK","Missing journal field; broker protection retained");return;}
   }
   if(same && GlobalVariableGet(k+"valid")!=1)
   {runtimeBlocked=true;runtimeRecoveryHold=true;initialRisk=0;entries=Model==VaultBreak ? VaultAttemptCap : 1;Note("RECOVERY_BLOCK","Incomplete state commit; broker protection retained");return;}
   if(same)
   {
      entries=(int)GlobalVariableGet(k+"entries");
      firstSide=GlobalVariableCheck(k+"firstside") ? (int)GlobalVariableGet(k+"firstside") : 0;
      firstStopDistance=GlobalVariableCheck(k+"firststopdist") ? GlobalVariableGet(k+"firststopdist") : 0;
      targetFilled=GlobalVariableCheck(k+"targetfilled") && GlobalVariableGet(k+"targetfilled")==1;
      retryArmed=GlobalVariableCheck(k+"retryarmed") && GlobalVariableGet(k+"retryarmed")==1;
      retryEligibleAfter=GlobalVariableCheck(k+"retryafter") ? (datetime)GlobalVariableGet(k+"retryafter") : 0;
      lastSignal=(datetime)GlobalVariableGet(k+"signal");
      virtualActive=GlobalVariableGet(k+"virtual")==1;
      virtualStart=(datetime)GlobalVariableGet(k+"vstart");
      virtualLastBar=(datetime)GlobalVariableGet(k+"vlast");
      virtualStop=GlobalVariableGet(k+"vsl");virtualTarget=GlobalVariableGet(k+"vtp");
      initialRisk=GlobalVariableGet(k+"risk");barPeakR=GlobalVariableGet(k+"peak");
      modelCostPerLot=GlobalVariableGet(k+"costlot");
      entryCommissionPerLot=GlobalVariableCheck(k+"commlot") ? GlobalVariableGet(k+"commlot") : CommissionRTPerLot;
      ownedEntryTime=(datetime)GlobalVariableGet(k+"entrytime");
      runtimeTrailLastBar=GlobalVariableCheck(k+"trailbar") ? (datetime)GlobalVariableGet(k+"trailbar") : 0;
      runtimeBlocked=GlobalVariableGet(k+"blocked")==1;
   }
   else
   {
      runtimeBlocked=false;entries=actual;
      if(SyntheticFirst && actual>0) entries++;
   }
   entries=MathMax(entries,actual+(SyntheticFirst && actual>0 ? 1 : 0));
   // Attachment cannot replay an old signal, even when no journal exists.
   lastSignal=MathMax(lastSignal,runtimeInitialSource);
   if(same && !OwnPosition() && GlobalVariableCheck(k+"pending") && GlobalVariableGet(k+"pending")==1 && actual<entries)
   {runtimeBlocked=true;runtimeRecoveryHold=true;Note("RECOVERY_BLOCK","Unresolved pre-send entry reservation; no replacement order");}
   if(OwnPosition())
   {
      if(firstSide==0) firstSide=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY ? 1 : -1;
      ulong position=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
      if(same && !GlobalVariableCheck(k+"poshi") && !GlobalVariableCheck(k+"poslo") && SigmaLegacyPositionRiskVerified())
      {
         runtimeTrailLastBar=ownedEntryTime/60*60-60;
         SigmaStateSave();Note("RECOVERY_LEGACY_VERIFIED","Entry-order stop verifies original risk; replay completed closes from entry");
      }
      bool pending=GlobalVariableCheck(k+"pending") && GlobalVariableGet(k+"pending")==1;
      if(same && pending && GlobalVariableCheck(k+"intentnonce") && PositionGetString(POSITION_COMMENT)=="SIGMA#"+IntegerToString((long)GlobalVariableGet(k+"intentnonce"))
         && GlobalVariableCheck(k+"intenttime") && GlobalVariableCheck(k+"intentsl") && GlobalVariableCheck(k+"intenttp")
         && SigmaRecoveryIntentMatches(pending,(datetime)GlobalVariableGet(k+"intenttime"),(datetime)PositionGetInteger(POSITION_TIME),
            GlobalVariableGet(k+"intentsl"),GlobalVariableGet(k+"intenttp"),PositionGetDouble(POSITION_SL),PositionGetDouble(POSITION_TP),SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE)))
      {
         initialRisk=MathAbs(PositionGetDouble(POSITION_PRICE_OPEN)-PositionGetDouble(POSITION_SL));
         ownedEntryTime=(datetime)PositionGetInteger(POSITION_TIME);barPeakR=0;runtimeTrailLastBar=0;runtimeEntryPending=false;
         SigmaStateSave();Note("RECOVERY_FILLED_INTENT","Broker bracket matches pre-send reservation");
      }
      bool bound=same && GlobalVariableCheck(k+"poshi") && GlobalVariableCheck(k+"poslo")
         && SigmaRecoveryPositionMatches(GlobalVariableGet(k+"poshi"),GlobalVariableGet(k+"poslo"),position,
            ownedEntryTime,(datetime)PositionGetInteger(POSITION_TIME),initialRisk);
      if(!bound || !GlobalVariableCheck(k+"trailbar") || !MathIsValidNumber(barPeakR) || barPeakR<0
         || runtimeTrailLastBar>now || !MathIsValidNumber(modelCostPerLot) || modelCostPerLot<0
         || !MathIsValidNumber(entryCommissionPerLot) || entryCommissionPerLot<0 || (SlPct>0.0 && (initialRisk<=0 || !MathIsValidNumber(initialRisk)))
         || ownedEntryTime!=(datetime)PositionGetInteger(POSITION_TIME))
      {runtimeBlocked=true;runtimeRecoveryHold=true;initialRisk=0;Note("RECOVERY_BLOCK","Original-risk/trail journal cannot identify owned position; broker protection retained");}
   }
   if(OwnPosition() && SlPct>0.0 && entries==1 && firstStopDistance<=0.0 && initialRisk>0.0)
   {firstStopDistance=initialRisk;Note("RECOVERY_RETRY_DISTANCE","Recovered original stop distance from the live first-attempt position");}
   if(retryArmed && (SlPct<=0.0 || firstStopDistance<=0.0 || firstSide==0 || entries!=1 || targetFilled))
   {retryArmed=false;retryEligibleAfter=0;Note("RECOVERY_RETRY_DISARMED","Stored retry lacks a verifiable original stop or target state");}
   SigmaStateSave();
}
datetime SigmaDate(int year,int month,int date)
{
   MqlDateTime p={};p.year=year;p.mon=month;p.day=date;return StructToTime(p);
}
int SigmaWeekday(datetime t){MqlDateTime p;TimeToStruct(t,p);return p.day_of_week;}
datetime SigmaNthSunday(int year,int month,int n)
{
   datetime first=SigmaDate(year,month,1);
   return first+((7-SigmaWeekday(first))%7+7*(n-1))*86400;
}
bool SigmaBrokerClockValid()
{
   return SigmaClockRefresh(MQLInfoInteger(MQL_TESTER) ? TimeCurrent() : TimeTradeServer());
}
bool SigmaRuntimeInit()
{
   if(MQLInfoInteger(MQL_TESTER)) return true;
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {Print("SIGMA EA BLOCK: hedging account required for independent USTEC sleeves");return false;}
   if(Magic==0 || Management==VWAPClose || Management==CostCoveredBE || Management==ATRTrail)
   {Print("SIGMA EA BLOCK: invalid model identity or unsupported management rule");return false;}
   if(!SigmaBrokerClockValid()) Print("SIGMA CLOCK_WAIT: requesting history for automatic weekly-opening clock detection");
   runtimeAccountId=AccountInfoInteger(ACCOUNT_LOGIN);
   runtimeAccountMode=AccountInfoInteger(ACCOUNT_TRADE_MODE);
   runtimeAccountServer=AccountInfoString(ACCOUNT_SERVER);
   runtimeAccountKey=SigmaRuntimeOwnershipKey(runtimeAccountId,runtimeAccountServer,runtimeAccountMode,_Symbol,Magic);
   FolderCreate("SigmaBreakoutLocks",FILE_COMMON);
   runtimeLockFile=FileOpen("SigmaBreakoutLocks/"+SigmaStateKey()+"lock",FILE_COMMON|FILE_BIN|FILE_READ|FILE_WRITE);
   if(runtimeLockFile==INVALID_HANDLE){Print("SIGMA EA BLOCK: duplicate instance or exclusive ownership lock unavailable");return false;}
   // Indicator calculations/history load asynchronously after handles are created.
   // Keep the EA attached; the entry path waits without disabling recovery/timer protection.
   SigmaRuntimeHistoryReady();
   EventSetTimer(1);
   return true;
}
bool SigmaRuntimeHistoryReady()
{
   if(MQLInfoInteger(MQL_TESTER)) return true;
   static string runtimeWaitReason="";
   if(!TerminalInfoInteger(TERMINAL_CONNECTED) || (runtimeHistoryReady && !SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_SYNCHRONIZED)))
   {
      dayWaiting=true;
      string reason=TerminalInfoInteger(TERMINAL_CONNECTED) ? "M1_SYNC_WAIT" : "CONNECTION_WAIT";
      dataWaitReason=reason;
      if(runtimeWaitReason!=reason)
      {runtimeWaitReason=reason;Print("SIGMA DATA_WAIT: "+reason+"; new entries paused, broker protection retained");}
      return false;
   }
   if(!SigmaBrokerClockValid()) return false;
   if(runtimeHistoryReady)
   {
      if(runtimeWaitReason!="")
      {
         runtimeWaitReason="";Print("SIGMA DATA_READY: connection and M1 synchronization restored");
         if(dataWaitReason=="M1_SYNC_WAIT" || dataWaitReason=="CONNECTION_WAIT" || dataWaitReason=="M1_HISTORY_WAIT")
         {lastSignal=MathMax(lastSignal,iTime(_Symbol,sourceTF,1));dayWaiting=false;dataWaitReason="";}
      }
      return true;
   }
   datetime source=iTime(_Symbol,sourceTF,1);
   MqlRates warm[];
   datetime from=SigmaSessionTime(SigmaDay(TimeCurrent()))-(Model==SigmaBreakout ? 3600 : 0);
   int minutes=CopyRates(_Symbol,PERIOD_M1,from,TimeCurrent(),warm);
   bool ready=source>0 && minutes>0 && SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_SYNCHRONIZED)
      && (Model==VaultBreak || BarsCalculated(adxHandle)>=ADXPeriod+2);
   double atr[],adx[];
   double sessionMean=0;
   if(ready) ready=SigmaSessionATRMean(SigmaDay(TimeCurrent()),sessionMean);
   if(ready && Model!=VaultBreak) ready=CopyBuffer(adxHandle,0,1,2,adx)==2;
   if(!ready)
   {
      static bool announced=false;
      if(!announced){Print("SIGMA HISTORY_WAIT: loading M1/source/daily indicators; new entries blocked, protection active");announced=true;}
      return false;
   }
   runtimeInitialSource=source;
   lastSignal=MathMax(lastSignal,source); // Do not replay a candle that closed during attachment/loading.
   runtimeHistoryReady=true;
   runtimeWaitReason="";
   Print("SIGMA HISTORY_READY: data loaded; waiting for a fresh completed-bar signal");
   return true;
}
bool SigmaRuntimeAccountAllowed(long mode,long margin,bool enabled)
{
   // The toggle controls new entries, not initialization/recovery or account type.
   return margin==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;
}
bool SigmaRuntimeAccountContextValid()
{
   if(AccountInfoInteger(ACCOUNT_LOGIN)!=runtimeAccountId) return false;
   return AccountInfoInteger(ACCOUNT_TRADE_MODE)==runtimeAccountMode
      && AccountInfoString(ACCOUNT_SERVER)==runtimeAccountServer
      && AccountInfoInteger(ACCOUNT_MARGIN_MODE)==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;
}
bool SigmaRuntimeSelfTest()
{
   if(!MQLInfoInteger(MQL_TESTER)) return false;
   string owner=SigmaRuntimeOwnershipKey(1,"server-a",ACCOUNT_TRADE_MODE_DEMO,"USTEC",Magic);
   if(owner==SigmaRuntimeOwnershipKey(1,"server-b",ACCOUNT_TRADE_MODE_DEMO,"USTEC",Magic)
      || owner==SigmaRuntimeOwnershipKey(1,"server-a",ACCOUNT_TRADE_MODE_REAL,"USTEC",Magic)
      || owner==SigmaRuntimeOwnershipKey(2,"server-a",ACCOUNT_TRADE_MODE_DEMO,"USTEC",Magic)
      || owner==SigmaRuntimeOwnershipKey(1,"server-a",ACCOUNT_TRADE_MODE_DEMO,"USTEC",Magic+1)) return false;
   if(!SigmaRuntimeAccountAllowed(ACCOUNT_TRADE_MODE_REAL,ACCOUNT_MARGIN_MODE_RETAIL_HEDGING,true)
      || !SigmaRuntimeAccountAllowed(ACCOUNT_TRADE_MODE_DEMO,ACCOUNT_MARGIN_MODE_RETAIL_HEDGING,false)
      || SigmaRuntimeAccountAllowed(ACCOUNT_TRADE_MODE_REAL,ACCOUNT_MARGIN_MODE_RETAIL_NETTING,true)) return false;
   datetime oldDay=day,oldSignal=lastSignal,oldStart=virtualStart,oldLast=virtualLastBar,oldEntry=ownedEntryTime;
   int oldEntries=entries;bool oldVirtual=virtualActive;
   double oldStop=virtualStop,oldTarget=virtualTarget,oldRisk=initialRisk,oldPeak=barPeakR;
   bool oldHold=runtimeRecoveryHold,oldPending=runtimeEntryPending;
   runtimeJournalTesting=true;runtimeBlocked=false;
   day=D'2022.01.24';entries=2;lastSignal=day+18*3600;
   virtualActive=true;virtualStart=lastSignal;virtualLastBar=lastSignal;
   virtualStop=100;virtualTarget=210;initialRisk=70;barPeakR=1.5;ownedEntryTime=0;
   string key=SigmaStateKey();SigmaStateSave();
   entries=0;lastSignal=0;virtualActive=false;initialRisk=0;barPeakR=0;
   SigmaStateRestore(day+19*3600);
   bool ok=runtimeJournalOK && !runtimeBlocked && entries==2 && lastSignal==day+18*3600
      && virtualActive && virtualStop==100 && virtualTarget==210 && initialRisk==70 && barPeakR==1.5;
   GlobalVariableSet(key+"valid",0);runtimeBlocked=false;SigmaStateRestore(day+19*3600);
   ok=ok && runtimeBlocked;
   GlobalVariableSet(key+"valid",1);GlobalVariableDel(key+"risk");runtimeBlocked=false;SigmaStateRestore(day+19*3600);
   ok=ok && runtimeBlocked;
   GlobalVariablesDeleteAll(key);
   FolderCreate("SigmaBreakoutLocks",FILE_COMMON);
   string lock="SigmaBreakoutLocks/fixture_"+RunId+".lock";
   int first=FileOpen(lock,FILE_COMMON|FILE_BIN|FILE_READ|FILE_WRITE);
   int second=FileOpen(lock,FILE_COMMON|FILE_BIN|FILE_READ|FILE_WRITE);
   ok=ok && first!=INVALID_HANDLE && second==INVALID_HANDLE;
   if(second!=INVALID_HANDLE) FileClose(second);
   if(first!=INVALID_HANDLE) FileClose(first);
   FileDelete(lock,FILE_COMMON);
   day=oldDay;entries=oldEntries;lastSignal=oldSignal;virtualActive=oldVirtual;
   virtualStart=oldStart;virtualLastBar=oldLast;ownedEntryTime=oldEntry;
   virtualStop=oldStop;virtualTarget=oldTarget;initialRisk=oldRisk;barPeakR=oldPeak;
   runtimeBlocked=false;runtimeJournalTesting=false;runtimeRecoveryHold=oldHold;runtimeEntryPending=oldPending;
   Print(ok ? "SIGMA_RUNTIME_SELFTEST_PASS account guard / restart / corruption / exclusive ownership" : "SIGMA_RUNTIME_SELFTEST_FAILED");
   return ok;
}
bool SigmaRuntimeEntryAllowed(double entry,double stop,double target,double volume,int side)
{
   if(!EnableTrading) return false;
   if(MQLInfoInteger(MQL_TESTER)) return true;
   if(runtimeBlocked || !SigmaRuntimeAccountContextValid() || !SigmaBrokerClockValid() || !RecoveryCloseReconcile(SigmaStateKey())) return false;
   if(!TerminalInfoInteger(TERMINAL_CONNECTED) || !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED) || !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)) return false;
   MqlTick q;if(!SymbolInfoTick(_Symbol,q) || TimeCurrent()-q.time>30) return false;
   double reference=side==1 ? q.bid : q.ask;
   if(stop>0.0 || target>0.0)
   {
      double bound=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
      if(stop>0.0 && side*(reference-stop)<bound) return false;
      if(target>0.0 && side*(target-reference)<bound) return false;
   }
   double margin=0;
   if(!OrderCalcMargin(side==1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,_Symbol,volume,entry,margin) || margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE)) return false;
   // Reserve the attempt before submission: interrupted requests cannot be replayed.
   runtimeEntryPending=true;runtimeIntentTime=TimeCurrent();runtimeIntentNonce=(ulong)runtimeIntentTime*1000+GetTickCount()%1000;
   runtimeIntentStop=stop;runtimeIntentTarget=target;SigmaStateSave(entries+1);
   return !runtimeBlocked && runtimeJournalOK;
}
void SigmaRuntimeFilled(int side,double stop,double friction)
{
   if(MQLInfoInteger(MQL_TESTER)) return;
   if(!OwnPosition()){runtimeBlocked=true;Note("FILL_BLOCK","Accepted request has no owned position");SigmaStateSave();return;}
   double volume=PositionGetDouble(POSITION_VOLUME),price=PositionGetDouble(POSITION_PRICE_OPEN),loss=0;
   initialRisk=MathAbs(price-stop);ownedEntryTime=(datetime)PositionGetInteger(POSITION_TIME);
   runtimeEntryPending=false;runtimeTrailLastBar=0;
   bool valid=(SlPct==0.0) || (PositionGetDouble(POSITION_SL)>0 && PositionGetDouble(POSITION_TP)>0
      && OrderCalcProfit(side==1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,_Symbol,volume,price,stop,loss)
      && (UseFixedSize || MathAbs(loss)+friction*volume<=RiskCash+0.01));
   if(!valid){runtimeBlocked=true;CloseOwned("FILLED_RISK_OR_PROTECTION");Note("FILL_BLOCK","Actual fill breached planned budget or protection");}
   SigmaStateSave();
}
void OnTimer()
{
   if(MQLInfoInteger(MQL_TESTER)) return;
   if(!SigmaRuntimeAccountContextValid()){SigmaDraw();return;}
   RecoveryCloseReconcile(SigmaStateKey());
   datetime now=TimeTradeServer();
   if(SlPct>0.0 && OwnPosition() && (PositionGetDouble(POSITION_SL)<=0 || PositionGetDouble(POSITION_TP)<=0))
   {runtimeBlocked=true;CloseOwned("PROTECTION_MISSING");SigmaStateSave();}
   SigmaRuntimeCutoffCheck(now);
   SigmaRuntimeHistoryReady();
   SigmaRefreshLiveVisuals(now);
   SigmaDraw();
}
void SigmaRuntimeCutoffCheck(datetime now)
{
   if(!SigmaBrokerClockValid()) return;
   if(OwnPosition() && (SigmaDay((datetime)PositionGetInteger(POSITION_TIME))<SigmaDay(now) || SigmaMinute(now)>=SigmaSessionCutoff(now,(int)Model)))
      CloseOwned("TIMER_CUTOFF_RECOVERY");
}
#ifdef SIGMA_LIFECYCLE_PROBE
bool gtLifecycleDone=false;
bool SigmaNativeLifecycleProbe()
{
   if(!MQLInfoInteger(MQL_TESTER)) return false;
   if(gtLifecycleDone || SigmaMinute(TimeCurrent())<600 || SigmaMinute(TimeCurrent())>=870) return false;
   gtLifecycleDone=true;bool ok=AccountInfoInteger(ACCOUNT_MARGIN_MODE)==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;
   MqlTick q;ok=SymbolInfoTick(_Symbol,q) && ok;
   double minlot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   CTrade foreign;foreign.SetExpertMagicNumber(Magic+999);
   foreign.SetTypeFillingBySymbol(_Symbol);
   ok=foreign.Buy(minlot,_Symbol,0,RoundPrice(q.ask-StopPoints),RoundPrice(q.ask+TargetPoints),"SIGMA fixture foreign") && ok;
   ulong foreignTicket=0;double foreignStop=0,foreignTarget=0,foreignVolume=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if((ulong)PositionGetInteger(POSITION_MAGIC)==Magic+999)
      {foreignTicket=ticket;foreignStop=PositionGetDouble(POSITION_SL);foreignTarget=PositionGetDouble(POSITION_TP);foreignVolume=PositionGetDouble(POSITION_VOLUME);}
   }
   ok=foreignTicket>0 && !OwnPosition() && ok;
   ok=Open(1,RoundPrice(q.ask-StopPoints),RoundPrice(q.ask+TargetPoints),0) && ok;
   ok=OwnPosition() && PositionGetDouble(POSITION_SL)>0 && PositionGetDouble(POSITION_TP)>0 && ok;
   ulong ownTicket=(ulong)PositionGetInteger(POSITION_TICKET);
   day=SigmaDay(TimeCurrent());lastSignal=iTime(_Symbol,sourceTF,1);
   runtimeJournalTesting=true;runtimeBlocked=false;string journal=SigmaStateKey();SigmaStateSave();
   initialRisk=0;ownedEntryTime=0;entries=0;
   SigmaStateRestore(TimeCurrent());
   ok=!runtimeBlocked && initialRisk>0 && ownedEntryTime>0 && OwnPosition()
      && (ulong)PositionGetInteger(POSITION_TICKET)==ownTicket && ok;
   bool rejected=!trade.Buy(0,_Symbol,0,0,0,"SIGMA invalid-volume fixture");
   bool budgetBlocked=!Open(1,SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE),q.ask+TargetPoints,0);
   ok=rejected && budgetBlocked && OwnPosition() && ok;
   double ownedVolume=PositionGetDouble(POSITION_VOLUME);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double partial=MathFloor(ownedVolume/2/step)*step;
   if(partial>=minlot && ownedVolume-partial>=minlot)
   {
      ok=trade.PositionClosePartial(ownTicket,partial) && OwnPosition()
         && MathAbs(PositionGetDouble(POSITION_VOLUME)-(ownedVolume-partial))<1e-8
         && PositionGetDouble(POSITION_SL)>0 && PositionGetDouble(POSITION_TP)>0 && ok;
   }
   else ok=false;
   SigmaRuntimeCutoffCheck(SigmaSessionTime(day)+870*60);
   ok=!OwnPosition() && PositionSelectByTicket(foreignTicket)
      && PositionGetDouble(POSITION_VOLUME)==foreignVolume
      && PositionGetDouble(POSITION_SL)==foreignStop && PositionGetDouble(POSITION_TP)==foreignTarget && ok;
   GlobalVariablesDeleteAll(journal);runtimeJournalTesting=false;
   // Only this fixture's own deliberately foreign-tagged position is cleaned up here.
   if(foreignTicket>0) ok=foreign.PositionClose(foreignTicket) && ok;
   int f=FileOpen(SigmaOutputRoot+"/native_lifecycle_"+RunId+".txt",FILE_COMMON|FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f!=INVALID_HANDLE)
   {FileWriteString(f,ok ? "PASS: native hedging ownership, staged SL/TP, original-risk restart, invalid-volume rejection, minimum-risk refusal, partial close protection, timer cutoff and foreign protection preserved." : "FAIL: native lifecycle fixture");FileClose(f);}
   Print(ok ? "SIGMA_NATIVE_LIFECYCLE_PASS" : "SIGMA_NATIVE_LIFECYCLE_FAILED");
   TesterStop();return true;
}
#endif
#endif
