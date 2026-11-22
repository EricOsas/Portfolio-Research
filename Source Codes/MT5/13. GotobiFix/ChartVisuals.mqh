#ifndef GF_CHART_VISUALS
#define GF_CHART_VISUALS
// ChartVisuals.mqh - Gotobi Fix
// Author: Osamwonyi Eric (@You_FoundEric)
// Copyright 2026-2027, Osamwonyi Eric (@You_FoundEric)
//
// Read-only dashboard. Visuals never influence signals or execution: this file only reads state.
// Objects are prefixed per instance (symbol+magic); foreign objects are never touched.

string gfPanelPrefix="";
bool   gfPanelDirty=true, gfPanelCollapsed=false, gfPanelStarted=false, gfOldObjEvents=false, gfOldForeground=false;
datetime gfPanelSecond=0;
int    gfVisualWrites=0;

bool GfVisual() { return ShowPanel && (!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE)); }
void GfVisualInt(string name,ENUM_OBJECT_PROPERTY_INTEGER prop,long value)
{
   if(ObjectGetInteger(0,name,prop)==value) return;
   if(ObjectSetInteger(0,name,prop,value)) gfVisualWrites++;
}
void GfVisualString(string name,ENUM_OBJECT_PROPERTY_STRING prop,string value)
{
   if(ObjectGetString(0,name,prop)==value) return;
   if(ObjectSetString(0,name,prop,value)) gfVisualWrites++;
}
void GfPanelDelete() { ObjectsDeleteAll(0,gfPanelPrefix); }
void GfPanelRect(string suffix,int x,int y,int w,int h,color bg,color border)
{
   string name=gfPanelPrefix+suffix;
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0);
   GfVisualInt(name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   GfVisualInt(name,OBJPROP_XDISTANCE,x); GfVisualInt(name,OBJPROP_YDISTANCE,y);
   GfVisualInt(name,OBJPROP_XSIZE,w); GfVisualInt(name,OBJPROP_YSIZE,h);
   GfVisualInt(name,OBJPROP_BGCOLOR,bg); GfVisualInt(name,OBJPROP_COLOR,border);
   GfVisualInt(name,OBJPROP_BORDER_TYPE,BORDER_FLAT); GfVisualInt(name,OBJPROP_ZORDER,10000);
   GfVisualInt(name,OBJPROP_BACK,false); GfVisualInt(name,OBJPROP_SELECTABLE,false); GfVisualInt(name,OBJPROP_HIDDEN,true);
}
void GfPanelLabel(string suffix,int x,int y,string text,int size,color ink)
{
   string name=gfPanelPrefix+suffix;
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   GfVisualInt(name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   GfVisualInt(name,OBJPROP_XDISTANCE,x); GfVisualInt(name,OBJPROP_YDISTANCE,y);
   GfVisualInt(name,OBJPROP_FONTSIZE,size); GfVisualInt(name,OBJPROP_COLOR,ink);
   GfVisualInt(name,OBJPROP_ZORDER,10001); GfVisualInt(name,OBJPROP_BACK,false);
   GfVisualInt(name,OBJPROP_SELECTABLE,false); GfVisualInt(name,OBJPROP_HIDDEN,true);
   GfVisualString(name,OBJPROP_FONT,"Consolas"); GfVisualString(name,OBJPROP_TEXT,text);
}
void GfPanelStart()
{
   gfPanelPrefix="GF_PANEL."+_Symbol+"."+IntegerToString(Magic)+".";
   if(!GfVisual()) return;
   gfOldObjEvents=(bool)ChartGetInteger(0,CHART_EVENT_OBJECT_CREATE);
   gfOldForeground=(bool)ChartGetInteger(0,CHART_FOREGROUND);
   ChartSetInteger(0,CHART_EVENT_OBJECT_CREATE,true);
   ChartSetInteger(0,CHART_FOREGROUND,false);
   gfPanelStarted=true;
}
string GfLegText(int leg)
{
   string n=leg==0?"LONG ":"SHORT";
   int s=gfLegState[leg];
   return n+" "+(s==0?"waiting":s==1?"IN FLIGHT":s==2?"filled":"BLOCKED");
}
void GfPanelRefresh()
{
   if(!GfVisual()) return;
   datetime now=ClkNowServer();
   if(now<=0) now=TimeCurrent();
   if(gfPanelSecond==now && !gfPanelDirty) return;
   gfPanelSecond=now;
   int writes=gfVisualWrites;
   const int x=10,y=20,w=300,h=230,hh=32;
   int height=gfPanelCollapsed?hh:h;
   GfPanelRect("BG",x,y,w,height,clrBlack,C'52,68,92');
   GfPanelRect("HDR",x,y,w,hh,C'18,22,28',C'52,68,92');
   GfPanelLabel("TTL",x+8,y+8,"Gotobi Fix v1.00 | "+_Symbol,9,C'190,210,236');
   string button=gfPanelPrefix+"BTN";
   if(ObjectFind(0,button)<0) ObjectCreate(0,button,OBJ_BUTTON,0,0,0);
   GfVisualInt(button,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   GfVisualInt(button,OBJPROP_XDISTANCE,x+w-29); GfVisualInt(button,OBJPROP_YDISTANCE,y+5);
   GfVisualInt(button,OBJPROP_XSIZE,22); GfVisualInt(button,OBJPROP_YSIZE,22);
   GfVisualInt(button,OBJPROP_FONTSIZE,12); GfVisualInt(button,OBJPROP_ZORDER,10002);
   GfVisualInt(button,OBJPROP_COLOR,C'190,210,236'); GfVisualInt(button,OBJPROP_BGCOLOR,C'18,22,28');
   GfVisualInt(button,OBJPROP_BORDER_COLOR,C'52,68,92'); GfVisualInt(button,OBJPROP_STATE,false); GfVisualInt(button,OBJPROP_HIDDEN,true);
   GfVisualString(button,OBJPROP_TEXT,gfPanelCollapsed?"+":"-");
   string rows[]={"CLK","UTC","TKY","CFG","DAY","NXT","LEG","POS","SZ","NOTE"};
   if(gfPanelCollapsed) { for(int i=0;i<ArraySize(rows);i++) if(ObjectFind(0,gfPanelPrefix+rows[i])>=0) ObjectDelete(0,gfPanelPrefix+rows[i]); }
   else
   {
      color grey=C'140,158,185', green=C'120,210,150', red=C'210,100,100', amber=C'190,180,120';
      datetime utc=ClkNowUtc(now);
      string profile=ClkText();
      GfPanelLabel("CLK",x+8,y+40,"Server "+TimeToString(now,TIME_SECONDS)+"  "+profile,8,grey);
      GfPanelLabel("UTC",x+8,y+58,"UTC    "+(utc>0?TimeToString(utc,TIME_DATE|TIME_SECONDS):"unresolved"),8,utc>0?grey:red);
      GfPanelLabel("TKY",x+8,y+76,"Tokyo  "+(utc>0?TimeToString(utc+GF_JST_SEC,TIME_DATE|TIME_SECONDS):"--")+"  "+(ClkOK()?(ClkEntryOK()?"clock OK":"clock PAUSED"):"CLOCK BLOCKED"),8,ClkEntryOK()?green:ClkOK()?amber:red);
      GfPanelLabel("CFG",x+8,y+94,StringFormat("%s | %s | lots %.2f | stop %s","hedging",Legs==GF_LEGS_BOTH?"both legs":Legs==GF_LEGS_LONG?"long only":"short only",Lots,DisasterStopPips>0?DoubleToString(DisasterStopPips,0)+"p":"none"),8,grey);
      string day="--", nxt="--"; color dc=grey;
      if(utc>0)
      {
         int ymd=GfTokyoYmd(utc); int ph=GfSignalPhase(utc,ymd);
         day=ph==GF_PHASE_LONG?"GOTOBI - long window":ph==GF_PHASE_SHORT?"GOTOBI - short window":
             (GfIsGotobi(ymd/10000,(ymd/100)%100,ymd%100)?"gotobi day (outside windows)":ph==GF_PHASE_UNKNOWN?"calendar unsupported":"not a gotobi day");
         dc=ph==GF_PHASE_LONG?green:ph==GF_PHASE_SHORT?red:grey;
         int ny,nm,nd;
         if(GfNextGotobi(ymd/10000,(ymd/100)%100,ymd%100,ny,nm,nd)) nxt=StringFormat("%04d-%02d-%02d",ny,nm,nd);
      }
      GfPanelLabel("DAY",x+8,y+116,"Today  "+day,8,dc);
      GfPanelLabel("NXT",x+8,y+134,"Next gotobi (Tokyo) "+nxt,8,grey);
      GfPanelLabel("LEG",x+8,y+156,GfLegText(0)+" | "+GfLegText(1),8,(gfLegState[0]==9||gfLegState[1]==9)?red:(gfLegState[0]==1||gfLegState[1]==1)?amber:grey);
      string pos="FLAT"; color pc=grey;
      if(gfOwnedN>0 && PositionSelectByTicket(gfOwned[0]))
      {
         bool lg=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
         pos=StringFormat("%s %.2f | P/L %.2f | SL %s",lg?"LONG":"SHORT",gfOwnedVol,PositionGetDouble(POSITION_PROFIT),PositionGetDouble(POSITION_SL)>0?DoubleToString(PositionGetDouble(POSITION_SL),_Digits):"--");
         pc=lg?green:red;
      }
      GfPanelLabel("POS",x+8,y+174,"Pos    "+pos,8,pc);
      GfPanelLabel("SZ",x+8,y+192,StringFormat("Recovery %s | owned %d",gfRecoveryReady?"ready":"WAIT",gfOwnedN),8,gfRecoveryReady?grey:amber);
      GfPanelLabel("NOTE",x+8,y+210,"Note   "+StringSubstr(gfNote==""?"-":gfNote,0,40),8,amber);
   }
   bool redraw=gfPanelDirty || gfVisualWrites!=writes; gfPanelDirty=false;
   if(redraw) ChartRedraw(0);
}
void GfPanelStop()
{
   if(!gfPanelStarted) return;
   GfPanelDelete();
   ChartSetInteger(0,CHART_EVENT_OBJECT_CREATE,gfOldObjEvents);
   ChartSetInteger(0,CHART_FOREGROUND,gfOldForeground);
   gfPanelStarted=false;
}
#endif
