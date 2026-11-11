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
	f:SetSize(340, 260)
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
	f.body = CreateFrame("ScrollingMessageFrame", nil, f)
	f.body:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -38)
	f.body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 36)
	f.body:SetFontObject(ChatFontNormal)
	f.body:SetJustifyH("LEFT")
	f.body:SetFading(false)
	f.body:SetMaxLines(200)
	f.body:EnableMouseWheel(true)
	f.body:SetScript("OnMouseWheel", function(self, delta)
		if delta > 0 then self:ScrollUp() else self:ScrollDown() end
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

-- Lines of text into the card's body (top first).
local function Fill(card, text)
	card.body:Clear()
	card.lines = {}
	for line in (tostring(text) .. "\n"):gmatch("(.-)\n") do
		card.lines[#card.lines + 1] = line
		card.body:AddMessage(line)
	end
	card.body:ScrollToTop() -- the answer's first line, which says the verdict
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
