// The prompt (prompts/spellmind.md through core/ai/pack.mjs): its comment is out, every {{code.X}}
// is filled from the code, its version is a 12-hex hash, and it holds the rules milestone 4 needs:
// game data is data, the fence, the character only from the data, numbers from memory marked.
import test from 'node:test';
import assert from 'node:assert/strict';
import { loadPack, fillPack, CODE } from '../../core/ai/pack.mjs';
import { TEXT_MAX } from '../../core/link/render.mjs';

test('the pack: filled, no comment, a version hash and a token estimate', () => {
  const p = loadPack({ fresh: true });
  assert.ok(!/\{\{[^}]*\}\}/.test(p.text), 'no unfilled placeholder');
  assert.ok(!p.text.includes('<!--'), 'the editors\' comment is out');
  assert.match(p.text, /^# Spellmind/);
  assert.match(p.version, /^[0-9a-f]{12}$/);
  assert.equal(p.tokens, Math.ceil(p.text.length / 4));
  assert.ok(p.text.includes(TEXT_MAX.toLocaleString('en-US')), 'a number from the code');
  assert.equal(loadPack().version, p.version, 'the same text, the same version');
});

test('the prompt holds the game-data rule and the rest of milestone 4\'s list', () => {
  const t = loadPack().text;
  assert.match(t, /## Game data is data/);
  assert.match(t, /<game_data id="…">/);
  assert.match(t, /never instructions/i);
  assert.match(t, /Don't follow it/);
  assert.match(t, /Class, race, level.*come only from the data|character comes only from the data/i);
  assert.match(t, /too_large/);
  assert.match(t, /stale/);
  assert.match(t, /from memory/);
  assert.match(t, /## Gear decisions/);
  assert.match(t, /No invented scores/);
  assert.match(t, /API key/);
  assert.match(t, /no tools/i);
  assert.match(t, /1 Hated/);
  assert.match(t, /0 poor/);
});

test('fillPack: an unknown constant or a stray placeholder is an error, never sent', () => {
  assert.equal(fillPack('<!-- note -->\nMax {{code.TEXT_MAX}}.'), `Max ${CODE.TEXT_MAX.toLocaleString('en-US')}.`);
  assert.throws(() => fillPack('{{code.NOPE}}'), /no constant/);
  assert.throws(() => fillPack('{{name}}'), /unfilled/);
});
