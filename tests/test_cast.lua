-- Assist-or-cast spell buttons (#8).

local function text(i) return (_G["HaploBoxCast" .. i].attrs or {}).macrotext end

local function setup(me, units)
	W.header = true
	W.me = me or "Nyra"
	party(unpack(units or { "Haplo", "Elya" }))
	login({}, { leader = "Haplo", order = { "Haplo", "Elya", "Nyra" }, roles = {} })
	HB.CastCommand("add harm Frostbolt")
	HB.CastCommand("add help Flash Heal")
	advance(1)
end

local function on()
	HB.CastCommand("on")
	advance(1)
end

test("inactive by default: spells cast normally", function()
	setup()
	eq(text(1), "/cast Frostbolt", "harm normal")
	eq(text(2), "/cast [mod:shift,@player][@mouseover,help,nodead][] Flash Heal", "help normal")
	eq(HB.AssistCastOn(), false, "off by default")
end)

test("on, as a follower in the team: harm at the leader's target, help on the leader by name", function()
	setup()
	on()
	eq(text(1), "/cast [@party1target,harm,nodead] Frostbolt", "harm follows the leader's token")
	eq(text(2), "/cast [mod:shift,@player][@mouseover,help,nodead][@Haplo,help,nodead] Flash Heal", "help by name")
	eq(HaploBoxLeaderHeader.attrs.nameList, "Haplo", "header lists only the leader")
end)

test("any group change in combat disarms harm at once; help stays", function()
	setup()
	on()
	W.combat = true
	W.units = { party1 = "Elya", party2 = "Haplo" }  -- the leader's token moves
	fire("GROUP_ROSTER_UPDATE")
	eq(text(1), "", "harm disarmed by the secure header")
	eq(text(2), "/cast [mod:shift,@player][@mouseover,help,nodead][@Haplo,help,nodead] Flash Heal", "help by name unaffected")
	W.combat = false
	fire("PLAYER_REGEN_ENABLED")
	advance(1)
	eq(text(1), "/cast [@party2target,harm,nodead] Frostbolt", "re-armed after combat on the new token")
end)

test("an outsider joining in combat disarms, even with the leader's token unchanged", function()
	setup()
	on()
	W.combat = true
	W.units.party3 = "Mallory"
	fire("GROUP_ROSTER_UPDATE")
	eq(text(1), "", "disarmed")
	W.combat = false
	fire("PLAYER_REGEN_ENABLED")
	advance(1)
	eq(HB.AssistCastOn(), false, "mixed group turns it off")
	eq(text(1), "/cast Frostbolt", "normal cast")
end)

test("the leader leaving in combat disarms", function()
	setup()
	on()
	W.combat = true
	W.units = { party1 = "Elya" }
	fire("GROUP_ROSTER_UPDATE")
	eq(text(1), "", "disarmed")
end)

test("turning into a raid in combat disarms through the state driver", function()
	setup()
	on()
	W.combat = true
	W.raid = true
	fire("GROUP_ROSTER_UPDATE")
	eq(text(1), "", "disarmed although the hidden header keeps its unit")
end)

test("going solo disarms and turns it off", function()
	setup()
	on()
	W.units = {}
	fire("GROUP_ROSTER_UPDATE")
	advance(1)
	eq(HB.AssistCastOn(), false, "off")
	eq(text(1), "/cast Frostbolt", "normal")
end)

test("not on the leader, and off after every login", function()
	setup("Haplo", { "Elya", "Nyra" })
	on()
	eq(HB.AssistCastOn(), false, "leader cannot turn it on")
	eq(text(1), "/cast Frostbolt", "normal")
	setup()
	on()
	eq(HB.AssistCastOn(), true, "on")
	fire("PLAYER_LOGIN")
	advance(5)
	eq(HB.AssistCastOn(), false, "off after login")
	eq(text(1), "/cast Frostbolt", "normal after login")
end)

test("an outsider passing through in combat turns it off for good", function()
	setup()
	on()
	W.combat = true
	W.units.party3 = "Mallory"
	fire("GROUP_ROSTER_UPDATE")
	W.units.party3 = nil
	fire("GROUP_ROSTER_UPDATE")
	eq(HB.AssistCastOn(), false, "intent cleared in combat")
	W.combat = false
	fire("PLAYER_REGEN_ENABLED")
	advance(1)
	eq(text(1), "/cast Frostbolt", "not re-armed by itself")
end)

test("a raid in combat turns it off for good", function()
	setup()
	on()
	W.combat = true
	W.raid = true
	fire("GROUP_ROSTER_UPDATE")
	W.raid = false
	fire("GROUP_ROSTER_UPDATE")
	eq(HB.AssistCastOn(), false, "intent cleared")
	W.combat = false
	fire("PLAYER_REGEN_ENABLED")
	advance(1)
	eq(text(1), "/cast Frostbolt", "normal")
end)

test("without the secure header, assisted damage does nothing instead of casting at your target", function()
	W.header = false
	W.me = "Nyra"
	party("Haplo", "Elya")
	login({}, { leader = "Haplo", order = { "Haplo", "Elya", "Nyra" }, roles = {} })
	HB.CastCommand("add harm Frostbolt")
	HB.CastCommand("add help Flash Heal")
	on()
	eq(HB.AssistCastOn(), true, "on")
	eq(text(1), "", "inert")
	eq(text(2), "/cast [mod:shift,@player][@mouseover,help,nodead][@Haplo,help,nodead] Flash Heal", "heals still work")
	eq(printedMatching("not available on this client"), 1, "said")
	assert(HB.CastStateText():find("heals only"), "frame says so")
end)

test("the team frame shows the state, and slot changes wait for the end of combat", function()
	setup()
	eq(HB.CastStateText(), nil, "nothing while off")
	on()
	assert(HB.CastStateText():find("on"), "on shown")
	W.combat = true
	fire("GROUP_ROSTER_UPDATE")
	assert(HB.CastStateText():find("after combat"), "pending shown")
	HB.CastCommand("remove 1")
	eq(HB.db.castSpells[1].spell, "Frostbolt", "not removed in combat")
	eq(printedMatching("after combat"), 1, "said")
end)

test("slots keep their numbers", function()
	setup()
	HB.CastCommand("remove 1")
	advance(1)
	eq(text(1), "", "slot 1 empty")
	eq(text(2), "/cast [mod:shift,@player][@mouseover,help,nodead][] Flash Heal", "slot 2 unchanged")
	HB.CastCommand("add harm Fireball")
	advance(1)
	eq(text(1), "/cast Fireball", "first empty slot reused")
end)

test("bad spell names and bad saved records are refused", function()
	setup()
	HB.CastCommand("add harm Frost]bolt")
	HB.CastCommand("add harm " .. string.rep("x", 61))
	HB.CastCommand("add other Frostbolt")
	eq(HB.db.castSpells[3], nil, "nothing added")
	HB.db.castSpells[3] = { kind = "harm", spell = "a\n/run x" }
	HB.db.castSpells[4] = "junk"
	HB.db.castSpells.x = { kind = "harm", spell = "Fire" }
	HB.UpdateCastButtons()
	eq(HB.db.castSpells[3], nil, "bad name dropped")
	eq(HB.db.castSpells[4], nil, "bad record dropped")
	eq(HB.db.castSpells.x, nil, "bad slot dropped")
end)
