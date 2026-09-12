#!/usr/bin/env python3
"""Compute the daily/weekly indicators used in the Prompt 2 example.

Usage:  python3 compute_indicators.py GCUSD_daily_2024-09-02_2026-09-11.csv

Pure standard library (no pandas). Wilder smoothing for RSI/ATR/ADX,
standard EMA for MACD(12,26,9). Weekly bars are ISO-week aggregates.
"""
import csv, datetime, sys


def sma(x, p):
    return [None if i < p - 1 else sum(x[i - p + 1:i + 1]) / p for i in range(len(x))]


def ema(x, p):
    k = 2 / (p + 1); out = [None] * len(x); s = None
    for i, v in enumerate(x):
        if v is None:
            continue
        s = v if s is None else v * k + s * (1 - k)
        out[i] = s
    return out


def rsi(x, p=14):
    out = [None] * len(x); g = l = None; gs = []; ls = []
    for i in range(1, len(x)):
        ch = x[i] - x[i - 1]; up = max(ch, 0); dn = max(-ch, 0)
        if i < p:
            gs.append(up); ls.append(dn)
            if i == p - 1:
                g = sum(gs) / p; l = sum(ls) / p
            continue
        g = (g * (p - 1) + up) / p; l = (l * (p - 1) + dn) / p
        out[i] = 100 if l == 0 else 100 - 100 / (1 + g / l)
    return out


def true_range(h, l, c):
    return [None] + [max(h[i] - l[i], abs(h[i] - c[i - 1]), abs(l[i] - c[i - 1])) for i in range(1, len(c))]


def atr(h, l, c, p=14):
    tr = true_range(h, l, c); out = [None] * len(c); s = None
    for i in range(p, len(c)):
        s = sum(tr[1:p + 1]) / p if s is None else (s * (p - 1) + tr[i]) / p
        out[i] = s
    return out


def adx(h, l, c, p=14):
    pdm = [0]; ndm = [0]; tr = [0]
    for i in range(1, len(c)):
        up = h[i] - h[i - 1]; dn = l[i - 1] - l[i]
        pdm.append(up if up > dn and up > 0 else 0)
        ndm.append(dn if dn > up and dn > 0 else 0)
        tr.append(max(h[i] - l[i], abs(h[i] - c[i - 1]), abs(l[i] - c[i - 1])))

    def wilder_sum(x):
        out = [None] * len(x); s = None
        for i in range(p, len(x)):
            s = sum(x[1:p + 1]) if s is None else s - s / p + x[i]
            out[i] = s
        return out

    st, sp, sn = wilder_sum(tr), wilder_sum(pdm), wilder_sum(ndm)
    pdi = [None if st[i] is None else 100 * sp[i] / st[i] for i in range(len(c))]
    ndi = [None if st[i] is None else 100 * sn[i] / st[i] for i in range(len(c))]
    dx = [None if pdi[i] is None or pdi[i] + ndi[i] == 0 else 100 * abs(pdi[i] - ndi[i]) / (pdi[i] + ndi[i]) for i in range(len(c))]
    out = [None] * len(c); s = None; buf = []
    for i in range(len(c)):
        if dx[i] is None:
            continue
        if s is None:
            buf.append(dx[i])
            if len(buf) == p:
                s = sum(buf) / p; out[i] = s
        else:
            s = (s * (p - 1) + dx[i]) / p; out[i] = s
    return out, pdi, ndi


def macd(x, fast=12, slow=26, sig=9):
    ef, es = ema(x, fast), ema(x, slow)
    m = [None if ef[i] is None or es[i] is None else ef[i] - es[i] for i in range(len(x))]
    s = ema([None if i < slow - 1 else m[i] for i in range(len(x))], sig)
    return m, s


def swings(dates, h, l, k=2):
    sh = [(dates[j], h[j]) for j in range(k, len(h) - k) if h[j] == max(h[j - k:j + k + 1])]
    sl = [(dates[j], l[j]) for j in range(k, len(l) - k) if l[j] == min(l[j - k:j + k + 1])]
    return sh, sl


def report(tag, dates, o, h, l, c):
    f = lambda v: None if v is None else round(v, 2)
    i = len(c) - 1
    S20, S50, S200 = sma(c, 20), sma(c, 50), sma(c, 200)
    E20, E50 = ema(c, 20), ema(c, 50)
    R = rsi(c); A = atr(h, l, c); AD, PDI, NDI = adx(h, l, c); M, SG = macd(c)
    sh, sl = swings(dates, h, l)
    print(f"\n=== {tag} === last bar {dates[i]} O{o[i]} H{h[i]} L{l[i]} C{c[i]}")
    print("SMA20/50/200:", f(S20[i]), f(S50[i]), f(S200[i]), "| EMA20/50:", f(E20[i]), f(E50[i]))
    print("RSI14:", f(R[i]))
    print("MACD/signal/hist:", f(M[i]), f(SG[i]), f(M[i] - SG[i]))
    print("ADX14/+DI/-DI:", f(AD[i]), f(PDI[i]), f(NDI[i]))
    print("ATR14:", f(A[i]), f"({100 * A[i] / c[i]:.2f}%)")
    print("swing highs:", sh[-6:])
    print("swing lows:", sl[-6:])
    print("SMA20 slope(10):", f(S20[i] - S20[i - 10]), "SMA50 slope(10):", f(S50[i] - S50[i - 10]))


def main(path):
    rows = list(csv.DictReader(open(path)))
    rows.sort(key=lambda r: r["date"])
    dates = [r["date"] for r in rows]
    o, h, l, c = ([float(r[k]) for r in rows] for k in ("open", "high", "low", "close"))
    report("DAILY", dates, o, h, l, c)
    wk = {}
    for j, d in enumerate(dates):
        y, w, _ = datetime.date.fromisoformat(d).isocalendar()
        b = wk.setdefault((y, w), dict(d=d, o=o[j], h=h[j], l=l[j], c=c[j]))
        b["h"] = max(b["h"], h[j]); b["l"] = min(b["l"], l[j]); b["c"] = c[j]
    W = [wk[k] for k in sorted(wk)]
    report("WEEKLY", [x["d"] for x in W], [x["o"] for x in W], [x["h"] for x in W], [x["l"] for x in W], [x["c"] for x in W])


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "GCUSD_daily_2024-09-02_2026-09-11.csv")
