-- Spellmind: the look (a player on CurseForge, 2026-11-25: "a traditional WoW theme, standard WoW frames and
-- buttons"). Spellmind's own (dark purple, gold corners) or Classic WoW (the Game Menu's dialog frame, gold-brown
-- boxes, the standard red buttons): SpellmindDB.look = "classic", chosen on the Settings tab, taking effect at
-- the next /reload (frames are made once).
--
-- Each frame made with a backdrop says what it is right after it's made: Theme.Adopt(frame, role).
--   "window"  a window of its own: the dialog frame, whatever backdrop and colours the frame then asks for,
--             over a dark fill (the dialog's background shows the world through).
--   "box"     a row, a menu, an input, a band: its backdrop as it is, its purple turned to Blizzard's brown-gold
--             (a selected tab highlighted gold) and its dark purple to grey (T.Map); other colours kept.
--   "button"  the standard red button: no backdrop, the button textures, gold text.
-- With Spellmind's look, Adopt does nothing. The purple fill and gold corners (Window.lua's Fill and Corners)
-- draw nothing in the classic look.

local _, ns = ...
local T = {}
ns.Theme = T

T.LOOKS = { "spellmind", "classic" }
T.NAMES = { spellmind = "Spellmind", classic = "Classic WoW" }

function T.Look() return (ns.db and ns.db.look == "classic") and "classic" or "spellmind" end
function T.Classic() return T.Look() == "classic" end
function T.SetLook(v) if ns.db then ns.db.look = (v == "classic") and "classic" or nil end end

-- The dialog's border alone: under it, the rock background Blizzard's Options window has (the player, 2026-11-25:
-- "a similar background instead of black"), tiled; a dark fill where the client hasn't that texture.
T.DIALOG = { edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
	tile = true, tileSize = 32, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } }
T.ROCK = "Interface\\FrameGeneral\\UI-Background-Rock"
T.BUTTON = { up = "Interface\\Buttons\\UI-Panel-Button-Up", down = "Interface\\Buttons\\UI-Panel-Button-Down",
	hi = "Interface\\Buttons\\UI-Panel-Button-Highlight", off = "Interface\\Buttons\\UI-Panel-Button-Disabled" }

-- A colour in the classic look (the player, 2026-11-25, with Blizzard's Options window beside it: "still purple
-- scrolling"): Spellmind's purple turned to Blizzard's brown-gold at its brightness (borders, the selected tab,
-- rules, scrollbars), a dark purple to the grey of its lightness (backgrounds); any other colour (gold, the
-- green of On, the red of a warning) kept.
T.GOLD = { 0.78, 0.62, 0.3 }
function T.Map(r, g, b)
	r, g, b = tonumber(r) or 0, tonumber(g) or 0, tonumber(b) or 0
	if not (b > r and b > g) then return r, g, b end
	local l = 0.3 * r + 0.59 * g + 0.11 * b
	if b < 0.45 then return l, l, l end
	local k = math.min(1.3, l / 0.5)
	return math.min(1, T.GOLD[1] * k), math.min(1, T.GOLD[2] * k), math.min(1, T.GOLD[3] * k)
end
T.Grey = T.Map
-- A texture's colour (rules, scrollbars): mapped in the classic look, as it is otherwise.
function T.Color(r, g, b, a)
	if not T.Classic() then return r, g, b, a end
	local x, y, z = T.Map(r, g, b)
	return x, y, z, a
end
-- The accent in text: Spellmind's purple, or Blizzard's gold.
function T.Accent() return T.Classic() and "|cffffd100" or "|cffb48cff" end
-- A switch's word (On, or a choice's name): green in Spellmind's look; on a red button in the classic look,
-- Blizzard's gold, as the other buttons' words (the player, 2026-11-27: green On on red looked off). Off grey.
function T.OnText(on, word)
	word = word or (on and "On" or "Off")
	if not on then return "|cff888888" .. word .. "|r" end
	return (T.Classic() and "|cffffd100" or "|cff19ff19") .. word .. "|r"
end

local function Tex(b, set, get, path)
	if type(b[set]) ~= "function" then return end
	b[set](b, path, set == "SetHighlightTexture" and "ADD" or nil)
	local t = type(b[get]) == "function" and b[get](b)
	if t and t.SetTexCoord then t:SetTexCoord(0, 0.625, 0, 0.6875) end
end

-- A box's background in the classic look (the player, 2026-11-25: the rows were black over the rock): a dark one
-- warm brown and part see-through, so the rock shows and the row stands out; a lighter one (a selected tab, the
-- route's current step) mapped as any colour; none (alpha 0) left none.
T.BOX_BG = { 0.22, 0.18, 0.12 }
function T.BoxBG(r, g, b, a)
	a = tonumber(a) or 1
	if a <= 0 then return r, g, b, a end
	local x, y, z = T.Map(r, g, b)
	if 0.3 * x + 0.59 * y + 0.11 * z < 0.18 then return T.BOX_BG[1], T.BOX_BG[2], T.BOX_BG[3], math.min(a, 0.55) end
	return x, y, z, a
end

-- The red button as Blizzard draws it (the player, 2026-11-25: wide ones looked stretched): a left cap, a middle
-- that stretches, a right cap (UIPanelButtonTemplate's pieces), the pushed ones while the mouse is down.
T.SLICES = { { 0, 0.09375 }, { 0.09375, 0.53125 }, { 0.53125, 0.625 } }
function T.Slices(b)
	if not b.CreateTexture then return end
	local s = b.slices or {}
	b.slices = s
	for i = 1, 3 do
		s[i] = s[i] or b:CreateTexture(nil, "BACKGROUND")
		s[i]:SetTexture(T.BUTTON.up)
		s[i]:SetTexCoord(T.SLICES[i][1], T.SLICES[i][2], 0, 0.6875)
		s[i]:ClearAllPoints()
	end
	s[1]:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0); s[1]:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0); s[1]:SetWidth(12)
	s[3]:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0); s[3]:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0); s[3]:SetWidth(12)
	s[2]:SetPoint("TOPLEFT", s[1], "TOPRIGHT", 0, 0); s[2]:SetPoint("BOTTOMRIGHT", s[3], "BOTTOMLEFT", 0, 0)
	local function Look(path) for i = 1, 3 do s[i]:SetTexture(path) end end
	if b.HookScript then
		b:HookScript("OnMouseDown", function() Look(T.BUTTON.down) end)
		b:HookScript("OnMouseUp", function() Look(T.BUTTON.up) end)
		b:HookScript("OnHide", function() Look(T.BUTTON.up) end)
	end
end

function T.Adopt(f, role)
	if not f or not T.Classic() then return f end
	local setBD, setBG, setEdge = f.SetBackdrop, f.SetBackdropColor, f.SetBackdropBorderColor
	if role == "window" then
		if setBD then f.SetBackdrop = function(self, t) return setBD(self, t and T.DIALOG or t) end end
		if setBG then f.SetBackdropColor = function(self) return setBG(self, 1, 1, 1, 1) end end
		if setEdge then f.SetBackdropBorderColor = function(self) return setEdge(self, 1, 1, 1, 1) end end
		if f.CreateTexture then
			local fill = f:CreateTexture(nil, "BACKGROUND", nil, -8)
			if fill:SetTexture(T.ROCK, "REPEAT", "REPEAT") then
				if fill.SetHorizTile then fill:SetHorizTile(true) end
				if fill.SetVertTile then fill:SetVertTile(true) end
			else
				fill:SetColorTexture(0.06, 0.06, 0.07, 0.95)
			end
			fill:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -6)
			fill:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 6)
			f.classicFill = fill
		end
	elseif role == "box" then
		if setBG then f.SetBackdropColor = function(self, r, g, b, a) return setBG(self, T.BoxBG(r, g, b, a)) end end
		if setEdge then f.SetBackdropBorderColor = function(self, r, g, b, a) local x, y, z = T.Map(r, g, b); return setEdge(self, x, y, z, a) end end
	elseif role == "button" then
		f.SetBackdrop = function() end
		f.SetBackdropColor = function() end
		f.SetBackdropBorderColor = function() end
		T.Slices(f)
		Tex(f, "SetHighlightTexture", "GetHighlightTexture", T.BUTTON.hi)
		f.classicButton = true
	end
	return f
end
