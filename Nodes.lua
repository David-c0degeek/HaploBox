-- Gathering nodes found by followers, shown on the leader's minimap (#5).
-- Not yet checked in the game: the minimap tooltip text, the zoom table and the
-- position maths are all "verify" items in docs/design-notes.md.
--
-- Only two observations count, both made by the player on a follower:
--   * hover:  the player moves the mouse over a node on the minimap and the game's
--             own tooltip names it. HaploBox only reads that tooltip; it never moves
--             the cursor, scans the minimap or reads pixels or memory.
--   * gather: the player gathers a node (Herb Gathering or Mining succeeds).
-- A report goes as an addon whisper to the current leader only. The leader shows a
-- marker "seen by <toon> <n> min ago" until it expires or someone gathers there. A
-- marker never claims that the node is there now; a missing report proves nothing.
local HB = HaploBox

local MERGE = 0.003      -- map units: reports this close together are the same node
local MAX_MARKERS, MAX_TOMBS, MAX_QUEUE, MAX_NAMES = 100, 100, 10, 200
local FUTURE_SKEW = 60   -- seconds a report's time may lie ahead of ours
local DEDUPE = 60        -- seconds before the same observation is sent again

-- Minimap diameter in yards per zoom level (as in HereBeDragons). verify on Forever.
local OUTDOOR = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 }
local INDOOR = { [0] = 300, 240, 180, 120, 80, 50 }

-- English Classic Era node names; more are learned from the player's own gathering.
local KNOWN = {}
for _, n in ipairs({ "Peacebloom", "Silverleaf", "Earthroot", "Mageroyal", "Briarthorn", "Stranglekelp",
	"Bruiseweed", "Wild Steelbloom", "Grave Moss", "Kingsblood", "Liferoot", "Fadeleaf", "Goldthorn",
	"Khadgar's Whisker", "Wintersbite", "Firebloom", "Purple Lotus", "Arthas' Tears", "Sungrass",
	"Blindweed", "Ghost Mushroom", "Gromsblood", "Golden Sansam", "Dreamfoil", "Mountain Silversage",
	"Plaguebloom", "Icecap", "Black Lotus" }) do KNOWN[n] = "h" end
for _, n in ipairs({ "Copper Vein", "Tin Vein", "Silver Vein", "Iron Deposit", "Gold Vein", "Mithril Deposit",
	"Truesilver Deposit", "Small Thorium Vein", "Rich Thorium Vein", "Dark Iron Deposit",
	"Incendicite Mineral Vein", "Lesser Bloodstone Deposit", "Indurium Mineral Vein",
	"Ooze Covered Silver Vein", "Ooze Covered Gold Vein", "Ooze Covered Iron Deposit",
	"Ooze Covered Mithril Deposit", "Ooze Covered Truesilver Deposit", "Ooze Covered Thorium Vein",
	"Ooze Covered Rich Thorium Vein" }) do KNOWN[n] = "o" end

local function validName(s)
	return type(s) == "string" and #s > 0 and #s <= 40 and not s:find("[|\r\n]")
end

local function learned()
	if type(HB.db.nodeNames) ~= "table" then HB.db.nodeNames = {} end
	return HB.db.nodeNames
end

local function kindOf(name)
	if KNOWN[name] then return KNOWN[name] end
	local k = learned()[name]
	if (k == "h" or k == "o") and validName(name) then return k end
end

local function now() return GetServerTime and GetServerTime() or math.floor(GetTime()) end

local function expirySeconds()
	return (tonumber(HB.db.nodeExpiry) or 10) * 60
end

-- ---------------------------------------------------------------- position maths
local sizes = {}  -- map sizes do not change
local function mapSize(mapID)
	if sizes[mapID] then return sizes[mapID][1], sizes[mapID][2] end
	if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return end
	local ok1, _, tl = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(0, 0))
	local ok2, _, br = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(1, 1))
	if not (ok1 and ok2 and tl and br) then return end
	local w, h = math.abs(tl.y - br.y), math.abs(tl.x - br.x)  -- world y runs along map x
	if w > 0 and h > 0 then
		sizes[mapID] = { w, h }
		return w, h
	end
end

-- The player's map, position (0..1) and the map's size in yards, or nil.
local function playerPos()
	if IsInInstance and IsInInstance() then return end
	if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return end
	local mapID = C_Map.GetBestMapForUnit("player")
	if not mapID then return end
	local pos = C_Map.GetPlayerMapPosition(mapID, "player")
	if not pos or not pos.x or not pos.y or (pos.x == 0 and pos.y == 0) then return end
	local w, h = mapSize(mapID)
	if not w then return end
	return mapID, pos.x, pos.y, w, h
end

-- Yards per minimap pixel, and the facing to rotate by (0 when the minimap is fixed).
local function minimapScale()
	if not (Minimap and Minimap.GetZoom) then return end
	local width = Minimap:GetWidth()
	if not width or width <= 0 then return end
	local yards
	if C_Minimap and C_Minimap.GetViewRadius then
		local r = C_Minimap.GetViewRadius()
		yards = type(r) == "number" and r > 0 and r * 2 or nil
	else
		local zoom = Minimap:GetZoom() or 0
		-- indoor or outdoor zoom, as HereBeDragons reads it: whichever CVar the
		-- current zoom matches; IsIndoors only when both match
		local out, inside = tonumber(GetCVar and GetCVar("minimapZoom")), tonumber(GetCVar and GetCVar("minimapInsideZoom"))
		local indoors
		if out ~= inside and (out == zoom or inside == zoom) then
			indoors = inside == zoom
		else
			indoors = IsIndoors and IsIndoors() or false
		end
		yards = (indoors and INDOOR or OUTDOOR)[zoom]
	end
	if not yards then return end
	local facing = 0
	if GetCVar and GetCVar("rotateMinimap") == "1" then
		facing = GetPlayerFacing and GetPlayerFacing()
		if not facing then return end
	end
	return yards / width, facing, width
end
HB.NodeMinimapScale = minimapScale

-- Screen offset on the minimap (pixels, y up) to a map position.
local function offsetToMap(sx, sy)
	local mapID, px, py, w, h = playerPos()
	if not mapID then return end
	local ypp, f = minimapScale()
	if not ypp then return end
	local c, s = math.cos(f), math.sin(f)
	local east = (sx * c - sy * s) * ypp
	local north = (sx * s + sy * c) * ypp
	return mapID, px + east / w, py - north / h
end

-- Where the player and the minimap are now, read once per refresh.
local function snapshot()
	local m, px, py, w, h = playerPos()
	if not m then return end
	local ypp, f, width = minimapScale()
	if not ypp then return end
	return { map = m, px = px, py = py, w = w, h = h, ypp = ypp, c = math.cos(f), s = math.sin(f), radius = width / 2 }
end

-- A map position to a minimap offset in pixels, or nil when off this map.
local function mapToOffset(mapID, x, y, snap)
	snap = snap or snapshot()
	if not snap or snap.map ~= mapID then return end
	local east, north = (x - snap.px) * snap.w, (snap.py - y) * snap.h
	return (east * snap.c + north * snap.s) / snap.ypp, (-east * snap.s + north * snap.c) / snap.ypp
end
HB.NodeMapToOffset = mapToOffset

-- ---------------------------------------------------------------- follower: send
local queue, recent = {}, {}
local draining = false

local function near(a, b) return a.map == b.map and (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 <= MERGE * MERGE end

-- Whether this toon may send a report to the leader now. Checked again at send time.
local function shareTarget()
	if not HB.db.nodeShare then return nil end
	if not IsInGroup() or IsInRaid() then return nil end
	if not HB.IsTeamName(HB.UnitIdent("player")) or HB.IAmLeader() then return nil end
	local leader = HB.Leader()
	if not leader or not HB.InGroup(leader) then return nil end
	return leader
end

local function drain()
	local item = table.remove(queue, 1)
	if not item then draining = false return end
	local leader = shareTarget()
	if leader then
		HB.Whisper(leader, item, nil, nil, function()
			return HB.Norm(shareTarget() or "") == HB.Norm(leader)
		end)
	end
	C_Timer.After(1, drain)
end

local function report(src, name, kind, mapID, x, y)
	if not shareTarget() then return end
	local t = now()
	local obs = { map = mapID, x = x, y = y }
	for i = #recent, 1, -1 do
		local r = recent[i]
		if t - r.t > DEDUPE then
			table.remove(recent, i)
		elseif r.name == name and r.src == src and near(r, obs) then
			return
		end
	end
	recent[#recent + 1] = { name = name, src = src, map = mapID, x = x, y = y, t = t }
	local msg = string.format("N|%s|%d|%d|%d|%s|%d|%s", kind, mapID,
		math.floor(x * 10000 + 0.5), math.floor(y * 10000 + 0.5), src, t, name)
	queue[#queue + 1] = msg
	while #queue > MAX_QUEUE do table.remove(queue, 1) end
	if not draining then
		draining = true
		drain()
	end
end

function HB.ClearNodeQueue() wipe(queue) end
function HB.NodeQueueSize() return #queue end

-- hover: the game's minimap tooltip, while the player's own cursor is on it
local function stripEscapes(s)
	return (s:gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- debug lines for minimap hovers that were dropped: each reason at most every 5
-- seconds (the details after it do not count as a new reason)
local lastWhy = {}
local noMouseOverSaid = false
local function why(reason, detail)
	if lastWhy[reason] and GetTime() - lastWhy[reason] < 5 then return end
	lastWhy[reason] = GetTime()
	HB.debug("minimap hover: " .. reason .. (detail or ""))
end

-- WoW Forever puts a marker before each name ("▾ Silverleaf"); only these markers
-- and spaces are removed, so learned names keep every letter
local MARKERS = { "\226\150\190", "\226\150\188", "\226\150\184", "\226\150\186", "\226\128\162", "\194\183" }
local function cleanName(part)
	local n = part:match("^%s*(.-)%s*$")
	local again = true
	while again do
		again = false
		for _, m in ipairs(MARKERS) do
			if n:sub(1, #m) == m then
				n = n:sub(#m + 1):match("^%s*(.-)$")
				again = true
			end
		end
	end
	return n
end
HB.NodeCleanName = cleanName

local function knownNames(line)
	local names = {}
	for part in stripEscapes(line):gmatch("[^\n]+") do
		local n = cleanName(part)
		local k = kindOf(n)
		if k then names[#names + 1] = { n, k } end
	end
	return names
end

local function onTooltip()
	if not (GameTooltip and Minimap) then return end
	local owner = GameTooltip:GetOwner()
	-- upstream clients own the tooltip by the minimap; WoW Forever anchors it to
	-- UIParent, so that only counts while the cursor is really on the minimap
	local fromMinimap = owner == Minimap
	if not fromMinimap and owner ~= nil and owner ~= UIParent then return end
	local line = GameTooltipTextLeft1 and GameTooltipTextLeft1:GetText()
	if type(line) ~= "string" or HB.secret(line) then return end
	local names = knownNames(line)
	if #names == 0 then
		-- a UIParent tooltip without a node name is any other tooltip: say nothing
		if fromMinimap then why("no known herb or ore in ", "\"" .. stripEscapes(line):sub(1, 40) .. "\"") end
		return
	end
	local label = " (" .. names[1][1] .. ")"
	if not fromMinimap then
		-- the client's own mouse-over test where it has one (WoW Forever's minimap has
		-- no IsMouseOver); a call that fails falls through to the circle check below
		local over, which
		if type(Minimap.IsMouseOver) == "function" then
			local ok, v = pcall(Minimap.IsMouseOver, Minimap)
			if ok then over, which = v, "Minimap:IsMouseOver" end
		end
		if over == nil and type(MouseIsOver) == "function" then
			local ok, v = pcall(MouseIsOver, Minimap)
			if ok then over, which = v, "MouseIsOver" end
		end
		if over ~= nil and not over then why("the cursor is not on the minimap", " (" .. which .. ")" .. label) return end
		if over == nil and not noMouseOverSaid then
			noMouseOverSaid = true
			HB.debug("minimap hover: no mouse-over test on this client, the minimap circle decides")
		end
	end
	if not GetCursorPosition then why("no cursor position", label) return end
	local cx, cy = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	local mx, my = Minimap:GetCenter()
	if not (cx and mx and scale and scale > 0) then why("no cursor or minimap position", label) return end
	local sx, sy = cx / scale - mx, cy / scale - my
	if not fromMinimap then
		local r = (Minimap:GetWidth() or 0) / 2
		if sx * sx + sy * sy > r * r then  -- a corner of the frame, outside the round map
			why("the cursor is outside the minimap circle", string.format(" (dx %d, dy %d, radius %d)", sx, sy, r) .. label)
			return
		end
	end
	if not shareTarget() then why("not sharing now (setting, group or leader)", label) return end
	local mapID, x, y = offsetToMap(sx, sy)
	if not mapID or x < 0 or x > 1 or y < 0 or y > 1 then why("no map position here", label) return end
	for _, e in ipairs(names) do report("h", e[1], e[2], mapID, x, y) end
end

if GameTooltip then
	pcall(GameTooltip.HookScript, GameTooltip, "OnShow", onTooltip)
	pcall(hooksecurefunc, GameTooltip, "SetText", onTooltip)
end

-- gather: the player's own Herb Gathering or Mining cast, matched by cast GUID
local GATHER = {}
local function spellName(id)
	if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
	if GetSpellInfo then return (GetSpellInfo(id)) end
end
local function gatherKind(id)
	local n = id and spellName(id)
	if not n then return end
	if GATHER.h == nil then GATHER.h, GATHER.o = spellName(2366) or false, spellName(2575) or false end
	if n == GATHER.h then return "h" end
	if n == GATHER.o then return "o" end
end

local pendingCast
local function onCast(event, unit, a, b, c)
	if unit ~= "player" then return end
	if event == "UNIT_SPELLCAST_SENT" then
		local target, guid, id = a, b, c
		local kind = gatherKind(id)
		pendingCast = (kind and validName(target) and guid) and { guid = guid, name = target, kind = kind } or nil
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		local guid = a
		local p = pendingCast
		if not p or p.guid ~= guid then return end
		pendingCast = nil
		local names = learned()
		if not KNOWN[p.name] and not names[p.name] then
			local count = 0
			for _ in pairs(names) do count = count + 1 end
			if count < MAX_NAMES then names[p.name] = p.kind end
		end
		local mapID, x, y = playerPos()
		if mapID then report("g", p.name, p.kind, mapID, x, y) end
	elseif pendingCast and a == pendingCast.guid then  -- failed or interrupted
		pendingCast = nil
	end
end

-- ---------------------------------------------------------------- leader: markers
local markers, tombs = {}, {}
local pins = {}
local refresh

local function prune()
	local t, limit = now(), expirySeconds()
	for i = #markers, 1, -1 do if t - markers[i].t > limit then table.remove(markers, i) end end
	for i = #tombs, 1, -1 do if t - tombs[i].t > limit then table.remove(tombs, i) end end
	table.sort(markers, function(p, q) return p.t > q.t end)
	while #markers > MAX_MARKERS do table.remove(markers) end
	table.sort(tombs, function(p, q) return p.t > q.t end)
	while #tombs > MAX_TOMBS do table.remove(tombs) end
end

function HB.OnNodeReport(sender, msg)
	-- kept while hidden too, so a gather seen meanwhile still removes its marker
	if #msg > 120 or not HB.IAmLeader() then return end
	if not HB.InGroup(sender) then return end
	local kind, mapID, x, y, src, t, name = msg:match("^N|([ho])|(%d+)|(%d+)|(%d+)|([hg])|(%d+)|([^|\r\n]+)$")
	if not kind or not validName(name) then HB.debug("node report from " .. sender .. " ignored: bad format") return end
	mapID, x, y, t = tonumber(mapID), tonumber(x), tonumber(y), tonumber(t)
	if mapID < 1 or mapID > 100000 or x > 10000 or y > 10000 then return end
	local age = now() - t
	if age > expirySeconds() or age < -FUTURE_SKEW then
		HB.debug("node report from " .. sender .. " ignored: too old or in the future")
		return
	end
	local obs = { map = mapID, x = x / 10000, y = y / 10000, name = name, kind = kind, t = t, by = sender, src = src }
	if src == "g" then
		for i = #markers, 1, -1 do
			local m = markers[i]
			if m.name == name and near(m, obs) and m.t <= t then table.remove(markers, i) end
		end
		local merged = false
		for _, tb in ipairs(tombs) do
			if tb.name == name and near(tb, obs) then tb.t = math.max(tb.t, t) merged = true end
		end
		if not merged then tombs[#tombs + 1] = obs end
	else
		for _, tb in ipairs(tombs) do
			if tb.name == name and near(tb, obs) and tb.t >= t then return end  -- gathered after this was seen
		end
		local merged = false
		for _, m in ipairs(markers) do
			if m.name == name and near(m, obs) then
				if t > m.t then m.t, m.by = t, sender end
				merged = true
			end
		end
		if not merged then markers[#markers + 1] = obs end
	end
	prune()
	refresh()
end

function HB.NodeMarkers() return markers end
function HB.ClearNodeMarkers() wipe(markers) wipe(tombs) refresh() end

local function shown(m)
	if m.kind == "h" then return HB.db.nodeHerbs end
	return HB.db.nodeOre
end

local function pinTooltip(pin)
	local m = pin.marker
	if not m or not GameTooltip then return end
	GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
	local mins = math.max(0, math.floor((now() - m.t) / 60))
	GameTooltip:SetText(m.name)
	GameTooltip:AddLine("seen by " .. (m.by:gsub("%-.*$", "")) .. " "
		.. (mins == 0 and "just now" or (mins .. " min ago")) .. ", may be gone", 0.8, 0.8, 0.8)
	GameTooltip:Show()
end

local function pin(i)
	if pins[i] then return pins[i] end
	local p = CreateFrame("Frame", nil, Minimap)
	p:SetSize(12, 12)
	p.icon = p:CreateTexture(nil, "OVERLAY")
	p.icon:SetAllPoints()
	p:EnableMouse(true)
	p:SetScript("OnEnter", pinTooltip)
	p:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	pins[i] = p
	return p
end

local ICON = { h = "Interface\\Icons\\INV_Misc_Flower_02", o = "Interface\\Icons\\INV_Ore_Copper_01" }

local updater = CreateFrame("Frame")
local elapsed = 0

function refresh()
	prune()
	local used = 0
	local snap = HB.db.nodeShow and HB.IAmLeader() and Minimap and #markers > 0 and snapshot()
	if snap then
		local radius = snap.radius
		for _, m in ipairs(markers) do
			if shown(m) then
				local sx, sy = mapToOffset(m.map, m.x, m.y, snap)
				if sx and sx * sx + sy * sy <= radius * radius then
					used = used + 1
					local p = pin(used)
					p.marker = m
					p.icon:SetTexture(ICON[m.kind])
					p:ClearAllPoints()
					p:SetPoint("CENTER", Minimap, "CENTER", sx, sy)
					p:Show()
				end
			end
		end
	end
	for i = used + 1, #pins do pins[i]:Hide() pins[i].marker = nil end
	updater:SetShown(#markers > 0)
end
HB.RefreshNodePins = refresh

function HB.NodePinsShown()
	local out = {}
	for _, p in ipairs(pins) do if p:IsShown() then out[#out + 1] = p end end
	return out
end
HB.NodePinTooltip = pinTooltip

updater:Hide()
updater:SetScript("OnUpdate", function(_, dt)
	elapsed = elapsed + (dt or 0)
	if elapsed < 0.1 then return end
	elapsed = 0
	refresh()
end)

function HB.NodesCommand(rest)
	if (rest or ""):lower() == "clear" then
		HB.ClearNodeMarkers()
		HB.print("gathering markers cleared")
		return
	end
	prune()
	HB.print(#markers .. " gathering markers from the team. Sharing on this toon: "
		.. (HB.db.nodeShare and "on" or "off") .. ", showing: " .. (HB.db.nodeShow and "on" or "off")
		.. ". /hb nodes clear removes them. Not yet checked in the game.")
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, ...)
	if event:find("^UNIT_SPELLCAST") then onCast(event, ...) return end
	refresh()
end)
for _, e in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
	"UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED_QUIET", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA",
	"PARTY_LEADER_CHANGED", "GROUP_ROSTER_UPDATE" }) do
	pcall(ev.RegisterEvent, ev, e)
end
