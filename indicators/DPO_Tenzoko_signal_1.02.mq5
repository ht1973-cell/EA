//+------------------------------------------------------------------+
//|                        DPO_Tenzoko_signal.mq5                    |
//|  DPO天底（ウォーターマーク方式）＋クロスシグナル検出              |
//|  Version: 1.02                                                   |
//+------------------------------------------------------------------+
//  ■ 機能概要
//  1. DPO/MADPOをサブウィンドウに描画
//  2. 価格BBをDPO座標系にデトレンドして重畳描画
//     → 価格のBB位置とDPO/MADPOのダイバージェンス観測用
//  3. 天底シグナル: ティックWM方式で天井(SELL)・底(BUY)を検出
//  4. クロスシグナル: DPOがMADPOを上抜け(BUY)・下抜け(SELL)
//  5. 通知: ポップアップ / サウンド / メール / プッシュ / Discord(EA専用)
//  6. 診断ログ: DPO/MADPO/BB/WM/%B値を記録
//
//  ■ BB座標変換の原理
//  DPO[i] = Price[i] - base[i-shift]  (base = SMA(Price, DPO_period))
//  BB_Upper_DPO[i] = BB_Upper_raw[i] - base[i-shift]
//  → 同じshifted SMAを減算するため、DPOと同一スケールになる
//  → %B = (DPO - BB_Lower_DPO)/(BB_Upper_DPO - BB_Lower_DPO)
//     = 標準%Bと数学的に同値（デトレンドがキャンセルされる）
//
//  ■ v1.02変更点
//  - BB計算を「DPO上のBB」→「価格BB→DPO座標デトレンド」に変更
//  - BB Middle(デトレンド済SMA)を追加描画
//  - 診断ログに%B追加
//+------------------------------------------------------------------+
#property copyright   "DPO_Tenzoko_signal"
#property version     "1.02"
#property description "DPO天底+クロス+価格BB(デトレンド) v1.02"
#property strict

#property indicator_separate_window
#property indicator_buffers 10
#property indicator_plots   9

//--- Plot 0: DPO
#property indicator_label1  "DPO"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrRed
#property indicator_width1  1

//--- Plot 1: MADPO
#property indicator_label2  "MADPO"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrAqua
#property indicator_width2  1

//--- Plot 2: BB Upper (価格BBデトレンド)
#property indicator_label3  "PriceBB_U"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrYellow
#property indicator_style3  STYLE_DOT
#property indicator_width3  1

//--- Plot 3: BB Middle (価格SMAデトレンド)
#property indicator_label4  "PriceBB_M"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrSilver
#property indicator_style4  STYLE_DASH
#property indicator_width4  1

//--- Plot 4: BB Lower (価格BBデトレンド)
#property indicator_label5  "PriceBB_L"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrYellow
#property indicator_style5  STYLE_DOT
#property indicator_width5  1

//--- Plot 5: Cross BUY
#property indicator_label6  "CrossBUY"
#property indicator_type6   DRAW_ARROW
#property indicator_color6  clrDodgerBlue
#property indicator_width6  1

//--- Plot 6: Cross SELL
#property indicator_label7  "CrossSELL"
#property indicator_type7   DRAW_ARROW
#property indicator_color7  clrOrangeRed
#property indicator_width7  1

//--- Plot 7: Tenzoko BUY (底確定)
#property indicator_label8  "TenzokoBUY"
#property indicator_type8   DRAW_ARROW
#property indicator_color8  clrLime
#property indicator_width8  2

//--- Plot 8: Tenzoko SELL (天井確定)
#property indicator_label9  "TenzokoSELL"
#property indicator_type9   DRAW_ARROW
#property indicator_color9  clrMagenta
#property indicator_width9  2

//+------------------------------------------------------------------+
//| 列挙型                                                           |
//+------------------------------------------------------------------+
enum ENUM_MA_METHOD_SIMPLE { MA_SMA_MODE, MA_EMA_MODE };

enum ENUM_PHASE
{
   PHASE_IDLE,
   PHASE_SEEKING_PEAK,
   PHASE_SEEKING_TROUGH
};

//+------------------------------------------------------------------+
//| 入力パラメータ                                                    |
//+------------------------------------------------------------------+
input group "=== DPO / MADPO 設定 ==="
input int                   Inp_DPO_Period    = 20;
input ENUM_MA_METHOD_SIMPLE Inp_DPO_MAType    = MA_SMA_MODE;
input int                   Inp_MADPO_Period  = 20;
input ENUM_MA_METHOD_SIMPLE Inp_MADPO_MAType  = MA_SMA_MODE;
input ENUM_APPLIED_PRICE    Inp_AppliedPrice  = PRICE_CLOSE;
input int                   Inp_MaxCalcBars   = 3000;

input group "=== 価格ボリンジャーバンド設定 ==="
input double Inp_BB_Sigma  = 2.0;    // BBシグマ倍率
input int    Inp_BB_Period = 20;     // BB計算期間(SMA+StdDev)

input group "=== 振幅フィルター（DPO StdDev方式） ==="
input bool   Inp_AmpFilterOn   = true;
input double Inp_AmpMultiplier = 1.0;
input int    Inp_AmpLookback   = 20;

input group "=== シグナル種別 ==="
input bool Inp_CrossAlertOn   = true;
input bool Inp_TenzokoAlertOn = true;

input group "=== 通知チャネル ==="
input bool   Inp_AlertPopup   = true;
input bool   Inp_AlertSound   = true;
input bool   Inp_AlertEmail   = false;
input bool   Inp_AlertPush    = false;
input bool   Inp_AlertDiscord = false;
input string Inp_DiscordURL   = "";

input group "=== 診断ログ ==="
input bool Inp_DiagLog = true;

//+------------------------------------------------------------------+
//| インジケーターバッファ                                            |
//+------------------------------------------------------------------+
double g_dpo[];          // 0: DPO
double g_madpo[];        // 1: MADPO
double g_bbUpper[];      // 2: 価格BB Upper (デトレンド済)
double g_bbMiddle[];     // 3: 価格BB Middle (デトレンド済)
double g_bbLower[];      // 4: 価格BB Lower (デトレンド済)
double g_crossBuy[];     // 5: クロスBUY
double g_crossSell[];    // 6: クロスSELL
double g_tenzokoBuy[];   // 7: 天底BUY
double g_tenzokoSell[];  // 8: 天底SELL
double g_dpoStdDev[];    // 9: DPO StdDev (計算用・非表示)

//+------------------------------------------------------------------+
//| ステートマシン変数                                                |
//+------------------------------------------------------------------+
ENUM_PHASE g_phase          = PHASE_IDLE;
double     g_watermark      = 0.0;
double     g_amplitude_base = 0.0;
datetime   g_last_bar_time  = 0;
int        g_signal_scan_from = 0;
bool       g_full_recalc    = true;

//+------------------------------------------------------------------+
//| SMA計算（EMPTY_VALUEギャップでリセット）                          |
//+------------------------------------------------------------------+
void CalcSMA(const double &src[], int period, int n, double &dst[])
{
   double sum = 0.0;
   int    vc  = 0;
   double wc[];
   ArrayResize(wc, n);
   ArrayCopy(wc, src);
   for(int i = 0; i < n; i++)
   {
      if(src[i] == EMPTY_VALUE)
      { dst[i] = EMPTY_VALUE; sum = 0.0; vc = 0; continue; }
      sum += src[i]; vc++;
      if(vc > period) sum -= wc[i - period];
      dst[i] = (vc >= period) ? sum / period : EMPTY_VALUE;
   }
}

//+------------------------------------------------------------------+
//| EMA計算（EMPTY_VALUEギャップでリセット）                          |
//+------------------------------------------------------------------+
void CalcEMA(const double &src[], int period, int n, double &dst[])
{
   double k = 2.0 / (period + 1.0);
   int rs = -1;
   for(int i = 0; i < n; i++)
   {
      if(src[i] == EMPTY_VALUE)
      { dst[i] = EMPTY_VALUE; rs = -1; continue; }
      if(rs < 0) rs = i;
      int p = i - rs;
      if(p < period - 1) { dst[i] = EMPTY_VALUE; continue; }
      if(p == period - 1)
      { double s = 0.0; for(int j = rs; j <= i; j++) s += src[j]; dst[i] = s / period; }
      else
      { dst[i] = dst[i-1] + k * (src[i] - dst[i-1]); }
   }
}

void CalcMA(const double &src[], int period, int n,
            ENUM_MA_METHOD_SIMPLE m, double &dst[])
{
   if(m == MA_EMA_MODE) CalcEMA(src, period, n, dst);
   else                 CalcSMA(src, period, n, dst);
}

//+------------------------------------------------------------------+
//| 汎用ローリング標準偏差計算                                        |
//+------------------------------------------------------------------+
void CalcRollingStdDev(const double &src[], int period, int n, double &dst[])
{
   for(int i = 0; i < n; i++)
   {
      if(i < period - 1 || src[i] == EMPTY_VALUE)
      { dst[i] = EMPTY_VALUE; continue; }
      double sum = 0.0, sumSq = 0.0;
      bool valid = true;
      for(int j = i - period + 1; j <= i; j++)
      {
         if(j < 0 || src[j] == EMPTY_VALUE) { valid = false; break; }
         sum += src[j]; sumSq += src[j] * src[j];
      }
      if(!valid) { dst[i] = EMPTY_VALUE; continue; }
      double mean = sum / period;
      double var  = sumSq / period - mean * mean;
      dst[i] = (var > 0.0) ? MathSqrt(var) : 0.0;
   }
}

//+------------------------------------------------------------------+
//| 通知送信                                                          |
//+------------------------------------------------------------------+
void SendAlert(string signalType, string direction, string detail)
{
   string msg = StringFormat("[%s] %s %s %s | %s",
                _Symbol, EnumToString(_Period), signalType, direction, detail);
   if(Inp_AlertPopup)   Alert(msg);
   if(Inp_AlertSound)   PlaySound("alert.wav");
   if(Inp_AlertEmail)   SendMail("DPO_Tenzoko: " + direction, msg);
   if(Inp_AlertPush)    SendNotification(msg);
   if(Inp_AlertDiscord) SendDiscordMessage(msg);
   Print("SIGNAL: ", msg);
}

void SendDiscordMessage(string message)
{
   if(Inp_DiscordURL == "") return;
   if(MQLInfoInteger(MQL_PROGRAM_TYPE) == PROGRAM_INDICATOR)
   {
      static bool w = false;
      if(!w) { Print("WARNING: Discord通知はインジケーターからは不可"); w = true; }
      return;
   }
   string json = "{\"content\":\"" + message + "\"}";
   char d[], r[]; string rh;
   StringToCharArray(json, d, 0, WHOLE_ARRAY, CP_UTF8);
   ArrayResize(d, ArraySize(d) - 1);
   int res = WebRequest("POST", Inp_DiscordURL, "Content-Type: application/json\r\n",
                        5000, d, r, rh);
   if(res != 200 && res != 204)
      Print("Discord error: HTTP ", res);
}

//+------------------------------------------------------------------+
//| 診断ログ出力                                                      |
//+------------------------------------------------------------------+
void DiagLog(int a, const datetime &time[], string evt, string detail)
{
   if(!Inp_DiagLog) return;
   string t = TimeToString(time[a], TIME_DATE|TIME_MINUTES|TIME_SECONDS);

   double dpo  = g_dpo[a];
   double mdpo = g_madpo[a];
   double bbU  = g_bbUpper[a];
   double bbM  = g_bbMiddle[a];
   double bbL  = g_bbLower[a];
   double sd   = g_dpoStdDev[a];

   // %B = (DPO - BB_Lower) / (BB_Upper - BB_Lower)  ※デトレンド空間でも標準%Bと同値
   double pctB = 0.0;
   if(bbU != EMPTY_VALUE && bbL != EMPTY_VALUE && dpo != EMPTY_VALUE)
   {
      double bw = bbU - bbL;
      if(bw > 0.0) pctB = (dpo - bbL) / bw;
   }

   Print(StringFormat(
      "DIAG [%s] %s | DPO=%.2f MADPO=%.2f BB_U=%.2f BB_M=%.2f BB_L=%.2f StdDev=%.2f %%B=%.3f | Phase=%s WM=%.2f AmpBase=%.2f | %s",
      t, evt,
      (dpo  != EMPTY_VALUE ? dpo  : 0.0),
      (mdpo != EMPTY_VALUE ? mdpo : 0.0),
      (bbU  != EMPTY_VALUE ? bbU  : 0.0),
      (bbM  != EMPTY_VALUE ? bbM  : 0.0),
      (bbL  != EMPTY_VALUE ? bbL  : 0.0),
      (sd   != EMPTY_VALUE ? sd   : 0.0),
      pctB,
      EnumToString(g_phase), g_watermark, g_amplitude_base,
      detail));
}

//+------------------------------------------------------------------+
//| ステートマシンリセット                                            |
//+------------------------------------------------------------------+
void ResetStateMachine()
{
   g_phase = PHASE_IDLE; g_watermark = 0.0; g_amplitude_base = 0.0;
   g_last_bar_time = 0; g_signal_scan_from = 0; g_full_recalc = true;
}

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   if(Inp_DPO_Period < 2)   { Alert("DPO期間は2以上"); return INIT_PARAMETERS_INCORRECT; }
   if(Inp_MADPO_Period < 1) { Alert("MADPO期間は1以上"); return INIT_PARAMETERS_INCORRECT; }
   if(Inp_BB_Period < 2)    { Alert("BB期間は2以上"); return INIT_PARAMETERS_INCORRECT; }
   if(Inp_BB_Sigma <= 0.0)  { Alert("BBシグマは正の値"); return INIT_PARAMETERS_INCORRECT; }
   if(Inp_AmpFilterOn && Inp_AmpLookback < 2)
   { Alert("振幅StdDev期間は2以上"); return INIT_PARAMETERS_INCORRECT; }
   if(Inp_AmpFilterOn && Inp_AmpMultiplier <= 0.0)
   { Alert("振幅StdDev倍率は正の値"); return INIT_PARAMETERS_INCORRECT; }

   // --- バッファ登録 ---
   SetIndexBuffer(0, g_dpo,         INDICATOR_DATA);
   SetIndexBuffer(1, g_madpo,       INDICATOR_DATA);
   SetIndexBuffer(2, g_bbUpper,     INDICATOR_DATA);
   SetIndexBuffer(3, g_bbMiddle,    INDICATOR_DATA);
   SetIndexBuffer(4, g_bbLower,     INDICATOR_DATA);
   SetIndexBuffer(5, g_crossBuy,    INDICATOR_DATA);
   SetIndexBuffer(6, g_crossSell,   INDICATOR_DATA);
   SetIndexBuffer(7, g_tenzokoBuy,  INDICATOR_DATA);
   SetIndexBuffer(8, g_tenzokoSell, INDICATOR_DATA);
   SetIndexBuffer(9, g_dpoStdDev,   INDICATOR_CALCULATIONS);

   ArraySetAsSeries(g_dpo,         false);
   ArraySetAsSeries(g_madpo,       false);
   ArraySetAsSeries(g_bbUpper,     false);
   ArraySetAsSeries(g_bbMiddle,    false);
   ArraySetAsSeries(g_bbLower,     false);
   ArraySetAsSeries(g_crossBuy,    false);
   ArraySetAsSeries(g_crossSell,   false);
   ArraySetAsSeries(g_tenzokoBuy,  false);
   ArraySetAsSeries(g_tenzokoSell, false);
   ArraySetAsSeries(g_dpoStdDev,   false);

   for(int i = 0; i < 10; i++)
      PlotIndexSetDouble(i, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   // --- 矢印コード ---
   PlotIndexSetInteger(5, PLOT_ARROW, 233);  // CrossBUY
   PlotIndexSetInteger(6, PLOT_ARROW, 234);  // CrossSELL
   PlotIndexSetInteger(7, PLOT_ARROW, 233);  // TenzokoBUY (太)
   PlotIndexSetInteger(8, PLOT_ARROW, 234);  // TenzokoSELL (太)

   // --- ショートネーム ---
   IndicatorSetString(INDICATOR_SHORTNAME,
      StringFormat("DPO_Tenzoko(%d/%d) v1.02", Inp_DPO_Period, Inp_MADPO_Period));

   // --- レベル線: 0.0 + ±0.1～±0.9 = 19本 ---
   IndicatorSetInteger(INDICATOR_LEVELS, 19);
   int idx = 0;
   IndicatorSetDouble(INDICATOR_LEVELVALUE, idx, 0.0);
   IndicatorSetInteger(INDICATOR_LEVELCOLOR, idx, clrDimGray);
   IndicatorSetInteger(INDICATOR_LEVELSTYLE, idx, STYLE_DOT);
   IndicatorSetInteger(INDICATOR_LEVELWIDTH, idx, 1);
   idx++;
   for(int s = 1; s <= 9; s++)
   {
      double v = s * 0.1;
      IndicatorSetDouble(INDICATOR_LEVELVALUE, idx, v);
      IndicatorSetInteger(INDICATOR_LEVELCOLOR, idx, clrSlateGray);
      IndicatorSetInteger(INDICATOR_LEVELSTYLE, idx, STYLE_DOT);
      IndicatorSetInteger(INDICATOR_LEVELWIDTH, idx, 1);
      idx++;
      IndicatorSetDouble(INDICATOR_LEVELVALUE, idx, -v);
      IndicatorSetInteger(INDICATOR_LEVELCOLOR, idx, clrSlateGray);
      IndicatorSetInteger(INDICATOR_LEVELSTYLE, idx, STYLE_DOT);
      IndicatorSetInteger(INDICATOR_LEVELWIDTH, idx, 1);
      idx++;
   }

   ResetStateMachine();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) { Comment(""); }

//+------------------------------------------------------------------+
//| OnCalculate                                                      |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   //=== STEP 0: 最小バー数 ===
   int shift   = Inp_DPO_Period / 2 + 1;
   int minBars = Inp_DPO_Period * 2 + Inp_MADPO_Period + 10;
   minBars = MathMax(minBars, Inp_BB_Period + shift + Inp_DPO_Period + 10);
   if(Inp_AmpFilterOn)
      minBars = MathMax(minBars, Inp_AmpLookback + shift + Inp_DPO_Period + 10);
   if(rates_total < minBars) return 0;

   //=== STEP 1: 計算ウィンドウ ===
   int windowStart = MathMax(0, rates_total - Inp_MaxCalcBars);
   int windowLen   = rates_total - windowStart;
   if(windowLen < minBars)
   { windowStart = MathMax(0, rates_total - minBars); windowLen = rates_total - windowStart; }

   //=== STEP 2: 価格配列 ===
   double price[];
   ArrayResize(price, windowLen);
   for(int i = 0; i < windowLen; i++)
   {
      int a = windowStart + i;
      switch(Inp_AppliedPrice)
      {
         case PRICE_OPEN:     price[i] = open[a];                              break;
         case PRICE_HIGH:     price[i] = high[a];                              break;
         case PRICE_LOW:      price[i] = low[a];                               break;
         case PRICE_MEDIAN:   price[i] = (high[a]+low[a])/2.0;                 break;
         case PRICE_TYPICAL:  price[i] = (high[a]+low[a]+close[a])/3.0;        break;
         case PRICE_WEIGHTED: price[i] = (high[a]+low[a]+2*close[a])/4.0;      break;
         default:             price[i] = close[a];                              break;
      }
   }

   //=== STEP 3: DPO計算 ===
   double base[];  // DPOのベースSMA（デトレンド基準）
   ArrayResize(base, windowLen);
   CalcMA(price, Inp_DPO_Period, windowLen, Inp_DPO_MAType, base);

   double dpoW[];
   ArrayResize(dpoW, windowLen);
   for(int i = 0; i < windowLen; i++)
   {
      int idx = i - shift;
      dpoW[i] = (idx >= 0 && base[idx] != EMPTY_VALUE)
                ? price[i] - base[idx] : EMPTY_VALUE;
   }

   //=== STEP 4: MADPO計算 ===
   double madpoW[];
   ArrayResize(madpoW, windowLen);
   CalcMA(dpoW, Inp_MADPO_Period, windowLen, Inp_MADPO_MAType, madpoW);
   for(int i = 0; i < windowLen; i++)
      if(dpoW[i] == EMPTY_VALUE) madpoW[i] = EMPTY_VALUE;

   //=== STEP 5: 価格BB計算 → DPO座標にデトレンド ===
   // 5a: 価格のSMA（BB中央線の原型）
   double priceSMA[];
   ArrayResize(priceSMA, windowLen);
   CalcSMA(price, Inp_BB_Period, windowLen, priceSMA);

   // 5b: 価格のローリングStdDev
   double priceSD[];
   ArrayResize(priceSD, windowLen);
   CalcRollingStdDev(price, Inp_BB_Period, windowLen, priceSD);

   // 5c: 価格BB（生値）→ DPO座標にデトレンド
   //     デトレンド = 生値 - base[i - shift]（DPOと同じ基準を減算）
   double bbUpW[], bbMdW[], bbLoW[];
   ArrayResize(bbUpW, windowLen);
   ArrayResize(bbMdW, windowLen);
   ArrayResize(bbLoW, windowLen);
   for(int i = 0; i < windowLen; i++)
   {
      int idx = i - shift;
      if(idx < 0 || base[idx] == EMPTY_VALUE ||
         priceSMA[i] == EMPTY_VALUE || priceSD[i] == EMPTY_VALUE)
      {
         bbUpW[i] = EMPTY_VALUE;
         bbMdW[i] = EMPTY_VALUE;
         bbLoW[i] = EMPTY_VALUE;
      }
      else
      {
         double detrend = base[idx];  // DPOと同じshifted SMAを減算
         bbUpW[i] = (priceSMA[i] + Inp_BB_Sigma * priceSD[i]) - detrend;
         bbMdW[i] =  priceSMA[i]                               - detrend;
         bbLoW[i] = (priceSMA[i] - Inp_BB_Sigma * priceSD[i]) - detrend;
      }
   }

   //=== STEP 5d: DPO StdDev（振幅フィルター用） ===
   double stddevAmpW[];
   ArrayResize(stddevAmpW, windowLen);
   if(Inp_AmpFilterOn)
      CalcRollingStdDev(dpoW, Inp_AmpLookback, windowLen, stddevAmpW);
   else
      ArrayInitialize(stddevAmpW, EMPTY_VALUE);

   //=== STEP 6: グローバルバッファ転写 ===
   for(int a = 0; a < windowStart; a++)
   {
      g_dpo[a] = EMPTY_VALUE;  g_madpo[a] = EMPTY_VALUE;
      g_bbUpper[a] = EMPTY_VALUE; g_bbMiddle[a] = EMPTY_VALUE; g_bbLower[a] = EMPTY_VALUE;
      g_crossBuy[a] = EMPTY_VALUE; g_crossSell[a] = EMPTY_VALUE;
      g_tenzokoBuy[a] = EMPTY_VALUE; g_tenzokoSell[a] = EMPTY_VALUE;
      g_dpoStdDev[a] = EMPTY_VALUE;
   }
   for(int i = 0; i < windowLen; i++)
   {
      int a = windowStart + i;
      g_dpo[a]       = dpoW[i];
      g_madpo[a]     = madpoW[i];
      g_bbUpper[a]   = bbUpW[i];
      g_bbMiddle[a]  = bbMdW[i];
      g_bbLower[a]   = bbLoW[i];
      g_dpoStdDev[a] = stddevAmpW[i];
   }

   //=== STEP 7: 全再計算判定 ===
   bool needFullRecalc = (prev_calculated < 2 || g_full_recalc);
   if(needFullRecalc)
   {
      for(int a = 0; a < rates_total; a++)
      {
         g_crossBuy[a] = EMPTY_VALUE; g_crossSell[a] = EMPTY_VALUE;
         g_tenzokoBuy[a] = EMPTY_VALUE; g_tenzokoSell[a] = EMPTY_VALUE;
      }
      g_phase = PHASE_IDLE; g_watermark = 0.0; g_amplitude_base = 0.0;
      g_signal_scan_from = windowStart + shift + Inp_DPO_Period + Inp_MADPO_Period + 2;
      g_signal_scan_from = MathMax(g_signal_scan_from,
                                    windowStart + Inp_BB_Period + shift + Inp_DPO_Period + 2);
      if(Inp_AmpFilterOn)
         g_signal_scan_from = MathMax(g_signal_scan_from,
                                      windowStart + Inp_AmpLookback + shift + Inp_DPO_Period + 2);
      g_full_recalc = false;
      g_last_bar_time = 0;
   }
   else
   {
      for(int a = prev_calculated; a < rates_total; a++)
      {
         g_crossBuy[a] = EMPTY_VALUE; g_crossSell[a] = EMPTY_VALUE;
         g_tenzokoBuy[a] = EMPTY_VALUE; g_tenzokoSell[a] = EMPTY_VALUE;
      }
   }

   //=== STEP 8: 新規バー検出 ===
   bool isNewBar   = false;
   bool isRealTime = (prev_calculated > 0 && !needFullRecalc);
   datetime curBarTime = time[rates_total - 1];
   if(curBarTime != g_last_bar_time)
   { isNewBar = true; g_last_bar_time = curBarTime; }

   //=== STEP 9: シグナル検出ループ ===
   int scanEnd = rates_total - 2;
   int scanStart;
   if(needFullRecalc)       scanStart = g_signal_scan_from;
   else if(isNewBar)        scanStart = g_signal_scan_from;
   else                     scanStart = scanEnd + 1;

   for(int a = scanStart; a <= scanEnd; a++)
   {
      if(g_dpo[a]   == EMPTY_VALUE || g_dpo[a-1]   == EMPTY_VALUE ||
         g_madpo[a] == EMPTY_VALUE || g_madpo[a-1] == EMPTY_VALUE)
         continue;

      bool alertNow = (isRealTime && a == scanEnd);

      //--- 9-A: 天底シグナル ---
      if(Inp_TenzokoAlertOn && g_phase != PHASE_IDLE)
      {
         double ampThreshold = 0.0;
         if(Inp_AmpFilterOn && g_dpoStdDev[a] != EMPTY_VALUE && g_dpoStdDev[a] > 0.0)
            ampThreshold = g_dpoStdDev[a] * Inp_AmpMultiplier;

         double amplitude = MathAbs(g_watermark - g_amplitude_base);

         if(g_phase == PHASE_SEEKING_PEAK &&
            high[a] < high[a-1] &&
            g_dpo[a] < g_watermark &&
            amplitude >= ampThreshold)
         {
            double peakWM   = g_watermark;
            double oldBase  = g_amplitude_base;
            g_tenzokoSell[a] = peakWM;
            g_amplitude_base = peakWM;
            g_watermark      = g_dpo[a];

            if(alertNow)
               SendAlert("TENZOKO", "SELL",
                  StringFormat("天井 WM=%.2f Amp=%.2f Thr=%.2f", peakWM, amplitude, ampThreshold));
            DiagLog(a, time, "TENZOKO_SELL",
               StringFormat("WM=%.2f OldBase=%.2f Amp=%.2f Thr=%.2f", peakWM, oldBase, amplitude, ampThreshold));
         }
         else if(g_phase == PHASE_SEEKING_TROUGH &&
                 low[a] > low[a-1] &&
                 g_dpo[a] > g_watermark &&
                 amplitude >= ampThreshold)
         {
            double troughWM = g_watermark;
            double oldBase  = g_amplitude_base;
            g_tenzokoBuy[a]  = troughWM;
            g_amplitude_base = troughWM;
            g_watermark      = g_dpo[a];

            if(alertNow)
               SendAlert("TENZOKO", "BUY",
                  StringFormat("底 WM=%.2f Amp=%.2f Thr=%.2f", troughWM, amplitude, ampThreshold));
            DiagLog(a, time, "TENZOKO_BUY",
               StringFormat("WM=%.2f OldBase=%.2f Amp=%.2f Thr=%.2f", troughWM, oldBase, amplitude, ampThreshold));
         }
      }

      //--- 9-B: クロスシグナル ---
      bool crossUp   = (g_dpo[a-1] <  g_madpo[a-1]) && (g_dpo[a] >= g_madpo[a]);
      bool crossDown = (g_dpo[a-1] >  g_madpo[a-1]) && (g_dpo[a] <= g_madpo[a]);

      if(crossUp)
      {
         if(Inp_CrossAlertOn)
         {
            g_crossBuy[a] = g_dpo[a];
            if(alertNow)
               SendAlert("CROSS", "BUY",
                  StringFormat("DPO=%.2f MADPO=%.2f", g_dpo[a], g_madpo[a]));
            DiagLog(a, time, "CROSS_BUY",
               StringFormat("DPO=%.2f MADPO=%.2f", g_dpo[a], g_madpo[a]));
         }
         g_phase = PHASE_SEEKING_PEAK;
         g_watermark = g_dpo[a];
         g_amplitude_base = g_dpo[a];
      }
      else if(crossDown)
      {
         if(Inp_CrossAlertOn)
         {
            g_crossSell[a] = g_dpo[a];
            if(alertNow)
               SendAlert("CROSS", "SELL",
                  StringFormat("DPO=%.2f MADPO=%.2f", g_dpo[a], g_madpo[a]));
            DiagLog(a, time, "CROSS_SELL",
               StringFormat("DPO=%.2f MADPO=%.2f", g_dpo[a], g_madpo[a]));
         }
         g_phase = PHASE_SEEKING_TROUGH;
         g_watermark = g_dpo[a];
         g_amplitude_base = g_dpo[a];
      }

      //--- 非クロスバーでのWM更新 ---
      if(!crossUp && !crossDown)
      {
         if(g_phase == PHASE_SEEKING_PEAK && g_dpo[a] != EMPTY_VALUE &&
            g_dpo[a] > g_watermark)
            g_watermark = g_dpo[a];
         else if(g_phase == PHASE_SEEKING_TROUGH && g_dpo[a] != EMPTY_VALUE &&
                 g_dpo[a] < g_watermark)
            g_watermark = g_dpo[a];
      }
   }

   g_signal_scan_from = MathMax(g_signal_scan_from, scanEnd + 1);

   //=== STEP 10: ティックWM更新 ===
   int curBar = rates_total - 1;
   if(g_dpo[curBar] != EMPTY_VALUE && g_phase != PHASE_IDLE)
   {
      if(g_phase == PHASE_SEEKING_PEAK && g_dpo[curBar] > g_watermark)
         g_watermark = g_dpo[curBar];
      else if(g_phase == PHASE_SEEKING_TROUGH && g_dpo[curBar] < g_watermark)
         g_watermark = g_dpo[curBar];
   }

   return rates_total;
}
//+------------------------------------------------------------------+
