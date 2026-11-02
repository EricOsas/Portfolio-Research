#ifndef RBE_CHART_VISUALS
#define RBE_CHART_VISUALS
void RBEPoint(string name,int point,datetime time,double price)
{
    if((datetime)ObjectGetInteger(0,name,OBJPROP_TIME,point)!=time) ObjectSetInteger(0,name,OBJPROP_TIME,point,time);
    if(ObjectGetDouble(0,name,OBJPROP_PRICE,point)!=price) ObjectSetDouble(0,name,OBJPROP_PRICE,point,price);
}
void RBETip(string name,string description)
{
    if(ObjectFind(0,name)>=0 && ObjectGetString(0,name,OBJPROP_TOOLTIP)!=description)
        ObjectSetString(0,name,OBJPROP_TOOLTIP,description);
}
bool RBEOrderInSession(datetime placed,datetime rangeLock,datetime cutoff)
{
    return placed>=rangeLock && placed<cutoff;
}
void RBEOverlayBroker(datetime now)
{
    datetime first=g_view[0].open>0 ? g_view[0].open : (g_view[1].open>0 ? g_view[1].open : g_view[2].open);
    if(first<=0 || !HistorySelect(first,now)) return;
    int count=HistoryDealsTotal();
    for(int slot=0;slot<3;slot++)
    for(int side=0;side<2;side++)
    {
        if(g_view[slot].open<=0) continue;
        ulong position=0;
        double inLots=0,outLots=0,inValue=0,outValue=0;
        datetime entryTime=0,exitTime=0;
        double originalSL=0;
        bool stopped=false;
        for(int i=0;i<count;i++)
        {
            ulong deal=HistoryDealGetTicket(i);
            if(HistoryDealGetInteger(deal,DEAL_MAGIC)!=Magic || HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol) continue;
            datetime time=(datetime)HistoryDealGetInteger(deal,DEAL_TIME);
            ulong id=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
            ENUM_DEAL_ENTRY type=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY);
            bool buy=(ENUM_DEAL_TYPE)HistoryDealGetInteger(deal,DEAL_TYPE)==DEAL_TYPE_BUY;
            double lots=HistoryDealGetDouble(deal,DEAL_VOLUME),price=HistoryDealGetDouble(deal,DEAL_PRICE);
            ulong entryOrder=(ulong)HistoryDealGetInteger(deal,DEAL_ORDER);
            datetime placed=(datetime)HistoryOrderGetInteger(entryOrder,ORDER_TIME_SETUP);
            // Session ownership follows the pending order's creation, not a
            // late broker fill. A stale prior-day stop must never replace this
            // day's independent synthetic range trade.
            if(type==DEAL_ENTRY_IN && buy==(side==0) && RBEOrderInSession(placed,g_view[slot].lock,g_view[slot].cutoff))
            {
                if(position!=0 && position!=id) continue;
                position=id; if(entryTime==0) entryTime=time;
                if(originalSL<=0) originalSL=HistoryOrderGetDouble(entryOrder,ORDER_SL);
                inLots+=lots; inValue+=lots*price;
            }
            else if(position!=0 && id==position && (type==DEAL_ENTRY_OUT || type==DEAL_ENTRY_OUT_BY))
            {
                outLots+=lots; outValue+=lots*price; exitTime=time;
                stopped=(ENUM_DEAL_REASON)HistoryDealGetInteger(deal,DEAL_REASON)==DEAL_REASON_SL;
            }
        }
        if(inLots<=0) continue;
        RBEViewTrade t;
        ZeroMemory(t);
        t.actual=true; t.filled=true; t.buy=(side==0); t.entry=inValue/inLots; t.fillTime=entryTime;
        t.initialSL=originalSL>0 ? originalSL : NormalizeDouble(t.entry+(t.buy ? -g_view[slot].high : g_view[slot].low)*Stop_Value/100,_Digits);
        t.stop=t.initialSL;
        if(outLots+1e-8>=inLots)
        {
            t.resolved=true; t.exitTime=exitTime; t.exitPrice=outValue/outLots;
            if(!stopped && exitTime>=g_view[slot].cutoff && exitTime<g_view[slot].cutoff+60)
            {
                MqlRates close[];
                if(now>=g_view[slot].cutoff+60 && CopyRates(_Symbol,PERIOD_M1,g_view[slot].cutoff,g_view[slot].cutoff,close)==1)
                { t.exitTime=g_view[slot].cutoff+59; t.exitPrice=close[0].close; }
                else t.resolved=false; // Await the timed-exit candle's final close.
            }
        }
        else
        {
            t.resolved=false;
            for(int p=0;p<PositionsTotal();p++)
            {
                if(PositionGetTicket(p)==0 || (ulong)PositionGetInteger(POSITION_IDENTIFIER)!=position) continue;
                t.stop=PositionGetDouble(POSITION_SL);
            }
        }
        if(side==0) g_view[slot].buy=t; else g_view[slot].sell=t;
    }
}
void RBEBox(string name,datetime left,datetime right,double a,double b,color shade,bool filled=true)
{
    if(right<=left || a==b) return;
    if(ObjectFind(0,name)<0)
    {
        ObjectCreate(0,name,OBJ_RECTANGLE,0,left,a,right,b);
        ObjectSetInteger(0,name,OBJPROP_BACK,true);
        ObjectSetInteger(0,name,OBJPROP_FILL,filled);
        ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
        ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
        ObjectSetInteger(0,name,OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS);
    }
    RBEPoint(name,0,left,a); RBEPoint(name,1,right,b);
    if((color)ObjectGetInteger(0,name,OBJPROP_COLOR)!=shade) ObjectSetInteger(0,name,OBJPROP_COLOR,shade);
    if((bool)ObjectGetInteger(0,name,OBJPROP_FILL)!=filled) ObjectSetInteger(0,name,OBJPROP_FILL,filled);
}
void RBEVisualTrade(string tag,const RBEViewTrade &t,datetime now,double level)
{
    if(!t.filled) return;
    int sec=PeriodSeconds(); if(sec<=0) sec=60;
    // Entry + three bars; then two complete bars ahead of the live bar.
    datetime minimum=RBEBarStart(t.fillTime)+3*sec-1;
    datetime live=RBEBarStart(now)+3*sec-1;
    datetime right=t.resolved ? t.exitTime : MathMax(minimum,live);
    double stop=t.initialSL;
    double result=t.buy ? t.exitPrice-t.entry : t.entry-t.exitPrice;
    if(t.resolved && result<=0) stop=t.exitPrice;
    RBEBox(tag+"_SL",t.fillTime,right,t.entry,stop,C'55,57,68',false);
    HLine(tag+"_ENTRY",t.entry,C'214,218,224',t.actual ? STYLE_SOLID : STYLE_DASH,1,t.fillTime,right);
    string side=t.buy ? "BUY" : "SELL";
    string origin=t.actual ? "Broker execution" : "Synthetic chart touch (no broker order)";
    string entry=DoubleToString(t.entry,_Digits),limit=DoubleToString(level,_Digits);
    string anchor=TimeToString(t.fillTime,TIME_MINUTES);
    RBETip(tag+"_ENTRY",origin+" | "+side+" entry "+entry+" at "+anchor+
           " | range "+(t.buy ? "high " : "low ")+limit);
    RBETip(tag+"_SL",origin+" | "+side+" initial stop "+DoubleToString(t.initialSL,_Digits)+
           (t.resolved && result<=0 ? " | loss area ends at actual exit "+DoubleToString(t.exitPrice,_Digits)
                                   : " | projected risk area from entry "+entry));
    if(t.resolved && result>0) RBEBox(tag+"_TP",t.fillTime,right,t.entry,t.exitPrice,C'22,55,120',false);
    else ObjectDelete(0,tag+"_TP");
    if(t.resolved && result>0) RBETip(tag+"_TP",origin+" | "+side+" profit area | entry "+entry+
                                       " | exit "+DoubleToString(t.exitPrice,_Digits));
    if(t.trailing) HLine(tag+"_TRAIL",t.stop,C'162,138,88',STYLE_DOT,1,t.trailTime,right);
    if(t.trailing) RBETip(tag+"_TRAIL",origin+" | latest trailing stop "+DoubleToString(t.stop,_Digits));
    string marker=tag+"_FILL";
    if(ObjectFind(0,marker)<0)
    {
        ObjectCreate(0,marker,t.buy ? OBJ_ARROW_BUY : OBJ_ARROW_SELL,0,t.fillTime,t.entry);
        ObjectSetInteger(0,marker,OBJPROP_COLOR,t.actual ? clrWhite : clrSlateGray);
        ObjectSetInteger(0,marker,OBJPROP_SELECTABLE,false);
    }
    RBEPoint(marker,0,t.fillTime,t.entry);
    color markerColor=t.actual ? clrWhite : clrSlateGray;
    if((color)ObjectGetInteger(0,marker,OBJPROP_COLOR)!=markerColor)
    {
        ObjectSetInteger(0,marker,OBJPROP_COLOR,markerColor);
    }
    RBETip(marker,origin+" | "+side+" at "+entry+" on "+anchor+
           " | range "+(t.buy ? "high " : "low ")+limit+
           " | difference "+DoubleToString(t.entry-level,_Digits));
}
void RBERender(datetime now)
{
    if(!CanDraw()) return;
    string keep[3];
    for(int slot=0;slot<3;slot++)
    {
        keep[slot]=PFX+IntegerToString((long)g_view[slot].day)+"_";
        if(g_view[slot].high<=g_view[slot].low) continue;
        datetime right=g_view[slot].locked ? g_view[slot].lock+59 : RBEAnchorBarEnd(now);
        RBEBox(keep[slot]+"BOX",g_view[slot].open,right,g_view[slot].high,g_view[slot].low,Range_Color);
        RBETip(keep[slot]+"BOX","NY range "+TimeToString(ServerToNY(g_view[slot].open),TIME_MINUTES)+
               " to "+TimeToString(ServerToNY(g_view[slot].lock),TIME_MINUTES)+
               " | broker "+TimeToString(g_view[slot].open,TIME_MINUTES)+
               " to "+TimeToString(g_view[slot].lock,TIME_MINUTES)+" | high "+DoubleToString(g_view[slot].high,_Digits)+
               " | low "+DoubleToString(g_view[slot].low,_Digits));
        bool expired=now>=g_view[slot].cutoff;
        if(Max_Buy>0 && (!expired || g_view[slot].buy.filled))
        {
            HLine(keep[slot]+"HI",g_view[slot].high,C'214,218,224',g_view[slot].buy.filled ? STYLE_SOLID : STYLE_DASH,1,
                  RBEBarStart(g_view[slot].highTime),g_view[slot].buy.filled ? (datetime)((long)g_view[slot].buy.fillTime/60*60+59) : RBEBarStart(now)+2*PeriodSeconds()-1);
            RBETip(keep[slot]+"HI","Buy-side range high "+DoubleToString(g_view[slot].high,_Digits)+
                   (g_view[slot].buy.filled ? " | first touch "+TimeToString(g_view[slot].buy.fillTime,TIME_MINUTES)
                                            : " | not touched in replay"));
        }
        else ObjectDelete(0,keep[slot]+"HI");
        if(Max_Sell>0 && (!expired || g_view[slot].sell.filled))
        {
            HLine(keep[slot]+"LO",g_view[slot].low,C'214,218,224',g_view[slot].sell.filled ? STYLE_SOLID : STYLE_DASH,1,
                  RBEBarStart(g_view[slot].lowTime),g_view[slot].sell.filled ? (datetime)((long)g_view[slot].sell.fillTime/60*60+59) : RBEBarStart(now)+2*PeriodSeconds()-1);
            RBETip(keep[slot]+"LO","Sell-side range low "+DoubleToString(g_view[slot].low,_Digits)+
                    (g_view[slot].sell.filled ? " | first touch "+TimeToString(g_view[slot].sell.fillTime,TIME_MINUTES)
                                             : " | not touched in replay"));
        }
        else ObjectDelete(0,keep[slot]+"LO");
        RBEVisualTrade(keep[slot]+"BUY",g_view[slot].buy,now,g_view[slot].high);
        RBEVisualTrade(keep[slot]+"SELL",g_view[slot].sell,now,g_view[slot].low);
    }
    for(int i=ObjectsTotal(0)-1;i>=0;i--)
    {
        string name=ObjectName(0,i);
        if(StringFind(name,PFX)!=0) continue;
        bool retained=false;
        for(int slot=0;slot<3;slot++) if(StringFind(name,keep[slot])==0) retained=true;
        if(!retained) ObjectDelete(0,name);
    }
}

//+------------------------------------------------------------------+
//| Visuals                                                          |
//+------------------------------------------------------------------+
datetime RBEBarStart(datetime t)
{
    int sec = PeriodSeconds();
    if(sec <= 0 || t <= 0) return t;
    return (datetime)(((long)t / sec) * sec);
}

datetime RBEAnchorBarEnd(datetime t)
{
    int sec = PeriodSeconds();
    if(sec <= 1 || t <= 0) return t;
    return RBEBarStart(t) + sec - 1;
}

bool CanDraw()  { return Show_Visuals && !((bool)MQLInfoInteger(MQL_TESTER) && !(bool)MQLInfoInteger(MQL_VISUAL_MODE)); }
bool CanPanel() { return Show_Panel  && !((bool)MQLInfoInteger(MQL_TESTER) && !(bool)MQLInfoInteger(MQL_VISUAL_MODE)); }



void HLine(string name,double price,color clr,ENUM_LINE_STYLE sty,int w,datetime t0,datetime t1)
{
    if(!CanDraw() || t1<t0) return;
    if(ObjectFind(0,name)<0)
    {
        ObjectCreate(0,name,OBJ_TREND,0,t0,price,t1,price);
        ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false); ObjectSetInteger(0,name,OBJPROP_RAY_LEFT,false);
        ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false); ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
        ObjectSetInteger(0,name,OBJPROP_BACK,true); ObjectSetInteger(0,name,OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS);
    }
    RBEPoint(name,0,t0,price); RBEPoint(name,1,t1,price);
    if((color)ObjectGetInteger(0,name,OBJPROP_COLOR)!=clr) ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
    if((ENUM_LINE_STYLE)ObjectGetInteger(0,name,OBJPROP_STYLE)!=sty) ObjectSetInteger(0,name,OBJPROP_STYLE,sty);
    if(ObjectGetInteger(0,name,OBJPROP_WIDTH)!=w) ObjectSetInteger(0,name,OBJPROP_WIDTH,w);
}

void PxText(string name, double price, datetime t, string text)
{
    if(!CanDraw()) return;
    if(ObjectFind(0, name) < 0)
    {
        ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
        ObjectSetString(0,  name, OBJPROP_FONT,       "Segoe UI Semibold");
        ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   7);
        ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
    }
    ObjectSetInteger(0, name, OBJPROP_TIME,  0, (long)t);
    ObjectSetDouble(0,  name, OBJPROP_PRICE, 0, price);
    ObjectSetString(0,  name, OBJPROP_TEXT,  text);
    ObjectSetInteger(0, name, OBJPROP_COLOR, (long)C'190,210,236');
}

//+------------------------------------------------------------------+
//| Panel — opaque black bg, blocks candles, Rene-style rows         |
//+------------------------------------------------------------------+
void Rect(string name, int x, int y, int w, int h, color bg, color bdr)
{
    if(ObjectFind(0, name) < 0)
    {
        ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
        ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
        ObjectSetInteger(0, name, OBJPROP_BACK,       false);  // foreground — blocks chart
    }
    ObjectSetInteger(0, name, OBJPROP_ZORDER,     10000);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE,   x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE,   y);
    ObjectSetInteger(0, name, OBJPROP_XSIZE,       w);
    ObjectSetInteger(0, name, OBJPROP_YSIZE,       h);
    ObjectSetInteger(0, name, OBJPROP_BGCOLOR,     (long)bg);
    ObjectSetInteger(0, name, OBJPROP_COLOR,       (long)bdr);
    ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
}

void Lbl(string name, int x, int y, string text, int fs, color clr)
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
    ObjectSetInteger(0, name, OBJPROP_ZORDER,     10001);
    if((int)ObjectGetInteger(0, name, OBJPROP_XDISTANCE) != x) ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
    if((int)ObjectGetInteger(0, name, OBJPROP_YDISTANCE) != y) ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    if((int)ObjectGetInteger(0, name, OBJPROP_FONTSIZE)  != fs) ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fs);
    if(ObjectGetInteger(0, name, OBJPROP_COLOR) != (long)clr) ObjectSetInteger(0, name, OBJPROP_COLOR, (long)clr);
    if(ObjectGetString(0, name, OBJPROP_TEXT) != text) ObjectSetString(0, name, OBJPROP_TEXT, text);
}

void DrawPanel()
{
    if(!CanPanel()) return;
    int height=g_panelCollapsed ? HH : PH;
    Rect(PPFX+"SHD2", PX+5, PY+5, PW, height, C'6,6,6',    C'6,6,6');
    Rect(PPFX+"SHD1", PX+2, PY+2, PW, height, C'12,12,12', C'12,12,12');
    Rect(PPFX+"BG",   PX,   PY,   PW, height, clrBlack,    C'52,68,92');
    Rect(PPFX+"HDR",  PX,   PY,   PW, HH, C'18,22,28', C'52,68,92');
    Rect(PPFX+"HAIR", PX,   PY+HH, PW, 1, C'52,68,92', C'52,68,92');
    Lbl(PPFX+"TTL",   PX+8, PY+8, "Range Breakout EA", 9, C'190,210,236');
    string button=PPFX+"BTN";
    if(ObjectFind(0,button)<0)
    {
        ObjectCreate(0,button,OBJ_BUTTON,0,0,0);
        ObjectSetInteger(0,button,OBJPROP_CORNER,CORNER_LEFT_UPPER);
        ObjectSetInteger(0,button,OBJPROP_HIDDEN,true);
        ObjectSetString(0,button,OBJPROP_FONT,"Segoe UI Semibold");
    }
    ObjectSetInteger(0,button,OBJPROP_XDISTANCE,PX+PW-29);
    ObjectSetInteger(0,button,OBJPROP_ZORDER,10002);
    ObjectSetInteger(0,button,OBJPROP_YDISTANCE,PY+5);
    ObjectSetInteger(0,button,OBJPROP_XSIZE,22);
    ObjectSetInteger(0,button,OBJPROP_YSIZE,22);
    ObjectSetInteger(0,button,OBJPROP_FONTSIZE,12);
    ObjectSetInteger(0,button,OBJPROP_COLOR,(long)C'190,210,236');
    ObjectSetInteger(0,button,OBJPROP_BGCOLOR,(long)C'18,22,28');
    ObjectSetInteger(0,button,OBJPROP_BORDER_COLOR,(long)C'52,68,92');
    ObjectSetInteger(0,button,OBJPROP_STATE,false);
    ObjectSetString(0,button,OBJPROP_TEXT,g_panelCollapsed ? "+" : "-");
    if(g_panelCollapsed)
    {
        string rows[]={"SRV","HI","LO","SZ","BUY","SEL","CST","COV","SL"};
        for(int i=0;i<ArraySize(rows);i++) ObjectDelete(0,PPFX+rows[i]);
    }
}

void RBERestackPanel(datetime now)
{
    if(!g_panelRestack || !CanPanel()) return;
    g_panelRestack=false;
    ObjectsDeleteAll(0,PPFX);
    DrawPanel();
    if(!g_panelCollapsed) UpdatePanel(now);
    ChartRedraw(0);
}

string RBENYClock(datetime serverNow)
{
    if((bool)MQLInfoInteger(MQL_TESTER) && TesterWeekAnchorOffsetSec()==-999999)
        return "Waiting for NY clock history";
    return TimeToString(ServerToNY(serverNow),TIME_SECONDS);
}



void UpdatePanel(datetime now)
{
    if(!CanPanel()) return;
    if(ObjectFind(0, PPFX+"BG") < 0) DrawPanel();
    if(g_panelCollapsed) return;

    double sz   = (g_rngHi > 0 && g_rngLo > 0) ? g_rngHi - g_rngLo : 0;
    double pct  = (g_rngHi > 0 && sz > 0) ? sz / g_rngHi * 100.0 : 0;
    string hi   = g_rngHi > 0 ? DoubleToString(g_rngHi, _Digits) : "--";
    string lo   = g_rngLo > 0 ? DoubleToString(g_rngLo, _Digits) : "--";
    string szs  = sz > 0 ? StringFormat("%.2f (%.2f%%)", sz, pct) : "--";
    double slD  = (g_rngHi > 0 && Stop_Value > 0) ? g_rngHi * Stop_Value / 100.0 : 0;
    string sls  = slD > 0 ? StringFormat("SL for -%.0f, -%.2f%%", slD / _Point, Stop_Value) : "--";
    string srv  = TimeToString(now, TIME_SECONDS);
    string nyClock = RBENYClock(now);

    double costPerLot = RBECostCashPerLot();
    string costS = StringFormat("Cost/lot: $%.2f %s", costPerLot, RBECommissionObserved() ? "(obs)" : "(est)");

    int x = PX + 8;
    Lbl(PPFX+"SRV",  x, PY+40,  "NY Time: " + nyClock + " [" + TimeToString(now, TIME_MINUTES|TIME_SECONDS) + "]", 8, C'140,158,185');
    Lbl(PPFX+"HI",   x, PY+59,  "Range High: "   + hi,                       8, C'120,210,150');
    Lbl(PPFX+"LO",   x, PY+76,  "Range Low: "    + lo,                       8, C'210,100,100');
    Lbl(PPFX+"SZ",   x, PY+93,  "Range Size: "   + szs,                      8, C'140,158,185');
    Lbl(PPFX+"BUY",  x,      PY+112, "Buy Trades: "  + IntegerToString(g_dayBuy),  8, C'120,210,150');
    Lbl(PPFX+"SEL",  x+104,  PY+112, "Sell Trades: " + IntegerToString(g_daySell), 8, C'210,100,100');
    Lbl(PPFX+"CST",  x,      PY+132, costS,                                        8, C'140,200,240');
    Lbl(PPFX+"COV",  x,      PY+149, Use_Cost_Covered_Stops ? "BE/Trail: cost-covered" : "BE/Trail: entry", 8, C'190,180,120');
    Lbl(PPFX+"SL",   x,      PY+166, sls,                                         8, C'200,70,70');

    static string sig = "";
    string ns = srv + hi + lo + IntegerToString(g_dayBuy + g_daySell) + DoubleToString(costPerLot, 2);
    if(ns != sig) { sig = ns; ChartRedraw(0); }
}


#endif // RBE_CHART_VISUALS
