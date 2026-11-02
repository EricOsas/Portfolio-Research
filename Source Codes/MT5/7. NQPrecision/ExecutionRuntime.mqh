
 // Commission is learned only from a fully closed, owned broker position.
 // Tester fees are simulation settings, never evidence of a broker schedule.
 double NQPEntryChargesPerLot(ulong positionId)
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
 double NQPCommissionEstimate()
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
          PrintFormat("NQP_COMMISSION_SOURCE broker completedPosition=%I64u roundTripPerLot=%.8f",candidates[j],rate);
       known=true;observed=rate;break; // Zero is a valid observed schedule.
    }
    return known ? observed : CommissionRTPerLot;
 }
 bool NQPCostCoveredPrice(int side,double entry,double commission,double &price)
 {
    double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE),cash=0,slip=0;
    ENUM_ORDER_TYPE type=side==1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    if(tick<=0 || !OrderCalcProfit(type,_Symbol,1.0,entry,entry+side*tick,cash) ||
       !OrderCalcProfit(type,_Symbol,1.0,entry,entry-side*SlipPrice,slip) ||
       cash<=0 || !MathIsValidNumber(cash) || commission<0 || !MathIsValidNumber(commission)) return false;
    double raw=entry+side*(commission+MathAbs(slip))*tick/cash;
    price=NormalizeDouble((side==1 ? MathCeil(raw/tick-1e-9) : MathFloor(raw/tick+1e-9))*tick,_Digits);
    return MathIsValidNumber(price);
 }

#ifndef NQP_STRATEGY_TRADE_EXPORT
#define NQP_STRATEGY_TRADE_EXPORT
datetime NQPServerUTC(datetime server)
{
   return NQPClockUTC(server);
}
bool NQPExportTrades(string path)
{
   datetime begin=0,end=TimeCurrent()+1;
   string stage="TESTER";
   if(!HistorySelect(begin,end-1)) return false;
   int f=FileOpen(path,FILE_COMMON|FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(f==INVALID_HANDLE) return false;
   FileWrite(f,"model","variant","feed","stage","run_id","position_id","exit_deal","entry_server","exit_server","entry_utc","exit_utc","central_date","side","volume","entry_price","exit_price","original_sl","original_tp","broker_net","modeled_cost","adjusted_net","risk_budget_cash","net_over_budget","real_entry_ordinal","model_attempt","exit_reason");
   string variant=SyntheticFirst ? "synthetic_first" : Management==M1RStep ? "M1_Rstep_TP"+DoubleToString(TargetR,1) : "nqp_fixed_bracket";
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
         datetime d=NQPDay(t);if(d!=previousDay){ordinal=0;previousDay=d;}ordinal++;
      }
      else if(direction==DEAL_ENTRY_OUT || direction==DEAL_ENTRY_OUT_BY)
      {
         if(entryVolume<=0 || HistoryDealGetInteger(deal,DEAL_POSITION_ID)!=positionId || qty>entryVolume+1e-8 || NQPDay(t)!=NQPDay(entryTime)){ok=false;break;}
         double broker=HistoryDealGetDouble(deal,DEAL_PROFIT)+HistoryDealGetDouble(deal,DEAL_COMMISSION)+HistoryDealGetDouble(deal,DEAL_SWAP)+HistoryDealGetDouble(deal,DEAL_FEE);
         double entryCharge=NQPEntryChargesPerLot((ulong)positionId)*qty;
         // The history helper changes selection: restore the full export window.
         HistorySelect(begin,end-1);
         double exitCharge=HistoryDealGetDouble(deal,DEAL_COMMISSION)+HistoryDealGetDouble(deal,DEAL_FEE);
         double nativeCommission=MathMax(0,entryCharge-exitCharge);
         double cost=costLot*qty-MathMin(CommissionRTPerLot*qty,nativeCommission),net=broker-entryCharge-cost;
         FileWrite(f,NQPOutputFamily,variant,_Symbol,stage,RunId,positionId,deal,
            TimeToString(entryTime,TIME_DATE|TIME_SECONDS),TimeToString(t,TIME_DATE|TIME_SECONDS),
            TimeToString(NQPServerUTC(entryTime),TIME_DATE|TIME_SECONDS),TimeToString(NQPServerUTC(t),TIME_DATE|TIME_SECONDS),
            TimeToString(NQPDay(t),TIME_DATE),side==1 ? "LONG" : "SHORT",qty,entryPrice,price,sl,tp,
            broker,cost,net,UseFixedSize ? 0 : RiskCash,UseFixedSize ? 0 : net/RiskCash,ordinal,ordinal+(SyntheticFirst ? 1 : 0),(int)HistoryDealGetInteger(deal,DEAL_REASON));
         entryVolume-=qty;exits++;reconstructed+=net;
      }
   }
   FileClose(f);
   double expected=TesterStatistics(STAT_PROFIT)-totalCost;
   ok=ok && entryVolume<1e-8 && exits==(int)TesterStatistics(STAT_TRADES) && MathAbs(reconstructed-expected)<.01;
   PrintFormat("NQP_TRADE_EXPORT_%s rows=%d net=%.2f expected=%.2f",ok ? "PASS" : "FAIL",exits,reconstructed,expected);
   return ok;
}
#endif

#ifndef NQP_STRATEGY_RUNTIME
#define NQP_STRATEGY_RUNTIME
// Owned-position lifecycle for production EAs and archived research fixtures.
bool runtimeBlocked=false;
bool runtimeRecoveryHold=false;
bool runtimeEntryPending=false;
datetime runtimeIntentTime=0;
ulong runtimeIntentNonce=0;
double runtimeIntentStop=0,runtimeIntentTarget=0;
bool NQPRecoveryIntentMatches(bool pending,datetime sent,datetime filled,double plannedStop,double plannedTarget,double brokerStop,double brokerTarget,double tick)
{
   return pending && sent>0 && filled>=sent && filled<=sent+60 && tick>0
      && plannedStop>0 && plannedTarget>0 && MathIsValidNumber(plannedStop) && MathIsValidNumber(plannedTarget)
      && MathAbs(plannedStop-brokerStop)<tick*1e-6 && MathAbs(plannedTarget-brokerTarget)<tick*1e-6;
}
bool NQPRecoveryPositionMatches(double hi,double lo,ulong actual,datetime savedTime,datetime actualTime,double risk)
{
   return MathIsValidNumber(hi) && MathIsValidNumber(lo) && hi>=0 && hi<=4294967295.0 && lo>=0 && lo<=4294967295.0
      && hi==MathFloor(hi) && lo==MathFloor(lo) && actual>0 && (((ulong)hi<<32)|(ulong)lo)==actual
      && savedTime>0 && savedTime==actualTime && MathIsValidNumber(risk) && risk>0;
}
bool runtimeJournalOK=true;
bool runtimeJournalTesting=false;
long runtimeAccountId=0;
long runtimeAccountMode=0;
string runtimeAccountServer="";
string runtimeAccountKey="";
int runtimeLockFile=INVALID_HANDLE;
datetime runtimeInitialSource=0;
bool runtimeHistoryReady=false;
string NQPStateKey(){return runtimeJournalTesting ? "NQP.fixture."+RunId+"." : runtimeAccountKey;}
// Pre-rename builds locked "VaultBreakLocks/<key>lock". Honour that lock so an old and a new build cannot trade the same account.
bool NQPLegacyLockHeld()
{
   string legacy="VaultBreakLocks/"+NQPStateKey()+"lock";
   if(!FileIsExist(legacy,FILE_COMMON)) return false;
   int h=FileOpen(legacy,FILE_COMMON|FILE_BIN|FILE_READ|FILE_WRITE);
   if(h==INVALID_HANDLE) return true;
   FileClose(h);
   return false;
}
// Order/position comments: "NQP#" is written now; "VB#" is still recognised for orders sent by the pre-rename build.
bool NQPCommentMatches(const string comment,const long nonce)
{
   string id=IntegerToString(nonce);
   return comment=="NQP#"+id || comment=="VB#"+id;
}
bool nqBrokerRestriction=false;
bool nqRecoveryEvidencePending=false;
ulong nqRecoveryNextTick=0;
bool NQRestrictionResult(uint ret,string comment)
{
   string text=comment;StringToLower(text);
   return ret==10017 || ret==10026 || ret==10027 || ret==10042 || ret==10043 || ret==10044
      || StringFind(text,"liquidation")>=0 || StringFind(text,"liquidate only")>=0
      || StringFind(text,"account restricted")>=0 || StringFind(text,"account is restricted")>=0
      || StringFind(text,"permission")>=0 || StringFind(text,"not authorized")>=0
      || StringFind(text,"trading disabled")>=0 || StringFind(text,"trading is disabled")>=0;
}
bool NQBrokerRestricted()
{
   if(!MQLInfoInteger(MQL_TESTER))
   {
      string key=NQPStateKey();
      if(key=="")return true;
      if(GlobalVariableCheck(key+"restricted") && GlobalVariableGet(key+"restricted")!=0)nqBrokerRestriction=true;
   }
   if(nqBrokerRestriction)runtimeBlocked=true;
   return nqBrokerRestriction;
}
void NQObserveBrokerResult(uint ret,string comment)
{
   if(!NQRestrictionResult(ret,comment))return;
   nqBrokerRestriction=true;runtimeBlocked=true;
   // Independent of the daily checkpoint: a reset cannot clear the broker pause.
   if(!MQLInfoInteger(MQL_TESTER))
   {
      if(NQPStateKey()=="" || GlobalVariableSet(NQPStateKey()+"restricted",(double)(ret>0 ? ret : 1))==0)
      {runtimeRecoveryHold=true;Print("NQ RESTRICTION JOURNAL FAILED: requests paused; broker protection retained");return;}
      GlobalVariablesFlush();
   }
   PrintFormat("NQ BROKER RESTRICTED ret=%u %s; requests paused, existing broker protection retained",ret,comment);
}

bool NQRestoreTimeContract(string key)
{
   string fields[]={"nqtimevalid","nqtimeenabled","nqminutes","nqdeadline"};
   for(int i=0;i<ArraySize(fields);i++)if(!GlobalVariableCheck(key+fields[i]))return false;
   double enabled=GlobalVariableGet(key+"nqtimeenabled"),minutes=GlobalVariableGet(key+"nqminutes"),deadline=GlobalVariableGet(key+"nqdeadline");
   if(GlobalVariableGet(key+"nqtimevalid")!=1 || (enabled!=0 && enabled!=1)
      || !MathIsValidNumber(minutes) || minutes<1 || minutes>1440 || minutes!=MathFloor(minutes)
      || !MathIsValidNumber(deadline) || deadline<0 || deadline!=MathFloor(deadline))return false;
   nqTimeContractKnown=true;nqTimeEnabled=enabled==1;nqTimeMinutes=(int)minutes;nqTradeDeadlineMsc=(long)deadline;
   return true;
}
bool NQSelectedOwned(ulong ticket)
{
   if(!PositionSelectByTicket(ticket) || PositionGetString(POSITION_SYMBOL)!=_Symbol
      || (ulong)PositionGetInteger(POSITION_MAGIC)!=Magic)return false;
   if(MQLInfoInteger(MQL_TESTER))return true;
   return NQPRuntimeAccountContextValid() && !runtimeRecoveryHold && nqVerifiedPositionId>0
      && (ulong)PositionGetInteger(POSITION_IDENTIFIER)==nqVerifiedPositionId
      && PositionGetInteger(POSITION_TIME)==nqVerifiedOpenTime;
}
bool NQBindEntryReceipt()
{
   if(!OwnPosition())return false;
   ulong position=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
   long opened=PositionGetInteger(POSITION_TIME);
   ulong receipt=trade.ResultDeal(),order=trade.ResultOrder();bool verified=false;
   if(receipt>0 && HistoryDealSelect(receipt))
      verified=HistoryDealGetString(receipt,DEAL_SYMBOL)==_Symbol
         && (ulong)HistoryDealGetInteger(receipt,DEAL_MAGIC)==Magic
         && HistoryDealGetInteger(receipt,DEAL_ENTRY)==DEAL_ENTRY_IN
         && (ulong)HistoryDealGetInteger(receipt,DEAL_POSITION_ID)==position;
   if(!verified && order>0 && HistoryOrderSelect(order))
      verified=HistoryOrderGetString(order,ORDER_SYMBOL)==_Symbol
         && (ulong)HistoryOrderGetInteger(order,ORDER_MAGIC)==Magic
         && (ulong)HistoryOrderGetInteger(order,ORDER_POSITION_ID)==position;
   if(!verified || position==0 || opened<=0)return false;
   nqVerifiedPositionId=position;nqVerifiedOpenTime=opened;return true;
}
string NQPRuntimeOwnershipKey(long login,string server,long mode,string symbol,ulong magic)
{
   string identity=StringFormat("%I64d|%s|%I64d|%s|%I64u",login,server,mode,symbol,magic);
   ulong hash=14695981039346656037;
   for(int i=0;i<StringLen(identity);i++){hash^=(ulong)StringGetCharacter(identity,i);hash*=1099511628211;}
   return "NQP."+StringFormat("%I64u",hash)+".";
}
void NQPStatePut(string k,double value)
{
   if(GlobalVariableSet(k,value)==0){runtimeJournalOK=false;runtimeBlocked=true;Print("NQP JOURNAL WRITE FAILED: entries blocked");}
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
   if(NQBrokerRestricted())return false;
   if(!NQSelectedOwned(ticket))return false;
   if(MQLInfoInteger(MQL_TESTER))return true;
   if(!TerminalInfoInteger(TERMINAL_CONNECTED) || !RecoveryCloseReconcile(stateKey) || runtimeCloseRejected || !PositionSelectByTicket(ticket))return false;
   if(PositionGetString(POSITION_SYMBOL)!=_Symbol || (ulong)PositionGetInteger(POSITION_MAGIC)!=Magic)return false;
   MqlTick quote;if(!SymbolInfoTick(_Symbol,quote) || quote.time_msc<=0)return false;
   ulong position=(ulong)PositionGetInteger(POSITION_IDENTIFIER);string k=stateKey+"close.";
   bool ok=RecoveryClosePut(k+"valid",-1); // Interrupted intent construction must also fail closed.
   ok=RecoveryClosePut(k+"hi",(double)(position>>32)) && ok;ok=RecoveryClosePut(k+"lo",(double)(position&0xffffffff)) && ok;
   ok=RecoveryClosePut(k+"qty",PositionGetDouble(POSITION_VOLUME)) && ok;
   ok=RecoveryClosePut(k+"time",(double)quote.time_msc) && ok;
   ok=RecoveryClosePut(k+"orderhi",0) && ok;ok=RecoveryClosePut(k+"orderlo",0) && ok;
   if(ok)ok=RecoveryClosePut(k+"valid",1);
   GlobalVariablesFlush();runtimeClosePending=true;return ok;
}
void RecoveryCloseResult(string stateKey,uint ret,ulong order)
{
   NQObserveBrokerResult(ret,"");
   if(NQBrokerRestricted())return; // Leave the intent pending; never retry a denied account blindly.
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
void NQPStateSave(int reserved=-1)
{
   if(runtimeRecoveryHold) return;
   if((MQLInfoInteger(MQL_TESTER) && !runtimeJournalTesting) || day==0) return;
   if(!runtimeJournalTesting && !NQPRuntimeAccountContextValid()) return;
   string k=NQPStateKey();
   runtimeJournalOK=true;
   NQPStatePut(k+"valid",0);
   NQPStatePut(k+"day",(double)day);
   NQPStatePut(k+"revision",NQPStateRevision);
   NQPStatePut(k+"entries",reserved>=0 ? reserved : entries);
   NQPStatePut(k+"signal",(double)lastSignal);
   NQPStatePut(k+"nqday",nqDecisionDay);
   NQPStatePut(k+"nqtimevalid",nqTimeContractKnown ? 1 : 0);
   NQPStatePut(k+"nqtimeenabled",nqTimeEnabled ? 1 : 0);
   NQPStatePut(k+"nqminutes",nqTimeMinutes);
   NQPStatePut(k+"nqdeadline",(double)nqTradeDeadlineMsc);
   NQPStatePut(k+"virtual",virtualActive ? 1 : 0);
   NQPStatePut(k+"vstart",(double)virtualStart);
   NQPStatePut(k+"vlast",(double)virtualLastBar);
   NQPStatePut(k+"vsl",virtualStop);NQPStatePut(k+"vtp",virtualTarget);
   NQPStatePut(k+"risk",initialRisk);NQPStatePut(k+"peak",barPeakR);
   NQPStatePut(k+"costlot",modelCostPerLot);
   NQPStatePut(k+"commlot",entryCommissionPerLot);
   NQPStatePut(k+"entrytime",(double)ownedEntryTime);
   ulong position=(!runtimeEntryPending && OwnPosition()) ? (ulong)PositionGetInteger(POSITION_IDENTIFIER) : 0;
   NQPStatePut(k+"poshi",(double)(position>>32));NQPStatePut(k+"poslo",(double)(position&0xffffffff));
   NQPStatePut(k+"pending",runtimeEntryPending ? 1 : 0);
   NQPStatePut(k+"intenttime",(double)runtimeIntentTime);NQPStatePut(k+"intentsl",runtimeIntentStop);NQPStatePut(k+"intenttp",runtimeIntentTarget);
   NQPStatePut(k+"intentnonce",(double)runtimeIntentNonce);
   NQPStatePut(k+"blocked",runtimeBlocked ? 1 : 0);
   NQPStatePut(k+"valid",runtimeJournalOK ? 1 : 0);GlobalVariablesFlush();
}
int NQPHistoryEntries(datetime now)
{
   if(!HistorySelect(NQPSessionTime(NQPDay(now)),now)) return -1;
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
int NQPRecoveredFundedEntries(int saved,int actual,bool legacySynthetic)
{
   // A legacy count included its synthetic first attempt. Keep any reserved
   // funded attempt even when broker history has not recorded an execution.
   return MathMax(actual,MathMax(0,saved-(legacySynthetic ? 1 : 0)));
}
bool NQPLegacyPositionRiskVerified()
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
void NQPStateRestore(datetime now)
{
   if(MQLInfoInteger(MQL_TESTER) && !runtimeJournalTesting) return;
   nqVerifiedPositionId=0;nqVerifiedOpenTime=0;
   RecoveryCloseReconcile(NQPStateKey());
   string k=NQPStateKey();int actual=NQPHistoryEntries(now);
   nqDecisionDay=GlobalVariableCheck(k+"nqday") ? (int)GlobalVariableGet(k+"nqday") : 0;
   nqTimeContractKnown=NQRestoreTimeContract(k);
   if(OwnPosition() && !nqTimeContractKnown)
   {runtimeBlocked=true;runtimeRecoveryHold=true;Note("RECOVERY_BLOCK","Original time-close contract missing; broker protection retained");return;}
   if(actual<0){nqRecoveryEvidencePending=true;runtimeBlocked=true;runtimeRecoveryHold=true;initialRisk=0;Note("RECOVERY_BLOCK","History unavailable; broker protection retained");return;}
   bool same=GlobalVariableCheck(k+"day") && (datetime)GlobalVariableGet(k+"day")==day;
   if(same)
   {
      string fields[]={"valid","entries","signal","virtual","vstart","vlast","vsl","vtp","risk","peak","costlot","entrytime","blocked"};
      for(int i=0;i<ArraySize(fields);i++)
         if(!GlobalVariableCheck(k+fields[i]))
         {runtimeBlocked=true;runtimeRecoveryHold=true;initialRisk=0;Note("RECOVERY_BLOCK","Missing journal field; broker protection retained");return;}
   }
   if(same && GlobalVariableGet(k+"valid")!=1)
   {runtimeBlocked=true;runtimeRecoveryHold=true;initialRisk=0;entries=1;Note("RECOVERY_BLOCK","Incomplete state commit; broker protection retained");return;}
   bool legacy=same && !GlobalVariableCheck(k+"revision");
   if(same && !legacy && GlobalVariableGet(k+"revision")!=NQPStateRevision)
   {runtimeBlocked=true;runtimeRecoveryHold=true;initialRisk=0;Note("RECOVERY_BLOCK","Unsupported journal revision; broker protection retained");return;}
   if(same)
   {
      entries=(int)GlobalVariableGet(k+"entries");
      lastSignal=(datetime)GlobalVariableGet(k+"signal");
      virtualActive=GlobalVariableGet(k+"virtual")==1;
      virtualStart=(datetime)GlobalVariableGet(k+"vstart");
      virtualLastBar=(datetime)GlobalVariableGet(k+"vlast");
      virtualStop=GlobalVariableGet(k+"vsl");virtualTarget=GlobalVariableGet(k+"vtp");
      initialRisk=GlobalVariableGet(k+"risk");barPeakR=GlobalVariableGet(k+"peak");
      modelCostPerLot=GlobalVariableGet(k+"costlot");
      entryCommissionPerLot=GlobalVariableCheck(k+"commlot") ? GlobalVariableGet(k+"commlot") : CommissionRTPerLot;
      ownedEntryTime=(datetime)GlobalVariableGet(k+"entrytime");
      runtimeBlocked=GlobalVariableGet(k+"blocked")==1;
      if(legacy)
      {
         int saved=entries;
         entries=NQPRecoveredFundedEntries(saved,actual,true);
         Note("RECOVERY_MODEL_MIGRATION",StringFormat("legacyAttempts=%d fundedAttempts=%d brokerEntries=%d blocked=%d",saved,entries,actual,runtimeBlocked));
      }
   }
   else
   {
      runtimeBlocked=false;entries=actual;
      if(SyntheticFirst && actual>0) entries++;
   }
   entries=MathMax(entries,actual+(SyntheticFirst && actual>0 ? 1 : 0));
   if(!SyntheticFirst)
   {
      // Retire only the synthetic state. Existing owned SL/TP, original risk,
      // entry time, costs and blocked status remain those of the actual trade.
      virtualActive=false;virtualStart=0;virtualLastBar=0;
      virtualStop=0;virtualTarget=0;nqpVirtualExitTime=0;
   }
   // Attachment cannot replay an old signal, even when no journal exists.
   lastSignal=MathMax(lastSignal,runtimeInitialSource);
   if(same && !OwnPosition() && GlobalVariableCheck(k+"pending") && GlobalVariableGet(k+"pending")==1 && actual<entries)
   {nqRecoveryEvidencePending=true;runtimeBlocked=true;runtimeRecoveryHold=true;Note("RECOVERY_BLOCK","Unresolved pre-send entry reservation; no replacement order");}
   if(OwnPosition())
   {
      ulong position=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
      if(same && !GlobalVariableCheck(k+"poshi") && !GlobalVariableCheck(k+"poslo") && NQPLegacyPositionRiskVerified())
      {NQPStateSave();Note("RECOVERY_LEGACY_VERIFIED","Entry-order stop verifies original risk; bound broker position identity");}
      bool pending=GlobalVariableCheck(k+"pending") && GlobalVariableGet(k+"pending")==1;
      if(same && pending && GlobalVariableCheck(k+"intentnonce") && NQPCommentMatches(PositionGetString(POSITION_COMMENT),(long)GlobalVariableGet(k+"intentnonce"))
         && GlobalVariableCheck(k+"intenttime") && GlobalVariableCheck(k+"intentsl") && GlobalVariableCheck(k+"intenttp")
         && NQPRecoveryIntentMatches(pending,(datetime)GlobalVariableGet(k+"intenttime"),(datetime)PositionGetInteger(POSITION_TIME),
            GlobalVariableGet(k+"intentsl"),GlobalVariableGet(k+"intenttp"),PositionGetDouble(POSITION_SL),PositionGetDouble(POSITION_TP),SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE)))
      {
         initialRisk=MathAbs(PositionGetDouble(POSITION_PRICE_OPEN)-PositionGetDouble(POSITION_SL));
         ownedEntryTime=(datetime)PositionGetInteger(POSITION_TIME);barPeakR=0;runtimeEntryPending=false;
         NQPStateSave();Note("RECOVERY_FILLED_INTENT","Broker bracket matches pre-send reservation");
      }
      bool bound=same && GlobalVariableCheck(k+"poshi") && GlobalVariableCheck(k+"poslo")
         && NQPRecoveryPositionMatches(GlobalVariableGet(k+"poshi"),GlobalVariableGet(k+"poslo"),position,
            ownedEntryTime,(datetime)PositionGetInteger(POSITION_TIME),initialRisk);
      if(!bound || !MathIsValidNumber(modelCostPerLot) || modelCostPerLot<0
         || !MathIsValidNumber(entryCommissionPerLot) || entryCommissionPerLot<0 || initialRisk<=0 || !MathIsValidNumber(initialRisk)
         || ownedEntryTime!=(datetime)PositionGetInteger(POSITION_TIME))
      {runtimeBlocked=true;runtimeRecoveryHold=true;initialRisk=0;Note("RECOVERY_BLOCK","Original-risk journal cannot identify owned position; broker protection retained");}
      else
      {nqVerifiedPositionId=position;nqVerifiedOpenTime=PositionGetInteger(POSITION_TIME);}
   }
   NQBrokerRestricted();
   NQPStateSave();
}
void NQReconcileState(datetime now)
{
   if(MQLInfoInteger(MQL_TESTER) || !runtimeHistoryReady || !NQPRuntimeAccountContextValid())return;
   if(nqRestored && !nqRecoveryEvidencePending)return;
   ulong clock=GetTickCount64();if(clock<nqRecoveryNextTick)return;
   nqRecoveryNextTick=clock+1000;
   // Retry only missing broker/history evidence; corruption/restrictions stay held.
   if(nqRecoveryEvidencePending)runtimeRecoveryHold=false;
   nqRecoveryEvidencePending=false;
   NQPStateRestore(now);nqRestored=true;
}
datetime NQPDate(int year,int month,int date)
{
   MqlDateTime p={};p.year=year;p.mon=month;p.day=date;return StructToTime(p);
}
int NQPWeekday(datetime t){MqlDateTime p;TimeToStruct(t,p);return p.day_of_week;}
datetime NQPNthSunday(int year,int month,int n)
{
   datetime first=NQPDate(year,month,1);
   return first+((7-NQPWeekday(first))%7+7*(n-1))*86400;
}
bool NQPBrokerClockValid()
{
   return NQPClockRefresh(MQLInfoInteger(MQL_TESTER) ? TimeCurrent() : TimeTradeServer());
}
bool NQPRuntimeInit()
{
   if(MQLInfoInteger(MQL_TESTER)) return true;
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {Print("NQP EA BLOCK: hedging account required for independent USTEC sleeves");return false;}
   if(Magic==0 || Management==CostCoveredBE || Management==ATRTrail)
   {Print("NQP EA BLOCK: invalid model identity or unsupported management rule");return false;}
   if(!NQPBrokerClockValid()) Print("NQP CLOCK_WAIT: requesting history for automatic weekly-opening clock detection");
   runtimeAccountId=AccountInfoInteger(ACCOUNT_LOGIN);
   runtimeAccountMode=AccountInfoInteger(ACCOUNT_TRADE_MODE);
   runtimeAccountServer=AccountInfoString(ACCOUNT_SERVER);
   runtimeAccountKey=NQPRuntimeOwnershipKey(runtimeAccountId,runtimeAccountServer,runtimeAccountMode,_Symbol,Magic);
   FolderCreate("NQPrecisionLocks",FILE_COMMON);
   if(NQPLegacyLockHeld()){Print("NQP EA BLOCK: duplicate instance or exclusive ownership lock unavailable");return false;}
   runtimeLockFile=FileOpen("NQPrecisionLocks/"+NQPStateKey()+"lock",FILE_COMMON|FILE_BIN|FILE_READ|FILE_WRITE);
   if(runtimeLockFile==INVALID_HANDLE){Print("NQP EA BLOCK: duplicate instance or exclusive ownership lock unavailable");return false;}
   // Indicator calculations/history load asynchronously after handles are created.
   // Keep the EA attached; the entry path waits without disabling recovery/timer protection.
   NQPRuntimeHistoryReady();
   EventSetTimer(1);
   return true;
}
bool NQPRuntimeHistoryReady()
{
   if(MQLInfoInteger(MQL_TESTER)) return true;
   static string runtimeWaitReason="";
   if(!TerminalInfoInteger(TERMINAL_CONNECTED) || (runtimeHistoryReady && !SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_SYNCHRONIZED)))
   {
      dayWaiting=true;
      string reason=TerminalInfoInteger(TERMINAL_CONNECTED) ? "M1_SYNC_WAIT" : "CONNECTION_WAIT";
      dataWaitReason=reason;
      if(runtimeWaitReason!=reason)
      {runtimeWaitReason=reason;Print("NQP DATA_WAIT: "+reason+"; new entries paused, broker protection retained");}
      return false;
   }
   if(!NQPBrokerClockValid()) return false;
   if(runtimeHistoryReady)
   {
      if(runtimeWaitReason!="")
      {
         runtimeWaitReason="";Print("NQP DATA_READY: connection and M1 synchronization restored");
         if(dataWaitReason=="M1_SYNC_WAIT" || dataWaitReason=="CONNECTION_WAIT" || dataWaitReason=="M1_HISTORY_WAIT")
         {lastSignal=MathMax(lastSignal,iTime(_Symbol,sourceTF,1));dayWaiting=false;dataWaitReason="";}
      }
      return true;
   }
   datetime source=iTime(_Symbol,sourceTF,1);
   MqlRates warm[];
   datetime from=NQPSessionTime(NQPDay(TimeCurrent()))-NQPWarmupLeadSeconds;
   int minutes=CopyRates(_Symbol,PERIOD_M1,from,TimeCurrent(),warm);
   bool ready=source>0 && minutes>0 && SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_SYNCHRONIZED)
      && nqIndicatorsReady;
   double atr[],adx[];
   double sessionMean=0;
   if(ready) ready=nqIndicatorsReady;
   
   if(!ready)
   {
      static bool announced=false;
      if(!announced){Print("NQP HISTORY_WAIT: loading M1/source/daily indicators; new entries blocked, protection active");announced=true;}
      return false;
   }
   runtimeInitialSource=source;
   lastSignal=MathMax(lastSignal,source); // Do not replay a candle that closed during attachment/loading.
   runtimeHistoryReady=true;
   runtimeWaitReason="";
   Print("NQP HISTORY_READY: data loaded; waiting for a fresh completed-bar signal");
   return true;
}
bool NQPRuntimeAccountAllowed(long mode,long margin,bool enabled)
{
   // The toggle controls new entries, not initialization/recovery or account type.
   return margin==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;
}
bool NQPRuntimeAccountContextValid()
{
   if(AccountInfoInteger(ACCOUNT_LOGIN)!=runtimeAccountId) return false;
   return AccountInfoInteger(ACCOUNT_TRADE_MODE)==runtimeAccountMode
      && AccountInfoString(ACCOUNT_SERVER)==runtimeAccountServer
      && AccountInfoInteger(ACCOUNT_MARGIN_MODE)==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;
}
bool NQPRuntimeSelfTest()
{
   if(!MQLInfoInteger(MQL_TESTER)) return false;
   string owner=NQPRuntimeOwnershipKey(1,"server-a",ACCOUNT_TRADE_MODE_DEMO,"USTEC",Magic);
   if(owner==NQPRuntimeOwnershipKey(1,"server-b",ACCOUNT_TRADE_MODE_DEMO,"USTEC",Magic)
      || owner==NQPRuntimeOwnershipKey(1,"server-a",ACCOUNT_TRADE_MODE_REAL,"USTEC",Magic)
      || owner==NQPRuntimeOwnershipKey(2,"server-a",ACCOUNT_TRADE_MODE_DEMO,"USTEC",Magic)
      || owner==NQPRuntimeOwnershipKey(1,"server-a",ACCOUNT_TRADE_MODE_DEMO,"USTEC",Magic+1)) return false;
   if(!NQPRuntimeAccountAllowed(ACCOUNT_TRADE_MODE_REAL,ACCOUNT_MARGIN_MODE_RETAIL_HEDGING,true)
      || !NQPRuntimeAccountAllowed(ACCOUNT_TRADE_MODE_DEMO,ACCOUNT_MARGIN_MODE_RETAIL_HEDGING,false)
      || NQPRuntimeAccountAllowed(ACCOUNT_TRADE_MODE_REAL,ACCOUNT_MARGIN_MODE_RETAIL_NETTING,true)) return false;
   datetime oldDay=day,oldSignal=lastSignal,oldStart=virtualStart,oldLast=virtualLastBar,oldEntry=ownedEntryTime;
   int oldEntries=entries;bool oldVirtual=virtualActive;
   double oldStop=virtualStop,oldTarget=virtualTarget,oldRisk=initialRisk,oldPeak=barPeakR;
   bool oldHold=runtimeRecoveryHold,oldPending=runtimeEntryPending;
   runtimeJournalTesting=true;runtimeBlocked=false;
   day=D'2022.01.24';entries=2;lastSignal=day+18*3600;
   virtualActive=SyntheticFirst;virtualStart=lastSignal;virtualLastBar=lastSignal;
   virtualStop=100;virtualTarget=210;initialRisk=70;barPeakR=1.5;ownedEntryTime=0;
   string key=NQPStateKey();NQPStateSave();
   entries=0;lastSignal=0;virtualActive=false;initialRisk=0;barPeakR=0;
   NQPStateRestore(day+19*3600);
   bool ok=runtimeJournalOK && !runtimeBlocked && entries==2 && lastSignal==day+18*3600
      && virtualActive==SyntheticFirst && (!SyntheticFirst || (virtualStop==100 && virtualTarget==210)) && initialRisk==70 && barPeakR==1.5;
   GlobalVariableSet(key+"valid",0);runtimeBlocked=false;NQPStateRestore(day+19*3600);
   ok=ok && runtimeBlocked;
   GlobalVariableSet(key+"valid",1);GlobalVariableDel(key+"risk");runtimeBlocked=false;NQPStateRestore(day+19*3600);
   ok=ok && runtimeBlocked;
   GlobalVariablesDeleteAll(key);
   FolderCreate("NQPrecisionLocks",FILE_COMMON);
   string lock="NQPrecisionLocks/fixture_"+RunId+".lock";
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
   Print(ok ? "NQP_RUNTIME_SELFTEST_PASS account guard / restart / corruption / exclusive ownership" : "NQP_RUNTIME_SELFTEST_FAILED");
   return ok;
}
// Visible-position/pending-order guard for the same account and contract. Same-direction sleeves coexist.
// This is a broker snapshot, not an atomic registry shared by other EAs/terminals.
bool NQIndexSymbol(string symbol)
{
   StringToUpper(symbol);
   string tags[]={"NASDAQ","USTEC","US100","US 100","NAS100","S&P","US500","US 500","US30","US 30","DOW","DAX","DE40","GER40"};
   for(int i=0;i<ArraySize(tags);i++)if(StringFind(symbol,tags[i])>=0)return true;
   return symbol=="NQ" || symbol=="MNQ" || symbol=="NNQ" || symbol=="ES" || symbol=="MES" || symbol=="YM" || symbol=="MYM";
}
bool NQOpposingExposure(const int side)
{
   bool index=BlockOpposingExposure && NQIndexSymbol(_Symbol);
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      if(PositionGetTicket(i)==0)continue;
      string symbol=PositionGetString(POSITION_SYMBOL);
      if(symbol!=_Symbol && !(index && NQIndexSymbol(symbol)))continue;
      if((PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY ? 1 : -1)!=side)return true;
   }
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(OrderGetTicket(i)==0)continue;
      string symbol=OrderGetString(ORDER_SYMBOL);
      if(symbol!=_Symbol && !(index && NQIndexSymbol(symbol)))continue;
      ENUM_ORDER_TYPE type=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      bool buy=type==ORDER_TYPE_BUY || type==ORDER_TYPE_BUY_LIMIT || type==ORDER_TYPE_BUY_STOP || type==ORDER_TYPE_BUY_STOP_LIMIT;
      bool sell=type==ORDER_TYPE_SELL || type==ORDER_TYPE_SELL_LIMIT || type==ORDER_TYPE_SELL_STOP || type==ORDER_TYPE_SELL_STOP_LIMIT;
      if((side>0 && sell) || (side<0 && buy))return true;
   }
   return false;
}
bool NQPRuntimeEntryAllowed(double entry,double stop,double target,double volume,int side)
{
   if(NQBrokerRestricted())return false;
   if(!EnableTrading) return false;
   if(MQLInfoInteger(MQL_TESTER)) return true;
   if(runtimeBlocked || !NQPRuntimeAccountContextValid() || !NQPBrokerClockValid() || !RecoveryCloseReconcile(NQPStateKey())) return false;
   if(!TerminalInfoInteger(TERMINAL_CONNECTED) || !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED) || !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)) return false;
   MqlTick q;if(!SymbolInfoTick(_Symbol,q) || TimeCurrent()-q.time>30) return false;
   double reference=side==1 ? q.bid : q.ask;
   double bound=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
   if(side*(reference-stop)<bound || side*(target-reference)<bound) return false;
   double margin=0;
   if(!OrderCalcMargin(side==1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,_Symbol,volume,entry,margin) || margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE)) return false;
   if(NQOpposingExposure(side)){Note("ENTRY_BLOCK","Opposing visible position or pending entry; independent same-direction sleeves allowed");return false;}
   // Reserve the attempt before submission: interrupted requests cannot be replayed.
   runtimeEntryPending=true;runtimeIntentTime=TimeCurrent();runtimeIntentNonce=(ulong)runtimeIntentTime*1000+GetTickCount()%1000;
   runtimeIntentStop=stop;runtimeIntentTarget=target;NQPStateSave(entries+1);
   return !runtimeBlocked && runtimeJournalOK;
}
void NQPRuntimeFilled(int side,double stop,double friction)
{
   if(MQLInfoInteger(MQL_TESTER)) return;
   if(!NQBindEntryReceipt())
   {nqRecoveryEvidencePending=true;runtimeBlocked=true;runtimeRecoveryHold=true;Note("FILL_BLOCK","Entry receipt cannot identify owned position; no guessed close or modification");return;}
   if(!OwnPosition()){runtimeBlocked=true;Note("FILL_BLOCK","Accepted request has no owned position");NQPStateSave();return;}
   double volume=PositionGetDouble(POSITION_VOLUME),price=PositionGetDouble(POSITION_PRICE_OPEN),loss=0;
   initialRisk=MathAbs(price-stop);ownedEntryTime=(datetime)PositionGetInteger(POSITION_TIME);
   long opened=PositionGetInteger(POSITION_TIME_MSC);
   if(nqTimeContractKnown && nqTimeEnabled && opened>0)nqTradeDeadlineMsc=opened+(long)nqTimeMinutes*60000;
   runtimeEntryPending=false;
   bool valid=PositionGetDouble(POSITION_SL)>0 && PositionGetDouble(POSITION_TP)>0
      && OrderCalcProfit(side==1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,_Symbol,volume,price,stop,loss)
      && (UseFixedSize || MathAbs(loss)+friction*volume<=RiskCash+0.01);
   if(!valid){runtimeBlocked=true;CloseOwned("FILLED_RISK_OR_PROTECTION");Note("FILL_BLOCK","Actual fill breached planned budget or protection");}
   NQPStateSave();
}
void OnTimer()
{
   if(MQLInfoInteger(MQL_TESTER)) return;
   if(!NQPRuntimeAccountContextValid()){NQPDraw();return;}
   RecoveryCloseReconcile(NQPStateKey());
   datetime now=TimeTradeServer();
   if(OwnPosition() && (PositionGetDouble(POSITION_SL)<=0 || PositionGetDouble(POSITION_TP)<=0))
   {runtimeBlocked=true;CloseOwned("PROTECTION_MISSING");NQPStateSave();}
   NQPRuntimeCutoffCheck(now);
   NQPRuntimeHistoryReady();
   NQReconcileState(now);
   NQPRefreshLiveVisuals(now);
   NQPDraw();
}
void NQPRuntimeCutoffCheck(datetime now)
{NQManageTimeClose(now);}
#ifdef NQP_LIFECYCLE_PROBE
bool nqvLifecycleDone=false;
bool NQPNativeLifecycleProbe()
{
   if(!MQLInfoInteger(MQL_TESTER)) return false;
   if(nqvLifecycleDone || NQPMinute(TimeCurrent())<600 || NQPMinute(TimeCurrent())>=870) return false;
   nqvLifecycleDone=true;bool ok=AccountInfoInteger(ACCOUNT_MARGIN_MODE)==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;
   MqlTick q;ok=SymbolInfoTick(_Symbol,q) && ok;
   double minlot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   CTrade foreign;foreign.SetExpertMagicNumber(Magic+999);
   foreign.SetTypeFillingBySymbol(_Symbol);
   ok=foreign.Buy(minlot,_Symbol,0,RoundPrice(q.ask-StopPoints),RoundPrice(q.ask+TargetPoints),"NQP fixture foreign") && ok;
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
   day=NQPDay(TimeCurrent());lastSignal=iTime(_Symbol,sourceTF,1);
   runtimeJournalTesting=true;runtimeBlocked=false;string journal=NQPStateKey();NQPStateSave();
   initialRisk=0;ownedEntryTime=0;entries=0;
   NQPStateRestore(TimeCurrent());
   ok=!runtimeBlocked && initialRisk>0 && ownedEntryTime>0 && OwnPosition()
      && (ulong)PositionGetInteger(POSITION_TICKET)==ownTicket && ok;
   bool rejected=!trade.Buy(0,_Symbol,0,0,0,"NQP invalid-volume fixture");
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
   NQPRuntimeCutoffCheck(NQPSessionTime(day)+870*60);
   ok=!OwnPosition() && PositionSelectByTicket(foreignTicket)
      && PositionGetDouble(POSITION_VOLUME)==foreignVolume
      && PositionGetDouble(POSITION_SL)==foreignStop && PositionGetDouble(POSITION_TP)==foreignTarget && ok;
   GlobalVariablesDeleteAll(journal);runtimeJournalTesting=false;
   // Only this fixture's own deliberately foreign-tagged position is cleaned up here.
   if(foreignTicket>0) ok=foreign.PositionClose(foreignTicket) && ok;
   int f=FileOpen(NQPOutputRoot+"/native_lifecycle_"+RunId+".txt",FILE_COMMON|FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f!=INVALID_HANDLE)
   {FileWriteString(f,ok ? "PASS: native hedging ownership, staged SL/TP, original-risk restart, invalid-volume rejection, minimum-risk refusal, partial close protection, timer cutoff and foreign protection preserved." : "FAIL: native lifecycle fixture");FileClose(f);}
   Print(ok ? "NQP_NATIVE_LIFECYCLE_PASS" : "NQP_NATIVE_LIFECYCLE_FAILED");
   TesterStop();return true;
}
#endif
#endif
