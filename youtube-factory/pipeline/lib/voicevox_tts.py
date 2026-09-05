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
  python3 pipeline/lib/voicevox_tts.py --ep 1 --speaker-name 青山龍星
  python3 pipeline/lib/voicevox_tts.py --ep 1 --speaker-name 青山龍星 --style ノーマル
  python3 pipeline/lib/voicevox_tts.py --ep 1 --speaker 13   # idを直接指定する場合

speaker idはVOICEVOXのバージョンによってズレることがあるため、
IDの丸暗記ではなく --speaker-name（＋任意で --style）での指定を推奨する。
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


def _post(url, data=None, timeout=30, json_body=False):
    req = urllib.request.Request(url, data=data, method="POST")
    if json_body:
        req.add_header("Content-Type", "application/json")
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


def resolve_speaker_id(name: str, style: str = None, base_url: str = DEFAULT_BASE_URL) -> int:
    """話者名(例:'青山龍星')からspeaker idを引く。

    speaker idはVOICEVOXのバージョン更新でズレることがあるため、
    IDを決め打ちせず毎回 /speakers から名前で解決する。styleを
    指定しない場合は「ノーマル」を優先し、無ければ最初に見つかった
    スタイルを使う。
    """
    candidates = [sp for sp in list_speakers(base_url) if sp["name"] == name]
    if not candidates:
        all_names = sorted({sp["name"] for sp in list_speakers(base_url)})
        raise ValueError(
            f"話者 '{name}' が見つかりません。--list-speakers で確認してください。"
            f"\n利用可能な話者: {', '.join(all_names)}"
        )
    if style:
        for sp in candidates:
            if sp["style"] == style:
                return sp["id"]
        styles = [sp["style"] for sp in candidates]
        raise ValueError(f"話者 '{name}' に style '{style}' がありません。利用可能: {styles}")
    for sp in candidates:
        if sp["style"] == "ノーマル":
            return sp["id"]
    return candidates[0]["id"]


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
    wav = _post(f"{base_url}/synthesis?{q2.decode()}", data=query_json, json_body=True)
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
    ap.add_argument("--speaker", type=int, help="使用する speaker id を直接指定する場合")
    ap.add_argument("--speaker-name", help="話者名で指定する場合（例: 青山龍星）。推奨。")
    ap.add_argument("--style", help="--speaker-name と併用。スタイル名（例: ノーマル）。省略時はノーマル優先。")
    a = ap.parse_args()

    if a.list_speakers:
        for sp in list_speakers(a.base_url):
            print(f"id={sp['id']:>4}  {sp['name']} / {sp['style']}")
        return

    if a.speaker is not None:
        speaker_id = a.speaker
    elif a.speaker_name:
        speaker_id = resolve_speaker_id(a.speaker_name, a.style, a.base_url)
        print(f"'{a.speaker_name}'" + (f"({a.style})" if a.style else "") + f" -> speaker id={speaker_id}")
    else:
        print("エラー: --speaker-name <名前> または --speaker <id> を指定してください"
              "（--list-speakers で確認できます）")
        sys.exit(1)

    generate_episode(a.ep, speaker_id, a.base_url)


if __name__ == "__main__":
    main()
