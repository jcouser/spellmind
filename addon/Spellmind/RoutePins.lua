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
			local s = not t.zone and RT.UpNext(1)[1] or nil
			if s and R.route and R.route.map then
				local k
				for n, st in ipairs(R.route.stops or {}) do if st == s then k = n end end
				pts.next = { world = RT.World(RT.StopMap(s), s.x, s.y), text = RT.StopText(s), num = k and tostring(k) or "",
					color = { 0.62, 0.49, 1 } }
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

local function HideAll()
	for _, b in pairs(pins) do b:Hide(); b.pt = nil end
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
