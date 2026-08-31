"""A9編集：FFmpegでスライド＋音声＋字幕を統合し最終MP4を出力する。

手順（確実性重視・APIレス）:
  1. sceneごとに [スライドPNG(尺dur) + 音声(実wav or 無音)] のセグメントmp4を作る
  2. concat demuxer で結合
  3. 字幕(SRT)を mov_text ソフト字幕として mux
戻り値: 最終mp4パス
"""
import os
import subprocess


def _run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError("ffmpeg失敗:\n" + " ".join(cmd) + "\n" + r.stderr[-1500:])
    return r


def _vcodec(ffmpeg):
    """libx264が使えるか確認。無ければmpeg4にフォールバック。"""
    r = subprocess.run([ffmpeg, "-hide_banner", "-encoders"], capture_output=True, text=True)
    return "libx264" if "libx264" in r.stdout else "mpeg4"


def build(scenes, durations, slide_paths, voice_paths, srt_path, size, out_path, ffmpeg, work_dir):
    W, H = size
    os.makedirs(work_dir, exist_ok=True)
    vcodec = _vcodec(ffmpeg)
    segs = []
    for i, (sc, dur, png, wav) in enumerate(zip(scenes, durations, slide_paths, voice_paths)):
        seg = os.path.join(work_dir, f"seg_{i:03d}.mp4")
        cmd = [
            ffmpeg, "-y",
            "-loop", "1", "-i", png,
            "-i", wav,
            "-t", f"{dur}",
            "-r", "30",
            "-vf", f"scale={W}:{H}:force_original_aspect_ratio=decrease,pad={W}:{H}:(ow-iw)/2:(oh-ih)/2:color=0x0E1420,format=yuv420p",
            "-c:v", vcodec, "-b:v", "4M",
            "-c:a", "aac", "-ar", "44100", "-ac", "2",
            seg,
        ]
        _run(cmd)
        segs.append(seg)

    # concat
    listfile = os.path.join(work_dir, "concat.txt")
    with open(listfile, "w") as f:
        for s in segs:
            f.write(f"file '{os.path.abspath(s)}'\n")
    combined = os.path.join(work_dir, "combined.mp4")
    _run([ffmpeg, "-y", "-f", "concat", "-safe", "0", "-i", listfile, "-c", "copy", combined])

    # 字幕を mov_text で mux（libass不要で確実）
    try:
        _run([ffmpeg, "-y", "-i", combined, "-i", srt_path,
              "-c", "copy", "-c:s", "mov_text",
              "-metadata:s:s:0", "language=jpn", out_path])
    except RuntimeError:
        # 字幕muxに失敗しても動画は成立させる
        _run([ffmpeg, "-y", "-i", combined, "-c", "copy", out_path])
    return out_path
