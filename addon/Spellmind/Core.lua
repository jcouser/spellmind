-- Spellmind: adapted from NeverQuestAlone's addon/NeverQuestAlone/Store.lua (MIT; see NOTICE.md).
-- Core.lua: the names, constants, small helpers and saved data the link and the chat share.
--
-- Every file of the addon shares one private table, `ns` (the second value of `...`).
-- Nothing of it is global except SpellmindDB (saved data) and SpellmindCodec (Codec.lua).
--
-- Saved data (SpellmindDB):
--   token        install token: 8 lowercase hex (NeverQuestAlone docs/PROTOCOL.md §2.2)
--   sendCounter  n of the newest keyed record; only ever increases (§2.3)
--   cursor       seq of the last applied record (§4.3)
--   reported     the highest cursor the app is known to have (cur / seen)
--   outbox       { { key = "<nonce>_<n>", hex = "<the whole v2 record>" }, ... }: keyed records
--                not acked yet, drawn again verbatim after /reload (§2.3)
--   nonces       the last few session nonces, so a new one never repeats them
--   chat         the one chat's id: c + 6 lowercase hex
--   lines        the window's last lines, so a /reload doesn't empty it
--   stateSeq     seq of the newest state build; only ever increases (State.lua)
--   chars        per character (a hash of its GUID): sid and the parts last sent (State.lua)
--   share        { state = true, identity = false }: what game data goes to the app

local ADDON_NAME, ns = ...

ns.ADDON = ADDON_NAME or "Spellmind"
ns.VERSION = "0.4.1"
-- Where the free Spellmind app is (the "Get the app" box, Marks.lua): the project's page, not a file.
ns.APP_URL = "https://github.com/jcouser/spellmind"
ns.PROTOCOL = 2
ns.SLOT_COUNT = 200
ns.SLOT_PREFIX = "Spellmind_S"
ns.SLOT_GLOBAL = "SpellmindSlotData"
ns.INBOX_GLOBAL = "SpellmindInbox"
ns.SIG = "Interface\\AddOns\\Spellmind\\sig\\"
ns.MAX_TEXT = 2900 -- bytes of one message (NeverQuestAlone SE-1)
ns.MAX_PAYLOAD = 3200 -- bytes of one strip frame's payload (§2.1)
ns.DEFAULT_AGENT = "main"
ns.RESERVED = "[Spellmind" -- typed text never starts with it (the app's own lines do)
ns.MAX_LINES = 100 -- window lines kept in saved data
ns.RS, ns.US, ns.GS = "\30", "\31", "\29"

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

function ns.Trim(s)
	return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- A whole number as text, the same on Lua 5.1 (the game) and 5.3 (the test VM):
-- tostring(41.0) is "41.0" on 5.3.
function ns.Int(n)
	return string.format("%d", math.floor(tonumber(n) or 0))
end

function ns.ToHex(s)
	return (tostring(s or ""):gsub(".", function(c)
		return string.format("%02x", c:byte())
	end))
end

-- nil for anything that isn't an even-length run of hex digits.
function ns.FromHex(h)
	if type(h) ~= "string" or #h % 2 ~= 0 or h:find("[^%x]") then return nil end
	return (h:gsub("%x%x", function(pair)
		return string.char(tonumber(pair, 16))
	end))
end

-- Args values are percent-encoded: %, ;, = and bytes below 0x20 or 0x7F (§2.2), with
-- uppercase hex, exactly as core/link/records.mjs encodeArg.
function ns.EncodeArg(v)
	return (tostring(v or ""):gsub(".", function(c)
		local b = c:byte()
		if b < 32 or b == 127 or c == "%" or c == ";" or c == "=" then
			return string.format("%%%02X", b)
		end
	end))
end

function ns.DecodeArg(v)
	return (tostring(v or ""):gsub("%%(%x%x)", function(h)
		return string.char(tonumber(h, 16))
	end))
end

-- User text never carries the record separators: GS, RS and US become spaces (§2.2).
function ns.CleanField(s)
	return (tostring(s or ""):gsub("[\29\30\31]", " "))
end

-- Text we didn't get from the app (what the player typed) is shown with every | doubled,
-- so it reads literally and can never form a game escape.
function ns.Escape(s)
	return (tostring(s or ""):gsub("|", "||"))
end

-- The app's text arrives escaped: every | doubled, and the only escapes left are its own
-- colour codes (|cAARRGGBB ... |r). It is shown as is. Anything else that starts with a
-- single | (a link, a texture) is doubled too, so text that didn't come through the app's
-- renderer can't form a live escape either. For conforming text this changes nothing.
function ns.SafeText(s)
	s = tostring(s or "")
	if not s:find("|", 1, true) then return s end
	local out, i, n = {}, 1, #s
	while i <= n do
		local j = s:find("|", i, true)
		if not j then
			out[#out + 1] = s:sub(i)
			break
		end
		out[#out + 1] = s:sub(i, j - 1)
		local nxt = s:sub(j + 1, j + 1)
		if nxt == "|" then
			out[#out + 1] = "||"
			i = j + 2
		elseif nxt == "r" then
			out[#out + 1] = "|r"
			i = j + 2
		elseif nxt == "c" and s:sub(j + 2, j + 9):match("^%x%x%x%x%x%x%x%x$") then
			out[#out + 1] = s:sub(j, j + 9)
			i = j + 10
		else
			out[#out + 1] = "||"
			i = j + 1
		end
	end
	return table.concat(out)
end

-- At most max bytes, never cutting a UTF-8 character in two.
function ns.Utf8Cut(s, max)
	s = tostring(s or "")
	if #s <= max then return s end
	local cut = max
	while cut > 0 and s:byte(cut + 1) and s:byte(cut + 1) >= 128 and s:byte(cut + 1) < 192 do cut = cut - 1 end
	return s:sub(1, cut)
end

-- Quest text with the character's name blanked out (the privacy review, 2026-11-12): the game writes
-- the name into quest text ("Greetings, <name>"), and that text goes to the AI with Break it down. The
-- name is read here only to find it, at the moment of use: it's never kept in a variable past this
-- call, never stored, never sent. Nothing else in Spellmind reads it.
ns.NAME_MARK = "[you]"
function ns.Redact(text)
	if type(text) ~= "string" or text == "" then return text end
	local ok, name = pcall(UnitName, "player")
	if not ok or type(name) ~= "string" or #name < 2 then return text end
	local pattern = name:gsub("(%W)", "%%%1")
	return (text:gsub(pattern, ns.NAME_MARK))
end

function ns.Try(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c, d = pcall(fn, ...)
	if ok then return a, b, c, d end
	return nil
end

---------------------------------------------------------------------------
-- Ids
---------------------------------------------------------------------------

function ns.NewToken()
	return string.format("%04x%04x", math.random(0, 0xFFFF), math.random(0, 0xFFFF))
end

-- A fresh nonce for this UI session (§2.3): 4 lowercase hex, never one of the last few
-- sessions' (their keys may still be in the app's dedupe window).
function ns.NewNonce()
	local recent = {}
	for _, n in ipairs(ns.db and ns.db.nonces or {}) do recent[n] = true end
	local nonce
	for _ = 1, 50 do
		nonce = string.format("%04x", math.random(0, 0xFFFF))
		if not recent[nonce] then break end
	end
	return nonce
end

function ns.NewChatId()
	return string.format("c%06x", math.random(0, 0xFFFFFF))
end

---------------------------------------------------------------------------
-- Events: one frame, handlers per event (registered by the other files)
---------------------------------------------------------------------------

local handlers = {}
local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event, ...)
	for _, fn in ipairs(handlers[event] or {}) do fn(event, ...) end
end)

function ns.On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		-- Events this client doesn't know would error; skip them quietly.
		pcall(eventFrame.RegisterEvent, eventFrame, event)
	end
	table.insert(handlers[event], fn)
end

-- Runtime state (per UI session; a /reload starts over).
ns.R = {}

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------

local function Count(n)
	n = tonumber(n)
	if not n or n ~= n or n < 0 then return 0 end
	return math.floor(n)
end

function ns.InitDB()
	if type(SpellmindDB) ~= "table" then SpellmindDB = {} end
	local db = SpellmindDB
	ns.db = db
	db.schema = 1
	if type(db.token) ~= "string" or not db.token:match("^[0-9a-f]+$") or #db.token ~= 8 then
		db.token = ns.NewToken()
	end
	db.sendCounter = Count(db.sendCounter)
	db.cursor = Count(db.cursor)
	db.reported = Count(db.reported)
	if db.reported > db.cursor then db.reported = db.cursor end

	-- Outbox entries are { key, hex }; anything else can't be sent verbatim.
	local outbox = {}
	for _, e in ipairs(type(db.outbox) == "table" and db.outbox or {}) do
		if type(e) == "table" and type(e.key) == "string" and ns.FromHex(e.hex) then
			outbox[#outbox + 1] = { key = e.key, hex = e.hex }
		end
	end
	db.outbox = outbox

	local nonces = {}
	for _, n in ipairs(type(db.nonces) == "table" and db.nonces or {}) do
		if type(n) == "string" and n:match("^%x%x%x%x$") then nonces[#nonces + 1] = n end
	end
	db.nonces = nonces

	if type(db.chat) ~= "string" or not db.chat:match("^c[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]$") then
		db.chat = ns.NewChatId()
	end

	local lines = {}
	for _, l in ipairs(type(db.lines) == "table" and db.lines or {}) do
		if type(l) == "string" then lines[#lines + 1] = l end
	end
	while #lines > ns.MAX_LINES do table.remove(lines, 1) end
	db.lines = lines

	-- The character's state (State.lua): one seq per install, an entry per character (keyed by a
	-- hash of its GUID, never its name), and what is shared (identity: name, realm and guild,
	-- off unless the player turns it on; nothing reads them yet).
	db.stateSeq = Count(db.stateSeq)
	local chars = {}
	for k, c in pairs(type(db.chars) == "table" and db.chars or {}) do
		if type(k) == "string" and type(c) == "table" then chars[k] = c end
	end
	db.chars = chars
	local share = type(db.share) == "table" and db.share or {}
	local parts = {}
	for k, v in pairs(type(share.parts) == "table" and share.parts or {}) do
		if type(k) == "string" and v == false then parts[k] = false end
	end
	db.share = { state = share.state ~= false, identity = share.identity == true, parts = parts }
	return db
end
