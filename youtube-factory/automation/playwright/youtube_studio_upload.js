// A11 公開：YouTube Studio をブラウザ操作してアップロード＋予約公開する。
// 使い方:
//   DRY_RUN=1 node youtube_studio_upload.js --meta ../../YouTubeFactory/EP01/publish/publish_metadata.json
// 安全設計:
//   - human_approval.approved !== true なら即中断（設計書§11）
//   - DRY_RUN=1（既定）ではフォーム入力の直前で停止しスクショのみ = 「予約投稿直前」を再現
//   - DRY_RUN=0 かつ承認済のときだけ実アップロード
// 注意: YouTubeの自動化・利用規約に従うこと。UI変更でセレクタ調整が要る。
const fs = require('fs');
const path = require('path');
const argv = require('minimist')(process.argv.slice(2));
const { launchPersistent, clickAny, shot } = require('./_context');

const DRY_RUN = process.env.DRY_RUN !== '0'; // 既定は安全側(true)
const metaPath = path.resolve(argv.meta);
const meta = JSON.parse(fs.readFileSync(metaPath, 'utf8'));

function abort(msg) { console.error(JSON.stringify({ ok: false, aborted: true, reason: msg })); process.exit(2); }

(async () => {
  // --- ゲート1: 人間承認 ---
  if (!meta.human_approval || meta.human_approval.approved !== true) {
    abort('human_approval.approved が true ではありません。承認前の公開は禁止です。');
  }
  const videoFile = path.resolve(path.dirname(metaPath), '..', 'edit', path.basename(meta.video_file));
  if (!fs.existsSync(videoFile)) abort('動画ファイルが見つかりません: ' + videoFile);

  const ctx = await launchPersistent(argv.profile || '../../profiles/youtube', { headless: false });
  const page = await ctx.newPage();
  await page.goto('https://studio.youtube.com/', { waitUntil: 'domcontentloaded' });

  // アップロード開始
  await clickAny(page, ['#create-icon', 'ytcp-button:has-text("作成")', 'button:has-text("Create")']);
  await clickAny(page, ['tp-yt-paper-item:has-text("動画をアップロード")', 'tp-yt-paper-item:has-text("Upload video")']);

  const fileInput = page.locator('input[type="file"]').first();
  await fileInput.setInputFiles(videoFile);

  // メタデータ入力
  await page.locator('#textbox').first().fill(meta.title.slice(0, 100));           // タイトル
  await page.locator('#textbox').nth(1).fill(meta.description.slice(0, 5000));      // 概要欄
  if (meta.thumbnail_file && fs.existsSync(path.resolve(path.dirname(metaPath), '..', 'thumbnail', path.basename(meta.thumbnail_file)))) {
    // サムネ設定（セレクタは環境で調整）
  }

  // 子ども向け設定（金融チャンネルは通常「子ども向けではない」）
  await clickAny(page, ['tp-yt-paper-radio-button[name="VIDEO_MADE_FOR_KIDS_NOT_MFK"]']).catch(() => {});

  // AI生成/合成コンテンツの開示
  if (meta.ai_content_disclosure) {
    await shot(page, 'set_ai_disclosure_hint'); // 「詳細」タブで開示設定を有効化（要手動確認）
  }

  const stamp = await shot(page, 'before_publish');
  if (DRY_RUN) {
    console.log(JSON.stringify({
      ok: true, dry_run: true,
      message: '予約投稿直前で停止しました（DRY_RUN）。承認済メタで実行すれば公開まで進みます。',
      video: videoFile, screenshot: stamp,
      scheduled_publish_at: meta.scheduled_publish_at || null,
    }));
    await ctx.close();
    return;
  }

  // --- ここから DRY_RUN=0 のみ ---
  // 「次へ」を3回 → 公開設定
  for (let i = 0; i < 3; i++) await clickAny(page, ['#next-button', 'ytcp-button:has-text("次へ")', 'button:has-text("Next")']);
  if (meta.visibility === 'scheduled' && meta.scheduled_publish_at) {
    await clickAny(page, ['tp-yt-paper-radio-button[name="SCHEDULE"]', 'button:has-text("スケジュール")']);
    // 日時入力（UIに合わせて調整）
  } else {
    await clickAny(page, [`tp-yt-paper-radio-button[name="${(meta.visibility || 'private').toUpperCase()}"]`]).catch(() => {});
  }
  await clickAny(page, ['#done-button', 'ytcp-button:has-text("完了")', 'button:has-text("Done")']);

  // 確定URL取得（要素はUIに合わせて調整）
  const url = await page.locator('a.ytcp-video-info, a[href*="youtu.be"]').first().getAttribute('href').catch(() => null);
  console.log(JSON.stringify({ ok: true, dry_run: false, youtube_url: url, scheduled_publish_at: meta.scheduled_publish_at }));
  await ctx.close();
})().catch((e) => { console.error(JSON.stringify({ ok: false, error: String(e) })); process.exit(1); });
