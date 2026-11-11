// Milestone 5, step 1 (docs/milestone-5.md): the Spellmind mark in the quest log's details, its hover
// facts, Explain ("Break it down") with the quest as the focus part, the answer card, Ask more, and
// the item tooltip line. The real addon in the VM and, for Explain, the real service, joined as the
// game and the app are (as tests/addon/e2e_state_test.mjs).
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { newVM } from '../helpers/addon-vm.mjs';
import { findAndDecode } from '../../core/link/strip.mjs';
import { createService } from '../../core/link/service.mjs';
import { buildRequest, FOCUS_NOTE } from '../../core/ai/context.mjs';
import { loadPack } from '../../core/ai/pack.mjs';

function ring(vm) {
  const bell = vm.pushBell = vm.pushBell === 'push_a' ? 'push_b' : 'push_a';
  vm.run('NS.Link.Poll()');
  vm.bell(`bell_${bell}`, false).run('NS.Link.Poll()');
  vm.bell(`bell_${bell}`, true).run('NS.Link.Poll()');
}

function rig(t, turn) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'sm-marks-'));
  const addonsDir = path.join(root, 'AddOns');
  fs.mkdirSync(path.join(addonsDir, 'Spellmind', 'sig', 'ctl'), { recursive: true });
  for (let i = 1; i <= 3; i++) fs.mkdirSync(path.join(addonsDir, `Spellmind_S00${i}`), { recursive: true });
  const svc = createService({ addonsDir, stateDir: path.join(root, 'state'), slotCount: 3, timers: false, ackRingMs: 0, turn });
  svc.start();
  t.after(() => { svc.stop(); fs.rmSync(root, { recursive: true, force: true }); });
  const vm = newVM().login().advance(3.1);
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

const lines = (vm, expr) => { const v = vm.json(expr); return Array.isArray(v) ? v : Object.values(v || {}); };

test('the quest log: the mark shows with a quest\'s details, and hovering it gives local facts (no AI)', () => {
  const vm = newVM().login().advance(3.1);
  assert.equal(vm.evaluate('type(SpellmindQuestMark)'), 'table', 'made at login on the quest panel\'s details');
  assert.equal(vm.evaluate('tostring(SpellmindQuestMark.parent == QuestMapFrame.DetailsFrame)'), 'true');
  assert.equal(vm.evaluate('tostring(SpellmindQuestMark:IsShown())'), 'false', 'hidden until a quest\'s details open');
  vm.run('QuestMapFrame_ShowQuestDetails(297)');
  assert.equal(vm.evaluate('tostring(SpellmindQuestMark:IsShown())'), 'true');
  assert.equal(vm.num('SpellmindQuestMark.questID'), 297);
  vm.run('SpellmindQuestMark.scripts.OnEnter(SpellmindQuestMark)');
  const tip = lines(vm, 'GameTooltip.added');
  assert.match(tip[0], /^Level 18 quest: .*orange.*a few levels above you \(you're 15\)$/, tip[0]);
  assert.ok(tip.includes('Left: Carved Stone Idol 0/8'), JSON.stringify(tip));
  assert.ok(tip.includes('On your map: 70.6, 25 (about 560 yd)'), JSON.stringify(tip));
  assert.ok(tip.includes('Rewards: 6s 50c, 1350 XP, choose 1 of 3 (2 you can use)'), JSON.stringify(tip));
  assert.match(tip.at(-1), /Click: Explain\. Shift-click: ask in the chat window\./);
  // A quest ready to turn in says so instead of what's left.
  vm.run('QuestMapFrame_ShowQuestDetails(1338); SpellmindQuestMark.scripts.OnEnter(SpellmindQuestMark)');
  assert.ok(lines(vm, 'GameTooltip.added').some(l => /Ready to turn in/.test(l)));
  assert.equal(vm.json('STUB.questHeaders') && Object.keys(vm.json('STUB.questHeaders')).length, 0, 'no quest header touched');
});

test('/sm marks off hides the mark and the tooltip line; /sm marks on brings them back', () => {
  const vm = newVM().login().advance(3.1);
  vm.run('QuestMapFrame_ShowQuestDetails(297)');
  vm.slash('marks off');
  assert.equal(vm.evaluate('tostring(SpellmindQuestMark:IsShown())'), 'false');
  vm.run('QuestMapFrame_ShowQuestDetails(297)');
  assert.equal(vm.evaluate('tostring(SpellmindQuestMark:IsShown())'), 'false', 'stays hidden while off');
  assert.deepEqual(lines(vm, `STUB.ShowItem(GameTooltip, STUB.ItemLink(4936))`), [], 'no tooltip line while off');
  vm.slash('marks on');
  vm.run('QuestMapFrame_ShowQuestDetails(297)');
  assert.equal(vm.evaluate('tostring(SpellmindQuestMark:IsShown())'), 'true');
});

test('Break it down: the turn gets the quest as focus (text, objectives, rewards, where); the answer goes to the card, not the chat frame', async (t) => {
  const seen = [];
  const { vm, round } = rig(t, async (a) => { seen.push(a); return { text: 'Worth doing now: the idols drop from troggs.\n• Kill troggs in the valley east of you.\n• Take the gloves.' }; });
  await round(); // the hello answered: caps state and z
  vm.run('QuestMapFrame_ShowQuestDetails(297)');
  vm.run('SpellmindQuestMark:Click()');
  assert.equal(vm.evaluate('tostring(SpellmindCard:IsShown())'), 'true', 'the card opens at once');
  assert.equal(vm.evaluate('SpellmindCard.title:GetText()'), 'Break it down: Gathering Idols');
  assert.match(lines(vm, 'SpellmindCard.lines')[0], /Thinking/);
  assert.equal(vm.evaluate('tostring(SpellmindCard.anchor.rel == WorldMapFrame)'), 'true', 'beside the map');
  for (let i = 0; i < 12 && !seen.length; i++) await round();
  assert.equal(seen.length, 1, 'one turn');
  const g = seen[0].game;
  assert.equal(seen[0].text, 'Break this quest down for me.');
  assert.equal(g.about, 'quest:297');
  const f = g.state.focus;
  assert.equal(f.kind, 'quest');
  assert.equal(f.id, 297);
  assert.equal(f.title, 'Gathering Idols');
  assert.equal(f.level, 18);
  assert.equal(f.diff, 'VeryDifficult');
  assert.equal(f.complete, false);
  assert.match(f.text, /^The troggs in the Valley of Kings carry stone idols\./);
  assert.equal(f.goal, 'Bring 8 Carved Stone Idols to Prospector Ironband.');
  assert.deepEqual(f.obj, [{ text: 'Carved Stone Idol', have: 0, need: 8 }]);
  assert.equal(f.money, 650);
  assert.equal(f.xp, 1350);
  assert.deepEqual(f.choices.map(c => [c.name, c.usable]), [["Ironband's Gloves", true], ['Trogg Mace', false], ['Idol Cloak', true]]);
  assert.deepEqual(f.where, { zone: 'Loch Modan', x: 70.6, y: 25, dist: 560 });
  // What the model gets: the focus inside the fenced block, and the note that the message is about it.
  const req = buildRequest({ pack: loadPack(), game: g, history: [], userText: seen[0].text, nonce: 'abcd1234' });
  const user = req.messages.at(-1).content;
  assert.match(user, /"focus":\{"v":1,"kind":"quest","id":297,"title":"Gathering Idols"/);
  assert.ok(user.includes(JSON.stringify(FOCUS_NOTE)), 'the focus note');
  for (let i = 0; i < 4; i++) await round();
  const card = lines(vm, 'SpellmindCard.lines');
  assert.equal(card[0], 'Worth doing now: the idols drop from troggs.');
  assert.equal(card.length, 3);
  assert.ok(!vm.chatLines().some(l => /Worth doing now/.test(l)), 'not in the chat frame: the card showed it');
  const win = vm.savedLines(); // the window's lines (it isn't built until opened)
  assert.ok(win.some(l => /Break it down: Gathering Idols/.test(l)), 'the window keeps the question');
  assert.ok(win.some(l => /Worth doing now/.test(l)), 'and the answer');
});

test('Ask more: the chat window\'s next question is about the same quest (its focus goes again); closing the card ends that', async (t) => {
  const seen = [];
  const { vm, round } = rig(t, async (a) => { seen.push(a); return { text: 'Sure.' }; });
  await round();
  vm.run('QuestMapFrame_ShowQuestDetails(297)');
  vm.run('SpellmindQuestMark:Click()');
  for (let i = 0; i < 12 && seen.length < 1; i++) await round();
  for (let i = 0; i < 3; i++) await round();
  vm.run('SpellmindCard.more.scripts.OnClick()');
  assert.equal(vm.evaluate('tostring(SpellmindWindow:IsShown())'), 'true', 'the chat window opens');
  assert.match(vm.evaluate('SpellmindWindow.status:GetText()'), /About: Break it down: Gathering Idols/);
  vm.run('SpellmindWindow.input:SetText("Which reward is best for me?"); SpellmindWindow.input.scripts.OnEnterPressed(SpellmindWindow.input)');
  for (let i = 0; i < 12 && seen.length < 2; i++) await round();
  assert.equal(seen[1].game.about, 'quest:297', 'the follow-up is about the quest');
  assert.equal(seen[1].game.state.focus.id, 297);
  vm.run('SpellmindCard:Hide()');
  assert.doesNotMatch(vm.evaluate('SpellmindWindow.status:GetText()'), /About:/);
  for (let i = 0; i < 3; i++) await round();
  vm.run('SpellmindWindow.input:SetText("And now?"); SpellmindWindow.input.scripts.OnEnterPressed(SpellmindWindow.input)');
  for (let i = 0; i < 12 && seen.length < 3; i++) await round();
  assert.equal(seen[2].game.about, undefined);
  const req = buildRequest({ pack: loadPack(), game: seen[2].game, history: [], userText: 'And now?', nonce: 'abcd1234' });
  assert.doesNotMatch(req.messages.at(-1).content, /"focus"/, 'a message about nothing in particular gets no focus');
});

test('Explain with game data off says how to turn it on and sends nothing', () => {
  const vm = newVM().login().advance(3.1);
  vm.slash('data off');
  vm.run('QuestMapFrame_ShowQuestDetails(297)');
  vm.run('SpellmindQuestMark:Click()');
  assert.ok(vm.windowLines().some(l => /Explain needs your game data/.test(l)) || vm.chatLines().some(l => /Explain needs your game data/.test(l)));
  assert.equal(vm.evaluate('tostring(SpellmindCard == nil or not SpellmindCard:IsShown())'), 'true');
});

test('shift-click puts the question in the chat box to edit first, about the quest', () => {
  const vm = newVM().login().advance(3.1);
  vm.run('QuestMapFrame_ShowQuestDetails(297); STUB.shift = true; SpellmindQuestMark:Click(); STUB.shift = false');
  assert.equal(vm.evaluate('SpellmindWindow.input:GetText()'), 'Break this quest down for me.');
  assert.equal(vm.evaluate('tostring(SpellmindWindow.input:HasFocus())'), 'true');
  assert.match(vm.evaluate('SpellmindWindow.status:GetText()'), /About: Break it down: Gathering Idols/);
});

test('the tooltip line: what a red requirement means (a skill to learn, a level), an empty slot, or the stat differences against what\'s worn', () => {
  const vm = newVM().login().advance(3.1);
  const show = id => lines(vm, `STUB.ShowItem(GameTooltip, STUB.ItemLink(${id}))`);
  assert.deepEqual(show(2504), ['|cff9d7dffSpellmind:|r no Bows skill yet: a weapon master may teach it'], 'Ranged and Bow in red: a skill, maybe learnable');
  assert.deepEqual(show(5404), ['|cff9d7dffSpellmind:|r needs level 18'], 'a level requirement in red');
  assert.deepEqual(show(4936), ['|cff9d7dffSpellmind:|r fills your empty Back slot']);
  assert.deepEqual(show(2140), ['|cff9d7dffSpellmind:|r +0.9 dps, +2 Str vs your Craftsman\'s Dagger'], 'against the main hand');
  assert.deepEqual(show(2218), [], 'the dagger it wears: nothing to say');
  assert.deepEqual(show(6948), [], 'not wearable: no line');
  assert.deepEqual(lines(vm, `STUB.ShowItem(ShoppingTooltip1 or CreateFrame("Frame", "ShoppingTooltip1"), STUB.ItemLink(4936))`), [], 'comparison tooltips stay the game\'s');
});
