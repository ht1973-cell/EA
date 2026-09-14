//+------------------------------------------------------------------+
//| GOLD_DPO_Tenzoko_Pyramid.mq5                                    |
//| DPO天底シグナルによるピラミッドEA                                 |
//| エントリー/決済: 天底シグナル、決済時に反対方向エントリー           |
//| SL/トレーリング/ピラミッド: TrendFollow_Pyramid方式                |
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
input group "=== DPO天底インジケーター設定 ==="
input string InpIndicatorName          = "DPO_Tenzoko_signal_1.02"; // インジケーターファイル名
input int    InpDPO_Period             = 20;               // DPO期間
input int    InpDPO_MAType             = 0;                // DPO MA方式 (0=SMA, 1=EMA)
input int    InpMADPO_Period           = 20;               // MADPO期間
input int    InpMADPO_MAType           = 0;                // MADPO MA方式 (0=SMA, 1=EMA)
input int    InpAppliedPrice           = 1;                // 適用価格 (1=CLOSE)
input int    InpMaxCalcBars            = 3000;             // 最大計算バー数
input double InpBB_Sigma              = 2.0;              // BBシグマ倍率
input int    InpBB_Period              = 20;               // BB計算期間
input bool   InpAmpFilterOn           = true;             // 振幅フィルターON
input double InpAmpMultiplier         = 1.0;              // 振幅閾値倍率
input int    InpAmpLookback           = 20;               // 振幅計算期間

input group "=== ピラミッドモード ==="
input ENUM_PYRAMID_MODE InpPyramidMode   = PYRAMID_FIXED;   // ピラミッドモード
input double InpMartinMultiplier         = 1.3;              // マーチン倍率 (MARTIN時)

input group "=== ストップ方式 ==="
input ENUM_STOP_MODE InpStopMode         = STOP_ATR;         // ストップ方式
input int    InpATRPeriod                = 14;               // ATR期間
input ENUM_TIMEFRAMES InpATR_TF          = PERIOD_M30;       // ATR計算タイムフレーム
input double InpInitStopATR              = 2.0;              // 初期SL ATR倍率
input double InpTrailATR                 = 3.0;              // トレール ATR倍率
input int    InpSwingLookback            = 10;               // スイング探索バー数
input double InpSwingBuffer              = 0.002;            // スイングSLバッファ率
input double InpStopPercent              = 1.5;              // SL% (PERCENT時)
input double InpTrailPercent             = 2.0;              // トレール% (PERCENT時)
input int    InpFixedStopPts             = 5000;             // 固定SLポイント
input int    InpFixedTrailPts            = 3000;             // 固定トレールポイント

input group "=== ピラミッド設定 ==="
input int    InpMaxPyramid               = 10;               // 最大ポジション数 (0=無制限)
input double InpAddDistATR               = 1.5;              // 追加最小距離 (ATR倍)
input int    InpAddDistFixedPts          = 3000;             // 追加最小距離 (固定pts)

input group "=== リスク管理 ==="
input double InpRiskPercent              = 1.0;              // 1トレードリスク%
input double InpMaxTotalRiskPct          = 5.0;              // 合計リスク上限%
input double InpMaxDailyLossPct          = 3.0;              // 日次損失上限%
input int    InpMaxSpread                = 50;               // 最大スプレッド (points)

input group "=== その他 ==="
input int    InpMagicNumber              = 20260915;         // マジックナンバー
input int    InpSlippage                 = 50;               // スリッページ (points)

// ── グローバル変数 ──────────────────────────────────
int    g_tenzoko_handle;
int    g_atr_handle;

datetime g_last_signal_bar;
datetime g_last_pyramid_bar;

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

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpSlippage);

   g_tenzoko_handle = iCustom(_Symbol, PERIOD_M30, InpIndicatorName,
                              InpDPO_Period,
                              InpDPO_MAType,
                              InpMADPO_Period,
                              InpMADPO_MAType,
                              InpAppliedPrice,
                              InpMaxCalcBars,
                              InpBB_Sigma,
                              InpBB_Period,
                              InpAmpFilterOn,
                              InpAmpMultiplier,
                              InpAmpLookback,
                              true,            // Inp_CrossAlertOn
                              true,            // Inp_TenzokoAlertOn
                              false,           // Inp_AlertPopup (EA側で制御)
                              false,           // Inp_AlertSound
                              false,           // Inp_AlertEmail
                              false,           // Inp_AlertPush
                              false,           // Inp_AlertDiscord
                              "",              // Inp_DiscordURL
                              false);          // Inp_DiagLog

   if(g_tenzoko_handle == INVALID_HANDLE)
   {
      Print("Error: Failed to create DPO_Tenzoko indicator handle. Error: ", GetLastError());
      return INIT_FAILED;
   }

   g_atr_handle = iATR(_Symbol, InpATR_TF, InpATRPeriod);
   if(g_atr_handle == INVALID_HANDLE)
   {
      Print("Error: Failed to create ATR handle. Error: ", GetLastError());
      return INIT_FAILED;
   }

   g_last_signal_bar    = 0;
   g_last_pyramid_bar   = 0;
   g_pyramid_count      = 0;
   g_last_entry_price   = 0;
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
   if(g_tenzoko_handle != INVALID_HANDLE) IndicatorRelease(g_tenzoko_handle);
   if(g_atr_handle     != INVALID_HANDLE) IndicatorRelease(g_atr_handle);
}

//+------------------------------------------------------------------+
//| OnTick                                                            |
//+------------------------------------------------------------------+
void OnTick()
{
   ResetDailyIfNeeded();
   if(DailyLossLimitHit()) return;

   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(g_atr_handle, 0, 0, 3, atr) < 3) return;
   if(atr[1] <= 0) return;

   int my_pos = CountMyPositions();

   if(my_pos > 0)
   {
      UpdateExtremes();
      UpdateTrailingStop(atr[1]);

      if(IsNewBar(PERIOD_M30, g_last_signal_bar))
      {
         int tenz_signal = DetectTenzokoSignal();

         if(tenz_signal != 0 && tenz_signal != g_position_direction)
         {
            g_closing_by_signal = true;
            CloseAllPositions();
            g_closing_by_signal = false;
            ResetPyramidState();

            if(SpreadOK())
               OpenNewPosition(tenz_signal, atr[1]);

            return;
         }
      }

      bool pyramid_allowed = (InpMaxPyramid == 0) || (my_pos < InpMaxPyramid);
      if(pyramid_allowed && IsNewBar(PERIOD_M30, g_last_pyramid_bar))
         CheckPyramidAdd(atr[1]);
   }
   else
   {
      g_position_direction = 0;

      if(!IsNewBar(PERIOD_M30, g_last_signal_bar)) return;
      if(!SpreadOK()) return;

      int tenz_signal = DetectTenzokoSignal();
      if(tenz_signal == 0) return;

      OpenNewPosition(tenz_signal, atr[1]);
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

//+------------------------------------------------------------------+
//| DetectTenzokoSignal — 天底シグナル検出                            |
//| 戻り値: 1=BUY(底確定), -1=SELL(天井確定), 0=シグナルなし           |
//+------------------------------------------------------------------+
int DetectTenzokoSignal()
{
   double tenz_buy[], tenz_sell[];
   ArraySetAsSeries(tenz_buy, true);
   ArraySetAsSeries(tenz_sell, true);

   if(CopyBuffer(g_tenzoko_handle, 7, 0, 3, tenz_buy) < 3) return 0;
   if(CopyBuffer(g_tenzoko_handle, 8, 0, 3, tenz_sell) < 3) return 0;

   // 確定バー[1]のシグナルを使用（バー[0]は未確定）
   bool has_buy  = (tenz_buy[1]  != EMPTY_VALUE && tenz_buy[1]  != 0);
   bool has_sell = (tenz_sell[1] != EMPTY_VALUE && tenz_sell[1] != 0);

   // 両方同時は稀だが安全側としてBUY優先
   if(has_buy && has_sell)
   {
      Print("Warning: Both Tenzoko BUY and SELL on same bar — BUY priority");
      return 1;
   }

   if(has_buy)  return  1;
   if(has_sell) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| OpenNewPosition — 新規ポジション発注                              |
//+------------------------------------------------------------------+
void OpenNewPosition(int direction, double current_atr)
{
   double sl = CalculateInitialSL(direction, current_atr);
   double entry = (direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                   : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl_dist = MathAbs(entry - sl);
   if(sl_dist < _Point) return;

   double lot = CalculateLot(sl_dist, 0);
   if(lot <= 0) return;

   sl = NormalizeDouble(sl, _Digits);
   if(ExecuteEntry(direction, lot, sl))
   {
      g_position_direction  = direction;
      g_pyramid_count       = 0;
      g_last_entry_price    = entry;
      g_highest_since_entry = (direction == 1)  ? entry : 0;
      g_lowest_since_entry  = (direction == -1) ? entry : DBL_MAX;
   }
}

//+------------------------------------------------------------------+
//| CalculateInitialSL — ストップモードに応じたSL計算                  |
//+------------------------------------------------------------------+
double CalculateInitialSL(int direction, double current_atr)
{
   double entry = (direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                   : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(direction == 1)
   {
      switch(InpStopMode)
      {
         case STOP_ATR:       return entry - current_atr * InpInitStopATR;
         case STOP_SWING:     return FindSwingLevel(direction) - FindSwingLevel(direction) * InpSwingBuffer;
         case STOP_PERCENT:   return entry * (1.0 - InpStopPercent / 100.0);
         case STOP_FIXED_PTS: return entry - InpFixedStopPts * _Point;
      }
   }
   else
   {
      switch(InpStopMode)
      {
         case STOP_ATR:       return entry + current_atr * InpInitStopATR;
         case STOP_SWING:     return FindSwingLevel(direction) + FindSwingLevel(direction) * InpSwingBuffer;
         case STOP_PERCENT:   return entry * (1.0 + InpStopPercent / 100.0);
         case STOP_FIXED_PTS: return entry + InpFixedStopPts * _Point;
      }
   }
   return 0;
}

//+------------------------------------------------------------------+
//| FindSwingLevel — 過去N本のスイングレベル探索                       |
//+------------------------------------------------------------------+
double FindSwingLevel(int direction)
{
   double level = (direction == 1) ? DBL_MAX : 0;

   for(int i = 1; i <= InpSwingLookback; i++)
   {
      if(direction == 1)
      {
         double low_i = iLow(_Symbol, PERIOD_M30, i);
         if(low_i < level) level = low_i;
      }
      else
      {
         double high_i = iHigh(_Symbol, PERIOD_M30, i);
         if(high_i > level) level = high_i;
      }
   }
   return level;
}

//+------------------------------------------------------------------+
//| UpdateExtremes — 最高値/最安値更新                                 |
//+------------------------------------------------------------------+
void UpdateExtremes()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(bid > g_highest_since_entry) g_highest_since_entry = bid;
   if(bid < g_lowest_since_entry)  g_lowest_since_entry  = bid;
}

//+------------------------------------------------------------------+
//| UpdateTrailingStop — 全ポジション共有トレーリングSL               |
//+------------------------------------------------------------------+
void UpdateTrailingStop(double current_atr)
{
   if(g_position_direction == 0) return;

   double new_sl = CalculateTrailSL(current_atr);
   if(new_sl <= 0) return;
   new_sl = NormalizeDouble(new_sl, _Digits);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      double cur_sl = PositionGetDouble(POSITION_SL);

      if(g_position_direction == 1)
      {
         if(new_sl > cur_sl)
            g_trade.PositionModify(ticket, new_sl, 0);
      }
      else
      {
         if(cur_sl <= 0 || new_sl < cur_sl)
            g_trade.PositionModify(ticket, new_sl, 0);
      }
   }
}

//+------------------------------------------------------------------+
//| CalculateTrailSL — トレーリングSL計算                             |
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
//| CheckPyramidAdd — ピラミッド追加判定                              |
//+------------------------------------------------------------------+
void CheckPyramidAdd(double current_atr)
{
   if(!SpreadOK()) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double price = (g_position_direction == 1) ? ask : bid;

   double min_dist;
   if(InpStopMode == STOP_ATR || InpStopMode == STOP_SWING)
      min_dist = current_atr * InpAddDistATR;
   else
      min_dist = InpAddDistFixedPts * _Point;

   double price_dist = MathAbs(price - g_last_entry_price);
   if(price_dist < min_dist) return;

   // 含み益条件
   if(TotalOpenPnL() <= 0) return;

   // 方向確認: ロングなら価格が上昇、ショートなら下降
   if(g_position_direction == 1 && price <= g_last_entry_price) return;
   if(g_position_direction == -1 && price >= g_last_entry_price) return;

   double sl = CalculateInitialSL(g_position_direction, current_atr);
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
      Print("Pyramid add #", g_pyramid_count, " lot=", DoubleToString(lot, 2),
            " price=", DoubleToString(price, _Digits));
   }
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
      ok = g_trade.Buy(lot, _Symbol, 0, sl, 0, "DPO-Tenzoko-Pyr");
   else
      ok = g_trade.Sell(lot, _Symbol, 0, sl, 0, "DPO-Tenzoko-Pyr");

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
      g_position_direction  = dir;
      g_pyramid_count       = count - 1;
      g_last_entry_price    = last_open;
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
