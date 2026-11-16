-- Extra displays on the team frame rows, all from the game's own unit data (no addon
-- messages): incoming heals on the health bar (#11), a slim cast/channel bar and the
-- five-second mana rule timer (#13). Display only: nothing here targets or casts.
-- Values the client marks secret are never compared or used in arithmetic; the
-- display then shows nothing rather than a guess.
local HB = HaploBox
local secret = HB.secret

local function num(v) return type(v) == "number" and not secret(v) end

local function safeCall(fn, ...)
	if not fn then return nil end
	local ok, a, b, c, d, e = pcall(fn, ...)
	if ok then return a, b, c, d, e end
end

local function noMouse(f) if f.EnableMouse then f:EnableMouse(false) end return f end

-- ---------------------------------------------------------------- incoming heals
-- A second bar under the health fill shows health + incoming heals. The row's own
-- health background is hidden only while that bar shows, so without data the
-- health bar looks exactly as before.
local function setPrediction(r, value, maxValue)
	local inc = r.incoming
	if not value then
		inc:Hide()
		r.health.back:SetAlpha(1)
		return
	end
	inc:SetMinMaxValues(0, maxValue)
	inc:SetValue(value)
	inc:Show()
	r.health.back:SetAlpha(0)
end

local function updatePrediction(r)
	local u = r.unit
	if not (HB.db.teamHealPrediction and u and UnitGetIncomingHeals and UnitExists(u)) then return setPrediction(r) end
	-- unit state can be restricted too: unknown state shows nothing
	local connected, dead = safeCall(UnitIsConnected, u), safeCall(UnitIsDeadOrGhost, u)
	if secret(connected) or secret(dead) or connected == false or dead then return setPrediction(r) end
	local h, m, incoming = safeCall(UnitHealth, u), safeCall(UnitHealthMax, u), safeCall(UnitGetIncomingHeals, u)
	if not (num(h) and num(m) and num(incoming)) or m <= 0 or incoming <= 0 then return setPrediction(r) end
	setPrediction(r, math.min(m, h + incoming), m)
end
HB.UpdateHealPrediction = updatePrediction

-- ---------------------------------------------------------------- cast bar
local CAST_COLOR, CHANNEL_COLOR = { 1.00, 0.82, 0.30 }, { 0.40, 0.85, 0.45 }

-- kind ("cast" or "channel"), start and end in seconds; nil when there is no cast
-- or its timing is unknown.
local function readCast(u)
	for _, entry in ipairs({ { "cast", UnitCastingInfo }, { "channel", UnitChannelInfo } }) do
		local name, _, _, startMS, endMS = safeCall(entry[2], u)
		if name ~= nil then
			if secret(name) or not (num(startMS) and num(endMS)) or endMS <= startMS then return nil end
			return entry[1], startMS / 1000, endMS / 1000
		end
	end
end

local function hideCast(r)
	r.cast:SetScript("OnUpdate", nil)
	r.cast:Hide()
	r.castInfo = nil
end

local function castTick(bar)
	local r = bar.row
	local info = r.castInfo
	local now = GetTime()
	if not info or now >= info.stop then return hideCast(r) end
	local part = (now - info.start) / (info.stop - info.start)
	bar:SetValue(info.kind == "channel" and (1 - part) or part)
end

local function updateCast(r)
	local u = r.unit
	if not (HB.db.teamCastBars and u and UnitExists(u)) then return hideCast(r) end
	local kind, start, stop = readCast(u)
	if not kind or GetTime() >= stop then return hideCast(r) end
	r.castInfo = { kind = kind, start = start, stop = stop }
	local c = kind == "channel" and CHANNEL_COLOR or CAST_COLOR
	r.cast:SetStatusBarColor(c[1], c[2], c[3])
	r.cast:Show()
	r.cast:SetScript("OnUpdate", castTick)
	castTick(r.cast)
end
HB.UpdateCastBar = updateCast

-- ---------------------------------------------------------------- five-second rule
-- Classic Era: mana regeneration from spirit stops for five seconds after mana is
-- spent. Only shown on that client; elsewhere (retail, WoW Forever unless it reports
-- itself as Classic, unknown clients) the mechanic is not known to apply.
local FSR = 5
local MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0

function HB.ManaRuleSupported()
	return WOW_PROJECT_ID ~= nil and WOW_PROJECT_CLASSIC ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CLASSIC
end

local function hideRule(r)
	r.fsr:SetScript("OnUpdate", nil)
	r.fsr:Hide()
	r.fsrUntil = nil
end

local function ruleTick(bar)
	local r = bar.row
	local left = (r.fsrUntil or 0) - GetTime()
	if left <= 0 then return hideRule(r) end
	bar:SetValue(left / FSR)
end

-- One mana reading. A drop starts the timer; regeneration and free casts do not. A drop
-- is not proof of a spend (enemy drains lower mana too), so the timer is an estimate.
-- Only a power event (fromEvent) can start it: a full refresh only takes a new
-- reading, because the last one may be old (row hidden, team changed, reload).
-- Readings are kept per character and unit, so a row that now shows someone else
-- starts over instead of comparing two characters' mana.
local function sampleMana(r, fromEvent)
	local u = r.unit
	if not (HB.db.teamManaRule and HB.ManaRuleSupported() and u and UnitExists(u)) then
		r.manaKey, r.manaLast = nil, nil
		return hideRule(r)
	end
	local ptype = safeCall(UnitPowerType, u)
	local mana = safeCall(UnitPower, u, MANA)
	if not (num(ptype) and num(mana)) or ptype ~= MANA then
		r.manaKey, r.manaLast = nil, nil
		return hideRule(r)
	end
	local key = tostring(HB.Norm(r.name)) .. "@" .. u
	if fromEvent and r.manaKey == key and r.manaLast and mana < r.manaLast then
		r.fsrUntil = GetTime() + FSR
		r.fsr:Show()
		r.fsr:SetScript("OnUpdate", ruleTick)
		ruleTick(r.fsr)
	end
	r.manaKey, r.manaLast = key, mana
end
HB.SampleMana = sampleMana

-- ---------------------------------------------------------------- hooks
local function create(r)
	local T = HB.THEME
	local inc = noMouse(CreateFrame("StatusBar", nil, r))
	inc:SetAllPoints(r.health)
	inc:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	inc:SetStatusBarColor(T.health[1], T.health[2], T.health[3], 0.45)
	inc.back = inc:CreateTexture(nil, "BACKGROUND")
	inc.back:SetAllPoints()
	inc.back:SetColorTexture(T.healthBg[1], T.healthBg[2], T.healthBg[3], T.healthBg[4] or 1)
	inc:SetFrameLevel(r.health:GetFrameLevel())
	r.health:SetFrameLevel(inc:GetFrameLevel() + 1)
	inc:Hide()
	r.incoming = inc

	local cast = noMouse(CreateFrame("StatusBar", nil, r))
	cast:SetPoint("BOTTOMLEFT", r.health, "BOTTOMLEFT")
	cast:SetPoint("BOTTOMRIGHT", r.health, "BOTTOMRIGHT")
	cast:SetHeight(3)
	cast:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	cast:SetMinMaxValues(0, 1)
	cast:SetFrameLevel(r.health:GetFrameLevel() + 2)
	cast:Hide()
	cast.row = r
	r.cast = cast

	local fsr = noMouse(CreateFrame("StatusBar", nil, r))
	fsr:SetPoint("TOPLEFT", r.power, "TOPLEFT")
	fsr:SetPoint("TOPRIGHT", r.power, "TOPRIGHT")
	fsr:SetHeight(2)
	fsr:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	fsr:SetStatusBarColor(0.85, 0.92, 1, 0.9)
	fsr:SetMinMaxValues(0, 1)
	fsr:SetFrameLevel(r.power:GetFrameLevel() + 2)
	fsr:Hide()
	fsr.row = r
	r.fsr = fsr
end

local function clear(r)
	if not r.incoming then return end
	setPrediction(r)
	hideCast(r)
	hideRule(r)
	r.manaKey, r.manaLast = nil, nil
end

local function refresh(r)
	updatePrediction(r)
	updateCast(r)
	sampleMana(r)
end

table.insert(HB.RowHooks.create, create)
table.insert(HB.RowHooks.clear, clear)
table.insert(HB.RowHooks.refresh, refresh)

for _, e in ipairs({ "UNIT_HEAL_PREDICTION", "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_CONNECTION", "UNIT_FLAGS" }) do
	HB.AddRowEvent(e, updatePrediction)
end
for _, e in ipairs({
	"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
	"UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE",
	"UNIT_SPELLCAST_CHANNEL_STOP",
}) do
	HB.AddRowEvent(e, updateCast)
end
HB.AddRowEvent("UNIT_POWER_FREQUENT", function(r, _, powerType)
	if powerType == nil or (not secret(powerType) and powerType == "MANA") then sampleMana(r, true) end
end)
HB.AddRowEvent("UNIT_DISPLAYPOWER", function(r) sampleMana(r) end)
