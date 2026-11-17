-- HaploBox settings: one window in sections (Esc > Options > AddOns > HaploBox, or
-- /hb options [section]), and a quick settings popup on the team frame (/hb quick).
-- Both read the same list below and change settings only through HB.SetOption, so
-- they always show the same values.
local HB = HaploBox

-- who: whom a setting affects. Settings are saved in HaploBoxDB, which WoW keeps per
-- account (every character on this WoW account shares them), and never sent to the team.
local WHO = {
	me = "",
	leader = "on the leader",
	followers = "on followers",
}

local FRAME_MODES = { "auto", "show", "hide" }
local SHARE_MODES = { "leader", "all", "off" }
local FRAME_MODE_TEXT = { auto = "leader only", show = "always", hide = "never" }
local SHARE_MODE_TEXT = { leader = "if I lead", all = "always", off = "never" }

-- kinds: toggle (checkbox), cycle (button through choices), scale, action (button).
local SECTIONS = {
	{ id = "team", title = "Team & roles", team = true },
	{ id = "frame", title = "Team frame", items = {
		{ "teamFrame", "cycle", "Show the team frame", choices = FRAME_MODES, text = FRAME_MODE_TEXT,
			help = "leader only: shown on the team leader. Also /hb frame auto|show|hide." },
		{ "teamView", "cycle", "View", choices = { "main", "mini" }, text = { main = "main", mini = "Mini Heal" },
			help = "Mini Heal: one big health tile per member for small windows. Click to target, [@mouseover] heals work. Also a key binding and /hb frame main|mini." },
		{ "teamLocked", "toggle", "Lock it in place (unlock to move and resize)" },
		{ "partyScale", "scale", "Scale" },
		{ "partyFrameSolo", "toggle", "Also show it when not in a group" },
		{ "teamClassColors", "toggle", "Class colours" },
		{ "teamShowXP", "toggle", "Level and XP bar" },
		{ "teamShowGold", "toggle", "Gold per character and team total" },
		{ "teamShowBags", "toggle", "Free bag slots per character and team total" },
		{ "teamShowBuffs", "toggle", "Group buffs with timers" },
		{ "teamHealPrediction", "toggle", "Incoming heals on the health bars",
			help = "From the game where it reports them, else from the team's own healers (estimates)." },
		{ "teamSendHeals", "toggle", "Tell the team about my heals (estimated sizes)",
			help = "Single-target heals with a cast time, sized from the spell's description." },
		{ "teamCastBars", "toggle", "Cast and channel bar on the health bars" },
		{ "teamManaRule", "toggle", "Five-second mana rule timer on the mana bars (Classic Era only)" },
		{ "teamShowHots", "toggle", "Heal-over-time icons on the health bars" },
		{ "teamHotNames", "text", "Heal-over-time spells",
			help = "Spell names, comma separated. Empty: Renew, Rejuvenation, Regrowth, Lifebloom, Wild Growth, Riptide." },
		{ "teamRequiredBuffs", "text", "Buffs everyone should have",
			help = "Buff names, comma separated, e.g. Power Word: Fortitude, Arcane Intellect. A row names the missing ones. Empty: off." },
		{ "teamBuffOverview", "toggle", "Window: every member's buffs" },
		{ "teamDebuffOverview", "toggle", "Window: every member's debuffs" },
		{ "reset", "action", "Reset position and size", run = function() HB.ResetPartyPosition() end },
		{ "acceptSharedUI", "toggle", "Take the layout the leader shares", who = "followers" },
		{ "shareUI", "action", "Share this layout with the team", run = function() HB.ShareUI() end,
			help = "Leader: sends to the team" },
		{ "undoUI", "action", "Undo the shared layout", run = function() HB.UndoSharedUI() end },
	} },
	{ id = "follow", title = "Follow & alerts", items = {
		{ "alertOnFollowStart", "toggle", "Also show a message when a follower starts following", who = "leader" },
		{ "relayErrors", "toggle", "Send my cast errors (range, line of sight, mana) to the leader", who = "followers" },
		{ "leadButton", "toggle", "Lead button: click it to take over as leader", who = "followers",
			help = "Shown on team members that are not the leader, in a party of only the team. Works in combat; Shift-drag to move. Same as /hb lead." },
		{ "castAssist", "toggle", "HaploBoxAssist and HaploBoxHelp cast for the leader", who = "followers",
			help = "Your own macros: /click HaploBoxAssist Frostbolt, /click HaploBoxHelp Flash_Heal (_ for spaces). Not yet checked in the game." },
		{ "showRelayedErrors", "toggle", "Show followers' cast errors in chat", who = "leader" },
		{ "bagFullAlert", "toggle", "Message when a character's bags are full", who = "leader" },
		{ "testAlert", "action", "Test leader alert", run = function() SlashCmdList.HAPLOBOX("test alert") end },
	} },
	{ id = "nodes", title = "Gathering", items = {
		{ "nodeShare", "toggle", "Send herbs and ore I hover on the minimap or gather to the leader", who = "followers",
			help = "Only what you yourself hover or gather. Not yet checked in the game." },
		{ "nodeShow", "toggle", "Show the team's herbs and ore on my minimap", who = "leader" },
		{ "nodeHerbs", "toggle", "Herbs", who = "leader" },
		{ "nodeOre", "toggle", "Ore", who = "leader" },
		{ "nodeExpiry", "cycle", "Markers last", choices = { "5", "10", "20", "30" },
			text = { ["5"] = "5 min", ["10"] = "10 min", ["20"] = "20 min", ["30"] = "30 min" }, who = "leader" },
		{ "clearNodes", "action", "Clear the markers", run = function() HB.ClearNodeMarkers() end },
	} },
	{ id = "group", title = "Group & loot", items = {
		{ "autoAcceptInvite", "toggle", "Accept group invites from the leader", who = "followers" },
		{ "autoFFA", "toggle", "Free-for-all loot for the team only, group loot when someone else joins", who = "leader" },
		{ "autoLeaveWithLeader", "toggle", "Leave the group when the leader leaves", who = "followers" },
		{ "autoRoleCheck", "toggle", "Answer group finder role checks with my team role" },
		{ "autoPartyRole", "toggle", "Set my party role and group finder role from my team role" },
	} },
	{ id = "quests", title = "Quests & travel", items = {
		{ "autoAcceptShared", "toggle", "Accept quests shared by a team member" },
		{ "autoShareQuests", "cycle", "Share quests I accept", choices = SHARE_MODES, text = SHARE_MODE_TEXT },
		{ "askAbandonQuests", "toggle", "When I abandon a quest, ask to abandon it on the followers", who = "leader" },
		{ "followAbandonQuests", "toggle", "Abandon a quest when the leader asks", who = "followers" },
		{ "shareErrorAlert", "toggle", "Sound and message when a quest share fails" },
		{ "followFlights", "toggle", "Fly to the leader's flight destination when my flight map opens", who = "followers" },
		{ "hideQuestTracker", "toggle", "Hide Blizzard's quest tracker" },
	} },
	{ id = "whispers", title = "Whispers", items = {
		{ "forwardWhispers", "toggle", "Forward whispers from outside the team to the leader", who = "followers" },
		{ "relayReplies", "toggle", "Pass the leader's replies on (leader whispers this character, or /hb r)", who = "followers" },
	} },
	{ id = "sounds", title = "Sounds", sounds = {
		{ "followOn", "Follow started (this character)" },
		{ "followOff", "Follow stopped (this character)" },
		{ "leaderAlert", "A follower stopped following", who = "leader" },
		{ "shareError", "Quest share failed" },
		{ "inviteAccept", "Invite accepted" },
		{ "whisperIn", "Forwarded whisper", who = "leader" },
		{ "bagsFull", "A character's bags are full", who = "leader" },
		{ "mountOn", "Passenger mount: on" },
		{ "mountOff", "Passenger mount: off" },
	} },
	{ id = "advanced", title = "Advanced", items = {
		{ "teamHeader", "toggle", "Secure team rows in a party (turn off if the team frame misbehaves)",
			help = "On: the game keeps each row on its character, also in combat. Off: the older rows, which dim and show ? when the group changes in combat." },
		{ "debug", "toggle", "Debug messages in chat (ignored addon messages, failed sends)" },
	} },
}
HB.SETTINGS = SECTIONS

-- the quick settings popup: display settings of the team frame on this account
local QUICK = {
	"teamView", "teamFrame", "teamLocked", "partyScale", "teamClassColors", "teamShowXP", "teamShowGold", "teamShowBags",
	"teamShowBuffs", "teamHealPrediction", "teamCastBars", "teamManaRule", "teamShowHots",
	"teamBuffOverview", "teamDebuffOverview",
}

local function findItem(key)
	for _, sec in ipairs(SECTIONS) do
		for _, it in ipairs(sec.items or {}) do if it[1] == key then return it, sec end end
	end
end
HB.FindSetting = findItem

local function nextChoice(it)
	local cur = HB.db[it[1]]
	for i, m in ipairs(it.choices) do
		if m == cur then return it.choices[i % #it.choices + 1] end
	end
	return it.choices[1]
end

local function whoText(who) return who and WHO[who] ~= "" and (" |cff888888(" .. WHO[who] .. ")|r") or "" end

local function themed(f, color)
	local t = f:CreateTexture(nil, "BACKGROUND")
	t:SetAllPoints()
	t:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
	return t
end

local function tooltip(owner, title, text)
	owner:SetScript("OnEnter", function(self)
		if not GameTooltip then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(title)
		if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
		GameTooltip:Show()
	end)
	owner:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

-- Builds one setting control inside parent at y. Returns the new y and a refresher.
local function control(parent, it, y, width)
	local key, kind, label = it[1], it[2], it[3]
	if kind == "toggle" then
		local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
		cb:SetPoint("TOPLEFT", 4, y)
		cb:SetSize(24, 24)
		local text = (type(cb.Text) == "table" and cb.Text) or (type(cb.text) == "table" and cb.text)
			or cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		text:ClearAllPoints()
		text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
		text:SetWidth(width - 34)
		text:SetJustifyH("LEFT")
		text:SetText(label .. whoText(it.who))
		cb:SetScript("OnClick", function(self) HB.SetOption(key, self:GetChecked() and true or false) end)
		cb.key = key
		return y - 26, function() cb:SetChecked(HB.db[key] and true or false) end, cb
	elseif kind == "cycle" then
		local l = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		l:SetPoint("TOPLEFT", 8, y - 5)
		l:SetText(label .. ":")
		local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
		b:SetSize(96, 22)
		b:SetPoint("LEFT", l, "RIGHT", 10, 0)
		b:SetScript("OnClick", function() HB.SetOption(key, nextChoice(it)) end)
		b.key = key
		tooltip(b, label, it.help or "Click to change.")
		return y - 28, function() b:SetText(it.text[HB.db[key]] or tostring(HB.db[key])) end, b
	elseif kind == "scale" then
		local l = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		l:SetPoint("TOPLEFT", 8, y - 5)
		l:SetText(label .. ":")
		local minus = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
		minus:SetSize(24, 22)
		minus:SetPoint("LEFT", l, "RIGHT", 10, 0)
		minus:SetText("-")
		local value = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		value:SetPoint("LEFT", minus, "RIGHT", 6, 0)
		value:SetWidth(40)
		local plus = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
		plus:SetSize(24, 22)
		plus:SetPoint("LEFT", value, "RIGHT", 6, 0)
		plus:SetText("+")
		minus:SetScript("OnClick", function() HB.SetOption(key, (HB.db[key] or 1) - 0.1) end)
		plus:SetScript("OnClick", function() HB.SetOption(key, (HB.db[key] or 1) + 0.1) end)
		minus.key, plus.key = key, key
		return y - 28, function() value:SetText(string.format("%.0f%%", (HB.db[key] or 1) * 100)) end, plus, minus
	elseif kind == "text" then
		local l = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		l:SetPoint("TOPLEFT", 8, y - 4)
		l:SetText(label .. ":")
		local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
		eb:SetSize(width - 30, 20)
		eb:SetPoint("TOPLEFT", 14, y - 20)
		eb:SetAutoFocus(false)
		local function save(self)
			HB.SetOption(key, self:GetText() or "")
			self:ClearFocus()
		end
		eb:SetScript("OnEnterPressed", save)
		eb:SetScript("OnEditFocusLost", save)
		eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
		eb.key = key
		local hint = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
		hint:SetPoint("TOPLEFT", 8, y - 42)
		hint:SetWidth(width - 16)
		hint:SetJustifyH("LEFT")
		hint:SetText(it.help or "")
		return y - 70, function()
			if eb.HasFocus and eb:HasFocus() then return end
			eb:SetText(HB.db[key] or "")
			eb:SetCursorPosition(0)
		end, eb
	elseif kind == "action" then
		local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
		b:SetSize(math.min(width - 16, 190), 22)
		b:SetPoint("TOPLEFT", 8, y - 2)
		b:SetText(label)
		b:SetScript("OnClick", it.run)
		b.key = key
		return y - 30, nil, b
	end
	return y
end

-- ---------------------------------------------------------------- full settings
local views = {}  -- open views: { refresh = fn }
local controls = {}  -- key -> list of controls, for tests and focus
HB.SettingControls = controls

function HB.RefreshSettingsViews()
	for _, v in ipairs(views) do if v.shown() then v.refresh() end end
end

-- open views show whether team frame changes wait for the end of combat
local combatWatch = CreateFrame("Frame")
combatWatch:SetScript("OnEvent", function() HB.RefreshSettingsViews() end)
pcall(combatWatch.RegisterEvent, combatWatch, "PLAYER_REGEN_DISABLED")
pcall(combatWatch.RegisterEvent, combatWatch, "PLAYER_REGEN_ENABLED")

local function note(parent, y, width, text)
	local n = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	n:SetPoint("TOPLEFT", 8, y)
	n:SetWidth(width - 16)
	n:SetJustifyH("LEFT")
	n:SetText(text)
	return y - 30
end

local function teamSection(pane, width, refreshers)
	local y = -4
	local roleLabel = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	roleLabel:SetPoint("TOPLEFT", 8, y - 5)
	roleLabel:SetText("My role:")
	local roleBtns, prev = {}, nil
	for _, r in ipairs(HB.ROLES) do
		local b = CreateFrame("Button", nil, pane, "UIPanelButtonTemplate")
		b:SetSize(70, 22)
		if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("LEFT", roleLabel, "RIGHT", 10, 0) end
		b:SetScript("OnClick", function() HB.SetMyRole(r) HB.RefreshSettingsViews() end)
		tooltip(b, "Role: " .. r, "Saved for this character and sent to the group.")
		roleBtns[r] = b
		prev = b
	end
	refreshers[#refreshers + 1] = function()
		local mine = HB.MyRole()
		for r, b in pairs(roleBtns) do b:SetText(r == mine and ("|cff33ff33" .. r:upper() .. "|r") or r) end
	end
	y = y - 32
	local leaderLabel = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	leaderLabel:SetPoint("TOPLEFT", 8, y)
	leaderLabel:SetWidth(width - 16)
	leaderLabel:SetJustifyH("LEFT")
	local teamLabel = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	teamLabel:SetPoint("TOPLEFT", 8, y - 18)
	teamLabel:SetWidth(width - 16)
	teamLabel:SetJustifyH("LEFT")
	refreshers[#refreshers + 1] = function()
		local l = HB.Leader()
		leaderLabel:SetText("Leader: " .. (l and ("|cffffff00" .. l .. "|r" .. (HB.IAmLeader() and " (this character)" or "")) or "|cffff5555none|r"))
		teamLabel:SetText("Team: " .. HB.TeamSummary())
	end
	y = y - 52
	-- a team action, not a setting: kept apart and coloured
	local head = pane:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	head:SetPoint("TOPLEFT", 8, y)
	head:SetText("Team action")
	y = y - 20
	local leaderBtn = CreateFrame("Button", nil, pane, "UIPanelButtonTemplate")
	leaderBtn:SetSize(math.min(width - 16, 220), 22)
	leaderBtn:SetPoint("TOPLEFT", 8, y)
	leaderBtn:SetText("Make this character the leader")
	leaderBtn:SetScript("OnClick", function() HB.MakeMeLeader() HB.RefreshSettingsViews() end)
	tooltip(leaderBtn, "Make this character the leader",
		"Sends to the group: in a party, the group becomes the team and every character gets it. New members are confirmed in a popup first.")
	y = y - 28
	return note(pane, y, width, "Each follower accepts a new leader once in a popup (or /hb accept). The healer is the character with the healer role.")
end

local function soundSection(pane, width, sec, refreshers)
	local y = note(pane, -4, width, "A SOUNDKIT name (RAID_WARNING), a sound kit id, file:<id> or a file path. Empty = off.")
	for _, s in ipairs(sec.sounds) do
		local key, label = s[1], s[2]
		local l = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		l:SetPoint("TOPLEFT", 8, y - 4)
		l:SetWidth(math.max(120, width - 250))
		l:SetJustifyH("LEFT")
		l:SetWordWrap(false)
		l:SetText(label .. whoText(s.who))
		local test = CreateFrame("Button", nil, pane, "UIPanelButtonTemplate")
		test:SetSize(44, 20)
		test:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -8, y)
		test:SetText("Test")
		test:SetScript("OnClick", function() HB.lastSound = {} HB.PlaySound(key) end)
		local eb = CreateFrame("EditBox", nil, pane, "InputBoxTemplate")
		eb:SetSize(170, 20)
		eb:SetPoint("RIGHT", test, "LEFT", -8, 0)
		eb:SetAutoFocus(false)
		local function save(self)
			HB.SetSound(key, self:GetText())
			self:ClearFocus()
		end
		eb:SetScript("OnEnterPressed", save)
		eb:SetScript("OnEditFocusLost", save)
		eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
		refreshers[#refreshers + 1] = function()
			if eb:HasFocus() then return end
			local v = HB.db.sounds[key]
			eb:SetText(v and tostring(v) or "")
			eb:SetCursorPosition(0)
		end
		y = y - 26
	end
	return y
end

function HB.CreateOptions()
	local T = HB.THEME or {}
	local outer = CreateFrame("Frame", "HaploBoxOptions")
	outer.name = "HaploBox"
	themed(outer, T.footer or { 0.10, 0.11, 0.13, 0.95 })

	local title = outer:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -14)
	title:SetText("HaploBox")
	if T.gold then title:SetTextColor(T.gold[1], T.gold[2], T.gold[3]) end
	local sub = outer:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
	sub:SetPoint("RIGHT", outer, "RIGHT", -16, 0)
	sub:SetJustifyH("LEFT")
	sub:SetText("Saved for this WoW account, not sent to the team. Grey notes say where a setting does something.")
	local status = outer:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	status:SetPoint("TOPRIGHT", -16, -18)

	local NAV_W = 130
	local nav = CreateFrame("Frame", nil, outer)
	nav:SetPoint("TOPLEFT", 10, -54)
	nav:SetPoint("BOTTOMLEFT", 10, 10)
	nav:SetWidth(NAV_W)
	themed(nav, T.rowBg or { 0.16, 0.17, 0.20, 0.92 })

	local scroll = CreateFrame("ScrollFrame", nil, outer, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", nav, "TOPRIGHT", 10, 0)
	scroll:SetPoint("BOTTOMRIGHT", -30, 10)

	local panes, navButtons, refreshers, current = {}, {}, {}, nil
	local function paneWidth() return math.max(300, (scroll:GetWidth() or 0) > 0 and scroll:GetWidth() or 440) end

	local function showSection(id)
		for _, sec in ipairs(SECTIONS) do
			local on = sec.id == id
			panes[sec.id]:SetShown(on)
			local b = navButtons[sec.id]
			b.bg:SetColorTexture(on and 0.36 or 0, on and 0.30 or 0, on and 0.10 or 0, on and 0.95 or 0)
			if on then
				scroll:SetScrollChild(panes[sec.id])
				panes[sec.id]:SetWidth(paneWidth())
			end
		end
		current = id
		if scroll.SetVerticalScroll then scroll:SetVerticalScroll(0) end
	end

	local width = 400  -- fits the narrowest settings canvas (Classic) next to the section list
	for i, sec in ipairs(SECTIONS) do
		local b = CreateFrame("Button", nil, nav)
		b:SetSize(NAV_W - 8, 22)
		b:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 24)
		b.bg = b:CreateTexture(nil, "BACKGROUND")
		b.bg:SetAllPoints()
		b.bg:SetColorTexture(0, 0, 0, 0)
		local fs = b:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		fs:SetPoint("LEFT", 8, 0)
		fs:SetPoint("RIGHT", -4, 0)
		fs:SetJustifyH("LEFT")
		fs:SetText(sec.title)
		b:SetScript("OnClick", function() showSection(sec.id) end)
		navButtons[sec.id] = b

		local pane = CreateFrame("Frame", nil, scroll)
		pane:SetSize(width, 400)
		pane:Hide()
		local head = pane:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
		head:SetPoint("TOPLEFT", 8, -4)
		head:SetText(sec.title)
		if T.name then head:SetTextColor(T.name[1], T.name[2], T.name[3]) end
		local body = CreateFrame("Frame", nil, pane)
		body:SetPoint("TOPLEFT", 0, -30)
		body:SetPoint("RIGHT", pane, "RIGHT")
		body:SetHeight(1)
		local y
		if sec.team then
			y = teamSection(body, width, refreshers)
		elseif sec.sounds then
			y = soundSection(body, width, sec, refreshers)
		else
			y = -4
			for _, it in ipairs(sec.items) do
				local r, c1, c2
				y, r, c1, c2 = control(body, it, y, width)
				if r then refreshers[#refreshers + 1] = r end
				controls[it[1]] = controls[it[1]] or {}
				if c1 then table.insert(controls[it[1]], c1) end
				if c2 then table.insert(controls[it[1]], c2) end
			end
		end
		if sec.id == "frame" then
			y = note(body, y - 4, width, "Team frame changes made in combat apply when combat ends. /hb quick opens these on the frame.")
		end
		pane:SetHeight(-y + 40)
		panes[sec.id] = pane
	end

	local function refresh()
		status:SetText(HB.SettingsDeferred() and "|cffffaa00In combat: team frame changes wait|r" or "")
		for _, r in ipairs(refreshers) do r() end
	end
	views[#views + 1] = { shown = function() return outer:IsShown() end, refresh = refresh }
	outer:SetScript("OnShow", function()
		showSection(current or "team")
		refresh()
	end)
	HB.OptionsSelect = function(id) if panes[id] then showSection(id) refresh() end end

	if Settings and Settings.RegisterCanvasLayoutCategory then
		local category = Settings.RegisterCanvasLayoutCategory(outer, outer.name)
		Settings.RegisterAddOnCategory(category)
		HB.OpenOptions = function(id)
			if id and panes[id] then current = id end
			Settings.OpenToCategory(category:GetID())
			if id then HB.OptionsSelect(id) end
		end
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(outer)
		HB.OpenOptions = function(id)
			if id and panes[id] then current = id end
			InterfaceOptionsFrame_OpenToCategory(outer)
			InterfaceOptionsFrame_OpenToCategory(outer)
			if id then HB.OptionsSelect(id) end
		end
	end
end

-- ---------------------------------------------------------------- quick settings
local quick

local function createQuick()
	local T = HB.THEME or {}
	quick = CreateFrame("Frame", "HaploBoxQuickSettings", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	quick:SetSize(260, 10)
	quick:SetFrameStrata("DIALOG")
	quick:SetClampedToScreen(true)
	quick:EnableMouse(true)
	quick:Hide()
	themed(quick, T.footer or { 0.10, 0.11, 0.13, 0.97 })
	local edge = quick:CreateTexture(nil, "BORDER")
	edge:SetPoint("TOPLEFT") edge:SetPoint("TOPRIGHT") edge:SetHeight(1)
	local g = T.gold or { 1, 0.82, 0.3 }
	edge:SetColorTexture(g[1], g[2], g[3], 1)
	local title = quick:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	title:SetPoint("TOPLEFT", 10, -8)
	title:SetText("Team frame")
	title:SetTextColor(g[1], g[2], g[3])
	local scope = quick:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	scope:SetPoint("TOPRIGHT", -10, -10)
	scope:SetText("this account only")
	local close = CreateFrame("Button", nil, quick, "UIPanelCloseButton")
	close:SetSize(20, 20)
	close:SetPoint("TOPRIGHT", 2, 2)
	close:SetScript("OnClick", function() quick:Hide() end)

	local refreshers = {}
	quick.controls = {}
	local y = -28
	for _, key in ipairs(QUICK) do
		local it = findItem(key)
		local r, c1, c2
		y, r, c1, c2 = control(quick, it, y, 260)
		if r then refreshers[#refreshers + 1] = r end
		quick.controls[key] = c1
		if c2 then quick.controls[key .. "-"] = c2 end
	end
	quick.deferred = quick:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	quick.deferred:SetPoint("TOPLEFT", 10, y - 2)
	quick.deferred:SetText("")
	y = y - 18
	local full = CreateFrame("Button", nil, quick, "UIPanelButtonTemplate")
	full:SetSize(240, 22)
	full:SetPoint("TOPLEFT", 10, y)
	full:SetText("Open full settings")
	full:SetScript("OnClick", function()
		quick:Hide()
		if HB.OpenOptions then HB.OpenOptions("frame") end
	end)
	quick.full = full
	quick:SetHeight(-y + 32)

	quick.refresh = function()
		quick.deferred:SetText(HB.SettingsDeferred() and "|cffffaa00In combat: changes apply after combat|r" or "")
		for _, r in ipairs(refreshers) do r() end
	end
	views[#views + 1] = { shown = function() return quick:IsShown() end, refresh = quick.refresh }

	if UISpecialFrames then table.insert(UISpecialFrames, "HaploBoxQuickSettings") end  -- Escape closes it
	-- A click anywhere outside closes it. Clicks on its own controls keep it open.
	quick:SetScript("OnEvent", function(self, event)
		if event == "GLOBAL_MOUSE_DOWN" and self:IsShown() and not self:IsMouseOver()
			and not (self.anchor and self.anchor.IsMouseOver and self.anchor:IsMouseOver()) then
			self:Hide()
		end
	end)
	quick:SetScript("OnShow", function(self)
		pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_DOWN")
		self.refresh()
	end)
	quick:SetScript("OnHide", function(self) pcall(self.UnregisterEvent, self, "GLOBAL_MOUSE_DOWN") end)
end

-- Opens the quick settings next to anchor (the gear, the TEAM line), or in the middle
-- of the screen. Pressing the same place again closes it.
function HB.ToggleQuickSettings(anchor)
	if not quick then createQuick() end
	if quick:IsShown() and (anchor == nil or quick.anchor == anchor) then quick:Hide() return end
	quick.anchor = anchor
	quick:ClearAllPoints()
	if anchor then
		quick:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 6, 0)
	else
		quick:SetPoint("CENTER", UIParent, "CENTER")
	end
	quick:Show()
	quick.refresh()
end

function HB.QuickSettingsFrame() return quick end
