# Example: Prompt 2 (Automated Technical Analyst) on GOLD / XAUUSD

実行日 / Run date: 2026-09-12 (data through the 2026-09-11 daily close)
対象 / Instrument: Gold futures front month, symbol `GCUSD` (proxy for XAUUSD)

## 検証レベル / Verification level

| Item | Level | Source |
|------|-------|--------|
| OHLCV, daily, 2024-09-02 to 2026-09-11 (564 bars) | VERIFIED | FMP commodities EOD, saved as `GCUSD_daily_2024-09-02_2026-09-11.csv` |
| All indicator values below | REPRODUCED | `compute_indicators.py` on that CSV, standard library only |
| Economic calendar (CPI, PPI, FOMC) | VERIFIED | TipRanks economic calendar, US high-impact |
| News flow | UNAVAILABLE | FMP news needs a paid plan; TipRanks had no gold-tagged stories in the window |
| Signal and levels | INFERRED | Reasoning from the numbers above, not a tested rule |

Anyone can rerun the numbers:

```bash
python3 compute_indicators.py GCUSD_daily_2024-09-02_2026-09-11.csv
```

## Prompt as filled in

```
Analyze GOLD (XAUUSD, proxy GCUSD) using daily and weekly charts. Break down support/resistance levels, trend lines, moving averages, and momentum indicators. Provide a step-by-step trading signal (Buy/Hold/Sell) with justification.
```

## 1. 週足構造 / Weekly structure

| Metric | Value |
|--------|-------|
| Last weekly bar (week of 2026-09-07) | O 4466.5 / H 4488.8 / L 4333.0 / C 4408.9 |
| SMA20 / SMA50 (weekly) | 4366.8 (falling, -265 over 10 weeks) / 4471.9 (rising) |
| EMA20 / EMA50 (weekly) | 4406.7 / 4288.3 |
| RSI14 | 50.1 |
| MACD / signal / histogram | -9.6 / -34.2 / +24.6 (histogram shrinking from +28.9) |
| ADX14 / +DI / -DI | 21.3 / 21.0 / 19.0 |
| ATR14 | 252 (5.7% of price) |

Swing points (weekly): highs 5626.8 (Jan 26) → 5434.1 (Mar 2) → 4917.7 (Apr 13) → 4783.4 (May 11) → 4755.0 (Aug 24). Lows 4100.0 (Mar 23) → 3955.4 (Jun 29).

読み: 2026年1月の 5626.8 から 6月の 3955.4 まで約 30% の調整。以後は高値を切り下げ続けており（5626 → 5434 → 4917 → 4783 → 4755）、週足は依然として「大きな上昇トレンド内の調整局面」。6月安値からの戻りで MACD は改善したが、ヒストグラムは縮小に転じ、戻りの勢いは鈍化。価格は週足 SMA50 の下、SMA20 の上に挟まれ、RSI は 50 ちょうど。週足単体では中立。

Key weekly levels: resistance 4755 to 4783 (two failed weekly highs), then 4917. Support 4329 to 4381 (recent daily lows), then 4100, then 3955.

## 2. 日足構造 / Daily structure

| Metric | Value |
|--------|-------|
| Last daily bar (2026-09-11) | O 4359.4 / H 4444.9 / L 4333.0 / C 4408.9 |
| SMA20 / SMA50 / SMA200 | 4517.5 (price below) / 4305.6 (price above, rising +67 over 10 bars) / 4595.8 (price below, flat) |
| EMA20 / EMA50 | 4453.9 (above price) / 4386.7 (below price) |
| Close vs SMA200 / SMA50 | -4.1% / +2.4% |
| RSI14 | 48.0 (was 75.3 at the Aug 24 close of 4697.8) |
| MACD / signal / histogram | 19.8 / 49.4 / -29.7 (histogram flat: -33.1, -30.0, -30.6, -29.7) |
| ADX14 / +DI / -DI | 19.9 / 20.2 / 19.8 |
| ATR14 | 108.5 (2.46% of price) |

Swing points (daily): lows 3993.8 (Jul 29) → 4074.0 (Aug 3) → 4365.5 (Aug 14) → 4378.0 (Aug 19) → 4329.2 (Sep 2) → 4381.0 (Sep 7). Highs 4509.1 (Aug 13) → 4755.0 (Aug 25) → 4558.5 (Sep 3).

読み: 6月30日安値 3955 から 8月25日高値 4755 までは高値・安値とも切り上げの明確な上昇。8月28日の大陰線（4664 → 4530）でその急角度のトレンドラインを下抜け、以降は 4329 から 4560 のレンジ。9月2日安値 4329 を 9月7日安値 4381 が割り込まなかった点は買い方に有利だが、9月3日高値 4558 は 4755 に対する明確な安値切り下げ。+DI と -DI がほぼ同値で ADX 20 未満、日足はトレンドレス。

Trend lines:
- Steep August line (Jul 29 low 3993.8 through Aug 14 low 4365.5, about +31 per day): broken on Aug 28, now far above price. No longer relevant as support.
- Shallow line from the Jun 30 low 3955.4 through the Jul 29 low 3993.8 (about +1.8 per day): projects to roughly 4085 today. Still intact, and it sits just below the 4100 weekly support.

Moving-average stack: price is above SMA50 and EMA50 but below EMA20, SMA20 and SMA200. That is the signature of a pullback inside a medium-term recovery that has not yet reclaimed the long-term average.

## 3. モメンタム / Momentum

- Daily RSI fell from 75 to 48 while price fell from 4698 to 4409. No bullish divergence yet: the Sep 7 higher low in price came with RSI around 47 to 52, so momentum is neutral, not stretched.
- Daily MACD is still positive but below its signal line, histogram negative and flat for four sessions. Downward momentum has stopped accelerating but has not turned.
- Weekly MACD histogram is positive but shrinking. The weekly bounce is losing thrust.
- ADX under 20 on the daily and about 21 on the weekly: no tradable trend on either timeframe right now.

## 4. 週足と日足の整合 / Alignment check

| Timeframe | Direction | Evidence |
|-----------|-----------|----------|
| Weekly | Corrective, lower highs since January | 5 successive lower swing highs, price below weekly SMA50 |
| Daily | Range 4329 to 4560 after a failed rally | Lower high 4558 vs 4755, higher low 4381 vs 4329, ADX 20 |

The two timeframes do not agree on direction. Per the usage note in Prompt 2, a mismatch defaults to Hold.

## 5. ファンダメンタル背景 / Event context

From the TipRanks US high-impact calendar:

| Date (UTC) | Event | Actual / Estimate / Prev |
|------------|-------|--------------------------|
| 2026-09-10 | PPI MoM | 0.3 / 0.4 / 0.0 |
| 2026-09-11 | CPI MoM / YoY | 0.3 / 0.4 / 0.1 and 3.4 / 3.4 / 3.4 |
| 2026-09-11 | Core CPI MoM / YoY | 0.3 / 0.2 / 0.2 and 2.4 / 2.4 / 2.5 |
| 2026-09-11 | Michigan Sentiment | 47.8 / 51.0 / 51.7 |
| 2026-09-16 | Fed rate decision | estimate 4.00 vs prev 3.75 |
| 2026-09-16 | FOMC projections and press conference | |

The calendar shows the consensus estimate for the Sep 16 decision above the previous rate. If that estimate is right, the market is pricing a hike, which is a headwind for gold. Headline CPI was softer than the estimate and sentiment fell sharply, which cuts the other way. Either way, Sep 16 is a binary event for this instrument and sits inside the window of any trade opened now.

## 6. シグナル / Signal

**HOLD.** No new position on either side at 4409.

Justification, step by step:

1. Weekly is corrective (lower highs), daily is a range. Direction is not confirmed on either timeframe.
2. ADX below 20 on the daily. There is no trend to follow, and trend-following entries (including pyramiding) have no statistical basis here.
3. Price is pinned between the daily EMA50 (4387) below and the EMA20 (4454) above, a 67-point band on an instrument moving 108 points a day. Noise dominates.
4. A rate decision with a hike in the consensus lands in four sessions. Position risk over that event is not compensated by the current setup.
5. Reward-to-risk on the obvious breakout trade is poor: long above 4560 with a stop under 4370 risks about 190 points for a first target at 4755, roughly 1:1. Only the second target at 4917 gets above 1.8:1.

Levels that change the signal:

| Trigger | New signal | First target | Second target | Invalidation |
|---------|-----------|--------------|---------------|--------------|
| Daily close above 4560 with RSI above 55 and ADX turning up | Buy | 4755 | 4917 | Daily close below 4381 |
| Daily close below 4329 | Sell | 4180 | 4100, then 3955 | Daily close back above 4454 (EMA20) |
| Daily close above 4783 (weekly lower-high line broken) | Weekly trend resumes up | 5000 | 5434 | Close below 4560 |

For an existing long taken from the August rally: hold with the stop just under 4329. A close below that level ends the higher-low sequence that the recovery rests on.

For the GOLD EA context: the session filter and pyramiding logic should stay dormant until daily ADX crosses back above 25 with +DI over -DI. Adding to positions inside a sub-20 ADX range is where consecutive losses come from.

## 7. 制限事項 / Limitations

- GCUSD is the futures front month, not spot XAUUSD. Levels can differ by the futures basis (a few dollars to a few tens of dollars).
- Volume in the data is exchange-reported futures volume and was not used for the signal.
- The signal is a reading, not a backtested rule. Nothing in this file has a measured win rate.
- No news flow was available through the connected tools in this session, so positioning and sentiment were not assessed.
