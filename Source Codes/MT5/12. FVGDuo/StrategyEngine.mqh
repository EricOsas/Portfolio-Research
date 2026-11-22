//+------------------------------------------------------------------+
//|                                             StrategyEngine.mqh   |
//| FVG Duo Strategy Engine (Opening Drive + Trend FVG)              |
//| Developed by Osamwonyi Eric (@You_FoundEric)                     |
//| Copyright 2026-2027, Osamwonyi Eric (@You_FoundEric)             |
//|                                                                  |
//| PARITY BUILD                                                     |
//| Event-driven on completed M1 bars. Mirrors the Python oracle in  |
//| tests/python/fvg_duo_engine.py:                                  |
//|   od_signal_for_date()      -> EvaluateOD()                      |
//|   compute_trend_signals()   -> PushM15() + EvaluateTrend()       |
//|   run_day()                 -> OnBarOpenM1() + HandleODSignal()  |
//|   simulate_trade()          -> broker SL/TP + session flatten    |
//|                                                                  |
//| The oracle exits are per M1 bar: gap through the level first     |
//| (fill at bar open), then the intrabar touch (fill at the level). |
//| A server side stop/limit reproduces exactly that, so exits are   |
//| delegated to the broker and journalled from deal history.        |
//+------------------------------------------------------------------+
#property strict
#property tester_no_cache

#include <Trade/Trade.mqh>

//--- Enums
enum ENUM_ATR_METHOD
{
   ATR_METHOD_SMA,       // Simple Moving Average (SMA)
   ATR_METHOD_RMA        // Wilder's Smoothed Average (RMA)
};

enum ENUM_ATR_REF
{
   ATR_REF_C2,           // ATR window includes c2 (bar k-1)
   ATR_REF_C1            // ATR window ends at c1 (bar k-2)
};

enum ENUM_SIZING_MODE
{
   SIZING_FIXED,            // Fixed Lots
   SIZING_PERCENT,          // Risk % of Live Equity
   SIZING_CASH,             // Fixed Cash Risk (USD)
   SIZING_PERCENT_BALANCE   // Risk % of Fixed Initial Balance (Non-compounding)
};

enum ENUM_MERGE_ANCHOR
{
   MERGE_TREND_ENTRY,    // Stop anchored to Trend entry price
   MERGE_OD_SIGNAL       // Stop anchored to OD signal bar open
};

//--- Fixed Strategy Parameters (Optimal B3a)
#define B3A_TREND_ATR_MULT       1.25
#define B3A_TREND_EMA_FAST       50
#define B3A_TREND_EMA_SLOW       100
#define B3A_OD_STOP_PCT          0.0125
#define B3A_TREND_AFTER_STOPOUT  true
#define B3A_ATR_METHOD           ATR_METHOD_SMA
#define B3A_ATR_REF              ATR_REF_C2

//--- Inputs
const bool   InpEnableOD = true;
const bool   InpEnableTrend = true;
const bool   InpFvgStrict = true;
const double InpTickSize = 0.0;
const double InpTrendRR = 3.0;
const ENUM_MERGE_ANCHOR InpMergeAnchor = MERGE_TREND_ENTRY;

input group "==========  1 - Sizing & Risk  =========="
input ENUM_SIZING_MODE  InpSizingMode          = SIZING_FIXED;       // Sizing Mode
input double            InpFixedLots           = 1.0;                // Fixed Lots
input double            InpRiskPercent         = 1.0;                // Risk % per Trade
input double            InpCashRiskUSD         = 100.0;              // Cash Risk USD per Trade
input double            InpFixedBalanceUSD     = 0.0;                // Fixed Balance USD (0 = derive from initial balance)
input int               InpRiskSlippageTicks   = 2;                  // Stressed Exit Slippage (ticks, reserved in risk)

input group " "
input group "==========  2 - Costs & Execution  =========="
input ulong             InpMagic               = 909150;             // EA Magic Number
input ulong             InpDeviation           = 10;                 // Max Slippage Points
input double            InpCommissionRTPerLot  = 7.0;                // Round-turn Commission per Lot ($3.50 open + $3.50 close)

input group "  "
input group "==========  3 - Display & Visuals  =========="
input bool              ShowVisuals            = true;               // Draw FVG Boxes and Markers
input bool              ShowDashboard          = true;               // Display Performance HUD

// Forward includes
#include "ExecutionRuntime.mqh"
#include "ChartVisuals.mqh"
#include "VisualRecovery.mqh"

//+------------------------------------------------------------------+
//| BROKER-IDEMPOTENT NEW YORK CLOCK ENGINE                          |
//|                                                                  |
//| Server time is anchored on the weekly reopen: the first bar after |
//| the weekend gap is, by construction, Sunday 18:00 New York. The    |
//| offset that maps it there is snapped to whole hours and cached per |
//| calendar week, so a broker DST change is picked up automatically   |
//| without ever guessing a timezone.                                  |
//+------------------------------------------------------------------+
const int CLOCK_UNKNOWN = 100000;

datetime g_clockWeekKey = 0;
int      g_clockWeekOff = CLOCK_UNKNOWN;

int OffsetFromReopen(datetime reopen)
{
   int raw    = (int)((long)reopen % 86400) - 18 * 3600;
   int offset = (int)MathRound((double)raw / 3600.0) * 3600;
   while(offset >  14 * 3600) offset -= 86400;
   while(offset < -12 * 3600) offset += 86400;
   return offset;
}

int VBWeekAnchorOffset(datetime stamp)
{
   MqlRates h1[];
   ArraySetAsSeries(h1, false);
   int n = CopyRates(_Symbol, PERIOD_H1, stamp - 30 * 86400, stamp, h1);
   if(n < 2) return CLOCK_UNKNOWN;

   for(int i = n - 1; i >= 1; i--)
   {
      if(h1[i].time - h1[i - 1].time < 36 * 3600) continue;   // not the weekend gap
      MqlRates m1[];
      ArraySetAsSeries(m1, false);
      if(CopyRates(_Symbol, PERIOD_M1, h1[i].time, h1[i].time + 2 * 3600, m1) < 1) continue;
      return OffsetFromReopen(m1[0].time);
   }
   return CLOCK_UNKNOWN;
}

int VBExpectedBrokerUTC(datetime utc)
{
   MqlDateTime dt;
   TimeToStruct(utc, dt);
   // Approximate US DST: 2nd Sunday March to 1st Sunday Nov
   if(dt.mon > 3 && dt.mon < 11) return 3; // Summer
   if(dt.mon == 3 && dt.day >= 8) return 3;
   if(dt.mon == 11 && dt.day < 7) return 3;
   return 2; // Winter
}

int VBServerNYOffsetSec(datetime stamp)
{
   if(MQLInfoInteger(MQL_TESTER))
   {
      MqlDateTime d;
      TimeToStruct(stamp, d);
      d.hour = 0; d.min = 0; d.sec = 0;
      datetime week = StructToTime(d) - d.day_of_week * 86400;
      if(week == g_clockWeekKey && g_clockWeekOff != CLOCK_UNKNOWN)
         return g_clockWeekOff;

      int off = VBWeekAnchorOffset(stamp);
      if(off != CLOCK_UNKNOWN)
      {
         g_clockWeekKey = week;
         g_clockWeekOff = off;
      }
      return off;
   }

   datetime utc = TimeGMT(), server = TimeTradeServer();
   if(server <= 0 || utc <= 0) return CLOCK_UNKNOWN;
   int raw = (int)(server - utc), offset = (int)MathRound((double)raw / 900.0) * 900;
   if(MathAbs(raw - offset) > 120 || offset < -12 * 3600 || offset > 14 * 3600) return CLOCK_UNKNOWN;
   if(MathAbs((double)(stamp - server)) > 7 * 86400)
      return VBWeekAnchorOffset(stamp);
   return offset - (VBExpectedBrokerUTC(stamp - offset) - 7) * 3600;
}

datetime NYTime(datetime serverTime)
{
   int offset = VBServerNYOffsetSec(serverTime);
   if(offset == CLOCK_UNKNOWN) return 0;
   return serverTime - offset;
}

//+------------------------------------------------------------------+
//| BROKER SESSION-END TABLE                                         |
//|                                                                  |
//| US half days do not produce a 16:00 bar, and the tester generates  |
//| no tick once the feed stops, so the flatten has to be driven from  |
//| the feed's own calendar instead of a clock. Each entry is the New  |
//| York minute-of-day of the last bar printed before 16:00 (derived   |
//| from the same M1 history the oracle ran on). Dates absent here     |
//| close normally at 16:00.                                          |
//+------------------------------------------------------------------+
const string SESSION_END_TABLE =
                 "20180115=779;20180219=779;20180528=779;20180703=794;20180704=779;20180903=779;"
                 "20181122=779;20181123=794;20181205=570;20181224=794;20181231=840;20190121=779;"
                 "20190218=779;20190527=779;20190703=794;20190704=779;20190902=779;20191128=779;"
                 "20191129=794;20191224=794;"
                 "20191231=839;20200120=779;20200217=779;20200525=779;20200703=779;20200907=779;"
                 "20201126=779;20201127=794;20201224=794;20201231=839;20210118=779;20210215=779;"
                 "20210402=554;20210531=779;20210705=779;20210906=779;20211125=779;20211126=794;"
                 "20211231=839;20220117=779;20220221=779;20220530=779;20220620=779;20220704=779;"
                 "20220905=779;20221124=779;20221125=794;20230116=779;20230220=779;20230529=779;"
                 "20230619=779;20230703=794;20230704=779;20230904=779;20231123=779;20231124=794;"
                 "20240115=779;20240219=779;20240527=779;20240619=779;20240703=795;20240704=779;"
                 "20240902=779;20241128=780;20241129=794;20241224=794;20250109=570;20250120=779;"
                 "20250217=779;20250526=779;20250619=779;20250703=794;20250704=779;20250901=779;"
                 "20251127=779;20251128=794;20251224=794;20260119=779;20260216=779;20260403=554;"
                 "20260525=779;20260619=779;20260703=779;20260907=779;";

string g_sessionKeys[];
int    g_sessionMins[];

void LoadSessionTable()
{
   string items[];
   int n = StringSplit(SESSION_END_TABLE, ';', items);
   ArrayResize(g_sessionKeys, 0);
   ArrayResize(g_sessionMins, 0);
   for(int i = 0; i < n; i++)
   {
      string item = items[i];
      if(StringLen(item) < 9) continue;
      int eq = StringFind(item, "=");
      if(eq != 8) continue;
      int k = ArraySize(g_sessionKeys);
      ArrayResize(g_sessionKeys, k + 1);
      ArrayResize(g_sessionMins, k + 1);
      g_sessionKeys[k] = StringSubstr(item, 0, 8);
      g_sessionMins[k] = (int)StringToInteger(StringSubstr(item, 9));
   }
}

// New York minute-of-day at which the session is flattened.
// 960 = 16:00 for a normal day.
int SessionEndMinute(datetime nyDay)
{
   MqlDateTime d;
   TimeToStruct(nyDay, d);
   string key = StringFormat("%04d%02d%02d", d.year, d.mon, d.day);
   for(int i = 0; i < ArraySize(g_sessionKeys); i++)
      if(g_sessionKeys[i] == key)
         return g_sessionMins[i];
   return 960;
}

//+------------------------------------------------------------------+
//| STATE                                                            |
//+------------------------------------------------------------------+
datetime g_lastM1Time      = 0;
datetime g_nyDay           = 0;
int      g_sessionEndMin   = 960;
ulong    g_sessionPositionId = 0;
datetime g_ownedSessionEndServer = 0;
double   g_dayStartBalance = 0.0;
// Non-compounding risk anchor. Resolved once in OnInit, never from live equity.
double   g_fixedBalanceBase = 0.0;
string   g_statusText      = "INITIALIZING";

// Opening Drive
bool     g_odCheck1Done    = false;
bool     g_odCheck2Done    = false;
bool     g_odFired         = false;
bool     g_odStoppedOut    = false;
datetime g_odTime          = 0;
double   g_odStop          = 0.0;

// Trend FVG: incremental M15 state, exactly the oracle's series
datetime g_m15Last         = 0;
int      g_m15Index        = -1;      // 0-based index of newest completed bar
double   g_emaFast         = 0.0;
double   g_emaSlow         = 0.0;
double   g_trPrevClose     = 0.0;
double   g_atrSum          = 0.0;
double   g_atr             = 0.0;
double   g_trRing[14];
int      g_trHead          = 0;
int      g_trCount         = 0;

// ring[0] = c3 (newest completed), ring[1] = c2, ring[2] = c1
datetime g_rTime[3];
double   g_rHigh[3];
double   g_rLow[3];
double   g_rAtr[3];

// exit sequencing (blocked_by_open_position rule)
int      g_seenExitSeq     = 0;

// A MERGE whose trim was not confirmed keeps the old stop; the request is
// retried every bar until the server confirms the reduction and the move.
bool     g_mergePending    = false;
double   g_mergePendingStop = 0.0;

// Active parameters resolved from preset
double          actTrendAtrMult;
int             actTrendEmaFast;
int             actTrendEmaSlow;
double          actODStopPct;
bool            actTrendAfterStopout;
ENUM_ATR_METHOD actAtrMethod;
ENUM_ATR_REF    actAtrRef;

// Strategy tick ("1 tick" of the stop rule). Resolved from the instrument so
// the same engine runs on 0.25 futures (ES/NQ), 0.1 gold and 0.1/0.01/0.001
// CFD grids. InpTickSize > 0 pins it explicitly.
double          g_modelTick = 0.25;

void ResolveTickGrid()
{
   g_symTick   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(g_symTick <= 0.0) g_symTick = _Point;
   if(g_symTick <= 0.0) g_symTick = 0.01;
   g_symDigits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(g_symDigits < 0) g_symDigits = 2;

   g_modelTick = (InpTickSize > 0.0) ? InpTickSize : g_symTick;
   if(g_modelTick <= 0.0) g_modelTick = g_symTick;

   PrintFormat("[FVG_DUO] symbol=%s digits=%d grid=%.6f strategyTick=%.6f stopsLevel=%.6f",
               _Symbol, g_symDigits, g_symTick, g_modelTick, MinStopDistance());
}

void ResolvePresets()
{
   actTrendAtrMult      = B3A_TREND_ATR_MULT;
   actTrendEmaFast      = B3A_TREND_EMA_FAST;
   actTrendEmaSlow      = B3A_TREND_EMA_SLOW;
   actODStopPct         = B3A_OD_STOP_PCT;
   actTrendAfterStopout = B3A_TREND_AFTER_STOPOUT;
   actAtrMethod         = B3A_ATR_METHOD;
   actAtrRef            = B3A_ATR_REF;
}

// Risk anchor is captured once. Using live equity here would compound risk.
void ResolveRiskAnchor()
{
   g_fixedBalanceBase = (InpFixedBalanceUSD > 0.0)
                        ? InpFixedBalanceUSD * AccountCashPerUSD()
                        : AccountInfoDouble(ACCOUNT_BALANCE);
   if(g_fixedBalanceBase <= 0.0) g_fixedBalanceBase = 10000.0;
   g_dashBalanceBase = g_fixedBalanceBase;

   if(InpSizingMode == SIZING_FIXED)              g_dashSizingText = "Fixed lots";
   else if(InpSizingMode == SIZING_PERCENT)       g_dashSizingText = "Risk % of live equity";
   else if(InpSizingMode == SIZING_CASH)          g_dashSizingText = "Fixed cash risk";
   else                                           g_dashSizingText = "Risk % of fixed balance";
}

double RoundTick(double price)
{
   double tick = g_modelTick;
   if(tick <= 0.0) return price;
   return MathFloor(price / tick + 0.5) * tick;
}

//+------------------------------------------------------------------+
//| M15 INDICATOR STATE (running, seeded on the first bar of data)    |
//+------------------------------------------------------------------+
void PushM15(datetime t, double h, double l, double c)
{
   double tr;
   if(g_m15Index < 0) tr = h - l;
   else tr = MathMax(h - l, MathMax(MathAbs(h - g_trPrevClose), MathAbs(l - g_trPrevClose)));

   double aF = 2.0 / (actTrendEmaFast + 1.0);
   double aS = 2.0 / (actTrendEmaSlow + 1.0);
   if(g_m15Index < 0)
   {
      g_emaFast = c;
      g_emaSlow = c;
   }
   else
   {
      g_emaFast = c * aF + g_emaFast * (1.0 - aF);
      g_emaSlow = c * aS + g_emaSlow * (1.0 - aS);
   }

   int idx = g_m15Index + 1;
   double atrVal = 0.0;
   if(actAtrMethod == ATR_METHOD_RMA)
   {
      if(idx < 13)      { g_atrSum += tr; atrVal = 0.0; }
      else if(idx == 13){ g_atrSum += tr; g_atr = g_atrSum / 14.0; atrVal = g_atr; }
      else              { g_atr = (g_atr * 13.0 + tr) / 14.0; atrVal = g_atr; }
   }
   else // SMA of the trailing 14 true ranges
   {
      g_trRing[g_trHead] = tr;
      g_trHead = (g_trHead + 1) % 14;
      if(g_trCount < 14) g_trCount++;
      if(g_trCount == 14)
      {
         double sum = 0.0;
         for(int i = 0; i < 14; i++) sum += g_trRing[i];
         g_atr = sum / 14.0;
      }
      atrVal = (g_trCount == 14) ? g_atr : 0.0;
   }

   g_trPrevClose = c;
   g_m15Index = idx;

   for(int k = 2; k > 0; k--)
   {
      g_rTime[k] = g_rTime[k - 1];
      g_rHigh[k] = g_rHigh[k - 1];
      g_rLow[k]  = g_rLow[k - 1];
      g_rAtr[k]  = g_rAtr[k - 1];
   }
   g_rTime[0] = t;
   g_rHigh[0] = h;
   g_rLow[0]  = l;
   g_rAtr[0]  = atrVal;
}

// Process every M15 bar that completed at or before barTime-1.
void UpdateM15(datetime barTime)
{
   datetime from = (g_m15Last > 0) ? g_m15Last + 1 : barTime - 400 * 86400;
   MqlRates r[];
   ArraySetAsSeries(r, false);
   int n = CopyRates(_Symbol, PERIOD_M15, from, barTime - 1, r);
   if(n <= 0) return;
   for(int i = 0; i < n; i++)
   {
      if(r[i].time <= g_m15Last) continue;
      datetime previousClose = g_m15Last + 900;
      double previousFast = g_emaFast, previousSlow = g_emaSlow;
      PushM15(r[i].time, r[i].high, r[i].low, r[i].close);
      if(g_m15Last > 0 && r[i].time - g_m15Last == 900 &&
         r[i].time >= barTime - 4 * 86400)
         ShowTrendAverages(previousClose, r[i].time + 900, previousFast, g_emaFast,
                            previousSlow, g_emaSlow);
      g_m15Last = r[i].time;
   }
}

//+------------------------------------------------------------------+
//| DAY / SESSION                                                    |
//+------------------------------------------------------------------+
void StartDay(datetime nyDay)
{
   if(g_fvgCandidateName != "")
   {
      ForgetVisualRecord(g_fvgCandidateName);
      ObjectDelete(0, g_fvgCandidateName);
   }
   g_fvgCandidateName = "";
   g_nyDay          = nyDay;
   g_odCheck1Done   = false;
   g_odCheck2Done   = false;
   g_odFired        = false;
   g_odStoppedOut   = false;
   g_odTime         = 0;
   g_mergePending   = false;
   g_mergePendingStop = 0.0;
   g_sessionEndMin  = SessionEndMinute(nyDay);
   g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_statusText     = "PRE-MARKET";
}

// Cache only an entry-date deadline established by the declared NY clock.
// A new signal date or a temporary clock gap must not postpone an open trade.
datetime OwnedSessionEndServer()
{
   if(!ownedActive || ownedPositionId == 0 || ownedEntryTime <= 0) return 0;
   if(g_sessionPositionId == ownedPositionId && g_ownedSessionEndServer > 0)
      return g_ownedSessionEndServer;
   datetime entryNy = NYTime(ownedEntryTime);
   if(entryNy <= 0) return 0;
   datetime day = (datetime)((long)entryNy - ((long)entryNy % 86400));
   g_ownedSessionEndServer = (datetime)((long)day + SessionEndMinute(day) * 60 +
                                       ((long)ownedEntryTime - entryNy));
   g_sessionPositionId = ownedPositionId;
   return g_ownedSessionEndServer;
}

// Passive geometry follows actual accepted position data and booked exits.
void SyncTradeVisuals(datetime barTime)
{
   if(!VisualsAllowed()) return;
   if(g_visualTradePositionId > 0 &&
      (!ownedActive || ownedPositionId != g_visualTradePositionId))
   {
      int i = JournalFind(g_visualTradePositionId);
      if(i >= 0 && j_exitServer[i] > 0 && j_exitPrice[i] > 0.0)
         FinishTradeGeometry(j_exitServer[i], j_exitPrice[i], j_exitReason[i]);
   }
   if(!ownedActive || ownedEntryTime <= 0 || ownedStopPrice <= 0.0) return;
   datetime end = barTime + 60;
   datetime planned = OwnedSessionEndServer();
   if(planned > end) end = planned;
   ShowTradeGeometry(ownedSide, ownedEntryTime, end, ownedEntryPrice,
                      ownedStopPrice, ownedTargetPrice, ownedPositionId, ownedSource);
}

//+------------------------------------------------------------------+
//| OPENING DRIVE                                                    |
//+------------------------------------------------------------------+
bool ODCheck(datetime barTime, int &side, double &entryPx, double &stopPx)
{
   datetime from = barTime - 1800;   // check1: 09:10 / check2: 09:20
   datetime to   = barTime - 60;
   MqlRates r[];
   ArraySetAsSeries(r, false);
   if(CopyRates(_Symbol, PERIOD_M10, from, to, r) != 3) return false;
   if(r[0].time != from || r[1].time != from + 600 || r[2].time != from + 1200) return false;

   double c1High = r[0].high, c1Low = r[0].low;
   double c3High = r[2].high, c3Low = r[2].low;

   bool bull, bear;
   if(InpFvgStrict)
   {
      bull = (c3Low > c1High);
      bear = (c3High < c1Low);
   }
   else
   {
      bull = (c3Low >= c1High);
      bear = (c3High <= c1Low);
   }
   if(!bull && !bear) return false;

   entryPx = iOpen(_Symbol, PERIOD_M1, 0);
   if(bull)
   {
      side   = 1;
      stopPx = RoundTick(entryPx * (1.0 - actODStopPct));
   }
   else
   {
      side   = -1;
      stopPx = RoundTick(entryPx * (1.0 + actODStopPct));
   }
   // C3 close, not C3 open: the box must cover the whole C1..C3 span.
   ShowFvgCandidate("OD", r[0].time, (bull ? c1High : c1Low), r[2].time + 600, (bull ? c3Low : c3High), bull);
   return true;
}

void EvaluateOD(datetime barTime, int tod)
{
   // Duo components remain enabled together; fixed model rule.
   if(tod != 9 * 60 + 40 && tod != 9 * 60 + 50) return;

   if(tod == 9 * 60 + 40)
   {
      if(g_odCheck1Done) return;
      g_odCheck1Done = true;
   }
   else
   {
      if(g_odCheck2Done) return;
      g_odCheck2Done = true;
   }
   if(g_odFired) return;

   int side;
   double entryPx, stopPx;
   if(!ODCheck(barTime, side, entryPx, stopPx)) return;

   g_odFired = true;
   g_odTime  = barTime;
   g_odStop  = stopPx;

   // 3b: flat -> simple OD entry
   if(!ownedActive)
   {
      if(ExecuteEntry(side, entryPx, stopPx, 0.0, "OD"))
      {
         g_statusText = (side > 0) ? "OD LONG ENTERED" : "OD SHORT ENTERED";
         MarkFvgCandidateTraded();
         SyncTradeVisuals(barTime);
      }
      return;
   }

   // An open position here can only be the long-only Trend trade.
   if(ownedSource != "TREND" || ownedSide <= 0) return;

   if(side > 0)
   {
      // 3c: MERGE — both long, fold the trend position into OD rules
      double anchor = (InpMergeAnchor == MERGE_TREND_ENTRY) ? ownedSignalEntry : entryPx;
      double mergeStop = RoundTick(anchor * (1.0 - actODStopPct));

      if(entryPx <= mergeStop)
      {
         // Already through the merged stop at the OD bar open: book the exit
         // at that open and do not open the OD trade.
         JournalUpdate(ownedPositionId, "MERGED", mergeStop, 0.0);
         ExecuteClose("STOP");
         g_mergePending = false;
         g_mergePendingStop = 0.0;
         g_statusText = "MERGED STOP AT OD OPEN";
         return;
      }
      if(ExecuteModify(mergeStop, 0.0, "MERGED"))
      {
         g_mergePending     = false;
         g_mergePendingStop = 0.0;
         g_statusText = "MERGED TO OD RULES";
         MarkFvgCandidateTraded();
      }
      else
      {
         // Trim or stop move unconfirmed: the old stop stays live and the
         // request is retried every bar until the server confirms both.
         g_mergePending     = true;
         g_mergePendingStop = mergeStop;
         g_statusText       = "MERGE PENDING CONFIRMATION";
      }
      return;
   }

   // 3d: FLIP - trend long against an OD short
   ExecuteClose("FLIP");
   if(ExecuteEntry(-1, entryPx, stopPx, 0.0, "OD"))
   {
      MarkFvgCandidateTraded();
      SyncTradeVisuals(barTime);
   }
   g_statusText = "FLIPPED TO OD SHORT";
}

//+------------------------------------------------------------------+
//| TREND FVG                                                        |
//+------------------------------------------------------------------+
void EvaluateTrend(datetime barTime, double barOpen, int tod)
{
   // Duo components remain enabled together; fixed model rule.
   if(g_m15Index < 1000) return;                 // oracle warmup_bars

   // c3 must be the bar that closed exactly at this M1 open
   if(g_rTime[0] + 900 != barTime) return;
   if(g_rTime[0] - g_rTime[1] != 900) return;
   if(g_rTime[1] - g_rTime[2] != 900) return;

   if(tod < 9 * 60 + 30 || tod > 15 * 60 + 30) return;

   // Rule b: bullish FVG, c3.low > c1.high
   if(InpFvgStrict)
   {
      if(g_rLow[0] <= g_rHigh[2]) return;
   }
   else
   {
      if(g_rLow[0] < g_rHigh[2]) return;
   }

   // Rule c: displacement, c2 range >= mult * ATR
   double atr = (actAtrRef == ATR_REF_C1) ? g_rAtr[2] : g_rAtr[1];
   if(atr <= 0.0) return;
   double c2Range = g_rHigh[1] - g_rLow[1];
   if(c2Range < actTrendAtrMult * atr) return;

   // Rule d: trend, EMA fast > EMA slow
   if(g_emaFast <= g_emaSlow) return;

   double stop = g_rLow[2] - g_modelTick;
   if(barOpen <= stop) return;

   // Arbitration gates (oracle run_day)
   if(ownedActive) return;
   if(barTime <= g_lastExitBar) return;
   if(g_odFired && barTime > g_odTime)
   {
      if(!(actTrendAfterStopout && g_odStoppedOut)) return;
   }

   double target = barOpen + InpTrendRR * (barOpen - stop);
   // Display only an eligible trigger candidate; its right bound is C3 open.
   ShowFvgCandidate("TREND", g_rTime[2], g_rHigh[2], g_rTime[0] + 900, g_rLow[0], true);
   if(ExecuteEntry(1, barOpen, stop, target, "TREND"))
   {
      g_statusText = "TREND LONG ENTERED";
      MarkFvgCandidateTraded();
      SyncTradeVisuals(barTime);
   }
}

//+------------------------------------------------------------------+
//| INITIALIZATION                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   ResolvePresets();
   ResolveTickGrid();
   ResolveRiskAnchor();
   LoadSessionTable();
   JournalOpen();
   ReconcileOwnedPosition();
   g_seenExitSeq = g_exitEventSeq;

   PrintFormat("[FVG_DUO] Initialized on %s. Model=Optimal_B3a Mult=%.2f FastEMA=%d SlowEMA=%d ODStop=%.4f Sessions=%d",
               _Symbol, actTrendAtrMult, actTrendEmaFast,
               actTrendEmaSlow, actODStopPct, ArraySize(g_sessionKeys));
   PrintFormat("[FVG_DUO] Sizing=%s RiskPct=%.2f FixedBalance=%.2f RiskUSD=%.2f",
               g_dashSizingText, InpRiskPercent, g_fixedBalanceBase,
               g_fixedBalanceBase * InpRiskPercent / 100.0);
   if(VisualsAllowed() || DashboardAllowed())
   {
      ConfigurePanelLayering();
      EventSetTimer(1);
   }
   g_fvgVisualRepair = true;
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(VisualsAllowed()) CaptureVisualRecords();
   JournalCloser();
   // Completed visual tester charts keep their final drawings for inspection.
   if(!MQLInfoInteger(MQL_TESTER) || !MQLInfoInteger(MQL_VISUAL_MODE)) RemoveVisuals();
}

//+------------------------------------------------------------------+
//| ON TICK: act on the open of each new M1 bar                      |
//+------------------------------------------------------------------+
void RefreshFvgDisplay(datetime serverNow)
{
   MaintainFvgVisuals(serverNow);
   if(!DashboardAllowed()) return;
   datetime ny = NYTime(serverNow);
   if(ny <= 0) return;
   int minute = (int)((ny % 86400) / 60);
   string displayStatus = g_statusText;
   if(displayStatus == "PRE-MARKET" && minute >= 570 && minute < SessionEndMinute(ny))
      displayStatus = "WAITING";
   if(!ownedActive && minute >= SessionEndMinute(ny)) displayStatus = "SESSION CLOSED";
   string position = "FLAT";
   if(ownedActive)
      position = StringFormat("%s %s @ %.2f (SL: %.2f)", ownedSource,
                              ownedSide > 0 ? "LONG" : "SHORT", ownedEntryPrice, ownedStopPrice);
   UpdateDashboard(displayStatus, TimeToString(ny, TIME_SECONDS), position,
                    AccountInfoDouble(ACCOUNT_BALANCE) - g_dayStartBalance);
}

void OnTimer()
{
   datetime now = MQLInfoInteger(MQL_TESTER) ? TimeCurrent() : TimeTradeServer();
   if(now <= 0) now = TimeCurrent();
   RefreshFvgDisplay(now); // Display only: no signals, reconciliation, closes or order retries.
}

void OnTick()
{
   datetime m1Time = iTime(_Symbol, PERIOD_M1, 0);
   if(m1Time == 0) return;
   if(m1Time != g_lastM1Time)
   {
      g_lastM1Time = m1Time;
      OnBarOpenM1(m1Time);
   }
   RefreshFvgDisplay(TimeCurrent());
}

void OnBarOpenM1(datetime barTime)
{
   // Broker management precedes signal-clock gates. Keep the existing M1
   // request cadence; a missing tick cannot be turned into a synthetic fill.
   ReconcileOwnedPosition();
   datetime sessionEndServer = OwnedSessionEndServer();
   bool sessionExpired = (sessionEndServer > 0 && barTime >= sessionEndServer);
   string sessionCloseStatus = "";
   if(sessionExpired)
   {
      sessionCloseStatus = ExecuteClose("TIME") ? "SESSION CLOSED" : "TIME CLOSE PENDING";
      g_statusText = sessionCloseStatus;
   }
   SyncTradeVisuals(barTime);

   datetime ny = NYTime(barTime);
   if(ny <= 0)
   {
      static long lastDiagnosticDay = -1;
      long day = (long)barTime / 86400;
      if(day != lastDiagnosticDay)
      {
         PrintFormat("[CLOSEOUT_CLOCK] server=%s week=%s offset=%d unknown", TimeToString(barTime, TIME_DATE|TIME_SECONDS), TimeToString(g_clockWeekKey,TIME_DATE), g_clockWeekOff);
         lastDiagnosticDay = day;
      }
      return;
   }

   MqlDateTime dt;
   TimeToStruct(ny, dt);
   datetime nyDay = ny - (dt.hour * 3600 + dt.min * 60 + dt.sec);
   int tod = dt.hour * 60 + dt.min;
   if(tod == 580 || tod == 590)
      PrintFormat("[CLOSEOUT_OD] ny=%s m15=%d clockOffset=%d owned=%d fired=%d", TimeToString(ny,TIME_DATE|TIME_SECONDS), g_m15Index,g_clockWeekOff,(int)ownedActive,(int)g_odFired);

   PruneFvgVisuals(ny);
   if(nyDay != g_nyDay) StartDay(nyDay);
   if(sessionExpired) g_statusText = sessionCloseStatus;
   if(VisualsAllowed())
   {
      datetime previous = iTime(_Symbol, PERIOD_M1, 1);
      datetime previousNy = NYTime(previous);
      if(previousNy > 0)
         UpdateObservedSessionVisual(previous, previousNy, SessionEndMinute(previousNy),
                              iHigh(_Symbol, PERIOD_M1, 1), iLow(_Symbol, PERIOD_M1, 1));
   }

   // 2. Consume the broker-exit event already reconciled above.
   if(g_exitEventSeq != g_seenExitSeq)
   {
      g_seenExitSeq = g_exitEventSeq;
      if(g_exitEventSource == "OD" && g_exitEventReason == "STOP")
         g_odStoppedOut = true;
   }

   // 2b. Retry a MERGE the server has not confirmed yet. The trend stop stays
   //     where it is until the trim and the wider stop are both settled.
   if(g_mergePending)
   {
      if(!ownedActive || ownedSource != "TREND")
      {
         g_mergePending     = false;
         g_mergePendingStop = 0.0;
      }
      else if(ExecuteModify(g_mergePendingStop, 0.0, "MERGED"))
      {
         g_mergePending     = false;
         g_mergePendingStop = 0.0;
         g_statusText       = "MERGED TO OD RULES";
         MarkFvgCandidateTraded();
      }
   }

   // 3. Rolling M15 state (every completed 15m bar, all hours)
   if(g_m15Last == 0 || (barTime % 900) == 0)
      UpdateM15(barTime);

   double barOpen = iOpen(_Symbol, PERIOD_M1, 0);

   if(tod < g_sessionEndMin)
   {
      // 4. Opening Drive checks at 09:40 / 09:50 NY
      EvaluateOD(barTime, tod);

      // 5. Trend FVG on completed 15m bars
      if((barTime % 900) == 0)
         EvaluateTrend(barTime, barOpen, tod);
   }

   SyncTradeVisuals(barTime);

   // 6. HUD
   string posText = "FLAT";
   if(ownedActive)
      posText = StringFormat("%s %s @ %.2f (SL: %.2f)",
                             ownedSource, (ownedSide > 0 ? "LONG" : "SHORT"),
                             ownedEntryPrice, ownedStopPrice);
   double todayPnL = AccountInfoDouble(ACCOUNT_BALANCE) - g_dayStartBalance;
   UpdateDashboard(g_statusText, TimeToString(ny, TIME_SECONDS), posText, todayPnL);
}

//+------------------------------------------------------------------+
//| ON TESTER: DETAILED TRADE EXPORT & PARITY HARNESS                |
//+------------------------------------------------------------------+
double OnTester()
{
   JournalFlush();

   if(!HistorySelect(0, TimeCurrent())) return 0;

   FolderCreate("FVG_Duo_Closeout_20261120", FILE_COMMON);
   FolderCreate("FVG_Duo_Closeout_20261120/logs", FILE_COMMON);
   int handle = FileOpen("FVG_Duo_Closeout_20261120/logs/trades_mt5.csv", FILE_COMMON | FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(handle == INVALID_HANDLE)
   {
      Print("[FVG_DUO] Failed to open Common/Files/FVG_Duo/logs/trades_mt5.csv");
      return 0;
   }

   FileWrite(handle, "trade_id", "date", "source", "side", "entry_server", "exit_server", "entry_ny", "exit_ny", "entry_price", "exit_price", "points", "commission", "gross_usd", "net_usd", "comment");

   int totalDeals = HistoryDealsTotal();
   int tradeCount = 0;
   double totalNet = 0.0;

   for(int i = 0; i < totalDeals; i++)
   {
      ulong exitTicket = HistoryDealGetTicket(i);
      if(exitTicket <= 0) continue;
      if(HistoryDealGetInteger(exitTicket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
      if(HistoryDealGetInteger(exitTicket, DEAL_MAGIC) != (long)InpMagic) continue;

      ulong posId = (ulong)HistoryDealGetInteger(exitTicket, DEAL_POSITION_ID);

      ulong entryTicket = 0;
      for(int j = 0; j < i; j++)
      {
         ulong dtick = HistoryDealGetTicket(j);
         if(HistoryDealGetInteger(dtick, DEAL_POSITION_ID) == (long)posId &&
            HistoryDealGetInteger(dtick, DEAL_ENTRY) == DEAL_ENTRY_IN)
         {
            entryTicket = dtick;
            break;
         }
      }

      if(entryTicket == 0) continue;

      tradeCount++;
      long dealType = HistoryDealGetInteger(entryTicket, DEAL_TYPE);
      string side = (dealType == DEAL_TYPE_BUY) ? "LONG" : "SHORT";

      datetime entryServer = (datetime)HistoryDealGetInteger(entryTicket, DEAL_TIME);
      datetime exitServer  = (datetime)HistoryDealGetInteger(exitTicket, DEAL_TIME);
      datetime entryNY     = NYTime(entryServer);
      datetime exitNY      = NYTime(exitServer);

      double entryPrice = HistoryDealGetDouble(entryTicket, DEAL_PRICE);
      double exitPrice  = HistoryDealGetDouble(exitTicket, DEAL_PRICE);

      double points = (side == "LONG") ? (exitPrice - entryPrice) : (entryPrice - exitPrice);
      double profit = HistoryDealGetDouble(exitTicket, DEAL_PROFIT);
      double comm   = HistoryDealGetDouble(entryTicket, DEAL_COMMISSION) + HistoryDealGetDouble(exitTicket, DEAL_COMMISSION);
      double swap   = HistoryDealGetDouble(exitTicket, DEAL_SWAP);
      double net    = profit + comm + swap;
      totalNet += net;

      string comment = HistoryDealGetString(exitTicket, DEAL_COMMENT);
      string entryComment = HistoryDealGetString(entryTicket, DEAL_COMMENT);
      string src = "OD";
      if(StringFind(entryComment, "TREND") >= 0) src = "TREND";
      if(StringFind(entryComment, "MERGED") >= 0 || StringFind(comment, "MERGED") >= 0) src = "MERGED";

      MqlDateTime dt;
      TimeToStruct(entryNY, dt);
      string dateStr = StringFormat("%04d-%02d-%02d", dt.year, dt.mon, dt.day);

      FileWrite(handle, tradeCount, dateStr, src, side,
                TimeToString(entryServer, TIME_DATE|TIME_SECONDS), TimeToString(exitServer, TIME_DATE|TIME_SECONDS),
                TimeToString(entryNY, TIME_DATE|TIME_SECONDS), TimeToString(exitNY, TIME_DATE|TIME_SECONDS),
                DoubleToString(entryPrice, 2), DoubleToString(exitPrice, 2),
                DoubleToString(points, 2), DoubleToString(comm, 2), DoubleToString(profit, 2), DoubleToString(net, 2),
                comment);
   }

   FileClose(handle);
   PrintFormat("[FVG_DUO] TESTER_COMPLETE: exported %d trades, Net P&L: %.2f USD", tradeCount, totalNet);
   return totalNet;
}
