# Prompt 5: Portfolio Risk Manager

## Purpose / 目的

Find concentration, hidden correlation, and downside exposure in a portfolio, then propose a risk-adjusted rebalancing and a hedge against a 20% drawdown.

ポートフォリオの集中リスク、隠れた相関、下落耐性を洗い出し、リスク調整後のリバランスと 20% 下落に対するヘッジを提案する。

## Prompt (EN)

```
Analyze my portfolio: [insert tickers and % allocation]. Highlight weak points, overexposure, and hidden correlations. Suggest a rebalancing adjusted to risk and hedging strategies to protect against a 20% market downturn.
```

## プロンプト (JA)

```
私のポートフォリオを分析してください: [ティッカーと配分 % を入力]。弱点、過剰なエクスポージャー、隠れた相関を指摘してください。リスク調整済みのリバランス案と、20% の市場下落から資産を守るヘッジ戦略を提案してください。
```

## Placeholders / プレースホルダー

| Placeholder | Example |
|-------------|---------|
| `[insert tickers and % allocation]` | `AAPL 25%, MSFT 20%, NVDA 20%, GLD 15%, TLT 10%, cash 10%` |

Add account currency, time horizon, and whether leverage is used.

## Expected output / 期待する出力

- Exposure map: by sector, factor, geography, currency
- Hidden correlations (for example three tickers that all move on the same theme)
- Weak points under a 20% equity drawdown, with an estimated portfolio loss
- Rebalancing proposal with target weights and the reason for each change
- Hedging options (index puts, inverse exposure, cash, gold, duration) with cost and trade-offs
- What to monitor after rebalancing

## Notes / 注意

- Correlation figures are INFERRED unless the model computed them from return data you supplied.
- Ask for the cost of each hedge. A hedge with no cost estimate is incomplete.
- 20% 下落シナリオでの推定損失は、前提（ベータ、相関）を明示させる。
