//+------------------------------------------------------------------+
//| GOLD_NanpinMartin.mq5                                           |
//| Nanpin Martingale EA: NM-S20 (Safe) / NM-R50 (Risk) modes       |
//| Counter-trend grid basket with expanding intervals               |
//+------------------------------------------------------------------+
#property copyright "2026"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

enum ENUM_NM_MODE
{
   NM_SAFE_20 = 0,   // NM-S20 超安全型 (DD≤20%)
   NM_RISK_50 = 1    // NM-R50 研究用 (DD≤50%)
};

// ── 入力パラメータ ──────────────────────────────────
input group "=== モード ==="
input ENUM_NM_MODE InpNMMode    = NM_SAFE_20;      // ナンピンモード

input group "=== ロット設定 (0=モード既定) ==="
input double InpLotPerUnit       = 0;               // 基本ロット (0=既定: S20→0.01/万$)
input double InpMaxTotalLot      = 0;               // 最大総ロット (0=自動)

input group "=== グリッド設定 (0=モード既定) ==="
input int    InpGridBasePts      = 0;               // グリッド基準間隔pts
input double InpGridExpand       = 0;               // グリッド拡大係数
input int    InpMaxLayers        = 0;               // 最大追加段数
input double InpMartinMult       = 0;               // マーチン倍率

input group "=== 決済設定 (0=モード既定) ==="
input int    InpBasketTPPts      = 0;               // バスケットTP pts
input int    InpTimeoutBars      = 0;               // 時間切れバー数

input group "=== エントリーシグナル ==="
input ENUM_TIMEFRAMES InpEntryTF = PERIOD_H1;       // エントリーTF
input int    InpRSIPeriod        = 14;              // RSI期間
input int    InpRSIOversold      = 30;              // RSI売られ過ぎ
input int    InpRSIOverbought    = 70;              // RSI買われ過ぎ
input int    InpBBPeriod         = 20;              // ボリンジャー期間
input double InpBBDeviation      = 2.0;             // ボリンジャー偏差

input group "=== リスク管理 (0=モード既定) ==="
input double InpDDThreshold      = 0;               // DD閾値%
input double InpMaxDailyLossPct  = 3.0;             // 日次損失上限%
input int    InpMinMarginLevel   = 200;             // 最低証拠金維持率%
input int    InpMaxSpread        = 50;              // 最大スプレッドpts

input group "=== その他 ==="
input int    InpMagicNumber      = 20260915;        // マジックナンバー
input int    InpSlippage         = 50;              // スリッページpts

// ── モードプリセット値（OnInitで確定） ────────────────
double g_lot_per_unit;
double g_lot_unit_equity;
int    g_grid_base_pts;
double g_grid_expand;
int    g_max_layers;
double g_martin_mult;
int    g_basket_tp_pts;
double g_dd_threshold;
int    g_timeout_bars;

// ── インジケータハンドル ──────────────────────────────
int    g_rsi_handle;
int    g_bb_handle;

// ── バスケット状態 ────────────────────────────────────
int      g_basket_direction;     // 1=long, -1=short, 0=flat
int      g_basket_count;         // グリッド追加回数（初回は含まず）
datetime g_basket_start_bar;     // 初回エントリーのバー時刻
double   g_initial_entry_price;  // 初回エントリー価格
double   g_catastrophic_sl;      // 全ポジション共通の破滅SL

// ── 日次損失追跡 ─────────────────────────────────────
double   g_daily_start_equity;
datetime g_daily_reset_date;

// ── 新バー追跡 ───────────────────────────────────────
datetime g_last_bar_time;

// ── 制御フラグ ───────────────────────────────────────
bool     g_closing_all;

CTrade   g_trade;

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_NETTING)
   {
      Print("Error: Netting account not supported for nanpin EA");
      return INIT_FAILED;
   }

   if(InpNMMode == NM_SAFE_20)
   {
      g_lot_per_unit    = 0.01;
      g_lot_unit_equity = 10000.0;
      g_grid_base_pts   = 500;
      g_grid_expand     = 1.5;
      g_max_layers      = 6;
      g_martin_mult     = 1.3;
      g_basket_tp_pts   = 300;
      g_dd_threshold    = 20.0;
      g_timeout_bars    = 480;
   }
   else
   {
      g_lot_per_unit    = 0.01;
      g_lot_unit_equity = 5000.0;
      g_grid_base_pts   = 300;
      g_grid_expand     = 1.2;
      g_max_layers      = 10;
      g_martin_mult     = 1.8;
      g_basket_tp_pts   = 200;
      g_dd_threshold    = 50.0;
      g_timeout_bars    = 720;
   }

   if(InpLotPerUnit   > 0) g_lot_per_unit    = InpLotPerUnit;
   if(InpGridBasePts  > 0) g_grid_base_pts   = InpGridBasePts;
   if(InpGridExpand   > 0) g_grid_expand     = InpGridExpand;
   if(InpMaxLayers    > 0) g_max_layers      = InpMaxLayers;
   if(InpMartinMult   > 0) g_martin_mult     = InpMartinMult;
   if(InpBasketTPPts  > 0) g_basket_tp_pts   = InpBasketTPPts;
   if(InpDDThreshold  > 0) g_dd_threshold    = InpDDThreshold;
   if(InpTimeoutBars  > 0) g_timeout_bars    = InpTimeoutBars;

   g_rsi_handle = iRSI(_Symbol, InpEntryTF, InpRSIPeriod, PRICE_CLOSE);
   g_bb_handle  = iBands(_Symbol, InpEntryTF, InpBBPeriod, 0, InpBBDeviation, PRICE_CLOSE);

   if(g_rsi_handle == INVALID_HANDLE || g_bb_handle == INVALID_HANDLE)
   {
      Print("Error: Failed to create indicator handles");
      return INIT_FAILED;
   }

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpSlippage);
   g_trade.SetTypeFilling(ORDER_FILLING_IOC);

   g_basket_direction   = 0;
   g_basket_count       = 0;
   g_basket_start_bar   = 0;
   g_initial_entry_price= 0;
   g_catastrophic_sl    = 0;
   g_daily_start_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_daily_reset_date   = 0;
   g_last_bar_time      = 0;
   g_closing_all        = false;

   SyncBasketState();

   Print("NanpinMartin init: Mode=", EnumToString(InpNMMode),
         " Grid=", g_grid_base_pts, "×", DoubleToString(g_grid_expand, 2),
         " Layers=", g_max_layers,
         " Martin=", DoubleToString(g_martin_mult, 2),
         " DD%=", DoubleToString(g_dd_threshold, 1));

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_rsi_handle != INVALID_HANDLE) IndicatorRelease(g_rsi_handle);
   if(g_bb_handle  != INVALID_HANDLE) IndicatorRelease(g_bb_handle);
}

//+------------------------------------------------------------------+
//| OnTick                                                            |
//+------------------------------------------------------------------+
void OnTick()
{
   ResetDailyIfNeeded();
   if(DailyLossLimitHit()) return;

   if(g_basket_direction != 0)
   {
      if(CheckEquityStop())  return;
      if(CheckMarginLevel()) return;
      if(CheckTimeout())     return;
      if(CheckBasketTP())    return;

      if(IsNewBar() && g_basket_count < g_max_layers)
         CheckGridAdd();
   }
   else
   {
      if(!IsNewBar())  return;
      if(!SpreadOK())  return;
      CheckEntrySignal();
   }
}

//+------------------------------------------------------------------+
//| OnTrade — 外部決済の検知                                           |
//+------------------------------------------------------------------+
void OnTrade()
{
   if(g_closing_all) return;
   if(g_basket_direction != 0 && CountMyPositions() == 0)
   {
      Print("All positions closed externally (StopOut or manual)");
      ResetBasketState();
   }
}

// ── ヘルパー関数 ────────────────────────────────────

bool IsNewBar()
{
   datetime cur = iTime(_Symbol, InpEntryTF, 0);
   if(cur == g_last_bar_time) return false;
   g_last_bar_time = cur;
   return true;
}

//+------------------------------------------------------------------+
//| CheckEntrySignal — RSI+BB逆張りエントリー判定                      |
//+------------------------------------------------------------------+
void CheckEntrySignal()
{
   double rsi[2], bb_upper[2], bb_lower[2];
   if(CopyBuffer(g_rsi_handle, 0, 0, 2, rsi)      < 2) return;
   if(CopyBuffer(g_bb_handle,  1, 0, 2, bb_upper)  < 2) return;
   if(CopyBuffer(g_bb_handle,  2, 0, 2, bb_lower)  < 2) return;
   ArraySetAsSeries(rsi,      true);
   ArraySetAsSeries(bb_upper, true);
   ArraySetAsSeries(bb_lower, true);

   double low1  = iLow(_Symbol,  InpEntryTF, 1);
   double high1 = iHigh(_Symbol, InpEntryTF, 1);

   int signal = 0;
   if(rsi[1] < InpRSIOversold  && low1  <= bb_lower[1]) signal =  1;
   if(rsi[1] > InpRSIOverbought && high1 >= bb_upper[1]) signal = -1;
   if(signal == 0) return;

   double lot = CalculateBaseLot();
   if(lot <= 0) return;

   double entry = (signal == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                 : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double max_grid = CumulativeGridDistance(g_max_layers);

   double sl;
   if(signal == 1)
      sl = entry - max_grid - g_grid_base_pts * _Point;
   else
      sl = entry + max_grid + g_grid_base_pts * _Point;
   sl = NormalizeDouble(sl, _Digits);

   if(ExecuteEntry(signal, lot, sl))
   {
      g_basket_direction    = signal;
      g_basket_count        = 0;
      g_basket_start_bar    = iTime(_Symbol, InpEntryTF, 0);
      g_initial_entry_price = entry;
      g_catastrophic_sl     = sl;
      Print("Basket opened: dir=", signal,
            " lot=", DoubleToString(lot, 2),
            " entry=", DoubleToString(entry, _Digits),
            " SL=", DoubleToString(sl, _Digits));
   }
}

//+------------------------------------------------------------------+
//| CheckGridAdd — グリッド追加判定                                     |
//+------------------------------------------------------------------+
void CheckGridAdd()
{
   if(!SpreadOK()) return;
   if(CountMyPositions() <= 0) return;

   double required_pts = GridSpacing(g_basket_count + 1);
   double required_dist = required_pts * _Point;

   double price = (g_basket_direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                             : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double last_price = GetWorstEntryPrice();
   if(last_price <= 0) return;

   bool triggered = false;
   if(g_basket_direction == 1)
      triggered = (price <= last_price - required_dist);
   else
      triggered = (price >= last_price + required_dist);
   if(!triggered) return;

   int level = g_basket_count + 1;
   double base_lot = CalculateBaseLot();
   double lot = base_lot * MathPow(g_martin_mult, level);
   lot = NormalizeLot(lot);
   if(lot <= 0) return;

   double current_total = GetTotalLots();
   double max_total = (InpMaxTotalLot > 0) ? InpMaxTotalLot : AutoMaxTotalLot();
   if(current_total + lot > max_total)
   {
      Print("Grid add rejected: total lot ",
            DoubleToString(current_total + lot, 2),
            " > max ", DoubleToString(max_total, 2));
      return;
   }

   double sl = NormalizeDouble(g_catastrophic_sl, _Digits);

   if(ExecuteEntry(g_basket_direction, lot, sl))
   {
      g_basket_count++;
      Print("Grid L", g_basket_count,
            ": lot=", DoubleToString(lot, 2),
            " price=", DoubleToString(price, _Digits),
            " avg=", DoubleToString(CalculateAveragePrice(), _Digits),
            " total_lot=", DoubleToString(current_total + lot, 2));
   }
}

//+------------------------------------------------------------------+
//| CheckBasketTP — バスケットTP判定                                    |
//+------------------------------------------------------------------+
bool CheckBasketTP()
{
   if(CountMyPositions() <= 0) return false;

   double avg = CalculateAveragePrice();
   if(avg <= 0) return false;

   double tp;
   if(g_basket_direction == 1)
      tp = avg + g_basket_tp_pts * _Point;
   else
      tp = avg - g_basket_tp_pts * _Point;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   bool hit = (g_basket_direction == 1  && bid >= tp) ||
              (g_basket_direction == -1 && ask <= tp);
   if(!hit) return false;

   double pnl = TotalOpenPnL();
   Print("Basket TP: avg=", DoubleToString(avg, _Digits),
         " tp=", DoubleToString(tp, _Digits),
         " PnL=", DoubleToString(pnl, 2));
   g_closing_all = true;
   CloseAllPositions();
   g_closing_all = false;
   ResetBasketState();
   return true;
}

//+------------------------------------------------------------------+
//| CheckEquityStop — エクイティDD停止                                  |
//+------------------------------------------------------------------+
bool CheckEquityStop()
{
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance <= 0) return false;

   double dd_pct = ((balance - equity) / balance) * 100.0;
   if(dd_pct < g_dd_threshold) return false;

   Print("Equity stop: DD=", DoubleToString(dd_pct, 1),
         "% >= ", DoubleToString(g_dd_threshold, 1), "%");
   g_closing_all = true;
   CloseAllPositions();
   g_closing_all = false;
   ResetBasketState();
   return true;
}

//+------------------------------------------------------------------+
//| CheckMarginLevel — 証拠金維持率監視                                 |
//+------------------------------------------------------------------+
bool CheckMarginLevel()
{
   if(InpMinMarginLevel <= 0) return false;
   double margin_used = AccountInfoDouble(ACCOUNT_MARGIN);
   if(margin_used <= 0) return false;

   double ml = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   if(ml <= 0 || ml >= InpMinMarginLevel) return false;

   Print("Margin level critical: ", DoubleToString(ml, 0),
         "% < min ", InpMinMarginLevel, "%");
   g_closing_all = true;
   CloseAllPositions();
   g_closing_all = false;
   ResetBasketState();
   return true;
}

//+------------------------------------------------------------------+
//| CheckTimeout — 時間切れ撤退                                        |
//+------------------------------------------------------------------+
bool CheckTimeout()
{
   if(g_timeout_bars <= 0 || g_basket_start_bar == 0) return false;

   int bars = iBarShift(_Symbol, InpEntryTF, g_basket_start_bar, false);
   if(bars < 0 || bars < g_timeout_bars) return false;

   double pnl = TotalOpenPnL();
   Print("Timeout: ", bars, " bars (limit=", g_timeout_bars,
         ") PnL=", DoubleToString(pnl, 2));
   g_closing_all = true;
   CloseAllPositions();
   g_closing_all = false;
   ResetBasketState();
   return true;
}

//+------------------------------------------------------------------+
//| CalculateBaseLot — エクイティ比例の基本ロット                       |
//+------------------------------------------------------------------+
double CalculateBaseLot()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity <= 0) return 0;
   double lot = g_lot_per_unit * (equity / g_lot_unit_equity);
   return NormalizeLot(lot);
}

//+------------------------------------------------------------------+
//| NormalizeLot — ロットを取引可能な値に正規化                         |
//+------------------------------------------------------------------+
double NormalizeLot(double lot)
{
   double min_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lot_step <= 0) lot_step = 0.01;

   lot = MathFloor(lot / lot_step) * lot_step;
   if(lot < min_lot) lot = min_lot;
   if(lot > max_lot) lot = max_lot;
   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
//| GridSpacing — レベルnのグリッド間隔 (points)                       |
//+------------------------------------------------------------------+
double GridSpacing(int level)
{
   if(level <= 0) return 0;
   return g_grid_base_pts * MathPow(g_grid_expand, level - 1);
}

//+------------------------------------------------------------------+
//| CumulativeGridDistance — レベルnまでの累計距離 (price)               |
//+------------------------------------------------------------------+
double CumulativeGridDistance(int level)
{
   double total_pts = 0;
   for(int i = 1; i <= level; i++)
      total_pts += GridSpacing(i);
   return total_pts * _Point;
}

//+------------------------------------------------------------------+
//| CalculateAveragePrice — ロット加重平均建値                          |
//+------------------------------------------------------------------+
double CalculateAveragePrice()
{
   double sum_lp = 0, sum_l = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      double vol = PositionGetDouble(POSITION_VOLUME);
      double op  = PositionGetDouble(POSITION_PRICE_OPEN);
      sum_lp += vol * op;
      sum_l  += vol;
   }
   if(sum_l <= 0) return 0;
   return NormalizeDouble(sum_lp / sum_l, _Digits);
}

//+------------------------------------------------------------------+
//| GetWorstEntryPrice — 最も逆行側のエントリー価格                     |
//+------------------------------------------------------------------+
double GetWorstEntryPrice()
{
   double worst = 0;
   bool found = false;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      double op = PositionGetDouble(POSITION_PRICE_OPEN);
      if(!found) { worst = op; found = true; continue; }

      if(g_basket_direction == 1  && op < worst) worst = op;
      if(g_basket_direction == -1 && op > worst) worst = op;
   }
   return worst;
}

//+------------------------------------------------------------------+
//| GetTotalLots — バスケット合計ロット数                                |
//+------------------------------------------------------------------+
double GetTotalLots()
{
   double total = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      total += PositionGetDouble(POSITION_VOLUME);
   }
   return total;
}

//+------------------------------------------------------------------+
//| AutoMaxTotalLot — 理論最大ロットの自動計算                          |
//+------------------------------------------------------------------+
double AutoMaxTotalLot()
{
   double base = CalculateBaseLot();
   if(base <= 0) return 1.0;
   double total = 0;
   for(int i = 0; i <= g_max_layers; i++)
      total += base * MathPow(g_martin_mult, i);
   return NormalizeDouble(total * 1.2, 2);
}

//+------------------------------------------------------------------+
//| ExecuteEntry — 安全な注文送信                                       |
//+------------------------------------------------------------------+
bool ExecuteEntry(int direction, double lot, double sl)
{
   ResetLastError();
   bool ok = false;

   if(direction == 1)
      ok = g_trade.Buy(lot, _Symbol, 0, sl, 0, "NM-Basket");
   else
      ok = g_trade.Sell(lot, _Symbol, 0, sl, 0, "NM-Basket");

   if(!ok || g_trade.ResultRetcode() != TRADE_RETCODE_DONE)
   {
      Print("OrderSend failed: ", g_trade.ResultRetcode(),
            " / ", g_trade.ResultComment(),
            " / Error: ", GetLastError());
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
//| TotalOpenPnL — 自ポジション合計含み損益                             |
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
//| SyncBasketState — 再起動時にバスケット状態を復元                     |
//+------------------------------------------------------------------+
void SyncBasketState()
{
   int count = 0;
   int dir = 0;
   datetime earliest = 0;
   double first_price = 0;
   double worst = 0;
   bool found_first = false;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      count++;
      long type = PositionGetInteger(POSITION_TYPE);
      dir = (type == POSITION_TYPE_BUY) ? 1 : -1;

      datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
      double op = PositionGetDouble(POSITION_PRICE_OPEN);

      if(earliest == 0 || open_time < earliest)
      {
         earliest    = open_time;
         first_price = op;
      }

      if(!found_first) { worst = op; found_first = true; }
      else
      {
         if(dir == 1  && op < worst) worst = op;
         if(dir == -1 && op > worst) worst = op;
      }
   }

   if(count > 0)
   {
      g_basket_direction    = dir;
      g_basket_count        = count - 1;
      g_basket_start_bar    = earliest;
      g_initial_entry_price = first_price;

      double max_grid = CumulativeGridDistance(g_max_layers);
      if(dir == 1)
         g_catastrophic_sl = first_price - max_grid - g_grid_base_pts * _Point;
      else
         g_catastrophic_sl = first_price + max_grid + g_grid_base_pts * _Point;

      Print("Basket synced: dir=", dir, " positions=", count,
            " layers=", g_basket_count,
            " avg=", DoubleToString(CalculateAveragePrice(), _Digits));
   }
}

//+------------------------------------------------------------------+
//| ResetBasketState                                                   |
//+------------------------------------------------------------------+
void ResetBasketState()
{
   g_basket_direction    = 0;
   g_basket_count        = 0;
   g_basket_start_bar    = 0;
   g_initial_entry_price = 0;
   g_catastrophic_sl     = 0;
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
   if(loss_pct < InpMaxDailyLossPct) return false;

   if(CountMyPositions() > 0)
   {
      Print("Daily loss limit: ", DoubleToString(loss_pct, 1), "%");
      g_closing_all = true;
      CloseAllPositions();
      g_closing_all = false;
      ResetBasketState();
   }
   return true;
}
//+------------------------------------------------------------------+
