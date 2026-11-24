"""Compare compiled production M1 math/setup with the selected development source."""
from pathlib import Path
import sys, subprocess, tempfile
import numpy as np
sys.path.insert(0,r'C:/Users/Administrator/Documents/Strategies/Conte_Research_Strategies/research/vwap_pullback')
import baseline
from exit_geometry_grid import native_atr
SOURCE=Path(__file__).resolve().parents[1]/'VWAPPullbackNT8.cs'
def block(s, token):
 i=s.index(token);b=s.index('{',i);level=1;j=b+1
 while level:level+=(s[j]=='{')-(s[j]=='}');j+=1
 return s[i:j]
f,audit=baseline.load();prepared=baseline.prepare(f,'rth')
times,minute,dates,prices,vwap,target,stop,sessions,coverage=prepared
adx=baseline.native_adx(f,14);atr=native_atr(prices)
reference=baseline.simulate(f,14,'rth',adx,prepared=prepared,start_minute=590,range_mode='close',later_vwap_contact=True)
valid={str(d) for d,_,_ in sessions}
matrix=np.column_stack([times.dt.tz_localize(None).astype('datetime64[ns]').astype('int64').to_numpy()/1e9,prices,f.v.to_numpy(),np.array([str(d) in valid for d in dates],dtype=float)])
s=SOURCE.read_text(encoding='utf-8-sig')
cs='using System;using System.IO;\n'+'\n'.join(block(s,t) for t in ['internal sealed class Candle','internal sealed class WilderAdx','internal sealed class PullbackSetup'])
cs+=r"""
class Replay {
static void Main(string[] args){
 var adx=new WilderAdx();var setup=new PullbackSetup();
 using(var input=new BinaryReader(File.OpenRead(args[0])))
 using(var output=new BinaryWriter(File.Create(args[1])))
 using(var signals=new StreamWriter(args[2])){
 int i=0;while(input.BaseStream.Position<input.BaseStream.Length){
 var t=new DateTime(1970,1,1).AddSeconds(input.ReadDouble());
 var b=new Candle(t,input.ReadDouble(),input.ReadDouble(),input.ReadDouble(),input.ReadDouble(),input.ReadDouble());
 bool valid=input.ReadDouble()>0;adx.Push(b);
 bool eligible=setup.Observe(t,b.High,b.Low,b.Close,b.Volume,adx.Value,adx.Previous);
 output.Write(adx.Value);output.Write(adx.Atr);output.Write(setup.Vwap);
 if(eligible&&valid){signals.WriteLine(i);setup.Consume();}
 i++;
 }}}
}
"""
with tempfile.TemporaryDirectory() as folder:
 p=Path(folder);matrix.astype('<f8').tofile(p/'bars.bin');(p/'Replay.cs').write_text(cs)
 csc=r'C:/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe'
 subprocess.run([csc,'/nologo','/out:'+str(p/'Replay.exe'),str(p/'Replay.cs')],check=True)
 subprocess.run([str(p/'Replay.exe'),str(p/'bars.bin'),str(p/'values.bin'),str(p/'signals.txt')],check=True)
 result=np.fromfile(p/'values.bin',dtype='<f8').reshape(-1,3)
 actual=[int(x) for x in (p/'signals.txt').read_text().splitlines()]
 index={t.isoformat():i for i,t in enumerate(times)}
 expected=[index[x['signal_time']] for x in reference['ledger']]
 print('Source bars',len(f),'complete sessions',len(sessions),'reference entries',len(expected),'production entries',len(actual))
 print('Max ADX error',np.max(np.abs(result[:,0]-adx)),'ATR error',np.max(np.abs(result[:,1]-atr)))
 active=(minute>=510)&np.isfinite(vwap)
 print('Max VWAP error',np.max(np.abs(result[active,2]-vwap[active])))
 mismatch=[(str(times.iloc[x]),str(times.iloc[y])) for x,y in zip(actual,expected) if x!=y]
 print('Signal mismatch samples',mismatch[:5])
 assert np.allclose(result[:,0],adx,atol=1e-10,rtol=0)
 assert np.allclose(result[:,1],atr,atol=1e-10,rtol=0)
 assert np.allclose(result[active,2],vwap[active],atol=1e-8,rtol=0)
 assert actual==expected,'Entry sequence differs from selected development model'
 print('PASS: compiled production core matches full-source development entries and M1 ADX/ATR/VWAP')

