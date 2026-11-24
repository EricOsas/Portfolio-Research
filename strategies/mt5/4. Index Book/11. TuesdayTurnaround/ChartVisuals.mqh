#ifndef TT_CHART_VISUALS
#define TT_CHART_VISUALS
string TTPrefix(){return "TT_"+IntegerToString((long)Magic)+"_";}
bool TTVisualEnabled(){return ShowVisuals && (!MQLInfoInteger(MQL_TESTER)||MQLInfoInteger(MQL_VISUAL_MODE));}
const int TT_PX=10,TT_PY=20,TT_PW=210,TT_PH=198,TT_HH=32;
bool ttPanelCollapsed=false;
void TTPanelRect(string key,int x,int y,int w,int h,color bg,color border)
{
   string id=TTPrefix()+key;
   if(ObjectFind(0,id)<0)
   {
      ObjectCreate(0,id,OBJ_RECTANGLE_LABEL,0,0,0);ObjectSetInteger(0,id,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,id,OBJPROP_SELECTABLE,false);ObjectSetInteger(0,id,OBJPROP_HIDDEN,true);ObjectSetInteger(0,id,OBJPROP_BACK,false);
   }
   ObjectSetInteger(0,id,OBJPROP_BACK,false);ObjectSetInteger(0,id,OBJPROP_ZORDER,10000);ObjectSetInteger(0,id,OBJPROP_XDISTANCE,x);ObjectSetInteger(0,id,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,id,OBJPROP_XSIZE,w);ObjectSetInteger(0,id,OBJPROP_YSIZE,h);ObjectSetInteger(0,id,OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(0,id,OBJPROP_COLOR,border);ObjectSetInteger(0,id,OBJPROP_BORDER_TYPE,BORDER_FLAT);
}
void TTDrawPanel()
{
   if(!TTVisualEnabled())return;
   int height=ttPanelCollapsed?TT_HH:TT_PH;
   TTPanelRect("P_SHD2",TT_PX+5,TT_PY+5,TT_PW,height,C'6,6,6',C'6,6,6');
   TTPanelRect("P_SHD1",TT_PX+2,TT_PY+2,TT_PW,height,C'12,12,12',C'12,12,12');
   TTPanelRect("P_BG",TT_PX,TT_PY,TT_PW,height,clrBlack,C'52,68,92');
   TTPanelRect("P_HDR",TT_PX,TT_PY,TT_PW,TT_HH,C'18,22,28',C'52,68,92');
   TTPanelRect("P_HAIR",TT_PX,TT_PY+TT_HH,TT_PW,1,C'52,68,92',C'52,68,92');
   string button=TTPrefix()+"P_BTN";
   if(ObjectFind(0,button)<0){ObjectCreate(0,button,OBJ_BUTTON,0,0,0);ObjectSetInteger(0,button,OBJPROP_CORNER,CORNER_LEFT_UPPER);ObjectSetInteger(0,button,OBJPROP_HIDDEN,true);ObjectSetString(0,button,OBJPROP_FONT,"Segoe UI Semibold");}
   ObjectSetInteger(0,button,OBJPROP_XDISTANCE,TT_PX+TT_PW-29);ObjectSetInteger(0,button,OBJPROP_YDISTANCE,TT_PY+5);
   ObjectSetInteger(0,button,OBJPROP_XSIZE,22);ObjectSetInteger(0,button,OBJPROP_YSIZE,22);ObjectSetInteger(0,button,OBJPROP_FONTSIZE,12);
   ObjectSetInteger(0,button,OBJPROP_BACK,false);ObjectSetInteger(0,button,OBJPROP_ZORDER,10002);ObjectSetInteger(0,button,OBJPROP_COLOR,C'190,210,236');ObjectSetInteger(0,button,OBJPROP_BGCOLOR,C'18,22,28');ObjectSetInteger(0,button,OBJPROP_BORDER_COLOR,C'52,68,92');ObjectSetInteger(0,button,OBJPROP_STATE,false);ObjectSetString(0,button,OBJPROP_TEXT,ttPanelCollapsed?"+":"-");
   if(ttPanelCollapsed){string rows[]={"Clock","State","Risk","Position","StopInfo","News","Status","Preview"};for(int i=0;i<ArraySize(rows);i++)ObjectDelete(0,TTPrefix()+rows[i]);}
}
void TTLabel(string key,int row,string text,color ink=clrWhite)
{
   if(!TTVisualEnabled())return;string id=TTPrefix()+key;
   if(ObjectFind(0,id)<0){ObjectCreate(0,id,OBJ_LABEL,0,0,0);ObjectSetInteger(0,id,OBJPROP_CORNER,CORNER_LEFT_UPPER);ObjectSetInteger(0,id,OBJPROP_SELECTABLE,false);ObjectSetInteger(0,id,OBJPROP_HIDDEN,true);ObjectSetInteger(0,id,OBJPROP_BACK,false);ObjectSetString(0,id,OBJPROP_FONT,"Segoe UI Semibold");}
   int y=row==0?TT_PY+8:TT_PY+40+(row-1)*19;
   ObjectSetInteger(0,id,OBJPROP_BACK,false);ObjectSetInteger(0,id,OBJPROP_ZORDER,10001);ObjectSetInteger(0,id,OBJPROP_XDISTANCE,TT_PX+8);ObjectSetInteger(0,id,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,id,OBJPROP_COLOR,ink);ObjectSetInteger(0,id,OBJPROP_FONTSIZE,row==0?9:8);ObjectSetString(0,id,OBJPROP_TEXT,text);
}
string TTPanelFit(string text,int width)
{
   if(StringLen(text)<=width)return text;
   return StringSubstr(text,0,width-3)+"...";
}
void TTLine(string key,datetime left,datetime right,double price,color ink,ENUM_LINE_STYLE style=STYLE_SOLID)
{
   string id=TTPrefix()+key;if(!TTVisualEnabled()||left<=0||right<=left||price<=0){ObjectDelete(0,id);return;}
   if(ObjectFind(0,id)<0)ObjectCreate(0,id,OBJ_TREND,0,left,price,right,price);
   ObjectMove(0,id,0,left,price);ObjectMove(0,id,1,right,price);ObjectSetInteger(0,id,OBJPROP_RAY_LEFT,false);ObjectSetInteger(0,id,OBJPROP_RAY_RIGHT,false);
   ObjectSetInteger(0,id,OBJPROP_BACK,true);ObjectSetInteger(0,id,OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS);ObjectSetInteger(0,id,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,id,OBJPROP_COLOR,ink);ObjectSetInteger(0,id,OBJPROP_STYLE,style);ObjectSetInteger(0,id,OBJPROP_SELECTABLE,false);ObjectSetString(0,id,OBJPROP_TOOLTIP,key+" "+DoubleToString(price,_Digits));
}
datetime TTProjectedExit(datetime monday)
{
   int days=(Model==T1_OnePercentDrop||Model==T2_BearishLowIBS)?1:4;datetime d=monday;
   for(int i=0;i<days;i++){do d+=86400;while(TTWeekday(d)==0||TTWeekday(d)==6);}
   return d+86400;
}
void TTInitVisuals()
{
   if(!TTVisualEnabled())return;ChartSetInteger(0,CHART_SHOW_GRID,false);ChartSetInteger(0,CHART_MODE,CHART_CANDLES);TTDrawPanel();
}
void TTUpdateVisuals(datetime now)
{
   if(!TTVisualEnabled())return;
   TTDailyBar current;if(TTReadD1(0,current)&&TTWeekday(current.day)==1)
   {
      TTDailyBar friday;if(TTReadD1(1,friday)&&TTIsPrecedingFriday(friday.day,current.day))
      {
         ttFriday=friday;ttMonday=current;ttMondayDay=current.day;
         datetime right=TTProjectedExit(current.day);
         TTLine("Friday open",friday.day,right,friday.open,clrOrange,STYLE_DASH);
         TTLine("Monday open",current.day,right,current.open,clrDeepSkyBlue,STYLE_DOT);
         TTLine("Monday high",current.day,right,current.high,clrDeepSkyBlue,STYLE_DOT);
         TTLine("Monday low",current.day,right,current.low,clrDeepSkyBlue,STYLE_DOT);
         TTLine("Monday close live",current.day,right,current.close,clrGold,STYLE_DOT);
         double ibs=TTIBS(current);
         if(!ttPanelCollapsed)TTLabel("Preview",EnableNewsFilter?8:7,TTPanelFit(StringFormat("Mon H %.*f L %.*f IBS %.3f",_Digits,current.high,_Digits,current.low,ibs),31),clrGold);
      }
   }
   datetime right=ttMondayDay>0?TTProjectedExit(ttMondayDay):now+86400;
   if(ttMondayDay>0)
   {
      TTLine("Friday open",ttFriday.day,right,ttFriday.open,clrOrange,STYLE_DASH);
      TTLine("Monday high",ttMonday.day,right,ttMonday.high,clrDeepSkyBlue,STYLE_DOT);
      TTLine("Monday low",ttMonday.day,right,ttMonday.low,clrDeepSkyBlue,STYLE_DOT);
   }
   if(TTOwnPosition() && PositionSelectByTicket(TTOwnPositionTicket()))
   {
      datetime left=(datetime)PositionGetInteger(POSITION_TIME);
      TTLine("Entry",left,right,PositionGetDouble(POSITION_PRICE_OPEN),clrWhite,STYLE_DOT);
      TTLine("Stop",left,right,PositionGetDouble(POSITION_SL),clrTomato,STYLE_SOLID);
   }
   else {ObjectDelete(0,TTPrefix()+"Entry");ObjectDelete(0,TTPrefix()+"Stop");}
   if(ObjectFind(0,TTPrefix()+"P_BG")<0)TTDrawPanel();
   if(ttPanelCollapsed){TTLabel("Title",0,TTName+" | "+TTRoot(),C'190,210,236');ChartRedraw();return;}
   datetime ny=TTNewYork(now);string clock=ny>0?"NY: "+TimeToString(ny,TIME_SECONDS)+" ["+TimeToString(now,TIME_SECONDS)+"]":"Waiting for clock history";
   TTLabel("Title",0,TTName+" | "+TTRoot(),C'190,210,236');
   TTLabel("Clock",1,clock,C'140,158,185');
   TTLabel("State",2,TTModelLabel(),C'120,210,150');
   TTLabel("Risk",3,"Risk: "+TTSizingLabel(),C'140,200,240');
   string position="Position: FLAT",stop="SL: --";
   if(TTOwnPosition()&&PositionSelectByTicket(TTOwnPositionTicket()))
   {position=StringFormat("Position: LONG %.2f @ %.*f",PositionGetDouble(POSITION_VOLUME),_Digits,PositionGetDouble(POSITION_PRICE_OPEN));stop="SL: "+DoubleToString(PositionGetDouble(POSITION_SL),_Digits);}
   TTLabel("Position",4,position,C'120,210,150');
   TTLabel("StopInfo",5,stop,C'210,100,100');
   int statusRow=6;
   if(EnableNewsFilter)
   {
      bool activeEvent=ttNewsBlocked&&ttNewsActive!="";
      string newsText=activeEvent?"News: BLACKOUT":ttNewsBlocked?"News: unavailable (blocked)":"News: clear | "+ttNewsProvider;
      color newsColor=activeEvent?C'210,100,100':ttNewsBlocked?C'220,170,70':C'120,210,150';
      TTLabel("News",6,TTPanelFit(newsText,31),newsColor);statusRow=7;
   }
   else ObjectDelete(0,TTPrefix()+"News");
   TTLabel("Status",statusRow,TTPanelFit(ttStatus,31),C'190,180,120');
   ChartRedraw();
}
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(id!=CHARTEVENT_OBJECT_CLICK||sparam!=TTPrefix()+"P_BTN"||!TTVisualEnabled())return;
   ObjectSetInteger(0,sparam,OBJPROP_STATE,false);ttPanelCollapsed=!ttPanelCollapsed;TTDrawPanel();TTUpdateVisuals(TimeTradeServer());ChartRedraw();
}
void TTDeinitVisuals(int reason)
{
   if(reason!=REASON_CHARTCHANGE || ChartSymbol(0)!=_Symbol || !ShowVisuals)ObjectsDeleteAll(0,TTPrefix());
}
#endif
