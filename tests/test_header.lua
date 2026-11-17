-- Team frame rows from the game's secure group header (#2).

local function kid(i) return HaploBoxHeaderUnitButton1 and _G["HaploBoxHeaderUnitButton" .. i] end

local function setup(db, units)
	W.header = true
	party(unpack(units or { "Elya", "Nyra" }))
	login(db or {}, standardTeam("Haplo"))
end

local function shownKids()
	local out = {}
	if HaploBoxHeader.shown == false then return out end  -- children of a hidden header are not visible
	for i = 1, 5 do
		local c = kid(i)
		if c and c.shown ~= false and c.attrs.unit then out[#out + 1] = c end
	end
	return out
end

test("five header rows are made out of combat and follow the team order", function()
	setup()
	for i = 1, 5 do assert(kid(i), "row " .. i .. " made") end
	eq(HaploBoxHeader.attrs.nameList, "Haplo,Elya,Nyra", "team order")
	eq(HaploBoxHeader.attrs.unitsPerColumn, 5, "capped at five")
	local k = shownKids()
	eq(#k, 3, "three in the group")
	eq(k[1].name, "Haplo", "leader first")
	eq(k[2].attrs.unit, "party1", "Elya's row targets party1")
	eq(k[2].attrs.type1, "target", "clickable")
	eq(ClickCastFrames[k[2]], true, "Clique")
	eq(HB.TeamHeaderActive(), true, "header in use")
end)

test("someone outside the team gets no row; a team member outside the group gets AWAY", function()
	setup({}, { "Elya", "Mallory" })
	eq(HaploBoxHeader.attrs.nameList, "Haplo,Elya,Nyra", "the whole team; Mallory is not in it")
	for _, c in ipairs(shownKids()) do assert(c.name ~= "Mallory", "no row for an outsider") end
	eq(HaploBoxAwayRow1.name, "Nyra", "Nyra is away")
	eq(HaploBoxAwayRow1.attrs and HaploBoxAwayRow1.attrs.type1, nil, "away row has nothing to click")
end)

test("in combat the game rebinds the rows and every label matches its unit", function()
	setup({}, { "Elya", "Nyra" })
	W.combat = true
	W.units = { party1 = "Nyra" }  -- Elya leaves in combat; Nyra moves to party1
	fire("GROUP_ROSTER_UPDATE")
	for _, c in ipairs(shownKids()) do
		eq(HB.Norm(c.name), HB.Norm(UnitName(c.attrs.unit)), "label is the bound unit's name")
		eq(c.stale, nil, "no stale state needed")
	end
	eq(#shownKids(), 2, "Haplo and Nyra")
end)

test("a team member who joins in combat gets a secure row at once", function()
	setup({}, { "Elya" })
	eq(HaploBoxAwayRow1.name, "Nyra", "Nyra away")
	W.combat = true
	W.units = { party1 = "Elya", party2 = "Nyra" }
	fire("GROUP_ROSTER_UPDATE")
	local found
	for _, c in ipairs(shownKids()) do
		if c.name == "Nyra" then found = c end
		eq(HB.Norm(c.name), HB.Norm(UnitName(c.attrs.unit)), "label matches")
	end
	assert(found, "Nyra has a header row in combat")
	eq(found.attrs.unit, "party2", "bound to party2")
	W.combat = false
	fire("PLAYER_REGEN_ENABLED")
	eq(HaploBoxAwayRow1.shown, false, "AWAY row gone after combat")
end)

test("Elya at party1 leaves in combat: the row that keeps party1 now says Nyra", function()
	setup({}, { "Elya", "Nyra" })
	local row = kid(2)
	eq(row.attrs.unit, "party1", "Elya's row")
	eq(row.name, "Elya", "labelled Elya")
	W.combat = true
	W.units = { party1 = "Nyra" }
	fire("GROUP_ROSTER_UPDATE")
	eq(row.attrs.unit, "party1", "same token, no attribute change")
	eq(row.name, "Nyra", "label follows the person behind the token")
end)

test("the same unit token with a new person gets the new name", function()
	setup({}, { "Elya", "Nyra" })
	W.combat = true
	HaploBoxTeam.order = { "Haplo", "Elya", "Nyra", "Vex" }
	W.units = { party1 = "Elya", party2 = "Vex" }  -- Nyra swapped for Vex at party2
	fire("GROUP_ROSTER_UPDATE")
	for _, c in ipairs(shownKids()) do
		eq(HB.Norm(c.name), HB.Norm(UnitName(c.attrs.unit)), "label matches " .. c.attrs.unit)
	end
end)

test("unit events reach the row bound to that unit only", function()
	setup()
	W.combat = true
	W.units = { party1 = "Nyra" }
	fire("GROUP_ROSTER_UPDATE")
	local nyra
	for _, c in ipairs(shownKids()) do if c.name == "Nyra" then nyra = c end end
	assert(nyra, "Nyra has a row")
	W.health = { party1 = 10 }
	fire("UNIT_HEALTH", "party1")
	eq(nyra.health.value, 10, "Nyra's row got party1's health")
end)

test("a raid hides the header rows and falls back to direct rows after combat", function()
	setup()
	W.combat = true
	W.raid = true
	fire("GROUP_ROSTER_UPDATE")
	eq(#shownKids(), 0, "no header rows in a raid, not wrong ones")
	W.combat = false
	fire("PLAYER_REGEN_ENABLED")
	eq(HB.TeamHeaderActive(), false, "direct rows")
	assert(HaploBoxPartyRow1 and HaploBoxPartyRow1.shown, "direct rows shown")
end)

test("a header row the game made but HaploBox did not set up cannot be clicked", function()
	setup()
	local h = HaploBoxHeader
	h.attrs.unitsPerColumn = 6
	W.units = { party1 = "Elya", party2 = "Nyra", party3 = "A", party4 = "B" }
	HaploBoxTeam.order = { "Haplo", "Elya", "Nyra", "A", "B", "C" }
	h:SetAttribute("startingIndex", -5)
	local extra = h.attrs.child6
	assert(extra, "an extra row exists")
	eq(extra.attrs.type1, nil, "no click action")
end)

test("Mini Heal and sizes apply to the header rows; turning it off uses direct rows", function()
	setup({ teamView = "mini", teamMiniW = 120 })
	eq(kid(2).bg.width, 120, "mini width")
	eq(kid(2).power.shown, false, "mini layout")
	HB.SetOption("teamHeader", false)
	eq(HB.TeamHeaderActive(), false, "off")
	eq(#shownKids(), 0, "header rows hidden")
	assert(HaploBoxPartyRow1.shown, "direct rows")
end)

test("logging in solo, then grouping, still gets the header rows", function()
	W.header = true
	login({}, standardTeam("Haplo"))
	eq(HaploBoxPartyFrame.shown, false, "hidden solo")
	party("Elya", "Nyra")
	fire("GROUP_ROSTER_UPDATE")
	eq(HB.TeamHeaderActive(), true, "header rows after joining")
	eq(#shownKids(), 3, "three rows")
end)

test("without the template the direct rows are used", function()
	W.header = false
	party("Elya", "Nyra")
	login({}, standardTeam("Haplo"))
	eq(HaploBoxHeader, nil, "no header")
	assert(HaploBoxPartyRow1.shown, "direct rows")
end)

test("team names spelt differently from the game still get their secure rows", function()
	W.header = true
	party("Elya", "Nyra-Other")
	login({}, { leader = "haplo-forever", order = { "haplo-forever", "elya", "nyra-other" }, roles = {} })
	eq(HaploBoxHeader.attrs.nameList, "Haplo,Elya,Nyra-Other", "the game's own spelling")
	local k = shownKids()
	eq(#k, 3, "a row for each member in the party")
	eq(k[2].attrs.unit, "party1", "elya -> Elya")
	eq(k[3].attrs.unit, "party2", "nyra-other -> Nyra-Other")
	eq(HaploBoxAwayRow1 == nil or HaploBoxAwayRow1.shown == false, true, "no away rows")
end)

test("a two-toon party of a bigger team: two secure rows, the rest away", function()
	W.header = true
	W.me = "Elya"
	party("Nyra")
	login({ teamFrame = "show" }, { leader = "Haplo", order = { "Haplo", "Elya", "Nyra", "Vex", "Mora" }, roles = {} })
	eq(#shownKids(), 2, "Elya and Nyra")
	eq(HaploBoxAwayRow3 and HaploBoxAwayRow3.name, "Mora", "three away")
end)

test("WoW Forever names with a surname get their secure rows", function()
	-- the team list holds "Name Surname" (GetUnitName); the header builds its key from
	-- UnitName's two values joined with "-", as the upstream header code does
	W.header = true
	W.me = "Haplina Willow"
	party("Haplina Purr")
	login({ teamFrame = "show" }, { leader = "Haplina Willow", order = { "Haplina Willow", "Haplina Purr", "Haplina Vex" }, roles = {} })
	eq(HaploBoxHeader.attrs.nameList, "Haplina-Willow,Haplina-Purr,Haplina Vex", "present members in the header's own form")
	eq(#shownKids(), 2, "both toons in the party have rows")
	eq(HaploBoxAwayRow1.name, "Haplina Vex", "the absent one is away")
end)
