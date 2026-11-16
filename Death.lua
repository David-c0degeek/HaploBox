-- Team controls below Blizzard's death/resurrection dialog. Keep our own frame:
-- do not resize, reparent or replace scripts on Blizzard's shared popup frames.
local HB = HaploBox
local controls, anchor
local DEATH_POPUPS = {
	DEATH = true, SKINNED_REPOP = true,
	RESURRECT = true, RESURRECT_NO_SICKNESS = true, RESURRECT_NO_TIMER = true,
	RECOVER_CORPSE = true, RECOVER_CORPSE_INSTANCE = true,
}

function HB.RefreshDeathControls()
	if not controls then return end
	local popup
	if HB.db and HB.IAmLeader() and UnitIsDeadOrGhost("player") then
		for i = 1, STATICPOPUP_NUMDIALOGS or 4 do
			local candidate = _G["StaticPopup" .. i]
			if candidate and candidate:IsShown() and not HB.secret(candidate.which)
				and DEATH_POPUPS[candidate.which] then
				popup = candidate
				break
			end
		end
	end
	if not popup then
		controls:Hide()
		anchor = nil
		return
	end
	if anchor ~= popup then
		controls:ClearAllPoints()
		controls:SetPoint("TOP", popup, "BOTTOM", 0, -8)
		anchor = popup
	end
	controls:SetFrameStrata(popup:GetFrameStrata())
	controls:SetFrameLevel(popup:GetFrameLevel() + 1)
	controls:Show()
end

local driver = CreateFrame("Frame")
driver:RegisterEvent("PLAYER_LOGIN")
driver:SetScript("OnEvent", function()
	controls = CreateFrame("Frame", "HaploBoxDeathControls", UIParent)
	controls:SetSize(204, 21)
	controls:Hide()
	for i, entry in ipairs({
		{ "release", "Release team", "Release dead team members to the graveyard" },
		{ "resurrect", "Rezz team", "Accept available resurrections or reclaim corpses in range once the timer expires" },
	}) do
		local action, label, tooltip = unpack(entry)
		local button = CreateFrame("Button", nil, controls, "UIPanelButtonTemplate")
		button:SetSize(100, 21)
		button:SetPoint("LEFT", (i - 1) * 104, 0)
		button:SetText(label)
		button:SetScript("OnClick", function() HB.TeamDeathAction(action) end)
		button:SetScript("OnEnter", function(self)
			if not GameTooltip then return end
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(tooltip)
			GameTooltip:Show()
		end)
		button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
		controls[action] = button
	end
	-- Poll visible dialogs so reused popup slots and delayed corpse dialogs work
	-- without hooking or changing Blizzard's popup lifecycle.
	local elapsed = 0
	driver:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed < 0.1 then return end
		elapsed = 0
		HB.RefreshDeathControls()
	end)
	HB.RefreshDeathControls()
end)
