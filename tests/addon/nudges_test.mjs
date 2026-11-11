// Milestone 8 (docs/milestone-8.md): nudges. A toast by the minimap from local facts, one at a time,
// never in combat; Ask sends its question (the answer in the card beside the toast), Dismiss moves
// on; a dismissed situation doesn't come back until it changes; the minimap button's dot; quests
// that become ready to turn in (not those ready at login); /sm nudges off.
import test from 'node:test';
import assert from 'node:assert/strict';
import { newVM } from '../helpers/addon-vm.mjs';

// Logged in and past the nudges' first look (8 s in).
const session = () => newVM().login().advance(9);
const shown = vm => vm.evaluate('tostring(SpellmindNudge ~= nil and SpellmindNudge.shown)') === 'true';
const title = vm => vm.evaluate('SpellmindNudge.title:GetText()');

test('at login: a spell to train (Sprint, due at 10, the rogue is 15), with the minimap dot', () => {
  const vm = session();
  assert.ok(shown(vm), 'the toast');
  assert.equal(title(vm), 'A spell to train');
  assert.equal(vm.evaluate('SpellmindNudge.text:GetText()'), 'Sprint (rank 1)', 'Kick is due at 16: not yet');
  assert.equal(vm.evaluate('tostring(SpellmindMinimapButton.dot.shown)'), 'true');
});

test('Dismiss: gone, and not again for the same situation; a level up (more spells due) brings a new one', () => {
  const vm = session();
  vm.run('SpellmindNudge.dismiss.scripts.OnClick(SpellmindNudge.dismiss)');
  assert.ok(!shown(vm));
  assert.equal(vm.evaluate('tostring(SpellmindMinimapButton.dot.shown)'), 'false');
  vm.run('NS.Nudges.Check()');
  vm.advance(4);
  assert.ok(!shown(vm), 'the same situation stays dismissed');
  vm.run('STUB.player.level = 16; STUB.FireEvent("PLAYER_LEVEL_UP", 16)');
  vm.advance(4);
  assert.ok(shown(vm));
  assert.equal(title(vm), '2 spells to train');
  assert.equal(vm.evaluate('SpellmindNudge.text:GetText()'), 'Sprint (rank 1), Kick (rank 2)');
});

test('Ask: the question in the chat, its answer in the card to the toast\'s left; the next nudge after a gap', () => {
  const vm = session();
  vm.run('for b = 0, 4 do STUB.bags[b].free = 0 end; STUB.FireEvent("BAG_UPDATE_DELAYED")');
  vm.advance(3);
  assert.equal(vm.evaluate('SpellmindNudge.count:GetText()'), '+1 more', 'bags wait behind the spells');
  vm.run('SpellmindNudge.ask.scripts.OnClick(SpellmindNudge.ask)');
  assert.equal(vm.evaluate('tostring(SpellmindCard.shown)'), 'true');
  assert.equal(vm.evaluate('SpellmindCard.title:GetText()'), 'Nudge: A spell to train');
  assert.equal(vm.evaluate('SpellmindCard.anchor.point'), 'TOPRIGHT', 'to the left: the minimap is at the screen\'s right edge');
  assert.ok(vm.savedLines().some(l => /Nudge: A spell to train/.test(l)));
  assert.ok(!shown(vm), 'the toast goes as it asks');
  assert.equal(vm.evaluate('tostring(SpellmindCard.shown)'), 'true', 'and the card stays');
  vm.advance(3.5);
  assert.ok(shown(vm));
  assert.equal(title(vm), 'Bags nearly full');
  assert.equal(vm.evaluate('SpellmindNudge.text:GetText()'), '0 slots free. 3 grey items to sell.');
});

test('never in combat: a nudge waits, hidden, and shows when the fight ends', () => {
  const vm = session();
  vm.run('SpellmindNudge.dismiss.scripts.OnClick(SpellmindNudge.dismiss)');
  vm.advance(4);
  vm.run('STUB.combat = true; STUB.FireEvent("PLAYER_REGEN_DISABLED")');
  vm.run('for b = 0, 4 do STUB.bags[b].free = 0 end; STUB.FireEvent("BAG_UPDATE_DELAYED")');
  vm.advance(3);
  assert.ok(!shown(vm), 'not in combat');
  assert.equal(vm.evaluate('tostring(SpellmindMinimapButton.dot.shown)'), 'true', 'the dot says one waits');
  vm.run('STUB.combat = false; STUB.FireEvent("PLAYER_REGEN_ENABLED")');
  assert.ok(shown(vm));
  assert.equal(title(vm), 'Bags nearly full');
});

test('bags: once cleared (more than 6 free), filling up again nudges again', () => {
  const vm = session();
  vm.run('SpellmindNudge.dismiss.scripts.OnClick(SpellmindNudge.dismiss)');
  vm.advance(4);
  const fill = n => vm.run(`for b = 0, 4 do STUB.bags[b].free = 0 end; STUB.bags[0].free = ${n}; STUB.FireEvent("BAG_UPDATE_DELAYED")`);
  fill(1); vm.advance(3);
  assert.equal(title(vm), 'Bags nearly full');
  vm.run('SpellmindNudge.dismiss.scripts.OnClick(SpellmindNudge.dismiss)');
  vm.advance(4);
  fill(2); vm.advance(3);
  assert.ok(!shown(vm), 'still nearly full: dismissed stays dismissed');
  fill(10); vm.advance(3);
  fill(1); vm.advance(3);
  assert.ok(shown(vm), 'cleared, then full again');
});

test('a quest that becomes ready to turn in this session (not those ready at login)', () => {
  const vm = session();
  vm.run('SpellmindNudge.dismiss.scripts.OnClick(SpellmindNudge.dismiss)');
  vm.advance(4);
  assert.ok(!shown(vm), 'Stormpike\'s Order was ready at login: no nudge for it');
  vm.run('STUB.quests[4].complete = true; STUB.FireEvent("QUEST_LOG_UPDATE")');
  vm.advance(3);
  assert.ok(shown(vm));
  assert.equal(title(vm), 'Ready to turn in');
  assert.equal(vm.evaluate('SpellmindNudge.text:GetText()'), "Bingles' Missing Supplies");
});

test('/sm nudges off: none, and the dot goes; on: they come back', () => {
  const vm = session();
  vm.slash('nudges off');
  assert.ok(!shown(vm));
  assert.equal(vm.evaluate('tostring(SpellmindMinimapButton.dot.shown)'), 'false');
  vm.run('STUB.player.level = 16; STUB.FireEvent("PLAYER_LEVEL_UP", 16)');
  vm.advance(4);
  assert.ok(!shown(vm));
  vm.slash('nudges on');
  assert.ok(shown(vm));
});

test('/sm nudges reset: dismissed ones show again, with a count in chat', () => {
  const vm = session();
  vm.run('SpellmindNudge.dismiss.scripts.OnClick(SpellmindNudge.dismiss)');
  vm.advance(4);
  assert.ok(!shown(vm));
  vm.slash('nudges reset');
  assert.ok(shown(vm));
  assert.equal(title(vm), 'A spell to train');
  assert.ok(vm.chatLines().includes('Spellmind: 1 nudge to show.'), JSON.stringify(vm.chatLines()));
});

test('/sm nudges demo: a sample toast; Ask works on it like a real one', () => {
  const vm = newVM().login().advance(3.1); // before the first look
  vm.slash('nudges demo');
  assert.ok(shown(vm));
  assert.equal(title(vm), 'A sample nudge');
  vm.run('SpellmindNudge.ask.scripts.OnClick(SpellmindNudge.ask)');
  assert.equal(vm.evaluate('SpellmindCard.title:GetText()'), 'Nudge: A sample nudge');
});

test('the toast sits beside the minimap, at its left (not under it, where the quest tracker is)', () => {
  const vm = session();
  assert.equal(vm.evaluate('SpellmindNudge.anchor.point'), 'TOPRIGHT');
  assert.equal(vm.evaluate('tostring(SpellmindNudge.anchor.rel == Minimap)'), 'true');
  assert.equal(vm.evaluate('SpellmindNudge.anchor.relPoint'), 'TOPLEFT');
});
