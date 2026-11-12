-- HaploBox: multibox team helper.
-- Followers report follow start/stop and spell errors to the leader over a
-- hidden addon channel. The leader gets a raid-warning style message on its
-- own screen. Nothing here touches protected frames, so it cannot taint the UI.

local ADDON = ...
local HB = {}
_G.HaploBox = HB

local PREFIX = "HaploBox"
local VERSION = "0.2.1"

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

function HB.MyRole()
	local roles = HaploBoxTeam and HaploBoxTeam.roles
	if not roles then return nil end
	local me = HB.Norm(HB.UnitIdent("player"))
	for name, role in pairs(roles) do
		if HB.Norm(name) == me then return role end
	end
end

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

-- ---------------------------------------------------------------- events
local f = CreateFrame("Frame")
HB.frame = f
local followEndPending, lastFollowAction
local suppressShareQuest, suppressUntil = nil, 0
local shareErrorPatterns
local errorThrottle = {}

local handlers = {}

-- Follow state of every team member: "S" following, "X" not following.
-- Followers broadcast changes to the group, so every toon knows every state.
HB.followState = {}
local function setFollowState(name, state)
	local k = HB.Norm(name)
	if not k or HB.followState[k] == state then return end
	HB.followState[k] = state
	if HB.OnFollowStateChanged then HB.OnFollowStateChanged() end
end
local function myFollowState() return lastFollowAction == "BEGIN" and "S" or "X" end

local lastQuery = 0
local function queryFollowStates()
	if not IsInGroup() or GetTime() - lastQuery < 3 then return end
	lastQuery = GetTime()
	send("F|?")
	if not HB.IAmLeader() then send("F|" .. myFollowState():lower()) end
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
end

function handlers.PLAYER_LOGIN()
	local leader = HB.Leader()
	if leader then
		print_(VERSION .. " loaded. Leader: |cffffff00" .. leader .. "|r" .. (HB.IAmLeader() and " (you)" or ""))
	else
		print_(VERSION .. " loaded. No leader set: target the leader and type |cffffff00/hb leader|r")
	end
end

function handlers.AUTOFOLLOW_BEGIN(name)
	followEndPending = nil
	if lastFollowAction == "BEGIN" then return end
	lastFollowAction = "BEGIN"
	setFollowState(HB.UnitIdent("player"), "S")
	HB.PlaySound("followOn")
	send("F|S")
end

function handlers.AUTOFOLLOW_END()
	-- WoW fires END followed by BEGIN when following is refreshed: wait before reporting.
	local token = {}
	followEndPending = token
	C_Timer.After(0.3, function()
		if followEndPending ~= token then return end
		followEndPending = nil
		lastFollowAction = "END"
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
	if grew then C_Timer.After(2, queryFollowStates) end
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
	local kind, code = strsplit("|", msg)
	if kind == "F" and code == "?" then
		if not HB.IAmLeader() then send("F|" .. myFollowState():lower()) end
		return
	end
	if kind == "F" and (code == "s" or code == "x") then  -- state report, not a change: no alert
		setFollowState(sender, code:upper())
		return
	end
	if kind == "F" and (code == "S" or code == "X") then setFollowState(sender, code) end
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
	print_("  /hb role tank|healer|dps - your role for group finder role checks")
	print_("  /hb ffa - set free-for-all loot (group leader only)")
	print_("  /hb share - share every quest in your log with the group")
	print_("  /hb sound <event> <value|off> - " .. "events: followOn followOff leaderAlert shareError inviteAccept mountOn mountOff")
	print_("  /hb test <event> - play a sound; /hb test alert - show the leader alert")
	print_("  /hb frame auto|show|hide - team frame on this toon (auto: only when it is the leader)")
	print_("  /hb frame scale <0.5-2> | solo | reset - size, show when solo, reset position (shift-drag moves it)")
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
		local r = rest:lower()
		if r ~= "tank" and r ~= "healer" and r ~= "dps" then print_("role must be tank, healer or dps") return end
		HaploBoxTeam.roles = HaploBoxTeam.roles or {}
		HaploBoxTeam.roles[HB.UnitIdent("player")] = r
		print_("role set to " .. r)
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
		elseif a == "reset" then
			if HB.ResetPartyPosition then HB.ResetPartyPosition() end
		else
			print_("team frame on this toon: " .. tostring(HB.db.teamFrame) .. ", scale " .. tostring(HB.db.partyScale)
				.. ". Use /hb frame auto|show|hide|scale <n>|solo|reset")
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
