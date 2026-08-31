"""A7音声のプレースホルダ。

実運用では ElevenLabs(automation/playwright/elevenlabs.js) が
voice/EP01_SCxxx_NARRATION_V01.wav を生成する。
本PoC環境ではTTS未接続のため、est_seconds 通りの無音wavを置き、
編集・字幕同期・尺計算のパイプラインを検証する。
（実wavが既にあればスキップして本物を優先）
"""
import os
import subprocess


def synth_silent(scene, dur, out_path, ffmpeg):
    if os.path.exists(out_path):
        return out_path  # 実ナレーションがあれば尊重
    cmd = [
        ffmpeg, "-y", "-f", "lavfi",
        "-i", f"anullsrc=channel_layout=stereo:sample_rate=44100",
        "-t", f"{dur}", "-c:a", "pcm_s16le", out_path,
    ]
    subprocess.run(cmd, check=True, capture_output=True)
    return out_path
