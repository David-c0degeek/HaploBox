-- Settings window (#6) and the team frame quick settings (#9): one list of settings,
-- one setter, the same values everywhere.

local INTERNAL = {}  -- saved keys that are not settings (none today; position and size are dragged)

test("every saved setting appears exactly once in the settings window", function()
	login({}, standardTeam("Haplo"))
	local seen = {}
	for _, sec in ipairs(HB.SETTINGS) do
		for _, it in ipairs(sec.items or {}) do
			if it[2] ~= "action" then seen[it[1]] = (seen[it[1]] or 0) + 1 end
		end
		for _, snd in ipairs(sec.sounds or {}) do seen["sound:" .. snd[1]] = (seen["sound:" .. snd[1]] or 0) + 1 end
	end
	for key, default in pairs(HB.DEFAULTS) do
		if key == "sounds" then
			for s in pairs(default) do eq(seen["sound:" .. s], 1, "sound " .. s) end
		elseif key:match("^node") and not HB.NODES_ON then
			eq(seen[key], nil, "nodes module off: " .. key .. " hidden")
		elseif not INTERNAL[key] then
			eq(seen[key], 1, "setting " .. key)
		end
	end
	for key in pairs(seen) do
		assert(key:match("^sound:") or HB.DEFAULTS[key] ~= nil, "unknown setting in the window: " .. key)
	end
end)

test("SetOption checks values and keeps scale finite and in range", function()
	login({}, standardTeam("Haplo"))
	eq(HB.SetOption("teamFrame", "sometimes"), nil, "unknown choice refused")
	eq(HB.db.teamFrame, "auto", "unchanged")
	eq(HB.SetOption("partyScale", "abc"), nil, "text refused")
	eq(HB.SetOption("partyScale", 0 / 0), nil, "NaN refused")
	eq(HB.SetOption("partyScale", math.huge), nil, "infinity refused")
	eq(HB.SetOption("partyScale", 5), 2, "clamped high")
	eq(HB.SetOption("partyScale", 0.1), 0.5, "clamped low")
	eq(HB.SetOption("partyScale", 1.1000001), 1.1, "rounded")
	eq(HB.SetOption("teamShowXP", nil), false, "booleans")
	eq(HB.SetOption("nonsense", true), nil, "unknown key")
	eq(HB.SetOption("sounds", {}), nil, "the sounds table is not a setting")
	SlashCmdList.HAPLOBOX("frame scale nan")
	eq(HB.db.partyScale, 1.1, "slash command cannot set NaN")
end)

test("turning free-for-all loot back on looks at the group again", function()
	party("Elya", "Nyra")
	W.loot = 3
	login({ autoFFA = false }, standardTeam("Haplo"))
	fire("GROUP_ROSTER_UPDATE")
	advance(3)
	eq(W.loot, 3, "off: left alone")
	HB.SetOption("autoFFA", true)
	advance(3)
	eq(W.loot, 0, "on: free for all for the team")
end)

test("quick settings open from the gear and the TEAM line, and change the same settings", function()
	party("Elya", "Nyra")
	login({}, standardTeam("Haplo"))
	local frame = HaploBoxPartyFrame
	frame.gearButton.scripts.OnClick(frame.gearButton)
	local quick = HB.QuickSettingsFrame()
	assert(quick and quick:IsShown(), "opened from the gear")
	local xp = quick.controls.teamShowXP
	eq(xp.checked, true, "shows the current value")
	xp:SetChecked(false)
	xp.scripts.OnClick(xp)
	eq(HB.db.teamShowXP, false, "saved through the shared setter")
	frame.gearButton.scripts.OnClick(frame.gearButton)
	eq(quick:IsShown(), false, "the same gear closes it")
	frame.footer.scripts.OnMouseUp(frame.footer, "LeftButton")
	eq(quick:IsShown(), false, "left click on TEAM does nothing")
	frame.footer.scripts.OnMouseUp(frame.footer, "RightButton")
	eq(quick:IsShown(), true, "right click on TEAM opens it")
	SlashCmdList.HAPLOBOX("frame xp")
	eq(xp.checked, true, "a slash command refreshes the open popup")
	quick.full.scripts.OnClick(quick.full)
	eq(quick:IsShown(), false, "Open full settings closes the popup")
end)

test("locked frames keep a gear to reach the quick settings", function()
	party("Elya", "Nyra")
	login({ teamLocked = true, teamShowGold = false, teamShowBags = false }, standardTeam("Haplo"))
	local frame = HaploBoxPartyFrame
	eq(frame.handle.shown, false, "bar hidden while locked")
	eq(frame.footer.shown, false, "TEAM line hidden without gold and bags")
	eq(frame.gearTab.shown, true, "gear still there")
end)

test("locking in combat waits for the end of combat", function()
	party("Elya", "Nyra")
	login({}, standardTeam("Haplo"))
	local frame = HaploBoxPartyFrame
	eq(frame.handle.shown, true, "unlocked")
	W.combat = true
	HB.ToggleQuickSettings()
	local lock = HB.QuickSettingsFrame().controls.teamLocked
	lock:SetChecked(true)
	lock.scripts.OnClick(lock)
	eq(HB.db.teamLocked, true, "saved")
	eq(frame.handle.shown, true, "frame untouched in combat")
	assert(HB.QuickSettingsFrame().deferred.text:find("after combat"), "popup says it waits")
	W.combat = false
	fire("PLAYER_REGEN_ENABLED")
	eq(frame.handle.shown, false, "applied after combat")
	eq(HB.QuickSettingsFrame().deferred.text, "", "the open popup drops the combat note")
	W.combat = true
	fire("PLAYER_REGEN_DISABLED")
	assert(HB.QuickSettingsFrame().deferred.text:find("after combat"), "and shows it again in combat")
end)
