# ② n8n ワークフロー設計

n8n を制作工場の**司令塔**にする。スケジュール／分岐／再試行／ファイル監視／状態管理／通知を担当し、各AI・ローカル処理は `Execute Command` で `pipeline/` と `automation/` を叩く（APIレス）。

## ワークフロー分割（推奨構成）

| WF | 名前 | トリガー | 役割 |
|----|------|----------|------|
| WF-1 | EP制作パイプライン | 手動 / スケジュール | 本体（調査→ゲート→編集→QA→承認→予約投稿直前）。`n8n/wf_ep01_pipeline.json` |
| WF-2 | 企画キュー投入 | 週次cron | Notion 52本DBから次のJob(Phase内)を選び WF-1 を起動 |
| WF-3 | 承認Webhook | Webhook | 承認URLのPOSTで WF-1 の Wait を再開＋`human_approval`をtrue化 |
| WF-4 | 公開後分析 | 日次cron | A12：Studio実績をNotion Jobへ書き戻し→改善ルール生成 |

## WF-1 のノード（インポート済JSON）
1. 手動トリガー → 2. 設定(EP番号) → 3. **A2調査**(`run_ep01.py --stage research`)
4. **A3事実監査** → 5. IF **ファクトゲート通過?**（false→差し戻し）
6. **A4-A9 台本→字幕→スライド→編集**(`--stage build`) → 7. **A10 QA**(`--stage qa`)
8. IF **QA合格?**（false→差し戻し） → 9. **人間承認ゲート(Wait/webhook)**
10. **A11 公開メタ生成**(`--stage publish_prep --approved-by ...`)
11. **A11 予約投稿(DRY_RUN)**(`youtube_studio_upload.js`)

各 Execute Command は stdout に JSON を返すので、後続 IF は `JSON.parse($json.stdout).gate_passed` 等で分岐する。

## 状態管理（Notion連携）
- 各ノード完了時に Notion「YouTube制作Jobs」の該当列（調査/ファクトチェック/映像/音声/編集/サムネ/QA/承認）を更新するサブフロー（HTTP Request → Notion API、または Notionノード）を挟むと、DBが制作状況のダッシュボードになる。
- 失敗・差し戻しは Slack/メール通知ノードで担当へ。

## 再試行・監視
- Execute Command は `Retry On Fail`（回数・待機）を有効化。
- ブラウザ操作系はタイムアウト長め＋失敗時スクショ（`logs/`）。
- 同一工程 revision が3回超で `blocked`（A0ルール）→人間へエスカレーション。

## 環境変数（n8n側）
`FACTORY_ROOT` を設定し、コマンドを `python3 $env.FACTORY_ROOT/pipeline/run_ep01.py ...` の形で参照（JSON内で使用済）。
