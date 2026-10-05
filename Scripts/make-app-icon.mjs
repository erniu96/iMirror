// Renders Resources/AppIcon.svg into Resources/AppIcon.icns.
// Requires Node and Playwright with Chromium: npm install playwright && npx playwright install chromium
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { createRequire } from 'node:module';

const projectDir = join(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(join(process.cwd(), 'noop.js'));
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');

// ICNS element types and their pixel sizes (PNG payloads, macOS 10.7+).
const entries = [
  ['icp4', 16], ['icp5', 32], ['ic11', 32], ['icp6', 64], ['ic12', 64],
  ['ic07', 128], ['ic08', 256], ['ic13', 256], ['ic09', 512], ['ic14', 512], ['ic10', 1024],
];

const svg = readFileSync(join(projectDir, 'Resources/AppIcon.svg'));
const source = `data:image/svg+xml;base64,${svg.toString('base64')}`;
const browser = await chromium.launch();
const rendered = new Map();
for (const size of new Set(entries.map(([, size]) => size))) {
  const page = await browser.newPage({ viewport: { width: size, height: size } });
  await page.setContent(
    `<body style="margin:0;background:transparent"><img src="${source}" width="${size}" height="${size}" style="display:block"></body>`,
  );
  await page.locator('img').evaluate((image) => image.decode());
  rendered.set(size, await page.screenshot({ omitBackground: true }));
  await page.close();
}
await browser.close();

const chunks = entries.map(([type, size]) => {
  const png = rendered.get(size);
  const header = Buffer.alloc(8);
  header.write(type, 0, 'ascii');
  header.writeUInt32BE(png.length + 8, 4);
  return Buffer.concat([header, png]);
});
const body = Buffer.concat(chunks);
const header = Buffer.alloc(8);
header.write('icns', 0, 'ascii');
header.writeUInt32BE(body.length + 8, 4);
writeFileSync(join(projectDir, 'Resources/AppIcon.icns'), Buffer.concat([header, body]));
console.log('Resources/AppIcon.icns');
