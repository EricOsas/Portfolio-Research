// ═══════════════════════════════════════════════════════════════════════════
//  FVG_Duo_NT8.cs
//  FVG Duo — Opening Drive FVG + Trend FVG (NinjaTrader 8 shell)
//  Developed by Osamwonyi Eric (@You_FoundEric)
//  Copyright 2026-2027, Osamwonyi Eric (@You_FoundEric)
//
//  Every signal decision lives in FvgDuoCore.cs. This shell owns what only the
//  platform can prove: executable quotes, fill risk, scoped inventory, durable
//  order lineage and separately protected contract slices.
//
//  Apply it to ANY chart of the instrument — the strategy adds its own
//  M1 / M10 / M15 series. Set "Days to load" high enough for ~1000 completed
//  15-minute bars of warm-up (10 calendar days is the engine minimum, a few
//  months is safer for the EMA/ATR seed).
//
//  Sessions: the flatten minute is taken from the platform's own session
//  template when it lands inside 13:00-17:00 New York, so half days close when
//  NinjaTrader says they close. Otherwise the strategy's RTH table applies.
// ═══════════════════════════════════════════════════════════════════════════

#region Using declarations
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.ComponentModel.DataAnnotations;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Xml.Linq;
#if !FVG_DUO_POLICY_TEST
using NinjaTrader.Cbi;
using NinjaTrader.Data;
using NinjaTrader.Gui;
using NinjaTrader.Gui.Tools;
using NinjaTrader.NinjaScript;
using NinjaTrader.NinjaScript.DrawingTools;
using NinjaTrader.NinjaScript.Strategies.FvgDuo;
using System.Windows.Media;
using NinjaTrader.NinjaScript.Strategies.FvgDuoSafety;
#endif
#endregion

namespace NinjaTrader.NinjaScript.Strategies.FvgDuoSafety
{
    internal struct FvgDuoRiskTerms
    {
        public readonly double PointValue;
        public readonly double TickSize;
        public readonly double RoundTripCommission;
        public readonly int StressedSlippageTicks;

        public FvgDuoRiskTerms(double pointValue, double tickSize,
                               double roundTripCommission, int stressedSlippageTicks)
        {
            PointValue = pointValue;
            TickSize = tickSize;
            RoundTripCommission = roundTripCommission;
            StressedSlippageTicks = stressedSlippageTicks;
        }

        public bool Valid
        {
            get
            {
                return FvgDuoFillRisk.FinitePositive(PointValue)
                    && FvgDuoFillRisk.FinitePositive(TickSize)
                    && FvgDuoFillRisk.FinitePositive(RoundTripCommission)
                    && StressedSlippageTicks > 0;
            }
        }
    }

    internal static class FvgDuoFillRisk
    {
        internal static bool Finite(double value)
        {
            return !double.IsNaN(value) && !double.IsInfinity(value);
        }

        internal static bool FinitePositive(double value)
        {
            return Finite(value) && value > 0.0;
        }

        internal static double PerContract(double executableEntry, double acceptedStop,
                                           FvgDuoRiskTerms terms)
        {
            if (!terms.Valid || !FinitePositive(executableEntry) || !FinitePositive(acceptedStop)
                || executableEntry == acceptedStop)
                return double.NaN;

            double priceRisk = Math.Abs(executableEntry - acceptedStop) * terms.PointValue;
            double stressedExitSlippage = terms.StressedSlippageTicks
                                         * terms.TickSize * terms.PointValue;
            double result = priceRisk + terms.RoundTripCommission + stressedExitSlippage;
            return FinitePositive(result) ? result : double.NaN;
        }

        internal static int Size(double executableEntry, double acceptedStop, double cashBudget,
                                 FvgDuoRiskTerms terms, int maxContracts,
                                 double availableMargin, double marginPerContract)
        {
            double perContract = PerContract(executableEntry, acceptedStop, terms);
            if (!FinitePositive(cashBudget) || !FinitePositive(perContract)
                || maxContracts <= 0 || !FinitePositive(availableMargin)
                || !FinitePositive(marginPerContract))
                return 0;

            int byRisk = SafeFloor(cashBudget / perContract);
            int byMargin = SafeFloor(availableMargin / marginPerContract);
            return Math.Max(0, Math.Min(maxContracts, Math.Min(byRisk, byMargin)));
        }

        internal static int FixedSize(int requested, FvgDuoRiskTerms terms, int maxContracts,
                                      double availableMargin, double marginPerContract)
        {
            if (requested <= 0 || !terms.Valid || maxContracts <= 0
                || !FinitePositive(availableMargin) || !FinitePositive(marginPerContract))
                return 0;
            int byMargin = SafeFloor(availableMargin / marginPerContract);
            return Math.Max(0, Math.Min(requested, Math.Min(maxContracts, byMargin)));
        }

        private static int SafeFloor(double value)
        {
            if (!FinitePositive(value)) return 0;
            if (value >= int.MaxValue) return int.MaxValue;
            return (int)Math.Floor(value + 1e-12);
        }
    }

    internal enum FvgDuoTransportState
    {
        None,
        Needed,
        SubmitPending,
        Working,
        CancelPending,
        ChangePending,
        Filled,
        Cancelled,
        Rejected
    }

    internal enum FvgDuoIntentKind
    {
        None,
        RiskReduction,
        Merge,
        Close
    }

    internal enum FvgDuoSliceCommandKind
    {
        SubmitStop,
        SubmitTarget,
        CancelTarget,
        CancelEntry,
        DriveStop,
        WidenStop,
        EmergencyExit,
        SweepOwned
    }

    internal enum FvgDuoRestartStatus
    {
        Clean,
        Ready,
        Blocked
    }

    internal sealed class FvgDuoSliceCommand
    {
        public FvgDuoSliceCommandKind Kind { get; private set; }
        public long SliceId { get; private set; }
        public string Name { get; private set; }
        public double Price { get; private set; }

        internal FvgDuoSliceCommand(FvgDuoSliceCommandKind kind, long sliceId,
                                    string name, double price)
        {
            Kind = kind;
            SliceId = sliceId;
            Name = name ?? string.Empty;
            Price = price;
        }
    }

    internal sealed class FvgDuoSlice
    {
        public long Id { get; internal set; }
        public double FillPrice { get; internal set; }
        public int Remaining { get; internal set; }
        public bool Retain { get; internal set; }
        public double AcceptedStop { get; internal set; }
        public double PendingStop { get; internal set; }
        public bool PendingStopIsExit { get; internal set; }
        public bool StopDriven { get; internal set; }
        public bool TargetCancelRejected { get; internal set; }
        public FvgDuoTransportState StopState { get; internal set; }
        public FvgDuoTransportState TargetState { get; internal set; }
        public FvgDuoTransportState EmergencyState { get; internal set; }
        public string StopOrderId { get; internal set; }
        public string TargetOrderId { get; internal set; }
        public string EmergencyOrderId { get; internal set; }

        internal FvgDuoSlice()
        {
            StopOrderId = string.Empty;
            TargetOrderId = string.Empty;
            EmergencyOrderId = string.Empty;
            Retain = true;
        }
    }

    internal sealed class FvgDuoOwnedOrderEvidence
    {
        public string Name { get; private set; }
        public string OrderId { get; private set; }
        public bool Active { get; private set; }
        public bool IsStop { get; private set; }
        public int Quantity { get; private set; }
        public double Price { get; private set; }
        public string Oco { get; private set; }

        internal FvgDuoOwnedOrderEvidence(string name, string orderId, bool active,
                                         bool isStop, int quantity, double price, string oco)
        {
            Name = name ?? string.Empty;
            OrderId = orderId ?? string.Empty;
            Active = active;
            IsStop = isStop;
            Quantity = quantity;
            Price = price;
            Oco = oco ?? string.Empty;
        }
    }

    internal sealed class FvgDuoProtectedSliceBook
    {
        private const string SnapshotVersion = "5";
        private readonly List<FvgDuoSlice> _slices = new List<FvgDuoSlice>();
        private readonly HashSet<string> _executionIds = new HashSet<string>(StringComparer.Ordinal);
        private long _nextSliceId = 1;
        private bool _sweepIssued;

        public string Owner { get; private set; }
        public string TradeId { get; private set; }
        public int Side { get; private set; }
        public double Budget { get; private set; }
        public FvgDuoRiskTerms Terms { get; private set; }
        public double InitialStop { get; private set; }
        public double InitialTarget { get; private set; }
        public bool FixedSizeMode { get; private set; }
        public int RequestedEntryQuantity { get; private set; }
        public string EntryOrderId { get; private set; }
        public FvgDuoTransportState EntryState { get; private set; }
        public int ReportedEntryFilled { get; private set; }
        public int ProcessedEntryQuantity { get; private set; }
        public FvgDuoIntentKind IntentKind { get; private set; }
        public double DesiredStop { get; private set; }
        public double DesiredTarget { get; private set; }
        public string IntentReason { get; private set; }
        public bool Blocked { get; private set; }
        public string BlockReason { get; private set; }
        public bool Diverged { get; private set; }
        public IList<FvgDuoSlice> Slices { get { return _slices.AsReadOnly(); } }

        public FvgDuoProtectedSliceBook(string owner, string tradeId, int side,
                                       double budget, FvgDuoRiskTerms terms,
                                       double initialStop, double initialTarget,
                                       bool fixedSizeMode)
        {
            if (string.IsNullOrWhiteSpace(owner)) throw new ArgumentException("owner");
            if (string.IsNullOrWhiteSpace(tradeId)) throw new ArgumentException("tradeId");
            if (side != 1 && side != -1) throw new ArgumentOutOfRangeException("side");
            Owner = owner;
            TradeId = tradeId;
            Side = side;
            Budget = budget;
            Terms = terms;
            InitialStop = initialStop;
            InitialTarget = initialTarget;
            FixedSizeMode = fixedSizeMode;
            EntryOrderId = string.Empty;
            EntryState = FvgDuoTransportState.None;
            IntentReason = string.Empty;
            BlockReason = string.Empty;
        }

        public int OwnedQuantity
        {
            get { return _slices.Sum(s => Math.Max(0, s.Remaining)); }
        }

        public bool EntryExecutionsSettled
        {
            get
            {
                if (RequestedEntryQuantity == 0) return true;
                if (!EntryTerminal() || ReportedEntryFilled < 0) return false;
                return ProcessedEntryQuantity == ReportedEntryFilled
                    && (EntryState != FvgDuoTransportState.Filled
                        || ReportedEntryFilled == RequestedEntryQuantity);
            }
        }

        public int RetainedQuantity
        {
            get { return _slices.Where(s => s.Remaining > 0 && s.Retain).Sum(s => s.Remaining); }
        }

        public double WeightedEntryPrice
        {
            get
            {
                int quantity = OwnedQuantity;
                return quantity <= 0 ? 0.0
                    : _slices.Where(s => s.Remaining > 0).Sum(s => s.FillPrice * s.Remaining) / quantity;
            }
        }

        public double ActualRisk
        {
            get
            {
                double total = 0.0;
                foreach (FvgDuoSlice slice in _slices.Where(s => s.Remaining > 0))
                {
                    double risk = FvgDuoFillRisk.PerContract(slice.FillPrice, slice.AcceptedStop, Terms);
                    if (!FvgDuoFillRisk.FinitePositive(risk)) return double.PositiveInfinity;
                    total += risk * slice.Remaining;
                }
                return total;
            }
        }

        public string EntryName { get { return Owner + "_E_" + TradeId; } }
        public string StopName(long sliceId) { return Owner + "_S_" + TradeId + "_" + sliceId; }
        public string TargetName(long sliceId) { return Owner + "_T_" + TradeId + "_" + sliceId; }
        public string EmergencyName(long sliceId) { return Owner + "_X_" + TradeId + "_" + sliceId; }
        public string OcoName(long sliceId) { return Owner + "_O_" + TradeId + "_" + sliceId; }

        public void SetEntryIntent(int quantity)
        {
            if (quantity <= 0) throw new ArgumentOutOfRangeException("quantity");
            RequestedEntryQuantity = quantity;
            ReportedEntryFilled = -1;
            ProcessedEntryQuantity = 0;
            EntryState = FvgDuoTransportState.Needed;
        }

        public void OnEntryOrderUpdate(string orderId, FvgDuoTransportState state)
        {
            int inferredFilled = state == FvgDuoTransportState.Filled
                ? RequestedEntryQuantity : ProcessedEntryQuantity;
            OnEntryOrderUpdate(orderId, state, inferredFilled);
        }

        public void OnEntryOrderUpdate(string orderId, FvgDuoTransportState state,
                                       int reportedFilled)
        {
            if (!string.IsNullOrEmpty(orderId)) EntryOrderId = orderId;
            if (reportedFilled >= 0) ReportedEntryFilled = Math.Max(ReportedEntryFilled, reportedFilled);
            if (EntryState == FvgDuoTransportState.CancelPending
                && state != FvgDuoTransportState.Filled
                && state != FvgDuoTransportState.Cancelled
                && state != FvgDuoTransportState.Rejected)
                return;
            if (state == FvgDuoTransportState.Rejected
                && EntryState == FvgDuoTransportState.CancelPending)
            {
                EntryState = FvgDuoTransportState.Working;
                SetBlocked("Rejected entry cancellation; known live entry retained");
                return;
            }
            if (TerminalCannotRegress(EntryState, state)) return;
            EntryState = state;
            if (state == FvgDuoTransportState.Rejected && OwnedQuantity == 0)
                SetBlocked("Entry rejected before any owned fill");
        }

        public void OnEntryExecution(string executionId, int quantity, double fillPrice)
        {
            if (string.IsNullOrEmpty(executionId) || quantity <= 0
                || !FvgDuoFillRisk.FinitePositive(fillPrice))
                return;
            if (!_executionIds.Add(executionId)) return;
            ProcessedEntryQuantity += quantity;

            for (int i = 0; i < quantity; i++)
            {
                _slices.Add(new FvgDuoSlice
                {
                    Id = _nextSliceId++,
                    FillPrice = fillPrice,
                    Remaining = 1,
                    Retain = true,
                    StopState = FvgDuoTransportState.Needed,
                    TargetState = InitialTarget > 0.0
                        ? FvgDuoTransportState.Needed : FvgDuoTransportState.None,
                    EmergencyState = FvgDuoTransportState.None
                });
            }
            if (IntentKind != FvgDuoIntentKind.None) RecomputeRetention();
        }

        public void OnExitExecution(string executionId, string orderName, int quantity, double fillPrice)
        {
            if (string.IsNullOrEmpty(executionId) || string.IsNullOrEmpty(orderName)
                || quantity <= 0 || !_executionIds.Add(executionId))
                return;

            FvgDuoSlice slice = SliceForOrder(orderName);
            if (slice == null || slice.Remaining <= 0) return;
            int applied = Math.Min(quantity, slice.Remaining);
            slice.Remaining -= applied;
            if (orderName == StopName(slice.Id)) slice.StopState = FvgDuoTransportState.Filled;
            else if (orderName == TargetName(slice.Id)) slice.TargetState = FvgDuoTransportState.Filled;
            else if (orderName == EmergencyName(slice.Id)) slice.EmergencyState = FvgDuoTransportState.Filled;
            if (slice.Remaining == 0) slice.Retain = false;
        }

        public void BeginMerge(double stop, double target, string reason)
        {
            if (IntentKind != FvgDuoIntentKind.None || Blocked) return;
            if (!FvgDuoFillRisk.FinitePositive(stop))
            {
                SetBlocked("Invalid merge stop");
                return;
            }
            IntentKind = FvgDuoIntentKind.Merge;
            DesiredStop = stop;
            DesiredTarget = target;
            IntentReason = reason ?? "MERGED";
            RecomputeRetention();
        }

        public void BeginClose(string reason)
        {
            if (IntentKind == FvgDuoIntentKind.Close) return;
            IntentKind = FvgDuoIntentKind.Close;
            DesiredStop = 0.0;
            DesiredTarget = 0.0;
            IntentReason = reason ?? "CLOSE";
            RecomputeRetention();
        }

        public List<FvgDuoSliceCommand> NextCommands(int accountSignedQuantity,
                                                     double executableBid, double executableAsk)
        {
            var result = new List<FvgDuoSliceCommand>();
            int ownedSigned = Side * OwnedQuantity;
            if (accountSignedQuantity != ownedSigned)
            {
                Diverged = true;
                return result;
            }
            Diverged = false;

            if (OwnedQuantity == 0)
            {
                if (IntentKind != FvgDuoIntentKind.None && !EntryTerminal())
                {
                    if (Blocked) return result;
                    if (EntryState == FvgDuoTransportState.Working
                        || EntryState == FvgDuoTransportState.SubmitPending)
                        result.Add(new FvgDuoSliceCommand(FvgDuoSliceCommandKind.CancelEntry,
                            0, EntryName, 0.0));
                    return result;
                }
                if (EntryExecutionsSettled && !_sweepIssued)
                    result.Add(new FvgDuoSliceCommand(FvgDuoSliceCommandKind.SweepOwned, 0, Owner, 0.0));
                return result;
            }

            foreach (FvgDuoSlice slice in _slices.Where(s => s.Remaining > 0
                                                          && s.StopState == FvgDuoTransportState.Needed))
            {
                result.Add(new FvgDuoSliceCommand(FvgDuoSliceCommandKind.SubmitStop,
                    slice.Id, StopName(slice.Id), InitialStop));
            }
            if (result.Count > 0) return result;

            // Explicitly rejected/missing protection resolves through exactly
            // one emergency exit. Cancelled can be the OCO half of a target fill;
            // wait for exact execution evidence instead of risking a second exit.
            foreach (FvgDuoSlice slice in _slices.Where(s => s.Remaining > 0
                && !HasAcceptedStop(s) && s.StopState == FvgDuoTransportState.Rejected))
            {
                if (slice.TargetState == FvgDuoTransportState.Working
                    && !slice.TargetCancelRejected)
                    result.Add(new FvgDuoSliceCommand(FvgDuoSliceCommandKind.CancelTarget,
                        slice.Id, TargetName(slice.Id), 0.0));
                else if (!TargetTransportLive(slice)
                    && slice.EmergencyState == FvgDuoTransportState.None)
                    result.Add(new FvgDuoSliceCommand(FvgDuoSliceCommandKind.EmergencyExit,
                        slice.Id, EmergencyName(slice.Id), 0.0));
            }
            if (result.Count > 0 || _slices.Any(s => s.Remaining > 0
                && !HasAcceptedStop(s) && s.StopState == FvgDuoTransportState.Rejected))
                return result;

            if (Blocked) return result;
            if (_slices.Any(s => s.Remaining > 0 && !HasAcceptedStop(s))) return result;

            if (IntentKind == FvgDuoIntentKind.None && !FixedSizeMode
                && FvgDuoFillRisk.FinitePositive(Budget) && ActualRisk > Budget + 1e-8)
            {
                IntentKind = FvgDuoIntentKind.RiskReduction;
                DesiredStop = 0.0;
                DesiredTarget = InitialTarget;
                IntentReason = "FILL_RISK";
                RecomputeRetention();
            }

            if (IntentKind == FvgDuoIntentKind.None)
            {
                foreach (FvgDuoSlice slice in _slices.Where(s => s.Remaining > 0
                    && s.TargetState == FvgDuoTransportState.Needed && InitialTarget > 0.0))
                {
                    result.Add(new FvgDuoSliceCommand(FvgDuoSliceCommandKind.SubmitTarget,
                        slice.Id, TargetName(slice.Id), InitialTarget));
                }
                return result;
            }

            if (!EntryTerminal())
            {
                if (EntryState == FvgDuoTransportState.Working
                    || EntryState == FvgDuoTransportState.SubmitPending)
                    result.Add(new FvgDuoSliceCommand(FvgDuoSliceCommandKind.CancelEntry,
                        0, EntryName, 0.0));
                return result;
            }

            foreach (FvgDuoSlice slice in _slices.Where(NeedsTargetCancellation))
            {
                result.Add(new FvgDuoSliceCommand(FvgDuoSliceCommandKind.CancelTarget,
                    slice.Id, TargetName(slice.Id), 0.0));
            }
            if (result.Count > 0 || _slices.Any(TargetCancellationPending)) return result;

            foreach (FvgDuoSlice slice in _slices.Where(s => s.Remaining > 0 && !s.Retain))
            {
                if (slice.StopState == FvgDuoTransportState.Working && !slice.StopDriven)
                {
                    double trigger = Side > 0
                        ? executableBid + Terms.TickSize
                        : executableAsk - Terms.TickSize;
                    if (FvgDuoFillRisk.FinitePositive(trigger))
                        result.Add(new FvgDuoSliceCommand(FvgDuoSliceCommandKind.DriveStop,
                            slice.Id, StopName(slice.Id), trigger));
                }
                else if (!StopTransportLive(slice) && !TargetTransportLive(slice)
                         && slice.EmergencyState == FvgDuoTransportState.None)
                {
                    result.Add(new FvgDuoSliceCommand(FvgDuoSliceCommandKind.EmergencyExit,
                        slice.Id, EmergencyName(slice.Id), 0.0));
                }
            }
            if (result.Count > 0 || _slices.Any(s => s.Remaining > 0 && !s.Retain)) return result;

            if (IntentKind == FvgDuoIntentKind.RiskReduction)
            {
                ClearSettledIntent();
                return result;
            }

            if (IntentKind == FvgDuoIntentKind.Merge)
            {
                int retainedSigned = Side * RetainedQuantity;
                if (accountSignedQuantity != retainedSigned) return result;
                foreach (FvgDuoSlice slice in _slices.Where(s => s.Remaining > 0 && s.Retain
                    && s.StopState == FvgDuoTransportState.Working
                    && !SamePrice(s.AcceptedStop, DesiredStop)))
                {
                    result.Add(new FvgDuoSliceCommand(FvgDuoSliceCommandKind.WidenStop,
                        slice.Id, StopName(slice.Id), DesiredStop));
                }
                if (result.Count == 0)
                {
                    InitialStop = DesiredStop;
                    InitialTarget = DesiredTarget;
                    ClearSettledIntent();
                }
            }
            return result;
        }

        public void Stage(FvgDuoSliceCommand command)
        {
            if (command == null) return;
            FvgDuoSlice slice = command.SliceId == 0 ? null : Slice(command.SliceId);
            switch (command.Kind)
            {
                case FvgDuoSliceCommandKind.SubmitStop:
                    if (slice != null && slice.StopState == FvgDuoTransportState.Needed)
                        slice.StopState = FvgDuoTransportState.SubmitPending;
                    break;
                case FvgDuoSliceCommandKind.SubmitTarget:
                    if (slice != null && slice.TargetState == FvgDuoTransportState.Needed)
                        slice.TargetState = FvgDuoTransportState.SubmitPending;
                    break;
                case FvgDuoSliceCommandKind.CancelTarget:
                    if (slice != null && slice.TargetState == FvgDuoTransportState.Working)
                    {
                        slice.TargetCancelRejected = false;
                        slice.TargetState = FvgDuoTransportState.CancelPending;
                    }
                    break;
                case FvgDuoSliceCommandKind.CancelEntry:
                    EntryState = FvgDuoTransportState.CancelPending;
                    break;
                case FvgDuoSliceCommandKind.DriveStop:
                    if (slice != null && slice.StopState == FvgDuoTransportState.Working)
                    {
                        slice.PendingStop = command.Price;
                        slice.PendingStopIsExit = true;
                        slice.StopState = FvgDuoTransportState.ChangePending;
                    }
                    break;
                case FvgDuoSliceCommandKind.WidenStop:
                    if (slice != null && slice.StopState == FvgDuoTransportState.Working)
                    {
                        slice.PendingStop = command.Price;
                        slice.PendingStopIsExit = false;
                        slice.StopState = FvgDuoTransportState.ChangePending;
                    }
                    break;
                case FvgDuoSliceCommandKind.EmergencyExit:
                    if (slice != null && slice.EmergencyState == FvgDuoTransportState.None)
                        slice.EmergencyState = FvgDuoTransportState.SubmitPending;
                    break;
                case FvgDuoSliceCommandKind.SweepOwned:
                    _sweepIssued = true;
                    break;
            }
        }

        public void OnOrderUpdate(string name, string orderId,
                                  FvgDuoTransportState state, double price)
        {
            OnOrderUpdate(name, orderId, state, price, -1);
        }

        public void OnOrderUpdate(string name, string orderId,
                                  FvgDuoTransportState state, double price,
                                  int reportedFilled)
        {
            if (name == EntryName)
            {
                if (reportedFilled >= 0) OnEntryOrderUpdate(orderId, state, reportedFilled);
                else OnEntryOrderUpdate(orderId, state);
                return;
            }
            FvgDuoSlice slice = SliceForOrder(name);
            if (slice == null) return;

            if (name == StopName(slice.Id))
            {
                if (!string.IsNullOrEmpty(orderId)) slice.StopOrderId = orderId;
                if (TerminalCannotRegress(slice.StopState, state)) return;
                if (state == FvgDuoTransportState.Working)
                {
                    if (!FvgDuoFillRisk.FinitePositive(price)) return;
                    // Old-price Working can arrive after ChangeOrder was staged;
                    // it proves old protection only, not requested-stop acceptance.
                    if (slice.StopState == FvgDuoTransportState.ChangePending
                        && FvgDuoFillRisk.FinitePositive(slice.PendingStop)
                        && !SamePrice(price, slice.PendingStop))
                        return;
                    if (slice.StopState == FvgDuoTransportState.Working
                        && FvgDuoFillRisk.FinitePositive(slice.AcceptedStop)
                        && FvgDuoFillRisk.FinitePositive(price)
                        && !SamePrice(price, slice.AcceptedStop))
                    {
                        SetBlocked("Unexpected stop price callback; confirmed protection retained");
                        return;
                    }
                    FvgDuoTransportState priorStopState = slice.StopState;
                    bool acceptedExit = priorStopState == FvgDuoTransportState.ChangePending
                                     && slice.PendingStopIsExit;
                    if (FvgDuoFillRisk.FinitePositive(price)) slice.AcceptedStop = price;
                    slice.PendingStop = 0.0;
                    slice.PendingStopIsExit = false;
                    if (priorStopState == FvgDuoTransportState.ChangePending)
                        slice.StopDriven = acceptedExit;
                    else if (priorStopState != FvgDuoTransportState.Working)
                        slice.StopDriven = false;
                    slice.StopState = FvgDuoTransportState.Working;
                }
                else if (state == FvgDuoTransportState.Rejected)
                {
                    if (FvgDuoFillRisk.FinitePositive(slice.AcceptedStop))
                    {
                        slice.PendingStop = 0.0;
                        slice.PendingStopIsExit = false;
                        slice.StopState = FvgDuoTransportState.Working;
                        SetBlocked("Rejected stop change; accepted protection retained");
                    }
                    else
                    {
                        slice.StopState = FvgDuoTransportState.Rejected;
                        BeginClose("PROTECTION_REJECT");
                    }
                }
                else if (state == FvgDuoTransportState.Cancelled
                      || state == FvgDuoTransportState.Filled)
                    slice.StopState = state;
                return;
            }

            if (name == TargetName(slice.Id))
            {
                if (!string.IsNullOrEmpty(orderId)) slice.TargetOrderId = orderId;
                if (TerminalCannotRegress(slice.TargetState, state)) return;
                if (state == FvgDuoTransportState.Working)
                {
                    if (!FvgDuoFillRisk.FinitePositive(price)) return;
                    if (slice.TargetState != FvgDuoTransportState.CancelPending)
                        slice.TargetState = FvgDuoTransportState.Working;
                }
                else if (state == FvgDuoTransportState.Cancelled
                      || state == FvgDuoTransportState.Filled)
                {
                    slice.TargetCancelRejected = false;
                    slice.TargetState = state;
                }
                else if (state == FvgDuoTransportState.Rejected)
                {
                    if (!string.IsNullOrEmpty(slice.TargetOrderId)
                        && slice.TargetState == FvgDuoTransportState.CancelPending)
                    {
                        slice.TargetState = FvgDuoTransportState.Working;
                        slice.TargetCancelRejected = true;
                        SetBlocked("Rejected target cancellation; existing target retained");
                    }
                    else
                    {
                        slice.TargetState = FvgDuoTransportState.Rejected;
                        SetBlocked("Target submission rejected; stop retained");
                    }
                }
                return;
            }

            if (name == EmergencyName(slice.Id))
            {
                if (!string.IsNullOrEmpty(orderId)) slice.EmergencyOrderId = orderId;
                if (TerminalCannotRegress(slice.EmergencyState, state)) return;
                slice.EmergencyState = state;
                if (state == FvgDuoTransportState.Rejected)
                    SetBlocked("Unprotected emergency exit rejected");
            }
        }

        public string Serialize(string account, string instrument)
        {
            var root = new XElement("FvgDuoRecovery",
                new XAttribute("version", SnapshotVersion),
                new XAttribute("owner", Owner),
                new XAttribute("account", account ?? string.Empty),
                new XAttribute("instrument", instrument ?? string.Empty),
                new XAttribute("trade", TradeId),
                new XAttribute("side", Side),
                new XAttribute("budget", Format(Budget)),
                new XAttribute("pointValue", Format(Terms.PointValue)),
                new XAttribute("tickSize", Format(Terms.TickSize)),
                new XAttribute("commission", Format(Terms.RoundTripCommission)),
                new XAttribute("slippageTicks", Terms.StressedSlippageTicks),
                new XAttribute("initialStop", Format(InitialStop)),
                new XAttribute("initialTarget", Format(InitialTarget)),
                new XAttribute("fixed", FixedSizeMode),
                new XAttribute("requested", RequestedEntryQuantity),
                new XAttribute("entryId", EntryOrderId ?? string.Empty),
                new XAttribute("entryState", EntryState),
                new XAttribute("reportedEntryFilled", ReportedEntryFilled),
                new XAttribute("processedEntryQuantity", ProcessedEntryQuantity),
                new XAttribute("intent", IntentKind),
                new XAttribute("desiredStop", Format(DesiredStop)),
                new XAttribute("desiredTarget", Format(DesiredTarget)),
                new XAttribute("reason", IntentReason ?? string.Empty),
                new XAttribute("blocked", Blocked),
                new XAttribute("blockReason", BlockReason ?? string.Empty),
                new XAttribute("nextSlice", _nextSliceId),
                new XAttribute("sweep", _sweepIssued));
            foreach (string id in _executionIds.OrderBy(x => x, StringComparer.Ordinal))
                root.Add(new XElement("Execution", new XAttribute("id", id)));
            foreach (FvgDuoSlice slice in _slices)
            {
                root.Add(new XElement("Slice",
                    new XAttribute("id", slice.Id),
                    new XAttribute("fill", Format(slice.FillPrice)),
                    new XAttribute("remaining", slice.Remaining),
                    new XAttribute("retain", slice.Retain),
                    new XAttribute("acceptedStop", Format(slice.AcceptedStop)),
                    new XAttribute("pendingStop", Format(slice.PendingStop)),
                    new XAttribute("pendingStopIsExit", slice.PendingStopIsExit),
                    new XAttribute("stopDriven", slice.StopDriven),
                    new XAttribute("stopState", slice.StopState),
                    new XAttribute("targetState", slice.TargetState),
                    new XAttribute("targetCancelRejected", slice.TargetCancelRejected),
                    new XAttribute("emergencyState", slice.EmergencyState),
                    new XAttribute("stopId", slice.StopOrderId ?? string.Empty),
                    new XAttribute("targetId", slice.TargetOrderId ?? string.Empty),
                    new XAttribute("emergencyId", slice.EmergencyOrderId ?? string.Empty)));
            }
            return new XDocument(root).ToString(SaveOptions.DisableFormatting);
        }

        public static bool TryDeserialize(string xml, string expectedOwner,
                                          string expectedAccount, string expectedInstrument,
                                          out FvgDuoProtectedSliceBook book)
        {
            book = null;
            try
            {
                XElement root = XDocument.Parse(xml).Root;
                if (root == null || (string)root.Attribute("version") != SnapshotVersion
                    || (string)root.Attribute("owner") != expectedOwner
                    || (string)root.Attribute("account") != expectedAccount
                    || (string)root.Attribute("instrument") != expectedInstrument)
                    return false;

                var terms = new FvgDuoRiskTerms(ParseDouble(root, "pointValue"),
                    ParseDouble(root, "tickSize"), ParseDouble(root, "commission"),
                    ParseInt(root, "slippageTicks"));
                var restored = new FvgDuoProtectedSliceBook(expectedOwner,
                    Required(root, "trade"), ParseInt(root, "side"),
                    ParseDouble(root, "budget"), terms,
                    ParseDouble(root, "initialStop"), ParseDouble(root, "initialTarget"),
                    ParseBool(root, "fixed"));
                restored.RequestedEntryQuantity = ParseInt(root, "requested");
                restored.EntryOrderId = Optional(root, "entryId");
                restored.EntryState = ParseEnum<FvgDuoTransportState>(root, "entryState");
                restored.ReportedEntryFilled = ParseInt(root, "reportedEntryFilled");
                restored.ProcessedEntryQuantity = ParseInt(root, "processedEntryQuantity");
                restored.IntentKind = ParseEnum<FvgDuoIntentKind>(root, "intent");
                restored.DesiredStop = ParseDouble(root, "desiredStop");
                restored.DesiredTarget = ParseDouble(root, "desiredTarget");
                restored.IntentReason = Optional(root, "reason");
                restored.Blocked = ParseBool(root, "blocked");
                restored.BlockReason = Optional(root, "blockReason");
                restored._nextSliceId = ParseLong(root, "nextSlice");
                restored._sweepIssued = ParseBool(root, "sweep");
                foreach (XElement e in root.Elements("Execution"))
                    restored._executionIds.Add(Required(e, "id"));
                foreach (XElement e in root.Elements("Slice"))
                {
                    restored._slices.Add(new FvgDuoSlice
                    {
                        Id = ParseLong(e, "id"),
                        FillPrice = ParseDouble(e, "fill"),
                        Remaining = ParseInt(e, "remaining"),
                        Retain = ParseBool(e, "retain"),
                        AcceptedStop = ParseDouble(e, "acceptedStop"),
                        PendingStop = ParseDouble(e, "pendingStop"),
                        PendingStopIsExit = ParseBool(e, "pendingStopIsExit"),
                        StopDriven = ParseBool(e, "stopDriven"),
                        StopState = ParseEnum<FvgDuoTransportState>(e, "stopState"),
                        TargetState = ParseEnum<FvgDuoTransportState>(e, "targetState"),
                        TargetCancelRejected = ParseBool(e, "targetCancelRejected"),
                        EmergencyState = ParseEnum<FvgDuoTransportState>(e, "emergencyState"),
                        StopOrderId = Optional(e, "stopId"),
                        TargetOrderId = Optional(e, "targetId"),
                        EmergencyOrderId = Optional(e, "emergencyId")
                    });
                }
                if (!terms.Valid || restored._nextSliceId <= 0
                    || restored.ReportedEntryFilled < -1 || restored.ProcessedEntryQuantity < 0
                    || restored._slices.Any(s => s.Id <= 0 || s.Remaining < 0
                        || !FvgDuoFillRisk.FinitePositive(s.FillPrice)))
                    return false;
                book = restored;
                return true;
            }
            catch (Exception)
            {
                book = null;
                return false;
            }
        }

        public FvgDuoRestartStatus ValidateRestart(int accountSignedQuantity,
                                                   IList<FvgDuoOwnedOrderEvidence> evidence)
        {
            if (evidence == null) evidence = new List<FvgDuoOwnedOrderEvidence>();
            if (accountSignedQuantity != Side * OwnedQuantity) return FvgDuoRestartStatus.Blocked;
            if (Blocked || !EntryExecutionsSettled || PendingTransport())
                return FvgDuoRestartStatus.Blocked;
            if (OwnedQuantity == 0)
                return evidence.Any(e => e.Active) ? FvgDuoRestartStatus.Blocked : FvgDuoRestartStatus.Clean;

            var expected = new HashSet<string>(StringComparer.Ordinal);
            foreach (FvgDuoSlice slice in _slices.Where(s => s.Remaining > 0))
            {
                if (!HasAcceptedStop(slice)) return FvgDuoRestartStatus.Blocked;
                FvgDuoOwnedOrderEvidence stop = evidence.SingleOrDefault(e => e.Active
                    && e.IsStop && e.Name == StopName(slice.Id));
                if (!ExactEvidence(stop, slice.StopOrderId, slice.Remaining,
                    slice.AcceptedStop, OcoName(slice.Id)))
                    return FvgDuoRestartStatus.Blocked;
                expected.Add(stop.Name);

                if (slice.TargetState == FvgDuoTransportState.Working)
                {
                    FvgDuoOwnedOrderEvidence target = evidence.SingleOrDefault(e => e.Active
                        && !e.IsStop && e.Name == TargetName(slice.Id));
                    if (!ExactEvidence(target, slice.TargetOrderId, slice.Remaining,
                        InitialTarget, OcoName(slice.Id)))
                        return FvgDuoRestartStatus.Blocked;
                    expected.Add(target.Name);
                }
            }
            if (evidence.Any(e => e.Active && !expected.Contains(e.Name)))
                return FvgDuoRestartStatus.Blocked;
            return FvgDuoRestartStatus.Ready;
        }

        public static FvgDuoRestartStatus ValidateUnknownRestart(int accountSignedQuantity,
                                                                 bool hasOwnedOrders)
        {
            return accountSignedQuantity == 0 && !hasOwnedOrders
                ? FvgDuoRestartStatus.Clean : FvgDuoRestartStatus.Blocked;
        }

        public void SetBlocked(string reason)
        {
            Blocked = true;
            BlockReason = reason ?? "Blocked";
        }

        public void MarkStopMissing(string stopName, string reason)
        {
            FvgDuoSlice slice = SliceForOrder(stopName);
            if (slice == null || slice.Remaining <= 0) return;
            slice.AcceptedStop = 0.0;
            slice.PendingStop = 0.0;
            slice.PendingStopIsExit = false;
            slice.StopDriven = false;
            slice.StopState = FvgDuoTransportState.Rejected;
            BeginClose(reason ?? "MISSING_PROTECTION");
        }

        private void ClearSettledIntent()
        {
            IntentKind = FvgDuoIntentKind.None;
            DesiredStop = 0.0;
            DesiredTarget = 0.0;
            IntentReason = string.Empty;
            foreach (FvgDuoSlice slice in _slices.Where(s => s.Remaining > 0))
                slice.Retain = true;
        }

        private void RecomputeRetention()
        {
            foreach (FvgDuoSlice slice in _slices) slice.Retain = slice.Remaining > 0;
            if (IntentKind == FvgDuoIntentKind.Close)
            {
                foreach (FvgDuoSlice slice in _slices) slice.Retain = false;
                return;
            }
            if (FixedSizeMode || IntentKind == FvgDuoIntentKind.None) return;

            foreach (FvgDuoSlice slice in _slices) slice.Retain = false;
            double used = 0.0;
            foreach (FvgDuoSlice slice in _slices.Where(s => s.Remaining > 0)
                     .OrderBy(RiskAtIntent).ThenBy(s => s.Id))
            {
                double risk = RiskAtIntent(slice);
                if (!FvgDuoFillRisk.FinitePositive(risk)) continue;
                if (used + risk <= Budget + 1e-8)
                {
                    slice.Retain = true;
                    used += risk;
                }
            }
        }

        private double RiskAtIntent(FvgDuoSlice slice)
        {
            double stop = IntentKind == FvgDuoIntentKind.Merge ? DesiredStop : slice.AcceptedStop;
            return FvgDuoFillRisk.PerContract(slice.FillPrice, stop, Terms);
        }

        private bool NeedsTargetCancellation(FvgDuoSlice slice)
        {
            if (slice.Remaining <= 0 || slice.TargetState != FvgDuoTransportState.Working
                || slice.TargetCancelRejected) return false;
            return IntentKind == FvgDuoIntentKind.Merge || IntentKind == FvgDuoIntentKind.Close || !slice.Retain;
        }

        private bool TargetCancellationPending(FvgDuoSlice slice)
        {
            if (slice.Remaining <= 0) return false;
            if (!(IntentKind == FvgDuoIntentKind.Merge || IntentKind == FvgDuoIntentKind.Close || !slice.Retain))
                return false;
            return slice.TargetState == FvgDuoTransportState.CancelPending
                || slice.TargetState == FvgDuoTransportState.SubmitPending;
        }

        private bool EntryTerminal()
        {
            return EntryState == FvgDuoTransportState.Filled
                || EntryState == FvgDuoTransportState.Cancelled
                || EntryState == FvgDuoTransportState.Rejected;
        }

        private bool PendingTransport()
        {
            if (EntryState == FvgDuoTransportState.Needed
                || EntryState == FvgDuoTransportState.SubmitPending
                || EntryState == FvgDuoTransportState.CancelPending)
                return true;
            return _slices.Any(s => s.StopState == FvgDuoTransportState.Needed
                || s.StopState == FvgDuoTransportState.SubmitPending
                || s.StopState == FvgDuoTransportState.ChangePending
                || s.TargetState == FvgDuoTransportState.SubmitPending
                || s.TargetState == FvgDuoTransportState.CancelPending
                || s.EmergencyState == FvgDuoTransportState.SubmitPending);
        }

        private static bool HasAcceptedStop(FvgDuoSlice slice)
        {
            return slice.StopState == FvgDuoTransportState.Working
                && FvgDuoFillRisk.FinitePositive(slice.AcceptedStop);
        }

        private static bool StopTransportLive(FvgDuoSlice slice)
        {
            return slice.StopState == FvgDuoTransportState.Working
                || slice.StopState == FvgDuoTransportState.SubmitPending
                || slice.StopState == FvgDuoTransportState.ChangePending;
        }

        private static bool TargetTransportLive(FvgDuoSlice slice)
        {
            return slice.TargetState == FvgDuoTransportState.Working
                || slice.TargetState == FvgDuoTransportState.SubmitPending
                || slice.TargetState == FvgDuoTransportState.CancelPending;
        }

        private FvgDuoSlice Slice(long id)
        {
            return _slices.SingleOrDefault(s => s.Id == id);
        }

        private FvgDuoSlice SliceForOrder(string name)
        {
            return _slices.SingleOrDefault(s => name == StopName(s.Id)
                || name == TargetName(s.Id) || name == EmergencyName(s.Id));
        }

        private static bool ExactEvidence(FvgDuoOwnedOrderEvidence evidence,
                                          string orderId, int quantity, double price,
                                          string expectedOco)
        {
            return evidence != null && evidence.Active && !string.IsNullOrEmpty(orderId)
                && !string.IsNullOrEmpty(evidence.OrderId)
                && evidence.OrderId == orderId
                && evidence.Quantity == quantity && SamePrice(evidence.Price, price)
                && evidence.Oco == (expectedOco ?? string.Empty);
        }

        private static bool SamePrice(double left, double right)
        {
            return Math.Abs(left - right) <= 1e-8;
        }

        private static bool TerminalCannotRegress(FvgDuoTransportState current,
                                                   FvgDuoTransportState incoming)
        {
            if (current == FvgDuoTransportState.Filled) return true;
            bool currentTerminal = current == FvgDuoTransportState.Cancelled
                                || current == FvgDuoTransportState.Rejected;
            bool incomingTerminal = incoming == FvgDuoTransportState.Filled
                                 || incoming == FvgDuoTransportState.Cancelled
                                 || incoming == FvgDuoTransportState.Rejected;
            return currentTerminal && !incomingTerminal;
        }

        private static string Format(double value)
        {
            return value.ToString("R", CultureInfo.InvariantCulture);
        }

        private static string Required(XElement element, string name)
        {
            XAttribute attribute = element.Attribute(name);
            if (attribute == null) throw new InvalidDataException("Missing " + name);
            return attribute.Value;
        }

        private static string Optional(XElement element, string name)
        {
            XAttribute attribute = element.Attribute(name);
            return attribute == null ? string.Empty : attribute.Value;
        }

        private static int ParseInt(XElement element, string name)
        {
            return int.Parse(Required(element, name), NumberStyles.Integer, CultureInfo.InvariantCulture);
        }

        private static long ParseLong(XElement element, string name)
        {
            return long.Parse(Required(element, name), NumberStyles.Integer, CultureInfo.InvariantCulture);
        }

        private static double ParseDouble(XElement element, string name)
        {
            return double.Parse(Required(element, name), NumberStyles.Float, CultureInfo.InvariantCulture);
        }

        private static bool ParseBool(XElement element, string name)
        {
            return bool.Parse(Required(element, name));
        }

        private static T ParseEnum<T>(XElement element, string name) where T : struct
        {
            T result;
            if (!Enum.TryParse(Required(element, name), false, out result))
                throw new InvalidDataException("Invalid " + name);
            return result;
        }
    }
}

#if !FVG_DUO_POLICY_TEST
namespace NinjaTrader.NinjaScript.Strategies
{
    public enum SizingModeNT8
    {
        [Display(Name = "Fixed Contracts")]
        FixedLots,
        [Display(Name = "Risk % of Equity")]
        RiskPercent,
        [Display(Name = "Cash Risk")]
        CashRisk,
        [Display(Name = "Risk % of Fixed Balance (Non-compounding)")]
        RiskBalance
    }

    public class FVG_Duo_NT8 : Strategy
    {
        #region Inputs
        [NinjaScriptProperty]
        [Display(Name = "Sizing Mode", Order = 1, GroupName = "1. Sizing & Risk")]
        public SizingModeNT8 SizingMode { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Fixed Contracts", Order = 2, GroupName = "1. Sizing & Risk")]
        public int FixedContracts { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Risk % per Trade", Order = 3, GroupName = "1. Sizing & Risk")]
        public double RiskPercent { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Cash Risk", Order = 4, GroupName = "1. Sizing & Risk")]
        public double CashRisk { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Fixed Balance (0 = account balance)", Order = 5, GroupName = "1. Sizing & Risk")]
        public double FixedBalance { get; set; }

        [NinjaScriptProperty]
        [Range(0.0, double.MaxValue)]
        [Display(Name = "Round-turn Commission per Contract ($3.00 open + $3.00 close)", Order = 1, GroupName = "2. Costs & Execution")]
        public double RoundTripCommissionOverride { get; set; }

        [NinjaScriptProperty]
        [Range(1, 20)]
        [Display(Name = "Stressed Exit Slippage (ticks)", Order = 2, GroupName = "2. Costs & Execution")]
        public int StressedSlippageTicks { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Show Visuals", Order = 1, GroupName = "3. Display")]
        public bool ShowVisuals { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Stable Instance Tag", Order = 1, GroupName = "4. Diagnostics")]
        public string InstanceTag { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Write Trade Journal CSV", Order = 2, GroupName = "4. Diagnostics")]
        public bool WriteJournal { get; set; }
        #endregion

        #region Model constants
        // Optimal B3a is the only live model. Mirrors B3A_* in StrategyEngine.mqh
        // and the Python oracle: SMA/c2 ATR(14) x1.25, EMA 50/100, OD stop 1.25%,
        // trend 3R, strict FVG, stop anchored to the trend entry.
        private const double B3A_TREND_ATR_MULT = 1.25;
        private const double B3A_OD_STOP_PCT = 0.0125;
        private const bool B3A_TREND_AFTER_STOPOUT = true;
        #endregion

        #region State
        private const int BipMinute = 1;
        private const int BipOdContext = 2;
        private const int BipTrendContext = 3;

        private static readonly TimeZoneInfo NewYorkZone =
            TimeZoneInfo.FindSystemTimeZoneById("Eastern Standard Time");

        private FvgDuoEngine _core;
        private IFvgDuoHistory _history;
        private TimeZoneInfo _platformZone;
        private SessionIterator _sessions;

        // NinjaTrader stamps intraday bars with their close boundary; verified at
        // DataLoaded against the session begin so a platform change cannot shift
        // every clock gate by a minute unnoticed.
        private int _stampOffsetMinutes = 1;

        private DateTime _asOfNy = DateTime.MinValue;
        private DateTime _dayNy = DateTime.MinValue;
        private readonly HashSet<string> _visualTags = new HashSet<string>(StringComparer.Ordinal);
        private int _fvgCandidatesSeen;
        private string _currentFvgTag = string.Empty;
        private FvgDuoZone _currentFvgZone;
        private string _pendingEntryFvgTag = string.Empty, _pendingMergeFvgTag = string.Empty;
        private readonly Dictionary<string, Tuple<FvgDuoZone, string>> _fvgHover =
            new Dictionary<string, Tuple<FvgDuoZone, string>>(StringComparer.Ordinal);
        private Tuple<FvgDuoZone, string>[] _fvgHoverSnapshot = new Tuple<FvgDuoZone, string>[0];
        private NinjaTrader.Gui.Chart.ChartControl _hoverChartControl;
        private System.Windows.Controls.ToolTip _visualTooltip;
        private string _visualTradePrefix = string.Empty, _visualTradeSource = string.Empty;
        private DateTime _visualTradeStartNy, _visualTradePlannedEndNy;
        private int _visualTradeSide, _visualExitQuantity;
        private double _visualTradeEntry, _visualTradeStop, _visualTradeTarget, _visualExitValue;
        private DateTime _visualSessionDay = DateTime.MinValue, _visualEmaLastClose = DateTime.MinValue;
        private double _visualSessionHigh, _visualSessionLow, _visualEmaFast, _visualEmaSlow;
        private static readonly Brush VisualStopBrush = VisualBrush(55, 65, 81);
        private static readonly Brush VisualTargetBrush = VisualBrush(56, 189, 248);
        private static readonly Brush VisualSlowBrush = VisualBrush(168, 85, 247);
        private static readonly Brush VisualSessionBrush = VisualBrush(71, 85, 105);
        private int _sessionEndMinute = 16 * 60;

        private readonly List<FvgDuoAction> _actions = new List<FvgDuoAction>(8);

        // Model metadata stays separate from actual owned executions.
        private string _posSource = string.Empty;
        private int _posSide;
        private double _posEntryModel;
        private double _posEntryFill;
        private double _posStop;
        private double _posTarget;
        private DateTime _posEntryNy;
        private double _entrySlippage;

        // Actual inventory/order lifecycle. Each filled contract owns one OCO
        // stop/target lineage through FvgDuoProtectedSliceBook.
        private FvgDuoProtectedSliceBook _book;
        private readonly Dictionary<string, Order> _ownedOrders =
            new Dictionary<string, Order>(StringComparer.Ordinal);
        private Order _entryOrder;
        private string _ownerPrefix = string.Empty;
        private string _snapshotPath = string.Empty;
        private string _pendingMergeSource = string.Empty;
        private string _pendingExitReason = string.Empty;
        private string _pendingFinalizeReason = string.Empty;
        private DateTime _pendingFinalizeTime;
        private double _pendingFinalizePrice;
        private string _lastDivergence = string.Empty;
        private string _executionBlockReason = string.Empty;
        private bool _executionBlocked;
        private bool _recoveryReady;
        private bool _recoveredLifecycle;
        private bool _accountEventsSubscribed;
        private bool _drivingLifecycle;
        private int _tradeSequence;
        private System.Timers.Timer _safetyTimer;
        private FileStream _ownerLock;

        private StreamWriter _journal;
        private int _journalRows;

        // Non-compounding risk anchor, captured once at DataLoaded.
        private double _fixedBalanceBase;
        #endregion

        protected override void OnStateChange()
        {
            if (State == State.SetDefaults)
            {
                Name = "FVG Duo";
                Description = "Opening Drive FVG + Trend FVG. Adds its own M1/M10/M15 series; "
                            + "load enough 15-minute history for 1000-bar warm-up.";
                Calculate = Calculate.OnEachTick;
                EntriesPerDirection = 1;
                EntryHandling = EntryHandling.AllEntries;
                IsUnmanaged = true;
                StartBehavior = StartBehavior.ImmediatelySubmit;
                IsAdoptAccountPositionAware = false;
                RealtimeErrorHandling = RealtimeErrorHandling.IgnoreAllErrors;
                TimeInForce = TimeInForce.Gtc;
                IsExitOnSessionCloseStrategy = false;
                IsFillLimitOnTouch = false;
                BarsRequiredToTrade = 20;

                SizingMode = SizingModeNT8.FixedLots;
                FixedContracts = 1;
                RiskPercent = 1.0;
                CashRisk = 100.0;
                FixedBalance = 0.0;
                RoundTripCommissionOverride = 6.0;
                StressedSlippageTicks = 2;

                InstanceTag = "A";
                ShowVisuals = true;
                WriteJournal = true;
            }
            else if (State == State.Configure)
            {
                AddDataSeries(BarsPeriodType.Minute, 1);   // BarsArray[1] execution
                AddDataSeries(BarsPeriodType.Minute, 10);  // BarsArray[2] OD context
                AddDataSeries(BarsPeriodType.Minute, 15);  // BarsArray[3] trend context
            }
            else if (State == State.DataLoaded)
            {
                _platformZone = Core.Globals.GeneralOptions.TimeZoneInfo;
                _sessions = new SessionIterator(BarsArray[BipMinute]);

                _core = BuildEngine();
                _history = new SeriesHistory(this);
                DetectStampOffset();

                _fixedBalanceBase = FixedBalance > 0.0 ? FixedBalance : AccountSize();
                _ownerPrefix = BuildOwnerPrefix();
                AttachVisualHover();
                _snapshotPath = Path.Combine(Core.Globals.UserDataDir, "FVG Duo", "recovery",
                    _ownerPrefix + ".xml");

                if (WriteJournal) OpenJournal();

                Print(string.Format(CultureInfo.InvariantCulture,
                    "[FVG_DUO] {0} owner={1} model=Optimal_B3a tick={2:F4} stampOffset={3}m platform={4} sizing={5} risk={6:F2}% balance={7:F2}",
                    Instrument.FullName, _ownerPrefix, _core.ModelTick, _stampOffsetMinutes,
                    _platformZone.Id, SizingMode, RiskPercent, _fixedBalanceBase));
            }
            else if (State == State.Realtime)
            {
                InitializeRecovery();
                StartSafetyTimer();
                Print(string.Format(CultureInfo.InvariantCulture,
                    "[FVG_DUO] realtime owner={0} recovery={1} blocked={2}",
                    _ownerPrefix, _recoveryReady, _executionBlocked));
            }
            else if (State == State.Terminated)
            {
                foreach (string tag in _visualTags) RemoveDrawObject(tag);
                _visualTags.Clear();
                _fvgHoverSnapshot = new Tuple<FvgDuoZone, string>[0];
                _fvgHover.Clear();
                DetachVisualHover();
                StopSafetyTimer();
                PersistSnapshot();
                UnsubscribeRecoveredAccountEvents();
                if (_ownerLock != null)
                {
                    _ownerLock.Dispose();
                    _ownerLock = null;
                }
                if (_journal != null)
                {
                    _journal.Flush();
                    _journal.Dispose();
                    _journal = null;
                    Print("[FVG_DUO] journal rows: " + _journalRows);
                }
            }
        }

        // ═══════════════════════════════════════════════════════════════════
        //  Configuration
        // ═══════════════════════════════════════════════════════════════════
        private FvgDuoEngine BuildEngine()
        {
            var e = new FvgDuoEngine
            {
                EnableOD = true,
                EnableTrend = true,
                FvgStrict = true,
                TrendRR = 3.0,
                EmaFastPeriod = 50,
                EmaSlowPeriod = 100,
                MergeAnchor = FvgDuoMergeAnchor.TrendEntry,
                WarmupBars = 1000,
                EntrySlippage = 0.0,

                // Optimal B3a only; no preset switch, no custom overrides.
                TrendAtrMult = B3A_TREND_ATR_MULT,
                OdStopPct = B3A_OD_STOP_PCT,
                TrendAfterStopout = B3A_TREND_AFTER_STOPOUT,
                AtrMethod = FvgDuoAtrMethod.Sma,
                AtrRef = FvgDuoAtrRef.C2
            };

            // "One tick" of the stop rules: the instrument's own grid, so 0.25
            // futures, 0.10 gold and 0.1 / 0.01 / 0.001 CFD grids all work from
            // one build. Override only to reproduce a fixed-tick study.
            double tick = Instrument.MasterInstrument.TickSize;
            if (tick <= 0.0) tick = 0.01;
            e.ModelTick = tick;

            e.Reset();
            return e;
        }

        private void DetectStampOffset()
        {
            // close-stamped bars put the first bar of a session one interval
            // after the session begin; open-stamped bars put it exactly there.
            try
            {
                _sessions.GetNextSession(Times[BipMinute][0], true);
                DateTime begin = _sessions.ActualSessionBegin;
                int last = CurrentBars[BipMinute];
                int floor = Math.Max(0, last - 30000);
                for (int i = last; i >= floor; i--)
                {
                    DateTime t = BarsArray[BipMinute].GetTime(i);
                    if (t > begin) continue;
                    int delta = (int)Math.Round((t - begin).TotalMinutes);
                    _stampOffsetMinutes = (delta == 0 || delta == 1) ? delta : 1;
                    return;
                }
            }
            catch (Exception)
            {
                _stampOffsetMinutes = 1;
            }
        }

        private DateTime ToNewYork(DateTime platformStamp)
        {
            if (_platformZone == null) _platformZone = Core.Globals.GeneralOptions.TimeZoneInfo;
            DateTime wall = DateTime.SpecifyKind(platformStamp, DateTimeKind.Unspecified);
            return TimeZoneInfo.ConvertTime(wall, _platformZone, NewYorkZone);
        }

        private DateTime ToPlatformTime(DateTime newYorkTime)
        {
            if (_platformZone == null) _platformZone = Core.Globals.GeneralOptions.TimeZoneInfo;
            DateTime wall = DateTime.SpecifyKind(newYorkTime, DateTimeKind.Unspecified);
            return TimeZoneInfo.ConvertTime(wall, NewYorkZone, _platformZone);
        }

        // ═══════════════════════════════════════════════════════════════════
        //  Bar history for the core
        // ═══════════════════════════════════════════════════════════════════
        private sealed class SeriesHistory : IFvgDuoHistory
        {
            private readonly FVG_Duo_NT8 _owner;
            public SeriesHistory(FVG_Duo_NT8 owner) { _owner = owner; }
            public void GetCompletedBars(int minutes, DateTime fromOpen, DateTime toOpen, List<FvgDuoBar> dest)
            {
                _owner.GetCompletedBars(minutes, fromOpen, toOpen, dest);
            }
        }

        private void GetCompletedBars(int minutes, DateTime fromOpen, DateTime toOpen, List<FvgDuoBar> dest)
        {
            int bip = minutes == 10 ? BipOdContext : BipTrendContext;
            int last = CurrentBars[bip];
            if (last < 0) return;

            // Walk back from the newest bar of that series. A bar counts only if
            // it has already closed at the instant being evaluated.
            for (int i = last; i >= 0; i--)
            {
                DateTime openNy = ToNewYork(BarsArray[bip].GetTime(i)).AddMinutes(-minutes);
                if (openNy > toOpen) continue;
                if (openNy < fromOpen) break;

                DateTime closeNy = openNy.AddMinutes(minutes);
                if (closeNy > _asOfNy) continue;

                dest.Add(new FvgDuoBar(openNy,
                    BarsArray[bip].GetHigh(i),
                    BarsArray[bip].GetLow(i),
                    BarsArray[bip].GetClose(i)));
            }
            dest.Reverse();
        }

        // ═══════════════════════════════════════════════════════════════════
        //  Session end for the current New York day
        // ═══════════════════════════════════════════════════════════════════
        private int SessionEndMinute(DateTime nyDay)
        {
            try
            {
                _sessions.GetNextSession(Times[BipMinute][0], true);
                DateTime endNy = ToNewYork(_sessions.ActualSessionEnd);
                int minute = endNy.Hour * 60 + endNy.Minute;
                // Only trust the template inside the cash session window; a 24h
                // or overnight template must not disable the RTH flatten.
                if (minute >= 13 * 60 && minute <= 17 * 60) return minute;
            }
            catch (Exception) { }

            return FvgDuoEngine.SessionEndMinuteFor(nyDay);
        }

        // ═══════════════════════════════════════════════════════════════════
        //  Main loop: the open of each M1 bar
        // ═══════════════════════════════════════════════════════════════════
        protected override void OnBarUpdate()
        {
            if (BarsInProgress != BipMinute) return;
            if (!IsFirstTickOfBar) return;
            if (_core == null) return;
            if (CurrentBars[BipMinute] < 1) return;
            if (CurrentBars[BipOdContext] < 3 || CurrentBars[BipTrendContext] < 2) return;

            DateTime nyOpen = ToNewYork(Times[BipMinute][0]).AddMinutes(-_stampOffsetMinutes);
            double barOpen = Opens[BipMinute][0];

            if (nyOpen.Date != _dayNy)
            {
                _dayNy = nyOpen.Date;
                _sessionEndMinute = SessionEndMinute(_dayNy);
            }

            _asOfNy = nyOpen;
            _actions.Clear();
            _core.OnM1Open(nyOpen, barOpen, _sessionEndMinute, _history, _actions);
            if (ShowVisuals)
            {
                DrawFvgCandidates(nyOpen);
                PruneVisuals(nyOpen.Date);
                DateTime previousNy = ToNewYork(Times[BipMinute][1]).AddMinutes(-_stampOffsetMinutes);
                int previousEnd = previousNy.Date == nyOpen.Date ? _sessionEndMinute
                    : FvgDuoEngine.SessionEndMinuteFor(previousNy.Date);
                UpdateSessionVisual(previousNy, previousEnd, Highs[BipMinute][1], Lows[BipMinute][1]);
                if (_core.M15LastOpen > DateTime.MinValue)
                    ShowTrendAverages(_core.M15LastOpen.AddMinutes(15), _core.EmaFast, _core.EmaSlow);
            }

            for (int i = 0; i < _actions.Count; i++)
            {
                Apply(_actions[i]);
            }

            DriveLifecycle();
            DrawTradeGeometry(nyOpen);
        }

        private void DrawFvgCandidates(DateTime throughNy)
        {
            if (_core == null || ChartControl == null) return;
            IList<FvgDuoZone> zones = _core.Zones;
            while (_fvgCandidatesSeen < zones.Count)
            {
                FvgDuoZone zone = zones[_fvgCandidatesSeen++];
                if (zone.End > throughNy) continue;
                string tag = _ownerPrefix + "_FVG_ZONE_" + zone.Source + "_"
                    + zone.Start.Ticks.ToString(CultureInfo.InvariantCulture);
                if (_currentFvgTag == tag) continue;
                if (!string.IsNullOrEmpty(_currentFvgTag)) RemoveOwnedVisual(_currentFvgTag);
                _currentFvgTag = tag;
                _currentFvgZone = zone;
                _visualTags.Add(tag);
                DrawFvgBox(tag, zone);
            }
        }

        private static Brush VisualBrush(byte red, byte green, byte blue)
        {
            var brush = new SolidColorBrush(Color.FromRgb(red, green, blue));
            brush.Freeze();
            return brush;
        }

        private string FvgDescription(FvgDuoZone zone, bool history)
        {
            return string.Format(CultureInfo.InvariantCulture,
                "FVG Duo | {0}{1} {2} FVG {3} | {4:HH:mm:ss} - {5:HH:mm:ss} NY",
                history ? "Trade-associated " : "Current ", zone.Source,
                zone.Bullish ? "Bullish" : "Bearish", history ? "history" : "candidate",
                zone.Start, zone.End);
        }

        private void DrawFvgBox(string tag, FvgDuoZone zone, bool history = false)
        {
            Brush color = zone.Source == "OD"
                ? (zone.Bullish ? Brushes.SteelBlue : Brushes.IndianRed)
                : (zone.Bullish ? Brushes.SeaGreen : Brushes.DarkOrange);
            DateTime startPlat = ToPlatformTime(zone.Start);
            DateTime endPlat = ToPlatformTime(zone.End);
            var box = Draw.Rectangle(this, tag, false, startPlat, zone.Top, endPlat, zone.Bottom,
                color, color, 25);
            box.AreaBrush = color;
            box.AreaOpacity = 25;
            box.OutlineStroke.Opacity = 0;
            box.IsLocked = true;
            box.Name = FvgDescription(zone, history);
            _fvgHover[tag] = Tuple.Create(zone, box.Name);
            _fvgHoverSnapshot = _fvgHover.Where(p => _visualTags.Contains(p.Key)).Select(p => p.Value).ToArray();
            AttachVisualHover();
        }

        private void RemoveOwnedVisual(string tag)
        {
            RemoveDrawObject(tag);
            _visualTags.Remove(tag);
            // A delayed fill can still associate its exact superseded candidate.
            if (tag != _pendingEntryFvgTag && tag != _pendingMergeFvgTag) _fvgHover.Remove(tag);
            _fvgHoverSnapshot = _fvgHover.Where(p => _visualTags.Contains(p.Key)).Select(p => p.Value).ToArray();
        }

        private string CandidateTagFor(string source)
        {
            return _currentFvgZone != null && _currentFvgZone.Source == source
                ? _currentFvgTag : string.Empty;
        }

        private void MarkFvgCandidateTraded(string tag)
        {
            Tuple<FvgDuoZone, string> item;
            if (string.IsNullOrEmpty(tag) || !_fvgHover.TryGetValue(tag, out item)) return;
            _visualTags.Add(tag);
            DrawFvgBox(tag, item.Item1, true);
            if (_currentFvgTag == tag)
            {
                _currentFvgTag = string.Empty;
                _currentFvgZone = null;
            }
        }

        private void PruneVisuals(DateTime currentNyDay)
        {
            // NT8 keeps every available historical date. Only an unconsumed
            // candidate expires with its signal date, matching MT5 StartDay.
            if (_currentFvgZone != null && _currentFvgZone.End.Date < currentNyDay)
            {
                RemoveOwnedVisual(_currentFvgTag);
                _currentFvgTag = string.Empty;
                _currentFvgZone = null;
            }
        }

        private void DrawTradeGeometry(DateTime throughNy)
        {
            if (!ShowVisuals || ChartControl == null || _book == null
                || _book.WeightedEntryPrice <= 0.0 || _book.OwnedQuantity <= 0) return;
            string prefix = "FVG_TRADE_" + _book.EntryName + "_";
            if (_visualTradePrefix != prefix)
            {
                _visualTradePrefix = prefix;
                _visualTradeStartNy = _recoveredLifecycle ? _posEntryNy : throughNy;
                int endMinute = _visualTradeStartNy.Date == _asOfNy.Date ? _sessionEndMinute
                    : FvgDuoEngine.SessionEndMinuteFor(_visualTradeStartNy.Date);
                _visualTradePlannedEndNy = _visualTradeStartNy.Date.AddMinutes(endMinute);
                _visualExitValue = 0.0;
                _visualExitQuantity = 0;
            }
            _visualTradeEntry = _book.WeightedEntryPrice;
            _visualTradeSide = _book.Side;
            _visualTradeSource = _posSource;
            _visualTradeStop = _posStop;
            _visualTradeTarget = _posTarget;
            DateTime right = throughNy > _visualTradePlannedEndNy ? throughNy : _visualTradePlannedEndNy;
            RenderTradeGeometry(right, _visualTradeTarget, "FVG Duo | " + _visualTradeSource + " | Booked entry");
        }

        private void RenderTradeGeometry(DateTime endNy, double target, string detail)
        {
            if (string.IsNullOrEmpty(_visualTradePrefix) || _visualTradeStartNy == DateTime.MinValue
                || endNy < _visualTradeStartNy || _visualTradeEntry <= 0.0 || _visualTradeStop <= 0.0) return;
            string entryTag = _visualTradePrefix + "ENTRY";
            var line = Draw.Line(this, entryTag, false, ToPlatformTime(_visualTradeStartNy),
                _visualTradeEntry, ToPlatformTime(endNy), _visualTradeEntry, Brushes.White, DashStyleHelper.Solid, 1);
            line.IsLocked = true;
            line.Name = detail;
            _visualTags.Add(entryTag);
            string stopTag = _visualTradePrefix + "STOP", targetTag = _visualTradePrefix + "TARGET";
            DrawOutlineBox(stopTag, _visualTradeStartNy, _visualTradeEntry, endNy, _visualTradeStop, VisualStopBrush);
            if (target > 0.0)
                DrawOutlineBox(targetTag, _visualTradeStartNy, _visualTradeEntry, endNy, target, VisualTargetBrush);
            else
                RemoveOwnedVisual(targetTag);
            // Drawing Name appears in native object properties; FVGs additionally
            // expose an actual hover tooltip without a custom drawing-tool file.
            if (target > 0.0)
            {
                var result = Draw.Rectangle(this, targetTag, false, ToPlatformTime(_visualTradeStartNy),
                    Math.Max(_visualTradeEntry, target), ToPlatformTime(endNy), Math.Min(_visualTradeEntry, target),
                    VisualTargetBrush, Brushes.Transparent, 0);
                result.OutlineStroke.Width = 1;
                result.IsLocked = true;
                result.Name = detail + (_visualTradeTarget > 0.0 ? " | Price target" : " | Realized profit, no resting TP");
            }
        }

        private void DrawOutlineBox(string tag, DateTime start, double entry, DateTime end, double price, Brush brush)
        {
            var box = Draw.Rectangle(this, tag, false, ToPlatformTime(start), Math.Max(entry, price), ToPlatformTime(end),
                Math.Min(entry, price), brush, Brushes.Transparent, 0);
            box.AreaOpacity = 0;
            box.OutlineStroke.Width = 1;
            box.IsLocked = true;
            box.Name = "FVG Duo | " + _visualTradeSource + " | Execution geometry";
            _visualTags.Add(tag);
        }

        private void RecordVisualExit(int quantity, double price)
        {
            if (_book == null || _visualTradePrefix != "FVG_TRADE_" + _book.EntryName + "_"
                || quantity <= 0 || price <= 0.0 || double.IsNaN(price) || double.IsInfinity(price)) return;
            _visualExitValue += quantity * price;
            _visualExitQuantity += quantity;
        }

        private void FinishTradeGeometry(DateTime exitNy, double exitPrice, string reason)
        {
            if (!ShowVisuals || ChartControl == null || string.IsNullOrEmpty(_visualTradePrefix)
                || exitNy < _visualTradeStartNy || exitPrice <= 0.0 || double.IsNaN(exitPrice)
                || double.IsInfinity(exitPrice) || reason == "UNCONFIRMED") return;
            double bookedPrice = _visualExitQuantity > 0 ? _visualExitValue / _visualExitQuantity : exitPrice;
            double target = _visualTradeTarget;
            if (target <= 0.0 && _visualTradeSide * (bookedPrice - _visualTradeEntry) > 0.0) target = bookedPrice;
            RenderTradeGeometry(exitNy, target, string.Format(CultureInfo.InvariantCulture,
                "FVG Duo | {0} | Booked {1} exit @ {2:F2}", _visualTradeSource, reason, bookedPrice));
            _visualTradePrefix = string.Empty;
        }

        private void UpdateSessionVisual(DateTime openNy, int endMinute, double high, double low)
        {
            int minute = openNy.Hour * 60 + openNy.Minute;
            if (openNy == DateTime.MinValue || minute < 570 || minute >= endMinute
                || double.IsNaN(high) || double.IsNaN(low) || double.IsInfinity(high)
                || double.IsInfinity(low) || high < low) return;
            if (_visualSessionDay != openNy.Date)
            {
                _visualSessionDay = openNy.Date;
                _visualSessionHigh = high;
                _visualSessionLow = low;
            }
            _visualSessionHigh = Math.Max(_visualSessionHigh, high);
            _visualSessionLow = Math.Min(_visualSessionLow, low);
            string tag = _ownerPrefix + "_FVG_SESSION_" + openNy.Date.Ticks.ToString(CultureInfo.InvariantCulture);
            var box = Draw.Rectangle(this, tag, false, ToPlatformTime(openNy.Date.AddMinutes(570)),
                _visualSessionHigh, ToPlatformTime(openNy.Date.AddMinutes(endMinute)), _visualSessionLow,
                VisualSessionBrush, Brushes.Transparent, 0);
            box.OutlineStroke.Width = 1;
            box.OutlineStroke.DashStyleHelper = DashStyleHelper.Dot;
            box.IsLocked = true;
            box.Name = "FVG Duo | NY cash session | Observed completed M1 range";
            _visualTags.Add(tag);
        }

        private void ShowTrendAverages(DateTime closeNy, double fast, double slow)
        {
            if (closeNy == DateTime.MinValue || closeNy <= _visualEmaLastClose
                || double.IsNaN(fast) || double.IsNaN(slow) || double.IsInfinity(fast) || double.IsInfinity(slow)) return;
            if (_visualEmaLastClose > DateTime.MinValue && closeNy - _visualEmaLastClose == TimeSpan.FromMinutes(15))
            {
                string suffix = _visualEmaLastClose.Ticks.ToString(CultureInfo.InvariantCulture);
                string fastTag = _ownerPrefix + "_FVG_EMA_FAST_" + suffix, slowTag = _ownerPrefix + "_FVG_EMA_SLOW_" + suffix;
                var fastLine = Draw.Line(this, fastTag, false, ToPlatformTime(_visualEmaLastClose), _visualEmaFast,
                    ToPlatformTime(closeNy), fast, VisualTargetBrush, DashStyleHelper.Solid, 1);
                var slowLine = Draw.Line(this, slowTag, false, ToPlatformTime(_visualEmaLastClose), _visualEmaSlow,
                    ToPlatformTime(closeNy), slow, VisualSlowBrush, DashStyleHelper.Solid, 1);
                fastLine.IsLocked = true;
                slowLine.IsLocked = true;
                fastLine.Name = "FVG Duo | M15 EMA 50 | Completed-bar engine values";
                slowLine.Name = "FVG Duo | M15 EMA 100 | Completed-bar engine values";
                _visualTags.Add(fastTag);
                _visualTags.Add(slowTag);
            }
            _visualEmaLastClose = closeNy;
            _visualEmaFast = fast;
            _visualEmaSlow = slow;
        }

        private string FvgTooltipAt(DateTime platformTime, double price)
        {
            DateTime ny = ToNewYork(platformTime);
            Tuple<FvgDuoZone, string>[] snapshot = _fvgHoverSnapshot;
            for (int i = snapshot.Length - 1; i >= 0; i--)
            {
                FvgDuoZone zone = snapshot[i].Item1;
                if (ny >= zone.Start && ny <= zone.End && price >= zone.Bottom && price <= zone.Top)
                    return snapshot[i].Item2;
            }
            return string.Empty;
        }

        private void AttachVisualHover()
        {
            if (!ShowVisuals || ChartControl == null || _hoverChartControl == ChartControl) return;
            var control = ChartControl;
            control.Dispatcher.BeginInvoke(new Action(() =>
            {
                if (State == State.Terminated || _hoverChartControl == control) return;
                _hoverChartControl = control;
                control.MouseMove += OnVisualMouseMove;
                control.MouseLeave += OnVisualMouseLeave;
            }));
        }

        private void OnVisualMouseMove(object sender, System.Windows.Input.MouseEventArgs args)
        {
            var control = sender as NinjaTrader.Gui.Chart.ChartControl;
            if (!ShowVisuals || control == null || ChartPanel == null) return;
            var panelPoint = args.GetPosition(ChartPanel);
            string detail = string.Empty;
            if (panelPoint.X >= 0 && panelPoint.X <= ChartPanel.ActualWidth
                && panelPoint.Y >= 0 && panelPoint.Y <= ChartPanel.ActualHeight)
            {
                var point = args.GetPosition(control);
                var scale = ChartPanel.Scales[ScaleJustification];
                detail = FvgTooltipAt(control.GetTimeByX((int)point.X), scale.GetValueByYWpf(point.Y));
            }
            if (string.IsNullOrEmpty(detail))
            {
                if (_visualTooltip != null) _visualTooltip.IsOpen = false;
                return;
            }
            if (_visualTooltip == null)
                _visualTooltip = new System.Windows.Controls.ToolTip
                {
                    PlacementTarget = control,
                    Placement = System.Windows.Controls.Primitives.PlacementMode.MousePoint,
                    StaysOpen = true
                };
            _visualTooltip.Content = detail;
            _visualTooltip.IsOpen = true;
        }

        private void OnVisualMouseLeave(object sender, System.Windows.Input.MouseEventArgs args)
        {
            if (_visualTooltip != null) _visualTooltip.IsOpen = false;
        }

        private void DetachVisualHover()
        {
            var control = _hoverChartControl;
            if (control == null) return;
            control.Dispatcher.BeginInvoke(new Action(() =>
            {
                control.MouseMove -= OnVisualMouseMove;
                control.MouseLeave -= OnVisualMouseLeave;
                if (_visualTooltip != null) _visualTooltip.IsOpen = false;
                _visualTooltip = null;
                _hoverChartControl = null;
            }));
        }

        // ═══════════════════════════════════════════════════════════════════
        //  Actions -> orders
        // ═══════════════════════════════════════════════════════════════════
        private void Apply(FvgDuoAction a)
        {
            if (_recoveredLifecycle) return; // exact broker protection stays idle after restart
            switch (a.Kind)
            {
                case FvgDuoActionKind.Entry:
                    ApplyEntry(a);
                    break;
                case FvgDuoActionKind.Close:
                    ApplyClose(a);
                    break;
                case FvgDuoActionKind.Modify:
                    ApplyModify(a);
                    break;
            }
        }

        private void ApplyEntry(FvgDuoAction a)
        {
            if (_executionBlocked || (State == State.Realtime && !_recoveryReady)
                || _book != null || AccountSignedPosition() != 0 || HasActiveOwnedOrders()
                || HasForeignActiveOrdersForInstrument()
                || (State == State.Realtime && (Account == null
                    || Account.ConnectionStatus != ConnectionStatus.Connected)))
            {
                RejectModelEntry(a, "owned/account lifecycle not flat");
                return;
            }

            double quote = ExecutableEntryQuote(a.Side);
            double stop = RoundOrderPrice(a.Stop);
            double target = a.Target > 0.0 ? RoundOrderPrice(a.Target) : 0.0;
            if (!ValidEntryGeometry(a.Side, quote, stop, target))
            {
                RejectModelEntry(a, "invalid executable quote or broker-grid geometry");
                return;
            }

            FvgDuoRiskTerms terms;
            string riskError;
            if (!TryRiskTerms(out terms, out riskError))
            {
                RejectModelEntry(a, riskError);
                return;
            }

            double availableMargin, marginPerContract;
            int maxContracts;
            if (!TryMarginEvidence(a.Side, out availableMargin, out marginPerContract,
                                   out maxContracts, out riskError))
            {
                RejectModelEntry(a, riskError);
                return;
            }

            double budget = CapturedCashBudget();
            int qty = SizingMode == SizingModeNT8.FixedLots
                ? FvgDuoFillRisk.FixedSize(FixedContracts, terms, maxContracts,
                                           availableMargin, marginPerContract)
                : FvgDuoFillRisk.Size(quote, stop, budget, terms, maxContracts,
                                      availableMargin, marginPerContract);
            if (qty <= 0)
            {
                RejectModelEntry(a, "risk/margin floor allows zero contracts");
                return;
            }

            string tradeId = DateTime.UtcNow.Ticks.ToString("X", CultureInfo.InvariantCulture)
                           + (++_tradeSequence).ToString("X", CultureInfo.InvariantCulture);
            _book = new FvgDuoProtectedSliceBook(_ownerPrefix, tradeId, a.Side,
                SizingMode == SizingModeNT8.FixedLots ? double.MaxValue : budget,
                terms, stop, target, SizingMode == SizingModeNT8.FixedLots);
            _book.SetEntryIntent(qty);
            _book.OnEntryOrderUpdate(string.Empty, FvgDuoTransportState.SubmitPending);

            _posSource = a.Source;
            _posSide = a.Side;
            _posEntryModel = a.Entry;
            _posEntryFill = 0.0;
            _posStop = stop;
            _posTarget = target;
            _posEntryNy = _asOfNy;
            _entrySlippage = 0.0;
            _pendingMergeSource = string.Empty;
            _pendingExitReason = string.Empty;
            _pendingFinalizeReason = string.Empty;

            if (!PersistOrBlock()) return; // entry intent must be durable before transport
            _pendingEntryFvgTag = CandidateTagFor(a.Source);

            try
            {
                OrderAction action = a.Side > 0 ? OrderAction.Buy : OrderAction.SellShort;
                _entryOrder = SubmitOrderUnmanaged(BipMinute, action, OrderType.Market,
                    qty, 0.0, 0.0, string.Empty, _book.EntryName);
                TrackOrder(_entryOrder);
                if (_entryOrder == null)
                {
                    _book.OnEntryOrderUpdate(string.Empty, FvgDuoTransportState.Rejected);
                    QueueFinalization("ENTRY_REJECT", _asOfNy, quote);
                }
            }
            catch (Exception ex)
            {
                _book.OnEntryOrderUpdate(string.Empty, FvgDuoTransportState.Rejected);
                SetExecutionBlock("Entry transport failed: " + ex.Message);
                QueueFinalization("ENTRY_REJECT", _asOfNy, quote);
            }
            PersistSnapshot();
        }

        private void ApplyClose(FvgDuoAction a)
        {
            if (_book == null) return; // never close an unowned net position
            if (AccountSignedPosition() == 0 && _book.OwnedQuantity > 0)
            {
                CheckDivergence();
                return;
            }

            _pendingExitReason = a.Reason == "FLIP" ? "FLIP" : "TIME";
            _book.BeginClose(_pendingExitReason);
            PersistOrBlock();
            DriveLifecycle();
        }

        private void ApplyModify(FvgDuoAction a)
        {
            if (_book == null || AccountSignedPosition() == 0) return;
            double stop = RoundOrderPrice(a.Stop);
            double target = a.Target > 0.0 ? RoundOrderPrice(a.Target) : 0.0;
            if (!ValidStopForSide(_book.Side, stop))
            {
                SetExecutionBlock("Invalid broker-grid merge stop");
                return;
            }

            _pendingMergeSource = a.Source;
            _pendingMergeFvgTag = CandidateTagFor(a.Source == "MERGED" ? "OD" : a.Source);
            _book.BeginMerge(stop, target, a.Source);
            PersistOrBlock();
            DriveLifecycle();
        }

        private double AccountSize()
        {
            try
            {
                if (Account != null && Account.Denomination == Currency.UsDollar)
                {
                    double value = Account.Get(AccountItem.CashValue, Currency.UsDollar);
                    if (FvgDuoFillRisk.FinitePositive(value)) return value;
                }
            }
            catch (Exception) { }
            return 0.0;
        }

        // ═══════════════════════════════════════════════════════════════════
        //  Fills
        // ═══════════════════════════════════════════════════════════════════
        protected override void OnExecutionUpdate(Execution execution, string executionId, double price,
                                                  int quantity, MarketPosition marketPosition,
                                                  string orderId, DateTime time)
        {
            ProcessOwnedExecution(execution, executionId, price, quantity, time);
        }

        private void ProcessOwnedExecution(Execution execution, string executionId, double price,
                                           int quantity, DateTime time)
        {
            if (execution == null || execution.Order == null || _book == null) return;
            string name = execution.Order.Name ?? string.Empty;
            if (!IsOwnedName(name)) return;
            TrackOrder(execution.Order);
            string exactExecutionId = !string.IsNullOrEmpty(executionId) ? executionId
                : (execution.Order.OrderId ?? name) + "|" + time.Ticks.ToString(CultureInfo.InvariantCulture)
                  + "|" + price.ToString("R", CultureInfo.InvariantCulture)
                  + "|" + quantity.ToString(CultureInfo.InvariantCulture);

            DateTime ny = ToNewYork(time);
            if (name == _book.EntryName)
            {
                // Process every execution, including PartFilled. The book dedups
                // exact execution ids and creates one protected contract slice.
                _book.OnEntryExecution(exactExecutionId, quantity, price);
                _posEntryFill = _book.WeightedEntryPrice;
                _entrySlippage = _posSide > 0
                    ? _posEntryFill - _posEntryModel : _posEntryModel - _posEntryFill;
                DrawTradeGeometry(ny);
                if (_book.OwnedQuantity > 0) MarkFvgCandidateTraded(_pendingEntryFvgTag);
                _pendingEntryFvgTag = string.Empty;
                PersistOrBlock();
                DriveLifecycle();
                return;
            }

            int before = _book.OwnedQuantity;
            FvgDuoIntentKind intentBefore = _book.IntentKind;
            _book.OnExitExecution(exactExecutionId, name, quantity, price);
            if (_book.OwnedQuantity == before) return; // duplicate/foreign role
            RecordVisualExit(before - _book.OwnedQuantity, price);

            string reason = ExitReasonFor(name, intentBefore);
            _pendingExitReason = reason;
            _pendingFinalizePrice = price;
            _pendingFinalizeTime = ny;
            PersistOrBlock();

            int accountSigned = AccountSignedPosition();
            if (!_book.EntryExecutionsSettled)
            {
                _book.BeginClose(reason);
                PersistOrBlock();
            }
            else if (_book.OwnedQuantity == 0 && accountSigned == 0)
                QueueFinalization(reason, ny, price);
            else if (accountSigned == 0 && _book.OwnedQuantity > 0)
                ReportDivergence(accountSigned);

            DriveLifecycle();
        }

        protected override void OnOrderUpdate(Order order, double limitPrice, double stopPrice, int quantity,
                                              int filled, double averageFillPrice, OrderState orderState,
                                              DateTime time, ErrorCode error, string comment)
        {
            ProcessOwnedOrderUpdate(order, limitPrice, stopPrice, averageFillPrice,
                filled, orderState, time, error, comment);
        }

        private void ProcessOwnedOrderUpdate(Order order, double limitPrice, double stopPrice,
                                             double averageFillPrice, int filled, OrderState orderState,
                                             DateTime time, ErrorCode error, string comment)
        {
            if (order == null || _book == null || !IsOwnedName(order.Name)) return;
            TrackOrder(order);

            if (orderState == OrderState.Unknown || orderState == OrderState.Suspended)
                SetExecutionBlock("Unknown/suspended owned order evidence: " + order.Name);
            if (error != ErrorCode.NoError)
                SetExecutionBlock("Owned order transport error " + error + " on " + order.Name
                    + ": " + (comment ?? string.Empty));
            FvgDuoTransportState state = MapOrderState(orderState);
            double price = order.Name == _book.EntryName ? averageFillPrice
                : IsStopName(order.Name) ? stopPrice : limitPrice;
            _book.OnOrderUpdate(order.Name, order.OrderId ?? string.Empty, state, price, filled);

            if (orderState == OrderState.Rejected)
            {
                Print(string.Format(CultureInfo.InvariantCulture,
                    "[FVG_DUO][ORDER_REJECT] {0} error={1} detail={2}",
                    order.Name, error, comment));
            }
            if (order.Name == _book.EntryName && _book.OwnedQuantity == 0
                && _book.EntryExecutionsSettled
                && (orderState == OrderState.Rejected || orderState == OrderState.Cancelled))
                QueueFinalization(orderState == OrderState.Rejected ? "ENTRY_REJECT" : "ENTRY_CANCEL",
                    ToNewYork(time), averageFillPrice);

            PersistOrBlock();
            DriveLifecycle();
        }

        // ═══════════════════════════════════════════════════════════════════
        //  Risk evidence, scoped ownership and protected-slice transport
        // ═══════════════════════════════════════════════════════════════════
        private string BuildOwnerPrefix()
        {
            string account = Account == null ? "NO_ACCOUNT" : Account.Name;
            string instrument = Instrument == null ? "NO_INSTRUMENT" : Instrument.FullName;
            string tag = string.IsNullOrWhiteSpace(InstanceTag) ? "A" : InstanceTag.Trim();
            string key = account + "|" + instrument + "|Optimal_B3a|" + tag;
            uint hash = 2166136261;
            for (int i = 0; i < key.Length; i++)
            {
                hash ^= key[i];
                hash *= 16777619;
            }
            return "FD8_" + hash.ToString("X8", CultureInfo.InvariantCulture);
        }

        private bool TryRiskTerms(out FvgDuoRiskTerms terms, out string error)
        {
            terms = new FvgDuoRiskTerms();
            error = string.Empty;
            if (Instrument == null || Instrument.MasterInstrument == null)
            {
                error = "missing instrument metadata";
                return false;
            }
            if (Instrument.MasterInstrument.Currency != Currency.UsDollar
                || Account == null || Account.Denomination != Currency.UsDollar)
            {
                error = "missing USD account/instrument conversion evidence";
                return false;
            }

            double commission = RoundTripCommissionOverride > 0.0
                ? RoundTripCommissionOverride : ScheduledCommission();
            terms = new FvgDuoRiskTerms(Instrument.MasterInstrument.PointValue,
                Instrument.MasterInstrument.TickSize, commission, StressedSlippageTicks);
            if (!terms.Valid)
            {
                error = "invalid point/tick/commission/slippage metadata";
                return false;
            }
            return true;
        }

        private double ScheduledCommission()
        {
            string root = Instrument == null || Instrument.MasterInstrument == null
                ? string.Empty : (Instrument.MasterInstrument.Name ?? string.Empty).ToUpperInvariant();
            if (root == "ES" || root == "NQ") return 5.76;
            if (root == "MES" || root == "MNQ") return 1.82;
            if (root == "GC") return 6.20;
            // MGC and unsupported instruments require explicit verified input.
            return 0.0;
        }

        private bool TryMarginEvidence(int side, out double availableMargin,
                                       out double marginPerContract, out int maxContracts,
                                       out string error)
        {
            availableMargin = 0.0;
            marginPerContract = 0.0;
            maxContracts = 0;
            error = string.Empty;
            try
            {
                if (Account == null || Instrument == null || Instrument.MasterInstrument == null)
                    throw new InvalidOperationException("missing account/instrument");
                InstrumentRisk risk;
                if (Account.RiskByMasterInstrument == null
                    || !Account.RiskByMasterInstrument.TryGetValue(Instrument.MasterInstrument, out risk)
                    || risk == null || !risk.IsEnabledForTrading)
                    throw new InvalidOperationException("missing enabled instrument margin schedule");

                marginPerContract = side > 0 ? risk.BuyIntradayMargin : risk.SellIntradayMargin;
                if (!FvgDuoFillRisk.FinitePositive(marginPerContract))
                    marginPerContract = risk.InitialMargin;
                availableMargin = Account.Get(AccountItem.ExcessIntradayMargin, Currency.UsDollar);
                if (!FvgDuoFillRisk.FinitePositive(marginPerContract)
                    || !FvgDuoFillRisk.FinitePositive(availableMargin))
                    throw new InvalidOperationException("invalid available/per-contract margin evidence");

                maxContracts = int.MaxValue;
                maxContracts = PositiveMinimum(maxContracts, Account.MaxOrderSize);
                maxContracts = PositiveMinimum(maxContracts, Account.MaxPositionSize);
                maxContracts = PositiveMinimum(maxContracts, risk.MaxOrderSize);
                maxContracts = PositiveMinimum(maxContracts, risk.MaxPositionSize);
                if (maxContracts <= 0) throw new InvalidOperationException("invalid broker quantity limits");
                return true;
            }
            catch (Exception ex)
            {
                error = "margin evidence unavailable: " + ex.Message;
                return false;
            }
        }

        private static int PositiveMinimum(int current, int candidate)
        {
            return candidate > 0 ? Math.Min(current, candidate) : current;
        }

        private double CapturedCashBudget()
        {
            switch (SizingMode)
            {
                case SizingModeNT8.FixedLots:
                    return double.MaxValue;
                case SizingModeNT8.RiskPercent:
                    return AccountSize() * (RiskPercent / 100.0);
                case SizingModeNT8.CashRisk:
                    return CashRisk;
                default:
                    return _fixedBalanceBase * (RiskPercent / 100.0);
            }
        }

        private double ExecutableEntryQuote(int side)
        {
            try
            {
                if (State == State.Realtime)
                    return side > 0 ? GetCurrentAsk(BipMinute) : GetCurrentBid(BipMinute);
                return Opens[BipMinute][0];
            }
            catch (Exception) { return 0.0; }
        }

        private double ExecutableBid()
        {
            try
            {
                return State == State.Realtime ? GetCurrentBid(BipMinute) : Closes[BipMinute][0];
            }
            catch (Exception) { return 0.0; }
        }

        private double ExecutableAsk()
        {
            try
            {
                return State == State.Realtime ? GetCurrentAsk(BipMinute) : Closes[BipMinute][0];
            }
            catch (Exception) { return 0.0; }
        }

        private double RoundOrderPrice(double price)
        {
            if (!FvgDuoFillRisk.FinitePositive(price) || Instrument == null
                || Instrument.MasterInstrument == null) return 0.0;
            return Instrument.MasterInstrument.RoundToTickSize(price);
        }

        private bool ValidEntryGeometry(int side, double quote, double stop, double target)
        {
            if (!FvgDuoFillRisk.FinitePositive(quote) || !FvgDuoFillRisk.FinitePositive(stop))
                return false;
            if (side > 0 && stop >= quote) return false;
            if (side < 0 && stop <= quote) return false;
            if (target > 0.0 && side > 0 && target <= quote) return false;
            if (target > 0.0 && side < 0 && target >= quote) return false;
            return side == 1 || side == -1;
        }

        private bool ValidStopForSide(int side, double stop)
        {
            if (!FvgDuoFillRisk.FinitePositive(stop)) return false;
            double bid = ExecutableBid(), ask = ExecutableAsk();
            return side > 0 ? FvgDuoFillRisk.FinitePositive(bid) && stop < bid
                            : FvgDuoFillRisk.FinitePositive(ask) && stop > ask;
        }

        private void RejectModelEntry(FvgDuoAction action, string reason)
        {
            Print("[FVG_DUO] Entry skipped: " + reason);
            if (_core != null) _core.ReportExit(action.Source, "RISK_SKIP", _asOfNy);
        }

        private void StartSafetyTimer()
        {
            StopSafetyTimer();
            _safetyTimer = new System.Timers.Timer(1000.0);
            _safetyTimer.AutoReset = true;
            _safetyTimer.Elapsed += SafetyTimerElapsed;
            _safetyTimer.Start();
        }

        private void SafetyTimerElapsed(object sender, System.Timers.ElapsedEventArgs args)
        {
            try { TriggerCustomEvent(o => SafetyStep(), null); }
            catch (InvalidOperationException) { }
        }

        private void StopSafetyTimer()
        {
            if (_safetyTimer == null) return;
            _safetyTimer.Stop();
            _safetyTimer.Elapsed -= SafetyTimerElapsed;
            _safetyTimer.Dispose();
            _safetyTimer = null;
        }

        private void SafetyStep()
        {
            if (State != State.Realtime) return;
            CheckDivergence();
            ReconcileProtectionEvidence();
            DriveLifecycle();
        }

        private void SubscribeRecoveredAccountEvents()
        {
            if (_accountEventsSubscribed || Account == null) return;
            Account.OrderUpdate += RecoveredAccountOrderUpdate;
            Account.ExecutionUpdate += RecoveredAccountExecutionUpdate;
            _accountEventsSubscribed = true;
        }

        private void UnsubscribeRecoveredAccountEvents()
        {
            if (!_accountEventsSubscribed || Account == null) return;
            Account.OrderUpdate -= RecoveredAccountOrderUpdate;
            Account.ExecutionUpdate -= RecoveredAccountExecutionUpdate;
            _accountEventsSubscribed = false;
        }

        private void RecoveredAccountOrderUpdate(object sender, OrderEventArgs args)
        {
            Order order = args == null ? null : args.Order;
            if (order == null || !IsOwnedOrder(order)) return;
            double limit = args.LimitPrice;
            double stop = args.StopPrice;
            double average = args.AverageFillPrice;
            int filled = args.Filled;
            OrderState state = args.OrderState;
            DateTime time = args.Time;
            ErrorCode error = args.Error;
            string comment = args.Comment;
            try
            {
                TriggerCustomEvent(o =>
                {
                    if (_recoveredLifecycle)
                        ProcessOwnedOrderUpdate(order, limit, stop, average, filled,
                            state, time, error, comment);
                }, null);
            }
            catch (InvalidOperationException) { }
        }

        private void RecoveredAccountExecutionUpdate(object sender, ExecutionEventArgs args)
        {
            Execution execution = args == null ? null : args.Execution;
            if (execution == null || execution.Order == null || !IsOwnedOrder(execution.Order)) return;
            string executionId = args.ExecutionId;
            double price = args.Price;
            int quantity = args.Quantity;
            DateTime time = args.Time;
            try
            {
                TriggerCustomEvent(o =>
                {
                    if (_recoveredLifecycle)
                        ProcessOwnedExecution(execution, executionId, price, quantity, time);
                }, null);
            }
            catch (InvalidOperationException) { }
        }

        private void InitializeRecovery()
        {
            UnsubscribeRecoveredAccountEvents();
            _recoveryReady = false;
            _recoveredLifecycle = false;
            _ownedOrders.Clear();
            _entryOrder = null;
            if (Account == null || Instrument == null)
            {
                SetExecutionBlock("Recovery unavailable: missing account/instrument");
                return;
            }
            if (Account.ConnectionStatus != ConnectionStatus.Connected)
            {
                SetExecutionBlock("Recovery unavailable: account connection is not connected");
                return;
            }
            try
            {
                if (_ownerLock == null)
                {
                    Directory.CreateDirectory(Path.GetDirectoryName(_snapshotPath));
                    _ownerLock = new FileStream(_snapshotPath + ".lock", FileMode.OpenOrCreate,
                        FileAccess.ReadWrite, FileShare.None);
                }
            }
            catch (Exception ex)
            {
                SetExecutionBlock("Duplicate/non-exclusive instance tag: " + ex.Message);
                return;
            }

            int accountSigned = AccountSignedPosition();
            List<Order> activeOwned = AccountOrdersSnapshot().Where(IsOwnedOrder)
                .Where(IsOrderActive).ToList();
            if (!File.Exists(_snapshotPath))
            {
                if (FvgDuoProtectedSliceBook.ValidateUnknownRestart(accountSigned,
                    activeOwned.Count > 0) == FvgDuoRestartStatus.Clean)
                    _recoveryReady = true;
                else
                    SetExecutionBlock("Unknown restart evidence; account/owned orders not clean");
                return;
            }

            string xml;
            try { xml = File.ReadAllText(_snapshotPath, Encoding.UTF8); }
            catch (Exception ex)
            {
                SetExecutionBlock("Recovery snapshot read failed: " + ex.Message);
                return;
            }

            FvgDuoProtectedSliceBook restored;
            if (!FvgDuoProtectedSliceBook.TryDeserialize(xml, _ownerPrefix, Account.Name,
                Instrument.FullName, out restored))
            {
                SetExecutionBlock("Recovery snapshot absent/corrupt/mismatched; no net adoption");
                return;
            }

            _book = restored;
            if (!LoadSnapshotMetadata(xml))
            {
                SetExecutionBlock("Recovery shell metadata invalid");
                return;
            }
            // Subscribe before the final broker snapshot so a fill/order change
            // cannot disappear in the validation-to-activation window.
            _recoveredLifecycle = true;
            SubscribeRecoveredAccountEvents();
            activeOwned = AccountOrdersSnapshot().Where(IsOwnedOrder)
                .Where(IsOrderActive).ToList();
            accountSigned = AccountSignedPosition();
            IList<FvgDuoOwnedOrderEvidence> evidence = BuildRecoveryEvidence(activeOwned);
            FvgDuoRestartStatus status = restored.ValidateRestart(accountSigned, evidence);
            if (status == FvgDuoRestartStatus.Blocked)
            {
                _recoveredLifecycle = false;
                UnsubscribeRecoveredAccountEvents();
                SetExecutionBlock("Recovery evidence does not exactly match persisted owned lineage");
                return;
            }

            foreach (Order order in activeOwned) TrackOrder(order);
            _entryOrder = FindActiveOrder(restored.EntryName);
            _recoveryReady = true;
            _recoveredLifecycle = status == FvgDuoRestartStatus.Ready;
            if (_recoveredLifecycle)
            {
                Print("[FVG_DUO] Exact owned position/brackets recovered; model actions idle until flat.");
            }
            else
            {
                UnsubscribeRecoveredAccountEvents();
                QueueFinalization(string.IsNullOrEmpty(_pendingFinalizeReason)
                    ? "RECOVERY_FLAT" : _pendingFinalizeReason,
                    _pendingFinalizeTime == DateTime.MinValue ? ToNewYork(DateTime.Now) : _pendingFinalizeTime,
                    _pendingFinalizePrice);
            }
            DriveLifecycle();
        }

        private IList<FvgDuoOwnedOrderEvidence> BuildRecoveryEvidence(IList<Order> orders)
        {
            var result = new List<FvgDuoOwnedOrderEvidence>();
            foreach (Order order in orders)
            {
                int outstanding = Math.Max(0, order.Quantity - order.Filled);
                bool isStop = IsStopName(order.Name);
                double price = isStop ? order.StopPrice : order.LimitPrice;
                result.Add(new FvgDuoOwnedOrderEvidence(order.Name, order.OrderId,
                    IsOrderActive(order), isStop, outstanding, price, order.Oco));
            }
            return result;
        }

        private bool LoadSnapshotMetadata(string xml)
        {
            try
            {
                XElement root = XDocument.Parse(xml).Root;
                if (root == null) return false;
                _posSource = Attribute(root, "posSource");
                _posSide = ParseIntAttribute(root, "posSide");
                _posEntryModel = ParseDoubleAttribute(root, "posEntryModel");
                _posEntryFill = ParseDoubleAttribute(root, "posEntryFill");
                _posStop = ParseDoubleAttribute(root, "posStop");
                _posTarget = ParseDoubleAttribute(root, "posTarget");
                _posEntryNy = DateTime.FromBinary(ParseLongAttribute(root, "posEntryNy"));
                _pendingMergeSource = Attribute(root, "pendingMergeSource");
                _pendingExitReason = Attribute(root, "pendingExitReason");
                _pendingFinalizeReason = Attribute(root, "pendingFinalizeReason");
                long finalTime = ParseLongAttribute(root, "pendingFinalizeTime");
                _pendingFinalizeTime = finalTime == 0 ? DateTime.MinValue : DateTime.FromBinary(finalTime);
                _pendingFinalizePrice = ParseDoubleAttribute(root, "pendingFinalizePrice");
                return _posSide == 1 || _posSide == -1 || _book.OwnedQuantity == 0;
            }
            catch (Exception) { return false; }
        }

        private bool PersistOrBlock()
        {
            if (PersistSnapshot()) return true;
            SetExecutionBlock("Durable lifecycle write failed; new transport blocked");
            return false;
        }

        private bool PersistSnapshot()
        {
            if (State != State.Realtime || _book == null) return true;
            string temp = _snapshotPath + ".tmp";
            try
            {
                XDocument document = XDocument.Parse(_book.Serialize(Account.Name, Instrument.FullName));
                XElement root = document.Root;
                root.SetAttributeValue("posSource", _posSource ?? string.Empty);
                root.SetAttributeValue("posSide", _posSide);
                root.SetAttributeValue("posEntryModel", Invariant(_posEntryModel));
                root.SetAttributeValue("posEntryFill", Invariant(_posEntryFill));
                root.SetAttributeValue("posStop", Invariant(_posStop));
                root.SetAttributeValue("posTarget", Invariant(_posTarget));
                root.SetAttributeValue("posEntryNy", _posEntryNy.ToBinary());
                root.SetAttributeValue("pendingMergeSource", _pendingMergeSource ?? string.Empty);
                root.SetAttributeValue("pendingExitReason", _pendingExitReason ?? string.Empty);
                root.SetAttributeValue("pendingFinalizeReason", _pendingFinalizeReason ?? string.Empty);
                root.SetAttributeValue("pendingFinalizeTime",
                    _pendingFinalizeTime == DateTime.MinValue ? 0L : _pendingFinalizeTime.ToBinary());
                root.SetAttributeValue("pendingFinalizePrice", Invariant(_pendingFinalizePrice));

                Directory.CreateDirectory(Path.GetDirectoryName(_snapshotPath));
                File.WriteAllText(temp, document.ToString(SaveOptions.DisableFormatting),
                    new UTF8Encoding(false));
                if (File.Exists(_snapshotPath))
                    File.Replace(temp, _snapshotPath, _snapshotPath + ".bak", true);
                else
                    File.Move(temp, _snapshotPath);
                return true;
            }
            catch (Exception ex)
            {
                Print("[FVG_DUO][RECOVERY] write failed: " + ex.Message);
                return false;
            }
        }

        private void DeleteCleanSnapshot()
        {
            try
            {
                if (File.Exists(_snapshotPath)) File.Delete(_snapshotPath);
                if (File.Exists(_snapshotPath + ".tmp")) File.Delete(_snapshotPath + ".tmp");
                if (File.Exists(_snapshotPath + ".bak")) File.Delete(_snapshotPath + ".bak");
            }
            catch (Exception ex)
            {
                SetExecutionBlock("Clean snapshot deletion failed: " + ex.Message);
            }
        }

        private void DriveLifecycle()
        {
            if (_drivingLifecycle || _book == null) return;
            if (State == State.Realtime && !_recoveryReady) return;
            _drivingLifecycle = true;
            try
            {
                int accountSigned = AccountSignedPosition();
                ReportDivergence(accountSigned);
                FvgDuoIntentKind before = _book.IntentKind;
                List<FvgDuoSliceCommand> commands = _book.NextCommands(accountSigned,
                    ExecutableBid(), ExecutableAsk());
                if (before == FvgDuoIntentKind.None
                    && _book.IntentKind == FvgDuoIntentKind.RiskReduction)
                {
                    _pendingExitReason = "FILL_RISK";
                    Print(string.Format(CultureInfo.InvariantCulture,
                        "[FVG_DUO] Actual fill risk {0:F2} exceeds captured budget {1:F2}; protected reduction started.",
                        _book.ActualRisk, _book.Budget));
                }
                if (before == FvgDuoIntentKind.Merge
                    && _book.IntentKind == FvgDuoIntentKind.None)
                {
                    _posStop = _book.InitialStop;
                    _posTarget = _book.InitialTarget;
                    if (!string.IsNullOrEmpty(_pendingMergeSource)) _posSource = _pendingMergeSource;
                    MarkFvgCandidateTraded(_pendingMergeFvgTag);
                    _pendingMergeFvgTag = string.Empty;
                    _pendingMergeSource = string.Empty;
                }

                foreach (FvgDuoSliceCommand command in commands)
                    DispatchCommand(command);

                if (_book.OwnedQuantity == 0 && _book.EntryExecutionsSettled
                    && AccountSignedPosition() == 0)
                {
                    if (string.IsNullOrEmpty(_pendingFinalizeReason))
                        QueueFinalization(string.IsNullOrEmpty(_pendingExitReason)
                            ? "STOP" : _pendingExitReason,
                            _pendingFinalizeTime == DateTime.MinValue ? _asOfNy : _pendingFinalizeTime,
                            _pendingFinalizePrice);
                    if (!HasActiveOwnedOrders()) CompleteFinalization();
                }
                PersistSnapshot();
            }
            finally { _drivingLifecycle = false; }
        }

        private void DispatchCommand(FvgDuoSliceCommand command)
        {
            if (State == State.Realtime && (Account == null
                || Account.ConnectionStatus != ConnectionStatus.Connected)) return;
            if (command.Kind == FvgDuoSliceCommandKind.SweepOwned)
            {
                if (AccountSignedPosition() != 0) return;
                _book.Stage(command);
                PersistOrBlock();
                SweepOwnedOrders();
                return;
            }

            int accountSigned = AccountSignedPosition();
            bool entryCancel = command.Kind == FvgDuoSliceCommandKind.CancelEntry;
            if (!entryCancel && (accountSigned == 0
                || accountSigned != _book.Side * _book.OwnedQuantity))
            {
                ReportDivergence(accountSigned);
                return;
            }
            bool safetyCritical = command.Kind == FvgDuoSliceCommandKind.SubmitStop
                               || command.Kind == FvgDuoSliceCommandKind.EmergencyExit
                               || command.Kind == FvgDuoSliceCommandKind.CancelTarget
                               || command.Kind == FvgDuoSliceCommandKind.CancelEntry;
            if (_executionBlocked && !safetyCritical)
                return;

            if (command.Kind == FvgDuoSliceCommandKind.EmergencyExit
                && HasActiveSliceExit(command.SliceId))
            {
                SetExecutionBlock("Emergency exit suppressed beside live slice exit");
                return;
            }

            _book.Stage(command);
            bool durable = PersistOrBlock();
            if (!durable && !safetyCritical) return;

            try
            {
                switch (command.Kind)
                {
                    case FvgDuoSliceCommandKind.SubmitStop:
                        SubmitSliceOrder(command, OrderType.StopMarket);
                        break;
                    case FvgDuoSliceCommandKind.SubmitTarget:
                        SubmitSliceOrder(command, OrderType.Limit);
                        break;
                    case FvgDuoSliceCommandKind.EmergencyExit:
                        SubmitSliceOrder(command, OrderType.Market);
                        break;
                    case FvgDuoSliceCommandKind.CancelEntry:
                        CancelExactOrder(command.Name, true);
                        break;
                    case FvgDuoSliceCommandKind.CancelTarget:
                        CancelExactOrder(command.Name, false);
                        break;
                    case FvgDuoSliceCommandKind.DriveStop:
                    case FvgDuoSliceCommandKind.WidenStop:
                        ChangeExactStop(command);
                        break;
                }
            }
            catch (Exception ex)
            {
                if (command.Kind != FvgDuoSliceCommandKind.CancelEntry)
                    _book.OnOrderUpdate(command.Name, string.Empty,
                        FvgDuoTransportState.Rejected, command.Price);
                _book.SetBlocked("Transport exception: " + ex.Message);
                SetExecutionBlock("Transport exception for " + command.Name + ": " + ex.Message);
            }
        }

        private void SubmitSliceOrder(FvgDuoSliceCommand command, OrderType type)
        {
            // Account flat/exact-ownership gate is re-read immediately before
            // every exit submission, not inferred from cached bookkeeping.
            int accountSigned = AccountSignedPosition();
            if (accountSigned == 0 || accountSigned != _book.Side * _book.OwnedQuantity) return;
            OrderAction action = _book.Side > 0 ? OrderAction.Sell : OrderAction.BuyToCover;
            string oco = type == OrderType.Market ? string.Empty : _book.OcoName(command.SliceId);
            double limit = type == OrderType.Limit ? command.Price : 0.0;
            double stop = type == OrderType.StopMarket ? command.Price : 0.0;
            Order order;
            if (_recoveredLifecycle)
            {
                order = Account.CreateOrder(Instrument, action, type, OrderEntry.Automated,
                    TimeInForce.Gtc, 1, limit, stop, oco, command.Name, Core.Globals.MaxDate, null);
                TrackOrder(order);
                Account.Submit(new[] { order });
            }
            else
            {
                order = SubmitOrderUnmanaged(BipMinute, action, type, 1,
                    limit, stop, oco, command.Name);
            }
            TrackOrder(order);
            if (order == null)
                _book.OnOrderUpdate(command.Name, string.Empty,
                    FvgDuoTransportState.Rejected, command.Price);
        }

        private void CancelExactOrder(string name, bool entry)
        {
            Order order = entry ? _entryOrder : FindActiveOrder(name);
            if (order == null || !IsOrderActive(order))
            {
                _book.SetBlocked("Exact order missing before cancellation: " + name);
                SetExecutionBlock("Exact order missing before cancellation: " + name);
                return;
            }
            if (_recoveredLifecycle) Account.Cancel(new[] { order });
            else CancelOrder(order);
        }

        private void ChangeExactStop(FvgDuoSliceCommand command)
        {
            if (AccountSignedPosition() == 0) return;
            Order order = FindActiveOrder(command.Name);
            if (order == null || !IsOrderActive(order))
            {
                _book.MarkStopMissing(command.Name, "MISSING_PROTECTION");
                SetExecutionBlock("Exact stop missing before change: " + command.Name);
                return;
            }
            if (_recoveredLifecycle)
            {
                order.QuantityChanged = 1;
                order.LimitPriceChanged = 0.0;
                order.StopPriceChanged = command.Price;
                Account.Change(new[] { order });
            }
            else
                ChangeOrder(order, 1, 0.0, command.Price);
        }

        private void ReconcileProtectionEvidence()
        {
            if (_book == null || _book.OwnedQuantity == 0) return;
            int accountSigned = AccountSignedPosition();
            if (accountSigned != _book.Side * _book.OwnedQuantity) return;
            foreach (FvgDuoSlice slice in _book.Slices.Where(s => s.Remaining > 0))
            {
                string name = _book.StopName(slice.Id);
                Order order = FindActiveOrder(name);
                if (order == null)
                {
                    if (slice.StopState == FvgDuoTransportState.Filled
                        || (slice.StopState == FvgDuoTransportState.Cancelled
                            && slice.TargetState == FvgDuoTransportState.Filled))
                    {
                        if (!_executionBlocked)
                            SetExecutionBlock("Terminal OCO callback awaits exact exit execution: " + name);
                        continue;
                    }
                    if (slice.StopState == FvgDuoTransportState.Working
                        || slice.StopState == FvgDuoTransportState.ChangePending
                        || (slice.StopState == FvgDuoTransportState.Cancelled
                            && slice.TargetState != FvgDuoTransportState.Filled))
                    {
                        _book.MarkStopMissing(name, "MISSING_PROTECTION");
                        Print("[FVG_DUO][ORPHAN] accepted stop missing: " + name);
                    }
                    continue;
                }
                if (slice.StopState == FvgDuoTransportState.ChangePending)
                {
                    if (PriceEqual(order.StopPrice, slice.PendingStop))
                        _book.OnOrderUpdate(name, order.OrderId,
                            FvgDuoTransportState.Working, order.StopPrice);
                    else if (!PriceEqual(order.StopPrice, slice.AcceptedStop))
                    {
                        _book.SetBlocked("Broker stop differs from old and requested prices: " + name);
                        SetExecutionBlock(_book.BlockReason);
                    }
                }
                else if (slice.StopState == FvgDuoTransportState.Working
                    && !PriceEqual(order.StopPrice, slice.AcceptedStop))
                {
                    _book.SetBlocked("Broker stop differs from confirmed price: " + name);
                    SetExecutionBlock(_book.BlockReason);
                }
            }
        }

        private static bool PriceEqual(double left, double right)
        {
            return Math.Abs(left - right) <= 1e-8;
        }

        private int AccountSignedPosition()
        {
            if (State != State.Realtime)
            {
                if (Position.MarketPosition == MarketPosition.Long) return Position.Quantity;
                if (Position.MarketPosition == MarketPosition.Short) return -Position.Quantity;
                return 0;
            }
            if (Account == null || Instrument == null) return 0;
            lock (Account.Positions)
            {
                foreach (Position position in Account.Positions)
                {
                    if (position.Instrument == null
                        || position.Instrument.FullName != Instrument.FullName) continue;
                    if (position.MarketPosition == MarketPosition.Long) return position.Quantity;
                    if (position.MarketPosition == MarketPosition.Short) return -position.Quantity;
                    return 0;
                }
            }
            return 0;
        }

        private void CheckDivergence()
        {
            ReportDivergence(AccountSignedPosition());
        }

        private void ReportDivergence(int accountSigned)
        {
            int ownedSigned = _book == null ? 0 : _book.Side * _book.OwnedQuantity;
            if (accountSigned == ownedSigned)
            {
                _lastDivergence = string.Empty;
                return;
            }
            string key = accountSigned.ToString(CultureInfo.InvariantCulture) + "/"
                       + ownedSigned.ToString(CultureInfo.InvariantCulture);
            if (key == _lastDivergence) return;
            _lastDivergence = key;
            Print(string.Format(CultureInfo.InvariantCulture,
                "[FVG_DUO][ORPHAN] account={0} owned={1} owner={2}; transport blocked, foreign/net exposure untouched.",
                accountSigned, ownedSigned, _ownerPrefix));
        }

        private bool IsOwnedName(string name)
        {
            return !string.IsNullOrEmpty(name)
                && name.StartsWith(_ownerPrefix + "_", StringComparison.Ordinal);
        }

        private bool IsOwnedOrder(Order order)
        {
            if (order == null || order.Instrument == null || Instrument == null
                || order.Instrument.FullName != Instrument.FullName) return false;
            return IsOwnedName(order.Name) || IsOwnedName(order.Oco)
                || IsOwnedName(order.FromEntrySignal);
        }

        private bool IsStopName(string name)
        {
            return IsOwnedName(name) && name.IndexOf("_S_", StringComparison.Ordinal) >= 0;
        }

        private void TrackOrder(Order order)
        {
            if (order == null || !IsOwnedOrder(order)) return;
            _ownedOrders[order.Name] = order;
            if (_book != null && order.Name == _book.EntryName) _entryOrder = order;
        }

        private Order FindActiveOrder(string name)
        {
            Order order;
            if (_ownedOrders.TryGetValue(name, out order) && IsOrderActive(order)) return order;
            foreach (Order candidate in AccountOrdersSnapshot())
            {
                if (!IsOwnedOrder(candidate) || candidate.Name != name || !IsOrderActive(candidate)) continue;
                TrackOrder(candidate);
                return candidate;
            }
            return null;
        }

        private List<Order> AccountOrdersSnapshot()
        {
            var result = new List<Order>();
            if (Account == null) return result;
            lock (Account.Orders) result.AddRange(Account.Orders);
            return result;
        }

        private bool HasActiveOwnedOrders()
        {
            return AccountOrdersSnapshot().Any(o => IsOwnedOrder(o) && IsOrderActive(o));
        }

        private bool HasForeignActiveOrdersForInstrument()
        {
            if (State != State.Realtime || Instrument == null) return false;
            return AccountOrdersSnapshot().Any(o => o != null && o.Instrument != null
                && o.Instrument.FullName == Instrument.FullName && IsOrderActive(o)
                && !IsOwnedOrder(o));
        }

        private bool HasActiveSliceExit(long sliceId)
        {
            return FindActiveOrder(_book.StopName(sliceId)) != null
                || FindActiveOrder(_book.TargetName(sliceId)) != null
                || FindActiveOrder(_book.EmergencyName(sliceId)) != null;
        }

        private static bool IsOrderActive(Order order)
        {
            if (order == null) return false;
            return order.OrderState != OrderState.Cancelled
                && order.OrderState != OrderState.Filled
                && order.OrderState != OrderState.Rejected;
        }

        private static bool IsCancelable(Order order)
        {
            if (!IsOrderActive(order)) return false;
            return order.OrderState != OrderState.CancelPending
                && order.OrderState != OrderState.CancelSubmitted;
        }

        private void SweepOwnedOrders()
        {
            if (AccountSignedPosition() != 0) return;
            foreach (Order order in AccountOrdersSnapshot())
            {
                if (!IsOwnedOrder(order) || !IsCancelable(order)) continue;
                try
                {
                    if (_recoveredLifecycle) Account.Cancel(new[] { order });
                    else CancelOrder(order);
                }
                catch (Exception ex)
                {
                    SetExecutionBlock("Owned-generation sweep failed: " + ex.Message);
                }
            }
        }

        private static FvgDuoTransportState MapOrderState(OrderState state)
        {
            switch (state)
            {
                case OrderState.Filled: return FvgDuoTransportState.Filled;
                case OrderState.Cancelled: return FvgDuoTransportState.Cancelled;
                case OrderState.Rejected: return FvgDuoTransportState.Rejected;
                case OrderState.CancelPending:
                case OrderState.CancelSubmitted:
                    return FvgDuoTransportState.CancelPending;
                case OrderState.ChangePending:
                case OrderState.ChangeSubmitted:
                    return FvgDuoTransportState.ChangePending;
                case OrderState.Accepted:
                case OrderState.AcceptedByRisk:
                case OrderState.Working:
                case OrderState.TriggerPending:
                case OrderState.PartFilled:
                    return FvgDuoTransportState.Working;
                default:
                    return FvgDuoTransportState.SubmitPending;
            }
        }

        private string ExitReasonFor(string orderName, FvgDuoIntentKind intent)
        {
            if (orderName.IndexOf("_T_", StringComparison.Ordinal) >= 0) return "TARGET";
            if (orderName.IndexOf("_X_", StringComparison.Ordinal) >= 0) return "PROTECTION_FAIL";
            if (intent == FvgDuoIntentKind.Close)
                return string.IsNullOrEmpty(_pendingExitReason) ? "CLOSE" : _pendingExitReason;
            if (intent == FvgDuoIntentKind.RiskReduction) return "FILL_RISK";
            if (intent == FvgDuoIntentKind.Merge) return "MERGE_TRIM";
            return "STOP";
        }

        private void QueueFinalization(string reason, DateTime time, double price)
        {
            _pendingFinalizeReason = reason ?? "EXIT";
            _pendingFinalizeTime = time;
            _pendingFinalizePrice = price;
        }

        private void CompleteFinalization()
        {
            if (_book == null || _book.OwnedQuantity != 0 || !_book.EntryExecutionsSettled
                || AccountSignedPosition() != 0
                || HasActiveOwnedOrders()) return;
            string reason = string.IsNullOrEmpty(_pendingFinalizeReason)
                ? "EXIT" : _pendingFinalizeReason;
            DateTime time = _pendingFinalizeTime == DateTime.MinValue ? _asOfNy : _pendingFinalizeTime;
            if (_core != null && reason != "TIME" && reason != "FLIP")
                _core.ReportExit(_posSource, reason, time);
            if (_posEntryFill > 0.0) JournalRow(time, _pendingFinalizePrice, reason);
            FinishTradeGeometry(time, _pendingFinalizePrice, reason);

            bool recoveredLifecycleCompleted = _recoveredLifecycle;
            if (recoveredLifecycleCompleted) UnsubscribeRecoveredAccountEvents();
            _book = null;
            _entryOrder = null;
            _ownedOrders.Clear();
            _recoveredLifecycle = false;
            _pendingMergeSource = string.Empty;
            _pendingEntryFvgTag = string.Empty;
            _pendingMergeFvgTag = string.Empty;
            _pendingExitReason = string.Empty;
            _pendingFinalizeReason = string.Empty;
            _pendingFinalizeTime = DateTime.MinValue;
            _pendingFinalizePrice = 0.0;
            DeleteCleanSnapshot();
            if (recoveredLifecycleCompleted)
                SetExecutionBlock("Recovered lifecycle completed; restart required before fresh entries");
        }

        private void SetExecutionBlock(string reason)
        {
            _executionBlocked = true;
            _executionBlockReason = reason ?? "Execution blocked";
            Print("[FVG_DUO][BLOCKED] " + _executionBlockReason);
        }

        private static string Invariant(double value)
        {
            return value.ToString("R", CultureInfo.InvariantCulture);
        }

        private static string Attribute(XElement element, string name)
        {
            XAttribute attribute = element.Attribute(name);
            return attribute == null ? string.Empty : attribute.Value;
        }

        private static int ParseIntAttribute(XElement element, string name)
        {
            return int.Parse(Attribute(element, name), NumberStyles.Integer, CultureInfo.InvariantCulture);
        }

        private static long ParseLongAttribute(XElement element, string name)
        {
            string value = Attribute(element, name);
            return string.IsNullOrEmpty(value) ? 0L
                : long.Parse(value, NumberStyles.Integer, CultureInfo.InvariantCulture);
        }

        private static double ParseDoubleAttribute(XElement element, string name)
        {
            string value = Attribute(element, name);
            return string.IsNullOrEmpty(value) ? 0.0
                : double.Parse(value, NumberStyles.Float, CultureInfo.InvariantCulture);
        }

        // ═══════════════════════════════════════════════════════════════════
        //  Trade journal — same columns as the MT5 parity export so both
        //  platforms can be diffed with tests/parity/diff_fast.py
        // ═══════════════════════════════════════════════════════════════════
        private void OpenJournal()
        {
            try
            {
                string dir = Path.Combine(Core.Globals.UserDataDir, "FVG Duo");
                Directory.CreateDirectory(dir);
                string path = Path.Combine(dir, "trades_nt8.csv");
                _journal = new StreamWriter(path, false, new UTF8Encoding(false));
                _journal.WriteLine("trade_id,pos_id,source,side,entry_server,entry_ny,entry_model,entry_fill,"
                                 + "exit_server,exit_ny,exit_price,exit_reason,stop,target");
                _journal.Flush();
                Print("[FVG_DUO] journal: " + path);
            }
            catch (Exception ex)
            {
                Print("[FVG_DUO] journal open failed: " + ex.Message);
                _journal = null;
            }
        }

        private void JournalRow(DateTime exitNy, double exitPrice, string reason)
        {
            if (_journal == null) return;

            _journalRows++;
            string stamp = "yyyy.MM.dd HH:mm:ss";
            _journal.WriteLine(string.Join(",",
                _journalRows.ToString(CultureInfo.InvariantCulture),
                _journalRows.ToString(CultureInfo.InvariantCulture),
                _posSource,
                _posSide > 0 ? "LONG" : "SHORT",
                exitNy.ToString(stamp, CultureInfo.InvariantCulture),
                _posEntryNy.ToString(stamp, CultureInfo.InvariantCulture),
                _posEntryModel.ToString("0.00", CultureInfo.InvariantCulture),
                _posEntryFill.ToString("0.00", CultureInfo.InvariantCulture),
                exitNy.ToString(stamp, CultureInfo.InvariantCulture),
                exitNy.ToString(stamp, CultureInfo.InvariantCulture),
                exitPrice.ToString("0.00", CultureInfo.InvariantCulture),
                reason,
                _posStop.ToString("0.00", CultureInfo.InvariantCulture),
                _posTarget.ToString("0.00", CultureInfo.InvariantCulture)));
            _journal.Flush();
        }
    }
}
#endif
