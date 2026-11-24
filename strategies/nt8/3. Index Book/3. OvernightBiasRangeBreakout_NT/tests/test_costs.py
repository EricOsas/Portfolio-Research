"""Compile production cost helpers with native-interface stubs; no market/holdout data."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
CSC = Path(r'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe')
HARNESS = r'''
using System; using System.Collections.Generic; using System.Linq;
enum State { Historical, Realtime }
class Execution { public double Commission, Fee; }
class AccountInfo { public string Name="LiveA"; }
class InstrumentInfo { public string FullName="MNQ 12-25"; }
static class Connection { public static object PlaybackConnection=null; }
class CostHarness {
State State=State.Realtime; AccountInfo Account=new AccountInfo(); InstrumentInfo Instrument=new InstrumentInfo();
InstrumentInfo ExecutionInstrument {get{return Instrument;}}
double CommissionPerContract=4; string entryName="trade1";
HELPER
FLOOR
static void Check(bool ok,string name) { if(!ok)throw new Exception(name); }
static void Main() {
var h=new CostHarness(); Check(h.EffectiveCommission==4,"fallback");
var e=new Execution {Commission=1,Fee=.2}; var x=new Execution {Commission=1.3,Fee=.3};
h.ObserveFee(e,"entry",1,true); h.ObserveFee(e,"entry",1,true);
Check(h.feeTrade.EntryQuantity==1,"duplicate quantity");
h.ObserveFee(x,"exit",1,false); Check(h.EffectiveCommission==4,"not closed yet");
h.feeTrade.Closed=true; Check(Math.Abs(h.EffectiveCommission-2.8)<1e-8,"both fee legs");
e.Commission=2; Check(Math.Abs(h.EffectiveCommission-3.8)<1e-8,"late mutable fee");
h.ObserveFee(new Execution {Commission=3,Fee=.2},"entry",1,true);
Check(Math.Abs(h.EffectiveCommission-4.8)<1e-8,"late duplicate replacement");
var second=new CostHarness(); Check(Math.Abs(second.EffectiveCommission-4.8)<1e-8,"timeframe cache");
second.Account.Name="OtherLive"; Check(second.EffectiveCommission==4,"account scope");
second.Account.Name="LiveA";second.Instrument.FullName="NQ 12-25";Check(second.EffectiveCommission==4,"contract scope");
second.Instrument.FullName="MNQ 12-25";second.Account.Name="Sim101";Check(second.EffectiveCommission==4,"sim excluded");
h.entryName="trade2";h.ObserveFee(new Execution {Commission=2},"e2",2,true);
h.ObserveFee(new Execution {Commission=2},"x2",1,false);h.feeTrade.Closed=true;
Check(Math.Abs(h.EffectiveCommission-4.8)<1e-8,"incomplete volume excluded");
Check(FeeTrade.Charge(new Execution {Commission=double.NaN,Fee=-.5})==.5,"finite absolute charges");
for(int side=-1;side<=1;side+=2) {
 double live=CoveredStop(side,100,4,2,.03,.25);
 double hist=CoveredStop(side,100,4,2,.06,.25);
 Check(side*(live-100)*2-4-.03*2>=-1e-8,"live BE costs");
 Check(side*(hist-100)*2-4-.06*2>=-1e-8,"historical modeled BE costs");
}
Console.WriteLine("PASS native cost helpers: fee dedupe, late updates, scope, volume, simulation exclusion, cost-covered BE");
} }
'''

ob = (ROOT/'OvernightBiasRangeBreakout_NT'/'OvernightBiasRangeBreakoutNT8.cs').read_text(encoding='utf-8-sig')
start = ob.index('        internal static double CoveredStop(')
stop = ob.index('        internal static double BracketPrice(', start)
floor = ob[start:stop]
for model, file in [('VaultBreak_NT','VaultBreakNT8.cs'), ('OvernightBiasRangeBreakout_NT','OvernightBiasRangeBreakoutNT8.cs')]:
    source = (ROOT/model/file).read_text(encoding='utf-8-sig')
    start = source.index('        // Execution charges are native NT values,')
    stop = source.index('        private double SlippagePrice', start)
    # Vault's source-contract selector now follows its fee helper; exclude routing code.
    routing = source.find('        private static string SourceContract(', start, stop)
    if routing >= 0:
        stop = routing
    selection = source.find('        // BEGIN SOURCE HISTORY CHECK', start, stop)
    if selection >= 0:
        stop = selection
    program = HARNESS.replace('HELPER', source[start:stop]).replace('FLOOR', floor)
    assert 'CommissionPerContract = 4' in source or 'CommissionPerContract=4' in source
    assert 'SlippagePoints = 3' in source or 'SlippagePoints=3' in source
    assert 'SlippagePoints * .01' in source or 'SlippagePoints*.01' in source
    with tempfile.TemporaryDirectory() as folder:
        target = Path(folder)
        (target/'CostHarness.cs').write_text(program)
        subprocess.run([str(CSC),'/nologo','/out:CostHarness.exe','CostHarness.cs'],cwd=target,check=True)
        subprocess.run([str(target/'CostHarness.exe')],cwd=target,check=True)
    print(model+' production helper verified')
