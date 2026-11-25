-- Spellmind: the look (a player on CurseForge, 2026-11-25: "a traditional WoW theme, standard WoW frames and
-- buttons"). Spellmind's own (dark purple, gold corners) or Classic WoW (the Game Menu's dialog frame, grey
-- boxes, the standard red buttons): SpellmindDB.look = "classic", chosen on the Settings tab, taking effect at
-- the next /reload (frames are made once).
--
-- Each frame made with a backdrop says what it is right after it's made: Theme.Adopt(frame, role).
--   "window"  a window of its own: the dialog frame, whatever backdrop and colours the frame then asks for,
--             over a dark fill (the dialog's background shows the world through).
--   "box"     a row, a menu, an input, a band: its backdrop as it is, every colour it asks for turned to the
--             grey of the same lightness (so a selected tab still stands out); gold stays gold.
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

T.DIALOG = { bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
	tile = true, tileSize = 32, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } }
T.BUTTON = { up = "Interface\\Buttons\\UI-Panel-Button-Up", down = "Interface\\Buttons\\UI-Panel-Button-Down",
	hi = "Interface\\Buttons\\UI-Panel-Button-Highlight", off = "Interface\\Buttons\\UI-Panel-Button-Disabled" }

-- A colour as the grey of its lightness; gold (the hover border, the app box) kept.
function T.Grey(r, g, b)
	r, g, b = tonumber(r) or 0, tonumber(g) or 0, tonumber(b) or 0
	if r > 0.7 and g > 0.45 and b < 0.45 then return r, g, b end
	local l = 0.3 * r + 0.59 * g + 0.11 * b
	return l, l, l
end

local function Tex(b, set, get, path)
	if type(b[set]) ~= "function" then return end
	b[set](b, path, set == "SetHighlightTexture" and "ADD" or nil)
	local t = type(b[get]) == "function" and b[get](b)
	if t and t.SetTexCoord then t:SetTexCoord(0, 0.625, 0, 0.6875) end
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
			fill:SetColorTexture(0, 0, 0, 0.75)
			fill:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -6)
			fill:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 6)
			f.classicFill = fill
		end
	elseif role == "box" then
		if setBG then f.SetBackdropColor = function(self, r, g, b, a) local x, y, z = T.Grey(r, g, b); return setBG(self, x, y, z, a) end end
		if setEdge then f.SetBackdropBorderColor = function(self, r, g, b, a) local x, y, z = T.Grey(r, g, b); return setEdge(self, x, y, z, a) end end
	elseif role == "button" then
		f.SetBackdrop = function() end
		f.SetBackdropColor = function() end
		f.SetBackdropBorderColor = function() end
		Tex(f, "SetNormalTexture", "GetNormalTexture", T.BUTTON.up)
		Tex(f, "SetPushedTexture", "GetPushedTexture", T.BUTTON.down)
		Tex(f, "SetHighlightTexture", "GetHighlightTexture", T.BUTTON.hi)
		Tex(f, "SetDisabledTexture", "GetDisabledTexture", T.BUTTON.off)
		f.classicButton = true
	end
	return f
end
