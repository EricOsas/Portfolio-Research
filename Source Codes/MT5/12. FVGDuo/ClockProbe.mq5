#property strict
// Native MQL pure clock/session boundary fixture. NO orders/account APIs.
const int CLOCK_UNKNOWN=100000;
datetime g_clockWeekKey=0;
int g_clockWeekOff=CLOCK_UNKNOWN;
string g_sessionKeys[];
int g_sessionMins[];
MqlRates probeH1[],probeM1[];
int checks=0,failures=0;
const string SESSION_END_TABLE =
                 "20180115=779;20180219=779;20180528=779;20180703=794;20180704=779;20180903=779;"
                 "20181122=779;20181123=794;20181205=570;20181224=794;20181231=840;20190121=779;"
                 "20190218=779;20190527=779;20190703=794;20190704=779;20190902=779;20191128=779;"
                 "20191129=794;20191224=794;"
                 "20191231=839;20200120=779;20200217=779;20200525=779;20200703=779;20200907=779;"
                 "20201126=779;20201127=794;20201224=794;20201231=839;20210118=779;20210215=779;"
                 "20210402=554;20210531=779;20210705=779;20210906=779;20211125=779;20211126=794;"
                 "20211231=839;20220117=779;20220221=779;20220530=779;20220620=779;20220704=779;"
                 "20220905=779;20221124=779;20221125=794;20230116=779;20230220=779;20230529=779;"
                 "20230619=779;20230703=794;20230704=779;20230904=779;20231123=779;20231124=794;"
                 "20240115=779;20240219=779;20240527=779;20240619=779;20240703=795;20240704=779;"
                 "20240902=779;20241128=780;20241129=794;20241224=794;20250109=570;20250120=779;"
                 "20250217=779;20250526=779;20250619=779;20250703=794;20250704=779;20250901=779;"
                 "20251127=779;20251128=794;20251224=794;20260119=779;20260216=779;20260403=554;"
                 "20260525=779;20260619=779;20260703=779;20260907=779;";
long ProbeInfo(ENUM_MQL_INFO_INTEGER property) { return property == MQL_TESTER ? 1 : 0; }
int ProbeRates(string symbol, ENUM_TIMEFRAMES period, datetime start, datetime end, MqlRates &rates[])
{
   ArrayResize(rates,0);
   int count=period==PERIOD_H1?ArraySize(probeH1):ArraySize(probeM1);
   for(int i=0;i<count;i++)
   {
      MqlRates bar;
      if(period==PERIOD_H1) bar=probeH1[i]; else bar=probeM1[i];
      if(bar.time<start || bar.time>end) continue;
      int n=ArraySize(rates);ArrayResize(rates,n+1);rates[n]=bar;
   }
   return ArraySize(rates);
}
void Series(string stamps, bool hourly)
{
   string parts[];int n=StringSplit(stamps,';',parts);
   if(hourly) ArrayResize(probeH1,n); else ArrayResize(probeM1,n);
   for(int i=0;i<n;i++)
   {
      if(hourly) probeH1[i].time=StringToTime(parts[i]); else probeM1[i].time=StringToTime(parts[i]);
   }
}
void Check(bool passed, string name, int handle)
{
   checks++;if(!passed) failures++;
   PrintFormat("[NATIVE_CLOCK_PROBE] %s %s", passed?"PASS":"FAIL",name);
   FileWrite(handle,name,passed?"PASS":"FAIL");
}
int OffsetFromReopen(datetime reopen)
{
   int raw    = (int)((long)reopen % 86400) - 18 * 3600;
   int offset = (int)MathRound((double)raw / 3600.0) * 3600;
   while(offset >  14 * 3600) offset -= 86400;
   while(offset < -12 * 3600) offset += 86400;
   return offset;
}

bool IsWeeklyReopen(datetime reopen, int offset)
{
   MqlDateTime ny;
   TimeToStruct(reopen - offset, ny);
   return ny.day_of_week == 0 && ny.hour == 18 && ny.min == 0 && ny.sec == 0;
}

int VBWeekAnchorOffset(datetime stamp)
{
   MqlRates h1[];
   ArraySetAsSeries(h1, false);
   int n = ProbeRates(_Symbol, PERIOD_H1, stamp - 30 * 86400, stamp, h1);
   if(n < 2) return CLOCK_UNKNOWN;

   for(int i = n - 1; i >= 1; i--)
   {
      if(h1[i].time - h1[i - 1].time < 36 * 3600) continue;   // not the weekend gap
      MqlRates m1[];
      ArraySetAsSeries(m1, false);
      if(ProbeRates(_Symbol, PERIOD_M1, h1[i].time, h1[i].time + 2 * 3600, m1) < 1) continue;
      int offset = OffsetFromReopen(m1[0].time);
      if(IsWeeklyReopen(m1[0].time, offset)) return offset;
   }
   return CLOCK_UNKNOWN;
}

int VBExpectedBrokerUTC(datetime utc)
{
   MqlDateTime dt;
   TimeToStruct(utc, dt);
   // Approximate US DST: 2nd Sunday March to 1st Sunday Nov
   if(dt.mon > 3 && dt.mon < 11) return 3; // Summer
   if(dt.mon == 3 && dt.day >= 8) return 3;
   if(dt.mon == 11 && dt.day < 7) return 3;
   return 2; // Winter
}

int VBServerNYOffsetSec(datetime stamp)
{
   if(ProbeInfo(MQL_TESTER))
   {
      MqlDateTime d;
      TimeToStruct(stamp, d);
      d.hour = 0; d.min = 0; d.sec = 0;
      datetime week = StructToTime(d) - d.day_of_week * 86400;
      if(week == g_clockWeekKey && g_clockWeekOff != CLOCK_UNKNOWN)
         return g_clockWeekOff;

      int off = VBWeekAnchorOffset(stamp);
      if(off != CLOCK_UNKNOWN)
      {
         g_clockWeekKey = week;
         g_clockWeekOff = off;
      }
      return off;
   }

   datetime utc = TimeGMT(), server = TimeTradeServer();
   if(server <= 0 || utc <= 0) return CLOCK_UNKNOWN;
   int raw = (int)(server - utc), offset = (int)MathRound((double)raw / 900.0) * 900;
   if(MathAbs(raw - offset) > 120 || offset < -12 * 3600 || offset > 14 * 3600) return CLOCK_UNKNOWN;
   if(MathAbs((double)(stamp - server)) > 7 * 86400)
      return VBWeekAnchorOffset(stamp);
   return offset - (VBExpectedBrokerUTC(stamp - offset) - 7) * 3600;
}

datetime NYTime(datetime serverTime)
{
   int offset = VBServerNYOffsetSec(serverTime);
   if(offset == CLOCK_UNKNOWN) return 0;
   return serverTime - offset;
}

void LoadSessionTable()
{
   string items[];
   int n = StringSplit(SESSION_END_TABLE, ';', items);
   ArrayResize(g_sessionKeys, 0);
   ArrayResize(g_sessionMins, 0);
   for(int i = 0; i < n; i++)
   {
      string item = items[i];
      if(StringLen(item) < 9) continue;
      int eq = StringFind(item, "=");
      if(eq != 8) continue;
      int k = ArraySize(g_sessionKeys);
      ArrayResize(g_sessionKeys, k + 1);
      ArrayResize(g_sessionMins, k + 1);
      g_sessionKeys[k] = StringSubstr(item, 0, 8);
      g_sessionMins[k] = (int)StringToInteger(StringSubstr(item, 9));
   }
}

int SessionEndMinute(datetime nyDay)
{
   MqlDateTime d;
   TimeToStruct(nyDay, d);
   string key = StringFormat("%04d%02d%02d", d.year, d.mon, d.day);
   for(int i = 0; i < ArraySize(g_sessionKeys); i++)
      if(g_sessionKeys[i] == key)
         return g_sessionMins[i];
   return 960;
}
void OnStart()
{
   int h=FileOpen("native_clock_probe.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(h==INVALID_HANDLE){Print("NATIVE_CLOCK_PROBE file open failed");TerminalClose(1);return;}
   FileWrite(h,"fixture","result");
   Series("2019.12.27 22:00;2019.12.30 01:00;2019.12.31 20:00;2020.01.02 08:00",true);
   Series("2019.12.30 01:00;2020.01.02 08:00",false);
   Check(NYTime(StringToTime("2020.01.02 16:50"))==StringToTime("2020.01.02 09:50"),"Jan2 NewYear gap",h);
   Check(NYTime(StringToTime("2020.01.03 16:50"))==StringToTime("2020.01.03 09:50"),"Jan3 cached clock",h);
   g_clockWeekKey=0;g_clockWeekOff=CLOCK_UNKNOWN;
   Check(NYTime(StringToTime("2020.01.03 16:50"))==StringToTime("2020.01.03 09:50"),"Jan3 restart",h);
   Series("2019.12.31 20:00;2020.01.02 08:00",true);Series("2020.01.02 08:00",false);
   Check(VBWeekAnchorOffset(StringToTime("2020.01.02 16:50"))==CLOCK_UNKNOWN,"No weekly evidence fails closed",h);
   LoadSessionTable();
   Check(SessionEndMinute(StringToTime("2019.01.21"))==779,"2019 Jan21 last-bar-open deadline",h);
   Check(SessionEndMinute(StringToTime("2019.07.03"))==794,"2019 Jul03 last-bar-open deadline",h);
   Check(SessionEndMinute(StringToTime("2019.07.04"))==779,"2019 Jul04 last-bar-open deadline",h);
   Check(SessionEndMinute(StringToTime("2019.09.02"))==779,"2019 Sep02 last-bar-open deadline",h);
   Check(SessionEndMinute(StringToTime("2019.11.28"))==779,"2019 Nov28 last-bar-open deadline",h);
   Check(SessionEndMinute(StringToTime("2019.12.24"))==794,"2019 Dec24 last-bar-open deadline",h);
   FileFlush(h);FileClose(h);
   PrintFormat("[NATIVE_CLOCK_PROBE] CHECKS=%d FAILURES=%d (pure native fixture; NOT EA journal)",checks,failures);
   TerminalClose(failures>0?1:0);
}
