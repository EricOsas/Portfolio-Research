#ifndef TOKYOCOIL_VISUAL_GEOMETRY_MQH
#define TOKYOCOIL_VISUAL_GEOMETRY_MQH
// ORB's containing-chart-bar convention, without accumulating -1 seconds.
datetime TcVisualBarEnd(datetime time,int seconds)
{
   if(time<=0 || seconds<=1) return time;
   return (datetime)((long)time/seconds*seconds+seconds-1);
}
datetime TcExecutionRight(datetime fill,datetime now,int seconds,datetime resolved)
{
   if(resolved>0) return resolved;
   seconds=MathMax(seconds,1);
   datetime initial=TcVisualBarEnd(fill,seconds)+3*seconds;
   datetime following=TcVisualBarEnd(now,seconds)+2*seconds;
   return MathMax(initial,following);
}
double TcExecutionLossEdge(int direction,double entry,double stop,double close,bool resolved)
{
   return resolved && direction*(close-entry)<=0?close:stop;
}
bool TcVisibleSession(datetime session,datetime today)
{
   return session>=today-2*86400 && session<=today;
}
// M1 hindsight inference is deliberately separate from native deal fills.
enum TC_REPLAY_STATE { TC_REPLAY_MISSING=-1,TC_REPLAY_NO_SIGNAL=0,TC_REPLAY_WAITING=1,TC_REPLAY_FILLED=2,TC_REPLAY_AMBIGUOUS=3 };
bool TcAllowLiveReplay(int state,datetime activeSince,datetime quote,datetime expiry)
{
   return state==TC_REPLAY_WAITING && quote>activeSince && quote<expiry;
}
// 2 means direction/order cannot be inferred safely from this candle.
int TcHindsightSide(double open,double high,double low,double spread,double buy,double sell,bool arming,double boxHigh,double boxLow)
{
   if(arming && open>boxHigh) return 1;
   if(arming && open<boxLow) return -1;
   if(open+spread>=buy) return 1;
   if(open<=sell) return -1;
   bool up=high+spread>=buy,down=low<=sell;
   if(up && down) return 2;
   return up?1:down?-1:0;
}
// ORB write-through guards: unchanged properties never enter the render queue.
int tcVisualWrites=0,tcVisualCreates=0,tcVisualDeletes=0;
void TcVisualInt(string name,ENUM_OBJECT_PROPERTY_INTEGER prop,long value,int modifier=0)
{
   if(ObjectGetInteger(0,name,prop,modifier)==value) return;
   if(ObjectSetInteger(0,name,prop,modifier,value)) tcVisualWrites++;
}
void TcVisualString(string name,ENUM_OBJECT_PROPERTY_STRING prop,string value)
{
   if(ObjectGetString(0,name,prop)==value) return;
   if(ObjectSetString(0,name,prop,value)) tcVisualWrites++;
}
void TcVisualPoint(string name,int index,datetime time,double price)
{
   if((datetime)ObjectGetInteger(0,name,OBJPROP_TIME,index)==time &&
      MathAbs(ObjectGetDouble(0,name,OBJPROP_PRICE,index)-price)<_Point*.5) return;
   if(ObjectMove(0,name,index,time,price)) tcVisualWrites++;
}
void TcVisualDelete(string name)
{
   if(ObjectFind(0,name)>=0 && ObjectDelete(0,name)) tcVisualDeletes++;
}
#endif

#ifndef TC_VISUAL_GEOMETRY_ONLY
// Stable foreground panel: no deletion/recreation when the chart scrolls.

string tcPanelPrefix="TC_RESEARCH_PANEL.";
bool tcPanelDirty=true,tcOldObjectEvents=false,tcOldForeground=false;
bool tcPanelStarted=false;
datetime tcPanelSecond=0;
int tcPanelTextWidth=0;
bool TcVisual() { return ShowPanel && (!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE)); }
void TcPanelDelete() { ObjectsDeleteAll(0,tcPanelPrefix); }
void TcPanelStart()
{
   if(!TcVisual()) return;
   tcOldObjectEvents=(bool)ChartGetInteger(0,CHART_EVENT_OBJECT_CREATE);
   tcOldForeground=(bool)ChartGetInteger(0,CHART_FOREGROUND);
   ChartSetInteger(0,CHART_EVENT_OBJECT_CREATE,true);
   ChartSetInteger(0,CHART_FOREGROUND,false);
   EventSetTimer(1);
   tcPanelStarted=true;
}
bool tcPanelCollapsed=false;
void TcPanelRect(string suffix,int x,int y,int width,int height,color bg,color border)
{
   string name=tcPanelPrefix+suffix;
   if(ObjectFind(0,name)<0)ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0);
   TcVisualInt(name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   TcVisualInt(name,OBJPROP_XDISTANCE,x);TcVisualInt(name,OBJPROP_YDISTANCE,y);
   TcVisualInt(name,OBJPROP_XSIZE,width);TcVisualInt(name,OBJPROP_YSIZE,height);
   TcVisualInt(name,OBJPROP_BGCOLOR,bg);TcVisualInt(name,OBJPROP_COLOR,border);
   TcVisualInt(name,OBJPROP_BORDER_TYPE,BORDER_FLAT);TcVisualInt(name,OBJPROP_ZORDER,10000);
   TcVisualInt(name,OBJPROP_BACK,false);TcVisualInt(name,OBJPROP_SELECTABLE,false);TcVisualInt(name,OBJPROP_HIDDEN,true);
}
void TcPanelLabel(string suffix,int x,int y,string text,int size,color ink)
{
   string name=tcPanelPrefix+suffix;
   if(ObjectFind(0,name)<0)ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   TcVisualInt(name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   TcVisualInt(name,OBJPROP_XDISTANCE,x);TcVisualInt(name,OBJPROP_YDISTANCE,y);
   TcVisualInt(name,OBJPROP_FONTSIZE,size);TcVisualInt(name,OBJPROP_COLOR,ink);
   TcVisualInt(name,OBJPROP_ZORDER,10001);TcVisualInt(name,OBJPROP_BACK,false);
   TcVisualInt(name,OBJPROP_SELECTABLE,false);TcVisualInt(name,OBJPROP_HIDDEN,true);
   TcVisualString(name,OBJPROP_FONT,"Segoe UI Semibold");TcVisualString(name,OBJPROP_TEXT,text);
}
void TcPanelRefresh()
{
   if(!TcVisual())return;
   datetime now=MQLInfoInteger(MQL_TESTER)?TimeCurrent():TimeTradeServer();
   if(now<=0)now=TimeCurrent();
   if(tcPanelSecond==now && !tcPanelDirty)return;
   tcPanelSecond=now;
   ulong writesBefore=tcVisualWrites;
   const int x=10,y=20,w=210,h=222,hh=32;
   int height=tcPanelCollapsed?hh:h;
   TcPanelRect("SHD2",x+5,y+5,w,height,C'6,6,6',C'6,6,6');
   TcPanelRect("SHD1",x+2,y+2,w,height,C'12,12,12',C'12,12,12');
   TcPanelRect("BG",x,y,w,height,clrBlack,C'52,68,92');
   TcPanelRect("HDR",x,y,w,hh,C'18,22,28',C'52,68,92');
   TcPanelRect("HAIR",x,y+hh,w,1,C'52,68,92',C'52,68,92');
   TcPanelLabel("TTL",x+8,y+8,"Tokyo Coil | "+_Symbol,9,C'190,210,236');
   string button=tcPanelPrefix+"BTN";
   if(ObjectFind(0,button)<0)ObjectCreate(0,button,OBJ_BUTTON,0,0,0);
   TcVisualInt(button,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   TcVisualInt(button,OBJPROP_XDISTANCE,x+w-29);TcVisualInt(button,OBJPROP_YDISTANCE,y+5);
   TcVisualInt(button,OBJPROP_XSIZE,22);TcVisualInt(button,OBJPROP_YSIZE,22);
   TcVisualInt(button,OBJPROP_FONTSIZE,12);TcVisualInt(button,OBJPROP_ZORDER,10002);
   TcVisualInt(button,OBJPROP_COLOR,C'190,210,236');TcVisualInt(button,OBJPROP_BGCOLOR,C'18,22,28');
   TcVisualInt(button,OBJPROP_BORDER_COLOR,C'52,68,92');TcVisualInt(button,OBJPROP_STATE,false);
   TcVisualInt(button,OBJPROP_HIDDEN,true);TcVisualString(button,OBJPROP_FONT,"Segoe UI Semibold");
   TcVisualString(button,OBJPROP_TEXT,tcPanelCollapsed?"+":"-");
   string rows[]={"SRV","CHART","HI","LO","SZ","BUY","SELL","POS","STOP","RISK","BRAKE","NEWS"};
   if(tcPanelCollapsed)
   {for(int i=0;i<ArraySize(rows);i++)TcVisualDelete(tcPanelPrefix+rows[i]);}
   else
   {
      datetime ny=TcServerToNY(now);double high=0,low=0;int count=0;
      MqlDateTime local;TimeToStruct(ny,local);
      datetime day=ny-local.hour*3600-local.min*60-local.sec;
      bool started=local.day_of_week<=4 && ny>=day+20*3600;
      bool forming=started && ny<day+23*3600;
      bool range=false;
      if(started)
      {
         MqlRates bars[];
         count=CopyRates(_Symbol,PERIOD_M5,TcNYToServer(day+20*3600),
                         MathMin(now,TcNYToServer(day+22*3600+55*60)),bars);
         if(count>0)
         {
            high=bars[0].high;low=bars[0].low;
            for(int i=1;i<count;i++){high=MathMax(high,bars[i].high);low=MathMin(low,bars[i].low);}
            range=true;
         }
      }
      ulong ticket=0;bool position=PositionOf(MagicC1,ticket),pending=false;
      double stop=position?PositionGetDouble(POSITION_SL):0;
      string direction=position?(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?"BUY ":"SELL ")+DoubleToString(PositionGetDouble(POSITION_VOLUME),2):"FLAT";
      for(int i=0;i<OrdersTotal();i++)
         if(OrderGetTicket(i)>0 && OrderGetString(ORDER_SYMBOL)==_Symbol && OrderGetInteger(ORDER_MAGIC)==MagicC1)pending=true;
      int buys=0,sells=0;ulong positions[];
      bool historyReady=HistorySelect(TcNYToServer(day),now);
      if(historyReady)
         for(int i=0;i<HistoryDealsTotal();i++)
         {
            ulong deal=HistoryDealGetTicket(i);
            if(HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol || HistoryDealGetInteger(deal,DEAL_MAGIC)!=MagicC1 ||
               HistoryDealGetInteger(deal,DEAL_ENTRY)!=DEAL_ENTRY_IN)continue;
            ulong id=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);bool seen=false;
            for(int j=0;j<ArraySize(positions);j++)if(positions[j]==id){seen=true;break;}
            if(seen)continue;
            int n=ArraySize(positions);ArrayResize(positions,n+1);positions[n]=id;
            long type=HistoryDealGetInteger(deal,DEAL_TYPE);
            if(type==DEAL_TYPE_BUY)buys++;else if(type==DEAL_TYPE_SELL)sells++;
         }
      TcPanelLabel("SRV",x+8,y+40,"NY Time: "+TimeToString(ny,TIME_SECONDS)+" ["+TimeToString(now,TIME_SECONDS)+"]",8,C'140,158,185');
      TcVisualDelete(tcPanelPrefix+"CHART");
      TcPanelLabel("HI",x+8,y+59,"Range High: "+(range?DoubleToString(high,_Digits):"--"),8,C'120,210,150');
      TcPanelLabel("LO",x+8,y+76,"Range Low: "+(range?DoubleToString(low,_Digits):"--"),8,C'210,100,100');
      TcPanelLabel("SZ",x+8,y+93,"Range Size: "+(range?StringFormat("%.3f (%.2f%%)",high-low,(high-low)/high*100):"--"),8,C'140,158,185');
      TcPanelLabel("BUY",x+8,y+112,"Buy Trades: "+(historyReady?IntegerToString(buys):"--"),8,C'120,210,150');
      TcPanelLabel("SELL",x+112,y+112,"Sell Trades: "+(historyReady?IntegerToString(sells):"--"),8,C'210,100,100');
      TcPanelLabel("POS",x+8,y+132,!tcRecoveryReady?"Recovery: history wait":!started?"Awaiting new range":forming?"Range forming":range?"Range locked":"Range unavailable",8,C'120,210,150');
      TcPanelLabel("STOP",x+8,y+149,(position?direction:pending?"PENDING":"FLAT")+" | SL "+(stop>0?DoubleToString(stop,_Digits):"--"),8,C'210,100,100');
      string risk=RiskMoney>0?StringFormat("$%.2f",AccountInfoDouble(ACCOUNT_BALANCE)*BrakeRF(S1)):StringFormat("%.2f%%",BrakeRF(S1)*100);
      TcPanelLabel("RISK",x+8,y+166,"Risk: "+risk+" | Exit 12:00 PM",8,C'140,200,240');
      int n=MathMin(BrakeN,ArraySize(S1.closedR));double sum=0;
      for(int i=ArraySize(S1.closedR)-n;i<ArraySize(S1.closedR);i++)sum+=S1.closedR[i];
      TcPanelLabel("BRAKE",x+8,y+183,StringFormat("Brake %s | %d/%d: %.2fR",UseBrake?"ON":"OFF",n,BrakeN,sum),8,C'190,180,120');
      bool ready=MQLInfoInteger(MQL_TESTER)?tcCalendarComplete:TcNativeNewsValid();
      TcPanelLabel("NEWS",x+8,y+200,!UseNewsFlatten?"News exit OFF":StringFormat("FF news %dm early | %s",NewsExitLeadMinutes,ready?"OK":"unavailable"),8,!UseNewsFlatten || ready?C'120,210,150':C'200,70,70');
   }
   bool redraw=tcPanelDirty || tcVisualWrites!=writesBefore;tcPanelDirty=false;if(redraw)ChartRedraw(0);
}
void TcPanelStop()
{
   if(!tcPanelStarted) return;
   EventKillTimer(); TcPanelDelete();
   ChartSetInteger(0,CHART_EVENT_OBJECT_CREATE,tcOldObjectEvents);
   ChartSetInteger(0,CHART_FOREGROUND,tcOldForeground);
   tcPanelStarted=false;
}

// ORB_Scalper pattern: filled background rectangle and finite dotted levels.
string tcRangePrefix="TC_RESEARCH_RANGE.";
datetime tcRangeSecond=0;
ulong tcRangePollMS=0;
bool TcRangeVisual() { return DrawRangeBoxes && (!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE)); }
datetime TcRangeAnchor(datetime time)
{
   return TcVisualBarEnd(time,PeriodSeconds());
}
void TcRangePoint(string name,int index,datetime time,double price)
{
   TcVisualPoint(name,index,time,price);
}
bool TcRangeFill(datetime session,int direction,datetime &fill);
void TcRangeLine(string name,datetime left,datetime right,double price,string tip,bool filled)
{
   if(ObjectFind(0,name)<0)
   {
      ObjectCreate(0,name,OBJ_TREND,0,left,price,right,price);
      ObjectSetInteger(0,name,OBJPROP_RAY_LEFT,false); ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
      ObjectSetInteger(0,name,OBJPROP_BACK,true); ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true); ObjectSetInteger(0,name,OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS);
      ObjectSetInteger(0,name,OBJPROP_WIDTH,1); tcVisualCreates++;
   }
   TcRangePoint(name,0,left,price); TcRangePoint(name,1,right,price);
   TcVisualInt(name,OBJPROP_COLOR,C'214,218,224');
   TcVisualInt(name,OBJPROP_STYLE,filled?STYLE_SOLID:STYLE_DASH);
   TcVisualInt(name,OBJPROP_BACK,true); // Repair lines from an earlier build.
   TcVisualString(name,OBJPROP_TOOLTIP,tip);
}
bool TcVisualQualifies(datetime session)
{
   double high,low;int count;
   if(!BoxOf(session,high,low,count) || !BoxValid(session,high,low,count))return false;
   double relative=TcHindsightWidth(session,high-low);
   return relative>0 && relative<1;
}
void TcRangeDraw(datetime session)
{
   MqlDateTime day; TimeToStruct(session,day);
   if(day.day_of_week==5 || day.day_of_week==6) return;
   datetime now=NYNow(),startNY=session+20*3600,endNY=session+23*3600;
   if(now<startNY) return;
   if(now>=endNY && !TcVisualQualifies(session))
   {
      string key=tcRangePrefix+TimeToString(session,TIME_DATE);
      TcVisualDelete(key+".box");TcVisualDelete(key+".high");TcVisualDelete(key+".low");return;
   }
   // A forming range uses only bars available now. No future high/low is read.
   datetime lastNY=MathMin(now,endNY-1);
   MqlRates bars[];
   int count=CopyRates(_Symbol,PERIOD_M5,TcNYToServer(startNY),TcNYToServer(lastNY),bars);
   if(count<=0) return;
   double high=-DBL_MAX,low=DBL_MAX;datetime highTime=bars[0].time,lowTime=bars[0].time;
   for(int i=0;i<count;i++)
   {
      if(bars[i].high>high) {high=bars[i].high;highTime=bars[i].time;}
      if(bars[i].low<low) {low=bars[i].low;lowTime=bars[i].time;}
   }
   datetime left=TcRangeAnchor(TcNYToServer(startNY));
   datetime right=TcRangeAnchor(TcNYToServer(endNY-1));
   if(right<=left) right=left+MathMax(1,PeriodSeconds());
   string key=TimeToString(session,TIME_DATE),name=tcRangePrefix+key+".box";
   if(ObjectFind(0,name)<0)
   {
      ObjectCreate(0,name,OBJ_RECTANGLE,0,left,high,right,low);
      ObjectSetInteger(0,name,OBJPROP_BACK,true); ObjectSetInteger(0,name,OBJPROP_FILL,true);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false); ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,name,OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS);
      ObjectSetInteger(0,name,OBJPROP_COLOR,C'44,39,57'); tcVisualCreates++;
   }
   TcRangePoint(name,0,left,high); TcRangePoint(name,1,right,low);
   string tip=StringFormat("Tokyo box %s NY 20:00-23:00 | high %.*f low %.*f | %s",
                           key,_Digits,high,_Digits,low,now<endNY?"developing":"complete");
   TcVisualString(name,OBJPROP_TOOLTIP,tip);
   datetime until=MathMin(TcRangeAnchor(TcNYToServer(session+86400+12*3600+59)),
                          TcRangeAnchor(TimeCurrent())+2*MathMax(1,PeriodSeconds()));
   if(until<=left) until=left+MathMax(1,PeriodSeconds());
   int period=MathMax(1,PeriodSeconds());
   datetime buyFill=0,sellFill=0;
   bool buyFilled=TcRangeFill(session,1,buyFill),sellFilled=TcRangeFill(session,-1,sellFill);
   bool expired=now>=session+86400+3*3600;
   datetime liveRight=(datetime)((long)TimeCurrent()/period*period)+2*period-1;
   if(!expired || buyFilled)
      TcRangeLine(tcRangePrefix+key+".high",(datetime)((long)highTime/period*period),buyFilled?(datetime)((long)buyFill/60*60+59):liveRight,high,tip+" | high level",buyFilled);
   else TcVisualDelete(tcRangePrefix+key+".high");
   if(!expired || sellFilled)
      TcRangeLine(tcRangePrefix+key+".low",(datetime)((long)lowTime/period*period),sellFilled?(datetime)((long)sellFill/60*60+59):liveRight,low,tip+" | low level",sellFilled);
   else TcVisualDelete(tcRangePrefix+key+".low");
}
void TcRangesRefresh(bool force=false)
{
   if(!TcRangeVisual() || (!force && tcRangeSecond==TimeCurrent() && GetTickCount64()-tcRangePollMS<5000)) return;
   tcRangePollMS=GetTickCount64();
   tcRangeSecond=TimeCurrent();
   datetime session=SessionOf(NYNow());
   // Reconcile in place even on scroll/zoom; never rebuild existing objects.
   for(int days=2;days>=0;days--) TcRangeDraw(session-days*86400);
   for(int i=ObjectsTotal(0)-1;i>=0;i--)
   {
      string name=ObjectName(0,i);
      if(StringFind(name,tcRangePrefix)!=0) continue;
      datetime date=StringToTime(StringSubstr(name,StringLen(tcRangePrefix),10));
      if(!TcVisibleSession(date,session)) TcVisualDelete(name);
   }
}
void TcRangesCheck()
{
   if(!TcRangeVisual()) return;
   int boxes=0,lines=0,failures=0;
   for(int i=0;i<ObjectsTotal(0);i++)
   {
      string name=ObjectName(0,i);
      if(StringFind(name,tcRangePrefix)!=0) continue;
      long type=ObjectGetInteger(0,name,OBJPROP_TYPE);
      if(type==OBJ_RECTANGLE)
      {
         boxes++;
         if(!ObjectGetInteger(0,name,OBJPROP_FILL) || !ObjectGetInteger(0,name,OBJPROP_BACK)) failures++;
      }
      if(type==OBJ_TREND)
      {
         lines++;
         if(ObjectGetInteger(0,name,OBJPROP_RAY_LEFT) || ObjectGetInteger(0,name,OBJPROP_RAY_RIGHT)) failures++;
      }
      if(ObjectGetInteger(0,name,OBJPROP_TIME,1)<=ObjectGetInteger(0,name,OBJPROP_TIME,0)) failures++;
      if(ObjectGetInteger(0,name,OBJPROP_SELECTABLE)) failures++;
   }
   PrintFormat("TC_RANGE_RESULT boxes=%d lines=%d failures=%d",boxes,lines,failures);
}
void TcRangesFocus()
{
   if(!TcRangeVisual() || !MQLInfoInteger(MQL_TESTER)) return;
   datetime latest=0;
   for(int i=0;i<ObjectsTotal(0);i++)
   {
      string name=ObjectName(0,i);
      if(StringFind(name,tcRangePrefix)==0 && ObjectGetInteger(0,name,OBJPROP_TYPE)==OBJ_RECTANGLE)
         latest=(datetime)MathMax(latest,ObjectGetInteger(0,name,OBJPROP_TIME,1));
   }
   if(latest<=0) return;
   int shift=iBarShift(_Symbol,_Period,latest,false);
   ChartSetInteger(0,CHART_AUTOSCROLL,false);
   ChartNavigate(0,CHART_END,-MathMax(0,shift-30));
   ChartRedraw(0);
}

// Owned deal history is the source for both historical and live execution visuals.
string tcExecPrefix="TC_EXEC.";
struct TcExecution
{
   ulong id;
   datetime fill,exit,session,reference;
   double entry,stop,close,actualClose,armingSpread;
   int direction;
   bool scheduled,referenceReady,synthetic,preciseTouch;
};
TcExecution tcExecutions[];
bool TcRangeFill(datetime session,int direction,datetime &fill)
{
   fill=0;
   for(int i=0;i<ArraySize(tcExecutions);i++)
      if(tcExecutions[i].session==session && tcExecutions[i].direction==direction &&
         (fill==0 || tcExecutions[i].fill<fill)) fill=tcExecutions[i].fill;
   return fill>0;
}
bool tcExecutionDirty=true;
datetime tcExecutionSession=0,tcExecutionSecond=0;
datetime tcSyntheticMinute=0;
ulong tcSyntheticRetryAt=0;
bool tcSyntheticPending=false;
bool TcExecutionVisual() { return ShowExecutionObjects && (!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE)); }
void TcExecutionHistory(datetime session)
{
   if(!HistorySelect(TcNYToServer(session-2*86400+17*3600),TimeCurrent())) return;
   ulong ids[];
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong deal=HistoryDealGetTicket(i);
      if(HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol || HistoryDealGetInteger(deal,DEAL_MAGIC)!=MagicC1 ||
         HistoryDealGetInteger(deal,DEAL_ENTRY)!=DEAL_ENTRY_IN) continue;
      ulong id=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);bool exists=false;
      for(int k=0;k<ArraySize(ids);k++) if(ids[k]==id) {exists=true;break;}
      if(!exists) {int n=ArraySize(ids);ArrayResize(ids,n+1);ids[n]=id;}
   }
   ArrayResize(tcExecutions,0);
   for(int i=0;i<ArraySize(ids);i++)
   {
      TcExecution v;ZeroMemory(v);v.id=ids[i];
      if(!TcHistoryRisk(v.id,v.entry,v.stop,v.direction,v.close,v.exit))
      { PrintFormat("TC_VISUAL_HISTORY_SKIP position=%I64u: initial risk unavailable",v.id);continue; }
      v.actualClose=v.close;
      bool stopped=false,expertExit=false;
      for(int k=0;k<HistoryDealsTotal();k++)
      {
         ulong deal=HistoryDealGetTicket(k);
         if(HistoryDealGetInteger(deal,DEAL_ENTRY)==DEAL_ENTRY_IN)
         {
            datetime t=(datetime)HistoryDealGetInteger(deal,DEAL_TIME);
            if(v.fill==0 || t<v.fill) v.fill=t;
         }
         if(HistoryDealGetInteger(deal,DEAL_REASON)==DEAL_REASON_SL) stopped=true;
         if(HistoryDealGetInteger(deal,DEAL_ENTRY)==DEAL_ENTRY_OUT || HistoryDealGetInteger(deal,DEAL_ENTRY)==DEAL_ENTRY_OUT_BY)
            expertExit=HistoryDealGetInteger(deal,DEAL_REASON)==DEAL_REASON_EXPERT;
      }
      v.session=SessionOf(TcServerToNY(v.fill));
      if(!TcVisibleSession(v.session,session)) continue;
      v.reference=TcNYToServer(v.session+86400+12*3600);
      v.scheduled=expertExit && !stopped && v.exit>=v.reference && v.exit<v.reference+60;
      int n=ArraySize(tcExecutions);ArrayResize(tcExecutions,n+1);tcExecutions[n]=v;
   }
   tcExecutionDirty=false;tcExecutionSession=session;
   tcSyntheticMinute=0;
}
void TcExecutionBox(string name,datetime left,datetime right,double entry,double edge,color ink,string tip)
{
   if(MathAbs(edge-entry)<_Point*.5) {TcVisualDelete(name);return;}
   if(ObjectFind(0,name)<0)
   {
      if(!ObjectCreate(0,name,OBJ_RECTANGLE,0,left,entry,right,edge)) return;
      tcVisualCreates++;
      TcVisualInt(name,OBJPROP_COLOR,ink);TcVisualInt(name,OBJPROP_WIDTH,1);
      TcVisualInt(name,OBJPROP_FILL,false);TcVisualInt(name,OBJPROP_BACK,true);
      TcVisualInt(name,OBJPROP_SELECTABLE,false);TcVisualInt(name,OBJPROP_HIDDEN,true);
      TcVisualInt(name,OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS);
   }
   TcVisualPoint(name,0,left,entry);TcVisualPoint(name,1,right,edge);
   TcVisualString(name,OBJPROP_TOOLTIP,tip);
}
void TcExecutionDraw(TcExecution &v)
{
   datetime resolution=v.exit>0?TcVisualBarEnd(v.exit,60):0;
   double endpoint=v.close;
   if(v.scheduled)
   {
      resolution=v.reference+59;
      // The 12:00 candle's close is available only at 12:01. Never read its future close.
      if(!v.referenceReady && TimeCurrent()>=v.reference+60)
      {
         MqlRates bar[];
         if(CopyRates(_Symbol,PERIOD_M1,v.reference,v.reference,bar)==1 && bar[0].time==v.reference)
         {v.close=bar[0].close;v.referenceReady=true;}
      }
      endpoint=v.close;
   }
   int seconds=PeriodSeconds();
   datetime right=TcExecutionRight(v.fill,TimeCurrent(),seconds,resolution);
   datetime left=v.fill; // First touch/fill timestamp, never range lock or chart-bar end.
   if(right<=left) return;
   string key=tcExecPrefix+TimeToString(v.session,TIME_DATE)+"."+(v.synthetic?"synthetic":StringFormat("%I64u",v.id));
   string tip=StringFormat("%s | fill %s @ %.*f | original SL %.*f",v.direction>0?"LONG":"SHORT",
      TimeToString(v.fill,TIME_DATE|TIME_SECONDS),_Digits,v.entry,_Digits,v.stop);
   if(v.synthetic) tip="SYNTHETIC M1 ESTIMATE (not broker-filled) | "+tip;
   if(v.synthetic) tip+=v.preciseTouch?" | ordered-quote first touch":" | first-touch candle (intrabar time unknown)";
   if(v.exit>0) tip+=v.scheduled?(v.referenceReady?" | 12:00 M1 close reference":" | awaiting 12:00 M1 close") : " | actual exit candle";
   if(v.exit>0) tip+=StringFormat(" | execution %.*f | visual %.*f",_Digits,v.actualClose,_Digits,endpoint);
   string line=key+".entry";
   if(ObjectFind(0,line)<0)
   {
      if(ObjectCreate(0,line,OBJ_TREND,0,left,v.entry,right,v.entry))
      {
         tcVisualCreates++;
         TcVisualInt(line,OBJPROP_COLOR,C'214,218,224');TcVisualInt(line,OBJPROP_WIDTH,1);
         TcVisualInt(line,OBJPROP_RAY_LEFT,false);TcVisualInt(line,OBJPROP_RAY_RIGHT,false);
         TcVisualInt(line,OBJPROP_BACK,true);TcVisualInt(line,OBJPROP_SELECTABLE,false);
         TcVisualInt(line,OBJPROP_HIDDEN,true);TcVisualInt(line,OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS);
      }
   }
   TcVisualPoint(line,0,left,v.entry);TcVisualPoint(line,1,right,v.entry);
   TcVisualInt(line,OBJPROP_STYLE,v.synthetic?STYLE_DASH:STYLE_SOLID);
   TcVisualString(line,OBJPROP_TOOLTIP,tip);
   bool resolved=v.exit>0 && (!v.scheduled || v.referenceReady);
   TcExecutionBox(key+".sl",left,right,v.entry,
      TcExecutionLossEdge(v.direction,v.entry,v.stop,endpoint,resolved),C'55,57,68',tip);
   if(resolved && v.direction*(endpoint-v.entry)>0)
      TcExecutionBox(key+".tp",left,right,v.entry,endpoint,C'22,55,120',tip);
   else TcVisualDelete(key+".tp");
}
double TcHindsightWidth(datetime session,double width)
{
   int shift=iBarShift(_Symbol,PERIOD_D1,TcNYToServer(session+23*3600),false);
   if(shift<0) return -1;
   datetime daily[];int n=CopyTime(_Symbol,PERIOD_D1,shift+1,20,daily);
   double widths[];
   for(int i=0;i<n;i++)
   {
      datetime previous=SessionOf(TcServerToNY(daily[i]));double high,low;int count;
      if(BoxOf(previous,high,low,count) && BoxValid(previous,high,low,count))
      {int k=ArraySize(widths);ArrayResize(widths,k+1);widths[k]=high-low;}
   }
   int count=ArraySize(widths);if(count<10) return -1;
   ArraySort(widths);double median=count%2!=0?widths[count/2]:(widths[count/2-1]+widths[count/2])*.5;
   return median>0?width/median:-1;
}
void TcRefineHindsightTouch(TcExecution &v,datetime minute,double buy,double sell,bool arming,double boxHigh,double boxLow,datetime now)
{
   MqlTick quotes[];
   ulong first=(ulong)minute*1000,last=(ulong)MathMin(minute+59,now)*1000+999;
   int count=CopyTicksRange(_Symbol,quotes,COPY_TICKS_ALL,first,last);
   // An incomplete beginning cannot establish the first touch in this candle.
   if(count<=0 || quotes[0].time>minute+2) return;
   for(int i=0;i<count;i++)
   {
      MqlTick q=quotes[i];if(q.bid<=0 || q.ask<=0) return;
      int side=0;
      if(arming && i==0 && q.bid>boxHigh) side=1;
      else if(arming && i==0 && q.bid<boxLow) side=-1;
      else if(q.ask>=buy) side=1;
      else if(q.bid<=sell) side=-1;
      if(side==0) continue;
      if(side!=v.direction) return; // M1/spread approximation disagrees; do not assert exact touch.
      v.fill=q.time;v.preciseTouch=true;return;
   }
}
// Bounded M1 replay: a visual estimate, never a performance or exact-tick parity claim.
int TcReplaySession(datetime session,datetime now,TcExecution &v)
{
   ZeroMemory(v);v.synthetic=true;v.session=session;
   datetime lock=TcNYToServer(session+23*3600),expiry=TcNYToServer(session+86400+3*3600);
   datetime scheduled=TcNYToServer(session+86400+12*3600);
   if(now<lock) return TC_REPLAY_NO_SIGNAL;
   MqlDateTime date;TimeToStruct(session,date);
   if(date.day_of_week==5 || date.day_of_week==6) return TC_REPLAY_NO_SIGNAL;
   double high,low;int count;
   if(!BoxOf(session,high,low,count)) return TC_REPLAY_MISSING;
   if(!BoxValid(session,high,low,count)) return TC_REPLAY_NO_SIGNAL;
   double relative=TcHindsightWidth(session,high-low);
   if(relative<0) return TC_REPLAY_MISSING;
   if(relative>=1) return TC_REPLAY_NO_SIGNAL;
   MqlRates bars[];count=CopyRates(_Symbol,PERIOD_M1,lock,MathMin(now,scheduled),bars);
   if(count<=0 || bars[0].time!=lock) return TC_REPLAY_MISSING;
   v.armingSpread=bars[0].spread*_Point;
   double buy=NormalizeDouble(high+v.armingSpread+_Point,_Digits),sell=NormalizeDouble(low-_Point,_Digits);
   datetime event=UseNewsFlatten?EventOn(session+86400):0;
   for(int i=0;i<count;i++)
   {
      MqlRates b=bars[i];double spread=b.spread*_Point;
      if(i>0 && b.time-bars[i-1].time>60) return TC_REPLAY_MISSING;
      bool justFilled=false,atOpen=false;
      if(v.fill==0)
      {
         if(b.time>=expiry) return TC_REPLAY_NO_SIGNAL;
         int side=TcHindsightSide(b.open,b.high,b.low,spread,buy,sell,i==0,high,low);
         if(side==2) return TC_REPLAY_AMBIGUOUS;
         if(side==0) continue;
         v.direction=side;v.fill=b.time;v.stop=side>0?low:high;
         atOpen=side>0?b.open+spread>=buy:b.open<=sell;
         if(i==0 && (b.open>high || b.open<low)) atOpen=true;
         v.entry=side>0?(atOpen?b.open+spread:buy):(atOpen?b.open:sell);justFilled=true;
         TcRefineHindsightTouch(v,b.time,buy,sell,i==0,high,low,now);
      }
      datetime flatten=event>0 && event-NewsExitLeadMinutes*60>v.fill?MathMin(scheduled,event-NewsExitLeadMinutes*60):scheduled;
      if(b.time>=flatten)
      {
         v.exit=b.time;v.close=v.direction>0?b.open:b.open+spread;v.actualClose=v.close;
         v.scheduled=flatten==scheduled;v.reference=scheduled;return TC_REPLAY_FILLED;
      }
      bool stopped=v.direction>0?b.low<=v.stop:b.high+spread>=v.stop;
      if(stopped)
      {
         if(justFilled && !atOpen) return TC_REPLAY_AMBIGUOUS;
         v.exit=b.time+59;v.close=v.direction>0?MathMin(v.stop,b.open):MathMax(v.stop,b.open+spread);
         v.actualClose=v.close;return TC_REPLAY_FILLED;
      }
   }
   return v.fill>0?TC_REPLAY_FILLED:TC_REPLAY_WAITING;
}
void TcSyntheticRefresh(datetime session)
{
   datetime minute=TimeCurrent()/60*60;
   if(tcSyntheticMinute==minute && (!tcSyntheticPending || GetTickCount64()<tcSyntheticRetryAt)) return;
   tcSyntheticMinute=minute;
   tcSyntheticPending=false;tcSyntheticRetryAt=GetTickCount64()+3000;
   for(int i=ArraySize(tcExecutions)-1;i>=0;i--)
      if(tcExecutions[i].synthetic)
      {for(int j=i;j<ArraySize(tcExecutions)-1;j++) tcExecutions[j]=tcExecutions[j+1];ArrayResize(tcExecutions,ArraySize(tcExecutions)-1);}
   if(!ShowSyntheticFills) return;
   for(int day=2;day>=0;day--)
   {
      datetime date=session-day*86400;bool brokerFilled=false;
      for(int i=0;i<ArraySize(tcExecutions);i++) if(tcExecutions[i].session==date && !tcExecutions[i].synthetic) brokerFilled=true;
      if(brokerFilled) continue;
      TcExecution v;
      int state=TcReplaySession(date,TimeCurrent(),v);
      if(state==TC_REPLAY_MISSING) tcSyntheticPending=true;
      if(state==TC_REPLAY_FILLED)
      {int n=ArraySize(tcExecutions);ArrayResize(tcExecutions,n+1);tcExecutions[n]=v;}
   }
}
void TcExecutionsRefresh(bool force=false)
{
   if(!TcExecutionVisual() || (!force && !tcExecutionDirty && tcExecutionSecond==TimeCurrent())) return;
   tcExecutionSecond=TimeCurrent();datetime session=SessionOf(NYNow());
   if(tcExecutionDirty || session!=tcExecutionSession) TcExecutionHistory(session);
   TcSyntheticRefresh(session);
   bool eligible[];ArrayResize(eligible,ArraySize(tcExecutions));
   for(int i=0;i<ArraySize(tcExecutions);i++)
   {eligible[i]=TcVisualQualifies(tcExecutions[i].session);if(eligible[i])TcExecutionDraw(tcExecutions[i]);}
   for(int i=ObjectsTotal(0)-1;i>=0;i--)
   {
      string name=ObjectName(0,i);
      if(StringFind(name,tcExecPrefix)!=0) continue;
      datetime date=StringToTime(StringSubstr(name,StringLen(tcExecPrefix),10));
      bool represented=false;
      for(int k=0;k<ArraySize(tcExecutions);k++)
      {
         if(!eligible[k])continue;
         string key=tcExecPrefix+TimeToString(tcExecutions[k].session,TIME_DATE)+"."+
            (tcExecutions[k].synthetic?"synthetic":StringFormat("%I64u",tcExecutions[k].id))+".";
         if(StringFind(name,key)==0) {represented=true;break;}
      }
      if(!TcVisibleSession(date,session) || !represented) TcVisualDelete(name);
   }
}

#endif
