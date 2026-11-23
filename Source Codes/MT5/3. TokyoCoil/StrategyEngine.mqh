#ifndef TC_STRATEGY_ENGINE
#define TC_STRATEGY_ENGINE
// Native request boundary: account-scoped restriction and exact-position close intent.
// Kept inside each strategy module; no companion runtime dependency.
bool StrategyStorageFault=false;
int StrategyLease=INVALID_HANDLE;
uint StrategyScopeHash(string value)
{uint h=2166136261;for(int i=0;i<StringLen(value);i++)h=(h^(uint)StringGetCharacter(value,i))*16777619;return h;}
string StrategyScope(ulong magic)
{return "TC."+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+"."+IntegerToString(StrategyScopeHash(AccountInfoString(ACCOUNT_SERVER)+"|"+_Symbol))+"."+IntegerToString((long)magic);}
bool StrategyPersist(string key,double value)
{if(GlobalVariableSet(key,value)==0){StrategyStorageFault=true;Print("TC_STORAGE_FAILED; broker protection retained");return false;}return true;}
bool StrategyLeaseAcquire(ulong magic)
{
   if(MQLInfoInteger(MQL_TESTER))return true;
   StrategyLease=FileOpen(StrategyScope(magic)+".lock",FILE_COMMON|FILE_READ|FILE_WRITE|FILE_BIN);
   if(StrategyLease==INVALID_HANDLE){Print("TC executor already active or ownership lease unavailable");return false;}
   return true;
}
bool StrategyOwnedPosition(ulong ticket,ulong magic,ulong &id,double &volume)
{
   if(!PositionSelectByTicket(ticket) || PositionGetString(POSITION_SYMBOL)!=_Symbol || (ulong)PositionGetInteger(POSITION_MAGIC)!=magic)return false;
   id=(ulong)PositionGetInteger(POSITION_IDENTIFIER);volume=PositionGetDouble(POSITION_VOLUME);
   if(id==0 || !HistorySelectByPosition(id))return false;
   double entered=0,exited=0;
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong deal=HistoryDealGetTicket(i);long kind=HistoryDealGetInteger(deal,DEAL_ENTRY);
      if(deal==0 || (ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID)!=id || HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol || kind==DEAL_ENTRY_INOUT)return false;
      if(kind==DEAL_ENTRY_IN){if((ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=magic)return false;entered+=HistoryDealGetDouble(deal,DEAL_VOLUME);}
      else if(kind==DEAL_ENTRY_OUT || kind==DEAL_ENTRY_OUT_BY)exited+=HistoryDealGetDouble(deal,DEAL_VOLUME);
   }
   return entered>0 && MathAbs(entered-exited-volume)<=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP)*.5;
}
bool StrategyRestriction(uint code,string comment)
{
   StringToLower(comment);
   return code==TRADE_RETCODE_TRADE_DISABLED || code==TRADE_RETCODE_SERVER_DISABLES_AT || code==TRADE_RETCODE_CLOSE_ONLY ||
      StringFind(comment,"liquidation only")>=0 || StringFind(comment,"liquidation-only")>=0 ||
      StringFind(comment,"account restricted")>=0 || StringFind(comment,"no trading permissions")>=0;
}
bool StrategyCloseSettled(string key,double volume,ulong id,ulong magic)
{
   ulong order=((ulong)(uint)GlobalVariableGet(key+".hi")<<32)|(ulong)(uint)GlobalVariableGet(key+".lo");
   if(order==0 && HistorySelectByPosition(id))
   {
      for(int i=0;i<HistoryDealsTotal();i++)
      {
         ulong deal=HistoryDealGetTicket(i);long kind=HistoryDealGetInteger(deal,DEAL_ENTRY);
         if((kind!=DEAL_ENTRY_OUT && kind!=DEAL_ENTRY_OUT_BY) || (ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=magic ||
            HistoryDealGetInteger(deal,DEAL_TIME_MSC)<(long)GlobalVariableGet(key+".time"))continue;
         ulong found=(ulong)HistoryDealGetInteger(deal,DEAL_ORDER);
         if(order!=0 && order!=found)return false;
         order=found;
      }
      if(order>0){StrategyPersist(key+".hi",(double)(uint)(order>>32));StrategyPersist(key+".lo",(double)(uint)order);GlobalVariablesFlush();}
   }
   if(order==0 || OrderSelect(order) || !HistoryOrderSelect(order))return false;
   if(HistoryOrderGetString(order,ORDER_SYMBOL)!=_Symbol || (ulong)HistoryOrderGetInteger(order,ORDER_MAGIC)!=magic ||
      (ulong)HistoryOrderGetInteger(order,ORDER_POSITION_ID)!=id)return false;
   long state=HistoryOrderGetInteger(order,ORDER_STATE);
   if(state!=ORDER_STATE_FILLED && state!=ORDER_STATE_CANCELED && state!=ORDER_STATE_REJECTED && state!=ORDER_STATE_EXPIRED)return false;
   double filled=HistoryOrderGetDouble(order,ORDER_VOLUME_INITIAL)-HistoryOrderGetDouble(order,ORDER_VOLUME_CURRENT);
   return volume<=GlobalVariableGet(key+".volume")-filled+SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP)*.5;
}
bool StrategyOrderSend(const MqlTradeRequest &request,MqlTradeResult &result,bool async)
{
   if(MQLInfoInteger(MQL_TESTER))return async ? ::OrderSendAsync(request,result) : ::OrderSend(request,result);
   string scope=StrategyScope(request.magic),pending="";
   if(StrategyStorageFault || GlobalVariableCheck(scope+".restricted"))
   {ZeroMemory(result);result.retcode=TRADE_RETCODE_TRADE_DISABLED;result.comment="TC durable broker restriction; protection retained";return false;}
   if(request.position>0)
   {
      ulong id=0;double volume=0;
      if(!StrategyOwnedPosition(request.position,request.magic,id,volume))
      {ZeroMemory(result);result.retcode=TRADE_RETCODE_LOCKED;result.comment="Waiting for exact owned position/history";return false;}
      pending=scope+".C"+IntegerToString((long)id);
      if(GlobalVariableCheck(pending+".active"))
      {
         if(!StrategyCloseSettled(pending,volume,id,request.magic))
         {ZeroMemory(result);result.retcode=TRADE_RETCODE_LOCKED;result.comment="Waiting for prior owned close acknowledgement";return false;}
         GlobalVariableDel(pending+".active");GlobalVariablesFlush();
      }
      if(request.action==TRADE_ACTION_DEAL)
      {
         MqlTick quote;if(!SymbolInfoTick(_Symbol,quote))return false;
         if(!StrategyPersist(pending+".time",(double)quote.time_msc) || !StrategyPersist(pending+".volume",volume) || !StrategyPersist(pending+".hi",0) || !StrategyPersist(pending+".lo",0) || !StrategyPersist(pending+".active",1))return false;
         GlobalVariablesFlush(); // Intent precedes submission. Unknown acknowledgements never duplicate a close.
      }
      else pending="";
   }
   bool sent=async ? ::OrderSendAsync(request,result) : ::OrderSend(request,result);
   if(pending!="")
   {
      if(result.order>0){StrategyPersist(pending+".hi",(double)(uint)(result.order>>32));StrategyPersist(pending+".lo",(double)(uint)result.order);}
      bool ambiguous=result.retcode==0 || result.retcode==TRADE_RETCODE_TIMEOUT || result.retcode==TRADE_RETCODE_CONNECTION || result.retcode==TRADE_RETCODE_PLACED;
      if(!sent && !ambiguous)GlobalVariableDel(pending+".active");
      else if(result.retcode!=TRADE_RETCODE_DONE && result.retcode!=TRADE_RETCODE_DONE_PARTIAL && !ambiguous)GlobalVariableDel(pending+".active");
      GlobalVariablesFlush();
   }
   if(StrategyRestriction(result.retcode,result.comment))
   {StrategyPersist(scope+".restricted",(double)result.retcode);GlobalVariablesFlush();PrintFormat("TC_BROKER_RESTRICTED code=%u detail=%s; protection retained",result.retcode,result.comment);}
   return sent;
}
#define OnInit ResearchModelInit
#define OnTick ResearchModelTick
#define OnDeinit ResearchModelDeinit
// Frozen C1 core, derived from the preserved appendix; maintained here.
bool tcRecoveryReady=true;
datetime tcRecoveryRetry=0;
//+------------------------------------------------------------------------------------------------+
//| AsianCoilBook.mq5 — C1 "Tokyo Coil" and C3 "Tokyo Stop-Run Reclaim" (USDJPY), and their book.  |
//| C3 is included for reference but switched OFF by default: it did not survive the broker test.  |
//|                                                                                                  |
//| Clock: New York time = server time - NewYorkFromServerTime hours (IC Markets: 7, verified month by month). |
//| The Asian box: the M5 bars starting 20:00..22:55 NY (>= 30 of 36 bars, width >= 2 pips), on    |
//| Sunday-Thursday evenings. Session days = D1 bars (IC's server midnight = 17:00 NY).             |
//|                                                                                                  |
//| C1: box narrower than the median of the valid boxes among the previous 20 sessions (>= 10      |
//|     valid); OCO stop orders at the box edges from 23:00 to 03:00 NY; stop at the far side;     |
//|     exit at 12:00 NY, or one minute before the day's first high-impact USD release before noon |
//|     if that release comes after the entry.                                                     |
//| C3: at 23:00 NY, the box ran yesterday's high (low) by 0.05..0.15 ATR(14) and the 22:55 bar    |
//|     closed back inside yesterday's range: market order back into the range; stop beyond the    |
//|     swept extreme (+1 pip on the ask for shorts, as in Python); same exits.                    |
//| Both: risk 1% of balance to the initial stop; 0.5% while the sleeve's last 20 closed trades    |
//|     sum below -4R (equity brake). C1 and C3 are independent sleeves (own magic, own brake).    |
//|                                                                                                  |
//| Known, deliberate differences from the Python bar simulation (measured by the match check):    |
//|  - Python skips a day when one M5 bar touches both box edges before any entry; the EA's OCO    |
//|    orders take whichever side the tick sequence reaches first.                                  |
//|  - Python fills a stop entry exactly at the edge (+ fixed 1 pip for longs) and checks the stop |
//|    from the entry bar's full range; the EA fills and stops on ticks, with the real spread.     |
//|  - Lots are rounded down to the volume step (Python sizes continuously).                        |
//+------------------------------------------------------------------------------------------------+
#property strict

//+------------------------------------------------------------------+
//| NEWS_FEED 1.0 - one accessor for the Forex Factory weekly calendar |
//|                                                                  |
//|  Copy this block VERBATIM into every EA's ExecutionRuntime.mqh     |
//|  (between the BEGIN/END markers). It is owned by the standard:     |
//|  fix it here, re-splice, then verify with tools/news_verify.py.     |
//|                                                                  |
//|  Why it exists                                                      |
//|    The EAs want Forex Factory (accuracy), not the terminal's own    |
//|    calendar. Four EAs each called WebRequest directly, so a failed  |
//|    fetch silently changed their behaviour mid-run. This accessor:   |
//|      1. fetches the SAME url, so the data and the decisions that    |
//|         parse it are unchanged;                                    |
//|      2. keeps the last good payload in a Common file that every EA  |
//|         on the machine shares, so five EAs do one request instead   |
//|         of five;                                                   |
//|      3. falls back to that snapshot when the network is down;       |
//|      4. NEVER calls WebRequest in the Strategy Tester (the tester   |
//|         forbids it) and only uses the snapshot there when the EA     |
//|         explicitly opts in, so backtest behaviour is unchanged by   |
//|         default.                                                    |
//|                                                                  |
//|  Contract                                                          |
//|    int NewsFeedGet(string &json, datetime &fetchedUtc,              |
//|                    bool &fromCache, bool allowCacheInTester)        |
//|      200 -> json holds the calendar (fresh or cached)                |
//|        0 -> nothing usable (no network and no snapshot)             |
//|       <0 -> nothing usable; the value is the last HTTP/error code    |
//|    The caller keeps its own parser, week handling and policy.        |
//+------------------------------------------------------------------+
// ===== NEWS-FEED 1.0 BEGIN ===================================================================================
#define NF_VERSION        "1.0"
#define NF_TTL_FRESH      3600        // seconds a payload is considered current
#define NF_RETRY          300         // seconds between failed attempts
#define NF_STALE_MAX      604800      // one week: the calendar itself is weekly
#define NF_URL            "https://nfs.faireconomy.media/ff_calendar_thisweek.json"
#define NF_BODY           "NewsFeed_ff_weekly.json"
#define NF_META           "NewsFeed_ff_weekly.meta"

// Reads the shared snapshot. Returns true when a payload no older than NF_STALE_MAX is present.
bool NewsFeedReadCache(string &json, datetime &fetchedUtc, long &retryUntil)
{
   json = "";
   fetchedUtc = 0;
   retryUntil = 0;
   int meta = FileOpen(NF_META, FILE_READ | FILE_TXT | FILE_COMMON);
   if(meta != INVALID_HANDLE)
   {
      string line = FileReadString(meta);
      FileClose(meta);
      long stamp = (long)StringToInteger(line);
      if(stamp > 0) fetchedUtc = (datetime)stamp;
   }
   int body = FileOpen(NF_BODY, FILE_READ | FILE_BIN | FILE_COMMON);
   if(body != INVALID_HANDLE)
   {
      ulong size = FileSize(body);
      if(size > 8 && size < 4000000)
      {
         uchar raw[];
         ArrayResize(raw, (int)size);
         if(FileReadArray(body, raw, 0, (int)size) == (int)size)
            json = CharArrayToString(raw, 0, (int)size, CP_UTF8);
      }
      FileClose(body);
   }
   if(StringLen(json) < 8)
   {
      json = "";
      return false;
   }
   return(fetchedUtc > 0 && TimeGMT() >= fetchedUtc && TimeGMT() - fetchedUtc <= NF_STALE_MAX);
}

// Stores a payload plus its fetch time. Best effort: a read-only sandbox must not break the EA.
void NewsFeedWriteCache(const string json, const datetime fetchedUtc)
{
   if(StringLen(json) < 8) return;
   int body = FileOpen(NF_BODY, FILE_WRITE | FILE_BIN | FILE_COMMON);
   if(body == INVALID_HANDLE) return;
   uchar raw[];
   int len = StringToCharArray(json, raw, 0, -1, CP_UTF8);
   if(len > 1) FileWriteArray(body, raw, 0, len - 1);   // drop the terminating zero
   FileClose(body);
   int meta = FileOpen(NF_META, FILE_WRITE | FILE_TXT | FILE_COMMON);
   if(meta == INVALID_HANDLE) return;
   FileWriteString(meta, IntegerToString((long)fetchedUtc));
   FileClose(meta);
}

// One accessor for every EA. Never halts, never blocks longer than the request timeout.
int NewsFeedGet(string &json, datetime &fetchedUtc, bool &fromCache, bool allowCacheInTester)
{
   json = "";
   fromCache = false;
   long retryUntil = 0;
   bool haveCache = NewsFeedReadCache(json, fetchedUtc, retryUntil);

   bool tester = (bool)MQLInfoInteger(MQL_TESTER) || (bool)MQLInfoInteger(MQL_OPTIMIZATION);
   if(tester)
   {
      // The tester forbids WebRequest. Only an explicit opt-in makes backtests news-aware, and then
      // the snapshot is a fixed input: same file, same result, every run.
      if(haveCache && allowCacheInTester)
      {
         fromCache = true;
         return(200);
      }
      json = "";
      return(0);
   }

   datetime now = TimeGMT();
   if(haveCache && now >= fetchedUtc && now - fetchedUtc < NF_TTL_FRESH)
      return(200);                                   // current: no request at all
   if(now < retryUntil)
   {
      if(haveCache)
      {
         fromCache = true;
         return(200);
      }
      return(-1);
   }

   if(!(bool)TerminalInfoInteger(TERMINAL_CONNECTED))
   {
      if(haveCache)
      {
         fromCache = true;
         return(200);
      }
      return(0);
   }

   char request[], response[];
   string headers;
   ResetLastError();
   int status = WebRequest("GET", NF_URL, "User-Agent: Mozilla/5.0\r\nAccept: application/json\r\n",
                           5000, request, response, headers);
   int requestError = GetLastError();
   if(status == 200 && ArraySize(response) > 8)
   {
      string payload = CharArrayToString(response, 0, -1, CP_UTF8);
      if(StringLen(payload) > 8)
      {
         json = payload;
         fetchedUtc = TimeGMT();
         NewsFeedWriteCache(payload, fetchedUtc);
         return(200);
      }
   }

   // Failure: back off, and serve the snapshot if there is one. A stale-but-real calendar is better
   // than no calendar, and the EA's own policy decides what to do with it.
   int backoff = FileOpen(NF_META, FILE_WRITE | FILE_TXT | FILE_COMMON);
   if(backoff != INVALID_HANDLE)
   {
      FileWriteString(backoff, IntegerToString((long)(haveCache && fetchedUtc > 0 ? fetchedUtc : now)));
      FileClose(backoff);
   }
   if(haveCache)
   {
      fromCache = true;
      return(200);
   }
   json = "";
   return(status > 0 ? status : -requestError);
}
// ===== NEWS-FEED 1.0 END =====================================================================================

#property copyright "Tokyo Coil (USDJPY) - built by Claude Opus 5.5"
// Bundled MetaQuotes trade library; original copyright notices retained.
// Flattened once from the installed MT5 standard library. No external includes.
#ifndef TOKYOCOIL_BUNDLED_TRADE_MQH
#define TOKYOCOIL_BUNDLED_TRADE_MQH
//+------------------------------------------------------------------+
//|                                                        Trade.mqh |
//|                             Copyright 2000-2026, MetaQuotes Ltd. |
//|                                                     www.mql5.com |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//|                                                       Object.mqh |
//|                             Copyright 2000-2026, MetaQuotes Ltd. |
//|                                                     www.mql5.com |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//|                                                    StdLibErr.mqh |
//|                             Copyright 2000-2026, MetaQuotes Ltd. |
//|                                                     www.mql5.com |
//+------------------------------------------------------------------+
#define ERR_USER_INVALID_HANDLE                            1
#define ERR_USER_INVALID_BUFF_NUM                          2
#define ERR_USER_ITEM_NOT_FOUND                            3
#define ERR_USER_ARRAY_IS_EMPTY                            1000
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Class CObject.                                                   |
//| Purpose: Base class for storing elements.                        |
//+------------------------------------------------------------------+
class CObject
  {
private:
   CObject          *m_prev;               // previous item of list
   CObject          *m_next;               // next item of list

public:
                     CObject(void): m_prev(NULL),m_next(NULL)            {                 }
                    ~CObject(void)                                       {                 }
   //--- methods to access protected data
   CObject          *Prev(void)                                    const { return(m_prev); }
   void              Prev(CObject *node)                                 { m_prev=node;    }
   CObject          *Next(void)                                    const { return(m_next); }
   void              Next(CObject *node)                                 { m_next=node;    }
   //--- methods for working with files
   virtual bool      Save(const int file_handle)                         { return(true);   }
   virtual bool      Load(const int file_handle)                         { return(true);   }
   //--- method of identifying the object
   virtual int       Type(void)                                    const { return(0);      }
   //--- method of comparing the objects
   virtual int       Compare(const CObject *node,const int mode=0) const { return(0);      }
  };
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//|                                                    OrderInfo.mqh |
//|                             Copyright 2000-2026, MetaQuotes Ltd. |
//|                                                     www.mql5.com |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Class COrderInfo.                                                |
//| Appointment: Class for access to order info.                     |
//|              Derives from class CObject.                         |
//+------------------------------------------------------------------+
class COrderInfo : public CObject
  {
protected:
   ulong             m_ticket;
   ENUM_ORDER_TYPE   m_type;
   ENUM_ORDER_STATE  m_state;
   datetime          m_expiration;
   double            m_volume_curr;
   double            m_price_open;
   double            m_stop_loss;
   double            m_take_profit;

public:
                     COrderInfo(void);
                    ~COrderInfo(void);
   //--- methods of access to protected data
   ulong             Ticket(void) const { return(m_ticket); }
   //--- fast access methods to the integer order propertyes
   datetime          TimeSetup(void) const;
   ulong             TimeSetupMsc(void) const;
   datetime          TimeDone(void) const;
   ulong             TimeDoneMsc(void) const;
   ENUM_ORDER_TYPE   OrderType(void) const;
   string            TypeDescription(void) const;
   ENUM_ORDER_STATE  State(void) const;
   string            StateDescription(void) const;
   datetime          TimeExpiration(void) const;
   ENUM_ORDER_TYPE_FILLING TypeFilling(void) const;
   string            TypeFillingDescription(void) const;
   ENUM_ORDER_TYPE_TIME TypeTime(void) const;
   string            TypeTimeDescription(void) const;
   long              Magic(void) const;
   long              PositionId(void) const;
   long              PositionById(void) const;
   //--- fast access methods to the double order propertyes
   double            VolumeInitial(void) const;
   double            VolumeCurrent(void) const;
   double            PriceOpen(void) const;
   double            StopLoss(void) const;
   double            TakeProfit(void) const;
   double            PriceCurrent(void) const;
   double            PriceStopLimit(void) const;
   //--- fast access methods to the string order propertyes
   string            Symbol(void) const;
   string            Comment(void) const;
   string            ExternalId(void) const;
   //--- access methods to the API MQL5 functions
   bool              InfoInteger(const ENUM_ORDER_PROPERTY_INTEGER prop_id,long &var) const;
   bool              InfoDouble(const ENUM_ORDER_PROPERTY_DOUBLE prop_id,double &var) const;
   bool              InfoString(const ENUM_ORDER_PROPERTY_STRING prop_id,string &var) const;
   //--- info methods
   string            FormatType(string &str,const uint type) const;
   string            FormatStatus(string &str,const uint status) const;
   string            FormatTypeFilling(string &str,const uint type) const;
   string            FormatTypeTime(string &str,const uint type) const;
   string            FormatOrder(string &str) const;
   string            FormatPrice(string &str,const double price_order,const double price_trigger,const uint digits) const;
   //--- method for select order
   bool              Select(void);
   bool              Select(const ulong ticket);
   bool              SelectByIndex(const int index);
   //--- additional methods
   void              StoreState(void);
   bool              CheckState(void);
  };
//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
COrderInfo::COrderInfo(void) : m_ticket(ULONG_MAX),
                               m_type(WRONG_VALUE),
                               m_state(WRONG_VALUE),
                               m_expiration(0),
                               m_volume_curr(0.0),
                               m_price_open(0.0),
                               m_stop_loss(0.0),
                               m_take_profit(0.0)
  {
  }
//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
COrderInfo::~COrderInfo(void)
  {
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TIME_SETUP"                        |
//+------------------------------------------------------------------+
datetime COrderInfo::TimeSetup(void) const
  {
   return((datetime)OrderGetInteger(ORDER_TIME_SETUP));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TIME_SETUP_MSC"                    |
//+------------------------------------------------------------------+
ulong COrderInfo::TimeSetupMsc(void) const
  {
   return(OrderGetInteger(ORDER_TIME_SETUP_MSC));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TIME_DONE"                         |
//+------------------------------------------------------------------+
datetime COrderInfo::TimeDone(void) const
  {
   return((datetime)OrderGetInteger(ORDER_TIME_DONE));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TIME_DONE_MSC"                     |
//+------------------------------------------------------------------+
ulong COrderInfo::TimeDoneMsc(void) const
  {
   return(OrderGetInteger(ORDER_TIME_DONE_MSC));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TYPE"                              |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE COrderInfo::OrderType(void) const
  {
   return((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TYPE" as string                    |
//+------------------------------------------------------------------+
string COrderInfo::TypeDescription(void) const
  {
   string str;
//---
   return(FormatType(str,OrderType()));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_STATE"                             |
//+------------------------------------------------------------------+
ENUM_ORDER_STATE COrderInfo::State(void) const
  {
   return((ENUM_ORDER_STATE)OrderGetInteger(ORDER_STATE));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_STATE" as string                   |
//+------------------------------------------------------------------+
string COrderInfo::StateDescription(void) const
  {
   string str;
//---
   return(FormatStatus(str,State()));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TIME_EXPIRATION"                   |
//+------------------------------------------------------------------+
datetime COrderInfo::TimeExpiration(void) const
  {
   return((datetime)OrderGetInteger(ORDER_TIME_EXPIRATION));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TYPE_FILLING"                      |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING COrderInfo::TypeFilling(void) const
  {
   return((ENUM_ORDER_TYPE_FILLING)OrderGetInteger(ORDER_TYPE_FILLING));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TYPE_FILLING" as string            |
//+------------------------------------------------------------------+
string COrderInfo::TypeFillingDescription(void) const
  {
   string str;
//---
   return(FormatTypeFilling(str,TypeFilling()));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TYPE_TIME"                         |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_TIME COrderInfo::TypeTime(void) const
  {
   return((ENUM_ORDER_TYPE_TIME)OrderGetInteger(ORDER_TYPE_TIME));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TYPE_TIME" as string               |
//+------------------------------------------------------------------+
string COrderInfo::TypeTimeDescription(void) const
  {
   string str;
//---
   return(FormatTypeTime(str,TypeFilling()));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_MAGIC"                             |
//+------------------------------------------------------------------+
long COrderInfo::Magic(void) const
  {
   return(OrderGetInteger(ORDER_MAGIC));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_POSITION_ID"                       |
//+------------------------------------------------------------------+
long COrderInfo::PositionId(void) const
  {
   return(OrderGetInteger(ORDER_POSITION_ID));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_POSITION_BY_ID"                    |
//+------------------------------------------------------------------+
long COrderInfo::PositionById(void) const
  {
   return(OrderGetInteger(ORDER_POSITION_BY_ID));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_VOLUME_INITIAL"                    |
//+------------------------------------------------------------------+
double COrderInfo::VolumeInitial(void) const
  {
   return(OrderGetDouble(ORDER_VOLUME_INITIAL));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_VOLUME_CURRENT"                    |
//+------------------------------------------------------------------+
double COrderInfo::VolumeCurrent(void) const
  {
   return(OrderGetDouble(ORDER_VOLUME_CURRENT));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_PRICE_OPEN"                        |
//+------------------------------------------------------------------+
double COrderInfo::PriceOpen(void) const
  {
   return(OrderGetDouble(ORDER_PRICE_OPEN));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_SL"                                |
//+------------------------------------------------------------------+
double COrderInfo::StopLoss(void) const
  {
   return(OrderGetDouble(ORDER_SL));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TP"                                |
//+------------------------------------------------------------------+
double COrderInfo::TakeProfit(void) const
  {
   return(OrderGetDouble(ORDER_TP));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_PRICE_CURRENT"                     |
//+------------------------------------------------------------------+
double COrderInfo::PriceCurrent(void) const
  {
   return(OrderGetDouble(ORDER_PRICE_CURRENT));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_PRICE_STOPLIMIT"                   |
//+------------------------------------------------------------------+
double COrderInfo::PriceStopLimit(void) const
  {
   return(OrderGetDouble(ORDER_PRICE_STOPLIMIT));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_SYMBOL"                            |
//+------------------------------------------------------------------+
string COrderInfo::Symbol(void) const
  {
   return(OrderGetString(ORDER_SYMBOL));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_COMMENT"                           |
//+------------------------------------------------------------------+
string COrderInfo::Comment(void) const
  {
   return(OrderGetString(ORDER_COMMENT));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_EXTERNAL_ID"                       |
//+------------------------------------------------------------------+
string COrderInfo::ExternalId(void) const
  {
   return(OrderGetString(ORDER_EXTERNAL_ID));
  }
//+------------------------------------------------------------------+
//| Access functions OrderGetInteger(...)                            |
//+------------------------------------------------------------------+
bool COrderInfo::InfoInteger(const ENUM_ORDER_PROPERTY_INTEGER prop_id,long &var) const
  {
   return(OrderGetInteger(prop_id,var));
  }
//+------------------------------------------------------------------+
//| Access functions OrderGetDouble(...)                             |
//+------------------------------------------------------------------+
bool COrderInfo::InfoDouble(const ENUM_ORDER_PROPERTY_DOUBLE prop_id,double &var) const
  {
   return(OrderGetDouble(prop_id,var));
  }
//+------------------------------------------------------------------+
//| Access functions OrderGetString(...)                             |
//+------------------------------------------------------------------+
bool COrderInfo::InfoString(const ENUM_ORDER_PROPERTY_STRING prop_id,string &var) const
  {
   return(OrderGetString(prop_id,var));
  }
//+------------------------------------------------------------------+
//| Converts the order type to text                                  |
//+------------------------------------------------------------------+
string COrderInfo::FormatType(string &str,const uint type) const
  {
//--- see the type
   switch(type)
     {
      case ORDER_TYPE_BUY:
         str="buy";
         break;
      case ORDER_TYPE_SELL:
         str="sell";
         break;
      case ORDER_TYPE_BUY_LIMIT:
         str="buy limit";
         break;
      case ORDER_TYPE_SELL_LIMIT:
         str="sell limit";
         break;
      case ORDER_TYPE_BUY_STOP:
         str="buy stop";
         break;
      case ORDER_TYPE_SELL_STOP:
         str="sell stop";
         break;
      case ORDER_TYPE_BUY_STOP_LIMIT:
         str="buy stop limit";
         break;
      case ORDER_TYPE_SELL_STOP_LIMIT:
         str="sell stop limit";
         break;
      case ORDER_TYPE_CLOSE_BY:
         str="close by";
         break;
      default :
         str="unknown order type "+(string)type;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the order status to text                                |
//+------------------------------------------------------------------+
string COrderInfo::FormatStatus(string &str,const uint status) const
  {
//--- see the type
   switch(status)
     {
      case ORDER_STATE_STARTED:
         str="started";
         break;
      case ORDER_STATE_PLACED:
         str="placed";
         break;
      case ORDER_STATE_CANCELED:
         str="canceled";
         break;
      case ORDER_STATE_PARTIAL:
         str="partial";
         break;
      case ORDER_STATE_FILLED:
         str="filled";
         break;
      case ORDER_STATE_REJECTED:
         str="rejected";
         break;
      case ORDER_STATE_EXPIRED:
         str="expired";
         break;
      case ORDER_STATE_REQUEST_ADD:
         str="request adding";
         break;
      case ORDER_STATE_REQUEST_MODIFY:
         str="request modifying";
         break;
      case ORDER_STATE_REQUEST_CANCEL:
         str="request cancelling";
         break;
      default :
         str="unknown order status "+(string)status;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the order filling type to text                          |
//+------------------------------------------------------------------+
string COrderInfo::FormatTypeFilling(string &str,const uint type) const
  {
//--- see the type
   switch(type)
     {
      case ORDER_FILLING_RETURN:
         str="return remainder";
         break;
      case ORDER_FILLING_IOC:
         str="cancel remainder";
         break;
      case ORDER_FILLING_FOK:
         str="fill or kill";
         break;
      default:
         str="unknown type filling "+(string)type;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the type of order by expiration to text                 |
//+------------------------------------------------------------------+
string COrderInfo::FormatTypeTime(string &str,const uint type) const
  {
//--- see the type
   switch(type)
     {
      case ORDER_TIME_GTC:
         str="gtc";
         break;
      case ORDER_TIME_DAY:
         str="day";
         break;
      case ORDER_TIME_SPECIFIED:
         str="specified";
         break;
      case ORDER_TIME_SPECIFIED_DAY:
         str="specified day";
         break;
      default:
         str="unknown type time "+(string)type;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the order parameters to text                            |
//+------------------------------------------------------------------+
string COrderInfo::FormatOrder(string &str) const
  {
   string type,price;
   long   tmp_long;
//--- set up
   string symbol_name=this.Symbol();
   int    digits=_Digits;
   if(SymbolInfoInteger(symbol_name,SYMBOL_DIGITS,tmp_long))
      digits=(int)tmp_long;
//--- form the order description
   str=StringFormat("#%I64u %s %s %s",
                    Ticket(),
                    FormatType(type,OrderType()),
                    DoubleToString(VolumeInitial(),2),
                    symbol_name);
//--- receive the price of the order
   FormatPrice(price,PriceOpen(),PriceStopLimit(),digits);
//--- if there is price, write it
   if(price!="")
     {
      str+=" at ";
      str+=price;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the order prices to text                                |
//+------------------------------------------------------------------+
string COrderInfo::FormatPrice(string &str,const double price_order,const double price_trigger,const uint digits) const
  {
   string price,trigger;
//--- Is there its trigger price?
   if(price_trigger)
     {
      price  =DoubleToString(price_order,digits);
      trigger=DoubleToString(price_trigger,digits);
      str    =StringFormat("%s (%s)",price,trigger);
     }
   else
      str=DoubleToString(price_order,digits);
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Selecting an order to access                                     |
//+------------------------------------------------------------------+
bool COrderInfo::Select(void)
  {
   return(OrderSelect(m_ticket));
  }
//+------------------------------------------------------------------+
//| Selecting an order to access                                     |
//+------------------------------------------------------------------+
bool COrderInfo::Select(const ulong ticket)
  {
   if(OrderSelect(ticket))
     {
      m_ticket=ticket;
      return(true);
     }
   m_ticket=ULONG_MAX;
//---
   return(false);
  }
//+------------------------------------------------------------------+
//| Select an order by the index                                     |
//+------------------------------------------------------------------+
bool COrderInfo::SelectByIndex(const int index)
  {
   ulong ticket=OrderGetTicket(index);
   if(ticket==0)
     {
      m_ticket=ULONG_MAX;
      return(false);
     }
   m_ticket=ticket;
//---
   return(true);
  }
//+------------------------------------------------------------------+
//| Stored order's current state                                     |
//+------------------------------------------------------------------+
void COrderInfo::StoreState(void)
  {
   m_type       =OrderType();
   m_state      =State();
   m_expiration =TimeExpiration();
   m_volume_curr=VolumeCurrent();
   m_price_open =PriceOpen();
   m_stop_loss  =StopLoss();
   m_take_profit=TakeProfit();
  }
//+------------------------------------------------------------------+
//| Check order change                                               |
//+------------------------------------------------------------------+
bool COrderInfo::CheckState(void)
  {
   if(m_type==OrderType()            &&
      m_state==State()               &&
      m_expiration==TimeExpiration() &&
      m_volume_curr==VolumeCurrent() &&
      m_price_open==PriceOpen()      &&
      m_stop_loss==StopLoss()        &&
      m_take_profit==TakeProfit())
      return(false);
//---
   return(true);
  }
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//|                                             HistoryOrderInfo.mqh |
//|                             Copyright 2000-2026, MetaQuotes Ltd. |
//|                                                     www.mql5.com |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Class CHistoryOrderInfo.                                         |
//| Appointment: Class for access to history order info.             |
//|              Derives from class CObject.                         |
//+------------------------------------------------------------------+
class CHistoryOrderInfo : public CObject
  {
protected:
   ulong             m_ticket;             // ticket of history order
public:
                     CHistoryOrderInfo(void);
                    ~CHistoryOrderInfo(void);
   //--- methods of access to protected data
   void              Ticket(const ulong ticket) { m_ticket=ticket;  }
   ulong             Ticket(void)         const { return(m_ticket); }
   //--- fast access methods to the integer order propertyes
   datetime          TimeSetup(void) const;
   ulong             TimeSetupMsc(void) const;
   datetime          TimeDone(void) const;
   ulong             TimeDoneMsc(void) const;
   ENUM_ORDER_TYPE   OrderType(void) const;
   string            TypeDescription(void) const;
   ENUM_ORDER_STATE  State(void) const;
   string            StateDescription(void) const;
   datetime          TimeExpiration(void) const;
   ENUM_ORDER_TYPE_FILLING TypeFilling(void) const;
   string            TypeFillingDescription(void) const;
   ENUM_ORDER_TYPE_TIME TypeTime(void) const;
   string            TypeTimeDescription(void) const;
   long              Magic(void) const;
   long              PositionId(void) const;
   long              PositionById(void) const;
   //--- fast access methods to the double order propertyes
   double            VolumeInitial(void) const;
   double            VolumeCurrent(void) const;
   double            PriceOpen(void) const;
   double            StopLoss(void) const;
   double            TakeProfit(void) const;
   double            PriceCurrent(void) const;
   double            PriceStopLimit(void) const;
   //--- fast access methods to the string order propertyes
   string            Symbol(void) const;
   string            Comment(void) const;
   string            ExternalId(void) const;
   //--- access methods to the API MQL5 functions
   bool              InfoInteger(const ENUM_ORDER_PROPERTY_INTEGER prop_id,long &var) const;
   bool              InfoDouble(const ENUM_ORDER_PROPERTY_DOUBLE prop_id,double &var) const;
   bool              InfoString(const ENUM_ORDER_PROPERTY_STRING prop_id,string &var) const;
   //--- info methods
   string            FormatType(string &str,const uint type) const;
   string            FormatStatus(string &str,const uint status) const;
   string            FormatTypeFilling(string &str,const uint type) const;
   string            FormatTypeTime(string &str,const uint type) const;
   string            FormatOrder(string &str) const;
   string            FormatPrice(string &str,const double price_order,const double price_trigger,const uint digits) const;
   //--- method for select history order
   bool              SelectByIndex(const int index);
  };
//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CHistoryOrderInfo::CHistoryOrderInfo(void) : m_ticket(0)
  {
  }
//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CHistoryOrderInfo::~CHistoryOrderInfo(void)
  {
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TIME_SETUP"                        |
//+------------------------------------------------------------------+
datetime CHistoryOrderInfo::TimeSetup(void) const
  {
   return((datetime)HistoryOrderGetInteger(m_ticket,ORDER_TIME_SETUP));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TIME_SETUP_MSC"                    |
//+------------------------------------------------------------------+
ulong CHistoryOrderInfo::TimeSetupMsc(void) const
  {
   return(HistoryOrderGetInteger(m_ticket,ORDER_TIME_SETUP_MSC));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TIME_DONE"                         |
//+------------------------------------------------------------------+
datetime CHistoryOrderInfo::TimeDone(void) const
  {
   return((datetime)HistoryOrderGetInteger(m_ticket,ORDER_TIME_DONE));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TIME_DONE_MSC"                     |
//+------------------------------------------------------------------+
ulong CHistoryOrderInfo::TimeDoneMsc(void) const
  {
   return(HistoryOrderGetInteger(m_ticket,ORDER_TIME_DONE_MSC));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TYPE"                              |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE CHistoryOrderInfo::OrderType(void) const
  {
   return((ENUM_ORDER_TYPE)HistoryOrderGetInteger(m_ticket,ORDER_TYPE));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TYPE" as string                    |
//+------------------------------------------------------------------+
string CHistoryOrderInfo::TypeDescription(void) const
  {
   string str;
//---
   return(FormatType(str,OrderType()));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_STATE"                             |
//+------------------------------------------------------------------+
ENUM_ORDER_STATE CHistoryOrderInfo::State(void) const
  {
   return((ENUM_ORDER_STATE)HistoryOrderGetInteger(m_ticket,ORDER_STATE));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_STATE" as string                   |
//+------------------------------------------------------------------+
string CHistoryOrderInfo::StateDescription(void) const
  {
   string str;
//---
   return(FormatStatus(str,State()));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TIME_EXPIRATION"                   |
//+------------------------------------------------------------------+
datetime CHistoryOrderInfo::TimeExpiration(void) const
  {
   return((datetime)HistoryOrderGetInteger(m_ticket,ORDER_TIME_EXPIRATION));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TYPE_FILLING"                      |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING CHistoryOrderInfo::TypeFilling(void) const
  {
   return((ENUM_ORDER_TYPE_FILLING)HistoryOrderGetInteger(m_ticket,ORDER_TYPE_FILLING));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TYPE_FILLING" as string            |
//+------------------------------------------------------------------+
string CHistoryOrderInfo::TypeFillingDescription(void) const
  {
   string str;
//---
   return(FormatTypeFilling(str,TypeFilling()));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TYPE_TIME"                         |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_TIME CHistoryOrderInfo::TypeTime(void) const
  {
   return((ENUM_ORDER_TYPE_TIME)HistoryOrderGetInteger(m_ticket,ORDER_TYPE_TIME));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TYPE_TIME" as string               |
//+------------------------------------------------------------------+
string CHistoryOrderInfo::TypeTimeDescription(void) const
  {
   string str;
//---
   return(FormatTypeTime(str,TypeTime()));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_EXPERT"                            |
//+------------------------------------------------------------------+
long CHistoryOrderInfo::Magic(void) const
  {
   return(HistoryOrderGetInteger(m_ticket,ORDER_MAGIC));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_POSITION_ID"                       |
//+------------------------------------------------------------------+
long CHistoryOrderInfo::PositionId(void) const
  {
   return(HistoryOrderGetInteger(m_ticket,ORDER_POSITION_ID));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_POSITION_BY_ID"                    |
//+------------------------------------------------------------------+
long CHistoryOrderInfo::PositionById(void) const
  {
   return(HistoryOrderGetInteger(m_ticket,ORDER_POSITION_BY_ID));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_VOLUME_INITIAL"                    |
//+------------------------------------------------------------------+
double CHistoryOrderInfo::VolumeInitial(void) const
  {
   return(HistoryOrderGetDouble(m_ticket,ORDER_VOLUME_INITIAL));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_VOLUME_CURRENT"                    |
//+------------------------------------------------------------------+
double CHistoryOrderInfo::VolumeCurrent(void) const
  {
   return(HistoryOrderGetDouble(m_ticket,ORDER_VOLUME_CURRENT));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_PRICE_OPEN"                        |
//+------------------------------------------------------------------+
double CHistoryOrderInfo::PriceOpen(void) const
  {
   return(HistoryOrderGetDouble(m_ticket,ORDER_PRICE_OPEN));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_SL"                                |
//+------------------------------------------------------------------+
double CHistoryOrderInfo::StopLoss(void) const
  {
   return(HistoryOrderGetDouble(m_ticket,ORDER_SL));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TP"                                |
//+------------------------------------------------------------------+
double CHistoryOrderInfo::TakeProfit(void) const
  {
   return(HistoryOrderGetDouble(m_ticket,ORDER_TP));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_PRICE_CURRENT"                     |
//+------------------------------------------------------------------+
double CHistoryOrderInfo::PriceCurrent(void) const
  {
   return(HistoryOrderGetDouble(m_ticket,ORDER_PRICE_CURRENT));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_PRICE_STOPLIMIT"                   |
//+------------------------------------------------------------------+
double CHistoryOrderInfo::PriceStopLimit(void) const
  {
   return(HistoryOrderGetDouble(m_ticket,ORDER_PRICE_STOPLIMIT));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_SYMBOL"                            |
//+------------------------------------------------------------------+
string CHistoryOrderInfo::Symbol(void) const
  {
   return(HistoryOrderGetString(m_ticket,ORDER_SYMBOL));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_COMMENT"                           |
//+------------------------------------------------------------------+
string CHistoryOrderInfo::Comment(void) const
  {
   return(HistoryOrderGetString(m_ticket,ORDER_COMMENT));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_EXTERNAL_ID"                       |
//+------------------------------------------------------------------+
string CHistoryOrderInfo::ExternalId(void) const
  {
   return(HistoryOrderGetString(m_ticket,ORDER_EXTERNAL_ID));
  }
//+------------------------------------------------------------------+
//| Access functions OrderGetInteger(...)                            |
//+------------------------------------------------------------------+
bool CHistoryOrderInfo::InfoInteger(const ENUM_ORDER_PROPERTY_INTEGER prop_id,long &var) const
  {
   return(HistoryOrderGetInteger(m_ticket,prop_id,var));
  }
//+------------------------------------------------------------------+
//| Access functions OrderGetDouble(...)                             |
//+------------------------------------------------------------------+
bool CHistoryOrderInfo::InfoDouble(const ENUM_ORDER_PROPERTY_DOUBLE prop_id,double &var) const
  {
   return(HistoryOrderGetDouble(m_ticket,prop_id,var));
  }
//+------------------------------------------------------------------+
//| Access functions OrderGetString(...)                             |
//+------------------------------------------------------------------+
bool CHistoryOrderInfo::InfoString(const ENUM_ORDER_PROPERTY_STRING prop_id,string &var) const
  {
   return(HistoryOrderGetString(m_ticket,prop_id,var));
  }
//+------------------------------------------------------------------+
//| Converts the order type to text                                  |
//+------------------------------------------------------------------+
string CHistoryOrderInfo::FormatType(string &str,const uint type) const
  {
//--- see the type
   switch(type)
     {
      case ORDER_TYPE_BUY:
         str="buy";
         break;
      case ORDER_TYPE_SELL:
         str="sell";
         break;
      case ORDER_TYPE_BUY_LIMIT:
         str="buy limit";
         break;
      case ORDER_TYPE_SELL_LIMIT:
         str="sell limit";
         break;
      case ORDER_TYPE_BUY_STOP:
         str="buy stop";
         break;
      case ORDER_TYPE_SELL_STOP:
         str="sell stop";
         break;
      case ORDER_TYPE_BUY_STOP_LIMIT:
         str="buy stop limit";
         break;
      case ORDER_TYPE_SELL_STOP_LIMIT:
         str="sell stop limit";
         break;
      case ORDER_TYPE_CLOSE_BY:
         str="close by";
         break;
      default:
         str="unknown order type "+(string)type;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the order status to text                                |
//+------------------------------------------------------------------+
string CHistoryOrderInfo::FormatStatus(string &str,const uint status) const
  {
//--- see the type
   switch(status)
     {
      case ORDER_STATE_STARTED:
         str="started";
         break;
      case ORDER_STATE_PLACED:
         str="placed";
         break;
      case ORDER_STATE_CANCELED:
         str="canceled";
         break;
      case ORDER_STATE_PARTIAL:
         str="partial";
         break;
      case ORDER_STATE_FILLED:
         str="filled";
         break;
      case ORDER_STATE_REJECTED:
         str="rejected";
         break;
      case ORDER_STATE_EXPIRED:
         str="expired";
         break;
      default:
         str="unknown order status "+(string)status;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the order filling type to text                          |
//+------------------------------------------------------------------+
string CHistoryOrderInfo::FormatTypeFilling(string &str,const uint type) const
  {
//--- see the type
   switch(type)
     {
      case ORDER_FILLING_RETURN:
         str="return remainder";
         break;
      case ORDER_FILLING_IOC:
         str="cancel remainder";
         break;
      case ORDER_FILLING_FOK:
         str="fill or kill";
         break;
      default:
         str="unknown type filling "+(string)type;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the type of order by expiration to text                 |
//+------------------------------------------------------------------+
string CHistoryOrderInfo::FormatTypeTime(string &str,const uint type) const
  {
//--- see the type
   switch(type)
     {
      case ORDER_TIME_GTC:
         str="gtc";
         break;
      case ORDER_TIME_DAY:
         str="day";
         break;
      case ORDER_TIME_SPECIFIED:
         str="specified";
         break;
      case ORDER_TIME_SPECIFIED_DAY:
         str="specified day";
         break;
      default:
         str="unknown type time "+(string)type;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the order parameters to text                            |
//+------------------------------------------------------------------+
string CHistoryOrderInfo::FormatOrder(string &str) const
  {
   string type,price;
   long   tmp_long;
//--- set up
   string symbol_name=this.Symbol();
   int    digits=_Digits;
   if(SymbolInfoInteger(symbol_name,SYMBOL_DIGITS,tmp_long))
      digits=(int)tmp_long;
//--- form the order description
   str=StringFormat("#%I64u %s %s %s",
                    Ticket(),
                    FormatType(type,OrderType()),
                    DoubleToString(VolumeInitial(),2),
                    symbol_name);
//--- receive the price of the order
   FormatPrice(price,PriceOpen(),PriceStopLimit(),digits);
//--- if there is price, write it
   if(price!="")
     {
      str+=" at ";
      str+=price;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the order prices to text                                |
//+------------------------------------------------------------------+
string CHistoryOrderInfo::FormatPrice(string &str,const double price_order,const double price_trigger,const uint digits) const
  {
   string price,trigger;
//--- Is there its trigger price?
   if(price_trigger)
     {
      price  =DoubleToString(price_order,digits);
      trigger=DoubleToString(price_trigger,digits);
      str    =StringFormat("%s (%s)",price,trigger);
     }
   else
      str=DoubleToString(price_order,digits);
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Select a history order on the index                              |
//+------------------------------------------------------------------+
bool CHistoryOrderInfo::SelectByIndex(const int index)
  {
   ulong ticket=HistoryOrderGetTicket(index);
   if(ticket==0)
      return(false);
   Ticket(ticket);
//---
   return(true);
  }
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//|                                                 PositionInfo.mqh |
//|                             Copyright 2000-2026, MetaQuotes Ltd. |
//|                                                     www.mql5.com |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Class CPositionInfo.                                             |
//| Appointment: Class for access to position info.                  |
//|              Derives from class CObject.                         |
//+------------------------------------------------------------------+
class CPositionInfo : public CObject
  {
protected:
   ENUM_POSITION_TYPE m_type;
   double            m_volume;
   double            m_price;
   double            m_stop_loss;
   double            m_take_profit;

public:
                     CPositionInfo(void);
                    ~CPositionInfo(void);
   //--- fast access methods to the integer position propertyes
   ulong             Ticket(void) const;
   datetime          Time(void) const;
   ulong             TimeMsc(void) const;
   datetime          TimeUpdate(void) const;
   ulong             TimeUpdateMsc(void) const;
   ENUM_POSITION_TYPE PositionType(void) const;
   string            TypeDescription(void) const;
   long              Magic(void) const;
   long              Identifier(void) const;
   //--- fast access methods to the double position propertyes
   double            Volume(void) const;
   double            PriceOpen(void) const;
   double            StopLoss(void) const;
   double            TakeProfit(void) const;
   double            PriceCurrent(void) const;
   double            Commission(void) const;
   double            Swap(void) const;
   double            Profit(void) const;
   //--- fast access methods to the string position propertyes
   string            Symbol(void) const;
   string            Comment(void) const;
   //--- access methods to the API MQL5 functions
   bool              InfoInteger(const ENUM_POSITION_PROPERTY_INTEGER prop_id,long &var) const;
   bool              InfoDouble(const ENUM_POSITION_PROPERTY_DOUBLE prop_id,double &var) const;
   bool              InfoString(const ENUM_POSITION_PROPERTY_STRING prop_id,string &var) const;
   //--- info methods
   string            FormatType(string &str,const uint type) const;
   string            FormatPosition(string &str) const;
   //--- methods for select position
   bool              Select(const string symbol);
   bool              SelectByMagic(const string symbol,const ulong magic);
   bool              SelectByTicket(const ulong ticket);
   bool              SelectByIndex(const int index);
   //---
   void              StoreState(void);
   bool              CheckState(void);
  };
//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CPositionInfo::CPositionInfo(void) : m_type(WRONG_VALUE),
                                     m_volume(0.0),
                                     m_price(0.0),
                                     m_stop_loss(0.0),
                                     m_take_profit(0.0)
  {
  }
//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CPositionInfo::~CPositionInfo(void)
  {
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_TICKET"                         |
//+------------------------------------------------------------------+
ulong CPositionInfo::Ticket(void) const
  {
   return((ulong)PositionGetInteger(POSITION_TICKET));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_TIME"                           |
//+------------------------------------------------------------------+
datetime CPositionInfo::Time(void) const
  {
   return((datetime)PositionGetInteger(POSITION_TIME));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_TIME_MSC"                       |
//+------------------------------------------------------------------+
ulong CPositionInfo::TimeMsc(void) const
  {
   return((ulong)PositionGetInteger(POSITION_TIME_MSC));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_TIME_UPDATE"                    |
//+------------------------------------------------------------------+
datetime CPositionInfo::TimeUpdate(void) const
  {
   return((datetime)PositionGetInteger(POSITION_TIME_UPDATE));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_TIME_UPDATE_MSC"                |
//+------------------------------------------------------------------+
ulong CPositionInfo::TimeUpdateMsc(void) const
  {
   return((ulong)PositionGetInteger(POSITION_TIME_UPDATE_MSC));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_TYPE"                           |
//+------------------------------------------------------------------+
ENUM_POSITION_TYPE CPositionInfo::PositionType(void) const
  {
   return((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_TYPE" as string                 |
//+------------------------------------------------------------------+
string CPositionInfo::TypeDescription(void) const
  {
   string str;
//---
   return(FormatType(str,PositionType()));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_MAGIC"                          |
//+------------------------------------------------------------------+
long CPositionInfo::Magic(void) const
  {
   return(PositionGetInteger(POSITION_MAGIC));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_IDENTIFIER"                     |
//+------------------------------------------------------------------+
long CPositionInfo::Identifier(void) const
  {
   return(PositionGetInteger(POSITION_IDENTIFIER));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_VOLUME"                         |
//+------------------------------------------------------------------+
double CPositionInfo::Volume(void) const
  {
   return(PositionGetDouble(POSITION_VOLUME));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_PRICE_OPEN"                     |
//+------------------------------------------------------------------+
double CPositionInfo::PriceOpen(void) const
  {
   return(PositionGetDouble(POSITION_PRICE_OPEN));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_SL"                             |
//+------------------------------------------------------------------+
double CPositionInfo::StopLoss(void) const
  {
   return(PositionGetDouble(POSITION_SL));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_TP"                             |
//+------------------------------------------------------------------+
double CPositionInfo::TakeProfit(void) const
  {
   return(PositionGetDouble(POSITION_TP));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_PRICE_CURRENT"                  |
//+------------------------------------------------------------------+
double CPositionInfo::PriceCurrent(void) const
  {
   return(PositionGetDouble(POSITION_PRICE_CURRENT));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_COMMISSION"                     |
//+------------------------------------------------------------------+
double CPositionInfo::Commission(void) const
  {
//--- property POSITION_COMMISSION is deprecated
   SetUserError(ERR_FUNCTION_NOT_ALLOWED);
   return(0);
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_SWAP"                           |
//+------------------------------------------------------------------+
double CPositionInfo::Swap(void) const
  {
   return(PositionGetDouble(POSITION_SWAP));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_PROFIT"                         |
//+------------------------------------------------------------------+
double CPositionInfo::Profit(void) const
  {
   return(PositionGetDouble(POSITION_PROFIT));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_SYMBOL"                         |
//+------------------------------------------------------------------+
string CPositionInfo::Symbol(void) const
  {
   return(PositionGetString(POSITION_SYMBOL));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_COMMENT"                        |
//+------------------------------------------------------------------+
string CPositionInfo::Comment(void) const
  {
   return(PositionGetString(POSITION_COMMENT));
  }
//+------------------------------------------------------------------+
//| Access functions PositionGetInteger(...)                         |
//+------------------------------------------------------------------+
bool CPositionInfo::InfoInteger(const ENUM_POSITION_PROPERTY_INTEGER prop_id,long &var) const
  {
   return(PositionGetInteger(prop_id,var));
  }
//+------------------------------------------------------------------+
//| Access functions PositionGetDouble(...)                          |
//+------------------------------------------------------------------+
bool CPositionInfo::InfoDouble(const ENUM_POSITION_PROPERTY_DOUBLE prop_id,double &var) const
  {
   return(PositionGetDouble(prop_id,var));
  }
//+------------------------------------------------------------------+
//| Access functions PositionGetString(...)                          |
//+------------------------------------------------------------------+
bool CPositionInfo::InfoString(const ENUM_POSITION_PROPERTY_STRING prop_id,string &var) const
  {
   return(PositionGetString(prop_id,var));
  }
//+------------------------------------------------------------------+
//| Converts the position type to text                               |
//+------------------------------------------------------------------+
string CPositionInfo::FormatType(string &str,const uint type) const
  {
//--- see the type
   switch(type)
     {
      case POSITION_TYPE_BUY:
         str="buy";
         break;
      case POSITION_TYPE_SELL:
         str="sell";
         break;
      default:
         str="unknown position type "+(string)type;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the position parameters to text                         |
//+------------------------------------------------------------------+
string CPositionInfo::FormatPosition(string &str) const
  {
   string tmp,type;
   long   tmp_long;
   ENUM_ACCOUNT_MARGIN_MODE margin_mode=(ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
//--- set up
   string symbol_name=this.Symbol();
   int    digits=_Digits;
   if(SymbolInfoInteger(symbol_name,SYMBOL_DIGITS,tmp_long))
      digits=(int)tmp_long;
//--- form the position description
   if(margin_mode==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      str=StringFormat("#%I64u %s %s %s %s",
                       Ticket(),
                       FormatType(type,PositionType()),
                       DoubleToString(Volume(),2),
                       symbol_name,
                       DoubleToString(PriceOpen(),digits+3));
   else
      str=StringFormat("%s %s %s %s",
                       FormatType(type,PositionType()),
                       DoubleToString(Volume(),2),
                       symbol_name,
                       DoubleToString(PriceOpen(),digits+3));
//--- add stops if there are any
   double sl=StopLoss();
   double tp=TakeProfit();
   if(sl!=0.0)
     {
      tmp=StringFormat(" sl: %s",DoubleToString(sl,digits));
      str+=tmp;
     }
   if(tp!=0.0)
     {
      tmp=StringFormat(" tp: %s",DoubleToString(tp,digits));
      str+=tmp;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Access functions PositionSelect(...)                             |
//+------------------------------------------------------------------+
bool CPositionInfo::Select(const string symbol)
  {
   return(PositionSelect(symbol));
  }
//+------------------------------------------------------------------+
//| Access functions PositionSelect(...)                             |
//+------------------------------------------------------------------+
bool CPositionInfo::SelectByMagic(const string symbol,const ulong magic)
  {
   bool res=false;
   uint total=PositionsTotal();
//---
   for(uint i=0; i<total; i++)
     {
      string position_symbol=PositionGetSymbol(i);
      if(position_symbol==symbol && magic==PositionGetInteger(POSITION_MAGIC))
        {
         res=true;
         break;
        }
     }
//---
   return(res);
  }
//+------------------------------------------------------------------+
//| Access functions PositionSelectByTicket(...)                     |
//+------------------------------------------------------------------+
bool CPositionInfo::SelectByTicket(const ulong ticket)
  {
   return(PositionSelectByTicket(ticket));
  }
//+------------------------------------------------------------------+
//| Select a position on the index                                   |
//+------------------------------------------------------------------+
bool CPositionInfo::SelectByIndex(const int index)
  {
   ulong ticket=PositionGetTicket(index);
   return(ticket>0);
  }
//+------------------------------------------------------------------+
//| Stored position's current state                                  |
//+------------------------------------------------------------------+
void CPositionInfo::StoreState(void)
  {
   m_type       =PositionType();
   m_volume     =Volume();
   m_price      =PriceOpen();
   m_stop_loss  =StopLoss();
   m_take_profit=TakeProfit();
  }
//+------------------------------------------------------------------+
//| Check position change                                            |
//+------------------------------------------------------------------+
bool CPositionInfo::CheckState(void)
  {
   if(m_type==PositionType()  &&
      m_volume==Volume()      &&
      m_price==PriceOpen()    &&
      m_stop_loss==StopLoss() &&
      m_take_profit==TakeProfit())
      return(false);
//---
   return(true);
  }
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//|                                                     DealInfo.mqh |
//|                             Copyright 2000-2026, MetaQuotes Ltd. |
//|                                                     www.mql5.com |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Class CDealInfo.                                                 |
//| Appointment: Class for access to history deal info.              |
//|              Derives from class CObject.                         |
//+------------------------------------------------------------------+
class CDealInfo : public CObject
  {
protected:
   ulong             m_ticket;             // ticket of history order

public:
                     CDealInfo(void);
                    ~CDealInfo(void);
   //--- methods of access to protected data
   void              Ticket(const ulong ticket)   { m_ticket=ticket;  }
   ulong             Ticket(void)           const { return(m_ticket); }
   //--- fast access methods to the integer position propertyes
   long              Order(void) const;
   datetime          Time(void) const;
   ulong             TimeMsc(void) const;
   ENUM_DEAL_TYPE    DealType(void) const;
   string            TypeDescription(void) const;
   ENUM_DEAL_ENTRY   Entry(void) const;
   string            EntryDescription(void) const;
   long              Magic(void) const;
   long              PositionId(void) const;
   //--- fast access methods to the double position propertyes
   double            Volume(void) const;
   double            Price(void) const;
   double            Commission(void) const;
   double            Swap(void) const;
   double            Profit(void) const;
   //--- fast access methods to the string position propertyes
   string            Symbol(void) const;
   string            Comment(void) const;
   string            ExternalId(void) const;
   //--- access methods to the API MQL5 functions
   bool              InfoInteger(ENUM_DEAL_PROPERTY_INTEGER prop_id,long &var) const;
   bool              InfoDouble(ENUM_DEAL_PROPERTY_DOUBLE prop_id,double &var) const;
   bool              InfoString(ENUM_DEAL_PROPERTY_STRING prop_id,string &var) const;
   //--- info methods
   string            FormatAction(string &str,const uint action) const;
   string            FormatEntry(string &str,const uint entry) const;
   string            FormatDeal(string &str) const;
   //--- method for select deal
   bool              SelectByIndex(const int index);
  };
//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CDealInfo::CDealInfo(void)
  {
  }
//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CDealInfo::~CDealInfo(void)
  {
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_ORDER"                              |
//+------------------------------------------------------------------+
long CDealInfo::Order(void) const
  {
   return(HistoryDealGetInteger(m_ticket,DEAL_ORDER));
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_TIME"                               |
//+------------------------------------------------------------------+
datetime CDealInfo::Time(void) const
  {
   return((datetime)HistoryDealGetInteger(m_ticket,DEAL_TIME));
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_TIME_MSC"                           |
//+------------------------------------------------------------------+
ulong CDealInfo::TimeMsc(void) const
  {
   return(HistoryDealGetInteger(m_ticket,DEAL_TIME_MSC));
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_TYPE"                               |
//+------------------------------------------------------------------+
ENUM_DEAL_TYPE CDealInfo::DealType(void) const
  {
   return((ENUM_DEAL_TYPE)HistoryDealGetInteger(m_ticket,DEAL_TYPE));
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_TYPE" as string                     |
//+------------------------------------------------------------------+
string CDealInfo::TypeDescription(void) const
  {
   string str;
//---
   switch(DealType())
     {
      case DEAL_TYPE_BUY:
         str="Buy type";
         break;
      case DEAL_TYPE_SELL:
         str="Sell type";
         break;
      case DEAL_TYPE_BALANCE:
         str="Balance type";
         break;
      case DEAL_TYPE_CREDIT:
         str="Credit type";
         break;
      case DEAL_TYPE_CHARGE:
         str="Charge type";
         break;
      case DEAL_TYPE_CORRECTION:
         str="Correction type";
         break;
      case DEAL_TYPE_BONUS:
         str="Bonus type";
         break;
      case DEAL_TYPE_COMMISSION:
         str="Commission type";
         break;
      case DEAL_TYPE_COMMISSION_DAILY:
         str="Daily Commission type";
         break;
      case DEAL_TYPE_COMMISSION_MONTHLY:
         str="Monthly Commission type";
         break;
      case DEAL_TYPE_COMMISSION_AGENT_DAILY:
         str="Daily Agent Commission type";
         break;
      case DEAL_TYPE_COMMISSION_AGENT_MONTHLY:
         str="Monthly Agent Commission type";
         break;
      case DEAL_TYPE_INTEREST:
         str="Interest Rate type";
         break;
      case DEAL_TYPE_BUY_CANCELED:
         str="Canceled Buy type";
         break;
      case DEAL_TYPE_SELL_CANCELED:
         str="Canceled Sell type";
         break;
      default:
         str="Unknown type";
     }
//---
   return(str);
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_ENTRY"                              |
//+------------------------------------------------------------------+
ENUM_DEAL_ENTRY CDealInfo::Entry(void) const
  {
   return((ENUM_DEAL_ENTRY)HistoryDealGetInteger(m_ticket,DEAL_ENTRY));
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_ENTRY" as string                    |
//+------------------------------------------------------------------+
string CDealInfo::EntryDescription(void) const
  {
   string str;
//---
   switch(CDealInfo::Entry())
     {
      case DEAL_ENTRY_IN:
         str="In entry";
         break;
      case DEAL_ENTRY_OUT:
         str="Out entry";
         break;
      case DEAL_ENTRY_INOUT:
         str="InOut entry";
         break;
      case DEAL_ENTRY_STATE:
         str="Status record";
         break;
      case DEAL_ENTRY_OUT_BY:
         str="Out By entry";
         break;
      default:
         str="Unknown entry";
     }
//---
   return(str);
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_MAGIC"                              |
//+------------------------------------------------------------------+
long CDealInfo::Magic(void) const
  {
   return(HistoryDealGetInteger(m_ticket,DEAL_MAGIC));
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_POSITION_ID"                        |
//+------------------------------------------------------------------+
long CDealInfo::PositionId(void) const
  {
   return(HistoryDealGetInteger(m_ticket,DEAL_POSITION_ID));
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_VOLUME"                             |
//+------------------------------------------------------------------+
double CDealInfo::Volume(void) const
  {
   return(HistoryDealGetDouble(m_ticket,DEAL_VOLUME));
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_PRICE_OPEN"                         |
//+------------------------------------------------------------------+
double CDealInfo::Price(void) const
  {
   return(HistoryDealGetDouble(m_ticket,DEAL_PRICE));
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_COMMISSION"                         |
//+------------------------------------------------------------------+
double CDealInfo::Commission(void) const
  {
   return(HistoryDealGetDouble(m_ticket,DEAL_COMMISSION));
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_SWAP"                               |
//+------------------------------------------------------------------+
double CDealInfo::Swap(void) const
  {
   return(HistoryDealGetDouble(m_ticket,DEAL_SWAP));
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_PROFIT"                             |
//+------------------------------------------------------------------+
double CDealInfo::Profit(void) const
  {
   return(HistoryDealGetDouble(m_ticket,DEAL_PROFIT));
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_SYMBOL"                             |
//+------------------------------------------------------------------+
string CDealInfo::Symbol(void) const
  {
   return(HistoryDealGetString(m_ticket,DEAL_SYMBOL));
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_COMMENT"                            |
//+------------------------------------------------------------------+
string CDealInfo::Comment(void) const
  {
   return(HistoryDealGetString(m_ticket,DEAL_COMMENT));
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_EXTERNAL_ID"                        |
//+------------------------------------------------------------------+
string CDealInfo::ExternalId(void) const
  {
   return(HistoryDealGetString(m_ticket,DEAL_EXTERNAL_ID));
  }
//+------------------------------------------------------------------+
//| Access functions HistoryDealGetInteger(...)                      |
//+------------------------------------------------------------------+
bool CDealInfo::InfoInteger(ENUM_DEAL_PROPERTY_INTEGER prop_id,long &var) const
  {
   return(HistoryDealGetInteger(m_ticket,prop_id,var));
  }
//+------------------------------------------------------------------+
//| Access functions HistoryDealGetDouble(...)                       |
//+------------------------------------------------------------------+
bool CDealInfo::InfoDouble(ENUM_DEAL_PROPERTY_DOUBLE prop_id,double &var) const
  {
   return(HistoryDealGetDouble(m_ticket,prop_id,var));
  }
//+------------------------------------------------------------------+
//| Access functions HistoryDealGetString(...)                       |
//+------------------------------------------------------------------+
bool CDealInfo::InfoString(ENUM_DEAL_PROPERTY_STRING prop_id,string &var) const
  {
   return(HistoryDealGetString(m_ticket,prop_id,var));
  }
//+------------------------------------------------------------------+
//| Converths the type of a  deal to text                            |
//+------------------------------------------------------------------+
string CDealInfo::FormatAction(string &str,const uint action) const
  {
//--- see the type
   switch(action)
     {
      case DEAL_TYPE_BUY:
         str="buy";
         break;
      case DEAL_TYPE_SELL:
         str="sell";
         break;
      case DEAL_TYPE_BALANCE:
         str="balance";
         break;
      case DEAL_TYPE_CREDIT:
         str="credit";
         break;
      case DEAL_TYPE_CHARGE:
         str="charge";
         break;
      case DEAL_TYPE_CORRECTION:
         str="correction";
         break;
      case DEAL_TYPE_BONUS:
         str="bonus";
         break;
      case DEAL_TYPE_COMMISSION:
         str="commission";
         break;
      case DEAL_TYPE_COMMISSION_DAILY:
         str="daily commission";
         break;
      case DEAL_TYPE_COMMISSION_MONTHLY:
         str="monthly commission";
         break;
      case DEAL_TYPE_COMMISSION_AGENT_DAILY:
         str="daily agent commission";
         break;
      case DEAL_TYPE_COMMISSION_AGENT_MONTHLY:
         str="monthly agent commission";
         break;
      case DEAL_TYPE_INTEREST:
         str="interest rate";
         break;
      case DEAL_TYPE_BUY_CANCELED:
         str="canceled buy";
         break;
      case DEAL_TYPE_SELL_CANCELED:
         str="canceled sell";
         break;
      default:
         str="unknown deal type "+(string)action;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the deal direction to text                              |
//+------------------------------------------------------------------+
string CDealInfo::FormatEntry(string &str,const uint entry) const
  {
//--- see the type
   switch(entry)
     {
      case DEAL_ENTRY_IN:
         str="in";
         break;
      case DEAL_ENTRY_OUT:
         str="out";
         break;
      case DEAL_ENTRY_INOUT:
         str="in/out";
         break;
      case DEAL_ENTRY_OUT_BY:
         str="out by";
         break;
      default:
         str="unknown deal entry "+(string)entry;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the deal parameters to text                             |
//+------------------------------------------------------------------+
string CDealInfo::FormatDeal(string &str) const
  {
   string type;
   long   tmp_long;
//--- set up
   string symbol_name=this.Symbol();
   int    digits=_Digits;
   if(SymbolInfoInteger(symbol_name,SYMBOL_DIGITS,tmp_long))
      digits=(int)tmp_long;
//--- form the description of the deal
   switch(DealType())
     {
      //--- Buy-Sell
      case DEAL_TYPE_BUY:
      case DEAL_TYPE_SELL:
         str=StringFormat("#%I64u %s %s %s at %s",
                          Ticket(),
                          FormatAction(type,DealType()),
                          DoubleToString(Volume(),2),
                          symbol_name,
                          DoubleToString(Price(),digits));
         break;

      //--- balance operations
      case DEAL_TYPE_BALANCE:
      case DEAL_TYPE_CREDIT:
      case DEAL_TYPE_CHARGE:
      case DEAL_TYPE_CORRECTION:
      case DEAL_TYPE_BONUS:
      case DEAL_TYPE_COMMISSION:
      case DEAL_TYPE_COMMISSION_DAILY:
      case DEAL_TYPE_COMMISSION_MONTHLY:
      case DEAL_TYPE_COMMISSION_AGENT_DAILY:
      case DEAL_TYPE_COMMISSION_AGENT_MONTHLY:
      case DEAL_TYPE_INTEREST:
         str=StringFormat("#%I64u %s %s [%s]",
                          Ticket(),
                          FormatAction(type,DealType()),
                          DoubleToString(Profit(),2),
                          this.Comment());
         break;

      default:
         str="unknown deal type "+(string)DealType();
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Select a deal on the index                                       |
//+------------------------------------------------------------------+
bool CDealInfo::SelectByIndex(const int index)
  {
   ulong ticket=HistoryDealGetTicket(index);
   if(ticket==0)
      return(false);
   Ticket(ticket);
//---
   return(true);
  }
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| enumerations                                                     |
//+------------------------------------------------------------------+
enum ENUM_LOG_LEVELS
  {
   LOG_LEVEL_NO    =0,
   LOG_LEVEL_ERRORS=1,
   LOG_LEVEL_ALL   =2
  };
//+------------------------------------------------------------------+
//| Class CTrade.                                                    |
//| Appointment: Class trade operations.                             |
//|              Derives from class CObject.                         |
//+------------------------------------------------------------------+
class CTrade : public CObject
  {
protected:
   MqlTradeRequest   m_request;              // request data
   MqlTradeResult    m_result;               // result data
   MqlTradeCheckResult m_check_result;       // result check data
   bool              m_async_mode;           // trade mode
   ulong             m_magic;                // expert magic number
   ulong             m_deviation;            // deviation default
   ENUM_ORDER_TYPE_FILLING m_type_filling;
   ENUM_ACCOUNT_MARGIN_MODE m_margin_mode;
   //---
   ENUM_LOG_LEVELS   m_log_level;

public:
                     CTrade(void);
                    ~CTrade(void);
   //--- methods of access to protected data
   void              LogLevel(const ENUM_LOG_LEVELS log_level) { m_log_level=log_level; }
   void              Request(MqlTradeRequest &request) const;
   ENUM_TRADE_REQUEST_ACTIONS RequestAction(void)   const { return(m_request.action);       }
   string            RequestActionDescription(void) const;
   ulong             RequestMagic(void)             const { return(m_request.magic);        }
   ulong             RequestOrder(void)             const { return(m_request.order);        }
   ulong             RequestPosition(void)          const { return(m_request.position);     }
   ulong             RequestPositionBy(void)        const { return(m_request.position_by);  }
   string            RequestSymbol(void)            const { return(m_request.symbol);       }
   double            RequestVolume(void)            const { return(m_request.volume);       }
   double            RequestPrice(void)             const { return(m_request.price);        }
   double            RequestStopLimit(void)         const { return(m_request.stoplimit);    }
   double            RequestSL(void)                const { return(m_request.sl);           }
   double            RequestTP(void)                const { return(m_request.tp);           }
   ulong             RequestDeviation(void)         const { return(m_request.deviation);    }
   ENUM_ORDER_TYPE   RequestType(void)              const { return(m_request.type);         }
   string            RequestTypeDescription(void) const;
   ENUM_ORDER_TYPE_FILLING RequestTypeFilling(void) const { return(m_request.type_filling); }
   string            RequestTypeFillingDescription(void) const;
   ENUM_ORDER_TYPE_TIME RequestTypeTime(void)       const { return(m_request.type_time);    }
   string            RequestTypeTimeDescription(void) const;
   datetime          RequestExpiration(void)        const { return(m_request.expiration);   }
   string            RequestComment(void)           const { return(m_request.comment);      }
   //---
   void              Result(MqlTradeResult &result) const;
   uint              ResultRetcode(void)         const { return(m_result.retcode);          }
   string            ResultRetcodeDescription(void) const;
   int               ResultRetcodeExternal(void) const { return(m_result.retcode_external); }
   ulong             ResultDeal(void)            const { return(m_result.deal);             }
   ulong             ResultOrder(void)           const { return(m_result.order);            }
   double            ResultVolume(void)          const { return(m_result.volume);           }
   double            ResultPrice(void)           const { return(m_result.price);            }
   double            ResultBid(void)             const { return(m_result.bid);              }
   double            ResultAsk(void)             const { return(m_result.ask);              }
   string            ResultComment(void)         const { return(m_result.comment);          }
   //---
   void              CheckResult(MqlTradeCheckResult &check_result) const;
   uint              CheckResultRetcode(void)     const { return(m_check_result.retcode);      }
   string            CheckResultRetcodeDescription(void) const;
   double            CheckResultBalance(void)     const { return(m_check_result.balance);      }
   double            CheckResultEquity(void)      const { return(m_check_result.equity);       }
   double            CheckResultProfit(void)      const { return(m_check_result.profit);       }
   double            CheckResultMargin(void)      const { return(m_check_result.margin);       }
   double            CheckResultMarginFree(void)  const { return(m_check_result.margin_free);  }
   double            CheckResultMarginLevel(void) const { return(m_check_result.margin_level); }
   string            CheckResultComment(void)     const { return(m_check_result.comment);      }
   //--- trade methods
   void              SetAsyncMode(const bool mode)               { m_async_mode=mode;                }
   void              SetExpertMagicNumber(const ulong magic)     { m_magic=magic;                    }
   void              SetDeviationInPoints(const ulong deviation) { m_deviation=deviation;            }
   void              SetTypeFilling(const ENUM_ORDER_TYPE_FILLING filling) { m_type_filling=filling; }
   bool              SetTypeFillingBySymbol(const string symbol);
   void              SetMarginMode(void) { m_margin_mode=(ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE); }
   //--- methods for working with positions
   bool              PositionOpen(const string symbol,const ENUM_ORDER_TYPE order_type,const double volume,
                                  const double price,const double sl,const double tp,const string comment="");
   bool              PositionModify(const string symbol,const double sl,const double tp);
   bool              PositionModify(const ulong ticket,const double sl,const double tp);
   bool              PositionClose(const string symbol,const ulong deviation=ULONG_MAX);
   bool              PositionClose(const ulong ticket,const ulong deviation=ULONG_MAX);
   bool              PositionCloseBy(const ulong ticket,const ulong ticket_by);
   bool              PositionClosePartial(const string symbol,const double volume,const ulong deviation=ULONG_MAX);
   bool              PositionClosePartial(const ulong ticket,const double volume,const ulong deviation=ULONG_MAX);
   //--- methods for working with pending orders
   bool              OrderOpen(const string symbol,const ENUM_ORDER_TYPE order_type,const double volume,
                               const double limit_price,const double price,const double sl,const double tp,
                               ENUM_ORDER_TYPE_TIME type_time=ORDER_TIME_GTC,const datetime expiration=0,
                               const string comment="");
   bool              OrderModify(const ulong ticket,const double price,const double sl,const double tp,
                                 const ENUM_ORDER_TYPE_TIME type_time,const datetime expiration,const double stoplimit=0.0);
   bool              OrderDelete(const ulong ticket);
   //--- additions methods
   bool              Buy(const double volume,const string symbol=NULL,double price=0.0,const double sl=0.0,const double tp=0.0,const string comment="");
   bool              Sell(const double volume,const string symbol=NULL,double price=0.0,const double sl=0.0,const double tp=0.0,const string comment="");
   bool              BuyLimit(const double volume,const double price,const string symbol=NULL,const double sl=0.0,const double tp=0.0,
                              const ENUM_ORDER_TYPE_TIME type_time=ORDER_TIME_GTC,const datetime expiration=0,const string comment="");
   bool              BuyStop(const double volume,const double price,const string symbol=NULL,const double sl=0.0,const double tp=0.0,
                             const ENUM_ORDER_TYPE_TIME type_time=ORDER_TIME_GTC,const datetime expiration=0,const string comment="");
   bool              SellLimit(const double volume,const double price,const string symbol=NULL,const double sl=0.0,const double tp=0.0,
                               const ENUM_ORDER_TYPE_TIME type_time=ORDER_TIME_GTC,const datetime expiration=0,const string comment="");
   bool              SellStop(const double volume,const double price,const string symbol=NULL,const double sl=0.0,const double tp=0.0,
                              const ENUM_ORDER_TYPE_TIME type_time=ORDER_TIME_GTC,const datetime expiration=0,const string comment="");
   //--- method check
   virtual double    CheckVolume(const string symbol,double volume,double price,ENUM_ORDER_TYPE order_type);
   virtual bool      OrderCheck(const MqlTradeRequest &request,MqlTradeCheckResult &check_result);
   virtual bool      OrderSend(const MqlTradeRequest &request,MqlTradeResult &result);
   //--- info methods
   void              PrintRequest(void) const;
   void              PrintResult(void) const;
   //--- positions
   string            FormatPositionType(string &str,const uint type) const;
   //--- orders
   string            FormatOrderType(string &str,const uint type) const;
   string            FormatOrderStatus(string &str,const uint status) const;
   string            FormatOrderTypeFilling(string &str,const uint type) const;
   string            FormatOrderTypeTime(string &str,const uint type) const;
   string            FormatOrderPrice(string &str,const double price_order,const double price_trigger,const uint digits) const;
   //--- trade request
   string            FormatRequest(string &str,const MqlTradeRequest &request) const;
   string            FormatRequestResult(string &str,const MqlTradeRequest &request,const MqlTradeResult &result) const;

protected:
   bool              FillingCheck(const string symbol);
   bool              ExpirationCheck(const string symbol);
   bool              OrderTypeCheck(const string symbol);
   void              ClearStructures(void);
   bool              IsStopped(const string function);
   bool              IsHedging(void) const { return(m_margin_mode==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING); }
   //--- position select depending on netting or hedging
   bool              SelectPosition(const string symbol);
  };
//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CTrade::CTrade(void) : m_async_mode(false),
                       m_magic(0),
                       m_deviation(10),
                       m_type_filling(ORDER_FILLING_FOK),
                       m_log_level(LOG_LEVEL_ERRORS)
  {
   SetMarginMode();
//--- initialize protected data
   ClearStructures();
//--- check programm mode
   if(MQLInfoInteger(ENUM_MQL_INFO_INTEGER::MQL_TESTER))
      m_log_level=LOG_LEVEL_ALL;
   if(MQLInfoInteger(ENUM_MQL_INFO_INTEGER::MQL_OPTIMIZATION))
      m_log_level=LOG_LEVEL_NO;
  }
//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CTrade::~CTrade(void)
  {
  }
//+------------------------------------------------------------------+
//| Get the request structure                                        |
//+------------------------------------------------------------------+
void CTrade::Request(MqlTradeRequest &request) const
  {
   request.action      =m_request.action;
   request.magic       =m_request.magic;
   request.order       =m_request.order;
   request.symbol      =m_request.symbol;
   request.volume      =m_request.volume;
   request.price       =m_request.price;
   request.stoplimit   =m_request.stoplimit;
   request.sl          =m_request.sl;
   request.tp          =m_request.tp;
   request.deviation   =m_request.deviation;
   request.type        =m_request.type;
   request.type_filling=m_request.type_filling;
   request.type_time   =m_request.type_time;
   request.expiration  =m_request.expiration;
   request.comment     =m_request.comment;
   request.position    =m_request.position;
   request.position_by =m_request.position_by;
  }
//+------------------------------------------------------------------+
//| Get the trade action as string                                   |
//+------------------------------------------------------------------+
string CTrade::RequestActionDescription(void) const
  {
   string str;
//---
   FormatRequest(str,m_request);
//---
   return(str);
  }
//+------------------------------------------------------------------+
//| Get the order type as string                                     |
//+------------------------------------------------------------------+
string CTrade::RequestTypeDescription(void) const
  {
   string str;
//---
   FormatOrderType(str,(uint)m_request.order);
//---
   return(str);
  }
//+------------------------------------------------------------------+
//| Get the order type filling as string                             |
//+------------------------------------------------------------------+
string CTrade::RequestTypeFillingDescription(void) const
  {
   string str;
//---
   FormatOrderTypeFilling(str,m_request.type_filling);
//---
   return(str);
  }
//+------------------------------------------------------------------+
//| Get the order type time as string                                |
//+------------------------------------------------------------------+
string CTrade::RequestTypeTimeDescription(void) const
  {
   string str;
//---
   FormatOrderTypeTime(str,m_request.type_time);
//---
   return(str);
  }
//+------------------------------------------------------------------+
//| Get the result structure                                         |
//+------------------------------------------------------------------+
void CTrade::Result(MqlTradeResult &result) const
  {
   result.retcode   =m_result.retcode;
   result.deal      =m_result.deal;
   result.order     =m_result.order;
   result.volume    =m_result.volume;
   result.price     =m_result.price;
   result.bid       =m_result.bid;
   result.ask       =m_result.ask;
   result.comment   =m_result.comment;
   result.request_id=m_result.request_id;
   result.retcode_external=m_result.retcode_external;
  }
//+------------------------------------------------------------------+
//| Get the retcode value as string                                  |
//+------------------------------------------------------------------+
string CTrade::ResultRetcodeDescription(void) const
  {
   string str;
//---
   FormatRequestResult(str,m_request,m_result);
//---
   return(str);
  }
//+------------------------------------------------------------------+
//| Get the check result structure                                   |
//+------------------------------------------------------------------+
void CTrade::CheckResult(MqlTradeCheckResult &check_result) const
  {
//--- copy structure
   check_result.retcode     =m_check_result.retcode;
   check_result.balance     =m_check_result.balance;
   check_result.equity      =m_check_result.equity;
   check_result.profit      =m_check_result.profit;
   check_result.margin      =m_check_result.margin;
   check_result.margin_free =m_check_result.margin_free;
   check_result.margin_level=m_check_result.margin_level;
   check_result.comment     =m_check_result.comment;
  }
//+------------------------------------------------------------------+
//| Get the check retcode value as string                            |
//+------------------------------------------------------------------+
string CTrade::CheckResultRetcodeDescription(void) const
  {
   string         str;
   MqlTradeResult result;
//---
   result.retcode=m_check_result.retcode;
   FormatRequestResult(str,m_request,result);
//---
   return(str);
  }
//+------------------------------------------------------------------+
//| Open position                                                    |
//+------------------------------------------------------------------+
bool CTrade::PositionOpen(const string symbol,const ENUM_ORDER_TYPE order_type,const double volume,
                          const double price,const double sl,const double tp,const string comment)
  {
//--- check stopped
   if(IsStopped(__FUNCTION__))
      return(false);
//--- clean
   ClearStructures();
//--- check
   if(order_type!=ORDER_TYPE_BUY && order_type!=ORDER_TYPE_SELL)
     {
      m_result.retcode=TRADE_RETCODE_INVALID;
      m_result.comment="Invalid order type";
      return(false);
     }
//--- setting request
   m_request.action   =TRADE_ACTION_DEAL;
   m_request.symbol   =symbol;
   m_request.magic    =m_magic;
   m_request.volume   =volume;
   m_request.type     =order_type;
   m_request.price    =price;
   m_request.sl       =sl;
   m_request.tp       =tp;
   m_request.deviation=m_deviation;
//--- check order type
   if(!OrderTypeCheck(symbol))
      return(false);
//--- check filling
   if(!FillingCheck(symbol))
      return(false);
   m_request.comment=comment;
//--- action and return the result
   return(OrderSend(m_request,m_result));
  }
//+------------------------------------------------------------------+
//| Modify specified opened position                                 |
//+------------------------------------------------------------------+
bool CTrade::PositionModify(const string symbol,const double sl,const double tp)
  {
//--- check stopped
   if(IsStopped(__FUNCTION__))
      return(false);
//--- check position existence
   if(!SelectPosition(symbol))
      return(false);
//--- clean
   ClearStructures();
//--- setting request
   m_request.action  =TRADE_ACTION_SLTP;
   m_request.symbol  =symbol;
   m_request.magic   =m_magic;
   m_request.sl      =sl;
   m_request.tp      =tp;
   m_request.position=PositionGetInteger(POSITION_TICKET);
//--- action and return the result
   return(OrderSend(m_request,m_result));
  }
//+------------------------------------------------------------------+
//| Modify specified opened position                                 |
//+------------------------------------------------------------------+
bool CTrade::PositionModify(const ulong ticket,const double sl,const double tp)
  {
//--- check stopped
   if(IsStopped(__FUNCTION__))
      return(false);
//--- check position existence
   if(!PositionSelectByTicket(ticket))
      return(false);
//--- clean
   ClearStructures();
//--- setting request
   m_request.action  =TRADE_ACTION_SLTP;
   m_request.position=ticket;
   m_request.symbol  =PositionGetString(POSITION_SYMBOL);
   m_request.magic   =m_magic;
   m_request.sl      =sl;
   m_request.tp      =tp;
//--- action and return the result
   return(OrderSend(m_request,m_result));
  }
//+------------------------------------------------------------------+
//| Close specified opened position                                  |
//+------------------------------------------------------------------+
bool CTrade::PositionClose(const string symbol,const ulong deviation)
  {
   bool partial_close=false;
   int  retry_count  =10;
   uint retcode      =TRADE_RETCODE_REJECT;
//--- check stopped
   if(IsStopped(__FUNCTION__))
      return(false);
//--- clean
   ClearStructures();
//--- check filling
   if(!FillingCheck(symbol))
      return(false);
   do
     {
      //--- check
      if(SelectPosition(symbol))
        {
         if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)
           {
            //--- prepare request for close BUY position
            m_request.type =ORDER_TYPE_SELL;
            m_request.price=SymbolInfoDouble(symbol,SYMBOL_BID);
           }
         else
           {
            //--- prepare request for close SELL position
            m_request.type =ORDER_TYPE_BUY;
            m_request.price=SymbolInfoDouble(symbol,SYMBOL_ASK);
           }
        }
      else
        {
         //--- position not found
         m_result.retcode=retcode;
         return(false);
        }
      //--- setting request
      m_request.action   =TRADE_ACTION_DEAL;
      m_request.symbol   =symbol;
      m_request.volume   =PositionGetDouble(POSITION_VOLUME);
      m_request.magic    =m_magic;
      m_request.deviation=(deviation==ULONG_MAX) ? m_deviation : deviation;
      m_request.position =PositionGetInteger(POSITION_TICKET);
      //--- check volume
      double max_volume=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
      if(m_request.volume>max_volume)
        {
         m_request.volume=max_volume;
         partial_close=true;
        }
      else
         partial_close=false;
      //--- hedging? just send order
      if(IsHedging())
         return(OrderSend(m_request,m_result));
      //--- order send
      if(!OrderSend(m_request,m_result))
        {
         if(--retry_count!=0)
            continue;
         if(retcode==TRADE_RETCODE_DONE_PARTIAL)
            m_result.retcode=retcode;
         return(false);
        }
      //--- WARNING. If position volume exceeds the maximum volume allowed for deal,
      //--- and when the asynchronous trade mode is on, for safety reasons, position is closed not completely,
      //--- but partially. It is decreased by the maximum volume allowed for deal.
      if(m_async_mode)
         break;
      retcode=TRADE_RETCODE_DONE_PARTIAL;
      if(partial_close)
         Sleep(1000);
     }
   while(partial_close);
//--- succeed
   return(true);
  }
//+------------------------------------------------------------------+
//| Close specified opened position                                  |
//+------------------------------------------------------------------+
bool CTrade::PositionClose(const ulong ticket,const ulong deviation)
  {
//--- check stopped
   if(IsStopped(__FUNCTION__))
      return(false);
//--- check position existence
   if(!PositionSelectByTicket(ticket))
      return(false);
   string symbol=PositionGetString(POSITION_SYMBOL);
//--- clean
   ClearStructures();
//--- check filling
   if(!FillingCheck(symbol))
      return(false);
//--- check
   if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)
     {
      //--- prepare request for close BUY position
      m_request.type =ORDER_TYPE_SELL;
      m_request.price=SymbolInfoDouble(symbol,SYMBOL_BID);
     }
   else
     {
      //--- prepare request for close SELL position
      m_request.type =ORDER_TYPE_BUY;
      m_request.price=SymbolInfoDouble(symbol,SYMBOL_ASK);
     }
//--- setting request
   m_request.action   =TRADE_ACTION_DEAL;
   m_request.position =ticket;
   m_request.symbol   =symbol;
   m_request.volume   =PositionGetDouble(POSITION_VOLUME);
   m_request.magic    =m_magic;
   m_request.deviation=(deviation==ULONG_MAX) ? m_deviation : deviation;
//--- close position
   return(OrderSend(m_request,m_result));
  }
//+------------------------------------------------------------------+
//| Close one position by other                                      |
//+------------------------------------------------------------------+
bool CTrade::PositionCloseBy(const ulong ticket,const ulong ticket_by)
  {
//--- check stopped
   if(IsStopped(__FUNCTION__))
      return(false);
//--- check hedging mode
   if(!IsHedging())
      return(false);
//--- check position existence
   if(!PositionSelectByTicket(ticket))
      return(false);
   string symbol=PositionGetString(POSITION_SYMBOL);
   ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   if(!PositionSelectByTicket(ticket_by))
      return(false);
   string symbol_by=PositionGetString(POSITION_SYMBOL);
   ENUM_POSITION_TYPE type_by=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
//--- check positions
   if(type==type_by)
      return(false);
   if(symbol!=symbol_by)
      return(false);
//--- clean
   ClearStructures();
//--- check filling
   if(!FillingCheck(symbol))
      return(false);
//--- setting request
   m_request.action     =TRADE_ACTION_CLOSE_BY;
   m_request.position   =ticket;
   m_request.position_by=ticket_by;
   m_request.magic      =m_magic;
//--- close position
   return(OrderSend(m_request,m_result));
  }
//+------------------------------------------------------------------+
//| Partial close specified opened position (for hedging mode only)  |
//+------------------------------------------------------------------+
bool CTrade::PositionClosePartial(const string symbol,const double volume,const ulong deviation)
  {
   uint retcode=TRADE_RETCODE_REJECT;
//--- check stopped
   if(IsStopped(__FUNCTION__))
      return(false);
//--- for hedging mode only
   if(!IsHedging())
      return(false);
//--- clean
   ClearStructures();
//--- check filling
   if(!FillingCheck(symbol))
      return(false);
//--- check
   if(SelectPosition(symbol))
     {
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)
        {
         //--- prepare request for close BUY position
         m_request.type =ORDER_TYPE_SELL;
         m_request.price=SymbolInfoDouble(symbol,SYMBOL_BID);
        }
      else
        {
         //--- prepare request for close SELL position
         m_request.type =ORDER_TYPE_BUY;
         m_request.price=SymbolInfoDouble(symbol,SYMBOL_ASK);
        }
     }
   else
     {
      //--- position not found
      m_result.retcode=retcode;
      return(false);
     }
//--- check volume
   double position_volume=PositionGetDouble(POSITION_VOLUME);
   if(position_volume>volume)
      position_volume=volume;
//--- setting request
   m_request.action   =TRADE_ACTION_DEAL;
   m_request.symbol   =symbol;
   m_request.volume   =position_volume;
   m_request.magic    =m_magic;
   m_request.deviation=(deviation==ULONG_MAX) ? m_deviation : deviation;
   m_request.position =PositionGetInteger(POSITION_TICKET);
//--- hedging? just send order
   return(OrderSend(m_request,m_result));
  }
//+------------------------------------------------------------------+
//| Partial close specified opened position (for hedging mode only)  |
//+------------------------------------------------------------------+
bool CTrade::PositionClosePartial(const ulong ticket,const double volume,const ulong deviation)
  {
//--- check stopped
   if(IsStopped(__FUNCTION__))
      return(false);
//--- for hedging mode only
   if(!IsHedging())
      return(false);
//--- check position existence
   if(!PositionSelectByTicket(ticket))
      return(false);
   string symbol=PositionGetString(POSITION_SYMBOL);
//--- clean
   ClearStructures();
//--- check filling
   if(!FillingCheck(symbol))
      return(false);
//--- check
   if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)
     {
      //--- prepare request for close BUY position
      m_request.type =ORDER_TYPE_SELL;
      m_request.price=SymbolInfoDouble(symbol,SYMBOL_BID);
     }
   else
     {
      //--- prepare request for close SELL position
      m_request.type =ORDER_TYPE_BUY;
      m_request.price=SymbolInfoDouble(symbol,SYMBOL_ASK);
     }
//--- check volume
   double position_volume=PositionGetDouble(POSITION_VOLUME);
   if(position_volume>volume)
      position_volume=volume;
//--- setting request
   m_request.action   =TRADE_ACTION_DEAL;
   m_request.position =ticket;
   m_request.symbol   =symbol;
   m_request.volume   =position_volume;
   m_request.magic    =m_magic;
   m_request.deviation=(deviation==ULONG_MAX) ? m_deviation : deviation;
//--- close position
   return(OrderSend(m_request,m_result));
  }
//+------------------------------------------------------------------+
//| Installation pending order                                       |
//+------------------------------------------------------------------+
bool CTrade::OrderOpen(const string symbol,const ENUM_ORDER_TYPE order_type,const double volume,const double limit_price,
                       const double price,const double sl,const double tp,
                       ENUM_ORDER_TYPE_TIME type_time,const datetime expiration,const string comment)
  {
//--- check stopped
   if(IsStopped(__FUNCTION__))
      return(false);
//--- clean
   ClearStructures();
//--- check filling
   if(!FillingCheck(symbol))
      return(false);
//--- check order type
   if(order_type==ORDER_TYPE_BUY || order_type==ORDER_TYPE_SELL)
     {
      m_result.retcode=TRADE_RETCODE_INVALID;
      m_result.comment="Invalid order type";
      return(false);
     }
//--- check order expiration
   if(type_time==ORDER_TIME_GTC && expiration==0)
     {
      int exp=(int)SymbolInfoInteger(symbol,SYMBOL_EXPIRATION_MODE);
      if((exp&SYMBOL_EXPIRATION_GTC)!=SYMBOL_EXPIRATION_GTC)
        {
         //--- if you place order for an unlimited time and if placing of such orders is prohibited
         //--- try to place order with expiration at the end of the day
         if((exp&SYMBOL_EXPIRATION_DAY)!=SYMBOL_EXPIRATION_DAY)
           {
            //--- if even this is not possible - error
            Print(__FUNCTION__,": Error: Unable to place order without explicitly specified expiration time");
            m_result.retcode=TRADE_RETCODE_INVALID_EXPIRATION;
            m_result.comment="Invalid expiration type";
            return(false);
           }
         type_time=ORDER_TIME_DAY;
        }
     }
//--- setting request
   m_request.action      =TRADE_ACTION_PENDING;
   m_request.symbol      =symbol;
   m_request.magic       =m_magic;
   m_request.volume      =volume;
   m_request.type        =order_type;
   m_request.stoplimit   =limit_price;
   m_request.price       =price;
   m_request.sl          =sl;
   m_request.tp          =tp;
   m_request.type_time   =type_time;
   m_request.expiration  =expiration;
//--- check order type
   if(!OrderTypeCheck(symbol))
      return(false);
//--- check filling
   if(!FillingCheck(symbol))
     {
      m_result.retcode=TRADE_RETCODE_INVALID_FILL;
      Print(__FUNCTION__+": Invalid filling type");
      return(false);
     }
//--- check expiration
   if(!ExpirationCheck(symbol))
     {
      m_result.retcode=TRADE_RETCODE_INVALID_EXPIRATION;
      Print(__FUNCTION__+": Invalid expiration type");
      return(false);
     }
   m_request.comment=comment;
//--- action and return the result
   return(OrderSend(m_request,m_result));
  }
//+------------------------------------------------------------------+
//| Modify specified pending order                                   |
//+------------------------------------------------------------------+
bool CTrade::OrderModify(const ulong ticket,const double price,const double sl,const double tp,
                         const ENUM_ORDER_TYPE_TIME type_time,const datetime expiration,const double stoplimit)
  {
//--- check stopped
   if(IsStopped(__FUNCTION__))
      return(false);
//--- check order existence
   if(!OrderSelect(ticket))
      return(false);
//--- clean
   ClearStructures();
//--- setting request
   m_request.symbol      =OrderGetString(ORDER_SYMBOL);
   m_request.action      =TRADE_ACTION_MODIFY;
   m_request.magic       =m_magic;
   m_request.order       =ticket;
   m_request.price       =price;
   m_request.stoplimit   =stoplimit;
   m_request.sl          =sl;
   m_request.tp          =tp;
   m_request.type_time   =type_time;
   m_request.expiration  =expiration;
//--- action and return the result
   return(OrderSend(m_request,m_result));
  }
//+------------------------------------------------------------------+
//| Delete specified pending order                                   |
//+------------------------------------------------------------------+
bool CTrade::OrderDelete(const ulong ticket)
  {
//--- check stopped
   if(IsStopped(__FUNCTION__))
      return(false);
//--- clean
   ClearStructures();
//--- setting request
   m_request.action    =TRADE_ACTION_REMOVE;
   m_request.magic     =m_magic;
   m_request.order     =ticket;
//--- action and return the result
   return(OrderSend(m_request,m_result));
  }
//+------------------------------------------------------------------+
//| Output full information of request to log                        |
//+------------------------------------------------------------------+
void CTrade::PrintRequest(void) const
  {
   if(m_log_level<LOG_LEVEL_ALL)
      return;
//---
   string str;
   PrintFormat("%s",FormatRequest(str,m_request));
  }
//+------------------------------------------------------------------+
//| Output full information of result to log                         |
//+------------------------------------------------------------------+
void CTrade::PrintResult(void) const
  {
   if(m_log_level<LOG_LEVEL_ALL)
      return;
//---
   string str;
   PrintFormat("%s",FormatRequestResult(str,m_request,m_result));
  }
//+------------------------------------------------------------------+
//| Clear structures m_request,m_result and m_check_result           |
//+------------------------------------------------------------------+
void CTrade::ClearStructures(void)
  {
   ZeroMemory(m_request);
   ZeroMemory(m_result);
   ZeroMemory(m_check_result);
  }
//+------------------------------------------------------------------+
//| Checks forced shutdown of MQL5-program                           |
//+------------------------------------------------------------------+
bool CTrade::IsStopped(const string function)
  {
   if(!::IsStopped())
      return(false);
//--- MQL5 program is stopped
   PrintFormat("%s: MQL5 program is stopped. Trading is disabled",function);
   m_result.retcode=TRADE_RETCODE_CLIENT_DISABLES_AT;
   return(true);
  }
//+------------------------------------------------------------------+
//| Buy operation                                                    |
//+------------------------------------------------------------------+
bool CTrade::Buy(const double volume,const string symbol=NULL,double price=0.0,const double sl=0.0,const double tp=0.0,const string comment="")
  {
//--- check volume
   if(volume<=0.0)
     {
      m_result.retcode=TRADE_RETCODE_INVALID_VOLUME;
      return(false);
     }
//--- check symbol
   string symbol_name=(symbol==NULL) ? _Symbol : symbol;
//--- check price
   if(price==0.0)
      price=SymbolInfoDouble(symbol_name,SYMBOL_ASK);
//---
   return(PositionOpen(symbol_name,ORDER_TYPE_BUY,volume,price,sl,tp,comment));
  }
//+------------------------------------------------------------------+
//| Sell operation                                                   |
//+------------------------------------------------------------------+
bool CTrade::Sell(const double volume,const string symbol=NULL,double price=0.0,const double sl=0.0,const double tp=0.0,const string comment="")
  {
//--- check volume
   if(volume<=0.0)
     {
      m_result.retcode=TRADE_RETCODE_INVALID_VOLUME;
      return(false);
     }
//--- check symbol
   string symbol_name=(symbol==NULL) ? _Symbol : symbol;
//--- check price
   if(price==0.0)
      price=SymbolInfoDouble(symbol_name,SYMBOL_BID);
//---
   return(PositionOpen(symbol_name,ORDER_TYPE_SELL,volume,price,sl,tp,comment));
  }
//+------------------------------------------------------------------+
//| Send BUY_LIMIT order                                             |
//+------------------------------------------------------------------+
bool CTrade::BuyLimit(const double volume,const double price,const string symbol=NULL,const double sl=0.0,const double tp=0.0,
                      const ENUM_ORDER_TYPE_TIME type_time=ORDER_TIME_GTC,const datetime expiration=0,const string comment="")
  {
   string symbol_name;
//--- check volume
   if(volume<=0.0)
     {
      m_result.retcode=TRADE_RETCODE_INVALID_VOLUME;
      return(false);
     }
//--- check symbol
   symbol_name=(symbol==NULL)?Symbol():symbol;
//--- send "BUY_LIMIT" order
   return(OrderOpen(symbol_name,ORDER_TYPE_BUY_LIMIT,volume,0.0,price,sl,tp,type_time,expiration,comment));
  }
//+------------------------------------------------------------------+
//| Send BUY_STOP order                                              |
//+------------------------------------------------------------------+
bool CTrade::BuyStop(const double volume,const double price,const string symbol=NULL,const double sl=0.0,const double tp=0.0,
                     const ENUM_ORDER_TYPE_TIME type_time=ORDER_TIME_GTC,const datetime expiration=0,const string comment="")
  {
   string symbol_name;
//--- check volume
   if(volume<=0.0)
     {
      m_result.retcode=TRADE_RETCODE_INVALID_VOLUME;
      return(false);
     }
//--- check symbol
   symbol_name=(symbol==NULL)?Symbol():symbol;
//--- send "BUY_STOP" order
   return(OrderOpen(symbol_name,ORDER_TYPE_BUY_STOP,volume,0.0,price,sl,tp,type_time,expiration,comment));
  }
//+------------------------------------------------------------------+
//| Send SELL_LIMIT order                                            |
//+------------------------------------------------------------------+
bool CTrade::SellLimit(const double volume,const double price,const string symbol=NULL,const double sl=0.0,const double tp=0.0,
                       const ENUM_ORDER_TYPE_TIME type_time=ORDER_TIME_GTC,const datetime expiration=0,const string comment="")
  {
   string symbol_name;
//--- check volume
   if(volume<=0.0)
     {
      m_result.retcode=TRADE_RETCODE_INVALID_VOLUME;
      return(false);
     }
//--- check symbol
   symbol_name=(symbol==NULL)?Symbol():symbol;
//--- send "SELL_LIMIT" order
   return(OrderOpen(symbol_name,ORDER_TYPE_SELL_LIMIT,volume,0.0,price,sl,tp,type_time,expiration,comment));
  }
//+------------------------------------------------------------------+
//| Send SELL_STOP order                                             |
//+------------------------------------------------------------------+
bool CTrade::SellStop(const double volume,const double price,const string symbol=NULL,const double sl=0.0,const double tp=0.0,
                      const ENUM_ORDER_TYPE_TIME type_time=ORDER_TIME_GTC,const datetime expiration=0,const string comment="")
  {
   string symbol_name;
//--- check volume
   if(volume<=0.0)
     {
      m_result.retcode=TRADE_RETCODE_INVALID_VOLUME;
      return(false);
     }
//--- check symbol
   symbol_name=(symbol==NULL)?Symbol():symbol;
//--- send "SELL_STOP" order
   return(OrderOpen(symbol_name,ORDER_TYPE_SELL_STOP,volume,0.0,price,sl,tp,type_time,expiration,comment));
  }
//+------------------------------------------------------------------+
//| Converts the position type to text                               |
//+------------------------------------------------------------------+
string CTrade::FormatPositionType(string &str,const uint type) const
  {
//--- see the type
   switch(type)
     {
      case POSITION_TYPE_BUY:
         str="buy";
         break;
      case POSITION_TYPE_SELL:
         str="sell";
         break;
      default:
         str="unknown position type "+(string)type;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the order type to text                                  |
//+------------------------------------------------------------------+
string CTrade::FormatOrderType(string &str,const uint type) const
  {
//--- see the type
   switch(type)
     {
      case ORDER_TYPE_BUY:
         str="buy";
         break;
      case ORDER_TYPE_SELL:
         str="sell";
         break;
      case ORDER_TYPE_BUY_LIMIT:
         str="buy limit";
         break;
      case ORDER_TYPE_SELL_LIMIT:
         str="sell limit";
         break;
      case ORDER_TYPE_BUY_STOP:
         str="buy stop";
         break;
      case ORDER_TYPE_SELL_STOP:
         str="sell stop";
         break;
      case ORDER_TYPE_BUY_STOP_LIMIT:
         str="buy stop limit";
         break;
      case ORDER_TYPE_SELL_STOP_LIMIT:
         str="sell stop limit";
         break;
      default:
         str="unknown order type "+(string)type;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the order filling type to text                          |
//+------------------------------------------------------------------+
string CTrade::FormatOrderTypeFilling(string &str,const uint type) const
  {
//--- see the type
   switch(type)
     {
      case ORDER_FILLING_RETURN:
         str="return remainder";
         break;
      case ORDER_FILLING_IOC:
         str="cancel remainder";
         break;
      case ORDER_FILLING_FOK:
         str="fill or kill";
         break;
      default:
         str="unknown type filling "+(string)type;
         break;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the type of order by expiration to text                 |
//+------------------------------------------------------------------+
string CTrade::FormatOrderTypeTime(string &str,const uint type) const
  {
//--- see the type
   switch(type)
     {
      case ORDER_TIME_GTC:
         str="gtc";
         break;
      case ORDER_TIME_DAY:
         str="day";
         break;
      case ORDER_TIME_SPECIFIED:
         str="specified";
         break;
      case ORDER_TIME_SPECIFIED_DAY:
         str="specified day";
         break;
      default:
         str="unknown type time "+(string)type;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the order prices to text                                |
//+------------------------------------------------------------------+
string CTrade::FormatOrderPrice(string &str,const double price_order,const double price_trigger,const uint digits) const
  {
   string price,trigger;
//--- Is there its trigger price?
   if(price_trigger)
     {
      price  =DoubleToString(price_order,digits);
      trigger=DoubleToString(price_trigger,digits);
      str    =StringFormat("%s (%s)",price,trigger);
     }
   else
      str=DoubleToString(price_order,digits);
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the parameters of a trade request to text               |
//+------------------------------------------------------------------+
string CTrade::FormatRequest(string &str,const MqlTradeRequest &request) const
  {
   string type,price,price_new;
   string tmp_string;
   long   tmp_long;
//--- clean
   str="";
//--- set up
   string symbol_name=(request.symbol==NULL) ? _Symbol : request.symbol;
   int    digits=_Digits;
   ENUM_SYMBOL_TRADE_EXECUTION trade_execution=0;
   if(SymbolInfoInteger(symbol_name,SYMBOL_DIGITS,tmp_long))
      digits=(int)tmp_long;
   if(SymbolInfoInteger(symbol_name,SYMBOL_TRADE_EXEMODE,tmp_long))
      trade_execution=(ENUM_SYMBOL_TRADE_EXECUTION)tmp_long;
//--- see what is wanted
   switch(request.action)
     {
      //--- instant execution of a deal
      case TRADE_ACTION_DEAL:
         switch(trade_execution)
           {
            //--- request execution
            case SYMBOL_TRADE_EXECUTION_REQUEST:
               if(IsHedging() && request.position!=0)
                  str=StringFormat("request %s %s position #%I64u %s at %s",
                                   FormatOrderType(type,request.type),
                                   DoubleToString(request.volume,2),
                                   request.position,
                                   request.symbol,
                                   DoubleToString(request.price,digits));
               else
                  str=StringFormat("request %s %s %s at %s",
                                   FormatOrderType(type,request.type),
                                   DoubleToString(request.volume,2),
                                   request.symbol,
                                   DoubleToString(request.price,digits));
               //--- Is there SL or TP?
               if(request.sl!=0.0)
                 {
                  tmp_string=StringFormat(" sl: %s",DoubleToString(request.sl,digits));
                  str+=tmp_string;
                 }
               if(request.tp!=0.0)
                 {
                  tmp_string=StringFormat(" tp: %s",DoubleToString(request.tp,digits));
                  str+=tmp_string;
                 }
               break;
            //--- instant execution
            case SYMBOL_TRADE_EXECUTION_INSTANT:
               if(IsHedging() && request.position!=0)
                  str=StringFormat("instant %s %s position #%I64u %s at %s",
                                   FormatOrderType(type,request.type),
                                   DoubleToString(request.volume,2),
                                   request.position,
                                   request.symbol,
                                   DoubleToString(request.price,digits));
               else
                  str=StringFormat("instant %s %s %s at %s",
                                   FormatOrderType(type,request.type),
                                   DoubleToString(request.volume,2),
                                   request.symbol,
                                   DoubleToString(request.price,digits));
               //--- Is there SL or TP?
               if(request.sl!=0.0)
                 {
                  tmp_string=StringFormat(" sl: %s",DoubleToString(request.sl,digits));
                  str+=tmp_string;
                 }
               if(request.tp!=0.0)
                 {
                  tmp_string=StringFormat(" tp: %s",DoubleToString(request.tp,digits));
                  str+=tmp_string;
                 }
               break;
            //--- market execution
            case SYMBOL_TRADE_EXECUTION_MARKET:
               if(IsHedging() && request.position!=0)
                  str=StringFormat("market %s %s position #%I64u %s",
                                   FormatOrderType(type,request.type),
                                   DoubleToString(request.volume,2),
                                   request.position,
                                   request.symbol);
               else
                  str=StringFormat("market %s %s %s",
                                   FormatOrderType(type,request.type),
                                   DoubleToString(request.volume,2),
                                   request.symbol);
               //--- Is there SL or TP?
               if(request.sl!=0.0)
                 {
                  tmp_string=StringFormat(" sl: %s",DoubleToString(request.sl,digits));
                  str+=tmp_string;
                 }
               if(request.tp!=0.0)
                 {
                  tmp_string=StringFormat(" tp: %s",DoubleToString(request.tp,digits));
                  str+=tmp_string;
                 }
               break;
            //--- exchange execution
            case SYMBOL_TRADE_EXECUTION_EXCHANGE:
               if(IsHedging() && request.position!=0)
                  str=StringFormat("exchange %s %s position #%I64u %s",
                                   FormatOrderType(type,request.type),
                                   DoubleToString(request.volume,2),
                                   request.position,
                                   request.symbol);
               else
                  str=StringFormat("exchange %s %s %s",
                                   FormatOrderType(type,request.type),
                                   DoubleToString(request.volume,2),
                                   request.symbol);
               //--- Is there SL or TP?
               if(request.sl!=0.0)
                 {
                  tmp_string=StringFormat(" sl: %s",DoubleToString(request.sl,digits));
                  str+=tmp_string;
                 }
               if(request.tp!=0.0)
                 {
                  tmp_string=StringFormat(" tp: %s",DoubleToString(request.tp,digits));
                  str+=tmp_string;
                 }
               break;
           }
         //--- end of TRADE_ACTION_DEAL processing
         break;

      //--- setting a pending order
      case TRADE_ACTION_PENDING:
         str=StringFormat("%s %s %s at %s",
                          FormatOrderType(type,request.type),
                          DoubleToString(request.volume,2),
                          request.symbol,
                          FormatOrderPrice(price,request.price,request.stoplimit,digits));
         //--- Is there SL or TP?
         if(request.sl!=0.0)
           {
            tmp_string=StringFormat(" sl: %s",DoubleToString(request.sl,digits));
            str+=tmp_string;
           }
         if(request.tp!=0.0)
           {
            tmp_string=StringFormat(" tp: %s",DoubleToString(request.tp,digits));
            str+=tmp_string;
           }
         break;

      //--- Setting SL/TP
      case TRADE_ACTION_SLTP:
         if(IsHedging() && request.position!=0)
            str=StringFormat("modify position #%I64u %s (sl: %s, tp: %s)",
                             request.position,
                             request.symbol,
                             DoubleToString(request.sl,digits),
                             DoubleToString(request.tp,digits));
         else
            str=StringFormat("modify %s (sl: %s, tp: %s)",
                             request.symbol,
                             DoubleToString(request.sl,digits),
                             DoubleToString(request.tp,digits));
         break;

      //--- modifying a pending order
      case TRADE_ACTION_MODIFY:
         str=StringFormat("modify #%I64u at %s (sl: %s tp: %s)",
                          request.order,
                          FormatOrderPrice(price_new,request.price,request.stoplimit,digits),
                          DoubleToString(request.sl,digits),
                          DoubleToString(request.tp,digits));
         break;

      //--- deleting a pending order
      case TRADE_ACTION_REMOVE:
         str=StringFormat("cancel #%I64u",request.order);
         break;

      //--- close by
      case TRADE_ACTION_CLOSE_BY:
         if(IsHedging() && request.position!=0)
            str=StringFormat("close position #%I64u by #%I64u",request.position,request.position_by);
         else
            str=StringFormat("wrong action close by (#%I64u by #%I64u)",request.position,request.position_by);
         break;

      default:
         str="unknown action "+(string)request.action;
         break;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the result of a request to text                         |
//+------------------------------------------------------------------+
string CTrade::FormatRequestResult(string &str,const MqlTradeRequest &request,const MqlTradeResult &result) const
  {
//--- set up
   string symbol_name=(request.symbol==NULL) ? _Symbol : request.symbol;
   int    digits=_Digits;
   long   tmp_long;
   ENUM_SYMBOL_TRADE_EXECUTION trade_execution=0;
   if(SymbolInfoInteger(symbol_name,SYMBOL_DIGITS,tmp_long))
      digits=(int)tmp_long;
   if(SymbolInfoInteger(symbol_name,SYMBOL_TRADE_EXEMODE,tmp_long))
      trade_execution=(ENUM_SYMBOL_TRADE_EXECUTION)tmp_long;
//--- see the response code
   switch(result.retcode)
     {
      case TRADE_RETCODE_REQUOTE:
         str=StringFormat("requote (%s/%s)",
                          DoubleToString(result.bid,digits),
                          DoubleToString(result.ask,digits));
         break;

      case TRADE_RETCODE_DONE:
         if(request.action==TRADE_ACTION_DEAL &&
            (trade_execution==SYMBOL_TRADE_EXECUTION_REQUEST ||
             trade_execution==SYMBOL_TRADE_EXECUTION_INSTANT ||
             trade_execution==SYMBOL_TRADE_EXECUTION_MARKET))
            str=StringFormat("done at %s",DoubleToString(result.price,digits));
         else
            str="done";
         break;

      case TRADE_RETCODE_DONE_PARTIAL:
         if(request.action==TRADE_ACTION_DEAL &&
            (trade_execution==SYMBOL_TRADE_EXECUTION_REQUEST ||
             trade_execution==SYMBOL_TRADE_EXECUTION_INSTANT ||
             trade_execution==SYMBOL_TRADE_EXECUTION_MARKET))
            str=StringFormat("done partially %s at %s",
                             DoubleToString(result.volume,2),
                             DoubleToString(result.price,digits));
         else
            str=StringFormat("done partially %s",
                             DoubleToString(result.volume,2));
         break;

      case TRADE_RETCODE_REJECT:
         str="rejected";
         break;
      case TRADE_RETCODE_CANCEL:
         str="canceled";
         break;
      case TRADE_RETCODE_PLACED:
         str="placed";
         break;
      case TRADE_RETCODE_ERROR:
         str="common error";
         break;
      case TRADE_RETCODE_TIMEOUT:
         str="timeout";
         break;
      case TRADE_RETCODE_INVALID:
         str="invalid request";
         break;
      case TRADE_RETCODE_INVALID_VOLUME:
         str="invalid volume";
         break;
      case TRADE_RETCODE_INVALID_PRICE:
         str="invalid price";
         break;
      case TRADE_RETCODE_INVALID_STOPS:
         str="invalid stops";
         break;
      case TRADE_RETCODE_TRADE_DISABLED:
         str="trade disabled";
         break;
      case TRADE_RETCODE_MARKET_CLOSED:
         str="market closed";
         break;
      case TRADE_RETCODE_NO_MONEY:
         str="not enough money";
         break;
      case TRADE_RETCODE_PRICE_CHANGED:
         str="price changed";
         break;
      case TRADE_RETCODE_PRICE_OFF:
         str="off quotes";
         break;
      case TRADE_RETCODE_INVALID_EXPIRATION:
         str="invalid expiration";
         break;
      case TRADE_RETCODE_ORDER_CHANGED:
         str="order changed";
         break;
      case TRADE_RETCODE_TOO_MANY_REQUESTS:
         str="too many requests";
         break;
      case TRADE_RETCODE_NO_CHANGES:
         str="no changes";
         break;
      case TRADE_RETCODE_SERVER_DISABLES_AT:
         str="auto trading disabled by server";
         break;
      case TRADE_RETCODE_CLIENT_DISABLES_AT:
         str="auto trading disabled by client";
         break;
      case TRADE_RETCODE_LOCKED:
         str="locked";
         break;
      case TRADE_RETCODE_FROZEN:
         str="frozen";
         break;
      case TRADE_RETCODE_INVALID_FILL:
         str="invalid fill";
         break;
      case TRADE_RETCODE_CONNECTION:
         str="no connection";
         break;
      case TRADE_RETCODE_ONLY_REAL:
         str="only real";
         break;
      case TRADE_RETCODE_LIMIT_ORDERS:
         str="limit orders";
         break;
      case TRADE_RETCODE_LIMIT_VOLUME:
         str="limit volume";
         break;
      case TRADE_RETCODE_POSITION_CLOSED:
         str="position closed";
         break;
      case TRADE_RETCODE_INVALID_ORDER:
         str="invalid order";
         break;
      case TRADE_RETCODE_CLOSE_ORDER_EXIST:
         str="close order already exists";
         break;
      case TRADE_RETCODE_LIMIT_POSITIONS:
         str="limit positions";
         break;
      default:
         str="unknown retcode "+(string)result.retcode;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double CTrade::CheckVolume(const string symbol,double volume,double price,ENUM_ORDER_TYPE order_type)
  {
//--- check
   if(order_type!=ORDER_TYPE_BUY && order_type!=ORDER_TYPE_SELL)
      return(0.0);
   double free_margin=AccountInfoDouble(ENUM_ACCOUNT_INFO_DOUBLE::ACCOUNT_MARGIN_FREE);
   if(free_margin<=0.0)
      return(0.0);
//--- clean
   ClearStructures();
//--- setting request
   m_request.action=TRADE_ACTION_DEAL;
   m_request.symbol=symbol;
   m_request.volume=volume;
   m_request.type  =order_type;
   m_request.price =price;
//--- action and return the result
   if(!::OrderCheck(m_request,m_check_result) && m_check_result.margin_free<0.0)
     {
      double coeff=free_margin/(free_margin-m_check_result.margin_free);
      double lots=NormalizeDouble(volume*coeff,2);
      if(lots<volume)
        {
         //--- normalize and check limits
         double stepvol=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
         if(stepvol>0.0)
            volume=stepvol*(MathFloor(lots/stepvol)-1);
         //---
         double minvol=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
         if(volume<minvol)
            volume=0.0;
        }
     }
   return(volume);
  }
//+------------------------------------------------------------------+
//| Checks if the m_request structure is filled correctly            |
//+------------------------------------------------------------------+
bool CTrade::OrderCheck(const MqlTradeRequest &request,MqlTradeCheckResult &check_result)
  {
//--- action and return the result
   return(::OrderCheck(request,check_result));
  }
//+------------------------------------------------------------------+
//| Set order filling type according to symbol filling mode          |
//+------------------------------------------------------------------+
bool CTrade::SetTypeFillingBySymbol(const string symbol)
  {
//--- get possible filling policy types by symbol
   uint filling=(uint)SymbolInfoInteger(symbol,SYMBOL_FILLING_MODE);
   if((filling&SYMBOL_FILLING_FOK)==SYMBOL_FILLING_FOK)
     {
      m_type_filling=ORDER_FILLING_FOK;
      return(true);
     }
   if((filling&SYMBOL_FILLING_IOC)==SYMBOL_FILLING_IOC)
     {
      m_type_filling=ORDER_FILLING_IOC;
      return(true);
     }
//---
   return(false);
  }
//+------------------------------------------------------------------+
//| Checks and corrects type of filling policy                       |
//+------------------------------------------------------------------+
bool CTrade::FillingCheck(const string symbol)
  {
//--- get execution mode of orders by symbol
   ENUM_SYMBOL_TRADE_EXECUTION exec=(ENUM_SYMBOL_TRADE_EXECUTION)SymbolInfoInteger(symbol,SYMBOL_TRADE_EXEMODE);
//--- check execution mode
   if(exec==SYMBOL_TRADE_EXECUTION_REQUEST || exec==SYMBOL_TRADE_EXECUTION_INSTANT)
     {
      //--- neccessary filling type will be placed automatically
      return(true);
     }
//--- get possible filling policy types by symbol
   uint filling=(uint)SymbolInfoInteger(symbol,SYMBOL_FILLING_MODE);
//--- check execution mode again
   if(exec==SYMBOL_TRADE_EXECUTION_MARKET)
     {
      //--- for the MARKET execution mode
      //--- analyze order
      if(m_request.action!=TRADE_ACTION_PENDING)
        {
         //--- in case of instant execution order
         //--- if the required filling policy is supported, add it to the request
         if((filling&SYMBOL_FILLING_FOK)==SYMBOL_FILLING_FOK)
           {
            m_type_filling=ORDER_FILLING_FOK;
            m_request.type_filling=m_type_filling;
            return(true);
           }
         if((filling&SYMBOL_FILLING_IOC)==SYMBOL_FILLING_IOC)
           {
            m_type_filling=ORDER_FILLING_IOC;
            m_request.type_filling=m_type_filling;
            return(true);
           }
         //--- wrong filling policy, set error code
         m_result.retcode=TRADE_RETCODE_INVALID_FILL;
         return(false);
        }
      return(true);
     }
//--- EXCHANGE execution mode
   switch(m_type_filling)
     {
      case ORDER_FILLING_FOK:
         //--- analyze order
         if(m_request.action==TRADE_ACTION_PENDING)
           {
            //--- in case of pending order
            //--- add the expiration mode to the request
            if(!ExpirationCheck(symbol))
               m_request.type_time=ORDER_TIME_DAY;
            //--- stop order?
            if(m_request.type==ORDER_TYPE_BUY_STOP || m_request.type==ORDER_TYPE_SELL_STOP ||
               m_request.type==ORDER_TYPE_BUY_LIMIT || m_request.type==ORDER_TYPE_SELL_LIMIT)
              {
               //--- in case of stop order
               //--- add the corresponding filling policy to the request
               m_request.type_filling=ORDER_FILLING_RETURN;
               return(true);
              }
           }
         //--- in case of limit order or instant execution order
         //--- if the required filling policy is supported, add it to the request
         if((filling&SYMBOL_FILLING_FOK)==SYMBOL_FILLING_FOK)
           {
            m_request.type_filling=m_type_filling;
            return(true);
           }
         //--- wrong filling policy, set error code
         m_result.retcode=TRADE_RETCODE_INVALID_FILL;
         return(false);
      case ORDER_FILLING_IOC:
         //--- analyze order
         if(m_request.action==TRADE_ACTION_PENDING)
           {
            //--- in case of pending order
            //--- add the expiration mode to the request
            if(!ExpirationCheck(symbol))
               m_request.type_time=ORDER_TIME_DAY;
            //--- stop order?
            if(m_request.type==ORDER_TYPE_BUY_STOP || m_request.type==ORDER_TYPE_SELL_STOP ||
               m_request.type==ORDER_TYPE_BUY_LIMIT || m_request.type==ORDER_TYPE_SELL_LIMIT)
              {
               //--- in case of stop order
               //--- add the corresponding filling policy to the request
               m_request.type_filling=ORDER_FILLING_RETURN;
               return(true);
              }
           }
         //--- in case of limit order or instant execution order
         //--- if the required filling policy is supported, add it to the request
         if((filling&SYMBOL_FILLING_IOC)==SYMBOL_FILLING_IOC)
           {
            m_request.type_filling=m_type_filling;
            return(true);
           }
         //--- wrong filling policy, set error code
         m_result.retcode=TRADE_RETCODE_INVALID_FILL;
         return(false);
      case ORDER_FILLING_RETURN:
         //--- add filling policy to the request
         m_request.type_filling=m_type_filling;
         return(true);
     }
//--- unknown execution mode, set error code
   m_result.retcode=TRADE_RETCODE_ERROR;
   return(false);
  }
//+------------------------------------------------------------------+
//| Check expiration type of pending order                           |
//+------------------------------------------------------------------+
bool CTrade::ExpirationCheck(const string symbol)
  {
//--- check symbol
   string symbol_name=(symbol==NULL) ? _Symbol : symbol;
//--- get flags
   long tmp_long;
   int  flags=0;
   if(SymbolInfoInteger(symbol_name,SYMBOL_EXPIRATION_MODE,tmp_long))
      flags=(int)tmp_long;
//--- check type
   switch(m_request.type_time)
     {
      case ORDER_TIME_GTC:
         if((flags&SYMBOL_EXPIRATION_GTC)!=0)
            return(true);
         break;
      case ORDER_TIME_DAY:
         if((flags&SYMBOL_EXPIRATION_DAY)!=0)
            return(true);
         break;
      case ORDER_TIME_SPECIFIED:
         if((flags&SYMBOL_EXPIRATION_SPECIFIED)!=0)
            return(true);
         break;
      case ORDER_TIME_SPECIFIED_DAY:
         if((flags&SYMBOL_EXPIRATION_SPECIFIED_DAY)!=0)
            return(true);
         break;
      default:
         Print(__FUNCTION__+": Unknown expiration type");
     }
//--- failed
   return(false);
  }
//+------------------------------------------------------------------+
//| Checks order                                                     |
//+------------------------------------------------------------------+
bool CTrade::OrderTypeCheck(const string symbol)
  {
   bool res=false;
//--- check symbol
   string symbol_name=(symbol==NULL) ? _Symbol : symbol;
//--- get flags of allowed trade orders
   long tmp_long;
   int  flags=0;
   if(SymbolInfoInteger(symbol_name,SYMBOL_ORDER_MODE,tmp_long))
      flags=(int)tmp_long;
//--- depending on the type of order in request
   switch(m_request.type)
     {
      case ORDER_TYPE_BUY:
      case ORDER_TYPE_SELL:
         //--- check possibility of execution
         res=((flags&SYMBOL_ORDER_MARKET)!=0);
         break;
      case ORDER_TYPE_BUY_LIMIT:
      case ORDER_TYPE_SELL_LIMIT:
         //--- check possibility of execution
         res=((flags&SYMBOL_ORDER_LIMIT)!=0);
         break;
      case ORDER_TYPE_BUY_STOP:
      case ORDER_TYPE_SELL_STOP:
         //--- check possibility of execution
         res=((flags&SYMBOL_ORDER_STOP)!=0);
         break;
      case ORDER_TYPE_BUY_STOP_LIMIT:
      case ORDER_TYPE_SELL_STOP_LIMIT:
         //--- check possibility of execution
         res=((flags&SYMBOL_ORDER_STOP_LIMIT)!=0);
         break;
     }
//--- check res
   if(res)
     {
      //--- trading order is valid
      //--- check if we need and able to set protective orders
      if(m_request.sl!=0.0 || m_request.tp!=0.0)
        {
         if((flags&SYMBOL_ORDER_SL)==0)
            m_request.sl=0.0;
         if((flags&SYMBOL_ORDER_TP)==0)
            m_request.tp=0.0;
        }
     }
   else
     {
      //--- trading order is not valid
      //--- set error
      m_result.retcode=TRADE_RETCODE_INVALID_ORDER;
      Print(__FUNCTION__+": Invalid order type");
     }
//--- result
   return(res);
  }
//+------------------------------------------------------------------+
//| Send order                                                       |
//+------------------------------------------------------------------+
bool CTrade::OrderSend(const MqlTradeRequest &request,MqlTradeResult &result)
  {
   bool   res;
   string action="";
   string fmt   ="";
//--- action
   if(m_async_mode)
      res=StrategyOrderSend(request,result,true);
   else
      res=StrategyOrderSend(request,result,false);
//--- check
   if(res)
     {
      if(m_log_level>LOG_LEVEL_ERRORS)
         PrintFormat(__FUNCTION__+": %s [%s]",FormatRequest(action,request),FormatRequestResult(fmt,request,result));
     }
   else
     {
      if(m_log_level>LOG_LEVEL_NO)
         PrintFormat(__FUNCTION__+": %s [%s]",FormatRequest(action,request),FormatRequestResult(fmt,request,result));
     }
//--- return the result
   return(res);
  }
//+------------------------------------------------------------------+
//| Position select depending on netting or hedging                  |
//+------------------------------------------------------------------+
bool CTrade::SelectPosition(const string symbol)
  {
   bool res=false;
//---
   if(IsHedging())
     {
      uint total=PositionsTotal();
      for(uint i=0; i<total; i++)
        {
         string position_symbol=PositionGetSymbol(i);
         if(position_symbol==symbol && m_magic==PositionGetInteger(POSITION_MAGIC))
           {
            res=true;
            break;
           }
        }
     }
   else
      res=PositionSelect(symbol);
//---
   return(res);
  }
//+------------------------------------------------------------------+

#endif


input group "==========  1 - Trading  =========="
input bool   EnableC1      = true; // Enable trading
const bool   EnableC3      = false;   // frozen: unused sleeve is not a user input
input group " "
input group "==========  2 - Risk & Equity Brake  =========="
input double RiskPct       = 1.0; // Balance risk (%) when fixed cash risk is zero
input double RiskMoney     = 0.0; // >0: fixed cash stop-risk budget; 0: RiskPct of balance.
input bool   UseBrake      = true; // Halve risk after rolling losses
input int    BrakeN        = 20; // Closed trades in rolling window
input double BrakeFloorR   = -4.0; // Half-risk threshold (R, inclusive)
#ifndef TOKYOCOIL_TIME_MQH
#define TOKYOCOIL_TIME_MQH
// NY transition instants follow the ORB_Time convention; no weekly-open heuristic.
// ===== CLK-CORE 1.2 BEGIN ===================================================================================
// STANDARD BLOCK - paste verbatim. Do not edit per EA. Changes happen only in the standard, then re-splice every EA.
//
// Broker clock core. PURE: every function depends only on its arguments. No terminal, file, chart or market access,
// no static caches, no hidden "now". Same inputs give the same outputs in tester and live, at any call time.
//
// Model:   server = UTC + baseMin*60 + dst(rule, utc)
//   baseMin  server-minus-UTC in STANDARD (non-DST) time, minutes, multiple of 15, within [-720, +840]
//   rule     CLK_RULE_NONE (fixed offset) | CLK_RULE_US (server follows US DST) | CLK_RULE_EU (server follows EU DST)
//   DST dates: US 2nd Sun Mar 07:00 UTC -> 1st Sun Nov 06:00 UTC; EU last Sun Mar 01:00 UTC -> last Sun Oct 01:00 UTC
//   (valid 2007 onward; earlier years need historical rules and are out of scope).
//
// A broker can change its server offset or its DST behaviour during a sample. One (rule, base) cannot describe
// that history, so the core also carries a DATED SCHEDULE: an ordered list of segments, each a (rule, base) in
// force from a UTC instant. A one-segment schedule is identical to the single model, so nothing is special-cased.
//
// Internal time domain is UTC. Server time exists only at the boundary: ticks, bar and position stamps in, chart
// objects and order expirations out. Convert once at the boundary, then compare and schedule in UTC.
//
// Server wall time -> UTC is not always one-to-one. It is resolved, never halted:
//   FOLD  (clock falls back, wall time occurs twice): the caller supplies lowerBoundUtc, a known lower bound on the true
//         instant (previous resolved UTC in a tick stream, or the PC clock). The smallest candidate >= lowerBoundUtc
//         is returned. With no bound (<=0) the FIRST occurrence is returned. conv reports which rule applied.
//   GAP   (clock jumps forward, wall time never occurs): the wall time is read with the pre-transition offset, which
//         shifts it forward by the gap, the usual convention. conv = CLK_CONV_GAP. Real server stamps never fall in a gap.
#define CLK_CORE_VERSION   "1.2"
#define CLK_BASE_INVALID   (-999999)
#define CLK_MIN_WEEKS      40
#define CLK_MIN_MARGIN     3
#define CLK_MAX_WEEKS      256

enum ENUM_CLK_RULE { CLK_RULE_NONE=0, CLK_RULE_US=1, CLK_RULE_EU=2 };
enum ENUM_CLK_MODE { CLK_MODE_AUTO=0, CLK_MODE_MANUAL=1 };
enum ENUM_CLK_CONV { CLK_CONV_EXACT=0, CLK_CONV_FOLD_BOUND=1, CLK_CONV_FOLD_FIRST=2, CLK_CONV_GAP=3 };
enum ENUM_CLK_ANCHOR { CLK_ANCHOR_OFF=0, CLK_ANCHOR_AUTO=1, CLK_ANCHOR_OPEN17=2, CLK_ANCHOR_OPEN18=3 };

// ---- civil date arithmetic (proleptic Gregorian, integers only; days since 1970-01-01; years >= 1970) -------------------
int ClkDaysFromCivil(int y,int m,int d)
{
   if(m<=2) y--;
   int era=y/400;
   int yoe=y-era*400;
   int doy=(153*(m>2?m-3:m+9)+2)/5+d-1;
   int doe=yoe*365+yoe/4-yoe/100+doy;
   return era*146097+doe-719468;
}
void ClkCivilFromDays(int z,int &y,int &m,int &d)
{
   z+=719468;
   int era=z/146097;
   int doe=z-era*146097;
   int yoe=(doe-doe/1460+doe/36524-doe/146096)/365;
   y=yoe+era*400;
   int doy=doe-(365*yoe+yoe/4-yoe/100);
   int mp=(5*doy+2)/153;
   d=doy-(153*mp+2)/5+1;
   m=mp<10?mp+3:mp-9;
   if(m<=2) y++;
}
int ClkDayOfWeek(int days) { return ((days%7)+7+4)%7; }          // 0=Sunday ... 6=Saturday
int ClkDow(int y,int m,int d) { return ClkDayOfWeek(ClkDaysFromCivil(y,m,d)); }
int ClkDaysInMonth(int y,int m)
{
   int ny=(m==12)?y+1:y, nm=(m==12)?1:m+1;
   return ClkDaysFromCivil(ny,nm,1)-ClkDaysFromCivil(y,m,1);
}
int ClkNthWeekday(int y,int m,int nth,int dow)                   // day of month of the nth given weekday (nth 1..5)
{
   int first=ClkDow(y,m,1);
   return 1+(dow-first+7)%7+7*(nth-1);
}
datetime ClkUtcAt(int y,int m,int d,int hour) { return (datetime)((long)ClkDaysFromCivil(y,m,d)*86400+hour*3600); }

// ---- DST rules -------------------------------------------------------------------------------------------------------
int ClkNyUtcOffset(datetime utc)                                  // America/New_York: -4h in US DST, else -5h
{
   int y,m,d; ClkCivilFromDays((int)(utc/86400),y,m,d);
   datetime start=ClkUtcAt(y,3,ClkNthWeekday(y,3,2,0),7);
   datetime end  =ClkUtcAt(y,11,ClkNthWeekday(y,11,1,0),6);
   return (utc>=start && utc<end) ? -4*3600 : -5*3600;
}
int ClkEuUtcOffset(datetime utc)                                  // EU summer-time delta: 3600 in EU DST, else 0
{
   int y,m,d; ClkCivilFromDays((int)(utc/86400),y,m,d);
   int ms=ClkNthWeekday(y,3,5,0);  if(ms>ClkDaysInMonth(y,3))  ms-=7;
   int os=ClkNthWeekday(y,10,5,0); if(os>ClkDaysInMonth(y,10)) os-=7;
   return (utc>=ClkUtcAt(y,3,ms,1) && utc<ClkUtcAt(y,10,os,1)) ? 3600 : 0;
}
int ClkDstDelta(datetime utc,int rule)                            // seconds the server clock is ahead of its standard time
{
   if(rule==CLK_RULE_US) return ClkNyUtcOffset(utc)==-4*3600 ? 3600 : 0;
   if(rule==CLK_RULE_EU) return ClkEuUtcOffset(utc);
   return 0;
}
bool ClkNearTransition(datetime utc,int rule,int hours)           // a DST change of this rule lies within +-hours of utc
{
   return ClkDstDelta(utc-hours*3600,rule)!=ClkDstDelta(utc+hours*3600,rule);
}

// ---- broker server clock <-> UTC ----------------------------------------------------------------------------------
datetime ClkUtcToServer(datetime utc,int rule,int baseMin) { return utc+baseMin*60+ClkDstDelta(utc,rule); }   // always unique
datetime ClkServerToUtc(datetime server,int rule,int baseMin,datetime lowerBoundUtc,int &conv)
{
   conv=CLK_CONV_EXACT;
   datetime a=server-baseMin*60;                                   // read as standard time (later instant in a fold)
   if(rule==CLK_RULE_NONE) return a;
   datetime b=a-3600;                                              // read as DST (earlier instant in a fold)
   bool va=(ClkUtcToServer(a,rule,baseMin)==server);
   bool vb=(ClkUtcToServer(b,rule,baseMin)==server);
   if(va && !vb) return a;
   if(vb && !va) return b;
   if(va && vb)                                                     // fold
   {
      if(lowerBoundUtc<=0) { conv=CLK_CONV_FOLD_FIRST; return b; }
      conv=CLK_CONV_FOLD_BOUND;
      return (b>=lowerBoundUtc) ? b : a;
   }
   conv=CLK_CONV_GAP;                                              // gap
   return a;
}

// ---- America/New_York wall time <-> UTC (for strategies defined in New York time) -------------------------------------
datetime ClkUtcToNy(datetime utc) { return utc+ClkNyUtcOffset(utc); }
// nyWall = New York wall clock encoded as a datetime (as if UTC). Fold -> first occurrence. Gap -> shifted forward.
datetime ClkNyToUtc(datetime nyWall,int &conv)
{
   conv=CLK_CONV_EXACT;
   datetime d=nyWall+4*3600, s=nyWall+5*3600;                      // EDT reading is the earlier instant
   bool vd=(ClkNyUtcOffset(d)==-4*3600), vs=(ClkNyUtcOffset(s)==-5*3600);
   if(vd && !vs) return d;
   if(vs && !vd) return s;
   if(vd && vs) { conv=CLK_CONV_FOLD_FIRST; return d; }
   conv=CLK_CONV_GAP;
   return s;
}

int ClkNyYmd(datetime utc)                                         // New York calendar date of a UTC instant, YYYYMMDD
{
   int y,m,d; ClkCivilFromDays((int)(ClkUtcToNy(utc)/86400),y,m,d);
   return y*10000+m*100+d;
}
int ClkNyMinute(datetime utc) { return (int)((ClkUtcToNy(utc)%86400)/60); }          // New York minute-of-day 0..1439
// UTC instant of "minuteOfDay on New York date ymd" (e.g. 09:30 -> 570). Fold -> first occurrence, gap -> shifted forward.
datetime ClkNyYmdToUtc(int ymd,int minuteOfDay,int &conv)
{
   return ClkNyToUtc((datetime)((long)ClkDaysFromCivil(ymd/10000,(ymd/100)%100,ymd%100)*86400+minuteOfDay*60),conv);
}

// ---- weekly open/close evidence: infer a broker's DST rule (and, under one stated assumption, its base) ----------------
// The FX week opens and closes at fixed New York times, so the SERVER stamps of the first and last M15 bar of each week
// reveal how the server clock moves against New York. With r_w = Sunday 17:00 NY (opens) or Friday 16:45 NY (start of the
// last M15 bar before the 17:00 NY close), in UTC, and a hypothesised rule R:
//      dev_w(R) = stamp_w - r_w - dst(R, r_w)
// is constant across weeks iff R is the true rule. The constant is base plus the feed's convention; late holiday opens
// only add sporadic positive noise; a wrong rule leaves +-1h steps. Opens and closes are scored together (twice the
// evidence in the same history). The RULE is therefore provable from history alone.
// The absolute BASE is not: a feed shifted by one hour looks identical to a server shifted by one hour. Sources of the
// base, strongest first: live observation (TimeTradeServer-TimeGMT), a registry or learned profile, then - tester only -
// the CLOSE ANCHOR below, which rests on ONE stated assumption: the weekly close is Friday 17:00 NY (last M15 bar 16:45 NY).
// Use symbols that follow the global FX week (FX pairs, metals, US-hours indices); others fail the quality gates.
datetime ClkWeekRefUtc(datetime stamp)                            // Sunday 17:00 New York, UTC
{
   int z=(int)(stamp/86400), dw=ClkDayOfWeek(z);
   int sun=(dw>=4)?z+(7-dw):z-dw;
   datetime approx=(datetime)((long)sun*86400+22*3600);
   return (datetime)((long)sun*86400+17*3600-ClkNyUtcOffset(approx));
}
datetime ClkWeekCloseRefUtc(datetime stamp)                       // Friday 16:45 New York, UTC (start of the last M15 bar of the week)
{
   int z=(int)(stamp/86400), dw=ClkDayOfWeek(z);
   int fri=(dw==6)?z-1:z;
   datetime approx=(datetime)((long)fri*86400+21*3600);
   return (datetime)((long)fri*86400+16*3600+45*60-ClkNyUtcOffset(approx));
}
// First/last-bar-of-week stamps from ascending M15 bar stamps: a >=40h hole, last bar before on Fri/Sat, first after on Sun/Mon.
int ClkWeekOpens(datetime &bars[],int n,datetime &opens[])
{
   int c=0;
   for(int i=1;i<n;i++)
   {
      if(bars[i]-bars[i-1]<40*3600) continue;
      int dp=ClkDayOfWeek((int)(bars[i-1]/86400)), dn=ClkDayOfWeek((int)(bars[i]/86400));
      if((dp!=5 && dp!=6) || (dn!=0 && dn!=1)) continue;
      ArrayResize(opens,c+1); opens[c++]=bars[i];
   }
   return c;
}
int ClkWeekCloses(datetime &bars[],int n,datetime &closes[])
{
   int c=0;
   for(int i=1;i<n;i++)
   {
      if(bars[i]-bars[i-1]<40*3600) continue;
      int dp=ClkDayOfWeek((int)(bars[i-1]/86400)), dn=ClkDayOfWeek((int)(bars[i]/86400));
      if((dp!=5 && dp!=6) || (dn!=0 && dn!=1)) continue;
      ArrayResize(closes,c+1); closes[c++]=bars[i-1];
   }
   return c;
}
// How many weeks of one series sit on a single constant under rule r (tolerance 15 min); mode = that constant (seconds).
int ClkSeriesHits(datetime &st[],int n,int rule,bool isClose,long &mode)
{
   mode=0;
   if(n<=0) return 0;
   if(n>CLK_MAX_WEEKS) n=CLK_MAX_WEEKS;
   long dev[CLK_MAX_WEEKS];
   for(int w=0;w<n;w++)
   {
      datetime ref=isClose ? ClkWeekCloseRefUtc(st[w]) : ClkWeekRefUtc(st[w]);
      dev[w]=(long)st[w]-(long)ref-ClkDstDelta(ref,rule);
   }
   int h=0;
   for(int w=0;w<n;w++)
   {
      int c=0;
      for(int j=0;j<n;j++) if(MathAbs(dev[j]-dev[w])<=900) c++;
      if(c>h) { h=c; mode=dev[w]; }
   }
   return h;
}
// status: 1 resolved | 0 ambiguous | -1 insufficient history (<40 weekly opens). Resolved needs >=85% of all open+close
// observations on one constant per series, and the winner beating the runner-up by >=3 observations.
// nClose may be 0 (opens only). modeOpen/modeClose are the winning rule's constants in seconds.
int ClkInferRule(datetime &opens[],int nOpen,datetime &closes[],int nClose,int &rule,int &hits,int &margin,int &modeOpen,int &modeClose)
{
   rule=-1; hits=0; margin=0; modeOpen=0; modeClose=0;
   if(nOpen<CLK_MIN_WEEKS) return -1;
   if(nOpen>CLK_MAX_WEEKS) nOpen=CLK_MAX_WEEKS;
   if(nClose>CLK_MAX_WEEKS) nClose=CLK_MAX_WEEKS;
   int bestH=-1, secondH=-1, bestR=0; long bestMO=0, bestMC=0;
   for(int r=0;r<3;r++)
   {
      long mo=0, mc=0;
      int h=ClkSeriesHits(opens,nOpen,r,false,mo)+ClkSeriesHits(closes,nClose,r,true,mc);
      if(h>bestH) { secondH=bestH; bestH=h; bestR=r; bestMO=mo; bestMC=mc; }
      else if(h>secondH) secondH=h;
   }
   int total=nOpen+nClose;
   rule=bestR; hits=bestH; margin=bestH-(secondH<0?0:secondH); modeOpen=(int)bestMO; modeClose=(int)bestMC;
   return (bestH*100>=total*85 && margin>=CLK_MIN_MARGIN) ? 1 : 0;
}
// Base (minutes) implied by a live server-minus-UTC observation (seconds, rounded to 15 min) under a rule.
int ClkBaseFromLive(int observedSec,int rule,datetime utcNow)
{
   int adj=observedSec-ClkDstDelta(utcNow,rule);
   if(adj%900!=0) return CLK_BASE_INVALID;
   int m=adj/60;
   return (m<-720 || m>840) ? CLK_BASE_INVALID : m;
}
// Base from a weekly-open constant ONLY under an assumed feed open hour (17 or 18 NY). An assumption, not a proof.
int ClkBaseFromAnchor(int modeSec,int openNYHour)
{
   int adj=modeSec-(openNYHour-17)*3600;
   int r=(adj>=0) ? ((adj+450)/900)*900 : ((adj-450)/900)*900;
   if(MathAbs(adj-r)>300) return CLK_BASE_INVALID;
   int m=r/60;
   return (m<-720 || m>840) ? CLK_BASE_INVALID : m;
}
// CLOSE ANCHOR (tester): base from the weekly-close constant, assuming the weekly close is Friday 17:00 NY, accepted ONLY
// when the open constant agrees under a 17:00 or 18:00 NY open (that agreement is the consistency check) and the base is
// on the 15-minute grid. openNY returns 17 or 18. The accepted feed shapes are exactly (open=close) and (open=close+1h), so
// the single residual assumption is close = 17:00 NY: a feed whose close is at c NY is read as a server shifted by (c-17)h.
// That is why the result is labelled and a live/registry/learned profile always outranks it.
int ClkBaseFromCloseAnchor(int modeOpenSec,int modeCloseSec,int &openNY)
{
   openNY=0;
   int bc=ClkBaseFromAnchor(modeCloseSec,17);
   if(bc==CLK_BASE_INVALID) return CLK_BASE_INVALID;
   if(bc==ClkBaseFromAnchor(modeOpenSec,17)) { openNY=17; return bc; }
   if(bc==ClkBaseFromAnchor(modeOpenSec,18)) { openNY=18; return bc; }
   return CLK_BASE_INVALID;
}

// OPEN ANCHOR (tester): base from the weekly-open constant under an assumed feed open hour. Same class of assumption,
// independent of the close. Used when the close geometry does not validate, so a feed whose close is not 17:00 NY
// resolves with a labelled assumption instead of refusing to run.
int ClkBaseFromOpenAnchor(int modeOpenSec,int openNYHour) { return ClkBaseFromAnchor(modeOpenSec,openNYHour); }

// ---- dated schedule: (fromUtc, rule, baseMin) segments --------------------------------------------------------------
// A one-segment schedule reproduces the single model exactly. Segments are ordered by fromUtc and cover all instants:
// the first segment applies to everything before fromUtc[1].
#define CLK_SEG_MAX        64
#define CLK_SEG_MIN_WEEKS  8
int ClkSegIndex(datetime utc,datetime &from[],int n)
{
   if(n<=0) return -1;
   int i=n-1;
   while(i>0 && utc<from[i]) i--;
   return i;
}
datetime ClkUtcToServerSeg(datetime utc,datetime &from[],int &rule[],int &baseMin[],int n)
{
   int i=ClkSegIndex(utc,from,n);
   if(i<0) return 0;
   return ClkUtcToServer(utc,rule[i],baseMin[i]);
}
// Server stamp -> UTC against a schedule. The reading must be self-consistent: the instant it produces has to fall in
// the same segment that produced it, otherwise the next older segment is tried. Deterministic, no state.
datetime ClkServerToUtcSeg(datetime server,datetime &from[],int &rule[],int &baseMin[],int n,datetime lowerBoundUtc,int &conv)
{
   conv=CLK_CONV_EXACT;
   if(n<=0) return 0;
   for(int i=n-1;i>=0;i--)
   {
      int c;
      datetime u=ClkServerToUtc(server,rule[i],baseMin[i],lowerBoundUtc,c);
      if(ClkSegIndex(u,from,n)!=i) continue;
      if(ClkUtcToServerSeg(u,from,rule,baseMin,n)!=server) continue;
      conv=c;
      return u;
   }
   return 0;
}
// Per-range fit: does ONE (rule, base) describe this slice of weeks, proven by ClkInferRule?
// The base comes from the close anchor when that anchor validates, otherwise from the labelled open-hour assumption.
bool ClkFitRange(datetime &opens[],int oStart,int count,datetime &closes[],int openNYHour,
                 int &rule,int &baseMin,int &hits)
{
   if(count<CLK_SEG_MIN_WEEKS) return false;
   datetime o[CLK_MAX_WEEKS]; datetime c[CLK_MAX_WEEKS];
   int nc=(count<=CLK_MAX_WEEKS)?count:CLK_MAX_WEEKS;
   for(int i=0;i<nc;i++) { o[i]=opens[oStart+i]; c[i]=closes[oStart+i]; }
   int margin=0, mo=0, mc=0;
   if(ClkInferRule(o,nc,c,nc,rule,hits,margin,mo,mc)!=1) return false;
   int on=0;
   int b=ClkBaseFromCloseAnchor(mo,mc,on);
   if(b==CLK_BASE_INVALID) b=ClkBaseFromAnchor(mo,openNYHour);
   if(b==CLK_BASE_INVALID) return false;
   baseMin=b;
   return true;
}
// Recursive dated schedule. A range that one (rule, base) explains becomes one segment; otherwise the split that lets
// both halves be proven independently wins. Depth is bounded, so a pathological history returns 0 segments instead of
// inventing many.
int ClkSchedRange(datetime &opens[],int oStart,int count,datetime &closes[],int openNYHour,int depth,
                  datetime &from[],int &rule[],int &baseMin[],int &segWeeks[],int &covered)
{
   int r=0,h=0,b=0;
   if(ClkFitRange(opens,oStart,count,closes,openNYHour,r,b,h))
   {
      int n=ArraySize(from);
      ArrayResize(from,n+1); ArrayResize(rule,n+1); ArrayResize(baseMin,n+1); ArrayResize(segWeeks,n+1);
      from[n]=(n==0) ? 0 : ClkWeekRefUtc(opens[oStart]);
      rule[n]=r; baseMin[n]=b; segWeeks[n]=count;
      covered+=count;
      return n+1;
   }
   if(depth<=0 || count<2*CLK_SEG_MIN_WEEKS) return 0;
   int bestK=0,bestScore=-1;
   for(int k=CLK_SEG_MIN_WEEKS;k<=count-CLK_SEG_MIN_WEEKS;k++)
   {
      int r1=0,h1=0,b1=0,r2=0,h2=0,b2=0;
      if(!ClkFitRange(opens,oStart,k,closes,openNYHour,r1,b1,h1)) continue;
      if(!ClkFitRange(opens,oStart+k,count-k,closes,openNYHour,r2,b2,h2)) continue;
      if(b1==b2 && r1==r2) continue;                        // same clock on both sides: not a change point
      int score=h1+h2-(count-(h1+h2))*4;                    // prefer splits where both halves fit well
      if(score>bestScore) { bestScore=score; bestK=k; }
   }
   if(bestK==0) return 0;
   int a=ClkSchedRange(opens,oStart,bestK,closes,openNYHour,depth-1,from,rule,baseMin,segWeeks,covered);
   if(a<=0) return 0;
   int c2=ClkSchedRange(opens,oStart+bestK,count-bestK,closes,openNYHour,depth-1,from,rule,baseMin,segWeeks,covered);
   if(c2<=a) return 0;
   return c2;
}
// Build a dated schedule from weekly open/close evidence. openNYHour is the assumed feed open hour (17 or 18).
// The RULE and every CHANGE are proven by the same weekly-constant test the single model uses; only the absolute base
// rests on the labelled feed-geometry assumption. covered reports how many weeks the schedule actually explains.
int ClkScheduleFromEvidence(datetime &opens[],int nOpen,datetime &closes[],int nClose,int openNYHour,
                            datetime &from[],int &rule[],int &baseMin[],int &segWeeks[],int &covered)
{
   covered=0;
   ArrayResize(from,0); ArrayResize(rule,0); ArrayResize(baseMin,0); ArrayResize(segWeeks,0);
   if(nOpen<CLK_SEG_MIN_WEEKS) return 0;
   if(nClose<nOpen) nOpen=nClose;                      // opens and closes are produced in parallel
   if(nOpen>CLK_MAX_WEEKS) nOpen=CLK_MAX_WEEKS;
   int n=ClkSchedRange(opens,0,nOpen,closes,openNYHour,3,from,rule,baseMin,segWeeks,covered);
   if(n<=0) return 0;
   if(n>CLK_SEG_MAX) return 0;
   from[0]=0;                                          // the first segment covers the whole earlier history
   return n;
}
// ===== CLK-CORE 1.2 END =====================================================================================
int clkConvDummy=0;   // fold/gap report of the NY->UTC conversions (unused)

bool ClockInitOnce()
{
   return (ClkInit()==INIT_SUCCEEDED);   // the standard clock owns the broker's offset; it needs no input
}

datetime TcDate(int year,int month,int day,int hour=0)
{
   MqlDateTime d; ZeroMemory(d);
   d.year=year; d.mon=month; d.day=day; d.hour=hour;
   return StructToTime(d);
}

int TcSunday(int year,int month,int nth) { return ClkNthWeekday(year,month,nth,0); }

int NyOffset(datetime utc) { return ClkNyUtcOffset(utc); }
datetime UtcToNewYork(datetime utc) { return ClkUtcToNy(utc); }
datetime NewYorkToUtc(datetime ny) { int conv=0; return ClkNyToUtc(ny,conv); }
int EuOffset(datetime utc) { return ClkEuUtcOffset(utc); }

int BrokerBaseMinutes() { return ClkOK() ? ClkBase() : 120; }

datetime UtcToServerTime(datetime utc)
{
   return ClkUtcToServerTime(utc);
}

datetime ServerTimeToUtc(datetime server)
{
   return ClkStampToUtc(server);
}

datetime NewYorkFromServer(datetime server)
{
   datetime utc=ClkStampToUtc(server);
   return utc>0 ? ClkUtcToNy(utc) : 0;
}

datetime ServerFromNewYork(datetime ny)
{
   int conv=0;
   datetime utc=ClkNyToUtc(ny,conv);
   return utc>0 ? ClkUtcToServerTime(utc) : 0;
}


string TcNyZone(datetime server)
{
   datetime utc=ServerTimeToUtc(server);
   if(utc<=0) return "NY ambiguous DST wall time";
   return ClkNyUtcOffset(utc)==-4*3600 ? "EDT UTC-4" : "EST UTC-5";
}

datetime MakeDateTime(int year,int mon,int day,int hour,int minute,int sec)
{
   MqlDateTime dt; ZeroMemory(dt);
   dt.year=year; dt.mon=mon; dt.day=day; dt.hour=hour; dt.min=minute; dt.sec=sec;
   return StructToTime(dt);
}

int NyOffsetSec(datetime utc) { return ClkNyUtcOffset(utc); }

// Seconds the server clock is ahead of New York: the one clock decision left in this EA.
int ServerAheadOfNewYork(datetime atServer)
{
   datetime utc=ClkStampToUtc(atServer);
   if(utc>0) return (int)((long)atServer-(long)ClkUtcToNy(utc));
   return 7*3600;                     // no mapping yet (first ticks, empty history): this feed's shape
}

datetime NewYorkFromServerTime(datetime serverTime) { return serverTime - ServerAheadOfNewYork(serverTime); }

datetime ServerTimeFromNewYorkWall(int year,int mon,int day,int hour,int minute,int sec)
{
   datetime utc=ClkNyToUtc(MakeDateTime(year,mon,day,hour,minute,sec),clkConvDummy);
   return utc>0 ? ClkUtcToServerTime(utc) : 0;
}
#endif   // TOKYOCOIL_TIME_MQH




input group "  "
input group "==========  3 - News Exit  =========="
input bool UseNewsFlatten = false; // Close before high-impact USD news
input int NewsExitLeadMinutes = 5; // Minutes before news
input string CalendarFile  = "asiancoil_usd_events.csv";   // Filename in Common\Files (NY event times)
input bool AllowDiagnosticCalendar=false; // Permit incomplete calendar for diagnostics only
input group "   "
input group "==========  4 - Execution & Logging  =========="
input string TradeLogFile  = "tokyocoil_frozen_trades.csv"; // Common\Files
input long   MagicC1       = 26093001; // Strategy magic number
const long   MagicC3       = 26093003;
input int    DeviationPts  = 30; // Maximum market-order deviation (points)
// Signal defaults reproduce appendix C1; user-selected news lead defaults to five minutes.
const bool MedianOfValidBoxes = false;
const bool EntryAtRawBoxEdges = false;
input group "    "
input group "==========  5 - Display  =========="
input bool ShowPanel=true; // Show information panel
input bool DrawRangeBoxes=true; // Draw session boxes and levels
input bool ShowExecutionObjects=true; // Draw filled-trade entry and outcome boxes
input bool ShowSyntheticFills=true; // Show hypothetical hindsight fills (never broker orders)
CTrade trade;
const double BOX_MIN_W = 0.02;
// ---------------- calendar -------------------------------------------------------------------------
datetime ev_day[];      // NY date (00:00) of the release
datetime ev_time[];     // NY datetime of the release
bool tcNativeNewsReady=false;
ulong tcNativeNewsAttempt=0,tcNativeNewsSuccess=0;
datetime tcNewsWeek=0;
bool tcNewsLastAttemptOK=false;
datetime tcNewsCountDay=0;
ulong tcNewsRetryMS=300000;
datetime TcNewsWeek(datetime ny)
{
   MqlDateTime d;TimeToStruct(ny,d);
   return DayOf(ny)-d.day_of_week*86400;
}
bool TcNativeNewsValid()
{
   return tcNativeNewsReady && GetTickCount64()-tcNativeNewsSuccess<3600000 &&
          tcNewsWeek==TcNewsWeek(UtcToNewYork(TimeGMT()));
}
string TcNewsField(string object,string key)
{
   int p=StringFind(object,"\""+key+"\"");if(p<0)return "";
   p=StringFind(object,":",p+StringLen(key)+2);if(p<0)return "";
   p++;while(p<StringLen(object) && StringGetCharacter(object,p)<=32)p++;
   if(StringGetCharacter(object,p)!='"')return "";
   string value="";bool escape=false;
   for(int i=p+1;i<StringLen(object);i++)
   {
      ushort c=StringGetCharacter(object,i);
      if(escape){value+=ShortToString(c);escape=false;continue;}
      if(c=='\\'){escape=true;continue;}
      if(c=='"')return value;
      value+=ShortToString(c);
   }
   return "";
}
bool TcNewsISO(string stamp,datetime &utc)
{
   int n=StringLen(stamp);
   if((n!=25 && n!=20) || StringSubstr(stamp,4,1)!="-" || StringSubstr(stamp,7,1)!="-" ||
      StringSubstr(stamp,10,1)!="T" || StringSubstr(stamp,13,1)!=":" || StringSubstr(stamp,16,1)!=":")return false;
   for(int i=0;i<19;i++)
   {
      if(i==4 || i==7 || i==10 || i==13 || i==16)continue;
      ushort c=StringGetCharacter(stamp,i);if(c<'0' || c>'9')return false;
   }
   MqlDateTime d={};d.year=(int)StringToInteger(StringSubstr(stamp,0,4));d.mon=(int)StringToInteger(StringSubstr(stamp,5,2));
   d.day=(int)StringToInteger(StringSubstr(stamp,8,2));d.hour=(int)StringToInteger(StringSubstr(stamp,11,2));
   d.min=(int)StringToInteger(StringSubstr(stamp,14,2));d.sec=(int)StringToInteger(StringSubstr(stamp,17,2));
   if(d.year<2000 || d.mon<1 || d.mon>12 || d.day<1 || d.day>31 || d.hour>23 || d.min>59 || d.sec>59)return false;
   datetime local=StructToTime(d);MqlDateTime check;TimeToStruct(local,check);
   if(check.year!=d.year || check.mon!=d.mon || check.day!=d.day)return false;
   int offset=0;
   if(n==20){if(StringSubstr(stamp,19,1)!="Z")return false;}
   else
   {
      ushort sign=StringGetCharacter(stamp,19);
      if((sign!='+' && sign!='-') || StringSubstr(stamp,22,1)!=":")return false;
      for(int i=20;i<25;i++){if(i==22)continue;ushort c=StringGetCharacter(stamp,i);if(c<'0' || c>'9')return false;}
      int h=(int)StringToInteger(StringSubstr(stamp,20,2)),m=(int)StringToInteger(StringSubstr(stamp,23,2));
      if(h>14 || m>59 || (h==14 && m!=0))return false;
      offset=(h*60+m)*60*(sign=='+'?1:-1);
   }
   utc=local-offset;return true;
}
bool TcNewsParse(string json,datetime week,datetime &events[])
{
   ArrayResize(events,0);StringTrimLeft(json);StringTrimRight(json);
   int size=StringLen(json);if(size<2 || StringGetCharacter(json,0)!='[' || StringGetCharacter(json,size-1)!=']')return false;
   int start=-1,dated=0;bool quoted=false,escape=false;
   for(int i=1;i<size-1;i++)
   {
      ushort c=StringGetCharacter(json,i);
      if(quoted){if(escape)escape=false;else if(c=='\\')escape=true;else if(c=='"')quoted=false;continue;}
      if(c=='"'){quoted=true;continue;}
      if(c=='{'){if(start>=0)return false;start=i;continue;}
      if(c!='}')continue;
      if(start<0)return false;
      string row=StringSubstr(json,start,i-start+1);start=-1;
      string currency=TcNewsField(row,"country"),impact=TcNewsField(row,"impact"),stamp=TcNewsField(row,"date");
      if(currency=="" || impact=="" || stamp=="")return false;
      datetime utc;
      if(!TcNewsISO(stamp,utc))return false;
      datetime ny=UtcToNewYork(utc);
      if(TcNewsWeek(ny)!=week)return false;
      dated++;
      if(currency=="USD" && impact=="High" && MinOfDay(ny)<12*60)
      {int n=ArraySize(events);ArrayResize(events,n+1);events[n]=ny;}
   }
   return dated>0 && start<0 && !quoted;
}
void TcNewsReleaseCounts(datetime &events[],datetime today,int &todayCount,int &remainingCount)
{
   todayCount=0;remainingCount=0;datetime end=TcNewsWeek(today)+7*86400;
   for(int i=0;i<ArraySize(events);i++)
   {
      if(i>0 && events[i]==events[i-1])continue; // Feed is sorted before counting.
      if(events[i]>=today && events[i]<end)remainingCount++;
      if(events[i]>=today && events[i]<today+86400)todayCount++;
   }
}
void TcNativeNewsRefresh()
{
   if(!UseNewsFlatten || MQLInfoInteger(MQL_TESTER) || !TerminalInfoInteger(TERMINAL_CONNECTED)) return;
   ulong nowMS=GetTickCount64();
   if(tcNativeNewsAttempt>0 && nowMS-tcNativeNewsAttempt<(TcNativeNewsValid() && tcNewsLastAttemptOK?1800000:tcNewsRetryMS)) return;
   bool wasReady=TcNativeNewsValid() && tcNewsLastAttemptOK;
   tcNativeNewsAttempt=nowMS;
   tcNewsLastAttemptOK=false;
   // One calendar accessor for the whole book: it owns the fetch, the shared cache, the backoff and the
   // tester refusal, so this EA can never call the network in a backtest and never parses a stale week.
   string payload; datetime fetched=0; bool fromCache=false;
   if(!NewsFeedGet(payload,fetched,fromCache,false))
   {
      Print("TC_LIVE_NEWS_UNAVAILABLE the shared news accessor has no fresh payload; keeping the previous calendar");
      return;
   }
   tcNewsRetryMS=300000;
   datetime week=TcNewsWeek(UtcToNewYork(TimeGMT())),events[];
   if(!TcNewsParse(payload,week,events))
   {Print("TC_LIVE_NEWS_UNAVAILABLE Forex Factory invalid payload or wrong week");return;}
   ArraySort(events);
   bool changed=week!=tcNewsWeek || ArraySize(events)!=ArraySize(ev_time);
   if(!changed)for(int i=0;i<ArraySize(events);i++)if(events[i]!=ev_time[i]){changed=true;break;}
   ArrayResize(ev_time,ArraySize(events));ArrayCopy(ev_time,events);ArrayResize(ev_day,ArraySize(events));
   for(int i=0;i<ArraySize(events);i++) ev_day[i]=DayOf(events[i]);
   tcCoverageStart=week;tcCoverageEnd=week+6*86400;tcCalendarComplete=true;tcNewsWeek=week;
   tcNativeNewsReady=true;tcNativeNewsSuccess=GetTickCount64()-(ulong)(MathMax(0,TimeGMT()-fetched)*1000);
   tcNewsLastAttemptOK=true;
   datetime today=DayOf(UtcToNewYork(TimeGMT()));int todayCount,remainingCount;
   TcNewsReleaseCounts(events,today,todayCount,remainingCount);
   if(!wasReady || changed || tcNewsCountDay!=today)
      PrintFormat("TC_LIVE_NEWS_READY Forex Factory red-folder USD release times: %d today | %d today through week end (NY dates, before 12:00 PM)",todayCount,remainingCount);
   tcNewsCountDay=today;
}
string TcCalendarPath() { return "TokyoCoil_"+CalendarFile; }
bool LoadCalendar()
{
   if(!MQLInfoInteger(MQL_TESTER)) {Print("TC_LIVE_NEWS Forex Factory; memory cache only; waiting for refresh");return true;}
   int h = FileOpen(TcCalendarPath(), FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(h == INVALID_HANDLE) { Print("TokyoCoil: calendar not found in Common\\Files: ", TcCalendarPath()); return false; }
   int n = 0;
   while(!FileIsEnding(h))
   {
      string s = FileReadString(h);
      StringTrimLeft(s); StringTrimRight(s);
      if(StringLen(s) < 16) continue;
      datetime t = StringToTime(s);
      if(t <= 0) continue;
      ArrayResize(ev_time, n + 1); ArrayResize(ev_day, n + 1);
      ev_time[n] = t; ev_day[n] = t - (t % 86400); n++;
   }
   FileClose(h);
   Print("AsianCoilBook: calendar events loaded: ", n);
   return n > 0;
}
// first release before noon NY on the NY date `day` (00:00), or 0
datetime EventOn(datetime day)
{
   for(int i = 0; i < ArraySize(ev_day); i++)
      if(ev_day[i] == day) return ev_time[i];
   return 0;
}
// ---------------- clock ----------------------------------------------------------------------------
datetime NYNow() { return NewYorkFromServer(TimeCurrent()); }
int      MinOfDay(datetime t) { return (int)((t % 86400) / 60); }
datetime DayOf(datetime t) { return t - (t % 86400); }
// the NY session (17:00 NY on date D .. 16:55 NY on D+1) containing NY time t -> D (00:00)
datetime SessionOf(datetime ny) { return DayOf(ny - 17 * 3600); }
// ---------------- box of one session -----------------------------------------------------------------

// session D: its box bars start at NY D 20:00 .. 22:55, i.e. server (D 20:00 + 7h)
bool BoxOf(datetime D, double &hi, double &lo, int &cnt)
{
   datetime from_srv = ServerFromNewYork(D + 20 * 3600);
   datetime to_srv   = ServerFromNewYork(D + 22 * 3600 + 55 * 60);
   MqlRates r[];
   cnt = CopyRates(_Symbol, PERIOD_M5, from_srv, to_srv, r);
   if(cnt <= 0) { cnt = 0; return false; }
   hi = -DBL_MAX; lo = DBL_MAX;
   for(int i = 0; i < cnt; i++) { if(r[i].high > hi) hi = r[i].high; if(r[i].low < lo) lo = r[i].low; }
   return true;
}
bool BoxValid(datetime D, double hi, double lo, int cnt)
{
   MqlDateTime m; TimeToStruct(D, m);                  // D is a NY date; box evenings Sunday..Thursday
   bool wd = (m.day_of_week == 0 || (m.day_of_week >= 1 && m.day_of_week <= 4));
   return wd && cnt >= 30 && (hi - lo) >= BOX_MIN_W - 1e-9;
}
// the previous `n` session dates that have bars (one per D1 bar before the current one)
int PrevSessions(int n, datetime &out[])
{
   ArrayResize(out, 0);
   datetime d1[];
   int got = CopyTime(_Symbol, PERIOD_D1, 1, n, d1);   // server dates of the previous n D1 bars (oldest first)
   if(got <= 0) return 0;
   ArrayResize(out, got);
   for(int i = 0; i < got; i++) out[i] = SessionOf(NewYorkFromServer(d1[i]));   // server date X = NY session date X-1 (17:00)
   return got;
}
// box width relative to the median of the valid boxes among the previous 20 sessions (>= 10 valid)
double RelWidth(double width)
{
   datetime S[];
   int n = PrevSessions(20, S);
    if(MedianOfValidBoxes)
    {
       ArrayResize(S, 0);
       int valid = 0;
       for(int shift = 1; valid < 20; shift++)
       {
          datetime day = iTime(_Symbol, PERIOD_D1, shift);
          if(day <= 0) break;
          datetime session = SessionOf(NewYorkFromServer(day));
          double hi, lo; int cnt;
          if(BoxOf(session, hi, lo, cnt) && BoxValid(session, hi, lo, cnt))
          {
             ArrayResize(S, valid + 1); S[valid++] = session;
          }
       }
       n = valid;
    }
   double w[]; int k = 0;
   for(int i = 0; i < n; i++)
   {
      double h, l; int c;
      if(BoxOf(S[i], h, l, c) && BoxValid(S[i], h, l, c)) { ArrayResize(w, k + 1); w[k++] = h - l; }
   }
   if(k < 10) return -1.0;
   ArraySort(w);
   double med = (k % 2 == 1) ? w[k / 2] : 0.5 * (w[k / 2 - 1] + w[k / 2]);
   return med > 0 ? width / med : -1.0;
}
// ATR(14) of the previous 14 D1 bars (true range with the prior D1 close)
double ATRPrev()
{
   MqlRates r[];
   int got = CopyRates(_Symbol, PERIOD_D1, 1, 15, r);    // oldest first; need 15 for 14 true ranges
   if(got < 11) return -1.0;
   double s = 0; int k = 0;
   for(int i = 1; i < got; i++)
   {
      double pc = r[i - 1].close;
      double tr = MathMax(r[i].high - r[i].low, MathMax(MathAbs(r[i].high - pc), MathAbs(r[i].low - pc)));
      s += tr; k++;
   }
   return k >= 10 ? s / k : -1.0;
}
// ---------------- sleeves ----------------------------------------------------------------------------
struct Sleeve
{
   long     magic;
   string   name;
   double   closedR[];
   datetime closedExit[];
   // open trade
   ulong    pos_id;
   ulong    close_order;
   double   close_volume;
   int      dir;
   double   entry, stop;
   datetime entry_srv;
   datetime flat_srv;      // 0 = none
   double   lots;
   double   rf;
};
Sleeve S1, S3;
// One R is each closed trade's original entry-to-stop distance, including
// trades taken at half risk. It is not a fixed percentage of today's balance.
double TcBrakeFraction(double base,bool enabled,int count,double floor,const double &closed[])
{
   int n=ArraySize(closed);
   if(!enabled || n<count) return base;
   double sum=0;
   for(int i=n-count;i<n;i++) sum+=closed[i];
   return sum<=floor ? base*.5 : base;
}

#include "ExecutionRuntime.mqh"
// ---------------- daily state ------------------------------------------------------------------------
datetime cur_session = 0;
bool     done23 = false;
double   box_hi, box_lo;
bool     c1_armed = false;
void TcSessionReset(datetime session)
{
   if(session==cur_session) return;
   cur_session=session;done23=false;c1_armed=false;DeletePendings(MagicC1);
}
int OnInit()
{
   if(EnableC3 || NewsExitLeadMinutes < 0 || NewsExitLeadMinutes > 720 ||
      RiskMoney<0 || RiskPct<=0 || RiskPct>100 || BrakeN<1 || BrakeFloorR>=0)
       return INIT_PARAMETERS_INCORRECT;
   if(!MQLInfoInteger(MQL_TESTER) && AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {Print("TC_INIT_FAIL live mode requires a hedging account for strategy-owned positions");return INIT_PARAMETERS_INCORRECT;}
    trade.SetDeviationInPoints(DeviationPts);
   trade.SetTypeFillingBySymbol(_Symbol);
   S1.magic = MagicC1; S1.name = "C1"; S1.pos_id = 0;
   S3.magic = MagicC3; S3.name = "C3"; S3.pos_id = 0;
   if(!StrategyLeaseAcquire((ulong)MagicC1))return INIT_FAILED;
   if(UseNewsFlatten && !LoadCalendar()) return INIT_FAILED;
   bool tester=(bool)MQLInfoInteger(MQL_TESTER);
   tcRecoveryReady=true;
   if(!tester && UseBrake && !TcRestoreBrakeHistory(S1)) tcRecoveryReady=false;
   if(tester) FileDelete(TradeLogFile, FILE_COMMON);
   string logname=tester?TradeLogFile:TradeLogFile+"."+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+".live.csv";
   bool has_log=FileIsExist(logname,FILE_COMMON);
   logh = FileOpen(logname, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
   if(logh == INVALID_HANDLE) PrintFormat("TC_LOG_UNAVAILABLE error=%d; trading does not require an audit file",GetLastError());
   if(logh!=INVALID_HANDLE && !has_log) FileWrite(logh, "sleeve", "entry_server", "exit_server", "direction", "entry_price", "stop_price", "exit_price",
             "exit_reason", "lots", "risk_fraction", "profit", "commission", "swap", "R_price", "balance_after");
   if(logh!=INVALID_HANDLE) FileSeek(logh,0,SEEK_END);
   if(!tester)
   {
      cur_session=SessionOf(NYNow());
      done23=false;
      bool historyReady=HistorySelect(ServerFromNewYork(cur_session),TimeCurrent());
      if(!historyReady){tcRecoveryReady=false;PrintFormat("TC_RECOVERY_WAIT current-session history error=%d",GetLastError());}
      for(int i=0;historyReady && i<HistoryDealsTotal();i++)
      {
         ulong d=HistoryDealGetTicket(i);
         if(HistoryDealGetString(d,DEAL_SYMBOL)==_Symbol && HistoryDealGetInteger(d,DEAL_MAGIC)==MagicC1 &&
            HistoryDealGetInteger(d,DEAL_ENTRY)==DEAL_ENTRY_IN) done23=true;
      }
      for(int i=0;i<ArraySize(S1.closedExit);i++)
         if(SessionOf(NewYorkFromServer(S1.closedExit[i]))==cur_session) done23=true;
      for(int i=0;i<OrdersTotal();i++)
         if(OrderGetTicket(i)>0 && OrderGetString(ORDER_SYMBOL)==_Symbol && OrderGetInteger(ORDER_MAGIC)==MagicC1) done23=true;
      Adopt(S1,cur_session);
      if(S1.pos_id>0)
      {
         double entry,stop,exit_price;int direction;datetime exit_time;
         if(!TcHistoryRisk(S1.pos_id,entry,stop,direction,exit_price,exit_time))
         {tcRecoveryReady=false;Print("TC_RECOVERY_WAIT owned position original risk unavailable; existing protection/deadlines remain managed");}
         else S1.stop=stop;
         done23=true;
      }
      if(!tcRecoveryReady)Print("TC_RECOVERY_WAIT new entries paused until broker history is verified");
   }
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason)
{
   if(StrategyLease!=INVALID_HANDLE){FileClose(StrategyLease);StrategyLease=INVALID_HANDLE;}
   if(logh != INVALID_HANDLE) FileClose(logh);
}
void OnTick()
{
   datetime ny = NYNow();
   datetime session = SessionOf(ny);
   int mod = MinOfDay(ny);
   // new session: reset
   TcSessionReset(session);
   // track fills and closes
   Adopt(S1, session); Adopt(S3, session);
   Reconcile(S1, "sl"); Reconcile(S3, "sl");
   // OCO: once a C1 position exists, remove the other order
   ulong t;
   if(PositionOf(MagicC1, t)) DeletePendings(MagicC1);
   // exits: print flatten, then noon (the NY trade-day clock runs 17:00 -> 16:59)
   for(int k = 0; k < 2; k++)
   {
      bool is1 = (k == 0);
      if(is1 ? S1.pos_id == 0 : S3.pos_id == 0) continue;
      datetime fl = is1 ? S1.flat_srv : S3.flat_srv;
      datetime entry_srv=is1?S1.entry_srv:S3.entry_srv;
      bool noon = TimeCurrent()>=ServerFromNewYork(SessionOf(NewYorkFromServer(entry_srv))+86400+12*3600);
      if(fl > 0 && TimeCurrent() >= fl) { if(is1) CloseSleeve(S1, "event"); else CloseSleeve(S3, "event"); continue; }
      if(noon) { if(is1) CloseSleeve(S1, "time"); else CloseSleeve(S3, "time"); }
   }
   // the Tokyo window closes at 03:00 NY: C1 orders that did not fill are cancelled
   if(mod >= 3 * 60 && mod < 17 * 60 && !PositionOf(MagicC1, t)) DeletePendings(MagicC1);
   // 23:00 NY: build the box, arm C1, decide C3 (only in the first 5 minutes, as Python needs the 23:00 bar)
   if(!done23 && mod >= 23 * 60 && mod < 23 * 60 + 5)
   {
      if(!MQLInfoInteger(MQL_TESTER) && !tcRecoveryReady)return;
      if(MQLInfoInteger(MQL_TESTER)) done23 = true;
      int cnt;
      if(!BoxOf(session, box_hi, box_lo, cnt) || !BoxValid(session, box_hi, box_lo, cnt)) return;
      done23 = true;
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      // ---- C1
      TcArmC1(box_hi,box_lo,ask-bid);
      // ---- C3
      if(EnableC3 && S3.pos_id == 0)
      {
         MqlRates d1[];
         if(CopyRates(_Symbol, PERIOD_D1, 1, 1, d1) == 1)
         {
            double pdh = d1[0].high, pdl = d1[0].low, atr = ATRPrev();
            MqlRates lastbar[];
            datetime t2255 = ServerFromNewYork(session + 22 * 3600 + 55 * 60);
            if(atr > 0 && CopyRates(_Symbol, PERIOD_M5, t2255, t2255, lastbar) == 1)
            {
               double c_last = lastbar[0].close;
               bool up = box_hi > pdh && c_last < pdh;
               bool dn = box_lo < pdl && c_last > pdl;
               if(up != dn)
               {
                  double depth = (up ? box_hi - pdh : pdl - box_lo) / atr;
                  if(depth >= 0.05 && depth < 0.15)
                  {
                     int d = up ? -1 : 1;
                     double e = d == 1 ? ask : bid;
                     double s = d == -1 ? box_hi + 0.010 : box_lo;
                     if(!((d == 1 && s >= e - 0.01) || (d == -1 && s <= e + 0.01)))
                     {
                        double rf = BrakeRF(S3); S3.rf = rf;
                        double lots = LotsFor(rf, e, s);
                        trade.SetExpertMagicNumber(MagicC3);
                        if(lots > 0) { if(d == 1) trade.Buy(lots, _Symbol, 0, s, 0, "C3"); else trade.Sell(lots, _Symbol, 0, s, 0, "C3"); }
                     }
                  }
               }
            }
         }
      }
      Adopt(S1, session); Adopt(S3, session);
   }
}

#undef OnInit
#undef OnTick
#undef OnDeinit
// Every calendar must declare its actual coverage; sparse fixtures cannot be
// accidentally run for eleven years. Completion is an audited data claim.
datetime tcCoverageStart=0,tcCoverageEnd=0;
bool tcCalendarComplete=false;
string TcCalendarStatus()
{
   return !UseNewsFlatten ? "DISABLED" : (tcCalendarComplete ? "COMPLETE" : "DIAGNOSTIC");
}
// The news calendar is data, never a prerequisite. A missing or short fixture closes the news gate and
// logs it; it must never stop the EA from starting, and nothing about the build depends on it.
bool TcLoadCoverage()
{
   if(!UseNewsFlatten) { Print("TC_NEWS_DISABLED calendar not loaded; noon exit retained"); return true; }
   if(!MQLInfoInteger(MQL_TESTER)) {tcCalendarComplete=TcNativeNewsValid();return true;}
   tcCalendarComplete=false; tcCoverageStart=0; tcCoverageEnd=0;
   if(StringLen(CalendarFile)==0) { Print("TC_NEWS_GATE_CLOSED CalendarFile is empty; no tester news gate"); return true; }
   if(StringFind(CalendarFile,"\\")>=0 || StringFind(CalendarFile,"/")>=0 || StringFind(CalendarFile,"..")>=0)
   { Print("TC_NEWS_GATE_CLOSED CalendarFile must be a bare filename: ",CalendarFile); return true; }
   int h=FileOpen(TcCalendarPath()+".coverage.csv",FILE_READ|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(h==INVALID_HANDLE)
   { Print("TC_NEWS_GATE_CLOSED no coverage sidecar for ",CalendarFile,"; news gate closed for this run"); return true; }
   tcCoverageStart=StringToTime(FileReadString(h));
   tcCoverageEnd=StringToTime(FileReadString(h));
   string status=FileReadString(h); FileClose(h);
   if(tcCoverageStart<=0 || tcCoverageEnd<tcCoverageStart)
   { Print("TC_NEWS_GATE_CLOSED malformed coverage sidecar; news gate closed"); return true; }
   if(status!="COMPLETE" && !AllowDiagnosticCalendar)
   { Print("TC_NEWS_GATE_CLOSED diagnostic calendar declared; opt in explicitly to use it"); return true; }
   datetime day=SessionOf(NYNow())+86400;
   if(day<tcCoverageStart || day>tcCoverageEnd)
   { Print("TC_NEWS_GATE_CLOSED start date outside declared coverage: ",TimeToString(day)); return true; }
   tcCalendarComplete=true;
   return true;
}
bool TcCoverageNow()
{
   if(!UseNewsFlatten) return true;
   if(!MQLInfoInteger(MQL_TESTER)) return TcNativeNewsValid();
   if(!tcCalendarComplete) return false;                 // gate closed: the run declared no usable calendar
   datetime day=SessionOf(NYNow())+86400;
   return day>=tcCoverageStart && day<=tcCoverageEnd;
}

// Observation only. Executable-side quotes: Bid for longs, Ask for shorts.
// R denominator is actual entry minus the initial stop. Fees are separate.
int tcExcursionFile=INVALID_HANDLE;
int tcPathFile=INVALID_HANDLE;
long tcPathStart=0;
// Little-endian records: int64 server milliseconds, int32 Bid points,
// int32 Ask points, uint8 kind (1 quote, 2 executed final fill).
void TcPath(long msc,double bid,double ask,int kind)
{
   FileWriteLong(tcPathFile,msc);
   FileWriteInteger(tcPathFile,(int)MathRound(bid/_Point),INT_VALUE);
   FileWriteInteger(tcPathFile,(int)MathRound(ask/_Point),INT_VALUE);
   FileWriteInteger(tcPathFile,kind,CHAR_VALUE);
}
ulong tcObservedPosition=0;
int tcObservedDirection=0,tcObservedTrades=0;
double tcEntry=0,tcInitialStop=0,tcObservedLots=0,tcMFE=0,tcMAE=0;
long tcEntryMSC=0,tcMFEMSC=0,tcMAEMSC=0;
bool tcExcursionFailed=false;

string TcStampNY(long msc) { return TimeToString(NewYorkFromServer((datetime)(msc/1000)),TIME_DATE|TIME_SECONDS); }
string TcStampUTC(long msc) { return TimeToString(ServerTimeToUtc((datetime)(msc/1000)),TIME_DATE|TIME_SECONDS); }
void TcExcursionSample(double executable,long serverMSC)
{
   if(serverMSC<tcEntryMSC || executable<=0) return;
   double r=tcObservedDirection*(executable-tcEntry)/MathAbs(tcEntry-tcInitialStop);
   if(r>tcMFE) { tcMFE=r; tcMFEMSC=serverMSC; }
   if(-r>tcMAE) { tcMAE=-r; tcMAEMSC=serverMSC; }
}
bool TcExcursionOpen()
{
   tcExcursionFile=FileOpen(TradeLogFile+".excursions.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(tcExcursionFile==INVALID_HANDLE) return false;
   tcPathFile=FileOpen(TradeLogFile+".paths.bin",FILE_WRITE|FILE_BIN|FILE_COMMON);
   if(tcPathFile==INVALID_HANDLE) return false;
   FileWrite(tcExcursionFile,"position_id","entry_server_msc","exit_server_msc","entry_ny","exit_ny",
             "direction","entry","initial_stop","lots","MFE_R","MAE_R","MFE_server_msc","MAE_server_msc",
             "MFE_ny","MAE_ny","MFE_utc","MAE_utc","minutes_to_MFE","minutes_to_MAE",
             "exit_price_R","giveback_R","native_profit","native_commission","native_swap","calendar_status",
             "path_start_byte","path_end_byte","point");
   return true;
}
void TcExcursionFinish()
{
   if(!HistorySelectByPosition(tcObservedPosition)) { tcExcursionFailed=true; return; }
   long exitMSC=0;
   double exitPrice=0,closedLots=0,profit=0,commission=0,swap=0;
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong deal=HistoryDealGetTicket(i);
      profit+=HistoryDealGetDouble(deal,DEAL_PROFIT);
      commission+=HistoryDealGetDouble(deal,DEAL_COMMISSION);
      swap+=HistoryDealGetDouble(deal,DEAL_SWAP);
      long entry=HistoryDealGetInteger(deal,DEAL_ENTRY);
      if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY)
      {
         closedLots+=HistoryDealGetDouble(deal,DEAL_VOLUME);
         long when=HistoryDealGetInteger(deal,DEAL_TIME_MSC);
         if(when>=exitMSC) { exitMSC=when; exitPrice=HistoryDealGetDouble(deal,DEAL_PRICE); }
      }
   }
   if(exitMSC<=0 || MathAbs(closedLots-tcObservedLots)>0.0001)
   { Print("TC_MAE_FAIL incomplete or partial close ",tcObservedPosition); tcExcursionFailed=true; return; }
   // The final executed fill belongs to the trade, not a later post-close quote.
   TcExcursionSample(exitPrice,exitMSC);
   TcPath(exitMSC,exitPrice,exitPrice,2);
   double exitR=tcObservedDirection*(exitPrice-tcEntry)/MathAbs(tcEntry-tcInitialStop);
   FileWrite(tcExcursionFile,tcObservedPosition,tcEntryMSC,exitMSC,TcStampNY(tcEntryMSC),TcStampNY(exitMSC),
             tcObservedDirection>0?"long":"short",DoubleToString(tcEntry,_Digits),DoubleToString(tcInitialStop,_Digits),
             DoubleToString(tcObservedLots,2),DoubleToString(tcMFE,8),DoubleToString(tcMAE,8),tcMFEMSC,tcMAEMSC,
             TcStampNY(tcMFEMSC),TcStampNY(tcMAEMSC),TcStampUTC(tcMFEMSC),TcStampUTC(tcMAEMSC),
             DoubleToString((tcMFEMSC-tcEntryMSC)/60000.0,6),DoubleToString((tcMAEMSC-tcEntryMSC)/60000.0,6),
             DoubleToString(exitR,8),DoubleToString(tcMFE-exitR,8),DoubleToString(profit,2),
             DoubleToString(commission,2),DoubleToString(swap,2),TcCalendarStatus(),
             tcPathStart,FileTell(tcPathFile),DoubleToString(_Point,8));
   tcObservedTrades++; tcObservedPosition=0;
}
void TcObserve()
{
   ulong ticket=0;
   bool exists=PositionOf(MagicC1,ticket);
   if(tcObservedPosition>0 && (!exists || (ulong)PositionGetInteger(POSITION_IDENTIFIER)!=tcObservedPosition))
      TcExcursionFinish();
   if(!exists) return;
   if(tcObservedPosition==0)
   {
      tcObservedPosition=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
      tcObservedDirection=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;
      tcEntry=PositionGetDouble(POSITION_PRICE_OPEN); tcInitialStop=PositionGetDouble(POSITION_SL);
      tcObservedLots=PositionGetDouble(POSITION_VOLUME);
      tcEntryMSC=PositionGetInteger(POSITION_TIME_MSC);
      tcMFE=0; tcMAE=0; tcMFEMSC=tcEntryMSC; tcMAEMSC=tcEntryMSC;
      tcPathStart=(long)FileTell(tcPathFile);
   }
   if(tcInitialStop<=0 || MathAbs(tcEntry-tcInitialStop)<_Point/2)
   { tcExcursionFailed=true; return; }
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick) || tick.time!=TimeCurrent())
   { Print("TC_MAE_FAIL quote/server clock mismatch"); tcExcursionFailed=true; return; }
   TcExcursionSample(tcObservedDirection>0?tick.bid:tick.ask,tick.time_msc);
   if(tick.time_msc>=tcEntryMSC) TcPath(tick.time_msc,tick.bid,tick.ask,1);
}

#include "ChartVisuals.mqh"

#ifndef TC_CORE_ONLY
datetime tcLiveActiveSince=0,tcLastLiveTick=0,tcResumeSession=0;
int tcResumeState=TC_REPLAY_NO_SIGNAL;
double tcResumeSpread=0;
bool tcResumePending=false;
bool tcPendingDirty=true;
datetime tcPendingSession=0;
bool tcPendingConsumed=false;
ulong tcPendingSubmitted[2]={0,0};
ulong tcNativeTriggerTicket=0;
void TcCancelOppositeTrigger()
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i);long type=ticket>0?OrderGetInteger(ORDER_TYPE):-1;
      if(ticket>0 && ticket!=tcNativeTriggerTicket && OrderGetString(ORDER_SYMBOL)==_Symbol &&
         OrderGetInteger(ORDER_MAGIC)==MagicC1 && (type==ORDER_TYPE_BUY_STOP || type==ORDER_TYPE_SELL_STOP))trade.OrderDelete(ticket);
   }
}
string TcConsumedKey(datetime session)
{
   return StrategyScope((ulong)MagicC1)+".U"+IntegerToString((long)session/86400);
}
bool TcPendingWindow(datetime now,datetime lock,datetime expiry,bool consumed,bool hasFill)
{
   return now>=lock && now<expiry && !consumed && !hasFill;
}
bool TcPendingMatches(double actual,double wanted,double step)
{
   return MathAbs(actual-wanted)<step*0.5;
}
// 0 keep, 1 create, 2 modify, 3 replace volume, 4 cancel.
int TcPendingAction(bool exists,double lots,bool sameVolume,bool sameGeometry)
{
   if(!exists)return lots>0?1:0;
   if(lots<=0)return 4;
   if(!sameVolume)return 3;
   return sameGeometry?0:2;
}
void TcConsumePending(datetime session,string reason)
{
   tcPendingConsumed=true;tcResumePending=false;
   StrategyPersist(TcConsumedKey(session),1);GlobalVariablesFlush();
   DeletePendings(MagicC1);
   PrintFormat("TC_PENDING_CONSUMED session=%s reason=%s",TimeToString(session,TIME_DATE),reason);
}
bool TcPendingHistorySafe(datetime session,double high,double low,double buy,double sell,datetime now)
{
   datetime lock=ServerFromNewYork(session+23*3600);
   MqlRates bars[];int count=CopyRates(_Symbol,PERIOD_M1,lock,now,bars);
   if(count<=0 || bars[0].time!=lock)return false;
   for(int i=0;i<count;i++)
   {
      if(i>0 && bars[i].time-bars[i-1].time!=60)return false;
      if((i==0 && (bars[i].open>high || bars[i].open<low)) ||
         bars[i].high+bars[i].spread*_Point>=buy || bars[i].low<=sell)return false;
   }
   return bars[count-1].time>=now-now%60;
}
int TcPendingFillState(datetime session,datetime now)
{
   ulong ticket;if(PositionOf(MagicC1,ticket))return 1;
   if(!HistorySelect(ServerFromNewYork(session),now))return -1; // Retry unknown history; never assume a fill or permit a replacement.
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong d=HistoryDealGetTicket(i);
      if(HistoryDealGetString(d,DEAL_SYMBOL)==_Symbol && HistoryDealGetInteger(d,DEAL_MAGIC)==MagicC1 &&
         HistoryDealGetInteger(d,DEAL_ENTRY)==DEAL_ENTRY_IN)return 1;
   }
   return 0;
}
void TcLivePendingReconcile()
{
   if(MQLInfoInteger(MQL_TESTER) || !TerminalInfoInteger(TERMINAL_CONNECTED))return;
   MqlTick quote;if(!SymbolInfoTick(_Symbol,quote))return;
   datetime session=SessionOf(NewYorkFromServer(quote.time));
   datetime lock=ServerFromNewYork(session+23*3600),expiry=ServerFromNewYork(session+86400+3*3600);
   if(tcPendingSession!=session)
   {
      tcPendingSession=session;tcPendingConsumed=GlobalVariableCheck(TcConsumedKey(session));tcPendingDirty=true;
      tcPendingSubmitted[0]=0;tcPendingSubmitted[1]=0;
      tcNativeTriggerTicket=0;
   }
   if(!tcRecoveryReady)return;
   if(!EnableC1 || !TcCoverageNow()){DeletePendings(MagicC1);return;}
   if(tcNativeTriggerTicket>0)
   {
      if(OrderSelect(tcNativeTriggerTicket)){TcCancelOppositeTrigger();return;}
      if(!HistoryOrderSelect(tcNativeTriggerTicket))return;
      long triggerState=HistoryOrderGetInteger(tcNativeTriggerTicket,ORDER_STATE);
      if(triggerState!=ORDER_STATE_FILLED && triggerState!=ORDER_STATE_PARTIAL && triggerState!=ORDER_STATE_CANCELED &&
         triggerState!=ORDER_STATE_REJECTED && triggerState!=ORDER_STATE_EXPIRED)return;
      tcNativeTriggerTicket=0;TcConsumePending(session,"native trigger settled; level consumed");return;
   }
   if(tcPendingConsumed){DeletePendings(MagicC1);return;}
   if(!TcPendingWindow(quote.time,lock,expiry,false,false))return;
   for(int side=0;side<2;side++)
   {
      ulong submitted=tcPendingSubmitted[side];if(submitted==0)continue;
      if(OrderSelect(submitted))continue;
      if(!HistoryOrderSelect(submitted))return; // Accepted request not yet visible: never submit a duplicate.
      long state=HistoryOrderGetInteger(submitted,ORDER_STATE);
      if(state==ORDER_STATE_FILLED || state==ORDER_STATE_PARTIAL)
      {TcConsumePending(session,"submitted order filled");return;}
      if(state!=ORDER_STATE_CANCELED && state!=ORDER_STATE_EXPIRED && state!=ORDER_STATE_REJECTED)return;
      tcPendingSubmitted[side]=0;tcPendingDirty=true;
   }
   ulong tickets[2]={0,0};double entries[2]={0,0};
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0 || OrderGetString(ORDER_SYMBOL)!=_Symbol || OrderGetInteger(ORDER_MAGIC)!=MagicC1)continue;
      int side=OrderGetInteger(ORDER_TYPE)==ORDER_TYPE_BUY_STOP?0:OrderGetInteger(ORDER_TYPE)==ORDER_TYPE_SELL_STOP?1:-1;
      if(side<0)continue;
      if(tickets[side]!=0)
      {if(!trade.OrderDelete(ticket) || trade.ResultRetcode()!=TRADE_RETCODE_DONE)return;tcPendingDirty=true;continue;}
      tickets[side]=ticket;entries[side]=OrderGetDouble(ORDER_PRICE_OPEN);
   }
   if((tickets[0]>0 && quote.ask>=entries[0]) || (tickets[1]>0 && quote.bid<=entries[1]))
   {
      tcNativeTriggerTicket=(tickets[0]>0 && quote.ask>=entries[0])?tickets[0]:tickets[1];
      tcResumePending=false;TcCancelOppositeTrigger();
      PrintFormat("TC_NATIVE_TRIGGER_WAIT order=%I64u; broker-owned trigger retained",tcNativeTriggerTicket);return;
   }
   if(!tcPendingDirty && tickets[0]>0 && tickets[1]>0)return;
   int fillState=TcPendingFillState(session,quote.time);
   if(fillState<0){tcPendingDirty=true;return;}
   if(fillState>0){TcConsumePending(session,"confirmed broker fill");return;}
   double high,low;int count;
   if(!BoxOf(session,high,low,count) || !BoxValid(session,high,low,count))return;
   TcExecution replay;int state=TcReplaySession(session,quote.time,replay);
   if(state!=TC_REPLAY_WAITING){TcConsumePending(session,"replay consumed or uncertain");return;}
   double spread=replay.armingSpread;
   // Recover the original arming buffer from active or historical orders, including manually deleted orders.
   if(tickets[0]>0)spread=MathMax(0,entries[0]-high-_Point);
   else
   {
      for(int i=HistoryOrdersTotal()-1;i>=0;i--)
      {
         ulong h=HistoryOrderGetTicket(i);
         if(HistoryOrderGetString(h,ORDER_SYMBOL)==_Symbol && HistoryOrderGetInteger(h,ORDER_MAGIC)==MagicC1 &&
            HistoryOrderGetInteger(h,ORDER_TYPE)==ORDER_TYPE_BUY_STOP &&
            HistoryOrderGetInteger(h,ORDER_TIME_SETUP)>=lock)
         {spread=MathMax(0,HistoryOrderGetDouble(h,ORDER_PRICE_OPEN)-high-_Point);break;}
      }
   }
   double desired[2]={NormalizeDouble(high+spread+_Point,_Digits),NormalizeDouble(low-_Point,_Digits)};
   double stops[2]={low,high},rf=BrakeRF(S1),step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(quote.ask>=desired[0] || quote.bid<=desired[1] || !TcPendingHistorySafe(session,high,low,desired[0],desired[1],quote.time))
   {TcConsumePending(session,"level crossed or incomplete replay");return;}
   if((SymbolInfoInteger(_Symbol,SYMBOL_EXPIRATION_MODE)&SYMBOL_EXPIRATION_SPECIFIED)==0)return;
   trade.SetExpertMagicNumber(MagicC1);S1.rf=rf;
   for(int side=0;side<2;side++)
   {
      double lots=LotsFor(rf,desired[side],stops[side]);ulong ticket=tickets[side];
      if(ticket>0)
      {
         if(!OrderSelect(ticket))return;
         bool sameGeometry=TcPendingMatches(OrderGetDouble(ORDER_PRICE_OPEN),desired[side],_Point) &&
            TcPendingMatches(OrderGetDouble(ORDER_SL),stops[side],_Point) && OrderGetDouble(ORDER_TP)==0 &&
            OrderGetInteger(ORDER_TYPE_TIME)==ORDER_TIME_SPECIFIED && OrderGetInteger(ORDER_TIME_EXPIRATION)==expiry;
         int action=TcPendingAction(true,lots,TcPendingMatches(OrderGetDouble(ORDER_VOLUME_CURRENT),lots,step),sameGeometry);
         if(action==0)continue;
         if(action==2)
         {
            if(!trade.OrderModify(ticket,desired[side],stops[side],0,ORDER_TIME_SPECIFIED,expiry,0) || trade.ResultRetcode()!=TRADE_RETCODE_DONE)return;
            continue;
         }
         if(!trade.OrderDelete(ticket) || trade.ResultRetcode()!=TRADE_RETCODE_DONE)return;
         if(OrderSelect(ticket))return;
      }
      if(lots<=0)continue;
      fillState=TcPendingFillState(session,quote.time);
      if(fillState<0){tcPendingDirty=true;return;}
      if(fillState>0){TcConsumePending(session,"fill during reconciliation");return;}
      if(!SymbolInfoTick(_Symbol,quote) || quote.time>=expiry)return;
      if(quote.ask>=desired[0] || quote.bid<=desired[1]){TcConsumePending(session,"gap during reconciliation");return;}
      bool sent=side==0?trade.BuyStop(lots,desired[side],_Symbol,stops[side],0,ORDER_TIME_SPECIFIED,expiry,"C1"):
                        trade.SellStop(lots,desired[side],_Symbol,stops[side],0,ORDER_TIME_SPECIFIED,expiry,"C1");
      if(!sent || (trade.ResultRetcode()!=TRADE_RETCODE_DONE && trade.ResultRetcode()!=TRADE_RETCODE_PLACED))return;
      tcPendingSubmitted[side]=trade.ResultOrder();
      if(tcPendingSubmitted[side]==0){TcConsumePending(session,"accepted order identity unavailable");return;}
   }
   tcPendingDirty=false;tcResumePending=false;done23=true;
}
void TcStartupReplay()
{
   if(MQLInfoInteger(MQL_TESTER)) return;
   tcPendingDirty=true;
   tcResumePending=false;tcResumeSession=SessionOf(NYNow());
   TcSessionReset(tcResumeSession); // An old done23 flag must not bypass replay after a session gap.
   tcLiveActiveSince=MathMax(TimeCurrent(),TimeTradeServer());
   datetime lock=ServerFromNewYork(tcResumeSession+23*3600);
   if(tcLiveActiveSince<lock) return;
   if(GlobalVariableCheck(TcConsumedKey(tcResumeSession)))
   {done23=true;tcPendingConsumed=true;tcPendingSession=tcResumeSession;DeletePendings(MagicC1);return;}
   ulong ticket;
   if(PositionOf(MagicC1,ticket)) return; // Adopt existing broker fills, never synthesize a new one.
   for(int i=0;i<OrdersTotal();i++)
      if(OrderGetTicket(i)>0 && OrderGetString(ORDER_SYMBOL)==_Symbol && OrderGetInteger(ORDER_MAGIC)==MagicC1) return;
   if(done23) return;
   done23=true; // Disable the original attach-mid-window immediate market-entry path.
   TcExecution replay;tcResumeState=TcReplaySession(tcResumeSession,TimeCurrent(),replay);
   tcResumeSpread=replay.armingSpread;
   tcResumePending=tcResumeState==TC_REPLAY_WAITING;
   PrintFormat("TC_STARTUP_REPLAY session=%s state=%d broker_resume=%d",TimeToString(tcResumeSession,TIME_DATE),tcResumeState,tcResumePending);
}
int OnInit()
{
#ifdef TC_BE_TEST
   if(!MQLInfoInteger(MQL_TESTER) || CandidateBETriggerR<=0 || CandidateCommissionRT<0) return INIT_PARAMETERS_INCORRECT;
#endif
#ifdef TC_FF_SELFTEST
   TcNewsSelfTest();return INIT_FAILED; // Validation harness stops before any account or order work.
#endif
#ifdef TC_PENDING_SELFTEST
   TcPendingSelfTest();return INIT_FAILED;
#endif
   if(!ClockInitOnce()) return INIT_FAILED;
   PrintFormat("TC_INIT_CHECK symbol=%s server=%s news=%d brake=%d connected=%d",_Symbol,AccountInfoString(ACCOUNT_SERVER),UseNewsFlatten,UseBrake,TerminalInfoInteger(TERMINAL_CONNECTED));
   if(!TcLoadCoverage()) return INIT_FAILED;
   tcPendingDirty=true;
   int result=ResearchModelInit();
   if(result!=INIT_SUCCEEDED) return result;
   TcStartupReplay();
   if(MQLInfoInteger(MQL_TESTER) && !TcExcursionOpen()) return INIT_FAILED;
   ResetLastError();
   if(!EventSetTimer(1)) {PrintFormat("TC_INIT_FAIL timer error=%d",GetLastError());return INIT_FAILED;}
   TcPanelStart(); TcRangesRefresh(true); TcExecutionsRefresh(true); TcPanelRefresh();
   return INIT_SUCCEEDED;
}
void OnTick()
{
   ClkRefresh(ClkNowServer());           // resolve/cross-check the broker's offset before any time decision
   if(!MQLInfoInteger(MQL_TESTER))
   {
      MqlTick liveQuote;if(!SymbolInfoTick(_Symbol,liveQuote))return;
      if(tcLastLiveTick>0 && liveQuote.time-tcLastLiveTick>120) TcStartupReplay();
      tcLastLiveTick=liveQuote.time;
      datetime session=SessionOf(NYNow()),expiry=ServerFromNewYork(tcResumeSession+86400+3*3600);
      if(tcResumePending && session==tcResumeSession && TcCoverageNow() &&
         TcAllowLiveReplay(tcResumeState,tcLiveActiveSince,TimeCurrent(),expiry))
      {
         tcResumePending=false;double high,low;int count;
         if(BoxOf(session,high,low,count) && BoxValid(session,high,low,count)) TcArmC1(high,low,tcResumeSpread);
      }
      if(session!=tcResumeSession || TimeCurrent()>=expiry) tcResumePending=false;
   }
   if(MQLInfoInteger(MQL_TESTER)) TcObserve();
   if(TcCoverageNow()) ResearchModelTick();
   else
   {
      DeletePendings(MagicC1);
      CloseSleeve(S1,"calendar_coverage_end");
   }
   if(MQLInfoInteger(MQL_TESTER)) TcObserve();
   TcLivePendingReconcile();
   TcRangesRefresh(); TcExecutionsRefresh(); TcPanelRefresh();
#ifdef TC_BE_TEST
   TcCandidateManage();
#endif
}
void TcLiveDeadlines()
{
   if(MQLInfoInteger(MQL_TESTER) || !TerminalInfoInteger(TERMINAL_CONNECTED)) return;
   trade.SetExpertMagicNumber(MagicC1);
   datetime now=(datetime)MathMax(TimeCurrent(),TimeTradeServer());
   Adopt(S1,SessionOf(NewYorkFromServer(now)));
   // Original order/entry date owns the deadline, even after NY session rollover.
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0 || OrderGetString(ORDER_SYMBOL)!=_Symbol || OrderGetInteger(ORDER_MAGIC)!=MagicC1) continue;
      long type=OrderGetInteger(ORDER_TYPE);
      if(type!=ORDER_TYPE_BUY_STOP && type!=ORDER_TYPE_SELL_STOP)continue;
      datetime setup=(datetime)OrderGetInteger(ORDER_TIME_SETUP);
      datetime expiry=ServerFromNewYork(SessionOf(NewYorkFromServer(setup))+86400+3*3600);
      if(now>=expiry) trade.OrderDelete(ticket);
      else if(OrderGetInteger(ORDER_TYPE_TIME)!=ORDER_TIME_SPECIFIED &&
              (SymbolInfoInteger(_Symbol,SYMBOL_EXPIRATION_MODE)&SYMBOL_EXPIRATION_SPECIFIED)!=0)
         trade.OrderModify(ticket,OrderGetDouble(ORDER_PRICE_OPEN),OrderGetDouble(ORDER_SL),
                           OrderGetDouble(ORDER_TP),ORDER_TIME_SPECIFIED,expiry,OrderGetDouble(ORDER_PRICE_STOPLIMIT));
   }
   if(S1.pos_id>0)
   {
      datetime deadline=ServerFromNewYork(SessionOf(NewYorkFromServer(S1.entry_srv))+86400+12*3600);
      if(UseNewsFlatten)
      {
         if(!TcNativeNewsValid()) {CloseSleeve(S1,"calendar_unavailable");return;}
         datetime event=EventOn(SessionOf(NewYorkFromServer(S1.entry_srv))+86400);
         if(event>0 && event>NewYorkFromServer(S1.entry_srv)) S1.flat_srv=ServerFromNewYork(event-NewsExitLeadMinutes*60);
      }
      if(S1.flat_srv>0 && now>=S1.flat_srv) CloseSleeve(S1,"event");
      else if(now>=deadline) CloseSleeve(S1,"time");
      else
      {
         ulong position;
         if(PositionOf(MagicC1,position) && PositionGetDouble(POSITION_SL)<=0 && S1.stop>0)
         {
            MqlTick quote;
            if(SymbolInfoTick(_Symbol,quote))
            {
               if((S1.dir>0 && quote.bid<=S1.stop) || (S1.dir<0 && quote.ask>=S1.stop)) CloseSleeve(S1,"recovered_stop_crossed");
               else if(!trade.PositionModify(position,S1.stop,PositionGetDouble(POSITION_TP)))
                  PrintFormat("TC_PROTECTION_RETRY position=%I64u retcode=%u detail=%s",position,trade.ResultRetcode(),trade.ResultRetcodeDescription());
            }
         }
      }
   }
}
void OnTimer()
{
   TcLiveDeadlines();TcNativeNewsRefresh();TcLiveDeadlines();
   if(!MQLInfoInteger(MQL_TESTER) && TerminalInfoInteger(TERMINAL_CONNECTED))
   {
      MqlTick quote;datetime now=TimeTradeServer();
      if(!tcRecoveryReady && now>=tcRecoveryRetry)
      {
         tcRecoveryRetry=now+30;
         bool ready=!UseBrake || TcRestoreBrakeHistory(S1);
         if(ready && S1.pos_id>0)
         {
            double entry,stop,exit_price;int direction;datetime exit_time;
            ready=TcHistoryRisk(S1.pos_id,entry,stop,direction,exit_price,exit_time);
            if(ready){S1.stop=stop;if(exit_time>0)S1.pos_id=0;} // Restored closed history already includes this trade.
         }
         int historyState=ready?TcPendingFillState(SessionOf(NewYorkFromServer(now)),now):-1;
         if(historyState>=0)
         {tcRecoveryReady=true;done23=historyState>0;TcStartupReplay();Print("TC_RECOVERY_READY owned history verified; normal entry checks resumed");}
      }
      // Timer catches an unprocessed fresh symbol quote; cached/offline prices never create entries.
      if(SymbolInfoTick(_Symbol,quote) && quote.time>0 && now>=quote.time && now-quote.time<=15)
      {
         if(quote.time>tcLastLiveTick || !done23) OnTick();
         else TcLivePendingReconcile();
      }
   }
   TcRangesRefresh();TcExecutionsRefresh();TcPanelRefresh();
}
void OnTradeTransaction(const MqlTradeTransaction &transaction,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   if(transaction.type==TRADE_TRANSACTION_DEAL_ADD) tcExecutionDirty=true;
   if(transaction.symbol==_Symbol && (transaction.type==TRADE_TRANSACTION_ORDER_ADD || transaction.type==TRADE_TRANSACTION_ORDER_UPDATE ||
      transaction.type==TRADE_TRANSACTION_ORDER_DELETE || transaction.type==TRADE_TRANSACTION_DEAL_ADD))tcPendingDirty=true;
}
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(id==CHARTEVENT_OBJECT_CLICK && sparam==tcPanelPrefix+"BTN")
   {tcPanelCollapsed=!tcPanelCollapsed;tcPanelDirty=true;TcPanelRefresh();ChartRedraw(0);return;}
   if(id==CHARTEVENT_OBJECT_CREATE && StringFind(sparam,tcPanelPrefix)!=0)
   {
      tcPanelDirty=true;
      if(TcVisual() && StringFind(sparam,"TC_")!=0)
      {TcPanelDelete();TcPanelRefresh();} // RBE foreground restack after external execution objects.
   }
   if(id==CHARTEVENT_CHART_CHANGE) { TcRangesRefresh(true); TcExecutionsRefresh(true); }
}
double OnTester()
{
#ifdef TC_BE_TEST
   PrintFormat("TC_EXIT_CANDIDATE changes=%d errors=%d trigger=%.2fR",tcCandidateChanges,tcCandidateErrors,CandidateBETriggerR);
#endif
   TcObserve();
   TcRangesCheck();
   TcRangesFocus();
   double trades=TesterStatistics(STAT_TRADES);
   PrintFormat("TC_RESEARCH_RESULT trades=%.0f observed=%d excursion_failed=%d profit=%.2f pf=%.6f equity_dd_pct=%.6f calendar=%s",
               trades,tcObservedTrades,tcExcursionFailed?1:0,TesterStatistics(STAT_PROFIT),
               TesterStatistics(STAT_PROFIT_FACTOR),TesterStatistics(STAT_EQUITY_DDREL_PERCENT),
               TcCalendarStatus());
   if(trades!=tcObservedTrades) Print("TC_MAE_FAIL excursion trade count differs from native result");
   return TesterStatistics(STAT_PROFIT);
}
void OnDeinit(const int reason)
{
   ResearchModelDeinit(reason);
   if(tcExcursionFile!=INVALID_HANDLE) FileClose(tcExcursionFile);
   if(tcPathFile!=INVALID_HANDLE) FileClose(tcPathFile);
   TcPanelStop();
   EventKillTimer();
   // Keep completed visual-test boxes for inspection; init cleans its own prefix.
   if(!MQLInfoInteger(MQL_TESTER)) ObjectsDeleteAll(0,tcRangePrefix);
   if(!MQLInfoInteger(MQL_TESTER)) ObjectsDeleteAll(0,tcExecPrefix);
}

#endif // TC_CORE_ONLY

#endif // TC_STRATEGY_ENGINE
