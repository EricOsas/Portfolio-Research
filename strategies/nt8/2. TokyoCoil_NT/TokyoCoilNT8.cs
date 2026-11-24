//+------------------------------------------------------------------+
//|                                                TokyoCoilNT8.cs  |
//| Asian Session Volatility Compression & Breakout Strategy         |
//| Developed by Osamwonyi Eric (You_FoundEric)                      |
//| Copyright 2026-2027, Osamwonyi Eric (@You_FoundEric)             |
//+------------------------------------------------------------------+

using NinjaTrader.Cbi;
using NinjaTrader.Core;
using NinjaTrader.Data;
using NinjaTrader.Gui.Chart;
using NinjaTrader.Gui;
using NinjaTrader.NinjaScript.DrawingTools;
using NinjaTrader.NinjaScript.Strategies.TokyoCoil_NT;
using SharpDX.Direct2D1;
using SharpDX.DirectWrite;
using SharpDX;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel;
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
using System.Windows;
using System.Xml.Serialization;
using System;

namespace NinjaTrader.NinjaScript.Strategies
{
using Brush = System.Windows.Media.Brush;
using SolidColorBrush = System.Windows.Media.SolidColorBrush;
using Color = System.Windows.Media.Color;
using Point = System.Windows.Point;
using Rectangle = NinjaTrader.NinjaScript.DrawingTools.Rectangle;
public class TokyoCoilNT8 : Strategy
{
	private CoilModel model;

	private CoilNews news;

	private readonly CoilDashboard dashboard = new CoilDashboard();

	private ChartControl dashboardChart;

	private bool dashboardMouseHooked;

	private bool dashboardFaultLogged;

	private TimeZoneInfo platformZone;

	private string owner;

	private string buySignal;

	private string sellSignal;

	private string status;

	private string ledgerPath;

	private Order buyOrder;

	private Order sellOrder;

	private readonly Dictionary<string, Order> ownedOrders = new Dictionary<string, Order>();

	private readonly Dictionary<string, CoilTrade> entryPlans = new Dictionary<string, CoilTrade>();

	private readonly Dictionary<string, int> processedFills = new Dictionary<string, int>();

	private int stopSequence;

	private string flattenReason;

	private int ownedNet;

	private bool emergency;

	private bool drivingEmergency;

	private Timer clockTimer;

	private CoilTrade active;

	private CoilTrade shadow;

	private readonly HashSet<string> executions = new HashSet<string>();

	private StreamWriter audit;

	private double balance;

	private DateTime activation;

	private DateTime lastTick;

	private DateTime latestNy;

	private bool firstRealtime;

	private bool suspended;

	private bool flattening;

	private bool reconnectPending;

	private int pendingStopQuantity;

	private bool forex;

	private CoilJournal journal;

	private FileStream ownershipLock;

	private string journalPath;

	private string reportedRecoveryCase;

	private bool recovering;

	private bool recoveryBlocked;

	private bool recoveryHooked;

	private bool recoveryDriving;

	private bool fillHydrationPending;

	private readonly Dictionary<string, Order> recoveryOrders = new Dictionary<string, Order>();

	private readonly object drawingGate = new object();

	private readonly Dictionary<string, Action> drawingUpdates = new Dictionary<string, Action>();

	private bool drawingQueued;

	private static readonly Brush EntryInk = Ink(214, 218, 224);

	private static readonly Brush StopInk = Ink(55, 57, 68);

	private static readonly Brush ProfitInk = Ink(22, 55, 120);

	private static readonly Brush RangeInk = Ink(25, 35, 45);

	private string legacyBrokerCloseConfirmation = string.Empty;

	[NinjaScriptProperty]
	[Display(Name = "Enable new trades", GroupName = "0. Trading", Order = 0)]
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
	[Range(0.01, 100.0)]
	[Display(Name = "Risk (%)", GroupName = "1. Risk", Order = 0)]
	public double RiskPercent { get; set; }

	[NinjaScriptProperty]
	[Range(0.0, double.MaxValue)]
	[Display(Name = "Fixed risk ($, 0 uses %)", GroupName = "1. Risk", Order = 1)]
	public double RiskMoney { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "20-trade equity brake", GroupName = "1. Risk", Order = 2)]
	public bool EquityBrake { get; set; }

	[NinjaScriptProperty]
	[Range(1.0, double.MaxValue)]
	[Display(Name = "Analyzer starting capital", GroupName = "1. Risk", Order = 3)]
	public double AnalyzerCapital { get; set; }

	[NinjaScriptProperty]
	[Range(1, 10000)]
	[Display(Name = "Maximum futures contracts", GroupName = "1. Risk", Order = 4)]
	public int MaxContracts { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "Enforce risk budget", Description = "ON: skip if minimum quantity exceeds the applied risk budget. OFF: use minimum quantity in that case; planned risk may exceed the budget.", GroupName = "1. Risk", Order = 5)]
	public bool EnforceRiskBudget { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "Enable news flatten", GroupName = "2. News", Order = 0)]
	public bool NewsFlatten { get; set; }

	[NinjaScriptProperty]
	[Range(0, 720)]
	[Display(Name = "Minutes before release", GroupName = "2. News", Order = 1)]
	public int NewsLeadMinutes { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "Historical NY calendar filename", GroupName = "2. News", Order = 2)]
	public string CalendarFile { get; set; }

	[NinjaScriptProperty]
	[Range(0, 100)]
	[Display(Name = "Historical Forex spread (ticks)", GroupName = "3. Execution", Order = 0)]
	public int HistoricalSpreadTicks { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "Write audit", GroupName = "3. Execution", Order = 1)]
	public bool WriteAudit { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "Show panel", GroupName = "4. Display", Order = 0)]
	public bool ShowPanel { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "Show historical and live objects", GroupName = "4. Display", Order = 1)]
	public bool ShowVisuals { get; set; }

	private static string StrategyRoot([CallerFilePath] string source = "")
	{
		return Path.GetDirectoryName(source);
	}

	private static Brush Ink(byte r, byte g, byte b)
	{
		SolidColorBrush solidColorBrush = new SolidColorBrush(Color.FromRgb(r, g, b));
		solidColorBrush.Freeze();
		return solidColorBrush;
	}

	protected override void OnStateChange()
	{
		if (State == State.SetDefaults)
		{
			Name = "TokyoCoil";
			Description = "TokyoCoil - Asian session volatility compression and breakout strategy. Detects a qualifying Tokyo coil, arms both range boundaries, manages protective and trailing stops, and supports equity-brake sizing and news flattening. Copyright 2026-2027, Osamwonyi Eric (@You_FoundEric). Developed by @You_FoundEric. Unauthorized redistribution prohibited.";
			EnableNewTrades = true;
			BrokerCloseConfirmation = string.Empty;
			Calculate = Calculate.OnEachTick;
			StartBehavior = StartBehavior.ImmediatelySubmit;
			ConnectionLossHandling = ConnectionLossHandling.KeepRunning;
			IsAdoptAccountPositionAware = false;
			IsExitOnSessionCloseStrategy = false;
			IsUnmanaged = true;
			EntriesPerDirection = 1;
			EntryHandling = EntryHandling.UniqueEntries;
			StopTargetHandling = StopTargetHandling.PerEntryExecution;
			RealtimeErrorHandling = RealtimeErrorHandling.IgnoreAllErrors;
			BarsRequiredToTrade = 0;
			IncludeCommission = true;
			MaximumBarsLookBack = MaximumBarsLookBack.Infinite;
			OrderFillResolution = OrderFillResolution.Standard;
			IsFillLimitOnTouch = true;
			Slippage = 1.0;
			TimeInForce = TimeInForce.Gtc;
			IsOverlay = true;
			DrawOnPricePanel = true;
			IsInstantiatedOnEachOptimizationIteration = true;
			RiskPercent = 1.0;
			RiskMoney = 500.0;
			EquityBrake = true;
			AnalyzerCapital = 100000.0;
			MaxContracts = 1;
			HistoricalSpreadTicks = 1;
			EnforceRiskBudget = true;
			NewsFlatten = false;
			NewsLeadMinutes = 5;
			CalendarFile = "asiancoil_usd_events.csv";
			bool showPanel = (ShowVisuals = true);
			ShowPanel = showPanel;
			WriteAudit = false;
		}
		else if (State == State.Configure)
		{
			if (StartBehavior != StartBehavior.ImmediatelySubmit)
			{
				throw new InvalidOperationException("TokyoCoil requires ImmediatelySubmit.");
			}
			AddDataSeries(BarsPeriodType.Minute, 1);
			AddDataSeries(BarsPeriodType.Tick, 1);
			OrderFillResolution = OrderFillResolution.Standard;
		}
		else if (State == State.DataLoaded)
		{
			string text = Instrument.MasterInstrument.Name.Replace("$", "").ToUpperInvariant();
			forex = text == "USDJPY";
			if (!forex && text != "6J")
			{
				throw new InvalidOperationException("This port supports USDJPY and 6J only; other assets require a separate data contract.");
			}
			model = new CoilModel
			{
				Inverse = !forex
			};
			news = new CoilNews();
			platformZone = Globals.GeneralOptions.TimeZoneInfo;
			owner = "TC" + Guid.NewGuid().ToString("N");
			status = "Warming up";
			balance = AnalyzerCapital;
			string text2 = StrategyRoot("C:\\Users\\Administrator\\Documents\\NinjaTrader 8\\bin\\Custom\\Strategies\\3. TokyoCoil_NT\\TokyoCoilNT8.cs");
			Directory.CreateDirectory(text2);
			if (Path.GetFileName(CalendarFile) != CalendarFile)
			{
				throw new InvalidOperationException("Calendar must be a filename inside the strategy root.");
			}
			if (NewsFlatten && IsInStrategyAnalyzer)
			{
				news.Load(Path.Combine(text2, CalendarFile));
			}
			if (WriteAudit)
			{
				Directory.CreateDirectory(text2);
				audit = new StreamWriter(Path.Combine(text2, owner + ".csv"));
				audit.AutoFlush = true;
				audit.WriteLine("event,ny_time,session,direction,entry,stop,exit,quantity,R,detail,entry_ny_time,fees,balance");
			}
		}
		else if (State == State.Transition)
		{
			if (active != null)
			{
				throw new InvalidOperationException("Historical exposure must be flat before realtime.");
			}
			shadow = null;
		}
		else if (State == State.Realtime)
		{
			InitializeRecovery();
			if (buyOrder != null)
			{
				buyOrder = GetRealtimeOrder(buyOrder);
			}
			if (sellOrder != null)
			{
				sellOrder = GetRealtimeOrder(sellOrder);
			}
			string[] array = ownedOrders.Keys.ToArray();
			foreach (string key in array)
			{
				ownedOrders[key] = GetRealtimeOrder(ownedOrders[key]);
			}
			activation = CoilModel.Platform(SessionClockNy(), platformZone);
			firstRealtime = true;
			model.ClosedR.Clear();
			string text3 = ((Account == null) ? "unknown" : Account.Name) + "_" + Instrument.FullName;
			char[] invalidFileNameChars = Path.GetInvalidFileNameChars();
			foreach (char oldChar in invalidFileNameChars)
			{
				text3 = text3.Replace(oldChar, '_');
			}
			ledgerPath = Path.Combine(Globals.UserDataDir, "TokyoCoil", text3 + ".risk.csv");
			string text4 = Account.Name + "_" + Instrument.MasterInstrument.Name;
			char[] invalidFileNameChars2 = Path.GetInvalidFileNameChars();
			foreach (char oldChar2 in invalidFileNameChars2)
			{
				text4 = text4.Replace(oldChar2, '_');
			}
			string path = Path.Combine(Globals.UserDataDir, "TokyoCoil", text4 + ".risk.csv");
			if (!File.Exists(ledgerPath) && File.Exists(path))
			{
				CoilJournal.Atomic(ledgerPath, File.ReadAllText(path));
			}
			if (journal != null && journal.HasFinalR)
			{
				RecordRisk(journal.Cycle, journal.FinalR);
			}
			if (EquityBrake && File.Exists(ledgerPath))
			{
				string[] array2 = File.ReadAllLines(ledgerPath);
				foreach (string text5 in array2)
				{
					string[] array3 = text5.Split('|');
					double num = double.Parse(array3[array3.Length - 1], CultureInfo.InvariantCulture);
					if (double.IsNaN(num) || double.IsInfinity(num))
					{
						throw new InvalidDataException("Invalid risk ledger.");
					}
					model.ClosedR.Add(num);
				}
			}
			if (NewsFlatten)
			{
				news.Refresh();
			}
			clockTimer = new Timer((object o) =>
			{
				if (State != State.Realtime)
				{
					return;
				}
				try
				{
					TriggerCustomEvent((object ignored) =>
					{
						if (State == State.Realtime)
						{
							DateTime ny = SessionClockNy();
							if (!BrokerReady())
							{
								reconnectPending = true;
								Paint(ny);
							}
							else
							{
								CheckRecoveryEvidence(poll: true);
								if (recovering || recoveryBlocked)
								{
									DriveRecovery(ny);
									Paint(ny);
								}
								else
								{
									if (reconnectPending)
									{
										reconnectPending = false;
										firstRealtime = true;
									}
									HandleDeadline(ny);
									Paint(ny);
									if (ChartControl != null)
									{
										ChartControl.Dispatcher.InvokeAsync(() =>
										{
											ChartControl.InvalidateVisual();
										});
									}
								}
							}
						}
					}, null);
				}
				catch (InvalidOperationException)
				{
				}
			}, null, 1000, 1000);
		}
		else
		{
			if (State != State.Terminated)
			{
				return;
			}
			if (clockTimer != null)
			{
				clockTimer.Dispose();
				clockTimer = null;
			}
			HookDashboardMouse(attach: false);
			if (audit != null)
			{
				audit.Dispose();
				audit = null;
			}
			if (recoveryHooked && Account != null)
			{
				Account.OrderUpdate -= RecoveryOrder;
				Account.ExecutionUpdate -= RecoveryExecution;
				recoveryHooked = false;
			}
			try
			{
				if (journal != null && ownershipLock != null && journalPath != null)
				{
					journal.Save(journalPath);
				}
			}
			catch (Exception ex)
			{
				Print("TokyoCoil journal shutdown error: " + ex.Message);
			}
			finally
			{
				if (ownershipLock != null)
				{
					ownershipLock.Dispose();
					ownershipLock = null;
				}
			}
		}
	}

	protected override void OnBarUpdate()
	{
		if (model == null)
		{
			return;
		}
		if (BarsInProgress == 1)
		{
			if (CurrentBars[1] < 1)
			{
				return;
			}
			int barsAgo = ((State == State.Realtime) ? 1 : 0);
			if (State == State.Realtime && !IsFirstTickOfBar)
			{
				return;
			}
			DateTime dateTime = CoilModel.NY(Times[1][barsAgo], platformZone).AddMinutes(-1.0);
			model.Minute(dateTime, Highs[1][barsAgo], Lows[1][barsAgo]);
			{
				foreach (CoilTrade trade in model.Trades)
				{
					if (trade.Scheduled && !trade.ReferenceReady && dateTime == trade.Reference)
					{
						trade.Close = Closes[1][barsAgo];
						trade.ReferenceReady = true;
					}
				}
				return;
			}
		}
		if (BarsInProgress != 2 || CurrentBars[2] < 0)
		{
			return;
		}
		DateTime dateTime2 = Times[2][0];
		DateTime dateTime3 = (latestNy = CoilModel.NY(dateTime2, platformZone));
		double num = Closes[2][0];
		double num2 = (forex ? ((double)HistoricalSpreadTicks * TickSize) : 0.0);
		double num3 = num;
		double num4 = num + num2;
		if (State == State.Realtime)
		{
			CheckRecoveryEvidence(poll: true);
			if (recovering || recoveryBlocked)
			{
				DriveRecovery(SessionClockNy());
				Paint(SessionClockNy());
				return;
			}
			DateTime dateTime4 = CoilModel.Session(dateTime3);
			if (dateTime4 != model.Day)
			{
				CancelEntries();
				model.Reset(dateTime4);
			}
			if (!BrokerReady())
			{
				reconnectPending = true;
				model.ResumeAfterGap(dateTime3);
				status = "Account disconnected";
				Paint(SessionClockNy());
				return;
			}
			if (reconnectPending)
			{
				reconnectPending = false;
				firstRealtime = true;
			}
			num3 = GetCurrentBid();
			num4 = GetCurrentAsk();
			if (num3 <= 0.0 || num4 < num3)
			{
				status = "Waiting for quotes";
				return;
			}
			if (NewsFlatten)
			{
				news.Refresh();
			}
			HandleDeadline(dateTime3);
			if (dateTime2 <= activation)
			{
				return;
			}
			if (firstRealtime || (lastTick != DateTime.MinValue && dateTime2 - lastTick > TimeSpan.FromSeconds(120.0)))
			{
				if (Working(buyOrder) || Working(sellOrder))
				{
					firstRealtime = false;
					lastTick = dateTime2;
					DriveClose();
					Paint(dateTime3);
					return;
				}
				bool flag = lastTick == DateTime.MinValue || dateTime2 - lastTick > TimeSpan.FromSeconds(120.0);
				CancelEntries();
				if (flag || model.Consumed || (model.Pending && (num4 >= model.Buy || num3 <= model.Sell)))
				{
					model.ResumeAfterGap(dateTime3);
					status = (model.Consumed ? "Stale session consumed" : "Waiting for tonight's range");
				}
				firstRealtime = false;
				lastTick = dateTime2;
				Paint(dateTime3);
				return;
			}
		}
		lastTick = dateTime2;
		ClearSettledEntries();
		DateTime dateTime5 = CoilModel.Session(dateTime3);
		if (dateTime5 != model.Day)
		{
			CancelEntries();
			model.Reset(dateTime5);
		}
		bool flag2 = dateTime3 >= dateTime5.AddDays(1.0).AddHours(3.0) && dateTime3 < dateTime5.AddDays(1.0).AddHours(17.0);
		if (flag2)
		{
			model.Pending = false;
			CancelEntries();
		}
		DateTime dateTime6 = (NewsFlatten ? news.Event(dateTime5.AddDays(1.0), State == State.Realtime) : DateTime.MinValue);
		DateTime dateTime7 = dateTime5.AddDays(1.0).AddHours(12.0);
		if (dateTime6 != DateTime.MinValue)
		{
			dateTime7 = Min(dateTime7, dateTime6.AddMinutes(-NewsLeadMinutes));
		}
		bool flag3 = !NewsFlatten || news.Ready(dateTime3, State == State.Realtime);
		if (!flag3)
		{
			CancelEntries();
			model.Pending = false;
			status = "News unavailable: entries blocked";
			if (active != null)
			{
				Flatten("NewsUnavailable");
			}
		}
		if (active != null && dateTime3 >= dateTime7)
		{
			Flatten((dateTime6 != DateTime.MinValue && dateTime7 < dateTime5.AddDays(1.0).AddHours(12.0)) ? "News" : "Time");
		}
		DriveClose();
		if (shadow != null)
		{
			bool flag4 = ((shadow.Direction > 0) ? (num3 <= shadow.Stop) : (num4 >= shadow.Stop));
			if (flag4 || dateTime3 >= dateTime7)
			{
				shadow.Exit = dateTime3;
				shadow.Close = (shadow.ActualClose = ((shadow.Direction > 0) ? num3 : num4));
				shadow.Scheduled = !flag4 && dateTime7 == dateTime5.AddDays(1.0).AddHours(12.0);
				shadow.Reference = dateTime5.AddDays(1.0).AddHours(12.0);
				model.ClosedR.Add((double)shadow.Direction * (shadow.Close - shadow.Entry) / Math.Abs(shadow.Entry - shadow.Stop));
				shadow = null;
			}
		}
		bool flag5 = flag3 && !suspended && active == null && shadow == null && model.Arm(dateTime3, num4 - num3, TickSize);
		if (flag5)
		{
			Log("ARM", dateTime3, new CoilTrade
			{
				Day = dateTime5,
				Entry = model.Buy,
				Stop = model.Low
			}, 0.0, "sell=" + model.Sell.ToString("R", CultureInfo.InvariantCulture) + ";high=" + model.High.ToString("R", CultureInfo.InvariantCulture));
		}
		int num5 = model.Touch(num3, num4, flag5);
		bool flag6 = IsInStrategyAnalyzer || State == State.Realtime;
		if (num5 != 0 && !flag6)
		{
			shadow = new CoilTrade
			{
				Day = dateTime5,
				Fill = dateTime3,
				Direction = num5,
				Entry = ((num5 > 0) ? num4 : num3),
				Stop = ((num5 > 0) ? model.Low : model.High),
				Synthetic = true
			};
			model.Trades.Add(shadow);
		}
		if (((flag6 && !suspended) & flag3) && active == null && !flag2)
		{
			if (flag5 && num5 != 0)
			{
				Submit(num5, market: true);
			}
			else if (model.Pending && buyOrder == null && sellOrder == null)
			{
				Submit(1, market: false);
				if (active == null && !model.Consumed)
				{
					Submit(-1, market: false);
				}
			}
		}
		Paint(dateTime3);
	}

	private static DateTime Min(DateTime a, DateTime b)
	{
		return (a < b) ? a : b;
	}

	private void InitializeRecovery()
	{
		if (Account == null)
		{
			recoveryBlocked = true;
			status = "Recovery blocked: account unavailable";
			return;
		}
		string s = Account.Name + "\n" + Instrument.FullName;
		string text;
		using (SHA256 sHA = SHA256.Create())
		{
			text = BitConverter.ToString(sHA.ComputeHash(Encoding.UTF8.GetBytes(s))).Replace("-", "");
		}
		string text2 = Path.Combine(Globals.UserDataDir, "TokyoCoil", "ownership");
		Directory.CreateDirectory(text2);
		journalPath = Path.Combine(text2, text + ".json");
		try
		{
			ownershipLock = new FileStream(Path.Combine(text2, text + ".lock"), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
			if (File.Exists(journalPath))
			{
				journal = CoilJournal.Load(journalPath, Account.Name, Instrument.FullName);
				owner = journal.Owner;
				recovering = journal.Orders.Count > 0;
			}
			else
			{
				lock (Account.Orders)
				{
					if (Account.Orders.Any((Order o) => Working(o) && o.Instrument.FullName == Instrument.FullName && CoilJournal.TokyoOrderName(o.Name)))
					{
						throw new InvalidDataException("Pre-upgrade TokyoCoil orders have no ownership journal; migration required.");
					}
				}
				journal = new CoilJournal
				{
					Account = Account.Name,
					Instrument = Instrument.FullName,
					Owner = owner,
					Closed = true
				};
				journal.Save(journalPath);
			}
			Account.OrderUpdate += RecoveryOrder;
			Account.ExecutionUpdate += RecoveryExecution;
			recoveryHooked = true;
			if (journal.Closed && journal.Day == CoilModel.Session(SessionClockNy()))
			{
				model.Reset(journal.Day);
				model.Decided = (model.Consumed = true);
				model.Pending = false;
			}
		}
		catch (Exception ex)
		{
			recoveryBlocked = true;
			suspended = true;
			status = "Recovery blocked: " + ex.Message;
			Print("TokyoCoil " + status);
		}
	}

	private void RecordRisk(string cycle, double r)
	{
		if (!string.IsNullOrEmpty(ledgerPath) && !string.IsNullOrEmpty(cycle))
		{
			string[] array = (File.Exists(ledgerPath) ? File.ReadAllLines(ledgerPath) : new string[0]);
			if (!array.Any((string s) => s.StartsWith(cycle + "|", StringComparison.Ordinal)))
			{
				CoilJournal.Atomic(ledgerPath, string.Join(Environment.NewLine, array.Concat(new string[1] { cycle + "|" + r.ToString("R", CultureInfo.InvariantCulture) })) + Environment.NewLine);
			}
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

	private void SubmitOwned(int series, OrderAction action, OrderType type, int qty, double limit, double stop, string oco, string signal)
	{
		if (BrokerRestrictionPaused()) return;
		CheckRecoveryEvidence();
		if (!BrokerReady() || recovering || recoveryBlocked || fillHydrationPending)
		{
			return;
		}
		if (State == State.Realtime)
		{
			if (journal == null || ownershipLock == null)
			{
				recoveryBlocked = true;
				status = "Recovery blocked: ownership unavailable";
				return;
			}
			if (entryPlans.ContainsKey(signal) && !journal.Closed && journal.Net() == 0 && journal.Orders.All((CoilJournalOrder o) => CoilJournal.Terminal(o.State)))
			{
				journal.Closed = true;
			}
			if (entryPlans.TryGetValue(signal, out var value) && journal.Closed)
			{
				journal.Orders.Clear();
				journal.Closed = false;
				journal.HasFinalR = false;
				journal.Day = value.Day;
				journal.Stop = value.Stop;
				journal.Cycle = Guid.NewGuid().ToString("N");
				journal.Direction = value.Direction;
				journal.Fill = DateTime.MinValue;
			}
			if (!entryPlans.ContainsKey(signal))
			{
				signal = signal + "_" + journal.Cycle;
			}
			if (journal.Orders.Any((CoilJournalOrder o) => o.Name == signal))
			{
				recoveryBlocked = true;
				status = "Recovery blocked: duplicate order intent";
				return;
			}
			double originalStop = (entryPlans.TryGetValue(signal, out var value2) ? value2.Stop : 0.0);
			journal.Orders.Add(new CoilJournalOrder
			{
				Name = signal,
				Action = action.ToString(),
				Type = type.ToString(),
				Quantity = qty,
				Stop = stop,
				OriginalStop = originalStop,
				State = "Intent"
			});
			journal.Save(journalPath);
		}
		SubmitOrderUnmanaged(series, action, type, qty, limit, stop, oco, signal);
	}

	private void JournalOrder(Order order)
	{
		if (State == State.Realtime && journal != null && !recovering && !recoveryBlocked)
		{
			CoilJournalOrder coilJournalOrder = journal.Orders.FirstOrDefault((CoilJournalOrder o) => o.Name == order.Name);
			if (coilJournalOrder == null)
			{
				recoveryBlocked = true;
				status = "Recovery blocked: unknown owned order";
			}
			else if (!UpdateJournalOrder(coilJournalOrder, order))
			{
				recovering = true;
				status = "Recovery: waiting for broker evidence";
			}
			else
			{
				journal.Save(journalPath);
			}
		}
	}

	private static bool SameBrokerAction(string expected, string observed)
	{
		return ((expected == "Buy" || expected == "BuyToCover") && (observed == "Buy" || observed == "BuyToCover")) || ((expected == "Sell" || expected == "SellShort") && (observed == "Sell" || observed == "SellShort"));
	}

	private bool SubmittedIdentityAssigned(CoilJournalOrder row, Order order)
	{
		Guid result;
		Guid result2;
		Order value;
		return order != null && order.Account == Account && order.Instrument != null && order.Instrument.FullName == Instrument.FullName && row.Name == order.Name && Guid.TryParseExact(row.Id, "N", out result) && !string.IsNullOrEmpty(order.OrderId) && !Guid.TryParse(order.OrderId, out result2) && ((ownedOrders.TryGetValue(order.Name, out value) && value == order) || (recoveryOrders.TryGetValue(order.Name, out value) && value == order));
	}

	private bool UpdateJournalOrder(CoilJournalOrder row, Order order)
	{
		if (!SameBrokerAction(row.Action, order.OrderAction.ToString()) || row.Type != order.OrderType.ToString() || row.Quantity != order.Quantity || (!string.IsNullOrEmpty(row.Id) && row.Id != order.OrderId && !SubmittedIdentityAssigned(row, order)))
		{
			throw new InvalidDataException("Owned broker order fingerprint changed.");
		}
		if (order.OrderState == OrderState.Unknown || order.Filled < row.Filled || (CoilJournal.Terminal(row.State) && !CoilJournal.Terminal(order.OrderState.ToString())))
		{
			return false;
		}
		row.Id = order.OrderId;
		row.Filled = order.Filled;
		row.Average = order.AverageFillPrice;
		row.Stop = order.StopPrice;
		row.State = order.OrderState.ToString();
		row.Acknowledged = true;
		return true;
	}

	private static bool AccountRestriction(string message)
	{
		string text = (message ?? "").ToLowerInvariant();
		return text.Contains("liquidation only") || text.Contains("liquidation-only") || text.Contains("liquidate only") ||
			text.Contains("account is restricted") || text.Contains("account restricted") || text.Contains("trading is disabled") ||
			text.Contains("not authorized to trade") || text.Contains("no trading permissions");
	}

	private bool BrokerRestrictionPaused()
	{
		if (State != State.Realtime || string.IsNullOrEmpty(journal?.BrokerRestriction)) return false;
		suspended = true;
		status = "Broker account restricted; protection retained: " + journal.BrokerRestriction;
		return true;
	}

	private void LatchBrokerRestriction(string reason)
	{
		// Commit before any error latch can suppress ordinary journal writes.
		journal.BrokerRestriction = reason;
		try { journal.Save(journalPath); }
		catch (Exception ex) { recoveryBlocked = true; status = "Restriction journal failed: " + ex.Message; return; }
		BrokerRestrictionPaused();
	}

	private void RecoveryOrder(object sender, OrderEventArgs e)
	{
		if (e.Order != null && journal != null && e.Order.Account == Account && e.Order.Instrument == Instrument &&
			journal.Orders.Any(o => o.Name == e.Order.Name) && AccountRestriction(e.Comment))
		{
			LatchBrokerRestriction(e.Comment);
			return;
		}
		if (recovering && e.Order != null && e.Order.Name != null && e.Order.Name.StartsWith(owner + "_"))
		{
			DispatchRecovery();
		}
	}

	private void RecoveryExecution(object sender, ExecutionEventArgs e)
	{
		if (recovering && e.Execution != null && e.Execution.Order != null && e.Execution.Order.Name != null && e.Execution.Order.Name.StartsWith(owner + "_"))
		{
			DispatchRecovery();
		}
	}

	private void DispatchRecovery()
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
					DriveRecovery(SessionClockNy());
				}
			}, null);
		}
		catch (InvalidOperationException)
		{
		}
	}

	private void DriveRecovery(DateTime ny)
	{
		if (!recovering || recoveryBlocked || !BrokerReady() || recoveryDriving)
		{
			return;
		}
		recoveryDriving = true;
		try
		{
			Order[] broker;
			lock (Account.Orders)
			{
				broker = Account.Orders.Where((Order o) => o.Instrument.FullName == Instrument.FullName && o.Name != null && o.Name.StartsWith(owner + "_") && (Working(o) || journal.Orders.Any((CoilJournalOrder j) => j.Name == o.Name))).ToArray();
			}
			lock (Account.Executions)
			{
				broker = broker.Concat(from e in Account.Executions
					where e.Order != null && e.Order.Instrument.FullName == Instrument.FullName && journal.Orders.Any((CoilJournalOrder j) => j.Name == e.Order.Name)
					select e.Order).Distinct().ToArray();
			}
			broker = broker.Concat(recoveryOrders.Values.Where((Order o) => !broker.Any((Order b) => b.Name == o.Name))).ToArray();
			foreach (IGrouping<string, Order> item in from o in broker
				group o by o.Name)
			{
				if (item.Select((Order o) => o.OrderId).Distinct().Count() != 1 || item.Select((Order o) => o.OrderAction).Distinct().Count() != 1 || item.Select((Order o) => o.OrderType).Distinct().Count() != 1 || item.Select((Order o) => o.Quantity).Distinct().Count() != 1)
				{
					throw new InvalidDataException("Duplicate broker order identity.");
				}
			}
			broker = (from o in broker
				group o by o.Name into g
				select (from o in g
					orderby CoilJournal.Terminal(o.OrderState.ToString()) descending, o.Filled descending, o.OrderState == OrderState.Unknown
					select o).First()).ToArray();
			Order[] array = broker;
			foreach (Order order in array)
			{
				if (!journal.Orders.Any((CoilJournalOrder o) => o.Name == order.Name))
				{
					throw new InvalidDataException("Unjournaled owned broker order.");
				}
			}
			foreach (CoilJournalOrder row in journal.Orders)
			{
				Order order2 = broker.FirstOrDefault((Order o) => o.Name == row.Name);
				if (order2 != null)
				{
					if (!UpdateJournalOrder(row, order2))
					{
						status = "Recovery: waiting for broker order status";
						return;
					}
					if (!row.Name.EndsWith("_B") && !row.Name.EndsWith("_S")) ProductExposure.ObserveExit(order2);
				}
				else if (!row.Acknowledged || !CoilJournal.Terminal(row.State))
				{
					status = "Recovery: waiting for owned order history";
					return;
				}
			}
			journal.Save(journalPath);
			if (BrokerRestrictionPaused()) return;
			if (journal.Orders.Any((CoilJournalOrder o) => o.Name.Contains("_REC_") && o.State == "Rejected" && o.Type == "Market"))
			{
				throw new InvalidDataException("Recovery exit rejected; manual broker reconciliation required.");
			}
			bool flag = journal.Orders.Any((CoilJournalOrder o) => o.Name.Contains("_REC_") && o.State == "Rejected" && o.Type == "StopMarket");
			int num2 = journal.Net();
			if (journal.Closed && num2 != 0)
			{
				throw new InvalidDataException("Closed owned cycle has unexpected exposure.");
			}
			if (!AccountSupportsOwnedNet(num2))
			{
				status = "Recovery: waiting for owned exit evidence";
				return;
			}
			bool flag2 = broker.Any((Order o) => (o.Name.EndsWith("_B") || o.Name.EndsWith("_S")) && Working(o));
			bool flag3 = (from o in journal.Orders
				where o.Name.EndsWith("_B") || o.Name.EndsWith("_S")
				select o.Action).Distinct().Count() > 1 && journal.Orders.Any((CoilJournalOrder o) => o.Name.EndsWith("_B") && o.Filled > 0) && journal.Orders.Any((CoilJournalOrder o) => o.Name.EndsWith("_S") && o.Filled > 0);
			DateTime dateTime = journal.Day.AddDays(1.0).AddHours(12.0);
			DateTime dateTime2 = (NewsFlatten ? news.Event(journal.Day.AddDays(1.0), realtime: true) : DateTime.MinValue);
			if (dateTime2 != DateTime.MinValue)
			{
				dateTime = Min(dateTime, dateTime2.AddMinutes(-NewsLeadMinutes));
			}
			if (((num2 == 0) & flag2) && !flag3 && ny < journal.Day.AddDays(1.0).AddHours(3.0) && ny < dateTime && (!NewsFlatten || news.Ready(ny, realtime: true)))
			{
				status = "Recovered owned pending orders";
				return;
			}
			bool close = ((num2 == 0) | flag3 | flag) || ny >= dateTime || (NewsFlatten && !news.Ready(ny, realtime: true));
			Order[] array2 = (from o in broker
				where Working(o) && (o.Name.EndsWith("_B") || o.Name.EndsWith("_S") || (close && o.OrderType != OrderType.Market))
				where o.OrderState != OrderState.CancelPending && o.OrderState != OrderState.CancelSubmitted
				select o).ToArray();
			if (array2.Length != 0)
			{
				Account.Cancel(array2);
				status = "Recovery: cancelling owned orders";
				return;
			}
			if (flag2 || (close && broker.Any((Order o) => Working(o) && o.OrderType != OrderType.Market)))
			{
				status = "Recovery: awaiting cancellation";
				return;
			}
			if (broker.Any((Order o) => Working(o) && o.OrderType == OrderType.Market))
			{
				status = "Recovery: owned exit working";
				return;
			}
			if (num2 == 0)
			{
				if (broker.Any(Working))
				{
					status = "Recovery: awaiting owned order settlement";
				}
				else
				{
					CompleteRecovery();
				}
				return;
			}
			if (close)
			{
				RecoverySubmit((num2 <= 0) ? OrderAction.BuyToCover : OrderAction.Sell, OrderType.Market, Math.Abs(num2), 0.0);
				status = "Recovery: closing owned exposure";
				return;
			}
			OrderAction exit = ((num2 <= 0) ? OrderAction.BuyToCover : OrderAction.Sell);
			Order[] array3 = broker.Where((Order o) => Working(o) && o.OrderType == OrderType.StopMarket).ToArray();
			if (array3.Any((Order o) => !SameBrokerAction(o.OrderAction.ToString(), exit.ToString()) || o.StopPrice <= 0.0))
			{
				throw new InvalidDataException("Owned protection direction/price mismatch.");
			}
			int num3 = array3.Sum((Order o) => o.Quantity - o.Filled);
			int num4 = Math.Abs(num2) - num3;
			if (num4 < 0)
			{
				throw new InvalidDataException("Owned protection exceeds remaining exposure.");
			}
			if (num4 > 0)
			{
				CoilJournalOrder coilJournalOrder = journal.Orders.FirstOrDefault((CoilJournalOrder o) => o.Filled > 0 && (o.Name.EndsWith("_B") || o.Name.EndsWith("_S")));
				double[] array4 = (from o in journal.Orders
					where o.Type == "StopMarket" && SameBrokerAction(o.Action, exit.ToString()) && o.Stop > 0.0 && !o.Name.EndsWith("_B") && !o.Name.EndsWith("_S")
					select o.Stop).ToArray();
				double num5;
				if (array3.Length != 0)
				{
					num5 = ((num2 > 0) ? array3.Max((Order o) => o.StopPrice) : array3.Min((Order o) => o.StopPrice));
				}
				else if (array4.Length != 0)
				{
					num5 = ((num2 > 0) ? array4.Max() : array4.Min());
				}
				else
				{
					num5 = coilJournalOrder?.OriginalStop ?? 0.0;
				}
				if (num5 <= 0.0)
				{
					throw new InvalidDataException("Missing original owned stop price.");
				}
				RecoverySubmit(exit, OrderType.StopMarket, num4, num5);
			}
			status = "Recovered owned trade: existing stops preserved";
		}
		catch (Exception ex)
		{
			recoveryBlocked = true;
			suspended = true;
			status = "Recovery blocked: " + ex.Message;
			Print("TokyoCoil " + status);
		}
		finally
		{
			recoveryDriving = false;
			if (recovering && !recoveryBlocked)
			{
				try
				{
					TryExternalSettlement();
				}
				catch (Exception ex2)
				{
					recoveryBlocked = true;
					suspended = true;
					status = "Recovery storage/settlement blocked: " + ex2.Message;
					Print(status);
				}
			}
		}
	}

	private void RecoverySubmit(OrderAction action, OrderType type, int quantity, double stop)
	{
		if (BrokerRestrictionPaused()) return;
		if (BrokerReady() && AccountSupportsOwnedNet(journal.Net()))
		{
			string text = owner + "_REC_" + Guid.NewGuid().ToString("N");
			Order order = Account.CreateOrder(Instrument, action, type, OrderEntry.Automated, TimeInForce.Gtc, quantity, 0.0, stop, string.Empty, text, DateTime.MaxValue, null);
			journal.Orders.Add(new CoilJournalOrder
			{
				Name = text,
				Action = action.ToString(),
				Type = type.ToString(),
				Quantity = quantity,
				Stop = stop,
				State = "Intent"
			});
			journal.Save(journalPath);
			recoveryOrders[text] = order;
			ProductExposure.ObserveExit(order);
			Account.Submit(new Order[1] { order });
		}
	}

	private void CompleteRecovery()
	{
		active = null;
		ownedNet = 0;
		pendingStopQuantity = 0;
		flattenReason = null;
		flattening = false;
		emergency = false;
		buyOrder = (sellOrder = null);
		ownedOrders.Clear();
		entryPlans.Clear();
		processedFills.Clear();
		recoveryOrders.Clear();
		if (journal.HasFinalR)
		{
			journal.Closed = true;
			journal.Save(journalPath);
			recovering = false;
			model.Reset(journal.Day);
			model.Pending = false;
			model.Consumed = (model.Decided = true);
			status = "Owned cycle already settled";
			return;
		}
		CoilJournalOrder[] array = (from o in journal.Orders
			where o.Name.EndsWith("_B") || o.Name.EndsWith("_S")
			where o.Filled > 0
			select o).ToArray();
		if (array.Length != 0)
		{
			journal.FinalR = journal.PriceR();
			journal.HasFinalR = true;
			journal.Save(journalPath);
			RecordRisk(journal.Cycle, journal.FinalR);
			model.ClosedR.Add(journal.FinalR);
		}
		journal.Closed = true;
		journal.Save(journalPath);
		recovering = false;
		model.Reset(journal.Day);
		model.Pending = false;
		model.Consumed = (model.Decided = true);
		status = "Recovered owned cycle flat";
	}

	private bool BrokerReady()
	{
		return State != State.Realtime || (Account != null && Account.ConnectionStatus == ConnectionStatus.Connected);
	}

	private bool AccountSupportsOwnedNet(int net)
	{
		if (net == 0)
		{
			return true;
		}
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
		return Math.Sign(num) == Math.Sign(net) && Math.Abs(num) >= Math.Abs(net);
	}

	private void CheckRecoveryEvidence(bool poll = false)
	{
		if (State == State.Realtime && journal != null && !recoveryBlocked && !recovering && BrokerReady())
		{
			fillHydrationPending = journal.Net() != ownedNet;
			if ((reconnectPending && !journal.Closed && journal.Orders.Count > 0) || ownedOrders.Values.Any((Order o) => o.OrderState == OrderState.Unknown) || !AccountSupportsOwnedNet(journal.Net()) || (poll && fillHydrationPending))
			{
				recovering = true;
				status = "Recovery: waiting for broker evidence";
			}
		}
	}

	private void TryExternalSettlement()
	{
		if (!BrokerReady() || ownershipLock == null || journal == null || journal.Net() == 0)
		{
			return;
		}
		lock (Account.Positions)
		{
			if (Account.Positions.Any((Position p) => p.Instrument.FullName == Instrument.FullName && p.Quantity != 0))
			{
				return;
			}
		}
		string s = new JavaScriptSerializer().Serialize(journal);
		string text;
		using (SHA256 sHA = SHA256.Create())
		{
			text = BitConverter.ToString(sHA.ComputeHash(Encoding.UTF8.GetBytes(s))).Replace("-", "").Substring(0, 32);
		}
		string text2 = "CLOSED " + text + " NO_ORDERS";
		if (reportedRecoveryCase != text2)
		{
			reportedRecoveryCase = text2;
			Print("TokyoCoil RECOVERY_CASE " + Account.Name + " " + Instrument.FullName + " confirmation=" + text2);
		}
		if (EnableNewTrades || string.IsNullOrEmpty(BrokerCloseConfirmation) || BrokerCloseConfirmation.Trim() != text2 || journal.Orders.Any((CoilJournalOrder o) => (o.Name.EndsWith("_B") || o.Name.EndsWith("_S")) && !CoilJournal.Terminal(o.State)))
		{
			return;
		}
		lock (Account.Orders)
		{
			if (Account.Orders.Any((Order o) => o.Instrument.FullName == Instrument.FullName && o.Name != null && o.Name.StartsWith(owner + "_") && o.OrderState != OrderState.Unknown && Working(o)))
			{
				return;
			}
		}
		string text3 = journalPath + ".settlement_" + text;
		journal.Save(journalPath);
		using (FileStream fileStream = new FileStream(text3 + ".before", FileMode.CreateNew, FileAccess.Write, FileShare.None))
		{
			byte[] array = File.ReadAllBytes(journalPath);
			fileStream.Write(array, 0, array.Length);
			fileStream.Flush(flushToDisk: true);
		}
		CoilJournal coilJournal = journal;
		CoilJournal coilJournal2 = new CoilJournal
		{
			Account = coilJournal.Account,
			Instrument = coilJournal.Instrument,
			Owner = "TC" + Guid.NewGuid().ToString("N"),
			Day = coilJournal.Day,
			Cycle = Guid.NewGuid().ToString("N"),
			Closed = true
		};
		CoilJournal.Atomic(text3 + ".receipt", DateTime.UtcNow.ToString("O") + "\n" + text2 + "\nAdministrative closure; no invented fill or PnL.");
		coilJournal2.Save(journalPath);
		journal = coilJournal2;
		owner = coilJournal2.Owner;
		CompleteRecovery();
		suspended = false;
		status = "Broker closure confirmed; entries disabled";
		Print("TokyoCoil EXTERNAL_SETTLEMENT_COMMITTED " + text3);
	}

	private DateTime SessionClockNy()
	{
		if (State != State.Realtime)
		{
			return latestNy;
		}
		if (Connection.PlaybackConnection != null)
		{
			return CoilModel.NY(Connection.PlaybackConnection.Now, platformZone);
		}
		return TimeZoneInfo.ConvertTimeFromUtc(DateTime.UtcNow, CoilModel.NewYork);
	}

	private void HandleDeadline(DateTime ny)
	{
		if (model == null)
		{
			return;
		}
		DateTime dateTime = ((active != null) ? active.Day : CoilModel.Session(ny));
		DateTime dateTime2 = dateTime.AddDays(1.0).AddHours(12.0);
		if (ny >= dateTime.AddDays(1.0).AddHours(3.0))
		{
			model.Pending = false;
			CancelEntries();
		}
		bool flag = !NewsFlatten || news.Ready(ny, realtime: true);
		DateTime dateTime3 = (NewsFlatten ? news.Event(dateTime.AddDays(1.0), realtime: true) : DateTime.MinValue);
		if (dateTime3 != DateTime.MinValue)
		{
			dateTime2 = Min(dateTime2, dateTime3.AddMinutes(-NewsLeadMinutes));
		}
		if (!flag)
		{
			CancelEntries();
			if (active != null)
			{
				Flatten("NewsUnavailable");
			}
		}
		if (active != null && ny >= dateTime2)
		{
			Flatten((dateTime2 < dateTime.AddDays(1.0).AddHours(12.0)) ? "News" : "Time");
		}
		DriveClose();
	}

	private int Quantity(double entry, double stop)
	{
		double num = ((State == State.Realtime) ? Account.Get(AccountItem.CashValue, Currency.UsDollar) : balance);
		if (num <= 0.0)
		{
			return 0;
		}
		double budget = ((RiskMoney > 0.0) ? RiskMoney : (num * RiskPercent / 100.0)) * model.Brake(EquityBrake);
		double num2 = CoilModel.UnitRisk(entry, stop, Instrument.MasterInstrument.PointValue, forex);
		if (num2 <= 0.0)
		{
			return 0;
		}
		return CoilModel.Size(budget, num2, (!forex) ? 1 : 1000, forex ? 2147482647 : MaxContracts, EnforceRiskBudget);
	}

	private void Submit(int direction, bool market)
	{
		if (!EnableNewTrades)
		{
			return;
		}
		if (!BrokerReady())
		{
			reconnectPending = true;
			model.Pending = false;
			model.Consumed = true;
			return;
		}
		if (State == State.Realtime)
		{
			if (BrokerRestrictionPaused()) return;
			var ownPending = new HashSet<Order>(ownedOrders.Values.Where(o => entryPlans.ContainsKey(o.Name)));
			string reason;
			bool allowed = market
				? ProductExposure.Reserve(owner, direction, Account, Instrument, true, out reason, ownPending)
				: ProductExposure.ReserveBoth(owner, Account, Instrument, true, out reason, ownPending);
			if (!allowed) { status = reason; return; }
		}
		double num = ((direction > 0) ? model.Buy : model.Sell);
		double stop = ((direction > 0) ? model.Low : model.High);
		int num2 = Quantity(num, stop);
		if (num2 <= 0)
		{
			status = "Risk below minimum quantity";
			Log("SKIP_SIZE", latestNy, new CoilTrade
			{
				Day = model.Day,
				Direction = direction,
				Entry = num,
				Stop = stop
			}, 0.0, status);
			return;
		}
		Log("SUBMIT", latestNy, new CoilTrade
		{
			Day = model.Day,
			Direction = direction,
			Entry = num,
			Stop = stop,
			Entered = num2
		}, 0.0, market ? "Market" : "StopMarket");
		string text = owner + "_" + model.Day.ToString("yyyyMMdd") + ((direction > 0) ? "_B" : "_S");
		entryPlans[text] = new CoilTrade
		{
			Day = model.Day,
			Direction = direction,
			Stop = stop
		};
		if (direction > 0)
		{
			buySignal = text;
		}
		else
		{
			sellSignal = text;
		}
		SubmitOwned(2, (direction <= 0) ? OrderAction.SellShort : OrderAction.Buy, market ? OrderType.Market : OrderType.StopMarket, num2, 0.0, market ? 0.0 : num, market ? string.Empty : (owner + "_OCO_" + model.Day.ToString("yyyyMMdd")), text);
		status = "Orders armed";
	}

	private static bool Working(Order order)
	{
		return order != null && order.OrderState != OrderState.Filled && order.OrderState != OrderState.Cancelled && order.OrderState != OrderState.Rejected;
	}

	private void CancelSafe(Order order)
	{
		if (BrokerRestrictionPaused()) return;
		CheckRecoveryEvidence();
		if (BrokerReady() && !recovering && !recoveryBlocked && !fillHydrationPending && Working(order) && order.OrderState != OrderState.Unknown && order.OrderState != OrderState.CancelPending && order.OrderState != OrderState.CancelSubmitted)
		{
			CancelOrder(order);
		}
	}

	private void CancelEntries()
	{
		CancelSafe(buyOrder);
		CancelSafe(sellOrder);
	}

	private void Flatten(string reason)
	{
		if (active == null || flattenReason != null)
		{
			return;
		}
		flattenReason = reason;
		CancelEntries();
		Order[] array = ownedOrders.Values.ToArray();
		foreach (Order order in array)
		{
			if (order.Name.StartsWith(owner + "_STOP_"))
			{
				CancelSafe(order);
			}
		}
		DriveClose();
	}

	private bool Settled(Order order)
	{
		if (order == null)
		{
			return true;
		}
		processedFills.TryGetValue(order.Name, out var value);
		return !Working(order) && value == order.Filled;
	}

	private void ClearSettledEntries()
	{
		if (active == null)
		{
			if (Settled(buyOrder))
			{
				buyOrder = null;
			}
			if (Settled(sellOrder))
			{
				sellOrder = null;
			}
		}
		if (State == State.Realtime && ownedNet == 0 && journal != null && journal.Net() == 0 &&
			journal.Orders.All(o => o.Acknowledged && CoilJournal.Terminal(o.State) &&
				o.Filled == (processedFills.TryGetValue(o.Name, out var processed) ? processed : 0)))
			ProductExposure.Release(owner);
	}

	private void DriveClose()
	{
		if (BrokerRestrictionPaused()) return;
		if (!BrokerReady())
		{
			reconnectPending = true;
			return;
		}
		CheckRecoveryEvidence();
		if (recovering || recoveryBlocked || fillHydrationPending)
		{
			return;
		}
		if (emergency)
		{
			DriveEmergency();
		}
		else
		{
			if (active == null)
			{
				return;
			}
			if (active.Exited == active.Entered && Settled(buyOrder) && Settled(sellOrder))
			{
				Complete();
				return;
			}
			if (flattenReason == null)
			{
				EnsureProtection();
				return;
			}
			pendingStopQuantity = 0;
			CancelEntries();
			Order[] array = ownedOrders.Values.ToArray();
			foreach (Order order in array)
			{
				if (order.Name.StartsWith(owner + "_STOP_"))
				{
					CancelSafe(order);
				}
			}
			if (flattening || !Settled(buyOrder) || !Settled(sellOrder))
			{
				return;
			}
			foreach (Order value in ownedOrders.Values)
			{
				if (value.Name.StartsWith(owner + "_STOP_") && !Settled(value))
				{
					return;
				}
			}
			int num = active.Entered - active.Exited;
			if (num > 0)
			{
				flattening = true;
				SubmitOwned(2, (active.Direction <= 0) ? OrderAction.BuyToCover : OrderAction.Sell, OrderType.Market, num, 0.0, 0.0, string.Empty, owner + "_" + flattenReason);
			}
		}
	}

	private void DriveEmergency()
	{
		if (!BrokerReady())
		{
			reconnectPending = true;
			return;
		}
		CheckRecoveryEvidence();
		if (recovering || recoveryBlocked || fillHydrationPending || drivingEmergency)
		{
			return;
		}
		drivingEmergency = true;
		try
		{
			Order[] array = ownedOrders.Values.ToArray();
			foreach (Order order in array)
			{
				if (order.OrderType != OrderType.Market)
				{
					CancelSafe(order);
				}
			}
			if (!ownedOrders.Values.Any((Order order2) => !Settled(order2)))
			{
				if (ownedNet == 0)
				{
					active = null;
					status = "OCO race closed; suspended";
				}
				else
				{
					SubmitOwned(2, (ownedNet <= 0) ? OrderAction.BuyToCover : OrderAction.Sell, OrderType.Market, Math.Abs(ownedNet), 0.0, 0.0, string.Empty, owner + "_Emergency_" + ++stopSequence);
				}
			}
		}
		finally
		{
			drivingEmergency = false;
		}
	}

	protected override void OnOrderUpdate(Order order, double limitPrice, double stopPrice, int quantity, int filled, double averageFillPrice, OrderState orderState, DateTime time, ErrorCode error, string nativeError)
	{
		if (owner == null || !order.Name.StartsWith(owner + "_"))
		{
			return;
		}
		if (State == State.Realtime && journal != null && journal.Orders.Any(o => o.Name == order.Name) && AccountRestriction(nativeError))
		{
			LatchBrokerRestriction(nativeError);
			return;
		}
		if (recovering || recoveryBlocked)
		{
			DispatchRecovery();
			return;
		}
		JournalOrder(order);
		if (recovering || recoveryBlocked)
		{
			DispatchRecovery();
			return;
		}
		ownedOrders[order.Name] = order;
		if (State == State.Realtime && !entryPlans.ContainsKey(order.Name)) ProductExposure.ObserveExit(order);
		if (order.Name == buySignal)
		{
			buyOrder = order;
		}
		if (order.Name == sellSignal)
		{
			sellOrder = order;
		}
		if (error != ErrorCode.NoError || orderState == OrderState.Rejected)
		{
			suspended = true;
			model.Pending = false;
			model.Consumed = true;
			status = "Owned order rejected";
			CancelEntries();
			if (active != null)
			{
				Flatten("OrderError");
			}
			Print("TokyoCoil owned order error: " + error.ToString() + " " + nativeError);
		}
		DriveClose();
	}

	protected override void OnExecutionUpdate(Execution execution, string executionId, double price, int quantity, MarketPosition marketPosition, string orderId, DateTime time)
	{
		if (recovering || recoveryBlocked)
		{
			DispatchRecovery();
		}
		else
		{
			if (execution == null || execution.Order == null || !executions.Add(executionId))
			{
				return;
			}
			Order order = execution.Order;
			if (!order.Name.StartsWith(owner + "_"))
			{
				return;
			}
			processedFills.TryGetValue(order.Name, out var value);
			processedFills[order.Name] = value + quantity;
			ownedNet += ((order.OrderAction == OrderAction.Buy || order.OrderAction == OrderAction.BuyToCover) ? quantity : (-quantity));
			if (emergency)
			{
				DriveEmergency();
				return;
			}
			bool flag = entryPlans.TryGetValue(order.Name, out var value2);
			DateTime dateTime = CoilModel.NY(time, platformZone);
			if (flag)
			{
				int direction = value2.Direction;
				if (active != null && active.Direction != direction)
				{
					emergency = true;
					suspended = true;
					model.Pending = false;
					model.Consumed = true;
					status = "OCO race: closing owned net";
					DriveEmergency();
					return;
				}
				if (active == null)
				{
					active = new CoilTrade
					{
						Day = value2.Day,
						Fill = dateTime,
						Direction = direction,
						Stop = value2.Stop
					};
					model.Trades.Add(active);
				}
				active.Entered += quantity;
				active.EntrySum += price * (double)quantity;
				active.Entry = active.EntrySum / (double)active.Entered;
				active.Fees += execution.Commission;
				model.Consumed = true;
				model.Pending = false;
				CancelEntries();
				status = "In trade";
				if (flattenReason == null)
				{
					pendingStopQuantity += quantity;
					EnsureProtection();
				}
			}
			else if (active != null && !emergency)
			{
				active.Exited += quantity;
				active.ExitSum += price * (double)quantity;
				active.Fees += execution.Commission;
				active.Exit = dateTime;
				active.Close = (active.ActualClose = active.ExitSum / (double)active.Exited);
				active.Scheduled = order.Name == owner + "_Time" || order.Name.StartsWith(owner + "_Time_");
				active.Reference = active.Day.AddDays(1.0).AddHours(12.0);
			}
			DriveClose();
		}
	}

	private void EnsureProtection()
	{
		if (BrokerReady() && active != null && flattenReason == null && !emergency && pendingStopQuantity > 0)
		{
			int num = Math.Min(pendingStopQuantity, active.Entered - active.Exited);
			if (num <= 0)
			{
				pendingStopQuantity = 0;
				return;
			}
			pendingStopQuantity -= num;
			SubmitOwned(2, (active.Direction <= 0) ? OrderAction.BuyToCover : OrderAction.Sell, OrderType.StopMarket, num, 0.0, active.Stop, string.Empty, owner + "_STOP_" + ++stopSequence);
		}
	}

	private void Complete()
	{
		if (active != null)
		{
			double num = (double)active.Direction * (active.Close - active.Entry) / Math.Abs(active.Entry - active.Stop);
			model.ClosedR.Add(num);
			if (State == State.Realtime && journal != null)
			{
				journal.FinalR = num;
				journal.HasFinalR = true;
				journal.Closed = true;
				journal.Save(journalPath);
				RecordRisk(journal.Cycle, num);
			}
			double num2 = (forex ? (1.0 / active.ActualClose) : Instrument.MasterInstrument.PointValue);
			balance += (double)active.Direction * (active.ActualClose - active.Entry) * (double)active.Entered * num2 - active.Fees;
			Log("CLOSE", active.Exit, active, num, flattenReason ?? "Stop");
			active = null;
			flattening = false;
			flattenReason = null;
			buyOrder = (sellOrder = null);
			status = "Session consumed";
		}
	}

	private void Log(string evt, DateTime ny, CoilTrade t, double r, string detail)
	{
		if (audit != null)
		{
			audit.WriteLine(string.Join(",", evt, ny.ToString("yyyy-MM-dd HH:mm:ss"), t.Day.ToString("yyyy-MM-dd"), t.Direction, t.Entry.ToString("R", CultureInfo.InvariantCulture), t.Stop.ToString("R", CultureInfo.InvariantCulture), t.ActualClose.ToString("R", CultureInfo.InvariantCulture), t.Entered, r.ToString("R", CultureInfo.InvariantCulture), detail, t.Fill.ToString("yyyy-MM-dd HH:mm:ss"), t.Fees.ToString("R", CultureInfo.InvariantCulture), balance.ToString("R", CultureInfo.InvariantCulture)));
		}
	}

	private void Line(string tag, DateTime from, DateTime to, double price, DashStyleHelper style)
	{
		if (!(to < from))
		{
			DateTime left = CoilModel.Platform(from, platformZone);
			DateTime right = CoilModel.Platform(to, platformZone);
			QueueDrawing(tag, () =>
			{
				NinjaTrader.NinjaScript.DrawingTools.Line line = Draw.Line(this, tag, isAutoScale: false, left, price, right, price, EntryInk, style, 1);
				line.ZOrder = 1;
			});
		}
	}

	private void Box(string tag, DateTime from, DateTime to, double a, double b, Brush ink, int opacity)
	{
		if (!(to <= from) && !(Math.Abs(a - b) < TickSize / 2.0))
		{
			DateTime left = CoilModel.Platform(from, platformZone);
			DateTime right = CoilModel.Platform(to, platformZone);
			QueueDrawing(tag, () =>
			{
				Rectangle rectangle = Draw.Rectangle(this, tag, isAutoScale: false, left, a, right, b, ink, ink, opacity);
				rectangle.ZOrder = 1;
			});
		}
	}

	private void QueueDrawing(string tag, Action update)
	{
		ChartControl chart = ChartControl;
		if (chart == null || State == State.Terminated)
		{
			return;
		}
		lock (drawingGate)
		{
			drawingUpdates[tag] = update;
			if (drawingQueued)
			{
				return;
			}
			drawingQueued = true;
		}
		chart.Dispatcher.InvokeAsync(() =>
		{
			Action[] array;
			lock (drawingGate)
			{
				array = drawingUpdates.Values.ToArray();
				drawingUpdates.Clear();
				drawingQueued = false;
			}
			if (State != State.Terminated && ChartControl == chart)
			{
				Action[] array2 = array;
				foreach (Action action in array2)
				{
					action();
				}
				chart.InvalidateVisual();
			}
		});
	}

	private void Paint(DateTime ny)
	{
		if (ShowVisuals && ChartControl != null)
		{
			int num = ((BarsPeriod.BarsPeriodType == BarsPeriodType.Minute) ? (60 * BarsPeriod.Value) : 60);
			foreach (CoilBox box in model.Boxes.Values)
			{
				string text = owner + box.Day.ToString("yyyyMMdd");
				if (ny >= box.Day.AddHours(23.0) && !model.Qualifies(box.Day))
				{
					string[] array = new string[3] { "R", "1", "-1" };
					foreach (string text2 in array)
					{
						string remove = text + text2;
						QueueDrawing(remove, () =>
						{
							RemoveDrawObject(remove);
						});
					}
					continue;
				}
				DateTime to = Min(ny, box.Day.AddHours(23.0).AddSeconds(-1.0));
				Box(text + "R", box.Day.AddHours(20.0), to, box.High, box.Low, RangeInk, 25);
				int[] array2 = new int[2] { 1, -1 };
				for (int num2 = 0; num2 < array2.Length; num2++)
				{
					int side = array2[num2];
					CoilTrade coilTrade = model.Trades.FirstOrDefault((CoilTrade t) => t.Day == box.Day && t.Direction == side);
					if (coilTrade == null && ny >= box.Day.AddDays(1.0).AddHours(3.0))
					{
						string tag = text + side;
						QueueDrawing(tag, () =>
						{
							RemoveDrawObject(tag);
						});
					}
					else
					{
						DateTime to2 = ((coilTrade != null) ? new DateTime(coilTrade.Fill.Ticks / 600000000 * 600000000).AddSeconds(59.0) : ny.AddSeconds(2 * num - 1));
						Line(text + side, (side > 0) ? box.HighTime : box.LowTime, to2, (side > 0) ? box.High : box.Low, (coilTrade == null) ? DashStyleHelper.Dash : DashStyleHelper.Solid);
					}
				}
			}
			foreach (CoilTrade trade in model.Trades)
			{
				string text3 = owner + trade.Day.ToString("yyyyMMdd") + "T";
				if (!model.Qualifies(trade.Day))
				{
					string[] array3 = new string[3] { "E", "S", "P" };
					foreach (string text4 in array3)
					{
						string remove2 = text3 + text4;
						QueueDrawing(remove2, () =>
						{
							RemoveDrawObject(remove2);
						});
					}
				}
				else
				{
					bool flag = trade.Exit != DateTime.MinValue && (!trade.Scheduled || trade.ReferenceReady);
					DateTime to3;
					if (trade.Exit == DateTime.MinValue)
					{
						to3 = CoilModel.Right(trade.Fill, ny, num);
					}
					else
					{
						to3 = (trade.Scheduled ? trade.Reference.AddSeconds(59.0) : trade.Exit);
					}
					double b = ((flag && (double)trade.Direction * (trade.Close - trade.Entry) <= 0.0) ? trade.Close : trade.Stop);
					Line(text3 + "E", trade.Fill, to3, trade.Entry, trade.Synthetic ? DashStyleHelper.Dash : DashStyleHelper.Solid);
					Box(text3 + "S", trade.Fill, to3, trade.Entry, b, StopInk, 0);
					if (flag && (double)trade.Direction * (trade.Close - trade.Entry) > 0.0)
					{
						Box(text3 + "P", trade.Fill, to3, trade.Entry, trade.Close, ProfitInk, 0);
					}
				}
			}
		}
		if (!ShowPanel || ChartControl == null)
		{
			return;
		}
		DateTime dateTime = SessionClockNy();
		bool flag2 = dateTime.DayOfWeek <= DayOfWeek.Thursday && dateTime.TimeOfDay >= TimeSpan.FromHours(20.0);
		bool flag3 = flag2 && dateTime.TimeOfDay < TimeSpan.FromHours(23.0);
		model.Boxes.TryGetValue(dateTime.Date, out var value);
		double num4 = value?.High ?? double.NaN;
		double num5 = value?.Low ?? double.NaN;
		if (flag3 && State == State.Realtime && CurrentBars[1] >= 0)
		{
			DateTime dateTime2 = CoilModel.NY(Times[1][0], platformZone);
			if (dateTime2.AddMinutes(-1.0).Date == dateTime.Date && dateTime2.AddMinutes(-1.0).TimeOfDay >= TimeSpan.FromHours(20.0) && dateTime2.AddMinutes(-1.0) <= dateTime)
			{
				num4 = (double.IsNaN(num4) ? Highs[1][0] : Math.Max(num4, Highs[1][0]));
				num5 = (double.IsNaN(num5) ? Lows[1][0] : Math.Min(num5, Lows[1][0]));
			}
		}
		bool flag4 = flag2 && !double.IsNaN(num4) && num4 >= num5;
		bool newsBlocked = State == State.Realtime && (recoveryBlocked || !BrokerReady() || (NewsFlatten && !news.Ready(dateTime, realtime: true)));
		int num6 = ((journal != null && (recovering || recoveryBlocked)) ? journal.Net() : 0);
		double num7 = ((journal == null) ? 0.0 : (from o in journal.Orders
			where o.Type == "StopMarket" && !CoilJournal.Terminal(o.State) && o.Stop > 0.0
			select o.Stop).DefaultIfEmpty(0.0).First());
		dashboard.Publish(new CoilDashState
		{
			Clock = dateTime.ToString("HH:mm:ss"),
			Mode = Instrument.FullName + " · 23:00–03:00",
			Status = ((recovering || recoveryBlocked) ? status : ((!BrokerReady()) ? "Account disconnected" : ((!flag2) ? "Awaiting new range" : (flag3 ? "Range forming" : (flag4 ? "Range locked" : "Range unavailable"))))),
			RangeHigh = (flag4 ? num4.ToString("0.#####", CultureInfo.InvariantCulture) : "--"),
			RangeLow = (flag4 ? num5.ToString("0.#####", CultureInfo.InvariantCulture) : "--"),
			RangeWidth = (flag4 ? (((num4 - num5) / TickSize).ToString("0") + "t") : "--"),
			Position = ((num6 != 0) ? (((num6 > 0) ? "LONG " : "SHORT ") + Math.Abs(num6)) : ((active == null) ? "FLAT" : (((active.Direction > 0) ? "LONG " : "SHORT ") + (active.Entered - active.Exited)))),
			Stop = ((num7 > 0.0) ? num7.ToString("0.#####", CultureInfo.InvariantCulture) : ((active == null) ? "--" : active.Stop.ToString("0.#####", CultureInfo.InvariantCulture))),
			Risk = "Risk " + ((RiskMoney > 0.0) ? ("$" + (RiskMoney * model.Brake(EquityBrake)).ToString("0.##")) : ((RiskPercent * model.Brake(EquityBrake)).ToString("0.##") + "%")) + " · Brake " + ((!EquityBrake) ? "OFF" : ((model.Brake(enabled: true) < 1.0) ? "HALF" : "ON")),
			Costs = (NewsFlatten ? ("FF news " + NewsLeadMinutes + "m early · " + (news.Ready(dateTime, State == State.Realtime) ? "OK" : "unavailable")) : "News OFF · Exit 12:00 PM NY"),
			History = "NY Time: " + dateTime.ToString("HH:mm:ss") + " [" + CoilModel.Platform(dateTime, platformZone).ToString("HH:mm:ss") + "]",
			InTrade = (active != null || num6 != 0),
			NewsBlocked = newsBlocked
		});
	}

	protected override void OnRender(ChartControl chartControl, ChartScale chartScale)
	{
		base.OnRender(chartControl, chartScale);
		if (!ShowPanel || dashboard == null || chartControl == null)
		{
			return;
		}
		try
		{
			try
			{
				if (ZOrder != int.MaxValue)
				{
					ZOrder = int.MaxValue;
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
			if (!dashboardFaultLogged)
			{
				dashboardFaultLogged = true;
				Print("[TokyoCoil] Dashboard render unavailable: " + ex.Message);
			}
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
		try
		{
			ChartControl chartControl = ChartControl;
			if (chartControl != null && dashboard != null)
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
			if (chartControl != null && dashboard != null)
			{
				Point point = DashboardPoint(chartControl, e.GetPosition(chartControl));
				if (dashboard.MouseMove((float)point.X, (float)point.Y))
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
}
}
namespace NinjaTrader.NinjaScript.Strategies.TokyoCoil_NT
{
using SolidColorBrush = SharpDX.Direct2D1.SolidColorBrush;
public sealed class CoilBox
{
	public DateTime Day;

	public DateTime HighTime;

	public DateTime LowTime;

	public double High = double.MinValue;

	public double Low = double.MaxValue;

	public readonly HashSet<DateTime> FiveMinutes = new HashSet<DateTime>();

	public bool Valid(bool inverse)
	{
		return Day.DayOfWeek != DayOfWeek.Friday && Day.DayOfWeek != DayOfWeek.Saturday && FiveMinutes.Count >= 30 && Width(inverse) >= 0.019999999;
	}

	public double Width(bool inverse)
	{
		return (inverse && Low > 0.0) ? (1.0 / Low - 1.0 / High) : (High - Low);
	}
}

internal sealed class CoilDashState
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

internal sealed class CoilDashboard
{
	private readonly object sync = new object();

	private CoilDashState state;

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

	internal void Publish(CoilDashState next)
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
		CoilDashState coilDashState;
		bool flag;
		double num;
		double num2;
		lock (sync)
		{
			coilDashState = state;
			flag = collapsed;
			num = offsetX;
			num2 = offsetY;
		}
		if (coilDashState == null || rt == null || chart == null)
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
			Text(rt, dw, "TOKYO COIL", 13f, solidColorBrush, num3 + 24f, num4 + 13f, 143f, bold: true);
			Text(rt, dw, coilDashState.Mode, 9f, brush3, num3 + 24f, num4 + 34f, 151f);
			Text(rt, dw, "NEW YORK", 8.5f, brush3, num6 - 98f, num4 + 13f, 80f, bold: false, right: true);
			Text(rt, dw, coilDashState.Clock, 13f, solidColorBrush, num6 - 98f, num4 + 32f, 80f, bold: true, right: true);
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
				Text(rt, dw, coilDashState.Status, 11.5f, coilDashState.NewsBlocked ? solidColorBrush3 : solidColorBrush, num3 + 20f, num4 + 69f, 222f);
				Text(rt, dw, "SESSION RANGE  ·  20:00–22:55", 9f, brush3, num3 + 20f, num4 + 95f, 184f);
				Text(rt, dw, coilDashState.RangeWidth, 13f, solidColorBrush, num6 - 55f, num4 + 92f, 55f, bold: true, right: true);
				Text(rt, dw, "HIGH", 9f, solidColorBrush2, num3 + 20f, num4 + 122f, 30f);
				Text(rt, dw, coilDashState.RangeHigh, 13f, solidColorBrush, num3 + 57f, num4 + 119f, 65f, bold: true, right: true);
				Text(rt, dw, "LOW", 9f, solidColorBrush3, num3 + 140f, num4 + 122f, 30f);
				Text(rt, dw, coilDashState.RangeLow, 13f, solidColorBrush, num3 + 177f, num4 + 119f, 65f, bold: true, right: true);
				Rule(rt, brush2, num3 + 20f, num4 + 149f, 222f);
				Text(rt, dw, "POSITION", 9f, brush3, num3 + 20f, num4 + 159f, 106f);
				Text(rt, dw, "HARD STOP", 9f, brush3, num3 + 139f, num4 + 159f, num6 - num3 - 139f, bold: false, right: true);
				Text(rt, dw, coilDashState.Position, 13f, coilDashState.InTrade ? solidColorBrush2 : solidColorBrush, num3 + 20f, num4 + 174f, 106f, bold: true);
				Text(rt, dw, coilDashState.Stop, 13f, solidColorBrush3, num3 + 139f, num4 + 174f, num6 - num3 - 139f, bold: true, right: true);
				Rule(rt, brush2, num3 + 20f, num4 + 199f, 222f);
				Text(rt, dw, coilDashState.Risk, 11.5f, solidColorBrush, num3 + 20f, num4 + 210f, 222f);
				Text(rt, dw, coilDashState.Costs, 9.5f, brush3, num3 + 20f, num4 + 229f, 222f);
				Text(rt, dw, coilDashState.History, 8.5f, brush3, num3 + 20f, num4 + 248f, 222f);
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

public sealed class CoilJournal
{
	public int Version = 1;

	// Optional v1 JSON extension; legacy journals omit this field.
	public string BrokerRestriction;

	public string Account;

	public string Instrument;

	public string Owner;

	public string Cycle;

	public DateTime Day;

	public DateTime Fill;

	public int Direction;

	public double Stop;

	public double FinalR;

	public bool Closed;

	public bool HasFinalR;

	public List<CoilJournalOrder> Orders = new List<CoilJournalOrder>();

	public static void Atomic(string path, string text)
	{
		string text2 = path + ".next";
		using (FileStream fileStream = new FileStream(text2, FileMode.Create, FileAccess.Write, FileShare.None))
		{
			using StreamWriter streamWriter = new StreamWriter(fileStream);
			streamWriter.Write(text);
			streamWriter.Flush();
			fileStream.Flush(flushToDisk: true);
		}
		if (File.Exists(path))
		{
			File.Replace(text2, path, path + ".previous");
		}
		else
		{
			File.Move(text2, path);
		}
	}

	public void Save(string path)
	{
		Atomic(path, new JavaScriptSerializer().Serialize(this));
	}

	public static CoilJournal Load(string path, string account, string instrument)
	{
		CoilJournal j = new JavaScriptSerializer().Deserialize<CoilJournal>(File.ReadAllText(path));
		if (j == null || j.Version != 1 || j.Account != account || j.Instrument != instrument || string.IsNullOrEmpty(j.Owner) || !j.Owner.StartsWith("TC") || j.Orders == null || !Finite(j.FinalR) || !Finite(j.Stop) || (j.Orders.Count > 0 && (string.IsNullOrEmpty(j.Cycle) || j.Day == DateTime.MinValue)) || j.Orders.Any((CoilJournalOrder o) => o == null || string.IsNullOrEmpty(o.Name) || !o.Name.StartsWith(j.Owner + "_") || o.Quantity <= 0 || o.Filled < 0 || o.Quantity < o.Filled || !Finite(o.Average) || !Finite(o.Stop) || !Finite(o.OriginalStop) || o.Stop < 0.0 || o.OriginalStop < 0.0 || (o.Filled > 0 && o.Average <= 0.0) || !new string[4] { "Buy", "BuyToCover", "Sell", "SellShort" }.Contains(o.Action) || !new string[2] { "Market", "StopMarket" }.Contains(o.Type) || string.IsNullOrEmpty(o.State)) || j.Orders.Select((CoilJournalOrder o) => o.Name).Distinct().Count() != j.Orders.Count)
		{
			throw new InvalidDataException("Owned recovery journal is invalid.");
		}
		return j;
	}

	public static bool Finite(double v)
	{
		return !double.IsNaN(v) && !double.IsInfinity(v);
	}

	public static bool TokyoOrderName(string name)
	{
		return name != null && name.Length > 35 && name.StartsWith("TC", StringComparison.Ordinal) && name[34] == '_' && name.Substring(2, 32).ToLowerInvariant().All((char c) => "0123456789abcdef".Contains(c));
	}

	public static bool Terminal(string state)
	{
		return state == "Filled" || state == "Cancelled" || state == "Rejected";
	}

	public int Net()
	{
		return Orders.Sum((CoilJournalOrder o) => ((o.Action == "Buy" || o.Action == "BuyToCover") ? 1 : (-1)) * o.Filled);
	}

	public double PriceR()
	{
		CoilJournalOrder[] entries = Orders.Where((CoilJournalOrder o) => o.Filled > 0 && (o.Name.EndsWith("_B") || o.Name.EndsWith("_S"))).ToArray();
		if (entries.Length == 0 || entries.Select((CoilJournalOrder o) => o.Action).Distinct().Count() != 1 || Net() != 0)
		{
			throw new InvalidDataException("Owned closed cycle does not reconcile.");
		}
		CoilJournalOrder[] source = Orders.Where((CoilJournalOrder o) => o.Filled > 0 && !entries.Contains(o)).ToArray();
		if (source.Sum((CoilJournalOrder o) => o.Filled) != entries.Sum((CoilJournalOrder o) => o.Filled))
		{
			throw new InvalidDataException("Owned exit quantities do not reconcile.");
		}
		double num = entries.Sum((CoilJournalOrder o) => (double)o.Filled * o.Average) / (double)entries.Sum((CoilJournalOrder o) => o.Filled);
		double num2 = Math.Abs(num - entries[0].OriginalStop);
		if (entries[0].OriginalStop <= 0.0 || num2 <= 0.0)
		{
			throw new InvalidDataException("Original owned risk unavailable.");
		}
		double num3 = source.Sum((CoilJournalOrder o) => (double)o.Filled * o.Average) / (double)source.Sum((CoilJournalOrder o) => o.Filled);
		return (double)((entries[0].Action == "Buy") ? 1 : (-1)) * (num3 - num) / num2;
	}
}

public sealed class CoilJournalOrder
{
	public string Name;

	public string Id;

	public string Action;

	public string Type;

	public string State;

	public int Quantity;

	public int Filled;

	public double Average;

	public double Stop;

	public double OriginalStop;

	public bool Acknowledged;
}

public sealed class CoilModel
{
	public static readonly TimeZoneInfo NewYork = TimeZoneInfo.FindSystemTimeZoneById("Eastern Standard Time");

	public readonly SortedDictionary<DateTime, CoilBox> Boxes = new SortedDictionary<DateTime, CoilBox>();

	public readonly SortedSet<DateTime> Sessions = new SortedSet<DateTime>();

	public readonly List<double> ClosedR = new List<double>();

	public readonly List<CoilTrade> Trades = new List<CoilTrade>();

	public DateTime Day;

	public DateTime LastMinute = DateTime.MinValue;

	public bool Decided;

	public bool Pending;

	public bool Consumed;

	public bool Gap;

	public double Buy;

	public double Sell;

	public double High;

	public double Low;

	public bool Inverse;

	public static DateTime Session(DateTime ny)
	{
		return ny.AddHours(-17.0).Date;
	}

	public static DateTime NY(DateTime platform, TimeZoneInfo zone)
	{
		return TimeZoneInfo.ConvertTime(DateTime.SpecifyKind(platform, DateTimeKind.Unspecified), zone, NewYork);
	}

	public static DateTime Platform(DateTime ny, TimeZoneInfo zone)
	{
		return TimeZoneInfo.ConvertTime(DateTime.SpecifyKind(ny, DateTimeKind.Unspecified), NewYork, zone);
	}

	public void Minute(DateTime start, double high, double low)
	{
		DateTime dateTime = Session(start);
		Sessions.Add(dateTime);
		if (start.Hour >= 20 && start.Hour < 23)
		{
			if (!Boxes.TryGetValue(dateTime, out var value))
			{
				value = new CoilBox
				{
					Day = dateTime
				};
				Boxes.Add(dateTime, value);
			}
			if (high > value.High)
			{
				value.High = high;
				value.HighTime = start;
			}
			if (low < value.Low)
			{
				value.Low = low;
				value.LowTime = start;
			}
			value.FiveMinutes.Add(start.Date.AddMinutes(Math.Floor(start.TimeOfDay.TotalMinutes / 5.0) * 5.0));
		}
	}

	public double Relative(DateTime day, double width)
	{
		DateTime[] source = Sessions.Where((DateTime d) => d < day).Reverse().Take(20)
			.ToArray();
		double[] array = (from d in source
			where Boxes.ContainsKey(d) && Boxes[d].Valid(Inverse)
			select Boxes[d].Width(Inverse) into v
			orderby v
			select v).ToArray();
		if (array.Length < 10)
		{
			return -1.0;
		}
		int num = array.Length;
		double num2 = ((num % 2 == 1) ? array[num / 2] : ((array[num / 2 - 1] + array[num / 2]) / 2.0));
		return width / num2;
	}

	public void Reset(DateTime day)
	{
		if (Day != day)
		{
			Day = day;
			Decided = (Pending = (Consumed = (Gap = false)));
		}
	}

	public bool Qualifies(DateTime day)
	{
		if (!Boxes.TryGetValue(day, out var value) || !value.Valid(Inverse))
		{
			return false;
		}
		double num = Relative(day, value.Width(Inverse));
		return num > 0.0 && num < 1.0;
	}

	public void ResumeAfterGap(DateTime ny)
	{
		Reset(Session(ny));
		Pending = false;
		Consumed = (Decided = ny >= Day.AddHours(23.0));
	}

	public bool Arm(DateTime ny, double spread, double tick)
	{
		Reset(Session(ny));
		if (Decided || ny.Hour != 23 || ny.Minute >= 5)
		{
			return false;
		}
		Decided = true;
		if (!Boxes.TryGetValue(Day, out var value) || !value.Valid(Inverse))
		{
			return false;
		}
		double num = Relative(Day, value.Width(Inverse));
		if (num <= 0.0 || num >= 1.0)
		{
			return false;
		}
		High = value.High;
		Low = value.Low;
		Buy = Math.Ceiling((High + spread + tick) / tick - 1E-08) * tick;
		Sell = Math.Floor((Low - tick) / tick + 1E-08) * tick;
		Pending = true;
		return true;
	}

	public int Touch(double bid, double ask, bool arming)
	{
		if (!Pending || Consumed)
		{
			return 0;
		}
		bool flag = (arming ? (bid > High) : (ask >= Buy));
		bool flag2 = (arming ? (bid < Low) : (bid <= Sell));
		if (!flag && !flag2)
		{
			return 0;
		}
		Consumed = true;
		Pending = false;
		return flag ? 1 : (-1);
	}

	public double Brake(bool enabled)
	{
		return (enabled && ClosedR.Count >= 20 && ClosedR.Skip(Math.Max(0, ClosedR.Count - 20)).Sum() <= -4.0) ? 0.5 : 1.0;
	}

	public static double UnitRisk(double entry, double stop, double pointValue, bool forex)
	{
		return (entry > 0.0) ? (Math.Abs(entry - stop) * (forex ? (1.0 / entry) : pointValue)) : 0.0;
	}

	public static int Size(double budget, double unitRisk, int step, int maximum, bool enforceBudget)
	{
		if (budget <= 0.0 || unitRisk <= 0.0 || double.IsNaN(budget) || double.IsInfinity(budget) || double.IsNaN(unitRisk) || double.IsInfinity(unitRisk) || step <= 0 || maximum < step)
		{
			return 0;
		}
		double num = Math.Floor(budget / unitRisk / (double)step) * (double)step;
		if (num < (double)step && !enforceBudget)
		{
			num = step;
		}
		return (int)Math.Min(num, Math.Floor((double)maximum / (double)step) * (double)step);
	}

	public static DateTime Right(DateTime fill, DateTime now, int seconds)
	{
		Func<DateTime, DateTime> func = (DateTime t) => new DateTime(t.Ticks / TimeSpan.FromSeconds(seconds).Ticks * TimeSpan.FromSeconds(seconds).Ticks).AddSeconds(seconds - 1);
		DateTime dateTime = func(fill).AddSeconds(3 * seconds);
		DateTime dateTime2 = func(now).AddSeconds(2 * seconds);
		return (dateTime > dateTime2) ? dateTime : dateTime2;
	}
}

public sealed class CoilNews
{
	private DateTime[] historical = new DateTime[0];

	private DateTime[] live = new DateTime[0];

	private DateTime from;

	private DateTime through;

	private DateTime fetchedUtc;

	private DateTime attemptUtc;

	private DateTime liveWeek;

	private int fetching;

	private bool lastAttemptOK;

	private readonly object sync = new object();

	private static readonly HttpClient Http = CreateHttp();

	private static HttpClient CreateHttp()
	{
		HttpClient httpClient = new HttpClient
		{
			Timeout = TimeSpan.FromSeconds(5.0)
		};
		httpClient.DefaultRequestHeaders.UserAgent.ParseAdd("Mozilla/5.0");
		httpClient.DefaultRequestHeaders.Accept.ParseAdd("application/json");
		return httpClient;
	}

	public void Load(string path)
	{
		string[] source = File.ReadAllLines(path + ".coverage.csv");
		string[] array = source.Last((string s) => !string.IsNullOrWhiteSpace(s)).Split(',');
		if (array.Length < 3 || array[2].Trim() != "COMPLETE")
		{
			throw new InvalidDataException("Historical news coverage must be audited COMPLETE.");
		}
		from = DateTime.ParseExact(array[0].Trim(), "yyyy.MM.dd", CultureInfo.InvariantCulture);
		through = DateTime.ParseExact(array[1].Trim(), "yyyy.MM.dd", CultureInfo.InvariantCulture).AddDays(1.0);
		List<DateTime> list = new List<DateTime>();
		string[] array2 = File.ReadAllLines(path);
		foreach (string text in array2)
		{
			if (!DateTime.TryParseExact(text.Trim(), new string[2] { "yyyy.MM.dd HH:mm", "yyyy.MM.dd HH:mm:ss" }, CultureInfo.InvariantCulture, DateTimeStyles.None, out var result))
			{
				throw new InvalidDataException("Invalid NY event row: " + text);
			}
			if (result < from || result >= through)
			{
				throw new InvalidDataException("Event outside audited coverage.");
			}
			list.Add(result);
		}
		historical = (from t in list.Distinct()
			orderby t
			select t).ToArray();
	}

	public void Refresh()
	{
		lock (sync)
		{
			DateTime utcNow = DateTime.UtcNow;
			DateTime dateTime = TimeZoneInfo.ConvertTimeFromUtc(utcNow, CoilModel.NewYork);
			bool flag = fetchedUtc != DateTime.MinValue && utcNow >= fetchedUtc && utcNow - fetchedUtc < TimeSpan.FromHours(1.0) && dateTime.Date >= liveWeek && dateTime.Date < liveWeek.AddDays(7.0);
			if (utcNow - attemptUtc < TimeSpan.FromMinutes((flag && lastAttemptOK) ? 30 : 5) || Interlocked.CompareExchange(ref fetching, 1, 0) != 0)
			{
				return;
			}
			attemptUtc = DateTime.UtcNow;
			lastAttemptOK = false;
		}
		Task.Run(async () =>
		{
			try
			{
				string json = await Http.GetStringAsync("https://nfs.faireconomy.media/ff_calendar_thisweek.json").ConfigureAwait(continueOnCapturedContext: false);
				List<Dictionary<string, object>> rows = new JavaScriptSerializer().Deserialize<List<Dictionary<string, object>>>(json);
				List<DateTime> times = new List<DateTime>();
				DateTime fetchedNy = TimeZoneInfo.ConvertTimeFromUtc(DateTime.UtcNow, CoilModel.NewYork);
				DateTime expectedWeek = fetchedNy.Date.AddDays(0 - fetchedNy.DayOfWeek);
				if (rows == null || rows.Count == 0)
				{
					throw new InvalidDataException("Empty weekly payload.");
				}
				foreach (Dictionary<string, object> row in rows)
				{
					string value = Convert.ToString(row["date"]);
					if (!value.EndsWith("Z") && !Regex.IsMatch(value, "[+-]\\d\\d:\\d\\d$"))
					{
						throw new InvalidDataException("News timestamp lacks offset.");
					}
					DateTime eventNy = TimeZoneInfo.ConvertTimeFromUtc(DateTimeOffset.Parse(value, CultureInfo.InvariantCulture).UtcDateTime, CoilModel.NewYork);
					if (eventNy.Date < expectedWeek || eventNy.Date >= expectedWeek.AddDays(7.0))
					{
						throw new InvalidDataException("Wrong-week payload.");
					}
					if (Convert.ToString(row["country"]) == "USD" && Convert.ToString(row["impact"]) == "High")
					{
						times.Add(eventNy);
					}
				}
				lock (sync)
				{
					live = (from t in times.Distinct()
						orderby t
						select t).ToArray();
					fetchedUtc = DateTime.UtcNow;
					liveWeek = expectedWeek;
					lastAttemptOK = true;
				}
			}
			catch
			{
			}
			finally
			{
				Interlocked.Exchange(ref fetching, 0);
			}
		});
	}

	public bool Ready(DateTime ny, bool realtime)
	{
		if (!realtime)
		{
			return ny >= from && ny < through;
		}
		lock (sync)
		{
			DateTime utcNow = DateTime.UtcNow;
			if (fetchedUtc == DateTime.MinValue || utcNow < fetchedUtc || utcNow - fetchedUtc >= TimeSpan.FromHours(1.0))
			{
				return false;
			}
			return ny.Date >= liveWeek && ny.Date < liveWeek.AddDays(7.0);
		}
	}

	public DateTime Event(DateTime date, bool realtime)
	{
		DateTime[] source;
		lock (sync)
		{
			source = (realtime ? live : historical);
		}
		return source.FirstOrDefault((DateTime t) => t.Date == date.Date && t.Hour < 12);
	}
}

public sealed class CoilTrade
{
	public DateTime Day;

	public DateTime Fill;

	public DateTime Exit;

	public DateTime Reference;

	public double Entry;

	public double Stop;

	public double Close;

	public double ActualClose;

	public double EntrySum;

	public double ExitSum;

	public double Fees;

	public int Direction;

	public int Entered;

	public int Exited;

	public bool Synthetic;

	public bool Scheduled;

	public bool ReferenceReady;
}
}
