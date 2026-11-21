-- Spellmind: ground walked (the player, 2026-11-21: "the most optimal way to support sharing of foot traffic
-- data ... for the best pathing possible"). The trails as squares of the world walked through and the
-- crossings made between them, one way or the other, instead of lines of points: walks laid over each other
-- fill in a field rather than tangling, a wall stays a gap no one crossed, and the same shape can later be
-- merged from many players. On this PC for now. Ideas from studying AzerothGPS (none of its code or data).
--
-- SpellmindDB.routeGround = { v = 1, c = { [continent] = { chunks } } }: each square 8 characters (its column,
-- its row, its value), packed when the game saves (one string a chunk, not a value a square: a saved file holds
-- about 262,000 values in all). In play: a table per continent, unpacked on first use.
-- A square's value: the crossings out of it (bits 0-7, one per direction), swum (bit 8), walked (times, 0-7,
-- from bit 9).

local _, ns = ...
local G = {}
ns.Ground = G

local function Try(fn, ...) return ns.Try(fn, ...) end
local function RT() return ns.Route end

G.CELL = 8 -- yards a square
G.MAX = 150000 -- squares kept, at most
G.LANE = 6 -- a walked square this near (to its middle) is the same road: crossed both ways
G.PASSES = 7 -- times walked, counted up to
G.REVERSE = 1.1 -- a crossing walked only the other way: taken, a little dearer (one walk isn't a one-way ledge)
G.ROAD = 0.02 -- each time walked (up to 5) makes a square this much cheaper: roads are preferred
G.CHUNK = 4096 -- squares a saved string
G.ENDS = 6 -- the walked squares tried at each end of a way
G.PULL = 40 -- squares looked ahead when straightening a way

local OFF = 32768
local function Key(ix, iy) return (ix + OFF) * 65536 + (iy + OFF) end
local function Unkey(k)
	local a = math.floor(k / 65536)
	return a - OFF, k - a * 65536 - OFF
end
G.Key, G.Unkey = Key, Unkey

-- The eight directions, east first, then round; DIRK[dx * 3 + dy] = 0-7.
local DIRS = { { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 }, { -1, 0 }, { -1, -1 }, { 0, -1 }, { 1, -1 } }
local DIRK = {}
for i, d in ipairs(DIRS) do DIRK[d[1] * 3 + d[2]] = i - 1 end
local POW = {}
for n = 0, 12 do POW[n] = 2 ^ n end
local function Bit(v, n) return math.floor(v / POW[n]) % 2 == 1 end
local function Wet(v) return Bit(v, 8) end
local function Passes(v) return math.floor(v / 512) end
G.Bit, G.Passes = Bit, Passes

---------------------------------------------------------------------------
-- Kept: packed when the game saves, unpacked on first use
---------------------------------------------------------------------------

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local CH, DEC = {}, {}
for i = 1, 64 do CH[i - 1] = B64:sub(i, i); DEC[B64:byte(i)] = i - 1 end
local function Enc(n, len)
	local t = {}
	for i = len, 1, -1 do local d = n % 64; t[i] = CH[d]; n = (n - d) / 64 end
	return table.concat(t)
end

local layers, total = {}, nil

local function Saved()
	ns.db.routeGround = type(ns.db.routeGround) == "table" and ns.db.routeGround or { v = 1 }
	local s = ns.db.routeGround
	s.c = type(s.c) == "table" and s.c or {}
	return s
end

local function Unpack(L, s)
	if type(s) ~= "string" then return end
	for i = 1, #s - 7, 8 do
		local a1, a2, a3, b1, b2, b3, v1, v2 = s:byte(i, i + 7)
		a1, a2, a3, b1, b2, b3, v1, v2 = DEC[a1], DEC[a2], DEC[a3], DEC[b1], DEC[b2], DEC[b3], DEC[v1], DEC[v2]
		if a1 and a2 and a3 and b1 and b2 and b3 and v1 and v2 then
			local k = ((a1 * 64 + a2) * 64 + a3) * 65536 + ((b1 * 64 + b2) * 64 + b3)
			if not L.cells[k] then L.n = L.n + 1 end
			L.cells[k] = v1 * 64 + v2
		end
	end
end

-- The steps from one square to another, each to a neighbour (diagonal first): { { from, to, dir } }.
local function Steps(ax, ay, bx, by)
	local out = {}
	while ax ~= bx or ay ~= by do
		local dx = bx > ax and 1 or (bx < ax and -1 or 0)
		local dy = by > ay and 1 or (by < ay and -1 or 0)
		out[#out + 1] = { Key(ax, ay), Key(ax + dx, ay + dy), DIRK[dx * 3 + dy] }
		ax, ay = ax + dx, ay + dy
	end
	return out
end

local function Touch(L, k, wet, enter)
	local v = L.cells[k]
	if not v then
		total = total or G.Count()
		if total >= G.MAX then return nil end
		v = 0
		L.n, total = L.n + 1, total + 1
	end
	if wet and not Wet(v) then v = v + 256 end
	if enter and Passes(v) < G.PASSES then v = v + 512 end
	L.cells[k] = v
	L.dirty = true
	return v
end
local function Cross(L, a, b, dir)
	local v = L.cells[a]
	if v and L.cells[b] and not Bit(v, dir) then L.cells[a] = v + POW[dir]; L.dirty = true end
end

-- The trails of before (points and the lines between them), walked again into squares, both ways.
local function Migrate(L, old)
	local X, Y, E, W = old.x, old.y, old.e, type(old.w) == "table" and old.w or {}
	if type(X) ~= "table" or type(Y) ~= "table" or type(E) ~= "table" then return end
	local function Cell(i) return math.floor(X[i] / G.CELL), math.floor(Y[i] / G.CELL) end
	for k = 1, #E, 2 do
		local a, b = E[k], E[k + 1]
		if tonumber(X[a]) and tonumber(Y[a]) and tonumber(X[b]) and tonumber(Y[b]) then
			local ax, ay = Cell(a)
			local bx, by = Cell(b)
			local wet = W[a] or W[b]
			Touch(L, Key(ax, ay), wet, false)
			for _, s in ipairs(Steps(ax, ay, bx, by)) do
				if Touch(L, s[2], wet, false) then Cross(L, s[1], s[2], s[3]); Cross(L, s[2], s[1], (s[3] + 4) % 8) end
			end
		end
	end
	L.dirty = true
end

function G.Layer(c)
	local L = layers[c]
	if not L then
		L = { cells = {}, n = 0 }
		layers[c] = L
		local packed = ns.db and Saved().c[c]
		if type(packed) == "table" then for _, chunk in ipairs(packed) do pcall(Unpack, L, chunk) end end
		total = nil -- counted again when next needed
	end
	-- The trails kept before squares (0.6.4 and earlier), once.
	local old = ns.db and type(ns.db.routeTrails) == "table" and ns.db.routeTrails[c]
	if type(old) == "table" then
		ns.db.routeTrails[c] = nil
		pcall(Migrate, L, old)
		total = nil
	end
	return L
end

-- Every square walked, on every continent (those not yet unpacked counted from their strings).
function G.Count()
	if not ns.db then return 0 end
	local n = 0
	for c, chunks in pairs(Saved().c) do
		if not layers[c] and type(chunks) == "table" then
			for _, s in ipairs(chunks) do if type(s) == "string" then n = n + math.floor(#s / 8) end end
		end
	end
	for _, L in pairs(layers) do n = n + L.n end
	-- Trails of before not yet walked into squares: about a square a point.
	for _, old in pairs(type(ns.db.routeTrails) == "table" and ns.db.routeTrails or {}) do
		if type(old) == "table" and type(old.x) == "table" then n = n + #old.x end
	end
	return n
end

function G.Save()
	if not ns.db then return end
	local s = Saved()
	for c, L in pairs(layers) do
		if L.dirty then
			local chunks, buf = {}, {}
			for k, v in pairs(L.cells) do
				local X = math.floor(k / 65536)
				buf[#buf + 1] = Enc(X, 3) .. Enc(k - X * 65536, 3) .. Enc(v, 2)
				if #buf >= G.CHUNK then chunks[#chunks + 1] = table.concat(buf); buf = {} end
			end
			if #buf > 0 then chunks[#chunks + 1] = table.concat(buf) end
			s.c[c] = #chunks > 0 and chunks or nil
			L.dirty = nil
		end
	end
end
ns.On("PLAYER_LOGOUT", function() pcall(G.Save) end)

function G.Forget()
	if ns.db then ns.db.routeGround = { v = 1, c = {} }; ns.db.routeTrails = nil end
	layers, total = {}, 0
	ns.R.routeTrailAt = nil
end

---------------------------------------------------------------------------
-- Walking: the squares entered, the crossings made
---------------------------------------------------------------------------

-- Walked squares beside this spot, near enough to be the same road: crossed both ways.
local function Lanes(L, ix, iy, w)
	local here = Key(ix, iy)
	if not L.cells[here] then return end
	for d, dir in ipairs(DIRS) do
		local nx, ny = ix + dir[1], iy + dir[2]
		local n = Key(nx, ny)
		if L.cells[n] then
			local cx, cy = (nx + 0.5) * G.CELL, (ny + 0.5) * G.CELL
			if (cx - w.x) ^ 2 + (cy - w.y) ^ 2 <= G.LANE * G.LANE then
				Cross(L, here, n, d - 1); Cross(L, n, here, (d + 3) % 8)
			end
		end
	end
end

-- One tick: w a world spot ({ c, x, y }), or nil (not walking: a flight, the switch off).
-- The last spot is ns.R.routeTrailAt = { c, ix, iy, x, y }.
function G.Note(w, wet)
	if not w or not ns.db then ns.R.routeTrailAt = nil; return end
	local L = G.Layer(w.c)
	local ix, iy = math.floor(w.x / G.CELL), math.floor(w.y / G.CELL)
	local last = ns.R.routeTrailAt
	local jump = (RT() and RT().TRAIL_JUMP) or 40
	if not last or last.c ~= w.c or last.ix == nil or (w.x - last.x) ^ 2 + (w.y - last.y) ^ 2 > jump * jump then
		-- A start, or a jump (a loading screen, a portal): no crossing to here.
		Touch(L, Key(ix, iy), wet, true)
	elseif last.ix ~= ix or last.iy ~= iy then
		for _, s in ipairs(Steps(last.ix, last.iy, ix, iy)) do
			if Touch(L, s[2], wet, true) then Cross(L, s[1], s[2], s[3]) end
		end
	end
	Lanes(L, ix, iy, w)
	ns.R.routeTrailAt = { c = w.c, ix = ix, iy = iy, x = w.x, y = w.y }
end

---------------------------------------------------------------------------
-- The way over the ground walked
---------------------------------------------------------------------------

local function Push(h, v, f) h[#h + 1] = { v, f }; local i = #h; while i > 1 do local p = math.floor(i / 2); if h[p][2] <= h[i][2] then break end; h[p], h[i] = h[i], h[p]; i = p end end
local function Pop(h)
	local top = h[1]
	if not top then return nil end
	h[1] = h[#h]; h[#h] = nil
	local i = 1
	while true do
		local l, r, m = 2 * i, 2 * i + 1, i
		if h[l] and h[l][2] < h[m][2] then m = l end
		if h[r] and h[r][2] < h[m][2] then m = r end
		if m == i then break end
		h[m], h[i] = h[i], h[m]; i = m
	end
	return top[1], top[2]
end

local function Center(k)
	local ix, iy = Unkey(k)
	return (ix + 0.5) * G.CELL, (iy + 0.5) * G.CELL
end

-- The walked squares within r yards of a spot, nearest first, at most max: { { key, yards } }.
local function Near(L, x, y, r, max)
	local out = {}
	local cx, cy = math.floor(x / G.CELL), math.floor(y / G.CELL)
	local reach = math.ceil(r / G.CELL)
	for i = cx - reach, cx + reach do
		for j = cy - reach, cy + reach do
			local k = Key(i, j)
			if L.cells[k] then
				local px, py = (i + 0.5) * G.CELL, (j + 0.5) * G.CELL
				local d = math.sqrt((px - x) ^ 2 + (py - y) ^ 2)
				if d <= r then out[#out + 1] = { k, d } end
			end
		end
	end
	table.sort(out, function(a, b) return a[2] < b[2] end)
	while max and #out > max do table.remove(out) end
	return out
end

-- Crossed between two neighbouring squares, either way (dir: from a to b).
local function Linked(L, a, b, dir)
	local va, vb = L.cells[a], L.cells[b]
	if not va or not vb then return nil end
	if Bit(va, dir) then return 1 end
	if Bit(vb, (dir + 4) % 8) then return G.REVERSE end
	return nil
end

-- A straight line of squares from one to another, every step a crossing walked (a field walked over in
-- many ways is crossed straight; a wall no one crossed isn't).
local function Clear(L, a, b)
	local x0, y0 = Unkey(a)
	local x1, y1 = Unkey(b)
	local dx, dy = math.abs(x1 - x0), math.abs(y1 - y0)
	local sx, sy = x0 < x1 and 1 or -1, y0 < y1 and 1 or -1
	local err = dx - dy
	local px, py = x0, y0
	while px ~= x1 or py ~= y1 do
		local e2 = 2 * err
		local mx, my = 0, 0
		if e2 > -dy then err = err - dy; mx = sx end
		if e2 < dx then err = err + dx; my = sy end
		local from, to = Key(px, py), Key(px + mx, py + my)
		if not Linked(L, from, to, DIRK[mx * 3 + my]) then
			-- A diagonal step: crossed by either corner (rows and columns walked make a field too).
			if mx == 0 or my == 0 then return false end
			local h, v = Key(px + mx, py), Key(px, py + my)
			local byH = Linked(L, from, h, DIRK[mx * 3]) and Linked(L, h, to, DIRK[my])
			local byV = Linked(L, from, v, DIRK[my]) and Linked(L, v, to, DIRK[mx * 3])
			if not (byH or byV) then return false end
		end
		px, py = px + mx, py + my
	end
	return true
end

-- Fewer points to draw: those that bend the way (within tol yards of the line otherwise).
local function Simplify(list, tol)
	if #list < 3 then return list end
	local keep, out = { [1] = true, [#list] = true }, {}
	local function Seg(i, j)
		local ax, ay, bx, by = list[i].x, list[i].y, list[j].x, list[j].y
		local dx, dy = bx - ax, by - ay
		local len = math.sqrt(dx * dx + dy * dy)
		local far, at = 0, nil
		for k = i + 1, j - 1 do
			local d = len > 0 and math.abs((list[k].x - ax) * dy - (list[k].y - ay) * dx) / len or math.sqrt((list[k].x - ax) ^ 2 + (list[k].y - ay) ^ 2)
			if d > far then far, at = d, k end
		end
		if at and far > tol then keep[at] = true; Seg(i, at); Seg(at, j) end
	end
	Seg(1, #list)
	for k, p in ipairs(list) do if keep[k] then out[#out + 1] = p end end
	return out
end

-- The way from one world spot to another over the ground walked: its points (world spots), when the
-- ground makes it cheaper than the straight line by the route's rules, else nil.
function G.Way(a, b)
	local R = RT()
	if not a or not b or a.c ~= b.c or not ns.db then return nil end
	local L = G.Layer(a.c)
	if L.n == 0 then return nil end
	local starts = Near(L, a.x, a.y, R.TRAIL_JOIN, G.ENDS)
	local ends = Near(L, b.x, b.y, R.TRAIL_JOIN, G.ENDS)
	if #starts == 0 or #ends == 0 then return nil end
	local goal = {}
	for _, e in ipairs(ends) do goal[e[1]] = e[2] * R.OFF_TRAIL end
	local least = 1 - 5 * G.ROAD
	local function H(k) local x, y = Center(k); return math.sqrt((x - b.x) ^ 2 + (y - b.y) ^ 2) * least end
	local g, prev, done, heap = {}, {}, {}, {}
	for _, s in ipairs(starts) do g[s[1]] = s[2] * R.OFF_TRAIL; Push(heap, s[1], g[s[1]] + H(s[1])) end
	local swim = R.SwimCost()
	local best, bestCost
	local steps = 0
	while true do
		local u = Pop(heap)
		if not u then break end
		if not done[u] then
			done[u] = true
			steps = steps + 1
			if steps > R.TRAIL_EXPAND then break end
			if goal[u] then
				local t = g[u] + goal[u]
				if not bestCost or t < bestCost then best, bestCost = u, t end
			end
			if bestCost and g[u] + H(u) >= bestCost then break end
			local ux, uy = Unkey(u)
			local uv = L.cells[u]
			for d, dir in ipairs(DIRS) do
				local n = Key(ux + dir[1], uy + dir[2])
				local f = Linked(L, u, n, d - 1)
				if f then
					local nv = L.cells[n]
					local len = G.CELL * ((dir[1] ~= 0 and dir[2] ~= 0) and 1.41421 or 1)
					f = f * ((Wet(uv) or Wet(nv)) and swim or 1) * (1 - G.ROAD * math.min(Passes(nv), 5))
					local c = g[u] + len * f
					if not g[n] or c < g[n] then g[n], prev[n] = c, u; Push(heap, n, c + H(n)) end
				end
			end
		end
	end
	if not best then return nil end
	local straight = math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
	-- In a city its walls are why the ground walked is taken at all; out in the open only when it's about
	-- as direct (the player, 2026-11-20: "just the path I had walked from a different point a to b").
	local city = Try(rawget(_G, "IsResting")) and true or false
	if bestCost >= straight * (city and R.STRAIGHT or R.STRAIGHT_OPEN) then return nil end
	local cells, n = {}, best
	while n do table.insert(cells, 1, n); n = prev[n] end
	-- Not back the way you came, out in the open.
	if not city then
		for _, k in ipairs(cells) do
			local x, y = Center(k)
			if math.sqrt((x - b.x) ^ 2 + (y - b.y) ^ 2) > straight + R.TRAIL_BACK then return nil end
		end
	end
	-- Straightened through the ground walked, then only the bends kept.
	local pulled, i = { cells[1] }, 1
	while i < #cells do
		local j = math.min(#cells, i + G.PULL)
		while j > i + 1 and not Clear(L, cells[i], cells[j]) do j = j - 1 end
		pulled[#pulled + 1] = cells[j]
		i = j
	end
	local pts = {}
	for _, k in ipairs(pulled) do local x, y = Center(k); pts[#pts + 1] = { c = a.c, x = x, y = y } end
	return Simplify(pts, 3)
end
