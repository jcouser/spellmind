// Milestone 12 (docs/milestone-12.md): the Settings tab. Every switch in one place: the marks on the
// game's windows, each kind of nudge, each part of the game data, the answers in the game's chat and
// the minimap button. Each lives where its slash command keeps it, so the two always agree.
import test from 'node:test';
import assert from 'node:assert/strict';
import { newVM, reloadVM } from '../helpers/addon-vm.mjs';
import { validatePart } from '../../core/link/charstate.mjs';
import { partNotes } from '../../core/ai/context.mjs';

const list = (vm, expr) => { const v = vm.json(expr); return Array.isArray(v) ? v : Object.values(v || {}); };
const session = () => newVM().login().advance(9);
const label = (vm, id) => vm.evaluate(`NS.Settings.Label(NS.Settings.Row("${id}"))`);
const flip = (vm, id) => vm.run(`NS.Settings.Flip("${id}")`);

test('the tab: last in the rail; its sections, each switch with its On or Off button', () => {
  const vm = session();
  vm.run('NS.Panel.Show("settings")');
  assert.equal(vm.evaluate('SpellmindPanel.tabs[10].text:GetText()'), 'Settings');
  const d = list(vm, 'SpellmindPanel.drawn');
  assert.deepEqual(d.filter(x => x.kind === 'head').map(x => x.text),
    ['The Spellmind app', 'On the game\'s windows', 'Quest route', 'Nudges', 'Game data the AI gets', 'Chat and the minimap', 'Your guide']);
  // The app's section (the audit): running or not, the addon's version; nothing to switch there.
  const app = d.find(x => x.text === 'App');
  assert.ok(app && /running/.test(app.right));
  assert.ok(d.some(x => x.text === 'Addon' && /^version /.test(x.right)));
  assert.ok(d.some(x => x.text === 'Item tooltips'));
  assert.ok(d.some(x => x.text === 'Spells to train'));
  assert.ok(d.some(x => x.text === 'Reputations'));
  // The first switch, found by its name.
  const row = d.findIndex(x => x.text === 'Quest log: Break it down') + 1;
  assert.ok(row > 0);
  assert.equal(vm.evaluate(`SpellmindPanel.rows[${row}].actions[1].text:GetText()`), '|cff19ff19On|r');
  // A click flips it and redraws in place.
  vm.run(`SpellmindPanel.rows[${row}].actions[1].scripts.OnClick(SpellmindPanel.rows[${row}].actions[1], "LeftButton")`);
  assert.equal(vm.evaluate(`SpellmindPanel.rows[${row}].actions[1].text:GetText()`), '|cff888888Off|r');
  assert.equal(vm.evaluate('tostring(SpellmindDB.marks.quest)'), 'false');
});

test('marks: one off at a time; after /sm marks off, turning one on leaves the others off', () => {
  const vm = session();
  flip(vm, 'mark:tooltip');
  assert.equal(vm.evaluate('tostring(NS.Marks.On("tooltip"))'), 'false');
  assert.equal(vm.evaluate('tostring(NS.Marks.On("merchant"))'), 'true');
  vm.slash('marks off');
  assert.equal(label(vm, 'mark:merchant'), '|cff888888Off|r');
  flip(vm, 'mark:merchant');
  assert.equal(vm.evaluate('tostring(NS.Marks.On("merchant"))'), 'true');
  assert.equal(vm.evaluate('tostring(NS.Marks.On("sheet"))'), 'false', 'still off, as /sm marks off left it');
  assert.equal(vm.evaluate('tostring(SpellmindDB.marks.all)'), 'nil');
});

test('a kind of nudge off: its waiting one goes, and it doesn\'t come back; on again, it does', () => {
  const vm = session();
  assert.equal(vm.evaluate('SpellmindNudge.title:GetText()'), 'A spell to train');
  flip(vm, 'nudge:spells');
  assert.equal(vm.evaluate('tostring(SpellmindNudge.shown)'), 'false');
  assert.equal(list(vm, 'NS.Nudges.List()').length, 0);
  vm.run('NS.Nudges.Check()');
  vm.advance(4);
  assert.equal(list(vm, 'NS.Nudges.List()').length, 0, 'not detected while off');
  assert.equal(vm.evaluate('tostring(SpellmindDB.nudges.kinds.spells)'), 'false');
  flip(vm, 'nudge:spells');
  vm.advance(4);
  assert.equal(list(vm, 'NS.Nudges.List()')[0].title, 'A spell to train');
});

test('nudges off greys the kinds under it', () => {
  const vm = session();
  flip(vm, 'nudges');
  vm.run('NS.Panel.Show("settings")');
  const d = list(vm, 'SpellmindPanel.drawn');
  assert.ok(d.some(x => x.text === '|cff888888Spells to train|r'));
});

test('a part of the game data kept back: sent as off (valid, and the AI is told); kept over a /reload; the report says so', () => {
  const vm = session();
  flip(vm, 'part:bags');
  const json = vm.evaluate('(NS.State.Part("bags", false))');
  assert.equal(json, '{"v":1,"off":true}');
  assert.equal(validatePart('bags', json).ok, true);
  assert.ok(partNotes({ bags: JSON.parse(json) }).some(n => /bags: the player keeps this back/.test(n)));
  assert.match(vm.evaluate('NS.State.Part("gear", false)'), /"items"/, 'the others still go');
  assert.equal(vm.evaluate('tostring(NS.Settings.Row("part:char"))'), 'nil', 'class, level and zone always go: no switch');
  const back = reloadVM(vm).login();
  assert.equal(back.evaluate('tostring(NS.State.PartOn("bags"))'), 'false');
  back.run('NS.R.caps = { state = true }');
  assert.ok(list(back, 'NS.State.Report()').includes('Bags: off in Settings'));
});

test('answers in the game\'s chat: Whole, First line, Off; off, a reply shows only in the window', () => {
  const vm = session();
  assert.equal(label(vm, 'chatLines'), '|cff19ff19Full answer|r');
  flip(vm, 'chatLines');
  assert.equal(label(vm, 'chatLines'), '|cff19ff19First line|r');
  vm.run('NS.Chat.OnRecord({ t = "reply", text = "Train Sprint.\\nThen Kick." })');
  assert.ok(vm.chatLines().includes('Spellmind: Train Sprint. ... |cff888888(more: /sm)|r'), JSON.stringify(vm.chatLines()));
  flip(vm, 'chatLines');
  assert.equal(label(vm, 'chatLines'), '|cff888888Off|r');
  const before = vm.chatLines().length;
  vm.run('NS.Chat.OnRecord({ t = "reply", text = "Sell the grey items." })');
  assert.equal(vm.chatLines().length, before, 'nothing in the chat frame');
  assert.ok(vm.savedLines().some(l => /Sell the grey items/.test(l)), 'the window has it');
  flip(vm, 'chatLines');
  assert.equal(vm.evaluate('tostring(SpellmindDB.ui.chatLines)'), 'nil', 'back to Whole');
});

test('the minimap button: off hides it, as /sm minimap off does', () => {
  const vm = session();
  flip(vm, 'minimap');
  assert.equal(vm.evaluate('tostring(SpellmindMinimapButton.shown)'), 'false');
  assert.equal(vm.evaluate('tostring(SpellmindDB.minimap.hide)'), 'true');
  vm.slash('minimap on');
  assert.equal(label(vm, 'minimap'), '|cff19ff19On|r');
});

test('Double-check facts: on unless turned off; off sends check=0 with each message', () => {
  const vm = session();
  assert.equal(label(vm, 'check'), '|cff19ff19On|r');
  flip(vm, 'check');
  assert.equal(vm.evaluate('tostring(SpellmindDB.ui.check)'), 'false');
  vm.slash('where is the bank?');
  const f = vm.outbox().at(-1).wire.split('\u001f');
  assert.match(f[5], /(^|;)check=0(;|$)/);
});
