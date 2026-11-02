//+------------------------------------------------------------------+
//|                                             VWAPPullbackNT8.cs  |
//| Intraday Session VWAP Pullback Trend Strategy on Nasdaq          |
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

namespace NinjaTrader.NinjaScript.Strategies
{
public class VWAPPullbackNT8 : Strategy
{
	private sealed class ExecutionView
	{
		internal string Tag;

		internal int Side;

		internal double Entry;

		internal double InitialStop;

		internal double Stop;

		internal double Target;

		internal double Exit;

		internal DateTime Entered;

		internal DateTime Exited;

		internal DateTime TrailStart;

		internal bool Trailing;
	}

	private static class PullbackExecutionVisual
	{
		private sealed class PendingChartDraws
		{
			internal readonly Dictionary<string, Action> Latest = new Dictionary<string, Action>();

			internal readonly Queue<string> Order = new Queue<string>();

			internal bool Queued;
		}

		public static readonly System.Windows.Media.Brush ClrEntryLine = MakeBrush(214, 218, 224);

		public static readonly System.Windows.Media.Brush ClrSLBox = MakeBrush(55, 57, 68);

		public static readonly System.Windows.Media.Brush ClrTPBox = MakeBrush(22, 55, 120);

		public static readonly System.Windows.Media.Brush ClrTrailingStop = MakeBrush(162, 138, 88);

		private static int reportedDrawFailure;

		private static readonly ConditionalWeakTable<Strategy, PendingChartDraws> pendingChartDraws = new ConditionalWeakTable<Strategy, PendingChartDraws>();

		private static bool ValidTime(DateTime t)
		{
			return t > new DateTime(2000, 1, 1);
		}

		public static System.Windows.Media.Brush MakeBrush(byte r, byte g, byte b)
		{
			System.Windows.Media.SolidColorBrush solidColorBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(r, g, b));
			solidColorBrush.Freeze();
			return solidColorBrush;
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
						if (strategy.State == State.Terminated || ((VWAPPullbackNT8)strategy).VisualsSuppressed)
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
				strategy.Print("[Execution visuals] Drawing update failed: " + ex.Message);
			}
		}

		private static void Sink(DrawingTool dt)
		{
			try
			{
				if (dt != null && dt.ZOrder != 1)
				{
					dt.ZOrder = 1;
				}
			}
			catch
			{
			}
		}

		public static void DrawBoundedLine(Strategy strategy, string tag, DateTime t1, double p1, DateTime t2, double p2, System.Windows.Media.Brush brush, DashStyleHelper dash, int width)
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
			DateTime right = ((exitTime < entryTime) ? entryTime : exitTime);
			int fillOpacity = (synthetic ? 25 : 40);
			DrawBoundedLine(strategy, tagBase + "_ENT", levelTime, levelPx, entryTime, levelPx, ClrEntryLine, synthetic ? DashStyleHelper.Dash : DashStyleHelper.Solid, 2);
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
		public DateTime Start;

		public DateTime Last;

		public double Open;

		public double High;

		public double Low;

		public double Close;

		public double Volume;

		public Candle(DateTime t, double o, double h, double l, double c, double v = 1.0)
		{
			Start = (Last = t);
			Open = o;
			High = h;
			Low = l;
			Close = c;
			Volume = v;
		}

		public Candle Clone()
		{
			return new Candle(Start, Open, High, Low, Close, Volume)
			{
				Last = Last
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

	internal sealed class PullbackSetup
	{
		private DateTime day;

		private double weightedPrice;

		private double volume;

		private int openingBars;

		private bool orderedOpening = true;

		public double RangeHigh { get; private set; }

		public double RangeLow { get; private set; }

		public double Vwap { get; private set; }

		public bool RangeReady => orderedOpening && openingBars == 30;

		public bool HighQualified { get; private set; }

		public bool TouchQualified { get; private set; }

		public bool Reclaimed { get; private set; }

		public bool Consumed { get; private set; }

		public void Consume()
		{
			Consumed = true;
		}

		public bool Observe(DateTime start, double high, double low, double close, double barVolume, double adx, double previousAdx)
		{
			if (start.Date != day)
			{
				day = start.Date;
				weightedPrice = (volume = 0.0);
				openingBars = 0;
				orderedOpening = true;
				RangeHigh = double.NegativeInfinity;
				RangeLow = double.PositiveInfinity;
				Vwap = double.NaN;
				bool flag = (Consumed = false);
				bool flag3 = (Reclaimed = flag);
				bool highQualified = (TouchQualified = flag3);
				HighQualified = highQualified;
			}
			int num = start.Hour * 60 + start.Minute;
			if (num < 510)
			{
				return false;
			}
			weightedPrice += (high + low + close) / 3.0 * barVolume;
			volume += barVolume;
			Vwap = ((volume > 0.0) ? (weightedPrice / volume) : double.NaN);
			if (num < 540)
			{
				orderedOpening &= num == 510 + openingBars;
				openingBars++;
				RangeHigh = Math.Max(RangeHigh, high);
				RangeLow = Math.Min(RangeLow, low);
			}
			if (!RangeReady || num < 590 || num >= 954 || Consumed)
			{
				return false;
			}
			if (!HighQualified && close > RangeHigh)
			{
				HighQualified = true;
				return false;
			}
			TouchQualified |= HighQualified && low <= Vwap && high >= Vwap;
			bool flag6 = HighQualified && TouchQualified && close > Vwap && adx > 20.0 && adx <= previousAdx;
			Reclaimed |= flag6;
			return flag6;
		}
	}

	private sealed class Bracket
	{
		public string StopName;

		public string TargetName;

		public Order Stop;

		public Order Target;
	}

	internal sealed class WilderAdx
	{
		private Candle previous;

		private int index = -1;

		private double tr;

		private double plus;

		private double minus;

		public double Value { get; private set; }

		public double Previous { get; private set; }

		public double Atr { get; private set; }

		public bool Ready => index >= 14;

		public bool Eligible => Ready && Value > 20.0 && Value <= Previous;

		public void Push(Candle bar)
		{
			index++;
			Previous = Value;
			double num = bar.High - bar.Low;
			if (previous == null)
			{
				tr = num;
				Value = 50.0;
				Atr = num;
				previous = bar.Clone();
				return;
			}
			num = Math.Max(num, Math.Max(Math.Abs(bar.High - previous.Close), Math.Abs(bar.Low - previous.Close)));
			double num2 = bar.High - previous.High;
			double num3 = previous.Low - bar.Low;
			num2 = ((num2 > num3 && num2 > 0.0) ? num2 : 0.0);
			num3 = ((num3 > bar.High - previous.High && num3 > 0.0) ? num3 : 0.0);
			int num4 = Math.Min(index + 1, 14);
			Atr = ((double)(num4 - 1) * Atr + num) / (double)num4;
			if (index < 14)
			{
				tr += num;
				plus += num2;
				minus += num3;
			}
			else
			{
				tr = tr - tr / 14.0 + num;
				plus = plus - plus / 14.0 + num2;
				minus = minus - minus / 14.0 + num3;
			}
			double num5 = ((plus + minus > 0.0) ? (100.0 * Math.Abs(plus - minus) / (plus + minus)) : 50.0);
			Value = ((plus + minus > 0.0) ? ((13.0 * Value + num5) / 14.0) : 50.0);
			previous = bar.Clone();
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

	private WilderAdx adx;

	private PullbackSetup setup;

	private double plannedDistance;

	private const double TargetMultiple = 1.27;

	private const double TrailActivationR = 1.0;

	private const double TrailDistanceR = 0.25;

	private const double TrailStepR = 0.25;

	private double trailPeakClose;

	private int trailConfirmations;

	private bool trailArmed;

	private DateTime trailEntryStart;

	private DateTime trailLastSourceStart = DateTime.MinValue;

	private DateTime drawnRangeDay;

	private string drawnEntry;

	private readonly VWAPPullbackADX.AdxHistory vwapHistory = new VWAPPullbackADX.AdxHistory();

	private VWAPPullbackADX displayAdx;

	private TimeZoneInfo platformZone;

	private TimeZoneInfo centralZone;

	private TimeZoneInfo nyZone;

	private System.Timers.Timer timer;

	private StreamWriter log;

	private DateTime lastMinute;

	private DateTime latestCentral;

	private DateTime sessionDay;

	private DateTime startupFloor;

	private int consumedSourceIndex = -1;

	private BarsRequest historyRepair;

	private DateTime repairRetry;

	private DateTime recoveryFloor;

	private bool sourceFresh = true;

	private int executionSeries = 1;

	private int signalSeries = 1;

	private string signalContract;

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

	private double actualFees;

	private double tradeModeledCost;

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

	private bool VisualsSuppressed => VisualFaultReason() != null;

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
		if (State != State.Realtime)
		{
			return null;
		}
		if (Account == null || Account.ConnectionStatus != ConnectionStatus.Connected)
		{
			return "Account disconnected; orders paused";
		}
		if (recoveryFault)
		{
			return status;
		}
		if (recoveryPending || reconcilingRecovery)
		{
			return (status != null && status.StartsWith("Recovery pending:", StringComparison.Ordinal)) ? status : "Reconciling owned broker orders; trading paused";
		}
		if (suspended || closeRejected)
		{
			return status;
		}
		if (CurrentBars == null || signalSeries >= CurrentBars.Length || executionSeries >= CurrentBars.Length || CurrentBars[signalSeries] < 0 || CurrentBars[executionSeries] < 0)
		{
			return "Required M1 history unavailable; trading paused";
		}
		if (visualHistoryWaiting || historyRepair != null)
		{
			return status;
		}
		if (adx != null && !adx.Ready)
		{
			return "Completed M1 ADX history unavailable; trading paused";
		}
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
				if (displayAdx != null)
				{
					displayAdx.IsVisible = !visualsSuppressed;
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

	private void DrawExecution(ExecutionView trade, DateTime now)
	{
		if (ShowVisuals && trade != null)
		{
			bool flag = trade.Exited != DateTime.MinValue;
			DateTime ct = (flag ? trade.Exited : now);
			double num = (double)trade.Side * (trade.Exit - trade.Entry);
			double num2 = ((flag && num <= 0.0) ? trade.Exit : trade.InitialStop);
			VWAPPullbackNT8 strategy = this;
			string tag = trade.Tag;
			bool isLong = trade.Side > 0;
			double entry = trade.Entry;
			double slPx = num2;
			double tpPx;
			if (flag)
			{
				tpPx = ((num > 0.0) ? trade.Exit : 0.0);
			}
			else
			{
				tpPx = trade.Target;
			}
			PullbackExecutionVisual.DrawExecutionTool(strategy, tag, isLong, entry, slPx, tpPx, trade.Entry, Platform(trade.Entered), Platform(trade.Entered), Platform(ct), trailing: false, DateTime.MinValue, synthetic: false);
			if (trade.Trailing)
			{
				PullbackExecutionVisual.DrawBoundedLine(this, trade.Tag + "_TRAIL", Platform(trade.TrailStart), trade.Stop, Platform(ct), trade.Stop, PullbackExecutionVisual.ClrTrailingStop, DashStyleHelper.Dot, 2);
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
				if (!hashSet.Contains(closedVisual.Tag + "_SL"))
				{
					DrawExecution(closedVisual, closedVisual.Exited);
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
			Name = "VWAPPullbackNT8";
			Description = "VWAPPullbackNT8 - Intraday session VWAP pullback strategy. Arms from 09:50 Central with a non-rising ADX(14) filter, 3x ATR stop, 1.27R target, two-close break-even trigger at 1R and a 0.25R stepped trail. Copyright 2026-2027, Osamwonyi Eric (@You_FoundEric). Developed by @You_FoundEric. Unauthorized redistribution prohibited.";
			Calculate = Calculate.OnEachTick;
			IsUnmanaged = true;
			StartBehavior = StartBehavior.ImmediatelySubmit;
			IsExitOnSessionCloseStrategy = false;
			RealtimeErrorHandling = RealtimeErrorHandling.IgnoreAllErrors;
			ConnectionLossHandling = ConnectionLossHandling.KeepRunning;
			BarsRequiredToTrade = 0;
			Slippage = 1.0;
			IsInstantiatedOnEachOptimizationIteration = true;
			OrderFillResolution = OrderFillResolution.Standard;
			StopTargetHandling = StopTargetHandling.PerEntryExecution;
			TimeInForce = TimeInForce.Gtc;
			IsOverlay = true;
			DrawOnPricePanel = true;
			MaximumBarsLookBack = MaximumBarsLookBack.Infinite;
			IsFillLimitOnTouch = true;
			AddPlot(new Stroke(Brushes.DeepSkyBlue, DashStyleHelper.Dot, 1f), PlotStyle.Line, "Session VWAP");
			EnableTrading = true;
			BlockOpposingExposure = true;
			RiskMoney = 500.0;
			UseFixedSize = true;
			FixedContracts = 1;
			CommissionPerContract = 3.0;
			SlippagePoints = 3;
			ShowVisuals = true;
			WriteTradeLog = false;
		}
		else if (State == State.Configure)
		{
			if (StartBehavior != StartBehavior.ImmediatelySubmit)
			{
				throw new InvalidOperationException("ImmediatelySubmit is required for ownership isolation.");
			}
			if (RiskMoney <= 0.0 || double.IsNaN(RiskMoney) || double.IsInfinity(RiskMoney) || FixedContracts <= 0)
			{
				throw new InvalidOperationException("Risk must be positive and finite; fixed contract quantity must be positive.");
			}
			IncludeTradeHistoryInBacktest = true;
			signalContract = SourceContract(Instrument);
			executionSeries = (signalSeries = 1);
			if (!Instrument.MasterInstrument.Name.Trim().Equals("NQ", StringComparison.OrdinalIgnoreCase))
			{
				AddDataSeries(signalContract, new BarsPeriod
				{
					BarsPeriodType = BarsPeriodType.Minute,
					Value = 1
				}, "CME US Index Futures ETH", true);
				AddDataSeries(Instrument.FullName, new BarsPeriod
				{
					BarsPeriodType = BarsPeriodType.Minute,
					Value = 1
				}, "CME US Index Futures ETH", true);
				executionSeries = 2;
			}
			else
			{
				AddDataSeries(Instrument.FullName, new BarsPeriod
				{
					BarsPeriodType = BarsPeriodType.Minute,
					Value = 1
				}, "CME US Index Futures ETH", true);
			}
		}
		else if (State == State.DataLoaded)
		{
			minutes = new SortedDictionary<DateTime, Candle>();
			orders = new Dictionary<string, Order>();
			processed = new Dictionary<string, int>();
			executions = new HashSet<string>();
			brackets = new List<Bracket>();
			adx = new WilderAdx();
			setup = new PullbackSetup();
			platformZone = Globals.GeneralOptions.TimeZoneInfo;
			centralZone = TimeZoneInfo.FindSystemTimeZoneById("Central Standard Time");
			nyZone = TimeZoneInfo.FindSystemTimeZoneById("Eastern Standard Time");
			owner = "VWP_" + Guid.NewGuid().ToString("N").Substring(0, 12);
			PrepareRecovery();
			string text = ExecutionInstrument.MasterInstrument.Name.ToUpperInvariant();
			if (text != "NQ" && text != "MNQ" && text != "NNQ")
			{
				throw new InvalidOperationException("Use NQ, MNQ or NNQ; selected " + ExecutionInstrument.FullName + ".");
			}
			if (ExecutionInstrument.MasterInstrument.PointValue <= 0.0 || ExecutionInstrument.MasterInstrument.TickSize <= 0.0)
			{
				throw new InvalidOperationException("Invalid contract specification.");
			}
			if (executionSeries == 2 && (BarsArray.Length < 3 || BarsArray[1].Instrument.FullName != signalContract || BarsArray[2].Instrument.FullName != ExecutionInstrument.FullName))
			{
				throw new InvalidOperationException("NQ signal / NNQ execution series mismatch; trading blocked.");
			}
			if (ShowVisuals)
			{
				displayAdx = VWAPPullbackModelDisplay();
				displayAdx.IsOverlay = false;
				displayAdx.Panel = 1;
				AddChartIndicator(displayAdx);
			}
			if (WriteTradeLog)
			{
				string text2 = Path.Combine(Globals.UserDataDir, "VWAPPullback", "logs");
				Directory.CreateDirectory(text2);
				log = new StreamWriter(Path.Combine(text2, owner + ".csv"))
				{
					AutoFlush = true
				};
				log.WriteLine("event,central_time,detail");
			}
		}
		else if (State == State.Transition)
		{
			if (ownedNet != 0 || entryPending || orders.Values.Any((Order o) => !Settled(o) || !ExecutionsCaughtUp(o)))
			{
				throw new InvalidOperationException("Historical owned exposure must be flat before realtime.");
			}
		}
		else if (State == State.Realtime)
		{
			startupArmed = false;
			ownerKey = ((Account == null) ? "" : Account.Name) + "|" + ExecutionInstrument.FullName;
			exposureKey = ((Account == null) ? "unknown" : Account.Name) + "|" + ExecutionInstrument.FullName;
			lock (ownerLock)
			{
				ownsGuard = activeOwners.Add(ownerKey);
			}
			if (!ownsGuard)
			{
				suspended = true;
				status = "Another VWAP instance owns this account/instrument";
			}
			startupFloor = Central(NativeNow());
			StartRecovery();
			if (!recoveredTrade && Account != null && Account.Positions.Any((Position p) => p.Instrument.FullName == ExecutionInstrument.FullName && p.Quantity != 0))
			{
				suspended = true;
				status = "Existing account exposure: new entries blocked";
			}
			timer = new System.Timers.Timer(1000.0);
			timer.AutoReset = true;
			timer.Elapsed += (object s, ElapsedEventArgs e) =>
			{
				try
				{
					TriggerCustomEvent((object o) =>
					{
						TimerStep();
					}, null);
				}
				catch
				{
				}
			};
			timer.Start();
		}
		else
		{
			if (State != State.Terminated)
			{
				return;
			}
			StopRecovery();
			HookDashboardMouse(attach: false);
			if (historyRepair != null)
			{
				historyRepair.Dispose();
				historyRepair = null;
			}
			if (ownedNet == 0 && !entryPending && (orders == null || orders.Values.All((Order o) => Settled(o) && ExecutionsCaughtUp(o))))
			{
				ReleaseExposure();
			}
			if (ownsGuard)
			{
				lock (ownerLock)
				{
					activeOwners.Remove(ownerKey);
				}
				ownsGuard = false;
			}
			if (timer != null)
			{
				timer.Stop();
				timer.Dispose();
				timer = null;
			}
			if (log != null)
			{
				log.Dispose();
				log = null;
			}
		}
	}

	internal static string SourceContract(Instrument instrument)
	{
		string text = instrument.MasterInstrument.Name.Trim().ToUpperInvariant();
		if (text != "NQ" && text != "MNQ" && text != "NNQ")
		{
			throw new InvalidOperationException("Use NQ, MNQ or NNQ.");
		}
		return "NQ" + instrument.FullName.Substring(instrument.MasterInstrument.Name.Length);
	}

	private DateTime Central(DateTime platform)
	{
		return TimeZoneInfo.ConvertTime(DateTime.SpecifyKind(platform, DateTimeKind.Unspecified), platformZone, centralZone);
	}

	private DateTime Platform(DateTime ct)
	{
		return TimeZoneInfo.ConvertTime(DateTime.SpecifyKind(ct, DateTimeKind.Unspecified), centralZone, platformZone);
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
			recoveryIdentity = text + "|" + Account.Name + "|" + ExecutionInstrument.FullName + "|VWAP3ATR1_27R_twoCloseTrail";
			string text2 = recoveryIdentity;
			char[] invalidFileNameChars = Path.GetInvalidFileNameChars();
			foreach (char oldChar in invalidFileNameChars)
			{
				text2 = text2.Replace(oldChar, '_');
			}
			recoveryPath = Path.Combine(Globals.UserDataDir, "VWAPPullback", "recovery", text2 + ".journal");
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
				if (binaryReader.ReadString() != "IndependentNT8.v1" || binaryReader.ReadString() != recoveryIdentity)
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
				entered = binaryReader.ReadInt32();
				exited = binaryReader.ReadInt32();
				entryPending = binaryReader.ReadBoolean();
				entrySum = binaryReader.ReadDouble();
				exitSum = binaryReader.ReadDouble();
				plannedDistance = binaryReader.ReadDouble();
				plannedStop = binaryReader.ReadDouble();
				plannedTarget = binaryReader.ReadDouble();
				initialRisk = binaryReader.ReadDouble();
				actualFees = binaryReader.ReadDouble();
				tradeModeledCost = binaryReader.ReadDouble();
				closeReason = binaryReader.ReadString();
				if (closeReason == "")
				{
					closeReason = null;
				}
				trailPeakClose = binaryReader.ReadDouble();
				trailConfirmations = binaryReader.ReadInt32();
				trailArmed = binaryReader.ReadBoolean();
				trailEntryStart = new DateTime(binaryReader.ReadInt64());
				trailLastSourceStart = new DateTime(binaryReader.ReadInt64());
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
				binaryWriter.Write("IndependentNT8.v1");
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
				binaryWriter.Write(entered);
				binaryWriter.Write(exited);
				binaryWriter.Write(entryPending);
				binaryWriter.Write(entrySum);
				binaryWriter.Write(exitSum);
				binaryWriter.Write(plannedDistance);
				binaryWriter.Write(plannedStop);
				binaryWriter.Write(plannedTarget);
				binaryWriter.Write(initialRisk);
				binaryWriter.Write(actualFees);
				binaryWriter.Write(tradeModeledCost);
				binaryWriter.Write(closeReason ?? "");
				binaryWriter.Write(trailPeakClose);
				binaryWriter.Write(trailConfirmations);
				binaryWriter.Write(trailArmed);
				binaryWriter.Write(trailEntryStart.Ticks);
				binaryWriter.Write(trailLastSourceStart.Ticks);
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
				File.Replace(text, recoveryPath, null);
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
		if ((State != State.Historical && State != State.Transition && State != State.Realtime) || adx == null || setup == null || platformZone == null || centralZone == null || nyZone == null || CurrentBars == null || BarsArray == null || BarsInProgress < 0 || BarsInProgress >= CurrentBars.Length || BarsInProgress >= BarsArray.Length || BarsArray[0] == null || BarsArray[BarsInProgress] == null)
		{
			return;
		}
		if (State == State.Realtime && !ObserveBrokerConnection(Central(NativeNow())))
		{
			UpdatePanel();
		}
		else if (BarsInProgress == 0)
		{
			if (CurrentBars[0] >= 0)
			{
				PaintVwap();
				if (State != State.Historical || CurrentBars[0] == BarsArray[0].Count - 1)
				{
					UpdatePanel();
				}
			}
		}
		else if (BarsInProgress == signalSeries && CurrentBars[signalSeries] >= 0)
		{
			ConsumeSource();
		}
	}

	private void PaintVwap()
	{
		if (CurrentBars[0] >= 0)
		{
			DateTime end = Central(Times[0][0]);
			double num = vwapHistory.At(end, double.NaN);
			if (ShowVisuals && end.TimeOfDay.TotalMinutes > 510.0 && end.TimeOfDay.TotalMinutes <= 955.0 && !double.IsNaN(num))
			{
				Values[0][0] = num;
			}
			else
			{
				Values[0].Reset();
			}
		}
	}

	private void ConsumeSource()
	{
		if (historyRepair != null || State == State.Terminated)
		{
			return;
		}
		int num = ((State == State.Historical) ? CurrentBars[signalSeries] : (BarsArray[signalSeries].Count - 2));
		for (int i = consumedSourceIndex + 1; i <= num; i++)
		{
			DateTime dateTime = Central(BarsArray[signalSeries].GetTime(i));
			if (dateTime <= lastMinute)
			{
				consumedSourceIndex = i;
				continue;
			}
			DateTime dateTime2 = dateTime.AddMinutes(-1.0);
			bool flag = lastMinute != DateTime.MinValue && dateTime2 > lastMinute && lastMinute >= dateTime2.Date.AddMinutes(510.0) && lastMinute < dateTime2.Date.AddMinutes(Cutoff(dateTime2.Date));
			if ((State == State.Realtime) & flag)
			{
				RequestSourceRepair((dateTime2 < dateTime2.Date.AddMinutes(Cutoff(dateTime2.Date))) ? dateTime2 : dateTime2.Date.AddMinutes(Cutoff(dateTime2.Date)));
				break;
			}
			DateTime dateTime3 = Central(NativeNow());
			bool fresh = State == State.Historical || (i == num && dateTime > recoveryFloor && dateTime >= new DateTime(dateTime3.Year, dateTime3.Month, dateTime3.Day, dateTime3.Hour, dateTime3.Minute, 0));
			ProcessSource(new Candle(dateTime2, BarsArray[signalSeries].GetOpen(i), BarsArray[signalSeries].GetHigh(i), BarsArray[signalSeries].GetLow(i), BarsArray[signalSeries].GetClose(i), BarsArray[signalSeries].GetVolume(i)), fresh);
			consumedSourceIndex = i;
			if (historyRepair != null)
			{
				break;
			}
		}
	}

	private void ProcessSource(Candle bar, bool fresh)
	{
		DateTime end = bar.Start.AddMinutes(1.0);
		sourceFresh = fresh;
		lastMinute = (latestCentral = end);
		minutes[bar.Start] = bar;
		DateTime[] array = minutes.Keys.TakeWhile((DateTime k) => k < end.AddDays(-3.0)).ToArray();
		foreach (DateTime key in array)
		{
			minutes.Remove(key);
		}
		if (bar.Start.Date != sessionDay)
		{
			ResetDay(bar.Start.Date);
		}
		SaveRecovery();
		adx.Push(bar);
		averageATR = adx.Atr;
		bool highQualified = setup.HighQualified;
		bool touchQualified = setup.TouchQualified;
		bool reclaimed = setup.Reclaimed;
		bool flag = setup.Observe(bar.Start, bar.High, bar.Low, bar.Close, bar.Volume, adx.Value, adx.Previous);
		if (log != null && ((!highQualified && setup.HighQualified) || (!touchQualified && setup.TouchQualified) || (!reclaimed & flag)))
		{
			Record("GATE", bar.Start, "H=" + setup.HighQualified + " V=" + setup.TouchQualified + " R=" + setup.Reclaimed + " fresh=" + fresh + " close=" + F(bar.Close) + " high=" + F(bar.High) + " low=" + F(bar.Low) + " volume=" + bar.Volume + " rangeHigh=" + F(setup.RangeHigh) + " vwap=" + F(setup.Vwap) + " adx=" + F(adx.Value) + " priorAdx=" + F(adx.Previous) + " atr=" + F(adx.Atr));
		}
		rangeHigh = setup.RangeHigh;
		rangeLow = setup.RangeLow;
		readyRange = setup.RangeReady;
		validDay = readyRange;
		vwapHistory.Store(end, (bar.Start.TimeOfDay.TotalMinutes >= 510.0 && end.TimeOfDay.TotalMinutes <= 955.0) ? setup.Vwap : double.NaN);
		if (displayAdx != null)
		{
			displayAdx.Publish(adx.Value, adx.Previous, adx.Ready, end);
		}
		if (ShowVisuals && !VisualsSuppressed)
		{
			string text = "VWP_" + bar.Start.ToString("yyyyMMddHHmm");
			if (!highQualified && setup.HighQualified)
			{
				Draw.Text(this, text + "H", isAutoScale: false, "H", Platform(end), bar.Low - ExecutionInstrument.MasterInstrument.TickSize * 2.0, 0, Brushes.DeepSkyBlue, new SimpleFont("Segoe UI", 9), System.Windows.TextAlignment.Center, Brushes.Transparent, Brushes.Transparent, 0);
			}
			if (!touchQualified && setup.TouchQualified)
			{
				Draw.Text(this, text + "V", isAutoScale: false, "V", Platform(end), bar.Low - ExecutionInstrument.MasterInstrument.TickSize * 4.0, 0, Brushes.DeepSkyBlue, new SimpleFont("Segoe UI", 9), System.Windows.TextAlignment.Center, Brushes.Transparent, Brushes.Transparent, 0);
			}
			if (!reclaimed & flag & fresh)
			{
				Draw.Text(this, text + "R", isAutoScale: false, "R", Platform(end), bar.Low - ExecutionInstrument.MasterInstrument.TickSize * 6.0, 0, Brushes.DeepSkyBlue, new SimpleFont("Segoe UI", 9), System.Windows.TextAlignment.Center, Brushes.Transparent, Brushes.Transparent, 0);
			}
			if (CurrentBars[0] >= 0 && Central(Times[0][0]) >= end)
			{
				PaintVwap();
			}
		}
		if (State == State.Realtime && !startupArmed)
		{
			startupArmed = true;
		}
		if (flag && State == State.Realtime && (!fresh || end <= startupFloor || end <= recoveryFloor))
		{
			setup.Consume();
		}
		if (end.TimeOfDay.TotalMinutes >= 955.0)
		{
			BeginClose("Time");
		}
		else if (flag)
		{
			Signal(end, bar.Close);
		}
		if (end.TimeOfDay.TotalMinutes < 955.0)
		{
			Trail(bar, end);
		}
		if (ownedNet == 0 && !entryPending && entryCount == 0)
		{
			ref string reference = ref status;
			string text2;
			if (setup.Consumed)
			{
				text2 = "Setup passed | no stale entry";
			}
			else if (readyRange)
			{
				if (setup.HighQualified)
				{
					if (setup.TouchQualified)
					{
						text2 = ((!flag) ? "Waiting for reclaim + ADX" : status);
					}
					else
					{
						text2 = "H armed | waiting for VWAP";
					}
				}
				else
				{
					text2 = "Waiting for 09:50 range close";
				}
			}
			else
			{
				text2 = "Opening range forming";
			}
			reference = text2;
		}
		if (ShowVisuals)
		{
			Levels(end);
		}
		SaveRecovery();
	}

	private void RequestSourceRepair(DateTime missingRight)
	{
		visualHistoryWaiting = true;
		DateTime dateTime = Central(NativeNow());
		DateTime missingLeft = lastMinute;
		status = "Reloading provider M1 " + missingLeft.ToString("HH:mm") + " to " + missingRight.ToString("HH:mm") + " Central; new entries paused";
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
		Print("VWAP M1 reload: " + missingLeft.ToString("s") + " to " + missingRight.ToString("s") + " Central");
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
							DateTime dateTime2 = Central(reply.Bars.GetTime(i)).AddMinutes(-1.0);
							if (dateTime2 >= missingLeft && dateTime2 < missingRight)
							{
								recovered.Add(new Candle(dateTime2, reply.Bars.GetOpen(i), reply.Bars.GetHigh(i), reply.Bars.GetLow(i), reply.Bars.GetClose(i), reply.Bars.GetVolume(i)));
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
								status = "Provider M1 unavailable at " + dateTime3.ToString("yyyy-MM-dd HH:mm") + " Central; retrying";
								Print("VWAP " + status + " " + message);
							}
							else
							{
								visualHistoryWaiting = false;
								recoveryFloor = Central(NativeNow());
								foreach (Candle item2 in recovered)
								{
									ProcessSource(item2, fresh: false);
								}
								status = "M1 history recovered; waiting for a fresh M1 close";
								Print("VWAP M1 recovered " + recovered.Count + " bars; old signals suppressed");
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
			Print("VWAP " + status + ": " + ex.Message);
		}
	}

	private void ResetDay(DateTime day)
	{
		sessionDay = day;
		validDay = (readyRange = false);
		entryCount = 0;
		if (ownedNet == 0 && !entryPending)
		{
			closing = false;
			closeReason = null;
		}
		else
		{
			suspended = true;
			BeginClose("SessionBoundary");
		}
	}

	private bool CanReplayCompletedSession(DateTime day)
	{
		if (State != State.Historical || IsInStrategyAnalyzer)
		{
			return true;
		}
		Bars bars = BarsArray[executionSeries];
		return day != DateTime.MinValue && bars.Count > 0 && Central(bars.GetTime(bars.Count - 1)) >= day.Date.AddMinutes(Cutoff(day) + 2);
	}

	private void Signal(DateTime end, double close)
	{
		if ((State == State.Realtime && (recoveryPending || recoveryFault)) || !CanReplayCompletedSession(sessionDay) || suspended || closing || !EnableTrading || !sourceFresh || !validDay || !readyRange || entryCount >= 1 || entryPending || ownedNet != 0 || !adx.Ready || !SignalTime(end.TimeOfDay.TotalMinutes) || end.Date != sessionDay || end.TimeOfDay.TotalMinutes >= (double)Cutoff(sessionDay) || latestCentral.TimeOfDay.TotalMinutes >= (double)Cutoff(sessionDay) || (State == State.Realtime && (!startupArmed || end <= startupFloor)))
		{
			return;
		}
		if (State == State.Realtime && Account != null && Account.Positions.Any((Position p) => p.Instrument.FullName == ExecutionInstrument.FullName && p.Quantity != 0))
		{
			status = "Other account exposure: new entry blocked";
			return;
		}
		int num = 1;
		Record("SIGNAL", end, "close=" + F(close) + " ADX=" + F(adx.Value) + " side=" + num);
		if (num == 0)
		{
			return;
		}
		if (CurrentBars[executionSeries] < 0)
		{
			status = "Waiting for execution-instrument M1 history";
			return;
		}
		if (State == State.Realtime && Central(NativeNow()) - Central(Times[executionSeries][0]).AddMinutes(-1.0) > TimeSpan.FromMinutes(2.0))
		{
			status = "Execution feed stale | new entries paused";
			return;
		}
		double num2;
		if (State != State.Realtime)
		{
			num2 = Closes[executionSeries][0];
		}
		else
		{
			num2 = ((num > 0) ? GetCurrentAsk(executionSeries) : GetCurrentBid(executionSeries));
		}
		if (num2 <= 0.0)
		{
			return;
		}
		plannedDistance = 3.0 * adx.Atr;
		double tickSize = ExecutionInstrument.MasterInstrument.TickSize;
		plannedStop = Math.Ceiling((num2 - plannedDistance) / tickSize - 1E-09) * tickSize;
		plannedTarget = Math.Floor((num2 + 1.27 * (num2 - plannedStop)) / tickSize + 1E-09) * tickSize;
		if (!(plannedStop >= num2) && !(plannedTarget <= num2))
		{
			double num3 = Math.Abs(num2 - plannedStop) * ExecutionInstrument.MasterInstrument.PointValue + CostPerContract;
			int num4 = (UseFixedSize ? FixedContracts : Quantity(RiskMoney, num3));
			if (num4 < 1)
			{
				status = "One contract needs $" + num3.ToString("0.00", CultureInfo.InvariantCulture) + "; risk $" + F(RiskMoney);
				Record("SKIP_RISK", end, F(num3));
			}
			else if (State != State.Realtime || AcquireExposure(num))
			{
				entryCount++;
				setup.Consume();
				entryPending = true;
				entered = (exited = (ownedNet = 0));
				entrySum = (exitSum = (actualFees = 0.0));
				tradeModeledCost = CostPerContract;
				trailPeakClose = 0.0;
				trailConfirmations = 0;
				trailArmed = false;
				trailLastSourceStart = DateTime.MinValue;
				brackets.Clear();
				closeReason = null;
				string text = owner;
				int num5 = ++sequence;
				entryName = text + "_Entry_" + num5;
				status = "Entry submitted";
				SubmitOwnedOrder(executionSeries, (num <= 0) ? OrderAction.SellShort : OrderAction.Buy, OrderType.Market, num4, 0.0, 0.0, string.Empty, entryName);
			}
		}
	}

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

	internal static double TrailLevel(double entry, double risk, double peak, double cost, double tick)
	{
		return Math.Ceiling(Math.Max(entry + cost, peak - 0.25 * risk) / tick - 1E-09) * tick;
	}

	private void Trail(Candle bar, DateTime end)
	{
		if (ownedNet <= 0 || entered <= 0 || closing || initialRisk <= 0.0 || bar.Start < trailEntryStart || bar.Start <= trailLastSourceStart || !BrokerReady())
		{
			return;
		}
		double num = entrySum / (double)entered;
		trailPeakClose = Math.Max(trailPeakClose, bar.Close);
		trailConfirmations = ((bar.Close - num >= 1.0 * initialRisk) ? (trailConfirmations + 1) : 0);
		trailLastSourceStart = bar.Start;
		if (trailConfirmations >= 2)
		{
			trailArmed = true;
		}
		if (!sourceFresh || !trailArmed)
		{
			return;
		}
		double num2 = TrailLevel(num, initialRisk, trailPeakClose, tradeModeledCost / ExecutionInstrument.MasterInstrument.PointValue, ExecutionInstrument.MasterInstrument.TickSize);
		Bracket[] array = brackets.ToArray();
		foreach (Bracket bracket in array)
		{
			Order stop = bracket.Stop;
			if (stop != null && (stop.OrderState == OrderState.Working || stop.OrderState == OrderState.Accepted) && !(num2 - stop.StopPrice < 0.25 * initialRisk - 1E-09))
			{
				if (num2 >= bar.Close || (State == State.Realtime && GetCurrentBid(executionSeries) <= num2))
				{
					BeginClose("TrailCrossed");
					break;
				}
				ChangeOwnedOrder(stop, stop.Quantity, 0.0, num2);
				Record("TRAIL", end, "stop=" + F(num2) + " peakClose=" + F(trailPeakClose));
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

	internal static int Bias(double open, double low, double high)
	{
		if (high <= low || open <= low || open >= high)
		{
			return 0;
		}
		return (open > low + 2.0 * (high - low) / 3.0) ? 1 : ((open < low + (high - low) / 3.0) ? (-1) : 0);
	}

	internal static bool SignalTime(double minute)
	{
		return minute >= 591.0 && minute < 955.0;
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
			!string.IsNullOrEmpty(nativeError) &&
			(nativeError.IndexOf("liquidation only", StringComparison.OrdinalIgnoreCase) >= 0 ||
			 nativeError.IndexOf("liquidation-only", StringComparison.OrdinalIgnoreCase) >= 0 ||
			 nativeError.IndexOf("low net liquidating value", StringComparison.OrdinalIgnoreCase) >= 0))
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
			Complete(Central(time));
		}
	}

	protected override void OnExecutionUpdate(Execution execution, string executionId, double price, int quantity, MarketPosition marketPosition, string orderId, DateTime time)
	{
		if (execution == null || execution.Order == null || !execution.Order.Name.StartsWith(owner + "_") || ReconcileOwnedExecution(execution, executionId))
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
			if (entered == 0)
			{
				double tickSize = ExecutionInstrument.MasterInstrument.TickSize;
				plannedStop = Math.Ceiling((price - plannedDistance) / tickSize - 1E-09) * tickSize;
				plannedTarget = Math.Floor((price + 1.27 * (price - plannedStop)) / tickSize + 1E-09) * tickSize;
				trailEntryStart = ((State == State.Historical) ? Central(time).AddMinutes(-1.0) : Central(time));
				trailLastSourceStart = DateTime.MinValue;
			}
			entered += quantity;
			entrySum += price * (double)quantity;
			initialRisk = Math.Abs(entrySum / (double)entered - plannedStop);
			if (initialRisk <= 0.0 || (double)num * (price - plannedStop) <= 0.0 || (double)num * (plannedTarget - price) <= 0.0)
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
					Target = plannedTarget,
					Entered = Central(time)
				};
			}
			executionVisual.Entry = entrySum / (double)entered;
			DrawExecution(executionVisual, Central(time));
			CheckActualFillRisk();
			Record("ENTRY", Central(time), "price=" + F(price) + " qty=" + quantity + " stop=" + F(plannedStop) + ";tradeId=" + entryName + ";executionId=" + executionId + ";time=" + Central(time).ToString("s") + ";direction=" + ((num > 0) ? "Long" : "Short") + ";quantity=" + quantity + ";initialStop=" + F(plannedStop) + ";initialTarget=" + F(plannedTarget));
			status = (closing ? "Closing owned position" : "Owned position protected");
		}
		else
		{
			exited += quantity;
			exitSum += price * (double)quantity;
			Record("EXIT", Central(time), order.Name + " price=" + F(price) + " qty=" + quantity + ";tradeId=" + entryName + ";executionId=" + executionId + ";time=" + Central(time).ToString("s") + ";direction=" + ((plannedStop < entrySum / (double)entered) ? "Long" : "Short") + ";quantity=" + quantity + ";initialStop=" + F(plannedStop));
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
			Complete(Central(time));
		}
	}

	private void Complete(DateTime time)
	{
		string[] array = new string[3] { "Original stop", "Entry", "Target" };
		foreach (string text in array)
		{
			RemoveDrawObject("VWP_" + sessionDay.ToString("yyyyMMdd") + "_" + text);
		}
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
		if (WriteTradeLog)
		{
			Print(Name + " trade closed: gross=" + F(num3) + " modeled net=" + F(value) + " actual commission=" + F(actualFees));
		}
		Record("CLOSE", time, "gross=" + F(num3) + " modeledNet=" + F(value));
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
		if (ownedNet != 0 || entryPending || !orders.Values.All((Order o) => Settled(o) && ExecutionsCaughtUp(o)))
		{
			closing = true;
			closeReason = reason;
			SaveRecovery();
			DriveClose();
		}
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

	private void TimerStep()
	{
		if (State == State.Realtime)
		{
			DateTime dateTime = Central(NativeNow());
			bool flag = ObserveBrokerConnection(dateTime);
			if (ownedNet != 0 && dateTime >= sessionDay.AddMinutes(Cutoff(sessionDay)))
			{
				BeginClose("Time");
			}
			if (flag)
			{
				CheckActualFillRisk();
				DriveClose();
				ConsumeSource();
			}
			UpdatePanel();
		}
	}

	private void Record(string evt, DateTime ct, string detail)
	{
		if (log != null)
		{
			log.WriteLine(evt + "," + ct.ToString("yyyy-MM-dd HH:mm:ss") + "," + detail.Replace(",", ";"));
		}
	}

	private static string F(double value)
	{
		return value.ToString("0.########", CultureInfo.InvariantCulture);
	}

	private void UpdatePanel()
	{
		SyncFaultVisuals();
		if (ShowVisuals)
		{
			DateTime dateTime = ((State == State.Realtime) ? Central(NativeNow()) : latestCentral);
			DateTime dateTime2 = TimeZoneInfo.ConvertTime(DateTime.SpecifyKind(dateTime, DateTimeKind.Unspecified), centralZone, nyZone);
			PaintHistoricalExecutions(dateTime);
			dashboard.Publish(new ModelDashState
			{
				Title = "VWAP Pullback",
				Clock = "NY: " + dateTime2.ToString("HH:mm:ss") + " CT: " + dateTime.ToString("HH:mm:ss"),
				Status = (VisualFaultReason() ?? status),
				NewsBlocked = (connectionPaused || suspended),
				RangeCaption = "OPENING RANGE | 08:30-09:00 CT",
				HighCaption = "HIGH",
				LowCaption = "LOW",
				RangeHigh = (readyRange ? F(rangeHigh) : "--"),
				RangeLow = (readyRange ? F(rangeLow) : "--"),
				RangeWidth = (readyRange ? F(rangeHigh - rangeLow) : "--"),
				InTrade = (ownedNet != 0 && !recoveryPending && !recoveryFault),
				Position = ((recoveryPending || recoveryFault) ? "UNVERIFIED" : ((ownedNet == 0) ? "FLAT" : (Math.Abs(ownedNet) + ((ownedNet > 0) ? " LONG" : " SHORT")))),
				Stop = ((!recoveryPending && !recoveryFault && brackets.Count > 0 && brackets[0].Stop != null) ? F(brackets[0].Stop.StopPrice) : "--"),
				Risk = "Trades " + entryCount + "/1 | " + (UseFixedSize ? ("Fixed " + FixedContracts + " contracts") : ("Risk $" + F(RiskMoney))),
				Costs = "Cost/contract: $" + F(CostPerContract) + " | Slip " + SlippagePoints,
				History = "ADX " + adx.Value.ToString("0.00", CultureInfo.InvariantCulture) + " | " + (setup.HighQualified ? "H" : "-") + (setup.TouchQualified ? "V" : "-") + (setup.Reclaimed ? "R" : "-") + ((signalSeries != executionSeries) ? (" | NQ -> " + ExecutionInstrument.MasterInstrument.Name) : "")
			});
			if (State == State.Realtime)
			{
				RequestDashboardRender();
			}
		}
	}

	private void Level(string tag, DateTime left, DateTime right, double price, System.Windows.Media.Brush brush)
	{
		if (!VisualsSuppressed && right > left && price > 0.0)
		{
			Draw.Line(this, "VWP_" + sessionDay.ToString("yyyyMMdd") + "_" + tag, isAutoScale: false, Platform(left), price, Platform(right), price, brush, DashStyleHelper.Dash, 1);
		}
	}

	private void Levels(DateTime now)
	{
		DateTime right = sessionDay.AddMinutes(955.0);
		if (readyRange && drawnRangeDay != sessionDay)
		{
			drawnRangeDay = sessionDay;
			Level("Opening range high", sessionDay.AddMinutes(510.0), right, rangeHigh, Brushes.Goldenrod);
			Level("Opening range low", sessionDay.AddMinutes(510.0), right, rangeLow, Brushes.Goldenrod);
		}
		if (ownedNet != 0 && entered > 0 && drawnEntry != entryName)
		{
			drawnEntry = entryName;
			Level("Original stop", (executionVisual == null) ? now : executionVisual.Entered, right, plannedStop, Brushes.OrangeRed);
			Level("Entry", (executionVisual == null) ? now : executionVisual.Entered, right, entrySum / (double)entered, Brushes.White);
			Level("Target", (executionVisual == null) ? now : executionVisual.Entered, right, plannedTarget, Brushes.LimeGreen);
		}
	}

	internal static int Cutoff(DateTime day)
	{
		return 955;
	}
}
}
namespace NinjaTrader.NinjaScript.Indicators
{

public class VWAPPullbackADX : Indicator
{
	internal sealed class AdxHistory
	{
		private struct Sample
		{
			internal double Value;

			internal double Previous;

			internal bool Ready;
		}

		private readonly SortedList<DateTime, Sample> values = new SortedList<DateTime, Sample>();

		public void Clear()
		{
			values.Clear();
		}

		public void Store(DateTime end, double value)
		{
			Store(end, value, double.NaN, ready: false);
		}

		public void Store(DateTime end, double value, double previous, bool ready)
		{
			values[end] = new Sample
			{
				Value = value,
				Previous = previous,
				Ready = ready
			};
		}

		public double At(DateTime end, double fallback)
		{
			int num = Find(end);
			return (num < 0) ? fallback : values.Values[num].Value;
		}

		public bool EligibleAt(DateTime end)
		{
			int num = Find(end);
			if (num < 0)
			{
				return false;
			}
			Sample sample = values.Values[num];
			return sample.Ready && sample.Value > 20.0 && sample.Value <= sample.Previous;
		}

		private int Find(DateTime end)
		{
			int num = 0;
			int num2 = values.Count;
			while (num < num2)
			{
				int num3 = num + (num2 - num) / 2;
				if (values.Keys[num3] <= end)
				{
					num = num3 + 1;
				}
				else
				{
					num2 = num3;
				}
			}
			return num - 1;
		}
	}

	private NinjaTrader.NinjaScript.Strategies.VWAPPullbackNT8.WilderAdx adx;

	private TimeZoneInfo platformZone;

	private TimeZoneInfo centralZone;

	private int consumedSourceIndex = -1;

	private readonly AdxHistory published = new AdxHistory();

	internal void Publish(double value, double previous, bool ready, DateTime sourceEnd, bool paint = true)
	{
		published.Store(sourceEnd, value, previous, ready);
		if (paint)
		{
			PaintCurrent();
		}
	}

	private void PaintCurrent()
	{
		if (base.State != State.Terminated && platformZone != null && base.CurrentBars != null && base.CurrentBars.Length != 0 && base.CurrentBars[0] >= 0)
		{
			DateTime end = Central(base.Times[0][0]);
			double value = published.At(end, 0.0);
			base.Values[0][0] = value;
			base.PlotBrushes[0][0] = (published.EligibleAt(end) ? System.Windows.Media.Brushes.SeaGreen : System.Windows.Media.Brushes.Gray);
		}
	}

	internal void ResetPublished()
	{
		published.Clear();
	}

	internal void RefreshPublishedPlots()
	{
		if (base.CurrentBars != null && base.CurrentBars[0] >= 0)
		{
			for (int i = 0; i <= base.CurrentBars[0]; i++)
			{
				DateTime end = Central(base.BarsArray[0].GetTime(i));
				double value = published.At(end, 0.0);
				int barsAgo = base.CurrentBars[0] - i;
				base.Values[0][barsAgo] = value;
				base.PlotBrushes[0][barsAgo] = (published.EligibleAt(end) ? System.Windows.Media.Brushes.SeaGreen : System.Windows.Media.Brushes.Gray);
			}
		}
	}

	protected override void OnStateChange()
	{
		if (base.State == State.SetDefaults)
		{
			base.Name = "VWAP Pullback ADX";
			base.Description = "Fixed completed NQ M1 ADX14; green means above 20 and nonrising.";
			base.Calculate = Calculate.OnEachTick;
			base.IsOverlay = false;
			base.IsSuspendedWhileInactive = false;
			base.BarsRequiredToPlot = 0;
			base.MaximumBarsLookBack = MaximumBarsLookBack.Infinite;
			AddPlot(new NinjaTrader.Gui.Stroke(System.Windows.Media.Brushes.SeaGreen, 2f), PlotStyle.Bar, "ADX14");
			AddLine(System.Windows.Media.Brushes.Goldenrod, 20.0, "Threshold");
		}
		else if (base.State == State.Configure)
		{
			AddDataSeries(NinjaTrader.NinjaScript.Strategies.VWAPPullbackNT8.SourceContract(base.Instrument), new BarsPeriod
			{
				BarsPeriodType = BarsPeriodType.Minute,
				Value = 1
			}, "CME US Index Futures ETH", true);
		}
		else if (base.State == State.DataLoaded)
		{
			adx = new NinjaTrader.NinjaScript.Strategies.VWAPPullbackNT8.WilderAdx();
			platformZone = NinjaTrader.Core.Globals.GeneralOptions.TimeZoneInfo;
			centralZone = TimeZoneInfo.FindSystemTimeZoneById("Central Standard Time");
		}
	}

	private DateTime Central(DateTime time)
	{
		return TimeZoneInfo.ConvertTime(DateTime.SpecifyKind(time, DateTimeKind.Unspecified), platformZone, centralZone);
	}

	protected override void OnBarUpdate()
	{
		if ((base.State != State.Historical && base.State != State.Transition && base.State != State.Realtime) || adx == null || platformZone == null || centralZone == null || base.CurrentBars == null || base.BarsArray == null || base.BarsInProgress < 0 || base.BarsInProgress >= base.CurrentBars.Length || base.BarsInProgress >= base.BarsArray.Length || base.BarsArray[0] == null || base.BarsArray[base.BarsInProgress] == null)
		{
			return;
		}
		if (base.BarsInProgress == 0)
		{
			PaintCurrent();
		}
		else if (base.BarsInProgress == 1 && base.CurrentBars[1] >= 0)
		{
			int num = base.CurrentBars[1] - ((base.State != State.Historical) ? 1 : 0);
			for (int i = consumedSourceIndex + 1; i <= num; i++)
			{
				DateTime end = Central(base.BarsArray[1].GetTime(i));
				adx.Push(new NinjaTrader.NinjaScript.Strategies.VWAPPullbackNT8.Candle(end.AddMinutes(-1.0), base.BarsArray[1].GetOpen(i), base.BarsArray[1].GetHigh(i), base.BarsArray[1].GetLow(i), base.BarsArray[1].GetClose(i)));
				published.Store(end, adx.Value, adx.Previous, adx.Ready);
				consumedSourceIndex = i;
			}
			if (base.CurrentBars[0] >= 0)
			{
				PaintCurrent();
			}
		}
	}
}
}

namespace NinjaTrader.NinjaScript.Strategies
{
    public partial class Strategy : NinjaTrader.Gui.NinjaScript.StrategyRenderBase
    {
        public Indicators.VWAPPullbackADX VWAPPullbackModelDisplay()
        {
            return indicator.VWAPPullbackModelDisplay(Input);
        }
    }
}
namespace NinjaTrader.NinjaScript.Indicators
{
    public partial class Indicator : NinjaTrader.Gui.NinjaScript.IndicatorRenderBase
    {
        private VWAPPullbackADX[] cacheVWAPPullbackModelDisplay;
        public VWAPPullbackADX VWAPPullbackModelDisplay(ISeries<double> input)
        {
            return CacheIndicator<VWAPPullbackADX>(new VWAPPullbackADX(), input, ref cacheVWAPPullbackModelDisplay);
        }
    }
}

