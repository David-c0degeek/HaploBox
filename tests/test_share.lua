-- Sharing the team frame layout (#14).

local function pieces()
	local out = {}
	for _, s in ipairs(sentMatching("^U|")) do out[#out + 1] = s end
	return out
end

-- The leader's share as the follower would get it: leader Haplo with some settings.
local function leaderPayload(db)
	UIParent:SetSize(1000, 800)
	party("Elya", "Nyra")
	db = db or {}
	db.teamShowGold = false
	db.teamW = 320
	db.teamHotNames = "Renew; Earth Shield"
	db.partyPos = { "TOPLEFT", "BOTTOMLEFT", 100, 600 }
	db.teamView = "mini"
	login(db, standardTeam("Haplo"))
	return HB.ShareText()
end

local function asFollower(db)
	W.me = "Elya"
	party("Haplo", "Nyra")
	login(db or {}, standardTeam("Haplo"))
	UIParent:SetSize(2000, 1000)
end

local function deliver(text, from, id, channel)
	local list = HB.SplitText("U|" .. (id or 5), text)
	for i, p in ipairs(list) do
		addon(from or "Haplo", "U|" .. (id or 5) .. "|" .. i .. "|" .. #list .. "|" .. p, channel or "WHISPER")
	end
end

local function answers()
	local out = {}
	for _, s in ipairs(sentMatching("^A|")) do out[#out + 1] = s.msg end
	return out
end

-- ---------------------------------------------------------------- payload
test("the shared text holds the allowlist only, with positions as screen fractions", function()
	local text = leaderPayload()
	assert(text:find("teamShowGold=0"), "display setting")
	assert(text:find("teamW=320"), "size")
	assert(text:find("pos=0%.1000,0%.7500"), "position as fractions: " .. text)
	assert(text:find("teamHotNames=Renew Earth Shield"), "separators stripped")
	assert(not text:find("teamView"), "Main / Mini Heal is not shared")
	assert(not text:find("autoFFA") and not text:find("forwardWhispers") and not text:find("leader"), "no automation or team")
	assert(HB.DecodeShare(text), "decodes")
end)

test("bad payloads are refused whole", function()
	local text = leaderPayload()
	local body = text:match("^(.*);sum=")
	local function signed(b)
		local a, c = 1, 0
		for i = 1, #b do a = (a + b:byte(i)) % 65521 c = (c + a) % 65521 end
		return b .. ";sum=" .. (c * 65536 + a)
	end
	eq(select(2, HB.DecodeShare(body .. ";sum=1")), "checksum", "checksum")
	eq(select(2, HB.DecodeShare(signed(body:gsub("v=1", "v=2")))), "version", "version")
	eq(select(2, HB.DecodeShare(signed(body .. ";autoFFA=1"))), "unknown autoFFA", "not on the allowlist")
	eq(select(2, HB.DecodeShare(signed(body:gsub("teamW=320", "teamW=nan")))), "bad teamW", "NaN")
	eq(select(2, HB.DecodeShare(signed(body:gsub("teamW=320", "teamW=9000")))), "bad teamW", "out of range")
	eq(select(2, HB.DecodeShare(signed(body:gsub("teamShowGold=0", "teamShowGold=yes")))), "bad teamShowGold", "type")
	eq(select(2, HB.DecodeShare(signed(body:gsub("buffsPos=d", "buffsPos=2,0.5")))), "bad buffsPos", "position off screen")
end)

-- ---------------------------------------------------------------- follower
test("a follower applies the leader's layout, keeps its own view, and can undo", function()
	local text = leaderPayload()
	asFollower({ teamView = "main", teamShowGold = true })
	deliver(text)
	eq(HB.db.teamShowGold, false, "applied")
	eq(HB.db.teamW, 320, "size")
	eq(HB.db.teamView, "main", "own view kept")
	eq(HB.db.partyPos[3], 200, "x fraction on this screen")
	eq(HB.db.partyPos[4], 750, "y fraction on this screen")
	eq(answers()[1], "A|5|applied", "answered")
	eq(sentMatching("^A|")[1].channel, "WHISPER", "privately")
	SlashCmdList.HAPLOBOX("frame undo")
	eq(HB.db.teamShowGold, true, "undone")
	eq(HB.db.teamW, nil, "a size it never had is gone again")
	eq(HB.db.partyPos, nil, "and so is the position")
end)

test("undo and a failed apply keep a saved false as false", function()
	local text = leaderPayload({ teamShowXP = true })
	asFollower({ teamShowXP = false, teamCastBars = false })
	deliver(text)
	eq(HB.db.teamShowXP, true, "applied")
	SlashCmdList.HAPLOBOX("frame undo")
	eq(HB.db.teamShowXP, false, "false again, not nil")
	eq(HB.db.teamCastBars, false, "untouched false kept")
	local real = HB.PlaceAuraOverviews
	HB.PlaceAuraOverviews = function() error("draw") end
	deliver(text, "Haplo", 12)
	HB.PlaceAuraOverviews = real
	eq(HB.db.teamShowXP, false, "drawing error rolled back")
	eq(HB.db.teamW, nil, "size rolled back")
	eq(answers()[2], "A|12|rejected:error", "refused")
end)

test("defaults on the leader replace the follower's own size and position", function()
	UIParent:SetSize(1000, 800)
	party("Elya", "Nyra")
	login({}, standardTeam("Haplo"))
	local text = HB.ShareText()
	assert(text:find("teamW=d") and text:find(";pos=d") and text:find("buffsPos=d"), "defaults said: " .. text)
	asFollower({ teamW = 420, partyPos = { "TOPLEFT", "BOTTOMLEFT", 5, 5 }, auraPos = { buffs = { x = 0.2, y = 0.2 } } })
	deliver(text)
	eq(answers()[1], "A|5|applied", "applied")
	eq(HB.db.teamW, nil, "own width dropped")
	eq(HB.db.partyPos, nil, "own position dropped")
	eq(HB.db.auraPos.buffs, nil, "own aura window position dropped")
	SlashCmdList.HAPLOBOX("frame undo")
	eq(HB.db.teamW, 420, "undo brings it back")
end)

test("an older share that completes late is refused, also after a reload", function()
	local gold = leaderPayload({ teamShowGold = false })
	asFollower()
	local nogold = gold:gsub("teamShowGold=0", "teamShowGold=1")
	local body = nogold:match("^(.*);sum=")
	local a, c = 1, 0
	for i = 1, #body do a = (a + body:byte(i)) % 65521 c = (c + a) % 65521 end
	nogold = body .. ";sum=" .. (c * 65536 + a)
	deliver(gold, "Haplo", 102)
	deliver(nogold, "Haplo", 101)
	eq(HB.db.teamShowGold, false, "older id did not win")
	eq(answers()[2], "A|101|rejected:stale", "stale")
	login(HB.db, HaploBoxTeam)
	reloadAddonFile("Share.lua")  -- reload: fresh module state, the newest id is saved
	deliver(nogold, "Haplo", 100)
	eq(HB.db.teamShowGold, false, "replay after reload refused")
	deliver(gold, "Haplo", 102)
	eq(answers()[#answers()], "A|102|applied", "same id: same answer, nothing new")
end)

test("in combat an older share cannot replace a newer waiting one", function()
	local text = leaderPayload()
	asFollower()
	W.combat = true
	deliver(text, "Haplo", 20)
	deliver(text, "Haplo", 19)
	eq(answers()[2], "A|19|rejected:stale", "stale")
	W.combat = false
	fire("PLAYER_REGEN_ENABLED")
	eq(answers()[3], "A|20|applied", "newer applied")
end)

test("a share left waiting by a reload is answered as lost, without a resend", function()
	leaderPayload()
	local leaderDb = HB.db
	HB.ShareUI()
	clickPopup(1)
	local id = HB.ShareJob().id
	addon("Elya", "A|" .. id .. "|waiting", "WHISPER")
	addon("Nyra", "A|" .. id .. "|applied", "WHISPER")
	-- Elya reloads in combat: its saved record says waiting, nothing is queued any more
	local followerDb = { shareNewest = { haplo = { id = id, result = "waiting", name = "Haplo" } } }
	W.me = "Elya"
	party("Haplo", "Nyra")
	reloadAddonFile("Share.lua")
	W.sent = {}
	HaploBoxDB, HaploBoxTeam = followerDb, standardTeam("Haplo")
	fire("ADDON_LOADED", "HaploBox")
	fire("PLAYER_LOGIN")
	advance(5)
	eq(followerDb.shareNewest.haplo.result, "rejected:reload", "saved record updated")
	local a = sentMatching("^A|")
	eq(a[1] and a[1].msg, "A|" .. id .. "|rejected:reload", "leader told")
	eq(a[1].target, "Haplo", "to the leader")
end)

test("a share left waiting by a reload is taken again when resent", function()
	local text = leaderPayload()
	asFollower({ teamW = 420 })
	W.combat = true
	deliver(text, "Haplo", 99)
	eq(answers()[1], "A|99|waiting", "waiting")
	W.combat = false
	reloadAddonFile("Share.lua")  -- reload before combat ended: the waiting share is gone
	deliver(text, "Haplo", 99)
	eq(answers()[2], "A|99|applied", "resend processed, not 'waiting' forever")
	eq(HB.db.teamW, 320, "applied")
end)

test("ids keep growing across a leader reload in the same second", function()
	leaderPayload()
	HB.ShareUI()
	clickPopup(1)
	local first = HB.ShareJob().id
	reloadAddonFile("Share.lua")
	HB.ShareUI()
	clickPopup(1)
	eq(HB.ShareJob().id > first, true, "newer id after reload")
end)

test("only the stored leader, only by whisper, and only when allowed", function()
	local text = leaderPayload()
	asFollower()
	deliver(text, "Nyra")
	eq(HB.db.teamW, nil, "a follower cannot send it")
	deliver(text, "Haplo", 5, "PARTY")
	eq(HB.db.teamW, nil, "not on the party channel")
	HB.db.acceptSharedUI = false
	deliver(text, "Haplo", 6)
	eq(HB.db.teamW, nil, "turned off")
	eq(answers()[1], "A|6|rejected:off", "says why")
end)

test("a resend is answered again but not applied twice", function()
	local text = leaderPayload()
	asFollower()
	deliver(text)
	HB.db.teamShowGold = true  -- changed by hand afterwards
	deliver(text)
	eq(HB.db.teamShowGold, true, "not applied again")
	eq(#answers(), 2, "answered twice")
end)

test("pieces older than 30 seconds are dropped", function()
	local text = leaderPayload()
	asFollower()
	local list = HB.SplitText("U|7", text)
	assert(#list > 1, "needs several pieces")
	addon("Haplo", "U|7|1|" .. #list .. "|" .. list[1], "WHISPER")
	advance(31)
	for i = 2, #list do addon("Haplo", "U|7|" .. i .. "|" .. #list .. "|" .. list[i], "WHISPER") end
	eq(HB.db.teamW, nil, "incomplete, nothing applied")
end)

test("in combat a share waits, a newer one replaces it, and the leader is checked again", function()
	local text = leaderPayload()
	asFollower()
	W.combat = true
	deliver(text, "Haplo", 8)
	deliver(text, "Haplo", 9)
	local a = answers()
	eq(a[1], "A|8|waiting", "waiting")
	eq(a[2], "A|8|rejected:superseded", "old one replaced")
	eq(a[3], "A|9|waiting", "newer waiting")
	eq(HB.db.teamW, nil, "nothing applied in combat")
	HaploBoxTeam.leader = "Nyra"  -- leader changed during combat
	W.combat = false
	fire("PLAYER_REGEN_ENABLED")
	eq(HB.db.teamW, nil, "not applied: Haplo is no longer the leader")
	eq(answers()[4], "A|9|rejected:not leader", "says why")
end)

-- ---------------------------------------------------------------- leader
test("the leader confirms, sends privately to the team in the group, and reports answers", function()
	leaderPayload()
	W.units.party3 = "Mallory"  -- in the group, not in the team
	HB.ShareUI()
	assert(W.popup and W.popup.text:find("Elya, Nyra"), "names the receivers")
	assert(W.popup.text:find("Not shared: Main / Mini Heal"), "preview")
	eq(#pieces(), 0, "nothing sent before confirming")
	clickPopup(1)
	advance(1)
	for _, s in ipairs(pieces()) do
		eq(s.channel, "WHISPER", "whisper")
		assert(s.target == "Elya" or s.target == "Nyra", "team only, not " .. tostring(s.target))
	end
	local id = HB.ShareJob().id
	addon("Elya", "A|" .. id .. "|applied", "WHISPER")
	addon("Nyra", "A|" .. id .. "|waiting", "WHISPER")
	eq(printedMatching("Elya|r: applied"), 1, "applied")
	eq(printedMatching("Nyra|r: waiting for the end of combat"), 1, "waiting")
	advance(20)
	eq(printedMatching("no answer"), 0, "waiting is an answer")
end)

test("no answer: one resend, then said so", function()
	leaderPayload()
	HB.ShareUI()
	clickPopup(1)
	advance(1)
	local first = #pieces()
	advance(8)
	eq(#pieces(), first * 2, "sent once more")
	advance(9)
	eq(printedMatching("no answer"), 2, "both said")
end)

test("a member who leaves before the queued send gets nothing", function()
	leaderPayload()
	HB.ShareUI()
	W.units.party2 = nil  -- Nyra leaves before the click
	clickPopup(1)
	advance(1)
	for _, s in ipairs(pieces()) do assert(s.target ~= "Nyra", "nothing to Nyra") end
	eq(printedMatching("Nyra|r: left the group"), 1, "said")
end)
