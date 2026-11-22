// The installer (core/link/install.mjs) on a fake WoW: Forever folder: the addon, its slot addons
// and its doorbells go in; a running game, a folder that isn't WoW's and a missing addon are refused;
// tasklist's CSV is read as the game's pids and never WowUp's or the voice proxy's.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { installAddon, parseTasklist, RUNNING_LINE } from '../../core/link/install.mjs';

function fakeWow(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'sm-install-'));
  const flavor = path.join(root, '_forever_');
  fs.mkdirSync(path.join(flavor, 'Interface', 'AddOns'), { recursive: true });
  fs.mkdirSync(path.join(flavor, 'WTF'));
  const src = path.join(root, 'src', 'Spellmind');
  fs.mkdirSync(path.join(src, 'Media'), { recursive: true });
  fs.writeFileSync(path.join(src, 'Spellmind.toc'), '## Interface: 16001\n## Title: Spellmind\nCodec.lua\n');
  fs.writeFileSync(path.join(src, 'Codec.lua'), '-- codec\n');
  fs.writeFileSync(path.join(src, 'Media', 'icon.tga'), 'x');
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  return { root, flavor, src, addons: path.join(flavor, 'Interface', 'AddOns') };
}
const closed = () => ({ running: false, pids: [] });

test('install: the addon, its slot addons (TOCs for the game\'s interface, placeholder inboxes) and its doorbells', (t) => {
  const w = fakeWow(t);
  const r = installAddon({ flavorDir: w.flavor, source: w.src, count: 3, running: closed });
  assert.equal(r.ok, true, JSON.stringify(r));
  assert.ok(fs.existsSync(path.join(w.addons, 'Spellmind', 'Spellmind.toc')));
  assert.ok(fs.existsSync(path.join(w.addons, 'Spellmind', 'Media', 'icon.tga')));
  const toc = fs.readFileSync(path.join(w.addons, 'Spellmind_S002', 'Spellmind_S002.toc'), 'utf8');
  assert.match(toc, /## Interface: 16001/);
  assert.match(toc, /## LoadOnDemand: 1/);
  assert.match(toc, /## Dependencies: Spellmind/);
  assert.equal(fs.readFileSync(path.join(w.addons, 'Spellmind_S001', 'Inbox.lua'), 'utf8'), 'SpellmindSlotData = nil\n');
  for (const f of ['present.wav', 'bell_push_a.wav', 'bell_push_b.wav', 'bell_alive_a.wav', 'bell_alive_b.wav']) assert.ok(fs.existsSync(path.join(w.addons, 'Spellmind', 'sig', 'ctl', f)), f);
  assert.equal(r.bells, 6);
  // Again: kept, and a bridge-written slot inbox stays.
  fs.writeFileSync(path.join(w.addons, 'Spellmind_S001', 'Inbox.lua'), 'SpellmindSlotData = { v = 2 }\n');
  const again = installAddon({ flavorDir: w.flavor, source: w.src, count: 3, running: closed });
  assert.equal(again.slots.kept, 3);
  assert.match(fs.readFileSync(path.join(w.addons, 'Spellmind_S001', 'Inbox.lua'), 'utf8'), /v = 2/);
});

test('install refuses while WoW runs, a folder that isn\'t WoW\'s, and a missing addon', (t) => {
  const w = fakeWow(t);
  const running = installAddon({ flavorDir: w.flavor, source: w.src, running: () => ({ running: true, pids: [42] }) });
  assert.deepEqual([running.ok, running.error, running.detail], [false, 'wow_running', RUNNING_LINE]);
  assert.equal(installAddon({ flavorDir: path.join(w.root, 'src'), source: w.src, running: closed }).error, 'not_a_wow_folder');
  assert.equal(installAddon({ flavorDir: w.flavor, source: path.join(w.root, 'nowhere'), running: closed }).error, 'no_addon');
  assert.equal(fs.existsSync(path.join(w.addons, 'Spellmind')), false, 'nothing written when refused');
});

test('tasklist: the game\'s pids, never WowUp\'s, the voice proxy\'s or the crash reporter\'s', () => {
  const csv = ['"WowClassicB.exe","4242","Console","1","900,000 K"', '"Wow.exe","77","Console","1","1 K"', '"WowUp.exe","5","Console","1","1 K"',
    '"WowVoiceProxy.exe","6","Console","1","1 K"', '"WowError.exe","7","Console","1","1 K"', '"notepad.exe","8","Console","1","1 K"'].join('\r\n');
  assert.deepEqual(parseTasklist(csv), [4242, 77]);
});

test('only forward: a newer addon from CurseForge is left, an older one updated, the same version left unless an older app put it there', async () => {
  const { shouldUpdate } = await import('../../core/link/install.mjs');
  const st = (o) => ({ state: 'outdated', changed: 1, added: 0, ...o });
  assert.deepEqual(shouldUpdate(st({ installedVersion: '0.5.0', version: '0.4.0' }), '0.4.0'), { update: false, why: 'newer_installed' });
  assert.deepEqual(shouldUpdate(st({ installedVersion: '0.3.9', version: '0.4.0' }), '0.4.0'), { update: true, why: 'older_installed' });
  assert.deepEqual(shouldUpdate(st({ installedVersion: '0.4.0', version: '0.4.0' }), '0.4.0'), { update: false, why: 'same_version' });
  assert.deepEqual(shouldUpdate(st({ installedVersion: '0.4.0', version: '0.4.0', installedBy: '0.3.3' }), '0.4.0'), { update: true, why: 'same_version_older_app' });
  assert.deepEqual(shouldUpdate(st({ installedVersion: '0.4.0', version: '0.4.0', installedBy: '0.4.0' }), '0.4.0'), { update: false, why: 'same_version' });
  assert.deepEqual(shouldUpdate(st({ installedBy: '0.5.0' }), '0.4.0'), { update: false, why: 'same_or_newer_app' });
  assert.deepEqual(shouldUpdate(st({}), '0.4.0'), { update: true, why: 'no_version' });
  assert.equal(shouldUpdate({ state: 'current' }, '0.4.0').update, false);
});

test('addonState reads both TOCs\' versions and says when the game\'s is newer', async (t) => {
  const { addonState } = await import('../../core/link/install.mjs');
  const w = fakeWow(t);
  fs.writeFileSync(path.join(w.src, 'Spellmind.toc'), '## Interface: 16001\n## Version: 0.4.0\nCodec.lua\n');
  assert.equal(installAddon({ flavorDir: w.flavor, source: w.src, count: 1, running: closed }).ok, true);
  fs.writeFileSync(path.join(w.addons, 'Spellmind', 'Spellmind.toc'), '## Interface: 16001\n## Version: 0.5.1\nCodec.lua\n');
  const s = addonState({ flavorDir: w.flavor, source: w.src });
  assert.equal(s.state, 'outdated');
  assert.equal(s.installedVersion, '0.5.1');
  assert.equal(s.version, '0.4.0');
  assert.equal(s.newerInstalled, true);
});

test('on Linux, WoW: Forever is found inside a Wine or Proton prefix: Faugus, Steam, Lutris (issue #1)', async () => {
  const { findLinuxFlavorDirs, findFlavorDirs } = await import('../../core/link/install.mjs');
  const fsm = await import('node:fs'); const osm = await import('node:os'); const pathm = await import('node:path');
  const home = fsm.mkdtempSync(pathm.join(osm.tmpdir(), 'sm-home-'));
  const make = (...parts) => { const d = pathm.join(home, ...parts); fsm.mkdirSync(pathm.join(d, 'Interface'), { recursive: true }); return d; };
  const faugus = make('Faugus', 'wow-forever', 'drive_c', 'Program Files (x86)', 'World of Warcraft', '_forever_');
  const steam = make('.local', 'share', 'Steam', 'steamapps', 'compatdata', '4122661234', 'pfx', 'drive_c', 'World of Warcraft', '_forever_');
  make('Games', 'some-other-game', 'drive_c', 'Program Files', 'Other Game');
  const found = findLinuxFlavorDirs(home);
  assert.deepEqual(found.sort(), [faugus, steam].sort());
  assert.deepEqual(findFlavorDirs({ platform: 'linux', home }).sort(), [faugus, steam].sort());
  assert.deepEqual(findLinuxFlavorDirs(pathm.join(home, 'nobody')), [], 'no prefixes: nothing');
});

test('the Linux screen reader as a file python can run: beside app.asar, else copied into the app\'s folder (issue #1)', async () => {
  const { x11Script, X11_SCRIPT } = await import('../../core/link/capture.mjs');
  const fsm = await import('node:fs'); const osm = await import('node:os'); const pathm = await import('node:path');
  // From source the script is where it is.
  assert.equal(x11Script(fsm.mkdtempSync(pathm.join(osm.tmpdir(), 'sm-data-'))), X11_SCRIPT);
  assert.ok(fsm.existsSync(X11_SCRIPT));
});
