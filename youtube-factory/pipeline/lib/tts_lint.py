"""台本のnarration(画面表示用・正しい漢字)から、TTSに渡すtts_prompt
(音声合成専用・誤読しない開き読み)を自動生成する、恒久的な品質ゲート。

これまでの運用（人間が耳で聴いて誤読を見つけ、都度ひらがなに手直しする）
を、以下2つの自動処理に置き換える：

  1. 数字の読み修正 … tts_numbers.py のルールベース変換
     （「十八」を『じゅうばち』のように誤連濁させるバグを構造的に防ぐ）
  2. 専門用語の読み修正 … tts_homographs.json の辞書置換
     （「貯金」を『じょきん』と誤読する等、G2P辞書の誤りを吸収する）

新しい語の誤読が見つかった場合は tts_homographs.json に追記するだけで、
シリーズ全52本すべてに反映される（1話ずつ手直しする必要がない）。
"""
import json
import os
import re

_HERE = os.path.dirname(os.path.abspath(__file__))
_HOMOGRAPH_PATH = os.path.join(_HERE, "tts_homographs.json")

import sys
sys.path.insert(0, _HERE)
from tts_numbers import normalize_numbers_for_tts  # noqa: E402


def _load_homographs():
    with open(_HOMOGRAPH_PATH, encoding="utf-8") as f:
        d = json.load(f)
    d.pop("_comment", None)
    # 長い語から先に置換する（「非課税」を「課税」置換で壊さないため）
    return sorted(d.items(), key=lambda kv: -len(kv[0]))


_HOMOGRAPHS = _load_homographs()


def apply_homographs(text: str) -> str:
    for kanji, kana in _HOMOGRAPHS:
        text = text.replace(kanji, kana)
    return text


def build_tts_prompt(narration: str) -> str:
    """narration(表示用)からtts_prompt(合成用)を自動生成する。"""
    text = apply_homographs(narration)
    text = normalize_numbers_for_tts(text)
    return text


# ---- 生成後の音声に対する異常検知(尺の統計的アノマリー) ----
# 長文一括生成や特定条件でTTSが確率的にノイズ/幻聴的な音を混入させることが
# あるため、「文字数から想定される尺」と「実測の尺」を突き合わせ、
# 大きくズレていたら異常(ノイズ混入や無音excessなど)の疑いとして検出する。

# 日本語ナレーションの標準的な速度の目安（文字/秒）。個人差・声質差を
# 考慮して広めのレンジを許容する。
_CHARS_PER_SEC_MIN = 4.0   # これより遅い=無音区間や間延びの疑い
_CHARS_PER_SEC_MAX = 9.5   # これより速い=早口すぎる/読み飛ばしの疑い


def check_duration_anomaly(narration: str, actual_seconds: float):
    """尺の異常を検知する。戻り値: (is_anomaly: bool, detail: str)

    実際の音声内容までは検証できない（この環境にASR/文字起こしツールが
    無いため）が、「想定尺から大きく外れている」ことは、ノイズ混入・
    無音excess・読み飛ばし等、何らかの異常が起きた強いシグナルになる。
    per-scene(短文)生成を前提にした閾値。
    """
    n_chars = len(re.sub(r"[、。\s]", "", narration))
    if n_chars == 0:
        return False, "空文のためスキップ"
    expected_min = n_chars / _CHARS_PER_SEC_MAX
    expected_max = n_chars / _CHARS_PER_SEC_MIN
    if actual_seconds < expected_min * 0.7:
        return True, (f"尺が短すぎる疑い: 文字数{n_chars} 想定{expected_min:.1f}"
                       f"-{expected_max:.1f}秒 実測{actual_seconds:.1f}秒")
    if actual_seconds > expected_max * 1.6:
        return True, (f"尺が長すぎる疑い(ノイズ/幻聴混入の可能性): 文字数{n_chars} "
                       f"想定{expected_min:.1f}-{expected_max:.1f}秒 実測{actual_seconds:.1f}秒")
    return False, "正常範囲"
