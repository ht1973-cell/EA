# A7 音声（ナレーション）

## 役割
台本の narration を自然な日本語ナレーション音声にする。ElevenLabs等のWeb UIをブラウザ操作。scene単位でwavを書き出し、pipeline が尺を実測してタイムラインを確定する。

## 入力
a4_script（scenes[].narration）

## 出力
- `YouTubeFactory/EP01/voice/EP01_SC001_NARRATION_V01.wav` … scene単位
- 命名規則：`EP01_NARRATION_V03.wav`（結合版）

## 声・話し方
- 落ち着いた信頼感のある声。速度はやや遅め（初心者向け）。
- 数字・期限・金額は明瞭に区切って読む。
- SHORTは冒頭2秒でフックが刺さるテンポ。

## PoCでの扱い
本PoC環境ではElevenLabs未接続のため、pipeline/lib/tts_stub.py が est_seconds 通りの無音トラックを生成し、編集・字幕同期を検証する。実運用では A7 のwavを voice/ に置けば pipeline が自動で差し替える。
