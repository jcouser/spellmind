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
P.MIN_W, P.MIN_H, P.MAX_W, P.MAX_H = 560, 430, 1100, 1000 -- the rail's eleven tabs fit
-- Compact: the chat alone.
P.CW, P.CH = 440, 460
P.CMIN_W, P.CMIN_H = 406, 366
P.HEAD_H = 54 -- the header, to the rule under it
P.FOLD_H = 52
P.RAIL_W = 150
P.ROW_H = 24
P.ROW_H2 = 38 -- a row with a second line
-- What each row button does, on hover (the review: nothing said before the click, and the AI ones
-- looked like the instant ones). The AI ones carry the owl's mark.
P.AI_ACTIONS = { Brief = true, Import = true, ["Re-import"] = true }
P.ACTION_TIPS = {
	Go = "Sets the game's map pin and arrow. Nothing else.",
	LFG = "Writes an LFG line in your chat box. You press Enter to send it.",
	Brief = "Asks your AI for a briefing: quests to pick up, bosses, loot, what to bring.",
	Quests = "Lists this dungeon's quests you haven't picked up.",
	Hide = "Hides the list again.",
	Import = "Your AI reads the guide's page and brings its build in.",
	["Re-import"] = "Your AI reads the guide's page again.",
	Change = "Paste a different guide's link.",
	["Set link"] = "Paste your leveling guide's link.",
	Reset = "Shows the nudges you dismissed again, if they still apply.",
	Show = "Shows what the app has of your game data now.",
	Ask = "Asks your AI about this.",
	Dismiss = "Hides it until something changes.",
	Open = "Opens the tab this is about.",
}
P.BAG_ROWS = 8
P.TABS = {
	{ id = "chat", name = "Chat", icon = "Interface\\AddOns\\Spellmind\\Media\\Portrait" },
	{ id = "quests", name = "Quests", icon = "Interface\\Icons\\INV_Letter_15" },
	{ id = "route", name = "Route", icon = "Interface\\Icons\\INV_Misc_Map_01" },
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
	quests = { { "Review my route", "ROUTE_REVIEW" }, { "What's worth skipping?", "Which of my quests are worth skipping or leaving for later, and why?" } },
	route = { { "Review my route", "ROUTE_REVIEW" }, { "Why this order?", "ROUTE_WHY" } },
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
	-- No zero parts ("1g", not "1g 0s 0c"), as the rest of Spellmind writes money (the review).
	if g > 0 then out[#out + 1] = "|cffffd100" .. g .. "g|r" end
	if s > 0 then out[#out + 1] = "|cffc7c7cf" .. s .. "s|r" end
	if c > 0 or #out == 0 then out[#out + 1] = "|cffeda55f" .. c .. "c|r" end
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
	-- A tag is coloured words, no border (the review: a bordered "Dungeon" beside LFG and Go read as a
	-- button).
	r.tag = CreateFrame("Frame", nil, r)
	r.tag:SetHeight(16)
	r.tag.text = r.tag:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	r.tag.text:SetPoint("CENTER", r.tag, "CENTER", 0, 0)
	r.rule = r:CreateTexture(nil, "ARTWORK")
	r.rule:SetColorTexture(0.62, 0.49, 1, 0.35)
	r.rule:SetHeight(1)
	r.rule:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
	r.rule:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
	-- An item's row: the game's tooltip for it on hover, with Spellmind's lines as anywhere else (the
	-- player, 2026-11-14: hovering the Gear tab showed nothing). Mouse only while the row has an item.
	r:SetScript("OnEnter", function(self)
		if not (self.link or self.invSlot) or not GameTooltip then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if self.invSlot then GameTooltip:SetInventoryItem("player", self.invSlot) else GameTooltip:SetHyperlink(self.link) end
		GameTooltip:Show()
	end)
	r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	return r
end

-- The rows laid out from a list of specs:
--   { kind = "head", text }                          a section title, gold, with a rule
--   { kind = "item", icon, left, right, tag = { text, r, g, b }, quest = id }   a row; quest: a Break it down mark
--   link = an item link, or invSlot = a worn slot: the item's tooltip on hover
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
		r.link = s.kind == "item" and type(s.link) == "string" and s.link or nil
		r.invSlot = s.kind == "item" and tonumber(s.invSlot) or nil
		r:EnableMouse(r.link ~= nil or r.invSlot ~= nil)
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
		elseif s.kind == "label" then
			-- A small heading inside a section ("To pick up", "Not yet"), set in like its rows.
			r:SetHeight(16)
			r.left:SetFontObject(GameFontNormalSmall)
			if r.left.SetWordWrap then r.left:SetWordWrap(false) end
			r.left:SetWidth(0)
			r.left:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 20, 1)
			r.left:SetText(s.text)
			y = y - 18
		elseif s.kind == "text" then
			-- Wrapped to the width, as tall as it needs (the review: hints and empty states ended in "…").
			r.left:SetFontObject(GameFontHighlightSmall)
			if r.left.SetWordWrap then r.left:SetWordWrap(true) end
			r.left:SetPoint("TOPLEFT", r, "TOPLEFT", 4, -3)
			r.left:SetWidth(w - 8)
			r.left:SetText(s.text)
			local th = math.max(14, tonumber(r.left:GetStringHeight()) or 14)
			r:SetHeight(th + 6)
			y = y - th - 8
		else
			local h = s.sub and P.ROW_H2 or P.ROW_H
			r:SetHeight(h)
			r.left:SetFontObject(GameFontHighlight)
			if r.left.SetWordWrap then r.left:SetWordWrap(false) end
			r.left:SetWidth(0)
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
					-- The owl's mark on a button that asks the AI (the bottom Ask buttons' kin).
					a.owl = a:CreateTexture(nil, "OVERLAY")
					a.owl:SetSize(11, 11)
					a.owl:SetPoint("LEFT", a, "LEFT", 5, 0)
					a.owl:SetTexture(ns.Window.MEDIA .. "Mark")
					a:RegisterForClicks("LeftButtonUp", "RightButtonUp")
					a:SetScript("OnClick", function(self, button) if self.fn then self.fn(button, self) end end)
					a:SetScript("OnEnter", function(self)
						if self.SetBackdropBorderColor then self:SetBackdropBorderColor(0.85, 0.68, 0.25, 1) end
						if self.tip and GameTooltip then
							GameTooltip:SetOwner(self, "ANCHOR_TOP")
							GameTooltip:SetText(self.tip, 1, 1, 1, 1, true)
							GameTooltip:Show()
						end
					end)
					a:SetScript("OnLeave", function(self)
						if self.SetBackdropBorderColor then self:SetBackdropBorderColor(0.58, 0.45, 0.98, 1) end
						if GameTooltip then GameTooltip:Hide() end
					end)
					r.actions[k] = a
				end
				local label = spec[1]
				local plainLabel = tostring(label):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
				local ai = spec.ai or P.AI_ACTIONS[plainLabel]
				a.text:SetText(label)
				a.fn = spec[2]
				a.tip = spec.tip or P.ACTION_TIPS[plainLabel]
				a.owl:SetShown(ai and true or false)
				a.text:ClearAllPoints()
				a.text:SetPoint("CENTER", a, "CENTER", ai and 6 or 0, 0)
				local aw = math.max(50, (tonumber(a.text:GetStringWidth()) or 40) + 18 + (ai and 12 or 0))
				a:SetWidth(aw)
				a:ClearAllPoints()
				a:SetPoint("RIGHT", r, "RIGHT", rightEdge, 0)
				a:Show()
				rightEdge = rightEdge - aw - 6
			end
			if s.tag then
				r.tag.text:SetText(s.tag[1])
				r.tag:SetWidth((tonumber(r.tag.text:GetStringWidth()) or 60) + 4)
				r.tag.text:SetTextColor(s.tag[2] or 1, s.tag[3] or 0.6, s.tag[4] or 0.2)
				r.tag:ClearAllPoints()
				r.tag:SetPoint("RIGHT", r, "RIGHT", rightEdge, 0)
				r.tag:Show()
				rightEdge = rightEdge - (tonumber(r.tag:GetWidth()) or 60) - 6
			end
			r.right:SetPoint("RIGHT", r, "RIGHT", rightEdge, 0)
			-- The second line stops short of the row's buttons and tags (seen in game: it ran under Go) and
			-- of the right text (seen in game: it ran under "level 17"), and wraps; lines of its own (a newline)
			-- stack, up to four (the player asked for the room, 2026-11-13).
			if s.sub then
				r.right:SetText(s.right or "")
				local rw = tonumber(r.right:GetStringWidth()) or 0
				if (s.right or "") == "" then rw = 0 end
				r.sub:SetWidth(math.max(40, w - lx - 2 + rightEdge - 8 - (rw > 0 and rw + 8 or 0)))
				if r.sub.SetWordWrap then r.sub:SetWordWrap(true) end
				if r.sub.SetMaxLines then r.sub:SetMaxLines(8) end
				local sh = math.max(12, tonumber(r.sub:GetStringHeight()) or 12)
				if sh > 16 then
					h = 21 + sh + 5
					r:SetHeight(h)
				end
			end
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
	if not keepScroll then
		f.scroll:SetVerticalScroll(0)
	else
		-- Kept, but never past the end when the list got shorter.
		local range = tonumber(f.scroll:GetVerticalScrollRange()) or 0
		if (tonumber(f.scroll:GetVerticalScroll()) or 0) > range then f.scroll:SetVerticalScroll(range) end
	end
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
	local dungeons, byDungeon = {}, {} -- dungeon quests, by their dungeon
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
			if info.complete then sub = "|cff19ff19Ready to turn in|r" .. (xpText and ("  " .. xpText) or "")
			else
				local left = ns.Quests.Left(info)
				sub = (xpText and (xpText .. (left and "  " or "")) or "") .. (left and ("|cffbbbbbb" .. left .. "|r") or "")
				if sub == "" then sub = nil end
			end
			local tag
			if info.elite then tag = { "Elite", 1, 0.3, 0.3 }
			-- Not "Dungeon": those rows sit under their own "Dungeon: …" heading (the review).
			elseif info.tagName and info.tagName ~= "Dungeon" and info.tagName ~= "Raid" then tag = { info.tagName, 0.45, 0.65, 1 }
			elseif info.group then tag = { "Group " .. info.group, 1, 0.6, 0.2 } end
			local dungeon = info.tagName == "Dungeon" or info.tagName == "Raid"
			local gap = level - you
			local right = where
			if not right and gap >= 3 and not info.complete then right = "|cffff9933+" .. gap .. " levels|r" end
			local id = it.id
			local row = { kind = "item", left = color .. "[" .. level .. plus .. "]|r " .. ns.Escape(info.title or it.title or "?"),
				sub = sub, right = right, tag = tag, quest = id, dist = info.dist or P.FAR, order = info.logIndex or 999, xp = xp or 0,
				name = info.title or it.title or "?", color = color,
				actions = { { "Go", function() P.Go(id) end } } }
			-- A group, elite or dungeon quest: LFG puts a ready message in the chat box.
			if not info.complete and (info.elite or info.group or dungeon) then
				table.insert(row.actions, 1, { "LFG", function(button, b) P.LFG(id, button, b) end })
			end
			if info.complete then groups.ready[#groups.ready + 1] = row
			elseif info.diff == "Trivial" or info.trivial then groups.grey[#groups.grey + 1] = row
			elseif dungeon then
				-- A dungeon's quests stay together, whatever their levels (seen in game: one under Do now,
				-- two under Later, all three for the Deadmines). Each keeps its "+3 levels".
				local h = info.header or info.title or "Dungeon"
				if not byDungeon[h] then
					byDungeon[h] = { title = h, rows = {}, order = #dungeons + 1, low = level }
					dungeons[#dungeons + 1] = byDungeon[h]
				end
				local g = byDungeon[h]
				g.rows[#g.rows + 1] = row
				if level <= g.low then g.low, g.color = level, color end
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
	-- The route (Route.lua): on or off from here, with where it stands.
	local RT = ns.Route
	if RT then
		local on = RT.On()
		local sub
		if on then
			local cur, i = RT.Current()
			local _, total = RT.Progress()
			local zone = R.route and R.route.zone
			sub = (cur and ("Step " .. i .. " of " .. total) or "Nothing left here") .. (zone and (" · " .. ns.Escape(zone)) or "")
		else
			sub = "Your next steps, an arrow and the map's areas, from your quest log" .. (ns.Dungeons.HasDB() and " and Questie." or ".")
		end
		out[#out + 1] = { kind = "item", left = "|cffb48cffQuest route|r", sub = "|cff888888" .. sub .. "|r",
			actions = { { on and "Hide" or "Show", function() RT.SetOn(not on); P.Show("quests", true) end,
				tip = on and "Turn the route off." or "Turn the route on: it stays on screen through /reload." },
				{ "Open", function() P.Show("route") end, tip = "The Route tab: every step, where next, the switches." } } }
	end
	Section("Ready to turn in", groups.ready)
	-- What turning them all in does for the level.
	local total = 0
	for _, r in ipairs(groups.ready) do total = total + (r.xp or 0) end
	local line = #groups.ready > 0 and ns.Quests.XpLine(total) or nil
	if line then table.insert(out, RT and 3 or 2, { kind = "text", text = line }) end
	for _, g in ipairs(now) do Section("Do now: " .. ns.Escape(g.title), g.rows) end
	-- Dungeons, the lowest first: one row each, its quests named, Open for the Dungeons tab, which has
	-- their givers, chains and hand-ins (the review, and the player's call: a dungeon's quests in
	-- full here repeated that tab). Ready ones are still under Ready to turn in.
	table.sort(dungeons, function(a, b) if a.low ~= b.low then return a.low < b.low end return a.order < b.order end)
	if #dungeons > 0 then out[#out + 1] = { kind = "head", text = "Dungeons" } end
	for _, g in ipairs(dungeons) do
		table.sort(g.rows, function(a, b) return a.order < b.order end)
		local names = {}
		for _, r in ipairs(g.rows) do names[#names + 1] = r.name end
		local gap, place = g.low - you, g.title
		out[#out + 1] = { kind = "item", left = (g.color or "|cffffffff") .. "[" .. g.low .. "]|r " .. ns.Escape(place),
			sub = "|cff888888" .. #g.rows .. (#g.rows == 1 and " quest: " or " quests: ") .. ns.Escape(table.concat(names, ", ")) .. "|r",
			right = gap >= 3 and ("|cffff9933+" .. gap .. " levels|r") or nil,
			actions = { { "LFG", function(button, b) P.LFGMenu(place, b) end }, { "Open", function() P.Show("dungeons") end } } }
	end
	Section("Group", groups.group)
	Section("Later", groups.later)
	Section("Skip? Little XP left", groups.grey)
	if #out == 0 then out[1] = { kind = "text", text = "Your quest log is empty. Ask what's worth picking up nearby." } end
	return out
end

-- LFG on a quest row: the message in the game's chat box, to edit and send with Enter.
-- Every click asks where it goes: the menu of the chat box's current channel, the channels the
-- player is in, Say, Party and Guild (the player preferred choosing each time to a kept pick).
-- The Route tab's questions (the player, 2026-11-19: "Review my route" took "Plan my next hour"'s
-- place). The route itself is in the game data the AI gets (advisor.route, advisor.whereNext).
function P.RouteQuestion(kind)
	local on = ns.Route and ns.Route.On()
	if kind == "ROUTE_WHY" then
		return on and "Why is my quest route in this order? Explain its first few steps briefly, from the route in my game data."
			or "The route is off. In what order should I do my quests here, and why?"
	end
	return on and "Review my quest route (the route in my game data): is the order good, which steps are worth skipping or leaving for later (and why), and where should I go after this zone? Keep it short."
		or "Plan my next hour of questing: which of my quests to do, in what order, and where."
end

-- The Route tab (Route.lua): the switches, every step with Skip, where next with Aim, what's elsewhere.
function Tabs.route()
	local RT = ns.Route
	local out = {}
	if not RT then return { { kind = "text", text = "The route isn't loaded." } } end
	local on = RT.On()
	local route = on and R.route or nil
	local function Switch(label, sub, value, set, indent, dim)
		out[#out + 1] = { kind = "item", indent = indent, left = dim and ("|cff888888" .. label .. "|r") or label,
			sub = sub and ("|cff888888" .. sub .. "|r") or nil,
			actions = { { value and "|cff19ff19On|r" or "|cff888888Off|r", function() set(not value); P.Show("route", true) end,
				tip = "Click to turn it on or off." } } }
	end
	out[#out + 1] = { kind = "head", text = "Quest route" }
	local status
	if route then
		local cur, i = RT.Current()
		local _, total = RT.Progress()
		status = route.nowhere and "Waiting for a position (an instance or a loading screen)."
			or ((cur and ("Step " .. i .. " of " .. total) or "Nothing left here") .. (route.zone and (" · " .. ns.Escape(route.zone)) or ""))
	end
	Switch("Quest route", status or ("Your next steps in a small window that stays on screen, an arrow and the steps on the world map, from your quest log"
		.. (ns.Dungeons.HasDB() and " and Questie's quest data." or ". Questie adds the quests to pick up and where mobs are.")), on, RT.SetOn)
	Switch("The arrow", "Points at the current step, with the yards to it.", RT.ArrowOn(), RT.SetArrow, true, not on)
	Switch("Steps on the world map", "Numbered, with each objective's area shaded.", RT.MapOn(), RT.SetMap, true, not on)
	Switch("Current step on the minimap", "Your current step, and the next one when it's in view. On the edge with an arrow when it's farther.", RT.MinimapOn(), RT.SetMinimap, true, not on)
	Switch("Lines on the world map", "From you to the current step, and on through the next ones, along the trails you've walked.", RT.LinesOn(), RT.SetLines, true, not on or not RT.MapOn())
	-- Trails learned from walking: on this PC only.
	local trailN = RT.TrailCount and RT.TrailCount() or 0
	Switch("Learn trails as I walk", "The roads you walk become the arrow's and the lines' way, on this PC only. " .. trailN .. " point" .. (trailN == 1 and "" or "s") .. " so far.",
		not ns.db.routeTrailsOff, function(v) ns.db.routeTrailsOff = (not v) or nil end, true, not on)
	if trailN > 0 then
		out[#out + 1] = { kind = "item", indent = true, left = "Forget my trails", sub = "|cff888888Every trail on this PC, for every character.|r",
			actions = { { "Forget", function() RT.ForgetTrails(); P.Show("route", true) end, tip = "They're gone for good." } } }
	end
	-- What the route plans for: questing here, or a dungeon's prep (the player, 2026-11-19).
	local mode, prep = RT.Mode()
	out[#out + 1] = { kind = "item", left = "Plan for", sub = "|cff888888" .. (mode == "dungeon" and ("Getting ready for " .. ns.Escape(prep) .. ": its quests and the questlines that open them, then the way in.")
		or "Questing where you are. Or pick a dungeon below: its quests, their questlines, the way in.") .. "|r",
		right = mode == "dungeon" and ("|cffffd100" .. ns.Escape(prep) .. " prep|r") or "|cffffd100Questing here|r",
		actions = mode == "dungeon" and { { "Questing", function() RT.SetMode("questing"); P.Show("route", true) end, tip = "Back to questing where you are." } } or nil }
	local seenD = {}
	local function Prep(dname, range)
		local key = ns.Dungeons.Norm(dname)
		if seenD[key] then return end
		seenD[key] = true
		local qs = ns.Dungeons.Quests(dname)
		if not qs or qs.total == 0 then return end
		local on = mode == "dungeon" and ns.Dungeons.Norm(prep) == key
		out[#out + 1] = { kind = "item", indent = true, left = ns.Escape(dname), right = range,
			sub = "|cff888888" .. (ns.Dungeons.Summary(qs) or "") .. "|r",
			actions = { { on and "Planned" or "Prep", function()
				if on then RT.SetMode("questing") else RT.SetMode("dungeon", dname); if not RT.On() then RT.SetOn(true) end end
				P.Show("route", true)
			end, tip = on and "Back to questing where you are." or "Plan the route to get ready for it." } } }
	end
	for _, d in ipairs(ns.Dungeons.FromLog()) do Prep(d.name, ns.Dungeons.Range(d.low, d.high)) end
	for _, d in ipairs(ns.Dungeons.AtLevel()) do Prep(d.name, ns.Dungeons.Range(d.low, d.high)) end
	out[#out + 1] = { kind = "item", indent = true, left = "Ask about your route", sub = "|cff888888Anything: your AI has the route. Or the two questions below.|r",
		actions = { { "Ask", function() ns.Chat.Open("About my route: ") end, tip = "The chat, ready for your question." } } }
	if not route or route.nowhere then return out end
	-- Every step: done, now, skipped, or to come.
	out[#out + 1] = { kind = "head", text = "Steps" }
	local cur = RT.Current()
	local skips = R.routeSkip or {}
	for i, s in ipairs(route.stops or {}) do
		local done, skipped = RT.StopDone(s), skips[s.key]
		local groups = RT.Groups(s, true)
		local more = {}
		for k = 2, #groups do more[#more + 1] = RT.GroupText(groups[k]) end
		local first = groups[1] and (RT.StopZone(s) .. RT.GroupText(groups[1])) or ""
		local grey = done or skipped
		local key = s.key
		out[#out + 1] = { kind = "item", left = (grey and "|cff888888" or (s == cur and "|cffffd100" or "|cffffffff")) .. i .. ".|r " .. first,
			sub = #more > 0 and ("|cff888888Then: " .. table.concat(more, "; ") .. "|r") or nil,
			right = done and "|cff19ff19done|r" or skipped and "|cff888888skipped|r" or (s == cur and "|cffffd100now|r") or nil,
			actions = (not done) and { { skipped and "Unskip" or "Skip", function() RT.SetSkip(key, not skipped); P.Show("route", true) end,
				tip = skipped and "Back on the route." or "Off the route for now (a /reload brings it back)." } } or nil }
	end
	if #(route.stops or {}) == 0 then out[#out + 1] = { kind = "text", text = "|cff19ff19Nothing left here that Spellmind knows of.|r" } end
	-- Where next: every zone counted, Aim for the arrow.
	local zones = {}
	for _, z in ipairs(route.where or {}) do if not z.here then zones[#zones + 1] = z end end
	if #zones > 0 then
		out[#out + 1] = { kind = "head", text = "Where next" }
		for _, z in ipairs(zones) do
			local aimed = R.routeAim == z.area
			out[#out + 1] = { kind = "item", left = "|cffffd100" .. ns.Escape(z.zone) .. "|r", sub = "|cff888888" .. RT.WhereText(z) .. "|r",
				right = z.low and ns.Dungeons.Range(z.low, z.high) or nil,
				actions = { { aimed and "Aimed" or "Aim", function() RT.Aim(z); P.Show("route", true) end,
					tip = aimed and "Back to the route's steps." or "Point the arrow the way there." } } }
		end
	end
	local away = RT.AwayLines(route)
	if #away > 0 then
		out[#out + 1] = { kind = "head", text = "Elsewhere" }
		for _, l in ipairs(away) do out[#out + 1] = { kind = "text", text = l } end
	end
	local credit = RT.Credit(route)
	if credit then out[#out + 1] = { kind = "text", text = "|cff777777" .. credit .. "|r" } end
	return out
end

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
		-- Nothing is posted: the line goes into the chat box (the review: "Post" said otherwise).
		m.title:SetText("Write your LFG line for:")
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
	-- Nothing is sent by Spellmind: the player sends it.
	if not m.foot then
		m.foot = m:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		m.foot:SetText("You press Enter to send it.")
	end
	m.foot:ClearAllPoints()
	m.foot:SetPoint("TOPLEFT", m, "TOPLEFT", 10, y - 2)
	m:SetSize(190, -y + 22)
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
	-- Route: this dungeon's prep on the route (the player, 2026-11-19), and the Route tab.
	local function prepRoute(name)
		return { "Route", function()
			if ns.Route then
				ns.Route.SetMode("dungeon", name)
				if not ns.Route.On() then ns.Route.SetOn(true) end
			end
			P.Show("route")
		end, tip = "Plan the route to get ready for it: its quests, the questlines that open them, the way in." }
	end
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
	-- Go to a giver: the game's map pin, and a line saying so.
	local function goTo(spot, giver)
		return { "Go", function()
			if ns.Dungeons.Go(spot) then
				ns.Chat.System("Map pin set for " .. ns.Escape(spot.name or giver or "the quest giver") .. ": follow the arrow.")
			else
				ns.Chat.System("The game can't pin " .. ns.Escape(giver or "that spot") .. " on the map.")
			end
		end }
	end
	-- The questlines that lead to this dungeon's locked quests (the player, 2026-11-13: "I'm trying to
	-- understand what questlines to follow leading to all deadmines quests"). One row each: the step to
	-- do now, then each of the dungeon's quests it opens, at its place in the chain.
	local function questlines(qs)
		local list = qs and qs.chains or {}
		if #list == 0 then return {} end
		out[#out + 1] = { kind = "label", text = "Questlines that lead here" }
		local starts, named = {}, {}
		for _, c in ipairs(list) do
			starts[c.id] = true
			-- A questline the game names unknown ("?") goes by where it leads (the player, 2026-11-17:
			-- a row titled "?"); one of the same name as another is a variant of it, shown once
			-- (Gnomeregan's Sparklematic 5200 has one quest per item it takes).
			local title = c.name
			if type(title) ~= "string" or title == "" or title == "?" then
				title = c.opens[1] and c.opens[1].name and ("A questline to " .. c.opens[1].name) or nil
			end
			if title and not named[title] then
			named[title] = true
			local lines, said = {}, {}
			local function add(line) if not said[line] then said[line] = true; lines[#lines + 1] = line end end
			-- How far it goes: its last step that opens one of the dungeon's quests.
			local last = c.step
			for _, o in ipairs(c.opens) do if o.step > last then last = o.step end end
			local stepWord = " step " .. c.step .. " of " .. last
			local from = c.from and (" |cff888888from " .. ns.Escape(c.from) .. "|r") or ""
			if c.inLog then
				add("|cff19ff19In your log:" .. stepWord .. "|r" .. (c.to and (" |cff888888hand it in to " .. ns.Escape(c.to) .. "|r") or ""))
			elseif c.at then
				add("|cffff9933Opens at level " .. c.at .. "|r" .. from)
			else
				add("|cffffd100Pick up" .. stepWord .. "|r" .. from)
			end
			for _, o in ipairs(c.opens) do
				local lvl = o.at and (" |cffff9933(level " .. o.at .. ")|r") or ""
				if o.same then
					add("|cff888888Step " .. o.step .. " is the dungeon's quest|r" .. lvl)
				else
					local after = o.step - 1
					add("|cff888888" .. (after > c.step and ("After step " .. after) or "Then") .. ": " .. ns.Escape(o.name)
						.. ((o.from and o.from ~= c.from) and (", from " .. ns.Escape(o.from)) or "") .. "|r" .. lvl)
				end
			end
			local actions = (not c.inLog and not c.at and c.spot) and { goTo(c.spot, c.from) } or nil
			out[#out + 1] = { kind = "item", indent = true, left = ns.Escape(title), right = c.level and ("level " .. c.level) or "",
				sub = table.concat(lines, "\n"), actions = actions }
			end
		end
		return starts
	end
	-- The rest still to pick up (QuestieDB's list), under small labels: the ones you can take now, then
	-- the ones waiting on a level. Each says its parts on lines of their own (the player asked,
	-- 2026-11-13: one crowded line ran under the level, with half the window empty below).
	local function pickups(qs, dname)
		local starts = questlines(qs)
		local ready, later, seen = {}, {}, {}
		for _, q in ipairs(qs and qs.pickup or {}) do
			-- A questline's quests are on its row; a quest of the same name as one shown is a variant.
			if q.after or starts[q.id] or seen[q.name or ""] then
			else
				seen[q.name or ""] = true
				if not q.at then ready[#ready + 1] = q else later[#later + 1] = q end
			end
		end
		local function Row(q)
			local lines = {}
			if q.at then
				lines[#lines + 1] = "|cffff9933Opens at level " .. q.at .. "|r"
				lines[#lines + 1] = "|cff888888Then from " .. ns.Escape(q.from or "a giver Spellmind doesn't know") .. "|r"
			else
				lines[#lines + 1] = "|cffffd100Pick up|r |cff888888from " .. ns.Escape(q.from or "a giver Spellmind doesn't know") .. "|r"
			end
			-- Ready to take: Go pins the giver on the map.
			local actions = (not q.at and q.spot) and { goTo(q.spot, q.from) } or nil
			out[#out + 1] = { kind = "item", indent = true, left = ns.Escape(q.name), right = q.level and ("level " .. q.level) or "",
				sub = table.concat(lines, "\n"), actions = actions }
		end
		if #ready > 0 then out[#out + 1] = { kind = "label", text = "To pick up" } end
		for _, q in ipairs(ready) do Row(q) end
		-- Not yet: one folded row, "N quests, opening at levels A-B", with Show (the player, 2026-11-17:
		-- eighteen rows for a dungeon seven levels away, then "make them a collapsed group"). Shown, their
		-- names by the level they open at; who gives them can wait until they open.
		if #later > 0 then
			local byLevel, levels = {}, {}
			for _, q in ipairs(later) do
				if not byLevel[q.at] then byLevel[q.at] = {}; levels[#levels + 1] = q.at end
				table.insert(byLevel[q.at], ns.Escape(q.name or "?"))
			end
			table.sort(levels)
			local key = DG.Norm(dname or "") .. "|later"
			local open = P.openDungeons[key]
			local span = levels[1] == levels[#levels] and ("level " .. levels[1]) or ("levels " .. levels[1] .. "-" .. levels[#levels])
			out[#out + 1] = { kind = "item", indent = true,
				left = "|cff888888Not yet:|r " .. #later .. " quest" .. (#later > 1 and "s" or "") .. ", opening at " .. span,
				actions = { { open and "Hide" or "Show", function()
					P.openDungeons[key] = not open or nil
					P.Show("dungeons", true)
				end } } }
			if open then
				for _, at in ipairs(levels) do
					out[#out + 1] = { kind = "text", text = "     |cffff9933Level " .. at .. ":|r |cffbbbbbb" .. table.concat(byLevel[at], ", ") .. "|r" }
				end
			end
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
		pickups(qs, here.name)
		shown[DG.Norm(here.name)] = true
	end
	out[#out + 1] = { kind = "head", text = "Dungeons you have quests for" }
	local any = false
	for _, d in ipairs(log) do
		if not shown[DG.Norm(d.name)] then
			any = true
			local name = d.name
			local bits = {}
			-- The dungeon's own range (the game's group finder), then the levels of your quests for it: two
			-- different things (seen in game: the quests' 18-20 read as the dungeon's).
			for _, l in ipairs(DG.Listed()) do
				if DG.Norm(l.name) == DG.Norm(name) and DG.Range(l.low, l.high) then bits[#bits + 1] = "dungeon " .. DG.Range(l.low, l.high) end
			end
			local range = DG.Range(d.low, d.high)
			if range then bits[#bits + 1] = "quests " .. range end
			if d.ready > 0 then bits[#bits + 1] = "|cff19ff19" .. d.ready .. " ready to turn in|r" end
			-- Without QuestieDB's count (which has them), how many are in the log.
			if not DG.HasDB() then table.insert(bits, 1, #d.quests .. " in your log") end
			local line, qs = status(name, #bits > 0 and table.concat(bits, " · ") or nil)
			out[#out + 1] = { kind = "item", left = ns.Escape(name), sub = "|cff888888" .. line .. "|r",
				tag = d.raid and { "Raid", 1, 0.5, 0.2 } or nil, actions = { lfg(name), brief(name), prepRoute(name) } }
			for _, q in ipairs(d.quests) do
				out[#out + 1] = { kind = "item", indent = true, quest = q.id,
					left = ns.Escape(q.title or "?"), right = q.complete and "|cff19ff19ready|r" or (q.level and ("level " .. q.level) or ""),
					actions = { { "Go", function() P.Go(q.id) end } } }
			end
			pickups(qs, name)
			shown[DG.Norm(name)] = true
		end
	end
	if not any then out[#out + 1] = { kind = "text", text = "No dungeon quests in your log. Ask: Which dungeon now? suggests one." } end
	local near = {}
	for _, d in ipairs(DG.AtLevel()) do if not shown[DG.Norm(d.name)] then near[#near + 1] = d end end
	if #near > 0 then
		out[#out + 1] = { kind = "head", text = "At your level" }
		for _, d in ipairs(near) do
			local name = d.name
			local line, qs = status(name, nil)
			local open = P.openDungeons[DG.Norm(name)]
			local actions = { lfg(name), brief(name), prepRoute(name) }
			-- Quests to pick up: a click lists them under the row (and hides them again).
			if qs and #qs.pickup > 0 then
				table.insert(actions, 1, { open and "Hide" or "Quests", function()
					P.openDungeons[DG.Norm(name)] = not open or nil
					P.Show("dungeons", true)
				end })
			end
			out[#out + 1] = { kind = "item", left = ns.Escape(name), right = DG.Range(d.low, d.high) or "",
				sub = line and ("|cff888888" .. line .. "|r") or nil, actions = actions }
			if open then pickups(qs, name) end
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
			link = c.link, actions = c.quest and { { "Go", function() P.Go(c.quest) end } } or nil }
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
				right = "|cffff9933" .. w.why .. "|r", invSlot = w.item and w.slot or nil }
		end
	end
	-- What needs you, not what the character sheet and the bags already show (the review: "Your gear
	-- (worn)" and "In your bags" repeated them). Gear about to break:
	local gear = Part("gear")
	local worn = {}
	for _, it in ipairs(type(gear.items) == "table" and gear.items or {}) do worn[#worn + 1] = it end
	table.sort(worn, function(a, b) return (a.slot or 0) < (b.slot or 0) end)
	local repairs = {}
	for _, it in ipairs(worn) do
		if type(it.dur) == "table" and (tonumber(it.dur[2]) or 0) > 0 then
			local pct = math.floor(it.dur[1] / it.dur[2] * 100 + 0.5)
			if pct < 75 then
				repairs[#repairs + 1] = { kind = "item", icon = ns.Try(GetInventoryItemTexture, "player", it.slot),
					left = (P.SLOT_NAMES[it.slot] or "?") .. " · " .. (QUALITY[it.q or 1] or "") .. ns.Escape(it.name or "?") .. "|r",
					right = (pct < 25 and "|cffff6060" or "|cffff9933") .. pct .. "% durability|r", invSlot = it.slot }
			end
		end
	end
	if #repairs > 0 then
		out[#out + 1] = { kind = "head", text = "Needs repair" }
		for _, r in ipairs(repairs) do out[#out + 1] = r end
	end
	-- The bags: only what has something to say (can't use it, safe to sell, a profession's), not every item.
	local bags = Part("bags")
	local items = type(bags.items) == "table" and bags.items or {}
	local worth, extra = {}, 0
	for _, it in ipairs(items) do
		local info = { pcall(C_Item.GetItemInfo, it.id) }
		local link, icon = info[1] and info[3], info[1] and info[11]
		local right
		if type(link) == "string" and ns.Tooltip then
			local data = C_TooltipInfo and type(C_TooltipInfo.GetHyperlink) == "function" and select(2, pcall(C_TooltipInfo.GetHyperlink, link)) or nil
			if it.equip then
				local reds = ns.Tooltip.RedTexts(type(data) == "table" and data or nil)
				if #reds > 0 then right = "|cffff9933" .. ns.Tooltip.Why(reds, tonumber(info[13]), it.sub, tonumber(info[14])) .. "|r" end
			end
			if not right then
				-- The tooltip's own advice, so the two never disagree (seen in game).
				local ok, advice = pcall(ns.Tooltip.SellLine, link, data)
				if not (ok and advice) then ok, advice = pcall(ns.Tooltip.ProfLine, link, data) end
				if ok and type(advice) == "string" then right = advice:gsub("^|cff9d7dffSpellmind:|r ", "") end
			end
		end
		if right then
			if #worth < P.BAG_ROWS then
				worth[#worth + 1] = { kind = "item", icon = icon, left = (QUALITY[it.q or 1] or "") .. ns.Escape(it.name or "?") .. "|r" .. ((it.n or 1) > 1 and (" x" .. it.n) or ""), right = right, link = link }
			else
				extra = extra + 1
			end
		end
	end
	if #worth > 0 or bags.slots then
		out[#out + 1] = { kind = "head", text = "Worth a look in your bags" .. (bags.free and bags.slots and (" (" .. bags.free .. " of " .. bags.slots .. " free)") or "") }
		for _, r in ipairs(worth) do out[#out + 1] = r end
		if extra > 0 then out[#out + 1] = { kind = "text", text = "|cff888888and " .. extra .. " more|r" } end
		if #worth == 0 then out[#out + 1] = { kind = "text", text = "|cff888888Nothing to sell, use or craft with that needs saying.|r" } end
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

-- Talents (docs/milestone-15.md): the player's guide, tracked. The next points from its talent order
-- against the character's own talents, points spent off it, names the tree doesn't have; without a
-- guide, how to set one. Then what's spent.
function Tabs.talents()
	local GD = ns.Guide
	local t = Part("talents")
	local unspent = tonumber(t.unspent) or 0
	local g = GD.Get()
	local plan = g and g.plan
	local out = {}
	if not g or (not g.url and not g.plan) then
		out[#out + 1] = { kind = "head", text = "Your guide" }
		out[#out + 1] = { kind = "item", left = "No guide yet", sub = "|cff888888Give Spellmind your leveling guide's link: it follows its talent order.|r",
			actions = { { "Set link", function() GD.AskLink(panel) end } } }
	elseif not plan then
		out[#out + 1] = { kind = "head", text = "Your guide" }
		out[#out + 1] = { kind = "item", left = ns.Escape(GD.Host(g.url) or "your guide"), sub = "|cff888888Not imported yet: your AI reads the page.|r",
			actions = { { "Change", function() GD.AskLink(panel) end }, { "Import", function() GD.Import(nil, panel) end } } }
	else
		out[#out + 1] = { kind = "head", text = "Your guide: " .. ns.Escape(plan.build or "build") }
		local p = GD.Progress()
		local tree = ns.State.AllTalents and ns.State.AllTalents() or {}
		out[#out + 1] = { kind = "item", left = ns.Escape(plan.title or GD.Host(g.url) or "your guide"),
			sub = "|cff888888" .. ns.Escape(plan.source or "") .. (p and (" · " .. p.done .. " of " .. p.total .. " points taken") or "") .. "|r",
			actions = { { "Change", function() GD.AskLink(panel) end }, { "Re-import", function() GD.Import(plan.build, panel) end } } }
		if p and #p.next > 0 then
			out[#out + 1] = { kind = "head", text = unspent > 0 and ("Spend your " .. (unspent == 1 and "point" or (unspent .. " points"))) or "Next points" }
			for i, s in ipairs(p.next) do
				if i > math.max(GD.TAB_NEXT or 4, unspent) then break end
				local now = s.now and unspent >= i
				-- Its level is past and no point is left for it: the guide had it by now (your points
				-- went elsewhere; the next one you get fills it).
				local behind = s.now and not now
				out[#out + 1] = { kind = "item", indent = true,
					left = (now and "|cff19ff19" or behind and "|cffff9933" or "") .. ns.Escape(GD.StepText(s, tree)) .. ((now or behind) and "|r" or ""),
					right = behind and ("|cffff9933behind: the guide takes it at " .. s.level .. "|r") or ("level " .. s.level),
					tag = nil } -- green says "now" (the review: the tag repeated it)
			end
			if p.behind > 0 and unspent == 0 then
				out[#out + 1] = { kind = "text", text = "     |cff888888Your next point" .. (p.behind > 1 and "s go" or " goes") .. " here first.|r" }
			end
		elseif p then
			out[#out + 1] = { kind = "text", text = "|cff19ff19Every point of the guide is taken.|r" }
		end
		-- Points the guide takes later, taken already: where the "behind" ones went.
		for _, e in ipairs(p and p.early or {}) do
			out[#out + 1] = { kind = "item", indent = true, left = "|cff9d7dffTaken early:|r " .. ns.Escape(e.name) .. " " .. e.rank,
				sub = "|cff888888Your guide takes it at level " .. (e.from == e.to and e.from or (e.from .. " to " .. e.to)) .. ".|r" }
		end
		for _, o in ipairs(p and p.off or {}) do
			out[#out + 1] = { kind = "item", indent = true, left = "|cffff6060Off plan:|r " .. ns.Escape(o.name) .. " " .. o.have,
				sub = "|cff888888" .. (o.plan > 0 and ("Your guide takes it to " .. o.plan .. ".") or "Your guide doesn't take it.") .. "|r" }
		end
		if p and #p.unknown > 0 then
			out[#out + 1] = { kind = "text", text = "|cffff6060Not in your talents: " .. ns.Escape(table.concat(p.unknown, ", ")) .. ".|r |cff888888The import may have misread them: Re-import, or ask.|r" }
		end
		-- The page's other builds: import one instead.
		local others = {}
		for _, b in ipairs(plan.builds or {}) do if b ~= plan.build then others[#others + 1] = b end end
		if #others > 0 then
			out[#out + 1] = { kind = "head", text = "Other builds in your guide" }
			for _, b in ipairs(others) do
				local build = b
				out[#out + 1] = { kind = "item", indent = true, left = ns.Escape(build), actions = { { "Import", function() GD.Import(build, panel) end } } }
			end
		end
	end
	-- What's spent: only without a guide (its row says "8 of 51 points taken" already, the review).
	if not plan then
		out[#out + 1] = { kind = "head", text = "Talents" }
		out[#out + 1] = { kind = "text", text = string.format("%d spent, %s", tonumber(t.spent) or 0,
			unspent > 0 and ("|cff19ff19" .. unspent .. " to spend|r") or "none to spend") }
	end
	return out
end

local function SpellRows()
	local s = Part("spells")
	local you = ns.State.Whole(ns.Try(UnitLevel, "player")) or 1
	-- The class trainer's kept list (Trainer.lua): Forever's spellbook shows nothing coming.
	local ok, p = false, nil
	if ns.Trainer then ok, p = pcall(ns.Trainer.Plan) end
	if ok and p then
		local M = ns.GearUI and ns.GearUI.Money or tostring
		local out = {}
		if #p.due > 0 then
			-- What the trainer has now, the ones your guide uses first and marked (the review: every spell
			-- was "train now" while the guide and the AI said otherwise).
			out[#out + 1] = { kind = "head", text = "At your trainer now: " .. M(p.total) }
			local plan = ns.Guide and ns.Guide.Get() and ns.Guide.Get().plan
			local lines = {}
			for _, l in ipairs(type(plan) == "table" and plan.rotation or {}) do lines[#lines + 1] = tostring(l):lower() end
			local function InGuide(name)
				for _, l in ipairs(lines) do if l:find(tostring(name):lower(), 1, true) then return true end end
				return false
			end
			local ordered = {}
			for _, t in ipairs(p.due) do if InGuide(t.name) then ordered[#ordered + 1] = t end end
			for _, t in ipairs(p.due) do if not InGuide(t.name) then ordered[#ordered + 1] = t end end
			for _, t in ipairs(ordered) do
				local g = InGuide(t.name)
				out[#out + 1] = { kind = "item", left = (g and "|cff19ff19" or "") .. ns.Escape(ns.Trainer.Label(t)) .. (g and "|r" or ""),
					right = M(t.cost or 0), tag = g and { "in your guide", 0.1, 1, 0.1 } or nil }
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

-- The Spells tab: the trainer's list (or the book's), then the guide's ability priority and its stat
-- and weapon advice (Guide.lua), when there's a guide.
function Tabs.spells()
	local out = SpellRows()
	local g = ns.Guide and ns.Guide.Get()
	local plan = g and g.plan
	if type(plan) == "table" and #(plan.rotation or {}) > 0 then
		out[#out + 1] = { kind = "head", text = "Your guide's priority" }
		-- One line a row: a long step is cut (the AI has the whole of it). Each says whether you have
		-- its ability yet, from your spellbook and your class trainer's list.
		for i, st in ipairs(ns.Guide.Priority()) do
			local right = ""
			if st.have then right = "|cff19ff19you have it|r"
			elseif st.train then right = "|cffff9933" .. ns.Escape(st.train) .. ": trains at " .. (st.level or "?") .. "|r" end
			out[#out + 1] = { kind = "item", left = i .. ". " .. ns.Escape(ns.ShortLine(st.line, 70)), right = right }
		end
	end
	if type(plan) == "table" and (#(plan.stats or {}) > 0 or plan.weapons) then
		out[#out + 1] = { kind = "head", text = "Stats and weapons" }
		if #(plan.stats or {}) > 0 then out[#out + 1] = { kind = "item", left = ns.Escape(table.concat(plan.stats, " > ")) } end
		if plan.weapons then out[#out + 1] = { kind = "text", text = "|cff888888" .. ns.Escape(ns.Utf8Cut(plan.weapons, 100)) .. "|r" } end
	end
	return out
end

-- Professions (docs/milestone-14.md): what to do next, not the numbers the game shows. Each profession
-- with its next rank (train now, or at what skill and level); for a crafting one, the recipes worth
-- crafting for a skill-up (orange, then yellow) and how many the bags make; then the bags' materials
-- and what they make. Recipes are known once the profession's window has been opened.
P.DIFF_COLOR = { optimal = "|cffff8040", medium = "|cffffff00", easy = "|cff40c040", trivial = "|cff808080" }
P.DIFF_NAME = { optimal = "orange", medium = "yellow" }
P.SKILLUPS_MAX, P.MATERIALS_MAX = 4, 6
-- The weapons worn (main hand, off hand, ranged) whose skill is P.WEAPON_BEHIND or more under its cap.
P.WEAPON_BEHIND = 25
function P.WeaponsBehind(s)
	local gear = Part("gear")
	local out, seen = {}, {}
	for _, it in ipairs(type(gear.items) == "table" and gear.items or {}) do
		if (it.slot == 16 or it.slot == 17 or it.slot == 18) and type(it.sub) == "string" then
			-- "One-Handed Axes" is the Axes skill; an exact name first ("Two-Handed Axes").
			local best
			for _, w in ipairs(type(s.weapon) == "table" and s.weapon or {}) do
				if w.name == it.sub then best = w end
			end
			if not best then
				for _, w in ipairs(type(s.weapon) == "table" and s.weapon or {}) do
					if type(w.name) == "string" and it.sub:find(w.name, 1, true) then best = w end
				end
			end
			local rank, max = best and tonumber(best.rank) or 0, best and tonumber(best.max) or 0
			if best and not seen[best.name] and max > 0 and rank <= max - P.WEAPON_BEHIND then
				seen[best.name] = true
				out[#out + 1] = { name = best.name, rank = rank, max = max }
			end
		end
	end
	return out
end

function Tabs.professions()
	local PR = ns.Professions
	local s = Part("skills")
	local out = { { kind = "head", text = "Professions" } }
	for _, p in ipairs(type(s.prof) == "table" and s.prof or {}) do
		local name = p.name or "?"
		local nr = PR.NextRank(p.rank, p.max)
		local sub
		if nr == "max" then sub = "|cff888888At the top rank.|r"
		elseif type(nr) == "table" and nr.ready then sub = "|cff19ff19Train " .. nr.name .. " now:|r |cff888888at a " .. ns.Escape(name) .. " trainer|r"
		elseif type(nr) == "table" then
			local need = {}
			if nr.needSkill then need[#need + 1] = "skill " .. nr.skill end
			if nr.needLevel then need[#need + 1] = "level " .. nr.level end
			sub = "|cff888888" .. nr.name .. " at " .. table.concat(need, " and ") .. "|r"
		end
		out[#out + 1] = { kind = "item", left = ns.Escape(name), right = (p.rank or 0) .. " / " .. (p.max or 0), sub = sub,
			tag = (type(nr) == "table" and nr.ready) and { "train", 0.1, 1, 0.1 } or nil }
		if not PR.GATHERING[name] then
			local su = PR.SkillUps(name)
			if not su.read or not su.list then
				out[#out + 1] = { kind = "text", text = "     |cff888888Open your " .. ns.Escape(name) .. " window once to see what to craft for skill-ups.|r" }
			elseif #su.list == 0 then
				out[#out + 1] = { kind = "text", text = "     |cff888888No orange or yellow recipes: learn new ones" .. ((type(nr) == "table" and nr.ready) and ", or train the next rank" or "") .. ".|r" }
			else
				for i, r in ipairs(su.list) do
					if i > P.SKILLUPS_MAX then break end
					local bits = {}
					for _, rg in ipairs(r.reagents) do
						local enough = rg.have >= rg.need
						bits[#bits + 1] = (enough and "" or "|cffff6060") .. ns.Escape(PR.ItemName(rg.item)) .. " " .. rg.have .. "/" .. rg.need .. (enough and "" or "|r")
					end
					out[#out + 1] = { kind = "item", indent = true,
						left = (P.DIFF_COLOR[r.diff] or "") .. ns.Escape(r.name) .. "|r  |cff888888" .. (P.DIFF_NAME[r.diff] or "") .. "|r",
						right = r.makes > 0 and ("|cff19ff19make " .. r.makes .. "|r") or "|cff888888make 0|r",
						sub = "|cff888888" .. table.concat(bits, " · ") .. "|r" }
				end
				-- The colours are as the window last showed them: after skill-ups, yellow may be green.
				if su.skill and tonumber(p.rank) and tonumber(p.rank) > su.skill then
					out[#out + 1] = { kind = "text", text = "     |cff888888As of skill " .. su.skill .. ": open the window again to refresh.|r" }
				end
			end
		end
	end
	if #out == 1 then out[2] = { kind = "text", text = "No professions yet." } end
	local mats = PR.Materials()
	if #mats > 0 then
		out[#out + 1] = { kind = "head", text = "Your materials" }
		for i, m in ipairs(mats) do
			if i > P.MATERIALS_MAX then break end
			local best = m.recipes[1]
			local also = {}
			for k = 2, math.min(#m.recipes, 3) do also[#also + 1] = ns.Escape(m.recipes[k].name) end
			out[#out + 1] = { kind = "item", left = ns.Escape(m.name) .. " x" .. m.n,
				right = best.makes > 0 and ("|cff19ff19makes " .. best.makes .. " " .. ns.Escape(best.name) .. "|r") or ("|cff888888" .. ns.Escape(best.name) .. ": not enough|r"),
				sub = #also > 0 and ("|cff888888also " .. table.concat(also, ", ") .. "|r") or nil }
		end
	end
	-- Weapon skills: only a weapon you have equipped whose skill is well behind (the review: the list
	-- copied the Skills window, and missed the one that mattered, Guns 1/85 with a gun on).
	local behind = P.WeaponsBehind(s)
	if #behind > 0 then
		out[#out + 1] = { kind = "head", text = "Weapon skills" }
		for _, w in ipairs(behind) do
			out[#out + 1] = { kind = "item", left = "|cffff9933" .. ns.Escape(w.name) .. " " .. w.rank .. "/" .. w.max .. "|r",
				sub = "|cff888888You'll miss often with it. Use it on easy mobs to raise it.|r" }
		end
	end
	return out
end

-- Nudges: every one waiting (faded or behind the toast), each with Ask and Dismiss.
function Tabs.nudges()
	local out = { { kind = "head", text = "Waiting" } }
	local list = ns.Nudges and ns.Nudges.List() or {}
	for _, n in ipairs(list) do
		local kind = n.kind
		local actions = {}
		if ns.Nudges.TabFor(kind) then actions[#actions + 1] = { "Open", function() ns.Nudges.OpenKind(kind) end } end
		actions[#actions + 1] = { "Ask", function() ns.Nudges.AskKind(kind, panel) end }
		actions[#actions + 1] = { "Dismiss", function() ns.Nudges.DoneKind(kind) end }
		-- The title, and its detail on a line of its own (the review: on one line beside two buttons it was cut).
		out[#out + 1] = { kind = "item", icon = n.icon, left = n.title, sub = (n.text and n.text ~= "") and ("|cff888888" .. n.text .. "|r") or nil,
			tag = n.asked and { "asked", 0.4, 0.85, 0.4 } or nil, actions = actions }
	end
	if #list == 0 then out[#out + 1] = { kind = "text", text = "Nothing waiting. Nudges show by the minimap when something comes up." } end
	return out
end

-- Gold (docs/milestone-14.md): what came in and went out, what's coming, and what the bags would fetch.
local function Signed(copper)
	copper = math.floor(tonumber(copper) or 0)
	if copper == 0 then return "|cff8888880|r" end
	return (copper > 0 and "|cff19ff19+" or "|cffff6060-") .. Money(math.abs(copper)) .. "|r"
end
function Tabs.gold()
	local GL = ns.Gold
	local c = Part("char")
	local b = Part("bags")
	local money = tonumber(c.money) or 0
	local out = { { kind = "head", text = "Gold" } }
	out[#out + 1] = { kind = "item", left = "On you", right = Money(money) }
	local inc = GL.Income()
	local s, d = inc.session, inc.today
	out[#out + 1] = { kind = "item", left = "This session", right = Signed(s.net),
		sub = "|cff888888in " .. Money(s.earned) .. " · out " .. Money(s.spent) .. (s.perHour and (" · about " .. Money(math.max(0, s.perHour)) .. " an hour") or "") .. "|r" }
	out[#out + 1] = { kind = "item", left = "Today", right = Signed(d.net), sub = "|cff888888in " .. Money(d.earned) .. " · out " .. Money(d.spent) .. "|r" }

	local costs, total = GL.Costs()
	if #costs > 0 then
		out[#out + 1] = { kind = "head", text = "Coming up" }
		for _, x in ipairs(costs) do
			out[#out + 1] = { kind = "item", left = ns.Escape(x.label), right = x.copper and Money(x.copper) or "",
				sub = x.note and ("|cff888888" .. ns.Escape(x.note) .. "|r") or nil }
		end
		if total > 0 then
			out[#out + 1] = { kind = "text", text = (money >= total and "|cff19ff19" or "|cffff6060") .. "Known costs: " .. Money(total) .. " of your " .. Money(money) .. "|r" }
		end
	end

	out[#out + 1] = { kind = "head", text = "Your bags are worth" }
	local sell, sellTotal = ns.Gear.SellList()
	local names = {}
	for i, it in ipairs(sell) do if i <= 3 then names[#names + 1] = ns.Escape(it.name) .. (it.n > 1 and (" x" .. it.n) or "") end end
	out[#out + 1] = { kind = "item", left = "Safe to sell at a vendor", right = Money(sellTotal),
		sub = #names > 0 and ("|cff888888" .. table.concat(names, ", ") .. (#sell > 3 and (" and " .. (#sell - 3) .. " more") or "") .. "|r") or "|cff888888Nothing clearly safe to sell.|r" }
	local ah = GL.AHWorth()
	if not ah then
		out[#out + 1] = { kind = "text", text = "|cff888888With Auctionator, auction house prices for your trade goods show here.|r" }
	elseif ah.priced == 0 then
		out[#out + 1] = { kind = "item", left = "On the auction house", right = "|cff888888no prices yet|r",
			sub = "|cff888888Scan at the auction house with Auctionator, then look again.|r" }
	else
		local top = {}
		for i, e in ipairs(ah.list) do
			if i <= 3 then top[#top + 1] = ns.Escape(e.name) .. (e.n > 1 and (" x" .. e.n) or "") .. " " .. Money(e.copper) end
		end
		out[#out + 1] = { kind = "item", left = "On the auction house", right = Money(ah.total),
			sub = "|cff888888" .. table.concat(top, " · ") .. " (Auctionator's last scan)|r" }
	end
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
	-- The Spellmind app, read only (the review: only the Chat tab's header said whether it was there, and
	-- which AI answers). The AI is changed in the app's window, not here.
	out[#out + 1] = { kind = "head", text = "The Spellmind app" }
	local gone = ns.Link.AppGone and ns.Link.AppGone()
	local age = ns.Link.BridgeAge and ns.Link.BridgeAge()
	out[#out + 1] = { kind = "item", left = "App",
		right = gone and "|cffff9933not running|r" or "|cff19ff19running|r",
		sub = "|cff888888" .. (gone and "Start it from the Start menu, or its icon by the clock. It talks to your AI for this addon. Don't have it? Get the app."
			or ("Heard from " .. (age and age < 60 and "just now" or age and (math.floor(age / 60) .. " min ago") or "this session") .. ".")) .. "|r",
		actions = gone and ns.Marks and ns.Marks.GetApp and { { "Get the app", function() ns.Marks.GetApp() end, tip = "Where the free app is: a link to copy." } } or nil }
	local ai = R.ai
	if type(ai) == "table" and type(ai.name) == "string" then
		local model = type(ai.model) == "string" and ai.model ~= "" and (" · " .. ns.Escape(ai.model)) or ""
		out[#out + 1] = { kind = "item", left = "Your AI", right = ns.Escape(ai.name) .. model,
			sub = "|cff888888" .. (ai.ready == false and "|cffff9933Not set up: sign in or paste a key in the app.|r" or "Change it, sign in or add a key in the app's window.") .. "|r" }
	end
	out[#out + 1] = { kind = "item", left = "Addon", right = "version " .. ns.Escape(ns.VERSION or "?"),
		sub = "|cff888888The app keeps it up to date while WoW is closed, or update it from CurseForge.|r" }
	for _, sec in ipairs(ST.List()) do
		out[#out + 1] = { kind = "head", text = sec.section }
		for _, r in ipairs(sec.rows) do
			local id = r.id
			local dim = r.dim and r.dim()
			out[#out + 1] = { kind = "item", indent = r.indent,
				left = dim and ("|cff888888" .. r.label .. "|r") or r.label,
				sub = r.sub and ("|cff888888" .. r.sub .. "|r") or nil,
				actions = { { ST.Label(r), function() ST.Flip(id); P.Show("settings", true) end,
					tip = r.choices and "Click for the next choice." or "Click to turn it on or off." } } }
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
	-- Your guide (Guide.lua): its link, set or changed here too.
	local g = ns.Guide.Get()
	out[#out + 1] = { kind = "head", text = "Your guide" }
	out[#out + 1] = { kind = "item", left = g and g.url and ns.Escape(ns.Guide.Host(g.url) or "your guide") or "No guide yet",
		sub = "|cff888888" .. (g and g.plan and ("Following " .. ns.Escape(g.plan.build or "its build") .. ". The Talents tab tracks it.") or "A leveling guide's link: its talent order, priorities and weapon advice.") .. "|r",
		actions = { { g and g.url and "Change" or "Set link", function() ns.Guide.AskLink(panel) end } } }
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
		elseif q == "DUNGEON_NEXT" then q = P.NextDungeonQuestion()
		elseif q == "ROUTE_REVIEW" or q == "ROUTE_WHY" then q = P.RouteQuestion(q) end
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
	-- MEDIUM, raised on a click (the review: at DIALOG it covered the game's windows and Spellmind's own
	-- trainer and merchant buttons beside them).
	f:SetFrameStrata("MEDIUM")
	if f.SetToplevel then f:SetToplevel(true) end
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
	-- A drawn bar, like the hamburger beside it (the review: the "-" was hard to see); folded, a chevron.
	f.fold.bar = f.fold:CreateTexture(nil, "OVERLAY")
	f.fold.bar:SetColorTexture(0.85, 0.68, 0.25, 1)
	f.fold.bar:SetSize(10, 2)
	f.fold.bar:SetPoint("CENTER", f.fold, "CENTER", 0, 0)
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
	-- In the 12 px right margin: the rows fill the scroll frame's width.
	f.bar = ns.Window.ScrollBar(f.scroll, 8)

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
		P.Show(P.tab, true)
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
	P.EscCloses(not saved.compact)
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
		if panel and panel:IsShown() and P.tab ~= "chat" then P.Show(P.tab, true) end -- a live redraw keeps the scroll (the review)
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
	f.fold.text:SetText(folded and "+" or "")
	if f.fold.bar then f.fold.bar:SetShown(not folded) end
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
-- Esc closes the full window, not the compact one (the review: kept open while questing, it went
-- with a routine Esc to clear a target). UISpecialFrames is the game's list of windows Esc closes.
function P.EscCloses(on)
	if type(UISpecialFrames) ~= "table" then return end
	for i = #UISpecialFrames, 1, -1 do
		if UISpecialFrames[i] == "SpellmindPanel" then table.remove(UISpecialFrames, i) end
	end
	if on then table.insert(UISpecialFrames, "SpellmindPanel") end
end

function P.SetCompact(on, quiet)
	local f = P.Build()
	local saved = Saved()
	if (saved.compact and true or false) == (on and true or false) then return end
	KeepSize(f)
	saved.compact = on and true or nil
	P.EscCloses(not saved.compact)
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
	if panel and panel:IsShown() and P.tab == "nudges" then P.Show("nudges", true) end
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
	-- The card is titled with the question itself (the review: "Advisor:" was an old internal name).
	return ns.Marks.Ask(panel, ns.Escape(label), text)
end
