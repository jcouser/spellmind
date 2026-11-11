// Milestone 6 (docs/milestone-6.md): the chat window redesign. Bubbles (yours right, Spellmind's left
// with the owl), the header's thinking dropdown and web search toggle from the app's bridge.ai, the
// reply's chips, shift-clicked links into the box (an item goes as the focus part), the minimap
// button, folding and the saved place. The real addon in the VM and the real service.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { newVM } from '../helpers/addon-vm.mjs';
import { findAndDecode } from '../../core/link/strip.mjs';
import { createService } from '../../core/link/service.mjs';
import { buildRequest } from '../../core/ai/context.mjs';

const AI = { name: 'ChatGPT', model: 'GPT-6 Luna', efforts: ['low', 'medium', 'high'], effort: 'medium', search: true, searchOn: true };

function ring(vm) {
  const bell = vm.pushBell = vm.pushBell === 'push_a' ? 'push_b' : 'push_a';
  vm.run('NS.Link.Poll()');
  vm.bell(`bell_${bell}`, false).run('NS.Link.Poll()');
  vm.bell(`bell_${bell}`, true).run('NS.Link.Poll()');
}

function rig(t, turn, { ai = AI } = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'sm-window-'));
  const addonsDir = path.join(root, 'AddOns');
  fs.mkdirSync(path.join(addonsDir, 'Spellmind', 'sig', 'ctl'), { recursive: true });
  for (let i = 1; i <= 3; i++) fs.mkdirSync(path.join(addonsDir, `Spellmind_S00${i}`), { recursive: true });
  const svc = createService({ addonsDir, stateDir: path.join(root, 'state'), slotCount: 3, timers: false, ackRingMs: 0, turn, ai });
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

const list = (vm, expr) => { const v = vm.json(expr); return Array.isArray(v) ? v : Object.values(v || {}); };
const type = (vm, text) => vm.run(`SpellmindWindow.input:SetText(${JSON.stringify(text)}); SpellmindWindow.input.scripts.OnEnterPressed(SpellmindWindow.input)`);

test('bubbles and chips: your message on the right, the reply on the left with the owl and its three chips; a chip asks', async (t) => {
  const seen = [];
  const { vm, round } = rig(t, async (a) => { seen.push(a); return { text: seen.length === 1 ? "Not yet: no Bows skill.\n\nNext: Where's Darnassus? / Compare with Cheese Knife / What do I train next?" : 'Northwest of Ashenvale, across the sea.' }; });
  await round();
  vm.slash('');
  type(vm, 'Should I keep the bow?');
  for (let i = 0; i < 12 && !seen.length; i++) await round();
  for (let i = 0; i < 4; i++) await round();
  assert.deepEqual(vm.windowLines(), ['Should I keep the bow?', 'Not yet: no Bows skill.']);
  assert.equal(vm.evaluate('SpellmindWindow.rows[1].anchor.point'), 'TOPRIGHT', 'yours: right');
  assert.equal(vm.evaluate('SpellmindWindow.rows[2].anchor.point'), 'TOPLEFT', 'Spellmind\'s: left');
  assert.equal(vm.evaluate('tostring(SpellmindWindow.rows[2].icon.shown)'), 'true', 'with the owl');
  assert.deepEqual(list(vm, 'SpellmindWindow.chipTexts'), ["Where's Darnassus?", 'Compare with Cheese Knife', 'What do I train next?']);
  vm.run('SpellmindWindow.chips[1].scripts.OnClick(SpellmindWindow.chips[1])');
  for (let i = 0; i < 12 && seen.length < 2; i++) await round();
  assert.equal(seen[1].text, "Where's Darnassus?", 'the chip is the question');
  for (let i = 0; i < 4; i++) await round();
  assert.deepEqual(list(vm, 'SpellmindWindow.chipTexts'), [], 'a reply without a Next: line has none, and the old ones go');
  assert.ok(list(vm, 'SpellmindDB.msgs').length >= 4, 'kept for the next session');
});

test('the header: thinking and web search from the app; a pick goes with the next message, and is saved', async (t) => {
  const seen = [];
  const { vm, round } = rig(t, async (a) => { seen.push(a); return { text: 'Ok.' }; });
  await round();
  vm.slash('');
  vm.run('NS.Window.Refresh()');
  assert.equal(vm.evaluate('tostring(SpellmindWindow.effort.shown)'), 'true');
  assert.equal(vm.evaluate('SpellmindWindow.effort.text:GetText()'), 'Thinking: Medium v', 'the app\'s default');
  assert.match(vm.evaluate('SpellmindWindow.search.text:GetText()'), /Web search: .*On/);
  assert.match(vm.evaluate('SpellmindWindow.status:GetText()'), /^Connected · ChatGPT · GPT-6 Luna/);
  vm.run('SpellmindWindow.effort.scripts.OnClick(SpellmindWindow.effort)');
  assert.equal(vm.evaluate('tostring(SpellmindEffortMenu.shown)'), 'true', 'the menu opens');
  assert.equal(vm.num('#SpellmindEffortMenu.rows'), 3);
  vm.run('SpellmindEffortMenu.rows[3].scripts.OnClick(SpellmindEffortMenu.rows[3])');
  assert.equal(vm.evaluate('SpellmindDB.ui.effort'), 'high');
  assert.equal(vm.evaluate('SpellmindWindow.effort.text:GetText()'), 'Thinking: High v');
  vm.run('SpellmindWindow.search.scripts.OnClick(SpellmindWindow.search)');
  assert.match(vm.evaluate('SpellmindWindow.search.text:GetText()'), /Off/);
  type(vm, 'think hard');
  for (let i = 0; i < 12 && !seen.length; i++) await round();
  assert.equal(seen[0].effort, 'high');
  assert.equal(seen[0].search, false);
});

test('an app without bridge.ai: no thinking or search controls, and no effort= sent', async (t) => {
  const seen = [];
  const { vm, round } = rig(t, async (a) => { seen.push(a); return { text: 'Ok.' }; }, { ai: null });
  await round();
  vm.slash('');
  assert.equal(vm.evaluate('tostring(SpellmindWindow.effort.shown)'), 'false');
  assert.equal(vm.evaluate('tostring(SpellmindWindow.search.shown)'), 'false');
  vm.run('SpellmindDB.ui.effort = "high"');
  type(vm, 'hi');
  for (let i = 0; i < 12 && !seen.length; i++) await round();
  assert.equal(seen[0].effort, undefined);
});

test('links: a shift-clicked item goes into the box; sent, it shows green, the AI gets [Name] and the item as focus', async (t) => {
  const seen = [];
  const { vm, round } = rig(t, async (a) => { seen.push(a); return { text: 'Not yet.' }; });
  await round();
  vm.slash('');
  vm.run('SpellmindWindow.input:SetText("Should I keep "); ChatEdit_InsertLink(STUB.ItemLink(2504)); SpellmindWindow.input:Insert("?")');
  assert.match(vm.evaluate('SpellmindWindow.input:GetText()'), /\|Hitem:2504:.*\|h\[Worn Shortbow\]\|h/, 'the link went into the focused box');
  vm.run('SpellmindWindow.input.scripts.OnEnterPressed(SpellmindWindow.input)');
  assert.equal(vm.windowLines()[0], 'Should I keep |cff1eff00[Worn Shortbow]|r?', 'the link green, nothing else live');
  for (let i = 0; i < 12 && !seen.length; i++) await round();
  assert.equal(seen[0].text, 'Should I keep [Worn Shortbow]?');
  assert.equal(seen[0].game.about, 'item:2504');
  const f = seen[0].game.state.focus;
  assert.equal(f.kind, 'item');
  assert.equal(f.name, 'Worn Shortbow');
  assert.equal(f.sub, 'Bows');
  assert.equal(f.usable, false);
  assert.equal(f.why, 'no Bows skill yet: a weapon master may teach it');
  const req = buildRequest({ pack: 'P', game: seen[0].game, userText: seen[0].text, nonce: 'abcd' });
  assert.match(req.messages.at(-1).content, /"focus":\{"v":1,"kind":"item","id":2504/);
});

test('a link clicked while the box isn\'t focused stays out of it', () => {
  const vm = newVM().login().advance(3.1);
  vm.slash('');
  vm.run('SpellmindWindow.input:ClearFocus(); ChatEdit_InsertLink(STUB.ItemLink(2504))');
  assert.equal(vm.evaluate('SpellmindWindow.input:GetText()'), '');
});

test('the minimap button: click opens and closes the chat; /sm minimap off hides it', () => {
  const vm = newVM().login().advance(3.1);
  assert.equal(vm.evaluate('type(SpellmindMinimapButton)'), 'table');
  assert.equal(vm.evaluate('tostring(SpellmindMinimapButton.parent == Minimap)'), 'true');
  vm.run('SpellmindMinimapButton.scripts.OnClick(SpellmindMinimapButton, "LeftButton")');
  assert.equal(vm.evaluate('tostring(SpellmindWindow.shown)'), 'true');
  vm.run('SpellmindMinimapButton.scripts.OnClick(SpellmindMinimapButton, "LeftButton")');
  assert.equal(vm.evaluate('tostring(SpellmindWindow.shown)'), 'false');
  vm.slash('minimap off');
  assert.equal(vm.evaluate('tostring(SpellmindMinimapButton.shown)'), 'false');
  assert.equal(vm.evaluate('tostring(SpellmindDB.minimap.hide)'), 'true');
  vm.slash('minimap on');
  assert.equal(vm.evaluate('tostring(SpellmindMinimapButton.shown)'), 'true');
});

test('fold and the saved place: the header only, and the size and spot kept', () => {
  const vm = newVM().login().advance(3.1);
  vm.slash('');
  vm.run('SpellmindWindow.mini.scripts.OnClick(SpellmindWindow.mini)');
  assert.equal(vm.evaluate('tostring(SpellmindDB.ui.folded)'), 'true');
  assert.equal(vm.evaluate('tostring(SpellmindWindow.input.shown)'), 'false');
  vm.run('SpellmindWindow.mini.scripts.OnClick(SpellmindWindow.mini)');
  assert.equal(vm.evaluate('tostring(SpellmindWindow.input.shown)'), 'true');
  vm.run('SpellmindWindow:SetSize(520, 480); SpellmindWindow.scripts.OnDragStop(SpellmindWindow)');
  assert.equal(vm.num('SpellmindDB.ui.w'), 520);
  assert.equal(vm.num('SpellmindDB.ui.h'), 480);
});

test('an empty conversation: a welcome and three starter chips; a starter asks; the window is solid, not see-through', () => {
  const vm = newVM().login().advance(3.1);
  vm.slash('');
  assert.equal(vm.evaluate('tostring(SpellmindWindow.welcome.shown)'), 'true');
  assert.match(vm.evaluate('SpellmindWindow.welcome:GetText()'), /^Ask me anything about your character/);
  assert.deepEqual(list(vm, 'SpellmindWindow.chipTexts'), ['What should I train next?', 'Any upgrades in my bags?', 'Which quests should I do now?']);
  assert.equal(vm.evaluate('tostring(SpellmindWindow.fill.color[4] >= 0.95)'), 'true', 'a solid fill under the window');
  vm.run('SpellmindWindow.chips[2].scripts.OnClick(SpellmindWindow.chips[2])');
  assert.equal(vm.windowLines()[0], 'Any upgrades in my bags?', 'then, with no app in this test, the note to start it');
  assert.equal(vm.evaluate('tostring(SpellmindWindow.welcome.shown)'), 'false', 'gone once something is said');
  assert.equal(vm.evaluate('tostring(SpellmindWindow.rows[1].fill.color[4])'), '1', 'bubbles are solid too');
});
