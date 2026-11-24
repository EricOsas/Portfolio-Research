"""Exercise production ADX publication/chart callbacks, without market data or orders."""
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
text = (root / 'OvernightBiasRangeBreakoutNT8.cs').read_text()
indicator = text[text.index('public class OvernightBiasRangeBreakoutADX : Indicator'):]
def declaration(source, pattern):
    match = re.search(pattern, source)
    assert match, pattern
    left = source.index('{', match.start())
    depth, right = 1, left + 1
    while depth:
        depth += (source[right] == '{') - (source[right] == '}')
        right += 1
    return source[match.start():right]

fields = indicator[indicator.index('{') + 1:re.search(r'\binternal void Publish\(', indicator).start()]
methods = [declaration(indicator, r'internal void Publish\('),
           declaration(indicator, r'protected override void OnBarUpdate\(')]
for name in ['PaintCurrent', 'ResetPublished', 'RefreshPublishedPlots']:
    if re.search(r'\bvoid ' + name + r'\(', indicator):
        methods.append(declaration(indicator, r'(?:private|internal) void ' + name + r'\('))
history = declaration(indicator, r'internal sealed class AdxHistory\b') if 'internal sealed class AdxHistory' in indicator else ''
if history:
    fields = fields.replace(history, '')
model = '\n'.join(declaration(text, r'internal sealed class ' + n + r'\b') for n in ['Candle', 'WilderAdx'])
model = re.sub(r'public bool (\w+)\s*=>\s*([^;]+);', r'public bool \1 { get { return \2; } }', model)
harness = r'''
using System;using System.Collections.Generic;
enum State {Historical,Realtime}
class Bars {public List<DateTime> Times=new List<DateTime>();public DateTime GetTime(int i){return Times[i];}}
class TimeSeries {public Probe Owner;public DateTime this[int ago]{get{return Owner.BarsArray[0].GetTime(Owner.CurrentBars[0]-ago);}}}
class PlotSeries {public Probe Owner;public Dictionary<int,double> Data=new Dictionary<int,double>();public double this[int ago]{get{return Data[Owner.CurrentBars[0]-ago];}set{Data[Owner.CurrentBars[0]-ago]=value;}}}
class Adapter {protected virtual void OnBarUpdate(){}public int BarsInProgress;public int[] CurrentBars={-1,-1};public State State=State.Historical;public Bars[] BarsArray={new Bars()};public TimeSeries[] Times;public PlotSeries[] Values;}
namespace NinjaTrader.NinjaScript.Strategies {class OvernightBiasRangeBreakoutNT8 {MODEL}}
class Probe:Adapter {
FIELDS
METHODS
HISTORY
public Probe(){platformZone=centralZone=TimeZoneInfo.Utc;adx=new NinjaTrader.NinjaScript.Strategies.OvernightBiasRangeBreakoutNT8.WilderAdx();Times=new[]{new TimeSeries{Owner=this}};Values=new[]{new PlotSeries{Owner=this}};}
private DateTime Central(DateTime time){return time;}
private void ProcessSource(int ago){throw new Exception("Unexpected source callback");}
public void Chart(int index){CurrentBars[0]=index;BarsInProgress=0;OnBarUpdate();}
static void Check(bool ok,string label){if(!ok)throw new Exception(label);}
static void Main(){
 var p=new Probe();DateTime t=new DateTime(2020,1,2,9,0,0);
 p.BarsArray[0].Times.AddRange(new[]{t.AddMinutes(-1),t,t.AddMinutes(15),t.AddMinutes(30)});
 // Host processes the full history before the hosted chart indicator replays it.
 p.Publish(25,t);p.Publish(35,t.AddMinutes(15));p.Publish(18,t.AddMinutes(30));
 p.Chart(0);Check(p.Values[0].Data[0]==0,"Future value leaked before first publication");
 p.Chart(1);Check(p.Values[0].Data[1]==25,"First historical bar overwritten by final ADX");
 p.Chart(2);Check(p.Values[0].Data[2]==35,"Historical threshold crossing disappeared");
 p.Chart(3);Check(p.Values[0].Data[3]==18,"Latest chart value does not match host");
 p.Publish(55,t.AddMinutes(45));p.Chart(3);Check(p.Values[0].Data[3]==18,"Future publication contaminated earlier chart bar");
 EXTRA
 Console.WriteLine("PASS actual ADX callbacks: host-first history, changing values, threshold crossing, no future leakage, live updates and repair repaint");
}}
'''
extra = ''
if history:
    extra = '''p.ResetPublished();p.Publish(26,t,false);p.Publish(36,t.AddMinutes(15),false);p.Publish(19,t.AddMinutes(30),false);p.RefreshPublishedPlots();Check(p.Values[0].Data[1]==26 && p.Values[0].Data[2]==36 && p.Values[0].Data[3]==19,"Repair did not repaint past chart values");p.Publish(29,t.AddMinutes(30));Check(p.Values[0].Data[3]==29,"Same-time live update ignored");'''
harness = harness.replace('MODEL', model).replace('FIELDS', fields).replace('METHODS', '\n'.join(methods)).replace('HISTORY', history).replace('EXTRA', extra).replace('Strategies.OvernightBiasRangeBreakoutNT8', 'NinjaTrader.NinjaScript.Strategies.OvernightBiasRangeBreakoutNT8')
# Avoid doubling qualification in the explicit constructor reference.
harness = harness.replace('NinjaTrader.NinjaScript.NinjaTrader.NinjaScript.', 'NinjaTrader.NinjaScript.')
harness = harness.replace('base.', '')
with tempfile.TemporaryDirectory(prefix='obrb-adx-display-') as work:
    path = Path(work)
    (path / 'Probe.cs').write_text(harness)
    compile_result = subprocess.run([r'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe', '/nologo', '/nowarn:0169,0414,0649', '/out:' + str(path / 'Probe.exe'), str(path / 'Probe.cs')], capture_output=True, text=True)
    assert compile_result.returncode == 0, compile_result.stdout
    result = subprocess.run([str(path / 'Probe.exe')], capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr
    print(result.stdout.strip())
