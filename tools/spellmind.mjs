#!/usr/bin/env node
// Spellmind from the command line (the desktop app, app/desktop, runs the same link: core/app/runner.mjs).
//
//   node tools/spellmind.mjs install --wow "C:\Program Files (x86)\World of Warcraft\_forever_"
//        the addon, its 200 slot addons and its doorbells, with WoW closed (saves the folder)
//   node tools/spellmind.mjs start [--provider chatgpt] [--model <id>] [--effort high|medium|low] [--search off]
//        reads the game's strip, asks your AI, brings replies back; Ctrl+C stops it
//   node tools/spellmind.mjs status
//
// Sign in or save a key first with tools/chat.mjs (signin, or key <provider>).
import { installAddon, wowRunning } from '../core/link/install.mjs';
import { dataDir, readConfig as readCfg, writeConfig as writeCfg, startSpellmind } from '../core/app/runner.mjs';
import { eventLine } from '../core/app/lines.mjs';

const DATA = dataDir();
const readConfig = () => readCfg(DATA);
const writeConfig = (c) => writeCfg(DATA, c);

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
    // The link itself is core/app/runner.mjs, the desktop app's too; here its events become lines (core/app/lines.mjs).
    const run = startSpellmind({ dataDir: DATA, cfg, over: { provider: a.provider, model: a.model, effort: a.effort, search: a.search },
      onEvent: (ev) => { const line = eventLine(ev); if (line) say(line); } });
    if (!run.ok) {
      console.error(run.error === 'not_installed' ? 'Install first: node tools/spellmind.mjs install --wow <your _forever_ folder>' : run.detail);
      process.exit(2);
    }
    // A promise nobody caught is logged, never the end of the app (the review: one could stop it and
    // lose the replies in flight).
    process.on('unhandledRejection', (e) => run.log('unhandled', { error: String(e?.message || e).slice(0, 200) }));
    const s = run.status();
    say(`Spellmind is running with ${s.ai.name} (${s.ai.model}, thinking ${s.ai.effort}${s.ai.search ? ', web search on' : ''}). In game: /sm <question>. Ctrl+C stops it.`);
    const stop = () => { say('Stopping…'); run.stop(); process.exit(0); };
    process.on('SIGINT', stop);
    process.on('SIGTERM', stop);
    break;
  }
  default:
    console.error('Commands: install --wow <folder> · start [--provider chatgpt] [--model id] [--effort high|medium|low] [--search off] · status');
    process.exit(2);
}
