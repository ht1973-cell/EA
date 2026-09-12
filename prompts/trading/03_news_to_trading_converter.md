# Prompt 3: News to Trading Converter

## Purpose / 目的

Turn a news flow into trading implications: time horizons, expected price range, and positioning.

ニュースをトレード上の含意へ変換する。時間軸、想定値幅、推奨ポジショニングまで落とし込む。

## Prompt (EN)

```
Summarize the latest news on [insert company/sector] and translate them into trading implications. Provide possible short- and long-term effects, expected price movement range, and recommended positioning.
```

## プロンプト (JA)

```
[企業/セクターを入力] に関する最新ニュースを要約し、トレード上の含意に翻訳してください。短期および長期に起こり得る影響、想定される価格変動レンジ、推奨するポジショニングを提示してください。
```

## Placeholders / プレースホルダー

| Placeholder | Example |
|-------------|---------|
| `[insert company/sector]` | `NVIDIA`, `Japanese banks`, `gold miners` |

Paste the news items (headline, source, date) yourself. A model without a search tool cannot fetch "the latest news".

## Expected output / 期待する出力

- News summary with source and date per item
- Short-term effect (days) and long-term effect (weeks to months)
- Expected price movement range with the reasoning behind it
- Recommended positioning: direction, size bias, hedges
- Scheduled events that could change the view

## Notes / 注意

- Each item needs a date and source. Undated news is UNVERIFIED.
- Ask for the counter-case: "what would make the market react the opposite way".
- 相場心理（MYTHOS 視点）を確認したい場合は「市場参加者はこのニュースをどう解釈しがちか」を追加で問う。
