//+------------------------------------------------------------------+
//|                                                 OpenDriveNT8.cs  |
//| OpenDrive - Institutional 09:30 AM New York Cash Open Drive      |
//| Developed by Osamwonyi Eric (You_FoundEric)                      |
//| Copyright 2026-2027, Osamwonyi Eric (@You_FoundEric)             |
//+------------------------------------------------------------------+

using NinjaTrader.Cbi;
using NinjaTrader.Core;
using NinjaTrader.Data;
using NinjaTrader.Gui.Chart;
using NinjaTrader.Gui;
using NinjaTrader.NinjaScript.DrawingTools;
using NinjaTrader.NinjaScript.Indicators;
using Color4 = SharpDX.Color4;
using RectangleF = SharpDX.RectangleF;
using Vector2 = SharpDX.Vector2;
using RenderTarget = SharpDX.Direct2D1.RenderTarget;
using RoundedRectangle = SharpDX.Direct2D1.RoundedRectangle;
using DrawTextOptions = SharpDX.Direct2D1.DrawTextOptions;
using TextFormat = SharpDX.DirectWrite.TextFormat;
using WordWrapping = SharpDX.DirectWrite.WordWrapping;
using System.Collections.Generic;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.ComponentModel.DataAnnotations;
using System.Globalization;
using System.IO;
using System.Net.Http;
using System.Runtime.CompilerServices;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using System.Windows;
using System;

namespace NinjaTrader.NinjaScript.Strategies
{
public enum OpenDriveRiskMode
{
	[Display(Name = "Dynamic Volatility (Prop Firms: 0.33% / 0.50% / 1.00% scaled)")]
	DynamicVolatility,
	[Display(Name = "Static Fixed Risk (Live Accounts: Fixed 1.00x Base)")]
	StaticFixed
}

public enum OpenDriveSizingType
{
	[Display(Name = "Percentage Risk (% of Account Balance / Capital)")]
	PercentRisk,
	[Display(Name = "Fixed Dollar Risk ($ Cash Budget per Trade)")]
	FixedDollar,
	[Display(Name = "Fixed Contracts (Constant Quantity)")]
	FixedContracts
}

public enum OpenDriveNewsImpact
{
	[Display(Name = "Off")]
	Off,
	[Display(Name = "Red Folder Only (High Impact)")]
	Red,
	[Display(Name = "Red & Orange/Medium Folders")]
	RedYellow,
	[Display(Name = "All News Folders")]
	All
}

public enum OpenDriveNewsWindow
{
	[Display(Name = "5 Minutes (2.5m before / after)")]
	Five = 5,
	[Display(Name = "10 Minutes (5m before / after)")]
	Ten = 10,
	[Display(Name = "14 Minutes (7m before / after)")]
	Fourteen = 14,
	[Display(Name = "20 Minutes (10m before / after)")]
	Twenty = 20
}

public class OpenDriveNT8 : Strategy
{
	private static class ProductExposure
	{
		private const string Slot = "IndependentEquityDirectionExposure.v1";
		private const string ExactSlot = "IndependentExactContractDirectionExposure.v1";
		private const string ExitSlot = "IndependentVerifiedExitOrders.v1";
		private static readonly HashSet<string> Equity = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
		{
			"ES", "MES", "NES", "NQ", "MNQ", "NNQ", "YM", "MYM", "RTY", "M2K",
			"EMD", "NKD", "FDAX", "FDXM", "FDXS", "FESX", "FSXE", "FXXP"
		};

		internal static void ObserveExit(Order order)
		{
			lock (AppDomain.CurrentDomain)
			{
				var exits = AppDomain.CurrentDomain.GetData(ExitSlot) as HashSet<Order>;
				if (exits == null) AppDomain.CurrentDomain.SetData(ExitSlot, exits = new HashSet<Order>());
				exits.RemoveWhere(o => Terminal(o));
				exits.Add(order);
			}
		}

		internal static bool Reserve(string ownerId, int side, Account account, Instrument instrument, bool broad, out string reason, HashSet<Order> ownEntries = null, long ownNet = 0)
		{
			return ReserveCore(ownerId, side, account, instrument, broad, false, out reason, ownEntries, ownNet);
		}

		internal static bool ReserveBoth(string ownerId, Account account, Instrument instrument, bool broad, out string reason, HashSet<Order> ownEntries = null, long ownNet = 0)
		{
			return ReserveCore(ownerId, 0, account, instrument, broad, true, out reason, ownEntries, ownNet);
		}

		private static bool ReserveCore(string ownerId, int side, Account ownAccount, Instrument ownInstrument, bool broad, bool both, out string reason, HashSet<Order> ownEntries, long ownNet)
		{
			if (string.IsNullOrEmpty(ownerId) || ownAccount == null || ownInstrument == null || (!both && side != 1 && side != -1))
			{
				reason = "Cannot verify shared account/contract; entry blocked";
				return false;
			}
			// FX/metals reserve their own exact contract; they never represent index direction.
			bool index = Equity.Contains(ownInstrument.MasterInstrument.Name);
			broad = broad && index;
			var snapshots = new Dictionary<Account, Tuple<Position[], Order[]>>();
			var managedExits = new HashSet<Order>();
			try
			{
				Account[] accounts;
				lock (Account.All) accounts = broad ? Account.All.ToArray() : new[] { ownAccount };
				foreach (Account account in accounts)
				{
					Position[] positions; Order[] orders; Execution[] executions;
					lock (account.Positions) positions = account.Positions.ToArray();
					lock (account.Orders) orders = account.Orders.ToArray();
					lock (account.Executions) executions = account.Executions.ToArray();
					// Only exact object references supplied by the owned executor may be excluded.
					orders = orders.Where(o => !(ReferenceEquals(account, ownAccount) && ownEntries != null && ownEntries.Contains(o))).ToArray();
					snapshots[account] = Tuple.Create(positions, orders);
					foreach (Order order in orders) if (ManagedExit(order, executions)) managedExits.Add(order);
				}
			}
			catch (Exception) { reason = "Cannot snapshot account exposure; entry blocked"; return false; }
			lock (AppDomain.CurrentDomain)
			{
				var directions = AppDomain.CurrentDomain.GetData(Slot) as Dictionary<string, int>;
				if (directions == null) AppDomain.CurrentDomain.SetData(Slot, directions = new Dictionary<string, int>());
				var exact = AppDomain.CurrentDomain.GetData(ExactSlot) as Dictionary<string, Tuple<Account, string, int>>;
				if (exact == null) AppDomain.CurrentDomain.SetData(ExactSlot, exact = new Dictionary<string, Tuple<Account, string, int>>());
				if ((broad && directions.Any(x => x.Key != ownerId && (both || x.Value != side))) ||
					exact.Any(x => x.Key != ownerId && ReferenceEquals(x.Value.Item1, ownAccount) && x.Value.Item2 == ownInstrument.FullName && (both || x.Value.Item3 != side)))
				{
					reason = "Opposing entry reserved; same-contract netting blocked";
					return false;
				}
				try
				{
					foreach (var snapshot in snapshots)
					{
						Account account = snapshot.Key;
						Position[] positions = snapshot.Value.Item1;
						Order[] orders = snapshot.Value.Item2;
						var instruments = positions.Select(p => p.Instrument).Concat(orders.Select(o => o.Instrument))
							.Concat(ReferenceEquals(account, ownAccount) ? new[] { ownInstrument } : new Instrument[0])
							.Where(i => i != null && ((ReferenceEquals(account, ownAccount) && i.FullName == ownInstrument.FullName) ||
								(broad && (Equity.Contains(i.MasterInstrument.Name) || i.MasterInstrument.Name == "FVS"))))
							.GroupBy(i => i.FullName).Select(g => g.First());
						foreach (Instrument instrument in instruments)
						{
							long net = positions.Where(p => p.Instrument.FullName == instrument.FullName)
								.Sum(p => (long)p.Quantity * (p.MarketPosition == MarketPosition.Long ? 1 : p.MarketPosition == MarketPosition.Short ? -1 : 0));
							Order[] active = orders.Where(o => o.Instrument.FullName == instrument.FullName && !Terminal(o)).ToArray();
							long foreignNet = net;
							if (ReferenceEquals(account, ownAccount) && instrument.FullName == ownInstrument.FullName && ownNet != 0)
							{
								if (Math.Sign(net) != Math.Sign(ownNet) || Math.Abs(net) < Math.Abs(ownNet))
								{
									reason = "Owned/account quantity disagreement; entry blocked";
									return false;
								}
								foreignNet -= ownNet;
							}
							foreach (int wantedSide in both ? new[] { 1, -1 } : new[] { side })
							{
								if (instrument.MasterInstrument.Name == "FVS" && wantedSide < 0) continue;
								int wanted = instrument.MasterInstrument.Name == "FVS" ? -1 : wantedSide;
								if (Opposes(active, net, wanted, managedExits, out reason, foreignNet))
								{
									reason += ": " + account.Name + " / " + instrument.FullName;
									return false;
								}
							}
						}
					}
				}
				catch (Exception) { reason = "Cannot verify account product exposure; entry blocked"; return false; }
				// BOTH is published once, under this same lock: no one-sided OCO reservation window.
				int reserved = ownNet != 0 && ownNet * side < 0 ? 0 : side;
				if (index) directions[ownerId] = reserved; else directions.Remove(ownerId);
				exact[ownerId] = Tuple.Create(ownAccount, ownInstrument.FullName, reserved);
				reason = null;
				return true;
			}
		}

		private static bool Terminal(Order order)
		{
			return order.OrderState == OrderState.Filled || order.OrderState == OrderState.Cancelled || order.OrderState == OrderState.Rejected;
		}

		private static bool ManagedExit(Order order, Execution[] executions)
		{
			if (string.IsNullOrEmpty(order.FromEntrySignal)) return false;
			return executions.Any(e => e.Order != null && e.Quantity > 0 && ReferenceEquals(e.Order.Account, order.Account) &&
				e.Order.Instrument.FullName == order.Instrument.FullName && e.Order.Name == order.FromEntrySignal &&
				((order.OrderAction == OrderAction.Sell && e.Order.OrderAction == OrderAction.Buy) ||
				 ((order.OrderAction == OrderAction.Buy || order.OrderAction == OrderAction.BuyToCover) && e.Order.OrderAction == OrderAction.SellShort)));
		}

		internal static bool Opposes(Order[] orders, long net, int wanted, HashSet<Order> managedExits, out string reason, long? directionalNet = null)
		{
			if ((directionalNet ?? net) * wanted < 0) { reason = "Opposing account position; entry blocked"; return true; }
			var protective = new List<Order>();
			foreach (Order order in orders)
			{
				int direction = order.OrderAction == OrderAction.Buy || order.OrderAction == OrderAction.BuyToCover ? 1 : -1;
				var exitsProof = AppDomain.CurrentDomain.GetData(ExitSlot) as HashSet<Order>;
				bool exit = managedExits.Contains(order) || (exitsProof != null && exitsProof.Contains(order));
				if (!exit && order.OrderAction == OrderAction.BuyToCover)
				{
					reason = "Unverified BuyToCover order; entry blocked (" + order.Name + ")";
					return true;
				}
				if (exit)
				{
					if (net == 0 || Math.Sign(net) == direction) { reason = "Uncovered protective order; entry blocked (" + order.Name + ")"; return true; }
					protective.Add(order);
				}
				else if (direction != wanted) { reason = "Opposing or unverified order; entry blocked (" + order.Name + ")"; return true; }
			}
			long exits = protective.GroupBy(o => string.IsNullOrEmpty(o.Oco) ? (object)o : o.Oco)
				.Sum(g => g.Max(o => (long)Math.Max(0, o.Quantity - o.Filled)));
			if (exits > Math.Abs(net)) { reason = "Uncovered protective orders; entry blocked"; return true; }
			reason = null;
			return false;
		}

		internal static void Release(string ownerId)
		{
			lock (AppDomain.CurrentDomain)
			{
				if (ownerId == null) return;
				var directions = AppDomain.CurrentDomain.GetData(Slot) as Dictionary<string, int>;
				var exact = AppDomain.CurrentDomain.GetData(ExactSlot) as Dictionary<string, Tuple<Account, string, int>>;
				if (directions != null) directions.Remove(ownerId);
				if (exact != null) exact.Remove(ownerId);
			}
		}
	}

	// Live ownership is independent of native historical Strategy.Position. New trades
	// remain managed; a replacement chart manages exact saved broker orders directly.
	public sealed class LiveOrder
	{
		public string Name, Id, Role, Action, Type, State;
		public int Quantity, Reported, Processed;
		public double Stop, Limit;
	}
	public sealed class LiveCheckpoint
	{
		public int Version = 1, Sequence, Side, Entered, Exited;
		public string Identity, Owner, Restriction, CloseReason;
		public double EntrySum, Entry, Stop, Risk, Extreme;
		public bool Trail, BreakEven;
		public DateTime EntryTime, EvaluatedDay;
		public int Buys, Sells;
		public List<LiveOrder> Orders = new List<LiveOrder>();
		public List<string> Executions = new List<string>();
	}
	private LiveCheckpoint live;
	private FileStream liveLease;
	private string livePath, liveIdentity, liveFault;
	private bool accountTransport, liveReady, livePolling;
	private bool resumePendingLimit;
	private readonly Dictionary<string, Order> liveOrders = new Dictionary<string, Order>();
	private Timer liveTimer;
	private bool LiveExecution { get { return State == State.Realtime && !IsInStrategyAnalyzer; } }
	private int LiveQuantity { get { return LiveExecution && live != null ? live.Entered - live.Exited : Position.Quantity; } }
	private string EntrySignal(int side) { return LiveExecution && live != null ? live.Owner + (side > 0 ? "_Long" : "_Short") : side > 0 ? "OD_Long" : "OD_Short"; }
	private static bool LiveTerminal(string state) { return state == "Filled" || state == "Cancelled" || state == "Rejected"; }
	private static int LiveDirection(string action) { return action == "Buy" || action == "BuyToCover" ? 1 : action == "Sell" || action == "SellShort" ? -1 : 0; }
	private static string LiveHash(string value)
	{
		using (var sha = SHA256.Create()) return BitConverter.ToString(sha.ComputeHash(Encoding.UTF8.GetBytes(value))).Replace("-", "").ToLowerInvariant();
	}
	private void OpenLiveStore()
	{
		if (IsInStrategyAnalyzer) return;
		liveIdentity = Account.Name + "|" + Account.Connection.Options.Provider + "|" + Instrument.FullName + "|OpenDrive";
		string directory = Path.Combine(Globals.UserDataDir, "OpenDrive", "recovery");
		Directory.CreateDirectory(directory);
		livePath = Path.Combine(directory, LiveHash(liveIdentity) + ".journal");
		liveLease = new FileStream(livePath + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
		if (File.Exists(livePath))
		{
			string[] envelope = File.ReadAllLines(livePath);
			if (envelope.Length != 2 || LiveHash(envelope[1]) != envelope[0]) throw new InvalidOperationException("OpenDrive owned checkpoint checksum failed; broker protection untouched.");
			live = new JavaScriptSerializer().Deserialize<LiveCheckpoint>(envelope[1]);
			if (live == null || live.Version != 1 || live.Identity != liveIdentity || string.IsNullOrEmpty(live.Owner) || live.Entered < live.Exited || live.Exited < 0 || live.Orders == null || live.Executions == null)
				throw new InvalidOperationException("OpenDrive owned checkpoint identity/state invalid; broker protection untouched.");
			if (live.Orders.Any(o => o == null || string.IsNullOrEmpty(o.Name) || !o.Name.StartsWith("OD_", StringComparison.Ordinal) ||
				(o.Role != "Entry" && o.Role != "Stop" && o.Role != "Close") || LiveDirection(o.Action) == 0 ||
				(o.Type != "Market" && o.Type != "Limit" && o.Type != "StopMarket") || o.Quantity <= 0 || o.Processed < 0 || o.Reported < o.Processed || o.Reported > o.Quantity) ||
				live.Orders.Select(o => o.Name).Distinct().Count() != live.Orders.Count || live.Executions.Any(string.IsNullOrEmpty) || live.Executions.Distinct().Count() != live.Executions.Count ||
				new[] { live.Entry, live.Stop, live.Risk, live.Extreme, live.EntrySum }.Any(v => double.IsNaN(v) || double.IsInfinity(v)) ||
				(live.Entered > live.Exited && (Math.Abs(live.Side) != 1 || live.Risk <= 0 || live.Stop <= 0 || live.Entry <= 0)))
				throw new InvalidOperationException("OpenDrive owned checkpoint quantities/risk invalid; broker protection untouched.");
			accountTransport = live.Orders.Count != 0 || live.Entered != live.Exited;
		}
		else live = new LiveCheckpoint { Identity = liveIdentity, Owner = "OD_" + Guid.NewGuid().ToString("N") };
	}
	private void SaveLive()
	{
		if (!LiveExecution || live == null || liveLease == null) return;
		live.Entry = positionEntryPrice; live.Stop = positionStopPrice; live.Risk = positionInitialRisk;
		live.Extreme = positionExtreme; live.Trail = trailActivated; live.BreakEven = costCoveredLocked;
		live.EntryTime = positionEntryTime; live.EvaluatedDay = lastEvaluatedDay;
		live.Buys = longTradesToday; live.Sells = shortTradesToday;
		string json = new JavaScriptSerializer().Serialize(live);
		string temporary = livePath + "." + Guid.NewGuid().ToString("N") + ".tmp";
		try
		{
			using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
			using (var writer = new StreamWriter(stream, new UTF8Encoding(false)))
			{ writer.Write(LiveHash(json) + "\n" + json + "\n"); writer.Flush(); stream.Flush(true); }
			if (File.Exists(livePath)) File.Replace(temporary, livePath, livePath + ".previous"); else File.Move(temporary, livePath);
		}
		catch { liveReady = false; liveFault = "Checkpoint write failed; no further order requests"; throw; }
		finally { if (File.Exists(temporary)) File.Delete(temporary); }
	}
	private void RestoreLiveFields()
	{
		positionDir = live.Side; positionEntryPrice = live.Entry; positionStopPrice = live.Stop;
		positionInitialRisk = live.Risk; positionExtreme = live.Extreme; trailActivated = live.Trail;
		costCoveredLocked = live.BreakEven; positionEntryTime = live.EntryTime;
		lastEvaluatedDay = live.EvaluatedDay; longTradesToday = live.Buys; shortTradesToday = live.Sells;
		inPosition = live.Entered > live.Exited;
	}
	private void LiveWait(string reason)
	{
		liveReady = false;
		statusMessage = "Recovery pending: " + reason;
	}
	private bool BindLiveOrder(LiveOrder saved, Order observed, bool callback)
	{
		if (observed == null || observed.Account != Account || observed.Instrument == null || observed.Instrument.FullName != Instrument.FullName || observed.Name != saved.Name ||
			LiveDirection(observed.OrderAction.ToString()) != LiveDirection(saved.Action) || observed.OrderType.ToString() != saved.Type || observed.Quantity != saved.Quantity || observed.Filled < saved.Processed)
			return false;
		Order registered;
		bool exactObject = liveOrders.TryGetValue(saved.Name, out registered) && ReferenceEquals(registered, observed);
		if (saved.Id != observed.OrderId)
		{
			Guid temporary;
			if (!callback || (!string.IsNullOrEmpty(saved.Id) && (!exactObject || !Guid.TryParse(saved.Id, out temporary)))) return false;
			saved.Id = observed.OrderId; // only the exact registered mutable callback may hand off its adapter ID
		}
		if (string.IsNullOrEmpty(saved.Id)) return false;
		liveOrders[saved.Name] = observed;
		// An equal-fill delayed Working callback must not revive terminal/cancel-pending state.
		if (!(saved.Reported == observed.Filled && (LiveTerminal(saved.State) || saved.State == "CancelPending" || saved.State == "CancelSubmitted") && !LiveTerminal(observed.OrderState.ToString())))
			saved.State = observed.OrderState.ToString();
		saved.Reported = Math.Max(saved.Reported, observed.Filled);
		if (saved.Role == "Stop" && !LiveTerminal(saved.State)) ProductExposure.ObserveExit(observed);
		return true;
	}
	private void ProcessLiveExecution(Execution execution)
	{
		if (execution == null || execution.Order == null || string.IsNullOrEmpty(execution.ExecutionId) || live.Executions.Contains(execution.ExecutionId)) return;
		if (execution.Order.Account != Account || execution.Order.Instrument == null || execution.Order.Instrument.FullName != Instrument.FullName) return;
		LiveOrder saved = live.Orders.FirstOrDefault(o => o.Name == execution.Order.Name && o.Id == execution.Order.OrderId);
		if (saved == null) return;
		if (LiveDirection(saved.Action) != LiveDirection(execution.Order.OrderAction.ToString()) || saved.Type != execution.Order.OrderType.ToString()) throw new InvalidOperationException("Owned execution identity conflicts: " + saved.Name);
		if (execution.Quantity <= 0 || saved.Processed + execution.Quantity > saved.Quantity) throw new InvalidOperationException("Owned execution quantity conflicts: " + saved.Name);
		saved.Processed += execution.Quantity;
		if (saved.Role == "Entry")
		{
			live.Entered += execution.Quantity; live.EntrySum += execution.Price * execution.Quantity;
			positionEntryPrice = live.EntrySum / live.Entered;
		}
		else live.Exited += execution.Quantity;
		if (live.Exited > live.Entered) throw new InvalidOperationException("Owned exit exceeds opening fills; no corrective order allowed");
		live.Executions.Add(execution.ExecutionId);
		inPosition = live.Entered > live.Exited;
	}
	private bool PollLive()
	{
		if (!LiveExecution || live == null || livePolling) return liveReady;
		livePolling = true;
		try
		{
			if (liveFault != null) { LiveWait(liveFault); return false; }
			if (Account.Connection.Status != ConnectionStatus.Connected) { LiveWait("connection not synchronized"); return false; }
			Order[] orders; Execution[] executions; Position[] positions;
			lock (Account.Orders) orders = Account.Orders.ToArray();
			lock (Account.Executions) executions = Account.Executions.ToArray();
			lock (Account.Positions) positions = Account.Positions.ToArray();
			if (live.Orders.Count == 0 && orders.Any(o => o.Instrument != null && o.Instrument.FullName == Instrument.FullName &&
				(o.Name == "OD_SL" || o.Name == "OD_Long" || o.Name == "OD_Short") && !LiveTerminal(o.OrderState.ToString())))
			{ LiveWait("legacy OpenDrive order has no durable ownership; existing protection untouched"); return false; }
			foreach (LiveOrder saved in live.Orders)
			{
				Order[] matches = orders.Where(o => o.Instrument != null && o.Instrument.FullName == Instrument.FullName && o.Name == saved.Name && o.OrderId == saved.Id).ToArray();
				if (matches.Length == 0 && LiveTerminal(saved.State) && saved.Reported == saved.Processed) continue;
				if (matches.Length != 1 || !BindLiveOrder(saved, matches[0], false)) { LiveWait("exact owned order missing/conflicting: " + saved.Name); return false; }
			}
			foreach (Execution execution in executions.OrderBy(e => e.Time)) ProcessLiveExecution(execution);
			SaveLive(); // execution and broker-ID evidence commits before any subsequent request
			if (live.Orders.Any(o => o.State == "Unknown" || o.State == "Initialized" || o.State == "CancelPending" || o.State == "CancelSubmitted" || o.Reported != o.Processed))
			{ LiveWait("owned order acknowledgements/fills"); return false; }
			if (!string.IsNullOrEmpty(live.Restriction)) { LiveWait(live.Restriction); return false; }
			int quantity = LiveQuantity;
			if (quantity > 0)
			{
				long net = positions.Where(p => p.Instrument.FullName == Instrument.FullName).Sum(p => (long)p.Quantity * (p.MarketPosition == MarketPosition.Long ? 1 : -1));
				if (net * live.Side < quantity) { LiveWait("owned/account position disagreement; protection retained"); return false; }
				if (live.Risk <= 0 || positionStopPrice <= 0) { LiveWait("original risk/protection unavailable"); return false; }
				LiveOrder stop = live.Orders.LastOrDefault(o => o.Role == "Stop" && !LiveTerminal(o.State));
				if (stop != null)
				{
					Order broker = liveOrders[stop.Name];
					if (broker.Quantity - broker.Filled != quantity) { LiveWait("owned protective quantity mismatch"); return false; }
					positionStopPrice = live.Side > 0 ? Math.Max(positionStopPrice, broker.StopPrice) : Math.Min(positionStopPrice, broker.StopPrice);
					odSLOrder = broker;
				}
			}
			else if (live.Orders.All(o => LiveTerminal(o.State) && o.Reported == o.Processed))
			{
				inPosition = false; ProductExposure.Release(live.Owner);
			}
			liveReady = true;
			return true;
		}
		catch (Exception ex) { liveFault = ex.Message; LiveWait(ex.Message); return false; }
		finally { livePolling = false; }
	}
	private LiveOrder NewLiveIntent(string role, int side, int quantity, OrderType type, double stop, double limit, string fixedName = null)
	{
		var saved = new LiveOrder { Name = fixedName ?? live.Owner + "_" + role + "_" + (++live.Sequence), Role = role,
			Action = side > 0 ? "Buy" : "Sell", Type = type.ToString(), Quantity = quantity, Stop = stop, Limit = limit, State = "Initialized" };
		live.Orders.Add(saved); SaveLive(); return saved;
	}
	private bool PrepareLiveEntry(int side, int quantity, double entry, double stop, DateTime time, OrderType type, double limit, bool countAttempt = true, double initialRisk = 0)
	{
		if (!LiveExecution) return true;
		if (!PollLive() || LiveQuantity != 0 || live.Orders.Any(o => !LiveTerminal(o.State))) return false;
		string reason;
		if (!ProductExposure.Reserve(live.Owner, side, Account, Instrument, BlockOpposingExposure, out reason)) { statusMessage = reason; return false; }
		// Use a fresh trade namespace after settled fills; old orders remain in the
		// receipt so delayed callbacks cannot be mistaken for the next day's trade.
		if (live.Orders.Count > 0)
		{
			ProductExposure.Release(live.Owner);
			live.Owner = "OD_" + Guid.NewGuid().ToString("N");
			if (!ProductExposure.Reserve(live.Owner, side, Account, Instrument, BlockOpposingExposure, out reason)) { statusMessage = reason; return false; }
		}
		live.Side = side; live.Entered = live.Exited = 0; live.EntrySum = 0;
		live.CloseReason = null;
		positionEntryPrice = entry; positionStopPrice = stop; positionInitialRisk = initialRisk > 0 ? initialRisk : StopATR * currentAtr;
		positionExtreme = entry; positionEntryTime = time; trailActivated = costCoveredLocked = false;
		if (countAttempt) { if (side > 0) longTradesToday++; else shortTradesToday++; }
		NewLiveIntent("Entry", side, quantity, type, 0, limit, EntrySignal(side));
		return true;
	}
	private void SubmitStop(int side, int quantity, double stop)
	{
		if (!LiveExecution)
		{
			if (side > 0) ExitLongStopMarket(calcSeries, true, quantity, stop, "OD_SL", "OD_Long"); else ExitShortStopMarket(calcSeries, true, quantity, stop, "OD_SL", "OD_Short");
			return;
		}
		stop = Instrument.MasterInstrument.RoundToTickSize(stop);
		// Managed exits submitted before the opening fill can be silently ignored.
		// Create the durable protective intent only after exact entry executions settle.
		if (!PollLive() || LiveQuantity <= 0) return;
		if (!string.IsNullOrEmpty(live.CloseReason) || live.Orders.Any(o => o.Role == "Close" && !LiveTerminal(o.State))) return;
		if (!string.IsNullOrEmpty(live.Restriction) || liveFault != null) return;
		if (LiveQuantity > 0)
		{
			double quote = side > 0 ? GetCurrentBid() : GetCurrentAsk();
			if (quote <= 0) { LiveWait("fresh executable quote"); return; }
			if ((side > 0 && stop >= quote) || (side < 0 && stop <= quote)) { SubmitFlat(side, "Stop collision"); return; }
		}
		LiveOrder saved = live.Orders.LastOrDefault(o => o.Role == "Stop" && !LiveTerminal(o.State));
		if (saved != null && (saved.State == "CancelPending" || saved.State == "CancelSubmitted" || saved.State == "Unknown")) return;
		if (saved == null) saved = NewLiveIntent("Stop", -side, quantity, OrderType.StopMarket, stop, 0);
		else { saved.Stop = stop; saved.Quantity = quantity; SaveLive(); }
		if (!accountTransport)
		{
			if (side > 0) ExitLongStopMarket(calcSeries, true, quantity, stop, saved.Name, EntrySignal(side)); else ExitShortStopMarket(calcSeries, true, quantity, stop, saved.Name, EntrySignal(side));
		}
		else
		{
			Order broker;
			if (liveOrders.TryGetValue(saved.Name, out broker))
			{
				broker.StopPriceChanged = stop; broker.QuantityChanged = quantity; Account.Change(new[] { broker });
			}
			else SubmitAccountIntent(saved);
		}
	}
	private void SubmitAccountIntent(LiveOrder saved)
	{
		OrderAction action = saved.Role == "Entry" ? (saved.Action == "Buy" ? OrderAction.Buy : OrderAction.SellShort) : saved.Action == "Buy" ? OrderAction.BuyToCover : OrderAction.Sell;
		Order order = Account.CreateOrder(Instrument, action,
			(OrderType)Enum.Parse(typeof(OrderType), saved.Type), OrderEntry.Automated, TimeInForce.Gtc, saved.Quantity, saved.Limit, saved.Stop, "", saved.Name, Core.Globals.MaxDate, null);
		liveOrders[saved.Name] = order; saved.Id = order.OrderId; SaveLive();
		Account.Submit(new[] { order });
	}
	private void SubmitFlat(int side, string reason)
	{
		if (!LiveExecution) { if (side > 0) ExitLong(calcSeries, reason, "OD_Long"); else ExitShort(calcSeries, reason, "OD_Short"); return; }
		if (!PollLive() || LiveQuantity <= 0 || live.Orders.Any(o => o.Role == "Close" && !LiveTerminal(o.State))) return;
		live.CloseReason = reason; SaveLive();
		// Keep the stop until native/account close acknowledgement. Recovered closes
		// wait for its confirmed cancellation to prevent a late stop reversing flat.
		if (accountTransport && odSLOrder != null && !LiveTerminal(odSLOrder.OrderState.ToString()))
		{
			LiveOrder stop = live.Orders.Last(o => o.Name == odSLOrder.Name); stop.State = "CancelSubmitted"; SaveLive();
			Account.Cancel(new[] { odSLOrder }); LiveWait("protective cancellation before owned close"); return;
		}
		LiveOrder saved = NewLiveIntent("Close", -side, LiveQuantity, OrderType.Market, 0, 0);
		if (accountTransport) SubmitAccountIntent(saved);
		else if (side > 0) ExitLong(calcSeries, saved.Name, EntrySignal(side)); else ExitShort(calcSeries, saved.Name, EntrySignal(side));
	}
	private void LiveOrderEvent(Order order, ErrorCode error, string message)
	{
		if (!LiveExecution || live == null || order == null) return;
		LiveOrder saved = live.Orders.LastOrDefault(o => o.Name == order.Name);
		if (saved == null) return;
		if (!liveOrders.ContainsKey(saved.Name)) liveOrders[saved.Name] = order;
		if (!BindLiveOrder(saved, order, true)) { LiveWait("owned order identity conflict: " + saved.Name); return; }
		string denial = (message ?? "").ToLowerInvariant();
		if (denial.Contains("liquidation") || denial.Contains("permission") || denial.Contains("trading disabled") || denial.Contains("not authorized"))
		{
			live.Restriction = "Broker account restriction: " + message;
			SaveLive(); // durable before fault; no repair/close retry against denied account
			liveFault = live.Restriction; LiveWait(liveFault); return;
		}
		SaveLive();
		if (order.OrderState == OrderState.Rejected || error != ErrorCode.NoError)
		{
			live.Restriction = "Broker rejected owned " + saved.Role + ": " + message;
			SaveLive(); liveFault = live.Restriction; LiveWait(liveFault);
		}
	}
	private void LiveMaintenance()
	{
		if (!PollLive()) return;
		ResumePendingLimit(DateTime.UtcNow);
		if (!liveReady || LiveQuantity <= 0) return;
		if (!string.IsNullOrEmpty(live.CloseReason)) { SubmitFlat(live.Side, live.CloseReason); return; }
		if (!live.Orders.Any(o => o.Role == "Stop" && !LiveTerminal(o.State))) SubmitStop(live.Side, LiveQuantity, positionStopPrice);
	}
	private double EntryRiskScale(double conviction)
	{
		if (RiskMode != OpenDriveRiskMode.DynamicVolatility || conviction >= 1.5) return 1.0;
		return conviction >= 0.75 ? 0.5 : 0.33;
	}
	private double EntryRiskBudget(double scale)
	{
		if (SizingType == OpenDriveSizingType.FixedDollar) return RiskMoney * scale;
		if (SizingType != OpenDriveSizingType.PercentRisk) return 0;
		double capital = 0;
		if (Account != null)
		{
			try { capital = Account.Get(AccountItem.CashValue, Currency.UsDollar); }
			catch { }
		}
		if (capital <= 0)
		{
			double profit = SystemPerformance.AllTrades.Count > 0 ? SystemPerformance.AllTrades.TradesPerformance.NetProfit : 0;
			capital = Math.Max(1000.0, AccountCapital + profit);
		}
		return capital * (RiskPercent * scale / 100.0);
	}
	private void ResumePendingLimit(DateTime utcNow)
	{
		if (!resumePendingLimit || !LiveExecution || live == null || !PollLive()) return;
		LiveOrder entry = live.Orders.LastOrDefault(o => o.Role == "Entry");
		if (entry == null || entry.Type != "Limit" || entry.State == "Rejected" || entry.State == "Filled" ||
			live.Entered != 0 || live.Exited != 0 || entry.Processed != 0 || entry.Reported != 0)
		{ resumePendingLimit = false; return; }
		DateTime nowNY = TimeZoneInfo.ConvertTimeFromUtc(DateTime.SpecifyKind(utcNow, DateTimeKind.Utc), NewYorkTimeZone);
		if (live.EntryTime.Date != nowNY.Date || nowNY < live.EntryTime ||
			(FlatAtExit && nowNY.TimeOfDay >= new TimeSpan(ExitHourNY, ExitMinNY, 0)))
		{ resumePendingLimit = false; statusMessage = "Pending limit signal expired"; return; }
		if (!EnableTrading || !UseLimitRiskEntry || SizingType == OpenDriveSizingType.FixedContracts ||
			(live.Side > 0 ? !AllowLong : !AllowShort))
		{ statusMessage = "Pending limit replacement disabled by inputs"; return; }
		NewsGuard(utcNow);
		if (newsBlocked) return;
		// Reprice the original signal, not the latest bar after re-enabling.
		DateTime signalTime = TimeZoneInfo.ConvertTime(DateTime.SpecifyKind(live.EntryTime, DateTimeKind.Unspecified), NewYorkTimeZone, platformZone);
		int signalIndex = BarsArray[calcSeries].GetBar(signalTime);
		if (signalIndex < 0 || signalIndex > CurrentBars[calcSeries] || CurrentBars[calcSeries] - signalIndex >= 256 ||
			ToNewYork(Times[calcSeries].GetValueAt(signalIndex)) != live.EntryTime)
		{ statusMessage = "Pending limit waiting for original signal history"; return; }
		double close = Closes[calcSeries].GetValueAt(signalIndex);
		double atr = atrIndicator.GetValueAt(signalIndex);
		double ema = emaIndicator.GetValueAt(signalIndex);
		double pointValue = Instrument.MasterInstrument.PointValue;
		if (atr <= 0 || pointValue <= 0 || live.Risk <= 0 || live.Stop <= 0 || Math.Abs(live.Side) != 1) return;
		double scale = EntryRiskScale(Math.Abs(close - ema) / atr);
		double budget = EntryRiskBudget(scale);
		double cost = live.Risk * pointValue + CommissionPerContract;
		if (budget <= 0 || double.IsNaN(budget) || double.IsInfinity(budget) || cost <= 0 || budget / cost > int.MaxValue) return;
		int quantity = (int)Math.Floor(budget / cost);
		if (quantity < 1 && !AllowMinOneContract)
		{ statusMessage = "Pending limit budget below minimum contract"; return; }
		// Preserve a limit order even when the increased budget can cover the original entry.
		double limit = quantity < 1 ? live.Stop + live.Side * budget / pointValue : close;
		quantity = Math.Max(1, quantity);
		limit = Instrument.MasterInstrument.RoundToTickSize(limit);
		double quote = live.Side > 0 ? GetCurrentAsk() : GetCurrentBid();
		if (quote <= 0) { statusMessage = "Pending limit waiting for fresh quote"; return; }
		if (limit <= 0 || (live.Side > 0 ? limit >= quote : limit <= quote))
		{ statusMessage = "Pending limit replacement would be marketable; waiting"; return; }
		if (!LiveTerminal(entry.State))
		{
			Order broker;
			if (!liveOrders.TryGetValue(entry.Name, out broker)) return;
			if (broker.LimitPrice == limit && broker.Quantity == quantity)
			{ resumePendingLimit = false; statusMessage = "Owned pending limit unchanged"; return; }
			entry.State = "CancelSubmitted"; SaveLive();
			Account.Cancel(new[] { broker });
			LiveWait("pending entry cancellation before risk replacement");
			return;
		}
		// PollLive reconciles exact executions and all terminal acknowledgements first.
		double stop = live.Stop, originalRisk = live.Risk;
		int side = live.Side;
		DateTime time = live.EntryTime;
		if (!PrepareLiveEntry(side, quantity, limit, stop, time, OrderType.Limit, limit, false, originalRisk)) return;
		resumePendingLimit = false;
		SubmitEntry(side, quantity, limit);
		SubmitStop(side, quantity, stop);
		statusMessage = $"Pending {(side > 0 ? "LONG" : "SHORT")} LIMIT replaced: {quantity}c @ {limit:F2} | SL={stop:F2} | Budget=${budget:F0}";
		SaveLive();
		UpdateDashboard(nowNY);
	}
	private void SubmitEntry(int side, int quantity, double limit)
	{
		if (LiveExecution && accountTransport) { SubmitAccountIntent(live.Orders.Last(o => o.Role == "Entry")); return; }
		if (limit > 0)
		{
			if (side > 0) EnterLongLimit(calcSeries, true, quantity, limit, EntrySignal(side)); else EnterShortLimit(calcSeries, true, quantity, limit, EntrySignal(side));
		}
		else if (side > 0) EnterLong(calcSeries, quantity, EntrySignal(side)); else EnterShort(calcSeries, quantity, EntrySignal(side));
	}
	private void OnLiveAccountOrder(object sender, OrderEventArgs e)
	{
		if (!accountTransport || e.Order == null) return;
		try { TriggerCustomEvent(_ => RunLiveCallback(() => { LiveOrderEvent(e.Order, e.Error, e.Comment); PollLive(); }), null); } catch (InvalidOperationException) { }
	}
	private void OnLiveAccountExecution(object sender, ExecutionEventArgs e)
	{
		if (!accountTransport) return;
		try { TriggerCustomEvent(_ => RunLiveCallback(() => { ProcessLiveExecution(e.Execution); SaveLive(); LiveMaintenance(); }), null); } catch (InvalidOperationException) { }
	}
	private void RunLiveCallback(Action callback)
	{
		if (!LiveExecution) return;
		try { callback(); }
		catch (Exception ex) { liveFault = "Owned recovery callback refused: " + ex.Message; LiveWait(liveFault); }
	}
	protected override void OnExecutionUpdate(Execution execution, string executionId, double price, int quantity, MarketPosition marketPosition, string orderId, DateTime time)
	{
		if (LiveExecution && !accountTransport) RunLiveCallback(() => { ProcessLiveExecution(execution); SaveLive(); LiveMaintenance(); });
	}
	internal sealed class ModelDashState
	{
		internal string Clock;

		internal string Status;

		internal string RangeHigh;

		internal string RangeLow;

		internal string RangeWidth;

		internal string Position;

		internal string Stop;

		internal string Risk;

		internal string History;

		internal string News;

		internal string Costs;

		internal string Title;

		internal string RangeCaption;

		internal string HighCaption;

		internal string LowCaption;

		internal bool InTrade;

		internal bool NewsBlocked;
	}

	internal sealed class ModelDashboard
	{
		private readonly object sync = new object();

		private ModelDashState state;

		private bool collapsed;

		private bool dragging;

		private double offsetX;

		private double offsetY;

		private double dragX;

		private double dragY;

		private Rect shellRect;

		private Rect headerRect;

		private Rect toggleRect;

		private const float Width = 258f;

		private const float FullHeight = 267f;

		private const float HeaderHeight = 64f;

		internal void Publish(ModelDashState next)
		{
			lock (sync)
			{
				state = next;
			}
		}

		internal bool MouseDown(double x, double y)
		{
			lock (sync)
			{
				if (state == null)
				{
					return false;
				}
				if (toggleRect.Contains(x, y))
				{
					collapsed = !collapsed;
					return true;
				}
				if (!headerRect.Contains(x, y))
				{
					return false;
				}
				dragging = true;
				dragX = x - shellRect.X;
				dragY = y - shellRect.Y;
				return true;
			}
		}

		internal bool MouseMove(double x, double y)
		{
			lock (sync)
			{
				if (!dragging)
				{
					return false;
				}
				double num = x - dragX - shellRect.X;
				double num2 = y - dragY - shellRect.Y;
				offsetX += num;
				offsetY += num2;
				shellRect.Offset(num, num2);
				headerRect.Offset(num, num2);
				toggleRect.Offset(num, num2);
				return true;
			}
		}

		internal bool MouseUp()
		{
			lock (sync)
			{
				bool result = dragging;
				dragging = false;
				return result;
			}
		}

		internal void Render(RenderTarget rt, ChartControl chart)
		{
			ModelDashState modelDashState;
			bool flag;
			double num;
			double num2;
			lock (sync)
			{
				modelDashState = state;
				flag = collapsed;
				num = offsetX;
				num2 = offsetY;
			}
			if (modelDashState == null || rt == null || chart == null)
			{
				return;
			}
			float num3 = (float)((double)((float)chart.CanvasRight - 258f - 12f) + num);
			float num4 = (float)(42.0 + num2);
			float num5 = (flag ? 64f : 267f);
			float num6 = num3 + 258f - 16f;
			RoundedRectangle roundedRect = new RoundedRectangle
			{
				Rect = new RectangleF(num3, num4, 258f, num5),
				RadiusX = 9.75f,
				RadiusY = 9.75f
			};
			using (SharpDX.Direct2D1.SolidColorBrush brush = new SharpDX.Direct2D1.SolidColorBrush(rt, new Color4(12f / 255f, 1f / 15f, 27f / 255f, 1f)))
			{
				using SharpDX.Direct2D1.SolidColorBrush brush2 = new SharpDX.Direct2D1.SolidColorBrush(rt, new Color4(182f / 255f, 205f / 255f, 235f / 255f, 110f / 255f));
				using SharpDX.Direct2D1.SolidColorBrush solidColorBrush = new SharpDX.Direct2D1.SolidColorBrush(rt, new Color4(14f / 15f, 244f / 255f, 250f / 255f, 1f));
				using SharpDX.Direct2D1.SolidColorBrush brush3 = new SharpDX.Direct2D1.SolidColorBrush(rt, new Color4(165f / 255f, 181f / 255f, 0.8f, 1f));
				using SharpDX.Direct2D1.SolidColorBrush brush4 = new SharpDX.Direct2D1.SolidColorBrush(rt, new Color4(115f / 255f, 171f / 255f, 1f, 1f));
				using SharpDX.Direct2D1.SolidColorBrush solidColorBrush2 = new SharpDX.Direct2D1.SolidColorBrush(rt, new Color4(91f / 255f, 215f / 255f, 164f / 255f, 1f));
				using SharpDX.Direct2D1.SolidColorBrush solidColorBrush3 = new SharpDX.Direct2D1.SolidColorBrush(rt, new Color4(1f, 125f / 255f, 128f / 255f, 1f));
				using SharpDX.DirectWrite.Factory dw = new SharpDX.DirectWrite.Factory();
				rt.FillRoundedRectangle(roundedRect, brush);
				rt.DrawRoundedRectangle(roundedRect, brush2, 1f);
				rt.FillRectangle(new RectangleF(num3 + 12f, num4 + 14f, 2f, 39f), brush4);
				Text(rt, dw, modelDashState.Title, 13f, solidColorBrush, num3 + 24f, num4 + 13f, 198f, bold: true);
				Text(rt, dw, modelDashState.Clock, 9f, brush3, num3 + 24f, num4 + 34f, 210f);
				RoundedRectangle roundedRect2 = new RoundedRectangle
				{
					Rect = new RectangleF(num6 - 12f, num4 + 13f, 19f, 19f),
					RadiusX = 6f,
					RadiusY = 6f
				};
				rt.FillRoundedRectangle(roundedRect2, brush2);
				Text(rt, dw, flag ? "+" : "-", 13f, solidColorBrush, num6 - 12f, num4 + 14f, 19f, bold: false, right: false, center: true);
				if (!flag)
				{
					Rule(rt, brush2, num3 + 20f, num4 + 61f, 222f);
					Text(rt, dw, modelDashState.Status, 11.5f, modelDashState.NewsBlocked ? solidColorBrush3 : solidColorBrush, num3 + 20f, num4 + 69f, 222f);
					Text(rt, dw, modelDashState.RangeCaption, 9f, brush3, num3 + 20f, num4 + 95f, 184f);
					Text(rt, dw, modelDashState.RangeWidth, 13f, solidColorBrush, num6 - 55f, num4 + 92f, 55f, bold: true, right: true);
					Text(rt, dw, modelDashState.HighCaption, 9f, solidColorBrush2, num3 + 20f, num4 + 122f, 30f);
					Text(rt, dw, modelDashState.RangeHigh, 13f, solidColorBrush, num3 + 57f, num4 + 119f, 65f, bold: true, right: true);
					Text(rt, dw, modelDashState.LowCaption, 9f, solidColorBrush3, num3 + 140f, num4 + 122f, 30f);
					Text(rt, dw, modelDashState.RangeLow, 13f, solidColorBrush, num3 + 177f, num4 + 119f, 65f, bold: true, right: true);
					Rule(rt, brush2, num3 + 20f, num4 + 149f, 222f);
					Text(rt, dw, "POSITION", 9f, brush3, num3 + 20f, num4 + 159f, 106f);
					Text(rt, dw, "HARD STOP", 9f, brush3, num3 + 139f, num4 + 159f, num6 - num3 - 139f, bold: false, right: true);
					Text(rt, dw, modelDashState.Position, 13f, modelDashState.InTrade ? solidColorBrush2 : solidColorBrush, num3 + 20f, num4 + 174f, 106f, bold: true);
					Text(rt, dw, modelDashState.Stop, 13f, solidColorBrush3, num3 + 139f, num4 + 174f, num6 - num3 - 139f, bold: true, right: true);
					Rule(rt, brush2, num3 + 20f, num4 + 199f, 222f);
					Text(rt, dw, modelDashState.Risk, 11.5f, solidColorBrush, num3 + 20f, num4 + 210f, 222f);
					Text(rt, dw, modelDashState.Costs, 9.5f, brush3, num3 + 20f, num4 + 229f, 222f);
					Text(rt, dw, modelDashState.History, 8.5f, brush3, num3 + 20f, num4 + 248f, 222f);
				}
			}
			lock (sync)
			{
				shellRect = new Rect(num3, num4, 258.0, num5);
				headerRect = new Rect(num3, num4, 258.0, 64.0);
				toggleRect = new Rect(num6 - 15f, num4 + 10f, 25.0, 25.0);
			}
		}

		private static void Text(RenderTarget rt, SharpDX.DirectWrite.Factory dw, string value, float size, SharpDX.Direct2D1.SolidColorBrush brush, float x, float y, float width, bool bold = false, bool right = false, bool center = false)
		{
			if (string.IsNullOrEmpty(value))
			{
				return;
			}
			using TextFormat textFormat = new TextFormat(dw, "Segoe UI", bold ? SharpDX.DirectWrite.FontWeight.DemiBold : SharpDX.DirectWrite.FontWeight.Normal, SharpDX.DirectWrite.FontStyle.Normal, size);
			textFormat.TextAlignment = (right ? SharpDX.DirectWrite.TextAlignment.Trailing : (center ? SharpDX.DirectWrite.TextAlignment.Center : SharpDX.DirectWrite.TextAlignment.Leading));
			textFormat.WordWrapping = WordWrapping.NoWrap;
			rt.DrawText(value, textFormat, new RectangleF(x, y, width, size + 7f), brush, DrawTextOptions.Clip);
		}

		private static void Rule(RenderTarget rt, SharpDX.Direct2D1.SolidColorBrush brush, float x, float y, float width)
		{
			rt.DrawLine(new Vector2(x, y), new Vector2(x + width, y), brush, 0.5f);
		}
	}

	private sealed class NewsEvent
	{
		public DateTime Utc;

		public string Impact;

		public string Title;
	}

	private static readonly TimeZoneInfo NewYorkTimeZone = TimeZoneInfo.FindSystemTimeZoneById("Eastern Standard Time");

	private TimeZoneInfo platformZone;

	private double currentAtr;

	private double currentEma;

	private EMA emaIndicator;

	private ATR atrIndicator;

	private int calcSeries = 0;

	private bool inPosition;

	private int positionDir;

	private double positionEntryPrice;

	private double positionStopPrice;

	private double positionExtreme;

	private double positionInitialRisk;

	private bool trailActivated;

	private DateTime positionEntryTime;

	private DateTime lastEvaluatedDay;

	private int longTradesToday;

	private int shortTradesToday;

	private double lastConvictionDist = -1.0;

	private double lastAppliedRiskBudget = 0.0;

	private string statusMessage = "Waiting for 09:30 NY open";

	private ModelDashboard dashboard;

	private ChartControl dashboardChart;

	private bool dashboardMouseHooked;

	private bool dashboardLayered;

	private int dashboardRedrawQueued;

	private static readonly HttpClient newsHttp = CreateNewsHttp();

	private readonly object newsLock = new object();

	private NewsEvent[] newsEvents = new NewsEvent[0];

	private DateTime newsFetchedUtc = DateTime.MinValue;

	private DateTime newsAttemptUtc = DateTime.MinValue;

	private DateTime newsWeekNy;

	private bool newsFetching;

	private bool newsBlocked;

	private bool costCoveredLocked;

	private string activeNewsTitle = "";

	private DateTime upcomingNewsUtc = DateTime.MinValue;

	private string upcomingNewsTitle = "";

	private Order  odSLOrder;

	private bool   slRejected;

	private bool   recoveredPosition;

	[NinjaScriptProperty]
	[Display(Name = "Enable New Trades", Description = "Enable new entry signals (open trades stay protected when off)", GroupName = "01 Trading", Order = 0)]
	public bool EnableTrading { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "Block opposing index exposure", Description = "Optional wider index guard. Exact account/contract opposite entries are always blocked.", GroupName = "01 Trading", Order = 3)]
	public bool BlockOpposingExposure { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "Allow Long Entries", GroupName = "01 Trading", Order = 1)]
	public bool AllowLong { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "Allow Short Entries", GroupName = "01 Trading", Order = 2)]
	public bool AllowShort { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "Risk Mode", Description = "Dynamic Volatility for Prop Firms (0.33/0.50/1.00), Static Fixed for Live Accounts", GroupName = "02 Risk & Sizing", Order = 0)]
	public OpenDriveRiskMode RiskMode { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "Sizing Method", Description = "Choose Percent Risk, Fixed Dollar Budget, or Fixed Contracts independently", GroupName = "02 Risk & Sizing", Order = 1)]
	public OpenDriveSizingType SizingType { get; set; }

	[NinjaScriptProperty]
	[Range(0.05, 10.0)]
	[Display(Name = "Risk Percent (%)", Description = "Percentage of account equity/balance to risk per trade (e.g. 1.0%)", GroupName = "02 Risk & Sizing", Order = 2)]
	public double RiskPercent { get; set; }

	[NinjaScriptProperty]
	[Range(10.0, 1000000.0)]
	[Display(Name = "Risk Dollar Budget ($)", Description = "Cash risk budget per trade when Fixed Dollar mode is active", GroupName = "02 Risk & Sizing", Order = 3)]
	public double RiskMoney { get; set; }

	[NinjaScriptProperty]
	[Range(1, 500)]
	[Display(Name = "Fixed Contracts", Description = "Fixed contract quantity when Fixed Contracts mode is active", GroupName = "02 Risk & Sizing", Order = 4)]
	public int FixedContracts { get; set; }

	[NinjaScriptProperty]
	[Range(1000.0, 10000000.0)]
	[Display(Name = "Initial Account Capital ($)", Description = "Used for percentage compounding calculations in Strategy Analyzer backtests", GroupName = "02 Risk & Sizing", Order = 5)]
	public double AccountCapital { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "Allow Minimum 1 Contract", Description = "Allows 1 contract on NQ if calculated size is 0 due to smaller budget", GroupName = "02 Risk & Sizing", Order = 6)]
	public bool AllowMinOneContract { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "Limit Entry on Budget Overrun", Description = "When budget can't cover 1 contract at market, place a limit order at the price where SL cost = your budget. Only for PercentRisk and FixedDollar modes.", GroupName = "02 Risk & Sizing", Order = 7)]
	public bool UseLimitRiskEntry { get; set; }

	[NinjaScriptProperty]
	[Range(2, 200)]
	[Display(Name = "Signal EMA Period", Description = "Benchmark EMA on 5-minute bars (Close)", GroupName = "03 Signal Core", Order = 0)]
	public int EmaPeriod { get; set; }

	[NinjaScriptProperty]
	[Range(0, 23)]
	[Display(Name = "Entry Hour (New York)", GroupName = "03 Signal Core", Order = 1)]
	public int EntryHourNY { get; set; }

	[NinjaScriptProperty]
	[Range(0, 59)]
	[Display(Name = "Entry Minute (New York)", GroupName = "03 Signal Core", Order = 2)]
	public int EntryMinNY { get; set; }

	[NinjaScriptProperty]
	[Range(2, 100)]
	[Display(Name = "ATR Period", Description = "Wilder RMA ATR period on 5-minute bars", GroupName = "04 Stops & Trailing", Order = 0)]
	public int AtrPeriod { get; set; }

	[NinjaScriptProperty]
	[Range(0.5, 20.0)]
	[Display(Name = "Hard Stop Distance (x ATR)", Description = "Initial hard stop placed from entry fill (default 4.0)", GroupName = "04 Stops & Trailing", Order = 1)]
	public double StopATR { get; set; }

	[NinjaScriptProperty]
	[Range(0.0, 10.0)]
	[Display(Name = "Trail Activation (x ATR)", Description = "Profit required on closed bar before trailing activates (default 0.25)", GroupName = "04 Stops & Trailing", Order = 2)]
	public double ActivateATR { get; set; }

	[NinjaScriptProperty]
	[Range(0.5, 20.0)]
	[Display(Name = "Chandelier Trail (x ATR)", Description = "Trailing distance behind session extreme (default 3.0)", GroupName = "04 Stops & Trailing", Order = 3)]
	public double TrailATR { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "Close Flat at Session Close", Description = "Liquidate position before session end (16:00 NY, no overnight hold)", GroupName = "04 Stops & Trailing", Order = 4)]
	public bool FlatAtExit { get; set; }

	[NinjaScriptProperty]
	[Range(0, 23)]
	[Display(Name = "Exit Hour (New York)", GroupName = "04 Stops & Trailing", Order = 5)]
	public int ExitHourNY { get; set; }

	[NinjaScriptProperty]
	[Range(0, 59)]
	[Display(Name = "Exit Minute (New York)", GroupName = "04 Stops & Trailing", Order = 6)]
	public int ExitMinNY { get; set; }

	[NinjaScriptProperty]
	[Range(0.0, 50.0)]
	[Display(Name = "Round-Trip Commission ($/contract)", GroupName = "05 Costs & Execution", Order = 0)]
	public double CommissionPerContract { get; set; }

	[NinjaScriptProperty]
	[Range(0, 100)]
	[Display(Name = "Slippage Allowance (Points)", GroupName = "05 Costs & Execution", Order = 1)]
	public int SlippagePoints { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "Show Floating HUD Dashboard", GroupName = "06 Display & Visuals", Order = 0)]
	public bool ShowVisuals { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "Show Chart Annotations & Lines", GroupName = "06 Display & Visuals", Order = 1)]
	public bool ShowExtras { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "News Impact Filter (USD)", GroupName = "07 News Guard", Order = 0)]
	public OpenDriveNewsImpact NewsImpact { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "Blackout Window", GroupName = "07 News Guard", Order = 1)]
	public OpenDriveNewsWindow NewsWindow { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "Move Stop to Cost-Covered BE", Description = "Move stop loss to cost-covered BE if in profit before news release", GroupName = "07 News Guard", Order = 2)]
	public bool NewsCostCoveredBE { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "Close Position Before News", Description = "Close position flat before news event (strict prop firm requirement)", GroupName = "07 News Guard", Order = 3)]
	public bool NewsFlattenBefore { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "Block Trade Modifications During Blackout", Description = "Prevent trailing stop modifications during news window (prop firm rule)", GroupName = "07 News Guard", Order = 4)]
	public bool NewsBlockModifications { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "Write Decision & Trade Logs", GroupName = "08 Logging", Order = 0)]
	public bool WriteTradeLog { get; set; }

	private bool IsPlayback => Connection.PlaybackConnection != null;

	private static string StrategyRoot([CallerFilePath] string source = "")
	{
		return Path.GetDirectoryName(source);
	}

	private DateTime ToNewYork(DateTime time)
	{
		if (platformZone == null)
		{
			platformZone = Globals.GeneralOptions.TimeZoneInfo;
		}
		return TimeZoneInfo.ConvertTime(DateTime.SpecifyKind(time, DateTimeKind.Unspecified), platformZone, NewYorkTimeZone);
	}

	private DateTime ToUtc(DateTime time)
	{
		if (platformZone == null)
		{
			platformZone = Globals.GeneralOptions.TimeZoneInfo;
		}
		return TimeZoneInfo.ConvertTimeToUtc(DateTime.SpecifyKind(time, DateTimeKind.Unspecified), platformZone);
	}

	private static HttpClient CreateNewsHttp()
	{
		HttpClient httpClient = new HttpClient();
		httpClient.DefaultRequestHeaders.Add("User-Agent", "Mozilla/5.0");
		httpClient.DefaultRequestHeaders.Add("Accept", "application/json");
		httpClient.Timeout = TimeSpan.FromSeconds(5.0);
		return httpClient;
	}

	protected override void OnStateChange()
	{
		if (State == State.SetDefaults)
		{
			Name = "OpenDriveNT8";
			Description = "OpenDriveNT8 - New York cash-open momentum strategy. Defaults to a 09:30 entry assessment with a 12-period EMA filter, ATR hard stop and Chandelier trailing stop. Configurable sizing, news guard and optional 16:00 New York flattening. Copyright 2026-2027, Osamwonyi Eric (@You_FoundEric). Developed by @You_FoundEric. Unauthorized redistribution prohibited.";
			Calculate = Calculate.OnBarClose;
			EntriesPerDirection = 1;
			EntryHandling = EntryHandling.AllEntries;
			IsExitOnSessionCloseStrategy = false;
			StartBehavior = StartBehavior.ImmediatelySubmit;
			MaximumBarsLookBack = MaximumBarsLookBack.TwoHundredFiftySix;
			OrderFillResolution = OrderFillResolution.Standard;
			Slippage = 1.0;
			ConnectionLossHandling = ConnectionLossHandling.KeepRunning;
			RealtimeErrorHandling = RealtimeErrorHandling.IgnoreAllErrors;
			BarsRequiredToTrade = 20;
			IsInstantiatedOnEachOptimizationIteration = false;
			EnableTrading = true;
			BlockOpposingExposure = true;
			AllowLong = true;
			AllowShort = true;
			RiskMode = OpenDriveRiskMode.DynamicVolatility;
			SizingType = OpenDriveSizingType.FixedContracts;
			RiskPercent = 1.0;
			RiskMoney = 5000.0;
			FixedContracts = 1;
			AccountCapital = 50000.0;
			AllowMinOneContract = true;
			UseLimitRiskEntry = false;
			EmaPeriod = 12;
			EntryHourNY = 9;
			EntryMinNY = 30;
			AtrPeriod = 14;
			StopATR = 4.0;
			ActivateATR = 0.25;
			TrailATR = 3.0;
			FlatAtExit = true;
			ExitHourNY = 16;
			ExitMinNY = 0;
			CommissionPerContract = 4.0;
			SlippagePoints = 1;
			ShowVisuals = true;
			ShowExtras = true;
			WriteTradeLog = true;
			NewsImpact = OpenDriveNewsImpact.Red;
			NewsWindow = OpenDriveNewsWindow.Ten;
			NewsCostCoveredBE = true;
			NewsFlattenBefore = false;
			NewsBlockModifications = true;
			AddPlot(new Stroke(Brushes.DodgerBlue, DashStyleHelper.Solid, 2f), PlotStyle.Line, "OpenDrive EMA");
		}
		else if (State == State.Configure)
		{
			dashboard = new ModelDashboard();
			if (BarsPeriod.BarsPeriodType != BarsPeriodType.Minute || BarsPeriod.Value != 5)
			{
				AddDataSeries(BarsPeriodType.Minute, 5);
				calcSeries = 1;
			}
			else
			{
				calcSeries = 0;
			}
		}
		else if (State == State.DataLoaded)
		{
			OpenLiveStore();
			platformZone = Globals.GeneralOptions.TimeZoneInfo;
			emaIndicator = EMA(BarsArray[calcSeries], EmaPeriod);
			atrIndicator = ATR(BarsArray[calcSeries], AtrPeriod);
			lastEvaluatedDay = DateTime.MinValue;
			costCoveredLocked = false;
			BeginNewsFetch();
			if (ShowVisuals)
			{
				AddChartIndicator(atrIndicator);
			}
		}
		else if (State == State.Realtime)
		{
			BeginNewsFetch();
			RecoverOpenPosition();
			Account.OrderUpdate += OnLiveAccountOrder;
			Account.ExecutionUpdate += OnLiveAccountExecution;
			liveTimer = new Timer(_ => { try { TriggerCustomEvent(o => RunLiveCallback(LiveMaintenance), null); } catch (InvalidOperationException) { } }, null, 1000, 1000);
		}
		else if (State == State.Terminated)
		{
			if (liveTimer != null) liveTimer.Dispose();
			if (Account != null) { Account.OrderUpdate -= OnLiveAccountOrder; Account.ExecutionUpdate -= OnLiveAccountExecution; }
			if (live != null && live.Entered == live.Exited && live.Orders.All(o => LiveTerminal(o.State) && o.Reported == o.Processed)) ProductExposure.Release(live.Owner);
			if (liveLease != null) liveLease.Dispose();
			HookDashboardMouse(attach: false);
		}
	}

	private double Up(double price)
	{
		return Instrument.MasterInstrument.RoundToTickSize(price + TickSize * 0.499);
	}

	private double Down(double price)
	{
		return Instrument.MasterInstrument.RoundToTickSize(price - TickSize * 0.499);
	}

	private double EffectiveCostDistance()
	{
		double num = ((Instrument != null && Instrument.MasterInstrument != null) ? Instrument.MasterInstrument.PointValue : 20.0);
		double num2 = CommissionPerContract + 2.0 * (double)SlippagePoints * TickSize * num;
		double val = ((num > 0.0) ? (num2 / num) : (2.0 * TickSize));
		return Math.Max(val, TickSize);
	}

	private void BeginNewsFetch()
	{
		if (NewsImpact == OpenDriveNewsImpact.Off || State != State.Realtime || IsPlayback)
		{
			return;
		}
		lock (newsLock)
		{
			bool flag = NewsSnapshotValid(DateTime.UtcNow);
			if (newsFetching || (DateTime.UtcNow - newsAttemptUtc).TotalMinutes < (double)(flag ? 30 : 5))
			{
				return;
			}
			newsFetching = true;
			newsAttemptUtc = DateTime.UtcNow;
		}
		Task.Run(() =>
		{
			try
			{
				string result = newsHttp.GetStringAsync("https://nfs.faireconomy.media/ff_calendar_thisweek.json").GetAwaiter().GetResult();
				NewsEvent[] array = ParseNews(result);
				DateTime dateTime = NewsWeek(DateTime.UtcNow);
				lock (newsLock)
				{
					newsEvents = array;
					newsFetchedUtc = DateTime.UtcNow;
					newsWeekNy = dateTime;
				}
			}
			catch (Exception ex)
			{
				if (WriteTradeLog)
				{
					Print("[OpenDrive] ForexFactory unavailable; entries blocked: " + ex.Message);
				}
			}
			finally
			{
				lock (newsLock)
				{
					newsFetching = false;
				}
			}
		});
	}

	private static NewsEvent[] ParseNews(string json)
	{
		List<NewsEvent> list = new List<NewsEvent>();
		List<Dictionary<string, object>> list2 = new JavaScriptSerializer().Deserialize<List<Dictionary<string, object>>>(json);
		if (list2 == null || list2.Count == 0)
		{
			throw new InvalidDataException("Empty ForexFactory calendar");
		}
		DateTime dateTime = NewsWeek(DateTime.UtcNow);
		foreach (Dictionary<string, object> item in list2)
		{
			string text = Convert.ToString(item["date"]);
			if (!text.EndsWith("Z", StringComparison.OrdinalIgnoreCase) && !Regex.IsMatch(text, "[+-]\\d\\d:\\d\\d$"))
			{
				throw new InvalidDataException("News timestamp lacks an offset");
			}
			DateTime utcDateTime = DateTimeOffset.Parse(text, CultureInfo.InvariantCulture).UtcDateTime;
			DateTime dateTime2 = TimeZoneInfo.ConvertTimeFromUtc(utcDateTime, NewYorkTimeZone);
			if (dateTime2.Date < dateTime || dateTime2.Date >= dateTime.AddDays(7.0))
			{
				throw new InvalidDataException("Wrong-week ForexFactory calendar");
			}
			if (Convert.ToString(item["country"]) == "USD")
			{
				list.Add(new NewsEvent
				{
					Utc = utcDateTime,
					Impact = Convert.ToString(item["impact"]),
					Title = Convert.ToString(item["title"])
				});
			}
		}
		return list.ToArray();
	}

	private static DateTime NewsWeek(DateTime utc)
	{
		DateTime dateTime = TimeZoneInfo.ConvertTimeFromUtc(utc, NewYorkTimeZone);
		return dateTime.Date.AddDays(0 - dateTime.DayOfWeek);
	}

	private bool NewsSnapshotValid(DateTime utc)
	{
		return newsFetchedUtc != DateTime.MinValue && utc >= newsFetchedUtc && utc - newsFetchedUtc < TimeSpan.FromHours(1.0) && newsWeekNy == NewsWeek(utc);
	}

	private bool NewsImpactAllowed(NewsEvent item)
	{
		string text = (item.Title ?? "").ToUpperInvariant();
		string text2 = (item.Impact ?? "").ToUpperInvariant();
		if (text.Contains("NEW HOME SALES") || text.Contains("EXISTING HOME SALES") || text.Contains("PENDING HOME SALES") || text.Contains("CRUDE OIL") || text.Contains("OIL STOCK") || (text.Contains("EIA") && text.Contains("STOCK")))
		{
			text2 = "MEDIUM";
		}
		return NewsImpact == OpenDriveNewsImpact.All || (text2 == "HIGH" && NewsImpact >= OpenDriveNewsImpact.Red) || (text2 == "MEDIUM" && NewsImpact == OpenDriveNewsImpact.RedYellow);
	}

	private void NewsGuard(DateTime utcNow)
	{
		if (IsPlayback)
		{
			newsBlocked = false;
			return;
		}
		if (NewsImpact == OpenDriveNewsImpact.Off || State != State.Realtime)
		{
			newsBlocked = false;
			return;
		}
		BeginNewsFetch();
		NewsEvent[] array;
		bool flag;
		lock (newsLock)
		{
			array = newsEvents;
			flag = NewsSnapshotValid(utcNow);
		}
		NewsEvent newsEvent = null;
		int num = (int)NewsWindow * 30;
		upcomingNewsUtc = DateTime.MinValue;
		upcomingNewsTitle = "";
		if (flag)
		{
			NewsEvent[] array2 = array;
			foreach (NewsEvent newsEvent2 in array2)
			{
				if (NewsImpactAllowed(newsEvent2))
				{
					if (utcNow >= newsEvent2.Utc.AddSeconds(-num) && utcNow <= newsEvent2.Utc.AddSeconds(num))
					{
						newsEvent = newsEvent2;
						break;
					}
					if (newsEvent2.Utc > utcNow && (upcomingNewsUtc == DateTime.MinValue || newsEvent2.Utc < upcomingNewsUtc))
					{
						upcomingNewsUtc = newsEvent2.Utc;
						upcomingNewsTitle = newsEvent2.Title;
					}
				}
			}
		}
		bool flag2 = !flag || newsEvent != null;
		ref string reference = ref activeNewsTitle;
		string text;
		if (newsEvent != null)
		{
			text = newsEvent.Title;
		}
		else
		{
			text = ((!flag) ? "Feed Syncing" : "");
		}
		reference = text;
		if (flag2 != newsBlocked && WriteTradeLog)
		{
			Print(string.Format("{0} [OpenDrive] NEWS {1}: {2}", utcNow, flag2 ? "BLACKOUT START" : "BLACKOUT END", activeNewsTitle));
		}
		newsBlocked = flag2;
		if (!inPosition || Position.MarketPosition == MarketPosition.Flat)
		{
			return;
		}
		if (NewsFlattenBefore && newsEvent != null && utcNow < newsEvent.Utc)
		{
			if (WriteTradeLog)
			{
				Print($"{utcNow} [OpenDrive] News Flatten triggered ahead of '{newsEvent.Title}'. Closing position.");
			}
			if (positionDir == 1)
			{
				SubmitFlat(1, "OD_NewsFlat");
			}
			else
			{
				SubmitFlat(-1, "OD_NewsFlat");
			}
			if (!LiveExecution) { inPosition = false; trailActivated = false; }
			statusMessage = LiveExecution ? "Owned news close pending acknowledgement" : "Closed flat before news";
		}
		else
		{
			if (!NewsCostCoveredBE)
			{
				return;
			}
			DateTime dateTime = newsEvent?.Utc ?? upcomingNewsUtc;
			string eventTitle = ((newsEvent != null) ? newsEvent.Title : upcomingNewsTitle);
			if (dateTime != DateTime.MinValue && dateTime > utcNow)
			{
				int num2 = (int)NewsWindow * 60;
				if (utcNow >= dateTime.AddSeconds(-num2))
				{
					ProtectAtCost(utcNow, eventTitle);
				}
			}
		}
	}

	private void ProtectAtCost(DateTime utcNow, string eventTitle)
	{
		if ((LiveExecution ? LiveQuantity == 0 || !PollLive() : Position.MarketPosition == MarketPosition.Flat) || !inPosition)
		{
			return;
		}
		double num = EffectiveCostDistance();
		double num2 = Closes[calcSeries][0];
		if (positionDir == 1)
		{
			double num3 = Up(positionEntryPrice + num);
			if (!(num3 <= positionStopPrice) && num2 > num3 + 2.0 * TickSize)
			{
				positionStopPrice = num3;
				SubmitStop(1, LiveQuantity, positionStopPrice);
				costCoveredLocked = true;
				if (WriteTradeLog)
				{
					Print($"{utcNow} [OpenDrive] [NEWS BE] Stop ratcheted to cost-covered BE at {positionStopPrice:F2} ahead of news '{eventTitle}'.");
				}
			}
			return;
		}
		double num4 = Down(positionEntryPrice - num);
		if ((!(positionStopPrice > 0.0) || !(num4 >= positionStopPrice)) && num2 < num4 - 2.0 * TickSize)
		{
			positionStopPrice = num4;
			SubmitStop(-1, LiveQuantity, positionStopPrice);
			costCoveredLocked = true;
			if (WriteTradeLog)
			{
				Print($"{utcNow} [OpenDrive] [NEWS BE] Stop ratcheted to cost-covered BE at {positionStopPrice:F2} ahead of news '{eventTitle}'.");
			}
		}
	}

	protected override void OnMarketData(MarketDataEventArgs marketDataUpdate)
	{
		if (State == State.Realtime && marketDataUpdate.MarketDataType == MarketDataType.Last)
		{
			if (PollLive()) NewsGuard(DateTime.UtcNow);
		}
	}

	protected override void OnBarUpdate()
	{
		if (BarsInProgress != calcSeries)
		{
			if (BarsInProgress == 0)
			{
				if (currentEma > 0.0)
				{
					Values[0][0] = currentEma;
				}
				if (ShowVisuals)
				{
					DateTime barTimeNY = ToNewYork(Times[0][0]);
					UpdateDashboard(barTimeNY);
				}
			}
		}
		else
		{
			if (CurrentBars[calcSeries] < BarsRequiredToTrade)
			{
				return;
			}
			DateTime utcNow = ToUtc(Times[calcSeries][0]);
			DateTime dateTime = ToNewYork(Times[calcSeries][0]);
			currentEma = emaIndicator[0];
			currentAtr = atrIndicator[0];
			if (calcSeries == 0)
			{
				Values[0][0] = currentEma;
			}
			if (LiveExecution && !PollLive()) { UpdateDashboard(dateTime); return; }
			NewsGuard(utcNow);
			if (LiveExecution ? LiveQuantity > 0 : Position.MarketPosition != MarketPosition.Flat)
			{
				inPosition = true;
				positionDir = LiveExecution ? live.Side : ((Position.MarketPosition == MarketPosition.Long) ? 1 : (-1));
				if (positionDir == 1)
				{
					positionExtreme = Math.Max(positionExtreme, Highs[calcSeries][0]);
				}
				else
				{
					positionExtreme = Math.Min(positionExtreme, Lows[calcSeries][0]);
				}
				if (FlatAtExit && (dateTime.Hour > ExitHourNY || (dateTime.Hour == ExitHourNY && dateTime.Minute >= ExitMinNY)))
				{
					if (positionDir == 1)
					{
						SubmitFlat(1, "OD_Flat");
					}
					else
					{
						SubmitFlat(-1, "OD_Flat");
					}
					if (WriteTradeLog)
					{
						Print($"{dateTime} [OpenDrive] 16:00 NY Cash Close reached. Position closed flat.");
					}
					if (!LiveExecution) { inPosition = false; trailActivated = false; costCoveredLocked = false; }
					statusMessage = LiveExecution ? "Owned session close pending acknowledgement" : "Closed flat at session close";
					SaveLive();
					UpdateDashboard(dateTime);
					return;
				}
				// Repair a rejected SL on next bar
				if (slRejected && State == State.Realtime)
				{
					slRejected = false;
					if (positionDir == 1)
						SubmitStop(1, LiveQuantity, positionStopPrice);
					else
						SubmitStop(-1, LiveQuantity, positionStopPrice);
					if (WriteTradeLog)
						Print($"{dateTime} [OpenDrive] SL repair re-submitted at {positionStopPrice:F2}");
				}
				if (!trailActivated && positionInitialRisk > 0.0)
				{
					double num = ((positionDir == 1) ? (Closes[calcSeries][0] - positionEntryPrice) : (positionEntryPrice - Closes[calcSeries][0]));
					if (ActivateATR < 0.0 || num >= ActivateATR * currentAtr)
					{
						trailActivated = true;
						if (WriteTradeLog)
						{
							Print($"{dateTime} [OpenDrive] Chandelier Trail ACTIVATED (+{num / currentAtr:F2} ATR profit).");
						}
					}
				}
				if (trailActivated && (!newsBlocked || !NewsBlockModifications))
				{
					double num2 = positionStopPrice;
					double num3 = ((positionDir == 1) ? (positionExtreme - TrailATR * currentAtr) : (positionExtreme + TrailATR * currentAtr));
					if ((positionDir == 1 && num3 > num2) || (positionDir == -1 && num2 > 0.0 && num3 < num2))
					{
						num2 = num3;
						positionStopPrice = num2;
						if (positionDir == 1)
						{
							SubmitStop(1, LiveQuantity, positionStopPrice);
						}
						else
						{
							SubmitStop(-1, LiveQuantity, positionStopPrice);
						}
						if (WriteTradeLog)
						{
							Print($"{dateTime} [OpenDrive] Trail Ratchet -> New SL: {positionStopPrice:F2}");
						}
					}
				}
			}
			else
			{
				inPosition = false;
				trailActivated = false;
				costCoveredLocked = false;
			}
			bool flag = dateTime.Hour == EntryHourNY && dateTime.Minute == EntryMinNY + 5;
			bool flag2 = dateTime.Date != lastEvaluatedDay.Date;
			bool flag3 = dateTime.DayOfWeek >= DayOfWeek.Monday && dateTime.DayOfWeek <= DayOfWeek.Friday;
			if (flag & flag2 & flag3)
			{
				lastEvaluatedDay = dateTime;
				// Guard: only fire entries in Realtime / Strategy Analyzer
				// Prevents 'invalid stop price near historical bar' with ImmediatelySubmit
				if (State != State.Realtime && !IsInStrategyAnalyzer)
				{
					UpdateDashboard(dateTime);
					return;
				}
				if (LiveExecution ? LiveQuantity != 0 || (!accountTransport && Position.MarketPosition != MarketPosition.Flat) : Position.MarketPosition != MarketPosition.Flat)
				{
					statusMessage = "Position open from previous day";
					UpdateDashboard(dateTime);
					return;
				}
				if (!EnableTrading)
				{
					statusMessage = "Trading disabled in inputs";
					UpdateDashboard(dateTime);
					return;
				}
				if (newsBlocked)
				{
					statusMessage = "Blocked by News Blackout (" + activeNewsTitle + ")";
					if (WriteTradeLog)
					{
						Print($"{dateTime} [OpenDrive] 09:35 entry blocked due to active news blackout window ({activeNewsTitle}).");
					}
					UpdateDashboard(dateTime);
					return;
				}
				int num4 = 0;
				double num5 = Closes[calcSeries][0];
				if (num5 > currentEma)
				{
					num4 = 1;
				}
				else if (num5 < currentEma)
				{
					num4 = -1;
				}
				if (num4 == 0)
				{
					statusMessage = "Close == EMA12 (Tie / Neutral)";
					UpdateDashboard(dateTime);
					return;
				}
				if ((num4 == 1 && !AllowLong) || (num4 == -1 && !AllowShort))
				{
					statusMessage = ((num4 == 1) ? "Longs blocked by inputs" : "Shorts blocked by inputs");
					UpdateDashboard(dateTime);
					return;
				}
				double num6 = (lastConvictionDist = ((currentAtr > 0.0) ? (Math.Abs(num5 - currentEma) / currentAtr) : 0.0));
				int num7 = 1;
				double num8 = 0.0;
				double num9 = EntryRiskScale(num6);
				double num10 = StopATR * currentAtr;
				double pointValue = Instrument.MasterInstrument.PointValue;
				double num11 = num10 * pointValue + CommissionPerContract;
				if (SizingType != OpenDriveSizingType.FixedContracts)
				{
					num8 = (lastAppliedRiskBudget = EntryRiskBudget(num9));
					if (num11 > 0.0)
					{
						num7 = (int)Math.Floor(num8 / num11);
					}
				}
				else
				{
					num8 = 0.0;
					lastAppliedRiskBudget = 0.0;
					num7 = ((RiskMode != OpenDriveRiskMode.DynamicVolatility || FixedContracts < 3) ? FixedContracts : Math.Max(1, (int)Math.Round((double)FixedContracts * num9)));
				}
				if (num7 < 1)
				{
					if (!AllowMinOneContract)
					{
						statusMessage = $"Budget ${num8:F0} < required ${num11:F0} for 1 contract";
						UpdateDashboard(dateTime);
						return;
					}
					num7 = 1;
				}
				double num15 = num5;
				double num16 = ((num4 == 1) ? (num15 - StopATR * currentAtr) : (num15 + StopATR * currentAtr));
				// Limit-entry on budget overrun: when budget < 1 contract cost and UseLimitRiskEntry is on
				bool rawBelowMin = (SizingType != OpenDriveSizingType.FixedContracts && num8 > 0.0 && num11 > 0.0 && (int)Math.Floor(num8 / num11) < 1);
				if (rawBelowMin && UseLimitRiskEntry)
				{
					double limitEntryPrice;
					if (num4 == 1)
					{
						limitEntryPrice = Instrument.MasterInstrument.RoundToTickSize(num16 + num8 / pointValue);
						if (limitEntryPrice < GetCurrentAsk())
						{
							if (!PrepareLiveEntry(1, 1, limitEntryPrice, num16, dateTime, OrderType.Limit, limitEntryPrice)) return;
							SubmitEntry(1, 1, limitEntryPrice);
							SubmitStop(1, 1, num16);
							if (!LiveExecution) longTradesToday++;
							statusMessage = $"LONG LIMIT 1c @ {limitEntryPrice:F2} | SL={num16:F2} | Budget=${num8:F0}";
							if (WriteTradeLog) Print($"{dateTime} [OpenDrive] LONG LIMIT: Limit={limitEntryPrice:F2} SL={num16:F2} Budget=${num8:F0} Cost/c=${num11:F0}");
						}
						else { statusMessage = $"Budget overrun - limit {limitEntryPrice:F2} >= ask"; }
					}
					else
					{
						limitEntryPrice = Instrument.MasterInstrument.RoundToTickSize(num16 - num8 / pointValue);
						if (limitEntryPrice > GetCurrentBid())
						{
							if (!PrepareLiveEntry(-1, 1, limitEntryPrice, num16, dateTime, OrderType.Limit, limitEntryPrice)) return;
							SubmitEntry(-1, 1, limitEntryPrice);
							SubmitStop(-1, 1, num16);
							if (!LiveExecution) shortTradesToday++;
							statusMessage = $"SHORT LIMIT 1c @ {limitEntryPrice:F2} | SL={num16:F2} | Budget=${num8:F0}";
							if (WriteTradeLog) Print($"{dateTime} [OpenDrive] SHORT LIMIT: Limit={limitEntryPrice:F2} SL={num16:F2} Budget=${num8:F0} Cost/c=${num11:F0}");
						}
						else { statusMessage = $"Budget overrun - limit {limitEntryPrice:F2} <= bid"; }
					}
				}
				else if (num4 == 1)
				{
					if (!PrepareLiveEntry(1, num7, num15, num16, dateTime, OrderType.Market, 0)) return;
					SubmitEntry(1, num7, 0);
					SubmitStop(1, num7, num16);
					if (!LiveExecution) longTradesToday++;
					statusMessage = $"LONG {num7} contracts @ {num15:F2} (Dist: {num6:F2} ATR)";
				}
				else
				{
					if (!PrepareLiveEntry(-1, num7, num15, num16, dateTime, OrderType.Market, 0)) return;
					SubmitEntry(-1, num7, 0);
					SubmitStop(-1, num7, num16);
					if (!LiveExecution) shortTradesToday++;
					statusMessage = $"SHORT {num7} contracts @ {num15:F2} (Dist: {num6:F2} ATR)";
				}
				positionEntryPrice = num15;
				positionStopPrice = num16;
				positionExtreme = num15;
				positionInitialRisk = StopATR * currentAtr;
				trailActivated = false;
				costCoveredLocked = false;
				positionEntryTime = dateTime;
				if (ShowExtras)
				{
					string tag = "OD_Box_" + dateTime.ToString("yyyyMMdd_HHmm");
					Brush areaBrush = ((num4 == 1) ? Brushes.LimeGreen : Brushes.OrangeRed);
					Draw.Rectangle(this, tag, isAutoScale: false, 1, High[0], 0, Low[0], Brushes.Transparent, areaBrush, 30);
				}
				if (WriteTradeLog)
				{
					Print(string.Format("{0} [OpenDrive] {1} Entry Submitted: Contracts={2} | Planned SL={3:F2} | Conviction={4:F2} ATR | Budget=${5:F0}", dateTime, (num4 == 1) ? "LONG" : "SHORT", num7, num16, num6, num8));
				}
			}
			UpdateDashboard(dateTime);
			SaveLive();
		}
	}

	private void RecoverOpenPosition()
	{
		if (live == null) { LiveWait("owned checkpoint unavailable"); return; }
		RestoreLiveFields();
		if (!accountTransport && Position.MarketPosition != MarketPosition.Flat)
		{ liveFault = "Legacy native position has no durable ownership; existing protection untouched"; LiveWait(liveFault); return; }
		recoveredPosition = accountTransport;
		resumePendingLimit = accountTransport && live.Entered == 0 && live.Exited == 0 && live.Orders.Any(o => o.Role == "Entry" && o.Type == "Limit");
		PollLive(); // exact-order handoff performs no Submit/Change/Cancel
	}

	protected override void OnOrderUpdate(Order order, double limitPrice, double stopPrice,
		int quantity, int filled, double averageFillPrice, OrderState orderState,
		DateTime time, ErrorCode error, string nativeError)
	{
		if (LiveExecution) { RunLiveCallback(() => LiveOrderEvent(order, error, nativeError)); return; }
		if (order == null || order.Name == null) return;
		string n = order.Name;
		// Only process OD-owned orders; silently ignore all other strategies' orders
		if (n != "OD_SL" && n != "OD_Long" && n != "OD_Short"
		 && n != "OD_Flat" && n != "OD_NewsFlat") return;

		// Track live SL reference
		if (n == "OD_SL" && orderState != OrderState.Filled
			&& orderState != OrderState.Cancelled && orderState != OrderState.Rejected)
			odSLOrder = order;

		// Detect SL rejection -> flag for repair next bar
		if (n == "OD_SL" && (orderState == OrderState.Rejected || error != ErrorCode.NoError))
		{
			slRejected = true;
			if (WriteTradeLog)
				Print($"[OpenDrive] OD_SL rejected (err={error}, native='{nativeError}'). Repair queued for next bar.");
		}
	}

	private void UpdateDashboard(DateTime barTimeNY)
	{
		if (ShowVisuals && dashboard != null)
		{
			string news;
			if (NewsImpact == OpenDriveNewsImpact.Off)
			{
				news = "News: OFF";
			}
			else if (newsBlocked)
			{
				news = "News: BLACKOUT [" + ((activeNewsTitle.Length > 16) ? activeNewsTitle.Substring(0, 16) : activeNewsTitle) + "]";
			}
			else if (costCoveredLocked)
			{
				news = "News: Cost BE Locked";
			}
			else if (!(upcomingNewsUtc != DateTime.MinValue))
			{
				news = ((newsEvents == null || newsEvents.Length == 0) ? "News: Syncing Calendar..." : "News: Active (No Events Soon)");
			}
			else
			{
				DateTime dateTime = TimeZoneInfo.ConvertTimeFromUtc(upcomingNewsUtc, NewYorkTimeZone);
				string arg = ((upcomingNewsTitle.Length > 14) ? upcomingNewsTitle.Substring(0, 14) : upcomingNewsTitle);
				news = $"News: {dateTime:HH:mm} NY [{arg}]";
			}
			ModelDashState next = new ModelDashState
			{
				Title = "OpenDrive — NQ 9:30",
				Clock = $"NY: {barTimeNY:HH:mm:ss} | CT: {barTimeNY.AddHours(-1.0):HH:mm:ss}",
				Status = statusMessage,
				RangeCaption = $"EMA {EmaPeriod} / ATR({AtrPeriod})",
				RangeWidth = $"{currentEma:F2}",
				HighCaption = "ATR",
				RangeHigh = $"{currentAtr:F2}",
				LowCaption = "TRADES",
				RangeLow = $"L:{longTradesToday} | S:{shortTradesToday}",
				Position = ((!inPosition) ? "FLAT" : ((positionDir == 1) ? "LONG OPEN" : "SHORT OPEN")),
				InTrade = inPosition,
				Stop = (inPosition ? $"{positionStopPrice:F2}" : $"SL x{StopATR:F1}"),
				Risk = string.Format("{0} [{1}]", (RiskMode == OpenDriveRiskMode.DynamicVolatility) ? "DynVol" : "Static", (SizingType == OpenDriveSizingType.PercentRisk) ? $"{RiskPercent:F1}%" : ((SizingType == OpenDriveSizingType.FixedDollar) ? $"${RiskMoney:F0}" : $"{FixedContracts}c")),
				Costs = $"Conviction: {((lastConvictionDist >= 0.0) ? lastConvictionDist : 0.0):F2} ATR | Comm: ${CommissionPerContract:F1}",
				History = (trailActivated ? "Trail: ACTIVE (3.0 ATR)" : $"Trail: Arm at +{ActivateATR:F2} ATR"),
				News = news,
				NewsBlocked = newsBlocked
			};
			dashboard.Publish(next);
			RequestDashboardRender();
		}
	}

	protected override void OnRender(ChartControl chartControl, ChartScale chartScale)
	{
		base.OnRender(chartControl, chartScale);
		if (!ShowVisuals || dashboard == null || chartControl == null)
		{
			return;
		}
		try
		{
			try
			{
				if (!dashboardLayered)
				{
					SetZOrder(int.MaxValue);
					dashboardLayered = true;
				}
			}
			catch
			{
			}
			HookDashboardMouse(attach: true);
			dashboard.Render(RenderTarget, chartControl);
		}
		catch (Exception ex)
		{
			if (WriteTradeLog)
			{
				Print("[OpenDrive] Dashboard render exception: " + ex.Message);
			}
		}
	}

	private void RequestDashboardRender()
	{
		ChartControl chart = ChartControl;
		if (!ShowVisuals || chart == null || chart.Dispatcher.HasShutdownStarted || chart.Dispatcher.HasShutdownFinished || Interlocked.CompareExchange(ref dashboardRedrawQueued, 1, 0) != 0)
		{
			return;
		}
		try
		{
			chart.Dispatcher.InvokeAsync(() =>
			{
				Interlocked.Exchange(ref dashboardRedrawQueued, 0);
				if (State != State.Terminated && ShowVisuals && chart == ChartControl)
				{
					chart.InvalidateVisual();
				}
			}, DispatcherPriority.Background);
		}
		catch (InvalidOperationException)
		{
			Interlocked.Exchange(ref dashboardRedrawQueued, 0);
		}
	}

	private void HookDashboardMouse(bool attach)
	{
		if (!attach)
		{
			dashboardLayered = false;
			dashboard.MouseUp();
		}
		ChartControl chart = (attach ? ChartControl : dashboardChart);
		if (chart == null || dashboardMouseHooked == attach)
		{
			return;
		}
		dashboardMouseHooked = attach;
		dashboardChart = (attach ? chart : null);
		chart.Dispatcher.InvokeAsync(() =>
		{
			if (attach && State != State.Terminated)
			{
				chart.PreviewMouseLeftButtonDown += DashboardMouseDown;
				chart.PreviewMouseMove += DashboardMouseMove;
				chart.PreviewMouseLeftButtonUp += DashboardMouseUp;
			}
			else
			{
				chart.PreviewMouseLeftButtonDown -= DashboardMouseDown;
				chart.PreviewMouseMove -= DashboardMouseMove;
				chart.PreviewMouseLeftButtonUp -= DashboardMouseUp;
			}
		});
	}

	private Point DashboardPoint(ChartControl chart, Point point)
	{
		return PresentationSource.FromVisual(chart)?.CompositionTarget.TransformToDevice.Transform(point) ?? point;
	}

	private void DashboardMouseDown(object sender, MouseButtonEventArgs e)
	{
		try
		{
			ChartControl chartControl = ChartControl;
			if (ShowVisuals && State != State.Terminated && chartControl != null && dashboard != null)
			{
				Point point = DashboardPoint(chartControl, e.GetPosition(chartControl));
				if (dashboard.MouseDown(point.X, point.Y))
				{
					e.Handled = true;
					chartControl.InvalidateVisual();
				}
			}
		}
		catch (Exception)
		{
		}
	}

	private void DashboardMouseMove(object sender, MouseEventArgs e)
	{
		try
		{
			ChartControl chartControl = ChartControl;
			if (chartControl != null && dashboard != null)
			{
				Point point = DashboardPoint(chartControl, e.GetPosition(chartControl));
				if (dashboard.MouseMove(point.X, point.Y))
				{
					e.Handled = true;
					chartControl.InvalidateVisual();
				}
			}
		}
		catch (Exception)
		{
		}
	}

	private void DashboardMouseUp(object sender, MouseButtonEventArgs e)
	{
		try
		{
			if (dashboard != null && dashboard.MouseUp())
			{
				e.Handled = true;
				if (ChartControl != null)
				{
					ChartControl.InvalidateVisual();
				}
			}
		}
		catch (Exception)
		{
		}
	}
}
}
