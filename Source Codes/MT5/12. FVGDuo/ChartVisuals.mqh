//+------------------------------------------------------------------+
//|                                             ChartVisuals.mqh     |
//| Chart dashboard, FVG zone and trade markers for FVG Duo           |
//| Developed by Osamwonyi Eric (@You_FoundEric)                     |
//|                                                                  |
//| Passive by contract: nothing here may create, suppress, delay or  |
//| alter a signal or an order. Every object is FVG_-prefixed and    |
//| owned by this EA only. Panel design matches the Index Book EAs.   |
//+------------------------------------------------------------------+
#ifndef FVG_CHART_VISUALS
#define FVG_CHART_VISUALS

// Values published by the engine for the dashboard.
double g_dashRiskBudget     = 0.0;   // captured cash budget for the current entry
double g_dashLots        = 0.0;   // lots actually sent for the current position
double g_dashBalanceBase = 0.0;   // non-compounding balance anchor
string g_dashSizingText  = "Fixed";
string g_fvgCandidateName = "";
datetime g_visualCutoffNy = 0;
string g_visualTradePrefix = "";
ulong g_visualTradePositionId = 0;
int g_visualTradeSide = 0;
string g_visualTradeSource = "";
datetime g_visualTradeStart = 0, g_visualTradeEnd = 0;
double g_visualTradeEntry = 0.0, g_visualTradeStop = 0.0, g_visualTradeTarget = 0.0;

bool VisualsAllowed()
{
   if(!ShowVisuals) return false;
   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)) return false;
   return true;
}
bool DashboardAllowed()
{
   if(!ShowDashboard) return false;
   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)) return false;
   return true;
}

//+------------------------------------------------------------------+
//| CURRENCY & MONEY FORMATTER                                       |
//+------------------------------------------------------------------+
string FormatMoney(double amount)
{
   string cur = AccountInfoString(ACCOUNT_CURRENCY);
   if(cur == "" || cur == "USD") cur = "$";
   else cur = cur + " ";

   bool neg = (amount < 0.0);
   double absVal = MathAbs(amount);
   long whole = (long)MathFloor(absVal);
   int cents = (int)MathRound((absVal - (double)whole) * 100.0);
   if(cents >= 100) { whole++; cents = 0; }

   string s = IntegerToString(whole);
   int len = StringLen(s);
   string res = "";
   for(int i = 0; i < len; i++)
   {
      if(i > 0 && (len - i) % 3 == 0) res += ",";
      res += StringSubstr(s, i, 1);
   }
   if(cur == "$")
      return StringFormat("%s%s%s.%02d", neg ? "-" : "", cur, res, cents);
   else
      return StringFormat("%s%s.%02d %s", neg ? "-" : "", res, cents, cur);
}

//+------------------------------------------------------------------+
//| PANEL (shared Index Book layout, fitted width)                    |
//+------------------------------------------------------------------+
const int PX = 10, PY = 20, PH = 210, HH = 32;
const int FVG_PANEL_BASE_WIDTH = 250;
int fvgPanelWidth = FVG_PANEL_BASE_WIDTH;
bool fvgPanelMeasureOk = true;
bool fvgPanelCollapsed = false, fvgPanelRestack = false;
bool fvgPanelLayeringSaved = false;
long fvgPanelOriginalForeground = 0, fvgPanelOriginalCreateEvents = 0, fvgPanelOriginalDeleteEvents = 0;
string fvgPanelStatus = "", fvgPanelClock = "", fvgPanelPosition = "FLAT";
double fvgPanelNet = 0.0;

// Render cache. Without it every tick rewrites every object and the panel
// shimmers; with it a tick that changes nothing repaints nothing.
string fvgPanelLastStatus = "", fvgPanelLastClock = "", fvgPanelLastPos = "";
string fvgPanelLastSizing = "";
double fvgPanelLastNet = 0.0, fvgPanelLastBudget = 0.0, fvgPanelLastLots = 0.0;
double fvgPanelLastBase = 0.0;
int    fvgPanelLastWidth = -1;
bool   fvgPanelLastCollapsed = false;
bool   fvgPanelDrawn = false;
bool   fvgPanelLayoutDirty = true;   // chart changed (open / timeframe / resize)

string FvgPanelPrefix() { return "FVG_PANEL_"; }

int FvgPanelTextWidth(string text, int fontSize)
{
   if(!fvgPanelMeasureOk) return -1;
   uint width = 0, height = 0;
   if(!TextSetFont("Segoe UI Semibold", -fontSize * 10) ||
      !TextGetSize(text, width, height) || width == 0)
   {
      fvgPanelMeasureOk = false;
      return -1;
   }
   return (int)width;
}

string FvgPanelFitText(string text, int fontSize)
{
   int available = fvgPanelWidth - 16;
   if(available < 1) return "";
   int measuredWidth = FvgPanelTextWidth(text, fontSize);
   if(measuredWidth < 0 || measuredWidth <= available) return text;

   string fitted = text;
   while(StringLen(fitted) > 0)
   {
      fitted = StringSubstr(fitted, 0, StringLen(fitted) - 1);
      string candidate = fitted + "...";
      measuredWidth = FvgPanelTextWidth(candidate, fontSize);
      if(measuredWidth < 0) return "...";
      if(measuredWidth <= available) return candidate;
   }
   return "...";
}

int FvgPanelDesiredWidth(const string &text[], const int &fontSizes[])
{
   int widest = FVG_PANEL_BASE_WIDTH;
   for(int i = 0; i < ArraySize(text); i++)
   {
      int measuredWidth = FvgPanelTextWidth(text[i], fontSizes[i]);
      if(measuredWidth < 0) return FVG_PANEL_BASE_WIDTH;
      widest = (int)MathMax(widest, measuredWidth + 16);
   }
   return widest;
}

void ConfigurePanelLayering()
{
   if(!DashboardAllowed() && !VisualsAllowed()) return;
   if(!fvgPanelLayeringSaved)
   {
      fvgPanelOriginalForeground = ChartGetInteger(0, CHART_FOREGROUND);
      fvgPanelOriginalCreateEvents = ChartGetInteger(0, CHART_EVENT_OBJECT_CREATE);
      fvgPanelOriginalDeleteEvents = ChartGetInteger(0, CHART_EVENT_OBJECT_DELETE);
      fvgPanelLayeringSaved = true;
   }
   // ZORDER only controls clicks. Foreground prices and later-created objects
   // require an actual foreground panel and creation-event restacking.
   if(DashboardAllowed() && ChartGetInteger(0, CHART_FOREGROUND) != 0)
      ChartSetInteger(0, CHART_FOREGROUND, false);
   if(ChartGetInteger(0, CHART_EVENT_OBJECT_CREATE) == 0)
      ChartSetInteger(0, CHART_EVENT_OBJECT_CREATE, true);
   if(ChartGetInteger(0, CHART_EVENT_OBJECT_DELETE) == 0)
      ChartSetInteger(0, CHART_EVENT_OBJECT_DELETE, true);
}

void RestorePanelLayering()
{
   if(!fvgPanelLayeringSaved) return;
   ChartSetInteger(0, CHART_FOREGROUND, fvgPanelOriginalForeground);
   ChartSetInteger(0, CHART_EVENT_OBJECT_CREATE, fvgPanelOriginalCreateEvents);
   ChartSetInteger(0, CHART_EVENT_OBJECT_DELETE, fvgPanelOriginalDeleteEvents);
   fvgPanelLayeringSaved = false;
}

void FvgPanelRect(string name, int x, int y, int w, int h, color bg, color bdr)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
      ObjectSetInteger(0, name, OBJPROP_BACK,       false);
      ObjectSetInteger(0, name, OBJPROP_ZORDER,     10000);
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   }
   // Write only what changed. Every ObjectSetInteger repaints the object, so
   // unconditional writes make the panel shimmer on every tick and on reselect.
   if((int)ObjectGetInteger(0, name, OBJPROP_XDISTANCE) != x) ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   if((int)ObjectGetInteger(0, name, OBJPROP_YDISTANCE) != y) ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   if((int)ObjectGetInteger(0, name, OBJPROP_XSIZE)     != w) ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   if((int)ObjectGetInteger(0, name, OBJPROP_YSIZE)     != h) ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   if(ObjectGetInteger(0, name, OBJPROP_BGCOLOR) != (long)bg)  ObjectSetInteger(0, name, OBJPROP_BGCOLOR, (long)bg);
   if(ObjectGetInteger(0, name, OBJPROP_COLOR)   != (long)bdr) ObjectSetInteger(0, name, OBJPROP_COLOR,   (long)bdr);
}

void FvgPanelLbl(string name, int x, int y, string text, int fs, color clr)
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
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 10001);
   if((int)ObjectGetInteger(0, name, OBJPROP_XDISTANCE) != x) ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   if((int)ObjectGetInteger(0, name, OBJPROP_YDISTANCE) != y) ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   if((int)ObjectGetInteger(0, name, OBJPROP_FONTSIZE)  != fs) ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fs);
   if(ObjectGetInteger(0, name, OBJPROP_COLOR) != (long)clr) ObjectSetInteger(0, name, OBJPROP_COLOR, (long)clr);
   if(ObjectGetString(0, name, OBJPROP_TEXT) != text) ObjectSetString(0, name, OBJPROP_TEXT, text);
}

void FvgPanelShell()
{
   if(!DashboardAllowed()) return;
   ConfigurePanelLayering();
   int height = fvgPanelCollapsed ? HH : PH;
   string p = FvgPanelPrefix();
   FvgPanelRect(p+"SHD2", PX+5, PY+5, fvgPanelWidth, height, C'6,6,6',    C'6,6,6');
   FvgPanelRect(p+"SHD1", PX+2, PY+2, fvgPanelWidth, height, C'12,12,12', C'12,12,12');
   FvgPanelRect(p+"BG",   PX,   PY,   fvgPanelWidth, height, clrBlack,    C'52,68,92');
   FvgPanelRect(p+"HDR",  PX,   PY,   fvgPanelWidth, HH, C'18,22,28', C'52,68,92');
   FvgPanelRect(p+"HAIR", PX,   PY+HH, fvgPanelWidth, 1, C'52,68,92', C'52,68,92');
   FvgPanelLbl(p+"TTL",   PX+8, PY+8, "FVG Duo", 9, C'190,210,236');
   string button = p+"BTN";
   if(ObjectFind(0, button) < 0)
   {
      ObjectCreate(0, button, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, button, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, button, OBJPROP_HIDDEN, true);
      ObjectSetString(0,  button, OBJPROP_FONT, "Segoe UI Semibold");
      ObjectSetInteger(0, button, OBJPROP_COLOR,        (long)C'190,210,236');
      ObjectSetInteger(0, button, OBJPROP_BGCOLOR,      (long)C'18,22,28');
      ObjectSetInteger(0, button, OBJPROP_BORDER_COLOR, (long)C'52,68,92');
      ObjectSetInteger(0, button, OBJPROP_BACK,         false);
      ObjectSetInteger(0, button, OBJPROP_ZORDER,       10002);
      ObjectSetInteger(0, button, OBJPROP_XSIZE,        22);
      ObjectSetInteger(0, button, OBJPROP_YSIZE,        22);
      ObjectSetInteger(0, button, OBJPROP_FONTSIZE,     12);
   }
   int bx = PX+fvgPanelWidth-29;
   if((int)ObjectGetInteger(0, button, OBJPROP_XDISTANCE) != bx) ObjectSetInteger(0, button, OBJPROP_XDISTANCE, bx);
   if((int)ObjectGetInteger(0, button, OBJPROP_YDISTANCE) != PY+5) ObjectSetInteger(0, button, OBJPROP_YDISTANCE, PY+5);
   if(ObjectGetInteger(0, button, OBJPROP_STATE) != 0) ObjectSetInteger(0, button, OBJPROP_STATE, false);
   string btnText = fvgPanelCollapsed ? "+" : "-";
   if(ObjectGetString(0, button, OBJPROP_TEXT) != btnText) ObjectSetString(0, button, OBJPROP_TEXT, btnText);
   if(fvgPanelCollapsed)
   {
      string rows[] = {"CLK","OD","TRD","STAT","BAL","RIS","POS","PNL"};
      for(int i = 0; i < ArraySize(rows); i++) ObjectDelete(0, p+rows[i]);
   }
}

void UpdateDashboard(string status, string nyClockStr, string posStr, double todayNet)
{
   if(!DashboardAllowed()) return;
   fvgPanelStatus = status;
   fvgPanelClock = nyClockStr;
   fvgPanelPosition = posStr;
   fvgPanelNet = todayNet;
   long chartWidth = ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int availableWidth = (int)MathMax(1, chartWidth - PX - 8);
   fvgPanelMeasureOk = true;
   string rows[] = {
      "NY "+nyClockStr+" | "+_Symbol,
      "Open Drive: 10m FVG | Stop 1.25%",
      "Trend FVG: 15m FVG | EMA 50/100 | 3.0R",
      "Status: "+status,
      StringFormat("Base Balance: %s (%s)", FormatMoney(g_fixedBalanceBase), g_dashSizingText),
      StringFormat("Risk Budget: %s | %.2f lots", FormatMoney(g_dashRiskBudget), g_dashLots),
      "Pos: "+(posStr == "FLAT" ? "flat" : posStr),
      StringFormat("Session PnL: %s", FormatMoney(todayNet))
   };
   int fontSizes[] = {8, 8, 8, 8, 8, 8, 8, 8};
   int desiredWidth = FvgPanelDesiredWidth(rows, fontSizes);
   fvgPanelWidth = (int)MathMax(1, MathMin(desiredWidth, availableWidth));

   bool panelPresent = ObjectFind(0, FvgPanelPrefix()+"BG") >= 0 &&
                       ObjectFind(0, FvgPanelPrefix()+"BTN") >= 0 &&
                       (fvgPanelCollapsed || ObjectFind(0, FvgPanelPrefix()+"PNL") >= 0);
   bool unchanged = panelPresent && fvgPanelDrawn && !fvgPanelRestack && !fvgPanelLayoutDirty
                    && status == fvgPanelLastStatus && nyClockStr == fvgPanelLastClock
                    && posStr == fvgPanelLastPos && todayNet == fvgPanelLastNet
                    && fvgPanelWidth == fvgPanelLastWidth
                    && fvgPanelCollapsed == fvgPanelLastCollapsed
                    && g_dashRiskBudget == fvgPanelLastBudget
                    && g_dashLots == fvgPanelLastLots
                    && g_fixedBalanceBase == fvgPanelLastBase
                    && g_dashSizingText == fvgPanelLastSizing;
   if(unchanged) return;

   if(fvgPanelRestack) { fvgPanelRestack = false; ObjectsDeleteAll(0, FvgPanelPrefix()); fvgPanelDrawn = false; }
   FvgPanelShell();
   if(fvgPanelCollapsed)
   {
      fvgPanelDrawn = true; fvgPanelLayoutDirty = false;
      fvgPanelLastStatus = status; fvgPanelLastClock = nyClockStr;
      fvgPanelLastPos = posStr; fvgPanelLastNet = todayNet;
      fvgPanelLastWidth = fvgPanelWidth; fvgPanelLastCollapsed = true;
      fvgPanelLastBudget = g_dashRiskBudget; fvgPanelLastLots = g_dashLots;
      fvgPanelLastBase = g_fixedBalanceBase; fvgPanelLastSizing = g_dashSizingText;
      ChartRedraw(0);
      return;
   }

   bool live = (status == "OD TRIGGERED" || status == "TREND ACTIVE" ||
                StringFind(status, "ENTERED") >= 0);
   string p = FvgPanelPrefix();
   FvgPanelLbl(p+"CLK", PX+8, PY+38, FvgPanelFitText("NY "+nyClockStr+" | "+_Symbol, 8), 8, C'140,158,185');
   FvgPanelLbl(p+"OD",  PX+8, PY+56, FvgPanelFitText("Open Drive: 10m FVG | Stop 1.25%", 8), 8, C'140,200,240');
   FvgPanelLbl(p+"TRD", PX+8, PY+74, FvgPanelFitText("Trend FVG: 15m FVG | EMA 50/100 | 3.0R", 8), 8, C'140,200,240');
   FvgPanelLbl(p+"STAT",PX+8, PY+96, FvgPanelFitText("Status: "+status, 8), 8, live ? C'120,210,150' : C'190,210,236');
   ObjectSetString(0, p+"STAT", OBJPROP_TOOLTIP, "Status: "+status);

   FvgPanelLbl(p+"BAL", PX+8, PY+118, FvgPanelFitText(StringFormat("Base Balance: %s (%s)", FormatMoney(g_fixedBalanceBase), g_dashSizingText), 8), 8, C'140,158,185');
   FvgPanelLbl(p+"RIS", PX+8, PY+136, FvgPanelFitText(StringFormat("Risk Budget: %s | %.2f lots", FormatMoney(g_dashRiskBudget), g_dashLots), 8), 8, C'140,158,185');
   FvgPanelLbl(p+"POS", PX+8, PY+154, FvgPanelFitText("Pos: "+(posStr == "FLAT" ? "flat" : posStr), 8), 8, (posStr != "FLAT") ? C'120,210,150' : C'140,158,185');
   ObjectSetString(0, p+"POS", OBJPROP_TOOLTIP, "Position: "+posStr);
   FvgPanelLbl(p+"PNL", PX+8, PY+172, FvgPanelFitText(StringFormat("Session PnL: %s", FormatMoney(todayNet)), 8), 8, (todayNet >= 0.0) ? C'120,210,150' : C'220,110,110');

   fvgPanelDrawn = true; fvgPanelLayoutDirty = false;
   fvgPanelLastStatus = status; fvgPanelLastClock = nyClockStr;
   fvgPanelLastPos = posStr; fvgPanelLastNet = todayNet;
   fvgPanelLastWidth = fvgPanelWidth; fvgPanelLastCollapsed = fvgPanelCollapsed;
   fvgPanelLastBudget = g_dashRiskBudget; fvgPanelLastLots = g_dashLots;
   fvgPanelLastBase = g_fixedBalanceBase; fvgPanelLastSizing = g_dashSizingText;
   ChartRedraw(0);
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   bool panelObject = StringFind(sparam, FvgPanelPrefix()) == 0;
   bool ownedGeometry = StringFind(sparam, "FVG_") == 0 && !panelObject;
   if(id == CHARTEVENT_OBJECT_DELETE)
   {
      if(ownedGeometry) g_fvgVisualRepair = true;
      if(panelObject) fvgPanelLayoutDirty = true;
   }
   if(!DashboardAllowed()) return;
   // Queue geometry/native/foreign creation bursts. Timer flushes once rather
   // than deleting/rebuilding the panel for every EMA/arrow on chart open.
   bool restack = id == CHARTEVENT_OBJECT_CREATE && !panelObject;
   bool layout  = (id == CHARTEVENT_CHART_CHANGE);
   if(id == CHARTEVENT_OBJECT_CLICK && sparam == FvgPanelPrefix()+"BTN")
   {
      fvgPanelCollapsed = !fvgPanelCollapsed;
      restack = true;
   }
   if(layout) fvgPanelLayoutDirty = true;
   if(restack) fvgPanelRestack = true;
   // Click/resize feedback stays immediate. Creation batches are coalesced by
   // the display timer; neither event path evaluates signals or sends orders.
   if(layout || id == CHARTEVENT_OBJECT_CLICK)
      UpdateDashboard(fvgPanelStatus, fvgPanelClock, fvgPanelPosition, fvgPanelNet);
}

//+------------------------------------------------------------------+
//| FVG ZONE (Filled rectangle, exact setup span, no borders/text)   |
//+------------------------------------------------------------------+
void PruneFvgVisuals(datetime currentNyTime)
{
   if(currentNyTime <= 0) return;
   // Retain current NY day plus 2 prior NY days (3 days total).
   MqlDateTime dt;
   TimeToStruct(currentNyTime, dt);
   datetime todayFloor = currentNyTime - (dt.hour * 3600 + dt.min * 60 + dt.sec);
   datetime cutoff = (g_visualHistoryDay == todayFloor && g_visualHistoryCutoff > 0)
                     ? g_visualHistoryCutoff : todayFloor - 2 * 86400;
   g_visualCutoffNy = cutoff;

   for(int i = ObjectsTotal(0, -1, -1) - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, -1, -1);
      if(StringFind(name, "FVG_BOX_") == 0 ||
         StringFind(name, "FVG_TRADE_") == 0 ||
         StringFind(name, "FVG_SESSION_") == 0 ||
         StringFind(name, "FVG_EMA_") == 0)
      {
         if(g_visualTradePositionId > 0 && g_visualTradePrefix != "" &&
            StringFind(name, g_visualTradePrefix) == 0) continue; // Never hide current owned protection.
         datetime t = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 0);
         datetime ny = (t > 0) ? NYTime(t) : 0;
         if(ny > 0 && ny < cutoff)
            ObjectDelete(0, name);
      }
   }
   if(g_fvgCandidateName != "" && ObjectFind(0, g_fvgCandidateName) < 0)
      g_fvgCandidateName = "";
}

void ShowFvgCandidate(string setup, datetime t0, double p0, datetime t1, double p1, bool isBull)
{
   if(!VisualsAllowed()) return;
   string name = "FVG_BOX_" + setup + "_" + TimeToString(t0, TIME_DATE|TIME_MINUTES|TIME_SECONDS);
   g_fvgCandidateName = name;
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t0 + 1, p0, t1 - 1, p1);
      ObjectSetInteger(0, name, OBJPROP_FILL, false);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   color clr = isBull ? C'40,110,80' : C'120,50,50';
   ObjectSetInteger(0, name, OBJPROP_COLOR, (long)clr);
   ObjectSetString(0, name, OBJPROP_TOOLTIP,
      StringFormat("FVG Duo | %s | Current %s FVG\nNY %s -> %s\nBounds %.2f / %.2f | Gap %.2f points\nC1+1s through C3 close-1s",
         setup, isBull ? "Bull" : "Bear", TimeToString(NYTime(t0+1), TIME_DATE|TIME_SECONDS),
         TimeToString(NYTime(t1-1), TIME_DATE|TIME_SECONDS), MathMax(p0,p1), MathMin(p0,p1), MathAbs(p1-p0)));
   ChartRedraw(0);
}

void MarkFvgCandidateTraded()
{
   if(g_fvgCandidateName != "" && ObjectFind(0, g_fvgCandidateName) >= 0)
   {
      ObjectSetInteger(0, g_fvgCandidateName, OBJPROP_STYLE, STYLE_SOLID);
      string detail = ObjectGetString(0, g_fvgCandidateName, OBJPROP_TOOLTIP);
      StringReplace(detail, "Current", "History (consumed)");
      ObjectSetString(0, g_fvgCandidateName, OBJPROP_TOOLTIP, detail);
      g_fvgCandidateName = "";
   }
}

void UpdateSessionVisual(datetime currentServerTime, datetime nySessionStart, datetime nySessionEnd, double highPx, double lowPx)
{
   if(!VisualsAllowed()) return;
   MqlDateTime dt;
   TimeToStruct(NYTime(nySessionStart), dt);
   string dayStr = StringFormat("%04d%02d%02d", dt.year, dt.mon, dt.day);
   string name = "FVG_SESSION_" + dayStr;

   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, nySessionStart, lowPx, nySessionEnd, highPx);
      ObjectSetInteger(0, name, OBJPROP_FILL, true);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_COLOR, (long)C'27,42,58');
   }
   else
   {
      double curLow = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
      double curHigh = ObjectGetDouble(0, name, OBJPROP_PRICE, 1);
      if(lowPx < curLow)  ObjectMove(0, name, 0, nySessionStart, lowPx);
      if(highPx > curHigh) ObjectMove(0, name, 1, nySessionEnd, highPx);
   }
   double rangeLow = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
   double rangeHigh = ObjectGetDouble(0, name, OBJPROP_PRICE, 1);
   ObjectSetString(0, name, OBJPROP_TOOLTIP,
      StringFormat("FVG Duo | NY cash-session range\nNY %s -> %s\nHigh %.2f | Low %.2f | Range %.2f points\nObserved completed M1 bars; not a stop/target",
         TimeToString(NYTime(nySessionStart), TIME_DATE|TIME_MINUTES),
         TimeToString(NYTime(nySessionEnd), TIME_DATE|TIME_MINUTES), rangeHigh, rangeLow, rangeHigh-rangeLow));
   ChartRedraw(0);
}

void UpdateObservedSessionVisual(datetime serverTime, datetime nyTime, int endMinute, double highPx, double lowPx)
{
   if(!VisualsAllowed() || serverTime <= 0 || nyTime <= 0) return;
   MqlDateTime dt;
   TimeToStruct(nyTime, dt);
   int minute = dt.hour * 60 + dt.min;
   if(minute < 570 || minute >= endMinute) return;
   datetime nyDay = nyTime - (dt.hour * 3600 + dt.min * 60 + dt.sec);
   datetime offset = serverTime - nyTime;
   UpdateSessionVisual(serverTime, nyDay + 570 * 60 + offset,
                        nyDay + endMinute * 60 + offset, highPx, lowPx);
}

void ShowTrendAverages(datetime t0, datetime t1, double fastPrev, double fastCurr, double slowPrev, double slowCurr)
{
   if(!VisualsAllowed()) return;
   string fastName = "FVG_EMA_FAST_" + TimeToString(t1, TIME_DATE|TIME_MINUTES);
   string slowName = "FVG_EMA_SLOW_" + TimeToString(t1, TIME_DATE|TIME_MINUTES);

   if(ObjectFind(0, fastName) < 0)
   {
      ObjectCreate(0, fastName, OBJ_TREND, 0, t0, fastPrev, t1, fastCurr);
      ObjectSetInteger(0, fastName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, fastName, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, fastName, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, fastName, OBJPROP_RAY_LEFT, false);
      ObjectSetInteger(0, fastName, OBJPROP_BACK, true);
      ObjectSetInteger(0, fastName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, fastName, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, fastName, OBJPROP_COLOR, (long)C'52,120,200');
   }
   if(ObjectFind(0, slowName) < 0)
   {
      ObjectCreate(0, slowName, OBJ_TREND, 0, t0, slowPrev, t1, slowCurr);
      ObjectSetInteger(0, slowName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, slowName, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, slowName, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, slowName, OBJPROP_RAY_LEFT, false);
      ObjectSetInteger(0, slowName, OBJPROP_BACK, true);
      ObjectSetInteger(0, slowName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, slowName, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, slowName, OBJPROP_COLOR, (long)C'180,120,40');
   }
   ObjectMove(0, fastName, 0, t0, fastPrev); ObjectMove(0, fastName, 1, t1, fastCurr);
   ObjectMove(0, slowName, 0, t0, slowPrev); ObjectMove(0, slowName, 1, t1, slowCurr);
   string span = "\nNY " + TimeToString(NYTime(t0), TIME_DATE|TIME_MINUTES) + " -> " + TimeToString(NYTime(t1), TIME_DATE|TIME_MINUTES);
   ObjectSetString(0, fastName, OBJPROP_TOOLTIP, StringFormat("FVG Duo | EMA 50 | Completed M15\nPrevious %.2f -> Current %.2f", fastPrev, fastCurr)+span);
   ObjectSetString(0, slowName, OBJPROP_TOOLTIP, StringFormat("FVG Duo | EMA 100 | Completed M15\nPrevious %.2f -> Current %.2f", slowPrev, slowCurr)+span);
   ChartRedraw(0);
}

void ShowTradeGeometry(int side, datetime t0, datetime tEnd, double entryPx, double stopPx, double targetPx, ulong positionId = 0, string source = "")
{
   if(!VisualsAllowed()) return;
   g_visualTradeSide = side;
   g_visualTradeStart = t0;
   g_visualTradeEnd = tEnd;
   g_visualTradeEntry = entryPx;
   g_visualTradeStop = stopPx;
   g_visualTradeTarget = targetPx;
   g_visualTradePositionId = positionId;
   g_visualTradeSource = source;

   string prefix = "FVG_TRADE_" + (positionId > 0 ? IntegerToString((long)positionId) : TimeToString(t0, TIME_DATE|TIME_MINUTES|TIME_SECONDS)) + "_";
   g_visualTradePrefix = prefix;

   string entryName = prefix + "ENTRY";
   string stopName = prefix + "STOP";
   string targetName = prefix + "TARGET";

   if(ObjectFind(0, entryName) < 0)
   {
      ObjectCreate(0, entryName, OBJ_TREND, 0, t0, entryPx, tEnd, entryPx);
      ObjectSetInteger(0, entryName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, entryName, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, entryName, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, entryName, OBJPROP_BACK, false);
      ObjectSetInteger(0, entryName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, entryName, OBJPROP_HIDDEN, true);
   }
   ObjectMove(0, entryName, 0, t0, entryPx);
   ObjectMove(0, entryName, 1, tEnd, entryPx);
   ObjectSetInteger(0, entryName, OBJPROP_COLOR, clrWhite);
   string context = StringFormat("\n%s | %s | Position #%I64u\nNY %s -> %s", source,
      side > 0 ? "LONG" : "SHORT", positionId,
      TimeToString(NYTime(t0), TIME_DATE|TIME_SECONDS), TimeToString(NYTime(tEnd), TIME_DATE|TIME_SECONDS));
   ObjectSetString(0, entryName, OBJPROP_TOOLTIP, StringFormat("FVG Duo | Entry\nFill %.2f", entryPx)+context);

   double stopTop = MathMax(entryPx, stopPx);
   double stopBot = MathMin(entryPx, stopPx);
   if(ObjectFind(0, stopName) < 0)
   {
      ObjectCreate(0, stopName, OBJ_RECTANGLE, 0, t0, stopBot, tEnd, stopTop);
      ObjectSetInteger(0, stopName, OBJPROP_FILL, false);
      ObjectSetInteger(0, stopName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, stopName, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, stopName, OBJPROP_BACK, false);
      ObjectSetInteger(0, stopName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, stopName, OBJPROP_HIDDEN, true);
   }
   ObjectMove(0, stopName, 0, t0, stopBot);
   ObjectMove(0, stopName, 1, tEnd, stopTop);
   ObjectSetInteger(0, stopName, OBJPROP_COLOR, (long)C'55,65,81');
   ObjectSetString(0, stopName, OBJPROP_TOOLTIP,
      StringFormat("FVG Duo | Stop-loss | Accepted protection\nEntry %.2f | SL %.2f | Distance %.2f points", entryPx, stopPx, MathAbs(entryPx-stopPx))+context);

   if(targetPx > 0.0)
   {
      double tgtTop = MathMax(entryPx, targetPx);
      double tgtBot = MathMin(entryPx, targetPx);
      if(ObjectFind(0, targetName) < 0)
      {
         ObjectCreate(0, targetName, OBJ_RECTANGLE, 0, t0, tgtBot, tEnd, tgtTop);
         ObjectSetInteger(0, targetName, OBJPROP_FILL, false);
         ObjectSetInteger(0, targetName, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, targetName, OBJPROP_STYLE, STYLE_SOLID);
         ObjectSetInteger(0, targetName, OBJPROP_BACK, false);
         ObjectSetInteger(0, targetName, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, targetName, OBJPROP_HIDDEN, true);
      }
      ObjectMove(0, targetName, 0, t0, tgtBot);
      ObjectMove(0, targetName, 1, tEnd, tgtTop);
      ObjectSetInteger(0, targetName, OBJPROP_COLOR, (long)C'56,189,248');
      ObjectSetString(0, targetName, OBJPROP_TOOLTIP,
         StringFormat("FVG Duo | Take-profit | Accepted price target\nEntry %.2f | TP %.2f | Distance %.2f points", entryPx, targetPx, MathAbs(targetPx-entryPx))+context);
   }
   else
   {
      ObjectDelete(0, targetName);
   }
   ChartRedraw(0);
}

void FinishTradeGeometry(datetime exitServer, double exitPrice, string reason)
{
   if(!VisualsAllowed() || g_visualTradePositionId == 0 ||
      exitServer < g_visualTradeStart || !MathIsValidNumber(exitPrice) ||
      exitPrice <= 0.0 || reason == "UNCONFIRMED") return;
   double target = g_visualTradeTarget;
   bool realizedProfit = (target <= 0.0 && g_visualTradeSide * (exitPrice - g_visualTradeEntry) > 0.0);
   if(realizedProfit) target = exitPrice;
   ShowTradeGeometry(g_visualTradeSide, g_visualTradeStart, exitServer,
                      g_visualTradeEntry, g_visualTradeStop, target,
                      g_visualTradePositionId, g_visualTradeSource);
   string detail = StringFormat("FVG Duo | %s | Booked %s exit @ %.2f\nNY %s -> %s\nEntry %.2f | SL %.2f | Position #%I64u",
                                 g_visualTradeSource, reason, exitPrice,
                                 TimeToString(NYTime(g_visualTradeStart), TIME_DATE|TIME_SECONDS),
                                 TimeToString(NYTime(exitServer), TIME_DATE|TIME_SECONDS),
                                 g_visualTradeEntry, g_visualTradeStop, g_visualTradePositionId);
   ObjectSetString(0, g_visualTradePrefix+"ENTRY", OBJPROP_TOOLTIP, detail);
   if(realizedProfit)
      ObjectSetString(0, g_visualTradePrefix+"TARGET", OBJPROP_TOOLTIP,
                       detail+" | Realized profit, no resting TP");
   g_visualTradePositionId = 0;
   g_visualTradePrefix = "";
   ChartRedraw(0);
}

void RemoveVisuals()
{
   ObjectsDeleteAll(0, FvgPanelPrefix());
   fvgPanelDrawn = false;
   for(int i = ObjectsTotal(0, -1, -1) - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, -1, -1);
      if(StringFind(name, "FVG_") == 0)
         ObjectDelete(0, name);
   }
   RestorePanelLayering();
   ChartRedraw(0);
}

#endif
