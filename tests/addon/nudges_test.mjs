// Milestone 8 (docs/milestone-8.md): nudges. A toast by the minimap from local facts, one at a time,
// never in combat; Ask sends its question (the answer in the card beside the toast), Dismiss moves
// on; a dismissed situation doesn't come back until it changes; the minimap button's dot; quests
// that become ready to turn in (not those ready at login); /sm nudges off.
import test from 'node:test';
import assert from 'node:assert/strict';
import { newVM } from '../helpers/addon-vm.mjs';

// Logged in and past the nudges' first look (8 s in).
const session = () => newVM().login().advance(9);
const list = (vm, expr) => { const v = vm.json(expr); return Array.isArray(v) ? v : Object.values(v || {}); };
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
  assert.equal(vm.evaluate('tostring(SpellmindMinimapButton.dot.shown)'), 'false', 'no look in the fight at all (the review): it runs when it ends');
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

test('a toast fades after 20 s but keeps waiting: the dot stays, the tooltip lists it, clicking the dot brings it back', () => {
  const vm = session();
  assert.ok(shown(vm));
  vm.advance(21);
  assert.ok(!shown(vm), 'faded');
  assert.equal(vm.evaluate('tostring(SpellmindMinimapDot.shown)'), 'true', 'still waiting');
  vm.run('SpellmindMinimapButton.scripts.OnEnter(SpellmindMinimapButton)');
  assert.ok(list(vm, 'GameTooltip.added').includes('  A spell to train'), JSON.stringify(list(vm, 'GameTooltip.added')));
  vm.run('NS.Nudges.Check()');
  vm.advance(1);
  assert.ok(!shown(vm), 'a check with nothing new doesn\'t bring it back');
  vm.run('SpellmindMinimapDot.scripts.OnClick(SpellmindMinimapDot)');
  assert.ok(shown(vm), 'the dot brings it back');
  assert.equal(title(vm), 'A spell to train');
  vm.run('SpellmindNudge.dismiss.scripts.OnClick(SpellmindNudge.dismiss)');
  assert.equal(vm.evaluate('tostring(SpellmindMinimapDot.shown)'), 'false');
});

test('a new situation after a fade shows the toast again on its own', () => {
  const vm = session();
  vm.advance(21);
  assert.ok(!shown(vm));
  vm.run('for b = 0, 4 do STUB.bags[b].free = 0 end; STUB.FireEvent("BAG_UPDATE_DELAYED")');
  vm.advance(3);
  assert.ok(shown(vm), 'something new');
  assert.equal(vm.evaluate('SpellmindNudge.count:GetText()'), '+1 more');
});

test('the Advisor panel\'s Nudges tab: every waiting one (faded too) with Ask and Dismiss; its count on the tab', () => {
  const vm = session();
  vm.run('for b = 0, 4 do STUB.bags[b].free = 0 end; STUB.FireEvent("BAG_UPDATE_DELAYED")');
  vm.advance(3);
  vm.advance(21); // the toast fades; both still wait
  vm.run('NS.Panel.Show("nudges")');
  const tab = vm.evaluate('SpellmindPanel.tabs[9].text:GetText()');
  assert.equal(tab, 'Nudges |cffffd100(2)|r');
  const rows = list(vm, 'SpellmindPanel.drawn').filter(x => x.kind === 'item').map(x => x.text);
  assert.equal(rows.length, 2);
  assert.match(rows[0], /^A spell to train/);
  assert.match(rows[1], /^Bags nearly full/);
  vm.run('SpellmindPanel.rows[3].actions[2].scripts.OnClick(SpellmindPanel.rows[3].actions[2])'); // Dismiss the bags one
  assert.equal(vm.evaluate('SpellmindPanel.tabs[9].text:GetText()'), 'Nudges |cffffd100(1)|r', 'redrawn, counted');
  vm.run('SpellmindPanel.rows[2].actions[1].scripts.OnClick(SpellmindPanel.rows[2].actions[1])'); // Ask the spells one
  assert.equal(vm.evaluate('SpellmindCard.title:GetText()'), 'Nudge: A spell to train');
  assert.equal(vm.evaluate('tostring(SpellmindCard.anchor.rel == SpellmindPanel)'), 'true', 'beside the panel');
  // Asked isn't dismissed (seen in game: Ask removed it): it stays, tagged, off the badge's count.
  const after = list(vm, 'SpellmindPanel.drawn').filter(x => x.kind === 'item');
  assert.equal(after.length, 1, 'still in the list');
  assert.equal(after[0].tag, 'asked');
  assert.equal(vm.evaluate('SpellmindPanel.tabs[9].text:GetText()'), 'Nudges', 'nothing left to see');
  assert.equal(vm.evaluate('tostring(SpellmindMinimapDot.shown)'), 'false');
  vm.advance(4);
  assert.ok(!shown(vm), 'an asked one doesn\'t toast again');
  // Dismissing the last one: "Nothing waiting", with no buttons left over on that row (seen in game).
  vm.run('SpellmindPanel.rows[2].actions[2].scripts.OnClick(SpellmindPanel.rows[2].actions[2])');
  assert.ok(list(vm, 'SpellmindPanel.drawn').some(x => /Nothing waiting/.test(x.text || '')));
  assert.equal(vm.evaluate('tostring(SpellmindPanel.rows[2].actions[1].shown)'), 'false');
  assert.equal(vm.evaluate('tostring(SpellmindPanel.rows[2].actions[2].shown)'), 'false');
  // Then a demo toasts again, though the last toast faded (seen in game: it only joined the list).
  vm.slash('nudges demo');
  assert.ok(shown(vm));
  assert.equal(title(vm), 'A sample nudge');
});

test('the badge: red, with how many wait on it', () => {
  const vm = session();
  assert.equal(vm.evaluate('SpellmindMinimapDot.count:GetText()'), '1');
  vm.run('for b = 0, 4 do STUB.bags[b].free = 0 end; STUB.FireEvent("BAG_UPDATE_DELAYED")');
  vm.advance(3);
  assert.equal(vm.evaluate('SpellmindMinimapDot.count:GetText()'), '2');
  assert.ok(vm.evaluate('SpellmindMinimapDot.tex.texture').endsWith('Media\\Badge'));
});

test('Ask with no app running: the card says the app isn\'t running (not "Thinking…" forever)', () => {
  const vm = session(); // no app in this VM
  vm.run('SpellmindNudge.ask.scripts.OnClick(SpellmindNudge.ask)');
  const card = list(vm, 'SpellmindCard.lines');
  assert.match(card[0], /The Spellmind app isn't running/);
  assert.ok(!card.some(l => /Thinking/.test(l)));
});

test('asking the same thing again while it waits reuses that question: one copy queued, one answer for the card', () => {
  const vm = session(); // no app: the question waits
  vm.run('SpellmindNudge.ask.scripts.OnClick(SpellmindNudge.ask)');
  vm.run('NS.Panel.Show("nudges")');
  vm.run('SpellmindPanel.rows[2].actions[1].scripts.OnClick(SpellmindPanel.rows[2].actions[1])'); // Ask again, from the list
  assert.equal(vm.outbox().filter(o => /I can train/.test(o.wire)).length, 1, 'one copy queued');
  assert.equal(vm.savedLines().filter(l => /Nudge: A spell to train/.test(l)).length, 1, 'one question in the chat');
});

test('a turn-in nearby: a nudge within 150 yd of a ready quest\'s hand-in; again only after going 400 yd away', () => {
  const vm = session();
  vm.run('SpellmindNudge.dismiss.scripts.OnClick(SpellmindNudge.dismiss)');
  vm.advance(4);
  vm.run('STUB.questDist[1338] = 90'); // Stormpike's Order (ready) is handed in 90 yd away
  vm.advance(6); // the 5 s look
  assert.ok(shown(vm));
  assert.equal(title(vm), 'Turn-in nearby');
  assert.equal(vm.evaluate('SpellmindNudge.text:GetText()'), "Stormpike's Order: about 90 yd");
  vm.run('SpellmindNudge.dismiss.scripts.OnClick(SpellmindNudge.dismiss)');
  vm.advance(10);
  assert.ok(!shown(vm), 'still near: once');
  vm.run('STUB.questDist[1338] = 900'); vm.advance(6);
  vm.run('STUB.questDist[1338] = 100'); vm.advance(6);
  assert.ok(shown(vm), 'away and back: again');
});

// The review (2026-11-12): nudges that outlived their situation, came back after every fight, or went
// silent for good once dismissed.
test('resolved: the bags cleared, the nudge goes from the toast, the badge and the list', () => {
  const vm = session();
  vm.run('SpellmindNudge.dismiss.scripts.OnClick(SpellmindNudge.dismiss)'); // the spells one
  vm.run('for b = 0, 4 do STUB.bags[b].free = 0 end; STUB.FireEvent("BAG_UPDATE_DELAYED")');
  vm.advance(4);
  assert.ok(list(vm, 'NS.Nudges.List()').some(n => n.kind === 'bags'));
  vm.run('for b = 0, 4 do STUB.bags[b].free = 5 end; STUB.FireEvent("BAG_UPDATE_DELAYED")');
  vm.advance(4);
  assert.ok(!list(vm, 'NS.Nudges.List()').some(n => n.kind === 'bags'), 'gone once cleared');
  assert.ok(!shown(vm));
});

test('gear about to break: dismissed, then repaired, then worn down again: it nudges again', () => {
  const vm = session();
  vm.run('SpellmindNudge.dismiss.scripts.OnClick(SpellmindNudge.dismiss)');
  vm.run('STUB.equipped[5].dur = { 5, 50 }; STUB.FireEvent("UPDATE_INVENTORY_DURABILITY")');
  vm.advance(4);
  assert.equal(title(vm), 'Gear about to break');
  vm.run('SpellmindNudge.dismiss.scripts.OnClick(SpellmindNudge.dismiss)');
  vm.run('STUB.equipped[5].dur = { 50, 50 }; STUB.FireEvent("UPDATE_INVENTORY_DURABILITY")');
  vm.advance(4);
  vm.run('STUB.equipped[5].dur = { 5, 50 }; STUB.FireEvent("UPDATE_INVENTORY_DURABILITY")');
  vm.advance(4);
  assert.ok(list(vm, 'NS.Nudges.List()').some(n => n.kind === 'durability'), 'back after the repair');
});

test('a toast that showed 5 s before a fight waits behind the badge after it, instead of coming back each kill', () => {
  const vm = session();
  assert.ok(shown(vm));
  vm.advance(6);
  vm.run('STUB.combat = true; STUB.FireEvent("PLAYER_REGEN_DISABLED")');
  vm.run('STUB.combat = false; STUB.FireEvent("PLAYER_REGEN_ENABLED")');
  assert.ok(!shown(vm), 'not again');
  assert.equal(vm.evaluate('tostring(SpellmindMinimapButton.dot.shown)'), 'true', 'still waiting on the badge');
});

test('dismissed situations are per character, not account-wide', () => {
  const vm = session();
  vm.run('SpellmindNudge.dismiss.scripts.OnClick(SpellmindNudge.dismiss)');
  assert.equal(vm.evaluate('tostring(SpellmindDB.nudges.seen)'), 'nil');
  assert.ok(Object.keys(vm.json('NS.State.Me().nudgeSeen')).length > 0);
});
