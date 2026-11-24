"""Execute the production ownership/fill methods with a tiny broker test double."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / "OpenDriveNT8.cs").read_text(encoding="utf-8-sig")

def extract(signature):
    start = source.index(signature)
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]

methods = "\n".join(extract(s) for s in (
    "public sealed class LiveOrder", "public sealed class LiveCheckpoint",
    "private static bool LiveTerminal", "private static int LiveDirection",
    "private bool BindLiveOrder", "private void ProcessLiveExecution",
    "private void RestoreLiveFields", "private void LiveOrderEvent",
    "private bool PollLive",
))
fixture = r'''
using System;
using System.Collections.Generic;
using System.Linq;
enum ErrorCode { NoError, Denied }
enum OrderAction { Buy, BuyToCover, Sell, SellShort }
enum OrderType { Market, StopMarket }
enum OrderState { Initialized, Working, Filled, CancelSubmitted, Cancelled, Rejected }
enum MarketPosition { Flat, Long, Short }
enum ConnectionStatus { Connected, Disconnected }
class Instrument { public string FullName = "MNQ DEC26"; }
class Connection { public ConnectionStatus Status=ConnectionStatus.Connected; }
class Position { public Instrument Instrument=new Instrument(); public int Quantity; public MarketPosition MarketPosition; }
class BrokerAccount {
 public List<Order> Orders=new List<Order>(); public List<Execution> Executions=new List<Execution>();
 public List<Position> Positions=new List<Position>(); public Connection Connection=new Connection();
}
class Order {
 public object Account; public Instrument Instrument = new Instrument();
 public string Name, OrderId; public OrderAction OrderAction;
 public OrderType OrderType; public int Quantity=1,Filled; public double StopPrice; public OrderState OrderState;
}
class Execution { public Order Order; public string ExecutionId; public int Quantity; public double Price; public DateTime Time; }
static class ProductExposure { public static void ObserveExit(Order o) {} public static void Release(string owner) {} }
class Fixture {
 BrokerAccount Account = new BrokerAccount(); Instrument Instrument = new Instrument();
 LiveCheckpoint live = new LiveCheckpoint();
 Dictionary<string,Order> liveOrders = new Dictionary<string,Order>();
 bool LiveExecution = true, inPosition, trailActivated, costCoveredLocked, livePolling, liveReady;
 int LiveQuantity { get { return live.Entered-live.Exited; } }
 Order odSLOrder;
 double positionEntryPrice, positionStopPrice, positionInitialRisk, positionExtreme;
 int positionDir,longTradesToday,shortTradesToday,writes;
 DateTime positionEntryTime,lastEvaluatedDay;
 string liveFault, statusMessage;
 void LiveWait(string s) { statusMessage=s; }
 void SaveLive() { if (liveFault != null) throw new Exception("fault preceded persistence"); writes++; }
__METHODS__
 static void Assert(bool ok,string message) { if (!ok) throw new Exception(message); }
 Order OrderFor(string name,string id, OrderAction action, OrderType type=OrderType.Market) {
  return new Order { Account=Account,Name=name,OrderId=id,OrderAction=action,OrderType=type,OrderState=OrderState.Working };
 }
 static void Main() {
  var f = new Fixture();
  var entry = new LiveOrder { Name="owned_Long",Id="123",Role="Entry",Action="Buy",Type="Market",Quantity=1,State="Working" };
  f.live.Orders.Add(entry);
  var broker = f.OrderFor(entry.Name,entry.Id,OrderAction.Buy);
  var execution = new Execution { Order=broker,ExecutionId="fill1",Quantity=1,Price=100 };
  var foreign = f.OrderFor(entry.Name,entry.Id,OrderAction.Buy); foreign.Account=new object();
  f.ProcessLiveExecution(new Execution { Order=foreign,ExecutionId="foreign",Quantity=1,Price=50 });
  Assert(f.live.Entered==0,"foreign account fill was adopted");
  foreign=f.OrderFor(entry.Name,entry.Id,OrderAction.Buy); foreign.Instrument.FullName="NQ DEC26";
  f.ProcessLiveExecution(new Execution { Order=foreign,ExecutionId="foreign2",Quantity=1,Price=50 });
  Assert(f.live.Entered==0,"foreign contract fill was adopted");
  f.ProcessLiveExecution(execution); f.ProcessLiveExecution(execution);
  Assert(f.live.Entered==1 && f.live.EntrySum==100 && entry.Processed==1,"fill was lost or counted twice");
  var stop = new LiveOrder { Name="owned_Stop",Id="456",Role="Stop",Action="SellShort",Type="StopMarket",Quantity=1,State="Working" };
  f.live.Orders.Add(stop);
  var brokerStop=f.OrderFor(stop.Name,stop.Id,OrderAction.Sell,OrderType.StopMarket);
  Assert(f.BindLiveOrder(stop,brokerStop,false),"provider Sell alias rejected");
  brokerStop.OrderId="different"; Assert(!f.BindLiveOrder(stop,brokerStop,false),"different broker ID accepted"); brokerStop.OrderId=stop.Id;
  stop.State="Cancelled"; Assert(f.BindLiveOrder(stop,brokerStop,false) && stop.State=="Cancelled","late Working revived terminal stop");
  f.live.Entry=100; f.live.Stop=102; f.live.Risk=10; f.live.Extreme=110;
  f.live.Trail=true; f.live.BreakEven=true; f.live.Side=1;
  f.RestoreLiveFields();
  Assert(f.positionInitialRisk==10 && f.positionExtreme==110 && f.positionStopPrice==102 && f.trailActivated && f.costCoveredLocked,"restart lost risk/trailing state");
  broker.Filled=1;broker.OrderState=OrderState.Filled;entry.Reported=1;entry.State="Filled";
  brokerStop.StopPrice=103;stop.State="Working";
  f.Account.Orders.Add(broker);f.Account.Orders.Add(brokerStop);
  f.Account.Positions.Add(new Position {Quantity=2,MarketPosition=MarketPosition.Long});
  Assert(f.PollLive() && f.odSLOrder==brokerStop && f.positionStopPrice==103,"same-direction foreign quantity blocked exact stop handoff or loosened stop");
  f.Account.Positions.Clear();
  Assert(!f.PollLive() && f.live.Entered-f.live.Exited==1,"account flatness fabricated an owned exit");
  f.Account.Positions.Add(new Position {Quantity=1,MarketPosition=MarketPosition.Long});
  f.Account.Orders.Remove(brokerStop);
  Assert(!f.PollLive() && f.statusMessage.Contains("missing/conflicting"),"missing protective snapshot permitted recovery");
  f.Account.Orders.Add(brokerStop);brokerStop.OrderId="wrong";
  Assert(!f.PollLive(),"conflicting broker ID permitted recovery");brokerStop.OrderId=stop.Id;
  f.Account.Connection.Status=ConnectionStatus.Disconnected;
  Assert(!f.PollLive(),"disconnected snapshots permitted recovery");f.Account.Connection.Status=ConnectionStatus.Connected;
  Assert(f.PollLive(),"pending evidence failed to recover dynamically");
  int priorWrites=f.writes;
  stop.State="Working"; f.LiveOrderEvent(brokerStop,ErrorCode.Denied,"Liquidation only");
  Assert(f.writes==priorWrites+1 && f.live.Restriction.Contains("restriction") && f.liveFault==f.live.Restriction,"restriction not committed before fault");
  Console.WriteLine("PASS OpenDrive production recovery: foreign fills, duplicate fills, aliases, IDs, delayed state, risk/trail restart, durable restriction");
 }
}
'''.replace("__METHODS__", methods)
with tempfile.TemporaryDirectory(prefix="od_owned_fixture_") as directory:
    path = Path(directory)
    (path / "fixture.cs").write_text(fixture)
    compiler = Path(r"C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe")
    subprocess.run([str(compiler), "/nologo", "/out:" + str(path / "fixture.exe"), str(path / "fixture.cs")], check=True, capture_output=True, text=True)
    subprocess.run([str(path / "fixture.exe")], check=True)

# The handoff itself must be read-only. Rejected/stale evidence must not trigger
# broker operations, and the fill callback drives protection after acknowledgement.
handoff = extract("private void RecoverOpenPosition")
assert all(token not in handoff for token in ("SubmitStop(", "Account.Submit", "Account.Change", "Account.Cancel"))
stop = extract("private void SubmitStop")
assert stop.index("LiveQuantity <= 0") < stop.index('NewLiveIntent("Stop"')
assert "LiveMaintenance();" in extract("protected override void OnExecutionUpdate")
assert "if (!LiveExecution) { inPosition = false;" in source
print("PASS OpenDrive read-only handoff and acknowledged-fill protection boundaries")
