-- Spellmind: adapted from NeverQuestAlone's addon/NeverQuestAlone/Chats.lua (MIT; see NOTICE.md).
-- Chat.lua: /spellmind and /sm, the one chat's sends, and its answers in a small window.
--
--   /sm            show or hide the window
--   /sm <words>    ask Spellmind (the window's box does the same)
--   /sm data       what the app gets of your character; /sm data off and /sm data on
--   /sm settings   every switch (the Settings tab); /sm panel the last tab other than Chat
--   /sm guide <link>  your leveling guide: your AI reads it, the Talents tab follows it
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
C.NOT_HEARD = "Start the Spellmind app to get answers. No app yet? Type /sm app."

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
-- The conversation (Window.lua draws it)
---------------------------------------------------------------------------

C.MSGS_MAX = 80 -- messages kept in saved data (SpellmindDB.msgs)

function C.IsOpen()
	return ns.Panel.ChatOpen()
end

-- The window on its Chat tab, or closed when that's what shows.
-- focus: put the keyboard in the box (/sm typed by hand). A minimap click doesn't, so the movement
-- keys keep moving the character (the review).
function C.Toggle(focus)
	if ns.Panel.ChatOpen() then
		ns.Panel.Get():Hide()
	else
		ns.Panel.Show("chat")
		C.Refresh()
		if focus then ns.Window.Get().input:SetFocus() end
	end
end

-- One flat line into the saved lines (the window's history as text, for /reload and the tests).
local function AddLine(line)
	local lines = ns.db.lines
	lines[#lines + 1] = line
	while #lines > ns.MAX_LINES do table.remove(lines, 1) end
end

-- Text with newlines as flat lines: the prefix on the first.
local function AddText(prefix, text)
	local first = true
	for line in (tostring(text) .. "\n"):gmatch("(.-)\n") do
		AddLine(first and (prefix .. line) or line)
		first = false
	end
end

---------------------------------------------------------------------------
-- Chats (milestone 6): up to CHATS_MAX conversations, each { title, at, msgs }, in SpellmindDB.chats;
-- SpellmindDB.chat is the one the window shows and new questions go to. The app keeps each one's
-- history by its id. After a break of NEW_AFTER seconds, the next question starts a new one.
---------------------------------------------------------------------------

C.CHATS_MAX = 10
C.NEW_AFTER = 4 * 3600
C.TITLE_MAX = 48

local function Chats()
	local db = ns.db
	if type(db.chats) ~= "table" then db.chats = {} end
	return db.chats
end

-- A chat's entry, made when it isn't there.
local function Entry(id)
	local chats = Chats()
	local e = chats[id]
	if type(e) ~= "table" then
		e = { at = time(), msgs = {} }
		chats[id] = e
	end
	if type(e.msgs) ~= "table" then e.msgs = {} end
	return e
end

-- The current chat's messages (Window.lua draws them).
function C.Msgs()
	if not ns.db then return {} end
	return Entry(ns.db.chat).msgs
end

function C.Known(id)
	return type(id) == "string" and ns.db ~= nil and type(Chats()[id]) == "table"
end

-- The chats, newest first: { id, title, at, current, n }.
function C.List()
	local out = {}
	for id, e in pairs(Chats()) do
		if type(e) == "table" and type(e.msgs) == "table" and (#e.msgs > 0 or id == ns.db.chat) then
			out[#out + 1] = { id = id, title = e.title or "New chat", at = tonumber(e.at) or 0, current = id == ns.db.chat, n = #e.msgs }
		end
	end
	table.sort(out, function(a, b) return a.at > b.at end)
	return out
end

-- Older chats past CHATS_MAX go (never the current one, nor one with an answer on its way).
local function Prune()
	local list = C.List()
	local busy = {}
	for _, p in ipairs(R.pending or {}) do if p.chat then busy[p.chat] = true end end
	-- The current one always stays; of the others, the newest CHATS_MAX - 1.
	local kept = 0
	for _, c in ipairs(list) do
		if not c.current then
			kept = kept + 1
			if kept > C.CHATS_MAX - 1 and not busy[c.id] then Chats()[c.id] = nil end
		end
	end
	for id, e in pairs(Chats()) do
		if type(e) == "table" and type(e.msgs) == "table" and #e.msgs == 0 and id ~= ns.db.chat and not busy[id] then Chats()[id] = nil end
	end
end

-- A new, empty chat becomes the current one (nothing happens when the current one is empty already).
function C.NewChat()
	local db = ns.db
	if not db then return end
	if #C.Msgs() == 0 then return db.chat end
	db.chat = ns.NewChatId()
	Entry(db.chat)
	R.ask = nil
	Prune()
	if ns.Window.Get() then ns.Window.Layout(true) end
	C.Refresh()
	return db.chat
end

function C.SwitchChat(id)
	if not C.Known(id) then return end
	ns.db.chat = id
	R.ask = nil
	if ns.Window.Get() then ns.Window.Layout(true) end
	C.Refresh()
end

-- PLAYER_LOGIN: the single chat of before (SpellmindDB.msgs) becomes the first entry.
function C.InitChats()
	local db = ns.db
	local e = Entry(db.chat)
	if type(db.msgs) == "table" then
		if #e.msgs == 0 then e.msgs = db.msgs end
		db.msgs = nil
	end
	if not e.title then
		for _, m in ipairs(e.msgs) do
			if m.w == "you" then e.title = C.Title(m.t); break end
		end
	end
	Prune()
end

-- A chat's title: its first question, plain, at most TITLE_MAX bytes.
function C.Title(shown)
	local s = tostring(shown or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("||", "|"):gsub("%s+", " ")
	s = ns.Trim(s)
	if #s > C.TITLE_MAX then s = ns.Utf8Cut(s, C.TITLE_MAX - 3) .. "..." end
	return ns.Escape(s)
end

-- One message of a chat (the current one by default): who ("you", "sm", "sys" or "err"), its shown
-- text (escaped), and a reply's chips. Drawn as a bubble when it's the window's chat.
local function AddMsg(who, text, chips, chatId, pins)
	local id = chatId or ns.db.chat
	local e = Entry(id)
	e.msgs[#e.msgs + 1] = { w = who, t = tostring(text), c = chips, p = pins }
	while #e.msgs > C.MSGS_MAX do table.remove(e.msgs, 1) end
	e.at = time()
	if who == "you" and not e.title then e.title = C.Title(text) end
	if id == ns.db.chat and ns.Window.Get() then ns.Window.Layout(who == "you") end
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
	AddMsg("sys", "|cff9d7dff" .. text .. "|r")
	ChatFrame("Spellmind: " .. text)
end

function C.Refresh()
	ns.Window.Refresh()
end

-- The window open with its box focused; text (when given) put in the box to edit first.
function C.Open(text)
	ns.Panel.Show("chat")
	local f = ns.Window.Get()
	if text then f.input:SetText(text) end
	f.input:SetFocus()
	ns.Window.Layout(true)
	C.Refresh()
end

-- Marks.lua: what the next questions from the window are about (nil: nothing). label is shown
-- escaped already.
function C.AskAbout(about, label)
	R.ask = about and { about = about, label = label } or nil
	C.Refresh()
end

---------------------------------------------------------------------------
-- Links in what the player types (shift-clicked items and quests)
---------------------------------------------------------------------------

-- The text as it's sent: a link becomes its [Name], and every other escape goes.
function C.PlainText(text)
	local s = tostring(text or "")
	s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:|]*:", ""):gsub("|r", "")
	s = s:gsub("|H[^|]*|h(.-)|h", "%1"):gsub("|T[^|]*|t", ""):gsub("|A[^|]*|a", "")
	return s
end

-- The text as the window shows it: links in green (items) or yellow (quests), the rest escaped.
function C.ShownText(text)
	local s = tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:|]*:", ""):gsub("|r", "")
	local links = {}
	s = s:gsub("|H([%a]+):[^|]*|h(.-)|h", function(kind, name)
		links[#links + 1] = (kind == "quest" and "|cffffd100" or "|cff1eff00") .. ns.Escape(name) .. "|r"
		return "\1" .. #links .. "\2"
	end)
	s = ns.Escape(s):gsub("\1(%d+)\2", function(n) return links[tonumber(n)] or "" end)
	return s
end

-- What the window's box sends: the first linked item or quest goes as the focus part (about=), so
-- the AI gets its stats or its text; otherwise the card's thread (Ask more) when there is one.
-- The quest in the log a question names, by its title (a leading "The" optional, any case), the
-- longest match; titles under 5 letters are too easily found by chance. nil when none.
function C.QuestNamed(text)
	local QL = C_QuestLog
	if type(QL) ~= "table" then return nil end
	local low = " " .. tostring(text or ""):lower():gsub("[^%w' ]", " "):gsub("%s+", " ") .. " "
	local best, bestLen
	for i = 1, tonumber((ns.Try(QL.GetNumQuestLogEntries))) or 0 do
		local info = ns.Try(QL.GetInfo, i)
		if type(info) == "table" and not info.isHeader and type(info.title) == "string" and (info.questID or 0) > 0 then
			local t = info.title:lower():gsub("[^%w' ]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""):gsub("^the ", "")
			if #t >= 5 and low:find(" " .. t .. " ", 1, true) and (not bestLen or #t > bestLen) then best, bestLen = info.questID, #t end
		end
	end
	return best
end

-- A quest named in plain words ("how do I turn in the defias brotherhood") goes with its details, as a
-- shift-clicked one does (seen in game: without its text the AI sent the player back to the giver of a
-- "talk to Wiley in Lakeshire" quest). Sets the focus and opts.about; returns opts.
function C.NamedFocus(text, opts)
	if opts.about or not (ns.State and ns.State.Sharing() and ns.Quests) then return opts end
	local id = C.QuestNamed(text)
	local focus = id and ns.Quests.Focus(id)
	if focus then
		ns.State.SetFocus(focus)
		opts.about = "quest:" .. id
	end
	return opts
end

function C.SendTyped(text)
	local opts = { about = R.ask and R.ask.about or nil, shown = C.ShownText(text) }
	local sharing = ns.State and ns.State.Sharing()
	-- The whole link (its colour too): the game's tooltip data is read from the hyperlink as shown.
	local item = text:match("(|c[^|]-|Hitem:[^|]*|h.-|h|r)") or text:match("(|Hitem:[^|]*|h.-|h)")
	local quest = tonumber(text:match("|Hquest:(%d+)"))
	if sharing and item and ns.Tooltip then
		local focus = ns.Tooltip.Focus(item)
		if focus then
			ns.State.SetFocus(focus)
			opts.about = "item:" .. tonumber(item:match("item:(%d+)"))
		end
	elseif sharing and quest and ns.Quests then
		local focus = ns.Quests.Focus(quest)
		if focus then
			ns.State.SetFocus(focus)
			opts.about = "quest:" .. quest
		end
	else
		C.NamedFocus(text, opts)
	end
	return C.Send(C.PlainText(text), opts)
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

-- A question still waiting in this chat (the window's "Thinking…" bubble).
function C.WaitingIn(chatId)
	for _, p in ipairs(Pending()) do
		if p.chat == nil or p.chat == chatId then return p end
	end
	return nil
end

-- Stop the question waiting in this chat (the review: a wrong one, or one waiting on a closed app,
-- couldn't be stopped). Not taken by the app yet: dropped here, nothing sent. Taken: a stop record,
-- which the app answers with "Stopped." (its aborted record ends the wait as an answer does).
-- → "dropped", "asked" or nil (nothing waiting).
function C.Stop()
	local db = ns.db
	if not db then return nil end
	local p = C.WaitingIn(db.chat)
	if not p then return nil end
	if ns.Link.Drop(p.key) then
		for i, x in ipairs(Pending()) do if x == p then table.remove(Pending(), i); break end end
		AddMsg("sys", "|cff888888Stopped before it was sent.|r")
		C.Refresh()
		return "dropped"
	end
	if not p.stopping then
		p.stopping = true
		ns.Link.NewKeyed("stop", db.chat, {}, "")
	end
	C.Refresh()
	return "asked"
end

-- The key of the same question (text and about) still waiting for its answer in the current chat,
-- or nil. A button pressed again while its question waits (the app not running, seen in game: one
-- Ask a click, each answered later) reuses it instead of queueing a copy.
function C.PendingKey(text, about)
	text = ns.Trim(tostring(text or ""))
	for _, p in ipairs(Pending()) do
		if p.text == text and p.about == about and p.chat == (ns.db and ns.db.chat) then
			p.card = true
			return p.key
		end
	end
	return nil
end

-- Ask Spellmind. Returns the record's key, or nil, a reason and (for a key-shaped text) "key".
-- opts (Marks.lua): about = what was clicked ("quest:1338"; the app gives the turn its focus part),
-- shown = the window's line instead of the text, card = the answer also goes to the answer card.
function C.Send(text, opts)
	opts = opts or {}
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
	-- Back after a long break: this question starts a new chat (the last one stays in Chats).
	local current = Entry(db.chat)
	if #current.msgs > 0 and time() - (tonumber(current.at) or 0) > C.NEW_AFTER then
		C.NewChat()
		AddMsg("sys", "|cff888888A new chat, after a break. The last one is in Chats.|r")
	end
	local args = { { "cur", db.cursor }, { "agent", ns.DEFAULT_AGENT }, { "ctx", 0 } }
	-- The character's state built first, so the message and its parts come out in one draw; st
	-- names the parts the app hasn't confirmed ("" when it has them all, none: no game data).
	local st = ns.State and ns.State.BeforeSend()
	if st then args[#args + 1] = { "st", st } end
	local about = type(opts.about) == "string" and opts.about:match("^%l+:%d+$") and opts.about or nil
	if about then args[#args + 1] = { "about", about } end
	-- The header's picks (Window.lua): sent only when the app offers them; otherwise its defaults.
	local effort = ns.Window and ns.Window.Effort()
	if effort then args[#args + 1] = { "effort", effort } end
	local search = ns.Window and ns.Window.Search()
	if search ~= nil then args[#args + 1] = { "search", search and 1 or 0 } end
	-- The double-check off (Settings): the app checks fact answers unless told not to.
	if ns.db.ui and ns.db.ui.check == false then args[#args + 1] = { "check", 0 } end
	-- A caller's own (Guide.lua's guide=1): short words and numbers only.
	for _, a in ipairs(type(opts.args) == "table" and opts.args or {}) do
		if type(a[1]) == "string" and a[1]:match("^%l+$") and tostring(a[2]):match("^[%w]+$") then args[#args + 1] = { a[1], a[2] } end
	end
	local key = ns.Link.NewKeyed("msg", db.chat, args, ns.CleanField(text))
	if not key then return nil, "Not ready yet: try again in a moment." end
	table.insert(Pending(), { key = key, t = time(), card = opts.card and true or nil, chat = db.chat, text = text, about = about })
	-- opts.shown is escaped already (a card's label, or the box's text with its links coloured).
	local shown = opts.shown or ns.Escape(text)
	AddText(YOU, shown)
	AddMsg("you", shown)
	if ns.Link.AppGone() and not R.toldStart then
		R.toldStart = true
		C.System(C.NOT_HEARD)
	end
	ns.Link.AfterSend()
	C.Refresh()
	return key
end

function C.OnAcked(key, o)
	for _, p in ipairs(Pending()) do
		if p.key == key and not p.acked then p.acked, p.ackedAt = true, time() end
	end
end

-- A question the app took but never answered (the review: "Thinking…" forever, and the link polling
-- four times a second for good): after EXPIRE seconds it's dropped, with a line saying so, in the
-- window and in its card. One the app hasn't taken yet waits: the app may still start.
C.EXPIRE = 300
C.NO_ANSWER = "No answer came for that question. Ask it again."
function C.ExpirePending()
	local list, keep, now = Pending(), {}, time()
	for _, p in ipairs(list) do
		if p.ackedAt and now - p.ackedAt > C.EXPIRE then
			AddMsg("err", "|cffff6060" .. C.NO_ANSWER .. "|r", nil, p.chat)
			if p.card and ns.Marks and ns.Marks.OnAnswer then pcall(ns.Marks.OnAnswer, p.key, { t = "error", text = C.NO_ANSWER }) end
		else
			keep[#keep + 1] = p
		end
	end
	if #keep ~= #list then
		R.pending = keep
		C.Refresh()
	end
end

---------------------------------------------------------------------------
-- Answers
---------------------------------------------------------------------------

-- Answers in the game's chat frame (the Settings tab, SpellmindDB.ui.chatLines): "all" (a short
-- answer whole, a long one's summary), "first" (the summary or first line only) or "off".
C.CHAT_LINES = { "all", "first", "off" }
function C.ChatLines()
	local v = ns.db and type(ns.db.ui) == "table" and ns.db.ui.chatLines
	if v == "first" or v == "off" then return v end
	return "all"
end

function C.SetChatLines(v)
	if not ns.db then return end
	if type(ns.db.ui) ~= "table" then ns.db.ui = {} end
	ns.db.ui.chatLines = (v == "first" or v == "off") and v or nil
end

-- A reply, error or aborted record for our chat (Link.ApplyRecords). replay = 1: it was
-- applied before a client crash rolled the cursor back, so it's shown without the chat frame.
function C.OnRecord(r, replay)
	local kind = r.t
	-- The oldest send of that chat waits for this answer (each chat's answers come in order).
	local p
	if not replay then
		for i, x in ipairs(Pending()) do
			if x.chat == nil or x.chat == r.chat then p = table.remove(Pending(), i); break end
		end
	end
	local chatId = C.Known(r.chat) and r.chat or ns.db.chat
	-- An Explain's answer goes to its card too; shown there, it skips the chat frame.
	local carded = p and p.card and ns.Marks and ns.Marks.OnAnswer(p.key, r) or false
	if carded then replay = true end
	local text
	if kind == "reply" then
		-- An imported guide (docs/milestone-15.md): its plan saved for this character.
		if type(r.plan) == "table" and ns.Guide then pcall(ns.Guide.OnPlan, r.plan) end
		text = ns.SafeText(r.text)
		local more = math.max(0, math.floor(tonumber(r.more) or 0))
		local whole = text .. (more > 0 and " |cff888888(cut short: ask for the rest)|r" or "")
		AddText(WHO, whole)
		-- The reply's suggestion chips (the app's, from its "Next:" line): one click asks.
		local chips = {}
		for _, c in ipairs(type(r.chips) == "table" and r.chips or {}) do
			if type(c) == "string" and c ~= "" and #chips < 3 then chips[#chips + 1] = ns.SafeText(ns.Utf8Cut(c, 60)) end
		end
		-- Its map pins (the app's, from its "Pin:" lines): a click sets the game's pin, nothing else does.
		local pins = {}
		for _, p in ipairs(type(r.pins) == "table" and r.pins or {}) do
			local x, y = tonumber(type(p) == "table" and p.x), tonumber(type(p) == "table" and p.y)
			if x and y and x >= 0 and x <= 100 and y >= 0 and y <= 100 and type(p.n) == "string" and type(p.z) == "string" and #pins < 3 then
				pins[#pins + 1] = { n = ns.SafeText(ns.Utf8Cut(p.n, 40)), z = ns.Utf8Cut(p.z, 40), x = x, y = y }
			end
		end
		AddMsg("sm", whole, #chips > 0 and chips or nil, chatId, #pins > 0 and pins or nil)
		if not replay then
			-- A short reply goes to the chat frame whole, line by line: its first line alone can be
			-- "…across three talents:" with the list below it (a player's, 2026-11-10). A longer one
			-- shows its summary and says the rest is in the window.
			local lines = {}
			for line in tostring(text):gmatch("[^\n]+") do
				if line:match("%S") then lines[#lines + 1] = line end
			end
			local mode = C.ChatLines()
			if mode == "off" then
				-- Nothing in the chat frame (the Settings tab): the answer is in the Spellmind window.
			elseif mode == "all" and #lines > 0 and #lines <= CHAT_LINES_MAX and #text <= CHAT_BYTES_MAX then
				for i, line in ipairs(lines) do ChatFrame((i == 1 and "Spellmind: " or "   ") .. line) end
			else
				local summary = type(r.summary) == "string" and r.summary ~= "" and ns.SafeText(r.summary) or nil
				ChatFrame("Spellmind: " .. (summary or Short(r.text)) .. " |cff888888(more: /sm)|r")
			end
		end
	elseif kind == "error" then
		text = ns.SafeText(r.text)
		AddText(ERR, text)
		AddMsg("err", "|cffff6060" .. text .. "|r", nil, chatId)
		if not replay and C.ChatLines() ~= "off" then ChatFrame("Spellmind: " .. Short(r.text)) end
	else
		text = ns.SafeText(type(r.text) == "string" and r.text ~= "" and r.text or "Stopped.")
		AddText(WHO, text)
		AddMsg("sm", text, nil, chatId)
		if not replay and C.ChatLines() ~= "off" then ChatFrame("Spellmind: " .. Short(text)) end
	end
	C.Refresh()
end

---------------------------------------------------------------------------
-- Slash commands and start
---------------------------------------------------------------------------

SLASH_SPELLMIND1 = "/spellmind"
SLASH_SPELLMIND2 = "/sm"

-- /sm help's lines, and the words that open a tab.
C.HELP = {
	"Spellmind commands:",
	"  /sm: open or close the chat.  /sm <question>: ask.",
	"  /sm quests, dungeons, gear, talents, spells, professions, gold, nudges, settings: open that tab.",
	"  /sm route: the quest route on or off (the Route tab has its switches).  /sm arrow: its arrow.",
	"  /sm guide <link>: your leveling guide, read by your AI.",
	"  /sm nudges on/off/reset · /sm marks on/off · /sm data, or data on/off · /sm minimap on/off.",
	"  /sm app: where to get the free Spellmind app (the chat needs it; every other tab works without).  /sm welcome: the first-time welcome again.  /sm news: what's new in this version.",
}
C.TAB_WORDS = { chat = "chat", quests = "quests", quest = "quests", dungeons = "dungeons", dungeon = "dungeons", gear = "gear",
	talents = "talents", spells = "spells", professions = "professions", profs = "professions", gold = "gold", settings = "settings" }
SlashCmdList.SPELLMIND = function(msg)
	msg = ns.Trim(msg)
	if msg == "" then
		C.Toggle(true)
		return
	end
	-- /sm probe: the API probe (Probe.lua), saved for the next /reload. Never sent anywhere.
	if msg:lower() == "probe" and ns.Probe then
		local n = ns.Probe()
		ChatFrame(("Spellmind: probed %d client functions. Type /reload to save the results."):format(n))
		return
	end
	local lower = msg:lower()
	-- /sm marks off and /sm marks on: the Spellmind marks on the game's windows and the tooltip line.
	local marks = lower:match("^marks%s+(%a+)$")
	if (marks == "off" or marks == "on") and ns.db then
		ns.db.marks = type(ns.db.marks) == "table" and ns.db.marks or {}
		ns.db.marks.all = marks == "on"
		if ns.Quests and ns.Quests.mark then
			if marks == "off" then ns.Quests.mark:Hide() end
		elseif marks == "on" and ns.Quests then
			ns.Quests.Hook()
		end
		ChatFrame(marks == "off" and "Spellmind: the marks on the game's windows and the tooltip line are off. Type /sm marks on to show them again."
			or "Spellmind: the marks on the game's windows and the tooltip line are on.")
		return
	end
	-- /sm nudges off and /sm nudges on: the toasts by the minimap.
	local nd = lower:match("^nudges%s+(%a+)$")
	if (nd == "off" or nd == "on") and ns.db and ns.Nudges then
		ns.Nudges.SetOn(nd == "on")
		ChatFrame(nd == "off" and "Spellmind: nudges are off. Type /sm nudges on to have them again." or "Spellmind: nudges are on.")
		return
	end
	-- /sm nudges demo: a sample toast.
	if nd == "demo" and ns.db and ns.Nudges then
		ns.Nudges.Demo()
		return
	end
	-- /sm nudges reset: the dismissed ones forgotten, so whatever applies now shows again.
	if nd == "reset" and ns.db and ns.Nudges then
		local n = ns.Nudges.Reset()
		ChatFrame(n > 0 and ("Spellmind: " .. n .. " nudge" .. (n > 1 and "s" or "") .. " to show.")
			or "Spellmind: nothing to nudge about right now (no spells due, points to spend, broken gear, full bags or capped professions).")
		return
	end
	-- /sm route: the route tracker (Route.lua), opened or closed.
	if lower == "route" and ns.Route and ns.db then
		ns.Route.Toggle()
		return
	end
	-- /sm arrow: the route's arrow (Route.lua), shown (with the tracker) or hidden.
	if lower == "arrow" and ns.Route and ns.db then
		ns.Route.ToggleArrow()
		return
	end
	-- /sm news: what's new in this version (Welcome.lua).
	if lower == "news" and ns.Welcome and ns.db then
		ns.Welcome.ShowNews()
		return
	end
	-- /sm welcome: the first-time welcome again (Welcome.lua).
	if lower == "welcome" and ns.Welcome and ns.db then
		ns.Welcome.Show()
		return
	end
	-- /sm app: the Get the app box, with the project's link to copy.
	if (lower == "app" or lower == "download") and ns.Marks and ns.Marks.GetApp then
		ns.Marks.GetApp()
		return
	end
	-- /sm help (or ?): the commands, never a question to the AI (the review: it was sent as one).
	if lower == "help" or lower == "?" then
		for _, line in ipairs(C.HELP) do ChatFrame(line) end
		return
	end
	-- /sm quests, /sm gear …: that tab of the Spellmind window. Bare /sm nudges and /sm marks say how.
	if lower == "nudges" or lower == "marks" then
		ChatFrame(lower == "nudges" and "Spellmind: /sm nudges on, off, reset or demo. The Nudges tab lists what's waiting." or "Spellmind: /sm marks on or off. Each mark has its own switch in Settings.")
		if lower == "nudges" and ns.Panel and ns.db then ns.Panel.Show("nudges") end
		return
	end
	if C.TAB_WORDS[lower] and ns.Panel and ns.db then
		ns.Panel.Show(C.TAB_WORDS[lower])
		return
	end
	-- /sm panel: the last tab other than Chat.
	if lower == "panel" and ns.Panel and ns.db then
		ns.Panel.Toggle()
		return
	end
	-- /sm guide <link>: your guide's link, read now by your AI; /sm guide alone: the link box.
	local guideArg = (lower == "guide" and "") or msg:match("^[Gg][Uu][Ii][Dd][Ee]%s+(.+)$")
	if guideArg and ns.Guide and ns.db then
		if guideArg == "" then
			ns.Guide.AskLink(ns.Panel and ns.Panel.Get())
		elseif ns.Guide.SetUrl(guideArg) then
			ns.Guide.Import()
		else
			ChatFrame("Spellmind: that isn't an https:// link. Paste your guide's link after /sm guide.")
		end
		return
	end
	-- /sm settings: the Settings tab.
	if lower == "settings" and ns.Panel and ns.db then
		ns.Panel.Show("settings")
		return
	end
	-- /sm minimap off and /sm minimap on: the minimap button.
	local mm = lower:match("^minimap%s+(%a+)$")
	if (mm == "off" or mm == "on") and ns.db and ns.MinimapButton then
		ns.MinimapButton.Show(mm == "on")
		ChatFrame(mm == "off" and "Spellmind: the minimap button is hidden. Type /sm minimap on to show it again." or "Spellmind: the minimap button is back.")
		return
	end
	-- /sm data: what the app gets of the character; /sm data off and /sm data on.
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
	-- A quest named in the words goes with its details, as from the chat box.
	C.Send(msg, C.NamedFocus(msg, {}))
end

ns.On("ADDON_LOADED", function(_, name)
	if name == ns.ADDON then ns.InitDB() end
end)

ns.On("PLAYER_LOGIN", function()
	if not ns.db then ns.InitDB() end
	C.InitChats()
	ns.Link.Start()
	-- Messages drawn again after a /reload still wait for their answers.
	local keys = {}
	for key, o in pairs(R.out) do
		if o.type == "msg" then keys[#keys + 1] = { key = key, n = o.n } end
	end
	table.sort(keys, function(a, b) return a.n < b.n end)
	for _, k in ipairs(keys) do table.insert(Pending(), { key = k.key, t = time(), chat = R.out[k.key].chat }) end
	-- Questions the app took and never answered expire (C.ExpirePending), checked twice a minute.
	if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(30, function() pcall(C.ExpirePending) end) end
	C.Refresh()
end)
