// The look (Theme.lua; a player on CurseForge, 2026-11-25: "a traditional WoW theme, standard WoW frames and
// buttons"): Spellmind's by default; Classic WoW from the Settings tab, at the next /reload.
import test from 'node:test';
import assert from 'node:assert/strict';
import { newVM } from '../helpers/addon-vm.mjs';

const session = (db) => newVM(db ? { db } : {}).login().advance(9);

test('by default, Spellmind\'s own look: its backdrop, its purple fill and gold corners', () => {
  const vm = session();
  vm.run('NS.Panel.Show("quests")');
  assert.equal(vm.evaluate('NS.Theme.Look()'), 'spellmind');
  assert.match(vm.evaluate('SpellmindPanel.backdrop.edgeFile'), /Tooltips/);
  assert.equal(vm.evaluate('tostring(SpellmindPanel.fill and SpellmindPanel.fill.shown ~= false)'), 'true');
  assert.equal(vm.evaluate('tostring(SpellmindPanel.classicFill)'), 'nil');
});

test('Classic WoW: the windows in the Game Menu\'s dialog frame, no purple fill or gold corners', () => {
  const vm = session('SpellmindDB = { look = "classic" }');
  vm.run('NS.Panel.Show("route"); NS.Route.SetOn(true); NS.Welcome.Show()');
  assert.equal(vm.evaluate('NS.Theme.Look()'), 'classic');
  for (const w of ['SpellmindPanel', 'SpellmindWelcome']) {
    assert.match(vm.evaluate(`${w}.backdrop.edgeFile`), /DialogFrame\\UI-DialogBox-Border/, w);
    assert.equal(vm.evaluate(`tostring(${w}.classicFill ~= nil)`), 'true', w + ': a dark fill under the dialog');
  }
  assert.equal(vm.evaluate('tostring(SpellmindPanel.fill == nil or SpellmindPanel.fill.shown == false)'), 'true', 'no purple fill');
  assert.equal(vm.evaluate('tostring(SpellmindPanel.corners == nil)'), 'true', 'no gold corners');
});

test('Classic WoW: a box\'s purple becomes Blizzard\'s gold, its dark purple grey, other colours kept; a button has the red textures, no backdrop', () => {
  const vm = session('SpellmindDB = { look = "classic" }');
  const got = vm.json(`(function()
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    local seen = {}
    f.SetBackdropColor = function(self, r, g, b, a) seen.bg = { r, g, b, a } end
    f.SetBackdropBorderColor = function(self, r, g, b, a) seen.edge = { r, g, b, a } end
    NS.Theme.Adopt(f, "box")
    f:SetBackdropColor(0.32, 0.22, 0.62, 0.95)
    f:SetBackdropBorderColor(0.85, 0.68, 0.25, 1)
    local b = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
    NS.Theme.Adopt(b, "button")
    b:SetBackdrop({ bgFile = "x" })
    return { bg = seen.bg, edge = seen.edge, buttonBackdrop = b.backdrop == nil, classicButton = b.classicButton == true }
  end)()`);
  const bg = Array.isArray(got.bg) ? got.bg : Object.values(got.bg);
  assert.ok(bg[0] > bg[1] && bg[1] > bg[2], 'the selected purple turned gold: ' + bg);
  assert.equal(bg[3], 0.95, 'the alpha kept');
  const map = vm.json('{ dark = { NS.Theme.Map(0.07, 0.05, 0.14) }, green = { NS.Theme.Map(0.1, 1, 0.1) } }');
  const dark = Array.isArray(map.dark) ? map.dark : Object.values(map.dark);
  assert.ok(Math.abs(dark[0] - dark[1]) < 1e-9 && Math.abs(dark[1] - dark[2]) < 1e-9, 'a dark purple turned grey: ' + dark);
  const green = Array.isArray(map.green) ? map.green : Object.values(map.green);
  assert.deepEqual(green, [0.1, 1, 0.1], 'other colours kept');
  const edge = Array.isArray(got.edge) ? got.edge : Object.values(got.edge);
  assert.deepEqual(edge, [0.85, 0.68, 0.25, 1], 'gold stays gold');
  assert.equal(got.buttonBackdrop, true, 'no backdrop on a classic button');
  assert.equal(got.classicButton, true);
});

test('the Settings tab: Look, Spellmind or Classic WoW, from the next /reload', () => {
  const vm = session();
  assert.equal(vm.evaluate('NS.Settings.Row("look").get()'), 'spellmind');
  vm.run('NS.Settings.Flip("look")');
  assert.equal(vm.evaluate('SpellmindDB.look'), 'classic');
  assert.ok(vm.chatLines().some(l => /Classic WoW look comes in at your next \/reload/.test(l)));
  vm.run('NS.Settings.Flip("look")');
  assert.equal(vm.evaluate('tostring(SpellmindDB.look)'), 'nil', 'back to Spellmind\'s');
});

test('Classic WoW: scrollbars, rules and the windows\' text accents in gold, not purple', () => {
  const vm = session('SpellmindDB = { look = "classic" }');
  assert.equal(vm.evaluate('NS.Theme.Accent()'), '|cffffd100');
  const c = vm.json('{ NS.Theme.Color(0.62, 0.49, 1, 0.55) }');
  const col = Array.isArray(c) ? c : Object.values(c);
  assert.ok(col[0] > col[2] && col[3] === 0.55, 'the thumb gold: ' + col);
  const plain = session();
  assert.equal(plain.evaluate('NS.Theme.Accent()'), '|cffb48cff', 'Spellmind\'s look: its purple');
});

test('Classic WoW: the windows over the rock background of Blizzard\'s Options window, the dialog border around it', () => {
  const vm = session('SpellmindDB = { look = "classic" }');
  vm.run('NS.Panel.Show("quests")');
  assert.match(vm.evaluate('SpellmindPanel.classicFill:GetTexture()'), /UI-Background-Rock/);
  assert.equal(vm.evaluate('tostring(SpellmindPanel.backdrop.bgFile)'), 'nil', 'no black dialog background over it');
});
