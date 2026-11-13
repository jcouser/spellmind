// Spellmind's link, started: the AI, the game's strip and the replies back (docs/milestone-3.md).
// One copy for both ways it runs: the command line (tools/spellmind.mjs start) and the desktop
// app's worker (app/desktop/worker.mjs), which the app restarts if it stops.
//
//   dataDir()                      where Spellmind keeps its settings and log
//   readConfig(dir) / writeConfig(dir, cfg)
//   startSpellmind({ dataDir, cfg, onEvent }) → { ok, stop(), status() } | { ok: false, error, detail }
//
// onEvent({ kind, ...data, status }): each thing worth a line ('hello', 'msg', 'reply', 'turn-error',
// 'msg-refused', 'state', 'state-rejected', 'state-wait-over', 'wow', 'reading', 'reading-error',
// 'started'), with the status after it. status(): { ai, wow, reading, hello, lastAt, error }.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { loadManifests, createProvider } from '../ai/providers/index.mjs';
import { createKeyStore } from '../ai/security/keystore.mjs';
import { createEgress } from '../ai/security/egress.mjs';
import { createSignIns } from '../ai/signin/index.mjs';
import { userLine } from '../ai/providers/errors.mjs';
import { createService } from '../link/service.mjs';
import { createWindowsCapture } from '../link/capture.mjs';
import { FOREVER_FLAVORS, NOT_GAME } from '../link/install.mjs';
import { loadPack } from '../ai/pack.mjs';
import { buildRequest } from '../ai/context.mjs';
import { needsCheck, checkHistory, CHECK_ASK, pickChecked } from '../ai/check.mjs';

export function dataDir(env = process.env, platform = process.platform) {
  return platform === 'win32'
    ? path.join(env.APPDATA || path.join(os.homedir(), 'AppData', 'Roaming'), 'Spellmind')
    : path.join(os.homedir(), '.config', 'spellmind');
}
export const configFile = dir => path.join(dir, 'config.json');
export function readConfig(dir) { try { return JSON.parse(fs.readFileSync(configFile(dir), 'utf8')); } catch { return {}; } }
export function writeConfig(dir, cfg) {
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(configFile(dir), JSON.stringify(cfg, null, 2) + '\n');
}

/** The AI the settings name, and what the app shows of it: { m, model, effort, search } or { error }. */
export function pickAI(cfg = {}, over = {}, manifests = loadManifests()) {
  const m = manifests.find(x => x.id === (over.provider || cfg.provider || 'chatgpt'));
  if (!m || m.custom) return { error: 'unknown_ai' };
  const model = over.model || cfg.model || m.models.default;
  // Web search on by default where the AI has it (manifest webSearch): without it, low and medium
  // thinking got game facts (which weapon master teaches Bows) wrong most of the time in a test on
  // 2026-11-10, and high was right only at about 10 s an answer. With it, low was right 3 of 3 at
  // 6 to 10 s; medium is the default, so plain chat stays quick and facts come from the web.
  const search = !!m.webSearch && (over.search || cfg.search || 'on') !== 'off';
  const effort = over.effort || cfg.effort || (search ? 'medium' : 'high');
  return { m, model, effort, search };
}

export function startSpellmind({ dataDir: DATA, cfg = {}, over = {}, onEvent = () => {}, capture: makeCapture = createWindowsCapture } = {}) {
  const flavorDir = cfg.wow;
  if (!flavorDir) return { ok: false, error: 'not_installed', detail: 'Install the addon first: pick your WoW folder.' };
  const pick = pickAI(cfg, over);
  if (pick.error) return { ok: false, error: pick.error, detail: 'Unknown AI.' };
  const { m, model, effort, search } = pick;
  const keystore = createKeyStore({ backend: 'os' });
  const egress = createEgress({ allowHosts: () => new Set(m.hosts), loopbackOk: true });
  const session = createSignIns({ keystore, fetch: egress.fetch }).for(m);
  const provider = createProvider(m, { getKey: async () => (session ? session.credentials() : keystore.get(m.id)), fetch: egress.fetch });
  const logFile = path.join(DATA, 'spellmind.log');
  fs.mkdirSync(DATA, { recursive: true });
  const log = (k, d) => { try { fs.appendFileSync(logFile, `${new Date().toISOString()} ${k} ${JSON.stringify(d ?? {})}\n`); } catch { /* logging never stops the link */ } };

  const label = m.models.list.find(x => x.id === model)?.label || model;
  const st = { ai: { name: m.name, model: label, effort, search }, wow: null, reading: false, hello: null, lastAt: null, error: null };
  const status = () => JSON.parse(JSON.stringify(st));
  const emit = (kind, data = {}) => { try { onEvent({ kind, ...data, status: status() }); } catch { /* a listener's trouble isn't the link's */ } };

  // The prompt (prompts/spellmind.md), read once: its version goes in the log.
  const pack = loadPack();
  log('pack', { version: pack.version, tokens: pack.tokens });

  // One request: the text, or { aborted } or { error }.
  const ask = async ({ history, userText, game, signal, effort: e, search: s }) => {
    let out = '', searched = false;
    const { system, messages, meta } = buildRequest({ pack, game, history, userText });
    log('request', { pack: pack.version, dataChars: meta.dataChars, omitted: meta.omitted.length ? meta.omitted : undefined, stale: game?.stale || undefined });
    for await (const ev of provider.stream({ model, effort: e, system, messages, webSearch: s }, { signal })) {
      if (ev.type === 'text') out += ev.delta;
      else if (ev.type === 'progress' && ev.searching && !searched) { searched = true; log('web-search', {}); }
      else if (ev.type === 'error') {
        if (ev.error?.kind === 'interrupted') return { aborted: true };
        const l = userLine(ev.error, { provider: m.name, product: 'Spellmind' });
        return { error: { kind: ev.error?.kind || 'error', text: `${l.headline} ${l.detail}`.trim() } };
      }
    }
    return { text: out };
  };
  // A turn: the answer, then (docs/milestone-17.md) a double-check of one that names places, people,
  // routes, items or quest steps, unless the player turned it off. A failed check keeps the draft.
  const turn = async ({ text, history, signal, game, effort: pickedEffort, search: pickedSearch, check }) => {
    const e = pickedEffort || effort, s = pickedSearch ?? search;
    const draft = await ask({ history, userText: text, game, signal, effort: e, search: s });
    if (!draft.text || check === false || !needsCheck(text, draft.text)) return draft;
    log('check', {});
    const checked = await ask({ history: checkHistory(history, text, draft.text), userText: CHECK_ASK, game, signal, effort: e, search: s });
    if (checked.aborted) return checked;
    if (!checked.text?.trim()) { log('check-failed', { kind: checked.error?.kind }); return draft; }
    // A check that came back as a comment, much shorter, or without its "Next:" line doesn't replace a good draft.
    const chosen = pickChecked(draft.text, checked.text);
    log('check-done', { used: chosen.used, why: chosen.why });
    return { text: chosen.text };
  };

  const addonsDir = path.join(flavorDir, 'Interface', 'AddOns');
  // What the chat window's header shows and lets the player pick: the model's thinking levels and search.
  const efforts = Object.keys(m.effort?.[model] || {});
  const ai = { name: m.name, model: label, efforts, effort, search: !!m.webSearch, searchOn: search };
  const SHOWN = new Set(['hello', 'msg', 'reply', 'turn-error', 'msg-refused', 'state', 'state-rejected', 'state-wait-over']);
  const svc = createService({ addonsDir, stateDir: path.join(DATA, 'link'), turn, ai, log: (k, d) => {
    log(k, d);
    if (k === 'hello') st.hello = new Date().toISOString();
    if (k === 'reply' || k === 'msg') st.lastAt = new Date().toISOString();
    if (k === 'turn-error') st.error = d?.kind || 'error';
    else if (k === 'reply') st.error = null;
    if (SHOWN.has(k)) emit(k, d);
  } });
  svc.start();
  let lastErr = '';
  const capture = makeCapture({ flavorDirs: FOREVER_FLAVORS, notGame: NOT_GAME, log,
    onPayload: ({ text }) => svc.handlePayload(text),
    // The game: running, launched, absent or exited (the helper's words).
    onGame: ({ state }) => { st.wow = state; emit('wow', { state }); },
    onError: (e) => { const s = String(e?.message || e?.kind || e); if (s !== lastErr) { lastErr = s; emit('reading-error', { error: s }); } },
    // The screen-reading helper up (connected) or gone.
    onStatus: (s) => {
      if (s.connected === true && !st.reading) { st.reading = true; emit('reading', {}); }
      else if (s.connected === false && st.reading) { st.reading = false; emit('reading', {}); }
    },
  });
  capture.start();
  emit('started', { pack: pack.version, model, provider: m.name });
  let stopped = false;
  const stop = () => {
    if (stopped) return;
    stopped = true;
    try { capture.stop(); } catch { /* stopping */ }
    try { svc.stop(); } catch { /* stopping */ }
  };
  return { ok: true, stop, status, log };
}
