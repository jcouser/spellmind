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
import { loadManifests, createProvider, manifestFor, effortLevels, nearestEffort } from '../ai/providers/index.mjs';
import { createKeyStore } from '../ai/security/keystore.mjs';
import { createEgress } from '../ai/security/egress.mjs';
import { createSignIns } from '../ai/signin/index.mjs';
import { createService } from '../link/service.mjs';
import { createWindowsCapture } from '../link/capture.mjs';
import { FOREVER_FLAVORS, NOT_GAME } from '../link/install.mjs';
import { loadPack } from '../ai/pack.mjs';
import { createTurn } from './turn.mjs';
import { createLogger } from '../log.mjs';

export function dataDir(env = process.env, platform = process.platform) {
  return platform === 'win32'
    ? path.join(env.APPDATA || path.join(os.homedir(), 'AppData', 'Roaming'), 'Spellmind')
    : path.join(os.homedir(), '.config', 'spellmind');
}
export const configFile = dir => path.join(dir, 'config.json');
// The settings. A byte-order mark (Notepad's, PowerShell's) is skipped: JSON.parse refuses it. A file
// that still can't be read is kept aside as config.json.bad (once), and reads as no settings.
export function readConfig(dir) {
  let text;
  try { text = fs.readFileSync(configFile(dir), 'utf8'); } catch { return {}; }
  try { return JSON.parse(text.replace(/^\uFEFF/, '')); } catch {
    try { if (!fs.existsSync(`${configFile(dir)}.bad`)) fs.copyFileSync(configFile(dir), `${configFile(dir)}.bad`); } catch { /* kept or not */ }
    return {};
  }
}
// Written whole (a temp file, then renamed over), so a crash mid-write never leaves half a file that
// reads as no settings (the security review: the start-at-login switch came back on that way).
export function writeConfig(dir, cfg) {
  fs.mkdirSync(dir, { recursive: true });
  const tmp = `${configFile(dir)}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(cfg, null, 2) + '\n');
  fs.renameSync(tmp, configFile(dir));
}

/** The AI the settings name, and what the app shows of it: { m, model, effort, search } or { error }. */
export function pickAI(cfg = {}, over = {}, manifests = loadManifests()) {
  // Other (custom) is built from the player's address and model (cfg.custom); null until it's set.
  const m = manifestFor(over.provider || cfg.provider || 'chatgpt', manifests, cfg.custom);
  if (!m || m.hidden) return { error: 'unknown_ai' };
  // A model another AI had (the settings kept from before a switch) falls back to this one's default.
  const wanted = over.model || cfg.model;
  const listed = (m.models.list || []).some(x => x.id === wanted);
  const model = wanted && (listed || (m.models.allowAny && !m.custom)) ? wanted : m.models.default;
  // Web search on by default where the AI has it (manifest webSearch): without it, low and medium
  // thinking got game facts (which weapon master teaches Bows) wrong most of the time in a test on
  // 2026-11-10, and high was right only at about 10 s an answer. With it, low was right 3 of 3 at
  // 6 to 10 s; medium is the default, so plain chat stays quick and facts come from the web.
  const search = !!m.webSearch && (over.search || cfg.search || 'on') !== 'off';
  // A level this model hasn't (one saved for another AI) goes to its nearest; a model with no levels
  // (Other) keeps the word, which its requests don't use.
  // Medium by default, search or not (the audit: without search it was High, the slowest, on the AIs
  // that already answer from memory).
  const wantEffort = over.effort || cfg.effort || 'medium';
  const effort = nearestEffort(effortLevels(m, model), wantEffort) || wantEffort;
  return { m, model, effort, search };
}

export function startSpellmind({ dataDir: DATA, cfg = {}, over = {}, onEvent = () => {}, capture: makeCapture = createWindowsCapture } = {}) {
  const flavorDir = cfg.wow;
  if (!flavorDir) return { ok: false, error: 'not_installed', detail: 'Install the addon first: pick your WoW folder.' };
  const pick = pickAI(cfg, over);
  if (pick.error) return { ok: false, error: pick.error, detail: 'Unknown AI.' };
  const { m, model, effort, search } = pick;
  const keystore = createKeyStore({ backend: 'os' });
  // Only Other may reach this computer (a server here); every other AI only its own hosts (the security review).
  const egress = createEgress({ allowHosts: () => new Set(m.hosts), loopbackOk: m.custom === true });
  const session = createSignIns({ keystore, fetch: egress.fetch }).for(m);
  // Other's key goes only to the host it was given for (cfg.custom.keyHost, core/app/ai.mjs).
  const customKeyOK = () => !m.custom || (cfg.custom?.keyHost && cfg.custom.keyHost === new URL(m.baseUrl).host);
  // A model on this computer may load from disk first: 3 minutes for its first word, not 1 (the audit).
  const timeouts = m.local ? { firstTokenMs: 180000 } : {};
  const provider = createProvider(m, { getKey: async () => (session ? session.credentials() : (customKeyOK() ? keystore.get(m.id) : null)), fetch: egress.fetch, timeouts });
  // The log (the security review: one file that grew forever, unscrubbed, with the link's session
  // token and nonce): core/log.mjs's, a file a day in <data>/logs kept 7 days, every line through the
  // key redactor. The token and nonce fields are left out, and a publish is logged only when it failed.
  fs.mkdirSync(DATA, { recursive: true });
  try { fs.rmSync(path.join(DATA, 'spellmind.log'), { force: true }); } catch { /* the old log, gone or not */ }
  const logger = createLogger(path.join(DATA, 'logs'));
  const log = (k, d) => {
    if (k === 'publish' && !(d && (d.errors || d.error))) return;
    const { token, nonce, ...rest } = d && typeof d === 'object' ? d : {};
    try { logger(k, rest); } catch { /* logging never stops the link */ }
  };

  const label = m.models.list.find(x => x.id === model)?.label || model;
  const st = { ai: { name: m.name, model: label, effort, search }, wow: null, reading: false, hello: null, lastAt: null, error: null };
  const status = () => JSON.parse(JSON.stringify(st));
  // An event's own "kind" (a turn error's: oauth_expired…) goes as "what", so it never hides the event's.
  const emit = (kind, data = {}) => {
    const { kind: what, ...rest } = data || {};
    try { onEvent({ ...rest, ...(what !== undefined ? { what } : {}), kind, status: status() }); } catch { /* a listener's trouble isn't the link's */ }
  };

  // The prompt (prompts/spellmind.md), read once: its version goes in the log.
  const pack = loadPack();
  log('pack', { version: pack.version, tokens: pack.tokens });

  const { turn } = createTurn({ m, model, label, provider, pack, log, effort, search });

  const addonsDir = path.join(flavorDir, 'Interface', 'AddOns');
  // What the chat window's header shows and lets the player pick: the model's thinking levels and search.
  // The game's menu stops at High: Extra high and Max can pass the turn's 3 minutes, doubled by the
  // double-check (the audit). The app's window still offers them.
  const efforts = effortLevels(m, model).filter(l => l !== 'xhigh' && l !== 'max');
  const ai = { name: m.name, model: label, efforts, effort, search: !!m.webSearch, searchOn: search };
  const SHOWN = new Set(['hello', 'msg', 'reply', 'turn-error', 'msg-refused', 'state', 'state-rejected', 'state-wait-over']);
  const svc = createService({ addonsDir, stateDir: path.join(DATA, 'link'), turn, ai, log: (k, d) => {
    log(k, d);
    if (k === 'hello') st.hello = new Date().toISOString();
    if (k === 'reply' || k === 'msg') st.lastAt = new Date().toISOString();
    if (k === 'turn-error') { st.error = d?.kind || 'error'; st.errorText = d?.text || null; }
    else if (k === 'reply') { st.error = null; st.errorText = null; }
    if (SHOWN.has(k)) emit(k, d);
  } });
  svc.start();
  // Is the AI set up (a sign-in or a key saved; Other may need none)? The game says so in its header
  // instead of "Connected" (the audit: it said Connected with nothing signed in, and the player learned
  // only by asking). Checked once here; a sign-in or key from the app restarts the link.
  (async () => {
    let ok = true;
    try { ok = session ? await session.signedIn() : (m.auth?.optional === true || !!(await keystore.get(m.id))); } catch { ok = false; }
    st.ai.ready = ok;
    if (!ok) { ai.ready = false; svc.publisher.publish({}); emit('ai-not-ready', {}); }
  })();
  let lastErr = '';
  const capture = makeCapture({ flavorDirs: FOREVER_FLAVORS, notGame: NOT_GAME, log,
    onPayload: ({ text }) => svc.handlePayload(text),
    // The game: running, launched, absent or exited (the helper's words). Closed, its link is gone with it
    // (the audit: "Linked (3 h ago)" stayed green after WoW closed).
    onGame: ({ state }) => { st.wow = state; if (state === 'exited' || state === 'absent') st.hello = null; emit('wow', { state }); },
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
  // A clean stop says goodbye to the game first (service.bye), then stops.
  const close = async () => { if (!stopped) { try { await svc.bye(); } catch { /* stopping anyway */ } } stop(); };
  return { ok: true, stop, close, status, log };
}
