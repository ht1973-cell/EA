//+------------------------------------------------------------------+
//| BacktestReportCollector.mq5                                      |
//| MT5 Strategy Tester結果をCSVに集約するスクリプト                     |
//| 使い方: テスト完了後にスクリプトとして実行                            |
//|         直近のバックテスト統計をCSV行として追記                       |
//+------------------------------------------------------------------+
#property copyright "2026"
#property version   "1.00"
#property script_show_inputs

input string InpConfigName  = "VariantJ_Full";   // テスト構成名
input string InpOutputFile  = "backtest_results.csv"; // 出力CSVファイル名

//+------------------------------------------------------------------+
//| Script program start function                                     |
//+------------------------------------------------------------------+
void OnStart()
{
   // Strategy Testerの統計値を取得
   double stat_profit        = TesterStatistics(STAT_PROFIT);
   double stat_gross_profit  = TesterStatistics(STAT_GROSS_PROFIT);
   double stat_gross_loss    = TesterStatistics(STAT_GROSS_LOSS);
   double stat_max_dd_pct    = TesterStatistics(STAT_EQUITYDD_PERCENT);
   double stat_max_dd_abs    = TesterStatistics(STAT_EQUITY_DD);
   double stat_sharpe        = TesterStatistics(STAT_SHARPE_RATIO);
   double stat_profit_factor = TesterStatistics(STAT_PROFIT_FACTOR);
   double stat_recovery      = TesterStatistics(STAT_RECOVERY_FACTOR);
   double stat_expected      = TesterStatistics(STAT_EXPECTED_PAYOFF);

   int    stat_trades        = (int)TesterStatistics(STAT_TRADES);
   int    stat_profit_trades = (int)TesterStatistics(STAT_PROFIT_TRADES);
   int    stat_loss_trades   = (int)TesterStatistics(STAT_LOSS_TRADES);
   int    stat_short_trades  = (int)TesterStatistics(STAT_SHORT_TRADES);
   int    stat_long_trades   = (int)TesterStatistics(STAT_LONG_TRADES);
   int    stat_max_consec_w  = (int)TesterStatistics(STAT_MAX_CONPROFIT_TRADES);
   int    stat_max_consec_l  = (int)TesterStatistics(STAT_MAX_CONLOSS_TRADES);

   double win_pct = (stat_trades > 0) ? (double)stat_profit_trades / stat_trades * 100.0 : 0.0;

   // ファイルオープン（追記モード）
   int handle = FileOpen(InpOutputFile, FILE_WRITE | FILE_READ | FILE_CSV | FILE_ANSI, ',');
   if(handle == INVALID_HANDLE)
   {
      Print("Error: ファイルを開けません: ", InpOutputFile, " Error=", GetLastError());
      return;
   }

   // ファイルが空ならヘッダー行を書く
   if(FileSize(handle) == 0)
   {
      FileWrite(handle,
         "Config",
         "Trades",
         "PF",
         "Win%",
         "NetProfit",
         "GrossProfit",
         "GrossLoss",
         "MaxDD%",
         "MaxDD$",
         "Sharpe",
         "Recovery",
         "Expected",
         "WinTrades",
         "LossTrades",
         "LongTrades",
         "ShortTrades",
         "MaxConsecWin",
         "MaxConsecLoss",
         "Timestamp"
      );
   }
   else
   {
      FileSeek(handle, 0, SEEK_END);
   }

   // データ行を書く
   FileWrite(handle,
      InpConfigName,
      IntegerToString(stat_trades),
      DoubleToString(stat_profit_factor, 2),
      DoubleToString(win_pct, 1),
      DoubleToString(stat_profit, 2),
      DoubleToString(stat_gross_profit, 2),
      DoubleToString(stat_gross_loss, 2),
      DoubleToString(stat_max_dd_pct, 2),
      DoubleToString(stat_max_dd_abs, 2),
      DoubleToString(stat_sharpe, 2),
      DoubleToString(stat_recovery, 2),
      DoubleToString(stat_expected, 2),
      IntegerToString(stat_profit_trades),
      IntegerToString(stat_loss_trades),
      IntegerToString(stat_long_trades),
      IntegerToString(stat_short_trades),
      IntegerToString(stat_max_consec_w),
      IntegerToString(stat_max_consec_l),
      TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS)
   );

   FileClose(handle);

   Print("=== Backtest Result Saved ===");
   Print("Config: ", InpConfigName);
   Print("Trades: ", stat_trades, "  PF: ", DoubleToString(stat_profit_factor, 2),
         "  Win%: ", DoubleToString(win_pct, 1));
   Print("Net: ", DoubleToString(stat_profit, 2),
         "  MaxDD%: ", DoubleToString(stat_max_dd_pct, 2),
         "  Sharpe: ", DoubleToString(stat_sharpe, 2));
   Print("Output: ", InpOutputFile);
}
//+------------------------------------------------------------------+
