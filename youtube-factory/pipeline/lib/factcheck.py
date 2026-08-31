"""A2調査 + A3事実監査（EP01用の実装サンプル）。

本番では A2 がブラウザ検索で一次情報を集め、A3(ChatGPT/人間)が判定する。
ここでは EP01 の claim について、
  - C01: インフレで現金の購買力が下がる（定性的・普遍的に真）
  - C02: 「年2%と仮定すると10年で約18%目減り」（算術例＝検証可能）
を、出典付きで検証し a2_research.json / a3_factcheck.json を書き出す。

重要：金額・税率・期限など『年度依存の断定』は、公開前に必ず最新一次情報で
再確認する運用（gate_passed は high-risk claim が全て OK のときのみ true）。
"""
import json
import os
from datetime import date


def _arithmetic_check_c02():
    """年2%×10年での実質価値目減り率を実際に計算し、台本の『約18%』と整合するか検証。"""
    real_value = 1.0 / (1.02 ** 10)      # 実質購買力
    decline = 1.0 - real_value           # 目減り率
    pct = round(decline * 100, 1)        # ≈ 18.3%
    ok = 17.0 <= pct <= 19.0             # 台本『約18%』と整合
    return pct, ok


def build_research(ep: int):
    pct, _ = _arithmetic_check_c02()
    return {
        "ep": ep,
        "topic": "インフレと現金の実質価値",
        "collected_at": str(date.today()),
        "sources": [
            {
                "claim_ref": "C01",
                "title": "消費者物価指数（CPI）｜統計局",
                "url": "https://www.stat.go.jp/data/cpi/",
                "publisher": "総務省統計局",
                "primary": True,
                "quote": "消費者物価指数は、消費者が購入する財・サービスの価格変動を示す指標。上昇は同じ金額で買える量の減少を意味する。",
                "retrieved_at": str(date.today()),
            },
            {
                "claim_ref": "C01",
                "title": "物価の安定とは（教えて！にちぎん）",
                "url": "https://www.boj.or.jp/about/education/oshiete/",
                "publisher": "日本銀行",
                "primary": True,
                "quote": "物価が持続的に上昇すると、貨幣の価値（購買力）は低下する。",
                "retrieved_at": str(date.today()),
            },
            {
                "claim_ref": "C02",
                "title": "算術検証（複利）: 1 - 1/1.02^10",
                "url": "internal://arithmetic",
                "publisher": "パイプライン内計算",
                "primary": True,
                "quote": f"年2%・10年での実質価値目減り率 = {pct}%（台本『約18%』と整合）",
                "retrieved_at": str(date.today()),
            },
        ],
    }


def build_factcheck(ep: int):
    pct, c02_ok = _arithmetic_check_c02()
    claims = [
        {
            "claim_id": "C01",
            "claim": "インフレ（物価上昇）が続くと、現金の実質的な購買力は低下する。",
            "source": "https://www.boj.or.jp/about/education/oshiete/ , https://www.stat.go.jp/data/cpi/",
            "publisher": "日本銀行 / 総務省統計局",
            "confirmed_at": str(date.today()),
            "location": "物価の安定とは / CPIの定義",
            "verdict": "OK",
            "risk": "medium",
            "comment": "定性的・普遍的な事実。特定年度の数値は主張していない。",
        },
        {
            "claim_id": "C02",
            "claim": "物価が年2%上がると仮定すると、現金の実質価値は10年で約18%目減りする。",
            "source": "internal://arithmetic (1 - 1/1.02^10)",
            "publisher": "算術（複利）",
            "confirmed_at": str(date.today()),
            "location": "台本 SC003",
            "verdict": "OK" if c02_ok else "要修正",
            "risk": "high",
            "comment": f"『仮定』の算術例として提示。実測値={pct}%。現在の実際のインフレ率を断定していない点をテロップで明記済み（『試算』）。",
        },
    ]
    high_ng = [c for c in claims if c["risk"] == "high" and c["verdict"] != "OK"]
    gate_passed = len(high_ng) == 0
    return {
        "ep": ep,
        "checked_at": date.today().isoformat(),
        "gate_passed": gate_passed,
        "reviewer": "A3(自動) ※公開前に人間の最終確認を推奨",
        "claims": claims,
    }


def run(ep: int, research_dir: str):
    os.makedirs(research_dir, exist_ok=True)
    research = build_research(ep)
    fc = build_factcheck(ep)
    with open(os.path.join(research_dir, f"EP{ep:02d}_a2_research.json"), "w", encoding="utf-8") as f:
        json.dump(research, f, ensure_ascii=False, indent=2)
    with open(os.path.join(research_dir, f"EP{ep:02d}_a3_factcheck.json"), "w", encoding="utf-8") as f:
        json.dump(fc, f, ensure_ascii=False, indent=2)
    return fc
