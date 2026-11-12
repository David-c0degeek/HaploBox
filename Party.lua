-- HaploBox party frame: one row per team member with health, power and follow status.
-- Rows are secure unit buttons: left-click targets the member, and [@mouseover]
-- macros work on them. Secure attributes and visibility only change out of combat.
-- Health values may be secret on this client: they go straight into StatusBars and
-- FontStrings, never into Lua arithmetic or comparisons.
local HB = HaploBox

local ROW_H, ROW_W, BOX_W, GAP = 38, 250, 56, 3
local MEDIA = "Interface\\AddOns\\HaploBox\\Media\\"

local C = {
	rowBg    = { 0.16, 0.17, 0.20, 0.92 },
	name     = { 1.00, 0.60, 0.20 },
	health   = { 0.98, 0.55, 0.13 },
	healthBg = { 0.30, 0.17, 0.08, 0.90 },
	power    = { 0.30, 0.55, 0.95 },
	powerBg  = { 0.12, 0.14, 0.20, 0.90 },
	ok       = { 0.17, 0.33, 0.20, 0.95 },
	broken   = { 0.55, 0.16, 0.14, 0.95 },
	unknown  = { 0.25, 0.25, 0.28, 0.95 },
}

local secret = function(v) return issecretvalue and issecretvalue(v) end
local container, rows = nil, {}
local unitRow = {}          -- unit token -> row
local pendingLayout = false
local displayPrefix         -- shared first word of all team names, hidden in the rows

-- ---------------------------------------------------------------- team
-- Team names in display order: HaploBoxTeam.order, else leader, tank, healer, dps.
function HB.TeamOrder()
	local team, out, seen = HaploBoxTeam or {}, {}, {}
	local function add(n)
		local k = HB.Norm(n)
		if k and not seen[k] then seen[k] = true out[#out + 1] = n end
	end
	if type(team.order) == "table" and #team.order > 0 then
		for _, n in ipairs(team.order) do add(n) end
	else
		add(HB.Leader())
		local rank = { tank = 1, healer = 2, dps = 3 }
		local names = {}
		for n in pairs(team.roles or {}) do names[#names + 1] = n end
		table.sort(names, function(a, b)
			local ra, rb = rank[team.roles[a]] or 4, rank[team.roles[b]] or 4
			if ra ~= rb then return ra < rb end
			return a < b
		end)
		for _, n in ipairs(names) do add(n) end
	end
	-- anyone with a role but missing from the order goes at the end
	add(HB.Leader())
	local extra = {}
	for n in pairs(team.roles or {}) do extra[#extra + 1] = n end
	table.sort(extra)
	for _, n in ipairs(extra) do add(n) end
	return out
end

local function unitForName(name)
	local key = HB.Norm(name)
	if not key then return nil end
	if HB.Norm(HB.UnitIdent("player")) == key then return "player" end
	if not IsInGroup() then return nil end
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			local u = "raid" .. i
			if HB.Norm(HB.UnitIdent(u)) == key then return u end
		end
	else
		for i = 1, 4 do
			local u = "party" .. i
			if UnitExists(u) and HB.Norm(HB.UnitIdent(u)) == key then return u end
		end
	end
end

local function sharedPrefix(names)
	local first
	for _, n in ipairs(names) do
		local w = n:match("^(%S+)%s+%S")
		if not w then return nil end
		if first and first ~= w then return nil end
		first = w
	end
	return #names > 1 and first or nil
end

local function displayName(name)
	if displayPrefix then
		local rest = name:match("^" .. displayPrefix:gsub("(%W)", "%%%1") .. "%s+(.+)$")
		if rest then return rest end
	end
	return (name:gsub("%-.*$", ""))
end

-- ---------------------------------------------------------------- rows
local function solid(parent, layer, c)
	local t = parent:CreateTexture(nil, layer)
	t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
	return t
end

local function bar(parent, fg, bg, h)
	local b = CreateFrame("StatusBar", nil, parent)
	b:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	b:SetStatusBarColor(fg[1], fg[2], fg[3])
	b:SetHeight(h)
	b:SetMinMaxValues(0, 1)
	b:SetValue(0)
	local back = solid(b, "BACKGROUND", bg)
	back:SetAllPoints()
	return b
end

local function createRow(i)
	local r = CreateFrame("Button", "HaploBoxPartyRow" .. i, container, "SecureUnitButtonTemplate")
	r:SetSize(ROW_W + GAP + BOX_W, ROW_H)
	r:RegisterForClicks("AnyUp")
	r:SetAttribute("type1", "target")
	r:RegisterForDrag("LeftButton")
	r:SetScript("OnDragStart", function()
		if IsShiftKeyDown() and not InCombatLockdown() then container:StartMoving() end
	end)
	r:SetScript("OnDragStop", function() HB.SavePartyPosition() end)

	local bg = solid(r, "BACKGROUND", C.rowBg)
	bg:SetPoint("TOPLEFT")
	bg:SetSize(ROW_W, ROW_H)

	r.nameText = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	r.nameText:SetPoint("TOPLEFT", 6, -4)
	r.nameText:SetTextColor(C.name[1], C.name[2], C.name[3])
	r.nameText:SetJustifyH("LEFT")

	r.pctText = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.pctText:SetPoint("TOPRIGHT", r, "TOPLEFT", ROW_W - 6, -5)
	r.pctText:SetJustifyH("RIGHT")

	r.health = bar(r, C.health, C.healthBg, 13)
	r.health:SetPoint("TOPLEFT", 6, -19)
	r.health:SetWidth(ROW_W - 12)

	r.power = bar(r, C.power, C.powerBg, 4)
	r.power:SetPoint("TOPLEFT", r.health, "BOTTOMLEFT", 0, -3)
	r.power:SetWidth(ROW_W - 12)

	local box = CreateFrame("Frame", nil, r)
	box:SetPoint("TOPLEFT", r, "TOPLEFT", ROW_W + GAP, 0)
	box:SetSize(BOX_W, ROW_H)
	box.bg = solid(box, "BACKGROUND", C.unknown)
	box.bg:SetAllPoints()
	box.icon = box:CreateTexture(nil, "ARTWORK")
	box.icon:SetSize(16, 16)
	box.icon:SetPoint("TOP", 0, -4)
	box.label = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	box.label:SetPoint("BOTTOM", 0, 4)
	box.label:SetFont(box.label:GetFont(), 9, "")
	r.box = box
	return r
end

local function setBox(r, kind)
	local b = r.box
	local c, icon, label
	if kind == "leader" then c, icon, label = C.ok, "crown", "LEADER"
	elseif kind == "S" then c, icon, label = C.ok, "link", "FOLLOW"
	elseif kind == "X" then c, icon, label = C.broken, "link-broken", "BROKEN"
	else c, icon, label = C.unknown, nil, kind == "away" and "AWAY" or "?" end
	b.bg:SetColorTexture(c[1], c[2], c[3], c[4])
	if icon then b.icon:SetTexture(MEDIA .. icon) b.icon:Show() else b.icon:Hide() end
	b.label:SetText(label)
end

-- ---------------------------------------------------------------- updates
local function safe(fn, ...)
	local ok, v = pcall(fn, ...)
	if ok and not secret(v) then return v end
end

local function updateHealth(r)
	local u = r.unit
	if not u or not UnitExists(u) then
		r.health:SetMinMaxValues(0, 1) r.health:SetValue(0)
		r.pctText:SetText("")
		return
	end
	if safe(UnitIsConnected, u) == false then r.pctText:SetText("|cff999999offline|r") r.health:SetValue(0) return end
	if safe(UnitIsDeadOrGhost, u) then r.pctText:SetText("|cffff5555dead|r") r.health:SetValue(0) return end
	local h, m = UnitHealth(u), UnitHealthMax(u)
	r.health:SetMinMaxValues(0, m)
	r.health:SetValue(h)
	if not secret(h) and not secret(m) then
		r.pctText:SetText(m > 0 and (math.floor(h / m * 100 + 0.5) .. "%") or "")
	elseif UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 then
		local ok = pcall(function()
			r.pctText:SetFormattedText("%.0f%%", UnitHealthPercent(u, true, CurveConstants.ScaleTo100))
		end)
		if not ok then r.pctText:SetText("") end
	else
		r.pctText:SetText("")
	end
end

local function updatePower(r)
	local u = r.unit
	if not u or not UnitExists(u) then r.power:SetMinMaxValues(0, 1) r.power:SetValue(0) return end
	local _, token = UnitPowerType(u)
	local col = token and not secret(token) and PowerBarColor and PowerBarColor[token]
	if col then r.power:SetStatusBarColor(col.r, col.g, col.b) else r.power:SetStatusBarColor(C.power[1], C.power[2], C.power[3]) end
	r.power:SetMinMaxValues(0, UnitPowerMax(u))
	r.power:SetValue(UnitPower(u))
end

local function updateStatus(r)
	if HB.IsLeaderName(r.name) then setBox(r, "leader") return end
	if not r.unit then setBox(r, "away") return end
	setBox(r, HB.followState and HB.followState[HB.Norm(r.name)])
end

local function updateRange(r)
	local u = r.unit
	if not u then r:SetAlpha(0.45) return end
	if u == "player" then r:SetAlpha(1) return end
	local ok, inRange, checked = pcall(UnitInRange, u)
	if not ok then r:SetAlpha(1) return end
	if secret(inRange) then
		if r.SetAlphaFromBoolean then pcall(r.SetAlphaFromBoolean, r, inRange, 1, 0.5) else r:SetAlpha(1) end
	elseif checked == false or secret(checked) then
		r:SetAlpha(1)
	else
		r:SetAlpha(inRange and 1 or 0.5)
	end
end

local function updateRow(r)
	updateHealth(r) updatePower(r) updateStatus(r) updateRange(r)
end

function HB.RefreshPartyFrame()
	for _, r in ipairs(rows) do if r:IsShown() then updateRow(r) end end
end

function HB.OnFollowStateChanged()
	for _, r in ipairs(rows) do if r:IsShown() then updateStatus(r) end end
end

-- ---------------------------------------------------------------- layout (out of combat only)
local function wanted()
	local mode = HB.db.partyFrame
	if mode == "off" then return false end
	if mode == "leader" and not HB.IAmLeader() then return false end
	if not IsInGroup() and not HB.db.partyFrameSolo then return false end
	return #HB.TeamOrder() > 0
end

function HB.LayoutPartyFrame()
	if not container then return end
	if InCombatLockdown() then pendingLayout = true return end
	pendingLayout = false
	container:SetScale(HB.db.partyScale or 1)
	if not wanted() then container:Hide() return end
	local names = HB.TeamOrder()
	displayPrefix = sharedPrefix(names)
	wipe(unitRow)
	for i, name in ipairs(names) do
		local r = rows[i] or createRow(i)
		rows[i] = r
		r.name = name
		r.unit = unitForName(name)
		r:SetAttribute("unit", r.unit)
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -(i - 1) * (ROW_H + GAP))
		r.nameText:SetText(displayName(name))
		if r.unit then unitRow[r.unit] = r end
		r:Show()
	end
	for i = #names + 1, #rows do rows[i]:Hide() rows[i]:SetAttribute("unit", nil) end
	container:SetSize(ROW_W + GAP + BOX_W, #names * (ROW_H + GAP) - GAP)
	container:Show()
	HB.RefreshPartyFrame()
end

function HB.SavePartyPosition()
	if not container then return end
	container:StopMovingOrSizing()
	local point, _, rel, x, y = container:GetPoint()
	HB.db.partyPos = { point, rel, x, y }
end

local function applyPosition()
	local p = HB.db.partyPos
	container:ClearAllPoints()
	if p then container:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else container:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -200) end
end

function HB.ResetPartyPosition()
	if InCombatLockdown() then HB.print("not in combat") return end
	HB.db.partyPos = nil
	applyPosition()
end

-- ---------------------------------------------------------------- events
local ev = CreateFrame("Frame")
local unitEvents = {
	UNIT_HEALTH = updateHealth, UNIT_MAXHEALTH = updateHealth, UNIT_CONNECTION = updateRow,
	UNIT_POWER_UPDATE = updatePower, UNIT_POWER_FREQUENT = updatePower,
	UNIT_MAXPOWER = updatePower, UNIT_DISPLAYPOWER = updatePower,
	UNIT_FLAGS = updateHealth,
}

ev:SetScript("OnEvent", function(_, event, arg1)
	if event == "PLAYER_LOGIN" then
		container = CreateFrame("Frame", "HaploBoxPartyFrame", UIParent)
		container:SetMovable(true)
		container:SetClampedToScreen(true)
		applyPosition()
		HB.LayoutPartyFrame()
		C_Timer.NewTicker(0.5, function()
			if container:IsShown() then for _, r in ipairs(rows) do if r:IsShown() then updateRange(r) updateHealth(r) end end end
		end)
		return
	end
	if not container then return end
	local fn = unitEvents[event]
	if fn then
		local r = arg1 and unitRow[arg1]
		if r and r:IsShown() then pcall(fn, r) end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if pendingLayout then HB.LayoutPartyFrame() end
	else  -- GROUP_ROSTER_UPDATE, PLAYER_ENTERING_WORLD, UNIT_NAME_UPDATE
		HB.LayoutPartyFrame()
	end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "UNIT_NAME_UPDATE" }) do
	pcall(ev.RegisterEvent, ev, e)
end
for e in pairs(unitEvents) do pcall(ev.RegisterEvent, ev, e) end
