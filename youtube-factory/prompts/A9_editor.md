# A9 編集

## 役割
映像・ナレーション・字幕・BGM・効果音を FFmpeg で統合し最終MP4を書き出す。ローカル完結（APIレスで最も確実な工程）。pipeline/lib/assemble.py が実装。

## 入力
- video/（scene素材 or 図解スライド）
- voice/（ナレーションwav。無ければ tts_stub）
- subtitle/（SRT）

## 出力
- `YouTubeFactory/EP01/edit/EP01_FINAL_V01.mp4`

## 仕様
- SHORT=1080x1920 30fps、LONG=1920x1080 30fps
- 音量ノーマライズ（-14 LUFS目安）、字幕焼き込み or ソフト字幕
- 各sceneの表示尺 = ナレーション実測尺（無ければ est_seconds）
- BGMは-24〜-28dBでダッキング

## 命名規則
`EP01_FINAL_V05.mp4`（Vは版数）
