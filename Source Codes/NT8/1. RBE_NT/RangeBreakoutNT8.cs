//+------------------------------------------------------------------+
//|                                            RangeBreakoutNT8.cs  |
//| Fixed New York Evening Range Breakout Strategy on Gold           |
//| Developed by Osamwonyi Eric (You_FoundEric)                      |
//| Copyright 2026-2027, Osamwonyi Eric (@You_FoundEric)             |
//+------------------------------------------------------------------+

using NinjaTrader.Cbi;
using NinjaTrader.Core;
using NinjaTrader.Data;
using NinjaTrader.Gui.Chart;
using NinjaTrader.Gui.NinjaScript;
using NinjaTrader.Gui;
using NinjaTrader.NinjaScript.DrawingTools;
using NinjaTrader.NinjaScript.Strategies.RBE_NT;
using SharpDX.Direct2D1;
using SharpDX.DirectWrite;
using SharpDX;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Runtime.CompilerServices;
using System.Security.Cryptography;
using System.Text.RegularExpressions;
using System.Text;
using System.Threading.Tasks;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using System.Windows;
using System.Xml.Serialization;
using System.Xml;
using System;
using Brush = System.Windows.Media.Brush;
using SolidColorBrush = SharpDX.Direct2D1.SolidColorBrush;
using Point = System.Windows.Point;

namespace NinjaTrader.NinjaScript.Strategies
{
public enum RbeTradeDirection
{
	Both,
	LongOnly,
	ShortOnly,
	Off
}

public enum RbeNewsImpact
{
	Off,
	Red,
	RedYellow,
	All
}

public enum RbeNewsWindow
{
	Five = 5,
	Ten = 10,
	Fourteen = 14,
	Twenty = 20
}

public class RangeBreakoutNT8 : Strategy
{
	private sealed class OwnedOrder
	{
		public Order Order;

		public OrderState State;

		public int ReportedFills;

		public int ProcessedFills;

		public bool CancelRequested;

		public int Quantity;

		public double StopPrice;

		public RbeNetLeg NetLeg;
	}

	private sealed class RestartOwner
	{
		public Account Account;

		public string Prefix;

		public bool InternalBooksActive;
	}

	private sealed class NewsEvent
	{
		public DateTime Utc;

		public string Impact;

		public string Title;
	}

	private enum NetRole
	{
		Entry,
		Protection,
		Adjustment
	}

	private sealed class NetIntent
	{
		public NetRole Role;

		public RbeNetLeg Leg;

		public double Distance;

		public OwnedOrder Tracked;
	}

	private Dictionary<Order, OwnedOrder> orders;

	private HashSet<string> executions;

	private HashSet<string> ownedEntrySignals;

	private int cycle;

	private int sessionBuyFills;

	private int sessionSellFills;

	private bool newsBeEligible;

	private static readonly Dictionary<long, RestartOwner> restartOwners = new Dictionary<long, RestartOwner>();

	private RbeSettings settings;

	private RbeModel model;

	private bool executionFailed;

	private RbeRangeVisual rangeVisual;

	private List<RbeTradeVisual> closedVisuals;

	private List<RbeRangeVisual> completedRanges;

	private RbeVisualReplay visualReplay;

	private HashSet<string> nativeVisualKeys;

	private HashSet<string> paintedReplay;

	private DateTime visualPulse;

	private DateTime historicalStartNy;

	private DateTime historicalEndNy;

	private int executionSeries;

	private int processedMinutes;

	private long startedAt;

	private RangeBreakoutNT8 auditOwner;

	private static readonly Dictionary<string, RangeBreakoutNT8> visualOwners = new Dictionary<string, RangeBreakoutNT8>();

	private string owner;

	private string status = "Building range";

	private TimeZoneInfo platformZone;

	private StreamWriter audit;
	private bool nullModelNoticed;
	private int riskSkipReports;
	private int rollSettleQuotes;
	private int historicalIgnoredEntries;
	private bool bootstrapNoticed;

	private bool buyTouched;

	private bool sellTouched;

	private bool skipRealtimeSession;

	private bool firstRealtimeQuote;

	private bool visualFault;

	private bool historicalVisualsPainted;

	private int historicalEntries;

	private int historicalEntryRequests;

	private int historicalRiskSkips;

	private int historicalIncompleteTouches;

	private Timer panelClock;

	private RbeDashboard dashboard;

	private bool dashboardMouseHooked;

	private bool dashboardFaultLogged;

	private bool dashboardLayered;

	private int dashboardRedrawQueued;

	private bool nativeDisplayQueued;

	private ChartControl dashboardChart;

	private double last;

	private double bid;

	private double ask;

	private DateTime latestTime;

	private DateTime latestNy;

	private string rangeTag;

	private static readonly HttpClient newsHttp = CreateNewsHttp();

	private readonly object newsLock = new object();

	private NewsEvent[] newsEvents = new NewsEvent[0];

	private DateTime newsFetchedUtc = DateTime.MinValue;

	private DateTime newsAttemptUtc = DateTime.MinValue;

	private DateTime newsWeekNy;

	private bool newsFetching;

	private bool newsBlocked;

	private double newsCycleCommission;

	private double newsCycleEntryQuantity;

	private double newsObservedCommission;

	private double newsObservedQuantity;

	private static readonly TimeZoneInfo NewsZone = TimeZoneInfo.FindSystemTimeZoneById("Eastern Standard Time");

	private string legacyBrokerCloseConfirmation = string.Empty;

	private const double StopPercent = 0.6;

	private const double MinimumRangePercent = 0.4;

	private const double TrailTriggerPercent = 2.6;

	private const double TrailDistancePercent = 0.6;

	private const double TrailStepPrice = 1.0;

	private const bool CoverCosts = true;

	private const double CostCoverageMultiple = 1.25;

	private Dictionary<string, NetIntent> netIntents;

	private List<NetIntent> netSessionIntents;

	private RbeNetBook netBook;

	private int netActual;

	private int netCloseQuantity;

	private double netCloseValue;

	private DateTime netCloseTime;

	private bool netCutoff;

	private bool netSubmitting;

	private bool netClosing;

	private bool netReconciling;

	private bool netHistoricalQuoteReplay;

	private bool netLongReady;

	private bool netShortReady;

	private DateTime netHistoricalBarTime;

	private OwnedOrder netMarket;

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

	private const string ExecutionModel = "NetExposure";

	private bool driving;

	private bool driveAgain;

	private RbeRecoveryStore recoveryStore;

	private RbeRecoveryRecord recoveryRecord;

	private string recoveryFingerprint;
	private string brokerRestrictionReason;

	private string recoverySeedName;

	private string recoveryCanonicalSettings;

	private bool recoveryNeeded;

	private bool recoveryBooting;

	private bool recoverySeedSubmitted;

	private bool recoveryStaged;

	private bool recoveryWriteFault;

	private bool recoveryAccountMode;

	private bool recoveryAccountSubscribed;

	private string recoveryAccountWait;

	private int recoverySeedFilled;

	private readonly object recoveryStateGate = new object();

	private static readonly XmlSerializer RecoverySerializer = new XmlSerializer(typeof(RbeRecoveryRecord));

	private string recoveryPayload;

	private DateTime recoveryLivePollUtc;

	private bool recoveryLiveReplaying;

	private readonly HashSet<string> recoveryLiveOrders = new HashSet<string>();

	private readonly HashSet<string> recoveryLiveExecutions = new HashSet<string>();

	private readonly Dictionary<string, Order> recoveryNativeOrders = new Dictionary<string, Order>();

	private readonly Dictionary<string, Order> recoveryBrokerOrders = new Dictionary<string, Order>();

	private bool IsPlayback => Connection.PlaybackConnection != null;

	[Browsable(false)]
	public override string DisplayName => "Range Breakout";

	[NinjaScriptProperty]
	[Display(Name = "Enable new trades", GroupName = "0. Trading", Order = 0)]
	public bool EnableNewTrades { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "Block opposing index exposure", GroupName = "0. Trading", Order = 1)]
	public bool BlockOpposingIndexExposure { get; set; }

	[Browsable(false)]
	[XmlIgnore]
	private string BrokerCloseConfirmation
	{
		get
		{
			return legacyBrokerCloseConfirmation ?? string.Empty;
		}
		set
		{
			legacyBrokerCloseConfirmation = value ?? string.Empty;
		}
	}

	[NinjaScriptProperty]
	[Range(1.0, double.MaxValue)]
	[Display(Name = "Risk per trade ($)", Description = "Modeled stop loss plus commission and assumed slippage. With strict risk off, one contract can exceed this target.", GroupName = "1. Risk and direction", Order = 1)]
	public double RiskMoney { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "Enforce risk limit", Description = "Skip entries when one contract exceeds the modeled risk budget. Disable to use a one-contract minimum.", GroupName = "1. Risk and direction", Order = 2)]
	public bool EnforceRiskLimit { get; set; }

	[NinjaScriptProperty]
	[Range(1, 40)]
	[Display(Name = "Maximum contracts", Description = "Contract limit for this strategy instance.", GroupName = "1. Risk and direction", Order = 3)]
	public int MaxContracts { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "Enable use of fixed contract", Description = "When enabled, every entry uses the fixed contract quantity below. Risk per trade, Enforce risk limit and Maximum contracts are ignored for sizing, whatever their values.", GroupName = "1. Risk and direction", Order = 4)]
	public bool UseFixedContract { get; set; }

	[NinjaScriptProperty]
	[Range(1, 40)]
	[Display(Name = "Fixed contracts", Description = "Contracts per entry when fixed contract is enabled.", GroupName = "1. Risk and direction", Order = 5)]
	public int FixedContracts { get; set; }

	[NinjaScriptProperty]
	[Range(0.0, double.MaxValue)]
	[Display(Name = "Commission per contract, round trip ($)", Description = "Set for the selected contract: supplied Tradeify costs are MGC 2.12 and GC 6.20. Used for sizing and cost coverage; select the matching NT8 commission template for backtest PnL.", GroupName = "2. Trading costs", Order = 0)]
	public double RoundTripCommission { get; set; }

	[NinjaScriptProperty]
	[Range(0, 100)]
	[Display(Name = "Slippage per fill (ticks)", Description = "Historical fill assumption; sizing includes one entry and one exit.", GroupName = "2. Trading costs", Order = 1)]
	public int AssumedSlipTicks { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "Trade direction", Description = "Both keeps independent internal long/short books and trades their net exposure. LongOnly/ShortOnly enable one range side. Off disables entries.", GroupName = "1. Risk and direction", Order = 0)]
	public RbeTradeDirection TradeDirection
	{
		get
		{
			if (MaxBuy > 0 && MaxSell > 0)
			{
				return RbeTradeDirection.Both;
			}
			if (MaxBuy > 0)
			{
				return RbeTradeDirection.LongOnly;
			}
			return (MaxSell > 0) ? RbeTradeDirection.ShortOnly : RbeTradeDirection.Off;
		}
		set
		{
			MaxBuy = ((value == RbeTradeDirection.Both || value == RbeTradeDirection.LongOnly) ? 1 : 0);
			MaxSell = ((value == RbeTradeDirection.Both || value == RbeTradeDirection.ShortOnly) ? 1 : 0);
		}
	}

	[NinjaScriptProperty]
	[Range(0, 1)]
	[Browsable(false)]
	public int MaxBuy { get; set; }

	[NinjaScriptProperty]
	[Range(0, 1)]
	[Browsable(false)]
	public int MaxSell { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "News impact", Description = "ForexFactory USD news. Missing or stale live feed blocks new entries. Disable for historical Analyzer runs.", GroupName = "3. News guard", Order = 0)]
	public RbeNewsImpact NewsImpact { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "Total blackout", Description = "Symmetric window around release: 5=2.5/2.5, 10=5/5, 14=7/7, 20=10/10 minutes.", GroupName = "3. News guard", Order = 1)]
	public RbeNewsWindow NewsWindow { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "Cost-covered stop before news", GroupName = "3. News guard", Order = 2)]
	public bool NewsCostCoveredBE { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "Flatten before news", GroupName = "3. News guard", Order = 3)]
	public bool NewsFlattenBefore { get; set; }

	[Browsable(false)]
	public bool ShowVisuals { get; set; }

	[Browsable(false)]
	public bool WriteAudit { get; set; }

	private int NetTarget => (!netClosing && !netCutoff && !executionFailed) ? netBook.Target : 0;

	private static HttpClient CreateNewsHttp()
	{
		HttpClient httpClient = new HttpClient
		{
			Timeout = TimeSpan.FromSeconds(5.0)
		};
		httpClient.DefaultRequestHeaders.UserAgent.ParseAdd("Mozilla/5.0");
		httpClient.DefaultRequestHeaders.Accept.ParseAdd("application/json");
		return httpClient;
	}

	protected override void OnStateChange()
	{
		if (State == State.Historical || State == State.Transition || State == State.Terminated)
		{
			if (State == State.Terminated && model != null && IsInStrategyAnalyzer)
			{
				Print("[RBE] Analyzer run summary: " + processedMinutes + " minutes processed; " + historicalEntries + " entries; " + historicalRiskSkips + " risk skips; " + historicalIgnoredEntries + " entries ignored by NinjaTrader (" + (UseFixedContract ? "fixed contract: " + FixedContracts + " per entry" : "strict risk, $" + RiskMoney.ToString("0", CultureInfo.InvariantCulture) + " budget, max " + MaxContracts + " contract(s)") + ").");
			}
			else if (State != State.Terminated)
			{
				Print("[RBE] state " + State + " reached; model initialised=" + (model != null) + "; analyzer=" + IsInStrategyAnalyzer);
			}
		}
		if (State == State.SetDefaults)
		{
			Name = "Range Breakout";
			BlockOpposingIndexExposure = true;
			Description = "Range Breakout - Gold evening range breakout. Builds the 20:05-23:05 New York range; applies a 0.4% minimum range, 0.6% stop, 2.6% trailing activation and 11:55 New York exit. Direction controls, cost-aware sizing and news guard. Copyright 2026-2027, Osamwonyi Eric (@You_FoundEric). Developed by @You_FoundEric. Unauthorized redistribution prohibited.";
			Calculate = Calculate.OnEachTick;
			StartBehavior = StartBehavior.ImmediatelySubmit;
			ConnectionLossHandling = ConnectionLossHandling.KeepRunning;
			IsAdoptAccountPositionAware = false;
			IsExitOnSessionCloseStrategy = false;
			EntriesPerDirection = 1;
			EntryHandling = EntryHandling.UniqueEntries;
			StopTargetHandling = StopTargetHandling.PerEntryExecution;
			// Owned rejection handling below retains surviving broker protection.
			RealtimeErrorHandling = RealtimeErrorHandling.IgnoreAllErrors;
			BarsRequiredToTrade = 0;
			MaximumBarsLookBack = MaximumBarsLookBack.Infinite;
			OrderFillResolution = OrderFillResolution.Standard;
			IsFillLimitOnTouch = true;
			Slippage = 1.0;
			TimeInForce = TimeInForce.Gtc;
			IncludeCommission = true;
			IncludeTradeHistoryInBacktest = true;
			IsOverlay = true;
			DrawOnPricePanel = true;
			IsInstantiatedOnEachOptimizationIteration = true;
			RiskMoney = 500.0;
			EnableNewTrades = true;
			BrokerCloseConfirmation = string.Empty;
			EnforceRiskLimit = true;
			RoundTripCommission = 3.0;
			AssumedSlipTicks = 1;
			int maxBuy = (MaxSell = 1);
			MaxBuy = maxBuy;
			MaxContracts = 1;
			UseFixedContract = false;
			FixedContracts = 1;
			ShowVisuals = true;
			WriteAudit = false;
			NewsImpact = RbeNewsImpact.Red;
			NewsWindow = RbeNewsWindow.Ten;
			NewsCostCoveredBE = true;
			NewsFlattenBefore = false;
			return;
		}
		if (State == State.Configure)
		{
			IsUnmanaged = true;
			IncludeTradeHistoryInBacktest = true;
			if (StartBehavior != StartBehavior.ImmediatelySubmit)
			{
				throw new InvalidOperationException("RBE requires ImmediatelySubmit to preserve strategy ownership.");
			}
			owner = "RBE" + Guid.NewGuid().ToString("N");
			platformZone = Globals.GeneralOptions.TimeZoneInfo;
			startedAt = Stopwatch.GetTimestamp();
			processedMinutes = 0;
			audit = null;
			auditOwner = this;
			// Audit CSV output is removed. The former writer created a GUID-named file in a hard-coded directory on every
			// Configure (including each launch with a saved WriteAudit=true instance). WriteAudit is now ignored; audit stays
			// null and every Log call returns without touching the disk.
			if (WriteAudit)
			{
				Print("[RBE] WriteAudit is ignored in this build; no audit file is written.");
			}
			Log("CONFIGURE", 0, 0, 0.0, "MINUTE_HISTORY", TimeZoneInfo.ConvertTimeFromUtc(DateTime.UtcNow, platformZone));
			executionSeries = 0;
			if (BarsPeriod.BarsPeriodType != BarsPeriodType.Minute || BarsPeriod.Value != 1)
			{
				AddDataSeries(BarsPeriodType.Minute, 1);
				executionSeries = 1;
			}
			OrderFillResolution = OrderFillResolution.Standard;
			Slippage = AssumedSlipTicks;
			return;
		}
		if (State == State.DataLoaded)
		{
			OpenRecoveryStore();
			if (!recoveryNeeded)
			{
				GuardOwnedRestart();
			}
			if (IsInStrategyAnalyzer && NewsImpact != RbeNewsImpact.Off)
			{
				// ForexFactory supplies current-week live news only; the default is Red, so this used to stop every Analyzer run.
				Print("[RBE] Strategy Analyzer: news impact forced to Off. Historical results exclude news blackout, news BE and news flattening.");
				NewsImpact = RbeNewsImpact.Off;
			}
			if (NewsImpact != RbeNewsImpact.Off)
			{
				Print("[RBE] ForexFactory news is live-only; chart historical executions are not news-filtered.");
			}
			if (TickSize <= 0.0 || double.IsNaN(TickSize) || double.IsInfinity(TickSize) || Instrument.MasterInstrument.PointValue <= 0.0 || double.IsNaN(Instrument.MasterInstrument.PointValue) || double.IsInfinity(Instrument.MasterInstrument.PointValue))
			{
				throw new InvalidOperationException("Range Breakout requires a valid instrument tick size and point value.");
			}
			orders = new Dictionary<Order, OwnedOrder>();
			executions = new HashSet<string>();
			ownedEntrySignals = new HashSet<string>();
			cycle = 0;
			sessionBuyFills = (sessionSellFills = 0);
			newsBeEligible = false;
			executionFailed = (visualFault = (historicalVisualsPainted = false));
			historicalEntries = (historicalEntryRequests = (historicalRiskSkips = (historicalIncompleteTouches = 0)));
			buyTouched = (sellTouched = (skipRealtimeSession = (firstRealtimeQuote = false)));
			latestTime = (latestNy = DateTime.MinValue);
			newsEvents = new NewsEvent[0];
			newsFetchedUtc = (newsAttemptUtc = DateTime.MinValue);
			newsFetching = (newsBlocked = false);
			newsCycleCommission = (newsCycleEntryQuantity = (newsObservedCommission = (newsObservedQuantity = 0.0)));
			last = (bid = (ask = 0.0));
			rangeTag = null;
			status = "Building range";
			platformZone = Globals.GeneralOptions.TimeZoneInfo;
			settings = new RbeSettings
			{
				StopPercent = 0.6,
				MinimumRangePercent = 0.4,
				TrailTriggerPercent = 2.6,
				TrailDistancePercent = 0.6,
				TrailStepPrice = 1.0,
				CoverCosts = true,
				CostCoverageMultiple = 1.25
			};
			model = new RbeModel(settings);
			InitializeNetExposure();
			rangeVisual = new RbeRangeVisual(MaxBuy > 0, MaxSell > 0);
			closedVisuals = new List<RbeTradeVisual>();
			completedRanges = new List<RbeRangeVisual>();
			nativeVisualKeys = new HashSet<string>();
			paintedReplay = new HashSet<string>();
			visualReplay = new RbeVisualReplay(owner, settings, MaxBuy > 0, MaxSell > 0, TickSize, Instrument.MasterInstrument.PointValue, Cost());
			if (!recoveryAccountMode)
			{
				ReconcileRecoveryStartup();
			}
			dashboard = new RbeDashboard();
			dashboardMouseHooked = (dashboardFaultLogged = false);
			nativeDisplayQueued = false;
			visualPulse = DateTime.MinValue;
			historicalStartNy = ((BarsArray[executionSeries].Count > 0) ? RbeModel.ToNewYork(BarsArray[executionSeries].GetTime(0), platformZone) : DateTime.MinValue);
			historicalEndNy = ((BarsArray[executionSeries].Count > 0) ? RbeModel.ToNewYork(BarsArray[executionSeries].GetTime(BarsArray[executionSeries].Count - 1), platformZone) : DateTime.MinValue);
			lock (visualOwners)
			{
				visualOwners[owner] = this;
			}
			PurgeStaleVisuals();
			Log("DATA_LOADED", 0, 0, 0.0, "MINUTES=" + BarsArray[executionSeries].Count, TimeZoneInfo.ConvertTimeFromUtc(DateTime.UtcNow, platformZone));
			Log("SETTINGS", 0, 0, 0.0, string.Format(CultureInfo.InvariantCulture, "CONTRACT={0};TICK={1};POINT_VALUE={2};RISK={3};STRICT={4};MAX_CONTRACTS={5};STOP_PCT={6};MIN_RANGE_PCT={7};TRAIL_TRIGGER_PCT={8};TRAIL_DISTANCE_PCT={9};TRAIL_STEP={10};COVER_COSTS={11};COST_MULTIPLE={12};RT_COMMISSION={13};ASSUMED_SLIP_TICKS={14};NATIVE_SLIP_TICKS={15};DIRECTION={16};EXECUTION={17};NEWS={18};TIMEZONE={19}", Instrument.FullName, TickSize, Instrument.MasterInstrument.PointValue, RiskMoney, EnforceRiskLimit, MaxContracts, 0.6, 0.4, 2.6, 0.6, 1.0, true, 1.25, RoundTripCommission, AssumedSlipTicks, Slippage, TradeDirection, "NetExposure", NewsImpact, platformZone.Id));
			Print("[" + owner + "] RBE visual build 2026-10-09. Range NY 20:05-23:05; cutoff 11:55. Cash risk $" + RiskMoney + "; " + Instrument.MasterInstrument.Name + " modeled RT friction $" + Cost().ToString("0.00") + ". Instance cap " + EffectiveMaxContracts + "." + (UseFixedContract ? " FIXED CONTRACT mode: " + FixedContracts + " contract(s) per entry; risk budget, risk enforcement and the contract cap are ignored for sizing." : string.Empty));
			{
				int barCount = BarsArray[executionSeries].Count;
				if (barCount > 0 && EnforceRiskLimit && !UseFixedContract)
				{
					double firstPx = BarsArray[executionSeries].GetClose(0);
					double lastPx = BarsArray[executionSeries].GetClose(barCount - 1);
					double pv = Instrument.MasterInstrument.PointValue;
					double needFirst = firstPx * 0.006 * pv + Cost();
					double needLast = lastPx * 0.006 * pv + Cost();
					if (Math.Min(needFirst, needLast) > RiskMoney)
					{
						Print("[RBE] WARNING: one " + Instrument.MasterInstrument.Name + " contract needs about $" + needFirst.ToString("0", CultureInfo.InvariantCulture) + " (first loaded price) to $" + needLast.ToString("0", CultureInfo.InvariantCulture) + " (last loaded price) of risk budget, above your $" + RiskMoney.ToString("0", CultureInfo.InvariantCulture) + ". With strict risk on, every entry will be skipped. Use MGC or raise Risk.");
					}
					else if (Math.Max(needFirst, needLast) > RiskMoney)
					{
						Print("[RBE] NOTE: one " + Instrument.MasterInstrument.Name + " contract needs $" + needFirst.ToString("0", CultureInfo.InvariantCulture) + " to $" + needLast.ToString("0", CultureInfo.InvariantCulture) + " of risk budget across the loaded prices; entries are skipped on the days it exceeds your $" + RiskMoney.ToString("0", CultureInfo.InvariantCulture) + ".");
					}
				}
			}
			return;
		}
		if (State == State.Transition)
		{
			ValidateRecoveryTransition();
			if (executionFailed)
			{
				Print("[RBE] Historical replay failed; see the first NET_ERROR above.");
				throw new InvalidOperationException("RBE historical order replay failed; see the first ORDER_ERROR in NinjaScript Output. Live activation refused.");
			}
			historicalVisualsPainted = false;
			paintedReplay.Clear();
			Print("[RBE] Loaded minute history " + historicalStartNy.ToString("yyyy-MM-dd HH:mm") + " to " + historicalEndNy.ToString("yyyy-MM-dd HH:mm") + " NY; processed " + processedMinutes + " minutes; native entry requests " + historicalEntryRequests + "; native fills " + historicalEntries + "; risk-skipped touches " + historicalRiskSkips + "; incomplete-session touches " + historicalIncompleteTouches + ".");
			if (!IsInStrategyAnalyzer && historicalEntries == 0)
			{
				Print("[RBE] No chart historical fills. Check the loaded minute span includes a 20:05-23:05 NY range and its following 11:55 NY exit; see native entry requests above.");
			}
			if (!recoveryNeeded && (netActual != 0 || netBook.Active))
			{
				// Live activation must start flat. The Analyzer only replays history, so a range that ends mid-trade is reported and the run continues.
				if (!IsInStrategyAnalyzer)
				{
					throw new InvalidOperationException("Net exposure history must finish flat before live activation.");
				}
				Print("[RBE] Analyzer: history ends with an open internal net book; the run continues and the position is not force-closed at data end.");
			}
			{
				foreach (RbeTradeVisual closedVisual in closedVisuals)
				{
					DrawTrade(closedVisual, closedVisual.ExitTime);
				}
				return;
			}
		}
		if (State == State.Realtime)
		{
			GuardNetActivation();
			if (recoveryAccountMode)
			{
				Account.OrderUpdate += RecoveredAccountOrderUpdate;
				Account.ExecutionUpdate += RecoveredAccountExecutionUpdate;
				recoveryAccountSubscribed = true;
				status = "Recovery pending: exact owned broker snapshot";
			}
			else
			{
				CompleteRecoveryActivation();
			}
			EnableNativeExecutionDisplay();
			firstRealtimeQuote = true;
			if (IsPlayback && NewsImpact != RbeNewsImpact.Off)
			{
				Print("[RBE] Playback news omitted: ForexFactory has no historical calendar. Playback orders exclude news blackout, news BE and news flattening.");
			}
			BeginNewsFetch();
			panelClock = new Timer(UpdatePanelClock, null, 1000, 1000);
			List<OwnedOrder> list = (recoveryNeeded ? new List<OwnedOrder>() : new List<OwnedOrder>(orders.Values));
			if (!recoveryNeeded)
			{
				orders.Clear();
			}
			{
				foreach (OwnedOrder item in list)
				{
					if (!Terminal(item.State))
					{
						item.Order = GetRealtimeOrder(item.Order);
					}
					orders.Add(item.Order, item);
				}
				return;
			}
		}
		if (State != State.Terminated)
		{
			return;
		}
		if (recoveryAccountSubscribed && Account != null)
		{
			Account.OrderUpdate -= RecoveredAccountOrderUpdate;
			Account.ExecutionUpdate -= RecoveredAccountExecutionUpdate;
			recoveryAccountSubscribed = false;
		}
		CloseRecoveryStore();
		if (panelClock != null)
		{
			panelClock.Dispose();
			panelClock = null;
		}
		HookDashboardMouse(attach: false);
		if (audit != null && auditOwner == this)
		{
			Log("TERMINATED", 0, 0, 0.0, "MINUTES=" + processedMinutes, TimeZoneInfo.ConvertTimeFromUtc(DateTime.UtcNow, platformZone));
			audit.Dispose();
			audit = null;
		}
		lock (visualOwners)
		{
			if (owner != null && visualOwners.TryGetValue(owner, out var value) && value == this)
			{
				visualOwners.Remove(owner);
			}
		}
	}

	protected override void OnBarUpdate()
	{
		try
		{
			lock (recoveryStateGate)
			{
				ProcessBarUpdate();
			}
		}
		catch (Exception ex)
		{
			// Diagnostic: make the exception text visible in NinjaScript Output before it propagates to the platform.
			Print("[RBE] OnBarUpdate exception in " + State + " bar=" + CurrentBars[0] + ": " + ex.GetType().Name + ": " + ex.Message);
			Print(ex.StackTrace ?? "(no stack)");
			throw;
		}
	}

	private void ProcessBarUpdate()
	{
		if (model == null)
		{
			if (State == State.Historical && BarsInProgress == executionSeries && !nullModelNoticed)
			{
				nullModelNoticed = true;
				Print("[RBE] Historical bars arrived but the model is not initialised (DataLoaded did not finish). No trades are processed.");
			}
			return;
		}
		if ((recoveryAccountMode && State == State.Historical) || (BarsInProgress == executionSeries && BootstrapRecoveryMinute()))
		{
			if (State == State.Historical && BarsInProgress == executionSeries && !bootstrapNoticed)
			{
				bootstrapNoticed = true;
				Print("[RBE] Historical bars skipped by the recovery gate (recoveryAccountMode=" + recoveryAccountMode + "). No trades are processed in this run.");
			}
			return;
		}
		if (BarsInProgress == 0)
		{
			Paint();
		}
		if (BarsInProgress == executionSeries && CurrentBars[executionSeries] >= 0 && State == State.Historical)
		{
			processedMinutes++;
			if (processedMinutes == 1 || processedMinutes % 5000 == 0)
			{
				if (processedMinutes == 1 || processedMinutes % 500000 == 0) Print("[RBE] Historical minute " + processedMinutes + " at " + Times[executionSeries][0].ToString("yyyy-MM-dd HH:mm") + " (server time)");
				Log("PROGRESS", 0, 0, 0.0, "MINUTES=" + processedMinutes + ";SECONDS=" + ((double)(Stopwatch.GetTimestamp() - startedAt) / (double)Stopwatch.Frequency).ToString("0.000", CultureInfo.InvariantCulture), Times[executionSeries][0]);
			}
			DateTime time = Times[executionSeries][0].AddMinutes(-1.0);
			netHistoricalBarTime = Times[executionSeries][0];
			netHistoricalQuoteReplay = true;
			try
			{
				ProcessQuote(time, Opens[executionSeries][0]);
				bool flag = false;
				ProcessQuote(time.AddSeconds(20.0), flag ? Lows[executionSeries][0] : Highs[executionSeries][0]);
				ProcessQuote(time.AddSeconds(40.0), flag ? Highs[executionSeries][0] : Lows[executionSeries][0]);
				ProcessQuote(time.AddSeconds(59.0), Closes[executionSeries][0]);
			}
			finally
			{
				netHistoricalQuoteReplay = false;
			}
			DriveNetExposure();
			SaveRecovery();
		}
	}

	private bool NetHistoricalSubmissionStopValid(int sign, double stop)
	{
		if (State != State.Historical)
		{
			return true;
		}
		if (netHistoricalBarTime == DateTime.MinValue)
		{
			return false;
		}
		int num = CurrentBars[executionSeries];
		if (num < 0 || num >= BarsArray[executionSeries].Count)
		{
			return false;
		}
		int bar = BarsArray[executionSeries].GetBar(netHistoricalBarTime);
		if (bar < 0 || bar >= BarsArray[executionSeries].Count)
		{
			return false;
		}
		return RbeHistory.CanSubmitNativeStop(sign, stop, BarsArray[executionSeries].GetHigh(num), BarsArray[executionSeries].GetLow(num), BarsArray[executionSeries].GetHigh(bar), BarsArray[executionSeries].GetLow(bar));
	}

	private void LogNativeStopContext(int sign, int quantity, double stop)
	{
		if (audit != null && State == State.Historical)
		{
			int num = CurrentBars[executionSeries];
			int bar = BarsArray[executionSeries].GetBar(netHistoricalBarTime);
			if (num >= 0 && bar >= 0 && num < BarsArray[executionSeries].Count && bar < BarsArray[executionSeries].Count)
			{
				Log("NET_STOP_CONTEXT", sign, quantity, stop, string.Format(CultureInfo.InvariantCulture, "CURRENT={0:O};HIGH={1};LOW={2};PROCESSING={3:O};HIGH={4};LOW={5};TICK={6}", BarsArray[executionSeries].GetTime(num), BarsArray[executionSeries].GetHigh(num), BarsArray[executionSeries].GetLow(num), BarsArray[executionSeries].GetTime(bar), BarsArray[executionSeries].GetHigh(bar), BarsArray[executionSeries].GetLow(bar), TickSize));
			}
		}
	}

	protected override void OnMarketData(MarketDataEventArgs update)
	{
		if (State != State.Realtime || model == null || update.MarketDataType != MarketDataType.Last)
		{
			return;
		}
		lock (recoveryStateGate)
		{
			ProcessQuote(update.Time, update.Price);
		}
	}

	private void ProcessQuote(DateTime time, double price)
	{
		PollLiveRecovery();
		if (!LiveRecoveryReady())
		{
			return;
		}
		latestTime = time;
		latestNy = RbeModel.ToNewYork(latestTime, platformZone);
		last = price;
		if (State == State.Realtime)
		{
			NewsGuard(DateTime.UtcNow);
		}
		bid = ((State == State.Historical) ? last : GetCurrentBid(executionSeries));
		ask = ((State == State.Historical) ? last : GetCurrentAsk(executionSeries));
		if (bid <= 0.0)
		{
			bid = last;
		}
		if (ask <= 0.0)
		{
			ask = last;
		}
		// A new trading day with exposure still open settles that exposure first and defers the new session. Realtime always did this;
		// historical replay used to fail the whole run at the roll (NET_ERROR Prior session has unsettled owned exposure or orders).
		if ((State == State.Realtime || State == State.Historical) && model.TradingDate != DateTime.MinValue && RbeModel.DayKey(latestNy) != model.TradingDate && (netBook.Active || netActual != 0 || (State == State.Historical && NetOrdersPending())))
		{
			if (State == State.Historical)
			{
				rollSettleQuotes++;
				if (rollSettleQuotes == 1)
				{
					Print("[RBE] Session roll at " + latestNy.ToString("yyyy-MM-dd HH:mm") + " NY with an unsettled prior session; settling it before the new session. " + NetStateText());
				}
				if (rollSettleQuotes > 240)
				{
					NetFail("Prior session could not be settled at the session roll after 240 quotes (" + NetStateText() + ")");
					return;
				}
			}
			netCutoff = true;
			BeginNetClose();
			Drive();
			SaveRecovery();
			return;
		}
		if (model.TradingDate != DateTime.MinValue && RbeModel.DayKey(latestNy) != model.TradingDate)
		{
			rangeVisual.EndDay();
			PaintRange();
			if (rangeVisual.High > rangeVisual.Low)
			{
				completedRanges.Add(rangeVisual.Snapshot());
			}
			while (completedRanges.Count > 2)
			{
				RbeRangeVisual rbeRangeVisual = completedRanges[0];
				completedRanges.RemoveAt(0);
				string text = owner + "_" + rbeRangeVisual.Day.ToString("yyyyMMdd");
				string[] array = new string[3] { "_BOX", "_HI", "_LO" };
				foreach (string text2 in array)
				{
					RemoveDrawObject(text + text2);
				}
			}
			historicalVisualsPainted = false;
		}
		double high = model.High;
		double low = model.Low;
		bool flag = model.OnQuote(latestNy, last);
		if (flag)
		{
			NewNetSession();
			sessionBuyFills = (sessionSellFills = 0);
			buyTouched = (sellTouched = false);
			skipRealtimeSession = false;
			rangeTag = owner + "_" + model.TradingDate.ToString("yyyyMMdd");
			PruneCustomExecutions();
			Log("SESSION", 0, 0, 0.0, "RESET");
		}
		DateTime highTouch = rangeVisual.HighTouch;
		DateTime lowTouch = rangeVisual.LowTouch;
		rangeVisual.Observe(model, latestTime, latestNy, last);
		visualReplay.Observe(model, rangeVisual, latestTime, latestNy, last);
		DateTime dateTime = new DateTime(latestTime.Year, latestTime.Month, latestTime.Day, latestTime.Hour, latestTime.Minute, 0);
		if (flag || dateTime != visualPulse || high != model.High || low != model.Low || highTouch != rangeVisual.HighTouch || lowTouch != rangeVisual.LowTouch)
		{
			visualPulse = dateTime;
			PaintRange();
		}
		if (State == State.Historical && !IsInStrategyAnalyzer && !RbeHistory.CanReplayCompletedSession(model.TradingDate, historicalEndNy))
		{
			if (!buyTouched && rangeVisual.HighTouch != DateTime.MinValue)
			{
				historicalIncompleteTouches++;
			}
			if (!sellTouched && rangeVisual.LowTouch != DateTime.MinValue)
			{
				historicalIncompleteTouches++;
			}
			buyTouched = buyTouched || rangeVisual.HighTouch != DateTime.MinValue;
			sellTouched = sellTouched || rangeVisual.LowTouch != DateTime.MinValue;
		}
		else
		{
			if (State == State.Realtime && firstRealtimeQuote)
			{
				firstRealtimeQuote = false;
				skipRealtimeSession = false;
				Log("START", 0, 0, 0.0, "REPLAYED_SIDES_CONSUMED;LIVE_UNTOUCHED_SIDES_ARMED");
			}
			ProcessNetQuote();
			SaveRecovery();
		}
	}

	private bool BrokerReady()
	{
		return State != State.Realtime || (Account != null && Account.ConnectionStatus == ConnectionStatus.Connected);
	}

	private void GuardOwnedRestart()
	{
		if (IsInStrategyAnalyzer || Account == null || Id <= 0)
		{
			return;
		}
		lock (restartOwners)
		{
			if (restartOwners.TryGetValue(Id, out var value) && value.Account == Account)
			{
				bool flag = recoveryRecord != null && recoveryRecord.RetiredOwners.Contains(value.Prefix);
				if (value.InternalBooksActive && !flag)
				{
					throw new InvalidOperationException("RBE restart blocked: this instance has active internal net books, even if the broker is flat. Keep the original executor running until both books finish.");
				}
				lock (Account.Orders)
				{
					foreach (Order order in Account.Orders)
					{
						if (RbeHistory.IsRestartOwnedOrder(value.Prefix, order.Name, order.FromEntrySignal, !Terminal(order.OrderState)) && (!flag || order.OrderState != OrderState.Unknown))
						{
							throw new InvalidOperationException("RBE restart blocked: this instance still has a working owned order. Keep the original strategy running until flat; restarting ImmediatelySubmit could cancel its protective stop. Other chart instances are not adopted.");
						}
					}
				}
			}
			restartOwners[Id] = new RestartOwner
			{
				Account = Account,
				Prefix = owner
			};
		}
	}

	private DateTime SessionClockNy()
	{
		if (State != State.Realtime)
		{
			return latestNy;
		}
		if (IsPlayback)
		{
			return RbeModel.ToNewYork(Connection.PlaybackConnection.Now, platformZone);
		}
		return RbeModel.ToNewYork(DateTime.UtcNow, TimeZoneInfo.Utc);
	}

	private double Cost()
	{
		return RoundTripCommission + (double)(2 * AssumedSlipTicks) * TickSize * Instrument.MasterInstrument.PointValue;
	}

	private double Distance(int side)
	{
		double num = ((side == 1) ? RbeModel.Up(model.High, TickSize) : RbeModel.Down(model.Low, TickSize));
		return Math.Abs(num - model.InitialStop(side == 1, TickSize));
	}

	// Strict modeled risk returns zero contracts when one contract's stop risk plus costs exceeds the cash budget.
	// That skip used to be silent (counter and audit file only), so a run on an oversized contract looked like it did nothing.
	private void ReportRiskSkip(int side, double entryLevel)
	{
		if (riskSkipReports >= 5)
		{
			return;
		}
		riskSkipReports++;
		double stopPoints = Distance(side);
		double perContract = stopPoints * Instrument.MasterInstrument.PointValue + Cost();
		Print("[RBE] RISK SKIP " + (side == 1 ? "long" : "short") + " at " + entryLevel.ToString("0.00", CultureInfo.InvariantCulture)
			+ " on " + Instrument.MasterInstrument.Name + ": one contract risks $" + perContract.ToString("0", CultureInfo.InvariantCulture)
			+ " (stop " + stopPoints.ToString("0.0", CultureInfo.InvariantCulture) + " pts x $" + Instrument.MasterInstrument.PointValue.ToString("0.##", CultureInfo.InvariantCulture)
			+ " + $" + Cost().ToString("0.00", CultureInfo.InvariantCulture) + " costs) against a $" + RiskMoney.ToString("0", CultureInfo.InvariantCulture)
			+ " budget; strict risk skips the trade. Use a smaller contract (MGC) or raise Risk."
			+ (riskSkipReports == 5 ? " Further skips are counted but not printed." : ""));
	}

	// Fixed contract mode ignores the risk budget, strict risk and the contract cap for sizing; the cap used by the executor's
	// safety checks is raised to at least the fixed quantity so a deliberate fixed size is never reported as a cap breach.
	private int EffectiveMaxContracts
	{
		get { return UseFixedContract ? Math.Max(MaxContracts, FixedContracts) : MaxContracts; }
	}

	private int QuantityFor(int side)
	{
		if (UseFixedContract)
		{
			return FixedContracts;
		}
		return RbeModel.Quantity(0.0, Distance(side), Instrument.MasterInstrument.PointValue, Cost(), RiskMoney, MaxContracts, EnforceRiskLimit);
	}

	private static bool Terminal(OrderState state)
	{
		return state == OrderState.Filled || state == OrderState.Cancelled || state == OrderState.Rejected;
	}

	private bool Owns(Order order)
	{
		return order != null && (ownedEntrySignals.Contains(order.Name) || ownedEntrySignals.Contains(order.FromEntrySignal));
	}

	private bool HasWorkingOwnedOrders()
	{
		foreach (OwnedOrder value in orders.Values)
		{
			if (!Terminal(value.State))
			{
				return true;
			}
		}
		return false;
	}

	private void Drive()
	{
		DriveNetExposure();
	}

	protected override void OnOrderUpdate(Order order, double limitPrice, double stopPrice, int quantity, int filled, double averageFillPrice, OrderState orderState, DateTime time, ErrorCode error, string comment)
	{
		lock (recoveryStateGate)
		{
			ProcessOrderUpdate(order, limitPrice, stopPrice, quantity, filled, averageFillPrice, orderState, time, error, comment);
		}
	}

	private void ProcessOrderUpdate(Order order, double limitPrice, double stopPrice, int quantity, int filled, double averageFillPrice, OrderState orderState, DateTime time, ErrorCode error, string comment)
	{
		if (!RecoveryOrderCallback(order, error))
		{
			NetOrderUpdate(order, quantity, stopPrice, filled, orderState, time, error, comment);
		}
	}

	protected override void OnExecutionUpdate(Execution execution, string executionId, double price, int quantity, MarketPosition marketPosition, string orderId, DateTime time)
	{
		lock (recoveryStateGate)
		{
			ProcessExecutionUpdate(execution, executionId, price, quantity, marketPosition, orderId, time);
		}
	}

	private void ProcessExecutionUpdate(Execution execution, string executionId, double price, int quantity, MarketPosition marketPosition, string orderId, DateTime time)
	{
		if (execution == null || !RecoveryExecutionCallback(execution, quantity))
		{
			NetExecutionUpdate(execution, executionId, price, quantity, time);
		}
	}

	private void Log(string evt, int side, int quantity, double price, string reason, DateTime? eventTime = null, DateTime? tradingDate = null)
	{
		if (audit == null)
		{
			return;
		}
		try
		{
			DateTime dateTime = eventTime ?? latestTime;
			DateTime dateTime2 = (eventTime.HasValue ? RbeModel.ToNewYork(dateTime, platformZone) : latestNy);
			RbeNetLeg rbeNetLeg = ((netBook == null) ? null : (side switch
			{
				-1 => netBook.Short, 
				1 => netBook.Long, 
				_ => null, 
			}));
			double num = ((rbeNetLeg != null && rbeNetLeg.Protection != null) ? rbeNetLeg.Protection.Stop : 0.0);
			audit.WriteLine(string.Format(CultureInfo.InvariantCulture, "{0},{1},{2:O},{3:O},{4:yyyy-MM-dd},{5:F5},{6:F5},{7:F5},{8:F5},{9},{10},{11:F5},{12:F5},{13}", owner, evt, dateTime, dateTime2, tradingDate ?? ((model == null) ? dateTime2.Date : model.TradingDate), (model == null) ? 0.0 : model.High, (model == null) ? 0.0 : model.Low, bid, ask, side, quantity, price, num, reason.Replace(',', ';').Replace('\n', ' ').Replace('\r', ' ')));
		}
		catch (IOException ex)
		{
			Print("[" + owner + "] Audit unavailable: " + ex.Message);
			audit.Dispose();
			audit = null;
		}
	}

	private void Paint()
	{
		if (!ShowVisuals || visualFault || ChartControl == null || model == null)
		{
			return;
		}
		try
		{
			PaintCore();
		}
		catch (Exception ex)
		{
			visualFault = true;
			Print("[" + owner + "] Visuals unavailable: " + ex.Message);
		}
	}

	private void BeginNewsFetch()
	{
		if (NewsImpact == RbeNewsImpact.Off || State != State.Realtime || IsPlayback)
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
				Print("[" + owner + "] ForexFactory unavailable; entries blocked: " + ex.Message);
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
			DateTime dateTime2 = TimeZoneInfo.ConvertTimeFromUtc(utcDateTime, NewsZone);
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
		DateTime dateTime = TimeZoneInfo.ConvertTimeFromUtc(utc, NewsZone);
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
		return NewsImpact == RbeNewsImpact.All || (text2 == "HIGH" && NewsImpact >= RbeNewsImpact.Red) || (text2 == "MEDIUM" && NewsImpact == RbeNewsImpact.RedYellow);
	}

	private void NewsGuard(DateTime utcNow)
	{
		if (IsPlayback)
		{
			newsBlocked = false;
		}
		else
		{
			if (NewsImpact == RbeNewsImpact.Off || State != State.Realtime)
			{
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
			if (flag)
			{
				NewsEvent[] array2 = array;
				foreach (NewsEvent newsEvent2 in array2)
				{
					if (NewsImpactAllowed(newsEvent2) && utcNow >= newsEvent2.Utc.AddSeconds(-num) && utcNow <= newsEvent2.Utc.AddSeconds(num))
					{
						newsEvent = newsEvent2;
						break;
					}
				}
			}
			bool flag2 = !flag || newsEvent != null;
			if (flag2)
			{
				NetNewsGuard(newsEvent != null, newsEvent != null && utcNow < newsEvent.Utc);
			}
			if (flag2 != newsBlocked)
			{
				Log(flag2 ? "NEWS_START" : "NEWS_END", 0, 0, 0.0, (newsEvent == null) ? "FEED_UNAVAILABLE" : newsEvent.Title);
			}
			if (flag2 != newsBlocked)
			{
				ref string reference = ref status;
				string text;
				if (flag2)
				{
					text = ((newsEvent == null) ? "News feed unavailable: entries blocked" : "News blackout");
				}
				else
				{
					text = "News cleared";
				}
				reference = text;
			}
			newsBlocked = flag2;
		}
	}

	private double EffectiveNewsCost()
	{
		double num = ((newsObservedQuantity > 0.0) ? (newsObservedCommission / newsObservedQuantity) : RoundTripCommission);
		return num + (double)(2 * AssumedSlipTicks) * TickSize * Instrument.MasterInstrument.PointValue;
	}

	private bool HasUpcomingSessionNews(DateTime fillTime)
	{
		if (IsPlayback || !NewsCostCoveredBE || NewsFlattenBefore || NewsImpact == RbeNewsImpact.Off)
		{
			return false;
		}
		DateTime dateTime = TimeZoneInfo.ConvertTimeToUtc(DateTime.SpecifyKind(fillTime, DateTimeKind.Unspecified), platformZone);
		DateTime dateTime2 = TimeZoneInfo.ConvertTimeToUtc(model.TradingDate.AddHours(11.0).AddMinutes(55.0), NewsZone);
		lock (newsLock)
		{
			if (!NewsSnapshotValid(DateTime.UtcNow))
			{
				return false;
			}
			NewsEvent[] array = newsEvents;
			foreach (NewsEvent newsEvent in array)
			{
				if (NewsImpactAllowed(newsEvent) && newsEvent.Utc > dateTime && TimeZoneInfo.ConvertTimeFromUtc(newsEvent.Utc, NewsZone).Date == model.TradingDate && newsEvent.Utc.AddSeconds((0 - NewsWindow) * 30) < dateTime2)
				{
					return true;
				}
			}
		}
		return false;
	}

	private string DashboardStatus()
	{
		if (recoveryAccountMode && recoveryBooting)
		{
			return status;
		}
		if (executionFailed || newsBlocked)
		{
			return status;
		}
		if (model.Locked && !model.RangeAccepted && model.High > model.Low && model.Low > 0.0)
		{
			return "Range filtered: " + (100.0 * (model.High - model.Low) / model.High).ToString("0.00") + "%";
		}
		if (model.Locked && model.RangeAccepted)
		{
			return "Buy trades: " + sessionBuyFills + "   Sell trades: " + sessionSellFills;
		}
		return status;
	}

	private void UpdatePanelClock(object unused)
	{
		if (State != State.Realtime)
		{
			return;
		}
		try
		{
			TriggerCustomEvent((object o) =>
			{
				lock (recoveryStateGate)
				{
					if (State == State.Realtime && model != null)
					{
						PollLiveRecovery();
						if (recoveryBooting)
						{
							Paint();
							RequestDashboardRender();
						}
						else
						{
							NewsGuard(DateTime.UtcNow);
							DateTime ny = SessionClockNy();
							if (RbeHistory.SubmitCutoff(model.TradingDate, ny, historical: false))
							{
								netCutoff = true;
								NetLiquidationQuotes();
								BeginNetClose();
								status = ((netActual != 0 || netBook.Active) ? "Closing owned position" : "Session complete");
								Drive();
							}
							Paint();
							RequestDashboardRender();
							SaveRecovery();
						}
					}
				}
			}, null);
		}
		catch (InvalidOperationException)
		{
		}
	}

	private void PaintCore()
	{
		if (!historicalVisualsPainted && State != State.Historical)
		{
			foreach (RbeRangeVisual completedRange in completedRanges)
			{
				PaintRange(completedRange);
			}
			foreach (RbeTradeVisual closedVisual in closedVisuals)
			{
				DrawTrade(closedVisual, closedVisual.ExitTime);
			}
			HashSet<string> hashSet = new HashSet<string>();
			foreach (IDrawingTool drawObject in DrawObjects)
			{
				if (drawObject != null)
				{
					hashSet.Add(drawObject.Tag);
				}
			}
			historicalVisualsPainted = true;
			foreach (RbeTradeVisual closedVisual2 in closedVisuals)
			{
				if (!TradeVisualRegistered(closedVisual2, hashSet))
				{
					historicalVisualsPainted = false;
					break;
				}
			}
			foreach (RbeRangeVisual completedRange2 in completedRanges)
			{
				if (!hashSet.Contains(owner + "_" + completedRange2.Day.ToString("yyyyMMdd") + "_BOX"))
				{
					historicalVisualsPainted = false;
				}
			}
		}
		PaintReplay();
		DateTime ny = SessionClockNy();
		if (dashboard != null)
		{
			dashboard.Publish(new RbeDashState
			{
				Clock = ny.ToString("HH:mm:ss"),
				Mode = DashboardMode(ny),
				Status = DashboardStatus(),
				RangeHigh = ((model.High > 0.0) ? model.High.ToString("0.00") : "--"),
				RangeLow = ((model.Low > 0.0) ? model.Low.ToString("0.00") : "--"),
				RangeWidth = ((model.High > model.Low && model.Low > 0.0) ? (model.High - model.Low).ToString("0.00") : "--"),
				Position = NetPositionText(),
				Stop = NetStopText(),
				Risk = UseFixedContract ? "Fixed contract  " + FixedContracts : "Risk budget  $" + RiskMoney.ToString("0.00"),
				Costs = NetCostText(),
				History = "History " + historicalEntries + " fills  ·  " + historicalRiskSkips + " risk skips  ·  11:55 exit",
				InTrade = (netBook.Active || netActual != 0),
				NewsBlocked = newsBlocked
			});
		}
		PaintRange();
		PaintNetTrades();
	}

	private string DashboardMode(DateTime ny)
	{
		if (netBook.Active)
		{
			return (netActual == 0) ? "NETTED BOOKS" : "LIVE NET TRADE";
		}
		if (model == null || model.TradingDate == DateTime.MinValue)
		{
			return "WAITING FOR RANGE";
		}
		if (ny >= model.TradingDate.AddHours(11.0).AddMinutes(55.0) || executionFailed)
		{
			return "SESSION CLOSED";
		}
		if (ny < model.RangeStart)
		{
			return "WAITING FOR RANGE";
		}
		if (ny < model.RangeEnd || !model.Locked)
		{
			return "RANGE FORMING";
		}
		if (!model.RangeAccepted)
		{
			return "RANGE FILTERED";
		}
		if ((MaxBuy > 0 && !buyTouched) || (MaxSell > 0 && !sellTouched))
		{
			return "ARMED";
		}
		return "LEVELS CONSUMED";
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
			EnableNativeExecutionDisplay();
			HookDashboardMouse(attach: true);
			dashboard.Render(RenderTarget, chartControl);
		}
		catch (Exception ex)
		{
			if (!dashboardFaultLogged)
			{
				dashboardFaultLogged = true;
				Print("[RBE] Dashboard render unavailable: " + ex.Message);
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
				if (dashboard.MouseDown((float)point.X, (float)point.Y))
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
			if (chartControl == null || dashboard == null)
			{
				return;
			}
			if (!ShowVisuals || State == State.Terminated || e.LeftButton != MouseButtonState.Pressed)
			{
				dashboard.MouseUp();
				return;
			}
			Point point = DashboardPoint(chartControl, e.GetPosition(chartControl));
			if (dashboard.MouseMove((float)point.X, (float)point.Y))
			{
				e.Handled = true;
				chartControl.InvalidateVisual();
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
			if (dashboard != null && dashboard.MouseUp() && ChartControl != null)
			{
				e.Handled = true;
				ChartControl.InvalidateVisual();
			}
		}
		catch (Exception)
		{
		}
	}

	private void PaintRange()
	{
		PaintRange(rangeVisual);
	}

	private void PaintRange(RbeRangeVisual range)
	{
		if (ShowVisuals && range != null && !(range.High <= range.Low))
		{
			string text = owner + "_" + range.Day.ToString("yyyyMMdd");
			RbeVisuals.DrawRangeBox(this, text + "_BOX", range.Left, range.Right, range.High, range.Low, RbeVisuals.ClrRangeBoxNY, 75);
			PaintLevel(text + "_HI", range.ShowHigh, range.HighFormed, range.HighTouch, range.High, range.Now);
			PaintLevel(text + "_LO", range.ShowLow, range.LowFormed, range.LowTouch, range.Low, range.Now);
		}
	}

	private void PaintLevel(string tag, bool show, DateTime formed, DateTime touch, double price, DateTime now)
	{
		if (!show)
		{
			RemoveDrawObject(tag);
		}
		else if (touch != DateTime.MinValue)
		{
			RbeVisuals.DrawBoundedLine(this, tag, formed, price, (touch < formed) ? formed : touch, price, RbeVisuals.ClrEntryLine, DashStyleHelper.Solid, 2);
		}
		else
		{
			RbeVisuals.DrawPendingLine(this, tag, price, formed, now);
		}
	}

	private static string VisualKey(DateTime day, int side)
	{
		return day.ToString("yyyyMMdd") + ":" + side;
	}

	private bool VisibleSession(DateTime day)
	{
		if (day == model.TradingDate)
		{
			return true;
		}
		foreach (RbeRangeVisual completedRange in completedRanges)
		{
			if (completedRange.Day == day)
			{
				return true;
			}
		}
		return false;
	}

	private void PruneCustomExecutions()
	{
		foreach (RbeTradeVisual closedVisual in closedVisuals)
		{
			if (!VisibleSession(closedVisual.Day))
			{
				RemoveExecutionVisual(closedVisual.Tag);
			}
		}
		foreach (RbeTradeVisual trade in visualReplay.Trades)
		{
			if (!VisibleSession(trade.Day))
			{
				RemoveExecutionVisual(trade.Tag);
			}
		}
		closedVisuals.RemoveAll((RbeTradeVisual trade) => !VisibleSession(trade.Day));
		visualReplay.Trades.RemoveAll((RbeTradeVisual trade) => !VisibleSession(trade.Day));
	}

	private void RemoveExecutionVisual(string tag)
	{
		string[] array = new string[5] { "_ENT", "_ENTRY", "_SL", "_TP", "_TRAIL" };
		foreach (string text in array)
		{
			RemoveDrawObject(tag + text);
		}
		paintedReplay.Remove(tag);
	}

	private void EnableNativeExecutionDisplay()
	{
		ChartControl chart = ChartControl;
		ChartBars bars = ChartBars;
		if (nativeDisplayQueued || chart == null || bars == null)
		{
			return;
		}
		nativeDisplayQueued = true;
		chart.Dispatcher.InvokeAsync(() =>
		{
			if (State == State.Terminated)
			{
				return;
			}
			try
			{
				bars.Properties.PlotExecutions = ChartExecutionStyle.MarkersOnly;
				bars.Properties.ShowTradeLines = true;
				chart.InvalidateVisual();
			}
			catch (Exception ex)
			{
				nativeDisplayQueued = false;
				Print("[RBE] Native execution display unavailable: " + ex.Message);
			}
		});
	}

	private void RemoveSyntheticVisual(DateTime day, int side)
	{
		string text = owner + "_SYN_" + day.ToString("yyyyMMdd") + ((side == 1) ? "_L" : "_S");
		string[] array = new string[5] { "_ENT", "_ENTRY", "_SL", "_TP", "_TRAIL" };
		foreach (string text2 in array)
		{
			RemoveDrawObject(text + text2);
		}
	}

	private void PaintReplay()
	{
		foreach (RbeTradeVisual trade in visualReplay.Trades)
		{
			if (!nativeVisualKeys.Contains(VisualKey(trade.Day, trade.Side)) && !paintedReplay.Contains(trade.Tag))
			{
				DrawTrade(trade, (trade.Day == model.TradingDate) ? LiveRight(trade) : trade.ObservedTime);
			}
		}
		HashSet<string> hashSet = new HashSet<string>();
		foreach (IDrawingTool drawObject in DrawObjects)
		{
			if (drawObject != null)
			{
				hashSet.Add(drawObject.Tag);
			}
		}
		foreach (RbeTradeVisual trade2 in visualReplay.Trades)
		{
			if (trade2.ExitTime != DateTime.MinValue && TradeVisualRegistered(trade2, hashSet))
			{
				paintedReplay.Add(trade2.Tag);
			}
		}
	}

	private static bool TradeVisualRegistered(RbeTradeVisual trade, HashSet<string> visible)
	{
		if (!visible.Contains(trade.Tag + "_ENTRY"))
		{
			return false;
		}
		double num = (double)trade.Side * (trade.ExitPrice - trade.Entry);
		if (!trade.Trailing && (trade.ExitTime == DateTime.MinValue || num != 0.0) && !visible.Contains(trade.Tag + "_SL"))
		{
			return false;
		}
		if (trade.ExitTime != DateTime.MinValue && num > 0.0 && !visible.Contains(trade.Tag + "_TP"))
		{
			return false;
		}
		return true;
	}

	private void PurgeStaleVisuals()
	{
		ChartControl chart = ChartControl;
		if (chart == null)
		{
			return;
		}
		chart.Dispatcher.InvokeAsync(() =>
		{
			try
			{
				List<DrawingTool> list = new List<DrawingTool>();
				foreach (IChartObject chartObject in chart.ChartObjects)
				{
					DrawingTool drawingTool = chartObject as DrawingTool;
					string text = drawingTool?.Tag;
					if (!string.IsNullOrEmpty(text) && text.Length >= 37 && text.StartsWith("RBE"))
					{
						string text2 = text.Substring(0, 35);
						if (Guid.TryParseExact(text2.Substring(3), "N", out var _))
						{
							string text3 = text.Substring(35);
							if (text3 == "_PANEL" || text3.EndsWith("_BOX") || text3.EndsWith("_HI") || text3.EndsWith("_LO") || text3.StartsWith("_EXEC_") || text3.StartsWith("_SYN_") || text3.StartsWith("_FILL_") || text3 == "_STOP")
							{
								lock (visualOwners)
								{
									if (visualOwners.ContainsKey(text2))
									{
										continue;
									}
								}
								list.Add(drawingTool);
							}
						}
					}
				}
				foreach (DrawingTool item in list)
				{
					chart.ChartObjects.Remove(item);
				}
				if (list.Count > 0)
				{
					chart.InvalidateVisual();
				}
			}
			catch
			{
			}
		});
	}

	private DateTime AddPrimaryBars(DateTime time, int count)
	{
		if (BarsPeriod.BarsPeriodType == BarsPeriodType.Minute)
		{
			return time.AddMinutes(count * BarsPeriod.Value);
		}
		if (BarsPeriod.BarsPeriodType == BarsPeriodType.Second)
		{
			return time.AddSeconds(count * BarsPeriod.Value);
		}
		if (BarsPeriod.BarsPeriodType == BarsPeriodType.Day)
		{
			return time.AddDays(count * BarsPeriod.Value);
		}
		return (latestTime > time) ? latestTime : time;
	}

	private DateTime LiveRight(RbeTradeVisual trade)
	{
		DateTime initial = AddPrimaryBars(trade.EntryTime, 3).AddSeconds(-1.0);
		DateTime live = AddPrimaryBars(latestTime, 2).AddSeconds(-1.0);
		try
		{
			int bar = BarsArray[0].GetBar(trade.EntryTime);
			int num = CurrentBars[0];
			if (bar >= 0)
			{
				initial = AddPrimaryBars(BarsArray[0].GetTime(bar), 2).AddSeconds(-1.0);
			}
			if (num >= 0)
			{
				DateTime dateTime = BarsArray[0].GetTime(num);
				TimeSpan timeSpan = AddPrimaryBars(dateTime, 1) - dateTime;
				if (timeSpan.Ticks > 0 && latestTime >= dateTime)
				{
					dateTime = dateTime.AddTicks(((latestTime - dateTime).Ticks / timeSpan.Ticks + 1) * timeSpan.Ticks);
				}
				live = AddPrimaryBars(dateTime, 1).AddSeconds(-1.0);
			}
		}
		catch (ArgumentOutOfRangeException)
		{
		}
		return trade.AdvanceRight(initial, live);
	}

	private void DrawTrade(RbeTradeVisual trade, DateTime right)
	{
		if (ShowVisuals && trade != null && !string.IsNullOrEmpty(trade.Tag) && VisibleSession(trade.Day))
		{
			bool flag = trade.ExitTime != DateTime.MinValue;
			if (flag)
			{
				right = trade.ExitTime;
			}
			double num = ((trade.InitialStop > 0.0) ? trade.InitialStop : trade.Stop);
			double num2 = (double)trade.Side * (trade.ExitPrice - trade.Entry);
			double slPx = num;
			if (flag && num2 <= 0.0)
			{
				slPx = trade.ExitPrice;
			}
			double tpPx = ((flag && num2 > 0.0) ? trade.ExitPrice : 0.0);
			RbeVisuals.DrawExecutionTool(this, trade.Tag, trade.Side == 1, trade.Entry, slPx, tpPx, trade.Level, trade.LevelTime, trade.EntryTime, right, trailing: false, DateTime.MinValue, trade.Synthetic);
			if (trade.Trailing)
			{
				RbeVisuals.DrawBoundedLine(this, trade.Tag + "_TRAIL", trade.TrailStart, trade.Stop, right, trade.Stop, RbeVisuals.ClrTrailingStop, DashStyleHelper.Dot, 2);
			}
		}
	}

	private void InitializeNetExposure()
	{
		netActual = (netCloseQuantity = 0);
		netCloseValue = 0.0;
		netCutoff = (netSubmitting = (netClosing = (netReconciling = false)));
		netHistoricalQuoteReplay = (netLongReady = (netShortReady = false));
		netHistoricalBarTime = DateTime.MinValue;
		netMarket = null;
		netIntents = new Dictionary<string, NetIntent>();
		netSessionIntents = new List<NetIntent>();
		netBook = new RbeNetBook(settings, TickSize, Instrument.MasterInstrument.PointValue, Cost());
		netBook.Opened += NetLegOpened;
		netBook.Closed += NetLegClosed;
	}

	private void GuardNetActivation()
	{
		if (Account == null)
		{
			return;
		}
		lock (visualOwners)
		{
			foreach (RangeBreakoutNT8 value in visualOwners.Values)
			{
				if (value != this && value.State == State.Realtime && value.Account == Account && value.Instrument.FullName == Instrument.FullName && value.TradeDirection == TradeDirection)
				{
					throw new InvalidOperationException("RBE recovery key already has an active executor on this account/contract/mode/direction.");
				}
			}
		}
	}

	private void HistoricalEntryIgnored(RbeNetLeg leg, double stop, string name, NetIntent intent)
	{
		historicalIgnoredEntries++;
		netIntents.Remove(name);
		ownedEntrySignals.Remove(name);
		netSessionIntents.Remove(intent);
		if (leg.Side == 1)
		{
			buyTouched = true;
		}
		else
		{
			sellTouched = true;
		}
		if (historicalIgnoredEntries <= 10)
		{
			int cur = CurrentBars[executionSeries];
			int prev = Math.Max(0, cur - 1);
			NinjaTrader.Data.Bars bars = BarsArray[executionSeries];
			Print("[RBE] Historical entry ignored by NinjaTrader at " + latestNy.ToString("yyyy-MM-dd HH:mm") + " NY: " + (leg.Side == 1 ? "buy" : "sell") + " stop " + stop.ToString("0.0###", CultureInfo.InvariantCulture)
				+ "; bar high/low/close " + bars.GetHigh(cur).ToString("0.0###", CultureInfo.InvariantCulture) + "/" + bars.GetLow(cur).ToString("0.0###", CultureInfo.InvariantCulture) + "/" + bars.GetClose(cur).ToString("0.0###", CultureInfo.InvariantCulture)
				+ "; previous bar high/low " + bars.GetHigh(prev).ToString("0.0###", CultureInfo.InvariantCulture) + "/" + bars.GetLow(prev).ToString("0.0###", CultureInfo.InvariantCulture)
				+ "; range " + model.Low.ToString("0.0###", CultureInfo.InvariantCulture) + "-" + model.High.ToString("0.0###", CultureInfo.InvariantCulture)
				+ ". The level is treated as already crossed for this session; no trade is taken on this side.");
		}
	}

	private string NetStateText()
	{
		string pending = string.Empty;
		foreach (NetIntent item in netSessionIntents)
		{
			if (item.Tracked != null && NetPending(item.Tracked))
			{
				pending += (pending.Length > 0 ? "," : string.Empty) + item.Role + ":" + (item.Tracked.Order != null ? item.Tracked.Order.Name : "?") + ":" + item.Tracked.State;
			}
		}
		return string.Format(CultureInfo.InvariantCulture, "netActual={0} longActive={1} shortActive={2} closing={3} reconciling={4} submitting={5} cutoff={6} market={7} pending=[{8}]",
			netActual, netBook.Long.Active, netBook.Short.Active, netClosing, netReconciling, netSubmitting, netCutoff,
			netMarket != null && netMarket.Order != null ? netMarket.Order.Name + ":" + netMarket.State : "none", pending);
	}

	private void NewNetSession()
	{
		if (netActual != 0 || netBook.Active || NetOrdersPending())
		{
			NetFail("Prior session has unsettled owned exposure or orders (" + NetStateText() + ")");
			return;
		}
		rollSettleQuotes = 0;
		netBook.NewSession(bid, ask, latestTime);
		netCutoff = false;
		netLongReady = (netShortReady = false);
		netSessionIntents.Clear();
	}

	private void ProcessNetQuote()
	{
		netBook.ManageNative(bid, ask, latestTime);
		if (RbeHistory.SubmitCutoff(model.TradingDate, latestNy, State == State.Historical))
		{
			netCutoff = true;
			BeginNetClose();
		}
		if (model.RangeAccepted)
		{
			NetObserveTouch(netBook.Long, last >= RbeModel.Up(model.High, TickSize));
			NetObserveTouch(netBook.Short, last <= RbeModel.Down(model.Low, TickSize));
			if (!buyTouched)
			{
				netLongReady = true;
			}
			if (!sellTouched)
			{
				netShortReady = true;
			}
		}
		DriveNetExposure();
	}

	private void NetObserveTouch(RbeNetLeg leg, bool crossed)
	{
		if (!crossed || ((leg.Side == 1) ? buyTouched : sellTouched))
		{
			return;
		}
		bool flag = ((leg.Side == 1) ? netLongReady : netShortReady);
		if (leg.Side == 1)
		{
			buyTouched = true;
		}
		else
		{
			sellTouched = true;
		}
		NetIntent netIntent = LegIntent(leg, NetRole.Entry);
		if (State == State.Historical && flag && !netCutoff && !netClosing && !netReconciling && !executionFailed && !newsBlocked && BrokerReady() && !leg.Used && !((leg.Side == 1) ? (MaxBuy == 0) : (MaxSell == 0)) && (netIntent == null || !NetPending(netIntent.Tracked)))
		{
			int num = QuantityFor(leg.Side);
			if (num < 1)
			{
				historicalRiskSkips++;
				ReportRiskSkip(leg.Side, last);
				return;
			}
			Log("NET_HISTORY_FALLBACK", leg.Side, num, last, "FRESH_TOUCH_BEFORE_VALID_STAGING");
			SubmitNetOrder(NetRole.Entry, leg, leg.Side * num, OrderType.Market, 0.0, Distance(leg.Side));
		}
	}

	private void NetLegOpened(RbeNetLeg leg)
	{
		UpdateNetRestartGuard();
		newsBeEligible = State == State.Realtime && HasUpcomingSessionNews(leg.EntryTime);
		if (leg.Side == 1)
		{
			sessionBuyFills++;
		}
		else
		{
			sessionSellFills++;
		}
		if (State == State.Historical)
		{
			historicalEntries++;
		}
		leg.Visual = new RbeTradeVisual
		{
			Tag = owner + "_NET_BOOK_" + ++cycle,
			Side = leg.Side,
			Day = model.TradingDate,
			EntryTime = leg.EntryTime,
			ObservedTime = leg.EntryTime,
			Entry = leg.Entry,
			InitialStop = leg.Protection.Stop,
			Stop = leg.Protection.Stop,
			Level = ((leg.Side == 1) ? model.High : model.Low),
			LevelTime = ((leg.Side == 1) ? rangeVisual.HighFormed : rangeVisual.LowFormed)
		};
		nativeVisualKeys.Add(VisualKey(model.TradingDate, leg.Side));
		RemoveSyntheticVisual(model.TradingDate, leg.Side);
		Log("BOOK_ENTRY", leg.Side, leg.Quantity, leg.Entry, "NATIVE_LEG_FILL", leg.EntryTime);
	}

	private void NetLegClosed(RbeNetLeg leg)
	{
		UpdateNetRestartGuard();
		if (leg.Visual != null)
		{
			leg.Visual.ExitPrice = leg.Exit;
			leg.Visual.ExitTime = leg.ExitTime;
			leg.Visual.UpdateStop(leg.Protection.Stop, leg.ExitTime);
			closedVisuals.Add(leg.Visual);
			DrawTrade(leg.Visual, leg.ExitTime);
		}
		Log("BOOK_EXIT", leg.Side, leg.FilledQuantity, leg.Exit, "NET_LEG_RESOLVED", leg.ExitTime, (leg.Visual == null) ? model.TradingDate : leg.Visual.Day);
	}

	private void UpdateNetRestartGuard()
	{
		if (Account == null || Id <= 0)
		{
			return;
		}
		lock (restartOwners)
		{
			if (restartOwners.TryGetValue(Id, out var value) && value.Account == Account && value.Prefix == owner)
			{
				value.InternalBooksActive = netBook.Active;
			}
		}
	}

	private static bool NetPending(OwnedOrder order)
	{
		return order != null && RbeNetOrderGate.Pending(Terminal(order.State), order.ReportedFills, order.ProcessedFills);
	}

	private bool NetOrdersPending()
	{
		foreach (NetIntent netSessionIntent in netSessionIntents)
		{
			if (NetPending(netSessionIntent.Tracked))
			{
				return true;
			}
		}
		return false;
	}

	private NetIntent LegIntent(RbeNetLeg leg, NetRole role)
	{
		NetIntent result = null;
		foreach (NetIntent netSessionIntent in netSessionIntents)
		{
			if (netSessionIntent.Leg == leg && netSessionIntent.Role == role)
			{
				result = netSessionIntent;
			}
		}
		return result;
	}

	private void CancelNetOrder(OwnedOrder tracked)
	{
		if (State == State.Realtime && (!string.IsNullOrEmpty(brokerRestrictionReason) || !LiveRecoveryReady())) return;
		if ((!recoveryAccountMode || (BrokerReady() && LiveRecoveryReady())) && tracked != null && tracked.Order != null && !tracked.CancelRequested && !Terminal(tracked.State) && (tracked.State == OrderState.Accepted || tracked.State == OrderState.Working || tracked.State == OrderState.PartFilled))
		{
			tracked.CancelRequested = true;
			if (recoveryAccountMode)
			{
				Account.Cancel(new Order[1] { tracked.Order });
			}
			else
			{
				CancelOrder(tracked.Order);
			}
		}
	}

	private void BeginNetClose()
	{
		if (!netClosing)
		{
			netCloseQuantity = 0;
			netCloseValue = 0.0;
		}
		netClosing = true;
	}

	private void DriveNetExposure()
	{
		if (State == State.Realtime && !string.IsNullOrEmpty(brokerRestrictionReason)) return;
		if (netBook == null || State == State.Terminated || !BrokerReady() || recoveryBooting || !LiveRecoveryReady())
		{
			return;
		}
		if (driving)
		{
			driveAgain = true;
			return;
		}
		driving = true;
		try
		{
			int num = 0;
			do
			{
				driveAgain = false;
				if (netSubmitting)
				{
					break;
				}
				if (netClosing || netReconciling)
				{
					bool flag = false;
					foreach (NetIntent item in new List<NetIntent>(netSessionIntents))
					{
						if (item.Role != NetRole.Adjustment && NetPending(item.Tracked))
						{
							flag = true;
							CancelNetOrder(item.Tracked);
						}
					}
					if (flag || NetPending(netMarket))
					{
						break;
					}
					netMarket = null;
					int num2 = RbeNetBook.Adjustment(netActual, NetTarget);
					if (num2 != 0)
					{
						SubmitNetOrder(NetRole.Adjustment, null, num2, OrderType.Market, 0.0, 0.0);
						break;
					}
					netReconciling = false;
					if (netClosing)
					{
						double price = ((netCloseQuantity > 0) ? (netCloseValue / (double)netCloseQuantity) : last);
						RbeNetLeg[] array = new RbeNetLeg[2] { netBook.Long, netBook.Short };
						foreach (RbeNetLeg rbeNetLeg in array)
						{
							if (rbeNetLeg.Active)
							{
								netBook.AddExitFill(rbeNetLeg, rbeNetLeg.Quantity, price, (netCloseQuantity > 0) ? netCloseTime : NetEventTime());
							}
						}
						netClosing = false;
					}
				}
				bool flag2 = false;
				foreach (NetIntent netSessionIntent in netSessionIntents)
				{
					if (netSessionIntent.Tracked != null && netSessionIntent.Tracked.ReportedFills > netSessionIntent.Tracked.ProcessedFills)
					{
						flag2 = true;
					}
				}
				if (flag2)
				{
					break;
				}
				if (netActual != netBook.Target)
				{
					netReconciling = true;
					driveAgain = true;
					continue;
				}
				RbeNetLeg[] array2 = new RbeNetLeg[2] { netBook.Long, netBook.Short };
				foreach (RbeNetLeg leg in array2)
				{
					EnsureNetLegStop(leg);
					EnsureNetEntry(leg);
				}
			}
			while (driveAgain && ++num < 16);
		}
		finally
		{
			driving = false;
			ReleaseSettledExposure();
		}
	}

	private void ReleaseSettledExposure()
	{
		if (State != State.Realtime || netActual != 0 || netSubmitting || recoveryBooting) return;
		foreach (NetIntent intent in netSessionIntents)
			if (intent.Tracked == null || !Terminal(intent.Tracked.State) || intent.Tracked.ReportedFills != intent.Tracked.ProcessedFills) return;
		ProductExposure.Release(owner);
	}

	private bool ReserveEntryExposure(int side)
	{
		var ownEntries = new HashSet<Order>(netSessionIntents.Where(i => i.Role == NetRole.Entry && i.Tracked != null && i.Tracked.Order != null).Select(i => i.Tracked.Order));
		bool both = MaxBuy > 0 && !netBook.Long.Used && MaxSell > 0 && !netBook.Short.Used;
		both = both || netSessionIntents.Any(i => i.Role == NetRole.Entry && i.Tracked != null && i.Tracked.Order != null && NetPending(i.Tracked) && NetOrderSign(i.Tracked.Order) != side);
		string reason;
		bool reserved = both
			? ProductExposure.ReserveBoth(owner, Account, Instrument, BlockOpposingIndexExposure, out reason, ownEntries, netActual)
			: ProductExposure.Reserve(owner, side, Account, Instrument, BlockOpposingIndexExposure, out reason, ownEntries, netActual);
		if (!reserved) status = reason;
		return reserved;
	}

	private static int NetOrderSign(Order order)
	{
		return (order.OrderAction == OrderAction.Buy || order.OrderAction == OrderAction.BuyToCover) ? 1 : (-1);
	}

	private void SubmitNetOrder(NetRole role, RbeNetLeg leg, int signedQuantity, OrderType type, double stop, double distance)
	{
		// Native Position may remain stale after a broker/account-level close.
		// The same owned/account evidence boundary applies to both transports.
		if (State == State.Realtime && (!string.IsNullOrEmpty(brokerRestrictionReason) || !LiveRecoveryReady())) return;
		if ((recoveryAccountMode && (!BrokerReady() || !LiveRecoveryReady())) || (role == NetRole.Entry && !EnableNewTrades))
		{
			return;
		}
		string text = owner;
		if (State == State.Realtime && role == NetRole.Entry && !ReserveEntryExposure(Math.Sign(signedQuantity))) return;
		string text2 = role switch
		{
			NetRole.Protection => "_NS", 
			NetRole.Entry => "_NE", 
			_ => "_NA", 
		};
		int num = ++cycle;
		string text3 = text + text2 + num;
		NetIntent netIntent = new NetIntent
		{
			Role = role,
			Leg = leg,
			Distance = distance
		};
		netIntents.Add(text3, netIntent);
		ownedEntrySignals.Add(text3);
		netSessionIntents.Add(netIntent);
		netSubmitting = true;
		if (role == NetRole.Entry && State == State.Historical)
		{
			historicalEntryRequests++;
		}
		Log("NET_REQUEST", Math.Sign(signedQuantity), Math.Abs(signedQuantity), stop, role.ToString());
		if (type == OrderType.StopMarket)
		{
			LogNativeStopContext(Math.Sign(signedQuantity), Math.Abs(signedQuantity), stop);
		}
		try
		{
			OrderAction orderAction;
			if (signedQuantity <= 0)
			{
				orderAction = ((netActual > 0 && -signedQuantity <= netActual) ? OrderAction.Sell : OrderAction.SellShort);
			}
			else
			{
				orderAction = ((netActual < 0 && signedQuantity <= -netActual) ? OrderAction.BuyToCover : OrderAction.Buy);
			}
			if (State == State.Realtime && !SaveRecovery(new RbeRecoveryOrder
			{
				Name = text3,
				Role = role.ToString(),
				Side = (leg?.Side ?? 0),
				Quantity = Math.Abs(signedQuantity),
				Distance = distance,
				Type = type.ToString(),
				Action = orderAction.ToString(),
				Stop = stop,
				State = OrderState.Initialized.ToString()
			}))
			{
				return;
			}
			Order order;
			if (recoveryAccountMode)
			{
				order = Account.CreateOrder(Instrument, orderAction, type, OrderEntry.Automated, TimeInForce.Gtc, Math.Abs(signedQuantity), 0.0, stop, "", text3, Globals.MaxDate, null);
				if (order != null)
				{
					NetTrack(order);
					Account.Submit(new Order[1] { order });
				}
			}
			else
			{
				order = SubmitOrderUnmanaged(executionSeries, orderAction, type, Math.Abs(signedQuantity), 0.0, stop, "", text3);
			}
			if (order != null && netIntent.Tracked == null)
			{
				NetTrack(order);
			}
			if (netIntent.Tracked == null)
			{
				if (State == State.Historical && role == NetRole.Entry && leg != null)
				{
					// NinjaTrader's historical engine can refuse a stop entry on its own bar-range check even when the local guard passed.
					// That used to fail the whole backtest (after years of data). The side is treated as already crossed for this session.
					HistoricalEntryIgnored(leg, stop, text3, netIntent);
					driveAgain = true;
					return;
				}
				NetFail("Unmanaged " + role.ToString() + " returned no order");
			}
			if (role == NetRole.Adjustment)
			{
				netMarket = netIntent.Tracked;
			}
		}
		finally
		{
			netSubmitting = false;
		}
		driveAgain = true;
	}

	private void EnsureNetEntry(RbeNetLeg leg)
	{
		if ((State == State.Realtime && recoveryWriteFault) || (State == State.Historical && !IsInStrategyAnalyzer && !RbeHistory.CanReplayCompletedSession(model.TradingDate, historicalEndNy)))
		{
			return;
		}
		NetIntent netIntent = LegIntent(leg, NetRole.Entry);
		if (netIntent != null && NetPending(netIntent.Tracked))
		{
			if (!EnableNewTrades || netCutoff || executionFailed || newsBlocked || leg.ExitStarted)
			{
				CancelNetOrder(netIntent.Tracked);
			}
		}
		else
		{
			if (!EnableNewTrades || netCutoff || executionFailed || newsBlocked || !model.RangeAccepted || leg.Used)
			{
				return;
			}
			bool num;
			if (leg.Side != 1)
			{
				if (MaxSell == 0)
				{
					return;
				}
				num = sellTouched;
			}
			else
			{
				if (MaxBuy == 0)
				{
					return;
				}
				num = buyTouched;
			}
			if (num || (State == State.Historical && netHistoricalQuoteReplay))
			{
				return;
			}
			double num2 = ((leg.Side == 1) ? RbeModel.Up(model.High, TickSize) : RbeModel.Down(model.Low, TickSize));
			if (((leg.Side == 1) ? (ask >= num2) : (bid <= num2)) || !NetHistoricalSubmissionStopValid(leg.Side, num2))
			{
				return;
			}
			int num3 = QuantityFor(leg.Side);
			if (num3 < 1)
			{
				if (leg.Side == 1)
				{
					buyTouched = true;
				}
				else
				{
					sellTouched = true;
				}
				if (State == State.Historical)
				{
					historicalRiskSkips++;
				}
				ReportRiskSkip(leg.Side, num2);
				Log("SKIP", leg.Side, 0, num2, "NET_RISK_LIMIT");
			}
			else
			{
				SubmitNetOrder(NetRole.Entry, leg, leg.Side * num3, OrderType.StopMarket, num2, Distance(leg.Side));
			}
		}
	}

	private void EnsureNetLegStop(RbeNetLeg leg)
	{
		NetIntent netIntent = LegIntent(leg, NetRole.Protection);
		if (!leg.Active)
		{
			if (netIntent != null)
			{
				CancelNetOrder(netIntent.Tracked);
			}
			return;
		}
		double num;
		if (latestTime >= leg.EntryTime)
		{
			num = ((leg.Side == 1) ? bid : ask);
		}
		else
		{
			num = leg.Entry;
		}
		bool flag = num > 0.0 && ((leg.Side == 1) ? (num <= leg.Protection.Stop) : (num >= leg.Protection.Stop));
		if (netIntent != null && NetPending(netIntent.Tracked))
		{
			OwnedOrder tracked = netIntent.Tracked;
			if (tracked.Order.OrderType == OrderType.Market || tracked.CancelRequested || (tracked.State != OrderState.Working && tracked.State != OrderState.Accepted && tracked.State != OrderState.PartFilled))
			{
				return;
			}
			int num2 = tracked.ProcessedFills + leg.Quantity;
			if (tracked.Quantity == num2 && !(Math.Abs(tracked.StopPrice - leg.Protection.Stop) > TickSize / 2.0))
			{
				return;
			}
			if (flag)
			{
				CancelNetOrder(tracked);
			}
			else if (!NetHistoricalSubmissionStopValid(-leg.Side, leg.Protection.Stop))
			{
				if (tracked.Quantity != num2 && NetHistoricalSubmissionStopValid(-leg.Side, tracked.StopPrice))
				{
					ChangeNetOrder(tracked.Order, num2, tracked.StopPrice);
				}
				else if (tracked.Quantity != num2)
				{
					Log("NET_STOP_DEFER", leg.Side, leg.Quantity, tracked.StopPrice, "QUANTITY_RESIZE_AMBIGUOUS");
				}
			}
			else
			{
				ChangeNetOrder(tracked.Order, num2, leg.Protection.Stop);
			}
			return;
		}
		if (flag)
		{
			leg.ExitStarted = true;
			NetIntent netIntent2 = LegIntent(leg, NetRole.Entry);
			if (netIntent2 != null)
			{
				CancelNetOrder(netIntent2.Tracked);
			}
		}
		else if (!NetHistoricalSubmissionStopValid(-leg.Side, leg.Protection.Stop))
		{
			Log("NET_STOP_DEFER", leg.Side, leg.Quantity, leg.Protection.Stop, "NATIVE_SUBMISSION_CONTEXT");
			return;
		}
		SubmitNetOrder(NetRole.Protection, leg, -leg.Side * leg.Quantity, flag ? OrderType.Market : OrderType.StopMarket, flag ? 0.0 : leg.Protection.Stop, 0.0);
	}

	private void ChangeNetOrder(Order order, int quantity, double stop)
	{
		if (State == State.Realtime && (!string.IsNullOrEmpty(brokerRestrictionReason) || !LiveRecoveryReady())) return;
		if (!recoveryAccountMode)
		{
			ChangeOrder(order, quantity, 0.0, stop);
		}
		else if (BrokerReady() && LiveRecoveryReady())
		{
			order.QuantityChanged = quantity;
			order.LimitPriceChanged = 0.0;
			order.StopPriceChanged = stop;
			Account.Change(new Order[1] { order });
		}
	}

	private OwnedOrder NetTrack(Order order)
	{
		if (!netIntents.TryGetValue(order.Name, out var value))
		{
			throw new InvalidOperationException("Owned net order has no intent");
		}
		if (!orders.TryGetValue(order, out var value2))
		{
			value2 = new OwnedOrder
			{
				Order = order,
				State = order.OrderState,
				Quantity = order.Quantity,
				StopPrice = order.StopPrice,
				NetLeg = value.Leg
			};
			orders.Add(order, value2);
		}
		value.Tracked = value2;
		if (State == State.Realtime && value.Role == NetRole.Protection) ProductExposure.ObserveExit(order);
		if (value.Role == NetRole.Adjustment)
		{
			netMarket = value2;
		}
		return value2;
	}

	private void NetOrderUpdate(Order order, int quantity, double stopPrice, int filled, OrderState state, DateTime time, ErrorCode error, string comment)
	{
		if (Owns(order))
		{
			RecoveryLiveOrder(order);
			if (State == State.Historical && time > netHistoricalBarTime)
			{
				netHistoricalBarTime = time;
			}
			OwnedOrder ownedOrder = NetTrack(order);
			ownedOrder.State = state;
			ownedOrder.ReportedFills = filled;
			ownedOrder.Quantity = quantity;
			ownedOrder.StopPrice = stopPrice;
			if (error != ErrorCode.NoError || state == OrderState.Rejected)
			{
				if (State == State.Realtime && IsBrokerRestriction(comment))
				{
					brokerRestrictionReason = comment;
					netCutoff = true;
					// Commit the restriction before faulting; restart cannot erase this latch.
					SaveRecovery();
					executionFailed = true;
					status = "Broker account restricted; existing protection retained";
					Print("[RBE] BROKER_RESTRICTION " + comment);
					return;
				}
				NetFail(error.ToString() + " " + comment);
			}
			Log("NET_ORDER", NetOrderSign(order), quantity, stopPrice, order.Name + ":" + state, time);
			SaveRecovery();
			DriveNetExposure();
		}
	}

	private void NetExecutionUpdate(Execution execution, string executionId, double price, int quantity, DateTime time)
	{
		if (execution == null || !Owns(execution.Order) || !executions.Add(executionId))
		{
			return;
		}
		RecoveryLiveFill(executionId);
		Order order = execution.Order;
		if (State == State.Historical && time > netHistoricalBarTime)
		{
			netHistoricalBarTime = time;
		}
		OwnedOrder ownedOrder = NetTrack(order);
		NetIntent netIntent = netIntents[order.Name];
		ownedOrder.ProcessedFills += quantity;
		int value = netActual;
		netActual += NetOrderSign(order) * quantity;
		if (Math.Abs(netActual) > EffectiveMaxContracts)
		{
			NetFail("Broker quantity exceeds instance cap");
			return;
		}
		if (netIntent.Role == NetRole.Entry)
		{
			RbeNetLeg leg = netIntent.Leg;
			if (leg.Side == 1)
			{
				buyTouched = true;
			}
			else
			{
				sellTouched = true;
			}
			if (leg == ((leg.Side == 1) ? netBook.Long : netBook.Short) && !leg.ExitStarted && !ownedOrder.CancelRequested && !netCutoff && !netClosing && !newsBlocked)
			{
				netBook.AddEntryFill(leg, quantity, price, netIntent.Distance, time);
				Log("BOOK_ENTRY_FILL", leg.Side, quantity, price, "VWAP=" + leg.Entry, time);
			}
			else
			{
				netReconciling = true;
				CancelNetOrder(ownedOrder);
			}
		}
		else if (netIntent.Role == NetRole.Protection)
		{
			if (netIntent.Leg == null || !netIntent.Leg.Active || quantity > netIntent.Leg.Quantity)
			{
				NetFail("Protective execution has no matching active leg quantity");
				return;
			}
			netBook.AddExitFill(netIntent.Leg, quantity, price, time);
			NetIntent netIntent2 = LegIntent(netIntent.Leg, NetRole.Entry);
			if (netIntent2 != null)
			{
				CancelNetOrder(netIntent2.Tracked);
			}
		}
		else if (netClosing)
		{
			netCloseQuantity += quantity;
			netCloseValue += price * (double)quantity;
			netCloseTime = time;
		}
		if (State == State.Realtime)
		{
			newsCycleCommission += Math.Abs(execution.Commission);
			newsCycleEntryQuantity += Math.Max(0, Math.Abs(netActual) - Math.Abs(value));
			if (netActual == 0 && newsCycleEntryQuantity > 0.0)
			{
				if (newsCycleCommission > 0.0)
				{
					newsObservedCommission += newsCycleCommission;
					newsObservedQuantity += newsCycleEntryQuantity;
				}
				newsCycleCommission = (newsCycleEntryQuantity = 0.0);
			}
		}
		Log("NET_FILL", NetOrderSign(order), quantity, price, netIntent.Role.ToString() + ";BROKER_NET=" + netActual, time);
		SaveRecovery();
		DriveNetExposure();
	}

	private static bool IsBrokerRestriction(string reason)
	{
		if (string.IsNullOrWhiteSpace(reason)) return false;
		return reason.IndexOf("liquidation only", StringComparison.OrdinalIgnoreCase) >= 0
			|| reason.IndexOf("liquidation-only", StringComparison.OrdinalIgnoreCase) >= 0
			|| reason.IndexOf("low net liquidating value", StringComparison.OrdinalIgnoreCase) >= 0
			|| reason.IndexOf("trading is disabled", StringComparison.OrdinalIgnoreCase) >= 0
			|| reason.IndexOf("permission", StringComparison.OrdinalIgnoreCase) >= 0;
	}

	private void NetFail(string reason)
	{
		executionFailed = true;
		netCutoff = true;
		status = "Net executor error";
		SaveRecovery();
		Print("[RBE] NET_ERROR " + reason);
		if (State == State.Historical)
		{
			throw new InvalidOperationException("Net historical execution failed: " + reason);
		}
		if (State == State.Realtime && string.IsNullOrEmpty(brokerRestrictionReason) && LiveRecoveryReady())
		{
			if (recoveryAccountMode)
			{
				BeginNetClose();
				DriveNetExposure();
			}
			else
			{
				CloseStrategy(owner + "_NET_FAULT");
			}
		}
	}

	private void NetNewsGuard(bool active, bool before)
	{
		if (active)
		{
			NetLiquidationQuotes();
			if (NewsFlattenBefore)
			{
				BeginNetClose();
			}
			else if (before && NewsCostCoveredBE)
			{
				netBook.ProtectAtCost(bid, ask, EffectiveNewsCost());
			}
			DriveNetExposure();
		}
	}

	private DateTime NetEventTime()
	{
		return (State == State.Realtime) ? TimeZoneInfo.ConvertTime(SessionClockNy(), NewsZone, platformZone) : latestTime;
	}

	private void NetLiquidationQuotes()
	{
		if (State == State.Realtime)
		{
			double currentBid = GetCurrentBid(executionSeries);
			double currentAsk = GetCurrentAsk(executionSeries);
			if (currentBid > 0.0)
			{
				bid = currentBid;
			}
			if (currentAsk > 0.0)
			{
				ask = currentAsk;
			}
		}
	}

	private string NetPositionText()
	{
		if (recoveryAccountMode && recoveryBooting)
		{
			return "UNVERIFIED";
		}
		if (netBook.Active)
		{
			return "NET " + netActual + "  L" + (netBook.Long.Active ? netBook.Long.Quantity : 0) + "/S" + (netBook.Short.Active ? netBook.Short.Quantity : 0);
		}
		return (netActual == 0) ? "FLAT" : ("NET " + netActual);
	}

	private string NetStopText()
	{
		NetIntent netIntent = LegIntent((netActual > 0) ? netBook.Long : netBook.Short, NetRole.Protection);
		return (netActual != 0 && netIntent != null && NetPending(netIntent.Tracked)) ? netIntent.Tracked.StopPrice.ToString("0.00") : "--";
	}

	private string NetCostText()
	{
		string text = "Cost $" + EffectiveNewsCost().ToString("0.00") + "/ct";
		RbeNetLeg rbeNetLeg = ((netActual > 0) ? netBook.Long : netBook.Short);
		if (netActual != 0 && rbeNetLeg.Active && newsBeEligible)
		{
			return text + "  ·  News BE " + rbeNetLeg.Protection.CostCoveredStop(TickSize, EffectiveNewsCost(), Instrument.MasterInstrument.PointValue).ToString("0.00");
		}
		return text + ((newsObservedQuantity > 0.0) ? " (observed)" : " (assumed)");
	}

	private void PaintNetTrades()
	{
		RbeNetLeg[] array = new RbeNetLeg[2] { netBook.Long, netBook.Short };
		foreach (RbeNetLeg rbeNetLeg in array)
		{
			if (rbeNetLeg.Active && rbeNetLeg.Visual != null)
			{
				rbeNetLeg.Visual.ObservedTime = latestTime;
				rbeNetLeg.Visual.UpdateStop(rbeNetLeg.Protection.Stop, latestTime);
				DrawTrade(rbeNetLeg.Visual, LiveRight(rbeNetLeg.Visual));
			}
		}
	}

	private void TryRecoverAccountOrders()
	{
		if (!recoveryAccountMode || !recoveryBooting || !BrokerReady())
		{
			return;
		}
		try
		{
			recoveryRecord = recoveryStore.Load(recoveryFingerprint);
			if (recoveryRecord == null)
			{
				throw new InvalidOperationException("Owned recovery checkpoint disappeared.");
			}
			ReconcileRecoveryBroker();
			RestoreRecoveryModels();
			orders.Clear();
			netIntents.Clear();
			netSessionIntents.Clear();
			netMarket = null;
			foreach (RbeRecoveryOrder order in recoveryRecord.Orders)
			{
				if (recoveryBrokerOrders.TryGetValue(RbeRecoveryEvidence.OrderKey(order), out var value))
				{
					NetIntent netIntent = new NetIntent();
					netIntent.Role = (NetRole)Enum.Parse(typeof(NetRole), order.Role);
					ref RbeNetLeg leg = ref netIntent.Leg;
					RbeNetLeg rbeNetLeg;
					if (order.Side == 1)
					{
						rbeNetLeg = netBook.Long;
					}
					else
					{
						rbeNetLeg = ((order.Side == -1) ? netBook.Short : null);
					}
					leg = rbeNetLeg;
					netIntent.Distance = order.Distance;
					NetIntent netIntent2 = netIntent;
					netIntents.Add(order.Name, netIntent2);
					netSessionIntents.Add(netIntent2);
					OwnedOrder ownedOrder = NetTrack(value);
					ownedOrder.ProcessedFills = order.ProcessedFilled;
					ownedOrder.ReportedFills = value.Filled;
				}
			}
			latestTime = recoveryRecord.LastQuoteTime;
			latestNy = RbeModel.ToNewYork(latestTime, platformZone);
			last = recoveryRecord.Last;
			bid = recoveryRecord.LastBid;
			ask = recoveryRecord.LastAsk;
			recoveryBooting = false;
			recoveryAccountWait = null;
			status = "Recovered exact owned broker orders";
			SaveRecovery();
			Print("[RBE] ACCOUNT_RECOVERY_READY: exact saved broker orders restored without native submissions; strategy panel/journal owns management.");
		}
		catch (Exception ex)
		{
			recoveryBooting = true;
			status = "Recovery pending: " + ex.Message;
			if (recoveryAccountWait != ex.Message)
			{
				recoveryAccountWait = ex.Message;
				Print("[RBE] ACCOUNT_RECOVERY_WAIT: " + ex.Message);
			}
		}
	}

	private bool BindRecoveredAccountOrder(Order order)
	{
		if (order == null || order.Account != Account || order.Instrument == null || order.Instrument.FullName != Instrument.FullName)
		{
			return false;
		}
		if (!netIntents.TryGetValue(order.Name, out var value) || value.Tracked == null)
		{
			return false;
		}
		OwnedOrder tracked = value.Tracked;
		Order order2 = tracked.Order;
		if (order2 != order)
		{
			if (string.IsNullOrEmpty(order2.OrderId) || order2.OrderId != order.OrderId || !RbeRecoveryEvidence.SameBrokerAction(order2.OrderAction.ToString(), order.OrderAction.ToString()) || order2.OrderType != order.OrderType)
			{
				return false;
			}
			orders.Remove(order2);
			tracked.Order = order;
			orders[order] = tracked;
		}
		return true;
	}

	private void RecoveredAccountOrderUpdate(object sender, OrderEventArgs e)
	{
		Order order = e.Order;
		if (!recoveryAccountMode || order == null || order.Name == null || !order.Name.StartsWith(owner + "_", StringComparison.Ordinal))
		{
			return;
		}
		int quantity = e.Quantity;
		int filled = e.Filled;
		double stop = e.StopPrice;
		OrderState state = e.OrderState;
		DateTime time = e.Time;
		ErrorCode error = e.Error;
		string comment = e.Comment;
		try
		{
			TriggerCustomEvent((object o) =>
			{
				lock (recoveryStateGate)
				{
					if (State == State.Realtime)
					{
						if (recoveryBooting)
						{
							PollLiveRecovery();
						}
						else if (!BindRecoveredAccountOrder(order))
						{
							if (!Terminal(state) || filled != 0)
							{
								recoveryBooting = true;
								status = "Recovery pending: conflicting owned account order";
							}
						}
						else
						{
							ProcessOrderUpdate(order, 0.0, stop, quantity, filled, order.AverageFillPrice, state, time, error, comment);
						}
					}
				}
			}, null);
		}
		catch (InvalidOperationException)
		{
		}
	}

	private void RecoveredAccountExecutionUpdate(object sender, ExecutionEventArgs e)
	{
		Execution execution = e.Execution;
		Order order = ((execution == null) ? null : execution.Order);
		if (!recoveryAccountMode || order == null || order.Name == null || !order.Name.StartsWith(owner + "_", StringComparison.Ordinal))
		{
			return;
		}
		string id = e.ExecutionId;
		double price = e.Price;
		int quantity = e.Quantity;
		DateTime time = e.Time;
		try
		{
			TriggerCustomEvent((object o) =>
			{
				lock (recoveryStateGate)
				{
					if (State == State.Realtime)
					{
						if (recoveryBooting)
						{
							PollLiveRecovery();
						}
						else if (!BindRecoveredAccountOrder(order))
						{
							recoveryBooting = true;
							status = "Recovery pending: conflicting owned execution";
						}
						else
						{
							NetExecutionUpdate(execution, id, price, quantity, time);
						}
					}
				}
			}, null);
		}
		catch (InvalidOperationException)
		{
		}
	}

	private bool LiveRecoveryReady()
	{
		if (State != State.Realtime)
		{
			return true;
		}
		if (recoveryLiveReplaying || !BrokerReady() || (recoveryAccountMode && recoveryBooting))
		{
			return false;
		}
		foreach (NetIntent netSessionIntent in netSessionIntents)
		{
			if (netSessionIntent.Tracked != null && (netSessionIntent.Tracked.State == OrderState.Unknown || netSessionIntent.Tracked.ReportedFills != netSessionIntent.Tracked.ProcessedFills))
			{
				status = "Recovery pending: owned order evidence";
				return false;
			}
		}
		int num = ((Position.MarketPosition == MarketPosition.Long) ? Position.Quantity : ((Position.MarketPosition == MarketPosition.Short) ? (-Position.Quantity) : 0));
		if (!recoveryAccountMode && num != netActual)
		{
			status = "Recovery pending: native position evidence";
			return false;
		}
		if (netActual != 0)
		{
			int num2 = 0;
			lock (Account.Positions)
			{
				foreach (Position position in Account.Positions)
				{
					if (position.Instrument.FullName == Instrument.FullName)
					{
						num2 += ((position.MarketPosition == MarketPosition.Long) ? 1 : ((position.MarketPosition == MarketPosition.Short) ? (-1) : 0)) * position.Quantity;
					}
				}
			}
			if (Math.Sign(num2) != Math.Sign(netActual) || Math.Abs(num2) < Math.Abs(netActual))
			{
				status = "Recovery pending: broker position evidence";
				return false;
			}
		}
		return true;
	}

	private void PollLiveRecovery()
	{
		if (State != State.Realtime || recoveryLiveReplaying || !BrokerReady() || DateTime.UtcNow < recoveryLivePollUtc)
		{
			return;
		}
		recoveryLivePollUtc = DateTime.UtcNow.AddSeconds(1.0);
		if (recoveryAccountMode && recoveryBooting)
		{
			TryRecoverAccountOrders();
		}
		else
		{
			if (recoveryBooting)
			{
				return;
			}
			List<Execution> source;
			lock (Account.Executions)
			{
				source = Account.Executions.ToList();
			}
			recoveryLiveReplaying = true;
			try
			{
				foreach (NetIntent netSessionIntent in netSessionIntents)
				{
					OwnedOrder tracked = netSessionIntent.Tracked;
					if (tracked != null && tracked.Order != null && tracked.Order.Filled >= tracked.ProcessedFills)
					{
						tracked.State = tracked.Order.OrderState;
						tracked.ReportedFills = tracked.Order.Filled;
					}
				}
				foreach (Execution item in source.OrderBy((Execution e) => e.Time))
				{
					if (item.Order != null && !string.IsNullOrEmpty(item.ExecutionId) && !executions.Contains(item.ExecutionId) && item.Quantity > 0 && !(item.Price <= 0.0) && !double.IsNaN(item.Price) && !double.IsInfinity(item.Price) && netIntents.TryGetValue(item.Order.Name, out var value) && value.Tracked != null)
					{
						OwnedOrder tracked2 = value.Tracked;
						if (tracked2.Order == item.Order && Owns(item.Order) && !(item.Order.Instrument.FullName != Instrument.FullName) && !string.IsNullOrEmpty(item.Order.OrderId) && tracked2.ProcessedFills + item.Quantity <= item.Order.Filled)
						{
							tracked2.ReportedFills = item.Order.Filled;
							tracked2.State = item.Order.OrderState;
							NetExecutionUpdate(item, item.ExecutionId, item.Price, item.Quantity, item.Time);
						}
					}
				}
			}
			finally
			{
				recoveryLiveReplaying = false;
			}
			if (LiveRecoveryReady())
			{
				DriveNetExposure();
			}
		}
	}

	private void OpenRecoveryStore()
	{
		if (IsInStrategyAnalyzer || Account == null)
		{
			return;
		}
		string text = string.Join(";", 0.6.ToString("R", CultureInfo.InvariantCulture), 0.4.ToString("R", CultureInfo.InvariantCulture), 2.6.ToString("R", CultureInfo.InvariantCulture), 0.6.ToString("R", CultureInfo.InvariantCulture), 1.0.ToString("R", CultureInfo.InvariantCulture), true.ToString(), 1.25.ToString("R", CultureInfo.InvariantCulture), RiskMoney.ToString("R", CultureInfo.InvariantCulture), EnforceRiskLimit.ToString(), MaxContracts.ToString(CultureInfo.InvariantCulture), MaxBuy.ToString(CultureInfo.InvariantCulture), MaxSell.ToString(CultureInfo.InvariantCulture), RoundTripCommission.ToString("R", CultureInfo.InvariantCulture), AssumedSlipTicks.ToString(CultureInfo.InvariantCulture), TickSize.ToString("R", CultureInfo.InvariantCulture), Instrument.MasterInstrument.PointValue.ToString("R", CultureInfo.InvariantCulture), platformZone.Id, NewsImpact.ToString(), NewsWindow.ToString(), NewsCostCoveredBE.ToString(), NewsFlattenBefore.ToString());
		recoveryFingerprint = RbeRecoveryStore.Fingerprint(text);
		recoveryCanonicalSettings = text;
		recoveryStore = RbeRecoveryStore.Acquire(Path.Combine(Globals.UserDataDir, "RangeBreakoutNT8", "recovery"), Account.Name, Instrument.FullName, "NetExposure", TradeDirection.ToString());
		try
		{
			recoveryRecord = recoveryStore.Load(recoveryFingerprint);
			if (recoveryStore.AdoptedFromFingerprint != null)
			{
				Print("[RBE] Settings changed since the last checkpoint; the saved state has no live exposure, so the new settings were adopted. Previous fingerprint=" + recoveryStore.AdoptedFromFingerprint + "; new fingerprint=" + recoveryFingerprint + "; new settings (stop;minRange;trailTrigger;trailDistance;trailStep;coverCosts;coverageMultiple;riskMoney;strictRisk;maxContracts;maxBuy;maxSell;commission;slipTicks;tickSize;pointValue;timeZone;newsImpact;newsWindow;newsBE;newsFlatten): " + text);
			}
			if (recoveryRecord != null)
			{
				owner = recoveryRecord.Owner;
				brokerRestrictionReason = recoveryRecord.BrokerRestrictionReason;
				recoveryNeeded = HasRecoveryExposure(recoveryRecord);
				recoveryAccountMode = recoveryNeeded;
				recoveryBooting = recoveryAccountMode;
			}
		}
		catch
		{
			Print("[RBE] Requested recovery settings (stop;minRange;trailTrigger;trailDistance;trailStep;coverCosts;coverageMultiple;riskMoney;strictRisk;maxContracts;maxBuy;maxSell;commission;slipTicks;tickSize;pointValue;timeZone;newsImpact;newsWindow;newsBE;newsFlatten): " + text);
			recoveryStore.Dispose();
			recoveryStore = null;
			throw;
		}
	}

	private static bool HasRecoveryExposure(RbeRecoveryRecord record)
	{
		return record.ActualNet != 0 || record.Long.Active || record.Short.Active || record.Orders.Any((RbeRecoveryOrder o) => !o.Terminal || o.ReportedFilled != o.ProcessedFilled || !o.SubmissionAcknowledged);
	}

	private RbeRecoveryOrder DescribeRecoveryOrder(Order order, string role, int side, double distance, int processed)
	{
		return new RbeRecoveryOrder
		{
			Name = order.Name,
			Signal = order.FromEntrySignal,
			OrderId = order.OrderId,
			Role = role,
			Side = side,
			Distance = distance,
			Action = order.OrderAction.ToString(),
			Type = order.OrderType.ToString(),
			State = order.OrderState.ToString(),
			Quantity = order.Quantity,
			Limit = order.LimitPrice,
			Stop = order.StopPrice,
			Oco = order.Oco,
			ReportedFilled = order.Filled,
			ProcessedFilled = processed,
			AverageFill = order.AverageFillPrice,
			Terminal = Terminal(order.OrderState),
			SubmissionAcknowledged = !string.IsNullOrEmpty(order.OrderId)
		};
	}

	private void ReconcileRecoveryBroker()
	{
		if (!recoveryNeeded)
		{
			return;
		}
		if (recoveryRecord.FlowFailed)
		{
			throw new InvalidOperationException("RBE executor failed before shutdown; owned state requires explicit reconciliation.");
		}
		if (Account.ConnectionStatus != ConnectionStatus.Connected)
		{
			throw new InvalidOperationException("RBE recovery requires synchronized owned broker evidence; connection is not ready.");
		}
		List<RbeRecoveryOrder> list = new List<RbeRecoveryOrder>();
		recoveryBrokerOrders.Clear();
		lock (Account.Orders)
		{
			foreach (Order order in Account.Orders)
			{
				if (order.Instrument.FullName != Instrument.FullName)
				{
					continue;
				}
				RbeRecoveryOrder rbeRecoveryOrder = recoveryRecord.Orders.FirstOrDefault((RbeRecoveryOrder o) => o.Name == order.Name && (o.Signal ?? "") == (order.FromEntrySignal ?? ""));
				if ((rbeRecoveryOrder == null || !(rbeRecoveryOrder.OrderId != order.OrderId) || !Terminal(order.OrderState) || order.Filled != 0) && (order.Name.StartsWith(owner + "_", StringComparison.Ordinal) || (!string.IsNullOrEmpty(order.FromEntrySignal) && order.FromEntrySignal.StartsWith(owner + "_", StringComparison.Ordinal))) && (rbeRecoveryOrder != null || !Terminal(order.OrderState) || order.Filled != 0))
				{
					RbeRecoveryOrder rbeRecoveryOrder2 = DescribeRecoveryOrder(order, (rbeRecoveryOrder == null) ? "Unknown" : rbeRecoveryOrder.Role, rbeRecoveryOrder?.Side ?? 0, rbeRecoveryOrder?.Distance ?? 0.0, rbeRecoveryOrder?.ProcessedFilled ?? 0);
					string text = RbeRecoveryEvidence.OrderKey(rbeRecoveryOrder2);
					if (recoveryBrokerOrders.ContainsKey(text))
					{
						throw new InvalidOperationException("Duplicate owned recovery order lineage: " + text);
					}
					recoveryBrokerOrders.Add(text, order);
					list.Add(rbeRecoveryOrder2);
				}
			}
		}
		Dictionary<string, RbeRecoveryOrder> dictionary = RbeRecoveryEvidence.Match(recoveryRecord, list);
		RbeNetBook rbeNetBook = new RbeNetBook(settings, TickSize, Instrument.MasterInstrument.PointValue, Cost());
		rbeNetBook.RestoreRecovery(recoveryRecord);
		HashSet<string> hashSet = new HashSet<string>(recoveryRecord.ExecutionIds, StringComparer.Ordinal);
		List<Execution> source;
		lock (Account.Executions)
		{
			source = Account.Executions.ToList();
		}
		foreach (Execution fill in source.OrderBy((Execution e) => e.Time))
		{
			if (fill.Order == null || fill.Order.Instrument.FullName != Instrument.FullName)
			{
				continue;
			}
			RbeRecoveryOrder rbeRecoveryOrder3 = recoveryRecord.Orders.FirstOrDefault((RbeRecoveryOrder o) => o.OrderId == fill.Order.OrderId && o.Name == fill.Order.Name && (o.Signal ?? "") == (fill.Order.FromEntrySignal ?? ""));
			if (rbeRecoveryOrder3 == null || hashSet.Contains(fill.ExecutionId))
			{
				continue;
			}
			if (string.IsNullOrEmpty(fill.ExecutionId) || fill.Quantity <= 0 || fill.Price <= 0.0)
			{
				throw new InvalidOperationException("Incomplete owned execution evidence during RBE recovery.");
			}
			if (!dictionary.TryGetValue(RbeRecoveryEvidence.OrderKey(rbeRecoveryOrder3), out var value) || rbeRecoveryOrder3.ProcessedFilled + fill.Quantity > value.ReportedFilled)
			{
				throw new InvalidOperationException("Owned recovery execution cannot be allocated exactly: " + rbeRecoveryOrder3.Name);
			}
			int num = NetOrderSign(fill.Order);
			RbeNetLeg leg = ((rbeRecoveryOrder3.Side == 1) ? rbeNetBook.Long : rbeNetBook.Short);
			if (rbeRecoveryOrder3.Role == "Entry")
			{
				rbeNetBook.AddEntryFill(leg, fill.Quantity, fill.Price, rbeRecoveryOrder3.Distance, fill.Time);
			}
			else if (rbeRecoveryOrder3.Role == "Protection")
			{
				rbeNetBook.AddExitFill(leg, fill.Quantity, fill.Price, fill.Time);
			}
			else
			{
				if (!recoveryRecord.Closing)
				{
					throw new InvalidOperationException("Unsettled net adjustment requires explicit reconciliation.");
				}
				recoveryRecord.CloseQuantity += fill.Quantity;
				recoveryRecord.CloseValue += fill.Price * (double)fill.Quantity;
				recoveryRecord.CloseTime = fill.Time;
			}
			recoveryRecord.ActualNet += num * fill.Quantity;
			rbeRecoveryOrder3.ProcessedFilled += fill.Quantity;
			hashSet.Add(fill.ExecutionId);
		}
		foreach (RbeRecoveryOrder order2 in recoveryRecord.Orders)
		{
			if (!dictionary.TryGetValue(RbeRecoveryEvidence.OrderKey(order2), out var value2))
			{
				continue;
			}
			if (order2.ProcessedFilled != value2.ReportedFilled)
			{
				throw new InvalidOperationException("Missing owned executions during downtime: " + order2.Name);
			}
			order2.ReportedFilled = value2.ReportedFilled;
			order2.Terminal = value2.Terminal;
			order2.State = value2.State;
			if (order2.Role == "Protection" && !value2.Terminal)
			{
				RbeRecoveryRecord rbeRecoveryRecord = new RbeRecoveryRecord();
				rbeNetBook.CaptureRecovery(rbeRecoveryRecord);
				RbeRecoveryLeg rbeRecoveryLeg = ((order2.Side == 1) ? rbeRecoveryRecord.Long : rbeRecoveryRecord.Short);
				rbeRecoveryLeg.Stop = ((rbeRecoveryLeg.Side == 1) ? Math.Max(rbeRecoveryLeg.Stop, value2.Stop) : Math.Min(rbeRecoveryLeg.Stop, value2.Stop));
				if (rbeRecoveryLeg.CoveredPrice > 0.0 && ((rbeRecoveryLeg.Side == 1) ? (rbeRecoveryLeg.Stop >= rbeRecoveryLeg.CoveredPrice) : (rbeRecoveryLeg.Stop <= rbeRecoveryLeg.CoveredPrice)))
				{
					rbeRecoveryLeg.CostCovered = true;
				}
				((order2.Side == 1) ? rbeNetBook.Long : rbeNetBook.Short).Protection = RbePosition.RestoreRecovery(order2.Side, rbeRecoveryLeg, settings);
			}
			order2.Stop = value2.Stop;
		}
		if (recoveryRecord.Closing && recoveryRecord.ActualNet == 0)
		{
			double price = ((recoveryRecord.CloseQuantity > 0) ? (recoveryRecord.CloseValue / (double)recoveryRecord.CloseQuantity) : recoveryRecord.Last);
			RbeNetLeg[] array = new RbeNetLeg[2] { rbeNetBook.Long, rbeNetBook.Short };
			foreach (RbeNetLeg rbeNetLeg in array)
			{
				if (rbeNetLeg.Active)
				{
					rbeNetBook.AddExitFill(rbeNetLeg, rbeNetLeg.Quantity, price, recoveryRecord.CloseTime);
				}
			}
			recoveryRecord.Closing = false;
		}
		rbeNetBook.CaptureRecovery(recoveryRecord);
		recoveryRecord.BuyFills = Math.Max(recoveryRecord.BuyFills, recoveryRecord.Long.Used ? 1 : 0);
		recoveryRecord.SellFills = Math.Max(recoveryRecord.SellFills, recoveryRecord.Short.Used ? 1 : 0);
		recoveryRecord.BuyTouched |= recoveryRecord.Long.Used;
		recoveryRecord.SellTouched |= recoveryRecord.Short.Used;
		if (recoveryRecord.ActualNet > EffectiveMaxContracts || recoveryRecord.ActualNet < -EffectiveMaxContracts)
		{
			throw new InvalidOperationException("Recovered owned quantity exceeds this executor's cap.");
		}
		recoveryRecord.ExecutionIds = hashSet.ToList();
	}

	private void ReconcileRecoveryStartup()
	{
		try
		{
			ReconcileRecoveryBroker();
		}
		catch (InvalidOperationException)
		{
			if (!TryExternalRecoverySettlement())
			{
				throw;
			}
			return;
		}
		if (!recoveryNeeded || !HasRecoveryExposure(recoveryRecord))
		{
			return;
		}
		if (recoveryNeeded && recoveryRecord.ActualNet != 0)
		{
			int num = 0;
			lock (Account.Positions)
			{
				foreach (Position position in Account.Positions)
				{
					if (position.Instrument.FullName == Instrument.FullName)
					{
						num += ((position.MarketPosition == MarketPosition.Long) ? 1 : ((position.MarketPosition == MarketPosition.Short) ? (-1) : 0)) * position.Quantity;
					}
				}
			}
			if (Math.Sign(num) != Math.Sign(recoveryRecord.ActualNet) || Math.Abs(num) < Math.Abs(recoveryRecord.ActualNet))
			{
				if (!TryExternalRecoverySettlement())
				{
					throw new InvalidOperationException("RBE recovery pending: broker position evidence does not support native bootstrap.");
				}
				return;
			}
		}
		TryExternalRecoverySettlement();
	}

	private bool TryExternalRecoverySettlement()
	{
		if (!recoveryNeeded || recoveryStore == null || State == State.Realtime || Account.ConnectionStatus != ConnectionStatus.Connected)
		{
			return false;
		}
		RbeRecoveryRecord rbeRecoveryRecord = recoveryStore.Load(recoveryFingerprint);
		if (rbeRecoveryRecord == null || rbeRecoveryRecord.ActualNet == 0)
		{
			return false;
		}
		lock (Account.Positions)
		{
			if (Account.Positions.Any((Position p) => p.Instrument.FullName == Instrument.FullName && p.Quantity != 0))
			{
				return false;
			}
		}
		string text = RbeRecoveryStore.SettlementConfirmation(rbeRecoveryRecord);
		Print("[RBE] RECOVERY_CASE " + Account.Name + " " + Instrument.FullName + " confirmation=" + text);
		if (EnableNewTrades || string.IsNullOrEmpty(BrokerCloseConfirmation) || BrokerCloseConfirmation.Trim() != text)
		{
			return false;
		}
		lock (Account.Orders)
		{
			foreach (Order order in Account.Orders)
			{
				if (!(order.Instrument.FullName != Instrument.FullName) && (order.Name.StartsWith(rbeRecoveryRecord.Owner + "_", StringComparison.Ordinal) || (!string.IsNullOrEmpty(order.FromEntrySignal) && order.FromEntrySignal.StartsWith(rbeRecoveryRecord.Owner + "_", StringComparison.Ordinal))))
				{
					RbeRecoveryOrder rbeRecoveryOrder = rbeRecoveryRecord.Orders.FirstOrDefault((RbeRecoveryOrder o) => o.Name == order.Name && (o.Signal ?? "") == (order.FromEntrySignal ?? ""));
					if (rbeRecoveryOrder == null || rbeRecoveryOrder.OrderId != order.OrderId || !RbeRecoveryEvidence.SameBrokerAction(rbeRecoveryOrder.Action, order.OrderAction.ToString()) || rbeRecoveryOrder.Type != order.OrderType.ToString() || rbeRecoveryOrder.Quantity != order.Quantity)
					{
						return false;
					}
					if (order.OrderState != OrderState.Unknown && !Terminal(order.OrderState))
					{
						return false;
					}
				}
			}
		}
		recoveryRecord = recoveryStore.SettleExternal(rbeRecoveryRecord, text, entriesDisabled: true, connectedFlat: true, noOwnedOrders: true);
		owner = recoveryRecord.Owner;
		recoveryNeeded = false;
		recoveryBrokerOrders.Clear();
		GuardOwnedRestart();
		Print("[RBE] EXTERNAL_SETTLEMENT_COMMITTED " + recoveryStore.Path + "; entries disabled; prior session consumed.");
		return true;
	}

	private bool BootstrapRecoveryMinute()
	{
		if (recoveryAccountMode)
		{
			return false;
		}
		if (!recoveryNeeded || State != State.Historical)
		{
			return false;
		}
		int num = CurrentBars[executionSeries];
		int count = BarsArray[executionSeries].Count;
		if (num < count - 3)
		{
			return false;
		}
		recoveryBooting = true;
		netHistoricalBarTime = Times[executionSeries][0];
		if (!recoverySeedSubmitted)
		{
			recoverySeedSubmitted = true;
			int actualNet = recoveryRecord.ActualNet;
			recoverySeedName = owner + "_RS";
			if (actualNet != 0)
			{
				SubmitOrderUnmanaged(executionSeries, (actualNet <= 0) ? OrderAction.SellShort : OrderAction.Buy, OrderType.Market, Math.Abs(actualNet), 0.0, 0.0, "", recoverySeedName);
			}
		}
		if (num == count - 1)
		{
			if (recoverySeedFilled != Math.Abs(recoveryRecord.ActualNet))
			{
				throw new InvalidOperationException("Native RBE recovery quantity could not be reconstructed before startup.");
			}
			RestoreRecoveryModels();
			StageRecoveryOrders();
		}
		return true;
	}

	private void RestoreRecoveryModels()
	{
		brokerRestrictionReason = recoveryRecord.BrokerRestrictionReason;
		model.RestoreRecovery(recoveryRecord);
		executionFailed = recoveryRecord.FlowFailed;
		netBook.RestoreRecovery(recoveryRecord);
		netActual = recoveryRecord.ActualNet;
		netCutoff = recoveryRecord.Cutoff;
		netClosing = recoveryRecord.Closing;
		netReconciling = recoveryRecord.Reconciling;
		netCloseQuantity = recoveryRecord.CloseQuantity;
		netCloseValue = recoveryRecord.CloseValue;
		netCloseTime = recoveryRecord.CloseTime;
		cycle = Math.Max(cycle, recoveryRecord.Cycle);
		buyTouched = recoveryRecord.BuyTouched;
		sellTouched = recoveryRecord.SellTouched;
		sessionBuyFills = recoveryRecord.BuyFills;
		sessionSellFills = recoveryRecord.SellFills;
		netLongReady = recoveryRecord.LongReady;
		netShortReady = recoveryRecord.ShortReady;
		newsBeEligible = recoveryRecord.NewsBeEligible;
		foreach (string executionId in recoveryRecord.ExecutionIds)
		{
			executions.Add(executionId);
			recoveryLiveExecutions.Add(executionId);
		}
		foreach (RbeRecoveryOrder order in recoveryRecord.Orders)
		{
			recoveryLiveOrders.Add(RbeRecoveryEvidence.OrderKey(order));
			ownedEntrySignals.Add(order.Name);
			if (!string.IsNullOrEmpty(order.Signal))
			{
				ownedEntrySignals.Add(order.Signal);
			}
		}
		RbeRecoveryLeg[] array = new RbeRecoveryLeg[2] { recoveryRecord.Long, recoveryRecord.Short };
		foreach (RbeRecoveryLeg rbeRecoveryLeg in array)
		{
			if (rbeRecoveryLeg.Active)
			{
				RbeTradeVisual visual = new RbeTradeVisual
				{
					Tag = owner + "_REC_" + rbeRecoveryLeg.Side,
					Side = rbeRecoveryLeg.Side,
					Day = recoveryRecord.TradingDate,
					Entry = rbeRecoveryLeg.Entry,
					InitialStop = rbeRecoveryLeg.InitialStop,
					Stop = rbeRecoveryLeg.Stop,
					EntryTime = rbeRecoveryLeg.EntryTime,
					ObservedTime = rbeRecoveryLeg.EntryTime,
					Level = ((rbeRecoveryLeg.Side == 1) ? model.High : model.Low),
					LevelTime = ((rbeRecoveryLeg.Side == 1) ? recoveryRecord.RangeHighTime : recoveryRecord.RangeLowTime)
				};
				((rbeRecoveryLeg.Side == 1) ? netBook.Long : netBook.Short).Visual = visual;
			}
		}
		status = "Recovering owned orders";
	}

	private void StageRecoveryOrders()
	{
		if (recoveryAccountMode)
		{
			throw new InvalidOperationException("Account recovery cannot stage native replacement orders.");
		}
		if (recoveryStaged)
		{
			return;
		}
		recoveryStaged = true;
		foreach (RbeRecoveryOrder order2 in recoveryRecord.Orders)
		{
			if (!order2.Terminal)
			{
				if (order2.Type != OrderType.StopMarket.ToString() || order2.ProcessedFilled != 0)
				{
					throw new InvalidOperationException("Native recovery cannot yet reproduce this pending partial/market order exactly: " + order2.Name);
				}
				NetIntent netIntent = new NetIntent();
				netIntent.Role = (NetRole)Enum.Parse(typeof(NetRole), order2.Role);
				netIntent.Leg = ((order2.Side == 1) ? netBook.Long : netBook.Short);
				netIntent.Distance = order2.Distance;
				NetIntent netIntent2 = netIntent;
				netIntents[order2.Name] = netIntent2;
				netSessionIntents.Add(netIntent2);
				Order order = SubmitOrderUnmanaged(executionSeries, (OrderAction)Enum.Parse(typeof(OrderAction), order2.Action), OrderType.StopMarket, order2.Quantity, order2.Limit, order2.Stop, order2.Oco ?? "", order2.Name);
				if (order == null)
				{
					throw new InvalidOperationException("Native recovery pending order refused: " + order2.Name);
				}
				netIntent2.Tracked = NetTrack(order);
				netIntent2.Tracked.ProcessedFills = order2.ProcessedFilled;
				recoveryNativeOrders[RbeRecoveryEvidence.OrderKey(order2)] = order;
			}
		}
		RbeNetLeg[] array = new RbeNetLeg[2] { netBook.Long, netBook.Short };
		foreach (RbeNetLeg leg in array)
		{
			if (leg.Active && !recoveryRecord.Orders.Any((RbeRecoveryOrder o) => !o.Terminal && o.Role == "Protection" && o.Side == leg.Side))
			{
				SubmitNetOrder(NetRole.Protection, leg, -leg.Side * leg.Quantity, OrderType.StopMarket, leg.Protection.Stop, 0.0);
			}
		}
	}

	private bool RecoveryOrderCallback(Order order, ErrorCode error)
	{
		if (!recoveryBooting || State == State.Realtime)
		{
			return false;
		}
		if (error != ErrorCode.NoError || order.OrderState == OrderState.Rejected)
		{
			throw new InvalidOperationException("Native recovery bootstrap order failed: " + order.Name + " " + error);
		}
		if (order.Name == recoverySeedName)
		{
			return true;
		}
		RbeRecoveryOrder order2 = DescribeRecoveryOrder(order, "", 0, 0.0, 0);
		recoveryNativeOrders[RbeRecoveryEvidence.OrderKey(order2)] = order;
		return true;
	}

	private bool RecoveryExecutionCallback(Execution execution, int quantity)
	{
		if (!recoveryBooting || State == State.Realtime)
		{
			return false;
		}
		if (execution.Order.Name != recoverySeedName)
		{
			throw new InvalidOperationException("Pending/protective recovery order filled during native bootstrap; activation refused.");
		}
		recoverySeedFilled += quantity;
		return true;
	}

	private void ValidateRecoveryTransition()
	{
		if (recoveryAccountMode || !recoveryNeeded)
		{
			return;
		}
		if (!recoveryStaged)
		{
			throw new InvalidOperationException("Insufficient loaded history for native recovery bootstrap.");
		}
		int num = ((Position.MarketPosition == MarketPosition.Long) ? Position.Quantity : ((Position.MarketPosition == MarketPosition.Short) ? (-Position.Quantity) : 0));
		if (num != recoveryRecord.ActualNet)
		{
			throw new InvalidOperationException("Native strategy/owned recovery quantity mismatch.");
		}
		foreach (RbeRecoveryOrder item in recoveryRecord.Orders.Where((RbeRecoveryOrder o) => !o.Terminal))
		{
			string key = RbeRecoveryEvidence.OrderKey(item);
			if (!recoveryBrokerOrders.TryGetValue(key, out var value) || value.OrderId != item.OrderId || value.Quantity != item.Quantity || value.StopPrice != item.Stop || value.OrderState.ToString() != item.State || value.Filled != item.ProcessedFilled)
			{
				throw new InvalidOperationException("Owned broker state changed during history load; reconcile again before native recovery.");
			}
			if (!recoveryNativeOrders.TryGetValue(key, out var value2) || !RbeRecoveryEvidence.SameBrokerAction(value2.OrderAction.ToString(), value.OrderAction.ToString()) || value2.OrderType != value.OrderType || value2.Quantity != value.Quantity || value2.StopPrice != value.StopPrice || value2.LimitPrice != value.LimitPrice)
			{
				throw new InvalidOperationException("Native bootstrap cannot match owned broker order exactly: " + item.Name);
			}
		}
	}

	private void CompleteRecoveryActivation()
	{
		if (recoveryNeeded)
		{
			Dictionary<Order, OwnedOrder> dictionary = new Dictionary<Order, OwnedOrder>();
			foreach (KeyValuePair<string, Order> pair in recoveryNativeOrders)
			{
				if (!Terminal(pair.Value.OrderState))
				{
					Order realtimeOrder = GetRealtimeOrder(pair.Value);
					if (realtimeOrder == null)
					{
						throw new InvalidOperationException("Native recovery remap returned no owned order: " + pair.Key);
					}
					if (!orders.TryGetValue(realtimeOrder, out var value))
					{
						value = new OwnedOrder
						{
							Order = realtimeOrder,
							State = realtimeOrder.OrderState,
							ReportedFills = realtimeOrder.Filled,
							Quantity = realtimeOrder.Quantity,
							StopPrice = realtimeOrder.StopPrice
						};
					}
					RbeRecoveryOrder rbeRecoveryOrder = recoveryRecord.Orders.FirstOrDefault((RbeRecoveryOrder o) => RbeRecoveryEvidence.OrderKey(o) == pair.Key);
					if (rbeRecoveryOrder != null)
					{
						value.ProcessedFills = Math.Max(value.ProcessedFills, rbeRecoveryOrder.ProcessedFilled);
					}
					dictionary[realtimeOrder] = value;
				}
			}
			foreach (RbeRecoveryOrder item in recoveryRecord.Orders.Where((RbeRecoveryOrder o) => !o.Terminal))
			{
				string key = RbeRecoveryEvidence.OrderKey(item);
				Order realtimeOrder2 = GetRealtimeOrder(recoveryNativeOrders[key]);
				if (realtimeOrder2 == null || realtimeOrder2.OrderId != item.OrderId)
				{
					throw new InvalidOperationException("Native startup did not resume the exact owned broker order: " + item.Name + ". Recovery refused.");
				}
			}
			orders = dictionary;
			foreach (OwnedOrder value2 in dictionary.Values)
			{
				NetTrack(value2.Order).ProcessedFills = value2.ProcessedFills;
			}
			Print("[RBE] Recovered owned native lifecycle on replacement chart; shared-account exposure was not adopted.");
		}
		else if (recoveryRecord != null && recoveryRecord.TradingDate == model.TradingDate)
		{
			buyTouched |= recoveryRecord.BuyTouched;
			sellTouched |= recoveryRecord.SellTouched;
			sessionBuyFills = Math.Max(sessionBuyFills, recoveryRecord.BuyFills);
			sessionSellFills = Math.Max(sessionSellFills, recoveryRecord.SellFills);
			cycle = Math.Max(cycle, recoveryRecord.Cycle);
		}
		recoveryBooting = false;
		SaveRecovery();
	}

	private bool SaveRecovery(RbeRecoveryOrder pending = null)
	{
		if (State != State.Realtime || recoveryStore == null || recoveryBooting)
		{
			return !recoveryWriteFault;
		}
		if (recoveryWriteFault)
		{
			return false;
		}
		try
		{
			RbeRecoveryRecord rbeRecoveryRecord = new RbeRecoveryRecord
			{
				Account = Account.Name,
				Instrument = Instrument.FullName,
				ExecutionMode = "NetExposure",
				TradeDirection = TradeDirection.ToString(),
				Owner = owner,
				SettingsFingerprint = recoveryFingerprint,
				SettingsXml = recoveryCanonicalSettings,
				LastQuoteTime = latestTime,
				LastBid = bid,
				LastAsk = ask,
				Last = last,
				ActualNet = netActual,
				BuyTouched = buyTouched,
				SellTouched = sellTouched,
				LongReady = netLongReady,
				ShortReady = netShortReady,
				BuyFills = sessionBuyFills,
				SellFills = sessionSellFills,
				Cycle = cycle,
				OrderSequence = cycle,
				NewsBlocked = newsBlocked,
				NewsBeEligible = newsBeEligible,
				Reconciling = netReconciling,
				CloseQuantity = netCloseQuantity,
				CloseValue = netCloseValue,
				CloseTime = netCloseTime,
				BrokerRestrictionReason = brokerRestrictionReason,
				RangeHighTime = rangeVisual.HighFormed,
				RangeLowTime = rangeVisual.LowFormed
			};
			if (recoveryRecord != null)
			{
				rbeRecoveryRecord.RetiredOwners.AddRange(recoveryRecord.RetiredOwners);
			}
			model.CaptureRecovery(rbeRecoveryRecord);
			rbeRecoveryRecord.FlowFailed = executionFailed;
			netBook.CaptureRecovery(rbeRecoveryRecord);
			rbeRecoveryRecord.Cutoff = netCutoff;
			rbeRecoveryRecord.Closing = netClosing;
			foreach (OwnedOrder value2 in orders.Values)
			{
				Order order = value2.Order;
				if (order != null && netIntents.TryGetValue(order.Name, out var value))
				{
					string role = value.Role.ToString();
					int side = ((value.Leg != null) ? value.Leg.Side : 0);
					double distance = value.Distance;
					RbeRecoveryOrder rbeRecoveryOrder = DescribeRecoveryOrder(order, role, side, distance, value2.ProcessedFills);
					if (recoveryLiveOrders.Contains(RbeRecoveryEvidence.OrderKey(rbeRecoveryOrder)))
					{
						rbeRecoveryRecord.Orders.Add(rbeRecoveryOrder);
					}
				}
			}
			RbeRecoveryEvidence.CarryLedger(rbeRecoveryRecord, recoveryRecord, pending);
			rbeRecoveryRecord.ExecutionIds = recoveryLiveExecutions.ToList();
			DateTime lastQuoteTime = rbeRecoveryRecord.LastQuoteTime;
			double lastBid = rbeRecoveryRecord.LastBid;
			double lastAsk = rbeRecoveryRecord.LastAsk;
			double num = rbeRecoveryRecord.Last;
			rbeRecoveryRecord.LastQuoteTime = DateTime.MinValue;
			rbeRecoveryRecord.LastBid = (rbeRecoveryRecord.LastAsk = (rbeRecoveryRecord.Last = 0.0));
			string text;
			using (StringWriter stringWriter = new StringWriter(CultureInfo.InvariantCulture))
			{
				RecoverySerializer.Serialize(stringWriter, rbeRecoveryRecord);
				text = stringWriter.ToString();
			}
			rbeRecoveryRecord.LastQuoteTime = lastQuoteTime;
			rbeRecoveryRecord.LastBid = lastBid;
			rbeRecoveryRecord.LastAsk = lastAsk;
			rbeRecoveryRecord.Last = num;
			if (text == recoveryPayload)
			{
				return true;
			}
			recoveryStore.Save(rbeRecoveryRecord);
			recoveryRecord = rbeRecoveryRecord;
			recoveryPayload = text;
			return true;
		}
		catch (Exception ex)
		{
			if (!recoveryWriteFault)
			{
				Print("[RBE] Recovery storage failed; new entries blocked: " + ex.Message);
			}
			recoveryWriteFault = true;
			status = "Recovery storage fault";
			return false;
		}
	}

	private void RecoveryLiveOrder(Order order)
	{
		if (State == State.Realtime && order != null && Owns(order))
		{
			recoveryLiveOrders.Add(RbeRecoveryEvidence.OrderKey(DescribeRecoveryOrder(order, "", 0, 0.0, 0)));
		}
	}

	private void RecoveryLiveFill(string id)
	{
		if (State == State.Realtime && !string.IsNullOrEmpty(id))
		{
			recoveryLiveExecutions.Add(id);
		}
	}

	private void CloseRecoveryStore()
	{
		if (recoveryStore != null)
		{
			recoveryStore.Dispose();
			recoveryStore = null;
		}
	}
}
}
namespace NinjaTrader.NinjaScript.Strategies.RBE_NT
{
internal sealed class RbeDashState
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

	internal string Mode;

	internal string Costs;

	internal bool InTrade;

	internal bool NewsBlocked;
}

internal sealed class RbeDashboard
{
	private readonly object sync = new object();

	private RbeDashState state;

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

	internal void Publish(RbeDashState next)
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
		RbeDashState rbeDashState;
		bool flag;
		double num;
		double num2;
		lock (sync)
		{
			rbeDashState = state;
			flag = collapsed;
			num = offsetX;
			num2 = offsetY;
		}
		if (rbeDashState == null || rt == null || chart == null)
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
		using (SolidColorBrush brush = new SolidColorBrush(rt, new Color4(12f / 255f, 1f / 15f, 27f / 255f, 1f)))
		{
			using SolidColorBrush brush2 = new SolidColorBrush(rt, new Color4(182f / 255f, 205f / 255f, 235f / 255f, 110f / 255f));
			using SolidColorBrush solidColorBrush = new SolidColorBrush(rt, new Color4(14f / 15f, 244f / 255f, 250f / 255f, 1f));
			using SolidColorBrush brush3 = new SolidColorBrush(rt, new Color4(165f / 255f, 181f / 255f, 0.8f, 1f));
			using SolidColorBrush brush4 = new SolidColorBrush(rt, new Color4(115f / 255f, 171f / 255f, 1f, 1f));
			using SolidColorBrush solidColorBrush2 = new SolidColorBrush(rt, new Color4(91f / 255f, 215f / 255f, 164f / 255f, 1f));
			using SolidColorBrush solidColorBrush3 = new SolidColorBrush(rt, new Color4(1f, 125f / 255f, 128f / 255f, 1f));
			using SharpDX.DirectWrite.Factory dw = new SharpDX.DirectWrite.Factory();
			rt.FillRoundedRectangle(roundedRect, brush);
			rt.DrawRoundedRectangle(roundedRect, brush2, 1f);
			rt.FillRectangle(new RectangleF(num3 + 12f, num4 + 14f, 2f, 39f), brush4);
			Text(rt, dw, "RANGE BREAKOUT", 13f, solidColorBrush, num3 + 24f, num4 + 13f, 143f, bold: true);
			Text(rt, dw, rbeDashState.Mode, 9f, brush3, num3 + 24f, num4 + 34f, 151f);
			Text(rt, dw, "NEW YORK", 8.5f, brush3, num6 - 98f, num4 + 13f, 80f, bold: false, right: true);
			Text(rt, dw, rbeDashState.Clock, 13f, solidColorBrush, num6 - 98f, num4 + 32f, 80f, bold: true, right: true);
			RoundedRectangle roundedRect2 = new RoundedRectangle
			{
				Rect = new RectangleF(num6 - 12f, num4 + 13f, 19f, 19f),
				RadiusX = 6f,
				RadiusY = 6f
			};
			rt.FillRoundedRectangle(roundedRect2, brush2);
			Text(rt, dw, flag ? "+" : "−", 13f, solidColorBrush, num6 - 12f, num4 + 14f, 19f, bold: false, right: false, center: true);
			if (!flag)
			{
				Rule(rt, brush2, num3 + 20f, num4 + 61f, 222f);
				Text(rt, dw, rbeDashState.Status, 11.5f, rbeDashState.NewsBlocked ? solidColorBrush3 : solidColorBrush, num3 + 20f, num4 + 69f, 222f);
				Text(rt, dw, "SESSION RANGE  ·  20:05–23:05", 9f, brush3, num3 + 20f, num4 + 95f, 184f);
				Text(rt, dw, rbeDashState.RangeWidth, 13f, solidColorBrush, num6 - 55f, num4 + 92f, 55f, bold: true, right: true);
				Text(rt, dw, "HIGH", 9f, solidColorBrush2, num3 + 20f, num4 + 122f, 30f);
				Text(rt, dw, rbeDashState.RangeHigh, 13f, solidColorBrush, num3 + 57f, num4 + 119f, 65f, bold: true, right: true);
				Text(rt, dw, "LOW", 9f, solidColorBrush3, num3 + 140f, num4 + 122f, 30f);
				Text(rt, dw, rbeDashState.RangeLow, 13f, solidColorBrush, num3 + 177f, num4 + 119f, 65f, bold: true, right: true);
				Rule(rt, brush2, num3 + 20f, num4 + 149f, 222f);
				Text(rt, dw, "POSITION", 9f, brush3, num3 + 20f, num4 + 159f, 106f);
				Text(rt, dw, "HARD STOP", 9f, brush3, num3 + 139f, num4 + 159f, num6 - num3 - 139f, bold: false, right: true);
				Text(rt, dw, rbeDashState.Position, 13f, rbeDashState.InTrade ? solidColorBrush2 : solidColorBrush, num3 + 20f, num4 + 174f, 106f, bold: true);
				Text(rt, dw, rbeDashState.Stop, 13f, solidColorBrush3, num3 + 139f, num4 + 174f, num6 - num3 - 139f, bold: true, right: true);
				Rule(rt, brush2, num3 + 20f, num4 + 199f, 222f);
				Text(rt, dw, rbeDashState.Risk, 11.5f, solidColorBrush, num3 + 20f, num4 + 210f, 222f);
				Text(rt, dw, rbeDashState.Costs, 9.5f, brush3, num3 + 20f, num4 + 229f, 222f);
				Text(rt, dw, rbeDashState.History, 8.5f, brush3, num3 + 20f, num4 + 248f, 222f);
			}
		}
		lock (sync)
		{
			shellRect = new Rect(num3, num4, 258.0, num5);
			headerRect = new Rect(num3, num4, 258.0, 64.0);
			toggleRect = new Rect(num6 - 15f, num4 + 10f, 25.0, 25.0);
		}
	}

	private static void Text(RenderTarget rt, SharpDX.DirectWrite.Factory dw, string value, float size, SolidColorBrush brush, float x, float y, float width, bool bold = false, bool right = false, bool center = false)
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

	private static void Rule(RenderTarget rt, SolidColorBrush brush, float x, float y, float width)
	{
		rt.DrawLine(new Vector2(x, y), new Vector2(x + width, y), brush, 0.5f);
	}
}

public static class RbeHistory
{
	public static bool IsRestartOwnedOrder(string owner, string name, string entrySignal, bool working)
	{
		if (!working || string.IsNullOrEmpty(owner))
		{
			return false;
		}
		string value = owner + "_";
		return (!string.IsNullOrEmpty(name) && name.StartsWith(value, StringComparison.Ordinal)) || (!string.IsNullOrEmpty(entrySignal) && entrySignal.StartsWith(value, StringComparison.Ordinal));
	}

	public static bool SubmitCutoff(DateTime tradingDate, DateTime ny, bool historical)
	{
		if (tradingDate == DateTime.MinValue)
		{
			return false;
		}
		DateTime dateTime = tradingDate.Date.AddHours(11.0).AddMinutes(55.0);
		return ny >= (historical ? dateTime.AddSeconds(-1.0) : dateTime);
	}

	public static bool CanReplayCompletedSession(DateTime tradingDate, DateTime historicalEndNy)
	{
		return tradingDate != DateTime.MinValue && historicalEndNy >= tradingDate.Date.AddHours(11.0).AddMinutes(57.0);
	}

	public static bool CanSubmitNativeStop(int sign, double stop, double currentHigh, double currentLow, double processingHigh, double processingLow)
	{
		return (sign > 0) ? (stop > Math.Max(currentHigh, processingHigh)) : (stop < Math.Min(currentLow, processingLow));
	}
}

public sealed class RbeModel
{
	private readonly RbeSettings settings;

	private static readonly TimeZoneInfo NewYork = TimeZoneInfo.FindSystemTimeZoneById("Eastern Standard Time");

	public DateTime TradingDate { get; private set; }

	public DateTime RangeStart { get; private set; }

	public DateTime RangeEnd { get; private set; }

	public double High { get; private set; }

	public double Low { get; private set; }

	public bool Locked { get; private set; }

	public bool RangeAccepted => Locked && High > 0.0 && Low > 0.0 && High - Low <= settings.MaximumRangePrice && 100.0 * (High - Low) / High >= settings.MinimumRangePercent;

	public RbeModel(RbeSettings settings)
	{
		this.settings = settings;
	}

	public void CaptureRecovery(RbeRecoveryRecord record)
	{
		if (record == null)
		{
			throw new ArgumentNullException("record");
		}
		record.TradingDate = TradingDate;
		record.RangeStart = RangeStart;
		record.RangeEnd = RangeEnd;
		record.RangeHigh = High;
		record.RangeLow = Low;
		record.RangeLocked = Locked;
	}

	public void RestoreRecovery(RbeRecoveryRecord record)
	{
		if (record == null)
		{
			throw new ArgumentNullException("record");
		}
		if (record.TradingDate == DateTime.MinValue)
		{
			if (record.RangeStart != DateTime.MinValue || record.RangeEnd != DateTime.MinValue || record.RangeHigh != 0.0 || record.RangeLow != 0.0 || record.RangeLocked)
			{
				throw new InvalidOperationException("Invalid recovered RBE empty range state.");
			}
			DateTime dateTime = (RangeEnd = DateTime.MinValue);
			DateTime tradingDate = (RangeStart = dateTime);
			TradingDate = tradingDate;
			double high = (Low = 0.0);
			High = high;
			Locked = false;
		}
		else
		{
			if (record.TradingDate != record.TradingDate.Date || record.RangeStart != record.TradingDate.AddDays(-1.0).AddHours(20.0).AddMinutes(5.0) || record.RangeEnd != record.TradingDate.AddDays(-1.0).AddHours(23.0).AddMinutes(5.0) || double.IsNaN(record.RangeHigh) || double.IsInfinity(record.RangeHigh) || double.IsNaN(record.RangeLow) || double.IsInfinity(record.RangeLow) || record.RangeHigh < 0.0 || record.RangeLow < 0.0 || record.RangeHigh < record.RangeLow || (record.RangeLocked && record.RangeLow <= 0.0))
			{
				throw new InvalidOperationException("Invalid recovered RBE range state.");
			}
			TradingDate = record.TradingDate;
			RangeStart = record.RangeStart;
			RangeEnd = record.RangeEnd;
			High = record.RangeHigh;
			Low = record.RangeLow;
			Locked = record.RangeLocked;
		}
	}

	public static DateTime ToNewYork(DateTime time, TimeZoneInfo source)
	{
		return TimeZoneInfo.ConvertTime(DateTime.SpecifyKind(time, DateTimeKind.Unspecified), source, NewYork);
	}

	public static DateTime DayKey(DateTime ny)
	{
		return (ny.TimeOfDay >= TimeSpan.FromHours(17.0)) ? ny.Date.AddDays(1.0) : ny.Date;
	}

	public bool OnQuote(DateTime ny, double rangePrice)
	{
		DateTime dateTime = DayKey(ny);
		bool flag = dateTime != TradingDate;
		if (flag)
		{
			TradingDate = dateTime;
			RangeStart = dateTime.AddDays(-1.0).AddHours(20.0).AddMinutes(5.0);
			RangeEnd = dateTime.AddDays(-1.0).AddHours(23.0).AddMinutes(5.0);
			double high = (Low = 0.0);
			High = high;
			Locked = false;
		}
		if (Locked || ny < RangeStart || rangePrice <= 0.0)
		{
			return flag;
		}
		if (ny < RangeEnd.AddMinutes(1.0))
		{
			High = ((High == 0.0) ? rangePrice : Math.Max(High, rangePrice));
			Low = ((Low == 0.0) ? rangePrice : Math.Min(Low, rangePrice));
		}
		if (ny >= RangeEnd)
		{
			Locked = true;
		}
		return flag;
	}

	public bool Expired(DateTime ny)
	{
		return ny >= TradingDate.AddHours(11.0).AddMinutes(55.0);
	}

	public double InitialStop(bool buy, double tick)
	{
		double num = (buy ? Up(High, tick) : Down(Low, tick));
		double num2 = (buy ? High : Low) * settings.StopPercent / 100.0;
		return buy ? Down(num - num2, tick) : Up(num + num2, tick);
	}

	public static double Down(double price, double tick)
	{
		return Math.Floor(price / tick + 1E-09) * tick;
	}

	public static double Up(double price, double tick)
	{
		return Math.Ceiling(price / tick - 1E-09) * tick;
	}

	public static int Quantity(double entry, double stop, double pointValue, double roundTripCost, double budget, int capacity, bool enforceRiskLimit)
	{
		double num = Math.Abs(entry - stop) * pointValue + roundTripCost;
		if (budget <= 0.0 || pointValue <= 0.0 || num <= 0.0 || capacity <= 0)
		{
			return 0;
		}
		int num2 = (int)Math.Min(capacity, Math.Floor(budget / num));
		return enforceRiskLimit ? num2 : Math.Max(1, num2);
	}
}

public sealed class RbeNetBook
{
	private readonly RbeSettings settings;

	private readonly double tick;

	private readonly double pointValue;

	private readonly double cost;

	private bool cutoff;

	public RbeNetLeg Long { get; private set; }

	public RbeNetLeg Short { get; private set; }

	public bool Active => Long.Active || Short.Active;

	public int Target => (Long.Active ? Long.Quantity : 0) - (Short.Active ? Short.Quantity : 0);

	public event Action<RbeNetLeg> Opened;

	public event Action<RbeNetLeg> Closed;

	public RbeNetBook(RbeSettings settings, double tick, double pointValue, double cost)
	{
		this.settings = settings;
		this.tick = tick;
		this.pointValue = pointValue;
		this.cost = cost;
		Long = new RbeNetLeg
		{
			Side = 1
		};
		Short = new RbeNetLeg
		{
			Side = -1
		};
	}

	public void CaptureRecovery(RbeRecoveryRecord record)
	{
		if (record == null)
		{
			throw new ArgumentNullException("record");
		}
		record.Long = CaptureLeg(Long);
		record.Short = CaptureLeg(Short);
		record.Cutoff = cutoff;
	}

	private static RbeRecoveryLeg CaptureLeg(RbeNetLeg leg)
	{
		RbeRecoveryLeg rbeRecoveryLeg = new RbeRecoveryLeg
		{
			Side = leg.Side,
			Quantity = leg.Quantity,
			FilledQuantity = leg.FilledQuantity,
			ExitedQuantity = leg.ExitedQuantity,
			Entry = leg.Entry,
			Exit = leg.Exit,
			EntryTime = leg.EntryTime,
			ExitTime = leg.ExitTime,
			Used = leg.Used,
			Active = leg.Active,
			ExitStarted = leg.ExitStarted
		};
		if (leg.Protection != null)
		{
			leg.Protection.CaptureRecovery(rbeRecoveryLeg);
		}
		if (leg.Visual != null)
		{
			rbeRecoveryLeg.InitialStop = leg.Visual.InitialStop;
		}
		return rbeRecoveryLeg;
	}

	public void RestoreRecovery(RbeRecoveryRecord record)
	{
		if (record == null)
		{
			throw new ArgumentNullException("record");
		}
		RbeNetLeg rbeNetLeg = RestoreLeg(record.Long, 1);
		RbeNetLeg rbeNetLeg2 = RestoreLeg(record.Short, -1);
		Long = rbeNetLeg;
		Short = rbeNetLeg2;
		cutoff = record.Cutoff;
	}

	private RbeNetLeg RestoreLeg(RbeRecoveryLeg saved, int side)
	{
		if (saved == null || saved.Side != side || saved.Quantity < 0 || saved.FilledQuantity < 0 || saved.ExitedQuantity < 0 || saved.ExitedQuantity > saved.FilledQuantity || (saved.Active && (!saved.Used || saved.Quantity <= 0 || saved.Quantity != saved.FilledQuantity - saved.ExitedQuantity)))
		{
			throw new InvalidOperationException("Invalid recovered RBE net leg.");
		}
		RbePosition protection = (saved.Used ? RbePosition.RestoreRecovery(side, saved, settings) : null);
		return new RbeNetLeg
		{
			Side = side,
			Quantity = saved.Quantity,
			FilledQuantity = saved.FilledQuantity,
			ExitedQuantity = saved.ExitedQuantity,
			Entry = saved.Entry,
			Exit = saved.Exit,
			EntryTime = saved.EntryTime,
			ExitTime = saved.ExitTime,
			Used = saved.Used,
			Active = saved.Active,
			ExitStarted = saved.ExitStarted,
			Protection = protection
		};
	}

	public bool Open(int side, int quantity, double price, double distance, DateTime time)
	{
		if (side != 1 && side != -1)
		{
			throw new ArgumentOutOfRangeException("side");
		}
		RbeNetLeg rbeNetLeg = ((side == 1) ? Long : Short);
		if (cutoff || rbeNetLeg.Used || quantity <= 0 || price <= 0.0 || distance <= 0.0 || double.IsNaN(price) || double.IsInfinity(price) || double.IsNaN(distance) || double.IsInfinity(distance))
		{
			return false;
		}
		rbeNetLeg.Used = (rbeNetLeg.Active = true);
		rbeNetLeg.Quantity = quantity;
		rbeNetLeg.Entry = price;
		rbeNetLeg.EntryTime = time;
		rbeNetLeg.FilledQuantity = quantity;
		double stop = ((side == 1) ? RbeModel.Down(price - distance, tick) : RbeModel.Up(price + distance, tick));
		rbeNetLeg.Protection = new RbePosition(side == 1, price, stop, settings, pointValue, cost);
		if (Opened != null)
		{
			Opened(rbeNetLeg);
		}
		return true;
	}

	public void AddEntryFill(RbeNetLeg leg, int quantity, double price, double distance, DateTime time)
	{
		if (!leg.Used)
		{
			if (!Open(leg.Side, quantity, price, distance, time))
			{
				throw new InvalidOperationException("Invalid native book entry");
			}
			return;
		}
		if (!leg.Active || leg.ExitStarted)
		{
			throw new InvalidOperationException("Entry arrived after leg exit");
		}
		leg.Entry = (leg.Entry * (double)leg.FilledQuantity + price * (double)quantity) / (double)(leg.FilledQuantity + quantity);
		leg.FilledQuantity += quantity;
		leg.Quantity += quantity;
		double val = ((leg.Side == 1) ? RbeModel.Down(leg.Entry - distance, tick) : RbeModel.Up(leg.Entry + distance, tick));
		val = ((leg.Side == 1) ? Math.Max(val, leg.Protection.Stop) : Math.Min(val, leg.Protection.Stop));
		leg.Protection = new RbePosition(leg.Side == 1, leg.Entry, val, settings, pointValue, cost);
		if (leg.Visual != null)
		{
			leg.Visual.Entry = leg.Entry;
			leg.Visual.UpdateStop(val, time);
		}
	}

	public void AddExitFill(RbeNetLeg leg, int quantity, double price, DateTime time)
	{
		if (leg == null || !leg.Active || quantity <= 0 || quantity > leg.Quantity)
		{
			throw new InvalidOperationException("Native exit exceeds its owned leg");
		}
		leg.ExitStarted = true;
		leg.Exit = (leg.Exit * (double)leg.ExitedQuantity + price * (double)quantity) / (double)(leg.ExitedQuantity + quantity);
		leg.ExitedQuantity += quantity;
		leg.Quantity -= quantity;
		leg.ExitTime = time;
		if (leg.Quantity == 0)
		{
			leg.Active = false;
			if (Closed != null)
			{
				Closed(leg);
			}
		}
	}

	public void ManageNative(double bid, double ask, DateTime time)
	{
		RbeNetLeg[] array = new RbeNetLeg[2] { Long, Short };
		foreach (RbeNetLeg rbeNetLeg in array)
		{
			if (rbeNetLeg.Active && !rbeNetLeg.ExitStarted && time >= rbeNetLeg.EntryTime)
			{
				double num = ((rbeNetLeg.Side == 1) ? bid : ask);
				if (num > 0.0 && ((rbeNetLeg.Side == 1) ? (num > rbeNetLeg.Protection.Stop) : (num < rbeNetLeg.Protection.Stop)))
				{
					rbeNetLeg.Protection.UpdateStop(num, tick);
				}
			}
		}
	}

	public void Observe(double bid, double ask, DateTime time)
	{
		Visit(Long, bid, time);
		Visit(Short, ask, time);
	}

	private void Visit(RbeNetLeg leg, double mark, DateTime time)
	{
		if (leg.Active && !(time < leg.EntryTime) && !(mark <= 0.0))
		{
			if ((leg.Side == 1) ? (mark <= leg.Protection.Stop) : (mark >= leg.Protection.Stop))
			{
				Close(leg, mark, time);
			}
			else
			{
				leg.Protection.UpdateStop(mark, tick);
			}
		}
	}

	public void StopSide(int side, double price, DateTime time)
	{
		Close((side == 1) ? Long : Short, price, time);
	}

	public void StopLeg(RbeNetLeg leg, double price, DateTime time)
	{
		if (leg != null)
		{
			Close(leg, price, time);
		}
	}

	private void Close(RbeNetLeg leg, double price, DateTime time)
	{
		if (leg.Active)
		{
			leg.Active = false;
			leg.Exit = price;
			leg.ExitTime = time;
			if (Closed != null)
			{
				Closed(leg);
			}
		}
	}

	public void Flatten(double bid, double ask, DateTime time)
	{
		cutoff = true;
		CloseTrades(bid, ask, time);
	}

	public void CloseTrades(double bid, double ask, DateTime time)
	{
		Close(Long, bid, time);
		Close(Short, ask, time);
	}

	public void ProtectAtCost(double bid, double ask, double effectiveCost)
	{
		if (Long.Active)
		{
			Long.Protection.ProtectAtCost(bid, tick, effectiveCost, pointValue);
		}
		if (Short.Active)
		{
			Short.Protection.ProtectAtCost(ask, tick, effectiveCost, pointValue);
		}
	}

	public void NewSession(double bid, double ask, DateTime time)
	{
		Flatten(bid, ask, time);
		Long = new RbeNetLeg
		{
			Side = 1
		};
		Short = new RbeNetLeg
		{
			Side = -1
		};
		cutoff = false;
	}

	public static int Adjustment(int actual, int target)
	{
		return target - actual;
	}
}

public sealed class RbeNetLeg
{
	public int Side;

	public int Quantity;

	public int FilledQuantity;

	public int ExitedQuantity;

	public double Entry;

	public double Exit;

	public DateTime EntryTime;

	public DateTime ExitTime;

	public RbePosition Protection;

	public RbeTradeVisual Visual;

	public bool Used;

	public bool Active;

	public bool ExitStarted;
}

public static class RbeNetOrderGate
{
	public static bool Pending(bool terminal, int reported, int processed)
	{
		return !terminal || processed < reported;
	}
}

public sealed class RbePosition
{
	private readonly RbeSettings settings;

	private readonly bool buy;

	private readonly double fill;

	private readonly double coveredPrice;

	private readonly double initialStop;

	public bool CostCovered { get; private set; }

	public double Stop { get; private set; }

	public RbePosition(bool buy, double fill, double stop, RbeSettings settings, double pointValue, double roundTripCost)
	{
		this.buy = buy;
		this.fill = fill;
		this.settings = settings;
		Stop = stop;
		initialStop = stop;
		CostCovered = !settings.CoverCosts;
		double num = roundTripCost / pointValue * Math.Max(1.0, settings.CostCoverageMultiple);
		coveredPrice = (buy ? (fill + num) : (fill - num));
	}

	private RbePosition(bool buy, RbeRecoveryLeg leg, RbeSettings settings)
	{
		this.buy = buy;
		this.settings = settings;
		fill = leg.Entry;
		Stop = leg.Stop;
		initialStop = leg.InitialStop;
		coveredPrice = leg.CoveredPrice;
		CostCovered = leg.CostCovered;
	}

	public void CaptureRecovery(RbeRecoveryLeg leg)
	{
		if (leg == null)
		{
			throw new ArgumentNullException("leg");
		}
		leg.Side = (buy ? 1 : (-1));
		leg.Entry = fill;
		leg.Stop = Stop;
		leg.InitialStop = initialStop;
		leg.CoveredPrice = coveredPrice;
		leg.CostCovered = CostCovered;
	}

	public static RbePosition RestoreRecovery(int side, RbeRecoveryLeg leg, RbeSettings settings)
	{
		if (leg == null || settings == null)
		{
			throw new ArgumentNullException((leg == null) ? "leg" : "settings");
		}
		if ((side != 1 && side != -1) || leg.Side != side || leg.Entry <= 0.0 || leg.Stop <= 0.0 || leg.InitialStop <= 0.0 || leg.CoveredPrice <= 0.0)
		{
			throw new InvalidOperationException("Invalid recovered RBE protection state.");
		}
		double[] array = new double[4] { leg.Entry, leg.Stop, leg.InitialStop, leg.CoveredPrice };
		foreach (double d in array)
		{
			if (double.IsNaN(d) || double.IsInfinity(d))
			{
				throw new InvalidOperationException("Non-finite recovered RBE protection state.");
			}
		}
		if ((side == 1) ? (leg.Stop < leg.InitialStop) : (leg.Stop > leg.InitialStop))
		{
			throw new InvalidOperationException("Recovered RBE stop loosens initial protection.");
		}
		return new RbePosition(side == 1, leg, settings);
	}

	public double UpdateStop(double mark, double tick)
	{
		if (!CostCovered && (buy ? (mark >= coveredPrice) : (mark <= coveredPrice)))
		{
			CostCovered = true;
		}
		double num = 100.0 * (buy ? (mark - fill) : (fill - mark)) / fill;
		if (!CostCovered || (settings.TrailTriggerPercent > 0.0 && num < settings.TrailTriggerPercent))
		{
			return Stop;
		}
		double num2 = fill * settings.TrailDistancePercent / 100.0;
		double num3 = (buy ? RbeModel.Down(mark - num2, tick) : RbeModel.Up(mark + num2, tick));
		if (buy ? (num3 > Stop + settings.TrailStepPrice + 1E-09) : (num3 < Stop - settings.TrailStepPrice - 1E-09))
		{
			Stop = num3;
		}
		return Stop;
	}

	public double ProtectAtCost(double mark, double tick, double roundTripCost, double pointValue)
	{
		double num = CostCoveredStop(tick, roundTripCost, pointValue);
		bool num2;
		if (!buy)
		{
			if (num < Stop - tick / 2.0)
			{
				num2 = num > mark + tick;
				goto IL_0052;
			}
		}
		else if (num > Stop + tick / 2.0)
		{
			num2 = num < mark - tick;
			goto IL_0052;
		}
		goto IL_005e;
		IL_0052:
		if (num2)
		{
			Stop = num;
		}
		goto IL_005e;
		IL_005e:
		return Stop;
	}

	public double CostCoveredStop(double tick, double roundTripCost, double pointValue)
	{
		double num = roundTripCost / pointValue * Math.Max(1.0, settings.CostCoverageMultiple);
		return buy ? RbeModel.Up(fill + num, tick) : RbeModel.Down(fill - num, tick);
	}
}

public sealed class RbeRangeVisual
{
	public DateTime Day;

	public DateTime Left;

	public DateTime Right;

	public DateTime HighFormed;

	public DateTime LowFormed;

	public DateTime HighTouch;

	public DateTime LowTouch;

	public DateTime Now;

	public double High;

	public double Low;

	public bool Expired;

	private readonly bool buy;

	private readonly bool sell;

	private bool rangeLocked;

	public bool ShowHigh => buy && (HighTouch != DateTime.MinValue || !Expired);

	public bool ShowLow => sell && (LowTouch != DateTime.MinValue || !Expired);

	public RbeRangeVisual(bool buy, bool sell)
	{
		this.buy = buy;
		this.sell = sell;
	}

	private static DateTime MinuteStart(DateTime t)
	{
		return new DateTime(t.Year, t.Month, t.Day, t.Hour, t.Minute, 0);
	}

	public void Observe(RbeModel model, DateTime time, DateTime ny, double price)
	{
		if (Day != model.TradingDate)
		{
			Day = model.TradingDate;
			Left = (Right = (HighFormed = (LowFormed = (HighTouch = (LowTouch = DateTime.MinValue)))));
			High = (Low = 0.0);
			Expired = (rangeLocked = false);
		}
		Now = time;
		Expired = model.Expired(ny);
		if (model.High <= 0.0)
		{
			return;
		}
		DateTime dateTime = MinuteStart(time);
		if (Left == DateTime.MinValue)
		{
			Left = dateTime;
		}
		if (model.High != High)
		{
			HighFormed = dateTime;
		}
		if (model.Low != Low)
		{
			LowFormed = dateTime;
		}
		if (!rangeLocked || model.High != High || model.Low != Low || Right == DateTime.MinValue)
		{
			Right = dateTime.AddMinutes(1.0).AddSeconds(-1.0);
		}
		rangeLocked = model.Locked;
		High = model.High;
		Low = model.Low;
		if (model.RangeAccepted && !Expired)
		{
			if (buy && HighTouch == DateTime.MinValue && price >= High)
			{
				HighTouch = dateTime.AddMinutes(1.0).AddSeconds(-1.0);
			}
			if (sell && LowTouch == DateTime.MinValue && price <= Low)
			{
				LowTouch = dateTime.AddMinutes(1.0).AddSeconds(-1.0);
			}
		}
	}

	public void EndDay()
	{
		Expired = true;
	}

	public RbeRangeVisual Snapshot()
	{
		return (RbeRangeVisual)MemberwiseClone();
	}
}

public static class RbeRecoveryEvidence
{
	public static bool SameBrokerAction(string expected, string observed)
	{
		return ((expected == "Buy" || expected == "BuyToCover") && (observed == "Buy" || observed == "BuyToCover")) || ((expected == "Sell" || expected == "SellShort") && (observed == "Sell" || observed == "SellShort"));
	}

	public static string OrderKey(RbeRecoveryOrder order)
	{
		return order.Name + (string.IsNullOrEmpty(order.Signal) ? "" : ("|" + order.Signal));
	}

	public static void CarryLedger(RbeRecoveryRecord next, RbeRecoveryRecord previous, RbeRecoveryOrder pending)
	{
		HashSet<string> hashSet = new HashSet<string>(StringComparer.Ordinal);
		foreach (RbeRecoveryOrder order in next.Orders)
		{
			hashSet.Add(OrderKey(order));
		}
		if (pending != null && hashSet.Add(OrderKey(pending)))
		{
			next.Orders.Add(pending);
		}
		if (previous == null)
		{
			return;
		}
		foreach (RbeRecoveryOrder order2 in previous.Orders)
		{
			if (hashSet.Add(OrderKey(order2)))
			{
				next.Orders.Add(order2);
			}
		}
	}

	public static Dictionary<string, RbeRecoveryOrder> Match(RbeRecoveryRecord record, IEnumerable<RbeRecoveryOrder> observed)
	{
		Dictionary<string, RbeRecoveryOrder> dictionary = new Dictionary<string, RbeRecoveryOrder>(StringComparer.Ordinal);
		foreach (RbeRecoveryOrder order in record.Orders)
		{
			dictionary.Add(OrderKey(order), order);
		}
		Dictionary<string, RbeRecoveryOrder> dictionary2 = new Dictionary<string, RbeRecoveryOrder>(StringComparer.Ordinal);
		foreach (RbeRecoveryOrder item in observed)
		{
			if (item != null && !string.IsNullOrEmpty(item.Name) && (item.Name.StartsWith(record.Owner + "_", StringComparison.Ordinal) || (!string.IsNullOrEmpty(item.Signal) && item.Signal.StartsWith(record.Owner + "_", StringComparison.Ordinal))))
			{
				string key = OrderKey(item);
				if (!dictionary.TryGetValue(key, out var value) || dictionary2.ContainsKey(key))
				{
					throw new InvalidOperationException("Unknown or duplicate RBE owned order: " + item.Name);
				}
				if (item.State == "Unknown")
				{
					throw new InvalidOperationException("RBE recovery pending: owned broker order status is Unknown: " + item.Name);
				}
				if (string.IsNullOrEmpty(value.OrderId) || item.OrderId != value.OrderId || !SameBrokerAction(value.Action, item.Action) || value.Type != item.Type || value.Quantity != item.Quantity || value.Limit != item.Limit || item.ReportedFilled < value.ProcessedFilled)
				{
					throw new InvalidOperationException("RBE order lineage/quantity mismatch: " + item.Name + " | saved: id=" + value.OrderId + ", action=" + value.Action + ", type=" + value.Type + ", qty=" + value.Quantity + ", limit=" + value.Limit.ToString("R", CultureInfo.InvariantCulture) + ", processed=" + value.ProcessedFilled + ", reported=" + value.ReportedFilled + ", state=" + value.State + " | observed: id=" + item.OrderId + ", action=" + item.Action + ", type=" + item.Type + ", qty=" + item.Quantity + ", limit=" + item.Limit.ToString("R", CultureInfo.InvariantCulture) + ", reported=" + item.ReportedFilled + ", state=" + item.State);
				}
				bool flag = value.Role == "Protection" && ((value.Side == 1) ? (item.Stop >= value.Stop) : (item.Stop <= value.Stop));
				if (item.Stop != value.Stop && !flag)
				{
					throw new InvalidOperationException("RBE order stop changed or widened: " + item.Name);
				}
				dictionary2.Add(key, item);
			}
		}
		foreach (RbeRecoveryOrder order2 in record.Orders)
		{
			if (!dictionary2.ContainsKey(OrderKey(order2)) && (!order2.Terminal || order2.ReportedFilled != order2.ProcessedFilled || !order2.SubmissionAcknowledged))
			{
				throw new InvalidOperationException("Missing owned broker evidence: " + order2.Name);
			}
		}
		return dictionary2;
	}
}

public sealed class RbeRecoveryLeg
{
	public int Side;

	public int Quantity;

	public int FilledQuantity;

	public int ExitedQuantity;

	public double Entry;

	public double Exit;

	public double InitialStop;

	public double Stop;

	public double CoveredPrice;

	public double HighWater;

	public DateTime EntryTime;

	public DateTime ExitTime;

	public bool Used;

	public bool Active;

	public bool ExitStarted;

	public bool CostCovered;
}

public sealed class RbeRecoveryOrder
{
	public string Name;

	public string Signal;

	public string OrderId;

	public string Role;

	public string Action;

	public string Type;

	public string State;

	public string Oco;

	public int Side;

	public int Quantity;

	public int ReportedFilled;

	public int ProcessedFilled;

	public double Limit;

	public double Stop;

	public double Distance;

	public double AverageFill;

	public DateTime Time;

	public bool Terminal;

	public bool SubmissionAcknowledged;
}

public sealed class RbeRecoveryRecord
{
	public int Version = 1;

	public long Generation;

	public DateTime SavedUtc;

	public string Account;

	public string Instrument;

	public string ExecutionMode;

	public string TradeDirection;

	public string Owner;

	public string SettingsFingerprint;

	public string SettingsXml;

	// Optional v1 XML field: absent in legacy checkpoints, never cleared by technical recovery.
	public string BrokerRestrictionReason;

	public DateTime TradingDate;

	public DateTime RangeStart;

	public DateTime RangeEnd;

	public DateTime RangeHighTime;

	public DateTime RangeLowTime;

	public DateTime LastQuoteTime;

	public double RangeHigh;

	public double RangeLow;

	public double LastBid;

	public double LastAsk;

	public double Last;

	public bool RangeLocked;

	public bool BuyTouched;

	public bool SellTouched;

	public bool LongReady;

	public bool ShortReady;

	public bool Cutoff;

	public bool Closing;

	public bool NewsBlocked;

	public bool NewsBeEligible;

	public int ActualNet;

	public int BuyFills;

	public int SellFills;

	public int OrderSequence;

	public int Cycle;

	public int FlowSide;

	public int FlowQuantity;

	public int FlowPendingSide;

	public int FlowEntrySide;

	public int FlowEntryReported;

	public int FlowEntryExecuted;

	public double FlowAveragePrice;

	public bool FlowBuyUsed;

	public bool FlowSellUsed;

	public bool FlowFailed;

	public bool FlowEntryTerminal;

	public bool FlowExitOutstanding;

	public bool Reconciling;

	public int CloseQuantity;

	public double CloseValue;

	public DateTime CloseTime;

	public string LongSignal;

	public string ShortSignal;

	public string CloseSignal;

	public double ActiveDistance;

	public RbeRecoveryLeg Long = new RbeRecoveryLeg
	{
		Side = 1
	};

	public RbeRecoveryLeg Short = new RbeRecoveryLeg
	{
		Side = -1
	};

	public List<RbeRecoveryOrder> Orders = new List<RbeRecoveryOrder>();

	public List<string> ExecutionIds = new List<string>();

	public List<string> RetiredOwners = new List<string>();
}

public sealed class RbeRecoveryStore : IDisposable
{
	public const int Version = 1;

	private static readonly XmlSerializer Serializer = new XmlSerializer(typeof(RbeRecoveryRecord));

	private readonly string account;

	private readonly string instrument;

	private readonly string mode;

	private readonly string direction;

	private readonly FileStream ownership;

	private readonly object gate = new object();

	private bool disposed;

	private bool loaded;

	private long generation;

	private string fingerprint;

	private string savedOwner;

	public string Path { get; private set; }

	// Set by Load() when a checkpoint saved under different settings held no live state and the new settings were adopted.
	public string AdoptedFromFingerprint { get; private set; }

	private RbeRecoveryStore(string directory, string account, string instrument, string mode, string direction)
	{
		this.account = Required(account, "account");
		this.instrument = Required(instrument, "instrument");
		this.mode = Required(mode, "execution mode");
		this.direction = Required(direction, "trade direction");
		Directory.CreateDirectory(directory);
		Path = System.IO.Path.Combine(directory, Key(account, instrument, mode, direction) + ".xml");
		try
		{
			ownership = new FileStream(Path + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
		}
		catch (IOException innerException)
		{
			throw new InvalidOperationException("RBE recovery ownership unavailable; another executor may own this account/contract/mode/direction.", innerException);
		}
	}

	public static RbeRecoveryStore Acquire(string directory, string account, string instrument, string executionMode, string tradeDirection)
	{
		return new RbeRecoveryStore(directory, account, instrument, executionMode, tradeDirection);
	}

	public static string Key(string account, string instrument, string executionMode, string tradeDirection)
	{
		StringBuilder stringBuilder = new StringBuilder();
		string[] array = new string[4] { account, instrument, executionMode, tradeDirection };
		foreach (string text in array)
		{
			Required(text, "recovery key component");
			stringBuilder.Append(text.Length.ToString(CultureInfo.InvariantCulture)).Append(':').Append(text);
		}
		return Fingerprint(stringBuilder.ToString());
	}

	public static string Fingerprint(string canonicalSettings)
	{
		using SHA256 sHA = SHA256.Create();
		byte[] array = sHA.ComputeHash(Encoding.UTF8.GetBytes(Required(canonicalSettings, "settings")));
		StringBuilder stringBuilder = new StringBuilder(array.Length * 2);
		byte[] array2 = array;
		foreach (byte b in array2)
		{
			stringBuilder.Append(b.ToString("x2", CultureInfo.InvariantCulture));
		}
		return stringBuilder.ToString();
	}

	public RbeRecoveryRecord Load(string expectedFingerprint)
	{
		lock (gate)
		{
			EnsureOpen();
			loaded = false;
			Required(expectedFingerprint, "expected settings fingerprint");
			if (!File.Exists(Path))
			{
				if (File.Exists(Path + ".previous"))
				{
					throw new InvalidOperationException("RBE recovery checkpoint missing while its previous generation exists; reconciliation required.");
				}
				fingerprint = expectedFingerprint;
				loaded = true;
				return null;
			}
			try
			{
				XmlReaderSettings settings = new XmlReaderSettings
				{
					DtdProcessing = DtdProcessing.Prohibit,
					XmlResolver = null
				};
				RbeRecoveryRecord rbeRecoveryRecord;
				using (FileStream input = new FileStream(Path, FileMode.Open, FileAccess.Read, FileShare.Read))
				{
					using XmlReader reader = XmlReader.Create(input, settings);
					XmlDocument xmlDocument = new XmlDocument
					{
						XmlResolver = null
					};
					xmlDocument.Load(reader);
					if (xmlDocument.DocumentElement == null || xmlDocument.DocumentElement.SelectSingleNode("Version") == null || xmlDocument.DocumentElement.SelectSingleNode("Generation") == null || xmlDocument.DocumentElement.SelectSingleNode("SavedUtc") == null)
					{
						throw new InvalidOperationException("Incomplete RBE recovery checkpoint header.");
					}
					using XmlNodeReader xmlReader = new XmlNodeReader(xmlDocument);
					rbeRecoveryRecord = (RbeRecoveryRecord)Serializer.Deserialize(xmlReader);
				}
				Validate(rbeRecoveryRecord);
				AdoptedFromFingerprint = null;
				if (!string.Equals(rbeRecoveryRecord.SettingsFingerprint, expectedFingerprint, StringComparison.Ordinal))
				{
					string liveStateReason = LiveStateReason(rbeRecoveryRecord);
					if (liveStateReason != null)
					{
						throw new InvalidOperationException("RBE recovery settings mismatch; saved live state (" + liveStateReason + ") must be reconciled before settings change. Saved fingerprint=" + rbeRecoveryRecord.SettingsFingerprint + "; requested fingerprint=" + expectedFingerprint + "; saved settings=" + ((rbeRecoveryRecord.SettingsXml == rbeRecoveryRecord.SettingsFingerprint) ? "legacy checkpoint contains only a hash" : rbeRecoveryRecord.SettingsXml));
					}
					// No live exposure in the checkpoint: nothing is protected by the old settings, so adopt the new ones.
					// The next SaveRecovery() writes the new fingerprint and settings.
					AdoptedFromFingerprint = rbeRecoveryRecord.SettingsFingerprint;
				}
				if (rbeRecoveryRecord.Generation < 1 || rbeRecoveryRecord.SavedUtc == default(DateTime))
				{
					throw new InvalidOperationException("Invalid RBE recovery checkpoint generation.");
				}
				generation = rbeRecoveryRecord.Generation;
				fingerprint = expectedFingerprint;
				savedOwner = rbeRecoveryRecord.Owner;
				loaded = true;
				return rbeRecoveryRecord;
			}
			catch (Exception ex)
			{
				throw new InvalidOperationException("RBE recovery checkpoint refused: " + ex.Message, ex);
			}
		}
	}

	private static string LiveStateReason(RbeRecoveryRecord record)
	{
		if (record.ActualNet != 0)
		{
			return "net position " + record.ActualNet.ToString(CultureInfo.InvariantCulture);
		}
		if (record.Long.Active || record.Short.Active)
		{
			return "active leg";
		}
		if (record.Reconciling)
		{
			return "reconciliation in progress";
		}
		if (record.FlowExitOutstanding)
		{
			return "exit outstanding";
		}
		foreach (RbeRecoveryOrder order in record.Orders)
		{
			if (!order.Terminal)
			{
				return "non-terminal order " + order.Name;
			}
			if (order.ReportedFilled != order.ProcessedFilled)
			{
				return "unprocessed fills on order " + order.Name;
			}
			if (!order.SubmissionAcknowledged)
			{
				return "unacknowledged order " + order.Name;
			}
		}
		return null;
	}

	public static string SettlementConfirmation(RbeRecoveryRecord record)
	{
		using StringWriter stringWriter = new StringWriter(CultureInfo.InvariantCulture);
		Serializer.Serialize(stringWriter, record);
		return "CLOSED " + Fingerprint(stringWriter.ToString()).Substring(0, 32) + " NO_ORDERS";
	}

	public RbeRecoveryRecord SettleExternal(RbeRecoveryRecord record, string confirmation, bool entriesDisabled, bool connectedFlat, bool noOwnedOrders)
	{
		lock (gate)
		{
			EnsureOpen();
			Validate(record);
			if (!loaded || record.Owner != savedOwner || record.Generation != generation || !entriesDisabled || !connectedFlat || !noOwnedOrders || record.ActualNet == 0 || confirmation != SettlementConfirmation(record))
			{
				throw new InvalidOperationException("RBE broker-close confirmation conditions not met.");
			}
			bool flag = false;
			foreach (RbeRecoveryOrder order in record.Orders)
			{
				if (order.Role == "Entry" && (!order.Terminal || !order.SubmissionAcknowledged || order.ReportedFilled != order.ProcessedFilled))
				{
					throw new InvalidOperationException("RBE entry evidence is not fully reconciled.");
				}
				flag |= order.Role == "Entry" && order.ProcessedFilled > 0;
			}
			if (!flag)
			{
				throw new InvalidOperationException("RBE owned opening evidence is missing.");
			}
			string text = Path + ".settlement_" + confirmation.Split(' ')[1];
			using (FileStream fileStream = new FileStream(text + ".before", FileMode.CreateNew, FileAccess.Write, FileShare.None))
			{
				byte[] array = File.ReadAllBytes(Path);
				fileStream.Write(array, 0, array.Length);
				fileStream.Flush(flushToDisk: true);
			}
			using (FileStream fileStream2 = new FileStream(text + ".receipt", FileMode.CreateNew, FileAccess.Write, FileShare.None))
			{
				byte[] bytes = Encoding.UTF8.GetBytes(DateTime.UtcNow.ToString("O") + "\n" + confirmation + "\nAdministrative closure; no invented fill or PnL.");
				fileStream2.Write(bytes, 0, bytes.Length);
				fileStream2.Flush(flushToDisk: true);
			}
			RbeRecoveryRecord rbeRecoveryRecord;
			using (StringWriter stringWriter = new StringWriter(CultureInfo.InvariantCulture))
			{
				Serializer.Serialize(stringWriter, record);
				using StringReader textReader = new StringReader(stringWriter.ToString());
				rbeRecoveryRecord = (RbeRecoveryRecord)Serializer.Deserialize(textReader);
			}
			rbeRecoveryRecord.RetiredOwners.Add(record.Owner);
			rbeRecoveryRecord.Owner = "RBE" + Guid.NewGuid().ToString("N");
			rbeRecoveryRecord.ActualNet = 0;
			rbeRecoveryRecord.Long = new RbeRecoveryLeg
			{
				Side = 1,
				Used = true
			};
			rbeRecoveryRecord.Short = new RbeRecoveryLeg
			{
				Side = -1,
				Used = true
			};
			rbeRecoveryRecord.BuyTouched = (rbeRecoveryRecord.SellTouched = (rbeRecoveryRecord.Cutoff = true));
			rbeRecoveryRecord.LongReady = (rbeRecoveryRecord.ShortReady = (rbeRecoveryRecord.Closing = (rbeRecoveryRecord.Reconciling = false)));
			rbeRecoveryRecord.FlowSide = (rbeRecoveryRecord.FlowQuantity = (rbeRecoveryRecord.FlowPendingSide = (rbeRecoveryRecord.FlowEntrySide = (rbeRecoveryRecord.FlowEntryReported = (rbeRecoveryRecord.FlowEntryExecuted = 0)))));
			rbeRecoveryRecord.FlowAveragePrice = 0.0;
			rbeRecoveryRecord.FlowBuyUsed = (rbeRecoveryRecord.FlowSellUsed = (rbeRecoveryRecord.FlowFailed = (rbeRecoveryRecord.FlowEntryTerminal = (rbeRecoveryRecord.FlowExitOutstanding = false))));
			rbeRecoveryRecord.CloseQuantity = 0;
			rbeRecoveryRecord.CloseValue = 0.0;
			rbeRecoveryRecord.CloseTime = DateTime.MinValue;
			rbeRecoveryRecord.LongSignal = (rbeRecoveryRecord.ShortSignal = (rbeRecoveryRecord.CloseSignal = null));
			rbeRecoveryRecord.Orders.Clear();
			string text2 = savedOwner;
			savedOwner = rbeRecoveryRecord.Owner;
			try
			{
				Save(rbeRecoveryRecord);
			}
			catch
			{
				savedOwner = text2;
				throw;
			}
			return rbeRecoveryRecord;
		}
	}

	public void Save(RbeRecoveryRecord record)
	{
		lock (gate)
		{
			EnsureOpen();
			if (!loaded)
			{
				throw new InvalidOperationException("RBE recovery must be loaded and reconciled before saving.");
			}
			Validate(record);
			if (record.SettingsFingerprint != fingerprint || (savedOwner != null && savedOwner != record.Owner))
			{
				throw new InvalidOperationException("RBE recovery settings or durable owner changed after loading.");
			}
			string text = Path + "." + Guid.NewGuid().ToString("N") + ".tmp";
			long num = record.Generation;
			DateTime savedUtc = record.SavedUtc;
			record.Generation = checked(generation + 1);
			record.SavedUtc = DateTime.UtcNow;
			try
			{
				using (FileStream fileStream = new FileStream(text, FileMode.CreateNew, FileAccess.Write, FileShare.None))
				{
					Serializer.Serialize(fileStream, record);
					fileStream.Flush(flushToDisk: true);
				}
				if (File.Exists(Path))
				{
					File.Replace(text, Path, Path + ".previous", ignoreMetadataErrors: false);
				}
				else
				{
					File.Move(text, Path);
				}
				generation = record.Generation;
				savedOwner = record.Owner;
			}
			catch (Exception innerException)
			{
				record.Generation = num;
				record.SavedUtc = savedUtc;
				throw new InvalidOperationException("RBE recovery write failed; further trading must remain blocked.", innerException);
			}
			finally
			{
				if (File.Exists(text))
				{
					File.Delete(text);
				}
			}
		}
	}

	private void Validate(RbeRecoveryRecord record)
	{
		if (record == null || record.Version != 1)
		{
			throw new InvalidOperationException("Unsupported RBE recovery checkpoint version.");
		}
		if (record.Account != account || record.Instrument != instrument || record.ExecutionMode != mode || record.TradeDirection != direction)
		{
			throw new InvalidOperationException("RBE recovery account/contract/mode/direction mismatch.");
		}
		Required(record.Owner, "owner");
		if (record.BrokerRestrictionReason != null && (record.BrokerRestrictionReason.Length > 4096 || string.IsNullOrWhiteSpace(record.BrokerRestrictionReason)))
			throw new InvalidOperationException("Invalid RBE broker restriction checkpoint.");
		Required(record.SettingsFingerprint, "settings fingerprint");
		if (record.RetiredOwners == null || record.RetiredOwners.Count > 10000)
		{
			throw new InvalidOperationException("Invalid RBE retired ownership history.");
		}
		HashSet<string> hashSet = new HashSet<string>(StringComparer.Ordinal);
		foreach (string retiredOwner in record.RetiredOwners)
		{
			if (string.IsNullOrEmpty(retiredOwner) || retiredOwner == record.Owner || !hashSet.Add(retiredOwner))
			{
				throw new InvalidOperationException("Invalid or duplicate RBE retired owner.");
			}
		}
		if (record.Generation < 0 || record.BuyFills < 0 || record.SellFills < 0 || record.OrderSequence < 0 || record.Cycle < 0)
		{
			throw new InvalidOperationException("Invalid RBE recovery counters.");
		}
		ValidateLeg(record.Long, 1);
		ValidateLeg(record.Short, -1);
		if (record.Orders == null || record.ExecutionIds == null)
		{
			throw new InvalidOperationException("Incomplete RBE recovery ledgers.");
		}
		HashSet<string> hashSet2 = new HashSet<string>(StringComparer.Ordinal);
		foreach (RbeRecoveryOrder order in record.Orders)
		{
			if (order == null || string.IsNullOrWhiteSpace(order.Name) || (!order.Name.StartsWith(record.Owner + "_", StringComparison.Ordinal) && (string.IsNullOrEmpty(order.Signal) || !order.Signal.StartsWith(record.Owner + "_", StringComparison.Ordinal))) || !hashSet2.Add(RbeRecoveryEvidence.OrderKey(order)) || order.Quantity < 1 || order.ReportedFilled < 0 || order.ReportedFilled > order.Quantity || order.ProcessedFilled < 0 || order.ProcessedFilled > order.Quantity || !Finite(order.Stop) || !Finite(order.Limit) || !Finite(order.AverageFill) || !Finite(order.Distance))
			{
				throw new InvalidOperationException("Invalid or foreign RBE recovery order lineage.");
			}
		}
		HashSet<string> hashSet3 = new HashSet<string>(StringComparer.Ordinal);
		foreach (string executionId in record.ExecutionIds)
		{
			if (string.IsNullOrWhiteSpace(executionId) || !hashSet3.Add(executionId))
			{
				throw new InvalidOperationException("Invalid or duplicate RBE recovery execution ID.");
			}
		}
		double[] array = new double[5] { record.RangeHigh, record.RangeLow, record.LastBid, record.LastAsk, record.Last };
		foreach (double num in array)
		{
			if (!Finite(num) || num < 0.0)
			{
				throw new InvalidOperationException("Invalid RBE recovery price.");
			}
		}
	}

	private static void ValidateLeg(RbeRecoveryLeg leg, int side)
	{
		if (leg == null || leg.Side != side || leg.Quantity < 0 || leg.FilledQuantity < 0 || leg.ExitedQuantity < 0 || (leg.Active && (!leg.Used || leg.Quantity == 0 || leg.Entry <= 0.0 || leg.Stop <= 0.0 || leg.InitialStop <= 0.0)) || (leg.Used && leg.ExitedQuantity > leg.FilledQuantity))
		{
			throw new InvalidOperationException("Invalid RBE recovery virtual leg.");
		}
		double[] array = new double[6] { leg.Entry, leg.Exit, leg.InitialStop, leg.Stop, leg.CoveredPrice, leg.HighWater };
		foreach (double num in array)
		{
			if (!Finite(num) || num < 0.0)
			{
				throw new InvalidOperationException("Invalid RBE recovery leg price.");
			}
		}
	}

	private static bool Finite(double value)
	{
		return !double.IsNaN(value) && !double.IsInfinity(value);
	}

	private static string Required(string value, string name)
	{
		if (string.IsNullOrWhiteSpace(value))
		{
			throw new ArgumentException("Missing RBE recovery " + name + ".");
		}
		return value;
	}

	private void EnsureOpen()
	{
		if (disposed)
		{
			throw new ObjectDisposedException("RbeRecoveryStore");
		}
	}

	public void Dispose()
	{
		lock (gate)
		{
			if (!disposed)
			{
				disposed = true;
				ownership.Dispose();
			}
		}
	}
}

public sealed class RbeSettings
{
	public double StopPercent = 0.6;

	public double MinimumRangePercent = 0.4;

	public double MaximumRangePrice = 10000.0;

	public double TrailTriggerPercent = 2.6;

	public double TrailDistancePercent = 0.6;

	public double TrailStepPrice = 1.0;

	public bool CoverCosts = true;

	public double CostCoverageMultiple = 1.25;
}

public sealed class RbeTradeVisual
{
	public string Tag;

	public int Side;

	public double Entry;

	public double Stop;

	public double InitialStop;

	public double ExitPrice;

	public double Level;

	public int ExitQuantity;

	public DateTime Day;

	public DateTime EntryTime;

	public DateTime ExitTime;

	public DateTime LevelTime;

	public DateTime TrailStart;

	public DateTime ObservedTime;

	public bool Synthetic;

	public bool Trailing;

	private DateTime rightAnchor;

	public DateTime AdvanceRight(DateTime initial, DateTime live)
	{
		if (initial > rightAnchor)
		{
			rightAnchor = initial;
		}
		if (live > rightAnchor)
		{
			rightAnchor = live;
		}
		return rightAnchor;
	}

	public void UpdateStop(double stop, DateTime time)
	{
		if (!(Math.Abs(stop - Stop) < 1E-09))
		{
			if (!Trailing)
			{
				TrailStart = time;
			}
			Stop = stop;
			Trailing = true;
		}
	}
}

public sealed class RbeVisualReplay
{
	public readonly List<RbeTradeVisual> Trades = new List<RbeTradeVisual>();

	private readonly string owner;

	private readonly RbeSettings settings;

	private readonly bool buy;

	private readonly bool sell;

	private readonly double tick;

	private readonly double pointValue;

	private readonly double cost;

	private DateTime day;

	private RbeTradeVisual longTrade;

	private RbeTradeVisual shortTrade;

	private RbePosition longPosition;

	private RbePosition shortPosition;

	public RbeVisualReplay(string owner, RbeSettings settings, bool buy, bool sell, double tick, double pointValue, double cost)
	{
		this.owner = owner;
		this.settings = settings;
		this.buy = buy;
		this.sell = sell;
		this.tick = tick;
		this.pointValue = pointValue;
		this.cost = cost;
	}

	public void Observe(RbeModel model, RbeRangeVisual range, DateTime time, DateTime ny, double price)
	{
		if (day != model.TradingDate)
		{
			day = model.TradingDate;
			longTrade = (shortTrade = null);
			longPosition = (shortPosition = null);
		}
		if (!model.RangeAccepted || ny < model.RangeEnd)
		{
			return;
		}
		if (longTrade != null && longTrade.ExitTime == DateTime.MinValue)
		{
			longTrade.ObservedTime = time;
		}
		if (shortTrade != null && shortTrade.ExitTime == DateTime.MinValue)
		{
			shortTrade.ObservedTime = time;
		}
		DateTime dateTime = day.AddHours(11.0).AddMinutes(55.0);
		if (ny >= dateTime)
		{
			if (ny >= dateTime.AddSeconds(59.0))
			{
				Resolve(longTrade, time, price);
				Resolve(shortTrade, time, price);
			}
			return;
		}
		Visit(longTrade, longPosition, time, price);
		Visit(shortTrade, shortPosition, time, price);
		if (buy && longTrade == null && price >= RbeModel.Up(model.High, tick))
		{
			longTrade = Start(model, range, time, price, 1);
			longPosition = new RbePosition(buy: true, price, longTrade.Stop, settings, pointValue, cost);
		}
		if (sell && shortTrade == null && price <= RbeModel.Down(model.Low, tick))
		{
			shortTrade = Start(model, range, time, price, -1);
			shortPosition = new RbePosition(buy: false, price, shortTrade.Stop, settings, pointValue, cost);
		}
	}

	private RbeTradeVisual Start(RbeModel model, RbeRangeVisual range, DateTime time, double price, int side)
	{
		double num = Math.Abs(((side == 1) ? RbeModel.Up(model.High, tick) : RbeModel.Down(model.Low, tick)) - model.InitialStop(side == 1, tick));
		double num2 = ((side == 1) ? RbeModel.Down(price - num, tick) : RbeModel.Up(price + num, tick));
		RbeTradeVisual rbeTradeVisual = new RbeTradeVisual
		{
			Tag = owner + "_SYN_" + day.ToString("yyyyMMdd") + ((side == 1) ? "_L" : "_S"),
			Day = day,
			Side = side,
			Synthetic = true,
			EntryTime = time,
			ObservedTime = time,
			Entry = price,
			InitialStop = num2,
			Stop = num2,
			Level = ((side == 1) ? model.High : model.Low),
			LevelTime = ((side == 1) ? range.HighFormed : range.LowFormed)
		};
		Trades.Add(rbeTradeVisual);
		return rbeTradeVisual;
	}

	private void Visit(RbeTradeVisual trade, RbePosition position, DateTime time, double price)
	{
		if (trade != null && !(trade.ExitTime != DateTime.MinValue))
		{
			if ((trade.Side == 1) ? (price <= trade.Stop) : (price >= trade.Stop))
			{
				Resolve(trade, time, price);
			}
			else
			{
				trade.UpdateStop(position.UpdateStop(price, tick), time);
			}
		}
	}

	private static void Resolve(RbeTradeVisual trade, DateTime time, double price)
	{
		if (trade != null && !(trade.ExitTime != DateTime.MinValue))
		{
			trade.ExitTime = time;
			trade.ExitPrice = price;
		}
	}
}

internal static class RbeVisuals
{
	private sealed class PendingChartDraws
	{
		internal readonly Dictionary<string, Action> Latest = new Dictionary<string, Action>();

		internal readonly Queue<string> Order = new Queue<string>();

		internal bool Queued;
	}

	private static int reportedDrawFailure;

	public static readonly Brush ClrRangeBoxNY = MakeBrush(25, 35, 45);

	public static readonly Brush ClrEntryLine = MakeBrush(214, 218, 224);

	public static readonly Brush ClrSLBox = MakeBrush(55, 57, 68);

	public static readonly Brush ClrTPBox = MakeBrush(22, 55, 120);

	public static readonly Brush ClrTrailingStop = MakeBrush(162, 138, 88);

	private static readonly ConditionalWeakTable<Strategy, PendingChartDraws> pendingChartDraws = new ConditionalWeakTable<Strategy, PendingChartDraws>();

	private static Brush MakeBrush(byte r, byte g, byte b)
	{
		var solidColorBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(r, g, b));
		solidColorBrush.Freeze();
		return solidColorBrush;
	}

	private static bool ValidTime(DateTime t)
	{
		return t > new DateTime(2000, 1, 1);
	}

	private static void Guard(Strategy strategy, string tag, Action draw)
	{
		try
		{
			ChartControl chartControl = strategy.ChartControl;
			if (chartControl == null || chartControl.Dispatcher.HasShutdownStarted || chartControl.Dispatcher.HasShutdownFinished)
			{
				return;
			}
			PendingChartDraws value = pendingChartDraws.GetValue(strategy, (Strategy key) => new PendingChartDraws());
			lock (value)
			{
				if (!value.Latest.ContainsKey(tag))
				{
					value.Order.Enqueue(tag);
				}
				value.Latest[tag] = () =>
				{
					if (strategy.State == State.Terminated)
					{
						return;
					}
					try
					{
						draw();
					}
					catch (Exception ex2)
					{
						Report(strategy, ex2);
					}
				};
				if (value.Queued)
				{
					return;
				}
				value.Queued = true;
			}
			QueueChartDraws(strategy, chartControl, value);
		}
		catch (Exception ex)
		{
			Report(strategy, ex);
		}
	}

	private static void QueueChartDraws(Strategy strategy, ChartControl chart, PendingChartDraws pending)
	{
		try
		{
			chart.Dispatcher.BeginInvoke(DispatcherPriority.Background, (Action)(() =>
			{
				List<Action> list = new List<Action>();
				lock (pending)
				{
					if (strategy.State == State.Terminated || chart != strategy.ChartControl)
					{
						pending.Latest.Clear();
						pending.Order.Clear();
						pending.Queued = false;
						return;
					}
					while (pending.Order.Count > 0 && list.Count < 32)
					{
						string key = pending.Order.Dequeue();
						list.Add(pending.Latest[key]);
						pending.Latest.Remove(key);
					}
				}
				foreach (Action item in list)
				{
					item();
				}
				lock (pending)
				{
					if (pending.Latest.Count == 0)
					{
						pending.Queued = false;
						return;
					}
				}
				QueueChartDraws(strategy, chart, pending);
			}));
		}
		catch (Exception ex)
		{
			lock (pending)
			{
				pending.Latest.Clear();
				pending.Order.Clear();
				pending.Queued = false;
			}
			Report(strategy, ex);
		}
	}

	private static void Report(Strategy strategy, Exception ex)
	{
		if (Interlocked.Exchange(ref reportedDrawFailure, 1) == 0)
		{
			strategy.Print("[RBE] Chart drawing failed: " + ex.Message);
		}
	}

	private static void Sink(DrawingTool tool)
	{
		try
		{
			if (tool != null && tool.ZOrder != 1)
			{
				tool.ZOrder = 1;
			}
		}
		catch
		{
		}
	}

	public static void DrawRangeBox(Strategy strategy, string tag, DateTime startTime, DateTime endTime, double rangeHigh, double rangeLow, Brush fillBrush, int opacity = 35)
	{
		if (!(rangeHigh <= rangeLow) && ValidTime(startTime) && !(endTime <= startTime))
		{
			Guard(strategy, tag, () =>
			{
				Sink(Draw.Rectangle(strategy, tag, isAutoScale: false, startTime, rangeHigh, endTime, rangeLow, Brushes.Transparent, fillBrush, opacity));
			});
		}
	}

	public static void DrawBoundedLine(Strategy strategy, string tag, DateTime t1, double p1, DateTime t2, double p2, Brush brush, DashStyleHelper dash, int width)
	{
		if (ValidTime(t1))
		{
			if (t2 <= t1)
			{
				t2 = t1.AddMinutes(1.0);
			}
			Guard(strategy, tag, () =>
			{
				Sink(Draw.Line(strategy, tag, isAutoScale: false, t1, p1, t2, p2, brush, dash, width));
			});
		}
	}

	public static void DrawPendingLine(Strategy strategy, string tag, double price, DateTime fromTime, DateTime toTime)
	{
		DrawBoundedLine(strategy, tag, fromTime, price, toTime, price, ClrEntryLine, DashStyleHelper.Dash, 1);
	}

	public static void DrawExecutionTool(Strategy strategy, string tagBase, bool isLong, double entryPx, double slPx, double tpPx, double levelPx, DateTime levelTime, DateTime entryTime, DateTime exitTime, bool trailing, DateTime trailStartTime, bool synthetic)
	{
		if (!ValidTime(entryTime))
		{
			return;
		}
		if (!ValidTime(levelTime))
		{
			levelTime = entryTime;
		}
		DateTime right = ((exitTime <= entryTime) ? entryTime.AddSeconds(1.0) : exitTime);
		int fillOpacity = (synthetic ? 25 : 40);
		DrawBoundedLine(strategy, tagBase + "_ENT", levelTime, levelPx, entryTime, levelPx, ClrEntryLine, synthetic ? DashStyleHelper.Dash : DashStyleHelper.Solid, 2);
		DrawBoundedLine(strategy, tagBase + "_ENTRY", entryTime, entryPx, right, entryPx, ClrEntryLine, synthetic ? DashStyleHelper.Dash : DashStyleHelper.Solid, 1);
		if (!trailing)
		{
			Guard(strategy, tagBase + "_SL", () =>
			{
				Sink(Draw.Rectangle(strategy, tagBase + "_SL", isAutoScale: false, entryTime, entryPx, right, slPx, Brushes.Transparent, ClrSLBox, fillOpacity));
			});
		}
		else
		{
			Guard(strategy, tagBase + "_SL", () =>
			{
				strategy.RemoveDrawObject(tagBase + "_SL");
			});
		}
		if (tpPx > 0.0)
		{
			Guard(strategy, tagBase + "_TP", () =>
			{
				Sink(Draw.Rectangle(strategy, tagBase + "_TP", isAutoScale: false, entryTime, entryPx, right, tpPx, Brushes.Transparent, ClrTPBox, fillOpacity));
			});
		}
		if (trailing && ValidTime(trailStartTime))
		{
			DrawBoundedLine(strategy, tagBase + "_TRAIL", (trailStartTime < entryTime) ? entryTime : trailStartTime, slPx, right, slPx, ClrTrailingStop, DashStyleHelper.Dot, 2);
			return;
		}
		Guard(strategy, tagBase + "_TRAIL", () =>
		{
			strategy.RemoveDrawObject(tagBase + "_TRAIL");
		});
	}
}
}
