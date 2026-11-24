#ifndef NQP_STRATEGY_VISUALS
#define NQP_STRATEGY_VISUALS
long nqvVisualChart=0;
int nqvPane=INVALID_HANDLE;
string nqvPaneName="";
double nqvLastEntry=0,nqvLastStop=0,nqvLastTarget=0;
datetime nqvLastBracketTime=0;
void NQPRememberBracket(double entry,double stop,double target){nqvLastEntry=entry;nqvLastStop=stop;nqvLastTarget=target;nqvLastBracketTime=ownedEntryTime>0 ? ownedEntryTime : TimeCurrent();}
void NQPVisualFit(datetime reference=0)
{
   double low=DBL_MAX,high=-DBL_MAX;
   MqlRates b[];
   int n=reference>0 ? CopyRates(_Symbol,sourceTF,reference,96,b) : CopyRates(_Symbol,sourceTF,0,96,b);
   for(int i=0;i<n;i++){low=MathMin(low,b[i].low);high=MathMax(high,b[i].high);}
   double levels[]={midnight,orHigh,orLow,nqvLastEntry,nqvLastStop,nqvLastTarget,
                    virtualActive ? virtualStop : 0,virtualActive ? virtualTarget : 0};
   for(int i=0;i<ArraySize(levels);i++) if(levels[i]>0){low=MathMin(low,levels[i]);high=MathMax(high,levels[i]);}
   if(high<=low || low==DBL_MAX) return;
   double pad=(high-low)*.08;
   ChartSetInteger(nqvVisualChart,CHART_SCALEFIX,true);
   ChartSetDouble(nqvVisualChart,CHART_FIXED_MIN,low-pad);ChartSetDouble(nqvVisualChart,CHART_FIXED_MAX,high+pad);
   ChartSetInteger(nqvVisualChart,CHART_SCALE,3);ChartNavigate(nqvVisualChart,CHART_END,reference>0 ? -iBarShift(_Symbol,sourceTF,reference,false) : 0);
   ChartRedraw(nqvVisualChart);
}
string NQPVisualPrefix(){return "NQP_"+IntegerToString((long)Magic)+"_";}
datetime NQPVisualDay(datetime now){return NQPDay(now);}
bool NQPVisualEnabled(){return ShowVisuals && (!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE));}
bool nqvVisualSuspended=false;
string NQPVisualFault()
{
   bool tester=MQLInfoInteger(MQL_TESTER);
   if(!tester && !TerminalInfoInteger(TERMINAL_CONNECTED))return "Disconnected | waiting for server";
   if(!tester && !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))return "Terminal trading disabled";
   if(!tester && !MQLInfoInteger(MQL_TRADE_ALLOWED))return "EA trading permission disabled";
   if(!tester && !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))return "Server account trading disabled";
   if(!tester && !NQPRuntimeAccountContextValid())return "Account context changed | trading blocked";
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
bool NQPVisualDataEnabled(){return NQPVisualEnabled() && NQPVisualFault()=="";}
void NQPVisualSuspend(bool blocked)
{
   if(blocked==nqvVisualSuspended)return;
   nqvVisualSuspended=blocked;
   // Preserve chart history for restoration; touch only this EA's own namespace.
   string prefix=NQPVisualPrefix(),panel=NQPPanelPrefix();
   for(int index=ObjectsTotal(nqvVisualChart,-1,-1)-1;index>=0;index--)
   {
      string name=ObjectName(nqvVisualChart,index,-1,-1);
      if(StringFind(name,prefix)!=0 || StringFind(name,panel)==0)continue;
      ObjectSetInteger(nqvVisualChart,name,OBJPROP_TIMEFRAMES,blocked ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS);
   }
   if(nqvPaneName!="")
   {
      if(blocked)
      {
         for(int window=(int)ChartGetInteger(nqvVisualChart,CHART_WINDOWS_TOTAL)-1;window>=1;window--)
            ChartIndicatorDelete(nqvVisualChart,window,nqvPaneName);
      }
      else if(nqvPane!=INVALID_HANDLE)
         ChartIndicatorAdd(nqvVisualChart,(int)ChartGetInteger(nqvVisualChart,CHART_WINDOWS_TOTAL),nqvPane);
   }
   ChartRedraw(nqvVisualChart);
}
void NQPInitVisual()
{
   // Objects drawn by earlier builds under the former prefixes; this build never creates them.
   ObjectsDeleteAll(0,"VB_"+IntegerToString((long)Magic)+"_");
   ObjectsDeleteAll(0,"GT_"+IntegerToString((long)Magic)+"_");
   if(!NQPVisualEnabled()) return;
   string oldRows[]={"Title","Clock","Metrics","State"};
   for(int i=0;i<ArraySize(oldRows);i++)ObjectDelete(nqvVisualChart,NQPVisualPrefix()+oldRows[i]);
   ChartSetInteger(nqvVisualChart,CHART_EVENT_OBJECT_CREATE,true);

   // Remove only objects owned by this EA under its former object namespace.
   ObjectsDeleteAll(nqvVisualChart,"GT_"+IntegerToString((long)Magic)+"_");
   // Rebuild only the bounded setup window; do not retain older-version history objects.
   ObjectsDeleteAll(nqvVisualChart,NQPVisualPrefix()+"Range ");
   ObjectsDeleteAll(nqvVisualChart,NQPVisualPrefix()+"Broker ");
   ObjectsDeleteAll(nqvVisualChart,NQPVisualPrefix()+"Deal ");
   ObjectsDeleteAll(nqvVisualChart,NQPVisualPrefix()+"Replay ");
   ObjectsDeleteAll(nqvVisualChart,NQPVisualPrefix()+"Entry_");
   ObjectsDeleteAll(nqvVisualChart,NQPVisualPrefix()+"Exit_");
   ObjectDelete(nqvVisualChart,NQPVisualPrefix()+"Opening range high");
   ObjectDelete(nqvVisualChart,NQPVisualPrefix()+"Opening range low");
   // Repair retained owned drawings from builds that used the foreground layer.
   for(int i=ObjectsTotal(nqvVisualChart,-1,-1)-1;i>=0;i--)
   {
      string name=ObjectName(nqvVisualChart,i,-1,-1);
      if(StringFind(name,NQPVisualPrefix())==0 && StringFind(name,NQPPanelPrefix())!=0)
      {
         bool execution=StringFind(name,NQPVisualPrefix()+"Broker ")==0;
         ObjectSetInteger(nqvVisualChart,name,OBJPROP_BACK,!execution);
         if(ObjectGetInteger(nqvVisualChart,name,OBJPROP_TYPE)==OBJ_RECTANGLE)
         {ObjectSetInteger(nqvVisualChart,name,OBJPROP_FILL,StringFind(name,NQPVisualPrefix()+"Range ")==0);ObjectSetInteger(nqvVisualChart,name,OBJPROP_WIDTH,execution?2:1);}
      }
   }
   ChartSetInteger(nqvVisualChart,CHART_MODE,CHART_CANDLES);
   ChartSetInteger(nqvVisualChart,CHART_COLOR_BACKGROUND,clrBlack);
   ChartSetInteger(nqvVisualChart,CHART_COLOR_FOREGROUND,clrSilver);
   ChartSetInteger(nqvVisualChart,CHART_COLOR_CANDLE_BULL,clrWhite);
   ChartSetInteger(nqvVisualChart,CHART_COLOR_CANDLE_BEAR,clrDarkOrange);
   ChartSetInteger(nqvVisualChart,CHART_COLOR_CHART_UP,clrWhite);
   ChartSetInteger(nqvVisualChart,CHART_COLOR_CHART_DOWN,clrDarkOrange);
   ChartSetInteger(nqvVisualChart,CHART_SHOW_GRID,false);
   ChartSetInteger(nqvVisualChart,CHART_AUTOSCROLL,true);ChartSetInteger(nqvVisualChart,CHART_SHIFT,true);
}

const int PX=10,PY=20,PW=210,PH=198,HH=32;
bool nqpPanelCollapsed=false,nqpPanelRestack=false;
string NQPPanelPrefix(){return NQPVisualPrefix()+"PANEL_";}
void NQPPanelRect(string name, int x, int y, int w, int h, color bg, color bdr)
{
    if(ObjectFind(nqvVisualChart, name) < 0)
    {
        ObjectCreate(nqvVisualChart, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
        ObjectSetInteger(nqvVisualChart, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
        ObjectSetInteger(nqvVisualChart, name, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(nqvVisualChart, name, OBJPROP_HIDDEN,     true);
        ObjectSetInteger(nqvVisualChart, name, OBJPROP_BACK,       false);  // foreground â€” blocks chart
    }
    ObjectSetInteger(nqvVisualChart, name, OBJPROP_ZORDER,     10000);
    ObjectSetInteger(nqvVisualChart, name, OBJPROP_BACK,       false);
    ObjectSetInteger(nqvVisualChart, name, OBJPROP_XDISTANCE,   x);
    ObjectSetInteger(nqvVisualChart, name, OBJPROP_YDISTANCE,   y);
    ObjectSetInteger(nqvVisualChart, name, OBJPROP_XSIZE,       w);
    ObjectSetInteger(nqvVisualChart, name, OBJPROP_YSIZE,       h);
    ObjectSetInteger(nqvVisualChart, name, OBJPROP_BGCOLOR,     (long)bg);
    ObjectSetInteger(nqvVisualChart, name, OBJPROP_COLOR,       (long)bdr);
    ObjectSetInteger(nqvVisualChart, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
}

void NQPPanelLbl(string name, int x, int y, string text, int fs, color clr)
{
    if(ObjectFind(nqvVisualChart, name) < 0)
    {
        ObjectCreate(nqvVisualChart, name, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(nqvVisualChart, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
        ObjectSetInteger(nqvVisualChart, name, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(nqvVisualChart, name, OBJPROP_HIDDEN,     true);
        ObjectSetInteger(nqvVisualChart, name, OBJPROP_BACK,       false);
        ObjectSetString(nqvVisualChart,  name, OBJPROP_FONT,       "Segoe UI Semibold");
    }
    ObjectSetInteger(nqvVisualChart, name, OBJPROP_ZORDER,     10001);
    if((int)ObjectGetInteger(nqvVisualChart, name, OBJPROP_XDISTANCE) != x) ObjectSetInteger(nqvVisualChart, name, OBJPROP_XDISTANCE, x);
    if((int)ObjectGetInteger(nqvVisualChart, name, OBJPROP_YDISTANCE) != y) ObjectSetInteger(nqvVisualChart, name, OBJPROP_YDISTANCE, y);
    if((int)ObjectGetInteger(nqvVisualChart, name, OBJPROP_FONTSIZE)  != fs) ObjectSetInteger(nqvVisualChart, name, OBJPROP_FONTSIZE, fs);
    if(ObjectGetInteger(nqvVisualChart, name, OBJPROP_COLOR) != (long)clr) ObjectSetInteger(nqvVisualChart, name, OBJPROP_COLOR, (long)clr);
    if(ObjectGetString(nqvVisualChart, name, OBJPROP_TEXT) != text) ObjectSetString(nqvVisualChart, name, OBJPROP_TEXT, text);
}

void NQPPanelShell()
{
    if(!NQPVisualEnabled()) return;
    int height=nqpPanelCollapsed ? HH : PH;
    NQPPanelRect(NQPPanelPrefix()+"SHD2", PX+5, PY+5, PW, height, C'6,6,6',    C'6,6,6');
    NQPPanelRect(NQPPanelPrefix()+"SHD1", PX+2, PY+2, PW, height, C'12,12,12', C'12,12,12');
    NQPPanelRect(NQPPanelPrefix()+"BG",   PX,   PY,   PW, height, clrBlack,    C'52,68,92');
    NQPPanelRect(NQPPanelPrefix()+"HDR",  PX,   PY,   PW, HH, C'18,22,28', C'52,68,92');
    NQPPanelRect(NQPPanelPrefix()+"HAIR", PX,   PY+HH, PW, 1, C'52,68,92', C'52,68,92');
    NQPPanelLbl(NQPPanelPrefix()+"TTL",   PX+8, PY+8, "NQ Precision", 9, C'190,210,236');
    string button=NQPPanelPrefix()+"BTN";
    if(ObjectFind(nqvVisualChart,button)<0)
    {
        ObjectCreate(nqvVisualChart,button,OBJ_BUTTON,0,0,0);
        ObjectSetInteger(nqvVisualChart,button,OBJPROP_CORNER,CORNER_LEFT_UPPER);
        ObjectSetInteger(nqvVisualChart,button,OBJPROP_HIDDEN,true);
        ObjectSetString(nqvVisualChart,button,OBJPROP_FONT,"Segoe UI Semibold");
    }
    ObjectSetInteger(nqvVisualChart,button,OBJPROP_XDISTANCE,PX+PW-29);
    ObjectSetInteger(nqvVisualChart,button,OBJPROP_ZORDER,10002);
    ObjectSetInteger(nqvVisualChart,button,OBJPROP_YDISTANCE,PY+5);
    ObjectSetInteger(nqvVisualChart,button,OBJPROP_XSIZE,22);
    ObjectSetInteger(nqvVisualChart,button,OBJPROP_YSIZE,22);
    ObjectSetInteger(nqvVisualChart,button,OBJPROP_FONTSIZE,12);
    ObjectSetInteger(nqvVisualChart,button,OBJPROP_COLOR,(long)C'190,210,236');
    ObjectSetInteger(nqvVisualChart,button,OBJPROP_BGCOLOR,(long)C'18,22,28');
    ObjectSetInteger(nqvVisualChart,button,OBJPROP_BORDER_COLOR,(long)C'52,68,92');
    ObjectSetInteger(nqvVisualChart,button,OBJPROP_STATE,false);
    ObjectSetString(nqvVisualChart,button,OBJPROP_TEXT,nqpPanelCollapsed ? "+" : "-");
    if(nqpPanelCollapsed)
    {
        string rows[]={"SRV","HI","LO","SZ","BUY","SEL","CST","COV","SL"};
        for(int i=0;i<ArraySize(rows);i++) ObjectDelete(nqvVisualChart,NQPPanelPrefix()+rows[i]);
    }
}

void NQPPanelRows(datetime clock,string state,double adx,double nub)
{
   if(nqpPanelRestack){nqpPanelRestack=false;ObjectsDeleteAll(nqvVisualChart,NQPPanelPrefix());}
   NQPPanelShell();
   if(nqpPanelCollapsed)return;
   string p=NQPPanelPrefix();
   NQPPanelLbl(p+"SRV",PX+8,PY+40,clockReady ? "NY: "+TimeToString(NQPNewYork(clock),TIME_SECONDS)+" CT: "+TimeToString(NQPCentral(clock),TIME_SECONDS) : "Clock history loading",8,C'140,158,185');
   NQPPanelLbl(p+"HI",PX+8,PY+59,"Range high: "+(orHigh>0?DoubleToString(orHigh,_Digits):"--"),8,C'120,210,150');
   NQPPanelLbl(p+"LO",PX+8,PY+76,"Range low: "+(orLow>0?DoubleToString(orLow,_Digits):"--"),8,C'210,100,100');
   NQPPanelLbl(p+"SZ",PX+8,PY+93,"ATR: "+DoubleToString(m_atr,2)+" RVOL: "+DoubleToString(m_rvol,2),8,C'140,158,185');
   NQPPanelLbl(p+"BUY",PX+8,PY+112,"Trades "+IntegerToString(entries)+"/1",8,C'120,210,150');
   NQPPanelLbl(p+"SEL",PX+112,PY+112,OwnPosition() ? (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY ? "Position: long" : "Position: short") : "Position: flat",8,C'210,100,100');
   NQPPanelLbl(p+"CST",PX+8,PY+132,StringFormat("Comm/lot: $%.2f | Slip: %dp",NQPCommissionEstimate(),SlippagePoints),8,C'140,200,240');
   NQPPanelLbl(p+"COV",PX+8,PY+149,StringFormat("ATR SL/TP: %.2f / %.2f",InpAtrSlMult,InpAtrTpMult),8,C'190,180,120');
   string display=NQPSizingLabel()+" | "+state;
   NQPPanelLbl(p+"SL",PX+8,PY+166,StringSubstr(display,0,31),8,C'200,70,70');
   ObjectSetString(nqvVisualChart,p+"SL",OBJPROP_TOOLTIP,display);
}
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(!NQPVisualEnabled())return;
   if(id==CHARTEVENT_OBJECT_CREATE && StringFind(sparam,NQPPanelPrefix())!=0)
   {nqpPanelRestack=true;return;}
   if(id==CHARTEVENT_OBJECT_CLICK && sparam==NQPPanelPrefix()+"BTN")
   {nqpPanelCollapsed=!nqpPanelCollapsed;NQPDraw();ChartRedraw(nqvVisualChart);}
}


datetime NQPHistoryFloor=0,NQPHistoryRendered=0;
bool nqpBrokerVisualDirty=true;
bool nqpBrokerVisualInitialized=false;
datetime nqpVirtualExitTime=0;
struct NQPBrokerView
{
   ulong id;int side;datetime entered,exited;double entryValue,volume,exitValue,exitVolume,stop;bool mixed;
};
NQPBrokerView nqpBrokerView[];
struct NQPRangeView {datetime day,left,right;double high,low;};
NQPRangeView nqpRangeViews[];
datetime nqpRangeCheckedMinute=0;
struct NQPReplayTrade
{
   datetime day,attempt,entered,exited;int side;
   bool decided,pending,filled,closed,timePending,finished;
   double entry,stop,target,exit;
};
NQPReplayTrade nqpReplayTrades[2];
string nqpReplayStatus="";
bool NQPSetupContains(datetime at)
{
   for(int i=0;i<ArraySize(nqpRangeViews);i++)
      if(NQPDay(at)==nqpRangeViews[i].day)return true;
   return false;
}
// Series shifts run backwards: two bars right of entry means entryShift-2.
int NQPExecutionRightShift(int entryShift,int eventShift,bool closed)
{
   return MathMin(entryShift-2,eventShift-(closed?0:1));
}
datetime NQPExecutionRight(datetime entered,datetime exited,datetime now)
{
   ENUM_TIMEFRAMES view=(ENUM_TIMEFRAMES)ChartPeriod(nqvVisualChart);
   string symbol=ChartSymbol(nqvVisualChart);
   int entryShift=iBarShift(symbol,view,entered,false);
   int eventShift=iBarShift(symbol,view,exited>0?exited:now,false);
   int seconds=MathMax(1,PeriodSeconds(view));
   if(entryShift<0 || eventShift<0)return entered+2*seconds;
   int rightShift=NQPExecutionRightShift(entryShift,eventShift,exited>0);
   if(rightShift>=0)return iTime(symbol,view,rightShift);
   datetime latest=iTime(symbol,view,0);
   if(view==PERIOD_MN1)
   {
      MqlDateTime calendar;TimeToStruct(latest,calendar);
      int month=calendar.mon-1-rightShift;
      calendar.year+=month/12;calendar.mon=month%12+1;
      return StructToTime(calendar);
   }
   return latest-rightShift*seconds;
}
void NQPTradeBox(string key,datetime left,datetime right,double entry,double edge,color ink)
{
   if(!NQPVisualDataEnabled())return;
   string id=NQPVisualPrefix()+key;
   if(right<=left)right=left+1;
   if(ObjectFind(nqvVisualChart,id)<0)ObjectCreate(nqvVisualChart,id,OBJ_RECTANGLE,0,left,entry,right,edge);
   ObjectMove(nqvVisualChart,id,0,left,entry);ObjectMove(nqvVisualChart,id,1,right,edge);
   ObjectSetInteger(nqvVisualChart,id,OBJPROP_COLOR,ink);
   ObjectSetInteger(nqvVisualChart,id,OBJPROP_FILL,false);
   ObjectSetInteger(nqvVisualChart,id,OBJPROP_WIDTH,2);
   ObjectSetInteger(nqvVisualChart,id,OBJPROP_BACK,false);
   ObjectSetInteger(nqvVisualChart,id,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(nqvVisualChart,id,OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS);
   ObjectSetString(nqvVisualChart,id,OBJPROP_TOOLTIP,"NQ Precision | "+(StringFind(key,"Replay ")==0?"Historical tick simulation (no broker order) | ":"Broker execution | ")+key);
}
void NQPPaintBrokerTrades(datetime now)
{
   bool rebuild=nqpBrokerVisualDirty;
   if(rebuild)
   {
      if(ArraySize(nqpRangeViews)==0)return;
      datetime begin=nqpRangeViews[ArraySize(nqpRangeViews)-1].left;
      if(!HistorySelect(begin,now))return;
      nqpBrokerVisualInitialized=true;
      ArrayResize(nqpBrokerView,0);
      // Retire average-price arrows from earlier builds; exact deal tickets replace them.
      ObjectsDeleteAll(nqvVisualChart,NQPVisualPrefix()+"Entry_");
      ObjectsDeleteAll(nqvVisualChart,NQPVisualPrefix()+"Exit_");
      ObjectsDeleteAll(nqvVisualChart,NQPVisualPrefix()+"Broker ");
      ObjectsDeleteAll(nqvVisualChart,NQPVisualPrefix()+"Deal ");
      for(int i=0;i<HistoryDealsTotal();i++)
      {
         ulong d=HistoryDealGetTicket(i);
         if(HistoryDealGetString(d,DEAL_SYMBOL)!=_Symbol)continue;
         long kind=HistoryDealGetInteger(d,DEAL_ENTRY);
         ulong id=(ulong)HistoryDealGetInteger(d,DEAL_POSITION_ID);int k=-1;
         for(int j=0;j<ArraySize(nqpBrokerView);j++)if(nqpBrokerView[j].id==id){k=j;break;}
         if(kind==DEAL_ENTRY_IN)
         {
            if((ulong)HistoryDealGetInteger(d,DEAL_MAGIC)!=Magic)continue;
            if(!NQPSetupContains((datetime)HistoryDealGetInteger(d,DEAL_TIME)))continue;
            if(k<0){k=ArraySize(nqpBrokerView);ArrayResize(nqpBrokerView,k+1);ZeroMemory(nqpBrokerView[k]);nqpBrokerView[k].id=id;nqpBrokerView[k].entered=(datetime)HistoryDealGetInteger(d,DEAL_TIME);}
            double qty=HistoryDealGetDouble(d,DEAL_VOLUME);
            nqpBrokerView[k].side=HistoryDealGetInteger(d,DEAL_TYPE)==DEAL_TYPE_BUY?1:-1;
            nqpBrokerView[k].entryValue+=qty*HistoryDealGetDouble(d,DEAL_PRICE);nqpBrokerView[k].volume+=qty;
            ulong order=(ulong)HistoryDealGetInteger(d,DEAL_ORDER);
            double sl=HistoryOrderGetDouble(order,ORDER_SL);if(sl>0)nqpBrokerView[k].stop=sl;
         }
         else if(k>=0 && (kind==DEAL_ENTRY_OUT || kind==DEAL_ENTRY_OUT_BY))
         {
            double qty=HistoryDealGetDouble(d,DEAL_VOLUME);
            nqpBrokerView[k].exitValue+=qty*HistoryDealGetDouble(d,DEAL_PRICE);nqpBrokerView[k].exitVolume+=qty;
            nqpBrokerView[k].exited=(datetime)HistoryDealGetInteger(d,DEAL_TIME);
         }
      }
      // Shared/netting positions with mixed opening ownership or reversals are not attributed.
      for(int i=0;i<HistoryDealsTotal();i++){
         ulong deal=HistoryDealGetTicket(i);long kind=HistoryDealGetInteger(deal,DEAL_ENTRY);
         if(kind!=DEAL_ENTRY_IN && kind!=DEAL_ENTRY_INOUT)continue;
         ulong id=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
         for(int k=0;k<ArraySize(nqpBrokerView);k++)if(nqpBrokerView[k].id==id
            && (kind==DEAL_ENTRY_INOUT || (ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=Magic))nqpBrokerView[k].mixed=true;
      }
      // Exact deal prices/timestamps, including partial fills and manual exits of owned positions.
      for(int i=0;i<HistoryDealsTotal();i++)
      {
         ulong deal=HistoryDealGetTicket(i);
         if(HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol)continue;
         ulong position=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
         bool owned=false;
         for(int k=0;k<ArraySize(nqpBrokerView);k++)if(nqpBrokerView[k].id==position && !nqpBrokerView[k].mixed){owned=true;break;}
         datetime at=(datetime)HistoryDealGetInteger(deal,DEAL_TIME);
         long type=HistoryDealGetInteger(deal,DEAL_TYPE);
         if(!owned || at<NQPHistoryFloor || (type!=DEAL_TYPE_BUY && type!=DEAL_TYPE_SELL))continue;
         NQPDrawFill(type==DEAL_TYPE_BUY?1:-1,at,HistoryDealGetDouble(deal,DEAL_PRICE),"Deal "+IntegerToString((long)deal));
      }
      nqpBrokerVisualDirty=false;
   }
   for(int i=0;i<ArraySize(nqpBrokerView);i++)
   {
      if(nqpBrokerView[i].volume<=0 || nqpBrokerView[i].mixed)continue;
      double entry=nqpBrokerView[i].entryValue/nqpBrokerView[i].volume;
      bool closed=nqpBrokerView[i].exitVolume>=nqpBrokerView[i].volume-1e-8;
      if(closed && (!rebuild || nqpBrokerView[i].exited<NQPHistoryFloor))continue;
      datetime right=NQPExecutionRight(nqpBrokerView[i].entered,closed?nqpBrokerView[i].exited:0,now);
      double exit=closed?nqpBrokerView[i].exitValue/nqpBrokerView[i].exitVolume:0;
      double stop=nqpBrokerView[i].stop>0?nqpBrokerView[i].stop:0;
      // A closed losing trade still has a known realized loss area if its entry order lacked SL metadata.
      if(stop<=0 && closed && nqpBrokerView[i].side*(exit-entry)<0)stop=exit;
      // Keep original order SL as risk geometry; an exit fill is not the initial stop.
      string tag="Broker "+IntegerToString((long)nqpBrokerView[i].id);
      if(stop>0)NQPTradeBox(tag+" risk",nqpBrokerView[i].entered,right,entry,stop,C'55,57,68');
      NQPLine(tag+" entry",entry,C'214,218,224',STYLE_SOLID,nqpBrokerView[i].entered,right);
      if(closed && nqpBrokerView[i].side*(exit-entry)>0)NQPTradeBox(tag+" profit",nqpBrokerView[i].entered,right,entry,exit,C'22,55,120');
      // Per-deal arrows above are authoritative; averages only define the position box.
   }
}

void NQPDrawFill(int side,datetime time,double price,string label)
{
   if(!NQPVisualDataEnabled()) return;
   string id=NQPVisualPrefix()+label+"_"+IntegerToString((long)time);
   ObjectCreate(nqvVisualChart,id,side==1 ? OBJ_ARROW_BUY : OBJ_ARROW_SELL,0,time,price);
   ObjectSetString(nqvVisualChart,id,OBJPROP_TOOLTIP,NQPDisplayName+" | "+label+" "+TimeToString(time,TIME_DATE|TIME_SECONDS));
   ObjectSetInteger(nqvVisualChart,id,OBJPROP_COLOR,clrWhite);
   ObjectSetInteger(nqvVisualChart,id,OBJPROP_BACK,false);
   ObjectSetInteger(nqvVisualChart,id,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(nqvVisualChart,id,OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS);
}
void NQPLine(string key,double price,color ink,ENUM_LINE_STYLE style=STYLE_SOLID,datetime left=0,datetime right=0)
{
   if(!NQPVisualDataEnabled())return;
   string id=NQPVisualPrefix()+key;
   if(left==0)
   {
      left=NQPSessionTime(day);
      if(StringFind(key,"Opening range")==0) left+=510*60;
      else if(StringFind(key,"Synthetic")==0) left=virtualStart;
      else if(key=="Entry" || key=="Stop" || key=="Target")
         left=ownedEntryTime>0 ? ownedEntryTime : (datetime)PositionGetInteger(POSITION_TIME);
      else if(StringFind(key,"Last ")==0) left=nqvLastBracketTime;
   }
   if(right==0 && (key=="Entry" || key=="Stop" || key=="Target"))
      right=NQPExecutionRight(left,0,TimeCurrent());
   if(right==0 && StringFind(key,"Last ")==0)
   {
      for(int i=0;i<ArraySize(nqpBrokerView);i++)
         if(!nqpBrokerView[i].mixed && nqpBrokerView[i].entered==left && nqpBrokerView[i].volume>0
            && nqpBrokerView[i].exitVolume>=nqpBrokerView[i].volume-1e-8)
         {right=NQPExecutionRight(left,nqpBrokerView[i].exited,TimeCurrent());break;}
   }
   if(right==0) right=NQPSessionTime(day)+NQPSessionCutoff(NQPSessionTime(day))*60;
   if(left<=0 || right<=left || price<=0) {ObjectDelete(nqvVisualChart,id);return;}
   if(ObjectFind(nqvVisualChart,id)>=0 && ObjectGetInteger(nqvVisualChart,id,OBJPROP_TYPE)!=OBJ_TREND)
      ObjectDelete(nqvVisualChart,id);
   if(ObjectFind(nqvVisualChart,id)<0) ObjectCreate(nqvVisualChart,id,OBJ_TREND,0,left,price,right,price);
   ObjectMove(nqvVisualChart,id,0,left,price);ObjectMove(nqvVisualChart,id,1,right,price);
   ObjectSetInteger(nqvVisualChart,id,OBJPROP_RAY_LEFT,false);ObjectSetInteger(nqvVisualChart,id,OBJPROP_RAY_RIGHT,false);
   ObjectSetInteger(nqvVisualChart,id,OBJPROP_COLOR,ink);ObjectSetInteger(nqvVisualChart,id,OBJPROP_STYLE,style);
   ObjectSetInteger(nqvVisualChart,id,OBJPROP_BACK,StringFind(key,"Broker ")!=0 && StringFind(key,"Replay ")!=0);
   ObjectSetInteger(nqvVisualChart,id,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(nqvVisualChart,id,OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS);
   ObjectSetString(nqvVisualChart,id,OBJPROP_TEXT,key);
   ObjectSetString(nqvVisualChart,id,OBJPROP_TOOLTIP,NQPDisplayName+" | "+key+" | "+DoubleToString(price,_Digits)
      +" | "+TimeToString(left,TIME_DATE|TIME_MINUTES)+" to "+TimeToString(right,TIME_MINUTES)+" (broker time)");
}

void NQPHistoryLine(string key,datetime left,double a,datetime right,double b,color ink)
{
   if(!NQPVisualDataEnabled() || right<=left || a<=0 || b<=0)return;
   string id=NQPVisualPrefix()+"HISTORY_"+key;
   if(ObjectFind(nqvVisualChart,id)<0)ObjectCreate(nqvVisualChart,id,OBJ_TREND,0,left,a,right,b);
   ObjectMove(nqvVisualChart,id,0,left,a);ObjectMove(nqvVisualChart,id,1,right,b);
   ObjectSetInteger(nqvVisualChart,id,OBJPROP_COLOR,ink);ObjectSetInteger(nqvVisualChart,id,OBJPROP_WIDTH,1);
   ObjectSetInteger(nqvVisualChart,id,OBJPROP_STYLE,STYLE_DOT);ObjectSetInteger(nqvVisualChart,id,OBJPROP_BACK,true);
   ObjectSetInteger(nqvVisualChart,id,OBJPROP_SELECTABLE,false);ObjectSetInteger(nqvVisualChart,id,OBJPROP_RAY_LEFT,false);
   ObjectSetInteger(nqvVisualChart,id,OBJPROP_RAY_RIGHT,false);ObjectSetInteger(nqvVisualChart,id,OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS);
   ObjectSetString(nqvVisualChart,id,OBJPROP_TOOLTIP,"Source-bar session history | "+key);
}
void NQPRangeBox(const NQPRangeView &range)
{
   string key="Range "+IntegerToString((long)range.day),id=NQPVisualPrefix()+key;
   if(!NQPVisualDataEnabled() || range.high<range.low || range.right<=range.left)return;
   if(ObjectFind(nqvVisualChart,id)<0)ObjectCreate(nqvVisualChart,id,OBJ_RECTANGLE,0,range.left,range.high,range.right,range.low);
   ObjectMove(nqvVisualChart,id,0,range.left,range.high);ObjectMove(nqvVisualChart,id,1,range.right,range.low);
   ObjectSetInteger(nqvVisualChart,id,OBJPROP_COLOR,C'25,35,45');
   ObjectSetInteger(nqvVisualChart,id,OBJPROP_FILL,true);
   ObjectSetInteger(nqvVisualChart,id,OBJPROP_BACK,true);
   ObjectSetInteger(nqvVisualChart,id,OBJPROP_ZORDER,0);
   ObjectSetInteger(nqvVisualChart,id,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(nqvVisualChart,id,OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS);
   // Match NT8's bounded range-reference horizon; convert NY clock to broker time first.
   int clock=InpUseTriggerTime?InpTriggerTime:InpTradeUntil;
   datetime sessionEnd=NQPSessionTime(range.day,clock/10000*60+clock/100%100-60)+clock%100+(InpCloseAfterMin+2)*60;
   NQPLine(key+" high",range.high,C'214,218,224',STYLE_DOT,range.left,sessionEnd);
   NQPLine(key+" low",range.low,C'214,218,224',STYLE_DOT,range.left,sessionEnd);
}
// Read-only historical visualization. Never calls Open/CloseOwned or changes runtime state.
void NQPVisitReplayTick(NQPReplayTrade &t,const MqlTick &q,double atr,bool filters,double high,double low)
{
   datetime at=(datetime)(q.time_msc/1000);
   if(t.closed)return;
   double signal=nqTradeData?q.last:q.bid;
   double execution=t.side>0?q.bid:q.ask;
   if(t.filled && execution>0)
   {
      bool stop=t.side>0?execution<=t.stop:execution>=t.stop;
      bool target=t.side>0?execution>=t.target:execution<=t.target;
      if(stop || target)
      {
         t.closed=true;t.exited=at;
         t.exit=target?t.target:execution;
         return;
      }
   }
   if(!NQStrategyEvent(q.flags,nqTradeData))return;
   if(t.filled && t.timePending && execution>0)
   {t.closed=true;t.exited=at;t.exit=execution;return;}
   if(t.pending)
   {
      double entry=t.side>0?q.ask:q.bid;
      if(entry<=0)return;
      if(!NQPBracket(t.side,entry,t.stop,t.target)){t.pending=false;return;}
      t.pending=false;t.filled=true;t.entry=entry;t.entered=at;
      return;
   }
   if(t.filled)
   {
      if(InpUseTimeClose && at>=t.entered+InpCloseAfterMin*60)t.timePending=true;
      return;
   }
   if(t.decided || signal<=0)return;
   int clock=GetEtHHMMSS(at);
   bool window=InpUseTriggerTime?clock>=InpTriggerTime:clock>=InpRangeEnd && clock<=InpTradeUntil;
   if(!window)return;
   int side=signal>high?1:signal<low?-1:0;
   if(InpUseTriggerTime)t.decided=true;
   if(side==0 || !filters || atr<=0)return;
   double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tick<=0)return;
   t.side=side;t.decided=true;t.pending=true;
   t.stop=NQCrossing(signal-side*InpAtrSlMult*atr,tick,side<0);
   t.target=NQCrossing(signal+side*InpAtrTpMult*atr,tick,side>0);
}
MqlRates nqpTickReplayBars[];
NQTickMinuteState nqpTickReplayMinute;
datetime nqpTickReplayCursor=0,nqpTickReplayRetryAfter=0;
bool NQPReplayTickBars(const datetime now,MqlRates &bars[])
{
   datetime through=now-now%60;
   if(now<nqpTickReplayRetryAfter)return false;
   if(nqpTickReplayCursor==0)
   {
      nqpTickReplayCursor=NQTickHistoryAnchor(through);
      if(nqpTickReplayCursor==0){nqpTickReplayRetryAfter=now+1;return false;}
   }
   // Independent read-only cache, shared by the two historical setup slots.
   for(int budget=0;budget<4 && nqpTickReplayCursor<through;budget++)
   {
      datetime end=(datetime)MathMin((double)through,(double)nqpTickReplayCursor+3600);
      MqlRates completed[];
      if(!NQReadTickMinutes(nqpTickReplayCursor,end,nqpTickReplayMinute,completed))
      {nqpTickReplayRetryAfter=now+1;return false;}
      int n=ArraySize(nqpTickReplayBars),added=ArraySize(completed);
      if(added>0)
      {
         ArrayResize(nqpTickReplayBars,n+added,1024);ArrayCopy(nqpTickReplayBars,completed,n,0,added);
         if(ArraySize(nqpTickReplayBars)>10000)ArrayRemove(nqpTickReplayBars,0,ArraySize(nqpTickReplayBars)-10000);
      }
      nqpTickReplayCursor=end;
   }
   if(nqpTickReplayCursor<through)return false;
   ArrayCopy(bars,nqpTickReplayBars);
   return true;
}
void NQPReplaySetup(NQPReplayTrade &t,const NQPRangeView &range,datetime now)
{
   datetime trigger=NQPSessionTime(range.day,InpTriggerTime/10000*60+InpTriggerTime/100%100-60)+InpTriggerTime%100;
   datetime start=InpUseTriggerTime?trigger:range.left+NQRequiredRangeBars()*60;
   if(now<start || range.right<range.left+NQRequiredRangeBars()*60)return;
   datetime minute=now-now%60;
   if(t.finished || t.attempt==minute)return;
   t.attempt=minute;
   // The selected source matches the live engine; filter state stays local to this replay.
   MqlRates bars[];ArraySetAsSeries(bars,false);
   int count=0;
   if(InpUseTickHistory)
   {
      if(!NQPReplayTickBars(now,bars))
      {t.attempt=0;nqpReplayStatus="Historical visuals: tick-minute history warming or unavailable";return;}
      count=ArraySize(bars);
   }
   else count=CopyRates(_Symbol,PERIOD_M1,now,10000,bars);
   if(count<MathMax(InpAtrPeriod,InpAtrRegimeLen) || bars[0].time>=start)
   {nqpReplayStatus=InpUseTickHistory?"Historical visuals: tick-minute warmup unavailable":"Historical visuals: M1 warmup unavailable";return;}
   double rangeHigh=range.high,rangeLow=range.low;
   if(InpUseTickHistory)
   {
      int rangeBars=0;
      for(int i=0;i<count;i++)if(bars[i].time>=range.left && bars[i].time<range.left+NQRequiredRangeBars()*60)
      {
         rangeHigh=rangeBars==0?bars[i].high:MathMax(rangeHigh,bars[i].high);
         rangeLow=rangeBars==0?bars[i].low:MathMin(rangeLow,bars[i].low);rangeBars++;
      }
      if(rangeBars<NQRequiredRangeBars()){nqpReplayStatus="Historical visuals: tick opening range incomplete";return;}
   }
   NQPReplayTrade replay;ZeroMemory(replay);replay.day=range.day;replay.attempt=minute;
   double atr=0,longAtr=0,previous=0,sum=0,rvol=0;
   int n=0,index=0,volumeDay=0,head=0,used=0;
   double ring[];ArrayResize(ring,InpRvolLen);ArrayInitialize(ring,0.0);
   datetime end=(datetime)MathMin((double)now,(double)NQPSessionTime(range.day,15*60));
   bool ticksSeen=false;
   for(datetime chunk=start;chunk<=end && !replay.closed;chunk+=60)
   {
      MqlTick ticks[];
      ulong until=(ulong)MathMin((double)end*1000+999,(double)(chunk+60)*1000-1);
      int available=CopyTicksRange(_Symbol,ticks,COPY_TICKS_ALL,(ulong)chunk*1000,until);
      if(available<0){nqpReplayStatus="Historical visuals: ticks unavailable";return;}
      for(int k=0;k<available && !replay.closed;k++)
      {
         datetime at=(datetime)(ticks[k].time_msc/1000);ticksSeen=true;
         while(index<count && bars[index].time+60<=at)
         {
            int date=GetEtDateNum(bars[index].time);
            if(date!=volumeDay){volumeDay=date;head=used=0;sum=0;ArrayInitialize(ring,0.0);}
            double tr=bars[index].high-bars[index].low;
            if(n>0)tr=MathMax(tr,MathMax(MathAbs(bars[index].high-previous),MathAbs(bars[index].low-previous)));
            n++;atr=NQWilder(atr,tr,n,InpAtrPeriod);longAtr=NQWilder(longAtr,tr,n,InpAtrRegimeLen);
            previous=bars[index].close;
            double volume=(double)(nqTradeData?bars[index].real_volume:bars[index].tick_volume);
            sum-=ring[head];ring[head]=volume;sum+=volume;
            head=(head+1)%InpRvolLen;used=(int)MathMin(used+1,InpRvolLen);
            rvol=used==InpRvolLen && sum>0?volume*InpRvolLen/sum:0;
            index++;
         }
         bool filters=n>=MathMax(InpAtrPeriod,InpAtrRegimeLen) && atr>0 && longAtr>0;
         if(InpUseFilters)filters=filters && used>=InpRvolLen && rvol>=InpRvolMin && rvol<=InpRvolMax
            && atr/longAtr>=InpRegimeMin && atr/longAtr<=InpRegimeMax;
         NQPVisitReplayTick(replay,ticks[k],atr,filters,rangeHigh,rangeLow);
         if(replay.decided && !replay.pending && !replay.filled)break;
      }
      if(replay.decided && !replay.pending && !replay.filled)break;
   }
   if(!ticksSeen){nqpReplayStatus="Historical visuals: no tick history";return;}
   replay.finished=replay.closed || (replay.decided && !replay.pending && !replay.filled) || now>=NQPSessionTime(range.day,15*60);
   t=replay;
   if(!t.filled)nqpReplayStatus=t.decided?"Historical setup: no qualifying signal":"Historical setup: waiting for trigger";
}
void NQPPaintReplay(datetime now)
{
   if(!NQPVisualDataEnabled())return;
   nqpReplayStatus="";
   for(int slot=0;slot<ArraySize(nqpRangeViews);slot++)
   {
      NQPRangeView range=nqpRangeViews[slot];
      if(nqpReplayTrades[slot].day!=range.day){ZeroMemory(nqpReplayTrades[slot]);nqpReplayTrades[slot].day=range.day;}
      string tag="Replay "+IntegerToString((long)range.day);
      bool broker=false;
      for(int i=0;i<ArraySize(nqpBrokerView);i++)if(!nqpBrokerView[i].mixed && NQPDay(nqpBrokerView[i].entered)==range.day)broker=true;
      if(broker){ObjectsDeleteAll(nqvVisualChart,NQPVisualPrefix()+tag);continue;}
      NQPReplaySetup(nqpReplayTrades[slot],range,now);
      NQPReplayTrade t=nqpReplayTrades[slot];
      if(!t.filled)continue;
      datetime viewedThrough=(datetime)MathMin((double)now,(double)NQPSessionTime(range.day,15*60));
      datetime right=NQPExecutionRight(t.entered,t.closed?t.exited:0,viewedThrough);
      NQPTradeBox(tag+" risk",t.entered,right,t.entry,t.stop,C'55,57,68');
      NQPLine(tag+" entry",t.entry,C'214,218,224',STYLE_DASH,t.entered,right);
      if(t.closed && t.side*(t.exit-t.entry)>0)NQPTradeBox(tag+" profit",t.entered,right,t.entry,t.exit,C'22,55,120');
      NQPDrawFill(t.side,t.entered,t.entry,tag+" simulated entry");
      if(t.closed)NQPDrawFill(-t.side,t.exited,t.exit,tag+" simulated exit");
   }
}
bool NQPRangeBounds(const MqlRates &bars[],datetime left,datetime right,bool forming,double &high,double &low)
{
   int count=ArraySize(bars),expected=(int)((right-left)/60);
   if(count<=0 || count!=expected || (!forming && count!=NQRequiredRangeBars()))return false;
   high=bars[0].high;low=bars[0].low;
   for(int i=0;i<count;i++)
   {
      if(bars[i].time!=left+i*60)return false;
      high=MathMax(high,bars[i].high);low=MathMin(low,bars[i].low);
   }
   return true;
}
void NQPHistoricalSessions(datetime now)
{
   if(!NQPVisualDataEnabled() || !clockReady)return;
   datetime minute=now-now%60;
   if(nqpRangeCheckedMinute==minute)return;
   MqlRates tickBars[];
   if(InpUseTickHistory && !NQPReplayTickBars(now,tickBars))return;
   nqpRangeCheckedMinute=minute;
   datetime previous[2]={0,0};
   for(int i=0;i<ArraySize(nqpRangeViews);i++)previous[i]=nqpRangeViews[i].day;
   ArrayResize(nqpRangeViews,0);
   int startMinute=InpRangeStart/10000*60+InpRangeStart/100%100-60;
   int endMinute=InpRangeEnd/10000*60+InpRangeEnd/100%100-60;
   datetime today=NQPDay(now);
   // Fixed safety bound: stop as soon as two valid sessions have been found.
   // A contiguous forming current session counts as the newest displayed setup.
   for(int back=0;back<32 && ArraySize(nqpRangeViews)<2;back++)
   {
      datetime date=today-back*86400;
      datetime left=NQPSessionTime(date,startMinute)+InpRangeStart%100;
      datetime finish=NQPSessionTime(date,endMinute)+InpRangeEnd%100;
      datetime right=(datetime)MathMin((double)minute,(double)finish);
      if(left<=0 || right<=left)continue;
      MqlRates bars[];ArraySetAsSeries(bars,false);
      int count=0;
      if(InpUseTickHistory)
      {
         for(int i=0;i<ArraySize(tickBars);i++)if(tickBars[i].time>=left && tickBars[i].time<right)
         {ArrayResize(bars,count+1);bars[count++]=tickBars[i];}
      }
      else count=CopyRates(_Symbol,PERIOD_M1,left,right-1,bars);
      double high=0,low=0;
      if(count<=0 || !NQPRangeBounds(bars,left,right,date==today && right<finish,high,low))continue;
      int k=ArraySize(nqpRangeViews);ArrayResize(nqpRangeViews,k+1);
      nqpRangeViews[k].day=date;nqpRangeViews[k].left=left;nqpRangeViews[k].right=right;
      nqpRangeViews[k].high=high;nqpRangeViews[k].low=low;
   }
   bool changed=false;
   for(int i=0;i<2;i++)if(previous[i]!=(i<ArraySize(nqpRangeViews)?nqpRangeViews[i].day:0))changed=true;
   if(changed)
   {
      ObjectsDeleteAll(nqvVisualChart,NQPVisualPrefix()+"Range ");
      ObjectsDeleteAll(nqvVisualChart,NQPVisualPrefix()+"Replay ");
      nqpBrokerVisualDirty=true;
      if(ArraySize(nqpRangeViews)==0)
      {
         ObjectsDeleteAll(nqvVisualChart,NQPVisualPrefix()+"Broker ");
         ObjectsDeleteAll(nqvVisualChart,NQPVisualPrefix()+"Deal ");
         ArrayResize(nqpBrokerView,0);
      }
   }
   for(int i=0;i<ArraySize(nqpRangeViews);i++)NQPRangeBox(nqpRangeViews[i]);
   ChartRedraw(nqvVisualChart);
}
void NQPDraw()
{
   if(!NQPVisualEnabled())return;
   string fault=NQPVisualFault();
   NQPVisualSuspend(fault!="");
   if(fault!="")
   {
      datetime now=MQLInfoInteger(MQL_TESTER)?TimeCurrent():TimeTradeServer();
      NQPPanelRows(now,fault,0,0);
      ChartRedraw(nqvVisualChart);return;
   }
   NQPHistoricalSessions(TimeCurrent());
   if(!NQPVisualEnabled()) return;
   string p=NQPVisualPrefix();
   if(dayValid && day==NQPVisualDay(TimeCurrent()))
   {

      if(rangeReady)
      {
         ObjectDelete(nqvVisualChart,p+"Opening range high");
         ObjectDelete(nqvVisualChart,p+"Opening range low");




      }
   }
   string state=virtualActive ? "Synthetic first trade: waiting for TP / SL" : "Waiting for NQ trigger snapshot";
   if(virtualActive || nqpVirtualExitTime>virtualStart)
   {
      datetime end=virtualActive?NQPSessionTime(day)+NQPSessionCutoff(NQPSessionTime(day))*60:nqpVirtualExitTime;
      NQPLine("Synthetic entry",virtualStop+StopPoints,clrSlateGray,STYLE_DASH,virtualStart,end);
      NQPLine("Synthetic SL",virtualStop,clrTomato,STYLE_DASH,virtualStart,end);
      NQPLine("Synthetic TP",virtualTarget,clrLimeGreen,STYLE_DASH,virtualStart,end);
   }
   else {ObjectDelete(nqvVisualChart,p+"Synthetic entry");ObjectDelete(nqvVisualChart,p+"Synthetic SL");ObjectDelete(nqvVisualChart,p+"Synthetic TP");}
   if(OwnPosition())
   {
      state="Broker position protected";
      NQPRememberBracket(PositionGetDouble(POSITION_PRICE_OPEN),PositionGetDouble(POSITION_SL),PositionGetDouble(POSITION_TP));
      NQPLine("Entry",PositionGetDouble(POSITION_PRICE_OPEN),clrWhite,STYLE_DOT);
      NQPLine("Stop",PositionGetDouble(POSITION_SL),clrTomato);
      NQPLine("Target",PositionGetDouble(POSITION_TP),clrLimeGreen);
   }
   else {ObjectDelete(nqvVisualChart,p+"Entry");ObjectDelete(nqvVisualChart,p+"Stop");ObjectDelete(nqvVisualChart,p+"Target");}
   if(!OwnPosition() && nqvLastEntry>0 && NQPSetupContains(nqvLastBracketTime))
   {
      NQPLine("Last entry (reference)",nqvLastEntry,clrWhite,STYLE_DOT);
      NQPLine("Last stop (reference)",nqvLastStop,clrTomato,STYLE_DASH);
      NQPLine("Last target (reference)",nqvLastTarget,clrLimeGreen,STYLE_DASH);
   }
   else
   {
      ObjectDelete(nqvVisualChart,p+"Last entry (reference)");ObjectDelete(nqvVisualChart,p+"Last stop (reference)");ObjectDelete(nqvVisualChart,p+"Last target (reference)");
   }
   double a[];ArraySetAsSeries(a,true);double adx=0;
   if(CopyBuffer(adxHandle,0,1,1,a)==1) adx=a[0];
   if(!dayValid) state="Waiting for session history / indicators";
   if(day!=NQPVisualDay(TimeCurrent()) || (!dayValid && NQPMinute(TimeCurrent())<1)) state="Session forming | waiting for completed source data";
   if(!MQLInfoInteger(MQL_TESTER) && !runtimeHistoryReady) state="Loading history | new entries blocked | protection active";
   if(!EnableTrading) state="New trades disabled | existing trades remain protected";
   datetime clock=MQLInfoInteger(MQL_TESTER) ? TimeCurrent() : TimeTradeServer();
   if(!clockReady) state="Loading clock history | waiting for a verified session anchor";
   if(runtimeRecoveryHold) state="Recovery needs attention | broker SL/TP retained";
   if(runtimeCloseAttention) state="Close unconfirmed | no duplicate request";
   if(runtimeCloseRejected) state="Close rejected | retry paused";
   double nub=dayValid && day==NQPVisualDay(clock) ? midnight+NoiseFraction*averageATR : 0;
   string level=NQPVisualPrefix()+"Noise Up Barrier (NUB)";
   if(nub<=0 && ObjectFind(nqvVisualChart,level)>=0
      && (datetime)ObjectGetInteger(nqvVisualChart,level,OBJPROP_TIME,0)==NQPSessionTime(NQPVisualDay(clock)))
      nub=ObjectGetDouble(nqvVisualChart,level,OBJPROP_PRICE,0);
   NQPPaintBrokerTrades(clock);
   NQPPaintReplay(clock);
   if(nqpReplayStatus!="" && !OwnPosition())state=nqpReplayStatus;
   NQPPanelRows(clock,state,adx,nub);
   static datetime fittedBar=0;
   static double fittedStop=0,fittedTarget=0;
   datetime currentBar=iTime(_Symbol,sourceTF,0);
   double fitStop=virtualActive ? virtualStop : nqvLastStop,fitTarget=virtualActive ? virtualTarget : nqvLastTarget;
   if(currentBar>0 && (currentBar!=fittedBar || fitStop!=fittedStop || fitTarget!=fittedTarget))
   {
      NQPVisualFit();fittedBar=currentBar;fittedStop=fitStop;fittedTarget=fitTarget;
   }
   ChartRedraw(nqvVisualChart);
}
void NQPRefreshLiveVisuals(datetime now)
{ /* Portfolio timer retains broker-trade and panel refresh; signal state owns range levels. */ }

#endif
