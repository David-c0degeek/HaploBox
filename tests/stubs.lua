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
}

function GetTime() return W.now end
function GetRealmName() return W.realm end
function issecretvalue() return false end
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
function hooksecurefunc() end
function GetAddOnMetadata(_, field) return field == "Version" and "test" or nil end

-- units
local function unitName(u)
	if u == "player" then return W.me end
	if u == "questnpc" then return W.questnpc end
	return W.units[u]
end
function UnitExists(u) return unitName(u) ~= nil end
function GetUnitName(u) return unitName(u) end
function UnitName(u) return unitName(u) end
function UnitIsPlayer() return true end
function UnitIsUnit(a, b) return unitName(a) == unitName(b) end
function UnitInParty() return true end
function UnitInRaid() return nil end
function UnitClass() return "Mage", "MAGE" end
function UnitIsConnected() return true end
function UnitIsDeadOrGhost() return false end
function UnitHealth() return 50 end
function UnitHealthMax() return 100 end
function UnitPower() return 10 end
function UnitPowerMax() return 20 end
function UnitPowerType() return 0, "MANA" end
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
function UnitIsGroupLeader() return true end
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
	LootMethod = { Freeforall = 0 },
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
	GetFont = function() return "font", 10 end,
	GetEffectiveScale = function() return 1 end,
	GetStringWidth = function() return 10 end,
	IsShown = function(self) return self.shown ~= false end,
	Show = function(self) self.shown = true end,
	Hide = function(self) self.shown = false end,
	SetShown = function(self, v) self.shown = v and true or false end,
	SetText = function(self, t) self.text = t end,
	GetText = function(self) return self.text end,
	SetAlpha = function(self, a) self.alpha = a end,
	SetAttribute = function(self, k, v) self.attrs = self.attrs or {} self.attrs[k] = v end,
	SetScript = function(self, k, fn) self.scripts = self.scripts or {} self.scripts[k] = fn end,
	IsProtected = function() return false end,
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
function CreateFrame(_, name) return newFrame(name) end
UIParent = newFrame()
function fire(e, ...)
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
C_PartyInfo = { LeaveParty = function() W.left = W.left + 1 end, GetLootMethod = function() return 0 end }
function SetLFGRoles(...) W.lfgRoles = { ... } end
function GetLFGRoles() return false end
function CompleteLFGRoleCheck() end
SlashCmdList = {}
ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
