//+------------------------------------------------------------------+
//| GOLD_TrendFollow_Pyramid.mq5                                     |
//| Trend-following pyramid EA with Martin / Fixed lot modes          |
//| Multi-TF: trend on upper TF, entry on lower TF                   |
//+------------------------------------------------------------------+
#property copyright "2026"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

// ── モード列挙 ──────────────────────────────────────
enum ENUM_PYRAMID_MODE
{
   PYRAMID_FIXED  = 0,  // 固定ロット
   PYRAMID_MARTIN = 1   // マーチン（ロット逓増）
};

enum ENUM_STOP_MODE
{
   STOP_ATR       = 0,  // ATRベース
   STOP_SWING     = 1,  // スイングロー/ハイ
   STOP_PERCENT   = 2,  // パーセンテージ
   STOP_FIXED_PTS = 3   // 固定ポイント
};

// ── 入力パラメータ ──────────────────────────────────
input group "=== ピラミッドモード ==="
input ENUM_PYRAMID_MODE InpPyramidMode   = PYRAMID_FIXED;   // ピラミッドモード
input double InpMartinMultiplier         = 1.3;              // マーチン倍率 (MARTIN時)

input group "=== トレンド判定 (上位足) ==="
input ENUM_TIMEFRAMES InpTrendTF         = PERIOD_H1;        // トレンド判定TF
input int    InpFastEMA                  = 20;               // 短期EMA
input int    InpSlowEMA                  = 50;               // 長期EMA

input group "=== エントリー (下位足) ==="
input ENUM_TIMEFRAMES InpEntryTF         = PERIOD_M15;       // エントリーTF
input bool   InpLongOnly                 = false;            // ロング専用

input group "=== ストップ方式 ==="
input ENUM_STOP_MODE InpStopMode         = STOP_SWING;       // ストップ方式
input int    InpATRPeriod                = 14;               // ATR期間
input double InpInitStopATR              = 2.0;              // 初期SL ATR倍率
input double InpTrailATR                 = 3.0;              // トレール ATR倍率
input int    InpSwingLookback            = 10;               // スイング探索バー数
input double InpSwingBuffer              = 0.002;            // スイングSLバッファ率
input double InpStopPercent              = 1.5;              // SL% (PERCENT時)
input double InpTrailPercent             = 2.0;              // トレール% (PERCENT時)
input int    InpFixedStopPts             = 5000;             // 固定SLポイント
input int    InpFixedTrailPts            = 3000;             // 固定トレールポイント

input group "=== ピラミッド設定 ==="
input int    InpMaxAdds                  = 5;                // 最大追加回数
input double InpAddDistATR               = 1.5;              // 追加最小距離 (ATR倍)
input int    InpAddDistFixedPts          = 3000;             // 追加最小距離 (固定pts)

input group "=== リスク管理 ==="
input double InpRiskPercent              = 1.0;              // 1トレードリスク%
input double InpMaxTotalRiskPct          = 5.0;              // 合計リスク上限%
input double InpMaxDailyLossPct          = 3.0;              // 日次損失上限%
input int    InpMaxSpread                = 50;               // 最大スプレッド (points)

input group "=== その他 ==="
input int    InpMagicNumber              = 20260914;         // マジックナンバー
input int    InpSlippage                 = 50;               // スリッページ (points)

// ── グローバル変数 ──────────────────────────────────
int    g_fast_ema_handle;
int    g_slow_ema_handle;
int    g_atr_handle;
int    g_entry_fast_ema_handle;

datetime g_last_trend_bar;
datetime g_last_entry_bar;

int    g_pyramid_count;
double g_last_entry_price;
double g_highest_since_entry;
double g_lowest_since_entry;
int    g_position_direction;  // 1=long, -1=short, 0=flat

double g_daily_start_equity;
datetime g_daily_reset_date;

bool   g_closing_by_signal;

CTrade g_trade;

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_NETTING)
   {
      Print("Error: Netting account not supported for pyramid EA");
      return INIT_FAILED;
   }

   g_fast_ema_handle = iMA(_Symbol, InpTrendTF, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   g_slow_ema_handle = iMA(_Symbol, InpTrendTF, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   g_atr_handle      = iATR(_Symbol, InpTrendTF, InpATRPeriod);
   g_entry_fast_ema_handle = iMA(_Symbol, InpEntryTF, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);

   if(g_fast_ema_handle == INVALID_HANDLE || g_slow_ema_handle == INVALID_HANDLE ||
      g_atr_handle == INVALID_HANDLE || g_entry_fast_ema_handle == INVALID_HANDLE)
   {
      Print("Error: Failed to create indicator handles");
      return INIT_FAILED;
   }

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpSlippage);
   g_trade.SetTypeFilling(ORDER_FILLING_IOC);

   g_last_trend_bar      = 0;
   g_last_entry_bar      = 0;
   g_pyramid_count       = 0;
   g_last_entry_price    = 0;
   g_highest_since_entry = 0;
   g_lowest_since_entry  = DBL_MAX;
   g_position_direction  = 0;
   g_daily_start_equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   g_daily_reset_date    = 0;
   g_closing_by_signal   = false;

   SyncPositionState();

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_fast_ema_handle != INVALID_HANDLE)       IndicatorRelease(g_fast_ema_handle);
   if(g_slow_ema_handle != INVALID_HANDLE)       IndicatorRelease(g_slow_ema_handle);
   if(g_atr_handle != INVALID_HANDLE)            IndicatorRelease(g_atr_handle);
   if(g_entry_fast_ema_handle != INVALID_HANDLE) IndicatorRelease(g_entry_fast_ema_handle);
}

//+------------------------------------------------------------------+
//| OnTick                                                            |
//+------------------------------------------------------------------+
void OnTick()
{
   ResetDailyIfNeeded();
   if(DailyLossLimitHit()) return;

   double fast[3], slow[3], atr[3], entry_ema[3];
   if(CopyBuffer(g_fast_ema_handle, 0, 0, 3, fast) < 3) return;
   if(CopyBuffer(g_slow_ema_handle, 0, 0, 3, slow) < 3) return;
   if(CopyBuffer(g_atr_handle,      0, 0, 3, atr)  < 3) return;
   if(CopyBuffer(g_entry_fast_ema_handle, 0, 0, 3, entry_ema) < 3) return;
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);
   ArraySetAsSeries(atr,  true);
   ArraySetAsSeries(entry_ema, true);

   if(atr[1] <= 0) return;

   int my_pos = CountMyPositions();

   if(my_pos > 0)
   {
      UpdateExtremes();
      UpdateTrailingStop(atr[1]);

      if(IsNewBar(InpTrendTF, g_last_trend_bar))
      {
         int cross = DetectCross(fast, slow);
         if((g_position_direction == 1 && cross == -1) ||
            (g_position_direction == -1 && cross == 1))
         {
            g_closing_by_signal = true;
            CloseAllPositions();
            g_closing_by_signal = false;
            ResetPyramidState();
            return;
         }
      }

      if(my_pos < InpMaxAdds + 1 && IsNewBar(InpEntryTF, g_last_entry_bar))
         CheckPyramidAdd(atr[1]);
   }
   else
   {
      g_position_direction = 0;

      if(!IsNewBar(InpEntryTF, g_last_entry_bar)) return;
      if(!SpreadOK()) return;

      int trend = GetTrendDirection(fast, slow);
      if(trend == 0) return;
      if(InpLongOnly && trend == -1) return;

      double close1 = iClose(_Symbol, InpEntryTF, 1);
      bool entry_confirm = (trend == 1) ? (close1 > entry_ema[1]) : (close1 < entry_ema[1]);
      if(!entry_confirm) return;

      double sl = CalculateInitialSL(trend, atr[1]);
      double entry = (trend == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                  : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl_dist = MathAbs(entry - sl);
      if(sl_dist < _Point) return;

      double lot = CalculateLot(sl_dist, 0);
      if(lot <= 0) return;

      sl = NormalizeDouble(sl, _Digits);
      if(ExecuteEntry(trend, lot, sl))
      {
         g_position_direction  = trend;
         g_pyramid_count       = 0;
         g_last_entry_price    = entry;
         g_highest_since_entry = (trend == 1) ? entry : 0;
         g_lowest_since_entry  = (trend == -1) ? entry : DBL_MAX;
      }
   }
}

//+------------------------------------------------------------------+
//| OnTrade — ストップアウト検知                                       |
//+------------------------------------------------------------------+
void OnTrade()
{
   if(g_closing_by_signal) return;
   if(g_position_direction != 0 && CountMyPositions() == 0)
   {
      Print("StopOut detected — all positions closed by broker");
      ResetPyramidState();
   }
}

// ── ヘルパー関数 ────────────────────────────────────

bool IsNewBar(ENUM_TIMEFRAMES tf, datetime &last)
{
   datetime cur = iTime(_Symbol, tf, 0);
   if(cur == last) return false;
   last = cur;
   return true;
}

int DetectCross(const double &fast[], const double &slow[])
{
   if(fast[1] > slow[1] && fast[2] <= slow[2]) return  1;
   if(fast[1] < slow[1] && fast[2] >= slow[2]) return -1;
   return 0;
}

int GetTrendDirection(const double &fast[], const double &slow[])
{
   if(fast[1] > slow[1]) return  1;
   if(fast[1] < slow[1]) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| CalculateInitialSL — ストップモードに応じたSL計算                  |
//+------------------------------------------------------------------+
double CalculateInitialSL(int direction, double current_atr)
{
   double entry = (direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                   : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   switch(InpStopMode)
   {
      case STOP_ATR:
         return (direction == 1) ? entry - current_atr * InpInitStopATR
                                 : entry + current_atr * InpInitStopATR;

      case STOP_SWING:
      {
         double swing = FindSwingLevel(direction);
         double buffer = swing * InpSwingBuffer;
         return (direction == 1) ? swing - buffer : swing + buffer;
      }

      case STOP_PERCENT:
         return (direction == 1) ? entry * (1.0 - InpStopPercent / 100.0)
                                 : entry * (1.0 + InpStopPercent / 100.0);

      case STOP_FIXED_PTS:
         return (direction == 1) ? entry - InpFixedStopPts * _Point
                                 : entry + InpFixedStopPts * _Point;
   }
   return 0;
}

//+------------------------------------------------------------------+
//| FindSwingLevel — 直近のスイングロー/ハイを探索                      |
//+------------------------------------------------------------------+
double FindSwingLevel(int direction)
{
   if(direction == 1)
   {
      double lowest = DBL_MAX;
      for(int i = 1; i <= InpSwingLookback; i++)
      {
         double lo = iLow(_Symbol, InpEntryTF, i);
         if(lo < lowest) lowest = lo;
      }
      return lowest;
   }
   else
   {
      double highest = 0;
      for(int i = 1; i <= InpSwingLookback; i++)
      {
         double hi = iHigh(_Symbol, InpEntryTF, i);
         if(hi > highest) highest = hi;
      }
      return highest;
   }
}

//+------------------------------------------------------------------+
//| UpdateExtremes — ポジション保持中の最高値/最安値を更新              |
//+------------------------------------------------------------------+
void UpdateExtremes()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid > g_highest_since_entry) g_highest_since_entry = bid;
   if(ask < g_lowest_since_entry)  g_lowest_since_entry  = ask;
}

//+------------------------------------------------------------------+
//| UpdateTrailingStop — 全ポジションのSLを共有トレーリングで更新       |
//+------------------------------------------------------------------+
void UpdateTrailingStop(double current_atr)
{
   double new_sl = 0;

   if(g_position_direction == 1)
   {
      switch(InpStopMode)
      {
         case STOP_ATR:       new_sl = g_highest_since_entry - current_atr * InpTrailATR; break;
         case STOP_SWING:     new_sl = g_highest_since_entry * (1.0 - InpStopPercent / 100.0); break;
         case STOP_PERCENT:   new_sl = g_highest_since_entry * (1.0 - InpTrailPercent / 100.0); break;
         case STOP_FIXED_PTS: new_sl = g_highest_since_entry - InpFixedTrailPts * _Point; break;
      }
   }
   else if(g_position_direction == -1)
   {
      switch(InpStopMode)
      {
         case STOP_ATR:       new_sl = g_lowest_since_entry + current_atr * InpTrailATR; break;
         case STOP_SWING:     new_sl = g_lowest_since_entry * (1.0 + InpStopPercent / 100.0); break;
         case STOP_PERCENT:   new_sl = g_lowest_since_entry * (1.0 + InpTrailPercent / 100.0); break;
         case STOP_FIXED_PTS: new_sl = g_lowest_since_entry + InpFixedTrailPts * _Point; break;
      }
   }

   new_sl = NormalizeDouble(new_sl, _Digits);
   if(new_sl <= 0) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      double cur_sl = PositionGetDouble(POSITION_SL);

      if(g_position_direction == 1 && new_sl > cur_sl && new_sl < SymbolInfoDouble(_Symbol, SYMBOL_BID))
         g_trade.PositionModify(ticket, new_sl, 0);
      else if(g_position_direction == -1 && (cur_sl == 0 || new_sl < cur_sl) && new_sl > SymbolInfoDouble(_Symbol, SYMBOL_ASK))
         g_trade.PositionModify(ticket, new_sl, 0);
   }
}

//+------------------------------------------------------------------+
//| CheckPyramidAdd — ピラミッド追加判定                               |
//+------------------------------------------------------------------+
void CheckPyramidAdd(double current_atr)
{
   if(!SpreadOK()) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double price = (g_position_direction == 1) ? ask : bid;

   double min_dist = (InpStopMode == STOP_FIXED_PTS || InpStopMode == STOP_PERCENT)
                     ? InpAddDistFixedPts * _Point
                     : current_atr * InpAddDistATR;

   bool dist_ok = false;
   if(g_position_direction == 1)
      dist_ok = (price >= g_last_entry_price + min_dist);
   else
      dist_ok = (price <= g_last_entry_price - min_dist);

   if(!dist_ok) return;
   if(TotalOpenPnL() <= 0) return;

   double sl = CalculateTrailSL(current_atr);
   double sl_dist = MathAbs(price - sl);
   if(sl_dist < _Point) return;

   int level = g_pyramid_count + 1;
   double lot = CalculateLot(sl_dist, level);
   if(lot <= 0) return;

   if(!RiskCapCheck(lot, sl_dist)) return;

   sl = NormalizeDouble(sl, _Digits);
   if(ExecuteEntry(g_position_direction, lot, sl))
   {
      g_pyramid_count++;
      g_last_entry_price = price;
   }
}

//+------------------------------------------------------------------+
//| CalculateTrailSL — 現在のトレール位置をSLとして返す                 |
//+------------------------------------------------------------------+
double CalculateTrailSL(double current_atr)
{
   if(g_position_direction == 1)
   {
      switch(InpStopMode)
      {
         case STOP_ATR:       return g_highest_since_entry - current_atr * InpTrailATR;
         case STOP_SWING:     return g_highest_since_entry * (1.0 - InpStopPercent / 100.0);
         case STOP_PERCENT:   return g_highest_since_entry * (1.0 - InpTrailPercent / 100.0);
         case STOP_FIXED_PTS: return g_highest_since_entry - InpFixedTrailPts * _Point;
      }
   }
   else
   {
      switch(InpStopMode)
      {
         case STOP_ATR:       return g_lowest_since_entry + current_atr * InpTrailATR;
         case STOP_SWING:     return g_lowest_since_entry * (1.0 + InpStopPercent / 100.0);
         case STOP_PERCENT:   return g_lowest_since_entry * (1.0 + InpTrailPercent / 100.0);
         case STOP_FIXED_PTS: return g_lowest_since_entry + InpFixedTrailPts * _Point;
      }
   }
   return 0;
}

//+------------------------------------------------------------------+
//| CalculateLot — リスクベースのロット計算                             |
//+------------------------------------------------------------------+
double CalculateLot(double sl_distance, int level)
{
   double equity    = AccountInfoDouble(ACCOUNT_EQUITY);
   double risk_cash = equity * InpRiskPercent / 100.0;
   double tick_val  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if(tick_val <= 0 || tick_size <= 0 || sl_distance <= 0) return 0;

   double base_lot = (risk_cash * tick_size) / (sl_distance * tick_val);

   if(InpPyramidMode == PYRAMID_MARTIN && level > 0)
      base_lot *= MathPow(InpMartinMultiplier, level);

   double min_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(lot_step <= 0) lot_step = 0.01;
   base_lot = MathFloor(base_lot / lot_step) * lot_step;
   if(base_lot < min_lot) base_lot = min_lot;
   if(base_lot > max_lot) base_lot = max_lot;

   return NormalizeDouble(base_lot, 2);
}

//+------------------------------------------------------------------+
//| RiskCapCheck — 合計リスクが上限内か確認                             |
//+------------------------------------------------------------------+
bool RiskCapCheck(double add_lot, double add_sl_dist)
{
   double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
   double tick_val = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size= SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_val <= 0 || tick_size <= 0) return false;

   double existing_risk = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      double pos_sl   = PositionGetDouble(POSITION_SL);
      double pos_open = PositionGetDouble(POSITION_PRICE_OPEN);
      double pos_lot  = PositionGetDouble(POSITION_VOLUME);
      double dist     = MathAbs(pos_open - pos_sl);
      existing_risk  += (dist * pos_lot * tick_val) / tick_size;
   }

   double add_risk = (add_sl_dist * add_lot * tick_val) / tick_size;
   double total_risk_pct = ((existing_risk + add_risk) / equity) * 100.0;

   if(total_risk_pct > InpMaxTotalRiskPct)
   {
      Print("Pyramid add rejected: total risk ", DoubleToString(total_risk_pct, 1),
            "% > cap ", DoubleToString(InpMaxTotalRiskPct, 1), "%");
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| ExecuteEntry — 安全な注文送信                                       |
//+------------------------------------------------------------------+
bool ExecuteEntry(int direction, double lot, double sl)
{
   ResetLastError();
   bool ok = false;

   if(direction == 1)
      ok = g_trade.Buy(lot, _Symbol, 0, sl, 0, "TF-Pyramid");
   else
      ok = g_trade.Sell(lot, _Symbol, 0, sl, 0, "TF-Pyramid");

   if(!ok || g_trade.ResultRetcode() != TRADE_RETCODE_DONE)
   {
      Print("OrderSend failed: ", g_trade.ResultRetcode(), " / ",
            g_trade.ResultComment(), " / Error: ", GetLastError());
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| CloseAllPositions — 全ポジション決済                                |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      g_trade.PositionClose(ticket);
   }
}

//+------------------------------------------------------------------+
//| CountMyPositions                                                   |
//+------------------------------------------------------------------+
int CountMyPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| TotalOpenPnL — 自ポジション合計損益                                |
//+------------------------------------------------------------------+
double TotalOpenPnL()
{
   double pnl = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      pnl += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return pnl;
}

//+------------------------------------------------------------------+
//| SyncPositionState — 再起動時にポジション状態を復元                  |
//+------------------------------------------------------------------+
void SyncPositionState()
{
   int count = 0;
   double last_open = 0;
   int dir = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      count++;
      long type = PositionGetInteger(POSITION_TYPE);
      dir = (type == POSITION_TYPE_BUY) ? 1 : -1;

      double op = PositionGetDouble(POSITION_PRICE_OPEN);
      if(last_open == 0 || (dir == 1 && op > last_open) || (dir == -1 && op < last_open))
         last_open = op;
   }

   if(count > 0)
   {
      g_position_direction = dir;
      g_pyramid_count      = count - 1;
      g_last_entry_price   = last_open;
      g_highest_since_entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      g_lowest_since_entry  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   }
}

//+------------------------------------------------------------------+
//| ResetPyramidState                                                  |
//+------------------------------------------------------------------+
void ResetPyramidState()
{
   g_pyramid_count       = 0;
   g_last_entry_price    = 0;
   g_highest_since_entry = 0;
   g_lowest_since_entry  = DBL_MAX;
   g_position_direction  = 0;
}

//+------------------------------------------------------------------+
//| SpreadOK                                                           |
//+------------------------------------------------------------------+
bool SpreadOK()
{
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return (spread <= InpMaxSpread);
}

//+------------------------------------------------------------------+
//| ResetDailyIfNeeded — 日次損失カウンタのリセット                     |
//+------------------------------------------------------------------+
void ResetDailyIfNeeded()
{
   MqlDateTime now;
   TimeCurrent(now);
   datetime today = StringToTime(IntegerToString(now.year) + "." +
                                 IntegerToString(now.mon)  + "." +
                                 IntegerToString(now.day));
   if(today != g_daily_reset_date)
   {
      g_daily_start_equity = AccountInfoDouble(ACCOUNT_EQUITY);
      g_daily_reset_date   = today;
   }
}

//+------------------------------------------------------------------+
//| DailyLossLimitHit                                                  |
//+------------------------------------------------------------------+
bool DailyLossLimitHit()
{
   if(InpMaxDailyLossPct <= 0) return false;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double loss_pct = ((g_daily_start_equity - equity) / g_daily_start_equity) * 100.0;
   if(loss_pct >= InpMaxDailyLossPct)
   {
      if(CountMyPositions() > 0)
      {
         Print("Daily loss limit hit: ", DoubleToString(loss_pct, 1), "%");
         g_closing_by_signal = true;
         CloseAllPositions();
         g_closing_by_signal = false;
         ResetPyramidState();
      }
      return true;
   }
   return false;
}
//+------------------------------------------------------------------+
