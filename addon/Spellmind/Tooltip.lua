-- Tooltip.lua: one quiet line at the bottom of an item's tooltip (docs/features.md §2, docs/milestone-5.md),
-- from local rules only (no AI, no cost):
--
--   Spellmind: no Bows skill yet: a weapon master may teach it    the game shows it in red
--   Spellmind: needs level 20                  (a requirement in red: level, skill, armor, class)
--   Spellmind: fills your empty Ranged slot
--   Spellmind: +0.9 dps, +2 Agi vs your Craftsman's Dagger
--
-- Through TooltipDataProcessor.AddTooltipPostCall (OnTooltipSetItem is gone on Forever, probe round 4),
-- on the game's own tooltip and the link tooltip only. The red check reads the game's own tooltip data
-- (its lines and colours), never what other addons added. Pawn's lines and scores stay Pawn's: this
-- is one fact, not a score. /sm marks off turns it off with the marks.

local _, ns = ...
local T = {}
ns.Tooltip = T

T.PREFIX = "|cff9d7dffSpellmind:|r "
T.NAME_MAX = 32
T.GAIN, T.LOSS = "|cff19ff19", "|cffff1919" -- GREEN_FONT_COLOR and RED_FONT_COLOR
-- Where an item is worn: its equip location's slots (the first is the one compared).
T.SLOTS = {
	INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 }, INVTYPE_CHEST = { 5 },
	INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 },
	INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
	INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 },
	INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 },
	INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 }, INVTYPE_TABARD = { 19 },
}
T.SLOT_NAMES = { "Head", "Neck", "Shoulder", "Shirt", "Chest", "Waist", "Legs", "Feet", "Wrist", "Hands", "Ring", "Ring",
	"Trinket", "Trinket", "Back", "Main Hand", "Off Hand", "Ranged", "Tabard" }
-- The stats a line names, in order, with their short names. Others still count toward nothing:
-- the line states differences, it doesn't weigh them.
T.STATS = { { "dps", "dps" }, { "str", "Str" }, { "agi", "Agi" }, { "sta", "Sta" }, { "int", "Int" }, { "spi", "Spi" },
	{ "ap", "AP" }, { "sp", "Spell Power" }, { "heal", "Healing" }, { "crit", "Crit" }, { "hit", "Hit" }, { "def", "Defense" },
	{ "armor", "Armor" } }
T.STATS_SHOWN = 3

local function Red(c)
	if type(c) ~= "table" then return false end
	local r, g, b
	if type(c.GetRGB) == "function" then r, g, b = c:GetRGB() else r, g, b = c.r, c.g, c.b end
	return type(r) == "number" and r > 0.9 and (g or 1) < 0.3 and (b or 1) < 0.3
end

-- The red texts of the game's own tooltip (requirements the character doesn't meet), past the name:
-- either side of a line (a rogue without Bows sees "Ranged" and "Bow" both in red).
function T.RedTexts(data)
	local out = {}
	for i, line in ipairs(type(data) == "table" and type(data.lines) == "table" and data.lines or {}) do
		if i > 1 and type(line) == "table" then
			for _, side in ipairs({ { line.leftColor, line.leftText }, { line.rightColor, line.rightText } }) do
				if Red(side[1]) and type(side[2]) == "string" then
					local text = ns.State.Text(side[2], 40)
					if text then out[#out + 1] = text end
				end
			end
		end
	end
	return out
end

-- What the red texts mean, in a few words. A weapon type the character lacks is a skill a weapon
-- master may teach: the game doesn't say which classes can learn which (and Forever differs from
-- classic: its rogues learn Axes), so it says "may". classID 2 is a weapon, 4 armor.
function T.Why(reds, classID, sub)
	local bits, other = {}, nil
	for _, t in ipairs(reds) do
		local lvl = t:match("[Rr]equires [Ll]evel (%d+)")
		if lvl then bits[#bits + 1] = "needs level " .. lvl elseif not other then other = t end
	end
	if other then
		if classID == 2 and type(sub) == "string" and sub ~= "" then
			bits[#bits + 1] = "no " .. sub .. " skill yet: a weapon master may teach it"
		elseif classID == 4 and type(sub) == "string" and sub ~= "" then
			bits[#bits + 1] = "can't wear " .. sub .. " yet"
		else
			bits[#bits + 1] = "can't use: " .. other
		end
	end
	return table.concat(bits, "; ")
end

local function Fmt(key, v)
	-- Rounded half away from zero: -2 stays -2 (floor(-2 - 0.5) made it -3).
	local whole = v >= 0 and math.floor(v + 0.5) or -math.floor(-v + 0.5)
	local n = key == "dps" and string.format("%.1f", v) or string.format("%d", whole)
	n = n:gsub("%.0$", "")
	return (v > 0 and "+" or "") .. n
end

-- The line for an item link (nil: nothing worth a line). data: the game's tooltip data, for the red check.
function T.Line(link, data)
	if type(link) ~= "string" then return nil end
	-- The equip location is GetItemInfo's ninth return (ns.Try keeps four, so pcall here).
	local r = C_Item and type(C_Item.GetItemInfo) == "function" and { pcall(C_Item.GetItemInfo, link) } or {}
	local equipLoc = r[1] and r[10] or nil
	local slots = type(equipLoc) == "string" and T.SLOTS[equipLoc]
	if not slots then return nil end
	local reds = T.RedTexts(data)
	if #reds > 0 then
		-- GetItemInfo's 7th return is the sub-type ("Bows"), its 12th the class id.
		local sub = ns.State.Text(r[8], 30)
		return T.PREFIX .. ns.Escape(T.Why(reds, tonumber(r[13]), sub))
	end
	local id = tonumber(link:match("item:(%d+)"))
	-- Worn already, in any of its slots: nothing to say.
	for _, s in ipairs(slots) do
		if id and ns.Try(GetInventoryItemID, "player", s) == id then return nil end
	end
	local slot = slots[1]
	-- A ring or trinket: the empty one of the pair, else the first. (A one-handed weapon is compared
	-- with the main hand: not every class can use the off hand.)
	if equipLoc == "INVTYPE_FINGER" or equipLoc == "INVTYPE_TRINKET" then
		for _, s in ipairs(slots) do
			if not ns.Try(GetInventoryItemID, "player", s) then slot = s; break end
		end
	end
	local wornId = ns.Try(GetInventoryItemID, "player", slot)
	if not wornId then return T.PREFIX .. "fills your empty " .. T.SLOT_NAMES[slot] .. " slot" end
	if wornId == id then return nil end
	local wornLink = ns.Try(GetInventoryItemLink, "player", slot)
	if not wornLink then return nil end
	local a, b = ns.State.ItemStats(link), ns.State.ItemStats(wornLink)
	local bits = {}
	for _, st in ipairs(T.STATS) do
		local d = (tonumber(a[st[1]]) or 0) - (tonumber(b[st[1]]) or 0)
		if math.abs(d) >= (st[1] == "dps" and 0.05 or 0.5) and #bits < T.STATS_SHOWN then
			-- Green for a gain, red for a loss: the game's own comparison colours.
			bits[#bits + 1] = (d > 0 and T.GAIN or T.LOSS) .. Fmt(st[1], d) .. " " .. st[2] .. "|r"
		end
	end
	local name = ns.State.Text(wornLink:match("|h%[(.-)%]|h"), T.NAME_MAX) or "item"
	if #bits == 0 then return T.PREFIX .. "about the same as your " .. ns.Escape(name) end
	return T.PREFIX .. table.concat(bits, ", ") .. " vs your " .. ns.Escape(name)
end

-- The focus part for an item linked in the chat box (milestone 6): what the AI needs to weigh it.
-- usable and why from the game's own red text; vs is the tooltip line's comparison, in words.
function T.Focus(link)
	if type(link) ~= "string" then return nil end
	local r = C_Item and type(C_Item.GetItemInfo) == "function" and { pcall(C_Item.GetItemInfo, link) } or {}
	if not r[1] or type(r[2]) ~= "string" then return nil end
	local S = ns.State
	local data = C_TooltipInfo and type(C_TooltipInfo.GetHyperlink) == "function" and select(2, pcall(C_TooltipInfo.GetHyperlink, link)) or nil
	local reds = T.RedTexts(type(data) == "table" and data or nil)
	local why = #reds > 0 and T.Why(reds, tonumber(r[13]), S.Text(r[8], 30)) or nil
	local equipLoc = type(r[10]) == "string" and r[10] or ""
	local wearable = T.SLOTS[equipLoc] ~= nil
	local vs
	if wearable and not why then
		local ok, line = pcall(T.Line, link, data)
		if ok and type(line) == "string" then
			vs = S.Text((line:gsub("^|cff9d7dffSpellmind:|r ", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")), 120)
		end
	end
	local O = S.JSON.O
	return O("v", 1, "kind", "item", "id", tonumber(link:match("item:(%d+)")), "name", S.Text(r[2]), "q", S.Whole(r[4]),
		"ilvl", S.Whole(r[5]), "req", S.Whole(r[6]), "type", S.Text(r[7], 30), "sub", S.Text(r[8], 30),
		"equip", wearable and S.Text(equipLoc:gsub("^INVTYPE_", ""):lower()) or nil, "st", wearable and S.ItemStatsO(link) or nil,
		"usable", why == nil, "why", why, "vs", vs)
end

function T.OnTooltip(tooltip, data)
	if not ns.db or not ns.Marks.On("tooltip") then return end
	if tooltip ~= rawget(_G, "GameTooltip") and tooltip ~= rawget(_G, "ItemRefTooltip") then return end
	local link
	if type(tooltip.GetItem) == "function" then
		local ok, _, l = pcall(tooltip.GetItem, tooltip)
		if ok then link = l end
	end
	local ok, line = pcall(T.Line, link, data)
	if ok and line then
		tooltip:AddLine(line, 1, 1, 1, true)
		T.last = line
	end
end

function T.Hook()
	if T.hooked then return end
	local TDP = rawget(_G, "TooltipDataProcessor")
	local kind = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item
	if type(TDP) ~= "table" or type(TDP.AddTooltipPostCall) ~= "function" or kind == nil then return end
	TDP.AddTooltipPostCall(kind, T.OnTooltip)
	T.hooked = true
end

ns.On("PLAYER_LOGIN", function() T.Hook() end)
