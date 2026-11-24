"""Execute the production broker boundary and reconnect floor in a disconnected account."""
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]

def method(text, name):
    match = re.search(r"private\s+\w+\s+" + name + r"\(", text)
    assert match, name
    left = text.index("{", match.start())
    right, depth = left + 1, 1
    while depth:
        depth += (text[right] == "{") - (text[right] == "}")
        right += 1
    return text[match.start():right]

for folder, filename in [("VaultBreak_NT", "VaultBreakNT8.cs"),
                         ("OvernightBiasRangeBreakout_NT", "OvernightBiasRangeBreakoutNT8.cs")]:
    if folder != Path(__file__).resolve().parents[1].name:
        continue
    text = (root / folder / filename).read_text()
    assert "ConnectionLossHandling = ConnectionLossHandling.KeepRunning;" in text
    # Broker APIs occur only inside their guarded boundaries.
    for native in ("SubmitOrderUnmanaged(", "CancelOrder(", "ChangeOrder("):
        assert text.count(native) == 1, (folder, native)
    methods = "\n".join(method(text, n) for n in [
        "BrokerReady", "ObserveBrokerConnection", "SubmitOwnedOrder",
        "CancelOwnedOrder", "ChangeOwnedOrder"])
    close_methods = method(text, "DriveClose")
    if folder == "VaultBreak_NT":
        close_methods += "\n" + method(text, "CancelSafe")
    timer = method(text, "TimerStep")
    assert "ObserveBrokerConnection(now)" in timer
    assert "if (connected)" in timer or "if(connected)" in timer
    harness = r'''
using System;
using System.Linq;
using System.Collections.Generic;
enum State { Historical, Realtime }
enum ConnectionStatus { Connected, Disconnected }
enum OrderAction { Buy, Sell, BuyToCover }
enum OrderType { Market, StopMarket }
enum OrderState { Working, CancelPending, CancelSubmitted, Cancelled }
class Order { public string Name; public OrderType OrderType; public OrderState OrderState; }
class Broker { public ConnectionStatus ConnectionStatus; }
class Probe {
 State State=State.Realtime; Broker Account=new Broker();
 bool connectionPaused; DateTime recoveryFloor; int requests;
 bool closing, driving, closingDrive, entryPending;
 int ownedNet=1,executionSeries,sequence; string owner="Probe",entryName="entry",status;
 Order entryOrder,closeOrder;
 Dictionary<string,Order> orders=new Dictionary<string,Order>();
 string Name="Probe";
 void Print(string s) {}
 Order SubmitOrderUnmanaged(int a,OrderAction b,OrderType c,int d,double e,double f,string g,string h)
 { requests++; var order=new Order{Name=h,OrderType=c,OrderState=OrderState.Working};orders[h]=order;return order; }
 void CancelOrder(Order o) { requests++;o.OrderState=OrderState.CancelPending; }
 void ChangeOrder(Order o,int q,double l,double s) { requests++; }
 bool Settled(Order o) { return o==null || o.OrderState==OrderState.Cancelled; }
 bool Working(Order o) { return o!=null && !Settled(o); }
 bool ExecutionsCaughtUp(Order o) { return true; }
 void ClearLegs() {}
 void ReleaseExposure() {}
 METHODS
 CLOSE_METHODS
 void SendAll() { SubmitOwnedOrder(0,OrderAction.Buy,OrderType.Market,1,0,0,"","entry");
     CancelOwnedOrder(new Order()); ChangeOwnedOrder(new Order(),1,0,1); }
 static void Check(bool ok,string message) { if(!ok)throw new Exception(message); }
 static void Main() {
   var p=new Probe(); DateTime t=new DateTime(2022,1,10,10,0,0);
   p.Account.ConnectionStatus=ConnectionStatus.Disconnected;
   Check(!p.ObserveBrokerConnection(t),"disconnect not observed"); p.SendAll();
   Check(p.requests==0,"offline broker request");
   p.ObserveBrokerConnection(t.AddMinutes(5)); p.SendAll();
   Check(p.requests==0 && p.recoveryFloor==t.AddMinutes(5),"offline timer advanced incorrectly");
   p.Account.ConnectionStatus=ConnectionStatus.Connected;
   Check(p.ObserveBrokerConnection(t.AddMinutes(6)),"reconnect not observed");
   Check(p.recoveryFloor==t.AddMinutes(6),"stale reconnect floor");
   p.SendAll(); Check(p.requests==3,"online operations blocked");
   p.State=State.Historical; p.Account=null; p.SendAll();
   Check(p.requests==6,"historical simulation blocked");
   var q=new Probe();q.closing=true;
   var stop=new Order{Name="stop",OrderType=OrderType.StopMarket,OrderState=OrderState.Working};
   q.orders[stop.Name]=stop;
   q.Account.ConnectionStatus=ConnectionStatus.Disconnected;q.DriveClose();
   Check(q.requests==0 && q.closing,"offline close intent discarded");
   q.Account.ConnectionStatus=ConnectionStatus.Connected;q.DriveClose();
   Check(q.requests==1 && stop.OrderState==OrderState.CancelPending,"reconnect cancellation not resumed");
   q.DriveClose();Check(q.requests==1,"duplicate pending cancellation");
   stop.OrderState=OrderState.Cancelled;q.DriveClose();
   Check(q.requests==2,"owned market close not resumed");
   q.DriveClose();Check(q.requests==2,"duplicate market close");
   Console.WriteLine("PASS offline requests, reconnect freshness, historical execution, deferred close and no duplicate close");
 }
}'''.replace("CLOSE_METHODS", close_methods).replace("METHODS", methods)
    with tempfile.TemporaryDirectory(prefix="connection-resume-") as work:
        p = Path(work)
        (p / "Probe.cs").write_text(harness)
        build = subprocess.run([r"C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
                                "/nologo", "/out:" + str(p / "Probe.exe"), str(p / "Probe.cs")],
                               capture_output=True, text=True)
        assert build.returncode == 0, build.stdout
        run = subprocess.run([str(p / "Probe.exe")], capture_output=True, text=True)
        assert run.returncode == 0, run.stdout + run.stderr
        print(folder + ": " + run.stdout.strip())

