//+------------------------------------------------------------------+
//|                                        NoiseBandMomentum.mq5     |
//|                                                                  |
//|  Noise Band Momentum - intraday momentum on US index CFDs.       |
//|                                                                  |
//|  Idea (Zarattini, Aziz & Barbon 2024; Chuk 2026): after the New  |
//|  York open, price moves randomly inside a "noise band". When it  |
//|  breaks out of that band, the move tends to continue into the    |
//|  close. The band grows with the square root of time, like noise. |
//|                                                                  |
//|  Rule (30-minute candles, broker server time):                   |
//|   1. Reference = close of the candle before the NY open.         |
//|   2. At the end of every half hour from the open (K = 1..11):    |
//|      move = (close - reference) / ATR(14)                        |
//|   3. move >  k*sqrt(K)  -> buy,  move < -k*sqrt(K) -> sell       |
//|   4. Stop 2 ATR, trailing stop 2 ATR once the trade is +1 R.     |
//|   5. Close everything at 23:00 server time - nothing overnight.  |
//|                                                                  |
//|  Trades the chart it is attached to, one position.                |
//|  It selects nothing, so Market Watch stays exactly as you set it. |
//|                                                                  |
//|  Shell only: properties, inputs, event handlers. The rule lives   |
//|  in StrategyEngine.mqh, the order path in ExecutionRuntime.mqh.   |
//|                                                                  |
//|  Educational code. Backtest it on your own broker before using   |
//|  it with real money. No guarantee of future results.             |
//+------------------------------------------------------------------+
#property copyright "Noise Band Momentum - free release"
#property version   "1.11"
#property strict

input group "=== Session (New York clock) ==="
input int    InpOpenNYMinute = 570;   // Session open, minutes after New York midnight (570 = 09:30 NY)
input int    InpCloseNYMinute= 960;   // Close all positions from this New York minute on (960 = 16:00 NY)
input int    InpCheckpoints  = 11;    // Number of half-hour checkpoints after the open (11 = until +5.5 h)

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
input bool   InpAllowMinLotOverride = true; // Take the broker minimum when the budget is below it (false = skip)
input long   InpMagic        = 260601;// Magic number
input int    InpSlippage     = 30;    // Max. slippage in points
input int    InpTrailSeconds = 300;   // Min. seconds between two trailing-stop updates

#include "StrategyEngine.mqh"


#include "ExecutionRuntime.mqh"

//+------------------------------------------------------------------+
int OnInit()
{
   return(NBMInit());
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   NBMDeinit();
}

//+------------------------------------------------------------------+
void OnTick()
{
   NBMTick();
}
//+------------------------------------------------------------------+
