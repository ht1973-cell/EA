#!/usr/bin/env python3
"""EP01 完全自動制作パイプライン（PoC）— YouTube予約投稿『直前』まで。

工程（設計書のA2〜A11に対応）:
  research     : A2調査 + A3事実監査 → a2_research.json / a3_factcheck.json（ゲート）
  factcheck    : ゲート結果だけ再出力（n8nのIF分岐用）
  build        : A4台本→A7音声(無音stub)→字幕SRT→A5/A6スライド→A9編集 → EP01_FINAL_V01.mp4 + サムネ
  qa           : A10品質検査 → a10_qa.json（passed）
  publish_prep : A11公開メタ生成（人間承認を反映）→ publish_metadata.json
  all          : 上記を順に実行（承認は --approved-by で付与、無指定なら承認前=公開しない）

使い方:
  python3 run_ep01.py --stage all --ep 1
  python3 run_ep01.py --stage all --ep 1 --approved-by "you@example.com"
"""
import argparse
import json
import os
import subprocess
import sys
from datetime import datetime, timezone, timedelta

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)                       # youtube-factory/
sys.path.insert(0, os.path.join(HERE, "lib"))
import factcheck, slides, subtitles, tts_stub, assemble, tts_lint   # noqa: E402

JST = timezone(timedelta(hours=9))


def ffmpeg_bin():
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:
        return os.environ.get("FFMPEG", "ffmpeg")


def job_dir(ep):
    d = os.path.join(ROOT, "YouTubeFactory", f"EP{ep:02d}")
    for sub in ["research", "script", "voice", "video", "thumbnail", "subtitle", "edit", "qa", "publish"]:
        os.makedirs(os.path.join(d, sub), exist_ok=True)
    return d


def wav_is_real_narration(wav, ffmpeg, silence_threshold_db=-45.0):
    """A7の無音stub(プレースホルダ)か、Higgsfield等の実ナレーションかを判定する。

    stubはanullsrcで生成した完全な無音のため、ffmpegのvolumedetectで
    最大音量がほぼ-∞dBになる。実音声はしゃべり声の分だけ十分な音量を持つ
    ため、閾値を超えていれば「検査対象の実音声」とみなす。
    """
    try:
        r = subprocess.run([ffmpeg, "-i", wav, "-af", "volumedetect", "-f", "null", "-"],
                          capture_output=True, text=True)
        for line in r.stderr.splitlines():
            if "max_volume:" in line:
                val = line.split("max_volume:")[1].strip().split(" ")[0]
                return float(val) > silence_threshold_db
    except Exception:
        pass
    return False


def load_script(ep):
    p = os.path.join(HERE, "ep01", f"ep{ep:02d}_a4_script.json")
    with open(p, encoding="utf-8") as f:
        return json.load(f)


# ---------- stages ----------
def stage_research(ep):
    jd = job_dir(ep)
    fc = factcheck.run(ep, os.path.join(jd, "research"))
    print(json.dumps({"stage": "research", "gate_passed": fc["gate_passed"],
                      "claims": len(fc["claims"])}, ensure_ascii=False))
    return fc["gate_passed"]


def stage_factcheck(ep):
    jd = job_dir(ep)
    p = os.path.join(jd, "research", f"EP{ep:02d}_a3_factcheck.json")
    if not os.path.exists(p):
        return stage_research(ep)
    fc = json.load(open(p, encoding="utf-8"))
    print(json.dumps({"stage": "factcheck", "gate_passed": fc["gate_passed"]}, ensure_ascii=False))
    return fc["gate_passed"]


def stage_build(ep):
    jd = job_dir(ep)
    ff = ffmpeg_bin()
    doc = load_script(ep)
    pl = doc["payload"]
    scenes = pl["scenes"]
    size = (pl["resolution"]["w"], pl["resolution"]["h"])

    # A4: 台本を script/ に保存
    with open(os.path.join(jd, "script", f"EP{ep:02d}_a4_script.json"), "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, indent=2)

    # A4品質ゲート: narration(表示用)からtts_prompt(合成用の開き読み)を
    # 自動生成する。数字の誤読(「十八」→『じゅうばち』等)や専門用語の誤読
    # (「貯金」→『じょきん』等)を、人手の目視チェックに頼らず構造的に防ぐ。
    for sc in scenes:
        if not sc.get("tts_prompt"):
            sc["tts_prompt"] = tts_lint.build_tts_prompt(sc["narration"])

    # 尺（voice優先→est_seconds）
    voice_dir = os.path.join(jd, "voice")
    durations = subtitles.compute_durations(scenes, voice_dir, ep)

    # A7: 音声（無音stub。実wavがあれば尊重）
    voice_paths = []
    for sc, dur in zip(scenes, durations):
        wav = os.path.join(voice_dir, f"EP{ep:02d}_{sc['scene_id']}_NARRATION_V01.wav")
        tts_stub.synth_silent(sc, dur, wav, ff)
        voice_paths.append(wav)
    # 実音声を使った場合の再計測
    durations = subtitles.compute_durations(scenes, voice_dir, ep)

    # A10品質ゲート(音声): 実ナレーションが置かれている場合、文字数から
    # 想定される尺と実測尺を突き合わせ、大きく乖離していればノイズ混入・
    # 幻聴的アーティファクト・無音excessの疑いとして検出する。異常があれば
    # ここで build を止め、壊れた音声のまま最終動画に焼き込むことを防ぐ
    # （「ノイズが起きないように成果物を作る」ことを工程として強制する）。
    anomalies = []
    voice_report = []
    for sc, dur in zip(scenes, durations):
        wav = os.path.join(voice_dir, f"EP{ep:02d}_{sc['scene_id']}_NARRATION_V01.wav")
        # 無音stub(プレースホルダ)は検査対象外。実ナレーションのみ検査。
        text_for_check = sc.get("tts_prompt") or sc["narration"]
        is_anom, detail = tts_lint.check_duration_anomaly(text_for_check, dur)
        voice_report.append({"scene_id": sc["scene_id"], "duration_sec": round(dur, 2),
                              "anomaly": is_anom, "detail": detail})
        if is_anom and os.path.exists(wav) and os.path.getsize(wav) > 0:
            # 無音stub(est_secondsそのまま)は異常判定に含めない。
            # 実音声ダウンロード後の再ビルド時のみ有効な検査。
            if wav_is_real_narration(wav, ff):
                anomalies.append((sc["scene_id"], detail))

    os.makedirs(os.path.join(jd, "qa"), exist_ok=True)
    with open(os.path.join(jd, "qa", f"EP{ep:02d}_voice_anomaly_report.json"), "w", encoding="utf-8") as f:
        json.dump({"ep": ep, "checked_at": datetime.now(JST).isoformat(),
                   "scenes": voice_report, "anomalies": [a[0] for a in anomalies]},
                  f, ensure_ascii=False, indent=2)

    if anomalies:
        detail_lines = "\n".join(f"  - {sid}: {detail}" for sid, detail in anomalies)
        raise RuntimeError(
            "音声の異常検知でNGになったシーンがあります。ノイズ混入・幻聴的\n"
            "アーティファクト・読み飛ばしの疑いがあるため、最終動画への焼き込みを\n"
            "停止しました。該当シーンの音声を再生成してから再度buildしてください:\n"
            + detail_lines
        )

    # 字幕SRT
    srt = os.path.join(jd, "subtitle", f"EP{ep:02d}.srt")
    _, total = subtitles.write_srt(scenes, durations, srt)

    # A5/A6: スライド生成（図解フォールバック）
    slide_paths = []
    for i, sc in enumerate(scenes, start=1):
        png = os.path.join(jd, "video", f"EP{ep:02d}_{sc['scene_id']}_V01.png")
        slides.render_scene(sc, size, png, ep, len(scenes), i)
        slide_paths.append(png)

    # A8: サムネ
    thumb = os.path.join(jd, "thumbnail", f"EP{ep:02d}_THUMB_V01.png")
    slides.render_thumbnail(pl["title"], thumb)

    # A9: 編集
    out = os.path.join(jd, "edit", f"EP{ep:02d}_FINAL_V01.mp4")
    assemble.build(scenes, durations, slide_paths, voice_paths, srt, size, out, ff,
                   os.path.join(jd, "edit", "_work"))

    print(json.dumps({"stage": "build", "final": out, "duration_sec": round(total, 1),
                      "scenes": len(scenes), "thumbnail": thumb}, ensure_ascii=False))
    return out


def _probe(ff, mp4):
    """ffprobe無しでffmpegのstderrから情報抽出。"""
    r = subprocess.run([ff, "-i", mp4], capture_output=True, text=True)
    s = r.stderr
    info = {"has_video": "Video:" in s, "has_audio": "Audio:" in s, "has_sub": "Subtitle:" in s}
    # Duration: 00:00:33.02
    dur = None
    for line in s.splitlines():
        if "Duration:" in line:
            t = line.split("Duration:")[1].split(",")[0].strip()
            try:
                h, m, sec = t.split(":")
                dur = int(h) * 3600 + int(m) * 60 + float(sec)
            except Exception:
                pass
    info["duration"] = dur
    # resolution e.g. 1080x1920
    import re
    mo = re.search(r"(\d{3,4})x(\d{3,4})", s)
    info["resolution"] = f"{mo.group(1)}x{mo.group(2)}" if mo else None
    return info


def stage_qa(ep):
    jd = job_dir(ep)
    ff = ffmpeg_bin()
    doc = load_script(ep); pl = doc["payload"]
    mp4 = os.path.join(jd, "edit", f"EP{ep:02d}_FINAL_V01.mp4")
    fc = json.load(open(os.path.join(jd, "research", f"EP{ep:02d}_a3_factcheck.json"), encoding="utf-8"))
    info = _probe(ff, mp4)
    W, H = pl["resolution"]["w"], pl["resolution"]["h"]
    is_short = pl["video_type"] == "SHORT"

    forbidden = ["必ず儲かる", "絶対に儲かる", "元本保証", "確実に増える"]
    text_all = " ".join(s["narration"] + s["telop"] for s in pl["scenes"])
    has_forbidden = any(w in text_all for w in forbidden)

    voice_report_path = os.path.join(jd, "qa", f"EP{ep:02d}_voice_anomaly_report.json")
    voice_anomaly_ok = True
    voice_anomaly_detail = "レポート未生成(build未実行)"
    if os.path.exists(voice_report_path):
        vr = json.load(open(voice_report_path, encoding="utf-8"))
        voice_anomaly_ok = len(vr.get("anomalies", [])) == 0
        voice_anomaly_detail = (f"異常なし({len(vr['scenes'])}シーン検査)" if voice_anomaly_ok
                                else f"異常検知: {vr['anomalies']}")

    checks = [
        {"name": "video_exists", "result": "pass" if os.path.exists(mp4) and os.path.getsize(mp4) > 0 else "fail",
         "detail": f"{os.path.getsize(mp4) if os.path.exists(mp4) else 0} bytes"},
        {"name": "has_video_stream", "result": "pass" if info["has_video"] else "fail"},
        {"name": "audio_present", "result": "pass" if info["has_audio"] else "fail",
         "detail": "PoCは無音stub（本番はElevenLabs音声）"},
        {"name": "has_subtitles", "result": "pass" if info["has_sub"] else "warn",
         "detail": "mov_textソフト字幕"},
        {"name": "resolution_ok", "result": "pass" if info["resolution"] == f"{W}x{H}" else "warn",
         "detail": str(info["resolution"])},
        {"name": "duration_within_range",
         "result": "pass" if (info["duration"] and (info["duration"] <= 60 if is_short else info["duration"] > 60)) else "warn",
         "detail": f"{info['duration']}s (SHORT<=60)"},
        {"name": "factcheck_gate", "result": "pass" if fc["gate_passed"] else "fail"},
        {"name": "no_forbidden_phrases", "result": "fail" if has_forbidden else "pass"},
        {"name": "disclaimer_present", "result": "pass" if pl.get("disclaimer") else "fail"},
        {"name": "voice_anomaly_check", "result": "pass" if voice_anomaly_ok else "fail",
         "detail": voice_anomaly_detail},
    ]
    passed = all(c["result"] != "fail" for c in checks)
    qa = {"ep": ep, "checked_at": datetime.now(JST).isoformat(), "passed": passed,
          "checks": checks, "final_video": mp4}
    with open(os.path.join(jd, "qa", f"EP{ep:02d}_a10_qa.json"), "w", encoding="utf-8") as f:
        json.dump(qa, f, ensure_ascii=False, indent=2)
    print(json.dumps({"stage": "qa", "passed": passed,
                      "fails": [c["name"] for c in checks if c["result"] == "fail"]}, ensure_ascii=False))
    return passed


def stage_publish_prep(ep, approved_by=None):
    jd = job_dir(ep)
    doc = load_script(ep); pl = doc["payload"]
    mp4 = os.path.join(jd, "edit", f"EP{ep:02d}_FINAL_V01.mp4")
    thumb = os.path.join(jd, "thumbnail", f"EP{ep:02d}_THUMB_V01.png")
    # 予約公開：翌朝7:00 JST（例）
    sched = (datetime.now(JST) + timedelta(days=1)).replace(hour=7, minute=0, second=0, microsecond=0)
    meta = {
        "ep": ep,
        "video_file": os.path.basename(mp4),
        "thumbnail_file": os.path.basename(thumb),
        "title": pl["title"][:100],
        "description": pl["youtube"]["description"],
        "tags": pl["youtube"]["tags"],
        "playlist": pl["youtube"].get("playlist", ""),
        "visibility": "scheduled",
        "scheduled_publish_at": sched.isoformat(),
        "made_for_kids": pl["youtube"].get("made_for_kids", False),
        "ai_content_disclosure": pl["youtube"].get("ai_content_disclosure", True),
        "human_approval": {
            "approved": bool(approved_by),
            "approved_by": approved_by or None,
            "approved_at": datetime.now(JST).isoformat() if approved_by else None,
        },
    }
    with open(os.path.join(jd, "publish", "publish_metadata.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=2)
    state = "承認済(予約投稿可)" if approved_by else "承認待ち(公開ブロック)"
    print(json.dumps({"stage": "publish_prep", "approval": state,
                      "scheduled_publish_at": meta["scheduled_publish_at"]}, ensure_ascii=False))
    return meta


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stage", required=True,
                    choices=["research", "factcheck", "build", "qa", "publish_prep", "all"])
    ap.add_argument("--ep", type=int, default=1)
    ap.add_argument("--approved-by", default=None)
    a = ap.parse_args()

    if a.stage == "research":
        sys.exit(0 if stage_research(a.ep) else 3)
    if a.stage == "factcheck":
        sys.exit(0 if stage_factcheck(a.ep) else 3)
    if a.stage == "build":
        stage_build(a.ep); return
    if a.stage == "qa":
        sys.exit(0 if stage_qa(a.ep) else 3)
    if a.stage == "publish_prep":
        stage_publish_prep(a.ep, a.approved_by); return
    if a.stage == "all":
        if not stage_research(a.ep):
            print(">> ファクトゲート未通過。A2/A4へ差し戻し。"); sys.exit(3)
        stage_build(a.ep)
        ok = stage_qa(a.ep)
        if not ok:
            print(">> QA不合格。該当工程へ差し戻し。"); sys.exit(3)
        stage_publish_prep(a.ep, a.approved_by)
        print(">> 完了：EP{:02d} は{}。".format(
            a.ep, "予約投稿の実行が可能（承認済）" if a.approved_by else "『予約投稿直前』で人間承認待ち"))


if __name__ == "__main__":
    main()
