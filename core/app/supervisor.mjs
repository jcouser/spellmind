// Keeps the link's worker running (docs/milestone-3.md): the desktop app starts it, and starts it
// again when it stops by itself, sooner the first times, then every 30 s at most. Seen before the
// app: the link stopped with the game or the PC, and the game said "Waiting for the Spellmind app to
// start…" until it was started by hand.
//
// A worker that exits with NEEDS_SETUP (2: no WoW folder, an unknown AI) isn't restarted: it waits
// for restart(), which the window calls once the setting is fixed.
//
//   createSupervisor({ spawn, onState, onMessage }) → { start(), stop() → Promise, restart() → Promise, state() }
//   spawn() → { onExit(cb(code)), onMessage(cb(msg)), kill() }
//   state(): { phase: 'running' | 'restarting' | 'setup' | 'stopped', restarts, delayMs?, code? }
export const NEEDS_SETUP = 2;
export const DELAYS_MS = Object.freeze([1000, 2000, 5000, 15000, 30000]);
// Up this long, a stop starts the count again from the shortest wait.
export const STABLE_MS = 120000;

export function createSupervisor({ spawn, onState = () => {}, onMessage = () => {}, delays = DELAYS_MS, stableMs = STABLE_MS,
  now = Date.now, setTimer = setTimeout, clearTimer = clearTimeout, killWaitMs = 5000 } = {}) {
  let child = null, timer = null, stopping = false, tries = 0, startedAt = 0, waiters = [];
  let st = { phase: 'stopped', restarts: 0 };
  const set = (next) => { st = { ...next, restarts: st.restarts + (next.phase === 'restarting' ? 1 : 0) }; try { onState({ ...st }); } catch { /* the listener's trouble */ } };

  function start() {
    if (child) return;
    if (timer) { clearTimer(timer); timer = null; }
    stopping = false;
    let c;
    try { c = spawn(); } catch (e) { return exited(null, -1); }
    child = c;
    startedAt = now();
    c.onMessage?.((m) => { try { onMessage(m); } catch { /* the listener's trouble */ } });
    c.onExit((code) => exited(c, code));
    set({ phase: 'running' });
  }

  function exited(c, code) {
    if (c && child !== c) return;
    child = null;
    const done = waiters; waiters = [];
    for (const w of done) w();
    if (stopping) { set({ phase: 'stopped', code }); return; }
    if (code === NEEDS_SETUP) { set({ phase: 'setup', code }); return; }
    if (now() - startedAt >= stableMs) tries = 0;
    const delayMs = delays[Math.min(tries, delays.length - 1)];
    tries += 1;
    set({ phase: 'restarting', code, delayMs });
    timer = setTimer(() => { timer = null; start(); }, delayMs);
  }

  function stop() {
    stopping = true;
    if (timer) { clearTimer(timer); timer = null; }
    if (!child) { if (st.phase !== 'stopped') set({ phase: 'stopped' }); return Promise.resolve(); }
    const c = child;
    return new Promise((resolve) => {
      let t = null;
      const done = () => { if (t) clearTimer(t); resolve(); };
      waiters.push(done);
      // A worker that doesn't go: let it go as stopped anyway, so a restart isn't held up.
      t = setTimer(() => { if (child === c) exited(c, null); }, killWaitMs);
      try { c.kill(); } catch { exited(c, null); }
    });
  }

  // A restart the player or a setting asked for: from the shortest wait again.
  async function restart() {
    await stop();
    tries = 0;
    start();
  }

  return { start, stop, restart, state: () => ({ ...st }) };
}
