"""Compile the actual display history; chart time must not fake a flat M1 ADX."""
from pathlib import Path
import subprocess,tempfile
source=Path(__file__).resolve().parents[1]/'VWAPPullbackNT8.cs'
s=source.read_text(encoding='utf-8-sig')
def block(token):
 i=s.index(token);b=s.index('{',i);level=1;j=b+1
 while level:level+=(s[j]=='{')-(s[j]=='}');j+=1
 return s[i:j]
history=block('internal sealed class AdxHistory')
fixture='''
class Proof {
static void Check(bool x,string m){if(!x)throw new Exception(m);}
static void Main(){
 var h=new AdxHistory();var d=new DateTime(2026,9,24,10,0,0);
 Check(!h.EligibleAt(d),"missing source is grey");
 h.Store(d,25,24,true);
 Check(!h.EligibleAt(d.AddMinutes(30)),"rising M1 stays grey on later M30 chart timestamp");
 Check(h.At(d.AddMinutes(30),0)==25,"source value is retained");
 h.Store(d.AddMinutes(1),24,25,true);
 Check(h.EligibleAt(d.AddMinutes(30)),"falling M1 is green");
 h.Store(d.AddMinutes(2),24,24,true);
 Check(h.EligibleAt(d.AddMinutes(30)),"flat is allowed");
 h.Store(d.AddMinutes(3),20,21,true);
 Check(!h.EligibleAt(d.AddMinutes(30)),"threshold equality is grey");
 h.Store(d.AddMinutes(4),25,26,false);
 Check(!h.EligibleAt(d.AddMinutes(30)),"warmup is grey");
 h.Clear();Check(!h.EligibleAt(d.AddMinutes(30)),"reload clears old eligibility");
 h.Store(d,100);Check(h.At(d,0)==100&&!h.EligibleAt(d),"numeric VWAP history keeps its original API");
 Console.WriteLine("PASS: rising/falling/flat/threshold/warmup/gap/chart-time/reload display eligibility");
}}
'''
with tempfile.TemporaryDirectory() as folder:
 p=Path(folder);(p/'Proof.cs').write_text('using System;using System.Collections.Generic;\n'+history+'\n'+fixture)
 subprocess.run([r'C:/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe','/nologo','/out:'+str(p/'Proof.exe'),str(p/'Proof.cs')],check=True)
 subprocess.run([str(p/'Proof.exe')],check=True)
assert 'published.At(end.AddMinutes(-1)' not in s
print('PASS: plots use source-paired eligibility')
