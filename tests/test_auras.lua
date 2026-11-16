-- Heal-over-time icons, required buffs and the aura overviews (#12).

local function rowFor(unit)
	for i = 1, 10 do
		local r = _G["HaploBoxPartyRow" .. i]
		if r and r.unit == unit then return r end
	end
	error("no row for " .. unit)
end

local function aura(name, left, source, dispel)
	return {
		name = name, icon = name, duration = left and 15 or 0,
		expirationTime = left and (W.now + left) or 0, sourceUnit = source, dispelName = dispel,
	}
end

local function setup(db)
	party("Elya", "Nyra")
	login(db or {}, standardTeam("Haplo"))
	return rowFor("party1")
end

-- ---------------------------------------------------------------- reading
test("the aura reader drops expired auras and sorts by time left", function()
	setup()
	W.auras = { party1 = { HELPFUL = {
		aura("Lasting", nil), aura("Late", 30), aura("Gone", -1), aura("Soon", 5),
	} } }
	local list = HB.ReadAuras("party1", "HELPFUL")
	eq(#list, 3, "expired dropped")
	eq(list[1].name, "Soon", "first")
	eq(list[2].name, "Late", "second")
	eq(list[3].name, "Lasting", "lasting last")
end)

test("restricted, failing or missing aura data is unknown", function()
	setup()
	W.auras = { party1 = { HELPFUL = { aura("Renew", 10, "player") } } }
	W.secrets = { Renew = true }
	eq(HB.ReadAuras("party1", "HELPFUL"), nil, "secret name")
	W.secrets = nil
	W.auraError = true
	eq(HB.ReadAuras("party1", "HELPFUL"), nil, "error")
	W.auraError = nil
	W.auraEndless = true
	local list, complete = HB.ReadAuras("party1", "HELPFUL")
	eq(#list, 40, "a broken API is read at most 40 times")
	eq(complete, false, "and the list says it may be partial")
	W.auraEndless = nil
	local api = C_UnitAuras
	C_UnitAuras = nil
	eq(HB.ReadAuras("party1", "HELPFUL"), nil, "no API on this client")
	C_UnitAuras = api
end)

-- ---------------------------------------------------------------- HoTs
test("HoT icons show group HoTs from the built-in list, at most four", function()
	local r = setup()
	W.auras = { party1 = { HELPFUL = {
		aura("Renew", 12, "player"), aura("Rejuvenation", 9, "party2"), aura("Regrowth", 20, nil),
		aura("Arcane Intellect", nil, "player"),
	} } }
	fire("UNIT_AURA", "party1")
	local shown = 0
	for _, b in ipairs(r.hots) do if b.shown then shown = shown + 1 end end
	eq(shown, 2, "Renew and Rejuvenation; Regrowth has no group caster, Arcane Intellect is no HoT")
	eq(r.hots[1].time.text, "9", "soonest first, seconds left")
	HB.SetOption("teamShowHots", false)
	fire("UNIT_AURA", "party1")
	eq(r.hots[1].shown, false, "off")
end)

test("HoT icons sit inside the health bar, with the time on the icon", function()
	local r = setup()
	local barH = r.health.height
	eq(r.hots[1].height <= barH - 2, true, "fits the main bar (" .. tostring(r.hots[1].height) .. " in " .. tostring(barH) .. ")")
	eq(r.hots[1].point[1], "LEFT", "centred on the bar")
	eq(r.hots[1].time.point[1], "CENTER", "time inside the icon")
	HB.SetOption("teamView", "mini")
	eq(r.hots[1].point[1], "BOTTOMLEFT", "Mini Heal: along the bottom of the tile")
end)

test("a HoT that runs out disappears on the next tick", function()
	local r = setup()
	W.auras = { party1 = { HELPFUL = { aura("Renew", 2, "player") } } }
	fire("UNIT_AURA", "party1")
	eq(r.hots[1].shown, true, "shown")
	advance(3)
	HB.UpdateRowAuras(r)  -- what the one-second ticker does
	eq(r.hots[1].shown, false, "gone, not shown at zero")
end)

test("custom HoT names replace the built-in list", function()
	local r = setup()
	HB.SetOption("teamHotNames", " Earth Shield ,  Renew|")
	eq(HB.db.teamHotNames, "Earth Shield ,  Renew", "trimmed, no escape codes")
	W.auras = { party1 = { HELPFUL = { aura("Earth Shield", 30, "player"), aura("Rejuvenation", 5, "player") } } }
	fire("UNIT_AURA", "party1")
	eq(r.hots[1].shown, true, "Earth Shield")
	eq(r.hots[2].shown, false, "Rejuvenation not in the custom list")
end)

-- ---------------------------------------------------------------- required buffs
test("required buffs: missing, present and unknown are told apart", function()
	local r = setup()
	HB.SetOption("teamRequiredBuffs", "Power Word: Fortitude, Arcane Intellect")
	W.auras = { party1 = { HELPFUL = { aura("Arcane Intellect", nil, "player") } } }
	fire("UNIT_AURA", "party1")
	assert(r.required.text:find("no power word: fortitude"), "missing named: " .. tostring(r.required.text))
	W.auras.party1.HELPFUL[2] = aura("Power Word: Fortitude", nil, "target")
	fire("UNIT_AURA", "party1")
	eq(r.required.text, "", "all there (any source counts)")
	W.auraError = true
	fire("UNIT_AURA", "party1")
	assert(r.required.text:find("buffs %?"), "unknown")
	W.auraError = nil
	fire("UNIT_AURA", "party1")
	eq(r.required.text, "", "known again")
	HB.SetOption("teamRequiredBuffs", "")
	eq(r.required.text, "", "off")
end)

test("a required buff beyond the 40 read is unknown, not missing", function()
	local r = setup()
	HB.SetOption("teamRequiredBuffs", "Arcane Intellect")
	W.auraEndless = true
	fire("UNIT_AURA", "party1")
	assert(r.required.text:find("buffs %?"), "partial list: " .. tostring(r.required.text))
	HB.SetOption("teamBuffOverview", true)
	advance(1)
	eq(HB.AuraOverview("buffs").lines[2].icons[8].time.text, "+33?", "overview says it is partial")
	W.auraEndless = nil
end)

test("an offline member's auras are unknown, also when the client returns old data", function()
	local r = setup()
	HB.SetOption("teamRequiredBuffs", "Renew")
	W.auras = { party1 = { HELPFUL = { aura("Renew", 12, "player") } } }
	fire("UNIT_AURA", "party1")
	eq(r.hots[1].shown, true, "online: shown")
	local online = UnitIsConnected
	UnitIsConnected = function(u) return u ~= "party1" end
	HB.UpdateRowAuras(r)
	eq(r.hots[1].shown, false, "offline: cached HoT hidden")
	assert(r.required.text:find("buffs %?"), "offline: unknown, not present")
	W.auras.party1.HELPFUL = {}
	HB.UpdateRowAuras(r)
	assert(r.required.text:find("buffs %?"), "offline with an empty list: unknown, not missing")
	HB.SetOption("teamBuffOverview", true)
	advance(1)
	eq(HB.AuraOverview("buffs").lines[2].note.text, "offline", "overview")
	UnitIsConnected = online
	W.auras.party1.HELPFUL = { aura("Renew", 12, "player") }
	HB.UpdateRowAuras(r)
	eq(r.required.text, "", "back online: present")
	eq(r.hots[1].shown, true, "back online: HoT")
end)

test("a stale row drops HoTs and required-buff text", function()
	local r = setup()
	HB.SetOption("teamRequiredBuffs", "Arcane Intellect")
	W.auras = { party1 = { HELPFUL = { aura("Renew", 12, "player") } } }
	fire("UNIT_AURA", "party1")
	W.combat = true
	W.units.party1 = "Mallory"
	fire("GROUP_ROSTER_UPDATE")
	eq(r.hots[1].shown, false, "HoT gone")
	eq(r.required.text, "", "text gone")
	W.combat = false
end)

-- ---------------------------------------------------------------- overviews
test("overviews list every row in team order, off by default", function()
	setup()
	eq(HB.AuraOverview("debuffs"), nil, "not created while off")
	W.auras = { party1 = { HARMFUL = { aura("Curse of Agony", 10, nil, "Curse") } } }
	HB.SetOption("teamDebuffOverview", true)
	advance(1)
	local o = HB.AuraOverview("debuffs")
	eq(o.shown, true, "shown")
	eq(o.lines[1].name.text, "Haplo", "leader first")
	eq(o.lines[2].name.text, "Elya", "then the team order")
	eq(o.lines[2].icons[1].shown, true, "Elya's curse")
	eq(o.lines[3].note.text, "-", "Nyra: no debuffs")
	eq(o.title.scripts.OnDragStart ~= nil, true, "title bar drags")
	eq(o.lines[2].icons[1].mouse, false, "icons never take the mouse")
	eq(o.lines[2].mouse, false, "lines never take the mouse")
	eq(o.mouse, false, "the window body never takes the mouse")
	eq(o.title.mouse, true, "only the title bar does")
	HB.SetOption("teamDebuffOverview", false)
	advance(1)
	eq(o.shown, false, "hidden when turned off")
end)

test("overview lines overflow with a count and say unknown when data is restricted", function()
	setup()
	local many = {}
	for i = 1, 12 do many[i] = aura("Buff" .. i, nil, "player") end
	W.auras = { party1 = { HELPFUL = many } }
	HB.SetOption("teamBuffOverview", true)
	advance(1)
	local line = HB.AuraOverview("buffs").lines[2]
	eq(line.icons[8].time.text, "+5", "seven icons and +5")
	W.auraError = true
	HB.RefreshAuraOverviews()
	eq(line.note.text, "unknown", "restricted")
	W.auraError = nil
end)

test("saved overview positions are checked", function()
	eq(HB.ClampAuraPos({ x = 0.5, y = 0.25 }).x, 0.5, "kept")
	eq(HB.ClampAuraPos({ x = 3, y = -1 }).x, 1, "clamped x")
	eq(HB.ClampAuraPos({ x = 3, y = -1 }).y, 0, "clamped y")
	eq(HB.ClampAuraPos({ x = 0 / 0, y = 0.5 }), nil, "NaN refused")
	eq(HB.ClampAuraPos({ x = math.huge, y = 0.5 }), nil, "infinity refused")
	eq(HB.ClampAuraPos("left"), nil, "not a position")
end)
