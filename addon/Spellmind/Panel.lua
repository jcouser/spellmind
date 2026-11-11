-- Panel.lua: the Advisor panel (docs/features.md §2, docs/milestone-7.md; mockup B of 2026-11-10): one
-- window with a rail of tabs (Quests, Gear, Talents, Spells, Professions, Gold) showing the character's
-- live facts at a glance, read locally (no AI), with Ask buttons whose answers show in the answer card
-- beside the panel. Opens from the minimap button's right-click or /sm panel.
--
-- Read only, like the marks: nothing is selected, equipped, sold or set.

local _, ns = ...
local P = {}
ns.Panel = P
local R = ns.R

P.W, P.H = 560, 480
P.RAIL_W = 150
P.ROW_H = 24
P.BAG_ROWS = 8
P.TABS = {
	{ id = "quests", name = "Quests", icon = "Interface\\Icons\\INV_Letter_15" },
	{ id = "gear", name = "Gear", icon = "Interface\\Icons\\INV_Chest_Leather_09" },
	{ id = "talents", name = "Talents", icon = "Interface\\Icons\\Ability_Marksmanship" },
	{ id = "spells", name = "Spells", icon = "Interface\\Icons\\Spell_Holy_MagicalSentry" },
	{ id = "professions", name = "Professions", icon = "Interface\\Icons\\Trade_BlackSmithing" },
	{ id = "gold", name = "Gold", icon = "Interface\\Icons\\INV_Misc_Coin_01" },
	{ id = "nudges", name = "Nudges", icon = "Interface\\AddOns\\Spellmind\\Media\\Badge" },
}
-- Each tab's two Ask buttons: { label, the question }.
P.ASKS = {
	quests = { { "Plan my next hour", "Plan my next hour of questing: which of my quests to do, in what order, and where." }, { "What's worth skipping?", "Which of my quests are worth skipping or leaving for later, and why?" } },
	gear = { { "Any upgrades?", "Is anything in my bags an upgrade for me? And what should I look for next at my level?" }, { "What should I sell?", "What in my bags should I sell, keep or put on the auction house?" } },
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
local function Draw(f, specs)
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
		r.tag:Hide()
		r.rule:SetShown(s.kind == "head")
		r.right:SetText("")
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
			r:SetHeight(P.ROW_H)
			r.left:SetFontObject(GameFontHighlight)
			if s.icon then r.icon:SetTexture(s.icon) end
			r.left:SetPoint("LEFT", r, "LEFT", s.icon and 30 or 8, 0)
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
					a:SetScript("OnClick", function(self) if self.fn then self.fn() end end)
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
			r.right:SetText(s.right or "")
			r.left:SetPoint("RIGHT", r.right, "LEFT", -8, 0)
			r.left:SetText(s.left or "")
			y = y - P.ROW_H - 4
		end
		r:Show()
		f.drawn[#f.drawn + 1] = { kind = s.kind, text = s.text or s.left, right = s.right, tag = s.tag and s.tag[1], quest = s.quest }
	end
	for i = #specs + 1, #f.rows do f.rows[i]:Hide() end
	f.content:SetHeight(math.max(10, -y))
	f.scroll:SetVerticalScroll(0)
end

---------------------------------------------------------------------------
-- The tabs' contents (each returns row specs)
---------------------------------------------------------------------------

local Tabs = {}
P.Tabs = Tabs

-- Quests: ready to turn in, worth doing now, later (elite, group, or orange and red), and grey.
function Tabs.quests()
	local q = Part("quests")
	local you = ns.State.Whole(ns.Try(UnitLevel, "player")) or 1
	local ready, now, later, grey = {}, {}, {}, {}
	for _, it in ipairs(type(q.list) == "table" and q.list or {}) do
		local info = ns.Quests.Read(it.id)
		if info then
			local level = info.level or it.level or 0
			local c = ns.Try(GetQuestDifficultyColor, level)
			local color = type(c) == "table" and Hex(c.r, c.g, c.b) or "|cffffffff"
			local plus = (info.elite or info.group) and "+" or ""
			local left = color .. "[" .. level .. plus .. "]|r " .. ns.Escape(info.title or it.title or "?")
			local right, tag
			if info.complete then
				right = "|cff40c040ready to turn in|r"
			elseif info.where then
				right = "on your map" .. (info.dist and (" · " .. info.dist .. " yd") or "")
			else
				local done, all = 0, 0
				for _, o in ipairs(Plain(info.obj) or {}) do
					all = all + 1
					if (tonumber(o.have) or 0) >= (tonumber(o.need) or 1) then done = done + 1 end
				end
				if all > 1 then right = done .. " of " .. all .. " done" elseif info.dist then right = info.dist .. " yd" end
			end
			if info.elite then tag = { "Elite", 1, 0.3, 0.3 } elseif info.group then tag = { "Group", 1, 0.6, 0.2 } end
			local row = { kind = "item", left = left, right = right, tag = tag, quest = it.id }
			if info.complete then ready[#ready + 1] = row
			elseif info.diff == "Trivial" or info.trivial then grey[#grey + 1] = row
			elseif info.elite or info.group or info.diff == "VeryDifficult" or info.diff == "Impossible" then later[#later + 1] = row
			else now[#now + 1] = row end
		end
	end
	local out = {}
	local function Section(title, rows)
		if #rows == 0 then return end
		out[#out + 1] = { kind = "head", text = title }
		for _, r in ipairs(rows) do out[#out + 1] = r end
	end
	Section("Ready to turn in", ready)
	Section("Worth doing now", now)
	Section("Later", later)
	Section("Grey: little XP left", grey)
	if #out == 0 then out[1] = { kind = "text", text = "Your quest log is empty. Ask what's worth picking up nearby." } end
	return out
end

-- Gear: what's worn, what's in the bags (wearables with the tooltip line's verdict, then the rest), empty slots.
function Tabs.gear()
	local out = { { kind = "head", text = "Your gear (worn)" } }
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
			elseif type(sell) == "number" and sell > 0 then
				right = "sell: " .. Money(sell * (it.n or 1))
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
	local out = { { kind = "head", text = "Coming next" } }
	local any = false
	for _, n in ipairs(type(s.next) == "table" and s.next or {}) do
		any = true
		local ready = (n.level or 99) <= you
		out[#out + 1] = { kind = "item", left = ns.Escape(n.name or "?") .. (n.rank and (" (rank " .. n.rank .. ")") or ""),
			right = "level " .. (n.level or "?"), tag = ready and { "train now", 0.1, 1, 0.1 } or nil }
	end
	if not any then out[#out + 1] = { kind = "text", text = "Nothing new in your spellbook yet." } end
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
	b:SetSize(P.RAIL_W - 16, 30)
	b:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -58 - (i - 1) * 34)
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
	b:SetScript("OnClick", function(self) if self.ask then P.Ask(self.ask[1], self.ask[2]) end end)
	return b
end

function P.Build()
	if panel then return panel end
	local saved = Saved()
	local f = CreateFrame("Frame", "SpellmindPanel", UIParent, "BackdropTemplate")
	f:SetSize(P.W, P.H)
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
	ns.Window.Fill(f, 4, 0.035, 0.025, 0.08, 0.97)
	ns.Window.Corners(f)

	f.portrait = f:CreateTexture(nil, "ARTWORK")
	f.portrait:SetSize(36, 36)
	f.portrait:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -8)
	f.portrait:SetTexture(ns.Window.PORTRAIT)
	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 52, -11)
	f.title:SetText("Spellmind Advisor")
	f.who = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.who:SetPoint("TOPLEFT", f, "TOPLEFT", 52, -31)
	f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
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
	local half = math.floor((P.W - P.RAIL_W - 36) / 2)
	for i, b in ipairs(f.asks) do
		b:SetWidth(half)
		b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", P.RAIL_W + 12 + (i - 1) * (half + 12), 14)
	end

	-- Live while open: the game's own events, at most one redraw a second.
	f:RegisterEvent("QUEST_LOG_UPDATE")
	f:RegisterEvent("BAG_UPDATE_DELAYED")
	f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	f:RegisterEvent("PLAYER_LEVEL_UP")
	f:RegisterEvent("PLAYER_MONEY")
	f:RegisterEvent("SKILL_LINES_CHANGED")
	f:SetScript("OnEvent", function() P.Soon() end)

	-- The card beside the panel closes with it.
	f:HookScript("OnHide", function(self) if ns.Marks and ns.Marks.card and ns.Marks.card.owner == self then ns.Marks.card:Hide() end end)
	if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "SpellmindPanel") end
	f:Hide()
	panel = f
	return f
end

function P.Get() return panel end

function P.Soon()
	if not panel or not panel:IsShown() or P.pending then return end
	P.pending = true
	C_Timer.After(1, function()
		P.pending = nil
		if panel and panel:IsShown() then P.Show(P.tab) end
	end)
end

-- The panel on a tab (the last one, by default), its rows read now.
function P.Show(id)
	local f = P.Build()
	id = id or Saved().tab or "quests"
	if not Tabs[id] then id = "quests" end
	P.tab, Saved().tab = id, id
	for _, b in ipairs(f.tabs) do
		local on = b.id == id
		if b.SetBackdropColor then
			b:SetBackdropColor(on and 0.32 or 0.06, on and 0.22 or 0.04, on and 0.62 or 0.12, on and 0.95 or 0.6)
			b:SetBackdropBorderColor(on and 0.62 or 0.3, on and 0.49 or 0.24, on and 1 or 0.5, 1)
		end
	end
	f.who:SetText(P.Who())
	P.CountNudges()
	f.content:SetWidth(P.W - P.RAIL_W - 24)
	local ok, specs = pcall(Tabs[id])
	Draw(f, ok and specs or { { kind = "text", text = "|cffff6060This tab couldn't read your character just now.|r" } })
	for i, b in ipairs(f.asks) do
		local a = P.ASKS[id] and P.ASKS[id][i]
		b.ask = a
		b.text:SetText(a and ("Ask: " .. a[1]) or "")
		b:SetShown(a ~= nil)
	end
	if not f:IsShown() then f:Show() end
	return f
end

-- The Nudges tab's label with its count, and the tab redrawn when it's the one showing.
function P.CountNudges()
	local f = panel
	if not f then return end
	local n = ns.Nudges and #ns.Nudges.List() or 0
	for _, b in ipairs(f.tabs) do
		if b.id == "nudges" then b.text:SetText(n > 0 and ("Nudges |cffffd100(" .. n .. ")|r") or "Nudges") end
	end
end

function P.NudgesChanged()
	P.CountNudges()
	if panel and panel:IsShown() and P.tab == "nudges" then P.Show("nudges") end
end

function P.Toggle()
	local f = P.Build()
	if f:IsShown() then f:Hide() else P.Show() end
end

-- An Ask button: the question goes to the chat, its answer to the card beside the panel.
function P.Ask(label, text)
	if not ns.Marks then return end
	return ns.Marks.Ask(panel, "Advisor: " .. ns.Escape(label), text)
end
