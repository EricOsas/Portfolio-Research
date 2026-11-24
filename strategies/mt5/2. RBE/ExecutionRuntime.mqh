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
#ifndef RBE_EXECUTION_RUNTIME
#define RBE_EXECUTION_RUNTIME

// Persist terminal broker restrictions independently of daily/session resets.
// Terminal globals are platform-managed data, not a source/runtime dependency.
bool g_brokerRestricted=false;
string RBERestrictionKey()
{
    uint serverHash=2166136261;
    string server=AccountInfoString(ACCOUNT_SERVER);
    for(int i=0;i<StringLen(server);i++) serverHash=(serverHash^(uint)StringGetCharacter(server,i))*16777619;
    return "RBE.restrict."+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+"."
        +IntegerToString(serverHash)+"."+IntegerToString(Magic)+"."+_Symbol;
}
bool RBEAccountRestricted()
{
    return !(bool)MQLInfoInteger(MQL_TESTER) && (g_brokerRestricted || GlobalVariableCheck(RBERestrictionKey()));
}
void RBELatchRestriction(uint code)
{
    if((bool)MQLInfoInteger(MQL_TESTER)) return;
    if(code!=TRADE_RETCODE_CLOSE_ONLY && code!=TRADE_RETCODE_TRADE_DISABLED) return;
    g_brokerRestricted=true;
    if(GlobalVariableSet(RBERestrictionKey(),(double)code)==0)
        Print("[RBE] ERROR: broker restriction persistence failed; terminal trading remains blocked");
    GlobalVariablesFlush();
    PrintFormat("[RBE] BROKER_RESTRICTION retcode=%u; new requests paused, existing broker protection retained",code);
}

bool RBEOwnedSelectedPosition()
{
    if(PositionGetInteger(POSITION_MAGIC)!=Magic || PositionGetString(POSITION_SYMBOL)!=_Symbol) return false;
    if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE)==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING) return true;
    // A netting ticket can aggregate several EAs. Last position magic is not ownership.
    ulong id=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
    if(id==0 || !HistorySelectByPosition(id)) return false;
    bool owned=false;
    for(int i=0;i<HistoryDealsTotal();i++)
    {
        ulong deal=HistoryDealGetTicket(i);
        long entry=HistoryDealGetInteger(deal,DEAL_ENTRY);
        if(entry==DEAL_ENTRY_INOUT) return false; // Reversal lineage needs explicit settlement.
        if(entry!=DEAL_ENTRY_IN) continue;
        if(HistoryDealGetInteger(deal,DEAL_MAGIC)!=Magic || HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol) return false;
        owned=true;
    }
    return owned;
}
//+------------------------------------------------------------------+
//| CostEngine spec v1 - Commission scanner + helpers                |
//+------------------------------------------------------------------+
bool RBECommissionObserved()
{
    return false; // Trade sizing stays on the validated explicit commission; news BE may use closed-deal history.
}

double RBECommissionRTPerLot()
{
    return MathMax(0.0, Commission_Per_Lot_Override);
}

double RBESlipCashPerLot()
{
    double pts = MathMax(0.0, (double)Assumed_Slip_Points);
    if(pts <= 0.0) return 0.0;
    double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    if(tickSize <= 0.0 || tickValue <= 0.0) return 0.0;
    return (pts * _Point / tickSize) * tickValue;
}

double RBECostCashPerLot()
{
    return RBECommissionRTPerLot() + 2.0 * RBESlipCashPerLot();
}

bool RBEUseCostCoveredStops()
{
    return Use_Cost_Covered_Stops;
}

double RBECostCoveredPrice(double entry, double lots, bool isBuy)
{
    if(entry <= 0.0) return entry;
    double costCash = RBECostCashPerLot();
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    if(tickSize <= 0.0 || tickValue <= 0.0) return entry;
    // Both modeled cash and tick value are per lot; lot size cancels.
    double costTicks = (costCash / tickValue) * tickSize * MathMax(1.0, Cost_Coverage_Multiple);
    double rawCovered = isBuy ? entry + costTicks : entry - costTicks;
    return NormalizeDouble(rawCovered, _Digits);
}

double RBECashForDistance(double distance)
{
    if(distance <= 0.0) return 0.0;
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    if(tickSize <= 0.0 || tickValue <= 0.0) return 0.0;
    return (distance / tickSize) * tickValue;
}

//+------------------------------------------------------------------+
// NY DST: second Sunday March → first Sunday November
// Returns true if dt (UTC) is in NY summer time (EDT, UTC-4)




// Convert NY wall-clock hour:min to target server calendar date.
// Rene's 03:05 server range is NY 20:05 on prior evening.
datetime NYHMtoServer(datetime nyDay,int hour,int minute)
{
    return RBESessionTime(nyDay,hour,minute);
}

datetime RBENewsNewYork(datetime utc) { return utc+ClkNyUtcOffset(utc); }
datetime RBENewsWeek(datetime ny)
{
    MqlDateTime d; TimeToStruct(ny,d);
    return (datetime)((long)ny/86400*86400)-d.day_of_week*86400;
}
bool RBENewsValid()
{
    return g_newsReady && GetTickCount64()-g_newsSuccessMs<3600000
           && g_newsWeek==RBENewsWeek(RBENewsNewYork(TimeGMT()));
}
bool RBENewsImpactAllowed(const string name,string impact)
{
    string title=name; StringToUpper(title);
    StringToUpper(impact);
    if(StringFind(title,"NEW HOME SALES")>=0 || StringFind(title,"EXISTING HOME SALES")>=0
       || StringFind(title,"PENDING HOME SALES")>=0 || StringFind(title,"CRUDE OIL")>=0
       || (StringFind(title,"EIA")>=0 && StringFind(title,"STOCK")>=0)
       || StringFind(title,"OIL STOCK")>=0) impact="MEDIUM";
    if(News_Impact==NEWS_RED_ONLY) return impact=="HIGH";
    if(News_Impact==NEWS_RED_YELLOW)
        return impact=="HIGH" || impact=="MEDIUM";
    return News_Impact==NEWS_ALL;
}

string RBENewsField(string row,string key)
{
    int p=StringFind(row,"\""+key+"\""); if(p<0) return "";
    p=StringFind(row,":",p+StringLen(key)+2); if(p<0) return "";
    p++; while(p<StringLen(row) && StringGetCharacter(row,p)<=32) p++;
    if(StringGetCharacter(row,p)!='"') return "";
    string value=""; bool escape=false;
    for(int i=p+1;i<StringLen(row);i++)
    {
        ushort c=StringGetCharacter(row,i);
        if(escape) { value+=ShortToString(c); escape=false; continue; }
        if(c=='\\') { escape=true; continue; }
        if(c=='"') return value;
        value+=ShortToString(c);
    }
    return "";
}
bool RBENewsISO(string stamp,datetime &utc)
{
    int n=StringLen(stamp);
    if((n!=25 && n!=20) || StringSubstr(stamp,4,1)!="-" || StringSubstr(stamp,7,1)!="-"
       || StringSubstr(stamp,10,1)!="T" || StringSubstr(stamp,13,1)!=":" || StringSubstr(stamp,16,1)!=":") return false;
    for(int i=0;i<19;i++)
    {
        if(i==4 || i==7 || i==10 || i==13 || i==16) continue;
        ushort c=StringGetCharacter(stamp,i); if(c<'0' || c>'9') return false;
    }
    MqlDateTime d={};
    d.year=(int)StringToInteger(StringSubstr(stamp,0,4)); d.mon=(int)StringToInteger(StringSubstr(stamp,5,2));
    d.day=(int)StringToInteger(StringSubstr(stamp,8,2)); d.hour=(int)StringToInteger(StringSubstr(stamp,11,2));
    d.min=(int)StringToInteger(StringSubstr(stamp,14,2)); d.sec=(int)StringToInteger(StringSubstr(stamp,17,2));
    if(d.year<2000 || d.mon<1 || d.mon>12 || d.day<1 || d.day>31 || d.hour>23 || d.min>59 || d.sec>59) return false;
    datetime local=StructToTime(d); MqlDateTime check; TimeToStruct(local,check);
    if(check.year!=d.year || check.mon!=d.mon || check.day!=d.day) return false;
    int offset=0;
    if(n==20) { if(StringSubstr(stamp,19,1)!="Z") return false; }
    else
    {
        ushort sign=StringGetCharacter(stamp,19);
        if((sign!='+' && sign!='-') || StringSubstr(stamp,22,1)!=":") return false;
        for(int i=20;i<25;i++) { if(i==22) continue; ushort c=StringGetCharacter(stamp,i); if(c<'0' || c>'9') return false; }
        int h=(int)StringToInteger(StringSubstr(stamp,20,2)),m=(int)StringToInteger(StringSubstr(stamp,23,2));
        if(h>14 || m>59 || (h==14 && m!=0)) return false;
        offset=(h*60+m)*60*(sign=='+' ? 1 : -1);
    }
    utc=local-offset; return true;
}
bool RBENewsParse(string json,datetime week,int serverUTCOffset,datetime &events[])
{
    ArrayResize(events,0); StringTrimLeft(json); StringTrimRight(json);
    int size=StringLen(json); if(size<2 || StringGetCharacter(json,0)!='[' || StringGetCharacter(json,size-1)!=']') return false;
    int start=-1,dated=0; bool quoted=false,escape=false;
    for(int i=1;i<size-1;i++)
    {
        ushort c=StringGetCharacter(json,i);
        if(quoted) { if(escape) escape=false; else if(c=='\\') escape=true; else if(c=='"') quoted=false; continue; }
        if(c=='"') { quoted=true; continue; }
        if(c=='{') { if(start>=0) return false; start=i; continue; }
        if(c!='}') continue;
        if(start<0) return false;
        string row=StringSubstr(json,start,i-start+1); start=-1;
        string currency=RBENewsField(row,"country"),impact=RBENewsField(row,"impact");
        string stamp=RBENewsField(row,"date"),title=RBENewsField(row,"title");
        if(currency=="" || impact=="" || stamp=="" || title=="") return false;
        datetime utc; if(!RBENewsISO(stamp,utc) || RBENewsWeek(RBENewsNewYork(utc))!=week) return false;
        dated++;
        if(currency=="USD" && RBENewsImpactAllowed(title,impact))
        { int n=ArraySize(events); ArrayResize(events,n+1); events[n]=utc+serverUTCOffset; }
    }
    return dated>0 && start<0 && !quoted;
}

void RBENewsRefresh(datetime now)
{
    if(News_Impact==NEWS_DISABLED || now<=0) return;
    if((bool)MQLInfoInteger(MQL_TESTER) || !(bool)TerminalInfoInteger(TERMINAL_CONNECTED)) return;
    ulong tick=GetTickCount64();
    if(g_newsAttemptMs>0 && tick-g_newsAttemptMs<(ulong)(RBENewsValid()?1800000:300000)) return;
    g_newsAttemptMs=tick;
    string payload;datetime fetched;int requestError;
    int status=RBEFeedGet(payload,fetched,requestError);
    if(status!=200)
    {
        if(!g_newsLaunchLogged)
            PrintFormat("[RBE] ForexFactory unavailable (HTTP %d, error %d): %s; new entries blocked; retries run silently",status,requestError,
                status==429?"provider rate limited; 15-minute backoff":"check provider access and allowed WebRequest URL https://nfs.faireconomy.media");
        g_newsLaunchLogged=true;
        return;
    }
    datetime week=RBENewsWeek(RBENewsNewYork(TimeGMT())),found[];
    int serverUTCOffset=(int)(MathRound((double)(TimeTradeServer()-TimeGMT())/3600.0)*3600.0);
    if(!RBENewsParse(payload,week,serverUTCOffset,found))
    {
        if(!g_newsLaunchLogged) Print("[RBE] ForexFactory payload invalid or wrong week; new entries blocked; retries run silently");
        g_newsLaunchLogged=true; return;
    }
    ArraySort(found);
    ArrayResize(g_newsEvents,0);
    for(int i=0;i<ArraySize(found);i++)
        if(i==0 || found[i]!=found[i-1])
        { int n=ArraySize(g_newsEvents); ArrayResize(g_newsEvents,n+1); g_newsEvents[n]=found[i]; }
    g_newsReady=true;
    g_newsWeek=week; g_newsSuccessMs=GetTickCount64()-(ulong)(MathMax(0,TimeGMT()-fetched)*1000);
    datetime nyToday=(datetime)((long)RBENewsNewYork(TimeGMT())/86400*86400);
    int today=0,throughWeekEnd=0;
    for(int i=0;i<ArraySize(g_newsEvents);i++)
    {
        datetime eventNY=RBENewsNewYork(g_newsEvents[i]-serverUTCOffset);
        if(eventNY<nyToday || eventNY>=week+7*86400) continue;
        throughWeekEnd++;
        if(eventNY<nyToday+86400) today++;
    }
    if(!g_newsLaunchLogged)
        PrintFormat("[RBE] ForexFactory USD news ready: %d unique release times today; %d from today through week-end (NY dates); refreshes run silently",
                    today,throughWeekEnd);
    g_newsLaunchLogged=true;
}

bool RBENewsKnownWindow(datetime now,datetime &eventTime)
{
    eventTime=0;
    if(News_Impact==NEWS_DISABLED || !g_newsReady || g_newsWeek!=RBENewsWeek(RBENewsNewYork(TimeGMT()))) return false;
    int halfSeconds=(int)News_Window*30;
    for(int i=0;i<ArraySize(g_newsEvents);i++)
        if(now>=g_newsEvents[i]-halfSeconds && now<=g_newsEvents[i]+halfSeconds)
        { eventTime=g_newsEvents[i]; return true; }
    return false;
}
bool RBENewsWindow(datetime now,datetime &eventTime)
{
    bool known=RBENewsKnownWindow(now,eventTime);
    return News_Impact!=NEWS_DISABLED && (!RBENewsValid() || known);
}

double RBENewsCommissionPerLot(datetime now)
{
    if(g_newsObservedCommission>0) return g_newsObservedCommission;
    if(g_newsCommissionChecked>0 && now-g_newsCommissionChecked<1800) return RBECommissionRTPerLot();
    g_newsCommissionChecked=now;
    if(!HistorySelect(now-90*86400,now)) return RBECommissionRTPerLot();
    double commission=0,lots=0;
    for(int i=0;i<HistoryDealsTotal();i++)
    {
        ulong deal=HistoryDealGetTicket(i);
        if(HistoryDealGetInteger(deal,DEAL_MAGIC)!=Magic || HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol) continue;
        commission+=MathAbs(HistoryDealGetDouble(deal,DEAL_COMMISSION));
        if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY)==DEAL_ENTRY_OUT)
            lots+=HistoryDealGetDouble(deal,DEAL_VOLUME);
    }
    if(lots>0 && commission>0) g_newsObservedCommission=commission/lots;
    return g_newsObservedCommission>0 ? g_newsObservedCommission : RBECommissionRTPerLot();
}

struct RBENewsDecision { ulong ticket;datetime event;string outcome; };
RBENewsDecision g_newsDecisions[];
datetime g_newsGuardEvent=0;
void RBENewsDecisionLog(ulong ticket,datetime event,string outcome,double mark,double desired)
{
    for(int i=0;i<ArraySize(g_newsDecisions);i++)
        if(g_newsDecisions[i].ticket==ticket && g_newsDecisions[i].event==event)
        {
            if(g_newsDecisions[i].outcome==outcome)return;
            g_newsDecisions[i].outcome=outcome;
            PrintFormat("[RBE] NEWS_BE position=%I64u eventNY=%s outcome=%s mark=%.5f desired=%.5f",ticket,TimeToString(ServerToNewYork(event),TIME_DATE|TIME_MINUTES),outcome,mark,desired);return;
        }
    int n=ArraySize(g_newsDecisions);ArrayResize(g_newsDecisions,n+1);
    g_newsDecisions[n].ticket=ticket;g_newsDecisions[n].event=event;g_newsDecisions[n].outcome=outcome;
    PrintFormat("[RBE] NEWS_BE position=%I64u eventNY=%s outcome=%s mark=%.5f desired=%.5f",ticket,TimeToString(ServerToNewYork(event),TIME_DATE|TIME_MINUTES),outcome,mark,desired);
}
void RBENewsProtect(datetime now,datetime eventTime)
{
    double tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
    double tickValue=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
    if(tickSize<=0 || tickValue<=0) return;
    double cost=(RBENewsCommissionPerLot(now)+2*RBESlipCashPerLot())*MathMax(1.0,Cost_Coverage_Multiple);
    double distance=cost/tickValue*tickSize;
    MqlTick tick;
    bool freshQuote=SymbolInfoTick(_Symbol,tick) && tick.time>0 && now>=tick.time && now-tick.time<=60;
    double stops=MathMax(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL))*_Point;
    int matched=0;
    for(int i=PositionsTotal()-1;i>=0;i--)
    {
        ulong ticket=PositionGetTicket(i);
        if(!RBEOwnedSelectedPosition()) continue;
        matched++;
        if(!freshQuote)
        {RBENewsDecisionLog(ticket,eventTime,"waiting_for_fresh_quote",0,0);continue;}
        bool buy=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY;
        double entry=PositionGetDouble(POSITION_PRICE_OPEN),sl=PositionGetDouble(POSITION_SL);
        double desired=NormalizeDouble(entry+(buy ? distance : -distance),_Digits);
        double mark=buy?tick.bid:tick.ask;
        if((sl>0) && (buy?desired<=sl+tickSize/2:desired>=sl-tickSize/2))
        {RBENewsDecisionLog(ticket,eventTime,"already_protected",mark,desired);continue;}
        if(buy?desired>=mark-stops-tickSize:desired<=mark+stops+tickSize)
        {RBENewsDecisionLog(ticket,eventTime,"waiting_for_profit_or_broker_distance",mark,desired);continue;}
        if(!g_trade.PositionModify(ticket,desired,PositionGetDouble(POSITION_TP))
           || g_trade.ResultRetcode()!=TRADE_RETCODE_DONE)
        {
            RBENewsDecisionLog(ticket,eventTime,"broker_rejected",mark,desired);
            PrintFormat("[RBE] News cost-covered stop failed #%I64u: %s",ticket,g_trade.ResultRetcodeDescription());
        }
        else RBENewsDecisionLog(ticket,eventTime,"applied",mark,desired);
    }
    if(matched==0)RBENewsDecisionLog(0,eventTime,"no_owned_position",0,0);
}

void RBENewsGuard(datetime now)
{
    if(RBEAccountRestricted()) return;
    if(News_Impact==NEWS_DISABLED || (bool)MQLInfoInteger(MQL_TESTER)) return;
    datetime eventTime=0;
    bool blocked=RBENewsWindow(now,eventTime);
    if(!blocked) { g_newsBlocked=false; return; }
    g_newsBlocked=true;
    if(eventTime<=0) return; // Unknown release schedule cannot be fabricated.
    bool fresh=RBENewsValid();
    if(g_newsGuardEvent!=eventTime)
    {
        g_newsGuardEvent=eventTime;
        PrintFormat("[RBE] NEWS_GUARD eventNY=%s BE=%s flatten=%s calendar=%s",
            TimeToString(ServerToNewYork(eventTime),TIME_DATE|TIME_MINUTES),News_Cost_Covered_BE?"on":"off",
            News_Flatten_Before?"on":"off",fresh?"fresh":"cached protective-only");
    }
    for(int i=OrdersTotal()-1;i>=0;i--)
    {
        ulong ticket=OrderGetTicket(i);
        if(OrderGetInteger(ORDER_MAGIC)==Magic && OrderGetString(ORDER_SYMBOL)==_Symbol && RBEPendingType(OrderGetInteger(ORDER_TYPE)))
            g_trade.OrderDelete(ticket);
    }
    if(News_Cost_Covered_BE && now<eventTime) RBENewsProtect(now,eventTime);
    if(News_Flatten_Before && fresh && now<eventTime)
        for(int i=PositionsTotal()-1;i>=0;i--)
        {
            ulong ticket=PositionGetTicket(i);
            if(RBEOwnedSelectedPosition())
                RBECloseOwned(ticket,"news");
        }
}

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
bool DeleteOrders(datetime now)
{
    if(RBEAccountRestricted()) return false;
    bool ok=true;
    if(now<=0) return false;
    for(int i=OrdersTotal()-1;i>=0;i--)
    {
        ulong t=OrderGetTicket(i);
        if(OrderGetInteger(ORDER_MAGIC)!=Magic || OrderGetString(ORDER_SYMBOL)!=Symbol()) continue;
        if(!RBEPendingType(OrderGetInteger(ORDER_TYPE))) continue;
        datetime setup=(datetime)OrderGetInteger(ORDER_TIME_SETUP);
        datetime cutoff=NYHMtoServer(RBENYDay(setup),Delete_Hour,Delete_Min);
        bool valid=now<cutoff && (ENUM_ORDER_TYPE_TIME)OrderGetInteger(ORDER_TYPE_TIME)==ORDER_TIME_SPECIFIED
                   && (datetime)OrderGetInteger(ORDER_TIME_EXPIRATION)==cutoff;
        if(valid) continue;
        if(!g_trade.OrderDelete(t) || g_trade.ResultRetcode()!=TRADE_RETCODE_DONE)
        {
            PrintFormat("[RBE] Pending cancel failed #%I64u: %s",t,g_trade.ResultRetcodeDescription());
            ok=false;
        }
    }
    return ok;
}
void PruneConsumedOrders()
{
    if(RBEAccountRestricted()) return;
    if(!g_replayReady || !g_rangeReady) return;
    MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return;
    double buyLevel=NormalizeDouble(g_rngHi,_Digits),sellLevel=NormalizeDouble(g_rngLo,_Digits);
    for(int i=OrdersTotal()-1;i>=0;i--)
    {
        ulong ticket=OrderGetTicket(i);
        if(OrderGetInteger(ORDER_MAGIC)!=Magic || OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
        ENUM_ORDER_TYPE type=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
        bool stale=(type==ORDER_TYPE_BUY_STOP && (g_buyTouched || tick.ask>=buyLevel || Max_Buy<=g_dayBuy))
                || (type==ORDER_TYPE_SELL_STOP && (g_sellTouched || tick.bid<=sellLevel || Max_Sell<=g_daySell));
        if(stale && (!g_trade.OrderDelete(ticket) || g_trade.ResultRetcode()!=TRADE_RETCODE_DONE))
            PrintFormat("[RBE] Consumed-side pending cancel failed #%I64u: %s",ticket,g_trade.ResultRetcodeDescription());
    }
}
// True if this EA already holds an open position of this side opened in the current session.
bool RBEOwnedSideOpen(bool buy)
{
    for(int i=PositionsTotal()-1;i>=0;i--)
    {
        if(PositionGetTicket(i)==0) continue;
        if(PositionGetInteger(POSITION_MAGIC)!=Magic || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
        if(((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)!=buy) continue;
        if((datetime)PositionGetInteger(POSITION_TIME)>=g_t1) return true;
    }
    return false;
}
void PlaceOrders(datetime now)
{
    if(RBEAccountRestricted()) return;
    // Netting combines the entire symbol into one ticket. Do not add risk to
    // an allocation that this EA cannot exclusively identify and manage.
    if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
    {
        for(int i=PositionsTotal()-1;i>=0;i--)
            if(PositionGetTicket(i)>0 && PositionGetString(POSITION_SYMBOL)==_Symbol && !RBEOwnedSelectedPosition()) return;
        for(int i=OrdersTotal()-1;i>=0;i--)
            if(OrderGetTicket(i)>0 && OrderGetString(ORDER_SYMBOL)==_Symbol && OrderGetInteger(ORDER_MAGIC)!=Magic) return;
    }
    if(!g_replayReady || !g_rangeReady) return;
    if(!g_recoveryHistoryReady || !g_recoveryProtected) return;
    if(g_newsBlocked) return;
    if(!DeleteOrders(now)) return;
    MqlTick tick; if(!SymbolInfoTick(_Symbol,tick) || tick.time_msc<=g_liveAfterMsc) return;
    double bEnt=NormalizeDouble(g_rngHi,_Digits),sEnt=NormalizeDouble(g_rngLo,_Digits);
    double bSL=CalcStop(bEnt,true),sSL=CalcStop(sEnt,false);
    double bLots=CalcLots(bEnt,bSL),sLots=CalcLots(sEnt,sSL);
    datetime cutoff=g_view[2].cutoff;
    long expiryModes=SymbolInfoInteger(_Symbol,SYMBOL_EXPIRATION_MODE);
    bool canExpire=(expiryModes & SYMBOL_EXPIRATION_SPECIFIED)!=0;
    bool sessionOK=RBEEntryBeforeExpiry(now,TimeTradeServer(),cutoff) && g_view[2].accepted && canExpire;
    bool buyAllowed=sessionOK && Max_Buy>g_dayBuy && g_dayTotal<Max_Trades && bLots>0;
    bool sellAllowed=sessionOK && Max_Sell>g_daySell && g_dayTotal<Max_Trades && sLots>0;
    // Independent of replay/event flags: an open position on a side consumes that side.
    if(RBEOwnedSideOpen(true)) { g_buyTouched=true; g_recoveryCountsDirty=true; }
    if(RBEOwnedSideOpen(false)) { g_sellTouched=true; g_recoveryCountsDirty=true; }
    bool canBuy=buyAllowed && !g_buyTouched && !RBEOwnedSideOpen(true) && tick.ask<bEnt;
    bool canSell=sellAllowed && !g_sellTouched && !RBEOwnedSideOpen(false) && tick.bid>sEnt;
    bool buyPending=false,sellPending=false;
    double priceTolerance=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE)*0.5;
    if(priceTolerance<=0) priceTolerance=_Point*0.5;
    double volumeTolerance=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP)*0.5;
    for(int i=OrdersTotal()-1;i>=0;i--)
    {
        ulong t=OrderGetTicket(i);
        if(OrderGetInteger(ORDER_MAGIC)!=Magic || OrderGetString(ORDER_SYMBOL)!=Symbol()) continue;
        ENUM_ORDER_TYPE type=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
        if(!RBEPendingType(type)) continue;
        bool buy=type==ORDER_TYPE_BUY_STOP, sell=type==ORDER_TYPE_SELL_STOP;
        bool sideAllowed=buy ? buyAllowed : sellAllowed;
        bool beforeTouch=RBEPendingBeforeTouch(buy ? (g_buyTouched || tick.ask>=bEnt) : (g_sellTouched || tick.bid<=sEnt),
                                               buy ? g_buyTouchTime : g_sellTouchTime,OrderGetInteger(ORDER_TIME_SETUP_MSC));
        bool duplicate=buy ? buyPending : sellPending;
        // An order armed before the first touch belongs to that trigger. New
        // placement still requires canBuy/canSell and an untouched level.
        bool wanted=sideAllowed && beforeTouch && !duplicate;
        string cancelReason=!sideAllowed ? "session/risk/trade limit" : !beforeTouch ? "consumed before order or unknown touch" : duplicate ? "duplicate pending" : "settings changed";
        if(wanted)
            wanted=MathAbs(OrderGetDouble(ORDER_PRICE_OPEN)-(buy ? bEnt : sEnt))<=priceTolerance
                   && MathAbs(OrderGetDouble(ORDER_SL)-(buy ? bSL : sSL))<=priceTolerance
                   && MathAbs(OrderGetDouble(ORDER_VOLUME_INITIAL)-(buy ? bLots : sLots))<=volumeTolerance
                   && (datetime)OrderGetInteger(ORDER_TIME_EXPIRATION)==cutoff;
        if(wanted) { if(buy) buyPending=true; else sellPending=true; continue; }
        if(!g_trade.OrderDelete(t) || g_trade.ResultRetcode()!=TRADE_RETCODE_DONE)
        {
            PrintFormat("[RBE] Pending update cancel failed #%I64u (%s): %s",t,cancelReason,g_trade.ResultRetcodeDescription());
            if(buy) buyPending=true;
            if(sell) sellPending=true;
        }
    }
    // Only fresh, unbroken levels may acquire a live broker order.
    if(!buyPending && canBuy && RBEEntryBeforeExpiry(now,TimeTradeServer(),cutoff))
        g_trade.BuyStop(bLots,bEnt,Symbol(),bSL,0,ORDER_TIME_SPECIFIED,cutoff,Commentary);
    if(!sellPending && canSell && RBEEntryBeforeExpiry(now,TimeTradeServer(),cutoff))
        g_trade.SellStop(sLots,sEnt,Symbol(),sSL,0,ORDER_TIME_SPECIFIED,cutoff,Commentary);
}

//+------------------------------------------------------------------+
bool RBEPendingType(long type)
{ return type==ORDER_TYPE_BUY_STOP || type==ORDER_TYPE_SELL_STOP; }
bool RBEEntryBeforeExpiry(datetime quoteTime,datetime serverTime,datetime expiry)
{
    // Quotes can predate the wall clock, and earlier broker calls consume time.
    // Leave one second for timestamp granularity; never extend the session.
    return quoteTime>0 && serverTime>0 && quoteTime<expiry && expiry-serverTime>1;
}
bool RBEPendingBeforeTouch(bool consumed,datetime touchTime,long setupMsc)
{ return !consumed || (touchTime>0 && setupMsc>0 && setupMsc<(long)touchTime*1000); }
bool RBERecenterConfirmed(uint code,bool selected,double sl,double tp,double desiredSL,double desiredTP,double tickSize)
{
    return selected && (code==TRADE_RETCODE_DONE || code==TRADE_RETCODE_NO_CHANGES)
        && MathAbs(sl-desiredSL)<=tickSize*.5 && MathAbs(tp-desiredTP)<=tickSize*.5;
}
bool RBECloseSettled(long state,double before,double current,double filled,double step)
{
    bool terminal=state==ORDER_STATE_FILLED || state==ORDER_STATE_CANCELED || state==ORDER_STATE_REJECTED || state==ORDER_STATE_EXPIRED;
    return terminal && current<=before-filled+step*.5;
}
struct RBECloseRequest { ulong identifier,order;double volume;datetime sentTime; };
RBECloseRequest g_closeRequests[];
bool g_closeEvidenceReady=true;
string RBECloseFile(ulong identifier)
{
    return RBERestrictionKey()+".close."+IntegerToString(identifier)+".bin";
}
bool RBESaveClose(RBECloseRequest &request)
{
    if((bool)MQLInfoInteger(MQL_TESTER)) return true;
    string target=RBECloseFile(request.identifier),temporary=target+".pending";
    int file=FileOpen(temporary,FILE_BIN|FILE_WRITE|FILE_COMMON);
    if(file==INVALID_HANDLE) return false;
    ResetLastError();
    FileWriteInteger(file,1); FileWriteLong(file,(long)request.identifier);
    FileWriteLong(file,(long)request.order); FileWriteDouble(file,request.volume);
    FileWriteInteger(file,913702); FileFlush(file);
    bool complete=FileTell(file)==32 && GetLastError()==0;FileClose(file);
    if(!complete)return false;
    return FileMove(temporary,FILE_COMMON,target,FILE_COMMON|FILE_REWRITE);
}
bool RBELoadClose(ulong identifier,RBECloseRequest &request)
{
    if((bool)MQLInfoInteger(MQL_TESTER) || !FileIsExist(RBECloseFile(identifier),FILE_COMMON)) return true;
    int file=FileOpen(RBECloseFile(identifier),FILE_BIN|FILE_READ|FILE_COMMON);
    if(file==INVALID_HANDLE) return false;
    bool valid=FileSize(file)==32;
    int version=FileReadInteger(file);ulong id=(ulong)FileReadLong(file);
    ulong order=(ulong)FileReadLong(file);double volume=FileReadDouble(file);
    int footer=FileReadInteger(file);FileClose(file);
    if(!valid || version!=1 || id!=identifier || footer!=913702 || volume<=0) return false;
    request.identifier=id;request.order=order;request.volume=volume;
    return true;
}
bool RBEPositionClosing(ulong identifier)
{
    for(int i=0;i<ArraySize(g_closeRequests);i++)
        if(g_closeRequests[i].identifier==identifier && g_closeRequests[i].volume!=0)return true;
    return !(bool)MQLInfoInteger(MQL_TESTER) && FileIsExist(RBECloseFile(identifier),FILE_COMMON);
}
bool RBEClosedOwnedHistory(ulong identifier)
{
    if(!HistorySelectByPosition(identifier))return false;
    double entered=0,exited=0;
    for(int i=0;i<HistoryDealsTotal();i++)
    {
        ulong deal=HistoryDealGetTicket(i);
        if((ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID)!=identifier || HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol)return false;
        long entry=HistoryDealGetInteger(deal,DEAL_ENTRY);
        if(entry==DEAL_ENTRY_INOUT)return false;
        if(entry==DEAL_ENTRY_IN)
        {
            if(HistoryDealGetInteger(deal,DEAL_MAGIC)!=Magic)return false;
            entered+=HistoryDealGetDouble(deal,DEAL_VOLUME);
        }
        else if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY)exited+=HistoryDealGetDouble(deal,DEAL_VOLUME);
    }
    double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
    return entered>0 && MathAbs(entered-exited)<=MathMax(step*.5,1e-8);
}
void RBEReconcileCloseIntents()
{
    g_closeEvidenceReady=true;
    if((bool)MQLInfoInteger(MQL_TESTER))return;
    string prefix=RBERestrictionKey()+".close.",name;
    long search=FileFindFirst(prefix+"*.bin",name,FILE_COMMON);
    if(search==INVALID_HANDLE)return;
    do
    {
        ulong identifier=(ulong)StringToInteger(StringSubstr(name,StringLen(prefix)));
        RBECloseRequest request;
        if(identifier==0 || !RBELoadClose(identifier,request)) {g_closeEvidenceReady=false;continue;}
        bool present=false;
        for(int i=PositionsTotal()-1;i>=0;i--)
            if(PositionGetTicket(i)>0 && (ulong)PositionGetInteger(POSITION_IDENTIFIER)==identifier){present=true;break;}
        if(!present && RBEClosedOwnedHistory(identifier) && FileDelete(name,FILE_COMMON))
        {
            for(int i=0;i<ArraySize(g_closeRequests);i++)
                if(g_closeRequests[i].identifier==identifier){g_closeRequests[i].volume=0;g_closeRequests[i].order=0;}
        }
        else g_closeEvidenceReady=false;
    }while(FileFindNext(search,name));
    FileFindClose(search);
}
bool RBECloseOwned(ulong ticket,string reason)
{
    if(RBEAccountRestricted()) return false;
    if(!PositionSelectByTicket(ticket))return true;
    if(!RBEOwnedSelectedPosition())return false;
    ulong id=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
    double volume=PositionGetDouble(POSITION_VOLUME);
    int index=-1;
    for(int i=0;i<ArraySize(g_closeRequests);i++)if(g_closeRequests[i].identifier==id){index=i;break;}
    if(index<0)
    {
        index=ArraySize(g_closeRequests);ArrayResize(g_closeRequests,index+1);
        // ArrayResize does not zero new elements; RBELoadClose leaves them untouched when no file exists.
        g_closeRequests[index].identifier=id;
        g_closeRequests[index].order=0;
        g_closeRequests[index].volume=0;
        g_closeRequests[index].sentTime=0;
        if(!RBELoadClose(id,g_closeRequests[index]))
        {g_closeRequests[index].volume=-1;Print("[RBE] Close checkpoint invalid; existing protection retained");return false;}
    }
    if(g_closeRequests[index].volume<0)return false;
    // Tester only: a close sent in this run that never produced an acknowledged
    // order (no ResultOrder, or no history entry) used to wait forever, so the
    // position sat open until its stop, days later. In the tester, once the
    // position is still open 3 simulated seconds after the send, the close is
    // sent again. Live trading keeps the rule: missing acknowledgement is never
    // treated as permission to send a second close.
    bool testerRetry=(bool)MQLInfoInteger(MQL_TESTER) && g_closeRequests[index].sentTime>0
                     && TimeCurrent()-g_closeRequests[index].sentTime>=3;
    // A durable intent without an assigned order can represent a request sent
    // before termination/timeout. Never turn missing acknowledgement into a retry.
    if(g_closeRequests[index].volume>0 && g_closeRequests[index].order==0 && !testerRetry) return true;
    if(g_closeRequests[index].order>0)
    {
        ulong order=g_closeRequests[index].order;
        if(OrderSelect(order))return true;
        if(!HistoryOrderSelect(order))
        {
            if(!testerRetry)return true;
            g_closeRequests[index].order=0;
        }
        else
        {
            double filled=HistoryOrderGetDouble(order,ORDER_VOLUME_INITIAL)-HistoryOrderGetDouble(order,ORDER_VOLUME_CURRENT);
            if(!RBECloseSettled(HistoryOrderGetInteger(order,ORDER_STATE),g_closeRequests[index].volume,volume,filled,SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP)))return true;
        }
    }
    g_closeRequests[index].order=0;g_closeRequests[index].volume=volume;
    if(!RBESaveClose(g_closeRequests[index]))return false;
    g_closeRequests[index].sentTime=TimeCurrent();
    bool sent=g_trade.PositionClose(ticket);uint code=g_trade.ResultRetcode();
    if(sent && (code==TRADE_RETCODE_DONE || code==TRADE_RETCODE_DONE_PARTIAL || code==TRADE_RETCODE_PLACED))
    {g_closeRequests[index].order=g_trade.ResultOrder();RBESaveClose(g_closeRequests[index]);return true;}
    if(code==TRADE_RETCODE_POSITION_CLOSED)return true;
    if(code!=TRADE_RETCODE_TIMEOUT && code!=TRADE_RETCODE_CONNECTION && code!=TRADE_RETCODE_ERROR && !RBEAccountRestricted())
    {
        g_closeRequests[index].volume=0;
        if(!(bool)MQLInfoInteger(MQL_TESTER))FileDelete(RBECloseFile(id),FILE_COMMON);
    }
    PrintFormat("[RBE] Owned close retry #%I64u reason=%s: %s",ticket,reason,g_trade.ResultRetcodeDescription());return false;
}
// Cutoff tracking: first tick at/after the 11:55 NY time for each open owned position.
struct RBEDueRecord { ulong ticket; datetime first; datetime lastForce; bool reported; };
RBEDueRecord g_due[];
int RBEDueIndex(ulong ticket)
{
    for(int i=0;i<ArraySize(g_due);i++) if(g_due[i].ticket==ticket) return i;
    int n=ArraySize(g_due);
    if(n>=64) // keep the list short: drop the oldest entry
    {
        for(int j=1;j<n;j++) g_due[j-1]=g_due[j];
        n--;
    }
    ArrayResize(g_due,n+1);
    g_due[n].ticket=ticket;g_due[n].first=0;g_due[n].lastForce=0;g_due[n].reported=false;
    return n;
}
string RBECloseStateText(ulong identifier)
{
    for(int i=0;i<ArraySize(g_closeRequests);i++)
        if(g_closeRequests[i].identifier==identifier)
            return StringFormat("checkpoint volume=%.2f order=%I64u",g_closeRequests[i].volume,g_closeRequests[i].order);
    return "no checkpoint yet";
}
void ClosePosTime(datetime now)
{
    if(!Close_Positions || now<=0) return;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong t = PositionGetTicket(i);
        if(!PositionSelectByTicket(t)) continue;
        bool owned=RBEOwnedSelectedPosition();
        datetime opened=(datetime)PositionGetInteger(POSITION_TIME);
        datetime closeTime=NYHMtoServer(RBENYDay(opened),Close_Hour,Close_Min);
        if(now<closeTime) continue;
        ulong identifier=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
        int k=RBEDueIndex(t);
        if(g_due[k].first==0) g_due[k].first=now;
        if(owned) RBECloseOwned(t,"cutoff");
        if(!PositionSelectByTicket(t)) continue; // closed
        // Still open after the close step. Say why, once per position, so a missed cutoff is never silent.
        if(!g_due[k].reported)
        {
            g_due[k].reported=true;
            PrintFormat("[RBE] Cutoff due but position #%I64u is still open: owned=%s restricted=%s %s; due %s, now %s",
                        t,owned ? "yes" : "no",RBEAccountRestricted() ? "yes" : "no",RBECloseStateText(identifier),
                        TimeToString(closeTime,TIME_DATE|TIME_SECONDS),TimeToString(now,TIME_DATE|TIME_SECONDS));
        }
        // Strategy Tester only: the model closes at 11:55 NY, so a position still open 5 seconds later is closed directly.
        // Live trading keeps the checkpoint rules and never sends a second close on missing acknowledgement.
        if((bool)MQLInfoInteger(MQL_TESTER) && now-g_due[k].first>=5 && now-g_due[k].lastForce>=60)
        {
            g_due[k].lastForce=now;
            bool ok=g_trade.PositionClose(t);
            PrintFormat("[RBE] Tester forced cutoff close #%I64u: sent=%s retcode=%u %s",t,ok ? "yes" : "no",g_trade.ResultRetcode(),g_trade.ResultRetcodeDescription());
        }
    }
}

//+------------------------------------------------------------------+
ulong RBEOwnedPositionTicket(ulong identifier)
{
    for(int i=PositionsTotal()-1;i>=0;i--)
    {
        ulong ticket=PositionGetTicket(i);
        if((ulong)PositionGetInteger(POSITION_IDENTIFIER)==identifier && RBEOwnedSelectedPosition())
            return ticket;
    }
    return 0;
}
bool RBERecoveryQuote(MqlTick &tick)
{
    bool connected=(bool)TerminalInfoInteger(TERMINAL_CONNECTED);
    if((bool)MQLInfoInteger(MQL_TESTER)) connected=true;
    if(!connected) { g_terminalConnected=false; return false; }
    if(!SymbolInfoTick(_Symbol,tick) || tick.time<=0) return false;
    if(!g_terminalConnected)
    {
        g_terminalConnected=true; g_recoveryCountsDirty=true;
        g_recoveryHistoryReady=false; g_liveAfterMsc=tick.time_msc;
        g_replayMinute=0;
    }
    datetime now=TimeTradeServer();
    return now>0 && tick.time<=now+2 && now-tick.time<=60;
}
void RBERecoverSessionCounts(datetime now)
{
    if(!g_recoveryCountsDirty) return;
    g_recoveryHistoryReady=false;
    if(g_t1<=0 || now<g_t1) { g_recoveryHistoryReady=true; return; }
    if(!HistorySelect(g_t1,now)) return;
    ulong ids[];
    int buys=0,sells=0;
    datetime cutoff=NYHMtoServer(g_dayBase,Close_Hour,Close_Min);
    for(int i=0;i<HistoryDealsTotal();i++)
    {
        ulong deal=HistoryDealGetTicket(i);
        if(HistoryDealGetInteger(deal,DEAL_MAGIC)!=Magic || HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol) continue;
        if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY)!=DEAL_ENTRY_IN) continue;
        datetime time=(datetime)HistoryDealGetInteger(deal,DEAL_TIME);
        if(time<g_t1 || time>=cutoff) continue;
        ulong id=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
        bool known=false;
        for(int j=0;j<ArraySize(ids);j++) if(ids[j]==id) { known=true; break; }
        if(known || id==0) continue;
        int n=ArraySize(ids); ArrayResize(ids,n+1); ids[n]=id;
        if((ENUM_DEAL_TYPE)HistoryDealGetInteger(deal,DEAL_TYPE)==DEAL_TYPE_BUY) buys++;
        else if((ENUM_DEAL_TYPE)HistoryDealGetInteger(deal,DEAL_TYPE)==DEAL_TYPE_SELL) sells++;
    }
    // Broker inventory remains useful while its most recent deal reaches history.
    for(int i=0;i<PositionsTotal();i++)
    {
        if(PositionGetTicket(i)==0 || PositionGetInteger(POSITION_MAGIC)!=Magic
           || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
        datetime time=(datetime)PositionGetInteger(POSITION_TIME);
        if(time<g_t1 || time>=cutoff) continue;
        ulong id=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
        bool known=false;
        for(int j=0;j<ArraySize(ids);j++) if(ids[j]==id) { known=true; break; }
        if(known) continue;
        if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY) buys++;
        else sells++;
    }
    g_dayBuy=buys; g_daySell=sells; g_dayTotal=buys+sells;
    if(buys>0) g_buyTouched=true;
    if(sells>0) g_sellTouched=true;
    g_recoveryHistoryReady=true; g_recoveryCountsDirty=false;
}
bool RBERestoreMissingStop(ulong ticket)
{
    if(!PositionSelectByTicket(ticket)) return true;
    if(PositionGetDouble(POSITION_SL)>0) return true; // Broker protection is authoritative.
    if(RBEAccountRestricted()) return false;
    bool buy=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY;
    double entry=PositionGetDouble(POSITION_PRICE_OPEN),tp=PositionGetDouble(POSITION_TP);
    ulong id=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
    double sl=CalcStop(entry,buy);
    if(HistorySelectByPosition(id))
        for(int i=0;i<HistoryDealsTotal();i++)
        {
            ulong deal=HistoryDealGetTicket(i);
            if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY)!=DEAL_ENTRY_IN) continue;
            ulong order=(ulong)HistoryDealGetInteger(deal,DEAL_ORDER);
            double original=HistoryOrderGetDouble(order,ORDER_SL);
            double intended=HistoryOrderGetDouble(order,ORDER_PRICE_OPEN);
            if(original>0 && intended>0) { sl=NormalizeDouble(original+entry-intended,_Digits); break; }
        }
    if(sl<=0) return false;
    MqlTick tick; if(!RBERecoveryQuote(tick)) return false;
    bool crossed=buy ? tick.bid<=sl : tick.ask>=sl;
    bool sent=crossed ? g_trade.PositionClose(ticket) : g_trade.PositionModify(ticket,sl,tp);
    if(!sent || g_trade.ResultRetcode()!=TRADE_RETCODE_DONE)
    {
        PrintFormat("[RBE] Recovery protection failed #%I64u: %s",ticket,g_trade.ResultRetcodeDescription());
        return false;
    }
    return true;
}
void ManagePos()
{
    if(RBEAccountRestricted()) { g_recoveryProtected=false; return; }
    RBERecoverSessionCounts(TimeCurrent());
    RBEReconcileCloseIntents();
    g_recoveryProtected=g_closeEvidenceReady;
    // Register new fills
    for(int i = 0; i < PositionsTotal(); i++)
    {
        ulong t = PositionGetTicket(i);
        if(!PositionSelectByTicket(t)) continue;
        if(!RBEOwnedSelectedPosition()) continue;
        if(RBEPositionClosing((ulong)PositionGetInteger(POSITION_IDENTIFIER))){g_recoveryProtected=false;continue;}
        if(!RBERestoreMissingStop(t)) g_recoveryProtected=false;
        if(!PositionSelectByTicket(t)) continue;
        bool found = false;
        for(int j = 0; j < ArraySize(g_pos); j++) if(g_pos[j].ticket == t) { found = true; break; }
        if(found) continue;
        int n = ArraySize(g_pos); ArrayResize(g_pos, n + 1);
        g_pos[n].ticket = t;
        g_pos[n].isBuy  = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
        g_pos[n].beOk   = false;

        // Cost engine adoption
        double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double posLots = PositionGetDouble(POSITION_VOLUME);
        bool useCoveredStops = RBEUseCostCoveredStops();
        g_pos[n].costStage = useCoveredStops ? RBE_COST_BELOW : RBE_COST_COVERED;
        g_pos[n].costCoveredPrice = useCoveredStops ?
            RBECostCoveredPrice(entryPrice, posLots, g_pos[n].isBuy) : entryPrice;
        double existingSL=PositionGetDouble(POSITION_SL);
        if(existingSL>0 && (g_pos[n].isBuy ? existingSL>=g_pos[n].costCoveredPrice : existingSL<=g_pos[n].costCoveredPrice))
            g_pos[n].costStage=RBE_COST_COVERED;
        g_pos[n].trailAnchor = 0.0;
        g_pos[n].intendedEntry = entryPrice;
        g_pos[n].intendedSL = PositionGetDouble(POSITION_SL);
        g_pos[n].intendedTP = PositionGetDouble(POSITION_TP);
        g_pos[n].recentered = false;

    }

    for(int i = 0; i < ArraySize(g_pos); i++)
    {
        ulong t = g_pos[i].ticket;
        if(!PositionSelectByTicket(t)) continue;
        if(!RBEOwnedSelectedPosition()) { g_recoveryProtected=false; continue; }
        if(RBEPositionClosing((ulong)PositionGetInteger(POSITION_IDENTIFIER))){g_recoveryProtected=false;continue;}
        bool  buy  = g_pos[i].isBuy;
        double op  = PositionGetDouble(POSITION_PRICE_OPEN);
        double csl = PositionGetDouble(POSITION_SL);
        double ctp = PositionGetDouble(POSITION_TP);
        double mk  = buy ? SymbolInfoDouble(Symbol(), SYMBOL_BID)
                         : SymbolInfoDouble(Symbol(), SYMBOL_ASK);
        double pPts = buy ? (mk - op) / _Point : (op - mk) / _Point;
        // Trigger progress: points by default; % of open price when the mode is Percent (regime-robust across gold price levels).
        double pPct    = (op > 0.0) ? (buy ? (mk - op) : (op - mk)) / op * 100.0 : 0.0;
        double tslProg = pPct;

        // Cost engine state machine
        double covPrice = g_pos[i].costCoveredPrice;
        ENUM_RBE_COST_STAGE stage = g_pos[i].costStage;

        if(stage == RBE_COST_BELOW)
        {
            bool covered = buy ? (mk >= covPrice) : (mk <= covPrice);
            if(covered)
            {
                g_pos[i].costStage = RBE_COST_COVERED;
                g_pos[i].trailAnchor = mk;
            }
        }
        else if(stage == RBE_COST_COVERED)
        {
            bool betterPrice = buy ? (mk > g_pos[i].trailAnchor) : (mk < g_pos[i].trailAnchor);
            if(betterPrice) g_pos[i].trailAnchor = mk;
        }

        // Trail
        if((TSL_Trigger <= 0 || tslProg >= TSL_Trigger) &&
           g_pos[i].costStage >= RBE_COST_COVERED)
        {
            double d  = op * TSL_Value / 100.0;
            double ns = NormalizeDouble(buy ? mk - d : mk + d, _Digits);
            double st = TSL_Step * _Point;
            bool mv   = buy ? (ns > csl + st) : (csl == 0 || ns < csl - st);
            if(mv && (!g_trade.PositionModify(t,ns,ctp) || g_trade.ResultRetcode()!=TRADE_RETCODE_DONE))
                PrintFormat("[RBE] Trailing stop update failed #%I64u: %s",t,g_trade.ResultRetcodeDescription());
        }
    }
}

//+------------------------------------------------------------------+
//| Sizing & calc                                                    |
//+------------------------------------------------------------------+
double CalcLots(double entry, double sl)
{
    double lots = Lots;
    double tv   = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
    double ts   = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
    if(sl > 0)
    {
        double riskBudget = Risk_Money;
        double d = MathAbs(entry - sl);
        double stopCashPerLot = (d > 0 && ts > 0 && tv > 0) ? (d / ts * tv) : 0.0;
        double costCashPerLot = Include_Costs_In_Risk ? RBECostCashPerLot() : 0.0;
        double totalCashPerLot = stopCashPerLot + costCashPerLot;
        if(riskBudget > 0.0 && totalCashPerLot > 0.0)
            lots = riskBudget / totalCashPerLot;
    }
    double mn = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    double mx = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
    double st = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
    return NormalizeDouble(MathMax(mn, MathMin(mx, MathFloor(lots / st) * st)), 2);
}

double CalcStop(double entry, bool buy)
{
    if(Stop_Value <= 0) return 0.0;
    double d = (buy ? g_rngHi : g_rngLo) * Stop_Value / 100.0;
    return NormalizeDouble(buy ? entry - d : entry + d, _Digits);
}


#endif // RBE_EXECUTION_RUNTIME
