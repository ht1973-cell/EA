// A7 音声：台本 narration を ElevenLabs Web UI で読み上げ、scene単位のwavを保存する。
// 使い方: node elevenlabs.js --ep 1 --profile ../../profiles/elevenlabs
// 注意: ElevenLabsの利用規約・自動化制限に従うこと。UIは変わりうるためセレクタは要調整。
const fs = require('fs');
const path = require('path');
const argv = require('minimist')(process.argv.slice(2));
const { launchPersistent, clickAny, shot } = require('./_context');

const EP = String(argv.ep || 1).padStart(2, '0');
const ROOT = path.resolve(__dirname, '../../YouTubeFactory/EP' + EP);
const scriptPath = path.join(ROOT, 'script', `EP${EP}_a4_script.json`);
const voiceDir = path.join(ROOT, 'voice');

(async () => {
  const script = JSON.parse(fs.readFileSync(scriptPath, 'utf8')).payload || JSON.parse(fs.readFileSync(scriptPath, 'utf8'));
  fs.mkdirSync(voiceDir, { recursive: true });
  const ctx = await launchPersistent(argv.profile || '../../profiles/elevenlabs', { headless: false });
  const page = await ctx.newPage();
  await page.goto('https://elevenlabs.io/app/speech-synthesis', { waitUntil: 'domcontentloaded' });

  for (const sc of script.scenes) {
    const outWav = path.join(voiceDir, `EP${EP}_${sc.scene_id}_NARRATION_V01.wav`);
    try {
      // 1) テキスト入力欄へ narration を入力
      const box = page.locator('textarea, [contenteditable="true"]').first();
      await box.waitFor({ state: 'visible', timeout: 15000 });
      await box.fill(sc.narration);
      // 2) 生成ボタン
      await clickAny(page, ['button:has-text("Generate")', 'button:has-text("生成")', '[data-testid="generate"]']);
      // 3) ダウンロード（生成完了を待ってからDL）
      const [download] = await Promise.all([
        page.waitForEvent('download', { timeout: 120000 }),
        clickAny(page, ['button:has-text("Download")', 'button[aria-label="Download"]', '[data-testid="download"]']),
      ]);
      await download.saveAs(outWav);
      console.log(JSON.stringify({ scene: sc.scene_id, wav: outWav, ok: true }));
    } catch (e) {
      const s = await shot(page, `elevenlabs_${sc.scene_id}_err`);
      console.error(JSON.stringify({ scene: sc.scene_id, ok: false, error: String(e), screenshot: s }));
    }
  }
  await ctx.close();
})();
