//+------------------------------------------------------------------+
//| NQPrecisionBot.cs — NQ Precision NinjaTrader 8 strategy runtime  |
//| NQ Precision: ETH M1 signal filters and print-driven execution   |
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
using SharpDX.Direct2D1;
using SharpDX.DirectWrite;
using SharpDX;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Timers;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using System.Windows;
using System.Xml.Serialization;
using System;
using Brush = System.Windows.Media.Brush;

namespace NinjaTrader.NinjaScript.Strategies
{
public class NQPrecisionBot : Strategy
{
	private sealed class ExecutionView
	{
		internal string Tag;

		internal int Side;

		internal double Entry;

		internal double InitialStop;

		internal double Stop;

		internal double Exit;

		internal DateTime Entered;

		internal DateTime Exited;

		internal DateTime TrailStart;

		internal bool Trailing;
	}

private static class PrecisionExecutionVisual
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
			strategy.Print("[NQ Precision] Chart drawing failed: " + ex.Message);
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

	private sealed class RecoverySnapshot
	{
		internal int Quantity;

		internal int Filled;

		internal double Limit;

		internal double Stop;

		internal double Average;

		internal OrderState State;

		internal DateTime Time;

		internal ErrorCode Error;

		internal string Comment;
	}

	private sealed class RecoveryRequest
	{
		internal string Name;

		internal string Id;

		internal string Oco;

		internal OrderAction Action;

		internal OrderType Type;

		internal int Quantity;

		internal int Processed;

		internal double Limit;

		internal double Stop;

		internal double Value;
	}

	private sealed class FeeSlice
	{
		internal Execution Execution;

		internal int Quantity;

		internal bool Entry;
	}

	private sealed class FeeTrade
	{
		internal string Signal;

		internal bool Closed;

		internal readonly Dictionary<string, FeeSlice> Slices = new Dictionary<string, FeeSlice>();

		internal int EntryQuantity => Slices.Values.Where((FeeSlice x) => x.Entry).Sum((FeeSlice x) => x.Quantity);

		internal int ExitQuantity => Slices.Values.Where((FeeSlice x) => !x.Entry).Sum((FeeSlice x) => x.Quantity);

		internal double RoundTurn => (Closed && EntryQuantity > 0 && EntryQuantity == ExitQuantity) ? (Slices.Values.Sum((FeeSlice x) => Charge(x.Execution)) / (double)EntryQuantity) : 0.0;

		internal static double Charge(Execution e)
		{
			double commission = e.Commission;
			double fee = e.Fee;
			return ((double.IsNaN(commission) || double.IsInfinity(commission)) ? 0.0 : Math.Abs(commission)) + ((double.IsNaN(fee) || double.IsInfinity(fee)) ? 0.0 : Math.Abs(fee));
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

	internal sealed class Candle
	{
        public double Volume;
		public DateTime Start;

		public DateTime Last;

		public double Open;

		public double High;

		public double Low;

		public double Close;

		public Candle(DateTime t, double o, double h, double l, double c)
		{
			Start = (Last = t);
			Open = o;
			High = h;
			Low = l;
			Close = c;
		}

		public Candle Clone()
		{
			return new Candle(Start, Open, High, Low, Close)
			{
				Last = Last, Volume = Volume
			};
		}

		public void Merge(Candle b)
		{
			High = Math.Max(High, b.High);
			Low = Math.Min(Low, b.Low);
			Close = b.Close;
			Last = b.Last;
            Volume += b.Volume;
		}
	}

    internal sealed class TickMinuteBuilder
    {
        private Candle forming;
        private DateTime closedThrough;

        public Candle Push(DateTime at, double price, double volume)
        {
            // Source indexes deduplicate callbacks; equal-time trades remain distinct prints.
            if (at < closedThrough || (forming != null && at < forming.Last)) return null;
            Candle completed = CloseThrough(at);
            DateTime start = at.AddTicks(-(at.Ticks % TimeSpan.TicksPerMinute));
            if (forming == null)
                forming = new Candle(start, price, price, price, price) { Last = at, Volume = volume };
            else
            {
                forming.High = Math.Max(forming.High, price);
                forming.Low = Math.Min(forming.Low, price);
                forming.Close = price;
                forming.Last = at;
                forming.Volume += volume;
            }
            return completed;
        }

        public Candle CloseThrough(DateTime at)
        {
            if (forming == null || forming.Start.AddMinutes(1) > at) return null;
            Candle completed = forming;
            forming = null;
            closedThrough = completed.Start.AddMinutes(1);
            return completed;
        }
    }

	private sealed class Bracket
	{
		public string StopName;

		public string TargetName;

		public Order Stop;

		public Order Target;
	}



    internal sealed class PrecisionModel
    {
        internal sealed class Snapshot
        {
            public DateTime End;
            public double Atr, Regime, Rvol;
        }
        private readonly int shortPeriod,longPeriod,volumePeriod,startSecond,endSecond;
        private readonly Queue<double> volumes=new Queue<double>();
        private DateTime lastEnd,day;
        private double previousClose=double.NaN, atr, longAtr, volumeSum;
        private Snapshot current, previous;
        public int Count { get; private set; }
        public double RangeHigh { get; private set; }
        public double RangeLow { get; private set; }
        public bool HaveRange { get; private set; }
        public bool RangeReady { get; private set; }
        public PrecisionModel(int shortLength,int longLength,int volumeLength,int rangeStart,int rangeEnd)
        {
            shortPeriod=shortLength; longPeriod=longLength; volumePeriod=volumeLength;
            startSecond=rangeStart/10000*3600+rangeStart/100%100*60+rangeStart%100;
            endSecond=rangeEnd/10000*3600+rangeEnd/100%100*60+rangeEnd%100;
        }
        public bool Push(Candle bar)
        {
            DateTime end=bar.Start.AddMinutes(1);
            if(end<=lastEnd) return false;
            if(day!=bar.Start.Date)
            {
                day=bar.Start.Date; volumes.Clear(); volumeSum=0;
                HaveRange=RangeReady=false; RangeHigh=double.MinValue; RangeLow=double.MaxValue;
            }
            double tr=bar.High-bar.Low;
            if(!double.IsNaN(previousClose)) tr=Math.Max(tr,Math.Max(Math.Abs(bar.High-previousClose),Math.Abs(bar.Low-previousClose)));
            Count++;
            int n=Math.Min(Count,shortPeriod), l=Math.Min(Count,longPeriod);
            atr=(atr*(n-1)+tr)/n; longAtr=(longAtr*(l-1)+tr)/l;
            previousClose=bar.Close;
            volumes.Enqueue(bar.Volume); volumeSum+=bar.Volume;
            if(volumes.Count>volumePeriod) volumeSum-=volumes.Dequeue();
            previous=current;
            current=new Snapshot { End=end, Atr=atr, Regime=longAtr>0?atr/longAtr:double.NaN, Rvol=volumes.Count==volumePeriod && volumeSum>0?bar.Volume*volumePeriod/volumeSum:double.NaN };
            int second=(int)bar.Start.TimeOfDay.TotalSeconds;
            if(second>=startSecond && second<endSecond)
            {
                RangeHigh=Math.Max(RangeHigh,bar.High); RangeLow=Math.Min(RangeLow,bar.Low); HaveRange=true;
            }
            if(HaveRange && end.TimeOfDay.TotalSeconds>=endSecond) RangeReady=true;
            lastEnd=end;
            return true;
        }
        public Snapshot At(DateTime time)
        {
            if(current!=null && current.End<=time) return current;
            if(previous!=null && previous.End<=time) return previous;
            return null;
        }
    }

	private static readonly object ownerLock = new object();

	private static readonly HashSet<string> activeOwners = new HashSet<string>();

	private string ownerKey;

	private string exposureKey;

	private bool ownsGuard;

	private string legacyExternalCloseConfirmation = string.Empty;

	private SortedDictionary<DateTime, Candle> minutes;

	private Dictionary<string, Order> orders;

	private Dictionary<string, int> processed;

	private HashSet<string> executions;

	private List<Bracket> brackets;


	private TimeZoneInfo platformZone;

	private TimeZoneInfo easternZone;

	private TimeZoneInfo nyZone;

	private System.Timers.Timer timer;

	private StreamWriter log;

	private DateTime lastMinute;

	private DateTime latestEastern;

	private DateTime sessionDay;

	private DateTime startupFloor;

	private DateTime lastExecutionMinute;

	private int consumedSourceIndex = -1;

	private BarsRequest historyRepair;

	private readonly SortedDictionary<DateTime, Candle> providerBars = new SortedDictionary<DateTime, Candle>();

	private DateTime repairRetry;

	private DateTime recoveryFloor;

	private bool sourceFresh = true;

	private int executionSeries = 2;

	private int signalSeries = 1;
    private PrecisionModel precision;
    private TickMinuteBuilder sourceTickMinutes;
    private DateTime decisionDay, firstEntryTime, tradeDeadline;
    private DateTime lastVisualSecond;

	private string signalContract;

	private int direction;

	private int entryCount;

	private int ownedNet;

	private int entered;

	private int exited;

	private int sequence;

	private double averageATR;

	private double rangeHigh;

	private double rangeLow;

	private double plannedStop;

	private double plannedTarget;

	private double entrySum;

	private double exitSum;

	private double initialRisk;

	private double peakR;

	private double actualFees;

	private double tradeModeledCost;

	private double recoveredCommissionFloor;

	private bool validDay;

	private bool readyRange;

	private bool suspended;

	private bool closing;

	private bool closingDrive;

	private bool entryPending;

	private bool startupArmed;

	private bool closeRejected;

	private string pendingCloseName;

	private int pendingCloseQuantity;

	private int pendingCloseExecuted;

	private int pendingCloseFinal = -1;

	private string owner;

	private string entryName;

	private string closeReason;

	private string status = "Loading completed M1 history";

	private bool nativeDisplayQueued;

	private bool historicalVisualsPainted;

	private readonly Dictionary<IDrawingTool, bool> hiddenVisuals = new Dictionary<IDrawingTool, bool>();

	private bool visualSyncQueued;

	private bool visualHistoryWaiting;

	private readonly HashSet<string> loggedDecisions = new HashSet<string>();

	private string lastStatePrinted;

	private long historicalPrints;

	private long lastHistoricalPanelMinute;

	private const int TriggerGraceSeconds = 5;

	private ExecutionView executionVisual;

	private readonly List<ExecutionView> closedVisuals = new List<ExecutionView>();

	private readonly ModelDashboard dashboard = new ModelDashboard();

	private ChartControl dashboardChart;

	private bool dashboardMouseHooked;

	private bool dashboardFaultLogged;

	private bool dashboardLayered;

	private int dashboardRedrawQueued;

	private readonly Dictionary<string, RecoverySnapshot> recoverySnapshots = new Dictionary<string, RecoverySnapshot>();

	private readonly Dictionary<string, RecoveryRequest> recoveryRequests = new Dictionary<string, RecoveryRequest>();

	private readonly HashSet<string> recoveredOrderNames = new HashSet<string>();

	private string recoveryPath;

	private string recoveryIdentity;

	private bool recoveryPending;

	private bool recoveredTrade;

	private bool reconcilingRecovery;

	private bool recoveryFault;

	private bool recoveryReady;

	private Account recoveryAccount;

	private bool repairingProtection;

	private string applyingRecoveryExecution;

	private readonly Dictionary<string, int> reportedFilled = new Dictionary<string, int>();

	private FileStream recoveryLock;

	private string externalRecoveryCaseReported;

	private string externalRecoveryRefusalReported;

	private bool connectionPaused;

	private DateTime recoveryNextPollUtc;

	private static readonly object FeeGate = new object();

	private static readonly Dictionary<string, List<FeeTrade>> FeeHistory = new Dictionary<string, List<FeeTrade>>();

	private FeeTrade feeTrade;

	[NinjaScriptProperty]
	[Display(Name = "Enable new trades", GroupName = "01 Trading", Order = 0)]
	public bool EnableTrading { get; set; }

	[Browsable(false)]
	[XmlIgnore]
	private string ExternalCloseConfirmation
	{
		get
		{
			return legacyExternalCloseConfirmation ?? string.Empty;
		}
		set
		{
			legacyExternalCloseConfirmation = value ?? string.Empty;
		}
	}

	[NinjaScriptProperty]
	[Range(1.0, double.MaxValue)]
	[Display(Name = "Risk per trade, including costs ($)", GroupName = "02 Risk", Order = 0)]
	public double RiskMoney { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "Use a fixed number of contracts", Description = "When enabled, contract quantity replaces the dollar risk budget. Stop/target and ownership protection remain active.", GroupName = "02 Risk", Order = 1)]
	public bool UseFixedSize { get; set; }

	[NinjaScriptProperty]
	[Range(1, int.MaxValue)]
	[Display(Name = "Fixed contract quantity", Description = "Whole contracts per entry when fixed sizing is enabled.", GroupName = "02 Risk", Order = 2)]
	public int FixedContracts { get; set; }

	[NinjaScriptProperty]
	[Range(0.0, double.MaxValue)]
	[Display(Name = "Round-trip commission fallback / contract ($)", Description = "Used until a completed live trade supplies nonzero NT execution charges. These may come from your commission template.", GroupName = "03 Costs", Order = 0)]
	public double CommissionPerContract { get; set; }

	[NinjaScriptProperty]
	[Range(0, int.MaxValue)]
	[Display(Name = "Slippage/side (x0.01; 3=0.03)", Description = "Cost reserve in 0.01 price units: 3=0.03, 25=0.25 (one NQ/MNQ tick), 100=1.00 price. This does not change native historical fill slippage, which NT8 specifies separately in ticks.", GroupName = "03 Costs", Order = 1)]
	public int SlippagePoints { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "Show levels, trade markers and information", GroupName = "04 Display", Order = 0)]
	public bool ShowVisuals { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "Write detailed decision and trade logs", GroupName = "05 Logging", Order = 0)]
	public bool WriteTradeLog { get; set; }

	[NinjaScriptProperty]
	[Display(Name = "Block opposing index exposure", Description = "Reject opposing index positions or pending entries across locally visible NT8 accounts. Exact-instrument ownership isolation remains active.", GroupName = "01 Trading", Order = 1)]
	public bool BlockOpposingExposure { get; set; }


    [NinjaScriptProperty]
    [Display(Name="Use tick history for source and fills", Description="True reconstructs completed ETH M1 signals from source ticks and executes on ticks. False uses stored M1 OHLC approximation. Live processes execution-instrument prints in either mode.", GroupName="06 NQ rules", Order=0)]
    public bool UseTickHistory { get; set; }
    [NinjaScriptProperty, Range(1, 10000)]
    [Display(Name="ATR short period", GroupName="06 NQ rules", Order=1)]
    public int AtrPeriod { get; set; }
    [NinjaScriptProperty, Range(1, 10000)]
    [Display(Name="ATR regime period", GroupName="06 NQ rules", Order=2)]
    public int AtrRegimeLen { get; set; }
    [NinjaScriptProperty, Range(0.000001, 1000.0)]
    [Display(Name="Stop ATR multiple", GroupName="06 NQ rules", Order=3)]
    public double AtrSlMult { get; set; }
    [NinjaScriptProperty, Range(0.000001, 1000.0)]
    [Display(Name="Target ATR multiple", GroupName="06 NQ rules", Order=4)]
    public double AtrTpMult { get; set; }
    [NinjaScriptProperty, Range(1, 10000)]
    [Display(Name="RVOL period", GroupName="06 NQ rules", Order=5)]
    public int RvolLen { get; set; }
    [NinjaScriptProperty, Range(0.0, 1000.0)]
    [Display(Name="Minimum RVOL", GroupName="06 NQ rules", Order=6)]
    public double RvolMin { get; set; }
    [NinjaScriptProperty, Range(0.0, 1000.0)]
    [Display(Name="Maximum RVOL", GroupName="06 NQ rules", Order=7)]
    public double RvolMax { get; set; }
    [NinjaScriptProperty, Range(0.0, 1000.0)]
    [Display(Name="Minimum ATR regime", GroupName="06 NQ rules", Order=8)]
    public double RegimeMin { get; set; }
    [NinjaScriptProperty, Range(0.0, 1000.0)]
    [Display(Name="Maximum ATR regime", GroupName="06 NQ rules", Order=9)]
    public double RegimeMax { get; set; }
    [NinjaScriptProperty, Range(0, 235959)]
    [Display(Name="Range start HHMMSS Eastern", GroupName="06 NQ rules", Order=10)]
    public int RangeStart { get; set; }
    [NinjaScriptProperty, Range(0, 235959)]
    [Display(Name="Range end HHMMSS Eastern", GroupName="06 NQ rules", Order=11)]
    public int RangeEnd { get; set; }
    [NinjaScriptProperty, Range(0, 235959)]
    [Display(Name="Trigger HHMMSS Eastern", GroupName="06 NQ rules", Order=12)]
    public int TriggerTime { get; set; }
    [NinjaScriptProperty, Range(0, 235959)]
    [Display(Name="Entry cutoff HHMMSS Eastern", GroupName="06 NQ rules", Order=13)]
    public int TradeUntil { get; set; }
    [NinjaScriptProperty, Range(1, 1440)]
    [Display(Name="Time close after minutes", GroupName="06 NQ rules", Order=14)]
    public int CloseAfterMin { get; set; }
    [NinjaScriptProperty]
    [Display(Name="Use RVOL and regime filters", GroupName="06 NQ rules", Order=15)]
    public bool UseFilters { get; set; }
    [NinjaScriptProperty]
    [Display(Name="Use fixed trigger", GroupName="06 NQ rules", Order=16)]
    public bool UseTriggerTime { get; set; }
    [NinjaScriptProperty]
    [Display(Name="Use time close", GroupName="06 NQ rules", Order=17)]
    public bool UseTimeClose { get; set; }

	// Drawings are hidden only while the signal history itself is being rebuilt. Trading holds (suspension, recovery, disconnects, warm-up)
	// are reported by the panel and Output; they must never blank the range, levels and execution boxes.
	private bool VisualsSuppressed => State == State.Realtime && (historyRepair != null || visualHistoryWaiting);

	private string FeeScope => ((Account == null) ? "unknown" : Account.Name) + "|" + ExecutionInstrument.FullName;

	private bool CanLearnFee
	{
		get
		{
			if (State != State.Realtime || Account == null || Connection.PlaybackConnection != null)
			{
				return false;
			}
			string name = Account.Name ?? "";
			return name.Length > 0 && !new string[4] { "Sim", "Playback", "Replay", "Backtest" }.Any((string prefix) => name.StartsWith(prefix, StringComparison.OrdinalIgnoreCase));
		}
	}

	private double EffectiveCommission
	{
		get
		{
			if (!CanLearnFee)
			{
				return CommissionPerContract;
			}
			lock (FeeGate)
			{
				if (FeeHistory.TryGetValue(FeeScope, out var value))
				{
					for (int num = value.Count - 1; num >= 0; num--)
					{
						double roundTurn = value[num].RoundTurn;
						if (roundTurn > 0.0)
						{
							return roundTurn;
						}
					}
				}
				return CommissionPerContract;
			}
		}
	}

	private double SlippagePrice => (double)SlippagePoints * 0.01;

	private double CostPerContract => EffectiveCommission + 2.0 * SlippagePrice * ExecutionInstrument.MasterInstrument.PointValue;

	private Instrument ExecutionInstrument => BarsArray[0].Instrument;

private string VisualFaultReason()
    {
        if (State != State.Realtime) return null;
        if (Account == null || Account.ConnectionStatus != ConnectionStatus.Connected) return "Account disconnected; orders paused";
        if (recoveryFault || suspended || closeRejected) return status;
        if (recoveryPending || reconcilingRecovery) return "Reconciling exact owned broker evidence; entries paused";
        if (historyRepair != null || visualHistoryWaiting) return status;
        if (precision == null || precision.Count < Math.Max(AtrPeriod,AtrRegimeLen)) return "Completed ETH M1 ATR history warming up";
        return null;
    }


	private void SyncFaultVisuals()
	{
		ChartControl chart = ChartControl;
		if (chart == null || visualSyncQueued)
		{
			return;
		}
		visualSyncQueued = true;
		Action action = () =>
		{
			visualSyncQueued = false;
			if (State != State.Terminated)
			{
				bool visualsSuppressed = VisualsSuppressed;
				if (visualsSuppressed)
				{
					IDrawingTool[] array = DrawObjects.ToArray();
					foreach (IDrawingTool drawingTool in array)
					{
						if (drawingTool != null && drawingTool.DrawnBy == this)
						{
							if (!hiddenVisuals.ContainsKey(drawingTool))
							{
								hiddenVisuals[drawingTool] = drawingTool.IsVisible;
							}
							drawingTool.IsVisible = false;
						}
					}
				}
				else
				{
					foreach (KeyValuePair<IDrawingTool, bool> hiddenVisual in hiddenVisuals)
					{
						hiddenVisual.Key.IsVisible = hiddenVisual.Value;
					}
					hiddenVisuals.Clear();
				}
				chart.InvalidateVisual();
			}
		};
		if (chart.Dispatcher.CheckAccess())
		{
			action();
		}
		else
		{
			chart.Dispatcher.BeginInvoke(DispatcherPriority.Background, action);
		}
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
				Print("[Execution visuals] Native execution display unavailable: " + ex.Message);
			}
		});
	}

	// Visual coordinates only: never change execution timestamps or the signal series.
	private static int ExecutionRightBar(int entryBar, int eventBar, bool closed)
	{
		return Math.Max(entryBar + 2, eventBar + (closed ? 0 : 1));
	}

	private DateTime ExecutionRightTime(DateTime entered, DateTime at, bool closed)
	{
		Bars viewed = BarsArray[0];
		int entryBar = viewed.GetBar(entered);
		int eventBar = viewed.GetBar(at);
		if (entryBar < 0 || eventBar < 0 || viewed.Count == 0)
			return entered.AddMinutes(2);
		int rightBar = ExecutionRightBar(entryBar, eventBar, closed);
		if (rightBar < viewed.Count)
			return viewed.GetTime(rightBar);
		DateTime last = viewed.GetTime(viewed.Count - 1);
		int ahead = rightBar - viewed.Count + 1;
		int value = Math.Max(1, viewed.BarsPeriod.Value);
		switch (viewed.BarsPeriod.BarsPeriodType)
		{
			case BarsPeriodType.Second: return last.AddSeconds(ahead * value);
			case BarsPeriodType.Minute: return last.AddMinutes(ahead * value);
			case BarsPeriodType.Day: return last.AddDays(ahead * value);
			case BarsPeriodType.Week: return last.AddDays(7 * ahead * value);
			case BarsPeriodType.Month: return last.AddMonths(ahead * value);
			case BarsPeriodType.Year: return last.AddYears(ahead * value);
			default:
				// Future non-time bars have no timestamp yet; use the latest observed spacing.
				long ticks = viewed.Count > 1 ? Math.Max(TimeSpan.TicksPerSecond, (last - viewed.GetTime(viewed.Count - 2)).Ticks) : TimeSpan.TicksPerMinute;
				return last.AddTicks(ticks * ahead);
		}
	}

	private void DrawExecution(ExecutionView trade, DateTime now)
	{
		if (ShowVisuals && trade != null)
		{
			bool flag = trade.Exited != DateTime.MinValue;
			DateTime right = ExecutionRightTime(Platform(trade.Entered), Platform(flag ? trade.Exited : now), flag);
			double num = (double)trade.Side * (trade.Exit - trade.Entry);
			double slPx = ((flag && num <= 0.0) ? trade.Exit : trade.InitialStop);
			PrecisionExecutionVisual.DrawExecutionTool(this, trade.Tag, trade.Side > 0, trade.Entry, slPx, (flag && num > 0.0) ? trade.Exit : 0.0, trade.Entry, Platform(trade.Entered), Platform(trade.Entered), right, trailing: false, DateTime.MinValue, synthetic: false);
			if (trade.Trailing)
			{
				PrecisionExecutionVisual.DrawBoundedLine(this, trade.Tag + "_TRAIL", Platform(trade.TrailStart), trade.Stop, right, trade.Stop, PrecisionExecutionVisual.ClrTrailingStop, DashStyleHelper.Dot, 2);
			}
		}
	}

	private void PaintHistoricalExecutions(DateTime now)
	{
		if (ShowVisuals)
		{
			EnableNativeExecutionDisplay();
		}
		if (!ShowVisuals)
		{
			return;
		}
		if (!historicalVisualsPainted && State != State.Historical && ChartControl != null)
		{
			HashSet<string> hashSet = new HashSet<string>(from x in DrawObjects
				where x != null
				select x.Tag);
			historicalVisualsPainted = true;
			foreach (ExecutionView closedVisual in closedVisuals)
			{
				// Re-anchor after the complete viewing series has loaded, including existing objects.
				DrawExecution(closedVisual, closedVisual.Exited);
				if (!hashSet.Contains(closedVisual.Tag + "_SL"))
				{
					historicalVisualsPainted = false;
				}
			}
		}
		if (executionVisual == null)
		{
			return;
		}
		Order order = (from b in brackets
			where b.Stop != null
			select b.Stop).FirstOrDefault();
		if (order != null && Math.Abs(order.StopPrice - executionVisual.InitialStop) > TickSize / 2.0)
		{
			if (!executionVisual.Trailing)
			{
				executionVisual.TrailStart = now;
			}
			executionVisual.Trailing = true;
			executionVisual.Stop = order.StopPrice;
		}
		DrawExecution(executionVisual, now);
	}

protected override void OnStateChange()
    {
        if (State == State.SetDefaults)
        {
            Name = "NQPrecisionBot";
            Description = "NQ Precision: Eastern opening range, completed ETH minute Wilder ATR/RVOL, print-driven trigger; independent owned execution and recovery.";
            Calculate = Calculate.OnEachTick;
            IsUnmanaged = true;
            StartBehavior = StartBehavior.ImmediatelySubmit;
            IsExitOnSessionCloseStrategy = false;
            RealtimeErrorHandling = RealtimeErrorHandling.IgnoreAllErrors;
            ConnectionLossHandling = ConnectionLossHandling.KeepRunning;
            BarsRequiredToTrade = 60; Slippage = 0;
            IsInstantiatedOnEachOptimizationIteration = true;
            MaximumBarsLookBack = MaximumBarsLookBack.TwoHundredFiftySix;
            OrderFillResolution = OrderFillResolution.Standard;
            IsFillLimitOnTouch = true;
            EntriesPerDirection = 1;
            EntryHandling = EntryHandling.AllEntries;
            StopTargetHandling = StopTargetHandling.PerEntryExecution;
            TimeInForce = TimeInForce.Gtc;
            IsOverlay = true; DrawOnPricePanel = true;
            EnableTrading = true; BlockOpposingExposure = true;
            RiskMoney = 500; UseFixedSize = true; FixedContracts = 1;
            CommissionPerContract = 3; SlippagePoints = 3;
            ShowVisuals = true; WriteTradeLog = true; UseTickHistory = true;
            AtrPeriod = 14; AtrRegimeLen = 50; AtrSlMult = 2.2; AtrTpMult = 0.8; // 0.3 was original default (tight scalp); 0.8 matched MT5 OptB winner (2020–2026 sweep)
            RvolLen = 14; RvolMin = 0.5; RvolMax = 1.5; RegimeMin = 1; RegimeMax = 2.5;
            RangeStart = 93000; RangeEnd = 94500; TriggerTime = 95955; TradeUntil = 110000;
            UseFilters = true; UseTriggerTime = true; UseTimeClose = true; CloseAfterMin = 8;
        }
        else if (State == State.Configure)
        {
            if (StartBehavior != StartBehavior.ImmediatelySubmit)
            {
                // A saved instance, workspace or Analyzer template can carry another start behavior. This strategy keeps its own durable
                // ownership records and must never wait on or adopt foreign account positions, so it always runs as ImmediatelySubmit.
                StartBehavior saved = StartBehavior;
                try { StartBehavior = StartBehavior.ImmediatelySubmit; }
                catch (Exception) { }
                if (StartBehavior != StartBehavior.ImmediatelySubmit)
                    throw new InvalidOperationException("ImmediatelySubmit is required for independent owned execution; set Start behavior = Immediately submit (saved value: " + saved + ").");
                Print("NQPB START_BEHAVIOR saved value '" + saved + "' replaced by ImmediatelySubmit (required for independent owned execution)");
            }
            if (OrderFillResolution != OrderFillResolution.Standard)
                throw new InvalidOperationException("Use Standard fill resolution; the strategy supplies its own execution series.");
            if (!(RiskMoney > 0) || double.IsInfinity(RiskMoney) || FixedContracts < 1 || AtrPeriod < 1 || AtrRegimeLen < 1 || RvolLen < 1
                || !(AtrSlMult > 0) || !(AtrTpMult > 0) || double.IsInfinity(AtrSlMult) || double.IsInfinity(AtrTpMult)
                || RvolMin < 0 || RvolMax < RvolMin || RegimeMin < 0 || RegimeMax < RegimeMin || CloseAfterMin < 1
                || !ValidClock(RangeStart) || !ValidClock(RangeEnd) || !ValidClock(TriggerTime) || !ValidClock(TradeUntil)
                || Clock(RangeEnd) <= Clock(RangeStart) || Clock(TriggerTime) < Clock(RangeEnd))
                throw new InvalidOperationException("Invalid NQ risk, filter, range or timing inputs.");
            IncludeTradeHistoryInBacktest = true;
            signalContract = SourceContract(Instrument);
            signalSeries = 1;
            executionSeries = UseTickHistory && signalContract == Instrument.FullName ? signalSeries : 2;
            AddDataSeries(signalContract, new BarsPeriod { BarsPeriodType = UseTickHistory ? BarsPeriodType.Tick : BarsPeriodType.Minute, Value = 1 }, "CME US Index Futures ETH", true);
            if (executionSeries != signalSeries)
                AddDataSeries(Instrument.FullName, new BarsPeriod { BarsPeriodType = UseTickHistory ? BarsPeriodType.Tick : BarsPeriodType.Minute, Value = 1 }, "CME US Index Futures ETH", true);
        }
        else if (State == State.DataLoaded)
        {
            minutes = new SortedDictionary<DateTime, Candle>();
            orders = new Dictionary<string, Order>(); processed = new Dictionary<string, int>();
            executions = new HashSet<string>(); brackets = new List<Bracket>();
            precision = NewPrecisionModel();
            sourceTickMinutes = new TickMinuteBuilder(); consumedSourceIndex = -1;
            platformZone = Globals.GeneralOptions.TimeZoneInfo;
            easternZone = TimeZoneInfo.FindSystemTimeZoneById("Eastern Standard Time");
            nyZone = easternZone;
            owner = "NQPB_" + Guid.NewGuid().ToString("N").Substring(0,12);
            if (!(ExecutionInstrument.MasterInstrument.PointValue > 0) || !(ExecutionInstrument.MasterInstrument.TickSize > 0))
                throw new InvalidOperationException("Invalid native execution-instrument specification.");
            PrepareRecovery();
            if (WriteTradeLog)
            {
                string folder = Path.Combine(Globals.UserDataDir,"NQPrecisionBot","logs");
                Directory.CreateDirectory(folder);
                log = new StreamWriter(Path.Combine(folder, owner + ".csv")) { AutoFlush = true };
                log.WriteLine("event,eastern_time,detail");
            }
            string inputContract = "source="+(UseTickHistory ? "Tick1-derived ETH M1" : "stored ETH M1 approximation")
                +";sourceContract="+signalContract+";execution="+(UseTickHistory ? "Tick1" : "M1")
                +";fillOnTouch="+IsFillLimitOnTouch+";nativeSlippage="+Slippage;
            Print("NQPB TICK_SOURCE_V2 "+inputContract+" | wall="+DateTime.Now.ToString("HH:mm:ss",CultureInfo.InvariantCulture));
            Record("CONFIG", Eastern(NativeNow()), inputContract);
        }
        else if (State == State.Transition)
        {
            if (ownedNet != 0 || entryPending || orders.Values.Any(o => !Settled(o) || !ExecutionsCaughtUp(o)))
                throw new InvalidOperationException("Historical owned exposure must settle before realtime; load a completed session.");
        }
        else if (State == State.Realtime)
        {
            ownerKey = (Account == null ? "" : Account.Name) + "|" + ExecutionInstrument.FullName;
            exposureKey = ownerKey;
            lock(ownerLock) { ownsGuard = activeOwners.Add(ownerKey); }
            if (!ownsGuard) { suspended = true; status = "Another NQ Precision instance owns this account/contract"; return; }
            startupFloor = Eastern(NativeNow()); startupArmed = true;
            StartRecovery();
            Print("NQPB REALTIME " + startupFloor.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture) + " ET | wall=" + DateTime.Now.ToString("HH:mm:ss", CultureInfo.InvariantCulture) + " historicalPrints=" + historicalPrints + " account=" + (Account == null ? "none" : Account.Name) + " instrument=" + ExecutionInstrument.FullName + " recoveryPending=" + recoveryPending + " recoveryFault=" + recoveryFault + " suspended=" + suspended + " decisionDay=" + decisionDay.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture) + " status=" + status);
            timer = new System.Timers.Timer(1000) { AutoReset = true };
            timer.Elapsed += (object sender, ElapsedEventArgs args) => {
                try { TriggerCustomEvent(o => TimerStep(),null); } catch (InvalidOperationException) { }
            };
            timer.Start();
        }
        else if (State == State.Terminated)
        {
            StopRecovery(); HookDashboardMouse(false);
            if (historyRepair != null) { historyRepair.Dispose(); historyRepair = null; }
            if (ownedNet == 0 && !entryPending && (orders == null || orders.Values.All(o => Settled(o) && ExecutionsCaughtUp(o)))) ReleaseExposure();
            if (ownsGuard) { lock(ownerLock) { activeOwners.Remove(ownerKey); } ownsGuard = false; }
            if (timer != null) { timer.Stop(); timer.Dispose(); timer = null; }
            if (log != null) { log.Dispose(); log = null; }
        }
    }




	internal static string SourceContract(Instrument instrument)
	{
		string text = instrument.MasterInstrument.Name.Trim().ToUpperInvariant();
		if (text != "NQ" && text != "MNQ" && text != "NNQ")
		{
			throw new InvalidOperationException("Use NQ, MNQ or NNQ; selected " + instrument.FullName + ".");
		}
		return (text == "NNQ") ? ("NQ" + instrument.FullName.Substring(instrument.MasterInstrument.Name.Length)) : instrument.FullName;
	}

	private Tuple<long, long> easternCache;

	private DateTime EasternExact(DateTime platform)
	{
		return TimeZoneInfo.ConvertTime(DateTime.SpecifyKind(platform, DateTimeKind.Unspecified), platformZone, easternZone);
	}

	// Called several times per tick during history; TimeZoneInfo.ConvertTime per tick made multi-month tick replays extremely slow.
	// The platform-to-Eastern offset is constant inside a 15-minute bucket unless the bucket contains a DST change, which falls back to exact conversion.
	private DateTime Eastern(DateTime platform)
	{
		const long bucketTicks = 15L * TimeSpan.TicksPerMinute;
		long ticks = platform.Ticks;
		long bucket = ticks / bucketTicks;
		Tuple<long, long> cache = easternCache;
		if (cache == null || cache.Item1 != bucket)
		{
			DateTime start = new DateTime(bucket * bucketTicks);
			DateTime last = new DateTime(bucket * bucketTicks + bucketTicks - 1);
			long first = EasternExact(start).Ticks - start.Ticks;
			if (first != EasternExact(last).Ticks - last.Ticks) return EasternExact(platform);
			cache = Tuple.Create(bucket, first);
			easternCache = cache;
		}
		return new DateTime(ticks + cache.Item2);
	}

	private DateTime Platform(DateTime ct)
	{
		return TimeZoneInfo.ConvertTime(DateTime.SpecifyKind(ct, DateTimeKind.Unspecified), easternZone, platformZone);
	}

	private static DateTime NativeNow()
	{
		return (Connection.PlaybackConnection != null) ? Connection.PlaybackConnection.Now : Globals.Now;
	}

	protected override void OnRender(ChartControl chartControl, ChartScale chartScale)
	{
		if (!VisualsSuppressed)
		{
			base.OnRender(chartControl, chartScale);
		}
		if (ShowVisuals)
		{
			EnableNativeExecutionDisplay();
		}
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
			if (!dashboardFaultLogged)
			{
				dashboardFaultLogged = true;
				Print("[Dashboard] Dashboard render unavailable: " + ex.Message);
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

	private System.Windows.Point DashboardPoint(ChartControl chart, System.Windows.Point point)
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
				System.Windows.Point point = DashboardPoint(chartControl, e.GetPosition(chartControl));
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
			System.Windows.Point point = DashboardPoint(chartControl, e.GetPosition(chartControl));
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

	private static int RecoveryStateRank(OrderState state)
	{
		if (state == OrderState.Filled || state == OrderState.Cancelled || state == OrderState.Rejected)
		{
			return 3;
		}
		if (state == OrderState.CancelPending || state == OrderState.CancelSubmitted)
		{
			return 2;
		}
		return (state != OrderState.Unknown) ? 1 : 0;
	}

	private static RecoverySnapshot SelectRecoverySnapshot(RecoverySnapshot prior, RecoverySnapshot candidate)
	{
		if (prior == null)
		{
			return candidate;
		}
		if (candidate.Filled < prior.Filled)
		{
			return prior;
		}
		if (candidate.Filled > prior.Filled)
		{
			return candidate;
		}
		int num = RecoveryStateRank(prior.State);
		int num2 = RecoveryStateRank(candidate.State);
		RecoverySnapshot recoverySnapshot = ((num2 > num || (num2 == num && candidate.Time >= prior.Time)) ? candidate : prior);
		if (recoverySnapshot.Error == ErrorCode.NoError)
		{
			RecoverySnapshot recoverySnapshot2 = ((recoverySnapshot == prior) ? candidate : prior);
			if (recoverySnapshot2.Error != ErrorCode.NoError)
			{
				recoverySnapshot.Error = recoverySnapshot2.Error;
				recoverySnapshot.Comment = recoverySnapshot2.Comment;
			}
		}
		return recoverySnapshot;
	}

	private void PrepareRecovery()
	{
		if (!IsInStrategyAnalyzer && Account != null && Connection.PlaybackConnection == null)
		{
			string text = ((Account.Connection == null) ? "" : (Account.Connection.Options.Name + "|" + Account.Connection.Options.Provider));
			recoveryIdentity = text + "|" + Account.Name + "|" + ExecutionInstrument.FullName + "|NQPrecision_ETH_M1_Tick_v2";
			string text2 = recoveryIdentity;
			char[] invalidFileNameChars = Path.GetInvalidFileNameChars();
			foreach (char oldChar in invalidFileNameChars)
			{
				text2 = text2.Replace(oldChar, '_');
			}
			recoveryPath = Path.Combine(Globals.UserDataDir, "NQPrecisionBot", "recovery", text2 + ".journal");
			recoveryPending = File.Exists(recoveryPath);
		}
	}

	private void StartRecovery()
	{
		if (recoveryPath == null || !ownsGuard)
		{
			return;
		}
		try
		{
			Directory.CreateDirectory(Path.GetDirectoryName(recoveryPath));
			recoveryLock = new FileStream(recoveryPath + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
		}
		catch (Exception ex)
		{
			RecoveryBlock("Another process owns this strategy recovery journal: " + ex.Message);
			return;
		}
		recoveryAccount = Account;
		recoveryAccount.OrderUpdate += RecoveryOrderUpdate;
		recoveryAccount.ExecutionUpdate += RecoveryExecutionUpdate;
		if (!recoveryPending)
		{
			recoveryReady = true;
			SaveRecovery();
			return;
		}
		try
		{
			using (BinaryReader binaryReader = new BinaryReader(File.OpenRead(recoveryPath)))
			{
				if (binaryReader.ReadString() != "NQPrecisionNT8.v3" || binaryReader.ReadString() != recoveryIdentity)
				{
					throw new InvalidDataException("Recovery account, connection, instrument or model mismatch");
				}
				owner = binaryReader.ReadString();
				sequence = binaryReader.ReadInt32();
				orders.Clear();
				processed.Clear();
				executions.Clear();
				recoveryRequests.Clear();
				suspended = binaryReader.ReadBoolean();
				closing = binaryReader.ReadBoolean();
				closeRejected = binaryReader.ReadBoolean();
				pendingCloseName = binaryReader.ReadString();
				if (pendingCloseName == "")
				{
					pendingCloseName = null;
				}
				pendingCloseQuantity = binaryReader.ReadInt32();
				pendingCloseExecuted = binaryReader.ReadInt32();
				pendingCloseFinal = binaryReader.ReadInt32();
				ownedNet = binaryReader.ReadInt32();
				entryName = binaryReader.ReadString();
				if (entryName == "")
				{
					entryName = null;
				}
				sessionDay = new DateTime(binaryReader.ReadInt64());
				entryCount = binaryReader.ReadInt32();
                decisionDay = new DateTime(binaryReader.ReadInt64());
                firstEntryTime = new DateTime(binaryReader.ReadInt64());
                tradeDeadline = new DateTime(binaryReader.ReadInt64());
				entered = binaryReader.ReadInt32();
				exited = binaryReader.ReadInt32();
				entryPending = binaryReader.ReadBoolean();
				entrySum = binaryReader.ReadDouble();
				exitSum = binaryReader.ReadDouble();
				plannedStop = binaryReader.ReadDouble();
				plannedTarget = binaryReader.ReadDouble();
				initialRisk = binaryReader.ReadDouble();
				actualFees = binaryReader.ReadDouble();
				recoveredCommissionFloor = binaryReader.ReadDouble();
				tradeModeledCost = binaryReader.ReadDouble();
				closeReason = binaryReader.ReadString();
				if (closeReason == "")
				{
					closeReason = null;
				}
				peakR = binaryReader.ReadDouble();
				brackets.Clear();
				int num = binaryReader.ReadInt32();
				if (num < 0 || num > 1000)
				{
					throw new InvalidDataException("Invalid bracket count");
				}
				for (int i = 0; i < num; i++)
				{
					brackets.Add(new Bracket
					{
						StopName = binaryReader.ReadString(),
						TargetName = binaryReader.ReadString()
					});
				}
				int num2 = binaryReader.ReadInt32();
				if (num2 < 0 || num2 > 100000)
				{
					throw new InvalidDataException("Invalid order count");
				}
				for (int j = 0; j < num2; j++)
				{
					RecoveryRequest recoveryRequest = new RecoveryRequest
					{
						Name = binaryReader.ReadString(),
						Id = binaryReader.ReadString(),
						Oco = binaryReader.ReadString(),
						Action = (OrderAction)binaryReader.ReadInt32(),
						Type = (OrderType)binaryReader.ReadInt32(),
						Quantity = binaryReader.ReadInt32(),
						Limit = binaryReader.ReadDouble(),
						Stop = binaryReader.ReadDouble(),
						Processed = binaryReader.ReadInt32(),
						Value = binaryReader.ReadDouble()
					};
					if (!recoveryRequest.Name.StartsWith(owner + "_", StringComparison.Ordinal) || recoveryRequest.Quantity < 1 || recoveryRequest.Processed < 0 || recoveryRequest.Processed > recoveryRequest.Quantity)
					{
						throw new InvalidDataException("Invalid owned order journal");
					}
					recoveryRequests.Add(recoveryRequest.Name, recoveryRequest);
					processed[recoveryRequest.Name] = recoveryRequest.Processed;
					lock (recoveredOrderNames)
					{
						recoveredOrderNames.Add(recoveryRequest.Name);
					}
				}
				num2 = binaryReader.ReadInt32();
				if (num2 < 0 || num2 > 1000000)
				{
					throw new InvalidDataException("Invalid execution count");
				}
				for (int k = 0; k < num2; k++)
				{
					executions.Add(binaryReader.ReadString());
				}
				if (binaryReader.BaseStream.Position != binaryReader.BaseStream.Length)
				{
					throw new InvalidDataException("Unexpected journal data");
				}
			}
			recoveredTrade = ownedNet != 0 || entryPending || closing;
			recoveryReady = true;
			if (!string.IsNullOrEmpty(closeReason) && closeReason.StartsWith("BrokerAccountRestricted:", StringComparison.Ordinal))
			{
				RecoveryBlock("Broker account restriction remains latched; verify broker account and owned protection: " + closeReason);
				return;
			}
			ReconcileRecovery();
		}
		catch (Exception ex2)
		{
			RecoveryBlock("Recovery journal could not be read: " + ex2.Message);
		}
	}

	private void RecoveryBlock(string reason)
	{
		recoveryFault = true;
		suspended = true;
		status = reason;
		Print(Name + ": " + reason);
		NinjaScript.Log(Name + ": " + reason, LogLevel.Error);
	}

	private void SaveRecovery(bool allowDuringReconciliation = false)
	{
		if (recoveryPath == null || recoveryLock == null || !recoveryReady || recoveryFault || (reconcilingRecovery && !allowDuringReconciliation) || (State != State.Realtime && State != State.Terminated))
		{
			return;
		}
		try
		{
			Directory.CreateDirectory(Path.GetDirectoryName(recoveryPath));
			string text = recoveryPath + ".tmp";
			using (FileStream fileStream = new FileStream(text, FileMode.Create, FileAccess.Write, FileShare.None))
			{
				using BinaryWriter binaryWriter = new BinaryWriter(fileStream);
				binaryWriter.Write("NQPrecisionNT8.v3");
				binaryWriter.Write(recoveryIdentity);
				binaryWriter.Write(owner);
				binaryWriter.Write(sequence);
				binaryWriter.Write(suspended);
				binaryWriter.Write(closing);
				binaryWriter.Write(closeRejected);
				binaryWriter.Write(pendingCloseName ?? "");
				binaryWriter.Write(pendingCloseQuantity);
				binaryWriter.Write(pendingCloseExecuted);
				binaryWriter.Write(pendingCloseFinal);
				binaryWriter.Write(ownedNet);
				binaryWriter.Write(entryName ?? "");
				binaryWriter.Write(sessionDay.Ticks);
				binaryWriter.Write(entryCount);
                binaryWriter.Write(decisionDay.Ticks);
                binaryWriter.Write(firstEntryTime.Ticks);
                binaryWriter.Write(tradeDeadline.Ticks);
				binaryWriter.Write(entered);
				binaryWriter.Write(exited);
				binaryWriter.Write(entryPending);
				binaryWriter.Write(entrySum);
				binaryWriter.Write(exitSum);
				binaryWriter.Write(plannedStop);
				binaryWriter.Write(plannedTarget);
				binaryWriter.Write(initialRisk);
				binaryWriter.Write(actualFees);
				binaryWriter.Write(recoveredCommissionFloor);
				binaryWriter.Write(tradeModeledCost);
				binaryWriter.Write(closeReason ?? "");
				binaryWriter.Write(peakR);
				binaryWriter.Write(brackets.Count);
				foreach (Bracket bracket in brackets)
				{
					binaryWriter.Write(bracket.StopName);
					binaryWriter.Write(bracket.TargetName);
				}
				binaryWriter.Write(recoveryRequests.Count);
				foreach (RecoveryRequest value2 in recoveryRequests.Values)
				{
					processed.TryGetValue(value2.Name, out var value);
					value2.Processed = value;
					binaryWriter.Write(value2.Name);
					binaryWriter.Write(value2.Id ?? "");
					binaryWriter.Write(value2.Oco ?? "");
					binaryWriter.Write((int)value2.Action);
					binaryWriter.Write((int)value2.Type);
					binaryWriter.Write(value2.Quantity);
					binaryWriter.Write(value2.Limit);
					binaryWriter.Write(value2.Stop);
					binaryWriter.Write(value2.Processed);
					binaryWriter.Write(value2.Value);
				}
				binaryWriter.Write(executions.Count);
				foreach (string execution in executions)
				{
					binaryWriter.Write(execution);
				}
				binaryWriter.Flush();
				fileStream.Flush(flushToDisk: true);
			}
			if (File.Exists(recoveryPath))
			{
				File.Replace(text, recoveryPath, recoveryPath + ".bak");
			}
			else
			{
				File.Move(text, recoveryPath);
			}
		}
		catch (Exception ex)
		{
			RecoveryBlock("Durable recovery write failed; new orders blocked: " + ex.Message);
		}
	}

	private string RecoveryCaseId()
	{
		using MemoryStream memoryStream = new MemoryStream();
		using BinaryWriter binaryWriter = new BinaryWriter(memoryStream);
		binaryWriter.Write(recoveryIdentity ?? "");
		binaryWriter.Write(owner ?? "");
		binaryWriter.Write(entryName ?? "");
		binaryWriter.Write(sequence);
		binaryWriter.Write(ownedNet);
		foreach (RecoveryRequest item in recoveryRequests.Values.OrderBy((RecoveryRequest r) => r.Name, StringComparer.Ordinal))
		{
			processed.TryGetValue(item.Name, out var value);
			binaryWriter.Write(item.Name);
			binaryWriter.Write(item.Id ?? "");
			binaryWriter.Write(item.Quantity);
			binaryWriter.Write(value);
			binaryWriter.Write(item.Value);
		}
		binaryWriter.Flush();
		using SHA256 sHA = SHA256.Create();
		return BitConverter.ToString(sHA.ComputeHash(memoryStream.ToArray())).Replace("-", "").Substring(0, 32);
	}

	private bool RefuseExternalSettlement(string reason)
	{
		if (externalRecoveryRefusalReported != reason)
		{
			externalRecoveryRefusalReported = reason;
			Print(Name + ": external settlement refused: " + reason);
		}
		return false;
	}

	private bool TryConfirmExternalSettlement(Order[] brokerOrders)
	{
		if (State != State.Realtime || IsInStrategyAnalyzer || !recoveryReady || recoveryFault || recoveryLock == null || !recoveryPending || ownedNet == 0 || string.IsNullOrEmpty(entryName))
		{
			return false;
		}
		string text = RecoveryCaseId();
		string text2 = "CLOSED " + text + " NO_ORDERS";
		if (externalRecoveryCaseReported != text)
		{
			externalRecoveryCaseReported = text;
			externalRecoveryRefusalReported = null;
			Print(Name + ": RECOVERY_CASE " + text + " | " + recoveryIdentity + " | entry=" + entryName + " | owned=" + ownedNet + " | Automatic reconciliation continues; new orders stay paused until exact owned broker evidence arrives.");
		}
		if (string.IsNullOrWhiteSpace(ExternalCloseConfirmation))
		{
			return false;
		}
		if (!string.Equals(ExternalCloseConfirmation.Trim(), text2, StringComparison.Ordinal))
		{
			return RefuseExternalSettlement("confirmation belongs to a different recovery case");
		}
		if (EnableTrading)
		{
			return RefuseExternalSettlement("disable Enable new trades before confirming");
		}
		if (Account == null || Account.ConnectionStatus != ConnectionStatus.Connected)
		{
			return RefuseExternalSettlement("account must be connected");
		}
		lock (Account.Positions)
		{
			if (Account.Positions.Any((Position p) => p.Instrument.FullName == ExecutionInstrument.FullName && p.Quantity != 0))
			{
				return RefuseExternalSettlement("contract still has a non-flat account position");
			}
		}
		processed.TryGetValue(entryName, out var value);
		if (!recoveryRequests.TryGetValue(entryName, out var value2) || value != value2.Quantity)
		{
			return RefuseExternalSettlement("entry quantity is not fully reconciled");
		}
		foreach (Order order in brokerOrders)
		{
			if (order.Name != null && recoveryRequests.ContainsKey(order.Name) && order.OrderState != OrderState.Unknown && !Settled(order))
			{
				return RefuseExternalSettlement("an owned order still has an active broker state: " + order.Name);
			}
		}
		try
		{
			SaveRecovery(allowDuringReconciliation: true);
			if (recoveryFault)
			{
				return true;
			}
			string text3 = owner;
			string text4 = owner.Substring(0, owner.LastIndexOf('_') + 1) + Guid.NewGuid().ToString("N").Substring(0, 12);
			string text5 = Path.Combine(Path.GetDirectoryName(recoveryPath), "settlements");
			Directory.CreateDirectory(text5);
			string text6 = Path.Combine(text5, text + "-" + Guid.NewGuid().ToString("N").Substring(0, 8));
			byte[] array = File.ReadAllBytes(recoveryPath);
			using (FileStream fileStream = new FileStream(text6 + ".before", FileMode.CreateNew, FileAccess.Write, FileShare.None))
			{
				fileStream.Write(array, 0, array.Length);
				fileStream.Flush(flushToDisk: true);
			}
			string s = "Operator-confirmed external closure\r\nUTC=" + DateTime.UtcNow.ToString("o") + "\r\nIdentity=" + recoveryIdentity + "\r\nEntry=" + entryName + "\r\nOwnedQuantity=" + ownedNet + "\r\nConfirmation=" + text2 + "\r\nPreviousOwner=" + text3 + "\r\nNextOwner=" + text4 + "\r\nBroker facts attested by operator: owned trade fully closed; all its orders inactive.\r\nNative exit ID, exit price and PnL were not reconstructed. Existing execution IDs remain unchanged.\r\nReceipt precedes checkpoint commit; the journal owner establishes whether commit completed.\r\n";
			byte[] bytes = Encoding.UTF8.GetBytes(s);
			using (FileStream fileStream2 = new FileStream(text6 + ".confirmation.txt", FileMode.CreateNew, FileAccess.Write, FileShare.None))
			{
				fileStream2.Write(bytes, 0, bytes.Length);
				fileStream2.Flush(flushToDisk: true);
			}
			owner = text4;
			ownedNet = 0;
			entryName = null;
			closing = false;
			closeRejected = false;
			pendingCloseName = null;
			pendingCloseQuantity = 0;
			pendingCloseExecuted = 0;
			pendingCloseFinal = -1;
			orders.Clear();
			processed.Clear();
			reportedFilled.Clear();
			recoveryRequests.Clear();
			recoverySnapshots.Clear();
			lock (recoveredOrderNames)
			{
				recoveredOrderNames.Clear();
			}
			entered = 0;
			exited = 0;
			entrySum = 0.0;
			exitSum = 0.0;
			entryPending = false;
			closeReason = null;
			brackets.Clear();
			executionVisual = null;
			recoveredTrade = true;
			connectionPaused = true;
			SaveRecovery(allowDuringReconciliation: true);
			if (recoveryFault)
			{
				return true;
			}
			recoveryPending = false;
			ReleaseExposure(text3);
			status = "External close confirmed; new entries disabled";
			Print(Name + ": EXTERNAL_SETTLEMENT_COMMITTED case=" + text + "; backup=" + text6 + ".before; owned position flat; no broker orders submitted/cancelled; keep the confirmation receipt.");
			return true;
		}
		catch (Exception ex)
		{
			RecoveryBlock("External settlement could not be committed; review journal and backup: " + ex.Message);
			return true;
		}
	}

	private bool RecoveryTracksOrder(string name)
	{
		if (name == null)
		{
			return false;
		}
		lock (recoveredOrderNames)
		{
			return recoveredOrderNames.Contains(name);
		}
	}

	private void WaitForRecoveryEvidence()
	{
		recoveryPending = true;
		if (status != "Recovery pending: awaiting broker evidence")
		{
			status = "Recovery pending: awaiting broker evidence";
			Print(Name + ": Recovery pending: awaiting broker evidence");
		}
		SaveRecovery();
	}

	private void StopRecovery()
	{
		SaveRecovery();
		if (recoveryAccount != null)
		{
			recoveryAccount.OrderUpdate -= RecoveryOrderUpdate;
			recoveryAccount.ExecutionUpdate -= RecoveryExecutionUpdate;
			recoveryAccount = null;
		}
		if (recoveryLock != null)
		{
			recoveryLock.Dispose();
			recoveryLock = null;
		}
	}

	private void RememberOrder(Order order, int quantity, double limit, double stop)
	{
		if (State == State.Realtime && order != null)
		{
			if (!recoveryRequests.TryGetValue(order.Name, out var value))
			{
				Dictionary<string, RecoveryRequest> dictionary = recoveryRequests;
				string name = order.Name;
				RecoveryRequest recoveryRequest = new RecoveryRequest
				{
					Name = order.Name,
					Action = order.OrderAction,
					Type = order.OrderType,
					Oco = order.Oco
				};
				value = recoveryRequest;
				dictionary[name] = recoveryRequest;
			}
			value.Id = order.OrderId ?? "";
			value.Quantity = quantity;
			value.Limit = limit;
			value.Stop = stop;
			// This exact object is observed only through our submission/verified recovery path.
			if (order.Name != entryName)
				ProductExposure.ObserveExit(order);
		}
	}

	private void RememberExecution(Order order, int quantity, double price)
	{
		if (State == State.Realtime && recoveryRequests.TryGetValue(order.Name, out var value))
		{
			value.Value += (double)quantity * price;
		}
	}

	private bool RecoveryPositionConsistent()
	{
		if (State != State.Realtime || ownedNet == 0)
		{
			return true;
		}
		Position position;
		lock (Account.Positions)
		{
			position = Account.Positions.FirstOrDefault((Position p) => p.Instrument.FullName == ExecutionInstrument.FullName && p.Quantity != 0);
		}
		int value = ((position != null) ? (((position.MarketPosition == MarketPosition.Long) ? 1 : (-1)) * position.Quantity) : 0);
		return Math.Sign(value) == Math.Sign(ownedNet) && Math.Abs(value) >= Math.Abs(ownedNet);
	}

	private void CancelOppositeOwnedProtection()
	{
		if (Account == null || Account.ConnectionStatus != ConnectionStatus.Connected || ownedNet == 0)
		{
			return;
		}
		Position position;
		lock (Account.Positions)
		{
			position = Account.Positions.FirstOrDefault((Position p) => p.Instrument.FullName == ExecutionInstrument.FullName && p.Quantity != 0);
		}
		if (position == null)
		{
			return;
		}
		int value = ((position.MarketPosition == MarketPosition.Long) ? position.Quantity : (-position.Quantity));
		if (Math.Sign(value) == Math.Sign(ownedNet))
		{
			return;
		}
		Order[] array = orders.Values.ToArray();
		foreach (Order order in array)
		{
			if (recoveryRequests.TryGetValue(order.Name, out var value2) && !Settled(order) && order.OrderType != OrderType.Market && order.OrderState != OrderState.CancelPending && order.OrderState != OrderState.CancelSubmitted && !(order.Instrument.FullName != ExecutionInstrument.FullName) && (string.IsNullOrEmpty(value2.Id) || !(value2.Id != order.OrderId)))
			{
				try
				{
					Account.Cancel(new Order[1] { order });
				}
				catch (Exception ex)
				{
					Print(Name + " could not cancel incompatible owned protection: " + ex.Message);
				}
			}
		}
	}

	private bool RefreshOwnedProviderIdentity(Order order, int quantity, double limit, double stop)
	{
		if (!recoveryRequests.TryGetValue(order.Name, out var value) || !orders.TryGetValue(order.Name, out var value2) || value2 != order)
		{
			return true;
		}
		if (order.Account != Account || order.Instrument.FullName != ExecutionInstrument.FullName || !SameBrokerAction(order.OrderAction.ToString(), value.Action.ToString()) || order.OrderType != value.Type || order.Oco != (value.Oco ?? ""))
		{
			RecoveryBlock(RecoveryIdentityError(order, value));
			return false;
		}
		if (!string.IsNullOrEmpty(value.Id) && value.Id != order.OrderId && !Guid.TryParseExact(value.Id, "N", out var _))
		{
			RecoveryBlock(RecoveryIdentityError(order, value));
			return false;
		}
		RememberOrder(order, quantity, limit, stop);
		SaveRecovery(allowDuringReconciliation: true);
		return !recoveryFault;
	}

	private void UpgradeProvisionalProtectionIds(List<Order> observed)
	{
		Dictionary<RecoveryRequest, string> dictionary = new Dictionary<RecoveryRequest, string>();
		foreach (RecoveryRequest request in recoveryRequests.Values)
		{
			if (string.IsNullOrEmpty(request.Id) || !Guid.TryParseExact(request.Id, "N", out var temporary) || string.IsNullOrEmpty(request.Oco) || (request.Type != OrderType.StopMarket && request.Type != OrderType.Limit) || !request.Name.StartsWith(owner + "_", StringComparison.Ordinal))
			{
				continue;
			}
			List<Order> source = observed.Where((Order o) => o != null && o.Name == request.Name && o.Account == Account && o.Instrument.FullName == ExecutionInstrument.FullName).ToList();
			List<Order> source2 = source.Where((Order o) => o.OrderState != OrderState.Initialized && o.OrderState != OrderState.Unknown && !string.IsNullOrEmpty(o.OrderId) && !Guid.TryParseExact(o.OrderId, "N", out temporary)).ToList();
			List<string> list = source2.Select((Order o) => o.OrderId).Distinct(StringComparer.Ordinal).ToList();
			if (list.Count != 0)
			{
				if (list.Count != 1)
				{
					throw new InvalidDataException("Multiple assigned broker IDs for provisional owned protection: " + request.Name);
				}
				Order candidate = source2.OrderByDescending((Order o) => o.Filled).First();
				if (source.Any((Order o) => !string.IsNullOrEmpty(o.OrderId) && o.OrderId != request.Id && o.OrderId != candidate.OrderId) || !SameBrokerAction(request.Action.ToString(), candidate.OrderAction.ToString()) || candidate.OrderType != request.Type || candidate.Oco != request.Oco || candidate.Quantity != request.Quantity || candidate.LimitPrice != request.Limit || candidate.StopPrice != request.Stop || candidate.Filled < request.Processed || candidate.Filled > request.Quantity)
				{
					throw new InvalidDataException(RecoveryIdentityError(candidate, request));
				}
				dictionary.Add(request, candidate.OrderId);
			}
		}
		if (dictionary.Count == 0)
		{
			return;
		}
		if (!string.IsNullOrEmpty(recoveryPath) && File.Exists(recoveryPath))
		{
			File.Copy(recoveryPath, recoveryPath + ".before_provider_id_" + DateTime.UtcNow.Ticks, overwrite: false);
		}
		foreach (KeyValuePair<RecoveryRequest, string> item in dictionary)
		{
			item.Key.Id = item.Value;
		}
		SaveRecovery(allowDuringReconciliation: true);
		if (recoveryFault)
		{
			throw new InvalidDataException("Assigned broker IDs could not be saved durably.");
		}
		foreach (KeyValuePair<RecoveryRequest, string> item2 in dictionary)
		{
			NinjaScript.Log(Name + ": RECOVERY_PROVIDER_ID_BOUND " + item2.Key.Name + " id=" + item2.Value, LogLevel.Information);
		}
	}

	private string RecoveryIdentityError(Order order, RecoveryRequest request)
	{
		return "Broker order identity differs from owned journal: " + request.Name + " | expected: instrument=" + ExecutionInstrument.FullName + ", id=" + request.Id + ", action=" + request.Action.ToString() + ", type=" + request.Type.ToString() + ", OCO=" + request.Oco + " | observed: instrument=" + order.Instrument.FullName + ", id=" + order.OrderId + ", action=" + order.OrderAction.ToString() + ", type=" + order.OrderType.ToString() + ", OCO=" + order.Oco;
	}

	private static bool SameBrokerAction(string expected, string observed)
	{
		return ((expected == "Buy" || expected == "BuyToCover") && (observed == "Buy" || observed == "BuyToCover")) || ((expected == "Sell" || expected == "SellShort") && (observed == "Sell" || observed == "SellShort"));
	}

	private Order[] RecoveryBrokerOrders()
	{
		List<Order> list = new List<Order>();
		lock (Account.Orders)
		{
			list.AddRange(Account.Orders);
		}
		lock (Account.Executions)
		{
			foreach (Execution execution in Account.Executions)
			{
				if (execution != null && execution.Order != null)
				{
					list.Add(execution.Order);
				}
			}
		}
		UpgradeProvisionalProtectionIds(list);
		Dictionary<string, Order> dictionary = new Dictionary<string, Order>();
		foreach (Order item in list)
		{
			if (item == null || item.Name == null || !recoveryRequests.TryGetValue(item.Name, out var value))
			{
				continue;
			}
			if (item.Instrument.FullName != ExecutionInstrument.FullName || !SameBrokerAction(item.OrderAction.ToString(), value.Action.ToString()) || item.OrderType != value.Type || (!string.IsNullOrEmpty(value.Id) && value.Id != item.OrderId) || item.Oco != (value.Oco ?? ""))
			{
				throw new InvalidDataException(RecoveryIdentityError(item, value));
			}
			if (!dictionary.TryGetValue(item.Name, out var value2))
			{
				dictionary[item.Name] = item;
				continue;
			}
			if (!string.IsNullOrEmpty(value2.OrderId) && !string.IsNullOrEmpty(item.OrderId) && value2.OrderId != item.OrderId)
			{
				throw new InvalidDataException("Multiple broker IDs for owned order: " + value.Name);
			}
			bool flag = item.OrderState == OrderState.Filled || item.OrderState == OrderState.Cancelled || item.OrderState == OrderState.Rejected;
			bool flag2 = value2.OrderState == OrderState.Filled || value2.OrderState == OrderState.Cancelled || value2.OrderState == OrderState.Rejected;
			if (item.Filled > value2.Filled || (item.Filled == value2.Filled && ((value2.OrderState == OrderState.Unknown && item.OrderState != OrderState.Unknown) || (string.IsNullOrEmpty(value2.OrderId) && !string.IsNullOrEmpty(item.OrderId)) || (flag && !flag2))))
			{
				dictionary[item.Name] = item;
			}
		}
		return dictionary.Values.ToArray();
	}

	private bool ResumeTechnicalProtectionClose()
	{
		if (!closing || closeReason != "ProtectionCancelled")
		{
			return true;
		}
		if (State != State.Realtime || ownedNet == 0 || recoveryFault || closeRejected || !string.IsNullOrEmpty(pendingCloseName) || pendingCloseQuantity != 0 || pendingCloseExecuted != 0 || pendingCloseFinal > 0 || exited != 0 || entered != Math.Abs(ownedNet) || !RecoveryPositionConsistent() || orders.Values.Any((Order o) => !ExecutionsCaughtUp(o)))
		{
			WaitForRecoveryEvidence();
			return false;
		}
		closing = false;
		closeReason = null;
		suspended = false;
		SaveRecovery(allowDuringReconciliation: true);
		if (recoveryFault)
		{
			return false;
		}
		Print(Name + ": TECHNICAL_PROTECTION_CLOSE_RESUMED reason=ProtectionCancelled; verified owned quantity=" + ownedNet);
		return true;
	}

	private void ReconcileRecovery()
	{
		if (!recoveryPending || recoveryFault || reconcilingRecovery || Account == null || Account.ConnectionStatus != ConnectionStatus.Connected)
		{
			return;
		}
		reconcilingRecovery = true;
		try
		{
			bool flag = false;
			Order[] array = RecoveryBrokerOrders();
			Order[] array2 = array;
			foreach (Order order in array2)
			{
				if (order.Name == null || !recoveryRequests.TryGetValue(order.Name, out var value))
				{
					continue;
				}
				if (order.Instrument.FullName != ExecutionInstrument.FullName || !SameBrokerAction(order.OrderAction.ToString(), value.Action.ToString()) || order.OrderType != value.Type || (!string.IsNullOrEmpty(value.Id) && value.Id != order.OrderId) || order.Oco != (value.Oco ?? ""))
				{
					throw new InvalidDataException(RecoveryIdentityError(order, value));
				}
				if (order.OrderState == OrderState.Unknown)
				{
					flag = true;
					continue;
				}
				recoverySnapshots.TryGetValue(order.Name, out var value2);
				value2 = SelectRecoverySnapshot(value2, new RecoverySnapshot
				{
					Quantity = order.Quantity,
					Filled = order.Filled,
					Limit = order.LimitPrice,
					Stop = order.StopPrice,
					Average = order.AverageFillPrice,
					State = order.OrderState,
					Time = order.Time,
					Error = ErrorCode.NoError,
					Comment = ""
				});
				recoverySnapshots[order.Name] = value2;
				lock (recoveredOrderNames)
				{
					recoveredOrderNames.Add(order.Name);
				}
				RememberOrder(order, value2.Quantity, value2.Limit, value2.Stop);
				orders[order.Name] = order;
				reportedFilled.TryGetValue(order.Name, out var value3);
				reportedFilled[order.Name] = Math.Max(value3, value2.Filled);
				foreach (Bracket bracket in brackets)
				{
					if (order.Name == bracket.StopName)
					{
						bracket.Stop = order;
					}
					if (order.Name == bracket.TargetName)
					{
						bracket.Target = order;
					}
				}
				processed.TryGetValue(order.Name, out var value4);
				if (value2.Filled < value4)
				{
					throw new InvalidDataException("Broker filled quantity regressed: " + order.Name);
				}
				if (value2.Filled > value4)
				{
					int num = value2.Filled - value4;
					double num2 = (value2.Average * (double)value2.Filled - value.Value) / (double)num;
					if (double.IsNaN(num2) || double.IsInfinity(num2) || num2 <= 0.0)
					{
						throw new InvalidDataException("Invalid recovered fill price");
					}
					Execution execution = new Execution
					{
						Account = Account,
						Instrument = order.Instrument,
						Order = order,
						Price = num2,
						Quantity = num,
						Time = value2.Time,
						ExecutionId = "RECOVERY_" + order.OrderId + "_" + value2.Filled,
						Commission = 0.0
					};
					applyingRecoveryExecution = execution.ExecutionId;
					try
					{
						OnExecutionUpdate(execution, execution.ExecutionId, num2, num, MarketPosition.Flat, order.OrderId, value2.Time);
					}
					finally
					{
						applyingRecoveryExecution = null;
					}
				}
				OnOrderUpdate(order, value2.Limit, value2.Stop, value2.Quantity, value2.Filled, value2.Average, value2.State, value2.Time, value2.Error, value2.Comment);
			}
			if (!flag && entryName != null && recoveryRequests.TryGetValue(entryName, out var value5) && value5.Processed < value5.Quantity && !orders.ContainsKey(entryName))
			{
				throw new InvalidDataException("Pending entry was not returned by broker; submission outcome is unknown");
			}
			bool flag2 = ownedNet != 0 && !RecoveryPositionConsistent();
			if (flag | flag2)
			{
				if (!TryConfirmExternalSettlement(array))
				{
					if (flag2)
					{
						CancelOppositeOwnedProtection();
					}
					recoveryPending = true;
					string text = (flag ? "Recovery pending: order status" : "Recovery pending: owned fills");
					if (status != text)
					{
						status = text;
						Print(Name + ": " + text + "; saved owned quantity=" + ownedNet);
					}
				}
				return;
			}
			if (!ResumeTechnicalProtectionClose())
			{
				return;
			}
			recoveryPending = false;
			if (recoveryFault)
			{
				return;
			}
			status = ((ownedNet == 0) ? "Recovered owned state; waiting for fresh signal" : "Recovered owned position and broker protection");
		}
		catch (Exception ex)
		{
			CancelOppositeOwnedProtection();
			RecoveryBlock("Broker recovery blocked: " + ex.Message);
		}
		finally
		{
			reconcilingRecovery = false;
			SaveRecovery();
		}
		if (recoveryFault || recoveryPending)
		{
			return;
		}
		if (ownedNet == 0)
		{
			Order[] array3 = orders.Values.ToArray();
			foreach (Order order2 in array3)
			{
				if (order2.OrderType != OrderType.Market && !Settled(order2))
				{
					RecoveryCancel(order2);
				}
			}
		}
		else if (closing && !closeRejected)
		{
			DriveClose();
		}
		else
		{
			RepairOwnedProtection();
		}
	}

	private bool ReadyForProtectionRepair(Order stopOrder, Order targetOrder, string stopName, string targetName)
	{
		if ((stopOrder == null && recoveryRequests.ContainsKey(stopName)) || (targetOrder == null && recoveryRequests.ContainsKey(targetName)) || new Order[2] { stopOrder, targetOrder }.Any((Order o) => o != null && (o.OrderState == OrderState.Unknown || o.OrderState == OrderState.CancelPending || o.OrderState == OrderState.CancelSubmitted)))
		{
			WaitForRecoveryEvidence();
			return false;
		}
		if (Settled(stopOrder) != Settled(targetOrder))
		{
			WaitForRecoveryEvidence();
			return false;
		}
		return true;
	}

	private bool RepairOwnedProtection()
	{
		if (repairingProtection || !BrokerReady() || recoveryFault || (closing && !closeRejected))
		{
			return false;
		}
		if (ownedNet == 0)
		{
			return true;
		}
		if (!RecoveryPositionConsistent() || orders.Values.Any((Order o) => !ExecutionsCaughtUp(o)))
		{
			WaitForRecoveryEvidence();
			return false;
		}
		repairingProtection = true;
		try
		{
			int num = Math.Abs(ownedNet);
			int num2 = Math.Sign(ownedNet);
			if (brackets.Count == 0)
			{
				List<Bracket> list = brackets;
				Bracket bracket = new Bracket();
				string text = owner;
				int num3 = ++sequence;
				bracket.StopName = text + "_RecoveredStop_" + num3;
				bracket.TargetName = owner + "_RecoveredTarget_" + sequence;
				list.Add(bracket);
			}
			foreach (Bracket bracket2 in brackets)
			{
				int num4 = (recoveryRequests.TryGetValue(bracket2.StopName, out var value) ? value.Quantity : num);
				int num5 = ((bracket2.Stop != null) ? bracket2.Stop.Filled : 0) + ((bracket2.Target != null) ? bracket2.Target.Filled : 0);
				int num6 = Math.Min(num, Math.Max(0, num4 - num5));
				if (num6 <= 0)
				{
					continue;
				}
				num -= num6;
				if (!Settled(bracket2.Stop) && bracket2.Stop.Quantity - bracket2.Stop.Filled != num6)
				{
					if (bracket2.Stop.Quantity - bracket2.Stop.Filled > num6)
					{
						RecoveryCancel(bracket2.Stop);
					}
					throw new InvalidDataException("Owned working stop quantity differs from remaining bracket");
				}
				if (!Settled(bracket2.Target) && bracket2.Target.Quantity - bracket2.Target.Filled != num6)
				{
					if (bracket2.Target.Quantity - bracket2.Target.Filled > num6)
					{
						RecoveryCancel(bracket2.Target);
					}
					throw new InvalidDataException("Owned working target quantity differs from remaining bracket");
				}
				if (!ReadyForProtectionRepair(bracket2.Stop, bracket2.Target, bracket2.StopName, bracket2.TargetName))
				{
					return false;
				}
				if (Settled(bracket2.Stop) || Settled(bracket2.Target))
				{
					double num7 = value?.Stop ?? plannedStop;
					double num8 = ((num2 > 0) ? GetCurrentBid(executionSeries) : GetCurrentAsk(executionSeries));
					if (num8 <= 0.0 || (double)num2 * (num8 - num7) <= 0.0 || (double)num2 * (plannedTarget - num8) <= 0.0)
					{
						throw new InvalidDataException("Missing protection cannot be restored at crossed or unavailable market levels");
					}
					string oco = owner + "_RepairOco_" + ++sequence;
					if (Settled(bracket2.Stop))
					{
						string text2 = owner;
						int num3 = ++sequence;
						bracket2.StopName = text2 + "_RepairStop_" + num3;
						bracket2.Stop = RecoverySubmit(executionSeries, (num2 <= 0) ? OrderAction.BuyToCover : OrderAction.Sell, OrderType.StopMarket, num6, 0.0, num7, oco, bracket2.StopName);
					}
					if (bracket2.Stop == null || bracket2.Stop.OrderState == OrderState.Rejected)
					{
						throw new InvalidDataException("Recovered owned stop was not accepted");
					}
					if (Settled(bracket2.Target))
					{
						string text3 = owner;
						int num3 = ++sequence;
						bracket2.TargetName = text3 + "_RepairTarget_" + num3;
						bracket2.Target = RecoverySubmit(executionSeries, (num2 <= 0) ? OrderAction.BuyToCover : OrderAction.Sell, OrderType.Limit, num6, plannedTarget, 0.0, oco, bracket2.TargetName);
					}
				}
			}
			if (num != 0)
			{
				throw new InvalidDataException("Remaining owned exposure has no journalled bracket");
			}
			SaveRecovery();
			return true;
		}
		catch (Exception ex)
		{
			RecoveryBlock("Owned protection requires attention: " + ex.Message);
			return false;
		}
		finally
		{
			repairingProtection = false;
		}
	}

	private void RecoveryOrderUpdate(object sender, OrderEventArgs args)
	{
		Order order = args.Order;
		if (order == null || order.Name == null || !RecoveryTracksOrder(order.Name))
		{
			return;
		}
		double limit = args.LimitPrice;
		double stop = args.StopPrice;
		double average = args.AverageFillPrice;
		int quantity = args.Quantity;
		int filled = args.Filled;
		OrderState state = args.OrderState;
		DateTime time = args.Time;
		ErrorCode error = args.Error;
		string comment = args.Comment;
		TriggerCustomEvent((object ignored) =>
		{
			if (State == State.Realtime && !recoveryFault && RecoveryTracksOrder(order.Name) && RefreshOwnedProviderIdentity(order, quantity, limit, stop))
			{
				recoverySnapshots.TryGetValue(order.Name, out var value);
				RecoverySnapshot prior = SelectRecoverySnapshot(value, new RecoverySnapshot
				{
					Quantity = quantity,
					Filled = filled,
					Limit = limit,
					Stop = stop,
					Average = average,
					State = state,
					Time = time,
					Error = error,
					Comment = comment
				});
				recoverySnapshots[order.Name] = SelectRecoverySnapshot(prior, new RecoverySnapshot
				{
					Quantity = order.Quantity,
					Filled = order.Filled,
					Limit = order.LimitPrice,
					Stop = order.StopPrice,
					Average = order.AverageFillPrice,
					State = order.OrderState,
					Time = order.Time,
					Error = ErrorCode.NoError,
					Comment = ""
				});
				recoveryPending = true;
				ReconcileRecovery();
			}
		}, null);
	}

	private bool ReconcileOwnedExecution(Execution execution, string executionId)
	{
		if (State != State.Realtime || execution == null || execution.Order == null || executionId == applyingRecoveryExecution)
		{
			return false;
		}
		lock (recoveredOrderNames)
		{
			if (!recoveredOrderNames.Contains(execution.Order.Name))
			{
				return false;
			}
		}
		recoveryPending = true;
		ReconcileRecovery();
		return true;
	}

	private void RecoveryExecutionUpdate(object sender, ExecutionEventArgs args)
	{
		Execution execution = args.Execution;
		if (execution == null || execution.Order == null || execution.Order.Name == null || !RecoveryTracksOrder(execution.Order.Name))
		{
			return;
		}
		string executionId = args.ExecutionId;
		string orderId = args.OrderId;
		double price = args.Price;
		int quantity = args.Quantity;
		DateTime time = args.Time;
		MarketPosition marketPosition = args.MarketPosition;
		TriggerCustomEvent((object ignored) =>
		{
			if (State == State.Realtime && !recoveryFault && RecoveryTracksOrder(execution.Order.Name))
			{
				recoveryPending = true;
				ReconcileRecovery();
			}
		}, null);
	}

	private Order RecoverySubmit(int series, OrderAction action, OrderType type, int quantity, double limit, double stop, string oco, string name)
	{
		if (State == State.Historical)
		{
			return SubmitOrderUnmanaged(series, action, type, quantity, limit, stop, oco, name);
		}
		if (!BrokerReady() || recoveryFault)
		{
			return null;
		}
		recoveryRequests[name] = new RecoveryRequest
		{
			Name = name,
			Id = "",
			Oco = oco,
			Action = action,
			Type = type,
			Quantity = quantity,
			Limit = limit,
			Stop = stop
		};
		SaveRecovery();
		if (recoveryFault)
		{
			return null;
		}
		Order order;
		if (recoveredTrade)
		{
			order = Account.CreateOrder(ExecutionInstrument, action, type, OrderEntry.Automated, TimeInForce.Gtc, quantity, limit, stop, oco, name, DateTime.MaxValue, null);
			lock (recoveredOrderNames)
			{
				recoveredOrderNames.Add(name);
			}
			orders[name] = order;
			RememberOrder(order, quantity, limit, stop);
			SaveRecovery();
			if (!recoveryFault)
			{
				Account.Submit(new Order[1] { order });
			}
		}
		else
		{
			order = SubmitOrderUnmanaged(series, action, type, quantity, limit, stop, oco, name);
		}
		if (order != null)
		{
			RememberOrder(order, quantity, limit, stop);
		}
		SaveRecovery();
		return order;
	}

	private void RecoveryCancel(Order order)
	{
		if (!BrokerReady() || order == null || recoveryFault)
		{
			return;
		}
		SaveRecovery();
		if (!recoveryFault)
		{
			if (recoveredOrderNames.Contains(order.Name))
			{
				Account.Cancel(new Order[1] { order });
			}
			else
			{
				CancelOrder(order);
			}
		}
	}

	private void RecoveryChange(Order order, int quantity, double limit, double stop)
	{
		if (!BrokerReady() || order == null || recoveryFault)
		{
			return;
		}
		RememberOrder(order, quantity, limit, stop);
		SaveRecovery();
		if (!recoveryFault)
		{
			if (recoveredOrderNames.Contains(order.Name))
			{
				order.QuantityChanged = quantity;
				order.LimitPriceChanged = limit;
				order.StopPriceChanged = stop;
				Account.Change(new Order[1] { order });
			}
			else
			{
				ChangeOrder(order, quantity, limit, stop);
			}
		}
	}

	private bool BrokerReady()
	{
		return State == State.Historical || (State == State.Realtime && !reconcilingRecovery && !recoveryPending && !recoveryFault && Account != null && Account.ConnectionStatus == ConnectionStatus.Connected);
	}

	private bool ObserveBrokerConnection(DateTime now)
	{
		if (State == State.Realtime && Account != null && Account.ConnectionStatus != ConnectionStatus.Connected && !recoveryPending)
		{
			recoveryPending = true;
			SaveRecovery();
		}
		DateTime utcNow = DateTime.UtcNow;
		if (utcNow >= recoveryNextPollUtc)
		{
			recoveryNextPollUtc = utcNow.AddSeconds(1.0);
			if (State == State.Realtime && recoveryReady && !recoveryFault && !recoveryPending && Account != null && Account.ConnectionStatus == ConnectionStatus.Connected && ((ownedNet != 0 && !RecoveryPositionConsistent()) || orders.Values.Any((Order o) => o != null && o.OrderState == OrderState.Unknown)))
			{
				WaitForRecoveryEvidence();
			}
			ReconcileRecovery();
		}
		if (!BrokerReady())
		{
			connectionPaused = true;
			recoveryFloor = now;
			return false;
		}
		if (connectionPaused)
		{
			connectionPaused = false;
			recoveryFloor = now;
			Print(Name + " connection restored; waiting for a fresh completed signal");
		}
		return true;
	}

	private Order SubmitOwnedOrder(int series, OrderAction action, OrderType type, int quantity, double limit, double stop, string oco, string signal)
	{
		return BrokerReady() ? RecoverySubmit(series, action, type, quantity, limit, stop, oco, signal) : null;
	}

	private void CancelOwnedOrder(Order order)
	{
		if (BrokerReady() && order != null)
		{
			RecoveryCancel(order);
		}
	}

	private void ChangeOwnedOrder(Order order, int quantity, double limit, double stop)
	{
		if (BrokerReady() && order != null)
		{
			RecoveryChange(order, quantity, limit, stop);
		}
	}

protected override void OnBarUpdate()
    {
        if (BarsInProgress == 0) return; // chart interval never drives signals or orders
        if (BarsInProgress == signalSeries) ConsumeSource();
        if (BarsInProgress != executionSeries || CurrentBars[executionSeries] < 0) return;
        if (State == State.Realtime && !UseTickHistory) return; // OnMarketData supplies the real print timestamp
        DateTime at = Eastern(Times[executionSeries][0]);
        ConsumeSource(at);
        ProcessPrint(at,Closes[executionSeries][0],State == State.Historical && !UseTickHistory);
    }

    protected override void OnMarketData(MarketDataEventArgs e)
    {
        if (State != State.Realtime || UseTickHistory || e.MarketDataType != MarketDataType.Last
            || e.Instrument == null || e.Instrument.FullName != ExecutionInstrument.FullName) return;
        DateTime at = Eastern(e.Time);
        ConsumeSource(at);
        ProcessPrint(at,e.Price,false);
    }

    private void ProcessPrint(DateTime at, double price, bool minuteApproximation)
    {
        latestEastern = at;
        if (State == State.Realtime && !ObserveBrokerConnection(at)) return;
        if (ownedNet != 0 && tradeDeadline != DateTime.MinValue && at >= tradeDeadline && !closing)
        {
            Record("TIME_REQUEST", at, "entry="+firstEntryTime.ToString("o")+";deadline="+tradeDeadline.ToString("o"));
            BeginClose("Time");
        }
        DriveClose();
        Signal(at,price,minuteApproximation);
        if (at.Ticks / TimeSpan.TicksPerSecond != lastVisualSecond.Ticks / TimeSpan.TicksPerSecond)
        {
            lastVisualSecond = at;
            if (State == State.Realtime) { Levels(at); UpdatePanel(); }
            else
            {
                // History replays millions of prints: the range is drawn when its last source minute completes (ProcessSource); refresh the panel once per data minute.
                historicalPrints++;
                long minute = at.Ticks / TimeSpan.TicksPerMinute;
                if (minute != lastHistoricalPanelMinute) { lastHistoricalPanelMinute = minute; UpdatePanel(); }
            }
        }
    }

private void ConsumeSource(DateTime through = default(DateTime))
    {
        if (precision == null || historyRepair != null || State == State.Terminated || CurrentBars[signalSeries] < 0) return;
        if (through == DateTime.MinValue) through = State == State.Historical || UseTickHistory ? Eastern(Times[signalSeries][0]) : Eastern(NativeNow());
        int last = State == State.Historical || UseTickHistory ? CurrentBars[signalSeries] : CurrentBars[signalSeries] - 1;
        for (int i=consumedSourceIndex+1; i<=last; i++)
        {
            DateTime end = Eastern(BarsArray[signalSeries].GetTime(i));
            if (end > through) break;
            if (UseTickHistory)
            {
                Candle completed = sourceTickMinutes.Push(end, BarsArray[signalSeries].GetClose(i), BarsArray[signalSeries].GetVolume(i));
                if (completed != null) ProcessSource(completed, false);
            }
            else if (end > lastMinute)
                ProcessSource(new Candle(end.AddMinutes(-1),BarsArray[signalSeries].GetOpen(i),BarsArray[signalSeries].GetHigh(i),BarsArray[signalSeries].GetLow(i),BarsArray[signalSeries].GetClose(i)) { Volume = BarsArray[signalSeries].GetVolume(i) },false);
            consumedSourceIndex = i;
        }
        if (UseTickHistory)
        {
            Candle completed = sourceTickMinutes.CloseThrough(through);
            if (completed != null) ProcessSource(completed, false);
        }
    }

private void ProcessSource(Candle bar, bool fresh)
    {
        if (!precision.Push(bar)) return;
        DateTime end = bar.Start.AddMinutes(1);
        lastMinute = end;
        minutes[bar.Start] = bar;
        foreach(DateTime key in minutes.Keys.TakeWhile(k => k < end.AddDays(-3)).ToArray()) minutes.Remove(key);
        if (bar.Start.Date != sessionDay) ResetDay(bar.Start.Date);
        rangeHigh = precision.RangeHigh; rangeLow = precision.RangeLow; readyRange = precision.RangeReady;
        validDay = precision.Count >= Math.Max(AtrPeriod,AtrRegimeLen);
        if (ShowVisuals && end.TimeOfDay.TotalSeconds >= Clock(RangeStart) && end.TimeOfDay.TotalSeconds <= Clock(RangeEnd)) Levels(end);
    }


	private void RequestSourceRepair(DateTime missingRight, DateTime historicalLeft = default(DateTime))
	{
		visualHistoryWaiting = true;
		DateTime dateTime = Eastern(NativeNow());
		DateTime missingLeft = ((historicalLeft == DateTime.MinValue) ? lastMinute : historicalLeft);
		status = "Reloading provider M1 " + missingLeft.ToString("HH:mm") + " to " + missingRight.ToString("HH:mm") + " Eastern; new entries paused";
		UpdatePanel();
		if (historyRepair != null || dateTime < repairRetry)
		{
			return;
		}
		repairRetry = dateTime.AddSeconds(30.0);
		BarsRequest request = new BarsRequest(BarsArray[signalSeries].Instrument, 3000);
		request.BarsPeriod = new BarsPeriod
		{
			BarsPeriodType = BarsPeriodType.Minute,
			Value = 1
		};
		request.TradingHours = TradingHours.Get("CME US Index Futures ETH");
		request.LookupPolicy = LookupPolicies.Provider;
		historyRepair = request;
		Print("NQ Precision M1 reload: " + missingLeft.ToString("s") + " to " + missingRight.ToString("s") + " Eastern");
		try
		{
			request.Request((BarsRequest reply, ErrorCode error, string message) =>
			{
				if (State == State.Realtime && historyRepair == request)
				{
					List<Candle> recovered = new List<Candle>();
					if (error == ErrorCode.NoError)
					{
						for (int i = 0; i < reply.Bars.Count; i++)
						{
							DateTime dateTime2 = Eastern(reply.Bars.GetTime(i)).AddMinutes(-1.0);
							if (dateTime2 >= missingLeft && dateTime2 < missingRight)
							{
								recovered.Add(new Candle(dateTime2, reply.Bars.GetOpen(i), reply.Bars.GetHigh(i), reply.Bars.GetLow(i), reply.Bars.GetClose(i)) { Volume = reply.Bars.GetVolume(i) });
							}
						}
					}
					TriggerCustomEvent((object ignored) =>
					{
						if (historyRepair == request && State == State.Realtime)
						{
							historyRepair = null;
							request.Dispose();
							DateTime dateTime3 = missingLeft;
							bool flag = error == ErrorCode.NoError;
							foreach (Candle item in recovered)
							{
								if (item.Start != dateTime3)
								{
									flag = false;
									break;
								}
								dateTime3 = item.Start.AddMinutes(1.0);
							}
							if (!flag || dateTime3 != missingRight)
							{
								status = "Provider M1 unavailable at " + dateTime3.ToString("yyyy-MM-dd HH:mm") + " Eastern; retrying";
								Print("NQ Precision " + status + " " + message);
							}
							else
							{
								visualHistoryWaiting = false;
								recoveryFloor = Eastern(NativeNow());
								foreach (Candle item2 in recovered)
								{
									providerBars[item2.Start] = item2;
								}
								if (historicalLeft != DateTime.MinValue)
								{
									RebuildSource(recovered);
								}
								else
								{
									foreach (Candle item3 in recovered)
									{
										ProcessSource(item3, fresh: false);
									}
								}
								status = "M1 history recovered; waiting for a fresh M15 close";
								Print("NQ Precision M1 recovered " + recovered.Count + " bars; old signals suppressed");
								ConsumeSource();
							}
						}
					}, null);
				}
			});
		}
		catch (Exception ex)
		{
			historyRepair = null;
			request.Dispose();
			status = "Provider history request failed; retrying";
			Print("NQ Precision " + status + ": " + ex.Message);
		}
	}

private void RebuildSource(List<Candle> recovered)
    {
        if (UseTickHistory)
        {
            // Provider M1 repairs must never overwrite tick-derived signal history.
            precision = NewPrecisionModel(); minutes.Clear(); lastMinute = DateTime.MinValue;
            sourceTickMinutes = new TickMinuteBuilder(); consumedSourceIndex = -1;
            ConsumeSource(Eastern(NativeNow()));
            recoveryFloor = Eastern(NativeNow()); startupFloor = recoveryFloor;
            return;
        }
        var bars = new SortedDictionary<DateTime,Candle>();
        int last = State == State.Historical ? CurrentBars[signalSeries] : CurrentBars[signalSeries]-1;
        for(int i=0;i<=last;i++)
        {
            DateTime end=Eastern(BarsArray[signalSeries].GetTime(i));
            bars[end.AddMinutes(-1)] = new Candle(end.AddMinutes(-1),BarsArray[signalSeries].GetOpen(i),BarsArray[signalSeries].GetHigh(i),BarsArray[signalSeries].GetLow(i),BarsArray[signalSeries].GetClose(i)) { Volume=BarsArray[signalSeries].GetVolume(i) };
        }
        foreach(Candle bar in recovered) bars[bar.Start]=bar;
        precision=NewPrecisionModel(); minutes.Clear(); lastMinute=DateTime.MinValue;
        foreach(Candle bar in bars.Values) ProcessSource(bar,false);
        consumedSourceIndex=last;
        recoveryFloor=Eastern(NativeNow()); startupFloor=recoveryFloor;
    }


private void ResetDay(DateTime day)
    {
        sessionDay = day; readyRange = false; validDay = false;
        if (ownedNet == 0 && !entryPending) { closing = false; closeReason = null; firstEntryTime = tradeDeadline = DateTime.MinValue; }
        if (decisionDay != day && ownedNet == 0 && !entryPending) entryCount = 0;
        ClearStaleSuspension();
    }

private void ClearStaleSuspension()
    {
        // A persisted order-error/OCO/fill-risk latch used to block every later session (live) or the rest of the run (Historical/Analyzer).
        // Clear it only at a session rollover, and only when nothing is open, pending or unreconciled. Journal/recovery faults (recoveryFault),
        // broker-restriction holds and a lost instance lease are never cleared here.
        if (!suspended || recoveryFault) return;
        if (State == State.Realtime)
        {
            if (!ownsGuard || recoveryPending || reconcilingRecovery || Account == null || Account.ConnectionStatus != ConnectionStatus.Connected) return;
        }
        else if (State != State.Historical) return;
        if (ownedNet != 0 || entryPending || closing || closeRejected || entered != 0 || exited != 0) return;
        if (!string.IsNullOrEmpty(pendingCloseName) || pendingCloseQuantity != 0 || pendingCloseExecuted != 0) return;
        if (orders.Values.Any(o => !Settled(o) || !ExecutionsCaughtUp(o))) return;
        suspended = false;
        status = "Suspension cleared at session rollover: flat, settled and reconciled";
        if (State == State.Realtime) Print(Name + ": SUSPENSION_CLEARED at session rollover; no owned position, order or pending close");
        SaveRecovery();
    }


	private bool Window(DateTime from, DateTime to, out Candle aggregate)
	{
		aggregate = null;
		DateTime dateTime = from;
		while (dateTime < to)
		{
			if (!minutes.TryGetValue(dateTime, out var value))
			{
				if (State == State.Realtime && historyRepair == null)
				{
					RequestSourceRepair(to, dateTime);
				}
				return false;
			}
			if (aggregate == null)
			{
				aggregate = value.Clone();
			}
			else
			{
				aggregate.Merge(value);
			}
			dateTime = dateTime.AddMinutes(1.0);
		}
		return aggregate != null;
	}

private void PrepareRange()
    {
        rangeHigh = precision.RangeHigh; rangeLow = precision.RangeLow; readyRange = precision.RangeReady;
    }

private bool CanReplayCompletedSession(DateTime day)
    {
        if (State != State.Historical || IsInStrategyAnalyzer) return true;
        Bars bars=BarsArray[executionSeries];
        // Exclude the unfinished chart tail, never a completed native historical session.
        DateTime ready=day.Date.AddSeconds(Clock(UseTriggerTime ? TriggerTime : TradeUntil)).AddMinutes(CloseAfterMin+2);
        return bars.Count>0 && Eastern(bars.GetTime(bars.Count-1))>=ready;
    }

private bool LogOnce(DateTime at, string key)
    {
        return loggedDecisions.Add(at.Date.ToString("yyyyMMdd", CultureInfo.InvariantCulture) + "|" + key);
    }

private void LogDecision(string code, DateTime at, string detail)
    {
        if (State == State.Realtime)
            Print("NQPB " + code + " " + at.ToString("yyyy-MM-dd HH:mm:ss.fff", CultureInfo.InvariantCulture) + " ET | " + detail);
        Record(code, at, detail);
    }

private void ConsumeTrigger(DateTime at)
    {
        if (UseTriggerTime && decisionDay != at.Date) { decisionDay = at.Date; SaveRecovery(); }
    }

private void Signal(DateTime at, double price, bool minuteApproximation)
    {
        int second=(int)at.TimeOfDay.TotalSeconds;
        if (UseTriggerTime ? second<Clock(TriggerTime) : (second<Clock(RangeEnd) || second>Clock(TradeUntil))) return;
        if (!EnableTrading || suspended || closing || entryPending || ownedNet!=0 || decisionDay==at.Date || !CanReplayCompletedSession(at.Date)) return;
        if (State==State.Realtime && (!startupArmed || at<startupFloor || recoveryPending || recoveryFault || historyRepair!=null)) return;
        if (UseTriggerTime)
        {
            int trigger=Clock(TriggerTime);
            if (second<trigger) return;
            if (second>trigger+TriggerGraceSeconds)
            {
                // The fixed trigger has passed (feed gap, late start/reload, or a block that outlived the window): never enter late.
                decisionDay=at.Date; SaveRecovery();
                LogDecision("TRIGGER_MISSED",at,"no entry decision inside the "+TriggerGraceSeconds+"s trigger window; last status="+status);
                return;
            }
        }
        else if (second<Clock(RangeEnd) || second>Clock(TradeUntil)) return;
        if (!readyRange || sessionDay!=at.Date)
        {
            status="Waiting for opening range history";
            if (LogOnce(at,"WAIT_RANGE")) LogDecision("TRIGGER_WAIT",at,"opening range not ready (readyRange="+readyRange+"; sessionDay="+sessionDay.ToString("yyyy-MM-dd",CultureInfo.InvariantCulture)+"); retrying");
            return;
        }
        DateTime cutoff=minuteApproximation ? at.AddMinutes(-1) : at;
        PrecisionModel.Snapshot frame=precision.At(cutoff);
        int side=price>rangeHigh ? 1 : price<rangeLow ? -1 : 0;
        if (side==0)
        {
            status="Trigger inside opening range"; ConsumeTrigger(at);
            if (UseTriggerTime || LogOnce(at,"SKIP_RANGE")) LogDecision("SKIP_RANGE",at,F(price)+" inside "+F(rangeLow)+"-"+F(rangeHigh));
            return;
        }
        if (frame==null || frame.End.Date!=at.Date || !(frame.Atr>0) || precision.Count<Math.Max(AtrPeriod,AtrRegimeLen))
        {
            status="No eligible completed ETH minute filters";
            if (LogOnce(at,"WAIT_FRAME")) LogDecision("TRIGGER_WAIT",at,"no eligible completed ETH minute filters yet (minutes="+precision.Count+"); retrying");
            return;
        }
        if (UseFilters && (double.IsNaN(frame.Rvol) || double.IsNaN(frame.Regime) || frame.Rvol<RvolMin || frame.Rvol>RvolMax || frame.Regime<RegimeMin || frame.Regime>RegimeMax))
        {
            status="Trigger filter rejected"; ConsumeTrigger(at);
            LogDecision("SKIP_FILTER",at,"ATR="+F(frame.Atr)+" RVOL="+F(frame.Rvol)+" regime="+F(frame.Regime));
            return;
        }
        plannedStop=CrossingTick(price-side*AtrSlMult*frame.Atr,side<0);
        plannedTarget=CrossingTick(price+side*AtrTpMult*frame.Atr,side>0);
        double unit=Math.Abs(price-plannedStop)*ExecutionInstrument.MasterInstrument.PointValue+CostPerContract;
        int quantity=UseFixedSize ? FixedContracts : Quantity(RiskMoney,unit);
        if (quantity<1)
        {
            status="Risk budget cannot fund one native contract"; ConsumeTrigger(at);
            LogDecision("SKIP_RISK",at,F(unit));
            return;
        }
        if (State==State.Realtime && !AcquireExposure(side))
        {
            // Not consumed: retried on later prints until the trigger window ends (then TRIGGER_MISSED is recorded).
            if (LogOnce(at,"BLOCK|"+status)) LogDecision("ENTRY_BLOCKED",at,status+"; retrying inside the trigger window");
            return;
        }
        DateTime priorDecision=decisionDay;
        int priorCount=entryCount;
        decisionDay=at.Date; entryCount++; entryPending=true;
        entered=exited=ownedNet=0; entrySum=exitSum=actualFees=peakR=0;
        firstEntryTime=tradeDeadline=DateTime.MinValue; tradeModeledCost=CostPerContract;
        brackets.Clear(); closeReason=null; recoveredCommissionFloor=0;
        entryName=owner+"_Entry_"+(++sequence);
        status="Entry submitted";
        Record(minuteApproximation ? "HIST_MINUTE_APPROX" : State==State.Historical ? "HIST_TICK" : "LIVE",at,
            "signal="+F(price)+" ATR="+F(frame.Atr)+" RVOL="+F(frame.Rvol)+" regime="+F(frame.Regime)+" filterEnd="+frame.End.ToString("s")+" stop="+F(plannedStop)+" target="+F(plannedTarget));
        SaveRecovery();
        Order submitted=SubmitOwnedOrder(executionSeries,side>0 ? OrderAction.Buy : OrderAction.SellShort,OrderType.Market,quantity,0,0,string.Empty,entryName);
        if (submitted==null && !recoveryFault)
        {
            // Nothing reached the broker (not ready, or the platform declined it): undo the pending state instead of stranding the day.
            recoveryRequests.Remove(entryName);
            entryPending=false; entryCount=priorCount; decisionDay=priorDecision;
            ReleaseExposure();
            status="Entry order was not accepted for submission; retrying inside the trigger window";
            if (LogOnce(at,"NOSUBMIT")) LogDecision("ENTRY_NOT_SUBMITTED",at,"broker not ready or platform declined the order; pending state rolled back");
            SaveRecovery();
            return;
        }
        if (State==State.Realtime)
            Print("NQPB ENTRY_SUBMIT "+at.ToString("yyyy-MM-dd HH:mm:ss.fff",CultureInfo.InvariantCulture)+" ET | side="+side+" qty="+quantity+" signal="+F(price)+" stop="+F(plannedStop)+" target="+F(plannedTarget)+" ATR="+F(frame.Atr)+" RVOL="+F(frame.Rvol)+" regime="+F(frame.Regime));
    }

    private double CrossingTick(double price,bool upward)
    {
        double tick=ExecutionInstrument.MasterInstrument.TickSize;
        return (upward ? Math.Ceiling(price/tick) : Math.Floor(price/tick))*tick;
    }
    private static int Clock(int value) { return value/10000*3600+value/100%100*60+value%100; }
    private static bool ValidClock(int value) { return value>=0 && value/10000<24 && value/100%100<60 && value%100<60; }
    private PrecisionModel NewPrecisionModel() { return new PrecisionModel(AtrPeriod,AtrRegimeLen,RvolLen,RangeStart,RangeEnd); }


	private void ObserveFee(Execution execution, string executionId, int quantity, bool isEntry)
	{
		if (!CanLearnFee || string.IsNullOrEmpty(executionId) || quantity <= 0)
		{
			return;
		}
		lock (FeeGate)
		{
			if (!FeeHistory.TryGetValue(FeeScope, out var value))
			{
				value = (FeeHistory[FeeScope] = new List<FeeTrade>());
			}
			FeeTrade feeTrade = value.FirstOrDefault((FeeTrade t) => t.Slices.ContainsKey(executionId));
			if (feeTrade != null)
			{
				feeTrade.Slices[executionId].Execution = execution;
				return;
			}
			if (isEntry && (this.feeTrade == null || this.feeTrade.Signal != entryName))
			{
				this.feeTrade = new FeeTrade
				{
					Signal = entryName
				};
				value.Add(this.feeTrade);
				if (value.Count > 32)
				{
					value.RemoveAt(0);
				}
			}
			if (this.feeTrade != null && !this.feeTrade.Closed)
			{
				this.feeTrade.Slices[executionId] = new FeeSlice
				{
					Execution = execution,
					Quantity = quantity,
					Entry = isEntry
				};
			}
		}
	}

	internal static double FillRiskCost(double reservedCost, double entryFees, int entryQuantity, double twoWaySlippage)
	{
		return (entryQuantity > 0) ? Math.Max(reservedCost, 2.0 * entryFees / (double)entryQuantity + twoWaySlippage) : reservedCost;
	}

	private void CheckActualFillRisk()
	{
		if (UseFixedSize || entered <= 0 || ownedNet == 0 || closing)
		{
			return;
		}
		double entryFees = 0.0;
		int entryQuantity = 0;
		if (CanLearnFee && feeTrade != null)
		{
			lock (FeeGate)
			{
				entryQuantity = feeTrade.EntryQuantity;
				entryFees = feeTrade.Slices.Values.Where((FeeSlice x) => x.Entry).Sum((FeeSlice x) => FeeTrade.Charge(x.Execution));
			}
		}
		double num = FillRiskCost(tradeModeledCost, entryFees, entryQuantity, 2.0 * SlippagePrice * ExecutionInstrument.MasterInstrument.PointValue);
		if ((double)entered * (initialRisk * ExecutionInstrument.MasterInstrument.PointValue + num) > RiskMoney + 1E-07)
		{
			suspended = true;
			BeginClose("ActualFillRiskExceeded");
		}
	}

	private double Round(double p)
	{
		return ExecutionInstrument.MasterInstrument.RoundToTickSize(p);
	}




	internal static int Quantity(double budget, double unit)
	{
		return (!(unit <= 0.0) && !double.IsNaN(unit) && !double.IsInfinity(unit)) ? ((int)Math.Min(2147483647.0, Math.Floor(budget / unit + 1E-09))) : 0;
	}




	private static bool Settled(Order o)
	{
		return o == null || o.OrderState == OrderState.Filled || o.OrderState == OrderState.Cancelled || o.OrderState == OrderState.Rejected;
	}

	private bool ExecutionsCaughtUp(Order o)
	{
		if (o == null)
		{
			return true;
		}
		processed.TryGetValue(o.Name, out var value);
		reportedFilled.TryGetValue(o.Name, out var value2);
		return value >= Math.Max(o.Filled, value2);
	}

    private static bool AccountRestriction(string message)
    {
        // Broker permission-denial aliases.
        string text = (message ?? "").ToLowerInvariant();
        return text.Contains("liquidation") || text.Contains("liquidate only") ||
            text.Contains("account is restricted") || text.Contains("account restricted") ||
            text.Contains("trading is disabled") || text.Contains("trading disabled") ||
            text.Contains("not authorized") || text.Contains("permission") ||
            text.Contains("low net liquidating value");
    }

	protected override void OnOrderUpdate(Order order, double limitPrice, double stopPrice, int quantity, int filled, double averageFillPrice, OrderState orderState, DateTime time, ErrorCode error, string nativeError)
	{
		if (owner == null || !order.Name.StartsWith(owner + "_"))
		{
			return;
		}
		orders[order.Name] = order;
		reportedFilled.TryGetValue(order.Name, out var value);
		reportedFilled[order.Name] = Math.Max(value, filled);
		RememberOrder(order, quantity, limitPrice, stopPrice);
		if (order.Name == pendingCloseName && (orderState == OrderState.Filled || orderState == OrderState.Cancelled || orderState == OrderState.Rejected))
		{
			pendingCloseFinal = ((orderState == OrderState.Filled) ? pendingCloseQuantity : filled);
		}
		foreach (Bracket bracket2 in brackets)
		{
			if (order.Name == bracket2.StopName)
			{
				bracket2.Stop = order;
			}
			if (order.Name == bracket2.TargetName)
			{
				bracket2.Target = order;
			}
		}
		if (!closing && !repairingProtection && !recoveryFault && orderState == OrderState.Cancelled && ownedNet != 0)
		{
			Bracket bracket = brackets.FirstOrDefault((Bracket b) => b.StopName == order.Name || b.TargetName == order.Name);
			if (bracket != null)
			{
				Order order2 = ((bracket.StopName == order.Name) ? bracket.Target : bracket.Stop);
				if (order2 == null || order2.Filled < order2.Quantity)
				{
					if (State == State.Realtime)
					{
						WaitForRecoveryEvidence();
					}
					else
					{
						suspended = true;
						BeginClose("ProtectionCancelled");
					}
				}
			}
		}
		if ((error != ErrorCode.NoError || orderState == OrderState.Rejected) &&
			AccountRestriction(nativeError))
		{
			// An account restriction cannot be repaired with another close/replace request.
			// Persist the entry latch before faulting; retain any accepted broker protection.
			suspended = true;
			closeReason = "BrokerAccountRestricted: " + nativeError + " | priorCloseReason=" + (closeReason ?? "");
			SaveRecovery();
			if (ownedNet == 0 && recoveryRequests.Keys.All(name => orders.ContainsKey(name)) && orders.Values.All(o => Settled(o) && ExecutionsCaughtUp(o)))
				ReleaseExposure();
			RecoveryBlock("Broker account restricted; new orders paused; verify broker position/protection: " + nativeError);
			return;
		}
		if ((error != ErrorCode.NoError || orderState == OrderState.Rejected) && order.Name.Contains("_Repair"))
		{
			if (!reconcilingRecovery || orderState != OrderState.Rejected || filled != 0 || order.Filled != 0)
			{
				RecoveryBlock("Broker rejected recovered protection: " + order.Name + " id=" + order.OrderId + " state=" + orderState.ToString() + " error=" + error.ToString() + " OCO=" + order.Oco + " detail=" + nativeError);
			}
			return;
		}
		if (error != ErrorCode.NoError || orderState == OrderState.Rejected)
		{
			if (order.Name == pendingCloseName)
			{
				closeRejected = true;
			}
			suspended = true;
			Print(Name + " owned order error: " + error.ToString() + " " + nativeError);
			BeginClose("OrderError");
		}
		SaveRecovery();
		DriveClose();
		if (closeRejected && order.Name == pendingCloseName)
		{
			RepairOwnedProtection();
		}
		if (entered > 0 && ownedNet == 0 && !entryPending && orders.Values.All((Order o) => Settled(o) && ExecutionsCaughtUp(o)))
		{
			Complete(Eastern(time));
		}
	}

	protected override void OnExecutionUpdate(Execution execution, string executionId, double price, int quantity, MarketPosition marketPosition, string orderId, DateTime time)
	{
		if (execution == null || execution.Order == null || owner == null || execution.Order.Name == null || !execution.Order.Name.StartsWith(owner + "_", StringComparison.Ordinal) || ReconcileOwnedExecution(execution, executionId))
		{
			return;
		}
		ObserveFee(execution, executionId, quantity, execution.Order.Name == entryName);
		if (!executions.Add(executionId))
		{
			CheckActualFillRisk();
			return;
		}
		RememberExecution(execution.Order, quantity, price);
		Order order = execution.Order;
		processed.TryGetValue(order.Name, out var value);
		processed[order.Name] = value + quantity;
		if (order.Name == pendingCloseName)
		{
			pendingCloseExecuted += quantity;
		}
		int num = ((order.OrderAction == OrderAction.Buy || order.OrderAction == OrderAction.BuyToCover) ? 1 : (-1));
		ownedNet += num * quantity;
		actualFees += FeeTrade.Charge(execution);
		if (order.Name == entryName)
		{
            RecordEntryClock(Eastern(time));
			entered += quantity;
			entrySum += price * (double)quantity;
			initialRisk = Math.Abs(entrySum / (double)entered - plannedStop);
			if (initialRisk > 0.0 && (double)num * (price - plannedStop) > 0.0 && (double)num * (plannedTarget - price) <= 0.0)
			{
				// Price ran through the 0.3 ATR target during order latency. That is a favourable fill: keep the normal bracket (the target limit is marketable)
				// instead of market-closing and suspending, which turned a would-be winner into a loss and blocked later trades.
				Record("FILL_THROUGH_TARGET", Eastern(time), "fill=" + F(price) + " target=" + F(plannedTarget));
				if (State == State.Realtime) Print("NQPB FILL_THROUGH_TARGET " + Eastern(time).ToString("HH:mm:ss.fff", CultureInfo.InvariantCulture) + " ET | fill=" + F(price) + " target=" + F(plannedTarget) + "; bracket placed, target marketable");
			}
			if (initialRisk <= 0.0 || (double)num * (price - plannedStop) <= 0.0)
			{
				suspended = true;
				BeginClose("InvalidFill");
			}
			else if (!closing)
			{
				Bracket bracket = new Bracket();
				string text = owner;
				int num2 = ++sequence;
				bracket.StopName = text + "_Stop_" + num2;
				bracket.TargetName = owner + "_Target_" + sequence;
				Bracket bracket2 = bracket;
				brackets.Add(bracket2);
				string oco = owner + "_OCO_" + sequence;
				bracket2.Stop = SubmitOwnedOrder(executionSeries, (num <= 0) ? OrderAction.BuyToCover : OrderAction.Sell, OrderType.StopMarket, quantity, 0.0, plannedStop, oco, bracket2.StopName);
				if (!closing)
				{
					bracket2.Target = SubmitOwnedOrder(executionSeries, (num <= 0) ? OrderAction.BuyToCover : OrderAction.Sell, OrderType.Limit, quantity, plannedTarget, 0.0, oco, bracket2.TargetName);
				}
			}
			if (executionVisual == null)
			{
				executionVisual = new ExecutionView
				{
					Tag = entryName + "_EXEC",
					Side = num,
					InitialStop = plannedStop,
					Stop = plannedStop,
					Entered = Eastern(time)
				};
			}
			executionVisual.Entry = entrySum / (double)entered;
			DrawExecution(executionVisual, Eastern(time));
			CheckActualFillRisk();
			Record("ENTRY", Eastern(time), "price=" + F(price) + " qty=" + quantity + " stop=" + F(plannedStop) + ";tradeId=" + entryName + ";executionId=" + executionId + ";time=" + Eastern(time).ToString("s") + ";direction=" + ((num > 0) ? "Long" : "Short") + ";quantity=" + quantity + ";initialStop=" + F(plannedStop) + ";initialTarget=" + F(plannedTarget));
			status = (closing ? "Closing owned position" : "Owned position protected");
		}
		else
		{
			exited += quantity;
			exitSum += price * (double)quantity;
			Record("EXIT", Eastern(time), order.Name + " price=" + F(price) + " qty=" + quantity + ";tradeId=" + entryName + ";executionId=" + executionId + ";time=" + Eastern(time).ToString("s") + ";direction=" + ((plannedStop < entrySum / (double)entered) ? "Long" : "Short") + ";quantity=" + quantity + ";initialStop=" + F(plannedStop));
			if (ownedNet != 0 && !closing)
			{
				BeginClose("PartialExit");
			}
		}
		if (orders.TryGetValue(entryName ?? "", out var value2) && Settled(value2) && ExecutionsCaughtUp(value2))
		{
			entryPending = false;
		}
		if (exited > entered)
		{
			suspended = true;
			BeginClose("OcoRace");
		}
		DriveClose();
		if (entered > 0 && ownedNet == 0 && !entryPending && orders.Values.All((Order o) => Settled(o) && ExecutionsCaughtUp(o)))
		{
			Complete(Eastern(time));
		}
	}

    private void RecordEntryClock(DateTime at)
    {
        if (firstEntryTime == DateTime.MinValue)
        {
            firstEntryTime = at;
            tradeDeadline = UseTimeClose ? at.AddMinutes(CloseAfterMin) : DateTime.MinValue;
        }
        else if (at < firstEntryTime)
        {
            if (tradeDeadline != DateTime.MinValue) tradeDeadline = tradeDeadline.Add(at - firstEntryTime);
            firstEntryTime = at;
        }
    }

	private void Complete(DateTime time)
	{
		if (feeTrade != null)
		{
			feeTrade.Closed = feeTrade.EntryQuantity > 0 && feeTrade.EntryQuantity == feeTrade.ExitQuantity;
		}
		if (executionVisual != null)
		{
			executionVisual.Exit = exitSum / (double)exited;
			executionVisual.Exited = time;
			closedVisuals.Add(executionVisual);
			historicalVisualsPainted = false;
			DrawExecution(executionVisual, time);
			executionVisual = null;
		}
		double num = exitSum - entrySum;
		int num2 = ((plannedStop < entrySum / (double)entered) ? 1 : (-1));
		double num3 = (double)num2 * num * ExecutionInstrument.MasterInstrument.PointValue;
		double value = num3 - (double)entered * tradeModeledCost;
		Print(Name + " trade closed: gross=" + F(num3) + " modeled net=" + F(value) + " actual commission=" + F(actualFees));
		Record("CLOSE", time, "gross=" + F(num3) + " modeledNet=" + F(value));
		try
		{
			string csvPath = Path.Combine(Globals.UserDataDir, "NQPrecisionBot_trades.csv");
			bool writeHeader = !File.Exists(csvPath);
			using (StreamWriter sw = new StreamWriter(csvPath, true))
			{
				if (writeHeader)
					sw.WriteLine("Date,Direction,EntryTime,EntryPrice,ExitTime,ExitPrice,Quantity,Gross,Net,Commission,Stop,Target");
				string dir = num2 > 0 ? "Long" : "Short";
				double avgEntry = entered > 0 ? entrySum / (double)entered : 0;
				double avgExit = exited > 0 ? exitSum / (double)exited : 0;
				sw.WriteLine(string.Format(CultureInfo.InvariantCulture, "{0},{1},{2},{3},{4},{5},{6},{7},{8},{9},{10},{11}",
					firstEntryTime.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
					dir,
					firstEntryTime.ToString("yyyy-MM-dd HH:mm:ss.fff", CultureInfo.InvariantCulture),
					F(avgEntry),
					time.ToString("yyyy-MM-dd HH:mm:ss.fff", CultureInfo.InvariantCulture),
					F(avgExit),
					entered,
					F(num3),
					F(value),
					F(actualFees),
					F(plannedStop),
					F(plannedTarget)));
			}
		}
		catch { }
		entered = (exited = 0);
		brackets.Clear();
		closing = false;
		closeReason = null;
		status = "Daily trade consumed";
		ReleaseExposure();
		SaveRecovery();
	}

	private void BeginClose(string reason)
	{
		closing = true;
		closeReason = reason;
		SaveRecovery();
		DriveClose();
	}

	private void DriveClose()
	{
		if (!BrokerReady() || !closing || closingDrive || closeRejected)
		{
			return;
		}
		closingDrive = true;
		try
		{
			if (ownedNet != 0 && orders.Values.All(ExecutionsCaughtUp) && !RecoveryPositionConsistent())
			{
				WaitForRecoveryEvidence();
				return;
			}
			Order[] array = orders.Values.ToArray();
			foreach (Order order in array)
			{
				if (!Settled(order) && (order.Name == entryName || order.OrderType != OrderType.Market) && order.OrderState != OrderState.CancelPending && order.OrderState != OrderState.CancelSubmitted)
				{
					CancelOwnedOrder(order);
				}
			}
			if (orders.Values.Any((Order o) => !Settled(o) || !ExecutionsCaughtUp(o)))
			{
				return;
			}
			entryPending = false;
			if (ownedNet == 0)
			{
				ReleaseExposure();
			}
			else if (pendingCloseName == null || (pendingCloseFinal >= 0 && pendingCloseExecuted >= pendingCloseFinal))
			{
				if (!RecoveryPositionConsistent())
				{
					WaitForRecoveryEvidence();
					return;
				}
				string text = owner;
				int num = ++sequence;
				pendingCloseName = text + "_Close_" + num;
				pendingCloseQuantity = Math.Abs(ownedNet);
				pendingCloseExecuted = 0;
				pendingCloseFinal = -1;
				SubmitOwnedOrder(executionSeries, (ownedNet <= 0) ? OrderAction.BuyToCover : OrderAction.Sell, OrderType.Market, Math.Abs(ownedNet), 0.0, 0.0, string.Empty, pendingCloseName);
			}
		}
		finally
		{
			closingDrive = false;
		}
	}

	private bool AcquireExposure(int side)
	{
		if (State != State.Realtime)
			return true;
		// Durable executor/instance leases remain separate from this direction guard.
		// Same-direction strategies may share a contract; opposite netting is always blocked.
		if (!ProductExposure.Reserve(owner, side, Account, ExecutionInstrument, BlockOpposingExposure, out var reason))
		{
			status = reason;
			return false;
		}
		return true;
	}

	private void ReleaseExposure(string releasingOwner = null)
	{
		string text = releasingOwner ?? owner;
		if (exposureKey != null && text != null)
		{
			ExposureRelease(exposureKey, text);
			ProductExposure.Release(text);
		}
	}

	internal static bool ExposureAcquire(string key, string ownerId)
	{
		lock (AppDomain.CurrentDomain)
		{
			Dictionary<string, string> dictionary = AppDomain.CurrentDomain.GetData("NQIndependentModelExposure.v1") as Dictionary<string, string>;
			if (dictionary == null)
			{
				dictionary = new Dictionary<string, string>();
				AppDomain.CurrentDomain.SetData("NQIndependentModelExposure.v1", dictionary);
			}
			if (dictionary.TryGetValue(key, out var value))
			{
				return value == ownerId;
			}
			dictionary[key] = ownerId;
			return true;
		}
	}

	internal static void ExposureRelease(string key, string ownerId)
	{
		lock (AppDomain.CurrentDomain)
		{
			if (AppDomain.CurrentDomain.GetData("NQIndependentModelExposure.v1") is Dictionary<string, string> dictionary && dictionary.TryGetValue(key, out var value) && value == ownerId)
			{
				dictionary.Remove(key);
			}
		}
	}

private void EnforceTimeExit(DateTime now)
    {
        if (ownedNet != 0 && tradeDeadline != DateTime.MinValue && now >= tradeDeadline && !closing)
        {
            Record("TIME_REQUEST", now, "entry="+firstEntryTime.ToString("o")+";deadline="+tradeDeadline.ToString("o")+";source=timer");
            BeginClose("Time");
        }
    }

private void TimerStep()
    {
        if (State!=State.Realtime) return;
        if (ObserveBrokerConnection(Eastern(NativeNow()))) { EnforceTimeExit(Eastern(NativeNow())); CheckActualFillRisk(); DriveClose(); ConsumeSource(); }
        // Timer retries recovery and enforces the time-close even when no print arrives; broker protection stays in place meanwhile.
        UpdatePanel();
    }


	private void Record(string evt, DateTime ct, string detail)
	{
		if (log != null)
		{
			log.WriteLine(evt + "," + ct.ToString("yyyy-MM-dd HH:mm:ss.fffffff", CultureInfo.InvariantCulture) + "," + detail.Replace(",", ";"));
		}
	}

	private static string F(double value)
	{
		return value.ToString("0.########", CultureInfo.InvariantCulture);
	}

private void ReportStateChange()
    {
        if (State != State.Realtime) return;
        string now = VisualFaultReason() ?? status ?? "READY";
        if (now == lastStatePrinted) return;
        lastStatePrinted = now;
        Print("NQPB STATE " + Eastern(NativeNow()).ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture) + " ET | " + now);
    }

private void UpdatePanel()
    {
        ReportStateChange();
        SyncFaultVisuals();
        if (!ShowVisuals) return;
        DateTime at=State==State.Realtime ? Eastern(NativeNow()) : latestEastern;
        PaintHistoricalExecutions(at);
        PrecisionModel.Snapshot frame=precision==null ? null : precision.At(at);
        dashboard.Publish(new ModelDashState {
            Title="NQ Precision", Clock="NY: "+at.ToString("HH:mm:ss"), Status=VisualFaultReason()??status,
            NewsBlocked=connectionPaused||suspended, RangeCaption="OPENING RANGE | "+RangeStart.ToString("000000")+"–"+RangeEnd.ToString("000000")+" NY",
            HighCaption="HIGH", LowCaption="LOW", RangeHigh=precision!=null&&precision.HaveRange?F(rangeHigh):"--", RangeLow=precision!=null&&precision.HaveRange?F(rangeLow):"--", RangeWidth=precision!=null&&precision.HaveRange?F(rangeHigh-rangeLow):"--",
            InTrade=ownedNet!=0&&!recoveryPending&&!recoveryFault,
            Position=recoveryPending||recoveryFault ? "UNVERIFIED" : ownedNet==0 ? "FLAT" : Math.Abs(ownedNet)+(ownedNet>0?" LONG":" SHORT"),
            Stop=ownedNet!=0&&!recoveryPending&&!recoveryFault ? F(plannedStop) : "--",
            Risk="Trades "+entryCount+"/1 | "+(UseFixedSize?"Fixed "+FixedContracts+" contracts":"Risk $"+F(RiskMoney)),
            Costs="Cost/contract $"+F(CostPerContract)+" | "+ExecutionInstrument.MasterInstrument.Name,
            History=(frame==null ? "ETH M1 warming up" : "ATR "+F(frame.Atr)+" | RVOL "+F(frame.Rvol)+" | regime "+F(frame.Regime))+(UseTickHistory?" | Tick history":" | OHLC approximation")
        });
        if(State==State.Realtime) RequestDashboardRender();
    }

private void Level(string tag,DateTime left,DateTime right,double price,System.Windows.Media.Brush brush)
    {
        if (ShowVisuals && !VisualsSuppressed && right>left && price>0)
            PrecisionExecutionVisual.DrawBoundedLine(this,"NQPB_"+sessionDay.ToString("yyyyMMdd")+"_"+tag,Platform(left),price,Platform(right),price,brush,DashStyleHelper.Dash,1);
    }

private void Levels(DateTime now)
    {
        if (!ShowVisuals || VisualsSuppressed || precision==null || !precision.HaveRange || sessionDay==DateTime.MinValue) return;
        DateTime left=sessionDay.AddSeconds(Clock(RangeStart));
        DateTime rangeEnd=sessionDay.AddSeconds(Clock(RangeEnd));
        DateTime end=now<rangeEnd?now:rangeEnd;
        if(end>left) PrecisionExecutionVisual.DrawRangeBox(this,"NQPB_"+sessionDay.ToString("yyyyMMdd")+"_RANGE",Platform(left),Platform(end),precision.RangeHigh,precision.RangeLow,Brushes.Goldenrod,12);
        DateTime right=sessionDay.AddSeconds(Clock(UseTriggerTime?TriggerTime:TradeUntil)).AddMinutes(CloseAfterMin+2);
        Level("HIGH",left,right,precision.RangeHigh,Brushes.Goldenrod);
        Level("LOW",left,right,precision.RangeLow,Brushes.Goldenrod);
    }

internal static int Cutoff(DateTime day) { return 960; }










}
}
