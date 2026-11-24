"""Run production execution metadata helpers in an NQ callback on an NNQ strategy."""
from pathlib import Path
import re
import subprocess
import tempfile

strategies = Path(__file__).resolve().parents[2]
def part(text, pattern):
    match = re.search(pattern, text)
    assert match, pattern
    left = text.index('{', match.start())
    right, depth = left + 1, 1
    while depth:
        depth += (text[right] == '{') - (text[right] == '}')
        right += 1
    return text[match.start():right]

for folder, filename, cost in [('VaultBreak_NT','VaultBreakNT8.cs','Friction'),
                               ('OvernightBiasRangeBreakout_NT','OvernightBiasRangeBreakoutNT8.cs','CostPerContract')]:
    if folder != Path(__file__).resolve().parents[1].name:
        continue
    text = (strategies / folder / filename).read_text()
    methods = [part(text, r'private double Round\('), part(text, r'private double '+cost+r'\s*\{'),
               part(text, r'private string FeeScope\s*\{')]
    if 'private Instrument ExecutionInstrument' in text:
        methods.append(part(text, r'private Instrument ExecutionInstrument\s*\{'))
    harness = r'''
using System;
class Master {public double PointValue,TickSize;public double RoundToTickSize(double p){return Math.Round(p/TickSize)*TickSize;}}
class Instrument {public string FullName;public Master MasterInstrument;}
class Bars {public Instrument Instrument;}
class AccountInfo {public string Name="Demo";}
class Probe {
 AccountInfo Account=new AccountInfo();int executionSeries=2,BarsInProgress=1;
 double EffectiveCommission=4,SlippagePrice=.03;
 Bars[] BarsArray={new Bars{Instrument=I("NNQ",.2,.01)},new Bars{Instrument=I("NQ",20,.25)},new Bars{Instrument=I("NNQ",.2,.01)}};
 Instrument Instrument {get{return BarsArray[BarsInProgress].Instrument;}}
 static Instrument I(string name,double pv,double tick){return new Instrument{FullName=name+" DEC26",MasterInstrument=new Master{PointValue=pv,TickSize=tick}};}
 METHODS
 static void Check(bool ok,string label){if(!ok)throw new Exception(label);}
 static void Main(){var p=new Probe();foreach(int bip in new[]{0,1,2}){p.BarsInProgress=bip;
 Check(Math.Abs(p.Round(100.13)-100.13)<1e-8,"NQ callback changed NNQ rounding");
 Check(Math.Abs(p.COST-4.012)<1e-8,"NQ callback changed NNQ risk costs");
 Check(p.FeeScope=="Demo|NNQ DEC26","NQ callback changed commission scope");}
 Console.WriteLine("PASS execution contract, rounding, cash costs and commission scope independent of callback series");}
}
'''.replace('METHODS','\n'.join(methods)).replace('COST',cost)
    with tempfile.TemporaryDirectory(prefix='execution-contract-') as work:
        p=Path(work);(p/'Probe.cs').write_text(harness)
        c=subprocess.run([r'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe','/nologo','/out:'+str(p/'Probe.exe'),str(p/'Probe.cs')],capture_output=True,text=True)
        assert c.returncode==0,c.stdout
        result=subprocess.run([str(p/'Probe.exe')],capture_output=True,text=True)
        assert result.returncode==0,folder+'\n'+result.stdout+result.stderr
        print(folder+': '+result.stdout.strip())
