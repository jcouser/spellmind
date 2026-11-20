-- Nudges.lua: small toasts by the minimap (docs/features.md §2, docs/milestone-8.md), from local facts
-- only: a talent point to spend, spells to train, gear about to break, bags nearly full, a quest
-- that just became ready to turn in, a profession near its rank's cap. One at a time, never in
-- combat; Ask sends the matching question (its answer in the card beside the toast), Dismiss moves on.
-- A dismissed nudge doesn't come back until its situation changes (a new level, more points, the
-- bags filling again after being cleared). The minimap button shows a dot while one waits.
-- /sm nudges off and on.

local _, ns = ...
local N = {}
ns.Nudges = N
local R = ns.R

N.THROTTLE = 2 -- seconds: events coalesce into one check
N.GAP = 3 -- seconds between one nudge and the next
N.FADE_AFTER = 20 -- seconds a toast shows before it fades (it keeps waiting: the dot brings it back)
N.FADE_TIME = 1
N.BAGS_LOW, N.BAGS_OK = 3, 6 -- free slots: nudge at or below LOW; again only after rising above OK
N.DURABILITY_LOW = 20 -- percent
N.PROF_NEAR = 5 -- ranks below the cap
N.ICONS = {
	talents = "Interface\\Icons\\Ability_Marksmanship",
	spells = "Interface\\Icons\\INV_Misc_Book_09",
	durability = "Interface\\Icons\\Trade_BlackSmithing",
	bags = "Interface\\Icons\\INV_Misc_Bag_08",
	turnin = "Interface\\Icons\\INV_Letter_15",
	near = "Interface\\Icons\\INV_Misc_Map_01",
	prof = "Interface\\Icons\\INV_Misc_Note_01",
	dungeon = "Interface\\Icons\\INV_Misc_Key_03",
	classq = "Interface\\Icons\\INV_Misc_Book_11",
}
N.SLOT_NAMES = { "head", "neck", "shoulders", "shirt", "chest", "waist", "legs", "feet", "wrists", "hands", "ring", "ring",
	"trinket", "trinket", "back", "main hand", "off hand", "ranged", "tabard" }

local toast

local function Saved()
	local db = ns.db
	if not db then return { seen = {} } end
	if type(db.nudges) ~= "table" then db.nudges = {} end
	db.nudges.seen = nil -- per character now (Seen)
	return db.nudges
end

function N.On()
	return ns.db ~= nil and Saved().off ~= true
end

-- The situations shown and dismissed or asked, per character (the review: account-wide, a nudge
-- dismissed on one character was silent on its alts): SpellmindDB.chars[key].nudgeSeen.
local function Seen()
	local me = ns.State and ns.State.Me and ns.db and ns.State.Me()
	if not me then return {} end
	if type(me.nudgeSeen) ~= "table" then me.nudgeSeen = {} end
	return me.nudgeSeen
end
N.Seen = Seen

local function Fighting()
	return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

local function Plain(o)
	if type(o) ~= "table" then return o end
	local t = {}
	if o._o then
		for _, kv in ipairs(o._o) do t[kv[1]] = Plain(kv[2]) end
	else
		for i, v in ipairs(o) do t[i] = Plain(v) end
	end
	return t
end

local function Part(name)
	local fn = ns.State and ns.State.Collect and ns.State.Collect[name]
	if type(fn) ~= "function" then return {} end
	local ok, o = pcall(fn)
	return ok and Plain(o) or {}
end

---------------------------------------------------------------------------
-- What's worth a nudge now: { kind (one per situation), key (its state), title, text, ask }
---------------------------------------------------------------------------

local Detect = {}
N.Detect = Detect

-- Inside a dungeon (Dungeons.lua): its name, how many of your quests are for it, and Ask for a briefing.
-- Once a visit: the key is the instance, and leaving drops it so the next visit nudges again.
function Detect.dungeon()
	local DG = ns.Dungeons
	local here = DG and DG.Here()
	if not here then
		local seen = Seen()
		seen.dungeon = nil
		return {}
	end
	local n, ready = 0, 0
	for _, d in ipairs(DG.FromLog()) do
		if DG.Norm(d.name) == DG.Norm(here.name) then n, ready = #d.quests, d.ready end
	end
	local text = n > 0 and (n .. " of your quests here" .. (ready > 0 and (", " .. ready .. " ready") or "") .. ". Want a briefing?") or "Want a briefing?"
	return { { kind = "dungeon", key = here.name, title = "Entering " .. ns.Escape(here.name),
		text = text, ask = DG.Briefing(here.name) } }
end

function Detect.talents()
	local t = Part("talents")
	local n = tonumber(t.unspent) or 0
	if n <= 0 then return {} end
	-- With a guide (Guide.lua): its next pick, by name.
	local text = "Want a pick for your build?"
	local p = ns.Guide and ns.Guide.Progress and select(2, pcall(ns.Guide.Progress))
	local first = type(p) == "table" and p.next and p.next[1]
	if first then text = "Your guide: " .. ns.Escape(ns.Guide.StepText(first, ns.State.AllTalents and ns.State.AllTalents() or {})) .. "." end
	return { { kind = "talents", key = "talents:" .. n .. ":" .. (ns.State.Whole(ns.Try(UnitLevel, "player")) or 0),
		title = n == 1 and "A talent point to spend" or (n .. " talent points to spend"),
		text = text,
		ask = "I have " .. n .. " talent point" .. (n > 1 and "s" or "") .. " to spend. What should I take, and why?" } }
end

function Detect.spells()
	local s = Part("spells")
	local you = ns.State.Whole(ns.Try(UnitLevel, "player")) or 1
	local due = {}
	for _, n in ipairs(type(s.next) == "table" and s.next or {}) do
		if (n.level or 99) <= you then due[#due + 1] = (n.name or "?") .. (n.rank and (" (rank " .. n.rank .. ")") or "") end
	end
	-- Forever's spellbook lists nothing coming (seen in game): the trainer's kept list says instead.
	local fromTrainer = false
	if #due == 0 and ns.Trainer then
		local ok, p = pcall(ns.Trainer.Plan)
		for _, t in ipairs(ok and p and p.due or {}) do due[#due + 1] = ns.Trainer.Label(t) end
		fromTrainer = #due > 0
	end
	if #due == 0 then return {} end
	if fromTrainer then
		local shown = table.concat(due, ", ", 1, math.min(3, #due)) .. (#due > 3 and (" and " .. (#due - 3) .. " more") or "")
		return { { kind = "spells", key = "spells:" .. you,
			title = (#due == 1 and "A spell" or (#due .. " spells")) .. " to train",
			text = ns.Escape(shown),
			ask = "My class trainer has " .. table.concat(due, ", ") .. " for me now. Which are worth it first if gold is short, and which trainer is closest?" } }
	end
	local shown = table.concat(due, ", ", 1, math.min(3, #due)) .. (#due > 3 and (" and " .. (#due - 3) .. " more") or "")
	return { { kind = "spells", key = "spells:" .. you,
		title = (#due == 1 and "A spell" or (#due .. " spells")) .. " to train",
		text = ns.Escape(shown),
		ask = "I can train " .. table.concat(due, ", ") .. " now. Which are worth it, roughly what do they cost, and where's my trainer?" } }
end

function Detect.durability()
	local g = Part("gear")
	local worst, slot
	for _, it in ipairs(type(g.items) == "table" and g.items or {}) do
		if type(it.dur) == "table" and (tonumber(it.dur[2]) or 0) > 0 then
			local pct = math.floor(it.dur[1] / it.dur[2] * 100 + 0.5)
			if not worst or pct < worst then worst, slot = pct, it.slot end
		end
	end
	if not worst or worst >= N.DURABILITY_LOW then return {} end
	local where = N.SLOT_NAMES[slot] or "gear"
	return { { kind = "durability", key = "durability",
		title = "Gear about to break",
		text = "Your " .. where .. " is at " .. worst .. "%.",
		ask = "My " .. where .. " is at " .. worst .. "% durability. Where's the nearest place to repair from here?" } }
end

function Detect.bags()
	local b = Part("bags")
	local free = tonumber(b.free)
	if not free or not b.slots then return {} end
	if free > N.BAGS_OK then Seen().bags = nil end -- cleared: it may nudge again when they fill
	if free > N.BAGS_LOW then return {} end
	local junk = type(b.junk) == "table" and (b.junk.n or 0) > 0 and (" " .. b.junk.n .. " grey item" .. (b.junk.n > 1 and "s" or "") .. " to sell.") or ""
	return { { kind = "bags", key = "bags", title = "Bags nearly full",
		text = free .. " slot" .. (free == 1 and "" or "s") .. " free." .. junk,
		ask = "My bags are nearly full (" .. free .. " free). What should I sell, bank or destroy first?" } }
end

-- A quest that became ready to turn in this session (not the ones already ready at login).
function Detect.turnin()
	local q = Part("quests")
	local first = R.nudgeComplete == nil
	local was = R.nudgeComplete or {}
	local now, out = {}, {}
	for _, it in ipairs(type(q.list) == "table" and q.list or {}) do
		if it.complete then
			now[it.id] = true
			if not first and not was[it.id] then
				out[#out + 1] = { kind = "turnin:" .. it.id, key = "done", title = "Ready to turn in",
					text = ns.Escape(it.title or "A quest"),
					ask = "My quest " .. (it.title or "") .. " is ready to turn in. Where do I turn it in, and what comes after it?" }
			end
		end
	end
	R.nudgeComplete = now
	return out
end

-- A ready quest's turn-in nearby: the game's distance to a completed quest is to where it's
-- handed in. Within NEAR_YD, once; again only after going further than FAR_YD away.
N.NEAR_YD, N.FAR_YD = 150, 400
N.NEAR_EVERY = 5 -- seconds
function Detect.near()
	local q = Part("quests")
	local out = {}
	local seen = Seen()
	local ready = false
	for _, it in ipairs(type(q.list) == "table" and q.list or {}) do
		if it.complete then ready = true end
		if it.complete and ns.Quests then
			local info = ns.Quests.Read(it.id)
			local dist = info and info.dist
			local kind = "near:" .. it.id
			if dist and dist > N.FAR_YD then seen[kind] = nil end
			if dist and dist <= N.NEAR_YD then
				local dir = ns.Quests.Direction(info.where)
				out[#out + 1] = { kind = kind, key = "near", title = "Turn-in nearby",
					text = ns.Escape(info.title or it.title or "A quest") .. ": about " .. dist .. " yd" .. (dir and (" " .. dir) or ""),
					ask = "I'm near where " .. (info.title or "my quest") .. " is turned in. Who exactly do I hand it to, and what comes after it?" }
			end
		end
	end
	R.nudgeHasReady = ready -- the 5 s look runs only while one is ready
	return out
end

function Detect.prof()
	local s = Part("skills")
	local out = {}
	for _, p in ipairs(type(s.prof) == "table" and s.prof or {}) do
		-- The same rules as the Professions tab (the review: the nudge waited for the cap while the tab
		-- said "train now", and urged a rank the level didn't allow yet).
		local rank, max = tonumber(p.rank) or 0, tonumber(p.max) or 0
		local nr = ns.Professions and ns.Professions.NextRank(rank, max)
		local name = p.name or "A profession"
		local near = max > 0 and rank >= max - N.PROF_NEAR -- only near the cap: the tab says "train now" before then
		if near and type(nr) == "table" and nr.ready then
			out[#out + 1] = { kind = "prof:" .. name, key = "ready:" .. max, title = ns.Escape(name) .. ": " .. nr.name .. " ready",
				text = "Train it at a " .. ns.Escape(name) .. " trainer.",
				ask = "I can train " .. nr.name .. " " .. name .. " now. Where's the nearest trainer, and what should I make next to level it?" }
		elseif near and type(nr) == "table" and nr.needLevel then
			out[#out + 1] = { kind = "prof:" .. name, key = "cap:" .. max, title = ns.Escape(name) .. " stops at " .. max,
				text = "Until level " .. nr.level .. ", when you can train " .. nr.name .. ".",
				ask = "My " .. name .. " is at " .. rank .. " of " .. max .. " and I can't train " .. nr.name .. " until level " .. nr.level .. ". What's worth doing with it meanwhile?" }
		end
	end
	return out
end

-- A class questline open at your level (the player, 2026-11-20): one nudge for all of them, again only
-- when one more opens (a new level). The Quests tab lists them, with Route.
function Detect.classq()
	local DG = ns.Dungeons
	local lines = DG and DG.ClassLines and DG.ClassLines()
	if not lines then return {} end
	local open, keys = {}, {}
	for _, l in ipairs(lines) do
		if not l.current.at and not l.current.inLog then open[#open + 1] = l; keys[#keys + 1] = l.current.id end
	end
	if #open == 0 then return {} end
	table.sort(keys)
	local first = open[1]
	return { { kind = "classq", key = table.concat(keys, ","),
		title = #open == 1 and "Class quest ready" or (#open .. " class quests ready"),
		text = ns.Escape(first.name) .. (first.current.from and (": " .. ns.Escape(first.current.from)) or "")
			.. (#open > 1 and (", and " .. (#open - 1) .. " more") or "") .. ". The Quests tab plans the way.",
		ask = "My class quest " .. first.name .. " is open (" .. first.current.name .. (first.current.from and (", from " .. first.current.from) or "")
			.. "). What does it give my class, where do I start it, and is it worth doing now?" } }
end

N.ORDER = { "dungeon", "talents", "spells", "classq", "durability", "bags", "turnin", "near", "prof" }

---------------------------------------------------------------------------
-- The queue
---------------------------------------------------------------------------

local function Queue()
	R.nudges = R.nudges or {}
	return R.nudges
end

-- The ones still to see: not asked or opened yet (an asked one stays in the list until dismissed, but doesn't
-- toast again or count on the badge).
local function Pending()
	local out = {}
	for _, n in ipairs(Queue()) do if not n.asked and not n.opened then out[#out + 1] = n end end
	return out
end

-- The queue changed: the minimap badge, and the Advisor panel's Nudges tab. With nothing left to
-- see, a faded toast's state goes, so the next nudge toasts again.
local function Changed()
	local pending = #Pending()
	if pending == 0 then R.nudgeFaded = nil end
	if ns.MinimapButton and ns.MinimapButton.Dot then ns.MinimapButton.Dot(pending) end
	if ns.Panel and ns.Panel.NudgesChanged then ns.Panel.NudgesChanged() end
end

-- The kinds off unless the player turns them on: with Questie loaded, a quest ready to turn in and
-- its turn-in nearby are already on its map and tracker (the player found them chatty, 2026-11-12).
N.QUESTIE_OFF = { turnin = true, near = true }
function N.DefaultOn(name)
	if N.QUESTIE_OFF[name] then
		local AO = rawget(_G, "C_AddOns")
		local loaded = (AO and type(AO.IsAddOnLoaded) == "function" and ns.Try(AO.IsAddOnLoaded, "Questie"))
			or (type(rawget(_G, "IsAddOnLoaded")) == "function" and ns.Try(IsAddOnLoaded, "Questie"))
		if loaded then return false end
	end
	return true
end

-- One kind of nudge on or off (the Settings tab): SpellmindDB.nudges.kinds[name] = true or false
-- once the player picks; else its default.
function N.KindOn(name)
	local k = Saved().kinds
	if type(k) == "table" and k[name] ~= nil then return k[name] == true end
	return N.DefaultOn(name)
end

function N.SetKind(name, on)
	local saved = Saved()
	if type(saved.kinds) ~= "table" then saved.kinds = {} end
	saved.kinds[name] = on and true or false
	if not on then
		-- Its waiting ones go ("turnin:297" is a turnin).
		local q, keep = Queue(), {}
		for _, n in ipairs(q) do
			local base = tostring(n.kind):match("^([^:]+)")
			if base ~= name then keep[#keep + 1] = n end
		end
		R.nudges = keep
		if toast and toast.nudge and tostring(toast.nudge.kind):match("^([^:]+)") == name then toast.nudge = nil; toast:Hide() end
		Changed()
		N.Next()
	else
		N.Check()
	end
end

-- Every detector, in order; a new situation (kind with a key it hasn't shown) joins the queue.
-- only: one kind's detector alone (the 5 s turn-in look); else every kind that's on. Not in combat
-- (the review: a full scan two seconds after every loot): it runs when the fight ends.
function N.Check(only)
	if not N.On() then return end
	if Fighting() then R.nudgeCheckLater = true; return end
	local seen = Seen()
	local q = Queue()
	local byKind = {}
	for _, n in ipairs(q) do byKind[n.kind] = n end
	local present, ran = {}, {}
	for _, name in ipairs(N.ORDER) do
		if (not only or only == name) and N.KindOn(name) then
			ran[name] = true
			local ok, list = pcall(Detect[name])
			for _, n in ipairs(ok and type(list) == "table" and list or {}) do
				n.icon = N.ICONS[name]
				present[n.kind] = true
				local had = byKind[n.kind]
				if had then
					-- The situation changed while it waited (two points to spend now, not one): it says so.
					if had.key ~= n.key and seen[n.kind] ~= n.key then
						had.key, had.title, had.text, had.ask, had.asked, had.opened = n.key, n.title, n.text, n.ask, nil, nil
						R.nudgeFaded = nil
					end
				elseif seen[n.kind] ~= n.key then
					q[#q + 1] = n
					byKind[n.kind] = n
					R.nudgeFaded = nil -- something new: the toast shows again
				end
			end
		end
	end
	-- Resolved (the review: the point spent, the gear repaired, the dungeon left, yet the toast, the
	-- badge and the list kept it): a kind whose detector ran and no longer reports it goes. And its
	-- "seen" is forgotten, so when it comes back it nudges again (gear about to break, next week).
	local keep, removed = {}, false
	for _, n in ipairs(q) do
		local base = tostring(n.kind):match("^([^:]+)")
		if ran[base] and not present[n.kind] then
			removed = true
			if toast and toast.nudge == n then toast.nudge = nil; toast:Hide() end
		else
			keep[#keep + 1] = n
		end
	end
	for kind in pairs(seen) do
		local base = tostring(kind):match("^([^:]+)")
		-- "near" keeps its own rule: forgotten only once you're far away (Detect.near), not as you step out.
		if ran[base] and not present[kind] and base ~= "near" then seen[kind] = nil end
	end
	if removed then
		R.nudges = keep
		Changed()
	end
	N.Next()
end

function N.Soon()
	if R.nudgeTimer then return end
	R.nudgeTimer = true
	C_Timer.After(N.THROTTLE, function()
		R.nudgeTimer = nil
		N.Check()
	end)
end

local function InCombat()
	return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

-- The first nudge still to see on show, unless one is showing, it faded, or in combat.
function N.Next()
	Changed()
	if not N.On() or InCombat() or R.nudgeGap or R.nudgeFaded then return end
	-- The first-time welcome is open: the nudges wait for it (Welcome.lua calls Next when it closes).
	if ns.Welcome and ns.Welcome.IsOpen and ns.Welcome.IsOpen() then return end
	local f = N.Build()
	local pending = Pending()
	if f:IsShown() and f.nudge then
		-- One is showing: only its count of the ones waiting behind it changes.
		f.count:SetText(#pending > 1 and ("+" .. (#pending - 1) .. " more") or "")
		return
	end
	local n = pending[1]
	if not n then return end
	f.nudge = n
	f.icon:SetTexture(n.icon)
	f.title:SetText(n.title)
	f.text:SetText(n.text or "")
	f.count:SetText(#pending > 1 and ("+" .. (#pending - 1) .. " more") or "")
	f:SetAlpha(1)
	f:Show()
	f.shownAt = GetTime()
	N.ArmFade()
end

-- After FADE_AFTER seconds the toast fades out but its nudge keeps waiting (the minimap dot); a
-- mouse over it holds it. Each showing has its own timer, so an old one can't fade a newer toast.
function N.ArmFade(delay)
	R.nudgeShowing = (R.nudgeShowing or 0) + 1
	local id = R.nudgeShowing
	C_Timer.After(delay or N.FADE_AFTER, function()
		local f = toast
		if not f or id ~= R.nudgeShowing or not f:IsShown() or not f.nudge then return end
		if f.IsMouseOver and f:IsMouseOver() then N.ArmFade(5) return end
		N.Fade()
	end)
end

function N.Fade()
	local f = toast
	if not f then return end
	R.nudgeFaded = true
	if type(UIFrameFadeOut) == "function" then
		UIFrameFadeOut(f, N.FADE_TIME, f:GetAlpha() or 1, 0)
		C_Timer.After(N.FADE_TIME, function() if R.nudgeFaded then f:Hide(); f:SetAlpha(1) end end)
	else
		f:Hide()
	end
	f.nudge = nil
	Changed()
end

-- The minimap button's dot, clicked: the waiting nudge back on show.
function N.Bring()
	R.nudgeFaded = nil
	R.nudgeGap = nil
	if toast and toast:IsShown() and not toast.nudge then toast:Hide() end
	N.Next()
end

-- What's still to see, for the minimap button's tooltip.
function N.Waiting()
	local out = {}
	for _, n in ipairs(Pending()) do out[#out + 1] = n.title end
	return out
end

-- Every nudge in the list (the Advisor panel's Nudges tab), asked ones too: { kind, title, text, icon, asked }.
function N.List()
	local out = {}
	for _, n in ipairs(Queue()) do out[#out + 1] = { kind = n.kind, title = n.title, text = n.text, icon = n.icon, asked = n.asked } end
	return out
end

local function Find(kind)
	for i, n in ipairs(Queue()) do if n.kind == kind then return i, n end end
end

-- The toast off (asked or dismissed from it or the list), and the next after a short gap.
local function ToastOff(n)
	local f = toast
	if not f or f.nudge ~= n then return end
	f.nudge = nil
	f:Hide()
	R.nudgeGap = true
	C_Timer.After(N.GAP, function() R.nudgeGap = nil; N.Next() end)
end

-- Dismissed (from the toast or the list): out of the list, and not back for this situation.
function N.DoneKind(kind)
	local i, n = Find(kind)
	if not i then return nil end
	Seen()[n.kind] = n.key
	table.remove(Queue(), i)
	ToastOff(n)
	N.Next()
	return n
end

-- Asked (from the toast or the list): its question sent, its answer in the card beside anchor. It
-- stays in the list, marked asked, until it's dismissed; it doesn't toast again.
function N.AskKind(kind, anchor, opts)
	local _, n = Find(kind)
	if not n then return end
	n.asked = true
	Seen()[n.kind] = n.key
	ToastOff(n)
	N.Next()
	if ns.Marks then ns.Marks.Ask(anchor, "Nudge: " .. n.title, n.ask, opts) end
end

-- The panel tab each kind of nudge is about (seen in game: "5 spells to train" should lead to
-- the Spells tab). The demo has none.
N.TABS = { talents = "talents", spells = "spells", classq = "quests", durability = "gear", bags = "gear", turnin = "quests",
	near = "quests", prof = "professions", dungeon = "dungeons" }
function N.TabFor(kind)
	return N.TABS[tostring(kind):match("^([^:]+)") or ""]
end

-- Opened (a click on the toast, or Open in the list): its tab shows. Seen, like Ask: it doesn't
-- toast again, and stays in the list until it's dismissed or no longer applies.
function N.OpenKind(kind)
	local _, n = Find(kind)
	local tab = n and N.TabFor(n.kind)
	if not tab or not ns.Panel then return nil end
	n.opened = true
	Seen()[n.kind] = n.key
	ToastOff(n)
	N.Next()
	ns.Panel.Show(tab)
	return tab
end

-- The toast's own buttons.
function N.Open()
	local f = toast
	if f and f.nudge then return N.OpenKind(f.nudge.kind) end
end

function N.Done()
	local f = toast
	if f and f.nudge then N.DoneKind(f.nudge.kind) end
end

function N.Ask()
	local f = toast
	if f and f.nudge then N.AskKind(f.nudge.kind, f, { side = "left" }) end
end


---------------------------------------------------------------------------
-- The toast
---------------------------------------------------------------------------

local function Button(f, label, w)
	local b = CreateFrame("Button", nil, f, "BackdropTemplate")
	b:SetSize(w, 20)
	if b.SetBackdrop then
		b:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
		b:SetBackdropColor(0.08, 0.06, 0.16, 0.95)
		b:SetBackdropBorderColor(0.58, 0.45, 0.98, 1)
	end
	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
	b.text:SetText(label)
	b:SetScript("OnEnter", function(self) if self.SetBackdropBorderColor then self:SetBackdropBorderColor(0.85, 0.68, 0.25, 1) end end)
	b:SetScript("OnLeave", function(self) if self.SetBackdropBorderColor then self:SetBackdropBorderColor(0.58, 0.45, 0.98, 1) end end)
	return b
end

function N.Build()
	if toast then return toast end
	local f = CreateFrame("Frame", "SpellmindNudge", UIParent, "BackdropTemplate")
	f:SetSize(290, 74)
	local saved = Saved()
	local map = rawget(_G, "Minimap")
	if saved.point then f:SetPoint(saved.point, UIParent, saved.relPoint or saved.point, tonumber(saved.x) or 0, tonumber(saved.y) or 0)
	-- Beside the minimap, at its left and level with its top: under it sits the quest tracker
	-- (Questie's, seen in game), which the toast covered.
	elseif map then f:SetPoint("TOPRIGHT", map, "TOPLEFT", -14, 0)
	else f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -240) end
	f:SetFrameStrata("HIGH")
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) self.dragged = true; self:StartMoving() end)
	-- A click (not a drag) opens the tab the nudge is about; the hover says which.
	f:SetScript("OnMouseDown", function(self) self.dragged = nil end)
	f:SetScript("OnMouseUp", function(self, button)
		if button == "LeftButton" and not self.dragged then N.Open() end
		self.dragged = nil
	end)
	f:SetScript("OnEnter", function(self)
		local tab = self.nudge and N.TabFor(self.nudge.kind)
		if not tab or not GameTooltip then return end
		local name = tab
		for _, t in ipairs(ns.Panel and ns.Panel.TABS or {}) do if t.id == tab then name = t.name end end
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText("Click: open the " .. name .. " tab", 1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	f:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		saved.point, saved.relPoint, saved.x, saved.y = point, relPoint, x, y
	end)
	if f.SetBackdrop then
		f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 14, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
		f:SetBackdropColor(0.04, 0.03, 0.09, 0.95)
		f:SetBackdropBorderColor(0.62, 0.49, 1, 1)
	end
	if ns.Window then ns.Window.Fill(f, 4, 0.035, 0.025, 0.08, 0.97); ns.Window.Corners(f, 16) end
	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetSize(32, 32)
	f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -10)
	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 50, -10)
	f.title:SetPoint("TOPRIGHT", f, "TOPRIGHT", -26, -10)
	f.title:SetJustifyH("LEFT")
	f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.text:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)
	f.text:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -26)
	f.text:SetJustifyH("LEFT")
	f.count = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.count:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 10)
	f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	f.close:SetSize(22, 22)
	f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
	-- X hides it for now: still in the list and on the badge (the review: X and Dismiss did the same).
	f.close:SetScript("OnClick", function() N.Fade() end)
	f.ask = Button(f, "Ask", 60)
	f.ask:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 8)
	f.ask:SetScript("OnClick", function() N.Ask() end)
	f.dismiss = Button(f, "Dismiss", 70)
	f.dismiss:SetPoint("RIGHT", f.ask, "LEFT", -6, 0)
	f.dismiss:SetScript("OnClick", function() N.Done() end)
	f:Hide()
	toast = f
	return f
end

function N.Get() return toast end

-- /sm nudges demo: a sample nudge, to see the toast, Ask and the card without waiting for a real one.
function N.Demo()
	Saved().off = nil
	R.demoN = (R.demoN or 0) + 1
	table.insert(Queue(), { kind = "demo:" .. R.demoN, key = "demo", icon = N.ICONS.spells,
		title = "A sample nudge", text = "Real ones come from your character: spells, talents, bags, gear, quests.",
		ask = "What kinds of nudges can Spellmind give me, and when do they show?" })
	-- Something new, like any new nudge: it toasts even after an earlier one faded (seen in game: it
	-- only joined the list).
	R.nudgeGap, R.nudgeFaded = nil, nil
	N.Next()
end

-- /sm nudges reset: every dismissed situation forgotten, and a look now. Returns how many wait.
function N.Reset()
	local me = ns.State and ns.State.Me and ns.State.Me()
	if me then me.nudgeSeen = {} end
	Saved().off = nil
	R.nudges = {}
	R.nudgeGap = nil
	if toast then toast.nudge = nil; toast:Hide() end
	N.Check()
	return #Queue()
end

-- /sm nudges off and on.
function N.SetOn(on)
	Saved().off = not on or nil
	if not on then
		R.nudges = {}
		if toast then toast.nudge = nil; toast:Hide() end
		if ns.MinimapButton and ns.MinimapButton.Dot then ns.MinimapButton.Dot(false) end
	else
		N.Check()
	end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

for _, ev in ipairs({ "PLAYER_LEVEL_UP", "BAG_UPDATE_DELAYED", "UPDATE_INVENTORY_DURABILITY", "QUEST_LOG_UPDATE",
	"SKILL_LINES_CHANGED", "SPELLS_CHANGED", "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE" }) do
	ns.On(ev, function() N.Soon() end)
end
-- Into or out of a dungeon (a loading screen): after the first look only, so login stays quiet.
for _, ev in ipairs({ "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
	ns.On(ev, function() if R.nudgeLooked then N.Soon() end end)
end
-- In combat: hidden; after it, the queue goes on.
-- A fight hides the toast. One that had shown 5 s or more counts as seen: it waits behind the badge
-- instead of coming back after every kill (the review). A look skipped in the fight runs after it.
N.SEEN_AFTER = 5
ns.On("PLAYER_REGEN_DISABLED", function()
	if toast and toast:IsShown() then
		if toast.nudge and GetTime() - (toast.shownAt or 0) >= N.SEEN_AFTER then
			R.nudgeFaded = true
			toast.nudge = nil
		end
		toast:Hide()
	end
end)
ns.On("PLAYER_REGEN_ENABLED", function()
	if R.nudgeCheckLater then R.nudgeCheckLater = nil; N.Check() else N.Next() end
end)
ns.On("PLAYER_LOGIN", function()
	-- A few seconds in, once the game's data has settled (the quest log, the spellbook).
	C_Timer.After(8, function() R.nudgeLooked = true; N.Check() end)
	-- Moving fires no event: every 5 s, a look for turn-ins nearby (only while a quest is ready).
	-- Only that kind's own look, only when it's on and a quest is ready (the review: a full scan every
	-- 5 s for the whole session, even with it off).
	C_Timer.NewTicker(N.NEAR_EVERY, function()
		if not N.On() or InCombat() or not N.KindOn("near") or not R.nudgeHasReady then return end
		N.Check("near")
	end)
end)
