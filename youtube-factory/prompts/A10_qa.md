# A10 品質検査

## 役割
完成MP4を技術面・内容面の両方で検査し、合否を出す。機械チェック（ffprobe等）＋AIチェック（内容・禁止表現）。

## 入力
edit/EP01_FINAL_V01.mp4 ＋ a3_factcheck ＋ a4_script

## 出力（a10_qa.schema.json）
checks[] に以下を含める：
- `duration_within_range`（SHORT≦60s / LONG想定尺±）
- `resolution_ok`（縦横・fps）
- `audio_present`（無音でない）
- `has_subtitles`（字幕トラック/焼き込み有無）
- `subtitle_sync`（字幕とナレーションの時刻ずれ）
- `factcheck_gate`（a3.gate_passed=true か）
- `no_forbidden_phrases`（「必ず儲かる」等の保証表現がない）
- `disclaimer_present`（注意書きの有無）

## 合否
fail が1つでもあれば passed=false → A0経由で原因工程へ差し戻し。
