# Prompt 6: Trading Journal Analyzer

## Purpose / 目的

Review a batch of recent trades to surface recurring mistakes, missed opportunities, and behavioral biases, then turn them into a few enforceable rules.

直近のトレード群から繰り返している誤り、取り逃した機会、行動バイアスを抽出し、すぐ実行できるルールに落とし込む。

## Prompt (EN)

```
Review my last 20 trades: [insert trades with entry/exit and results]. Identify recurring errors, missed opportunities, and behavioral biases. Give me 3 personalized rules to immediately increase consistency.
```

## プロンプト (JA)

```
私の直近 20 トレードをレビューしてください: [エントリー/イグジット/損益を含むトレード一覧を入力]。繰り返している誤り、取り逃した機会、行動バイアスを特定してください。一貫性をすぐに高めるための、私専用のルールを 3 つ提示してください。
```

## Placeholders / プレースホルダー

| Placeholder | Example |
|-------------|---------|
| `[insert trades with entry/exit and results]` | Table with date, instrument, direction, entry, exit, stop, size, P/L, and a one-line note on why the trade was taken |

Include the planned stop and the actual exit for each trade. The gap between them is where most behavioral findings come from.

## Expected output / 期待する出力

- Summary statistics: win rate, average R, largest loss, longest losing streak
- Recurring errors with the trade numbers that show them
- Missed opportunities and the reason they were missed
- Behavioral biases detected (loss aversion, revenge trading, early exit, overtrading, etc.) with evidence
- 3 rules, each specific, measurable, and tied to a finding above

## Notes / 注意

- Rules must be checkable before the next trade ("no entry within 30 minutes of a stopped trade"), not vague ("be more patient").
- 連敗中の挙動（ロット増加、ルール逸脱）を特に確認させる。連続損失の構造的防止が目的。
