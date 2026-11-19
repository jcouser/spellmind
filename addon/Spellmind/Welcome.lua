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

local _, ns = ...
local WL = {}
ns.Welcome = WL

WL.DELAY = 6 -- seconds after login: the app's first answer to the hello comes in by then
WL.RETRY = 5 -- seconds, while in combat
WL.TITLE = "Welcome to Spellmind"
WL.INTRO = "Your companion for WoW Forever. With no setup at all:\n\n"
	.. "|cffffd100•|r The minimap button, or |cffffd100/sm|r, opens it. Right-click the button for your last tab.\n"
	.. "|cffffd100•|r Quests, Dungeons, Gear, Talents, Spells, Professions and Gold say what to do next.\n"
	.. "|cffffd100•|r Nudges by the minimap tell you when spells wait at your trainer, talent points are unspent or gear is about to break.\n"
	.. "|cffffd100•|r Spellmind's lines on quest and item tooltips.\n"
	.. "|cffffd100•|r The quest route: your next steps, an arrow and the map's areas. Turn it on in the Route tab."
WL.APP = "|cff9d7dffWant to ask your own AI anything about your character?|r Get the free Spellmind app for Windows. It works with a ChatGPT plan, or an API key for Claude, ChatGPT, Grok or Gemini, and sends nothing to the Spellmind authors."
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

-- Each version's news, oldest first (core/news.mjs, word for word). route: the route's two buttons.
WL.NEWS = {
	{ version = "0.5.0", title = "The quest route", route = true, lines = {
		"Your next steps from your quest log and where you stand: pick up, do and turn in, in a short order, ticked off as you go.",
		"An arrow points at the current step, and the world map numbers the steps and shades where each objective is.",
		"Where next ranks the zones by what is left for your level, with your flight paths and hearthstone.",
		"Best with Questie installed: it adds the quests to pick up and where the mobs are.",
		"Turn it on in the new Route tab. Your AI gets the route too: try Review my route.",
	} },
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

local function Build()
	if WL.frame then return WL.frame end
	local f = CreateFrame("Frame", "SpellmindWelcome", UIParent, "BackdropTemplate")
	f:SetSize(460, 330)
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
	if f.SetBackdrop then
		f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 14, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
		f:SetBackdropColor(0.05, 0.04, 0.1, 0.98)
		f:SetBackdropBorderColor(0.62, 0.49, 1, 1)
	end
	if ns.Window and ns.Window.Fill then ns.Window.Fill(f, 4, 0.035, 0.025, 0.08, 0.97) end
	if ns.Window and ns.Window.Corners then ns.Window.Corners(f, 18) end
	f.portrait = f:CreateTexture(nil, "ARTWORK")
	f.portrait:SetSize(28, 28)
	f.portrait:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -8)
	f.portrait:SetTexture(ns.Marks and ns.Marks.PORTRAIT or "Interface\\AddOns\\Spellmind\\Media\\Portrait")
	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 44, -14)
	f.title:SetText(WL.TITLE)
	f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
	f.intro = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.intro:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -46)
	f.intro:SetWidth(428)
	f.intro:SetJustifyH("LEFT")
	if f.intro.SetWordWrap then f.intro:SetWordWrap(true) end
	f.intro:SetText(WL.INTRO)
	f.app = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.app:SetPoint("TOPLEFT", f.intro, "BOTTOMLEFT", 0, -12)
	f.app:SetWidth(428)
	f.app:SetJustifyH("LEFT")
	if f.app.SetWordWrap then f.app:SetWordWrap(true) end
	-- The project's link, selected to copy; typing can't change it (as in /sm app's box).
	f.link = CreateFrame("EditBox", nil, f, "BackdropTemplate")
	f.link:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 52)
	f.link:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 52)
	f.link:SetHeight(24)
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
	f.hint:SetPoint("BOTTOMLEFT", f.link, "TOPLEFT", 2, 4)
	f.hint:SetText("Click the link, press Ctrl+C, then paste it in your browser.")
	f.again = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.again:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 20)
	f.again:SetText("/sm welcome shows this again.")
	f.ok = ns.GearUI.Button(f, "Close", 80)
	f.ok:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 14)
	f.ok:SetScript("OnClick", function() f:Hide() end)
	f.panel = ns.GearUI.Button(f, "Open the panel", 130)
	f.panel:SetPoint("RIGHT", f.ok, "LEFT", -8, 0)
	f.panel:SetScript("OnClick", function()
		f:Hide()
		if ns.Panel and ns.Panel.Show then ns.Panel.Show("quests") end
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

-- The app's part says what's true now: connected, or where to get it.
local function Fill(f)
	local heard = AppHeard()
	f.app:SetText(heard and WL.CONNECTED or WL.APP)
	if heard then f.link:Hide(); f.hint:Hide() else f.link:Show(); f.hint:Show() end
	f.link:SetText(ns.APP_URL)
	-- Tall enough for its text at any UI scale: the title, the two texts, then the link and buttons.
	local textH = (tonumber(f.intro:GetStringHeight()) or 130) + 12 + (tonumber(f.app:GetStringHeight()) or 50)
	f:SetHeight(math.max(heard and 260 or 320, 46 + textH + (heard and 56 or 108)))
end

function WL.Show()
	local f = Build()
	Fill(f)
	f:ClearAllPoints()
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
	f:Show()
	return f
end

-- What's new: the news since the version last seen (newest first, three at most); the route's buttons
-- when one is the route's.
local function BuildNews()
	if WL.news then return WL.news end
	local f = CreateFrame("Frame", "SpellmindNews", UIParent, "BackdropTemplate")
	f:SetSize(460, 300)
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
	if f.SetBackdrop then
		f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 14, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
		f:SetBackdropColor(0.05, 0.04, 0.1, 0.98)
		f:SetBackdropBorderColor(0.62, 0.49, 1, 1)
	end
	if ns.Window and ns.Window.Fill then ns.Window.Fill(f, 4, 0.035, 0.025, 0.08, 0.97) end
	if ns.Window and ns.Window.Corners then ns.Window.Corners(f, 18) end
	f.portrait = f:CreateTexture(nil, "ARTWORK")
	f.portrait:SetSize(28, 28)
	f.portrait:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -8)
	f.portrait:SetTexture(ns.Marks and ns.Marks.PORTRAIT or "Interface\\AddOns\\Spellmind\\Media\\Portrait")
	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 44, -14)
	f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
	f.body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.body:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -46)
	f.body:SetWidth(428)
	f.body:SetJustifyH("LEFT")
	if f.body.SetWordWrap then f.body:SetWordWrap(true) end
	f.again = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.again:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 20)
	f.again:SetText("/sm news shows this again.")
	f.ok = ns.GearUI.Button(f, "Close", 70)
	f.ok:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 14)
	f.ok:SetScript("OnClick", function() f:Hide() end)
	f.tab = ns.GearUI.Button(f, "Open the Route tab", 140)
	f.tab:SetPoint("RIGHT", f.ok, "LEFT", -8, 0)
	f.tab:SetScript("OnClick", function()
		f:Hide()
		if ns.Panel and ns.Panel.Show then ns.Panel.Show("route") end
	end)
	f.route = ns.GearUI.Button(f, "Turn on the route", 130)
	f.route:SetPoint("RIGHT", f.tab, "LEFT", -8, 0)
	f.route:SetScript("OnClick", function()
		if ns.Route then ns.Route.SetOn(true) end
		f.route:Hide()
	end)
	f:SetScript("OnHide", function() if ns.Nudges and ns.Nudges.Next then ns.Nudges.Next() end end)
	f:Hide()
	WL.news = f
	return f
end

function WL.ShowNews(list)
	list = list or WL.Since("0", ns.VERSION)
	if #list == 0 then list = { WL.NEWS[#WL.NEWS] } end
	local f = BuildNews()
	local newest = list[#list]
	f.title:SetText("What's new in Spellmind " .. newest.version)
	local text, route = {}, false
	for k = #list, math.max(1, #list - 2), -1 do
		local n = list[k]
		if n.route then route = true end
		text[#text + 1] = "|cffffd100" .. n.title .. "|r" .. (#list > 1 and (" |cff888888(" .. n.version .. ")|r") or "")
		for _, l in ipairs(n.lines) do text[#text + 1] = "|cffffd100•|r " .. l end
		text[#text + 1] = ""
	end
	f.body:SetText(table.concat(text, "\n"))
	local on = ns.Route and ns.Route.On and ns.Route.On()
	if route then f.tab:Show() else f.tab:Hide() end
	if route and not on then f.route:Show() else f.route:Hide() end
	f:SetHeight(math.max(220, 46 + (tonumber(f.body:GetStringHeight()) or 160) + 60))
	f:ClearAllPoints()
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
	f:Show()
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
