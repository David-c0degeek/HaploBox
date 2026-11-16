-- Abandon a quest on the whole team. When the leader abandons a quest, a popup asks
-- whether the followers should abandon it too. Yes sends it to the group; No does
-- nothing on the followers. A follower acts only on its own stored leader's message,
-- only for a quest it has, and only with "Abandon quests when the leader does" on.
--   Q|<questID>|<title>      leader -> group
--   B|<result>|<title>       toon -> leader, addon whisper: done, missing, off
local HB = HaploBox

local POPUP = "HAPLOBOX_ABANDON_TEAM"
local abandoning = false   -- true while this toon abandons for its leader
local captured             -- { id, title } of the quest the player is abandoning
local offer                -- what the popup shows: { id, title }

local function clean(s) return type(s) == "string" and s:gsub("|", "") or nil end

-- ---------------------------------------------------------------- quest log
local function entries()
	local list = {}
	if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
		local n = C_QuestLog.GetNumQuestLogEntries() or 0
		for i = 1, n do
			local info = C_QuestLog.GetInfo(i)
			if info and not info.isHeader and info.title then
				list[#list + 1] = { index = i, id = info.questID, title = info.title }
			end
		end
	elseif GetNumQuestLogEntries and GetQuestLogTitle then
		local n = GetNumQuestLogEntries() or 0
		for i = 1, n do
			local title, _, _, isHeader, _, _, _, id = GetQuestLogTitle(i)
			if title and not isHeader then list[#list + 1] = { index = i, id = id, title = title } end
		end
	end
	return list
end

-- The quest this toon has that matches. By id when both sides know it; by title
-- only when exactly one quest has that title.
local function find(id, title)
	local list, byTitle = entries(), {}
	for _, q in ipairs(list) do
		if id and q.id and q.id == id then return q end
		if q.title == title then byTitle[#byTitle + 1] = q end
	end
	if not id or not list[1] or not list[1].id then
		if #byTitle == 1 then return byTitle[1] end
	end
end

local function abandon(q)
	abandoning = true
	local ok = pcall(function()
		if C_QuestLog and C_QuestLog.SetAbandonQuest and C_QuestLog.AbandonQuest and q.id then
			C_QuestLog.SetSelectedQuest(q.id)
			C_QuestLog.SetAbandonQuest()
			C_QuestLog.AbandonQuest()
		else
			SelectQuestLogEntry(q.index)
			SetAbandonQuest()
			AbandonQuest()
		end
	end)
	abandoning = false
	return ok
end

-- ---------------------------------------------------------------- leader
local function teamInGroup()
	local me = HB.Norm(HB.UnitIdent("player"))
	for _, n in ipairs(HaploBoxTeam and HaploBoxTeam.order or {}) do
		if HB.Norm(n) ~= me and HB.InGroup(n) then return true end
	end
	return false
end

local function capture()
	if abandoning then return end
	captured = nil
	if C_QuestLog and C_QuestLog.GetAbandonQuest then
		local ok, id = pcall(C_QuestLog.GetAbandonQuest)
		local title = ok and id and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
		if title then captured = { id = id, title = title } return end
	end
	local i = GetQuestLogSelection and GetQuestLogSelection()
	if i and GetQuestLogTitle then
		local title, _, _, isHeader, _, _, _, id = GetQuestLogTitle(i)
		if title and not isHeader then captured = { id = id, title = title } return end
	end
	local name = GetAbandonQuestName and GetAbandonQuestName()
	if type(name) == "string" and name ~= "" then captured = { title = name } end
end

function HB.SendAbandon(q)
	local title = clean(q and q.title)
	if not title or title == "" then return end
	HB.SendGroup("Q|" .. (tonumber(q.id) or "") .. "|" .. title)
	HB.print("asked the team to abandon |cffffff00" .. title .. "|r")
end

local function afterAbandon()
	if abandoning then return end
	local q = captured
	captured = nil
	if not q or not HB.db or not HB.db.askAbandonQuests then return end
	if not (HB.IAmLeader() and IsInGroup() and teamInGroup()) then return end
	offer = q
	if StaticPopupDialogs and StaticPopup_Show then
		StaticPopupDialogs[POPUP] = {
			text = "HaploBox: abandon \"%s\" on all followers too?",
			button1 = YES or "Yes",
			button2 = NO or "No",
			OnAccept = function()
				local o = offer
				offer = nil
				if o then HB.SendAbandon(o) end
			end,
			OnCancel = function() offer = nil end,
			timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
		}
		StaticPopup_Show(POPUP, q.title)
	end
end

if C_QuestLog and C_QuestLog.SetAbandonQuest and C_QuestLog.AbandonQuest then
	hooksecurefunc(C_QuestLog, "SetAbandonQuest", capture)
	hooksecurefunc(C_QuestLog, "AbandonQuest", afterAbandon)
elseif SetAbandonQuest and AbandonQuest then
	hooksecurefunc("SetAbandonQuest", capture)
	hooksecurefunc("AbandonQuest", afterAbandon)
end

-- ---------------------------------------------------------------- follower
local RESULT = { done = "abandoned it", missing = "did not have it", off = "has this turned off", failed = "could not abandon it" }

function HB.OnQuestAbandon(sender, msg)
	local id, title = msg:match("^Q|(%d*)|(.+)$")
	if not title then return end
	id = tonumber(id)
	local result
	if not HB.db.followAbandonQuests then
		result = "off"
	else
		local q = find(id, title)
		if not q then
			result = "missing"
		elseif abandon(q) then
			result = "done"
			HB.print("abandoned |cffffff00" .. title .. "|r for the leader")
		else
			result = "failed"
		end
	end
	HB.Whisper(sender, "B|" .. result .. "|" .. title)
end

function HB.OnAbandonResult(sender, msg)
	local result, title = msg:match("^B|(%a+)|(.+)$")
	if not RESULT[result] then return end
	HB.print("|cffffff00" .. sender:gsub("%-.*$", "") .. "|r " .. RESULT[result] .. ": " .. title)
end
