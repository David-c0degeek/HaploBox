test("Blizzard popup team buttons work with the HaploBox frame hidden", function()
	party("Elya")
	login({ teamFrame = "hide" }, standardTeam("Haplo"))
	local controls = HaploBoxDeathControls
	eq(controls:IsShown(), false, "no popup")
	eq(HaploBoxPartyFrame:IsShown(), false)
	StaticPopup1 = CreateFrame("Frame")
	StaticPopup1.which = "DEATH"
	W.dead = true
	HB.RefreshDeathControls()
	eq(controls:IsShown(), true)
	eq(controls.point[2], StaticPopup1, "anchored to Blizzard popup")
	eq(controls.point[3], "BOTTOM", "below popup")
	controls.release.scripts.OnClick()
	eq(#sentMatching("^D|release$"), 1)
	eq(W.released, 1, "dead leader releases too")
	W.ghost = true
	controls.release.scripts.OnClick()
	eq(W.released, 1, "ghost is not released again")
	W.deathPopup = "RECOVER_CORPSE"
	controls.resurrect.scripts.OnClick()
	eq(#sentMatching("^D|resurrect$"), 1)
	eq(W.retrieved, 1)
end)

test("followers accept exact death commands only from the stored leader in group", function()
	W.me = "Elya"
	party("Haplo", "Nyra")
	login({ teamFrame = "show" }, standardTeam("Haplo"))
	eq(HaploBoxDeathControls:IsShown(), false)
	W.dead = true
	addon("Nyra", "D|release")
	addon("Mallory", "D|release")
	addon("Haplo", "D|release", "WHISPER")
	addon("Haplo", "D|release|extra")
	addon("Haplo", "D|unknown")
	HB.TeamDeathAction("release")
	eq(W.released, nil)
	eq(#sentMatching("^D|"), 0, "followers cannot command the team")
	addon("Haplo-Forever", "D|release")
	eq(W.released, 1)
	addon("Elya", "D|release")
	eq(W.released, 1, "self echoes ignored")
end)

test("team buttons follow popup reuse and hide for unrelated popups or a living leader", function()
	party("Elya")
	login({}, standardTeam("Haplo"))
	StaticPopup2 = CreateFrame("Frame")
	local controls = HaploBoxDeathControls
	W.dead = true
	for _, which in ipairs({ "DEATH", "SKINNED_REPOP", "RESURRECT", "RESURRECT_NO_SICKNESS",
		"RESURRECT_NO_TIMER", "RECOVER_CORPSE", "RECOVER_CORPSE_INSTANCE" }) do
		StaticPopup2.which = which
		HB.RefreshDeathControls()
		eq(controls:IsShown(), true, which)
		eq(controls.point[2], StaticPopup2)
	end
	StaticPopup2:Hide()
	HB.RefreshDeathControls()
	eq(controls:IsShown(), false, "popup closed")
	StaticPopup2:Show()
	StaticPopup2.which = "PARTY_INVITE"
	HB.RefreshDeathControls()
	eq(controls:IsShown(), false, "unrelated popup")
	StaticPopup2.which = "DEATH"
	W.dead = false
	HB.RefreshDeathControls()
	eq(controls:IsShown(), false, "alive")
	W.dead, W.me = true, "Elya"
	HB.RefreshDeathControls()
	eq(controls:IsShown(), false, "follower")
end)

test("rezz accepts each offered resurrection and skips living characters", function()
	W.me = "Elya"
	party("Haplo")
	login({}, standardTeam("Haplo"))
	W.deathPopup = "RESURRECT"
	addon("Haplo", "D|resurrect")
	eq(W.resurrected, nil, "alive")
	W.dead = true
	addon("Haplo", "D|resurrect")
	eq(W.resurrected, 1)
	W.deathPopup = "RESURRECT_NO_SICKNESS"
	addon("Haplo", "D|resurrect")
	eq(W.resurrected, 2)
	W.corpseDelay = 10
	addon("Haplo", "D|resurrect")
	eq(W.resurrected, 2, "offer timer respected")
	W.deathPopup = "RESURRECT_NO_TIMER"
	addon("Haplo", "D|resurrect")
	eq(W.resurrected, 3, "untimed offer")
end)

test("corpse reclaim requires ghost, range and expired timer without deferred action", function()
	party("Elya")
	login({}, standardTeam("Haplo"))
	W.dead = true
	W.deathPopup = "RECOVER_CORPSE"
	HB.TeamDeathAction("resurrect")
	eq(W.retrieved, nil, "not a ghost")
	W.ghost, W.corpseDelay = true, 20
	HB.TeamDeathAction("resurrect")
	eq(W.retrieved, nil, "timer")
	W.corpseDelay = 0
	advance(30)
	eq(W.retrieved, nil, "no deferred resurrection")
	W.deathPopup = nil
	HB.TeamDeathAction("resurrect")
	eq(W.retrieved, nil, "out of range")
	W.deathPopup = "XP_LOSS"
	HB.TeamDeathAction("resurrect")
	eq(W.retrieved, nil, "spirit healer excluded")
	W.deathPopup = "RECOVER_CORPSE"
	HB.TeamDeathAction("resurrect")
	eq(W.retrieved, 1)
end)

test("release respects client restrictions and missing APIs are harmless", function()
	party("Elya")
	login({}, standardTeam("Haplo"))
	W.dead = true
	IsEncounterSuppressingRelease = function() return true end
	HB.TeamDeathAction("release")
	eq(W.released, nil)
	IsEncounterSuppressingRelease = nil
	HasNoReleaseAura = function() return true end
	HB.TeamDeathAction("release")
	eq(W.released, nil)
	HasNoReleaseAura = nil
	IsFalling = function() return true end
	HB.TeamDeathAction("release")
	eq(W.released, nil)
	IsFalling = nil
	RepopMe, AcceptResurrect, RetrieveCorpse = nil, nil, nil
	HB.TeamDeathAction("release")
	HB.TeamDeathAction("resurrect")
	eq(W.released, nil)
end)
