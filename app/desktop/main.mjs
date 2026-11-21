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
import { app, BrowserWindow, Tray, Menu, nativeImage, nativeTheme, dialog, ipcMain, shell, utilityProcess, Notification, session } from 'electron';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { dataDir, readConfig, writeConfig } from '../../core/app/runner.mjs';
import { newsSince, card } from '../../core/news.mjs';
import { createSupervisor } from '../../core/app/supervisor.mjs';
import { aiChoices, applyAI } from '../../core/app/settings.mjs';
import { createAISetup } from '../../core/app/ai.mjs';
import { eventLine } from '../../core/app/lines.mjs';
import { installAddon, addonState, looksLikeFlavor, flavorIn, findFlavorDirs, wowRunning, shouldUpdate, RUNNING_LINE } from '../../core/link/install.mjs';
import { loadManifests, checkCustomUrl } from '../../core/ai/providers/index.mjs';
import { createKeyStore } from '../../core/ai/security/keystore.mjs';
import { createEgress } from '../../core/ai/security/egress.mjs';
import { createSignIns } from '../../core/ai/signin/index.mjs';
import { IDENTITY } from '../../core/identity.mjs';
import { createUpdater } from './updater.mjs';
import { uploadGround, syncRoads, applyRoads, roadsStatus, ROADS_URL } from '../../core/roads/share.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
// SPELLMIND_DATA: another data folder (a first run seen from source, the tests); the player's is dataDir().
const DATA = (!app.isPackaged && process.env.SPELLMIND_DATA) || dataDir();
const HIDDEN = process.argv.includes('--hidden');
const ACTIVITY_MAX = 40;

// A run from source is Electron's own exe: its own app id, so Windows never gives the installed app its
// icon (the player, 2026-11-13: the taskbar showed Electron's atom after a run from source).
app.setAppUserModelId(app.isPackaged ? IDENTITY.appId : `${IDENTITY.appId}.dev`);
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
const APP_DEFAULTS = Object.freeze({ startAtLogin: true, minimizeToTray: true, notifications: true, updateAddon: true, checkUpdates: true });
const appSettings = () => ({ ...APP_DEFAULTS, ...(readConfig(DATA).app || {}) });

// The errors the player has to act on (core/ai/providers/errors.mjs kinds), each with the pill's
// words, its tone, and a notification's title. In the AI's own terms: a key isn't a sign-in, and a
// slow-down isn't a spent plan (the audit: "Sign in again" for a refused Claude key; "Your AI plan's
// limit is reached" for every limit). The notification's body is the line the game showed.
const ACT_ON = Object.freeze({
  oauth_expired: ['bad', 'Sign in again', 'Your sign-in ended'],
  auth_invalid: ['bad', 'Your AI key was refused', 'Your AI key was refused'],
  no_key: ['bad', 'Set up your AI', 'Your AI isn\'t set up'],
  out_of_credit: ['warn', 'Your AI account is out of credit', 'Out of credit'],
  spend_limit: ['warn', 'Your AI spend limit is reached', 'Spend limit reached'],
  rate_limited_daily: ['warn', 'Your AI\'s daily limit is reached', 'Daily limit reached'],
  model_not_found: ['warn', 'Pick another model', 'That model isn\'t available'],
  region_blocked: ['warn', 'Pick another AI', 'Your AI isn\'t available where you are'],
});
// Passing: shown while it lasts, no notification.
const PASSING = Object.freeze({ rate_limited: 'Your AI asked to slow down', overloaded: 'Your AI is busy right now' });
let failStreak = 0; // restarts in a row without the link staying up
const told = new Set(); // what a notification has said this session

// A desktop notification, once per thing until it's resolved; a click opens the window.
function notify(key, title, body) {
  if (told.has(key) || !appSettings().notifications || !Notification.isSupported()) return;
  // Not from source: Electron makes a Start menu shortcut ("Electron", its own exe, no app) for a
  // notification's app id, and Windows then gave the installed app's taskbar button its atom and a
  // relaunch into bare Electron (2026-11-13).
  if (!app.isPackaged) { note(`(A notification, from source: ${title})`); return; }
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
  // Only forward (core/link/install.mjs shouldUpdate): never over a newer addon, from CurseForge or a
  // newer app (the security review: an older copy of the app wrote its older addon back).
  const plan = shouldUpdate(st, app.getVersion());
  if (!plan.update) {
    if (plan.why === 'newer_installed') note(`The game has a newer Spellmind addon (${st.installedVersion}) than this app's (${st.version}): left as it is. Update the app to match.`);
    else note("The addon differs from this app's, but it's the same or a newer version: left as it is. Update in the window to replace it.");
    return;
  }
  if (wowRunning().running) { note('An addon update is ready: it goes in when WoW closes.'); return; }
  const r = installAddon({ flavorDir: cfg.wow, version: app.getVersion() });
  if (r.ok) roadsAgain();
  if (r.ok) {
    note(`Addon updated (${why}).`);
    told.delete('addon-updated');
    notify('addon-updated', 'Spellmind\'s addon is up to date', 'The new version loads the next time you start WoW.');
  } else note(`The addon couldn't be updated: ${r.detail || r.error}`);
  pushStatus();
}

// ---------------------------------------------------------------------------
// Shared roads (core/roads/share.mjs, server/roads/README.md): what's new in the ground walked goes up about once a
// day (unless the game's "Share the ground I walk" is off), and the roads merged come back into the addon. Only
// the roads' Worker can be reached this way (the same allowlisted fetch as the AI's). Off until ROADS_URL is set.
const roadsFetch = ROADS_URL ? createEgress({ allowHosts: () => new Set([new URL(ROADS_URL).hostname]), loopbackOk: false }).fetch : null;
async function roadsTick() {
  const cfg = readConfig(DATA);
  if (!roadsFetch || !cfg.wow) return;
  try { await uploadGround({ flavorDir: cfg.wow, dataDir: DATA, version: app.getVersion(), fetchFn: roadsFetch, log: note }); } catch (e) { note(`Roads: ${e.message}`); }
  try {
    const r = await syncRoads({ flavorDir: cfg.wow, dataDir: DATA, fetchFn: roadsFetch, log: note });
    if (r.applied) note(`Roads of ${r.date} in the addon: they load at the next /reload.`);
  } catch (e) { note(`Roads: ${e.message}`); }
  pushStatus();
}
// After an addon install put the app's own Roads.lua in place: the newer roads kept here, again.
function roadsAgain() {
  const cfg = readConfig(DATA);
  if (cfg.wow) { try { applyRoads({ flavorDir: cfg.wow, dataDir: DATA }); } catch { /* the addon works without them */ } }
}

// ---------------------------------------------------------------------------
// The app's own updates (updater.mjs): the installed app on Windows only; a run from source has none.
let updates = null;
async function startUpdates() {
  if (!app.isPackaged || process.platform !== 'win32') return;
  try {
    const mod = await import('electron-updater');
    const autoUpdater = mod.autoUpdater ?? mod.default?.autoUpdater;
    autoUpdater.autoDownload = false;
    autoUpdater.autoInstallOnAppQuit = true;
    autoUpdater.allowDowngrade = false;
    autoUpdater.allowPrerelease = false;
    autoUpdater.logger = null;
    updates = createUpdater({
      updater: autoUpdater,
      current: app.getVersion(),
      wowRunning: () => wowRunning().running,
      onChange: (s) => {
        if (s.phase === 'available' && !s.error) {
          note(`Spellmind ${s.version} is available.`);
          notify('update', `Spellmind ${s.version} is available`, 'Open Spellmind to update it.');
        }
        if (s.phase === 'ready') note(`Spellmind ${s.version} is downloaded: it installs when you restart Spellmind.`);
        pushStatus();
      },
    });
    updates.schedule(appSettings().checkUpdates);
  } catch {
    note('Updates can\'t be checked in this copy: download new versions from the releases page.');
  }
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
      // An answer came: what needed acting on is fixed; a later failure may say so again.
      if (k === 'reply') for (const key of [...told]) if (key.startsWith('error:')) told.delete(key);
      if (k === 'turn-error' && Object.hasOwn(ACT_ON, m.ev.what)) {
        notify(`error:${m.ev.what}`, `Spellmind: ${ACT_ON[m.ev.what][2]}`, m.ev.text || 'Open Spellmind to see what happened.');
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
const fetchFor = (m) => createEgress({ allowHosts: () => new Set(m.hosts), loopbackOk: m.custom === true }).fetch;
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
// Only the installed app writes it: a run from source would point Windows at Electron's exe and this
// folder (the security review), and take the installed app's entry.
const loginItem = {
  get: () => !!app.getLoginItemSettings({ path: process.execPath, args: loginArgs() }).openAtLogin,
  set: (on) => { if (app.isPackaged) app.setLoginItemSettings({ openAtLogin: !!on, path: process.execPath, args: loginArgs() }); },
};

// ---------------------------------------------------------------------------
// What the window and the tray show.

function summary() {
  const s = runStatus;
  // The setup card says which step; the pill only that there's one (the review: a long sentence in it).
  if (linkState.phase === 'setup' || setupError || setupNeeded) return { tone: 'warn', text: 'Finish the setup' };
  if (linkState.phase === 'gave-up') return { tone: 'bad', text: 'The link keeps stopping: restart it' };
  if (linkState.phase === 'restarting') return { tone: 'warn', text: `Restarting the link in ${Math.round((linkState.delayMs || 0) / 1000)} s` };
  if (linkState.phase !== 'running') return { tone: 'off', text: 'The link is stopped' };
  if (s?.error && Object.hasOwn(ACT_ON, s.error)) return { tone: ACT_ON[s.error][0], text: ACT_ON[s.error][1] };
  if (s?.error && Object.hasOwn(PASSING, s.error)) return { tone: 'warn', text: PASSING[s.error] };
  if (s?.wow === 'running' || s?.wow === 'launched') return { tone: 'good', text: s.hello ? 'Connected to WoW' : 'WoW is running: waiting for the addon' };
  return { tone: 'idle', text: 'Waiting for WoW' };
}

// What's new after the app updated itself (core/news.mjs): the entries after config.json's seenVersion.
// A first run (nothing set up yet) has none to show; a setup from before seenVersion existed shows this
// version's (the player, 2026-11-19: updating from 0.4 to the route should say so).
function newsState() {
  const cfg = readConfig(DATA);
  const current = app.getVersion();
  if (!cfg.seenVersion) {
    if (Object.keys(cfg).length === 0) { writeConfig(DATA, { seenVersion: current }); return []; }
    return newsSince('0', current);
  }
  return cfg.seenVersion === current ? [] : newsSince(cfg.seenVersion, current);
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
    update: updates ? updates.state() : { phase: 'off' },
    activity: activity.slice().reverse(),
    roads: roadsStatus(DATA),
    news: card(newsState()),
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
    ...updateItems(),
    { type: 'separator' },
    { label: 'Quit Spellmind', click: () => { quitting = true; app.quit(); } },
  ]));
}

// An update on offer, in the tray's menu too.
function updateItems() {
  const u = updates?.state();
  if (u?.phase === 'available') return [{ label: `Update to ${u.version}`, click: () => { CALLS.downloadUpdate(); } }];
  if (u?.phase === 'ready') return [{ label: `Restart to update to ${u.version}`, click: () => { const r = CALLS.installUpdate(); if (!r.ok) openWindow(); } }];
  return [];
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
  // The app's own updates: a check if the last one is over an hour old (updater.mjs STALE_MS).
  if (updates && appSettings().checkUpdates) updates.checkIfStale();
  if (win && !win.isDestroyed()) { if (win.isMinimized()) win.restore(); win.show(); win.focus(); return; }
  win = new BrowserWindow({
    width: 620, height: 760, minWidth: 520, minHeight: 560,
    title: 'Spellmind', icon: path.join(HERE, 'assets', 'icon.png'), backgroundColor: '#120b2e', show: false, autoHideMenuBar: true,
    webPreferences: { preload: path.join(HERE, 'preload.cjs'), contextIsolation: true, sandbox: true, nodeIntegration: false, spellcheck: false },
  });
  // No menu bar, but a hidden menu that keeps zoom (Ctrl + and Ctrl -; the review: removing the menu took it).
  win.setMenu(Menu.buildFromTemplate([
    { label: 'Edit', submenu: [{ role: 'undo' }, { role: 'redo' }, { role: 'cut' }, { role: 'copy' }, { role: 'paste' }, { role: 'selectAll' }] },
    { label: 'View', submenu: [{ role: 'zoomIn' }, { role: 'zoomIn', accelerator: 'CommandOrControl+=', visible: false }, { role: 'zoomOut' }, { role: 'resetZoom' }] },
  ]));
  win.setMenuBarVisibility(false);
  // The taskbar button's own record: this exe's icon, and this exe to relaunch from a pin (the player,
  // 2026-11-13: after runs from source shared the app id, Windows showed Electron's atom and a pin
  // started bare Electron, its "To run a local app" page). Written on every window, so it mends a stale record.
  if (app.isPackaged && process.platform === 'win32' && typeof win.setAppDetails === 'function') {
    win.setAppDetails({ appId: IDENTITY.appId, appIconPath: process.execPath, appIconIndex: 0, relaunchCommand: `"${process.execPath}"`, relaunchDisplayName: 'Spellmind' });
  }
  // A right-click in a field: Cut, Copy, Paste, Select all (pasting a key or an address by mouse).
  win.webContents.on('context-menu', (_e, params) => {
    if (!params.isEditable) return;
    Menu.buildFromTemplate([{ role: 'cut' }, { role: 'copy' }, { role: 'paste' }, { type: 'separator' }, { role: 'selectAll' }]).popup({ window: win });
  });
  // Nothing navigates away or opens a window of its own; links go to the browser through openLink.
  win.webContents.on('will-navigate', (e) => e.preventDefault());
  win.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  win.on('close', (e) => { if (!quitting) { e.preventDefault(); win.hide(); } });
  // Minimized: into the tray, off the taskbar (a switch in the window).
  win.on('minimize', (e) => { if (appSettings().minimizeToTray) { e.preventDefault(); win.hide(); } });
  win.once('ready-to-show', () => {
    win.show();
    // --shot (from source only): app/desktop/dev-shot.mjs, which the installed app doesn't have.
    if (!app.isPackaged && process.argv.includes('--shot')) import('./dev-shot.mjs').then(d => d.shoot(win, process.argv)).catch(() => {});
  });
  win.loadFile(path.join(HERE, 'renderer', 'index.html'));
}

// ---------------------------------------------------------------------------
// The window's calls (preload.cjs lists them).

const keyText = (p) => (typeof p?.key === 'string' && p.key.length <= 4096 ? p.key : '');

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

  // An API key from the window's field (the player, 2026-11-13: reading the clipboard said it was empty
  // when it wasn't): which AI it's for by its shape, a live test, then the OS credential store. It's never
  // sent back to the window, logged, or shown again.
  saveKey: async (p) => {
    const r = await aiSetup.pasteKey(readConfig(DATA), keyText(p));
    if (!r.ok) return { ok: false, error: r.error, detail: r.detail };
    await useCfg(r.cfg, `${r.card}: key saved and working.`);
    return { ok: true, card: r.card };
  },
  removeKey: async (id) => {
    const r = await aiSetup.removeKey(readConfig(DATA), String(id || ''));
    if (r.ok) { note('Key removed.'); await sup.restart(); }
    return r;
  },
  // Other: an OpenAI-compatible address and model, with a key from the window's field when one's given.
  connectCustom: async (p) => {
    const key = keyText(p).trim() || null;
    // A new address: the player says yes in a dialog of the app's own before anything goes there (the
    // security review: one call sent the clipboard and every later question to any address typed in).
    const c = checkCustomUrl(String(p?.baseUrl || ''));
    if (c.ok) {
      const cfg = readConfig(DATA);
      let known = null;
      try { known = cfg.custom?.baseUrl ? new URL(cfg.custom.baseUrl).host : null; } catch { known = null; }
      if (c.host !== known) {
        const clear = key && c.baseUrl.startsWith('http:') && !c.local;
        const r = await dialog.showMessageBox(win, {
          type: clear ? 'warning' : 'question', buttons: ['Connect', 'Cancel'], defaultId: 1, cancelId: 1, noLink: true,
          title: 'Spellmind', message: `Send your questions and game data to ${c.host}?`,
          detail: (c.local ? 'A server on this computer: nothing leaves it.' : 'Everything you ask Spellmind from now on goes to this service, with your character\'s data.')
            + (key ? ' Your key goes with it.' : '')
            + (clear ? '\n\nThis address is http: the key travels unencrypted over your network.' : ''),
        });
        if (r.response !== 0) return { ok: false, error: 'cancelled' };
      }
    }
    const r = await aiSetup.connectCustom(readConfig(DATA), { baseUrl: String(p?.baseUrl || ''), model: String(p?.model || '') }, key);
    if (!r.ok) return r;
    await useCfg(r.cfg, `Connected to ${r.cfg.custom.model} at ${new URL(r.cfg.custom.baseUrl).host}.`);
    return { ok: true };
  },
  disconnectCustom: async () => {
    const r = await aiSetup.disconnectCustom(readConfig(DATA));
    await useCfg(r.cfg, 'Other disconnected: its key and address are gone.');
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
    const r = installAddon({ flavorDir: cfg.wow, force: running, version: app.getVersion() });
    if (!r.ok) return r;
    roadsAgain();
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
    if (Object.hasOwn(change, 'checkUpdates')) updates?.schedule(next.checkUpdates);
    return { ok: true };
  },
  // The app's own updates (updater.mjs).
  checkUpdate: async () => (updates ? updates.check({ manual: true }) : { ok: false, error: 'no_updates', detail: 'Only the installed app updates itself.' }),
  downloadUpdate: async () => (updates ? updates.download() : { ok: false, error: 'no_updates' }),
  installUpdate: () => {
    if (!updates) return { ok: false, error: 'no_updates' };
    const was = quitting;
    quitting = true;
    const r = updates.install();
    if (!r.ok) quitting = was;
    return r;
  },
  restartLink: async () => { note('Restarting the link.'); await sup.restart(); return { ok: true }; },
  // What's new, read: not shown again until the next version.
  seenNews: async () => { writeConfig(DATA, { ...readConfig(DATA), seenVersion: app.getVersion() }); pushStatus(); return { ok: true }; },
  openLogs: async () => { await shell.openPath(DATA); return { ok: true }; },
};

const SETUP_WORDS = { signIn: 'Signing in', saveKey: 'Saving the key', connectCustom: 'Connecting to Other', chooseWow: 'Picking the WoW folder', installAddon: 'Installing the addon' };
for (const [name, fn] of Object.entries(CALLS)) {
  ipcMain.handle(`spellmind:${name}`, async (e, payload) => {
    // Only this app's own page may call.
    if (!win || e.sender !== win.webContents || e.senderFrame?.url !== PAGE_URL) return { ok: false, error: 'refused' };
    let r;
    try { r = await fn(payload); } catch (err) { r = { ok: false, error: 'failed', detail: String(err?.message || err).slice(0, 200) }; }
    // A setup step that failed goes in Activity too, so it can be read again (the review).
    if (r && r.ok === false && SETUP_WORDS[name] && r.error !== 'cancelled') { note(`${SETUP_WORDS[name]} didn't work: ${r.detail || r.error}`); pushStatus(); }
    return r;
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

// The window's page, and nothing else, may call (its frame's address checked, not only its window).
const PAGE_URL = pathToFileURL(path.join(HERE, 'renderer', 'index.html')).href;

// Any web contents at all (the window's, or one that should never exist): no webviews, no new
// windows, no navigation away (the security review: defence in depth behind the page's own policy).
app.on('web-contents-created', (_e, wc) => {
  wc.on('will-attach-webview', (ev) => ev.preventDefault());
  wc.on('will-navigate', (ev) => ev.preventDefault());
  wc.setWindowOpenHandler(() => ({ action: 'deny' }));
});

app.whenReady().then(() => {
  // The page asks for nothing: camera, microphone, notifications, clipboard, all refused.
  session.defaultSession.setPermissionRequestHandler((_wc, _perm, done) => done(false));
  session.defaultSession.setPermissionCheckHandler(() => false);
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
  startUpdates();
  setTimeout(roadsTick, 60e3);
  setInterval(roadsTick, 3 * 3600e3);
  // A login start stays in the tray; a start by hand, or one with any setup step undone, opens the window.
  if (!HIDDEN) openWindow();
  else fullStatus().then((s) => { if (!s.wow.ok || s.wow.addon.state === 'missing' || !s.ai.ready) openWindow(); }).catch(() => openWindow());
});
