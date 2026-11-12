-- Settings.lua: every switch in one list, for the Spellmind window's Settings tab (docs/milestone-12.md).
-- Each lives where it always did (SpellmindDB.marks, .nudges, .share, .ui, .minimap), so the slash
-- commands (/sm marks off, /sm nudges off, /sm data off, /sm minimap off) and this tab agree.
--
--   { section, rows = { { id, label, sub, get(), set(v), choices? } } }
--
-- A row without choices is On or Off; with choices, a click goes to the next one.

local _, ns = ...
local ST = {}
ns.Settings = ST

-- The marks: the keys Marks.On reads.
ST.MARKS = {
	{ "quest", "Quest log: Break it down", "The owl mark beside a quest's details." },
	{ "tooltip", "Item tooltips", "Spellmind's lines: upgrade, sell, profession use." },
	{ "reward", "Quest rewards: the pick", "Which reward to take when you turn a quest in." },
	{ "sheet", "Character sheet: the dots", "Upgrades waiting and gear about to break." },
	{ "merchant", "Merchant: what to sell", "A button beside a vendor's window." },
	{ "trainer", "Class trainer: what to train", "A button beside your trainer's window." },
}

ST.NUDGES = {
	{ "talents", "Talent points to spend" },
	{ "spells", "Spells to train" },
	{ "durability", "Gear about to break" },
	{ "bags", "Bags nearly full" },
	{ "turnin", "Quests ready to turn in" },
	{ "near", "A turn-in nearby" },
	{ "prof", "Professions near their cap" },
}

ST.PARTS = {
	stats = { "Stats", "Health, mana, attributes, crit and the rest." },
	talents = { "Talents", "Where your points are." },
	spells = { "Spells", "Your spellbook and your trainer's list." },
	gear = { "Gear worn", "Each item, its stats and durability." },
	bags = { "Bags", "What you carry, by kind." },
	skills = { "Skills", "Professions and weapon skills." },
	quests = { "Quest log", "Your quests and their objectives." },
	rep = { "Reputations", "Your standing with each faction." },
}

ST.CHAT_NAMES = { all = "Whole", first = "First line", off = "Off" }

local function Marks()
	local db = ns.db
	if type(db.marks) ~= "table" then db.marks = {} end
	return db.marks
end

function ST.MarkOn(key) return ns.Marks.On(key) end

-- One mark on or off. After /sm marks off (all = false) the others stay off: each gets its own switch.
function ST.SetMark(key, on)
	local m = Marks()
	if m.all == false then
		for _, row in ipairs(ST.MARKS) do m[row[1]] = false end
		m.all = nil
	end
	if on then m[key] = nil else m[key] = false end
	if key == "quest" and ns.Quests then
		if not on and ns.Quests.mark then ns.Quests.mark:Hide() end
		if on then ns.Quests.Hook() end
	end
	if key == "sheet" and ns.GearUI and ns.GearUI.MarkSlots then pcall(ns.GearUI.MarkSlots) end
end

-- The sections, as the tab draws them.
function ST.List()
	local out = {}
	local marks = { section = "On the game's windows", rows = {} }
	for _, r in ipairs(ST.MARKS) do
		local key = r[1]
		marks.rows[#marks.rows + 1] = { id = "mark:" .. key, label = r[2], sub = r[3],
			get = function() return ST.MarkOn(key) end, set = function(v) ST.SetMark(key, v) end }
	end
	out[#out + 1] = marks

	local nudges = { section = "Nudges", rows = {} }
	local N = ns.Nudges
	nudges.rows[1] = { id = "nudges", label = "Nudges by the minimap", sub = "Off: none of the kinds below.",
		get = function() return N.On() end, set = function(v) N.SetOn(v) end }
	for _, r in ipairs(ST.NUDGES) do
		local kind = r[1]
		nudges.rows[#nudges.rows + 1] = { id = "nudge:" .. kind, label = r[2], indent = true,
			get = function() return N.KindOn(kind) end, set = function(v) N.SetKind(kind, v) end,
			dim = function() return not N.On() end }
	end
	out[#out + 1] = nudges

	local data = { section = "Game data the AI gets", rows = {} }
	local S = ns.State
	data.rows[1] = { id = "data", label = "Game data", sub = "Your class, level and zone always go with it. Never your name, realm or guild.",
		get = function() return S.Sharing() end, set = function(v) if v then S.On() else S.Off() end end }
	for _, p in ipairs(S.OPTIONAL) do
		local info = ST.PARTS[p] or { p }
		data.rows[#data.rows + 1] = { id = "part:" .. p, label = info[1], sub = info[2], indent = true,
			get = function() return S.PartOn(p) end, set = function(v) S.SetPart(p, v) end,
			dim = function() return not S.Sharing() end }
	end
	out[#out + 1] = data

	local other = { section = "Chat and the minimap", rows = {} }
	other.rows[1] = { id = "chatLines", label = "Answers in the game's chat", sub = "Whole: a short answer in full. First line: a summary. Off: only in this window.",
		choices = ns.Chat.CHAT_LINES, names = ST.CHAT_NAMES,
		get = function() return ns.Chat.ChatLines() end, set = function(v) ns.Chat.SetChatLines(v) end }
	other.rows[2] = { id = "minimap", label = "Minimap button", sub = "Off: /sm opens the chat.",
		get = function() return not (type(ns.db.minimap) == "table" and ns.db.minimap.hide) end,
		set = function(v) ns.MinimapButton.Show(v) end }
	out[#out + 1] = other
	return out
end

-- A row by id (the tests, and the tab's clicks).
function ST.Row(id)
	for _, sec in ipairs(ST.List()) do
		for _, r in ipairs(sec.rows) do if r.id == id then return r end end
	end
	return nil
end

-- A click: On to Off and back, or the next of its choices.
function ST.Flip(id)
	local r = ST.Row(id)
	if not r then return end
	if r.choices then
		local cur, n = r.get(), #r.choices
		for i, c in ipairs(r.choices) do
			if c == cur then r.set(r.choices[i % n + 1]); return end
		end
		r.set(r.choices[1])
	else
		r.set(not r.get())
	end
end

-- The button's label for a row now.
function ST.Label(r)
	if r.choices then
		local v = r.get()
		local name = (r.names and r.names[v]) or tostring(v)
		return v == "off" and ("|cff888888" .. name .. "|r") or ("|cff19ff19" .. name .. "|r")
	end
	return r.get() and "|cff19ff19On|r" or "|cff888888Off|r"
end
