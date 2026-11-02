//+------------------------------------------------------------------+
//|                                                 ChartVisuals.mqh |
//|                        OpenDrive — Visual Engine & HUD Dashboard |
//+------------------------------------------------------------------+
#ifndef OPENDRIVE_CHART_VISUALS
#define OPENDRIVE_CHART_VISUALS

const string ODPFX = "ODP_";
const int    OD_PX = 10, OD_PY = 20, OD_PW = 210, OD_PH = 220, OD_HH = 32;

bool g_panelCollapsed     = false;
bool g_panelRestack       = false;
bool g_chartConfigured    = false;
long g_origForeground     = 0;
long g_origObjectEvents   = 0;
string g_lastStatusText   = "waiting";

//+------------------------------------------------------------------+
//| Panel Primitive: Flat Rectangle Label                            |
//+------------------------------------------------------------------+
void OD_Rect(string name, int x, int y, int w, int h, color bg, color bdr)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
      ObjectSetInteger(0, name, OBJPROP_BACK,       false);
   }
   ObjectSetInteger(0, name, OBJPROP_ZORDER,       10000);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,    x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,    y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,        w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,        h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,      (long)bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR,        (long)bdr);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE,  BORDER_FLAT);
}

//+------------------------------------------------------------------+
//| Panel Primitive: Typography Label                                |
//+------------------------------------------------------------------+
void OD_Lbl(string name, int x, int y, string text, int fs, color clr)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
      ObjectSetInteger(0, name, OBJPROP_BACK,       false);
      ObjectSetString(0,  name, OBJPROP_FONT,       "Segoe UI Semibold");
   }
   ObjectSetInteger(0, name, OBJPROP_ZORDER,       10001);
   if((int)ObjectGetInteger(0, name, OBJPROP_XDISTANCE) != x) ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   if((int)ObjectGetInteger(0, name, OBJPROP_YDISTANCE) != y) ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   if((int)ObjectGetInteger(0, name, OBJPROP_FONTSIZE)  != fs) ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fs);
   if(ObjectGetInteger(0, name, OBJPROP_COLOR) != (long)clr) ObjectSetInteger(0, name, OBJPROP_COLOR, (long)clr);
   if(ObjectGetString(0, name, OBJPROP_TEXT) != text) ObjectSetString(0, name, OBJPROP_TEXT, text);
}

//+------------------------------------------------------------------+
//| Render HUD Panel Shell & Collapse Toggle                         |
//+------------------------------------------------------------------+
void RenderHUDShell()
{
   if(!ShowPanel) return;
   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)) return;

   int height = g_panelCollapsed ? OD_HH : OD_PH;

   // Layered drop shadows and dark glass background
   OD_Rect(ODPFX+"SHD2", OD_PX+5, OD_PY+5, OD_PW, height, C'6,6,6',    C'6,6,6');
   OD_Rect(ODPFX+"SHD1", OD_PX+2, OD_PY+2, OD_PW, height, C'12,12,12', C'12,12,12');
   OD_Rect(ODPFX+"BG",   OD_PX,   OD_PY,   OD_PW, height, clrBlack,    C'52,68,92');
   OD_Rect(ODPFX+"HDR",  OD_PX,   OD_PY,   OD_PW, OD_HH,  C'18,22,28', C'52,68,92');
   OD_Rect(ODPFX+"HAIR", OD_PX,   OD_PY+OD_HH, OD_PW, 1,  C'52,68,92', C'52,68,92');

   // Brand Title
   OD_Lbl(ODPFX+"TTL",   OD_PX+8, OD_PY+8, "OpenDrive — NQ 9:30", 9, C'190,210,236');

   // Collapse / Expand Button
   string btnName = ODPFX + "BTN";
   if(ObjectFind(0, btnName) < 0)
   {
      ObjectCreate(0, btnName, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, btnName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, btnName, OBJPROP_HIDDEN, true);
      ObjectSetString(0,  btnName, OBJPROP_FONT,   "Segoe UI Semibold");
   }
   ObjectSetInteger(0, btnName, OBJPROP_XDISTANCE, OD_PX + OD_PW - 29);
   ObjectSetInteger(0, btnName, OBJPROP_YDISTANCE, OD_PY + 5);
   ObjectSetInteger(0, btnName, OBJPROP_XSIZE,     22);
   ObjectSetInteger(0, btnName, OBJPROP_YSIZE,     22);
   ObjectSetInteger(0, btnName, OBJPROP_FONTSIZE,  12);
   ObjectSetInteger(0, btnName, OBJPROP_COLOR,     (long)C'190,210,236');
   ObjectSetInteger(0, btnName, OBJPROP_BGCOLOR,   (long)C'18,22,28');
   ObjectSetInteger(0, btnName, OBJPROP_BORDER_COLOR, (long)C'52,68,92');
   ObjectSetInteger(0, btnName, OBJPROP_STATE,     false);
   ObjectSetInteger(0, btnName, OBJPROP_ZORDER,    10002);
   ObjectSetString(0,  btnName, OBJPROP_TEXT,      g_panelCollapsed ? "+" : "-");

   if(g_panelCollapsed)
   {
      string rows[] = {"SRV", "EMA", "STR", "ATR", "TRD", "STAT", "TRL", "SL", "NEWS"};
      for(int i = 0; i < ArraySize(rows); i++) ObjectDelete(0, ODPFX + rows[i]);
   }
}

//+------------------------------------------------------------------+
//| Update HUD Metrics Content                                       |
//+------------------------------------------------------------------+
void UpdateHUD(datetime serverTime, datetime nyTime, double emaValue, double currentATR)
{
   if(!ShowPanel) return;
   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)) return;

   if(ObjectFind(0, ODPFX+"BG") < 0) RenderHUDShell();
   if(g_panelCollapsed) return;

   int x = OD_PX + 8;

   // Row 1: NY Clock
   string nyClockStr = "NY: " + TimeToString(nyTime, TIME_MINUTES|TIME_SECONDS) + " [" + TimeToString(serverTime, TIME_MINUTES|TIME_SECONDS) + "]";
   OD_Lbl(ODPFX+"SRV", x, OD_PY+40, nyClockStr, 8, C'140,158,185');

   // Row 2: EMA Level
   string emaStr = StringFormat("EMA %d: %s", EmaPeriod, emaValue > 0.0 ? DoubleToString(emaValue, _Digits) : "--");
   OD_Lbl(ODPFX+"EMA", x, OD_PY+59, emaStr, 8, C'120,210,150');

   // Row 3: Signal Conviction / Risk Tier
   string strTier;
   if(g_lastSigDist >= 0.0)
   {
      string modeName = (RiskMode == RISK_DYNAMIC_VOLATILITY) ? "Dyn" : "Fix";
      strTier = StringFormat("Conviction: %.2f ATR -> %.2f%% (%s)", g_lastSigDist, g_lastRiskPct, modeName);
   }
   else
   {
      strTier = (RiskMode == RISK_DYNAMIC_VOLATILITY) ? "Sizing: Dynamic (Prop Firm)" : "Sizing: Static (Live)";
   }
   OD_Lbl(ODPFX+"STR", x, OD_PY+76, strTier, 8, C'210,100,100');

   // Row 4: ATR and Stop Size
   string atrStr = StringFormat("ATR(%d): %s (SL x%.1f)", AtrPeriod, currentATR > 0.0 ? DoubleToString(currentATR, _Digits) : "--", StopATR);
   OD_Lbl(ODPFX+"ATR", x, OD_PY+93, atrStr, 8, C'140,158,185');

   // Row 5: Daily Trades
   OD_Lbl(ODPFX+"TRD", x, OD_PY+112, StringFormat("Trades Today: Long %d | Short %d", g_dayBuyCount, g_daySellCount), 8, C'140,200,240');

   // Row 6: Position & R-Multiple
   string posText;
   ulong tk = 0;
   ENUM_POSITION_TYPE pType;
   double sl = 0.0;
   if(OwnPosition(tk, pType, sl))
   {
      double curPrice = (pType == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double rMult = (g_openRisk > 0.0) ? ((curPrice - g_openPrice) * g_openDir / g_openRisk) : 0.0;
      posText = StringFormat("Open: %s @ %s (%+.2fR)", g_openDir == 1 ? "LONG" : "SHORT", DoubleToString(g_openPrice, _Digits), rMult);
   }
   else
   {
      posText = "Status: " + (g_recoveryReason!=""?g_recoveryReason:g_lastStatusText);
   }
   OD_Lbl(ODPFX+"STAT", x, OD_PY+132, StringSubstr(posText, 0, 32), 8, C'140,200,240');

   // Row 7: Trailing Stop Status
   string trailStr;
   if(g_openTicket > 0)
   {
      trailStr = g_trailActive ? "Trail: ACTIVE (Chandelier 3.0 ATR)" : StringFormat("Trail: Arm at +%.2f ATR", ActivateATR);
   }
   else
   {
      trailStr = StringFormat("Trail: 3.0 ATR after +%.2f ATR", ActivateATR);
   }
   OD_Lbl(ODPFX+"TRL", x, OD_PY+149, trailStr, 8, C'190,180,120');

   // Row 8: Current Stop Loss distance in points / %
   string slStr = "--";
   if(g_openTicket > 0 && g_openSL > 0.0)
   {
      double pts = MathAbs(g_openPrice - g_openSL) / _Point;
      double pct = (g_openPrice > 0.0) ? (MathAbs(g_openPrice - g_openSL) / g_openPrice * 100.0) : 0.0;
      slStr = StringFormat("SL: -%.0f pts (-%.2f%%)", pts, pct);
   }
   else if(currentATR > 0.0)
   {
      double pts = (StopATR * currentATR) / _Point;
      slStr = StringFormat("Planned SL: -%.0f pts", pts);
   }
   OD_Lbl(ODPFX+"SL", x, OD_PY+166, slStr, 8, C'200,70,70');

   // Row 9: News Guard Status
   string newsStr;
   color newsColor;
   if(News_Impact == NEWS_DISABLED)
   {
      newsStr = "News: OFF";
      newsColor = C'140,158,185';
   }
   else if(g_newsBlocked)
   {
      string title = (g_activeNewsTitle != "") ? g_activeNewsTitle : "High Impact";
      newsStr = "News: BLACKOUT [" + StringSubstr(title, 0, 16) + "]";
      newsColor = C'255,100,100';
   }
   else if(g_costCoveredApplied)
   {
      newsStr = "News: Cost BE Locked";
      newsColor = C'100,230,120';
   }
   else if(g_upcomingNewsTime > 0)
   {
      datetime nyNews = ConvertServerToNY(g_upcomingNewsTime);
      string timeStr = TimeToString(nyNews, TIME_MINUTES);
      newsStr = StringFormat("News: %s NY [%s]", timeStr, StringSubstr(g_upcomingNewsTitle, 0, 14));
      newsColor = C'240,200,90';
   }
   else if(g_newsReady)
   {
      newsStr = "News: Active (No Events Soon)";
      newsColor = C'120,210,150';
   }
   else
   {
      newsStr = "News: Syncing Calendar...";
      newsColor = C'140,158,185';
   }
   OD_Lbl(ODPFX+"NEWS", x, OD_PY+185, newsStr, 8, newsColor);
}

//+------------------------------------------------------------------+
//| Prune Chart Objects                                              |
//+------------------------------------------------------------------+
void PruneVisualObjects(const string prefix, int keepDays)
{
   datetime cutoff = TimeCurrent() - keepDays * 86400;
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, prefix) != 0) continue;
      datetime objTime = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME);
      if(objTime > 0 && objTime < cutoff) ObjectDelete(0, name);
   }
}

//+------------------------------------------------------------------+
//| Draw Session Time Lines (09:30 NY Open & 16:00 NY Flat Exit)     |
//+------------------------------------------------------------------+
void DrawSessionLine(const string name, datetime t, color c, const string desc)
{
   if(!ShowVisuals) return;
   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)) return;

   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_VLINE, 0, t, 0);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_BACK,  true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   ObjectSetInteger(0, name, OBJPROP_TIME, t);
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   ObjectSetString(0,  name, OBJPROP_TOOLTIP, desc);
}

//+------------------------------------------------------------------+
//| Draw Signal Box on 09:30 NY Candle                               |
//+------------------------------------------------------------------+
void DrawSignalCandleBox(const MqlRates &candle, int dir, const string text)
{
   if(!ShowVisuals || !ShowExtras) return;
   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)) return;

   string name = "OD_SIG_" + TimeToString(candle.time, TIME_DATE|TIME_MINUTES);
   color c = (dir == 1) ? clrLime : (dir == -1) ? clrRed : clrGray;

   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, candle.time, candle.high, candle.time + 300, candle.low);
      ObjectSetInteger(0, name, OBJPROP_FILL, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   ObjectSetString(0,  name, OBJPROP_TOOLTIP, text);
}

//+------------------------------------------------------------------+
//| Draw Trade Execution Arrow                                       |
//+------------------------------------------------------------------+
void DrawExecutionMarker(int dir, datetime t, double price, const string desc)
{
   if(!ShowVisuals || !ShowExtras) return;
   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)) return;

   string name = "OD_EXEC_" + TimeToString(t, TIME_DATE|TIME_MINUTES);
   ENUM_OBJECT arrowType = (dir == 1) ? OBJ_ARROW_BUY : OBJ_ARROW_SELL;
   color c = (dir == 1) ? clrLime : clrRed;

   ObjectCreate(0, name, arrowType, 0, t, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   ObjectSetString(0,  name, OBJPROP_TOOLTIP, desc);
}

//+------------------------------------------------------------------+
//| Cleanup Visuals on Deinit                                        |
//+------------------------------------------------------------------+
void CleanupVisuals()
{
   ObjectsDeleteAll(0, ODPFX);
   ObjectsDeleteAll(0, "OD_SIG_");
   ObjectsDeleteAll(0, "OD_EXEC_");
   ObjectsDeleteAll(0, "OD_LINE_");

   if(g_chartConfigured)
   {
      ChartSetInteger(0, CHART_FOREGROUND, g_origForeground);
      ChartSetInteger(0, CHART_EVENT_OBJECT_CREATE, g_origObjectEvents);
   }
   ChartRedraw(0);
}

#endif // OPENDRIVE_CHART_VISUALS
