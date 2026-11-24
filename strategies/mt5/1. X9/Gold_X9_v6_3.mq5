//+------------------------------------------------------------------+
//|                                                   Gold_X9_v6_3.mq5|
//|        Copyright 2026-2027, Osamwonyi Eric (@You_FoundEric)      |
//|                                      https://x.com/You_FoundEric |
//+------------------------------------------------------------------+
#property copyright   "Copyright 2026-2027, Osamwonyi Eric (@You_FoundEric)"
#property link        "https://x.com/You_FoundEric"
#property version     "6.30"
#property description "Gold X9 v6.3 - Institutional Multi-Strategy Portfolio Expert Advisor"
#property strict

//--- Lot sizing
// enum_lotsizing retained for compatibility with Part 3 presets.
enum enum_lotsizing {
   Manual_Lotsize   = 0, // Fixed lots
   Tiered_Lotsizing = 1, // Portfolio tiered sizing
   RiskScaleFactor  = 2  // Balance-scaled sizing
};

enum enum_TradeFrequency {
   Extremely_Low             = 0, // Extremely low (Strategies 1-3)
   Low                       = 1, // Low (Strategies 1-5)
   Moderate                  = 2, // Moderate (Strategies 1-7)
   High                      = 3, // High (Strategies 1-8)
   Very_High                 = 4, // Very high (Strategies 1-9)
   Manual_Strategy_Selection = 5  // Manual strategy selection
};

enum ENUM_NEWS_IMPACT {
   NEWS_DISABLED   = 0, // Disabled
   NEWS_RED_ONLY   = 1, // Red-folder only (high impact)
   NEWS_RED_YELLOW = 2, // Red and yellow-folder (high + medium)
   NEWS_ALL        = 3  // All impacts (high + medium + low)
};

enum ENUM_DD_BASIS {
   DD_BASIS_EQUITY  = 0, // Equity (includes open P/L)
   DD_BASIS_BALANCE = 1  // Balance (closed P/L only)
};

enum ENUM_DD_MODE {
   DD_MODE_DYNAMIC = 0, // Dynamic (trailing high-water mark)
   DD_MODE_STATIC  = 1  // Static (fixed reference balance)
};

enum ENUM_DD_ACTION {
   DD_ACTION_NO_NEW_TRADES    = 0, // Block entries and cancel X9 pending orders
   DD_ACTION_CLOSE_EVERYTHING = 1  // Close X9 positions and cancel X9 pending orders
};

input group "==========  1 - Trading Profile  =========="
input enum_TradeFrequency TradeFrequency = Very_High;       // Portfolio frequency / enabled strategies

input group " "
input group "==========  2 - Lot Sizing  =========="
input enum_lotsizing Lotsizing_Method = Tiered_Lotsizing;   // Lot-sizing method
input double        TieredLot        = 30.0;               // Tiered sizing factor (>0 to 100; not risk percent)
input double        RiskScaling      = 1.0;                // Balance-scaled sizing multiplier
input double        InpFixedBalance  = 0.0;                // Sizing balance (account currency; 0 = actual balance)
input double        FixedLots        = 0.01;               // Fixed lots per trade (Fixed lots mode only)

input group "  "
input group "==========  2b - Separate Fixed Lots  =========="
input bool   SepLotSize = false;                           // Use separate strategy lots (Fixed lots mode only)
input double Strat1Lots = 0.01;                            // Strategy 1 - fixed lots
input double Strat2Lots = 0.01;                            // Strategy 2 - fixed lots
input double Strat3Lots = 0.01;                            // Strategy 3 - fixed lots
input double Strat4Lots = 0.01;                            // Strategy 4 - fixed lots
input double Strat5Lots = 0.01;                            // Strategy 5 - fixed lots
input double Strat6Lots = 0.01;                            // Strategy 6 - fixed lots
input double Strat7Lots = 0.01;                            // Strategy 7 - fixed lots
input double Strat8Lots = 0.01;                            // Strategy 8 - fixed lots
input double Strat9Lots = 0.01;                            // Strategy 9 - fixed lots

input group "   "
input group "==========  3 - Manual Strategy Selection  =========="
input bool RunStrat1 = true;                               // Strategy 1 (Manual strategy selection only)
input bool RunStrat2 = true;                               // Strategy 2 (Manual strategy selection only)
input bool RunStrat3 = true;                               // Strategy 3 (Manual strategy selection only)
input bool RunStrat4 = true;                               // Strategy 4 (Manual strategy selection only)
input bool RunStrat5 = true;                               // Strategy 5 (Manual strategy selection only)
input bool RunStrat6 = true;                               // Strategy 6 (Manual strategy selection only)
input bool RunStrat7 = true;                               // Strategy 7 (Manual strategy selection only)
input bool RunStrat8 = true;                               // Strategy 8 (Manual strategy selection only)
input bool RunStrat9 = true;                               // Strategy 9 (Manual strategy selection only)

input group "    "
input group "==========  4 - Prop / Execution Adjustments  =========="
input double AdjustEntry       = 0.0;                     // Entry-price adjustment (broker points; 0 = unchanged)
input double AdjustSL          = 0.0;                     // Initial stop adjustment (broker points)
input double AdjustTP          = 0.0;                     // Take-profit adjustment (broker points)
input double AdjustTrailSL     = 0.0;                     // Trailing-stop adjustment (broker points)
input double AdjustSalvageExit = 0.0;                     // Salvage-exit adjustment (broker points)
input double AdjustBreakEven   = 0.0;                     // Break-even adjustment (broker points)

input group "     "
input group "==========  5 - News Engine (USD | fixed 5m + 5m)  =========="
input ENUM_NEWS_IMPACT News_Impact = NEWS_DISABLED;        // ForexFactory news impact filter
input bool News_Block_Entries     = true;                 // Blackout: block new X9 orders
input bool News_Cancel_Pending    = false;                // Blackout: cancel existing X9 pending orders
input bool News_Freeze_Management = true;                 // Blackout: pause EA exits, SL/TP and pending maintenance
input bool News_Flatten_Before    = false;                // Flatten: close X9 positions and cancel pending before news
input int  News_Flatten_Min       = 5;                    // Flatten lead time (minutes; 0 = at release)
input bool InpNewsCacheInTester   = false;                // Use the last saved calendar snapshot in the tester (fixed input, deterministic)

input group "      "
input group "==========  6 - Drawdown Safeguards  =========="
input double        MaxDailyDDPercent = 0.0;              // Maximum daily drawdown (%; 0 = disabled)
input double        MaxTotalDDPercent = 0.0;              // Maximum total drawdown (%; 0 = disabled)
input ENUM_DD_BASIS DDBasis           = DD_BASIS_EQUITY;   // Drawdown measurement basis
input ENUM_DD_ACTION DDAction         = DD_ACTION_NO_NEW_TRADES; // Action when a drawdown limit is breached
input int           InpTotalDDResetID = 0;                 // Increase to explicitly re-arm a latched total-DD lock

input group "       "
input group "==========  6b - Total Drawdown Reference  =========="
input ENUM_DD_MODE DDMode          = DD_MODE_DYNAMIC;     // Total drawdown reference mode
input double       StaticDDBalance = 0.0;                // Static reference (account currency; 0 = startup basis)

input group "        "
input group "==========  7 - Chart Display  =========="
input bool  ShowInfoPanel    = true;                      // Show collapsible X9 information panel (live / visual test)
input bool  ShowGradientBg   = true;                      // Show Navy chart gradient (live / visual test)
input color GradientEndColor = C'18,42,76';               // Gradient colour - Navy by default

input group "         "
input group "==========  8 - Execution & Logging  =========="
input int    InpMagic          = 647900;                  // Magic base: strategy N owns base+N (1..9), so the last digit is the strategy number
input string TradeComment     = "X9S";                      // Order comment prefix; the strategy number is appended (X9S1 ... X9S9)
input bool   InpEnableAuditLog = true;                    // Detailed strategy / order journal logging
input bool   InpAllowMinLotOverride = true;              // Take the broker minimum when the budget is below it (false = skip the entry)

#include "StrategyEngine.mqh"


#include "ExecutionRuntime.mqh"
#include "ChartVisuals.mqh"

int OnInit() {
   int clockInit = ClkInit();
   if (clockInit != INIT_SUCCEEDED) return clockInit;
   if (News_Flatten_Min < 0) {
      Print("[X9_INPUT] Flatten lead time must be zero or greater.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if (X9VisualMode()) ChartSetInteger(0, CHART_SHOW_GRID, false);

   TradeSym = Symbol();
   SymPoint = SymbolInfoDouble(TradeSym, SYMBOL_POINT);
   SymDigits = (int)SymbolInfoInteger(TradeSym, SYMBOL_DIGITS);
   if (SymPoint <= 0.0 || SymDigits < 0) return INIT_FAILED;

   PipFactor = SymPoint;
   if (SymDigits == 3 || SymDigits == 5) PipFactor = SymPoint * 10.0;
   if (SymDigits == 1) PipFactor = SymPoint / 10.0;

   CurrSpread = SymbolInfoDouble(TradeSym, SYMBOL_ASK) - SymbolInfoDouble(TradeSym, SYMBOL_BID);
   StopLevelDist = (double)SymbolInfoInteger(TradeSym, SYMBOL_TRADE_STOPS_LEVEL) * SymPoint;
   FreezeLevelDist = (double)SymbolInfoInteger(TradeSym, SYMBOL_TRADE_FREEZE_LEVEL) * SymPoint;

   int legacyTickets = X9LegacyMagicTickets();
   if (legacyTickets > 0) {
      PrintFormat("[X9_MAGIC] %d ticket(s) still carry the old magic base %d (now %d). They are not owned by this build: "
                  "flatten the account before trusting adoption. Strategy magics are now base+N (last digit = strategy).",
                  legacyTickets, X9_LEGACY_MAGIC, InpMagic);
   }

   TieredLotEff = TieredLot;
   if (TieredLotEff > 100.0) TieredLotEff = 100.0;
   if (TieredLotEff <= 0.0) TieredLotEff = 1.0;

   SepStrategyLots[0] = Strat1Lots;
   SepStrategyLots[1] = Strat2Lots;
   SepStrategyLots[2] = Strat3Lots;
   SepStrategyLots[3] = Strat4Lots;
   SepStrategyLots[4] = Strat5Lots;
   SepStrategyLots[5] = Strat6Lots;
   SepStrategyLots[6] = Strat7Lots;
   SepStrategyLots[7] = Strat8Lots;
   SepStrategyLots[8] = Strat9Lots;

   switch (TradeFrequency) {
      case Extremely_Low:
         for (int i = 0; i < 9; i++) StratEnabled[i] = (i < 3);
         DDTierDivisor = 3.0;
         break;
      case Low:
         for (int i = 0; i < 9; i++) StratEnabled[i] = (i < 5);
         DDTierDivisor = 4.0;
         break;
      case Moderate:
         for (int i = 0; i < 9; i++) StratEnabled[i] = (i < 7);
         DDTierDivisor = 5.0;
         break;
      case High:
         for (int i = 0; i < 9; i++) StratEnabled[i] = (i < 8);
         DDTierDivisor = 5.6;
         break;
      case Very_High:
         for (int i = 0; i < 9; i++) StratEnabled[i] = true;
         DDTierDivisor = 6.0;
         break;
      case Manual_Strategy_Selection: {
         bool manualEnabled[9] = {RunStrat1, RunStrat2, RunStrat3, RunStrat4, RunStrat5, RunStrat6, RunStrat7, RunStrat8, RunStrat9};
         int manualCount = 0;
         for (int i = 0; i < 9; i++) {
            StratEnabled[i] = manualEnabled[i];
            if (StratEnabled[i]) manualCount++;
         }
         if (manualCount < 1) manualCount = 1;
         DDTierDivisor = (double)manualCount;
         break;
      }
   }

   double seedLots = FixedLots;
   if (Lotsizing_Method == Tiered_Lotsizing) seedLots = SymbolInfoDouble(TradeSym, SYMBOL_VOLUME_MIN);
   for (int i = 0; i < 9; i++) {
      PerStrategyPendingRescanBars[i] = 0;
      PerStrategyRescanBars[i] = 0;
      StrategyLots[i] = seedLots;
   }

   for (int i = 0; i < VirtualSLStoreSize; i++) {
      VirtualSLStore[i][0] = 0.0;
      VirtualSLStore[i][1] = 0.0;
   }
   for (int i = 0; i < 100; i++) {
      OrderPriceMap[i][0] = 0.0;
      OrderPriceMap[i][1] = 0.0;
   }

   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   LastHour = now.hour;
   g_dailyStartBasis = (DDBasis == DD_BASIS_EQUITY) ? AccountInfoDouble(ACCOUNT_EQUITY) : AccountInfoDouble(ACCOUNT_BALANCE);
   g_peakBasis = g_dailyStartBasis;
   g_staticFloorBasis = (StaticDDBalance > 0.0) ? StaticDDBalance : g_dailyStartBasis;
   g_lastDailyDay = now.year * 10000 + now.mon * 100 + now.day;
   X9LoadTotalDDLatch();
   X9ReconcilePendingOrders();

   SymInitOk = true;
   EventSetTimer(1);
   DrawGradientBackground();
   RenderInfoPanel();
   PrintFormat("[INIT] Gold X9 v6.3 initialized. BaseMagic=%d, Sym=%s, LotMode=%d, TieredLotEff=%.1f, DDTierDivisor=%.2f, PipFactor=%.5f",
               InpMagic, TradeSym, (int)Lotsizing_Method, TieredLotEff, DDTierDivisor, PipFactor);
   return INIT_SUCCEEDED;
}

void OnTick() {
   ClkRefresh(ClkNowServer());
   if (!SymInitOk) return;
   if (News_Impact != NEWS_DISABLED) EvaluateNewsControls();
   for (int i = 0; i < 9; i++) {
      if (!StratEnabled[i]) continue;
      SetupStrategyParams(i + 1);
      ActivateStrategyContext(i);
      RunStrategyTick(i);
   }
}

void OnTimer() {
   RefreshNewsFeed();
   EvaluateNewsControls();
   EvaluateDrawdownControls();
   X9RestoreCancelledPendingOrders();
   DrawGradientBackground();
   RenderInfoPanel();
}

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result) {
   if (trans.type == TRADE_TRANSACTION_ORDER_DELETE) X9NoteOrderDeleted(trans.order);
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
   ProcessVisualChartEvent(id, lparam, dparam, sparam);
}

void ExportDealLedger() {
   int file = FileOpen("Gold_X9_v6_3_Deals.csv", FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ",");
   if (file == INVALID_HANDLE || !HistorySelect(0, TimeCurrent() + 86400)) {
      if (file != INVALID_HANDLE) FileClose(file);
      return;
   }

   FileWrite(file, "deal_ticket", "time", "type", "entry_type", "volume", "price", "profit", "commission", "swap", "magic", "symbol", "comment");
   for (int i = 0; i < HistoryDealsTotal(); i++) {
      ulong ticket = HistoryDealGetTicket(i);
      if (ticket == 0) continue;
      long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
      if (!IsX9Magic(magic) || HistoryDealGetString(ticket, DEAL_SYMBOL) != TradeSym) continue;
      ENUM_DEAL_TYPE type = (ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE);
      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
      FileWrite(file,
         IntegerToString((long)ticket),
         TimeToString((datetime)HistoryDealGetInteger(ticket, DEAL_TIME), TIME_DATE | TIME_SECONDS),
         EnumToString(type), EnumToString(entry),
         DoubleToString(HistoryDealGetDouble(ticket, DEAL_VOLUME), 2),
         DoubleToString(HistoryDealGetDouble(ticket, DEAL_PRICE), SymDigits),
         DoubleToString(HistoryDealGetDouble(ticket, DEAL_PROFIT), 2),
         DoubleToString(HistoryDealGetDouble(ticket, DEAL_COMMISSION), 2),
         DoubleToString(HistoryDealGetDouble(ticket, DEAL_SWAP), 2),
         IntegerToString(magic), TradeSym, HistoryDealGetString(ticket, DEAL_COMMENT));
   }
   FileClose(file);
}

void OnDeinit(const int reason) {
   EventKillTimer();
   if (reason != REASON_RECOMPILE && reason != REASON_CHARTCHANGE && reason != REASON_PARAMETERS) {
      CancelAllX9PendingOrders();
   }
   ExportDealLedger();
   DeleteGradientBackground();
   DeleteInfoPanel();
   PrintFormat("[DEINIT] Gold X9 v6.3 exiting, reason=%d", reason);
}
