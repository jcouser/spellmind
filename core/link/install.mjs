// Spellmind's installer: the addon, its 200 slot addons and its doorbells into a WoW: Forever
// AddOns folder, while the game is closed (the client reads TOCs and sees doorbell files only at its
// start). Parts adapted from NeverQuestAlone's bridge/byok/wow.mjs (MIT; see NOTICE.md): the flavor
// folders, the process check and the addon copy.
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { installSlots, SLOT_COUNT, countSlots } from './slots.mjs';
import { signalPaths, BELLS } from './signals.mjs';

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

// Copy the addon's own files; keep sig/ (live doorbells) and an Inbox.lua the service wrote.
function copyAddon(src, dst) {
  fs.mkdirSync(dst, { recursive: true });
  let files = 0;
  for (const e of fs.readdirSync(src, { withFileTypes: true })) {
    if (e.name === 'sig' || (e.name === 'Inbox.lua' && fs.existsSync(path.join(dst, 'Inbox.lua')))) continue;
    const from = path.join(src, e.name);
    const to = path.join(dst, e.name);
    if (e.isDirectory()) { fs.rmSync(to, { recursive: true, force: true }); files += copyAddon(from, to); } else if (e.isFile()) { fs.copyFileSync(from, to); files += 1; }
  }
  return files;
}

/**
 * Install into flavorDir (…/World of Warcraft/_forever_). Refuses while the game runs.
 * → { ok, addonsDir, files, slots, bells } | { ok: false, error, detail }
 */
export function installAddon({ flavorDir, source = ADDON_SOURCE, count = SLOT_COUNT, running = wowRunning, force = false } = {}) {
  if (!flavorDir || !looksLikeFlavor(flavorDir)) return { ok: false, error: 'not_a_wow_folder', detail: `${flavorDir} doesn't look like a WoW: Forever folder (the one with Interface and WTF in it, like _forever_).` };
  if (!fs.existsSync(path.join(source, `${ADDON_NAME}.toc`))) return { ok: false, error: 'no_addon', detail: `No addon at ${source}.` };
  if (!force && running().running) return { ok: false, error: 'wow_running', detail: RUNNING_LINE };
  const addonsDir = path.join(flavorDir, 'Interface', 'AddOns');
  const files = copyAddon(source, path.join(addonsDir, ADDON_NAME));
  const slots = installSlots(addonsDir, { count, iface: addonInterface(source) });
  const sig = signalPaths(addonsDir);
  const bells = [sig.present(), ...BELLS.map(sig.bell)].filter(f => fs.existsSync(f)).length;
  const have = countSlots(addonsDir);
  if (have < count) return { ok: false, error: 'slots_missing', detail: `Only ${have} of ${count} slot addons are in place.` };
  return { ok: true, addonsDir, files, slots, bells, note: RESTART_LINE };
}
