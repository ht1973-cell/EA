# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

GOLD (XAUUSD) trading system for MetaTrader 5. Contains Expert Advisors, custom indicators, backtest infrastructure, and LLM trading prompt templates. Target broker: AXIORY (symbol suffix `_z`, e.g. `XAUUSD_z`).

## Architecture

### EA Strategies (experts/)

| EA | Strategy | Timeframe | Direction |
|----|----------|-----------|-----------|
| `GOLD_DPO_Tenzoko_Pyramid.mq5` | DPO + ZigZag/StdDev ratchet signals, pyramid entries | M20 (custom) | Long only |
| `GOLD_EMA_CrossoverJ.mq5` | EMA 20/50 crossover, Variant J (Fixed) / K (Martin) switchable | D1 | Long only |
| `GOLD_TrendFollow_Pyramid.mq5` | Multi-TF trend-following with 4 stop modes, pyramid | D1 | Both |
| `GOLD_NanpinMartin.mq5` | Counter-trend grid/basket (NM-S20 safe, NM-R50 risk) | H1 | Both |

### Indicators (indicators/)

- `DPO_Tenzoko_signal_v2.01.mq5` — Primary signal indicator for DPO Tenzoko EA. 8 buffers: DPO(0), MADPO(1), BB_Upper(2), BB_Mid(3), BB_Lower(4), **SwingBUY(5)**, **SwingSELL(6)**, StdDev(7-calc). Buffer 5/6 are the entry signals consumed by the EA via `iCustom()`.
- `DPO_Tenzoko_signal_1.02.mq5` — Earlier version.

### EA ↔ Indicator Relationship

The DPO Tenzoko EA loads `DPO_Tenzoko_signal_v2.01` via `iCustom()` with 21 parameters matching the indicator's input order exactly. Buffer indices for buy/sell signals are configurable EA inputs (`InpBuyBufferIdx=5`, `InpSellBufferIdx=6`). Parameter order mismatch = silent wrong data.

### Stop Loss Modes (TrendFollow / DPO EA)

`STOP_ATR` (ATR multiplier), `STOP_SWING` (swing high/low), `STOP_PERCENT` (% of price), `STOP_FIXED_PTS` (fixed points).

### Pyramid Modes

`PYRAMID_FIXED` (constant lot), `PYRAMID_MARTIN` (lot × multiplier^level). Pyramiding requires a **hedging** account; netting accounts fall back to single-position mode.

## MQL5 Compilation Requirements

**File encoding is critical.** MetaEditor requires:
- **UTF-8 with BOM** (first 3 bytes: `EF BB BF`)
- **CRLF line endings** (`\r\n`)

Without BOM, files with Japanese comments produce `"event handling function not found"` — the compiler silently fails to parse event handlers. Verify with: `file -bi <filename>` should show `charset=utf-8` and `file <filename>` should show `UTF-8 (with BOM) text, with CRLF line terminators`.

Python conversion snippet:
```python
content = open(path, 'r', encoding='utf-8-sig').read()
open(path, 'w', encoding='utf-8-sig', newline='\r\n').write(content)
```

## Backtest

### Quick Run (Windows)
```powershell
cd backtest
.\run_all_backtests.ps1           # 10 configs × 4 periods = 40 tests
.\run_all_backtests.ps1 -Model 1  # OHLC 1-min (faster)
```

### Periods
| ID | Range | Purpose |
|----|-------|---------|
| IS1 | 2008-01-01 ~ 2015-12-31 | In-Sample 1 |
| IS2 | 2016-01-01 ~ 2019-12-31 | In-Sample 2 |
| OOS | 2020-01-01 ~ 2026-09-11 | Out-of-Sample |
| Full | 2008-01-01 ~ 2026-09-11 | Full period |

### Parameter Presets (backtest/sets/)
10 `.set` files: VariantJ, VariantK, TF_FP_{ATR,Swing,Pct,Fixed}, TF_MP_{ATR,Swing}, NM_S20, NM_R50.

### Result Collection
`scripts/BacktestReportCollector.mq5` — Run after each backtest to append a CSV row to `MQL5/Files/backtest_results.csv`.

## Python Scripts

- `backtest_sei.py` — SEI (Structural Edge Index) backtest comparing ATR-free approaches
- `backtest_all_ea.py` — Batch backtest runner for all EA configurations

## Trading Prompts (prompts/trading/)

7 reusable LLM prompt templates for trade analysis: ideas generator, technical analyst, news converter, strategy backtester, portfolio risk manager, journal analyzer, trading plan. See `prompts/trading/README.md`.

## Broker-Specific Notes (AXIORY)

- Symbol suffix: `_z` (use `XAUUSD_z` in tester)
- Preferred timeframe for DPO EA: M20 (non-standard, must be available)
- Account type matters: hedging account required for pyramid functionality
- Spread/slippage for GOLD: deviation 30-50 points in OrderSend
