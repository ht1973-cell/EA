#!/usr/bin/env python3
"""Comprehensive backtest for all EA strategies on GOLD daily bars.

Covers 6 modes:
  1. Variant-J   : EMA cross, long only, ATR trail (baseline from CrossoverJ)
  2. Variant-K   : Variant J + pyramid
  3. TF-FP       : TrendFollow Fixed-lot Pyramid (4 stop modes)
  4. TF-MP       : TrendFollow Martin Pyramid
  5. NM-S20      : NanpinMartin Safe (DD≤20%)
  6. NM-R50      : NanpinMartin Risk (DD≤50%)

Usage: python3 backtest_all_ea.py GCUSD_daily.csv
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

def rsi(close, period=14):
    out = [None]*len(close)
    if len(close) < period + 1:
        return out
    gains = [0.0]*len(close)
    losses = [0.0]*len(close)
    for i in range(1, len(close)):
        d = close[i] - close[i-1]
        gains[i] = d if d > 0 else 0
        losses[i] = -d if d < 0 else 0
    avg_gain = sum(gains[1:period+1]) / period
    avg_loss = sum(losses[1:period+1]) / period
    for i in range(period, len(close)):
        if i > period:
            avg_gain = (avg_gain * (period-1) + gains[i]) / period
            avg_loss = (avg_loss * (period-1) + losses[i]) / period
        if avg_loss == 0:
            out[i] = 100.0
        else:
            rs = avg_gain / avg_loss
            out[i] = 100.0 - 100.0 / (1 + rs)
    return out

def bollinger(close, period=20, dev=2.0):
    upper = [None]*len(close)
    lower = [None]*len(close)
    middle = [None]*len(close)
    for i in range(period-1, len(close)):
        window = close[i-period+1:i+1]
        mu = sum(window) / period
        sd = math.sqrt(sum((x-mu)**2 for x in window) / period)
        middle[i] = mu
        upper[i] = mu + dev * sd
        lower[i] = mu - dev * sd
    return upper, middle, lower

def find_swing_low(low_arr, idx, lookback=10):
    start = max(0, idx - lookback)
    return min(low_arr[start:idx]) if idx > start else low_arr[idx]

def find_swing_high(high_arr, idx, lookback=10):
    start = max(0, idx - lookback)
    return max(high_arr[start:idx]) if idx > start else high_arr[idx]

# ============================================================
# METRICS
# ============================================================

def compute_metrics(trades, eq_curve, start_equity, label):
    if not trades:
        return {'label': label, 'trades': 0, 'net_pnl': 0, 'pf': 0,
                'win_rate': 0, 'max_dd_pct': 0, 'cagr': 0, 'sharpe': 0,
                'avg_r': 0, 'max_consec_loss': 0}

    pnl = [t['pnl'] for t in trades]
    wins = [x for x in pnl if x > 0]
    losses = [x for x in pnl if x <= 0]
    gp = sum(wins)
    gl = -sum(losses) if losses else 0.001

    peak = start_equity; mdd = 0; mdd_pct = 0
    for _, e in eq_curve:
        peak = max(peak, e)
        dd = peak - e
        mdd = max(mdd, dd)
        if peak > 0:
            mdd_pct = max(mdd_pct, dd / peak)

    streak = cur = 0
    for x in pnl:
        cur = cur + 1 if x <= 0 else 0
        streak = max(streak, cur)

    rets = []
    for i in range(1, len(eq_curve)):
        if eq_curve[i-1][1] > 0:
            rets.append(eq_curve[i][1] / eq_curve[i-1][1] - 1)

    if rets:
        mu = sum(rets) / len(rets)
        sd = math.sqrt(sum((r - mu)**2 for r in rets) / max(1, len(rets) - 1))
        sharpe = mu / sd * math.sqrt(252) if sd > 0 else 0
    else:
        sharpe = 0

    if len(eq_curve) >= 2:
        days = (datetime.date.fromisoformat(eq_curve[-1][0]) -
                datetime.date.fromisoformat(eq_curve[0][0])).days
        years = days / 365.25 if days > 0 else 1
        e1 = eq_curve[-1][1]
        cagr = (e1 / start_equity) ** (1 / years) - 1 if start_equity > 0 and years > 0 else 0
    else:
        cagr = 0

    return {
        'label': label,
        'trades': len(trades),
        'net_pnl': sum(pnl),
        'pf': round(gp / gl, 2) if gl > 0 else 999,
        'win_rate': round(len(wins) / len(trades) * 100, 1),
        'max_dd_pct': round(mdd_pct * 100, 2),
        'cagr': round(cagr * 100, 2),
        'sharpe': round(sharpe, 2),
        'avg_r': round(sum(pnl) / len(pnl), 2),
        'max_consec_loss': streak,
    }

# ============================================================
# BACKTEST: TREND FOLLOW (Variant J/K, TF-FP, TF-MP)
# ============================================================

def run_trend_follow(bars, mode='variant_j', stop_mode='atr',
                     fast=20, slow=50, long_only=True,
                     risk_pct=1.0, cost=0.25, start_eq=100000,
                     date_from=None, date_to=None,
                     init_stop_atr=2.0, trail_atr=4.0,
                     swing_lookback=10, swing_buffer=0.002,
                     stop_pct=1.5, trail_pct=2.0,
                     fixed_stop_pts=50.0, fixed_trail_pts=30.0,
                     max_adds=5, add_dist_atr=1.5, add_dist_pct=0.03,
                     martin_mult=1.3):

    d = [b['date'] for b in bars]; o = [b['open'] for b in bars]
    h = [b['high'] for b in bars]; l = [b['low'] for b in bars]
    c = [b['close'] for b in bars]
    n = len(c)

    ef = ema(c, fast); es = ema(c, slow)
    ATR = wilder(true_range(h, l, c), 14)

    warm = max(slow, 50, 14) + 5
    i0 = next((i for i in range(warm, n) if date_from is None or d[i] >= date_from), warm)
    i1 = n - 1 if date_to is None else max((i for i in range(n) if d[i] <= date_to), default=n-1)

    equity = start_eq; cash = start_eq
    pos = None; trades = []; eq_curve = []
    pyramid_count = 0; last_entry_px = 0
    highest = 0; lowest = 1e9; pos_dir = 0

    def calc_init_sl(entry, direction, idx):
        atr = ATR[idx] if ATR[idx] else entry * 0.02
        if stop_mode == 'atr':
            return entry - direction * init_stop_atr * atr
        elif stop_mode == 'swing':
            if direction == 1:
                sw = find_swing_low(l, idx, swing_lookback)
                return sw * (1 - swing_buffer)
            else:
                sw = find_swing_high(h, idx, swing_lookback)
                return sw * (1 + swing_buffer)
        elif stop_mode == 'percent':
            return entry * (1 - direction * stop_pct / 100)
        elif stop_mode == 'fixed':
            return entry - direction * fixed_stop_pts
        return entry - direction * 2 * atr

    def calc_trail_sl(extreme, direction, idx):
        atr = ATR[idx] if ATR[idx] else extreme * 0.02
        if stop_mode == 'atr':
            return extreme - direction * trail_atr * atr
        elif stop_mode == 'swing':
            return extreme * (1 - direction * stop_pct / 100)
        elif stop_mode == 'percent':
            return extreme * (1 - direction * trail_pct / 100)
        elif stop_mode == 'fixed':
            return extreme - direction * fixed_trail_pts
        return extreme - direction * trail_atr * atr

    def calc_lot(sl_dist, level):
        risk_cash = equity * risk_pct / 100
        base = risk_cash / sl_dist if sl_dist > 0 else 0
        if mode == 'tf_mp' and level > 0:
            base *= martin_mult ** level
        return max(base, 0)

    enable_pyramid = mode in ('variant_k', 'tf_fp', 'tf_mp')

    for i in range(i0, i1 + 1):
        # --- signals ---
        sig = 0
        if ef[i] is not None and es[i] is not None and ef[i-1] is not None and es[i-1] is not None:
            if ef[i] > es[i] and ef[i-1] <= es[i-1]: sig = 1
            elif ef[i] < es[i] and ef[i-1] >= es[i-1]: sig = -1

        # re-entry (Variant J/K behavior)
        if mode in ('variant_j', 'variant_k') and sig == 0 and pos is None:
            if ef[i] is not None and es[i] is not None:
                if ef[i] > es[i] and c[i] > ef[i] and c[i-1] <= ef[i-1]:
                    sig = 1

        if long_only and sig == -1:
            if pos is not None and pos_dir == 1:
                sig = -1  # allow close signal
            else:
                sig = 0

        # --- manage existing position ---
        if pos is not None:
            dr = pos_dir
            if dr == 1:
                highest = max(highest, h[i])
            else:
                lowest = min(lowest, l[i])

            # stop check
            stopped = False
            for u in pos['units'][:]:
                hit = (l[i] <= u['stop']) if dr > 0 else (h[i] >= u['stop'])
                if hit:
                    px = min(o[i], u['stop']) if dr > 0 else max(o[i], u['stop'])
                    pnl_u = (px - u['entry']) * u['size'] * dr - cost * u['size']
                    cash += pnl_u
                    pos['pnl'] += pnl_u
                    pos['units'].remove(u)
            if not pos['units']:
                trades.append(pos)
                pos = None; pos_dir = 0; pyramid_count = 0
                stopped = True

            # trail update
            if pos is not None:
                extreme = highest if dr > 0 else lowest
                new_sl = calc_trail_sl(extreme, dr, i)
                for u in pos['units']:
                    if dr > 0:
                        u['stop'] = max(u['stop'], new_sl)
                    else:
                        u['stop'] = min(u['stop'], new_sl)

            # cross exit
            if pos is not None and sig != 0 and sig != pos_dir:
                for u in pos['units']:
                    pnl_u = (c[i] - u['entry']) * u['size'] * dr - cost * u['size']
                    cash += pnl_u
                    pos['pnl'] += pnl_u
                pos['units'] = []
                trades.append(pos)
                pos = None; pos_dir = 0; pyramid_count = 0

            # pyramid add
            if pos is not None and enable_pyramid and pyramid_count < max_adds:
                dr = pos_dir
                atr = ATR[i] if ATR[i] else c[i] * 0.02
                if stop_mode in ('atr', 'swing'):
                    min_dist = add_dist_atr * atr
                else:
                    min_dist = c[i] * add_dist_pct
                moved = (c[i] - last_entry_px) * dr >= min_dist
                in_profit = sum((c[i] - u['entry']) * u['size'] * dr for u in pos['units']) > 0
                if moved and in_profit:
                    sl = calc_trail_sl(highest if dr > 0 else lowest, dr, i)
                    sl_dist = abs(c[i] - sl)
                    lot = calc_lot(sl_dist, pyramid_count + 1)
                    if lot > 0 and sl_dist > 0:
                        pos['units'].append({'entry': c[i], 'size': lot, 'stop': sl})
                        last_entry_px = c[i]
                        pyramid_count += 1

        # --- new entry ---
        if pos is None and sig != 0 and not (long_only and sig < 0):
            dr = sig
            entry = o[i]
            sl = calc_init_sl(entry, dr, i)
            sl_dist = abs(entry - sl)
            if sl_dist > 0:
                lot = calc_lot(sl_dist, 0)
                if lot > 0:
                    pos = {'dir': dr, 'units': [{'entry': entry, 'size': lot, 'stop': sl}],
                           'pnl': 0, 'open_date': d[i]}
                    pos_dir = dr; pyramid_count = 0; last_entry_px = entry
                    highest = h[i]; lowest = l[i]

        # equity
        open_pnl = 0
        if pos:
            for u in pos['units']:
                open_pnl += (c[i] - u['entry']) * u['size'] * pos_dir
        equity = cash + open_pnl
        eq_curve.append((d[i], equity))

    # close remaining
    if pos:
        dr = pos_dir
        for u in pos['units']:
            pnl_u = (c[i1] - u['entry']) * u['size'] * dr - cost * u['size']
            cash += pnl_u
            pos['pnl'] += pnl_u
        trades.append(pos)
        equity = cash
        if eq_curve:
            eq_curve[-1] = (d[i1], equity)

    return trades, eq_curve

# ============================================================
# BACKTEST: NANPIN MARTIN (NM-S20, NM-R50)
# ============================================================

def run_nanpin_martin(bars, mode='nm_s20', cost=0.25, start_eq=100000,
                      date_from=None, date_to=None):

    if mode == 'nm_s20':
        lot_per_unit = 0.01; lot_unit = 10000
        grid_base = 5.0; grid_expand = 1.5; max_layers = 6
        martin = 1.3; basket_tp = 3.0; dd_thresh = 20.0; timeout = 480
    else:
        lot_per_unit = 0.01; lot_unit = 5000
        grid_base = 3.0; grid_expand = 1.2; max_layers = 10
        martin = 1.8; basket_tp = 2.0; dd_thresh = 50.0; timeout = 720

    d = [b['date'] for b in bars]; o = [b['open'] for b in bars]
    h = [b['high'] for b in bars]; l = [b['low'] for b in bars]
    c = [b['close'] for b in bars]
    n = len(c)

    RSI = rsi(c, 14)
    BB_upper, BB_mid, BB_lower = bollinger(c, 20, 2.0)

    warm = 50
    i0 = next((i for i in range(warm, n) if date_from is None or d[i] >= date_from), warm)
    i1 = n - 1 if date_to is None else max((i for i in range(n) if d[i] <= date_to), default=n-1)

    equity = start_eq; cash = start_eq; balance = start_eq
    basket = None; trades = []; eq_curve = []

    def base_lot():
        return lot_per_unit * (equity / lot_unit)

    def grid_spacing(level):
        return grid_base * (grid_expand ** (level - 1))

    def avg_price():
        if not basket or not basket['units']:
            return 0
        total_lp = sum(u['size'] * u['entry'] for u in basket['units'])
        total_l = sum(u['size'] for u in basket['units'])
        return total_lp / total_l if total_l > 0 else 0

    def total_lots():
        if not basket:
            return 0
        return sum(u['size'] for u in basket['units'])

    def basket_pnl(price):
        if not basket:
            return 0
        dr = basket['dir']
        return sum((price - u['entry']) * u['size'] * dr for u in basket['units'])

    def close_basket(price, reason):
        nonlocal cash, balance, basket
        pnl = 0
        for u in basket['units']:
            pnl_u = (price - u['entry']) * u['size'] * basket['dir'] - cost * u['size']
            cash += pnl_u
            pnl += pnl_u
        trade = {'dir': basket['dir'], 'pnl': pnl, 'layers': len(basket['units']),
                 'open_date': basket['open_date'], 'reason': reason,
                 'total_lot': total_lots()}
        trades.append(trade)
        balance = cash
        basket = None

    for i in range(i0, i1 + 1):
        if basket is not None:
            # --- equity DD check ---
            open_pnl = basket_pnl(c[i])
            equity = cash + open_pnl
            dd_pct = (balance - equity) / balance * 100 if balance > 0 else 0
            if dd_pct >= dd_thresh:
                close_basket(c[i], 'equity_stop')
                equity = cash
                eq_curve.append((d[i], equity))
                continue

            # --- basket TP check ---
            avg = avg_price()
            dr = basket['dir']
            if avg > 0:
                tp_price = avg + dr * basket_tp
                hit = (h[i] >= tp_price) if dr > 0 else (l[i] <= tp_price)
                if hit:
                    close_basket(tp_price, 'basket_tp')
                    equity = cash
                    eq_curve.append((d[i], equity))
                    continue

            # --- timeout check ---
            bars_elapsed = i - basket['start_idx']
            if bars_elapsed >= timeout:
                close_basket(c[i], 'timeout')
                equity = cash
                eq_curve.append((d[i], equity))
                continue

            # --- grid add check ---
            if basket['grid_count'] < max_layers:
                worst = basket['worst_price']
                level = basket['grid_count'] + 1
                required_dist = grid_spacing(level)
                price = c[i]
                triggered = False
                if dr == 1 and price <= worst - required_dist:
                    triggered = True
                elif dr == -1 and price >= worst + required_dist:
                    triggered = True

                if triggered:
                    lot = base_lot() * (martin ** level)
                    lot = max(lot, 0.01)
                    basket['units'].append({'entry': price, 'size': lot})
                    basket['grid_count'] += 1
                    if dr == 1:
                        basket['worst_price'] = min(basket['worst_price'], price)
                    else:
                        basket['worst_price'] = max(basket['worst_price'], price)

        else:
            equity = cash

            # --- entry signal ---
            if RSI[i-1] is None or BB_upper[i-1] is None:
                eq_curve.append((d[i], equity))
                continue

            sig = 0
            if RSI[i-1] < 30 and l[i-1] <= BB_lower[i-1]:
                sig = 1
            elif RSI[i-1] > 70 and h[i-1] >= BB_upper[i-1]:
                sig = -1

            if sig != 0:
                lot = base_lot()
                lot = max(lot, 0.01)
                entry = o[i]
                basket = {
                    'dir': sig,
                    'units': [{'entry': entry, 'size': lot}],
                    'open_date': d[i],
                    'start_idx': i,
                    'grid_count': 0,
                    'worst_price': entry,
                }
                balance = cash

        open_pnl = basket_pnl(c[i]) if basket else 0
        equity = cash + open_pnl
        eq_curve.append((d[i], equity))

    if basket:
        close_basket(c[i1], 'end')
        equity = cash
        if eq_curve:
            eq_curve[-1] = (d[i1], equity)

    return trades, eq_curve

# ============================================================
# MAIN
# ============================================================

def load_bars(path):
    bars = []
    with open(path) as f:
        for row in csv.DictReader(f):
            bars.append({
                'date': row['date'],
                'open': float(row['open']),
                'high': float(row['high']),
                'low': float(row['low']),
                'close': float(row['close']),
            })
    return bars

def main():
    path = sys.argv[1] if len(sys.argv) > 1 else 'GCUSD_daily.csv'
    bars = load_bars(path)
    print(f"Loaded {len(bars)} bars: {bars[0]['date']} -> {bars[-1]['date']}")

    splits = [
        ('IS 2008-2015', '2008-01-01', '2015-12-31'),
        ('IS 2016-2019', '2016-01-01', '2019-12-31'),
        ('OOS 2020-2026', '2020-01-01', '2026-12-31'),
    ]

    configs = [
        ('Variant-J',   lambda b, f, t: run_trend_follow(b, 'variant_j', 'atr', date_from=f, date_to=t)),
        ('Variant-K',   lambda b, f, t: run_trend_follow(b, 'variant_k', 'atr', date_from=f, date_to=t)),
        ('TF-FP(ATR)',  lambda b, f, t: run_trend_follow(b, 'tf_fp', 'atr', long_only=False, date_from=f, date_to=t)),
        ('TF-FP(Swing)',lambda b, f, t: run_trend_follow(b, 'tf_fp', 'swing', long_only=False, date_from=f, date_to=t)),
        ('TF-FP(Pct)',  lambda b, f, t: run_trend_follow(b, 'tf_fp', 'percent', long_only=False, date_from=f, date_to=t)),
        ('TF-FP(Fixed)',lambda b, f, t: run_trend_follow(b, 'tf_fp', 'fixed', long_only=False, date_from=f, date_to=t)),
        ('TF-MP(ATR)',  lambda b, f, t: run_trend_follow(b, 'tf_mp', 'atr', long_only=False, date_from=f, date_to=t)),
        ('TF-MP(Swing)',lambda b, f, t: run_trend_follow(b, 'tf_mp', 'swing', long_only=False, date_from=f, date_to=t)),
        ('NM-S20',      lambda b, f, t: run_nanpin_martin(b, 'nm_s20', date_from=f, date_to=t)),
        ('NM-R50',      lambda b, f, t: run_nanpin_martin(b, 'nm_r50', date_from=f, date_to=t)),
    ]

    all_results = []
    start_eq = 100000

    for split_name, sf, st in splits:
        print(f"\n{'='*70}")
        print(f"  {split_name} ({sf} ~ {st})")
        print(f"{'='*70}")
        hdr = f"{'EA':<16} {'Trades':>6} {'PF':>6} {'Win%':>6} {'NetPnL':>12} {'MaxDD%':>7} {'CAGR%':>7} {'Sharpe':>7} {'MaxCL':>5}"
        print(hdr)
        print('-' * len(hdr))

        for label, run_fn in configs:
            try:
                trades, eq_curve = run_fn(bars, sf, st)
                m = compute_metrics(trades, eq_curve, start_eq, label)
                m['split'] = split_name
                all_results.append(m)
                print(f"{label:<16} {m['trades']:>6} {m['pf']:>6.2f} {m['win_rate']:>5.1f}% "
                      f"{m['net_pnl']:>12,.0f} {m['max_dd_pct']:>6.1f}% {m['cagr']:>6.1f}% "
                      f"{m['sharpe']:>7.2f} {m['max_consec_loss']:>5}")
            except Exception as e:
                print(f"{label:<16} ERROR: {e}")
                all_results.append({'label': label, 'split': split_name, 'error': str(e)})

    # Full period summary
    print(f"\n{'='*70}")
    print(f"  FULL PERIOD (2008-2026)")
    print(f"{'='*70}")
    hdr = f"{'EA':<16} {'Trades':>6} {'PF':>6} {'Win%':>6} {'NetPnL':>12} {'MaxDD%':>7} {'CAGR%':>7} {'Sharpe':>7} {'MaxCL':>5}"
    print(hdr)
    print('-' * len(hdr))

    for label, run_fn in configs:
        try:
            trades, eq_curve = run_fn(bars, None, None)
            m = compute_metrics(trades, eq_curve, start_eq, label)
            m['split'] = 'FULL'
            all_results.append(m)
            print(f"{label:<16} {m['trades']:>6} {m['pf']:>6.2f} {m['win_rate']:>5.1f}% "
                  f"{m['net_pnl']:>12,.0f} {m['max_dd_pct']:>6.1f}% {m['cagr']:>6.1f}% "
                  f"{m['sharpe']:>7.2f} {m['max_consec_loss']:>5}")
        except Exception as e:
            print(f"{label:<16} ERROR: {e}")

    # Save results
    out_path = path.rsplit('.', 1)[0] + '_all_ea_results.json'
    with open(out_path, 'w') as f:
        json.dump(all_results, f, indent=2, default=str)
    print(f"\nResults saved to {out_path}")

if __name__ == '__main__':
    main()
