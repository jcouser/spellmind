// Milestone 4 end to end: the real addon (in the VM, on the stub's level-15 Dwarf rogue) and the real
// service, joined the way the game and the app are: what the addon draws is read off its screen into
// handlePayload, and each slot the service writes is loaded on a doorbell ring. The turn (a stand-in
// AI) must see the character: the race, class, level, gear and talents from the game, not a guess.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { newVM } from '../helpers/addon-vm.mjs';
import { findAndDecode } from '../../core/link/strip.mjs';
import { createService } from '../../core/link/service.mjs';
import { buildRequest } from '../../core/ai/context.mjs';
import { loadPack } from '../../core/ai/pack.mjs';

function ring(vm) {
  const bell = vm.pushBell = vm.pushBell === 'push_a' ? 'push_b' : 'push_a';
  vm.run('NS.Link.Poll()');
  vm.bell(`bell_${bell}`, false).run('NS.Link.Poll()');
  vm.bell(`bell_${bell}`, true).run('NS.Link.Poll()');
}

function rig(t, turn) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'sm-e2e-'));
  const addonsDir = path.join(root, 'AddOns');
  fs.mkdirSync(path.join(addonsDir, 'Spellmind', 'sig', 'ctl'), { recursive: true });
  for (let i = 1; i <= 3; i++) fs.mkdirSync(path.join(addonsDir, `Spellmind_S00${i}`), { recursive: true });
  const svc = createService({ addonsDir, stateDir: path.join(root, 'state'), slotCount: 3, timers: false, ackRingMs: 0, turn });
  svc.start();
  t.after(() => { svc.stop(); fs.rmSync(root, { recursive: true, force: true }); });
  const vm = newVM().login().advance(3.1);
  // One round of the link: the screen read into the service, the service's slot loaded on a ring.
  const round = async () => {
    const img = vm.screen();
    if (img) { const r = findAndDecode(img); if (r.kind === 'decoded') svc.handlePayload(r.text); }
    await new Promise(r => setTimeout(r, 20));
    svc.flushNow();
    vm.slotText(fs.readFileSync(path.join(addonsDir, 'Spellmind_S001', 'Inbox.lua'), 'utf8'));
    ring(vm);
    vm.advance(1);
  };
  return { svc, vm, round };
}

test('the character reaches the AI: hello, the parts, then a message whose turn sees a level-15 Dwarf rogue with its gear and talents', async (t) => {
  const seen = [];
  const { vm, round, svc } = rig(t, async (a) => { seen.push(a); return { text: 'You are a Dwarf rogue.' }; });
  await round(); // the hello answered: caps state and z, so the parts go up
  vm.slash('What race am I?');
  for (let i = 0; i < 12 && !seen.length; i++) await round();
  assert.equal(seen.length, 1, 'one turn');
  const g = seen[0].game;
  assert.ok(g && g.state, `the turn got the game state: ${JSON.stringify(g)}`);
  assert.equal(g.stale, false);
  assert.equal(g.state.char.race, 'Dwarf');
  assert.equal(g.state.char.class, 'Rogue');
  assert.equal(g.state.char.level, 15);
  assert.ok(g.state.gear.items.some(i => i.name === 'Simple Robe of the Monkey'));
  assert.ok(g.state.talents.nodes.length > 0);
  assert.equal(g.state.quests.count, 7);
  for (let i = 0; i < 4; i++) await round();
  assert.ok(vm.chatLines().includes('Spellmind: You are a Dwarf rogue.'), JSON.stringify(vm.chatLines()));
  // What the model is sent: the fenced block with the race in it, then the typed question; no name.
  const req = buildRequest({ pack: loadPack(), game: g, history: [], userText: 'What race am I?', nonce: 'abcd1234' });
  const user = req.messages.at(-1).content;
  assert.match(user, /^<game_data id="abcd1234">\n/);
  assert.match(user, /"race":"Dwarf"/);
  assert.match(user, /<\/game_data id="abcd1234">\nWhat race am I\?$/);
  const token = vm.evaluate('SpellmindDB.token');
  assert.ok(svc.state.tokens[token], 'the token is known');
});

test('a second question carries only what changed: an equip change sends gear again and nothing else', async (t) => {
  const seen = [];
  const { vm, round, svc } = rig(t, async (a) => { seen.push(a); return { text: 'Noted.' }; });
  await round();
  vm.slash('first');
  for (let i = 0; i < 12 && seen.length < 1; i++) await round();
  for (let i = 0; i < 3; i++) await round(); // every part confirmed
  const lines = [];
  // Watch what the next frames carry.
  const watch = () => { const img = vm.screen(); if (img) { const r = findAndDecode(img); if (r.kind === 'decoded') lines.push(r.text); } };
  vm.run('STUB.equipped[5] = nil; STUB.FireEvent("PLAYER_EQUIPMENT_CHANGED", 5, true)'); // the robe comes off
  vm.advance(3); // the 2 s coalesced build
  vm.slash('second');
  watch();
  const parts = [...lines.join('\x1e').matchAll(/part=([a-z]+)/g)].map(m => m[1]);
  assert.ok(parts.includes('gear'), `gear goes again: ${parts}`);
  // The robe moves gear and stats (its armor and agility); nothing else changed, so nothing else goes.
  for (const p of ['char', 'talents', 'skills', 'quests', 'rep']) assert.ok(!parts.includes(p), `${p} didn't change, so it doesn't go: ${parts}`);
  for (let i = 0; i < 12 && seen.length < 2; i++) await round();
  assert.equal(seen.length, 2);
  assert.ok(!seen[1].game.state.gear.items.some(i => i.slot === 5), 'the turn sees the robe gone');
});
