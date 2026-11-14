// The app's own updates (docs/install.md "Updating"): electron-updater against this repository's
// GitHub releases (electron-builder.yml's publish block writes the feed's address into the build).
// No token, no account: the releases are public.
//
// Policy, kept here so it's tested without Electron:
//   - A check finds a newer version: the window and the tray offer it, and a notification says so
//     once. Nothing downloads until the player clicks.
//   - Downloaded: "Restart to update" installs it now, never while WoW is running (the link would go
//     mid-answer); otherwise it installs when Spellmind quits.
//   - Only forward: a feed naming the same or an older version is ignored (electron-updater's
//     allowDowngrade is off too).
//   - Checks: 30 s after the start, then every 6 hours, while the player's "Check for updates" is on;
//     "Check now" any time.
//
//   createUpdater({ updater, current, wowRunning, onChange, log, timers }) → {
//     state() → { phase, version?, percent?, error?, checkedAt? }
//       phase: 'idle' | 'checking' | 'none' | 'available' | 'downloading' | 'ready' | 'error'
//     check({ manual }) · download() · install() → { ok } | { ok: false, error }
//     checkIfStale(now?) → a check when none has finished in STALE_MS (opening the window)
//     schedule(on) · stop()
//   }
// updater is electron-updater's autoUpdater (an EventEmitter with checkForUpdates, downloadUpdate,
// quitAndInstall), or a stand-in in the tests.

export const FIRST_CHECK_MS = 30 * 1000;
export const EVERY_MS = 6 * 3600 * 1000;
// Opening the window checks too, when the last check is older than this (the player, 2026-11-14: with the
// app running for hours, the 6-hour check hadn't come yet and "Check now" found the release first).
export const STALE_MS = 3600 * 1000;

/** a < b for versions like 0.4.10 (numbers part by part; anything after - or + ignored). */
export function newer(candidate, current) {
  const parts = (v) => String(v || '').replace(/^v/, '').split(/[-+]/)[0].split('.').map(n => parseInt(n, 10) || 0);
  const a = parts(candidate), b = parts(current);
  for (let i = 0; i < Math.max(a.length, b.length); i++) { const x = a[i] || 0, y = b[i] || 0; if (x !== y) return x > y; }
  return false;
}

// What the player sees for an updater error: short, never the raw message (it can hold a URL or a path).
export function errorWords(err) {
  // The code and the message both (seen with 0.4.0: the code alone, ERR_UPDATER_CHANNEL_FILE_NOT_FOUND,
  // matched nothing and the player read "didn't work" while the release was only a draft).
  const s = `${err?.code || ''} ${err?.message || (typeof err === 'string' ? err : '')}`;
  if (/ENOTFOUND|ECONNREFUSED|ETIMEDOUT|EAI_AGAIN|net::ERR_/i.test(s)) return 'No connection to GitHub right now.';
  if (/ERR_UPDATER_(NO_PUBLISHED_VERSIONS|CHANNEL_FILE_NOT_FOUND|LATEST_VERSION_NOT_FOUND)|404|latest\.yml|Cannot find/i.test(s)) return 'No published release to update from yet.';
  if (/sha512|checksum|signature|publisher/i.test(s)) return 'The download didn\'t check out, so it wasn\'t installed.';
  return 'The update check didn\'t work. It tries again later.';
}

export function createUpdater({ updater, current, wowRunning = () => false, onChange = () => {}, log = () => {}, timers = { setTimeout, clearTimeout, setInterval, clearInterval } } = {}) {
  let st = { phase: 'idle' };
  let first = null, every = null;
  const set = (next) => { st = { ...next }; onChange(st); };

  updater.on('update-available', (info) => {
    const v = info?.version;
    if (!newer(v, current)) { log('update-ignored', { version: v }); set({ phase: 'none', checkedAt: Date.now() }); return; }
    log('update-available', { version: v });
    set({ phase: 'available', version: v, checkedAt: Date.now() });
  });
  updater.on('update-not-available', () => { if (st.phase === 'checking') set({ phase: 'none', checkedAt: Date.now() }); });
  updater.on('download-progress', (p) => {
    if (st.phase !== 'downloading') return;
    const percent = Math.max(0, Math.min(100, Math.round(Number(p?.percent) || 0)));
    if (percent !== st.percent) set({ ...st, percent });
  });
  updater.on('update-downloaded', (info) => {
    const v = info?.version || st.version;
    if (!newer(v, current)) { set({ phase: 'none', checkedAt: Date.now() }); return; }
    log('update-downloaded', { version: v });
    set({ phase: 'ready', version: v });
  });
  updater.on('error', (err) => {
    log('update-error', { what: String(err?.code || err?.name || 'error').slice(0, 60) });
    // A failed download keeps the offer; a failed check says so.
    if (st.phase === 'downloading') set({ phase: 'available', version: st.version, error: errorWords(err) });
    else set({ phase: 'error', error: errorWords(err), checkedAt: Date.now() });
  });

  async function check({ manual = false } = {}) {
    if (['checking', 'downloading', 'ready'].includes(st.phase)) return { ok: true, phase: st.phase };
    if (st.phase === 'available' && !manual) return { ok: true, phase: st.phase };
    set({ phase: 'checking' });
    try { await updater.checkForUpdates(); } catch (e) { if (st.phase === 'checking') set({ phase: 'error', error: errorWords(e), checkedAt: Date.now() }); }
    return { ok: true, phase: st.phase };
  }

  async function download() {
    if (st.phase !== 'available') return { ok: false, error: 'nothing_to_download' };
    set({ phase: 'downloading', version: st.version, percent: 0 });
    try { await updater.downloadUpdate(); } catch (e) { if (st.phase === 'downloading') set({ phase: 'available', version: st.version, error: errorWords(e) }); }
    return { ok: true };
  }

  function install() {
    if (st.phase !== 'ready') return { ok: false, error: 'not_ready' };
    if (wowRunning()) return { ok: false, error: 'wow_running', detail: 'Close WoW first: the update restarts Spellmind. Or it installs when you quit Spellmind.' };
    log('update-install', { version: st.version });
    // Silent (the installer is one click already), and Spellmind starts again after.
    updater.quitAndInstall(true, true);
    return { ok: true };
  }

  function schedule(on) {
    if (first) { timers.clearTimeout(first); first = null; }
    if (every) { timers.clearInterval(every); every = null; }
    if (!on) return;
    first = timers.setTimeout(() => { first = null; check(); }, FIRST_CHECK_MS);
    every = timers.setInterval(() => check(), EVERY_MS);
    first?.unref?.(); every?.unref?.();
  }

  let lastChecked = 0;
  const checkedNow = () => { lastChecked = Date.now(); };
  updater.on('update-available', checkedNow);
  updater.on('update-not-available', checkedNow);
  function checkIfStale(now = Date.now()) {
    if (now - lastChecked < STALE_MS) return { ok: true, phase: st.phase, fresh: true };
    return check();
  }

  return { state: () => ({ ...st }), check, checkIfStale, download, install, schedule, stop: () => schedule(false) };
}
