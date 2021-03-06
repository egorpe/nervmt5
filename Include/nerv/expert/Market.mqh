#include <nerv/core.mqh>
#include <nerv/expert/PortfolioElement.mqh>
#include <nerv/enums.mqh>

class nvDeal;

/*
Class: nvMarket

Base class used to represent a market on which currency trader can open/close positions
*/
class nvMarket : public nvPortfolioElement
{
protected:
  // The type of this market
  MarketType _marketType;

  // Currently opened positions:
  nvDeal* _currentDeals[];

  // Positive and negative deals count:
  int _positiveDeals;
  int _negativeDeals;

public:
  /*
    Class constructor.
  */
  nvMarket()
  {
    _marketType = MARKET_TYPE_UNKNOWN;
    _positiveDeals = 0;
    _negativeDeals = 0;
  }

  /*
    Copy constructor
  */
  nvMarket(const nvMarket& rhs)
  {
    this = rhs;
  }

  /*
    assignment operator
  */
  void operator=(const nvMarket& rhs)
  {
    THROW("No copy assignment.")
  }

  /*
    Class destructor.
  */
  ~nvMarket()
  {
    // release the current deals if any:
    nvReleaseObjects(_currentDeals);
  }

  /*
  Function: getPositiveDealCount
  
  Retrieve the number of positive deals
  */
  int getPositiveDealCount()
  {
    return _positiveDeals;
  }
  
  /*
  Function: getNegativeDealCount
  
  Retrieve the number of negative deals
  */
  int getNegativeDealCount()
  {
    return _negativeDeals;
  }
  
  /*
  Function: getMarketType
  
  Retrieve the type of this market
  */
  MarketType getMarketType()
  {
    return _marketType;
  }
  
  /*
  Function: openPosition
  
  Method called to open a position this market for a given symbol.
  Must be reimplemented by derived classes.
  */
  void openPosition(string symbol, ENUM_ORDER_TYPE otype, double lot, double sl = 0.0)
  {
    // Close any previous position on this symbol:
    closePosition(symbol);

    // Create a new deal for this trade opening:
    nvDeal* deal = new nvDeal();
    deal.setCurrencyTrader(getManager().getCurrencyTrader(symbol));
    deal.setMarketType(_marketType);
    deal.setOrderType(otype);
    deal.setLotSize(lot);

    nvPriceManager* pman = getManager().getPriceManager();

    double price = 0.0;
    double point = nvGetPointSize(deal.getSymbol());

    if(deal.getOrderType()==ORDER_TYPE_BUY)
    {
      price = pman.getAskPrice(deal.getSymbol());      
      deal.setStopLossPrice(price-sl*point);
    }
    else {
      price = pman.getBidPrice(deal.getSymbol());      
      deal.setStopLossPrice(price+sl*point);
    }

    deal.setEntryTime(getManager().getCurrentTime());
    deal.setEntryPrice(price);

    deal.open();

    logDEBUG("Opening deal with lotSize="<<deal.getLotSize());
    
    // Perform the actual opening of the position:
    if(doOpenPosition(deal))
    {
      // The deal is opened properly, we keep a reference on it:
      nvAppendArrayElement(_currentDeals,deal);
    }
    else {
      // something went wrong, we discard this deal:
      RELEASE_PTR(deal);
    }
  }
  
  /*
  Function: closePosition
  
  Method called to close a position on a given symbol on that market.
  Must be reimplemented by derived classes.
  */
  virtual void closePosition(string symbol)
  {
    // Check if we have a position on that symbol:
    nvDeal* deal = getCurrentDeal(symbol);
    if(!deal)
    {
      // There is nothing to close.
      return;
    }
    
    nvPriceManager* pman = getManager().getPriceManager();
    
    double price = 0.0;

    if(deal.getOrderType()==ORDER_TYPE_SELL)
    {
      price = pman.getAskPrice(deal.getSymbol());
    }
    else 
    {
      price = pman.getBidPrice(deal.getSymbol());
    }

    deal.setExitTime(getManager().getCurrentTime());
    deal.setExitPrice(price);

    deal.close(); // Needed to update the value of numPoints and profit.

    // Perform the actual close operation if needed.
    doClosePosition(deal);

    // Remove this deal from the list of current positions:
    nvRemoveArrayElement(_currentDeals,deal);

    // We should notify a deal to the currency trader corresponding to that symbol:
    nvCurrencyTrader* ct = getManager().getCurrencyTrader(symbol);
    CHECK(ct,"Invalid currency trader for symbol "<<symbol);
    ct.onDeal(deal); // Now the currency trader will take ownership of that deal.
  }
  
  /*
  Function: doClosePosition
  
  Method called to actually close a position on a given symbol on that market.
  Must be reimplemented by derived classes.
  */
  virtual void doClosePosition(nvDeal* deal)
  {
    THROW("No implementation");
  }

  /*
  Function: doClosePosition
  
  Method called to actually open a position on a given symbol on that market.
  Must be reimplemented by derived classes.
  */
  virtual bool doOpenPosition(nvDeal* deal)
  {
    THROW("No implementation");
    return false;
  }

  /*
  Function: getBalance
  
  Retrieve the current balance on this market in a given currency.
  */
  virtual double getBalance(string currency = "")
  {
    THROW("No implementation");
    return 0.0;
  }

  /*
  Function: getEquity
  
  Method used to compute the current equity on this market, based on the current
  balance value + the open position values in a given quote currency
  */
  virtual double getEquity(string currency = "")
  {
    if(currency=="")
      currency = nvGetAccountCurrency();

    double value = 0.0;
    int num = ArraySize( _currentDeals );
    for(int i=0;i<num;++i) {
      value += _currentDeals[i].getCurrentEquity(currency);
    }

    return getBalance(currency)+value;
  }
  
  /*
  Function: getUsedMargin
  
  Retrieve the current used margin in a given currency
  */
  double getUsedMargin(string currency = "")
  {
    if(currency=="")
      currency = nvGetAccountCurrency();

    double value = 0.0;
    int num = ArraySize( _currentDeals );
    for(int i=0;i<num;++i) {
      value += _currentDeals[i].getUsedMargin(currency);
    }
    
    return value/nvGetAccountLeverage();   
  }
  
  /*
  Function: acknowledgeDeal
  
  Method called by the currency traders to notify its market that a deal 
  is indeed acknowledged
  */
  virtual void acknowledgeDeal(nvDeal* deal)
  {
    // send the current balance value on the socket:
    double val = getBalance();
    // getManager().sendData("Balance updated to: "+(string)val);

    logDEBUG("New balance value: "<<val<<", deal value: "<<deal.getProfit()<<", lotSize:"<<deal.getLotSize());
    logDEBUG("Deal entry price: "<<deal.getEntryPrice()<<" at "<<deal.getEntryTime());
    logDEBUG("Deal exit price: "<<deal.getExitPrice()<<" at "<<deal.getExitTime());
    
    nvBinStream msg;
    msg << (ushort)MSGTYPE_BALANCE_UPDATED;
    msg << (uchar)getMarketType();
    msg << getManager().getCurrentTime();
    msg << val;
    
    getManager().sendData(msg);

    // Count the number of deals:
    if(deal.getProfit()>0.0) {
      _positiveDeals++;
    }
    else {
      _negativeDeals++;
    }
  }
  
  /*
  Function:   
  
  Retrieve the current deal on a given symbol is any.
  */
  nvDeal* getCurrentDeal(string symbol)
  {
    int num = ArraySize(_currentDeals);
    for(int i=0;i<num;++i)
    {
      if(_currentDeals[i].getSymbol()==symbol)
        return _currentDeals[i];
    }

    return NULL;
  }
  
  /*
  Function: getPositionType
  
  Retrieve the current position type on a symbol.
  Must be reimplemented by derived classes.
  */
  PositionType getPositionType(string symbol)
  {
    nvDeal* deal = getCurrentDeal(symbol);
    if(deal)
    {
      return deal.getOrderType()==ORDER_TYPE_BUY ? POS_LONG : POS_SHORT;
    }

    return POS_NONE;
  }
  
  /*
  Function: hasOpenPosition
  
  Method used to check if there is currently an open position for a given symbol on this market.
  */
  bool hasOpenPosition(string symbol)
  {
    return getPositionType(symbol)!=POS_NONE;
  }
  
};
