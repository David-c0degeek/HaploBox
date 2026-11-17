-- Incoming heals announced by the team's own healers (clients without UnitGetIncomingHeals).

local guidN = 0
local function cast(spellID, target, castMs)
	guidN = guidN + 1
	local guid = "Cast-" .. guidN
	fire("UNIT_SPELLCAST_SENT", "player", target, guid, spellID)
	W.casts = { player = { "Heal", W.now * 1000, W.now * 1000 + (castMs or 2500) } }
	fire("UNIT_SPELLCAST_START", "player", guid, spellID)
	return guid
end

local function land(guid, spellID, amount, crit, name)
	W.casts = {}
	fire("UNIT_SPELLCAST_SUCCEEDED", "player", guid, spellID)
	fire("UNIT_SPELLCAST_STOP", "player", guid, spellID)
	W.clog = { 0, "SPELL_HEAL", false, UnitGUID("player"), W.me, 0, 0, "Player-X", "X", 0, 0, 0,
		name or "Heal", 2, amount, 0, 0, crit or false }
	fire("COMBAT_LOG_EVENT_UNFILTERED")
end

local function learn(spellID, amount)
	land(cast(spellID, "Nyra"), spellID, amount)
end

local function asElya(...)
	UnitGetIncomingHeals = nil
	W.me = "Elya"
	party(...)
	login({}, standardTeam("Haplo"))
end

local function starts(channel) return sentMatching("^I|%d+|[^-]", channel) end
local function stops(channel) return sentMatching("^I|%d+|%-$", channel) end

test("a learned heal is announced to the team when the cast starts, and stopped when it lands", function()
	asElya("Haplo", "Nyra")
	learn(6064, 800)
	W.sent = {}
	local g = cast(6064, "Haplo", 2500)
	advance(0.1)
	local s = starts("PARTY")
	eq(#s, 1, "start sent")
	assert(s[1].msg:find("^I|%d+|Haplo|800|2500$"), s[1].msg)
	land(g, 6064, 810)
	advance(0.1)
	eq(#stops("PARTY"), 1, "stop sent")
end)

test("sizes are per rank, without crits, as a moving average", function()
	asElya("Haplo", "Nyra")
	learn(6064, 1000)
	learn(2054, 300)
	land(cast(6064, "Nyra"), 6064, 2000, true)  -- a crit does not count
	eq(HB.db.healSizes[6064], 1000, "rank 4")
	eq(HB.db.healSizes[2054], 300, "rank 1")
	learn(6064, 2000)
	eq(HB.db.healSizes[6064], 1300, "moving average")
end)

test("a heal not cast before, an unsupported spell, or an unclear target announces nothing", function()
	asElya("Haplo", "Nyra")
	cast(6064, "Haplo")  -- not learned yet
	learn(596, 500)      -- Prayer of Healing: not supported
	cast(596, "Haplo")
	learn(6064, 800)
	W.sent = {}
	cast(6064, "")          -- no target name
	cast(6064, "Mallory")   -- not in the group
	advance(1)
	eq(#starts(), 0, "nothing")
end)

test("two members with the same short name: unknown", function()
	asElya("Haplo-Alpha", "Haplo-Beta")
	learn(6064, 800)  -- learning target Nyra is not in this group: learn on myself
	land(cast(6064, "Elya"), 6064, 800)
	W.sent = {}
	cast(6064, "Haplo")
	advance(1)
	eq(#starts(), 0, "ambiguous")
	eq(HB.TeamIncoming("Haplo-Alpha") + HB.TeamIncoming("Haplo-Beta"), 0, "no local prediction either")
	asElya("Haplo-Forever", "Haplo-Other")  -- same realm and another: still two fit "Haplo"
	land(cast(6064, "Elya"), 6064, 800)
	cast(6064, "Haplo")
	eq(HB.TeamIncoming("Haplo"), 0, "same-realm name with a namesake: unknown")
end)

test("with an outsider in the group the leader alone hears it; in a raid nobody", function()
	asElya("Haplo", "Mallory")
	land(cast(6064, "Elya"), 6064, 800)
	W.sent = {}
	cast(6064, "Haplo")
	advance(0.1)
	eq(#starts("PARTY"), 0, "not the party")
	local w = starts("WHISPER")
	eq(#w, 1, "whisper")
	eq(w[1].target, "Haplo", "to the leader")
	asElya("Haplo", "Nyra")
	land(cast(6064, "Elya"), 6064, 800)
	W.raid = true
	W.sent = {}
	cast(6064, "Haplo")
	advance(1)
	eq(#starts(), 0, "raid: nothing")
end)

test("a start still queued when the cast stops is never sent", function()
	asElya("Haplo", "Nyra")
	learn(6064, 800)
	W.sent = {}
	W.sendResults = { 3, 3, 3 }  -- the queue is held back
	local g = cast(6064, "Haplo")
	fire("UNIT_SPELLCAST_INTERRUPTED", "player", g, 6064)
	advance(5)
	eq(#starts(), 0, "start dropped")
	eq(#stops(), 0, "no stop needed")
end)

test("the stop reaches whoever heard the start, even after the group changed", function()
	asElya("Haplo", "Nyra")
	learn(6064, 800)
	W.sent = {}
	local g = cast(6064, "Haplo")
	advance(0.1)
	eq(#starts("PARTY"), 1, "start to the party")
	W.units.party3 = "Mallory"  -- now mixed
	fire("UNIT_SPELLCAST_FAILED", "player", g, 6064)
	advance(0.1)
	eq(#stops("PARTY"), 1, "stop to the party too")
end)

test("turning sending off stops open announcements at once", function()
	asElya("Haplo", "Nyra")
	learn(6064, 800)
	W.sent = {}
	cast(6064, "Haplo")
	advance(0.1)
	HB.SetOption("teamSendHeals", false)
	advance(0.1)
	eq(#stops("PARTY"), 1, "stopped")
	cast(6064, "Haplo")
	advance(1)
	eq(#starts("PARTY"), 1, "no new start")
end)

test("pushback announces the new end; an outsider target gets nothing", function()
	asElya("Haplo", "Nyra")
	learn(6064, 800)
	W.sent = {}
	local g = cast(6064, "Haplo", 2500)
	advance(0.5)
	W.casts = { player = { "Heal", (W.now - 0.5) * 1000, (W.now + 2.5) * 1000 } }  -- pushed back 0.5 s
	fire("UNIT_SPELLCAST_DELAYED", "player", g, 6064)
	advance(0.1)
	local s = starts("PARTY")
	eq(#s, 2, "start and update")
	assert(s[2].msg:find("|2500$"), s[2].msg)
	asElya("Haplo", "Mallory")
	land(cast(6064, "Elya"), 6064, 800)
	W.sent = {}
	cast(6064, "Mallory")
	advance(1)
	eq(#starts(), 0, "outsider")
end)

test("a start held up in the send queue is dropped", function()
	asElya("Haplo", "Nyra")
	learn(6064, 800)
	W.sent = {}
	W.sendResults = { 3, 3 }
	cast(6064, "Haplo")
	advance(5)
	eq(#starts(), 0, "too late")
end)

test("secret combat log values and bad saved sizes are never used", function()
	asElya("Haplo", "Nyra")
	W.secrets = { [777] = true }
	learn(6064, 777)
	eq(HB.db.healSizes[6064], nil, "secret amount not learned")
	HB.db.healSizes[6064] = 0 / 0
	HB.db.healSizes[2054] = "800"
	HB.db.healSizes.x = 5
	W.sent = {}
	cast(6064, "Haplo")
	cast(2054, "Haplo")
	advance(1)
	eq(#starts(), 0, "nothing announced")
	eq(HB.db.healSizes[6064], nil, "NaN dropped")
	eq(HB.db.healSizes[2054], nil, "string dropped")
	eq(HB.db.healSizes.x, nil, "bad key dropped")
end)

-- ---------------------------------------------------------------- receiving
local function asLeader()
	UnitGetIncomingHeals = nil
	party("Elya", "Nyra")
	login({}, standardTeam("Haplo"))
end

local function rowOf(name)
	for _, r in ipairs(HB.ShownRows()) do if r.name == name then return r end end
end

test("announced heals add up on the target's health bar and expire", function()
	asLeader()
	addon("Elya", "I|1|Nyra|300|2000")
	addon("Haplo", "I|9|Nyra|300|2000")  -- my own name: ignored by Core
	eq(HB.TeamIncoming("Nyra"), 300, "one")
	addon("Elya", "I|2|Nyra|200|3000")
	eq(HB.TeamIncoming("Nyra"), 500, "two casts add up")
	local r = rowOf("Nyra")
	assert(r.incoming.shown, "bar shown")
	eq(r.incoming.value, 50 + 500 > 100 and 100 or 550, "health + incoming, capped")
	addon("Elya", "I|1|-")
	eq(HB.TeamIncoming("Nyra"), 200, "stopped one")
	advance(4)
	eq(HB.TeamIncoming("Nyra"), 0, "expired")
	eq(r.incoming.shown, false, "bar gone")
end)

test("a healer leaving the group takes its heals along, also after a rejoin", function()
	asLeader()
	addon("Elya", "I|1|Nyra|30|10000")
	eq(HB.TeamIncoming("Nyra"), 30, "taken")
	party("Nyra")
	fire("GROUP_ROSTER_UPDATE")
	eq(HB.TeamIncoming("Nyra"), 0, "gone with the healer")
	party("Elya", "Nyra")
	fire("GROUP_ROSTER_UPDATE")
	eq(HB.TeamIncoming("Nyra"), 0, "not back on rejoin")
	addon("Elya", "I|2|Nyra|30|10000")
	HaploBoxTeam.order = { "Haplo", "Nyra" }  -- Elya is no longer on the team
	HB.RefreshTeam()
	eq(HB.TeamIncoming("Nyra"), 0, "gone with the team change")
end)

test("an old expiry timer does not remove a newer cast with the same id", function()
	asLeader()
	addon("Elya", "I|1|Nyra|300|1000")
	advance(0.9)
	addon("Elya", "I|1|Nyra|400|3000")
	advance(1)
	eq(HB.TeamIncoming("Nyra"), 400, "newer one kept")
end)

test("announcements are checked", function()
	asLeader()
	addon("Mallory", "I|1|Nyra|300|2000")
	addon("Elya", "I|1|Nyra|0|2000")
	addon("Elya", "I|1|Nyra|300|20000")
	addon("Elya", "I|12345|Nyra|300|2000")
	addon("Elya", "I|x|Nyra|300|2000")
	addon("Elya", "I|1|Mallory|300|2000")  -- not a team member in my group
	eq(HB.TeamIncoming("Nyra"), 0, "all refused")
	for i = 1, 6 do addon("Elya", "I|" .. i .. "|Nyra|10|2000") end
	eq(HB.TeamIncoming("Nyra"), 40, "at most four open casts per healer")
end)

test("the client's own API wins whenever it exists", function()
	asLeader()
	UnitGetIncomingHeals = function() return nil end
	addon("Elya", "I|1|Nyra|300|2000")
	local r = rowOf("Nyra")
	HB.UpdateHealPrediction(r)
	eq(r.incoming.shown, false, "nil from the client: nothing, no fallback")
end)
