// Milestone 3 (docs/milestone-3.md): the desktop app's pieces that run without Electron.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { addonState, ADDON_SOURCE } from '../../core/link/install.mjs';
import { aiChoices, applyAI } from '../../core/app/settings.mjs';
import { eventLine } from '../../core/app/lines.mjs';
import { readConfig, writeConfig, pickAI } from '../../core/app/runner.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const DESKTOP = path.join(HERE, '..', '..', 'app', 'desktop');
const tmp = () => fs.mkdtempSync(path.join(os.tmpdir(), 'spellmind-app-'));

test('the addon against the installed one: missing, current, then outdated (changed or new files told apart)', () => {
  const flavor = tmp();
  fs.mkdirSync(path.join(flavor, 'Interface', 'AddOns'), { recursive: true });
  assert.equal(addonState({ flavorDir: flavor }).state, 'missing');
  const dst = path.join(flavor, 'Interface', 'AddOns', 'Spellmind');
  fs.cpSync(ADDON_SOURCE, dst, { recursive: true });
  assert.deepEqual(addonState({ flavorDir: flavor }), { state: 'current', changed: 0, added: 0 });
  fs.appendFileSync(path.join(dst, 'Panel.lua'), '\n-- old\n');
  fs.rmSync(path.join(dst, 'Advisor.lua'));
  assert.deepEqual(addonState({ flavorDir: flavor }), { state: 'outdated', changed: 1, added: 1 });
  // The game's own files in the folder (the doorbells, the inbox the app writes) aren't the addon's.
  fs.cpSync(ADDON_SOURCE, dst, { recursive: true });
  fs.mkdirSync(path.join(dst, 'sig'), { recursive: true });
  fs.writeFileSync(path.join(dst, 'Inbox.lua'), '-- written by the app');
  assert.equal(addonState({ flavorDir: flavor }).state, 'current');
  assert.equal(addonState({ flavorDir: null }).state, 'missing');
});

test('the AI settings: the choices offered, and a change checked before it is saved', () => {
  const c = aiChoices({});
  assert.equal(c.provider, 'chatgpt');
  assert.equal(c.signIn, true);
  assert.ok(c.models.length > 0 && c.models.every(m => m.id && m.label));
  assert.ok(c.efforts.includes(c.effort));
  assert.equal(c.search, true, 'web search on by default');
  assert.deepEqual(applyAI({ wow: 'x' }, { effort: 'low', search: false }), { ok: true, cfg: { wow: 'x', effort: 'low', search: 'off' } });
  assert.equal(applyAI({}, { model: 'not-a-model' }).error, 'unknown_model');
  assert.equal(applyAI({}, { effort: 'ludicrous' }).error, 'unknown_effort');
  assert.equal(applyAI({}, { search: 'yes' }).error, 'bad_search');
  // The settings are what the link starts with.
  const p = pickAI({ effort: 'low', search: 'off' });
  assert.equal(p.effort, 'low');
  assert.equal(p.search, false);
});

test('config.json: read back as written; a missing or broken one reads as empty', () => {
  const dir = tmp();
  assert.deepEqual(readConfig(dir), {});
  writeConfig(dir, { wow: 'C:\\WoW\\_forever_', effort: 'high' });
  assert.deepEqual(readConfig(dir), { wow: 'C:\\WoW\\_forever_', effort: 'high' });
  fs.writeFileSync(path.join(dir, 'config.json'), '﻿{ "wow": "X" }');
  assert.deepEqual(readConfig(dir), { wow: 'X' }, 'saved by Notepad, with a byte-order mark');
  fs.writeFileSync(path.join(dir, 'config.json'), '{ not json');
  assert.deepEqual(readConfig(dir), {});
});

test('the Activity lines: the link\'s events in words; "window not found" kept quiet while WoW is closed', () => {
  assert.equal(eventLine({ kind: 'hello', ver: '0.1.0' }), 'The game said hello (addon 0.1.0).');
  assert.equal(eventLine({ kind: 'msg', chat: 'c1', bytes: 40, status: { ai: { name: 'ChatGPT' } } }), 'Question received: asking ChatGPT…');
  assert.equal(eventLine({ kind: 'state', part: 'quests', bytes: 900 }), null, 'not a line every few seconds');
  assert.equal(eventLine({ kind: 'turn-error', chat: 'c2', what: 'oauth_expired', text: 'Your ChatGPT sign-in ended. Sign in again in the Spellmind app.' }), 'Answer failed: Your ChatGPT sign-in ended. Sign in again in the Spellmind app.');
  assert.equal(eventLine({ kind: 'turn-error', chat: 'c2', what: 'unknown' }), 'Answer failed (unknown).');
  assert.equal(eventLine({ kind: 'wow', state: 'exited' }), 'WoW closed.');
  assert.equal(eventLine({ kind: 'reading-error', error: 'window not found', status: { wow: 'absent' } }), null);
  assert.equal(eventLine({ kind: 'reading-error', error: 'denied', status: { wow: 'running' } }), 'Screen reading: denied');
  assert.equal(eventLine({ kind: 'nothing' }), null);
});

test('the window\'s calls: the preload offers exactly the ones main.mjs answers', () => {
  const pre = fs.readFileSync(path.join(DESKTOP, 'preload.cjs'), 'utf8');
  const main = fs.readFileSync(path.join(DESKTOP, 'main.mjs'), 'utf8');
  const offered = JSON.parse(pre.match(/const CALLS = (\[[^\]]*\])/)[1].replace(/'/g, '"')).sort();
  const block = main.slice(main.indexOf('const CALLS = {'), main.indexOf('\n};', main.indexOf('const CALLS = {')));
  const answered = [...block.matchAll(/^ {2}([A-Za-z]+): /gm)].map(m => m[1]).sort();
  assert.deepEqual(offered, answered);
});

test('the window is locked down: sandboxed, no Node, isolated, a strict content policy, no navigation', () => {
  const main = fs.readFileSync(path.join(DESKTOP, 'main.mjs'), 'utf8');
  assert.match(main, /contextIsolation: true, sandbox: true, nodeIntegration: false/);
  assert.match(main, /will-navigate', \(e\) => e\.preventDefault\(\)/);
  assert.match(main, /setWindowOpenHandler\(\(\) => \(\{ action: 'deny' \}\)\)/);
  assert.match(main, /e\.sender !== win\.webContents/, 'only the app\'s own page may call');
  const html = fs.readFileSync(path.join(DESKTOP, 'renderer', 'index.html'), 'utf8');
  assert.match(html, /default-src 'none'; script-src 'self'/);
  const js = fs.readFileSync(path.join(DESKTOP, 'renderer', 'app.js'), 'utf8');
  assert.doesNotMatch(js, /innerHTML|outerHTML|insertAdjacentHTML|eval\(/, 'text goes in as text');
});

test('the window\'s script parses, and every element it looks up is in the page (seen: a name declared twice left it blank)', async () => {
  const { Script } = await import('node:vm');
  const js = fs.readFileSync(path.join(DESKTOP, 'renderer', 'app.js'), 'utf8');
  assert.doesNotThrow(() => new Script(js, { filename: 'app.js' }));
  const html = fs.readFileSync(path.join(DESKTOP, 'renderer', 'index.html'), 'utf8');
  const ids = [...new Set([...js.matchAll(/\$\('([A-Za-z]+)'\)/g)].map(m => m[1]))];
  assert.deepEqual(ids.filter(id => !html.includes(`id="${id}"`)), []);
});
