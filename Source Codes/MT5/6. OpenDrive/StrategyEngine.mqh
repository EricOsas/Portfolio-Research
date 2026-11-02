//+------------------------------------------------------------------+
//|                                               StrategyEngine.mqh |
//|                       OpenDrive — Nasdaq 9:30 AM Cash Open Drive |
//+------------------------------------------------------------------+
#ifndef OPENDRIVE_STRATEGY_ENGINE
#define OPENDRIVE_STRATEGY_ENGINE

#property copyright "OpenDrive"
#property version   "5.00"
#property strict

//+------------------------------------------------------------------+
//| Strategy Enums                                                   |
//+------------------------------------------------------------------+
enum ENUM_RISK_MODE
{
   RISK_DYNAMIC_VOLATILITY = 0, // Dynamic Strength Scaling (Prop Firms: 0.33% / 0.50% / 1.00%)
   RISK_STATIC_FIXED       = 1  // Static Fixed Risk (Live Accounts: Fixed % per trade)
};

enum ENUM_ATR_MODE
{
   ATR_MT5    = 0, // MT5 Standard iATR (SMA)
   ATR_WILDER = 1  // Wilder RMA ATR (TradingView / Research Standard)
};

enum ENUM_NEWS_IMPACT
{
   NEWS_DISABLED   = 0, // Off
   NEWS_RED_ONLY   = 1, // Red folder only (High impact)
   NEWS_RED_YELLOW = 2, // Red and Orange/Medium folders
   NEWS_ALL        = 3  // All news folders
};

enum ENUM_NEWS_WINDOW
{
   NEWS_WINDOW_5  = 5,  // 5 min total: 2m30s before / after
   NEWS_WINDOW_10 = 10, // 10 min total: 5m before / after
   NEWS_WINDOW_14 = 14, // 14 min total: 7m before / after
   NEWS_WINDOW_20 = 20  // 20 min total: 10m before / after
};

//+------------------------------------------------------------------+
//| Input Parameters: Standard Numbered Sectioning                   |
//+------------------------------------------------------------------+

input group "==========  1 - Trading  =========="
input bool             EnableTrading       = true;  // Enable new entries (open trades stay protected when off)
input bool             AllowLong           = true;  // Allow Long entries
input bool             AllowShort          = true;  // Allow Short entries
input bool             BlockOpposingExposure = true; // Block opposing same-symbol / equity-index exposure

input group " "
input group "==========  2 - Risk & Sizing  =========="
input ENUM_RISK_MODE   RiskMode            = RISK_DYNAMIC_VOLATILITY; // Sizing Mode (Dynamic for Prop, Static for Live)
input double           RiskPercent         = 1.0;   // Maximum Risk % per trade (0.5% - 1.0%)
input double           RiskMoney           = 0.0;   // Fixed Dollar Risk per trade (0 = use RiskPercent)
input bool             UseFixedLots        = false; // Use fixed contracts instead of % risk
input double           FixedLots           = 1.0;   // Contract quantity when fixed sizing enabled
input bool             AllowMinLotFallback = true;  // Execute broker min lot if calculated lot is below minimum
input double           DailyLossLimitPct   = 0.0;   // Daily loss lock % of day-start balance (0 = off)

input group "  "
input group "==========  3 - Signal Core  =========="
input int              EmaPeriod           = 12;    // Opening Signal EMA (M5 close)
input int              EntryHourNY         = 9;     // Cash open hour (New York)
input int              EntryMinNY          = 30;    // Cash open minute (New York)

input group "   "
input group "==========  4 - Stops & Trailing  =========="
input int              AtrPeriod           = 14;    // Volatility ATR period
input ENUM_ATR_MODE    AtrMode             = ATR_WILDER; // ATR Calculation Mode
input double           StopATR             = 4.0;   // Hard stop distance (x ATR from fill)
input double           ActivateATR         = 0.25;  // Profit confirmation before trail (x ATR)
input double           TrailATR            = 3.0;   // Chandelier trailing distance (x ATR behind extreme)
input bool             FlatAtExit          = true;  // Close flat before session close (no overnight gap)
input int              ExitHourNY          = 16;    // Session exit hour (16:00 NY Cash Close)
input int              ExitMinNY           = 0;     // Session exit minute

input group "    "
input group "==========  5 - Costs & Execution  =========="
input int              BrokerServerGMTOffset = 99;    // Server GMT offset in Winter (99 = Auto-detect from chart)
input int              MaxSpreadPoints     = 0;     // Max allowed spread in points (0 = off)
input int              SlippagePoints      = 3;     // Slippage allowance in points
input double           CommissionPerLot    = 7.0;   // Fallback round-trip commission per lot ($)
input ulong            MagicNumber         = 93093001; // EA Magic Number
input string           TradeComment        = "OpenDrive"; // Trade Comment

input group "     "
input group "==========  6 - Display & Visuals  =========="
input bool             ShowVisuals         = true;  // Draw chart lines & markers
input bool             ShowPanel           = true;  // Display floating HUD panel
input bool             ShowExtras          = false; // Diagnostic signal boxes & arrows
input bool             WriteLog            = true;  // Print journal decision log

input group "      "
input group "==========  7 - News Guard  =========="
input string           News_WebRequest_URL     = "https://nfs.faireconomy.media"; // WebRequest URL (copy to MT5 Options)
input ENUM_NEWS_IMPACT News_Impact             = NEWS_RED_ONLY; // News impact filter (USD)
input ENUM_NEWS_WINDOW News_Window             = NEWS_WINDOW_10; // Blackout window around release
input bool             News_Cost_Covered_BE    = true;  // Move stop to cost-covered BE if in profit before news
input bool             News_Flatten_Before     = false; // Close position before news (strict prop rule)
input bool             News_Block_Modification = true;  // Block trade modifications during blackout (prop rule)

//+------------------------------------------------------------------+
//| New York Time & Daylight Saving Time Conversion                  |
//+------------------------------------------------------------------+
datetime MakeDT(int year, int mon, int day, int hour, int minute, int sec)
{
   MqlDateTime dt; ZeroMemory(dt);
   dt.year = year; dt.mon = mon; dt.day = day; dt.hour = hour; dt.min = minute; dt.sec = sec;
   return StructToTime(dt);
}

int NthSundayOfMonth(int year, int month, int nth)
{
   MqlDateTime dt; ZeroMemory(dt);
   dt.year = year; dt.mon = month; dt.day = 1;
   datetime firstDay = StructToTime(dt);
   TimeToStruct(firstDay, dt);
   int firstDow = dt.day_of_week;
   int firstSunday = 1 + ((7 - firstDow) % 7);
   return firstSunday + (nth - 1) * 7;
}

int NYUTCOffsetSeconds(datetime utcTime)
{
   MqlDateTime utc; TimeToStruct(utcTime, utc);
   int year = utc.year;
   int marchSunday    = NthSundayOfMonth(year, 3, 2);
   int novemberSunday = NthSundayOfMonth(year, 11, 1);

   MqlDateTime startUtc; ZeroMemory(startUtc);
   startUtc.year = year; startUtc.mon = 3;  startUtc.day = marchSunday;    startUtc.hour = 7;
   MqlDateTime endUtc;   ZeroMemory(endUtc);
   endUtc.year = year;   endUtc.mon = 11; endUtc.day = novemberSunday;   endUtc.hour = 6;

   datetime dstStart = StructToTime(startUtc);
   datetime dstEnd   = StructToTime(endUtc);
   return (utcTime >= dstStart && utcTime < dstEnd) ? -4 * 3600 : -5 * 3600;
}

int TesterAnchorOffsetSec(datetime atServer)
{
   if(atServer == 0) atServer = TimeCurrent();
   static datetime cachedWeek[6];
   static int cachedOffset[6];
   static int nextCache = 0;

   for(int c = 0; c < 6; c++)
   {
      if(cachedWeek[c] > 0 && atServer >= cachedWeek[c] && atServer < cachedWeek[c] + 7 * 86400)
         return cachedOffset[c];
   }

   // 1. Manual User Broker Offset Override (if supplied)
   if(BrokerServerGMTOffset != 99)
   {
      int srvUTC = BrokerServerGMTOffset * 3600;
      int nyOff  = NYUTCOffsetSeconds(atServer - srvUTC);
      int bDst   = (nyOff == -4 * 3600) ? 3600 : 0;
      return (srvUTC + bDst) - nyOff;
   }

   // 2. Universal Friday Close Market Anchor (Broker-Agnostic)
   // US Index and Equity markets close globally on Friday at 17:00 New York.
   int first = iBarShift(_Symbol, PERIOD_H1, atServer, false);
   if(first < 0 || iTime(_Symbol, PERIOD_H1, first) <= 0) return -999999;

   datetime newer = 0;
   for(int i = first; i < first + 500; i++)
   {
      datetime t = iTime(_Symbol, PERIOD_H1, i);
      if(t <= 0) break;
      if(newer > 0 && (newer - t) >= 40 * 3600)
      {
         datetime weekOpenServer  = newer;
         datetime weekCloseServer = t;
         MqlDateTime co; TimeToStruct(weekCloseServer, co);
         MqlDateTime op; TimeToStruct(weekOpenServer, op);
         if(co.day_of_week != 5 || (op.day_of_week != 0 && op.day_of_week != 1)) { newer = t; continue; }

         // The last H1 bar of Friday closes at weekCloseServer + 3600.
         datetime fridayCloseServer = weekCloseServer + 3600;
         int srvCloseSecDay = (int)((long)fridayCloseServer % 86400);
         int nyCloseSecDay  = 17 * 3600; // 17:00 NY Friday market close
         int diff = srvCloseSecDay - nyCloseSecDay;
         while(diff >  12 * 3600) diff -= 86400;
         while(diff < -12 * 3600) diff += 86400;
         int off = (int)(MathRound((double)diff / 3600.0) * 3600.0);

         if(off < -5 * 3600 || off > 12 * 3600) { newer = t; continue; }

         cachedWeek[nextCache]   = weekOpenServer;
         cachedOffset[nextCache] = off;
         nextCache = (nextCache + 1) % 6;
         return off;
      }
      newer = t;
   }
   return -999999;
}

int GetServerNYOffsetSec(datetime serverTime)
{
   if(MQLInfoInteger(MQL_TESTER))
   {
      int anchored = TesterAnchorOffsetSec(serverTime);
      if(anchored != -999999) return anchored;

      // Fallback if no weekend gap in loaded history:
      if(BrokerServerGMTOffset != 99)
      {
         int srvUTC = BrokerServerGMTOffset * 3600;
         int nyOff  = NYUTCOffsetSeconds(serverTime - srvUTC);
         int bDst   = (nyOff == -4 * 3600) ? 3600 : 0;
         return (srvUTC + bDst) - nyOff;
      }
      // Standard fallback for GMT+2/+3 brokers (serverUTC = 2h + DST):
      int nyOff = NYUTCOffsetSeconds(serverTime - 2 * 3600);
      int bDst  = (nyOff == -4 * 3600) ? 3600 : 0;
      return (2 * 3600 + bDst) - nyOff;
   }

   // LIVE TRADING: Completely dynamic using TimeTradeServer() and TimeGMT()
   datetime serverNow = TimeCurrent();
   datetime tradeNow  = TimeTradeServer();
   datetime gmtNow    = TimeGMT();
   int currentOff = (int)(serverNow - gmtNow);
   int tradeOff   = (tradeNow > 0) ? (int)(tradeNow - gmtNow) : 0;
   int rawUTC = (tradeNow > 0) ? tradeOff : (MathAbs(currentOff) >= 60 ? currentOff : 0);
   int serverUTC = (int)(MathRound((double)rawUTC / 3600.0) * 3600.0);
   return serverUTC - NYUTCOffsetSeconds(serverTime - serverUTC);
}

datetime ConvertServerToNY(datetime serverTime)
{
   return serverTime - GetServerNYOffsetSec(serverTime);
}

datetime ConvertNYLocalToServer(int year, int mon, int day, int hour, int minute, int sec)
{
   datetime nyWall = MakeDT(year, mon, day, hour, minute, sec);
   datetime candidate = nyWall + GetServerNYOffsetSec(TimeCurrent());
   return nyWall + GetServerNYOffsetSec(candidate);
}

long BuildDayKey(datetime dt)
{
   MqlDateTime d; TimeToStruct(dt, d);
   return (long)d.year * 10000 + d.mon * 100 + d.day;
}

// Include Execution and Visual modules
#include "ExecutionRuntime.mqh"
#include "ChartVisuals.mqh"

// Indicators & Internal Engine Handles
int      hEma        = INVALID_HANDLE;
int      hAtr        = INVALID_HANDLE;
double   g_atrWilder = 0.0;
double   g_currentATR = 0.0;
datetime g_atrTime   = 0;
datetime g_lastBarTime = 0;

//+------------------------------------------------------------------+
//| Wilder RMA ATR Seeding & Updating                                |
//+------------------------------------------------------------------+
bool SeedWilderATR(int seedBars = 3000)
{
   MqlRates rates[]; ArraySetAsSeries(rates, false);
   int copied = CopyRates(_Symbol, PERIOD_M5, 1, seedBars, rates);
   if(copied < AtrPeriod + 5) return false;

   double sum = 0.0;
   for(int i = 1; i <= AtrPeriod; i++)
   {
      sum += MathMax(rates[i].high - rates[i].low, MathMax(MathAbs(rates[i].high - rates[i-1].close), MathAbs(rates[i].low - rates[i-1].close)));
   }
   double a = sum / AtrPeriod;
   for(int i = AtrPeriod + 1; i < copied; i++)
   {
      double tr = MathMax(rates[i].high - rates[i].low, MathMax(MathAbs(rates[i].high - rates[i-1].close), MathAbs(rates[i].low - rates[i-1].close)));
      a = (a * (AtrPeriod - 1) + tr) / AtrPeriod;
   }
   g_atrWilder = a;
   g_currentATR = a;
   g_atrTime   = rates[copied - 1].time;
   return true;
}

bool UpdateWilderATR(const MqlRates &b1, const MqlRates &b2)
{
   if(g_atrTime == b2.time)
   {
      double tr = MathMax(b1.high - b1.low, MathMax(MathAbs(b1.high - b2.close), MathAbs(b1.low - b2.close)));
      g_atrWilder = (g_atrWilder * (AtrPeriod - 1) + tr) / AtrPeriod;
      g_atrTime = b1.time;
      return true;
   }
   return SeedWilderATR();
}

//+------------------------------------------------------------------+
//| Expert Initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   if(!ODLoadState())
   {g_stateFault=true;Print("OpenDrive recovery: ",g_recoveryReason);return INIT_FAILED;}
   // OpenDrive calculations and signals run strictly on M5, but the EA can be attached to ANY timeframe chart (M1, M5, H1, H4, etc.)
   PrintFormat("OpenDrive: Initialized on %s (Chart TF: %s). Core calculations & execution strictly fitted to M5.", _Symbol, EnumToString(_Period));

   hEma = iMA(_Symbol, PERIOD_M5, EmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   hAtr = iATR(_Symbol, PERIOD_M5, AtrPeriod);
   if(hEma == INVALID_HANDLE || hAtr == INVALID_HANDLE)
   {
      Print("OpenDrive: Failed to create indicator handles.");
      return INIT_FAILED;
   }

   if(!SeedWilderATR())
   {
      Print("OpenDrive: ATR history pending; existing broker protection retained.");
   }

   g_lastBarTime = iTime(_Symbol, PERIOD_M5, 0);
   RestoreExecutionState();

   if(!MQLInfoInteger(MQL_TESTER))
   {
      if(News_Impact != NEWS_DISABLED)
      {
         PrintFormat("OpenDrive: News Guard ACTIVE [Impact: %d | Window: %d min | BE: %s | Flatten: %s | BlockMod: %s]",
                     News_Impact, News_Window, News_Cost_Covered_BE ? "ON" : "OFF",
                     News_Flatten_Before ? "ON" : "OFF", News_Block_Modification ? "ON" : "OFF");
         PrintFormat("OpenDrive: Please ensure '%s' is added to MT5 Allowed WebRequest URLs (Tools -> Options -> Expert Advisors).", News_WebRequest_URL);
         ODNewsRefresh(TimeCurrent());
      }
      else
      {
         Print("OpenDrive: News Guard is DISABLED.");
      }
   }
   else if(News_Impact != NEWS_DISABLED)
   {
      Print("OpenDrive: Tester news guard omitted: ForexFactory has no historical WebRequest feed.");
   }

   if(ShowVisuals && (!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE)))
   {
      // 1. Attach EMA line to main price chart window (self-dependent visualization)
      if(hEma != INVALID_HANDLE)
      {
         ChartIndicatorAdd(0, 0, hEma);
      }
      // 2. Attach ATR indicator to a subwindow
      if(hAtr != INVALID_HANDLE)
      {
         int totalWindows = (int)ChartGetInteger(0, CHART_WINDOWS_TOTAL);
         ChartIndicatorAdd(0, totalWindows, hAtr);
      }
   }

   if(ShowPanel && (!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE)))
   {
      g_origForeground   = ChartGetInteger(0, CHART_FOREGROUND);
      g_origObjectEvents = ChartGetInteger(0, CHART_EVENT_OBJECT_CREATE);
      ChartSetInteger(0, CHART_FOREGROUND, false);
      ChartSetInteger(0, CHART_EVENT_OBJECT_CREATE, true);
      g_chartConfigured  = true;

      RenderHUDShell();
      UpdateHUD(TimeCurrent(), ConvertServerToNY(TimeCurrent()), 0.0, g_currentATR);
   }

   EventSetTimer(1); // reconciliation must also run with the panel disabled
   ChartRedraw(0);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert Deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   if(!g_stateFault && g_stateLease!=INVALID_HANDLE) ODSaveState();
   if(g_stateLease!=INVALID_HANDLE) {FileClose(g_stateLease);g_stateLease=INVALID_HANDLE;}
   CleanupVisuals();

   // Clean up attached indicators from chart
   int totalWindows = (int)ChartGetInteger(0, CHART_WINDOWS_TOTAL);
   for(int w = totalWindows - 1; w >= 0; w--)
   {
      int totalIndicators = ChartIndicatorsTotal(0, w);
      for(int i = totalIndicators - 1; i >= 0; i--)
      {
         string name = ChartIndicatorName(0, w, i);
         if(StringFind(name, "Moving Average") >= 0 || StringFind(name, "EMA") >= 0 || 
            StringFind(name, "Average True Range") >= 0 || StringFind(name, "ATR") >= 0)
         {
            ChartIndicatorDelete(0, w, name);
         }
      }
   }

   if(hEma != INVALID_HANDLE) IndicatorRelease(hEma);
   if(hAtr != INVALID_HANDLE) IndicatorRelease(hAtr);

   if(WriteLog)
   {
      PrintFormat("OpenDrive Deinit: Lifetime Trades -> Long: %d | Short: %d", g_dayBuyCount, g_daySellCount);
   }
}

//+------------------------------------------------------------------+
//| Timer Event (Live HUD Clock & Panel Restack)                     |
//+------------------------------------------------------------------+
void OnTimer()
{
   ODReconcile();
   ODProtectPosition();
   if(g_atrTime==0) SeedWilderATR();
   if(g_panelRestack)
   {
      g_panelRestack = false;
      ObjectsDeleteAll(0, ODPFX);
      RenderHUDShell();
   }

   datetime nowServer = TimeCurrent();
   datetime nowNY     = ConvertServerToNY(nowServer);

   // Evaluate News Guard in timer
   ODNewsGuard(nowServer);

   double emaVals[1];
   double liveEMA = (CopyBuffer(hEma, 0, 0, 1, emaVals) > 0) ? emaVals[0] : 0.0;

   UpdateHUD(nowServer, nowNY, liveEMA, g_currentATR);
}

//+------------------------------------------------------------------+
//| Chart Event (Handle HUD Button Click)                            |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CREATE && ShowPanel && StringFind(sparam, ODPFX) != 0)
   {
      g_panelRestack = true;
      return;
   }

   if(id == CHARTEVENT_OBJECT_CLICK && sparam == ODPFX + "BTN")
   {
      ObjectSetInteger(0, ODPFX + "BTN", OBJPROP_STATE, false);
      g_panelCollapsed = !g_panelCollapsed;
      RenderHUDShell();
      UpdateHUD(TimeCurrent(), ConvertServerToNY(TimeCurrent()), 0.0, g_currentATR);
      ChartRedraw(0);
   }
}

//+------------------------------------------------------------------+
//| Tick Event                                                       |
//+------------------------------------------------------------------+
void OnTick()
{
   ODReconcile();
   ODProtectPosition();
   datetime nowServer = TimeCurrent();
   CheckDailyGuard(nowServer);

   // News Guard protection check on every tick
   ODNewsGuard(nowServer);

   datetime bar0Time = iTime(_Symbol, PERIOD_M5, 0);
   if(bar0Time != g_lastBarTime)
   {
      g_lastBarTime = bar0Time;
      OnNewBar(nowServer);
   }
}

//+------------------------------------------------------------------+
//| New M5 Bar Event (Signal Check & Trailing Stop Updates)          |
//+------------------------------------------------------------------+
void OnNewBar(datetime nowServer)
{
   MqlRates rates[]; ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, PERIOD_M5, 0, 4, rates) < 4) return; // rates[0]=forming, rates[1]=last closed

   // Update ATR
   if(!UpdateWilderATR(rates[1], rates[2])) return;
   if(AtrMode == ATR_MT5)
   {
      double atrBuf[1];
      if(CopyBuffer(hAtr, 0, 1, 1, atrBuf) > 0 && atrBuf[0] > 0.0)
         g_currentATR = atrBuf[0];
   }
   else
   {
      g_currentATR = g_atrWilder;
   }

   // Fetch last closed EMA
   double emaBuf[2];
   if(CopyBuffer(hEma, 0, 1, 2, emaBuf) < 2) return;
   double closedEMA = emaBuf[1];

   datetime nyTimeBar0 = ConvertServerToNY(rates[0].time);
   datetime nyTimeBar1 = ConvertServerToNY(rates[1].time);
   MqlDateTime dt0, dt1;
   TimeToStruct(nyTimeBar0, dt0);
   TimeToStruct(nyTimeBar1, dt1);

   long dayKey1 = BuildDayKey(nyTimeBar1);
   bool pastExit = (dt0.hour > ExitHourNY) || (dt0.hour == ExitHourNY && dt0.min >= ExitMinNY);

   // 1. Session Lines Drawing
   if(ShowVisuals && (!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE)))
   {
      datetime sEntry = ConvertNYLocalToServer(dt0.year, dt0.mon, dt0.day, EntryHourNY, EntryMinNY, 0);
      DrawSessionLine("OD_LINE_OPEN_" + IntegerToString(dayKey1), sEntry, clrOrange, "09:30 NY Cash Open Drive");

      if(FlatAtExit)
      {
         datetime sExit = ConvertNYLocalToServer(dt0.year, dt0.mon, dt0.day, ExitHourNY, ExitMinNY, 0);
         DrawSessionLine("OD_LINE_EXIT_" + IntegerToString(dayKey1), sExit, clrSilver, "16:00 NY Cash Close Flat Exit");
      }
      PruneVisualObjects("OD_LINE_", 20);
      PruneVisualObjects("OD_SIG_",  30);
      PruneVisualObjects("OD_EXEC_", 30);
   }

   // 2. Active Position Management (Chandelier Trail & 16:00 Flat Exit)
   ManagePosition(rates[1], g_currentATR, pastExit);

   // 3. New Entry Signal Evaluation (At 09:35 NY open, evaluating 09:30 candle)
   bool is0930Candle = (dt1.hour == EntryHourNY && dt1.min == EntryMinNY);
   bool isWeekday    = (dt1.day_of_week >= 1 && dt1.day_of_week <= 5);

   if(is0930Candle && isWeekday && dayKey1 != g_evaluatedDayKey)
   {
      g_evaluatedDayKey = dayKey1;
      if(!ODSaveState() || !g_recoveryReady || g_entryPending || g_closePending) return;

      // Ensure no position is currently open before entering
      ulong tk = 0;
      ENUM_POSITION_TYPE pType;
      double sl = 0.0;
      if(OwnPosition(tk, pType, sl))
      {
         g_lastStatusText = "Position already open";
         return;
      }

      if(!EnableTrading)
      {
         g_lastStatusText = "Trading disabled by input";
         return;
      }

      // Check News Blackout Window Guard
      if(g_newsBlocked)
      {
         g_lastStatusText = "Blocked by News";
         if(WriteLog) PrintFormat("OpenDrive: 09:35 entry skipped due to active news blackout window (%s).", g_activeNewsTitle);
         return;
      }

      // Signal Direction: Close vs EMA12
      int signalDir = 0;
      if(rates[1].close > closedEMA)
         signalDir = 1;
      else if(rates[1].close < closedEMA)
         signalDir = -1;

      if(signalDir == 0)
      {
         g_lastStatusText = "Close == EMA (Tie)";
         return;
      }

      if((signalDir == 1 && !AllowLong) || (signalDir == -1 && !AllowShort))
      {
         g_lastStatusText = (signalDir == 1) ? "Longs blocked" : "Shorts blocked";
         return;
      }

      // Signal Conviction Distance in ATR
      double distATR = (g_currentATR > 0.0) ? (MathAbs(rates[1].close - closedEMA) / g_currentATR) : 0.0;

      // Visual annotations
      string sigInfo = StringFormat("%s C=%.2f EMA=%.2f Dist=%.2f ATR",
                                    signalDir == 1 ? "LONG" : "SHORT",
                                    rates[1].close,
                                    closedEMA,
                                    distATR);
      DrawSignalCandleBox(rates[1], signalDir, sigInfo);

      // Execute Trade
      bool executed = ExecuteEntry(signalDir, distATR, g_currentATR);
      if(executed)
      {
         DrawExecutionMarker(signalDir, rates[0].time, (signalDir == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID), sigInfo);
         g_lastStatusText = (signalDir == 1) ? "Traded LONG" : "Traded SHORT";
      }
      else
      {
         g_lastStatusText = "Entry rejected";
      }
   }

   UpdateHUD(nowServer, nyTimeBar0, closedEMA, g_currentATR);
}

//+------------------------------------------------------------------+
//| Tester Optimization Criterion                                    |
//+------------------------------------------------------------------+
double OnTester()
{
   double trades = TesterStatistics(STAT_TRADES);
   double dd     = TesterStatistics(STAT_EQUITY_DD);
   double profit = TesterStatistics(STAT_PROFIT);

   if(trades < 50 || dd <= 0.0) return 0.0;
   return (profit / dd) * MathSqrt(trades / 100.0);
}

#endif // OPENDRIVE_STRATEGY_ENGINE
