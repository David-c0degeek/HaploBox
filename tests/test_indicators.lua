-- Incoming heals (#11), cast bars and the five-second mana rule (#13) on the rows.

local function rowFor(unit)
	for i = 1, 10 do
		local r = _G["HaploBoxPartyRow" .. i]
		if r and r.unit == unit then return r end
	end
	error("no row for " .. unit)
end

local function setup()
	party("Elya", "Nyra")
	login({}, standardTeam("Haplo"))
	return rowFor("party1")
end

-- ---------------------------------------------------------------- incoming heals
test("incoming heals extend the health bar, capped at full health", function()
	local r = setup()
	W.incoming = { party1 = 30 }
	fire("UNIT_HEAL_PREDICTION", "party1")
	eq(r.incoming.shown, true, "shown")
	eq(r.incoming.value, 80, "health 50 + 30")
	eq(r.health.back.alpha, 0, "the prediction bar carries the background")
	W.incoming.party1 = 90
	fire("UNIT_HEAL_PREDICTION", "party1")
	eq(r.incoming.value, 100, "capped")
	W.incoming.party1 = 0
	fire("UNIT_HEAL_PREDICTION", "party1")
	eq(r.incoming.shown, false, "nothing incoming")
	eq(r.health.back.alpha, 1, "normal background back")
end)

test("secret or missing prediction data shows nothing", function()
	local r = setup()
	W.incoming = { party1 = 31 }
	W.secrets = { [31] = true }
	fire("UNIT_HEAL_PREDICTION", "party1")
	eq(r.incoming.shown, false, "secret incoming value")
	W.secrets = { [50] = true }
	W.incoming.party1 = 30
	fire("UNIT_HEALTH", "party1")
	eq(r.incoming.shown, false, "secret health value")
	W.secrets = nil
	local api = UnitGetIncomingHeals
	UnitGetIncomingHeals = nil
	fire("UNIT_HEAL_PREDICTION", "party1")
	eq(r.incoming.shown, false, "client without the API")
	UnitGetIncomingHeals = api
end)

test("restricted alive or online state shows no prediction", function()
	local r = setup()
	W.incoming = { party1 = 30 }
	local dead, online = UnitIsDeadOrGhost, UnitIsConnected
	local hidden = {}
	W.secrets = { [hidden] = true }
	UnitIsDeadOrGhost = function() return hidden end
	fire("UNIT_HEAL_PREDICTION", "party1")
	eq(r.incoming.shown, false, "restricted dead state")
	UnitIsDeadOrGhost = dead
	UnitIsConnected = function() return hidden end
	fire("UNIT_HEAL_PREDICTION", "party1")
	eq(r.incoming.shown, false, "restricted online state")
	UnitIsConnected = online
	W.secrets = nil
end)

test("a member removed from the team and added back starts with fresh readings", function()
	local r = setup()
	local nyra = rowFor("party2")
	local now = W.now * 1000
	W.mana = { party2 = 100 }
	fire("UNIT_POWER_FREQUENT", "party2", "MANA")
	W.casts = { party2 = { "Heal", now, now + 3000 } }
	fire("UNIT_SPELLCAST_START", "party2")
	-- Nyra leaves the team and the group: her row goes
	HaploBoxTeam.order = { "Haplo", "Elya" }
	HaploBoxTeam.roles.Nyra = nil
	W.units.party2 = nil
	HB.LayoutPartyFrame()
	eq(nyra.shown, false, "row hidden")
	eq(nyra.cast.scripts.OnUpdate, nil, "cast updates stopped on removal")
	eq(nyra.cast.shown, false, "cast hidden")
	W.casts = nil
	-- she comes back with less mana; no event saw it go down
	W.mana.party2 = 20
	W.units.party2 = "Nyra"
	HaploBoxTeam.order = { "Haplo", "Elya", "Nyra" }
	HB.LayoutPartyFrame()
	eq(rowFor("party2").fsr.shown, false, "not after the layout")
	W.mana.party2 = 25
	fire("UNIT_POWER_FREQUENT", "party2", "MANA")
	eq(rowFor("party2").fsr.shown, false, "the old reading is not compared")
end)

test("a full refresh never starts the mana timer from an old reading", function()
	local r = setup()
	W.mana = { party1 = 100 }
	fire("UNIT_POWER_FREQUENT", "party1", "MANA")
	W.mana.party1 = 20  -- changed while no event reached the row
	HB.RefreshPartyFrame()
	eq(r.fsr.shown, false, "refresh only takes a reading")
	W.mana.party1 = 10
	fire("UNIT_POWER_FREQUENT", "party1", "MANA")
	eq(r.fsr.shown, true, "the next drop counts")
end)

test("predictions clear on death, and the setting turns them off", function()
	local r = setup()
	W.incoming = { party1 = 30 }
	fire("UNIT_HEAL_PREDICTION", "party1")
	local dead = UnitIsDeadOrGhost
	UnitIsDeadOrGhost = function(u) return u == "party1" end
	fire("UNIT_HEALTH", "party1")
	eq(r.incoming.shown, false, "dead")
	UnitIsDeadOrGhost = dead
	HB.SetOption("teamHealPrediction", false)
	fire("UNIT_HEAL_PREDICTION", "party1")
	eq(r.incoming.shown, false, "off")
end)

-- ---------------------------------------------------------------- cast bar
test("a cast fills the bar and disappears when it ends", function()
	local r = setup()
	local now = W.now * 1000
	W.casts = { party1 = { "Frostbolt", now, now + 2000 } }
	fire("UNIT_SPELLCAST_START", "party1")
	eq(r.cast.shown, true, "shown")
	advance(1)
	r.cast.scripts.OnUpdate(r.cast)
	assert(math.abs(r.cast.value - 0.5) < 0.01, "half way: " .. tostring(r.cast.value))
	W.casts.party1 = nil
	fire("UNIT_SPELLCAST_STOP", "party1")
	eq(r.cast.shown, false, "stopped")
	eq(r.cast.scripts.OnUpdate, nil, "no more updates")
end)

test("a channel drains, and an interrupted or expired cast leaves nothing behind", function()
	local r = setup()
	local now = W.now * 1000
	W.channels = { party1 = { "Arcane Missiles", now, now + 4000 } }
	fire("UNIT_SPELLCAST_CHANNEL_START", "party1")
	advance(1)
	r.cast.scripts.OnUpdate(r.cast)
	assert(math.abs(r.cast.value - 0.75) < 0.01, "drains: " .. tostring(r.cast.value))
	W.channels.party1 = nil
	fire("UNIT_SPELLCAST_INTERRUPTED", "party1")
	eq(r.cast.shown, false, "interrupted")
	W.casts = { party1 = { "Heal", now, now + 2500 } }
	fire("UNIT_SPELLCAST_START", "party1")
	advance(5)  -- no STOP event arrives
	r.cast.scripts.OnUpdate(r.cast)
	eq(r.cast.shown, false, "past its end")
end)

test("secret cast timing shows no bar", function()
	local r = setup()
	W.casts = { party1 = { "Frostbolt", 1234567, 1236567 } }
	W.secrets = { [1236567] = true }
	fire("UNIT_SPELLCAST_START", "party1")
	eq(r.cast.shown, false, "unknown timing stays unknown")
end)

-- ---------------------------------------------------------------- five-second rule
test("spending mana starts the five-second timer; regeneration does not", function()
	local r = setup()
	W.mana = { party1 = 100 }
	fire("UNIT_POWER_FREQUENT", "party1", "MANA")
	eq(r.fsr.shown, false, "first reading only")
	W.mana.party1 = 120
	fire("UNIT_POWER_FREQUENT", "party1", "MANA")
	eq(r.fsr.shown, false, "regeneration")
	W.mana.party1 = 90
	fire("UNIT_POWER_FREQUENT", "party1", "MANA")
	eq(r.fsr.shown, true, "mana went down")
	advance(2.5)
	r.fsr.scripts.OnUpdate(r.fsr)
	assert(math.abs(r.fsr.value - 0.5) < 0.01, "half the time left")
	advance(3)
	r.fsr.scripts.OnUpdate(r.fsr)
	eq(r.fsr.shown, false, "over after five seconds")
end)

test("a free cast, a rage user and other clients show no mana timer", function()
	local r = setup()
	W.mana = { party1 = 100 }
	fire("UNIT_POWER_FREQUENT", "party1", "MANA")
	fire("UNIT_SPELLCAST_START", "party1")  -- a free spell: mana unchanged
	fire("UNIT_POWER_FREQUENT", "party1", "MANA")
	eq(r.fsr.shown, false, "free cast")
	W.rage = { party1 = true }
	W.mana.party1 = 50
	fire("UNIT_POWER_FREQUENT", "party1", "MANA")
	eq(r.fsr.shown, false, "not a mana user")
	W.rage = nil
	WOW_PROJECT_ID = WOW_PROJECT_MAINLINE
	fire("UNIT_POWER_FREQUENT", "party1", "MANA")
	W.mana.party1 = 10
	fire("UNIT_POWER_FREQUENT", "party1", "MANA")
	eq(r.fsr.shown, false, "retail has no five-second rule")
	WOW_PROJECT_ID = nil
	fire("UNIT_POWER_FREQUENT", "party1", "MANA")
	W.mana.party1 = 5
	fire("UNIT_POWER_FREQUENT", "party1", "MANA")
	eq(r.fsr.shown, false, "an unknown client stays unknown")
	WOW_PROJECT_ID = WOW_PROJECT_CLASSIC
end)

test("secret mana readings are not compared", function()
	local r = setup()
	W.mana = { party1 = 100 }
	fire("UNIT_POWER_FREQUENT", "party1", "MANA")
	W.mana.party1 = 51
	W.secrets = { [51] = true }
	fire("UNIT_POWER_FREQUENT", "party1", "MANA")
	eq(r.fsr.shown, false, "no timer from a secret value")
	W.secrets = nil
	W.mana.party1 = 40
	fire("UNIT_POWER_FREQUENT", "party1", "MANA")
	eq(r.fsr.shown, false, "the secret reading reset the comparison")
end)

test("a row that now shows someone else starts over", function()
	local r = setup()
	W.mana = { party1 = 100 }
	fire("UNIT_POWER_FREQUENT", "party1", "MANA")
	W.units.party1, W.units.party2 = "Nyra", "Elya"  -- the group order changed
	W.mana = { party1 = 20, party2 = 100 }
	fire("GROUP_ROSTER_UPDATE")
	local nyra = rowFor("party1")
	fire("UNIT_POWER_FREQUENT", "party1", "MANA")
	eq(nyra.fsr.shown, false, "Elya's old reading is not compared with Nyra's mana")
end)

-- ---------------------------------------------------------------- stale rows
test("a stale row in combat drops every indicator at once", function()
	local r = setup()
	local now = W.now * 1000
	W.incoming = { party1 = 30 }
	W.casts = { party1 = { "Frostbolt", now, now + 2000 } }
	W.mana = { party1 = 100 }
	fire("UNIT_HEAL_PREDICTION", "party1")
	fire("UNIT_SPELLCAST_START", "party1")
	fire("UNIT_POWER_FREQUENT", "party1", "MANA")
	W.mana.party1 = 50
	fire("UNIT_POWER_FREQUENT", "party1", "MANA")
	W.combat = true
	W.units.party1 = "Mallory"  -- someone else took the token in combat
	fire("GROUP_ROSTER_UPDATE")
	eq(r.stale, true, "row is stale")
	eq(r.incoming.shown, false, "prediction gone")
	eq(r.cast.shown, false, "cast gone")
	eq(r.cast.scripts.OnUpdate, nil, "cast updates stopped")
	eq(r.fsr.shown, false, "mana timer gone")
	eq(r.fsr.scripts.OnUpdate, nil, "timer updates stopped")
	fire("UNIT_HEAL_PREDICTION", "party1")
	eq(r.incoming.shown, false, "no updates for a stale row")
	W.combat = false
end)
