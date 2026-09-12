# Prompt 7: Fully Automated Trading Plan

## Purpose / 目的

A complete daily routine for one market, delivered as a timestamped checklist covering pre-market, open, mid-session, and close.

1 つの市場について、プレマーケットから引けまでを網羅したタイムスタンプ付きチェックリストの 1 日計画を作る。

## Prompt (EN)

```
Design a daily trading plan for [insert market/asset]. Include pre-market scanning, opening strategy, mid-session adjustments, and closing strategy. Deliver it as a checklist with timestamps that I can follow like a professional trader.
```

## プロンプト (JA)

```
[市場/資産を入力] のデイリートレード計画を設計してください。プレマーケットのスキャン、寄り付きの戦略、セッション中盤の調整、引けの戦略を含めてください。プロのトレーダーのように従えるタイムスタンプ付きチェックリストとして提示してください。
```

## Placeholders / プレースホルダー

| Placeholder | Example |
|-------------|---------|
| `[insert market/asset]` | `XAUUSD (London and New York sessions)`, `Nikkei 225 futures`, `US large-cap equities` |

State your time zone and the sessions you actually trade so the timestamps are usable.

## Expected output / 期待する出力

- Pre-market (with times): news and calendar check, key levels, bias, max risk for the day
- Open: first-minutes rule (trade or wait), setups allowed, size
- Mid-session: review points, adjustment rules, when to stop trading for the day
- Close: position handling into the close, journal entry, next-day prep
- Hard rules: daily loss limit, max trades, no-trade conditions

## Notes / 注意

- Ask the model to include a "stop trading today" condition. A plan without a daily loss limit is incomplete.
- 時間帯別ロジック（東京・ロンドン・NY）を分けて記述させると EA のセッションフィルター設計にも流用できる。
