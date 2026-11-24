//+------------------------------------------------------------------+
//|                                   TuesdayTurnaroundStrategy.cs  |
//| Turnaround Tuesday Models (T1-T4) on US Index Futures            |
//| Developed by Osamwonyi Eric (You_FoundEric)                      |
//| Copyright 2026-2027, Osamwonyi Eric (@You_FoundEric)             |
//+------------------------------------------------------------------+

using NinjaTrader.Cbi;
using NinjaTrader.Core;
using NinjaTrader.Data;
using NinjaTrader.Gui.Chart;
using NinjaTrader.Gui.Tools;
using NinjaTrader.Gui;
using NinjaTrader.NinjaScript.DrawingTools;
using SharpDX.Direct2D1;
using SharpDX.DirectWrite;
using SharpDX;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Runtime.CompilerServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;
using System.Threading;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows;
using System.Xml.Serialization;
using System;
using Brush = System.Windows.Media.Brush;
using Color = System.Windows.Media.Color;
using Point = System.Windows.Point;
using SolidColorBrush = SharpDX.Direct2D1.SolidColorBrush;
using TextAlignment = System.Windows.TextAlignment;

namespace NinjaTrader.NinjaScript.Strategies.TuesdayTurnaround_NT
{
internal static class TTVisuals
{
	internal static readonly Brush ClrEntryLine = MakeBrush(214, 218, 224);

	internal static readonly Brush ClrSLBox = MakeBrush(55, 57, 68);

	internal static readonly Brush ClrTrailingStop = MakeBrush(162, 138, 88);

	private static Brush MakeBrush(byte r, byte g, byte b)
	{
		System.Windows.Media.SolidColorBrush solidColorBrush = new System.Windows.Media.SolidColorBrush(Color.FromRgb(r, g, b));
		solidColorBrush.Freeze();
		return solidColorBrush;
	}

	private static bool ValidTime(DateTime time)
	{
		return time > new DateTime(2000, 1, 1);
	}

	private static void Guard(Action draw)
	{
		try
		{
			draw();
		}
		catch
		{
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

	private static DateTime MinSpanRight(Strategy strategy, DateTime trigger, DateTime right)
	{
		try
		{
			int num = -1;
			for (int i = 0; i <= Math.Min(strategy.CurrentBar, 5000); i++)
			{
				if (strategy.Times[0][i] <= trigger)
				{
					num = i;
					break;
				}
			}
			if (num < 0)
			{
				return right;
			}
			DateTime dateTime = strategy.Times[0][Math.Max(0, num - 3)];
			return (right < dateTime) ? dateTime : right;
		}
		catch
		{
			return right;
		}
	}

	internal static void DrawBoundedLine(Strategy strategy, string tag, DateTime start, double startPrice, DateTime end, double endPrice, Brush brush, DashStyleHelper dash, int width)
	{
		if (ValidTime(start))
		{
			if (end <= start)
			{
				end = start.AddMinutes(1.0);
			}
			Guard(() =>
			{
				Sink(Draw.Line(strategy, tag, isAutoScale: false, start, startPrice, end, endPrice, brush, dash, width));
			});
		}
	}

	internal static void DrawTradeTool(Strategy strategy, string tag, bool isLong, double entry, double stop, double target, double level, DateTime levelTime, DateTime trigger, DateTime right, bool trailing, DateTime trailStart, bool synthetic)
	{
		if (!ValidTime(trigger))
		{
			return;
		}
		if (!ValidTime(levelTime))
		{
			levelTime = trigger;
		}
		if (right <= trigger)
		{
			right = trigger.AddMinutes(1.0);
		}
		DateTime boxRight = MinSpanRight(strategy, trigger, right);
		int opacity = (synthetic ? 25 : 40);
		DrawBoundedLine(strategy, tag + "_ENT", levelTime, level, trigger, level, ClrEntryLine, synthetic ? DashStyleHelper.Dash : DashStyleHelper.Solid, 2);
		if (!trailing)
		{
			Guard(() =>
			{
				Sink(Draw.Rectangle(strategy, tag + "_SL", isAutoScale: false, trigger, entry, boxRight, stop, Brushes.Transparent, ClrSLBox, opacity));
			});
		}
		else
		{
			strategy.RemoveDrawObject(tag + "_SL");
		}
		if (trailing && ValidTime(trailStart))
		{
			DrawBoundedLine(strategy, tag + "_TRAIL", (trailStart < trigger) ? trigger : trailStart, stop, boxRight, stop, ClrTrailingStop, DashStyleHelper.Dot, 2);
		}
		else
		{
			strategy.RemoveDrawObject(tag + "_TRAIL");
		}
	}
}

public class TuesdayTurnaround : Strategy
{
	private const string BuildId = "2026-10-13a";

	private const string IndexTradingHours = "CME US Index Futures ETH";

	private const string EntrySignal = "TT_Long";

	private static readonly TimeZoneInfo NewYorkTimeZone = TimeZoneInfo.FindSystemTimeZoneById("Eastern Standard Time");

	private readonly List<TurnaroundDailyBar> daily = new List<TurnaroundDailyBar>();

	private readonly Dictionary<DateTime, DateTime> visibleMinuteCloseTimes = new Dictionary<DateTime, DateTime>();

	private int lastDailyIndex = -1;

	private bool pendingEntry;

	private bool pendingExit;

	private bool breakEvenArmed;

	private bool fixedSelfCloseRequested;

	private bool haveMinutePreview;

	private bool newsBlackoutActive;

	private bool newsEntryCancelPending;

	private int heldSessions;

	private int quantity;

	private int newsFlattenQuantity;

	private double stopPrice;

	private double entryPrice;

	private double initialRisk;

	private double protectiveStopPrice;

	private DateTime newsConsumedMonday = DateTime.MinValue;

	private DateTime mondayDate;

	private DateTime entryTime;

	private string csvPath = "";

	private string status = "WARMUP";

	private string pendingExitReason = "";

	private Order entryOrder;

	private Order exitOrder;

	private SessionIterator minuteSessionIterator;

	private DateTime minuteTradingDay;

	private TurnaroundDailyBar minutePreview;

	private TurnaroundLiveLedger liveLedger;

	private FileStream liveLease;

	private string livePath = "";

	private string liveFault = "";

	private string liveReportedCase = "";

	private bool liveHooked;

	private bool liveReady;

	private bool livePumping;

	private bool liveJournalValid;

	private bool liveVisualRestored;

	private DateTime liveQuoteUtc;

	private DateTime liveScanUtc;

	private readonly Dictionary<string, Order> liveOrders = new Dictionary<string, Order>();

	private readonly ConcurrentDictionary<string, string> liveIdentities = new ConcurrentDictionary<string, string>();

	private string legacyBrokerCloseConfirmation = string.Empty;

	private TurnaroundDashboard dashboard;

	private Timer panelClock;

	private ChartControl dashboardChart;

	private bool dashboardMouseHooked;

	private TurnaroundNewsCalendar newsCalendar;

	private TurnaroundNewsEvent activeNewsEvent;

	private bool newsSourceAvailable;

	private double newsCycleCommission;

	private double newsCycleQuantity;

	private double newsObservedCommission;

	private double newsObservedQuantity;

	private bool shadowPending;

	private bool shadowActive;

	private bool shadowBreakEven;

	private bool shadowFixedClosePending;

	private int shadowHeldSessions;

	private double shadowEntry;

	private double shadowInitialStop;

	private double shadowStop;

	private double shadowRisk;

	private double shadowFridayOpen;

	private DateTime shadowEntryTime;

	private DateTime shadowTrailTime;

	private string shadowTag = "";

	private const string ActiveEntryTag = "TT_ACTIVE_ENTRY";

	private const string ActiveStopTag = "TT_ACTIVE_STOP";

	private const string ActiveTriggerTag = "TT_ACTIVE_TRIGGER";

	private TurnaroundDailyBar visualFriday;

	private TurnaroundDailyBar visualMonday;

	private bool haveVisualSetup;

	private bool visualSignalConfirmed;

	private double tradeInitialStop;

	private double tradeFridayOpen;

	private DateTime trailStartTime;

	private string activeTradeTag = "";

	private int visualErrors;

	private string visualError = "";

	private bool BrokerLive => State == State.Realtime && !IsInStrategyAnalyzer;

	private MarketPosition OwnedPosition => (!BrokerLive) ? Position.MarketPosition : ((liveLedger == null || liveLedger.OwnQuantity <= 0) ? MarketPosition.Flat : MarketPosition.Long);

	private int OwnedQuantity => (!BrokerLive) ? Position.Quantity : ((liveLedger != null) ? liveLedger.OwnQuantity : 0);

	[NinjaScriptProperty]
	[Display(Name = "Recovery ID", Description = "Stable sleeve identity for this account and exact contract. Reuse on replacement charts. Give concurrent instances different IDs. Broker-owned live orders are shown in TT's panel/journal, not the native strategy-position ledger.", GroupName = "Strategy", Order = 1)]
	public string RecoveryId { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "Enable new live trades", GroupName = "0. Trading", Order = 0)]
	public bool EnableNewTrades { get; set; }

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
	[Display(Name = "Model", Description = "T1: Monday drop >=1%, Tuesday close. T2: bearish Monday + IBS<0.20, Tuesday close. T3: below Friday + IBS<0.50, fourth close. T4: T3 entry, close above prior high or fourth close. An active recovered trade retains its saved model. Research candidates: NQ/MNQ T1; ES/MES T4. T4 spans sessions and needs separate daily-flat validation for Tradeify.", GroupName = "Strategy", Order = 0)]
	public TurnaroundModel Model { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "Risk mode", GroupName = "Risk", Order = 0)]
	public TurnaroundRiskMode RiskMode { get; set; }

	[NinjaScriptProperty]
	[Range(1, 50000)]
	[Display(Name = "Risk budget ($)", GroupName = "Risk", Order = 1)]
	public double RiskBudget { get; set; }

	[NinjaScriptProperty]
	[Range(1, 100)]
	[Display(Name = "Fixed quantity", GroupName = "Risk", Order = 2)]
	public int FixedQuantity { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "Enable fixed self-close", GroupName = "Exit", Order = 0)]
	public bool EnableFixedSelfClose { get; set; }

	[NinjaScriptProperty]
	[Range(0, 175959)]
	[Display(Name = "Fixed self-close time (HHmmss ET)", GroupName = "Exit", Order = 1)]
	public int FixedSelfCloseTime { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "CSV audit path", GroupName = "Audit", Order = 0)]
	public string LogPath { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "News folders", Description = "Off; HighOnly = red; HighMedium = red + yellow; All = all folders. ForexFactory with RBE impact classification.", GroupName = "News", Order = 0)]
	public TurnaroundNewsMode NewsMode { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "Total blackout minutes", Description = "Five = 2m30s each side; Ten = 5m each side; Fourteen = 7m each side; Twenty = 10m each side.", GroupName = "News", Order = 1)]
	public TurnaroundNewsWindow NewsWindow { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "Cost-covered BE before news", Description = "Tighten to entry plus round-trip commission and assumed slippage when a valid profitable stop is possible. Never loosens the stop.", GroupName = "News", Order = 2)]
	public bool NewsCostCoveredBE { get; set; }

	[NinjaScriptProperty]
	[Range(0.0, double.MaxValue)]
	[Display(Name = "Assumed commission / contract ($)", Description = "Round turn. Zero uses MES/MNQ 1.82; ES/NQ 5.76. Observed completed live trades replace this estimate.", GroupName = "News", Order = 8)]
	public double NewsAssumedCommission { get; set; }

	[NinjaScriptProperty]
	[Range(0, 100)]
	[Display(Name = "Assumed slip ticks per side", Description = "Added for both entry and exit; remains assumed when commission history is available.", GroupName = "News", Order = 9)]
	public int NewsAssumedSlipTicks { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "Cancel pending entry", GroupName = "News", Order = 3)]
	public bool NewsCancelPending { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "Freeze trailing", GroupName = "News", Order = 4)]
	public bool NewsFreezeTrailing { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "Flatten owned position", GroupName = "News", Order = 5)]
	public bool NewsFlattenPosition { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "Currencies (blank = USD)", GroupName = "News", Order = 6)]
	public string NewsCurrencies { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "Historical news CSV", GroupName = "News", Order = 7)]
	public string HistoricalNewsCsv { get; set; }

	private static string StrategyRoot([CallerFilePath] string source = "")
	{
		return Path.GetDirectoryName(source);
	}

	protected override void OnStateChange()
	{
		if (State == State.SetDefaults)
		{
			Name = "TuesdayTurnaround";
			Description = "TuesdayTurnaround - Native daily Turnaround Tuesday models T1-T4 for index futures. Completed daily return and IBS signals, Tuesday-open minute execution, model-dependent exits, optional fixed close and news guard. Copyright 2026-2027, Osamwonyi Eric (@You_FoundEric). Developed by @You_FoundEric. Unauthorized redistribution prohibited.";
			Calculate = Calculate.OnEachTick;
			EntriesPerDirection = 1;
			EntryHandling = EntryHandling.AllEntries;
			IsExitOnSessionCloseStrategy = false;
			ExitOnSessionCloseSeconds = 30;
			StartBehavior = StartBehavior.ImmediatelySubmit;
			ConnectionLossHandling = ConnectionLossHandling.KeepRunning;
			BarsRequiredToTrade = 0;
			MaximumBarsLookBack = MaximumBarsLookBack.Infinite;
			OrderFillResolution = OrderFillResolution.Standard;
			IsFillLimitOnTouch = true;
			Slippage = 1.0;
			StopTargetHandling = StopTargetHandling.PerEntryExecution;
			TimeInForce = TimeInForce.Gtc;
			IsOverlay = true;
			IncludeCommission = false;
			Model = TurnaroundModel.T1;
			RiskMode = TurnaroundRiskMode.FixedOneContract;
			RiskBudget = 500.0;
			FixedQuantity = 1;
			EnableFixedSelfClose = false;
			FixedSelfCloseTime = 164455;
			NewsMode = TurnaroundNewsMode.HighOnly;
			NewsWindow = TurnaroundNewsWindow.Ten;
			NewsCostCoveredBE = true;
			NewsAssumedCommission = 3.0;
			NewsAssumedSlipTicks = 1;
			NewsCancelPending = true;
			NewsFreezeTrailing = true;
			NewsFlattenPosition = false;
			NewsCurrencies = "";
			HistoricalNewsCsv = "";
			RecoveryId = "main";
			EnableNewTrades = true;
			BrokerCloseConfirmation = "";
			LogPath = "";
		}
		else if (State == State.Configure)
		{
			IsExitOnSessionCloseStrategy = false;
			AddDataSeries(null, new BarsPeriod
			{
				BarsPeriodType = BarsPeriodType.Minute,
				Value = 1
			}, "CME US Index Futures ETH");
			AddDataSeries(null, new BarsPeriod
			{
				BarsPeriodType = BarsPeriodType.Day,
				Value = 1
			}, "CME US Index Futures ETH");
		}
		else if (State == State.DataLoaded)
		{
			InitializeDashboard();
			csvPath = (string.IsNullOrWhiteSpace(LogPath) ? "" : Path.Combine(StrategyRoot("C:\\Users\\Administrator\\Documents\\NinjaTrader 8\\bin\\Custom\\Strategies\\1. TuesdayTurnaround_NT\\TuesdayTurnaroundStrategy.cs"), Path.GetFileName(LogPath.Trim())));
			minuteSessionIterator = new SessionIterator(BarsArray[1]);
			InitializeNews();
			EnsureHeader();
			string text = TuesdayTurnaroundModel.SelfTest();
			if (text.Length > 0)
			{
				throw new InvalidOperationException("TuesdayTurnaround self-test: " + text);
			}
			if (!TuesdayTurnaroundModel.ValidClock(FixedSelfCloseTime))
			{
				throw new InvalidOperationException("Fixed self-close time must be a valid HHmmss before 18:00.");
			}
			if (!PrepareOwnedRecovery())
			{
				SetState(State.Terminated);
			}
		}
		else if (State == State.Transition)
		{
			pendingEntry = false;
			pendingExit = false;
			pendingExitReason = "";
			entryOrder = ((entryOrder == null) ? null : GetRealtimeOrder(entryOrder));
			exitOrder = ((exitOrder == null) ? null : GetRealtimeOrder(exitOrder));
			fixedSelfCloseRequested = false;
			newsFlattenQuantity = 0;
			newsEntryCancelPending = false;
			FreezeHistoricalShadow();
			PublishMondayPreview();
			status = "LIVE READY | WAITING FOR FRESH MONDAY SIGNAL";
		}
		else if (State == State.Realtime)
		{
			StartOwnedRecovery();
			StartDashboardClock();
		}
		else if (State == State.Terminated)
		{
			ShutdownDashboard();
			ShutdownNews();
			StopOwnedRecovery();
		}
	}

	protected override void OnBarUpdate()
	{
		if (BarsInProgress == 0)
		{
			UpdateTurnaroundVisuals();
		}
		else if (BarsInProgress == 2)
		{
			ProcessVisibleDaily();
		}
		else
		{
			if (BarsInProgress != 1 || CurrentBars[1] < 0)
			{
				return;
			}
			CaptureVisibleMinuteClose();
			UpdateMinutePreview();
			ProcessHistoricalShadowMinute();
			if (BrokerLive)
			{
				PumpOwnedOrders();
			}
			if (!OrderConnectionReady())
			{
				if (OwnedPosition == MarketPosition.Long && TuesdayTurnaroundModel.TimedExitDue(Model, heldSessions) && Times[1][0] >= minuteSessionIterator.ActualSessionEnd.AddMinutes(-1.0))
				{
					pendingExit = true;
					pendingExitReason = ((Model == TurnaroundModel.T1 || Model == TurnaroundModel.T2) ? "FIRST_SESSION_CLOSE" : "FOURTH_CLOSE");
				}
				status = "DISCONNECTED | ORDER ACTIONS PAUSED";
				return;
			}
			if (newsEntryCancelPending && OwnedPosition == MarketPosition.Long)
			{
				SubmitNewsFlatten("DEFERRED_LATE_FILL");
			}
			bool flag = UpdateNewsState(ToUtc(Times[1][0]));
			if (EnableFixedSelfClose && State == State.Historical && IsInStrategyAnalyzer && OwnedPosition == MarketPosition.Long && !fixedSelfCloseRequested && TuesdayTurnaroundModel.FixedCloseDue(ToNewYork(Times[1][0]), FixedSelfCloseTime, historical: true))
			{
				SubmitFixedSelfClose("HISTORICAL");
				return;
			}
			if (OwnedPosition == MarketPosition.Long && TuesdayTurnaroundModel.TimedExitDue(Model, heldSessions) && Times[1][0] >= minuteSessionIterator.ActualSessionEnd.AddMinutes(-1.0) && exitOrder == null)
			{
				string reason = ((Model == TurnaroundModel.T1 || Model == TurnaroundModel.T2) ? "TT_FIRST_SESSION_CLOSE" : "TT_FOURTH_CLOSE");
				SubmitOwnedExit(reason);
				status = ((Model == TurnaroundModel.T1 || Model == TurnaroundModel.T2) ? "EXIT SENT | FIRST SESSION" : "EXIT SENT | FOURTH SESSION");
				return;
			}
			if (pendingExit)
			{
				if (OwnedPosition == MarketPosition.Long && exitOrder == null)
				{
					SubmitOwnedExit("TT_" + pendingExitReason);
					pendingExit = false;
					status = "EXIT SENT | " + pendingExitReason;
					return;
				}
				if (OwnedPosition == MarketPosition.Flat)
				{
					pendingExit = false;
					pendingExitReason = "";
				}
			}
			if (!flag && pendingEntry && OwnedPosition == MarketPosition.Flat && entryOrder == null)
			{
				SubmitEntry();
				pendingEntry = false;
			}
			if (OwnedPosition == MarketPosition.Long && (!flag || !NewsFreezeTrailing) && !breakEvenArmed && TuesdayTurnaroundModel.UsesBreakEven(Root()) && Highs[1][0] >= entryPrice + 1.5 * initialRisk)
			{
				double num = Math.Max(protectiveStopPrice, RoundUp(entryPrice + RoundTurnCost() / Instrument.MasterInstrument.PointValue));
				if (num <= protectiveStopPrice || TightenOwnedStop(num))
				{
					protectiveStopPrice = num;
					breakEvenArmed = true;
					trailStartTime = Times[1][0];
					status = "LONG | BE ARMED " + num.ToString("0.00");
				}
			}
			if (State == State.Realtime)
			{
				UpdateTurnaroundVisuals();
			}
		}
	}

	private void ProcessVisibleDaily()
	{
		int num = ((State != State.Historical) ? (IsFirstTickOfBar ? 1 : (-1)) : 0);
		if (num < 0 || CurrentBars[2] < num)
		{
			return;
		}
		int num2 = CurrentBars[2] - num;
		if (num2 == lastDailyIndex)
		{
			return;
		}
		lastDailyIndex = num2;
		TurnaroundDailyBar turnaroundDailyBar = new TurnaroundDailyBar
		{
			Date = Times[2][num].Date,
			Open = Opens[2][num],
			High = Highs[2][num],
			Low = Lows[2][num],
			Close = Closes[2][num]
		};
		daily.Add(turnaroundDailyBar);
		if (daily.Count > 12)
		{
			daily.RemoveAt(0);
		}
		WriteAudit("DAILY", turnaroundDailyBar, turnaroundDailyBar.Close, "NATIVE_DAILY");
		ProcessHistoricalShadowDaily(turnaroundDailyBar);
		if (OwnedPosition == MarketPosition.Long)
		{
			if (BrokerLive)
			{
				OwnedDailyClose(turnaroundDailyBar);
				return;
			}
			heldSessions++;
			bool flag = false;
			string text = "";
			if (Model == TurnaroundModel.T4 && daily.Count >= 2)
			{
				flag = TuesdayTurnaroundModel.T4CloseExit(turnaroundDailyBar, daily[daily.Count - 2]) && heldSessions < 4;
				text = "CLOSE_GT_PRIOR_HIGH";
			}
			if (flag)
			{
				pendingExitReason = text;
				if (IsInStrategyAnalyzer)
				{
					ExitLong(1, quantity, "TT_" + text, "TT_Long");
				}
				else
				{
					pendingExit = true;
				}
				status = "EXIT QUEUED | " + text + " | source " + turnaroundDailyBar.Close.ToString("0.00");
				WriteAudit("EXIT_SIGNAL", turnaroundDailyBar, turnaroundDailyBar.Close, text);
			}
		}
		if (daily.Count < 2 || turnaroundDailyBar.Date.DayOfWeek != DayOfWeek.Monday)
		{
			return;
		}
		TurnaroundDailyBar friday = daily[daily.Count - 2];
		bool flag2 = TuesdayTurnaroundModel.Signal(Model, friday, turnaroundDailyBar);
		WriteAudit(flag2 ? "SIGNAL" : "REJECT", turnaroundDailyBar, turnaroundDailyBar.Close, flag2 ? "RULE_MET" : "RULE_NOT_MET");
		if (!flag2)
		{
			ClearMondayPreview(turnaroundDailyBar.Date);
			status = "REJECTED " + Model.ToString() + " | Monday rule not met";
		}
		else
		{
			if (OwnedPosition != MarketPosition.Flat || (BrokerLive && liveLedger != null && liveLedger.Busy))
			{
				return;
			}
			mondayDate = turnaroundDailyBar.Date;
			stopPrice = RoundDown(TuesdayTurnaroundModel.StopPrice(Root(), turnaroundDailyBar, TickSize));
			quantity = ((RiskMode == TurnaroundRiskMode.FixedOneContract) ? FixedQuantity : 0);
			heldSessions = 0;
			RememberAndDrawSetup(friday, turnaroundDailyBar);
			if (!OrderSubmissionEnabled())
			{
				ArmHistoricalShadow(friday, turnaroundDailyBar);
				status = "HISTORICAL VISUAL TRADE | BROKER ORDER SUPPRESSED";
				return;
			}
			pendingEntry = true;
			status = "ARMED " + Model.ToString() + " | qty " + quantity + " | stop " + stopPrice.ToString("0.00");
			if (IsInStrategyAnalyzer && CurrentBars[1] >= 0)
			{
				DateTime utcNow = TimeZoneInfo.ConvertTimeToUtc(DateTime.SpecifyKind(turnaroundDailyBar.Date.AddHours(18.0).AddMinutes(1.0), DateTimeKind.Unspecified), NewYorkTimeZone);
				if (NewsBlackout(utcNow))
				{
					pendingEntry = false;
					status = "BLOCKED | NEWS AT TUESDAY OPEN";
					WriteNewsAudit("NEWS_BLOCK_ENTRY", utcNow);
				}
				else
				{
					SubmitEntry();
					pendingEntry = false;
				}
			}
		}
	}

	private void CaptureVisibleMinuteClose()
	{
		if (minuteTradingDay == DateTime.MinValue || Times[1][0] > minuteSessionIterator.ActualSessionEnd || Bars.IsFirstBarOfSession)
		{
			minuteSessionIterator.GetNextSession(Times[1][0], includesEndTimeStamp: true);
			minuteTradingDay = minuteSessionIterator.ActualTradingDayExchange.Date;
		}
		visibleMinuteCloseTimes[minuteTradingDay] = Times[1][0];
		if (visibleMinuteCloseTimes.Count <= 20)
		{
			return;
		}
		DateTime dateTime = DateTime.MaxValue;
		foreach (DateTime key in visibleMinuteCloseTimes.Keys)
		{
			if (key < dateTime)
			{
				dateTime = key;
			}
		}
		visibleMinuteCloseTimes.Remove(dateTime);
	}

	private void UpdateMinutePreview()
	{
		bool flag = TuesdayTurnaroundModel.UpdatePreview(ref minutePreview, minuteTradingDay, Opens[1][0], Highs[1][0], Lows[1][0], Closes[1][0]);
		haveMinutePreview = true;
		if (minuteTradingDay.DayOfWeek == DayOfWeek.Monday && (flag || State == State.Realtime))
		{
			PublishMondayPreview();
		}
	}

	private void PublishMondayPreview()
	{
		if (haveMinutePreview && minutePreview.Date.DayOfWeek == DayOfWeek.Monday && TryPriorFriday(minutePreview.Date, out var friday))
		{
			RememberLiveMondayPreview(friday, minutePreview);
			if (State == State.Realtime)
			{
				status = "MONDAY FORMING | awaiting completed Daily close";
			}
		}
	}

	private bool TryPriorFriday(DateTime monday, out TurnaroundDailyBar friday)
	{
		DateTime dateTime = monday.Date.AddDays(-3.0);
		for (int num = daily.Count - 1; num >= 0; num--)
		{
			if (daily[num].Date.Date == dateTime)
			{
				friday = daily[num];
				return true;
			}
		}
		friday = default;
		return false;
	}

	private bool OrderSubmissionEnabled()
	{
		return IsInStrategyAnalyzer || (State == State.Realtime && liveReady && liveLedger != null && !liveLedger.Blocked);
	}

	private bool OrderConnectionReady()
	{
		return State != State.Realtime || (Account != null && Account.ConnectionStatus == ConnectionStatus.Connected);
	}

	private void SubmitEntry()
	{
		if (!OrderConnectionReady())
		{
			return;
		}
		if (newsConsumedMonday == mondayDate)
		{
			pendingEntry = false;
			return;
		}
		double num = Closes[1][0];
		if (num <= stopPrice)
		{
			status = "SKIP | OPEN THROUGH STOP";
			return;
		}
		if (RiskMode == TurnaroundRiskMode.RiskBudget)
		{
			quantity = TuesdayTurnaroundModel.Quantity(num, stopPrice, Instrument.MasterInstrument.PointValue, RoundTurnCost(), RiskBudget);
		}
		if (quantity < 1)
		{
			status = "SKIP | RISK < 1 CONTRACT";
			return;
		}
		if (BrokerLive)
		{
			SubmitOwnedEntry();
			return;
		}
		SetStopLoss("TT_Long", CalculationMode.Price, stopPrice, isSimulatedStop: false);
		protectiveStopPrice = stopPrice;
		EnterLong(1, quantity, "TT_Long");
		status = "ENTRY SENT | " + Model.ToString() + " | qty " + quantity;
	}

	protected override void OnExecutionUpdate(Execution execution, string executionId, double price, int qty, MarketPosition marketPosition, string orderId, DateTime time)
	{
		if (BrokerLive || execution == null || execution.Order == null)
		{
			return;
		}
		TrackNewsCommission(execution, marketPosition);
		if (execution.Order.Name == "TT_Long" && marketPosition == MarketPosition.Long)
		{
			entryPrice = price;
			entryTime = time;
			initialRisk = Math.Max(TickSize, entryPrice - stopPrice);
			breakEvenArmed = false;
			fixedSelfCloseRequested = false;
			if (newsEntryCancelPending || newsConsumedMonday == mondayDate)
			{
				newsEntryCancelPending = true;
				SubmitNewsFlatten("ENTRY_FILLED_AFTER_CANCEL");
			}
			trailStartTime = DateTime.MinValue;
			status = "LONG " + Model.ToString() + " | " + qty + " @ " + price.ToString("0.00");
			DrawExecutionMarker(entry: true, time, price);
			WriteFill("ENTRY", execution.Order.Name, time, price, qty);
		}
		else
		{
			if (execution.Order.OrderAction != OrderAction.Sell || !(entryPrice > 0.0))
			{
				return;
			}
			if (execution.Order.Name == "TT_NEWS_BLACKOUT")
			{
				newsFlattenQuantity = Math.Max(0, newsFlattenQuantity - qty);
				if (newsEntryCancelPending && marketPosition == MarketPosition.Long)
				{
					SubmitNewsFlatten("PARTIAL_LATE_FILL");
				}
			}
			if (marketPosition == MarketPosition.Flat)
			{
				DrawCompletedTrade(time, price);
				WriteFill("EXIT", execution.Order.Name, time, price, qty);
				status = "FLAT | exit " + price.ToString("0.00");
				entryPrice = 0.0;
				entryOrder = null;
				exitOrder = null;
				pendingExit = false;
				pendingExitReason = "";
				fixedSelfCloseRequested = false;
				newsFlattenQuantity = 0;
				newsEntryCancelPending = false;
			}
		}
	}

	protected override void OnMarketData(MarketDataEventArgs marketDataUpdate)
	{
		if (BrokerLive && marketDataUpdate != null)
		{
			liveQuoteUtc = ToUtc(marketDataUpdate.Time);
			PumpOwnedOrders();
		}
		if (State == State.Realtime && marketDataUpdate != null && marketDataUpdate.MarketDataType == MarketDataType.Last && OrderConnectionReady())
		{
			UpdateNewsState(ToUtc(marketDataUpdate.Time));
		}
		if (EnableFixedSelfClose && State == State.Realtime && marketDataUpdate != null && marketDataUpdate.MarketDataType == MarketDataType.Last && OwnedPosition == MarketPosition.Long && !fixedSelfCloseRequested && TuesdayTurnaroundModel.FixedCloseDue(ToNewYork(marketDataUpdate.Time), FixedSelfCloseTime, historical: false))
		{
			SubmitFixedSelfClose("REALTIME");
		}
	}

	private static DateTime ToNewYork(DateTime platformTime)
	{
		TimeZoneInfo timeZoneInfo = Globals.GeneralOptions.TimeZoneInfo;
		return TimeZoneInfo.ConvertTime(DateTime.SpecifyKind(platformTime, DateTimeKind.Unspecified), timeZoneInfo, NewYorkTimeZone);
	}

	private static DateTime ToUtc(DateTime platformTime)
	{
		TimeZoneInfo timeZoneInfo = Globals.GeneralOptions.TimeZoneInfo;
		return TimeZoneInfo.ConvertTimeToUtc(DateTime.SpecifyKind(platformTime, DateTimeKind.Unspecified), timeZoneInfo);
	}

	private void SubmitFixedSelfClose(string source)
	{
		if (OrderConnectionReady())
		{
			fixedSelfCloseRequested = true;
			SubmitOwnedExit("TT_FIXED_SELF_CLOSE");
			status = "EXIT SENT | FIXED SELF CLOSE | " + source;
		}
	}

	protected override void OnOrderUpdate(Order order, double limitPrice, double stopPriceValue, int quantityValue, int filled, double averageFillPrice, OrderState orderState, DateTime time, ErrorCode error, string comment)
	{
		if (BrokerLive)
		{
			return;
		}
		if (order != null && order.Name == "TT_Long")
		{
			entryOrder = ((orderState == OrderState.Filled || orderState == OrderState.Cancelled || orderState == OrderState.Rejected) ? null : order);
			if (orderState == OrderState.Cancelled || orderState == OrderState.Rejected)
			{
				newsEntryCancelPending = false;
			}
			if (orderState == OrderState.Rejected)
			{
				status = "ENTRY REJECTED | " + comment;
			}
		}
		else if (order != null && order.Name.StartsWith("TT_", StringComparison.Ordinal))
		{
			exitOrder = ((orderState == OrderState.Filled || orderState == OrderState.Cancelled || orderState == OrderState.Rejected) ? null : order);
			if (orderState == OrderState.Rejected)
			{
				status = "EXIT REJECTED | " + comment;
			}
		}
	}

	private string Root()
	{
		string text = Instrument.MasterInstrument.Name.ToUpperInvariant();
		if (text.StartsWith("MNQ"))
		{
			return "MNQ";
		}
		if (text.StartsWith("MES"))
		{
			return "MES";
		}
		if (text.StartsWith("NQ"))
		{
			return "NQ";
		}
		if (text.StartsWith("ES"))
		{
			return "ES";
		}
		return text;
	}

	private double RoundTurnCost()
	{
		return Root() switch
		{
			"MES" => 3.07, 
			"MNQ" => 2.32, 
			"ES" => 18.26, 
			"NQ" => 10.76, 
			_ => 0.0, 
		};
	}

	private double RoundDown(double price)
	{
		return Math.Floor(price / TickSize + 1E-09) * TickSize;
	}

	private double RoundUp(double price)
	{
		return Math.Ceiling(price / TickSize - 1E-09) * TickSize;
	}

	private void EnsureHeader()
	{
		if (csvPath.Length != 0 && !File.Exists(csvPath))
		{
			string directoryName = Path.GetDirectoryName(csvPath);
			if (!string.IsNullOrEmpty(directoryName))
			{
				Directory.CreateDirectory(directoryName);
			}
			File.AppendAllText(csvPath, "event,asset,model,monday_date,time,source_open,source_high,source_low,source_close,fill_price,quantity,reason\r\n");
		}
	}

	private void WriteAudit(string evt, TurnaroundDailyBar bar, double sourceClose, string reason)
	{
		WriteCsv(evt, bar.Date, bar.Date, bar.Open, bar.High, bar.Low, sourceClose, double.NaN, quantity, reason);
	}

	private void WriteFill(string evt, string reason, DateTime time, double fill, int qty)
	{
		WriteCsv(evt, mondayDate, time, double.NaN, double.NaN, double.NaN, double.NaN, fill, qty, reason);
	}

	private void WriteCsv(string evt, DateTime monday, DateTime time, double sourceOpen, double sourceHigh, double sourceLow, double sourceClose, double fill, int qty, string reason)
	{
		if (csvPath.Length != 0)
		{
			string text = string.Join(",", evt, Root(), Model.ToString(), monday.ToString("yyyy-MM-dd"), time.ToString("yyyy-MM-dd HH:mm:ss"), Finite(sourceOpen), Finite(sourceHigh), Finite(sourceLow), Finite(sourceClose), Finite(fill), qty.ToString(CultureInfo.InvariantCulture), reason);
			File.AppendAllText(csvPath, text + "\r\n");
		}
	}

	private static string Finite(double value)
	{
		return double.IsNaN(value) ? "" : value.ToString("0.########", CultureInfo.InvariantCulture);
	}

	private DateTime OwnedUtcNow()
	{
		return (Connection.PlaybackConnection != null) ? ToUtc(Connection.PlaybackConnection.Now) : DateTime.UtcNow;
	}

	private bool OwnedQuoteReady()
	{
		double totalSeconds = (OwnedUtcNow() - liveQuoteUtc).TotalSeconds;
		DateTime dateTime = TimeZoneInfo.ConvertTimeFromUtc(OwnedUtcNow(), NewYorkTimeZone);
		return dateTime.DayOfWeek != DayOfWeek.Saturday && (dateTime.DayOfWeek != DayOfWeek.Sunday || dateTime.Hour >= 18) && (dateTime.DayOfWeek != DayOfWeek.Friday || dateTime.Hour < 17) && (dateTime.Hour < 17 || dateTime.Hour >= 18) && liveQuoteUtc != DateTime.MinValue && totalSeconds >= -2.0 && totalSeconds <= 10.0 && GetCurrentBid(1) > 0.0;
	}

	private bool PrepareOwnedRecovery()
	{
		if (IsInStrategyAnalyzer || Account == null || Instrument == null)
		{
			return true;
		}
		try
		{
			string text = Account.Name + "|" + Instrument.FullName + "|" + RecoveryId.Trim();
			if (string.IsNullOrWhiteSpace(RecoveryId) || RecoveryId.Length > 64)
			{
				throw new InvalidDataException("Recovery ID must contain 1-64 characters");
			}
			liveLedger = new TurnaroundLiveLedger(text);
			if (Connection.PlaybackConnection != null)
			{
				liveJournalValid = true;
				return true;
			}
			string text2 = Path.Combine(Globals.UserDataDir, "TuesdayTurnaround", "Recovery");
			Directory.CreateDirectory(text2);
			using (SHA256 sHA = SHA256.Create())
			{
				livePath = Path.Combine(text2, BitConverter.ToString(sHA.ComputeHash(Encoding.UTF8.GetBytes(text))).Replace("-", "") + ".state");
			}
			liveLease = TurnaroundLiveLedger.Lease(livePath + ".lease");
			if (File.Exists(livePath))
			{
				liveLedger = TurnaroundLiveLedger.Decode(File.ReadAllBytes(livePath), text);
			}
			liveJournalValid = true;
			lock (Account.Orders)
			{
				if (Account.Orders.Any((Order o) => o.Instrument.FullName == Instrument.FullName && o.FromEntrySignal == "TT_Long" && !TerminalOrder(o.OrderState)))
				{
					throw new InvalidDataException("Legacy TT order lacks recovery identity; resolve it before enabling this build");
				}
			}
			return true;
		}
		catch (Exception ex)
		{
			liveFault = "RECOVERY BLOCKED | " + ex.Message;
			Print(Name + ": " + liveFault);
			return false;
		}
	}

	private void StartOwnedRecovery()
	{
		if (IsInStrategyAnalyzer || Account == null || liveLedger == null)
		{
			return;
		}
		foreach (TurnaroundLiveOrder order in liveLedger.Orders)
		{
			liveIdentities[order.Name] = order.Id;
		}
		Account.OrderUpdate += OwnedAccountOrderUpdate;
		Account.ExecutionUpdate += OwnedAccountExecutionUpdate;
		liveHooked = true;
		RefreshOwnedBroker();
		ApplyOwnedFields();
		status = (liveLedger.Busy ? "RECOVERING OWNED TRADE | waiting for fresh quotes" : "LIVE READY | broker-owned sleeve");
	}

	private void StopOwnedRecovery()
	{
		if (liveHooked && Account != null)
		{
			Account.OrderUpdate -= OwnedAccountOrderUpdate;
			Account.ExecutionUpdate -= OwnedAccountExecutionUpdate;
		}
		liveHooked = false;
		SaveOwnedState();
		if (liveLease != null)
		{
			liveLease.Dispose();
			liveLease = null;
		}
	}

	private bool SaveOwnedState()
	{
		if (!liveJournalValid)
		{
			return false;
		}
		if (liveLedger == null || livePath.Length == 0)
		{
			return true;
		}
		try
		{
			liveLedger.Commit(livePath);
			return true;
		}
		catch (Exception ex)
		{
			liveLedger.Blocked = true;
			liveFault = "JOURNAL FAILED | " + ex.Message;
			Print(Name + ": " + liveFault);
			return false;
		}
	}

	private static bool TerminalOrder(OrderState state)
	{
		return state == OrderState.Filled || state == OrderState.Cancelled || state == OrderState.Rejected;
	}

	private bool OwnedOrder(Order order)
	{
		string value;
		return order != null && order.Instrument != null && !string.IsNullOrEmpty(order.Name) && order.Instrument.FullName == Instrument.FullName && liveIdentities.TryGetValue(order.Name, out value) && (value.Length == 0 || value == order.OrderId || SubmittedIdentityAssigned(order, value));
	}

	private bool SubmittedIdentityAssigned(Order order, string previousId)
	{
		if (order == null || order.Account != Account || order.Instrument == null || order.Instrument.FullName != Instrument.FullName || string.IsNullOrEmpty(order.Name) || !Guid.TryParseExact(previousId, "N", out var _) || string.IsNullOrEmpty(order.OrderId) || Guid.TryParse(order.OrderId, out var _) || !liveOrders.TryGetValue(order.Name, out var value) || value != order)
		{
			return false;
		}
		TurnaroundLiveOrder turnaroundLiveOrder = liveLedger.Orders.SingleOrDefault((TurnaroundLiveOrder o) => o.Name == order.Name);
		bool num;
		if (turnaroundLiveOrder != null && turnaroundLiveOrder.Id == previousId && turnaroundLiveOrder.Quantity == order.Quantity)
		{
			if (turnaroundLiveOrder.Role != 'E')
			{
				if (order.OrderAction != OrderAction.Sell)
				{
					num = order.OrderAction == OrderAction.SellShort;
					goto IL_0171;
				}
			}
			else if (order.OrderAction != OrderAction.Buy)
			{
				num = order.OrderAction == OrderAction.BuyToCover;
				goto IL_0171;
			}
			goto IL_0173;
		}
		goto IL_0191;
		IL_0191:
		int result3 = 0;
		goto IL_0192;
		IL_0192:
		return (byte)result3 != 0;
		IL_0171:
		if (num)
		{
			goto IL_0173;
		}
		goto IL_0191;
		IL_0173:
		result3 = ((order.OrderType == (OrderType)((turnaroundLiveOrder.Role != 'S') ? 1 : 4)) ? 1 : 0);
		goto IL_0192;
	}

	private void ObserveOwnedOrder(Order order)
	{
		if (!OwnedOrder(order))
		{
			return;
		}
		if (order.OrderState == OrderState.Unknown)
		{
			liveReady = false;
		}
		else
		{
			if (string.IsNullOrEmpty(order.OrderId))
			{
				return;
			}
			TurnaroundLiveOrder turnaroundLiveOrder = liveLedger.Orders.Single((TurnaroundLiveOrder o) => o.Name == order.Name);
			if (turnaroundLiveOrder.Terminal && !TerminalOrder(order.OrderState))
			{
				liveReady = false;
				return;
			}
			liveLedger.Observe(order.Name, order.OrderId, order.Quantity, order.Filled, order.AverageFillPrice, order.StopPrice, TerminalOrder(order.OrderState), order.OrderState == OrderState.Rejected, SubmittedIdentityAssigned(order, turnaroundLiveOrder.Id));
			liveIdentities[order.Name] = order.OrderId;
			liveOrders[order.Name] = order;
			if (turnaroundLiveOrder.Role != 'E') ProductExposure.ObserveExit(order);
			if (turnaroundLiveOrder.Role == 'S' && turnaroundLiveOrder.Rejected && liveLedger.OwnQuantity > 0)
			{
				liveLedger.ExitReason = "PROTECTION_REJECTED";
			}
			if (turnaroundLiveOrder.Role == 'X' && turnaroundLiveOrder.Rejected)
			{
				liveLedger.RetryAt = OwnedUtcNow().AddSeconds(5.0);
			}
		}
	}

	private void RefreshOwnedBroker()
	{
		if (liveLedger == null || !OrderConnectionReady())
		{
			liveReady = false;
			return;
		}
		try
		{
			Order[] first;
			lock (Account.Orders)
			{
				first = Account.Orders.ToArray();
			}
			Execution[] array;
			lock (Account.Executions)
			{
				array = Account.Executions.ToArray();
			}
			first = first.Concat(from e in array
				where e.Order != null
				select e.Order).Distinct().ToArray();
			Order[] array2 = first;
			foreach (Order order in array2)
			{
				if (order.Instrument != null && order.Instrument.FullName == Instrument.FullName && !string.IsNullOrEmpty(order.Name) && liveIdentities.ContainsKey(order.Name) && !OwnedOrder(order))
				{
					throw new InvalidDataException("Owned broker ID conflicts with committed identity");
				}
				if (!OwnedOrder(order) && order.Instrument != null && order.Instrument.FullName == Instrument.FullName && !string.IsNullOrEmpty(order.Name) && order.Name.StartsWith(TurnaroundLiveLedger.Prefix(liveLedger.Identity), StringComparison.Ordinal) && !liveLedger.RetiredTags.Any((string t) => order.Name.StartsWith(t + "_", StringComparison.Ordinal)) && !TerminalOrder(order.OrderState))
				{
					throw new InvalidDataException("Broker order differs from committed identity");
				}
			}
			if ((from o in first.Where(OwnedOrder)
				group o by o.Name).Any((IGrouping<string, Order> g) => (from o in g
				where !string.IsNullOrEmpty(o.OrderId)
				select o.OrderId).Distinct().Count() > 1))
			{
				throw new InvalidDataException("Multiple broker IDs for one owned intent");
			}
			Order[] owned = (from o in first.Where(OwnedOrder)
				group o by o.Name into g
				select (from o in g
					orderby o.Filled descending, TerminalOrder(o.OrderState) descending, o.OrderState == OrderState.Unknown
					select o).First()).ToArray();
			Order[] array3 = owned;
			foreach (Order order2 in array3)
			{
				ObserveOwnedOrder(order2);
			}
			Execution[] array4 = array;
			foreach (Execution execution in array4)
			{
				if (OwnedOrder(execution.Order))
				{
					CaptureOwnedExecution(execution.Order, execution.ExecutionId, execution.Price, execution.Quantity, Math.Abs(execution.Commission), execution.Time, draw: false);
				}
			}
			liveReady = owned.All((Order o) => o.OrderState != OrderState.Unknown) && owned.All((Order o) => !liveLedger.Orders.Single((TurnaroundLiveOrder r) => r.Name == o.Name).Terminal || TerminalOrder(o.OrderState)) && liveLedger.Orders.Where((TurnaroundLiveOrder o) => !o.Terminal).All((TurnaroundLiveOrder o) => owned.Any((Order b) => b.Name == o.Name && b.OrderState != OrderState.Unknown)) && (liveLedger.OwnQuantity == 0 || OwnedAccountQuantity() >= liveLedger.OwnQuantity);
			if (!liveReady)
			{
				liveFault = "RECOVERY WAIT | broker order/position evidence incomplete";
			}
			else if (!liveLedger.Blocked)
			{
				liveFault = "";
			}
			if (!liveReady && !liveLedger.Blocked && liveLedger.OwnQuantity > 0)
			{
				string text = liveLedger.SettlementConfirmation();
				if (text != liveReportedCase)
				{
					liveReportedCase = text;
					Print(Name + ": RECOVERY_CASE " + liveLedger.Identity + " entry=" + liveLedger.Entry.ToString(CultureInfo.InvariantCulture) + " qty=" + liveLedger.OwnQuantity + " confirmation=" + text);
				}
				if (!string.IsNullOrEmpty(BrokerCloseConfirmation))
				{
					TryOwnedExternalSettlement(first);
				}
			}
			liveScanUtc = OwnedUtcNow();
			SaveOwnedState();
		}
		catch (Exception ex)
		{
			liveLedger.Blocked = true;
			liveReady = false;
			liveFault = "RECOVERY BLOCKED | " + ex.Message;
			Print(Name + ": " + liveFault);
		}
	}

	private int OwnedAccountQuantity()
	{
		lock (Account.Positions)
		{
			return Account.Positions.Where((Position p) => p.Instrument != null && p.Instrument.FullName == Instrument.FullName).Sum((Position p) => (p.MarketPosition == MarketPosition.Long) ? p.Quantity : ((p.MarketPosition == MarketPosition.Short) ? (-p.Quantity) : 0));
		}
	}

	private void TryOwnedExternalSettlement(Order[] orders)
	{
		bool flag = !orders.Any((Order o) => OwnedOrder(o) && o.OrderState != OrderState.Unknown && !TerminalOrder(o.OrderState));
		if (EnableNewTrades || !OrderConnectionReady() || OwnedAccountQuantity() != 0 || !flag || livePath.Length == 0 || BrokerCloseConfirmation.Trim() != liveLedger.SettlementConfirmation())
		{
			return;
		}
		TurnaroundLiveLedger turnaroundLiveLedger = liveLedger.SettleExternal(BrokerCloseConfirmation.Trim(), entriesDisabled: true, connectedFlat: true, noActiveOrders: true);
		if (SaveOwnedState())
		{
			string text = livePath + ".settlement_" + liveLedger.Tag;
			byte[] array = File.ReadAllBytes(livePath);
			using (FileStream fileStream = new FileStream(text + ".before", FileMode.CreateNew, FileAccess.Write, FileShare.None))
			{
				fileStream.Write(array, 0, array.Length);
				fileStream.Flush(flushToDisk: true);
			}
			using (FileStream fileStream2 = new FileStream(text + ".confirmation.txt", FileMode.CreateNew, FileAccess.Write, FileShare.None))
			{
				byte[] bytes = Encoding.UTF8.GetBytes("Administrative external closure; no synthetic fills or PnL.\r\n" + liveLedger.Identity + "\r\n" + BrokerCloseConfirmation.Trim() + "\r\nUTC=" + DateTime.UtcNow.ToString("o"));
				fileStream2.Write(bytes, 0, bytes.Length);
				fileStream2.Flush(flushToDisk: true);
			}
			turnaroundLiveLedger.Commit(livePath);
			liveLedger = turnaroundLiveLedger;
			liveIdentities.Clear();
			liveOrders.Clear();
			liveVisualRestored = false;
			liveReady = true;
			liveFault = "";
			ApplyOwnedFields();
			Print(Name + ": EXTERNAL_SETTLEMENT_COMMITTED | " + text);
		}
	}

	private static bool AccountRestriction(string message)
	{
		string text = (message ?? "").ToLowerInvariant();
		return text.Contains("liquidation only") || text.Contains("liquidation-only") || text.Contains("liquidate only") ||
			text.Contains("account is restricted") || text.Contains("account restricted") || text.Contains("trading is disabled") ||
			text.Contains("not authorized to trade") || text.Contains("no trading permissions");
	}

	private void OwnedAccountOrderUpdate(object sender, OrderEventArgs e)
	{
		if (!OwnedOrder(e.Order))
		{
			return;
		}
		Order order = e.Order;
		string restriction = e.Comment;
		try
		{
			TriggerCustomEvent((object o) =>
			{
				if (!BrokerLive || !OwnedOrder(order))
				{
					return;
				}
				try
				{
					ObserveOwnedOrder(order);
					if (AccountRestriction(restriction))
					{
						liveLedger.BrokerRestriction = restriction;
						SaveOwnedState();
						liveLedger.Blocked = true;
						liveFault = "BROKER ACCOUNT RESTRICTED | protection retained | " + restriction;
						SaveOwnedState();
						return;
					}
					ApplyOwnedFields();
					SaveOwnedState();
					PumpOwnedOrders();
				}
				catch (Exception ex2)
				{
					liveLedger.Blocked = true;
					liveFault = "OWNED ORDER ERROR | " + ex2.Message;
					Print(Name + ": " + liveFault);
				}
			}, null);
		}
		catch (InvalidOperationException)
		{
		}
	}

	private void OwnedAccountExecutionUpdate(object sender, ExecutionEventArgs e)
	{
		if (!OwnedOrder(e.Execution.Order))
		{
			return;
		}
		Order order = e.Execution.Order;
		string id = e.Execution.ExecutionId;
		double price = e.Execution.Price;
		double commission = Math.Abs(e.Execution.Commission);
		int filled = e.Execution.Quantity;
		DateTime time = e.Execution.Time;
		try
		{
			TriggerCustomEvent((object o) =>
			{
				if (!BrokerLive || !OwnedOrder(order))
				{
					return;
				}
				try
				{
					ObserveOwnedOrder(order);
					CaptureOwnedExecution(order, id, price, filled, commission, time, draw: true);
					SaveOwnedState();
					PumpOwnedOrders();
				}
				catch (Exception ex2)
				{
					liveLedger.Blocked = true;
					liveFault = "OWNED FILL ERROR | " + ex2.Message;
					Print(Name + ": " + liveFault);
				}
			}, null);
		}
		catch (InvalidOperationException)
		{
		}
	}

	private void CaptureOwnedExecution(Order order, string id, double price, int filled, double commission, DateTime time, bool draw)
	{
		if (string.IsNullOrEmpty(id) || !liveLedger.Executions.Add(id))
		{
			return;
		}
		TurnaroundLiveOrder turnaroundLiveOrder = liveLedger.Orders.Single((TurnaroundLiveOrder r) => r.Name == order.Name);
		turnaroundLiveOrder.ExecutionQuantity += filled;
		turnaroundLiveOrder.ExecutionCash += (double)filled * price;
		if (turnaroundLiveOrder.ExecutionQuantity > turnaroundLiveOrder.Quantity)
		{
			throw new InvalidDataException("Execution replay exceeds owned order quantity");
		}
		turnaroundLiveOrder.Filled = Math.Max(turnaroundLiveOrder.Filled, turnaroundLiveOrder.ExecutionQuantity);
		liveLedger.CycleCommission += commission;
		if (turnaroundLiveOrder.Role == 'E')
		{
			if (liveLedger.EntryTime == DateTime.MinValue)
			{
				liveLedger.EntryTime = time;
			}
			if (turnaroundLiveOrder.ExecutionQuantity == turnaroundLiveOrder.Filled && turnaroundLiveOrder.ExecutionQuantity > 0)
			{
				liveLedger.Observe(turnaroundLiveOrder.Name, turnaroundLiveOrder.Id, turnaroundLiveOrder.Quantity, turnaroundLiveOrder.Filled, turnaroundLiveOrder.ExecutionCash / (double)turnaroundLiveOrder.ExecutionQuantity, 0.0, turnaroundLiveOrder.Terminal, turnaroundLiveOrder.Rejected);
			}
		}
		if (liveLedger.OwnQuantity < 0)
		{
			throw new InvalidDataException("Execution replay exceeds owned position");
		}
		ApplyOwnedFields();
		if (draw)
		{
			if (turnaroundLiveOrder.Role == 'E')
			{
				DrawExecutionMarker(entry: true, time, price);
			}
			else if (liveLedger.OwnQuantity == 0)
			{
				DrawCompletedTrade(time, price);
			}
			WriteFill((turnaroundLiveOrder.Role == 'E') ? "ENTRY" : "EXIT", turnaroundLiveOrder.Name, time, price, filled);
		}
	}

	private void ApplyOwnedFields()
	{
		if (liveLedger == null)
		{
			return;
		}
		newsConsumedMonday = liveLedger.ConsumedMonday;
		newsObservedCommission = liveLedger.ObservedCommission;
		newsObservedQuantity = liveLedger.ObservedQuantity;
		newsEntryCancelPending = liveLedger.CancelEntry;
		entryOrder = null;
		exitOrder = null;
		TurnaroundLiveOrder turnaroundLiveOrder = liveLedger.Last('E');
		if (turnaroundLiveOrder != null && !turnaroundLiveOrder.Terminal)
		{
			liveOrders.TryGetValue(turnaroundLiveOrder.Name, out entryOrder);
		}
		turnaroundLiveOrder = liveLedger.Last('X');
		if (turnaroundLiveOrder != null && !turnaroundLiveOrder.Terminal)
		{
			liveOrders.TryGetValue(turnaroundLiveOrder.Name, out exitOrder);
		}
		if (!liveLedger.Busy)
		{
			newsFlattenQuantity = 0;
			return;
		}
		Model = (TurnaroundModel)liveLedger.Model;
		mondayDate = liveLedger.Monday;
		stopPrice = liveLedger.BaseStop;
		protectiveStopPrice = liveLedger.DesiredStop;
		entryPrice = liveLedger.Entry;
		initialRisk = liveLedger.Risk;
		entryTime = liveLedger.EntryTime;
		breakEvenArmed = liveLedger.BreakEven;
		trailStartTime = liveLedger.TrailTime;
		heldSessions = liveLedger.Held;
		quantity = liveLedger.OwnQuantity;
		if (!liveVisualRestored && liveLedger.OwnQuantity > 0 && entryTime > new DateTime(2000, 1, 1))
		{
			tradeInitialStop = liveLedger.BaseStop;
			tradeFridayOpen = liveLedger.FridayOpen;
			activeTradeTag = "TT_EXEC_" + liveLedger.Tag;
			if (liveLedger.MondayHigh > liveLedger.MondayLow)
			{
				TurnaroundDailyBar monday = new TurnaroundDailyBar
				{
					Date = liveLedger.Monday,
					Open = liveLedger.MondayOpen,
					High = liveLedger.MondayHigh,
					Low = liveLedger.MondayLow,
					Close = liveLedger.MondayClose
				};
				TurnaroundDailyBar friday = new TurnaroundDailyBar
				{
					Date = liveLedger.Monday.AddDays(-3.0),
					Open = liveLedger.FridayOpen,
					High = liveLedger.FridayHigh,
					Low = liveLedger.FridayLow,
					Close = liveLedger.FridayClose
				};
				RememberAndDrawSetup(friday, monday);
			}
			liveVisualRestored = true;
		}
	}

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

	private void SubmitOwnedEntry()
	{
		if (EnableNewTrades && liveLedger != null && liveReady && !liveLedger.Blocked && OwnedQuoteReady() && !liveLedger.Busy)
		{
			if (!ProductExposure.Reserve(liveLedger.Identity, 1, Account, Instrument, true, out string exposureReason))
			{
				status = exposureReason;
				return;
			}
			liveLedger.Begin((int)Model, quantity, stopPrice, mondayDate);
			liveOrders.Clear();
			liveIdentities.Clear();
			liveVisualRestored = false;
			liveLedger.MondayOpen = visualMonday.Open;
			liveLedger.MondayHigh = visualMonday.High;
			liveLedger.MondayLow = visualMonday.Low;
			liveLedger.MondayClose = visualMonday.Close;
			liveLedger.FridayOpen = visualFriday.Open;
			liveLedger.FridayHigh = visualFriday.High;
			liveLedger.FridayLow = visualFriday.Low;
			liveLedger.FridayClose = visualFriday.Close;
			liveLedger.FixedEnabled = EnableFixedSelfClose;
			liveLedger.FixedTime = FixedSelfCloseTime;
			SendOwnedOrder('E', quantity, 0.0);
			ApplyOwnedFields();
		}
	}

	private void SendOwnedOrder(char role, int size, double price)
	{
		if (!BrokerLive || !liveHooked || !OrderConnectionReady() || !OwnedQuoteReady() || liveLedger == null || liveLedger.Blocked)
		{
			return;
		}
		TurnaroundLiveOrder turnaroundLiveOrder = liveLedger.Plan(role, size, price);
		liveIdentities[turnaroundLiveOrder.Name] = "";
		if (!SaveOwnedState())
		{
			return;
		}
		try
		{
			Order order = Account.CreateOrder(Instrument, (role != 'E') ? OrderAction.Sell : OrderAction.Buy, (role != 'S') ? OrderType.Market : OrderType.StopMarket, OrderEntry.Automated, TimeInForce.Gtc, size, 0.0, price, "", turnaroundLiveOrder.Name, Globals.MaxDate, null);
			if (role != 'E') ProductExposure.ObserveExit(order);
			liveOrders[turnaroundLiveOrder.Name] = order;
			if (!string.IsNullOrEmpty(order.OrderId))
			{
				turnaroundLiveOrder.Id = order.OrderId;
			}
			liveIdentities[turnaroundLiveOrder.Name] = turnaroundLiveOrder.Id;
			if (SaveOwnedState() && BrokerLive && liveHooked && OrderConnectionReady())
			{
				Account.Submit(new Order[1] { order });
			}
		}
		catch (Exception ex)
		{
			liveLedger.Blocked = true;
			liveFault = "TRANSMISSION UNCERTAIN | " + ex.Message;
			SaveOwnedState();
			Print(Name + ": " + liveFault);
		}
	}

	private void CancelOwnedOrder(Order order)
	{
		if (order != null && OrderConnectionReady())
		{
			if (!BrokerLive)
			{
				CancelOrder(order);
			}
			else if (OwnedOrder(order) && liveReady && order.OrderState != OrderState.Unknown && OwnedQuoteReady() && !liveLedger.Blocked && order.OrderState != OrderState.CancelPending && order.OrderState != OrderState.CancelSubmitted && !TerminalOrder(order.OrderState) && SaveOwnedState())
			{
				Account.Cancel(new Order[1] { order });
			}
		}
	}

	private void SubmitOwnedExit(string reason)
	{
		if (!BrokerLive)
		{
			ExitLong(1, quantity, reason, "TT_Long");
		}
		else if (liveLedger != null && liveLedger.OwnQuantity >= 1)
		{
			if (liveLedger.ExitReason.Length == 0)
			{
				liveLedger.ExitReason = reason;
			}
			liveLedger.CancelEntry = true;
			SaveOwnedState();
			PumpOwnedOrders();
		}
	}

	private bool TightenOwnedStop(double price)
	{
		if (!BrokerLive)
		{
			SetStopLoss("TT_Long", CalculationMode.Price, price, isSimulatedStop: false);
			return true;
		}
		if (liveLedger == null || !liveReady || liveLedger.Blocked || !OwnedQuoteReady() || price > GetCurrentBid(1) - TickSize)
		{
			return false;
		}
		if (price <= liveLedger.DesiredStop)
		{
			return true;
		}
		liveLedger.DesiredStop = price;
		liveLedger.TrailTime = ((CurrentBars[1] >= 0) ? Times[1][0] : entryTime);
		if (!SaveOwnedState())
		{
			return false;
		}
		PumpOwnedOrders();
		return true;
	}

	private void OwnedDailyClose(TurnaroundDailyBar bar)
	{
		if (liveLedger == null || liveLedger.OwnQuantity < 1 || bar.Date <= liveLedger.LastDaily)
		{
			return;
		}
		liveLedger.LastDaily = bar.Date;
		liveLedger.Held++;
		if (Model == TurnaroundModel.T4)
		{
			TurnaroundDailyBar prior = (from b in daily
				where b.Date < bar.Date
				orderby b.Date
				select b).LastOrDefault();
			if (prior.Date != DateTime.MinValue && liveLedger.Held < 4 && TuesdayTurnaroundModel.T4CloseExit(bar, prior))
			{
				liveLedger.ExitReason = "CLOSE_GT_PRIOR_HIGH";
			}
		}
		if (TurnaroundLiveLedger.CompletedCloseDue(liveLedger.Model, liveLedger.Held) && liveLedger.ExitReason.Length == 0)
		{
			liveLedger.ExitReason = "OVERDUE_BASE_CLOSE";
		}
		SaveOwnedState();
		ApplyOwnedFields();
	}

	private void PumpOwnedOrders()
	{
		if (!BrokerLive || liveLedger == null || livePumping || !OrderConnectionReady())
		{
			return;
		}
		livePumping = true;
		try
		{
			if ((OwnedUtcNow() - liveScanUtc).TotalSeconds >= 1.0)
			{
				RefreshOwnedBroker();
			}
			ApplyOwnedFields();
			if (liveLedger.OwnQuantity == 0 && liveLedger.Orders.All(o => o.Received && o.Terminal && o.Filled == o.ExecutionQuantity))
				ProductExposure.Release(liveLedger.Identity);
			if (!string.IsNullOrEmpty(liveLedger.BrokerRestriction))
			{
				liveLedger.Blocked = true;
				liveFault = "BROKER ACCOUNT RESTRICTED | protection retained | " + liveLedger.BrokerRestriction;
			}
			if (!liveReady || liveLedger.Blocked)
			{
				status = liveFault;
				return;
			}
			if (liveLedger.OwnQuantity > 0)
			{
				DateTime dateTime = TimeZoneInfo.ConvertTimeFromUtc(OwnedUtcNow(), NewYorkTimeZone);
				DateTime tradingDay = ((dateTime.Hour >= 18) ? dateTime.Date.AddDays(1.0) : dateTime.Date);
				TurnaroundDailyBar[] array = (from b in daily
					where b.Date > liveLedger.LastDaily && b.Date < tradingDay
					orderby b.Date
					select b).ToArray();
				foreach (TurnaroundDailyBar bar in array)
				{
					OwnedDailyClose(bar);
				}
				if (liveLedger.FixedEnabled)
				{
					DateTime dateTime2 = liveLedger.Monday.Date.AddDays(1.0).AddHours(liveLedger.FixedTime / 10000).AddMinutes(liveLedger.FixedTime / 100 % 100)
						.AddSeconds(liveLedger.FixedTime % 100);
					if (dateTime >= dateTime2 && liveLedger.ExitReason.Length == 0)
					{
						liveLedger.ExitReason = "TT_FIXED_SELF_CLOSE";
					}
				}
			}
			if (liveLedger.CancelEntry && liveLedger.OwnQuantity > 0 && liveLedger.ExitReason.Length == 0)
			{
				liveLedger.ExitReason = "LATE_FILL_AFTER_CANCEL";
			}
			string text = liveLedger.NextAction(OrderConnectionReady(), OwnedQuoteReady());
			if (OwnedUtcNow() < liveLedger.RetryAt)
			{
				text = "WAIT";
			}
			if (text == "CANCEL_ENTRY" || text == "CANCEL_STOP")
			{
				TurnaroundLiveOrder turnaroundLiveOrder = liveLedger.Last((text == "CANCEL_ENTRY") ? 'E' : 'S');
				if (liveOrders.TryGetValue(turnaroundLiveOrder.Name, out var value))
				{
					CancelOwnedOrder(value);
				}
			}
			else if (text == "EXIT")
			{
				SendOwnedOrder('X', liveLedger.OwnQuantity, 0.0);
			}
			else if (text == "PROTECT" || text == "CHANGE_STOP")
			{
				double currentBid = GetCurrentBid(1);
				if (liveLedger.DesiredStop > currentBid - TickSize)
				{
					liveLedger.ExitReason = "STOP_LEVEL_PASSED";
					SaveOwnedState();
					return;
				}
				if (text == "PROTECT")
				{
					SendOwnedOrder('S', liveLedger.OwnQuantity, liveLedger.DesiredStop);
				}
				else
				{
					TurnaroundLiveOrder turnaroundLiveOrder2 = liveLedger.Last('S');
					if (liveOrders.TryGetValue(turnaroundLiveOrder2.Name, out var value2) && value2.OrderState == OrderState.Working && SaveOwnedState())
					{
						value2.QuantityChanged = turnaroundLiveOrder2.Filled + liveLedger.OwnQuantity;
						value2.StopPriceChanged = Math.Max(turnaroundLiveOrder2.Price, liveLedger.DesiredStop);
						Account.Change(new Order[1] { value2 });
					}
				}
			}
			if (liveLedger.OwnQuantity == 0 && !liveLedger.Busy && liveLedger.Bought > 0)
			{
				liveLedger.ObservedCommission += Math.Max(0.0, liveLedger.CycleCommission - liveLedger.BookedCommission);
				liveLedger.BookedCommission = liveLedger.CycleCommission;
				if (!liveLedger.CommissionBooked)
				{
					liveLedger.ObservedQuantity += liveLedger.Bought;
					liveLedger.CommissionBooked = true;
				}
			}
			SaveOwnedState();
			ApplyOwnedFields();
			ref string reference = ref status;
			string text2;
			if (liveFault.Length > 0)
			{
				text2 = liveFault;
			}
			else
			{
				text2 = ((liveLedger.OwnQuantity > 0) ? ("OWNED LONG " + liveLedger.OwnQuantity + " | " + text) : "FLAT | owned sleeve");
			}
			reference = text2;
		}
		catch (Exception ex)
		{
			liveLedger.Blocked = true;
			liveFault = "RECOVERY BLOCKED | " + ex.Message;
			Print(Name + ": " + liveFault);
		}
		finally
		{
			livePumping = false;
		}
	}

	private void InitializeDashboard()
	{
		dashboard = new TurnaroundDashboard();
	}

	private void StartDashboardClock()
	{
		if (!IsInStrategyAnalyzer && panelClock == null)
		{
			panelClock = new Timer(UpdatePanelClock, null, 1000, 1000);
		}
	}

	private void ShutdownDashboard()
	{
		if (panelClock != null)
		{
			panelClock.Dispose();
			panelClock = null;
		}
		HookDashboardMouse(attach: false);
	}

	private DateTime DashboardClockNy()
	{
		if (Connection.PlaybackConnection != null)
		{
			return ToNewYork(Connection.PlaybackConnection.Now);
		}
		if (State == State.Realtime)
		{
			return TimeZoneInfo.ConvertTimeFromUtc(DateTime.UtcNow, NewYorkTimeZone);
		}
		return (CurrentBars != null && CurrentBars.Length != 0 && CurrentBars[0] >= 0) ? ToNewYork(Times[0][0]) : TimeZoneInfo.ConvertTimeFromUtc(DateTime.UtcNow, NewYorkTimeZone);
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
				if (State == State.Realtime)
				{
					PumpOwnedOrders();
					if (NewsMode != TurnaroundNewsMode.Off && OrderConnectionReady())
					{
						UpdateNewsState((Connection.PlaybackConnection != null) ? ToUtc(Connection.PlaybackConnection.Now) : DateTime.UtcNow);
					}
					PublishDashboard();
					ChartControl chart = ChartControl;
					if (chart != null)
					{
						chart.Dispatcher.InvokeAsync(() =>
						{
							chart.InvalidateVisual();
						});
					}
				}
			}, null);
		}
		catch (InvalidOperationException)
		{
		}
	}

	private void PublishDashboard()
	{
		if (dashboard != null)
		{
			bool flag = OwnedPosition == MarketPosition.Long;
			string text;
			if (EnableFixedSelfClose)
			{
				text = (FixedSelfCloseTime / 10000).ToString("00") + ":" + (FixedSelfCloseTime / 100 % 100).ToString("00") + ":" + (FixedSelfCloseTime % 100).ToString("00") + " ET exit";
			}
			else if (Model == TurnaroundModel.T1 || Model == TurnaroundModel.T2)
			{
				text = "Tuesday close";
			}
			else
			{
				text = ((Model == TurnaroundModel.T3) ? "Fourth close" : "Prior high / fourth close");
			}
			dashboard.Publish(new TurnaroundDashState
			{
				Clock = DashboardClockNy().ToString("HH:mm:ss"),
				Mode = Root() + " · " + Model.ToString() + " · " + (flag ? "LIVE TRADE" : ((!haveVisualSetup) ? "WAITING FOR MONDAY" : (visualSignalConfirmed ? "VALIDATED" : "MONDAY FORMING"))),
				Status = ((liveFault.Length > 0) ? liveFault : ((!OrderConnectionReady()) ? "Disconnected · orders paused" : ((visualErrors > 0) ? ("Visual error: " + visualError) : (haveVisualSetup ? ("IBS " + TuesdayTurnaroundModel.Ibs(visualMonday).ToString("0.000") + " · C " + visualMonday.Close.ToString("0.00")) : status)))),
				RangeLabel = (haveVisualSetup ? ("MONDAY RANGE · " + visualMonday.Date.ToString("MMM dd")) : "MONDAY RANGE"),
				RangeHigh = (haveVisualSetup ? visualMonday.High.ToString("0.00") : "--"),
				RangeLow = (haveVisualSetup ? visualMonday.Low.ToString("0.00") : "--"),
				RangeWidth = (haveVisualSetup ? (visualMonday.High - visualMonday.Low).ToString("0.00") : "--"),
				Position = (flag ? ("LONG " + OwnedQuantity + " · " + RecoveryId) : "FLAT"),
				Stop = (flag ? protectiveStopPrice.ToString("0.00") : "--"),
				Risk = ((RiskMode == TurnaroundRiskMode.RiskBudget) ? ("Risk budget $" + RiskBudget.ToString("0.00")) : ("Fixed " + FixedQuantity + " contract · " + text)),
				Costs = ((NewsMode == TurnaroundNewsMode.Off) ? "" : ("News: " + NewsStatusText())),
				History = (haveVisualSetup ? ("O " + visualMonday.Open.ToString("0.00") + " · Fri C " + visualFriday.Close.ToString("0.00") + " · " + text) : text),
				InTrade = flag,
				NewsBlocked = (newsBlackoutActive || !OrderConnectionReady()),
				NewsUnavailable = !newsSourceAvailable
			});
		}
	}

	protected override void OnRender(ChartControl chartControl, ChartScale chartScale)
	{
		base.OnRender(chartControl, chartScale);
		if (dashboard == null || chartControl == null)
		{
			return;
		}
		try
		{
			if (ZOrder != int.MaxValue)
			{
				ZOrder = int.MaxValue;
			}
			HookDashboardMouse(attach: true);
			dashboard.Render(RenderTarget, chartControl);
		}
		catch (Exception e)
		{
			RecordVisualError(e);
		}
	}

	private void HookDashboardMouse(bool attach)
	{
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
		ChartControl chartControl = ChartControl;
		if (chartControl != null && dashboard != null)
		{
			Point point = DashboardPoint(chartControl, e.GetPosition(chartControl));
			if (dashboard.MouseDown(point.X, point.Y))
			{
				e.Handled = true;
				chartControl.InvalidateVisual();
			}
		}
	}

	private void DashboardMouseMove(object sender, MouseEventArgs e)
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

	private void DashboardMouseUp(object sender, MouseButtonEventArgs e)
	{
		if (dashboard != null && dashboard.MouseUp() && ChartControl != null)
		{
			e.Handled = true;
			ChartControl.InvalidateVisual();
		}
	}

	private void InitializeNews()
	{
		string text = StrategyRoot("C:\\Users\\Administrator\\Documents\\NinjaTrader 8\\bin\\Custom\\Strategies\\1. TuesdayTurnaround_NT\\TuesdayTurnaroundStrategy.cs");
		Directory.CreateDirectory(text);
		newsCalendar = new TurnaroundNewsCalendar(Path.Combine(text, "news_cache.json"), (IsInStrategyAnalyzer && !string.IsNullOrWhiteSpace(HistoricalNewsCsv)) ? Path.Combine(text, Path.GetFileName(HistoricalNewsCsv)) : "", IsInStrategyAnalyzer);
	}

	private void ShutdownNews()
	{
		if (newsCalendar != null)
		{
			newsCalendar.Dispose();
		}
		newsCalendar = null;
	}

	private bool NewsBlackout(DateTime utcNow)
	{
		activeNewsEvent = null;
		newsSourceAvailable = true;
		if (NewsMode == TurnaroundNewsMode.Off)
		{
			return false;
		}
		if (newsCalendar == null)
		{
			newsSourceAvailable = false;
			return true;
		}
		newsCalendar.Refresh();
		if (!newsCalendar.IsAvailable || !newsCalendar.HasCoverage(utcNow))
		{
			newsSourceAvailable = false;
			return true;
		}
		string[] array = NewsCurrencyList();
		TurnaroundNewsEvent[] events = newsCalendar.Events;
		foreach (TurnaroundNewsEvent turnaroundNewsEvent in events)
		{
			if (!TuesdayTurnaroundModel.SymmetricNewsWindow(utcNow, turnaroundNewsEvent.Utc, (int)NewsWindow) || !TuesdayTurnaroundModel.NewsImpactAllowed(ClassifiedImpact(turnaroundNewsEvent), (int)NewsMode))
			{
				continue;
			}
			string text = turnaroundNewsEvent.Currency.ToUpperInvariant();
			for (int j = 0; j < array.Length; j++)
			{
				if (text == array[j])
				{
					activeNewsEvent = turnaroundNewsEvent;
					return true;
				}
			}
		}
		return false;
	}

	private string[] NewsCurrencyList()
	{
		if (string.IsNullOrWhiteSpace(NewsCurrencies))
		{
			return new string[1] { "USD" };
		}
		List<string> list = new List<string>();
		string[] array = NewsCurrencies.Split(',');
		foreach (string text in array)
		{
			string text2 = text.Trim().ToUpperInvariant();
			if (text2.Length == 3 && !list.Contains(text2))
			{
				list.Add(text2);
			}
		}
		return (list.Count != 0) ? list.ToArray() : new string[1] { "USD" };
	}

	private bool UpdateNewsState(DateTime utcNow)
	{
		if (!OrderConnectionReady())
		{
			return true;
		}
		bool flag = NewsBlackout(utcNow);
		if (flag && (pendingEntry || EntryOrderCanStillFill()))
		{
			newsConsumedMonday = mondayDate;
			pendingEntry = false;
		}
		if (flag && !newsBlackoutActive)
		{
			newsBlackoutActive = true;
			if (NewsCancelPending)
			{
				pendingEntry = false;
				if (EntryOrderCanStillFill())
				{
					newsEntryCancelPending = true;
					CancelOwnedOrder(entryOrder);
				}
			}
			WriteNewsAudit("NEWS_START", utcNow);
		}
		else if (!flag && newsBlackoutActive)
		{
			newsBlackoutActive = false;
			if (!EntryOrderCanStillFill())
			{
				newsEntryCancelPending = false;
			}
			WriteNewsAudit("NEWS_END", utcNow);
		}
		if (flag && activeNewsEvent != null && utcNow < activeNewsEvent.Utc)
		{
			if (NewsFlattenPosition && OwnedPosition == MarketPosition.Long)
			{
				SubmitNewsFlatten("BLACKOUT_START");
			}
			else if (NewsCostCoveredBE)
			{
				ApplyNewsCostCoveredBE(utcNow);
			}
		}
		if (BrokerLive && liveLedger != null)
		{
			if (newsConsumedMonday > liveLedger.ConsumedMonday)
			{
				liveLedger.ConsumedMonday = newsConsumedMonday;
			}
			if (newsEntryCancelPending)
			{
				liveLedger.CancelEntry = true;
			}
			SaveOwnedState();
			PumpOwnedOrders();
		}
		return flag;
	}

	private static string ClassifiedImpact(TurnaroundNewsEvent item)
	{
		string text = (item.Title ?? "").ToUpperInvariant();
		if (text.Contains("NEW HOME SALES") || text.Contains("EXISTING HOME SALES") || text.Contains("PENDING HOME SALES") || text.Contains("CRUDE OIL") || text.Contains("OIL STOCK") || (text.Contains("EIA") && text.Contains("STOCK")))
		{
			return "Medium";
		}
		return item.Impact;
	}

	private void TrackNewsCommission(Execution execution, MarketPosition marketPosition)
	{
		if (State != State.Realtime)
		{
			return;
		}
		newsCycleCommission += Math.Abs(execution.Commission);
		if (execution.Order.Name == "TT_Long")
		{
			newsCycleQuantity += execution.Quantity;
		}
		if (execution.Order.OrderAction == OrderAction.Sell && marketPosition == MarketPosition.Flat)
		{
			if (newsCycleQuantity > 0.0 && newsCycleCommission > 0.0)
			{
				newsObservedCommission += newsCycleCommission;
				newsObservedQuantity += newsCycleQuantity;
			}
			newsCycleCommission = (newsCycleQuantity = 0.0);
		}
	}

	private double EffectiveNewsCost()
	{
		double num;
		if (NewsAssumedCommission > 0.0)
		{
			num = NewsAssumedCommission;
		}
		else
		{
			num = ((Root() == "MES" || Root() == "MNQ") ? 1.82 : 5.76);
		}
		double num2 = ((newsObservedQuantity > 0.0) ? (newsObservedCommission / newsObservedQuantity) : num);
		return num2 + (double)(2 * NewsAssumedSlipTicks) * TickSize * Instrument.MasterInstrument.PointValue;
	}

	private void ApplyNewsCostCoveredBE(DateTime utcNow)
	{
		if (OrderConnectionReady() && OwnedPosition == MarketPosition.Long && !(entryPrice <= 0.0))
		{
			double bid = ((State == State.Realtime) ? GetCurrentBid(1) : Closes[1][0]);
			double num = TuesdayTurnaroundModel.NewsCoveredStop(entryPrice, (protectiveStopPrice > 0.0) ? protectiveStopPrice : stopPrice, bid, TickSize, Instrument.MasterInstrument.PointValue, EffectiveNewsCost());
			if (!(num <= ((protectiveStopPrice > 0.0) ? protectiveStopPrice : stopPrice)) && TightenOwnedStop(num))
			{
				protectiveStopPrice = num;
				trailStartTime = ((CurrentBars[1] >= 0) ? Times[1][0] : entryTime);
				status = "NEWS BE | " + num.ToString("0.00");
				WriteNewsAudit("NEWS_COST_BE", utcNow);
			}
		}
	}

	private void SubmitNewsFlatten(string reason)
	{
		if (OrderConnectionReady() && OwnedPosition == MarketPosition.Long)
		{
			int num = Math.Max(0, OwnedQuantity - newsFlattenQuantity);
			if (num >= 1)
			{
				newsFlattenQuantity += num;
				SubmitOwnedExit("TT_NEWS_BLACKOUT");
				status = "EXIT SENT | NEWS BLACKOUT | " + reason;
			}
		}
	}

	private bool EntryOrderCanStillFill()
	{
		if (BrokerLive && liveLedger != null)
		{
			TurnaroundLiveOrder turnaroundLiveOrder = liveLedger.Last('E');
			return turnaroundLiveOrder != null && !turnaroundLiveOrder.Terminal;
		}
		if (entryOrder == null)
		{
			return false;
		}
		return entryOrder.OrderState != OrderState.Filled && entryOrder.OrderState != OrderState.Cancelled && entryOrder.OrderState != OrderState.Rejected;
	}

	private void WriteNewsAudit(string evt, DateTime utcNow)
	{
		WriteCsv(evt, mondayDate, utcNow, double.NaN, double.NaN, double.NaN, double.NaN, double.NaN, quantity, (newsCalendar == null) ? "NO_SOURCE" : newsCalendar.Provider);
	}

	private string NewsStatusText()
	{
		if (NewsMode == TurnaroundNewsMode.Off)
		{
			return "OFF";
		}
		string text = ((newsCalendar == null) ? "not loaded" : newsCalendar.Provider);
		string result;
		if (newsSourceAvailable)
		{
			result = (newsBlackoutActive ? ("BLACKOUT | " + ((activeNewsEvent == null) ? "news" : activeNewsEvent.Currency)) : ("CLEAR | " + text));
		}
		else
		{
			result = "DATA UNAVAILABLE | entries blocked";
		}
		return result;
	}

	private bool HistoricalVisualMode()
	{
		return State == State.Historical && !IsInStrategyAnalyzer;
	}

	private void ArmHistoricalShadow(TurnaroundDailyBar friday, TurnaroundDailyBar monday)
	{
		if (HistoricalVisualMode() && !shadowActive && !shadowPending)
		{
			shadowPending = true;
			shadowHeldSessions = 0;
			shadowInitialStop = stopPrice;
			shadowStop = stopPrice;
			shadowFridayOpen = friday.Open;
			shadowTag = "TT_SHADOW_" + monday.Date.ToString("yyyyMMdd");
		}
	}

	private void ProcessHistoricalShadowMinute()
	{
		if (!HistoricalVisualMode())
		{
			return;
		}
		if (shadowFixedClosePending && shadowActive)
		{
			shadowFixedClosePending = false;
			DrawShadowTrade(Times[1][0], resolved: true);
			DrawShadowExit(Times[1][0], Opens[1][0]);
			shadowActive = false;
			return;
		}
		if (shadowPending)
		{
			shadowPending = false;
			if (Opens[1][0] <= shadowInitialStop)
			{
				return;
			}
			shadowActive = true;
			shadowEntry = Opens[1][0];
			shadowEntryTime = Times[1][0];
			shadowRisk = Math.Max(TickSize, shadowEntry - shadowInitialStop);
			shadowBreakEven = false;
			shadowTrailTime = DateTime.MinValue;
			shadowFixedClosePending = false;
			DrawShadowTrade(Times[1][0], resolved: false);
		}
		if (!shadowActive)
		{
			return;
		}
		double num = double.NaN;
		if (Opens[1][0] <= shadowStop)
		{
			num = Opens[1][0];
		}
		else if (Lows[1][0] <= shadowStop)
		{
			num = shadowStop;
		}
		if (!double.IsNaN(num))
		{
			DrawShadowTrade(Times[1][0], resolved: true);
			DrawShadowExit(Times[1][0], num);
			shadowActive = false;
			return;
		}
		if (EnableFixedSelfClose && TuesdayTurnaroundModel.FixedCloseDue(ToNewYork(Times[1][0]), FixedSelfCloseTime, historical: true))
		{
			shadowFixedClosePending = true;
			return;
		}
		if (!shadowBreakEven && TuesdayTurnaroundModel.UsesBreakEven(Root()) && Highs[1][0] >= shadowEntry + 1.5 * shadowRisk)
		{
			shadowBreakEven = true;
			shadowTrailTime = Times[1][0];
			shadowStop = RoundUp(shadowEntry + RoundTurnCost() / Instrument.MasterInstrument.PointValue);
		}
		DrawShadowTrade(Times[1][0], resolved: false);
	}

	private void ProcessHistoricalShadowDaily(TurnaroundDailyBar bar)
	{
		if (!HistoricalVisualMode() || !shadowActive)
		{
			return;
		}
		shadowHeldSessions++;
		bool flag = false;
		if (Model == TurnaroundModel.T1 || Model == TurnaroundModel.T2)
		{
			flag = shadowHeldSessions >= 1;
		}
		else if (Model == TurnaroundModel.T3)
		{
			flag = shadowHeldSessions >= 4;
		}
		else if (Model == TurnaroundModel.T4 && daily.Count >= 2)
		{
			flag = TuesdayTurnaroundModel.T4CloseExit(bar, daily[daily.Count - 2]) || shadowHeldSessions >= 4;
		}
		if (flag)
		{
			if (!visibleMinuteCloseTimes.TryGetValue(bar.Date.Date, out var value))
			{
				value = bar.Date.AddHours(17.0);
			}
			DrawShadowTrade(value, resolved: true);
			DrawShadowExit(value, bar.Close);
			shadowActive = false;
		}
	}

	private void DrawShadowTrade(DateTime rightTime, bool resolved)
	{
		if (!Headless() && shadowTag.Length != 0 && !(shadowEntry <= 0.0))
		{
			TTVisuals.DrawTradeTool(this, shadowTag, isLong: true, shadowEntry, shadowStop, 0.0, shadowEntry, shadowEntryTime, shadowEntryTime, rightTime, shadowBreakEven, shadowTrailTime, synthetic: true);
			TTVisuals.DrawBoundedLine(this, shadowTag + "_ENTRY_LEVEL", shadowEntryTime, shadowEntry, rightTime, shadowEntry, TTVisuals.ClrEntryLine, DashStyleHelper.Solid, 2);
			TTVisuals.DrawBoundedLine(this, shadowTag + "_STOP_LEVEL", shadowEntryTime, shadowStop, rightTime, shadowStop, shadowBreakEven ? TTVisuals.ClrTrailingStop : TTVisuals.ClrSLBox, shadowBreakEven ? DashStyleHelper.Dot : DashStyleHelper.Solid, 2);
			DateTime start = visualFriday.Date.AddDays(-1.0).AddHours(18.0);
			TTVisuals.DrawBoundedLine(this, shadowTag + "_FRIDAY_OPEN", start, shadowFridayOpen, rightTime, shadowFridayOpen, TTVisuals.ClrEntryLine, DashStyleHelper.Dash, 2);
		}
	}

	private void DrawShadowExit(DateTime time, double price)
	{
		if (!Headless() && TryPrimaryBarsAgo(time, out var barsAgo))
		{
			Draw.ArrowDown(this, shadowTag + "_EXIT", isAutoScale: false, barsAgo, price + 3.0 * TickSize, Brushes.OrangeRed);
		}
	}

	private void FreezeHistoricalShadow()
	{
		shadowPending = false;
		shadowActive = false;
		shadowFixedClosePending = false;
	}

	private bool Headless()
	{
		return ChartControl == null || ChartPanel == null || IsInStrategyAnalyzer;
	}

	private string GeometryLabel()
	{
		switch (Root())
		{
		case "NQ":
			return "Monday low - 1 tick | BE @ +1.5R";
		case "MNQ":
			return "Monday low - 0.75 x Monday range";
		case "ES":
		case "MES":
			return "Monday low - 0.50 x Monday range";
		default:
			return "Monday low - 1 tick";
		}
	}

	private bool TryPrimaryBarsAgo(DateTime time, out int barsAgo)
	{
		int bar = BarsArray[0].GetBar(time);
		barsAgo = CurrentBars[0] - bar;
		return bar >= 0 && barsAgo >= 0;
	}

	private void RememberAndDrawSetup(TurnaroundDailyBar friday, TurnaroundDailyBar monday)
	{
		visualFriday = friday;
		visualMonday = monday;
		haveVisualSetup = true;
		visualSignalConfirmed = true;
		if (Headless())
		{
			return;
		}
		try
		{
			DrawSetupVisual(monday);
		}
		catch (Exception e)
		{
			RecordVisualError(e);
		}
	}

	private void RememberLiveMondayPreview(TurnaroundDailyBar friday, TurnaroundDailyBar monday)
	{
		visualFriday = friday;
		visualMonday = monday;
		haveVisualSetup = true;
		visualSignalConfirmed = false;
		if (Headless())
		{
			return;
		}
		try
		{
			DrawMondayRange(monday, confirmed: false);
		}
		catch (Exception e)
		{
			RecordVisualError(e);
		}
	}

	private void ClearMondayPreview(DateTime monday)
	{
		if (!visualSignalConfirmed && !(visualMonday.Date.Date != monday.Date))
		{
			string text = monday.ToString("yyyyMMdd");
			string[] array = new string[6] { "TT_MON_H_", "TT_MON_L_", "TT_MON_O_", "TT_MON_C_", "TT_SIG_", "TT_SIG_TEXT_" };
			foreach (string text2 in array)
			{
				RemoveDrawObject(text2 + text);
			}
			haveVisualSetup = false;
		}
	}

	private void DrawSetupVisual(TurnaroundDailyBar monday)
	{
		DrawMondayRange(monday, confirmed: true);
	}

	private void DrawMondayRange(TurnaroundDailyBar monday, bool confirmed)
	{
		DateTime time = monday.Date.AddDays(-1.0).AddHours(18.0);
		DateTime time2;
		if (confirmed)
		{
			time2 = monday.Date.AddHours(17.0);
		}
		else
		{
			time2 = ((CurrentBars[1] >= 0) ? Times[1][0] : Times[0][0]);
		}
		if (TryPrimaryBarsAgo(time, out var barsAgo) && TryPrimaryBarsAgo(time2, out var barsAgo2))
		{
			string text = monday.Date.ToString("yyyyMMdd");
			double y = monday.Low - 8.0 * TickSize;
			double y2 = monday.Low - 36.0 * TickSize;
			Draw.Line(this, "TT_MON_H_" + text, isAutoScale: false, barsAgo, monday.High, barsAgo2, monday.High, Brushes.Goldenrod, DashStyleHelper.Solid, 2);
			Draw.Line(this, "TT_MON_L_" + text, isAutoScale: false, barsAgo, monday.Low, barsAgo2, monday.Low, Brushes.Goldenrod, DashStyleHelper.Solid, 2);
			Draw.Line(this, "TT_MON_O_" + text, isAutoScale: false, barsAgo, monday.Open, barsAgo2, monday.Open, Brushes.SlateGray, DashStyleHelper.Dot, 1);
			Draw.Line(this, "TT_MON_C_" + text, isAutoScale: false, barsAgo, monday.Close, barsAgo2, monday.Close, Brushes.DeepSkyBlue, DashStyleHelper.Dash, 2);
			if (confirmed)
			{
				Draw.ArrowUp(this, "TT_SIG_" + text, isAutoScale: false, barsAgo2, y, Brushes.Gold);
				Draw.Text(this, "TT_SIG_TEXT_" + text, isAutoScale: false, Model.ToString() + " | IBS " + TuesdayTurnaroundModel.Ibs(monday).ToString("0.000"), barsAgo2, y2, 0, Brushes.Gold, new SimpleFont("Segoe UI", 9), TextAlignment.Center, Brushes.Transparent, Brushes.Transparent, 0);
			}
		}
	}

	private void UpdateTurnaroundVisuals()
	{
		if (Headless())
		{
			return;
		}
		try
		{
			if (haveVisualSetup)
			{
				DrawMondayRange(visualMonday, visualSignalConfirmed);
			}
			if (OwnedPosition == MarketPosition.Long && entryPrice > 0.0)
			{
				DrawOrbExecutionTool((CurrentBars[1] >= 0) ? Times[1][0] : Times[0][0], resolved: false);
				if (TuesdayTurnaroundModel.UsesBreakEven(Root()))
				{
					Draw.HorizontalLine(this, "TT_ACTIVE_TRIGGER", isAutoScale: false, entryPrice + 1.5 * initialRisk, Brushes.MediumPurple, DashStyleHelper.Dot, 1);
				}
			}
			else
			{
				RemoveDrawObject("TT_ACTIVE_ENTRY");
				RemoveDrawObject("TT_ACTIVE_STOP");
				RemoveDrawObject("TT_ACTIVE_TRIGGER");
				RemoveDrawObject("TT_ACTIVE_ENTRY_TEXT");
				RemoveDrawObject("TT_ACTIVE_STOP_TEXT");
			}
			RemoveDrawObject("TT_STATUS");
			PublishDashboard();
		}
		catch (Exception e)
		{
			RecordVisualError(e);
		}
	}

	private void DrawExecutionMarker(bool entry, DateTime time, double price)
	{
		if (Headless())
		{
			return;
		}
		try
		{
			if (TryPrimaryBarsAgo(time, out var barsAgo))
			{
				if (entry)
				{
					tradeInitialStop = stopPrice;
					tradeFridayOpen = visualFriday.Open;
					activeTradeTag = "TT_EXEC_" + mondayDate.ToString("yyyyMMdd");
					Draw.ArrowUp(this, "TT_ENTRY_" + time.Ticks, isAutoScale: false, barsAgo, price - 3.0 * TickSize, Brushes.DodgerBlue);
					DrawOrbExecutionTool(time.AddMinutes(1.0), resolved: false);
				}
				else
				{
					Draw.ArrowDown(this, "TT_EXIT_" + time.Ticks, isAutoScale: false, barsAgo, price + 3.0 * TickSize, Brushes.OrangeRed);
				}
			}
		}
		catch (Exception e)
		{
			RecordVisualError(e);
		}
	}

	private void DrawCompletedTrade(DateTime exitTime, double exitPrice)
	{
		if (Headless())
		{
			return;
		}
		try
		{
			DrawExecutionMarker(entry: false, exitTime, exitPrice);
			DrawOrbExecutionTool(exitTime, resolved: true);
			if (TryPrimaryBarsAgo(entryTime, out var barsAgo) && TryPrimaryBarsAgo(exitTime, out var barsAgo2))
			{
				Draw.Line(this, "TT_TRADE_" + exitTime.Ticks, isAutoScale: false, barsAgo, entryPrice, barsAgo2, exitPrice, (exitPrice >= entryPrice) ? Brushes.LimeGreen : Brushes.Red, DashStyleHelper.Solid, 2);
				Draw.Line(this, "TT_ENTRY_LINE_" + exitTime.Ticks, isAutoScale: false, barsAgo, entryPrice, barsAgo2, entryPrice, Brushes.DodgerBlue, DashStyleHelper.Dash, 2);
				Draw.Line(this, "TT_STOP_LINE_" + exitTime.Ticks, isAutoScale: false, barsAgo, tradeInitialStop, barsAgo2, tradeInitialStop, Brushes.OrangeRed, DashStyleHelper.Solid, 2);
			}
			RemoveDrawObject("TT_ACTIVE_ENTRY");
			RemoveDrawObject("TT_ACTIVE_STOP");
			RemoveDrawObject("TT_ACTIVE_TRIGGER");
			RemoveDrawObject("TT_ACTIVE_ENTRY_TEXT");
			RemoveDrawObject("TT_ACTIVE_STOP_TEXT");
		}
		catch (Exception e)
		{
			RecordVisualError(e);
		}
	}

	private void DrawOrbExecutionTool(DateTime rightTime, bool resolved)
	{
		if (!Headless() && !(entryPrice <= 0.0) && activeTradeTag.Length != 0)
		{
			double num = ((protectiveStopPrice > 0.0) ? protectiveStopPrice : tradeInitialStop);
			bool flag = num > tradeInitialStop;
			TTVisuals.DrawTradeTool(this, activeTradeTag, isLong: true, entryPrice, num, 0.0, entryPrice, entryTime, entryTime, rightTime, flag, trailStartTime, synthetic: false);
			TTVisuals.DrawBoundedLine(this, activeTradeTag + "_ENTRY_LEVEL", entryTime, entryPrice, rightTime, entryPrice, TTVisuals.ClrEntryLine, DashStyleHelper.Solid, 2);
			TTVisuals.DrawBoundedLine(this, activeTradeTag + "_STOP_LEVEL", entryTime, num, rightTime, num, flag ? TTVisuals.ClrTrailingStop : TTVisuals.ClrSLBox, flag ? DashStyleHelper.Dot : DashStyleHelper.Solid, 2);
			DateTime start = visualFriday.Date.AddDays(-1.0).AddHours(18.0);
			TTVisuals.DrawBoundedLine(this, activeTradeTag + "_FRIDAY_OPEN", start, tradeFridayOpen, rightTime, tradeFridayOpen, TTVisuals.ClrEntryLine, DashStyleHelper.Dash, 2);
			if (resolved)
			{
				activeTradeTag = "";
			}
		}
	}

	private void RecordVisualError(Exception e)
	{
		visualErrors++;
		visualError = e.GetType().Name + ": " + e.Message;
		if (visualErrors == 1)
		{
			Print("TuesdayTurnaround visual error: " + e);
		}
	}
}

public static class TuesdayTurnaroundModel
{
	public static double Ibs(TurnaroundDailyBar bar)
	{
		double num = bar.High - bar.Low;
		return (num > 0.0) ? ((bar.Close - bar.Low) / num) : double.NaN;
	}

	public static bool Signal(TurnaroundModel model, TurnaroundDailyBar friday, TurnaroundDailyBar monday)
	{
		if (monday.Date.DayOfWeek != DayOfWeek.Monday)
		{
			return false;
		}
		if (friday.Date.Date != monday.Date.Date.AddDays(-3.0))
		{
			return false;
		}
		double num = Ibs(monday);
		switch (model)
		{
		case TurnaroundModel.T1:
			return monday.Close <= 0.99 * friday.Close;
		case TurnaroundModel.T2:
			return monday.Close < monday.Open && num < 0.2;
		case TurnaroundModel.T3:
		case TurnaroundModel.T4:
			return monday.Close < friday.Close && num < 0.5;
		default:
			return false;
		}
	}

	public static double StopPrice(string root, TurnaroundDailyBar monday, double tickSize)
	{
		double num = monday.High - monday.Low;
		double num2;
		switch (root)
		{
		default:
			num2 = 0.0;
			break;
		case "ES":
		case "MES":
			num2 = 0.5;
			break;
		case "MNQ":
			num2 = 0.75;
			break;
		}
		double num3 = num2;
		return (num3 > 0.0) ? (monday.Low - num3 * num) : (monday.Low - tickSize);
	}

	public static bool UsesBreakEven(string root)
	{
		return root == "NQ";
	}

	public static bool UsesNativeSessionClose(TurnaroundModel model)
	{
		return false;
	}

	public static bool TimedExitDue(TurnaroundModel model, int completedSessions)
	{
		int num = ((model != TurnaroundModel.T1 && model != TurnaroundModel.T2) ? 3 : 0);
		return completedSessions >= num;
	}

	public static bool ValidClock(int hhmmss)
	{
		int num = hhmmss / 10000;
		int num2 = hhmmss / 100 % 100;
		int num3 = hhmmss % 100;
		return num >= 0 && num < 18 && num2 >= 0 && num2 < 60 && num3 >= 0 && num3 < 60;
	}

	public static bool FixedCloseDue(DateTime marketTime, int hhmmss, bool historical)
	{
		if (!ValidClock(hhmmss))
		{
			return false;
		}
		int num = marketTime.Hour * 10000 + marketTime.Minute * 100 + marketTime.Second;
		int num2 = (historical ? (hhmmss / 100 * 100) : hhmmss);
		return num >= num2 && num < 180000;
	}

	public static int Quantity(double entryEstimate, double stop, double pointValue, double roundTurnCost, double riskBudget)
	{
		double num = Math.Abs(entryEstimate - stop) * pointValue + roundTurnCost;
		return (num > 0.0) ? Math.Max(0, (int)Math.Floor(riskBudget / num)) : 0;
	}

	public static bool T4CloseExit(TurnaroundDailyBar current, TurnaroundDailyBar prior)
	{
		return current.Close > prior.High;
	}

	public static bool UpdatePreview(ref TurnaroundDailyBar preview, DateTime tradingDay, double open, double high, double low, double close)
	{
		if (preview.Date.Date != tradingDay.Date)
		{
			preview = new TurnaroundDailyBar
			{
				Date = tradingDay.Date,
				Open = open,
				High = high,
				Low = low,
				Close = close
			};
			return true;
		}
		preview.High = Math.Max(preview.High, high);
		preview.Low = Math.Min(preview.Low, low);
		preview.Close = close;
		return false;
	}

	public static bool NewsWindow(DateTime nowUtc, DateTime eventUtc, int minutesBefore, int minutesAfter)
	{
		return nowUtc >= eventUtc.AddMinutes(-Math.Max(0, minutesBefore)) && nowUtc <= eventUtc.AddMinutes(Math.Max(0, minutesAfter));
	}

	public static bool NewsImpactAllowed(string impact, int mode)
	{
		if (mode <= 0)
		{
			return false;
		}
		bool flag = string.Equals(impact, "High", StringComparison.OrdinalIgnoreCase);
		bool flag2 = string.Equals(impact, "Medium", StringComparison.OrdinalIgnoreCase);
		return ((mode >= 3) | flag) || ((mode >= 2) & flag2);
	}

	public static bool SymmetricNewsWindow(DateTime nowUtc, DateTime eventUtc, int totalMinutes)
	{
		int num = Math.Max(0, totalMinutes) * 30;
		return nowUtc >= eventUtc.AddSeconds(-num) && nowUtc <= eventUtc.AddSeconds(num);
	}

	public static double NewsCoveredStop(double entry, double currentStop, double bid, double tickSize, double pointValue, double cost)
	{
		if (tickSize <= 0.0 || pointValue <= 0.0 || bid <= 0.0)
		{
			return currentStop;
		}
		double num = Math.Ceiling((entry + Math.Max(0.0, cost) / pointValue) / tickSize - 1E-09) * tickSize;
		return (num > currentStop && num <= bid - tickSize) ? num : currentStop;
	}

	public static string SelfTest()
	{
		TurnaroundDailyBar turnaroundDailyBar = new TurnaroundDailyBar
		{
			Date = new DateTime(2023, 1, 27),
			Open = 4100.0,
			High = 4110.0,
			Low = 4070.0,
			Close = 4084.0
		};
		TurnaroundDailyBar monday = new TurnaroundDailyBar
		{
			Date = new DateTime(2023, 1, 30),
			Open = 4077.0,
			High = 4086.0,
			Low = 4029.5,
			Close = 4039.75
		};
		if (!Signal(TurnaroundModel.T1, turnaroundDailyBar, monday))
		{
			return "T1 threshold";
		}
		if (!Signal(TurnaroundModel.T2, turnaroundDailyBar, monday))
		{
			return "T2 IBS";
		}
		if (!Signal(TurnaroundModel.T3, turnaroundDailyBar, monday))
		{
			return "T3 weakness";
		}
		TurnaroundDailyBar friday = turnaroundDailyBar;
		friday.Date = new DateTime(2023, 1, 26);
		if (Signal(TurnaroundModel.T3, friday, monday))
		{
			return "exact preceding Friday";
		}
		if (Math.Abs(StopPrice("ES", monday, 0.25) - 4001.25) > 1E-09)
		{
			return "ES range stop";
		}
		if (Math.Abs(StopPrice("MNQ", monday, 0.25) - 3987.125) > 1E-09)
		{
			return "MNQ range stop";
		}
		if (Math.Abs(StopPrice("NQ", monday, 0.25) - 4029.25) > 1E-09)
		{
			return "NQ low stop";
		}
		if (!T4CloseExit(new TurnaroundDailyBar
		{
			Close = 101.0
		}, new TurnaroundDailyBar
		{
			High = 100.0
		}))
		{
			return "T4 close exit";
		}
		if (T4CloseExit(new TurnaroundDailyBar
		{
			Close = 100.0
		}, new TurnaroundDailyBar
		{
			High = 100.0
		}))
		{
			return "T4 strict exit";
		}
		if (UsesNativeSessionClose(TurnaroundModel.T1) || UsesNativeSessionClose(TurnaroundModel.T2) || UsesNativeSessionClose(TurnaroundModel.T3) || UsesNativeSessionClose(TurnaroundModel.T4))
		{
			return "native session close disabled";
		}
		if (!TimedExitDue(TurnaroundModel.T1, 0))
		{
			return "first-session deadline";
		}
		if (!TimedExitDue(TurnaroundModel.T3, 3) || TimedExitDue(TurnaroundModel.T3, 2))
		{
			return "four-session deadline";
		}
		DateTime marketTime = new DateTime(2026, 9, 15, 16, 44, 55);
		if (!ValidClock(164455) || ValidClock(166099))
		{
			return "fixed close clock validation";
		}
		if (!FixedCloseDue(marketTime, 164455, historical: false))
		{
			return "realtime fixed close second";
		}
		if (!FixedCloseDue(new DateTime(2026, 9, 15, 16, 44, 0), 164455, historical: true))
		{
			return "historical fixed close minute";
		}
		if (FixedCloseDue(new DateTime(2026, 9, 15, 16, 43, 0), 164455, historical: true))
		{
			return "fixed close not early";
		}
		if (Quantity(100.0, 95.0, 5.0, 3.07, 500.0) != 17)
		{
			return "risk sizing";
		}
		TurnaroundDailyBar preview = default;
		if (!UpdatePreview(ref preview, new DateTime(2026, 10, 5), 100.0, 102.0, 99.0, 101.0) || preview.Open != 100.0 || preview.High != 102.0 || preview.Low != 99.0 || preview.Close != 101.0)
		{
			return "Monday preview initialize";
		}
		if (UpdatePreview(ref preview, new DateTime(2026, 10, 5), 101.0, 105.0, 98.0, 104.0) || preview.Open != 100.0 || preview.High != 105.0 || preview.Low != 98.0 || preview.Close != 104.0)
		{
			return "Monday preview update";
		}
		if (!NewsWindow(new DateTime(2026, 10, 5, 13, 20, 0), new DateTime(2026, 10, 5, 13, 30, 0), 10, 10) || !NewsWindow(new DateTime(2026, 10, 5, 13, 40, 0), new DateTime(2026, 10, 5, 13, 30, 0), 10, 10) || NewsWindow(new DateTime(2026, 10, 5, 13, 19, 59), new DateTime(2026, 10, 5, 13, 30, 0), 10, 10))
		{
			return "news window boundaries";
		}
		if (!NewsImpactAllowed("High", 1) || NewsImpactAllowed("Medium", 1) || !NewsImpactAllowed("Medium", 2) || NewsImpactAllowed("Low", 2) || !NewsImpactAllowed("Low", 3))
		{
			return "news impact filter";
		}
		return "";
	}
}

public struct TurnaroundDailyBar
{
	public DateTime Date;

	public double Open;

	public double High;

	public double Low;

	public double Close;
}

internal sealed class TurnaroundDashState
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

	internal string RangeLabel;

	internal bool InTrade;

	internal bool NewsBlocked;

	internal bool NewsUnavailable;
}

internal sealed class TurnaroundDashboard
{
	private readonly object sync = new object();

	private TurnaroundDashState state;

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

	internal void Publish(TurnaroundDashState next)
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
		TurnaroundDashState turnaroundDashState;
		bool flag;
		double num;
		double num2;
		lock (sync)
		{
			turnaroundDashState = state;
			flag = collapsed;
			num = offsetX;
			num2 = offsetY;
		}
		if (turnaroundDashState == null || rt == null || chart == null)
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
		using (SolidColorBrush brush = new SolidColorBrush(rt, new Color4(12f / 255f, 1f / 15f, 27f / 255f, 241f / 255f)))
		{
			using SolidColorBrush brush2 = new SolidColorBrush(rt, new Color4(182f / 255f, 205f / 255f, 235f / 255f, 110f / 255f));
			using SolidColorBrush solidColorBrush = new SolidColorBrush(rt, new Color4(14f / 15f, 244f / 255f, 250f / 255f, 1f));
			using SolidColorBrush solidColorBrush2 = new SolidColorBrush(rt, new Color4(165f / 255f, 181f / 255f, 0.8f, 1f));
			using SolidColorBrush brush3 = new SolidColorBrush(rt, new Color4(115f / 255f, 171f / 255f, 1f, 1f));
			using SolidColorBrush solidColorBrush3 = new SolidColorBrush(rt, new Color4(91f / 255f, 215f / 255f, 164f / 255f, 1f));
			using SolidColorBrush solidColorBrush4 = new SolidColorBrush(rt, new Color4(1f, 125f / 255f, 128f / 255f, 1f));
			using SharpDX.DirectWrite.Factory factory = new SharpDX.DirectWrite.Factory();
			rt.FillRoundedRectangle(roundedRect, brush);
			rt.DrawRoundedRectangle(roundedRect, brush2, 1f);
			rt.FillRectangle(new RectangleF(num3 + 12f, num4 + 14f, 2f, 39f), brush3);
			Text(rt, factory, "TUESDAY TURNAROUND", 13f, solidColorBrush, num3 + 24f, num4 + 13f, 143f, bold: true);
			Text(rt, factory, turnaroundDashState.Mode, 9f, solidColorBrush2, num3 + 24f, num4 + 34f, 151f);
			Text(rt, factory, "NEW YORK", 8.5f, solidColorBrush2, num6 - 98f, num4 + 13f, 80f, bold: false, right: true);
			Text(rt, factory, turnaroundDashState.Clock, 13f, solidColorBrush, num6 - 98f, num4 + 32f, 80f, bold: true, right: true);
			RoundedRectangle roundedRect2 = new RoundedRectangle
			{
				Rect = new RectangleF(num6 - 12f, num4 + 13f, 19f, 19f),
				RadiusX = 6f,
				RadiusY = 6f
			};
			rt.FillRoundedRectangle(roundedRect2, brush2);
			Text(rt, factory, flag ? "+" : "−", 13f, solidColorBrush, num6 - 12f, num4 + 14f, 19f, bold: false, right: false, center: true);
			if (!flag)
			{
				Rule(rt, brush2, num3 + 20f, num4 + 61f, 222f);
				Text(rt, factory, turnaroundDashState.Status, 11.5f, turnaroundDashState.NewsBlocked ? solidColorBrush4 : solidColorBrush, num3 + 20f, num4 + 69f, 222f);
				Text(rt, factory, turnaroundDashState.RangeLabel, 9f, solidColorBrush2, num3 + 20f, num4 + 95f, 184f);
				Text(rt, factory, turnaroundDashState.RangeWidth, 13f, solidColorBrush, num6 - 55f, num4 + 92f, 55f, bold: true, right: true);
				Text(rt, factory, "HIGH", 9f, solidColorBrush3, num3 + 20f, num4 + 122f, 30f);
				Text(rt, factory, turnaroundDashState.RangeHigh, 13f, solidColorBrush, num3 + 57f, num4 + 119f, 65f, bold: true, right: true);
				Text(rt, factory, "LOW", 9f, solidColorBrush4, num3 + 140f, num4 + 122f, 30f);
				Text(rt, factory, turnaroundDashState.RangeLow, 13f, solidColorBrush, num3 + 177f, num4 + 119f, 65f, bold: true, right: true);
				Rule(rt, brush2, num3 + 20f, num4 + 149f, 222f);
				Text(rt, factory, "POSITION", 9f, solidColorBrush2, num3 + 20f, num4 + 159f, 106f);
				Text(rt, factory, "HARD STOP", 9f, solidColorBrush2, num3 + 139f, num4 + 159f, num6 - num3 - 139f, bold: false, right: true);
				Text(rt, factory, turnaroundDashState.Position, 13f, turnaroundDashState.InTrade ? solidColorBrush3 : solidColorBrush, num3 + 20f, num4 + 174f, 106f, bold: true);
				Text(rt, factory, turnaroundDashState.Stop, 13f, solidColorBrush4, num3 + 139f, num4 + 174f, num6 - num3 - 139f, bold: true, right: true);
				Rule(rt, brush2, num3 + 20f, num4 + 199f, 222f);
				Text(rt, factory, turnaroundDashState.Risk, 11.5f, solidColorBrush, num3 + 20f, num4 + 210f, 222f);
				if (!string.IsNullOrEmpty(turnaroundDashState.Costs))
				{
					RenderTarget rt2 = rt;
					SharpDX.DirectWrite.Factory dw = factory;
					string costs = turnaroundDashState.Costs;
					SolidColorBrush brush4;
					if (turnaroundDashState.NewsUnavailable)
					{
						brush4 = solidColorBrush2;
					}
					else
					{
						brush4 = (turnaroundDashState.NewsBlocked ? solidColorBrush4 : solidColorBrush3);
					}
					Text(rt2, dw, costs, 9.5f, brush4, num3 + 20f, num4 + 229f, 222f);
				}
				Text(rt, factory, turnaroundDashState.History, 8.5f, solidColorBrush2, num3 + 20f, num4 + 248f, 222f);
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

internal sealed class TurnaroundLiveLedger
{
	internal string BrokerRestriction = "";
	internal readonly string Identity;

	internal string Tag = "";

	internal string ExitReason = "";

	internal int Model = 1;

	internal int Requested;

	internal int Held;

	internal int FixedTime = 164455;

	internal double BaseStop;

	internal double DesiredStop;

	internal double Entry;

	internal double Risk;

	internal double CycleCommission;

	internal double ObservedCommission;

	internal double ObservedQuantity;

	internal double BookedCommission;

	internal double MondayOpen;

	internal double MondayHigh;

	internal double MondayLow;

	internal double MondayClose;

	internal double FridayOpen;

	internal double FridayHigh;

	internal double FridayLow;

	internal double FridayClose;

	internal bool BreakEven;

	internal bool CancelEntry;

	internal bool FixedEnabled;

	internal bool Blocked;

	internal bool CommissionBooked;

	internal DateTime Monday;

	internal DateTime EntryTime;

	internal DateTime TrailTime;

	internal DateTime LastDaily;

	internal DateTime ConsumedMonday;

	internal DateTime RetryAt;

	internal readonly List<TurnaroundLiveOrder> Orders = new List<TurnaroundLiveOrder>();

	internal readonly HashSet<string> Executions = new HashSet<string>();

	internal readonly HashSet<string> RetiredTags = new HashSet<string>();

	private string committedHash = "";

	internal int Bought => Orders.Where((TurnaroundLiveOrder o) => o.Role == 'E').Sum((TurnaroundLiveOrder o) => o.Filled);

	internal int Sold => Orders.Where((TurnaroundLiveOrder o) => o.Role != 'E').Sum((TurnaroundLiveOrder o) => o.Filled);

	internal int OwnQuantity => Bought - Sold;

	internal bool Busy => OwnQuantity > 0 || Orders.Any((TurnaroundLiveOrder o) => !o.Terminal);

	internal TurnaroundLiveLedger(string identity)
	{
		Identity = identity;
	}

	internal TurnaroundLiveOrder Last(char role)
	{
		return Orders.LastOrDefault((TurnaroundLiveOrder o) => o.Role == role);
	}

	internal string SettlementConfirmation()
	{
		string s = Identity + "|" + Tag + "|" + Bought + "|" + Sold + "|" + string.Join(";", Orders.Select((TurnaroundLiveOrder o) => o.Name + ":" + o.Id + ":" + o.Filled));
		using SHA256 sHA = SHA256.Create();
		return "CLOSED " + BitConverter.ToString(sHA.ComputeHash(Encoding.UTF8.GetBytes(s))).Replace("-", "") + " NO_ORDERS";
	}

	internal TurnaroundLiveLedger SettleExternal(string confirmation, bool entriesDisabled, bool connectedFlat, bool noActiveOrders)
	{
		if (Blocked || !entriesDisabled || !connectedFlat || !noActiveOrders || OwnQuantity < 1 || Orders.Any((TurnaroundLiveOrder o) => o.Role == 'E' && (!o.Terminal || o.Filled != o.Quantity)) || confirmation != SettlementConfirmation())
		{
			throw new InvalidOperationException("Broker closure confirmation conditions not met");
		}
		TurnaroundLiveLedger turnaroundLiveLedger = new TurnaroundLiveLedger(Identity)
		{
			ConsumedMonday = ConsumedMonday,
			ObservedCommission = ObservedCommission,
			ObservedQuantity = ObservedQuantity
		};
		turnaroundLiveLedger.RetiredTags.UnionWith(RetiredTags);
		turnaroundLiveLedger.RetiredTags.Add(Tag);
		return turnaroundLiveLedger;
	}

	internal void Begin(int model, int quantity, double stop, DateTime monday)
	{
		if (Busy || Blocked)
		{
			throw new InvalidOperationException("Existing sleeve is unresolved");
		}
		if (model < 1 || model > 4 || quantity < 1 || !Finite(stop) || stop <= 0.0)
		{
			throw new InvalidDataException("Invalid entry intent");
		}
		Tag = Prefix(Identity) + Guid.NewGuid().ToString("N");
		Model = model;
		Requested = quantity;
		BaseStop = (DesiredStop = stop);
		Monday = (ConsumedMonday = monday);
		LastDaily = monday;
		EntryTime = (TrailTime = (RetryAt = DateTime.MinValue));
		Entry = (Risk = (CycleCommission = (BookedCommission = 0.0)));
		Held = 0;
		BreakEven = (CancelEntry = (CommissionBooked = false));
		ExitReason = "";
		Orders.Clear();
		Executions.Clear();
	}

	internal TurnaroundLiveOrder Plan(char role, int quantity, double price)
	{
		if (Tag.Length == 0 || Orders.Count >= 128 || quantity < 1 || quantity > Requested || (role != 'E' && role != 'S' && role != 'X'))
		{
			throw new InvalidDataException("Invalid owned order intent");
		}
		if (Orders.Any((TurnaroundLiveOrder o) => o.Role == role && !o.Terminal))
		{
			throw new InvalidDataException("An owned order of this role is still unresolved");
		}
		TurnaroundLiveOrder turnaroundLiveOrder = new TurnaroundLiveOrder
		{
			Name = Tag + "_" + role + Orders.Count,
			Role = role,
			Quantity = quantity,
			Price = price
		};
		Orders.Add(turnaroundLiveOrder);
		return turnaroundLiveOrder;
	}

	internal void Observe(string name, string id, int quantity, int filled, double average, double price, bool terminal, bool rejected, bool submittedIdentityAssigned = false)
	{
		TurnaroundLiveOrder turnaroundLiveOrder = Orders.SingleOrDefault((TurnaroundLiveOrder o) => o.Name == name);
		if (turnaroundLiveOrder == null || string.IsNullOrEmpty(id) || (turnaroundLiveOrder.Id.Length > 0 && turnaroundLiveOrder.Id != id && !submittedIdentityAssigned) || quantity < 1 || quantity > Requested || filled < 0 || filled > quantity || !Finite(average) || !Finite(price))
		{
			throw new InvalidDataException("Broker order identity or quantity mismatch");
		}
		turnaroundLiveOrder.Id = id;
		turnaroundLiveOrder.Received = true;
		turnaroundLiveOrder.Quantity = quantity;
		turnaroundLiveOrder.Filled = Math.Max(turnaroundLiveOrder.Filled, filled);
		turnaroundLiveOrder.Average = ((average > 0.0) ? average : turnaroundLiveOrder.Average);
		turnaroundLiveOrder.Price = ((price > 0.0) ? price : turnaroundLiveOrder.Price);
		turnaroundLiveOrder.Terminal |= terminal;
		turnaroundLiveOrder.Rejected |= rejected;
		if (OwnQuantity < 0)
		{
			throw new InvalidDataException("Owned sells exceed confirmed buys");
		}
		if (turnaroundLiveOrder.Role == 'E' && turnaroundLiveOrder.Average > 0.0)
		{
			Entry = turnaroundLiveOrder.Average;
			if (!BreakEven && DesiredStop <= BaseStop)
			{
				Risk = Entry - BaseStop;
			}
		}
		if (turnaroundLiveOrder.Role == 'S' && !turnaroundLiveOrder.Terminal && price > 0.0)
		{
			DesiredStop = Math.Max(DesiredStop, price);
			if (Entry > 0.0 && price >= Entry)
			{
				BreakEven = true;
			}
		}
		if (turnaroundLiveOrder.Role == 'S' && turnaroundLiveOrder.Filled > 0)
		{
			CancelEntry = true;
			if (ExitReason.Length == 0)
			{
				ExitReason = "STOP_FILL";
			}
		}
	}

	internal string NextAction(bool connected, bool freshQuotes)
	{
		if (!connected || !freshQuotes || Blocked || Tag.Length == 0)
		{
			return "WAIT";
		}
		TurnaroundLiveOrder turnaroundLiveOrder = Last('E');
		TurnaroundLiveOrder turnaroundLiveOrder2 = Last('S');
		TurnaroundLiveOrder turnaroundLiveOrder3 = Last('X');
		if ((CancelEntry || ExitReason.Length > 0) && turnaroundLiveOrder != null && !turnaroundLiveOrder.Terminal)
		{
			return turnaroundLiveOrder.Received ? "CANCEL_ENTRY" : "WAIT";
		}
		if (ExitReason.Length > 0)
		{
			if (turnaroundLiveOrder2 != null && !turnaroundLiveOrder2.Terminal)
			{
				return turnaroundLiveOrder2.Received ? "CANCEL_STOP" : "WAIT";
			}
			if (turnaroundLiveOrder3 != null && !turnaroundLiveOrder3.Terminal)
			{
				return "WAIT";
			}
			return (OwnQuantity > 0) ? "EXIT" : "WAIT";
		}
		if (OwnQuantity < 1)
		{
			return "WAIT";
		}
		if (turnaroundLiveOrder2 == null || turnaroundLiveOrder2.Terminal)
		{
			return "PROTECT";
		}
		if (!turnaroundLiveOrder2.Received)
		{
			return "WAIT";
		}
		return (turnaroundLiveOrder2.Quantity - turnaroundLiveOrder2.Filled != OwnQuantity || turnaroundLiveOrder2.Price < DesiredStop) ? "CHANGE_STOP" : "WAIT";
	}

	internal static bool Finite(double value)
	{
		return !double.IsNaN(value) && !double.IsInfinity(value);
	}

	internal static bool CompletedCloseDue(int model, int completed)
	{
		return completed >= ((model <= 2) ? 1 : 4);
	}

	internal static string Prefix(string identity)
	{
		using SHA256 sHA = SHA256.Create();
		return "TT_" + BitConverter.ToString(sHA.ComputeHash(Encoding.UTF8.GetBytes(identity)), 0, 4).Replace("-", "") + "_";
	}

	internal byte[] Encode()
	{
		byte[] array4;
		using (MemoryStream memoryStream = new MemoryStream())
		{
			using BinaryWriter binaryWriter = new BinaryWriter(memoryStream, Encoding.UTF8);
			binaryWriter.Write(20261015);
			binaryWriter.Write(Identity);
			binaryWriter.Write(Tag);
			binaryWriter.Write(Model);
			binaryWriter.Write(Requested);
			double[] array = new double[8] { BaseStop, DesiredStop, Entry, Risk, CycleCommission, ObservedCommission, ObservedQuantity, BookedCommission };
			foreach (double value in array)
			{
				binaryWriter.Write(value);
			}
			double[] array2 = new double[8] { MondayOpen, MondayHigh, MondayLow, MondayClose, FridayOpen, FridayHigh, FridayLow, FridayClose };
			foreach (double value2 in array2)
			{
				binaryWriter.Write(value2);
			}
			binaryWriter.Write(Held);
			binaryWriter.Write(FixedTime);
			binaryWriter.Write(BreakEven);
			binaryWriter.Write(CancelEntry);
			binaryWriter.Write(FixedEnabled);
			binaryWriter.Write(Blocked);
			binaryWriter.Write(CommissionBooked);
			DateTime[] array3 = new DateTime[6] { Monday, EntryTime, TrailTime, LastDaily, ConsumedMonday, RetryAt };
			foreach (DateTime dateTime in array3)
			{
				binaryWriter.Write(dateTime.ToBinary());
			}
			binaryWriter.Write(ExitReason);
			binaryWriter.Write(Orders.Count);
			foreach (TurnaroundLiveOrder order in Orders)
			{
				binaryWriter.Write(order.Name);
				binaryWriter.Write(order.Id);
				binaryWriter.Write(order.Role);
				binaryWriter.Write(order.Quantity);
				binaryWriter.Write(order.Filled);
				binaryWriter.Write(order.ExecutionQuantity);
				binaryWriter.Write(order.Average);
				binaryWriter.Write(order.Price);
				binaryWriter.Write(order.ExecutionCash);
				binaryWriter.Write(order.Received);
				binaryWriter.Write(order.Terminal);
				binaryWriter.Write(order.Rejected);
			}
			binaryWriter.Write(Executions.Count);
			foreach (string execution in Executions)
			{
				binaryWriter.Write(execution);
			}
			binaryWriter.Write(RetiredTags.Count);
			foreach (string retiredTag in RetiredTags)
			{
				binaryWriter.Write(retiredTag);
			}
			if (!string.IsNullOrEmpty(BrokerRestriction))
			{
				binaryWriter.Write("BrokerAccountRestriction.v1");
				binaryWriter.Write(BrokerRestriction);
			}
			binaryWriter.Flush();
			array4 = memoryStream.ToArray();
		}
		using SHA256 sHA = SHA256.Create();
		return array4.Concat(sHA.ComputeHash(array4)).ToArray();
	}

	internal static TurnaroundLiveLedger Decode(byte[] data, string identity)
	{
		try
		{
			if (data.Length < 36 || data.Length > 1048576)
			{
				throw new InvalidDataException("Checkpoint size");
			}
			int num = data.Length - 32;
			using (SHA256 sHA = SHA256.Create())
			{
				if (!sHA.ComputeHash(data, 0, num).SequenceEqual(data.Skip(num)))
				{
					throw new InvalidDataException("Checkpoint checksum");
				}
			}
			using BinaryReader binaryReader = new BinaryReader(new MemoryStream(data, 0, num), Encoding.UTF8);
			int num2 = binaryReader.ReadInt32();
			if ((num2 != 20261013 && num2 != 20261015) || binaryReader.ReadString() != identity)
			{
				throw new InvalidDataException("Checkpoint identity/version");
			}
			TurnaroundLiveLedger turnaroundLiveLedger = new TurnaroundLiveLedger(identity);
			turnaroundLiveLedger.Tag = binaryReader.ReadString();
			turnaroundLiveLedger.Model = binaryReader.ReadInt32();
			turnaroundLiveLedger.Requested = binaryReader.ReadInt32();
			turnaroundLiveLedger.BaseStop = binaryReader.ReadDouble();
			turnaroundLiveLedger.DesiredStop = binaryReader.ReadDouble();
			turnaroundLiveLedger.Entry = binaryReader.ReadDouble();
			turnaroundLiveLedger.Risk = binaryReader.ReadDouble();
			turnaroundLiveLedger.CycleCommission = binaryReader.ReadDouble();
			turnaroundLiveLedger.ObservedCommission = binaryReader.ReadDouble();
			turnaroundLiveLedger.ObservedQuantity = binaryReader.ReadDouble();
			turnaroundLiveLedger.BookedCommission = binaryReader.ReadDouble();
			turnaroundLiveLedger.MondayOpen = binaryReader.ReadDouble();
			turnaroundLiveLedger.MondayHigh = binaryReader.ReadDouble();
			turnaroundLiveLedger.MondayLow = binaryReader.ReadDouble();
			turnaroundLiveLedger.MondayClose = binaryReader.ReadDouble();
			turnaroundLiveLedger.FridayOpen = binaryReader.ReadDouble();
			turnaroundLiveLedger.FridayHigh = binaryReader.ReadDouble();
			turnaroundLiveLedger.FridayLow = binaryReader.ReadDouble();
			turnaroundLiveLedger.FridayClose = binaryReader.ReadDouble();
			turnaroundLiveLedger.Held = binaryReader.ReadInt32();
			turnaroundLiveLedger.FixedTime = binaryReader.ReadInt32();
			turnaroundLiveLedger.BreakEven = binaryReader.ReadBoolean();
			turnaroundLiveLedger.CancelEntry = binaryReader.ReadBoolean();
			turnaroundLiveLedger.FixedEnabled = binaryReader.ReadBoolean();
			turnaroundLiveLedger.Blocked = binaryReader.ReadBoolean();
			turnaroundLiveLedger.CommissionBooked = binaryReader.ReadBoolean();
			turnaroundLiveLedger.Monday = DateTime.FromBinary(binaryReader.ReadInt64());
			turnaroundLiveLedger.EntryTime = DateTime.FromBinary(binaryReader.ReadInt64());
			turnaroundLiveLedger.TrailTime = DateTime.FromBinary(binaryReader.ReadInt64());
			turnaroundLiveLedger.LastDaily = DateTime.FromBinary(binaryReader.ReadInt64());
			turnaroundLiveLedger.ConsumedMonday = DateTime.FromBinary(binaryReader.ReadInt64());
			turnaroundLiveLedger.RetryAt = DateTime.FromBinary(binaryReader.ReadInt64());
			turnaroundLiveLedger.ExitReason = binaryReader.ReadString();
			int num3 = binaryReader.ReadInt32();
			if (num3 < 0 || num3 > 128)
			{
				throw new InvalidDataException("Order count");
			}
			for (int i = 0; i < num3; i++)
			{
				TurnaroundLiveOrder turnaroundLiveOrder = new TurnaroundLiveOrder
				{
					Name = binaryReader.ReadString(),
					Id = binaryReader.ReadString(),
					Role = binaryReader.ReadChar(),
					Quantity = binaryReader.ReadInt32(),
					Filled = binaryReader.ReadInt32(),
					ExecutionQuantity = binaryReader.ReadInt32(),
					Average = binaryReader.ReadDouble(),
					Price = binaryReader.ReadDouble(),
					ExecutionCash = binaryReader.ReadDouble(),
					Received = binaryReader.ReadBoolean(),
					Terminal = binaryReader.ReadBoolean(),
					Rejected = binaryReader.ReadBoolean()
				};
				if (!turnaroundLiveOrder.Name.StartsWith(turnaroundLiveLedger.Tag + "_" + turnaroundLiveOrder.Role, StringComparison.Ordinal) || turnaroundLiveOrder.Quantity < 1 || turnaroundLiveOrder.Quantity > turnaroundLiveLedger.Requested || turnaroundLiveOrder.Filled < 0 || turnaroundLiveOrder.Filled > turnaroundLiveOrder.Quantity || (turnaroundLiveOrder.Role != 'E' && turnaroundLiveOrder.Role != 'S' && turnaroundLiveOrder.Role != 'X') || !Finite(turnaroundLiveOrder.Average) || !Finite(turnaroundLiveOrder.Price) || !Finite(turnaroundLiveOrder.ExecutionCash))
				{
					throw new InvalidDataException("Order record");
				}
				turnaroundLiveLedger.Orders.Add(turnaroundLiveOrder);
			}
			num3 = binaryReader.ReadInt32();
			if (num3 < 0 || num3 > 10000)
			{
				throw new InvalidDataException("Execution count");
			}
			for (int j = 0; j < num3; j++)
			{
				turnaroundLiveLedger.Executions.Add(binaryReader.ReadString());
			}
			if (num2 >= 20261015)
			{
				num3 = binaryReader.ReadInt32();
				if (num3 < 0 || num3 > 10000)
				{
					throw new InvalidDataException("Retired identity count");
				}
				for (int k = 0; k < num3; k++)
				{
					string text = binaryReader.ReadString();
					if (text.Length != 44 || !text.StartsWith(Prefix(identity), StringComparison.Ordinal) || text == turnaroundLiveLedger.Tag)
					{
						throw new InvalidDataException("Retired identity");
					}
					turnaroundLiveLedger.RetiredTags.Add(text);
				}
			}
			if (binaryReader.BaseStream.Position < num)
			{
				if (binaryReader.ReadString() != "BrokerAccountRestriction.v1") throw new InvalidDataException("Unknown checkpoint extension");
				turnaroundLiveLedger.BrokerRestriction = binaryReader.ReadString();
				if (string.IsNullOrEmpty(turnaroundLiveLedger.BrokerRestriction)) throw new InvalidDataException("Empty broker restriction");
			}
			if (binaryReader.BaseStream.Position != num || turnaroundLiveLedger.Model < 1 || turnaroundLiveLedger.Model > 4 || turnaroundLiveLedger.OwnQuantity < 0 || !new double[8] { turnaroundLiveLedger.BaseStop, turnaroundLiveLedger.DesiredStop, turnaroundLiveLedger.Entry, turnaroundLiveLedger.Risk, turnaroundLiveLedger.CycleCommission, turnaroundLiveLedger.ObservedCommission, turnaroundLiveLedger.ObservedQuantity, turnaroundLiveLedger.BookedCommission }.All(Finite) || !new double[8] { turnaroundLiveLedger.MondayOpen, turnaroundLiveLedger.MondayHigh, turnaroundLiveLedger.MondayLow, turnaroundLiveLedger.MondayClose, turnaroundLiveLedger.FridayOpen, turnaroundLiveLedger.FridayHigh, turnaroundLiveLedger.FridayLow, turnaroundLiveLedger.FridayClose }.All(Finite) || turnaroundLiveLedger.Held < 0 || (turnaroundLiveLedger.Tag.Length > 0 && (turnaroundLiveLedger.Tag.Length != 44 || !turnaroundLiveLedger.Tag.StartsWith(Prefix(identity), StringComparison.Ordinal) || turnaroundLiveLedger.Requested < 1 || turnaroundLiveLedger.BaseStop <= 0.0 || turnaroundLiveLedger.DesiredStop < turnaroundLiveLedger.BaseStop)))
			{
				throw new InvalidDataException("Checkpoint values");
			}
			return turnaroundLiveLedger;
		}
		catch (InvalidDataException)
		{
			throw;
		}
		catch (Exception innerException)
		{
			throw new InvalidDataException("Invalid checkpoint", innerException);
		}
	}

	internal void Commit(string path)
	{
		byte[] array = Encode();
		string text = Convert.ToBase64String(array.Skip(array.Length - 32).ToArray());
		if (!(text == committedHash) || !File.Exists(path))
		{
			using (FileStream fileStream = new FileStream(path + ".tmp", FileMode.Create, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
			{
				fileStream.Write(array, 0, array.Length);
				fileStream.Flush(flushToDisk: true);
			}
			if (File.Exists(path))
			{
				File.Replace(path + ".tmp", path, path + ".bak");
			}
			else
			{
				File.Move(path + ".tmp", path);
			}
			committedHash = text;
		}
	}

	internal static FileStream Lease(string path)
	{
		return new FileStream(path, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
	}
}

internal sealed class TurnaroundLiveOrder
{
	internal string Name;

	internal string Id = "";

	internal char Role;

	internal int Quantity;

	internal int Filled;

	internal int ExecutionQuantity;

	internal double Average;

	internal double Price;

	internal double ExecutionCash;

	internal bool Received;

	internal bool Terminal;

	internal bool Rejected;
}

public enum TurnaroundModel
{
	T1,
	T2,
	T3,
	T4
}

internal sealed class TurnaroundNewsCalendar : IDisposable
{
	private const string FeedUrl = "https://nfs.faireconomy.media/ff_calendar_thisweek.json";

	private static readonly TimeSpan MaxCacheAge = TimeSpan.FromHours(2.0);

	private static readonly TimeZoneInfo NewsZone = TimeZoneInfo.FindSystemTimeZoneById("Eastern Standard Time");

	private static readonly HttpClient Http = new HttpClient();

	private readonly string cachePath;

	private readonly bool localOnly;

	private volatile TurnaroundNewsEvent[] events = new TurnaroundNewsEvent[0];

	private volatile string provider = "ForexFactory loading";

	private int fetching;

	private DateTime lastAttemptUtc = DateTime.MinValue;

	private DateTime loadedAtUtc = DateTime.MinValue;

	internal TurnaroundNewsEvent[] Events => events;

	internal string Provider => provider;

	internal bool IsAvailable => events.Length != 0;

	internal TurnaroundNewsCalendar(string cache, string historicalCsv, bool analyzer)
	{
		cachePath = cache;
		if (!string.IsNullOrWhiteSpace(historicalCsv) && File.Exists(historicalCsv))
		{
			LoadCsv(historicalCsv);
			localOnly = true;
			provider = "Historical CSV";
		}
		else if (analyzer)
		{
			localOnly = true;
			provider = "Unavailable (historical CSV required)";
		}
		else
		{
			LoadCache();
			BeginFetch();
		}
	}

	internal bool HasCoverage(DateTime utcNow)
	{
		if (!localOnly && (loadedAtUtc == DateTime.MinValue || utcNow - loadedAtUtc > MaxCacheAge))
		{
			provider = "Stale ForexFactory data; fail closed";
			return false;
		}
		DateTime date = TimeZoneInfo.ConvertTimeFromUtc(utcNow, NewsZone).Date;
		DateTime dateTime = date.AddDays(0 - date.DayOfWeek);
		TurnaroundNewsEvent[] array = events;
		for (int i = 0; i < array.Length; i++)
		{
			DateTime date2 = TimeZoneInfo.ConvertTimeFromUtc(array[i].Utc, NewsZone).Date;
			if (date2 >= dateTime && date2 < dateTime.AddDays(7.0))
			{
				return true;
			}
		}
		return false;
	}

	internal void Refresh()
	{
		if (!localOnly && (DateTime.UtcNow - lastAttemptUtc).TotalMinutes >= 30.0)
		{
			BeginFetch();
		}
	}

	private void LoadCache()
	{
		try
		{
			if (!File.Exists(cachePath))
			{
				return;
			}
			DateTime lastWriteTimeUtc = File.GetLastWriteTimeUtc(cachePath);
			if (DateTime.UtcNow - lastWriteTimeUtc > MaxCacheAge)
			{
				provider = "Stale ForexFactory cache; fail closed";
				return;
			}
			events = ParseJson(File.ReadAllText(cachePath));
			loadedAtUtc = lastWriteTimeUtc;
			if (events.Length != 0)
			{
				provider = "ForexFactory cache";
			}
		}
		catch
		{
		}
	}

	private void BeginFetch()
	{
		if (Interlocked.CompareExchange(ref fetching, 1, 0) != 0)
		{
			return;
		}
		Task.Run(() =>
		{
			try
			{
				string result = Http.GetStringAsync("https://nfs.faireconomy.media/ff_calendar_thisweek.json").GetAwaiter().GetResult();
				TurnaroundNewsEvent[] array = ParseJson(result);
				if (array.Length != 0)
				{
					events = array;
					loadedAtUtc = DateTime.UtcNow;
					provider = "ForexFactory live";
					try
					{
						string directoryName = Path.GetDirectoryName(cachePath);
						if (!string.IsNullOrEmpty(directoryName))
						{
							Directory.CreateDirectory(directoryName);
						}
						File.WriteAllText(cachePath, result);
						return;
					}
					catch
					{
						return;
					}
				}
			}
			catch
			{
				provider = ((events.Length != 0) ? "ForexFactory cache" : "Unavailable (ForexFactory)");
			}
			finally
			{
				lastAttemptUtc = DateTime.UtcNow;
				fetching = 0;
			}
		});
	}

	private static TurnaroundNewsEvent[] ParseJson(string json)
	{
		List<TurnaroundNewsEvent> list = new List<TurnaroundNewsEvent>();
		try
		{
			foreach (Dictionary<string, string> item in ParseFlatArray(json))
			{
				if (item.TryGetValue("date", out var value) && DateTime.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.AdjustToUniversal | DateTimeStyles.RoundtripKind, out var result))
				{
					TurnaroundNewsEvent turnaroundNewsEvent = new TurnaroundNewsEvent
					{
						Utc = result
					};
					item.TryGetValue("country", out turnaroundNewsEvent.Currency);
					item.TryGetValue("impact", out turnaroundNewsEvent.Impact);
					item.TryGetValue("title", out turnaroundNewsEvent.Title);
					turnaroundNewsEvent.Currency = turnaroundNewsEvent.Currency ?? "";
					turnaroundNewsEvent.Impact = turnaroundNewsEvent.Impact ?? "";
					turnaroundNewsEvent.Title = turnaroundNewsEvent.Title ?? "";
					list.Add(turnaroundNewsEvent);
				}
			}
		}
		catch
		{
		}
		return list.ToArray();
	}

	private static List<Dictionary<string, string>> ParseFlatArray(string json)
	{
		List<Dictionary<string, string>> list = new List<Dictionary<string, string>>();
		int num = 0;
		while (num < json.Length)
		{
			int num2 = json.IndexOf('{', num);
			if (num2 < 0)
			{
				break;
			}
			int num3 = 0;
			int i;
			for (i = num2; i < json.Length; i++)
			{
				if (json[i] == '{')
				{
					num3++;
				}
				else if (json[i] == '}' && --num3 == 0)
				{
					break;
				}
			}
			if (num3 != 0)
			{
				break;
			}
			list.Add(ParseObject(json.Substring(num2, i - num2 + 1)));
			num = i + 1;
		}
		return list;
	}

	private static Dictionary<string, string> ParseObject(string text)
	{
		Dictionary<string, string> dictionary = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
		int num = 1;
		while (num < text.Length)
		{
			int num2 = text.IndexOf('"', num);
			int num3 = ((num2 < 0) ? (-1) : text.IndexOf('"', num2 + 1));
			if (num3 < 0)
			{
				break;
			}
			int num4 = text.IndexOf(':', num3 + 1);
			int num5 = ((num4 < 0) ? (-1) : text.IndexOf('"', num4 + 1));
			if (num5 < 0)
			{
				break;
			}
			StringBuilder stringBuilder = new StringBuilder();
			int num6 = num5 + 1;
			while (num6 < text.Length && text[num6] != '"')
			{
				if (text[num6] == '\\' && num6 + 1 < text.Length)
				{
					num6++;
				}
				stringBuilder.Append(text[num6++]);
			}
			dictionary[text.Substring(num2 + 1, num3 - num2 - 1)] = stringBuilder.ToString();
			num = num6 + 1;
		}
		return dictionary;
	}

	private void LoadCsv(string path)
	{
		List<TurnaroundNewsEvent> list = new List<TurnaroundNewsEvent>();
		string[] array = File.ReadAllLines(path);
		foreach (string text in array)
		{
			if (!string.IsNullOrWhiteSpace(text) && !text.StartsWith("date", StringComparison.OrdinalIgnoreCase))
			{
				string[] array2 = text.Split(',');
				if (array2.Length >= 5 && DateTime.TryParse(array2[0] + " " + array2[1], CultureInfo.InvariantCulture, DateTimeStyles.AdjustToUniversal | DateTimeStyles.AssumeUniversal, out var result))
				{
					list.Add(new TurnaroundNewsEvent
					{
						Utc = result,
						Currency = array2[2].Trim(),
						Impact = array2[3].Trim(),
						Title = string.Join(",", array2, 4, array2.Length - 4).Trim()
					});
				}
			}
		}
		events = list.ToArray();
	}

	public void Dispose()
	{
	}
}

internal sealed class TurnaroundNewsEvent
{
	internal DateTime Utc;

	internal string Currency = "";

	internal string Impact = "";

	internal string Title = "";
}

public enum TurnaroundNewsMode
{
	Off,
	HighOnly,
	HighMedium,
	All
}

public enum TurnaroundNewsWindow
{
	Five = 5,
	Ten = 10,
	Fourteen = 14,
	Twenty = 20
}

public enum TurnaroundRiskMode
{
	FixedOneContract,
	RiskBudget
}
}
