#!/usr/bin/env python3
"""SEI (Structural Edge Index) backtest: ATR-free trading on GOLD daily bars.

Compares ATR-based approach (Variant J/K) against SEI-based alternatives.
Uses same data format and metrics as backtest_prompt04.py for fair comparison.

Usage: python3 backtest_sei.py GCUSD_daily.csv
"""
import csv, datetime, json, math, sys

# ============================================================
# INDICATORS
# ============================================================

def ema(x, p):
    k = 2 / (p + 1); out = [None]*len(x); s = None
    for i, v in enumerate(x):
        s = v if s is None else v*k + s*(1-k); out[i] = s
    return out

def true_range(h, l, c):
    return [h[0]-l[0]] + [max(h[i]-l[i], abs(h[i]-c[i-1]), abs(l[i]-c[i-1])) for i in range(1, len(c))]

def wilder(x, p):
    out = [None]*len(x); s = None
    for i in range(p, len(x)):
        s = sum(x[1:p+1])/p if s is None else (s*(p-1)+x[i])/p
        out[i] = s
    return out

# --- SEI Components ---

def efficiency_ratio(close, period=20):
    """Price Efficiency Ratio: |net move| / sum(|step|). 0=noise, 1=straight line."""
    out = [None]*len(close)
    for i in range(period, len(close)):
        net = abs(close[i] - close[i-period])
        gross = sum(abs(close[j] - close[j-1]) for j in range(i-period+1, i+1))
        out[i] = net / gross if gross > 0 else 0
    return out

def asymmetric_volatility(high, low, close, period=20):
    """Ratio of up-day range to total range. >0.5 = bullish vol dominance."""
    out = [None]*len(close)
    for i in range(period, len(close)):
        up_r, dn_r = [], []
        for j in range(i-period+1, i+1):
            r = high[j] - low[j]
            if close[j] > close[j-1]:
                up_r.append(r)
            else:
                dn_r.append(r)
        avg_up = sum(up_r)/len(up_r) if up_r else 0
        avg_dn = sum(dn_r)/len(dn_r) if dn_r else 0
        denom = avg_up + avg_dn
        out[i] = avg_up / denom if denom > 0 else 0.5
    return out

def swing_progress(high, low, period=20):
    """How many consecutive bars have higher highs (long) / lower lows (short).
    Returns (bull_progress, bear_progress) each in [0,1]."""
    bull = [None]*len(high)
    bear = [None]*len(low)
    for i in range(1, len(high)):
        hh = 0
        for j in range(i, max(i-period, 0), -1):
            if j == 0: break
            if high[j] >= high[j-1]: hh += 1
            else: break
        bull[i] = min(hh / period, 1.0) if period > 0 else 0

        ll = 0
        for j in range(i, max(i-period, 0), -1):
            if j == 0: break
            if low[j] <= low[j-1]: ll += 1
            else: break
        bear[i] = min(ll / period, 1.0) if period > 0 else 0
    return bull, bear

def compute_sei(high, low, close, period=20):
    """Structural Edge Index: 0-100 composite score.
    >0 = bullish edge, <0 = bearish edge (returned as signed -100..+100)."""
    er = efficiency_ratio(close, period)
    av = asymmetric_volatility(high, low, close, period)
    sp_bull, sp_bear = swing_progress(high, low, period)

    sei = [None]*len(close)
    for i in range(period, len(close)):
        if er[i] is None or av[i] is None or sp_bull[i] is None:
            continue
        eff = er[i]
        asym = av[i]
        sw_bull = sp_bull[i]
        sw_bear = sp_bear[i]

        # Bull SEI
        bull_score = eff * 40 + (asym - 0.5) * 2 * 30 + sw_bull * 30
        # Bear SEI
        bear_score = eff * 40 + (0.5 - asym) * 2 * 30 + sw_bear * 30

        sei[i] = bull_score - bear_score
    return sei

# --- Swing-based stops ---

def find_swing_lows(low, lookback=20):
    """For each bar, find the lowest swing low in the last `lookback` bars."""
    out = [None]*len(low)
    for i in range(2, len(low)):
        best = None
        limit = max(1, i - lookback)
        for j in range(i-1, limit, -1):
            if j < 1 or j >= len(low)-1: continue
            if low[j] < low[j-1] and low[j] < low[j+1]:
                if best is None or low[j] < best:
                    best = low[j]
        if best is None:
            best = min(low[max(0,i-lookback):i])
        out[i] = best
    return out

def find_swing_highs(high, lookback=20):
    """For each bar, find the highest swing high in the last `lookback` bars."""
    out = [None]*len(high)
    for i in range(2, len(high)):
        best = None
        limit = max(1, i - lookback)
        for j in range(i-1, limit, -1):
            if j < 1 or j >= len(high)-1: continue
            if high[j] > high[j-1] and high[j] > high[j+1]:
                if best is None or high[j] > best:
                    best = high[j]
        if best is None:
            best = max(high[max(0,i-lookback):i])
        out[i] = best
    return out

def n_bar_trail(high, low, n=10, pct_buffer=0.015):
    """Trailing stop: N-bar high/low minus percentage buffer.
    Returns (long_trail, short_trail)."""
    long_t = [None]*len(high)
    short_t = [None]*len(low)
    for i in range(n, len(high)):
        hh = max(high[i-n:i+1])
        ll = min(low[i-n:i+1])
        long_t[i] = hh * (1 - pct_buffer)
        short_t[i] = ll * (1 + pct_buffer)
    return long_t, short_t

# ============================================================
# BACKTEST ENGINE
# ============================================================

def run(bars, fast=20, slow=50, long_only=True, risk_pct=1.0,
        cost_per_oz=0.25, start_equity=100_000.0,
        date_from=None, date_to=None, reentry=True,
        # --- mode selection ---
        mode='atr_baseline',
        # ATR params (baseline)
        init_stop_mult=2.0, trail_mult=4.0,
        # SEI params
        sei_period=20, sei_entry_thresh=30, sei_exit_thresh=-10,
        sei_pyramid_thresh=50,
        # Swing stop params
        swing_lookback=20, trail_n=10, trail_pct=0.015,
        # Percentage stop fallback
        pct_stop=0.025,
        # Pyramid
        pyramid=False, max_adds=3, add_move_pct=0.03,
        add_atr_mult=1.5, lot_ratios=(1.0, 0.7, 0.5, 0.3), risk_cap_pct=3.0,
        ):
    d = [b['date'] for b in bars]; o = [b['open'] for b in bars]
    h = [b['high'] for b in bars]; l = [b['low'] for b in bars]
    c = [b['close'] for b in bars]
    n = len(c)

    ef, es = ema(c, fast), ema(c, slow)
    ATR = wilder(true_range(h, l, c), 14)
    SEI = compute_sei(h, l, c, sei_period)
    sw_lows = find_swing_lows(l, swing_lookback)
    sw_highs = find_swing_highs(h, swing_lookback)
    lt, st = n_bar_trail(h, l, trail_n, trail_pct)

    warm = max(slow, sei_period, 200)
    i0 = next(i for i in range(warm, n) if date_from is None or d[i] >= date_from)
    i1 = n-1 if date_to is None else max(i for i in range(n) if d[i] <= date_to)

    equity = start_equity; cash = start_equity
    pos = None; trades = []; eq_curve = []; units_closed = 0
    pending = None

    use_sei = mode in ('sei_filter', 'sei_full', 'sei_adaptive')
    use_swing_stop = mode in ('sei_full', 'sei_adaptive', 'swing_only')
    use_sei_entry = mode in ('sei_full', 'sei_adaptive')

    def unit_pnl(u, px, dr): return (px - u['entry']) * u['size'] * dr
    def close_units(units, px, dr, date, reason, ctx):
        nonlocal cash, units_closed
        for u in units:
            pnl = unit_pnl(u, px, dr) - cost_per_oz * u['size']
            cash += pnl; ctx['realised'] += pnl; units_closed += 1
    def open_unit(px, size, stop, date, ctx):
        nonlocal cash
        cash -= cost_per_oz * size
        ctx['units'].append({'entry': px, 'size': size, 'stop': stop, 'date': date})
        ctx['last_entry'] = px; ctx['count'] += 1
    def flat(date, ctx, reason):
        trades.append({'dir': ctx['dir'], 'open': ctx['open_date'], 'close': date,
                       'pnl': ctx['realised'], 'units': ctx['count'], 'reason': reason,
                       'r': ctx['realised'] / ctx['risk0'] if ctx['risk0'] else 0})

    def calc_stop_distance(i, direction):
        """Calculate initial stop distance based on mode."""
        if use_swing_stop:
            if direction > 0 and sw_lows[i] is not None:
                dist = o[i] - sw_lows[i]
                min_dist = o[i] * pct_stop
                return max(dist + o[i]*0.002, min_dist)
            elif direction < 0 and sw_highs[i] is not None:
                dist = sw_highs[i] - o[i]
                min_dist = o[i] * pct_stop
                return max(dist + o[i]*0.002, min_dist)
        if ATR[i]:
            return init_stop_mult * ATR[i]
        return o[i] * pct_stop

    for i in range(i0, i1 + 1):
        atr = ATR[i-1]
        sei_val = SEI[i-1] if SEI[i-1] is not None else 0

        # ---- execute pending ----
        if pending is not None and (atr or use_swing_stop):
            kind, arg = pending; pending = None
            if kind == 'exit' and pos is not None:
                close_units(pos['units'], o[i], pos['dir'], d[i], 'cross', pos)
                flat(d[i], pos, 'cross'); pos = None
                if arg is not None and not (long_only and arg < 0):
                    kind, arg = 'enter', arg
                else:
                    kind = None
            if kind == 'enter' and pos is None:
                dr = arg; stop_dist = calc_stop_distance(i, dr)
                size = equity * risk_pct / 100 / stop_dist if stop_dist > 0 else 0
                if size > 0:
                    ctx = {'dir': dr, 'units': [], 'last_entry': None,
                           'extreme': o[i], 'count': 0, 'open_date': d[i],
                           'realised': 0.0, 'risk0': size * stop_dist, 'base_size': size}
                    open_unit(o[i], size, o[i] - dr * stop_dist, d[i], ctx)
                    pos = ctx
            elif kind == 'add' and pos is not None:
                dr = pos['dir']
                idx = min(pos['count'], len(lot_ratios)-1)
                size = pos['base_size'] * lot_ratios[idx]
                if use_swing_stop:
                    if dr > 0 and lt[i] is not None:
                        stop = lt[i]
                    elif dr < 0 and st[i] is not None:
                        stop = st[i]
                    else:
                        stop = pos['extreme'] - dr * trail_mult * atr if atr else o[i] - dr * o[i] * pct_stop
                else:
                    stop = pos['extreme'] - dr * trail_mult * atr if atr else o[i] - dr * o[i] * pct_stop
                risk_now = sum(max(0, (u['entry']-u['stop'])*dr)*u['size'] for u in pos['units'])
                new_risk = max(0, (o[i]-stop)*dr)*size
                if risk_now + new_risk <= equity * risk_cap_pct / 100:
                    open_unit(o[i], size, stop, d[i], pos)

        # ---- stop check ----
        if pos is not None:
            dr = pos['dir']; survivors = []; stopped = []
            for u in pos['units']:
                hit = (l[i] <= u['stop']) if dr > 0 else (h[i] >= u['stop'])
                if hit:
                    px = o[i] if (dr>0 and o[i]<u['stop']) or (dr<0 and o[i]>u['stop']) else u['stop']
                    stopped.append((u, px))
                else:
                    survivors.append(u)
            for u, px in stopped:
                close_units([u], px, dr, d[i], 'stop', pos)
            pos['units'] = survivors
            if not survivors:
                flat(d[i], pos, 'stop'); pos = None

        # ---- trail update ----
        sei_now = SEI[i] if SEI[i] is not None else 0
        if pos is not None:
            dr = pos['dir']
            pos['extreme'] = max(pos['extreme'], h[i]) if dr > 0 else min(pos['extreme'], l[i])

            if use_swing_stop:
                if dr > 0 and lt[i] is not None:
                    trail = lt[i]
                elif dr < 0 and st[i] is not None:
                    trail = st[i]
                else:
                    trail = None
            else:
                if ATR[i]:
                    trail = pos['extreme'] - dr * trail_mult * ATR[i]
                else:
                    trail = None

            if trail is not None:
                for u in pos['units']:
                    if dr > 0:
                        u['stop'] = max(u['stop'], trail)
                    else:
                        u['stop'] = min(u['stop'], trail)

            # SEI-based exit: if SEI drops below threshold while in position
            if use_sei_entry and sei_now is not None:
                if dr > 0 and sei_now < sei_exit_thresh:
                    close_units(pos['units'], c[i], dr, d[i], 'sei_exit', pos)
                    flat(d[i], pos, 'sei_exit'); pos = None
                elif dr < 0 and sei_now > -sei_exit_thresh:
                    close_units(pos['units'], c[i], dr, d[i], 'sei_exit', pos)
                    flat(d[i], pos, 'sei_exit'); pos = None

        # ---- signals ----
        sig = 0
        if ef[i-1] is not None and es[i-1] is not None:
            if ef[i] > es[i] and ef[i-1] <= es[i-1]: sig = 1
            elif ef[i] < es[i] and ef[i-1] >= es[i-1]: sig = -1

        # re-entry
        if reentry and sig == 0 and pos is None and pending is None and ef[i-1] is not None:
            if ef[i] > es[i] and c[i] > ef[i] and c[i-1] <= ef[i-1]: sig = 1
            elif ef[i] < es[i] and c[i] < ef[i] and c[i-1] >= ef[i-1]: sig = -1

        # SEI filter: block entry if SEI doesn't confirm
        if use_sei and sig != 0 and sei_now is not None:
            if sig > 0 and sei_now < sei_entry_thresh: sig = 0
            if sig < 0 and sei_now > -sei_entry_thresh: sig = 0

        # SEI-only entry (no EMA cross needed)
        if use_sei_entry and sig == 0 and pos is None and pending is None:
            if sei_now is not None:
                if sei_now > sei_entry_thresh and ef[i] is not None and es[i] is not None:
                    if ef[i] > es[i]:  # still require EMA alignment
                        sig = 1
                elif sei_now < -sei_entry_thresh and ef[i] is not None and es[i] is not None:
                    if ef[i] < es[i]:
                        sig = -1

        if sig != 0:
            if pos is not None and pos['dir'] != sig:
                pending = ('exit', sig if not (long_only and sig < 0) else None)
            elif pos is None and not (long_only and sig < 0):
                pending = ('enter', sig)

        # pyramid check
        elif pyramid and pos is not None and pos['count'] < 1 + max_adds:
            dr = pos['dir']
            if use_swing_stop:
                moved = (c[i] - pos['last_entry']) * dr >= pos['last_entry'] * add_move_pct
            else:
                moved = atr and (c[i] - pos['last_entry']) * dr >= add_atr_mult * atr
            in_profit = sum(unit_pnl(u, c[i], dr) for u in pos['units']) > 0

            sei_ok = True
            if use_sei and sei_now is not None:
                sei_ok = (dr > 0 and sei_now > sei_pyramid_thresh) or \
                         (dr < 0 and sei_now < -sei_pyramid_thresh)

            if moved and in_profit and sei_ok:
                pending = ('add', None)

        # mark to market
        open_pnl = sum(unit_pnl(u, c[i], pos['dir']) for u in pos['units']) if pos else 0
        equity = cash + open_pnl
        eq_curve.append((d[i], equity))

    if pos is not None:
        close_units(pos['units'], c[i1], pos['dir'], d[i1], 'end', pos)
        flat(d[i1], pos, 'end'); pos = None
        equity = cash; eq_curve[-1] = (d[i1], equity)

    m = metrics(trades, eq_curve, start_equity, units_closed, c[i0-1], c[i1])
    m['_trades'] = trades
    return m

def metrics(trades, eq, e0, units_closed, p0, p1):
    if not trades:
        return {'trades': 0}
    pnl = [t['pnl'] for t in trades]; wins = [x for x in pnl if x > 0]; losses = [x for x in pnl if x <= 0]
    gp, gl = sum(wins), -sum(losses)
    peak = e0; mdd = 0; mdd_pct = 0
    for _, e in eq:
        peak = max(peak, e); mdd = max(mdd, peak-e); mdd_pct = max(mdd_pct, (peak-e)/peak)
    streak = cur = 0
    for x in pnl:
        cur = cur+1 if x <= 0 else 0; streak = max(streak, cur)
    rets = [eq[i][1]/eq[i-1][1]-1 for i in range(1, len(eq)) if eq[i-1][1] > 0]
    mu = sum(rets)/len(rets); sd = math.sqrt(sum((r-mu)**2 for r in rets)/max(1, len(rets)-1))
    years = (datetime.date.fromisoformat(eq[-1][0]) - datetime.date.fromisoformat(eq[0][0])).days / 365.25
    e1 = eq[-1][1]
    # exit reason breakdown
    reasons = {}
    for t in trades:
        reasons[t['reason']] = reasons.get(t['reason'], 0) + 1
    # yearly returns
    yearly = {}; last = None; start = eq[0][1]
    for dte, e in eq:
        y = dte[:4]
        if last is not None and y != last:
            yearly[last] = round(100*(prev/start - 1), 1); start = prev
        prev = e; last = y
    yearly[last] = round(100*(prev/start - 1), 1)
    return {
        'period': f"{eq[0][0]}..{eq[-1][0]}", 'years': round(years, 2),
        'trades': len(trades), 'units': units_closed,
        'win_rate': round(100*len(wins)/len(trades), 1),
        'profit_factor': round(gp/gl, 2) if gl else None,
        'net_pnl': round(e1-e0), 'return_pct': round(100*(e1/e0-1), 1),
        'cagr_pct': round(100*((e1/e0)**(1/years)-1), 2) if years > 0 and e1 > 0 else None,
        'max_dd_pct': round(100*mdd_pct, 1), 'max_dd_usd': round(mdd),
        'avg_win': round(gp/len(wins)) if wins else 0,
        'avg_loss': round(gl/len(losses)) if losses else 0,
        'expectancy_R': round(sum(t['r'] for t in trades)/len(trades), 3),
        'max_consec_losses': streak,
        'sharpe': round(mu/sd*math.sqrt(252), 2) if sd else None,
        'buy_hold_pct': round(100*(p1/p0-1), 1),
        'exit_reasons': reasons,
        'yearly': yearly,
    }

# ============================================================
# VARIANTS
# ============================================================

VARIANTS = {
    # --- ATR baselines (reproduce J and K) ---
    'J_ATR_baseline': dict(
        mode='atr_baseline', long_only=True, trail_mult=4.0, reentry=True,
    ),
    'K_ATR_pyramid': dict(
        mode='atr_baseline', long_only=True, trail_mult=4.0, reentry=True,
        pyramid=True,
    ),

    # --- SEI as filter on EMA cross (still ATR stops) ---
    'S1_SEI_filter_ATR_stop': dict(
        mode='sei_filter', long_only=True, trail_mult=4.0, reentry=True,
        sei_entry_thresh=20,
    ),
    'S2_SEI_filter_strict': dict(
        mode='sei_filter', long_only=True, trail_mult=4.0, reentry=True,
        sei_entry_thresh=40,
    ),

    # --- Swing stops (no ATR in stops) ---
    'S3_swing_stop_only': dict(
        mode='swing_only', long_only=True, reentry=True,
        swing_lookback=20, trail_n=10, trail_pct=0.015,
    ),
    'S4_swing_stop_tight': dict(
        mode='swing_only', long_only=True, reentry=True,
        swing_lookback=15, trail_n=8, trail_pct=0.012,
    ),
    'S5_swing_stop_wide': dict(
        mode='swing_only', long_only=True, reentry=True,
        swing_lookback=30, trail_n=15, trail_pct=0.020,
    ),

    # --- Full SEI (SEI entry + swing stops) ---
    'S6_SEI_full': dict(
        mode='sei_full', long_only=True, reentry=True,
        sei_entry_thresh=30, sei_exit_thresh=-10,
        swing_lookback=20, trail_n=10, trail_pct=0.015,
    ),
    'S7_SEI_full_strict': dict(
        mode='sei_full', long_only=True, reentry=True,
        sei_entry_thresh=50, sei_exit_thresh=0,
        swing_lookback=20, trail_n=10, trail_pct=0.015,
    ),

    # --- Full SEI + pyramid ---
    'S8_SEI_full_pyramid': dict(
        mode='sei_full', long_only=True, reentry=True,
        sei_entry_thresh=30, sei_exit_thresh=-10, sei_pyramid_thresh=50,
        swing_lookback=20, trail_n=10, trail_pct=0.015,
        pyramid=True, add_move_pct=0.03,
    ),

    # --- Percentage trail variants ---
    'S9_pct_trail_1pct': dict(
        mode='swing_only', long_only=True, reentry=True,
        swing_lookback=20, trail_n=10, trail_pct=0.010,
    ),
    'S10_pct_trail_2pct': dict(
        mode='swing_only', long_only=True, reentry=True,
        swing_lookback=20, trail_n=10, trail_pct=0.020,
    ),
}

SPLITS = {
    'IS_2009-2019': ('2009-01-01', '2019-12-31'),
    'OOS_2020-2026': ('2020-01-01', '2026-09-11'),
    'FULL_2009-2026': ('2009-01-01', '2026-09-11'),
}

def main():
    path = sys.argv[1] if len(sys.argv) > 1 else 'GCUSD_daily.csv'
    bars = sorted(({k: (v if k == 'date' else float(v)) for k, v in r.items()}
                   for r in csv.DictReader(open(path))), key=lambda r: r['date'])
    print(f"Loaded {len(bars)} bars: {bars[0]['date']} to {bars[-1]['date']}\n")

    results = {}
    for vn, kw in VARIANTS.items():
        for sn, (f, t) in SPLITS.items():
            key = f"{vn}|{sn}"
            results[key] = run(bars, date_from=f, date_to=t, **kw)
            print(f"  {key}: done", file=sys.stderr)

    # --- Print comparison table ---
    keys = ['trades', 'win_rate', 'profit_factor', 'cagr_pct', 'max_dd_pct',
            'expectancy_R', 'max_consec_losses', 'sharpe']
    header = f"{'variant|split':40s}" + ''.join(f"{k:>18s}" for k in keys)
    print(header)
    print("=" * len(header))

    for vn in VARIANTS:
        for sn in SPLITS:
            k = f"{vn}|{sn}"
            r = results[k]
            line = f"{k:40s}" + ''.join(f"{str(r.get(x)):>18s}" for x in keys)
            print(line)
        print()

    # --- OOS ranking ---
    print("\n" + "=" * 80)
    print("OOS 2020-2026 RANKING (by Profit Factor)")
    print("=" * 80)
    oos = [(vn, results[f"{vn}|OOS_2020-2026"]) for vn in VARIANTS
           if results[f"{vn}|OOS_2020-2026"].get('trades', 0) > 0]
    oos.sort(key=lambda x: x[1].get('profit_factor', 0) or 0, reverse=True)
    print(f"{'#':>3s}  {'Variant':30s}  {'PF':>6s}  {'CAGR%':>7s}  {'MaxDD%':>7s}  {'ExpR':>7s}  "
          f"{'Sharpe':>7s}  {'Trades':>7s}  {'WinR%':>7s}  {'ConsL':>6s}")
    for rank, (vn, r) in enumerate(oos, 1):
        print(f"{rank:3d}  {vn:30s}  {r.get('profit_factor',''):>6}  "
              f"{r.get('cagr_pct',''):>7}  {r.get('max_dd_pct',''):>7}  "
              f"{r.get('expectancy_R',''):>7}  {r.get('sharpe',''):>7}  "
              f"{r.get('trades',''):>7}  {r.get('win_rate',''):>7}  "
              f"{r.get('max_consec_losses',''):>6}")

    # --- Exit reason analysis ---
    print("\n" + "=" * 80)
    print("EXIT REASON BREAKDOWN (OOS)")
    print("=" * 80)
    for vn in VARIANTS:
        r = results[f"{vn}|OOS_2020-2026"]
        reasons = r.get('exit_reasons', {})
        if reasons:
            print(f"  {vn:30s}: {reasons}")

    # --- Yearly returns for top variants ---
    print("\n" + "=" * 80)
    print("YEARLY RETURNS (FULL period) — Top 5 OOS")
    print("=" * 80)
    for vn, _ in oos[:5]:
        r = results[f"{vn}|FULL_2009-2026"]
        yr = r.get('yearly', {})
        print(f"\n  {vn}:")
        for y in sorted(yr.keys()):
            bar = "+" * max(0, int(yr[y] / 2)) if yr[y] > 0 else "-" * max(0, int(-yr[y] / 2))
            print(f"    {y}: {yr[y]:>7.1f}%  {bar}")

    # --- Overfitting check ---
    print("\n" + "=" * 80)
    print("OVERFITTING CHECK: IS vs OOS degradation")
    print("=" * 80)
    print(f"{'Variant':30s}  {'IS_PF':>7s}  {'OOS_PF':>7s}  {'Ratio':>7s}  {'IS_CAGR':>8s}  {'OOS_CAGR':>9s}")
    for vn in VARIANTS:
        is_r = results[f"{vn}|IS_2009-2019"]
        oos_r = results[f"{vn}|OOS_2020-2026"]
        is_pf = is_r.get('profit_factor', 0) or 0
        oos_pf = oos_r.get('profit_factor', 0) or 0
        ratio = oos_pf / is_pf if is_pf > 0 else 0
        print(f"  {vn:28s}  {is_pf:>7.2f}  {oos_pf:>7.2f}  {ratio:>7.2f}  "
              f"{is_r.get('cagr_pct',''):>8}  {oos_r.get('cagr_pct',''):>9}")

    # save
    for r in results.values(): r.pop('_trades', None)
    json.dump(results, open('backtest_sei_results.json', 'w'), indent=1)
    print(f"\nResults saved to backtest_sei_results.json")

if __name__ == '__main__':
    main()
