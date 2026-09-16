# MT5 バッチバックテスト手順書

## ファイル構成

```
backtest/
├── sets/                          # パラメータプリセット (.set)
│   ├── VariantJ.set              # Variant-J: Fixed Pyramid + Swing Stop + Long Only
│   ├── VariantK.set              # Variant-K: Martin Pyramid + Swing Stop + Long Only
│   ├── TF_FP_ATR.set             # TF-FP: Fixed Pyramid + ATR Stop
│   ├── TF_FP_Swing.set           # TF-FP: Fixed Pyramid + Swing Stop
│   ├── TF_FP_Pct.set             # TF-FP: Fixed Pyramid + Percent Stop
│   ├── TF_FP_Fixed.set           # TF-FP: Fixed Pyramid + Fixed Points Stop
│   ├── TF_MP_ATR.set             # TF-MP: Martin Pyramid + ATR Stop
│   ├── TF_MP_Swing.set           # TF-MP: Martin Pyramid + Swing Stop
│   ├── NM_S20.set                # NM-S20: Nanpin Safe (DD≤20%)
│   └── NM_R50.set                # NM-R50: Nanpin Risk (DD≤50%)
├── ini/                           # 自動生成INIファイル (実行時生成)
├── reports/                       # HTML/CSVレポート出力先
├── run_all_backtests.bat          # Windows バッチ版
├── run_all_backtests.ps1          # PowerShell版 (推奨)
└── README_BACKTEST.md             # この文書
scripts/
└── BacktestReportCollector.mq5    # 結果CSV集約スクリプト
```

## セットアップ

### 1. EAファイル配置

MT5データフォルダにコピー:
```
MQL5/Experts/GOLD_TrendFollow_Pyramid.mq5
MQL5/Experts/GOLD_NanpinMartin.mq5
MQL5/Scripts/BacktestReportCollector.mq5
```

### 2. コンパイル

MetaEditorで3ファイルともコンパイル (F7):
- エラー0であることを確認
- 警告は許容（非推奨関数警告等）

### 3. .setファイル配置

`backtest/sets/*.set` を以下にコピー:
```
MQL5/Tester/backtest/sets/
```
または `run_all_backtests.ps1` の `ExpertParameters` パスを調整。

## 実行方法

### 方法A: PowerShell一括実行 (推奨)

```powershell
# デフォルト (Every tick, $10,000, 1:100)
.\run_all_backtests.ps1

# OHLC 1分モデル (高速)
.\run_all_backtests.ps1 -Model 1

# カスタム設定
.\run_all_backtests.ps1 -MT5Path "D:\MT5\terminal64.exe" -Deposit 50000 -Leverage 500
```

10構成 × 4期間 = 40テストが順次実行されます。

### 方法B: バッチファイル実行

```cmd
run_all_backtests.bat
```

### 方法C: 手動実行

1. MT5 Strategy Tester を開く (Ctrl+R)
2. Expert: `GOLD_TrendFollow_Pyramid` or `GOLD_NanpinMartin`
3. Symbol: XAUUSD
4. Period: D1 (TF系) / H1 (NM系)
5. Model: Every tick
6. Deposit: $10,000 USD
7. パラメータ読込: 対応する .set ファイルを選択
8. Start

## テスト期間

| 期間 | 開始 | 終了 | 用途 |
|------|------|------|------|
| IS1 | 2008.01.01 | 2015.12.31 | In-Sample 1 |
| IS2 | 2016.01.01 | 2019.12.31 | In-Sample 2 |
| OOS | 2020.01.01 | 2026.09.11 | Out-of-Sample |
| Full | 2008.01.01 | 2026.09.11 | 全期間 |

## 結果集約

### BacktestReportCollector.mq5

各テスト完了後にスクリプト実行で結果をCSVに追記:
1. Strategy Testerでバックテスト完了
2. Navigator → Scripts → BacktestReportCollector
3. ConfigName に構成名を入力 (例: "VariantJ_Full")
4. OK → `MQL5/Files/backtest_results.csv` に1行追加

### CSV出力カラム

Config, Trades, PF, Win%, NetProfit, GrossProfit, GrossLoss,
MaxDD%, MaxDD$, Sharpe, Recovery, Expected, WinTrades, LossTrades,
LongTrades, ShortTrades, MaxConsecWin, MaxConsecLoss, Timestamp

## Python結果との比較ポイント

| 項目 | Python | MT5 | 差異が出る理由 |
|------|--------|-----|---------------|
| 取引数 | 概算 | 正確 | ティックレベル約定 |
| PF | 方向性のみ | 精密 | スプレッド・スリッページ |
| MaxDD% | 日次ベース | ティックベース | 日中DD捕捉 |
| NM系 | 信頼度低 | 高精度 | グリッド約定の再現性 |

特にNM-S20/NM-R50はPython日足シミュレーションとMT5ティック結果の乖離が大きいと予想されます。
