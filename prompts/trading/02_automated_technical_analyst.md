# Prompt 2: Automated Technical Analyst

## Purpose / 目的

A structured multi-timeframe technical read on one instrument, ending in an explicit Buy / Hold / Sell signal with justification.

1 銘柄について日足・週足の構造的なテクニカル分析を行い、根拠付きの Buy / Hold / Sell シグナルで締める。

## Prompt (EN)

```
Analyze [insert action/ticker] using daily and weekly charts. Break down support/resistance levels, trend lines, moving averages, and momentum indicators. Provide a step-by-step trading signal (Buy/Hold/Sell) with justification.
```

## プロンプト (JA)

```
[銘柄/ティッカーを入力] を日足チャートと週足チャートで分析してください。サポート/レジスタンス水準、トレンドライン、移動平均線、モメンタム指標を分解して説明してください。段階的なトレードシグナル（Buy/Hold/Sell）を根拠付きで提示してください。
```

## Placeholders / プレースホルダー

| Placeholder | Example |
|-------------|---------|
| `[insert action/ticker]` | `GOLD`, `7203.T`, `SPY` |

Paste recent OHLC values, moving-average readings, and indicator values (RSI, MACD, ADX) with the prompt so the analysis is grounded in numbers.

## Expected output / 期待する出力

1. Weekly structure: trend, major support/resistance, key moving averages
2. Daily structure: trend, near-term levels, trend lines
3. Momentum: RSI, MACD, or equivalent, with divergence notes
4. Alignment check between weekly and daily
5. Signal: Buy / Hold / Sell
6. Justification and the level that would flip the signal

## Notes / 注意

- Ask the model to state which values it used. If it did not receive data, the levels are UNVERIFIED.
- 週足と日足の方向が一致しない場合は Hold 判定にするよう指示すると誤シグナルが減る。
