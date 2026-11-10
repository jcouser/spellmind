// Spellmind: adapted from NeverQuestAlone's tests/strip_js_test.mjs (MIT; see NOTICE.md).
// The JavaScript strip decoder (core/link/strip.mjs) against the addon's real codec (Codec.lua in a Lua
// VM, rendered to a PNG): the live strip, the cases told apart, and living beside NeverQuestAlone's strip.
import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { LIVE, MAGIC, decodeAt, findAndDecode } from '../../core/link/strip.mjs';
import { decodePng } from '../helpers/images.mjs';

const require = createRequire(import.meta.url);
const { encodeWithLua, render } = require('../helpers/strip-render.cjs');
const cellsFor = (id, text, magic2) => encodeWithLua(id, text, magic2); // the shipped codec, magic 53 4D (code health AD-11)
const TEXT = 'v=2;k=msg;c=main;t=Which professions suit a Combat rogue? Ünïcödé ✓';

test('the magic is "SM" (0x53 0x4D), its first cells 2,4,6,4,6: neither NeverQuestAlone\'s (6,1,6) nor wow-ai\'s', () => {
  assert.deepEqual(MAGIC, [0x53, 0x4d]);
  assert.deepEqual(cellsFor(1, 'x').slice(0, 5), [2, 4, 6, 4, 6]);
});

test('the live strip: 4 px cells at the corner, and scaled under a title bar with noise', () => {
  const clean = decodePng(render(cellsFor(4242, TEXT), { width: 900, height: 200 }));
  const r = findAndDecode(clean, LIVE);
  assert.equal(r.kind, 'decoded');
  assert.equal(r.id, 4242);
  assert.equal(r.text, TEXT);
  assert.deepEqual(r.geometry, { x0: 0, y0: 0, pitch: 4 });

  const rough = decodePng(render(cellsFor(7, TEXT), { width: 1200, height: 260, pitch: 5.4, y0: 28, titleBar: 28, busyBackground: true, gamma: 1.2, jitter: 20 }));
  const s = findAndDecode(rough, LIVE);
  assert.equal(s.kind, 'decoded', JSON.stringify(s));
  assert.equal(s.text, TEXT);
  assert.ok(Math.abs(s.geometry.pitch - 5.4) < 0.05 && Math.abs(s.geometry.y0 - 28) < 2);
  assert.deepEqual(findAndDecode(rough, LIVE, s.geometry), s, 'a hint that worked decodes at once');
});

test('beside NeverQuestAlone: a strip in its magic (C7 2C) is none to Spellmind; Spellmind\'s own, 272 px down under it, decodes', () => {
  const nqa = encodeWithLua(9, TEXT, 0x2c, 0xc7); // NeverQuestAlone's codec is this one with its magic
  assert.deepEqual(nqa.slice(0, 3), [6, 1, 6], 'NeverQuestAlone\'s strip starts 6,1,6');
  const onlyTheirs = decodePng(render(nqa, { width: 900, height: 200 }));
  assert.equal(findAndDecode(onlyTheirs, LIVE).kind, 'none', 'never read as Spellmind\'s');
  const both = decodePng(render(cellsFor(11, TEXT), { width: 900, height: 700, y0: 272, others: [{ cells: nqa, x0: 0, y0: 0 }] }));
  const r = findAndDecode(both, LIVE);
  assert.equal(r.kind, 'decoded', JSON.stringify(r));
  assert.equal(r.text, TEXT);
  assert.equal(r.geometry.y0, 272);
});

test('no strip, a damaged strip and cells too small to read are told apart', () => {
  const blank = decodePng(render([], { width: 400, height: 100 }));
  assert.deepEqual(findAndDecode(blank, LIVE), { kind: 'none' });

  const img = decodePng(render(cellsFor(1, TEXT), { width: 900, height: 200 }));
  const g = findAndDecode(img, LIVE).geometry;
  // Flip one payload cell (the 30th) to another colour: the checksum catches it.
  const x = Math.floor(g.x0 + 29.5 * g.pitch), y = Math.floor(g.y0 + 0.5 * g.pitch);
  for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
    const p = ((y + dy) * img.width + x + dx) * 3;
    img.data[p] ^= 0xff;
  }
  const bad = findAndDecode(img, LIVE);
  assert.equal(bad.kind, 'rejected');
  assert.equal(bad.reason, 'checksum');
  assert.equal(decodeAt(img, g, LIVE).reason, 'checksum');

  const tiny = decodePng(render(cellsFor(1, TEXT), { width: 500, height: 60, pitch: 2 }));
  assert.equal(findAndDecode(tiny, LIVE).reason, 'pitch_too_small');
});
