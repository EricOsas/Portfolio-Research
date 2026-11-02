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
//| Clock: New York time = server time - ServerToNY hours (IC Markets: 7, verified month by month). |
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
enum TC_BROKER_CLOCK { TC_IC_NY_CLOSE=0, TC_FIXED_UTC=1, TC_EU_DST=2, TC_NY_CLOSE_8=3 };
// Internal clock state; no broker-clock switches in user-facing inputs.
TC_BROKER_CLOCK BrokerClock=TC_IC_NY_CLOSE;
int FixedBrokerUTCMinutes=0;
const bool DetectLiveUTCOffset=true;
bool TcClockInit()
{
   string broker=AccountInfoString(ACCOUNT_SERVER)+" "+AccountInfoString(ACCOUNT_COMPANY);
   StringToLower(broker);BrokerClock=TC_FIXED_UTC;
   if(StringFind(broker,"icmarkets")>=0 || StringFind(broker,"ic markets")>=0 || StringFind(broker,"raw trading")>=0)
      BrokerClock=TC_IC_NY_CLOSE;
   else if(StringFind(broker,"fundingpips")>=0 || StringFind(broker,"funding pips")>=0)
      BrokerClock=TC_NY_CLOSE_8;
   return true;
}

datetime TcDate(int year,int month,int day,int hour=0)
{
   MqlDateTime d; ZeroMemory(d);
   d.year=year; d.mon=month; d.day=day; d.hour=hour;
   return StructToTime(d);
}
int TcSunday(int year,int month,int nth)
{
   MqlDateTime d; TimeToStruct(TcDate(year,month,1),d);
   return 1+(7-d.day_of_week)%7+7*(nth-1);
}
int TcNyUTCOffset(datetime utc)
{
   MqlDateTime d; TimeToStruct(utc,d);
   datetime start=TcDate(d.year,3,TcSunday(d.year,3,2),7);
   datetime end=TcDate(d.year,11,TcSunday(d.year,11,1),6);
   return utc>=start && utc<end ? -4*3600 : -5*3600;
}
datetime TcUTCToNY(datetime utc) { return utc+TcNyUTCOffset(utc); }
// Reject nonexistent/ambiguous wall times rather than silently choosing a fold.
datetime TcNYToUTC(datetime ny)
{
   datetime winter=ny+5*3600, summer=ny+4*3600;
   bool w=TcUTCToNY(winter)==ny, s=TcUTCToNY(summer)==ny;
   if(w==s) return 0;
   return w ? winter : summer;
}
int TcEuUTCOffset(datetime utc)
{
   MqlDateTime d;TimeToStruct(utc,d);
   int march=TcSunday(d.year,3,4),october=TcSunday(d.year,10,4);
   if(march+7<=31) march+=7;
   if(october+7<=31) october+=7;
   return utc>=TcDate(d.year,3,march,1) && utc<TcDate(d.year,10,october,1)?3600:0;
}
datetime TcUTCToServer(datetime utc,TC_BROKER_CLOCK profile,int fixedMinutes)
{
   if(profile==TC_IC_NY_CLOSE || profile==TC_NY_CLOSE_8) return TcUTCToNY(utc)+(profile==TC_IC_NY_CLOSE?7:8)*3600;
   return utc+fixedMinutes*60+(profile==TC_EU_DST?TcEuUTCOffset(utc):0);
}
datetime TcServerToUTC(datetime server,TC_BROKER_CLOCK profile,int fixedMinutes)
{
   if(profile==TC_IC_NY_CLOSE || profile==TC_NY_CLOSE_8) return TcNYToUTC(server-(profile==TC_IC_NY_CLOSE?7:8)*3600);
   datetime winter=server-fixedMinutes*60;
   if(profile==TC_FIXED_UTC) return winter;
   datetime summer=winter-3600;
   bool w=TcUTCToServer(winter,profile,fixedMinutes)==server;
   bool s=TcUTCToServer(summer,profile,fixedMinutes)==server;
   if(w==s) return 0;
   return w?winter:summer;
}
int TcBrokerBaseMinutes()
{
   if(BrokerClock==TC_IC_NY_CLOSE || BrokerClock==TC_NY_CLOSE_8 || !DetectLiveUTCOffset || MQLInfoInteger(MQL_TESTER)) return FixedBrokerUTCMinutes;
   // ORB live clock detection; round to minutes to retain half-hour brokers.
   // Resolve the profile's winter base once per UTC day, independently of conversion arguments.
   static datetime day=0;static int base=0;
   datetime utc=TimeGMT(),today=utc-utc%86400;
   if(day!=today)
   {
      datetime server=TimeTradeServer();
      if(server<=0) return FixedBrokerUTCMinutes; // Do not infer from a stale last tick.
      base=(int)MathRound((double)(server-utc)/60.0);
      if(BrokerClock==TC_EU_DST) base-=TcEuUTCOffset(utc)/60;
      day=today;
   }
   return base;
}
datetime TcServerToUTC(datetime server) { return TcNYToUTC(TcServerToNY(server)); }
datetime TcServerToNY(datetime server,TC_BROKER_CLOCK profile,int fixedMinutes)
{
   if(profile==TC_IC_NY_CLOSE || profile==TC_NY_CLOSE_8) return server-(profile==TC_IC_NY_CLOSE?7:8)*3600;
   datetime utc=TcServerToUTC(server,profile,fixedMinutes);
   return utc>0?TcUTCToNY(utc):0;
}
datetime TcServerToNY(datetime server) { return ServerToNY(server); }
datetime TcNYToServer(datetime ny,TC_BROKER_CLOCK profile,int fixedMinutes)
{
   if(profile==TC_IC_NY_CLOSE || profile==TC_NY_CLOSE_8) return ny+(profile==TC_IC_NY_CLOSE?7:8)*3600;
   datetime utc=TcNYToUTC(ny);
   return utc>0 ? TcUTCToServer(utc,profile,fixedMinutes) : 0;
}
datetime TcNYToServer(datetime ny)
{
   MqlDateTime d;TimeToStruct(ny,d);
   return NYLocalToServer(d.year,d.mon,d.day,d.hour,d.min,d.sec);
}
string TcNyZone(datetime server)
{
   datetime utc=TcServerToUTC(server);
   if(utc<=0) return "NY ambiguous DST wall time";
   return TcNyUTCOffset(utc)==-4*3600 ? "EDT UTC-4" : "EST UTC-5";
}

#ifndef TC_RBE_CLOCK_MQH
#define TC_RBE_CLOCK_MQH
// ORB_Scalper clock port: compile-time helper, no runtime file dependency.
#define ORB_TESTER_DEFAULT_SERVER_UTC 8

datetime MakeDateTime(int year,int mon,int day,int hour,int minute,int sec)
{
    MqlDateTime dt;
    ZeroMemory(dt);
    dt.year=year;
    dt.mon=mon;
    dt.day=day;
    dt.hour=hour;
    dt.min=minute;
    dt.sec=sec;
    return StructToTime(dt);
}

int NthSundayOfMonthUTC(int year,int month,int nth)
{
    if(nth < 1) return 1;
    MqlDateTime dt; ZeroMemory(dt);
    dt.year=year; dt.mon=month; dt.day=1;
    datetime firstDay=StructToTime(dt);
    TimeToStruct(firstDay,dt);
    int firstDow=dt.day_of_week;            // 0=Sunday
    int firstSunday=1 + ((7-firstDow)%7);
    return firstSunday + (nth-1)*7;
}

int NYUTCOffsetSec(datetime utcTime)
{
    if(!true) return -5*3600;
    MqlDateTime utc; TimeToStruct(utcTime,utc);
    int year=utc.year;

    int marchSunday    = NthSundayOfMonthUTC(year,3,2);
    int novemberSunday = NthSundayOfMonthUTC(year,11,1);

    MqlDateTime startUtc; ZeroMemory(startUtc);
    startUtc.year=year; startUtc.mon=3;  startUtc.day=marchSunday;    startUtc.hour=7;
    MqlDateTime endUtc;   ZeroMemory(endUtc);
    endUtc.year=year;   endUtc.mon=11; endUtc.day=novemberSunday;   endUtc.hour=6;

    datetime dstStart=StructToTime(startUtc);
    datetime dstEnd  =StructToTime(endUtc);
    return (utcTime>=dstStart && utcTime<dstEnd) ? -4*3600 : -5*3600;
}

int TesterWeekAnchorOffsetSec(datetime atServer=0)
{
    if(atServer==0) atServer=TimeCurrent();
    static datetime cachedWeekOpen[6];
    static int cachedOffset[6];
    static int nextCache=0;
    for(int c=0;c<6;c++)
        if(cachedWeekOpen[c]>0 && atServer>=cachedWeekOpen[c] && atServer<cachedWeekOpen[c]+7*86400)
            return cachedOffset[c];

    // History may not be loaded on the very first call (OnInit) - retry later.
    int first=iBarShift(_Symbol,PERIOD_H1,atServer,false);
    if(first<0 || iTime(_Symbol,PERIOD_H1,first)<=0) return -999999;

    datetime newer = 0;
    for(int i = first; i < first+500; i++)
    {
        datetime t = iTime(_Symbol, PERIOD_H1, i);
        if(t <= 0) break;
        if(newer > 0 && (newer - t) >= 40*3600)      // candidate weekend gap
        {
            datetime weekOpenServer = newer;          // first bar of the new week
            datetime weekCloseServer = t;             // last bar of the prior week

            // EXNESS +1h REGRESSION FIX: validate the gap is a TRUE Fri->Sun
            // weekend, not a holiday hole or a data gap. The bar BEFORE the gap
            // must fall on a Friday (server time, dow 5) and the bar AFTER it on
            // a Sunday or Monday (dow 0/1). A few hours of offset skew can never
            // move a Friday-evening bar off Friday, so the day-of-week test is
            // safe before the offset is even known. Reject anything else and
            // keep scanning for the next gap.
            MqlDateTime co; TimeToStruct(weekCloseServer, co);
            MqlDateTime op; TimeToStruct(weekOpenServer,  op);
            bool closeIsFri = (co.day_of_week == 5);
            bool openIsSunMon = (op.day_of_week == 0 || op.day_of_week == 1);
            if(!closeIsFri || !openIsSunMon) { newer = t; continue; }

            // The market week ALWAYS opens at 17:00 New York. Derive the
            // broker's FIXED server->UTC offset from this anchor, then let
            // NYUTCOffsetSec apply NY DST once on top (the correct model).
            //
            // CORRECT MODEL (evidence: Exness runs a FIXED UTC offset, NOT a
            // DST-following clock - a 09:30 NY range fires at 14:30 server in
            // summer and 15:30 in winter on the same UTC+1 feed). So:
            //   serverUTCoffset = weekendServerSecOfDay - weekendUTCSecOfDay
            // where the weekend's UTC second-of-day is 17:00 NY converted via
            // that weekend's OWN DST: summer (EDT,-4h) -> 21:00 UTC,
            // winter (EST,-5h) -> 22:00 UTC. The weekend DST is resolved from
            // its NY wall-clock (17:00), which is unambiguous.
            // The server stamp of the weekly-open bar IS the server->NY offset
            // directly. On FundingPips the first bar of the week is stamped
            // server 02:00 = 18:00 NY (Sunday), so server->NY = 02:00 - 18:00
            // wrapped = +8h. DST is already baked into the server clock
            // (DST-following feed), so we DO NOT re-apply NY DST on top - that
            // double-count was the 1h summer error. For a fixed-UTC feed
            // (Exness) the open bar sits at a different season-dependent server
            // time and the anchor re-derives the correct server->NY per season.
            //
            // WEEKLY-OPEN REFERENCE = 18:00 NY (not 17:00): this feed's first
            // post-weekend bar lands at 18:00 NY. Using 17:00 over-counted the
            // offset by 1h (Dec resolved 9h -> 18:30 instead of 8h -> 17:30).
            int srvSecDay     = (int)((long)weekOpenServer % 86400);
            int nyOpenSecDay  = 18*3600;                          // 18:00 NY open
            int diff          = srvSecDay - nyOpenSecDay;         // server->NY offset
            while(diff >  12*3600) diff -= 86400;
            while(diff < -12*3600) diff += 86400;
            int off = (int)(MathRound((double)diff/3600.0)*3600.0);  // snap to hour

            // PLAUSIBILITY GATE: server->NY for real feeds is roughly -2..+10.
            if(off < -2*3600 || off > 10*3600) { newer = t; continue; }

            cachedWeekOpen[nextCache]=weekOpenServer;
            cachedOffset[nextCache]=off;
            nextCache=(nextCache+1)%6;
            // DIAGNOSTIC: surface what the anchor resolved so the tester time
            // can be verified directly (weekend bar + derived offset).
            return off;
        }
        newer = t;
    }
    // History can arrive after OnInit. Retry rather than freezing a fallback.
    return -999999;
}

int ServerNYOffsetSec(datetime atServer)
{
    // Retain verified NY-close broker calibration across historical seasons.
    if(BrokerClock==TC_IC_NY_CLOSE || BrokerClock==TC_NY_CLOSE_8)
        return (BrokerClock==TC_IC_NY_CLOSE?7:8)*3600;
    int correction = 0 * 3600;   // +/- nudge on auto value
    int autoOff;

    // TESTER: TimeGMT() is simulated (~= server clock), so the live
    // TimeTradeServer()-vs-TimeGMT() method collapses to 0. Use the weekly-open
    // anchor instead (Sunday 17:00 NY), which yields server->NY directly,
    // guarded by a Fri->Sun day-of-week check + plausibility gate. Falls back to
    // a sane default only if no valid weekend gap is in the loaded history (a
    // sub-week window or a 24/7 crypto feed); pin it with the correction input.
    if((bool)MQLInfoInteger(MQL_TESTER))
    {
        int anchored = TesterWeekAnchorOffsetSec(atServer);
        if(anchored != -999999)
            autoOff = anchored;
        else
            // No weekend in range (sub-week window or 24/7 feed): use the
            // default DIRECTLY - it is already a server->NY value (flat NY+8h
            // for FundingPips), so it is correct in both seasons with no DST
            // term. Adding NYUTCOffsetSec here was the leftover double-count
            // that pushed summer to 12h/21:30.
            autoOff = ORB_TESTER_DEFAULT_SERVER_UTC*3600;
        return autoOff + correction;
    }

    // LIVE: server->UTC from the live trade-server clock vs GMT, then add NY's
    // UTC offset to express it as server->NY (server is AHEAD of NY by this).
    datetime serverNow = TimeCurrent();
    datetime tradeNow  = TimeTradeServer();
    datetime gmtNow    = TimeGMT();

    int currentOff = (int)(serverNow - gmtNow);
    int tradeOff   = (tradeNow > 0) ? (int)(tradeNow - gmtNow) : 0;

    int rawUTC = 0;
    if(tradeNow > 0)                   rawUTC = tradeOff;
    else if(MathAbs(currentOff) >= 60) rawUTC = currentOff;
    int serverUTC = (int)(MathRound((double)rawUTC / 3600.0) * 3600.0);

    // server->NY = server->UTC - NY->UTC  (NYUTCOffsetSec is negative, so this
    // adds the 4h/5h; e.g. UTC+0 server in winter = NY+5h).
    // Rebuilding a prior day must use that day's NY DST, not today's.
    // Retain ORB's live server/GMT calibration. For older broker dates,
    // use its weekly anchor only when today's anchor agrees with the live
    // clock; feeds whose weekly opening differs from 18:00 NY keep the
    // calibrated conversion instead of inheriting an unvalidated anchor.
    autoOff = serverUTC - NYUTCOffsetSec(atServer-serverUTC);
    if((long)atServer/86400!=(long)serverNow/86400)
    {
        int liveAnchor=TesterWeekAnchorOffsetSec(serverNow);
        if(liveAnchor==serverUTC-NYUTCOffsetSec(gmtNow))
        {
            int datedAnchor=TesterWeekAnchorOffsetSec(atServer);
            if(datedAnchor!=-999999) autoOff=datedAnchor;
        }
    }
    return autoOff + correction;
}

datetime ServerToNY(datetime serverTime)
{
    // Server clock already carries DST (DST-following feed) or the anchor has
    // resolved the correct per-season offset (fixed-UTC feed). Convert directly.
    return serverTime - ServerNYOffsetSec(serverTime);
}

datetime NYLocalToServer(int year,int mon,int day,int hour,int minute,int sec)
{
    // Exact inverse of ServerToNY: the server clock is AHEAD of NY wall time by
    // ServerNYOffsetSec (DST already baked into the server clock, or resolved
    // per-season by the anchor). So server = NY wall + offset, directly. No
    // UTC round trip and no second DST application - that double-count was the
    
// old 1h summer error.
    datetime nyWall = MakeDateTime(year,mon,day,hour,minute,sec);
    datetime candidate=nyWall + ServerNYOffsetSec(TimeCurrent());
    return nyWall + ServerNYOffsetSec(candidate);
}
#endif


#endif

input group "  "
input group "==========  3 - News Exit  =========="
input bool UseNewsFlatten = false; // Close before high-impact USD news
input int NewsExitLeadMinutes = 5; // Minutes before news
input string NewsWebRequestURL = "https://nfs.faireconomy.media"; // Copy to MT5 Allow WebRequest (reference only)
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
          tcNewsWeek==TcNewsWeek(TcUTCToNY(TimeGMT()));
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
      datetime ny=TcUTCToNY(utc);
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
   char request[],response[];string headers;ResetLastError();
   int status=WebRequest("GET","https://nfs.faireconomy.media/ff_calendar_thisweek.json",
                        "User-Agent: Mozilla/5.0\r\nAccept: application/json\r\n",5000,request,response,headers);
   int requestError=GetLastError();datetime fetched=TimeGMT();
   string payload=status==200?CharArrayToString(response,0,-1,CP_UTF8):"";
   tcNewsRetryMS=status==429?900000:300000;
   if(status!=200)
   {
      if(status==429)Print("TC_LIVE_NEWS_UNAVAILABLE Forex Factory rate limit HTTP 429; retry in 15 minutes; existing cache retains its original freshness limit");
      else PrintFormat("TC_LIVE_NEWS_UNAVAILABLE Forex Factory http=%d error=%d; %s",status,requestError,
         "check provider access and WebRequest allowlist if requests are disabled");
      return;
   }
   datetime week=TcNewsWeek(TcUTCToNY(TimeGMT())),events[];
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
   datetime today=DayOf(TcUTCToNY(TimeGMT()));int todayCount,remainingCount;
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
datetime NYNow() { return TcServerToNY(TimeCurrent()); }
int      MinOfDay(datetime t) { return (int)((t % 86400) / 60); }
datetime DayOf(datetime t) { return t - (t % 86400); }
// the NY session (17:00 NY on date D .. 16:55 NY on D+1) containing NY time t -> D (00:00)
datetime SessionOf(datetime ny) { return DayOf(ny - 17 * 3600); }
// ---------------- box of one session -----------------------------------------------------------------

// session D: its box bars start at NY D 20:00 .. 22:55, i.e. server (D 20:00 + 7h)
bool BoxOf(datetime D, double &hi, double &lo, int &cnt)
{
   datetime from_srv = TcNYToServer(D + 20 * 3600);
   datetime to_srv   = TcNYToServer(D + 22 * 3600 + 55 * 60);
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
   for(int i = 0; i < got; i++) out[i] = SessionOf(TcServerToNY(d1[i]));   // server date X = NY session date X-1 (17:00)
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
          datetime session = SessionOf(TcServerToNY(day));
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
      bool historyReady=HistorySelect(TcNYToServer(cur_session),TimeCurrent());
      if(!historyReady){tcRecoveryReady=false;PrintFormat("TC_RECOVERY_WAIT current-session history error=%d",GetLastError());}
      for(int i=0;historyReady && i<HistoryDealsTotal();i++)
      {
         ulong d=HistoryDealGetTicket(i);
         if(HistoryDealGetString(d,DEAL_SYMBOL)==_Symbol && HistoryDealGetInteger(d,DEAL_MAGIC)==MagicC1 &&
            HistoryDealGetInteger(d,DEAL_ENTRY)==DEAL_ENTRY_IN) done23=true;
      }
      for(int i=0;i<ArraySize(S1.closedExit);i++)
         if(SessionOf(TcServerToNY(S1.closedExit[i]))==cur_session) done23=true;
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
      bool noon = TimeCurrent()>=TcNYToServer(SessionOf(TcServerToNY(entry_srv))+86400+12*3600);
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
            datetime t2255 = TcNYToServer(session + 22 * 3600 + 55 * 60);
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
bool TcLoadCoverage()
{
   if(!UseNewsFlatten) { Print("TC_NEWS_DISABLED calendar not loaded; noon exit retained"); return true; }
   if(!MQLInfoInteger(MQL_TESTER)) {tcCalendarComplete=TcNativeNewsValid();return true;}
   if(StringFind(CalendarFile,"\\")>=0 || StringFind(CalendarFile,"/")>=0 || StringFind(CalendarFile,"..")>=0 || StringLen(CalendarFile)==0)
   { Print("TC_COVERAGE_FAIL calendar must be a filename in TokyoCoil/calendar");return false; }
   int h=FileOpen(TcCalendarPath()+".coverage.csv",FILE_READ|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(h==INVALID_HANDLE) { Print("TC_COVERAGE_FAIL missing sidecar for ",CalendarFile); return false; }
   tcCoverageStart=StringToTime(FileReadString(h));
   tcCoverageEnd=StringToTime(FileReadString(h));
   string status=FileReadString(h); FileClose(h);
   tcCalendarComplete=status=="COMPLETE";
   if(tcCoverageStart<=0 || tcCoverageEnd<tcCoverageStart) return false;
   if(!tcCalendarComplete && !AllowDiagnosticCalendar)
   { Print("TC_COVERAGE_FAIL diagnostic calendar requires explicit opt-in"); return false; }
   datetime day=SessionOf(NYNow())+86400;
   if(day<tcCoverageStart || day>tcCoverageEnd)
   { Print("TC_COVERAGE_FAIL start date outside declared calendar coverage: ",TimeToString(day)); return false; }
   return true;
}
bool TcCoverageNow()
{
   if(!UseNewsFlatten) return true;
   if(!MQLInfoInteger(MQL_TESTER)) return TcNativeNewsValid();
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

string TcStampNY(long msc) { return TimeToString(TcServerToNY((datetime)(msc/1000)),TIME_DATE|TIME_SECONDS); }
string TcStampUTC(long msc) { return TimeToString(TcServerToUTC((datetime)(msc/1000)),TIME_DATE|TIME_SECONDS); }
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
   datetime lock=TcNYToServer(session+23*3600);
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
   if(!HistorySelect(TcNYToServer(session),now))return -1; // Retry unknown history; never assume a fill or permit a replacement.
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
   datetime session=SessionOf(TcServerToNY(quote.time));
   datetime lock=TcNYToServer(session+23*3600),expiry=TcNYToServer(session+86400+3*3600);
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
   datetime lock=TcNYToServer(tcResumeSession+23*3600);
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
   if(FixedBrokerUTCMinutes < -840 || FixedBrokerUTCMinutes > 840) return INIT_PARAMETERS_INCORRECT;
   if(!TcClockInit()) return INIT_FAILED;
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
   if(!MQLInfoInteger(MQL_TESTER))
   {
      MqlTick liveQuote;if(!SymbolInfoTick(_Symbol,liveQuote))return;
      if(tcLastLiveTick>0 && liveQuote.time-tcLastLiveTick>120) TcStartupReplay();
      tcLastLiveTick=liveQuote.time;
      datetime session=SessionOf(NYNow()),expiry=TcNYToServer(tcResumeSession+86400+3*3600);
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
   Adopt(S1,SessionOf(TcServerToNY(now)));
   // Original order/entry date owns the deadline, even after NY session rollover.
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0 || OrderGetString(ORDER_SYMBOL)!=_Symbol || OrderGetInteger(ORDER_MAGIC)!=MagicC1) continue;
      long type=OrderGetInteger(ORDER_TYPE);
      if(type!=ORDER_TYPE_BUY_STOP && type!=ORDER_TYPE_SELL_STOP)continue;
      datetime setup=(datetime)OrderGetInteger(ORDER_TIME_SETUP);
      datetime expiry=TcNYToServer(SessionOf(TcServerToNY(setup))+86400+3*3600);
      if(now>=expiry) trade.OrderDelete(ticket);
      else if(OrderGetInteger(ORDER_TYPE_TIME)!=ORDER_TIME_SPECIFIED &&
              (SymbolInfoInteger(_Symbol,SYMBOL_EXPIRATION_MODE)&SYMBOL_EXPIRATION_SPECIFIED)!=0)
         trade.OrderModify(ticket,OrderGetDouble(ORDER_PRICE_OPEN),OrderGetDouble(ORDER_SL),
                           OrderGetDouble(ORDER_TP),ORDER_TIME_SPECIFIED,expiry,OrderGetDouble(ORDER_PRICE_STOPLIMIT));
   }
   if(S1.pos_id>0)
   {
      datetime deadline=TcNYToServer(SessionOf(TcServerToNY(S1.entry_srv))+86400+12*3600);
      if(UseNewsFlatten)
      {
         if(!TcNativeNewsValid()) {CloseSleeve(S1,"calendar_unavailable");return;}
         datetime event=EventOn(SessionOf(TcServerToNY(S1.entry_srv))+86400);
         if(event>0 && event>TcServerToNY(S1.entry_srv)) S1.flat_srv=TcNYToServer(event-NewsExitLeadMinutes*60);
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
         int historyState=ready?TcPendingFillState(SessionOf(TcServerToNY(now)),now):-1;
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
