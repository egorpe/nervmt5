// Include the core files:
#include <nerv/unit/Testing.mqh>
#include <nerv/core.mqh>
#include <nerv/expert/PortfolioManager.mqh>
#include <nerv/expert/agent/IchimokuAgent.mqh>

void OnStart()
{
  nvLogManager* lm = nvLogManager::instance();
  string fname = "portfolio_test_03.log";
  nvFileLogger* logger = new nvFileLogger(fname);
  lm.addSink(logger);

  logDEBUG("Initializing Portfolio test.");

  nvPortfolioManager man;

  // Initial start time:
  // Note: we should not start on the 1st of January:
  // Because there is no trading at that time!
  datetime time = D'2015.01.05 00:00';

  // Note that we must update the portfolio initial time **before**
  // adding the currency traders, otherwise, the first weight updated message
  // timetag could be largely different from the subsequent values.
  man.setCurrentTime(time);

  // Add some currency traders:
  int nsym = 4;
  string symbols[] = {"GBPJPY", "EURUSD", "EURJPY", "USDCHF"};

  for(int j=0;j<nsym;++j)
  {
    nvCurrencyTrader* ct = man.addCurrencyTrader(symbols[j]);
    // We have to stay on the virtual market only for the moment:
    ct.setMarketType(MARKET_TYPE_VIRTUAL);

    nvIchimokuAgent* ichi = new nvIchimokuAgent(ct);
    ichi.setPeriod(PERIOD_H1);

    ct.addTradingAgent(GetPointer(ichi));
  }

  int numDays = 31*2;
  int nsecs = 86400*numDays;
  int nmins = 26*60*numDays;
  for(int i=0;i<nmins;++i) {
    // logDEBUG("Elapsed time: "<<i);
    man.update(time+i*60);
  }

  logDEBUG("Done executing portfolio test.");
}
