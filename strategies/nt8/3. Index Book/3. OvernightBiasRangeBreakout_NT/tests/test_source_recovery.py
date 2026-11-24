"""Run actual NT source cursors and async provider repair with deterministic adapters."""
from pathlib import Path
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
CSC=r'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'

def method(text,name):
    start=text.index('        private void '+name+'(')
    begin=text.index('{',start);end=begin+1;depth=1
    while depth:
        depth+=(text[end]=='{')-(text[end]=='}');end+=1
    return text[start:end]

common=r'''
using System;using System.Collections.Generic;using System.Linq;
enum RunState {Historical,Realtime,Terminated}
enum ErrorCode {NoError,Failed}
enum BarsPeriodType {Minute}
enum LookupPolicies {Provider}
class BarsPeriod {public BarsPeriodType BarsPeriodType;public int Value;}
class TradingHours {public static object Get(string name){return name;}}
class FakeBars {
 public List<DateTime> Ends=new List<DateTime>();public object Instrument=new object();public int Count {get{return Ends.Count;}}
 public DateTime GetTime(int i){return Ends[i];}public double GetOpen(int i){return 100;}
 public double GetHigh(int i){return 105;}public double GetLow(int i){return 95;}
 public double GetClose(int i){return 101;}public double GetVolume(int i){return 10;}
}
class BarsRequest {
 public static BarsRequest Latest;public FakeBars Bars=new FakeBars();public BarsPeriod BarsPeriod;public object TradingHours;public LookupPolicies LookupPolicy;
 Action<BarsRequest,ErrorCode,string> callback;public BarsRequest(object instrument,int count){Latest=this;}
 public void Request(Action<BarsRequest,ErrorCode,string> action){callback=action;}
 public void Complete(DateTime? end,ErrorCode error=ErrorCode.NoError){if(end.HasValue)Bars.Ends.Add(end.Value);callback(this,error,"fixture");}
 public void Dispose(){}
}
class Series<T> {public Func<int,T> Read;public T this[int ago]{get{return Read(ago);}}}
class Model {
 public DateTime Day,MissingStart,MissingEnd,VirtualStart;public int Attempts;public List<Minute> Rows=new List<Minute>();
 public bool Ready=true,VirtualActive,VirtualPending;public string BlockReason;public double VirtualStop,VirtualTarget;
 public const double StopDistance=70,TargetDistance=40;
 public static int Cutoff(DateTime d){return 870;}
 public void MinuteClosed(Minute b,bool enabled){if(enabled)throw new Exception("Rebuild must not trade");Rows.Add(b);Day=b.Start.Date;}
 public void BeginLive(DateTime t){Attempts=0;}
 public static int VirtualOutcome(double low,double high,double stop,double target){return low<=stop?-1:high>=target?1:0;}
 public void RestoreVirtual(bool active,bool pending,DateTime start,double stop,double target){VirtualActive=active;VirtualPending=pending;VirtualStart=start;VirtualStop=stop;VirtualTarget=target;}
}
class Minute {public DateTime Start;public double Open,High,Low,Close,Volume;}
class Candle {public DateTime Start;public double Open,High,Low,Close;public Candle(DateTime t,double o,double h,double l,double c){Start=t;Open=o;High=h;Low=l;Close=c;}}
class Harness {
 RunState State=RunState.Historical;int signalSeries=1,consumedSourceIndex=-1;
 DateTime lastEnd,latest,lastMinute,latestCentral,activation,recoveryFloor,repairRetry;
 static DateTime now=new DateTime(2025,2,25,10,0,0);
 Model model=new Model();BarsRequest historyRepair;string status;
 bool historyWaiting;
 FakeBars[] BarsArray={null,new FakeBars()};int[] CurrentBars={-1,-1};
 Series<DateTime>[] Times={null,new Series<DateTime>()};
 Series<double>[] Opens={null,new Series<double>()},Highs={null,new Series<double>()},Lows={null,new Series<double>()},Closes={null,new Series<double>()},Volumes={null,new Series<double>()};
 Dictionary<DateTime,BARTYPE> providerBars=new Dictionary<DateTime,BARTYPE>();
 List<DateTime> seen=new List<DateTime>();List<bool> freshFlags=new List<bool>();
 Harness(){Times[1].Read=a=>BarsArray[1].GetTime(CurrentBars[1]-a);foreach(var s in new[]{Opens,Highs,Lows,Closes,Volumes})s[1].Read=a=>100;}
 DateTime Central(DateTime t){return t;}static DateTime NativeNow(){return now;}
 int Cutoff(DateTime d){return 870;}void Paint(DateTime t){}void UpdatePanel(){}void Print(string s){}
 void TriggerCustomEvent(Action<object> action,object value){action(value);}
 void ProcessSource(BARTYPE b,bool fresh){seen.Add(b.Start);freshFlags.Add(fresh);model.Day=b.Start.Date;lastEnd=lastMinute=b.Start.AddMinutes(1);}
 void RefreshVwapPlot(){}
 REBUILD
 void Add(DateTime end){BarsArray[1].Ends.Add(end);CurrentBars[1]++;}
 METHODS
 static void Check(bool ok,string name){if(!ok)throw new Exception(name);}
 static void Main(){
  var h=new Harness();h.Add(now);h.ConsumeSource();Check(h.seen.Count==1,"historical first bar consumed");
  h.State=RunState.Realtime;now=now.AddMinutes(3);h.Add(now.AddMinutes(-1));h.Add(now);h.ConsumeSource();
  Check(h.historyRepair!=null&&h.seen.Count==1,"gap pauses source before corrupting model");
  HISTORY_WAIT_CHECK
  BarsRequest.Latest.Complete(now.AddMinutes(-2));
  Check(h.historyRepair==null&&h.seen.Count==3,"provider bar restores gap then buffered bar");
  Check(!h.freshFlags[1]&&!h.freshFlags[2],"provider and delayed bars cannot enter");
  h.ConsumeSource();Check(h.seen.Count==3,"duplicate callbacks do nothing");
  h.Add(now.AddMinutes(1));h.ConsumeSource();Check(!h.freshFlags[3],"recovery boundary signal stale");
  now=now.AddMinutes(1);h.Add(now.AddMinutes(1));h.ConsumeSource();Check(h.freshFlags[4],"next fresh close can qualify");
  h.CurrentBars[1]=0;h.ConsumeSource();Check(h.seen.Count==5,"live canonical cursor is independent of queued callback index");
  now=now.AddMinutes(4);h.Add(now.AddMinutes(-1));h.Add(now);h.ConsumeSource();
  int before=h.seen.Count;Check(h.historyRepair!=null,"second gap paused");
  BarsRequest.Latest.Complete(null);Check(h.seen.Count==before,"empty provider response never invents bars");
  h.ConsumeSource();Check(h.historyRepair==null,"failed repair backs off rather than request every tick");
  now=now.AddSeconds(31);h.ConsumeSource();Check(h.historyRepair!=null,"repair retries after backoff");
  h.State=RunState.Terminated;BarsRequest.Latest.Complete(null);
  Check(h.seen.Count==before,"late provider callback cannot touch terminated strategy");
  HISTORICAL_FIXTURE
  Console.WriteLine("PASS KIND actual cursor/repair: catches missed callbacks, reloads gap, suppresses stale signals, empty/error waits, bounded retries");
 }
}
'''

models=[('Vault',ROOT/'VaultBreakNT8.cs')] if ROOT.name=='VaultBreak_NT' else [('Overnight',ROOT/'OvernightBiasRangeBreakoutNT8.cs')]
for kind,path in models:
    text=path.read_text(encoding='utf-8-sig')
    assert 'LookupPolicies.Provider' in text
    assert 'else AddDataSeries(Instrument.FullName,new BarsPeriod {BarsPeriodType=BarsPeriodType.Minute,Value=1},"CME US Index Futures ETH",true);' in text
    methods='\n'.join(method(text,n) for n in ['ConsumeSource','RequestSourceRepair'])
    rebuild=method(text,'RebuildSource') if kind=='Vault' else 'void RebuildSource(List<Candle> bars){throw new Exception("Unexpected historical rebuild in live gap fixture");}'
    historical=r'''
  var loaded=new Harness();now=new DateTime(2025,2,25,10,3,0);loaded.State=RunState.Realtime;
  loaded.Add(now.AddMinutes(-3));loaded.Add(now.AddMinutes(-1));loaded.Add(now);
  loaded.model.Day=now.Date;loaded.model.Attempts=3;
  loaded.model.VirtualActive=true;loaded.model.VirtualStart=now.AddMinutes(-4);loaded.model.VirtualStop=90;loaded.model.VirtualTarget=140;
  loaded.lastEnd=now.AddMinutes(-1);loaded.model.MissingStart=now.AddMinutes(-3);loaded.model.MissingEnd=now.AddMinutes(-2);
  loaded.ConsumeSource();Check(loaded.historyRepair!=null,"loaded historical gap requests provider");
  BarsRequest.Latest.Complete(now.AddMinutes(-2));
  Check(loaded.model.Attempts==3,"historical rebuild preserves funded attempt cap");
  Check(loaded.model.VirtualActive,"historical rebuild cannot discard unresolved synthetic attempt");
  Check(loaded.model.Rows.Count==3&&loaded.model.Rows[1].Start==now.AddMinutes(-3),"historical rebuild merges provider bars chronologically");
  Check(loaded.seen.Count==0,"historical rebuild sends no old entries");
''' if kind=='Vault' else ''
    code=common.replace('BARTYPE','Minute' if kind=='Vault' else 'Candle').replace('METHODS',methods.replace('State.', 'RunState.')).replace('REBUILD',rebuild).replace('HISTORICAL_FIXTURE',historical).replace('KIND',kind).replace('HISTORY_WAIT_CHECK','Check(h.historyWaiting,"Vault panel exposes history pause");' if kind=='Vault' else '')
    with tempfile.TemporaryDirectory(prefix='source_recovery_') as d:
        p=Path(d);(p/'Test.cs').write_text(code)
        # SDK adapters deliberately expose fields unused by one of the two ports.
        subprocess.run([CSC,'/nologo','/nowarn:0169,0649','/out:Test.exe','Test.cs'],cwd=p,check=True)
        subprocess.run([str(p/'Test.exe')],cwd=p,check=True)
