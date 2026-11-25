-- GearUI.lua: the gear advisor in the game's own windows (docs/features.md §2.1 and §3.2,
-- docs/milestone-9.md), all from Gear.lua's local facts:
--
--   the reward pick     turning in a quest with a choice: a small "Spellmind picks" box with why,
--                       and Why? to ask the AI
--   the character sheet a dot on a gear slot: green, an upgrade is waiting (bags or a quest in the
--                       log); orange or red, its durability is low. Its tooltip says which.
--   the merchant        "What to sell" beside the merchant's window: a card listing what's safe to
--                       sell (grey junk, bound gear that's worse or unusable) and its value. Nothing
--                       is sold: the player sells it, or not.
--
-- Plain frames on plain windows; nothing touches a protected frame, nothing acts.

local _, ns = ...
local U = {}
ns.GearUI = U

U.SLOT_FRAMES = { "Head", "Neck", "Shoulder", "Shirt", "Chest", "Waist", "Legs", "Feet", "Wrist", "Hands", "Finger0", "Finger1",
	"Trinket0", "Trinket1", "Back", "MainHand", "SecondaryHand", "Ranged", "Tabard" }

local BACKDROP = { bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } }

local function Money(copper)
	copper = math.floor(tonumber(copper) or 0)
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	local out = {}
	if g > 0 then out[#out + 1] = g .. "g" end
	if s > 0 then out[#out + 1] = s .. "s" end
	if c > 0 or #out == 0 then out[#out + 1] = c .. "c" end -- "3s", not "3s 0c"
	return table.concat(out, " ")
end
U.Money = Money

local function Button(parent, label, w)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	if ns.Theme then ns.Theme.Adopt(b, "button") end
	b:SetSize(w, 20)
	if b.SetBackdrop then
		b:SetBackdrop(BACKDROP)
		b:SetBackdropColor(0.08, 0.06, 0.16, 0.95)
		b:SetBackdropBorderColor(0.58, 0.45, 0.98, 1)
	end
	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
	b.text:SetText(label)
	b:SetScript("OnEnter", function(self) if self.SetBackdropBorderColor then self:SetBackdropBorderColor(0.85, 0.68, 0.25, 1) end end)
	b:SetScript("OnLeave", function(self) if self.SetBackdropBorderColor then self:SetBackdropBorderColor(0.58, 0.45, 0.98, 1) end end)
	return b
end
U.Button = Button

---------------------------------------------------------------------------
-- The reward pick
---------------------------------------------------------------------------

function U.BuildPick()
	if U.pick then return U.pick end
	local f = CreateFrame("Frame", "SpellmindPick", UIParent, "BackdropTemplate")
	if ns.Theme then ns.Theme.Adopt(f, "window") end
	f:SetSize(300, 72)
	f:SetFrameStrata("HIGH")
	f:SetClampedToScreen(true)
	if f.SetBackdrop then
		f:SetBackdrop(BACKDROP)
		f:SetBackdropColor(0.04, 0.03, 0.09, 0.95)
		f:SetBackdropBorderColor(0.62, 0.49, 1, 1)
	end
	if ns.Window then ns.Window.Fill(f, 3, 0.035, 0.025, 0.08, 0.97); ns.Window.Corners(f, 14) end
	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetSize(18, 18)
	f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -9)
	f.icon:SetTexture(ns.Marks.ICON)
	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 34, -11)
	f.title:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -11)
	f.title:SetJustifyH("LEFT")
	f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.text:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
	f.text:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -30)
	f.text:SetJustifyH("LEFT")
	f.why = Button(f, "Why?", 56)
	f.why:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 7)
	f.why:SetScript("OnClick", function() U.AskPick() end)
	f:Hide()
	U.pick = f
	return f
end

-- QUEST_COMPLETE: the likely pick of a choice of rewards, beside the quest's window (or at the top).
function U.ShowPick()
	if not ns.Marks.On("reward") then return end
	local p = ns.Gear.PickChoice()
	if not p then return end
	local f = U.BuildPick()
	f.choice = p
	f.title:SetText("Spellmind picks: " .. ns.Escape(p.name))
	f.text:SetText(ns.Escape(p.why or ""))
	f:ClearAllPoints()
	local qf = rawget(_G, "QuestFrame")
	if type(qf) == "table" and qf.IsShown and qf:IsShown() then f:SetPoint("TOPLEFT", qf, "TOPRIGHT", 6, -40)
	else f:SetPoint("TOP", UIParent, "TOP", 0, -120) end
	f:Show()
	return p
end

function U.AskPick()
	local f = U.pick
	if not f or not f.choice then return end
	local names = {}
	for i = 1, math.min(tonumber((ns.Try(GetNumQuestChoices))) or 0, 8) do
		local l = ns.Try(GetQuestItemLink, "choice", i)
		local n = type(l) == "string" and l:match("|h%[(.-)%]|h")
		if n then names[#names + 1] = n end
	end
	local title = ns.Try(GetTitleText) or "this quest"
	ns.Marks.Ask(f, "Reward pick: " .. ns.Escape(tostring(title)),
		"I'm turning in " .. tostring(title) .. ". The rewards to choose from are " .. table.concat(names, ", ")
		.. ". Which should I take, and why? Spellmind's pick was " .. f.choice.name .. ".")
end

ns.On("QUEST_COMPLETE", function() C_Timer.After(0.1, function() pcall(U.ShowPick) end) end)
ns.On("QUEST_FINISHED", function() if U.pick then U.pick:Hide() end end)

---------------------------------------------------------------------------
-- The character sheet's slots
---------------------------------------------------------------------------

-- Each slot's state now: { [slot] = { up = candidate, dur = percent } }.
function U.SlotStates()
	local out = {}
	for _, c in ipairs(ns.Gear.Candidates()) do
		out[c.slot] = out[c.slot] or {}
		out[c.slot].up = out[c.slot].up or c
	end
	for slot = 1, 19 do
		local cur, max = ns.Try(GetInventoryItemDurability, slot)
		if type(cur) == "number" and type(max) == "number" and max > 0 then
			local pct = math.floor(cur / max * 100 + 0.5)
			if pct < 50 then out[slot] = out[slot] or {}; out[slot].dur = pct end
		end
	end
	return out
end

local function SlotButton(slot)
	return rawget(_G, "Character" .. U.SLOT_FRAMES[slot] .. "Slot")
end

function U.MarkSlots()
	if not ns.Marks.On("sheet") then
		for _, d in pairs(U.dots or {}) do d:Hide() end
		return
	end
	U.dots = U.dots or {}
	U.states = U.SlotStates()
	for slot = 1, 19 do
		local b = SlotButton(slot)
		if type(b) == "table" then
			local d = U.dots[slot]
			if not d then
				d = b:CreateTexture(nil, "OVERLAY", nil, 7)
				d:SetSize(8, 8)
				d:SetPoint("TOPRIGHT", b, "TOPRIGHT", -2, -2)
				U.dots[slot] = d
				-- Its tooltip says why, after the game's own lines: through the game's own slot function
				-- when it has one (U.HookSheet), which the sheet calls again while the mouse stays and
				-- rebuilds the tooltip each time (seen in game: our line showed for a frame, then went).
				if not U.slotFnHooked then b:HookScript("OnEnter", function(self) U.SlotTip(slot) end) end
			end
			local s = U.states[slot]
			if s and s.up then d:SetColorTexture(0.1, 1, 0.1, 1); d:Show()
			elseif s and s.dur and s.dur < 25 then d:SetColorTexture(1, 0.2, 0.2, 1); d:Show()
			elseif s and s.dur then d:SetColorTexture(1, 0.6, 0.15, 1); d:Show()
			else d:Hide() end
		end
	end
end

-- The tooltip already holds this line (two paths add it: the slot function's hook and the item
-- tooltip's post-call, whichever rebuild comes): its text lines read back.
local function Has(tip, line)
	local name = tip.GetName and tip:GetName()
	for i = 1, (tip.NumLines and tip:NumLines()) or 0 do
		local fs = name and rawget(_G, name .. "TextLeft" .. i)
		if fs and fs.GetText and fs:GetText() == line then return true end
	end
	for _, l in ipairs(tip.added or {}) do if l == line then return true end end -- (the tests' tooltip)
	return false
end

-- A character sheet slot button's inventory slot, or nil.
function U.SlotOf(owner)
	if type(owner) ~= "table" or not owner.GetID then return nil end
	local id = owner:GetID()
	if type(id) ~= "number" or id < 1 or id > 19 then return nil end
	return rawget(_G, "Character" .. (U.SLOT_FRAMES[id] or "") .. "Slot") == owner and id or nil
end

function U.SlotTip(slot, tip)
	local s = U.states and U.states[slot]
	tip = tip or GameTooltip
	if not s or not tip or not tip.AddLine then return end
	local lines = {}
	if s.up then
		lines[#lines + 1] = "|cff9d7dffSpellmind:|r upgrade waiting: " .. ns.Escape(s.up.name) .. " (" .. (s.up.from == "bags" and "in your bags"
			or ("from " .. ns.Escape(s.up.from))) .. ")"
	end
	if s.dur then lines[#lines + 1] = "|cff9d7dffSpellmind:|r durability " .. s.dur .. "%: repair soon" end
	local added = false
	for _, line in ipairs(lines) do
		if not Has(tip, line) then tip:AddLine(line, 1, 1, 1, true); added = true end
	end
	if added then tip:Show() end
end

function U.HookSheet()
	if U.sheetHooked then return end
	local pd = rawget(_G, "PaperDollFrame") or rawget(_G, "CharacterFrame")
	if type(pd) ~= "table" or not pd.HookScript then return end
	pd:HookScript("OnShow", function() pcall(U.MarkSlots) end)
	-- The slot tooltip: after every call of the game's own function (its first, and each refresh
	-- while the mouse stays), the button's id being the inventory slot.
	if type(rawget(_G, "PaperDollItemSlotButton_OnEnter")) == "function" then
		hooksecurefunc("PaperDollItemSlotButton_OnEnter", function(button)
			local id = button and button.GetID and button:GetID()
			if type(id) == "number" then pcall(U.SlotTip, id) end
		end)
		U.slotFnHooked = true
	end
	U.sheetHooked = true
end

local function SheetOpen()
	local pd = rawget(_G, "PaperDollFrame")
	return type(pd) == "table" and pd.IsVisible and pd:IsVisible()
end

ns.On("PLAYER_LOGIN", function() U.HookSheet() end)
for _, ev in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED", "UPDATE_INVENTORY_DURABILITY", "QUEST_LOG_UPDATE" }) do
	ns.On(ev, function() if SheetOpen() then pcall(U.MarkSlots) end end)
end

---------------------------------------------------------------------------
-- The merchant
---------------------------------------------------------------------------

function U.SellText()
	local list, total = ns.Gear.SellList()
	if #list == 0 then return "Nothing in your bags is clearly safe to sell: no grey junk, and no bound gear you can't use or that's worse than what you wear." end
	local lines = { "Safe to sell, worth |cffffd100" .. Money(total) .. "|r in all:", "" }
	for i, it in ipairs(list) do
		if i > 12 then lines[#lines + 1] = "|cff888888and " .. (#list - 12) .. " more|r"; break end
		lines[#lines + 1] = "• " .. ns.Escape(it.name) .. (it.n > 1 and (" x" .. it.n) or "") .. ": " .. Money(it.copper) .. " |cff888888(" .. it.why .. ")|r"
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = "|cff888888Spellmind doesn't sell anything: right-click the items to sell them.|r"
	return table.concat(lines, "\n")
end

function U.ShowMerchant()
	if not ns.Marks.On("merchant") then return end
	local mf = rawget(_G, "MerchantFrame")
	if type(mf) ~= "table" then return end
	if not U.sell then
		U.sell = Button(mf, "Spellmind: what to sell", 150)
		U.sell:SetPoint("TOPLEFT", mf, "TOPRIGHT", 4, -36)
		U.sell:SetScript("OnClick", function(self)
			ns.Marks.ShowText(mf, "Spellmind: what to sell", U.SellText(), { owner = mf })
		end)
	end
	U.sell:Show()
end

ns.On("MERCHANT_SHOW", function() pcall(U.ShowMerchant) end)
ns.On("MERCHANT_CLOSED", function()
	if ns.Marks.card and ns.Marks.card.owner == rawget(_G, "MerchantFrame") then ns.Marks.card:Hide() end
end)
