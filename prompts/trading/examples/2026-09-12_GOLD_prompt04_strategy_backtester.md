# Example: Prompt 4 (Strategy Backtester) on GOLD / XAUUSD

実行日 / Run date: 2026-09-12
対象 / Instrument: Gold futures front month `GCUSD` (proxy for XAUUSD), daily bars
期間 / Period: 2008-01-02 to 2026-09-11 (4,861 bars; 2008 used as indicator warm-up)

## 検証レベル / Verification level

| Item | Level | Source |
|------|-------|--------|
| Daily OHLCV 2008 to 2026 | VERIFIED | FMP commodities EOD, saved as `GCUSD_daily_2008-01-02_2026-09-11.csv`. 0 malformed bars, 0 gaps over 5 days |
| Every number in this file | SIMULATED | `backtest_prompt04.py` (standard library only), output in `backtest_prompt04_results.json` |
| Strategy rules A to F | Pre-registered | Fixed before the first run |
| Strategy rules G to L | Post-hoc | Designed after reading the in-sample table and the trade log. Their in-sample figures are therefore not a fair test; only their out-of-sample figures are |
| Improvement ranking | INFERRED | Reasoning from the tables below |

Rerun everything (about one second):

```bash
python3 backtest_prompt04.py GCUSD_daily_2008-01-02_2026-09-11.csv --grid --log
```

## Prompt as filled in

```
Perform a backtest of an EMA 20/50 crossover with a 2-ATR initial stop and a 3-ATR trailing stop on GOLD (GCUSD daily) over the last 17 years (2009-01-01 to 2026-09-11). Present win rate, profit factor, maximum drawdown, and improvements to increase the edge.
```

## ルール定義 / Rules as tested

Fixed before running. The pyramiding rules copy the `CanPyramid()` / `ExecutePyramid()` logic in the MQL5 EA skill so the result speaks to that design.

| Element | Rule |
|---------|------|
| Signal | EMA20 crosses EMA50 on the daily close |
| Execution | Next day's open |
| Direction | Long and short (baseline), or long only |
| Initial stop | 2.0 x ATR14 from entry, per unit |
| Trailing stop | Highest high since entry minus 3.0 x ATR14 (mirror for shorts), ratchets only |
| Exit | Stop hit (gaps fill at the open), or opposite cross at the next open |
| Sizing | 1% of current equity at risk per initial unit, so 1R = 1% of equity |
| Pyramiding (D, E, F, H, K) | Add when close moves 1.5 ATR beyond the last entry and the position is in profit. Unit sizes 1.0 / 0.7 / 0.5 / 0.3. Max 3 adds. Total open risk capped at 3% of equity |
| Add-unit stop | D, E, F: last entry minus 0.5 ATR (the skill's rule). H, K: the shared trailing stop only |
| ADX filter (C, E, F, I) | New entries only when ADX14 is above 25 (or 20 for I) |
| Re-entry (J, K, L) | After a stop-out, re-enter when the EMAs are still aligned and the close crosses back over EMA20 |
| Costs | 0.25 USD per ounce per side (spread plus slippage). No financing or roll costs |
| Equity | 100,000 USD start, marked to market daily |
| Splits | In-sample 2009 to 2019, out-of-sample 2020 to 2026-09-11 |

A trade below is one campaign: first entry until flat. Pyramided units are counted separately in the JSON.

## 結果: 事前登録した戦略 A〜F / Pre-registered variants

Out-of-sample 2020 to 2026-09-11 (gold buy-and-hold over the same window: +189.5%):

| Variant | Trades | Win rate | Profit factor | CAGR | Max DD | Expectancy (R) | Max consecutive losses |
|---------|--------|----------|---------------|------|--------|----------------|------------------------|
| A baseline long+short | 28 | 28.6% | 0.78 | -0.45% | 7.8% | -0.09 | 6 |
| B long only | 14 | 35.7% | 1.47 | 0.39% | 3.8% | +0.21 | 3 |
| C ADX>25 filter, L+S | 7 | 14.3% | 0.05 | -0.59% | 4.1% | -0.56 | 5 |
| D pyramid (skill rules), L+S | 28 | 14.3% | 0.84 | -0.41% | 12.2% | -0.07 | 9 |
| E ADX>25 + pyramid, L+S | 7 | 0.0% | 0.00 | -0.76% | 5.0% | -0.72 | 7 |
| F ADX>25 + pyramid, long only | 4 | 0.0% | 0.00 | -0.41% | 3.7% | -0.68 | 4 |

In-sample 2009 to 2019 (buy-and-hold +72.2%):

| Variant | Trades | Win rate | Profit factor | CAGR | Max DD | Expectancy (R) | Max consecutive losses |
|---------|--------|----------|---------------|------|--------|----------------|------------------------|
| A baseline long+short | 52 | 46.2% | 1.41 | 0.62% | 5.1% | +0.15 | 5 |
| B long only | 26 | 53.8% | 2.72 | 0.99% | 3.2% | +0.43 | 2 |
| C ADX>25 filter, L+S | 8 | 50.0% | 0.97 | -0.01% | 2.4% | -0.01 | 2 |
| D pyramid (skill rules), L+S | 52 | 23.1% | 1.16 | 0.34% | 8.4% | +0.10 | 7 |
| E ADX>25 + pyramid, L+S | 8 | 25.0% | 0.48 | -0.19% | 5.0% | -0.25 | 4 |
| F ADX>25 + pyramid, long only | 3 | 33.3% | 1.30 | 0.02% | 3.7% | +0.10 | 2 |

読み:

1. **基準戦略 A はアウトオブサンプルで負け**（PF 0.78）。2020 年 10 月には 5 回連続でクロスに振り回された。
2. **ショートが一貫して損失源。** 2009 年以降のフルサンプルで、ロングの合計損益はプラス、ショートはマイナス。ゴールドの長期的な上方ドリフトの下で、EMA クロスの売りに優位性はなかった。
3. **クロス時点の ADX>25 フィルターはトレードをほぼ全滅させる**（11 年で 8 回）。クロスはトレンドの初期に起き、その時点で ADX はまだ低いのが普通。フィルターとしての構造が間違っている。
4. **スキルのピラミッディング規則（追加玉の SL = 直前エントリー − 0.5 ATR）は日足では悪化要因。** 勝率が 46% → 23% に半減。0.5 ATR は日足のノイズ幅より狭く、追加玉が刈られて勝ちトレードを負けに変える。この規則は H1 を想定して書かれている。

CAGR が小さいのは 1 トレードあたりリスク 1% で年 3〜5 回しか取引しないためで、期待値 0.15R × 5 回 × 1% ≈ 年 0.7% という算術どおり。比較は R 単位の期待値、PF、DD で行うこと。

## 事後的な改善案 G〜L / Post-hoc improvements

これらは IS の表とトレードログを見てから設計した。よって IS の数字は参考値であり、テストは OOS のみ。

Out-of-sample 2020 to 2026-09-11:

| Variant | Trades | Win rate | Profit factor | CAGR | Max DD | Expectancy (R) | Max consecutive losses | Sharpe |
|---------|--------|----------|---------------|------|--------|----------------|------------------------|--------|
| G long only, trail 4 ATR | 14 | 42.9% | 2.21 | 1.03% | 4.7% | +0.51 | 3 | 0.38 |
| H long only, pyramid with shared trail stop | 14 | 21.4% | 1.59 | 0.67% | 7.3% | +0.37 | 4 | 0.19 |
| I long only, ADX>20 | 6 | 50.0% | 1.56 | 0.15% | 2.4% | +0.18 | 2 | 0.11 |
| J G + re-entry rule | 32 | 40.6% | 2.95 | 3.31% | 6.9% | +0.71 | 5 | 0.80 |
| K J + pyramid with shared trail stop | 32 | 31.2% | 3.38 | 6.07% | 11.5% | +1.32 | 8 | 0.77 |
| L long+short, trail 4, re-entry | 52 | 38.5% | 1.96 | 2.84% | 7.9% | +0.38 | 6 | 0.60 |

In-sample 2009 to 2019 for the same variants (reference only):

| Variant | Trades | Win rate | Profit factor | CAGR | Max DD | Expectancy (R) | Max consecutive losses |
|---------|--------|----------|---------------|------|--------|----------------|------------------------|
| G | 26 | 42.3% | 2.92 | 1.71% | 5.3% | +0.75 | 5 |
| H | 26 | 30.8% | 1.82 | 0.91% | 6.3% | +0.42 | 5 |
| I | 9 | 33.3% | 0.64 | -0.10% | 2.6% | -0.11 | 3 |
| J | 48 | 35.4% | 1.69 | 1.42% | 10.3% | +0.35 | 6 |
| K | 48 | 29.2% | 1.62 | 2.07% | 19.7% | +0.54 | 10 |
| L | 93 | 28.0% | 1.12 | 0.50% | 12.7% | +0.08 | 7 |

Yearly returns, full period, for the three candidates worth keeping:

| Year | G | J | K |
|------|---|---|---|
| 2009 | 6.0 | 4.6 | 8.4 |
| 2010 | 3.3 | 4.2 | 5.1 |
| 2011 | 1.9 | 1.9 | 5.6 |
| 2012 | 1.6 | 0.5 | 0.3 |
| 2013 | -0.6 | -1.3 | -2.4 |
| 2014 | -1.0 | -2.0 | -3.0 |
| 2015 | -1.8 | -1.8 | -4.0 |
| 2016 | 5.1 | 4.9 | 7.3 |
| 2017 | -0.3 | 0.5 | -2.3 |
| 2018 | -1.4 | -0.6 | -3.0 |
| 2019 | 6.4 | 5.0 | 12.2 |
| 2020 | 1.9 | 1.4 | 1.9 |
| 2021 | -1.0 | -1.0 | -3.1 |
| 2022 | 1.4 | 0.7 | 2.1 |
| 2023 | 0.8 | -0.5 | -2.1 |
| 2024 | 0.0 | 8.3 | 18.5 |
| 2025 | 5.0 | 12.0 | 21.6 |
| 2026 | -0.6 | 2.4 | 4.1 |

## 改善案の順位 / Improvements ranked by evidence

1. **ロング専用にする（B → G）。** IS と OOS の両方で PF が改善し、連敗も短い。根拠は「ショートが両期間で負けている」という事実で、パラメータ探索ではない。最も信頼できる改善。
2. **損切り後の再エントリー規則（J）。** 基準戦略は 2023-11 の損切り後、次の（弱気）クロスまで再エントリーできず、2024 年の 2073 → 2640 の上昇をまるごと逃した。再エントリーで OOS の取引数が 14 → 32、PF 2.21 → 2.95、期待値 0.51R → 0.71R。ただし IS では PF が 2.92 → 1.69 に低下しており、レンジ期（2013〜2015）に損切りを増やす。トレンド期に効き、レンジ期に払うトレードオフ。
3. **トレーリング幅 3 → 4 ATR（G）。** IS のロバストネス・グリッドでは 12 組中 8 組で 4 ATR が最良。ただし EMA20/100 や 50/100 では逆で、普遍的ではない。
4. **ピラミッディングは「共有トレーリングストップ」方式でのみ有効（H, K）。** 追加玉に個別のタイトな SL を付ける D/E/F は全滅、追加玉がトレーリングストップだけを共有する H/K は PF を維持したまま平均利益を倍以上にした（K の OOS 平均勝ち 6,885 USD 対 J の 2,847 USD）。代償は DD 倍増（IS 19.7%）と最大連敗 10。
5. **ADX フィルターは不採用。** 20 でも 25 でも取引数が消え、優位性は出ない。使うならクロス時点ではなく、クロス後に ADX が上向いた時点で入る「遅延エントリー」として再設計が必要。

## 過学習リスクの評価 / Overfitting assessment

- G〜L は IS を見た後に作った。OOS で確認したとはいえ、OOS 期間（2020〜2026）はゴールドが +190% した歴史的な強気相場で、ロング専用戦略には最も有利な地合い。次の 5 年が 2013〜2015 型のレンジなら、J と K は年 -2〜-4% を複数年続ける（上の年次表を参照）。
- K の OOS 利益 48,292 USD のうち、2024〜2026 の 5 キャンペーン（各 7R 超）で約 44,000 USD。利益の 9 割が 5 トレードに集中する典型的なトレンドフォローの分布であり、その 5 回を逃せば戦略は負ける。
- ロバストネス・グリッド（`--grid`）では EMA20/50 は 12 組の中で中位。50/200 は PF 4 台だが 11 年で 11 回しか取引せず、統計的に何も言えない。
- 手数料は 0.25 USD/oz/片道。スプレッドの広い CFD 口座なら 2〜4 倍になり、取引数の多い J/L の期待値を 0.05〜0.1R 削る。

## EA 実装への含意 / Implications for the GOLD EA

- 日足ロジックをそのまま H1 に移すと ATR の意味が変わる。この結果は日足専用。
- スキルの `ExecutePyramid()` にある「追加玉 SL = 直前エントリー − 0.5 ATR」は、少なくとも日足では期待値を壊す。追加玉はトレーリングストップのみを共有する設計（H/K）に変えるか、0.5 を時間軸ごとに再検証すること。
- 「連続損失の構造的禁止」という運用原則に対して、K は最大 10 連敗、J は 6 連敗。トレンドフォローで連敗をなくすことはできない。できるのは 1R を小さくして連敗の総額を抑えることだけで、K を 1% リスクで運用した場合の IS 最大 DD は 19.7%。0.5% なら概ね半分になる。
- MT5 の Strategy Tester でこのルールを再現し、同じ期間の数字と突き合わせてから採用すること。ここでの数字は先物の日足終値ベースで、スプレッド、スワップ、ティック単位の約定は含まない。

## 制限事項 / Limitations

- GCUSD は先物の期近つなぎ。ロール時のギャップがそのまま損益に入っている。スポット XAUUSD とはベーシス分ずれる。
- 約定は翌日始値の 1 本値。ストップは日中の高値安値で判定し、ギャップは始値で約定。実際のスリッページは考慮外。
- スワップ、金利、ロールコストは未計上。ショート側は本来スワップ受け取り、ロング側は支払いが発生する。
- ロットは連続値。最小ロット・ステップの丸めは未実装。
- 1 サンプル（ゴールド 17 年）での検証であり、他の商品や他の期間への一般化はできない。
