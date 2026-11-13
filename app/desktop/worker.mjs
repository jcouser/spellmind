// The link's worker (docs/milestone-3.md): core/app/runner.mjs in a process of its own, which the
// app's supervisor (core/app/supervisor.mjs) starts again if it stops. Its events go to the app
// over the parent port; "stop" from the app stops it cleanly.
//
// Exit codes: 2 (NEEDS_SETUP) when it can't start until a setting changes (no WoW folder, an
// unknown AI); anything else that ends it is a stop the supervisor answers with a restart.
import { dataDir, readConfig, startSpellmind } from '../../core/app/runner.mjs';
import { NEEDS_SETUP } from '../../core/app/supervisor.mjs';

const port = process.parentPort;
const post = (m) => { try { port?.postMessage(m); } catch { /* the app is gone */ } };
const DATA = process.env.SPELLMIND_DATA || dataDir();

const run = startSpellmind({ dataDir: DATA, cfg: readConfig(DATA), onEvent: (ev) => post({ type: 'event', ev }) });
if (!run.ok) {
  post({ type: 'setup', error: run.error, detail: run.detail });
  setTimeout(() => process.exit(NEEDS_SETUP), 50);
} else {
  post({ type: 'status', status: run.status() });
  // A promise nobody caught is logged, never the end of the link (the review).
  process.on('unhandledRejection', (e) => run.log('unhandled', { error: String(e?.message || e).slice(0, 200) }));
  port?.on('message', (e) => {
    if (e?.data === 'stop') { run.stop(); setTimeout(() => process.exit(0), 50); }
  });
}
