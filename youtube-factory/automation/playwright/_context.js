// 永続プロファイルでブラウザを起動する共通関数。
// ログイン状態を profiles/<service>/ に保持し、毎回のログインを避ける。
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');

async function launchPersistent(profileDir, { headless = false } = {}) {
  const dir = path.resolve(profileDir);
  fs.mkdirSync(dir, { recursive: true });
  // channel:'chrome' で実Chromeを使う（bot検知対策・実ログイン流用）
  const ctx = await chromium.launchPersistentContext(dir, {
    headless,
    channel: 'chrome',
    viewport: { width: 1440, height: 900 },
    args: ['--disable-blink-features=AutomationControlled'],
  });
  return ctx;
}

// UI変更に強くするための緩いクリック（複数セレクタを順に試す）
async function clickAny(page, selectors, timeout = 8000) {
  for (const sel of selectors) {
    const el = page.locator(sel).first();
    try {
      await el.waitFor({ state: 'visible', timeout });
      await el.click();
      return sel;
    } catch (_) { /* 次の候補へ */ }
  }
  throw new Error('clickAny: どのセレクタも見つかりません: ' + selectors.join(' | '));
}

async function shot(page, label) {
  const dir = path.resolve(__dirname, '../../logs');
  fs.mkdirSync(dir, { recursive: true });
  const p = path.join(dir, `${Date.now()}_${label}.png`);
  await page.screenshot({ path: p, fullPage: false });
  return p;
}

module.exports = { launchPersistent, clickAny, shot };
