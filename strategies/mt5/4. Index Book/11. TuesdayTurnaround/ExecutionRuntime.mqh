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
#ifndef TT_EXECUTION_RUNTIME
#define TT_EXECUTION_RUNTIME

struct TTNewsEvent { datetime time; string currency,title; int importance; };
TTNewsEvent ttNews[];
datetime ttNewsLastAttempt=0;
string ttNewsProvider="disabled",ttNewsActive="";
bool ttHistoricalNewsLoaded=false,ttCancelBlackout=false;
bool ttNewsPreEvent=false;
datetime ttCancelGuardUntil=0;

bool TTTradeConnectionReady()
{
   if(MQLInfoInteger(MQL_TESTER))return true;
   return TerminalInfoInteger(TERMINAL_CONNECTED)
      && MQLInfoInteger(MQL_TRADE_ALLOWED)
      && TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)
      && AccountInfoInteger(ACCOUNT_TRADE_ALLOWED);
}

bool TTRecoveryBlocked=false,ttRecoveryPending=false;
ulong ttPositionId=0;
double ttOriginalStop=0;
long ttStateSequence=0;
datetime ttLastReconcile=0;
uint TTScopeHash(string value){uint hash=2166136261;for(int i=0;i<StringLen(value);i++)hash=(hash^(uint)StringGetCharacter(value,i))*16777619;return hash;}
string TTStateKey(string field)
{
   return "TT3."+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+"."+
      IntegerToString(TTScopeHash(AccountInfoString(ACCOUNT_SERVER)+"|"+_Symbol))+"."+IntegerToString((long)Magic)+"."+field;
}
double TTStateChecksum(const double &values[]){double sum=37;for(int i=0;i<ArraySize(values);i++)sum+=(i+1)*values[i];return sum;}
bool TTRecoveryMetadataMatches(ulong savedId,ulong liveId,double risk,double originalStop)
{return savedId!=0&&savedId==liveId&&risk>0&&originalStop>0;}
bool TTTradeAccepted(uint code){return code==TRADE_RETCODE_DONE||code==TRADE_RETCODE_DONE_PARTIAL||code==TRADE_RETCODE_PLACED;}
void TTStateSave()
{
   if(MQLInfoInteger(MQL_TESTER)||MQLInfoInteger(MQL_OPTIMIZATION)||TTRecoveryBlocked)return;
   double v[16];v[0]=3;v[1]=(double)(++ttStateSequence);v[2]=(double)ttMondayDay;v[3]=ttHeldSessions;
   v[4]=ttInitialRisk;v[5]=ttBreakEven?1:0;v[6]=ttEntry;v[7]=(double)ttEntryTime;v[8]=ttStop;
   v[9]=ttMondaySignalConsumed?1:0;v[10]=(double)(uint)(ttPositionId>>32);v[11]=(double)(uint)ttPositionId;
   v[12]=ttOriginalStop;v[13]=ttFlattenRequested?1:0;v[14]=(double)ttCancelGuardUntil;v[15]=(double)ttCurrentD1;
   string slot=IntegerToString(ttStateSequence%2)+".";
   bool ok=GlobalVariableSet(TTStateKey(slot+"commit"),0)>0;GlobalVariablesFlush();
   for(int i=0;i<ArraySize(v);i++)if(GlobalVariableSet(TTStateKey(slot+IntegerToString(i)),v[i])==0)ok=false;
   if(ok)ok=GlobalVariableSet(TTStateKey(slot+"sum"),TTStateChecksum(v))>0;
   GlobalVariablesFlush();
   if(ok)ok=GlobalVariableSet(TTStateKey(slot+"commit"),v[1])>0;
   GlobalVariablesFlush();
   if(!ok){TTRecoveryBlocked=true;ttStatus="Recovery storage failed; entries blocked";}
}
bool TTRestoreSlot(int slot,double &v[])
{
   string key=IntegerToString(slot)+".";ArrayResize(v,16);
   if(!GlobalVariableCheck(TTStateKey(key+"commit")))return false;
   double commit=GlobalVariableGet(TTStateKey(key+"commit"));if(commit<=0)return false;
   for(int i=0;i<16;i++){string field=TTStateKey(key+IntegerToString(i));if(!GlobalVariableCheck(field))return false;v[i]=GlobalVariableGet(field);if(!MathIsValidNumber(v[i]))return false;}
   return v[0]==3&&v[1]==commit&&GlobalVariableCheck(TTStateKey(key+"sum"))&&GlobalVariableGet(TTStateKey(key+"sum"))==TTStateChecksum(v);
}
void TTStateRestore()
{
   if(MQLInfoInteger(MQL_TESTER)||MQLInfoInteger(MQL_OPTIMIZATION))return;
   double a[],b[],v[];bool av=TTRestoreSlot(0,a),bv=TTRestoreSlot(1,b);if(!av&&!bv)return;
   if(av&&(!bv||a[1]>b[1]))ArrayCopy(v,a);else ArrayCopy(v,b);
   ttStateSequence=(long)v[1];ttMondayDay=(datetime)v[2];ttHeldSessions=(int)v[3];
   ttInitialRisk=v[4];ttBreakEven=v[5]>.5;ttEntry=v[6];ttEntryTime=(datetime)v[7];ttStop=v[8];ttMondaySignalConsumed=v[9]>.5;
   ttPositionId=((ulong)(uint)v[10]<<32)|(ulong)(uint)v[11];ttOriginalStop=v[12];ttFlattenRequested=v[13]>.5;
   ttCancelGuardUntil=(datetime)v[14];ttCancelBlackout=ttCancelGuardUntil>0;if(v[15]>0)ttCurrentD1=(datetime)v[15];
}

bool TTOwnPosition()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket>0 && PositionGetString(POSITION_SYMBOL)==_Symbol && (ulong)PositionGetInteger(POSITION_MAGIC)==Magic) return true;
   }
   return false;
}
ulong TTOwnPositionTicket()
{
   if(TTRecoveryBlocked)return 0;
   ulong selected=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket>0 && PositionGetString(POSITION_SYMBOL)==_Symbol && (ulong)PositionGetInteger(POSITION_MAGIC)==Magic)
      {if(selected!=0||PositionGetInteger(POSITION_TYPE)!=POSITION_TYPE_BUY)return 0;selected=ticket;}
   }
   return selected;
}
double TTMoneyPerPriceUnit()
{
   MqlTick q;if(!SymbolInfoTick(_Symbol,q)) return 0;
   double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE),cash=0;
   if(tick<=0 || !OrderCalcProfit(ORDER_TYPE_BUY,_Symbol,1.0,q.ask,q.ask+tick,cash)) return 0;
   return MathAbs(cash)/tick;
}
double TTNormalizeVolume(double lots)
{
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP),min=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),max=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   if(step<=0 || lots<min) return 0;
   return MathMin(max,MathFloor(lots/step+1e-9)*step);
}
double TTVolumeFor(double entry,double stop)
{
   if(Sizing==Fixed_Lots) return TTNormalizeVolume(FixedVolume);
   double loss=0;if(!OrderCalcProfit(ORDER_TYPE_BUY,_Symbol,1.0,entry,stop,loss)) return 0;
   double perLot=MathAbs(loss)+TTCost();
   return perLot>0 ? TTNormalizeVolume(RiskMoney/perLot) : 0;
}
void TTAudit(string event,string detail,double price)
{
   string line=StringFormat("TT_%s model=%d root=%s monday=%s price=%.*f detail=%s",event,(int)Model,TTRoot(),TimeToString(ttMondayDay,TIME_DATE),_Digits,price,detail);
   Print(line);
   if(ttAudit!=INVALID_HANDLE){FileWrite(ttAudit,TimeToString(TimeTradeServer(),TIME_DATE|TIME_SECONDS),event,(int)Model,TTRoot(),TimeToString(ttMondayDay,TIME_DATE),price,detail);FileFlush(ttAudit);}
}
void TTInitAudit()
{
   if(!WriteAuditLog) return;
   string path="TuesdayTurnaround_audit_"+_Symbol+"_"+IntegerToString((long)Magic)+".csv";
   ttAudit=FileOpen(path,FILE_COMMON|FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(ttAudit==INVALID_HANDLE) return;
   if(FileSize(ttAudit)==0) FileWrite(ttAudit,"server_time","event","model","root","monday","price","detail");
   FileSeek(ttAudit,0,SEEK_END);
}
void TTResetTrade(){ttEntry=0;ttEntryTime=0;ttInitialRisk=0;ttPositionId=0;ttOriginalStop=0;ttBreakEven=false;ttFlattenRequested=false;ttStatus="Flat";TTStateSave();}
void TTCancelOwnedOrders(string reason)
{
   if(!TTTradeConnectionReady())return;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i);
      if(ticket>0 && OrderGetString(ORDER_SYMBOL)==_Symbol && (ulong)OrderGetInteger(ORDER_MAGIC)==Magic)
         if(!trade.OrderDelete(ticket)) PrintFormat("TT_CANCEL_FAILED ticket=%I64u code=%u",ticket,trade.ResultRetcode());
   }
   TTAudit("CANCEL_OWNED",reason,0);
}
bool TTCloseOwned(string reason)
{
   if(!TTTradeConnectionReady())return false;
   ulong ticket=TTOwnPositionTicket();if(ticket==0) return true;
   ttFlattenRequested=true;TTStateSave();
   bool ok=trade.PositionClose(ticket)&&TTTradeAccepted(trade.ResultRetcode());
   TTAudit(ok?"EXIT_SENT":"EXIT_FAILED",reason,ok?trade.ResultPrice():0);
   return ok;
}
bool TTModifyOwnedStop(double stop)
{
   if(!TTTradeConnectionReady())return false;
   ulong ticket=TTOwnPositionTicket();if(ticket==0 || !PositionSelectByTicket(ticket)) return false;
   double current=PositionGetDouble(POSITION_SL);
   if(stop<=current || stop>=SymbolInfoDouble(_Symbol,SYMBOL_BID)) return false;
   bool ok=trade.PositionModify(ticket,stop,PositionGetDouble(POSITION_TP))&&trade.ResultRetcode()==TRADE_RETCODE_DONE;
   if(ok){ttStop=stop;TTStateSave();}return ok;
}
bool TTOpenLong()
{
   if(!TTTradeConnectionReady())return false;
   if(!ttArmed || ttMondaySignalConsumed || TTRecoveryBlocked || ttRecoveryPending || TTOwnPosition()) return false;
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING&&PositionSelect(_Symbol))
   {ttRecoveryPending=true;ttStatus="Waiting for foreign netting position to clear";return false;}
   MqlTick q;if(!SymbolInfoTick(_Symbol,q) || q.ask<=ttStop){ttArmed=false;ttStatus="Skipped: open through stop";TTAudit("ENTRY_SKIP","OPEN_THROUGH_STOP",q.ask);return false;}
   double volume=TTVolumeFor(q.ask,ttStop);
   if(volume<=0){ttArmed=false;ttStatus="Skipped: risk below minimum volume";TTAudit("ENTRY_SKIP","RISK_BELOW_MINIMUM",q.ask);return false;}
   ttMondaySignalConsumed=true;ttArmed=false;ttOriginalStop=ttStop;TTStateSave();
   if(TTRecoveryBlocked)return false;
   bool ok=trade.Buy(volume,_Symbol,0,ttStop,0,"TT_"+EnumToString(Model))&&TTTradeAccepted(trade.ResultRetcode());
   ttArmed=false;ttStatus=ok?"Entry submitted":"Entry rejected";
   TTAudit(ok?"ENTRY_SENT":"ENTRY_FAILED",StringFormat("volume=%.2f retcode=%u",volume,trade.ResultRetcode()),q.ask);
   return ok;
}
void TTRecoverOwned()
{
   TTReconcileOwned(true);
}
bool TTClosedPositionHistory(ulong id)
{
   if(!HistorySelectByPosition(id))return false;
   double entered=0,exited=0;
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0 || (ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID)!=id || HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol)return false;
      long kind=HistoryDealGetInteger(deal,DEAL_ENTRY);
      if(kind==DEAL_ENTRY_INOUT)return false;
      if(kind==DEAL_ENTRY_IN)
      {
         if((ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=Magic)return false;
         entered+=HistoryDealGetDouble(deal,DEAL_VOLUME);
      }
      else if(kind==DEAL_ENTRY_OUT || kind==DEAL_ENTRY_OUT_BY)exited+=HistoryDealGetDouble(deal,DEAL_VOLUME);
   }
   return entered>0 && MathAbs(entered-exited)<1e-8;
}
void TTReconcileOwned(bool initializing=false)
{
   if(!TTTradeConnectionReady()||TTRecoveryBlocked)return;
   ttRecoveryPending=false;
   ulong ticket=TTOwnPositionTicket();
   if(ticket==0)
   {
      if(TTOwnPosition()){TTRecoveryBlocked=true;ttStatus="Ambiguous owned position; management blocked";return;}
      if(ttPositionId!=0)
      {
         if(!TTClosedPositionHistory(ttPositionId)){ttRecoveryPending=true;ttStatus="Waiting for complete owned exit history";return;}
         TTResetTrade();
      }
      return;
   }
   if(!PositionSelectByTicket(ticket))return;
   ulong id=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
   if(ttPositionId!=0 && ttPositionId!=id && !TTClosedPositionHistory(ttPositionId))
   {ttRecoveryPending=true;ttStatus="Waiting for prior owned exit history";return;}
   if(!HistorySelectByPosition(id)){ttRecoveryPending=true;ttStatus="Waiting for owned position history";return;}
   bool own=true;datetime firstEntry=0;ulong firstOrder=0;
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong deal=HistoryDealGetTicket(i);long type=HistoryDealGetInteger(deal,DEAL_TYPE);
      if(type!=DEAL_TYPE_BUY&&type!=DEAL_TYPE_SELL)continue;
      if(HistoryDealGetInteger(deal,DEAL_ENTRY)==DEAL_ENTRY_IN)
      {if((ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=Magic)own=false;datetime t=(datetime)HistoryDealGetInteger(deal,DEAL_TIME);if(firstEntry==0||t<firstEntry){firstEntry=t;firstOrder=(ulong)HistoryDealGetInteger(deal,DEAL_ORDER);}}
      else if(HistoryDealGetInteger(deal,DEAL_ENTRY)==DEAL_ENTRY_INOUT)own=false;
   }
   if(!own){TTRecoveryBlocked=true;ttStatus="Mixed ownership; broker stop retained";return;}
   if(firstEntry==0||!SeriesInfoInteger(_Symbol,PERIOD_D1,SERIES_SYNCHRONIZED))
   {ttRecoveryPending=true;ttStatus="Waiting for owned entry/daily history";return;}
   if(!PositionSelectByTicket(ticket))return;
   double brokerStop=PositionGetDouble(POSITION_SL),entry=PositionGetDouble(POSITION_PRICE_OPEN);
   bool matching=TTRecoveryMetadataMatches(ttPositionId,id,ttInitialRisk,ttOriginalStop);
   bool recoveredMetadata=!matching;
   // A consumed, durable entry intent can be bound to its fill after an abrupt restart.
   if(!matching&&ttPositionId==0&&ttMondaySignalConsumed&&ttOriginalStop>0&&ttEntryTime==0)
   {ttInitialRisk=entry-ttOriginalStop;matching=ttInitialRisk>0;}
   // Migrate a pre-journal position only from its verified opening order, never from a moved SL.
   if(!matching&&firstOrder!=0)
   {
      double original=HistoryOrderGetDouble(firstOrder,ORDER_SL);
      int entryShift=iBarShift(_Symbol,PERIOD_D1,firstEntry,false);
      if(original>0&&original<entry&&entryShift>=0)
      {
         ttOriginalStop=original;ttInitialRisk=entry-original;ttHeldSessions=0;
         ttCurrentD1=iTime(_Symbol,PERIOD_D1,entryShift);ttMondayDay=iTime(_Symbol,PERIOD_D1,entryShift+1);
         ttMondaySignalConsumed=true;ttBreakEven=false;ttFlattenRequested=false;ttCancelGuardUntil=0;ttCancelBlackout=false;matching=true;
      }
   }
   if(!matching||brokerStop<=0){ttRecoveryPending=true;ttStatus="Waiting for recovery metadata/stop; position retained";return;}
   bool changed=recoveredMetadata||ttPositionId!=id||ttEntry!=entry||ttEntryTime!=firstEntry||ttStop!=brokerStop||(!ttBreakEven&&brokerStop>=entry);
   ttPositionId=id;ttEntry=entry;ttEntryTime=firstEntry;ttStop=brokerStop;ttArmed=false;
   if(brokerStop>=entry)ttBreakEven=true;
   if(changed||initializing)TTStateSave();if(initializing)ttStatus="Recovered owned position; broker stop retained";
}

int TTImpactFromText(string impact)
{
   string x=impact;StringToUpper(x);
   if(x=="HIGH"||x=="RED")return CALENDAR_IMPORTANCE_HIGH;
   if(x=="MODERATE"||x=="MEDIUM"||x=="YELLOW")return CALENDAR_IMPORTANCE_MODERATE;
   if(x=="LOW")return CALENDAR_IMPORTANCE_LOW;
   return CALENDAR_IMPORTANCE_NONE;
}
int TTAdjustedImportance(string eventName,int importance)
{
   string n=eventName;StringToUpper(n);
   if(StringFind(n,"NEW HOME SALES")>=0||StringFind(n,"EXISTING HOME SALES")>=0||
      StringFind(n,"PENDING HOME SALES")>=0||StringFind(n,"CRUDE OIL")>=0||
      (StringFind(n,"EIA")>=0&&StringFind(n,"STOCK")>=0)||StringFind(n,"OIL STOCK")>=0)
      return CALENDAR_IMPORTANCE_MODERATE;
   return importance;
}
bool TTImpactAllowedFor(int mode,int importance)
{
   if(mode==News_Off)return false;
   if(mode==News_All)return true;
   if(importance==CALENDAR_IMPORTANCE_HIGH)return true;
   return mode==News_Red_Yellow&&importance==CALENDAR_IMPORTANCE_MODERATE;
}
bool TTImpactAllowed(int importance){return TTImpactAllowedFor((int)NewsImpact,importance);}
void TTNewsPresetSeconds(int preset,double customBefore,double customAfter,int &before,int &after)
{
   if(preset==News_Custom){before=(int)MathRound(customBefore*60.0);after=(int)MathRound(customAfter*60.0);return;}
   before=preset*30;after=before;
}
void TTNewsWindowSeconds(int &before,int &after){TTNewsPresetSeconds((int)NewsWindow,CustomNewsMinutesBefore,CustomNewsMinutesAfter,before,after);}
bool TTNewsSelfTest()
{
   if(!TTImpactAllowedFor(News_Red_Only,CALENDAR_IMPORTANCE_HIGH)||TTImpactAllowedFor(News_Red_Only,CALENDAR_IMPORTANCE_MODERATE))return false;
   if(!TTImpactAllowedFor(News_Red_Yellow,CALENDAR_IMPORTANCE_MODERATE)||!TTImpactAllowedFor(News_All,CALENDAR_IMPORTANCE_LOW))return false;
   if(TTAdjustedImportance("New Home Sales",CALENDAR_IMPORTANCE_HIGH)!=CALENDAR_IMPORTANCE_MODERATE)return false;
   int b=0,a=0;TTNewsPresetSeconds(5,0,0,b,a);if(b!=150||a!=150)return false;
   TTNewsPresetSeconds(10,0,0,b,a);if(b!=300||a!=300)return false;
   TTNewsPresetSeconds(14,0,0,b,a);if(b!=420||a!=420)return false;
   TTNewsPresetSeconds(20,0,0,b,a);return b==600&&a==600;
}
bool TTLoadHistoricalNewsCsv(string path)
{
   ArrayResize(ttNews,0);int f=FileOpen(path,FILE_COMMON|FILE_READ|FILE_CSV|FILE_ANSI,',');if(f==INVALID_HANDLE)return false;
   while(!FileIsEnding(f))
   {
      string stamp=FileReadString(f),currency=FileReadString(f),impact=FileReadString(f),title=FileReadString(f);
      datetime utc=StringToTime(stamp);int importance=TTAdjustedImportance(title,TTImpactFromText(impact));if(utc<=0||!TTImpactAllowed(importance))continue;
      int n=ArraySize(ttNews);ArrayResize(ttNews,n+1);ttNews[n].time=utc;ttNews[n].currency=currency;ttNews[n].importance=importance;ttNews[n].title=title;
   }
   FileClose(f);return ArraySize(ttNews)>0;
}
void TTNewsInit()
{
   if(!EnableNewsFilter||NewsImpact==News_Off){ttNewsProvider="disabled";return;}
   if(MQLInfoInteger(MQL_TESTER))
   {
      ttHistoricalNewsLoaded=HistoricalNewsCsv!=""&&TTLoadHistoricalNewsCsv(HistoricalNewsCsv);
      ttNewsProvider=ttHistoricalNewsLoaded?"Historical CSV":"missing historical CSV; fail closed";return;
   }
   ttNewsProvider="MT5 calendar loading; fail closed";
   TTNewsRefresh(TimeTradeServer());
}
bool TTCurrencyAllowed(string currency);
void TTNewsRefresh(datetime now)
{
   if(!EnableNewsFilter||NewsImpact==News_Off||MQLInfoInteger(MQL_TESTER)||(ttNewsLastAttempt>0&&now-ttNewsLastAttempt<60))return;
   ttNewsLastAttempt=now;int before=0,after=0;TTNewsWindowSeconds(before,after);
   datetime day=now-(now%86400);MqlCalendarValue values[];ResetLastError();int count=CalendarValueHistory(values,day-before-3600,day+86400+after+3600,NULL,NULL);
   if(count<0){ArrayResize(ttNews,0);ttNewsProvider="MT5 calendar unavailable; fail closed";PrintFormat("TT_NEWS_CALENDAR_FAILED error=%d",GetLastError());return;}
   ArrayResize(ttNews,0);
   for(int i=0;i<count;i++)
   {
      MqlCalendarEvent event;if(!CalendarEventById(values[i].event_id,event))continue;
      int importance=TTAdjustedImportance(event.name,(int)event.importance);if(!TTImpactAllowed(importance))continue;
      MqlCalendarCountry country;if(!CalendarCountryById(event.country_id,country)||!TTCurrencyAllowed(country.currency))continue;
      int n=ArraySize(ttNews);ArrayResize(ttNews,n+1);ttNews[n].time=values[i].time;ttNews[n].currency=country.currency;ttNews[n].importance=importance;ttNews[n].title=event.name;
   }
   ttNewsProvider="MT5 calendar";
}
bool TTCurrencyAllowed(string currency)
{
   string list=","+NewsCurrencies+",",c=currency;StringToUpper(list);StringToUpper(c);
   return StringFind(list,","+c+",")>=0;
}
bool TTNewsBlackout(datetime server)
{
   ttNewsActive="";ttNewsPreEvent=false;if(!EnableNewsFilter||NewsImpact==News_Off)return false;
   if(MQLInfoInteger(MQL_TESTER) && !ttHistoricalNewsLoaded)return true;
   if(!MQLInfoInteger(MQL_TESTER)&&ttNewsProvider!="MT5 calendar")return true;
   datetime compare=server;if(MQLInfoInteger(MQL_TESTER)){compare=TTClockUTC(server);if(compare<=0)return true;}
   int before=0,after=0;TTNewsWindowSeconds(before,after);
   for(int i=0;i<ArraySize(ttNews);i++)
      if(TTCurrencyAllowed(ttNews[i].currency)&&compare>=ttNews[i].time-before&&compare<=ttNews[i].time+after)
      {ttNewsActive=ttNews[i].currency+" "+ttNews[i].title;ttNewsPreEvent=compare<=ttNews[i].time;return true;}
   return false;
}
string TTNewsSummary(){return ttNewsBlocked?(ttNewsActive==""?"SOURCE_UNAVAILABLE":ttNewsActive):ttNewsProvider;}
void TTNewsShutdown(){}
#endif
