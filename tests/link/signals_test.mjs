// Spellmind: adapted from NeverQuestAlone's tests/signals_test.mjs (MIT; see NOTICE.md).
// Doorbells (docs/PROTOCOL.md §3, C-8): pulses delete a bell and recreate it,
// the two bells of a pair are never missing together, and the bridge re-rings
// push until the addon says (seen p=) that it has read the latest publish.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createSignals, BELLS, PUSH_MIN_MS } from '../../core/link/signals.mjs';
import { installSlots } from '../../core/link/slots.mjs';
import { encodeRecord } from '../../core/link/records.mjs';

// A clock and timers the test moves by hand.
function fakeTimers() {
  let now = 0;
  let id = 0;
  const due = new Map();
  return {
    now: () => now,
    setTimeout(fn, ms) { const t = ++id; due.set(t, { at: now + ms, fn }); return t; },
    clearTimeout(t) { due.delete(t); },
    advance(ms) {
      const until = now + ms;
      for (;;) {
        let next = null;
        for (const [t, d] of due) if (d.at <= until && (!next || d.at < next[1].at)) next = [t, d];
        if (!next) break;
        due.delete(next[0]);
        now = next[1].at;
        next[1].fn();
      }
      now = until;
    },
  };
}

function addons() {
  const dir = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'nqa-bells-')), 'AddOns');
  installSlots(dir, { count: 2, iface: '16001' });
  return dir;
}
const bellFile = (dir, b) => path.join(dir, 'Spellmind', 'sig', 'ctl', `bell_${b}.wav`);
const armed = (dir, b) => fs.existsSync(bellFile(dir, b));

test('doorbells: setup makes every bell; a ring deletes one bell for its pulse, then recreates it', () => {
  const dir = addons();
  for (const b of BELLS) assert.ok(armed(dir, b), `${b} made at setup`);
  const clock = fakeTimers();
  const sig = createSignals(dir, { timers: clock });
  sig.ringPush();
  assert.equal(armed(dir, 'push_a'), false, 'push_a rung');
  assert.equal(armed(dir, 'push_b'), true);
  clock.advance(2999);
  assert.equal(armed(dir, 'push_a'), false);
  clock.advance(1);
  assert.equal(armed(dir, 'push_a'), true, 'back after 3 s');
  sig.ringPush();
  assert.equal(armed(dir, 'push_b'), false, 'the next ring uses the other bell');
  clock.advance(3000);
  assert.deepEqual(sig.stats().rings, { push_a: 1, push_b: 1, alive_a: 0, alive_b: 0, act: 0 });
});

test('doorbells: a ring during a pulse follows it on the other bell; the two of a pair are never missing together', () => {
  const dir = addons();
  const clock = fakeTimers();
  const sig = createSignals(dir, { timers: clock });
  sig.ringPush();
  clock.advance(1000);
  sig.ringPush();
  sig.ringPush(); // folds into the one that follows
  for (let t = 0; t < 8000; t += 100) {
    assert.ok(armed(dir, 'push_a') || armed(dir, 'push_b'), `a push bell present at ${t} ms`);
    clock.advance(100);
  }
  assert.equal(sig.stats().rings.push_a + sig.stats().rings.push_b, 2);
  sig.beat();
  assert.equal(armed(dir, 'alive_a'), false);
  clock.advance(2500);
  assert.equal(armed(dir, 'alive_a'), true);
  sig.beat();
  assert.equal(armed(dir, 'alive_b'), false, 'alive bells take turns');
});

test('doorbells (PF-03): a reply rung 400 ms after its ack starts its pulse within 1 s of the ack\'s, not after the ack\'s 3 s; then it lasts its whole pulse', () => {
  const dir = addons();
  const clock = fakeTimers();
  const sig = createSignals(dir, { timers: clock });
  assert.equal(PUSH_MIN_MS, 1000);
  sig.ringPush(); // the ack's publish
  clock.advance(400);
  sig.ringPush(); // the reply's, during the ack's pulse
  let t = 400;
  while (armed(dir, 'push_b') && t < 5000) {
    clock.advance(50);
    t += 50;
    assert.ok(armed(dir, 'push_a') || armed(dir, 'push_b'), `a push bell present at ${t} ms`);
  }
  assert.ok(t <= PUSH_MIN_MS, `the reply's bell rang at ${t} ms (before the cut: 3000 ms)`);
  assert.equal(armed(dir, 'push_a'), true, 'the ack\'s bell is back before the reply\'s went');
  // Nothing behind it: the reply's pulse keeps its whole 3 s, for a reader on the 2 s tick.
  clock.advance(2999);
  assert.equal(armed(dir, 'push_b'), false, 'still ringing at 2999 ms');
  clock.advance(1);
  assert.equal(armed(dir, 'push_b'), true, 'back at 3000 ms');
  assert.equal(sig.stats().rings.push_a + sig.stats().rings.push_b, 2);
});

test('doorbells (PF-03): rings asked for in one tick during a pulse still fold into one follow-up after the cut', () => {
  const dir = addons();
  const clock = fakeTimers();
  const sig = createSignals(dir, { timers: clock });
  sig.ringPush();
  clock.advance(1500);
  sig.ringPush();
  sig.ringPush();
  sig.ringPush();
  clock.advance(0);
  assert.equal(armed(dir, 'push_a'), true, 'cut at once: past its first second');
  assert.equal(armed(dir, 'push_b'), false);
  for (let t = 0; t < 6000; t += 100) {
    assert.ok(armed(dir, 'push_a') || armed(dir, 'push_b'), `a push bell present at ${t} ms`);
    clock.advance(100);
  }
  assert.equal(sig.stats().rings.push_a + sig.stats().rings.push_b, 2, 'the three rings behind it are one');
});

test('doorbells: act pulses queue with gaps a 4 Hz reader can see; stop puts every bell back', () => {
  const dir = addons();
  const clock = fakeTimers();
  const sig = createSignals(dir, { timers: clock });
  for (let i = 0; i < 12; i++) sig.act();
  let pulses = 0, was = true;
  for (let t = 0; t < 20000; t += 50) {
    const now = armed(dir, 'act');
    if (was && !now) pulses++;
    was = now;
    clock.advance(50);
  }
  assert.equal(pulses, 9, 'one pulsing and at most 8 waiting; extras dropped');
  sig.ringPush();
  sig.beat();
  sig.act();
  sig.stop();
  for (const b of BELLS) assert.ok(armed(dir, b), `${b} back in place after stop`);
});

test('doorbells: cleanup removes the v2.0 signal files and keeps the bells', () => {
  const dir = addons();
  const root = path.join(dir, 'Spellmind', 'sig');
  for (const [fam, name] of [['ack', 'a3f1_1'], ['push', '7'], ['act', 'a3f1_1_1'], ['presence', '59679030'], ['ctl', 'live_a3f1'], ['ctl', 'probe_a3f1']]) {
    fs.mkdirSync(path.join(root, fam), { recursive: true });
    fs.writeFileSync(path.join(root, fam, `${name}.wav`), '');
  }
  const sig = createSignals(dir);
  assert.equal(sig.cleanupLegacy(), 6);
  for (const b of BELLS) assert.ok(armed(dir, b));
  assert.ok(fs.existsSync(path.join(root, 'ctl', 'present.wav')));
});

// A link planted where the doorbells go is TH12's POSIX case (another account that can write AddOns).
const PLANTED_LINKS = process.platform === 'win32' ? 'making a symlink on Windows takes an administrator or Developer Mode; the Windows check is the AddOns folder\'s ACL (bridge/byok/wow.mjs broadWritersFromIcacls)' : false;

test('doorbells: cleanup never follows a link planted where sig/ or one of its folders goes (TH12, final review L3-3)', { skip: PLANTED_LINKS }, () => {
  // Another account that can write AddOns plants sig/push → the player's own folder; the player's
  // bridge must not delete that folder's .wav files.
  const victim = fs.mkdtempSync(path.join(os.tmpdir(), 'nqa-victim-'));
  for (const f of ['song.wav', 'take2.wav', 'live_x.wav', 'notes.txt']) fs.writeFileSync(path.join(victim, f), 'mine');
  const dir = addons();
  const root = path.join(dir, 'Spellmind', 'sig');
  fs.mkdirSync(path.join(root, 'ack'), { recursive: true });
  fs.writeFileSync(path.join(root, 'ack', 'a3f1_1.wav'), '');
  fs.symlinkSync(victim, path.join(root, 'push'));
  fs.rmSync(path.join(root, 'ctl'), { recursive: true });
  fs.symlinkSync(victim, path.join(root, 'ctl'));
  fs.symlinkSync(path.join(victim, 'song.wav'), path.join(root, 'ack', 'linked.wav'));
  const sig = createSignals(dir);
  assert.equal(sig.cleanupLegacy(), 1, 'only the real legacy file');
  assert.deepEqual(fs.readdirSync(victim).sort(), ['live_x.wav', 'notes.txt', 'song.wav', 'take2.wav']);
  // sig/ itself a link: nothing at all.
  const dir2 = addons();
  fs.rmSync(path.join(dir2, 'Spellmind', 'sig'), { recursive: true });
  fs.mkdirSync(path.join(victim, 'push'));
  fs.writeFileSync(path.join(victim, 'push', '7.wav'), 'mine');
  fs.symlinkSync(victim, path.join(dir2, 'Spellmind', 'sig'));
  assert.equal(createSignals(dir2).cleanupLegacy(), 0);
  assert.deepEqual(fs.readdirSync(path.join(victim, 'push')), ['7.wav']);
});

// What a folder outside AddOns holds, name → contents (a folder shows as '<dir>').
const snapshot = (dir) => Object.fromEntries(fs.readdirSync(dir).sort().map(f => {
  const st = fs.lstatSync(path.join(dir, f));
  return [f, st.isFile() ? fs.readFileSync(path.join(dir, f), 'utf8') : '<dir>'];
}));
const isLink = f => { try { return fs.lstatSync(f).isSymbolicLink(); } catch { return false; } };

test('doorbells: nothing is written or removed through a link planted at sig/ctl; setup puts a real folder back (TH12)', { skip: PLANTED_LINKS }, () => {
  // Another account that can write AddOns plants sig/ctl → the player's own folder, where some
  // files happen to carry bell names: a ring would delete them, ensure and stop would add bells.
  const victim = fs.mkdtempSync(path.join(os.tmpdir(), 'nqa-victim-'));
  for (const f of ['bell_push_a.wav', 'bell_alive_a.wav', 'bell_act.wav', 'present.wav', 'notes.txt']) fs.writeFileSync(path.join(victim, f), 'mine');
  const before = snapshot(victim);
  const dir = addons();
  const ctl = path.join(dir, 'Spellmind', 'sig', 'ctl');
  fs.rmSync(ctl, { recursive: true });
  fs.symlinkSync(victim, ctl);
  const clock = fakeTimers();
  const logged = [];
  const sig = createSignals(dir, { timers: clock, log: (ev, o) => logged.push([ev, o.error]) });
  assert.deepEqual(sig.missingFolders(), ['ctl'], 'a link is not the ctl folder: run setup');
  assert.deepEqual(sig.ensure(), [], 'nothing made through the link');
  assert.equal(sig.isArmed('push_a'), false);
  sig.ringPush(); sig.beat(); sig.act();
  clock.advance(10000);
  sig.ringPush(); sig.beat();
  sig.stop();
  assert.deepEqual(snapshot(victim), before, 'the outside folder is untouched');
  assert.ok(isLink(ctl), 'the bridge removes nothing at ctl; setup replaces it');
  assert.ok(logged.length > 0 && logged.every(([ev, e]) => ev === 'signal-error' && e === 'ctl_not_a_folder'));
  // A link to an outside file where the folder goes: the same.
  const outside = path.join(victim, 'notes.txt');
  const dir2 = addons();
  const ctl2 = path.join(dir2, 'Spellmind', 'sig', 'ctl');
  fs.rmSync(ctl2, { recursive: true });
  fs.symlinkSync(outside, ctl2);
  const sig2 = createSignals(dir2, { timers: clock });
  assert.deepEqual(sig2.ensure(), []);
  sig2.ringPush(); clock.advance(3000); sig2.stop();
  assert.deepEqual(snapshot(victim), before);
  // Setup removes the link (never what it points to) and makes the bells; rings work again.
  installSlots(dir, { count: 2, iface: '16001' });
  assert.equal(isLink(ctl), false);
  assert.deepEqual(sig.missingFolders(), []);
  assert.deepEqual(sig.ensure(), []);
  sig.ringPush();
  assert.equal(armed(dir, 'push_a'), false, 'rung');
  clock.advance(3000);
  assert.equal(armed(dir, 'push_a'), true, 'back after 3 s');
  assert.deepEqual(snapshot(victim), before);
});

test('doorbells: a link planted at a bell\'s path is removed and the bell made; the file it points to is untouched (TH12)', { skip: PLANTED_LINKS }, () => {
  const outsideDir = fs.mkdtempSync(path.join(os.tmpdir(), 'nqa-victim-'));
  const victim = path.join(outsideDir, 'zshrc');
  fs.writeFileSync(victim, 'mine\n');
  const dir = addons();
  const ctl = path.join(dir, 'Spellmind', 'sig', 'ctl');
  const plant = (name, target = victim) => { const f = path.join(ctl, name); fs.rmSync(f, { recursive: true, force: true }); fs.symlinkSync(target, f); return f; };
  // A link to an existing file (the plain existence check followed it and kept the link), and a
  // dangling one.
  plant('present.wav');
  plant('bell_push_a.wav');
  plant('bell_alive_a.wav', path.join(outsideDir, 'made-by-the-bell'));
  const clock = fakeTimers();
  const sig = createSignals(dir, { timers: clock });
  assert.equal(sig.isArmed('push_a'), false, 'a link is not a bell');
  assert.deepEqual(sig.ensure(), ['present', 'push_a', 'alive_a']);
  for (const f of ['present.wav', 'bell_push_a.wav', 'bell_alive_a.wav']) {
    assert.ok(fs.lstatSync(path.join(ctl, f)).isFile(), `${f} a plain file again`);
  }
  assert.deepEqual(snapshot(outsideDir), { zshrc: 'mine\n' }, 'nothing written, removed or made outside');
  // Planted again after start: a ring removes the link itself, and the bell comes back a file.
  plant('bell_push_a.wav');
  sig.ringPush();
  assert.equal(fs.existsSync(path.join(ctl, 'bell_push_a.wav')) || isLink(path.join(ctl, 'bell_push_a.wav')), false, 'the link is gone for the pulse');
  assert.equal(armed(dir, 'push_b'), true);
  clock.advance(3000);
  assert.ok(fs.lstatSync(path.join(ctl, 'bell_push_a.wav')).isFile());
  // Planted during a pulse: the bell made when it ends replaces the link.
  sig.ringPush();
  plant('bell_push_b.wav');
  clock.advance(3000);
  assert.ok(fs.lstatSync(path.join(ctl, 'bell_push_b.wav')).isFile());
  // stop() replaces one too.
  plant('bell_alive_b.wav');
  sig.stop();
  assert.ok(fs.lstatSync(path.join(ctl, 'bell_alive_b.wav')).isFile());
  assert.deepEqual(snapshot(outsideDir), { zshrc: 'mine\n' });
  // Only regular files and links are removed: a folder at a bell's path stays, and so does its file.
  const folder = path.join(ctl, 'bell_act.wav');
  fs.rmSync(folder);
  fs.mkdirSync(folder);
  fs.writeFileSync(path.join(folder, 'keep.txt'), 'mine');
  assert.deepEqual(sig.ensure(), []);
  sig.act(); clock.advance(2000); sig.stop();
  assert.equal(fs.readFileSync(path.join(folder, 'keep.txt'), 'utf8'), 'mine');
  // Normal rings still work, on time.
  sig.ringPush(); // the third push ring: push_a again
  assert.equal(armed(dir, 'push_a'), false);
  assert.equal(armed(dir, 'push_b'), true);
  clock.advance(2999);
  assert.equal(armed(dir, 'push_a'), false);
  clock.advance(1);
  assert.equal(armed(dir, 'push_a'), true, 'back after 3 s');
  assert.deepEqual(sig.stats().rings, { push_a: 2, push_b: 1, alive_a: 0, alive_b: 0, act: 1 });
});

