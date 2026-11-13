// The CurseForge zip (tools/package-addon.mjs): the addon as the app installs it, its licence, the
// doorbells and the 200 slot addons; reproducible; and its version the app's, so an addon from
// CurseForge and the app's copy are compared by the same number (core/link/install.mjs shouldUpdate).
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';
import { addonEntries, packageAddon, zip } from '../../tools/package-addon.mjs';
import { SLOT_COUNT, slotName } from '../../core/link/slots.mjs';
import { BELLS } from '../../core/link/signals.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');

test('the zip holds the addon, LICENSE.txt, every doorbell and every slot addon', () => {
  const { version, iface, entries } = addonEntries();
  const names = new Set(entries.map(e => e.name));
  assert.match(version, /^\d+\.\d+\.\d+$/);
  assert.equal(iface, '16001');
  assert.ok(names.has('Spellmind/Spellmind.toc'));
  assert.ok(names.has('Spellmind/Core.lua'));
  assert.ok(names.has('Spellmind/Media/Spellmind.tga'));
  assert.ok(names.has('Spellmind/LICENSE.txt'));
  assert.ok(names.has('Spellmind/sig/ctl/present.wav'));
  for (const b of BELLS) assert.ok(names.has(`Spellmind/sig/ctl/bell_${b}.wav`), b);
  for (const i of [1, SLOT_COUNT]) {
    assert.ok(names.has(`${slotName(i)}/${slotName(i)}.toc`));
    assert.ok(names.has(`${slotName(i)}/Inbox.lua`));
  }
  assert.ok(!names.has(`${slotName(SLOT_COUNT + 1)}/${slotName(SLOT_COUNT + 1)}.toc`));
  assert.ok(![...names].some(n => n.split('/').some(p => p.startsWith('.'))), 'no dotfiles (.installed-by)');
});

test('the addon\'s version is the app\'s: one number for a release', () => {
  const app = JSON.parse(fs.readFileSync(path.join(ROOT, 'app', 'desktop', 'package.json'), 'utf8')).version;
  assert.equal(addonEntries().version, app);
});

test('a build is the same bytes twice, and unzips to what went in', (t) => {
  const out = fs.mkdtempSync(path.join(os.tmpdir(), 'sm-zip-'));
  t.after(() => fs.rmSync(out, { recursive: true, force: true }));
  const a = packageAddon({ outDir: out, name: 'a.zip' });
  const b = packageAddon({ outDir: out, name: 'b.zip' });
  assert.ok(fs.readFileSync(a.file).equals(fs.readFileSync(b.file)));
  // Read the first file's entry back (local header at 0 is a folder; find Spellmind/Spellmind.toc).
  const buf = zip([{ name: 'x/y.txt', data: Buffer.from('hello hello hello hello hello') }]);
  const at = buf.indexOf(Buffer.from('x/y.txt'), 30 + 2);
  const head = at - 30;
  assert.equal(buf.readUInt32LE(head), 0x04034b50);
  const method = buf.readUInt16LE(head + 8), size = buf.readUInt32LE(head + 18);
  const body = buf.subarray(at + 7, at + 7 + size);
  assert.equal((method === 8 ? zlib.inflateRawSync(body) : body).toString(), 'hello hello hello hello hello');
});

test('bad names are refused', () => {
  assert.throws(() => zip([{ name: '../evil', data: Buffer.alloc(0) }]), /bad zip name/);
  assert.throws(() => zip([{ name: 'a', data: Buffer.alloc(0) }, { name: 'a', data: Buffer.alloc(0) }]), /two files/);
});
