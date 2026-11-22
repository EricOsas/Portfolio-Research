//+------------------------------------------------------------------+
//|                                                 ChartVisuals.mqh |
//|        Copyright 2026-2027, Osamwonyi Eric (@You_FoundEric)      |
//|                                      https://x.com/You_FoundEric |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026-2027, Osamwonyi Eric (@You_FoundEric)"
#property link      "https://x.com/You_FoundEric"
#property strict

#include <Canvas\Canvas.mqh>
#include <Trade\PositionInfo.mqh>

extern CPositionInfo posinfo;

// Global Canvas
CCanvas g_gradientCanvas;
bool    g_panelCollapsed = false;
bool    g_panelRestack = false;
int     g_origObjectCreateEvent = -1;
int     g_origChartForeground = -1;
ulong   g_lastVisualRefreshMs = 0;
int     g_gradientWidth = 0;
int     g_gradientHeight = 0;
color   g_gradientColor = clrNONE;

// Colors matching VaultBreak / Wayward theme
color CLR_PANEL_BG      = C'15,20,30';
color CLR_PANEL_BORDER  = C'40,55,80';
color CLR_TEXT_TITLE    = C'239,159,39';  // Orange
color CLR_TEXT_BODY     = C'218,229,242'; // Light Blue-Gray
color CLR_TEXT_MUTED    = C'124,138,160'; // Gray-Blue
color CLR_TEXT_POS      = C'93,202,165';  // Green/Teal
color CLR_TEXT_NEG      = C'226,75,74';   // Red

//+------------------------------------------------------------------+
//| Color Interpolation for Gradient Steps                           |
//+------------------------------------------------------------------+
uint ColorToXRGB(color clr) {
    uint r = (clr) & 0xFF;
    uint g = (clr >> 8) & 0xFF;
    uint b = (clr >> 16) & 0xFF;
    return (0xFF000000 | (r << 16) | (g << 8) | b);
}

color CalculateGradientColor(color colorStart, color colorEnd, int steps, int step) {
    if (steps <= 0 || step <= 0) return colorStart;
    if (step >= steps) return colorEnd;

    int r1 = colorStart & 0xFF, g1 = (colorStart >> 8) & 0xFF, b1 = (colorStart >> 16) & 0xFF;
    int r2 = colorEnd & 0xFF,   g2 = (colorEnd >> 8) & 0xFF,   b2 = (colorEnd >> 16) & 0xFF;

    int r = r1 + (int)((r2 - r1) * (double)step / steps);
    int g = g1 + (int)((g2 - g1) * (double)step / steps);
    int b = b1 + (int)((b2 - b1) * (double)step / steps);

    return (color)(r | (g << 8) | (b << 16));
}

//+------------------------------------------------------------------+
//| Draw Wayward-Style CCanvas Top-to-Bottom Background Gradient     |
//+------------------------------------------------------------------+
bool X9VisualMode() {
    return !(bool)MQLInfoInteger(MQL_TESTER) || (bool)MQLInfoInteger(MQL_VISUAL_MODE);
}

void DrawGradientBackground() {
    if (!ShowGradientBg || !X9VisualMode()) return;

    int chartWidth = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
    int chartHeight = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);

    if (chartWidth <= 0 || chartHeight <= 0) return;

    string canvasName = "GoldX9_GradientBg";
    if (ObjectFind(0, canvasName) >= 0 && chartWidth == g_gradientWidth &&
        chartHeight == g_gradientHeight && GradientEndColor == g_gradientColor) return;
    if (ObjectFind(0, canvasName) < 0) {
        if (!g_gradientCanvas.CreateBitmapLabel(0, 0, canvasName, 0, 0, chartWidth, chartHeight, COLOR_FORMAT_XRGB_NOALPHA)) return;
        ObjectSetInteger(0, canvasName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, canvasName, OBJPROP_XDISTANCE, 0);
        ObjectSetInteger(0, canvasName, OBJPROP_YDISTANCE, 0);
        ObjectSetInteger(0, canvasName, OBJPROP_BACK, true);
        ObjectSetInteger(0, canvasName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, canvasName, OBJPROP_HIDDEN, true);
    } else {
        if (!g_gradientCanvas.Resize(chartWidth, chartHeight)) return;
    }

    int steps = chartHeight;
    color startColor = clrBlack;

    for (int y = 0; y < chartHeight; y++) {
        color stepClr = CalculateGradientColor(GradientEndColor, startColor, steps, y);
        uint xrgb = ColorToXRGB(stepClr);
        g_gradientCanvas.LineHorizontal(0, chartWidth - 1, y, xrgb);
    }

    g_gradientCanvas.Update();
    g_gradientWidth = chartWidth;
    g_gradientHeight = chartHeight;
    g_gradientColor = GradientEndColor;
}

void DeleteGradientBackground() {
    g_gradientCanvas.Destroy();
    ObjectDelete(0, "GoldX9_GradientBg");
    g_gradientWidth = 0;
    g_gradientHeight = 0;
    g_gradientColor = clrNONE;
}

//+------------------------------------------------------------------+
//| VaultBreak-Style Label & Rect Helpers                            |
//+------------------------------------------------------------------+
void CreatePanelRect(string name, int x, int y, int w, int h, color bg, color bdr) {
    if (ObjectFind(0, name) < 0) {
        ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
        ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
        ObjectSetInteger(0, name, OBJPROP_BACK, false);
        ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
    }
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
    ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
    ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
    ObjectSetInteger(0, name, OBJPROP_COLOR, bdr);
}

void CreatePanelLabel(string name, int x, int y, string text, int fontSize, color clr) {
    if (ObjectFind(0, name) < 0) {
        ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
        ObjectSetInteger(0, name, OBJPROP_BACK, false);
        ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI");
    }
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

int PanelTextWidth(string text, int fontSize) {
    if (!TextSetFont("Segoe UI", -fontSize * 10)) return StringLen(text) * fontSize * 2;
    uint width = 0;
    uint height = 0;
    if (!TextGetSize(text, width, height)) return StringLen(text) * fontSize * 2;
    return (int)width;
}

void CreatePanelButton(string name, int x, int y, int w, int h, string text) {
    if (ObjectFind(0, name) < 0) {
        ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
        ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
        ObjectSetInteger(0, name, OBJPROP_BACK, false);
        ObjectSetInteger(0, name, OBJPROP_STATE, false);
        ObjectSetInteger(0, name, OBJPROP_ZORDER, 1000);
        ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI");
    }
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
    ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
    ObjectSetInteger(0, name, OBJPROP_COLOR, CLR_TEXT_TITLE);
    ObjectSetInteger(0, name, OBJPROP_BGCOLOR, CLR_PANEL_BG);
    ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, CLR_PANEL_BORDER);
    ObjectSetString(0, name, OBJPROP_TEXT, text);
}

void PollX9PanelButton() {
    // Visual Tester does not reliably deliver EA OnChartEvent callbacks.
    if (ObjectGetInteger(0, "GoldX9_PanelToggle", OBJPROP_STATE) != 0) {
        ObjectSetInteger(0, "GoldX9_PanelToggle", OBJPROP_STATE, false);
        g_panelCollapsed = !g_panelCollapsed;
        g_lastVisualRefreshMs = 0;
    }
}

//+------------------------------------------------------------------+
//| Paint-order layering                                              |
//| MT5 paints chart objects in creation order, so executions and other|
//| objects created after the panel render on top of it. Recreating    |
//| only the X9 panel objects after a non-panel object appears puts    |
//| them back on top without touching foreign or native objects.       |
//+------------------------------------------------------------------+
void EnablePanelLayering() {
    if (g_origObjectCreateEvent < 0) {
        g_origObjectCreateEvent = (int)ChartGetInteger(0, CHART_EVENT_OBJECT_CREATE);
        g_origChartForeground = (int)ChartGetInteger(0, CHART_FOREGROUND);
    }
    if (g_origObjectCreateEvent == 0) ChartSetInteger(0, CHART_EVENT_OBJECT_CREATE, true);
    if (g_origChartForeground != 0) ChartSetInteger(0, CHART_FOREGROUND, false);
}

void RestorePanelLayering() {
    if (g_origObjectCreateEvent < 0) return;
    ChartSetInteger(0, CHART_EVENT_OBJECT_CREATE, g_origObjectCreateEvent != 0);
    ChartSetInteger(0, CHART_FOREGROUND, g_origChartForeground != 0);
    g_origObjectCreateEvent = -1;
    g_origChartForeground = -1;
}

void RestackPanelObjects() {
    ObjectsDeleteAll(0, "GoldX9_Row_");
    ObjectDelete(0, "GoldX9_Header");
    ObjectDelete(0, "GoldX9_PanelToggle");
    ObjectDelete(0, "GoldX9_PanelBg");
    g_panelRestack = false;
}

//+------------------------------------------------------------------+
//| Render VaultBreak-Style Segoe UI Collapsible Info Panel           |
//+------------------------------------------------------------------+
void RenderInfoPanel() {
    if (!ShowInfoPanel || !X9VisualMode()) return;
    PollX9PanelButton();
    EnablePanelLayering();

    ulong tick = GetTickCount64();
    bool restack = g_panelRestack;
    if (!restack && g_lastVisualRefreshMs > 0 && tick - g_lastVisualRefreshMs < 1000) return;

    int chartWidth = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
    int chartHeight = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
    if (chartWidth <= 0 || chartHeight <= 0) return;
    g_lastVisualRefreshMs = tick;
    if (restack) RestackPanelObjects();
    int x = 15, y = 15;
    int bodyFont = (chartWidth < 500) ? 8 : 9;
    int titleFont = (chartWidth < 500) ? 9 : 10;
    int rowHeight = 20;

    string headerText = (chartWidth < 500) ? "GOLD X9 v6.3 | PORTFOLIO" : "GOLD X9 v6.3 | INSTITUTIONAL PORTFOLIO";
    int panelWidth = PanelTextWidth(headerText, titleFont) + 58;

    if (g_panelCollapsed) {
        CreatePanelRect("GoldX9_PanelBg", x, y, panelWidth, 32, CLR_PANEL_BG, CLR_PANEL_BORDER);
        CreatePanelLabel("GoldX9_Header", x + 10, y + 6, headerText, titleFont, CLR_TEXT_TITLE);
        CreatePanelButton("GoldX9_PanelToggle", x + panelWidth - 36, y + 4, 28, 24, "+");
        ObjectsDeleteAll(0, "GoldX9_Row_");
        ChartRedraw(0);
        return;
    }

    // Read Account & P/L Metrics
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
    string accountCurrency = AccountInfoString(ACCOUNT_CURRENCY);
    if (accountCurrency == "") accountCurrency = "USD";

    double openPL = 0.0;
    for (int p = PositionsTotal() - 1; p >= 0; p--) {
        if (posinfo.SelectByIndex(p)) {
            if (posinfo.Magic() >= InpMagic && posinfo.Magic() <= InpMagic + 20 && posinfo.Symbol() == TradeSym) {
                openPL += posinfo.Profit() + posinfo.Swap();
            }
        }
    }

    double totalRealizedPL = 0.0;
    int stratTrades[9] = {0}, stratWins[9] = {0};
    double stratPL[9] = {0.0};

    if (HistorySelect(0, TimeCurrent() + 86400)) {
        int totalDeals = HistoryDealsTotal();
        for (int d = 0; d < totalDeals; d++) {
            ulong ticket = HistoryDealGetTicket(d);
            if (ticket == 0) continue;

            long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
            if (magic < InpMagic || magic > InpMagic + 20) continue;
            if (HistoryDealGetString(ticket, DEAL_SYMBOL) != TradeSym) continue;

            ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
            if (entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT) {
                double p = HistoryDealGetDouble(ticket, DEAL_PROFIT);
                double comm = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
                double swap = HistoryDealGetDouble(ticket, DEAL_SWAP);
                double netP = p + comm + swap;

                totalRealizedPL += netP;

                int sIdx = (int)(magic - InpMagic - 1);
                if (sIdx >= 0 && sIdx < 9) {
                    stratTrades[sIdx]++;
                    if (netP >= 0.0) stratWins[sIdx]++;
                    stratPL[sIdx] += netP;
                }
            }
        }
    }

    string statusStr = "NORMAL";
    color statusClr = CLR_TEXT_POS;

    if (g_totalBreached)     { statusStr = "TOTAL DD BREACH"; statusClr = CLR_TEXT_NEG; }
    else if (g_dailyBreached){ statusStr = "DAILY DD BREACH"; statusClr = CLR_TEXT_NEG; }
    else if (News_Impact != NEWS_DISABLED && !NewsValid()) { statusStr = "NEWS UNAVAILABLE"; statusClr = CLR_TEXT_TITLE; }
    else if (g_newsFlattenActive) { statusStr = "PRE-NEWS FLATTEN"; statusClr = CLR_TEXT_TITLE; }
    else if (g_newsBlocked)  { statusStr = "NEWS BLACKOUT"; statusClr = CLR_TEXT_TITLE; }

    string acctStr = StringFormat("Balance: %s%.2f  |  Equity: %s%.2f", accountCurrency, balance, accountCurrency, equity);
    string plStr = StringFormat("Open P/L: %s%.2f  |  Realized P/L: %s%.2f", accountCurrency, openPL, accountCurrency, totalRealizedPL);
    string rawLines[3];
    rawLines[0] = "Status: " + statusStr + "  |  " + GetNYTimeString();
    rawLines[1] = acctStr;
    rawLines[2] = plStr;
    color rawColors[3];
    rawColors[0] = statusClr;
    rawColors[1] = CLR_TEXT_BODY;
    rawColors[2] = (openPL < 0.0 || totalRealizedPL < 0.0) ? CLR_TEXT_BODY : CLR_TEXT_POS;
    string lines[6];
    color lineColors[6];
    int lineCount = 0;
    for (int i = 0; i < 3; i++) {
        int separator = StringFind(rawLines[i], "  |  ");
        if (separator >= 0 && PanelTextWidth(rawLines[i], bodyFont) > chartWidth - 2 * x - 20) {
            lines[lineCount] = StringSubstr(rawLines[i], 0, separator);
            lineColors[lineCount++] = rawColors[i];
            lines[lineCount] = StringSubstr(rawLines[i], separator + 5);
            lineColors[lineCount++] = rawColors[i];
        } else {
            lines[lineCount] = rawLines[i];
            lineColors[lineCount++] = rawColors[i];
        }
    }
    for (int i = 0; i < lineCount; i++) panelWidth = MathMax(panelWidth, PanelTextWidth(lines[i], bodyFont) + 20);

    string headings[5] = {"Strategy", "Magic", "Exits", "Win %", "Net P/L"};
    string table[9][5];
    int columnWidths[5] = {0};
    for (int c = 0; c < 5; c++) columnWidths[c] = PanelTextWidth(headings[c], bodyFont);
    for (int i = 0; i < 9; i++) {
        int magic = InpMagic + i + 1;
        double winRate = (stratTrades[i] > 0) ? ((double)stratWins[i] / stratTrades[i] * 100.0) : 0.0;
        table[i][0] = "Strategy " + IntegerToString(i + 1);
        table[i][1] = IntegerToString(magic);
        table[i][2] = IntegerToString(stratTrades[i]);
        table[i][3] = StringFormat("%.1f%%", winRate);
        table[i][4] = StringFormat("%s%.2f", accountCurrency, stratPL[i]);
        for (int c = 0; c < 5; c++) columnWidths[c] = MathMax(columnWidths[c], PanelTextWidth(table[i][c], bodyFont));
    }
    int tableWidth = 48;
    for (int c = 0; c < 5; c++) tableWidth += columnWidths[c];
    bool compactTable = tableWidth + 20 > chartWidth - 2 * x;
    if (!compactTable) panelWidth = MathMax(panelWidth, tableWidth + 20);
    else {
        for (int i = 0; i < 9; i++) {
            panelWidth = MathMax(panelWidth, PanelTextWidth(table[i][0] + " | Magic " + table[i][1], bodyFont) + 20);
            panelWidth = MathMax(panelWidth, PanelTextWidth("Exits: " + table[i][2] + " | Win: " + table[i][3] + " | P/L: " + table[i][4], bodyFont) + 20);
        }
    }

    int panelHeight = 32 + lineCount * rowHeight + 6 + (compactTable ? 18 : 10) * rowHeight + 10;
    CreatePanelRect("GoldX9_PanelBg", x, y, panelWidth, panelHeight, CLR_PANEL_BG, CLR_PANEL_BORDER);
    CreatePanelLabel("GoldX9_Header", x + 10, y + 6, headerText, titleFont, CLR_TEXT_TITLE);
    CreatePanelButton("GoldX9_PanelToggle", x + panelWidth - 36, y + 4, 28, 24, "-");
    int currY = y + 32;
    int row = 0;
    for (int i = 0; i < lineCount; i++) {
        CreatePanelLabel("GoldX9_Row_" + IntegerToString(row++), x + 10, currY, lines[i], bodyFont, lineColors[i]);
        currY += rowHeight;
    }
    currY += 6;
    if (!compactTable) {
        int currX = x + 10;
        for (int c = 0; c < 5; c++) {
            CreatePanelLabel("GoldX9_Row_" + IntegerToString(row++), currX, currY, headings[c], bodyFont, CLR_TEXT_MUTED);
            currX += columnWidths[c] + 12;
        }
        currY += rowHeight;
    }
    for (int i = 0; i < 9; i++) {
        color rowClr = (stratPL[i] > 0.0) ? CLR_TEXT_POS : ((stratPL[i] < 0.0) ? CLR_TEXT_NEG : CLR_TEXT_BODY);
        if (compactTable) {
            CreatePanelLabel("GoldX9_Row_" + IntegerToString(row++), x + 10, currY, table[i][0] + " | Magic " + table[i][1], bodyFont, CLR_TEXT_BODY);
            currY += rowHeight;
            CreatePanelLabel("GoldX9_Row_" + IntegerToString(row++), x + 10, currY, "Exits: " + table[i][2] + " | Win: " + table[i][3] + " | P/L: " + table[i][4], bodyFont, rowClr);
        } else {
            int currX = x + 10;
            for (int c = 0; c < 5; c++) {
                CreatePanelLabel("GoldX9_Row_" + IntegerToString(row++), currX, currY, table[i][c], bodyFont, rowClr);
                currX += columnWidths[c] + 12;
            }
        }
        currY += rowHeight;
    }
    for (int i = row; i < 64; i++) ObjectDelete(0, "GoldX9_Row_" + IntegerToString(i));
    ChartRedraw(0);
}

void DeleteInfoPanel() {
    ObjectsDeleteAll(0, "GoldX9_Row_");
    ObjectDelete(0, "GoldX9_Header");
    ObjectDelete(0, "GoldX9_PanelToggle");
    ObjectDelete(0, "GoldX9_PanelBg");
    g_panelRestack = false;
    RestorePanelLayering();
}

//+------------------------------------------------------------------+
//| Chart Event Handler for Panel Collapse Toggle                    |
//+------------------------------------------------------------------+
void ProcessVisualChartEvent(const int id, const long& lparam, const double& dparam, const string& sparam) {
    if (id == CHARTEVENT_OBJECT_CLICK) {
        if (sparam == "GoldX9_PanelToggle" || sparam == "GoldX9_Header" || sparam == "GoldX9_PanelBg") {
            ObjectSetInteger(0, "GoldX9_PanelToggle", OBJPROP_STATE, false);
            g_panelCollapsed = !g_panelCollapsed;
            g_lastVisualRefreshMs = 0; // Force immediate redraw
            RenderInfoPanel();
        }
    } else if (id == CHARTEVENT_CHART_CHANGE) {
        DrawGradientBackground();
        g_lastVisualRefreshMs = 0;
        RenderInfoPanel();
    } else if (id == CHARTEVENT_OBJECT_CREATE) {
        // Anything drawn after the panel paints above it; queue a panel rebuild.
        if (StringFind(sparam, "GoldX9_") != 0) {
            g_panelRestack = true;
            g_lastVisualRefreshMs = 0;
            RenderInfoPanel();
        }
    }
}
