// Renders Resources/AppIcon.svg into Resources/AppIcon.icns (macOS 14 and 15) and
// the full-bleed layer of the Icon Composer icon Resources/AppIcon.icon (macOS 26+,
// which otherwise shrinks a legacy icon into a gray tile).
// Requires Node and Playwright with Chromium: npm install playwright && npx playwright install chromium
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
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

// Icon Composer layer: the same artwork filling the whole 1024 square, without
// the rounded corners or shadow; the system applies its own shape and effects.
// The tile spans 100…924, so scale it up by 1024 / 824 around that origin.
const fullBleed = svg.toString()
  .replace('rx="185"', 'rx="0"')
  .replace('<g filter="url(#iconShadow)">', '<g>')
  .replace(/(<\/defs>)([\s\S]*)(<\/svg>\s*)$/, `$1<g transform="scale(${1024 / 824}) translate(-100,-100)">$2</g>$3`);
const page = await browser.newPage({ viewport: { width: 1024, height: 1024 } });
await page.setContent(
  `<body style="margin:0"><img src="data:image/svg+xml;base64,${Buffer.from(fullBleed).toString('base64')}" width="1024" height="1024" style="display:block"></body>`,
);
await page.locator('img').evaluate((image) => image.decode());
const layerDir = join(projectDir, 'Resources/AppIcon.icon/Assets');
mkdirSync(layerDir, { recursive: true });
writeFileSync(join(layerDir, 'AppIcon-art.png'), await page.screenshot());
console.log('Resources/AppIcon.icon/Assets/AppIcon-art.png');
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
