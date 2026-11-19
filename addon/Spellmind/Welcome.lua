-- Welcome.lua: the first time Spellmind loads on an account, a short welcome (the player, 2026-11-14:
-- a player who installs the addon from CurseForge only heard of the app by trying the chat or opening
-- Settings). What works with no setup, then the free app with the project's link to copy (the same
-- page as /sm app: the download, its checksums and how to install), or, when the app already talks
-- to the game, that it does.
--
--   once per account (SpellmindDB.welcomed), WELCOME_DELAY s after login, never in combat (it waits);
--   nudges wait while it's open; /sm welcome shows it again.
--
-- And after an update, What's new (the player, 2026-11-19: the route is a big one, and a player who
-- updates wouldn't know it's there): once per version (SpellmindDB.seenVersion), the same way;
-- /sm news shows it again. The words are core/news.mjs's (the app's card after it updates), kept the
-- same by a test.
--
-- Both are one kind of window, an announcement (the maintainer: "more producty"): a headline and a
-- line under it, highlights with icons, then what's particular to each. The welcome's highlights are
-- what's new since the last version players had (WL.FRESH_SINCE: every feature added before the next
-- public release shows there too, the maintainer's ask), then what's always there, then the app.

local _, ns = ...
local WL = {}
ns.Welcome = WL

WL.DELAY = 6 -- seconds after login: the app's first answer to the hello comes in by then
WL.RETRY = 5 -- seconds, while in combat
WL.TITLE = "Welcome to Spellmind"
WL.INTRO = "Your companion for WoW Forever. It knows your character as you play, and says what to do next. Everything here works with no setup at all."
-- The welcome shows the highlights of every version after this one (the last that players had): set it
-- to the version before the one being published (docs/releasing.md).
WL.FRESH_SINCE = "0.4.7"
-- What's always there, after what's new.
WL.BASICS = {
	{ icon = "Interface\\Icons\\INV_Misc_Book_09", title = "A panel that knows your character", text = "Quests, Dungeons, Gear, Talents, Spells, Professions and Gold, each saying what to do next. The minimap button or /sm opens it; right-click the button for your last tab." },
	{ icon = "Interface\\AddOns\\Spellmind\\Media\\Mark", title = "Nudges and tooltips", text = "A quiet nudge by the minimap when spells wait at your trainer, talent points are unspent or gear is about to break, and Spellmind's lines on quest and item tooltips." },
}
WL.APP = "Get the free Spellmind app for Windows, and ask your own AI anything about your character. It works with a ChatGPT plan, or an API key for Claude, ChatGPT, Grok or Gemini, and sends nothing to the Spellmind authors."
WL.CONNECTED = "|cff19ff19The Spellmind app is connected.|r Ask anything in the Chat tab, or click the Spellmind mark on a quest to have it broken down."

local function InCombat()
	return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

local function AppHeard()
	return ns.Link and ns.Link.AppGone and not ns.Link.AppGone() or false
end

function WL.IsOpen()
	return (WL.frame and WL.frame:IsShown() or WL.news and WL.news:IsShown()) and true or false
end

-- Each version's news, oldest first (core/news.mjs, word for word): a headline, a line under it, a few
-- highlights (each with a game icon here), a footnote, and what "Try it now" does; and its changes,
-- plainly (a version can have only those: "What's changed").
WL.NEWS = {
	{ version = "0.5.0", try = "route",
		headline = "Meet your quest route",
		tagline = "Spellmind now plans your leveling for you: built from your own quest log, and kept up to date as you play.",
		features = {
			{ icon = "Interface\\Icons\\INV_Misc_Map_01", title = "A plan that knows your character", text = "Every pickup, objective and turn-in around you, in the shortest order, ticked off the moment you finish it." },
			{ icon = "Interface\\Icons\\Ability_Hunter_Pathfinding", title = "Never lose your way", text = "An arrow on screen points to your next step, and the world map numbers each step and shades where to go." },
			{ icon = "Interface\\Icons\\Ability_Mount_Gryphon_01", title = "The way there, leg by leg", text = "Flight paths you know, the roads between zones, the tram and the boats: the arrow and the map take you there by the fastest way you have." },
			{ icon = "Interface\\Icons\\Spell_Arcane_PortalStormWind", title = "Always know where to go next", text = "When a zone runs dry, Spellmind ranks the best zones for your level, counting your flight paths and hearthstone." },
			{ icon = "Interface\\Icons\\INV_Misc_Key_03", title = "Ready for any dungeon", text = "Pick a dungeon on the Route tab: Spellmind routes you through its quests and the questlines that open them, across zones, to its door." },
			{ icon = "Interface\\AddOns\\Spellmind\\Media\\Portrait", title = "Ask your AI about it", text = "Your AI sees the same route. Ask \"Review my route\" for what to skip, and why." },
		},
		note = "Works best with Questie installed. Find it all in the new Route tab.",
		changes = {
			"The Quests tab's \"Plan my next hour\" is now \"Review my route\".",
			"After each update, this window says what's new. /sm news shows it again.",
			"A quest handed in in another zone is planned as a trip there and back when what it opens here makes it worth it.",
			"The arrow and the map's lines follow the roads you've walked: Spellmind learns them as you go, on your PC only.",
			"A far quest that gives little XP for the walk is marked \"worth skipping?\", and the ones worth more come first.",
			"In a route review, each quest your AI says to skip gets a Skip button.",
		} },
}

-- What each news's "Try it now" does: the route on, and its tab.
WL.TRY = {
	route = function()
		if ns.Route and not ns.Route.On() then ns.Route.SetOn(true) end
		if ns.Panel and ns.Panel.Show then ns.Panel.Show("route") end
	end,
}

local function Parts(v)
	local t = {}
	for n in tostring(v or ""):gmatch("%d+") do t[#t + 1] = tonumber(n) end
	return t
end
-- Is version a newer than b?
function WL.Newer(a, b)
	local x, y = Parts(a), Parts(b)
	for i = 1, math.max(#x, #y) do
		local p, q = x[i] or 0, y[i] or 0
		if p ~= q then return p > q end
	end
	return false
end
-- The news after the version last seen, up to the one running now.
function WL.Since(seen, current)
	local out = {}
	for _, n in ipairs(WL.NEWS) do
		if WL.Newer(n.version, seen or "0") and not WL.Newer(n.version, current) then out[#out + 1] = n end
	end
	return out
end

---------------------------------------------------------------------------
-- The announcement: a window for the welcome and for What's new
---------------------------------------------------------------------------

WL.W, WL.PAD = 560, 22
WL.NEWS_W, WL.NEWS_PAD = WL.W, WL.PAD
local INNER = WL.W - 2 * WL.PAD
local BACK = { bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 14, insets = { left = 4, right = 4, top = 4, bottom = 4 } }

-- The frame: the owl and a small line at the top, the close button, the headline and the line under
-- it; pools for highlights, section labels and change lines.
local function Window(name)
	local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
	f:SetSize(WL.W, 420)
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
	if f.SetBackdrop then
		f:SetBackdrop(BACK)
		f:SetBackdropColor(0.05, 0.04, 0.1, 0.98)
		f:SetBackdropBorderColor(0.62, 0.49, 1, 1)
	end
	if ns.Window and ns.Window.Fill then ns.Window.Fill(f, 4, 0.035, 0.025, 0.08, 0.97) end
	if ns.Window and ns.Window.Corners then ns.Window.Corners(f, 18) end
	f.portrait = f:CreateTexture(nil, "ARTWORK")
	f.portrait:SetSize(24, 24)
	f.portrait:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
	f.portrait:SetTexture(ns.Marks and ns.Marks.PORTRAIT or "Interface\\AddOns\\Spellmind\\Media\\Portrait")
	f.top = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	f.top:SetPoint("LEFT", f.portrait, "RIGHT", 8, 0)
	f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
	f.headline = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	f.headline:SetPoint("TOPLEFT", f, "TOPLEFT", WL.PAD, -52)
	f.headline:SetWidth(INNER)
	f.headline:SetJustifyH("LEFT")
	f.tagline = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.tagline:SetPoint("TOPLEFT", f.headline, "BOTTOMLEFT", 0, -10)
	f.tagline:SetWidth(INNER)
	f.tagline:SetJustifyH("LEFT")
	if f.tagline.SetWordWrap then f.tagline:SetWordWrap(true) end
	if f.tagline.SetSpacing then f.tagline:SetSpacing(3) end
	f.features, f.labels, f.changes = {}, {}, {}
	return f
end

-- One highlight: its icon, its title (gold, larger) and its line.
local function Feature(f, k)
	local row = f.features[k]
	if row then return row end
	row = {}
	row.icon = f:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(34, 34)
	row.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	row.title:SetJustifyH("LEFT")
	row.title:SetWidth(INNER - 48)
	row.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.text:SetJustifyH("LEFT")
	row.text:SetWidth(INNER - 48)
	if row.text.SetWordWrap then row.text:SetWordWrap(true) end
	if row.text.SetSpacing then row.text:SetSpacing(2) end
	f.features[k] = row
	return row
end
local function Label(f, k)
	local l = f.labels[k]
	if l then return l end
	l = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	l:SetJustifyH("LEFT")
	f.labels[k] = l
	return l
end
local function Change(f, k)
	local l = f.changes[k]
	if l then return l end
	l = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	l:SetJustifyH("LEFT")
	l:SetWidth(INNER - 14)
	if l.SetWordWrap then l:SetWordWrap(true) end
	f.changes[k] = l
	return l
end

-- The headline and its line; then the sections ({ label?, features }), each highlight under the last
-- with room between them. Returns the y below them.
local function Fill(f, headline, tagline, sections)
	f.headline:SetText(headline or "")
	f.tagline:SetText(tagline or "")
	if tagline then f.tagline:Show() else f.tagline:Hide() end
	local y = -52 - (tonumber(f.headline:GetStringHeight()) or 22) - 10 - (tagline and (tonumber(f.tagline:GetStringHeight()) or 30) or 0) - 22
	for _, row in ipairs(f.features) do row.icon:Hide(); row.title:Hide(); row.text:Hide() end
	for _, l in ipairs(f.labels) do l:Hide() end
	local k, nl = 0, 0
	for _, sec in ipairs(sections) do
		if #(sec.features or {}) > 0 then
			if sec.label then
				nl = nl + 1
				local l = Label(f, nl)
				l:SetText(sec.label)
				l:ClearAllPoints()
				l:SetPoint("TOPLEFT", f, "TOPLEFT", WL.PAD, y)
				l:Show()
				y = y - 24
			end
			for _, ft in ipairs(sec.features) do
				k = k + 1
				local row = Feature(f, k)
				row.icon:SetTexture(ft.icon)
				row.icon:ClearAllPoints()
				row.icon:SetPoint("TOPLEFT", f, "TOPLEFT", WL.PAD, y)
				row.title:SetText(ft.title)
				row.title:ClearAllPoints()
				row.title:SetPoint("TOPLEFT", f, "TOPLEFT", WL.PAD + 48, y)
				row.text:SetText(ft.text)
				row.text:ClearAllPoints()
				row.text:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -4)
				row.icon:Show(); row.title:Show(); row.text:Show()
				local h = (tonumber(row.title:GetStringHeight()) or 16) + 4 + (tonumber(row.text:GetStringHeight()) or 28)
				y = y - math.max(36, h) - 18
			end
			y = y - 4
		end
	end
	return y
end

local function Center(f, h)
	f:SetHeight(h)
	f:ClearAllPoints()
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
	f:Show()
end

-- The highlights of the news after a version (newest first) and the news they came from.
function WL.FeaturesSince(seen, current)
	local out, newest = {}, nil
	local list = WL.Since(seen, current)
	for k = #list, 1, -1 do
		for _, ft in ipairs(list[k].features or {}) do out[#out + 1] = ft end
		if not newest and list[k].headline then newest = list[k] end
	end
	return out, newest
end

---------------------------------------------------------------------------
-- The welcome: what's new, what's always there, the app
---------------------------------------------------------------------------

local function Build()
	if WL.frame then return WL.frame end
	local f = Window("SpellmindWelcome")
	f.title, f.intro = f.headline, f.tagline
	f.title:SetText(WL.TITLE)
	-- The app: its own highlight (the owl), then the link to copy when it isn't there yet.
	f.appIcon = f:CreateTexture(nil, "ARTWORK")
	f.appIcon:SetSize(34, 34)
	f.appIcon:SetTexture(ns.Marks and ns.Marks.PORTRAIT or "Interface\\AddOns\\Spellmind\\Media\\Portrait")
	f.appTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.appTitle:SetJustifyH("LEFT")
	f.appTitle:SetText("Ask your own AI")
	f.app = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.app:SetWidth(INNER - 48)
	f.app:SetJustifyH("LEFT")
	if f.app.SetWordWrap then f.app:SetWordWrap(true) end
	if f.app.SetSpacing then f.app:SetSpacing(2) end
	-- The project's link, selected to copy; typing can't change it (as in /sm app's box).
	f.link = CreateFrame("EditBox", nil, f, "BackdropTemplate")
	f.link:SetSize(INNER - 48, 24)
	if f.link.SetBackdrop then
		f.link:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 10, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
		f.link:SetBackdropColor(0.07, 0.05, 0.14, 0.95)
		f.link:SetBackdropBorderColor(0.5, 0.4, 0.85, 1)
	end
	f.link:SetFontObject(ChatFontNormal)
	f.link:SetTextInsets(6, 6, 0, 0)
	f.link:SetAutoFocus(false)
	f.link:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	f.link:SetScript("OnTextChanged", function(self, user)
		if user and self:GetText() ~= ns.APP_URL then
			self:SetText(ns.APP_URL)
			if self.HighlightText then self:HighlightText() end
		end
	end)
	f.link:SetScript("OnEditFocusGained", function(self) if self.HighlightText then self:HighlightText() end end)
	f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.hint:SetText("Click the link, press Ctrl+C, then paste it in your browser.")
	f.again = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.again:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", WL.PAD, 22)
	f.again:SetText("/sm welcome shows this again.")
	f.ok = ns.GearUI.Button(f, "Close", 80)
	f.ok:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -WL.PAD + 4, 16)
	f.ok:SetScript("OnClick", function() f:Hide() end)
	f.panel = ns.GearUI.Button(f, "Open the panel", 130)
	f.panel:SetPoint("RIGHT", f.ok, "LEFT", -10, 0)
	f.panel:SetScript("OnClick", function()
		f:Hide()
		if ns.Panel and ns.Panel.Show then ns.Panel.Show("quests") end
	end)
	f.go = ns.GearUI.Button(f, "Try the route", 120)
	f.go:SetPoint("RIGHT", f.panel, "LEFT", -10, 0)
	f.go:SetScript("OnClick", function()
		f:Hide()
		local run = f.try and WL.TRY[f.try]
		if run then run() end
	end)
	-- Closed: the nudges that waited go on.
	f:SetScript("OnHide", function()
		if f.link.ClearFocus then f.link:ClearFocus() end
		if ns.Nudges and ns.Nudges.Next then ns.Nudges.Next() end
	end)
	f:Hide()
	WL.frame = f
	return f
end

function WL.Show()
	local f = Build()
	local fresh, newest = WL.FeaturesSince(WL.FRESH_SINCE, ns.VERSION)
	f.top:SetText("Spellmind " .. tostring(ns.VERSION or ""))
	local y = Fill(f, WL.TITLE, WL.INTRO, {
		{ label = #fresh > 0 and ("New in " .. tostring(ns.VERSION or "")) or nil, features = fresh },
		{ label = #fresh > 0 and "Always in Spellmind" or nil, features = WL.BASICS },
	})
	-- The app: connected, or where to get it.
	local heard = AppHeard()
	f.appIcon:ClearAllPoints()
	f.appIcon:SetPoint("TOPLEFT", f, "TOPLEFT", WL.PAD, y)
	f.appTitle:ClearAllPoints()
	f.appTitle:SetPoint("TOPLEFT", f, "TOPLEFT", WL.PAD + 48, y)
	f.app:SetText(heard and WL.CONNECTED or WL.APP)
	f.app:ClearAllPoints()
	f.app:SetPoint("TOPLEFT", f.appTitle, "BOTTOMLEFT", 0, -4)
	y = y - (tonumber(f.appTitle:GetStringHeight()) or 16) - 4 - (tonumber(f.app:GetStringHeight()) or 42) - 10
	f.link:SetText(ns.APP_URL)
	f.link:ClearAllPoints()
	f.hint:ClearAllPoints()
	if heard then
		f.link:Hide(); f.hint:Hide()
	else
		f.hint:SetPoint("TOPLEFT", f, "TOPLEFT", WL.PAD + 50, y)
		f.hint:Show()
		y = y - 16
		f.link:SetPoint("TOPLEFT", f, "TOPLEFT", WL.PAD + 46, y)
		f.link:Show()
		y = y - 30
	end
	f.try = newest and newest.try or nil
	if f.try and WL.TRY[f.try] then f.go:Show() else f.go:Hide() end
	Center(f, math.max(360, -y + 66))
	return f
end

---------------------------------------------------------------------------
-- What's new: the news since the version last seen
---------------------------------------------------------------------------

local function BuildNews()
	if WL.news then return WL.news end
	local f = Window("SpellmindNews")
	f.title = f.top
	f.note = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	f.note:SetWidth(INNER)
	f.note:SetJustifyH("LEFT")
	if f.note.SetWordWrap then f.note:SetWordWrap(true) end
	f.alsoLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.again = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.again:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", WL.PAD, 22)
	f.again:SetText("/sm news shows this again.")
	f.ok = ns.GearUI.Button(f, "Close", 80)
	f.ok:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -WL.PAD + 4, 16)
	f.ok:SetScript("OnClick", function() f:Hide() end)
	f.go = ns.GearUI.Button(f, "Try it now", 110)
	f.go:SetPoint("RIGHT", f.ok, "LEFT", -10, 0)
	f.go:SetScript("OnClick", function()
		f:Hide()
		local run = f.try and WL.TRY[f.try]
		if run then run() end
	end)
	f:SetScript("OnHide", function() if ns.Nudges and ns.Nudges.Next then ns.Nudges.Next() end end)
	f:Hide()
	WL.news = f
	return f
end

-- Several versions since the one last seen: the newest headline, every version's highlights (newest
-- first) and every version's changes.
function WL.ShowNews(list)
	list = list or WL.Since("0", ns.VERSION)
	if #list == 0 then list = { WL.NEWS[#WL.NEWS] } end
	local n = list[#list]
	local features, lead = {}, nil
	for k = #list, 1, -1 do
		for _, ft in ipairs(list[k].features or {}) do features[#features + 1] = ft end
		if not lead and list[k].headline then lead = list[k] end
	end
	lead = lead or n
	local f = BuildNews()
	local P = WL.PAD
	f.title:SetText("What's new in Spellmind " .. n.version)
	local y = Fill(f, lead.headline or "What's changed", lead.tagline, { { features = features } })
	-- The changes: every version's since the one last seen, newest first ("Also in this update" under
	-- highlights; on their own, the headline says it).
	local lines = {}
	for k = #list, 1, -1 do
		for _, c in ipairs(list[k].changes or {}) do
			lines[#lines + 1] = (#list > 1 and ("|cff888888" .. list[k].version .. "|r  ") or "") .. c
		end
	end
	for _, l in ipairs(f.changes) do l:Hide() end
	f.alsoLabel:Hide()
	if #lines > 0 and #features > 0 then
		f.alsoLabel:SetText("Also in this update")
		f.alsoLabel:ClearAllPoints()
		f.alsoLabel:SetPoint("TOPLEFT", f, "TOPLEFT", P, y)
		f.alsoLabel:Show()
		y = y - 22
	end
	for k, text in ipairs(lines) do
		local l = Change(f, k)
		l:SetText("|cffffd100•|r  " .. text)
		l:ClearAllPoints()
		l:SetPoint("TOPLEFT", f, "TOPLEFT", P + 4, y)
		l:Show()
		y = y - (tonumber(l:GetStringHeight()) or 14) - 8
	end
	if #lines > 0 then y = y - 10 end
	f.note:SetText(lead.note or "")
	f.note:ClearAllPoints()
	f.note:SetPoint("TOPLEFT", f, "TOPLEFT", P, y - 2)
	if lead.note then y = y - 2 - (tonumber(f.note:GetStringHeight()) or 14) end
	f.try = lead.try
	if lead.try and WL.TRY[lead.try] then f.go:Show() else f.go:Hide() end
	Center(f, math.max(300, -y + 70))
	return f
end

-- The first time on this account, the welcome; after an update, What's new. After the login has
-- settled, never in combat.
function WL.MaybeShow()
	if not ns.db then return end
	if not ns.db.welcomed then
		if InCombat() then C_Timer.After(WL.RETRY, WL.MaybeShow); return end
		ns.db.welcomed = true
		ns.db.seenVersion = ns.VERSION
		WL.Show()
		return
	end
	if ns.db.seenVersion == ns.VERSION then return end
	local news = WL.Since(ns.db.seenVersion or "0", ns.VERSION)
	if #news == 0 then ns.db.seenVersion = ns.VERSION; return end
	if InCombat() then C_Timer.After(WL.RETRY, WL.MaybeShow); return end
	ns.db.seenVersion = ns.VERSION
	WL.ShowNews(news)
end

ns.On("PLAYER_LOGIN", function() C_Timer.After(WL.DELAY, WL.MaybeShow) end)
