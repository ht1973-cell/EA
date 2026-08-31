"""尺計算 + 字幕(SRT)生成（A9編集の一部）。

- 各sceneの表示尺は、voice/ に実ナレーションwavがあればその実測長、無ければ est_seconds。
- 字幕は narration をそのまま焼き込む/ソフト字幕にできる形で SRT 出力。
"""
import os
import wave
import contextlib


def wav_duration(path):
    try:
        with contextlib.closing(wave.open(path, "r")) as w:
            return w.getnframes() / float(w.getframerate())
    except Exception:
        return None


def compute_durations(scenes, voice_dir, ep):
    """scene順の尺(秒)リストを返す。voice優先→est_seconds。最低1.5秒。"""
    durs = []
    for sc in scenes:
        wav = os.path.join(voice_dir, f"EP{ep:02d}_{sc['scene_id']}_NARRATION_V01.wav")
        d = wav_duration(wav) if os.path.exists(wav) else None
        if d is None:
            d = float(sc.get("est_seconds", 4.0))
        durs.append(max(1.5, round(d, 2)))
    return durs


def _ts(sec):
    h = int(sec // 3600); sec -= h * 3600
    m = int(sec // 60); sec -= m * 60
    s = int(sec); ms = int(round((sec - s) * 1000))
    if ms == 1000:
        s += 1; ms = 0
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def write_srt(scenes, durations, out_path):
    lines = []
    t = 0.0
    for i, (sc, dur) in enumerate(zip(scenes, durations), start=1):
        start, end = t, t + dur
        lines.append(str(i))
        lines.append(f"{_ts(start)} --> {_ts(end)}")
        lines.append(sc["narration"])
        lines.append("")
        t = end
    with open(out_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    return out_path, t  # 総尺も返す
