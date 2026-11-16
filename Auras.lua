-- Team auras beyond the long-buff strip (#12): heal-over-time icons and missing
-- required buffs on the rows, and two optional overview windows listing every
-- member's buffs or debuffs. Additive displays only (all off or empty by default
-- where they add windows); Blizzard's own frames are left alone.
-- When the client restricts aura data (secret values, as retail does in combat)
-- the displays show "unknown" rather than a guess or an old snapshot.
local HB = HaploBox
local secret = HB.secret

local MAX_AURAS = 40                -- traversal bound, even for a broken API
local HOT_SIZE, HOT_MAX = 12, 4
local LINE_ICONS, LINE_MAX, ICON = 8, 10, 16

-- ---------------------------------------------------------------- reading
local function plain(v) return v == nil or not secret(v) end

local function fromGroup(src)
	if not src or secret(src) then return false end
	local ok, v = pcall(function()
		return UnitIsUnit(src, "player") or UnitInParty(src) or UnitInRaid(src) ~= nil
	end)
	return ok and v == true
end

-- Auras on unit, filter "HELPFUL" or "HARMFUL". Returns a list sorted by time left
-- (lasting auras last), then name, and whether the list is complete (false when the
-- traversal bound was reached before the end); or nil when the data is unknown.
-- Expired entries are dropped.
function HB.ReadAuras(unit, filter)
	local list, now, complete = {}, GetTime(), false
	for i = 1, MAX_AURAS do  -- no end seen within the bound: complete stays false
		local name, icon, duration, expires, source, dispel
		if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
			local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
			if not ok then return nil end
			if not a then complete = true break end
			name, icon, duration, expires, source, dispel = a.name, a.icon, a.duration, a.expirationTime, a.sourceUnit, a.dispelName
		else
			local api = filter == "HARMFUL" and UnitDebuff or UnitBuff
			if not api then return nil end
			local ok, n, ic, _, kind, d, e, src = pcall(api, unit, i)
			if not ok then return nil end
			if not n then complete = true break end
			name, icon, duration, expires, source, dispel = n, ic, d, e, src, kind
		end
		if not (plain(name) and plain(icon) and plain(duration) and plain(expires) and plain(source) and plain(dispel)) then
			return nil
		end
		if type(name) ~= "string" then return nil end
		local lasting = not (type(expires) == "number" and expires > 0)
		if lasting or expires > now then
			list[#list + 1] = {
				name = name, icon = icon, duration = duration, source = source, dispel = dispel,
				expires = not lasting and expires or nil,
			}
		end
	end
	table.sort(list, function(a, b)
		local ea, eb = a.expires or math.huge, b.expires or math.huge
		if ea ~= eb then return ea < eb end
		return a.name < b.name
	end)
	return list, complete
end

-- Aura data is only current for a unit the client can see: offline members keep
-- returning nothing or an old list, so they count as unknown.
local function observable(u)
	if not (u and UnitExists(u)) then return false end
	local ok, connected = pcall(UnitIsConnected, u)
	return ok and not secret(connected) and connected ~= false
end
HB.AurasObservable = observable

local function nameSet(text)
	local set, n = {}, 0
	for part in (text or ""):gmatch("[^,]+") do
		local name = part:match("^%s*(.-)%s*$"):lower()
		if name ~= "" and not set[name] then set[name] = true n = n + 1 end
	end
	return set, n
end

-- Built-in HoTs, by spell id so the names come out in the client's language.
-- Ids a client does not know are skipped.
local HOT_IDS = { 139, 774, 8936, 33763, 48438, 61295 }
local builtinHots
local function spellName(id)
	if C_Spell and C_Spell.GetSpellName then
		local ok, n = pcall(C_Spell.GetSpellName, id)
		if ok and type(n) == "string" then return n end
	end
	if GetSpellInfo then
		local ok, n = pcall(GetSpellInfo, id)
		if ok and type(n) == "string" then return n end
	end
end
function HB.HotNames()
	if HB.db.teamHotNames ~= "" then return HB.db.teamHotNames end
	if not builtinHots then
		local names = {}
		for _, id in ipairs(HOT_IDS) do
			local n = spellName(id)
			if n then names[#names + 1] = n end
		end
		builtinHots = table.concat(names, ", ")
	end
	return builtinHots
end

local function secondsText(expires)
	if not expires then return "" end
	local left = expires - GetTime()
	if left <= 0 then return "" end
	if left >= 60 then return math.floor(left / 60) .. "m" end
	return tostring(math.floor(left))
end

local function iconFrame(parent, size)
	local b = CreateFrame("Frame", nil, parent)
	b:SetSize(size, size)
	b:EnableMouse(false)
	b.border = b:CreateTexture(nil, "BACKGROUND")
	b.border:SetPoint("TOPLEFT", -1, 1)
	b.border:SetPoint("BOTTOMRIGHT", 1, -1)
	b.border:SetColorTexture(0.27, 0.28, 0.32, 1)
	b.tex = b:CreateTexture(nil, "ARTWORK")
	b.tex:SetAllPoints()
	b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.time = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.time:SetPoint("BOTTOM", 0, -1)  -- HoT icons move it inside the icon (see size)
	b.time:SetFont(b.time:GetFont(), 8, "OUTLINE")
	return b
end

-- ---------------------------------------------------------------- rows
local function hideRow(r)
	if not r.hots then return end
	for _, b in ipairs(r.hots) do b:Hide() end
	r.required:SetText("")
end

local function updateRow(r)
	if not r.hots then return end
	local u = r.unit
	local wantHots = HB.db.teamShowHots
	local required, nRequired = nameSet(HB.db.teamRequiredBuffs)
	if not (u and UnitExists(u)) or (not wantHots and nRequired == 0) then return hideRow(r) end
	local buffs, complete
	if observable(u) then buffs, complete = HB.ReadAuras(u, "HELPFUL") end
	-- heal over time icons
	local shown = 0
	if wantHots and buffs then
		local hots = nameSet(HB.HotNames())
		for _, a in ipairs(buffs) do
			if shown < HOT_MAX and hots[a.name:lower()] and fromGroup(a.source) then
				shown = shown + 1
				local b = r.hots[shown]
				b.tex:SetTexture(a.icon)
				b.time:SetText(secondsText(a.expires))
				b:Show()
			end
		end
	end
	for i = shown + 1, HOT_MAX do r.hots[i]:Hide() end
	-- required buffs: missing / all there / unknown
	if nRequired == 0 then
		r.required:SetText("")
	elseif not buffs then
		r.required:SetText(r.requiredShort and "|cff999999?|r" or "|cff999999buffs ?|r")
	else
		local have = {}
		for _, a in ipairs(buffs) do have[a.name:lower()] = true end
		local missing = {}
		for name in pairs(required) do if not have[name] then missing[#missing + 1] = name end end
		table.sort(missing)
		if #missing > 0 and not complete then
			r.required:SetText(r.requiredShort and "|cff999999?|r" or "|cff999999buffs ?|r")  -- not seen, but the list was cut short
		else
			local text = r.requiredShort and ("-" .. #missing) or ("no " .. table.concat(missing, ", "))
			r.required:SetText(#missing > 0 and ("|cffff5544" .. text .. "|r") or "")
		end
	end
end
HB.UpdateRowAuras = updateRow

local function create(r)
	r.hots = {}
	for i = 1, HOT_MAX do
		local b = iconFrame(r, HOT_SIZE)
		b.time:ClearAllPoints()
		b.time:SetPoint("CENTER", 0, 0)  -- inside the icon, so it never covers the mana bar
		b:SetFrameLevel(r.health:GetFrameLevel() + 3)
		b:Hide()
		r.hots[i] = b
	end
	local holder = CreateFrame("Frame", nil, r)
	holder:SetAllPoints(r.health)
	holder:EnableMouse(false)
	holder:SetFrameLevel(r.health:GetFrameLevel() + 3)
	r.required = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.required:SetWordWrap(false)
	r.requiredHolder = holder
end

-- Room for the required-buff text: right of the HoT icons, left of the percent.
-- Narrow bars (Mini Heal at its smallest) only get a short count at the right.
local HOTS_W, PCT_W, MIN_TEXT = 4 + HOT_MAX * (HOT_SIZE + 2), 34, 50
local function size(r)
	local w = r.health.GetWidth and r.health:GetWidth()
	if type(w) ~= "number" or secret(w) then w = 0 end
	local h = r.health.GetHeight and r.health:GetHeight()
	if type(h) ~= "number" or secret(h) then h = HOT_SIZE + 2 end
	-- HoT icons fit inside the health bar: centred on the thin main bar, along the
	-- bottom of the tall Mini Heal tile (the name sits at its top)
	local mini = HB.AppliedView and HB.AppliedView() == "mini"
	local s = math.max(8, math.min(mini and 16 or HOT_SIZE, math.floor(h - 2)))
	for i, b in ipairs(r.hots) do
		b:SetSize(s, s)
		b:ClearAllPoints()
		if mini then
			b:SetPoint("BOTTOMLEFT", r.health, "BOTTOMLEFT", 2 + (i - 1) * (s + 2), 2)
		else
			b:SetPoint("LEFT", r.health, "LEFT", 2 + (i - 1) * (s + 2), 0)
		end
	end
	r.required:ClearAllPoints()
	r.requiredShort = w - HOTS_W - PCT_W < MIN_TEXT
	if r.requiredShort then
		r.required:SetPoint("BOTTOMRIGHT", r.requiredHolder, "BOTTOMRIGHT", -3, 2)
		r.required:SetJustifyH("RIGHT")
	else
		r.required:SetPoint("LEFT", r.requiredHolder, "LEFT", HOTS_W, 0)
		r.required:SetPoint("RIGHT", r.requiredHolder, "RIGHT", -PCT_W, 0)
		r.required:SetJustifyH("LEFT")
	end
end
HB.SizeRowAuras = size

-- ---------------------------------------------------------------- overviews
local DISPEL_COLOR = {
	Magic = { 0.2, 0.6, 1 }, Curse = { 0.6, 0, 1 }, Disease = { 0.6, 0.4, 0 }, Poison = { 0, 0.6, 0 },
}
local overviews = {}

local function clampPos(p)
	if type(p) ~= "table" then return nil end
	local x, y = p.x, p.y
	if type(x) ~= "number" or type(y) ~= "number" or x ~= x or y ~= y then return nil end
	if x == math.huge or x == -math.huge or y == math.huge or y == -math.huge then return nil end
	return { x = math.min(1, math.max(0, x)), y = math.min(1, math.max(0, y)) }
end
HB.ClampAuraPos = clampPos

local function place(o)
	local saved = clampPos(HB.db.auraPos and HB.db.auraPos[o.kind])
	o:ClearAllPoints()
	if saved then
		o:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", saved.x * (UIParent:GetWidth() or 0), saved.y * (UIParent:GetHeight() or 0))
	else
		o:SetPoint("CENTER", UIParent, "CENTER", o.kind == "buffs" and -200 or 200, 100)
	end
end

local function savePos(o)
	o:StopMovingOrSizing()
	local left, top, w, h = o:GetLeft(), o:GetTop(), UIParent:GetWidth(), UIParent:GetHeight()
	if type(left) ~= "number" or type(top) ~= "number" or not w or not h or w <= 0 or h <= 0 then return end
	HB.db.auraPos = HB.db.auraPos or {}
	HB.db.auraPos[o.kind] = clampPos({ x = left / w, y = top / h })
	place(o)
end

local function createOverview(kind)
	local T = HB.THEME
	local o = CreateFrame("Frame", "HaploBox" .. (kind == "buffs" and "Buff" or "Debuff") .. "Overview", UIParent)
	o.kind, o.lines = kind, {}
	o:SetMovable(true)
	o:SetClampedToScreen(true)
	o:EnableMouse(false)  -- only the title bar takes the mouse
	o:SetWidth(32 + 70 + LINE_ICONS * (ICON + 2))
	local bg = o:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(T.footer[1], T.footer[2], T.footer[3], 0.85)
	local title = CreateFrame("Frame", nil, o)
	title:SetPoint("TOPLEFT") title:SetPoint("TOPRIGHT")
	title:SetHeight(16)
	title:EnableMouse(true)
	title:RegisterForDrag("LeftButton")
	title:SetScript("OnDragStart", function() if not HB.db.teamLocked then o:StartMoving() end end)
	title:SetScript("OnDragStop", function() savePos(o) end)
	local tbg = title:CreateTexture(nil, "BACKGROUND")
	tbg:SetAllPoints()
	tbg:SetColorTexture(T.footer[1], T.footer[2], T.footer[3], 1)
	local text = title:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	text:SetPoint("LEFT", 6, 0)
	text:SetText(kind == "buffs" and "Team buffs" or "Team debuffs")
	text:SetTextColor(T.gold[1], T.gold[2], T.gold[3])
	o.title = title
	o.more = o:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	o:Hide()
	overviews[kind] = o
	place(o)
	return o
end

local function overviewLine(o, i)
	local l = o.lines[i]
	if l then return l end
	l = CreateFrame("Frame", nil, o)
	l:EnableMouse(false)
	l:SetHeight(ICON + 2)
	l:SetPoint("TOPLEFT", 4, -18 - (i - 1) * (ICON + 4))
	l:SetPoint("RIGHT", o, "RIGHT", -4, 0)
	l.name = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	l.name:SetPoint("LEFT", 2, 0)
	l.name:SetWidth(66)
	l.name:SetJustifyH("LEFT")
	l.name:SetWordWrap(false)
	l.icons = {}
	for k = 1, LINE_ICONS do
		local b = iconFrame(l, ICON)
		b:SetPoint("LEFT", 70 + (k - 1) * (ICON + 2), 0)
		l.icons[k] = b
	end
	l.note = l:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	l.note:SetPoint("LEFT", 70, 0)
	o.lines[i] = l
	return l
end

local function fillLine(o, l, r)
	l.name:SetText((r.name or "?"):gsub("%-.*$", ""))
	local list, complete
	if r.unit and not r.stale and observable(r.unit) then
		list, complete = HB.ReadAuras(r.unit, o.kind == "buffs" and "HELPFUL" or "HARMFUL")
	end
	for _, b in ipairs(l.icons) do b:Hide() end
	l.note:SetText("")
	if r.stale or not r.unit then l.note:SetText(r.unit and "?" or "away") return end
	if not observable(r.unit) then l.note:SetText("offline") return end
	if not list then l.note:SetText("unknown") return end
	if #list == 0 then l.note:SetText(o.kind == "buffs" and "none" or "-") return end
	local n = (#list > LINE_ICONS or not complete) and math.min(#list, LINE_ICONS - 1) or #list
	for k = 1, n do
		local a, b = list[k], l.icons[k]
		b.tex:SetTexture(a.icon)
		b.time:SetText(secondsText(a.expires))
		local c = o.kind == "debuffs" and type(a.dispel) == "string" and DISPEL_COLOR[a.dispel]
		if c then b.border:SetColorTexture(c[1], c[2], c[3], 1) else b.border:SetColorTexture(0.27, 0.28, 0.32, 1) end
		b:Show()
	end
	if #list > n or not complete then
		local b = l.icons[LINE_ICONS]
		b.tex:SetTexture(nil)
		b.border:SetColorTexture(0.27, 0.28, 0.32, 1)
		b.time:SetText("+" .. (#list - n) .. (complete and "" or "?"))
		b:Show()
	end
end

local function refreshOverview(kind)
	local on = kind == "buffs" and HB.db.teamBuffOverview or kind == "debuffs" and HB.db.teamDebuffOverview
	local o = overviews[kind]
	if not on then if o then o:Hide() end return end
	o = o or createOverview(kind)
	local rows = HB.ShownRows()
	local n = math.min(#rows, LINE_MAX)
	for i = 1, n do
		local l = overviewLine(o, i)
		fillLine(o, l, rows[i])
		l:Show()
	end
	for i = n + 1, #o.lines do o.lines[i]:Hide() end
	o.more:ClearAllPoints()
	o.more:SetPoint("TOPLEFT", 8, -18 - n * (ICON + 4))
	o.more:SetText(#rows > n and ("+" .. (#rows - n) .. " more") or (#rows == 0 and "team frame hidden" or ""))
	o:SetHeight(18 + n * (ICON + 4) + ((#rows > n or #rows == 0) and 16 or 4))
	o:Show()
end
HB.PlaceAuraOverviews = function()
	for _, o in pairs(overviews) do place(o) end
end
HB.RefreshAuraOverviews = function()
	refreshOverview("buffs")
	refreshOverview("debuffs")
end
HB.AuraOverview = function(kind) return overviews[kind] end

-- ---------------------------------------------------------------- hooks and timers
local pending = false
local function refreshSoon()
	if pending then return end
	pending = true
	C_Timer.After(0.2, function() pending = false HB.RefreshAuraOverviews() end)
end

table.insert(HB.RowHooks.create, create)
table.insert(HB.RowHooks.size, size)
table.insert(HB.RowHooks.clear, hideRow)
table.insert(HB.RowHooks.refresh, function(r) updateRow(r) refreshSoon() end)
HB.AddRowEvent("UNIT_AURA", function(r) updateRow(r) refreshSoon() end)

-- Once a second: timers count down and expired auras drop out of every display.
C_Timer.NewTicker(1, function()
	if not HB.db then return end
	local rows = HB.ShownRows()
	if HB.db.teamShowHots or HB.db.teamRequiredBuffs ~= "" then
		for _, r in ipairs(rows) do if not r.stale then updateRow(r) end end
	end
	if HB.db.teamBuffOverview or HB.db.teamDebuffOverview then
		HB.RefreshAuraOverviews()
	elseif overviews.buffs or overviews.debuffs then
		HB.RefreshAuraOverviews()
	end
end)
