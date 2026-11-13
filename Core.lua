-- HaploBox: multibox team helper.
-- Followers report follow start/stop and spell errors to the leader over a
-- hidden addon channel. The leader gets a raid-warning style message on its
-- own screen. Nothing here touches protected frames, so it cannot taint the UI.

local ADDON = ...
local HB = {}
_G.HaploBox = HB

local PREFIX = "HaploBox"
local VERSION = "0.8.0"

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
		if HB.Norm(n) == key then return role end
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

local function send(msg)
	if not IsInGroup() then return end
	local channel = IsInRaid() and "RAID" or "PARTY"
	if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then channel = "INSTANCE_CHAT" end
	C_ChatInfo.SendAddonMessage(PREFIX, msg, channel)
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
-- order, with the leader first. It is sent as M|<leader>|<name>=<role>;... and every
-- toon that receives it from that leader stores it. /hb role sends R|<role>|<name>.
local function clean(n) return (str(n) or ""):gsub("[|;=]", "") end

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

local function applyTeam(leader, list)
	HaploBoxTeam.leader = leader
	HaploBoxTeam.order = {}
	HaploBoxTeam.roles = {}
	for _, m in ipairs(list) do
		HaploBoxTeam.order[#HaploBoxTeam.order + 1] = m.name
		HaploBoxTeam.roles[m.name] = m.role
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
				local role = HB.RoleOf(name) or (u == "player" and "tank" or "dps")
				list[#list + 1] = { name = name, role = role }
				wire[#wire + 1] = name .. "=" .. role
			end
		end
	end
	applyTeam(me, list)
	send("M|" .. me .. "|" .. table.concat(wire, ";"))
	print_("team set and sent: " .. HB.TeamSummary())
end

-- My role, from the options panel or /hb role: stored, sent to the group, applied.
function HB.SetMyRole(r)
	if r ~= "tank" and r ~= "healer" and r ~= "dps" then print_("role must be tank, healer or dps") return end
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
	HaploBoxTeam.leader = clean(HB.UnitIdent("player"))
	refreshTeam()
	print_("you are the leader. Group up and press it again (or /hb team) to send the team to every toon.")
end

local function onTeamMessage(sender, leader, body)
	-- only the leader named in the message may send it
	if HB.Norm(sender) ~= HB.Norm(leader) then return end
	local list = {}
	for entry in (body or ""):gmatch("[^;]+") do
		local name, role = entry:match("^(.-)=(%a+)$")
		if name and name ~= "" then list[#list + 1] = { name = name, role = role } end
	end
	if #list == 0 then return end
	applyTeam(leader, list)
	print_("team set by |cffffff00" .. shortName(leader) .. "|r: " .. HB.TeamSummary())
end

local function onRoleMessage(sender, role, name)
	if HB.Norm(sender) ~= HB.Norm(name) then return end
	if role ~= "tank" and role ~= "healer" and role ~= "dps" then return end
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
	send(focusMsg())
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
	send(lastStatsMsg)
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
-- whispering the toon directly within 5 minutes of the last forwarded whisper.
-- The toon whispers the text on and confirms with K|<to>|ok, K|<to>|fail or K|<to>|hidden.
-- Long text is split: addon messages are limited to 255 bytes.
local CHUNK, RELAY_WINDOW = 200, 300
local function sendText(head, text)
	text = text or ""
	local pieces, pos = {}, 1
	repeat
		local stop = pos + CHUNK - 1
		-- never cut inside a UTF-8 character
		while stop < #text and stop > pos and text:byte(stop + 1) >= 0x80 and text:byte(stop + 1) < 0xC0 do
			stop = stop - 1
		end
		pieces[#pieces + 1] = text:sub(pos, stop)
		pos = stop + 1
	until pos > #text
	for i, p in ipairs(pieces) do send(head .. "|" .. i .. "|" .. #pieces .. "|" .. p) end
end

local partial = {}
local function joinText(key, i, n, piece)
	i, n = tonumber(i), tonumber(n)
	if not i or not n or n < 1 or n > 10 or i > n then return nil end
	if n == 1 then return piece end
	if i == 1 or not partial[key] then partial[key] = {} end
	partial[key][i] = piece
	if i < n then return nil end
	local p = partial[key]
	partial[key] = nil
	for j = 1, n do if not p[j] then return nil end end
	return table.concat(p, "", 1, n)
end

local function isTeamName(name)
	local k = HB.Norm(name)
	if not k then return false end
	if HB.IsLeaderName(name) then return true end
	for _, n in ipairs(HaploBoxTeam.order or {}) do if HB.Norm(n) == k then return true end end
	for n in pairs(HaploBoxTeam.roles or {}) do if HB.Norm(n) == k then return true end end
	return false
end

local lastWhisperer, lastWhisperAt = nil, 0
local function relayTo(who, text)
	local fn = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
	local ok = fn and pcall(fn, text, "WHISPER", nil, who)
	if ok then lastWhisperAt = GetTime() end
	send("K|" .. who .. "|" .. (ok and "ok" or "fail"))
end

function handlers.CHAT_MSG_WHISPER(text, sender, _, _, _, flag)
	sender = str(sender)
	if not sender or not IsInGroup() or HB.IAmLeader() then return end
	if HB.IsLeaderName(sender) then
		-- the leader answers a forwarded whisper by whispering this toon
		if not HB.db.relayReplies or not lastWhisperer or GetTime() - lastWhisperAt > RELAY_WINDOW then return end
		if secret(text) or type(text) ~= "string" then send("K|" .. lastWhisperer .. "|hidden") return end
		relayTo(lastWhisperer, text)
		return
	end
	if not HB.db.forwardWhispers or isTeamName(sender) then return end
	lastWhisperer, lastWhisperAt = sender, GetTime()
	local flags = (flag == "GM" or flag == "DEV") and "GM" or ""
	if secret(text) or type(text) ~= "string" then
		sendText("W|" .. flags .. "H|" .. sender, "")
	else
		sendText("W|" .. flags .. "|" .. sender, text)
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
	if text and text ~= "" then relayTo(who, text) end
end

local function onRelayResult(sender, who, result)
	if not HB.IAmLeader() then return end
	if result == "ok" then
		print_("|cffff80ffsent to " .. shortName(who) .. " via " .. shortName(sender) .. "|r")
	elseif result == "hidden" then
		print_("|cffff4444" .. shortName(sender) .. " could not read your reply (hidden by the game); use /hb r|r")
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
	sendText("Y|" .. lr.toon .. "|" .. lr.who, text)
end

local lastQuery = 0
local function queryFollowStates()
	if not IsInGroup() or GetTime() - lastQuery < 3 then return end
	lastQuery = GetTime()
	send("F|?")
	if not HB.IAmLeader() then send(myFollowMsg(true)) end
	send(focusMsg())
	sendStats()
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
	if HB.CreateOptions then HB.CreateOptions() end
end

function handlers.PLAYER_ENTERING_WORLD()
	C_Timer.After(3, queryFollowStates)
	updateMyStats()
end

function handlers.PLAYER_LOGIN()
	C_Timer.After(2, HB.ApplyRoles)
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
		local present = false
		for i = 1, GetNumGroupMembers() do
			local unit = IsInRaid() and ("raid" .. i) or ("party" .. i)
			if HB.IsLeaderName(HB.UnitIdent(unit)) then present = true end
		end
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
	if HB.db.autoAcceptShared then
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
	if not HB.db.shareErrorAlert or secret(msg) or type(msg) ~= "string" then return end
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

function handlers.CHAT_MSG_ADDON(prefix, msg, _, sender)
	if prefix ~= PREFIX or secret(msg) or secret(sender) then return end
	if HB.Norm(sender) == HB.Norm(HB.UnitIdent("player")) then return end
	-- whisper messages carry free text (which may contain "|"), so they are matched whole
	local head = msg:sub(1, 2)
	if head == "W|" then onWhisperForward(sender, msg) return end
	if head == "Y|" then onReplyRequest(sender, msg) return end
	if head == "S|" then onStats(sender, select(2, strsplit("|", msg))) return end
	local kind, code, arg = strsplit("|", msg)
	if kind == "K" then onRelayResult(sender, code, arg) return end
	if kind == "F" and code == "?" then
		if not HB.IAmLeader() then send(myFollowMsg(true)) end
		send(focusMsg())
		sendStats()
		return
	end
	if kind == "M" then onTeamMessage(sender, code, arg) return end
	if kind == "R" then onRoleMessage(sender, code, arg) return end
	if kind == "T" then
		setFocus(sender, code ~= "" and code or nil)
		return
	end
	if kind == "F" and (code == "s" or code == "x") then  -- state report, not a change: no alert
		setFollowState(sender, code:upper(), arg)
		return
	end
	if kind == "F" and (code == "S" or code == "X") then setFollowState(sender, code, arg) end
	if kind == "F" and HB.IAmLeader() then
		if code == "X" then
			HB.PlaySound("leaderAlert")
			leaderAlert(shortName(sender) .. " stopped following!")
		elseif code == "S" and HB.db.alertOnFollowStart then
			leaderAlert(shortName(sender) .. " is following", { r = 0.2, g = 1, b = 0.2 })
		end
	elseif kind == "E" and HB.IAmLeader() and HB.db.showRelayedErrors then
		print_("|cffffaa00" .. shortName(sender) .. ":|r " .. (ERROR_TEXT[code] or code or "?"))
	elseif kind == "HELLO" then
		debug("hello from " .. tostring(sender) .. " " .. tostring(code))
	end
end

local GAME_ROLE = { tank = "TANK", healer = "HEALER", dps = "DAMAGER" }
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
	local role = HB.MyRole()
	if not role then return end
	local leaderFlag = GetLFGRoles and select(1, GetLFGRoles()) or false
	SetLFGRoles(leaderFlag, role == "tank", role == "healer", role == "dps" or role == "damager")
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

-- ---------------------------------------------------------------- slash
local function help()
	print_("commands:")
	print_("  /hb status - leader, role and settings")
	print_("  /hb leader [name] - set the leader (no name: your target)")
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
	print_("  /hb who - show how the game names you and your target")
	print_("  /hb options - open the options panel; /hb debug - toggle debug output")
end

SLASH_HAPLOBOX1, SLASH_HAPLOBOX2 = "/hb", "/haplobox"
SlashCmdList.HAPLOBOX = function(input)
	local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
	cmd = cmd:lower()
	if cmd == "leader" then
		local name = rest ~= "" and rest or HB.UnitIdent("target")
		if not name then print_("no target and no name given") return end
		HaploBoxTeam.leader = name
		print_("leader set to |cffffff00" .. name .. "|r")
	elseif cmd == "role" then
		HB.SetMyRole(rest:lower())
	elseif cmd == "team" then
		if rest:lower() == "show" then print_("team: " .. HB.TeamSummary()) return end
		HB.SetTeamFromGroup()
	elseif cmd == "r" or cmd == "reply" then
		HB.Reply(rest)
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
		print_("leader: " .. tostring(HB.Leader()) .. (HB.IAmLeader() and " (you)" or "")
			.. "  role: " .. tostring(HB.MyRole()) .. "  loot: " .. tostring(GetLootMethod and GetLootMethod()))
	elseif cmd == "options" or cmd == "config" then
		if HB.OpenOptions then HB.OpenOptions() end
	elseif cmd == "debug" then
		HB.db.debug = not HB.db.debug
		print_("debug " .. (HB.db.debug and "on" or "off"))
	else
		help()
	end
end
