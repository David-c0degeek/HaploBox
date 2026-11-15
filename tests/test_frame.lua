-- Team frame: stale rows after a roster change in combat (F-16), the name-update
-- filter (F-11) and the unit-event error channel (M-4).

local function row(i) return _G["HaploBoxPartyRow" .. i] end

test("a roster change in combat marks moved rows stale until combat ends", function()
	party("Elya", "Nyra")
	login({}, standardTeam("Haplo"))
	eq(row(2).name, "Elya", "row 2")
	eq(row(2).attrs.unit, "party1", "row 2 unit")
	W.combat = true
	W.units = { party1 = "Nyra" }  -- Elya left: party1 is now Nyra
	fire("GROUP_ROSTER_UPDATE")
	eq(row(2).stale, true, "Elya's row is stale")
	eq(row(1).stale, nil, "the player's row is fine")
	-- periodic refreshes and unit events must not repaint it
	fire("UNIT_HEALTH", "party1")
	HB.RefreshPartyFrame()
	HB.OnStatsChanged("elya")
	HB.OnFollowStateChanged()
	eq(row(2).alpha, 0.35, "still dim")
	eq(row(2).nameText.text, "|cff999999?|r", "still ?")
	eq(row(2).attrs.unit, "party1", "secure binding untouched in combat")
	W.combat = false
	fire("PLAYER_REGEN_ENABLED")
	eq(row(2).stale, nil, "cleared after combat")
	eq(row(2).attrs.unit, nil, "Elya's row now unbound (AWAY)")
	eq(row(3).name, "Nyra", "Nyra's row")
	eq(row(3).attrs.unit, "party1", "rebound to party1 after combat")
end)

test("UNIT_NAME_UPDATE relays out only for group units", function()
	party("Elya")
	login({}, standardTeam("Haplo"))
	local n = 0
	HB.LayoutPartyFrame = function() n = n + 1 end
	fire("UNIT_NAME_UPDATE", "nameplate3")
	fire("UNIT_NAME_UPDATE", "target")
	eq(n, 0, "ignored")
	fire("UNIT_NAME_UPDATE", "party1")
	fire("UNIT_NAME_UPDATE", "raid12")
	fire("UNIT_NAME_UPDATE", "player")
	eq(n, 3, "group units relay out")
end)

test("unit-event errors show under /hb debug", function()
	party("Elya")
	login({ debug = true }, standardTeam("Haplo"))
	UnitPowerType = function() error("boom") end
	fire("UNIT_POWER_UPDATE", "party1")
	eq(printedMatching("UNIT_POWER_UPDATE:.*boom"), 1, "reported")
end)
