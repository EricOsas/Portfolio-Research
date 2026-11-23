#ifndef OS_STRATEGY_VISUALS
#define OS_STRATEGY_VISUALS
long osVisualChart=0;
int osPane=INVALID_HANDLE;
string osPaneName="";
double osLastEntry=0,osLastStop=0,osLastTarget=0;
datetime osLastBracketTime=0;
void OSRememberBracket(double entry,double stop,double target){osLastEntry=entry;osLastStop=stop;osLastTarget=target;osLastBracketTime=ownedEntryTime>0 ? ownedEntryTime : TimeCurrent();}
void OSVisualFit(datetime reference=0)
{
   double low=DBL_MAX,high=-DBL_MAX;
   MqlRates b[];
   int n=reference>0 ? CopyRates(_Symbol,sourceTF,reference,96,b) : CopyRates(_Symbol,sourceTF,0,96,b);
   for(int i=0;i<n;i++){low=MathMin(low,b[i].low);high=MathMax(high,b[i].high);}
   double levels[]={midnight,vwap,orHigh,orLow,overnightHigh,overnightLow,osLastEntry,osLastStop,osLastTarget,
                    virtualActive ? virtualStop : 0,virtualActive ? virtualTarget : 0,
                    0};
   for(int i=0;i<ArraySize(levels);i++) if(levels[i]>0){low=MathMin(low,levels[i]);high=MathMax(high,levels[i]);}
   if(high<=low || low==DBL_MAX) return;
   double pad=(high-low)*.08;
   ChartSetInteger(osVisualChart,CHART_SCALEFIX,true);
   ChartSetDouble(osVisualChart,CHART_FIXED_MIN,low-pad);ChartSetDouble(osVisualChart,CHART_FIXED_MAX,high+pad);
   ChartSetInteger(osVisualChart,CHART_SCALE,3);ChartNavigate(osVisualChart,CHART_END,reference>0 ? -iBarShift(_Symbol,sourceTF,reference,false) : 0);
   ChartRedraw(osVisualChart);
}
string OSVisualPrefix(){return "OS_"+IntegerToString((long)Magic)+"_";}
datetime OSVisualDay(datetime now){return OSDay(now);}
bool OSVisualEnabled(){return ShowVisuals && (!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE));}
bool osVisualSuspended=false;
string OSVisualFault()
{
   bool tester=MQLInfoInteger(MQL_TESTER);
   if(!tester && !TerminalInfoInteger(TERMINAL_CONNECTED))return "Disconnected | waiting for server";
   if(!tester && !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))return "Terminal trading disabled";
   if(!tester && !MQLInfoInteger(MQL_TRADE_ALLOWED))return "EA trading permission disabled";
   if(!tester && !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))return "Server account trading disabled";
   if(!tester && !OSRuntimeAccountContextValid())return "Account context changed | trading blocked";
   if(runtimeCloseRejected)return "Close rejected | retry paused";
   if(runtimeCloseAttention)return "Close unconfirmed | recovery pending";
   if(runtimeRecoveryHold)return "Recovery needs attention | broker SL/TP retained";
   if(runtimeBlocked)return "Recovery / server order error | trading blocked";
   if(!clockReady)return "Clock history loading";
   if(!SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_SYNCHRONIZED) || iTime(_Symbol,PERIOD_M1,1)<=0)
      return "M1 history unavailable";
   if(!tester && !runtimeHistoryReady)return "History / indicators loading";
   if(dayWaiting && dataWaitReason!="")return "Data unavailable | "+dataWaitReason;
   return "";
}
bool OSVisualDataEnabled(){return OSVisualEnabled() && OSVisualFault()=="";}
void OSVisualSuspend(bool blocked)
{
   if(blocked==osVisualSuspended)return;
   osVisualSuspended=blocked;
   // Preserve chart history for restoration; touch only this EA's own namespace.
   string prefix=OSVisualPrefix(),panel=OSPanelPrefix();
   for(int index=ObjectsTotal(osVisualChart,-1,-1)-1;index>=0;index--)
   {
      string name=ObjectName(osVisualChart,index,-1,-1);
      if(StringFind(name,prefix)!=0 || StringFind(name,panel)==0)continue;
      ObjectSetInteger(osVisualChart,name,OBJPROP_TIMEFRAMES,blocked ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS);
   }
   if(osPaneName!="")
   {
      if(blocked)
      {
         for(int window=(int)ChartGetInteger(osVisualChart,CHART_WINDOWS_TOTAL)-1;window>=1;window--)
            ChartIndicatorDelete(osVisualChart,window,osPaneName);
      }
      else if(osPane!=INVALID_HANDLE)
         ChartIndicatorAdd(osVisualChart,(int)ChartGetInteger(osVisualChart,CHART_WINDOWS_TOTAL),osPane);
   }
   ChartRedraw(osVisualChart);
}
void OSInitVisual()
{
   if(!OSVisualEnabled()) return;
   string oldRows[]={"Title","Clock","Metrics","State"};
   for(int i=0;i<ArraySize(oldRows);i++)ObjectDelete(osVisualChart,OSVisualPrefix()+oldRows[i]);
   ChartSetInteger(osVisualChart,CHART_EVENT_OBJECT_CREATE,true);

   // Rebuild the curve at the new view's resolution; retain the other owned levels.
   ObjectsDeleteAll(osVisualChart,OSVisualPrefix()+"VWAP_");
   // Remove only objects owned by this EA under its former object namespace.
   ObjectsDeleteAll(osVisualChart,"GT_"+IntegerToString((long)Magic)+"_");
   // Repair retained owned drawings from builds that used the foreground layer.
   for(int i=ObjectsTotal(osVisualChart,-1,-1)-1;i>=0;i--)
   {
      string name=ObjectName(osVisualChart,i,-1,-1);
      if(StringFind(name,OSVisualPrefix())==0 && StringFind(name,OSPanelPrefix())!=0)
      {
         ObjectSetInteger(osVisualChart,name,OBJPROP_BACK,true);
         if(ObjectGetInteger(osVisualChart,name,OBJPROP_TYPE)==OBJ_RECTANGLE)
         {ObjectSetInteger(osVisualChart,name,OBJPROP_FILL,false);ObjectSetInteger(osVisualChart,name,OBJPROP_WIDTH,1);}
      }
   }
   ChartSetInteger(osVisualChart,CHART_MODE,CHART_CANDLES);
   ChartSetInteger(osVisualChart,CHART_COLOR_BACKGROUND,clrBlack);
   ChartSetInteger(osVisualChart,CHART_COLOR_FOREGROUND,clrSilver);
   ChartSetInteger(osVisualChart,CHART_COLOR_CANDLE_BULL,clrWhite);
   ChartSetInteger(osVisualChart,CHART_COLOR_CANDLE_BEAR,clrDarkOrange);
   ChartSetInteger(osVisualChart,CHART_COLOR_CHART_UP,clrWhite);
   ChartSetInteger(osVisualChart,CHART_COLOR_CHART_DOWN,clrDarkOrange);
   ChartSetInteger(osVisualChart,CHART_SHOW_GRID,false);
   ChartSetInteger(osVisualChart,CHART_AUTOSCROLL,true);ChartSetInteger(osVisualChart,CHART_SHIFT,true);
}

const int PX=10,PY=20,PW=210,PH=198,HH=32;
bool vbPanelCollapsed=false,vbPanelRestack=false;
string OSPanelPrefix(){return OSVisualPrefix()+"PANEL_";}
void OSPanelRect(string name, int x, int y, int w, int h, color bg, color bdr)
{
    if(ObjectFind(osVisualChart, name) < 0)
    {
        ObjectCreate(osVisualChart, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
        ObjectSetInteger(osVisualChart, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
        ObjectSetInteger(osVisualChart, name, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(osVisualChart, name, OBJPROP_HIDDEN,     true);
        ObjectSetInteger(osVisualChart, name, OBJPROP_BACK,       false);  // foreground â€” blocks chart
    }
    ObjectSetInteger(osVisualChart, name, OBJPROP_ZORDER,     10000);
    ObjectSetInteger(osVisualChart, name, OBJPROP_BACK,       false);
    ObjectSetInteger(osVisualChart, name, OBJPROP_XDISTANCE,   x);
    ObjectSetInteger(osVisualChart, name, OBJPROP_YDISTANCE,   y);
    ObjectSetInteger(osVisualChart, name, OBJPROP_XSIZE,       w);
    ObjectSetInteger(osVisualChart, name, OBJPROP_YSIZE,       h);
    ObjectSetInteger(osVisualChart, name, OBJPROP_BGCOLOR,     (long)bg);
    ObjectSetInteger(osVisualChart, name, OBJPROP_COLOR,       (long)bdr);
    ObjectSetInteger(osVisualChart, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
}

void OSPanelLbl(string name, int x, int y, string text, int fs, color clr)
{
    if(ObjectFind(osVisualChart, name) < 0)
    {
        ObjectCreate(osVisualChart, name, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(osVisualChart, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
        ObjectSetInteger(osVisualChart, name, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(osVisualChart, name, OBJPROP_HIDDEN,     true);
        ObjectSetInteger(osVisualChart, name, OBJPROP_BACK,       false);
        ObjectSetString(osVisualChart,  name, OBJPROP_FONT,       "Segoe UI Semibold");
    }
    ObjectSetInteger(osVisualChart, name, OBJPROP_ZORDER,     10001);
    if((int)ObjectGetInteger(osVisualChart, name, OBJPROP_XDISTANCE) != x) ObjectSetInteger(osVisualChart, name, OBJPROP_XDISTANCE, x);
    if((int)ObjectGetInteger(osVisualChart, name, OBJPROP_YDISTANCE) != y) ObjectSetInteger(osVisualChart, name, OBJPROP_YDISTANCE, y);
    if((int)ObjectGetInteger(osVisualChart, name, OBJPROP_FONTSIZE)  != fs) ObjectSetInteger(osVisualChart, name, OBJPROP_FONTSIZE, fs);
    if(ObjectGetInteger(osVisualChart, name, OBJPROP_COLOR) != (long)clr) ObjectSetInteger(osVisualChart, name, OBJPROP_COLOR, (long)clr);
    if(ObjectGetString(osVisualChart, name, OBJPROP_TEXT) != text) ObjectSetString(osVisualChart, name, OBJPROP_TEXT, text);
}

void OSPanelShell()
{
    if(!OSVisualEnabled()) return;
    int height=vbPanelCollapsed ? HH : PH;
    OSPanelRect(OSPanelPrefix()+"SHD2", PX+5, PY+5, PW, height, C'6,6,6',    C'6,6,6');
    OSPanelRect(OSPanelPrefix()+"SHD1", PX+2, PY+2, PW, height, C'12,12,12', C'12,12,12');
    OSPanelRect(OSPanelPrefix()+"BG",   PX,   PY,   PW, height, clrBlack,    C'52,68,92');
    OSPanelRect(OSPanelPrefix()+"HDR",  PX,   PY,   PW, HH, C'18,22,28', C'52,68,92');
    OSPanelRect(OSPanelPrefix()+"HAIR", PX,   PY+HH, PW, 1, C'52,68,92', C'52,68,92');
    OSPanelLbl(OSPanelPrefix()+"TTL",   PX+8, PY+8, OSDisplayName, 9, C'190,210,236');
    string button=OSPanelPrefix()+"BTN";
    if(ObjectFind(osVisualChart,button)<0)
    {
        ObjectCreate(osVisualChart,button,OBJ_BUTTON,0,0,0);
        ObjectSetInteger(osVisualChart,button,OBJPROP_CORNER,CORNER_LEFT_UPPER);
        ObjectSetInteger(osVisualChart,button,OBJPROP_HIDDEN,true);
        ObjectSetString(osVisualChart,button,OBJPROP_FONT,"Segoe UI Semibold");
    }
    ObjectSetInteger(osVisualChart,button,OBJPROP_XDISTANCE,PX+PW-29);
    ObjectSetInteger(osVisualChart,button,OBJPROP_ZORDER,10002);
    ObjectSetInteger(osVisualChart,button,OBJPROP_YDISTANCE,PY+5);
    ObjectSetInteger(osVisualChart,button,OBJPROP_XSIZE,22);
    ObjectSetInteger(osVisualChart,button,OBJPROP_YSIZE,22);
    ObjectSetInteger(osVisualChart,button,OBJPROP_FONTSIZE,12);
    ObjectSetInteger(osVisualChart,button,OBJPROP_COLOR,(long)C'190,210,236');
    ObjectSetInteger(osVisualChart,button,OBJPROP_BGCOLOR,(long)C'18,22,28');
    ObjectSetInteger(osVisualChart,button,OBJPROP_BORDER_COLOR,(long)C'52,68,92');
    ObjectSetInteger(osVisualChart,button,OBJPROP_STATE,false);
    ObjectSetString(osVisualChart,button,OBJPROP_TEXT,vbPanelCollapsed ? "+" : "-");
    if(vbPanelCollapsed)
    {
        string rows[]={"SRV","HI","LO","SZ","BUY","SEL","CST","COV","SL"};
        for(int i=0;i<ArraySize(rows);i++) ObjectDelete(osVisualChart,OSPanelPrefix()+rows[i]);
    }
}

void OSPanelRows(datetime clock,string state,double adx,double nub)
{
   if(vbPanelRestack){vbPanelRestack=false;ObjectsDeleteAll(osVisualChart,OSPanelPrefix());}
   OSPanelShell();
   if(vbPanelCollapsed)return;
   string p=OSPanelPrefix();
   OSPanelLbl(p+"SRV",PX+8,PY+40,clockReady ? "NY: "+TimeToString(OSNewYork(clock),TIME_SECONDS)+" CT: "+TimeToString(OSCentral(clock),TIME_SECONDS) : "Clock history loading",8,C'140,158,185');
   OSPanelLbl(p+"HI",PX+8,PY+59,"NUB: "+(nub>0?DoubleToString(nub,3):"--"),8,C'120,210,150');
   OSPanelLbl(p+"LO",PX+8,PY+76,"SOP: "+(midnight>0?DoubleToString(midnight,2):"--"),8,C'210,100,100');
   OSPanelLbl(p+"SZ",PX+8,PY+93,"VWAP: "+(vwap>0?DoubleToString(vwap,2):"--"),8,C'140,158,185');
   OSPanelLbl(p+"BUY",PX+8,PY+112,"Trades "+IntegerToString(entries)+"/3",8,C'120,210,150');
   OSPanelLbl(p+"SEL",PX+112,PY+112,OwnPosition()?"Position: long":"Position: flat",8,C'210,100,100');
   OSPanelLbl(p+"CST",PX+8,PY+132,StringFormat("Comm/lot: $%.2f | Slip: %dp",OSCommissionEstimate(),SlippagePoints),8,C'140,200,240');
   OSPanelLbl(p+"COV",PX+8,PY+149,"Fixed SL / TP: 60 / 40",8,C'190,180,120');
   string display=OSSizingLabel()+" | "+state;
   OSPanelLbl(p+"SL",PX+8,PY+166,StringSubstr(display,0,31),8,C'200,70,70');
   ObjectSetString(osVisualChart,p+"SL",OBJPROP_TOOLTIP,display);
}
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(!OSVisualEnabled())return;
   if(id==CHARTEVENT_OBJECT_CREATE && StringFind(sparam,OSPanelPrefix())!=0)
   {vbPanelRestack=true;return;}
   if(id==CHARTEVENT_OBJECT_CLICK && sparam==OSPanelPrefix()+"BTN")
   {vbPanelCollapsed=!vbPanelCollapsed;OSDraw();ChartRedraw(osVisualChart);}
}


datetime OSHistoryFloor=0,OSHistoryRendered=0;
bool vbBrokerVisualDirty=true;
bool vbBrokerVisualInitialized=false;
datetime vbVirtualExitTime=0;
struct OSBrokerView
{
   ulong id;int side;datetime entered,exited;double entryValue,volume,exitValue,exitVolume,stop;bool mixed;
};
OSBrokerView vbBrokerView[];
void OSTradeBox(string key,datetime left,datetime right,double entry,double edge,color ink)
{
   if(!OSVisualDataEnabled())return;
   string id=OSVisualPrefix()+key;
   if(right<=left)right=left+1;
   if(ObjectFind(osVisualChart,id)<0)ObjectCreate(osVisualChart,id,OBJ_RECTANGLE,0,left,entry,right,edge);
   ObjectMove(osVisualChart,id,0,left,entry);ObjectMove(osVisualChart,id,1,right,edge);
   ObjectSetInteger(osVisualChart,id,OBJPROP_COLOR,ink);
   ObjectSetInteger(osVisualChart,id,OBJPROP_FILL,false);
   ObjectSetInteger(osVisualChart,id,OBJPROP_WIDTH,1);
   ObjectSetInteger(osVisualChart,id,OBJPROP_BACK,true);
   ObjectSetInteger(osVisualChart,id,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(osVisualChart,id,OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS);
   ObjectSetString(osVisualChart,id,OBJPROP_TOOLTIP,OSDisplayName+" | Broker execution | "+key);
}
void OSPaintBrokerTrades(datetime now)
{
   bool rebuild=vbBrokerVisualDirty;
   if(rebuild)
   {
      int bars=Bars(_Symbol,_Period);
      datetime begin=!vbBrokerVisualInitialized && bars>0?iTime(_Symbol,_Period,bars-1):now-45*86400;
      begin=now-90*86400; // Include owned openings preceding the visible history window.
      if(!HistorySelect(begin,now))return;
      vbBrokerVisualInitialized=true;
      ArrayResize(vbBrokerView,0);
      // Retire average-price arrows from earlier builds; exact deal tickets replace them.
      ObjectsDeleteAll(osVisualChart,OSVisualPrefix()+"Entry_");
      ObjectsDeleteAll(osVisualChart,OSVisualPrefix()+"Exit_");
      for(int i=0;i<HistoryDealsTotal();i++)
      {
         ulong d=HistoryDealGetTicket(i);
         if(HistoryDealGetString(d,DEAL_SYMBOL)!=_Symbol)continue;
         long kind=HistoryDealGetInteger(d,DEAL_ENTRY);
         ulong id=(ulong)HistoryDealGetInteger(d,DEAL_POSITION_ID);int k=-1;
         for(int j=0;j<ArraySize(vbBrokerView);j++)if(vbBrokerView[j].id==id){k=j;break;}
         if(kind==DEAL_ENTRY_IN)
         {
            if((ulong)HistoryDealGetInteger(d,DEAL_MAGIC)!=Magic)continue;
            if(k<0){k=ArraySize(vbBrokerView);ArrayResize(vbBrokerView,k+1);ZeroMemory(vbBrokerView[k]);vbBrokerView[k].id=id;vbBrokerView[k].entered=(datetime)HistoryDealGetInteger(d,DEAL_TIME);}
            double qty=HistoryDealGetDouble(d,DEAL_VOLUME);
            vbBrokerView[k].side=HistoryDealGetInteger(d,DEAL_TYPE)==DEAL_TYPE_BUY?1:-1;
            vbBrokerView[k].entryValue+=qty*HistoryDealGetDouble(d,DEAL_PRICE);vbBrokerView[k].volume+=qty;
            ulong order=(ulong)HistoryDealGetInteger(d,DEAL_ORDER);
            double sl=HistoryOrderGetDouble(order,ORDER_SL);if(sl>0)vbBrokerView[k].stop=sl;
         }
         else if(k>=0 && (kind==DEAL_ENTRY_OUT || kind==DEAL_ENTRY_OUT_BY))
         {
            double qty=HistoryDealGetDouble(d,DEAL_VOLUME);
            vbBrokerView[k].exitValue+=qty*HistoryDealGetDouble(d,DEAL_PRICE);vbBrokerView[k].exitVolume+=qty;
            vbBrokerView[k].exited=(datetime)HistoryDealGetInteger(d,DEAL_TIME);
         }
      }
      // Shared/netting positions with mixed opening ownership or reversals are not attributed.
      for(int i=0;i<HistoryDealsTotal();i++){
         ulong deal=HistoryDealGetTicket(i);long kind=HistoryDealGetInteger(deal,DEAL_ENTRY);
         if(kind!=DEAL_ENTRY_IN && kind!=DEAL_ENTRY_INOUT)continue;
         ulong id=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
         for(int k=0;k<ArraySize(vbBrokerView);k++)if(vbBrokerView[k].id==id
            && (kind==DEAL_ENTRY_INOUT || (ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=Magic))vbBrokerView[k].mixed=true;
      }
      // Exact deal prices/timestamps, including partial fills and manual exits of owned positions.
      for(int i=0;i<HistoryDealsTotal();i++)
      {
         ulong deal=HistoryDealGetTicket(i);
         if(HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol)continue;
         ulong position=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
         bool owned=false;
         for(int k=0;k<ArraySize(vbBrokerView);k++)if(vbBrokerView[k].id==position && !vbBrokerView[k].mixed){owned=true;break;}
         datetime at=(datetime)HistoryDealGetInteger(deal,DEAL_TIME);
         long type=HistoryDealGetInteger(deal,DEAL_TYPE);
         if(!owned || at<OSHistoryFloor || (type!=DEAL_TYPE_BUY && type!=DEAL_TYPE_SELL))continue;
         OSDrawFill(type==DEAL_TYPE_BUY?1:-1,at,HistoryDealGetDouble(deal,DEAL_PRICE),"Deal "+IntegerToString((long)deal));
      }
      vbBrokerVisualDirty=false;
   }
   for(int i=0;i<ArraySize(vbBrokerView);i++)
   {
      if(vbBrokerView[i].volume<=0 || vbBrokerView[i].mixed)continue;
      double entry=vbBrokerView[i].entryValue/vbBrokerView[i].volume;
      bool closed=vbBrokerView[i].exitVolume>=vbBrokerView[i].volume-1e-8;
      if(closed && (!rebuild || vbBrokerView[i].exited<OSHistoryFloor))continue;
      datetime right=closed?vbBrokerView[i].exited:(datetime)MathMax((double)now,(double)(vbBrokerView[i].entered+3*PeriodSeconds(_Period)));
      double exit=closed?vbBrokerView[i].exitValue/vbBrokerView[i].exitVolume:0;
      double stop=vbBrokerView[i].stop>0?vbBrokerView[i].stop:0;
      // Keep original order SL as risk geometry; an exit fill is not the initial stop.
      string tag="Broker "+IntegerToString((long)vbBrokerView[i].id);
      if(stop>0)OSTradeBox(tag+" risk",vbBrokerView[i].entered,right,entry,stop,C'55,57,68');
      OSLine(tag+" entry",entry,C'214,218,224',STYLE_SOLID,vbBrokerView[i].entered,right);
      if(closed && vbBrokerView[i].side*(exit-entry)>0)OSTradeBox(tag+" profit",vbBrokerView[i].entered,right,entry,exit,C'22,55,120');
      // Per-deal arrows above are authoritative; averages only define the position box.
   }
}

void OSDrawFill(int side,datetime time,double price,string label)
{
   if(!OSVisualDataEnabled()) return;
   string id=OSVisualPrefix()+label+"_"+IntegerToString((long)time);
   ObjectCreate(osVisualChart,id,side==1 ? OBJ_ARROW_BUY : OBJ_ARROW_SELL,0,time,price);
   ObjectSetString(osVisualChart,id,OBJPROP_TOOLTIP,OSDisplayName+" | "+label+" "+TimeToString(time,TIME_DATE|TIME_SECONDS));
   ObjectSetInteger(osVisualChart,id,OBJPROP_COLOR,clrWhite);
   ObjectSetInteger(osVisualChart,id,OBJPROP_BACK,true);
   ObjectSetInteger(osVisualChart,id,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(osVisualChart,id,OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS);
}
void OSLine(string key,double price,color ink,ENUM_LINE_STYLE style=STYLE_SOLID,datetime left=0,datetime right=0)
{
   if(!OSVisualDataEnabled())return;
   string id=OSVisualPrefix()+key;
   if(left==0)
   {
      left=OSSessionTime(day);
      if(StringFind(key,"Opening range")==0) left+=510*60;
      else if(StringFind(key,"Overnight")==0 || StringFind(key,"Bias")==0)
         left-=(OvernightStart==23 ? 3600 : 0);
      else if(StringFind(key,"Synthetic")==0) left=virtualStart;
      else if(key=="Entry" || key=="Stop" || key=="Target")
         left=ownedEntryTime>0 ? ownedEntryTime : (datetime)PositionGetInteger(POSITION_TIME);
      else if(StringFind(key,"Last ")==0) left=osLastBracketTime;
   }
   if(right==0) right=OSSessionTime(day)+OSSessionCutoff(OSSessionTime(day),(int)Model)*60;
   if(left<=0 || right<=left || price<=0) {ObjectDelete(osVisualChart,id);return;}
   if(ObjectFind(osVisualChart,id)>=0 && ObjectGetInteger(osVisualChart,id,OBJPROP_TYPE)!=OBJ_TREND)
      ObjectDelete(osVisualChart,id);
   if(ObjectFind(osVisualChart,id)<0) ObjectCreate(osVisualChart,id,OBJ_TREND,0,left,price,right,price);
   ObjectMove(osVisualChart,id,0,left,price);ObjectMove(osVisualChart,id,1,right,price);
   ObjectSetInteger(osVisualChart,id,OBJPROP_RAY_LEFT,false);ObjectSetInteger(osVisualChart,id,OBJPROP_RAY_RIGHT,false);
   ObjectSetInteger(osVisualChart,id,OBJPROP_COLOR,ink);ObjectSetInteger(osVisualChart,id,OBJPROP_STYLE,style);
   ObjectSetInteger(osVisualChart,id,OBJPROP_BACK,true);
   ObjectSetInteger(osVisualChart,id,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(osVisualChart,id,OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS);
   ObjectSetString(osVisualChart,id,OBJPROP_TEXT,key);
   ObjectSetString(osVisualChart,id,OBJPROP_TOOLTIP,OSDisplayName+" | "+key+" | "+DoubleToString(price,_Digits)
      +" | "+TimeToString(left,TIME_DATE|TIME_MINUTES)+" to "+TimeToString(right,TIME_MINUTES)+" (broker time)");
}

void OSHistoryLine(string key,datetime left,double a,datetime right,double b,color ink)
{
   if(!OSVisualDataEnabled() || right<=left || a<=0 || b<=0)return;
   string id=OSVisualPrefix()+"HISTORY_"+key;
   if(ObjectFind(osVisualChart,id)<0)ObjectCreate(osVisualChart,id,OBJ_TREND,0,left,a,right,b);
   ObjectMove(osVisualChart,id,0,left,a);ObjectMove(osVisualChart,id,1,right,b);
   ObjectSetInteger(osVisualChart,id,OBJPROP_COLOR,ink);ObjectSetInteger(osVisualChart,id,OBJPROP_WIDTH,1);
   ObjectSetInteger(osVisualChart,id,OBJPROP_STYLE,STYLE_DOT);ObjectSetInteger(osVisualChart,id,OBJPROP_BACK,true);
   ObjectSetInteger(osVisualChart,id,OBJPROP_SELECTABLE,false);ObjectSetInteger(osVisualChart,id,OBJPROP_RAY_LEFT,false);
   ObjectSetInteger(osVisualChart,id,OBJPROP_RAY_RIGHT,false);ObjectSetInteger(osVisualChart,id,OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS);
   ObjectSetString(osVisualChart,id,OBJPROP_TOOLTIP,"Source-bar session history | "+key);
}
void OSHistoricalSessions(datetime now)
{
   if(!OSVisualDataEnabled() || MQLInfoInteger(MQL_TESTER))return;
   datetime today=OSVisualDay(now);static datetime retry=0;
   if(OSHistoryRendered==today || now<retry)return;
   retry=now+60;
   MqlRates b[];ArraySetAsSeries(b,false);
   int count=CopyRates(_Symbol,PERIOD_M1,now-14*86400,now-60,b);
   if(count<=0 || !SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_SYNCHRONIZED))return;
   datetime dates[3];int found=0;datetime last=0;
   for(int i=count-1;i>=0 && found<3;i--){
      datetime key=OSVisualDay(b[i].time);
      datetime ny=OSNewYork(OSSessionTime(key));MqlDateTime d;TimeToStruct(ny,d);
      if(d.day_of_week==0 || d.day_of_week==6)continue;
      if(key==last)continue;last=key;dates[found++]=key;
   }
   if(found==0)return;
   bool complete=found==3;
   OSHistoryFloor=OSSessionTime(dates[found-1]);
   ObjectsDeleteAll(osVisualChart,OSVisualPrefix()+"HISTORY_");
   for(int n=found-1;n>=0;n--){
      datetime sd=dates[n],anchor=OSSessionTime(sd);
      if(sd==today)continue;
      datetime right=anchor+OSSessionCutoff(anchor,(int)Model)*60;
      string tag=IntegerToString((long)sd)+"_";
      double pv=0,vol=0,prior=0,hi=-DBL_MAX,lo=DBL_MAX,op=0,nh=-DBL_MAX,nl=DBL_MAX;
      datetime priorTime=0,segment=0,segmentLeft=0;double segmentValue=0;int opened=0;
      int seconds=MathMax(60,PeriodSeconds((ENUM_TIMEFRAMES)ChartPeriod(osVisualChart)));
      int start=0,openingLength=30;
      for(int i=0;i<count;i++){
         datetime t=b[i].time;
         if(t>=anchor-3600 && t<anchor+510*60){nh=MathMax(nh,b[i].high);nl=MathMin(nl,b[i].low);}
         if(t<anchor+start*60 || t>=right)continue;
         if(t<anchor+(start+openingLength)*60){if(t==anchor+start*60)op=b[i].open;opened++;hi=MathMax(hi,b[i].high);lo=MathMin(lo,b[i].low);}
         double q=(double)(b[i].real_volume>0?b[i].real_volume:b[i].tick_volume);
         pv+=(b[i].high+b[i].low+b[i].close)/3*q;vol+=q;double value=vol>0?pv/vol:0;
         if(priorTime>0 && t==priorTime+60){
            datetime slot=(datetime)((long)t/seconds*seconds+seconds);
            if(slot!=segment){segment=slot;segmentLeft=priorTime+60;segmentValue=prior;}
            OSHistoryLine(tag+"VWAP_"+IntegerToString((long)slot),segmentLeft,segmentValue,t+60,value,clrDeepSkyBlue);
         }
         priorTime=t;prior=value;
      }
      
      if(opened!=openingLength || op<=0)complete=false;
      if(opened==openingLength && op>0 ){
         OSHistoryLine(tag+"Session Opening Price (SOP)",anchor,op,right,op,clrSilver);
         double mean=0;if(OSSessionATRMean(sd,mean,true))OSHistoryLine(tag+"Noise Up Barrier (NUB)",anchor,op+NoiseFraction*mean,right,op+NoiseFraction*mean,clrOrange);
         else complete=false;
      }
   }
   if(complete)OSHistoryRendered=today;
   vbBrokerVisualDirty=true;
}
void OSDraw()
{
   if(!OSVisualEnabled())return;
   string fault=OSVisualFault();
   OSVisualSuspend(fault!="");
   if(fault!="")
   {
      datetime now=MQLInfoInteger(MQL_TESTER)?TimeCurrent():TimeTradeServer();
      OSPanelRows(now,fault,0,0);
      ChartRedraw(osVisualChart);return;
   }
   // Original Vault-specific historical NUB/ATR overlays do not apply to these models.
   // Keep broker-owned entry/stop/target charts, suppress invalid research levels.
   if(!OSVisualEnabled()) return;
   string p=OSVisualPrefix();
   if(dayValid && day==OSVisualDay(TimeCurrent()))
   {
      OSLine("Session Opening Price (SOP)",midnight,clrSilver,STYLE_DOT);
      if(Model==OpeningShock || Model==PostCloseFade) OSLine("RTH reference range (points)",midnight+averageATR,clrOrange,STYLE_DOT);
      else if(rangeReady)
      {
         OSLine("Opening range high",orHigh,clrOrange,STYLE_DOT);
         OSLine("Opening range low",orLow,clrOrange,STYLE_DOT);
         OSLine("Overnight high",overnightHigh,clrDeepSkyBlue,STYLE_DOT);
         OSLine("Overnight low",overnightLow,clrDeepSkyBlue,STYLE_DOT);
         OSLine("Bias upper third",overnightLow+2*(overnightHigh-overnightLow)/3,clrSlateGray,STYLE_DOT);
         OSLine("Bias lower third",overnightLow+(overnightHigh-overnightLow)/3,clrSlateGray,STYLE_DOT);
      }
      ObjectDelete(osVisualChart,p+"VWAP current"); // The VWAP is its bounded curve, never a horizontal ray.
   }
   string state=virtualActive ? "Synthetic first trade: waiting for TP / SL" : "Waiting for a fresh closed-bar signal";
   if(virtualActive || vbVirtualExitTime>virtualStart)
   {
      datetime end=virtualActive?OSSessionTime(day)+OSSessionCutoff(OSSessionTime(day),(int)Model)*60:vbVirtualExitTime;
      OSLine("Synthetic entry",virtualStop+StopPoints,clrSlateGray,STYLE_DASH,virtualStart,end);
      OSLine("Synthetic SL",virtualStop,clrTomato,STYLE_DASH,virtualStart,end);
      OSLine("Synthetic TP",virtualTarget,clrLimeGreen,STYLE_DASH,virtualStart,end);
   }
   else {ObjectDelete(osVisualChart,p+"Synthetic entry");ObjectDelete(osVisualChart,p+"Synthetic SL");ObjectDelete(osVisualChart,p+"Synthetic TP");}
   if(OwnPosition())
   {
      state="Broker position protected";
      OSRememberBracket(PositionGetDouble(POSITION_PRICE_OPEN),PositionGetDouble(POSITION_SL),PositionGetDouble(POSITION_TP));
      OSLine("Entry",PositionGetDouble(POSITION_PRICE_OPEN),clrWhite,STYLE_DOT);
      OSLine("Stop",PositionGetDouble(POSITION_SL),clrTomato);
      OSLine("Target",PositionGetDouble(POSITION_TP),clrLimeGreen);
   }
   else {ObjectDelete(osVisualChart,p+"Entry");ObjectDelete(osVisualChart,p+"Stop");ObjectDelete(osVisualChart,p+"Target");}
   if(!OwnPosition() && osLastEntry>0)
   {
      OSLine("Last entry (reference)",osLastEntry,clrWhite,STYLE_DOT);
      OSLine("Last stop (reference)",osLastStop,clrTomato,STYLE_DASH);
      OSLine("Last target (reference)",osLastTarget,clrLimeGreen,STYLE_DASH);
   }
   else
   {
      ObjectDelete(osVisualChart,p+"Last entry (reference)");ObjectDelete(osVisualChart,p+"Last stop (reference)");ObjectDelete(osVisualChart,p+"Last target (reference)");
   }
   double a[];ArraySetAsSeries(a,true);double adx=0;
   if(CopyBuffer(adxHandle,0,1,1,a)==1) adx=a[0];
   if(!dayValid) state="Waiting for session history / indicators";
   if(day!=OSVisualDay(TimeCurrent()) || (!dayValid && OSMinute(TimeCurrent())<1)) state="Session forming | waiting for completed source data";
   if(!MQLInfoInteger(MQL_TESTER) && !runtimeHistoryReady) state="Loading history | new entries blocked | protection active";
   if(!EnableTrading) state="New trades disabled | existing trades remain protected";
   datetime clock=MQLInfoInteger(MQL_TESTER) ? TimeCurrent() : TimeTradeServer();
   if(!clockReady) state="Loading clock history | waiting for a verified session anchor";
   if(runtimeRecoveryHold) state="Recovery needs attention | broker SL/TP retained";
   if(runtimeCloseAttention) state="Close unconfirmed | no duplicate request";
   if(runtimeCloseRejected) state="Close rejected | retry paused";
   double nub=dayValid && day==OSVisualDay(clock) ? midnight+NoiseFraction*averageATR : 0;
   string level=OSVisualPrefix()+"Noise Up Barrier (NUB)";
   if(nub<=0 && ObjectFind(osVisualChart,level)>=0
      && (datetime)ObjectGetInteger(osVisualChart,level,OBJPROP_TIME,0)==OSSessionTime(OSVisualDay(clock)))
      nub=ObjectGetDouble(osVisualChart,level,OBJPROP_PRICE,0);
   OSPaintBrokerTrades(clock);
   OSPanelRows(clock,state,adx,nub);
   static datetime fittedBar=0;
   static double fittedStop=0,fittedTarget=0;
   datetime currentBar=iTime(_Symbol,sourceTF,0);
   double fitStop=virtualActive ? virtualStop : osLastStop,fitTarget=virtualActive ? virtualTarget : osLastTarget;
   if(currentBar>0 && (currentBar!=fittedBar || fitStop!=fittedStop || fitTarget!=fittedTarget))
   {
      OSVisualFit();fittedBar=currentBar;fittedStop=fitStop;fittedTarget=fitTarget;
   }
   ChartRedraw(osVisualChart);
}
void OSDrawVWAP(datetime t,double value)
{
   if(!OSVisualDataEnabled() || value<=0) return;
   static datetime previous=0;static double old=0;
   static datetime segment=0,left=0;static double leftValue=0;
   int seconds=MathMax(60,PeriodSeconds((ENUM_TIMEFRAMES)ChartPeriod(osVisualChart)));
   // Each completed M1 value remains the endpoint. A viewed-bar boundary ends
   // the previous segment, so dotted strokes span pixels rather than subpixels.
   datetime end=(datetime)(((long)t-1)/seconds*seconds+seconds);
   if(previous>0 && (t<=previous || OSDay(previous)!=OSDay(t)))
   {previous=0;segment=0;left=0;old=0;leftValue=0;}
   if(previous>0 && OSDay(previous)==OSDay(t) && t>previous)
   {
      if(segment!=end){segment=end;left=previous;leftValue=old;}
      string id=OSVisualPrefix()+"VWAP_"+IntegerToString((long)segment);
      if(ObjectFind(osVisualChart,id)<0) ObjectCreate(osVisualChart,id,OBJ_TREND,0,left,leftValue,t,value);
      ObjectMove(osVisualChart,id,0,left,leftValue);ObjectMove(osVisualChart,id,1,t,value);
      ObjectSetInteger(osVisualChart,id,OBJPROP_COLOR,clrDeepSkyBlue);
      ObjectSetInteger(osVisualChart,id,OBJPROP_BACK,true);
      ObjectSetInteger(osVisualChart,id,OBJPROP_STYLE,STYLE_DOT);
      ObjectSetInteger(osVisualChart,id,OBJPROP_WIDTH,1);
      ObjectSetInteger(osVisualChart,id,OBJPROP_RAY_LEFT,false);ObjectSetInteger(osVisualChart,id,OBJPROP_RAY_RIGHT,false);ObjectSetInteger(osVisualChart,id,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(osVisualChart,id,OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS);
      ObjectSetString(osVisualChart,id,OBJPROP_TOOLTIP,OSDisplayName+" | Midnight Central VWAP | "+TimeToString(t,TIME_DATE|TIME_MINUTES)+" | "+DoubleToString(value,_Digits));
   }
   previous=t;old=value;
}
void OSRefreshLiveVisuals(datetime now)
{
   if(MQLInfoInteger(MQL_TESTER) || !OSVisualEnabled() || !OSRuntimeHistoryReady()) return;
   datetime visualDay=OSVisualDay(now);
   if(dayValid && day==visualDay) return;
   static datetime refreshed=0,previousDay=0;
   datetime minute=(datetime)((long)now/60*60);
   if(minute==refreshed) return;
   datetime anchor=OSSessionTime(visualDay);
   if(minute<=anchor) return; // No completed M1 bar in this session yet.
   datetime right=anchor+OSSessionCutoff(anchor,(int)Model)*60;
   // Date-keyed session history and broker executions survive session rollover.
   MqlRates bars[];ArraySetAsSeries(bars,false);
   if(!M1HistoryAvailable(anchor)) return;
   int count=CopyRates(_Symbol,PERIOD_M1,anchor,minute-60,bars);
   if(count<=0 || !NativeBarsValid(bars,anchor,minute)) return;
   previousDay=visualDay;refreshed=minute;
   double pv=0,volume=0;
   double sessionOpen=0;
   if(OpeningPrice(anchor,30,sessionOpen))
   {
      OSLine("Session Opening Price (SOP)",sessionOpen,clrSilver,STYLE_DOT,anchor,right);
      double mean=0;
      if(OSSessionATRMean(visualDay,mean))
      {
         OSLine("Noise Up Barrier (NUB)",sessionOpen+NoiseFraction*mean,clrOrange,STYLE_DOT,anchor,right);
      }
   }
   for(int i=0;i<count;i++)
   {
      double weight=(double)(bars[i].real_volume>0 ? bars[i].real_volume : bars[i].tick_volume);
      pv+=(bars[i].high+bars[i].low+bars[i].close)/3.0*weight;volume+=weight;
      if(volume>0) OSDrawVWAP(bars[i].time,pv/volume);
   }
   // Display projection never changes trading day, bias, attempts, readiness, or indicator accumulators.
   static bool reported=false;
   if(!reported)
   {
      int levels=0,curve=0;
      string prefix=OSVisualPrefix();
      for(int index=ObjectsTotal(osVisualChart,0,-1)-1;index>=0;index--)
      {
         string name=ObjectName(osVisualChart,index,0,-1);
         if(StringFind(name,prefix)!=0 || ObjectGetInteger(osVisualChart,name,OBJPROP_TYPE)!=OBJ_TREND) continue;
         if(StringFind(name,prefix+"VWAP_")==0) curve++;else levels++;
      }
      if(levels>0 || curve>0)
      {
         PrintFormat("OS_LIVE_DISPLAY_READY levels=%d curveSegments=%d viewed=%s source=M1 session=%s",levels,curve,EnumToString((ENUM_TIMEFRAMES)Period()),TimeToString(visualDay,TIME_DATE));
         reported=true;
      }
   }
   OSVisualFit();
}

#endif
