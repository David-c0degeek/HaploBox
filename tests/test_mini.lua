-- Mini Heal view (#10): a local layout of the same secure rows.

local function rowFor(unit)
	for i = 1, 10 do
		local r = _G["HaploBoxPartyRow" .. i]
		if r and r.unit == unit then return r end
	end
	error("no row for " .. unit)
end

local function setup(db)
	party("Elya", "Nyra")
	login(db or {}, standardTeam("Haplo"))
	return rowFor("party1")
end

test("Mini Heal hides everything but the health tile, and main brings it back", function()
	local r = setup()
	eq(r.power.shown, true, "main: power bar shown")
	HB.SetOption("teamView", "mini")
	eq(HB.AppliedView(), "mini", "applied out of combat")
	eq(r.power.shown, false, "power hidden")
	eq(r.rested.shown, false, "XP hidden")
	eq(r.box.shown, false, "follow box hidden")
	eq(r.focusText.shown, false, "focus hidden")
	eq(r.moneyText.shown, false, "gold hidden")
	eq(HaploBoxPartyFrame.footer.shown, false, "TEAM line hidden")
	eq(r.attrs.unit, "party1", "the tile targets the same unit")
	HB.SetOption("teamView", "main")
	eq(r.power.shown, true, "power back")
	eq(r.box.shown, true, "follow box back")
	eq(r.focusText.shown, true, "focus back")
	eq(r.health.point[1], "TOPLEFT", "health anchored")
	eq(r.health.point[3], -19, "main anchor restored")
end)

test("updates in Mini Heal do not bring hidden parts back", function()
	local r = setup({ teamView = "mini" })
	W.auras = { party1 = { HELPFUL = {
		{ name = "Fort", icon = 1, duration = 3600, expirationTime = W.now + 3000, sourceUnit = "player" },
	} } }
	fire("UNIT_AURA", "party1")
	fire("UNIT_HEALTH", "party1")
	fire("UNIT_POWER_UPDATE", "party1")
	HB.RefreshPartyFrame()
	eq(r.power.shown, false, "power still hidden")
	for _, b in ipairs(r.buffs) do eq(b.shown, false, "no buff strip") end
	W.mana = { party1 = 100 }
	fire("UNIT_POWER_FREQUENT", "party1", "MANA")
	W.mana.party1 = 50
	fire("UNIT_POWER_FREQUENT", "party1", "MANA")
	eq(r.fsr.shown, false, "no mana timer on a hidden mana bar")
end)

test("a view change in combat waits, and the rows keep their layout until then", function()
	local r = setup()
	W.combat = true
	HB.ToggleView()
	eq(HB.db.teamView, "mini", "asked for")
	eq(HB.AppliedView(), "main", "not applied in combat")
	eq(printedMatching("after combat"), 1, "says so")
	fire("UNIT_AURA", "party1")
	HB.RefreshPartyFrame()
	eq(r.power.shown, true, "main layout untouched in combat")
	W.combat = false
	fire("PLAYER_REGEN_ENABLED")
	eq(HB.AppliedView(), "mini", "applied after combat")
	eq(r.power.shown, false, "now mini")
end)

test("each view keeps its own size, and bad saved sizes fall back", function()
	setup({ teamW = 300, teamMiniW = 120, teamMiniH = 0 / 0 })
	HB.SetOption("teamView", "mini")
	local r = rowFor("party1")
	eq(r.bg.width, 120, "mini width")
	eq(r.bg.height, 40, "NaN height falls back to 40")
	HB.SetOption("teamView", "main")
	eq(r.bg.width, 300, "main width kept")
	HB.ResetPartyPosition()
	eq(HB.db.teamMiniW, nil, "reset clears the mini size too")
end)

test("Mini Heal at its smallest keeps the bar buttons and buff text inside the frame", function()
	local r = setup({ teamMiniW = 90 })
	HB.SetOption("teamRequiredBuffs", "Arcane Intellect")
	HB.SetOption("teamView", "mini")
	local frame = HaploBoxPartyFrame
	eq(frame.sendButton.shown, false, "no Send team in Mini Heal")
	eq(frame.dragHint.shown, false, "no hint")
	eq(frame.gearButton.width + 4 + 44 + 2 <= 90, true, "gear and Lock fit 90 px")
	eq(r.requiredShort, true, "short required-buff text")
	W.auras = { party1 = { HELPFUL = {} } }
	fire("UNIT_AURA", "party1")
	assert(r.required.text:find("%-1"), "count only: " .. tostring(r.required.text))
	HB.SetOption("teamView", "main")
	eq(frame.sendButton.shown, true, "Send team back")
	eq(r.requiredShort, false, "full text on the main bar")
end)

test("rows are registered for Clique in both views", function()
	setup({ teamView = "mini" })
	eq(ClickCastFrames[HaploBoxPartyRow1], true, "row registered")
end)

test("the view is local: switching sends nothing", function()
	setup()
	W.sent = {}
	HB.ToggleView()
	advance(2)
	eq(#W.sent, 0, "no addon message")
end)
