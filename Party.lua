-- HaploBox party frame: one row per team member with health, power and follow status.
-- Rows are secure unit buttons: left-click targets the member, and [@mouseover]
-- macros work on them. Secure attributes and visibility only change out of combat.
-- Health values may be secret on this client: they go straight into StatusBars and
-- FontStrings, never into Lua arithmetic or comparisons.
local HB = HaploBox

local BOX_W, GAP = 56, 3  -- row width and height are settings (teamW, teamRowH)
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

-- ---------------------------------------------------------------- sizes
local MIN_W, MAX_W, MIN_H, MAX_H = 150, 500, 28, 70
local function rowW() return math.min(MAX_W, math.max(MIN_W, HB.db.teamW or 250)) end
local function rowH() return math.min(MAX_H, math.max(MIN_H, HB.db.teamRowH or 38)) end

-- ---------------------------------------------------------------- class colours
local function classFileFor(r)
	local key = HB.Norm(r.name)
	HB.db.classCache = HB.db.classCache or {}
	if r.unit then
		local ok, _, file = pcall(UnitClass, r.unit)
		if ok and type(file) == "string" and not secret(file) then HB.db.classCache[key] = file return file end
	end
	return HB.db.classCache[key]
end

local function classColor(file)
	if not file then return nil end
	if C_ClassColor and C_ClassColor.GetClassColor then
		local c = C_ClassColor.GetClassColor(file)
		if c then return c.r, c.g, c.b end
	end
	local c = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS or {})[file]
	if c then return c.r, c.g, c.b end
end

local function updateColors(r)
	local cr, cg, cb
	if HB.db.teamClassColors then cr, cg, cb = classColor(classFileFor(r)) end
	if not cr then cr, cg, cb = C.health[1], C.health[2], C.health[3] end
	r.health:SetStatusBarColor(cr, cg, cb)
	r.health.back:SetColorTexture(cr * 0.28, cg * 0.28, cb * 0.28, 0.9)
	if HB.db.teamClassColors then
		r.nameText:SetTextColor(math.min(1, cr * 1.1 + 0.08), math.min(1, cg * 1.1 + 0.08), math.min(1, cb * 1.1 + 0.08))
	else
		r.nameText:SetTextColor(C.name[1], C.name[2], C.name[3])
	end
end

-- ---------------------------------------------------------------- rows
local function solid(parent, layer, c)
	local t = parent:CreateTexture(nil, layer)
	t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
	return t
end

local function bar(parent, fg, bg)
	local b = CreateFrame("StatusBar", nil, parent)
	b:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	b:SetStatusBarColor(fg[1], fg[2], fg[3])
	b:SetMinMaxValues(0, 1)
	b:SetValue(0)
	b.back = solid(b, "BACKGROUND", bg)
	b.back:SetAllPoints()
	return b
end

local function startMove()
	if HB.db.teamLocked or InCombatLockdown() or not container then return end
	container:StartMoving()
end

-- Sizes and anchors that depend on the row size. Out of combat only (rows are secure).
local function sizeRow(r)
	local W, H = rowW(), rowH()
	r:SetSize(W + GAP + BOX_W, H)
	r.bg:SetSize(W, H)
	r.pctText:ClearAllPoints()
	r.pctText:SetPoint("TOPRIGHT", r, "TOPLEFT", W - 6, -5)
	local barH = math.max(6, H - 25)
	r.health:SetSize(W - 12, barH)
	r.power:SetSize(W - 12, math.max(3, math.floor(barH / 3)))
	r.box:ClearAllPoints()
	r.box:SetPoint("TOPLEFT", r, "TOPLEFT", W + GAP, 0)
	r.box:SetSize(BOX_W, H)
	r.box.label:SetShown(H >= 32)
end

local function createRow(i)
	local r = CreateFrame("Button", "HaploBoxPartyRow" .. i, container, "SecureUnitButtonTemplate")
	r:RegisterForClicks("AnyUp")
	r:SetAttribute("type1", "target")
	r:RegisterForDrag("LeftButton")
	r:SetScript("OnDragStart", startMove)
	r:SetScript("OnDragStop", function() HB.SavePartyPosition() end)

	r.bg = solid(r, "BACKGROUND", C.rowBg)
	r.bg:SetPoint("TOPLEFT")

	r.nameText = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	r.nameText:SetPoint("TOPLEFT", 6, -4)
	r.nameText:SetJustifyH("LEFT")

	r.pctText = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.pctText:SetJustifyH("RIGHT")

	r.health = bar(r, C.health, C.healthBg)
	r.health:SetPoint("TOPLEFT", 6, -19)

	r.power = bar(r, C.power, C.powerBg)
	r.power:SetPoint("TOPLEFT", r.health, "BOTTOMLEFT", 0, -3)

	local box = CreateFrame("Frame", nil, r)
	box.bg = solid(box, "BACKGROUND", C.unknown)
	box.bg:SetAllPoints()
	box.icon = box:CreateTexture(nil, "ARTWORK")
	box.icon:SetSize(16, 16)
	box.icon:SetPoint("TOP", 0, -4)
	box.label = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	box.label:SetPoint("BOTTOM", 0, 4)
	box.label:SetFont(box.label:GetFont(), 9, "")
	r.box = box
	sizeRow(r)
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
	updateColors(r) updateHealth(r) updatePower(r) updateStatus(r) updateRange(r)
end

function HB.RefreshPartyFrame()
	for _, r in ipairs(rows) do if r:IsShown() then updateRow(r) end end
end

function HB.OnFollowStateChanged()
	for _, r in ipairs(rows) do if r:IsShown() then updateStatus(r) end end
end

-- ---------------------------------------------------------------- handle, lock and resize
local function shownRows()
	local n = 0
	for _, r in ipairs(rows) do if r:IsShown() then n = n + 1 end end
	return n
end

local function sizeContainer()
	local n = math.max(1, shownRows())
	container:SetSize(rowW() + GAP + BOX_W, n * (rowH() + GAP) - GAP)
	for i, r in ipairs(rows) do
		if r:IsShown() then
			sizeRow(r)
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -(i - 1) * (rowH() + GAP))
		end
	end
end

local function updateLockUI()
	local unlocked = not HB.db.teamLocked
	container.handle:SetShown(unlocked)
	container.grip:SetShown(unlocked)
end

function HB.SetTeamFrameLocked(locked)
	HB.db.teamLocked = locked and true or false
	if container then updateLockUI() end
	HB.print("team frame " .. (HB.db.teamLocked and "locked (/hb frame unlock to move it)"
		or "unlocked: drag the bar or a row to move it, drag the corner to resize"))
end

local function createChrome()
	local h = CreateFrame("Frame", nil, container)
	h:SetPoint("BOTTOMLEFT", container, "TOPLEFT", 0, 2)
	h:SetPoint("BOTTOMRIGHT", container, "TOPRIGHT", 0, 2)
	h:SetHeight(18)
	h:EnableMouse(true)
	h:RegisterForDrag("LeftButton")
	h:SetScript("OnDragStart", startMove)
	h:SetScript("OnDragStop", function() HB.SavePartyPosition() end)
	solid(h, "BACKGROUND", { 0.10, 0.11, 0.13, 0.95 }):SetAllPoints()
	local t = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	t:SetPoint("LEFT", 6, 0)
	t:SetText("HaploBox team - drag to move")
	local lock = CreateFrame("Button", nil, h, "UIPanelButtonTemplate")
	lock:SetSize(48, 16)
	lock:SetPoint("RIGHT", -2, 0)
	lock:SetText("Lock")
	lock:SetScript("OnClick", function() HB.SetTeamFrameLocked(true) end)
	container.handle = h

	local g = CreateFrame("Button", nil, container)
	g:SetSize(16, 16)
	g:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 2, -2)
	g:SetFrameLevel(container:GetFrameLevel() + 20)
	solid(g, "BACKGROUND", { 0.45, 0.45, 0.50, 0.6 }):SetAllPoints()  -- visible even without the grabber art
	g:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	g:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	g:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	g:SetScript("OnMouseDown", function(self)
		if InCombatLockdown() or HB.db.teamLocked then return end
		local s = container:GetEffectiveScale()
		local cx, cy = GetCursorPosition()
		self.start = { x = cx / s, y = cy / s, w = rowW(), h = rowH(), n = math.max(1, shownRows()), s = s }
		self:SetScript("OnUpdate", function()
			if InCombatLockdown() then return end
			local st = self.start
			local x, y = GetCursorPosition()
			x, y = x / st.s, y / st.s
			HB.db.teamW = math.floor(math.min(MAX_W, math.max(MIN_W, st.w + (x - st.x))) + 0.5)
			HB.db.teamRowH = math.floor(math.min(MAX_H, math.max(MIN_H, st.h + (st.y - y) / st.n)) + 0.5)
			sizeContainer()
		end)
	end)
	g:SetScript("OnMouseUp", function(self)
		self:SetScript("OnUpdate", nil)
		HB.SavePartyPosition()
	end)
	container.grip = g
	updateLockUI()
end

-- ---------------------------------------------------------------- layout (out of combat only)
local function wanted()
	local mode = HB.db.teamFrame
	if mode == "hide" then return false end
	if mode ~= "show" and not HB.IAmLeader() then return false end  -- "auto": leader only
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
		r.nameText:SetText(displayName(name))
		if r.unit then unitRow[r.unit] = r end
		r:Show()
	end
	for i = #names + 1, #rows do rows[i]:Hide() rows[i]:SetAttribute("unit", nil) end
	sizeContainer()
	updateLockUI()
	container:Show()
	HB.RefreshPartyFrame()
end

-- Position is stored as the top-left corner, so resizing grows right and down.
function HB.SavePartyPosition()
	if not container then return end
	container:StopMovingOrSizing()
	local left, top = container:GetLeft(), container:GetTop()
	if not left or not top then return end
	HB.db.partyPos = { "TOPLEFT", "BOTTOMLEFT", left, top }
	container:ClearAllPoints()
	container:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

local function applyPosition()
	local p = HB.db.partyPos
	container:ClearAllPoints()
	if p then container:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else container:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -200) end
end

function HB.ResetPartyPosition()
	if InCombatLockdown() then HB.print("not in combat") return end
	HB.db.partyPos, HB.db.teamW, HB.db.teamRowH = nil, nil, nil
	applyPosition()
	HB.LayoutPartyFrame()
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
		createChrome()
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
