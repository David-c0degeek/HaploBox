-- Team trust (F-1), the per-kind sender gate (F-6, M-2) and whisper privacy (F-2, F-15,
-- F-10, F-17, F-8).

-- ---------------------------------------------------------------- team messages
test("M| from a non-leader does not change the team; /hb accept does", function()
	W.me = "Elya"
	party("Haplo", "Mallory")
	login({}, standardTeam("Haplo"))
	addon("Mallory", "M|Mallory|Mallory=tank;Elya=none", "PARTY")
	eq(HB.Leader(), "Haplo", "leader after hijack attempt")
	eq(printedMatching("wants to lead the team"), 1, "offer printed")
	SlashCmdList.HAPLOBOX("accept")
	eq(HB.Leader(), "Mallory", "leader after /hb accept")
	eq(HB.RoleOf("Elya"), "healer", "own role kept when the offer's role is not mine")
end)

test("M| with no stored leader waits for /hb accept", function()
	W.me = "Elya"
	party("Haplo")
	login({}, {})
	addon("Haplo", "M|Haplo|Haplo=tank;Elya=healer")
	eq(HB.Leader(), nil, "no leader before accept")
	SlashCmdList.HAPLOBOX("accept")
	eq(HB.Leader(), "Haplo", "leader after accept")
end)

test("M| from the stored leader applies at once", function()
	W.me = "Elya"
	party("Haplo", "Nyra")
	login({}, standardTeam("Haplo"))
	addon("Haplo", "M|Haplo|Haplo=tank;Elya=healer;Nyra=dps;Ayla=dps")
	eq(HB.IsTeamName("Ayla"), true, "new member applied")
end)

test("M| is rejected when malformed, by whisper, or from outside the group", function()
	W.me = "Elya"
	party("Haplo")
	login({}, standardTeam("Haplo"))
	local before = #HaploBoxTeam.order
	addon("Haplo", "M|Haplo|Haplo=tank;Nyra=dps")                 -- this toon missing
	addon("Haplo", "M|Haplo|Elya=dps;Nyra=dps")                   -- leader missing
	addon("Haplo", "M|Haplo|Haplo=tank;Elya=dps;elya=dps")        -- duplicate
	addon("Haplo", "M|Nyra|Nyra=tank;Elya=dps;Haplo=dps")         -- names another leader
	addon("Haplo", "M|Haplo|Haplo=tank;Elya=dps;Zed=dps", "WHISPER")
	addon("Stranger", "M|Stranger|Stranger=tank;Elya=dps")        -- not in the group
	eq(#HaploBoxTeam.order, before, "team unchanged")
	eq(HB.Leader(), "Haplo", "leader unchanged")
	eq(printedMatching("wants to lead"), 0, "no offer printed")
	SlashCmdList.HAPLOBOX("accept")
	eq(printedMatching("no team offer"), 1, "nothing to accept")
end)

test("/hb team sends none for unknown roles and the follower keeps its own role", function()
	party("Elya", "Nyra")
	login({}, { leader = "Haplo", roles = { Haplo = "tank" } })
	SlashCmdList.HAPLOBOX("team")
	eq(#sentMatching("^M|"), 0, "new members wait for confirmation")
	assert(W.popup and W.popup.text:find("add Elya, Nyra to your team"), "confirmation popup")
	clickPopup(1)
	local m = sentMatching("^M|")[1]
	eq(m.msg, "M|Haplo|Haplo=tank;Elya=none;Nyra=none", "wire")
	-- the follower's side
	local wire = m.msg
	W.me, W.sent, W.printed = "Elya", {}, {}
	HaploBoxTeam = { leader = "Haplo", roles = { Elya = "healer" } }
	party("Haplo", "Nyra")
	addon("Haplo", wire)
	eq(HB.RoleOf("Elya"), "healer", "own role kept")
	eq(HB.RoleOf("Nyra"), nil, "unknown role stays unknown")
	eq(HB.IsTeamName("Nyra"), true, "member kept even without a role")
end)

test("R| only from a team member naming itself, with a valid role", function()
	W.me = "Haplo"
	party("Elya", "Mallory")
	login({}, standardTeam("Haplo"))
	addon("Mallory", "R|healer|Mallory")
	eq(HB.IsTeamName("Mallory"), false, "outsider not added")
	addon("Elya", "R|tank|Nyra")
	eq(HB.RoleOf("Nyra"), "dps", "cannot set another toon's role")
	addon("Elya", "R|damager|Elya")
	eq(HB.RoleOf("Elya"), "healer", "invalid role ignored")
	addon("Elya", "R|dps|Elya")
	eq(HB.RoleOf("Elya"), "dps", "valid role applied")
end)

-- ---------------------------------------------------------------- sender gate
test("follow alerts and errors only from the team", function()
	party("Elya", "Mallory")
	login({}, standardTeam("Haplo"))
	addon("Mallory", "F|X")
	addon("Mallory", "E|R")
	eq(printedMatching("stopped following"), 0, "no alert from an outsider")
	eq(printedMatching("out of range"), 0, "no error from an outsider")
	addon("Elya", "F|X")
	addon("Elya", "E|R")
	eq(printedMatching("Elya stopped following"), 1, "alert from the team")
	eq(printedMatching("out of range"), 1, "error from the team")
end)

test("group kinds are dropped when whispered, old HELLO is dropped", function()
	party("Elya")
	login({}, standardTeam("Haplo"))
	addon("Elya", "F|X", "WHISPER")
	addon("Elya", "HELLO|0.7")
	eq(printedMatching("stopped following"), 0, "whispered F ignored")
end)

test("P| flights only from the stored leader", function()
	W.me = "Elya"
	party("Haplo", "Mallory")
	login({}, standardTeam("Haplo"))
	HB.db.debug = true
	addon("Mallory", "P|Goldshire")
	eq(printedMatching("leader flies"), 0, "outsider flight ignored")
	addon("Haplo", "P|Goldshire")
	eq(printedMatching("leader flies to Goldshire"), 1, "leader flight taken")
end)

test("F|? answers are merged into one reply per second", function()
	W.me = "Elya"
	party("Haplo", "Nyra")
	login({}, standardTeam("Haplo"))
	addon("Haplo", "F|?")
	addon("Nyra", "F|?")
	addon("Haplo", "F|?")
	eq(#W.sent, 0, "nothing before the window ends")
	advance(1.5)
	eq(#sentMatching("^S|"), 1, "one stats reply")
	eq(#sentMatching("^T|"), 1, "one focus reply")
	eq(#sentMatching("^F|x"), 1, "one follow reply")
end)

-- ---------------------------------------------------------------- whispers
test("forwarded whispers go to the leader only, never to the group", function()
	W.me = "Elya"
	party("Haplo", "Nyra")
	login({}, standardTeam("Haplo"))
	fire("CHAT_MSG_WHISPER", "selling cloth?", "Bob")
	local w = sentMatching("^W|")
	eq(#w, 1, "one forward")
	eq(w[1].channel, "WHISPER", "channel")
	eq(w[1].target, "Haplo", "target")
	eq(#sentMatching("^W|", "PARTY"), 0, "nothing on the party channel")
end)

test("a failed forward is reported locally and not broadcast", function()
	W.me = "Elya"
	party("Haplo")
	login({}, standardTeam("Haplo"))
	W.sendResults = { 1 }  -- some failure code
	fire("CHAT_MSG_WHISPER", "hello", "Bob")
	eq(printedMatching("could not forward"), 1, "local message")
	eq(#W.sent, 0, "nothing sent anywhere")
end)

test("a failed forward does not open the direct-reply window", function()
	W.me = "Elya"
	party("Haplo")
	login({}, standardTeam("Haplo"))
	W.sendResults = { 1 }
	fire("CHAT_MSG_WHISPER", "hello", "Bob")
	fire("CHAT_MSG_WHISPER", "private note", "Haplo")
	eq(#W.whispers, 0, "leader's whisper not relayed to Bob")
end)

test("no direct-reply relay while the forward is still queued", function()
	W.me = "Elya"
	party("Haplo")
	login({}, standardTeam("Haplo"))
	W.sendResults = { 3, 3 }  -- throttled twice, then accepted
	fire("CHAT_MSG_WHISPER", string.rep("long ", 100), "Bob")  -- 500 bytes: three pieces
	eq(#sentMatching("^W|"), 0, "not forwarded yet")
	fire("CHAT_MSG_WHISPER", "private note", "Haplo")
	eq(#W.whispers, 0, "pending forward: no relay")
	advance(5)
	eq(#sentMatching("^W|"), 3, "all pieces forwarded")
	fire("CHAT_MSG_WHISPER", "answer", "Haplo")
	eq(#W.whispers, 1, "relayed after the forward went through")
	advance(300)  -- the window runs from Bob's whisper, not from the forward
	fire("CHAT_MSG_WHISPER", "late", "Haplo")
	eq(#W.whispers, 1, "window closed 5 minutes after Bob's whisper")
end)

test("a late forward failure does not close a newer conversation", function()
	W.me = "Elya"
	party("Haplo")
	login({}, standardTeam("Haplo"))
	W.sendResults = { 3, 3, 3, 3, 3 }  -- Bob's forward is throttled until it gives up
	fire("CHAT_MSG_WHISPER", "hello", "Bob")
	fire("CHAT_MSG_WHISPER", "hi there", "Carl")
	advance(10)
	eq(printedMatching("could not forward the whisper from Bob"), 1, "Bob's forward failed")
	eq(#sentMatching("^W||Carl"), 1, "Carl's forward went out")
	fire("CHAT_MSG_WHISPER", "answer", "Haplo")
	eq(#W.whispers, 1, "relayed")
	eq(W.whispers[1].who, "Carl", "to the newer whisperer")
end)

test("/hb r relays only from the leader, and honours relayReplies", function()
	W.me = "Elya"
	party("Haplo", "Mallory")
	login({}, standardTeam("Haplo"))
	addon("Mallory", "Y|Elya|Bob|1|1|buy gold", "WHISPER")
	eq(#W.whispers, 0, "outsider cannot relay")
	HB.db.relayReplies = false
	addon("Haplo", "Y|Elya|Bob|1|1|hi", "WHISPER")
	eq(#W.whispers, 0, "toggle off: no whisper")
	local k = sentMatching("^K|Bob|off")
	eq(#k, 1, "leader told it is off")
	eq(k[1].target, "Haplo", "result whispered to the leader")
	HB.db.relayReplies = true
	addon("Haplo", "Y|Elya|Bob|1|1|hi", "WHISPER")
	eq(#W.whispers, 1, "toggle on: whispered")
	eq(W.whispers[1].who, "Bob", "to the whisperer")
end)

test("relay result: ok after a second, fail when the game says not online", function()
	W.me = "Elya"
	party("Haplo")
	login({}, standardTeam("Haplo"))
	addon("Haplo", "Y|Elya|Bob|1|1|hi")
	eq(#sentMatching("^K|"), 0, "no result yet")
	advance(1.1)
	eq(#sentMatching("^K|Bob|ok"), 1, "ok after a second")
	addon("Haplo", "Y|Elya|Gone|1|1|hi")
	fire("CHAT_MSG_SYSTEM", "No player named 'Gone' is currently playing.")
	advance(1.1)
	eq(#sentMatching("^K|Gone|fail"), 1, "fail on not online")
	eq(#sentMatching("^K|Gone|ok"), 0, "no ok after a fail")
end)

test("leader wording does not claim delivery", function()
	party("Elya")
	login({}, standardTeam("Haplo"))
	addon("Elya", "K|Bob|ok", "WHISPER")
	eq(printedMatching("reply passed to Elya for Bob"), 1, "wording")
	eq(printedMatching("sent to"), 0, "no delivery claim")
end)

test("direct-whisper relay window is not extended by relaying", function()
	W.me = "Elya"
	party("Haplo")
	login({}, standardTeam("Haplo"))
	fire("CHAT_MSG_WHISPER", "hi", "Bob")
	advance(200)
	fire("CHAT_MSG_WHISPER", "one", "Haplo")
	eq(#W.whispers, 1, "relayed inside the window")
	advance(150)  -- 350 s after Bob's whisper, 150 s after the relay
	fire("CHAT_MSG_WHISPER", "two", "Haplo")
	eq(#W.whispers, 1, "window closed 5 minutes after Bob's whisper")
end)

test("direct-whisper relay only for the leader the whisper was forwarded to", function()
	W.me = "Elya"
	party("Haplo", "Nyra")
	login({}, standardTeam("Haplo"))
	fire("CHAT_MSG_WHISPER", "hi", "Bob")
	SlashCmdList.HAPLOBOX("leader Nyra")
	fire("CHAT_MSG_WHISPER", "secret", "Nyra")
	eq(#W.whispers, 0, "new leader's whisper not relayed to Bob")
end)

test("text pieces fit 255 bytes and a long text needs no more than 10", function()
	local head = "Y|" .. string.rep("n", 60) .. "|" .. string.rep("r", 80)
	local text = string.rep("x", 900)
	local pieces = HB.SplitText(head, text)
	assert(pieces, "split")
	for i, p in ipairs(pieces) do
		local msg = head .. "|" .. i .. "|" .. #pieces .. "|" .. p
		assert(#msg <= 255, "piece " .. i .. " is " .. #msg .. " bytes")
	end
	eq(table.concat(pieces), text, "joined text")
	eq(HB.SplitText(string.rep("h", 250), "abc"), nil, "impossible header refused")
	eq(HB.SplitText("Y|a|b", string.rep("x", 5000)), nil, "more than 10 pieces refused")
end)

test("text pieces never split a UTF-8 character", function()
	local e = string.char(0xC3, 0xA9)  -- e with acute accent, 2 bytes
	eq(HB.SplitText(string.rep("h", 249), e), nil, "1 byte of room: the character cannot fit")
	eq(#HB.SplitText(string.rep("h", 248), e), 1, "2 bytes of room: it fits")
	local head = "Y|" .. string.rep("n", 100)
	local text = string.rep(e, 200)
	local pieces = HB.SplitText(head, text)
	assert(pieces, "split")
	for i, p in ipairs(pieces) do
		local first, last = p:byte(1), p:byte(#p)
		assert(not (first >= 0x80 and first < 0xC0), "piece " .. i .. " starts mid-character")
		assert(last < 0xC0, "piece " .. i .. " ends with a lead byte")
	end
	eq(table.concat(pieces), text, "joined text")
end)

test("old peers' W| on the party channel still reaches the leader", function()
	party("Elya")
	login({}, standardTeam("Haplo"))
	addon("Elya", "W||Bob|1|1|hello", "PARTY")
	eq(printedMatching("Bob whispers: hello"), 1, "shown")
end)
