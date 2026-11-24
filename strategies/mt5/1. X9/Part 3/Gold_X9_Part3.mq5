//+------------------------------------------------------------------+
//| Gold_X9_Part3.mq5 - Strategy information                         |
//| Copyright 2026, Mr CapFree                                       |
//| https://www.MrCapFree.com                                        |
//+------------------------------------------------------------------+
#property copyright   "Mr CapFree"
#property link        "https://www.MrCapFree.com"
#property version     "6.30"
#property description "Gold X9 - v 6.3 - by Mr CapFree (Multi-Strategy Part 3)"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\PositionInfo.mqh>

CTrade         trade;
COrderInfo     ordinfo;
CPositionInfo  posinfo;

//--- Lotsize Calculation Methods
enum enum_lotsizing {
   Manual_Lotsize   = 0,  // Fixed Lots
   Tiered_Lotsizing = 1,  // Tiered Lot Sizing
   RiskScaleFactor  = 2   // Risk Scaling Factor (%)
};

//--- Trade Frequency Execution / Strategy Selection Preset
enum enum_TradeFrequency {
   Extremely_Low             = 0, // Extremely Low (Strategies 1-3)
   Low                       = 1, // Low (Strategies 1-5)
   Moderate                  = 2, // Moderate (Strategies 1-7)
   High                      = 3, // High (Strategies 1-8)
   Very_High                 = 4, // Very High (Strategies 1-9)
   Manual_Strategy_Selection = 5  // Manual strategy selection
};

//====================================================================
// INPUT PARAMETERS
//====================================================================
input group "=== TRADE SETUP ===";
input enum_TradeFrequency  TradeFrequency        = Very_High;              // Trading Frequency
input int                  InpMagic              = 647873;                 // EA Magic Number
input string               TradeComment          = "Gold X9 by MrCapFree"; // Comment for trades

input group "=== MONEY MANAGEMENT / Lotsize Calculations ===";
input enum_lotsizing       Lotsizing_Method      = Tiered_Lotsizing;       // Lotsize Calculation method
input double               TieredLot             = 30;                     // Tiered Lot Sizing Risk Meter (1 - 100 Max)
input double               FixedLots             = 0.01;                   // Fixed Lots
input double               RiskScaling           = 1;                      // Risk Scaling Factor (%)
input double               InpFixedBalance       = 0.0;                    // Fixed Balance for Sizing (0 = Live Account Balance)

input group "=== Define Separate Lotsize for Individual Strategies ===";
input bool                 SepLotSize            = false;                  // Use separate lotsize per strategy (Fixed Lots mode only)
input double               Strat1Lots            = 0.01;                   // Strategy 1 Lotsize
input double               Strat2Lots            = 0.01;                   // Strategy 2 Lotsize
input double               Strat3Lots            = 0.01;                   // Strategy 3 Lotsize
input double               Strat4Lots            = 0.01;                   // Strategy 4 Lotsize
input double               Strat5Lots            = 0.01;                   // Strategy 5 Lotsize
input double               Strat6Lots            = 0.01;                   // Strategy 6 Lotsize
input double               Strat7Lots            = 0.01;                   // Strategy 7 Lotsize
input double               Strat8Lots            = 0.01;                   // Strategy 8 Lotsize
input double               Strat9Lots            = 0.01;                   // Strategy 9 Lotsize

input group "=== PROP AND ENTRY ADJUSTMENTS ===";
input double               AdjustEntry           = 0;                      // Adjust Entry (in points)
input double               AdjustSL              = 0;                      // Adjust SL (in points)
input double               AdjustTP              = 0;                      // Adjust TP (in points)
input double               AdjustTrailSL         = 0;                      // Adjust Trail SL (in points)
input double               AdjustSalvageExit     = 0;                      // Adjust Salvage Exit (in points)
input double               AdjustBreakEven       = 0;                      // Adjust Breakeven (in points)

input group "=== Manual Strategy Selection ===";
input bool                 RunStrat1             = true;                   // Run Strategy 1
input bool                 RunStrat2             = true;                   // Run Strategy 2
input bool                 RunStrat3             = true;                   // Run Strategy 3
input bool                 RunStrat4             = true;                   // Run Strategy 4
input bool                 RunStrat5             = true;                   // Run Strategy 5
input bool                 RunStrat6             = true;                   // Run Strategy 6
input bool                 RunStrat7             = true;                   // Run Strategy 7
input bool                 RunStrat8             = true;                   // Run Strategy 8
input bool                 RunStrat9             = true;                   // Run Strategy 9

input group "=== DIAGNOSTICS & AUDIT LOGGING ===";
input bool                 InpEnableAuditLog     = true;                   // Enable Reason-Coded Audit Logging

//====================================================================
// STRATEGY PRESET STRUCTURE & TABLE
//====================================================================
struct StrategyPreset {
   ENUM_TIMEFRAMES fractalTf;
   ENUM_TIMEFRAMES rescanTf;
   int             fractalRight;
   int             fractalLeft;
   int             fractalMaxSearch;
   int             maxPending;
   int             pendExpiryHrs;
   ENUM_TIMEFRAMES exitScanTf;
   int             maxPositions;
   int             magicOffset;
   double          fractalMinDistPct;
   double          pendDedupDist;
   double          buyEntryPct;
   double          sellEntryPct;
   double          slPct;
   double          tpPct;
   double          trailPct;
   double          trailMinProfitPct;
   double          trailMaxSLPct;
   double          salvageTriggerPct;
   double          salvageExitPct;
   double          beTriggerPct;
   double          beLockPct;
   double          riskWeight;
   string          commentSuffix;
};

StrategyPreset StrategyPresets[9] = {
   // Strategy 1
   {
      PERIOD_D1, PERIOD_M15, 3, 25, 100, 5, 35, PERIOD_M1, 5, 1,
      0.02, 30.0, -0.14, -0.14, 3.00, 0.75, 0.90, 0.90, 2.50, 0.80, 0.35, 0.45, 0.06, 0.60, "_XAUUSD_1"
   },
   // Strategy 2
   {
      PERIOD_D1, PERIOD_M15, 3, 15, 200, 1, 500, PERIOD_M1, 10, 2,
      0.28, 500.0, -0.085, -0.085, 0.50, 2.00, 0.25, 0.70, 2.50, 0.80, 0.20, 0.25, 0.05, 0.3333, "_XAUUSD_2"
   },
   // Strategy 3
   {
      PERIOD_D1, PERIOD_H1, 2, 7, 20, 1, 400, PERIOD_M1, 10, 3,
      0.125, 1000.0, -0.065, -0.065, 0.30, 1.65, 0.25, 0.20, 2.50, 0.50, 1.00, 0.20, 0.00, 0.1714, "_XAUUSD_3"
   },
   // Strategy 4
   {
      PERIOD_H4, PERIOD_M15, 8, 12, 100, 2, 200, PERIOD_M5, 10, 4,
      0.66, 130.0, -0.025, -0.0625, 0.44, 3.10, 0.81, 0.91, 1.25, 0.90, 0.125, 0.33, 0.125, 0.1346, "_XAUUSD_4"
   },
   // Strategy 5
   {
      PERIOD_H1, PERIOD_M15, 19, 30, 100, 3, 30, PERIOD_M1, 10, 5,
      0.05, 50.0, -0.045, -0.045, 2.00, 0.35, 0.20, 0.15, 1.90, 0.70, 0.10, 0.10, 0.05, 0.48182, "_XAUUSD_5"
   },
   // Strategy 6
   {
      PERIOD_H1, PERIOD_M5, 25, 25, 150, 5, 20, PERIOD_M1, 5, 6,
      0.05, 50.0, -0.060, -0.060, 4.20, 0.33, 0.20, 0.50, 2.10, 0.80, 0.15, 0.15, 0.0333, 0.7214, "_XAUUSD_6"
   },
   // Strategy 7
   {
      PERIOD_H1, PERIOD_M5, 23, 25, 150, 5, 60, PERIOD_M1, 5, 7,
      0.005, 90.0, -0.055, -0.055, 0.87, 0.56, 0.175, 0.35, 1.90, 1.10, 0.15, 0.13, 0.01, 0.20, "_XAUUSD_7"
   },
   // Strategy 8
   {
      PERIOD_H1, PERIOD_M15, 20, 25, 250, 5, 55, PERIOD_M1, 10, 8,
      0.03, 5.0, -0.060, -0.060, 0.68, 0.43, 0.45, 0.23, 1.40, 0.70, 0.10, 0.10, 0.00, 0.14615, "_XAUUSD_8"
   },
   // Strategy 9
   {
      PERIOD_H1, PERIOD_M15, 5, 5, 200, 3, 15, PERIOD_M1, 10, 9,
      0.02, 5.0, -0.080, -0.080, 2.00, 0.70, 0.20, 0.20, 1.00, 1.00, 0.15, 0.10, 0.025, 0.055, "_XAUUSD_9"
   }
};

//====================================================================
// GLOBAL VARIABLES
//====================================================================
double              TieredLotEff;
double              CurrSpread;
ENUM_TIMEFRAMES     FractalTf;
ENUM_TIMEFRAMES     RescanTf;
int                 FractalRight;
int                 FractalLeft;
int                 FractalMaxSearch;
int                 MaxPendingOrders;
int                 MaxPositions;
double              PendingDedupDist;
int                 PendingExpiryHrs;
int                 ActiveMagic;
ENUM_TIMEFRAMES     ExitScanTf;
int                 SymDigits;
double              StopLevelDist;
double              PipFactor;
double              FreezeLevelDist;
string              ActiveComment;
string              TradeSym;
double              SymPoint;

int                 DayswitchBufferMin = 30;
double              FractalMinDist;
double              BuyEntryOffset;
double              SellEntryOffset;
bool                Virtual_expiration = true;

double              SLDist;
double              TPDist;
double              TrailDist;
double              TrailMinProfit;
double              TrailMaxSL;
double              TrailStep = 0.1;
double              SalvageExitDist;
double              SalvageTrigger;
double              BeTrigger;
double              BeLockDist;

double              MaxLotCap = 100.0;
double              WeightedRiskDivisor = 1.0;
double              DDTierDivisor = 1.0;
double              RiskWeight = 0.0;

double              LastSwingHigh = 0.0;
double              LastSwingLow = 0.0;
double              VirtualSL = 0.0;

double              VirtualSLStore[20][2];
double              OrderPriceMap[100][2];
int                 VirtualSLStoreSize = 20;

double              StrategyLots[9];
double              SepStrategyLots[9];
int                 LastTradeTicket = 0;
int                 PendingExpirySeconds;

double              SwingLow = 0.0;
double              SwingHigh = 0.0;

int                 LastHour = 0;
datetime            PendingExpiry = 0;
int                 PerStrategyRescanBars[9];
int                 PerStrategyPendingRescanBars[9];

bool                StratEnabled[9];
int                 StrategyIdx = 0;
bool                SymInitOk = false;

// Active parameter cache from preset
double              FractalMinDistPct;
double              BuyEntryPct;
double              SellEntryPct;
double              SlPct;
double              TpPct;
double              TrailPct;
double              TrailMinProfitPct;
double              TrailMaxSLPct;
double              SalvageTriggerPct;
double              SalvageExitDistPct;
double              BeTriggerPct;
double              BeLockPct;

//====================================================================
// FORWARD DECLARATIONS
//====================================================================
void   SetupStrategyParams(int stratNum);
void   ActivateStrategyContext(int strategyIndex);
int    RunStrategyTick(int stratIdx);
double FindSwingPoint(ENUM_TIMEFRAMES timeframe, bool findHigh);
bool   PlaceEntry(bool isBuy);
void   CalculateLotSize();
void   ProcessStrategyEntries();
bool   ManageOrders(bool isBuy);
void   ExportOrdersToCsv();

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    ChartSetInteger(0, CHART_SHOW_GRID, false);

    TradeSym = Symbol();
    SymPoint = SymbolInfoDouble(TradeSym, SYMBOL_POINT);
    SymDigits = (int)SymbolInfoInteger(TradeSym, SYMBOL_DIGITS);

    PipFactor = SymPoint;
    if ( (double)SymDigits == 3.0 || (double)SymDigits == 5.0 ){
        PipFactor = SymPoint * 10.0;
    }
    if ( SymDigits == 1 ){
        PipFactor = SymPoint / 10.0;
    }

    CurrSpread = SymbolInfoDouble(TradeSym, SYMBOL_ASK) - SymbolInfoDouble(TradeSym, SYMBOL_BID);
    StopLevelDist = (double)SymbolInfoInteger(TradeSym, SYMBOL_TRADE_STOPS_LEVEL) * SymPoint;
    FreezeLevelDist = (double)SymbolInfoInteger(TradeSym, SYMBOL_TRADE_FREEZE_LEVEL) * SymPoint;

    TieredLotEff = TieredLot;
    if ( TieredLotEff > 100.0 ) TieredLotEff = 100.0;
    if ( TieredLotEff <= 0.0 )  TieredLotEff = 1.0;

    SepStrategyLots[0] = Strat1Lots;
    SepStrategyLots[1] = Strat2Lots;
    SepStrategyLots[2] = Strat3Lots;
    SepStrategyLots[3] = Strat4Lots;
    SepStrategyLots[4] = Strat5Lots;
    SepStrategyLots[5] = Strat6Lots;
    SepStrategyLots[6] = Strat7Lots;
    SepStrategyLots[7] = Strat8Lots;
    SepStrategyLots[8] = Strat9Lots;

    // Configure frequency and active strategies
    switch(TradeFrequency) {
        case Extremely_Low: // Strategies 1-3
            StratEnabled[0] = true;  StratEnabled[1] = true;  StratEnabled[2] = true;
            StratEnabled[3] = false; StratEnabled[4] = false; StratEnabled[5] = false;
            StratEnabled[6] = false; StratEnabled[7] = false; StratEnabled[8] = false;
            DDTierDivisor = 3.0;
            break;
        case Low: // Strategies 1-5
            StratEnabled[0] = true;  StratEnabled[1] = true;  StratEnabled[2] = true;
            StratEnabled[3] = true;  StratEnabled[4] = true;  StratEnabled[5] = false;
            StratEnabled[6] = false; StratEnabled[7] = false; StratEnabled[8] = false;
            DDTierDivisor = 4.0;
            break;
        case Moderate: // Strategies 1-7
            StratEnabled[0] = true;  StratEnabled[1] = true;  StratEnabled[2] = true;
            StratEnabled[3] = true;  StratEnabled[4] = true;  StratEnabled[5] = true;
            StratEnabled[6] = true;  StratEnabled[7] = false; StratEnabled[8] = false;
            DDTierDivisor = 5.0;
            break;
        case High: // Strategies 1-8
            StratEnabled[0] = true;  StratEnabled[1] = true;  StratEnabled[2] = true;
            StratEnabled[3] = true;  StratEnabled[4] = true;  StratEnabled[5] = true;
            StratEnabled[6] = true;  StratEnabled[7] = true;  StratEnabled[8] = false;
            DDTierDivisor = 5.6;
            break;
        case Very_High: // Strategies 1-9
            StratEnabled[0] = true;  StratEnabled[1] = true;  StratEnabled[2] = true;
            StratEnabled[3] = true;  StratEnabled[4] = true;  StratEnabled[5] = true;
            StratEnabled[6] = true;  StratEnabled[7] = true;  StratEnabled[8] = true;
            DDTierDivisor = 6.0;
            break;
        case Manual_Strategy_Selection: {
            StratEnabled[0] = RunStrat1;
            StratEnabled[1] = RunStrat2;
            StratEnabled[2] = RunStrat3;
            StratEnabled[3] = RunStrat4;
            StratEnabled[4] = RunStrat5;
            StratEnabled[5] = RunStrat6;
            StratEnabled[6] = RunStrat7;
            StratEnabled[7] = RunStrat8;
            StratEnabled[8] = RunStrat9;

            int manualStratCount = 0;
            for (int i = 0; i < 9; i++) {
                if (StratEnabled[i]) manualStratCount++;
            }
            if (manualStratCount < 1) manualStratCount = 1;
            DDTierDivisor = (double)manualStratCount;
            break;
        }
    }

    double seedLots = FixedLots;
    if ( Lotsizing_Method == Tiered_Lotsizing ){
        seedLots = SymbolInfoDouble(TradeSym, SYMBOL_VOLUME_MIN);
    }

    for (int i = 0; i < 9; i++){
        PerStrategyPendingRescanBars[i] = 0;
        PerStrategyRescanBars[i]        = 0;
        StrategyLots[i]                = seedLots;
    }

    if ( MaxLotCap > SymbolInfoDouble(TradeSym, SYMBOL_VOLUME_MAX) && SymbolInfoDouble(TradeSym, SYMBOL_VOLUME_MAX) > 0.0 ){
        MaxLotCap = SymbolInfoDouble(TradeSym, SYMBOL_VOLUME_MAX);
    }

    for (int vslResetOuterIdx = 0; vslResetOuterIdx < VirtualSLStoreSize; vslResetOuterIdx++){
        for (int vslResetInnerIdx = 0; vslResetInnerIdx < 2; vslResetInnerIdx++){
            VirtualSLStore[vslResetOuterIdx][vslResetInnerIdx] = 0.0;
        }
    }

    for (int mapInitIdx = 0; mapInitIdx < 100; mapInitIdx++){
        OrderPriceMap[mapInitIdx][0] = 0.0;
        OrderPriceMap[mapInitIdx][1] = 0.0;
    }

    MqlDateTime nowDt;
    TimeToStruct(TimeCurrent(), nowDt);
    LastHour = nowDt.hour;

    SymInitOk = true;

    PrintFormat("[INIT] Gold X9 v6.3 Part 3 initialized. BaseMagic=%d, Sym=%s, LotMode=%d, TieredLotEff=%.1f, DDTierDivisor=%.2f, PipFactor=%.5f",
                InpMagic, TradeSym, (int)Lotsizing_Method, TieredLotEff, DDTierDivisor, PipFactor);

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Export Orders to CSV for parity verification                     |
//+------------------------------------------------------------------+
void ExportOrdersToCsv() {
    int handle = FileOpen("Gold_X9_Part3_Orders.csv", FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ",");
    if(handle == INVALID_HANDLE)
        return;

    FileWrite(handle, "open_time", "order", "symbol", "type", "volume", "price", "sl", "tp", "close_time", "state", "comment", "magic");

    if(!HistorySelect(0, TimeCurrent() + 86400)) {
        FileClose(handle);
        return;
    }

    int totalOrders = HistoryOrdersTotal();
    for(int i = 0; i < totalOrders; i++) {
        ulong ticket = HistoryOrderGetTicket(i);
        if(ticket == 0) continue;

        long magic = HistoryOrderGetInteger(ticket, ORDER_MAGIC);
        if(magic < InpMagic || magic > InpMagic + 20) continue;

        string sym = HistoryOrderGetString(ticket, ORDER_SYMBOL);
        ENUM_ORDER_TYPE typeInt = (ENUM_ORDER_TYPE)HistoryOrderGetInteger(ticket, ORDER_TYPE);
        double volInit = HistoryOrderGetDouble(ticket, ORDER_VOLUME_INITIAL);
        double volCurr = HistoryOrderGetDouble(ticket, ORDER_VOLUME_CURRENT);
        double px = HistoryOrderGetDouble(ticket, ORDER_PRICE_OPEN);
        double sl = HistoryOrderGetDouble(ticket, ORDER_SL);
        double tp = HistoryOrderGetDouble(ticket, ORDER_TP);
        datetime timeSetup = (datetime)HistoryOrderGetInteger(ticket, ORDER_TIME_SETUP);
        datetime timeDone = (datetime)HistoryOrderGetInteger(ticket, ORDER_TIME_DONE);
        ENUM_ORDER_STATE stateInt = (ENUM_ORDER_STATE)HistoryOrderGetInteger(ticket, ORDER_STATE);
        string comm = HistoryOrderGetString(ticket, ORDER_COMMENT);

        string typeStr = "unknown";
        switch(typeInt) {
            case ORDER_TYPE_BUY:        typeStr = "buy"; break;
            case ORDER_TYPE_SELL:       typeStr = "sell"; break;
            case ORDER_TYPE_BUY_LIMIT:  typeStr = "buy limit"; break;
            case ORDER_TYPE_SELL_LIMIT: typeStr = "sell limit"; break;
            case ORDER_TYPE_BUY_STOP:   typeStr = "buy stop"; break;
            case ORDER_TYPE_SELL_STOP:  typeStr = "sell stop"; break;
        }

        string stateStr = "unknown";
        switch(stateInt) {
            case ORDER_STATE_STARTED:   stateStr = "started"; break;
            case ORDER_STATE_PLACED:    stateStr = "placed"; break;
            case ORDER_STATE_CANCELED:  stateStr = "canceled"; break;
            case ORDER_STATE_PARTIAL:   stateStr = "partial"; break;
            case ORDER_STATE_FILLED:    stateStr = "filled"; break;
            case ORDER_STATE_REJECTED:  stateStr = "rejected"; break;
            case ORDER_STATE_EXPIRED:   stateStr = "expired"; break;
            case ORDER_STATE_REQUEST_ADD:    stateStr = "request add"; break;
            case ORDER_STATE_REQUEST_MODIFY: stateStr = "request modify"; break;
            case ORDER_STATE_REQUEST_CANCEL: stateStr = "request cancel"; break;
        }

        string volStr = StringFormat("%.2f / %.2f", volInit, volCurr);
        string timeDoneStr = (timeDone > 0) ? TimeToString(timeDone, TIME_DATE | TIME_SECONDS) : "";

        FileWrite(handle,
                  TimeToString(timeSetup, TIME_DATE | TIME_SECONDS),
                  IntegerToString(ticket),
                  sym,
                  typeStr,
                  volStr,
                  DoubleToString(px, SymDigits),
                  DoubleToString(sl, SymDigits),
                  DoubleToString(tp, SymDigits),
                  timeDoneStr,
                  stateStr,
                  comm,
                  IntegerToString(magic));
    }

    FileClose(handle);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    ExportOrdersToCsv();

    if ( HistorySelect(0, TimeCurrent() + 86400) ){
        int totalDeals = HistoryDealsTotal();
        int inDeals = 0, outDeals = 0;
        int winCount = 0, lossCount = 0;
        int shortWins = 0, shortTotal = 0, longWins = 0, longTotal = 0;
        double netProfit = 0.0, grossProfit = 0.0, grossLoss = 0.0;
        double largestWin = 0.0, largestLoss = 0.0;

        for (int d = 0; d < totalDeals; d++){
            ulong dealTicket = HistoryDealGetTicket(d);
            if ( dealTicket == 0 ) continue;
            long dealMagic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
            if ( dealMagic < InpMagic || dealMagic > InpMagic + 20 ) continue;
            if ( HistoryDealGetString(dealTicket, DEAL_SYMBOL) != TradeSym ) continue;

            ENUM_DEAL_ENTRY entryType = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
            ENUM_DEAL_TYPE dealType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(dealTicket, DEAL_TYPE);

            if ( entryType == DEAL_ENTRY_IN ) {
                inDeals++;
            }
            else if ( entryType == DEAL_ENTRY_OUT || entryType == DEAL_ENTRY_INOUT ){
                outDeals++;
                double p = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
                double comm = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
                double swap = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
                double totalP = p + comm + swap;
                netProfit += totalP;

                // Deal direction on entry was opposite of exit
                bool wasShort = (dealType == DEAL_TYPE_BUY); // Exit by buying means original position was SHORT
                if ( wasShort ) {
                    shortTotal++;
                    if ( totalP >= 0.0 ) shortWins++;
                }
                else {
                    longTotal++;
                    if ( totalP >= 0.0 ) longWins++;
                }

                if ( totalP >= 0.0 ){
                    winCount++;
                    grossProfit += totalP;
                    if ( totalP > largestWin ) largestWin = totalP;
                }
                else{
                    lossCount++;
                    grossLoss += totalP;
                    if ( totalP < largestLoss ) largestLoss = totalP;
                }
            }
        }

        double pf = (MathAbs(grossLoss) > 0.0) ? (grossProfit / MathAbs(grossLoss)) : 0.0;
        double winRate = (outDeals > 0) ? ((double)winCount / (double)outDeals * 100.0) : 0.0;
        double payoff = (outDeals > 0) ? (netProfit / (double)outDeals) : 0.0;
        double avgWin = (winCount > 0) ? (grossProfit / (double)winCount) : 0.0;
        double avgLoss = (lossCount > 0) ? (grossLoss / (double)lossCount) : 0.0;

        PrintFormat("[SUMMARY] Trades: %d (In: %d, Out: %d) | Wins: %d (%.2f%%) | Losses: %d | NetProfit: %.2f",
                    outDeals, inDeals, outDeals, winCount, winRate, lossCount, netProfit);
        PrintFormat("[SUMMARY] PF: %.2f | Payoff: %.2f | AvgWin: %.2f | AvgLoss: %.2f | MaxWin: %.2f | MaxLoss: %.2f",
                    pf, payoff, avgWin, avgLoss, largestWin, largestLoss);
        PrintFormat("[SUMMARY] Shorts: %d (Won %d, %.2f%%) | Longs: %d (Won %d, %.2f%%)",
                    shortTotal, shortWins, (shortTotal > 0 ? (double)shortWins/shortTotal*100.0 : 0.0),
                    longTotal, longWins, (longTotal > 0 ? (double)longWins/longTotal*100.0 : 0.0));

        // Write summary to Common Files for external scripts to read instantly
        int sumHandle = FileOpen("Gold_X9_Part3_Summary.txt", FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
        if ( sumHandle != INVALID_HANDLE ){
            FileWriteString(sumHandle, StringFormat(
                "Trades=%d\nWins=%d\nLosses=%d\nWinRate=%.2f\nNetProfit=%.2f\nGrossProfit=%.2f\nGrossLoss=%.2f\nPF=%.2f\nPayoff=%.2f\nAvgWin=%.2f\nAvgLoss=%.2f\nLargestWin=%.2f\nLargestLoss=%.2f\nInDeals=%d\nOutDeals=%d\nShortTrades=%d\nShortWon=%d\nLongTrades=%d\nLongWon=%d\n",
                outDeals, winCount, lossCount, winRate, netProfit, grossProfit, grossLoss, pf, payoff, avgWin, avgLoss, largestWin, largestLoss, inDeals, outDeals, shortTotal, shortWins, longTotal, longWins));
            FileClose(sumHandle);
        }
    }
    PrintFormat("[DEINIT] Gold X9 v6.3 Part 3 exiting, reason=%d", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    if (!SymInitOk) return;

    for (int stratNum = 1; stratNum <= 9; stratNum++) {
        int strategyIndex = stratNum - 1;
        if (!StratEnabled[strategyIndex]) continue;

        SetupStrategyParams(stratNum);
        ActivateStrategyContext(strategyIndex);
        RunStrategyTick(strategyIndex);
    }
}

//+------------------------------------------------------------------+
//| Setup Strategy Parameters from preset                            |
//+------------------------------------------------------------------+
void SetupStrategyParams(int stratNum) {
    StrategyPreset preset = StrategyPresets[stratNum - 1];

    FractalTf          = preset.fractalTf;
    RescanTf           = preset.rescanTf;
    FractalRight       = preset.fractalRight;
    FractalLeft        = preset.fractalLeft;
    FractalMaxSearch   = preset.fractalMaxSearch;
    FractalMinDistPct  = preset.fractalMinDistPct;
    BuyEntryPct        = preset.buyEntryPct;
    SellEntryPct       = preset.sellEntryPct;
    MaxPendingOrders   = preset.maxPending;
    PendingDedupDist   = preset.pendDedupDist;
    PendingExpiryHrs   = preset.pendExpiryHrs;
    ExitScanTf         = preset.exitScanTf;
    SlPct              = preset.slPct;
    TpPct              = preset.tpPct;
    TrailPct           = preset.trailPct;
    TrailMinProfitPct  = preset.trailMinProfitPct;
    TrailMaxSLPct      = preset.trailMaxSLPct;
    SalvageTriggerPct  = preset.salvageTriggerPct;
    SalvageExitDistPct = preset.salvageExitPct;
    BeTriggerPct       = preset.beTriggerPct;
    BeLockPct          = preset.beLockPct;
    MaxPositions       = preset.maxPositions;
    ActiveComment      = TradeComment + preset.commentSuffix;
    ActiveMagic        = InpMagic + preset.magicOffset;
    RiskWeight         = preset.riskWeight;
}

//+------------------------------------------------------------------+
//| Activate Strategy Context                                        |
//+------------------------------------------------------------------+
void ActivateStrategyContext(int strategyIndex) {
    StrategyIdx = strategyIndex;

    CurrSpread          = SymbolInfoDouble(TradeSym, SYMBOL_ASK) - SymbolInfoDouble(TradeSym, SYMBOL_BID);
    StopLevelDist       = (double)SymbolInfoInteger(TradeSym, SYMBOL_TRADE_STOPS_LEVEL) * SymPoint;
    FreezeLevelDist     = (double)SymbolInfoInteger(TradeSym, SYMBOL_TRADE_FREEZE_LEVEL) * SymPoint;
    PendingExpirySeconds = PendingExpiryHrs * 60 * 60;

    double currentRefPrice = SymbolInfoDouble(TradeSym, SYMBOL_BID);

    FractalMinDist      = FractalMinDistPct / 100.0 * currentRefPrice / PipFactor;
    BuyEntryOffset      = AdjustEntry + NormalizeDouble(BuyEntryPct / 100.0 * currentRefPrice / PipFactor, 0);
    SellEntryOffset     = AdjustEntry + NormalizeDouble(SellEntryPct / 100.0 * currentRefPrice / PipFactor, 0);
    SLDist              = AdjustSL + SlPct / 100.0 * currentRefPrice / PipFactor;
    TPDist              = AdjustTP + TpPct / 100.0 * currentRefPrice / PipFactor;
    TrailDist           = AdjustTrailSL + TrailPct / 100.0 * currentRefPrice / PipFactor;
    TrailMinProfit      = TrailMinProfitPct / 100.0 * currentRefPrice / PipFactor;
    TrailMaxSL          = TrailMaxSLPct / 100.0 * currentRefPrice / PipFactor;
    SalvageExitDist     = AdjustSalvageExit + SalvageExitDistPct / 100.0 * currentRefPrice / PipFactor;
    SalvageTrigger      = SalvageTriggerPct / 100.0 * currentRefPrice / PipFactor;
    BeTrigger           = BeTriggerPct / 100.0 * currentRefPrice / PipFactor;
    BeLockDist          = AdjustBreakEven + BeLockPct / 100.0 * currentRefPrice / PipFactor;
    if ( BeLockPct == 0.0 && BeLockDist == 0.0 && BeTrigger > 0.0 ){
        BeLockDist = 1.0 * SymPoint / PipFactor;
    }

    if ( BeLockDist > BeTrigger ){
        BeLockDist = BeTrigger / 2.0;
    }
}

//+------------------------------------------------------------------+
//| RunStrategyTick (Per-Strategy Execution)                         |
//+------------------------------------------------------------------+
int RunStrategyTick(int stratIdx) {
    bool        anyOrderModified;
    MqlDateTime nowDt;
    int         buyPendingCount;
    int         buyPendingCountScanIdx;
    double      highestBuyPendingPrice;
    long        highestBuyPendingTicket;
    int         buyPendingWorstScanIdx;
    long        deletedBuyTicket;
    int         buyMapClearIdx;
    int         sellPendingCount;
    int         sellPendingCountScanIdx;
    double      lowestSellPendingPrice;
    long        lowestSellPendingTicket;
    int         sellPendingWorstScanIdx;
    long        deletedSellTicket;
    int         sellMapClearIdx;
    bool        orderMapEntryStillOpen;
    int         orderMapScanIdx;
    long        mapStoredTicket;
    int         orderMapTicketScanIdx;
    long        currentScanTicket;
    int         pendingLoopCounter;

    TimeToStruct(TimeCurrent(), nowDt);
    anyOrderModified = false;

    //--- Manage open orders based on ExitScanTf
    if ( ExitScanTf == PERIOD_CURRENT ){
        if ( ManageOrders(true) ){
            anyOrderModified = true;
        }
        if ( ManageOrders(false) ){
            anyOrderModified = true;
        }
        if ( anyOrderModified ){
            return(0);
        }
    }
    else{
        if ( PerStrategyRescanBars[stratIdx] != iBars(TradeSym, ExitScanTf) ){
            PerStrategyRescanBars[stratIdx] = iBars(TradeSym, ExitScanTf);
            if ( ManageOrders(true) ){
                anyOrderModified = true;
            }
            if ( ManageOrders(false) ){
                anyOrderModified = true;
            }
            if ( anyOrderModified ){
                return(0);
            }
        }
    }

    //--- Day-switch rollover filter (minute-based window around midnight)
    if ( (nowDt.hour == 0  && nowDt.min <  DayswitchBufferMin) ||
         (nowDt.hour == 23 && nowDt.min >= 60 - DayswitchBufferMin) ){
        return(0);
    }

    CurrSpread = SymbolInfoDouble(TradeSym, SYMBOL_ASK) - SymbolInfoDouble(TradeSym, SYMBOL_BID);

    //--- Scan Buy Pending Orders and prune worst if > MaxPendingOrders
    buyPendingCount = 0;
    for (buyPendingCountScanIdx = 0; ordinfo.SelectByIndex(buyPendingCountScanIdx); buyPendingCountScanIdx++){
        if ( ordinfo.Magic() != ActiveMagic ||
             ordinfo.Symbol() != TradeSym ||
             ordinfo.OrderType() != ORDER_TYPE_BUY_STOP )
            continue;
        buyPendingCount = buyPendingCount + 1;
    }

    if ( buyPendingCount > MaxPendingOrders ){
        highestBuyPendingPrice = 0.0;
        highestBuyPendingTicket = 0;
        for (buyPendingWorstScanIdx = 0; ordinfo.SelectByIndex(buyPendingWorstScanIdx); buyPendingWorstScanIdx++){
            if ( ordinfo.Magic() != ActiveMagic ||
                 ordinfo.Symbol() != TradeSym ||
                 ordinfo.OrderType() != ORDER_TYPE_BUY_STOP ||
                 !(ordinfo.PriceOpen() > highestBuyPendingPrice) )
                continue;
            highestBuyPendingTicket = (long)ordinfo.Ticket();
            highestBuyPendingPrice = ordinfo.PriceOpen();
        }
        if ( highestBuyPendingTicket != 0 ){
            if ( InpEnableAuditLog )
                PrintFormat("[AUDIT] Pruning worst Buy Pending #%I64d at %.2f (count %d > max %d)",
                            highestBuyPendingTicket, highestBuyPendingPrice, buyPendingCount, MaxPendingOrders);
            trade.OrderDelete(highestBuyPendingTicket);
            deletedBuyTicket = highestBuyPendingTicket;
            for (buyMapClearIdx = 0; buyMapClearIdx < 100; buyMapClearIdx = buyMapClearIdx + 1){
                if ( !(OrderPriceMap[buyMapClearIdx][0] == (double)deletedBuyTicket) ) continue;
                OrderPriceMap[buyMapClearIdx][0] = 0.0;
                OrderPriceMap[buyMapClearIdx][1] = 0.0;
                break;
            }
        }
    }

    //--- Scan Sell Pending Orders and prune worst if > MaxPendingOrders
    sellPendingCount = 0;
    for (sellPendingCountScanIdx = 0; ordinfo.SelectByIndex(sellPendingCountScanIdx); sellPendingCountScanIdx++){
        if ( ordinfo.Magic() != ActiveMagic ||
             ordinfo.Symbol() != TradeSym ||
             ordinfo.OrderType() != ORDER_TYPE_SELL_STOP )
            continue;
        sellPendingCount = sellPendingCount + 1;
    }

    if ( sellPendingCount > MaxPendingOrders ){
        lowestSellPendingPrice = DBL_MAX;
        lowestSellPendingTicket = 0;
        for (sellPendingWorstScanIdx = 0; ordinfo.SelectByIndex(sellPendingWorstScanIdx); sellPendingWorstScanIdx++){
            if ( ordinfo.Magic() != ActiveMagic ||
                 ordinfo.Symbol() != TradeSym ||
                 ordinfo.OrderType() != ORDER_TYPE_SELL_STOP ||
                 !(ordinfo.PriceOpen() < lowestSellPendingPrice) )
                continue;
            lowestSellPendingTicket = (long)ordinfo.Ticket();
            lowestSellPendingPrice = ordinfo.PriceOpen();
        }
        if ( lowestSellPendingTicket != 0 ){
            if ( InpEnableAuditLog )
                PrintFormat("[AUDIT] Pruning worst Sell Pending #%I64d at %.2f (count %d > max %d)",
                            lowestSellPendingTicket, lowestSellPendingPrice, sellPendingCount, MaxPendingOrders);
            trade.OrderDelete(lowestSellPendingTicket);
            deletedSellTicket = lowestSellPendingTicket;
            for (sellMapClearIdx = 0; sellMapClearIdx < 100; sellMapClearIdx = sellMapClearIdx + 1){
                if ( !(OrderPriceMap[sellMapClearIdx][0] == (double)deletedSellTicket) ) continue;
                OrderPriceMap[sellMapClearIdx][0] = 0.0;
                OrderPriceMap[sellMapClearIdx][1] = 0.0;
                break;
            }
        }
    }

    //--- Rescan TF entry burst
    if ( PerStrategyPendingRescanBars[stratIdx] != iBars(TradeSym, RescanTf) ){
        PerStrategyPendingRescanBars[stratIdx] = iBars(TradeSym, RescanTf);
        for (pendingLoopCounter = 0; pendingLoopCounter < MaxPendingOrders; pendingLoopCounter++){
            ProcessStrategyEntries();
        }
    }

    //--- Hourly cleanup of OrderPriceMap for closed orders
    if ( LastHour != nowDt.hour ){
        LastHour = nowDt.hour;
        orderMapEntryStillOpen = false;
        for (orderMapScanIdx = 0; orderMapScanIdx < 100; orderMapScanIdx = orderMapScanIdx + 1){
            mapStoredTicket = (long)OrderPriceMap[orderMapScanIdx][0];
            if ( mapStoredTicket == 0 ) continue;
            orderMapEntryStillOpen = false;
            for (orderMapTicketScanIdx = 0; posinfo.SelectByIndex(orderMapTicketScanIdx); orderMapTicketScanIdx++){
                currentScanTicket = (long)posinfo.Ticket();
                if ( mapStoredTicket != currentScanTicket ) continue;
                orderMapEntryStillOpen = true;
                break;
            }
            if ( !orderMapEntryStillOpen ){
                for (orderMapTicketScanIdx = 0; ordinfo.SelectByIndex(orderMapTicketScanIdx); orderMapTicketScanIdx++){
                    currentScanTicket = (long)ordinfo.Ticket();
                    if ( mapStoredTicket != currentScanTicket ) continue;
                    orderMapEntryStillOpen = true;
                    break;
                }
            }
            if ( orderMapEntryStillOpen ) continue;
            OrderPriceMap[orderMapScanIdx][0] = 0.0;
            OrderPriceMap[orderMapScanIdx][1] = 0.0;
        }
    }

    return(0);
}

//+------------------------------------------------------------------+
//| FindSwingPoint (Fractal Detection)                               |
//+------------------------------------------------------------------+
double FindSwingPoint(ENUM_TIMEFRAMES timeframe, bool findHigh) {
    bool        found = false;
    bool        leftOk = false;
    bool        rightOk = false;
    int         barIdx;
    int         rightScan;
    int         leftScan;
    double      candidateExtreme;
    int         candidateBar;
    double      historicalExtreme;
    int         histIdx;
    double      normalizedPrice;
    int         ordIdx;
    bool        dupFound;
    double      result;

    barIdx = FractalRight + 1;

    do{
        leftOk = true;
        rightOk = true;

        for (rightScan = barIdx; rightScan >= barIdx - FractalRight; rightScan--){
            if ( findHigh ? (iHigh(TradeSym, timeframe, rightScan) > iHigh(TradeSym, timeframe, barIdx)) :
                            (iLow(TradeSym, timeframe, rightScan) < iLow(TradeSym, timeframe, barIdx)) ){
                rightOk = false;
            }
        }

        for (leftScan = barIdx; leftScan <= barIdx + FractalLeft; leftScan++){
            if ( findHigh ? (iHigh(TradeSym, timeframe, leftScan) > iHigh(TradeSym, timeframe, barIdx)) :
                            (iLow(TradeSym, timeframe, leftScan) < iLow(TradeSym, timeframe, barIdx)) ){
                leftOk = false;
            }
        }

        if ( rightOk && leftOk && ( findHigh ?
            (iHigh(TradeSym, timeframe, barIdx) > FractalMinDist * PipFactor + SymbolInfoDouble(TradeSym, SYMBOL_ASK)) :
            (iLow(TradeSym, timeframe, barIdx) < SymbolInfoDouble(TradeSym, SYMBOL_BID) - FractalMinDist * PipFactor) ) ){

            candidateExtreme = findHigh ? iHigh(TradeSym, timeframe, barIdx) :
                                          iLow(TradeSym, timeframe, barIdx);

            candidateBar = barIdx;

            historicalExtreme = findHigh ? iHigh(TradeSym, FractalTf, 0) :
                                           iLow(TradeSym, FractalTf, 0);

            for (histIdx = 1; histIdx <= candidateBar; histIdx = histIdx + 1){
                if ( findHigh ? (iHigh(TradeSym, FractalTf, histIdx) > historicalExtreme) :
                                (iLow(TradeSym, FractalTf, histIdx) < historicalExtreme) ){
                    historicalExtreme = findHigh ? iHigh(TradeSym, FractalTf, histIdx) :
                                                   iLow(TradeSym, FractalTf, histIdx);
                }
            }

            if ( findHigh ? (candidateExtreme >= historicalExtreme) :
                            (candidateExtreme <= historicalExtreme) ){

                normalizedPrice = NormalizeDouble(candidateExtreme, SymDigits);
                dupFound = false;

                for (ordIdx = 0; ordinfo.SelectByIndex(ordIdx); ordIdx++){
                    if ( findHigh ){
                        if ( ordinfo.Magic() != ActiveMagic ||
                             ordinfo.Symbol() != TradeSym ||
                             ordinfo.OrderType() != ORDER_TYPE_BUY_STOP ||
                             !(MathAbs(ordinfo.PriceOpen() - (BuyEntryOffset * PipFactor + normalizedPrice)) < PendingDedupDist * PipFactor) )
                            continue;
                    }
                    else{
                        if ( ordinfo.Magic() != ActiveMagic ||
                             ordinfo.Symbol() != TradeSym ||
                             ordinfo.OrderType() != ORDER_TYPE_SELL_STOP ||
                             !(MathAbs(ordinfo.PriceOpen() - (normalizedPrice - SellEntryOffset * PipFactor)) < PendingDedupDist * PipFactor) )
                            continue;
                    }

                    dupFound = true;
                    break;
                }

                if ( !(dupFound) ){
                    found = true;
                    result = normalizedPrice;
                    if ( findHigh ){
                        SwingHigh = result;
                    }
                    else{
                        SwingLow = result;
                    }
                    break;
                }
            }
        }

        barIdx++;

        if ( barIdx <= FractalMaxSearch ) continue;

        if ( findHigh ){
            SwingHigh = 0.0;
        }
        else{
            SwingLow = 0.0;
        }
        break;

    }
    while(!(found));

    return( findHigh ? SwingHigh : SwingLow );
}

//+------------------------------------------------------------------+
//| CalculateLotSize (Part 3 Multi-Strategy Weighted Sizing)         |
//+------------------------------------------------------------------+
void CalculateLotSize() {
    double calculatedLots = StrategyLots[StrategyIdx];

    if ( Lotsizing_Method == Manual_Lotsize ){
        calculatedLots = SepLotSize ? SepStrategyLots[StrategyIdx] : FixedLots;
        if ( calculatedLots < SymbolInfoDouble(TradeSym, SYMBOL_VOLUME_MIN) ){
            calculatedLots = SymbolInfoDouble(TradeSym, SYMBOL_VOLUME_MIN);
        }
        StrategyLots[StrategyIdx] = calculatedLots;
        return;
    }

    double slDollars = SLDist * PipFactor;
    double riskDivisorValue = 0.0;

    if ( Lotsizing_Method == Tiered_Lotsizing ){
        WeightedRiskDivisor = TieredLotEff / DDTierDivisor;
        riskDivisorValue = WeightedRiskDivisor;
    }

    if ( Lotsizing_Method == RiskScaleFactor ){
        riskDivisorValue = RiskScaling;
    }

    if ( ( Lotsizing_Method == Tiered_Lotsizing || Lotsizing_Method == RiskScaleFactor ) && slDollars > 0.0 ){
        double effectiveBalance = (InpFixedBalance > 0.0) ? InpFixedBalance : AccountInfoDouble(ACCOUNT_BALANCE);
        calculatedLots = riskDivisorValue * effectiveBalance * 0.0001 * RiskWeight / slDollars;
    }

    if ( calculatedLots < SymbolInfoDouble(TradeSym, SYMBOL_VOLUME_STEP) ){
        calculatedLots = SymbolInfoDouble(TradeSym, SYMBOL_VOLUME_STEP);
    }

    if ( calculatedLots > MaxLotCap ){
        calculatedLots = MaxLotCap;
    }

    if ( calculatedLots < SymbolInfoDouble(TradeSym, SYMBOL_VOLUME_MIN) ){
        calculatedLots = SymbolInfoDouble(TradeSym, SYMBOL_VOLUME_MIN);
    }

    if ( calculatedLots > SymbolInfoDouble(TradeSym, SYMBOL_VOLUME_MAX) && SymbolInfoDouble(TradeSym, SYMBOL_VOLUME_MAX) != 0.0 ){
        calculatedLots = SymbolInfoDouble(TradeSym, SYMBOL_VOLUME_MAX);
    }

    if ( SymbolInfoDouble(TradeSym, SYMBOL_VOLUME_STEP) == 0.1 ){
        StrategyLots[StrategyIdx] = NormalizeDouble((MathFloor(calculatedLots * 10.0)) / 10.0, 1);
    }
    else{
        StrategyLots[StrategyIdx] = NormalizeDouble(MathFloor(calculatedLots * 100.0) / 100.0, 2);
    }

    if ( InpEnableAuditLog ){
        double effBal = (InpFixedBalance > 0.0) ? InpFixedBalance : AccountInfoDouble(ACCOUNT_BALANCE);
        PrintFormat("[LOT_AUDIT] Strat %d | Bal=%.2f | SLDist=%.2f | RawLots=%.4f | Lots=%.2f | RiskWeight=%.4f | ImpliedRisk=%.2f",
                    StrategyIdx + 1, effBal, slDollars, calculatedLots, StrategyLots[StrategyIdx], RiskWeight,
                    StrategyLots[StrategyIdx] * slDollars);
    }
}

//+------------------------------------------------------------------+
//| ProcessStrategyEntries                                           |
//+------------------------------------------------------------------+
void ProcessStrategyEntries() {
    int        expireIdx;
    datetime   nowTime;
    datetime   orderExpireTime;
    int        buyPosCount;
    int        buyPosScanIdx;
    int        buyPendDeleteIdx;
    int        sellPosCount;
    int        sellPosScanIdx;
    int        sellPendDeleteIdx;
    bool       deleteThisOrder;

    CalculateLotSize();

    if ( StrategyLots[StrategyIdx] > MaxLotCap ){
        StrategyLots[StrategyIdx] = MaxLotCap;
    }

    //--- Virtual Expiration handling
    if ( Virtual_expiration ){
        expireIdx = 0;
        while ( ordinfo.SelectByIndex(expireIdx) ){
            deleteThisOrder = false;
            if ( ordinfo.Magic() == ActiveMagic && ordinfo.Symbol() == TradeSym ){
                nowTime = TimeCurrent();
                orderExpireTime = ordinfo.TimeSetup() + PendingExpirySeconds;
                if ( nowTime >= orderExpireTime ){
                    if ( InpEnableAuditLog )
                        PrintFormat("[AUDIT] Pending order #%I64u expired (setup=%s, now=%s, limit=%ds)",
                                    ordinfo.Ticket(), TimeToString(ordinfo.TimeSetup()), TimeToString(nowTime), PendingExpirySeconds);
                    deleteThisOrder = trade.OrderDelete(ordinfo.Ticket());
                }
            }
            if ( !deleteThisOrder ) expireIdx++;
        }
    }

    //--- Count Buy Positions and enforce MaxPositions
    buyPosCount = 0;
    for (buyPosScanIdx = 0; posinfo.SelectByIndex(buyPosScanIdx); buyPosScanIdx++){
        if ( posinfo.Magic() != ActiveMagic ||
             posinfo.Symbol() != TradeSym ||
             posinfo.PositionType() != POSITION_TYPE_BUY )
            continue;
        buyPosCount = buyPosCount + 1;
    }

    if ( buyPosCount < MaxPositions ){
        PlaceEntry(true);
    }
    else{
        buyPendDeleteIdx = 0;
        while ( ordinfo.SelectByIndex(buyPendDeleteIdx) ){
            deleteThisOrder = false;
            if ( ordinfo.Magic() == ActiveMagic &&
                 ordinfo.Symbol() == TradeSym &&
                 ordinfo.OrderType() == ORDER_TYPE_BUY_STOP ){
                if ( InpEnableAuditLog )
                    PrintFormat("[AUDIT] Deleting Buy Stop #%I64u (MaxPositions reached: %d >= %d)",
                                ordinfo.Ticket(), buyPosCount, MaxPositions);
                deleteThisOrder = trade.OrderDelete(ordinfo.Ticket());
            }
            if ( !deleteThisOrder ) buyPendDeleteIdx++;
        }
    }

    //--- Count Sell Positions and enforce MaxPositions
    sellPosCount = 0;
    for (sellPosScanIdx = 0; posinfo.SelectByIndex(sellPosScanIdx); sellPosScanIdx++){
        if ( posinfo.Magic() != ActiveMagic ||
             posinfo.Symbol() != TradeSym ||
             posinfo.PositionType() != POSITION_TYPE_SELL )
            continue;
        sellPosCount = sellPosCount + 1;
    }

    if ( sellPosCount < MaxPositions ){
        PlaceEntry(false);
    }
    else{
        sellPendDeleteIdx = 0;
        while ( ordinfo.SelectByIndex(sellPendDeleteIdx) ){
            deleteThisOrder = false;
            if ( ordinfo.Magic() == ActiveMagic &&
                 ordinfo.Symbol() == TradeSym &&
                 ordinfo.OrderType() == ORDER_TYPE_SELL_STOP ){
                if ( InpEnableAuditLog )
                    PrintFormat("[AUDIT] Deleting Sell Stop #%I64u (MaxPositions reached: %d >= %d)",
                                ordinfo.Ticket(), sellPosCount, MaxPositions);
                deleteThisOrder = trade.OrderDelete(ordinfo.Ticket());
            }
            if ( !deleteThisOrder ) sellPendDeleteIdx++;
        }
    }
}

//+------------------------------------------------------------------+
//| ManageOrders (Position Management & Protection)                  |
//+------------------------------------------------------------------+
bool ManageOrders(bool isBuy) {
    bool      modified = false;
    bool      orderModified = false;
    double    effectiveSL;
    double    tpRefPrice;
    int       orderIdx;
    double    currentSL;
    double    currentTP;
    long      orderTicket;
    double    openPrice;
    double    orderLots;
    datetime  openTime;
    int       orderType;
    int       orderMagic;
    string    orderSymbol;
    double    entryRefPrice;
    int       digitsTemp;
    long      mapTicket;
    int       mapScanIdx;
    double    mapPrice;
    double    entryPriceForMap;
    long      newMapTicket;
    int       mapSlotIdx;
    long      adaptTrailTicket;
    double    adaptTrailDistParam;
    double    adaptTrailRefPrice;
    int       adaptTrailDirection;
    double    adaptTrailComputed;
    bool      adaptTrailFound;
    int       adaptTrailScanIdx;
    int       adaptTrailSaveScanIdx;
    double    newVSlValue;
    long      newVSlTicket;
    int       vSlSaveIdx;

    ulong closeDeviation = (ulong)(CurrSpread);

    effectiveSL = 0.0;
    tpRefPrice = 0.0;

    for (orderIdx = 0; posinfo.SelectByIndex(orderIdx); orderIdx++){
        modified = false;

        currentSL = NormalizeDouble(posinfo.StopLoss(), SymDigits);
        currentTP = NormalizeDouble(posinfo.TakeProfit(), SymDigits);
        orderTicket = (long)posinfo.Ticket();
        openPrice = NormalizeDouble(posinfo.PriceOpen(), SymDigits);
        orderLots = posinfo.Volume();
        openTime = (datetime)posinfo.Time();
        orderType = (int)posinfo.PositionType();
        orderMagic = (int)posinfo.Magic();
        orderSymbol = posinfo.Symbol();

        if ( orderType == (isBuy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL) &&
             orderMagic == ActiveMagic &&
             orderSymbol == TradeSym ){

            //--- 1. Initialize SL if missing
            if ( currentSL == 0.0 ){
                currentSL = isBuy ? NormalizeDouble(openPrice - SLDist * PipFactor, SymDigits) :
                                    NormalizeDouble(SLDist * PipFactor + openPrice, SymDigits);
                if ( InpEnableAuditLog )
                    PrintFormat("[AUDIT] PositionModify #%I64d | Reason: InitialSL | SL: 0 -> %.2f | TP: %.2f",
                                orderTicket, currentSL, currentTP);
                trade.PositionModify(orderTicket, currentSL, currentTP);
            }

            //--- 2. Initialize TP if missing
            if ( currentTP == 0.0 ){
                currentTP = isBuy ? NormalizeDouble(TPDist * PipFactor + openPrice, SymDigits) :
                                    NormalizeDouble(openPrice - TPDist * PipFactor, SymDigits);
                if ( InpEnableAuditLog )
                    PrintFormat("[AUDIT] PositionModify #%I64d | Reason: InitialTP | SL: %.2f | TP: 0 -> %.2f",
                                orderTicket, currentSL, currentTP);
                trade.PositionModify(orderTicket, currentSL, currentTP);
            }

            //--- 3. Lookup or record mapped entry reference price
            digitsTemp = SymDigits;
            mapTicket = orderTicket;
            mapPrice = 0.0;

            for (mapScanIdx = 0; mapScanIdx < 100; mapScanIdx = mapScanIdx + 1){
                if ( !(OrderPriceMap[mapScanIdx][0] == (double)mapTicket) ) continue;
                mapPrice = OrderPriceMap[mapScanIdx][1];
                break;
            }

            entryRefPrice = NormalizeDouble(mapPrice, digitsTemp);

            if ( entryRefPrice == 0.0 ){
                entryPriceForMap = openPrice;
                newMapTicket = orderTicket;
                for (mapSlotIdx = 0; mapSlotIdx < 100; mapSlotIdx = mapSlotIdx + 1){
                    if ( !(OrderPriceMap[mapSlotIdx][0] == 0.0) ) continue;
                    OrderPriceMap[mapSlotIdx][0] = (double)newMapTicket;
                    OrderPriceMap[mapSlotIdx][1] = entryPriceForMap;
                    break;
                }
                entryRefPrice = openPrice;
            }

            tpRefPrice = entryRefPrice;

            //--- 4. Spread-adjusted SL modification
            double spreadSL = isBuy ? NormalizeDouble(openPrice - SLDist * PipFactor - CurrSpread, SymDigits) :
                                      NormalizeDouble(SLDist * PipFactor + openPrice + CurrSpread, SymDigits);
            bool spreadSlNeedsMod = isBuy ? (spreadSL > currentSL + Point() / 2.0) :
                                            (spreadSL < currentSL - Point() / 2.0);
            if ( spreadSlNeedsMod ){
                double oldSL = currentSL;
                currentSL = spreadSL;
                if ( InpEnableAuditLog )
                    PrintFormat("[AUDIT] PositionModify #%I64d | Reason: SpreadAdjSL | SL: %.2f -> %.2f | CurrSpread: %.2f",
                                orderTicket, oldSL, currentSL, CurrSpread);
                trade.PositionModify(orderTicket, currentSL, currentTP);
            }

            //--- 5. Spread-adjusted SL market close
            if ( isBuy ? (SymbolInfoDouble(TradeSym, SYMBOL_BID) < openPrice - SLDist * PipFactor - CurrSpread) :
                         (SymbolInfoDouble(TradeSym, SYMBOL_ASK) > SLDist * PipFactor + openPrice + CurrSpread) ){
                if ( InpEnableAuditLog )
                    PrintFormat("[AUDIT] PositionClose #%I64d | Reason: SpreadSLHit | Quote: %.2f | Thresh: %.2f",
                                orderTicket,
                                isBuy ? SymbolInfoDouble(TradeSym, SYMBOL_BID) : SymbolInfoDouble(TradeSym, SYMBOL_ASK),
                                isBuy ? (openPrice - SLDist * PipFactor - CurrSpread) : (SLDist * PipFactor + openPrice + CurrSpread));
                trade.PositionClose(orderTicket, closeDeviation);
                return(true);
            }

            //--- 6. Virtual SL store lookup
            adaptTrailTicket = orderTicket;
            adaptTrailDistParam = SLDist;
            adaptTrailRefPrice = openPrice;
            adaptTrailDirection = isBuy ? 1 : 2;
            adaptTrailComputed = 0.0;
            adaptTrailFound = false;

            for (adaptTrailScanIdx = 0; adaptTrailScanIdx < VirtualSLStoreSize; adaptTrailScanIdx++){
                if ( VirtualSLStore[adaptTrailScanIdx][0] == (double)adaptTrailTicket ){
                    adaptTrailComputed = VirtualSLStore[adaptTrailScanIdx][1];
                    adaptTrailFound = true;
                    break;
                }
            }

            if ( !(adaptTrailFound) ){
                if ( adaptTrailDirection == 1 ){
                    adaptTrailComputed = NormalizeDouble(adaptTrailRefPrice - adaptTrailDistParam * PipFactor, SymDigits);
                }
                if ( adaptTrailDirection == 2 ){
                    adaptTrailComputed = NormalizeDouble(adaptTrailDistParam * PipFactor + adaptTrailRefPrice, SymDigits);
                }

                for (adaptTrailSaveScanIdx = 0; adaptTrailSaveScanIdx < VirtualSLStoreSize; adaptTrailSaveScanIdx++){
                    if ( VirtualSLStore[adaptTrailSaveScanIdx][0] == 0.0 ){
                        VirtualSLStore[adaptTrailSaveScanIdx][0] = (double)adaptTrailTicket;
                        VirtualSLStore[adaptTrailSaveScanIdx][1] = adaptTrailComputed;
                        break;
                    }
                }
            }

            VirtualSL = adaptTrailComputed;
            effectiveSL = VirtualSL;

            //--- 7. Virtual SL market close
            if ( isBuy ? (SymbolInfoDouble(TradeSym, SYMBOL_BID) < effectiveSL) :
                         (SymbolInfoDouble(TradeSym, SYMBOL_ASK) > effectiveSL) ){
                if ( InpEnableAuditLog )
                    PrintFormat("[AUDIT] PositionClose #%I64d | Reason: VirtualSLHit | Quote: %.2f | VirtualSL: %.2f",
                                orderTicket,
                                isBuy ? SymbolInfoDouble(TradeSym, SYMBOL_BID) : SymbolInfoDouble(TradeSym, SYMBOL_ASK),
                                effectiveSL);
                trade.PositionClose(orderTicket, closeDeviation);
                return(true);
            }

            double Bid = SymbolInfoDouble(TradeSym, SYMBOL_BID);
            double Ask = SymbolInfoDouble(TradeSym, SYMBOL_ASK);

            //--- 8. Adaptive Trailing SL
            if ( TrailDist > 0.0 && ( isBuy ?
                (Bid > (TrailDist + TrailStep) * PipFactor + currentSL &&
                 Bid > TrailMinProfit * PipFactor + tpRefPrice &&
                 Bid < currentTP - FreezeLevelDist &&
                 currentSL < TrailMaxSL * PipFactor + openPrice) :

                (Ask < currentSL - (TrailDist + TrailStep) * PipFactor &&
                 Ask < tpRefPrice - TrailMinProfit * PipFactor &&
                 Ask > currentTP + FreezeLevelDist &&
                 currentSL > openPrice - TrailMaxSL * PipFactor)
            )){
                double newSL = isBuy ? NormalizeDouble(Bid - TrailDist * PipFactor, SymDigits) :
                                       NormalizeDouble(Ask + TrailDist * PipFactor, SymDigits);

                bool slImproved = isBuy ? (newSL > currentSL + Point() / 2.0) :
                                          (newSL < currentSL - Point() / 2.0);

                if ( slImproved && (isBuy ? (newSL < Bid - StopLevelDist) : (newSL > Ask + StopLevelDist)) ){
                    if ( InpEnableAuditLog )
                        PrintFormat("[AUDIT] PositionModify #%I64d | Reason: TrailSL | SL: %.2f -> %.2f | Price: %.2f",
                                    orderTicket, currentSL, newSL, isBuy ? Bid : Ask);
                    currentSL = newSL;
                    trade.PositionModify(orderTicket, currentSL, currentTP);
                    modified = true;
                }
            }

            //--- 9. Salvage Exit TP Modification
            if ( SalvageExitDist > 0.0 && ( isBuy ?
                (Ask < currentTP - SalvageExitDist * PipFactor &&
                 Ask < tpRefPrice - SalvageTrigger * PipFactor &&
                 Bid < currentTP - FreezeLevelDist) :

                (Bid > currentTP + SalvageExitDist * PipFactor &&
                 Bid > tpRefPrice + SalvageTrigger * PipFactor &&
                 Ask > currentTP + FreezeLevelDist)
            )){
                double sellSalvagePrice = SymbolInfoDouble(TradeSym, SYMBOL_BID);

                double newTP = isBuy ? NormalizeDouble(SymbolInfoDouble(TradeSym, SYMBOL_BID) + SalvageExitDist * PipFactor, SymDigits) :
                                       NormalizeDouble(sellSalvagePrice - SalvageExitDist * PipFactor, SymDigits);

                bool salvageValid = isBuy ? (newTP > Bid + StopLevelDist) :
                                            (newTP < Ask - StopLevelDist);

                if ( salvageValid ){
                    if ( InpEnableAuditLog )
                        PrintFormat("[AUDIT] PositionModify #%I64d | Reason: SalvageTP | TP: %.2f -> %.2f | tpRefPrice: %.2f",
                                    orderTicket, currentTP, newTP, tpRefPrice);
                    currentTP = newTP;
                    trade.PositionModify(orderTicket, currentSL, currentTP);
                    modified = true;
                }
            }

            //--- 10. Breakeven SL (fixed: normalize before comparing against currentSL to eliminate invalid stops)
            if ( BeTrigger > 0.0 && ( isBuy ?
                (Bid > BeTrigger * PipFactor + openPrice &&
                 Bid > BeLockDist * PipFactor + openPrice + StopLevelDist &&
                 Bid < currentTP - FreezeLevelDist) :

                (Ask < openPrice - BeTrigger * PipFactor &&
                 Ask < openPrice - BeLockDist * PipFactor - StopLevelDist &&
                 Ask > currentTP + FreezeLevelDist)
            )){
                double newSL = isBuy ? NormalizeDouble(BeLockDist * PipFactor + openPrice, SymDigits) :
                                       NormalizeDouble(openPrice - BeLockDist * PipFactor, SymDigits);

                bool slImproved = isBuy ? (newSL > currentSL + Point() / 2.0) :
                                          (newSL < currentSL - Point() / 2.0);

                if ( slImproved && (isBuy ? (newSL < Bid - StopLevelDist) : (newSL > Ask + StopLevelDist)) ){
                    if ( InpEnableAuditLog )
                        PrintFormat("[AUDIT] PositionModify #%I64d | Reason: Breakeven | SL: %.2f -> %.2f | LockDist: %.2f",
                                    orderTicket, currentSL, newSL, BeLockDist * PipFactor);
                    currentSL = newSL;
                    trade.PositionModify(orderTicket, currentSL, currentTP);
                    modified = true;
                }
            }

            //--- 11. Market close if price touches currentSL
            VirtualSL = currentSL;

            if ( isBuy ? (SymbolInfoDouble(TradeSym, SYMBOL_BID) < currentSL) :
                         (SymbolInfoDouble(TradeSym, SYMBOL_ASK) > currentSL) ){
                if ( InpEnableAuditLog )
                    PrintFormat("[AUDIT] PositionClose #%I64d | Reason: TrailedSLHit | Quote: %.2f | SL: %.2f",
                                orderTicket,
                                isBuy ? SymbolInfoDouble(TradeSym, SYMBOL_BID) : SymbolInfoDouble(TradeSym, SYMBOL_ASK),
                                currentSL);
                trade.PositionClose(orderTicket, closeDeviation);
                return(true);
            }

            //--- 12. Update VirtualSLStore if changed
            if ( NormalizeDouble(effectiveSL, SymDigits) != NormalizeDouble(VirtualSL, SymDigits) ){
                newVSlValue = NormalizeDouble(VirtualSL, SymDigits);
                newVSlTicket = orderTicket;

                for (vSlSaveIdx = 0; vSlSaveIdx < VirtualSLStoreSize; vSlSaveIdx = vSlSaveIdx + 1){
                    if ( VirtualSLStore[vSlSaveIdx][0] == (double)newVSlTicket ){
                        VirtualSLStore[vSlSaveIdx][1] = newVSlValue;
                        break;
                    }
                }
            }

            if ( modified ){
                orderModified = true;
            }
        }
    }

    return(orderModified);
}

//+------------------------------------------------------------------+
//| PlaceEntry                                                       |
//+------------------------------------------------------------------+
bool PlaceEntry(bool isBuy) {
    bool swingFound;
    double entryPrice;
    double slippageEntryPrice;
    double slPrice;
    double tpPrice;
    double swingPrice;
    int pendIdx;
    bool dupFound;
    int pendCount;
    int pendCountIdx;
    double worstPendingPrice;
    int pendScanIdx;
    double entryPriceCheck;
    int pendScanIdx2;
    bool betterPendingExists;
    bool volumeValid;
    int maxOrdersLimit;
    bool orderLimitOk;
    int lastErrorCode;
    double filledEntryPrice;
    long newTicket;
    ENUM_ORDER_TYPE_TIME pendTimeType;
    int mapSlot;
    int pendType;

    pendType = (int)(isBuy ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP);

    if ( isBuy ){
        FindSwingPoint(FractalTf, true);
        swingPrice = SwingHigh;
    }
    else{
        FindSwingPoint(FractalTf, false);
        swingPrice = SwingLow;
    }

    swingFound = false;
    dupFound = false;

    for (pendIdx = 0; ordinfo.SelectByIndex(pendIdx); pendIdx = pendIdx + 1){
        if ( ordinfo.Magic() != ActiveMagic ||
             ordinfo.Symbol() != TradeSym ||
             (int)ordinfo.OrderType() != pendType ||
             !(MathAbs(ordinfo.PriceOpen() - (isBuy ? (BuyEntryOffset * PipFactor + swingPrice) :
                      (swingPrice - SellEntryOffset * PipFactor))) < PendingDedupDist * PipFactor) )
            continue;
        dupFound = true;
        break;
    }

    if ( !(dupFound) ){
        pendCount = 0;

        for (pendCountIdx = 0; ordinfo.SelectByIndex(pendCountIdx); pendCountIdx = pendCountIdx + 1){
            if ( ordinfo.Magic() != ActiveMagic ||
                 ordinfo.Symbol() != TradeSym ||
                 (int)ordinfo.OrderType() != pendType )
                continue;
            pendCount = pendCount + 1;
        }

        if ( pendCount == MaxPendingOrders ){
            worstPendingPrice = isBuy ? DBL_MAX : 0.0;
            for (pendScanIdx = 0; ordinfo.SelectByIndex(pendScanIdx); pendScanIdx = pendScanIdx + 1){
                if ( ordinfo.Magic() != ActiveMagic ||
                     ordinfo.Symbol() != TradeSym ||
                     (int)ordinfo.OrderType() != pendType ||
                     (isBuy ? !(ordinfo.PriceOpen() < worstPendingPrice) :
                              !(ordinfo.PriceOpen() > worstPendingPrice)) )
                    continue;
                worstPendingPrice = ordinfo.PriceOpen();
            }
            if ( isBuy ){
                if ( SwingHigh > worstPendingPrice ){
                    return(false);
                }
            }
            else{
                if ( SwingLow < worstPendingPrice ){
                    return(false);
                }
            }
        }

        if ( isBuy ){
            swingFound = true;
            LastSwingHigh = NormalizeDouble(SwingHigh, SymDigits);
        }
        else{
            swingFound = true;
            LastSwingLow = NormalizeDouble(SwingLow, SymDigits);
        }
    }

    if ( isBuy ){
        if ( LastSwingHigh == 0.0 ){
            return(false);
        }
    }
    else{
        if ( LastSwingLow == 0.0 ){
            return(false);
        }
    }

    if ( swingFound ){
        if ( isBuy ){
            entryPrice = NormalizeDouble(LastSwingHigh + BuyEntryOffset * PipFactor, SymDigits);
        }
        else{
            entryPrice = NormalizeDouble(LastSwingLow - SellEntryOffset * PipFactor, SymDigits);
        }

        entryPriceCheck = entryPrice;
        betterPendingExists = false;

        for (pendScanIdx2 = 0; ordinfo.SelectByIndex(pendScanIdx2); pendScanIdx2 = pendScanIdx2 + 1){
            if ( ordinfo.Magic() != ActiveMagic ||
                 ordinfo.Symbol() != TradeSym ||
                 (int)ordinfo.OrderType() != pendType ||
                 (isBuy ? !(ordinfo.PriceOpen() <= entryPriceCheck) :
                          !(ordinfo.PriceOpen() >= entryPriceCheck)) )
                continue;
            betterPendingExists = true;
            break;
        }

        if ( betterPendingExists ){
            return(false);
        }

        ENUM_ORDER_TYPE marginOrderType = (isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
        double marginPrice = (isBuy ? SymbolInfoDouble(TradeSym, SYMBOL_ASK) :
                                      SymbolInfoDouble(TradeSym, SYMBOL_BID));
        double marginRequired = 0.0;

        if ( !OrderCalcMargin(marginOrderType, TradeSym, StrategyLots[StrategyIdx], marginPrice, marginRequired) ||
             AccountInfoDouble(ACCOUNT_MARGIN_FREE) - marginRequired <= 0.0 ){
            return(false);
        }

        if ( isBuy ){
            slippageEntryPrice = entryPrice;
            slPrice = NormalizeDouble(entryPrice - SLDist * PipFactor, SymDigits);
            tpPrice = NormalizeDouble(TPDist * PipFactor + entryPrice, SymDigits);
        }
        else{
            slippageEntryPrice = entryPrice;
            slPrice = NormalizeDouble(SLDist * PipFactor + entryPrice, SymDigits);
            tpPrice = NormalizeDouble(entryPrice - TPDist * PipFactor, SymDigits);
        }

        if ( StrategyLots[StrategyIdx] < SymbolInfoDouble(TradeSym, SYMBOL_VOLUME_MIN) ){
            volumeValid = false;
        }
        else{
            if ( StrategyLots[StrategyIdx] > SymbolInfoDouble(TradeSym, SYMBOL_VOLUME_MAX) ){
                volumeValid = false;
            }
            else{
                if ( MathAbs(NormalizeDouble(StrategyLots[StrategyIdx] / SymbolInfoDouble(TradeSym, SYMBOL_VOLUME_STEP), 0) *
                             SymbolInfoDouble(TradeSym, SYMBOL_VOLUME_STEP) - StrategyLots[StrategyIdx]) > 0.0000001 ){
                    volumeValid = false;
                }
                else{
                    volumeValid = true;
                }
            }
        }

        maxOrdersLimit = (int)AccountInfoInteger(ACCOUNT_LIMIT_ORDERS);
        if ( maxOrdersLimit == 0 ){
            orderLimitOk = true;
        }
        else{
            orderLimitOk = (PositionsTotal() + OrdersTotal()) < maxOrdersLimit;
        }

        if ( !(volumeValid) || !(orderLimitOk) ){
            return(false);
        }

        double fzDist = FreezeLevelDist;
        double stDist = StopLevelDist;

        if ( ( isBuy ? (SymbolInfoDouble(TradeSym, SYMBOL_ASK) < slippageEntryPrice - fzDist &&
                        SymbolInfoDouble(TradeSym, SYMBOL_ASK) < slippageEntryPrice - stDist) :

                       (SymbolInfoDouble(TradeSym, SYMBOL_BID) > fzDist + slippageEntryPrice &&
                        SymbolInfoDouble(TradeSym, SYMBOL_BID) > stDist + slippageEntryPrice) ) ){

            trade.SetExpertMagicNumber(ActiveMagic);
            trade.SetTypeFilling(ORDER_FILLING_RETURN);

            if ( PendingExpiryHrs > 0 ){
                PendingExpiry = TimeCurrent() + PendingExpirySeconds;
            }
            else{
                PendingExpiry = 0;
            }
            if ( Virtual_expiration ){
                PendingExpiry = 0;
            }

            pendTimeType = (PendingExpiry > 0) ? ORDER_TIME_SPECIFIED : ORDER_TIME_GTC;

            if ( trade.OrderOpen(TradeSym, isBuy ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP, StrategyLots[StrategyIdx], 0, slippageEntryPrice,
                                slPrice, tpPrice, pendTimeType, PendingExpiry, ActiveComment) ){
                LastTradeTicket = (int)trade.ResultOrder();
                if ( InpEnableAuditLog )
                    PrintFormat("[AUDIT] Placed %s Stop #%d | Vol: %.2f | Price: %.2f | SL: %.2f | TP: %.2f | Magic: %d",
                                isBuy ? "BUY" : "SELL", LastTradeTicket, StrategyLots[StrategyIdx], slippageEntryPrice, slPrice, tpPrice, ActiveMagic);
            }
            else{
                LastTradeTicket = -1;
            }

            if ( LastTradeTicket <= 0 ){
                lastErrorCode = GetLastError();
                if ( lastErrorCode == 132 ){
                    ResetLastError();
                }
            }
            else{
                filledEntryPrice = entryPrice;
                newTicket = LastTradeTicket;

                for (mapSlot = 0; mapSlot < 100; mapSlot = mapSlot + 1){
                    if ( !(OrderPriceMap[mapSlot][0] == 0.0) ) continue;
                    OrderPriceMap[mapSlot][0] = (double)newTicket;
                    OrderPriceMap[mapSlot][1] = filledEntryPrice;
                    break;
                }
            }
        }
        return(true);
    }
    return(false);
}
//+------------------------------------------------------------------+
