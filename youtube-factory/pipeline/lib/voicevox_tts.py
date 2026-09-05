"""VOICEVOX(ローカルエンジン)を使ったナレーション生成。

VOICEVOXはユーザーのPC上でローカルHTTPサーバーとして動く
(既定 http://127.0.0.1:50021)。日本語専用エンジンのため、MiniMax等の
多言語TTSで確認された「連濁誤変換」（例:十八→じゅうばち）が起きにくい。
さらに読み(カナ)を明示指定して合成するため、狙った発音を確実に再現できる。

無料・ローカル・生成回数無制限。Higgsfieldのクレジット枯渇を気にせず
何度でも試せる。

前提：VOICEVOXアプリを起動しておくこと(起動するとローカルサーバーが立つ)。
このスクリプトは youtube-factory を配置した「ユーザーのPC/VPS環境」で
実行する（このクラウド実行環境からは user のlocalhostへ到達できない）。

使い方:
  python3 pipeline/lib/voicevox_tts.py --list-speakers
  python3 pipeline/lib/voicevox_tts.py --ep 1 --speaker 13
"""
import argparse
import json
import os
import sys
import urllib.request
import urllib.parse

DEFAULT_BASE_URL = "http://127.0.0.1:50021"

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))  # youtube-factory/


def _post(url, data=None, timeout=30):
    req = urllib.request.Request(url, data=data, method="POST")
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def _get(url, timeout=10):
    with urllib.request.urlopen(url, timeout=timeout) as resp:
        return resp.read()


def list_speakers(base_url=DEFAULT_BASE_URL):
    """利用可能な話者(キャラクター)とstyle_idの一覧を取得する。

    VOICEVOXは「キャラクター」ごとに複数の話style(ノーマル/あまあま等)を
    持ち、実際の合成にはstyleごとのid(speaker id)を指定する。
    """
    raw = _get(f"{base_url}/speakers")
    data = json.loads(raw)
    out = []
    for sp in data:
        for style in sp["styles"]:
            out.append({"name": sp["name"], "style": style["name"], "id": style["id"]})
    return out


def synthesize(text: str, speaker_id: int, base_url=DEFAULT_BASE_URL) -> bytes:
    """text(かな/漢字混じり可)をspeaker_idの声でwavバイト列に合成する。

    2段階API: 1) /audio_query で読み・韻律を含むクエリを生成
              2) /synthesis でそのクエリから実際の音声を合成
    tts_lint.pyで作った tts_prompt(既にひらがな化・数字補正済み)を渡せば、
    VOICEVOX側の辞書変換に頼らず、狙った読みでほぼ確実に合成できる。
    """
    q = urllib.parse.urlencode({"text": text, "speaker": speaker_id}).encode()
    query_json = _post(f"{base_url}/audio_query?{q.decode()}")

    q2 = urllib.parse.urlencode({"speaker": speaker_id}).encode()
    wav = _post(f"{base_url}/synthesis?{q2.decode()}", data=query_json)
    return wav


def load_script(ep: int):
    p = os.path.join(HERE, "..", "ep01", f"ep{ep:02d}_a4_script.json")
    with open(p, encoding="utf-8") as f:
        return json.load(f)


def generate_episode(ep: int, speaker_id: int, base_url=DEFAULT_BASE_URL):
    doc = load_script(ep)
    scenes = doc["payload"]["scenes"]
    voice_dir = os.path.join(ROOT, "YouTubeFactory", f"EP{ep:02d}", "voice")
    os.makedirs(voice_dir, exist_ok=True)

    for sc in scenes:
        text = sc.get("tts_prompt") or sc["narration"]
        out = os.path.join(voice_dir, f"EP{ep:02d}_{sc['scene_id']}_NARRATION_V01.wav")
        print(f"生成中: {sc['scene_id']} -> {text}")
        wav = synthesize(text, speaker_id, base_url)
        with open(out, "wb") as f:
            f.write(wav)
        print(f"  保存: {out} ({len(wav)} bytes)")

    print("完了。次に: python3 pipeline/run_ep01.py --stage build --ep", ep)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-url", default=DEFAULT_BASE_URL)
    ap.add_argument("--list-speakers", action="store_true", help="利用可能な話者一覧を表示して終了")
    ap.add_argument("--ep", type=int, default=1)
    ap.add_argument("--speaker", type=int, help="使用する speaker id (--list-speakers で確認)")
    a = ap.parse_args()

    if a.list_speakers:
        for sp in list_speakers(a.base_url):
            print(f"id={sp['id']:>4}  {sp['name']} / {sp['style']}")
        return

    if a.speaker is None:
        print("エラー: --speaker <id> を指定してください（--list-speakers で確認できます）")
        sys.exit(1)

    generate_episode(a.ep, a.speaker, a.base_url)


if __name__ == "__main__":
    main()
