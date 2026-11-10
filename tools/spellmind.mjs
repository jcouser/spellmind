#!/usr/bin/env node
// Spellmind from the command line (milestone 2: no app window yet).
//
//   node tools/spellmind.mjs install --wow "C:\Program Files (x86)\World of Warcraft\_forever_"
//        the addon, its 200 slot addons and its doorbells, with WoW closed (saves the folder)
//   node tools/spellmind.mjs start [--provider chatgpt] [--model <id>] [--effort low]
//        reads the game's strip, asks your AI, brings replies back; Ctrl+C stops it
//   node tools/spellmind.mjs status
//
// Sign in or save a key first with tools/chat.mjs (signin, or key <provider>).
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { loadManifests, createProvider } from '../core/ai/providers/index.mjs';
import { createKeyStore } from '../core/ai/security/keystore.mjs';
import { createEgress } from '../core/ai/security/egress.mjs';
import { createSignIns } from '../core/ai/signin/index.mjs';
import { userLine } from '../core/ai/providers/errors.mjs';
import { createService } from '../core/link/service.mjs';
import { createWindowsCapture } from '../core/link/capture.mjs';
import { installAddon, FOREVER_FLAVORS, NOT_GAME, wowRunning } from '../core/link/install.mjs';
import { loadPack } from '../core/ai/pack.mjs';
import { buildRequest } from '../core/ai/context.mjs';

const DATA = process.platform === 'win32' ? path.join(process.env.APPDATA || path.join(os.homedir(), 'AppData', 'Roaming'), 'Spellmind') : path.join(os.homedir(), '.config', 'spellmind');
const CONFIG = path.join(DATA, 'config.json');
const readConfig = () => { try { return JSON.parse(fs.readFileSync(CONFIG, 'utf8')); } catch { return {}; } };
const writeConfig = (c) => { fs.mkdirSync(DATA, { recursive: true }); fs.writeFileSync(CONFIG, JSON.stringify(c, null, 2) + '\n'); };

function args(argv) {
  const out = { _: [] };
  for (let i = 0; i < argv.length; i++) { const a = argv[i]; if (a.startsWith('--')) out[a.slice(2)] = argv[++i]; else out._.push(a); }
  return out;
}

const a = args(process.argv.slice(2));
const cfg = readConfig();
const stamp = () => new Date().toISOString().slice(11, 19);
const say = (...x) => console.log(`[${stamp()}]`, ...x);

switch (a._[0]) {
  case 'install': {
    const flavorDir = a.wow || cfg.wow;
    if (!flavorDir) { console.error('Where is WoW? node tools/spellmind.mjs install --wow "C:\\Program Files (x86)\\World of Warcraft\\_forever_"'); process.exit(2); }
    const r = installAddon({ flavorDir });
    if (!r.ok) { console.error(r.detail); process.exit(1); }
    writeConfig({ ...cfg, wow: flavorDir });
    console.log(`Installed Spellmind into ${r.addonsDir}: ${r.files} addon files, ${r.slots.created + r.slots.rewritten + r.slots.kept} slot addons, ${r.bells} doorbells.`);
    console.log(r.note);
    break;
  }
  case 'status': {
    console.log(`Data folder: ${DATA}`);
    console.log(`WoW folder: ${cfg.wow || '(not installed yet)'}`);
    console.log(`WoW running: ${wowRunning().running ? 'yes' : 'no'}`);
    break;
  }
  case 'start': {
    const flavorDir = cfg.wow;
    if (!flavorDir) { console.error('Install first: node tools/spellmind.mjs install --wow <your _forever_ folder>'); process.exit(2); }
    const manifests = loadManifests();
    const m = manifests.find(x => x.id === (a.provider || cfg.provider || 'chatgpt'));
    if (!m || m.custom) { console.error('Unknown AI.'); process.exit(2); }
    const model = a.model || cfg.model || m.models.default;
    const effort = a.effort || cfg.effort || 'low';
    const keystore = createKeyStore({ backend: 'os' });
    const egress = createEgress({ allowHosts: () => new Set(m.hosts), loopbackOk: true });
    const session = createSignIns({ keystore, fetch: egress.fetch }).for(m);
    const provider = createProvider(m, { getKey: async () => (session ? session.credentials() : keystore.get(m.id)), fetch: egress.fetch });
    const logFile = path.join(DATA, 'spellmind.log');
    fs.mkdirSync(DATA, { recursive: true });
    const log = (k, d) => { try { fs.appendFileSync(logFile, `${new Date().toISOString()} ${k} ${JSON.stringify(d ?? {})}\n`); } catch { /* logging never stops the link */ } };

    // The prompt (prompts/spellmind.md), read once: its version goes in the log.
    const pack = loadPack();
    log('pack', { version: pack.version, tokens: pack.tokens });

    // One turn: the prompt, the chat's history, then the game data and the message; the reply's
    // text, or the error's words.
    const turn = async ({ text, history, signal, game }) => {
      let out = '';
      const { system, messages, meta } = buildRequest({ pack, game, history, userText: text });
      log('request', { pack: pack.version, dataChars: meta.dataChars, omitted: meta.omitted.length ? meta.omitted : undefined, stale: game?.stale || undefined });
      for await (const ev of provider.stream({ model, effort, system, messages }, { signal })) {
        if (ev.type === 'text') out += ev.delta;
        else if (ev.type === 'error') {
          if (ev.error?.kind === 'interrupted') return { aborted: true };
          const l = userLine(ev.error, { provider: m.name, product: 'Spellmind' });
          return { error: { kind: ev.error?.kind || 'error', text: `${l.headline} ${l.detail}`.trim() } };
        }
      }
      return { text: out };
    };

    const addonsDir = path.join(flavorDir, 'Interface', 'AddOns');
    const svc = createService({ addonsDir, stateDir: path.join(DATA, 'link'), turn, log: (k, d) => {
      log(k, d);
      if (k === 'hello') say('The game said hello (addon', d.ver + ').');
      else if (k === 'msg') say('Message in', d.chat, `(${d.bytes} bytes): asking ${m.name}…`);
      else if (k === 'reply') say('Reply out', d.chat, `(${d.chars} characters).`);
      else if (k === 'turn-error') say('Error for', d.chat + ':', d.kind);
      else if (k === 'msg-refused') say('Refused a message:', d.reason);
      else if (k === 'state') say('Character data in:', d.part, `(${d.bytes} bytes)`);
      else if (k === 'state-rejected') say('Character data refused:', d.part || '?', d.reason);
      else if (k === 'state-wait-over') say('Character data late for', d.chat + ': answering with what is there.');
    } });
    svc.start();
    let lastErr = '';
    const capture = createWindowsCapture({ flavorDirs: FOREVER_FLAVORS, notGame: NOT_GAME, log,
      onPayload: ({ text }) => svc.handlePayload(text),
      onGame: ({ state }) => say('WoW:', state),
      onError: (e) => { const s = String(e?.message || e?.kind || e); if (s !== lastErr) { lastErr = s; say('Screen reading:', s); } },
      onStatus: (s) => { if (s.connected === true) say('Screen reading started.'); },
    });
    capture.start();
    say(`Spellmind is running with ${m.name} (${model}, thinking ${effort}), prompt ${pack.version}. In game: /sm <question>. Ctrl+C stops it.`);
    const stop = () => { say('Stopping…'); try { capture.stop(); } catch { /* stopping */ } svc.stop(); process.exit(0); };
    process.on('SIGINT', stop);
    process.on('SIGTERM', stop);
    break;
  }
  default:
    console.error('Commands: install --wow <folder> · start [--provider chatgpt] [--model id] [--effort low] · status');
    process.exit(2);
}
