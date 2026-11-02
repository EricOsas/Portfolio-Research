#property strict
#property tester_no_cache
#property version "1.21"
#property description "NQ Precision. Completed-M1 filters, tick decisions, cost-inclusive cash risk and portfolio owned-position recovery."
#include <Trade/Trade.mqh>
#ifndef NQP_STRATEGY_CORE
#define NQP_STRATEGY_CORE
// Weekly-open clock: live server/GMT detection; tester weekly-open anchor.
// No broker whitelist or fixed tester fallback.
const int CLOCK_UNKNOWN=100000;
int clockServerNY=0;
bool clockReady=false;
datetime clockObserved=0;
datetime clockWeeks[];
int clockWeekOffsets[];
int NQPWeekendOffset(datetime previous,datetime opening)
{
   int raw=(int)((long)opening%86400)-18*3600;
   int offset=(int)MathRound((double)raw/900.0)*900;
   // Validate in NY time so an eastern server's Saturday close is accepted.
   for(int wrap=-1;wrap<=1;wrap++)
   {
      int candidate=offset+wrap*86400;
      if(candidate< -8*3600 || candidate>19*3600) continue;
      MqlDateTime before,after;
      TimeToStruct(previous-candidate,before);TimeToStruct(opening-candidate,after);
      if(before.day_of_week==5 && after.day_of_week==0) return candidate;
   }
   return CLOCK_UNKNOWN;
}
int NQPWeekAnchorOffset(datetime stamp)
{
   MqlDateTime d;TimeToStruct(stamp,d);d.hour=0;d.min=0;d.sec=0;
   datetime week=StructToTime(d)-d.day_of_week*86400;
   for(int k=0;k<ArraySize(clockWeeks);k++)
      if(clockWeeks[k]==week) return clockWeekOffsets[k];
   MqlRates hours[];ArraySetAsSeries(hours,false);
   int count=CopyRates(_Symbol,PERIOD_H1,stamp-22*86400,stamp,hours);
   for(int i=count-1;i>0;i--)
   {
      if(hours[i].time-hours[i-1].time<40*3600) continue;
      // Same 18:00 New York weekly reopening reference used by the session clock.
      MqlRates minutes[];ArraySetAsSeries(minutes,false);
      datetime last=MathMin(stamp,hours[i].time+3599);
      if(CopyRates(_Symbol,PERIOD_M1,hours[i].time,last,minutes)<=0) continue;
      datetime opening=minutes[0].time;
      int offset=NQPWeekendOffset(hours[i-1].time,opening);
      if(offset==CLOCK_UNKNOWN) continue;
      // A holiday can remove the current Fri->Sun gap. Reuse an older anchor
      // only inside the same NY DST season; do not freeze last season's offset.
      if(hours[i].time<week
         && NQPExpectedBrokerUTC(opening-offset+5*3600)!=NQPExpectedBrokerUTC(stamp-offset+5*3600)) continue;
      int n=ArraySize(clockWeeks);ArrayResize(clockWeeks,n+1);ArrayResize(clockWeekOffsets,n+1);
      clockWeeks[n]=week;clockWeekOffsets[n]=offset;return offset;
   }
   return CLOCK_UNKNOWN;
}
int NQPServerNYOffsetSec(datetime stamp)
{
   if(InpResearchUTC)return -(NQPExpectedBrokerUTC(stamp)-7)*3600;
   if(MQLInfoInteger(MQL_TESTER)) return NQPWeekAnchorOffset(stamp);
   datetime utc=TimeGMT(),server=TimeTradeServer();
   if(server<=0 || utc<=0) return CLOCK_UNKNOWN;
   int raw=(int)(server-utc),offset=(int)MathRound((double)raw/900.0)*900;
   if(MathAbs(raw-offset)>120 || offset< -12*3600 || offset>14*3600) return CLOCK_UNKNOWN;
   if(MathAbs((double)(stamp-server))>7*86400)
      return NQPWeekAnchorOffset(stamp);
   return offset-(NQPExpectedBrokerUTC(stamp-offset)-7)*3600;
}
bool NQPClockRefresh(datetime stamp)
{
   if(clockReady && stamp>=clockObserved && stamp-clockObserved<60) return true;
   int offset=NQPServerNYOffsetSec(stamp);
   bool announce=!clockReady || offset!=clockServerNY;
   clockReady=offset!=CLOCK_UNKNOWN;
   if(!clockReady) return false;
   if(announce) PrintFormat("NQP_CLOCK_READY serverAheadOfNYMinutes=%d source=%s",offset/60,MQLInfoInteger(MQL_TESTER) ? "weekly opening anchor" : "live server/GMT");
   clockServerNY=offset;clockObserved=stamp;return true;
}
datetime NQPNewYorkAtOffset(datetime server,int offset){return server-offset;}
datetime NQPSessionAtOffset(datetime centralDay,int minute,int offset){return centralDay+offset+3600+minute*60;}
datetime NQPNewYork(datetime server)
{
   int offset=NQPServerNYOffsetSec(server);
   return offset==CLOCK_UNKNOWN ? 0 : NQPNewYorkAtOffset(server,offset);
}
datetime NQPNewYorkUTC(datetime utc){return utc+(NQPExpectedBrokerUTC(utc)-7)*3600;}
datetime NQPCentralUTC(datetime utc){return utc+(NQPExpectedBrokerUTC(utc-3600)-8)*3600;}
datetime NQPClockUTC(datetime server)
{
   if(!MQLInfoInteger(MQL_TESTER) && MathAbs((double)(server-TimeTradeServer()))<=7*86400)
   {
      int offset=(int)MathRound((double)(TimeTradeServer()-TimeGMT())/900.0)*900;
      return server-offset;
   }
   datetime ny=NQPNewYork(server);
   if(ny<=0) return 0;
   datetime utc=ny+5*3600;
   return ny-(NQPExpectedBrokerUTC(utc)-7)*3600;
}
datetime NQPCentral(datetime server){datetime utc=NQPClockUTC(server);return utc>0 ? NQPCentralUTC(utc) : 0;}
datetime NQPSessionTime(datetime centralDay,int minute=0)
{
   int offset=NQPServerNYOffsetSec(centralDay+minute*60+clockServerNY+3600);
   if(offset==CLOCK_UNKNOWN && clockReady && MathAbs((double)(centralDay-TimeCurrent()))<3*86400) offset=clockServerNY;
   if(offset==CLOCK_UNKNOWN) return 0;
   datetime result=NQPSessionAtOffset(centralDay,minute,offset);
   int resolved=NQPServerNYOffsetSec(result);
   return NQPSessionAtOffset(centralDay,minute,resolved==CLOCK_UNKNOWN ? offset : resolved);
}

datetime NQPDay(datetime server)
{
   MqlDateTime p; TimeToStruct(NQPCentral(server),p);
   p.hour=0; p.min=0; p.sec=0;
   return StructToTime(p);
}
int NQPMinute(datetime server)
{
   MqlDateTime p; TimeToStruct(NQPCentral(server),p);
   return p.hour*60+p.min;
}
bool NQPAllowed(datetime server) {return server>=D'2019.09.01';}
bool NQPEligible(int minute,int cutoff) {return minute>=0 && minute<cutoff;}
datetime NQPCalendarDate(int y,int m,int d)
{
   MqlDateTime p={};p.year=y;p.mon=m;p.day=d;return StructToTime(p);
}
int NQPCalendarWeekday(datetime t){MqlDateTime p;TimeToStruct(t,p);return p.day_of_week;}
datetime NQPObserved(datetime t)
{
   int w=NQPCalendarWeekday(t);return t+(w==6 ? -86400 : w==0 ? 86400 : 0);
}
datetime NQPMonday(int y,int month,int n)
{
   datetime t=NQPCalendarDate(y,month,1);
   return t+((8-NQPCalendarWeekday(t))%7+7*(n-1))*86400;
}
bool NQPFutureSpecialDay(datetime d)
{
   MqlDateTime p;TimeToStruct(d,p);int y=p.year;
   datetime mayEnd=NQPCalendarDate(y,6,1)-86400;
   datetime memorial=mayEnd-((NQPCalendarWeekday(mayEnd)+6)%7)*86400;
   // Gregorian Easter, then Good Friday. Calendar-only; no market-data inputs.
   int a=y%19,b=y/100,c=y%100,e=b%4,f=(b+8)/25,g=(b-f+1)/3;
   int h=(19*a+b-b/4-g+15)%30,i=c/4,k=c%4,l=(32+2*e+2*i-h-k)%7;
   int m=(a+11*h+22*l)/451,n=h+l-7*m+114;
   datetime friday=NQPCalendarDate(y,n/31,n%31+1)-2*86400;
   datetime nov=NQPCalendarDate(y,11,1);
   datetime thanks=nov+((11-NQPCalendarWeekday(nov))%7+21)*86400;
   return d==NQPObserved(NQPCalendarDate(y,1,1)) || d==NQPMonday(y,1,3)
      || d==NQPMonday(y,2,3) || d==friday || d==memorial
      || d==NQPObserved(NQPCalendarDate(y,6,19)) || d==NQPCalendarDate(y,7,3)
      || d==NQPObserved(NQPCalendarDate(y,7,4)) || d==NQPMonday(y,9,1)
      || d==thanks || d==thanks+86400 || d==NQPCalendarDate(y,12,24)
      || d==NQPObserved(NQPCalendarDate(y,12,25)) || d==NQPCalendarDate(y,12,31);
}
int NQPExpectedBrokerUTC(datetime utc)
{
   MqlDateTime p;TimeToStruct(utc,p);
   datetime march=NQPCalendarDate(p.year,3,1),nov=NQPCalendarDate(p.year,11,1);
   datetime start=march+((7-NQPCalendarWeekday(march))%7+7)*86400+7*3600;
   datetime finish=nov+(7-NQPCalendarWeekday(nov))%7*86400+6*3600;
   return utc>=start && utc<finish ? 3 : 2;
}
bool NQPCalendarSelfTest()
{
   return NQPNewYorkAtOffset(D'2022.01.24 08:00',7*3600)==D'2022.01.24 01:00'
      && NQPNewYorkAtOffset(D'2022.01.24 08:00',8*3600)==D'2022.01.24 00:00'
      && NQPNewYorkAtOffset(D'2022.07.12 08:00',7*3600)==D'2022.07.12 01:00'
      && NQPNewYorkAtOffset(D'2022.07.12 08:00',8*3600)==D'2022.07.12 00:00'
      && NQPSessionAtOffset(D'2022.01.24',510,7*3600)==D'2022.01.24 16:30'
      && NQPSessionAtOffset(D'2022.07.12',600,7*3600)==D'2022.07.12 18:00'
      && NQPSessionAtOffset(D'2022.07.12',870,7*3600)==D'2022.07.12 22:30'
      && NQPSessionAtOffset(D'2022.07.12',0,7*3600)==D'2022.07.12 08:00'
      && NQPFutureSpecialDay(D'2026.04.03') && NQPFutureSpecialDay(D'2027.03.26')
      && NQPFutureSpecialDay(D'2026.11.26') && NQPFutureSpecialDay(D'2026.11.27')
      && !NQPFutureSpecialDay(D'2026.11.25')
      && NQPExpectedBrokerUTC(D'2026.03.08 06:59:59')==2
      && NQPExpectedBrokerUTC(D'2026.03.08 07:00:00')==3
      && NQPExpectedBrokerUTC(D'2026.11.01 05:59:59')==3
      && NQPExpectedBrokerUTC(D'2026.11.01 06:00:00')==2
      && NQPNewYorkUTC(D'2026.03.08 06:59:59')==D'2026.03.08 01:59:59'
      && NQPNewYorkUTC(D'2026.03.08 07:00:00')==D'2026.03.08 03:00:00'
      && NQPCentralUTC(D'2026.03.08 07:59:59')==D'2026.03.08 01:59:59'
      && NQPCentralUTC(D'2026.03.08 08:00:00')==D'2026.03.08 03:00:00'
      && NQPNewYorkUTC(D'2026.11.01 06:00:00')==D'2026.11.01 01:00:00'
      && NQPCentralUTC(D'2026.11.01 07:00:00')==D'2026.11.01 01:00:00'
      && NQPWeekendOffset(D'2022.07.08 20:00',D'2022.07.10 22:05')==4*3600
      && NQPWeekendOffset(D'2022.01.22 11:00',D'2022.01.24 13:00')==19*3600;
}
int NQPSessionCutoff(datetime server)
{
   // Policy v1: 11:55 Central on published US cash-market holidays/early
   // closes, plus conservative Christmas Eve and year-end handling.
   // This is an earlier research deadline, not the CFD's exact close time.
   string dates=
      "|2020.01.01|2020.01.20|2020.02.17|2020.04.10|2020.05.25|2020.07.03|2020.09.07|2020.11.26|2020.11.27|2020.12.24|2020.12.25|2020.12.31"
      "|2021.01.01|2021.01.18|2021.02.15|2021.04.02|2021.05.31|2021.07.05|2021.09.06|2021.11.25|2021.11.26|2021.12.24|2021.12.31"
      "|2022.01.17|2022.02.21|2022.04.15|2022.05.30|2022.06.20|2022.07.04|2022.09.05|2022.11.24|2022.11.25|2022.12.24|2022.12.26|2022.12.31"
      "|2023.01.02|2023.01.16|2023.02.20|2023.04.07|2023.05.29|2023.06.19|2023.07.03|2023.07.04|2023.09.04|2023.11.23|2023.11.24|2023.12.24|2023.12.25|2023.12.31"
      "|2024.01.01|2024.01.15|2024.02.19|2024.03.29|2024.05.27|2024.06.19|2024.07.03|2024.07.04|2024.09.02|2024.11.28|2024.11.29|2024.12.24|2024.12.25|2024.12.31"
      "|2025.01.01|2025.01.09|2025.01.20|2025.02.17|2025.04.18|2025.05.26|2025.06.19|2025.07.03|2025.07.04|2025.09.01|2025.11.27|2025.11.28|2025.12.24|2025.12.25|2025.12.31|";
   if(StringFind(dates,"|"+TimeToString(NQPDay(server),TIME_DATE)+"|")>=0) return 715;
   if(NQPDay(server)>=D'2026.01.01' && NQPFutureSpecialDay(NQPDay(server))) return 715;
   return 870;
}
bool NQPBracket(int side,double entry,double stop,double target)
{
   return side*(entry-stop)>0 && side*(target-entry)>0;
}
// Closed M1 long-side path. A double touch resolves as stop first.
int NQPVirtualExit(double low,double high,double stop,double target)
{
   if(low<=stop) return -1;
   if(high>=target) return 1;
   return 0;
}
bool NQPCanEnter(int minute,int start,int cutoff,int count,int cap)
{
   return minute>=start && NQPEligible(minute,cutoff) && count<cap;
}
#endif
#ifndef NQP_STRATEGY_BAR_TRAIL
#define NQP_STRATEGY_BAR_TRAIL
// Original R = actual fill to original stop. Only completed M1 closes advance peak.
bool NQPBarTrailLock(double peakR,double activateR,double distanceR,double stepR,double &lockR)
{
   if(activateR<=0 || distanceR<=0 || stepR<=0 || peakR<activateR) return false;
   lockR=activateR+MathFloor((peakR-activateR)/stepR+1e-9)*stepR-distanceR;
   return true;
}
bool NQPBarTrailSelfTest()
{
   double lock=0;
   if(NQPBarTrailLock(1.499,1.5,1.5,.5,lock)) return false;
   double peaks[]={1.5,1.999,2.0,2.499,2.5,3.0};
   double expected[]={0.0,0.0,.5,.5,1.0,1.5};
   for(int i=0;i<ArraySize(peaks);i++)
      if(!NQPBarTrailLock(peaks[i],1.5,1.5,.5,lock) || MathAbs(lock-expected[i])>1e-9) return false;
   return !NQPBarTrailLock(2.0,1.5,1.5,0,lock)
      && NQPVirtualExit(99,111,100,110)==-1
      && NQPVirtualExit(100,109,100,110)==-1
      && NQPVirtualExit(101,110,100,110)==1
      && NQPVirtualExit(101,109,100,110)==0;
}
#endif

enum NQPGeometry { SourceGeometry=0, ATRGeometry=1 };
enum NQPManagement { FixedBracket=0, CostCoveredBE=2, ATRTrail=3, M1RStep=4 };
// Numeric strategy id written to the trade export's model column (schema compatibility).
const int NQPModelId=2;
#ifndef NQP_STRATEGY_PRODUCTION_INPUTS
#define NQP_STRATEGY_PRODUCTION_INPUTS

input group "==========  1 - Trading  =========="
input bool   EnableTrading       = true;  // Enable new trades (open trades stay protected when off)
input bool   BlockOpposingExposure = true; // Also check the visible index family; exact-symbol isolation is always on

input group " "
input group "==========  2 - Risk  =========="
input double RiskMoney           = 100.0; // Risk per trade, including costs (account currency)
input bool   UseFixedSize        = false; // Use fixed lots instead of the cash risk budget
input double FixedLots           = 1.0;   // Lots per trade when fixed sizing is enabled

input group "  "
input group "==========  3 - Trading Costs  =========="
input double CommissionPerLot    = 0.0;   // ICMarkets index CFD: costs are embedded in spread; 7.0 was original fallback (double-charges on CFD)
input int    SlippagePoints      = 3;     // Slippage/side (3=0.03 if broker Point=0.01)

// Frozen strategy rules: not user-facing options or alternate models.
const int ATRPeriod=14,ADXPeriod=14;
const double NoiseFraction=0.30,StopPoints=60.0,TargetPoints=40.0,TargetR=3.0;
const int NQPStateRevision=3;
// Indicator warm-up lead-in: M1 history is loaded this many seconds before the session start so the Wilder ATR/RVOL
// seed matches the reviewed research. Changing it changes ATR values and therefore signals.
const int NQPWarmupLeadSeconds=3600;
const bool SyntheticFirst=false;
const NQPManagement Management=FixedBracket;
const double BarTrailActivateR=1.5,BarTrailDistanceR=1.5;
const string NQPDisplayName="NQ Precision";

input group "   "
input group "==========  4 - Display  =========="
input bool   ShowVisuals         = true;  // Show chart levels, trade markers and information

input group "    "
input group "==========  5 - Execution & Logging  =========="
const ulong  MagicNumber         = 1095958; // Fixed model identity; preserves owned-position recovery
input bool   WriteTradeLog       = true;  // Write a detailed trade and decision log


// Private adapter to the existing, validated execution engine.
const int StartMinute=600;
const double RiskCash=RiskMoney,CommissionRTPerLot=CommissionPerLot,SlipPrice=SlippagePoints*_Point;
const ulong Magic=MagicNumber;
const bool DetailedLog=WriteTradeLog;
const NQPGeometry Geometry=SourceGeometry;
const double BreakEvenR=0.5,TrailR=1.0,BarTrailStepR=0.5;
string RunId="";
#endif

const string NQPOutputFamily="NQPrecision";
const string NQPOutputRoot=NQPOutputFamily+"/logs";
void NQPPrepareOutput()
{
   FolderCreate(NQPOutputFamily,FILE_COMMON);
   FolderCreate(NQPOutputRoot,FILE_COMMON);
}

CTrade trade;
int atrHandle=INVALID_HANDLE, adxHandle=INVALID_HANDLE, ledger=INVALID_HANDLE;
ENUM_TIMEFRAMES sourceTF=PERIOD_M1;
datetime lastMinute=0,lastSignal=0,day=0;
double averageATR=0,midnight=0,orHigh=0,orLow=0;
double initialRisk=0,modelCost=0,totalCost=0;
double modelCostPerLot=0,entryCommissionPerLot=0;
datetime ownedEntryTime=0;
string carryDetails="";
int entries=0,daysReady=0,daysRejected=0,invalidBrackets=0,failedOrders=0;
bool rangeReady=false,armed=false,touched=false,waitingFresh=false,dayValid=false,beDone=false;
bool previousORAbove=false;
bool dayWaiting=false,dayRejected=false;
string dataWaitReason="";
bool virtualActive=false;
double virtualStop=0,virtualTarget=0;
datetime virtualStart=0;
datetime virtualLastBar=0;
int virtualStarts=0,virtualStops=0,virtualTargets=0,virtualCollisions=0;
int virtualExpired=0,virtualGaps=0;
double barPeakR=0;
double yearProfit[7],worstRisk=0,netWins=0,netLosses=0,adjustedPeak=0,adjustedDD=0;
int yearTrades[7];
int resultsFile=INVALID_HANDLE;
double dailyNet[2557];
string rejectedDetails="";
#ifdef NQP_VISUAL_PROBE
bool nqvPreviewRequested=false;
ulong nqvPreviewRequestedMs=0;
#endif

input group "     "
input group "==========  6 - NQ Signal & Research  =========="
enum NQDataContract { NativeChartData=0, LastTradeRealVolume=1, BidQuoteTickVolume=2 };
bool NQUsesTradeData(int requested,int chartMode,int calculationMode)
{
   if(requested!=NativeChartData)return requested==LastTradeRealVolume;
   if(calculationMode==SYMBOL_CALC_MODE_CFD || calculationMode==SYMBOL_CALC_MODE_CFDINDEX
      || calculationMode==SYMBOL_CALC_MODE_CFDLEVERAGE)return false;
   return chartMode==SYMBOL_CHART_MODE_LAST;
}
input NQDataContract SignalData=NativeChartData; // Automatic symbol data contract; explicit research overrides
input bool InpUseTickHistory=true; // Tick-derived ETH M1; false uses stored M1 approximation
input bool InpResearchUTC=false; // UTC imported research tape; otherwise portfolio automatic broker clock
input int InpAtrPeriod=14;
input int InpAtrRegimeLen=50;
input double InpAtrSlMult=2.2;
input double InpAtrTpMult=0.8;  // 0.3 was original default (tight scalp); 0.8 is OptB winner (2020–2026 sweep, PF 1.37 vs 0.88 baseline)
input bool   InpInvertSignal=false; // Invert trade direction (Counter-scalp / Market-maker mode)
input bool InpUseTimeClose=true;
input int InpCloseAfterMin=8;
input bool InpUseFilters=true;
input int InpRvolLen=14;
input double InpRvolMin=0.5;
input double InpRvolMax=1.5;
input double InpRegimeMin=1.0;
input double InpRegimeMax=2.5;
input int InpRangeStart=93000;
input int InpRangeEnd=94500;
input bool InpUseTriggerTime=true;
input int InpTriggerTime=95955;
input int InpTradeUntil=110000;

struct NQTickMinuteState
{
   bool forming;
   MqlRates bar;
   long last_msc;
   datetime closed_through;
};
bool nqTradeData=true,nqRestored=false,nqIndicatorsReady=false;
int nqDecisionDay=0,nqRangeBars=0;
string nqLastSkip="";
int nqSkipDay=0;
double         m_atr=0.0,m_atrLong=0.0,m_previousClose=0.0;
int            m_atrCount=0,m_volumeCount=0,m_volumeHead=0;
double         m_volumeRing[],m_volumeSum=0.0,m_rvol=0.0;

int            m_currentDayDate = 0;
double         m_rangeHigh      = 0.0;
double         m_rangeLow       = 0.0;
bool           m_haveRange      = false;
bool           m_rangeLocked    = false;
bool           m_tradedToday    = false;

long           m_entryTime      = 0; // Actual POSITION_TIME_MSC, not request submission time.
double         m_entryPrice     = 0.0;
int            m_entrySide      = 0;
datetime       m_lastBarTime    = 0;
datetime       m_observationStart=0;
NQTickMinuteState m_tickMinute;
datetime       m_tickHistoryCursor=0,m_tickHistoryRetryAfter=0;
int            m_pendingDirection=0;
double         m_pendingLots=0,m_pendingStop=0,m_pendingTarget=0;
ulong          m_pendingClose=0;
bool           nqTimeContractKnown=false,nqTimeEnabled=false;
int            nqTimeMinutes=0;
long           nqTradeDeadlineMsc=0;
ulong          nqVerifiedPositionId=0;
long           nqVerifiedOpenTime=0;


double NQWilder(double previous,double tr,int count,int period)
{int n=(int)MathMin(count,period);return count==1 ? tr : ((n-1)*previous+tr)/n;}
double NQCrossing(double price,double tick,bool upward)
{return tick*(upward ? MathCeil(price/tick-1e-9) : MathFloor(price/tick+1e-9));}
bool NQEthMinute(const int weekday,const int seconds)
{
   if(weekday==0)return seconds>18*3600;
   if(weekday==6)return false;
   if(weekday==5)return seconds<=17*3600;
   return seconds<=17*3600 || seconds>18*3600;
}
bool NQSignalMinuteEligible(const datetime start)
{
   MqlDateTime et;TimeToStruct(NQPNewYork(start+60),et);
   return NQEthMinute(et.day_of_week,et.hour*3600+et.min*60+et.sec);
}
bool NQTickMinuteClose(NQTickMinuteState &state,const datetime at,MqlRates &completed)
{
   datetime boundary=at-at%60;
   if(boundary>state.closed_through)state.closed_through=boundary;
   if(!state.forming || state.bar.time+60>at)return false;
   completed=state.bar;state.forming=false;
   return true;
}
bool NQTickMinutePush(NQTickMinuteState &state,const MqlTick &tick,const bool tradeData,MqlRates &completed)
{
   if(tradeData && (tick.flags & (TICK_FLAG_LAST|TICK_FLAG_VOLUME|TICK_FLAG_BUY|TICK_FLAG_SELL))==0)return false;
   double price=tradeData ? tick.last : tick.bid;
   if(price<=0 || !MathIsValidNumber(price))return false;
   long stamp=tick.time_msc>0 ? tick.time_msc : (long)tick.time*1000;
   datetime at=(datetime)(stamp/1000);
   if(stamp<state.last_msc || at<state.closed_through)return false;
   bool ready=NQTickMinuteClose(state,at,completed);
   state.last_msc=stamp;
   if(!state.forming)
   {
      ZeroMemory(state.bar);state.bar.time=at-at%60;
      state.bar.open=price;state.bar.high=price;state.bar.low=price;state.forming=true;
   }
   state.bar.high=MathMax(state.bar.high,price);state.bar.low=MathMin(state.bar.low,price);
   state.bar.close=price;state.bar.tick_volume++;
   if(tradeData)state.bar.real_volume+=(long)(tick.volume_real>0 ? tick.volume_real : (double)tick.volume);
   return ready;
}
void NQAppendMinute(MqlRates &bars[],const MqlRates &bar)
{
   if(!NQSignalMinuteEligible(bar.time))return;
   int n=ArraySize(bars);ArrayResize(bars,n+1);bars[n]=bar;
}
bool NQReadTickMinutes(const datetime from,const datetime until,NQTickMinuteState &state,MqlRates &bars[])
{
   ArrayResize(bars,0);
   if(until<=from || from%60!=0 || until%60!=0)return false;
   MqlTick ticks[];ResetLastError();
   int count=CopyTicksRange(_Symbol,ticks,COPY_TICKS_ALL,(ulong)from*1000,(ulong)until*1000-1);
   if(count<0 || GetLastError()!=0)return false;
   for(int i=0;i<count;i++)
   {
      MqlRates completed;
      if(NQTickMinutePush(state,ticks[i],nqTradeData,completed))NQAppendMinute(bars,completed);
   }
   MqlRates completed;
   if(NQTickMinuteClose(state,until,completed))NQAppendMinute(bars,completed);
   return true;
}
datetime NQTickHistoryAnchor(const datetime before)
{
   int available=Bars(_Symbol,PERIOD_M1);
   if(available<=0)return 0;
   datetime anchor=iTime(_Symbol,PERIOD_M1,(int)MathMin(9999,available-1));
   return anchor>0 && anchor<before ? anchor-anchor%60 : 0;
}
bool NQUpdateTickMinutes(const datetime now)
{
   datetime through=now-now%60;
   if(m_tickHistoryCursor>=through)return m_tickHistoryCursor>0;
   if(now<m_tickHistoryRetryAfter)return false;
   if(m_tickHistoryCursor==0)
   {
      m_tickHistoryCursor=NQTickHistoryAnchor(through);
      if(m_tickHistoryCursor==0){m_tickHistoryRetryAfter=now+1;return false;}
   }
   // Whole intervals retain every equal-millisecond print without a partial tick cursor.
   for(int budget=0;budget<4 && m_tickHistoryCursor<through;budget++)
   {
      datetime end=(datetime)MathMin((double)through,(double)m_tickHistoryCursor+3600);
      MqlRates bars[];
      if(!NQReadTickMinutes(m_tickHistoryCursor,end,m_tickMinute,bars))
      {m_tickHistoryRetryAfter=now+1;return false;}
      for(int i=0;i<ArraySize(bars);i++)CompletedMinute(bars[i]);
      m_tickHistoryCursor=end;
   }
   bool ready=m_tickHistoryCursor>=through;
   if(ready)NQPHistoricalSessions(now);
   return ready;
}
datetime ServerTimeToEt(datetime stamp){return NQPNewYork(stamp);}
int GetEtHHMMSS(datetime serverTime)
{
   datetime et = ServerTimeToEt(serverTime);
   MqlDateTime dt;
   TimeToStruct(et, dt);
   return (dt.hour * 10000 + dt.min * 100 + dt.sec);
}
int GetEtDateNum(datetime serverTime)
{
   datetime et = ServerTimeToEt(serverTime);
   MqlDateTime dt;
   TimeToStruct(et, dt);
   return (dt.year * 10000 + dt.mon * 100 + dt.day);
}
void ResetDaily()
{
   m_rangeHigh   = 0.0;
   m_rangeLow    = 0.0;
   m_haveRange   = false;
   m_rangeLocked = false;
   m_tradedToday = false;
   nqRangeBars=0;m_volumeCount=0;m_volumeHead=0;m_volumeSum=0;m_rvol=0;
   ArrayInitialize(m_volumeRing,0.0);
}
bool CheckFilters(double &atrVal)
{
   atrVal=m_atr;
   if(m_atrCount<MathMax(InpAtrPeriod,InpAtrRegimeLen) || m_atr<=0 || m_atrLong<=0)return false;
   if(!InpUseFilters)return true;
   double regime=m_atr/m_atrLong;
   return m_volumeCount>=InpRvolLen && m_rvol>=InpRvolMin && m_rvol<=InpRvolMax
          && regime>=InpRegimeMin && regime<=InpRegimeMax;
}
void CompletedMinute(const MqlRates &bar)
{
   int barDay=GetEtDateNum(bar.time);
   if(barDay!=m_currentDayDate){m_currentDayDate=barDay;ResetDaily();}
   double tr=bar.high-bar.low;
   if(m_atrCount>0)tr=MathMax(tr,MathMax(MathAbs(bar.high-m_previousClose),MathAbs(bar.low-m_previousClose)));
   m_atrCount++;
   m_atr=NQWilder(m_atr,tr,m_atrCount,InpAtrPeriod);
   m_atrLong=NQWilder(m_atrLong,tr,m_atrCount,InpAtrRegimeLen);
   m_previousClose=bar.close;
   // Real contract volume is required. Tick-count volume is a different input contract.
   double volume=(double)(nqTradeData ? bar.real_volume : bar.tick_volume);
   m_volumeSum-=m_volumeRing[m_volumeHead];m_volumeRing[m_volumeHead]=volume;m_volumeSum+=volume;
   m_volumeHead=(m_volumeHead+1)%InpRvolLen;m_volumeCount=(int)MathMin(m_volumeCount+1,InpRvolLen);
   m_rvol=m_volumeCount==InpRvolLen && m_volumeSum>0 ? volume*InpRvolLen/m_volumeSum : 0;
   int clock=GetEtHHMMSS(bar.time);
   // Indicator warmup is not evidence that the strategy observed a past opening range.
   if(bar.time>=m_observationStart && clock>=InpRangeStart && clock<InpRangeEnd)
   {
      nqRangeBars++;m_rangeHigh=m_haveRange ? MathMax(m_rangeHigh,bar.high) : bar.high;
      m_rangeLow=m_haveRange ? MathMin(m_rangeLow,bar.low) : bar.low;m_haveRange=true;
   }
   m_lastBarTime=bar.time;
}
bool UpdateClosedMinutes(const datetime now)
{
   if(InpUseTickHistory)return NQUpdateTickMinutes(now);
   datetime latest=iTime(_Symbol,PERIOD_M1,1);
   if(latest==0)return false;
   if(latest==m_lastBarTime)return true;
   MqlRates rates[];ArraySetAsSeries(rates,false);
   int count=m_lastBarTime==0 ? CopyRates(_Symbol,PERIOD_M1,1,10000,rates)
                            : CopyRates(_Symbol,PERIOD_M1,m_lastBarTime+60,now,rates);
   if(count<=0)return false;
   for(int i=0;i<count;i++)if(rates[i].time>m_lastBarTime && rates[i].time+60<=now)CompletedMinute(rates[i]);
   // Publish the completed-minute range even while signal/entry gates return early.
   // Run once after catch-up, never once for every warmup candle.
   NQPHistoricalSessions(now);
   return m_lastBarTime==latest;
}
void NQSkip(string why)
{
   int today=GetEtDateNum(TimeCurrent());
   if(why==nqLastSkip && today==nqSkipDay)return;
   nqLastSkip=why;nqSkipDay=today;
   PrintFormat("NQPB SKIP %s NY=%s ATR=%.8f regime=%.8f rvol=%.8f",why,
      TimeToString(NQPNewYork(TimeCurrent()),TIME_DATE|TIME_SECONDS),m_atr,m_atrLong>0 ? m_atr/m_atrLong : 0,m_rvol);
   Note("NO_ENTRY",why);
}
int NQRequiredRangeBars()
{
   int start=InpRangeStart/10000*3600+(InpRangeStart/100%100)*60+InpRangeStart%100;
   int end=InpRangeEnd/10000*3600+(InpRangeEnd/100%100)*60+InpRangeEnd%100;
   return (end+59)/60-(start+59)/60;
}
void NQManageTimeClose(datetime now)
{
   // Portfolio timer hook: ordinary NQ exits remain queued to actual ticks.
   // OnTimer still reconciles durable close requests and broker protection.
}

#include "ChartVisuals.mqh"
#include "ExecutionRuntime.mqh"

bool OwnPosition()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket>0 && PositionGetString(POSITION_SYMBOL)==_Symbol && (ulong)PositionGetInteger(POSITION_MAGIC)==Magic)
         return true;
   }
   return false;
}
bool NQTimeCloseDue(long nowMsc)
{
   if(!OwnPosition())return false;
   if(!NQSelectedOwned((ulong)PositionGetInteger(POSITION_TICKET)))return false;
   if(!nqTimeContractKnown)
   {runtimeBlocked=true;runtimeRecoveryHold=true;return false;}
   if(!nqTimeEnabled)return false;
   if(nqTradeDeadlineMsc==0)
   {
      long opened=PositionGetInteger(POSITION_TIME_MSC);
      if(opened<=0 || nqTimeMinutes<1){runtimeBlocked=true;runtimeRecoveryHold=true;return false;}
      nqTradeDeadlineMsc=opened+(long)nqTimeMinutes*60000;
      NQPStateSave();
   }
   return nowMsc>=nqTradeDeadlineMsc;
}
bool DateAllowed(datetime t)
{
   return true; // Tester dates belong to MT5; live operation has no research-stage lock.
}
double RoundPrice(double price)
{
   double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   return NormalizeDouble(MathRound(price/tick)*tick,_Digits);
}
void CloseOwned(string why)
{
   if(NQBrokerRestricted() || runtimeRecoveryHold)return;
   if(!MQLInfoInteger(MQL_TESTER) && !NQPRuntimeAccountContextValid()){NQPDraw();return;}
   if(!MQLInfoInteger(MQL_TESTER) && !TerminalInfoInteger(TERMINAL_CONNECTED)) return;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket>0 && PositionGetString(POSITION_SYMBOL)==_Symbol && (ulong)PositionGetInteger(POSITION_MAGIC)==Magic)
      {
         if(!RecoveryCloseBegin(NQPStateKey(),ticket))continue;
         bool closed=trade.PositionClose(ticket);uint ret=trade.ResultRetcode();
         NQObserveBrokerResult(ret,trade.ResultComment());
         RecoveryCloseResult(NQPStateKey(),ret,trade.ResultOrder());
         if(!closed || (ret!=TRADE_RETCODE_DONE && ret!=TRADE_RETCODE_DONE_PARTIAL))
         { failedOrders++; PrintFormat("NQP_CLOSE_REJECT %s ret=%u",why,trade.ResultRetcode()); }
      }
   }
}
void Note(string kind,string text)
{
   if(kind=="RECOVERY_BLOCK")Print("NQP RECOVERY ATTENTION: ",text);
   if(kind=="ENTRY_REJECT" || kind=="INVALID_BRACKET" || kind=="ENTRY_BLOCK" || kind=="RISK_TOO_SMALL" || kind=="FIXED_LOTS_INVALID" || kind=="RISK_INVALID")
      PrintFormat("NQPB %s %s",kind,text);
   if(DetailedLog && ledger!=INVALID_HANDLE)
   {
      FileWrite(ledger,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),kind,text);
      FileFlush(ledger); // Make decision events readable during visual tester diagnostics too.
   }
}
bool M1HistoryAvailable(datetime from)
{
   if(!MQLInfoInteger(MQL_TESTER) && !TerminalInfoInteger(TERMINAL_CONNECTED)) return false;
   long first=SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_FIRSTDATE);
   if(first<=0 || first>from || !SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_SYNCHRONIZED))
   {
      MqlRates preceding[];
      CopyRates(_Symbol,PERIOD_M1,from-86400,from,preceding); // Request the boundary's preceding history; retry asynchronously.
      return false;
   }
   return SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_SYNCHRONIZED) && first>0 && first<=from;
}
bool NativeBarsValid(MqlRates &bars[],datetime from,datetime to)
{
   int n=ArraySize(bars);
   if(n<=0 || bars[0].time<from || bars[n-1].time>=to) return false;
   for(int i=0;i<n;i++)
   {
      if((i>0 && bars[i].time<=bars[i-1].time) || !MathIsValidNumber(bars[i].open)
         || !MathIsValidNumber(bars[i].high) || !MathIsValidNumber(bars[i].low)
         || !MathIsValidNumber(bars[i].close) || bars[i].low>bars[i].high
         || bars[i].open<bars[i].low || bars[i].open>bars[i].high
         || bars[i].close<bars[i].low || bars[i].close>bars[i].high) return false;
   }
   return true;
}
bool Window(datetime from,datetime to,MqlRates &bars[],int minimum)
{
   ArraySetAsSeries(bars,false);
   if(to<=from || !M1HistoryAvailable(from)) return false;
   int n=CopyRates(_Symbol,PERIOD_M1,from,to-60,bars);
   // Native minute series omit minutes without a trade/quote. Use observed bars only.
   return n>0 && NativeBarsValid(bars,from,to);
}
bool OpeningPrice(datetime anchor,int minutes,double &price)
{
   if(!M1HistoryAvailable(anchor)) return false;
   datetime last=(datetime)MathMin((double)(anchor+(minutes-1)*60),(double)((long)TimeCurrent()/60*60));
   if(last<anchor) return false;
   MqlRates bars[];ArraySetAsSeries(bars,false);
   int n=CopyRates(_Symbol,PERIOD_M1,anchor,last,bars);
   if(n<=0 || !NativeBarsValid(bars,anchor,anchor+minutes*60)) return false;
   price=bars[0].open; // First observed trade in the nominal opening interval.
   return true;
}
bool RejectDay(string reason)
{
   if(!dayRejected){dayRejected=true;daysRejected++;}
   dayWaiting=true;
   if(dataWaitReason!=reason)
   {
      dataWaitReason=reason;
      rejectedDetails+=TimeToString(day,TIME_DATE)+","+reason+"\r\n";
      PrintFormat("NQP DATA_WAIT day=%s reason=%s synchronized=%d firstM1=%s; retrying, protection active",
         TimeToString(day,TIME_DATE),reason,(int)SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_SYNCHRONIZED),
         TimeToString((datetime)SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_FIRSTDATE),TIME_DATE|TIME_MINUTES));
   }
   return false;
}
void ResetDay(datetime now)
{
   day=NQPDay(now); entries=0; rangeReady=false; armed=false; touched=false;
   nqvLastEntry=0;nqvLastStop=0;nqvLastTarget=0;nqvLastBracketTime=0;
   if(NQPVisualEnabled()) ObjectsDeleteAll(0,NQPVisualPrefix());
   waitingFresh=false; previousORAbove=false; beDone=false;
   virtualActive=false;virtualStart=0;virtualLastBar=0;nqpVirtualExitTime=0;
   lastSignal=0;averageATR=0;
   dayValid=false;dayRejected=false;dataWaitReason=""; // Preserve an outstanding history/connection wait across the day boundary.
}
// Daily candles end at 17:00 New York, independent of broker midnight.
bool NQPATRMean(MqlRates &daily[],int period,double &mean)
{
   int n=ArraySize(daily);mean=0;
   if(n<period+15) return false;
   for(int end=n-1;end>=n-15;end--)
   {
      double atr=0;
      for(int i=end-period+1;i<=end;i++)
      {
         if(daily[i].high<daily[i].low || daily[i-1].close<=0) return false;
         double tr=MathMax(daily[i].high-daily[i].low,
            MathMax(MathAbs(daily[i].high-daily[i-1].close),MathAbs(daily[i].low-daily[i-1].close)));
         if(!MathIsValidNumber(tr)) return false;
         atr+=tr/period;
      }
      mean+=atr/15.0;
   }
   return mean>0 && MathIsValidNumber(mean);
}
bool NQPSessionATRMean(datetime sessionDay,double &mean,bool datedVisual=false)
{
   static datetime cachedDay=0;
   static double cachedMean=0;
   if(!datedVisual && cachedDay==sessionDay && cachedMean>0){mean=cachedMean;return true;}
   // Preserve native results on feeds whose D1 candles already use the model close.
   bool aligned=true;
   for(int i=1;i<=ATRPeriod+15;i++)
   {
      datetime open=iTime(_Symbol,PERIOD_D1,i),ny=NQPNewYork(open);
      if(open<=0 || ny<=0 || (long)ny%86400!=17*3600){aligned=false;break;}
   }
   if(aligned)
   {
      double values[];mean=0;
      int shift=datedVisual ? iBarShift(_Symbol,PERIOD_D1,NQPSessionTime(sessionDay),false)+1 : 1;
      if(shift<1 || CopyBuffer(atrHandle,0,shift,15,values)!=15) return false;
      for(int i=0;i<15;i++)
      {
         if(values[i]<=0 || !MathIsValidNumber(values[i])) return false;
         mean+=values[i]/15.0;
      }
   }
   else
   {
      // H1 OHLC preserves a daily high/low/close at an hour-aligned rollover.
      // Use M1 on fractional-hour server zones so no bar crosses that rollover.
      ENUM_TIMEFRAMES tf=clockServerNY%3600==0 ? PERIOD_H1 : PERIOD_M1;
      datetime finish=NQPSessionTime(sessionDay-86400,960);
      datetime begin=finish-90*86400;
      if(begin<=0 || finish<=begin) return false;
      MqlRates source[],daily[];ArraySetAsSeries(source,false);
      int count=CopyRates(_Symbol,tf,begin,finish-1,source);
      if(count<=0 || !SeriesInfoInteger(_Symbol,tf,SERIES_SYNCHRONIZED)) return false;
      datetime previous=0;
      for(int i=0;i<count;i++)
      {
         datetime local=NQPCentral(source[i].time);
         if(local<=0) return false;
         MqlDateTime d;TimeToStruct(local,d);
         bool afterClose=d.hour>=16;d.hour=0;d.min=0;d.sec=0;
         datetime key=StructToTime(d)+(afterClose ? 86400 : 0);
         if(key>=sessionDay) continue;
         if(key!=previous)
         {
            int n=ArraySize(daily);ArrayResize(daily,n+1);
            daily[n]=source[i];daily[n].time=key;previous=key;
         }
         else
         {
            int n=ArraySize(daily)-1;
            daily[n].high=MathMax(daily[n].high,source[i].high);
            daily[n].low=MathMin(daily[n].low,source[i].low);daily[n].close=source[i].close;
         }
      }
      // The first bucket may start partway through a day; only its closing price seeds TR.
      if(!NQPATRMean(daily,ATRPeriod,mean)) return false;
   }
   if(!datedVisual){cachedDay=sessionDay;cachedMean=mean;}return true;
}
double NQPRequestedVolume(bool fixedSize,double lots,double budget,double unitRisk,double step,double minimum,double maximum)
{
   if(unitRisk<=0 || !MathIsValidNumber(unitRisk) || step<=0 || minimum<=0 || maximum<minimum) return 0;
   if(fixedSize)
   {
      if(!MathIsValidNumber(lots) || lots<minimum || lots>maximum || MathAbs(lots/step-MathRound(lots/step))>1e-7) return 0;
      return lots;
   }
   return MathMin(MathFloor(budget/unitRisk/step+1e-9)*step,maximum);
}
string NQPSizingLabel()
{return UseFixedSize ? "Lots "+DoubleToString(FixedLots,4) : "Risk "+DoubleToString(RiskMoney,2);}
bool Open(int side,double stop,double target,double distance)
{
   if(NQBrokerRestricted() || runtimeRecoveryHold || OwnPosition())return false;
   MqlTick q;if(!SymbolInfoTick(_Symbol,q)) return false;
   double entry=(side==1 ? q.ask : q.bid);
   if(distance>0) {stop=entry-side*distance;target=entry+side*distance*TargetR;}
   stop=RoundPrice(stop);target=RoundPrice(target);
   if(!NQPBracket(side,entry,stop,target)) {invalidBrackets++;Note("INVALID_BRACKET",StringFormat("%d %f %f %f",side,entry,stop,target));return false;}
   double loss=0;
   if(!OrderCalcProfit(side==1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,_Symbol,1.0,entry,stop,loss)) return false;
   double commission=NQPCommissionEstimate();
   double friction=commission;
   double slipLoss=0;
   if(!OrderCalcProfit(ORDER_TYPE_BUY,_Symbol,1.0,entry,entry-2*SlipPrice,slipLoss)) return false;
   friction+=MathAbs(slipLoss);
   double unitRisk=MathAbs(loss)+friction;
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP),minimum=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   if(unitRisk<=0 || !MathIsValidNumber(unitRisk) || step<=0 || minimum<=0) {Note("RISK_INVALID","Invalid cash risk or volume contract");return false;}
   double volume=NQPRequestedVolume(UseFixedSize,FixedLots,RiskCash,unitRisk,step,minimum,SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX));
   if(volume<minimum || unitRisk<=0) {Note(UseFixedSize ? "FIXED_LOTS_INVALID" : "RISK_TOO_SMALL",DoubleToString(unitRisk*minimum,2));return false;}
   double stops=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
   if(side*(entry-stop)<stops || side*(target-entry)<stops){invalidBrackets++;return false;}
   entryCommissionPerLot=commission;modelCostPerLot=friction;
   // Reserve the original management contract before the entry request checkpoint.
   nqTimeContractKnown=true;nqTimeEnabled=InpUseTimeClose;nqTimeMinutes=InpCloseAfterMin;nqTradeDeadlineMsc=0;
   if(!NQPRuntimeEntryAllowed(entry,stop,target,volume,side)) {Note("ENTRY_BLOCK","EA safety, clock, margin or terminal gate");return false;}
   string comment=MQLInfoInteger(MQL_TESTER) ? NQPDisplayName : "NQP#"+IntegerToString((long)runtimeIntentNonce);
   bool ok=(side==1 ? trade.Buy(volume,_Symbol,0,stop,target,comment) : trade.Sell(volume,_Symbol,0,stop,target,comment));
   uint ret=trade.ResultRetcode();
   NQObserveBrokerResult(ret,trade.ResultComment());
   if(!ok || (ret!=TRADE_RETCODE_DONE && ret!=TRADE_RETCODE_DONE_PARTIAL))
   {
      failedOrders++;Note("ENTRY_REJECT",IntegerToString((int)ret));
      if(!MQLInfoInteger(MQL_TESTER)){entries++;runtimeBlocked=true;NQPStateSave();}
      return false;
   }
   initialRisk=MathAbs(trade.ResultPrice()-stop);beDone=false;barPeakR=0;
   double filledVolume=trade.ResultVolume()>0 ? trade.ResultVolume() : volume;
   entryCommissionPerLot=commission;modelCostPerLot=friction;modelCost=friction*filledVolume;totalCost+=modelCost;ownedEntryTime=TimeCurrent();
   entries++;worstRisk=MathMax(worstRisk,unitRisk*volume);
   NQPRememberBracket(trade.ResultPrice(),stop,target);
   NQPDrawFill(side,TimeCurrent(),trade.ResultPrice(),"Entry");
   NQPRuntimeFilled(side,stop,friction);
   Note("ENTRY",StringFormat("side=%d lots=%f fill=%f sl=%f tp=%f atr=%f count=%d modeledCost=%f",side,volume,trade.ResultPrice(),stop,target,averageATR,entries,modelCost));
   return true;
}
void Manage()
{
   if(NQBrokerRestricted() || runtimeRecoveryHold)return;
   if(Management==M1RStep) return;
   if(Management<CostCoveredBE || !OwnPosition() || initialRisk<=0) return;
   if(!NQSelectedOwned((ulong)PositionGetInteger(POSITION_TICKET)))return;
   MqlTick q;SymbolInfoTick(_Symbol,q);
   int side=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY ? 1 : -1);
   double entry=PositionGetDouble(POSITION_PRICE_OPEN),sl=PositionGetDouble(POSITION_SL),tp=PositionGetDouble(POSITION_TP);
   double current=(side==1 ? q.bid : q.ask);
   double favorable=side*(current-entry);
   double desired=sl;
   if(Management==CostCoveredBE && !beDone && favorable>=BreakEvenR*initialRisk)
   {
      double volume=PositionGetDouble(POSITION_VOLUME),unit=0;
      if(!OrderCalcProfit(ORDER_TYPE_BUY,_Symbol,1.0,entry,entry+1,unit)) return;
      desired=entry+side*(unit!=0 ? modelCost/volume/MathAbs(unit) : 0);
   }
   if(Management==ATRTrail && favorable>=TrailR*initialRisk) desired=current-side*averageATR*NoiseFraction;
   desired=RoundPrice(desired);
   if(side*(desired-sl)<=0 || side*(current-desired)<=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point) return;
   bool modified=trade.PositionModify((ulong)PositionGetInteger(POSITION_TICKET),desired,tp);
   NQObserveBrokerResult(trade.ResultRetcode(),trade.ResultComment());
   if(modified) {beDone=true;Note("STOP_CHANGE",DoubleToString(desired,_Digits));}
}
void ManageClosedMinute()
{
   if(NQBrokerRestricted() || runtimeRecoveryHold)return;
   if(Management!=M1RStep || !OwnPosition() || initialRisk<=0) return;
   if(!NQSelectedOwned((ulong)PositionGetInteger(POSITION_TICKET)))return;
   MqlRates b[];
   if(CopyRates(_Symbol,PERIOD_M1,1,1,b)!=1 || b[0].time+60<=ownedEntryTime) return;
   int side=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY ? 1 : -1;
   double entry=PositionGetDouble(POSITION_PRICE_OPEN);
   double sl=PositionGetDouble(POSITION_SL),tp=PositionGetDouble(POSITION_TP);
   ulong ticket=(ulong)PositionGetInteger(POSITION_TICKET);
   barPeakR=MathMax(barPeakR,side*(b[0].close-entry)/initialRisk);
   NQPStateSave();
   double lockR=0;
   if(!NQPBarTrailLock(barPeakR,BarTrailActivateR,BarTrailDistanceR,BarTrailStepR,lockR)) return;
   double desired=RoundPrice(entry+side*lockR*initialRisk);
   if(side*(desired-sl)<=0) return;
   MqlTick q;if(!SymbolInfoTick(_Symbol,q)) return;
   double current=side==1 ? q.bid : q.ask;
   if(side*(current-desired)<=0) {CloseOwned("M1_TRAIL_CROSSED");return;}
   double bound=MathMax(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL))*_Point;
   if(side*(current-desired)<=bound) return;
   bool modified=trade.PositionModify(ticket,desired,tp);
   NQObserveBrokerResult(trade.ResultRetcode(),trade.ResultComment());
   if(modified && trade.ResultRetcode()==TRADE_RETCODE_DONE)
      Note("M1_STOP_CHANGE",StringFormat("bar=%s peakR=%f lockR=%f stop=%f",TimeToString(b[0].time,TIME_DATE|TIME_SECONDS),barPeakR,lockR,desired));
   else {failedOrders++;Note("M1_STOP_REJECT",IntegerToString((int)trade.ResultRetcode()));}
}
int OnInit()
{
#ifdef NQP_VISUAL_PROBE
   if(!MQLInfoInteger(MQL_TESTER)) return INIT_FAILED;
#endif
#ifdef NQP_LIFECYCLE_PROBE
   if(!MQLInfoInteger(MQL_TESTER)) return INIT_FAILED;
#endif
   if(!NQPBarTrailSelfTest() || !NQPCalendarSelfTest()) {Print("NQP_CALC_SELFTEST_FAILED");return INIT_FAILED;}
   Print("NQP_CALC_SELFTEST_PASS virtual collision/equality and M1 R milestones");
   RunId=NQPOutputFamily+(MQLInfoInteger(MQL_TESTER) ? "_test_"+IntegerToString((long)GetTickCount64()) : "_trades");
   if(ATRPeriod<2 || ADXPeriod<2 || (!UseFixedSize && RiskCash<=0) || (UseFixedSize && FixedLots<=0) || NoiseFraction<=0 || TargetR<=0 || StopPoints<=0 || TargetPoints<=0 || CommissionRTPerLot<0 || SlipPrice<0 || Magic==0) return INIT_PARAMETERS_INCORRECT;
   if(SyntheticFirst && (Geometry!=SourceGeometry || Management!=FixedBracket)) return INIT_PARAMETERS_INCORRECT;
   if(Management==M1RStep && (BarTrailActivateR<=0 || BarTrailDistanceR<=0 || BarTrailStepR<=0)) return INIT_PARAMETERS_INCORRECT;
   NQPClockRefresh(TimeCurrent());
   sourceTF=PERIOD_M1;
   ArrayResize(m_volumeRing,InpRvolLen);ResetDaily();
   ZeroMemory(m_tickMinute);m_tickHistoryCursor=0;m_tickHistoryRetryAfter=0;
   nqTradeData=NQUsesTradeData((int)SignalData,(int)SymbolInfoInteger(_Symbol,SYMBOL_CHART_MODE),(int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_CALC_MODE));
   PrintFormat("NQ_DATA price=%s volume=%s clock=%s",nqTradeData ? "Last" : "Bid",nqTradeData ? "real" : "tick",InpResearchUTC ? "UTC research" : "portfolio automatic");
   if(SignalData==LastTradeRealVolume)
      Print("NQ_DATA explicit LastTradeRealVolume requires historical Last trades and real volume; CFD Bid/tick-volume data cannot substitute for them.");
   if(InpAtrPeriod<2 || InpAtrRegimeLen<2 || InpRvolLen<2 || InpCloseAfterMin<1 || InpAtrSlMult<=0 || InpAtrTpMult<=0 || InpRangeStart>=InpRangeEnd || InpRvolMin>InpRvolMax || InpRegimeMin>InpRegimeMax)return INIT_PARAMETERS_INCORRECT;
   if(MQLInfoInteger(MQL_TESTER) && !NQPRuntimeSelfTest()) return INIT_FAILED;
   if(!NQPRuntimeInit()) return INIT_FAILED;
   trade.SetExpertMagicNumber(Magic);trade.SetTypeFillingBySymbol(_Symbol);trade.SetDeviationInPoints(30);
   NQPInitVisual();
   if(DetailedLog)
   {
      NQPPrepareOutput();
      string name=NQPOutputRoot+"/ledger_"+RunId+".csv";
      bool append=false;
      if(!MQLInfoInteger(MQL_TESTER))
      {append=true;name=NQPOutputRoot+"/ledger_"+RunId+"_"+IntegerToString(runtimeAccountId)+"_"+IntegerToString((long)Magic)+".csv";}
      ledger=FileOpen(name,FILE_COMMON|FILE_WRITE|FILE_SHARE_READ|(append ? FILE_READ : 0)|FILE_CSV|FILE_ANSI,',');
      if(ledger==INVALID_HANDLE){Print("NQP_LOG_BLOCK: requested ledger unavailable");return INIT_FAILED;}
      if(!append || FileSize(ledger)==0) FileWrite(ledger,"server_time","event","detail");
      else FileSeek(ledger,0,SEEK_END);
   }
   PrintFormat("%s ready | new trades=%s | %s | clock=automatic server/GMT or tester weekly anchor",NQPDisplayName,EnableTrading ? "enabled" : "disabled",NQPSizingLabel());
   PrintFormat("NQP_SPEC tick=%f tickvalue=%f minlot=%f contract=%f",SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE),SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE),SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),SymbolInfoDouble(_Symbol,SYMBOL_TRADE_CONTRACT_SIZE));
   NQPRefreshLiveVisuals(TimeTradeServer());NQPDraw();
   return INIT_SUCCEEDED;
}
// SymbolInfoTick retains cached Last/volume on quote-only changes. Futures
// strategy events must be actual trades; CFD Bid mode consumes quote events.
bool NQStrategyEvent(const uint flags,const bool tradeData)
{
   return !tradeData || (flags & (TICK_FLAG_LAST|TICK_FLAG_VOLUME|TICK_FLAG_BUY|TICK_FLAG_SELL))!=0;
}
void OnTick()
{
   if(!MQLInfoInteger(MQL_TESTER) && !NQPRuntimeAccountContextValid())return;
   datetime now=TimeCurrent();
   if(!NQPClockRefresh(now)){dataWaitReason="CLOCK_WAIT";dayWaiting=true;return;}
   if(day!=NQPDay(now)){ResetDay(now);nqRestored=false;}
   if(m_observationStart==0)m_observationStart=now-now%60;
   bool minutesReady=UpdateClosedMinutes(now);
   nqIndicatorsReady=minutesReady && m_atrCount>=MathMax(InpAtrPeriod,InpAtrRegimeLen);
   if(!NQPRuntimeHistoryReady())return;
   if(!nqRestored || nqRecoveryEvidencePending)
   {
      if(MQLInfoInteger(MQL_TESTER)){NQPStateRestore(now);nqRestored=true;}
      else NQReconcileState(now);
   }
   if(!nqRestored)return;
   MqlTick q;if(!SymbolInfoTick(_Symbol,q))return;
   double equity=AccountInfoDouble(ACCOUNT_EQUITY)-totalCost;
   adjustedPeak=MathMax(adjustedPeak,equity);adjustedDD=MathMax(adjustedDD,adjustedPeak-equity);
   if(!NQStrategyEvent(q.flags,nqTradeData))return;
   if(m_pendingClose!=0)
   {m_pendingClose=0;CloseOwned("TIME_CLOSE");return;}
   if(m_pendingDirection!=0)
   {
      int side=m_pendingDirection;m_pendingDirection=0;
      if(!minutesReady){NQSkip(InpUseTickHistory ? "TICK_HISTORY_WAIT" : "M1_HISTORY_WAIT");return;}
      if(!OwnPosition() && EnableTrading && !runtimeBlocked)Open(side,m_pendingStop,m_pendingTarget,0);
      return;
   }
   if(OwnPosition())
   {
      if(NQTimeCloseDue(q.time_msc))
      {m_pendingClose=(ulong)PositionGetInteger(POSITION_TICKET);return;}
   }
   if(!minutesReady){NQSkip(InpUseTickHistory ? "TICK_HISTORY_WAIT" : "M1_HISTORY_WAIT");return;}
   int today=GetEtDateNum(now),clock=GetEtHHMMSS(now);
   orHigh=m_haveRange ? m_rangeHigh : 0;orLow=m_haveRange ? m_rangeLow : 0;
   rangeReady=m_haveRange && nqRangeBars>=NQRequiredRangeBars() && clock>=InpRangeEnd;
   dayValid=nqIndicatorsReady;averageATR=m_atr;midnight=(orHigh+orLow)/2;
   dayWaiting=false;dataWaitReason="";
   if(!rangeReady)
   {if(clock>=InpTriggerTime)NQSkip("OPENING_RANGE_INCOMPLETE");return;}
   bool window=InpUseTriggerTime ? clock>=InpTriggerTime : clock>=InpRangeEnd && clock<=InpTradeUntil;
   if(!window || nqDecisionDay==today || OwnPosition() || entries>=1)return;
   if(runtimeBlocked || runtimeRecoveryHold){NQSkip("RECOVERY_BLOCK");return;}
   if(!EnableTrading)
   {if(InpUseTriggerTime){nqDecisionDay=today;NQPStateSave();}NQSkip("TRADING_DISABLED");return;}
   double price=nqTradeData ? q.last : q.bid;
   if(price<=0){NQSkip(nqTradeData ? "LAST_PRICE_MISSING" : "BID_PRICE_MISSING");return;}
   int rawSide=price>orHigh ? 1 : price<orLow ? -1 : 0;
   double atr=0;
   if(rawSide==0 || !CheckFilters(atr))
   {
      if(InpUseTriggerTime){nqDecisionDay=today;lastSignal=now;NQPStateSave();}
      NQSkip(rawSide==0 ? "INSIDE_RANGE" : nqTradeData && m_volumeSum<=0 ? "REAL_VOLUME_MISSING" : "FILTER_BAND");
      return;
   }
   int side=InpInvertSignal ? -rawSide : rawSide;
   double size=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(size<=0){NQSkip("TICK_SIZE_MISSING");return;}
   nqDecisionDay=today;lastSignal=now;NQPStateSave();
   m_pendingStop=NQCrossing(price-side*InpAtrSlMult*atr,size,side<0);
   m_pendingTarget=NQCrossing(price+side*InpAtrTpMult*atr,size,side>0);
   m_pendingDirection=side;
   PrintFormat("NQPB %d SIGNAL dir=%d px=%.8f ATR=%.12f regime=%.12f rvol=%.12f",today,side,price,atr,m_atr/m_atrLong,m_rvol);
   NQPDraw();
}
void OnTradeTransaction(const MqlTradeTransaction &tx,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   if(tx.type!=TRADE_TRANSACTION_DEAL_ADD || !HistoryDealSelect(tx.deal)) return;
   if(HistoryDealGetString(tx.deal,DEAL_SYMBOL)!=_Symbol)return;
   bool visualOwned=(ulong)HistoryDealGetInteger(tx.deal,DEAL_MAGIC)==Magic;
   ulong visualPosition=(ulong)HistoryDealGetInteger(tx.deal,DEAL_POSITION_ID);
   for(int i=0;i<ArraySize(nqpBrokerView);i++)
      if(nqpBrokerView[i].id==visualPosition && !nqpBrokerView[i].mixed)visualOwned=true;
   if(visualOwned){nqpBrokerVisualDirty=true;NQPDraw();}
   if((ulong)HistoryDealGetInteger(tx.deal,DEAL_MAGIC)!=Magic)return;
   long entry=HistoryDealGetInteger(tx.deal,DEAL_ENTRY);
   if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY) return;
   datetime t=(datetime)HistoryDealGetInteger(tx.deal,DEAL_TIME);MqlDateTime p;TimeToStruct(NQPDay(t),p);
   if(ownedEntryTime>0 && NQPDay(t)!=NQPDay(ownedEntryTime))
   {
      carryDetails+=TimeToString(ownedEntryTime-8*3600,TIME_DATE|TIME_SECONDS)+","+TimeToString(t-8*3600,TIME_DATE|TIME_SECONDS)+"\r\n";
   }
   int y=p.year-2020;
   double qty=HistoryDealGetDouble(tx.deal,DEAL_VOLUME),exitPrice=HistoryDealGetDouble(tx.deal,DEAL_PRICE);
   int exitReason=(int)HistoryDealGetInteger(tx.deal,DEAL_REASON);
   int exitSide=HistoryDealGetInteger(tx.deal,DEAL_TYPE)==DEAL_TYPE_BUY ? 1 : -1;
   ulong pid=(ulong)HistoryDealGetInteger(tx.deal,DEAL_POSITION_ID);
   double exitCharges=HistoryDealGetDouble(tx.deal,DEAL_COMMISSION)+HistoryDealGetDouble(tx.deal,DEAL_FEE);
   double brokerNet=HistoryDealGetDouble(tx.deal,DEAL_PROFIT)+exitCharges+HistoryDealGetDouble(tx.deal,DEAL_SWAP);
   double entryCharges=NQPEntryChargesPerLot(pid)*qty;
   double slipCost=MathMax(0,modelCostPerLot-entryCommissionPerLot)*qty;
   double extraCommission=MQLInfoInteger(MQL_TESTER) ? MathMax(0,entryCommissionPerLot*qty-entryCharges+exitCharges) : 0;
   // Broker-net already contains exit charges; include allocated entry charges once.
   double net=brokerNet-entryCharges-slipCost-extraCommission;
   if(MQLInfoInteger(MQL_TESTER)) totalCost-=MathMin(entryCommissionPerLot*qty,MathMax(0,entryCharges-exitCharges));
   NQPStateSave();
   if(y>=0 && y<7){yearProfit[y]+=net;yearTrades[y]++;}
   int di=(int)((NQPDay(t)-D'2020.01.01')/86400);
   if(di>=0 && di<ArraySize(dailyNet)) dailyNet[di]+=net;
   if(net>0)netWins+=net;else netLosses-=net;
   Note("EXIT",StringFormat("ticket=%I64u price=%f netAdjusted=%f reason=%d",tx.deal,exitPrice,net,exitReason));
   NQPDrawFill(exitSide,t,exitPrice,"Exit");
}
double OnTester()
{
#ifdef NQP_LIFECYCLE_PROBE
   return 0;
#endif
   double net=TesterStatistics(STAT_PROFIT)-totalCost;
   double pf=netLosses>0 ? netWins/netLosses : 0;
   NQPPrepareOutput();
   string path=NQPOutputRoot+"/"+RunId+".csv";
   int out=FileOpen(path,FILE_COMMON|FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(out==INVALID_HANDLE) return -1000000;
   FileWrite(out,"model","net","pf","equityDD","trades","days","rejectedDays","invalidBrackets","failedOrders","worstRisk");
   FileWrite(out,NQPModelId,net,pf,adjustedDD,TesterStatistics(STAT_TRADES),daysReady,daysRejected,invalidBrackets,failedOrders,worstRisk);
   FileClose(out);
   bool exported=!DetailedLog || NQPExportTrades(path+".trades.csv");
   PrintFormat("%s TESTER_RESULT net=%.2f PF=%.6f trades=%d export=%s path=%s",NQPDisplayName,net,pf,(int)TesterStatistics(STAT_TRADES),!DetailedLog ? "DISABLED" : exported ? "PASS" : "FAIL",path);
   return exported && failedOrders==0 && invalidBrackets==0 ? (adjustedDD>0 ? net/adjustedDD : 0) : -1000000;
}
void OnDeinit(const int reason)
{
   NQPStateSave();EventKillTimer();
   if(runtimeLockFile!=INVALID_HANDLE) FileClose(runtimeLockFile);
   // A timeframe reload must not erase the M1-derived session state while history warms up.
   if(reason!=REASON_CHARTCHANGE || ChartSymbol(0)!=_Symbol || !ShowVisuals)
      ObjectsDeleteAll(0,NQPVisualPrefix());
   if(nqvPane!=INVALID_HANDLE)
   {
      for(int window=(int)ChartGetInteger(0,CHART_WINDOWS_TOTAL)-1;window>=1;window--) ChartIndicatorDelete(0,window,nqvPaneName);
      IndicatorRelease(nqvPane);
   }
   if(ledger!=INVALID_HANDLE) FileClose(ledger);
   if(atrHandle!=INVALID_HANDLE) IndicatorRelease(atrHandle);
   if(adxHandle!=INVALID_HANDLE) IndicatorRelease(adxHandle);
}
