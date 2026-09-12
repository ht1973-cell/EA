# Prompt 4: Strategy Backtester

## Purpose / 目的

Measure a rule-based strategy on historical data and get concrete ideas for improving its edge.

ルールベース戦略を過去データで検証し、エッジを高めるための具体的な改善案を得る。

## Prompt (EN)

```
Perform a backtest of [insert trading strategy: e.g., moving average crossover, RSI divergence] on [insert stock/index] over the last [insert time period]. Present win rate, profit factor, maximum drawdown, and improvements to increase the edge.
```

## プロンプト (JA)

```
[トレード戦略を入力: 例 移動平均クロス、RSI ダイバージェンス] を [銘柄/指数を入力] に対して直近 [期間を入力] でバックテストしてください。勝率、プロフィットファクター、最大ドローダウンを提示し、エッジを高めるための改善案を示してください。
```

## Placeholders / プレースホルダー

| Placeholder | Example |
|-------------|---------|
| `[insert trading strategy]` | `20/50 EMA crossover with ATR trailing stop` |
| `[insert stock/index]` | `XAUUSD H1`, `S&P 500 daily` |
| `[insert time period]` | `3 years`, `2020-01-01 to 2025-12-31` |

Attach the historical data file (CSV of OHLCV) and define the rules precisely: entry, exit, stop, position size, costs.

## Expected output / 期待する出力

- Rule definition as tested (so you can check it matches your intent)
- Number of trades, win rate, profit factor, maximum drawdown
- Average win / average loss, longest losing streak
- Equity curve description or chart
- Improvements ranked by expected impact, each with the rationale
- Overfitting risk assessment for each improvement

## Notes / 注意

- This prompt only yields a real backtest when the model executes code on the data you supplied. Ask for the code and rerun it yourself. A narrated result without code is UNVERIFIED.
- Require out-of-sample confirmation before accepting any "improvement".
- 連敗回数と最大ドローダウンは必ず確認する。勝率だけで判断しない。
- MQL5 EA として実装する場合は、ここで得た数値を Strategy Tester の結果と突き合わせてから採用する。
