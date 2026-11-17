-- Leader handover and role controls (#4).

local function team()
	return { leader = "Haplo", order = { "Haplo", "Elya", "Nyra" },
		roles = { Haplo = "tank", Elya = "healer", Nyra = "dps" } }
end

local function asToon(me, db)
	W.me = me
	local others = {}
	for _, n in ipairs({ "Haplo", "Elya", "Nyra" }) do if n ~= me then others[#others + 1] = n end end
	party(unpack(others))
	login(db or {}, team())
	advance(5)
end

local function attrs(name) return _G[name].attrs or {} end

-- ---------------------------------------------------------------- handover
test("take over as leader keeps the team and tells the group", function()
	asToon("Nyra")
	HB.TakeLead()
	eq(HaploBoxTeam.leader, "Nyra", "leader")
	eq(table.concat(HaploBoxTeam.order, ","), "Haplo,Elya,Nyra", "order kept")
	eq(HaploBoxTeam.roles.Nyra, "dps", "roles kept")
	advance(1)
	local s = sentMatching("^H|")
	eq(#s, 1, "sent")
	eq(s[1].channel, "PARTY", "to the group")
	assert(s[1].msg:match("^H|%d+|" .. HB.RosterHash(HaploBoxTeam.order) .. "$"), "epoch and hash: " .. s[1].msg)
end)

test("a follower takes a handover from a team member in its group with the same team", function()
	asToon("Elya")
	local e = (HaploBoxTeam.leaderEpoch or 0) + 10
	addon("Nyra", "H|" .. e .. "|" .. HB.RosterHash({ "Nyra", "Haplo", "Elya" }), "PARTY")
	eq(HaploBoxTeam.leader, "Nyra", "new leader")
	eq(HaploBoxTeam.roles.Elya, "healer", "roles unchanged")
end)

test("handovers that are refused", function()
	asToon("Elya")
	HaploBoxTeam.leaderEpoch = 1000
	local e = (HaploBoxTeam.leaderEpoch or 0) + 10
	local hash = HB.RosterHash(team().order)
	addon("Mallory", "H|" .. e .. "|" .. hash, "PARTY")
	eq(HaploBoxTeam.leader, "Haplo", "not a team member")
	addon("Nyra", "H|" .. e .. "|" .. HB.RosterHash({ "Nyra", "Haplo" }), "PARTY")
	eq(HaploBoxTeam.leader, "Haplo", "different team")
	eq(printedMatching("its team is different"), 1, "said")
	addon("Nyra", "H|999|" .. hash, "PARTY")
	eq(HaploBoxTeam.leader, "Haplo", "older than the current leader")
	addon("Nyra", "H|99999999999999|" .. hash, "PARTY")
	eq(HaploBoxTeam.leader, "Haplo", "epoch too large")
	addon("Nyra", "H|" .. e .. "|" .. hash .. "|x", "PARTY")
	eq(HaploBoxTeam.leader, "Haplo", "trailing field")
	W.units.party2 = nil  -- Nyra left the group
	addon("Nyra", "H|" .. e .. "|" .. hash, "PARTY")
	eq(HaploBoxTeam.leader, "Haplo", "not in my group")
end)

test("a late, older handover cannot undo a newer one", function()
	asToon("Haplo")
	local hash = HB.RosterHash(team().order)
	local base = HaploBoxTeam.leaderEpoch or 0
	addon("Nyra", "H|" .. (base + 20) .. "|" .. hash, "PARTY")
	addon("Elya", "H|" .. (base + 10) .. "|" .. hash, "PARTY")  -- sent earlier, arrives later
	eq(HaploBoxTeam.leader, "Nyra", "newest wins")
end)

test("two handovers with the same epoch: every toon picks the lower name", function()
	asToon("Haplo")
	local hash = HB.RosterHash(team().order)
	local e = (HaploBoxTeam.leaderEpoch or 0) + 5
	addon("Nyra", "H|" .. e .. "|" .. hash, "PARTY")
	addon("Elya", "H|" .. e .. "|" .. hash, "PARTY")
	eq(HaploBoxTeam.leader, "Elya", "Elya < Nyra")
	asToon("Haplo")
	e = (HaploBoxTeam.leaderEpoch or 0) + 5
	addon("Elya", "H|" .. e .. "|" .. hash, "PARTY")
	addon("Nyra", "H|" .. e .. "|" .. hash, "PARTY")
	eq(HaploBoxTeam.leader, "Elya", "same result in the other order")
end)

test("a full team never lowers the epoch", function()
	asToon("Elya")
	HaploBoxTeam.leaderEpoch = 4000000000
	addon("Haplo", "M|Haplo|Haplo=tank;Elya=healer;Nyra=dps", "PARTY")
	eq(HaploBoxTeam.leaderEpoch, 4000000000, "kept")
end)

test("the roster hash ignores order and roles, and names cannot run together", function()
	eq(HB.RosterHash({ "Haplo", "Elya" }), HB.RosterHash({ "elya", "Haplo" }), "order and case")
	assert(HB.RosterHash({ "ab", "c" }) ~= HB.RosterHash({ "a", "bc" }), "length-delimited")
end)

-- ---------------------------------------------------------------- role controls
test("a follower's keys follow and assist the leader by name", function()
	W.groupRoles = { Elya = "HEALER" }
	asToon("Nyra")
	eq(attrs("HaploBoxFollowLeader").macrotext, "/follow Haplo", "follow leader")
	eq(attrs("HaploBoxAssistLeader").type, "assist", "assist directly, not a macro")
	eq(attrs("HaploBoxAssistLeader").unit, "Haplo", "the leader by name")
	eq(attrs("HaploBoxAssistLeader").macrotext, nil, "no macro text")
	for _, n in ipairs({ "HaploBoxFollowLeader", "HaploBoxAssistLeader", "HaploBoxFollowHealer" }) do
		eq(attrs(n).useOnKeyDown, false, n .. " acts on the up edge")
	end
	eq(attrs("HaploBoxFollowHealer").macrotext, "/follow Elya", "follow the healer")
	eq(attrs("HaploBoxFollowLeader").type, "macro", "active")
end)

test("the healer follows the leader; the leader's keys do nothing", function()
	W.groupRoles = { Elya = "HEALER" }
	asToon("Elya")
	eq(attrs("HaploBoxFollowHealer").macrotext, "/follow Haplo", "healer follows the leader")
	asToon("Haplo")
	eq(attrs("HaploBoxFollowLeader").type, nil, "leader does not follow itself")
	eq(attrs("HaploBoxAssistLeader").type, nil, "nor assists itself")
end)

test("the leader's Follow healer key follows the healer; not itself, not with none or two", function()
	W.groupRoles = { Elya = "HEALER" }
	asToon("Haplo")
	eq(attrs("HaploBoxFollowHealer").macrotext, "/follow Elya", "leader follows the healer")
	W.groupRoles = { Haplo = "HEALER" }
	asToon("Haplo")
	eq(attrs("HaploBoxFollowHealer").type, nil, "the leader is the healer")
	W.groupRoles = {}
	asToon("Haplo")
	eq(attrs("HaploBoxFollowHealer").type, nil, "no healer")
	W.groupRoles = { Elya = "HEALER", Nyra = "HEALER" }
	asToon("Haplo")
	eq(attrs("HaploBoxFollowHealer").type, nil, "two healers")
	HB.PrintRoleControls()
	eq(printedMatching("2 healer roles"), 1, "reason shown")
end)

test("no healer or two healers: Follow healer does nothing and says why", function()
	W.groupRoles = {}
	asToon("Nyra")
	eq(attrs("HaploBoxFollowHealer").type, nil, "no healer")
	W.groupRoles = { Elya = "HEALER", Haplo = "HEALER" }
	asToon("Nyra")
	eq(attrs("HaploBoxFollowHealer").type, nil, "two healers")
	HB.PrintRoleControls()
	eq(printedMatching("2 healer roles"), 1, "reason shown")
end)

test("the keys do nothing solo, in a raid, or with an outsider in the group", function()
	asToon("Nyra")
	W.units = {}
	fire("GROUP_ROSTER_UPDATE") advance(1)
	eq(attrs("HaploBoxFollowLeader").type, nil, "solo")
	eq(attrs("HaploBoxAssistLeader").type, nil, "assist off solo")
	eq(attrs("HaploBoxAssistLeader").unit, nil, "no stale unit")
	party("Haplo", "Elya", "Mallory")
	fire("GROUP_ROSTER_UPDATE") advance(1)
	eq(attrs("HaploBoxFollowLeader").type, nil, "outsider")
	party("Haplo", "Elya")
	W.raid = true
	fire("GROUP_ROSTER_UPDATE") advance(1)
	eq(attrs("HaploBoxFollowLeader").type, nil, "raid")
end)

test("a change in combat waits, shows it, and applies after combat", function()
	asToon("Nyra")
	W.combat = true
	HB.SetLeaderName("Elya")
	advance(1)
	eq(attrs("HaploBoxFollowLeader").macrotext, "/follow Haplo", "unchanged in combat")
	eq(attrs("HaploBoxAssistLeader").unit, "Haplo", "assist unchanged in combat")
	eq(HB.RoleControlsPending(), true, "pending")
	W.combat = false
	fire("PLAYER_REGEN_ENABLED")
	advance(1)
	eq(attrs("HaploBoxFollowLeader").macrotext, "/follow Elya", "applied")
	eq(attrs("HaploBoxAssistLeader").unit, "Elya", "assist applied")
	eq(HB.RoleControlsPending(), false, "done")
end)

test("the Blizzard party leader gets a crown on its row, and it moves", function()
	W.partyLeader = "Elya"
	asToon("Haplo")
	local rows = {}
	for _, r in ipairs(HB.ShownRows()) do rows[r.name] = r end
	eq(rows.Elya.partyLead.shown, true, "crown")
	W.partyLeader = "Haplo"
	fire("PARTY_LEADER_CHANGED")
	eq(rows.Elya.partyLead.shown, false, "moved away")
	eq(rows.Haplo.partyLead.shown, true, "moved to Haplo")
end)

test("taking over does not work in a raid, sent or received", function()
	asToon("Nyra")
	W.raid = true
	HB.TakeLead()
	eq(HaploBoxTeam.leader, "Haplo", "not taken")
	advance(1)
	eq(#sentMatching("^H|"), 0, "nothing sent")
	addon("Elya", "H|" .. ((HaploBoxTeam.leaderEpoch or 0) + 10) .. "|" .. HB.RosterHash(team().order), "RAID")
	eq(HaploBoxTeam.leader, "Haplo", "not taken from a raid")
end)

test("the frame and the key use the same healer: Blizzard roles, not stored ones", function()
	W.groupRoles = { Nyra = "HEALER" }  -- stored team role says Elya
	asToon("Haplo")
	eq(HB.TeamHealer(), "Nyra", "Blizzard role wins")
	HB.followState.elya, HB.followTarget.elya = "S", "Nyra"
	HB.OnFollowStateChanged()
	local row
	for _, r in ipairs(HB.ShownRows()) do if r.name == "Elya" then row = r end end
	eq(row.box.label.text, "> HEAL", "Elya follows the healer Nyra")
	W.groupRoles = { Nyra = "HEALER", Elya = "HEALER" }
	eq(HB.TeamHealer(), nil, "two healers: none")
end)

test("an unreadable group role makes the healer unknown", function()
	W.groupRoles = { Elya = "HEALER" }
	asToon("Nyra")
	W.secrets = W.secrets or {}
	local real = UnitGroupRolesAssigned
	UnitGroupRolesAssigned = function(u) if u == "party1" then error("restricted") end return real(u) end
	local h, why = HB.TeamHealer()
	UnitGroupRolesAssigned = real
	eq(h, nil, "unknown")
	eq(why, "group roles cannot be read", "says why")
end)

-- ---------------------------------------------------------------- Lead button
local function leadShown() return HaploBoxLeadButton and HaploBoxLeadButton:IsShown() end

test("the Lead button shows on team members that are not the leader, in a team-only party", function()
	asToon("Nyra")
	advance(1)
	eq(leadShown(), true, "follower")
	asToon("Haplo")
	advance(1)
	eq(leadShown(), false, "not on the leader")
	asToon("Nyra")
	party("Haplo", "Elya", "Mallory")
	fire("GROUP_ROSTER_UPDATE") advance(1)
	eq(leadShown(), false, "someone outside the team")
	party("Haplo", "Elya")
	W.raid = true
	fire("GROUP_ROSTER_UPDATE") advance(1)
	eq(leadShown(), false, "raid")
	W.raid = false
	W.units = {}
	fire("GROUP_ROSTER_UPDATE") advance(1)
	eq(leadShown(), false, "solo")
end)

test("clicking Lead takes over, also in combat, and the button moves to the old leader", function()
	asToon("Nyra")
	advance(1)
	W.combat = true
	W.sent = {}
	HaploBoxLeadButton.scripts.OnClick(HaploBoxLeadButton)
	eq(HB.IAmLeader(), true, "leader now")
	eq(#sentMatching("^H|"), 1, "handover sent in combat")
	eq(leadShown(), false, "hidden on the new leader")
	advance(1)
	eq(HB.RoleControlsPending(), true, "secure buttons wait for the end of combat")
end)

test("the Lead button can be turned off", function()
	asToon("Nyra", { leadButton = false })
	advance(1)
	eq(leadShown(), false, "off")
	HB.SetOption("leadButton", true)
	eq(leadShown(), true, "on")
end)
