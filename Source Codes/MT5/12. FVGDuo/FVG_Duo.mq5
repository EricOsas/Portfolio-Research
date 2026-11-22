//+------------------------------------------------------------------+
//|                                                   FVG_Duo.mq5    |
//| FVG Duo - Opening Drive FVG + Trend FVG Strategy                 |
//| Developed by Osamwonyi Eric (@You_FoundEric)                     |
//| Copyright 2026-2027, Osamwonyi Eric (@You_FoundEric)             |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026-2027, Osamwonyi Eric (@You_FoundEric)"
#property link      "https://x.com/You_FoundEric"
#property version   "5.00"
#property description "FVG Duo - Opening Drive FVG + Trend FVG Strategy on Index Futures/CFDs (NQ, MNQ, USTEC)"
#property description "Opening Drive: 10m FVG, 1.25% stop, no resting price TP; dated NY session deadline."
#property description "Trend FVG: completed M15 EMA 50/100, fixed displacement, long-only, 3.0R target."
#property description "Defaults: $7.00 round-turn commission per lot; $100.00 cash risk."
#property description "Broker clock metadata requires validation; unknown signal clock keeps owned-position management active."
#property strict

#include "StrategyEngine.mqh"
