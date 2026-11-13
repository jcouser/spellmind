-- Guide.lua: the player's guide (docs/milestone-15.md). They give a link once (/sm guide <link>, or
-- Set in the Talents tab or Settings); Import sends "Import my guide: <link>" with guide=1, the app's
-- AI reads the page and the reply brings its build back as a plan:
--   SpellmindDB.chars[key].guide = { url, at, plan = { title, build, builds, talents = { { level, name,
--   rank } }, rotation, stats, weapons, source } }
-- Tracking it is local: the next points against the character's own talents, points spent off the
-- plan, and the plan's talent names checked against the tree (a name it can't find is shown, never
-- quietly followed).
--
-- Read only: nothing is learned or spent; the player does that.

local _, ns = ...
local GD = {}
ns.Guide = GD

GD.NEXT_MAX = 4

local function Me() return ns.State and ns.State.Me and ns.State.Me() or nil end
local function Level() return tonumber((ns.Try(UnitLevel, "player"))) or 1 end

function GD.Get()
	local me = Me()
	local g = me and me.guide
	return type(g) == "table" and g or nil
end

-- A link the player gave: https, one line, not too long. Returns it, or nil.
function GD.CleanUrl(text)
	local url = tostring(text or ""):match("(https://[^%s|<>\"']+)")
	if not url or #url > 300 then return nil end
	-- No login in a link ("user:pw@host"): the app refuses those too (the privacy review).
	if url:match("^https://[^/]*@") then return nil end
	url = url:gsub("#.*$", "")
	return (url:gsub("[%).,;]+$", ""))
end

-- "mobalytics.gg".
function GD.Host(url)
	local h = tostring(url or ""):match("^https://([^/]+)")
	return h and h:gsub("^www%.", "") or nil
end

function GD.SetUrl(url)
	local me = Me()
	if not me then return nil end
	url = GD.CleanUrl(url)
	if not url then return nil end
	me.guide = type(me.guide) == "table" and me.guide or {}
	if me.guide.url ~= url then me.guide.plan, me.guide.at = nil, nil end
	me.guide.url = url
	return url
end

-- Ask the app to read the guide (a build by name, or the page's main one). anchor: where the answer
-- card opens (the Spellmind window); without one, the answer goes to the chat.
function GD.Import(build, anchor)
	local g = GD.Get()
	if not g or not g.url then return nil, "Set your guide's link first." end
	local text = "Import my guide: " .. g.url .. (build and ("\nBuild: " .. tostring(build):sub(1, 60)) or "")
	local label = "Import " .. (build and (build .. " from ") or "") .. (GD.Host(g.url) or "your guide")
	if anchor and ns.Marks then return ns.Marks.Ask(anchor, label, text, { args = { { "guide", 1 } } }) end
	return ns.Chat.Send(text, { shown = ns.Escape(label), args = { { "guide", 1 } } })
end

-- The reply's plan: kept, its names checked, the Talents tab and the nudge brought up to date.
function GD.OnPlan(plan)
	local me = Me()
	if not me or type(plan) ~= "table" then return end
	local talents = {}
	for _, t in ipairs(type(plan.talents) == "table" and plan.talents or {}) do
		local level, rank = tonumber(t.level), tonumber(t.rank)
		if type(t.name) == "string" and level and rank then talents[#talents + 1] = { level = level, name = t.name, rank = rank } end
	end
	local function strings(list)
		local out = {}
		for _, s in ipairs(type(list) == "table" and list or {}) do if type(s) == "string" then out[#out + 1] = s end end
		return out
	end
	me.guide = type(me.guide) == "table" and me.guide or {}
	me.guide.url = type(plan.url) == "string" and plan.url ~= "" and plan.url or me.guide.url
	me.guide.at = time()
	me.guide.plan = { title = plan.title, build = plan.build, builds = strings(plan.builds), talents = talents,
		rotation = strings(plan.rotation), stats = strings(plan.stats), weapons = type(plan.weapons) == "string" and plan.weapons or nil,
		source = plan.source }
	if ns.State and ns.State.Dirty then ns.State.Dirty() end
	if ns.Nudges and ns.Nudges.Soon then ns.Nudges.Soon() end
	if ns.Panel and ns.Panel.Get() and ns.Panel.Get():IsShown() and (ns.Panel.tab == "talents" or ns.Panel.tab == "spells") then ns.Panel.Show(ns.Panel.tab, true) end
end

-- The character's talents now: { [name] = rank }.
local function Current()
	local out = {}
	local t = ns.State and ns.State.Collect and select(2, pcall(ns.State.Collect.talents))
	for _, kv in ipairs(type(t) == "table" and t._o or {}) do
		if kv[1] == "nodes" then
			for _, n in ipairs(kv[2] or {}) do
				local f = {}
				for _, x in ipairs(n._o or {}) do f[x[1]] = x[2] end
				if f.name then out[f.name] = math.max(out[f.name] or 0, tonumber(f.r) or 0) end
			end
		end
	end
	return out
end

-- Where the character stands against the plan:
--   next     the next steps not taken, in the plan's order (at most NEXT_MAX), each { level, name,
--            rank, now (its level is reached: with no point to spend, it's one you're behind on) }
--   behind   how many steps at or below your level aren't taken
--   early    talents taken before the guide's level for them: { name, rank, from, to } (its levels)
--   off      talents with points the plan doesn't give them: { name, have, plan }
--   unknown  plan names the tree doesn't have (only when the client lists the tree)
--   done, total
function GD.Progress(have)
	local g = GD.Get()
	local plan = g and g.plan
	if type(plan) ~= "table" or type(plan.talents) ~= "table" or #plan.talents == 0 then return nil end
	local level = Level()
	have = have or Current()
	local out = { next = {}, off = {}, unknown = {}, early = {}, behind = 0, done = 0, total = #plan.talents }
	local planned, early = {}, {}
	for _, s in ipairs(plan.talents) do
		planned[s.name] = math.max(planned[s.name] or 0, s.rank)
		if (have[s.name] or 0) >= s.rank then
			out.done = out.done + 1
			-- Taken before the guide's level for it (seen in game: 8 points, not the guide's first 8).
			if s.level > level then
				local e = early[s.name]
				if not e then
					e = { name = s.name, rank = s.rank, from = s.level, to = s.level }
					early[s.name] = e
					out.early[#out.early + 1] = e
				end
				e.rank, e.to = math.max(e.rank, s.rank), math.max(e.to, s.level)
			end
		else
			if s.level <= level then out.behind = out.behind + 1 end
			if #out.next < GD.NEXT_MAX then
				out.next[#out.next + 1] = { level = s.level, name = s.name, rank = s.rank, now = s.level <= level }
			end
		end
	end
	for name, r in pairs(have) do
		if r > (planned[name] or 0) then out.off[#out.off + 1] = { name = name, have = r, plan = planned[name] or 0 } end
	end
	table.sort(out.off, function(a, b) return a.name < b.name end)
	local tree = ns.State.AllTalents and ns.State.AllTalents() or {}
	if next(tree) then
		local seen = {}
		for _, s in ipairs(plan.talents) do
			if not tree[s.name] and not seen[s.name] then seen[s.name] = true; out.unknown[#out.unknown + 1] = s.name end
		end
	end
	return out
end

-- The next step's words: "Remorseless Attacks 1/2" (the tree's top rank when the client lists it,
-- else the plan's).
function GD.StepText(s, tree)
	local max = (type(tree) == "table" and tree[s.name]) or GD.MaxRank(s.name)
	return (s.name or "?") .. " " .. (s.rank or "?") .. "/" .. (max or "?")
end

-- A talent's top rank in the plan (what "1/2" counts to).
function GD.MaxRank(name)
	local g = GD.Get()
	local top
	for _, s in ipairs(g and g.plan and g.plan.talents or {}) do
		if s.name == name then top = math.max(top or 0, s.rank) end
	end
	return top
end

-- The guide's ability priority against the spellbook (docs/milestone-16.md): for each step, the
-- ability it names that you have ({ have = name }), or one your class trainer teaches later
-- ({ train = name, level }), or neither. The longest name found in the step wins ("Slice and Dice"
-- over "Slice"). Talents with an ability (Riposte) are in the spellbook once taken.
function GD.Priority()
	local g = GD.Get()
	local plan = g and g.plan
	if type(plan) ~= "table" or type(plan.rotation) ~= "table" then return {} end
	local book = {}
	local s = ns.State and ns.State.Collect and select(2, pcall(ns.State.Collect.spells))
	for _, kv in ipairs(type(s) == "table" and s._o or {}) do
		if kv[1] == "tabs" then
			for _, tab in ipairs(kv[2] or {}) do
				for _, f in ipairs(tab._o or {}) do
					if f[1] == "list" then
						for _, sp in ipairs(f[2] or {}) do
							for _, x in ipairs(sp._o or {}) do if x[1] == "name" and type(x[2]) == "string" then book[x[2]] = true end end
						end
					end
				end
			end
		end
	end
	local trainer = {}
	local me = Me()
	for _, sv in ipairs(me and me.trainer and me.trainer.services or {}) do
		if type(sv.name) == "string" and not book[sv.name] then
			local lvl = tonumber(sv.level) or 0
			if not trainer[sv.name] or lvl < trainer[sv.name] then trainer[sv.name] = lvl end
		end
	end
	local out = {}
	for _, line in ipairs(plan.rotation) do
		local low = tostring(line):lower()
		local best, bestKind, bestLevel
		local function try(name, kind, level)
			if #name >= 3 and low:find(name:lower(), 1, true) and (not best or #name > #best) then best, bestKind, bestLevel = name, kind, level end
		end
		for name in pairs(book) do try(name, "have") end
		for name, lvl in pairs(trainer) do try(name, "train", lvl) end
		out[#out + 1] = { line = line, have = bestKind == "have" and best or nil, train = bestKind == "train" and best or nil, level = bestLevel }
	end
	return out
end

-- For the talents part (State.lua): the AI follows the player's guide in its answers.
function GD.ForState(have)
	local g = GD.Get()
	local plan = g and g.plan
	if type(plan) ~= "table" then return nil end
	local O = ns.State.JSON.O
	local p = GD.Progress(have)
	local nextList = {}
	local tree = ns.State.AllTalents and ns.State.AllTalents() or {}
	for _, s in ipairs(p and p.next or {}) do nextList[#nextList + 1] = GD.StepText(s, tree) end
	local function cap(list, n)
		local out = {}
		for i, s in ipairs(list or {}) do if i <= n then out[#out + 1] = s end end
		return #out > 0 and out or nil
	end
	return O("build", plan.build, "source", plan.source, "next", cap(nextList, 4), "stats", cap(plan.stats, 8),
		"rotation", cap(plan.rotation, 8), "weapons", plan.weapons)
end

---------------------------------------------------------------------------
-- The link box: a line to paste the guide's link into (Ctrl+V)
---------------------------------------------------------------------------

function GD.AskLink(anchor)
	local f = GD.box
	if not f then
		f = CreateFrame("Frame", "SpellmindGuideBox", UIParent, "BackdropTemplate")
		f:SetSize(420, 96)
		f:SetFrameStrata("FULLSCREEN_DIALOG")
		if f.SetBackdrop then
			f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
				tile = true, tileSize = 16, edgeSize = 14, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
			f:SetBackdropColor(0.05, 0.04, 0.1, 0.98)
			f:SetBackdropBorderColor(0.62, 0.49, 1, 1)
		end
		f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
		f.title:SetText("Your guide's link (paste it with Ctrl+V)")
		f.input = CreateFrame("EditBox", nil, f, "BackdropTemplate")
		f.input:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -30)
		f.input:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -30)
		f.input:SetHeight(24)
		if f.input.SetBackdrop then
			f.input:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
				tile = true, tileSize = 16, edgeSize = 10, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
			f.input:SetBackdropColor(0.07, 0.05, 0.14, 0.95)
			f.input:SetBackdropBorderColor(0.5, 0.4, 0.85, 1)
		end
		f.input:SetFontObject(ChatFontNormal)
		f.input:SetTextInsets(6, 6, 0, 0)
		f.input:SetAutoFocus(false)
		f.input:SetMaxBytes(301)
		f.input:SetScript("OnEscapePressed", function() f:Hide() end)
		f.input:SetScript("OnEnterPressed", function() GD.SaveBox() end)
		f.ok = ns.GearUI.Button(f, "Import", 100)
		f.ok:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 10)
		f.ok:SetScript("OnClick", function() GD.SaveBox() end)
		f.cancel = ns.GearUI.Button(f, "Cancel", 80)
		f.cancel:SetPoint("RIGHT", f.ok, "LEFT", -8, 0)
		f.cancel:SetScript("OnClick", function() f:Hide() end)
		f.note = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		f.note:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 14)
		f.note:SetText("Your AI reads the page.")
		f:Hide()
		GD.box = f
	end
	local g = GD.Get()
	f.input:SetText(g and g.url or "")
	f.anchor = anchor
	f:ClearAllPoints()
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
	f:Show()
	f.input:SetFocus()
	if f.input.HighlightText then f.input:HighlightText() end
	return f
end

function GD.SaveBox()
	local f = GD.box
	if not f then return end
	local url = GD.SetUrl(f.input:GetText())
	if not url then
		f.note:SetText("|cffff6060That isn't an https:// link.|r")
		return
	end
	f:Hide()
	GD.Import(nil, f.anchor)
end
