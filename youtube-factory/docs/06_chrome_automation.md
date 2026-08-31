# ⑥ Chrome / Playwright 自動操作

APIレス方針（設計書§5）のため、AIサービスとYouTube Studioは**ブラウザ自動操作**で連携する。

## 方針と前提
- **永続プロファイル**（`profiles\<service>\`）でログイン状態を保持し、毎回のログインを避ける。
- 各サービスの**利用規約・自動化制限・bot検知**に従う。規約で自動化が禁止される操作はしない。
- 完全無人の公開は保証しない。**公開直前に人間承認ゲート**を置く（§11）。
- UI変更に弱いので、セレクタは `data-testid` 優先＋フォールバック、失敗時はスクショを `logs\` に残す。
- 秘匿情報（Cookie/プロファイル）はGit管理外。

## 構成
```
automation/playwright/
├─ package.json
├─ _context.js        永続プロファイルでブラウザ起動する共通関数
├─ chatgpt.js         A0-A5相当のテキスト生成をWeb UIで実行（任意）
├─ elevenlabs.js      A7 ナレーション生成→wavダウンロード
└─ youtube_studio_upload.js  A11 アップロード＋予約公開（承認ゲート付き）
```

## 実行例
```bash
cd automation/playwright
npm install
# ナレーション生成（scriptのnarrationを読み上げ）
node elevenlabs.js --ep 1 --profile ../../profiles/elevenlabs
# YouTubeアップロード（DRY_RUN=1なら実アップロードせず手順検証のみ）
DRY_RUN=1 node youtube_studio_upload.js --meta ../../YouTubeFactory/EP01/publish/publish_metadata.json
```

## 安全設計（youtube_studio_upload.js）
1. `publish_metadata.json` を読み、`human_approval.approved !== true` なら**即中断**。
2. `DRY_RUN=1`（既定）では、フォーム入力の直前で停止しスクショだけ保存 → 「予約投稿直前」を再現。
3. `DRY_RUN=0` かつ承認済のときのみ、実際に公開設定まで進む。
4. アップロード後、確定したURLを標準出力に返す（n8nがNotionへ書き戻す）。

## n8nからの呼び出し
n8nの `Execute Command` ノードで上記 `node ...` を実行し、stdout(JSON)を次ノードへ渡す。詳細は `docs/02` / `n8n/wf_ep01_pipeline.json`。
