// A check of Ground.lua on real trails (dev only, not shipped): reads only SpellmindDB.routeTrails from a
// SavedVariables file, walks them into squares, and reports counts, the packed size and how long a way takes.
// Usage: node tools/ground-check.mjs <path to Spellmind.lua SavedVariables>
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import fengari from 'fengari';
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;

const here = path.dirname(fileURLToPath(import.meta.url));
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const run = (src, name) => {
  if (lauxlib.luaL_loadbuffer(L, to_luastring(src), null, to_luastring(name)) !== lua.LUA_OK || lua.lua_pcall(L, 0, 1, 0) !== lua.LUA_OK) {
    throw new Error(to_jsstring(lua.lua_tostring(L, -1)));
  }
  const out = lua.lua_isstring(L, -1) ? to_jsstring(lua.lua_tostring(L, -1)) : null;
  lua.lua_pop(L, 1);
  return out;
};
run(fs.readFileSync(process.argv[2], 'utf8'), 'saved');
// Only the trails are kept; everything else in the file is dropped before any of it is looked at.
run('local t = SpellmindDB and SpellmindDB.routeTrails; for k in pairs(_G) do if k == "SpellmindDB" then _G[k] = nil end end; TRAILS = t', 'keep');
run(`
  local ns = { R = {}, db = { routeTrails = TRAILS }, Route = { TRAIL_JUMP = 40, TRAIL_JOIN = 150, OFF_TRAIL = 1.25, STRAIGHT = 3, STRAIGHT_OPEN = 1.3, TRAIL_BACK = 30, TRAIL_EXPAND = 20000, SwimCost = function() return 1.48 end } }
  function ns.Try(fn, ...) if type(fn) ~= "function" then return nil end local ok, a = pcall(fn, ...) if ok then return a end end
  function ns.On() end
  NS = ns
  local chunk = assert(loadstring or load)(${JSON.stringify(fs.readFileSync(path.join(here, '../addon/Spellmind/Ground.lua'), 'utf8'))})
  chunk("Spellmind", ns)
`, 'ground');
console.log(run(`
  local G, out = NS.Ground, {}
  local pts = 0
  local conts = {}
  for c, t in pairs(TRAILS or {}) do pts = pts + #(t.x or {}); conts[#conts + 1] = c end
  local t0 = os.clock()
  for _, c in ipairs(conts) do G.Layer(c) end
  out[#out + 1] = "old points " .. pts .. ", squares " .. G.Count() .. ", walked in " .. string.format("%.2f", os.clock() - t0) .. " s"
  t0 = os.clock(); G.Save()
  local bytes = 0
  for _, ch in pairs(NS.db.routeGround.c) do for _, s in ipairs(ch) do bytes = bytes + #s end end
  out[#out + 1] = "packed " .. bytes .. " characters in " .. string.format("%.2f", os.clock() - t0) .. " s"
  -- Ways between walked squares far apart, as the arrow asks for them.
  for _, c in ipairs(conts) do
    local L = G.Layer(c)
    local keys = {}
    for k in pairs(L.cells) do keys[#keys + 1] = k end
    table.sort(keys)
    local found, tries, slow = 0, 0, 0
    t0 = os.clock()
    for i = 1, (#keys > 1 and 40 or 0) do
      local a, b = keys[(i * 7919) % #keys + 1], keys[(i * 104729 + 17) % #keys + 1]
      local ax, ay = G.Unkey(a); local bx, by = G.Unkey(b)
      local A, B = { c = c, x = (ax + 0.5) * 8, y = (ay + 0.5) * 8 }, { c = c, x = (bx + 0.5) * 8, y = (by + 0.5) * 8 }
      local d = math.sqrt((A.x - B.x) ^ 2 + (A.y - B.y) ^ 2)
      if d < 1500 then
        tries = tries + 1
        local s0 = os.clock()
        local w = G.Way(A, B)
        if os.clock() - s0 > slow then slow = os.clock() - s0 end
        if w then found = found + 1 end
      end
    end
    out[#out + 1] = "continent " .. c .. ": " .. L.n .. " squares; " .. tries .. " ways asked, " .. found .. " along the ground, slowest " .. string.format("%.3f", slow) .. " s"
  end
  return table.concat(out, "\\n")
`, 'check'));
