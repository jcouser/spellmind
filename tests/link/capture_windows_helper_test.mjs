// spellmind-capture.exe against test pictures (its --test-image path: no capture API, no game): it
// reads Spellmind's strip at the corner and 272 px down under NeverQuestAlone's, and never reads
// NeverQuestAlone's strip as its own. Windows only, once the helper is built (npm run capture:build).
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { decodePng } from '../helpers/images.mjs';

const require = createRequire(import.meta.url);
const { encodeWithLua, render } = require('../helpers/strip-render.cjs');
const EXE = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..', 'core', 'capture', 'windows', 'build', 'spellmind-capture.exe');
const skip = process.platform !== 'win32' ? 'Windows only' : !fs.existsSync(EXE) ? 'spellmind-capture.exe is not built (npm run capture:build)' : false;
const TEXT = '2\x1f3fa9c2d1\x1fa3f1_7\x1fmsg\x1fc3f9a1e\x1fcur=0\x1fWhich professions suit a Combat rogue?';

function ppm(png) {
  const img = decodePng(png);
  return Buffer.concat([Buffer.from(`P6\n${img.width} ${img.height}\n255\n`, 'ascii'), Buffer.from(img.data.buffer, img.data.byteOffset, img.width * img.height * 3)]);
}

function decode(png) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'sm-capture-'));
  const file = path.join(dir, 'strip.ppm');
  fs.writeFileSync(file, ppm(png));
  const r = spawnSync(EXE, ['--test-image', file], { encoding: 'utf8', timeout: 20000 });
  fs.rmSync(dir, { recursive: true, force: true });
  const lines = r.stdout.trim().split(/\r?\n/).filter(Boolean).map(l => { try { return JSON.parse(l); } catch { return { raw: l }; } });
  return { status: r.status, lines, stderr: r.stderr };
}
const payload = out => out.lines.find(l => typeof l.text === 'string');

test('the helper reads Spellmind\'s strip at the corner', { skip }, () => {
  const out = decode(render(encodeWithLua(42, TEXT), { width: 900, height: 200 }));
  const p = payload(out);
  assert.ok(p, JSON.stringify(out));
  assert.equal(p.text, TEXT);
  assert.equal(p.id, 42);
});

test('the helper reads Spellmind\'s strip 272 px down, under NeverQuestAlone\'s, and ignores NeverQuestAlone\'s alone', { skip }, () => {
  const nqa = encodeWithLua(9, 'not ours', 0x2c, 0xc7);
  const both = decode(render(encodeWithLua(43, TEXT), { width: 900, height: 640, y0: 272, others: [{ cells: nqa, x0: 0, y0: 0 }] }));
  const p = payload(both);
  assert.ok(p, JSON.stringify(both));
  assert.equal(p.text, TEXT);
  const theirs = decode(render(nqa, { width: 900, height: 200 }));
  assert.equal(payload(theirs), undefined, `never read as Spellmind's: ${JSON.stringify(theirs)}`);
});
