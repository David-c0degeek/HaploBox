-- HaploBox party frame: one row per team member with health, power and follow status,
-- plus an info strip (level, XP, free bag slots, team buffs, gold) and a team total footer.
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
	ok       = { 0.17, 0.33, 0.20, 0.95 },  -- following the leader
	chain    = { 0.10, 0.30, 0.33, 0.95 },  -- following the healer or another toon (teal)
	lead     = { 0.36, 0.30, 0.10, 0.95 },
	paused   = { 0.55, 0.38, 0.08, 0.95 },
	broken   = { 0.55, 0.16, 0.14, 0.95 },
	unknown  = { 0.25, 0.25, 0.28, 0.95 },
	xp       = { 0.65, 0.30, 0.90 },
	rested   = { 0.25, 0.47, 0.86 },
	xpBg     = { 0.16, 0.12, 0.22, 0.90 },
	footer   = { 0.10, 0.11, 0.13, 0.95 },
	gold     = { 1.00, 0.82, 0.30 },
}
local BAG_ICON = "Interface\\Buttons\\Button-Backpack-Up"
local FOOT_H = 22
local XP_H = 9                 -- XP bar height (with the percentage inside)
local BUFF_SIZE, BUFF_STEP = 20, 22
local BUFF_MIN_DURATION = 60   -- only buffs of a minute or longer: skips procs, stances, aspects and auras
local BUFF_WARN = 120          -- red border and timer from 2 minutes left

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
	-- group members who are not in the team list (a swapped-in toon) still get a row
	if IsInGroup() and not IsInRaid() then
		add(HB.UnitIdent("player"))
		for i = 1, 4 do
			if UnitExists("party" .. i) then add(HB.UnitIdent("party" .. i)) end
		end
	end
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
-- the info strip below the bars: XP bar, then a line with free bag slots and gold
local function showTotals() return HB.db.teamShowGold or HB.db.teamShowBags end
local function showLine() return showTotals() or HB.db.teamShowBuffs end
local function lineH() return HB.db.teamShowBuffs and (BUFF_SIZE + 3) or 15 end
local function stripH() return (HB.db.teamShowXP and (XP_H + 3) or 0) + (showLine() and lineH() or 0) end
local function fullH() return rowH() + stripH() end

-- ---------------------------------------------------------------- money
local function coin(kind) return "|TInterface\\MoneyFrame\\UI-" .. kind .. "Icon:0:0:1:0|t" end
local GOLD, SILVER, COPPER = coin("Gold"), coin("Silver"), coin("Copper")
local function commas(n)
	local s, k = tostring(n), 0
	repeat s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2") until k == 0
	return s
end
-- compact: 100g and up shows gold only, under 100g gold and silver (if any), under 1g silver and copper
function HB.FormatMoney(copper, compact)
	copper = math.floor(copper)
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	local parts = {}
	if g > 0 then parts[#parts + 1] = commas(g) .. GOLD end
	if compact and g >= 100 then return parts[1] end
	if (g > 0 and not compact) or s > 0 then parts[#parts + 1] = s .. SILVER end
	if not (compact and g > 0) then parts[#parts + 1] = c .. COPPER end
	return table.concat(parts, " ")
end

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
	local W, H, FH = rowW(), rowH(), fullH()
	r:SetSize(W + GAP + BOX_W, FH)
	r.bg:SetSize(W, FH)
	r.focusMaxW = math.floor(W * 0.45)
	r.nameText:SetWidth(math.floor(W * 0.45))
	local barH = math.max(6, H - 25)
	r.health:SetSize(W - 12, barH)
	r.power:SetSize(W - 12, math.max(3, math.floor(barH / 3)))
	r.rested:SetSize(W - 12, XP_H)
	r.rested:SetShown(HB.db.teamShowXP and true or false)
	local mid = lineH() / 2
	r.bagIcon:ClearAllPoints()
	r.bagIcon:SetPoint("LEFT", r, "BOTTOMLEFT", 6, mid)
	r.moneyText:ClearAllPoints()
	r.moneyText:SetPoint("RIGHT", r, "BOTTOMLEFT", W - 6, mid)
	r.buffMax = math.max(1, math.floor((W - 120) / BUFF_STEP))
	r.moneyText:SetShown(HB.db.teamShowGold and true or false)
	r.bagIcon:SetShown(HB.db.teamShowBags and true or false)
	r.bagText:SetShown(HB.db.teamShowBags and true or false)
	r.box:ClearAllPoints()
	r.box:SetPoint("TOPLEFT", r, "TOPLEFT", W + GAP, 0)
	r.box:SetSize(BOX_W, FH)
	r.box.label:SetShown(FH >= 32)
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

	-- focus: crosshair + name, top right of the bar area
	r.focusText = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.focusText:SetJustifyH("RIGHT")
	r.focusText:SetWordWrap(false)
	r.focusText:SetTextColor(1, 0.82, 0.3)
	r.focusIcon = r:CreateTexture(nil, "OVERLAY")
	r.focusIcon:SetSize(11, 11)
	r.focusIcon:SetTexture(MEDIA .. "focus")
	r.focusIcon:SetVertexColor(1, 0.82, 0.3)

	r.health = bar(r, C.health, C.healthBg)
	r.health:SetPoint("TOPLEFT", 6, -19)
	r.focusText:SetPoint("BOTTOMRIGHT", r.health, "TOPRIGHT", 0, 3)
	r.focusIcon:SetPoint("RIGHT", r.focusText, "LEFT", -3, 0)

	-- health percent sits inside the health bar, right side
	r.pctText = r.health:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.pctText:SetPoint("RIGHT", r.health, "RIGHT", -3, 0)
	r.pctText:SetJustifyH("RIGHT")
	r.pctText:SetShadowOffset(1, -1)

	r.power = bar(r, C.power, C.powerBg)
	r.power:SetPoint("TOPLEFT", r.health, "BOTTOMLEFT", 0, -3)

	-- info strip: XP bar (rested XP shows as a lighter bar behind it), bags left, gold right
	r.rested = bar(r, C.rested, C.xpBg)
	r.rested:SetPoint("TOPLEFT", r.power, "BOTTOMLEFT", 0, -2)
	r.xp = bar(r.rested, C.xp, { 0, 0, 0, 0 })
	r.xp:SetAllPoints(r.rested)
	r.xp:SetFrameLevel(r.rested:GetFrameLevel() + 1)
	r.xpText = r.xp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.xpText:SetPoint("CENTER", r.rested, "CENTER", 0, 0)
	r.xpText:SetFont(r.xpText:GetFont(), 8, "OUTLINE")
	r.bagIcon = r:CreateTexture(nil, "OVERLAY")
	r.bagIcon:SetSize(12, 12)
	r.bagIcon:SetTexture(BAG_ICON)
	-- team buffs, centred on the bottom line; created when needed
	r.buffs = {}
	r.buffMore = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.bagText = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.bagText:SetPoint("LEFT", r.bagIcon, "RIGHT", 3, 0)
	r.moneyText = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.moneyText:SetJustifyH("RIGHT")

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

local function setBox(r, c, icon, label)
	local b = r.box
	b.bg:SetColorTexture(c[1], c[2], c[3], c[4])
	if icon then b.icon:SetTexture(MEDIA .. icon) b.icon:Show() else b.icon:Hide() end
	b.label:SetText(label)
end

-- Walks the follow chain from a toon: true when it ends at the leader (or at
-- someone outside the team we know nothing about), false when a toon on the way
-- has stopped following. Following the healer while the healer stopped = paused.
local function chainMoving(target)
	local seen = {}
	for _ = 1, 10 do
		local k = HB.Norm(target)
		if not k or seen[k] then return true end
		seen[k] = true
		if HB.IsLeaderName(target) then return true end
		local st = HB.followState[k]
		if st == "X" then return false end
		if st ~= "S" then return true end
		target = HB.followTarget[k]
		if not target then return true end
	end
	return true
end

local function shortLabel(name)
	local n = displayName(name or "?")
	if #n > 9 then n = n:sub(1, 9) end
	return "> " .. n:upper()
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
	if HB.IsLeaderName(r.name) then setBox(r, C.lead, "crown", "LEADER") return end
	if not r.unit then setBox(r, C.unknown, nil, "AWAY") return end
	local k = HB.Norm(r.name)
	local st, target = HB.followState[k], HB.followTarget[k]
	if st == "X" then setBox(r, C.broken, "link-broken", "BROKEN") return end
	if st ~= "S" then setBox(r, C.unknown, nil, "?") return end
	if not target then setBox(r, C.ok, "link", "FOLLOW") return end   -- old version: no target
	local icon, label
	if HB.IsLeaderName(target) then icon, label = "crown", "> LEAD"
	elseif HB.RoleOf(target) == "healer" then icon, label = "cross", "> HEAL"
	else icon, label = "link", shortLabel(target) end
	if chainMoving(target) then
		setBox(r, HB.IsLeaderName(target) and C.ok or C.chain, icon, label)
	else
		setBox(r, C.paused, "pause", label)
	end
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

local function updateFocus(r)
	local f = HB.focus and HB.focus[HB.Norm(r.name)]
	-- size the text to its content so the crosshair sits right before the name
	r.focusText:SetWidth(0)
	r.focusText:SetText(f and displayName(f) or "|cff777777-|r")
	local w = r.focusText.GetUnboundedStringWidth and r.focusText:GetUnboundedStringWidth() or r.focusText:GetStringWidth()
	if type(w) ~= "number" or secret(w) then w = r.focusMaxW or 100 end
	r.focusText:SetWidth(math.min(math.ceil(w) + 2, r.focusMaxW or 100))
	r.focusIcon:SetAlpha(f and 1 or 0.35)
end

-- Level, XP, bags and gold come from the toon itself (HB.stats). A toon without
-- this version of HaploBox, or one that has not reported yet, shows a dash.
local function bagColor(free)
	if free == 0 then return "|cffff5544" elseif free <= 5 then return "|cffffaa33" end
	return "|cffdddddd"
end

local function updateStats(r)
	local s = HB.stats and HB.stats[HB.Norm(r.name)]
	local lvl = HB.db.teamShowXP and s and s.lvl
	r.nameText:SetText((lvl and ("|cffffdc78" .. lvl .. "|r ") or "") .. displayName(r.name))
	if s and s.xpMax and s.xpMax > 0 and s.xp then
		r.rested:SetMinMaxValues(0, s.xpMax)
		r.rested:SetValue(math.min(s.xpMax, s.xp + (s.rest or 0)))
		r.xp:SetMinMaxValues(0, s.xpMax)
		r.xp:SetValue(s.xp)
		r.xpText:SetText(math.floor(s.xp / s.xpMax * 100) .. "%")
		r.rested:SetAlpha(1)
	else
		r.rested:SetAlpha(0)  -- max level or unknown: keep the space, hide the bar
		r.xpText:SetText("")
	end
	if s and s.free then
		r.bagText:SetText(bagColor(s.free) .. s.free .. "|r")
		r.bagIcon:SetAlpha(1)
	else
		r.bagText:SetText("|cff777777-|r")
		r.bagIcon:SetAlpha(0.35)
	end
	r.moneyText:SetText(s and s.copper and HB.FormatMoney(s.copper, true) or "|cff777777-|r")
end

-- ---------------------------------------------------------------- buffs
-- Buffs are read straight from the unit (no messages needed). Only buffs cast by a
-- group member and lasting a minute or more are shown. On clients with secret
-- values the aura data can be hidden in combat: then the last good list stays.
local function buffButton(r, i)
	local b = r.buffs[i]
	if b then return b end
	b = CreateFrame("Frame", nil, r)
	b:SetSize(BUFF_SIZE, BUFF_SIZE)
	b:EnableMouse(false)  -- clicks go through to the row (target the toon)
	b.border = solid(b, "BACKGROUND", { 0.27, 0.28, 0.32, 1 })
	b.border:SetPoint("TOPLEFT", -1, 1)
	b.border:SetPoint("BOTTOMRIGHT", 1, -1)
	b.tex = b:CreateTexture(nil, "ARTWORK")
	b.tex:SetAllPoints()
	b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.time = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.time:SetPoint("BOTTOM", 0, 1)
	b.time:SetFont(b.time:GetFont(), 9, "OUTLINE")
	r.buffs[i] = b
	return b
end

local function fromGroup(src)
	if not src then return false end
	local ok, v = pcall(function()
		return UnitIsUnit(src, "player") or UnitInParty(src) or UnitInRaid(src) ~= nil
	end)
	return ok and v == true
end

local function readBuffs(u)
	local list = {}
	for i = 1, 40 do
		local name, icon, duration, expires, source
		if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
			local a = C_UnitAuras.GetAuraDataByIndex(u, i, "HELPFUL")
			if not a then break end
			name, icon, duration, expires, source = a.name, a.icon, a.duration, a.expirationTime, a.sourceUnit
		elseif UnitBuff then
			local _
			name, icon, _, _, duration, expires, source = UnitBuff(u, i)
			if not name then break end
		else
			break
		end
		if duration and duration >= BUFF_MIN_DURATION and fromGroup(source) then
			list[#list + 1] = { icon = icon, expires = expires }
		end
	end
	return list
end

local function timeLeft(expires)
	local ok, left = pcall(function() return expires - GetTime() end)
	if not ok or type(left) ~= "number" then return nil end
	return left
end

local function fmtTime(left)
	if left >= 3600 then return math.floor(left / 3600) .. "h" end
	if left >= 60 then return math.floor(left / 60) .. "m" end
	return math.max(0, math.floor(left)) .. "s"
end

local function updateBuffTimers(r)
	for _, b in ipairs(r.buffs) do
		if b:IsShown() then
			local left = b.expires and timeLeft(b.expires)
			if left then
				local warn = left <= BUFF_WARN
				b.time:SetText(fmtTime(left))
				b.time:SetTextColor(1, warn and 0.35 or 1, warn and 0.3 or 1)
				b.border:SetColorTexture(warn and 1 or 0.27, warn and 0.35 or 0.28, warn and 0.3 or 0.32, 1)
			else
				b.time:SetText("")
			end
		end
	end
end

local function updateBuffs(r)
	local show = HB.db.teamShowBuffs and r.unit and UnitExists(r.unit)
	local list = {}
	if show then
		local ok, res = pcall(readBuffs, r.unit)
		if not ok then return end  -- hidden right now: keep what is shown
		list = res
	end
	local max = r.buffMax or 5
	local n = #list
	local shown = n > max and (max - 1) or n
	local width = shown * BUFF_STEP - 2 + (n > shown and 20 or 0)
	local x = rowW() / 2 - width / 2
	local y = lineH() / 2
	for i = 1, math.max(shown, #r.buffs) do
		local b = i <= shown and buffButton(r, i) or r.buffs[i]
		if i <= shown then
			b.tex:SetTexture(list[i].icon)
			b.expires = list[i].expires
			b:ClearAllPoints()
			b:SetPoint("LEFT", r, "BOTTOMLEFT", x + (i - 1) * BUFF_STEP, y)
			b:Show()
		elseif b then
			b:Hide()
		end
	end
	if n > shown then
		r.buffMore:ClearAllPoints()
		r.buffMore:SetPoint("LEFT", r, "BOTTOMLEFT", x + shown * BUFF_STEP, y)
		r.buffMore:SetText("+" .. (n - shown))
		r.buffMore:Show()
	else
		r.buffMore:Hide()
	end
	updateBuffTimers(r)
end

local function updateFooter()
	local ft = container and container.footer
	if not ft or not ft:IsShown() then return end
	local copper, free, slots, known, total = 0, 0, 0, 0, 0
	for _, r in ipairs(rows) do
		if r:IsShown() then
			total = total + 1
			local s = HB.stats and HB.stats[HB.Norm(r.name)]
			if s and (s.copper or s.free) then
				known = known + 1
				copper = copper + (s.copper or 0)
				free, slots = free + (s.free or 0), slots + (s.slots or 0)
			end
		end
	end
	ft.bagIcon:SetShown(HB.db.teamShowBags and true or false)
	ft.bagText:SetShown(HB.db.teamShowBags and true or false)
	ft.bagText:SetText(bagColor(free) .. free .. "|r|cff888888 / " .. slots .. " free|r")
	ft.moneyText:SetShown(HB.db.teamShowGold and true or false)
	ft.moneyText:SetText(HB.FormatMoney(copper, false))
	ft.known:SetText(known < total and ("|cff777777" .. known .. " of " .. total .. "|r") or "")
end

local function updateRow(r)
	updateColors(r) updateHealth(r) updatePower(r) updateStatus(r) updateFocus(r) updateStats(r) updateBuffs(r) updateRange(r)
end

function HB.RefreshPartyFrame()
	for _, r in ipairs(rows) do if r:IsShown() then updateRow(r) end end
	updateFooter()
end

function HB.OnStatsChanged(key)
	for _, r in ipairs(rows) do
		if r:IsShown() and HB.Norm(r.name) == key then updateStats(r) end
	end
	updateFooter()
end

function HB.OnFocusChanged()
	for _, r in ipairs(rows) do if r:IsShown() then updateFocus(r) end end
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
	local W, FH = rowW() + GAP + BOX_W, fullH()
	local rowsH = n * (FH + GAP) - GAP
	local ft = container.footer
	ft:SetShown(showTotals() and true or false)
	container:SetSize(W, rowsH + (ft:IsShown() and (GAP + FOOT_H) or 0))
	for i, r in ipairs(rows) do
		if r:IsShown() then
			sizeRow(r)
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -(i - 1) * (FH + GAP))
		end
	end
	ft:ClearAllPoints()
	ft:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -(rowsH + GAP))
	ft:SetSize(W, FOOT_H)
	updateFooter()
end

local function createFooter()
	local ft = CreateFrame("Frame", nil, container)
	ft:EnableMouse(true)
	ft:RegisterForDrag("LeftButton")
	ft:SetScript("OnDragStart", startMove)
	ft:SetScript("OnDragStop", function() HB.SavePartyPosition() end)
	solid(ft, "BACKGROUND", C.footer):SetAllPoints()
	local line = solid(ft, "BORDER", C.gold)
	line:SetPoint("TOPLEFT") line:SetPoint("TOPRIGHT") line:SetHeight(1)
	local label = ft:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	label:SetPoint("LEFT", 8, 0)
	label:SetText("TEAM")
	label:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
	ft.bagIcon = ft:CreateTexture(nil, "OVERLAY")
	ft.bagIcon:SetSize(13, 13)
	ft.bagIcon:SetTexture(BAG_ICON)
	ft.bagIcon:SetPoint("LEFT", label, "RIGHT", 10, 0)
	ft.bagText = ft:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	ft.bagText:SetPoint("LEFT", ft.bagIcon, "RIGHT", 3, 0)
	ft.moneyText = ft:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	ft.moneyText:SetPoint("RIGHT", -8, 0)
	ft.known = ft:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	ft.known:SetPoint("RIGHT", ft.moneyText, "LEFT", -8, 0)
	container.footer = ft
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
	UNIT_AURA = updateBuffs,
}

ev:SetScript("OnEvent", function(_, event, arg1)
	if event == "PLAYER_LOGIN" then
		container = CreateFrame("Frame", "HaploBoxPartyFrame", UIParent)
		container:SetMovable(true)
		container:SetClampedToScreen(true)
		applyPosition()
		createFooter()
		createChrome()
		HB.LayoutPartyFrame()
		local tick = false
		C_Timer.NewTicker(0.5, function()
			if not container:IsShown() then return end
			tick = not tick
			for _, r in ipairs(rows) do
				if r:IsShown() then
					updateRange(r) updateHealth(r)
					if tick then updateBuffTimers(r) end  -- once a second
				end
			end
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
