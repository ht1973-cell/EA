#!/usr/bin/env python3
"""Prompt 4 example: backtest EMA crossover variants on GOLD daily bars.

Usage: python3 backtest_prompt04.py GCUSD_daily_2008-01-02_2026-09-11.csv [--grid]

Rules (fixed before running, not optimised):
  Signal      : EMA(fast) crosses EMA(slow) on the daily close.
  Execution   : next day's open. Long and short unless long_only.
  Initial stop: 2.0 x ATR(14) from entry (per unit).
  Trail stop  : highest high (long) / lowest low (short) since entry
                minus/plus trail_mult x ATR(14); ratchets only.
  Exit        : stop hit (gap -> filled at open), or opposite cross
                (close at next open, optionally reverse).
  Sizing      : risk_pct of current equity per initial unit, stop = 2 ATR.
  Pyramiding  : (optional) add a unit when close >= last entry + 1.5 ATR in
                favour and the position is in profit; unit lot ratios
                1.0/0.7/0.5/0.3; unit stop = last entry -/+ 0.5 ATR;
                total open risk capped at 3% of equity. Mirrors the
                CanPyramid()/ExecutePyramid() rules in the MQL5 EA skill.
  ADX filter  : (optional) new entries only when ADX(14) > adx_min.
  Re-entry    : (optional) after a stop-out, re-enter when the EMAs are still
                aligned and the close crosses back over the fast EMA.
  Costs       : cost_per_oz USD per side per unit (spread + slippage).
Metrics use campaigns (entry to flat) as trades. Equity is marked to
market daily at the close.
"""
import csv, datetime, json, math, sys, itertools

# ---------- indicators (same maths as compute_indicators.py) ----------
def ema(x, p):
    k = 2 / (p + 1); out = [None] * len(x); s = None
    for i, v in enumerate(x):
        s = v if s is None else v * k + s * (1 - k); out[i] = s
    return out

def true_range(h, l, c):
    return [h[0] - l[0]] + [max(h[i] - l[i], abs(h[i] - c[i - 1]), abs(l[i] - c[i - 1])) for i in range(1, len(c))]

def wilder(x, p):
    out = [None] * len(x); s = None
    for i in range(p, len(x)):
        s = sum(x[1:p + 1]) / p if s is None else (s * (p - 1) + x[i]) / p
        out[i] = s
    return out

def adx(h, l, c, p=14):
    pdm = [0.0]; ndm = [0.0]
    for i in range(1, len(c)):
        up = h[i] - h[i - 1]; dn = l[i - 1] - l[i]
        pdm.append(up if up > dn and up > 0 else 0.0)
        ndm.append(dn if dn > up and dn > 0 else 0.0)
    tr = true_range(h, l, c)
    st, sp, sn = wilder(tr, p), wilder(pdm, p), wilder(ndm, p)
    dx = [None] * len(c)
    for i in range(len(c)):
        if st[i] is None or st[i] == 0: continue
        pdi, ndi = 100 * sp[i] / st[i], 100 * sn[i] / st[i]
        dx[i] = 0 if pdi + ndi == 0 else 100 * abs(pdi - ndi) / (pdi + ndi)
    out = [None] * len(c); s = None; buf = []
    for i in range(len(c)):
        if dx[i] is None: continue
        if s is None:
            buf.append(dx[i])
            if len(buf) == p: s = sum(buf) / p; out[i] = s
        else:
            s = (s * (p - 1) + dx[i]) / p; out[i] = s
    return out

# ---------- engine ----------
def run(bars, fast=20, slow=50, trail_mult=3.0, init_stop_mult=2.0, risk_pct=1.0,
        long_only=False, adx_min=None, pyramid=False, max_adds=3, add_atr=1.5,
        add_stop_atr=0.5, lot_ratios=(1.0, 0.7, 0.5, 0.3), risk_cap_pct=3.0,
        cost_per_oz=0.25, start_equity=100_000.0, date_from=None, date_to=None, reentry=False):
    d = [b['date'] for b in bars]; o = [b['open'] for b in bars]; h = [b['high'] for b in bars]
    l = [b['low'] for b in bars]; c = [b['close'] for b in bars]
    n = len(c)
    ef, es = ema(c, fast), ema(c, slow)
    A = wilder(true_range(h, l, c), 14)
    X = adx(h, l, c, 14) if adx_min is not None else [999] * n
    warm = max(slow, 200)
    i0 = next(i for i in range(warm, n) if date_from is None or d[i] >= date_from)
    i1 = n - 1 if date_to is None else max(i for i in range(n) if d[i] <= date_to)

    equity = start_equity; cash = start_equity
    pos = None  # dict(dir, units:[{entry,size,stop}], last_entry, extreme, count, open_date, realised)
    trades = []; eq_curve = []; units_closed = 0
    pending = None  # ('enter', dir) or ('exit', reverse_dir|None) executed at next open

    def unit_pnl(u, px, dr): return (px - u['entry']) * u['size'] * dr
    def close_units(units, px, dr, date, reason, ctx):
        nonlocal cash, units_closed
        for u in units:
            pnl = unit_pnl(u, px, dr) - cost_per_oz * u['size']  # exit cost
            cash += pnl; ctx['realised'] += pnl; units_closed += 1
    def open_unit(px, size, stop, date, ctx):
        nonlocal cash
        cash -= cost_per_oz * size  # entry cost
        ctx['units'].append({'entry': px, 'size': size, 'stop': stop, 'date': date})
        ctx['last_entry'] = px; ctx['count'] += 1
    def flat(date, ctx, reason):
        trades.append({'dir': ctx['dir'], 'open': ctx['open_date'], 'close': date, 'pnl': ctx['realised'],
                       'units': ctx['count'], 'reason': reason, 'r': ctx['realised'] / ctx['risk0']})

    for i in range(i0, i1 + 1):
        atr = A[i - 1]
        # ---- execute pending order at today's open ----
        if pending is not None and atr:
            kind, arg = pending; pending = None
            if kind == 'exit' and pos is not None:
                close_units(pos['units'], o[i], pos['dir'], d[i], 'cross', pos); flat(d[i], pos, 'cross'); pos = None
                if arg is not None and not (long_only and arg < 0):
                    kind, arg = 'enter', arg
                else:
                    kind = None
            if kind == 'enter' and pos is None:
                dr = arg; stop_dist = init_stop_mult * atr
                size = equity * risk_pct / 100 / stop_dist
                ctx = {'dir': dr, 'units': [], 'last_entry': None, 'extreme': o[i], 'count': 0,
                       'open_date': d[i], 'realised': 0.0, 'risk0': size * stop_dist, 'base_size': size}
                open_unit(o[i], size, o[i] - dr * stop_dist, d[i], ctx); pos = ctx
            elif kind == 'add' and pos is not None:
                pos_dr = pos['dir']; idx = min(pos['count'], len(lot_ratios) - 1)
                size = pos['base_size'] * lot_ratios[idx]
                stop = (pos['last_entry'] - pos_dr * add_stop_atr * atr) if add_stop_atr is not None else (pos['extreme'] - pos_dr * trail_mult * atr)
                # total risk cap at current stops
                risk_now = sum(max(0.0, (u['entry'] - u['stop']) * pos_dr) * u['size'] for u in pos['units'])
                new_risk = max(0.0, (o[i] - stop) * pos_dr) * size
                if risk_now + new_risk <= equity * risk_cap_pct / 100:
                    open_unit(o[i], size, stop, d[i], pos)
        # ---- intraday stop check (gap-aware), stops are per unit ----
        if pos is not None:
            dr = pos['dir']; survivors = []; stopped = []
            for u in pos['units']:
                hit = (l[i] <= u['stop']) if dr > 0 else (h[i] >= u['stop'])
                if hit:
                    px = o[i] if (dr > 0 and o[i] < u['stop']) or (dr < 0 and o[i] > u['stop']) else u['stop']
                    stopped.append((u, px))
                else:
                    survivors.append(u)
            for u, px in stopped:
                close_units([u], px, dr, d[i], 'stop', pos)
            pos['units'] = survivors
            if not survivors:
                flat(d[i], pos, 'stop'); pos = None
        # ---- end of day: trail update, signals ----
        atr = A[i]
        if pos is not None and atr:
            dr = pos['dir']
            pos['extreme'] = max(pos['extreme'], h[i]) if dr > 0 else min(pos['extreme'], l[i])
            trail = pos['extreme'] - dr * trail_mult * atr
            for u in pos['units']:
                u['stop'] = max(u['stop'], trail) if dr > 0 else min(u['stop'], trail)
        # cross signal on close
        sig = 0
        if ef[i - 1] is not None and es[i - 1] is not None:
            if ef[i] > es[i] and ef[i - 1] <= es[i - 1]: sig = 1
            elif ef[i] < es[i] and ef[i - 1] >= es[i - 1]: sig = -1
        adx_ok = X[i] is not None and X[i] > (adx_min or -1)
        # re-entry after a stop-out: EMAs still aligned and close crosses back over the fast EMA
        if reentry and sig == 0 and pos is None and pending is None and ef[i - 1] is not None:
            if ef[i] > es[i] and c[i] > ef[i] and c[i - 1] <= ef[i - 1]: sig = 1
            elif ef[i] < es[i] and c[i] < ef[i] and c[i - 1] >= ef[i - 1]: sig = -1
        if sig != 0:
            if pos is not None and pos['dir'] != sig:
                pending = ('exit', sig if adx_ok else None)
            elif pos is None and adx_ok and not (long_only and sig < 0):
                pending = ('enter', sig)
        elif pyramid and pos is not None and atr and pos['count'] < 1 + max_adds:
            dr = pos['dir']; moved = (c[i] - pos['last_entry']) * dr >= add_atr * atr
            in_profit = sum(unit_pnl(u, c[i], dr) for u in pos['units']) > 0
            if moved and in_profit: pending = ('add', None)
        # mark to market
        open_pnl = sum(unit_pnl(u, c[i], pos['dir']) for u in pos['units']) if pos else 0.0
        equity = cash + open_pnl
        eq_curve.append((d[i], equity))
    if pos is not None:  # close at last bar for accounting
        close_units(pos['units'], c[i1], pos['dir'], d[i1], 'end', pos); flat(d[i1], pos, 'end'); pos = None
        equity = cash; eq_curve[-1] = (d[i1], equity)
    m = metrics(trades, eq_curve, start_equity, units_closed, c[i0 - 1], c[i1]); m['_trades'] = trades; return m

def metrics(trades, eq, e0, units_closed, p0, p1):
    if not trades:
        return {'trades': 0}
    pnl = [t['pnl'] for t in trades]; wins = [x for x in pnl if x > 0]; losses = [x for x in pnl if x <= 0]
    gp, gl = sum(wins), -sum(losses)
    peak = e0; mdd = 0.0; mdd_pct = 0.0
    for _, e in eq:
        peak = max(peak, e); mdd = max(mdd, peak - e); mdd_pct = max(mdd_pct, (peak - e) / peak)
    streak = cur = 0
    for x in pnl:
        cur = cur + 1 if x <= 0 else 0; streak = max(streak, cur)
    rets = [eq[i][1] / eq[i - 1][1] - 1 for i in range(1, len(eq)) if eq[i - 1][1] > 0]
    mu = sum(rets) / len(rets); sd = math.sqrt(sum((r - mu) ** 2 for r in rets) / max(1, len(rets) - 1))
    years = (datetime.date.fromisoformat(eq[-1][0]) - datetime.date.fromisoformat(eq[0][0])).days / 365.25
    e1 = eq[-1][1]
    return {
        'period': f"{eq[0][0]}..{eq[-1][0]}", 'years': round(years, 2),
        'trades': len(trades), 'units': units_closed,
        'win_rate': round(100 * len(wins) / len(trades), 1),
        'profit_factor': round(gp / gl, 2) if gl else None,
        'net_pnl': round(e1 - e0), 'return_pct': round(100 * (e1 / e0 - 1), 1),
        'cagr_pct': round(100 * ((e1 / e0) ** (1 / years) - 1), 2) if years > 0 and e1 > 0 else None,
        'max_dd_pct': round(100 * mdd_pct, 1), 'max_dd_usd': round(mdd),
        'avg_win': round(gp / len(wins)) if wins else 0, 'avg_loss': round(gl / len(losses)) if losses else 0,
        'expectancy_R': round(sum(t['r'] for t in trades) / len(trades), 3),
        'max_consec_losses': streak,
        'sharpe': round(mu / sd * math.sqrt(252), 2) if sd else None,
        'buy_hold_pct': round(100 * (p1 / p0 - 1), 1),
        'long_trades': sum(1 for t in trades if t['dir'] > 0), 'short_trades': sum(1 for t in trades if t['dir'] < 0),
        'long_pnl': round(sum(t['pnl'] for t in trades if t['dir'] > 0)), 'short_pnl': round(sum(t['pnl'] for t in trades if t['dir'] < 0)),
        'yearly': yearly(eq),
    }

def yearly(eq):
    out = {}; last = None; start = eq[0][1]
    for dte, e in eq:
        y = dte[:4]
        if last is not None and y != last:
            out[last] = round(100 * (prev / start - 1), 1); start = prev
        prev = e; last = y
    out[last] = round(100 * (prev / start - 1), 1)
    return out

VARIANTS = {
    'A_baseline_LS':      dict(),
    'B_long_only':        dict(long_only=True),
    'C_adx25_LS':         dict(adx_min=25),
    'D_pyramid_LS':       dict(pyramid=True),
    'E_adx25_pyramid_LS': dict(adx_min=25, pyramid=True),
    'F_adx25_pyramid_L':  dict(adx_min=25, pyramid=True, long_only=True),
    # --- post-hoc improvements (defined after reading the IS table above) ---
    'G_long_trail4':      dict(long_only=True, trail_mult=4.0),
    'H_long_pyr_trailstop': dict(long_only=True, pyramid=True, add_stop_atr=None),
    'I_long_adx20':       dict(long_only=True, adx_min=20),
    # --- defined after reading the trade log (2024 rally missed after a stop-out) ---
    'J_long_trail4_reentry': dict(long_only=True, trail_mult=4.0, reentry=True),
    'K_J_plus_pyr_trailstop': dict(long_only=True, trail_mult=4.0, reentry=True, pyramid=True, add_stop_atr=None),
    'L_LS_trail4_reentry':  dict(trail_mult=4.0, reentry=True),
}
SPLITS = {'IS_2009-2019': ('2009-01-01', '2019-12-31'), 'OOS_2020-2026': ('2020-01-01', '2026-09-11'),
          'FULL_2009-2026': ('2009-01-01', '2026-09-11')}

def main():
    path = sys.argv[1] if len(sys.argv) > 1 else 'GCUSD_daily_2008-01-02_2026-09-11.csv'
    bars = sorted(({k: (v if k == 'date' else float(v)) for k, v in r.items()} for r in csv.DictReader(open(path))), key=lambda r: r['date'])
    results = {}
    for vn, kw in VARIANTS.items():
        for sn, (f, t) in SPLITS.items():
            results[f"{vn}|{sn}"] = run(bars, date_from=f, date_to=t, **kw)
    keys = ['trades', 'win_rate', 'profit_factor', 'cagr_pct', 'max_dd_pct', 'expectancy_R', 'max_consec_losses', 'sharpe', 'buy_hold_pct']
    print(f"{'variant|split':34s}" + ''.join(f"{k:>18s}" for k in keys))
    for k, r in results.items():
        print(f"{k:34s}" + ''.join(f"{str(r.get(x)):>18s}" for x in keys))
    if '--grid' in sys.argv:  # robustness grid on IS only
        print("\nIS robustness grid (baseline long+short), CAGR% / MaxDD% / PF / trades")
        for fast, slow, tm in itertools.product((10, 20, 50), (30, 50, 100, 200), (2.0, 3.0, 4.0)):
            if fast >= slow: continue
            r = run(bars, fast=fast, slow=slow, trail_mult=tm, date_from='2009-01-01', date_to='2019-12-31')
            print(f"  EMA{fast}/{slow} trail{tm}: {r['cagr_pct']:>6} / {r['max_dd_pct']:>5} / {r['profit_factor']:>5} / {r['trades']}")
    if '--log' in sys.argv:
        for key in ('J_long_trail4_reentry|OOS_2020-2026', 'K_J_plus_pyr_trailstop|OOS_2020-2026'):
            print(f"\ntrade log {key}")
            for t in results[key]['_trades']:
                print(f"  {'L' if t['dir']>0 else 'S'} {t['open']}..{t['close']} units={t['units']} pnl={t['pnl']:>9.0f} R={t['r']:>6.2f} {t['reason']}")
    for r in results.values(): r.pop('_trades', None)
    json.dump(results, open('backtest_prompt04_results.json', 'w'), indent=1)

if __name__ == '__main__':
    main()
