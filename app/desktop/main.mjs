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
import { app, BrowserWindow, Tray, Menu, nativeImage, dialog, ipcMain, shell, utilityProcess } from 'electron';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { dataDir, readConfig, writeConfig } from '../../core/app/runner.mjs';
import { createSupervisor } from '../../core/app/supervisor.mjs';
import { aiChoices, applyAI } from '../../core/app/settings.mjs';
import { eventLine } from '../../core/app/lines.mjs';
import { installAddon, addonState, looksLikeFlavor, wowRunning, RUNNING_LINE } from '../../core/link/install.mjs';
import { loadManifests } from '../../core/ai/providers/index.mjs';
import { createKeyStore } from '../../core/ai/security/keystore.mjs';
import { createEgress } from '../../core/ai/security/egress.mjs';
import { createSignIns } from '../../core/ai/signin/index.mjs';
import { IDENTITY } from '../../core/identity.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const DATA = dataDir();
const HIDDEN = process.argv.includes('--hidden');
const ACTIVITY_MAX = 40;

app.setAppUserModelId(IDENTITY.appId);
if (!app.requestSingleInstanceLock()) { app.quit(); process.exit(0); }

let win = null, tray = null, quitting = false;
let linkState = { phase: 'stopped', restarts: 0 };
let runStatus = null; // the worker's last status: { ai, wow, reading, hello, lastAt, error }
let setupError = null; // what the worker needs before it can start
const activity = []; // { at, line }

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
    if (s.phase === 'restarting') note(`The link stopped; starting it again in ${Math.round(s.delayMs / 1000)} s.`);
    pushStatus();
  },
  onMessage: (m) => {
    if (m?.type === 'event') { runStatus = m.ev?.status || runStatus; note(eventLine(m.ev)); }
    else if (m?.type === 'status') runStatus = m.status;
    else if (m?.type === 'setup') setupError = m.detail || m.error;
    pushStatus();
  },
});

// ---------------------------------------------------------------------------
// The AI's sign-in (a ChatGPT plan), here in the app; the worker reads the same key store.

const manifests = loadManifests();
const keystore = createKeyStore({ backend: 'os' });
function signInFor(cfg) {
  const m = manifests.find(x => x.id === (cfg.provider || 'chatgpt'));
  if (!m) return { m: null, session: null };
  const egress = createEgress({ allowHosts: () => new Set(m.hosts), loopbackOk: true });
  return { m, session: createSignIns({ keystore, fetch: egress.fetch }).for(m) };
}
let signingIn = null;

async function aiStatus(cfg) {
  const choices = aiChoices(cfg, manifests);
  const { m, session } = signInFor(cfg);
  let signedIn = false;
  try { signedIn = session ? await session.signedIn() : !!(m && await keystore.get(m.id)); } catch { signedIn = false; }
  return { ...choices, signedIn, signingIn: !!signingIn };
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
  if (linkState.phase === 'setup' || setupError) return { tone: 'warn', text: setupError || 'Finish the setup' };
  if (linkState.phase === 'restarting') return { tone: 'warn', text: `Restarting the link in ${Math.round((linkState.delayMs || 0) / 1000)} s` };
  if (linkState.phase !== 'running') return { tone: 'off', text: 'The link is stopped' };
  if (s?.error === 'auth' || s?.error === 'expired') return { tone: 'bad', text: 'Sign in again' };
  if (s?.wow === 'running' || s?.wow === 'launched') return { tone: 'good', text: s.hello ? 'Linked to WoW' : 'WoW is running: waiting for the addon' };
  return { tone: 'idle', text: 'Waiting for WoW' };
}

async function fullStatus() {
  const cfg = readConfig(DATA);
  const wow = cfg.wow || null;
  return {
    version: app.getVersion(),
    packaged: app.isPackaged,
    summary: summary(),
    link: linkState,
    run: runStatus,
    ai: await aiStatus(cfg),
    wow: { folder: wow, ok: !!wow && looksLikeFlavor(wow), addon: wow ? addonState({ flavorDir: wow }) : { state: 'missing' } },
    loginItem: loginItem.get(),
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
    { label: 'Start when I log in to Windows', type: 'checkbox', checked: loginItem.get(), click: (item) => { loginItem.set(item.checked); pushStatus(); } },
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
  win.once('ready-to-show', () => {
    win.show();
    // --shot <file.png>, from source only: a picture of the window once it's drawn (to check the layout).
    const at = process.argv.indexOf('--shot');
    if (!app.isPackaged && at > 0 && process.argv[at + 1]) {
      setTimeout(async () => {
        try {
          const file = process.argv[at + 1];
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

  signIn: async () => {
    const { session } = signInFor(readConfig(DATA));
    if (!session) return { ok: false, error: 'unsupported' };
    signingIn = session;
    pushStatus();
    try {
      const r = await session.start({ openUrl: (url) => shell.openExternal(url) });
      if (r.ok) { note(`Signed in with your ChatGPT${r.plan ? ' ' + r.plan : ''} plan.`); await sup.restart(); }
      return r.ok ? { ok: true, plan: r.plan } : { ok: false, error: r.error };
    } finally { signingIn = null; pushStatus(); }
  },
  cancelSignIn: () => { signingIn?.cancel(); return { ok: true }; },
  signOut: async () => {
    const { m, session } = signInFor(readConfig(DATA));
    if (m) await keystore.delete(m.id);
    session?.signOut();
    note('Signed out.');
    await sup.restart();
    return { ok: true };
  },

  chooseWow: async () => {
    const r = await dialog.showOpenDialog(win, { title: 'Your WoW: Forever folder (_forever_)', properties: ['openDirectory'] });
    if (r.canceled || !r.filePaths[0]) return { ok: false, error: 'cancelled' };
    const dir = r.filePaths[0];
    if (!looksLikeFlavor(dir)) return { ok: false, error: 'not_a_wow_folder', detail: 'That folder doesn\'t look like WoW: Forever\'s. Pick the _forever_ folder (the one with Interface and WTF in it).' };
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

  setLoginItem: (on) => { loginItem.set(!!on); refreshTray(); return { ok: true, on: loginItem.get() }; },
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

app.on('second-instance', () => openWindow());
app.on('window-all-closed', () => { /* the tray keeps it running */ });
app.on('before-quit', () => { quitting = true; });
app.on('will-quit', (e) => {
  if (linkState.phase === 'stopped') return;
  e.preventDefault();
  sup.stop().finally(() => { linkState = { phase: 'stopped', restarts: 0 }; app.quit(); });
});

app.whenReady().then(() => {
  fs.mkdirSync(DATA, { recursive: true });
  const cfg = readConfig(DATA);
  // Start at login is on unless the player turned it off (the point of the app: the link is there
  // when the game is).
  if (!cfg.loginItemSet) { loginItem.set(true); writeConfig(DATA, { ...cfg, loginItemSet: true }); }
  createTray();
  sup.start();
  // A login start stays in the tray; a start by hand, or one that still needs setup, opens the window.
  if (!HIDDEN || !cfg.wow) openWindow();
});
