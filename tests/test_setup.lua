-- Setting up the team without slash commands: the accept popup, the key binding
-- actions and the Send team button.

local function offer()
	addon("Mallory", "M|Mallory|Mallory=tank;Elya=none")
end

test("a team offer shows a popup; Accept takes the team", function()
	W.me = "Elya"
	party("Haplo", "Mallory")
	login({}, standardTeam("Haplo"))
	offer()
	assert(W.popup, "popup shown")
	assert(W.popup.text:find("Mallory wants to lead your team %(Mallory, Elya%)"), W.popup.text)
	clickPopup(1)
	eq(HB.Leader(), "Mallory", "leader after Accept")
end)

test("Decline drops the offer", function()
	W.me = "Elya"
	party("Haplo", "Mallory")
	login({}, standardTeam("Haplo"))
	offer()
	clickPopup(2)
	eq(HB.Leader(), "Haplo", "leader unchanged")
	SlashCmdList.HAPLOBOX("accept")
	eq(HB.Leader(), "Haplo", "nothing left to accept")
end)

test("an offer in combat waits for the end of combat", function()
	W.me = "Elya"
	party("Haplo", "Mallory")
	login({}, standardTeam("Haplo"))
	W.combat = true
	offer()
	eq(W.popup, nil, "no popup in combat")
	W.combat = false
	fire("PLAYER_REGEN_ENABLED")
	assert(W.popup, "popup after combat")
end)

test("/hb accept closes the popup; a team from the stored leader closes it too", function()
	W.me = "Elya"
	party("Haplo", "Mallory")
	login({}, standardTeam("Haplo"))
	offer()
	SlashCmdList.HAPLOBOX("accept")
	eq(W.popup, nil, "closed by /hb accept")
	eq(HB.Leader(), "Mallory", "accepted")
	addon("Haplo", "M|Haplo|Haplo=tank;Elya=none")  -- Haplo is no longer the leader: offer
	assert(W.popup, "new offer shown")
	addon("Mallory", "M|Mallory|Mallory=tank;Elya=none")  -- the stored leader resends
	eq(W.popup, nil, "closed when the stored leader's team arrives")
end)

test("key binding actions: target leader and roles", function()
	W.me = "Elya"
	party("Haplo")
	login({}, {})
	W.units.target = "Haplo"
	HaploBox.SetLeaderName(HaploBox.UnitIdent("target"))
	eq(HB.Leader(), "Haplo", "leader from target")
	HaploBox.SetMyRole("healer")
	eq(HB.MyRole(), "healer", "role")
	W.units.target = nil
	HaploBox.SetLeaderName(HaploBox.UnitIdent("target"))
	eq(printedMatching("no target"), 1, "no target message")
end)

test("Send team button sends the team from the leader", function()
	party("Elya", "Nyra")
	login({}, standardTeam("Haplo"))
	local button = HaploBoxPartyFrame.sendButton
	eq(button.text, "Send team", "label on the leader")
	button.scripts.OnClick()
	eq(#sentMatching("^M|Haplo|"), 1, "team sent")
end)
