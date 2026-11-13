-- Marks.lua: the Spellmind mark on the game's own windows (docs/features.md §2.1, docs/milestone-5.md).
--
--   hover        local facts in the game tooltip: no AI, no cost
--   click        Explain: the AI answers about that exact thing; the answer shows in a card beside
--                the window (and in the chat window's history)
--   shift-click  the question put in the chat box, to edit before sending
--
-- A mark is made by the window's integration (Quests.lua) with a spec:
--   spec.facts()    -> { lines } shown on hover (escaped text)
--   spec.explain()  -> { about = "quest:1338", label, text, focus = <State O object>, anchor = frame } or nil
--
-- Marks never touch a protected frame or anything in combat: they're plain buttons on plain windows,
-- and the card is parented to UIParent and only anchored to the window it explains.

local _, ns = ...
local M = {}
ns.Marks = M
local R = ns.R

M.ICON = "Interface\\AddOns\\Spellmind\\Media\\Mark"
M.PORTRAIT = "Interface\\AddOns\\Spellmind\\Media\\Portrait"
-- The feature's own name, as Settings and the card say it (the review).
M.HINT = "|cff888888Click: Break it down (asks your AI). Shift-click: edit the question first.|r"
M.NO_DATA = "Break it down needs your game data. Turn it on in Settings, then click again."
M.THINKING = "|cff888888Thinking…|r"
M.NO_APP = "|cff9d7dffThe Spellmind app isn't running, so there's no answer yet.|r\n\nStart it from the Start menu, or its icon by the clock. Your question is waiting: its answer will show here.\n\n|cff888888No app yet? Type /sm app.|r"
M.CARD_W, M.CARD_MIN_H, M.CARD_MAX_H = 360, 120, 420

-- Marks on or off (/sm marks off): the saved switch, on unless set off.
function M.On(what)
	local m = ns.db and ns.db.marks
	if type(m) ~= "table" then return true end
	if m.all == false then return false end
	return m[what] ~= false
end

---------------------------------------------------------------------------
-- The mark
---------------------------------------------------------------------------

local function ShowFacts(b)
	local tip = GameTooltip
	if not tip or not b.spec then return end
	tip:SetOwner(b, "ANCHOR_RIGHT")
	tip:SetText("Spellmind", 0.62, 0.49, 1)
	local ok, lines = pcall(b.spec.facts)
	for _, line in ipairs(ok and type(lines) == "table" and lines or {}) do tip:AddLine(line, 1, 1, 1, true) end
	tip:AddLine(M.HINT, 1, 1, 1, true)
	tip:Show()
	M.lastFacts = ok and lines or nil
end

-- opts.round: a round, gold-rimmed button like the game's and other addons' small header buttons
-- (Questie's and the like on the quest details, seen in game), instead of the bare sigil.
function M.Create(parent, name, spec, opts)
	local b = CreateFrame("Button", name, parent)
	local round = opts and opts.round
	b:SetSize(round and 24 or 20, round and 24 or 20)
	local level = parent and parent.GetFrameLevel and parent:GetFrameLevel()
	if type(level) == "number" then b:SetFrameLevel(level + 10) end
	if round then
		b.bg = b:CreateTexture(nil, "BACKGROUND")
		b.bg:SetSize(18, 18)
		b.bg:SetPoint("CENTER", b, "CENTER", 0, 0)
		b.bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetSize(16, 16)
		b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
		-- The tracking border's ring sits in the top-left of its texture: 41 px for a 24 px button.
		b.border = b:CreateTexture(nil, "OVERLAY")
		b.border:SetSize(41, 41)
		b.border:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
		b.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
		b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
	else
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetAllPoints(b)
		b:SetHighlightTexture(M.ICON, "ADD")
	end
	b.icon:SetTexture(M.ICON)
	b.spec = spec
	b:SetScript("OnEnter", ShowFacts)
	b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	b:SetScript("OnClick", function(self)
		if type(IsShiftKeyDown) == "function" and IsShiftKeyDown() then M.AskInChat(self) else M.Explain(self) end
	end)
	-- The card goes when the window it explains goes.
	b:HookScript("OnHide", function(self) if M.card and M.card.owner == self then M.card:Hide() end end)
	return b
end

-- The explain request of a mark, or nil (and why, said in chat).
local function Request(b)
	if not b.spec then return nil end
	local ok, req = pcall(b.spec.explain)
	if not ok or type(req) ~= "table" then return nil end
	return req
end

function M.Explain(b)
	local req = Request(b)
	if not req then return nil end
	if not (ns.State and ns.State.Sharing()) then
		ns.Chat.System(M.NO_DATA)
		return nil
	end
	ns.State.SetFocus(req.focus)
	local key = ns.Chat.PendingKey(req.text, req.about) or ns.Chat.Send(req.text, { about = req.about, shown = req.label, card = true })
	if not key then return nil end
	M.ShowCard(b, req, key)
	return key
end

function M.AskInChat(b)
	local req = Request(b)
	if not req then return end
	if ns.State and ns.State.Sharing() then ns.State.SetFocus(req.focus) end
	ns.Chat.AskAbout(req.about, req.label)
	ns.Chat.Open(req.text)
end

---------------------------------------------------------------------------
-- The answer card
---------------------------------------------------------------------------

local function BuildCard()
	if M.card then return M.card end
	local f = CreateFrame("Frame", "SpellmindCard", UIParent, "BackdropTemplate")
	f:SetSize(M.CARD_W, M.CARD_MIN_H)
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
	if f.SetBackdrop then
		f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
		f:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
		f:SetBackdropBorderColor(0.62, 0.49, 1, 1)
	end
	if ns.Window and ns.Window.Fill then ns.Window.Fill(f, 4, 0.035, 0.025, 0.08, 0.97) end -- solid: the tooltip background shows the world through
	if ns.Window and ns.Window.Corners then ns.Window.Corners(f, 18) end
	f.portrait = f:CreateTexture(nil, "ARTWORK")
	f.portrait:SetSize(24, 24)
	f.portrait:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -7)
	f.portrait:SetTexture(M.PORTRAIT)
	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 38, -12)
	f.title:SetPoint("TOPRIGHT", f, "TOPRIGHT", -30, -12)
	f.title:SetJustifyH("LEFT")
	f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
	-- The answer: one word-wrapped text, top-aligned, in a scroll frame (the wheel scrolls a long one).
	-- A ScrollingMessageFrame fills from the bottom, which showed only the first line (seen in game).
	f.scroll = CreateFrame("ScrollFrame", nil, f)
	f.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -38)
	f.scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 38)
	f.content = CreateFrame("Frame", nil, f.scroll)
	f.content:SetSize(M.CARD_W - 24, 10)
	f.scroll:SetScrollChild(f.content)
	f.body = f.content:CreateFontString(nil, "OVERLAY")
	f.body:SetFontObject(ChatFontNormal)
	f.body:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, 0)
	f.body:SetWidth(M.CARD_W - 24)
	f.body:SetJustifyH("LEFT")
	f.body:SetJustifyV("TOP")
	if f.body.SetWordWrap then f.body:SetWordWrap(true) end
	f.scroll:EnableMouseWheel(true)
	f.scroll:SetScript("OnMouseWheel", function(self, delta)
		local range = tonumber(self:GetVerticalScrollRange()) or 0
		local y = (tonumber(self:GetVerticalScroll()) or 0) - delta * 28
		self:SetVerticalScroll(math.max(0, math.min(range, y)))
	end)
	f.bar = ns.Window.ScrollBar(f.scroll, 8)
	-- Ask more, in the chat window's own button style (the game's red one clashed, seen in game).
	f.more = CreateFrame("Button", nil, f, "BackdropTemplate")
	f.more:SetSize(96, 22)
	f.more:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 9)
	if f.more.SetBackdrop then
		f.more:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
		f.more:SetBackdropColor(0.08, 0.06, 0.16, 0.95)
		f.more:SetBackdropBorderColor(0.58, 0.45, 0.98, 1)
	end
	f.more.text = f.more:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.more.text:SetPoint("CENTER", f.more, "CENTER", 0, 0)
	f.more.text:SetText("Ask more")
	f.more:SetScript("OnEnter", function(self) if self.SetBackdropBorderColor then self:SetBackdropBorderColor(0.85, 0.68, 0.25, 1) end end)
	f.more:SetScript("OnLeave", function(self) if self.SetBackdropBorderColor then self:SetBackdropBorderColor(0.58, 0.45, 0.98, 1) end end)
	f.more:SetScript("OnClick", function() M.AskMore() end)
	f:SetScript("OnHide", function(self)
		-- Closing the card ends its thread: the window's next questions are about nothing in particular.
		if R.ask and R.ask.about == self.about then ns.Chat.AskAbout(nil) end
		self.key, self.owner = nil, nil
	end)
	f:Hide()
	M.card = f
	return f
end

-- The text into the card, top first; the card grows to fit it (CARD_MIN_H to CARD_MAX_H), and a longer
-- one scrolls.
local function Fill(card, text)
	card.lines = {}
	for line in (tostring(text) .. "\n"):gmatch("(.-)\n") do card.lines[#card.lines + 1] = line end
	card.body:SetText(table.concat(card.lines, "\n"))
	local h = tonumber(card.body:GetStringHeight()) or 14
	card.content:SetHeight(math.max(10, h))
	card:SetHeight(math.max(M.CARD_MIN_H, math.min(M.CARD_MAX_H, h + 38 + 44)))
	card.scroll:SetVerticalScroll(0)
end

function M.ShowCard(b, req, key)
	local card = BuildCard()
	-- owner: the frame whose hiding closes the card (the mark, or the Advisor panel for its marks and
	-- Ask buttons: its rows redraw, so a row's mark hiding mustn't close it).
	card.owner, card.key, card.about, card.label = req.owner or b, key, req.about, req.label
	card.title:SetText(req.label)
	-- With no app heard, "Thinking…" would wait forever (seen in game): say so. The question stays
	-- queued, and its answer still comes here when the app starts.
	if ns.Link and ns.Link.AppGone and ns.Link.AppGone() then Fill(card, M.NO_APP) else Fill(card, M.THINKING) end
	card:ClearAllPoints()
	local anchor = req.anchor or b
	-- side "left": the card opens to the anchor's left (a nudge by the minimap, at the screen's right edge).
	-- To the left when asked (a nudge by the minimap), or when there's no room on the right (the review:
	-- clamped to the screen, it landed on top of the window it belonged beside).
	local side = req.side
	if side ~= "left" and anchor.GetRight and UIParent and UIParent.GetRight then
		local right, screen = tonumber((anchor:GetRight())), tonumber((UIParent:GetRight()))
		if right and screen and right + M.CARD_W + 6 > screen then side = "left" end
	end
	if side == "left" then card:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -6, 0)
	else card:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 6, 0) end
	card:Show()
end

-- Chat.lua, for the answer of a send made with card = true: shown in the card when it still waits
-- for that answer. Returns true when the card showed it.
function M.OnAnswer(key, r)
	local card = M.card
	if not card or card.key ~= key or not card:IsShown() then return false end
	card.key = nil
	local text
	if r.t == "reply" then
		text = ns.SafeText(r.text)
		if (tonumber(r.more) or 0) > 0 then text = text .. "\n|cff888888(cut short: ask for the rest)|r" end
	elseif r.t == "error" then
		text = "|cffff6060" .. ns.SafeText(r.text) .. "|r"
	else
		text = ns.SafeText(type(r.text) == "string" and r.text ~= "" and r.text or "Stopped.")
	end
	Fill(card, text)
	return true
end

-- A card of Spellmind's own text, no AI (the vendor helper's list): beside anchor, owned by it,
-- with Ask more to take it to the chat.
function M.ShowText(anchor, label, text, opts)
	M.ShowCard(anchor, { label = label, anchor = anchor, owner = (opts and opts.owner) or anchor, side = opts and opts.side }, nil)
	local card = M.card
	card.key = nil
	Fill(card, text)
	return card
end

-- A question from a button (the Advisor panel's Ask buttons): sent like a typed one, shown in the
-- window as label, its answer in the card beside anchor (which also owns it).
function M.Ask(anchor, label, text, opts)
	local key = ns.Chat.PendingKey(text, nil) or ns.Chat.Send(text, { shown = label, card = true, args = opts and opts.args })
	if not key then return nil end
	-- A nudge's toast hides as it's asked, so it can't own the card: the card stays until closed.
	local owner = opts and opts.side == "left" and UIParent or anchor
	M.ShowCard(anchor, { label = label, anchor = anchor, owner = owner, side = opts and opts.side }, key)
	return key
end

-- Ask more: the chat window, its next questions about the card's thing.
function M.AskMore()
	local card = M.card
	if not card then return end
	ns.Chat.AskAbout(card.about, card.label)
	ns.Chat.Open()
end

---------------------------------------------------------------------------
-- Get the app: where the free desktop app is, as a link to copy (the game can't open a browser)
---------------------------------------------------------------------------

M.GET_APP_TEXT = "The free Spellmind app (Windows 10 or 11) asks your own AI, a ChatGPT plan or an API key for Claude, ChatGPT, Grok or Gemini, and brings the answers here.\n\n|cff888888Every tab works without it: quests, dungeons, gear, talents, spells, professions, gold and nudges. Only the chat and Break it down need it.|r"

function M.GetApp()
	local f = M.appBox
	if not f then
		f = CreateFrame("Frame", "SpellmindGetApp", UIParent, "BackdropTemplate")
		f:SetSize(440, 196)
		f:SetFrameStrata("FULLSCREEN_DIALOG")
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
		f.portrait = f:CreateTexture(nil, "ARTWORK")
		f.portrait:SetSize(24, 24)
		f.portrait:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -7)
		f.portrait:SetTexture(M.PORTRAIT)
		f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 38, -12)
		f.title:SetText("Get the Spellmind app")
		f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
		f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
		f.body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		f.body:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -40)
		f.body:SetWidth(412)
		f.body:SetJustifyH("LEFT")
		if f.body.SetWordWrap then f.body:SetWordWrap(true) end
		f.body:SetText(M.GET_APP_TEXT)
		-- The link, selected, to copy: typing can't change it (any edit puts it back).
		f.input = CreateFrame("EditBox", nil, f, "BackdropTemplate")
		f.input:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 36)
		f.input:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 36)
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
		f.input:SetScript("OnEscapePressed", function() f:Hide() end)
		f.input:SetScript("OnEnterPressed", function() f:Hide() end)
		f.input:SetScript("OnTextChanged", function(self, user)
			if user and self:GetText() ~= ns.APP_URL then
				self:SetText(ns.APP_URL)
				if self.HighlightText then self:HighlightText() end
			end
		end)
		f.input:SetScript("OnEditFocusGained", function(self) if self.HighlightText then self:HighlightText() end end)
		f.note = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		f.note:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 16)
		f.note:SetText("Press Ctrl+C to copy the link, then open it in your browser.")
		f:Hide()
		M.appBox = f
	end
	f.input:SetText(ns.APP_URL)
	f:ClearAllPoints()
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
	f:Show()
	f.input:SetFocus()
	if f.input.HighlightText then f.input:HighlightText() end
	return f
end
