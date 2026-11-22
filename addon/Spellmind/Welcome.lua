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
WL.INTRO = "Your companion for WoW Forever. It knows your character as you play, and says what to do next."
-- The welcome shows the highlights of every version after this one (the last that players had): set it
-- to the version before the one being published (docs/releasing.md).
WL.FRESH_SINCE = "0.6.5"
WL.TRY_ALWAYS = "route" -- the welcome's Try it now when nothing is new
-- What's always there, after what's new. The quest route since 0.5.0 (published 2026-11-20): once it's no
-- longer new, a new player still meets it here.
WL.BASICS = {
	{ icon = "Interface\\Icons\\INV_Misc_Map_01", title = "Your quest route", text = "Every pickup, objective and turn-in near you in the shortest order, an arrow, and the way on your maps. It plans dungeons and class questlines too. /sm route turns it on." },
	{ icon = "Interface\\Icons\\INV_Misc_Book_09", title = "A panel that knows your character", text = "Quests, Route, Dungeons, Gear, Talents, Spells, Professions and Gold, each saying what to do next. The minimap button or /sm opens it." },
	{ icon = "Interface\\AddOns\\Spellmind\\Media\\Mark", title = "Nudges and tooltips", text = "A quiet nudge when spells wait at your trainer, talent points are unspent or gear is about to break, and Spellmind's lines on tooltips." },
}
-- The app, in a box of its own (the player, 2026-11-21: "really emphasize the desktop app and its value"):
-- its heading, a line, then what it adds, two by two, and the link to copy (or that it's connected).
WL.APP_TITLE = "Even better with the free app"
WL.APP = "The free Spellmind app for Windows sits by the clock while you play, and keeps the addon up to date. No account, no subscription."
WL.APP_FEATURES = {
	{ icon = "Interface\\Icons\\Ability_Hunter_Pathfinding", title = "Roads every player walks", text = "Your route follows the paths players really take, kept up to date. It shares the ground you walk (squares only; the Route tab turns it off)." },
	{ icon = "Interface\\AddOns\\Spellmind\\Media\\Portrait", title = "Ask your own AI", text = "Anything about your character: gear, quests, talents, gold, your route. A ChatGPT plan, or a key for Claude, ChatGPT, Grok or Gemini." },
	{ icon = "Interface\\AddOns\\Spellmind\\Media\\Mark", title = "Break it down", text = "Click the Spellmind mark on a quest, an item, a trainer or a merchant: your AI explains that exact thing." },
	{ icon = "Interface\\Icons\\INV_Scroll_03", title = "Review my route", text = "Your AI sees your route and says what to skip, and why. Or bring your own leveling guide with /sm guide." },
}
WL.BASICS_LABEL = "Works right away, no setup"
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
			{ icon = "Interface\\Icons\\Ability_Hunter_Pathfinding", title = "Never lose your way", text = "An arrow on screen points to your next step. The world map numbers each step and shades where to go, and the minimap draws the line to it." },
			{ icon = "Interface\\Icons\\Ability_Mount_Gryphon_01", title = "The way there, leg by leg", text = "Flight paths you know, the roads between zones, the tram and the boats: the arrow and the map take you there by the fastest way you have." },
			{ icon = "Interface\\Icons\\Spell_Arcane_PortalStormWind", title = "Always know where to go next", text = "When a zone runs dry, Spellmind ranks the best zones for your level. Pick one and the route takes you there, and holds to it until you arrive." },
			{ icon = "Interface\\Icons\\INV_Misc_Key_03", title = "Ready for any dungeon", text = "Pick a dungeon on the Route tab: Spellmind routes you through its quests and the questlines that open them, across zones, to its door." },
			{ icon = "Interface\\AddOns\\Spellmind\\Media\\Portrait", title = "Ask your AI about it", text = "Your AI sees the same route. Ask \"Review my route\" for what to skip, and why." },
		},
		note = "Works best with Questie installed. Find it all in the new Route tab.",
		changes = {
			"The Quests tab's \"Plan my next hour\" is now \"Review my route\", and each quest your AI says to skip gets a Skip button.",
			"After each update, this window says what's new. /sm news shows it again.",
			"A quest handed in in another zone is planned as a trip there and back when what it opens makes it worth it.",
			"The arrow and the lines follow the roads you've walked (learned on your PC only), and hold still on a flight path.",
			"Far quests that give little XP for the walk are marked \"worth skipping?\", and each kill step goes to the mobs least out of your way.",
			"Up next numbers each step as the map does. /sm route why <step> says why a step is where it is.",
		} },
	{ version = "0.6.0", try = "classq",
		headline = "Your class quests, planned",
		tagline = "Spellmind now finds your class's own questlines, wherever they start, and takes you through them.",
		features = {
			{ icon = "Interface\\Icons\\INV_Misc_Book_11", title = "Every class questline for you", text = "The Quests tab lists your class's questlines at your level, with the step you're on and where it starts. Versions from other starting areas fold under yours." },
			{ icon = "Interface\\Icons\\INV_Misc_Map_01", title = "Routed like a dungeon", text = "Pick one and the route takes you through it, across zones, by boat and flight path, to its last turn-in." },
			{ icon = "Interface\\AddOns\\Spellmind\\Media\\Mark", title = "Never miss one", text = "A nudge when a new class questline opens at your level, and a pointer in the route window while you quest." },
			{ icon = "Interface\\Icons\\INV_Misc_Spyglass_02", title = "Know when you're there", text = "Inside an objective's area, the arrow says so and the minimap shades it, with no line pointing at its middle." },
		},
		note = "Works best with Questie installed. Find it on the Quests tab and the Route tab.",
		changes = {
			"Class quests, and quests whose reward is an upgrade for you, are never marked \"worth skipping?\".",
			"The route keeps its order as you quest: new steps slot in where they fit, and Rebuild plans it afresh.",
			"Fixed: a spell you had trained could stay \"to train\" after a trainer visit.",
			"Season of Discovery quests no longer slip into the route on WoW Forever.",
			"Spellmind's lines in the game's chat have their own colours, and nudges grow to fit their words.",
		} },
	{ version = "0.6.1",
		changes = {
			"Skipping a step skips what needs it: skip a pickup or an objective and the quest's turn-in and follow-ups go with it; skip a turn-in and its follow-ups go. Back brings them back.",
			"The route counts the steps left (\"22 steps left · 2 skipped\"), not \"Step 3 of 25\".",
			"When a fresh plan from where you stand would be clearly shorter, Rebuild says so (\"Rebuild: 1,300 yd shorter\"). After you finish a step, a much shorter order is taken by itself, your next step kept (a switch on the Route tab).",
			"Fixed: in a step with goals at several NPCs close together, the arrow and the map pointed at the first one placed, not the one to do now.",
		} },
	{ version = "0.6.2",
		changes = {
			"Fixed: Lua errors in combat from the route's arrow (the game's \"large number of errors\" warning).",
		} },
	{ version = "0.6.3",
		changes = {
			"Class questlines include every step: objectives placed (class quests have no zone of their own), and items to buy at a vendor.",
			"Items a vendor sells are bought from the nearest friendly seller, not farmed in a zone far away.",
			"On a flight path, the way there starts where you land (\"In flight to Stormwind\").",
			"Fixed: the map's gold line could run to another step when your current one was on a different map.",
			"/sm route why lists every seller of a step's items: where, whose, and how far.",
		} },
	{ version = "0.6.4",
		changes = {
			"A quest's items each get their own step, with their own seller and navigation: in class questlines and in your zone's quests.",
			"Items picked up off the ground are listed as \"take ... (on the ground)\", so no item goes unsaid.",
			"When another quest in your log needs the same item, the step says how many to buy (\"buy 2: ... needs one too\").",
			"A vendor seen sold out of an item is noticed on these steps too: the next seller, or the Auction House.",
			"At one NPC, the finished quest is turned in before its follow-up is picked up.",
			"Fixed: the minimap line and the arrow cut through walls when the target was nearer in a straight line.",
			"Out in the open, the line and the arrow go straight to the step unless a trail you walked heads there anyway: no more going back along another trip.",
			"Fixed: the world map's line ran back to a trail point you had already walked past.",
		} },
	{ version = "0.6.5", try = "route",
		headline = "Roads every player walks",
		tagline = "Your route now follows the paths players really take, and gets better the more people play.",
		features = {
			{ icon = "Interface\\Icons\\Ability_Hunter_Pathfinding", title = "Roads every player walks", text = "With the Spellmind app, the ground players walk is shared and merged into roads. The arrow and the lines follow them, kept up to date by the app and in every release." },
			{ icon = "Interface\\Icons\\INV_Misc_Map_01", title = "Straight where it's open", text = "Out in the open the line goes straight, unless a road heads your way: then it follows the road as far as it helps and cuts across. In a city it follows the streets." },
			{ icon = "Interface\\Icons\\INV_Misc_Spyglass_02", title = "Your own trails, smarter", text = "A field you've crossed every which way is crossed straight, a wall no one walked through stays a wall, and a road walked one way is a way back too." },
			{ icon = "Interface\\AddOns\\Spellmind\\Media\\Mark", title = "Yours to turn off", text = "Only squares crossed are shared: no times, no character, no account, and a crossing only once 2 players walked it. \"Share the ground I walk\" on the Route tab turns it off." },
		},
		note = "Shared roads need the free Spellmind app. The switches are on the Route tab.",
		changes = {
			"The welcome shows what the free app adds, in a box of its own.",
			"The app's Status card says how much ground you've shared and when, and the roads you've received.",
			"An objective Questie has no spot for gets a circle around the game's marker, as the others have.",
			"/sm route why also says why the line goes the way it does.",
			"Your trails from before are turned into the new kind once, by themselves.",
		} },
	{ version = "0.6.6",
		changes = {
			"Fixed: with a long leveling guide imported, your AI got none of your talents, and answers said the game data was stale.",
			"The app shares the ground you walk right after you close WoW, not up to a day later.",
			"Fixed: the minimap's line could stay straight while the world map's followed your road.",
		} },
}

-- What each news's "Try it now" does: the route on, and its tab.
WL.TRY = {
	route = function()
		if ns.Route and not ns.Route.On() then ns.Route.SetOn(true) end
		if ns.Panel and ns.Panel.Show then ns.Panel.Show("route") end
	end,
	-- The class questlines: the Quests tab lists them, each with Route.
	classq = function()
		if ns.Panel and ns.Panel.Show then ns.Panel.Show("quests") end
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

WL.W, WL.PAD = 600, 22
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
	l = (f.histContent or f):CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	l:SetJustifyH("LEFT")
	l:SetWidth(INNER - 30)
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

-- Taller than the screen (a long What's new): scaled down to fit, never cut off.
WL.SCREEN_MARGIN = 60
local function Center(f, h)
	local room = (tonumber((UIParent and UIParent:GetHeight())) or 768) - WL.SCREEN_MARGIN
	if f.SetScale then f:SetScale(h > room and room / h or 1) end
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
	-- The app: a box of its own, lighter, with the owl, its heading and line, what it adds two by two, then
	-- the link to copy when it isn't there yet.
	local box = CreateFrame("Frame", nil, f, "BackdropTemplate")
	box:SetWidth(INNER)
	if box.SetBackdrop then
		box:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
		box:SetBackdropColor(0.13, 0.09, 0.26, 0.95)
		box:SetBackdropBorderColor(1, 0.82, 0, 0.8)
	end
	f.appBox = box
	f.appIcon = box:CreateTexture(nil, "ARTWORK")
	f.appIcon:SetSize(34, 34)
	f.appIcon:SetTexture(ns.Marks and ns.Marks.PORTRAIT or "Interface\\AddOns\\Spellmind\\Media\\Portrait")
	f.appTitle = box:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.appTitle:SetJustifyH("LEFT")
	f.appTitle:SetText(WL.APP_TITLE)
	f.app = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.app:SetWidth(INNER - 28 - 46)
	f.app:SetJustifyH("LEFT")
	if f.app.SetWordWrap then f.app:SetWordWrap(true) end
	if f.app.SetSpacing then f.app:SetSpacing(2) end
	f.appRows = {}
	local colW = math.floor((INNER - 28 - 16) / 2)
	for k, ft in ipairs(WL.APP_FEATURES) do
		local row = {}
		row.icon = box:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(24, 24)
		row.icon:SetTexture(ft.icon)
		row.title = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		row.title:SetJustifyH("LEFT")
		row.title:SetWidth(colW - 32)
		row.title:SetText(ft.title)
		row.text = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.text:SetJustifyH("LEFT")
		row.text:SetWidth(colW - 32)
		if row.text.SetWordWrap then row.text:SetWordWrap(true) end
		if row.text.SetSpacing then row.text:SetSpacing(2) end
		row.text:SetText(ft.text)
		f.appRows[k] = row
	end
	f.appColW = colW
	-- The project's link, selected to copy; typing can't change it (as in /sm app's box).
	f.link = CreateFrame("EditBox", nil, box, "BackdropTemplate")
	f.link:SetSize(INNER - 28, 24)
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
	f.hint = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.hint:SetText("Get it here: click the link, press Ctrl+C, then paste it in your browser.")
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
		{ label = WL.BASICS_LABEL, features = WL.BASICS },
	})
	-- The app's box: connected, or where to get it.
	local heard = AppHeard()
	local box = f.appBox
	box:ClearAllPoints()
	box:SetPoint("TOPLEFT", f, "TOPLEFT", WL.PAD, y)
	local by = -14
	f.appIcon:ClearAllPoints()
	f.appIcon:SetPoint("TOPLEFT", box, "TOPLEFT", 14, by)
	f.appTitle:ClearAllPoints()
	f.appTitle:SetPoint("TOPLEFT", box, "TOPLEFT", 14 + 46, by)
	f.app:SetText(heard and WL.CONNECTED or WL.APP)
	f.app:ClearAllPoints()
	f.app:SetPoint("TOPLEFT", f.appTitle, "BOTTOMLEFT", 0, -4)
	by = by - math.max(34, (tonumber(f.appTitle:GetStringHeight()) or 16) + 4 + (tonumber(f.app:GetStringHeight()) or 30)) - 14
	-- What it adds, two by two.
	for k = 1, #f.appRows, 2 do
		local h = 0
		for c = 0, 1 do
			local row = f.appRows[k + c]
			if row then
				local x = 14 + c * (f.appColW + 16)
				row.icon:ClearAllPoints(); row.icon:SetPoint("TOPLEFT", box, "TOPLEFT", x, by)
				row.title:ClearAllPoints(); row.title:SetPoint("TOPLEFT", box, "TOPLEFT", x + 32, by)
				row.text:ClearAllPoints(); row.text:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
				h = math.max(h, 24, (tonumber(row.title:GetStringHeight()) or 14) + 3 + (tonumber(row.text:GetStringHeight()) or 26))
			end
		end
		by = by - h - 12
	end
	f.link:SetText(ns.APP_URL)
	f.link:ClearAllPoints()
	f.hint:ClearAllPoints()
	if heard then
		f.link:Hide(); f.hint:Hide()
	else
		f.hint:SetPoint("TOPLEFT", box, "TOPLEFT", 16, by)
		f.hint:Show()
		by = by - 16
		f.link:SetPoint("TOPLEFT", box, "TOPLEFT", 14, by)
		f.link:Show()
		by = by - 30
	end
	box:SetHeight(-by + 4)
	y = y + by - 4 - 10
	-- Try it now: the newest feature's, else the route's (always there since 0.5.0).
	f.try = newest and newest.try or WL.TRY_ALWAYS
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
	-- The version history (the player, 2026-11-20: "a scrolling list of change log version history,
	-- while keeping the main product release section intact"): every version's changes, newest first.
	f.hist = CreateFrame("ScrollFrame", nil, f)
	f.histContent = CreateFrame("Frame", nil, f.hist)
	f.histContent:SetSize(INNER - 10, 10)
	f.hist:SetScrollChild(f.histContent)
	f.hist:EnableMouseWheel(true)
	f.hist:SetScript("OnMouseWheel", function(self, delta)
		local range = tonumber((self:GetVerticalScrollRange())) or 0
		local y = (tonumber((self:GetVerticalScroll())) or 0) - delta * 30
		self:SetVerticalScroll(math.max(0, math.min(range, y)))
		if f.histBar and f.histBar.Update then f.histBar.Update() end
	end)
	f.histBar = ns.Window and ns.Window.ScrollBar and ns.Window.ScrollBar(f.hist, 4) or nil
	f.heads = {}
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

-- What's new (the player, 2026-11-20): the showcase, the newest release with a headline (its line, its
-- highlights, its footnote, Try it now), even when a fix came after it; then the version history,
-- every version up to this one, newest first, each its changes ("new" on the ones since the version
-- last seen), in a scroll of its own so the window keeps its size. list: the versions since the one
-- last seen (to mark them new); nil for /sm news.
WL.HISTORY_H = 190
local function Head(f, k)
	local l = f.heads[k]
	if l then return l end
	l = f.histContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	l:SetJustifyH("LEFT")
	l:SetWidth(INNER - 16)
	f.heads[k] = l
	return l
end
function WL.ShowNews(list)
	local current = ns.VERSION
	local all = {}
	for _, e in ipairs(WL.NEWS) do if not WL.Newer(e.version, current or "0") then all[#all + 1] = e end end
	if #all == 0 then all = { WL.NEWS[#WL.NEWS] } end
	local fresh = {}
	for _, e in ipairs(list or {}) do fresh[e.version] = true end
	local lead
	for k = #all, 1, -1 do if all[k].headline then lead = all[k]; break end end
	lead = lead or all[#all]
	local f = BuildNews()
	local P = WL.PAD
	f.title:SetText("What's new in Spellmind " .. tostring(current or all[#all].version))
	local y = Fill(f, lead.headline or "What's changed", lead.tagline, { { features = lead.features or {} } })
	f.note:SetText(lead.note or "")
	f.note:ClearAllPoints()
	f.note:SetPoint("TOPLEFT", f, "TOPLEFT", P, y - 2)
	if lead.note then y = y - 2 - (tonumber(f.note:GetStringHeight()) or 14) - 14 end
	-- The history.
	for _, l in ipairs(f.changes) do l:Hide() end
	for _, l in ipairs(f.heads) do l:Hide() end
	f.alsoLabel:SetText("Version history")
	f.alsoLabel:ClearAllPoints()
	f.alsoLabel:SetPoint("TOPLEFT", f, "TOPLEFT", P, y)
	f.alsoLabel:Show()
	y = y - 22
	local cy, nh, nl = 0, 0, 0
	for k = #all, 1, -1 do
		local e = all[k]
		nh = nh + 1
		local h = Head(f, nh)
		h:SetText("|cffffd100" .. e.version .. "|r" .. (e.headline and ("  |cffffffff" .. e.headline .. "|r") or "")
			.. (fresh[e.version] and "  |cff19ff19new|r" or ""))
		h:ClearAllPoints()
		h:SetPoint("TOPLEFT", f.histContent, "TOPLEFT", 0, cy)
		h:Show()
		cy = cy - (tonumber(h:GetStringHeight()) or 14) - 6
		for _, c in ipairs(e.changes or {}) do
			nl = nl + 1
			local l = Change(f, nl)
			l:SetText("|cffffd100•|r  " .. c)
			l:ClearAllPoints()
			l:SetPoint("TOPLEFT", f.histContent, "TOPLEFT", 8, cy)
			l:Show()
			cy = cy - (tonumber(l:GetStringHeight()) or 14) - 6
		end
		cy = cy - 10
	end
	f.histContent:SetSize(INNER - 10, math.max(1, -cy))
	local hh = math.min(WL.HISTORY_H, math.max(30, -cy))
	f.hist:ClearAllPoints()
	f.hist:SetPoint("TOPLEFT", f, "TOPLEFT", P, y)
	f.hist:SetSize(INNER, hh)
	f.hist:SetVerticalScroll(0)
	f.hist:Show()
	if f.histBar and f.histBar.Update then f.histBar.Update() end
	y = y - hh - 12
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
	-- A fix alone (no headline) doesn't open it: it's in the history, for /sm news.
	local feature = false
	for _, e in ipairs(news) do if e.headline then feature = true end end
	if not feature then ns.db.seenVersion = ns.VERSION; return end
	if InCombat() then C_Timer.After(WL.RETRY, WL.MaybeShow); return end
	ns.db.seenVersion = ns.VERSION
	WL.ShowNews(news)
end

ns.On("PLAYER_LOGIN", function() C_Timer.After(WL.DELAY, WL.MaybeShow) end)
