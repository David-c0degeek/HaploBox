-- Minimal WoW API stubs, enough to load HaploBox in plain Lua 5.1 and drive it with
-- events. The game world lives in W; a test changes W and calls fire(event, ...).
W = {
	now = 100, me = "Haplo", realm = "Forever",
	units = {},          -- unit token -> name, e.g. W.units.party1 = "Elya"
	raid = false, instance = false, combat = false,
	sent = {},           -- addon messages that went out: { msg, channel, target }
	whispers = {},       -- chat whispers: { text, who }
	printed = {},        -- lines added to the chat frame
	timers = {},
	sendResults = {},    -- queued return values for SendAddonMessage (default: success)
	accepted = 0, questAccepted = 0, left = 0, lfgRoles = nil, questnpc = nil,
	header = false,      -- true: SecureGroupHeaderTemplate exists (test_header.lua)
}

function GetTime() return W.now end
function GetRealmName() return W.realm end
-- W.secrets: values the client would mark secret (tests pick odd numbers for them)
function issecretvalue(v) return W.secrets ~= nil and v ~= nil and W.secrets[v] == true end
function strsplit(sep, s)
	local out, pos = {}, 1
	while true do
		local a, b = s:find(sep, pos, true)
		if not a then out[#out + 1] = s:sub(pos) break end
		out[#out + 1] = s:sub(pos, a - 1)
		pos = b + 1
	end
	return unpack(out)
end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function CopyTable(t)
	local o = {}
	for k, v in pairs(t) do o[k] = type(v) == "table" and CopyTable(v) or v end
	return o
end
-- runs fn after the original, like the game's hooksecurefunc
function hooksecurefunc(a, b, c)
	local t, name, fn = _G, a, b
	if type(a) == "table" then t, name, fn = a, b, c end
	local orig = t[name]
	if type(orig) ~= "function" then return end
	t[name] = function(...)
		local r = { orig(...) }
		fn(...)
		return unpack(r)
	end
end

-- quest log (Classic style): W.quests = { { title, id, header } }
function GetNumQuestLogEntries() return #(W.quests or {}) end
function GetQuestLogTitle(i)
	local q = (W.quests or {})[i]
	if not q then return nil end
	return q.title, 10, 0, q.header or false, false, false, 0, q.id
end
function SelectQuestLogEntry(i) W.questSel = i end
function GetQuestLogSelection() return W.questSel or 0 end
function SetAbandonQuest() W.abandonSel = W.questSel end
function GetAbandonQuestName()
	local q = (W.quests or {})[W.abandonSel or 0]
	return q and q.title or ""
end
function AbandonQuest()
	local q = table.remove(W.quests or {}, W.abandonSel or 0)
	W.abandoned = W.abandoned or {}
	if q then W.abandoned[#W.abandoned + 1] = q.title end
end
function GetAddOnMetadata(_, field) return field == "Version" and "test" or nil end

-- units
local function unitName(u)
	if u == "player" then return W.me end
	if u == "questnpc" then return W.questnpc end
	return W.units[u]
end
function UnitExists(u) return unitName(u) ~= nil end
function GetUnitName(u) return unitName(u) end
-- like the game: the name and, for another realm, the realm apart
function UnitName(u)
	local n = unitName(u)
	if not n then return nil end
	-- WoW Forever: "Name Surname" comes back as two values, the surname second
	local first, surname = n:match("^(%S+) (.+)$")
	if first then return first, surname end
	local base, realm = n:match("^(.-)%-(.+)$")
	if base and realm ~= W.realm then return base, realm end
	return base or n, nil
end
function UnitIsPlayer() return true end
function UnitIsUnit(a, b) return unitName(a) == unitName(b) end
function UnitInParty() return true end
function UnitInRaid() return nil end
function UnitClass() return "Mage", "MAGE" end
function UnitIsConnected() return true end
function UnitIsDeadOrGhost(u) return u == "player" and (W.dead or W.ghost) or false end
function UnitIsGhost(u) return u == "player" and W.ghost or false end
function RepopMe() W.released = (W.released or 0) + 1 end
function AcceptResurrect() W.resurrected = (W.resurrected or 0) + 1 end
function RetrieveCorpse() W.retrieved = (W.retrieved or 0) + 1 end
function GetCorpseRecoveryDelay() return W.corpseDelay or 0 end
function StaticPopup_Visible(which) return W.deathPopup == which end
function UnitHealth(u) return W.health and W.health[u] or 50 end
function UnitHealthMax() return 100 end
function UnitPower(u) return W.mana and W.mana[u] or 10 end
function UnitPowerMax() return 20 end
function UnitPowerType(u) if W.rage and W.rage[u] then return 1, "RAGE" end return 0, "MANA" end
-- W.incoming[u]: incoming heals; W.casts[u] / W.channels[u]: { name, startMS, endMS }
function UnitGetIncomingHeals(u) return W.incoming and W.incoming[u] end
local function castInfo(t)
	if not t then return nil end
	return t[1], t[1], nil, t[2], t[3]
end
function UnitCastingInfo(u) return castInfo(W.casts and W.casts[u]) end
function UnitChannelInfo(u) return castInfo(W.channels and W.channels[u]) end
-- W.auras[u] = { HELPFUL = { {name=, icon=, duration=, expirationTime=, sourceUnit=, dispelName=}, ... }, HARMFUL = {...} }
-- W.auraError makes the call fail; W.auraEndless returns an aura for every index.
C_UnitAuras = {
	GetAuraDataByIndex = function(u, i, filter)
		if W.auraError then error("restricted") end
		if W.auraEndless then return { name = "x" .. i, icon = 1, duration = 0, expirationTime = 0 } end
		local t = W.auras and W.auras[u] and W.auras[u][filter]
		return t and t[i]
	end,
}
local SPELLS = { [139] = "Renew", [774] = "Rejuvenation", [8936] = "Regrowth", [2366] = "Herb Gathering",
	[2575] = "Mining", [133] = "Fireball", [2054] = "Heal", [6064] = "Heal", [2050] = "Lesser Heal",
	[2061] = "Flash Heal", [596] = "Prayer of Healing" }
-- combat log: W.clog holds the current event's values
function UnitGUID(u) local n = unitName(u) return n and ("Player-" .. n) or nil end
function CombatLogGetCurrentEventInfo() return unpack(W.clog or {}) end
-- spell descriptions as the client gives them: W.spellDesc[id]
C_Spell = { GetSpellName = function(id) return SPELLS[id] end,
	GetSpellDescription = function(id) return W.spellDesc and W.spellDesc[id] or "" end }
WOW_PROJECT_CLASSIC, WOW_PROJECT_MAINLINE = 2, 1
WOW_PROJECT_ID = 2
function UnitInRange() return true, true end
function UnitLevel() return 10 end
function UnitXP() return 5 end
function UnitXPMax() return 10 end
function GetMoney() return 12345 end
local function groupSize()
	local n = 0
	for u in pairs(W.units) do if u:match("^party%d$") or u:match("^raid%d+$") then n = n + 1 end end
	return n
end
function IsInGroup(category)
	if category == LE_PARTY_CATEGORY_INSTANCE then return W.instance end
	return groupSize() > 0
end
function IsInRaid() return W.raid end
function GetNumGroupMembers() local n = groupSize() return n > 0 and (W.raid and n or n + 1) or 0 end
function UnitIsGroupLeader(u)
	if W.partyLeader then return unitName(u or "player") == W.partyLeader end
	if u == nil or u == "player" then return not W.notGroupLeader end
	return false
end
-- W.groupRoles = { Elya = "HEALER" }: Blizzard group roles by name
function UnitGroupRolesAssigned(u) return (W.groupRoles or {})[unitName(u) or ""] or "NONE" end
function InCombatLockdown() return W.combat end
LE_PARTY_CATEGORY_INSTANCE = 2

-- chat output
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) W.printed[#W.printed + 1] = m end }
UIErrorsFrame = { AddMessage = function() end }
ChatTypeInfo = { RAID_WARNING = {}, WHISPER = { r = 1, g = 1, b = 1 } }
function printedMatching(pattern)
	local n = 0
	for _, m in ipairs(W.printed) do if m:find(pattern) then n = n + 1 end end
	return n
end

-- timers
C_Timer = {
	After = function(d, fn) W.timers[#W.timers + 1] = { at = W.now + d, fn = fn } end,
	NewTicker = function() return {} end,
}
function advance(sec)
	local target = W.now + sec
	while true do
		local best
		for i, t in ipairs(W.timers) do
			if t.at <= target and (not best or t.at < W.timers[best].at) then best = i end
		end
		if not best then break end
		local t = table.remove(W.timers, best)
		if t.at > W.now then W.now = t.at end
		t.fn()
	end
	W.now = target
end

-- addon messages
Enum = {
	SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 3, ChannelThrottle = 8 },
	LootMethod = { Freeforall = 0, Group = 3 },
}
C_ChatInfo = {
	RegisterAddonMessagePrefix = function() end,
	SendAddonMessage = function(_, msg, channel, target)
		assert(#msg <= 255, "addon message over 255 bytes: " .. #msg)
		local r = table.remove(W.sendResults, 1) or 0
		if r == 0 then W.sent[#W.sent + 1] = { msg = msg, channel = channel, target = target } end
		return r
	end,
	SendChatMessage = function(text, _, _, who) W.whispers[#W.whispers + 1] = { text = text, who = who } end,
}
function sentMatching(pattern, channel)
	local out = {}
	for _, s in ipairs(W.sent) do
		if s.msg:find(pattern) and (not channel or s.channel == channel) then out[#out + 1] = s end
	end
	return out
end

-- frames: every method exists; a few keep state the tests read back
local frameMethods = {
	GetFrameLevel = function() return 1 end,
	GetFrameStrata = function() return "DIALOG" end,
	SetPoint = function(self, ...) self.point = { ... } end,
	ClearAllPoints = function(self) self.point = nil end,
	GetFont = function() return "font", 10 end,
	GetEffectiveScale = function() return 1 end,
	GetStringWidth = function() return 10 end,
	IsShown = function(self) return self.shown ~= false end,
	Show = function(self) self.shown = true if self.isHeader then headerUpdate(self) end end,
	Hide = function(self) self.shown = false end,
	SetShown = function(self, v) self.shown = v and true or false end,
	SetText = function(self, t) self.text = t end,
	GetText = function(self) return self.text end,
	SetAlpha = function(self, a) self.alpha = a end,
	SetAttribute = function(self, k, v)
		self.attrs = self.attrs or {}
		local same = self.attrs[k] == v
		self.attrs[k] = v
		-- an unchanged value does not count on firing the handler (same unit token,
		-- new person behind it): tests must not depend on it
		if not same and self.scripts and self.scripts.OnAttributeChanged then self.scripts.OnAttributeChanged(self, k, v) end
		if not same and k:sub(1, 1) ~= "_" and type(self.attrs._onattributechanged) == "string" then
			runSnippet(self, "local self, name, value = ...\n" .. self.attrs._onattributechanged, k, v)
		end
		if self.isHeader then headerUpdate(self) end
	end,
	GetAttribute = function(self, k) return self.attrs and self.attrs[k] end,
	GetFrameRef = function(self, k) return self.attrs and self.attrs["frameref-" .. k] end,
	SetScript = function(self, k, fn) self.scripts = self.scripts or {} self.scripts[k] = fn end,
	IsProtected = function() return false end,
	SetChecked = function(self, v) self.checked = v and true or false end,
	SetValue = function(self, v) self.value = v end,
	SetSize = function(self, w, h) self.width, self.height = w, h end,
	GetWidth = function(self) return self.width end,
	GetHeight = function(self) return self.height end,
	EnableMouse = function(self, v) self.mouse = v and true or false end,
	GetValue = function(self) return self.value end,
	SetMinMaxValues = function(self, a, b) self.min, self.max = a, b end,
	GetChecked = function(self) return self.checked end,
	GetName = function(self) return self.frameName end,
	GetParent = function(self) return self.parentFrame end,
}
local events = {}
local newFrame
frameMethods.CreateTexture = function() return newFrame() end
frameMethods.CreateFontString = function() return newFrame() end
frameMethods.RegisterEvent = function(self, e) events[e] = events[e] or {} events[e][self] = true end
frameMethods.UnregisterEvent = function(self, e) if events[e] then events[e][self] = nil end end
local noop = function() end
-- methods are capitalised; any other missing key is plain data (nil)
local frameMeta = { __index = function(_, k) return frameMethods[k] or (k:match("^%u") and noop) or nil end }
function newFrame(name)
	local fr = setmetatable({}, frameMeta)
	if name then _G[name] = fr end
	return fr
end
-- Restricted snippets run as plain Lua with the frame itself as "self".
function runSnippet(frame, code, ...)
	local fn = assert(loadstring(code))
	fn(frame, ...)
end
-- the restricted environment's string functions
strlen, strfind, gsub = strlen or string.len, strfind or string.find, gsub or string.gsub
-- a wrapped OnClick: the pre-body runs with self, button, down before the click
function SecureHandlerWrapScript(frame, script, header, pre)
	frame.wraps = frame.wraps or {}
	frame.wraps[script] = pre
end
-- SecureCmdOptionParse for the clauses HaploBox uses: @unit, harm, help, nodead,
-- mod:shift and an empty clause. W.hostile[unit] marks enemies, W.dead[unit] the
-- dead, W.shift a held Shift; a unit exists when it is a party token, "player", a
-- member's name, or "<token>target" with W.targets[token] set.
local function unitExists(u)
	if u == "player" or (W.units or {})[u] then return true end
	for _, n in pairs(W.units or {}) do if n == u then return true end end
	local tok = u:match("^(.-)target$")
	return tok ~= nil and (W.targets or {})[tok] ~= nil
end
function SecureCmdOptionParse(msg)
	local conds, action = msg:match("^(.-)%s*([^%]]-)$")
	for clause in conds:gmatch("%[(.-)%]") do
		local unit, ok = nil, true
		for c in (clause .. ","):gmatch("([^,]*),") do
			c = c:match("^%s*(.-)%s*$")
			if c:sub(1, 1) == "@" then unit = c:sub(2)
			elseif c == "harm" then ok = ok and unit ~= nil and unitExists(unit) and (W.hostile or {})[unit] == true
			elseif c == "help" then ok = ok and unit ~= nil and unitExists(unit) and not (W.hostile or {})[unit]
			elseif c == "nodead" then ok = ok and not (W.dead or {})[unit or "target"]
			elseif c == "mod:shift" then ok = ok and W.shift == true
			elseif c ~= "" then error("clause not modelled: " .. c) end
		end
		if ok then return action, unit end
	end
	return nil
end
-- /click <name> <button>: the wrap first, then the button's action. Returns what
-- would be cast: "spell@unit" ("@" alone: the normal target), or nil for nothing.
function clickButton(name, button)
	local b = _G[name]
	if b.wraps and b.wraps.OnClick then
		runSnippet(b, "local self, button, down = ... " .. b.wraps.OnClick, button or "LeftButton", false)
	end
	local a = b.attrs or {}
	if a.type ~= "spell" then return nil end
	return a.spell .. "@" .. (a.unit or "")
end
function SecureHandlerSetFrameRef(f, k, other)
	f.attrs = f.attrs or {}
	f.attrs["frameref-" .. k] = other
end

-- A small SecureGroupHeaderTemplate: party only (the real one also treats a raid as a
-- party when showParty is on, so only the visibility driver hides it there). It rebinds
-- its children on every roster change, in combat too, and never runs addon layout.
local headers = {}
local function headerUnits(h)
	if h.attrs.nameList == nil then return {} end
	local order = {}
	for n in (h.attrs.nameList or ""):gmatch("[^,]+") do order[#order + 1] = n end
	local out = {}
	for _, n in ipairs(order) do
		for _, u in ipairs({ "player", "party1", "party2", "party3", "party4" }) do
			-- the game's key: UnitName plus "-realm" when it has one, compared exactly
			local name, server = UnitName(u)
			if name and server and server ~= "" then name = name .. "-" .. server end
			if name == n and not (u == "player" and h.attrs.showPlayer == false) and (u == "player" or IsInGroup() or h.attrs.showSolo) then out[#out + 1] = u end
		end
	end
	return out
end
function headerUpdate(h)
	h.kids = h.kids or {}
	-- like the real header: nothing happens while it is not visible (its parent too)
	if h.parent and h.parent.shown == false then return end
	local hidden = h.shown == false or (h.driver and W.raid)
	local units = hidden and {} or headerUnits(h)
	local start = h.attrs.startingIndex or 1
	local cap = (h.attrs.unitsPerColumn or 1) * (h.attrs.maxColumns or 1)
	local need = math.min(cap, #units - start + 1)
	for i = #h.kids + 1, need do
		local c = newFrame((h.name or "Header") .. "UnitButton" .. i)
		h.kids[i] = c
		h.attrs["child" .. i] = c
	end
	for i, c in ipairs(h.kids) do
		local u = units[start + i - 1]
		if hidden or i > need then
			c:SetAttribute("unit", nil)
			c.shown = false
		else
			c:SetAttribute("unit", u)
			c.shown = true
			if c.attrs and type(c.attrs.refreshUnitChange) == "string" then
				runSnippet(c, "local self = ...\n" .. c.attrs.refreshUnitChange)
			end
		end
	end
end
-- visibility drivers on headers; other state drivers report party / raid / solo
local stateFrames = {}
local function groupState() return W.raid and "raid" or (IsInGroup() and "party" or "solo") end
function evalStates()
	for _, f in ipairs(stateFrames) do
		local s = groupState()
		if f.state ~= s then
			f.state = s
			local code = f.attrs and f.attrs["_onstate-" .. f.stateId]
			if type(code) == "string" then runSnippet(f, "local self, stateid, newstate = ...\n" .. code, f.stateId, s) end
		end
	end
end
function RegisterStateDriver(f, id, cond)
	if f.isHeader then f.driver = cond headerUpdate(f) return end
	f.stateId = id
	stateFrames[#stateFrames + 1] = f
	evalStates()
end
function UnregisterStateDriver(f) f.driver = nil end
function CreateFrame(_, name, parent, template)
	if template == "SecureGroupHeaderTemplate" then
		if not W.header then error("unknown template " .. template) end
		local h = newFrame(name)
		h.isHeader, h.name, h.attrs, h.parent = true, name, {}, parent
		headers[#headers + 1] = h
		return h
	end
	local f = newFrame(name)
	f.frameName, f.parentFrame = name, parent
	return f
end
UIParent = newFrame()
frameMethods.HookScript = function(self, k, fn)
	self.hooks = self.hooks or {}
	self.hooks[k] = self.hooks[k] or {}
	table.insert(self.hooks[k], fn)
end
frameMethods.GetCenter = function(self) return self.cx, self.cy end
frameMethods.GetOwner = function(self) return self.owner end
frameMethods.SetOwner = function(self, o) self.owner = o end
frameMethods.SetTexture = function(self, t) self.texture = t end
frameMethods.AddLine = function(self, t) self.lines = self.lines or {} table.insert(self.lines, t) end

-- minimap and map position (#5): W.map = { id, x, y, w, h }, W.zoom, W.rotate, W.facing
Minimap = newFrame("Minimap")
WorldFrame = newFrame("WorldFrame")
WorldFrame.frameName = "WorldFrame"
Minimap.width, Minimap.height, Minimap.cx, Minimap.cy = 140, 140, 1000, 700
Minimap.GetZoom = function() return W.zoom or 0 end
GameTooltip = newFrame("GameTooltip")
GameTooltipTextLeft1 = newFrame("GameTooltipTextLeft1")
function GetCursorPosition() return W.cursorX or 0, W.cursorY or 0 end
function GetServerTime() return math.floor(W.now) + 1000000 end
function GetCVar(k)
	if k == "rotateMinimap" then return W.rotate and "1" or "0" end
	if k == "minimapZoom" then return tostring(W.outZoom or 0) end
	if k == "minimapInsideZoom" then return tostring(W.inZoom or 0) end
end
function GetPlayerFacing() return W.facing or 0 end
function IsIndoors() return W.indoors or false end
function IsInInstance() return W.instance or false end
function CreateVector2D(x, y) return { x = x, y = y } end
C_Map = {
	GetBestMapForUnit = function() return W.map and W.map.id end,
	GetPlayerMapPosition = function(id) if W.map and W.map.id == id then return { x = W.map.x, y = W.map.y } end end,
	GetWorldPosFromMapPos = function(id, v)
		if not (W.map and W.map.id == id) then return nil end
		-- world x runs north (down the map is smaller x), world y runs west
		return 0, { x = -v.y * W.map.h, y = -v.x * W.map.w }
	end,
}
-- hover: the game shows its minimap tooltip while the player's cursor is on a node
-- px, py: offset from the minimap centre in its own pixels; the cursor is in screen
-- pixels (times the effective scale). owner: Minimap by default; "UIParent" as on
-- WoW Forever. viaSetText: the tooltip text arrives through SetText, not OnShow.
Minimap.GetEffectiveScale = function() return W.minimapScale or 1 end
-- visible unless it or a parent is hidden (W.minimapParentHidden)
Minimap.IsVisible = function() return Minimap.shown ~= false and not W.minimapParentHidden end
Minimap.IsMouseOver = function()
	local s = W.minimapScale or 1
	local x, y = (W.cursorX or 0) / s, (W.cursorY or 0) / s
	return math.abs(x - Minimap.cx) <= Minimap.width / 2 and math.abs(y - Minimap.cy) <= Minimap.height / 2
end
function hoverMinimap(text, px, py, owner, viaSetText)
	local s = W.minimapScale or 1
	W.cursorX, W.cursorY = (Minimap.cx + px) * s, (Minimap.cy + py) * s
	GameTooltip.owner = owner == "UIParent" and UIParent or owner or Minimap
	GameTooltipTextLeft1.text = text
	if viaSetText then
		GameTooltip:SetText(text)
	else
		for _, fn in ipairs((GameTooltip.hooks or {}).OnShow or {}) do fn(GameTooltip) end
	end
end
-- every event some frame registered since the addon loaded
function registeredEvents()
	local t = {}
	for e, frames in pairs(events) do if next(frames) then t[#t + 1] = e end end
	return t
end

function fire(e, ...)
	if e == "GROUP_ROSTER_UPDATE" or e == "UNIT_NAME_UPDATE" then
		evalStates()
		for _, h in ipairs(headers) do headerUpdate(h) end  -- the game's header goes first
	end
	for fr in pairs(events[e] or {}) do
		if fr.scripts and fr.scripts.OnEvent then fr.scripts.OnEvent(fr, e, ...) end
	end
end

-- sounds
W.sounds = {}
function PlaySound(kit) W.sounds[#W.sounds + 1] = kit end
function PlaySoundFile(f) W.sounds[#W.sounds + 1] = f end
SOUNDKIT = { RAID_WARNING = 8959 }

-- popups
StaticPopupDialogs = {}
W.popup = nil  -- { which, text } while shown
function StaticPopup_Show(which, a, b)
	W.popup = { which = which, text = StaticPopupDialogs[which].text:format(a, b) }
end
function StaticPopup_Hide(which) if W.popup and W.popup.which == which then W.popup = nil end end
function clickPopup(button)  -- 1 = Accept, 2 = Decline
	local d = StaticPopupDialogs[W.popup.which]
	W.popup = nil
	if button == 1 then d.OnAccept() else d.OnCancel(nil, nil, "clicked") end
end

-- automations
function AcceptGroup() W.accepted = W.accepted + 1 end
function AcceptQuest() W.questAccepted = W.questAccepted + 1 end
function HideUIPanel() end
function GetQuestID() return 42 end
-- loot: W.loot is the method (Enum value); W.lootSets lists every change asked for;
-- W.lootRefused makes the server ignore changes; W.noLootApi removes both calls.
W.loot, W.lootSets = 0, {}
C_PartyInfo = {
	LeaveParty = function() W.left = W.left + 1 end,
	GetLootMethod = function() if not W.noLootApi then return W.loot end end,
	SetLootMethod = function(m)
		if W.noLootApi then error("no loot API") end
		assert(type(m) == "number", "enum expected")
		W.lootSets[#W.lootSets + 1] = m
		if not W.lootRefused then W.loot = m end
	end,
}
function SetLFGRoles(...) W.lfgRoles = { ... } end
function GetLFGRoles() return false end
function CompleteLFGRoleCheck() end
SlashCmdList = {}
ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
