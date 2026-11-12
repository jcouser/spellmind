-- Panel.lua: the Spellmind window (docs/features.md §2, docs/milestone-7.md, docs/milestone-11.md;
-- mockup B of 2026-11-10). One window with a rail of tabs: Chat at the top (Window.lua draws it),
-- then Quests, Gear, Talents, Spells, Professions, Gold and Nudges, the character's live facts at a
-- glance, read locally (no AI), with Ask buttons whose answers show in the card beside the window, so
-- the tab stays in view. Compact mode hides the rail: the chat alone, small, for questing. The
-- minimap button's click opens the Chat tab, its right-click (and /sm panel) the last other tab.
--
-- Read only, like the marks: nothing is selected, equipped, sold or set.

local _, ns = ...
local P = {}
ns.Panel = P
local R = ns.R

P.W, P.H = 600, 480
P.MIN_W, P.MIN_H, P.MAX_W, P.MAX_H = 560, 400, 1100, 1000 -- the rail's ten tabs fit
-- Compact: the chat alone.
P.CW, P.CH = 440, 460
P.CMIN_W, P.CMIN_H = 406, 366
P.HEAD_H = 54 -- the header, to the rule under it
P.FOLD_H = 52
P.RAIL_W = 150
P.ROW_H = 24
P.ROW_H2 = 38 -- a row with a second line
P.BAG_ROWS = 8
P.TABS = {
	{ id = "chat", name = "Chat", icon = "Interface\\AddOns\\Spellmind\\Media\\Portrait" },
	{ id = "quests", name = "Quests", icon = "Interface\\Icons\\INV_Letter_15" },
	{ id = "dungeons", name = "Dungeons", icon = "Interface\\Icons\\INV_Misc_Key_03" },
	{ id = "gear", name = "Gear", icon = "Interface\\Icons\\INV_Chest_Leather_09" },
	{ id = "talents", name = "Talents", icon = "Interface\\Icons\\Ability_Marksmanship" },
	{ id = "spells", name = "Spells", icon = "Interface\\Icons\\Spell_Holy_MagicalSentry" },
	{ id = "professions", name = "Professions", icon = "Interface\\Icons\\Trade_BlackSmithing" },
	{ id = "gold", name = "Gold", icon = "Interface\\Icons\\INV_Misc_Coin_01" },
	{ id = "nudges", name = "Nudges", icon = "Interface\\AddOns\\Spellmind\\Media\\Mark" },
	{ id = "settings", name = "Settings", icon = "Interface\\Icons\\INV_Misc_Gear_01" },
}
-- Each tab's two Ask buttons: { label, the question }.
P.ASKS = {
	dungeons = { { "Which dungeon now?", "DUNGEON_WHICH" }, { "Brief my next one", "DUNGEON_NEXT" } },
	quests = { { "Plan my next hour", "Plan my next hour of questing: which of my quests to do, in what order, and where." }, { "What's worth skipping?", "Which of my quests are worth skipping or leaving for later, and why?" } },
	gear = { { "Find my next upgrades", "GEAR_UPGRADES" }, { "What should I sell?", "What in my bags should I sell, keep or put on the auction house?" } },
	talents = { { "Plan my next points", "Plan my next talent points for how I play now." }, { "Is my build good?", "Is my talent build good for my level and role? What would you change?" } },
	spells = { { "What do I train next?", "What should I train next, and when? Which spells matter most for me?" }, { "My rotation", "What should my basic rotation be with the spells I have?" } },
	professions = { { "Level my professions", "How do I level my professions from where they are now?" }, { "Which suit me?", "Which professions suit my class and how I play, and why?" } },
	gold = { { "Make gold", "How can I make gold at my level with what I have?" }, { "Bag space", "My bags: what should I clear, sell or bank first?" } },
}
P.SLOT_NAMES = { "Head", "Neck", "Shoulder", "Shirt", "Chest", "Waist", "Legs", "Feet", "Wrist", "Hands", "Ring", "Ring",
	"Trinket", "Trinket", "Back", "Main Hand", "Off Hand", "Ranged", "Tabard" }

local panel
local BACKDROP = { bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } }

local function Saved()
	local db = ns.db
	if not db then return {} end
	if type(db.panel) ~= "table" then db.panel = {} end
	return db.panel
end

-- An O object (State.lua's JSON objects) as a plain table, lists too.
local function Plain(o)
	if type(o) ~= "table" then return o end
	if o._o then
		local t = {}
		for _, kv in ipairs(o._o) do t[kv[1]] = Plain(kv[2]) end
		return t
	end
	local t = {}
	for i, v in ipairs(o) do t[i] = Plain(v) end
	return t
end

local function Part(name)
	local fn = ns.State and ns.State.Collect and ns.State.Collect[name]
	if type(fn) ~= "function" then return {} end
	local ok, o = pcall(fn)
	return ok and Plain(o) or {}
end

local function Money(copper)
	copper = math.floor(tonumber(copper) or 0)
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	local out = {}
	if g > 0 then out[#out + 1] = "|cffffd100" .. g .. "g|r" end
	if s > 0 or g > 0 then out[#out + 1] = "|cffc7c7cf" .. s .. "s|r" end
	out[#out + 1] = "|cffeda55f" .. c .. "c|r"
	return table.concat(out, " ")
end

local function Hex(r, g, b)
	return string.format("|cff%02x%02x%02x", math.floor((r or 1) * 255), math.floor((g or 1) * 255), math.floor((b or 1) * 255))
end

local QUALITY = { [0] = "|cff9d9d9d", [1] = "|cffffffff", [2] = "|cff1eff00", [3] = "|cff0070dd", [4] = "|cffa335ee", [5] = "|cffff8000" }

---------------------------------------------------------------------------
-- Rows: a pool of generic rows the tabs fill
---------------------------------------------------------------------------

local function NewRow(f)
	local r = CreateFrame("Frame", nil, f.content, "BackdropTemplate")
	r:SetHeight(P.ROW_H)
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(20, 20)
	r.icon:SetPoint("LEFT", r, "LEFT", 4, 0)
	r.left = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	r.left:SetJustifyH("LEFT")
	if r.left.SetWordWrap then r.left:SetWordWrap(false) end
	r.right = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	-- A second line (a quest's what's-left), small, under the first.
	r.sub = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	r.sub:SetJustifyH("LEFT")
	if r.sub.SetWordWrap then r.sub:SetWordWrap(false) end
	r.right:SetJustifyH("RIGHT")
	r.tag = CreateFrame("Frame", nil, r, "BackdropTemplate")
	r.tag:SetHeight(16)
	if r.tag.SetBackdrop then r.tag:SetBackdrop(BACKDROP) end
	r.tag.text = r.tag:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.tag.text:SetPoint("CENTER", r.tag, "CENTER", 0, 0)
	r.rule = r:CreateTexture(nil, "ARTWORK")
	r.rule:SetColorTexture(0.62, 0.49, 1, 0.35)
	r.rule:SetHeight(1)
	r.rule:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
	r.rule:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
	return r
end

-- The rows laid out from a list of specs:
--   { kind = "head", text }                          a section title, gold, with a rule
--   { kind = "item", icon, left, right, tag = { text, r, g, b }, quest = id }   a row; quest: a Break it down mark
--   { kind = "text", text }                          a plain line
--   indent = true: the row set in (a setting under its section's main switch)
local function Draw(f, specs, keepScroll)
	local y = -2
	local w = f.content:GetWidth()
	f.drawn = {}
	for i, s in ipairs(specs) do
		local r = f.rows[i] or NewRow(f)
		f.rows[i] = r
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, y)
		r:SetWidth(w)
		r.icon:SetShown(s.kind == "item" and s.icon ~= nil)
		-- A reused row keeps no buttons of its last life (seen in game: "Nothing waiting" with Ask and
		-- Dismiss over it).
		for _, a in ipairs(r.actions or {}) do a:Hide() end
		r.tag:Hide()
		r.rule:SetShown(s.kind == "head")
		r.right:SetText("")
		r.sub:SetText("")
		r.sub:Hide()
		r.left:ClearAllPoints()
		r.right:ClearAllPoints()
		if r.mark then r.mark:Hide() end
		if r.SetBackdrop then
			if s.kind == "item" then
				if not r.bd then r:SetBackdrop(BACKDROP); r.bd = true end
				r:SetBackdropColor(0.07, 0.05, 0.14, 0.9)
				r:SetBackdropBorderColor(0.45, 0.36, 0.78, 0.8)
			elseif r.bd then
				r:SetBackdropColor(0, 0, 0, 0)
				r:SetBackdropBorderColor(0, 0, 0, 0)
			end
		end
		if s.kind == "head" then
			r:SetHeight(26)
			r.left:SetFontObject(GameFontNormal)
			r.left:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 2, 4)
			r.left:SetText(s.text)
			y = y - 30
		elseif s.kind == "text" then
			r:SetHeight(20)
			r.left:SetFontObject(GameFontHighlightSmall)
			r.left:SetPoint("LEFT", r, "LEFT", 4, 0)
			r.left:SetWidth(w - 8)
			r.left:SetText(s.text)
			y = y - 22
		else
			local h = s.sub and P.ROW_H2 or P.ROW_H
			r:SetHeight(h)
			r.left:SetFontObject(GameFontHighlight)
			if s.icon then r.icon:SetTexture(s.icon) end
			local lx = (s.icon and 30 or 8) + (s.indent and 16 or 0)
			if s.sub then
				r.left:SetPoint("TOPLEFT", r, "TOPLEFT", lx, -5)
				r.sub:ClearAllPoints()
				r.sub:SetPoint("TOPLEFT", r, "TOPLEFT", lx + 2, -21)
				r.sub:SetText(s.sub)
				r.sub:Show()
			else
				r.left:SetPoint("LEFT", r, "LEFT", lx, 0)
			end
			local rightEdge = -6
			if s.quest and ns.Marks then
				if not r.mark then
					r.mark = ns.Marks.Create(r, nil, {
						facts = function() return ns.Quests.Facts(r.mark.questID) end,
						explain = function()
							local req = ns.Quests.Explain(r.mark.questID, panel)
							if req then req.owner = panel end
							return req
						end,
					})
					r.mark:SetSize(18, 18)
				end
				r.mark.questID = s.quest
				r.mark:ClearAllPoints()
				r.mark:SetPoint("RIGHT", r, "RIGHT", -4, 0)
				r.mark:Show()
				rightEdge = -28
			end
			-- Buttons of the row's own (a nudge's Ask and Dismiss), at the right.
			r.actions = r.actions or {}
			for _, a in ipairs(r.actions) do a:Hide() end
			for k = #(s.actions or {}), 1, -1 do
				local spec = s.actions[k]
				local a = r.actions[k]
				if not a then
					a = CreateFrame("Button", nil, r, "BackdropTemplate")
					a:SetSize(58, 18)
					if a.SetBackdrop then
						a:SetBackdrop(BACKDROP)
						a:SetBackdropColor(0.08, 0.06, 0.16, 0.95)
						a:SetBackdropBorderColor(0.58, 0.45, 0.98, 1)
					end
					a.text = a:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
					a.text:SetPoint("CENTER", a, "CENTER", 0, 0)
					a:RegisterForClicks("LeftButtonUp", "RightButtonUp")
					a:SetScript("OnClick", function(self, button) if self.fn then self.fn(button, self) end end)
					r.actions[k] = a
				end
				a.text:SetText(spec[1])
				a.fn = spec[2]
				a:ClearAllPoints()
				a:SetPoint("RIGHT", r, "RIGHT", rightEdge, 0)
				a:Show()
				rightEdge = rightEdge - 64
			end
			if s.tag then
				r.tag.text:SetText(s.tag[1])
				r.tag:SetWidth((tonumber(r.tag.text:GetStringWidth()) or 60) + 14)
				if r.tag.SetBackdropColor then
					r.tag:SetBackdropColor(0.1, 0.06, 0.06, 0.95)
					r.tag:SetBackdropBorderColor(s.tag[2] or 1, s.tag[3] or 0.6, s.tag[4] or 0.2, 1)
				end
				r.tag.text:SetTextColor(s.tag[2] or 1, s.tag[3] or 0.6, s.tag[4] or 0.2)
				r.tag:ClearAllPoints()
				r.tag:SetPoint("RIGHT", r, "RIGHT", rightEdge, 0)
				r.tag:Show()
				rightEdge = rightEdge - (tonumber(r.tag:GetWidth()) or 60) - 6
			end
			r.right:SetPoint("RIGHT", r, "RIGHT", rightEdge, 0)
			-- The second line stops short of the row's buttons and tags (seen in game: it ran under Go).
			if s.sub then r.sub:SetWidth(math.max(40, w - lx - 2 + rightEdge - 8)) end
			r.right:SetText(s.right or "")
			r.left:SetPoint("RIGHT", r.right, "LEFT", -8, 0)
			r.left:SetText(s.left or "")
			y = y - h - 4
		end
		r:Show()
		f.drawn[#f.drawn + 1] = { kind = s.kind, text = s.text or s.left, right = s.right, tag = s.tag and s.tag[1], quest = s.quest, sub = s.sub }
	end
	for i = #specs + 1, #f.rows do f.rows[i]:Hide() end
	f.content:SetHeight(math.max(10, -y))
	if not keepScroll then f.scroll:SetVerticalScroll(0) end
end

---------------------------------------------------------------------------
-- The tabs' contents (each returns row specs)
---------------------------------------------------------------------------

local Tabs = {}
P.Tabs = Tabs

-- Quests (features.md §3.1), re-read on every quest-log change, level-up and zone change:
--   Ready to turn in            nearest first
--   Do now: <zone or dungeon>   at your level, by the quest log's own headers (as the log and
--                               Questie group them): the one you're in first, then the nearest;
--                               nearest first inside (a map marker isn't "here": dungeon quests
--                               have none outside, seen in game)
--   Group                       elite or a suggested group
--   Later                       orange or red for your level, with the gap
--   Skip?                       grey: little XP left
-- Each row: the level in its difficulty colour, the title, what's left on a second line, the
-- direction and distance when the game knows the spot, Go (the game's own map pin and arrow, on
-- click) and the quest's Spellmind mark (Break it down).
P.FAR = 1e9
function Tabs.quests()
	local q = Part("quests")
	local you = ns.State.Whole(ns.Try(UnitLevel, "player")) or 1
	local groups = { ready = {}, group = {}, later = {}, grey = {} }
	local now, byHeader = {}, {} -- the Do now headers in log order, and their rows
	local zone, sub = ns.Try(GetRealZoneText), ns.Try(GetSubZoneText)
	for _, it in ipairs(type(q.list) == "table" and q.list or {}) do
		local info = ns.Quests.Read(it.id)
		if info then
			local level = info.level or it.level or 0
			local c = ns.Try(GetQuestDifficultyColor, level)
			local color = type(c) == "table" and Hex(c.r, c.g, c.b) or "|cffffffff"
			local plus = (info.elite or info.group) and "+" or ""
			local dir = ns.Quests.Direction(info.where)
			local where
			if info.dist then where = (dir and (dir .. " · ") or "") .. info.dist .. " yd" end
			-- The second line: ready, or what's left, with the quest's XP reward.
			local xp = info.rewards and info.rewards.xp
			local xpText = xp and ("|cffb48cff" .. ns.Quests.Num(xp) .. " XP|r") or nil
			local sub
			if info.complete then sub = "|cff40c040Ready to turn in|r" .. (xpText and ("  " .. xpText) or "")
			else
				local left = ns.Quests.Left(info)
				sub = (xpText and (xpText .. (left and "  " or "")) or "") .. (left and ("|cffbbbbbb" .. left .. "|r") or "")
				if sub == "" then sub = nil end
			end
			local tag
			if info.elite then tag = { "Elite", 1, 0.3, 0.3 }
			elseif info.tagName then tag = { info.tagName, 0.45, 0.65, 1 }
			elseif info.group then tag = { "Group " .. info.group, 1, 0.6, 0.2 } end
			local dungeon = info.tagName == "Dungeon" or info.tagName == "Raid"
			local gap = level - you
			local right = where
			if not right and gap >= 3 and not info.complete then right = "|cffff8040+" .. gap .. " levels|r" end
			local id = it.id
			local row = { kind = "item", left = color .. "[" .. level .. plus .. "]|r " .. ns.Escape(info.title or it.title or "?"),
				sub = sub, right = right, tag = tag, quest = id, dist = info.dist or P.FAR, order = info.logIndex or 999, xp = xp or 0,
				actions = { { "Go", function() P.Go(id) end } } }
			-- A group, elite or dungeon quest: LFG puts a ready message in the chat box.
			if not info.complete and (info.elite or info.group or dungeon) then
				table.insert(row.actions, 1, { "LFG", function(button, b) P.LFG(id, button, b) end })
			end
			if info.complete then groups.ready[#groups.ready + 1] = row
			elseif info.diff == "Trivial" or info.trivial then groups.grey[#groups.grey + 1] = row
			elseif (info.elite or info.group) and not dungeon then groups.group[#groups.group + 1] = row
			elseif info.diff == "VeryDifficult" or info.diff == "Impossible" then groups.later[#groups.later + 1] = row
			else
				local h = info.header or "Other"
				if not byHeader[h] then
					byHeader[h] = { title = h, rows = {}, near = P.FAR, order = #now + 1,
						here = (type(zone) == "string" and h == zone) or (type(sub) == "string" and h == sub) }
					now[#now + 1] = byHeader[h]
				end
				local g = byHeader[h]
				g.rows[#g.rows + 1] = row
				if row.dist < g.near then g.near = row.dist end
			end
		end
	end
	local function near(a, b) if a.dist ~= b.dist then return a.dist < b.dist end return a.order < b.order end
	table.sort(groups.ready, near)
	for _, g in ipairs(now) do table.sort(g.rows, near) end
	-- Where you are first, then the nearest group, then the log's order.
	table.sort(now, function(a, b)
		if a.here ~= b.here then return a.here end
		if a.near ~= b.near then return a.near < b.near end
		return a.order < b.order
	end)
	local out = {}
	local function Section(title, rows)
		if #rows == 0 then return end
		out[#out + 1] = { kind = "head", text = title }
		for _, r in ipairs(rows) do out[#out + 1] = r end
	end
	Section("Ready to turn in", groups.ready)
	-- What turning them all in does for the level.
	local total = 0
	for _, r in ipairs(groups.ready) do total = total + (r.xp or 0) end
	local line = #groups.ready > 0 and ns.Quests.XpLine(total) or nil
	if line then table.insert(out, 2, { kind = "text", text = line }) end
	for _, g in ipairs(now) do Section("Do now: " .. ns.Escape(g.title), g.rows) end
	Section("Group", groups.group)
	Section("Later", groups.later)
	Section("Skip? Little XP left", groups.grey)
	if #out == 0 then out[1] = { kind = "text", text = "Your quest log is empty. Ask what's worth picking up nearby." } end
	return out
end

-- LFG on a quest row: the message in the game's chat box, to edit and send with Enter.
-- Every click asks where it goes: the menu of the chat box's current channel, the channels the
-- player is in, Say, Party and Guild (the player preferred choosing each time to a kept pick).
function P.LFG(id, button, anchor)
	P.LFGMenu(id, anchor)
	return nil
end

function P.LFGTo(id, slash)
	-- id: a quest (its dungeon or title), or a dungeon by name (the Dungeons tab).
	local text = type(id) == "string" and ns.Quests.LFGFor(id) or ns.Quests.LFGText(id)
	if text and ns.Quests.PutInChat(text, slash) then return text end
	if text then ns.Chat.System("Your LFG line: " .. ns.Escape(text)) end
	return text
end

-- The menu: one row per chat target; a pick puts the line in the chat box at once.
function P.LFGMenu(id, anchor)
	local f = panel or P.Build()
	local m = f.lfgMenu
	if not m then
		m = CreateFrame("Frame", "SpellmindLFGMenu", f, "BackdropTemplate")
		m:SetFrameStrata("FULLSCREEN_DIALOG")
		if m.SetBackdrop then
			m:SetBackdrop(BACKDROP)
			m:SetBackdropColor(0.05, 0.04, 0.1, 0.98)
			m:SetBackdropBorderColor(0.58, 0.45, 0.98, 1)
		end
		m.title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		m.title:SetPoint("TOPLEFT", m, "TOPLEFT", 10, -8)
		m.title:SetText("Post your LFG line in:")
		m.rows = {}
		f.lfgMenu = m
	end
	for _, r in ipairs(m.rows) do r:Hide() end
	local targets = ns.Quests.ChatTargets()
	local y = -24
	for i, t in ipairs(targets) do
		local r = m.rows[i]
		if not r then
			r = CreateFrame("Button", nil, m)
			r:SetSize(176, 18)
			r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			r.text:SetPoint("LEFT", r, "LEFT", 6, 0)
			r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
			m.rows[i] = r
		end
		r.text:SetText(ns.Escape(t.label))
		r.slash = t.slash
		r:SetScript("OnClick", function(self)
			m:Hide()
			P.LFGTo(id, self.slash)
		end)
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", m, "TOPLEFT", 6, y)
		r:Show()
		y = y - 20
	end
	m:SetSize(190, -y + 6)
	m:ClearAllPoints()
	if anchor then m:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2) else m:SetPoint("CENTER", f, "CENTER", 0, 0) end
	m:Show()
	return m
end

-- Go on a quest row: the game's pin and arrow, and a line saying which.
function P.Go(id)
	local did = ns.Quests.Go(id)
	local q = ns.Quests.Read(id)
	local title = q and q.title or "the quest"
	if did == "pin" then
		ns.Chat.System("Map pin set for " .. ns.Escape(title) .. ": follow the arrow.")
	elseif did == "track" then
		ns.Chat.System("Tracking " .. ns.Escape(title) .. ": the game's arrow points where it knows to.")
	else
		ns.Chat.System("The game doesn't know where " .. ns.Escape(title) .. " is on this map. Break it down asks Spellmind.")
	end
	return did
end

-- Gear: what's worn, what's in the bags (wearables with the tooltip line's verdict, then the rest), empty slots.
-- The question behind "Find my next upgrades": the weak slots named, so the AI looks where it counts.
function P.UpgradeQuestion()
	local weak = ns.Gear and ns.Gear.WeakSlots() or {}
	local names = {}
	for i, w in ipairs(weak) do
		if i > 6 then break end
		names[#names + 1] = w.name .. " (" .. w.why .. ")"
	end
	return "Find my next realistic gear upgrades" .. (#names > 0 and (", starting with my weakest slots: " .. table.concat(names, "; ")) or "")
		.. ". For each, name one item and exactly how to get it now or soon: a quest near me or in my log, a dungeon at my level (which boss), a vendor, something I can craft with my professions, or the auction house. Skip anything my class can't use. Search the web for item sources and cite them."
end

-- Dungeons (docs/milestone-13.md): the one you're in, the ones your quest log has quests for, and the
-- ones at your level that the game's LFG tool lists. Each with Brief (the AI's briefing, in the card
-- beside the window) and LFG; a quest row has Go and its Break it down mark.
function Tabs.dungeons()
	local DG = ns.Dungeons
	local out = {}
	local here = DG.Here()
	local log = DG.FromLog()
	local shown = {}
	P.openDungeons = P.openDungeons or {}
	local redraw = function() if panel and panel:IsShown() and P.tab == "dungeons" then P.Show("dungeons", true) end end
	local function brief(name)
		return { "Brief", function() P.Ask("Brief me: " .. name, DG.Briefing(name)) end }
	end
	local function lfg(name)
		return { "LFG", function(_, btn) P.LFGMenu(name, btn) end }
	end
	-- The quests still to pick up (QuestieDB's list): who gives each and where, or what opens it.
	local function pickups(qs)
		for _, q in ipairs(qs and qs.pickup or {}) do
			local from = q.from and ("from " .. ns.Escape(q.from)) or "giver unknown"
			-- What it waits on: the step in your log, or the chain's first step (listed above, to pick up).
			local wait = ""
			if q.after and q.afterLog then wait = "|cffff6060after " .. ns.Escape(q.after) .. " (in your log)|r · "
			elseif q.after then wait = "|cffff6060after " .. ns.Escape(q.after) .. " (pick it up first, above)|r · "
			elseif q.at then wait = "|cffff6060at level " .. q.at .. "|r · " end
			local opens = ""
			if q.opens and #q.opens > 0 then opens = " · leads to " .. ns.Escape(table.concat(q.opens, ", ")) end
			-- A chain's first step can share its name with a later one (The Defias Brotherhood).
			local label = q.name
			if q.first then
				for _, o in ipairs(q.opens or {}) do if o == q.name then label = q.name .. " (first step)" end end
			end
			-- Ready to take: "Pick up" in gold leads the line (a label, not a button: seen in game, a tag
			-- read as one), and Go pins the giver on the map.
			local ready = not q.after and not q.at
			local actions
			if ready and q.spot then
				local spot, giver = q.spot, q.from
				actions = { { "Go", function()
					if ns.Dungeons.Go(spot) then
						ns.Chat.System("Map pin set for " .. ns.Escape(spot.name or giver or "the quest giver") .. ": follow the arrow.")
					else
						ns.Chat.System("The game can't pin " .. ns.Escape(giver or "that spot") .. " on the map.")
					end
				end } }
			end
			out[#out + 1] = { kind = "item", indent = true, left = ns.Escape(label), right = q.level and ("level " .. q.level) or "",
				sub = (ready and "|cffffd100Pick up|r · " or wait) .. "|cff888888" .. from .. opens .. "|r", actions = actions }
		end
	end
	-- The status line: QuestieDB's count when it's there (while its first read runs, "reading…").
	local function status(name, fallback)
		if not DG.HasDB() then return fallback end
		local qs = DG.Quests(name, redraw)
		if not qs then return DG.index and fallback or ((fallback and (fallback .. " · ") or "") .. "reading quests…"), nil end
		local s = DG.Summary(qs)
		return (fallback and (fallback .. " · ") or "") .. s, qs
	end
	if here then
		out[#out + 1] = { kind = "head", text = "You're in " .. ns.Escape(here.name) }
		local line, qs = status(here.name, here.diff and ns.Escape(here.diff) or nil)
		out[#out + 1] = { kind = "item", left = ns.Escape(here.name), sub = line and ("|cff888888" .. line .. "|r") or nil, actions = { brief(here.name) } }
		for _, d in ipairs(log) do
			if DG.Norm(d.name) == DG.Norm(here.name) then
				for _, q in ipairs(d.quests) do
					out[#out + 1] = { kind = "item", indent = true, quest = q.id, left = ns.Escape(q.title or "?"),
						right = q.complete and "|cff19ff19ready|r" or (q.level and ("level " .. q.level) or "") }
				end
			end
		end
		pickups(qs)
		shown[DG.Norm(here.name)] = true
	end
	out[#out + 1] = { kind = "head", text = "Your quests are for" }
	local any = false
	for _, d in ipairs(log) do
		if not shown[DG.Norm(d.name)] then
			any = true
			local name = d.name
			local bits = {}
			local range = DG.Range(d.low, d.high)
			if range then bits[#bits + 1] = range end
			if d.ready > 0 then bits[#bits + 1] = "|cff19ff19" .. d.ready .. " ready to turn in|r" end
			-- Without QuestieDB's count (which has them), how many are in the log.
			if not DG.HasDB() then table.insert(bits, 1, #d.quests .. " in your log") end
			local line, qs = status(name, #bits > 0 and table.concat(bits, " · ") or nil)
			out[#out + 1] = { kind = "item", left = ns.Escape(name), sub = "|cff888888" .. line .. "|r",
				tag = d.raid and { "Raid", 1, 0.5, 0.2 } or nil, actions = { lfg(name), brief(name) } }
			for _, q in ipairs(d.quests) do
				out[#out + 1] = { kind = "item", indent = true, quest = q.id,
					left = ns.Escape(q.title or "?"), right = q.complete and "|cff19ff19ready|r" or (q.level and ("level " .. q.level) or ""),
					actions = { { "Go", function() P.Go(q.id) end } } }
			end
			pickups(qs)
			shown[DG.Norm(name)] = true
		end
	end
	if not any then out[#out + 1] = { kind = "text", text = "No dungeon quests in your log. Brief on a dungeon below, or ask which one fits." } end
	local near = {}
	for _, d in ipairs(DG.AtLevel()) do if not shown[DG.Norm(d.name)] then near[#near + 1] = d end end
	if #near > 0 then
		out[#out + 1] = { kind = "head", text = "At your level" }
		for _, d in ipairs(near) do
			local name = d.name
			local line, qs = status(name, nil)
			local open = P.openDungeons[DG.Norm(name)]
			local actions = { lfg(name), brief(name) }
			-- Quests to pick up: a click lists them under the row (and hides them again).
			if qs and #qs.pickup > 0 then
				table.insert(actions, 1, { open and "Hide" or "Quests", function()
					P.openDungeons[DG.Norm(name)] = not open or nil
					P.Show("dungeons", true)
				end })
			end
			out[#out + 1] = { kind = "item", left = ns.Escape(name), right = DG.Range(d.low, d.high) or "",
				sub = line and ("|cff888888" .. line .. "|r") or nil, actions = actions }
			if open then pickups(qs) end
		end
	end
	if not DG.HasDB() then
		out[#out + 1] = { kind = "text", text = "|cff888888With the QuestieDB addon installed, each dungeon also lists the quests you haven't picked up.|r" }
	end
	return out
end

-- "Brief my next one": the dungeon you're in, else the first in your log, else which fits.
function P.NextDungeonQuestion()
	local here = ns.Dungeons.Here()
	if here then return ns.Dungeons.Briefing(here.name) end
	local log = ns.Dungeons.FromLog()
	if log[1] then return ns.Dungeons.Briefing(log[1].name) end
	return ns.Dungeons.WhichQuestion()
end

function Tabs.gear()
	local out = {}
	-- Next upgrades (milestone 9): what's already within reach, then the weakest slots.
	local cands = ns.Gear and ns.Gear.Candidates() or {}
	local weak = ns.Gear and ns.Gear.WeakSlots() or {}
	-- Within reach: items you have or a quest in your log gives, that beat what you wear.
	out[#out + 1] = { kind = "head", text = "Upgrades within reach" }
	local bySlot = {}
	for _, c in ipairs(cands) do
		bySlot[c.slot] = true
		out[#out + 1] = { kind = "item", icon = c.icon, left = (P.SLOT_NAMES[c.slot] or "?") .. " · " .. (QUALITY[c.q or 1] or "") .. ns.Escape(c.name) .. "|r",
			sub = "|cffbbbbbb" .. (c.from == "bags" and "In your bags" or ("Reward of " .. ns.Escape(c.from))) .. ": |r" .. (c.reason or ""),
			tag = { "upgrade", 0.1, 1, 0.1 },
			actions = c.quest and { { "Go", function() P.Go(c.quest) end } } or nil }
	end
	if #cands == 0 then
		out[#out + 1] = { kind = "text", text = "|cff888888Nothing in your bags or your quests' rewards beats what you wear. Find my next upgrades asks where to look.|r" }
	end
	-- The weakest slots, the ones to look for first.
	local shown = 0
	for _, w in ipairs(weak) do
		if not bySlot[w.slot] and shown < 6 then
			if shown == 0 then out[#out + 1] = { kind = "head", text = "Weakest slots" } end
			shown = shown + 1
			out[#out + 1] = { kind = "item", left = w.name .. (w.item and (" · " .. ns.Escape(w.item)) or ""),
				right = "|cffff8040" .. w.why .. "|r" }
		end
	end
	out[#out + 1] = { kind = "head", text = "Your gear (worn)" }
	local gear = Part("gear")
	local worn = {}
	for _, it in ipairs(type(gear.items) == "table" and gear.items or {}) do worn[#worn + 1] = it end
	table.sort(worn, function(a, b) return (a.slot or 0) < (b.slot or 0) end)
	for _, it in ipairs(worn) do
		local bits = {}
		if it.ilvl then bits[#bits + 1] = "ilvl " .. it.ilvl end
		if type(it.st) == "table" and it.st.dps then bits[#bits + 1] = string.format("%.1f dps", it.st.dps) end
		local tag
		if type(it.dur) == "table" and (tonumber(it.dur[2]) or 0) > 0 then
			local pct = math.floor(it.dur[1] / it.dur[2] * 100 + 0.5)
			if pct < 25 then tag = { pct .. "% durability", 1, 0.25, 0.25 } elseif pct < 75 then tag = { pct .. "% durability", 1, 0.6, 0.2 } end
		end
		out[#out + 1] = { kind = "item", icon = ns.Try(GetInventoryItemTexture, "player", it.slot),
			left = (P.SLOT_NAMES[it.slot] or "?") .. " · " .. (QUALITY[it.q or 1] or "") .. ns.Escape(it.name or "?") .. "|r",
			right = table.concat(bits, " · "), tag = tag }
	end
	local bags = Part("bags")
	local items = type(bags.items) == "table" and bags.items or {}
	if #items > 0 then
		out[#out + 1] = { kind = "head", text = "In your bags" .. (bags.free and bags.slots and (" (" .. bags.free .. " of " .. bags.slots .. " free)") or "") }
		local n = 0
		for _, it in ipairs(items) do
			if n >= P.BAG_ROWS then break end
			n = n + 1
			local info = { pcall(C_Item.GetItemInfo, it.id) }
			local link, icon, sell = info[1] and info[3], info[1] and info[11], info[1] and info[12]
			local tag, right
			if it.equip and type(link) == "string" and ns.Tooltip then
				local data = C_TooltipInfo and type(C_TooltipInfo.GetHyperlink) == "function" and select(2, pcall(C_TooltipInfo.GetHyperlink, link)) or nil
				local reds = ns.Tooltip.RedTexts(type(data) == "table" and data or nil)
				if #reds > 0 then
					local why = ns.Tooltip.Why(reds, tonumber(info[13]), it.sub)
					tag = { (why:gsub("^no (.-) skill yet.*$", "needs %1 skill")), 1, 0.3, 0.3 }
				else
					local ok, line = pcall(ns.Tooltip.Line, link, data)
					-- Just the differences: the row names the item, and "vs your …" crowded its name out (seen in game).
					if ok and type(line) == "string" then right = (line:gsub("^|cff9d7dffSpellmind:|r ", ""):gsub(" vs your .*$", "")) end
				end
			elseif type(link) == "string" and ns.Tooltip then
				-- The tooltip's own advice, so the two never disagree (seen in game: "sell: 2s 50c" here
				-- read as a recommendation the tooltip didn't make); otherwise just its vendor value.
				local data = C_TooltipInfo and type(C_TooltipInfo.GetHyperlink) == "function" and select(2, pcall(C_TooltipInfo.GetHyperlink, link)) or nil
				local ok, advice = pcall(ns.Tooltip.SellLine, link, data)
				if not (ok and advice) then ok, advice = pcall(ns.Tooltip.ProfLine, link, data) end
				if ok and type(advice) == "string" then
					right = advice:gsub("^|cff9d7dffSpellmind:|r ", "")
				elseif type(sell) == "number" and sell > 0 then
					right = "|cff888888vendor " .. Money(sell * (it.n or 1)) .. "|r"
				end
			elseif type(sell) == "number" and sell > 0 then
				right = "|cff888888vendor " .. Money(sell * (it.n or 1)) .. "|r"
			end
			out[#out + 1] = { kind = "item", icon = icon, left = (QUALITY[it.q or 1] or "") .. ns.Escape(it.name or "?") .. "|r" .. ((it.n or 1) > 1 and (" x" .. it.n) or ""), right = right, tag = tag }
		end
		local more = (#items - n) + (tonumber(bags.more) or 0)
		if more > 0 then out[#out + 1] = { kind = "text", text = "|cff888888and " .. more .. " more|r" } end
		if type(bags.junk) == "table" and (bags.junk.n or 0) > 0 then
			out[#out + 1] = { kind = "text", text = "Grey junk: " .. bags.junk.n .. " item" .. (bags.junk.n > 1 and "s" or "") .. ", worth " .. Money(bags.junk.copper) }
		end
	end
	local empty = {}
	local seen = {}
	for _, slot in ipairs(type(gear.empty) == "table" and gear.empty or {}) do
		local name = P.SLOT_NAMES[slot]
		if name and slot ~= 4 and slot ~= 19 and not seen[name] then seen[name] = true; empty[#empty + 1] = name end
	end
	if #empty > 0 then
		out[#out + 1] = { kind = "head", text = "Empty slots" }
		out[#out + 1] = { kind = "text", text = table.concat(empty, ", ") }
	end
	return out
end

function Tabs.talents()
	local t = Part("talents")
	local out = { { kind = "head", text = "Talents" } }
	out[#out + 1] = { kind = "text", text = string.format("%d spent, %s", tonumber(t.spent) or 0,
		(tonumber(t.unspent) or 0) > 0 and ("|cff19ff19" .. t.unspent .. " to spend|r") or "none to spend") }
	for _, n in ipairs(type(t.nodes) == "table" and t.nodes or {}) do
		out[#out + 1] = { kind = "item", left = ns.Escape(n.name or "?"), right = (n.r or 0) .. " / " .. (n.max or 0) }
	end
	return out
end

function Tabs.spells()
	local s = Part("spells")
	local you = ns.State.Whole(ns.Try(UnitLevel, "player")) or 1
	-- The class trainer's kept list (Trainer.lua): Forever's spellbook shows nothing coming.
	local ok, p = false, nil
	if ns.Trainer then ok, p = pcall(ns.Trainer.Plan) end
	if ok and p then
		local M = ns.GearUI and ns.GearUI.Money or tostring
		local out = {}
		if #p.due > 0 then
			out[#out + 1] = { kind = "head", text = "Train now: " .. M(p.total) }
			for _, t in ipairs(p.due) do
				out[#out + 1] = { kind = "item", left = ns.Escape(ns.Trainer.Label(t)), right = M(t.cost or 0), tag = { "train now", 0.1, 1, 0.1 } }
			end
			local money = tonumber((ns.Try(GetMoney))) or 0
			if money < p.total then out[#out + 1] = { kind = "text", text = "|cffff6060You have " .. M(money) .. ": ask which come first.|r" } end
		else
			out[#out + 1] = { kind = "head", text = "Train now" }
			out[#out + 1] = { kind = "text", text = "Nothing new at your level." }
		end
		out[#out + 1] = { kind = "head", text = "Coming next" }
		for _, t in ipairs(p.soon) do
			out[#out + 1] = { kind = "item", left = ns.Escape(ns.Trainer.Label(t)), right = "level " .. (t.level or "?") }
		end
		if #p.soon == 0 then out[#out + 1] = { kind = "text", text = "Nothing more listed by your trainer." } end
		out[#out + 1] = { kind = "text", text = "|cff888888From your trainer's list (" .. (ns.Window and ns.Window.Ago and ns.Window.Ago(p.at) or "kept") .. "). Visit again after you level to refresh it.|r" }
		return out
	end
	local out = { { kind = "head", text = "Coming next" } }
	local any = false
	for _, n in ipairs(type(s.next) == "table" and s.next or {}) do
		any = true
		local ready = (n.level or 99) <= you
		out[#out + 1] = { kind = "item", left = ns.Escape(n.name or "?") .. (n.rank and (" (rank " .. n.rank .. ")") or ""),
			right = "level " .. (n.level or "?"), tag = ready and { "train now", 0.1, 1, 0.1 } or nil }
	end
	if not any then out[#out + 1] = { kind = "text", text = "Nothing new in your spellbook yet. Open your class trainer once and Spellmind keeps its list." } end
	return out
end

function Tabs.professions()
	local s = Part("skills")
	local out = { { kind = "head", text = "Professions" } }
	for _, p in ipairs(type(s.prof) == "table" and s.prof or {}) do
		local near = (p.max or 0) > 0 and (p.rank or 0) >= (p.max or 0) - 5
		out[#out + 1] = { kind = "item", left = ns.Escape(p.name or "?"), right = (p.rank or 0) .. " / " .. (p.max or 0),
			tag = near and { "train the next rank", 1, 0.82, 0 } or nil }
	end
	if #out == 1 then out[2] = { kind = "text", text = "No professions yet." } end
	out[#out + 1] = { kind = "head", text = "Weapon skills" }
	for _, p in ipairs(type(s.weapon) == "table" and s.weapon or {}) do
		out[#out + 1] = { kind = "item", left = ns.Escape(p.name or "?"), right = (p.rank or 0) .. " / " .. (p.max or 0) }
	end
	return out
end

-- Nudges: every one waiting (faded or behind the toast), each with Ask and Dismiss.
function Tabs.nudges()
	local out = { { kind = "head", text = "Waiting" } }
	local list = ns.Nudges and ns.Nudges.List() or {}
	for _, n in ipairs(list) do
		local kind = n.kind
		out[#out + 1] = { kind = "item", icon = n.icon, left = n.title .. (n.text and n.text ~= "" and ("  |cff888888" .. n.text .. "|r") or ""),
			tag = n.asked and { "asked", 0.4, 0.85, 0.4 } or nil,
			actions = {
				{ "Ask", function() ns.Nudges.AskKind(kind, panel) end },
				{ "Dismiss", function() ns.Nudges.DoneKind(kind) end },
			} }
	end
	if #list == 0 then out[#out + 1] = { kind = "text", text = "Nothing waiting. Nudges show by the minimap when something comes up." } end
	return out
end

function Tabs.gold()
	local c = Part("char")
	local b = Part("bags")
	local out = { { kind = "head", text = "Gold" } }
	out[#out + 1] = { kind = "item", left = "On you", right = Money(c.money) }
	if type(b.junk) == "table" then out[#out + 1] = { kind = "item", left = "Grey junk to sell", right = Money(b.junk.copper) .. " (" .. (b.junk.n or 0) .. ")" } end
	if b.slots then
		local low = (b.free or 0) <= 4
		out[#out + 1] = { kind = "item", left = "Bag space", right = (b.free or 0) .. " of " .. b.slots .. " free", tag = low and { "nearly full", 1, 0.6, 0.2 } or nil }
	end
	return out
end

-- Settings: every switch in one place (Settings.lua), each row's button showing On or Off (or its
-- pick) and flipping it. A setting under a main switch that's off is greyed.
function Tabs.settings()
	local ST = ns.Settings
	local out = {}
	for _, sec in ipairs(ST.List()) do
		out[#out + 1] = { kind = "head", text = sec.section }
		for _, r in ipairs(sec.rows) do
			local id = r.id
			local dim = r.dim and r.dim()
			out[#out + 1] = { kind = "item", indent = r.indent,
				left = dim and ("|cff888888" .. r.label .. "|r") or r.label,
				sub = r.sub and ("|cff888888" .. r.sub .. "|r") or nil,
				actions = { { ST.Label(r), function() ST.Flip(id); P.Show("settings", true) end } } }
		end
		if sec.section == "Nudges" then
			out[#out + 1] = { kind = "item", indent = true, left = "Dismissed nudges", sub = "|cff888888Show the ones you dismissed again, if they still apply.|r",
				actions = { { "Reset", function()
					local n = ns.Nudges.Reset()
					P.Show("settings", true)
					ns.Marks.ShowText(panel, "Nudges", n > 0 and (n .. " nudge" .. (n > 1 and "s" or "") .. " to show again: see the Nudges tab.") or "Nothing to nudge about right now.", { owner = panel })
				end } } }
		elseif sec.section == "Game data the AI gets" then
			out[#out + 1] = { kind = "item", indent = true, left = "What the app has now", sub = "|cff888888Each part's size, and whether it arrived.|r",
				actions = { { "Show", function()
					ns.Marks.ShowText(panel, "Game data", table.concat(ns.State.Report(), "\n"), { owner = panel })
				end } } }
		end
	end
	return out
end

---------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------

function P.Who()
	local level = ns.State.Whole(ns.Try(UnitLevel, "player"))
	local race = ns.Try(UnitRace, "player")
	local class = ns.Try(UnitClass, "player")
	local bits = {}
	if level then bits[#bits + 1] = "Level " .. level end
	local rc = ((type(race) == "string" and race or "") .. " " .. (type(class) == "string" and class or "")):gsub("^%s+", ""):gsub("%s+$", "")
	if rc ~= "" then bits[#bits + 1] = ns.Escape(rc) end
	return table.concat(bits, " · ")
end

local function TabButton(f, i, tab)
	local b = CreateFrame("Button", nil, f, "BackdropTemplate")
	b:SetSize(P.RAIL_W - 16, 28)
	b:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -58 - (i - 1) * 31)
	if b.SetBackdrop then b:SetBackdrop(BACKDROP) end
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetSize(20, 20)
	b.icon:SetPoint("LEFT", b, "LEFT", 6, 0)
	b.icon:SetTexture(tab.icon)
	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	b.text:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
	b.text:SetText(tab.name)
	b.id = tab.id
	b:SetScript("OnClick", function(self) P.Show(self.id) end)
	return b
end

local function AskButton(f)
	local b = CreateFrame("Button", nil, f, "BackdropTemplate")
	b:SetHeight(24)
	if b.SetBackdrop then
		b:SetBackdrop(BACKDROP)
		b:SetBackdropColor(0.08, 0.06, 0.16, 0.95)
		b:SetBackdropBorderColor(0.58, 0.45, 0.98, 1)
	end
	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
	b:SetScript("OnEnter", function(self) if self.SetBackdropBorderColor then self:SetBackdropBorderColor(0.85, 0.68, 0.25, 1) end end)
	b:SetScript("OnLeave", function(self) if self.SetBackdropBorderColor then self:SetBackdropBorderColor(0.58, 0.45, 0.98, 1) end end)
	b:SetScript("OnClick", function(self)
		if not self.ask then return end
		local q = self.ask[2]
		if q == "GEAR_UPGRADES" then q = P.UpgradeQuestion()
		elseif q == "DUNGEON_WHICH" then q = ns.Dungeons.WhichQuestion()
		elseif q == "DUNGEON_NEXT" then q = P.NextDungeonQuestion() end
		P.Ask(self.ask[1], q)
	end)
	return b
end

-- The size kept for a mode: { w, h } within its bounds.
local function ModeSize(compact)
	local saved = Saved()
	if compact then
		return math.max(P.CMIN_W, math.min(P.MAX_W, tonumber(saved.cw) or P.CW)), math.max(P.CMIN_H, math.min(P.MAX_H, tonumber(saved.ch) or P.CH))
	end
	return math.max(P.MIN_W, math.min(P.MAX_W, tonumber(saved.w) or P.W)), math.max(P.MIN_H, math.min(P.MAX_H, tonumber(saved.h) or P.H))
end

local function KeepSize(f)
	local saved = Saved()
	if saved.folded then return end
	if saved.compact then saved.cw, saved.ch = f:GetWidth(), f:GetHeight()
	else saved.w, saved.h = f:GetWidth(), f:GetHeight() end
end

local function Bounds(f)
	if not f.SetResizeBounds then return end
	if Saved().compact then f:SetResizeBounds(P.CMIN_W, P.CMIN_H, P.MAX_W, P.MAX_H)
	else f:SetResizeBounds(P.MIN_W, P.MIN_H, P.MAX_W, P.MAX_H) end
end

function P.Build()
	if panel then return panel end
	local saved = Saved()
	-- The chat window's place (before the two were one window) is where it opens the first time.
	local ui = ns.db and type(ns.db.ui) == "table" and ns.db.ui or {}
	if not saved.point and ui.point then saved.point, saved.relPoint, saved.x, saved.y = ui.point, ui.relPoint, ui.x, ui.y end
	local f = CreateFrame("Frame", "SpellmindPanel", UIParent, "BackdropTemplate")
	-- Resizable (the grip at the bottom right), its size kept for each mode: quest rows carry a lot.
	f:SetSize(ModeSize(saved.compact))
	f:SetResizable(true)
	Bounds(f)
	if saved.point then f:SetPoint(saved.point, UIParent, saved.relPoint or saved.point, tonumber(saved.x) or 0, tonumber(saved.y) or 0)
	else f:SetPoint("CENTER", UIParent, "CENTER", -120, 40) end
	f:SetFrameStrata("DIALOG")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		saved.point, saved.relPoint, saved.x, saved.y = point, relPoint, x, y
	end)
	if f.SetBackdrop then
		f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
		f:SetBackdropColor(0.04, 0.03, 0.09, 0.94)
		f:SetBackdropBorderColor(0.62, 0.49, 1, 1)
	end
	-- A solid fill under it: the tooltip background is see-through even at full alpha (seen in game).
	ns.Window.Fill(f, 4, 0.035, 0.025, 0.08, 0.97)
	ns.Window.Corners(f)

	f.portrait = f:CreateTexture(nil, "ARTWORK")
	f.portrait:SetSize(36, 36)
	f.portrait:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -8)
	f.portrait:SetTexture(ns.Window.PORTRAIT)
	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 52, -11)
	f.title:SetText("Spellmind")
	f.who = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.who:SetPoint("TOPLEFT", f, "TOPLEFT", 52, -31)
	f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
	-- Fold (the header only) and compact (the chat alone), left of the close button.
	f.fold = ns.Window.SmallButton(f, 20)
	f.fold:SetPoint("RIGHT", f.close, "LEFT", -2, 0)
	f.fold:SetScript("OnClick", function() P.Fold(not Saved().folded) end)
	f.compact = ns.Window.SmallButton(f, 20)
	f.compact:SetPoint("RIGHT", f.fold, "LEFT", -4, 0)
	-- A hamburger: three gold bars (the tabs' menu), drawn, no texture file.
	f.compact.bars = {}
	for i = 1, 3 do
		local bar = f.compact:CreateTexture(nil, "OVERLAY")
		bar:SetColorTexture(0.85, 0.68, 0.25, 1)
		bar:SetSize(12, 2)
		bar:SetPoint("CENTER", f.compact, "CENTER", 0, (2 - i) * 4)
		f.compact.bars[i] = bar
	end
	f.compact:SetScript("OnClick", function() P.SetCompact(not Saved().compact) end)
	f.rule = f:CreateTexture(nil, "ARTWORK")
	f.rule:SetColorTexture(0.62, 0.49, 1, 0.35)
	f.rule:SetHeight(1)
	f.rule:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -50)
	f.rule:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -50)
	f.rail = f:CreateTexture(nil, "ARTWORK")
	f.rail:SetColorTexture(0.62, 0.49, 1, 0.35)
	f.rail:SetWidth(1)
	f.rail:SetPoint("TOPLEFT", f, "TOPLEFT", P.RAIL_W, -50)
	f.rail:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", P.RAIL_W, 8)

	f.tabs = {}
	for i, tab in ipairs(P.TABS) do f.tabs[i] = TabButton(f, i, tab) end

	f.scroll = CreateFrame("ScrollFrame", nil, f)
	f.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", P.RAIL_W + 12, -58)
	f.scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 48)
	f.content = CreateFrame("Frame", nil, f.scroll)
	f.content:SetSize(P.W - P.RAIL_W - 24, 10)
	f.scroll:SetScrollChild(f.content)
	f.scroll:EnableMouseWheel(true)
	f.scroll:SetScript("OnMouseWheel", function(self, delta)
		local range = tonumber(self:GetVerticalScrollRange()) or 0
		local y = (tonumber(self:GetVerticalScroll()) or 0) - delta * 40
		self:SetVerticalScroll(math.max(0, math.min(range, y)))
	end)
	f.rows = {}

	f.asks = { AskButton(f), AskButton(f) }
	P.PlaceAsks(f)

	f.grip = CreateFrame("Button", nil, f)
	f.grip:SetSize(16, 16)
	f.grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
	f.grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	f.grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	f.grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	f.grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
	f.grip:SetScript("OnMouseUp", function()
		f:StopMovingOrSizing()
		KeepSize(f)
		P.Show(P.tab)
	end)
	-- While sizing: the Ask buttons and the chat follow at once, the rows when it stops (or a moment after).
	f:SetScript("OnSizeChanged", function() P.PlaceAsks(f); P.PlaceChat(f); P.Soon() end)

	-- Live while open: the game's own events, at most one redraw a second.
	f:RegisterEvent("QUEST_LOG_UPDATE")
	f:RegisterEvent("QUEST_WATCH_UPDATE")
	f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	f:RegisterEvent("BAG_UPDATE_DELAYED")
	f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	f:RegisterEvent("PLAYER_LEVEL_UP")
	f:RegisterEvent("PLAYER_MONEY")
	f:RegisterEvent("SKILL_LINES_CHANGED")
	f:SetScript("OnEvent", function() P.Soon() end)

	-- The card beside the window, and the chat, close with it.
	f:HookScript("OnHide", function(self)
		if ns.Marks and ns.Marks.card and ns.Marks.card.owner == self then ns.Marks.card:Hide() end
		local chat = ns.Window.Get()
		if chat then chat:Hide() end
	end)
	if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "SpellmindPanel") end
	f:Hide()
	panel = f
	return f
end

function P.Get() return panel end

-- The rail's width now: none in compact mode.
function P.Left()
	return Saved().compact and 0 or P.RAIL_W
end

-- The content's width at the panel's size now.
function P.ContentWidth(f)
	return math.max(200, (tonumber(f:GetWidth()) or P.W) - P.Left() - 24)
end

-- The two Ask buttons, side by side across the content's width.
function P.PlaceAsks(f)
	local half = math.floor((P.ContentWidth(f) - 12) / 2)
	for i, b in ipairs(f.asks or {}) do
		b:SetWidth(half)
		b:ClearAllPoints()
		b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", P.Left() + 12 + (i - 1) * (half + 12), 14)
	end
end

-- The chat in the content area: right of the rail (or the whole width when compact), under the header.
function P.PlaceChat(f)
	local chat = ns.Window.Get()
	if not chat or not f then return end
	local x = P.Left() + 8
	chat:ClearAllPoints()
	chat:SetPoint("TOPLEFT", f, "TOPLEFT", x, -P.HEAD_H)
	chat:SetSize(math.max(ns.Window.MIN_W, (tonumber(f:GetWidth()) or P.W) - x - 8), math.max(120, (tonumber(f:GetHeight()) or P.H) - P.HEAD_H - 14))
end

function P.Soon()
	if not panel or not panel:IsShown() or P.pending then return end
	P.pending = true
	C_Timer.After(1, function()
		P.pending = nil
		if panel and panel:IsShown() and P.tab ~= "chat" then P.Show(P.tab) end
	end)
end

-- What shows for the mode, the tab and the fold: the rail and tabs (not compact), the chat (its tab)
-- or the rows and Ask buttons (the others); the header alone when folded.
local function Arrange(f)
	local saved = Saved()
	local folded, compact, chatTab = saved.folded and true or false, saved.compact and true or false, P.tab == "chat"
	f.rail:SetShown(not compact and not folded)
	for _, b in ipairs(f.tabs) do b:SetShown(not compact and not folded) end
	f.scroll:SetShown(not chatTab and not folded)
	for i, b in ipairs(f.asks) do b:SetShown(not chatTab and not folded and b.ask ~= nil) end
	f.grip:SetShown(not folded)
	f.who:SetShown(not chatTab)
	local chat = ns.Window.Get()
	if chat then chat:SetShown(chatTab and not folded) end
	f.fold.text:SetText(folded and "+" or "-")
	f.fold.tip = folded and "Unfold the window." or "Fold the window to its header."
	-- The hamburger's bars: gold with the tabs showing, grey without (compact).
	for _, bar in ipairs(f.compact.bars) do
		if compact then bar:SetColorTexture(0.6, 0.6, 0.6, 1) else bar:SetColorTexture(0.85, 0.68, 0.25, 1) end
	end
	f.compact.tip = compact and "Show the tabs again." or "Compact: the chat alone, small, for questing."
end

-- The window on a tab (the last one, by default), its rows read now. The Chat tab draws the chat;
-- another tab out of compact mode (it needs the rail).
function P.Show(id, keepScroll)
	local f = P.Build()
	local saved = Saved()
	id = id or saved.tab or "chat"
	if not Tabs[id] then id = "chat" end
	if id ~= "chat" and saved.compact then P.SetCompact(false, true) end
	P.tab, saved.tab = id, id
	if id ~= "chat" then saved.other = id end
	for _, b in ipairs(f.tabs) do
		local on = b.id == id
		if b.SetBackdropColor then
			b:SetBackdropColor(on and 0.32 or 0.06, on and 0.22 or 0.04, on and 0.62 or 0.12, on and 0.95 or 0.6)
			b:SetBackdropBorderColor(on and 0.62 or 0.3, on and 0.49 or 0.24, on and 1 or 0.5, 1)
		end
	end
	f.who:SetText(P.Who())
	P.CountNudges()
	if id == "chat" then
		ns.Window.Build()
		for _, b in ipairs(f.asks) do b.ask = nil end
	else
		f.content:SetWidth(P.ContentWidth(f))
		P.PlaceAsks(f)
		local ok, specs = pcall(Tabs[id])
		Draw(f, ok and specs or { { kind = "text", text = "|cffff6060This tab couldn't read your character just now.|r" } }, keepScroll)
		for i, b in ipairs(f.asks) do
			local a = P.ASKS[id] and P.ASKS[id][i]
			b.ask = a
			b.text:SetText(a and ("Ask: " .. a[1]) or "")
		end
	end
	if not f:IsShown() then f:Show() end
	Arrange(f)
	if id == "chat" then
		P.PlaceChat(f)
		ns.Window.Refresh()
		ns.Window.Layout(true)
	end
	return f
end

-- The Chat tab's draw (P.Show does it).
function Tabs.chat() return {} end

-- Compact on or off: each mode keeps its own size. Compact shows the Chat tab. quiet: P.Show is
-- already switching tabs.
function P.SetCompact(on, quiet)
	local f = P.Build()
	local saved = Saved()
	if (saved.compact and true or false) == (on and true or false) then return end
	KeepSize(f)
	saved.compact = on and true or nil
	Bounds(f)
	if not saved.folded then f:SetSize(ModeSize(saved.compact)) end
	P.PlaceAsks(f)
	if quiet then return end
	if on then P.Show("chat") else P.Show(P.tab) end
end

-- Folded: the header only (the tab and mode kept).
function P.Fold(on)
	local f = P.Build()
	local saved = Saved()
	if on and not saved.folded then
		KeepSize(f)
		saved.folded = true
		f:SetHeight(P.FOLD_H)
	elseif not on and saved.folded then
		saved.folded = nil
		f:SetSize(ModeSize(saved.compact))
	end
	Arrange(f)
	if not saved.folded then P.Show(P.tab) end
end

-- The Nudges tab's label with its count, and the tab redrawn when it's the one showing.
function P.CountNudges()
	local f = panel
	if not f then return end
	local n = ns.Nudges and #ns.Nudges.Waiting() or 0 -- still to see (asked ones stay listed, uncounted)
	for _, b in ipairs(f.tabs) do
		if b.id == "nudges" then b.text:SetText(n > 0 and ("Nudges |cffffd100(" .. n .. ")|r") or "Nudges") end
	end
end

function P.NudgesChanged()
	P.CountNudges()
	if panel and panel:IsShown() and P.tab == "nudges" then P.Show("nudges") end
end

-- The minimap button's right-click and /sm panel: the last tab other than Chat, or closed when it shows.
function P.Toggle()
	local f = P.Build()
	if f:IsShown() and P.tab ~= "chat" then f:Hide() else P.Show(Saved().other or "quests") end
end

-- Is the chat showing (the window open on its Chat tab)?
function P.ChatOpen()
	return panel ~= nil and panel:IsShown() and P.tab == "chat"
end

-- An Ask button: the question goes to the chat, its answer to the card beside the window.
function P.Ask(label, text)
	if not ns.Marks then return end
	return ns.Marks.Ask(panel, "Advisor: " .. ns.Escape(label), text)
end
