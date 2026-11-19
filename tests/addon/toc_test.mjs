// Spellmind: adapted from NeverQuestAlone's tests/order_check.js (MIT; see NOTICE.md).
// The addon's files as the game loads them: the TOC (its fields and load order), every file parsing
// as Lua with each top-level local defined before its first use, the names the app uses (slots,
// doorbells, version), the pasted key check equal to its generator's, and a NOTICE line for every
// file adapted from NeverQuestAlone.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { ADDON, ROOT, tocFiles } from '../helpers/addon-vm.mjs';
import { luaKeyCheckSource } from '../../core/ai/security/keycheck.mjs';
import { SLOT_PREFIX, SLOT_COUNT } from '../../core/link/slots.mjs';
import { signalPaths, BELLS } from '../../core/link/signals.mjs';
import { SERVICE_VERSION } from '../../core/link/service.mjs';

const require = createRequire(import.meta.url);
const { lua, lauxlib, to_luastring, to_jsstring } = require('fengari');
const read = f => fs.readFileSync(path.join(ADDON, f), 'utf8');

test('the TOC: interface 16001, the title, the notes, SpellmindDB, and every file in load order with the codec first', () => {
  const toc = read('Spellmind.toc');
  const field = name => (toc.match(new RegExp(`^## ${name}: (.*)$`, 'm')) || [])[1];
  assert.equal(field('Interface'), '16001');
  assert.equal(field('Title'), 'Spellmind');
  assert.equal(field('Notes'), 'Spellmind: AI Companion. Quest, dungeon, gear and spell help in game; ask your own AI with the free Spellmind app.');
  assert.equal(field('SavedVariables'), 'SpellmindDB');
  assert.deepEqual(tocFiles(), ['Codec.lua', 'Inbox.lua', 'Core.lua', 'Link.lua', 'State.lua', 'Probe.lua', 'Window.lua', 'Chat.lua', 'Marks.lua', 'Quests.lua', 'Tooltip.lua', 'Gear.lua', 'GearUI.lua', 'Professions.lua', 'Trainer.lua', 'Settings.lua', 'Dungeons.lua', 'Gold.lua', 'Guide.lua', 'World.lua', 'Advisor.lua', 'Panel.lua', 'Nudges.lua', 'Minimap.lua', 'Route.lua', 'Welcome.lua']);
  const onDisk = fs.readdirSync(ADDON).filter(f => f.endsWith('.lua')).sort();
  assert.deepEqual([...tocFiles()].sort(), onDisk, 'every Lua file is listed, and every listed one exists');
  const version = read('Core.lua').match(/^ns\.VERSION = "([^"]+)"/m)[1];
  assert.equal(field('Version'), version, 'the TOC says the addon\'s version');
  assert.equal(version.split('.')[0], SERVICE_VERSION.split('.')[0], 'the app\'s major version, which the addon checks');
});

test('every file parses as Lua, and every top-level local is defined before its first use', () => {
  for (const f of tocFiles()) {
    const src = read(f);
    const L = lauxlib.luaL_newstate();
    const status = lauxlib.luaL_loadbuffer(L, to_luastring(src), null, to_luastring(f));
    assert.equal(status, lua.LUA_OK, `${f}: ${status === lua.LUA_OK ? '' : to_jsstring(lua.lua_tostring(L, -1))}`);
    // Comments blanked, so a name mentioned in prose doesn't count as a use.
    const code = src.replace(/--\[\[[\s\S]*?\]\]|--[^\n]*/g, m => m.replace(/[^\n]/g, ' '));
    const forward = new Set([...code.matchAll(/^local (\w+)\s*$/gm)].map(m => m[1]));
    const defs = [
      ...[...code.matchAll(/^local function (\w+)/gm)].map(m => ({ name: m[1], at: m.index, call: true })),
      ...[...code.matchAll(/^local (\w+)\s*=/gm)].map(m => ({ name: m[1], at: m.index, call: false })),
    ];
    for (const d of defs) {
      if (forward.has(d.name)) continue;
      const use = d.call ? new RegExp(`(?<![\\w.:])${d.name}\\s*\\(`, 'g') : new RegExp(`(?<![\\w.:])${d.name}(?![\\w])`, 'g');
      for (const m of code.matchAll(use)) assert.ok(m.index >= d.at, `${f}: ${d.name} used before it's defined (line ${code.slice(0, m.index).split('\n').length})`);
    }
  }
});

test('the names the app writes: slot addons, the slot and inbox globals, the doorbells', () => {
  const core = read('Core.lua');
  const str = name => core.match(new RegExp(`^ns\\.${name} = "([^"]*)"`, 'm'))[1].replace(/\\\\/g, '\\');
  assert.equal(str('SLOT_PREFIX'), SLOT_PREFIX);
  assert.equal(Number(core.match(/^ns\.SLOT_COUNT = (\d+)/m)[1]), SLOT_COUNT);
  assert.equal(str('SLOT_GLOBAL'), 'SpellmindSlotData');
  assert.equal(str('INBOX_GLOBAL'), 'SpellmindInbox');
  const sig = signalPaths('Interface/AddOns');
  assert.equal(str('SIG'), sig.root.split(/[\\/]/).join('\\') + '\\');
  const link = read('Link.lua');
  const bells = JSON.parse(link.match(/^local BELLS = \{([^}]*)\}/m)[1].replace(/^\s*/, '[').replace(/\s*$/, ']'));
  for (const b of bells) assert.ok(BELLS.includes(b), `${b} is a bell the app rings`);
  assert.match(link, /SpellmindSlotData = nil/);
  assert.match(read('Inbox.lua'), /^SpellmindInbox = nil$/m);
});

test('the key check pasted into Chat.lua is exactly what core/ai/security/keycheck.mjs generates', () => {
  assert.ok(read('Chat.lua').includes(luaKeyCheckSource({ assign: 'local LooksLikeKey' }) + '\n'),
    'regenerate it: node -e "import(\'./core/ai/security/keycheck.mjs\').then(m => console.log(m.luaKeyCheckSource({ assign: \'local LooksLikeKey\' })))"');
});

test('every file adapted from NeverQuestAlone says so on its first line and has its NOTICE.md line', () => {
  const notice = fs.readFileSync(path.join(ROOT, 'NOTICE.md'), 'utf8');
  const dirs = ['addon/Spellmind', 'tests/helpers', 'tests/addon'];
  let n = 0;
  for (const dir of dirs) {
    for (const f of fs.readdirSync(path.join(ROOT, dir))) {
      if (!fs.statSync(path.join(ROOT, dir, f)).isFile()) continue; // Media/ and the like
      const rel = `${dir}/${f}`;
      const first = fs.readFileSync(path.join(ROOT, dir, f), 'utf8').split('\n')[0];
      const m = first.match(/^(?:--|\/\/) Spellmind: adapted from NeverQuestAlone's (\S+) \(MIT; see NOTICE\.md\)[.,]/);
      if (!m) continue;
      n++;
      assert.ok(notice.includes(`- \`${rel}\` ← \`${m[1]}`), `NOTICE.md lists ${rel} ← ${m[1]}`);
    }
  }
  for (const f of ['Core.lua', 'Link.lua', 'State.lua', 'Chat.lua', 'Inbox.lua']) assert.match(read(f).split('\n')[0], /adapted from NeverQuestAlone's/, f);
  assert.ok(n >= 9, `${n} adapted files`);
});

test('the art: every texture the addon and its slots name is in Media as a 32-bit TGA with power-of-two sides', () => {
  const named = new Set();
  const sources = [read('Spellmind.toc'), ...tocFiles().map(read), fs.readFileSync(path.join(ROOT, 'core/link/slots.mjs'), 'utf8')];
  for (const src of sources) {
    for (const m of src.matchAll(/Interface\\{1,2}AddOns\\{1,2}Spellmind\\{1,2}Media\\{1,2}(\w+)/g)) named.add(m[1]);
    for (const m of src.matchAll(/MEDIA \.\. "(\w+)"/g)) named.add(m[1]); // Window.lua's W.MEDIA .. "Corner"
  }
  assert.deepEqual([...named].sort(), ['Area', 'Badge', 'Chevron', 'Corner', 'Dot', 'Mark', 'Portrait', 'Send', 'Spellmind']);
  for (const name of named) {
    const file = path.join(ADDON, 'Media', `${name}.tga`);
    assert.ok(fs.existsSync(file), `${name}.tga is there`);
    const b = fs.readFileSync(file);
    const [w, h, bpp] = [b.readUInt16LE(12), b.readUInt16LE(14), b[16]];
    assert.equal(b[2], 2, `${name}: uncompressed true-colour`);
    assert.equal(bpp, 32, `${name}: has alpha`);
    for (const side of [w, h]) assert.equal(side & (side - 1), 0, `${name}: ${w}x${h} is a power of two`);
  }
});
