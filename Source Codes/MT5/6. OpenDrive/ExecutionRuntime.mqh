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

   char request[], response[]; string headers; ResetLastError();
   string url = News_WebRequest_URL;
   if(StringFind(url, ".json") < 0)
   {
      if(StringSubstr(url, StringLen(url)-1, 1) != "/") url += "/";
      url += "ff_calendar_thisweek.json";
   }

   int result = WebRequest("GET", url,
                           "User-Agent: Mozilla/5.0\r\nAccept: application/json\r\n",
                           5000, request, response, headers);
   requestError = GetLastError();
   string payload = (result == 200) ? CharArrayToString(response, 0, -1, CP_UTF8) : "";
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
