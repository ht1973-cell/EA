//+------------------------------------------------------------------+
//|                   DPO_Tenzoko_signal_v2.01.mq5                   |
//|  DPO Swing Detection（ZigZag原理）                               |
//|  Version: 2.01                                                   |
//+------------------------------------------------------------------+
//  ■ v2.01 変更点
//  - StdDevラチェット方式: 直近N本のStdDev最大値でminSwingを算出
//    → 大相場後のレンジでminSwingが急縮小しない
//  - %Bゲートのデフォルトをfalseに変更
//+------------------------------------------------------------------+
#property copyright   "DPO_Tenzoko_signal"
#property version     "2.01"
#property description "DPO Swing(ZigZag+StdDevRatchet) v2.01"
#property strict

#property indicator_separate_window
#property indicator_buffers 8
#property indicator_plots   7

#property indicator_label1  "DPO"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrRed
#property indicator_width1  1

#property indicator_label2  "MADPO"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrAqua
#property indicator_width2  1

#property indicator_label3  "PriceBB_U"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrYellow
#property indicator_style3  STYLE_DOT
#property indicator_width3  1

#property indicator_label4  "PriceBB_M"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrSilver
#property indicator_style4  STYLE_DASH
#property indicator_width4  1

#property indicator_label5  "PriceBB_L"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrYellow
#property indicator_style5  STYLE_DOT
#property indicator_width5  1

#property indicator_label6  "SwingBUY"
#property indicator_type6   DRAW_ARROW
#property indicator_color6  clrLime
#property indicator_width6  2

#property indicator_label7  "SwingSELL"
#property indicator_type7   DRAW_ARROW
#property indicator_color7  clrMagenta
#property indicator_width7  2

//+------------------------------------------------------------------+
enum ENUM_MA_METHOD_SIMPLE{MA_SMA_MODE,MA_EMA_MODE};
enum ENUM_SWING_DIR{SWING_INIT,SWING_UP,SWING_DOWN};

//+------------------------------------------------------------------+
input group "=== DPO / MADPO ==="
input int                   Inp_DPO_Period   =20;
input ENUM_MA_METHOD_SIMPLE Inp_DPO_MAType   =MA_SMA_MODE;
input int                   Inp_MADPO_Period =20;
input ENUM_MA_METHOD_SIMPLE Inp_MADPO_MAType =MA_SMA_MODE;
input ENUM_APPLIED_PRICE    Inp_AppliedPrice =PRICE_CLOSE;
input int                   Inp_MaxCalcBars  =3000;

input group "=== 価格BB ==="
input double Inp_BB_Sigma =2.0;
input int    Inp_BB_Period=20;

input group "=== スイング検出 ==="
input double Inp_SwingMultiplier  =1.5;   // minSwing = StdDevMax × この倍率
input int    Inp_SwingLookback    =20;    // StdDev計算期間
input int    Inp_StdDevMaxLookback=60;    // StdDev最大値の記憶バー数（ラチェット窓）

input group "=== %Bゲート（任意） ==="
input bool   Inp_PctBFilterOn =false;     // v2.01: デフォルトfalse
input double Inp_PctB_BuyGate =0.2;
input double Inp_PctB_SellGate=0.8;

input group "=== 通知 ==="
input bool   Inp_AlertPopup  =true;
input bool   Inp_AlertSound  =true;
input bool   Inp_AlertEmail  =false;
input bool   Inp_AlertPush   =false;
input bool   Inp_AlertDiscord=false;
input string Inp_DiscordURL  ="";

input group "=== 診断ログ ==="
input bool Inp_DiagLog=true;

//+------------------------------------------------------------------+
double g_dpo[],g_madpo[];
double g_bbUpper[],g_bbMiddle[],g_bbLower[];
double g_swingBuy[],g_swingSell[];
double g_dpoStdDev[]; // ラチェット適用後のStdDev最大値を格納

ENUM_SWING_DIR g_swingDir =SWING_INIT;
double g_watermark         =0;
double g_initHigh          =EMPTY_VALUE;
double g_initLow           =EMPTY_VALUE;
datetime g_last_bar_time   =0;
int    g_signal_scan_from  =0;
bool   g_full_recalc       =true;

//+------------------------------------------------------------------+
void CalcSMA(const double &src[],int period,int n,double &dst[])
{double sum=0;int vc=0;double wc[];ArrayResize(wc,n);ArrayCopy(wc,src);
 for(int i=0;i<n;i++){if(src[i]==EMPTY_VALUE){dst[i]=EMPTY_VALUE;sum=0;vc=0;continue;}
 sum+=src[i];vc++;if(vc>period)sum-=wc[i-period];dst[i]=(vc>=period)?sum/period:EMPTY_VALUE;}}

void CalcEMA(const double &src[],int period,int n,double &dst[])
{double k=2.0/(period+1.0);int rs=-1;
 for(int i=0;i<n;i++){if(src[i]==EMPTY_VALUE){dst[i]=EMPTY_VALUE;rs=-1;continue;}
 if(rs<0)rs=i;int p=i-rs;if(p<period-1){dst[i]=EMPTY_VALUE;continue;}
 if(p==period-1){double s=0;for(int j=rs;j<=i;j++)s+=src[j];dst[i]=s/period;}
 else{dst[i]=dst[i-1]+k*(src[i]-dst[i-1]);}}}

void CalcMA(const double &s[],int p,int n,ENUM_MA_METHOD_SIMPLE m,double &d[])
{if(m==MA_EMA_MODE)CalcEMA(s,p,n,d);else CalcSMA(s,p,n,d);}

void CalcRollingStdDev(const double &src[],int period,int n,double &dst[])
{for(int i=0;i<n;i++){if(i<period-1||src[i]==EMPTY_VALUE){dst[i]=EMPTY_VALUE;continue;}
 double sum=0,sq=0;bool ok=true;for(int j=i-period+1;j<=i;j++)
 {if(j<0||src[j]==EMPTY_VALUE){ok=false;break;}sum+=src[j];sq+=src[j]*src[j];}
 if(!ok){dst[i]=EMPTY_VALUE;continue;}double mn=sum/period,v=sq/period-mn*mn;
 dst[i]=(v>0)?MathSqrt(v):0;}}

//+------------------------------------------------------------------+
//| StdDevローリング最大値（ラチェット）                                |
//+------------------------------------------------------------------+
void CalcRollingMax(const double &src[],int lookback,int n,double &dst[])
{
   for(int i=0;i<n;i++)
   {
      if(src[i]==EMPTY_VALUE){dst[i]=EMPTY_VALUE;continue;}
      double mx=0;
      int start=MathMax(0,i-lookback+1);
      for(int j=start;j<=i;j++)
      {
         if(src[j]!=EMPTY_VALUE&&src[j]>mx) mx=src[j];
      }
      dst[i]=(mx>0)?mx:src[i]; // 最大値が0ならraw値にフォールバック
   }
}

//+------------------------------------------------------------------+
void SendAlert(string dir,string detail)
{string msg=StringFormat("[%s] %s SWING_%s | %s",_Symbol,EnumToString(_Period),dir,detail);
 if(Inp_AlertPopup)Alert(msg);if(Inp_AlertSound)PlaySound("alert.wav");
 if(Inp_AlertEmail)SendMail("DPO_Swing: "+dir,msg);
 if(Inp_AlertPush)SendNotification(msg);
 if(Inp_AlertDiscord&&Inp_DiscordURL!="")SendDiscordMsg(msg);Print("SIGNAL: ",msg);}

void SendDiscordMsg(string message)
{if(Inp_DiscordURL=="")return;
 if(MQLInfoInteger(MQL_PROGRAM_TYPE)==PROGRAM_INDICATOR)
 {static bool w=false;if(!w){Print("WARNING: Discord不可(IND)");w=true;}return;}
 string j="{\"content\":\""+message+"\"}";char d[],r[];string rh;
 StringToCharArray(j,d,0,WHOLE_ARRAY,CP_UTF8);ArrayResize(d,ArraySize(d)-1);
 WebRequest("POST",Inp_DiscordURL,"Content-Type: application/json\r\n",5000,d,r,rh);}

//+------------------------------------------------------------------+
double CalcPctB(int a)
{if(g_bbUpper[a]==EMPTY_VALUE||g_bbLower[a]==EMPTY_VALUE||g_dpo[a]==EMPTY_VALUE)return 0.5;
 double bw=g_bbUpper[a]-g_bbLower[a];if(bw<=0)return 0.5;
 return(g_dpo[a]-g_bbLower[a])/bw;}

void DiagLog(int a,const datetime &time[],string evt,string detail)
{if(!Inp_DiagLog)return;
 double pctB=CalcPctB(a);
 double sdMax=(g_dpoStdDev[a]!=EMPTY_VALUE)?g_dpoStdDev[a]:0;
 Print(StringFormat("DIAG [%s] %s | DPO=%.2f MADPO=%.2f BB_U=%.2f BB_M=%.2f BB_L=%.2f SDmax=%.2f %%B=%.3f | Dir=%s WM=%.2f | %s",
 TimeToString(time[a],TIME_DATE|TIME_MINUTES|TIME_SECONDS),evt,
 (g_dpo[a]!=EMPTY_VALUE?g_dpo[a]:0),(g_madpo[a]!=EMPTY_VALUE?g_madpo[a]:0),
 (g_bbUpper[a]!=EMPTY_VALUE?g_bbUpper[a]:0),(g_bbMiddle[a]!=EMPTY_VALUE?g_bbMiddle[a]:0),
 (g_bbLower[a]!=EMPTY_VALUE?g_bbLower[a]:0),sdMax,pctB,
 EnumToString(g_swingDir),g_watermark,detail));}

//+------------------------------------------------------------------+
int OnInit()
{
   if(Inp_DPO_Period<2||Inp_MADPO_Period<1||Inp_BB_Period<2||Inp_BB_Sigma<=0||
      Inp_SwingLookback<2||Inp_SwingMultiplier<=0||Inp_StdDevMaxLookback<1)
   {Alert("パラメータエラー");return INIT_PARAMETERS_INCORRECT;}

   SetIndexBuffer(0,g_dpo,INDICATOR_DATA);
   SetIndexBuffer(1,g_madpo,INDICATOR_DATA);
   SetIndexBuffer(2,g_bbUpper,INDICATOR_DATA);
   SetIndexBuffer(3,g_bbMiddle,INDICATOR_DATA);
   SetIndexBuffer(4,g_bbLower,INDICATOR_DATA);
   SetIndexBuffer(5,g_swingBuy,INDICATOR_DATA);
   SetIndexBuffer(6,g_swingSell,INDICATOR_DATA);
   SetIndexBuffer(7,g_dpoStdDev,INDICATOR_CALCULATIONS);

   ArraySetAsSeries(g_dpo,false);ArraySetAsSeries(g_madpo,false);
   ArraySetAsSeries(g_bbUpper,false);ArraySetAsSeries(g_bbMiddle,false);
   ArraySetAsSeries(g_bbLower,false);ArraySetAsSeries(g_swingBuy,false);
   ArraySetAsSeries(g_swingSell,false);ArraySetAsSeries(g_dpoStdDev,false);

   for(int i=0;i<8;i++)PlotIndexSetDouble(i,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetInteger(5,PLOT_ARROW,233);
   PlotIndexSetInteger(6,PLOT_ARROW,234);

   IndicatorSetString(INDICATOR_SHORTNAME,
      StringFormat("DPO_Swing(%d/%d) v2.01",Inp_DPO_Period,Inp_MADPO_Period));

   IndicatorSetInteger(INDICATOR_LEVELS,19);
   int idx=0;
   IndicatorSetDouble(INDICATOR_LEVELVALUE,idx,0);
   IndicatorSetInteger(INDICATOR_LEVELCOLOR,idx,clrDimGray);
   IndicatorSetInteger(INDICATOR_LEVELSTYLE,idx,STYLE_DOT);
   IndicatorSetInteger(INDICATOR_LEVELWIDTH,idx,1);idx++;
   for(int s=1;s<=9;s++){double v=s*0.1;
      IndicatorSetDouble(INDICATOR_LEVELVALUE,idx,v);
      IndicatorSetInteger(INDICATOR_LEVELCOLOR,idx,clrSlateGray);
      IndicatorSetInteger(INDICATOR_LEVELSTYLE,idx,STYLE_DOT);
      IndicatorSetInteger(INDICATOR_LEVELWIDTH,idx,1);idx++;
      IndicatorSetDouble(INDICATOR_LEVELVALUE,idx,-v);
      IndicatorSetInteger(INDICATOR_LEVELCOLOR,idx,clrSlateGray);
      IndicatorSetInteger(INDICATOR_LEVELSTYLE,idx,STYLE_DOT);
      IndicatorSetInteger(INDICATOR_LEVELWIDTH,idx,1);idx++;}

   g_swingDir=SWING_INIT;g_watermark=0;
   g_initHigh=EMPTY_VALUE;g_initLow=EMPTY_VALUE;
   g_last_bar_time=0;g_signal_scan_from=0;g_full_recalc=true;
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason){Comment("");}

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,const int prev_calculated,
                const datetime &time[],const double &open[],
                const double &high[],const double &low[],
                const double &close[],const long &tick_volume[],
                const long &volume[],const int &spread[])
{
   int shift=Inp_DPO_Period/2+1;
   int minBars=Inp_DPO_Period*2+Inp_MADPO_Period+10;
   minBars=MathMax(minBars,Inp_BB_Period+shift+Inp_DPO_Period+10);
   minBars=MathMax(minBars,Inp_SwingLookback+Inp_StdDevMaxLookback+shift+Inp_DPO_Period+10);
   if(rates_total<minBars)return 0;

   int wS=MathMax(0,rates_total-Inp_MaxCalcBars);
   int wL=rates_total-wS;
   if(wL<minBars){wS=MathMax(0,rates_total-minBars);wL=rates_total-wS;}

   // --- 価格 ---
   double price[];ArrayResize(price,wL);
   for(int i=0;i<wL;i++){int a=wS+i;
      switch(Inp_AppliedPrice){
      case PRICE_OPEN:price[i]=open[a];break;case PRICE_HIGH:price[i]=high[a];break;
      case PRICE_LOW:price[i]=low[a];break;case PRICE_MEDIAN:price[i]=(high[a]+low[a])/2;break;
      case PRICE_TYPICAL:price[i]=(high[a]+low[a]+close[a])/3;break;
      case PRICE_WEIGHTED:price[i]=(high[a]+low[a]+2*close[a])/4;break;
      default:price[i]=close[a];break;}}

   // --- DPO ---
   double base[];ArrayResize(base,wL);CalcMA(price,Inp_DPO_Period,wL,Inp_DPO_MAType,base);
   double dW[];ArrayResize(dW,wL);
   for(int i=0;i<wL;i++){int x=i-shift;
      dW[i]=(x>=0&&base[x]!=EMPTY_VALUE)?price[i]-base[x]:EMPTY_VALUE;}

   // --- MADPO ---
   double mW[];ArrayResize(mW,wL);CalcMA(dW,Inp_MADPO_Period,wL,Inp_MADPO_MAType,mW);
   for(int i=0;i<wL;i++)if(dW[i]==EMPTY_VALUE)mW[i]=EMPTY_VALUE;

   // --- 価格BB→デトレンド ---
   double pSMA[];ArrayResize(pSMA,wL);CalcSMA(price,Inp_BB_Period,wL,pSMA);
   double pSD[];ArrayResize(pSD,wL);CalcRollingStdDev(price,Inp_BB_Period,wL,pSD);
   double bU[],bM[],bL[];ArrayResize(bU,wL);ArrayResize(bM,wL);ArrayResize(bL,wL);
   for(int i=0;i<wL;i++){int x=i-shift;
      if(x<0||base[x]==EMPTY_VALUE||pSMA[i]==EMPTY_VALUE||pSD[i]==EMPTY_VALUE)
      {bU[i]=EMPTY_VALUE;bM[i]=EMPTY_VALUE;bL[i]=EMPTY_VALUE;}
      else{double dt=base[x];
           bU[i]=(pSMA[i]+Inp_BB_Sigma*pSD[i])-dt;
           bM[i]=pSMA[i]-dt;
           bL[i]=(pSMA[i]-Inp_BB_Sigma*pSD[i])-dt;}}

   // --- DPO StdDev(raw) ---
   double sdRaw[];ArrayResize(sdRaw,wL);
   CalcRollingStdDev(dW,Inp_SwingLookback,wL,sdRaw);

   // --- StdDevローリング最大値（ラチェット） ---
   double sdMax[];ArrayResize(sdMax,wL);
   CalcRollingMax(sdRaw,Inp_StdDevMaxLookback,wL,sdMax);

   // --- バッファ転写 ---
   for(int a=0;a<wS;a++){
      g_dpo[a]=EMPTY_VALUE;g_madpo[a]=EMPTY_VALUE;
      g_bbUpper[a]=EMPTY_VALUE;g_bbMiddle[a]=EMPTY_VALUE;g_bbLower[a]=EMPTY_VALUE;
      g_swingBuy[a]=EMPTY_VALUE;g_swingSell[a]=EMPTY_VALUE;g_dpoStdDev[a]=EMPTY_VALUE;}
   for(int i=0;i<wL;i++){int a=wS+i;
      g_dpo[a]=dW[i];g_madpo[a]=mW[i];
      g_bbUpper[a]=bU[i];g_bbMiddle[a]=bM[i];g_bbLower[a]=bL[i];
      g_dpoStdDev[a]=sdMax[i];} // ★ラチェット適用済みのStdDev最大値を格納

   // --- 再計算判定 ---
   bool needFull=(prev_calculated<2||g_full_recalc);
   if(needFull){
      for(int a=0;a<rates_total;a++){g_swingBuy[a]=EMPTY_VALUE;g_swingSell[a]=EMPTY_VALUE;}
      g_swingDir=SWING_INIT;g_watermark=0;g_initHigh=EMPTY_VALUE;g_initLow=EMPTY_VALUE;
      g_signal_scan_from=wS+shift+Inp_DPO_Period+MathMax(Inp_MADPO_Period,Inp_SwingLookback+Inp_StdDevMaxLookback)+2;
      g_signal_scan_from=MathMax(g_signal_scan_from,wS+Inp_BB_Period+shift+Inp_DPO_Period+2);
      g_full_recalc=false;g_last_bar_time=0;
   }else{
      for(int a=prev_calculated;a<rates_total;a++){g_swingBuy[a]=EMPTY_VALUE;g_swingSell[a]=EMPTY_VALUE;}}

   bool isNewBar=false;bool isRT=(prev_calculated>0&&!needFull);
   datetime cbt=time[rates_total-1];
   if(cbt!=g_last_bar_time){isNewBar=true;g_last_bar_time=cbt;}

   // --- スイング検出ループ ---
   int scanEnd=rates_total-2;
   int scanStart;
   if(needFull)scanStart=g_signal_scan_from;
   else if(isNewBar)scanStart=g_signal_scan_from;
   else scanStart=scanEnd+1;

   for(int a=scanStart;a<=scanEnd;a++)
   {
      double dpo=g_dpo[a];
      if(dpo==EMPTY_VALUE)continue;
      // g_dpoStdDevにはラチェット適用済みの最大値が入っている
      double sdM=(g_dpoStdDev[a]!=EMPTY_VALUE&&g_dpoStdDev[a]>0)?g_dpoStdDev[a]:0;
      double minSwing=(sdM>0)?sdM*Inp_SwingMultiplier:999999;
      bool alertNow=(isRT&&a==scanEnd);

      //--- SWING_INIT ---
      if(g_swingDir==SWING_INIT)
      {
         if(g_initHigh==EMPTY_VALUE){g_initHigh=dpo;g_initLow=dpo;continue;}
         if(dpo>g_initHigh)g_initHigh=dpo;
         if(dpo<g_initLow)g_initLow=dpo;

         if(g_initHigh-dpo>=minSwing)
         {
            g_swingDir=SWING_DOWN;g_watermark=dpo;
            DiagLog(a,time,"INIT→DOWN",
               StringFormat("InitH=%.2f InitL=%.2f minSw=%.2f SDmax=%.2f",
                            g_initHigh,g_initLow,minSwing,sdM));
         }
         else if(dpo-g_initLow>=minSwing)
         {
            g_swingDir=SWING_UP;g_watermark=dpo;
            DiagLog(a,time,"INIT→UP",
               StringFormat("InitH=%.2f InitL=%.2f minSw=%.2f SDmax=%.2f",
                            g_initHigh,g_initLow,minSwing,sdM));
         }
         continue;
      }

      //--- SWING_UP ---
      if(g_swingDir==SWING_UP)
      {
         if(dpo>g_watermark)g_watermark=dpo;

         if(g_watermark-dpo>=minSwing)
         {
            double pctB=CalcPctB(a);
            bool gatePass=(!Inp_PctBFilterOn||pctB<=Inp_PctB_SellGate);

            if(gatePass)
            {
               g_swingSell[a]=g_watermark;
               if(alertNow)
                  SendAlert("SELL",StringFormat("天井 WM=%.2f DPO=%.2f minSw=%.2f SDmax=%.2f",
                            g_watermark,dpo,minSwing,sdM));
               DiagLog(a,time,"SWING_SELL",
                  StringFormat("WM=%.2f DPO=%.2f Drop=%.2f minSw=%.2f SDmax=%.2f %%B=%.3f",
                               g_watermark,dpo,g_watermark-dpo,minSwing,sdM,pctB));
            }
            else
            {
               DiagLog(a,time,"SELL_BLOCKED(%B)",
                  StringFormat("WM=%.2f DPO=%.2f %%B=%.3f>Gate=%.2f",
                               g_watermark,dpo,pctB,Inp_PctB_SellGate));
            }
            g_swingDir=SWING_DOWN;g_watermark=dpo;
         }
      }
      //--- SWING_DOWN ---
      else if(g_swingDir==SWING_DOWN)
      {
         if(dpo<g_watermark)g_watermark=dpo;

         if(dpo-g_watermark>=minSwing)
         {
            double pctB=CalcPctB(a);
            bool gatePass=(!Inp_PctBFilterOn||pctB>=Inp_PctB_BuyGate);

            if(gatePass)
            {
               g_swingBuy[a]=g_watermark;
               if(alertNow)
                  SendAlert("BUY",StringFormat("底 WM=%.2f DPO=%.2f minSw=%.2f SDmax=%.2f",
                            g_watermark,dpo,minSwing,sdM));
               DiagLog(a,time,"SWING_BUY",
                  StringFormat("WM=%.2f DPO=%.2f Rise=%.2f minSw=%.2f SDmax=%.2f %%B=%.3f",
                               g_watermark,dpo,dpo-g_watermark,minSwing,sdM,pctB));
            }
            else
            {
               DiagLog(a,time,"BUY_BLOCKED(%B)",
                  StringFormat("WM=%.2f DPO=%.2f %%B=%.3f<Gate=%.2f",
                               g_watermark,dpo,pctB,Inp_PctB_BuyGate));
            }
            g_swingDir=SWING_UP;g_watermark=dpo;
         }
      }
   }
   g_signal_scan_from=MathMax(g_signal_scan_from,scanEnd+1);

   // --- ティックWM ---
   int cur=rates_total-1;
   if(g_dpo[cur]!=EMPTY_VALUE&&g_swingDir!=SWING_INIT)
   {
      if(g_swingDir==SWING_UP&&g_dpo[cur]>g_watermark)
         g_watermark=g_dpo[cur];
      else if(g_swingDir==SWING_DOWN&&g_dpo[cur]<g_watermark)
         g_watermark=g_dpo[cur];
   }

   return rates_total;
}
//+------------------------------------------------------------------+
