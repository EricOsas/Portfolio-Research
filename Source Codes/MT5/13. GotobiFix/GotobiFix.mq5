// GotobiFix.mq5 - strategy information
#property copyright "Copyright 2026-2027, Osamwonyi Eric (@You_FoundEric)"
#property link "https://x.com/You_FoundEric"
#property version "1.00"
#property description "Gotobi Fix: long JPY-cross into the 09:55 Tokyo fix, short 09:55-10:30 Tokyo, on Japanese gotobi settlement days."
#property description "USDJPY / EURJPY / GBPJPY, one chart per pair. Clock-only exits, fixed lots, no stop or target by rule."
#property description "Developed by Osamwonyi Eric (@You_FoundEric)."
#property description "Unauthorized redistribution prohibited."
#property strict

#include "StrategyEngine.mqh"

input group "==========  1 - Trading  =========="
input bool   EnableTrading   = true;            // Enable trading (false = manage/flatten only)
input group " "
input group "==========  2 - Legs & Size  =========="
enum GF_LEGS { GF_LEGS_BOTH=0, GF_LEGS_LONG=1, GF_LEGS_SHORT=2 };
input GF_LEGS Legs            = GF_LEGS_BOTH;  // Legs: both / long into the fix / short after it
input double Lots            = 0.10;            // Fixed lots per pair (PDF reference: 1.00 on a 100k account)
input double MaxExposureLots = 1.00;            // Exposure guard: owned lots + new entry may not exceed this
input group "  "
input group "==========  3 - Broker Clock  =========="
input string ExtraHolidays   = "";              // Official extra Japanese bank holidays, YYYYMMDD comma-separated
input group "   "
input group "==========  4 - Protection & Guards (0 = off, rule parity)  =========="
input double DisasterStopPips     = 0.0;        // Catastrophic broker-side stop in pips (0 = none, as per rule)
input double MaxFloatingLossMoney = 0.0;        // Close and block the day if owned floating P/L <= -value
input double MaxEntrySpreadPips   = 0.0;        // Skip entry while spread above this
input int    MaxLateEntrySec      = 0;          // Skip a leg entered later than this after its window opens
input group "    "
input group "==========  5 - Execution & Logging  =========="
input long   Magic           = 26111701;        // Strategy magic number (unique per chart/pair)
input int    DeviationPts    = 30;              // Maximum market-order deviation (points)
input string JournalFile     = "gotobifix_trades"; // Common\Files journal (.csv appended)
input bool   AllowOtherSymbols = false;         // Allow symbols other than USDJPY/EURJPY/GBPJPY
input group "     "
input group "==========  6 - Display  =========="
input bool   ShowPanel       = true;            // Show information panel

#include "ExecutionRuntime.mqh"
#include "ChartVisuals.mqh"

int OnInit()
{
   int r=GfRuntimeInit();
   if(r!=INIT_SUCCEEDED) { GfLeaseRelease(); return r; }
   ResetLastError();
   if(!EventSetTimer(1)) { PrintFormat("GF_INIT_FAIL timer error=%d",GetLastError()); GfLeaseRelease(); return INIT_FAILED; }
   GfPanelStart(); GfPanelRefresh();
   return INIT_SUCCEEDED;
}
bool GfClockFatal()                              // tester only: a clock that can never resolve ends the run with one clear message
{
   if(!ClkGaveUp()) return false;
   Print("GF_STOPPED the broker clock cannot be resolved in the tester (",ClkNote(),"). See the CLK_GIVE_UP line above for the fix.");
   ExpertRemove();
   return true;
}
void OnTick()
{
   GfProcess();
   if(GfClockFatal()) return;
   GfPanelRefresh();
}
void OnTimer()
{
   if(!MQLInfoInteger(MQL_TESTER))
   {
      // Timer manages exits, recovery and unprocessed fresh quotes; cached/offline prices never create entries (GfQuoteFresh).
      GfProcess();
   }
   if(GfClockFatal()) return;
   GfPanelRefresh();
}
void OnTradeTransaction(const MqlTradeTransaction &transaction,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   // Mark history dirty first: HistorySelect may fail or lag behind the transaction.
   if(transaction.symbol==_Symbol || transaction.type==TRADE_TRANSACTION_HISTORY_ADD || transaction.type==TRADE_TRANSACTION_DEAL_ADD)
   { gfTxDirty=true; gfPanelDirty=true; }
}
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(id==CHARTEVENT_OBJECT_CLICK && sparam==gfPanelPrefix+"BTN")
   { gfPanelCollapsed=!gfPanelCollapsed; gfPanelDirty=true; GfPanelRefresh(); ChartRedraw(0); }
}
double OnTester()
{
   PrintFormat("GF_RESEARCH_RESULT trades=%.0f profit=%.2f pf=%.6f equity_dd_pct=%.6f clock=%s",
               TesterStatistics(STAT_TRADES),TesterStatistics(STAT_PROFIT),TesterStatistics(STAT_PROFIT_FACTOR),
               TesterStatistics(STAT_EQUITY_DDREL_PERCENT),ClkText());
   return TesterStatistics(STAT_PROFIT);
}
void OnDeinit(const int reason)
{
   EventKillTimer();
   GfPanelStop();
   GfLeaseRelease();
}
