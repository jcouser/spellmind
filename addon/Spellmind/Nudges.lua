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
	prof = "Interface\\Icons\\INV_Misc_Note_01",
}
N.SLOT_NAMES = { "head", "neck", "shoulders", "shirt", "chest", "waist", "legs", "feet", "wrists", "hands", "ring", "ring",
	"trinket", "trinket", "back", "main hand", "off hand", "ranged", "tabard" }

local toast

local function Saved()
	local db = ns.db
	if not db then return { seen = {} } end
	if type(db.nudges) ~= "table" then db.nudges = {} end
	if type(db.nudges.seen) ~= "table" then db.nudges.seen = {} end
	return db.nudges
end

function N.On()
	return ns.db ~= nil and Saved().off ~= true
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

function Detect.talents()
	local t = Part("talents")
	local n = tonumber(t.unspent) or 0
	if n <= 0 then return {} end
	return { { kind = "talents", key = "talents:" .. n .. ":" .. (ns.State.Whole(ns.Try(UnitLevel, "player")) or 0),
		title = n == 1 and "A talent point to spend" or (n .. " talent points to spend"),
		text = "Want a pick for your build?",
		ask = "I have " .. n .. " talent point" .. (n > 1 and "s" or "") .. " to spend. What should I take, and why?" } }
end

function Detect.spells()
	local s = Part("spells")
	local you = ns.State.Whole(ns.Try(UnitLevel, "player")) or 1
	local due = {}
	for _, n in ipairs(type(s.next) == "table" and s.next or {}) do
		if (n.level or 99) <= you then due[#due + 1] = (n.name or "?") .. (n.rank and (" (rank " .. n.rank .. ")") or "") end
	end
	if #due == 0 then return {} end
	local shown = table.concat(due, ", ", 1, math.min(3, #due)) .. (#due > 3 and (" and " .. (#due - 3) .. " more") or "")
	return { { kind = "spells", key = "spells:" .. you .. ":" .. #due,
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
	if free > N.BAGS_OK then Saved().seen.bags = nil end -- cleared: it may nudge again when they fill
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

function Detect.prof()
	local s = Part("skills")
	local out = {}
	for _, p in ipairs(type(s.prof) == "table" and s.prof or {}) do
		local rank, max = tonumber(p.rank) or 0, tonumber(p.max) or 0
		if max > 0 and max < 300 and rank >= max - N.PROF_NEAR then
			out[#out + 1] = { kind = "prof:" .. (p.name or "?"), key = tostring(max), title = ns.Escape(p.name or "A profession") .. " near its cap",
				text = rank .. " of " .. max .. ": train the next rank to keep going.",
				ask = "My " .. (p.name or "profession") .. " is at " .. rank .. " of " .. max .. ". Where do I train the next rank, and what does it need?" }
		end
	end
	return out
end

N.ORDER = { "talents", "spells", "durability", "bags", "turnin", "prof" }

---------------------------------------------------------------------------
-- The queue
---------------------------------------------------------------------------

local function Queue()
	R.nudges = R.nudges or {}
	return R.nudges
end

-- The queue changed: the minimap badge, and the Advisor panel's Nudges tab.
local function Changed()
	if ns.MinimapButton and ns.MinimapButton.Dot then ns.MinimapButton.Dot(#Queue() > 0) end
	if ns.Panel and ns.Panel.NudgesChanged then ns.Panel.NudgesChanged() end
end

-- Every detector, in order; a new situation (kind with a key it hasn't shown) joins the queue.
function N.Check()
	if not N.On() then return end
	local seen = Saved().seen
	local q = Queue()
	local queued = {}
	for _, n in ipairs(q) do queued[n.kind] = true end
	for _, name in ipairs(N.ORDER) do
		local ok, list = pcall(Detect[name])
		for _, n in ipairs(ok and type(list) == "table" and list or {}) do
			n.icon = N.ICONS[name]
			if seen[n.kind] ~= n.key and not queued[n.kind] then
				q[#q + 1] = n
				queued[n.kind] = true
				R.nudgeFaded = nil -- something new: the toast shows again
			end
		end
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

-- The first waiting nudge on show, unless one is showing or in combat.
function N.Next()
	Changed()
	if not N.On() or InCombat() or R.nudgeGap or R.nudgeFaded then return end
	local f = N.Build()
	if f:IsShown() then
		-- One is showing: only its count of the ones waiting behind it changes.
		local left = #Queue() - 1
		f.count:SetText(left > 0 and ("+" .. left .. " more") or "")
		return
	end
	local n = Queue()[1]
	if not n then return end
	f.nudge = n
	f.icon:SetTexture(n.icon)
	f.title:SetText(n.title)
	f.text:SetText(n.text or "")
	local left = #Queue() - 1
	f.count:SetText(left > 0 and ("+" .. left .. " more") or "")
	f:SetAlpha(1)
	f:Show()
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

-- What waits, for the minimap button's tooltip.
function N.Waiting()
	local out = {}
	for _, n in ipairs(Queue()) do out[#out + 1] = n.title end
	return out
end

-- Every waiting nudge (the Advisor panel's Nudges tab): { kind, title, text, icon }.
function N.List()
	local out = {}
	for _, n in ipairs(Queue()) do out[#out + 1] = { kind = n.kind, title = n.title, text = n.text, icon = n.icon } end
	return out
end

local function Find(kind)
	for i, n in ipairs(Queue()) do if n.kind == kind then return i, n end end
end

-- Done with one from the list, wherever it is in the queue (the toast moves on if it was showing it).
function N.DoneKind(kind)
	local i, n = Find(kind)
	if not i then return nil end
	if toast and toast.nudge == n then N.Done() return n end
	Saved().seen[n.kind] = n.key
	table.remove(Queue(), i)
	N.Next()
	Changed()
	return n
end

-- Asked from the list: its answer in the card beside anchor (the panel).
function N.AskKind(kind, anchor)
	local _, n = Find(kind)
	if not n then return end
	N.DoneKind(kind)
	if ns.Marks then ns.Marks.Ask(anchor, "Nudge: " .. n.title, n.ask) end
end

-- Done with the showing one (asked or dismissed): it won't come back for this situation.
function N.Done()
	local f = toast
	if not f or not f.nudge then return end
	local n = f.nudge
	Saved().seen[n.kind] = n.key
	table.remove(Queue(), 1)
	f.nudge = nil
	f:Hide()
	R.nudgeGap = true
	C_Timer.After(N.GAP, function() R.nudgeGap = nil; N.Next() end)
	Changed()
end

function N.Ask()
	local f = toast
	if not f or not f.nudge then return end
	local n = f.nudge
	local anchor = f
	N.Done()
	if ns.Marks then ns.Marks.Ask(anchor, "Nudge: " .. n.title, n.ask, { side = "left" }) end
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
	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
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
	f.close:SetScript("OnClick", function() N.Done() end)
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
	R.nudgeGap = nil
	N.Next()
end

-- /sm nudges reset: every dismissed situation forgotten, and a look now. Returns how many wait.
function N.Reset()
	Saved().seen = {}
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
-- In combat: hidden; after it, the queue goes on.
ns.On("PLAYER_REGEN_DISABLED", function() if toast and toast:IsShown() then toast:Hide() end end)
ns.On("PLAYER_REGEN_ENABLED", function() N.Next() end)
ns.On("PLAYER_LOGIN", function()
	-- A few seconds in, once the game's data has settled (the quest log, the spellbook).
	C_Timer.After(8, function() N.Check() end)
end)
