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
   datetime tday = SessionOf(TcServerToNY(s.entry_srv)) + 86400;
   datetime ev = UseNewsFlatten ? EventOn(tday) : 0;
   datetime entry_ny = TcServerToNY(s.entry_srv);
   s.flat_srv = 0;
   if(ev > 0 && MinOfDay(ev) < 12 * 60 && ev > entry_ny - (entry_ny % 300))   // release slot after the entry slot (as Python)
      s.flat_srv = TcNYToServer(ev - NewsExitLeadMinutes * 60);
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
      datetime expiry=TcNYToServer(SessionOf(NYNow())+86400+3*3600);
      if(lb > 0) TcReportEntry(trade.BuyStop(lb, buy_px, _Symbol, low, 0, ORDER_TIME_SPECIFIED, expiry, "C1"),"BUY stop");
      if(ls > 0) TcReportEntry(trade.SellStop(ls, sell_px, _Symbol, high, 0, ORDER_TIME_SPECIFIED, expiry, "C1"),"SELL stop");
   }
}

#endif // TC_EXECUTION_RUNTIME
