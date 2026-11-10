-- Spellmind: adapted from NeverQuestAlone's tests/wow_stub.lua (MIT; see NOTICE.md).
-- A minimal stand-in for the WoW addon environment, enough to load and drive
-- the addon outside the game (tests/helpers/addon-vm.mjs). Frames are plain tables:
-- capitalized names that aren't listed below resolve to a no-op method, so any
-- SetFoo/EnableBar call is accepted; lowercase names are ordinary fields.
--
-- STUB collects what the addon did: frames, texts, timers, tickers, prints.

STUB = {
	frames = {}, texts = {}, timers = {}, tickers = {}, prints = {}, bindings = {},
	now = 1000, epoch = 1700000000, sounds = {}, loaded = {}, reloaded = false,
	tooltips = {}, combat = false,
}

local function noop() end

local Methods = {}
local FrameMT = {
	__index = function(t, k)
		if type(k) == "string" and k:match("^%u") then
			return Methods[k] or noop
		end
	end,
}

local function NewObject(kind, name, parent)
	local o = setmetatable({ kind = kind, name = name, parent = parent, scripts = {}, hooks = {}, events = {}, shown = true, textures = {}, children = {} }, FrameMT)
	if name then _G[name] = o end
	if parent and type(parent) == "table" and parent.children then table.insert(parent.children, o) end
	return o
end

function Methods.SetScript(self, name, fn) self.scripts[name] = fn end
function Methods.GetScript(self, name) return self.scripts[name] end
function Methods.HookScript(self, name, fn) self.hooks[name] = self.hooks[name] or {}; table.insert(self.hooks[name], fn) end
function Methods.RegisterEvent(self, ev) self.events[ev] = true end
function Methods.UnregisterEvent(self, ev) self.events[ev] = nil end
function Methods.Show(self) self.shown = true end
function Methods.Hide(self)
	local was = self.shown
	self.shown = false
	if was and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function Methods.SetShown(self, v) if v then self:Show() else self:Hide() end end
function Methods.IsShown(self) return self.shown end
-- Whether the frame takes the mouse (click-through frames don't).
function Methods.EnableMouse(self, on) self.mouse = on and true or false end
function Methods.IsMouseEnabled(self) return self.mouse == true end
function Methods.IsVisible(self) return self.shown end
function Methods.SetText(self, t) self.text = t; table.insert(STUB.texts, tostring(t)) end
function Methods.GetText(self) return self.text or "" end
function Methods.GetName(self) return self.name end
function Methods.GetParent(self) return self.parent end
function Methods.GetWidth(self) return self.width or 400 end
function Methods.GetHeight(self) return self.height or 300 end
function Methods.SetSize(self, w, h) self.width, self.height = w, h end
function Methods.SetWidth(self, w) self.width = w end
function Methods.SetHeight(self, h) self.height = h end
function Methods.GetSize(self) return self:GetWidth(), self:GetHeight() end
function Methods.GetStringHeight(self) return 14 end
function Methods.GetStringWidth(self) return 100 end
function Methods.GetFontString(self) return self end
function Methods.GetPoint(self) return "CENTER", nil, "CENTER", 0, 0 end
function Methods.SetPoint(self, point, rel, relPoint, x, y)
	if type(rel) == "number" then x, y, rel, relPoint = rel, relPoint, nil, nil end
	self.x, self.y = x or 0, y or 0
	self.anchor = { point = point, rel = rel, relPoint = relPoint or point }
end
function Methods.SetAlpha(self, a) self.alpha = a end
function Methods.GetAlpha(self) return self.alpha or 1 end
function Methods.GetVerticalScrollRange(self) return 0 end
function Methods.CreateTexture(self, name, layer)
	local t = NewObject("Texture", name, self)
	table.insert(self.textures, t)
	return t
end
function Methods.CreateFontString(self, name) return NewObject("FontString", name, self) end
function Methods.CreateAnimationGroup(self) return NewObject("AnimationGroup", nil, self) end
function Methods.CreateAnimation(self) return NewObject("Animation", nil, self) end
function Methods.IsPlaying(self) return self.playing or false end
function Methods.Play(self) self.playing = true end
function Methods.Stop(self) self.playing = false end
function Methods.SetColorTexture(self, r, g, b, a) self.color = { r, g, b, a } end
function Methods.SetTexture(self, path) self.texture = path; return true end
function Methods.GetTexture(self) return self.texture end
function Methods.SetBackdrop(self, t)
	-- The real client would silently draw nothing; make it a test failure instead.
	assert(type(t) == "table", "SetBackdrop called with " .. tostring(t) .. " on " .. tostring(self.name or self.kind))
	self.backdrop = t
end
function Methods.SetFocus(self) STUB.focus = self end
function Methods.ClearFocus(self) if STUB.focus == self then STUB.focus = nil end end
function Methods.HasFocus(self) return STUB.focus == self end
function Methods.Insert(self, t) self.text = (self.text or "") .. tostring(t) end
function Methods.GetEditBox(self) return self.editBox end
-- Tooltip scanning: SetHyperlink fills <name>TextLeft<i> / TextRight<i> from
-- STUB.tooltips[link], a list of strings or { left, right } pairs, then the
-- lines other addons' post-calls add to any tooltip frame (STUB.postCall,
-- TooltipDataProcessor.AddTooltipPostCall without a GameTooltip filter).
function Methods.ClearLines(self) self.lines = {} end
function Methods.NumLines(self) return #(self.lines or {}) end
function Methods.SetHyperlink(self, link)
	self.lines = {}
	for _, l in ipairs(STUB.tooltips[link] or {}) do table.insert(self.lines, l) end
	for _, l in ipairs(STUB.postCall or {}) do table.insert(self.lines, l) end
	for i, l in ipairs(self.lines) do
		local left, right = l, nil
		if type(l) == "table" then left, right = l[1], l[2] end
		local L = NewObject("FontString", self.name .. "TextLeft" .. i, self)
		L.text = left
		local R = NewObject("FontString", self.name .. "TextRight" .. i, self)
		R.text = right
		R.shown = right ~= nil
	end
end

-- The game's tooltip data for a link (C_TooltipInfo): STUB.tooltips's lines,
-- before any frame or addon post-call touches them.
C_TooltipInfo = {
	GetHyperlink = function(link)
		local src = STUB.tooltips[link]
		if not src then return nil end
		local data = { type = 0, lines = {} }
		for _, l in ipairs(src) do
			if type(l) == "table" then
				table.insert(data.lines, { leftText = l[1], rightText = l[2], type = 0 })
			else
				table.insert(data.lines, { leftText = l, type = 0 })
			end
		end
		return data
	end,
}

function CreateFrame(kind, name, parent, template)
	local f = NewObject(kind, name, parent)
	f.template = template
	table.insert(STUB.frames, f)
	return f
end

-- Fire an event on every frame that registered for it.
function STUB.FireEvent(ev, ...)
	for _, f in ipairs(STUB.frames) do
		if f.events[ev] and f.scripts.OnEvent then f.scripts.OnEvent(f, ev, ...) end
	end
end

-- Run every C_Timer.After callback that is due, then every ticker once.
function STUB.RunTimers()
	local due = STUB.timers
	STUB.timers = {}
	for _, t in ipairs(due) do t.fn() end
end
function STUB.Tick()
	for _, fn in ipairs(STUB.tickers) do fn() end
end

UIParent = CreateFrame("Frame", "UIParent")
GameTooltip = CreateFrame("Frame", "GameTooltip")
UIErrorsFrame = CreateFrame("Frame", "UIErrorsFrame")
-- What the game shows in its error line (red) or as a warning (yellow).
STUB.errors = {}
function UIErrorsFrame:AddExternalErrorMessage(t) table.insert(STUB.errors, "error: " .. t) end
function UIErrorsFrame:AddExternalWarningMessage(t) table.insert(STUB.errors, t) end
ChatFontNormal = {}
OKAY, CANCEL, DELETE = "Okay", "Cancel", "Delete"
NUM_CHAT_WINDOWS = 1
StaticPopupDialogs = {}
function StaticPopup_Show(which, a, b, data) STUB.popup = { which = which, data = data } end
SlashCmdList = {}
UISpecialFrames = {}
tinsert = table.insert
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function hooksecurefunc(a, b, c)
	if type(a) == "table" then
		local orig = a[b]
		a[b] = function(...) local r = orig(...); c(...); return r end
	else
		local orig = _G[a]
		_G[a] = function(...) local r = orig(...); b(...); return r end
	end
end
function InCombatLockdown() return STUB.combat end
function ReloadUI() STUB.reloaded = true end
function GetTime() return STUB.now end
function time() return STUB.epoch + math.floor(STUB.now) end
function date(fmt, t) return "12:00" end
C_Timer = {
	After = function(delay, fn) table.insert(STUB.timers, { delay = delay, fn = fn }) end,
	NewTicker = function(delay, fn) table.insert(STUB.tickers, fn); return { Cancel = noop } end,
}
C_AddOns = {
	IsAddOnLoaded = function(name) return STUB.loaded[name] or false end,
	LoadAddOn = function(name)
		STUB.loaded[name] = true
		if STUB.onLoadAddOn then STUB.onLoadAddOn(name) end
		return true
	end,
}
C_Texture = { GetAtlasExists = function() return true end }
function PlaySound() end
function PlaySoundFile(path) if STUB.sounds[path] then return true, 1 end return false end
function StopSound() end
function GetPhysicalScreenSize() return 1920, 1080 end
function SetBinding(key, cmd) STUB.bindings[key] = cmd end
function SaveBindings() end
function GetCurrentBindingSet() return 1 end
function SetItemRef() end
-- Nothing of Blizzard's is ever active here, so the link goes nowhere unless the
-- addon takes it. The Forever client's UI code calls ChatFrameUtil.InsertLink;
-- ChatEdit_InsertLink is the older global name.
ChatFrameUtil = { InsertLink = function(text) return false end }
function ChatEdit_InsertLink(text) return ChatFrameUtil.InsertLink(text) end

-- The character: a level-15 Dwarf rogue, as tests/fixtures/state-parts.json has it (milestone 4's
-- contract; the probe of 2026-11-10 on client 1.60.1.70888, made up where the probe didn't read).
-- Only the Forever forms of each function: the classic ones the probe found missing
-- (GetNumTalentTabs, GetTalentInfo, GetNumSkillLines, GetSkillLineInfo, GetFactionInfo, GetItemStats,
-- the global GetSpecialization) aren't here, so nothing can lean on them. Tests change STUB.player,
-- STUB.items, STUB.equipped, STUB.bags, STUB.skills, STUB.quests, STUB.factions and STUB.talents.
function GetBuildInfo() return "1.60.1", "69913", "Sep 1 2026", 16001 end
-- Never read by Spellmind (privacy): every call is counted, and the tests check none was made.
STUB.identityCalls = {}
function UnitName(unit) table.insert(STUB.identityCalls, "UnitName"); if unit == "player" then return "Testchar" end end
function GetRealmName() table.insert(STUB.identityCalls, "GetRealmName"); return "Test Realm" end
function GetGuildInfo(unit) table.insert(STUB.identityCalls, "GetGuildInfo"); return "Test Guild", "Member", 1 end
function GetNormalizedRealmName() table.insert(STUB.identityCalls, "GetNormalizedRealmName"); return "TestRealm" end
function UnitFullName(unit) table.insert(STUB.identityCalls, "UnitFullName"); return "Testchar", "TestRealm" end

STUB.player = {
	guid = "Player-4372-0A1B2C3D",
	class = { "Rogue", "ROGUE", 4 }, race = { "Dwarf", "Dwarf", 3 }, faction = { "Alliance", "Alliance" },
	level = 15, xp = 2944, xpMax = 14400, rested = 1550, resting = true, money = 9851,
	map = 1432, zone = "Loch Modan", subzone = "Stoutlager Inn", x = 0.354, y = 0.482,
	hp = 363, power = { [0] = 0, [3] = 100 },
	-- UnitStat: base, effective, plus, minus
	stats = { { 33, 36, 3, 0 }, { 38, 49, 11, 0 }, { 37, 40, 3, 0 }, { 18, 18, 0, 0 }, { 25, 25, 0, 0 } },
	armor = { 333, 333, 0, 0 }, ap = { 95, 0, 0 }, rap = { 93, 0, 0 },
	crit = 10.41234, rcrit = 10.287600517273, scrit = 2, dodge = 16.695199966431, parry = 4.8, block = 0,
	res = { [1] = 0, [2] = 0, [3] = 0, [4] = 0, [5] = 0, [6] = 0 },
}
local P = STUB.player
function UnitGUID(unit) if unit == "player" then return P.guid end end
function UnitClass(unit) return P.class[1], P.class[2], P.class[3] end
function UnitRace(unit) return P.race[1], P.race[2], P.race[3] end
function UnitFactionGroup(unit) return P.faction[1], P.faction[2] end
function UnitLevel(unit) return P.level end
function UnitXP(unit) return P.xp end
function UnitXPMax(unit) return P.xpMax end
function GetXPExhaustion() return P.rested end
function IsResting() return P.resting end
function GetMoney() return P.money end
function GetZoneText() return P.zone end
function GetRealZoneText() return P.zone end
function GetSubZoneText() return P.subzone end
C_Map = {
	GetBestMapForUnit = function(unit) return P.map end,
	-- A Vector2D in the game: GetXY gives both.
	GetPlayerMapPosition = function(mapId, unit)
		return { x = P.x, y = P.y, GetXY = function(self) return self.x, self.y end }
	end,
	GetMapInfo = function(mapId) return { name = P.zone, mapID = mapId } end,
}
function UnitHealthMax(unit) return P.hp end
function UnitPowerMax(unit, kind) return P.power[kind or 0] or 0 end
function UnitStat(unit, i) local s = P.stats[i]; return s[1], s[2], s[3], s[4] end
function UnitArmor(unit) return P.armor[1], P.armor[2], P.armor[3], P.armor[4] end
function UnitAttackPower(unit) return P.ap[1], P.ap[2], P.ap[3] end
function UnitRangedAttackPower(unit) return P.rap[1], P.rap[2], P.rap[3] end
function GetCritChance() return P.crit end
function GetRangedCritChance() return P.rcrit end
function GetSpellCritChance(school) return P.scrit end
function GetDodgeChance() return P.dodge end
function GetParryChance() return P.parry end
function GetBlockChance() return P.block end
function UnitResistance(unit, i) local v = P.res[i] or 0; return v, v, 0, 0 end

-- Talents: the modern trait tree, one per class.
STUB.talents = {
	config = 2229800, tree = 1111, spec = { 1488, "Rogue", "", 626005, "DAMAGER" },
	currency = { { traitCurrencyID = 2000, quantity = 0, maxQuantity = 6, spent = 6 } },
	-- In the tree's order; rank 0 nodes aren't sent.
	nodes = {
		{ ID = 105708, activeRank = 1, maxRanks = 3, entryIDs = { 130437 }, activeEntry = { entryID = 130437, rank = 1 }, isVisible = true, type = 0 },
		{ ID = 105709, activeRank = 0, maxRanks = 2, entryIDs = { 130438 }, isVisible = true, type = 0 },
		{ ID = 105712, activeRank = 2, maxRanks = 2, entryIDs = { 130441 }, activeEntry = { entryID = 130441, rank = 2 }, isVisible = true, type = 0 },
		{ ID = 105715, activeRank = 0, maxRanks = 1, entryIDs = { 130444 }, isVisible = true, type = 0 },
		-- A choice node: the chosen entry's name.
		{ ID = 105720, activeRank = 3, maxRanks = 5, entryIDs = { 130450, 130451 }, activeEntry = { entryID = 130451, rank = 3 }, isVisible = true, type = 2 },
	},
	entries = { [130437] = 9001, [130438] = 9002, [130441] = 9005, [130444] = 9008, [130450] = 9010, [130451] = 9011 },
	-- definition: overrideName, else spellID's name
	defs = {
		[9001] = { overrideName = "Malice", spellID = 14138 },
		[9002] = { spellID = 13741 }, [9005] = { overrideName = "", spellID = 13732 }, [9008] = { spellID = 14165 },
		[9010] = { spellID = 13712 }, [9011] = { spellID = 13789 },
	},
}
STUB.spells = { [14138] = "Malice", [13741] = "Improved Gouge", [13732] = "Improved Sinister Strike", [14165] = "Improved Eviscerate",
	[13712] = "Deflection", [13789] = "Lightning Reflexes" }
local T = STUB.talents
C_SpecializationInfo = {
	GetSpecialization = function() return 1 end,
	GetSpecializationInfo = function(i) if i == 1 then return T.spec[1], T.spec[2], T.spec[3], T.spec[4], T.spec[5] end end,
}
C_ClassTalents = { GetActiveConfigID = function() return T.config end }
local function NodeById(id) for _, n in ipairs(T.nodes) do if n.ID == id then return n end end end
C_Traits = {
	GetConfigInfo = function(config) if config == T.config then return { ID = config, type = 4, name = "Rogue", treeIDs = { T.tree } } end end,
	GetTreeNodes = function(tree)
		if tree ~= T.tree then return {} end
		local ids = {}
		for i, n in ipairs(T.nodes) do ids[i] = n.ID end
		return ids
	end,
	GetNodeInfo = function(config, id)
		local n = NodeById(id)
		if not n then return { ID = 0, activeRank = 0, maxRanks = 0, entryIDs = {} } end
		return { ID = n.ID, activeRank = n.activeRank, currentRank = n.activeRank, ranksPurchased = n.activeRank, maxRanks = n.maxRanks,
			entryIDs = n.entryIDs, activeEntry = n.activeEntry, isVisible = n.isVisible, type = n.type }
	end,
	GetEntryInfo = function(config, entryID) local d = T.entries[entryID]; if d then return { definitionID = d, maxRanks = 1 } end end,
	GetDefinitionInfo = function(def) return T.defs[def] end,
	GetTreeCurrencyInfo = function(config, tree, excludeStaged) return T.currency end,
}
C_Spell = { GetSpellName = function(id) return STUB.spells[id] end }
function GetNumUnspentTalents() return 0 end

-- Items: C_Item.GetItemInfo's returns by id; stats as C_Item.GetItemStats gives them.
-- { name, quality, ilvl, reqLevel, type, subType, stack, equipLoc, icon, sellPrice, classID, subclassID, dilvl = detailed }
STUB.items = {
	[9748] = { "Simple Robe of the Monkey", 2, 15, 10, "Armor", "Leather", 1, "INVTYPE_ROBE", 132719, 120, 4, 2 },
	[4237] = { "Handstitched Leather Pants", 1, 10, 5, "Armor", "Leather", 1, "INVTYPE_LEGS", 134582, 30, 4, 2 },
	-- GetItemInfo says 13, the detailed level 15 (the probe's dagger).
	[2218] = { "Craftsman's Dagger", 2, 13, 11, "Weapon", "Daggers", 1, "INVTYPE_WEAPON", 135641, 501, 2, 15, dilvl = 15 },
	[6948] = { "Hearthstone", 1, 1, 0, "Miscellaneous", "Junk", 1, "INVTYPE_NON_EQUIP_IGNORE", 134414, 0, 15, 0 },
	[2318] = { "Light Leather", 1, 10, 0, "Trade Goods", "Leather", 200, "", 134256, 15, 7, 6 },
	[2934] = { "Ruined Leather Scraps", 1, 3, 0, "Trade Goods", "Leather", 200, "", 134251, 5, 7, 6 },
	[2589] = { "Linen Cloth", 1, 5, 0, "Trade Goods", "Cloth", 200, "", 132889, 13, 7, 5 },
	[3300] = { "Rabbit's Foot", 0, 1, 0, "Miscellaneous", "Junk", 10, "", 133854, 45, 15, 0 },
	[4865] = { "Ruined Pelt", 0, 1, 0, "Miscellaneous", "Junk", 10, "", 134367, 50, 15, 0 },
	[2140] = { "Fine Longsword", 2, 19, 14, "Weapon", "One-Handed Swords", 1, "INVTYPE_WEAPONMAINHAND", 135321, 300, 2, 7 },
}
STUB.itemStats = {
	[9748] = { ITEM_MOD_AGILITY_SHORT = 3, ITEM_MOD_STAMINA_SHORT = 3, RESISTANCE0_NAME = 28 },
	[4237] = { ITEM_MOD_AGILITY_SHORT = 1, RESISTANCE0_NAME = 48 },
	[2218] = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 6.0999999046326 },
}
function STUB.ItemLink(id, ench)
	local it = STUB.items[id]
	return string.format("|cnIQ%d:|Hitem:%d:%s:::::::15:1488::11:::::::|h[%s]|h|r", it[2], id, ench and tostring(ench) or "", it[1])
end
local function ItemId(x)
	if type(x) == "number" then return x end
	return tonumber(tostring(x):match("item:(%d+)"))
end
C_Item = {
	GetItemInfo = function(x)
		local id = ItemId(x)
		local it = id and STUB.items[id]
		if not it then return nil end
		return it[1], STUB.ItemLink(id), it[2], it[3], it[4], it[5], it[6], it[7], it[8], it[9], it[10], it[11], it[12]
	end,
	GetDetailedItemLevelInfo = function(x)
		local id = ItemId(x)
		local it = id and STUB.items[id]
		if it then return it.dilvl or it[3], false, it[3] end
	end,
	GetItemStats = function(link)
		local id = ItemId(link)
		local s = id and STUB.itemStats[id]
		local out = {}
		for k, v in pairs(s or {}) do out[k] = v end
		return out
	end,
}
ITEM_QUALITY2_DESC = "Uncommon"

-- Equipped: slot -> { id, link, dur = { cur, max } }.
STUB.equipped = {
	[5] = { id = 9748, link = "|cnIQ2:|Hitem:9748::::::::15:1488:::1:12721::::::|h[Simple Robe of the Monkey]|h|r", dur = { 36, 50 } },
	[7] = { id = 4237, link = "|cnIQ1:|Hitem:4237:1:::::::15:1488::::::::|h[Handstitched Leather Pants]|h|r", dur = { 34, 40 } },
	[16] = { id = 2218, link = "|cnIQ2:|Hitem:2218::::::::15:1488::11:::::::|h[Craftsman's Dagger]|h|r", dur = { 40, 45 } },
}
function GetInventoryItemID(unit, slot) local e = STUB.equipped[slot]; return e and e.id or nil end
function GetInventoryItemLink(unit, slot) local e = STUB.equipped[slot]; return e and e.link or nil end
function GetInventoryItemDurability(slot) local e = STUB.equipped[slot]; if e and e.dur then return e.dur[1], e.dur[2] end end

-- Bags 0..NUM_BAG_SLOTS: { size, free (as the game counts it), items = { [slot] = { id, count, bound } } }.
NUM_BAG_SLOTS = 4
STUB.bags = {
	[0] = { size = 16, free = 2, items = { { 6948, 1, true }, { 2318, 12 }, { 2934, 4 }, { 2589, 14 }, { 3300, 1 }, { 4865, 2 } } },
	[1] = { size = 12, free = 4, items = { [3] = { 2318, 8 } } },
	[2] = { size = 12, free = 2, items = {} },
	[3] = { size = 12, free = 2, items = {} },
	[4] = { size = 12, free = 2, items = {} },
}
C_Container = {
	GetContainerNumSlots = function(bag) local b = STUB.bags[bag]; return b and b.size or 0 end,
	GetContainerNumFreeSlots = function(bag) local b = STUB.bags[bag]; return b and b.free or 0, 0 end,
	GetContainerItemInfo = function(bag, slot)
		local b = STUB.bags[bag]
		local e = b and b.items[slot]
		if not e then return nil end
		local it = STUB.items[e[1]]
		return { itemID = e[1], itemName = it[1], quality = it[2], stackCount = e[2], isBound = e[3] or false,
			hasNoValue = (it[10] or 0) == 0, hyperlink = STUB.ItemLink(e[1]), isLocked = false, iconFileID = it[9] }
	end,
}

-- Skill lines, as C_SkillInfo gives them (one table each).
TRADE_SKILLS, SECONDARY_SKILLS = "Professions", "Secondary Skills"
STUB.skills = {
	{ name = "Class Skills", skillID = 7, isHeader = true },
	{ name = "Assassination", skillID = 253, rank = 1, maxRank = 1 },
	{ name = "Professions", skillID = 0, isHeader = true },
	{ name = "Skinning", skillID = 393, rank = 58, maxRank = 75 },
	{ name = "Leatherworking", skillID = 165, rank = 61, maxRank = 75 },
	{ name = "Weapon Skills", skillID = 0, isHeader = true },
	{ name = "Daggers", skillID = 173, rank = 72, maxRank = 75 },
	{ name = "Swords", skillID = 43, rank = 40, maxRank = 75 },
	{ name = "Defense", skillID = 95, rank = 70, maxRank = 75 },
	{ name = "Armor Proficiencies", skillID = 0, isHeader = true },
	{ name = "Leather", skillID = 414, rank = 1, maxRank = 1 },
	{ name = "Languages", skillID = 0, isHeader = true, isCollapsed = true },
	{ name = "Language: Dwarven", skillID = 111, rank = 300, maxRank = 300 },
}
C_SkillInfo = {
	GetNumSkillLines = function() return #STUB.skills end,
	GetSkillLineInfo = function(i)
		local s = STUB.skills[i]
		if not s then return nil end
		return { name = s.name, skillID = s.skillID, rank = s.rank or 0, maxRank = s.maxRank or 0, isHeader = s.isHeader or false,
			isCollapsed = s.isCollapsed or false, modifier = 0, parentSkillLineID = 0 }
	end,
}

-- The quest log: every row C_QuestLog.GetInfo lists, quests under a collapsed header too.
-- Opening or closing a header is never done (STUB.questHeaders counts any try).
STUB.quests = {
	{ title = "Loch Modan", isHeader = true },
	{ title = "Snowbound", questID = 86667, level = 10 },
	{ title = "Stormpike's Order", questID = 1338, level = 14, complete = true },
	{ title = "Bingles' Missing Supplies", questID = 2038, level = 15 },
	{ title = "Dun Morogh", isHeader = true, isCollapsed = true },
	{ title = "In Defense of the King's Lands", questID = 263, level = 15, complete = true },
	{ title = "Report to Ironforge", questID = 301, level = 15, complete = true },
	{ title = "A hidden one", questID = 999, level = 1, isHidden = true },
	{ title = "Ironforge", isHeader = true },
	{ title = "Gathering Idols", questID = 297, level = 18 },
	{ title = "Old Ironforge Incursion", questID = 96393, level = 16 },
}
STUB.objectives = {
	[86667] = { { text = "Jar of Snow: 0/1", numFulfilled = 0, numRequired = 1, finished = false } },
	[2038] = { { text = "Bingles' Wrench: 0/1", numFulfilled = 0, numRequired = 1 }, { text = "Bingles' Screwdriver: 0/1", numFulfilled = 0, numRequired = 1 } },
	[297] = { { text = "Carved Stone Idol: 0/8", numFulfilled = 0, numRequired = 8 } },
	[96393] = { { text = "Durgen Dirgehammer's Head: 0/1", numFulfilled = 0, numRequired = 1 } },
}
STUB.questHeaders = {}
Constants = { QuestLogConsts = { MAXIMUM_NUM_QUESTS_LOG_CAN_ACCEPT = 40 } }
C_QuestLog = {
	GetNumQuestLogEntries = function()
		local n = 0
		for _, q in ipairs(STUB.quests) do if not q.isHeader then n = n + 1 end end
		return #STUB.quests, n
	end,
	GetInfo = function(i)
		local q = STUB.quests[i]
		if not q then return nil end
		return { title = q.title, questID = q.questID or 0, level = q.level or 0, isHeader = q.isHeader or false,
			isCollapsed = q.isCollapsed or false, isHidden = q.isHidden or false, isTask = false, isBounty = false, questLogIndex = i }
	end,
	IsComplete = function(id)
		for _, q in ipairs(STUB.quests) do if q.questID == id then return q.complete or false end end
		return false
	end,
	GetQuestObjectives = function(id) return STUB.objectives[id] or {} end,
	-- A stale 25, as some clients answer: Forever's constant (40) wins.
	GetMaxNumQuestsCanAccept = function() return 25 end,
	ExpandQuestHeader = function(i) table.insert(STUB.questHeaders, "expand " .. tostring(i)) end,
	CollapseQuestHeader = function(i) table.insert(STUB.questHeaders, "collapse " .. tostring(i)) end,
}

-- Reputation, as C_Reputation gives it (one table each).
STUB.factions = {
	{ factionID = 469, name = "Alliance", isHeader = true, reaction = 5, currentStanding = 3581, currentReactionThreshold = 3000, nextReactionThreshold = 9000 },
	{ factionID = 47, name = "Ironforge", reaction = 5, currentStanding = 3581, currentReactionThreshold = 3000, nextReactionThreshold = 9000, isChild = true },
	{ factionID = 72, name = "Stormwind", reaction = 4, currentStanding = 2100, currentReactionThreshold = 0, nextReactionThreshold = 3000, isChild = true },
	{ factionID = 54, name = "Gnomeregan", reaction = 4, currentStanding = 400, currentReactionThreshold = 0, nextReactionThreshold = 3000, isChild = true },
}
C_Reputation = {
	GetNumFactions = function() return #STUB.factions end,
	GetFactionDataByIndex = function(i)
		local f = STUB.factions[i]
		if not f then return nil end
		local out = { isHeader = false, isCollapsed = false, isWatched = false, isHeaderWithRep = false, isChild = false }
		for k, v in pairs(f) do out[k] = v end
		return out
	end,
	GetWatchedFactionData = function()
		for _, f in ipairs(STUB.factions) do if f.isWatched then return { factionID = f.factionID, name = f.name } end end
		return nil
	end,
}
function print(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
	table.insert(STUB.prints, table.concat(parts, " "))
end
