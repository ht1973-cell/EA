# Trading Prompts Collection / トレーディング・プロンプト集

A reusable set of seven prompts for LLM-assisted trade analysis. Each file holds the
original English prompt verbatim, a Japanese version, the placeholders to fill, and the
output structure to expect.

LLM を使ったトレード分析用の再利用可能なプロンプト 7 本。各ファイルには英語原文（そのまま）、
日本語版、差し替え用プレースホルダー、期待する出力形式を収録しています。

## Index / 目次

| # | Prompt | File | Use case / 用途 |
|---|--------|------|-----------------|
| 1 | Trading Ideas Generator | [01_trading_ideas_generator.md](01_trading_ideas_generator.md) | 当日の高確率セットアップ 5 本を抽出 |
| 2 | Automated Technical Analyst | [02_automated_technical_analyst.md](02_automated_technical_analyst.md) | 日足・週足のテクニカル分析と売買シグナル |
| 3 | News to Trading Converter | [03_news_to_trading_converter.md](03_news_to_trading_converter.md) | ニュースをトレード上の含意へ変換 |
| 4 | Strategy Backtester | [04_strategy_backtester.md](04_strategy_backtester.md) | 戦略のバックテストと改善案 |
| 5 | Portfolio Risk Manager | [05_portfolio_risk_manager.md](05_portfolio_risk_manager.md) | ポートフォリオの弱点・相関・ヘッジ |
| 6 | Trading Journal Analyzer | [06_trading_journal_analyzer.md](06_trading_journal_analyzer.md) | 直近 20 トレードの癖・バイアス分析 |
| 7 | Fully Automated Trading Plan | [07_fully_automated_trading_plan.md](07_fully_automated_trading_plan.md) | タイムスタンプ付きの 1 日トレード計画 |

## Examples / 実行例

Worked runs live in [examples/](examples/). Each one stores the input data, the script that produced every number, and the verification level of each claim.

| Date | Prompt | Instrument | File |
|------|--------|------------|------|
| 2026-09-12 | 2 Automated Technical Analyst | GOLD (GCUSD) | [examples/2026-09-12_GOLD_prompt02_technical_analyst.md](examples/2026-09-12_GOLD_prompt02_technical_analyst.md) |
| 2026-09-12 | 4 Strategy Backtester | GOLD (GCUSD), 2009-2026 | [examples/2026-09-12_GOLD_prompt04_strategy_backtester.md](examples/2026-09-12_GOLD_prompt04_strategy_backtester.md) |

## How to use / 使い方

1. Open the prompt file and copy the block under **Prompt (EN)** or **プロンプト (JA)**.
2. Replace every `[insert ...]` placeholder with your own values (ticker, period, trades, allocation).
3. Paste the prompt together with the data the model needs (chart values, news, trade log). The model cannot see your screen or fetch live prices unless it has a data tool.
4. Read the output against the verification notes below before acting on it.

1. プロンプトファイルを開き、**Prompt (EN)** または **プロンプト (JA)** のブロックをコピーする。
2. `[insert ...]` のプレースホルダーをすべて自分の値（銘柄、期間、トレード、配分）に置き換える。
3. モデルが必要とするデータ（チャートの数値、ニュース、トレード記録）と一緒に貼り付ける。データ取得ツールがない限り、モデルはリアルタイム価格や画面を見ることはできない。
4. 出力を下記の検証メモに照らして確認してから行動する。

## Verification notes / 検証メモ

Output from these prompts is analysis, not a verified result. Treat every figure by its source:

| Level | When it applies |
|-------|-----------------|
| VERIFIED | The model ran the calculation on data you supplied, and you reproduced it |
| SIMULATED | A backtest executed by the model in code on real historical data |
| INFERRED | The model reasoned from the data you pasted without running code |
| UNVERIFIED | Price levels, news, or statistics the model produced without any source |

- A backtest result from Prompt 4 is UNVERIFIED unless the model executed code on real historical data and shows it. Never treat a narrated win rate as a measured one.
- Entry, target, and stop levels from Prompts 1 and 2 are INFERRED at best. Confirm them on your own chart before placing an order.
- News summaries from Prompt 3 need a dated source. Without one they are UNVERIFIED.
- None of this is investment advice. Position sizing and the final decision stay with you.

- プロンプト 4 のバックテスト結果は、モデルが実際の過去データでコードを実行して示さない限り UNVERIFIED。語られただけの勝率を測定値として扱わない。
- プロンプト 1・2 のエントリー、利確、損切り水準は良くても INFERRED。発注前に自分のチャートで確認する。
- プロンプト 3 のニュース要約には日付付きの出典が必要。出典がなければ UNVERIFIED。
- いずれも投資助言ではない。ロットサイズと最終判断は自分で行う。
