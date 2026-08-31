# AI YouTube 自動制作工場 — PoC (EP01)

「顔出しなし お金の失敗検証チャンネル」の全52本を、**企画→調査→ファクトチェック→台本→映像→音声→編集→サムネ→QA→承認→予約公開→分析** で回すAI制作工場。設計方針は Notion「📌 AI YouTube自動制作工場 構築方針・次工程」/「設計書 v1.0」に準拠（**APIレス＝Web UIブラウザ操作＋ローカル処理**、A0〜A12の役割分担、ファクトチェック必須ゲート、公開前 人間承認）。

このリポジトリは **EP01 を『完全自動制作 → YouTube予約投稿 直前』まで実際に通すPoC**。

## 7ステップの対応

| # | 要求 | 実体 |
|---|------|------|
| ① | Notion 52本のDB化 | Notion「YouTube制作Jobs」DB（EP01〜52登録済／全工程ステータス列） |
| ② | n8n 各ワークフロー | `n8n/wf_ep01_pipeline.json`（インポートで動く司令塔） |
| ③ | 各AIのプロンプト定義 | `prompts/A0..A12` |
| ④ | AI間で渡すJSON形式 | `schemas/*.schema.json`（handoff＋各工程） |
| ⑤ | Windows/VPSフォルダ構成 | `docs/05_folder_structure.md` |
| ⑥ | Chrome自動操作 | `docs/06` ＋ `automation/playwright/*`（ElevenLabs / YouTube Studio） |
| ⑦ | EP01を1本作る | `pipeline/`（実行すると実MP4を生成） |

## EP01 PoC を動かす

前提：Python3。FFmpegは `pip install imageio-ffmpeg` の同梱バイナリを自動使用（無ければ `.env` の FFMPEG を使用）。図解描画に Pillow を使用（`pip install Pillow`）。

```bash
cd youtube-factory
pip install Pillow imageio-ffmpeg
# 全工程を一気に（承認なし＝予約投稿直前で停止）
python3 pipeline/run_ep01.py --stage all --ep 1
# 承認を付与すると『予約投稿の実行が可能』な状態のメタを生成
python3 pipeline/run_ep01.py --stage publish_prep --ep 1 --approved-by "you@example.com"
```

### 生成物（`YouTubeFactory/EP01/`）
```
research/  EP01_a2_research.json     出典（一次情報）
           EP01_a3_factcheck.json    ファクトチェック（gate_passed）
script/    EP01_a4_script.json       台本
voice/     EP01_SCxxx_NARRATION.wav  音声（PoCは無音stub＝A7差し替え口）
video/     EP01_SCxxx_V01.png        図解スライド
subtitle/  EP01.srt                  字幕
thumbnail/ EP01_THUMB_V01.png        サムネ
edit/      EP01_FINAL_V01.mp4        ★最終動画（1080x1920 H.264+AAC+字幕）
qa/        EP01_a10_qa.json          品質検査（passed）
publish/   publish_metadata.json     公開メタ（human_approval付き）
```

## 全体フロー（差し戻し付き）
```
Notion Job → A0司令官 → A1企画 → A2調査 → A3事実監査(ゲート)
   └NG→A2へ                                     │OK
A4脚本 → A5演出 → (A6映像 ∥ A7音声) → A9編集 → A8サムネ → A10 QA
                                                   └NG→該当工程へ
→ 人間承認(必須) → A11 YouTube予約公開 → A12分析 → A1次回へ
```

## 実運用への接続点（PoC→本番）
- **A7音声**：`automation/playwright/elevenlabs.js` が実wavを `voice/` に置けば、pipeline が無音stubを自動で差し替える。
- **A6映像**：Veo等の実素材を `video/EP01_SCxxx_V01.mp4` に置けば図解スライドの代わりに使う（assemble拡張点）。
- **A11公開**：`automation/playwright/youtube_studio_upload.js` は `human_approval.approved=true` かつ `DRY_RUN=0` のときだけ実アップロード。既定は「予約投稿直前」で停止。
- **オーケストレーション**：`n8n/wf_ep01_pipeline.json` を n8n にインポートし、各 Execute Command から本pipeline/automationを叩く。

## 品質・法務（金融ゆえ必須）
- A3ファクトチェックが**必須ゲート**。制度・税率・金額・期限・法律の断定は一次情報の裏付けが無ければ公開しない。
- 公開前に**人間承認**を必ず通す。断定的な利益保証・投資助言表現は禁止。
- 詳細は各 `prompts/` と `docs/`、Notion設計書を参照。

## 注意
APIレス（ブラウザ操作）はUI変更に弱く、各サービスの利用規約・自動化制限に従う必要がある。安定運用時は正式APIへの段階移行を検討（設計書§20）。
