#ifndef VWP_STRATEGY_VISUALS
#define VWP_STRATEGY_VISUALS
long gtVisualChart=0;
int gtPane=INVALID_HANDLE;
string gtPaneName="";
double gtLastEntry=0,gtLastStop=0,gtLastTarget=0;
datetime gtLastBracketTime=0;
void VWPRememberBracket(double entry,double stop,double target){gtLastEntry=entry;gtLastStop=stop;gtLastTarget=target;gtLastBracketTime=ownedEntryTime>0 ? ownedEntryTime : TimeCurrent();}
void VWPVisualFit(datetime reference=0)
{
   double low=DBL_MAX,high=-DBL_MAX;
   MqlRates b[];
   int n=reference>0 ? CopyRates(_Symbol,sourceTF,reference,96,b) : CopyRates(_Symbol,sourceTF,0,96,b);
   for(int i=0;i<n;i++){low=MathMin(low,b[i].low);high=MathMax(high,b[i].high);}
   double levels[]={orHigh,orLow,overnightHigh,overnightLow,gtLastEntry,gtLastStop,gtLastTarget,
                    virtualActive ? virtualStop : 0,virtualActive ? virtualTarget : 0};
   for(int i=0;i<ArraySize(levels);i++) if(levels[i]>0){low=MathMin(low,levels[i]);high=MathMax(high,levels[i]);}
   if(high<=low || low==DBL_MAX) return;
   double pad=(high-low)*.08;
   ChartSetInteger(gtVisualChart,CHART_SCALEFIX,true);
   ChartSetDouble(gtVisualChart,CHART_FIXED_MIN,low-pad);ChartSetDouble(gtVisualChart,CHART_FIXED_MAX,high+pad);
   ChartSetInteger(gtVisualChart,CHART_SCALE,3);ChartNavigate(gtVisualChart,CHART_END,reference>0 ? -iBarShift(_Symbol,sourceTF,reference,false) : 0);
   ChartRedraw(gtVisualChart);
}
string VWPVisualPrefix(){return "VWP_"+IntegerToString((long)Magic)+"_";}
datetime VWPVisualDay(datetime now){return VWPDay(now);}
bool VWPVisualEnabled(){return ShowVisuals && (!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE));}
bool gtVisualSuspended=false;
string VWPVisualFault()
{
   bool tester=MQLInfoInteger(MQL_TESTER);
   if(!tester && !TerminalInfoInteger(TERMINAL_CONNECTED))return "Disconnected | waiting for server";
   if(!tester && !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))return "Terminal trading disabled";
   if(!tester && !MQLInfoInteger(MQL_TRADE_ALLOWED))return "EA trading permission disabled";
   if(!tester && !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))return "Server account trading disabled";
   if(!tester && !VWPRuntimeAccountContextValid())return "Account context changed | trading blocked";
   if(runtimeCloseRejected)return "Close rejected | retry paused";
   if(runtimeCloseAttention)return "Close unconfirmed | recovery pending";
   if(runtimeRecoveryHold)return "Recovery needs attention | broker SL/TP retained";
   if(runtimeBlocked)return "Recovery / server order error | trading blocked";
   if(!clockReady)return "Clock history loading";
   if(!SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_SYNCHRONIZED) || iTime(_Symbol,PERIOD_M1,1)<=0)
      return "M1 history unavailable";
   if(!tester && !runtimeHistoryReady)return "History / indicators loading";
   if(modelDisconnected || StringFind(modelStatus,"missing M1")>=0 || modelStatus=="Clock history loading"
      || modelStatus=="Reloading opening range history" || modelStatus=="M1 history unavailable")return modelStatus;
   return "";
}
bool VWPVisualDataEnabled(){return VWPVisualEnabled() && VWPVisualFault()=="";}
void VWPVisualSuspend(bool blocked)
{
   if(blocked==gtVisualSuspended)return;
   gtVisualSuspended=blocked;
   // Preserve chart history for restoration; touch only this EA's own namespace.
   string prefix=VWPVisualPrefix(),panel=VWPPanelPrefix();
   for(int index=ObjectsTotal(gtVisualChart,-1,-1)-1;index>=0;index--)
   {
      string name=ObjectName(gtVisualChart,index,-1,-1);
      if(StringFind(name,prefix)!=0 || StringFind(name,panel)==0)continue;
      ObjectSetInteger(gtVisualChart,name,OBJPROP_TIMEFRAMES,blocked ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS);
   }
   if(gtPaneName!="")
   {
      if(blocked)
      {
         for(int window=(int)ChartGetInteger(gtVisualChart,CHART_WINDOWS_TOTAL)-1;window>=1;window--)
            ChartIndicatorDelete(gtVisualChart,window,gtPaneName);
      }
      else if(gtPane!=INVALID_HANDLE)
         ChartIndicatorAdd(gtVisualChart,(int)ChartGetInteger(gtVisualChart,CHART_WINDOWS_TOTAL),gtPane);
   }
   ChartRedraw(gtVisualChart);
}
void VWPInitVisual()
{
   if(!VWPVisualEnabled()) return;
   string oldRows[]={"Title","Clock","Metrics","State"};
   for(int i=0;i<ArraySize(oldRows);i++)ObjectDelete(gtVisualChart,VWPVisualPrefix()+oldRows[i]);
   ChartSetInteger(gtVisualChart,CHART_EVENT_OBJECT_CREATE,true);

   // Remove only objects owned by this EA under its former object namespace.
   ObjectsDeleteAll(gtVisualChart,"GT_"+IntegerToString((long)Magic)+"_");
   // Repair retained owned drawings from builds that used the foreground layer.
   for(int i=ObjectsTotal(gtVisualChart,-1,-1)-1;i>=0;i--)
   {
      string name=ObjectName(gtVisualChart,i,-1,-1);
      if(StringFind(name,VWPVisualPrefix())==0 && StringFind(name,VWPPanelPrefix())!=0)
      {
         ObjectSetInteger(gtVisualChart,name,OBJPROP_BACK,true);
         if(ObjectGetInteger(gtVisualChart,name,OBJPROP_TYPE)==OBJ_RECTANGLE)
         {ObjectSetInteger(gtVisualChart,name,OBJPROP_FILL,false);ObjectSetInteger(gtVisualChart,name,OBJPROP_WIDTH,1);}
      }
   }
   ObjectsDeleteAll(gtVisualChart,VWPVisualPrefix()+"VWAP");
   ObjectDelete(gtVisualChart,VWPVisualPrefix()+"Session Opening Price (SOP)");
   ObjectDelete(gtVisualChart,VWPVisualPrefix()+"Noise Up Barrier (NUB)");
   ChartSetInteger(gtVisualChart,CHART_MODE,CHART_CANDLES);
   ChartSetInteger(gtVisualChart,CHART_COLOR_BACKGROUND,clrBlack);
   ChartSetInteger(gtVisualChart,CHART_COLOR_FOREGROUND,clrSilver);
   ChartSetInteger(gtVisualChart,CHART_COLOR_CANDLE_BULL,clrWhite);
   ChartSetInteger(gtVisualChart,CHART_COLOR_CANDLE_BEAR,clrDarkOrange);
   ChartSetInteger(gtVisualChart,CHART_COLOR_CHART_UP,clrWhite);
   ChartSetInteger(gtVisualChart,CHART_COLOR_CHART_DOWN,clrDarkOrange);
   ChartSetInteger(gtVisualChart,CHART_SHOW_GRID,false);
   ChartSetInteger(gtVisualChart,CHART_AUTOSCROLL,true);ChartSetInteger(gtVisualChart,CHART_SHIFT,true);
   if(Model==VWAPPullback)
   {
      gtPaneName=VWPOutputFamily+" ADX "+IntegerToString((long)Magic);
      for(int window=(int)ChartGetInteger(gtVisualChart,CHART_WINDOWS_TOTAL)-1;window>=1;window--)
         for(int index=ChartIndicatorsTotal(gtVisualChart,window)-1;index>=0;index--)
            if(ChartIndicatorName(gtVisualChart,window,index)==gtPaneName) ChartIndicatorDelete(gtVisualChart,window,gtPaneName);
      gtPane=iCustom(_Symbol,(ENUM_TIMEFRAMES)Period(),"::ADXPane.ex5",ADXPeriod,gtPaneName);
      if(gtPane!=INVALID_HANDLE && !ChartIndicatorAdd(gtVisualChart,(int)ChartGetInteger(gtVisualChart,CHART_WINDOWS_TOTAL),gtPane))
         PrintFormat("VWP_DISPLAY_ADX_ADD_FAILED error=%d",GetLastError());
   }
}

const int PX=10,PY=20,PW=210,PH=198,HH=32;
bool vwpPanelCollapsed=false,vwpPanelRestack=false;
string VWPPanelPrefix(){return VWPVisualPrefix()+"PANEL_";}
void VWPPanelRect(string name, int x, int y, int w, int h, color bg, color bdr)
{
    if(ObjectFind(gtVisualChart, name) < 0)
    {
        ObjectCreate(gtVisualChart, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
        ObjectSetInteger(gtVisualChart, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
        ObjectSetInteger(gtVisualChart, name, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(gtVisualChart, name, OBJPROP_HIDDEN,     true);
        ObjectSetInteger(gtVisualChart, name, OBJPROP_BACK,       false);  // foreground â€” blocks chart
    }
    ObjectSetInteger(gtVisualChart, name, OBJPROP_ZORDER,     10000);
    ObjectSetInteger(gtVisualChart, name, OBJPROP_BACK,       false);
    ObjectSetInteger(gtVisualChart, name, OBJPROP_XDISTANCE,   x);
    ObjectSetInteger(gtVisualChart, name, OBJPROP_YDISTANCE,   y);
    ObjectSetInteger(gtVisualChart, name, OBJPROP_XSIZE,       w);
    ObjectSetInteger(gtVisualChart, name, OBJPROP_YSIZE,       h);
    ObjectSetInteger(gtVisualChart, name, OBJPROP_BGCOLOR,     (long)bg);
    ObjectSetInteger(gtVisualChart, name, OBJPROP_COLOR,       (long)bdr);
    ObjectSetInteger(gtVisualChart, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
}

void VWPPanelLbl(string name, int x, int y, string text, int fs, color clr)
{
    if(ObjectFind(gtVisualChart, name) < 0)
    {
        ObjectCreate(gtVisualChart, name, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(gtVisualChart, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
        ObjectSetInteger(gtVisualChart, name, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(gtVisualChart, name, OBJPROP_HIDDEN,     true);
        ObjectSetInteger(gtVisualChart, name, OBJPROP_BACK,       false);
        ObjectSetString(gtVisualChart,  name, OBJPROP_FONT,       "Segoe UI Semibold");
    }
    ObjectSetInteger(gtVisualChart, name, OBJPROP_ZORDER,     10001);
    if((int)ObjectGetInteger(gtVisualChart, name, OBJPROP_XDISTANCE) != x) ObjectSetInteger(gtVisualChart, name, OBJPROP_XDISTANCE, x);
    if((int)ObjectGetInteger(gtVisualChart, name, OBJPROP_YDISTANCE) != y) ObjectSetInteger(gtVisualChart, name, OBJPROP_YDISTANCE, y);
    if((int)ObjectGetInteger(gtVisualChart, name, OBJPROP_FONTSIZE)  != fs) ObjectSetInteger(gtVisualChart, name, OBJPROP_FONTSIZE, fs);
    if(ObjectGetInteger(gtVisualChart, name, OBJPROP_COLOR) != (long)clr) ObjectSetInteger(gtVisualChart, name, OBJPROP_COLOR, (long)clr);
    if(ObjectGetString(gtVisualChart, name, OBJPROP_TEXT) != text) ObjectSetString(gtVisualChart, name, OBJPROP_TEXT, text);
}

void VWPPanelShell()
{
    if(!VWPVisualEnabled()) return;
    int height=vwpPanelCollapsed ? HH : PH;
    VWPPanelRect(VWPPanelPrefix()+"SHD2", PX+5, PY+5, PW, height, C'6,6,6',    C'6,6,6');
    VWPPanelRect(VWPPanelPrefix()+"SHD1", PX+2, PY+2, PW, height, C'12,12,12', C'12,12,12');
    VWPPanelRect(VWPPanelPrefix()+"BG",   PX,   PY,   PW, height, clrBlack,    C'52,68,92');
    VWPPanelRect(VWPPanelPrefix()+"HDR",  PX,   PY,   PW, HH, C'18,22,28', C'52,68,92');
    VWPPanelRect(VWPPanelPrefix()+"HAIR", PX,   PY+HH, PW, 1, C'52,68,92', C'52,68,92');
    VWPPanelLbl(VWPPanelPrefix()+"TTL",   PX+8, PY+8, "VWAP Pullback", 9, C'190,210,236');
    string button=VWPPanelPrefix()+"BTN";
    if(ObjectFind(gtVisualChart,button)<0)
    {
        ObjectCreate(gtVisualChart,button,OBJ_BUTTON,0,0,0);
        ObjectSetInteger(gtVisualChart,button,OBJPROP_CORNER,CORNER_LEFT_UPPER);
        ObjectSetInteger(gtVisualChart,button,OBJPROP_HIDDEN,true);
        ObjectSetString(gtVisualChart,button,OBJPROP_FONT,"Segoe UI Semibold");
    }
    ObjectSetInteger(gtVisualChart,button,OBJPROP_XDISTANCE,PX+PW-29);
    ObjectSetInteger(gtVisualChart,button,OBJPROP_ZORDER,10002);
    ObjectSetInteger(gtVisualChart,button,OBJPROP_YDISTANCE,PY+5);
    ObjectSetInteger(gtVisualChart,button,OBJPROP_XSIZE,22);
    ObjectSetInteger(gtVisualChart,button,OBJPROP_YSIZE,22);
    ObjectSetInteger(gtVisualChart,button,OBJPROP_FONTSIZE,12);
    ObjectSetInteger(gtVisualChart,button,OBJPROP_COLOR,(long)C'190,210,236');
    ObjectSetInteger(gtVisualChart,button,OBJPROP_BGCOLOR,(long)C'18,22,28');
    ObjectSetInteger(gtVisualChart,button,OBJPROP_BORDER_COLOR,(long)C'52,68,92');
    ObjectSetInteger(gtVisualChart,button,OBJPROP_STATE,false);
    ObjectSetString(gtVisualChart,button,OBJPROP_TEXT,vwpPanelCollapsed ? "+" : "-");
    if(vwpPanelCollapsed)
    {
        string rows[]={"SRV","HI","LO","SZ","BUY","SEL","CST","COV","SL"};
        for(int i=0;i<ArraySize(rows);i++) ObjectDelete(gtVisualChart,VWPPanelPrefix()+rows[i]);
    }
}

void VWPPanelRows(datetime clock,string state,double adx,double nub)
{
   if(vwpPanelRestack){vwpPanelRestack=false;ObjectsDeleteAll(gtVisualChart,VWPPanelPrefix());}
   VWPPanelShell();
   if(vwpPanelCollapsed)return;
   string p=VWPPanelPrefix();
   VWPPanelLbl(p+"SRV",PX+8,PY+40,clockReady ? "NY: "+TimeToString(VWPNewYork(clock),TIME_SECONDS)+" CT: "+TimeToString(VWPCentral(clock),TIME_SECONDS) : "Clock history loading",8,C'140,158,185');
   VWPPanelLbl(p+"HI",PX+8,PY+59,"Range high: "+(rangeReady && orHigh>0?DoubleToString(orHigh,2):"--"),8,C'120,210,150');
   VWPPanelLbl(p+"LO",PX+8,PY+76,"Range low: "+(rangeReady && orLow>0?DoubleToString(orLow,2):"--"),8,C'210,100,100');
   VWPPanelLbl(p+"SZ",PX+8,PY+93,StringFormat("ADX: %.2f | %s%s%s",adx,setup.H?"H":"-",setup.V?"V":"-",setup.R?"R":"-"),8,C'140,158,185');
   VWPPanelLbl(p+"BUY",PX+8,PY+112,"Trades "+IntegerToString(entries)+"/1",8,C'120,210,150');
   VWPPanelLbl(p+"SEL",PX+112,PY+112,OwnPosition()?"Position: open":"Position: flat",8,C'210,100,100');
   VWPPanelLbl(p+"CST",PX+8,PY+132,StringFormat("Comm/lot: $%.2f | Slip: %dp",VWPCommissionEstimate(),SlippagePoints),8,C'140,200,240');
   VWPPanelLbl(p+"COV",PX+8,PY+149,"VWAP: "+(setup.Vwap>0?DoubleToString(setup.Vwap,2):"--")+" | TP 1.27R",8,C'190,180,120');
   string display=VWPSizingLabel()+" | "+state;
   VWPPanelLbl(p+"SL",PX+8,PY+166,StringSubstr(display,0,31),8,C'200,70,70');
   ObjectSetString(gtVisualChart,p+"SL",OBJPROP_TOOLTIP,display);
}
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(!VWPVisualEnabled())return;
   if(id==CHARTEVENT_OBJECT_CREATE && StringFind(sparam,VWPPanelPrefix())!=0)
   {vwpPanelRestack=true;return;}
   if(id==CHARTEVENT_OBJECT_CLICK && sparam==VWPPanelPrefix()+"BTN")
   {vwpPanelCollapsed=!vwpPanelCollapsed;VWPDraw();ChartRedraw(gtVisualChart);}
}

datetime VWPHistoryFloor=0,VWPHistoryRendered=0;
bool vwpBrokerVisualDirty=true;
bool vwpBrokerVisualInitialized=false;
struct VWPBrokerView
{
   ulong id;int side;datetime entered,exited;double entryValue,volume,exitValue,exitVolume,stop;bool mixed;
};
VWPBrokerView vwpBrokerView[];
void VWPTradeBox(string key,datetime left,datetime right,double entry,double edge,color ink)
{
   if(!VWPVisualDataEnabled())return;
   string id=VWPVisualPrefix()+key;
   if(right<=left)right=left+1;
   if(ObjectFind(gtVisualChart,id)<0)ObjectCreate(gtVisualChart,id,OBJ_RECTANGLE,0,left,entry,right,edge);
   ObjectMove(gtVisualChart,id,0,left,entry);ObjectMove(gtVisualChart,id,1,right,edge);
   ObjectSetInteger(gtVisualChart,id,OBJPROP_COLOR,ink);
   ObjectSetInteger(gtVisualChart,id,OBJPROP_FILL,false);
   ObjectSetInteger(gtVisualChart,id,OBJPROP_WIDTH,1);
   ObjectSetInteger(gtVisualChart,id,OBJPROP_BACK,true);
   ObjectSetInteger(gtVisualChart,id,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(gtVisualChart,id,OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS);
   ObjectSetString(gtVisualChart,id,OBJPROP_TOOLTIP,"VWAP Pullback | Broker execution | "+key);
}
void VWPPaintBrokerTrades(datetime now)
{
   bool rebuild=vwpBrokerVisualDirty;
   if(rebuild)
   {
      int bars=Bars(_Symbol,_Period);
      datetime begin=!vwpBrokerVisualInitialized && bars>0?iTime(_Symbol,_Period,bars-1):now-45*86400;
      begin=now-90*86400; // Include owned openings preceding the visible history window.
      if(!HistorySelect(begin,now))return;
      vwpBrokerVisualInitialized=true;
      ArrayResize(vwpBrokerView,0);
      // Retire average-price arrows from earlier builds; exact deal tickets replace them.
      ObjectsDeleteAll(gtVisualChart,VWPVisualPrefix()+"Entry_");
      ObjectsDeleteAll(gtVisualChart,VWPVisualPrefix()+"Exit_");
      for(int i=0;i<HistoryDealsTotal();i++)
      {
         ulong d=HistoryDealGetTicket(i);
         if(HistoryDealGetString(d,DEAL_SYMBOL)!=_Symbol)continue;
         long kind=HistoryDealGetInteger(d,DEAL_ENTRY);
         ulong id=(ulong)HistoryDealGetInteger(d,DEAL_POSITION_ID);int k=-1;
         for(int j=0;j<ArraySize(vwpBrokerView);j++)if(vwpBrokerView[j].id==id){k=j;break;}
         if(kind==DEAL_ENTRY_IN)
         {
            if((ulong)HistoryDealGetInteger(d,DEAL_MAGIC)!=Magic)continue;
            if(k<0){k=ArraySize(vwpBrokerView);ArrayResize(vwpBrokerView,k+1);ZeroMemory(vwpBrokerView[k]);vwpBrokerView[k].id=id;vwpBrokerView[k].entered=(datetime)HistoryDealGetInteger(d,DEAL_TIME);}
            double qty=HistoryDealGetDouble(d,DEAL_VOLUME);
            vwpBrokerView[k].side=HistoryDealGetInteger(d,DEAL_TYPE)==DEAL_TYPE_BUY?1:-1;
            vwpBrokerView[k].entryValue+=qty*HistoryDealGetDouble(d,DEAL_PRICE);vwpBrokerView[k].volume+=qty;
            ulong order=(ulong)HistoryDealGetInteger(d,DEAL_ORDER);
            double sl=HistoryOrderGetDouble(order,ORDER_SL);if(sl>0)vwpBrokerView[k].stop=sl;
         }
         else if(k>=0 && (kind==DEAL_ENTRY_OUT || kind==DEAL_ENTRY_OUT_BY))
         {
            double qty=HistoryDealGetDouble(d,DEAL_VOLUME);
            vwpBrokerView[k].exitValue+=qty*HistoryDealGetDouble(d,DEAL_PRICE);vwpBrokerView[k].exitVolume+=qty;
            vwpBrokerView[k].exited=(datetime)HistoryDealGetInteger(d,DEAL_TIME);
         }
      }
      // Shared/netting positions with mixed opening ownership or reversals are not attributed.
      for(int i=0;i<HistoryDealsTotal();i++){
         ulong deal=HistoryDealGetTicket(i);long kind=HistoryDealGetInteger(deal,DEAL_ENTRY);
         if(kind!=DEAL_ENTRY_IN && kind!=DEAL_ENTRY_INOUT)continue;
         ulong id=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
         for(int k=0;k<ArraySize(vwpBrokerView);k++)if(vwpBrokerView[k].id==id
            && (kind==DEAL_ENTRY_INOUT || (ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=Magic))vwpBrokerView[k].mixed=true;
      }
      // Exact deal prices/timestamps, including partial fills and manual exits of owned positions.
      for(int i=0;i<HistoryDealsTotal();i++)
      {
         ulong deal=HistoryDealGetTicket(i);
         if(HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol)continue;
         ulong position=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
         bool owned=false;
         for(int k=0;k<ArraySize(vwpBrokerView);k++)if(vwpBrokerView[k].id==position && !vwpBrokerView[k].mixed){owned=true;break;}
         datetime at=(datetime)HistoryDealGetInteger(deal,DEAL_TIME);
         long type=HistoryDealGetInteger(deal,DEAL_TYPE);
         if(!owned || at<VWPHistoryFloor || (type!=DEAL_TYPE_BUY && type!=DEAL_TYPE_SELL))continue;
         VWPDrawFill(type==DEAL_TYPE_BUY?1:-1,at,HistoryDealGetDouble(deal,DEAL_PRICE),"Deal "+IntegerToString((long)deal));
      }
      vwpBrokerVisualDirty=false;
   }
   for(int i=0;i<ArraySize(vwpBrokerView);i++)
   {
      if(vwpBrokerView[i].volume<=0 || vwpBrokerView[i].mixed)continue;
      double entry=vwpBrokerView[i].entryValue/vwpBrokerView[i].volume;
      bool closed=vwpBrokerView[i].exitVolume>=vwpBrokerView[i].volume-1e-8;
      if(closed && (!rebuild || vwpBrokerView[i].exited<VWPHistoryFloor))continue;
      datetime right=closed?vwpBrokerView[i].exited:(datetime)MathMax((double)now,(double)(vwpBrokerView[i].entered+3*PeriodSeconds(_Period)));
      double exit=closed?vwpBrokerView[i].exitValue/vwpBrokerView[i].exitVolume:0;
      double stop=vwpBrokerView[i].stop>0?vwpBrokerView[i].stop:0;
      // Keep original order SL as risk geometry; an exit fill is not the initial stop.
      string tag="Broker "+IntegerToString((long)vwpBrokerView[i].id);
      if(stop>0)VWPTradeBox(tag+" risk",vwpBrokerView[i].entered,right,entry,stop,C'55,57,68');
      VWPLine(tag+" entry",entry,C'214,218,224',STYLE_SOLID,vwpBrokerView[i].entered,right);
      if(closed && vwpBrokerView[i].side*(exit-entry)>0)VWPTradeBox(tag+" profit",vwpBrokerView[i].entered,right,entry,exit,C'22,55,120');
      // Per-deal arrows above are authoritative; averages only define the position box.
   }
}

void VWPDrawFill(int side,datetime time,double price,string label)
{
   if(!VWPVisualDataEnabled()) return;
   string id=VWPVisualPrefix()+label+"_"+IntegerToString((long)time);
   ObjectCreate(gtVisualChart,id,side==1 ? OBJ_ARROW_BUY : OBJ_ARROW_SELL,0,time,price);
   ObjectSetString(gtVisualChart,id,OBJPROP_TOOLTIP,VWPDisplayName+" | "+label+" "+TimeToString(time,TIME_DATE|TIME_SECONDS));
   ObjectSetInteger(gtVisualChart,id,OBJPROP_COLOR,clrWhite);
   ObjectSetInteger(gtVisualChart,id,OBJPROP_BACK,true);
   ObjectSetInteger(gtVisualChart,id,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(gtVisualChart,id,OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS);
}
void VWPLine(string key,double price,color ink,ENUM_LINE_STYLE style=STYLE_SOLID,datetime left=0,datetime right=0)
{
   if(!VWPVisualDataEnabled())return;
   string id=VWPVisualPrefix()+key;
   if(left==0)
   {
      left=VWPSessionTime(day);
      if(StringFind(key,"Opening range")==0) left+=510*60;
      else if(StringFind(key,"Overnight")==0 || StringFind(key,"Bias")==0)
         left-=(OvernightStart==23 ? 3600 : 0);
      else if(StringFind(key,"Synthetic")==0) left=virtualStart;
      else if(key=="Entry" || key=="Stop" || key=="Target")
         left=ownedEntryTime>0 ? ownedEntryTime : (datetime)PositionGetInteger(POSITION_TIME);
      else if(StringFind(key,"Last ")==0) left=gtLastBracketTime;
   }
   if(right==0) right=VWPSessionTime(day)+VWPSessionCutoff(VWPSessionTime(day),(int)Model)*60;
   if(left<=0 || right<=left || price<=0) {ObjectDelete(gtVisualChart,id);return;}
   if(ObjectFind(gtVisualChart,id)>=0 && ObjectGetInteger(gtVisualChart,id,OBJPROP_TYPE)!=OBJ_TREND)
      ObjectDelete(gtVisualChart,id);
   if(ObjectFind(gtVisualChart,id)<0) ObjectCreate(gtVisualChart,id,OBJ_TREND,0,left,price,right,price);
   ObjectMove(gtVisualChart,id,0,left,price);ObjectMove(gtVisualChart,id,1,right,price);
   ObjectSetInteger(gtVisualChart,id,OBJPROP_RAY_LEFT,false);ObjectSetInteger(gtVisualChart,id,OBJPROP_RAY_RIGHT,false);
   ObjectSetInteger(gtVisualChart,id,OBJPROP_COLOR,ink);ObjectSetInteger(gtVisualChart,id,OBJPROP_STYLE,style);
   ObjectSetInteger(gtVisualChart,id,OBJPROP_BACK,true);
   ObjectSetInteger(gtVisualChart,id,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(gtVisualChart,id,OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS);
   ObjectSetString(gtVisualChart,id,OBJPROP_TEXT,key);
   ObjectSetString(gtVisualChart,id,OBJPROP_TOOLTIP,VWPDisplayName+" | "+key+" | "+DoubleToString(price,_Digits)
      +" | "+TimeToString(left,TIME_DATE|TIME_MINUTES)+" to "+TimeToString(right,TIME_MINUTES)+" (broker time)");
}

void VWPHistoryLine(string key,datetime left,double a,datetime right,double b,color ink)
{
   if(!VWPVisualDataEnabled() || right<=left || a<=0 || b<=0)return;
   string id=VWPVisualPrefix()+"HISTORY_"+key;
   if(ObjectFind(gtVisualChart,id)<0)ObjectCreate(gtVisualChart,id,OBJ_TREND,0,left,a,right,b);
   ObjectMove(gtVisualChart,id,0,left,a);ObjectMove(gtVisualChart,id,1,right,b);
   ObjectSetInteger(gtVisualChart,id,OBJPROP_COLOR,ink);ObjectSetInteger(gtVisualChart,id,OBJPROP_WIDTH,1);
   ObjectSetInteger(gtVisualChart,id,OBJPROP_STYLE,STYLE_DOT);ObjectSetInteger(gtVisualChart,id,OBJPROP_BACK,true);
   ObjectSetInteger(gtVisualChart,id,OBJPROP_SELECTABLE,false);ObjectSetInteger(gtVisualChart,id,OBJPROP_RAY_LEFT,false);
   ObjectSetInteger(gtVisualChart,id,OBJPROP_RAY_RIGHT,false);ObjectSetInteger(gtVisualChart,id,OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS);
   ObjectSetString(gtVisualChart,id,OBJPROP_TOOLTIP,"Source-bar session history | "+key);
}
void VWPHistoricalSessions(datetime now)
{
   if(!VWPVisualDataEnabled() || MQLInfoInteger(MQL_TESTER))return;
   datetime today=VWPVisualDay(now);static datetime retry=0;
   if(VWPHistoryRendered==today || now<retry)return;
   retry=now+60;
   MqlRates b[];ArraySetAsSeries(b,false);
   int count=CopyRates(_Symbol,PERIOD_M1,now-14*86400,now-60,b);
   if(count<=0 || !SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_SYNCHRONIZED))return;
   datetime dates[3];int found=0;datetime last=0;
   for(int i=count-1;i>=0 && found<3;i--){
      datetime key=VWPVisualDay(b[i].time);
      datetime ny=VWPNewYork(VWPSessionTime(key));MqlDateTime d;TimeToStruct(ny,d);
      if(d.day_of_week==0 || d.day_of_week==6)continue;
      if(key==last)continue;last=key;dates[found++]=key;
   }
   if(found==0)return;
   bool complete=found==3;
   VWPHistoryFloor=VWPSessionTime(dates[found-1]);
   ObjectsDeleteAll(gtVisualChart,VWPVisualPrefix()+"HISTORY_");
   for(int n=found-1;n>=0;n--){
      datetime sd=dates[n],anchor=VWPSessionTime(sd);
      if(sd==today)continue;
      datetime right=anchor+VWPSessionCutoff(anchor,(int)Model)*60;
      string tag=IntegerToString((long)sd)+"_";
      double pv=0,vol=0,prior=0,hi=-DBL_MAX,lo=DBL_MAX,op=0,nh=-DBL_MAX,nl=DBL_MAX;
      datetime priorTime=0,segment=0,segmentLeft=0;double segmentValue=0;int opened=0;
      int seconds=MathMax(60,PeriodSeconds((ENUM_TIMEFRAMES)ChartPeriod(gtVisualChart)));
      int start=510,openingLength=30;
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
            VWPHistoryLine(tag+"VWAP_"+IntegerToString((long)slot),segmentLeft,segmentValue,t+60,value,clrDeepSkyBlue);
         }
         priorTime=t;prior=value;
      }
      
      if(opened!=openingLength || op<=0)complete=false;
      if(opened==openingLength && op>0 ){
         VWPHistoryLine(tag+"Opening range high",anchor+510*60,hi,right,hi,clrOrange);
         VWPHistoryLine(tag+"Opening range low",anchor+510*60,lo,right,lo,clrOrange);
      }
   }
   if(complete)VWPHistoryRendered=today;
   vwpBrokerVisualDirty=true;
}
void VWPDraw()
{
   if(!VWPVisualEnabled())return;
   string fault=VWPVisualFault();
   VWPVisualSuspend(fault!="");
   if(fault!="")
   {
      datetime now=MQLInfoInteger(MQL_TESTER)?TimeCurrent():TimeTradeServer();
      VWPPanelRows(now,fault,0,0);
      ChartRedraw(gtVisualChart);return;
   }
   VWPHistoricalSessions(TimeCurrent());
   if(!VWPVisualEnabled())return;
   datetime clock=MQLInfoInteger(MQL_TESTER)?TimeCurrent():TimeTradeServer();
   if(rangeReady)
   {
      datetime left=VWPSessionTime(day,510),right=VWPSessionTime(day,955);
      VWPLine("Opening range high",orHigh,clrOrange,STYLE_DOT,left,right);
      VWPLine("Opening range low",orLow,clrOrange,STYLE_DOT,left,right);
   }
   string keys[]={"Entry","Stop","Target"};
   if(OwnPosition())
   {
      datetime left=(datetime)PositionGetInteger(POSITION_TIME),right=VWPSessionTime(day,955);
      VWPLine(keys[0],PositionGetDouble(POSITION_PRICE_OPEN),clrWhite,STYLE_DOT,left,right);
      VWPLine(keys[1],PositionGetDouble(POSITION_SL),clrTomato,STYLE_DASH,left,right);
      VWPLine(keys[2],PositionGetDouble(POSITION_TP),clrLimeGreen,STYLE_DASH,left,right);
   }
   else for(int i=0;i<3;i++)ObjectDelete(0,VWPVisualPrefix()+keys[i]);
   string state=runtimeRecoveryHold?"Recovery needs attention | broker SL/TP retained":!EnableTrading?"New entries disabled":runtimeBlocked?"Recovery blocked":!clockReady?"Clock history loading":modelStatus;
   if(runtimeCloseAttention)state="Close unconfirmed | no duplicate request";
   if(runtimeCloseRejected)state="Close rejected | retry paused";
   VWPPaintBrokerTrades(clock);VWPPanelRows(clock,state,m1.Value,0);
   ChartRedraw(0);
}
void VWPRefreshLiveVisuals(datetime now){ModelUpdate(false);}

#endif


