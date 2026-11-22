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
   FolderCreate("FVG_Duo_Closeout_20261120", FILE_COMMON);
   g_journalHandle = FileOpen("FVG_Duo_Closeout_20261120/trades_mt5.csv",
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

//+------------------------------------------------------------------+
//| SIZING                                                            |
//+------------------------------------------------------------------+
double AccountCashPerUSD()
{
   string currency = AccountInfoString(ACCOUNT_CURRENCY);
   if(currency == "USD") return 1.0;
   if(currency == "USC") return 100.0;
   return 0.0;
}

// Entry captures this account-currency budget once; later equity changes cannot enlarge it.
double TargetRiskUSD()
{
   double cashPerUSD = AccountCashPerUSD();
   if(cashPerUSD <= 0.0) return 0.0;
   if(InpSizingMode == SIZING_PERCENT)
      return AccountInfoDouble(ACCOUNT_EQUITY) * (InpRiskPercent / 100.0);
   if(InpSizingMode == SIZING_CASH)
      return InpCashRiskUSD * cashPerUSD;
   if(InpSizingMode == SIZING_PERCENT_BALANCE)
   {
      double balBase = (InpFixedBalanceUSD > 0.0)
                       ? InpFixedBalanceUSD * cashPerUSD : g_fixedBalanceBase;
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
      AccountCashPerUSD() <= 0.0) return false;
   double loss = 0.0;
   double stressedStop = stop - side * InpRiskSlippageTicks * tick;
   if(stressedStop <= 0.0 || !OrderCalcProfit(side > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                                            _Symbol, reference, entry, stressedStop, loss) ||
      !MathIsValidNumber(loss)) return false;
   perLot = MathMax(0.0, -loss) / reference + InpCommissionRTPerLot * AccountCashPerUSD();
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
      if(lots < minLot && MathIsValidNumber(budget) && budget > 0.0 &&
         MathIsValidNumber(minLot) && MathIsValidNumber(maxLot) && MathIsValidNumber(step) &&
         minLot > 0.0 && maxLot >= minLot && step > 0.0)
      {
         lots = minLot;
         PrintFormat("[FVG_DUO] RISK_MINIMUM: broker minimum exceeds intended risk; lots=%.8f estimatedRisk=%.2f intendedRisk=%.2f %s",
                     lots, lots * perLot, budget, AccountInfoString(ACCOUNT_CURRENCY));
      }
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
   double budget = TargetRiskUSD();
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

   double want = AllowedVolumeAtStop(ownedSide, entry, stopPrice, TargetRiskUSD());
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
