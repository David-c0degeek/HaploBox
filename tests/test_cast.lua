-- Assist-or-cast buttons (#8): /click HaploBoxAssist <spell>, /click HaploBoxHelp <spell>.
-- clickButton returns what the button would cast: "spell@unit", "spell@" for the
-- normal target, or nil for nothing.

local function assist(spell) return clickButton("HaploBoxAssist", spell) end
local function help(spell) return clickButton("HaploBoxHelp", spell) end

local function setup(me, units, db)
	W.header = true
	W.me = me or "Nyra"
	party(unpack(units or { "Haplo", "Elya" }))
	login(db or {}, { leader = "Haplo", order = { "Haplo", "Elya", "Nyra" }, roles = {} })
	advance(4)
	W.targets = { party1 = "Hogger" }   -- the leader (party1) targets an enemy
	W.hostile = { party1target = true }
end

local function on()
	HB.CastCommand("on")
	advance(1)
end

test("off by default: spells cast normally, heals on yourself with Shift", function()
	setup()
	eq(assist("Frostbolt"), "Frostbolt@", "damage at your own target")
	eq(help("Flash_Heal"), "Flash Heal@", "help on your own target, _ is a space")
	W.shift = true
	eq(help("Flash_Heal"), "Flash Heal@player", "Shift: yourself")
	eq(HB.AssistCastOn(), false, "off by default")
	eq(HaploBoxAssist.attrs.useOnKeyDown, false, "assist acts on the up click /click gives")
	eq(HaploBoxHelp.attrs.useOnKeyDown, false, "help too")
	eq(HaploBoxAssist.attrs.type, "spell", "a direct spell cast, never a macro")
end)

test("on, as a follower in the team: damage at the leader's target, help on the leader by name", function()
	setup()
	on()
	eq(assist("Frostbolt"), "Frostbolt@party1target", "the leader's target")
	eq(help("Power_Word:_Fortitude"), "Power Word: Fortitude@Haplo", "by name")
	eq(assist("Frostbolt(Rank_1)"), "Frostbolt(Rank 1)@party1target", "a rank when given; without one the game casts the highest")
	eq(HaploBoxLeaderHeader.attrs.nameList, "Haplo", "header lists only the leader")
end)

test("help: leader, then Shift for yourself, then the normal target; nothing stale leaks", function()
	setup()
	on()
	eq(help("Renew"), "Renew@Haplo", "leader")
	W.shift = true
	eq(help("Renew"), "Renew@player", "Shift")
	W.shift = false
	W.dead = { Haplo = true }
	eq(help("Renew"), "Renew@", "leader dead: the normal target, not the last unit")
	eq(HaploBoxHelp.attrs.unit, nil, "unit cleared")
end)

test("no living enemy on the leader: damage casts nothing, also right after a cast", function()
	setup()
	on()
	eq(assist("Frostbolt"), "Frostbolt@party1target", "cast")
	W.hostile = {}
	eq(assist("Frostbolt"), nil, "friendly target: nothing")
	W.hostile = { party1target = true }
	W.dead = { party1target = true }
	eq(assist("Frostbolt"), nil, "dead enemy: nothing")
	W.dead, W.targets = {}, {}
	eq(assist("Frostbolt"), nil, "no target: nothing")
	eq(HaploBoxAssist.attrs.spell, nil, "spell cleared")
end)

test("a click without a spell, or with unsafe text, casts nothing and clears the last cast", function()
	setup()
	on()
	eq(assist("Frostbolt"), "Frostbolt@party1target", "built")
	for _, bad in ipairs({ "LeftButton", "RightButton", "Button4", "a;b", "[x]", "a/run", "a|cff", "x\ny", string.rep("x", 61), "" }) do
		eq(assist(bad), nil, "refused: " .. bad)
	end
	eq(help("LeftButton"), nil, "help too")
	eq(assist("Éclair_de_givre"), "Éclair de givre@party1target", "localized names are read as typed")
end)

test("any group change in combat disarms damage at once, also a cast already built; help stays", function()
	setup()
	on()
	assist("Frostbolt")
	W.combat = true
	W.units = { party1 = "Elya", party2 = "Haplo" }  -- the leader's token moves
	fire("GROUP_ROSTER_UPDATE")
	eq(HaploBoxAssist.attrs.type, nil, "built cast emptied")
	eq(assist("Frostbolt"), nil, "disarmed by the secure header")
	eq(help("Flash_Heal"), "Flash Heal@Haplo", "help by name unaffected")
	W.combat = false
	fire("PLAYER_REGEN_ENABLED")
	advance(1)
	W.targets, W.hostile = { party2 = "Hogger" }, { party2target = true }
	eq(assist("Frostbolt"), "Frostbolt@party2target", "re-armed after combat on the new token")
end)

test("an outsider pauses it: disarmed in combat, plain casts after, back by itself when it leaves", function()
	setup()
	on()
	W.combat = true
	W.units.party3 = "Mallory"
	fire("GROUP_ROSTER_UPDATE")
	eq(assist("Frostbolt"), nil, "disarmed")
	eq(assist("Frostbolt"), nil, "still inert on the next click")
	eq(HB.AssistCastOn(), true, "intent kept")
	W.combat = false
	fire("PLAYER_REGEN_ENABLED")
	advance(1)
	eq(assist("Frostbolt"), "Frostbolt@", "outsider still there: plain cast, never the leader's target")
	eq(help("Renew"), "Renew@", "help plain too")
	assert(HB.CastStateText():find("paused"), "frame says paused")
	fire("GROUP_ROSTER_UPDATE")
	advance(1)
	eq(printedMatching("assisted casting paused: someone outside the team"), 1, "said once per visit")
	W.units.party3 = nil
	fire("GROUP_ROSTER_UPDATE")
	advance(1)
	eq(assist("Frostbolt"), "Frostbolt@party1target", "back without /hb cast on")
	eq(help("Renew"), "Renew@Haplo", "help on the leader again")
	assert(not HB.CastStateText():find("paused"), "no longer paused")
	W.units.party3 = "Mallory"
	fire("GROUP_ROSTER_UPDATE")
	advance(1)
	eq(printedMatching("assisted casting paused"), 2, "a new visit says it again")
end)

test("turned off while paused stays off; nothing said when it is already off", function()
	setup()
	on()
	W.units.party3 = "Mallory"
	fire("GROUP_ROSTER_UPDATE")
	advance(1)
	HB.CastCommand("off")
	W.units.party3 = nil
	fire("GROUP_ROSTER_UPDATE")
	advance(1)
	eq(HB.AssistCastOn(), false, "stays off")
	eq(assist("Frostbolt"), "Frostbolt@", "plain")
	setup()
	W.units.party3 = "Mallory"
	fire("GROUP_ROSTER_UPDATE")
	advance(1)
	eq(printedMatching("paused"), 0, "off: no pause message")
end)

test("the leader leaving, or a raid, in combat disarms", function()
	setup()
	on()
	W.combat = true
	W.units = { party1 = "Elya" }
	fire("GROUP_ROSTER_UPDATE")
	eq(assist("Frostbolt"), nil, "leader gone")
	setup()
	on()
	W.combat = true
	W.raid = true
	fire("GROUP_ROSTER_UPDATE")
	eq(assist("Frostbolt"), nil, "raid: disarmed although the hidden header keeps its unit")
end)

test("solo it casts normally and comes back in the team", function()
	setup()
	on()
	W.units = {}
	fire("GROUP_ROSTER_UPDATE")
	advance(1)
	eq(HB.AssistCastOn(), true, "still on")
	eq(assist("Frostbolt"), "Frostbolt@", "solo: normal")
	eq(help("Renew"), "Renew@", "solo help: normal")
	W.units = { party1 = "Haplo", party2 = "Elya" }
	fire("GROUP_ROSTER_UPDATE")
	advance(1)
	eq(assist("Frostbolt"), "Frostbolt@party1target", "back in the team")
end)

test("not on the leader; the choice is kept after logging in again", function()
	setup("Haplo", { "Elya", "Nyra" })
	on()
	eq(assist("Frostbolt"), "Frostbolt@", "the leader casts normally")
	setup()
	on()
	local db = HB.db
	setup(nil, nil, db)   -- a reload into the same team
	eq(HB.AssistCastOn(), true, "kept")
	eq(assist("Frostbolt"), "Frostbolt@party1target", "active after the reload")
end)

test("without the secure header, assisted damage does nothing instead of casting at your target", function()
	W.header = false
	W.me = "Nyra"
	party("Haplo", "Elya")
	login({}, { leader = "Haplo", order = { "Haplo", "Elya", "Nyra" }, roles = {} })
	advance(4)
	W.targets, W.hostile = { party1 = "Hogger" }, { party1target = true }
	eq(assist("Frostbolt"), "Frostbolt@", "off: normal")
	on()
	eq(HB.AssistCastOn(), true, "on")
	eq(assist("Frostbolt"), nil, "inert")
	eq(help("Flash_Heal"), "Flash Heal@Haplo", "heals still work")
	assert(HB.CastStateText():find("heals only"), "frame says so")
end)

test("without wrapped clicks both buttons do nothing, and that is said once", function()
	SecureHandlerWrapScript = nil
	setup()
	on()
	eq(assist("Frostbolt"), nil, "assist inert")
	eq(help("Renew"), nil, "help inert")
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
