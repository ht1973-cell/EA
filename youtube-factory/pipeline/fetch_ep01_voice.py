#!/usr/bin/env python3
"""EP01のHiggsfield生成ナレーション(5シーン)をダウンロードし、
YouTubeFactory/EP01/voice/EP01_SCxxx_NARRATION_V01.wav として配置する。

このクラウド実行環境はegressプロキシがHiggsfieldのCDN(cloudfront)への
通信を許可していないため、ネットワーク制限のないローカル/VPS環境で実行する。

使い方:
  python3 pipeline/fetch_ep01_voice.py

実行後、そのまま以下でEP01を再ビルドできる:
  python3 pipeline/run_ep01.py --stage build --ep 1
  python3 pipeline/run_ep01.py --stage qa --ep 1
"""
import json
import os
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def main():
    cfg_path = os.path.join(HERE, "ep01", "ep01_voice_config.json")
    with open(cfg_path, encoding="utf-8") as f:
        cfg = json.load(f)

    voice_dir = os.path.join(ROOT, "YouTubeFactory", "EP01", "voice")
    os.makedirs(voice_dir, exist_ok=True)

    print(f"声: {cfg['voice_name']} (model={cfg['model']}, speech_rate={cfg['speech_rate']})")
    for sc in cfg["ep01_scenes"]:
        out = os.path.join(voice_dir, f"EP01_{sc['scene_id']}_NARRATION_V01.wav")
        print(f"  {sc['scene_id']} ({sc['duration_sec']:.2f}s) -> {out}")
        urllib.request.urlretrieve(sc["result_url"], out)
    print("完了。次に: python3 pipeline/run_ep01.py --stage build --ep 1")


if __name__ == "__main__":
    sys.exit(main())
