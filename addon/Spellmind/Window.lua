-- Window.lua: the chat (docs/milestone-6.md; mockup A of 2026-11-10), drawn in the Spellmind window's
-- Chat tab (Panel.lua, docs/milestone-11.md): the thinking dropdown and the web search toggle, a status
-- line, the conversation as bubbles (yours on the right in gold, Spellmind's on the left in violet with
-- the owl), the reply's suggestion chips, and an input box that takes shift-clicked item and quest
-- links. The picks are saved (SpellmindDB.ui); the window's place and size are the panel's.
--
-- Chat.lua keeps the conversation (SpellmindDB.msgs) and the sending; this file only draws.

local _, ns = ...
local W = {}
ns.Window = W
local R = ns.R

W.PORTRAIT = "Interface\\AddOns\\Spellmind\\Media\\Portrait"
W.MIN_W, W.MIN_H = 390, 300 -- the chat area at its smallest (compact mode is this plus the borders)
W.DEF_W, W.DEF_H = 460, 440
W.PAD = 10 -- inside a bubble
W.GAP = 8 -- between rows
W.BUBBLE = 0.78 -- of the list's width, at most
W.PLACEHOLDER = "Ask Spellmind… (shift-click items or quests to add them)"
W.EFFORT_NAMES = { low = "Low", medium = "Medium", high = "High", xhigh = "Extra high", max = "Max", none = "None", minimal = "Minimal" }
W.EFFORT_HINT = {
	low = "Fastest (about 3 s). Fine for plain questions.",
	medium = "Balanced. With web search, facts come from the web.",
	high = "Slower (about 10 s), more careful.",
	xhigh = "Slower still; uses more of your plan.",
	max = "The slowest and most thorough; uses the most of your plan.",
}

local COLORS = {
	you = { bg = { 0.20, 0.15, 0.05, 0.92 }, edge = { 0.85, 0.68, 0.25, 1 } },
	sm = { bg = { 0.13, 0.09, 0.24, 0.92 }, edge = { 0.58, 0.45, 0.98, 1 } },
}
local BUBBLE_BACKDROP = { bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } }

local win

W.WELCOME = "Ask me anything about your character: gear, talents, spells, quests, professions or gold.\n\nShift-click an item or a quest into the box to ask about it."
W.STARTERS = { "What should I train next?", "Any upgrades in my bags?", "Which quests should I do now?" }

W.MEDIA = "Interface\\AddOns\\Spellmind\\Media\\"

-- The gold corner trim (Media\Corner, a top-left piece, flipped for the other three).
function W.Corners(frame, size, inset)
	-- inset 2: inside the frame, over its border (at -3 they sat outside the window, seen in game).
	size, inset = size or 22, inset or 2
	frame.corners = frame.corners or {}
	local spots = {
		{ "TOPLEFT", inset, -inset, 0, 1, 0, 1 }, { "TOPRIGHT", -inset, -inset, 1, 0, 0, 1 },
		{ "BOTTOMLEFT", inset, inset, 0, 1, 1, 0 }, { "BOTTOMRIGHT", -inset, inset, 1, 0, 1, 0 },
	}
	for i, s in ipairs(spots) do
		local t = frame.corners[i] or frame:CreateTexture(nil, "OVERLAY", nil, 7)
		frame.corners[i] = t
		t:SetTexture(W.MEDIA .. "Corner")
		t:SetSize(size, size)
		t:SetTexCoord(s[4], s[5], s[6], s[7])
		t:ClearAllPoints()
		t:SetPoint(s[1], frame, s[1], s[2], s[3])
	end
end

-- A thin scrollbar on a scroll frame's right edge (the review and the player, 2026-11-13: no list
-- showed that it scrolls; the Settings tab "could use a scrollbar"). Shown only while there's more
-- than fits. The thumb's size is the share in view, its place the scroll; drag it to scroll. It
-- reads the scroll ten times a second while shown, so no caller has to tell it of a change.
-- x: its offset from the scroll frame's right edge (outside it when the content fills the width).
W.BAR_W = 4
function W.ScrollBar(scroll, x)
	local bar = CreateFrame("Button", nil, scroll:GetParent())
	bar:SetWidth(W.BAR_W + 4)
	bar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", (x or 0) + 2, 0)
	bar:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", (x or 0) + 2, 0)
	bar:SetFrameLevel((scroll:GetFrameLevel() or 1) + 5)
	local track = bar:CreateTexture(nil, "BACKGROUND")
	track:SetColorTexture(0.35, 0.28, 0.6, 0.18)
	track:SetPoint("TOP", bar, "TOP", 0, 0)
	track:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
	track:SetWidth(W.BAR_W)
	local thumb = bar:CreateTexture(nil, "ARTWORK")
	thumb:SetColorTexture(0.62, 0.49, 1, 0.55)
	thumb:SetWidth(W.BAR_W)
	bar.thumb, bar.track = thumb, track
	local function Range() return tonumber((scroll:GetVerticalScrollRange())) or 0 end
	local function ViewH() return tonumber((scroll:GetHeight())) or 0 end
	function bar.Update()
		local range, h = Range(), ViewH()
		if range <= 1 or h <= 0 then bar:Hide() return end
		bar:Show()
		local th = math.max(20, h * h / (h + range))
		local at = (tonumber((scroll:GetVerticalScroll())) or 0) / range
		thumb:SetHeight(th)
		thumb:ClearAllPoints()
		thumb:SetPoint("TOP", bar, "TOP", 0, -at * (h - th))
		bar.th = th
	end
	-- Dragging: the cursor's travel over the track's free length is the scroll's over its range.
	local function CursorY()
		local _, y = GetCursorPosition()
		local s = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
		return (tonumber(y) or 0) / s
	end
	bar:SetScript("OnMouseDown", function(self)
		self.drag = { y = CursorY(), from = tonumber((scroll:GetVerticalScroll())) or 0 }
	end)
	bar:SetScript("OnMouseUp", function(self) self.drag = nil end)
	bar:SetScript("OnEnter", function() thumb:SetColorTexture(0.85, 0.68, 0.25, 0.9) end)
	bar:SetScript("OnLeave", function(self) if not self.drag then thumb:SetColorTexture(0.62, 0.49, 1, 0.55) end end)
	local wait = 0
	bar:SetScript("OnUpdate", function(self, elapsed)
		if self.drag then
			local range, h = Range(), ViewH()
			local free = math.max(1, h - (self.th or 20))
			local y = self.drag.from + (self.drag.y - CursorY()) * range / free
			scroll:SetVerticalScroll(math.max(0, math.min(range, y)))
			self.Update()
			return
		end
		wait = wait - (elapsed or 0)
		if wait > 0 then return end
		wait = 0.1
		self.Update()
	end)
	-- Hidden, its OnUpdate stops: a timer keeps it in step until there's something to show.
	if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(0.5, function() if not bar:IsShown() and scroll:IsVisible() then bar.Update() end end) end
	bar.Update()
	return bar
end

-- A solid colour under a backdrop frame, inset past its border.
function W.Fill(frame, inset, r, g, b, a)
	local t = frame.fill or frame:CreateTexture(nil, "BACKGROUND", nil, -8)
	frame.fill = t
	t:SetColorTexture(r, g, b, a)
	t:ClearAllPoints()
	t:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
	t:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
	return t
end

local function UI()
	local db = ns.db
	if not db then return {} end
	if type(db.ui) ~= "table" then db.ui = {} end
	return db.ui
end

---------------------------------------------------------------------------
-- What the app offers (bridge.ai, read by Chat.lua into R.ai) and the player's picks
---------------------------------------------------------------------------

-- The thinking level to send: the player's pick when the app offers it, else nil (the app's default).
function W.Effort()
	local ai, pick = R.ai, UI().effort
	if type(ai) ~= "table" or type(pick) ~= "string" then return nil end
	for _, e in ipairs(type(ai.efforts) == "table" and ai.efforts or {}) do
		if e == pick then return pick end
	end
	return nil
end

-- Web search to send: true or false when the AI has it, else nil.
function W.Search()
	local ai = R.ai
	if type(ai) ~= "table" or ai.search ~= true then return nil end
	local pick = UI().search
	if pick == nil then return ai.searchOn ~= false end
	return pick and true or false
end

local function EffortLabel()
	local ai = R.ai
	local e = W.Effort() or (type(ai) == "table" and ai.effort) or nil
	return "Thinking: " .. (e and (W.EFFORT_NAMES[e] or e) or "Default")
end

---------------------------------------------------------------------------
-- The header's controls
---------------------------------------------------------------------------

local function SmallButton(parent, width)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(width, 20)
	if b.SetBackdrop then
		b:SetBackdrop(BUBBLE_BACKDROP)
		b:SetBackdropColor(0.08, 0.06, 0.16, 0.95)
		b:SetBackdropBorderColor(0.5, 0.4, 0.85, 1)
	end
	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
	b:SetScript("OnEnter", function(self)
		if self.SetBackdropBorderColor then self:SetBackdropBorderColor(0.85, 0.68, 0.25, 1) end
		if self.tip and GameTooltip then
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			GameTooltip:SetText(self.tip, 1, 1, 1, 1, true)
			GameTooltip:Show()
		end
	end)
	b:SetScript("OnLeave", function(self)
		if self.SetBackdropBorderColor then self:SetBackdropBorderColor(0.5, 0.4, 0.85, 1) end
		if GameTooltip then GameTooltip:Hide() end
	end)
	return b
end
W.SmallButton = SmallButton

-- The thinking menu: one row per level the app's model offers.
local function BuildMenu(f, name)
	local m = CreateFrame("Frame", name or "SpellmindEffortMenu", f, "BackdropTemplate")
	m:SetFrameStrata("FULLSCREEN_DIALOG")
	m:SetSize(230, 20)
	if m.SetBackdrop then
		m:SetBackdrop(BUBBLE_BACKDROP)
		m:SetBackdropColor(0.05, 0.04, 0.1, 0.98)
		m:SetBackdropBorderColor(0.58, 0.45, 0.98, 1)
	end
	m.rows = {}
	m:Hide()
	return m
end

function W.OpenMenu()
	local f = win
	if not f then return end
	local m = f.menu
	if m:IsShown() then m:Hide() return end
	local ai = R.ai
	local efforts = type(ai) == "table" and type(ai.efforts) == "table" and ai.efforts or {}
	for _, r in ipairs(m.rows) do r:Hide() end
	local y = -6
	for i, e in ipairs(efforts) do
		local r = m.rows[i]
		if not r then
			r = CreateFrame("Button", nil, m)
			r:SetSize(218, 34)
			r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			r.name:SetPoint("TOPLEFT", r, "TOPLEFT", 6, -2)
			r.hint = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
			r.hint:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -1)
			r.hint:SetWidth(206)
			r.hint:SetJustifyH("LEFT")
			r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
			m.rows[i] = r
		end
		local current = (W.Effort() or (type(ai) == "table" and ai.effort)) == e
		r.name:SetText((current and "|cffffd100> " or "") .. (W.EFFORT_NAMES[e] or e) .. (type(ai) == "table" and ai.effort == e and " |cff888888(default)|r" or ""))
		r.hint:SetText(W.EFFORT_HINT[e] or "")
		r.effort = e
		r:SetScript("OnClick", function(self)
			UI().effort = self.effort
			m:Hide()
			W.Refresh()
		end)
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", m, "TOPLEFT", 6, y)
		r:Show()
		y = y - 36
	end
	m:SetHeight(-y + 4)
	m:ClearAllPoints()
	m:SetPoint("TOPRIGHT", f.effort, "BOTTOMRIGHT", 0, -2)
	m:Show()
end

---------------------------------------------------------------------------
-- The conversation: rows of bubbles, pooled
---------------------------------------------------------------------------

local function NewRow(f)
	local row = CreateFrame("Frame", nil, f.content, "BackdropTemplate")
	row.text = row:CreateFontString(nil, "OVERLAY")
	row.text:SetFontObject(ChatFontNormal)
	row.text:SetJustifyH("LEFT")
	row.text:SetJustifyV("TOP")
	if row.text.SetWordWrap then row.text:SetWordWrap(true) end
	row.icon = f.content:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(22, 22)
	row.icon:SetTexture(W.PORTRAIT)
	row.icon:Hide()
	return row
end

local function NewChip(f)
	local c = SmallButton(f.content, 80)
	c:SetHeight(22)
	c.text:SetFontObject(GameFontHighlightSmall)
	c:SetScript("OnClick", function(self)
		if self.ask then ns.Chat.Send(self.ask, R.ask and { about = R.ask.about } or nil) end
	end)
	return c
end

-- Plain width of a text, for a short bubble that shouldn't span the list.
local function TextWidth(fs)
	local w = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()
	if type(w) ~= "number" or w <= 0 then w = fs:GetStringWidth() end
	return tonumber(w) or 100
end

-- Every row laid out again (after a new message, a resize or a /reload).
function W.Layout(stick)
	local f = win
	if not f or not ns.db then return end
	local msgs = ns.Chat.Msgs()
	-- While a question of this chat waits: a "Thinking…" bubble last (the review: with the double-check
	-- an answer takes 5 to 11 s, and only the grey status line said anything).
	if ns.Chat.WaitingIn and ns.db and ns.Chat.WaitingIn(ns.db.chat) then
		local copy = {}
		for i, m in ipairs(msgs) do copy[i] = m end
		local away = ns.Link and ns.Link.AppGone and ns.Link.AppGone()
		copy[#copy + 1] = { w = "sm", t = away and "|cff888888Waiting for the Spellmind app to start…|r" or "|cff888888Thinking…|r", pending = true }
		msgs = copy
	end
	-- Where the player is before the rows change: at the bottom (within a few pixels) or reading.
	local range0 = tonumber(f.scroll:GetVerticalScrollRange()) or 0
	local atBottom = (tonumber(f.scroll:GetVerticalScroll()) or 0) >= range0 - 12
	-- 12 px off the right edge: the scrollbar sits there (W.ScrollBar).
	local listW = math.max(200, (tonumber(f.scroll:GetWidth()) or (W.DEF_W - 24)) - 12)
	local maxText = math.floor(listW * W.BUBBLE) - 2 * W.PAD
	f.content:SetWidth(listW)
	local y = -4
	f.texts = {}
	for i, msg in ipairs(msgs) do
		local row = f.rows[i] or NewRow(f)
		f.rows[i] = row
		local who = msg.w
		row.text:SetText(msg.t or "")
		f.texts[#f.texts + 1] = msg.t or ""
		row:ClearAllPoints()
		row.text:ClearAllPoints()
		row.icon:Hide()
		if who == "you" or who == "sm" then
			row.text:SetWidth(maxText)
			local tw = math.min(maxText, TextWidth(row.text))
			row.text:SetWidth(tw)
			local th = tonumber(row.text:GetStringHeight()) or 14
			row:SetSize(tw + 2 * W.PAD, th + 2 * W.PAD - 2)
			if row.SetBackdrop then
				if not row.backdropSet then row:SetBackdrop(BUBBLE_BACKDROP); row.backdropSet = true end
				local c = COLORS[who]
				row:SetBackdropColor(c.bg[1], c.bg[2], c.bg[3], c.bg[4])
				row:SetBackdropBorderColor(c.edge[1], c.edge[2], c.edge[3], c.edge[4])
			end
			W.Fill(row, 3, COLORS[who].bg[1], COLORS[who].bg[2], COLORS[who].bg[3], 1)
			row.fill:Show()
			row.text:SetPoint("TOPLEFT", row, "TOPLEFT", W.PAD, -W.PAD + 1)
			if who == "you" then
				row:SetPoint("TOPRIGHT", f.content, "TOPRIGHT", -2, y)
			else
				row:SetPoint("TOPLEFT", f.content, "TOPLEFT", 30, y)
				row.icon:ClearAllPoints()
				row.icon:SetPoint("TOPLEFT", f.content, "TOPLEFT", 2, y - 2)
				row.icon:Show()
			end
			y = y - (th + 2 * W.PAD - 2) - W.GAP
		else
			-- A line of Spellmind's own (a system note or an error): no bubble, centred.
			if row.SetBackdropColor and row.backdropSet then
				row:SetBackdropColor(0, 0, 0, 0)
				row:SetBackdropBorderColor(0, 0, 0, 0)
			end
			if row.fill then row.fill:Hide() end
			row.text:SetWidth(listW - 20)
			local th = tonumber(row.text:GetStringHeight()) or 14
			row:SetSize(listW - 20, th)
			row:SetPoint("TOPLEFT", f.content, "TOPLEFT", 10, y)
			row.text:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
			y = y - th - W.GAP
		end
		row:Show()
	end
	for i = #msgs + 1, #f.rows do f.rows[i]:Hide(); f.rows[i].icon:Hide() end
	-- Nothing said yet: a welcome, with starter chips.
	f.welcome:SetShown(#msgs == 0)
	if #msgs == 0 then
		f.welcome:SetWidth(listW - 40)
		f.welcome:ClearAllPoints()
		f.welcome:SetPoint("TOP", f.content, "TOP", 0, -16)
		y = -16 - (tonumber(f.welcome:GetStringHeight()) or 40) - 14
	end
	-- The chips of the last reply, when it's the last message (or the starters).
	for _, c in ipairs(f.chips) do c:Hide() end
	local last = msgs[#msgs]
	f.chipTexts = {}
	local asks = #msgs == 0 and W.STARTERS or (last and last.w == "sm" and type(last.c) == "table" and #last.c > 0 and last.c) or nil
	if asks then
		local x = #msgs == 0 and 10 or 30
		y = y + W.GAP - 4
		for i, ask in ipairs(asks) do
			local c = f.chips[i] or NewChip(f)
			f.chips[i] = c
			c.text:SetText(ask)
			c.ask = ask
			local cw = math.min(listW - 34, TextWidth(c.text) + 18)
			c:SetWidth(cw)
			if x + cw > listW then x = 30; y = y - 26 end
			c:ClearAllPoints()
			c:SetPoint("TOPLEFT", f.content, "TOPLEFT", x, y)
			c:Show()
			f.chipTexts[#f.chipTexts + 1] = ask
			x = x + cw + 6
		end
		y = y - 22 - W.GAP
	end
	f.content:SetHeight(math.max(10, -y))
	-- The newest at the bottom, in view: when the player was at the bottom already, or just asked
	-- (stick); left alone when they scrolled up to read. The scroll range only catches up with the
	-- new height on the next frame (seen in game: it stopped one reply short), so again then.
	if stick or atBottom then W.ScrollToEnd() end
end

function W.ScrollToEnd()
	local f = win
	if not f then return end
	local function go()
		if f.scroll.UpdateScrollChildRect then f.scroll:UpdateScrollChildRect() end
		f.scroll:SetVerticalScroll(tonumber(f.scroll:GetVerticalScrollRange()) or 0)
	end
	go()
	W.scrolls = (W.scrolls or 0) + 1
	if C_Timer and C_Timer.After then C_Timer.After(0, go) end
end

---------------------------------------------------------------------------
-- The input: text, and shift-clicked links
---------------------------------------------------------------------------

-- A link shift-clicked anywhere in the game while the box has focus goes into it.
local function HookLinks()
	if W.linksHooked then return end
	local function insert(link)
		if win and win:IsShown() and win.input:HasFocus() and type(link) == "string" then win.input:Insert(link) end
	end
	local util = rawget(_G, "ChatFrameUtil")
	if type(util) == "table" and type(util.InsertLink) == "function" then
		hooksecurefunc(util, "InsertLink", insert)
	elseif type(rawget(_G, "ChatEdit_InsertLink")) == "function" then
		hooksecurefunc("ChatEdit_InsertLink", insert)
	end
	W.linksHooked = true
end

local function Send(self)
	local text = self:GetText()
	if text and text:match("%S") then
		local key, _, why = ns.Chat.SendTyped(text)
		if key or why == "key" then self:SetText("") end
	end
	-- Like the game's own chat box: Enter leaves it, so the movement keys move the character again.
	self:ClearFocus()
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

-- The chat: the Spellmind window's Chat tab (Panel.lua, 2026-11-12: one window, the chat at the top of
-- its rail). This frame fills the window's content area; the window's header, place, size, fold and
-- compact mode are the panel's. The status line sits in the window's header while the Chat tab shows.
function W.Build()
	if win then return win end
	local p = ns.Panel.Build()
	local f = CreateFrame("Frame", "SpellmindWindow", p)
	f:SetSize(W.DEF_W, W.DEF_H)
	f:SetPoint("TOPLEFT", p, "TOPLEFT", 8, -54)

	-- Status in the window's header (where the other tabs say who): the link, the AI, what it's about.
	f.status = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.status:SetPoint("TOPLEFT", p, "TOPLEFT", 52, -31)
	f.status:SetPoint("TOPRIGHT", p, "TOPRIGHT", -84, -31) -- clear of the compact, fold and close buttons
	f.status:SetJustifyH("LEFT")
	if f.status.SetWordWrap then f.status:SetWordWrap(false) end

	-- The chat's own row: thinking and web search at the left, Chats and + New at the right.
	f.effort = SmallButton(f, 120)
	f.effort:SetPoint("TOPLEFT", f, "TOPLEFT", 2, 0)
	-- A real dropdown: the label at the left, the gold chevron at the right.
	f.effort.text:ClearAllPoints()
	f.effort.text:SetPoint("LEFT", f.effort, "LEFT", 8, 0)
	f.effort.arrow = f.effort:CreateTexture(nil, "OVERLAY")
	f.effort.arrow:SetSize(12, 12)
	f.effort.arrow:SetPoint("RIGHT", f.effort, "RIGHT", -6, 0)
	f.effort.arrow:SetTexture(W.MEDIA .. "Chevron")
	f.effort.tip = "How hard your AI thinks before it answers. Higher is slower and more careful."
	f.effort:SetScript("OnClick", function() W.OpenMenu() end)
	f.search = SmallButton(f, 100)
	f.search:SetPoint("LEFT", f.effort, "RIGHT", 6, 0)
	f.search:SetScript("OnClick", function()
		UI().search = not W.Search()
		W.Refresh()
	end)
	f.menu = BuildMenu(f)
	f.chatsMenu = BuildMenu(f, "SpellmindChatsMenu")
	-- Chats: the list of recent ones, and a new one.
	f.new = SmallButton(f, 58)
	f.new.text:SetText("+ New")
	f.new.tip = "Start a new chat. This one stays in Chats."
	f.new:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, 0)
	f.new:SetScript("OnClick", function() ns.Chat.NewChat() end)
	f.chats = SmallButton(f, 74)
	f.chats.text:ClearAllPoints()
	f.chats.text:SetPoint("LEFT", f.chats, "LEFT", 8, 0)
	f.chats.text:SetText("Chats")
	f.chats.arrow = f.chats:CreateTexture(nil, "OVERLAY")
	f.chats.arrow:SetSize(11, 11)
	f.chats.arrow:SetPoint("RIGHT", f.chats, "RIGHT", -6, 0)
	f.chats.arrow:SetTexture(W.MEDIA .. "Chevron")
	f.chats.tip = "Your recent chats: pick one to go back to it."
	f.chats:SetPoint("RIGHT", f.new, "LEFT", -6, 0)
	f.chats:SetScript("OnClick", function() W.OpenChats() end)

	-- The conversation.
	f.scroll = CreateFrame("ScrollFrame", nil, f)
	f.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -28)
	f.scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 36)
	f.content = CreateFrame("Frame", nil, f.scroll)
	f.content:SetSize(W.DEF_W - 24, 10)
	f.scroll:SetScrollChild(f.content)
	f.scroll:EnableMouseWheel(true)
	f.scroll:SetScript("OnMouseWheel", function(self, delta)
		local range = tonumber(self:GetVerticalScrollRange()) or 0
		local y = (tonumber(self:GetVerticalScroll()) or 0) - delta * 40
		self:SetVerticalScroll(math.max(0, math.min(range, y)))
	end)
	f.rows, f.chips = {}, {}
	f.bar = W.ScrollBar(f.scroll, -2)
	f.welcome = f.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.welcome:SetJustifyH("CENTER")
	f.welcome:SetJustifyV("TOP")
	if f.welcome.SetWordWrap then f.welcome:SetWordWrap(true) end
	f.welcome:SetText(W.WELCOME)

	-- The input and the send button.
	f.input = CreateFrame("EditBox", nil, f, "BackdropTemplate")
	f.input:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 2, 4)
	f.input:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -36, 4)
	f.input:SetHeight(26)
	if f.input.SetBackdrop then
		f.input:SetBackdrop(BUBBLE_BACKDROP)
		f.input:SetBackdropColor(0.07, 0.05, 0.14, 0.95)
		f.input:SetBackdropBorderColor(0.5, 0.4, 0.85, 1)
	end
	f.input:SetFontObject(ChatFontNormal)
	f.input:SetTextInsets(8, 8, 0, 0)
	f.input:SetAutoFocus(false)
	f.input:SetMaxBytes(ns.MAX_TEXT + 1)
	f.input:SetScript("OnEnterPressed", Send)
	f.input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	f.input:SetScript("OnTextChanged", function() W.Placeholder() end)
	f.input:SetScript("OnEditFocusGained", function() W.Placeholder() end)
	f.input:SetScript("OnEditFocusLost", function() W.Placeholder() end)
	f.hint = f.input:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.hint:SetPoint("LEFT", f.input, "LEFT", 9, 0)
	f.hint:SetText(W.PLACEHOLDER)
	f.send = SmallButton(f, 30)
	f.send:SetHeight(26)
	f.send:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 4)
	f.send.tip = "Send (Enter)"
	f.send.arrow = f.send:CreateTexture(nil, "OVERLAY")
	f.send.arrow:SetSize(16, 16)
	f.send.arrow:SetPoint("CENTER", f.send, "CENTER", 1, 0)
	f.send.arrow:SetTexture(W.MEDIA .. "Send")
	f.send:SetScript("OnClick", function() Send(f.input) end)

	f:SetScript("OnSizeChanged", function() if win then W.Layout() end end)
	f:Hide()
	win = f
	HookLinks()
	W.Refresh()
	W.Layout()
	return f
end

function W.Get() return win end

-- "now", "5m ago", "2h ago", "3d ago".
function W.Ago(at)
	local d = math.max(0, time() - (tonumber(at) or 0))
	if d < 60 then return "now" end
	if d < 3600 then return math.floor(d / 60) .. "m ago" end
	if d < 86400 then return math.floor(d / 3600) .. "h ago" end
	return math.floor(d / 86400) .. "d ago"
end

-- The chats menu: the recent chats, newest first, the current one marked.
function W.OpenChats()
	local f = win
	if not f then return end
	local m = f.chatsMenu
	if m:IsShown() then m:Hide() return end
	f.menu:Hide()
	for _, r in ipairs(m.rows) do r:Hide() end
	local y = -6
	m.items = ns.Chat.List()
	for i, c in ipairs(m.items) do
		local r = m.rows[i]
		if not r then
			r = CreateFrame("Button", nil, m)
			r:SetSize(258, 22)
			r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			r.name:SetPoint("LEFT", r, "LEFT", 6, 0)
			r.name:SetWidth(190)
			r.name:SetJustifyH("LEFT")
			if r.name.SetWordWrap then r.name:SetWordWrap(false) end
			r.age = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
			r.age:SetPoint("RIGHT", r, "RIGHT", -6, 0)
			r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
			m.rows[i] = r
		end
		r.name:SetText((c.current and "|cffffd100> " or "") .. (c.title or "New chat") .. (c.current and "|r" or ""))
		r.age:SetText(W.Ago(c.at))
		r.id = c.id
		r:SetScript("OnClick", function(self)
			m:Hide()
			ns.Chat.SwitchChat(self.id)
		end)
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", m, "TOPLEFT", 6, y)
		r:Show()
		y = y - 24
	end
	m:SetSize(270, -y + 4)
	m:ClearAllPoints()
	m:SetPoint("TOPRIGHT", f.chats, "BOTTOMRIGHT", 0, -2)
	m:Show()
end

function W.Placeholder()
	local f = win
	if not f then return end
	local empty = (f.input:GetText() or "") == ""
	f.hint:SetShown(empty and not f.input:HasFocus())
end

-- The header's controls and the status line, from R.ai and the link's status.
function W.Refresh()
	local f = win
	if not f then return end
	local ai = R.ai
	local hasAI = type(ai) == "table"
	f.effort:SetShown(hasAI and type(ai.efforts) == "table" and #ai.efforts > 0)
	f.effort.text:SetText(EffortLabel())
	-- As wide as its words and the chevron (the review: "Medium" touched the arrow; "Extra high" ran under it).
	f.effort:SetWidth(math.max(100, (tonumber(f.effort.text:GetStringWidth()) or 90) + 30))
	local search = W.Search()
	f.search:SetShown(search ~= nil)
	f.search.text:SetText("Web search: " .. (search and "|cff19ff19On|r" or "|cff888888Off|r"))
	f.search.tip = "Lets your AI look up facts on the web (trainers, quest turn-ins, drops). Off answers from its memory."
	local bits = {}
	local link = ns.Link.Status()
	-- Not "Connected" when the app says its AI isn't set up (the audit: the player learned only by asking).
	if link == "" and hasAI and ai.ready == false then link = "|cffff9933Set up your AI in the Spellmind app|r" end
	bits[#bits + 1] = (link ~= "" and link) or "Connected"
	if hasAI then
		if type(ai.name) == "string" and ai.name ~= "" then bits[#bits + 1] = ns.Escape(ai.name) end
		if type(ai.model) == "string" and ai.model ~= "" then bits[#bits + 1] = ns.Escape(ai.model) end
	end
	local about = R.ask and R.ask.label and ("  |cff9d7dffAbout: " .. R.ask.label .. "|r") or ""
	f.status:SetText(table.concat(bits, " · ") .. about)
	W.Placeholder()
end
