
#include <nerv/core.mqh>
#include <nerv/math.mqh>
#include <nerv/trade/DigestTraits.mqh>
#include <nerv/trade/HistoryMap.mqh>
#include <nerv/trade/TradePrediction.mqh>
#include <nerv/trade/TradeModelTraits.mqh>
#include <nerv/trade/TradeModel.mqh>
#include <nerv/trade/StrategyTraits.mqh>
#include <nerv/trade/Strategy.mqh>
#include <nerv/trade/TrainContext.mqh>
#include <nerv/trade/CostFunction.mqh>
#include <nerv/trade/StrategyEvaluator.mqh>

nvVecd nv_get_return_prices(int count, string symbol = "EURUSD", ENUM_TIMEFRAMES period = PERIOD_M1, int offset = 0)
{
  double arr[];

  int res = CopyClose(symbol, period, 0+offset, count, arr);
  CHECK(res==count,"Invalid copyclose result: "<<res<<"!="<<count);

  nvVecd cur_prices(arr);

  //logDEBUG("Current price vector is: "<<cur_prices);

  res = CopyClose(symbol, period, 1+offset, count, arr);
  CHECK(res==count,"Invalid copyclose result: "<<res<<"!="<<count);

  nvVecd prev_prices(arr);

  return cur_prices - prev_prices;
}

/* Compute the sharpe ratio for a series of returns.
it is assumed that the returns vector contains at least 2 elements
otherwise an error will be thrown. */
double nv_sharpe_ratio(const nvVecd& rets)
{
  double A = rets.mean();
  double B = rets.norm2()/rets.size();
  return A/sqrt(B-A*A);
}

/* Retrieve the bar duration in seconds depending on the selected period. */
ulong getBarDuration(ENUM_TIMEFRAMES period)
{
  switch (period)
  {
  case PERIOD_M1: return 60;
  case PERIOD_M2: return 60 * 2;
  case PERIOD_M3: return 60 * 3;
  case PERIOD_M4: return 60 * 4;
  case PERIOD_M5: return 60 * 5;
  case PERIOD_M6: return 60 * 6;
  case PERIOD_M10: return 60 * 10;
  case PERIOD_M12: return 60 * 12;
  case PERIOD_M15: return 60 * 15;
  case PERIOD_M20: return 60 * 20;
  case PERIOD_M30: return 60 * 30;
  case PERIOD_H1: return 3600;
  case PERIOD_H2: return 3600 * 2;
  case PERIOD_H3: return 3600 * 3;
  case PERIOD_H4: return 3600 * 4;
  case PERIOD_H6: return 3600 * 6;
  case PERIOD_H8: return 3600 * 8;
  case PERIOD_H12: return 3600 * 12;
  }
 
  THROW("Unsupported period value " << (int)period);
  return 0;
}

double computeMaxDrawnDown(const nvVecd& wealth)
{
  uint num = wealth.size();

  double max_dd, dd, max_val, val;
  max_dd = dd = max_val = 0.0;
  max_val = wealth[0];

  for(uint i =0; i< num;++i)
  {
    val = wealth[i];
    if(val>=max_val) {
      max_dd = MathMax(max_dd,dd);
      // Now use this value as the new max:
      max_val = val;

      // reset the current drawndown:
      dd = 0.0;
    }
    else {
      // value is under the current max
      // we check if it is a bigger drawndown than what we have so far:
      dd = MathMax(dd, max_val - val);
    }
  }

  // Final evaluation step in case we are only going down:
  max_dd = MathMax(max_dd,dd);  

  return max_dd;
}

nvVecd nv_generatePrices(int num, double alpha, double k, double mini = 1.0, double maxi = 1.4)
{
  nvVecd result;

  SimpleRNG rng1;
  SimpleRNG rng2;
  rng2.SetSeed(1234,987654);

  double p = rng1.GetUniform()*10.0; // nv_random_real(1.0,10.0);
  double beta = rng1.GetUniform()*10.0; //nv_random_real(1.0,10.0);

  for(int i=0;i<num;++i)
  {
    p = p + beta + k* rng1.GetNormal();
    beta = alpha * beta + rng2.GetNormal();
    result.push_back(p);
  }
  
  double R = result.max() - result.min();
  result /= R;

  result = result.exp();

  R = result.max() - result.min();
  result -= result.min();
  result *= (maxi - mini)/R;
  result += mini;
  
  return result;
}

nvVecd nv_generate_returns(const nvVecd& prices)
{
  uint size = prices.size();
  CHECK(size >= 2,"Not enough prices to compute returns");
  return prices.subvec(1,size-1) - prices.subvec(0,size-1);;
}
