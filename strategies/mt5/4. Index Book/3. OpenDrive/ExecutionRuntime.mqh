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
//   SHARED-LIVE live only: a fresh, fully recorded LIVE/LIVE-REF proof from another instance on this server,
//             accepted only when its predicted current offset agrees with the observed live offset.
//   LIVE-REF  live only: another already-open/selected series proves the rule, with the base measured live.
//             No reference symbol is added to Market Watch; provisional results are never shared as proof.
#define CLK_ADAPTER_VERSION "1.12"

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
int      clkEvCloses=0;                         // completed-week observations recorded with a shared live proof
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
   clkEvWeeks=0; clkEvCloses=0; clkEvHits=0; clkEvMargin=0; clkFoldFirstCount=0; clkGapCount=0; clkSegN=0;
   ArrayResize(clkEvidenceRefs,0); clkEvidenceRefsBuilt=false; clkRefPos=0;
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
// References come only from open charts, never from the terminal's selected-symbol catalogue.
// SYMBOL_SELECT alone includes invisible conversion pairs; it is not evidence that the user loaded a symbol.
bool ClkIsOpenChart(string sym)
{
   for(long chart=ChartFirst();chart>=0;chart=ChartNext(chart))
      if(ChartSymbol(chart)==sym) return true;
   return false;
}
bool ClkIsLoadedRef(string sym)
{
   if(sym=="" || !ClkIsOpenChart(sym) || SymbolInfoInteger(sym,SYMBOL_SELECT)==0 ||
      SymbolInfoDouble(sym,SYMBOL_TRADE_CONTRACT_SIZE)<=0.0) return false;
   string path=SymbolInfoString(sym,SYMBOL_PATH); StringToLower(path);
   return path!="" && StringFind(path,"crypto")<0;
}
void ClkAddEvidenceRef(string sym,string &refs[])
{
   if(sym==_Symbol || ArraySize(refs)>=6 || !ClkIsLoadedRef(sym)) return;
   for(int i=0;i<ArraySize(refs);i++) if(refs[i]==sym) return;
   int n=ArraySize(refs); ArrayResize(refs,n+1); refs[n]=sym;
}
void ClkBuildEvidenceRefs(string &out[])
{
   ArrayResize(out,0);
   for(long chart=ChartFirst();chart>=0 && ArraySize(out)<6;chart=ChartNext(chart))
      ClkAddEvidenceRef(ChartSymbol(chart),out);
}
string clkEvidenceRefs[];
bool clkEvidenceRefsBuilt=false;
string ClkEvidenceSymbolAt(int attempt)
{
   if(attempt==0) return _Symbol;
   if(!clkEvidenceRefsBuilt) { ClkBuildEvidenceRefs(clkEvidenceRefs); clkEvidenceRefsBuilt=true; }
   int i=attempt-1;
   if(i<0 || i>=ArraySize(clkEvidenceRefs)) return "";
   string sym=clkEvidenceRefs[i];
   return ClkIsLoadedRef(sym) ? sym : "";                    // respect a symbol the user hid after the snapshot
}
int ClkEvidenceFor(string sym,int &rule,int &modeOpen,int &modeClose,datetime &opensOut[],datetime &closesOut[])
{
   datetime bars[];
   datetime opens[];
   datetime closes[];
   clkEvWeeks=0; clkEvCloses=0; clkEvHits=0; clkEvMargin=0; rule=-1; modeOpen=0; modeClose=0;
   ArrayResize(opensOut,0); ArrayResize(closesOut,0);
   // The user owns these selections. Never borrow, stamp or re-select a reference behind their back.
   if(sym!=_Symbol && (!ClkIsOpenChart(sym) || SymbolInfoInteger(sym,SYMBOL_SELECT)==0)) return -1;
   datetime touch[];
   CopyTime(sym,PERIOD_M15,0,1,touch);                       // queues the sync; the copy below may still be short
   int got=CopyTime(sym,PERIOD_M15,0,CLK_BARS_LOOKBACK,bars);
   if(got<4000) return -1;                                   // still downloading: try again on the next pass
   clkEvWeeks=ClkWeekOpens(bars,got,opens);
   int nClose=ClkWeekCloses(bars,got,closes);
   clkEvCloses=nClose;
   ArrayCopy(opensOut,opens);
   ArrayCopy(closesOut,closes);
   return ClkInferRule(opens,clkEvWeeks,closes,nClose,rule,clkEvHits,clkEvMargin,modeOpen,modeClose);
}
int ClkEvidence(int &rule,int &modeOpen,int &modeClose,datetime &opensOut[],datetime &closesOut[])
{
   return ClkEvidenceFor(ClkEvidenceSymbolName(),rule,modeOpen,modeClose,opensOut,closesOut);
}
int ClkEvidence(int &rule,int &modeOpen,int &modeClose) { datetime eo[],ec[]; return ClkEvidence(rule,modeOpen,modeClose,eo,ec); }

// Live fallback over already-loaded series. The chart's own history was tested by ClkResolve first.
int clkRefPos=0;
bool clkRefPending=false;
string clkDeadRefs[];       // failed during this walk; a scoped, expiring memo avoids needless repeat walks
string clkRefSym[];         // per reference: the series name
int    clkRefTried[];       // per reference: reads since it last showed progress
int    clkRefWeeks[];       // per reference: weeks of weekly opens seen on the last read
string clkRefsNote="";      // the walk was skipped or given up: the reason, said once in the EA's own note
#define CLK_PROOF_WEEKS   60    // a reference is judged useless only once it holds this many weeks of opens
#define CLK_REF_MAX_READS 200   // ...but a feed that never reaches them is given up on instead of read forever
#define CLK_CLAIM         "CLK_OWN_"   // "this selection is ours": survives a terminal closed mid-read
int ClkRefBook(const string sym)
{
   for(int i=0;i<ArraySize(clkRefSym);i++) if(clkRefSym[i]==sym) return i;
   int n=ArraySize(clkRefSym);
   ArrayResize(clkRefSym,n+1); ArrayResize(clkRefTried,n+1); ArrayResize(clkRefWeeks,n+1);
   clkRefSym[n]=sym; clkRefTried[n]=0; clkRefWeeks[n]=-1;
   return n;
}
// One read of a reference. More weeks than last time means the download is alive, so the read counter restarts.
int ClkRefNoteRead(const string sym)
{
   int i=ClkRefBook(sym);
   if(clkEvWeeks>clkRefWeeks[i]) { clkRefWeeks[i]=clkEvWeeks; clkRefTried[i]=0; }
   return ++clkRefTried[i];
}
// Retire stale selections left by OLD builds only. New builds never create selection claims.
// An open chart takes ownership of its symbol: clear the old claim without touching that selection.
void ClkDropStaleLoans()
{
   for(int i=SymbolsTotal(true)-1;i>=0;i--)
   {
      string sym=SymbolName(i,true);
      if(sym=="") continue;
      string claim=CLK_CLAIM+sym;
      if(!GlobalVariableCheck(claim)) continue;
      if(TimeLocal()-(datetime)GlobalVariableGet(claim)<300) continue;
      if(ClkIsOpenChart(sym)) { GlobalVariableDel(claim); continue; }
      ResetLastError();
      if(!SymbolSelect(sym,false))
      {
         ClkLog(StringFormat("CLK_REF_CLEANUP_FAILED %s remains selected; terminal error=%d",sym,GetLastError()));
         continue;                                         // failed cleanup keeps its claim for a later retry
      }
      GlobalVariableDel(claim);                             // successful housekeeping is silent
   }
}
bool ClkRefIsDead(string sym)
{
   for(int i=0;i<ArraySize(clkDeadRefs);i++) if(clkDeadRefs[i]==sym) return true;
   return false;
}
void ClkRefMarkDead(string sym)
{
   if(sym==_Symbol || ClkRefIsDead(sym)) return;
   int n=ArraySize(clkDeadRefs); ArrayResize(clkDeadRefs,n+1); clkDeadRefs[n]=sym;
}
// ---- expiring negative memo, scoped to the exact loaded candidate set -----------------------------------
#define CLK_NOPROOF_HOURS 12
string ClkRefsFile() { return "clock_refs_"+IntegerToString(ClkHash(AccountInfoString(ACCOUNT_SERVER)))+".txt"; }
bool ClkProofInteger(string text,long &value)
{
   StringTrimLeft(text); StringTrimRight(text);
   if(text=="" || StringLen(text)>20) return false;
   value=StringToInteger(text);
   return IntegerToString(value)==text;                    // no partial parse, leading junk or silent zero
}
string ClkRefsKey()
{
   string refs[]; ArrayCopy(refs,clkEvidenceRefs);
   for(int i=0;i<ArraySize(refs);i++)
      for(int j=i+1;j<ArraySize(refs);j++)
         if(StringCompare(refs[i],refs[j])>0) { string tmp=refs[i]; refs[i]=refs[j]; refs[j]=tmp; }
   string key="";
   for(int i=0;i<ArraySize(refs);i++)
      if(ClkIsLoadedRef(refs[i])) key+=IntegerToString(StringLen(refs[i]))+":"+refs[i]+"|";
   return key;
}
bool ClkRefsGivenUp()
{
   string key=ClkRefsKey();
   if(key=="") return false;
   int h=FileOpen(ClkRefsFile(),FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h==INVALID_HANDLE) return false;
   string version="",server="",stamp="",savedKey="";
   if(!FileIsEnding(h)) version=FileReadString(h);
   if(!FileIsEnding(h)) server=FileReadString(h);
   if(!FileIsEnding(h)) stamp=FileReadString(h);
   if(!FileIsEnding(h)) savedKey=FileReadString(h);
   FileClose(h);
   long written=0;
   if(version!="loaded-1" || server!=AccountInfoString(ACCOUNT_SERVER) || savedKey!=key ||
      !ClkProofInteger(stamp,written)) return false;         // old catalogue-wide memos are not applicable
   return written>0 && TimeGMT()>=written && TimeGMT()-written<CLK_NOPROOF_HOURS*3600;
}
void ClkRefsGiveUp()
{
   string key=ClkRefsKey();
   if(key=="") return;
   int h=FileOpen(ClkRefsFile(),FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h==INVALID_HANDLE) return;
   FileWriteString(h,"loaded-1\r\n"+AccountInfoString(ACCOUNT_SERVER)+"\r\n"+
                     IntegerToString((long)TimeGMT())+"\r\n"+key+"\r\n");
   FileClose(h);
}
int ClkAnchorBase(int &rule,int &modeOpen,int &modeClose,int &openNY,string &usedSym)
{
   openNY=0; usedSym=""; clkRefPending=false; clkRefsNote="";
   if(MQLInfoInteger(MQL_TESTER)) return CLK_BASE_INVALID;   // tester never synchronises foreign symbols
   int observed=0;
   if(!ClkLiveOffset(observed)) return CLK_BASE_INVALID;
   datetime utc=TimeGMT();
   ClkBuildEvidenceRefs(clkEvidenceRefs); clkEvidenceRefsBuilt=true;
   if(ClkRefsGivenUp())
   { clkRefsNote="DST rule unproven from loaded history; current live offset is used"; return CLK_BASE_INVALID; }
   ArrayResize(clkDeadRefs,0);                               // changed inventory or expired memo permits new evidence
   bool anyHistory=false, triedAny=false;
   for(int tried=0;tried<8;tried++)
   {
      string sym=ClkEvidenceSymbolAt(clkRefPos);
      clkRefPos=(clkRefPos+1)%8;
      if(sym=="" || sym==_Symbol || ClkRefIsDead(sym)) continue;
      triedAny=true;
      datetime eo[],ec[];
      int st=ClkEvidenceFor(sym,rule,modeOpen,modeClose,eo,ec);
      int reads=ClkRefNoteRead(sym);
      if(st<0) { clkRefPending=true; continue; }
      anyHistory=true;
      int b=st==1 ? ClkBaseFromLive(observed,rule,utc) : CLK_BASE_INVALID;
      int b17=ClkBaseFromAnchor(modeOpen,17), b18=ClkBaseFromAnchor(modeOpen,18);
      if(st==1 && b!=CLK_BASE_INVALID && (b==b17 || b==b18))
      {
         openNY=b==b17 ? 17 : 18;
         usedSym=sym; clkRefPending=false;
         return b;                                         // identical live/open-anchor guard to the own-series rung
      }
      if(clkEvWeeks<CLK_PROOF_WEEKS && reads<=CLK_REF_MAX_READS)
      { clkRefPending=true; continue; }
      ClkRefMarkDead(sym);
   }
   if(!anyHistory && triedAny) clkRefPending=true;
   int cands=0,live=0;
   for(int i=0;i<8;i++)
   {
      string c=ClkEvidenceSymbolAt(i);
      if(c=="" || c==_Symbol) continue;
      cands++;
      if(!ClkRefIsDead(c)) live++;
   }
   if(cands>0 && live==0)
   {
      clkRefsNote="DST rule unproven from loaded history; current live offset is used";
      ClkRefsGiveUp();
   }
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
   FileWriteString(h,StringFormat("%s,%d,%d,%s,%I64d,%d,%d,%d,%s,%d\r\n",ClkServerKey(),clkRule,clkBase,
                                clkSource,(long)TimeGMT(),clkEvWeeks,clkEvHits,clkEvMargin,clkAnchorAudit,clkEvCloses));
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
// Shared LIVE proofs expire independently of tester profiles. Readers never refresh their evidence timestamp.
#define CLK_SHARED_PROOF_SECONDS 86400
bool ClkVerifiedLiveProof(string line,int observedSec,datetime utc,int &rule,int &base)
{
   string f[];
   if(StringSplit(line,',',f)!=10 || f[0]!=ClkServerKey() ||
      (f[3]!="LIVE" && f[3]!="LIVE-REF")) return false;
   long r=0,b=0,written=0,weeks=0,hits=0,margin=0,closes=0;
   if(!ClkProofInteger(f[1],r) || !ClkProofInteger(f[2],b) || !ClkProofInteger(f[4],written) ||
      !ClkProofInteger(f[5],weeks) || !ClkProofInteger(f[6],hits) || !ClkProofInteger(f[7],margin) ||
      !ClkProofInteger(f[9],closes)) return false;
   if(r<0 || r>2 || b<-720 || b>840 || b%15!=0 || written<=0 || utc<written ||
      utc-written>CLK_SHARED_PROOF_SECONDS) return false;
   if(weeks<CLK_MIN_WEEKS || weeks>CLK_MAX_WEEKS || closes<CLK_MIN_WEEKS-1 || closes>CLK_MAX_WEEKS ||
      MathAbs(weeks-closes)>1 || hits<0 || hits>weeks+closes || margin<CLK_MIN_MARGIN || margin>hits ||
      hits*100<(weeks+closes)*85) return false;
   if(f[8]!="agree" && f[8]!="DISAGREE" && f[8]!="n/a") return false;
   long expected=(long)ClkUtcToServer(utc,(int)r,(int)b)-(long)utc;
   if(MathAbs(expected-observedSec)>CLK_TOL_SEC) return false;
   rule=(int)r; base=(int)b;
   return true;
}
bool ClkReadLiveProof(int observedSec,datetime utc,int &rule,int &base)
{
   int h=FileOpen(ClkProfileFile(),FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h==INVALID_HANDLE) return false;
   string line="";
   bool read=ClkReadLine(h,line);
   FileClose(h);
   return read && ClkVerifiedLiveProof(line,observedSec,utc,rule,base);
}
bool ClkTryLiveFallback()
{
   if(MQLInfoInteger(MQL_TESTER)) return false;
   int observed=0;
   if(!ClkLiveOffset(observed)) return false;
   datetime utc=TimeGMT();
   bool confirming=clkResolved && clkProvisional;
   int rule=-1,base=CLK_BASE_INVALID;
   if(!clkIgnoreProfile && ClkReadLiveProof(observed,utc,rule,base))
   {
      ClkSetSingle(rule,base,"SHARED-LIVE");
      clkNote="fresh verified live proof from another instance on this server";
      if(confirming) ClkJournal("CLK_CONFIRMED "+ClkText()+" from verified same-server evidence");
      return true;                                         // no history requests or evidence refresh/write
   }
   int mo=0,mc=0,on=0; string used="";
   base=ClkAnchorBase(rule,mo,mc,on,used);
   if(base==CLK_BASE_INVALID || used=="") return false;
   ClkSetSingle(rule,base,"LIVE-REF");
   clkNote=StringFormat("clock verified from already-loaded history (%d weekly opens)",clkEvWeeks);
   int anchorOpen=0,anchorBase=ClkBaseFromCloseAnchor(mo,mc,anchorOpen);
   clkAnchorAudit=anchorBase==CLK_BASE_INVALID ? "n/a" : (anchorBase==base ? "agree" : "DISAGREE");
   ClkLearnedWrite();                                       // only newly proven history can publish a shared proof
   if(confirming) ClkJournal("CLK_CONFIRMED "+ClkText()+" from already-loaded history");
   return true;
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
            ClkLog(StringFormat("CLK_GIVE_UP tester history does not fit the accepted weekly shape "
                                "(close base %+dm, open base %+dm). Only the traded feed is used; "
                                "a same-server profile from a verified live run can supply the mapping.",
                                ClkBaseFromAnchor(mc,17),ClkBaseFromAnchor(mo,18)));
            return;
         }
         ClkSetSingle(rule,ab,src);
         clkNote=(used==_Symbol)
            ? StringFormat("ASSUMPTION: weekly close 17:00 NY, feed opens %d:00 NY; confirm with a live profile",on)
            : StringFormat("ASSUMPTION: proved on %s (standard hours on this server), traded feed cannot prove it",used);
         ClkJournal(StringFormat("CLK_ASSUMPTION %s base %+dm; a live/registry profile outranks this",ClkText(),ab));
         return;
      }
   }
   // Own-series inference has priority. Otherwise reuse verified same-server evidence or test loaded series.
   // Merely copying another provisional offset would not establish a DST rule.
   if(st!=1 && ClkTryLiveFallback()) return;
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
   if(clkRefsNote!="") clkNote=clkRefsNote;                   // the walk was skipped or gave up: say which, once
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
   static bool swept=false;
   if(!swept && !MQLInfoInteger(MQL_TESTER)) { ClkDropStaleLoans(); swept=true; }
   ClkResolve(nowSrv);
   if(!clkResolved) { clkOkFlag=false; clkSkew=false; return; }
   if(!clkAnnounced)                     // one line per EA process: an EA's own log can always prove its clock
   {
      clkAnnounced=true;
      PrintFormat("CLK_EA %s symbol=%s clock=%s source=%s server=%s adapter=%s",
                  MQLInfoString(MQL_PROGRAM_NAME),_Symbol,ClkText(),clkSource,
                  AccountInfoString(ACCOUNT_SERVER),CLK_ADAPTER_VERSION);
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
   if(clkSource=="LIVE" || clkSource=="LIVE-REF" || clkSource=="SHARED-LIVE" || clkProvisional)
   { clkResolved=false; clkProvisional=false; clkRetry=nowSrv+30; }
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
//+------------------------------------------------------------------+
//|                                             ExecutionRuntime.mqh |
//|                     OpenDrive — Execution, Sizing & State Engine |
//+------------------------------------------------------------------+
#ifndef OPENDRIVE_EXECUTION_RUNTIME
#define OPENDRIVE_EXECUTION_RUNTIME

// Global Execution State
ulong    g_openTicket  = 0;
int      g_openDir     = 0;
double   g_openPrice   = 0.0;
double   g_openSL      = 0.0;
double   g_openRisk    = 0.0;
double   g_extreme     = 0.0;
bool     g_trailActive = false;
datetime g_entryBar    = 0;

// Daily Guard State
long     g_dayKey      = -1;
double   g_dayStartBal = 0.0;
bool     g_dailyLocked = false;

// Statistics & Metrics
int      g_dayBuyCount  = 0;
int      g_daySellCount = 0;
double   g_lastSigDist  = -1.0;
double   g_lastRiskPct  = 0.0;

// Account-scoped, two-slot checkpoint. A missing position is not an exit receipt.
long g_evaluatedDayKey=-1;
ulong g_ownedId=0, g_entryOrder=0, g_entryDeal=0, g_closeOrder=0;
bool g_entryPending=false, g_closePending=false;
bool g_closeRequested=false;
datetime g_closeRetryAfter=0,g_repairRetryAfter=0;
bool g_costCoveredApplied=false;
uint g_restriction=0;
long g_stateGeneration=0;
int g_stateLease=INVALID_HANDLE;
string g_stateBase="", g_entryToken="", g_recoveryReason="";
bool g_recoveryReady=false, g_stateLoaded=false, g_stateFault=false;
string ODStateIdentity()
{
   return IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+"/"+AccountInfoString(ACCOUNT_SERVER)+"/"+_Symbol+"/"+IntegerToString((long)MagicNumber);
}
string ODManagementSettings()
{
   return IntegerToString(AtrPeriod)+","+IntegerToString((int)AtrMode)+","+
      DoubleToString(StopATR,16)+","+DoubleToString(ActivateATR,16)+","+DoubleToString(TrailATR,16);
}

uint ODChecksum(const string value)
{
   uint hash=2166136261;
   for(int i=0;i<StringLen(value);i++) hash=(hash^(uint)StringGetCharacter(value,i))*16777619;
   return hash;
}
string ODStatePayload()
{
   return IntegerToString(g_stateGeneration)+"|"+IntegerToString((long)g_ownedId)+"|"+
      IntegerToString((long)g_openTicket)+"|"+IntegerToString(g_openDir)+"|"+
      DoubleToString(g_openPrice,16)+"|"+DoubleToString(g_openSL,16)+"|"+
      DoubleToString(g_openRisk,16)+"|"+DoubleToString(g_extreme,16)+"|"+
      IntegerToString(g_trailActive)+"|"+IntegerToString(g_costCoveredApplied)+"|"+
      IntegerToString((long)g_entryBar)+"|"+IntegerToString(g_entryPending)+"|"+
      IntegerToString(g_closePending)+"|"+IntegerToString((long)g_entryOrder)+"|"+
      IntegerToString((long)g_entryDeal)+"|"+g_entryToken+"|"+IntegerToString(g_restriction)+"|"+
      IntegerToString(g_dayKey)+"|"+DoubleToString(g_dayStartBal,16)+"|"+
      IntegerToString(g_dailyLocked)+"|"+IntegerToString(g_dayBuyCount)+"|"+
      IntegerToString(g_daySellCount)+"|"+IntegerToString(g_evaluatedDayKey)+"|"+ODStateIdentity()+"|"+ODManagementSettings()+"|"+IntegerToString((long)g_closeOrder)+"|"+
      IntegerToString(g_closeRequested)+"|"+IntegerToString((long)g_closeRetryAfter);
}
bool ODSaveState()
{
   if(MQLInfoInteger(MQL_TESTER)) return true;
   if(g_stateLease==INVALID_HANDLE) return false;
   g_stateGeneration++;
   string payload=ODStatePayload();
   string path=g_stateBase+"."+IntegerToString(g_stateGeneration%2);
   int file=FileOpen(path,FILE_BIN|FILE_WRITE|FILE_UNICODE|FILE_COMMON);
   if(file==INVALID_HANDLE) {g_stateFault=true;g_recoveryReady=false;g_recoveryReason="checkpoint write failed";return false;}
   FileWriteInteger(file,0x4F443031,INT_VALUE);
   FileWriteInteger(file,StringLen(payload),INT_VALUE);
   FileWriteString(file,payload,StringLen(payload));
   FileWriteInteger(file,(int)ODChecksum(payload),INT_VALUE);
   FileFlush(file);
   bool ok=(FileTell(file)==12+2*StringLen(payload));
   FileClose(file);
   if(!ok) {g_stateFault=true;g_recoveryReady=false;g_recoveryReason="checkpoint incomplete";}
   return ok;
}
bool ODReadSlot(const string path,string &payload,long &generation)
{
   int file=FileOpen(path,FILE_BIN|FILE_READ|FILE_UNICODE|FILE_COMMON);
   if(file==INVALID_HANDLE) return false;
   bool ok=false;
   if(FileSize(file)>=12 && FileReadInteger(file,INT_VALUE)==0x4F443031)
   {
      int count=FileReadInteger(file,INT_VALUE);
      if(count>0 && count<4096 && FileSize(file)==12+2*count)
      {
         payload=FileReadString(file,count);
         uint checksum=(uint)FileReadInteger(file,INT_VALUE);
         string fields[];
         ok=(checksum==ODChecksum(payload) && StringSplit(payload,'|',fields)==28);
         if(ok) {generation=StringToInteger(fields[0]);ok=generation>0;}
      }
   }
   FileClose(file);return ok;
}
bool ODLoadState()
{
   if(MQLInfoInteger(MQL_TESTER)) return true;
   string identity=AccountInfoString(ACCOUNT_SERVER)+"|"+_Symbol+"|"+IntegerToString((long)MagicNumber);
   g_stateBase="OpenDrive_"+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+"_"+IntegerToString(ODChecksum(identity));
   g_stateLease=FileOpen(g_stateBase+".lock",FILE_BIN|FILE_READ|FILE_WRITE|FILE_COMMON);
   if(g_stateLease==INVALID_HANDLE) {g_recoveryReason="ownership lease unavailable";return false;}
   string a="",b="",payload="";long ga=0,gb=0;
   bool va=ODReadSlot(g_stateBase+".0",a,ga),vb=ODReadSlot(g_stateBase+".1",b,gb);
   if(!va && !vb)
   {
      if(FileIsExist(g_stateBase+".0",FILE_COMMON)||FileIsExist(g_stateBase+".1",FILE_COMMON))
      {g_recoveryReason="checkpoint corrupt; protection retained";return false;}
      return true;
   }
   payload=(va && (!vb || ga>gb))?a:b;
   string f[];StringSplit(payload,'|',f);
   if(f[23]!=ODStateIdentity()) {g_recoveryReason="checkpoint identity mismatch";return false;}
   g_stateGeneration=StringToInteger(f[0]);g_ownedId=(ulong)StringToInteger(f[1]);
   g_openTicket=(ulong)StringToInteger(f[2]);g_openDir=(int)StringToInteger(f[3]);
   g_openPrice=StringToDouble(f[4]);g_openSL=StringToDouble(f[5]);g_openRisk=StringToDouble(f[6]);
   g_extreme=StringToDouble(f[7]);g_trailActive=(StringToInteger(f[8])!=0);
   g_costCoveredApplied=(StringToInteger(f[9])!=0);g_entryBar=(datetime)StringToInteger(f[10]);
   g_entryPending=(StringToInteger(f[11])!=0);g_closePending=(StringToInteger(f[12])!=0);
   g_entryOrder=(ulong)StringToInteger(f[13]);g_entryDeal=(ulong)StringToInteger(f[14]);
   g_entryToken=f[15];g_restriction=(uint)StringToInteger(f[16]);g_dayKey=StringToInteger(f[17]);
   g_dayStartBal=StringToDouble(f[18]);g_dailyLocked=(StringToInteger(f[19])!=0);
   g_dayBuyCount=(int)StringToInteger(f[20]);g_daySellCount=(int)StringToInteger(f[21]);
   g_evaluatedDayKey=StringToInteger(f[22]);g_stateLoaded=true;
   g_closeOrder=(ulong)StringToInteger(f[25]);
   g_closeRequested=(StringToInteger(f[26])!=0);g_closeRetryAfter=(datetime)StringToInteger(f[27]);
   if((g_ownedId!=0 || g_entryPending) && f[24]!=ODManagementSettings())
   {g_recoveryReason="live management settings mismatch";return false;}
   if((g_ownedId!=0 || g_entryPending) && (MathAbs(g_openDir)!=1 || g_openRisk<=0 ||
      g_openPrice<=0 || g_openSL<=0 || g_extreme<=0 || g_entryBar<=0 || g_entryToken=="" ||
      !MathIsValidNumber(g_openRisk) || !MathIsValidNumber(g_openSL) ||
      !MathIsValidNumber(g_openPrice) || !MathIsValidNumber(g_extreme)))
   {g_recoveryReason="invalid owned checkpoint";return false;}
   if(g_closeRequested && g_ownedId==0) {g_recoveryReason="invalid close checkpoint";return false;}
   return true;
}
void ODObserveResult(const MqlTradeResult &result)
{
   if(result.retcode==TRADE_RETCODE_TRADE_DISABLED || result.retcode==TRADE_RETCODE_SERVER_DISABLES_AT ||
      result.retcode==TRADE_RETCODE_CLIENT_DISABLES_AT || result.retcode==TRADE_RETCODE_CLOSE_ONLY ||
      result.retcode==TRADE_RETCODE_LONG_ONLY || result.retcode==TRADE_RETCODE_SHORT_ONLY)
   {g_restriction=result.retcode;g_recoveryReady=false;g_recoveryReason="broker restriction "+IntegerToString(g_restriction);ODSaveState();}
}
bool ODSelectedOwned()
{
   return g_ownedId!=0 && PositionGetString(POSITION_SYMBOL)==_Symbol &&
      (ulong)PositionGetInteger(POSITION_MAGIC)==MagicNumber &&
      (ulong)PositionGetInteger(POSITION_IDENTIFIER)==g_ownedId;
}
// Opening evidence must be ours; an externally submitted exit is allowed.
bool ODPositionEvidence(const ulong id,double &remaining)
{
   remaining=0;bool opening=false;double opened=0;
   if(g_entryOrder==0 || !HistoryOrderSelect(g_entryOrder) ||
      HistoryOrderGetString(g_entryOrder,ORDER_SYMBOL)!=_Symbol ||
      (ulong)HistoryOrderGetInteger(g_entryOrder,ORDER_MAGIC)!=MagicNumber ||
      (ulong)HistoryOrderGetInteger(g_entryOrder,ORDER_POSITION_ID)!=id) return false;
   double expected=HistoryOrderGetDouble(g_entryOrder,ORDER_VOLUME_INITIAL)-HistoryOrderGetDouble(g_entryOrder,ORDER_VOLUME_CURRENT);
   if(expected<=0) return false;
   if(!HistorySelectByPosition(id)) return false;
   int count=HistoryDealsTotal();
   for(int i=0;i<count;i++)
   {
      ulong deal=HistoryDealGetTicket(i);
      ENUM_DEAL_TYPE type=(ENUM_DEAL_TYPE)HistoryDealGetInteger(deal,DEAL_TYPE);
      if(type!=DEAL_TYPE_BUY && type!=DEAL_TYPE_SELL) continue;
      if(HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol) return false;
      ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY);
      if(entry==DEAL_ENTRY_IN)
      {
         if((ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=MagicNumber ||
            ((ulong)HistoryDealGetInteger(deal,DEAL_ORDER)!=g_entryOrder &&
             HistoryDealGetString(deal,DEAL_COMMENT)!=g_entryToken) ||
            (type==DEAL_TYPE_BUY?1:-1)!=g_openDir) return false;
         opening=true;opened+=HistoryDealGetDouble(deal,DEAL_VOLUME);remaining+=HistoryDealGetDouble(deal,DEAL_VOLUME);
      }
      else if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY)
      {
         if((type==DEAL_TYPE_BUY?1:-1)==g_openDir) return false;
         remaining-=HistoryDealGetDouble(deal,DEAL_VOLUME);
      }
      else return false;
   }
   return opening && MathAbs(opened-expected)<=0.00000001 && remaining>=-0.00000001;
}
void ODReconcile()
{
   g_recoveryReady=false;
   if(g_stateFault) return;
   if(!MQLInfoInteger(MQL_TESTER) && (!TerminalInfoInteger(TERMINAL_CONNECTED) || g_stateLease==INVALID_HANDLE)) return;
   if(g_restriction!=0) {g_recoveryReason="broker restriction "+IntegerToString(g_restriction);return;}
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong order=OrderGetTicket(i);
      if(order!=0 && OrderGetString(ORDER_SYMBOL)==_Symbol &&
         (ulong)OrderGetInteger(ORDER_MAGIC)==MagicNumber && order!=g_entryOrder && order!=g_closeOrder)
      {g_recoveryReason="unverified owned order; protection retained";return;}
   }
   // Hydrate an accepted/uncertain entry only from its exact request token/order.
   if(g_entryPending && g_ownedId==0)
   {
      if(!HistorySelect(g_entryBar-60,TimeCurrent())) {g_recoveryReason="entry history pending";return;}
      ulong found=0;int total=HistoryDealsTotal();
      for(int i=0;i<total;i++)
      {
         ulong deal=HistoryDealGetTicket(i);
         if(HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol ||
            (ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=MagicNumber ||
            HistoryDealGetInteger(deal,DEAL_ENTRY)!=DEAL_ENTRY_IN) continue;
         if((g_entryOrder!=0 && (ulong)HistoryDealGetInteger(deal,DEAL_ORDER)==g_entryOrder) ||
            HistoryDealGetString(deal,DEAL_COMMENT)==g_entryToken)
         {
            ulong id=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
            if((found!=0 && found!=id) || (g_entryOrder!=0 && g_entryOrder!=(ulong)HistoryDealGetInteger(deal,DEAL_ORDER)))
            {g_recoveryReason="ambiguous entry evidence";return;}
            found=id;g_entryOrder=(ulong)HistoryDealGetInteger(deal,DEAL_ORDER);
         }
      }
      if(found==0) {g_recoveryReason="entry acknowledgement pending";return;}
      g_ownedId=found;if(!ODSaveState()) return;
   }
   ulong ticket=0;int matches=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong current=PositionGetTicket(i);
      if(current==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol ||
         (ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      if(g_ownedId==0 || !ODSelectedOwned()) {g_recoveryReason="legacy/foreign position; protection retained";return;}
      matches++;ticket=current;
   }
   if(matches>1) {g_recoveryReason="multiple owned positions";return;}
   if(g_ownedId!=0)
   {
      double remaining=0;
      if(!ODPositionEvidence(g_ownedId,remaining)) {g_recoveryReason="owned fills pending";return;}
      if(matches==0)
      {
         if((g_entryOrder!=0 && OrderSelect(g_entryOrder)) || (g_closeOrder!=0 && OrderSelect(g_closeOrder)))
         {g_recoveryReason="owned order settlement pending";return;}
         if(MathAbs(remaining)>0.00000001) {g_recoveryReason="exit evidence pending";return;}
         if(g_entryOrder==0 || !HistoryOrderSelect(g_entryOrder)) {g_recoveryReason="entry settlement pending";return;}
         ENUM_ORDER_STATE entryState=(ENUM_ORDER_STATE)HistoryOrderGetInteger(g_entryOrder,ORDER_STATE);
         if(entryState!=ORDER_STATE_FILLED && entryState!=ORDER_STATE_CANCELED && entryState!=ORDER_STATE_EXPIRED && entryState!=ORDER_STATE_REJECTED)
         {g_recoveryReason="entry still active";return;}
         g_ownedId=0;g_openTicket=0;g_openDir=0;g_entryPending=false;g_closePending=false;g_closeRequested=false;g_closeOrder=0;
         g_trailActive=false;g_costCoveredApplied=false;
         if(!ODSaveState()) return;
      }
      else
      {
         if(!PositionSelectByTicket(ticket) || !ODSelectedOwned()) return;
         if(MathAbs(PositionGetDouble(POSITION_VOLUME)-remaining)>0.00000001)
         {g_recoveryReason="position/fill quantity pending";return;}
         g_openTicket=ticket;
         if(g_entryPending)
         {
            if(g_entryOrder==0 || !HistoryOrderSelect(g_entryOrder)) {g_recoveryReason="entry acknowledgement pending";return;}
            ENUM_ORDER_STATE entryState=(ENUM_ORDER_STATE)HistoryOrderGetInteger(g_entryOrder,ORDER_STATE);
            if(entryState!=ORDER_STATE_FILLED && entryState!=ORDER_STATE_CANCELED && entryState!=ORDER_STATE_EXPIRED)
            {g_recoveryReason="entry fills pending";return;}
            if(!PositionSelectByTicket(ticket) || !ODSelectedOwned()) return;
            g_openPrice=PositionGetDouble(POSITION_PRICE_OPEN);g_extreme=g_openPrice;
            g_openRisk=MathAbs(g_openPrice-g_openSL);
            if(g_openRisk<=0) {g_recoveryReason="invalid opening risk";return;}
            g_entryPending=false;if(!ODSaveState()) return;
         }
         double sl=PositionGetDouble(POSITION_SL);
         if(sl>0 && (g_openSL==0 || (sl-g_openSL)*g_openDir>0)) {g_openSL=sl;if(!ODSaveState())return;}
         if(g_closePending && g_closeOrder!=0 && !OrderSelect(g_closeOrder) && HistoryOrderSelect(g_closeOrder) &&
            (ulong)HistoryOrderGetInteger(g_closeOrder,ORDER_POSITION_ID)==g_ownedId)
         {
            ENUM_ORDER_STATE state=(ENUM_ORDER_STATE)HistoryOrderGetInteger(g_closeOrder,ORDER_STATE);
            if(state==ORDER_STATE_FILLED || state==ORDER_STATE_CANCELED || state==ORDER_STATE_REJECTED || state==ORDER_STATE_EXPIRED)
            {g_closePending=false;g_closeOrder=0;if(!ODSaveState())return;}
         }
      }
   }
   g_recoveryReason=g_closePending?"close acknowledgement pending":"";
   g_recoveryReady=!g_closePending;
}

//+------------------------------------------------------------------+
//| Self-Contained Native Broker Order Helpers                       |
//+------------------------------------------------------------------+
uint GetFillingMode()
{
   uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
   if((filling & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}

bool NativeClosePosition(ulong ticket)
{
   ODReconcile();
   if(!g_recoveryReady || g_closePending || !PositionSelectByTicket(ticket) || !ODSelectedOwned()) return false;
   if(!g_closeRequested) {g_closeRequested=true;if(!ODSaveState())return false;}
   if(TimeCurrent()<g_closeRetryAfter) return false;

   MqlTradeRequest request; ZeroMemory(request);
   MqlTradeResult  result;  ZeroMemory(result);

   ENUM_POSITION_TYPE pType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   request.action       = TRADE_ACTION_DEAL;
   request.position     = ticket;
   request.symbol       = _Symbol;
   request.volume       = PositionGetDouble(POSITION_VOLUME);
   request.type         = (pType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   request.price        = (pType == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   request.deviation    = (ulong)(SlippagePoints * 10);
   request.magic        = MagicNumber;
   request.comment      = "OD_Close";
   request.type_filling = (ENUM_ORDER_TYPE_FILLING)GetFillingMode();
   g_closePending=true;g_closeOrder=0;
   g_closeRetryAfter=TimeCurrent()+5;
   if(!ODSaveState()) return false;
   bool sent=OrderSend(request,result);
   g_closeOrder=result.order;
   if(!ODSaveState()) return false;
   ODObserveResult(result);
   if(!sent || (result.retcode!=TRADE_RETCODE_DONE && result.retcode!=TRADE_RETCODE_DONE_PARTIAL && result.retcode!=TRADE_RETCODE_PLACED))
   {
      // Timeouts/connection loss are ambiguous: never send another close blindly.
      if(result.retcode!=0 && result.retcode!=TRADE_RETCODE_TIMEOUT && result.retcode!=TRADE_RETCODE_CONNECTION)
      {g_closePending=false;ODSaveState();}
      PrintFormat("OpenDrive: Close pending/refused (%u) %s",result.retcode,result.comment);
      return false;
   }
   ODReconcile();
   return true;
}

bool NativeModifySL(ulong ticket, double newSL)
{
   ODReconcile();
   if(!g_recoveryReady || !PositionSelectByTicket(ticket) || !ODSelectedOwned()) return false;
   double current=PositionGetDouble(POSITION_SL);
   double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tick<=0) return false;
   newSL=NormalizeDouble((g_openDir>0?MathFloor(newSL/tick):MathCeil(newSL/tick))*tick,_Digits);
   if((current>0 && (newSL-current)*g_openDir<=0) || (g_openSL>0 && (newSL-g_openSL)*g_openDir<0)) return false;
   double market=SymbolInfoDouble(_Symbol,g_openDir>0?SYMBOL_BID:SYMBOL_ASK);
   if((market-newSL)*g_openDir<(double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point) return false;
   MqlTradeRequest request; ZeroMemory(request);
   MqlTradeResult  result;  ZeroMemory(result);

   request.action   = TRADE_ACTION_SLTP;
   request.position = ticket;
   request.symbol   = _Symbol;
   request.sl       = newSL;
   request.tp       = PositionGetDouble(POSITION_TP);

   bool sent=OrderSend(request,result);
   ODObserveResult(result);
   if(!sent)
   {
      PrintFormat("OpenDrive: ModifySL failed (%d)", GetLastError());
      return false;
   }
   if(result.retcode!=TRADE_RETCODE_DONE) return false;
   if(!PositionSelectByTicket(ticket) || !ODSelectedOwned()) return false;
   double observed=PositionGetDouble(POSITION_SL);
   if(observed<=0 || (observed-newSL)*g_openDir<-tick/2) return false;
   if(g_openSL==0 || (observed-g_openSL)*g_openDir>0) g_openSL=observed;
   return ODSaveState();
}

bool NativeSendOrder(ENUM_ORDER_TYPE orderType, double volume, double price, double sl, ulong &outTicket)
{
   MqlTradeRequest request; ZeroMemory(request);
   MqlTradeResult  result;  ZeroMemory(result);

   request.action       = TRADE_ACTION_DEAL;
   request.symbol       = _Symbol;
   request.volume       = volume;
   request.type         = orderType;
   request.price        = price;
   request.sl           = sl;
   request.tp           = 0;
   request.deviation    = (ulong)(SlippagePoints * 10);
   request.magic        = MagicNumber;
   request.comment      = g_entryToken;
   request.type_filling = (ENUM_ORDER_TYPE_FILLING)GetFillingMode();

   if(!ODSaveState()) return false; // intent is durable before broker mutation
   bool sent=OrderSend(request,result);
   g_entryOrder=result.order;g_entryDeal=result.deal;
   ODObserveResult(result);
   if(!sent || (result.retcode != TRADE_RETCODE_DONE && result.retcode != TRADE_RETCODE_DONE_PARTIAL && result.retcode != TRADE_RETCODE_PLACED))
   {
      if(result.retcode!=0 && result.retcode!=TRADE_RETCODE_TIMEOUT && result.retcode!=TRADE_RETCODE_CONNECTION)
         g_entryPending=false;
      ODSaveState();
      PrintFormat("OpenDrive: Server returned %d (%s)", result.retcode, result.comment);
      return false;
   }

   if(!ODSaveState()) return false;
   ODReconcile();
   outTicket=g_openTicket;
   return true;
}

// Retain the persisted ratchet even if the terminal missed a modification/stop.
void ODProtectPosition()
{
   if(g_recoveryReady && g_ownedId!=0 && g_closeRequested) {NativeClosePosition(g_openTicket);return;}
   if(!g_recoveryReady || g_ownedId==0 || g_openSL<=0 ||
      !PositionSelectByTicket(g_openTicket) || !ODSelectedOwned()) return;
   double actual=PositionGetDouble(POSITION_SL);
   if(actual>0 && (actual-g_openSL)*g_openDir>=0) return;
   if(TimeCurrent()<g_repairRetryAfter)return;
   g_repairRetryAfter=TimeCurrent()+5;
   double market=SymbolInfoDouble(_Symbol,g_openDir>0?SYMBOL_BID:SYMBOL_ASK);
   if((market-g_openSL)*g_openDir<=0) {NativeClosePosition(g_openTicket);return;}
   NativeModifySL(g_openTicket,g_openSL);
}

//+------------------------------------------------------------------+
//| Check and recover existing owned position                        |
//+------------------------------------------------------------------+
bool OwnPosition(ulong &ticket, ENUM_POSITION_TYPE &posType, double &openSL)
{
   if(!g_recoveryReady || g_ownedId==0) {ticket=0;return false;}
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!ODSelectedOwned()) continue;

      ticket  = t;
      posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      openSL  = PositionGetDouble(POSITION_SL);
      return true;
   }
   ticket = 0;
   return false;
}

//+------------------------------------------------------------------+
//| Restore state from terminal and memory                           |
//+------------------------------------------------------------------+
void RestoreExecutionState()
{
   ODReconcile();
}

//+------------------------------------------------------------------+
//| ForexFactory WebRequest Calendar Feed & News Protection Engine   |
//+------------------------------------------------------------------+
string   g_odFeedJson         = "";
datetime g_odFeedFetched      = 0;
datetime g_odFeedRetry        = 0;
int      g_odFeedStatus       = 0;
bool     g_newsReady          = false;
bool     g_newsBlocked        = false;
datetime g_newsWeek           = 0;
ulong    g_newsSuccessMs      = 0;
ulong    g_newsAttemptMs      = 0;
bool     g_newsLaunchLogged   = false;

struct ODNewsItem
{
   datetime timeServer;
   datetime timeUTC;
   string   title;
   string   impact;
};

ODNewsItem g_newsEvents[];
string     g_activeNewsTitle   = "";
datetime   g_activeNewsTime    = 0;
string     g_upcomingNewsTitle = "";
datetime   g_upcomingNewsTime  = 0;

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

int ODFeedGet(string &json, datetime &fetched, int &requestError)
{
   json = ""; fetched = g_odFeedFetched; requestError = 0;
   datetime now = TimeGMT();
   bool fresh = (fetched > 0 && now >= fetched && now - fetched < 3600 && g_odFeedJson != "");
   if((fresh && now - fetched < 1800) || now < g_odFeedRetry)
   {
      if(fresh) { json = g_odFeedJson; return 200; }
      return g_odFeedStatus;
   }

   string payload = ""; bool cached = false;
   int result = NewsFeedGet(payload, now, cached, InpNewsCacheInTester);
   requestError = 0;
   StringTrimLeft(payload); StringTrimRight(payload);

   if(result == 200 && (StringLen(payload) < 2 || StringSubstr(payload, 0, 1) != "[" || StringSubstr(payload, StringLen(payload)-1, 1) != "]"))
      result = -3;

   g_odFeedStatus = result;
   if(result == 200)
   {
      g_odFeedJson = payload; g_odFeedFetched = now; g_odFeedRetry = now + 1800;
      json = payload; fetched = now; return 200;
   }

   g_odFeedRetry = now + (result == 429 ? 900 : 300);
   if(fresh) { json = g_odFeedJson; return 200; }
   return result;
}

datetime ODNewsNY(datetime utc) { return utc + NYUTCOffsetSeconds(utc); }

datetime ODNewsWeek(datetime ny)
{
   MqlDateTime d; TimeToStruct(ny, d);
   return (datetime)((long)ny / 86400 * 86400) - d.day_of_week * 86400;
}

bool ODNewsValid()
{
   return g_newsReady && (GetTickCount64() - g_newsSuccessMs < 3600000)
          && g_newsWeek == ODNewsWeek(ODNewsNY(TimeGMT()));
}

bool ODNewsImpactAllowed(const string name, string impact)
{
   string title = name; StringToUpper(title);
   StringToUpper(impact);
   if(StringFind(title, "NEW HOME SALES") >= 0 || StringFind(title, "EXISTING HOME SALES") >= 0
      || StringFind(title, "PENDING HOME SALES") >= 0 || StringFind(title, "CRUDE OIL") >= 0
      || (StringFind(title, "EIA") >= 0 && StringFind(title, "STOCK") >= 0)
      || StringFind(title, "OIL STOCK") >= 0) impact = "MEDIUM";

   if(News_Impact == NEWS_RED_ONLY) return (impact == "HIGH");
   if(News_Impact == NEWS_RED_YELLOW) return (impact == "HIGH" || impact == "MEDIUM");
   if(News_Impact == NEWS_ALL) return true;
   return false;
}

string ODNewsField(string row, string key)
{
   int p = StringFind(row, "\"" + key + "\""); if(p < 0) return "";
   p = StringFind(row, ":", p + StringLen(key) + 2); if(p < 0) return "";
   p++; while(p < StringLen(row) && StringGetCharacter(row, p) <= 32) p++;
   if(StringGetCharacter(row, p) != '"') return "";
   string value = ""; bool escape = false;
   for(int i = p + 1; i < StringLen(row); i++)
   {
      ushort c = StringGetCharacter(row, i);
      if(escape) { value += ShortToString(c); escape = false; continue; }
      if(c == '\\') { escape = true; continue; }
      if(c == '"') return value;
      value += ShortToString(c);
   }
   return "";
}

bool ODNewsISO(string stamp, datetime &utc)
{
   int n = StringLen(stamp);
   if((n != 25 && n != 20) || StringSubstr(stamp, 4, 1) != "-" || StringSubstr(stamp, 7, 1) != "-"
      || StringSubstr(stamp, 10, 1) != "T" || StringSubstr(stamp, 13, 1) != ":" || StringSubstr(stamp, 16, 1) != ":") return false;
   for(int i = 0; i < 19; i++)
   {
      if(i == 4 || i == 7 || i == 10 || i == 13 || i == 16) continue;
      ushort c = StringGetCharacter(stamp, i); if(c < '0' || c > '9') return false;
   }
   MqlDateTime d = {};
   d.year = (int)StringToInteger(StringSubstr(stamp, 0, 4)); d.mon = (int)StringToInteger(StringSubstr(stamp, 5, 2));
   d.day  = (int)StringToInteger(StringSubstr(stamp, 8, 2)); d.hour = (int)StringToInteger(StringSubstr(stamp, 11, 2));
   d.min  = (int)StringToInteger(StringSubstr(stamp, 14, 2)); d.sec = (int)StringToInteger(StringSubstr(stamp, 17, 2));
   if(d.year < 2000 || d.mon < 1 || d.mon > 12 || d.day < 1 || d.day > 31 || d.hour > 23 || d.min > 59 || d.sec > 59) return false;
   datetime local = StructToTime(d);
   int offset = 0;
   if(n == 20)
   {
      if(StringSubstr(stamp, 19, 1) != "Z") return false;
   }
   else
   {
      ushort sign = StringGetCharacter(stamp, 19);
      if((sign != '+' && sign != '-') || StringSubstr(stamp, 22, 1) != ":") return false;
      int h = (int)StringToInteger(StringSubstr(stamp, 20, 2)), m = (int)StringToInteger(StringSubstr(stamp, 23, 2));
      if(h > 14 || m > 59 || (h == 14 && m != 0)) return false;
      offset = (h * 60 + m) * 60 * (sign == '+' ? 1 : -1);
   }
   utc = local - offset;
   return true;
}

bool ODNewsParse(string json, datetime week, int serverUTCOffset, ODNewsItem &items[])
{
   ArrayResize(items, 0); StringTrimLeft(json); StringTrimRight(json);
   int size = StringLen(json);
   if(size < 2 || StringGetCharacter(json, 0) != '[' || StringGetCharacter(json, size - 1) != ']') return false;
   int start = -1, dated = 0; bool quoted = false, escape = false;

   for(int i = 1; i < size - 1; i++)
   {
      ushort c = StringGetCharacter(json, i);
      if(quoted) { if(escape) escape = false; else if(c == '\\') escape = true; else if(c == '"') quoted = false; continue; }
      if(c == '"') { quoted = true; continue; }
      if(c == '{') { if(start >= 0) return false; start = i; continue; }
      if(c != '}') continue;
      if(start < 0) return false;

      string row = StringSubstr(json, start, i - start + 1); start = -1;
      string currency = ODNewsField(row, "country");
      string impact   = ODNewsField(row, "impact");
      string stamp    = ODNewsField(row, "date");
      string title    = ODNewsField(row, "title");

      if(currency == "" || impact == "" || stamp == "" || title == "") return false;
      datetime utc = 0;
      if(!ODNewsISO(stamp, utc) || ODNewsWeek(ODNewsNY(utc)) != week) return false;
      dated++;

      if(currency == "USD" && ODNewsImpactAllowed(title, impact))
      {
         int n = ArraySize(items);
         ArrayResize(items, n + 1);
         items[n].timeUTC    = utc;
         items[n].timeServer = utc + serverUTCOffset;
         items[n].title      = title;
         items[n].impact     = impact;
      }
   }
   return (dated > 0 && start < 0 && !quoted);
}

void ODNewsRefresh(datetime nowServer)
{
   if(News_Impact == NEWS_DISABLED || nowServer <= 0) return;
   if((bool)MQLInfoInteger(MQL_TESTER) || !(bool)TerminalInfoInteger(TERMINAL_CONNECTED)) return;

   ulong tick = GetTickCount64();
   if(g_newsAttemptMs > 0 && tick - g_newsAttemptMs < (ulong)(ODNewsValid() ? 1800000 : 300000)) return;
   g_newsAttemptMs = tick;

   string payload; datetime fetched; int requestError;
   int status = ODFeedGet(payload, fetched, requestError);
   if(status != 200)
   {
      if(!g_newsLaunchLogged)
      {
         PrintFormat("OpenDrive: ForexFactory calendar unavailable (HTTP %d, error %d): %s; entries blocked; retries run silently",
                     status, requestError,
                     status == 429 ? "provider rate limited; 15-minute backoff" : "check WebRequest URL in MT5 Options");
         g_newsLaunchLogged = true;
      }
      return;
   }

   datetime week = ODNewsWeek(ODNewsNY(TimeGMT()));
   int serverUTCOffset = (int)(MathRound((double)(TimeTradeServer() - TimeGMT()) / 3600.0) * 3600.0);
   ODNewsItem found[];
   if(!ODNewsParse(payload, week, serverUTCOffset, found))
   {
      if(!g_newsLaunchLogged)
      {
         Print("OpenDrive: ForexFactory calendar payload invalid or wrong week; retries run silently.");
         g_newsLaunchLogged = true;
      }
      return;
   }

   // Sort chronologically
   int total = ArraySize(found);
   for(int i = 0; i < total - 1; i++)
   {
      for(int j = i + 1; j < total; j++)
      {
         if(found[j].timeServer < found[i].timeServer)
         {
            ODNewsItem tmp = found[i];
            found[i] = found[j];
            found[j] = tmp;
         }
      }
   }

   ArrayResize(g_newsEvents, 0);
   for(int i = 0; i < total; i++)
   {
      if(i == 0 || found[i].timeServer != found[i-1].timeServer || found[i].title != found[i-1].title)
      {
         int n = ArraySize(g_newsEvents);
         ArrayResize(g_newsEvents, n + 1);
         g_newsEvents[n] = found[i];
      }
   }

   g_newsReady     = true;
   g_newsWeek      = week;
   g_newsSuccessMs = GetTickCount64() - (ulong)(MathMax(0, TimeGMT() - fetched) * 1000);

   if(!g_newsLaunchLogged)
   {
      PrintFormat("OpenDrive: ForexFactory USD calendar ready (%d events parsed for current week).", ArraySize(g_newsEvents));
      g_newsLaunchLogged = true;
   }
}

bool ODNewsWindow(datetime nowServer, datetime &activeEventTime, string &activeTitle)
{
   activeEventTime = 0; activeTitle = "";
   if(News_Impact == NEWS_DISABLED || (bool)MQLInfoInteger(MQL_TESTER)) return false;
   if(!ODNewsValid()) return false;

   int halfSeconds = (int)News_Window * 30; // 5 min -> 150s, 10 min -> 300s
   for(int i = 0; i < ArraySize(g_newsEvents); i++)
   {
      if(nowServer >= g_newsEvents[i].timeServer - halfSeconds && nowServer <= g_newsEvents[i].timeServer + halfSeconds)
      {
         activeEventTime = g_newsEvents[i].timeServer;
         activeTitle     = g_newsEvents[i].title;
         return true;
      }
   }
   return false;
}

double OpenDriveCostCashPerLot()
{
   double pts = MathMax(0.0, (double)SlippagePoints);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double slipCash  = 0.0;
   if(tickSize > 0.0 && tickValue > 0.0)
      slipCash = (pts * _Point / tickSize) * tickValue;
   return CommissionPerLot + 2.0 * slipCash;
}

double OpenDriveCostCoveredPrice(double entry, bool isBuy)
{
   if(entry <= 0.0) return entry;
   double costCash  = OpenDriveCostCashPerLot();
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0.0 || tickValue <= 0.0) return entry;
   double costTicks = (costCash / tickValue) * tickSize;
   costTicks = MathMax(costTicks, tickSize); // Ensure at least 1 tick cushion
   double rawCovered = isBuy ? (entry + costTicks) : (entry - costTicks);
   return NormalizeDouble(rawCovered, _Digits);
}

void ODNewsProtectAtCost(datetime nowServer, datetime eventTime, string title)
{
   ulong tk = 0;
   ENUM_POSITION_TYPE pType;
   double currentSL = 0.0;

   if(!OwnPosition(tk, pType, currentSL)) return;

   bool isBuy = (pType == POSITION_TYPE_BUY);
   double entry = PositionGetDouble(POSITION_PRICE_OPEN);
   double desiredSL = OpenDriveCostCoveredPrice(entry, isBuy);

   double tickSize   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double stopsLevel = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(isBuy)
   {
      // Already at or above desired cost-covered stop
      if(currentSL >= desiredSL - tickSize / 2.0) return;

      // Check if in profit and market is safely beyond desired SL + broker stops
      if(bid > desiredSL + stopsLevel + tickSize)
      {
         if(NativeModifySL(tk, desiredSL))
         {
            g_costCoveredApplied = true;
            ODSaveState();
            PrintFormat("OpenDrive: [NEWS BE] Stop ratcheted to cost-covered BE at %s (Entry: %s) ahead of %s [Server %s]",
                        DoubleToString(desiredSL, _Digits), DoubleToString(entry, _Digits), title, TimeToString(eventTime, TIME_MINUTES));
         }
      }
   }
   else
   {
      // Already at or below desired cost-covered stop (or currentSL == 0)
      if(currentSL > 0.0 && currentSL <= desiredSL + tickSize / 2.0) return;

      // Check if in profit and market is safely below desired SL - broker stops
      if(ask < desiredSL - stopsLevel - tickSize)
      {
         if(NativeModifySL(tk, desiredSL))
         {
            g_costCoveredApplied = true;
            ODSaveState();
            PrintFormat("OpenDrive: [NEWS BE] Stop ratcheted to cost-covered BE at %s (Entry: %s) ahead of %s [Server %s]",
                        DoubleToString(desiredSL, _Digits), DoubleToString(entry, _Digits), title, TimeToString(eventTime, TIME_MINUTES));
         }
      }
   }
}

void ODNewsGuard(datetime nowServer)
{
   if(News_Impact == NEWS_DISABLED || (bool)MQLInfoInteger(MQL_TESTER))
   {
      g_newsBlocked = false;
      return;
   }

   ODNewsRefresh(nowServer);

   datetime activeTime = 0; string activeTitle = "";
   bool inWindow = ODNewsWindow(nowServer, activeTime, activeTitle);
   g_newsBlocked = inWindow;

   if(inWindow)
   {
      g_activeNewsTitle = activeTitle;
      g_activeNewsTime  = activeTime;
   }
   else
   {
      g_activeNewsTitle = "";
      g_activeNewsTime  = 0;
   }

   // Update upcoming news event for HUD & protection
   g_upcomingNewsTime  = 0;
   g_upcomingNewsTitle = "";
   for(int i = 0; i < ArraySize(g_newsEvents); i++)
   {
      if(g_newsEvents[i].timeServer > nowServer)
      {
         g_upcomingNewsTime  = g_newsEvents[i].timeServer;
         g_upcomingNewsTitle = g_newsEvents[i].title;
         break;
      }
   }

   // 1. Flatten position before news release if requested by user/prop firm
   if(News_Flatten_Before && inWindow && activeTime > 0 && nowServer < activeTime)
   {
      ulong tk = 0; ENUM_POSITION_TYPE pType; double sl = 0.0;
      if(OwnPosition(tk, pType, sl))
      {
         PrintFormat("OpenDrive: [NEWS FLATTEN] Closing position #%I64u ahead of %s [Server %s]",
                     tk, activeTitle, TimeToString(activeTime, TIME_MINUTES));
         NativeClosePosition(tk);
      }
   }

   // 2. Cost-covered BE before news release
   if(News_Cost_Covered_BE)
   {
      datetime targetEventTime = (activeTime > 0) ? activeTime : g_upcomingNewsTime;
      string targetTitle = (activeTitle != "") ? activeTitle : g_upcomingNewsTitle;

      if(targetEventTime > 0 && targetEventTime > nowServer)
      {
         int leadSeconds = (int)News_Window * 60; // Check up to window minutes ahead of event
         if(nowServer >= targetEventTime - leadSeconds)
         {
            ODNewsProtectAtCost(nowServer, targetEventTime, targetTitle);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Daily Loss Lock Monitor                                          |
//+------------------------------------------------------------------+
void CheckDailyGuard(datetime nowServer)
{
   long currentDay = (long)(nowServer / 86400);
   if(currentDay != g_dayKey)
   {
      g_dayKey      = currentDay;
      g_dayStartBal = AccountInfoDouble(ACCOUNT_BALANCE);
      g_dailyLocked = false;
      ODSaveState();
   }

   if(DailyLossLimitPct > 0.0 && !g_dailyLocked)
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double threshold = g_dayStartBal * (1.0 - DailyLossLimitPct / 100.0);
      if(equity <= threshold)
      {
         g_dailyLocked = true;
         if(!ODSaveState()) return;
         ulong tk = 0;
         ENUM_POSITION_TYPE pType;
         double sl = 0.0;
         if(OwnPosition(tk, pType, sl))
         {
            NativeClosePosition(tk);
         }
         PrintFormat("OpenDrive: Daily loss lock activated (Equity: %.2f <= Threshold: %.2f)", equity, threshold);
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate position sizing (Dynamic Volatility or Static Fixed)   |
//+------------------------------------------------------------------+
double CalculateLots(int dir, double entry, double sl, double signalDistATR, double &appliedRiskPct)
{
   double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(minL <= 0.0) minL = 0.01;
   if(maxL <= 0.0) maxL = 1000.0;
   if(step <= 0.0) step = (minL > 0.0) ? minL : 0.01;

   // Determine lot decimal precision dynamically from broker volume step
   int lotDigits = 0;
   double s = step;
   while(s < 1.0 && lotDigits < 8)
   {
      s *= 10.0;
      lotDigits++;
   }

   if(UseFixedLots && FixedLots > 0.0)
   {
      appliedRiskPct = 0.0;
      double clamped = MathMax(minL, MathMin(maxL, FixedLots));
      return NormalizeDouble(clamped, lotDigits);
   }

   double mult = 1.0;
   if(RiskMode == RISK_DYNAMIC_VOLATILITY)
   {
      // Prop-firm optimization: scale risk by conviction / breakout distance
      if(signalDistATR >= 1.50)
         mult = 1.00; // Strong impulse: full risk
      else if(signalDistATR >= 0.75)
         mult = 0.50; // Moderate impulse: half risk
      else
         mult = 0.33; // Shallow impulse: third risk
   }
   else
   {
      mult = 1.00; // Static Fixed Risk for live compounding
   }

   appliedRiskPct = RiskPercent * mult;
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance <= 0.0) balance = AccountInfoDouble(ACCOUNT_EQUITY);
   if(balance <= 0.0) balance = 10000.0;

   double riskMoney = 0.0;
   if(RiskPercent > 0.0)
   {
      riskMoney = balance * (appliedRiskPct / 100.0);
   }
   else if(RiskMoney > 0.0)
   {
      riskMoney = RiskMoney * mult;
   }
   else
   {
      riskMoney = balance * 0.01;
   }

   // 1. Calculate profit/loss per 1.0 lot via OrderCalcProfit
   double lossPerLot = 0.0;
   double profitOneLot = 0.0;
   ENUM_ORDER_TYPE orderType = (dir == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(OrderCalcProfit(orderType, _Symbol, 1.0, entry, sl, profitOneLot) && profitOneLot < 0.0)
   {
      lossPerLot = MathAbs(profitOneLot);
   }

   // 2. Broker-agnostic fallback if OrderCalcProfit returns 0, false, or tick cache is unready
   if(lossPerLot <= 0.0)
   {
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double point     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      if(tickSize <= 0.0) tickSize = (point > 0.0) ? point : 1.0;
      double pointDist = MathAbs(entry - sl);
      if(tickValue > 0.0)
      {
         lossPerLot = (pointDist / tickSize) * tickValue;
      }
      else
      {
         double contractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
         if(contractSize <= 0.0) contractSize = 1.0;
         lossPerLot = pointDist * contractSize;
      }
   }

   if(lossPerLot <= 0.0)
   {
      PrintFormat("OpenDrive: Warning - Could not determine loss per lot for symbol %s.", _Symbol);
      return minL;
   }

   double rawLots = riskMoney / lossPerLot;
   double calculatedLots = 0.0;

   if(rawLots < minL)
   {
      if(AllowMinLotFallback)
      {
         calculatedLots = minL;
         PrintFormat("OpenDrive: Sizing info - Target risk lot (%.4f, Risk: $%.2f) is below broker min lot (%.4f). Clamped to min lot (%.4f).",
                     rawLots, riskMoney, minL, minL);
      }
      else
      {
         PrintFormat("OpenDrive: Sizing info - Target risk lot (%.4f, Risk: $%.2f) is below broker min lot (%.4f). Trade rejected (AllowMinLotFallback=false).",
                     rawLots, riskMoney, minL);
         return 0.0;
      }
   }
   else
   {
      calculatedLots = MathFloor(rawLots / step + 1e-9) * step;
      if(calculatedLots < minL)
         calculatedLots = minL;
   }

   if(calculatedLots > maxL)
      calculatedLots = maxL;

   return NormalizeDouble(calculatedLots, lotDigits);
}

//+------------------------------------------------------------------+
//| Execute New Trade at 09:35 NY Bar Open                           |
//+------------------------------------------------------------------+
bool ODIndexSymbol(string symbol)
{
   StringToUpper(symbol);
   string tags[]={"NASDAQ","USTEC","US100","US 100","NAS100","S&P","US500","US 500","US30","US 30","DOW","DAX","DE40","GER40"};
   for(int i=0;i<ArraySize(tags);i++) if(StringFind(symbol,tags[i])>=0) return true;
   return symbol=="NQ" || symbol=="MNQ" || symbol=="ES" || symbol=="MES" || symbol=="YM" || symbol=="MYM";
}
bool ODOpposingExposure(const int side)
{
   if(!BlockOpposingExposure) return false;
   bool index=ODIndexSymbol(_Symbol);
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      if(PositionGetTicket(i)==0) continue;
      string symbol=PositionGetString(POSITION_SYMBOL);
      if(symbol!=_Symbol && !(index && ODIndexSymbol(symbol))) continue;
      if((PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1)!=side) return true;
   }
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(OrderGetTicket(i)==0) continue;
      string symbol=OrderGetString(ORDER_SYMBOL);
      if(symbol!=_Symbol && !(index && ODIndexSymbol(symbol))) continue;
      ENUM_ORDER_TYPE type=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      bool buy=(type==ORDER_TYPE_BUY || type==ORDER_TYPE_BUY_LIMIT || type==ORDER_TYPE_BUY_STOP || type==ORDER_TYPE_BUY_STOP_LIMIT);
      bool sell=(type==ORDER_TYPE_SELL || type==ORDER_TYPE_SELL_LIMIT || type==ORDER_TYPE_SELL_STOP || type==ORDER_TYPE_SELL_STOP_LIMIT);
      if((side>0 && sell)||(side<0 && buy)) return true;
   }
   return false;
}
bool ExecuteEntry(int dir, double signalDistATR, double currentATR)
{
   ODReconcile();
   if(!g_recoveryReady || g_ownedId!=0 || g_entryPending || g_closePending) return false;
   // A netting position cannot retain independently owned strategy exposure.
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {g_recoveryReason="independent ownership requires hedging account";return false;}
   if(ODOpposingExposure(dir)) {g_recoveryReason="opposing exposure; entry blocked";return false;}
   if(g_dailyLocked)
   {
      Print("OpenDrive: Trade blocked by daily loss limit.");
      return false;
   }

   if(g_newsBlocked)
   {
      PrintFormat("OpenDrive: Trade blocked by active news blackout window (%s).", g_activeNewsTitle);
      return false;
   }

   if(MaxSpreadPoints > 0)
   {
      int currentSpread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      if(currentSpread > MaxSpreadPoints)
      {
         PrintFormat("OpenDrive: Spread %d exceeds cap %d. Entry skipped.", currentSpread, MaxSpreadPoints);
         return false;
      }
   }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double entryPrice = (dir == 1) ? ask : bid;
   double stopDistance = StopATR * currentATR;
   double tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tickSize<=0)return false;
   double rawStop=entryPrice-dir*stopDistance;
   double stopLoss=NormalizeDouble((dir>0?MathFloor(rawStop/tickSize):MathCeil(rawStop/tickSize))*tickSize,_Digits);

   double stopsLevel = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(stopDistance < stopsLevel)
   {
      PrintFormat("OpenDrive: Stop distance %.2f below broker minimum %.2f.", stopDistance, stopsLevel);
      return false;
   }

   double appliedRisk = 0.0;
   double volume = CalculateLots(dir, entryPrice, stopLoss, signalDistATR, appliedRisk);
   if(volume <= 0.0)
   {
      PrintFormat("OpenDrive: Calculated lot size is 0.0 (Risk: %.2f%%). Check account balance.", appliedRisk);
      return false;
   }

   ulong newTicket = 0;
   ENUM_ORDER_TYPE orderType = (dir == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   g_entryPending=true;g_entryOrder=0;g_entryDeal=0;
   string prefix=StringSubstr(TradeComment,0,8);StringReplace(prefix,"|","_");
   g_entryToken=prefix+"_"+IntegerToString((long)TimeLocal())+"_"+IntegerToString((long)(GetMicrosecondCount()%10000000000));
   g_entryToken=StringSubstr(g_entryToken,0,31);
   g_openDir=dir;g_openPrice=entryPrice;g_openSL=stopLoss;g_openRisk=stopDistance;
   g_extreme=entryPrice;g_trailActive=false;g_costCoveredApplied=false;
   g_entryBar=iTime(_Symbol,PERIOD_M5,0);
   if(dir==1) g_dayBuyCount++;else g_daySellCount++;
   bool success = NativeSendOrder(orderType, volume, entryPrice, stopLoss, newTicket);

   if(!success)
   {
      Print("OpenDrive: NativeSendOrder failed.");
      return false;
   }

   g_lastSigDist = signalDistATR;
   g_lastRiskPct = appliedRisk;

   ODSaveState();

   if(WriteLog)
   {
      PrintFormat("OpenDrive: %s executed @ %s | Lots: %.2f | SL: %s (%.1f pts) | Conviction: %.2f ATR | Risk: %.2f%%",
                  dir == 1 ? "LONG" : "SHORT",
                  DoubleToString(entryPrice, _Digits),
                  volume,
                  DoubleToString(stopLoss, _Digits),
                  stopDistance / _Point,
                  signalDistATR,
                  appliedRisk);
   }

   return true;
}

//+------------------------------------------------------------------+
//| Manage Open Position: Chandelier Trailing & 16:00 NY Flat Exit   |
//+------------------------------------------------------------------+
void ManagePosition(const MqlRates &lastClosedBar, double currentATR, bool pastSessionExit)
{
   ODReconcile();
   if(!g_recoveryReady) return;
   ulong tk = 0;
   ENUM_POSITION_TYPE pType;
   double currentSL = 0.0;

   if(!OwnPosition(tk, pType, currentSL))
   {
      return;
   }

   // 1. Time-based Session Liquidation (16:00 NY Cash Close)
   if(FlatAtExit && pastSessionExit)
   {
      if(WriteLog) PrintFormat("OpenDrive: 16:00 NY session close reached. Closing position #%I64u flat.", tk);
      NativeClosePosition(tk);
      return;
   }

   // Skip if bar is before trade entry
   if(lastClosedBar.time < g_entryBar) return;

   int dir = (pType == POSITION_TYPE_BUY) ? 1 : -1;
   double spreadPts = lastClosedBar.spread * _Point;

   // Update extreme reached
   if(dir == 1)
      g_extreme = MathMax(g_extreme, lastClosedBar.high);
   else
      g_extreme = (g_extreme == 0.0) ? (lastClosedBar.low + spreadPts) : MathMin(g_extreme, lastClosedBar.low + spreadPts);

   // 2. Chandelier Trail Activation Check (+0.25 ATR profit on closed bar)
   if(!g_trailActive)
   {
      double confirmPrice = (dir == 1) ? lastClosedBar.close : (lastClosedBar.close + spreadPts);
      double currentGain  = (confirmPrice - g_openPrice) * dir;
      if(ActivateATR < 0.0 || currentGain >= ActivateATR * currentATR)
      {
         g_trailActive = true;
         if(WriteLog) PrintFormat("OpenDrive: Chandelier trail ACTIVATED (Gain: +%.2f ATR).", currentGain / currentATR);
      }
   }

   if(!ODSaveState()) return;
   if(!g_trailActive) return; // Only hard stop is active until confirmed

   // 3. Ratchet Chandelier Trailing Stop
   if(g_newsBlocked && News_Block_Modification)
   {
      // High-impact news blackout active: order modifications blocked to comply with prop firm regulations
      return;
   }

   double targetSL = currentSL;
   double newTrail = NormalizeDouble((dir == 1) ? (g_extreme - TrailATR * currentATR) : (g_extreme + TrailATR * currentATR), _Digits);

   if((dir == 1 && newTrail > targetSL) || (dir == -1 && (targetSL == 0.0 || newTrail < targetSL)))
   {
      targetSL = newTrail;
   }

   if(targetSL != currentSL)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      // Stop collision check
      if((dir == 1 && targetSL >= bid) || (dir == -1 && targetSL <= ask))
      {
         NativeClosePosition(tk);
         return;
      }

      double stopsLevel = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
      bool validDistance = (dir == 1) ? (bid - targetSL >= stopsLevel) : (targetSL - ask >= stopsLevel);
      if(validDistance)
      {
         NativeModifySL(tk, targetSL);
      }
   }
}

#endif // OPENDRIVE_EXECUTION_RUNTIME
