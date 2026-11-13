// Spellmind's desktop app (docs/milestone-3.md): the link to the game, kept running, in the tray.
// Adapted in part from NeverQuestAlone's app/desktop (MIT; see NOTICE.md): its tray, login item
// and single-instance patterns.
//
//   - The link runs in a worker (worker.mjs, an Electron utility process) that the supervisor
//     (core/app/supervisor.mjs) starts again when it stops by itself.
//   - The tray: what the link is doing, Open, Start when I log in, Restart the link, Quit.
//   - Start at login (on by default), with --hidden: no window, just the tray.
//   - One copy runs: a second launch opens the first one's window.
//   - The window (renderer/): status, the AI and its sign-in, the WoW folder and the addon, the app.
//     Closing it keeps Spellmind in the tray; Quit in the tray's menu ends it.
import { app, BrowserWindow, Tray, Menu, nativeImage, nativeTheme, dialog, ipcMain, shell, utilityProcess, Notification, clipboard } from 'electron';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { dataDir, readConfig, writeConfig } from '../../core/app/runner.mjs';
import { createSupervisor } from '../../core/app/supervisor.mjs';
import { aiChoices, applyAI } from '../../core/app/settings.mjs';
import { createAISetup } from '../../core/app/ai.mjs';
import { eventLine } from '../../core/app/lines.mjs';
import { installAddon, addonState, looksLikeFlavor, flavorIn, findFlavorDirs, wowRunning, RUNNING_LINE } from '../../core/link/install.mjs';
import { loadManifests } from '../../core/ai/providers/index.mjs';
import { createKeyStore } from '../../core/ai/security/keystore.mjs';
import { createEgress } from '../../core/ai/security/egress.mjs';
import { createSignIns } from '../../core/ai/signin/index.mjs';
import { IDENTITY } from '../../core/identity.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
// SPELLMIND_DATA: another data folder (a first run seen from source, the tests); the player's is dataDir().
const DATA = (!app.isPackaged && process.env.SPELLMIND_DATA) || dataDir();
const HIDDEN = process.argv.includes('--hidden');
const ACTIVITY_MAX = 40;

app.setAppUserModelId(IDENTITY.appId);
// The window's title bar and menus dark, like the page.
nativeTheme.themeSource = 'dark';
// --quit (the installer, closing it for an update): the running copy hears it (second-instance) and
// quits; with none running, this one just ends.
const QUIT_ASKED = process.argv.includes('--quit');
if (!app.requestSingleInstanceLock() || QUIT_ASKED) { app.quit(); process.exit(0); }

let win = null, tray = null, quitting = false;
let linkState = { phase: 'stopped', restarts: 0 };
let runStatus = null; // the worker's last status: { ai, wow, reading, hello, lastAt, error }
let setupError = null; // what the worker needs before it can start
let setupNeeded = false; // a setup step undone (fullStatus works it out)
const activity = []; // { at, line }

// The app's own switches, in config.json under "app" (all on unless turned off).
const APP_DEFAULTS = Object.freeze({ startAtLogin: true, minimizeToTray: true, notifications: true, updateAddon: true });
const appSettings = () => ({ ...APP_DEFAULTS, ...(readConfig(DATA).app || {}) });

// The sign-in is gone or refused (core/ai/providers/errors.mjs kinds): the player has to act.
const SIGN_IN_KINDS = new Set(['oauth_expired', 'auth_invalid', 'no_key']);
let failStreak = 0; // restarts in a row without the link staying up
const told = new Set(); // what a notification has said this session

// A desktop notification, once per thing until it's resolved; a click opens the window.
function notify(key, title, body) {
  if (told.has(key) || !appSettings().notifications || !Notification.isSupported()) return;
  told.add(key);
  const n = new Notification({ title, body, icon: path.join(HERE, 'assets', 'icon.png'), silent: true });
  n.on('click', () => openWindow());
  n.show();
}

// The addon kept up to date: the app's copy over the game's, only while WoW is closed (new files load
// only when the game starts). At start and when WoW closes; nothing when it isn't installed yet.
function updateAddonIfOld(why) {
  const cfg = readConfig(DATA);
  if (!appSettings().updateAddon || !cfg.wow) return;
  const st = addonState({ flavorDir: cfg.wow });
  if (st.state !== 'outdated') return;
  if (wowRunning().running) { note('An addon update is ready: it goes in when WoW closes.'); return; }
  const r = installAddon({ flavorDir: cfg.wow });
  if (r.ok) {
    note(`Addon updated (${why}).`);
    told.delete('addon-updated');
    notify('addon-updated', 'Spellmind\'s addon is up to date', 'The new version loads the next time you start WoW.');
  } else note(`The addon couldn't be updated: ${r.detail || r.error}`);
  pushStatus();
}

// ---------------------------------------------------------------------------
// The link's worker, kept running.

function note(line) {
  if (!line) return;
  activity.push({ at: new Date().toISOString(), line });
  if (activity.length > ACTIVITY_MAX) activity.shift();
}

const sup = createSupervisor({
  spawn: () => {
    const child = utilityProcess.fork(path.join(HERE, 'worker.mjs'), [], { serviceName: 'Spellmind link', stdio: 'ignore', env: { ...process.env, SPELLMIND_DATA: DATA } });
    return {
      onExit: (cb) => child.on('exit', cb),
      onMessage: (cb) => child.on('message', cb),
      // Asked first, then ended: the worker stops the screen reading and the service on "stop".
      kill: () => {
        try { child.postMessage('stop'); } catch { /* gone */ }
        setTimeout(() => { try { child.kill(); } catch { /* gone */ } }, 2000);
      },
    };
  },
  onState: (s) => {
    linkState = s;
    if (s.phase === 'running') setupError = null;
    if (s.phase === 'restarting') {
      note(`The link stopped; starting it again in ${Math.round(s.delayMs / 1000)} s.`);
      failStreak += 1;
      // Three in a row: something's wrong that a restart doesn't fix.
      if (failStreak >= 3) notify('link-failing', 'Spellmind\'s link keeps stopping', 'It keeps trying. Open Spellmind to see what happened, or restart it from the tray.');
    }
    pushStatus();
  },
  onMessage: (m) => {
    if (m?.type === 'event') {
      runStatus = m.ev?.status || runStatus;
      note(eventLine(m.ev));
      const k = m.ev?.kind;
      // The link works again: a later failure may say so again.
      if (k === 'hello' || k === 'reply') { failStreak = 0; told.delete('link-failing'); }
      if (k === 'reply') told.delete('sign-in');
      if (k === 'turn-error' && SIGN_IN_KINDS.has(m.ev.what)) {
        notify('sign-in', 'Spellmind needs you to sign in again', 'Your AI refused the sign-in. Open Spellmind and sign in, then ask again in game.');
      }
      if (k === 'wow' && m.ev.state === 'exited') updateAddonIfOld('WoW closed');
    }
    else if (m?.type === 'status') runStatus = m.status;
    else if (m?.type === 'setup') setupError = m.detail || m.error;
    pushStatus();
  },
});

// ---------------------------------------------------------------------------
// The AI's sign-in (a ChatGPT plan), here in the app; the worker reads the same key store.

const manifests = loadManifests();
const keystore = createKeyStore({ backend: 'os' });
// Each AI's own egress (only its hosts) and, for a plan, its sign-in session, made once.
const fetchFor = (m) => createEgress({ allowHosts: () => new Set(m.hosts), loopbackOk: true }).fetch;
const sessions = new Map();
function sessionFor(m) {
  if (!m) return null;
  if (!sessions.has(m.id)) sessions.set(m.id, createSignIns({ keystore, fetch: fetchFor(m) }).for(m));
  return sessions.get(m.id);
}
const PLAN = manifests.find(m => m.id === 'chatgpt');
const aiSetup = createAISetup({ manifests, keystore, signInFor: sessionFor, fetchFor });
let signingIn = null;

// The AI the link uses, with every AI the window offers and which are set up.
async function aiStatus(cfg) {
  const list = await aiSetup.list(cfg);
  const choices = aiChoices(cfg, manifests);
  const current = list.find(x => x.current);
  return { ...choices, list, ready: !!current?.ready, signedIn: !!list.find(x => x.id === 'chatgpt')?.ready, signingIn: !!signingIn };
}

// A setting the AI setup changed: saved, and the link restarted with it.
async function useCfg(cfg, line) {
  writeConfig(DATA, cfg);
  if (line) note(line);
  await sup.restart();
}

// ---------------------------------------------------------------------------
// Start at login: the HKCU Run value, with --hidden. A run from source names Electron and this folder.

const loginArgs = () => (app.isPackaged ? ['--hidden'] : [app.getAppPath(), '--hidden']);
const loginItem = {
  get: () => !!app.getLoginItemSettings({ path: process.execPath, args: loginArgs() }).openAtLogin,
  set: (on) => app.setLoginItemSettings({ openAtLogin: !!on, path: process.execPath, args: loginArgs() }),
};

// ---------------------------------------------------------------------------
// What the window and the tray show.

function summary() {
  const s = runStatus;
  // The setup card says which step; the pill only that there's one (the review: a long sentence in it).
  if (linkState.phase === 'setup' || setupError || setupNeeded) return { tone: 'warn', text: 'Finish the setup' };
  if (linkState.phase === 'restarting') return { tone: 'warn', text: `Restarting the link in ${Math.round((linkState.delayMs || 0) / 1000)} s` };
  if (linkState.phase !== 'running') return { tone: 'off', text: 'The link is stopped' };
  if (SIGN_IN_KINDS.has(s?.error)) return { tone: 'bad', text: 'Sign in again' };
  if (s?.error === 'out_of_credit' || s?.error === 'spend_limit' || s?.error === 'rate_limited') return { tone: 'warn', text: 'Your AI plan\'s limit is reached' };
  if (s?.wow === 'running' || s?.wow === 'launched') return { tone: 'good', text: s.hello ? 'Linked to WoW' : 'WoW is running: waiting for the addon' };
  return { tone: 'idle', text: 'Waiting for WoW' };
}

async function fullStatus() {
  const cfg = readConfig(DATA);
  const wow = cfg.wow || null;
  const ai = await aiStatus(cfg);
  const wowState = { folder: wow, ok: !!wow && looksLikeFlavor(wow), addon: wow ? addonState({ flavorDir: wow }) : { state: 'missing' } };
  // Kept for the tray and the pill: any of the first three setup steps undone.
  const was = setupNeeded;
  setupNeeded = !wowState.ok || wowState.addon.state === 'missing' || !ai.ready;
  if (was !== setupNeeded) refreshTray();
  return {
    version: app.getVersion(),
    packaged: app.isPackaged,
    summary: summary(),
    link: linkState,
    run: runStatus,
    ai,
    wow: wowState,
    loginItem: loginItem.get(),
    app: appSettings(),
    activity: activity.slice().reverse(),
  };
}

let pushTimer = null;
function pushStatus() {
  refreshTray();
  if (pushTimer || !win || win.isDestroyed()) return;
  pushTimer = setTimeout(async () => {
    pushTimer = null;
    if (win && !win.isDestroyed()) win.webContents.send('spellmind:status', await fullStatus());
  }, 150);
}

// ---------------------------------------------------------------------------
// The tray.

function refreshTray() {
  if (!tray || tray.isDestroyed()) return;
  const s = summary();
  tray.setToolTip(`Spellmind: ${s.text}`);
  tray.setContextMenu(Menu.buildFromTemplate([
    { label: s.text, enabled: false },
    { type: 'separator' },
    { label: 'Open Spellmind', click: () => openWindow() },
    { label: 'Start when I log in to Windows', type: 'checkbox', checked: loginItem.get(), click: (item) => { CALLS.setApp({ startAtLogin: item.checked }); pushStatus(); } },
    { label: 'Restart the link', click: () => { note('Restarting the link.'); sup.restart(); } },
    { type: 'separator' },
    { label: 'Quit Spellmind', click: () => { quitting = true; app.quit(); } },
  ]));
}

function createTray() {
  const icon = nativeImage.createFromPath(path.join(HERE, 'assets', 'tray.png'));
  tray = new Tray(icon);
  tray.on('click', () => openWindow());
  refreshTray();
}

// ---------------------------------------------------------------------------
// The window.

function openWindow() {
  if (win && !win.isDestroyed()) { if (win.isMinimized()) win.restore(); win.show(); win.focus(); return; }
  win = new BrowserWindow({
    width: 620, height: 760, minWidth: 520, minHeight: 560,
    title: 'Spellmind', icon: path.join(HERE, 'assets', 'icon.png'), backgroundColor: '#120b2e', show: false, autoHideMenuBar: true,
    webPreferences: { preload: path.join(HERE, 'preload.cjs'), contextIsolation: true, sandbox: true, nodeIntegration: false, spellcheck: false },
  });
  win.removeMenu();
  // Nothing navigates away or opens a window of its own; links go to the browser through openLink.
  win.webContents.on('will-navigate', (e) => e.preventDefault());
  win.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  win.on('close', (e) => { if (!quitting) { e.preventDefault(); win.hide(); } });
  // Minimized: into the tray, off the taskbar (a switch in the window).
  win.on('minimize', (e) => { if (appSettings().minimizeToTray) { e.preventDefault(); win.hide(); } });
  win.once('ready-to-show', () => {
    win.show();
    // --shot <file.png>, from source only: a picture of the window once it's drawn (to check the layout).
    const at = process.argv.indexOf('--shot');
    if (!app.isPackaged && at > 0 && process.argv[at + 1]) {
      setTimeout(async () => {
        try {
          const file = process.argv[at + 1];
          // --shot-ai <id>: the picker on that AI first (its setup shown; nothing is switched).
          const ai = process.argv[process.argv.indexOf('--shot-ai') + 1];
          if (process.argv.includes('--shot-ai') && /^[a-z]+$/.test(ai || '')) {
            await win.webContents.executeJavaScript(`(() => { const s = document.getElementById('aiPick'); s.value = '${ai}'; viewing = '${ai}'; draw(last); })()`);
            await new Promise(r => setTimeout(r, 300));
          }
          fs.writeFileSync(file, (await win.webContents.capturePage()).toPNG());
          await win.webContents.executeJavaScript('window.scrollTo(0, document.body.scrollHeight)');
          await new Promise(r => setTimeout(r, 300));
          fs.writeFileSync(file.replace(/\.png$/, '-end.png'), (await win.webContents.capturePage()).toPNG());
        } catch { /* a check only */ }
      }, 2500);
    }
  });
  win.loadFile(path.join(HERE, 'renderer', 'index.html'));
}

// ---------------------------------------------------------------------------
// The window's calls (preload.cjs lists them).

const CALLS = {
  status: () => fullStatus(),

  setAI: async (change) => {
    const r = applyAI(readConfig(DATA), change || {}, manifests);
    if (!r.ok) return r;
    writeConfig(DATA, r.cfg);
    note('Settings saved: restarting the link.');
    await sup.restart();
    return { ok: true };
  },

  // The ChatGPT plan: the browser sign-in; once in, the link uses it.
  signIn: async () => {
    const session = sessionFor(PLAN);
    if (!session) return { ok: false, error: 'unsupported' };
    signingIn = session;
    pushStatus();
    try {
      const r = await session.start({ openUrl: (url) => shell.openExternal(url) });
      if (r.ok) {
        const picked = await aiSetup.choose(readConfig(DATA), PLAN.id);
        await useCfg(picked.ok ? picked.cfg : readConfig(DATA), `Signed in with your ChatGPT${r.plan ? ' ' + r.plan : ''} plan.`);
      }
      return r.ok ? { ok: true, plan: r.plan } : { ok: false, error: r.error };
    } finally { signingIn = null; pushStatus(); }
  },
  cancelSignIn: () => { signingIn?.cancel(); return { ok: true }; },
  signOut: async () => {
    await keystore.delete(PLAN.id);
    sessionFor(PLAN)?.signOut();
    note('Signed out of the ChatGPT plan.');
    await sup.restart();
    return { ok: true };
  },

  // An API key from the clipboard, read here (the window never sees it): which AI it's for, a live
  // test, then the OS credential store. The clipboard is cleared once it's kept.
  pasteKey: async () => {
    const text = clipboard.readText();
    const r = await aiSetup.pasteKey(readConfig(DATA), text);
    if (!r.ok) return { ok: false, error: r.error, detail: r.detail };
    if (clipboard.readText() === text) clipboard.clear();
    await useCfg(r.cfg, `${r.card}: key saved and working.`);
    return { ok: true, card: r.card };
  },
  removeKey: async (id) => {
    const r = await aiSetup.removeKey(readConfig(DATA), String(id || ''));
    if (r.ok) { note('Key removed.'); await sup.restart(); }
    return r;
  },
  // Other: an OpenAI-compatible address and model, with the key from the clipboard when asked.
  connectCustom: async (p) => {
    const keyText = p?.withKey ? clipboard.readText() : null;
    const r = await aiSetup.connectCustom(readConfig(DATA), { baseUrl: String(p?.baseUrl || ''), model: String(p?.model || '') }, keyText);
    if (!r.ok) return r;
    if (keyText && clipboard.readText() === keyText) clipboard.clear();
    await useCfg(r.cfg, `Connected to ${r.cfg.custom.model} at ${new URL(r.cfg.custom.baseUrl).host}.`);
    return { ok: true };
  },
  chooseAI: async (id) => {
    const r = await aiSetup.choose(readConfig(DATA), String(id || ''));
    if (!r.ok) return r;
    await useCfg(r.cfg, 'Switched AI: restarting the link.');
    return { ok: true };
  },
  // An AI's API key page, from its manifest only (never a URL the window sends).
  openKeysPage: async (id) => {
    const url = manifests.find(m => m.id === id)?.links?.keys;
    if (typeof url !== 'string' || !url.startsWith('https://')) return { ok: false, error: 'no_link' };
    await shell.openExternal(url);
    return { ok: true };
  },

  chooseWow: async () => {
    // It opens where WoW is (the saved folder, or one found on this computer).
    const near = readConfig(DATA).wow || findFlavorDirs()[0] || null;
    const r = await dialog.showOpenDialog(win, { title: 'Your WoW: Forever folder (_forever_)', properties: ['openDirectory'], ...(near ? { defaultPath: near } : {}) });
    if (r.canceled || !r.filePaths[0]) return { ok: false, error: 'cancelled' };
    // The _forever_ folder, or the "World of Warcraft" folder above it.
    const dir = flavorIn(r.filePaths[0]);
    if (!dir) return { ok: false, error: 'not_a_wow_folder', detail: 'That folder doesn\'t look like WoW: Forever\'s. Pick the _forever_ folder (the one with Interface and WTF in it), or the World of Warcraft folder above it.' };
    writeConfig(DATA, { ...readConfig(DATA), wow: dir });
    await sup.restart();
    return { ok: true, folder: dir };
  },

  // Install or update the addon. With WoW running, only changed files are copied (they load on
  // /reload); a new file needs WoW closed, since the game reads new files only when it starts.
  installAddon: async () => {
    const cfg = readConfig(DATA);
    if (!cfg.wow) return { ok: false, error: 'no_folder', detail: 'Pick your WoW folder first.' };
    const before = addonState({ flavorDir: cfg.wow });
    const running = wowRunning().running;
    if (running && (before.state === 'missing' || before.added > 0)) return { ok: false, error: 'wow_running', detail: RUNNING_LINE };
    const r = installAddon({ flavorDir: cfg.wow, force: running });
    if (!r.ok) return r;
    note(running ? 'Addon updated: type /reload in game.' : 'Addon installed.');
    await sup.restart();
    return { ok: true, reload: running, note: running ? 'Type /reload in game to load the new files.' : r.note };
  },

  setLoginItem: (on) => CALLS.setApp({ startAtLogin: !!on }),
  // The app's switches: only the known ones, only true or false.
  setApp: (change) => {
    const next = { ...appSettings() };
    for (const [k, v] of Object.entries(change || {})) {
      if (!Object.hasOwn(APP_DEFAULTS, k) || typeof v !== 'boolean') return { ok: false, error: 'bad_setting' };
      next[k] = v;
    }
    writeConfig(DATA, { ...readConfig(DATA), app: next });
    if (Object.hasOwn(change, 'startAtLogin')) { loginItem.set(next.startAtLogin); refreshTray(); }
    if (change?.updateAddon === true) updateAddonIfOld('turned on');
    return { ok: true };
  },
  restartLink: async () => { note('Restarting the link.'); await sup.restart(); return { ok: true }; },
  openLogs: async () => { await shell.openPath(DATA); return { ok: true }; },
};

for (const [name, fn] of Object.entries(CALLS)) {
  ipcMain.handle(`spellmind:${name}`, async (e, payload) => {
    // Only this app's own page may call.
    if (!win || e.sender !== win.webContents) return { ok: false, error: 'refused' };
    try { return await fn(payload); } catch (err) { return { ok: false, error: 'failed', detail: String(err?.message || err).slice(0, 200) }; }
  });
}

// ---------------------------------------------------------------------------
// Start.

app.on('second-instance', (_e, argv) => {
  if (Array.isArray(argv) && argv.includes('--quit')) { quitting = true; app.quit(); return; }
  openWindow();
});
app.on('window-all-closed', () => { /* the tray keeps it running */ });
app.on('before-quit', () => { quitting = true; });
app.on('will-quit', (e) => {
  if (linkState.phase === 'stopped') return;
  e.preventDefault();
  sup.stop().finally(() => { linkState = { phase: 'stopped', restarts: 0 }; app.quit(); });
});

app.whenReady().then(() => {
  fs.mkdirSync(DATA, { recursive: true });
  // No WoW folder yet: the one WoW: Forever folder on this computer, when there's exactly one.
  if (!readConfig(DATA).wow) {
    const found = findFlavorDirs();
    if (found.length === 1) { writeConfig(DATA, { ...readConfig(DATA), wow: found[0] }); note(`Found your WoW folder: ${found[0]}`); }
  }
  // Start at login is on unless the player turned it off (the point of the app: the link is there
  // when the game is). Written on every start, so the Run value names this copy: the installed one
  // after an install, not a run from source before it.
  loginItem.set(appSettings().startAtLogin);
  createTray();
  updateAddonIfOld('Spellmind started');
  sup.start();
  // A login start stays in the tray; a start by hand, or one with any setup step undone, opens the window.
  if (!HIDDEN) openWindow();
  else fullStatus().then((s) => { if (!s.wow.ok || s.wow.addon.state === 'missing' || !s.ai.ready) openWindow(); }).catch(() => openWindow());
});
