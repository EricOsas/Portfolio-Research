// Passive visual recovery only. Never calls signal evaluation or order APIs.
#ifndef FVG_VISUAL_RECOVERY
#define FVG_VISUAL_RECOVERY

struct FvgVisualRecord
{
   string name, tip;
   int kind, clr, style;
   datetime t0, t1;
   double p0, p1;
   bool fill, back;
};
FvgVisualRecord g_fvgVisualRecords[];
bool g_fvgVisualRepair = true, g_fvgVisualLoaded = false;
datetime g_fvgVisualBar = 0;
datetime g_visualHistoryDay = 0, g_visualHistoryCutoff = 0;

// Latest two prior NY dates WITH observed cash-session bars, not weekend dates.
datetime VisualSessionCutoff(const MqlRates &bars[], datetime currentNy)
{
   datetime today = currentNy - currentNy % 86400;
   datetime cutoff = today, lastDay = 0;
   int completed = 0;
   for(int i = ArraySize(bars) - 1; i >= 0; i--)
   {
      datetime ny = NYTime(bars[i].time);
      if(ny <= 0) continue;
      datetime day = ny - ny % 86400;
      int minute = (int)((ny - day) / 60);
      if(day >= today || day == lastDay || minute < 570 || minute >= SessionEndMinute(day)) continue;
      cutoff = day;
      lastDay = day;
      if(++completed == 2) break;
   }
   return cutoff;
}

void RebuildSessionRanges(const MqlRates &bars[], datetime currentNy)
{
   g_visualHistoryDay = currentNy - currentNy % 86400;
   g_visualHistoryCutoff = VisualSessionCutoff(bars, currentNy);
   g_visualCutoffNy = g_visualHistoryCutoff;
   datetime day = 0, firstServer = 0, firstNy = 0;
   double high = 0.0, low = 0.0;
   for(int i = 0; i <= ArraySize(bars); i++)
   {
      datetime ny = 0, nextDay = 0;
      bool valid = false;
      if(i < ArraySize(bars))
      {
         ny = NYTime(bars[i].time);
         nextDay = ny - ny % 86400;
         int minute = (int)((ny - nextDay) / 60);
         valid = ny > 0 && ny < currentNy && nextDay >= g_visualCutoffNy &&
                 minute >= 570 && minute < SessionEndMinute(nextDay);
      }
      if(day > 0 && (i == ArraySize(bars) || (valid && nextDay != day)))
      {
         UpdateObservedSessionVisual(firstServer, firstNy, SessionEndMinute(day), high, low);
         MqlDateTime d;
         TimeToStruct(day, d);
         string name = "FVG_SESSION_" + StringFormat("%04d%02d%02d", d.year, d.mon, d.day);
         datetime offset = firstServer - firstNy;
         // Authoritative rebuild also repairs stale/misanchored extrema.
         ObjectMove(0, name, 0, day + 570 * 60 + offset, low);
         ObjectMove(0, name, 1, day + SessionEndMinute(day) * 60 + offset, high);
         ObjectSetString(0, name, OBJPROP_TOOLTIP,
            StringFormat("FVG Duo | NY cash-session range\nNY %s | 09:30 -> %02d:%02d\nHigh %.2f | Low %.2f | Range %.2f points\nRebuilt from completed M1 history; not a stop/target",
               TimeToString(day, TIME_DATE), SessionEndMinute(day)/60, SessionEndMinute(day)%60, high, low, high-low));
         day = 0;
      }
      if(!valid) continue;
      if(day == 0)
      {
         day = nextDay; firstServer = bars[i].time; firstNy = ny;
         high = bars[i].high; low = bars[i].low;
      }
      else
      {
         high = MathMax(high, bars[i].high);
         low = MathMin(low, bars[i].low);
      }
   }
}

// Same completed-M15 EMA recurrence, separate local state: no PushM15/engine mutation.
void RebuildVisualAverages(const MqlRates &bars[], datetime completedAt)
{
   double fast = 0.0, slow = 0.0;
   double aF = 2.0 / (B3A_TREND_EMA_FAST + 1.0);
   double aS = 2.0 / (B3A_TREND_EMA_SLOW + 1.0);
   datetime previous = 0;
   for(int i = 0; i < ArraySize(bars); i++)
   {
      if(bars[i].time + 900 > completedAt) break;
      double oldFast = fast, oldSlow = slow;
      if(previous == 0) { fast = bars[i].close; slow = bars[i].close; }
      else
      {
         fast = bars[i].close * aF + fast * (1.0 - aF);
         slow = bars[i].close * aS + slow * (1.0 - aS);
      }
      datetime start = previous + 900;
      if(previous > 0 && bars[i].time - previous == 900 && NYTime(start) >= g_visualCutoffNy)
         ShowTrendAverages(start, bars[i].time + 900, oldFast, fast, oldSlow, slow);
      previous = bars[i].time;
   }
}

void RestoreVisualRecords()
{
   for(int i = 0; i < ArraySize(g_fvgVisualRecords); i++)
   {
      FvgVisualRecord r = g_fvgVisualRecords[i];
      if(NYTime(r.t0) < g_visualCutoffNy) continue;
      bool currentCandidate = StringFind(r.tip, "Current") >= 0 && StringFind(r.name, "FVG_BOX_") == 0;
      if(currentCandidate && NYTime(r.t0) < g_visualHistoryDay) continue;
      if(currentCandidate) g_fvgCandidateName = r.name;
      if(ObjectFind(0, r.name) >= 0) continue;
      ObjectCreate(0, r.name, (ENUM_OBJECT)r.kind, 0, r.t0, r.p0, r.t1, r.p1);
      ObjectSetInteger(0, r.name, OBJPROP_COLOR, r.clr);
      ObjectSetInteger(0, r.name, OBJPROP_STYLE, r.style);
      ObjectSetInteger(0, r.name, OBJPROP_FILL, r.fill);
      ObjectSetInteger(0, r.name, OBJPROP_BACK, r.back);
      ObjectSetInteger(0, r.name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, r.name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, r.name, OBJPROP_RAY_LEFT, false);
      ObjectSetInteger(0, r.name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, r.name, OBJPROP_HIDDEN, true);
      ObjectSetString(0, r.name, OBJPROP_TOOLTIP, r.tip);
   }
}

void ForgetVisualRecord(string name)
{
   for(int i = ArraySize(g_fvgVisualRecords) - 1; i >= 0; i--)
      if(g_fvgVisualRecords[i].name == name)
      {
         for(int j = i; j + 1 < ArraySize(g_fvgVisualRecords); j++)
            g_fvgVisualRecords[j] = g_fvgVisualRecords[j + 1];
         ArrayResize(g_fvgVisualRecords, ArraySize(g_fvgVisualRecords) - 1);
      }
}

string VisualRecordFile()
{
   string symbol = _Symbol;
   StringReplace(symbol, "/", "_"); StringReplace(symbol, "\\", "_");
   return StringFormat("FVG_Duo/visuals_%I64d_%I64u_%s.csv", AccountInfoInteger(ACCOUNT_LOGIN), InpMagic, symbol);
}

void LoadVisualRecords()
{
   if(g_fvgVisualLoaded) return;
   g_fvgVisualLoaded = true;
   if(MQLInfoInteger(MQL_TESTER)) return; // Never contaminate demo snapshots with tester output.
   int h = FileOpen(VisualRecordFile(), FILE_COMMON | FILE_READ | FILE_CSV | FILE_ANSI, '\t');
   if(h == INVALID_HANDLE) return;
   if(FileReadString(h) != "FVG_VISUAL_V1") { FileClose(h); return; }
   while(!FileIsEnding(h) && ArraySize(g_fvgVisualRecords) < 4096)
   {
      FvgVisualRecord r;
      r.name = FileReadString(h);
      r.kind = (int)StringToInteger(FileReadString(h));
      r.t0 = (datetime)StringToInteger(FileReadString(h));
      r.p0 = StringToDouble(FileReadString(h));
      r.t1 = (datetime)StringToInteger(FileReadString(h));
      r.p1 = StringToDouble(FileReadString(h));
      r.clr = (int)StringToInteger(FileReadString(h));
      r.style = (int)StringToInteger(FileReadString(h));
      r.fill = StringToInteger(FileReadString(h)) != 0;
      r.back = StringToInteger(FileReadString(h)) != 0;
      r.tip = FileReadString(h); StringReplace(r.tip, "\\n", "\n");
      if((StringFind(r.name, "FVG_BOX_") != 0 && StringFind(r.name, "FVG_TRADE_") != 0) ||
         (r.kind != OBJ_RECTANGLE && r.kind != OBJ_TREND) || r.t0 <= 0 || r.t1 < r.t0 ||
         !MathIsValidNumber(r.p0) || !MathIsValidNumber(r.p1) || r.p0 <= 0 || r.p1 <= 0) continue;
      int n = ArraySize(g_fvgVisualRecords);
      ArrayResize(g_fvgVisualRecords, n + 1); g_fvgVisualRecords[n] = r;
   }
   FileClose(h);
}

void CaptureVisualRecords()
{
   ArrayResize(g_fvgVisualRecords, 0);
   for(int i = 0; i < ObjectsTotal(0, -1, -1); i++)
   {
      string name = ObjectName(0, i, -1, -1);
      if(StringFind(name, "FVG_BOX_") != 0 && StringFind(name, "FVG_TRADE_") != 0) continue;
      FvgVisualRecord r;
      r.name = name; r.kind = (int)ObjectGetInteger(0, name, OBJPROP_TYPE);
      r.t0 = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 0);
      r.t1 = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 1);
      r.p0 = ObjectGetDouble(0, name, OBJPROP_PRICE, 0); r.p1 = ObjectGetDouble(0, name, OBJPROP_PRICE, 1);
      r.clr = (int)ObjectGetInteger(0, name, OBJPROP_COLOR); r.style = (int)ObjectGetInteger(0, name, OBJPROP_STYLE);
      r.fill = ObjectGetInteger(0, name, OBJPROP_FILL) != 0; r.back = ObjectGetInteger(0, name, OBJPROP_BACK) != 0;
      r.tip = ObjectGetString(0, name, OBJPROP_TOOLTIP);
      if(NYTime(r.t0) < g_visualCutoffNy) continue;
      int n = ArraySize(g_fvgVisualRecords); ArrayResize(g_fvgVisualRecords, n + 1); g_fvgVisualRecords[n] = r;
   }
   if(MQLInfoInteger(MQL_TESTER)) return;
   string path = VisualRecordFile(), tmp = path + ".tmp";
   int h = FileOpen(tmp, FILE_COMMON | FILE_WRITE | FILE_CSV | FILE_ANSI, '\t');
   if(h == INVALID_HANDLE) return;
   FileWrite(h, "FVG_VISUAL_V1");
   for(int i = 0; i < ArraySize(g_fvgVisualRecords); i++)
   {
      FvgVisualRecord r = g_fvgVisualRecords[i];
      string tip = r.tip; StringReplace(tip, "\n", "\\n");
      FileWrite(h, r.name, r.kind, (long)r.t0, DoubleToString(r.p0, _Digits),
                 (long)r.t1, DoubleToString(r.p1, _Digits), r.clr, r.style, (int)r.fill, (int)r.back, tip);
   }
   FileFlush(h); FileClose(h);
   FileMove(tmp, FILE_COMMON, path, FILE_COMMON | FILE_REWRITE);
}

// Legacy installations have no visual snapshot. Reconstruct ONLY owned booked
// trades from native history; initial order bracket is explicitly labeled as
// such, never claimed to be the unavailable final modified stop/target.
void RecoverBookedVisualHistory(datetime fromServer, datetime throughServer)
{
   if(!HistorySelect(fromServer, throughServer)) return;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol ||
         HistoryDealGetInteger(ticket, DEAL_MAGIC) != (long)InpMagic ||
         HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
      ulong id = (ulong)HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
      datetime start = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      if(NYTime(start) < g_visualCutoffNy) continue;
      string prefix = "FVG_TRADE_" + IntegerToString((long)id) + "_";
      if(ObjectFind(0, prefix + "ENTRY") >= 0) continue; // Accepted snapshot takes precedence.
      int side = HistoryDealGetInteger(ticket, DEAL_TYPE) == DEAL_TYPE_BUY ? 1 : -1;
      double entrySum = 0.0, entryQty = 0.0, exitSum = 0.0, exitQty = 0.0;
      datetime end = 0;
      bool foreign = false;
      for(int j = i; j < total; j++)
      {
         ulong d = HistoryDealGetTicket(j);
         if((ulong)HistoryDealGetInteger(d, DEAL_POSITION_ID) != id) continue;
         if(HistoryDealGetInteger(d, DEAL_MAGIC) != (long)InpMagic ||
            HistoryDealGetString(d, DEAL_SYMBOL) != _Symbol) { foreign = true; break; }
         double qty = HistoryDealGetDouble(d, DEAL_VOLUME);
         long direction = HistoryDealGetInteger(d, DEAL_ENTRY);
         if(direction == DEAL_ENTRY_IN)
         {
            entrySum += qty * HistoryDealGetDouble(d, DEAL_PRICE); entryQty += qty;
         }
         else if(direction == DEAL_ENTRY_OUT)
         {
            exitSum += qty * HistoryDealGetDouble(d, DEAL_PRICE); exitQty += qty;
            end = (datetime)HistoryDealGetInteger(d, DEAL_TIME);
         }
         else { foreign = true; break; } // Netting reversal/foreign allocation is not guessed.
      }
      if(foreign || entryQty <= 0.0 || exitQty + 1e-8 < entryQty || end <= 0) continue;
      ulong order = (ulong)HistoryDealGetInteger(ticket, DEAL_ORDER);
      double stop = HistoryOrderGetDouble(order, ORDER_SL), target = HistoryOrderGetDouble(order, ORDER_TP);
      if(stop <= 0.0) continue; // Missing protection evidence: no invented historical rectangle.
      string comment = HistoryDealGetString(ticket, DEAL_COMMENT);
      string source = StringFind(comment, "TREND") >= 0 ? "TREND" : "OD";
      ulong savedId = g_visualTradePositionId;
      string savedPrefix = g_visualTradePrefix, savedSource = g_visualTradeSource, savedCandidate = g_fvgCandidateName;
      int savedSide = g_visualTradeSide;
      datetime savedStart = g_visualTradeStart, savedEnd = g_visualTradeEnd;
      double savedEntry = g_visualTradeEntry, savedStop = g_visualTradeStop, savedTarget = g_visualTradeTarget;
      ShowTradeGeometry(side, start, end, entrySum / entryQty, stop, target, id, source);
      string evidence = StringFormat("\nRecovered booked fills | Exit %.2f\nInitial entry-order bracket only; later SL/TP modifications unavailable", exitSum / exitQty);
      ObjectSetString(0, prefix+"ENTRY", OBJPROP_TOOLTIP, ObjectGetString(0, prefix+"ENTRY", OBJPROP_TOOLTIP)+evidence);
      ObjectSetString(0, prefix+"STOP", OBJPROP_TOOLTIP, ObjectGetString(0, prefix+"STOP", OBJPROP_TOOLTIP)+evidence);
      if(target > 0) ObjectSetString(0, prefix+"TARGET", OBJPROP_TOOLTIP, ObjectGetString(0, prefix+"TARGET", OBJPROP_TOOLTIP)+evidence);
      MqlRates context[];
      ArraySetAsSeries(context, false);
      int periodSeconds = source == "TREND" ? 900 : 600;
      ENUM_TIMEFRAMES period = source == "TREND" ? PERIOD_M15 : PERIOD_M10;
      datetime signalBar = start - start % 60;
      if(CopyRates(_Symbol, period, signalBar - 3 * periodSeconds, signalBar - 1, context) == 3)
      {
         if(side > 0 && context[2].low > context[0].high)
            ShowFvgCandidate(source, context[0].time, context[0].high, context[2].time+periodSeconds, context[2].low, true);
         else if(side < 0 && context[2].high < context[0].low)
            ShowFvgCandidate(source, context[0].time, context[0].low, context[2].time+periodSeconds, context[2].high, false);
         if(g_fvgCandidateName != savedCandidate) MarkFvgCandidateTraded();
      }
      g_visualTradePositionId = savedId; g_visualTradePrefix = savedPrefix; g_visualTradeSource = savedSource;
      g_visualTradeSide = savedSide; g_visualTradeStart = savedStart; g_visualTradeEnd = savedEnd;
      g_visualTradeEntry = savedEntry; g_visualTradeStop = savedStop; g_visualTradeTarget = savedTarget;
      g_fvgCandidateName = savedCandidate;
   }
}

void MaintainFvgVisuals(datetime serverNow)
{
   if(!VisualsAllowed()) return;
   datetime bar = iTime(_Symbol, PERIOD_M1, 0);
   if(bar <= 0) return;
   if(!g_fvgVisualRepair && bar == g_fvgVisualBar) return;
   datetime ny = NYTime(bar);
   if(ny <= 0) return; // Never guess historical clock or clear valid visuals on missing history.
   if(!g_fvgVisualRepair && ny - ny % 86400 == g_visualHistoryDay)
   {
      // Normal M1 engine path already emitted current EMA/range/trade changes.
      // Persist only; full 400-day history replay is for attach/repair/date roll.
      CaptureVisualRecords(); g_fvgVisualBar = bar;
      return;
   }
   MqlRates m1[], m15[];
   ArraySetAsSeries(m1, false); ArraySetAsSeries(m15, false);
   // Bounded retries: a fresh attach frequently holds fewer than 21 days of M1,
   // and one failed pull used to drop the session range and the averages together.
   int spans[] = {21, 7, 3};
   int got = 0;
   for(int s = 0; s < ArraySize(spans) && got <= 0; s++)
      got = CopyRates(_Symbol, PERIOD_M1, bar - spans[s] * 86400, bar - 1, m1);
   if(got <= 0)
   {
      // Last resort: the chart's own series still carries observed cash-session bars,
      // so the range reflects real prints instead of disappearing for the day.
      got = CopyRates(_Symbol, (ENUM_TIMEFRAMES)_Period, bar - 3 * 86400, bar - 1, m1);
      if(got > 0)
         PrintFormat("FVG Duo: M1 history unavailable, session ranges rebuilt from %s bars (%d)",
                     EnumToString((ENUM_TIMEFRAMES)_Period), got);
   }
   if(got <= 0) return;
   LoadVisualRecords();
   RebuildSessionRanges(m1, ny);
   if(CopyRates(_Symbol, PERIOD_M15, bar - 400 * 86400, bar - 1, m15) > 0)
      RebuildVisualAverages(m15, bar);
   else return; // Retry asynchronous history acquisition on next timer/tick.
   RestoreVisualRecords();
   RecoverBookedVisualHistory(bar - (ny - g_visualCutoffNy), bar);
   PruneFvgVisuals(ny);
   CaptureVisualRecords();
   g_fvgVisualBar = bar; g_fvgVisualRepair = false;
   fvgPanelRestack = DashboardAllowed();
}

#endif
