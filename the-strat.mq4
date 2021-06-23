//+------------------------------------------------------------------+
//|                                        Heiken Ashi RSI Dance.mq4 |
//|                                                   Suhas Chatekar |
//|                                                 www.chatekar.com |
//+------------------------------------------------------------------+

#import "Kernel32.dll"
void GetSystemTime(int& a0[]);


#property copyright "Copyright � 2021, Chatekar"
#property link      "http://www.chatekar.com"


int gmtoffset;
string gs_548 = "";


// Money management
extern double Lots = 0.01; 		// Basic lot size
extern bool MM  = true;  	// If true - Parabolic SAR based risk sizing
extern int ATR_Period = 20;
extern double ATR_Multiplier = 1;
extern double Risk = 2; // Risk tolerance in percentage points
extern double FixedBalance = 0; // If greater than 0, position size calculator will use it instead of actual account balance.
extern double MoneyRisk = 0; // Risk tolerance in base currency
extern bool UseMoneyInsteadOfPercentage = false;
extern bool UseEquityInsteadOfBalance = true;
extern int LotDigits = 2; // How many digits after dot supported in lot size. For example, 2 for 0.01, 1 for 0.1, 3 for 0.001, etc.




// Miscellaneous
extern string OrderCommentary = "The-Strat";
extern int Slippage = 2; 	// Tolerated slippage in brokers' pips
extern int Magic = 18911040; 	// Order magic number
extern int Profit = 4; // Profit in number of pips

// Global variables

// Common

int CurrentLongTicket = 0;
int CurrentShortTicket = 0;
int PendingLongTicket = 0;
int PendingShortTicket = 0;
int TradingSince = 0;
int LotFactor = 1;


//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int init()
{
   return(0);    
}

//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
int deinit()
{
   return(0);
}

enum CandleType {
    Unset,
    One,
    TwoUp,
    TwoDown,
    Three
};

class Candle {
   private:
      double open, high, low, close, popen, phigh, plow, pclose;
      
   public:
      Candle() {}
      Candle(int period, int index) {
         this.open = iOpen(Symbol(), period, index);
         this.high = iHigh(Symbol(), period,index);
         this.low = iLow(Symbol(), period, index);
         this.close = iClose(Symbol(), period, index);

         this.popen = iOpen(Symbol(), period, index+1);
         this.phigh = iHigh(Symbol(), period,index+1);
         this.plow = iLow(Symbol(), period, index+1);
         this.pclose = iClose(Symbol(), period, index+1);
      }
      
      double GetHigh() { return this.high; }
      double GetLow() { return this.low; }
      double IsGreen() { return this.close >= this.open; }
      double IsRed() { return this.close <= this.open; }
      CandleType GetType(){
          if(this.high < this.phigh && this.low > this.plow) return One;
          if(this.high > this.phigh && this.low > this.plow) return TwoUp;
          if(this.high < this.phigh && this.low < this.plow) return TwoDown;
          if(this.high > this.phigh && this.low < this.plow) return Three;
          return Unset;
      }

      bool TwoUp() { return this.GetType() == TwoUp; }
      bool TwoDown() { return this.GetType() == TwoDown; }
      bool Three() { return this.GetType() == Three; }
      bool One() { return this.GetType() == One; }
      bool HigherHigh() { return this.high > this.phigh; }
      bool HigherLow() { return this.low > this.plow; }
      bool LowerHigh() { return this.high < this.phigh; }
      bool LowerLow() { return this.low < this.plow; }
      
      string ToString() {
         return this.open + "|"  + this.popen + "|" + this.high + "|" + this.phigh + "|" + this.low  + "|" + this.plow  + "|" + this.close  + "|" + this.pclose;
      }
};

int ExitTimeframe = PERIOD_M15;
int TradingTimeframe = PERIOD_M30;
int HTF1 = PERIOD_H1;
int HTF2 = PERIOD_H4;
int HTF3 = PERIOD_D1;
//+------------------------------------------------------------------+
//| Each tick                                                        |
//+------------------------------------------------------------------+
int start()
{
   //return(0);
   if ((!IsConnected()) || ((!MarketInfo(Symbol(), MODE_TRADEALLOWED)) && (!IsTesting()))) return(0);
   
   AttachOrders();
   
   
   if(CurrentLongTicket != 0) {
       if(OrderSelect(CurrentLongTicket, SELECT_BY_TICKET, MODE_TRADES)){
          if((OrderProfit() - OrderCommission()) > 0.01*AccountBalance()){
              OrderClose(CurrentLongTicket, OrderLots(), Bid, 2);
               CurrentLongTicket = 0;
          } 
       }
   } 

   if(CurrentShortTicket != 0){
      if(OrderSelect(CurrentShortTicket, SELECT_BY_TICKET, MODE_TRADES)){
         if((OrderProfit() - OrderCommission()) > 0.01*AccountBalance()){
             OrderClose(CurrentShortTicket, OrderLots(), Ask, 2);
             CurrentShortTicket = 0;
         }
     }
   }
   
   
   Candle c_cur_0 = new Candle(TradingTimeframe, 0);
   Candle c_cur_1 = new Candle(TradingTimeframe, 1);
   Candle c_cur_2 = new Candle(TradingTimeframe, 2);
   Candle c_cur_3 = new Candle(TradingTimeframe, 3);
   Candle c_htf1 = new Candle(HTF1, 0);
   Candle c_htf2 = new Candle(HTF2, 0);
   Candle c_htf3 = new Candle(HTF3, 0);
   
   
   double LotSize = MarketInfo(Symbol(), MODE_LOTSIZE);
   double MinLot = MarketInfo(Symbol(), MODE_MINLOT);
   double LotStep =  MarketInfo(Symbol(), MODE_LOTSTEP);
   double MaxLot =  MarketInfo(Symbol(), MODE_MAXLOT);
   double Spread = Point * MarketInfo(Symbol(), MODE_SPREAD);
   
   
   string ls_52 = "Your Strategy is Running.";
   string ls_76 = "Account Balance= " + DoubleToStr(AccountBalance(), 2);
   string ls_77 = "Long Ticket: " + CurrentLongTicket;
   string ls_78 = "Short Ticket: " + CurrentShortTicket;
   
   string ls_79 = "Lot Size: " + DoubleToStr(LotSize, 5);
   string ls_80 = "Min Lot: " + DoubleToStr(MinLot, 5);
   string ls_81 = "Lot Step: " + DoubleToStr(LotStep, 5);
   string ls_82 = "Max Lot: " + DoubleToStr(MaxLot, 5);
   string ls_83 = " Spread: " + DoubleToStr(Spread, 5);
   
   string ls_84 = "Candle States: " + ToString(c_cur_0.GetType()) + "|" + ToString(c_htf1.GetType()) + "|" + ToString(c_htf2.GetType()) + "|" +ToString(c_htf3.GetType());   
   
   double UnitCost = MarketInfo(Symbol(), MODE_TICKVALUE);
   double TickSize = MarketInfo(Symbol(), MODE_TICKSIZE);
   
   string ls_90 = "Unit Cost: " + DoubleToStr(UnitCost, 5);
   string ls_91 = " Tick Size: " + DoubleToStr(TickSize, 5);
   string ls_92 = "Server Time: " + TimeToStr(TimeCurrent());
   
   Comment("\n",
   "\n", " ",
   "\n", " ",
   "\n", " ", ls_52,
   "\n", " ", ls_76,
   "\n", " ", ls_77,
   "\n", " ", ls_78,
   /*
   "\n", " ", ls_79,
   "\n", " ", ls_80,
   "\n", " ", ls_81,
   "\n", " ", ls_82,
   "\n", " ", ls_83,
   */
   "\n", " ", ls_84,
   "\n", " ", ls_90,
   "\n", " ", ls_91,
   "\n", " ", ls_92,
   "\n");

   /*
   int volume = iVolume(Symbol(), TradingTimeframe, 0);
   if(volume > 1) return(0);
   
   MathSrand(TimeLocal());
   int num = MathRand()%60 + 1;  
   Sleep(num*1000);
   */
   

   /*
   int volume = iVolume(Symbol(), ExitTimeframe, 0);
   if(volume == 1){
   
      Candle c_exit_0 = new Candle(ExitTimeframe, 0);
      
      //Print("M15 Candle:", c_exit_0.ToString(), "Lower Low:", c_exit_0.LowerLow(), "Higher High:", c_exit_0.HigherHigh() );
      
      if(CurrentLongTicket != 0) {
          if(OrderSelect(CurrentLongTicket, SELECT_BY_TICKET, MODE_TRADES)){
             if(OrderCloseTime() > 0){
                  CurrentLongTicket = 0;
             } else if (c_exit_0.LowerLow()){
                  OrderClose(CurrentLongTicket, OrderLots(), Bid, 2);
             } else {
                  OrderModify(CurrentLongTicket, 0, c_cur_1.GetLow(), 0, OrderExpiration());
             }
          }
      } 
   
      if(CurrentShortTicket != 0){
         if(OrderSelect(CurrentShortTicket, SELECT_BY_TICKET, MODE_TRADES)){
            if(OrderCloseTime() > 0) {
               CurrentShortTicket = 0;
            } else if (c_exit_0.HigherHigh()){
                  OrderClose(CurrentShortTicket, OrderLots(), Ask, 2);
             } else {
               OrderModify(CurrentShortTicket, 0, c_cur_1.GetHigh(), 0, OrderExpiration());
            }
        }
      }
      
      delete(&c_exit_0);
   }
   */
  
   /*
   string first = ToString(c_cur_0.GetType());
   string second = ToString(c_cur_1.GetType());
   string third = ToString(c_cur_2.GetType());
   string fourth = ToString(c_cur_3.GetType());

   Print("Candle State - ", fourth, "/", third, "/", second, "/",first);
   Print("c_cur_0 OHLC - ", c_cur_0.ToString());
   Print("c_cur_1 OHLC - ", c_cur_1.ToString());
   */


   double spread = Point * MarketInfo(Symbol(), MODE_SPREAD);
      
   /*
   if(spread > 30) return(0);
   */
   
   double longStopLoss = c_cur_1.GetLow() - CalculateNormalizedDigits() - spread; 
   double shortStopLoss = c_cur_1.GetHigh() + CalculateNormalizedDigits() + spread;
   
   if(CurrentLongTicket == 0 && 
      ((c_htf1.TwoUp() || c_htf1.Three() ) && c_htf1.IsGreen() &&
       (c_htf2.TwoUp() || c_htf2.Three() ) && c_htf2.IsGreen() &&
       (c_htf3.TwoUp() || c_htf3.Three() ) && c_htf3.IsGreen())    ) {
      
         if(c_cur_0.TwoUp()   && c_cur_0.IsGreen() && 
            c_cur_1.TwoDown() && c_cur_1.IsRed()) {
            
              CurrentLongTicket = BuyMarket(longStopLoss, "2-2 Bullish Reversal");
              
          } else if(c_cur_0.TwoUp() && c_cur_0.IsGreen() && (
                     (c_cur_1.One() && c_cur_2.Three() && c_cur_2.IsRed()) ||
                     (c_cur_1.One() && c_cur_2.One()   && c_cur_3.Three() && c_cur_3.IsRed())
                     ) ){
                     
              CurrentLongTicket = BuyMarket(longStopLoss, "3-1-2 Bullish Reversal");
              
          } else if(c_cur_0.TwoUp() && c_cur_0.IsGreen() && 
                    c_cur_1.TwoDown() && c_cur_1.IsGreen() && 
                    c_cur_2.Three() && c_cur_2.IsRed()){
                    
              CurrentLongTicket = BuyMarket(longStopLoss, "3-2-2  Bullish Reversal");
              
          } else if(c_cur_0.TwoUp()   && c_cur_0.IsGreen() &&
                    c_cur_1.One()     && 
                    c_cur_2.TwoDown() && c_cur_2.IsRed() ){
                     
              CurrentLongTicket = BuyMarket(longStopLoss, "2-1-2  Bullish Reversal");
              
          } else if(c_cur_0.TwoUp()  && c_cur_0.IsGreen() &&
                    c_cur_1.Three()  && c_cur_1.IsRed()){
                    
              CurrentLongTicket = BuyMarket(longStopLoss, "3-2 Bullish Reversal");
              
          } else if (c_cur_0.TwoUp()   && c_cur_0.IsGreen() &&
                     c_cur_1.TwoDown() && c_cur_1.IsRed()   &&
                     c_cur_2.One() ) {
          
              CurrentLongTicket = BuyMarket(longStopLoss, "1-2-2 Bullish RevStrat");
          
          }else  if(c_cur_0.TwoUp() && c_cur_0.IsGreen() && 
                    c_cur_1.One()   && 
                    c_cur_2.TwoUp() && c_cur_2.IsGreen() ){
                     
              CurrentLongTicket = BuyMarket(longStopLoss, "2-1-2 Bullish Continuation");
              
          }else if(c_cur_0.IsGreen() && c_cur_0.TwoUp()  && 
                   c_cur_1.IsGreen() && c_cur_1.TwoUp()  && 
                   c_cur_2.IsGreen() && c_cur_2.TwoUp() ){
                   
              CurrentLongTicket = BuyMarket(longStopLoss, "2-2-2 Bullish Continuation");
          }
    } else {
      //Print("NO UPSIDE FTFC OR LONG POSITION ALREADY OPEN");
    }
    
    if(CurrentShortTicket == 0  && 
      ((c_htf1.TwoDown() || c_htf1.Three() ) && c_htf1.IsRed() &&
       (c_htf2.TwoDown() || c_htf2.Three() ) && c_htf2.IsRed() &&
       (c_htf3.TwoDown() || c_htf3.Three() ) && c_htf3.IsRed())   ) {
       
         if(c_cur_0.TwoDown()  && c_cur_0.IsRed() && 
            c_cur_1.TwoUp()    && c_cur_1.IsGreen()) {
            
            CurrentShortTicket = SellMarket(shortStopLoss, "2-2 Bearish Reversal");
           
       } else if(c_cur_0.TwoDown() && c_cur_0.IsRed() && (
                  (c_cur_1.One()                      && c_cur_2.Three()  && c_cur_2.IsGreen()) ||
                  (c_cur_1.One()   && c_cur_2.One()   && c_cur_3.Three()  && c_cur_3.IsGreen()))){
                  
            CurrentShortTicket = SellMarket(shortStopLoss, "3-1-2  Bearish Reversal");
            
       } else if(c_cur_0.TwoDown() && c_cur_0.IsRed() && 
                 c_cur_1.TwoUp() && c_cur_1.IsRed() && 
                 c_cur_2.Three()   && c_cur_2.IsGreen()){
                 
            CurrentShortTicket = SellMarket(shortStopLoss, "3-2-2  Bearish Reversal");
            
       }else if(c_cur_0.TwoDown()&& c_cur_0.IsRed() && 
                c_cur_1.One()    && 
                c_cur_2.TwoUp()  && c_cur_2.IsGreen() ){
                 
            CurrentShortTicket = SellMarket(shortStopLoss, "2-1-2  Bearish Reversal");
            
       } else if(c_cur_0.TwoDown() && c_cur_0.IsRed() && 
                 c_cur_1.Three()   && c_cur_1.IsGreen()){
                 
           CurrentShortTicket = SellMarket(shortStopLoss, "3-2  Bearish Reversal");
           
       } else  if(c_cur_0.TwoDown() && c_cur_0.IsRed() &&  
                  c_cur_1.One()     && 
                  c_cur_2.TwoDown() && c_cur_2.IsRed() ){
                  
            CurrentLongTicket = SellMarket(shortStopLoss, "2-1-2 Bearish Continuation");
              
       } else if(c_cur_0.TwoDown() && c_cur_0.IsRed()   &&
                 c_cur_1.TwoUp()   && c_cur_1.IsGreen() &&
                 c_cur_2.One()) {
          
          CurrentLongTicket = SellMarket(shortStopLoss, "1-2-2 Bearish RevStrat");
       
       }else if(c_cur_0.TwoDown() && c_cur_0.IsRed() &&
                c_cur_1.TwoDown() && c_cur_1.IsRed() && 
                c_cur_2.TwoDown() && c_cur_2.IsRed() ){
                 
           CurrentLongTicket = SellMarket(shortStopLoss, "2-2-2 Bearish Continuation");
       }
    } else {
      //Print("NO DOWNSIDE FTFC OR LONG POSITION ALREADY OPEN");
    }
   
      
    delete(&c_cur_0);
    delete(&c_cur_1);
    delete(&c_cur_2);
    delete(&c_cur_3);
    delete(&c_htf1);
    delete(&c_htf2);
    delete(&c_htf3);
   return(0);
}

string ToString(CandleType type){
   if(type == One) return "1";
   if(type == TwoUp) return "2U";
   if(type == TwoDown) return "2D";
   if(type == Three) return "3";
   return "--";
}

//+------------------------------------------------------------------+
//| Buy                                                              |
//+------------------------------------------------------------------+
int BuyMarket(double stopLoss, string comment)
{
   Print("Sending buy order for ", Symbol());
	EnsureTradeContextIsFree();
	int LongTicket = OrderSend(Symbol(), OP_BUY, LotsOptimized(Ask - stopLoss), Ask, Slippage, stopLoss, 0, comment, Magic, 0, clrGreen);
	if (LongTicket == -1)
	{
	   LongTicket = 0;
		int e = GetLastError();
		Print("Failed sending buy order. Error: ", e);
		if(e == ERR_TRADE_CONTEXT_BUSY) {
		   LongTicket = BuyMarket(stopLoss, comment);
		} else if(e == ERR_NOT_ENOUGH_MONEY){
		   LotFactor = 0.5*LotFactor;
		   LongTicket = BuyMarket(stopLoss, comment);
		}
	} else {
	   LotFactor = 1;
	} 
	
   return LongTicket;
}

//+------------------------------------------------------------------+
//| Sell                                                             |
//+------------------------------------------------------------------+
int SellMarket(double stopLoss, string comment)
{
	Print("Sending sell order for ", Symbol());
	EnsureTradeContextIsFree();
	int ShortTicket = OrderSend(Symbol(), OP_SELL, LotsOptimized(stopLoss - Bid), Bid, Slippage, stopLoss, 0, comment, Magic, 0, clrBrown);
	if (ShortTicket == -1)
	{
	   ShortTicket = 0;
		int e = GetLastError();
		Print("Failed sending sell order. Error: ", e);
		if(e == ERR_TRADE_CONTEXT_BUSY) {
		   ShortTicket = SellMarket(stopLoss, comment);
		} else if(e == ERR_NOT_ENOUGH_MONEY){
		   LotFactor = 0.5*LotFactor;
		   ShortTicket = SellMarket(stopLoss, comment); 
		}
	} else {
	   LotFactor = 1;
	}

   return ShortTicket;
}

int AttachOrders()
{
  int total  = OrdersTotal();
  
  for (int cnt = total-1 ; cnt >= 0 ; cnt--)
  {
    OrderSelect(cnt,SELECT_BY_POS,MODE_TRADES);
    if (OrderMagicNumber() == Magic && OrderSymbol() == Symbol())
    {
      if (OrderType()==OP_BUY)
      {
        CurrentLongTicket = OrderTicket();
      }
      
      if (OrderType()==OP_SELL)
      {
        CurrentShortTicket = OrderTicket();
      }
      
      if (OrderType()==OP_BUYSTOP)
      {
        PendingLongTicket = OrderTicket();
      }
      
      if (OrderType()==OP_SELLSTOP)
      {
        PendingShortTicket = OrderTicket();
      }
    }
  }
  return(0);
}


double CalculateNormalizedDigits()
{
   // If there are 3 or fewer digits (JPY, for example), then return 0.01, which is the pip value.
   if (Digits <= 3){
      return(0.01);
   }
   // If there are 4 or more digits, then return 0.0001, which is the pip value.
   else if (Digits >= 4){
      return(0.0001);
   }
   // In all other cases, return 0.
   else return(0);
}

void EnsureTradeContextIsFree(){
     int StartWaitingTime = GetTickCount();
     // infinite loop
     while(true)
       {
   
         // if it is waited longer than it is specified in the variable named 
         // MaxWaiting_sec, stop operation, as well
         if(GetTickCount() - StartWaitingTime > 30 * 1000) 
           {
             Print("The standby limit (" + 3 + " sec) exceeded!");
             return;
           }
         // if the trade context has become free,
         if(IsTradeAllowed())
           {
             Print("Trade context is free!");
             // refresh the market information
             RefreshRates();            
             break;
           }
         // if no loop breaking condition has been met, "wait" for 0.1 
         // second and then restart checking
         Sleep(500);
       }
}
//+------------------------------------------------------------------+
//| Calculate position size depending on money management parameters.|
//+------------------------------------------------------------------+
double LotsOptimized(double stopLoss)
{
    Print("Stop Loss in points : ", stopLoss);
	if (!MM) return (Lots);

   double Size, RiskMoney, PositionSize = 0;

   if (AccountCurrency() == "") return(0);

   if (FixedBalance > 0)
   {
      Size = FixedBalance;
   }
   else if (UseEquityInsteadOfBalance)
   {
      Size = AccountEquity();
   }
   else
   {
      Size = AccountBalance();
   }

   if (!UseMoneyInsteadOfPercentage) RiskMoney = Size * Risk / 100;
   else RiskMoney = MoneyRisk;

   double UnitCost = MarketInfo(Symbol(), MODE_TICKVALUE);
   double TickSize = MarketInfo(Symbol(), MODE_TICKSIZE);

   if ((stopLoss != 0) && (UnitCost != 0) && (TickSize != 0)) PositionSize = NormalizeDouble(RiskMoney / (stopLoss * UnitCost / TickSize), LotDigits);


   if (PositionSize < MarketInfo(Symbol(), MODE_MINLOT)) PositionSize = MarketInfo(Symbol(), MODE_MINLOT);
   else if (PositionSize > MarketInfo(Symbol(), MODE_MAXLOT)) PositionSize = MarketInfo(Symbol(), MODE_MAXLOT);
   
   
   PositionSize = LotFactor * PositionSize;
   double LotStep =  MarketInfo(Symbol(), MODE_LOTSTEP);
   PositionSize = PositionSize - MathMod(PositionSize, LotStep);
   
   Print("Position Size: ", PositionSize);

   return(PositionSize);

} 
