-- Spellmind: adapted from NeverQuestAlone's addon/NeverQuestAlone/MinimapPins.lua (MIT; see NOTICE.md).
-- RoutePins.lua: the route's current step on the minimap, and the step after it (the player,
-- 2026-11-19: "should they also be in the minimap?"; only those two: the minimap is small, and the
-- arrow already gives the direction).
--
-- From NeverQuestAlone: the minimap's geometry on Forever (its minimap is retail's:
-- C_Minimap.GetViewRadius() is the view radius in yards for the current zoom, indoors or out; the
-- rotateMinimap CVar turns it with the player unless C_Minimap.IsRotateMinimapIgnored(); addons that
-- reshape it say so through GetMinimapShape()), the offset from the player with the turn, the clamp
-- to the rim (round or square by quadrant) with an arrow beyond it, and the polling driver.
-- Spellmind's own: the points (the route's, in the game's world yards: x north, y west), the look
-- (the map's dots: the current step gold, the next purple, the way to another zone green).
--
-- The lines (the player, 2026-11-19: "thin versions of the map lines in the minimap"): Spellmind's own.
-- The world map's lines, thin: from the player to the current step along the trails they've walked
-- (gold), on to the step after (purple); the way to another zone in green. Cut at the minimap's rim
-- (its shapes are all convex: the part of a segment inside is one piece, found by halving). A switch.
--
-- Display only: plain frames parented to Minimap (not protected, so they update in combat too); no
-- Blizzard frame is hooked or changed. Checks run 20 times a second while the route is on, and the
-- pins move only when the player, the view or the points changed.

local _, ns = ...
local RP = {}
ns.RoutePins = RP

RP.TICK = 0.05 -- seconds between checks while nothing turns
RP.CUR, RP.NEXT = 18, 12 -- pin sizes
RP.ARROW = 14
local EDGE_INSET = RP.CUR / 2 + RP.ARROW + 1 -- the current step on the rim sits this far in, its arrow beyond
local DOT_TEX = "Interface\\AddOns\\Spellmind\\Media\\Dot"
local ARROW_ATLAS = "Navigation-Tracked-Arrow" -- Forever's tracked arrow, pointing up
local ARROW_FILE = "Interface\\Minimap\\MinimapArrow"
local sqrt, abs, sin, cos, max = math.sqrt, math.abs, math.sin, math.cos, math.max
local atan2 = math.atan2 or math.atan -- Lua 5.1 in game; 5.3 in the test VM
local function Try(...) return ns.Try(...) end

-- The quadrants that are round for each shape GetMinimapShape() may name:
-- { top-left, bottom-left, top-right, bottom-right }. Without it: round.
local SHAPES = {
	ROUND = { true, true, true, true },
	SQUARE = { false, false, false, false },
	["CORNER-TOPLEFT"] = { true, false, false, false },
	["CORNER-TOPRIGHT"] = { false, false, true, false },
	["CORNER-BOTTOMLEFT"] = { false, true, false, false },
	["CORNER-BOTTOMRIGHT"] = { false, false, false, true },
	["SIDE-LEFT"] = { true, true, false, false },
	["SIDE-RIGHT"] = { false, false, true, true },
	["SIDE-TOP"] = { true, false, true, false },
	["SIDE-BOTTOM"] = { false, true, false, true },
	["TRICORNER-TOPLEFT"] = { true, true, true, false },
	["TRICORNER-TOPRIGHT"] = { true, false, true, true },
	["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
	["TRICORNER-BOTTOMRIGHT"] = { false, true, true, true },
}

---------------------------------------------------------------------------
-- The points: worked out when the route changes (RP.Refresh, from the tracker's Draw)
---------------------------------------------------------------------------

-- RP.points = { cur = { world, num, color, text, sub }, next = … } or {}.
RP.points = {}
function RP.Refresh()
	local RT, R = ns.Route, ns.R
	local pts = {}
	if RT and RT.Shown() and RT.MinimapOn() then
		local t = RT.ArrowTarget()
		if t and t.world then
			local _, i = RT.Current()
			pts.cur = { world = t.world, text = t.text, sub = t.sub,
				num = t.zone and "\194\187" or (i and tostring(i) or ""),
				color = t.zone and { 0.3, 0.95, 0.4 } or { 1, 0.82, 0 }, dark = true }
			-- The step after (not while the arrow heads to another zone).
			local s = not t.zone and not t.away and RT.UpNext(1)[1] or nil
			if s and R.route and R.route.map then
				local k
				for n, st in ipairs(R.route.stops or {}) do if st == s then k = n end end
				local sx, sy = RT.StopPoint(s)
				pts.next = { world = RT.World(RT.StopMap(s), sx, sy), text = RT.StopText(s), num = k and tostring(k) or "",
					color = { 0.62, 0.49, 1 } }
			end
			-- The current step's area (the player, 2026-11-20): shown faintly while you're inside it.
			local st = t.step
			for _, g in ipairs(st and st.goals or {}) do
				if not pts.area and g.kind == "do" and g.ax and g.rx and g.ry and R.route and R.route.map then
					local mapW, mapH = RT.MapYards(RT.StopMap(st))
					local c = RT.World(RT.StopMap(st), g.ax, g.ay)
					if c and mapW then pts.area = { world = c, rx = g.rx / 100 * mapW, ry = g.ry / 100 * mapH, step = st } end
				end
			end
			-- The lines: { color, pts (world spots), fromMe (it starts at the player, live) }.
			if RT.MinimapLinesOn() then
				local lines = {}
				if (t.zone or t.away) and type(t.legs) == "table" and #t.legs > 0 then
					local way = {}
					for _, leg in ipairs(t.legs) do
						for _, p in ipairs(leg.path or {}) do way[#way + 1] = p end
						if leg.world then way[#way + 1] = leg.world end
					end
					lines[1] = { color = { 0.3, 0.95, 0.4 }, pts = way, fromMe = true }
				else
					local way = {}
					for _, p in ipairs(t.path or {}) do way[#way + 1] = p end
					way[#way + 1] = t.world
					lines[1] = { color = { 1, 0.82, 0 }, pts = way, fromMe = true, step = t.step }
					if pts.next and pts.next.world then lines[2] = { color = { 0.62, 0.49, 1 }, pts = { t.world, pts.next.world } } end
				end
				pts.lines = lines
			end
		end
	end
	RP.points = pts
	RP.dirty = true
end

---------------------------------------------------------------------------
-- Pins
---------------------------------------------------------------------------

local pins = {}
RP.pins = pins

local function ShowTip(self)
	if not GameTooltip or not self.pt then return end
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:SetText(self.pt.text or "")
	if self.pt.sub then GameTooltip:AddLine(self.pt.sub, 1, 1, 1, true) end
	if self.yards then GameTooltip:AddLine(string.format("%d yd away", self.yards), 0.6, 0.6, 0.6) end
	GameTooltip:Show()
end

local function Pin(k, size)
	local b = pins[k]
	if not b then
		b = CreateFrame("Frame", nil, Minimap)
		b.dot = b:CreateTexture(nil, "OVERLAY")
		b.dot:SetAllPoints()
		b.dot:SetTexture(DOT_TEX)
		b.num = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.num:SetPoint("CENTER")
		b.arrow = b:CreateTexture(nil, "OVERLAY")
		if b.arrow.SetAtlas and C_Texture and Try(C_Texture.GetAtlasExists, ARROW_ATLAS) then
			b.arrow:SetAtlas(ARROW_ATLAS)
			local info = Try(C_Texture.GetAtlasInfo, ARROW_ATLAS)
			local w, h = info and info.width or RP.ARROW, info and info.height or RP.ARROW
			local s = RP.ARROW / max(w, h, 1)
			b.arrow:SetSize(w * s, h * s)
		else
			b.arrow:SetTexture(ARROW_FILE)
			b.arrow:SetSize(RP.ARROW, RP.ARROW)
		end
		b.arrow:Hide()
		-- Hover says what it is; clicks go through to the minimap.
		b:EnableMouse(true)
		if b.SetMouseClickEnabled then b:SetMouseClickEnabled(false) end
		b:SetScript("OnEnter", ShowTip)
		b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
		pins[k] = b
	end
	b:SetSize(size, size)
	return b
end

local function Place(b, dx, dy)
	b:ClearAllPoints()
	b:SetPoint("CENTER", Minimap, "CENTER", dx, dy)
	b:Show()
end

local lines, holder = {}, nil
RP.lines = lines
RP.LINE_PX = 1.25 -- thin, in the screen's own pixels (the player, 2026-11-19: 1.5 UI units came out
-- about 3 pixels at their resolution and scale: "could it be any thinner?")
-- The thickness in the minimap's units for RP.LINE_PX screen pixels: the UI is 768 units tall at
-- scale 1, whatever the screen.
function RP.LineWidth()
	local h = select(2, Try(GetPhysicalScreenSize))
	local scale = tonumber((Try(Minimap.GetEffectiveScale, Minimap))) or 1
	local unit = (tonumber(h) and h > 0) and (768 / h) or 1
	return RP.LINE_PX * unit / (scale > 0 and scale or 1)
end
RP.LINE_A = 0.85
RP.LINES_MAX = 120
RP.linesShown = 0
RP.CLIP_SAMPLES = 24
local function HideLines(from)
	for k = from or 1, #lines do lines[k]:Hide() end
	if not from then RP.linesShown = 0 end
end
local function HideAll()
	for _, b in pairs(pins) do b:Hide(); b.pt = nil end
	HideLines()
	if RP.areaTex then RP.areaTex:Hide(); RP.areaShown = nil end
end
local function LineAt(k)
	if not holder then
		holder = CreateFrame("Frame", nil, Minimap)
		holder:SetAllPoints(Minimap)
	end
	holder:SetFrameLevel((tonumber((Minimap:GetFrameLevel())) or 1) + 4) -- under the pins
	local l = lines[k]
	if not l then l = holder:CreateLine(nil, "OVERLAY"); lines[k] = l end
	return l
end

-- Pixels from the minimap's centre to a world spot: east is right, north is up, and a turning
-- minimap turns everything by the player's facing.
local function Offset(p, me, scale, facing, sn, cs)
	local dx, dy = -(p.y - me.y) * scale, (p.x - me.x) * scale
	if facing then dx, dy = dx * cs + dy * sn, dy * cs - dx * sn end
	return dx, dy
end

-- (dx, dy) when a pin with this margin fits inside the minimap there; otherwise the spot on the rim
-- (inset by margin) toward it, and true.
local function Clamp(dx, dy, w, h, margin, shape)
	local rx, ry = w / 2 - margin, h / 2 - margin
	if rx <= 0 or ry <= 0 then return 0, 0, true end
	local nx, ny = dx / rx, dy / ry
	local q = (dx < 0 and 1 or 3) + (dy < 0 and 1 or 0)
	local d = shape[q] and sqrt(nx * nx + ny * ny) or max(abs(nx), abs(ny))
	if d <= 1 then return dx, dy, false end
	return dx / d, dy / d, true
end

-- The part of a segment inside the minimap (inset a pixel): its ends, or nil. Inside: one end, the
-- point nearest the middle, or one of a few along it; from there, the rim toward each outside end by
-- halving.
local function Inside(x, y, w, h, shape) local _, _, out = Clamp(x, y, w, h, 1, shape); return not out end
local function ClipSeg(ax, ay, bx, by, w, h, shape)
	local ina, inb = Inside(ax, ay, w, h, shape), Inside(bx, by, w, h, shape)
	if ina and inb then return ax, ay, bx, by end
	local vx, vy = bx - ax, by - ay
	local function At(t) return ax + vx * t, ay + vy * t end
	local tin = ina and 0 or (inb and 1) or nil
	if not tin then
		local len2 = vx * vx + vy * vy
		local tn = len2 > 0 and math.min(1, math.max(0, -(ax * vx + ay * vy) / len2)) or 0
		local x, y = At(tn)
		if Inside(x, y, w, h, shape) then tin = tn end
		for k = 1, RP.CLIP_SAMPLES - 1 do
			if tin then break end
			x, y = At(k / RP.CLIP_SAMPLES)
			if Inside(x, y, w, h, shape) then tin = k / RP.CLIP_SAMPLES end
		end
	end
	if not tin then return nil end
	local function Rim(tout)
		local lo, hi = tin, tout
		for _ = 1, 14 do
			local mid = (lo + hi) / 2
			local x, y = At(mid)
			if Inside(x, y, w, h, shape) then lo = mid else hi = mid end
		end
		return lo
	end
	local t0, t1 = ina and 0 or Rim(0), inb and 1 or Rim(1)
	if math.abs(t1 - t0) * math.sqrt(vx * vx + vy * vy) < 0.5 then return nil end
	local x0, y0 = At(t0)
	local x1, y1 = At(t1)
	return x0, y0, x1, y1
end

-- A line's points ahead of the player: from the nearest one on (those behind them are walked).
local function Ahead(me, list)
	local from, fd = 1, nil
	for k, p in ipairs(list) do
		if p.c == nil or p.c == me.c then
			local d = (p.x - me.x) ^ 2 + (p.y - me.y) ^ 2
			if not fd or d < fd then from, fd = k, d end
		end
	end
	-- The nearest is the target itself, or the player is past it toward the next: from the next one.
	local out = {}
	for k = from, #list do out[#out + 1] = list[k] end
	if #out > 1 then
		local a, b = out[1], out[2]
		local abx, aby = b.x - a.x, b.y - a.y
		if (me.x - a.x) * abx + (me.y - a.y) * aby > 0 then table.remove(out, 1) end
	end
	return out
end

RP.AREA_ALPHA = 0.16 -- faint: the minimap's own marks stay readable
local DOT_AREA_TEX = "Interface\\AddOns\\Spellmind\\Media\\Area"
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local SQUARE_MASK = "Interface\\Buttons\\WHITE8X8"
-- The current step's area while you're inside it: the world map's shading, faint, cut to the
-- minimap's shape (round, or square for a square minimap), turned with a turning minimap.
local function DrawArea(pts, me, scale, facing, sn, cs, shapeName)
	local a = pts.area
	local on = a and ns.Route.InArea(a.step)
	local t = RP.areaTex
	if not on then if t then t:Hide() end; RP.areaShown = nil; return end
	if not t then
		local holder = CreateFrame("Frame", nil, Minimap)
		holder:SetAllPoints(Minimap)
		holder:SetFrameLevel((tonumber((Minimap:GetFrameLevel())) or 1) + 3) -- under the lines and pins
		t = holder:CreateTexture(nil, "ARTWORK")
		t:SetTexture(DOT_AREA_TEX)
		local mask = type(holder.CreateMaskTexture) == "function" and holder:CreateMaskTexture() or nil
		if mask then
			mask:SetAllPoints(Minimap)
			if type(t.AddMaskTexture) == "function" then t:AddMaskTexture(mask) end
		end
		RP.areaTex, RP.areaMask = t, mask
	end
	if RP.areaMask and RP.areaMaskShape ~= shapeName then
		RP.areaMask:SetTexture(shapeName == "SQUARE" and SQUARE_MASK or ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		RP.areaMaskShape = shapeName
	end
	local dx, dy = Offset(a.world, me, scale, facing, sn, cs)
	t:ClearAllPoints()
	t:SetPoint("CENTER", Minimap, "CENTER", dx, dy)
	t:SetSize(2 * a.rx * scale, 2 * a.ry * scale)
	if t.SetRotation then t:SetRotation(facing and -facing or 0) end
	t:SetVertexColor(1, 0.82, 0, RP.AREA_ALPHA)
	t:Show()
	RP.areaShown = true
end

local function DrawLines(pts, me, scale, facing, sn, cs, w, h, shape)
	local n = 0
	local width = RP.LineWidth()
	for _, ln in ipairs(pts.lines or {}) do
		-- Not while you're inside the current step's area (the player, 2026-11-20).
		if ln.step and ns.Route.InArea(ln.step) then ln = { pts = {} } end
		local list = ln.fromMe and Ahead(me, ln.pts) or ln.pts
		local prev = ln.fromMe and { x = me.x, y = me.y, c = me.c } or nil
		for _, p in ipairs(list) do
			if n >= RP.LINES_MAX then break end
			if prev and (p.c == nil or p.c == me.c) and (prev.c == nil or prev.c == me.c) then
				local ax, ay = Offset(prev, me, scale, facing, sn, cs)
				local bx, by = Offset(p, me, scale, facing, sn, cs)
				local x0, y0, x1, y1 = ClipSeg(ax, ay, bx, by, w, h, shape)
				if x0 then
					n = n + 1
					local l = LineAt(n)
					l:SetThickness(width)
					l:SetColorTexture(ln.color[1], ln.color[2], ln.color[3], RP.LINE_A)
					l:SetStartPoint("CENTER", Minimap, x0, y0)
					l:SetEndPoint("CENTER", Minimap, x1, y1)
					l:Show()
				end
			end
			prev = p
		end
	end
	HideLines(n + 1)
	RP.linesShown = n
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local last = {}

function RP.Update(force)
	local pts = RP.points
	local radius = C_Minimap and Try(C_Minimap.GetViewRadius)
	local me = pts.cur and Minimap and Minimap:IsVisible() and type(radius) == "number" and radius > 0 and ns.Route.PlayerWorld() or nil
	local turn = me and Try(GetCVar, "rotateMinimap") == "1" and not (C_Minimap and Try(C_Minimap.IsRotateMinimapIgnored))
	local facing = turn and Try(GetPlayerFacing) or nil
	-- No position, another continent, or a turning minimap without the facing (an instance): none.
	if not me or pts.cur.world.c ~= me.c or (turn and not facing) then
		HideAll()
		last.x = nil
		return
	end
	local w, h = tonumber((Minimap:GetWidth())) or 140, tonumber((Minimap:GetHeight())) or 140
	local shapeName = type(GetMinimapShape) == "function" and Try(GetMinimapShape) or "ROUND"
	local pixel = radius / max(1, w / 2)
	if not force and not RP.dirty and last.x and abs(last.x - me.x) < pixel and abs(last.y - me.y) < pixel
		and last.radius == radius and last.facing == facing and last.w == w and last.shape == shapeName then
		return -- nothing moved
	end
	RP.dirty = false
	last.x, last.y, last.radius, last.facing, last.w, last.shape = me.x, me.y, radius, facing, w, shapeName
	local shape = SHAPES[shapeName] or SHAPES.ROUND
	local scale = (w / 2) / radius
	local sn, cs = 0, 1
	if facing then sn, cs = sin(facing), cos(facing) end
	DrawArea(pts, me, scale, facing, sn, cs, shapeName)
	DrawLines(pts, me, scale, facing, sn, cs, w, h, shape)
	-- The step after: only when it's in view.
	local b2 = Pin(2, RP.NEXT)
	b2:Hide()
	if pts.next and pts.next.world and pts.next.world.c == me.c then
		local dx, dy = Offset(pts.next.world, me, scale, facing, sn, cs)
		local _, _, out = Clamp(dx, dy, w, h, RP.NEXT / 2, shape)
		if not out then
			b2.pt = pts.next
			b2.dot:SetVertexColor(pts.next.color[1], pts.next.color[2], pts.next.color[3])
			b2.num:SetText(pts.next.num)
			b2.num:SetTextColor(1, 1, 1)
			if b2.num.SetTextScale then b2.num:SetTextScale(0.8) end
			b2.yards = math.floor(sqrt((pts.next.world.x - me.x) ^ 2 + (pts.next.world.y - me.y) ^ 2) + 0.5)
			b2:SetFrameLevel((tonumber((Minimap:GetFrameLevel())) or 1) + 5)
			b2.arrow:Hide()
			Place(b2, dx, dy)
		end
	end
	-- The current step: always shown, on the rim with its arrow when it's out of view.
	local b = Pin(1, RP.CUR)
	local c = pts.cur
	b.pt = c
	b.dot:SetVertexColor(c.color[1], c.color[2], c.color[3])
	b.num:SetText(c.num)
	b.num:SetTextColor(0.1, 0.05, 0)
	b.yards = math.floor(sqrt((c.world.x - me.x) ^ 2 + (c.world.y - me.y) ^ 2) + 0.5)
	b:SetFrameLevel((tonumber((Minimap:GetFrameLevel())) or 1) + 6)
	local dx, dy = Offset(c.world, me, scale, facing, sn, cs)
	local _, _, out = Clamp(dx, dy, w, h, RP.CUR / 2, shape)
	if out then
		local ex, ey = Clamp(dx, dy, w, h, EDGE_INSET, shape)
		local len = sqrt(dx * dx + dy * dy)
		local ux, uy = dx / len, dy / len
		local gap = RP.CUR / 2 + RP.ARROW / 2
		b.arrow:ClearAllPoints()
		b.arrow:SetPoint("CENTER", b, "CENTER", ux * gap, uy * gap)
		b.arrow:SetRotation(atan2(-ux, uy))
		b.arrow:Show()
		b.onEdge = true
		Place(b, ex, ey)
	else
		b.arrow:Hide()
		b.onEdge = nil
		Place(b, dx, dy)
	end
end

---------------------------------------------------------------------------
-- Driver: a check 20 times a second, and every frame while the minimap turns
---------------------------------------------------------------------------

local driver = CreateFrame("Frame")
RP.driver = driver
local acc, lastFacing = 0, nil
driver:SetScript("OnUpdate", function(_, elapsed)
	if not RP.points.cur then return end
	acc = acc + (tonumber(elapsed) or 0)
	local f = Try(GetCVar, "rotateMinimap") == "1" and Try(GetPlayerFacing) or nil
	if acc >= RP.TICK or f ~= lastFacing then
		acc, lastFacing = 0, f
		pcall(RP.Update, false)
	end
end)
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "MINIMAP_UPDATE_ZOOM", "CVAR_UPDATE" }) do
	pcall(driver.RegisterEvent, driver, e)
end
driver:SetScript("OnEvent", function() RP.dirty = true end)
