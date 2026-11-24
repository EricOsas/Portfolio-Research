from pathlib import Path
import subprocess, tempfile
ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'VWAPPullbackNT8.cs'
def block(s, token):
    i=s.index(token); b=s.index('{',i); level=1; j=b+1
    while level:
        level += (s[j]=='{')-(s[j]=='}'); j+=1
    return s[i:j]
s=SOURCE.read_text(encoding='utf-8-sig')
core=block(s,'internal sealed class PullbackSetup')
bars=block(s,'internal sealed class Candle')
adx=block(s,'internal sealed class WilderAdx')
trail=block(s,'internal static double TrailLevel')
constants=next(l.strip().replace('private const','const') for l in s.splitlines() if 'private const double TargetMultiple=' in l)
fixture=r'''
using System;
class Proof {
static void Check(bool x,string m){if(!x)throw new Exception(m);}
static void Main(){
 var f=new PullbackSetup();var d=new DateTime(2026,9,24);
 for(int m=510;m<540;m++)f.Observe(d.AddMinutes(m),100,90,95,1,25,26);
 Check(f.RangeReady,"OR ready");
 Check(!f.Observe(d.AddMinutes(589),110,90,105,1,25,26)&&!f.HighQualified,"09:49 cannot arm");
 Check(!f.Observe(d.AddMinutes(590),110,90,105,1,25,26)&&f.HighQualified&&!f.TouchQualified,"H alone");
 Check(!f.Observe(d.AddMinutes(591),110,90,105,1,27,26)&&f.TouchQualified,"rising ADX blocks R");
 Check(f.Observe(d.AddMinutes(592),110,90,105,1,26,27)&&f.Reclaimed,"later V/R qualified");
 f.Consume();Check(!f.Observe(d.AddMinutes(593),110,90,105,1,25,26),"one daily trade");
 var g=new PullbackSetup();
 for(int m=510;m<540;m++)g.Observe(d.AddMinutes(m),100,90,95,1,25,26);
 g.Observe(d.AddMinutes(950),110,90,105,1,25,26);
 Check(g.Observe(d.AddMinutes(953),110,90,105,1,25,26),"15:54 confirmation eligible");
 Check(!g.Observe(d.AddMinutes(954),110,90,105,1,25,26),"15:55 confirmation blocked");
 var a=new WilderAdx();a.Push(new Candle(d,100,110,90,100,1));
 Check(a.Value==50&&a.Atr==20,"native seeds");
 a.Push(new Candle(d.AddMinutes(1),100,120,95,110,1));
 Check(Math.Abs(a.Atr-22.5)<1e-9&&Math.Abs(a.Value-(650.0+100)/14)<1e-9,"native ATR/ADX recurrence");
 double stop=Math.Ceiling((100-3*1.13)/.25-1e-9)*.25;
 double target=Math.Floor((100+TargetMultiple*(100-stop))/.25+1e-9)*.25;
 Check(stop==96.75&&target==104,"toward-entry SL and 1.27R target");
 Check(TrailLevel(100,10,110,.185,.25)==107.5,"quarter-R trail distance");
 Check(TrailLevel(100,10,100,.185,.25)==100.25,"tick-rounded cost floor");
 Console.WriteLine("PASS: unchanged H/V/R and ADX; native recurrence; rounded 1.27R; quarter-R trail and cost floor");
}}
'''
with tempfile.TemporaryDirectory() as folder:
 p=Path(folder); (p/'Proof.cs').write_text('using System;\n'+core+'\n'+bars+'\n'+adx+'\n'+fixture.replace('using System;','').replace('static void Main(){',constants+'\n'+trail+'\nstatic void Main(){'))
 csc=r'C:/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe'
 subprocess.run([csc,'/nologo','/out:'+str(p/'Proof.exe'),str(p/'Proof.cs')],check=True)
 subprocess.run([str(p/'Proof.exe')],check=True)
assert 'ConnectionLossHandling.KeepRunning' in s
assert 'StartBehavior.ImmediatelySubmit' in s
assert 'Trail(bar,end)' in block(s,'private void ProcessSource')
assert 'trailConfirmations>=2' in block(s,'private void Trail')
assert 'bar.Start<trailEntryStart || !BrokerReady()' in block(s,'private void Trail')
assert 'next-stop.StopPrice<TrailStepR*initialRisk' in block(s,'private void Trail')
assert 'IsExitOnSessionCloseStrategy=false' in s
assert 'if(qualified && State==State.Realtime && (!fresh || end<=startupFloor || end<=recoveryFloor))' in s
print('PASS: production runtime defaults')

# Reused broker boundary/fee functions must remain byte-identical to the reference.
reference=(ROOT.parent/'5. OvernightBiasRangeBreakout_NT'/'OvernightBiasRangeBreakoutNT8.cs').read_text(encoding='utf-8-sig')
for token in ['private bool BrokerReady','private bool ObserveBrokerConnection',
              'private Order SubmitOwnedOrder','private void CancelOwnedOrder',
              'private void ChangeOwnedOrder','private void ObserveFee',
              'private void CheckActualFillRisk']:
 assert block(s,token)==block(reference,token),token+' changed from validated reference'
assert 'NQIndependentModelExposure.v1' in s and 'IndependentEquityDirectionExposure.v1' in s
print('PASS: broker guards, fee idempotence and actual-fill risk checking preserved from reference')

