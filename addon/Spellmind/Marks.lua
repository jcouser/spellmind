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
M.HINT = "|cff888888Click: Explain. Shift-click: ask in the chat window.|r"
M.NO_DATA = "Explain needs your game data. Type /sm data on, then click again."
M.THINKING = "|cff888888Thinking…|r"
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

function M.Create(parent, name, spec)
	local b = CreateFrame("Button", name, parent)
	b:SetSize(20, 20)
	local level = parent and parent.GetFrameLevel and parent:GetFrameLevel()
	if type(level) == "number" then b:SetFrameLevel(level + 10) end
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints(b)
	b.icon:SetTexture(M.ICON)
	b:SetHighlightTexture(M.ICON, "ADD")
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
	local key = ns.Chat.Send(req.text, { about = req.about, shown = req.label, card = true })
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
	f.more = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.more:SetSize(96, 22)
	f.more:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 9)
	f.more:SetText("Ask more")
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
	card.owner, card.key, card.about, card.label = b, key, req.about, req.label
	card.title:SetText(req.label)
	Fill(card, M.THINKING)
	card:ClearAllPoints()
	local anchor = req.anchor or b
	card:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 6, 0)
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
		if (tonumber(r.more) or 0) > 0 then text = text .. "\n|cff888888(the rest is in the Spellmind app)|r" end
	elseif r.t == "error" then
		text = "|cffff6060" .. ns.SafeText(r.text) .. "|r"
	else
		text = ns.SafeText(type(r.text) == "string" and r.text ~= "" and r.text or "Stopped.")
	end
	Fill(card, text)
	return true
end

-- Ask more: the chat window, its next questions about the card's thing.
function M.AskMore()
	local card = M.card
	if not card then return end
	ns.Chat.AskAbout(card.about, card.label)
	ns.Chat.Open()
end
