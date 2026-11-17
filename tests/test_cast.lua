-- Assist-or-cast buttons (#8): /click HaploBoxAssist <spell>, /click HaploBoxHelp <spell>.

local function assist(spell) return clickButton("HaploBoxAssist", spell) end
local function help(spell) return clickButton("HaploBoxHelp", spell) end

local function setup(me, units, db)
	W.header = true
	W.me = me or "Nyra"
	party(unpack(units or { "Haplo", "Elya" }))
	login(db or {}, { leader = "Haplo", order = { "Haplo", "Elya", "Nyra" }, roles = {} })
	advance(4)
end

local function on()
	HB.CastCommand("on")
	advance(1)
end

test("off by default: spells cast normally, heals on yourself with Shift", function()
	setup()
	eq(assist("Frostbolt"), "/cast Frostbolt", "damage normal")
	eq(help("Flash_Heal"), "/cast [mod:shift,@player][] Flash Heal", "help normal, _ is a space")
	eq(HB.AssistCastOn(), false, "off by default")
	eq(HaploBoxAssist.attrs.useOnKeyDown, false, "assist acts on the up click /click gives")
	eq(HaploBoxHelp.attrs.useOnKeyDown, false, "help too")
end)

test("on, as a follower in the team: damage at the leader's target, help on the leader by name", function()
	setup()
	on()
	eq(assist("Frostbolt"), "/cast [@party1target,harm,nodead] Frostbolt", "the leader's token")
	eq(help("Power_Word:_Fortitude"), "/cast [mod:shift,@player][@Haplo,help,nodead][] Power Word: Fortitude", "by name")
	eq(HaploBoxLeaderHeader.attrs.nameList, "Haplo", "header lists only the leader")
end)

test("no mouseover anywhere", function()
	setup()
	assert(not help("Renew"):find("mouseover"), "off")
	on()
	assert(not help("Renew"):find("mouseover"), "on")
	assert(not assist("Frostbolt"):find("mouseover"), "damage")
end)

test("a click without a spell, or with unsafe text, casts nothing and clears the last text", function()
	setup()
	on()
	eq(assist("Frostbolt"), "/cast [@party1target,harm,nodead] Frostbolt", "built")
	for _, bad in ipairs({ "LeftButton", "RightButton", "Button4", "a;b", "[x]", "a/run", "a|cff", "x\ny", string.rep("x", 61), "" }) do
		eq(assist(bad), "", "refused: " .. bad)
	end
	eq(help("LeftButton"), "", "help too")
	eq(assist("Éclair_de_givre"), "/cast [@party1target,harm,nodead] Éclair de givre", "localized names are read as typed")
	eq(assist("Frostbolt(Rank_1)"), "/cast [@party1target,harm,nodead] Frostbolt(Rank 1)", "ranks")
end)

test("any group change in combat disarms damage at once, also text already built; help stays", function()
	setup()
	on()
	assist("Frostbolt")
	W.combat = true
	W.units = { party1 = "Elya", party2 = "Haplo" }  -- the leader's token moves
	fire("GROUP_ROSTER_UPDATE")
	eq(HaploBoxAssist.attrs.macrotext, "", "built text emptied")
	eq(assist("Frostbolt"), "", "disarmed by the secure header")
	eq(help("Flash_Heal"), "/cast [mod:shift,@player][@Haplo,help,nodead][] Flash Heal", "help by name unaffected")
	W.combat = false
	fire("PLAYER_REGEN_ENABLED")
	advance(1)
	eq(assist("Frostbolt"), "/cast [@party2target,harm,nodead] Frostbolt", "re-armed after combat on the new token")
end)

test("an outsider joining disarms in combat and turns it off for good", function()
	setup()
	on()
	W.combat = true
	W.units.party3 = "Mallory"
	fire("GROUP_ROSTER_UPDATE")
	eq(assist("Frostbolt"), "", "disarmed")
	eq(HB.AssistCastOn(), false, "intent cleared at once")
	W.units.party3 = nil
	fire("GROUP_ROSTER_UPDATE")
	W.combat = false
	fire("PLAYER_REGEN_ENABLED")
	advance(1)
	eq(HB.AssistCastOn(), false, "stays off")
	eq(assist("Frostbolt"), "/cast Frostbolt", "normal cast")
	eq(printedMatching("turned off: someone outside the team"), 1, "said")
end)

test("the leader leaving, or a raid, in combat disarms", function()
	setup()
	on()
	W.combat = true
	W.units = { party1 = "Elya" }
	fire("GROUP_ROSTER_UPDATE")
	eq(assist("Frostbolt"), "", "leader gone")
	setup()
	on()
	W.combat = true
	W.raid = true
	fire("GROUP_ROSTER_UPDATE")
	eq(assist("Frostbolt"), "", "raid: disarmed although the hidden header keeps its unit")
end)

test("solo or in a raid it casts normally and comes back in the team", function()
	setup()
	on()
	W.units = {}
	fire("GROUP_ROSTER_UPDATE")
	advance(1)
	eq(HB.AssistCastOn(), true, "still on")
	eq(assist("Frostbolt"), "/cast Frostbolt", "solo: normal")
	eq(help("Renew"), "/cast [mod:shift,@player][] Renew", "solo help: normal")
	W.units = { party1 = "Haplo", party2 = "Elya" }
	fire("GROUP_ROSTER_UPDATE")
	advance(1)
	eq(assist("Frostbolt"), "/cast [@party1target,harm,nodead] Frostbolt", "back in the team")
end)

test("not on the leader; the choice is kept after logging in again", function()
	setup("Haplo", { "Elya", "Nyra" })
	on()
	eq(assist("Frostbolt"), "/cast Frostbolt", "the leader casts normally")
	setup()
	on()
	local db = HB.db
	setup(nil, nil, db)   -- a reload into the same team
	eq(HB.AssistCastOn(), true, "kept")
	eq(assist("Frostbolt"), "/cast [@party1target,harm,nodead] Frostbolt", "active after the reload")
end)

test("without the secure header, assisted damage does nothing instead of casting at your target", function()
	W.header = false
	W.me = "Nyra"
	party("Haplo", "Elya")
	login({}, { leader = "Haplo", order = { "Haplo", "Elya", "Nyra" }, roles = {} })
	advance(4)
	eq(assist("Frostbolt"), "/cast Frostbolt", "off: normal")
	on()
	eq(HB.AssistCastOn(), true, "on")
	eq(assist("Frostbolt"), "", "inert")
	eq(help("Flash_Heal"), "/cast [mod:shift,@player][@Haplo,help,nodead][] Flash Heal", "heals still work")
	assert(HB.CastStateText():find("heals only"), "frame says so")
end)

test("without wrapped clicks both buttons do nothing, and that is said once", function()
	SecureHandlerWrapScript = nil
	setup()
	on()
	eq(assist("Frostbolt"), "", "assist inert")
	eq(help("Renew"), "", "help inert")
	HB.UpdateCastButtons()
	HB.UpdateCastButtons()
	eq(printedMatching("not available on this client"), 0, "said once, at login, not again")
end)

test("the team frame shows the state; changes wait for the end of combat", function()
	setup()
	eq(HB.CastStateText(), nil, "nothing while off")
	on()
	assert(HB.CastStateText():find("on"), "on shown")
	W.combat = true
	fire("GROUP_ROSTER_UPDATE")
	assert(HB.CastStateText():find("after combat"), "pending shown")
	HB.CastCommand("")
	eq(printedMatching("/click HaploBoxAssist Frostbolt"), 1, "examples shown")
end)
