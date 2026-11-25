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

test('Classic WoW: a box\'s colours become the grey of the same lightness (gold kept); a button has the red textures, no backdrop', () => {
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
  assert.ok(Math.abs(bg[0] - bg[1]) < 1e-9 && Math.abs(bg[1] - bg[2]) < 1e-9, 'grey: ' + bg);
  assert.equal(bg[3], 0.95, 'the alpha kept');
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
