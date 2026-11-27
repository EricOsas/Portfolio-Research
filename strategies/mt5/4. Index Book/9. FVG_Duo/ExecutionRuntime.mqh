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
//|                                         ExecutionRuntime.mqh     |
//| FVG Duo execution, order tracking, recovery, sizing and journal  |
//| Developed by Osamwonyi Eric (@You_FoundEric)                     |
//+------------------------------------------------------------------+
#ifndef FVG_EXECUTION_RUNTIME
#define FVG_EXECUTION_RUNTIME

#include <Trade/Trade.mqh>

CTrade extTrade;

// State of owned position
ulong    ownedPositionId   = 0;
ulong    ownedTicket       = 0;
int      ownedSide         = 0;       // +1 = LONG, -1 = SHORT
string   ownedSource       = "";      // "OD", "TREND", "MERGED"
double   ownedEntryPrice   = 0.0;     // actual filled entry
double   ownedVolume       = 0.0;     // volume the server confirms is still open
double   ownedSignalEntry  = 0.0;     // unslipped model entry (oracle geometry anchor)
double   ownedStopPrice    = 0.0;
double   ownedTargetPrice  = 0.0;
datetime ownedEntryTime    = 0;
bool     ownedActive       = false;

// Reason passed to the next close so the journal can label the exit the way
// the Python oracle does (STOP / TARGET / TIME / FLIP).
string   g_pendingCloseReason = "";

// Last exit, in oracle terms. Used by the engine for the
// blocked_by_open_position rule and for the OD stop-out branch.
datetime g_lastExitBar     = 0;       // M1 open time of the exit bar
int      g_exitEventSeq    = 0;
string   g_exitEventSource = "";
string   g_exitEventReason = "";
datetime g_exitEventTime   = 0;

datetime TruncMinute(datetime t) { return t - (t % 60); }

//+------------------------------------------------------------------+
//| SYMBOL GRID                                                      |
//|                                                                  |
//| Every asset has its own tradable price grid: futures 0.25 / 0.1  |
//| (ES, NQ, GC), CFDs 0.1 / 0.01 / 0.001, FX 0.00001.              |
//| The strategy tick (the "1 tick" of the stop rule) is resolved     |
//| from the instrument unless it is pinned by input, and every      |
//| price handed to the server is snapped onto the live grid so an    |
//| order is never rejected for an off-grid stop.                     |
//+------------------------------------------------------------------+
double g_symTick   = 0.0;
int    g_symDigits = -1;

double SymTick()
{
   if(g_symTick > 0.0) return g_symTick;
   double t = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(t <= 0.0) t = _Point;
   if(t <= 0.0) t = 0.01;
   return t;
}

int SymDigits()
{
   if(g_symDigits >= 0) return g_symDigits;
   int d = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(d < 0) d = 2;
   return d;
}

// Snap a price onto the instrument's tradable grid.
double GridPrice(double price)
{
   double t = SymTick();
   double steps = price / t;
   double snapped = (MathAbs(steps - MathRound(steps)) < 1e-6) ? price : MathRound(steps) * t;
   return NormalizeDouble(snapped, SymDigits());
}

// Broker minimum distance between the market and a stop or target.
double MinStopDistance()
{
   long lvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double d = (double)lvl * _Point;
   if(d < 0.0) d = 0.0;
   return d;
}

//+------------------------------------------------------------------+
//| TRADE JOURNAL                                                     |
//| One row per closed position, in oracle terms, so an MT5 run can   |
//| be diffed trade-for-trade against the Python engine.              |
//+------------------------------------------------------------------+
#define JOURNAL_MAX 16384

ulong    j_posId[JOURNAL_MAX];
string   j_source[JOURNAL_MAX];
string   j_side[JOURNAL_MAX];
datetime j_entryServer[JOURNAL_MAX];
datetime j_entryNY[JOURNAL_MAX];
double   j_entryGeo[JOURNAL_MAX];
double   j_entryFill[JOURNAL_MAX];
double   j_stop[JOURNAL_MAX];
double   j_target[JOURNAL_MAX];
double   j_lots[JOURNAL_MAX];
datetime j_exitServer[JOURNAL_MAX];
datetime j_exitNY[JOURNAL_MAX];
double   j_exitPrice[JOURNAL_MAX];
string   j_exitReason[JOURNAL_MAX];
bool     j_written[JOURNAL_MAX];
int      j_count = 0;
int      j_writtenCount = 0;

int      g_journalHandle = INVALID_HANDLE;

bool JournalOpen()
{
   FolderCreate("FVG_Duo", FILE_COMMON);
   g_journalHandle = FileOpen("FVG_Duo/trades_mt5.csv",
                              FILE_COMMON | FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(g_journalHandle == INVALID_HANDLE)
   {
      Print("[FVG_DUO] Journal open failed");
      return false;
   }
   FileWrite(g_journalHandle, "trade_id", "pos_id", "source", "side",
             "entry_server", "entry_ny", "entry_model", "entry_fill",
             "exit_server", "exit_ny", "exit_price", "exit_reason",
             "stop", "target", "lots");
   return true;
}

int JournalFind(ulong positionId)
{
   for(int i = j_count - 1; i >= 0; i--)
      if(j_posId[i] == positionId) return i;
   return -1;
}

void JournalAdd(ulong positionId, string source, string side,
                datetime entryServer, double entryGeo, double entryFill,
                double stop, double target, double lots)
{
   if(j_count >= JOURNAL_MAX) return;
   int i = j_count++;
   j_posId[i]       = positionId;
   j_source[i]      = source;
   j_side[i]        = side;
   j_entryServer[i] = entryServer;
   j_entryNY[i]     = (entryServer > 0) ? NYTime(entryServer) : 0;
   j_entryGeo[i]    = entryGeo;
   j_entryFill[i]   = entryFill;
   j_stop[i]        = stop;
   j_target[i]      = target;
   j_lots[i]        = lots;
   j_exitServer[i]  = 0;
   j_exitNY[i]      = 0;
   j_exitPrice[i]   = 0.0;
   j_exitReason[i]  = "";
   j_written[i]     = false;
}

void JournalUpdate(ulong positionId, string source, double stop, double target)
{
   int i = JournalFind(positionId);
   if(i < 0) return;
   if(source != "") j_source[i] = source;
   j_stop[i]   = stop;
   j_target[i] = target;
}

// Held volume after a merge trim: the row records what was actually carried
// into the re-anchored stop, not what was opened.
void JournalLots(ulong positionId, double lots)
{
   int i = JournalFind(positionId);
   if(i < 0) return;
   j_lots[i] = lots;
}

void JournalWriteRow(int i)
{
   if(i < 0 || i >= j_count || j_written[i]) return;
   if(g_journalHandle == INVALID_HANDLE) return;
   if(j_exitServer[i] == 0) return;   // still open

   j_written[i] = true;
   j_writtenCount++;
   FileWrite(g_journalHandle, j_writtenCount, (long)j_posId[i], j_source[i], j_side[i],
             TimeToString(j_entryServer[i], TIME_DATE | TIME_SECONDS),
             TimeToString(j_entryNY[i], TIME_DATE | TIME_SECONDS),
             DoubleToString(j_entryGeo[i], SymDigits()),
             DoubleToString(j_entryFill[i], SymDigits()),
             TimeToString(j_exitServer[i], TIME_DATE | TIME_SECONDS),
             TimeToString(j_exitNY[i], TIME_DATE | TIME_SECONDS),
             DoubleToString(j_exitPrice[i], SymDigits()),
             j_exitReason[i],
             DoubleToString(j_stop[i], SymDigits()),
             DoubleToString(j_target[i], SymDigits()),
             DoubleToString(j_lots[i], 2));
   FileFlush(g_journalHandle);
}

void JournalClose(ulong positionId, datetime exitServer, double exitPrice, string reason)
{
   int i = JournalFind(positionId);
   if(i < 0) return;
   if(j_exitServer[i] != 0) return;   // already recorded
   j_exitServer[i] = exitServer;
   j_exitNY[i]     = (exitServer > 0) ? NYTime(exitServer) : 0;
   j_exitPrice[i]  = exitPrice;
   j_exitReason[i] = reason;

   string src = j_source[i];
   g_exitEventSeq++;
   g_exitEventSource = src;
   g_exitEventReason = reason;
   g_exitEventTime   = exitServer;
   g_lastExitBar     = TruncMinute(exitServer);

   // Rows are appended as soon as a position closes, so a terminal shutdown
   // cannot lose the tail of the run.
   JournalWriteRow(i);
}

void JournalFlush()
{
   if(g_journalHandle == INVALID_HANDLE) return;
   for(int i = 0; i < j_count; i++)
      JournalWriteRow(i);
   FileFlush(g_journalHandle);
}

void JournalCloser()
{
   JournalFlush();
   if(g_journalHandle != INVALID_HANDLE)
   {
      FileClose(g_journalHandle);
      g_journalHandle = INVALID_HANDLE;
   }
}

//+------------------------------------------------------------------+
//| MERGED ownership persisted across EA/terminal restarts            |
//+------------------------------------------------------------------+
string MergedStateGlobalKey(ulong positionId)
{
   return StringFormat("FVDM_%I64d_%I64u",
                       AccountInfoInteger(ACCOUNT_LOGIN), positionId);
}

bool IsPersistedMergedPosition(ulong positionId)
{
   if(positionId == 0) return false;
   string key = MergedStateGlobalKey(positionId);
   return GlobalVariableCheck(key) && GlobalVariableGet(key) > 0.5;
}

void PersistMergedPosition(ulong positionId)
{
   if(positionId == 0) return;
   GlobalVariableSet(MergedStateGlobalKey(positionId), 1.0);
   GlobalVariablesFlush();
}

void ClearPersistedMergedPosition(ulong positionId)
{
   if(positionId == 0) return;
   string key = MergedStateGlobalKey(positionId);
   if(GlobalVariableCheck(key))
   {
      GlobalVariableDel(key);
      GlobalVariablesFlush();
   }
}
double FdgCashPerUnit()
{
   // Money inputs are read in the ACCOUNT's own denomination, so the scale is the identity. No currency
   // declaration, no rate input, no cent assumption: a USD account, a USC cent account and any other
   // denomination size from exactly the numbers the terminal reports.
   return 1.0;
}
double AccountCashPerUnit() { return FdgCashPerUnit(); }              // name kept for existing call sites

// Entry captures this account-currency budget once; later equity changes cannot enlarge it.
double TargetRiskCash()
{
   double cashPerUSD = AccountCashPerUnit();
   if(cashPerUSD <= 0.0) return 0.0;
   if(InpSizingMode == SIZING_PERCENT)
      return AccountInfoDouble(ACCOUNT_EQUITY) * (InpRiskPercent / 100.0);
   if(InpSizingMode == SIZING_CASH)
      return InpCashRisk * cashPerUSD;
   if(InpSizingMode == SIZING_PERCENT_BALANCE)
   {
      double balBase = (InpFixedBalance > 0.0)
                       ? InpFixedBalance * cashPerUSD : g_fixedBalanceBase;
      if(balBase <= 0.0) balBase = AccountInfoDouble(ACCOUNT_BALANCE);
      return balBase * (InpRiskPercent / 100.0);
   }
   return 0.0;
}

double RiskVolume(double budget, double perLot, double minLot, double maxLot, double step)
{
   if(!MathIsValidNumber(budget) || !MathIsValidNumber(perLot) ||
      !MathIsValidNumber(minLot) || !MathIsValidNumber(maxLot) || !MathIsValidNumber(step) ||
      budget <= 0.0 || perLot <= 0.0 || minLot <= 0.0 || maxLot < minLot || step <= 0.0)
      return 0.0;
   double lots = MathFloor(MathMin(maxLot, budget / perLot) / step + 1e-10) * step;
   if(lots * perLot > budget + 1e-8) lots -= step;
   return lots + 1e-10 >= minLot ? lots : 0.0;
}

bool RiskPerLot(int side, double entry, double stop, double &perLot)
{
   perLot = 0.0;
   double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double reference = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if((side != 1 && side != -1) || !MathIsValidNumber(entry) || !MathIsValidNumber(stop) ||
      !MathIsValidNumber(tick) || !MathIsValidNumber(reference) || entry <= 0.0 || stop <= 0.0 ||
      tick <= 0.0 || reference <= 0.0 || InpRiskSlippageTicks < 0 ||
      !MathIsValidNumber(InpCommissionRTPerLot) || InpCommissionRTPerLot < 0.0 ||
      AccountCashPerUnit() <= 0.0) return false;
   double loss = 0.0;
   double stressedStop = stop - side * InpRiskSlippageTicks * tick;
   if(stressedStop <= 0.0 || !OrderCalcProfit(side > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                                            _Symbol, reference, entry, stressedStop, loss) ||
      !MathIsValidNumber(loss)) return false;
   perLot = MathMax(0.0, -loss) / reference + InpCommissionRTPerLot * AccountCashPerUnit();
   return MathIsValidNumber(perLot) && perLot > 0.0;
}

double CalculateLotSize(int side, double entryPrice, double stopPrice, double budget)
{
   if((side != 1 && side != -1) || !MathIsValidNumber(entryPrice) || !MathIsValidNumber(stopPrice) ||
      entryPrice <= 0.0 || stopPrice <= 0.0 || side * (entryPrice - stopPrice) <= 0.0) return 0.0;
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double lots = 0.0;
   if(InpSizingMode == SIZING_FIXED)
   {
      if(!MathIsValidNumber(InpFixedLots) || !MathIsValidNumber(step) || step <= 0.0 ||
         minLot <= 0.0 || maxLot < minLot || InpFixedLots < minLot || InpFixedLots > maxLot ||
         MathAbs(InpFixedLots / step - MathRound(InpFixedLots / step)) > 1e-8) return 0.0;
      lots = InpFixedLots;
   }
   else
   {
      double perLot = 0.0;
      if(!RiskPerLot(side, entryPrice, stopPrice, perLot)) return 0.0;
      lots = RiskVolume(budget, perLot, minLot, maxLot, step);
      if(lots < minLot && InpAllowMinLotOverride && MathIsValidNumber(budget) && budget > 0.0 &&
         MathIsValidNumber(minLot) && MathIsValidNumber(maxLot) && MathIsValidNumber(step) &&
         minLot > 0.0 && maxLot >= minLot && step > 0.0)
      {
         lots = minLot;
         PrintFormat("[FVG_DUO] RISK_MINIMUM: broker minimum exceeds intended risk; lots=%.8f estimatedRisk=%.2f intendedRisk=%.2f %s",
                     lots, lots * perLot, budget, AccountInfoString(ACCOUNT_CURRENCY));
      }
   }
   if(lots < minLot && !InpAllowMinLotOverride && InpSizingMode != SIZING_FIXED)
   {
      PrintFormat("[FVG_DUO] RISK_BELOW_MIN_LOT: budget %.2f is under the broker minimum %.8f lots; entry skipped",
                  budget, minLot);
      return 0.0;
   }
   double margin = 0.0;
   if(lots <= 0.0 || !OrderCalcMargin(side > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                                     _Symbol, lots, entryPrice, margin) ||
      !MathIsValidNumber(margin) || margin < 0.0 ||
      margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE)) return 0.0;
   return lots;
}

bool MergeReady(double held, double allowed, double oldSL, double oldTP,
                double newSL, double newTP, bool settled)
{
   return settled && MathIsValidNumber(held) && MathIsValidNumber(allowed) &&
          MathIsValidNumber(oldSL) && MathIsValidNumber(oldTP) &&
          MathIsValidNumber(newSL) && MathIsValidNumber(newTP) &&
          held > 0.0 && allowed > 0.0 && held <= allowed + 1e-8 && oldSL > 0.0 &&
          oldTP >= 0.0 && newSL > 0.0 && newTP >= 0.0;
}

//+------------------------------------------------------------------+
//| Deal evidence                                                     |
//|                                                                   |
//| A CTrade return value is a request outcome, not proof of a fill.   |
//| Ownership, sizing and the journal are all read back from the deals |
//| the server actually booked for the position.                       |
//+------------------------------------------------------------------+
int DealEvidence(ulong positionId, double &inVol, double &outVol,
                 double &outPrice, datetime &outTime, string &reason)
{
   inVol = 0.0; outVol = 0.0; outPrice = 0.0; outTime = 0; reason = "";
   if(positionId == 0) return 0;
   if(!HistorySelectByPosition(positionId)) return 0;

   int seen = 0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong t = HistoryDealGetTicket(i);
      if(t == 0) continue;
      double v = HistoryDealGetDouble(t, DEAL_VOLUME);
      if(v <= 0.0) continue;

      long entry = HistoryDealGetInteger(t, DEAL_ENTRY);
      if(entry == DEAL_ENTRY_IN)
      {
         inVol += v;
         seen++;
      }
      else if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
      {
         outVol   += v;
         outPrice  = HistoryDealGetDouble(t, DEAL_PRICE);
         outTime   = (datetime)HistoryDealGetInteger(t, DEAL_TIME);
         long r    = HistoryDealGetInteger(t, DEAL_REASON);
         reason    = (r == DEAL_REASON_TP) ? "TARGET"
                   : (r == DEAL_REASON_SL) ? "STOP" : "";
         seen++;
      }
   }
   return seen;
}

// Any exposure carrying our magic on this symbol. A dropped or late send result
// leaves this true while ownedActive is still false, so it is the guard against
// opening a second position on the same signal.
bool OwnedExposureExists()
{
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong t = PositionGetTicket(i);
      if(t <= 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)InpMagic) continue;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Reconcile and recover owned position after restart                |
//+------------------------------------------------------------------+
void ReconcileOwnedPosition()
{
   ulong  prevTicket = ownedTicket;
   ulong  prevPosId  = ownedPositionId;
   string prevSource = ownedSource;
   double prevSignal = ownedSignalEntry;

   ownedActive = false;
   ownedTicket = 0;
   ownedPositionId = 0;
   ownedVolume = 0.0;

   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)InpMagic) continue;

      ownedTicket     = ticket;
      ownedPositionId = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      long type       = PositionGetInteger(POSITION_TYPE);
      ownedSide       = (type == POSITION_TYPE_BUY) ? 1 : -1;
      ownedEntryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      ownedVolume     = PositionGetDouble(POSITION_VOLUME);
      ownedStopPrice  = PositionGetDouble(POSITION_SL);
      ownedTargetPrice= PositionGetDouble(POSITION_TP);
      ownedEntryTime  = (datetime)PositionGetInteger(POSITION_TIME);
      string comment  = PositionGetString(POSITION_COMMENT);

      if(StringFind(comment, "MERGED") >= 0)      ownedSource = "MERGED";
      else if(StringFind(comment, "TREND") >= 0)   ownedSource = "TREND";
      else                                         ownedSource = "OD";

      // The broker may retain the original FVG_TREND comment after a merge.
      // The terminal-global marker survives EA and terminal restarts.
      if(IsPersistedMergedPosition(ownedPositionId) ||
         (ticket == prevTicket && prevSource == "MERGED"))
         ownedSource = "MERGED";

      // Signal geometry is unslipped, so it must not be replaced by the
      // broker fill on a reconcile.
      ownedSignalEntry = (ticket == prevTicket && prevSignal > 0.0)
                         ? prevSignal : ownedEntryPrice;
      ownedActive = true;
      return;
   }

   // Nothing open: if we were tracking a position, the broker took it out.
   if(prevPosId != 0)
   {
      double   inVol = 0.0, outVol = 0.0, outPrice = 0.0;
      datetime when = 0;
      string   reason = "";
      DealEvidence(prevPosId, inVol, outVol, outPrice, when, reason);

      if(outVol > 0.0)
      {
         if(reason == "") reason = "STOP";
         JournalClose(prevPosId, when, outPrice, reason);
      }
      else
      {
         // No exit deal is visible yet: journal what the server reported rather
         // than inventing a fill and a reason for a position we cannot see.
         PrintFormat("[FVG_DUO] Exit unconfirmed for pos=%I64u (no out deal yet)", prevPosId);
         JournalClose(prevPosId, TimeCurrent(), 0.0, "UNCONFIRMED");
      }

      ClearPersistedMergedPosition(prevPosId);
      ownedVolume      = 0.0;
      ownedSignalEntry = 0.0;
      ownedSource = "";
   }
}

//+------------------------------------------------------------------+
//| SEND MARKET ORDER                                                 |
//+------------------------------------------------------------------+
bool ExecuteEntry(int side, double signalEntry, double sl, double tp, string source)
{
   if(side == 0) return false;
   if(ownedActive) return false;

   // A previous send can fill while its result is lost (requote, timeout,
   // restart). Adopt that exposure instead of opening a second one.
   if(OwnedExposureExists())
   {
      ReconcileOwnedPosition();
      PrintFormat("[FVG_DUO] Entry suppressed: existing magic exposure adopted (src=%s)", ownedSource);
      return false;
   }

   extTrade.SetExpertMagicNumber(InpMagic);
   extTrade.SetDeviationInPoints(InpDeviation);

   // Snap the protective levels onto the live grid; the model geometry in the
   // journal stays exactly as the strategy computed it.
   double slSend = (sl > 0.0) ? GridPrice(sl) : 0.0;
   double tpSend = (tp > 0.0) ? GridPrice(tp) : 0.0;

   double refPx = (side > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                             : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double minD  = MinStopDistance();
   if(minD > 0.0 && refPx > 0.0)
   {
      if(slSend > 0.0 && MathAbs(refPx - slSend) < minD)
      {
         slSend = GridPrice((side > 0) ? refPx - minD : refPx + minD);
         PrintFormat("[FVG_DUO] SL below broker stop level, widened to %.5f (level=%.5f)", slSend, minD);
      }
      if(tpSend > 0.0 && MathAbs(tpSend - refPx) < minD)
      {
         tpSend = GridPrice((side > 0) ? refPx + minD : refPx - minD);
         PrintFormat("[FVG_DUO] TP below broker stop level, widened to %.5f (level=%.5f)", tpSend, minD);
      }
   }

   // Size from the executable quote and the stop the broker will actually hold,
   // not from the model entry: gap and stop-level widening both change real risk.
   double budget = TargetRiskCash();
   double lots = CalculateLotSize(side, refPx, slSend, budget);
   if(lots <= 0.0)
   {
      PrintFormat("[FVG_DUO] Entry skipped: sizing returned %.2f lots (quote=%.2f stop=%.2f budget=%.2f)",
                  lots, refPx, slSend, budget);
      return false;
   }
   g_dashLots    = lots;
   g_dashRiskBudget = budget;
   string comment = "FVG_" + source;

   bool res = false;
   if(side > 0)
      res = extTrade.Buy(lots, _Symbol, 0.0, slSend, tpSend, comment);
   else
      res = extTrade.Sell(lots, _Symbol, 0.0, slSend, tpSend, comment);

   if(!res)
   {
      PrintFormat("[FVG_DUO] Order failed retcode=%u (%s)",
                  extTrade.ResultRetcode(), extTrade.ResultRetcodeDescription());
      return false;
   }

   ulong ticket = extTrade.ResultOrder();
   double fill  = extTrade.ResultPrice();
   datetime when = TimeCurrent();

   // Resolve the position identifier created by this fill.
   ulong posId = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t <= 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)InpMagic) continue;
      if(PositionGetInteger(POSITION_TIME) > (long)when) continue;
      posId = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      break;
   }
   if(posId == 0) posId = ticket;   // hedging: position id == opening order ticket

   // The accepted request is not the fill. Take the volume and price the
   // server booked, so sizing, the journal and the risk cap all describe the
   // position that actually exists.
   double inVol = 0.0, outVol = 0.0, outPrice = 0.0, filled = 0.0;
   datetime outTime = 0;
   string   evReason = "";
   DealEvidence(posId, inVol, outVol, outPrice, outTime, evReason);
   if(inVol > 0.0)
      filled = inVol - outVol;
   else if(PositionSelectByTicket(ticket))
   {
      // History lag: the open position is still authoritative server state.
      filled = PositionGetDouble(POSITION_VOLUME);
      fill   = PositionGetDouble(POSITION_PRICE_OPEN);
   }

   if(filled <= 0.0)
   {
      PrintFormat("[FVG_DUO] ENTRY unconfirmed ticket=%I64u pos=%I64u retcode=%u (%s): ownership not claimed",
                  ticket, posId, extTrade.ResultRetcode(), extTrade.ResultRetcodeDescription());
      return false;
   }

   ownedActive      = true;
   ownedTicket      = ticket;
   ownedSide        = side;
   ownedSource      = source;
   ownedSignalEntry = signalEntry;
   ownedEntryPrice  = fill;
   ownedVolume      = filled;
   ownedStopPrice   = slSend;
   ownedTargetPrice = tpSend;
   ownedEntryTime   = when;

   ownedPositionId = posId;

   JournalAdd(posId, source, (side > 0 ? "LONG" : "SHORT"),
              when, signalEntry, fill, sl, tp, filled);
   if(MathAbs(filled - lots) > SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP) * 0.5)
      PrintFormat("[FVG_DUO] ENTRY volume differs from request: requested=%.2f filled=%.2f", lots, filled);
   PrintFormat("[FVG_DUO] ENTRY ticket=%I64u pos=%I64u src=%s side=%s model=%.2f fill=%.2f sl=%.2f tp=%.2f lots=%.2f",
               ticket, posId, source, (side > 0 ? "LONG" : "SHORT"), signalEntry, fill, slSend, tpSend, filled);
   return true;
}

//+------------------------------------------------------------------+
//| CLOSE OWNED POSITION                                              |
//+------------------------------------------------------------------+
bool ExecuteClose(string reason)
{
   if(!ownedActive || ownedTicket == 0) return true;

   ulong posId  = ownedPositionId;
   ulong ticket = ownedTicket;

   extTrade.SetExpertMagicNumber(InpMagic);
   extTrade.SetDeviationInPoints(InpDeviation);

   g_pendingCloseReason = reason;
   bool res = extTrade.PositionClose(ticket);
   string pending = g_pendingCloseReason;
   g_pendingCloseReason = "";

   if(!res)
   {
      PrintFormat("[FVG_DUO] PositionClose failed ticket=%I64u retcode=%u (%s)",
                  ticket, extTrade.ResultRetcode(), extTrade.ResultRetcodeDescription());
      return false;
   }

   // The retcode only reports the request. Ownership is released only when the
   // server no longer lists the position; anything else stays tracked and is
   // retried on the next bar.
   if(PositionSelectByTicket(ticket))
   {
      PrintFormat("[FVG_DUO] CLOSE unconfirmed ticket=%I64u still open vol=%.2f (ownership retained)",
                  ticket, PositionGetDouble(POSITION_VOLUME));
      ownedVolume = PositionGetDouble(POSITION_VOLUME);
      return false;
   }

   double   inVol = 0.0, outVol = 0.0, outPrice = 0.0;
   datetime dealTime = 0;
   string   evReason = "";
   DealEvidence(posId, inVol, outVol, outPrice, dealTime, evReason);

   datetime when  = (dealTime > 0) ? dealTime : TimeCurrent();
   double   price = (outPrice > 0.0) ? outPrice : extTrade.ResultPrice();
   if(outVol + SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP) * 0.5 < ownedVolume)
      PrintFormat("[FVG_DUO] CLOSE volume mismatch pos=%I64u tracked=%.2f out=%.2f (recording booked volume)",
                  posId, ownedVolume, outVol);

   JournalClose(posId, when, price, pending);

   PrintFormat("[FVG_DUO] CLOSE ticket=%I64u reason=%s price=%.2f out=%.2f", ticket, pending, price, outVol);
   ClearPersistedMergedPosition(posId);
   ownedActive = false;
   ownedTicket = 0;
   ownedPositionId = 0;
   ownedVolume = 0.0;
   ownedSignalEntry = 0.0;
   ownedSource = "";
   return true;
}

//+------------------------------------------------------------------+
//| MODIFY STOP / TARGET (MERGE folds the trend position into OD)     |
//+------------------------------------------------------------------+
// Largest volume that keeps cash risk at stopPrice inside the configured cap.
// Zero means the volume cannot be evaluated or is below the broker minimum.
double AllowedVolumeAtStop(int side, double entry, double stopPrice, double budget)
{
   double perLot = 0.0;
   if(!RiskPerLot(side, entry, stopPrice, perLot)) return 0.0;
   return RiskVolume(budget, perLot,
                     SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN),
                     SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX),
                     SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP));
}

// A merge re-anchors the stop to a wider level than the volume was sized at, so
// the held volume is cut until the new stop is back inside the risk cap. The old
// attached stop stays live until the position itself reports the reduced volume,
// so a rejected or partial trim never leaves widened risk on the wrong side of
// the cap. Returns true only when the held volume is confirmed inside the cap.
bool TrimToRiskCap(double stopPrice)
{
   if(InpSizingMode == SIZING_FIXED) return true;
   if(!PositionSelectByTicket(ownedTicket)) return false;

   double held  = PositionGetDouble(POSITION_VOLUME);
   double entry = PositionGetDouble(POSITION_PRICE_OPEN);
   double step  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(held <= 0.0 || step <= 0.0) return false;

   double want = AllowedVolumeAtStop(ownedSide, entry, stopPrice, TargetRiskCash());
   if(want >= held) return want > 0.0;

   double keep   = MathFloor(want / step + 1e-10) * step;
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(keep < minLot)
   {
      PrintFormat("[FVG_DUO] Merge cap leaves %.2f lots below minimum %.2f: closing owned position instead.",
                  keep, minLot);
      ExecuteClose("MERGE_CAP");
      return false;
   }

   double cut = held - keep;
   if(!extTrade.PositionClosePartial(ownedTicket, cut))
   {
      PrintFormat("[FVG_DUO] Merge trim failed ticket=%I64u cut=%.2f retcode=%u (%s)",
                  ownedTicket, cut, extTrade.ResultRetcode(), extTrade.ResultRetcodeDescription());
      return false;
   }
   if(!PositionSelectByTicket(ownedTicket))
   {
      // The broker closed the remainder instead of trimming it: nothing is left
      // to re-anchor, so ownership is dropped with the old stop recorded.
      PrintFormat("[FVG_DUO] Merge trim closed the position outright ticket=%I64u cut=%.2f", ownedTicket, cut);
      ownedVolume = 0.0;
      ExecuteClose("MERGE_CAP");
      return false;
   }

   double nowHeld = PositionGetDouble(POSITION_VOLUME);
   ownedVolume = nowHeld;
   if(nowHeld > keep + step * 0.5)
   {
      // Partial or unconfirmed reduction: keep the old stop and retry next tick.
      PrintFormat("[FVG_DUO] Merge trim unconfirmed ticket=%I64u want=%.2f now=%.2f (old stop retained)",
                  ownedTicket, keep, nowHeld);
      return false;
   }

   JournalLots(ownedPositionId, nowHeld);
   PrintFormat("[FVG_DUO] Merge trim confirmed ticket=%I64u held=%.2f cut=%.2f keep=%.2f newStop=%.2f",
               ownedTicket, held, cut, nowHeld, stopPrice);
   return MergeReady(nowHeld, keep, ownedStopPrice, ownedTargetPrice,
                     stopPrice, ownedTargetPrice, true);
}

bool ExecuteModify(double newSL, double newTP, string newComment)
{
   if(!ownedActive || ownedTicket == 0) return false;

   extTrade.SetExpertMagicNumber(InpMagic);
   double slSend = (newSL > 0.0) ? GridPrice(newSL) : 0.0;
   double tpSend = (newTP > 0.0) ? GridPrice(newTP) : 0.0;

   // Reduce first, then move the stop. Widening before the reduction settles would
   // put the full held volume behind the wider stop and breach the risk cap.
   if(newComment == "MERGED" && !TrimToRiskCap(slSend))
   {
      PrintFormat("[FVG_DUO] MERGE deferred ticket=%I64u: reduction not confirmed, old stop %.2f retained.",
                  ownedTicket, ownedStopPrice);
      return false;
   }

   bool res = extTrade.PositionModify(ownedTicket, slSend, tpSend);
   if(res && PositionSelectByTicket(ownedTicket))
   {
      double liveSL = PositionGetDouble(POSITION_SL);
      double liveTP = PositionGetDouble(POSITION_TP);
      if(MathAbs(liveSL - slSend) > SymTick() * 0.5 ||
         (tpSend > 0.0 && MathAbs(liveTP - tpSend) > SymTick() * 0.5))
      {
         // The server kept the previous levels: record what it holds, not what
         // was requested, so the next decision is made on real protection.
         ownedStopPrice   = liveSL;
         ownedTargetPrice = liveTP;
         PrintFormat("[FVG_DUO] MODIFY unconfirmed ticket=%I64u want sl=%.2f tp=%.2f live sl=%.2f tp=%.2f",
                     ownedTicket, slSend, tpSend, liveSL, liveTP);
         return false;
      }
      ownedStopPrice   = slSend;
      ownedTargetPrice = tpSend;
      ownedVolume      = PositionGetDouble(POSITION_VOLUME);
      ownedSource      = newComment;
      if(newComment == "MERGED")
         PersistMergedPosition(ownedPositionId);
      else
         ClearPersistedMergedPosition(ownedPositionId);
      JournalUpdate(ownedPositionId, newComment, newSL, newTP);
      PrintFormat("[FVG_DUO] MODIFY ticket=%I64u sl=%.2f tp=%.2f status=%s",
                  ownedTicket, slSend, tpSend, newComment);
      return true;
   }

   PrintFormat("[FVG_DUO] PositionModify failed ticket=%I64u retcode=%u (%s)",
               ownedTicket, extTrade.ResultRetcode(), extTrade.ResultRetcodeDescription());
   return false;
}

#endif // FVG_EXECUTION_RUNTIME
