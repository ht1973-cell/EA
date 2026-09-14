//+------------------------------------------------------------------+
//| GOLD_EMA_CrossoverJ.mq5                                         |
//| GOLD日足EMA20/50クロス トレンドフォローEA                          |
//| Variant J (ロング専用/4ATRトレール/再エントリー) をベースに         |
//| Variant K (ピラミッディング/共有トレーリングストップ) を切替可能      |
//|                                                                  |
//| バックテスト結果(OOS 2020-2026):                                  |
//|   J: PF 2.95, CAGR 8.15%, MaxDD 6.9%, Exp +0.71R                |
//|   K: PF 3.38, CAGR 15.51%, MaxDD 11.5%, Exp +1.32R              |
//+------------------------------------------------------------------+
#property copyright "EMA Crossover J/K - Backtest-Verified"
#property version   "1.00"
#property strict

//--- 入力パラメータ: エントリー設定
input group "=== エントリー設定 ==="
input int    InpFastEMA        = 20;      // 短期EMA期間
input int    InpSlowEMA        = 50;      // 長期EMA期間
input int    InpATRPeriod      = 14;      // ATR期間 (Wilder平滑)
input bool   InpLongOnly       = true;    // ロング専用モード

//--- 入力パラメータ: リスク管理
input group "=== リスク管理 ==="
input double InpInitStopATR    = 2.0;     // 初期SL: ATR倍率
input double InpTrailATR       = 4.0;     // トレーリング: ATR倍率
input double InpRiskPercent    = 1.0;     // リスク%(口座比率)
input bool   InpEnableReentry  = true;    // 再エントリー機能

//--- 入力パラメータ: ピラミッディング (Variant K)
input group "=== ピラミッディング ==="
input bool   InpEnablePyramid  = false;   // ピラミッディング有効化
input int    InpMaxAdds        = 3;       // 最大追加回数
input double InpAddATR         = 1.5;     // 追加条件: ATR移動量
input double InpRiskCapPct     = 3.0;     // 合計リスク上限%

//--- 入力パラメータ: システム
input group "=== システム ==="
sinput long  InpMagicNumber    = 20260912; // マジックナンバー
input int    InpSlippage       = 50;       // スリッページ(points)

//--- グローバル変数: 指標ハンドル
int g_fast_ema_handle = INVALID_HANDLE;
int g_slow_ema_handle = INVALID_HANDLE;
int g_atr_handle      = INVALID_HANDLE;

//--- グローバル変数: 状態管理
datetime g_last_bar_time     = 0;
double   g_highest_high      = 0;       // ロングポジション中の最高値
double   g_lowest_low        = 0;       // ショートポジション中の最安値
double   g_last_entry_price  = 0;       // 直近エントリー価格
double   g_base_lot          = 0;       // 初回ロットサイズ
int      g_unit_count        = 0;       // 現在のユニット数 (ピラミッド含む)
bool     g_was_stopped       = false;   // 直前がストップアウトか
bool     g_had_position      = false;   // 前バーでポジションを持っていたか
bool     g_closing_by_cross  = false;   // クロスによるクローズ中フラグ

//+------------------------------------------------------------------+
//| OnInit: ハンドル生成・パラメータ検証                               |
//+------------------------------------------------------------------+
int OnInit()
{
   if(StringFind(_Symbol, "XAU") < 0 && StringFind(_Symbol, "GOLD") < 0)
      Print("警告: GOLD(XAUUSD)以外のシンボルです: ", _Symbol);

   if(InpFastEMA >= InpSlowEMA)
   {
      Alert("短期EMA期間は長期EMA期間より小さくしてください");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(InpRiskPercent <= 0 || InpRiskPercent > 10)
   {
      Alert("InpRiskPercentが不正(0〜10%): ", InpRiskPercent);
      return INIT_PARAMETERS_INCORRECT;
   }

   g_fast_ema_handle = iMA(_Symbol, PERIOD_D1, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   g_slow_ema_handle = iMA(_Symbol, PERIOD_D1, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   g_atr_handle      = iATR(_Symbol, PERIOD_D1, InpATRPeriod);

   if(g_fast_ema_handle == INVALID_HANDLE ||
      g_slow_ema_handle == INVALID_HANDLE ||
      g_atr_handle      == INVALID_HANDLE)
   {
      Alert("指標ハンドル作成失敗! EA停止");
      return INIT_FAILED;
   }

   double dummy[1];
   int wait = 0;
   while(CopyBuffer(g_atr_handle, 0, 0, 1, dummy) < 1)
   {
      if(++wait > 200) { Alert("指標データ取得タイムアウト"); return INIT_FAILED; }
      Sleep(50);
   }

   Print("OnInit完了 Symbol=", _Symbol, " Period=D1 Magic=", InpMagicNumber,
         " Mode=", InpEnablePyramid ? "Variant K (Pyramid)" : "Variant J");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit: リソース解放                                             |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_fast_ema_handle != INVALID_HANDLE) { IndicatorRelease(g_fast_ema_handle); g_fast_ema_handle = INVALID_HANDLE; }
   if(g_slow_ema_handle != INVALID_HANDLE) { IndicatorRelease(g_slow_ema_handle); g_slow_ema_handle = INVALID_HANDLE; }
   if(g_atr_handle      != INVALID_HANDLE) { IndicatorRelease(g_atr_handle);      g_atr_handle      = INVALID_HANDLE; }

   Print("OnDeinit: ハンドル解放完了 reason=", reason);
}

//+------------------------------------------------------------------+
//| OnTick: メインループ (日足バー確定時のみ処理)                       |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!IsNewBar()) return;

   // 指標値取得: [0]=形成中, [1]=直前確定, [2]=その前
   double ema_fast[3], ema_slow[3], atr_buf[3];
   ArraySetAsSeries(ema_fast, true);
   ArraySetAsSeries(ema_slow, true);
   ArraySetAsSeries(atr_buf,  true);

   if(CopyBuffer(g_fast_ema_handle, 0, 0, 3, ema_fast) < 3) return;
   if(CopyBuffer(g_slow_ema_handle, 0, 0, 3, ema_slow) < 3) return;
   if(CopyBuffer(g_atr_handle,      0, 0, 3, atr_buf)  < 3) return;

   double atr = atr_buf[1];
   if(atr <= 0) return;

   int pos_count = CountMyPositions();
   bool have_pos = (pos_count > 0);

   // トレーリングストップ更新 (ポジション保有時)
   if(have_pos)
      UpdateTrailingStop(atr);

   // EMAクロスシグナル判定 (確定バー[1]と[2]を比較)
   int cross_sig = DetectCrossSignal(ema_fast, ema_slow);

   // 反対クロスでエグジット
   if(have_pos && cross_sig != 0)
   {
      int pos_dir = GetPositionDirection();
      if(pos_dir != 0 && pos_dir != cross_sig)
      {
         g_closing_by_cross = true;
         CloseAllPositions("EMA Cross Exit");
         g_closing_by_cross = false;
         have_pos = false;
         pos_count = 0;
         g_was_stopped = false;
         g_unit_count = 0;
      }
   }

   // ピラミッディング (ポジション保有中・クロスシグルなし・ピラミッド有効時)
   if(have_pos && InpEnablePyramid && cross_sig == 0)
      CheckPyramidAdd(atr, ema_fast[1], ema_slow[1]);

   // 新規エントリー (ポジションなし)
   if(!have_pos)
   {
      // クロスシグナル
      if(cross_sig != 0)
      {
         if(InpLongOnly && cross_sig < 0)
         {
            g_had_position = false;
            return;
         }
         ExecuteEntry(cross_sig, atr);
         g_was_stopped = false;
      }
      // 再エントリー (クロスなし、直前ストップアウト後)
      else if(InpEnableReentry && g_was_stopped)
      {
         int reentry_sig = DetectReentrySignal(ema_fast, ema_slow);
         if(reentry_sig != 0)
         {
            if(InpLongOnly && reentry_sig < 0)
            {
               g_had_position = false;
               return;
            }
            ExecuteEntry(reentry_sig, atr);
            g_was_stopped = false;
         }
      }
   }

   g_had_position = (CountMyPositions() > 0);
}

//+------------------------------------------------------------------+
//| 新規バー検出 (D1)                                                 |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime current = iTime(_Symbol, PERIOD_D1, 0);
   if(current == g_last_bar_time) return false;
   g_last_bar_time = current;
   return true;
}

//+------------------------------------------------------------------+
//| EMAクロスシグナル検出                                              |
//| Python: ef[i] > es[i] and ef[i-1] <= es[i-1] → bull cross        |
//| MQL5:   ema_fast[1] > ema_slow[1] && ema_fast[2] <= ema_slow[2]  |
//+------------------------------------------------------------------+
int DetectCrossSignal(const double &fast[], const double &slow[])
{
   if(fast[1] > slow[1] && fast[2] <= slow[2]) return  1;  // ゴールデンクロス
   if(fast[1] < slow[1] && fast[2] >= slow[2]) return -1;  // デッドクロス
   return 0;
}

//+------------------------------------------------------------------+
//| 再エントリーシグナル検出                                           |
//| Python: ef[i] > es[i] and c[i] > ef[i] and c[i-1] <= ef[i-1]     |
//| MQL5: fast[1] > slow[1] and close[1] > fast[1] and close[2] <= fast[2] |
//+------------------------------------------------------------------+
int DetectReentrySignal(const double &fast[], const double &slow[])
{
   double close1 = iClose(_Symbol, PERIOD_D1, 1);
   double close2 = iClose(_Symbol, PERIOD_D1, 2);

   // ロング再エントリー: EMA bullish alignment + close crosses above fast EMA
   if(fast[1] > slow[1] && close1 > fast[1] && close2 <= fast[2])
      return 1;

   // ショート再エントリー: EMA bearish alignment + close crosses below fast EMA
   if(fast[1] < slow[1] && close1 < fast[1] && close2 >= fast[2])
      return -1;

   return 0;
}

//+------------------------------------------------------------------+
//| エントリー実行                                                     |
//+------------------------------------------------------------------+
void ExecuteEntry(int direction, double atr)
{
   double lot = CalculateLot(InpRiskPercent, atr);
   if(lot <= 0) return;

   double price, sl;
   double stop_dist = InpInitStopATR * atr;

   if(direction > 0)
   {
      price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      sl    = NormalizeDouble(price - stop_dist, _Digits);
   }
   else
   {
      price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      sl    = NormalizeDouble(price + stop_dist, _Digits);
   }

   if(SendOrderSafe(direction > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                     price, sl, 0, lot, "Entry"))
   {
      g_base_lot        = lot;
      g_last_entry_price = price;
      g_unit_count      = 1;
      g_highest_high    = (direction > 0) ? iHigh(_Symbol, PERIOD_D1, 1) : 0;
      g_lowest_low      = (direction < 0) ? iLow(_Symbol, PERIOD_D1, 1) : 0;
      g_was_stopped     = false;
   }
}

//+------------------------------------------------------------------+
//| ピラミッディング追加判定                                           |
//| 条件: close >= last_entry + 1.5 ATR (有利方向) AND ポジション利益 > 0 |
//| ストップ: 共有トレーリングストップ (add_stop_atr=None)              |
//+------------------------------------------------------------------+
void CheckPyramidAdd(double atr, double ema_fast, double ema_slow)
{
   if(g_unit_count >= 1 + InpMaxAdds) return;
   if(g_unit_count == 0) return;

   int pos_dir = GetPositionDirection();
   if(pos_dir == 0) return;

   double close1 = iClose(_Symbol, PERIOD_D1, 1);

   // 有利方向にATR*InpAddATR以上動いているか
   double move = (close1 - g_last_entry_price) * pos_dir;
   if(move < InpAddATR * atr) return;

   // ポジション全体が利益になっているか
   double total_pnl = TotalOpenPnL();
   if(total_pnl <= 0) return;

   // ロット逓減: 1.0/0.7/0.5/0.3
   double lot_ratios[] = {1.0, 0.7, 0.5, 0.3};
   int idx = MathMin(g_unit_count, 3);
   double lot = NormalizeDouble(g_base_lot * lot_ratios[idx], 2);
   double lot_min = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lot_max = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathFloor(lot / lot_step) * lot_step;
   lot = MathMax(lot_min, MathMin(lot_max, lot));

   // 共有トレーリングストップ: extreme - trail_mult * ATR
   double sl;
   double price;
   if(pos_dir > 0)
   {
      price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      sl = NormalizeDouble(g_highest_high - InpTrailATR * atr, _Digits);
   }
   else
   {
      price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      sl = NormalizeDouble(g_lowest_low + InpTrailATR * atr, _Digits);
   }

   // リスク上限チェック
   double current_risk = CalculateTotalRisk();
   double new_unit_risk = MathAbs(price - sl) * lot *
                          SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) /
                          SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double max_risk = AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskCapPct / 100.0;

   if(current_risk + new_unit_risk > max_risk)
   {
      Print("ピラミッド: リスク上限超過 現在=", current_risk,
            " 追加=", new_unit_risk, " 上限=", max_risk);
      return;
   }

   ENUM_ORDER_TYPE otype = (pos_dir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(SendOrderSafe(otype, price, sl, 0, lot,
      "Pyramid_" + IntegerToString(g_unit_count + 1)))
   {
      g_last_entry_price = price;
      g_unit_count++;
      Print("ピラミッド追加成功 #", g_unit_count, " lot=", lot, " sl=", sl);
   }
}

//+------------------------------------------------------------------+
//| トレーリングストップ更新                                           |
//| Python: extreme = max(extreme, high[i])                           |
//|         trail = extreme - dir * trail_mult * atr                  |
//|         stop = max(stop, trail) [ロング: 上方向のみ]                |
//| 全ユニットに同一の共有トレーリングストップを適用                     |
//+------------------------------------------------------------------+
void UpdateTrailingStop(double atr)
{
   int pos_dir = GetPositionDirection();
   if(pos_dir == 0) return;

   // 直前確定バーのhigh/lowでextremeを更新
   double high1 = iHigh(_Symbol, PERIOD_D1, 1);
   double low1  = iLow(_Symbol, PERIOD_D1, 1);

   if(pos_dir > 0)
      g_highest_high = MathMax(g_highest_high, high1);
   else
      g_lowest_low = (g_lowest_low == 0) ? low1 : MathMin(g_lowest_low, low1);

   // 新しいトレーリングストップを計算
   double new_trail;
   if(pos_dir > 0)
      new_trail = NormalizeDouble(g_highest_high - InpTrailATR * atr, _Digits);
   else
      new_trail = NormalizeDouble(g_lowest_low + InpTrailATR * atr, _Digits);

   // 全ポジションに適用 (上方のみ = ratchet)
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)       continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

      double current_sl = PositionGetDouble(POSITION_SL);
      double current_tp = PositionGetDouble(POSITION_TP);

      if(pos_dir > 0)
      {
         if(new_trail > current_sl + _Point * 5)
            ModifyPosition(ticket, new_trail, current_tp);
      }
      else
      {
         if(current_sl == 0 || new_trail < current_sl - _Point * 5)
            ModifyPosition(ticket, new_trail, current_tp);
      }
   }
}

//+------------------------------------------------------------------+
//| 全ポジションクローズ                                               |
//+------------------------------------------------------------------+
void CloseAllPositions(string reason)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)       continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

      long pos_type = PositionGetInteger(POSITION_TYPE);
      double lot    = PositionGetDouble(POSITION_VOLUME);
      double price;

      if(pos_type == POSITION_TYPE_BUY)
         price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      else
         price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      MqlTradeRequest req = {};
      MqlTradeResult  res = {};
      req.action       = TRADE_ACTION_DEAL;
      req.position     = ticket;
      req.symbol       = _Symbol;
      req.volume       = lot;
      req.type         = (pos_type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      req.price        = price;
      req.deviation    = InpSlippage;
      req.magic        = InpMagicNumber;
      req.comment      = reason;
      req.type_filling = GetFillingType();

      ResetLastError();
      if(!OrderSend(req, res) || res.retcode != TRADE_RETCODE_DONE)
         Print("クローズ失敗 ticket=", ticket, " code=", res.retcode,
               " err=", GetLastError());
      else
         Print("クローズ成功 ticket=", ticket, " reason=", reason);
   }

   g_unit_count = 0;
   g_highest_high = 0;
   g_lowest_low = 0;
}

//+------------------------------------------------------------------+
//| 安全なOrderSend (SL/TP最低距離チェック付き)                        |
//+------------------------------------------------------------------+
bool SendOrderSafe(ENUM_ORDER_TYPE type, double price,
                   double sl, double tp, double lot, string comment)
{
   long stop_pts = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double min_dist = (stop_pts + 5) * _Point;

   if(type == ORDER_TYPE_BUY)
   {
      if(price - sl < min_dist)
         sl = NormalizeDouble(price - min_dist, _Digits);
      if(tp > 0 && tp - price < min_dist)
         tp = NormalizeDouble(price + min_dist, _Digits);
   }
   else
   {
      if(sl - price < min_dist)
         sl = NormalizeDouble(price + min_dist, _Digits);
      if(tp > 0 && price - tp < min_dist)
         tp = NormalizeDouble(price - min_dist, _Digits);
   }

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.action       = TRADE_ACTION_DEAL;
   req.symbol       = _Symbol;
   req.volume       = lot;
   req.type         = type;
   req.price        = price;
   req.sl           = sl;
   req.tp           = tp;
   req.deviation    = InpSlippage;
   req.magic        = InpMagicNumber;
   req.comment      = comment;
   req.type_filling = GetFillingType();

   ResetLastError();
   bool ok = OrderSend(req, res);

   if(!ok || res.retcode != TRADE_RETCODE_DONE)
   {
      Print("OrderSend失敗: retcode=", res.retcode,
            " comment=", res.comment, " err=", GetLastError());
      return false;
   }

   Print("発注成功: ", EnumToString(type), " lot=", lot,
         " price=", price, " SL=", sl, " TP=", tp);
   return true;
}

//+------------------------------------------------------------------+
//| ポジション修正 (SL/TP)                                            |
//+------------------------------------------------------------------+
bool ModifyPosition(ulong ticket, double sl, double tp)
{
   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.action   = TRADE_ACTION_SLTP;
   req.position = ticket;
   req.symbol   = _Symbol;
   req.sl       = sl;
   req.tp       = tp;

   ResetLastError();
   if(!OrderSend(req, res))
   {
      Print("SL修正失敗 ticket=", ticket, " code=", GetLastError());
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Filling方式自動検出                                                |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING GetFillingType()
{
   uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
   if((filling & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}

//+------------------------------------------------------------------+
//| ロットサイズ計算 (リスクベース: ATR*InitStopATR = SL距離)           |
//+------------------------------------------------------------------+
double CalculateLot(double risk_pct, double atr)
{
   double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
   double risk_amt = equity * risk_pct / 100.0;

   double tick_val  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_sz   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double lot_min   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lot_max   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lot_step  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   double sl_dist = atr * InpInitStopATR;
   if(sl_dist <= 0 || tick_val <= 0 || tick_sz <= 0) return lot_min;

   double lot = risk_amt / ((sl_dist / tick_sz) * tick_val);
   lot = MathFloor(lot / lot_step) * lot_step;
   lot = MathMax(lot_min, MathMin(lot_max, lot));

   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
//| ポジション数カウント (マジックナンバー+シンボルフィルタ)            |
//+------------------------------------------------------------------+
int CountMyPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)       continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| ポジション方向取得 (最初に見つかったもの)                           |
//+------------------------------------------------------------------+
int GetPositionDirection()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)       continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      return (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
   }
   return 0;
}

//+------------------------------------------------------------------+
//| 全ポジションの未実現損益合計                                       |
//+------------------------------------------------------------------+
double TotalOpenPnL()
{
   double total = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)       continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      total += PositionGetDouble(POSITION_PROFIT);
   }
   return total;
}

//+------------------------------------------------------------------+
//| 合計リスク金額計算                                                 |
//+------------------------------------------------------------------+
double CalculateTotalRisk()
{
   double total = 0;
   double tick_val = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_sz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if(tick_val <= 0 || tick_sz <= 0) return 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)       continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

      double sl   = PositionGetDouble(POSITION_SL);
      double open_px = PositionGetDouble(POSITION_PRICE_OPEN);
      double lot  = PositionGetDouble(POSITION_VOLUME);
      long   type = PositionGetInteger(POSITION_TYPE);

      if(sl == 0) continue;

      double risk_dist;
      if(type == POSITION_TYPE_BUY)
         risk_dist = MathMax(0, open_px - sl);
      else
         risk_dist = MathMax(0, sl - open_px);

      total += (risk_dist / tick_sz) * tick_val * lot;
   }
   return total;
}

//+------------------------------------------------------------------+
//| OnTrade: ストップアウト検出                                        |
//| ポジション数が0になったとき、前回保持していたなら停止されたと判断    |
//+------------------------------------------------------------------+
void OnTrade()
{
   if(g_closing_by_cross) return;

   int current_count = CountMyPositions();
   if(g_had_position && current_count == 0)
   {
      g_was_stopped = true;
      g_unit_count  = 0;
      Print("ストップアウト検出: 再エントリー待機モード");
   }
}
//+------------------------------------------------------------------+
