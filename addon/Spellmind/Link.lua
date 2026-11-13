-- Spellmind: adapted from NeverQuestAlone's addon/NeverQuestAlone/Transport.lua (MIT; see NOTICE.md).
-- Link.lua: the addon's two doors to the Spellmind app (NeverQuestAlone's docs/PROTOCOL.md,
-- protocol v2, with Spellmind's names: docs/milestone-2.md, "Coexistence").
--
--   Out: records (§2.2) drawn as a pixel strip (§2.1), newest first within 3,200 bytes. Keyed
--        records stay in SpellmindDB.outbox until the app acks them and are drawn again
--        verbatim after /reload. After them, the character's state parts the app hasn't
--        confirmed (State.lua, docs/milestone-4.md); one that doesn't fit waits, the rest go.
--   In: doorbells (§3): files that exist at every UI load, which the app rings by deleting
--        them for a moment: push (read a slot) and alive (its beat), plus the self-test; slot
--        addons Spellmind_S001..S200 loaded under the rules of §4.2; records applied with the
--        seq cursor (§4.3); and SpellmindInbox (Spellmind/Inbox.lua) at every login.
--
-- The strip sits 272 physical pixels below the screen's top-left corner, under
-- NeverQuestAlone's (which is at the corner), so both addons can draw at once.
-- Nothing here calls ReloadUI.

local _, ns = ...
local L = {}
ns.Link = L
local R = ns.R
local Codec = SpellmindCodec

-- 3 px cells (NeverQuestAlone draws 4): 44% less of the screen; the reader takes pitches from 2.5 px
-- (core/link/strip.mjs minPitch). One unit is one physical pixel, so the cells stay crisp.
local CELL, CELLS_PER_ROW, MAX_ROWS = 3, 200, 48
-- Where the strip sits, in strip units (physical pixels) from UIParent's top-left: the very corner,
-- the least intrusive spot (a player found it floating a third down the screen, 2026-11-11), unless
-- NeverQuestAlone is loaded, whose own strip has that corner; then 272 px down, below it. The
-- readers search the first 600 rows at the left edge, so either is found.
local STRIP_X = 0
L.STRIP_Y_ALONE, L.STRIP_Y_BESIDE_NQA = 0, 272
function L.StripY()
	local AO = rawget(_G, "C_AddOns")
	local loaded = AO and type(AO.IsAddOnLoaded) == "function" and ns.Try(AO.IsAddOnLoaded, "NeverQuestAlone")
	return loaded and L.STRIP_Y_BESIDE_NQA or L.STRIP_Y_ALONE
end
local FAST_TICK = 0.25 -- poll while a strip is up or a reply is awaited
local SLOW_EVERY = 8 -- ticks: the 2-second ticker
local SELFTEST_EVERY = 60
local HELLO_DELAY = 3 -- after login (zone and map are ready by then)
local HELLO_DWELL = 20 -- seconds an unconfirmed hello stays on the strip by itself
local HELLO_RETRY = 60
local LIVE_WAIT = 30 -- no push ring by then: one slot load settles the live self-test
local SLOTONLY_HELLO_WAIT = 8 -- slot-only mode: the hello's answer is read after this
local SEEN_DWELL = 5
local SEEN_RECORDS, SEEN_BYTES, SEEN_AFTER = 10, 16384, 30 -- §2.4
local SLOTONLY_SCHEDULE = { 5, 12, 25, 45 } -- §4.2 rule 4
local IDLE_CHECK = 600 -- §4.2 rule 5
local RED_AFTER = 120 -- no word from the app for 2 min: it isn't running
local BELL_DEAD = 10 -- a bell missing this long isn't pulsing (pulses last 3 s at most, §3)
local PUSH_GAP = 1.5 -- a push ring loads a slot, at most one per 1.5 s (§4.2 rule 1)
local BUSY_EVERY, BUSY_SLOW, BUSY_SLOW_AFTER, BUSY_MAX = 30, 60, 300, 20 -- slot-only: rule 4's tail
local BELLS = { "push_a", "push_b", "alive_a", "alive_b" }
-- The app's beat pulses an alive bell for 2.5 s, so the 2-second tick always reads one.
local SLOW_BELLS = { alive_a = true, alive_b = true }
-- The strip's self-heal (L.Heal), in visible seconds: a frame that waits this long for its
-- answer is drawn again in full, once; and while anything drawn waits, a full draw this often.
L.HEAL_ACK, L.HEAL_EVERY = 12, 30
L.TYPED_MAX = 20 -- typed messages that may wait for their ack at once

---------------------------------------------------------------------------
-- Runtime state
---------------------------------------------------------------------------

function L.Reset()
	for k in pairs(R) do R[k] = nil end
	R.out, R.sentAt, R.sched, R.follow, R.warned, R.bells = {}, {}, {}, {}, {}, {}
	R.frame, R.ticks, R.absentCount, R.applyBytes, R.orphans, R.skipped = 0, 0, 0, 0, 0, 0
	R.sig = { checks = 0, hits = 0, live = "pending" }
	R.push = { rings = 0 }
	R.slots = { nextIndex = 1, free = ns.SLOT_COUNT, loads = 0, reasons = {} }
	R.heal = { drawn = 0, full = 0, ack = 0, timer = 0 }
	R.loginAt = GetTime()
end

---------------------------------------------------------------------------
-- Sounds and addons
---------------------------------------------------------------------------

local function SigPath(name)
	return ns.SIG .. "ctl\\" .. name .. ".wav"
end

-- PlaySoundFile returns true (and a handle, stopped at once) for a file that existed when the
-- UI loaded and still exists, and false for a missing one; files made after the load read as
-- missing until the next /reload (§3).
local function Probe(path)
	local S = R.sig
	if type(PlaySoundFile) ~= "function" then return false end
	S.checks = S.checks + 1
	local ok, willPlay, handle = pcall(PlaySoundFile, path, "Master")
	if not ok then
		S.error = tostring(willPlay)
		return false
	end
	if handle and type(StopSound) == "function" then pcall(StopSound, handle) end
	if willPlay then S.hits = S.hits + 1 end
	return willPlay and true or false
end

local bellPaths = {}
local function BellPath(name)
	local path = bellPaths[name]
	if not path then
		path = SigPath(name == "present" and "present" or ("bell_" .. name))
		bellPaths[name] = path
	end
	return path
end

local function LoadFn(name)
	if type(C_AddOns) == "table" and type(C_AddOns.LoadAddOn) == "function" then return C_AddOns.LoadAddOn(name) end
	if type(LoadAddOn) == "function" then return LoadAddOn(name) end
	return false, "NO_API"
end

local function IsLoaded(name)
	if type(C_AddOns) == "table" and type(C_AddOns.IsAddOnLoaded) == "function" then return C_AddOns.IsAddOnLoaded(name) end
	if type(IsAddOnLoaded) == "function" then return IsAddOnLoaded(name) end
	return false
end

L.Probe = Probe

-- The self-test passed (§3). Otherwise the addon is in slot-only mode and no doorbell is
-- trusted: if missing files "played", every ring would.
function L.SignalsOK()
	return R.sig.static == "ok" and R.sig.live ~= "fail"
end

function L.SlotOnly()
	return not L.SignalsOK()
end

function L.SlotsIn()
	return not R.slots.broken and not R.slots.out
end

-- Said once a session, in the window and the chat frame.
function L.Warn(id, text)
	if R.warned[id] then return end
	R.warned[id] = true
	ns.Chat.System(text)
end

---------------------------------------------------------------------------
-- Records (§2.2)
---------------------------------------------------------------------------

-- 2 US token US key US type US chat US args US body. args is a list of { name, value }
-- pairs, drawn in that order; cur comes first on every record.
function L.Record(key, rtype, chat, args, body)
	local parts = {}
	for _, kv in ipairs(args) do
		local v = kv[2]
		if type(v) == "number" then v = ns.Int(v) end
		parts[#parts + 1] = kv[1] .. "=" .. ns.EncodeArg(v)
	end
	return table.concat({ "2", ns.db.token, key, rtype, chat or "", table.concat(parts, ";"), body or "" }, ns.US)
end

-- The fields of a record this addon drew (the outbox after /reload).
function L.ParseRecord(wire)
	if type(wire) ~= "string" then return nil end
	local f, start = {}, 1
	for i = 1, 6 do
		local j = wire:find(ns.US, start, true)
		if not j then return nil end
		f[i] = wire:sub(start, j - 1)
		start = j + 1
	end
	if f[1] ~= "2" then return nil end
	local args = {}
	for pair in (f[6] .. ";"):gmatch("([^;]*);") do
		local k, v = pair:match("^([^=]+)=(.*)$")
		if k then args[k] = ns.DecodeArg(v) end
	end
	return { token = f[2], key = f[3], type = f[4], chat = f[5], args = args, body = wire:sub(start) }
end

local function KeyN(key)
	return tonumber(tostring(key):match("^%x%x%x%x_(%d+)$"))
end

-- R.out is built from SpellmindDB.outbox, whose hex is the one source of truth.
function L.LoadOutbox()
	local keep = {}
	for _, e in ipairs(ns.db.outbox) do
		local wire = ns.FromHex(e.hex)
		local rec = L.ParseRecord(wire)
		local n = KeyN(e.key)
		-- One without a cursor the app will never ack: it goes, or it would stay on the strip for good.
		if rec and n and rec.key == e.key and tonumber(rec.args.cur) then
			R.out[e.key] = { wire = wire, type = rec.type, chat = rec.chat, cur = tonumber(rec.args.cur) or 0, n = n }
			R.sentAt[e.key] = GetTime()
			keep[#keep + 1] = e
		end
	end
	ns.db.outbox = keep
end

-- A keyed record: the next n, key <nonce>_<n>, into the outbox until acked (§2.3). Every
-- keyed record carries the cursor: a caller that leaves it out gets it first.
function L.NewKeyed(rtype, chatId, args, body)
	local db = ns.db
	if not db or not R.nonce then return nil end
	local hasCur = false
	for _, a in ipairs(args) do if a[1] == "cur" then hasCur = true end end
	if not hasCur then
		local withCur = { { "cur", db.cursor } }
		for _, a in ipairs(args) do withCur[#withCur + 1] = a end
		args = withCur
	end
	db.sendCounter = math.floor(db.sendCounter) + 1
	local n = db.sendCounter
	local key = R.nonce .. "_" .. ns.Int(n)
	local wire = L.Record(key, rtype, chatId, args, body)
	table.insert(db.outbox, { key = key, hex = ns.ToHex(wire) })
	R.out[key] = { wire = wire, type = rtype, chat = chatId, cur = db.cursor, n = n }
	R.sentAt[key] = GetTime()
	L.RefreshStrip()
	return key
end

function L.OutboxDepth()
	local n = 0
	for _ in pairs(R.out) do n = n + 1 end
	return n
end

-- Typed messages waiting for their ack.
function L.TypedWaiting()
	local n = 0
	for _, o in pairs(R.out) do
		if o.type == "msg" then n = n + 1 end
	end
	return n
end

function L.Reported(cur)
	local db = ns.db
	cur = math.floor(tonumber(cur) or 0)
	if cur > db.reported then db.reported = cur end
	if db.reported >= db.cursor then
		R.applyBytes = 0
		R.unreportedSince = nil
	end
end

function L.Acked(key)
	local db = ns.db
	for i, e in ipairs(db.outbox) do
		if e.key == key then
			table.remove(db.outbox, i)
			break
		end
	end
	local o = R.out[key]
	R.out[key], R.sentAt[key] = nil, nil
	if o then
		L.Reported(o.cur)
		ns.Chat.OnAcked(key, o)
	end
	R.lastAckAt = GetTime()
	L.NoteBridge()
	L.RefreshStrip()
end

---------------------------------------------------------------------------
-- The strip (§2.1)
---------------------------------------------------------------------------

local strip
local cellPool = {}
-- The strip as drawn: each cell's value, how many cells are shown, and the table every frame
-- is encoded into. A frame touches only the cells that changed.
local cellVal, cellsShown, frameCells = {}, 0, {}

-- One strip unit is one physical pixel: the strip ignores its parent's scale and takes
-- 768 / the physical screen height (Blizzard's PixelUtil; wow-ai issue #8).
local function StripScale()
	local physH
	if type(GetPhysicalScreenSize) == "function" then
		local ok, _, h = pcall(GetPhysicalScreenSize)
		if ok and type(h) == "number" and h > 0 then physH = h end
	end
	return 768 / (physH or 1080)
end

function L.EnsureStrip()
	if strip then return strip end
	strip = CreateFrame("Frame", "SpellmindStrip", UIParent)
	strip:SetFrameStrata("TOOLTIP")
	strip:SetFrameLevel(10000)
	if strip.SetIgnoreParentScale then strip:SetIgnoreParentScale(true) end
	-- Nor its alpha: a UIParent another addon fades would blend the cells into the world.
	if strip.SetIgnoreParentAlpha then strip:SetIgnoreParentAlpha(true) end
	strip:SetScale(StripScale())
	R.stripY = L.StripY()
	strip:SetPoint("TOPLEFT", UIParent, "TOPLEFT", STRIP_X, -R.stripY)
	strip:SetSize(CELLS_PER_ROW * CELL, MAX_ROWS * CELL)
	strip:Hide()
	return strip
end

-- UI_SCALE_CHANGED and DISPLAY_SIZE_CHANGED.
function L.UpdateStripScale()
	if strip then strip:SetScale(StripScale()) end
end

-- full: every cell coloured and shown again, and the rest of the pool hidden again, whatever
-- the strip is thought to hold (the self-heal).
local function DrawCells(frameId, payload, full)
	local cells = Codec.Encode(frameId % 65536, payload, frameCells)
	local s = L.EnsureStrip()
	local rows = math.ceil(#cells / CELLS_PER_ROW)
	local total = rows * CELLS_PER_ROW
	for i = 1, total do
		local t = cellPool[i]
		if not t then
			t = s:CreateTexture(nil, "OVERLAY")
			t:SetSize(CELL, CELL)
			local c = (i - 1) % CELLS_PER_ROW
			local r = math.floor((i - 1) / CELLS_PER_ROW)
			t:SetPoint("TOPLEFT", s, "TOPLEFT", c * CELL, -r * CELL)
			cellPool[i] = t
		end
		local v = cells[i] or 0
		if full or cellVal[i] ~= v then
			cellVal[i] = v
			local cr, cg, cb = Codec.CellColor(v)
			t:SetColorTexture(cr, cg, cb, 1)
		end
		if full or i > cellsShown then t:Show() end
	end
	for i = total + 1, full and #cellPool or cellsShown do
		cellPool[i]:Hide()
	end
	cellsShown = total
	s:Show()
	local H = R.heal
	H.drawn = 0
	if full then H.full = 0 end
end

function L.HideStrip()
	if strip then strip:Hide() end
	R.stripShown = false
	R.stripPayload = nil
	R.stripWaits = false
end

-- What the strip carries now: unacked keyed records, the hello until the app confirms it,
-- and a seen for a few seconds, newest first. waits: the app answers it (an ack, the hello's).
function L.StripEntries()
	local list = {}
	for _, o in pairs(R.out) do
		list[#list + 1] = { wire = o.wire, order = o.n, waits = true }
	end
	local now = GetTime()
	local h = R.hello
	if h and not h.confirmed and ((h.drawUntil and now < h.drawUntil) or #list > 0) then
		list[#list + 1] = { wire = h.wire, order = h.order, untilT = #list == 0 and h.drawUntil or nil, waits = true }
	end
	local s = R.seen
	if s and now < s.untilT then
		list[#list + 1] = { wire = s.wire, order = s.order, untilT = s.untilT }
	end
	table.sort(list, function(a, b) return a.order > b.order end)
	-- Then the character's state parts the app hasn't confirmed (State.lua), in part order.
	if ns.State then
		for _, e in ipairs(ns.State.Entries()) do list[#list + 1] = e end
	end
	return list
end

-- Records are drawn newest first until the payload would pass 3,200 bytes; older ones wait
-- for a later frame (§2.2). A state part that doesn't fit is skipped, not a stop, so smaller
-- ones fill the space (docs/milestone-4.md). The frame counter changes whenever the content does.
-- The app is known to be away: the doorbells work (so its alive pulse, every 10 s while it runs,
-- would be heard) and nothing of it, pulse or slot, came for AWAY_AFTER seconds (nor since this
-- session's link started). Then the strip isn't drawn: it would sit on screen with nobody to read
-- it (seen in game, the app not running). What it carries stays queued; the app's first pulse
-- draws it again. Without working doorbells (slot-only mode) the app can't be told away, so the
-- strip is drawn as before.
L.AWAY_AFTER = 25
function L.AppAway()
	if not L.SignalsOK() then return false end
	local now = GetTime()
	local since = R.bridgeSeenAt or R.linkStartAt or now
	return now - since >= L.AWAY_AFTER
end

function L.RefreshStrip()
	if not ns.db or not R.nonce then return end
	if L.AppAway() then
		if R.stripShown then L.HideStrip() end
		R.stripAway = true
		return
	end
	R.stripAway = nil
	local parts, size, waits = {}, 0, false
	local now, untilT = GetTime(), nil
	local full = false -- a record didn't fit: the older ones wait too
	for _, e in ipairs(L.StripEntries()) do
		if e.state or not full then
			local add = #e.wire + (#parts > 0 and 1 or 0)
			if size + add <= ns.MAX_PAYLOAD then
				parts[#parts + 1] = e.wire
				size = size + add
				waits = waits or e.waits == true
				if e.untilT and e.untilT > now and (not untilT or e.untilT < untilT) then untilT = e.untilT end
			elseif not e.state then
				full = true
			end
		end
	end
	R.stripUntil = untilT
	R.stripWaits = waits
	if #parts == 0 then
		if R.stripShown then L.HideStrip() end
		return
	end
	local payload = table.concat(parts, ns.RS)
	if payload ~= R.stripPayload or not R.stripShown then
		R.frame = (R.frame + 1) % 65536
		DrawCells(R.frame, payload)
		R.stripPayload = payload
		R.stripShown = true
	elseif strip and not strip:IsShown() then
		-- Another addon hid it: shown again at the next refresh (every 2 s at most).
		strip:Show()
	end
end

-- The game's interface is on screen: not Alt+Z, a cinematic or a loading screen.
local function UIVisible()
	if type(UIParent) ~= "table" or type(UIParent.IsVisible) ~= "function" then return true end
	return UIParent:IsVisible() and true or false
end

function L.StripOnScreen()
	return (R.stripShown and strip ~= nil and strip:IsVisible() and UIVisible()) and true or false
end

-- The self-heal. A frame changes only the cells whose value changed, so a cell left wrong
-- (another addon recolouring a texture) would stay wrong and the app would stop reading the
-- strip. So while what's drawn waits for the app's answer, with the app up, it's drawn again in
-- full: once a frame that has waited L.HEAL_ACK, and every L.HEAL_EVERY however often it
-- changes. dt: seconds since the last tick; time off screen doesn't count.
function L.Heal(dt, onScreen)
	local H = R.heal
	if not (R.stripWaits and R.stripShown and L.BridgeAlive()) then
		H.drawn, H.full = 0, 0
		return
	end
	if not onScreen then return end
	H.drawn, H.full = H.drawn + dt, H.full + dt
	local why = (H.drawn >= L.HEAL_ACK and H.frame ~= R.frame and "ack") or (H.full >= L.HEAL_EVERY and "timer") or nil
	if not why then return end
	H.frame = R.frame
	H[why] = H[why] + 1
	DrawCells(R.frame, R.stripPayload, true)
end

function L.Clocks(now)
	local dt = R.clockAt and math.max(0, math.min(1, now - R.clockAt)) or 0
	R.clockAt = now
	L.Heal(dt, L.StripOnScreen())
end

---------------------------------------------------------------------------
-- The app's pulse
---------------------------------------------------------------------------

function L.NoteBridge(at)
	at = at or GetTime()
	if not R.bridgeSeenAt or at > R.bridgeSeenAt then R.bridgeSeenAt = at end
end

function L.BridgeAge()
	return R.bridgeSeenAt and math.max(0, GetTime() - R.bridgeSeenAt) or nil
end

-- Without beats (slot-only mode) the app is only heard from on a slot load, at least every
-- IDLE_CHECK, so it counts as gone that much later.
function L.BridgeAlive()
	local age = L.BridgeAge()
	return age ~= nil and age < (L.SlotOnly() and (IDLE_CHECK + RED_AFTER) or RED_AFTER)
end

function L.Beat()
	R.lastBeatAt = GetTime()
	L.NoteBridge()
	-- The app is back after being away: what's queued goes on the strip now.
	if R.stripAway then L.RefreshStrip() end
end

---------------------------------------------------------------------------
-- Self-test (§3)
---------------------------------------------------------------------------

-- Static part: present.wav plays and a fresh absent_* name doesn't.
function L.SelfTest()
	local S = R.sig
	local wasOK = L.SignalsOK()
	local wasStatic = S.static
	S.lastRun = GetTime()
	S.error = nil
	local reason
	if type(PlaySoundFile) ~= "function" then
		reason = "no-playsoundfile"
	else
		local present = Probe(SigPath("present"))
		R.absentCount = R.absentCount + 1
		local absent = Probe(SigPath(string.format("absent_%s_%d_%04x", R.nonce or "0000", R.absentCount, math.random(0, 0xFFFF))))
		if S.error then
			reason = "error"
		elseif not present then
			-- With all sound off the channel reports nothing at all.
			reason = ns.Try(GetCVar, "Sound_EnableAllSound") == "0" and "sound-off" or "present-missing"
		elseif absent then
			reason = "absent-plays"
		end
	end
	S.static = reason or "ok"
	if wasOK and not L.SignalsOK() then L.EnteredSlotOnly() end
	-- The static part passes again (sound back on): the live part was never settled while it failed.
	if S.static == "ok" and wasStatic ~= nil and wasStatic ~= "ok" and S.live == "pending" and not R.helloAnswered then
		L.ArmLiveCheck(LIVE_WAIT)
	end
	return S.static
end

-- One slot load settles the live half of the self-test (HelloAnswered): 30 s after the hello
-- goes up, and again after a send while it's unsettled, at most 3 times a session.
function L.ArmLiveCheck(delay)
	if R.sig.live ~= "pending" or R.helloAnswered or (R.liveChecks or 0) >= 3 then return end
	local at = GetTime() + delay
	if not R.liveCheckAt or at < R.liveCheckAt then R.liveCheckAt = at end
end

-- Slot-only mode from now on: a reply still awaited gets the fallback schedule (§4.2 rule 4).
function L.EnteredSlotOnly()
	if ns.Chat.Waiting() then L.Schedule(SLOTONLY_SCHEDULE, "schedule") end
end

---------------------------------------------------------------------------
-- hello and seen (§2.4)
---------------------------------------------------------------------------

function L.SayHello()
	if R.hello or not ns.db or not R.nonce then return end
	local db = ns.db
	local _, build, _, iface = ns.Try(GetBuildInfo)
	local args = {
		{ "cur", db.cursor }, { "ver", ns.VERSION }, { "build", build or "" }, { "iface", iface or "" },
		{ "n", db.sendCounter }, { "ctx", 0 }, { "sig", R.sig.static or "untested" }, { "slots", R.slots.free },
	}
	-- The push counter read so far (from the inbox), so the app stops re-ringing at once.
	if R.push.known and R.push.known > 0 then args[#args + 1] = { "p", R.push.known } end
	-- Where this session's next slot load is (the app writes only the slots from there on; a
	-- seen says it again after every load) and the way records go out (always the strip here).
	args[#args + 1] = { "slot", R.slots.nextIndex }
	args[#args + 1] = { "mode", "pixel" }
	-- The character's session id (State.lua): the app keeps one stored state per sid.
	local sid = ns.State and ns.State.Sid()
	if sid then args[#args + 1] = { "sid", sid } end
	R.slots.reported = R.slots.nextIndex
	local wire = L.Record(R.nonce, "hello", "", args, "")
	R.hello = { wire = wire, cur = db.cursor, p = R.push.known, order = db.sendCounter + 0.5, createdAt = GetTime() }
	R.hello.firstDrawAt = GetTime()
	R.hello.drawUntil = GetTime() + HELLO_DWELL
	L.ArmLiveCheck(LIVE_WAIT)
	L.RefreshStrip()
end

-- The app handled our hello: a slot says so (bridge.nonce).
function L.HelloConfirmed()
	local h = R.hello
	if not h or h.confirmed then return end
	h.confirmed = true
	L.Reported(h.cur)
	if h.p and (not R.push.reported or h.p > R.push.reported) then R.push.reported = h.p end
	R.lastAckAt = GetTime()
	L.RefreshStrip()
end

-- The slot answers our hello. Read because push rang (or a ring was heard since the hello went
-- up): the doorbells work. Read by the live check with no ring heard: the app answered, but its
-- ring didn't reach this client, so slot-only mode (§3 self-test, part 2).
function L.HelloAnswered(reason)
	if R.sig.live ~= "pending" then return end
	if reason == "push" or R.ringAfterHello then
		R.sig.live = "ok"
	elseif reason == "hello" and L.SignalsOK() then
		R.sig.live = "fail"
		L.Warn("live", "Answers come a little slower for now: the game can't hear the Spellmind app's signal. A /reload usually fixes it.")
		L.EnteredSlotOnly()
	end
end

function L.HelloTick(now)
	if R.liveCheckAt and now >= R.liveCheckAt then
		-- Still no push ring: a slot load settles whether the app handled the hello.
		R.liveCheckAt = nil
		if L.SignalsOK() and R.sig.live == "pending" and not R.helloAnswered and L.SlotsIn() then
			R.liveChecks = (R.liveChecks or 0) + 1
			L.LoadSlot("hello")
		end
	end
	local h = R.hello
	if not h or h.confirmed then return end
	if R.sig.static and R.sig.static ~= "ok" and not R.slotOnlyHelloLoaded and now - h.firstDrawAt >= SLOTONLY_HELLO_WAIT and L.SlotsIn() then
		-- Slot-only mode: nothing rings for the hello's answer, so read it once, a few seconds after it went up.
		R.slotOnlyHelloLoaded = true
		L.LoadSlot("hello")
	end
	-- Not confirmed and off the strip: show it again once the app shows life.
	if h.drawUntil and now >= h.drawUntil and R.bridgeSeenAt and R.bridgeSeenAt > h.drawUntil
		and now - (h.lastRetryAt or 0) >= HELLO_RETRY then
		h.lastRetryAt = now
		h.drawUntil = now + HELLO_DWELL
		L.ArmLiveCheck(LIVE_WAIT)
		L.RefreshStrip()
	end
end

-- A seen record for now's cursor and push counter, with where the next slot load is.
function L.SeenRecord()
	local db, P = ns.db, R.push
	local args = { { "cur", db.cursor } }
	if P.known and P.known > 0 then args[2] = { "p", P.known } end
	local withP = args[2] ~= nil
	args[#args + 1] = { "slot", R.slots.nextIndex }
	R.slots.reported = R.slots.nextIndex
	local wire = L.Record(R.nonce, "seen", "", args, "")
	return { wire = wire, cur = db.cursor, p = withP and P.known or nil, order = db.sendCounter + 0.75, untilT = GetTime() + SEEN_DWELL }
end

-- seen: when the applied cursor is 10 records, or 16 KB of record text, past the last reported
-- one, or 30 s after applying a record not yet reported; right after a slot load brought a newer
-- push counter, so the app stops re-ringing; and after every slot load, with slot=.
function L.MaybeSeen()
	local db = ns.db
	if not db or not R.nonce or R.seen then return end
	local P = R.push
	local now = GetTime()
	local pushDue = P.known ~= nil and P.known > 0 and (P.reported or 0) < P.known
	local slotDue = R.hello ~= nil and R.slots.nextIndex > (R.slots.reported or 0)
	local curDue = db.cursor > db.reported and (db.cursor - db.reported >= SEEN_RECORDS or R.applyBytes >= SEEN_BYTES
		or (R.unreportedSince ~= nil and now - R.unreportedSince >= SEEN_AFTER))
	if curDue and not pushDue and not slotDue then
		-- A keyed record still waiting for its ack will report this cursor anyway.
		for _, o in pairs(R.out) do
			if o.cur >= db.cursor then return end
		end
	end
	if not (curDue or pushDue or slotDue) then return end
	R.seen = L.SeenRecord()
	L.RefreshStrip()
end

-- Every tick: a seen whose few seconds are up counts as reported, and a timed entry leaves the
-- strip on time.
function L.Expire(now)
	if R.seen and now >= R.seen.untilT then
		L.Reported(R.seen.cur)
		if R.seen.p and (not R.push.reported or R.seen.p > R.push.reported) then R.push.reported = R.seen.p end
		R.seen = nil
		L.RefreshStrip()
	elseif R.stripUntil and now >= R.stripUntil then
		L.RefreshStrip()
	end
end

---------------------------------------------------------------------------
-- Doorbells (§3)
---------------------------------------------------------------------------

-- The highest push counter read. It only moves forward, except after a big drop, which means
-- the app's state was reset.
function L.NotePush(bp)
	local P = R.push
	bp = tonumber(bp)
	if not bp then return end
	if P.known and bp < P.known - 100 then
		P.known = bp
		P.reported = nil
		return
	end
	if not P.known or bp > P.known then P.known = bp end
end

-- A push ring: read one slot as soon as the last load is 1.5 s old (Poll). The app rings again
-- every 10 s until a seen reports its push counter.
function L.OnPushRing()
	local P = R.push
	P.rings = P.rings + 1
	P.lastRingAt = GetTime()
	P.pending = true
	if R.hello and not R.helloAnswered then R.ringAfterHello = true end
	-- A ring heard after the hello was answered settles a live test left open.
	if R.sig.live == "pending" and R.helloAnswered then R.sig.live = "ok" end
	L.NoteBridge()
end

-- Both push bells dead: nothing can announce a slot any more, so slot-only mode for this
-- session (a bell missing when the UI loaded stays missing).
function L.BellDied()
	local B = R.bells
	if B.push_a and B.push_a.dead and B.push_b and B.push_b.dead and R.sig.live ~= "fail" then
		R.sig.live = "fail"
		L.Warn("bells", "Answers come a little slower for now: the addon checks for them on a timer. A /reload usually brings the speed back.")
		L.EnteredSlotOnly()
	end
end

-- Read the bells. A missing read counts only when present.wav plays in the same read (else the
-- channel is down, e.g. sound off). present -> missing is a pulse. A bell missing for BELL_DEAD s
-- in a row isn't pulsing: dead until it reads present again. A bell's first read being missing
-- isn't a pulse (it may be mid-pulse); the app re-rings push. fast: the quarter-second poll,
-- which leaves the alive bells to the 2-second one.
function L.PollBells(fast)
	local reads, missing = {}, false
	for _, name in ipairs(BELLS) do
		if not (fast and SLOW_BELLS[name]) then
			local here = Probe(BellPath(name))
			reads[#reads + 1] = { name, here }
			if not here then missing = true end
		end
	end
	if missing and not Probe(BellPath("present")) then return end
	local now = GetTime()
	for _, rd in ipairs(reads) do
		local name, here = rd[1], rd[2]
		local b = R.bells[name]
		if not b then b = { rings = 0 }; R.bells[name] = b end
		if here then
			b.dead, b.missingSince, b.armed = nil, nil, true
		elseif not b.missingSince then
			b.missingSince = now
			if b.armed then
				b.rings = b.rings + 1
				if name == "push_a" or name == "push_b" then L.OnPushRing() else L.Beat() end
			end
		elseif not b.dead and now - b.missingSince >= BELL_DEAD then
			b.dead = true
			L.BellDied()
		end
	end
end

function L.Poll(fast)
	if not ns.db or not R.nonce then return end
	if L.SignalsOK() then
		L.PollBells(fast)
		local P = R.push
		if P.pending and L.SlotsIn() and (not R.slots.lastAt or GetTime() - R.slots.lastAt >= PUSH_GAP) then
			P.pending = false
			local before = P.known
			-- A ring whose slot has no newer push counter is a re-ring: the app never got the seen
			-- that told it. Say it again, or each re-ring loads another slot.
			if L.LoadSlot("push") and P.known == before and not R.protoMismatch then P.reported = nil end
			L.MaybeSeen()
		end
	end
	L.RunSchedules()
end

---------------------------------------------------------------------------
-- Slots (§4)
---------------------------------------------------------------------------

function L.SlotName(i)
	return string.format("%s%03d", ns.SLOT_PREFIX, i)
end

function L.CountFree()
	local free = 0
	for i = 1, ns.SLOT_COUNT do
		if not IsLoaded(L.SlotName(i)) then free = free + 1 end
	end
	R.slots.free = free
	return free
end

function L.NextSlot()
	for i = R.slots.nextIndex, ns.SLOT_COUNT do
		local name = L.SlotName(i)
		if not IsLoaded(name) then
			R.slots.nextIndex = i + 1
			return name
		end
	end
end

-- Load the next slot this UI session hasn't loaded, and read what it holds:
--   SpellmindSlotData = nil; C_AddOns.LoadAddOn(name); then read SpellmindSlotData
-- reason: push | hello | schedule | busy | idle. Returns the table it read, or nil.
function L.LoadSlot(reason)
	if not L.SlotsIn() then return nil end
	local S = R.slots
	local name = L.NextSlot()
	if not name then
		L.CountFree()
		S.out = true
		L.Warn("noslots", "Spellmind has used up its answers for this session. Type /reload to keep getting them.")
		return nil
	end
	SpellmindSlotData = nil
	local ok, loaded, why = pcall(LoadFn, name)
	S.loads = S.loads + 1
	S.reasons[reason] = (S.reasons[reason] or 0) + 1
	S.lastAt = GetTime()
	local data = SpellmindSlotData
	SpellmindSlotData = nil
	if not ok or not loaded then
		local code = tostring(ok and (why or "not loaded") or loaded)
		S.broken = string.format("%s (%s)", name, code)
		if code == "DISABLED" then
			L.Warn("parts", "Spellmind Parts are turned off in the AddOns list, so answers can't come in. Turn them back on there, then type /reload.")
		else
			L.Warn("slots", "A part of Spellmind didn't load, so answers can't come in. Run the Spellmind app's setup again, then restart WoW.")
		end
		L.CountFree()
		return nil
	end
	L.CountFree()
	R.loadReason = reason
	if type(data) == "table" then L.HandleSlotData(data, "slot") end
	R.loadReason = nil
	return type(data) == "table" and data or nil
end

-- A slot file or SpellmindInbox (the same table, §4.1).
function L.HandleSlotData(data, source)
	if type(data) ~= "table" then return false end
	if tonumber(data.v) ~= ns.PROTOCOL then
		R.protoMismatch = tostring(data.v)
		L.Warn("proto", "This Spellmind addon can't read what the Spellmind app sends, so nothing from it was used. Update the app; it updates the addon too.")
		return false
	end
	R.protoMismatch = nil
	local now = tonumber(data.now)
	if now then L.NoteBridge(GetTime() - math.max(0, time() - now)) end
	local bridge = type(data.bridge) == "table" and data.bridge or {}
	R.bridge = bridge
	-- The app's and the addon's major versions must match: said once, and everything still applies.
	local theirs = type(bridge.ver) == "string" and tonumber(bridge.ver:match("^(%d+)%.")) or nil
	if theirs and theirs ~= tonumber(ns.VERSION:match("^(%d+)")) then
		L.Warn("ver", "The Spellmind app is version " .. ns.Escape(bridge.ver) .. " and this addon is " .. ns.VERSION .. ". Update the app; it updates the addon too.")
	end
	if type(bridge.warn) == "string" and bridge.warn ~= "" then
		L.Warn("bridge:" .. bridge.warn, "A note from the Spellmind app: " .. ns.Escape(bridge.warn))
	end
	L.NotePush(bridge.push)
	if type(data.gw) == "table" then R.gw = data.gw end
	-- If token ~= ours, only the header is used: no acks, no records (§4.1).
	if data.token == ns.db.token then
		if type(bridge.acked) == "table" then
			for _, key in ipairs(bridge.acked) do
				if type(key) == "string" and R.out[key] then L.Acked(key) end
			end
		end
		if R.nonce ~= nil and bridge.nonce == R.nonce then
			R.helloAnswered = true
			L.HelloConfirmed()
			L.HelloAnswered(R.loadReason)
		end
		-- The app's caps and what it has of the character's state (bridge.state).
		if ns.State then ns.State.OnBridge(bridge) end
		L.ApplyRecords(data.records)
	end
	ns.Chat.Refresh()
	return true
end

local APPLIED = { reply = true, error = true, aborted = true }

-- §4.3: every record with seq > cursor, in seq order, then cursor = seq. replay = 1 applies
-- silently. A record for another chat than ours creates nothing (an orphan).
function L.ApplyRecords(records)
	if type(records) ~= "table" then return 0 end
	local list = {}
	for _, r in pairs(records) do
		if type(r) == "table" and tonumber(r.seq) then list[#list + 1] = r end
	end
	table.sort(list, function(a, b) return tonumber(a.seq) < tonumber(b.seq) end)
	local db = ns.db
	local applied = 0
	for _, r in ipairs(list) do
		local seq = math.floor(tonumber(r.seq))
		if seq > db.cursor then
			local replay = r.replay == 1 or r.replay == true
			if not APPLIED[r.t] then
				R.skipped = R.skipped + 1 -- a type from a later protocol milestone
			elseif r.chat == db.chat or ns.Chat.Known(r.chat) then -- any of our chats (milestone 6)
				ns.Chat.OnRecord(r, replay)
			else
				R.orphans = R.orphans + 1
			end
			db.cursor = seq
			applied = applied + 1
			R.applyBytes = R.applyBytes + #(type(r.text) == "string" and r.text or "")
			R.unreportedSince = R.unreportedSince or GetTime()
		end
	end
	if applied > 0 then L.MaybeSeen() end
	return applied
end

-- Spellmind/Inbox.lua, the same table as a slot, read at every login and /reload.
function L.ProcessInbox()
	local inbox = SpellmindInbox
	SpellmindInbox = nil
	if type(inbox) == "table" then L.HandleSlotData(inbox, "inbox") end
end

---------------------------------------------------------------------------
-- Slot-only mode (§4.2 rules 4 and 5)
---------------------------------------------------------------------------

function L.Schedule(steps, why)
	local now = GetTime()
	for _, s in ipairs(steps) do
		table.insert(R.sched, { at = now + s, why = why })
	end
end

function L.RunSchedules()
	local now = GetTime()
	local i = 1
	while i <= #R.sched do
		local s = R.sched[i]
		if now >= s.at then
			table.remove(R.sched, i)
			-- One load serves every schedule due at the same moment.
			if ns.Chat.Waiting() and L.SlotOnly() and not (R.slots.lastAt and now - R.slots.lastAt < 2) then
				L.LoadSlot(s.why)
			end
		else
			i = i + 1
		end
	end
end

-- Once a send's schedule is done, a load every 30 s while its reply is awaited (60 s once it
-- has waited 5 minutes), at most 20 per send.
function L.BusyFollow(now)
	if not (L.SlotOnly() and L.SlotsIn()) or #R.sched > 0 then return end
	local pend = ns.Chat.Waiting()
	local waited = pend and time() - pend.t
	if not waited or waited < SLOTONLY_SCHEDULE[#SLOTONLY_SCHEDULE] then return end
	local f = R.follow[pend.key]
	if not f then f = { n = 0 }; R.follow[pend.key] = f end
	local every = waited >= BUSY_SLOW_AFTER and BUSY_SLOW or BUSY_EVERY
	if f.n < BUSY_MAX and (not R.slots.lastAt or now - R.slots.lastAt >= every) then
		f.n = f.n + 1
		L.LoadSlot("busy")
	end
end

-- A message was queued: draw it; slot-only mode reads the answer on rule 4's schedule.
function L.AfterSend()
	if L.SlotOnly() and L.SlotsIn() then
		L.Schedule(SLOTONLY_SCHEDULE, "schedule")
	else
		L.ArmLiveCheck(LIVE_WAIT) -- the hello rides along with it
	end
	L.RefreshStrip()
end

---------------------------------------------------------------------------
-- Ticks
---------------------------------------------------------------------------

function L.FastActive()
	if R.stripShown or #R.sched > 0 then return true end
	local h = R.hello
	if h and not h.confirmed and h.drawUntil and GetTime() < h.drawUntil then return true end
	-- A question waiting keeps the fast poll, but not while the app is away: it can't answer then
	-- (the review: four checks a second for the rest of the session).
	return ns.Chat.Waiting() ~= nil and not L.AppAway()
end

function L.Slow()
	local now = GetTime()
	if not R.sig.lastRun or now - R.sig.lastRun >= SELFTEST_EVERY then L.SelfTest() end
	if L.SlotOnly() and L.SlotsIn() and now - (R.slots.lastAt or R.loginAt) >= IDLE_CHECK then
		L.LoadSlot("idle")
	end
	L.BusyFollow(now)
	L.MaybeSeen()
	L.RefreshStrip()
	ns.Chat.Refresh()
end

function L.OnTick()
	if not ns.db or not R.nonce then return end
	R.ticks = R.ticks + 1
	local now = GetTime()
	local slow = R.ticks % SLOW_EVERY == 0
	if slow or L.FastActive() then L.Poll(not slow) end
	L.HelloTick(now)
	L.Clocks(now)
	L.Expire(now)
	if slow then L.Slow() end
end

-- One line for the window: what the player needs to know about the link right now, or "".
function L.Status()
	if not R.nonce then return "" end
	if R.slots.out then return "Type /reload to keep getting answers." end
	if R.slots.broken then return "Answers can't come in: see the note above." end
	if R.protoMismatch then return "Update the Spellmind app: it updates the addon too." end
	if not L.BridgeAlive() then return "Start the Spellmind app to get answers." end
	if ns.Chat.Waiting() then return "Spellmind is thinking..." end
	return ""
end

-- PLAYER_LOGIN (every login and /reload): a new nonce, the outbox redrawn verbatim, the
-- self-test, the inbox, then the hello.
function L.Start()
	local db = ns.db
	L.Reset()
	R.linkStartAt = GetTime() -- the app counts as away only AWAY_AFTER seconds after this
	R.nonce = ns.NewNonce()
	table.insert(db.nonces, 1, R.nonce)
	while #db.nonces > 8 do table.remove(db.nonces) end
	L.LoadOutbox()
	L.CountFree()
	L.SelfTest()
	L.ProcessInbox()
	L.RefreshStrip()
	C_Timer.After(HELLO_DELAY, L.SayHello)
	R.ticker = C_Timer.NewTicker(FAST_TICK, L.OnTick)
end

ns.On("UI_SCALE_CHANGED", L.UpdateStripScale)
ns.On("DISPLAY_SIZE_CHANGED", L.UpdateStripScale)
