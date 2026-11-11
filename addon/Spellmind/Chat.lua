-- Spellmind: adapted from NeverQuestAlone's addon/NeverQuestAlone/Chats.lua (MIT; see NOTICE.md).
-- Chat.lua: /spellmind and /sm, the one chat's sends, and its answers in a small window.
--
--   /sm            show or hide the window
--   /sm <words>    ask Spellmind (the window's box does the same)
--   /sm data       what the app gets of your character; /sm data off and /sm data on
--
-- Answers arrive through Link.lua (slot records reply, error and aborted) and show in the window
-- and, shortened, in the chat frame. The app's text comes with every | doubled already; what the
-- player typed is shown with its | doubled here, so nothing shown can form a game escape.

local _, ns = ...
local C = {}
ns.Chat = C
local R = ns.R

local SHORT_MAX = 240 -- bytes of an answer shown in the chat frame
local CHAT_LINES_MAX = 4 -- a reply this short (lines and bytes) shows whole in the chat frame
local CHAT_BYTES_MAX = 600
local WHO = "|cff9d7dffSpellmind:|r "
local YOU = "|cffffd100You:|r "
local ERR = "|cffff6060Spellmind:|r "
C.KEY_REFUSED = "That looks like an API key, so it wasn't sent. Keys go in the Spellmind app, never in game."
C.NOT_HEARD = "Start the Spellmind app to get answers."

---------------------------------------------------------------------------
-- What may be sent
---------------------------------------------------------------------------

-- KY-10: generated from core/ai/security/keycheck.mjs (KEY_SHAPES, GLUED_SHAPES); do not edit by hand.
local KEY_PATTERNS = {
	"%f[%w]sk%-ant%-[%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-]",
	"%f[%w]sk%-proj%-[%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-]",
	"%f[%w]sk%-svcacct%-[%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-]",
	"%f[%w]sk%-admin%-[%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-]",
	"%f[%w]sk%-None%-[%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-]",
	"%f[%w]sk%-or%-[%w%-][%w%-][%w%-][%w%-][%w%-][%w%-][%w%-][%w%-][%w%-][%w%-]",
	"%f[%w]sk%-%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w",
	"%f[%w]AIza[%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-]",
	"%f[%w]AQ%.[%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-]",
	"%f[%w]xai%-[%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_]",
	"%f[%w]gsk_%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w",
	"sk%-ant%-api[%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-]",
	"sk%-ant%-admin[%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-]",
	"sk%-ant%-oat[%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-]",
	"sk%-or%-v1%-%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w",
	"AIza[%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-]",
	"gsk_%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w%w",
}
-- Glued shapes that also need a digit in the run after the prefix: { pattern, prefix length }.
local KEY_DIGIT_PATTERNS = {
	{ "sk%-proj%-[%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-]*", 8 },
	{ "sk%-svcacct%-[%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-]*", 11 },
	{ "sk%-admin%-[%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-]*", 9 },
	{ "sk%-None%-[%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-]*", 8 },
	{ "AQ%.[%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-]*", 3 },
	{ "xai%-[%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_][%w_]*", 4 },
}
local LooksLikeKey = function(s)
	if type(s) ~= "string" or #s < 13 then return false end
	for i = 1, #KEY_PATTERNS do
		if string.find(s, KEY_PATTERNS[i]) then return true end
	end
	for i = 1, #KEY_DIGIT_PATTERNS do
		local p, n, init = KEY_DIGIT_PATTERNS[i][1], KEY_DIGIT_PATTERNS[i][2], 1
		while true do
			local a, b = string.find(s, p, init)
			if not a then break end
			if string.find(string.sub(s, a + n, b), "%d") then return true end
			init = a + 1
		end
	end
	return false
end


-- Characters that hide inside a pasted key (control bytes, soft hyphen, zero-width spaces and
-- joiners, word joiner, byte-order mark) go before a second look.
local function Visible(s)
	s = s:gsub("%c", "")
	s = s:gsub("\194\173", ""):gsub("\226\128[\139-\143]", ""):gsub("\226\129\160", ""):gsub("\239\187\191", "")
	return s
end

function C.KeyShaped(s)
	if type(s) ~= "string" then return false end
	return LooksLikeKey(s) or LooksLikeKey(Visible(s))
end

-- "[Spellmind" starts only what the addon and the app write, so typed text can't pass for one.
local RESERVED_PATTERN = "^%[" .. ns.RESERVED:sub(2):gsub("%a", function(c) return "[" .. c:upper() .. c:lower() .. "]" end)

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

local win

local function Build()
	if win then return win end
	local f = CreateFrame("Frame", "SpellmindWindow", UIParent, "BackdropTemplate")
	f:SetSize(440, 300)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
	f:SetFrameStrata("DIALOG")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
	if f.SetBackdrop then
		f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
		f:SetBackdropColor(0.05, 0.05, 0.08, 0.92)
		f:SetBackdropBorderColor(0.62, 0.49, 1, 1)
	end

	-- The persona's portrait (Media\Portrait.tga, a round wisp) beside the title.
	f.portrait = f:CreateTexture(nil, "ARTWORK")
	f.portrait:SetSize(32, 32)
	f.portrait:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -6)
	f.portrait:SetTexture("Interface\\AddOns\\Spellmind\\Media\\Portrait")

	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 46, -10)
	f.title:SetText("Spellmind: AI Companion")

	f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)

	f.status = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.status:SetPoint("TOPLEFT", f, "TOPLEFT", 46, -26)
	f.status:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -28)
	f.status:SetJustifyH("LEFT")

	f.log = CreateFrame("ScrollingMessageFrame", nil, f)
	f.log:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -44)
	f.log:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 40)
	f.log:SetFontObject(ChatFontNormal)
	f.log:SetJustifyH("LEFT")
	f.log:SetFading(false)
	f.log:SetMaxLines(500)
	f.log:SetHyperlinksEnabled(false)
	f.log:EnableMouseWheel(true)
	f.log:SetScript("OnMouseWheel", function(self, delta)
		if delta > 0 then self:ScrollUp() else self:ScrollDown() end
	end)

	f.input = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	f.input:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 18, 12)
	f.input:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
	f.input:SetHeight(22)
	f.input:SetAutoFocus(false)
	f.input:SetMaxBytes(ns.MAX_TEXT + 1)
	f.input:SetScript("OnEnterPressed", function(self)
		local text = self:GetText()
		if text and text:match("%S") then
			local key, _, why = C.Send(text)
			-- Sent, or refused as a key: either way the box keeps nothing.
			if key or why == "key" then self:SetText("") end
		end
		-- Like the game's own chat box: Enter leaves it, so the movement keys move the character
		-- again instead of typing into the box (a player's "wwawa", 2026-11-10).
		self:ClearFocus()
	end)
	f.input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

	if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "SpellmindWindow") end
	f:Hide()
	for _, line in ipairs(ns.db and ns.db.lines or {}) do f.log:AddMessage(line) end
	win = f
	C.Refresh()
	return f
end

function C.IsOpen()
	return win ~= nil and win:IsShown() and true or false
end

function C.Toggle()
	local f = Build()
	if f:IsShown() then
		f:Hide()
	else
		f:Show()
		C.Refresh()
		f.input:SetFocus()
	end
end

-- One shown line: into the window (if it's been made) and the saved lines.
local function AddLine(line)
	local lines = ns.db.lines
	lines[#lines + 1] = line
	while #lines > ns.MAX_LINES do table.remove(lines, 1) end
	if win then win.log:AddMessage(line) end
end

-- Text with newlines as window lines: the prefix on the first.
local function AddText(prefix, text)
	local first = true
	for line in (tostring(text) .. "\n"):gmatch("(.-)\n") do
		AddLine(first and (prefix .. line) or line)
		first = false
	end
end

local function ChatFrame(text)
	local frame = DEFAULT_CHAT_FRAME
	if frame and frame.AddMessage then frame:AddMessage(text) end
end

-- The first line of an answer, at most SHORT_MAX bytes (the app's escapes kept safe).
local function Short(text)
	local line = tostring(text or ""):match("^[^\n]*") or ""
	local cut = ns.Utf8Cut(line, SHORT_MAX)
	local more = #cut < #tostring(text or "")
	return ns.SafeText(cut) .. (more and " ..." or "")
end

-- A line of the addon's own, in the window and the chat frame.
function C.System(text)
	if not ns.db then return end
	AddText(WHO, text)
	ChatFrame("Spellmind: " .. text)
end

function C.Refresh()
	if not win then return end
	win.status:SetText(ns.Link.Status())
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------

-- The sends that wait for their answer, oldest first: { key, t }.
local function Pending()
	R.pending = R.pending or {}
	return R.pending
end

function C.Waiting()
	return Pending()[1]
end

-- Ask Spellmind. Returns the record's key, or nil, a reason and (for a key-shaped text) "key".
function C.Send(text)
	local db = ns.db
	if not db or not R.nonce then return nil, "Not ready yet: try again in a moment." end
	text = ns.Trim(text)
	if text == "" then return nil, "There's nothing to send." end
	-- Before anything keeps it: no window line, no outbox.
	if C.KeyShaped(text) then
		C.System(C.KEY_REFUSED)
		return nil, C.KEY_REFUSED, "key"
	end
	if text:find(RESERVED_PATTERN) then
		C.System("Not sent: a message can't start with \"[Spellmind\". The addon keeps that for its own lines.")
		return nil, "It can't start with \"[Spellmind\"."
	end
	if #text > ns.MAX_TEXT then
		C.System("That message is too long to send. Split it into shorter messages.")
		return nil, "Too long: split it into shorter messages."
	end
	if ns.Link.TypedWaiting() >= ns.Link.TYPED_MAX then
		C.System("Not sent: other messages are still on their way. Send it again in a moment.")
		return nil, "Other messages are still on their way."
	end
	local args = { { "cur", db.cursor }, { "agent", ns.DEFAULT_AGENT }, { "ctx", 0 } }
	-- The character's state built first, so the message and its parts come out in one draw; st
	-- names the parts the app hasn't confirmed ("" when it has them all, none: no game data).
	local st = ns.State and ns.State.BeforeSend()
	if st then args[#args + 1] = { "st", st } end
	local key = ns.Link.NewKeyed("msg", db.chat, args, ns.CleanField(text))
	if not key then return nil, "Not ready yet: try again in a moment." end
	table.insert(Pending(), { key = key, t = time() })
	AddText(YOU, ns.Escape(text))
	if not ns.Link.BridgeAlive() and not R.toldStart then
		R.toldStart = true
		C.System(C.NOT_HEARD)
	end
	ns.Link.AfterSend()
	C.Refresh()
	return key
end

function C.OnAcked(key, o)
	for _, p in ipairs(Pending()) do
		if p.key == key then p.acked = true end
	end
end

---------------------------------------------------------------------------
-- Answers
---------------------------------------------------------------------------

-- A reply, error or aborted record for our chat (Link.ApplyRecords). replay = 1: it was
-- applied before a client crash rolled the cursor back, so it's shown without the chat frame.
function C.OnRecord(r, replay)
	local kind = r.t
	if not replay then table.remove(Pending(), 1) end
	local text
	if kind == "reply" then
		text = ns.SafeText(r.text)
		local more = math.max(0, math.floor(tonumber(r.more) or 0))
		AddText(WHO, text .. (more > 0 and " |cff888888(the rest is in the Spellmind app)|r" or ""))
		if not replay then
			-- A short reply goes to the chat frame whole, line by line: its first line alone can be
			-- "…across three talents:" with the list below it (a player's, 2026-11-10). A longer one
			-- shows its summary and says the rest is in the window.
			local lines = {}
			for line in tostring(text):gmatch("[^\n]+") do
				if line:match("%S") then lines[#lines + 1] = line end
			end
			if #lines > 0 and #lines <= CHAT_LINES_MAX and #text <= CHAT_BYTES_MAX then
				for i, line in ipairs(lines) do ChatFrame((i == 1 and "Spellmind: " or "   ") .. line) end
			else
				local summary = type(r.summary) == "string" and r.summary ~= "" and ns.SafeText(r.summary) or nil
				ChatFrame("Spellmind: " .. (summary or Short(r.text)) .. " |cff888888(more: /sm)|r")
			end
		end
	elseif kind == "error" then
		text = ns.SafeText(r.text)
		AddText(ERR, text)
		if not replay then ChatFrame("Spellmind: " .. Short(r.text)) end
	else
		text = ns.SafeText(type(r.text) == "string" and r.text ~= "" and r.text or "Stopped.")
		AddText(WHO, text)
		if not replay then ChatFrame("Spellmind: " .. Short(text)) end
	end
	C.Refresh()
end

---------------------------------------------------------------------------
-- Slash commands and start
---------------------------------------------------------------------------

SLASH_SPELLMIND1 = "/spellmind"
SLASH_SPELLMIND2 = "/sm"
SlashCmdList.SPELLMIND = function(msg)
	msg = ns.Trim(msg)
	if msg == "" then
		C.Toggle()
		return
	end
	-- /sm probe: the API probe (Probe.lua), saved for the next /reload. Never sent anywhere.
	if msg:lower() == "probe" and ns.Probe then
		local n = ns.Probe()
		ChatFrame(("Spellmind: probed %d client functions. Type /reload to save the results."):format(n))
		return
	end
	-- /sm data: what the app gets of the character; /sm data off and /sm data on.
	local lower = msg:lower()
	local data = (lower == "data" and "") or lower:match("^data%s+(%a+)$")
	if data and ns.State and ns.db then
		if data == "off" then
			ns.State.Off()
			ChatFrame("Spellmind: game data is off. The app forgets your character and gets none of it. Type /sm data on to send it again.")
		elseif data == "on" then
			ns.State.On()
			ChatFrame("Spellmind: game data is on. The app gets your character again (never your name, realm or guild).")
		elseif data == "" then
			for _, line in ipairs(ns.State.Report()) do ChatFrame("Spellmind: " .. line) end
		else
			ChatFrame("Spellmind: /sm data shows what the app gets; /sm data off and /sm data on stop and start it.")
		end
		return
	end
	C.Send(msg)
end

ns.On("ADDON_LOADED", function(_, name)
	if name == ns.ADDON then ns.InitDB() end
end)

ns.On("PLAYER_LOGIN", function()
	if not ns.db then ns.InitDB() end
	ns.Link.Start()
	-- Messages drawn again after a /reload still wait for their answers.
	local keys = {}
	for key, o in pairs(R.out) do
		if o.type == "msg" then keys[#keys + 1] = { key = key, n = o.n } end
	end
	table.sort(keys, function(a, b) return a.n < b.n end)
	for _, k in ipairs(keys) do table.insert(Pending(), { key = k.key, t = time() }) end
	C.Refresh()
end)
