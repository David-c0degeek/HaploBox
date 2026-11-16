-- Abandoning a quest on the whole team.

local function quests()
	W.quests = {
		{ title = "Elwynn", header = true },
		{ title = "Kobold Camp Cleanup", id = 7 },
		{ title = "Wolves Across the Border", id = 33 },
	}
end

local function leaderAbandons(title)
	for i, q in ipairs(W.quests) do
		if q.title == title then SelectQuestLogEntry(i) end
	end
	SetAbandonQuest()
	AbandonQuest()
end

local function asLeader(db)
	party("Elya", "Nyra")
	login(db or {}, standardTeam("Haplo"))
	quests()
end

local function asFollower(db)
	W.me = "Elya"
	party("Haplo", "Nyra")
	login(db or {}, standardTeam("Haplo"))
	quests()
end

test("the leader is asked; Yes asks the team, No does nothing", function()
	asLeader()
	leaderAbandons("Kobold Camp Cleanup")
	assert(W.popup and W.popup.text:find("Kobold Camp Cleanup"), "asked")
	clickPopup(2)
	advance(1)
	eq(#sentMatching("^Q|"), 0, "No: nothing sent")
	leaderAbandons("Wolves Across the Border")
	clickPopup(1)
	advance(1)
	local s = sentMatching("^Q|")
	eq(s[1] and s[1].msg, "Q|33|Wolves Across the Border", "Yes: sent to the group")
end)

test("no popup solo, with the setting off, or on a follower", function()
	quests()
	login({}, standardTeam("Haplo"))
	leaderAbandons("Kobold Camp Cleanup")
	eq(W.popup, nil, "solo")
	asLeader({ askAbandonQuests = false })
	leaderAbandons("Kobold Camp Cleanup")
	eq(W.popup, nil, "off")
	asFollower()
	leaderAbandons("Kobold Camp Cleanup")
	eq(W.popup, nil, "follower")
end)

test("a follower abandons the quest its leader names, and says so", function()
	asFollower()
	addon("Haplo", "Q|33|Wolves Across the Border", "PARTY")
	eq(W.abandoned and W.abandoned[1], "Wolves Across the Border", "abandoned")
	eq(W.popup, nil, "no popup on the follower")
	local r = sentMatching("^B|")
	eq(r[1].msg, "B|done|Wolves Across the Border", "answered")
	eq(r[1].channel, "WHISPER", "privately")
end)

test("a follower ignores anyone but its leader, and missing quests or the setting off", function()
	asFollower()
	addon("Nyra", "Q|33|Wolves Across the Border", "PARTY")
	eq(W.abandoned, nil, "not from a follower")
	addon("Haplo", "Q|99|Some Other Quest", "PARTY")
	eq(W.abandoned, nil, "not in the log")
	eq(sentMatching("^B|")[1].msg, "B|missing|Some Other Quest", "said")
	HB.db.followAbandonQuests = false
	addon("Haplo", "Q|33|Wolves Across the Border", "PARTY")
	eq(W.abandoned, nil, "turned off")
end)

test("the leader sees who abandoned it", function()
	asLeader()
	addon("Elya", "B|done|Wolves Across the Border", "WHISPER")
	addon("Nyra", "B|missing|Wolves Across the Border", "WHISPER")
	eq(printedMatching("Elya|r abandoned it"), 1, "done")
	eq(printedMatching("Nyra|r did not have it"), 1, "missing")
end)
