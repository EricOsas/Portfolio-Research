//+------------------------------------------------------------------+
//|                                                      ADXPane.mq5 |
//| Copyright 2026-2027, Osamwonyi Eric (You_FoundEric)              |
//| https://x.com/You_FoundEric                                      |
//+------------------------------------------------------------------+
#property copyright   "Copyright 2026-2027, Osamwonyi Eric (You_FoundEric)"
#property link        "https://x.com/You_FoundEric"
#property strict
#property indicator_separate_window
#property indicator_buffers 2
#property indicator_plots 1
#property indicator_type1 DRAW_COLOR_HISTOGRAM
#property indicator_color1 clrGray,clrSeaGreen
#property indicator_width1 2
#property indicator_label1 "ADX14"
#property indicator_level1 20
#property indicator_levelcolor clrGoldenrod
#define VWP_INDICATOR_CORE
#include "StrategyEngine.mqh"
input int AdxPeriod=14;
input string PaneName="VWAP Pullback ADX";
double values[],colors[];
datetime ends[];
double computed[],previousValues[];
bool readyValues[];
VWPWilder engine;
datetime last=0;
int OnInit()
{
   if(AdxPeriod!=14)return INIT_PARAMETERS_INCORRECT;
   SetIndexBuffer(0,values,INDICATOR_DATA);SetIndexBuffer(1,colors,INDICATOR_COLOR_INDEX);
   ArraySetAsSeries(values,false);ArraySetAsSeries(colors,false);
   PlotIndexSetDouble(0,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   IndicatorSetString(INDICATOR_SHORTNAME,PaneName);return INIT_SUCCEEDED;
}
int Find(datetime end)
{
   int left=0,right=ArraySize(ends);
   while(left<right){int mid=left+(right-left)/2;if(ends[mid]<=end)left=mid+1;else right=mid;}
   return left-1;
}
int OnCalculate(const int total,const int previous,const datetime &time[],const double &open[],
 const double &high[],const double &low[],const double &close[],const long &tickVolume[],const long &volume[],const int &spread[])
{
   if(total<=0)return 0;
   ArraySetAsSeries(time,false);
   datetime current=iTime(_Symbol,PERIOD_M1,0);
   if(current<=0)return previous;
   if(previous==0){engine.Reset();last=0;ArrayResize(ends,0);ArrayResize(computed,0);ArrayResize(previousValues,0);ArrayResize(readyValues,0);}
   MqlRates bars[];ArraySetAsSeries(bars,false);
   datetime from=last>0?last+60:time[0]-3*86400;
   int n=last<current-60?CopyRates(_Symbol,PERIOD_M1,from,current-60,bars):0;
   if(n<0)return previous;
   int old=ArraySize(ends);
   ArrayResize(ends,old+n);ArrayResize(computed,old+n);ArrayResize(previousValues,old+n);ArrayResize(readyValues,old+n);
   for(int i=0;i<n;i++){engine.Push(bars[i]);ends[old+i]=bars[i].time+60;computed[old+i]=engine.Value;previousValues[old+i]=engine.Previous;readyValues[old+i]=engine.Ready();last=bars[i].time;}
   int start=previous>0?MathMax(0,previous-2):0;
   for(int i=start;i<total;i++)
   {
      datetime end=MathMin(time[i]+PeriodSeconds((ENUM_TIMEFRAMES)_Period),current);
      int index=Find(end);
      values[i]=index>=0?computed[index]:EMPTY_VALUE;
      colors[i]=index>=0 && readyValues[index] && computed[index]>20 && computed[index]<=previousValues[index]?1:0;
   }
   return total;
}

