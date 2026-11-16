-- HaploBox: multibox team helper. This file holds names and team state, the addon
-- message protocol (follow state, focus, stats, team sync, whisper forwarding),
-- the automations (invites, quests, loot, roles, flights, quest tracker) and the
-- slash commands. Party.lua draws the team frame, Options.lua the options panel.
-- It avoids changing protected frames in combat and avoids known taint paths, but
-- it calls some Blizzard UI code, so it cannot promise never to taint.

local ADDON = ...
local HB = {}
_G.HaploBox = HB

local PREFIX = "HaploBox"
local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local VERSION = getMetadata and getMetadata(ADDON, "Version") or "?"

-- The team roles. GAME_ROLE is the single validator: anything else is "no role".
HB.ROLES = { "tank", "healer", "dps" }
local GAME_ROLE = { tank = "TANK", healer = "HEALER", dps = "DAMAGER" }
local function validRole(r) return GAME_ROLE[r] and r or nil end
HB.ValidRole = validRole

-- Sound values: a SOUNDKIT name ("RAID_WARNING"), a sound kit id (8959),
-- a file id ("file:567397") or a file path ("Interface\\AddOns\\HaploBox\\Sounds\\x.ogg").
-- false or "" turns the sound off.
local DEFAULTS = {
	sounds = {
		followOn     = "IG_QUEST_LIST_OPEN",
		followOff    = "IG_QUEST_LIST_CLOSE",
		leaderAlert  = "RAID_WARNING",
		shareError   = "IG_QUEST_FAILED",
		inviteAccept = "IG_PLAYER_INVITE",
		mountOn      = false,
		mountOff     = false,
		whisperIn    = "TELL_MESSAGE",
		bagsFull     = false,
	},
	alertOnFollowStart  = false,  -- leader also gets a (green) message when a follower starts following
	autoAcceptInvite    = true,   -- followers accept invites from the leader
	autoAcceptShared    = true,   -- accept quests that a team member shares
	autoShareQuests     = "leader", -- "leader", "all" or "off"
	shareErrorAlert     = true,
	relayErrors         = true,   -- followers send cast errors to the leader
	showRelayedErrors   = true,   -- leader prints them in chat
	autoRoleCheck       = true,
	autoFFA             = true,   -- leader sets free-for-all loot when the group changes
	autoLeaveWithLeader = false,
	followFlights       = true,   -- followers: fly to the leader's flight destination when their flight map opens
	teamFrame           = "auto", -- team frame on this toon: "auto" (only if it is the leader), "show" or "hide"
	partyFrameSolo      = false,  -- also show it when not in a group
	partyScale          = 1,
	teamLocked          = false,  -- team frame: locked in place (unlocked shows a drag bar and resize corner)
	teamClassColors     = true,   -- team frame: names and health bars in class colours
	teamShowXP          = true,   -- team frame: level and XP bar
	teamShowGold        = true,   -- team frame: gold per toon and the team total
	teamShowBags        = true,   -- team frame: free bag slots per toon and the team total
	teamShowBuffs       = true,   -- team frame: buffs from the group (a minute or longer) with timers
	autoPartyRole       = true,   -- set my party and group finder role from my team role
	hideQuestTracker    = true,   -- hide Blizzard's quest tracker (objective tracker)
	bagFullAlert        = true,   -- leader: message when a toon's bags are full
	forwardWhispers     = true,   -- followers: forward whispers from outside the team to the leader
	relayReplies        = true,   -- followers: pass the leader's replies on to the last whisperer
	debug               = false,
}

local SOUND_FALLBACK = {  -- SOUNDKIT ids from the 1.x client, used if the constant is missing
	IG_QUEST_LIST_OPEN = 875, IG_QUEST_LIST_CLOSE = 876, RAID_WARNING = 8959,
	READY_CHECK = 8960, IG_QUEST_FAILED = 847, IG_PLAYER_INVITE = 880, TELL_MESSAGE = 3081,
}

local ERRORS = {  -- UI error global -> short code -> text shown to the leader
	{ "ERR_OUT_OF_RANGE", "R", "out of range" },
	{ "ERR_SPELL_OUT_OF_RANGE", "R", "out of range" },
	{ "SPELL_FAILED_LINE_OF_SIGHT", "L", "no line of sight" },
	{ "SPELL_FAILED_MOVING", "V", "can't cast while moving" },
	{ "SPELL_FAILED_BAD_TARGETS", "B", "invalid target" },
	{ "SPELL_FAILED_UNIT_NOT_INFRONT", "F", "target not in front" },
	{ "ERR_BADATTACKFACING", "F", "target not in front" },
	{ "ERR_OUT_OF_MANA", "M", "out of mana" },
	{ "SPELL_FAILED_SILENCED", "S", "silenced" },
	{ "SPELL_FAILED_STUNNED", "S", "stunned" },
	{ "ERR_SPELL_COOLDOWN", "C", "spell on cooldown" },
}
local ERROR_TEXT = {}
for _, e in ipairs(ERRORS) do ERROR_TEXT[e[2]] = e[3] end

local QUEST_SHARE_ERRORS = {
	"ERR_QUEST_PUSH_INVALID_S", "ERR_QUEST_PUSH_DECLINED_S", "ERR_QUEST_PUSH_DEAD_S",
	"ERR_QUEST_PUSH_LOG_FULL_S", "ERR_QUEST_PUSH_ACCEPTED_S", "ERR_QUEST_PUSH_ONQUEST_S",
	"ERR_QUEST_PUSH_ALREADY_DONE_S", "ERR_QUEST_PUSH_NOT_DAILY_S", "ERR_QUEST_PUSH_TIMER_EXPIRED_S",
	"ERR_QUEST_PUSH_NOT_IN_PARTY_S", "ERR_QUEST_PUSH_DIFFERENT_SERVER_DAILY_S",
	"ERR_QUEST_PUSH_NOT_ALLOWED_S", "ERR_QUEST_PUSH_PREREQUISITE_S", "ERR_QUEST_PUSH_LOW_LEVEL_S",
	"ERR_QUEST_PUSH_HIGH_LEVEL_S", "ERR_QUEST_PUSH_CLASS_S", "ERR_QUEST_PUSH_RACE_S",
	"ERR_QUEST_PUSH_LOW_FACTION_S", "ERR_QUEST_PUSH_WRONG_FACTION_S", "ERR_QUEST_PUSH_BUSY_S",
}
-- Not errors: the quest was accepted or the target already has it.
local QUEST_SHARE_HARMLESS = { ERR_QUEST_PUSH_ACCEPTED_S = true, ERR_QUEST_PUSH_ONQUEST_S = true }

-- ---------------------------------------------------------------- helpers
local function secret(v) return issecretvalue and issecretvalue(v) end

local function str(v)
	if v == nil or secret(v) or type(v) ~= "string" or v == "" then return nil end
	return v
end

local function print_(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffHaploBox|r " .. msg) end
local function debug(msg) if HB.db and HB.db.debug then print_("|cff888888" .. msg .. "|r") end end
HB.print, HB.debug, HB.secret = print_, debug, secret

local myRealm = str(GetRealmName and GetRealmName())
myRealm = myRealm and myRealm:gsub("%s", "") or nil

-- Names are compared case-insensitively, with our own realm suffix removed.
-- WoW Forever uses "Name Surname", normal realms "Name" or "Name-Realm".
function HB.Norm(name)
	name = str(name)
	if not name then return nil end
	name = name:match("^%s*(.-)%s*$")
	if myRealm then
		local base, realm = name:match("^(.-)%-([^%-]+)$")
		if base and realm and realm:gsub("%s", "") == myRealm then name = base end
	end
	return name:lower()
end

function HB.UnitIdent(unit)
	local ok, full = pcall(GetUnitName, unit, true)
	full = ok and str(full) or nil
	if not full then
		local ok2, first, second = pcall(UnitName, unit)
		first = ok2 and str(first) or nil
		second = ok2 and str(second) or nil
		if first then full = second and (first .. " " .. second) or first end
	end
	return full
end

function HB.Leader() return HaploBoxTeam and str(HaploBoxTeam.leader) end
function HB.IsLeaderName(name)
	local l = HB.Norm(HB.Leader())
	return l ~= nil and l == HB.Norm(name)
end
function HB.IAmLeader() return HB.IsLeaderName(HB.UnitIdent("player")) end

function HB.RoleOf(name)
	local roles = HaploBoxTeam and HaploBoxTeam.roles
	local key = HB.Norm(name)
	if not roles or not key then return nil end
	for n, role in pairs(roles) do
		if HB.Norm(n) == key then return validRole(role) end
	end
end
function HB.MyRole() return HB.RoleOf(HB.UnitIdent("player")) end

function HB.PlaySound(key)
	local v = HB.db.sounds[key]
	if not v or v == "" then return end
	HB.lastSound = HB.lastSound or {}
	local now = GetTime()
	if (HB.lastSound[key] or 0) > now then return end
	HB.lastSound[key] = now + 0.5
	if type(v) == "number" then
		PlaySound(v, "Master")
	elseif type(v) == "string" then
		local fileId = v:match("^file:(%d+)$")
		if fileId then
			PlaySoundFile(tonumber(fileId), "Master")
		elseif v:find("[\\/]") then
			PlaySoundFile(v, "Master")
		else
			local kit = (SOUNDKIT and SOUNDKIT[v]) or SOUND_FALLBACK[v]
			if kit then PlaySound(kit, "Master") else debug("unknown sound " .. v) end
		end
	end
end

-- ---------------------------------------------------------------- sending
-- Addon messages share a per-prefix allowance (about 10, regaining 1 a second), and
-- a send over it fails. Every message goes through a queue that stays under that
-- allowance and retries a send the game turned down as throttled. A queued message
-- with a key (stats, focus) is replaced by a newer one with the same key.
local SEND_BURST, SEND_RATE, SEND_TRIES = 8, 1, 5
local SEND_RESULT = Enum and Enum.SendAddonMessageResult
local THROTTLED = {
	[(SEND_RESULT and SEND_RESULT.AddonMessageThrottle) or 3] = true,
	[(SEND_RESULT and SEND_RESULT.ChannelThrottle) or 8] = true,
}
local SEND_OK = (SEND_RESULT and SEND_RESULT.Success) or 0
local sendQueue, sendTokens, sendRefillAt, drainScheduled = {}, SEND_BURST, GetTime(), false

local function groupChannel()
	if not IsInGroup() then return nil end
	if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
	return IsInRaid() and "RAID" or "PARTY"
end

-- "ok", "throttled" or "fail". Older clients return nothing or a boolean.
local function rawSend(e)
	local channel = e.target and "WHISPER" or groupChannel()
	if not channel then return "fail" end
	local ok, r = pcall(C_ChatInfo.SendAddonMessage, PREFIX, e.msg, channel, e.target)
	if not ok or r == false then return "fail" end
	if r == nil or r == true or r == SEND_OK then return "ok" end
	if THROTTLED[r] then return "throttled" end
	return "fail"
end

local drainQueue
local function scheduleDrain()
	if drainScheduled then return end
	drainScheduled = true
	C_Timer.After(1 / SEND_RATE, function()
		drainScheduled = false
		drainQueue()
	end)
end

function drainQueue()
	local now = GetTime()
	sendTokens = math.min(SEND_BURST, sendTokens + (now - sendRefillAt) * SEND_RATE)
	sendRefillAt = now
	while sendQueue[1] and sendTokens >= 1 do
		local e = sendQueue[1]
		local result = rawSend(e)
		e.tries = (e.tries or 0) + 1
		if result == "throttled" and e.tries < SEND_TRIES then
			sendTokens = 0
			break
		end
		table.remove(sendQueue, 1)
		sendTokens = sendTokens - 1
		if result ~= "ok" then
			debug("send failed (" .. result .. "): " .. e.msg:sub(1, 40))
			if e.onFail then e.onFail() end
		elseif e.onOk then
			e.onOk()
		end
	end
	if sendQueue[1] then scheduleDrain() end
end

-- Drops queued messages: group ones (target nil) and/or whispers. Used when the group
-- or the leader changes, so a late message does not reach a group or toon it was not
-- meant for.
local function dropQueued(groupMsgs, whispers)
	for i = #sendQueue, 1, -1 do
		local e = sendQueue[i]
		if (e.target and whispers) or (not e.target and groupMsgs) then table.remove(sendQueue, i) end
	end
end

local function enqueue(msg, target, key, onFail, onOk)
	if key then
		for _, e in ipairs(sendQueue) do
			if e.key == key then e.msg = msg return end
		end
	end
	sendQueue[#sendQueue + 1] = { msg = msg, target = target, key = key, onFail = onFail, onOk = onOk }
	drainQueue()
end

-- To the whole group (party, raid or instance chat).
local function send(msg, key)
	if not IsInGroup() then return end
	enqueue(msg, nil, key)
end

-- To one toon only, as an addon whisper. Never falls back to the group.
local function whisper(target, msg, onFail, onOk)
	target = str(target)
	if not target then
		if onFail then onFail() end
		return
	end
	enqueue(msg, target, nil, onFail, onOk)
end

local function leaderAlert(text, color)
	if RaidNotice_AddMessage and RaidWarningFrame then
		RaidNotice_AddMessage(RaidWarningFrame, text, color or ChatTypeInfo["RAID_WARNING"])
	else
		UIErrorsFrame:AddMessage(text, 1, 0.2, 0.2)
	end
	print_(text)
end

local function shortName(name)
	return (str(name) or "?"):gsub("%-.*$", "")
end

-- Turns a global format like "%s is already on that quest." into a Lua pattern.
local function formatToPattern(fmt)
	local p = fmt:gsub("%%%d+%$", "%%")                       -- "%1$s" -> "%s"
	p = p:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")        -- escape magic characters
	p = p:gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")       -- escaped "%s"/"%d" -> captures
	return "^" .. p .. "$"
end
HB.formatToPattern = formatToPattern

-- ---------------------------------------------------------------- loot
-- true / false when the client can tell, nil when it cannot read the loot method
function HB.IsFFA()
	if C_PartyInfo and C_PartyInfo.GetLootMethod then
		local ok, m = pcall(C_PartyInfo.GetLootMethod)
		if ok and m ~= nil then
			if type(m) == "string" then return m == "freeforall" end
			if Enum and Enum.LootMethod and Enum.LootMethod.Freeforall ~= nil then return m == Enum.LootMethod.Freeforall end
		end
	end
	if GetLootMethod then
		local ok, m = pcall(GetLootMethod)
		if ok and m ~= nil then
			if type(m) == "string" then return m == "freeforall" end
			if Enum and Enum.LootMethod and Enum.LootMethod.Freeforall ~= nil then return m == Enum.LootMethod.Freeforall end
		end
	end
	return nil
end

function HB.SetFFA(quiet)
	if not IsInGroup() then if not quiet then print_("not in a group") end return end
	if UnitIsGroupLeader and not UnitIsGroupLeader("player") then
		if not quiet then print_("only the group leader can change the loot method") end
		return
	end
	if HB.IsFFA() then if not quiet then print_("loot is already free for all") end return end
	local tries = {}
	if C_PartyInfo and C_PartyInfo.SetLootMethod then
		if Enum and Enum.LootMethod and Enum.LootMethod.Freeforall ~= nil then
			tries[#tries + 1] = function() C_PartyInfo.SetLootMethod(Enum.LootMethod.Freeforall) end
		end
		tries[#tries + 1] = function() C_PartyInfo.SetLootMethod("freeforall") end
	end
	if SetLootMethod then tries[#tries + 1] = function() SetLootMethod("freeforall") end end
	for i, fn in ipairs(tries) do
		local ok, err = pcall(fn)
		debug("SetLootMethod try " .. i .. ": " .. tostring(ok) .. " " .. tostring(err))
		if ok then
			if not quiet then print_("loot set to free for all") end
			return true
		end
	end
	print_("could not change the loot method on this client")
end

-- ---------------------------------------------------------------- team sync
-- /hb team (on the leader, grouped): the current group becomes the team, in group
-- order, with the leader first. It is sent as M|<leader>|<name>=<role>;... A toon
-- applies it at once only when it comes from the leader this toon already has (set
-- here with /hb leader, the options button, /hb accept or the setup skill). From
-- anyone else it waits for /hb accept. A role the leader does not know is sent as
-- "none" (older versions parse letters only), and every toon keeps its own stored
-- role for that name. /hb role sends R|<role>|<name>.
local function clean(n) return (str(n) or ""):gsub("[|;=]", "") end

local function isTeamName(name)
	local k = HB.Norm(name)
	if not k then return false end
	if HB.IsLeaderName(name) then return true end
	for _, n in ipairs(HaploBoxTeam.order or {}) do if HB.Norm(n) == k then return true end end
	for n in pairs(HaploBoxTeam.roles or {}) do if HB.Norm(n) == k then return true end end
	return false
end
HB.IsTeamName = isTeamName

-- true when that name is one of the other members of my current group
local function inGroup(name)
	local key = HB.Norm(name)
	if not key or not IsInGroup() then return false end
	local raid = IsInRaid()
	for i = 1, raid and GetNumGroupMembers() or 4 do
		local u = raid and ("raid" .. i) or ("party" .. i)
		if UnitExists(u) and HB.Norm(HB.UnitIdent(u)) == key then return true end
	end
	return false
end

local function setRole(name, role)
	HaploBoxTeam.roles = HaploBoxTeam.roles or {}
	local key = HB.Norm(name)
	for n in pairs(HaploBoxTeam.roles) do
		if HB.Norm(n) == key then HaploBoxTeam.roles[n] = nil end
	end
	HaploBoxTeam.roles[name] = role
end

local function refreshTeam()
	if HB.LayoutPartyFrame then HB.LayoutPartyFrame() end
	if HB.OnFollowStateChanged then HB.OnFollowStateChanged() end
end

-- Every leader change goes through here. Private messages still queued for the old
-- leader, and the leader's reply target, are dropped.
local function setLeader(name)
	if HB.Norm(name) ~= HB.Norm(HaploBoxTeam.leader) then
		dropQueued(false, true)
		HB.lastRelay = nil
	end
	HaploBoxTeam.leader = name
end

-- list: { name = , role = } with role nil when unknown. An unknown role keeps the
-- role this toon has stored for that name.
local function applyTeam(leader, list)
	local old = HaploBoxTeam.roles or {}
	setLeader(leader)
	HaploBoxTeam.order = {}
	HaploBoxTeam.roles = {}
	for _, m in ipairs(list) do
		HaploBoxTeam.order[#HaploBoxTeam.order + 1] = m.name
		local role = validRole(m.role)
		if not role then
			local key = HB.Norm(m.name)
			for n, r in pairs(old) do
				if HB.Norm(n) == key then role = validRole(r) end
			end
		end
		HaploBoxTeam.roles[m.name] = role
	end
	refreshTeam()
	if HB.ApplyRoles then C_Timer.After(0.5, HB.ApplyRoles) end
end

function HB.TeamSummary()
	local parts = {}
	for _, n in ipairs(HaploBoxTeam.order or {}) do
		local r = HB.RoleOf(n) or "?"
		parts[#parts + 1] = n .. " (" .. (HB.IsLeaderName(n) and "leader, " or "") .. r .. ")"
	end
	return #parts > 0 and table.concat(parts, ", ") or "no team set"
end

function HB.SetTeamFromGroup()
	if not IsInGroup() or IsInRaid() then print_("join a party (not a raid) with your team first") return end
	local me = clean(HB.UnitIdent("player"))
	local units = { "player", "party1", "party2", "party3", "party4" }
	local list, wire = {}, {}
	for _, u in ipairs(units) do
		if UnitExists(u) then
			local name = clean(HB.UnitIdent(u))
			if name ~= "" then
				local role = HB.RoleOf(name)
				list[#list + 1] = { name = name, role = role }
				wire[#wire + 1] = name .. "=" .. (role or "none")
			end
		end
	end
	applyTeam(me, list)
	send("M|" .. me .. "|" .. table.concat(wire, ";"))
	print_("team set and sent: " .. HB.TeamSummary())
end

-- My role, from the options panel or /hb role: stored, sent to the group, applied.
function HB.SetMyRole(r)
	if not validRole(r) then print_("role must be " .. table.concat(HB.ROLES, ", ")) return end
	local me = clean(HB.UnitIdent("player"))
	setRole(me, r)
	send("R|" .. r .. "|" .. me)
	refreshTeam()
	if HB.ApplyRoles then HB.ApplyRoles() end
	print_("role set to " .. r .. (IsInGroup() and " (sent to the group)" or ""))
end

-- This toon becomes the leader. In a party the whole group becomes the team (as /hb team).
function HB.MakeMeLeader()
	if IsInGroup() and not IsInRaid() then HB.SetTeamFromGroup() return end
	setLeader(clean(HB.UnitIdent("player")))
	refreshTeam()
	print_("you are the leader. Group up and press it again (or /hb team) to send the team to every toon.")
end

-- Parses and checks an M| team. Returns the member list, or nil and the reason.
local MAX_TEAM = 40
local function parseTeam(sender, leader, body)
	if not str(leader) or HB.Norm(sender) ~= HB.Norm(leader) then return nil, "sender is not the leader it names" end
	if not inGroup(sender) then return nil, "sender is not in my group" end
	local list, seen = {}, {}
	for entry in (body or ""):gmatch("[^;]+") do
		local name, role = entry:match("^(.-)=(%a*)$")
		local key = name and HB.Norm(name)
		if not key or key == "" then return nil, "bad entry" end
		if seen[key] then return nil, "duplicate name " .. name end
		seen[key] = true
		list[#list + 1] = { name = name, role = validRole(role) }
	end
	if #list == 0 or #list > MAX_TEAM then return nil, "bad team size" end
	if not seen[HB.Norm(leader)] then return nil, "leader missing from the team" end
	if not seen[HB.Norm(HB.UnitIdent("player"))] then return nil, "this toon is not in the team" end
	return list
end

local pendingTeam  -- a team offered by someone who is not this toon's leader

local function onTeamMessage(sender, leader, body)
	local list, why = parseTeam(sender, leader, body)
	if not list then debug("team from " .. tostring(sender) .. " ignored: " .. why) return end
	if HB.IsLeaderName(sender) then
		pendingTeam = nil
		if HB.HideTeamOffer then HB.HideTeamOffer() end
		applyTeam(leader, list)
		print_("team set by |cffffff00" .. shortName(leader) .. "|r: " .. HB.TeamSummary())
		return
	end
	pendingTeam = { leader = leader, list = list }
	local names = {}
	for i, m in ipairs(list) do names[i] = shortName(m.name) end
	print_("|cffffff00" .. shortName(leader) .. "|r wants to lead the team (" .. table.concat(names, ", ")
		.. "). Accept in the popup, or type |cffffff00/hb accept|r.")
	if HB.ShowTeamOffer then HB.ShowTeamOffer() end
end

-- The waiting offer as text for the popup: leader, member names. nil when none.
function HB.PendingTeamText()
	local p = pendingTeam
	if not p then return nil end
	local names = {}
	for i, m in ipairs(p.list) do names[i] = shortName(m.name) end
	return shortName(p.leader), table.concat(names, ", ")
end

-- /hb accept, the popup or the key binding: take the team offered by someone who is
-- not (yet) this toon's leader.
function HB.AcceptTeam()
	local p = pendingTeam
	if HB.HideTeamOffer then HB.HideTeamOffer() end
	if not p then print_("no team offer to accept") return end
	pendingTeam = nil
	if not inGroup(p.leader) then print_(shortName(p.leader) .. " is no longer in your group") return end
	applyTeam(p.leader, p.list)
	print_("team accepted from |cffffff00" .. shortName(p.leader) .. "|r: " .. HB.TeamSummary())
end

function HB.DeclineTeam()
	if not pendingTeam then return end
	print_("team from " .. shortName(pendingTeam.leader) .. " declined")
	pendingTeam = nil
end

-- /hb leader and the "make my target the leader" key binding.
function HB.SetLeaderName(name)
	name = str(name)
	if not name then print_("no target and no name given") return end
	setLeader(name)
	refreshTeam()
	print_("leader set to |cffffff00" .. name .. "|r")
end

local function onRoleMessage(sender, role, name)
	if HB.Norm(sender) ~= HB.Norm(name) then return end
	role = validRole(role)
	if not role then return end
	setRole(name, role)
	refreshTeam()
	debug(name .. " is now " .. role)
end

-- ---------------------------------------------------------------- events
local f = CreateFrame("Frame")
HB.frame = f
local followEndPending, lastFollowAction
local suppressShareQuest, suppressUntil = nil, 0
local shareErrorPatterns
local errorThrottle = {}

local handlers = {}

-- Follow state of every team member: "S" following, "X" not following, plus who
-- they follow. Messages: F|S|<target> and F|X on a change, F|? asks everyone,
-- F|s|<target> / F|x answer it (lowercase never triggers the leader alert).
HB.followState, HB.followTarget = {}, {}
local myFollowTarget
local function setFollowState(name, state, target)
	local k = HB.Norm(name)
	if not k then return end
	target = state == "S" and str(target) or nil
	if HB.followState[k] == state and HB.followTarget[k] == target then return end
	HB.followState[k], HB.followTarget[k] = state, target
	if HB.OnFollowStateChanged then HB.OnFollowStateChanged() end
end
local function myFollowMsg(lower)
	local code = lastFollowAction == "BEGIN" and "S" or "X"
	if lower then code = code:lower() end
	if lastFollowAction == "BEGIN" and myFollowTarget then return "F|" .. code .. "|" .. myFollowTarget end
	return "F|" .. code
end

-- Focus of every team member: T|<name> when it changes, T| when cleared.
-- Answered together with the follow state on F|?.
HB.focus = {}
local function setFocus(name, target)
	local k = HB.Norm(name)
	if not k then return end
	target = str(target)
	if HB.focus[k] == target then return end
	HB.focus[k] = target
	if HB.OnFocusChanged then HB.OnFocusChanged() end
end
local function myFocusName()
	local n = str(UnitExists("focus") and HB.UnitIdent("focus") or nil)
	return n and n:gsub("|", "") or nil
end
local function focusMsg() return "T|" .. (myFocusName() or "") end

function handlers.PLAYER_FOCUS_CHANGED()
	setFocus(HB.UnitIdent("player"), myFocusName())
	send(focusMsg(), "T")
end

-- Level, XP, money and bag space of every team member. The game only gives these
-- for your own character, so each toon sends S|level|xp|xpMax|rested|copper|free|slots
-- when one of them changes (at most once a second) and when asked with F|?.
HB.stats = {}
local STAT_FIELDS = { "lvl", "xp", "xpMax", "rest", "copper", "free", "slots" }
local function num(v)
	if v == nil or secret(v) then return nil end
	return tonumber(v)
end

local function bagSpace()
	local CC = C_Container
	local numSlots = (CC and CC.GetContainerNumSlots) or GetContainerNumSlots
	local numFree = (CC and CC.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
	if not numSlots or not numFree then return nil end
	local free, total = 0, 0
	for bag = 0, NUM_BAG_SLOTS or 4 do
		local okS, slots = pcall(numSlots, bag)
		local okF, f, family = pcall(numFree, bag)
		slots, f = okS and num(slots), okF and num(f)
		-- only general bags: quivers, ammo pouches and soul bags hold one kind of item
		if slots and f and (family == nil or secret(family) or family == 0) then
			total, free = total + slots, free + f
		end
	end
	return free, total
end

local function atMaxLevel(lvl)
	if IsXPUserDisabled and IsXPUserDisabled() then return true end
	if IsPlayerAtEffectiveMaxLevel then
		local ok, v = pcall(IsPlayerAtEffectiveMaxLevel)
		if ok and v ~= nil and not secret(v) then return v end
	end
	local cap = num(MAX_PLAYER_LEVEL)
	return lvl and cap and lvl >= cap or false
end

local function myStats()
	local s = { lvl = num(UnitLevel("player")) }
	if atMaxLevel(s.lvl) then
		s.xp, s.xpMax, s.rest = 0, 0, 0
	else
		s.xp, s.xpMax = num(UnitXP("player")), num(UnitXPMax("player"))
		s.rest = num(GetXPExhaustion and GetXPExhaustion()) or 0
	end
	s.copper = num(GetMoney and GetMoney())
	s.free, s.slots = bagSpace()
	return s
end

local function statsMsg(s)
	local t = {}
	for i, k in ipairs(STAT_FIELDS) do t[i] = s[k] and tostring(math.floor(s[k])) or "" end
	return "S|" .. table.concat(t, "|")
end

local function setStats(name, s)
	local k = HB.Norm(name)
	if not k then return end
	local old = HB.stats[k]
	HB.stats[k] = s
	if HB.db.bagFullAlert and HB.IAmLeader() and s.free == 0 and (s.slots or 0) > 0
		and old and (old.free or 0) > 0 then
		print_("|cffff4444" .. shortName(name) .. ": bags are full|r")
		HB.PlaySound("bagsFull")
	end
	if HB.OnStatsChanged then HB.OnStatsChanged(k) end
end

local function onStats(sender, ...)
	local v, s = { ... }, {}
	for i, k in ipairs(STAT_FIELDS) do s[k] = tonumber(v[i]) end
	setStats(sender, s)
end

local statsPending, lastStatsMsg = false, nil
local function sendStats()
	lastStatsMsg = statsMsg(myStats())
	send(lastStatsMsg, "S")
end
local function updateMyStats()
	setStats(HB.UnitIdent("player"), myStats())
	if statsPending then return end
	statsPending = true
	C_Timer.After(1, function()
		statsPending = false
		if statsMsg(myStats()) ~= lastStatsMsg then sendStats() end
	end)
end
for _, e in ipairs({ "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION", "PLAYER_MONEY",
	"BAG_UPDATE", "BAG_UPDATE_DELAYED" }) do
	handlers[e] = updateMyStats
end

-- ---------------------------------------------------------------- whisper forwarding
-- A follower forwards whispers from outside the team to the leader:
--   W|<flags>|<from>|<i>|<n>|<text>   flags: GM (from a GM), H (text hidden by the game)
-- The leader answers with /hb r <text>, which sends Y|<toon>|<to>|<i>|<n>|<text>, or by
-- whispering the toon directly within 5 minutes of the last whisper it forwarded.
-- The toon whispers the text on and answers K|<to>|ok, fail, hidden or off (relaying
-- turned off). "ok" only means the game took the whisper and did not say, within a
-- second, that nobody by that name is online: the game never confirms delivery.
-- W, Y and K are addon whispers between the two toons, never sent to the group.
-- Long text is split: one addon message holds at most 255 bytes, and a receiver
-- joins at most 10 pieces.
local MAX_MSG, MAX_PIECES, RELAY_WINDOW = 255, 10, 300

-- Pieces for head|i|n|piece, each within MAX_MSG; nil when it cannot fit.
local function splitText(head, text)
	for n = 1, MAX_PIECES do
		local room = MAX_MSG - #head - #("|" .. n .. "|" .. n .. "|")
		if room < 1 then return nil end
		local pieces, pos = {}, 1
		repeat
			local stop = pos + room - 1
			-- never cut inside a UTF-8 character; a character that does not fit at all fails
			while stop >= pos and stop < #text and text:byte(stop + 1) >= 0x80 and text:byte(stop + 1) < 0xC0 do
				stop = stop - 1
			end
			if stop < pos and pos <= #text then return nil end
			pieces[#pieces + 1] = text:sub(pos, stop)
			pos = stop + 1
		until pos > #text or #pieces > n
		if #pieces <= n then return pieces end
	end
	return nil
end
HB.SplitText = splitText

-- Whispers text to one toon in pieces. onFail runs once if any piece fails; onDone
-- runs once when the game has taken every piece.
local function sendText(target, head, text, onFail, onDone)
	local pieces = splitText(head, text or "")
	local failed, left = false, pieces and #pieces or 0
	local function fail()
		if failed then return end
		failed = true
		if onFail then onFail() end
	end
	local function ok()
		left = left - 1
		if left == 0 and not failed and onDone then onDone() end
	end
	if not pieces then fail() return end
	for i, p in ipairs(pieces) do whisper(target, head .. "|" .. i .. "|" .. #pieces .. "|" .. p, fail, ok) end
end

local partial = {}
local function joinText(key, i, n, piece)
	i, n = tonumber(i), tonumber(n)
	if not i or not n or n < 1 or n > MAX_PIECES or i < 1 or i > n then return nil end
	if n == 1 then return piece end
	if i == 1 or not partial[key] then partial[key] = {} end
	partial[key][i] = piece
	if i < n then return nil end
	local p = partial[key]
	partial[key] = nil
	for j = 1, n do if not p[j] then return nil end end
	return table.concat(p, "", 1, n)
end

local lastWhisperer, lastWhisperAt, forwardedTo = nil, 0, nil
local forwardSeq, armedSeq = 0, 0  -- forwards started / the newest one that reached the leader
local relayWatch = {}  -- normalized name -> { who, leader, token } while we wait for "not online"
local notFoundPattern

local function relayTo(who, text, leader)
	local fn = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
	local ok = fn and pcall(fn, text, "WHISPER", nil, who)
	if not ok then whisper(leader, "K|" .. who .. "|fail") return end
	local key = HB.Norm(who) or who
	local w = { who = who, leader = leader }
	relayWatch[key] = w
	C_Timer.After(1, function()
		if relayWatch[key] ~= w then return end
		relayWatch[key] = nil
		whisper(leader, "K|" .. who .. "|ok")
	end)
end

-- CHAT_MSG_SYSTEM: "No player named X is currently playing." right after a relay.
local function relayNotFound(msg)
	local name = notFoundPattern and msg:match(notFoundPattern)
	local w = name and relayWatch[HB.Norm(name) or name]
	if not w then return false end
	relayWatch[HB.Norm(name) or name] = nil
	whisper(w.leader, "K|" .. w.who .. "|fail")
	return true
end

function handlers.CHAT_MSG_WHISPER(text, sender, _, _, _, flag)
	sender = str(sender)
	local leader = HB.Leader()
	if not sender or not leader or not IsInGroup() or HB.IAmLeader() then return end
	if HB.IsLeaderName(sender) then
		-- the leader answers a forwarded whisper by whispering this toon
		if not HB.db.relayReplies or not lastWhisperer or GetTime() - lastWhisperAt > RELAY_WINDOW then return end
		if HB.Norm(sender) ~= HB.Norm(forwardedTo) then return end  -- forwarded to a previous leader
		if secret(text) or type(text) ~= "string" then whisper(sender, "K|" .. lastWhisperer .. "|hidden") return end
		relayTo(lastWhisperer, text, sender)
		return
	end
	if not HB.db.forwardWhispers or isTeamName(sender) then return end
	-- The direct-reply window opens only once the whole whisper has gone to the leader
	-- (until then the leader has not seen it), and it runs from the stranger's whisper:
	-- relaying a reply does not extend it. A forward that finishes after a newer one
	-- does not take the window back.
	forwardSeq = forwardSeq + 1
	local seq, at = forwardSeq, GetTime()
	local function done()
		if seq < armedSeq then return end
		armedSeq = seq
		lastWhisperer, lastWhisperAt, forwardedTo = sender, at, leader
	end
	local flags = (flag == "GM" or flag == "DEV") and "GM" or ""
	local function failed() print_("|cffff4444could not forward the whisper from " .. shortName(sender) .. " to the leader|r") end
	if secret(text) or type(text) ~= "string" then
		sendText(leader, "W|" .. flags .. "H|" .. sender, "", failed, done)
	else
		sendText(leader, "W|" .. flags .. "|" .. sender, text, failed, done)
	end
end

local function onWhisperForward(sender, msg)
	if not HB.IAmLeader() then return end
	local flags, who, i, n, piece = msg:match("^W|([^|]*)|([^|]*)|(%d+)|(%d+)|(.*)$")
	if not who or who == "" then return end
	local text = joinText("W" .. sender, i, n, piece)
	if not text then return end
	HB.lastRelay = { toon = sender, who = who }
	local gm = flags:find("GM") and "|cff00ccff<GM>|r " or ""
	local body = flags:find("H") and "|cff999999(the game hid the text)|r" or text
	local c = (ChatTypeInfo and ChatTypeInfo.WHISPER) or { r = 1, g = 0.5, b = 1 }
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ccff[" .. shortName(sender) .. "]|r " .. gm .. shortName(who)
		.. " whispers: " .. body, c.r, c.g, c.b)
	HB.PlaySound("whisperIn")
end

local function onReplyRequest(sender, msg)
	if not HB.IsLeaderName(sender) then return end
	local toon, who, i, n, piece = msg:match("^Y|([^|]*)|([^|]*)|(%d+)|(%d+)|(.*)$")
	if not who or who == "" or HB.Norm(toon) ~= HB.Norm(HB.UnitIdent("player")) then return end
	local text = joinText("Y" .. sender, i, n, piece)
	if not text or text == "" then return end
	if not HB.db.relayReplies then whisper(sender, "K|" .. who .. "|off") return end
	relayTo(who, text, sender)
end

local function onRelayResult(sender, who, result)
	if not HB.IAmLeader() then return end
	if result == "ok" then
		print_("|cffff80ffreply passed to " .. shortName(sender) .. " for " .. shortName(who) .. "|r")
	elseif result == "hidden" then
		print_("|cffff4444" .. shortName(sender) .. " could not read your reply (hidden by the game); use /hb r|r")
	elseif result == "off" then
		print_("|cffff4444" .. shortName(sender) .. " has reply relaying turned off|r")
	else
		print_("|cffff4444" .. shortName(sender) .. " could not whisper " .. shortName(who) .. "|r")
	end
end

function HB.Reply(text)
	local lr = HB.lastRelay
	if not lr then print_("no forwarded whisper to reply to") return end
	if not text or text == "" then
		print_("/hb r <text> replies to " .. shortName(lr.who) .. " via " .. shortName(lr.toon))
		return
	end
	sendText(lr.toon, "Y|" .. lr.toon .. "|" .. lr.who, text, function()
		print_("|cffff4444could not send your reply to " .. shortName(lr.toon) .. " (too long, or the message failed)|r")
	end)
end

local lastQuery = 0
local function queryFollowStates()
	if not IsInGroup() or GetTime() - lastQuery < 3 then return end
	lastQuery = GetTime()
	send("F|?")
	if not HB.IAmLeader() then send(myFollowMsg(true), "f") end
	send(focusMsg(), "T")
	sendStats()
end

-- F|? from each toon that logs in or joins: one answer per second at most, so a
-- whole team reloading at once stays under the send allowance.
local answerPending = false
local function answerQuery()
	if answerPending then return end
	answerPending = true
	C_Timer.After(1, function()
		answerPending = false
		if not HB.IAmLeader() then send(myFollowMsg(true), "f") end
		send(focusMsg(), "T")
		sendStats()
	end)
end

function handlers.ADDON_LOADED(name)
	if name ~= ADDON then return end
	HaploBoxDB = HaploBoxDB or {}
	HaploBoxTeam = HaploBoxTeam or {}
	for k, v in pairs(DEFAULTS) do
		if HaploBoxDB[k] == nil then
			HaploBoxDB[k] = type(v) == "table" and CopyTable(v) or v
		end
	end
	for k, v in pairs(DEFAULTS.sounds) do
		if HaploBoxDB.sounds[k] == nil then HaploBoxDB.sounds[k] = v end
	end
	HB.db = HaploBoxDB
	C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
	shareErrorPatterns = {}
	for _, g in ipairs(QUEST_SHARE_ERRORS) do
		local fmt = _G[g]
		if type(fmt) == "string" then
			shareErrorPatterns[#shareErrorPatterns + 1] = { formatToPattern(fmt), QUEST_SHARE_HARMLESS[g] }
		end
	end
	if type(ERR_CHAT_PLAYER_NOT_FOUND_S) == "string" then notFoundPattern = formatToPattern(ERR_CHAT_PLAYER_NOT_FOUND_S) end
	if HB.CreateOptions then HB.CreateOptions() end
end

function handlers.PLAYER_ENTERING_WORLD()
	C_Timer.After(3, queryFollowStates)
	updateMyStats()
end

function handlers.PLAYER_LOGIN()
	C_Timer.After(2, HB.ApplyRoles)
	HB.ApplyQuestTracker()
	C_Timer.After(3, HB.ApplyQuestTracker)  -- some clients build the tracker late
	local leader = HB.Leader()
	if leader then
		print_(VERSION .. " loaded. Leader: |cffffff00" .. leader .. "|r" .. (HB.IAmLeader() and " (you)" or ""))
	else
		print_(VERSION .. " loaded. No leader set: target the leader and type |cffffff00/hb leader|r")
	end
end

function handlers.AUTOFOLLOW_BEGIN(name)
	followEndPending = nil
	name = str(name)
	-- a refresh of the same follow is not news; a switch to another target is
	if lastFollowAction == "BEGIN" and HB.Norm(name) == HB.Norm(myFollowTarget) then return end
	local wasFollowing = lastFollowAction == "BEGIN"
	lastFollowAction, myFollowTarget = "BEGIN", name
	setFollowState(HB.UnitIdent("player"), "S", name)
	if not wasFollowing then HB.PlaySound("followOn") end
	send(myFollowMsg(false))
end

function handlers.AUTOFOLLOW_END()
	-- WoW fires END followed by BEGIN when following is refreshed: wait before reporting.
	local token = {}
	followEndPending = token
	C_Timer.After(0.3, function()
		if followEndPending ~= token then return end
		followEndPending = nil
		lastFollowAction, myFollowTarget = "END", nil
		setFollowState(HB.UnitIdent("player"), "X")
		HB.PlaySound("followOff")
		send("F|X")
	end)
end

function handlers.PARTY_INVITE_REQUEST(inviter)
	if not HB.db.autoAcceptInvite or not HB.IsLeaderName(inviter) then return end
	AcceptGroup()
	HB.PlaySound("inviteAccept")
	C_Timer.After(0.1, function()
		StaticPopup_Hide("PARTY_INVITE")
		StaticPopup_Hide("PARTY_INVITE_XREALM")
	end)
end

local ffaGroupSize = 0
function handlers.GROUP_ROSTER_UPDATE()
	-- Only when someone joins: setting the loot method fires GROUP_ROSTER_UPDATE again,
	-- and every roster update resets other addons' party state.
	if not IsInGroup() then
		HB.wasLeaderPresent = nil  -- a later group starts without a leader to wait for
		dropQueued(true, false)    -- group messages queued for the group we left
	end
	local size = IsInGroup() and GetNumGroupMembers() or 0
	local grew = size > ffaGroupSize
	ffaGroupSize = size
	if grew then
		C_Timer.After(2, queryFollowStates)
		C_Timer.After(1.5, HB.ApplyRoles)
	end
	if grew and HB.db.autoFFA and HB.IAmLeader() and IsInGroup() and HB.IsFFA() ~= true then
		C_Timer.After(1, function() HB.SetFFA(true) end)
	end
	if HB.db.autoLeaveWithLeader and not HB.IAmLeader() and IsInGroup() and HB.Leader() then
		local present = inGroup(HB.Leader())
		if HB.wasLeaderPresent and not present then
			print_("leader left the group, leaving too")
			C_PartyInfo.LeaveParty()
		end
		HB.wasLeaderPresent = present
	end
end

local function questFromPlayer()
	return UnitExists("questnpc") and UnitIsPlayer("questnpc")
end

function handlers.QUEST_DETAIL()
	if not questFromPlayer() then return end
	-- Quests shared by a player are never shared back.
	local id = GetQuestID and GetQuestID()
	if id and id > 0 then suppressShareQuest, suppressUntil = id, GetTime() + 5 end
	-- only quests from the team; a quest from anyone else stays open to decide
	if HB.db.autoAcceptShared and isTeamName(HB.UnitIdent("questnpc")) then
		AcceptQuest()
		HideUIPanel(QuestFrame)
	end
end

function handlers.QUEST_ACCEPTED(a, b)
	-- Classic sends (questLogIndex, questID), newer clients only (questID).
	local questID = b or a
	local mode = HB.db.autoShareQuests
	if mode == "off" or (mode == "leader" and not HB.IAmLeader()) or not IsInGroup() then return end
	if questID and questID == suppressShareQuest and GetTime() < suppressUntil then return end
	debug("QUEST_ACCEPTED " .. tostring(a) .. " " .. tostring(b) .. ", sharing")
	C_Timer.After(0.5, function() HB.ShareQuest(b and a or nil, questID, true) end)
end

local function questTitle(questID, index)
	if questID and C_QuestLog and C_QuestLog.GetTitleForQuestID then
		local ok, t = pcall(C_QuestLog.GetTitleForQuestID, questID)
		if ok and t then return t end
	end
	if index and GetQuestLogTitle then
		local t = GetQuestLogTitle(index)
		if t then return t end
	end
	return "quest " .. tostring(questID or index)
end

-- Share one quest with the party. Tries the modern API, then the log-index API.
-- retry: try once more a second later (the quest log can lag behind QUEST_ACCEPTED).
function HB.ShareQuest(index, questID, retry)
	if not IsInGroup() then return end
	if questID and not index and C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
		local ok, i = pcall(C_QuestLog.GetLogIndexForQuestID, questID)
		if ok and i and i > 0 then index = i end
	end
	local pushed = false
	if questID and C_QuestLog and C_QuestLog.IsPushableQuest and C_QuestLog.IsPushableQuest(questID) then
		if C_QuestLog.SetSelectedQuest then C_QuestLog.SetSelectedQuest(questID) end
		QuestLogPushQuest()
		pushed = true
	elseif index and SelectQuestLogEntry and GetQuestLogPushable then
		SelectQuestLogEntry(index)
		if GetQuestLogPushable() then
			QuestLogPushQuest(index)
			pushed = true
		end
	end
	if pushed then
		print_("shared: " .. questTitle(questID, index))
	elseif retry then
		C_Timer.After(1, function() HB.ShareQuest(index, questID, false) end)
	else
		print_("|cffffaa00not shareable:|r " .. questTitle(questID, index))
	end
end

function handlers.CHAT_MSG_SYSTEM(msg)
	if secret(msg) or type(msg) ~= "string" then return end
	if relayNotFound(msg) or not HB.db.shareErrorAlert then return end
	for _, p in ipairs(shareErrorPatterns) do
		local who = msg:match(p[1])
		if who then
			if not p[2] then
				HB.PlaySound("shareError")
				print_("|cffff4444quest share failed:|r " .. msg)
			end
			return
		end
	end
end

function handlers.UI_ERROR_MESSAGE(_, msg)
	if not HB.db.relayErrors or HB.IAmLeader() or secret(msg) then return end
	for _, e in ipairs(ERRORS) do
		if _G[e[1]] and msg == _G[e[1]] then
			local now = GetTime()
			if (errorThrottle[e[2]] or 0) < now then
				errorThrottle[e[2]] = now + 2
				send("E|" .. e[2])
			end
			return
		end
	end
end

-- ---------------------------------------------------------------- flights
-- When the leader takes a flight, it sends the destination name ("P|<name>").
-- A follower flies there as soon as its own flight map is open: right away when it
-- already is, or when it opens within PENDING_FLIGHT seconds. Names are sent instead
-- of node indexes, because the index list differs per toon (known flight paths).
local PENDING_FLIGHT = 120
local pendingFlight, pendingFlightUntil
local taxiNames = {}  -- node index -> name, from the open flight map

local function taxiNodes()
	local list = {}
	if NumTaxiNodes and TaxiNodeName then
		for i = 1, NumTaxiNodes() do
			local name = TaxiNodeName(i)
			local kind = TaxiNodeGetType and TaxiNodeGetType(i)
			if str(name) then list[#list + 1] = { index = i, name = name, ok = kind == nil or kind == "REACHABLE" } end
		end
	end
	if #list == 0 and C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and GetTaxiMapID then
		local ok, nodes = pcall(C_TaxiMap.GetAllTaxiNodes, GetTaxiMapID())
		if ok and type(nodes) == "table" then
			local reachable = Enum and Enum.FlightPathState and Enum.FlightPathState.Reachable
			for _, n in ipairs(nodes) do
				if str(n.name) and n.slotIndex then
					list[#list + 1] = { index = n.slotIndex, name = n.name, ok = reachable == nil or n.state == reachable }
				end
			end
		end
	end
	return list
end

local function tryPendingFlight()
	if not pendingFlight then return end
	if GetTime() > pendingFlightUntil then pendingFlight = nil return end
	if UnitOnTaxi and UnitOnTaxi("player") then pendingFlight = nil return end
	local nodes = taxiNodes()
	if #nodes == 0 then return end  -- flight map not open yet
	local want = pendingFlight
	pendingFlight = nil
	for _, n in ipairs(nodes) do
		if n.name == want then
			if n.ok then
				print_("flying with the leader to |cffffff00" .. want .. "|r")
				TakeTaxiNode(n.index)
			else
				print_("|cffffaa00can't fly to " .. want .. ":|r not reachable from here")
			end
			return
		end
	end
	print_("|cffffaa00can't fly to " .. want .. ":|r flight path not known")
end

function handlers.TAXIMAP_OPENED()
	wipe(taxiNames)
	for _, n in ipairs(taxiNodes()) do taxiNames[n.index] = n.name end
	if pendingFlight then C_Timer.After(0.2, tryPendingFlight) end
end

local function onLeaderFlight(sender, dest)
	if not HB.db.followFlights or not HB.IsLeaderName(sender) or not str(dest) then return end
	pendingFlight, pendingFlightUntil = dest, GetTime() + PENDING_FLIGHT
	debug("leader flies to " .. dest)
	tryPendingFlight()
end

if TakeTaxiNode then
	hooksecurefunc("TakeTaxiNode", function(index)
		if not HB.db or not HB.IAmLeader() then return end
		local name = taxiNames[index] or (TaxiNodeName and TaxiNodeName(index))
		if str(name) then send("P|" .. name:gsub("|", "")) end
	end)
end

-- ---------------------------------------------------------------- team death controls
-- One-shot requests: a toon that is not ready waits for another click.
-- Never queue a resurrection for later or accept spirit-healer penalties.
local function deathAction(action)
	if not UnitIsDeadOrGhost("player") then return end
	local ghost = UnitIsGhost and UnitIsGhost("player")
	if action == "release" then
		if not UnitIsGhost or ghost or not RepopMe then return end
		if IsEncounterSuppressingRelease and IsEncounterSuppressingRelease() then return end
		if HasNoReleaseAura and HasNoReleaseAura() then return end
		if IsFalling and IsFalling() and not (IsOutOfBounds and IsOutOfBounds()) then return end
		RepopMe()
	elseif action == "resurrect" then
		if not StaticPopup_Visible or not GetCorpseRecoveryDelay then return end
		local noTimer = StaticPopup_Visible("RESURRECT_NO_TIMER")
		if AcceptResurrect and (noTimer or StaticPopup_Visible("RESURRECT")
			or StaticPopup_Visible("RESURRECT_NO_SICKNESS")) then
			if noTimer or GetCorpseRecoveryDelay() == 0 then
				AcceptResurrect()
				StaticPopup_Hide("RESURRECT")
				StaticPopup_Hide("RESURRECT_NO_SICKNESS")
				StaticPopup_Hide("RESURRECT_NO_TIMER")
			end
		elseif ghost and RetrieveCorpse and StaticPopup_Visible("RECOVER_CORPSE")
			and GetCorpseRecoveryDelay() == 0 then
			RetrieveCorpse()
		end
	end
end

function HB.TeamDeathAction(action)
	if action ~= "release" and action ~= "resurrect" then return end
	if not HB.IAmLeader() then print_("only the team leader can do that") return end
	send("D|" .. action)
	deathAction(action)
end

-- ---------------------------------------------------------------- protocol
-- Every addon message is <kind>|<fields>. The table says who sends each kind to whom,
-- and whom a receiver accepts it from ("team": a name in this toon's team list,
-- "leader": this toon's stored leader).
--   kind  direction            fields                                  accepted from
--   M     leader -> group      M|<leader>|<name>=<role>;...            see onTeamMessage
--   R     toon -> group        R|<role>|<name>                         team, naming itself
--   F     toon -> group        F|S|<target>, F|X: follow changes;      team
--                              F|? asks all; F|s|<target>, F|x answer
--   T     toon -> group        T|<focus name> (empty: no focus)        team
--   S     toon -> group        S|lvl|xp|xpMax|rested|copper|free|slots team
--   E     follower -> group    E|<error code> (see ERRORS)             team
--   P     leader -> group      P|<flight destination name>             leader
--   D     leader -> group      D|release or D|resurrect                 leader
--   W     follower -> leader   W|<flags>|<from>|<i>|<n>|<text>         team
--   Y     leader -> toon       Y|<toon>|<to>|<i>|<n>|<text>            leader
--   K     toon -> leader       K|<to>|ok|fail|hidden|off               team
-- Group kinds count only on the group channel. W, Y and K go out as addon whispers
-- (0.9.0 and later); they are also taken from the group channel, where older
-- versions send them. Anything else (older HELLO messages included) is dropped.
local POLICY = {
	M = "offer", R = "team", F = "team", T = "team", S = "team", E = "team",
	P = "leader", D = "leader", W = "team", Y = "leader", K = "team",
}
local WHISPER_KINDS = { W = true, Y = true, K = true }
local GROUP_CHANNELS = { PARTY = true, RAID = true, INSTANCE_CHAT = true }

local function accepted(kind, channel, sender)
	local policy = POLICY[kind]
	if not policy then return false end
	if not GROUP_CHANNELS[channel] and not (channel == "WHISPER" and WHISPER_KINDS[kind]) then return false end
	if policy == "leader" then return HB.IsLeaderName(sender) end
	if policy == "team" then return isTeamName(sender) end
	return true  -- "offer": onTeamMessage checks the sender itself and may ask for /hb accept
end

function handlers.CHAT_MSG_ADDON(prefix, msg, channel, sender)
	if prefix ~= PREFIX or secret(msg) or secret(sender) or secret(channel) or type(msg) ~= "string" then return end
	if HB.Norm(sender) == HB.Norm(HB.UnitIdent("player")) then return end
	local kind = msg:match("^([^|]*)")
	if not accepted(kind, channel, sender) then
		debug("ignored " .. kind:sub(1, 8) .. " from " .. tostring(sender) .. " (" .. tostring(channel) .. ")")
		return
	end
	-- whisper messages carry free text (which may contain "|"), so they are matched whole
	if kind == "W" then onWhisperForward(sender, msg) return end
	if kind == "Y" then onReplyRequest(sender, msg) return end
	if kind == "S" then onStats(sender, select(2, strsplit("|", msg))) return end
	if kind == "P" then onLeaderFlight(sender, msg:sub(3)) return end
	local _, code, arg = strsplit("|", msg)
	if kind == "D" then
		if msg == "D|release" or msg == "D|resurrect" then deathAction(code) end
		return
	end
	if kind == "K" then onRelayResult(sender, code, arg) return end
	if kind == "M" then onTeamMessage(sender, code, arg) return end
	if kind == "R" then onRoleMessage(sender, code, arg) return end
	if kind == "T" then setFocus(sender, code ~= "" and code or nil) return end
	if kind == "F" and code == "?" then answerQuery() return end
	if kind == "F" and (code == "s" or code == "x") then  -- state report, not a change: no alert
		setFollowState(sender, code:upper(), arg)
		return
	end
	if kind == "F" and (code == "S" or code == "X") then
		setFollowState(sender, code, arg)
		if not HB.IAmLeader() then return end
		if code == "X" then
			HB.PlaySound("leaderAlert")
			leaderAlert(shortName(sender) .. " stopped following!")
		elseif HB.db.alertOnFollowStart then
			leaderAlert(shortName(sender) .. " is following", { r = 0.2, g = 1, b = 0.2 })
		end
	elseif kind == "E" and HB.IAmLeader() and HB.db.showRelayedErrors then
		print_("|cffffaa00" .. shortName(sender) .. ":|r " .. (ERROR_TEXT[code] or code or "?"))
	end
end

-- ---------------------------------------------------------------- quest tracker
-- Hides Blizzard's quest tracker. On WoW Forever the objective tracker shows itself
-- again on updates, so an OnShow hook hides it each time. A protected tracker can only
-- be hidden or shown out of combat; that waits for PLAYER_REGEN_ENABLED. Never calls
-- the tracker's Update(): on Forever that runs Blizzard's layout and taints it.
local trackerHooked, trackerHidden = false, false
local function questTracker()
	return ObjectiveTrackerFrame or WatchFrame or QuestWatchFrame
end

function HB.ApplyQuestTracker()
	local t = questTracker()
	if not t then return end
	local hide = HB.db.hideQuestTracker and true or false
	if not hide and not trackerHidden then return end  -- never touch a tracker we did not hide
	if InCombatLockdown() and t.IsProtected and t:IsProtected() then
		f:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	if hide and not trackerHooked then
		t:HookScript("OnShow", function()
			if HB.db.hideQuestTracker then HB.ApplyQuestTracker() end
		end)
		trackerHooked = true
	end
	if hide then
		if t:IsShown() then t:Hide() end
		trackerHidden = true
	else
		t:Show()
		trackerHidden = false
	end
end

-- ---------------------------------------------------------------- team offer popup
-- A team offer from a new leader shows an Accept / Decline popup on this toon, after
-- combat if it arrives in combat. /hb accept and the key binding do the same.
local OFFER_POPUP = "HAPLOBOX_TEAM_OFFER"
local offerAfterCombat = false

function HB.ShowTeamOffer()
	local leader, names = HB.PendingTeamText()
	if not leader or not (StaticPopupDialogs and StaticPopup_Show) then return end
	if InCombatLockdown() then
		offerAfterCombat = true
		f:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	offerAfterCombat = false
	StaticPopupDialogs[OFFER_POPUP] = StaticPopupDialogs[OFFER_POPUP] or {
		text = "HaploBox: %s wants to lead your team (%s).",
		button1 = ACCEPT or "Accept",
		button2 = DECLINE or "Decline",
		OnAccept = function() HB.AcceptTeam() end,
		OnCancel = function(_, _, reason)
			if reason == "clicked" then HB.DeclineTeam() end  -- not when another popup replaces it
		end,
		timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
	}
	if StaticPopup_Hide then StaticPopup_Hide(OFFER_POPUP) end  -- a newer offer replaces the shown one
	StaticPopup_Show(OFFER_POPUP, leader, names)
end

function HB.HideTeamOffer()
	offerAfterCombat = false
	if StaticPopup_Hide then StaticPopup_Hide(OFFER_POPUP) end
end

function handlers.PLAYER_REGEN_ENABLED()
	f:UnregisterEvent("PLAYER_REGEN_ENABLED")
	HB.ApplyQuestTracker()
	if offerAfterCombat then HB.ShowTeamOffer() end
end

-- Party role icon and group finder roles from my team role.
function HB.ApplyRoles()
	if not HB.db.autoPartyRole then return end
	local role = HB.MyRole()
	local wanted = GAME_ROLE[role or ""]
	if not wanted then return end
	if SetLFGRoles then
		local leaderFlag = GetLFGRoles and select(1, GetLFGRoles()) or false
		pcall(SetLFGRoles, leaderFlag, role == "tank", role == "healer", role == "dps")
	end
	if IsInGroup() and UnitSetRole then
		local ok, current = pcall(UnitGroupRolesAssigned or function() end, "player")
		if not ok or secret(current) or current ~= wanted then
			local done = pcall(UnitSetRole, "player", wanted)
			debug("party role " .. wanted .. (done and "" or " failed"))
		end
	end
end

function handlers.ROLE_POLL_BEGIN()
	if not HB.db.autoPartyRole or not GAME_ROLE[HB.MyRole() or ""] then return end
	HB.ApplyRoles()
	if RolePollPopup then
		C_Timer.After(0.1, function()
			if StaticPopupSpecial_Hide then pcall(StaticPopupSpecial_Hide, RolePollPopup) else RolePollPopup:Hide() end
		end)
	end
end

function handlers.LFG_ROLE_CHECK_SHOW()
	if not HB.db.autoRoleCheck or not (SetLFGRoles and CompleteLFGRoleCheck) then return end
	local role = validRole(HB.MyRole())
	if not role then return end  -- no team role: leave the role check to the player
	local leaderFlag = GetLFGRoles and select(1, GetLFGRoles()) or false
	SetLFGRoles(leaderFlag, role == "tank", role == "healer", role == "dps")
	CompleteLFGRoleCheck(true)
	debug("role check answered as " .. role)
end

function handlers.UNIT_ENTERING_VEHICLE(unit)
	if unit == "player" then HB.PlaySound("mountOn") end
end

function handlers.UNIT_EXITING_VEHICLE(unit)
	if unit == "player" then HB.PlaySound("mountOff") end
end

f:SetScript("OnEvent", function(_, event, ...)
	local h = handlers[event]
	if h then
		local ok, err = pcall(h, ...)
		if not ok then debug(event .. ": " .. tostring(err)) end
	end
end)
for event in pairs(handlers) do
	pcall(f.RegisterEvent, f, event)  -- some events do not exist on every client
end

-- ---------------------------------------------------------------- key bindings
-- Names for the actions in Bindings.xml (Esc > Options > Keybindings > AddOns).
BINDING_HEADER_HAPLOBOX = "HaploBox"
BINDING_NAME_HAPLOBOX_LEAD = "Make this toon the leader and send the team"
BINDING_NAME_HAPLOBOX_ACCEPT = "Accept the team offered by a new leader"
BINDING_NAME_HAPLOBOX_TARGET_LEADER = "Make my target the leader"
BINDING_NAME_HAPLOBOX_ROLE_TANK = "My role: tank"
BINDING_NAME_HAPLOBOX_ROLE_HEALER = "My role: healer"
BINDING_NAME_HAPLOBOX_ROLE_DPS = "My role: dps"

-- ---------------------------------------------------------------- slash
local function help()
	print_("commands:")
	print_("  /hb status - leader, role and settings")
	print_("  /hb leader [name] - set the leader (no name: your target)")
	print_("  /hb accept - accept the team offered by a new leader (or click Accept in the popup)")
	print_("  /hb team - on the leader, in a party: make this group the team and send it to every toon")
	print_("  /hb team show - list the team")
	print_("  /hb role tank|healer|dps - your role (also in the options panel); sent to the group, sets your party role")
	print_("  /hb ffa - set free-for-all loot (group leader only)")
	print_("  /hb share - share every quest in your log with the group")
	print_("  /hb sound <event> <value|off> - " .. "events: followOn followOff leaderAlert shareError inviteAccept whisperIn bagsFull mountOn mountOff")
	print_("  /hb test <event> - play a sound; /hb test alert - show the leader alert")
	print_("  /hb frame auto|show|hide - team frame on this toon (auto: only when it is the leader)")
	print_("  /hb frame lock | unlock - unlocked: drag the bar to move, drag the corner to resize")
	print_("  /hb frame colors | scale <0.5-2> | solo | reset - class colours, scale, show when solo, reset position and size")
	print_("  /hb frame xp | gold | bags | buffs - show or hide level and XP, gold, free bag slots, buffs")
	print_("  /hb r <text> - leader: reply to the last forwarded whisper, through the toon that got it")
	print_("  /hb tracker - hide or show Blizzard's quest tracker")
	print_("  /hb who - show how the game names you and your target")
	print_("  /hb options - open the options panel; /hb debug - toggle debug output")
	print_("  Key bindings: Esc > Options > Keybindings > AddOns > HaploBox")
end

SLASH_HAPLOBOX1, SLASH_HAPLOBOX2 = "/hb", "/haplobox"
SlashCmdList.HAPLOBOX = function(input)
	local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
	cmd = cmd:lower()
	if cmd == "leader" then
		HB.SetLeaderName(rest ~= "" and rest or HB.UnitIdent("target"))
	elseif cmd == "accept" then
		HB.AcceptTeam()
	elseif cmd == "role" then
		HB.SetMyRole(rest:lower())
	elseif cmd == "team" then
		if rest:lower() == "show" then print_("team: " .. HB.TeamSummary()) return end
		HB.SetTeamFromGroup()
	elseif cmd == "r" or cmd == "reply" then
		HB.Reply(rest)
	elseif cmd == "tracker" then
		HB.db.hideQuestTracker = not HB.db.hideQuestTracker
		HB.ApplyQuestTracker()
		print_("quest tracker " .. (HB.db.hideQuestTracker and "hidden" or "shown")
			.. (InCombatLockdown() and " (after combat)" or ""))
	elseif cmd == "ffa" then
		HB.SetFFA(false)
	elseif cmd == "share" then
		if not IsInGroup() then print_("not in a group") return end
		local n = C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries()
			or (GetNumQuestLogEntries and GetNumQuestLogEntries()) or 0
		local i = 0
		C_Timer.NewTicker(0.4, function()
			i = i + 1
			if C_QuestLog and C_QuestLog.GetInfo then
				local info = C_QuestLog.GetInfo(i)
				if info and not info.isHeader then HB.ShareQuest(i, info.questID) end
			else
				local _, _, _, isHeader = GetQuestLogTitle(i)
				if not isHeader then HB.ShareQuest(i) end
			end
		end, n)
		print_("sharing " .. n .. " quest log entries")
	elseif cmd == "sound" then
		local event, value = rest:match("^(%S+)%s*(.-)$")
		if not event or HB.db.sounds[event] == nil and DEFAULTS.sounds[event] == nil then
			print_("unknown sound event") return
		end
		if value == "" then print_(event .. " = " .. tostring(HB.db.sounds[event])) return end
		if value == "off" then value = false elseif tonumber(value) then value = tonumber(value) end
		HB.db.sounds[event] = value
		print_(event .. " = " .. tostring(value))
		HB.PlaySound(event)
	elseif cmd == "test" then
		if rest == "alert" then
			HB.PlaySound("leaderAlert")
			leaderAlert("Test Follower stopped following!")
		elseif DEFAULTS.sounds[rest] ~= nil then
			HB.lastSound = {}
			HB.PlaySound(rest)
		else
			print_("test what? alert or a sound event")
		end
	elseif cmd == "frame" then
		local a, b = rest:lower():match("^(%S*)%s*(.-)$")
		local alias = { on = "show", off = "hide", all = "show", leader = "auto" }
		a = alias[a] or a
		if a == "auto" or a == "show" or a == "hide" then
			HB.db.teamFrame = a
			print_("team frame on this toon: " .. a)
		elseif a == "scale" and tonumber(b) then
			HB.db.partyScale = math.min(2, math.max(0.5, tonumber(b)))
			print_("team frame scale: " .. HB.db.partyScale)
		elseif a == "solo" then
			HB.db.partyFrameSolo = not HB.db.partyFrameSolo
			print_("team frame when solo: " .. (HB.db.partyFrameSolo and "shown" or "hidden"))
		elseif a == "lock" or a == "unlock" then
			if HB.SetTeamFrameLocked then HB.SetTeamFrameLocked(a == "lock") end
		elseif a == "colors" or a == "colours" then
			HB.db.teamClassColors = not HB.db.teamClassColors
			print_("team frame class colours: " .. (HB.db.teamClassColors and "on" or "off"))
		elseif a == "xp" or a == "gold" or a == "bags" or a == "buffs" then
			local key = ({ xp = "teamShowXP", gold = "teamShowGold", bags = "teamShowBags", buffs = "teamShowBuffs" })[a]
			HB.db[key] = not HB.db[key]
			print_("team frame " .. a .. ": " .. (HB.db[key] and "shown" or "hidden"))
		elseif a == "reset" then
			if HB.ResetPartyPosition then HB.ResetPartyPosition() end
		else
			print_("team frame on this toon: " .. tostring(HB.db.teamFrame) .. ", scale " .. tostring(HB.db.partyScale)
				.. ". Use /hb frame auto|show|hide|lock|unlock|colors|xp|gold|bags|buffs|scale <n>|solo|reset")
			return
		end
		if HB.LayoutPartyFrame then HB.LayoutPartyFrame() end
	elseif cmd == "who" then
		print_("you: " .. tostring(HB.UnitIdent("player")) .. "  target: " .. tostring(HB.UnitIdent("target"))
			.. "  realm: " .. tostring(myRealm))
	elseif cmd == "status" then
		local ffa = HB.IsFFA()
		local loot = ffa == true and "free for all" or ffa == false and "not free for all" or "unknown"
		print_("leader: " .. tostring(HB.Leader()) .. (HB.IAmLeader() and " (you)" or "")
			.. "  role: " .. tostring(HB.MyRole()) .. "  loot: " .. (IsInGroup() and loot or "not in a group"))
	elseif cmd == "options" or cmd == "config" then
		if HB.OpenOptions then HB.OpenOptions() end
	elseif cmd == "debug" then
		HB.db.debug = not HB.db.debug
		print_("debug " .. (HB.db.debug and "on" or "off"))
	else
		help()
	end
end
