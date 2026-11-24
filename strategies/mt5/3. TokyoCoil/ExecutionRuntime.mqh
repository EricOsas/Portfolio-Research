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
#ifndef TC_EXECUTION_RUNTIME
#define TC_EXECUTION_RUNTIME
bool TcHistoryRisk(ulong id,double &entry,double &stop,int &direction,double &exit_price,datetime &exit_time)
{
   if(!HistorySelectByPosition(id)) return false;
   double in_volume=0,out_volume=0; entry=0;stop=0;exit_price=0;exit_time=0;direction=0;
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong deal=HistoryDealGetTicket(i);
      long type=HistoryDealGetInteger(deal,DEAL_ENTRY);
      double v=HistoryDealGetDouble(deal,DEAL_VOLUME);
      if(type==DEAL_ENTRY_IN)
      {
         entry+=HistoryDealGetDouble(deal,DEAL_PRICE)*v;in_volume+=v;
         direction=HistoryDealGetInteger(deal,DEAL_TYPE)==DEAL_TYPE_BUY?1:-1;
         ulong order=(ulong)HistoryDealGetInteger(deal,DEAL_ORDER);
         double initial=HistoryDealGetDouble(deal,DEAL_SL);
         if(initial<=0 && HistoryOrderSelect(order)) initial=HistoryOrderGetDouble(order,ORDER_SL);
         if(initial<=0) return false;
         if(stop>0 && MathAbs(stop-initial)>_Point) return false;
         stop=initial;
      }
      else if(type==DEAL_ENTRY_OUT || type==DEAL_ENTRY_OUT_BY)
      {
         exit_price+=HistoryDealGetDouble(deal,DEAL_PRICE)*v;out_volume+=v;
         exit_time=(datetime)HistoryDealGetInteger(deal,DEAL_TIME);
      }
      else if(type==DEAL_ENTRY_INOUT) return false;
   }
   if(in_volume<=0 || stop<=0) return false;
   entry/=in_volume;
   if(MathAbs(entry-stop)<_Point*.5) return false;
   if(out_volume>0) exit_price/=out_volume;
   if(out_volume<in_volume-1e-8) exit_time=0; // Open / partially closed positions are not closed trades.
   return true;
}

bool TcRestoreBrakeHistory(Sleeve &s)
{
   if(!HistorySelect(0,TimeCurrent())) {PrintFormat("TC_INIT_FAIL brake history download error=%d",GetLastError());return false;}
   ulong ids[];
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong deal=HistoryDealGetTicket(i);
      if(HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol || HistoryDealGetInteger(deal,DEAL_MAGIC)!=s.magic ||
         HistoryDealGetInteger(deal,DEAL_ENTRY)!=DEAL_ENTRY_IN) continue;
      ulong id=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
      bool exists=false;
      for(int k=0;k<ArraySize(ids);k++) if(ids[k]==id) {exists=true;break;}
      if(!exists) {int n=ArraySize(ids);ArrayResize(ids,n+1);ids[n]=id;}
   }
   ArrayResize(s.closedR,0);ArrayResize(s.closedExit,0);
   // Only the most recent lookback plus the possible current position is needed.
   int first=MathMax(0,ArraySize(ids)-BrakeN-1);
   for(int i=first;i<ArraySize(ids);i++)
   {
      double entry,stop,exit_price;int direction;datetime exit_time;
      if(!TcHistoryRisk(ids[i],entry,stop,direction,exit_price,exit_time))
      {PrintFormat("TC_BRAKE_HISTORY_FAIL position=%I64u: original risk cannot be reconstructed",ids[i]);return false;}
      if(exit_time==0) continue;
      int n=ArraySize(s.closedR);ArrayResize(s.closedR,n+1);ArrayResize(s.closedExit,n+1);
      s.closedR[n]=direction*(exit_price-entry)/MathAbs(entry-stop);s.closedExit[n]=exit_time;
   }
   // Close order can differ from entry order; sort before taking the last N.
   for(int i=1;i<ArraySize(s.closedR);i++)
      for(int k=i;k>0 && s.closedExit[k]<s.closedExit[k-1];k--)
      {
         datetime t=s.closedExit[k];s.closedExit[k]=s.closedExit[k-1];s.closedExit[k-1]=t;
         double r=s.closedR[k];s.closedR[k]=s.closedR[k-1];s.closedR[k-1]=r;
      }
   PrintFormat("TC_BRAKE_RESTORED closed=%d threshold=%.2fR",ArraySize(s.closedR),BrakeFloorR);
   return true;
}

double BrakeRF(Sleeve &s)
{
   double balance=AccountInfoDouble(ACCOUNT_BALANCE);
   double rf = RiskMoney>0 && balance>0 ? RiskMoney/balance : RiskPct/100.0;
   return TcBrakeFraction(rf,UseBrake,BrakeN,BrakeFloorR,s.closedR);

}
double LotsFor(double rf, double entry, double stop)
{
   double risk = AccountInfoDouble(ACCOUNT_BALANCE) * rf;
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double per_lot = MathAbs(entry - stop) / ts * tv;
   if(per_lot <= 0) return 0;
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lots = MathFloor(risk / per_lot / step) * step;
   if(lots < vmin) return 0;
   return MathMin(lots, vmax);
}
// ---------------- trade log --------------------------------------------------------------------------
int logh = INVALID_HANDLE;
void LogTrade(Sleeve &s, datetime exit_srv, double exit_px, string why, double profit, double comm, double swap, double R)
{
   if(logh==INVALID_HANDLE) return;
   if(logh == INVALID_HANDLE) return;
   FileWrite(logh, s.name, TimeToString(s.entry_srv, TIME_DATE | TIME_SECONDS), TimeToString(exit_srv, TIME_DATE | TIME_SECONDS),
             s.dir == 1 ? "long" : "short", DoubleToString(s.entry, _Digits), DoubleToString(s.stop, _Digits),
             DoubleToString(exit_px, _Digits), why, DoubleToString(s.lots, 2), DoubleToString(s.rf, 4),
             DoubleToString(profit, 2), DoubleToString(comm, 2), DoubleToString(swap, 2), DoubleToString(R, 4),
             DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));
}
bool PositionOf(long magic, ulong &ticket)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == magic)
      { ticket = t; return true; }
   }
   return false;
}
void DeletePendings(long magic)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong t = OrderGetTicket(i);
      long type=t>0?OrderGetInteger(ORDER_TYPE):-1;
      if(t > 0 && (type==ORDER_TYPE_BUY_STOP || type==ORDER_TYPE_SELL_STOP) &&
         OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == magic) trade.OrderDelete(t);
   }
}
// when a sleeve's tracked position is gone: read its closing deal(s), log, store R
void Reconcile(Sleeve &s, string why_if_ours)
{
   if(!MQLInfoInteger(MQL_TESTER) && !tcRecoveryReady)return;
   if(s.pos_id == 0) return;
   ulong t;
   if(PositionOf(s.magic, t)) return;
   if(!HistorySelectByPosition(s.pos_id)) return;
   double profit = 0, comm = 0, swap = 0, exit_px = 0, vol = 0, entered = 0; datetime exit_t = 0; string why = why_if_ours;
   for(int i = 0; i < HistoryDealsTotal(); i++)
   {
      ulong d = HistoryDealGetTicket(i);
      if(d==0 || (ulong)HistoryDealGetInteger(d,DEAL_POSITION_ID)!=s.pos_id || HistoryDealGetString(d,DEAL_SYMBOL)!=_Symbol)return;
      long entry_kind=HistoryDealGetInteger(d,DEAL_ENTRY);
      if(entry_kind==DEAL_ENTRY_INOUT)return;
      if(entry_kind==DEAL_ENTRY_IN)
      {
         if((ulong)HistoryDealGetInteger(d,DEAL_MAGIC)!=s.magic)return;
         entered+=HistoryDealGetDouble(d,DEAL_VOLUME);
      }
      profit += HistoryDealGetDouble(d, DEAL_PROFIT);
      comm   += HistoryDealGetDouble(d, DEAL_COMMISSION);
      swap   += HistoryDealGetDouble(d, DEAL_SWAP);
      if(entry_kind == DEAL_ENTRY_OUT || entry_kind == DEAL_ENTRY_OUT_BY)
      {
         double v = HistoryDealGetDouble(d, DEAL_VOLUME);
         exit_px += HistoryDealGetDouble(d, DEAL_PRICE) * v; vol += v;
         exit_t = (datetime)HistoryDealGetInteger(d, DEAL_TIME);
         if(HistoryDealGetInteger(d, DEAL_REASON) == DEAL_REASON_SL) why = "stop";
      }
   }
   // Position disappearance can precede deal-history hydration. Retain ownership
   // until the exact position's complete entry/exit volume is available.
   if(entered<=0 || MathAbs(vol-entered)>1e-8 || exit_t<=0 || exit_px<=0 || MathAbs(s.entry-s.stop)<_Point*.5)return;
   exit_px /= vol;
   double R = s.dir * (exit_px - s.entry) / MathAbs(s.entry - s.stop);
   int n = ArraySize(s.closedR);
   ArrayResize(s.closedR, n + 1); ArrayResize(s.closedExit, n + 1);
   s.closedR[n] = R; s.closedExit[n] = exit_t;
   LogTrade(s, exit_t, exit_px, why, profit, comm, swap, R);
   s.pos_id = 0;
   s.close_order=0;s.close_volume=0;
}
bool TcCloseSettled(long state,double before,double current,double filled,double step)
{
   bool terminal=state==ORDER_STATE_FILLED || state==ORDER_STATE_CANCELED || state==ORDER_STATE_REJECTED || state==ORDER_STATE_EXPIRED;
   return terminal && current<=before-filled+step*.5;
}
void CloseSleeve(Sleeve &s, string why)
{
   ulong t;
   if(PositionOf(s.magic, t))
   {
      double volume=PositionGetDouble(POSITION_VOLUME);
      if(s.close_order>0)
      {
         if(OrderSelect(s.close_order))return;
         if(!HistoryOrderSelect(s.close_order))return;
         long state=HistoryOrderGetInteger(s.close_order,ORDER_STATE);
         double filled=HistoryOrderGetDouble(s.close_order,ORDER_VOLUME_INITIAL)-HistoryOrderGetDouble(s.close_order,ORDER_VOLUME_CURRENT);
         if(!TcCloseSettled(state,s.close_volume,volume,filled,SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP)))return;
         s.close_order=0;
      }
      trade.SetExpertMagicNumber(s.magic);
      bool sent=trade.PositionClose(t, DeviationPts);
      uint code=trade.ResultRetcode();
      if(sent && (code==TRADE_RETCODE_DONE || code==TRADE_RETCODE_DONE_PARTIAL || code==TRADE_RETCODE_PLACED))
      {
         s.close_order=trade.ResultOrder();s.close_volume=volume;
         if(!MQLInfoInteger(MQL_TESTER))PrintFormat("TC_CLOSE_REQUEST position=%I64u reason=%s order=%I64u NY=%s",t,why,s.close_order,TimeToString(NYNow(),TIME_DATE|TIME_SECONDS));
      }
      else PrintFormat("TC_CLOSE_RETRY position=%I64u reason=%s retcode=%u detail=%s",t,why,code,trade.ResultRetcodeDescription());
   }
   Reconcile(s, why);
}
// adopt a freshly filled position (pending order filled or market order)

void Adopt(Sleeve &s, datetime session)
{
   ulong t;
   if(s.pos_id != 0 || !PositionOf(s.magic, t)) return;
   s.close_order=0;s.close_volume=0;
   s.pos_id = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
   s.dir = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1;
   s.entry = PositionGetDouble(POSITION_PRICE_OPEN);
   s.stop = PositionGetDouble(POSITION_SL);
   s.entry_srv = (datetime)PositionGetInteger(POSITION_TIME);
   s.lots = PositionGetDouble(POSITION_VOLUME);
   // print flatten: the trade day's first USD release before noon, if it comes after the entry
   datetime tday = SessionOf(NewYorkFromServer(s.entry_srv)) + 86400;
   datetime ev = UseNewsFlatten ? EventOn(tday) : 0;
   datetime entry_ny = NewYorkFromServer(s.entry_srv);
   s.flat_srv = 0;
   if(ev > 0 && MinOfDay(ev) < 12 * 60 && ev > entry_ny - (entry_ny % 300))   // release slot after the entry slot (as Python)
      s.flat_srv = ServerFromNewYork(ev - NewsExitLeadMinutes * 60);
}
void TcReportEntry(bool accepted,string side)
{
   if(MQLInfoInteger(MQL_TESTER))return;
   PrintFormat("TC_ENTRY_%s side=%s order=%I64u retcode=%u detail=%s NY=%s",accepted?"REQUEST":"FAILED",side,
               trade.ResultOrder(),trade.ResultRetcode(),trade.ResultRetcodeDescription(),TimeToString(NYNow(),TIME_DATE|TIME_SECONDS));
}
void TcArmC1(double high,double low,double spread)
{
   if(!EnableC1 || S1.pos_id!=0 || !tcRecoveryReady) return;
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID),ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   double relative=RelWidth(high-low);
   if(relative<=0 || relative>=1)
   {if(!MQLInfoInteger(MQL_TESTER))PrintFormat("TC_ENTRY_SKIP coil filter relative=%.6f high=%.5f low=%.5f",relative,high,low);return;}
   double buy_px  = NormalizeDouble(EntryAtRawBoxEdges ? high : high + spread + pt, _Digits);   // ask level = bid above the high
   double sell_px = NormalizeDouble(EntryAtRawBoxEdges ? low : low - pt, _Digits);            // bid below the low
   double rf = BrakeRF(S1); S1.rf = rf;
   trade.SetExpertMagicNumber(MagicC1);
   double lb = LotsFor(rf, buy_px, low), ls = LotsFor(rf, sell_px, high);
   if(!MQLInfoInteger(MQL_TESTER) && (lb<=0 || ls<=0))PrintFormat("TC_ENTRY_SIZE buy=%.4f sell=%.4f riskFraction=%.6f",lb,ls,rf);
   bool long_out = EntryAtRawBoxEdges ? ask >= high : bid > high;
    bool short_out = EntryAtRawBoxEdges ? bid <= low : bid < low;
    if(long_out || short_out)
   {
      // already outside at 23:00: Python enters at the 23:00 bar's open (max(level, open))
      if(long_out && lb > 0) TcReportEntry(trade.Buy(lb, _Symbol, 0, low, 0, "C1"),"BUY market");
      else if(short_out && ls > 0) TcReportEntry(trade.Sell(ls, _Symbol, 0, high, 0, "C1"),"SELL market");
   }
   else
   {
      if((SymbolInfoInteger(_Symbol,SYMBOL_EXPIRATION_MODE)&SYMBOL_EXPIRATION_SPECIFIED)==0)
      {Print("TC_ENTRY_BLOCKED broker does not support exact pending expiry");return;}
      datetime expiry=ServerFromNewYork(SessionOf(NYNow())+86400+3*3600);
      if(lb > 0) TcReportEntry(trade.BuyStop(lb, buy_px, _Symbol, low, 0, ORDER_TIME_SPECIFIED, expiry, "C1"),"BUY stop");
      if(ls > 0) TcReportEntry(trade.SellStop(ls, sell_px, _Symbol, high, 0, ORDER_TIME_SPECIFIED, expiry, "C1"),"SELL stop");
   }
}

#endif // TC_EXECUTION_RUNTIME
