// Spellmind: adapted from NeverQuestAlone's tests/helpers/nqa-vm.js (MIT; see NOTICE.md).
// A fengari VM running the real Spellmind addon (addon/Spellmind, every file in its TOC order) on
// the WoW stub (tests/helpers/wow_stub.lua), plus:
//   - the Forever APIs the stub lacks (DEFAULT_CHAT_FRAME, GetCVar, frame scale, a
//     ScrollingMessageFrame's AddMessage), as build 70009 has them;
//   - a timer queue that honours delays: STUB.Advance(seconds) runs every C_Timer.After callback
//     and ticker that falls due, in time order;
//   - C_EncodingUtil on Node's zlib (raw deflate, as the client's Deflate method);
//   - traps for everything Spellmind must never call (SendChatMessage, RunScript, loadstring, ...).
// The addon's private table is passed in as NS, so tests can read its state; in the game nothing
// of it is global.
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');

const HERE = path.dirname(fileURLToPath(import.meta.url));
export const ROOT = path.join(HERE, '..', '..');
export const ADDON = path.join(ROOT, 'addon', 'Spellmind');
export const SIG = 'Interface\\AddOns\\Spellmind\\sig\\';
export const BELL_FILES = ['present', 'bell_push_a', 'bell_push_b', 'bell_alive_a', 'bell_alive_b'];

/** A Lua string literal holding exactly these UTF-8 bytes (control and high bytes as \ddd). */
export function lstr(s) {
  const bytes = Buffer.from(String(s), 'utf8');
  let out = '"';
  for (const b of bytes) {
    if (b === 0x22 || b === 0x5c) out += '\\' + String.fromCharCode(b);
    else if (b < 0x20 || b >= 0x7f) out += '\\' + String(b).padStart(3, '0');
    else out += String.fromCharCode(b);
  }
  return out + '"';
}

/** The .lua files the TOC lists, in its order. */
export function tocFiles() {
  const toc = fs.readFileSync(path.join(ADDON, 'Spellmind.toc'), 'utf8');
  return toc.split(/\r?\n/).map(l => l.trim()).filter(l => l && !l.startsWith('#') && l.endsWith('.lua'));
}

// Frame methods the stub lacks. Appended to its chunk, so they reach its local Methods table.
const STUB_METHODS = `
function Methods.SetScale(self, s) self.scale = s end
function Methods.GetScale(self) return self.scale or 1 end
function Methods.SetIgnoreParentScale(self, v) self.ignoreParentScale = v end
function Methods.SetIgnoreParentAlpha(self, v) self.ignoreParentAlpha = v end
function Methods.SetFrameStrata(self, s) self.strata = s end
function Methods.SetFrameLevel(self, l) self.level = l end
function Methods.SetMaxBytes(self, n) self.maxBytes = n end
function Methods.SetMovable(self, v) self.movable = v end
function Methods.AddMessage(self, text) self.messages = self.messages or {}; table.insert(self.messages, tostring(text)) end
`;

const EXTRA = `
STUB.chat, STUB.forbidden, STUB.loads = {}, {}, {}
STUB.cvars = { Sound_EnableAllSound = "1" }
STUB.physW, STUB.physH = 1920, 1080
function GetPhysicalScreenSize() return STUB.physW, STUB.physH end
DEFAULT_CHAT_FRAME = CreateFrame("Frame", "ChatFrame1")
function DEFAULT_CHAT_FRAME:AddMessage(text) table.insert(STUB.chat, tostring(text)) end
function GetCVar(name) return STUB.cvars[name] end
function GetBuildInfo() return "1.60.1", "70009", "Sep 1 2026", 16001 end

-- A timer queue that honours delays.
STUB.queue = {}
C_Timer.After = function(delay, fn) table.insert(STUB.queue, { at = STUB.now + (delay or 0), fn = fn }) end
C_Timer.NewTicker = function(delay, fn, iterations)
	local t = { at = STUB.now + delay, every = delay, fn = fn, left = iterations }
	t.Cancel = function() t.cancelled = true end
	table.insert(STUB.queue, t)
	return t
end
function STUB.Advance(sec)
	local target = STUB.now + (sec or 0)
	while true do
		local best
		for _, t in ipairs(STUB.queue) do
			if not t.cancelled and t.at <= target + 1e-9 and (not best or t.at < best.at) then best = t end
		end
		if not best then break end
		if best.at > STUB.now then STUB.now = best.at end
		if best.every then
			best.at = best.at + best.every
			if best.left then
				best.left = best.left - 1
				if best.left <= 0 then best.cancelled = true end
			end
			best.fn(best)
		else
			best.cancelled = true
			best.fn()
		end
	end
	STUB.now = target
	local keep = {}
	for _, t in ipairs(STUB.queue) do if not t.cancelled then keep[#keep + 1] = t end end
	STUB.queue = keep
end

-- Slot addons: every call is counted; STUB.slotReason makes loads fail.
C_AddOns.LoadAddOn = function(name)
	table.insert(STUB.loads, name)
	if STUB.slotReason then return false, STUB.slotReason end
	STUB.loaded[name] = true
	if STUB.onLoadAddOn then STUB.onLoadAddOn(name) end
	return true
end

-- SavedVariables as the client writes them: a Lua table literal.
function STUB.Serialize(v)
	local t = type(v)
	if t == "string" then return string.format("%q", v) end
	if t == "number" then
		if v == math.floor(v) and math.abs(v) < 2^53 then return string.format("%d", v) end
		return string.format("%.17g", v)
	end
	if t == "boolean" then return tostring(v) end
	if t == "table" then
		local parts = {}
		for k, x in pairs(v) do
			local xs = STUB.Serialize(x)
			if xs then parts[#parts + 1] = "[" .. STUB.Serialize(k) .. "] = " .. xs end
		end
		return "{ " .. table.concat(parts, ", ") .. " }"
	end
	return nil
end
`;

// C_EncodingUtil's deflate and base64 calls as build 70009 documents them
// (EncodingUtilDocumentation.lua at wow-ui-source bd2470a; NeverQuestAlone's nqa-vm.js), done by
// Node's zlib: CompressString(source[, method[, level]]) and DecompressString(source[, method])
// with Enum.CompressionMethod Deflate 0 (raw deflate, what core/link/records.mjs inflateBody
// reads first), Zlib 1, Gzip 2 and Enum.CompressionLevel Default 0, OptimizeForSpeed 1,
// OptimizeForSize 2; EncodeBase64/DecodeBase64(source[, variant]), Standard 0 or StandardUrlSafe 1.
// A bad argument raises; input that doesn't inflate returns nothing. Tests replace or remove them in Lua.
const DEFLATE = [zlib.deflateRawSync, zlib.deflateSync, zlib.gzipSync];
const INFLATE = [zlib.inflateRawSync, zlib.inflateSync, zlib.gunzipSync];
const LEVELS = [{}, { level: 1 }, { level: 9 }];
function installEncodingUtil(L) {
  const src = (L1, i) => Buffer.from(lauxlib.luaL_checklstring(L1, i));
  const opt = (L1, i, n) => {
    const v = lauxlib.luaL_optinteger(L1, i, 0);
    if (v < 0 || v >= n) lauxlib.luaL_argerror(L1, i, to_luastring('invalid enum value'));
    return v;
  };
  const push = (L1, buf) => { const u = Uint8Array.from(buf); lua.lua_pushlstring(L1, u, u.length); return 1; };
  const fns = {
    CompressString: L1 => push(L1, DEFLATE[opt(L1, 2, 3)](src(L1, 1), LEVELS[opt(L1, 3, 3)])),
    DecompressString: L1 => {
      const input = src(L1, 1);
      const inflate = INFLATE[opt(L1, 2, 3)];
      let out;
      try { out = inflate(input); } catch { return 0; }
      return push(L1, out);
    },
    EncodeBase64: L1 => {
      const b64 = src(L1, 1).toString('base64');
      return push(L1, Buffer.from(opt(L1, 2, 2) === 1 ? b64.replace(/\+/g, '-').replace(/\//g, '_') : b64));
    },
    DecodeBase64: L1 => { const input = src(L1, 1); opt(L1, 2, 2); return push(L1, Buffer.from(input.toString('latin1'), 'base64')); },
  };
  lua.lua_createtable(L, 0, 4);
  for (const [name, fn] of Object.entries(fns)) {
    lua.lua_pushjsfunction(L, fn);
    lua.lua_setfield(L, -2, to_luastring(name));
  }
  lua.lua_setglobal(L, to_luastring('C_EncodingUtil'));
}
const ENUMS = `
Enum = Enum or {}
Enum.CompressionMethod = { Deflate = 0, Zlib = 1, Gzip = 2 }
Enum.CompressionLevel = { Default = 0, OptimizeForSpeed = 1, OptimizeForSize = 2 }
Enum.Base64Variant = { Standard = 0, StandardUrlSafe = 1 }
`;

// Installed after the addon's files have loaded: anything that could reach another player or run
// code records itself and raises.
const TRAPS = `
local function Trap(name)
	return function()
		table.insert(STUB.forbidden, name)
		error("Spellmind must never call " .. name, 2)
	end
end
SendChatMessage = Trap("SendChatMessage")
C_ChatInfo = { SendAddonMessage = Trap("C_ChatInfo.SendAddonMessage"), SendChatMessage = Trap("C_ChatInfo.SendChatMessage") }
RunScript = Trap("RunScript")
RunMacroText = Trap("RunMacroText")
ReloadUI = Trap("ReloadUI")
loadstring = Trap("loadstring")
load = Trap("load")
dofile = Trap("dofile")
loadfile = Trap("loadfile")
`;

/**
 * A new UI session. opts: db (Lua that sets SpellmindDB, as SavedVariables would), now, seed,
 * signals (false: no doorbells on disk), sounds (a Lua table of extra sound files), inbox (what
 * Spellmind/Inbox.lua holds), before (Lua run after the addon's files, before login).
 */
export function newVM(opts = {}) {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  const check = (status, what) => {
    if (status !== lua.LUA_OK) {
      const msg = to_jsstring(lua.lua_tostring(L, -1));
      lua.lua_pop(L, 1);
      throw new Error(`${what}: ${msg}`);
    }
  };
  const run = (code, name = 'test') => {
    check(lauxlib.luaL_loadbuffer(L, to_luastring(code), null, to_luastring('=' + name)), 'Lua load');
    check(lua.lua_pcall(L, 0, 0, 0), 'Lua error');
  };
  // One addon file, the way the client loads it: (addonName, addonTable).
  const loadFile = (src, name) => {
    check(lauxlib.luaL_loadbuffer(L, to_luastring(src), null, to_luastring('@Spellmind/' + name)), 'Lua load ' + name);
    lua.lua_pushstring(L, to_luastring('Spellmind'));
    lua.lua_getglobal(L, to_luastring('NS'));
    check(lua.lua_pcall(L, 2, 0, 0), 'Lua error in ' + name);
  };
  const toJS = (idx, depth = 0) => {
    const t = lua.lua_type(L, idx);
    if (t === lua.LUA_TNIL) return null;
    if (t === lua.LUA_TBOOLEAN) return lua.lua_toboolean(L, idx);
    if (t === lua.LUA_TNUMBER) return lua.lua_tonumber(L, idx);
    if (t === lua.LUA_TSTRING) return to_jsstring(lua.lua_tostring(L, idx));
    if (t === lua.LUA_TTABLE) {
      if (depth > 30 || !lua.lua_checkstack(L, 4)) return '<deep>';
      const abs = lua.lua_absindex(L, idx);
      const entries = [];
      lua.lua_pushnil(L);
      while (lua.lua_next(L, abs) !== 0) {
        entries.push([toJS(-2, depth + 1), toJS(-1, depth + 1)]);
        lua.lua_pop(L, 1);
      }
      const isArray = entries.length > 0 && entries.every(([k]) => typeof k === 'number')
        && entries.map(([k]) => k).sort((a, b) => a - b).every((k, i) => k === i + 1);
      if (isArray) return entries.sort((a, b) => a[0] - b[0]).map(([, v]) => v);
      return Object.fromEntries(entries.map(([k, v]) => [String(k), v]));
    }
    return `<${to_jsstring(lua.lua_typename(L, t))}>`;
  };
  // A Lua string's exact bytes, as a Buffer (to_jsstring would decode them as UTF-8).
  const bytesOf = (expr) => {
    run(`RESULT = (${expr})`, 'bytes');
    lua.lua_getglobal(L, to_luastring('RESULT'));
    const u = lua.lua_tolstring(L, -1);
    lua.lua_pop(L, 1);
    return u ? Buffer.from(u) : null;
  };
  const evaluate = (expr) => {
    run(`local v = (${expr}); if v == nil then RESULT = nil else RESULT = tostring(v) end`, 'evaluate');
    lua.lua_getglobal(L, to_luastring('RESULT'));
    const s = lua.lua_isnil(L, -1) ? null : to_jsstring(lua.lua_tolstring(L, -1));
    lua.lua_pop(L, 1);
    return s;
  };
  const json = (expr) => {
    run(`RESULT = (${expr})`, 'json');
    lua.lua_getglobal(L, to_luastring('RESULT'));
    const v = toJS(-1);
    lua.lua_pop(L, 1);
    return v;
  };
  const num = (expr) => Number(evaluate(expr));
  const list = (expr) => { const v = json(expr); return Array.isArray(v) ? v : []; };

  run(fs.readFileSync(path.join(HERE, 'wow_stub.lua'), 'utf8') + STUB_METHODS, 'wow_stub');
  run(EXTRA, 'extra');
  installEncodingUtil(L);
  run(ENUMS, 'enums');
  run('math.randomseed(' + (opts.seed || 7) + ')');
  if (opts.now) run(`STUB.now = ${opts.now}`);
  // present.wav and the doorbells exist when the UI loads (setup makes them, PROTOCOL §3).
  if (opts.signals !== false) {
    for (const f of BELL_FILES) run(`STUB.sounds[${JSON.stringify(SIG + 'ctl\\' + f + '.wav')}] = true`);
  }
  if (opts.sounds) run(`for k, v in pairs(${opts.sounds}) do STUB.sounds[k] = v end`);
  if (opts.db) run(opts.db, 'saved variables');
  run('NS = {}');
  for (const f of tocFiles()) {
    let src = fs.readFileSync(path.join(ADDON, f), 'utf8');
    if (f === 'Inbox.lua' && opts.inbox) src = opts.inbox;
    loadFile(src, f);
  }
  run(TRAPS, 'traps');
  if (opts.before) run(opts.before, 'opts.before');

  const vm = {
    L, run, evaluate, json, num, list, bytesOf,
    bool: (expr) => evaluate(`(${expr}) and true or false`) === 'true',
    /**
     * ADDON_LOADED, PLAYER_LOGIN, then PLAYER_ENTERING_WORLD: a login (isInitialLogin) for a new
     * VM, a /reload (isReloadingUi) for one from reloadVM, unless initial says otherwise.
     */
    login({ initial = !opts.reloaded } = {}) {
      run('STUB.FireEvent("ADDON_LOADED", "Spellmind"); STUB.FireEvent("PLAYER_LOGIN")');
      run(`STUB.FireEvent("PLAYER_ENTERING_WORLD", ${initial}, ${!initial})`);
      return vm;
    },
    advance(sec) { run(`STUB.Advance(${sec})`); return vm; },
    /** A doorbell file (e.g. 'bell_push_a', 'present') on disk, or not. */
    bell(name, on = true) {
      run(`STUB.sounds[${JSON.stringify(SIG + 'ctl\\' + name + '.wav')}] = ${on ? 'true' : 'nil'}`);
      return vm;
    },
    /** Every following slot load runs this Lua (a slot file: it assigns SpellmindSlotData). */
    slotText(text) { run(`STUB.onLoadAddOn = function(name)\n${text}\nend`); return vm; },
    loads: () => list('STUB.loads'),
    slash: (text) => { run(`SlashCmdList.SPELLMIND(${lstr(text)})`); return vm; },
    chatLines: () => list('STUB.chat'),
    windowLines: () => list('SpellmindWindow and SpellmindWindow.log.messages or {}'),
    savedLines: () => list('SpellmindDB.lines'),
    saved: () => evaluate('STUB.Serialize(SpellmindDB)'),
    sounds: () => evaluate('STUB.Serialize(STUB.sounds)'),
    outbox: () => list('SpellmindDB.outbox').map(e => ({ key: e.key, wire: Buffer.from(e.hex, 'hex').toString('utf8') })),
    /**
     * The screen as the capture reads it: a black picture with the strip's shown cells painted at
     * their physical pixels ({ width, height, channels, data }, as core/link/strip.mjs takes), or
     * null when the strip is hidden. One strip unit is scale * physH / 768 physical pixels.
     */
    screen({ width = 1000, height = 700 } = {}) {
      if (!vm.bool('SpellmindStrip ~= nil and SpellmindStrip.shown')) return null;
      const s = json(`{ x = SpellmindStrip.x, y = SpellmindStrip.y, scale = SpellmindStrip.scale, physH = STUB.physH }`);
      const k = s.scale * s.physH / 768;
      run(`
        local parts = {}
        for _, t in ipairs(SpellmindStrip.textures) do
          if t.shown and t.color then
            local v = (t.color[1] >= 0.5 and 4 or 0) + (t.color[2] >= 0.5 and 2 or 0) + (t.color[3] >= 0.5 and 1 or 0)
            parts[#parts + 1] = string.format("%d:%d:%d:%d", t.x, -t.y, t.width or 0, v)
          end
        end
        RESULT = table.concat(parts, ",")`, 'screen');
      const data = new Uint8Array(width * height * 3);
      const cells = evaluate('RESULT');
      for (const p of cells ? cells.split(',') : []) {
        const [x, y, w, v] = p.split(':').map(Number);
        const px0 = Math.round((s.x + x) * k), py0 = Math.round((-s.y + y) * k), size = Math.round(w * k);
        for (let yy = py0; yy < py0 + size && yy < height; yy++) {
          for (let xx = px0; xx < px0 + size && xx < width; xx++) {
            const o = (yy * width + xx) * 3;
            data[o] = v & 4 ? 255 : 0; data[o + 1] = v & 2 ? 255 : 0; data[o + 2] = v & 1 ? 255 : 0;
          }
        }
      }
      return { width, height, channels: 3, data };
    },
  };
  return vm;
}

/** A /reload: SavedVariables and the doorbells carry over, the Lua is read again, every slot is free again. */
export function reloadVM(vm, opts = {}) {
  return newVM({ ...opts, reloaded: true, now: vm.num('STUB.now'), db: 'SpellmindDB = ' + vm.saved(), sounds: vm.sounds() });
}
