// Spellmind's installer: the addon, its 200 slot addons and its doorbells into a WoW: Forever
// AddOns folder, while the game is closed (the client reads TOCs and sees doorbell files only at its
// start). Parts adapted from NeverQuestAlone's bridge/byok/wow.mjs (MIT; see NOTICE.md): the flavor
// folders, the process check and the addon copy.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { installSlots, SLOT_COUNT, countSlots } from './slots.mjs';
import { signalPaths, BELLS } from './signals.mjs';
import { roadsDate } from '../roads/pack.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
export const ADDON_NAME = 'Spellmind';
export const ADDON_SOURCE = path.resolve(HERE, '..', '..', 'addon', ADDON_NAME);
/** Flavor folders a Forever client installs under, best first. */
export const FOREVER_FLAVORS = Object.freeze(['_forever_', '_classic_beta_']);
/** Exes in a flavor folder that aren't the game: the voice proxy and the crash reporter. */
export const NOT_GAME = Object.freeze(['VoiceProxy', 'Error']);
export const RESTART_LINE = 'New addon files only load after a full restart of World of Warcraft, not /reload.';
export const RUNNING_LINE = `Quit World of Warcraft completely first (not just log out). ${RESTART_LINE}`;

const reEscape = s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const WIN_IMAGE = /^Wow[A-Za-z]*(?:-64|-ARM64)?\.exe$/i;
const NOT_GAME_IMAGE = new RegExp(['WowUp', ...NOT_GAME].map(reEscape).join('|'), 'i');

/** Wow*.exe pids in tasklist's CSV (not WowUp, the voice proxy or the crash reporter). */
export function parseTasklist(csv) {
  const pids = [];
  for (const line of String(csv || '').split(/\r?\n/)) {
    const m = /^"([^"]+)","(\d+)"/.exec(line.trim());
    if (m && WIN_IMAGE.test(m[1]) && !NOT_GAME_IMAGE.test(m[1])) pids.push(Number(m[2]));
  }
  return pids;
}

/** Is the game running? tasklist on Windows (by its full System32 path), pgrep elsewhere. */
export function wowRunning({ platform = process.platform, run = spawnSync, env = process.env } = {}) {
  let pids = [];
  if (platform === 'win32') {
    const tasklist = path.join(env.SystemRoot || env.windir || 'C:\\Windows', 'System32', 'tasklist.exe');
    const r = run(tasklist, ['/FO', 'CSV', '/NH'], { encoding: 'utf8', timeout: 8000, windowsHide: true });
    pids = parseTasklist(r?.stdout);
  } else {
    const r = run('pgrep', ['-f', platform === 'darwin' ? 'World of Warcraft[^/]*\\.app/Contents/MacOS/' : 'Wow[A-Za-z]*(-64)?\\.exe'], { encoding: 'utf8', timeout: 5000 });
    if (r?.status === 0) pids = String(r.stdout || '').split(/\s+/).filter(Boolean).map(Number).filter(n => Number.isInteger(n) && n !== process.pid);
  }
  return { running: pids.length > 0, pids };
}

/** The interface number in the addon's TOC (## Interface: 16001). */
export function addonInterface(source = ADDON_SOURCE) {
  try { return /^##\s*Interface:\s*(\d+)/m.exec(fs.readFileSync(path.join(source, `${ADDON_NAME}.toc`), 'utf8'))?.[1] ?? '16001'; } catch { return '16001'; }
}

/** A flavor folder looks like WoW's: it has Interface/ or WTF/ or a Wow*.exe in it. */
export function looksLikeFlavor(dir) {
  try {
    const names = fs.readdirSync(dir);
    return names.includes('Interface') || names.includes('WTF') || names.some(n => WIN_IMAGE.test(n));
  } catch { return false; }
}

/**
 * A picked folder as WoW: Forever's (the desktop app's picker): the flavor folder itself, or one of
 * the flavors inside a picked "World of Warcraft" folder. → the flavor folder, or null.
 */
export function flavorIn(dir, flavors = FOREVER_FLAVORS) {
  if (!dir) return null;
  const base = path.basename(dir);
  if (flavors.includes(base) && looksLikeFlavor(dir)) return dir;
  for (const f of flavors) { const inside = path.join(dir, f); if (looksLikeFlavor(inside)) return inside; }
  return looksLikeFlavor(dir) && fs.existsSync(path.join(dir, 'Interface')) ? dir : null;
}

/**
 * Where WoW: Forever may be installed on this computer (the app's first run, the review: the player
 * had to find the folder by hand). Battle.net's own record of WoW's folder first (the registry), then
 * "World of Warcraft" under Program Files and at each drive's root. → the flavor folders found.
 */
export function findFlavorDirs({ platform = process.platform, env = process.env, run = spawnSync, drives = ['C', 'D', 'E', 'F', 'G'], home = os.homedir() } = {}) {
  if (platform === 'linux') return findLinuxFlavorDirs(home);
  if (platform !== 'win32') return [];
  const roots = [];
  try {
    const reg = path.join(env.SystemRoot || env.windir || 'C:\\Windows', 'System32', 'reg.exe');
    for (const key of ['HKLM\\SOFTWARE\\WOW6432Node\\Blizzard Entertainment\\World of Warcraft', 'HKLM\\SOFTWARE\\Blizzard Entertainment\\World of Warcraft']) {
      const r = run(reg, ['query', key, '/v', 'InstallPath'], { encoding: 'utf8', timeout: 5000, windowsHide: true });
      const m = /InstallPath\s+REG_SZ\s+(.+)/i.exec(String(r?.stdout || ''));
      // It names a flavor folder (…\World of Warcraft\_retail_\): its parent holds the others.
      if (m) roots.push(path.dirname(m[1].trim().replace(/[\\/]+$/, '')));
    }
  } catch { /* no registry: the usual places */ }
  for (const d of drives) {
    roots.push(`${d}:\\Program Files (x86)\\World of Warcraft`, `${d}:\\Program Files\\World of Warcraft`, `${d}:\\World of Warcraft`, `${d}:\\Games\\World of Warcraft`);
  }
  const found = [];
  for (const root of [...new Set(roots)]) {
    for (const f of FOREVER_FLAVORS) {
      const dir = path.join(root, f);
      if (!found.some(x => x.toLowerCase() === dir.toLowerCase()) && looksLikeFlavor(dir)) found.push(dir);
    }
  }
  return found;
}

/**
 * On Linux, WoW: Forever runs under Wine or Proton, inside a prefix's drive_c (issue #1, 2026-11-21: Faugus
 * Launcher on Bazzite). The prefixes the usual launchers make, each one's drive_c searched as Windows' drives are.
 */
export const LINUX_PREFIX_PARENTS = Object.freeze([
  'Faugus', // Faugus Launcher: ~/Faugus/<game>
  'Games', // Lutris: ~/Games/<game>
  'Games/Heroic/Prefixes',
  '.local/share/Steam/steamapps/compatdata', // Steam (a non-Steam game under Proton): compatdata/<id>/pfx
  '.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/compatdata',
  '.local/share/bottles/bottles',
  '.var/app/com.usebottles.bottles/data/bottles/bottles',
  '.local/share/lutris/prefixes',
]);
export function findLinuxFlavorDirs(home = os.homedir()) {
  const prefixes = [path.join(home, '.wine')];
  for (const parent of LINUX_PREFIX_PARENTS) {
    let names = [];
    try { names = fs.readdirSync(path.join(home, parent), { withFileTypes: true }).filter(e => e.isDirectory()).map(e => e.name); } catch { continue; }
    for (const n of names.slice(0, 200)) {
      prefixes.push(path.join(home, parent, n));
      prefixes.push(path.join(home, parent, n, 'pfx')); // Steam's compatdata/<id>/pfx
    }
  }
  const found = [];
  for (const prefix of prefixes) {
    const c = path.join(prefix, 'drive_c');
    for (const root of [path.join(c, 'Program Files (x86)', 'World of Warcraft'), path.join(c, 'Program Files', 'World of Warcraft'), path.join(c, 'World of Warcraft'), path.join(c, 'Games', 'World of Warcraft')]) {
      for (const f of FOREVER_FLAVORS) {
        const dir = path.join(root, f);
        if (!found.includes(dir) && looksLikeFlavor(dir)) found.push(dir);
      }
    }
  }
  return found;
}

// A real folder at dir: a link or junction there is removed (never written through), then made.
// The security review: on a shared PC the WoW folder is often writable by every user, and a junction
// planted at AddOns\Spellmind sent the copy, at every app start, into another folder.
const lstat = p => { try { return fs.lstatSync(p); } catch { return null; } };
function realDirAt(dir) {
  const st = lstat(dir);
  if (st && st.isDirectory() && !st.isSymbolicLink()) return;
  if (st) fs.rmSync(dir, { recursive: true, force: true });
  fs.mkdirSync(dir, { recursive: true });
}

// Copy the addon's own files; keep sig/ (live doorbells), an Inbox.lua the service wrote, and a Roads.lua with roads
// as new as this copy's or newer (the app keeps it up to date: core/roads/share.mjs).
const roadsDay = (file) => { try { return roadsDate(fs.readFileSync(file, 'utf8')) || ''; } catch { return ''; } };
function copyAddon(src, dst) {
  realDirAt(dst);
  let files = 0;
  for (const e of fs.readdirSync(src, { withFileTypes: true })) {
    if (e.name === 'sig' || (e.name === 'Inbox.lua' && lstat(path.join(dst, 'Inbox.lua'))?.isFile())) continue;
    if (e.name === 'Roads.lua' && lstat(path.join(dst, 'Roads.lua'))?.isFile() && roadsDay(path.join(dst, 'Roads.lua')) >= roadsDay(path.join(src, 'Roads.lua'))) continue;
    const from = path.join(src, e.name);
    const to = path.join(dst, e.name);
    if (e.isDirectory()) { fs.rmSync(to, { recursive: true, force: true }); files += copyAddon(from, to); } else if (e.isFile()) {
      // A file that's a link: removed, not copied through.
      if (lstat(to)?.isSymbolicLink()) fs.rmSync(to, { force: true });
      fs.copyFileSync(from, to);
      files += 1;
    }
  }
  return files;
}

// The installed addon's marker: the app version that last installed it.
export const INSTALLED_BY = '.installed-by';
export function installedBy(flavorDir) {
  try { return fs.readFileSync(path.join(flavorDir, 'Interface', 'AddOns', ADDON_NAME, INSTALLED_BY), 'utf8').trim().slice(0, 32) || null; } catch { return null; }
}

/** The ## Version in an addon folder's TOC (the game's copy or this app's), or null. */
export function addonVersion(dir) {
  try { return /^##\s*Version:\s*([\w.-]{1,32})\s*$/m.exec(fs.readFileSync(path.join(dir, `${ADDON_NAME}.toc`), 'utf8'))?.[1] ?? null; } catch { return null; }
}

/** a < b for versions like 0.2.10 (numbers compared part by part). */
export function olderVersion(a, b) {
  const pa = String(a || '0').split('.').map(n => parseInt(n, 10) || 0), pb = String(b || '0').split('.').map(n => parseInt(n, 10) || 0);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) { const x = pa[i] || 0, y = pb[i] || 0; if (x !== y) return x < y; }
  return false;
}

/**
 * The installed addon against this copy's (the desktop app, docs/milestone-3.md): file by file, as
 * copyAddon copies them. → { state: 'missing' | 'current' | 'outdated', changed, added, installedBy,
 * installedVersion, version } where installedVersion and version are the two TOCs' and added
 * counts files the game hasn't got (those load only after a full restart of WoW; changed ones on
 * /reload).
 */
export function addonState({ flavorDir, source = ADDON_SOURCE } = {}) {
  const dst = flavorDir ? path.join(flavorDir, 'Interface', 'AddOns', ADDON_NAME) : null;
  if (!dst || !fs.existsSync(path.join(dst, `${ADDON_NAME}.toc`))) return { state: 'missing', changed: 0, added: 0 };
  let changed = 0, added = 0;
  const walk = (src, to) => {
    for (const e of fs.readdirSync(src, { withFileTypes: true })) {
      if (e.name === 'sig' || e.name === 'Inbox.lua' || e.name === 'Roads.lua') continue; // the app's to keep
      const from = path.join(src, e.name), there = path.join(to, e.name);
      if (e.isDirectory()) walk(from, there);
      else if (e.isFile()) {
        let have = null;
        try { have = fs.readFileSync(there); } catch { /* not there */ }
        if (!have) added += 1;
        else if (!have.equals(fs.readFileSync(from))) changed += 1;
      }
    }
  };
  try { walk(source, dst); } catch { return { state: 'missing', changed: 0, added: 0 }; }
  const installedVersion = addonVersion(dst), version = addonVersion(source);
  const newerInstalled = !!(installedVersion && version && olderVersion(version, installedVersion));
  return { state: changed + added > 0 ? 'outdated' : 'current', changed, added, installedBy: installedBy(flavorDir), installedVersion, version, newerInstalled };
}

/**
 * Install into flavorDir (…/World of Warcraft/_forever_). Refuses while the game runs.
 * → { ok, addonsDir, files, slots, bells } | { ok: false, error, detail }
 */
export function installAddon({ flavorDir, source = ADDON_SOURCE, count = SLOT_COUNT, running = wowRunning, force = false, version = null } = {}) {
  if (!flavorDir || !looksLikeFlavor(flavorDir)) return { ok: false, error: 'not_a_wow_folder', detail: `${flavorDir} doesn't look like a WoW: Forever folder (the one with Interface and WTF in it, like _forever_).` };
  if (!fs.existsSync(path.join(source, `${ADDON_NAME}.toc`))) return { ok: false, error: 'no_addon', detail: `No addon at ${source}.` };
  if (!force && running().running) return { ok: false, error: 'wow_running', detail: RUNNING_LINE };
  const addonsDir = path.join(flavorDir, 'Interface', 'AddOns');
  const files = copyAddon(source, path.join(addonsDir, ADDON_NAME));
  // Which app put it there, so an older app never writes its older addon over this one (the marker
  // isn't one of the addon's files: the game never reads it, and copyAddon leaves it).
  if (version) { try { fs.writeFileSync(path.join(addonsDir, ADDON_NAME, INSTALLED_BY), String(version)); } catch { /* the addon works without it */ } }
  const slots = installSlots(addonsDir, { count, iface: addonInterface(source) });
  const sig = signalPaths(addonsDir);
  const bells = [sig.present(), ...BELLS.map(sig.bell)].filter(f => fs.existsSync(f)).length;
  const have = countSlots(addonsDir);
  if (have < count) return { ok: false, error: 'slots_missing', detail: `Only ${have} of ${count} slot addons are in place.` };
  return { ok: true, addonsDir, files, slots, bells, note: RESTART_LINE };
}

/**
 * Whether the app's copy should go over the game's on its own (docs/curseforge.md): only forward.
 *   - The game's is a newer version (CurseForge or WowUp updated it first): left.
 *   - The same version: left, unless an older copy of this app put it there (a build between releases).
 *   - An older version: updated.
 * → { update: boolean, why }
 */
export function shouldUpdate(st, appVersion) {
  if (!st || st.state !== 'outdated') return { update: false, why: 'current' };
  if (st.installedVersion && st.version) {
    if (olderVersion(st.version, st.installedVersion)) return { update: false, why: 'newer_installed' };
    if (!olderVersion(st.installedVersion, st.version)) {
      return st.installedBy && olderVersion(st.installedBy, appVersion) ? { update: true, why: 'same_version_older_app' } : { update: false, why: 'same_version' };
    }
    return { update: true, why: 'older_installed' };
  }
  // No version to go by: the marker decides, as before.
  if (st.installedBy && !olderVersion(st.installedBy, appVersion)) return { update: false, why: 'same_or_newer_app' };
  return { update: true, why: 'no_version' };
}
