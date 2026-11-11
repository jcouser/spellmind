-- Quests.lua: the Spellmind mark in the quest log's details (docs/features.md §2.1 and §3.1,
-- docs/milestone-5.md). On Forever the quest log is the world map's quest panel (QuestMapFrame), and
-- QuestMapFrame_ShowQuestDetails(questID) opens a quest's details (probe round 4, 2026-11-10).
--
--   hover   the quest's level against yours, group or elite, what's left, where, the rewards
--   click   "Break it down": the quest's text, objectives and rewards go as the focus part, and the
--           answer shows in a card beside the map
--
-- Read only: it never selects a quest, opens a window or sets a waypoint.

local _, ns = ...
local Q = {}
ns.Quests = Q

Q.TEXT_MAX = 1200 -- bytes of the quest's description in focus
Q.GOAL_MAX = 400 -- bytes of its objectives line
Q.REWARDS_MAX = 6
Q.ASK = "Break this quest down for me."
-- The game's quest difficulty colours (GetQuestDifficultyColor's font), in words for the hover.
Q.DIFF_WORDS = {
	Impossible = "|cffff1a1ared|r: well above your level",
	VeryDifficult = "|cffff8040orange|r: a few levels above you",
	Difficult = "|cffffff00yellow|r: about your level",
	Standard = "|cff40c040green|r: easy for you",
	Trivial = "|cff808080grey|r: too low to be worth much XP",
}

local unpack = unpack or table.unpack -- Lua 5.1 in game; 5.3 in the tests' VM
local function Try(fn, ...) return ns.Try(fn, ...) end
-- Every return (ns.Try keeps four; GetQuestLogChoiceInfo gives the item id sixth).
local function All(fn, ...)
	if type(fn) ~= "function" then return nil end
	local r = { pcall(fn, ...) }
	if not r[1] then return nil end
	return unpack(r, 2, 8)
end
local S = function() return ns.State end
-- An O object's fields as a plain table.
local function Plain(o)
	local t = {}
	for _, kv in ipairs(type(o) == "table" and o._o or {}) do t[kv[1]] = kv[2] end
	return t
end

local function LogIndex(id)
	local QL = C_QuestLog
	local i = QL and Try(QL.GetLogIndexForQuestID, id)
	if type(i) == "number" and i > 0 then return i end
	return nil
end

local function Info(id)
	local QL = C_QuestLog
	local i = LogIndex(id)
	local info = i and QL and Try(QL.GetInfo, i)
	return type(info) == "table" and info or nil, i
end

-- The quest log's header a quest sits under: its zone or dungeon ("Loch Modan", "The Hall of
-- Thanes"), as the log and Questie group them.
function Q.Header(id)
	local QL = C_QuestLog
	local i = LogIndex(id)
	if not i or not QL then return nil end
	for k = i - 1, 1, -1 do
		local info = Try(QL.GetInfo, k)
		if type(info) == "table" and info.isHeader then return S().Text(info.title) end
	end
	return nil
end

-- The game's tag for a quest ("Dungeon", "Raid", "Elite", "Group"), or nil.
local function TagName(id)
	local QL = C_QuestLog
	local t = QL and Try(QL.GetQuestTagInfo, id)
	if type(t) == "table" and type(t.tagName) == "string" and t.tagName ~= "" then return S().Text(t.tagName, 20) end
	return nil
end

-- "Difficult", from the font name of the colour the game gives a quest of that level.
local function Difficulty(level)
	local c = type(level) == "number" and Try(GetQuestDifficultyColor, level)
	local font = type(c) == "table" and c.font
	return type(font) == "string" and font:match("^QuestDifficulty_(%a+)$") or nil
end

-- Where the quest's objectives are on the player's map now (x, y in map percent), and how far.
local function Where(id)
	local map = C_Map and Try(C_Map.GetBestMapForUnit, "player")
	if type(map) ~= "number" then return nil end
	local x, y
	for _, q in ipairs(Try(C_QuestLog.GetQuestsOnMap, map) or {}) do
		if type(q) == "table" and q.questID == id and type(q.x) == "number" and type(q.y) == "number" then
			x, y = S().Round1(q.x * 100), S().Round1(q.y * 100)
			break
		end
	end
	local d2, ok = Try(C_QuestLog.GetDistanceSqToQuest, id)
	local dist = (ok and type(d2) == "number" and d2 >= 0) and math.floor(math.sqrt(d2) / 10 + 0.5) * 10 or nil
	if not x then return nil, dist end
	local info = Try(C_Map.GetMapInfo, map)
	local zone = type(info) == "table" and S().Text(info.name) or nil
	return { zone = zone, x = x, y = y, map = map }, dist
end

Q.COMPASS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

-- The compass direction from the player to a spot on the same map (x, y in map percent), or nil.
-- The map's world size, when the game gives it, keeps east-west and north-south in proportion.
function Q.Direction(where)
	if type(where) ~= "table" or not where.map then return nil end
	local pos = Try(C_Map.GetPlayerMapPosition, where.map, "player")
	local px, py
	if type(pos) == "table" then
		if type(pos.GetXY) == "function" then px, py = pos:GetXY() else px, py = pos.x, pos.y end
	end
	if type(px) ~= "number" or type(py) ~= "number" then return nil end
	local w, h = Try(C_Map.GetMapWorldSize, where.map)
	w, h = (type(w) == "number" and w > 0) and w or 1, (type(h) == "number" and h > 0) and h or 1
	local dx, dy = (where.x / 100 - px) * w, (where.y / 100 - py) * h -- map y grows southward
	if math.abs(dx) < 1e-6 and math.abs(dy) < 1e-6 then return nil end
	local atan2 = math.atan2 or math.atan
	local deg = (math.deg(atan2(dx, -dy)) + 360) % 360 -- 0 = north, clockwise
	return Q.COMPASS[math.floor((deg + 22.5) / 45) % 8 + 1]
end

-- Go: the game's own map pin and arrow, on the player's click (features.md §1 rule 6: Spellmind
-- never acts by itself; a waypoint is the game's player-facing feature). The quest's spot on this
-- map when the game shows one; otherwise the quest itself is super-tracked, which points the
-- game's arrow wherever it knows to. Returns what it did ("pin", "track") or nil.
function Q.Go(id)
	local q = Q.Read(id)
	if not q then return nil end
	local w = q.where
	local SM, ST = rawget(_G, "C_Map"), rawget(_G, "C_SuperTrack")
	local point = rawget(_G, "UiMapPoint")
	if w and SM and type(SM.SetUserWaypoint) == "function" and type(point) == "table" and type(point.CreateFromCoordinates) == "function"
		and Try(SM.CanSetUserWaypointOnMap, w.map) ~= false then
		local ok = pcall(function()
			SM.SetUserWaypoint(point.CreateFromCoordinates(w.map, w.x / 100, w.y / 100))
			if ST and type(ST.SetSuperTrackedUserWaypoint) == "function" then ST.SetSuperTrackedUserWaypoint(true) end
		end)
		if ok then return "pin" end
	end
	if ST and type(ST.SetSuperTrackedQuestID) == "function" and pcall(ST.SetSuperTrackedQuestID, id) then return "track" end
	return nil
end

-- What's left of a quest, short: its unfinished objectives ("0/8 Carved Stone Idol"), at most two.
function Q.Left(q)
	local bits = {}
	for _, o in ipairs(type(q) == "table" and q.obj or {}) do
		local p = Plain(o)
		local have, need = tonumber(p.have) or 0, tonumber(p.need) or 0
		if have < need and #bits < 2 then bits[#bits + 1] = have .. "/" .. need .. " " .. ns.Escape(p.text or "objective") end
	end
	return #bits > 0 and table.concat(bits, ", ") or nil
end

-- The rewards: money, XP, and the items (to choose from, and given). Choice info reads the selected
-- quest, so it's only read when that's this one.
local function Rewards(id)
	local out = { money = S().Whole(Try(GetQuestLogRewardMoney, id)), xp = S().Whole(Try(GetQuestLogRewardXP, id)) }
	if out.money == 0 then out.money = nil end
	if out.xp == 0 then out.xp = nil end
	local selected = C_QuestLog and Try(C_QuestLog.GetSelectedQuest)
	-- kind: "choice" or "reward", GetQuestLogItemLink's first argument: with the link, a wearable
	-- reward also gets its type, where it's worn and its stats, so the AI can weigh the pick.
	local function Items(count, get, kind)
		local list = {}
		for i = 1, math.min(S().Whole(count) or 0, Q.REWARDS_MAX) do
			local name, _, n, q, usable, itemID = get(i)
			if type(name) == "string" and name ~= "" then
				local it = { id = S().Whole(itemID), name = S().Text(name), q = S().Whole(q), n = S().Whole(n), usable = usable and true or false }
				local link = Try(GetQuestLogItemLink, kind, i, id)
				if type(link) ~= "string" and itemID then link = "item:" .. S().Whole(itemID) end
				local info = type(link) == "string" and { pcall(C_Item.GetItemInfo, link) } or {}
				if info[1] and type(info[10]) == "string" and info[10]:match("^INVTYPE_") and not info[10]:match("^INVTYPE_NON_EQUIP") then
					it.sub, it.equip = S().Text(info[8]), S().Text(info[10]:gsub("^INVTYPE_", ""):lower())
					it.st = S().ItemStatsO(link)
				end
				list[#list + 1] = it
			end
		end
		return #list > 0 and list or nil
	end
	if selected == id then
		out.choices = Items(Try(GetNumQuestLogChoices, id), function(i) return All(GetQuestLogChoiceInfo, i) end, "choice")
	end
	out.items = Items(Try(GetNumQuestLogRewards, id), function(i) return All(GetQuestLogRewardInfo, i, id) end, "reward")
	return out
end

-- Everything the hover and the focus part use, read now.
function Q.Read(id)
	if type(id) ~= "number" or id <= 0 then return nil end
	local info, logIndex = Info(id)
	if not info then return nil end
	local QL = C_QuestLog
	local level = S().Whole(info.difficultyLevel) or S().Whole(info.level)
	local desc, goal
	if logIndex then desc, goal = Try(GetQuestLogQuestText, logIndex) end
	local group = S().Whole(Try(QL.GetSuggestedGroupSize, id)) or S().Whole(info.suggestedGroup)
	local where, dist = Where(id)
	return {
		id = id, title = S().Text(info.title) or S().Text(Try(QL.GetTitleForQuestID, id)), level = level,
		diff = Difficulty(level), trivial = Try(QL.IsQuestTrivial, id) and true or false, elite = Try(QL.IsEliteQuest, id) and true or false,
		group = (group and group > 1) and group or nil, complete = (Try(QL.IsComplete, id) or Try(QL.ReadyForTurnIn, id)) and true or false,
		text = S().Text(desc, Q.TEXT_MAX), goal = S().Text(goal, Q.GOAL_MAX), obj = S().Objectives(id),
		rewards = Rewards(id), where = where, dist = dist, header = Q.Header(id), tagName = TagName(id), logIndex = logIndex,
	}
end

local function Money(copper)
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	local out = {}
	if g > 0 then out[#out + 1] = g .. "g" end
	if s > 0 then out[#out + 1] = s .. "s" end
	if c > 0 and g == 0 then out[#out + 1] = c .. "c" end
	return table.concat(out, " ")
end

-- The hover's lines: local facts only (escaped).
function Q.Facts(id)
	local q = Q.Read(id)
	if not q then return { "This quest's details aren't loaded yet." } end
	local lines = {}
	local you = S().Whole(Try(UnitLevel, "player"))
	local lvl = q.level and ("Level " .. q.level .. " quest") or "Quest"
	local word = q.diff and Q.DIFF_WORDS[q.diff]
	lines[#lines + 1] = lvl .. (word and (": " .. word) or "") .. (you and (" (you're " .. you .. ")") or "")
	if q.elite or q.group then
		lines[#lines + 1] = (q.elite and "Elite" or "Group") .. (q.group and (": " .. q.group .. " players suggested") or ": bring help")
	end
	if q.complete then
		lines[#lines + 1] = "|cff40c040Ready to turn in.|r"
	else
		for _, o in ipairs(q.obj or {}) do
			local p = Plain(o)
			local have, need = tonumber(p.have) or 0, tonumber(p.need) or 0
			if have < need then lines[#lines + 1] = "Left: " .. ns.Escape(p.text or "objective") .. " " .. have .. "/" .. need end
		end
	end
	if q.where then
		-- 25, not 25.0 (Lua 5.3's tostring of a float; the game's 5.1 prints 25).
		local function N(v) return v == math.floor(v) and string.format("%d", v) or string.format("%.1f", v) end
		lines[#lines + 1] = "On your map: " .. N(q.where.x) .. ", " .. N(q.where.y) .. (q.dist and (" (about " .. string.format("%d", q.dist) .. " yd)") or "")
	end
	local r = q.rewards or {}
	local bits = {}
	if r.money then bits[#bits + 1] = Money(r.money) end
	if r.xp then bits[#bits + 1] = r.xp .. " XP" end
	if r.choices then
		local usable = 0
		for _, c in ipairs(r.choices) do if c.usable then usable = usable + 1 end end
		bits[#bits + 1] = "choose 1 of " .. #r.choices .. " (" .. usable .. " you can use)"
	end
	if r.items then bits[#bits + 1] = #r.items .. " item" .. (#r.items > 1 and "s" or "") end
	if #bits > 0 then lines[#lines + 1] = "Rewards: " .. table.concat(bits, ", ") end
	return lines
end

-- The focus part for an Explain: the quest as the contract has it (docs/milestone-5.md).
function Q.Focus(id)
	local q = Q.Read(id)
	if not q then return nil end
	local O = S().JSON.O
	local function List(items)
		if not items then return nil end
		local out = {}
		for _, it in ipairs(items) do
			out[#out + 1] = O("id", it.id, "name", it.name, "q", it.q, "n", it.n, "usable", it.usable, "sub", it.sub, "equip", it.equip, "st", it.st)
		end
		return out
	end
	local where = q.where and O("zone", q.where.zone, "x", q.where.x, "y", q.where.y, "dist", q.dist) or (q.dist and O("dist", q.dist)) or nil
	local r = q.rewards or {}
	return O("v", 1, "kind", "quest", "id", q.id, "title", q.title, "level", q.level, "diff", q.diff, "trivial", q.trivial,
		"elite", q.elite, "group", q.group, "complete", q.complete, "text", q.text, "goal", q.goal, "obj", q.obj,
		"money", r.money, "xp", r.xp, "choices", List(r.choices), "items", List(r.items), "where", where)
end

-- An Explain's request for the quest a mark shows.
function Q.Explain(id, anchor)
	local q = Q.Read(id)
	if not q then return nil end
	return { about = "quest:" .. id, label = "Break it down: " .. ns.Escape(q.title or "this quest"), text = Q.ASK, focus = Q.Focus(id), anchor = anchor }
end

---------------------------------------------------------------------------
-- The quest log's details
---------------------------------------------------------------------------

function Q.Hook()
	if Q.mark or not ns.Marks.On("quest") then return Q.mark end
	local panel = rawget(_G, "QuestMapFrame")
	local details = (type(panel) == "table" and panel.DetailsFrame) or rawget(_G, "QuestMapDetailsScrollFrame")
	if type(details) ~= "table" or type(rawget(_G, "QuestMapFrame_ShowQuestDetails")) ~= "function" then return nil end
	local mark
	mark = ns.Marks.Create(details, "SpellmindQuestMark", {
		facts = function() return Q.Facts(mark.questID) end,
		explain = function() return Q.Explain(mark.questID, rawget(_G, "WorldMapFrame") or details) end,
	}, { round = true })
	-- Beside the details' Back button, at the left of the header row. The right end of that row is
	-- where other addons put their round buttons (Questie's, Spoken's), and the mark overlapped them
	-- there (seen in game); their number varies, so the left end is the reliable spot.
	local back = rawget(details, "BackButton")
	if type(back) ~= "table" then
		local frame = rawget(details, "BackFrame")
		back = type(frame) == "table" and rawget(frame, "BackButton") or nil
	end
	if type(back) == "table" then
		mark:SetPoint("LEFT", back, "RIGHT", 6, 0)
	else
		mark:SetPoint("TOPLEFT", details, "TOPLEFT", 110, -4)
	end
	mark:Hide()
	hooksecurefunc("QuestMapFrame_ShowQuestDetails", function(questID)
		if not ns.Marks.On("quest") then mark:Hide(); return end
		mark.questID = type(questID) == "number" and questID or (C_QuestLog and Try(C_QuestLog.GetSelectedQuest))
		mark:Show()
	end)
	Q.mark = mark
	return mark
end

ns.On("PLAYER_LOGIN", function() Q.Hook() end)
ns.On("ADDON_LOADED", function(_, name)
	if name == "Blizzard_WorldMap" or name == "Blizzard_QuestLog" then Q.Hook() end
end)
