//+------------------------------------------------------------------+
//|                                          NoiseBandMomentum.mq5   |
//|                                                                  |
//|  Noise Band Momentum - intraday momentum on US index CFDs.       |
//|                                                                  |
//|  Idea (Zarattini, Aziz & Barbon 2024; Chuk 2026): after the New  |
//|  York open, price moves randomly inside a "noise band". When it  |
//|  breaks out of that band, the move tends to continue into the    |
//|  close. The band grows with the square root of time, like noise. |
//|                                                                  |
//|  Rule (30-minute candles, broker server time):                   |
//|   1. Reference = close of the candle before the NY open.          |
//|   2. At the end of every half hour from the open (K = 1..11):     |
//|      move = (close - reference) / ATR(14)                        |
//|   3. move >  k*sqrt(K)  -> buy,  move < -k*sqrt(K) -> sell       |
//|   4. Stop 2 ATR, trailing stop 2 ATR once the trade is +1 R.     |
//|   5. Close everything at 23:00 server time - nothing overnight.  |
//|                                                                  |
//|  One EA trades all symbols in InpSymbols, one position each.     |
//|  Attach it to any chart; the chart symbol does not matter.       |
//|                                                                  |
//|  Educational code. Backtest it on your own broker before using   |
//|  it with real money. No guarantee of future results.             |
//+------------------------------------------------------------------+
#property copyright "Noise Band Momentum - free release"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

input group "=== Markets ==="
input string InpSymbols      = "NAS100,SP500"; // Symbols, comma separated (use your broker's names)

input group "=== Session (broker server time) ==="
input int    InpOpenHour     = 16;    // New York open: hour (16 on brokers at New York + 7 h)
input int    InpOpenMinute   = 30;    // New York open: minute
input int    InpCheckpoints  = 11;    // Number of half-hour checkpoints after the open (11 = until +5.5 h)
input int    InpCloseHour    = 23;    // Close all positions from this hour on (New York close)

input group "=== Signal ==="
input double InpBandK        = 1.4;   // Band width k (threshold = k * sqrt(K) * ATR)
input int    InpAtrPeriod    = 14;    // ATR period (30-minute candles)

input group "=== Exit ==="
input double InpStopAtr      = 2.0;   // Initial stop in ATR
input double InpTrailAtr     = 2.0;   // Trailing distance in ATR
input double InpTrailStartR  = 1.0;   // Start trailing at this profit in R (1 R = initial stop distance)
input int    InpMaxBars      = 20;    // Hard exit after this many 30-minute candles

input group "=== Risk ==="
input double InpRiskPercent  = 1.0;   // Risk per trade in % of balance
input long   InpMagic        = 260601;// Magic number
input int    InpSlippage     = 30;    // Max. slippage in points
input int    InpTrailSeconds = 300;   // Min. seconds between two trailing-stop updates

#define TF PERIOD_M30

CTrade   trade;
string   g_sym[];        // symbols actually traded
int      g_atr[];        // ATR handle per symbol
datetime g_lastBar[];    // last 30-minute candle that was evaluated
datetime g_entryTime[];  // open time of the entry candle
double   g_stopDist[];   // initial stop distance in price (= 1 R)
double   g_best[];       // best price since entry (for trailing)
datetime g_lastTrail[];  // last trailing update
int      g_openMinute;   // NY open in minutes since midnight

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippage);
   g_openMinute = InpOpenHour * 60 + InpOpenMinute;

   string parts[];
   int n = StringSplit(InpSymbols, ',', parts);
   int used = 0;
   for(int i = 0; i < n; i++)
   {
      string s = parts[i];
      StringTrimLeft(s);
      StringTrimRight(s);
      if(s == "")
         continue;
      if(!SymbolSelect(s, true))
      {
         PrintFormat("Symbol %s not found at this broker - skipped. Check the exact name in Market Watch.", s);
         continue;
      }
      int h = iATR(s, TF, InpAtrPeriod);
      if(h == INVALID_HANDLE)
      {
         PrintFormat("No ATR for %s - skipped.", s);
         continue;
      }
      used++;
      ArrayResize(g_sym, used);
      ArrayResize(g_atr, used);
      ArrayResize(g_lastBar, used);
      ArrayResize(g_entryTime, used);
      ArrayResize(g_stopDist, used);
      ArrayResize(g_best, used);
      ArrayResize(g_lastTrail, used);
      int k = used - 1;
      g_sym[k] = s;
      g_atr[k] = h;
      g_lastBar[k] = 0;
      g_entryTime[k] = 0;
      g_stopDist[k] = 0.0;
      g_best[k] = 0.0;
      g_lastTrail[k] = 0;
   }
   if(used == 0)
   {
      Print("No tradable symbol in InpSymbols. Example: NAS100,SP500 or US100.cash,US500.cash");
      return(INIT_PARAMETERS_INCORRECT);
   }
   PrintFormat("Noise Band Momentum: %d symbol(s), k = %.2f, NY open %02d:%02d server time.",
               used, InpBandK, InpOpenHour, InpOpenMinute);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   for(int i = 0; i < ArraySize(g_atr); i++)
      IndicatorRelease(g_atr[i]);
}

//+------------------------------------------------------------------+
void OnTick()
{
   for(int i = 0; i < ArraySize(g_sym); i++)
   {
      if(SelectPosition(g_sym[i]))
         Manage(i);
      CheckEntry(i);
   }
}

//+------------------------------------------------------------------+
//| Position of this EA on the symbol (selected on success)          |
//+------------------------------------------------------------------+
bool SelectPosition(const string sym)
{
   for(int p = PositionsTotal() - 1; p >= 0; p--)
   {
      ulong ticket = PositionGetTicket(p);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) == sym && PositionGetInteger(POSITION_MAGIC) == InpMagic)
         return(true);
   }
   return(false);
}

double Atr(const int i, const int shift)
{
   double buf[1];
   if(CopyBuffer(g_atr[i], 0, shift, 1, buf) != 1)
      return(0.0);
   return(buf[0]);
}

//+------------------------------------------------------------------+
//| Exit rules for an open position (already selected)               |
//+------------------------------------------------------------------+
void Manage(const int i)
{
   string sym    = g_sym[i];
   ulong  ticket = (ulong)PositionGetInteger(POSITION_TICKET);
   long   type   = PositionGetInteger(POSITION_TYPE);
   double open   = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl     = PositionGetDouble(POSITION_SL);
   int    dir    = (type == POSITION_TYPE_BUY) ? 1 : -1;
   double price  = (dir == 1) ? SymbolInfoDouble(sym, SYMBOL_BID) : SymbolInfoDouble(sym, SYMBOL_ASK);

   // A position this run did not open (restart): rebuild its state from the position itself.
   if(g_entryTime[i] == 0)
   {
      datetime t = (datetime)PositionGetInteger(POSITION_TIME);
      g_entryTime[i] = iTime(sym, TF, iBarShift(sym, TF, t));
      g_stopDist[i]  = (sl > 0.0) ? MathAbs(open - sl) : 0.0;
      g_best[i]      = open;
   }

   // 1. Intraday only: close at the close hour or if the day has changed.
   MqlDateTime e, now;
   TimeToStruct(g_entryTime[i], e);
   TimeToStruct(TimeCurrent(), now);
   if(now.hour >= InpCloseHour || e.day != now.day || e.mon != now.mon || e.year != now.year)
   {
      trade.PositionClose(ticket);
      return;
   }

   // 2. Maximum holding time.
   int held = Bars(sym, TF, g_entryTime[i], TimeCurrent()) - 1;
   if(held >= InpMaxBars)
   {
      trade.PositionClose(ticket);
      return;
   }

   // 3. Trailing stop: follow the best price at InpTrailAtr * ATR once the trade is InpTrailStartR in profit.
   if(g_stopDist[i] <= 0.0)
      return;
   g_best[i] = (dir == 1) ? MathMax(g_best[i], price) : MathMin(g_best[i], price);
   if(TimeCurrent() - g_lastTrail[i] < InpTrailSeconds)
      return;
   g_lastTrail[i] = TimeCurrent();
   if(dir * (g_best[i] - open) / g_stopDist[i] < InpTrailStartR)
      return;
   double atr = Atr(i, 1);
   if(atr <= 0.0)
      return;
   int    digits    = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double candidate = NormalizeDouble(g_best[i] - dir * InpTrailAtr * atr, digits);
   if((dir == 1 && candidate > sl) || (dir == -1 && (sl == 0.0 || candidate < sl)))
      trade.PositionModify(ticket, candidate, PositionGetDouble(POSITION_TP));
}

//+------------------------------------------------------------------+
//| Entry check once per new 30-minute candle                        |
//+------------------------------------------------------------------+
void CheckEntry(const int i)
{
   string   sym = g_sym[i];
   datetime bar = iTime(sym, TF, 0);
   if(bar == 0 || bar == g_lastBar[i])
      return;
   g_lastBar[i] = bar;
   if(SelectPosition(sym))
      return;

   // The candle that just closed must end at one of the checkpoints.
   MqlDateTime d;
   TimeToStruct(iTime(sym, TF, 1), d);
   int minute = d.hour * 60 + d.min;
   int since  = minute - g_openMinute;
   if(since < 0 || since % 30 != 0)
      return;
   int K = since / 30 + 1;                    // half-hours since the open, 1 .. InpCheckpoints
   if(K > InpCheckpoints)
      return;

   double atr = Atr(i, 1);
   if(atr <= 0.0)
      return;
   double close     = iClose(sym, TF, 1);
   double reference = iClose(sym, TF, 1 + K); // close of the candle before the open
   if(close <= 0.0 || reference <= 0.0)
      return;
   double move      = (close - reference) / atr;
   double threshold = MathRound(InpBandK * MathSqrt(K) * 20.0) / 20.0;   // rounded to 0.05

   int dir = 0;
   if(move > threshold)
      dir = 1;
   else if(move < -threshold)
      dir = -1;
   if(dir == 0)
      return;

   double stopDist = InpStopAtr * atr;
   double lot      = LotFor(sym, stopDist);
   if(lot <= 0.0)
   {
      PrintFormat("%s: signal, but the lot for %.2f %% risk is below the broker minimum - no trade.",
                  sym, InpRiskPercent);
      return;
   }
   int    digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double entry  = (dir == 1) ? SymbolInfoDouble(sym, SYMBOL_ASK) : SymbolInfoDouble(sym, SYMBOL_BID);
   double sl     = NormalizeDouble(entry - dir * stopDist, digits);
   trade.SetTypeFillingBySymbol(sym);
   bool ok = (dir == 1) ? trade.Buy(lot, sym, 0.0, sl, 0.0, "NoiseBand")
                        : trade.Sell(lot, sym, 0.0, sl, 0.0, "NoiseBand");
   if(ok)
   {
      g_entryTime[i] = bar;
      g_stopDist[i]  = stopDist;
      g_best[i]      = entry;
      g_lastTrail[i] = 0;
      PrintFormat("%s %s at checkpoint %d: move %.2f ATR, threshold %.2f, lot %.2f",
                  sym, (dir == 1 ? "BUY" : "SELL"), K, move, threshold, lot);
   }
   else
      PrintFormat("%s: order failed, retcode %u", sym, trade.ResultRetcode());
}

//+------------------------------------------------------------------+
//| Lot size so that the stop costs InpRiskPercent of the balance    |
//+------------------------------------------------------------------+
double LotFor(const string sym, const double stopDist)
{
   double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
   double price     = SymbolInfoDouble(sym, SYMBOL_ASK);
   double loss      = 0.0;
   if(!OrderCalcProfit(ORDER_TYPE_BUY, sym, 1.0, price, price - stopDist, loss) || loss >= 0.0)
   {
      double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
      if(tickValue <= 0.0 || tickSize <= 0.0)
         return(0.0);
      loss = -stopDist / tickSize * tickValue;
   }
   double lot  = riskMoney / -loss;
   double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   double minL = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double maxL = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   if(step > 0.0)
      lot = MathFloor(lot / step + 1e-9) * step;   // round DOWN - never risk more than set
   if(lot < minL - 1e-9)
      return(0.0);
   return(NormalizeDouble(MathMin(lot, maxL), 8));
}
//+------------------------------------------------------------------+
