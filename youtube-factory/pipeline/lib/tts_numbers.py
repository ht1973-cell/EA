"""日本語の数字読み上げを、ルールベースで機械的に生成する。

背景：TTS(MiniMax等)は漢数字→読み仮名の変換を内部G2Pに任せており、
「十八」を『じゅうばち』のように誤って連濁させることがある(モデル側のバグ)。
この誤りは"AIが気まぐれに間違える"ものであり、人間が毎回目視で直すのは
非現実的。そこで日本語の数詞読み上げルール(百・千の連濁パターンを含む)を
決定的なアルゴリズムとして実装し、常に正しい読みのひらがな文字列を生成して
TTSに渡す。これにより同種の誤読はシリーズ全体で構造的に再発しなくなる。

対応範囲：0〜99,999,999(億の位まで)の整数。「20万円」のような算用数字＋
漢数字の混在表記にも対応する。金融系動画で読み上げる年数・金額・
パーセンテージ・人数等はこの範囲でほぼ全てカバーできる。
"""
import re

_DIGITS = ["", "いち", "に", "さん", "よん", "ご", "ろく", "なな", "はち", "きゅう"]

# 百の位：連濁(rendaku)がある数字だけ特別な読みを持つ
_HYAKU = {
    1: "ひゃく", 2: "にひゃく", 3: "さんびゃく", 4: "よんひゃく", 5: "ごひゃく",
    6: "ろっぴゃく", 7: "ななひゃく", 8: "はっぴゃく", 9: "きゅうひゃく",
}

# 千の位：連濁がある数字だけ特別な読みを持つ
_SEN = {
    1: "せん", 2: "にせん", 3: "さんぜん", 4: "よんせん", 5: "ごせん",
    6: "ろくせん", 7: "ななせん", 8: "はっせん", 9: "きゅうせん",
}


def _read_0_9999(n: int) -> str:
    """0〜9999の整数を読み仮名にする(百・千の連濁ルール込み)。"""
    if n == 0:
        return "ゼロ"
    s = ""
    sen, n = divmod(n, 1000)
    if sen:
        s += _SEN[sen]
    hyaku, n = divmod(n, 100)
    if hyaku:
        s += _HYAKU[hyaku]
    juu, ichi = divmod(n, 10)
    if juu:
        s += ("じゅう" if juu == 1 else _DIGITS[juu] + "じゅう")
    if ichi:
        s += _DIGITS[ichi]
    return s


def number_to_yomi(n: int) -> str:
    """整数nの正しい日本語読み(ひらがな)を返す。億・万の位に対応。

    例: 18 -> 'じゅうはち'（『じゅうばち』のような誤連濁を起こさない）
        300 -> 'さんびゃく', 600 -> 'ろっぴゃく', 800 -> 'はっぴゃく'
        3000 -> 'さんぜん', 8000 -> 'はっせん'
        200000 -> 'にじゅうまん'（=20万）
    """
    if n < 0:
        return "マイナス" + number_to_yomi(-n)
    if n == 0:
        return "ゼロ"

    oku, rem = divmod(n, 100_000_000)
    man, rest = divmod(rem, 10_000)

    parts = []
    if oku:
        parts.append(_read_0_9999(oku) + "おく")
    if man:
        parts.append(_read_0_9999(man) + "まん")
    if rest or not parts:
        parts.append(_read_0_9999(rest))
    return "".join(parts)


# ---- 算用数字・漢数字が混在した表記(例:「20万」「二百三十」)を1つの整数に解析する ----

_KANJI_DIGIT = {"〇": 0, "一": 1, "二": 2, "三": 3, "四": 4,
                "五": 5, "六": 6, "七": 7, "八": 8, "九": 9}
_KANJI_UNIT = {"十": 10, "百": 100, "千": 1000}
_KANJI_BIG = {"万": 10_000, "億": 100_000_000}

_HALF_DIGITS = "0123456789"
_FULL_DIGITS = "０１２３４５６７８９"
_ZEN_TO_HAN = str.maketrans(_FULL_DIGITS, _HALF_DIGITS)

_NUMERAL_CHARS = _HALF_DIGITS + _FULL_DIGITS + "".join(_KANJI_DIGIT) + "".join(_KANJI_UNIT) + "".join(_KANJI_BIG)


def _parse_mixed_number(s: str) -> int:
    """'20万'->200000, '十八'->18, '二百三十'->230 のように、
    算用数字と漢数字が混在していても正しく整数へ解析する。
    """
    total = 0    # 億・万で確定した累計
    section = 0  # 直近の万/億区切り内(1〜9999)の累計
    num = 0      # 直前に読んだ生の数字(位取り前)
    i, n = 0, len(s)
    while i < n:
        ch = s[i]
        if ch in _HALF_DIGITS or ch in _FULL_DIGITS:
            j = i
            while j < n and (s[j] in _HALF_DIGITS or s[j] in _FULL_DIGITS):
                j += 1
            num = int(s[i:j].translate(_ZEN_TO_HAN))
            i = j
            continue
        if ch in _KANJI_DIGIT:
            num = _KANJI_DIGIT[ch]
        elif ch in _KANJI_UNIT:
            section += (num or 1) * _KANJI_UNIT[ch]
            num = 0
        elif ch in _KANJI_BIG:
            total += (section + num) * _KANJI_BIG[ch]
            section = 0
            num = 0
        i += 1
    return total + section + num


_UNIT_LOOKAHEAD = "パーセント|％|%|円|年|人|歳|件|回|か月|ヶ月|日"
_NUMERAL_RUN_RE = re.compile(
    rf"(?<![{_NUMERAL_CHARS}])([{_NUMERAL_CHARS}]+)(?={_UNIT_LOOKAHEAD})"
)


def normalize_numbers_for_tts(text: str) -> str:
    """テキスト中の算用数字・漢数字を、単位の直前だけ正しい読みのひらがなに置換する。

    「18％」「十八パーセント」「20万円」等、数字表記に起因するTTSの誤読
    （例：MiniMaxが『十八』を連濁させ『じゅうばち』と読んだバグ）を、
    人手の目視チェックに頼らずアルゴリズムで機械的に防ぐための正規化。
    画面表示用の narration 側の表記(18％・十八パーセント等)はそのまま残し、
    TTSに渡す tts_prompt 側にのみ適用すること。
    """
    def _sub(m: re.Match) -> str:
        return number_to_yomi(_parse_mixed_number(m.group(1)))

    return _NUMERAL_RUN_RE.sub(_sub, text)
