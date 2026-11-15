-- Send queue (F-3), quests (F-4), leaving with the leader (F-5), roles (M-1) and
-- the status line (M-3).

-- ---------------------------------------------------------------- send queue
test("a burst stays within the allowance and the rest goes out later", function()
	party("Elya")
	login({}, standardTeam("Haplo"))
	for i = 1, 12 do addon("Elya", "R|dps|Elya") SlashCmdList.HAPLOBOX("role tank") end
	assert(#W.sent <= 8, "burst sent " .. #W.sent)
	advance(10)
	eq(#sentMatching("^R|"), 12, "all role messages sent in the end")
end)

test("a throttled send is retried, not lost", function()
	party("Elya")
	login({}, standardTeam("Haplo"))
	W.sendResults = { 3, 8 }  -- AddonMessageThrottle, then ChannelThrottle
	SlashCmdList.HAPLOBOX("role healer")
	eq(#W.sent, 0, "throttled at first")
	advance(3)
	eq(#sentMatching("^R|healer|Haplo"), 1, "sent after the retry")
end)

test("queued stats are replaced by newer stats, and dropped when leaving the group", function()
	party("Elya")
	login({}, standardTeam("Haplo"))
	W.sendResults = { 3 }
	fire("PLAYER_FOCUS_CHANGED")
	W.units.focus = "Defias"
	fire("PLAYER_FOCUS_CHANGED")
	advance(2)
	local t = sentMatching("^T|")
	eq(#t, 1, "one focus message")
	eq(t[1].msg, "T|Defias", "the newest")
	W.sendResults = { 3 }
	fire("PLAYER_FOCUS_CHANGED")
	W.units = {}
	fire("GROUP_ROSTER_UPDATE")
	advance(5)
	eq(#sentMatching("^T|"), 1, "nothing sent after leaving")
end)

test("a whole team reloading stays within the allowance", function()
	W.me = "Elya"
	party("Haplo", "Nyra", "Ayla", "Zed")
	login({}, { leader = "Haplo", order = { "Haplo", "Elya", "Nyra", "Ayla", "Zed" } })
	fire("PLAYER_ENTERING_WORLD")
	advance(3.1)
	for _, n in ipairs({ "Haplo", "Nyra", "Ayla", "Zed" }) do addon(n, "F|?") end
	advance(1.1)
	assert(#W.sent <= 8, "sent " .. #W.sent .. " in the first seconds")
end)

-- ---------------------------------------------------------------- quests
test("shared quests are accepted from the team only", function()
	W.me = "Elya"
	party("Haplo", "Mallory")
	login({}, standardTeam("Haplo"))
	W.questnpc = "Mallory"
	fire("QUEST_DETAIL")
	eq(W.questAccepted, 0, "not from an outsider")
	W.questnpc = "Haplo"
	fire("QUEST_DETAIL")
	eq(W.questAccepted, 1, "from the leader")
end)

-- ---------------------------------------------------------------- leave with the leader
test("leaving a group resets the leader-present flag", function()
	W.me = "Elya"
	party("Haplo")
	login({ autoLeaveWithLeader = true }, standardTeam("Haplo"))
	fire("GROUP_ROSTER_UPDATE")
	W.units = {}               -- this toon leaves while the leader is still there
	fire("GROUP_ROSTER_UPDATE")
	party("Friend")            -- joins someone else's group
	fire("GROUP_ROSTER_UPDATE")
	eq(W.left, 0, "does not leave the new group")
	party("Friend", "Haplo")
	fire("GROUP_ROSTER_UPDATE")
	W.units.party2 = nil       -- now the leader leaves
	fire("GROUP_ROSTER_UPDATE")
	eq(W.left, 1, "leaves when the leader leaves")
end)

-- ---------------------------------------------------------------- roles
test("role check: a stored role outside the set is not answered", function()
	W.me = "Elya"
	login({}, { leader = "Haplo", roles = { Elya = "damager" } })
	fire("LFG_ROLE_CHECK_SHOW")
	eq(W.lfgRoles, nil, "not answered")
	HaploBoxTeam.roles.Elya = "dps"
	fire("LFG_ROLE_CHECK_SHOW")
	eq(W.lfgRoles[4], true, "dps answered")
end)

test("/hb role refuses unknown roles", function()
	login({}, standardTeam("Haplo"))
	SlashCmdList.HAPLOBOX("role damager")
	eq(HB.MyRole(), "tank", "unchanged")
	eq(printedMatching("role must be tank, healer, dps"), 1, "message")
end)

-- ---------------------------------------------------------------- status
test("/hb status reads loot through the modern API", function()
	party("Elya")
	login({}, standardTeam("Haplo"))
	SlashCmdList.HAPLOBOX("status")
	eq(printedMatching("loot: free for all"), 1, "loot shown")
end)
