-- Minimap.lua: Spellmind's button on the minimap's rim (docs/features.md §2). Click: the Chat tab; right-click: the last other tab.
-- Drag: around the rim (its angle saved in SpellmindDB.minimap). /sm minimap off hides it.
-- Right-click: the Advisor panel. A gold dot shows while a nudge waits.

local _, ns = ...
local MB = {}
ns.MinimapButton = MB

MB.ICON = "Interface\\AddOns\\Spellmind\\Media\\Spellmind"
MB.BADGE = "Interface\\AddOns\\Spellmind\\Media\\Badge"
MB.RADIUS = 105 -- from the minimap's centre (its rim at the default size)
MB.DEFAULT_ANGLE = 200 -- degrees, about eight o'clock

local function Saved()
	local db = ns.db
	if not db then return {} end
	if type(db.minimap) ~= "table" then db.minimap = {} end
	return db.minimap
end

-- On the rim at the saved angle.
function MB.Place()
	local b, map = MB.button, rawget(_G, "Minimap")
	if not b or not map then return end
	local a = math.rad(tonumber(Saved().angle) or MB.DEFAULT_ANGLE)
	b:ClearAllPoints()
	b:SetPoint("CENTER", map, "CENTER", math.cos(a) * MB.RADIUS, math.sin(a) * MB.RADIUS)
end

-- The cursor's angle around the minimap's centre, in degrees.
local function CursorAngle(map)
	local mx, my = map:GetCenter()
	local cx, cy = GetCursorPosition()
	local scale = map:GetEffectiveScale()
	if not (mx and cx and scale) then return nil end
	local atan2 = math.atan2 or math.atan -- Lua 5.1 in game; 5.3's atan takes two arguments
	return math.deg(atan2(cy / scale - my, cx / scale - mx))
end

function MB.Create()
	local map = rawget(_G, "Minimap")
	if MB.button or type(map) ~= "table" then return MB.button end
	local b = CreateFrame("Button", "SpellmindMinimapButton", map)
	b:SetSize(31, 31)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(8)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:RegisterForDrag("LeftButton")
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetSize(20, 20)
	b.bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	b.bg:SetPoint("CENTER", b, "CENTER", 0, 1)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetSize(19, 19)
	b.icon:SetTexture(MB.ICON)
	b.icon:SetPoint("CENTER", b, "CENTER", 0, 1)
	b.border = b:CreateTexture(nil, "OVERLAY")
	b.border:SetSize(53, 53)
	b.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	b.border:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
	b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
	b:SetScript("OnClick", function(_, button)
		if button == "RightButton" then
			if ns.Panel then ns.Panel.Toggle() end
		else
			ns.Chat.Toggle()
		end
	end)
	b:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local a = CursorAngle(map)
			if a then Saved().angle = a; MB.Place() end
		end)
	end)
	b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	b:SetScript("OnEnter", function(self)
		if not GameTooltip then return end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("Spellmind", 0.62, 0.49, 1)
		GameTooltip:AddLine("Click: chat.", 1, 1, 1)
		GameTooltip:AddLine("Right-click: your last tab (Quests, Gear and the rest).", 1, 1, 1)
		GameTooltip:AddLine("Drag: move the button around the map.", 0.7, 0.7, 0.7)
		local waiting = ns.Nudges and ns.Nudges.Waiting() or {}
		if #waiting > 0 then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine("Waiting (click the red badge, or the Nudges tab):", 1, 0.82, 0)
			for _, t in ipairs(waiting) do GameTooltip:AddLine("  " .. t, 1, 1, 1) end
		end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	MB.button = b
	MB.Place()
	if Saved().hide then b:Hide() end
	return b
end

-- The dot: a nudge waits (Nudges.lua).
-- n: how many wait (or true/false). Shown as a red notification badge with the count.
function MB.Dot(n)
	local b = MB.button
	if not b then return end
	if not b.dot then
		-- A small button of its own: clicked, it brings the waiting nudge back (Nudges.Bring).
		-- Media\Badge: a small red disc with a dark rim and the count on it, like a typical notification
		-- badge (a gold one read as part of the icon, seen in game), over the icon's corner.
		b.dot = CreateFrame("Button", "SpellmindMinimapDot", b)
		b.dot:SetSize(13, 13)
		b.dot:SetPoint("CENTER", b, "TOPRIGHT", -6, -6)
		local level = b:GetFrameLevel()
		b.dot:SetFrameLevel((type(level) == "number" and level or 8) + 2)
		b.dot.tex = b.dot:CreateTexture(nil, "OVERLAY")
		b.dot.tex:SetAllPoints(b.dot)
		b.dot.tex:SetTexture(MB.BADGE)
		b.dot.count = b.dot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.dot.count:SetPoint("CENTER", b.dot, "CENTER", 0, 0)
		local font = b.dot.count.GetFont and b.dot.count:GetFont()
		if type(font) == "string" then b.dot.count:SetFont(font, 8, "OUTLINE") end
		b.dot.pulse = b.dot:CreateAnimationGroup()
		b.dot.pulse:SetLooping("BOUNCE")
		local fade = b.dot.pulse:CreateAnimation("Alpha")
		fade:SetFromAlpha(1)
		fade:SetToAlpha(0.7)
		fade:SetDuration(0.9)
		b.dot:SetScript("OnShow", function(self) self.pulse:Play() end)
		b.dot:SetScript("OnHide", function(self) self.pulse:Stop() end)
		b.dot:SetScript("OnClick", function() if ns.Nudges then ns.Nudges.Bring() end end)
		b.dot:SetScript("OnEnter", function(self) local s = b:GetScript("OnEnter"); if s then s(b) end end)
		b.dot:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	end
	local count = type(n) == "number" and n or (n and 1 or 0)
	b.dot.count:SetText(count > 9 and "9+" or (count > 0 and tostring(count) or ""))
	b.dot:SetShown(count > 0)
end

function MB.Show(on)
	Saved().hide = not on or nil
	local b = MB.Create()
	if b then b:SetShown(on) end
end

ns.On("PLAYER_LOGIN", function() MB.Create() end)
