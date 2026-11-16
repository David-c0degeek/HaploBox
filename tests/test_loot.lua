-- Loot in mixed groups (#7): free for all only when every member is in the team,
-- group loot as soon as someone from outside is there. Name forms across realms (#1).

local FFA, GROUP = 0, 3

local function leaderIn(...)
	party(...)
	login({}, standardTeam("Haplo"))
end

-- ---------------------------------------------------------------- automatic loot
test("a team-only group gets free for all", function()
	W.loot = GROUP
	leaderIn("Elya", "Nyra")
	fire("GROUP_ROSTER_UPDATE")
	advance(3)
	eq(W.loot, FFA, "free for all")
	eq(printedMatching("loot set to free for all"), 1, "confirmed from the readable method")
end)

test("an outsider joining switches free for all to group loot", function()
	leaderIn("Elya", "Nyra")
	fire("GROUP_ROSTER_UPDATE")
	advance(3)
	W.units.party3 = "Mallory"
	fire("GROUP_ROSTER_UPDATE")
	advance(3)
	eq(W.loot, GROUP, "group loot")
	eq(printedMatching("Mallory is not in the team"), 1, "says why")
end)

test("a same-size replacement by an outsider is caught", function()
	leaderIn("Elya", "Nyra")
	fire("GROUP_ROSTER_UPDATE")
	advance(3)
	W.units.party2 = "Mallory"  -- Nyra left, Mallory joined: still three
	fire("GROUP_ROSTER_UPDATE")
	advance(3)
	eq(W.loot, GROUP, "group loot")
end)

test("free for all comes back when the outsider leaves", function()
	leaderIn("Elya", "Mallory")
	W.loot = GROUP
	fire("GROUP_ROSTER_UPDATE")
	advance(3)
	eq(W.loot, GROUP, "stays group loot while Mallory is there")
	W.units.party2 = nil
	fire("GROUP_ROSTER_UPDATE")
	advance(3)
	eq(W.loot, FFA, "free for all again")
end)

test("leaving and regrouping with the same team sets free for all again", function()
	leaderIn("Elya", "Nyra")
	fire("GROUP_ROSTER_UPDATE")
	advance(3)
	eq(W.loot, FFA, "first group")
	party()
	fire("GROUP_ROSTER_UPDATE")
	advance(3)
	W.loot = GROUP  -- the new group starts with another method
	party("Elya", "Nyra")
	fire("GROUP_ROSTER_UPDATE")
	advance(3)
	eq(W.loot, FFA, "free for all in the new group")
end)

test("a loot method chosen by hand stays until the group changes", function()
	leaderIn("Elya", "Nyra")
	fire("GROUP_ROSTER_UPDATE")
	advance(3)
	W.loot = GROUP  -- the leader picks group loot in Blizzard's menu
	fire("GROUP_ROSTER_UPDATE")  -- the change itself fires a roster update
	advance(3)
	eq(W.loot, GROUP, "not switched back")
end)

test("an unknown name blocks free for all until it resolves", function()
	W.loot = GROUP
	leaderIn("Elya", "Unknown")
	fire("GROUP_ROSTER_UPDATE")
	advance(3)
	eq(W.loot, GROUP, "nothing while a name is unknown")
	W.units.party2 = "Nyra"
	advance(3)  -- the retry looks again
	eq(W.loot, FFA, "free for all once the name is known")
end)

test("a delayed check sees the group as it is when it runs", function()
	W.loot = GROUP
	leaderIn("Elya", "Nyra")
	fire("GROUP_ROSTER_UPDATE")
	W.units.party2 = "Mallory"  -- before the check runs, without a new event
	advance(3)
	eq(W.loot, GROUP, "no free for all for a group with an outsider")
end)

test("no loot change without group-leader authority or with the option off", function()
	W.loot = GROUP
	W.notGroupLeader = true
	leaderIn("Elya", "Nyra")
	fire("GROUP_ROSTER_UPDATE")
	advance(3)
	eq(#W.lootSets, 0, "not group leader")
	W.notGroupLeader = nil
	HB.db.autoFFA = false
	fire("GROUP_ROSTER_UPDATE")
	advance(3)
	eq(#W.lootSets, 0, "option off")
end)

test("a refused change is reported, not claimed", function()
	W.loot = GROUP
	W.lootRefused = true
	leaderIn("Elya", "Nyra")
	fire("GROUP_ROSTER_UPDATE")
	advance(3)
	eq(printedMatching("loot set to"), 0, "no success message")
	eq(printedMatching("could not set loot to free for all"), 1, "failure shown")
end)

test("a client without loot methods is left alone", function()
	W.noLootApi = true
	leaderIn("Elya", "Mallory")
	fire("GROUP_ROSTER_UPDATE")
	advance(3)
	eq(#W.lootSets, 0, "nothing tried")
end)

-- ---------------------------------------------------------------- /hb ffa
test("/hb ffa works with an outsider, warns, and is not switched back", function()
	W.loot = GROUP
	leaderIn("Elya", "Mallory")
	fire("GROUP_ROSTER_UPDATE")
	advance(3)
	SlashCmdList.HAPLOBOX("ffa")
	eq(W.loot, FFA, "the leader's choice")
	eq(printedMatching("Mallory is not in the team and can loot freely"), 1, "warning")
	fire("GROUP_ROSTER_UPDATE")
	advance(3)
	eq(W.loot, FFA, "not switched back")
end)

test("/hb ffa when free for all is already set still counts as the leader's choice", function()
	leaderIn("Elya", "Nyra")
	fire("GROUP_ROSTER_UPDATE")
	advance(3)
	SlashCmdList.HAPLOBOX("ffa")
	eq(printedMatching("already free for all"), 1, "already set")
	W.units.party3 = "Mallory"
	fire("GROUP_ROSTER_UPDATE")
	advance(3)
	eq(W.loot, FFA, "kept")
end)

test("/hb ffa without authority or solo does not count as a choice", function()
	W.notGroupLeader = true
	leaderIn("Elya", "Nyra")
	fire("GROUP_ROSTER_UPDATE")
	advance(3)
	SlashCmdList.HAPLOBOX("ffa")
	W.notGroupLeader = nil
	W.units.party3 = "Mallory"
	fire("GROUP_ROSTER_UPDATE")
	advance(3)
	eq(W.loot, GROUP, "outsider protection still on")
end)

test("free for all picked in Blizzard's menu with an outsider stays", function()
	leaderIn("Elya", "Mallory")
	fire("GROUP_ROSTER_UPDATE")
	advance(3)
	eq(W.loot, GROUP, "switched once when Mallory was found")
	W.loot = FFA  -- the leader picks free for all again
	fire("PARTY_LOOT_METHOD_CHANGED")
	advance(3)
	eq(W.loot, FFA, "left alone")
	W.units.party3 = "Zed"  -- another outsider joins
	fire("GROUP_ROSTER_UPDATE")
	advance(3)
	eq(W.loot, FFA, "still the leader's choice")
end)

test("a slow server answer is not taken for a choice by hand", function()
	leaderIn("Elya", "Mallory")
	W.lootRefused = true  -- the request is not applied yet
	fire("GROUP_ROSTER_UPDATE")
	advance(3)
	W.lootRefused = nil
	fire("GROUP_ROSTER_UPDATE")
	advance(3)
	eq(W.loot, GROUP, "still switched to group loot")
end)

-- ---------------------------------------------------------------- trusted roster
test("a stored role alone does not make someone part of the team", function()
	login({}, { leader = "Haplo", order = { "Haplo", "Elya" }, roles = { Mallory = "dps" } })
	eq(HB.IsTeamName("Mallory"), false, "role-only name")
	eq(HB.IsTeamName("Elya"), true, "team list name")
end)

test("Send team asks before adding group members who are not in the team", function()
	party("Elya", "Mallory")
	login({}, standardTeam("Haplo"))
	HB.MakeMeLeader()
	eq(#sentMatching("^M|"), 0, "not sent yet")
	assert(W.popup and W.popup.text:find("add Mallory to your team"), "names the newcomer only")
	clickPopup(1)
	eq(#sentMatching("^M|Haplo|"), 1, "sent after confirming")
	eq(HB.IsTeamName("Mallory"), true, "now in the team")
end)

test("a confirmation for a group that has since changed adds nobody", function()
	party("Elya", "Mallory")
	login({}, standardTeam("Haplo"))
	HB.MakeMeLeader()
	W.units.party2 = "Zed"  -- Mallory left, Zed joined before the click
	clickPopup(1)
	eq(#sentMatching("^M|"), 0, "nothing sent")
	eq(HB.IsTeamName("Zed"), false, "Zed not added")
	eq(printedMatching("the group changed"), 1, "explains")
end)

test("Send team with only known members needs no confirmation", function()
	party("Elya", "Nyra")
	login({}, standardTeam("Haplo"))
	HB.MakeMeLeader()
	eq(W.popup, nil, "no popup")
	eq(#sentMatching("^M|Haplo|"), 1, "sent")
end)

-- ---------------------------------------------------------------- names (#1)
test("names match across realm suffix forms", function()
	-- W.realm is "Forever"; realms with spaces keep their identity without spaces
	eq(HB.Norm("Haplo-Forever"), HB.Norm("Haplo"), "own realm suffix")
	eq(HB.Norm("Haplo-forever"), HB.Norm("Haplo"), "own realm, other case")
	eq(HB.Norm("Elya-Argent Dawn"), HB.Norm("Elya-ArgentDawn"), "spaces in a realm")
	assert(HB.Norm("Elya-ArgentDawn") ~= HB.Norm("Elya"), "other realm stays distinct")
	assert(HB.Norm("Elya-ArgentDawn") ~= HB.Norm("Elya-Stormrage"), "two other realms differ")
	eq(HB.Norm("Ayla Moon"), "ayla moon", "Forever full names unchanged")
end)

test("a cross-realm leader is recognised in either name form", function()
	W.me = "Elya"
	party("Haplo-Argent Dawn", "Nyra")
	login({}, { leader = "Haplo-Argent Dawn", order = { "Haplo-Argent Dawn", "Elya", "Nyra" } })
	eq(HB.IsLeaderName("Haplo-ArgentDawn"), true, "addon sender form")
	HB.db.debug = true
	addon("Haplo-ArgentDawn", "P|Ironforge")
	addon("Mallory", "P|Ironforge")
	eq(printedMatching("ignored.*Mallory"), 1, "debug shows ignored messages")
	eq(printedMatching("ignored.*Haplo"), 0, "leader message not ignored")
end)
