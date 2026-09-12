# Prompt 1: Trading Ideas Generator

## Purpose / 目的

Produce a short list of concrete, tradeable setups for one instrument, index, or sector, each with a full trade plan (entry, targets, stop, risk/reward) and the reasoning behind it.

特定の銘柄・指数・セクターについて、エントリー、利確目標、損切り、リスクリワードを揃えた具体的なセットアップを 5 本抽出する。

## Prompt (EN)

```
Scan today's market and generate 5 high-probability trading setups for [insert stock/index/sector]. Include entry price, exit targets, stop-loss, and risk/reward ratio. Explain why each setup works based on technical and fundamental factors.
```

## プロンプト (JA)

```
本日の市場をスキャンし、[銘柄/指数/セクターを入力] について高確率のトレードセットアップを 5 つ生成してください。各セットアップにエントリー価格、利確目標、損切り、リスクリワード比を含めてください。それぞれのセットアップがテクニカル要因とファンダメンタル要因の両面からなぜ機能するのかを説明してください。
```

## Placeholders / プレースホルダー

| Placeholder | Example |
|-------------|---------|
| `[insert stock/index/sector]` | `XAUUSD`, `Nikkei 225`, `US semiconductors` |

Supply current prices and key levels with the prompt. Without them the model has no "today" to scan.

## Expected output / 期待する出力

For each of the 5 setups:

- Direction (long / short) and setup type (breakout, pullback, range fade, etc.)
- Entry price or trigger condition
- Target 1 / Target 2
- Stop-loss
- Risk/reward ratio
- Technical rationale
- Fundamental rationale
- What invalidates the idea

## Notes / 注意

- Ask for the source of every fundamental claim. Unsourced claims are UNVERIFIED.
- Add "and list the assumptions you made about current price" to make missing data visible.
- 価格水準は自分のチャートで確認してから使う。
