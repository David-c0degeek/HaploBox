-- HaploBox options panel (Esc > Options > AddOns > HaploBox, or /hb options).
local HB = HaploBox

local TOGGLES = {
	{ "autoAcceptInvite", "Accept group invites from the leader" },
	{ "autoAcceptShared", "Accept quests shared by a team member" },
	{ "shareErrorAlert", "Sound and message when a quest share fails" },
	{ "relayErrors", "Send my cast errors (range, line of sight, mana) to the leader" },
	{ "showRelayedErrors", "Leader: show followers' cast errors in chat" },
	{ "alertOnFollowStart", "Leader: also show a message when a follower starts following" },
	{ "autoFFA", "Leader: set free-for-all loot when the group changes" },
	{ "autoRoleCheck", "Answer group finder role checks with my team role" },
	{ "autoLeaveWithLeader", "Leave the group when the leader leaves" },
	{ "followFlights", "Fly to the leader's flight destination when my flight map opens" },
	{ "teamLocked", "Team frame: lock in place (unlock to move and resize)" },
	{ "teamClassColors", "Team frame: class colours" },
	{ "teamShowXP", "Team frame: level and XP bar" },
	{ "teamShowGold", "Team frame: gold per toon and team total" },
	{ "teamShowBags", "Team frame: free bag slots per toon and team total" },
	{ "teamShowBuffs", "Team frame: group buffs with timers" },
	{ "autoPartyRole", "Set my party role and group finder role from my team role" },
	{ "hideQuestTracker", "Hide Blizzard's quest tracker" },
	{ "bagFullAlert", "Leader: message when a toon's bags are full" },
	{ "forwardWhispers", "Forward whispers from outside the team to the leader" },
	{ "relayReplies", "Pass the leader's replies on (leader whispers this toon, or /hb r)" },
}

local SOUNDS = {
	{ "followOn", "Follow started (this toon)" },
	{ "followOff", "Follow stopped (this toon)" },
	{ "leaderAlert", "Leader: a follower stopped following" },
	{ "shareError", "Quest share failed" },
	{ "inviteAccept", "Invite accepted" },
	{ "whisperIn", "Leader: forwarded whisper" },
	{ "bagsFull", "Leader: a toon's bags are full" },
	{ "mountOn", "Passenger mount: on" },
	{ "mountOff", "Passenger mount: off" },
}

local SHARE_MODES = { "leader", "all", "off" }
local FRAME_MODES = { "auto", "show", "hide" }

function HB.CreateOptions()
	local outer = CreateFrame("Frame")
	outer.name = "HaploBox"
	local scroll = CreateFrame("ScrollFrame", nil, outer, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 0, -4)
	scroll:SetPoint("BOTTOMRIGHT", -28, 4)
	local panel = CreateFrame("Frame", nil, scroll)
	panel:SetSize(620, 1000)
	scroll:SetScrollChild(panel)

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("HaploBox")

	local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	sub:SetText("Sound values: a SOUNDKIT name (RAID_WARNING), a sound kit id, file:<id>, or a file path. Empty = off.")

	local y = -60
	local refreshers = {}

	-- this toon: role and leader, no typing needed
	local head = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	head:SetPoint("TOPLEFT", 16, y)
	head:SetText("This toon")
	y = y - 24
	local roleLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	roleLabel:SetPoint("TOPLEFT", 20, y - 4)
	roleLabel:SetText("My role:")
	local roleBtns = {}
	local prev
	for _, r in ipairs({ "tank", "healer", "dps" }) do
		local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
		b:SetSize(80, 22)
		if prev then b:SetPoint("LEFT", prev, "RIGHT", 6, 0) else b:SetPoint("LEFT", roleLabel, "RIGHT", 12, 0) end
		b:SetScript("OnClick", function()
			HB.SetMyRole(r)
			for _, f in ipairs(refreshers) do f() end
		end)
		roleBtns[r] = b
		prev = b
	end
	refreshers[#refreshers + 1] = function()
		local mine = HB.MyRole()
		for r, b in pairs(roleBtns) do
			b:SetText(r == mine and ("|cff33ff33" .. r:upper() .. "|r") or r)
		end
	end
	y = y - 30
	local leaderLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	leaderLabel:SetPoint("TOPLEFT", 20, y - 4)
	local leaderBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	leaderBtn:SetSize(170, 22)
	leaderBtn:SetPoint("TOPLEFT", 300, y)
	leaderBtn:SetText("Make this toon the leader")
	leaderBtn:SetScript("OnClick", function()
		HB.MakeMeLeader()
		for _, f in ipairs(refreshers) do f() end
	end)
	refreshers[#refreshers + 1] = function()
		local l = HB.Leader()
		leaderLabel:SetText("Leader: " .. (l and ("|cffffff00" .. l .. "|r" .. (HB.IAmLeader() and " (this toon)" or "")) or "|cffff5555none|r"))
	end
	y = y - 26
	local teamHint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	teamHint:SetPoint("TOPLEFT", 20, y - 2)
	teamHint:SetWidth(560)
	teamHint:SetJustifyH("LEFT")
	teamHint:SetText("In a party, the leader button also makes the group the team and sends it to every toon. The healer is the toon with the healer role.")
	y = y - 30

	for _, t in ipairs(TOGGLES) do
		local key, label = t[1], t[2]
		local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
		cb:SetPoint("TOPLEFT", 16, y)
		local text = cb.Text or cb.text or cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		if not (cb.Text or cb.text) then text:SetPoint("LEFT", cb, "RIGHT", 2, 0) end
		text:SetText(label)
		cb:SetScript("OnClick", function(self)
			HB.db[key] = self:GetChecked() and true or false
			if HB.LayoutPartyFrame then HB.LayoutPartyFrame() end
			if key == "hideQuestTracker" then HB.ApplyQuestTracker() end
		end)
		refreshers[#refreshers + 1] = function() cb:SetChecked(HB.db[key]) end
		y = y - 26
	end

	-- quest sharing mode
	local shareLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	shareLabel:SetPoint("TOPLEFT", 20, y - 6)
	local shareBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	shareBtn:SetSize(90, 22)
	shareBtn:SetPoint("LEFT", shareLabel, "RIGHT", 10, 0)
	local function showShare()
		shareLabel:SetText("Share quests I accept:")
		shareBtn:SetText(HB.db.autoShareQuests)
	end
	shareBtn:SetScript("OnClick", function()
		local cur = HB.db.autoShareQuests
		for i, m in ipairs(SHARE_MODES) do
			if m == cur then HB.db.autoShareQuests = SHARE_MODES[i % #SHARE_MODES + 1] break end
		end
		showShare()
	end)
	refreshers[#refreshers + 1] = showShare
	y = y - 30

	-- team frame mode
	local frameLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	frameLabel:SetPoint("TOPLEFT", 20, y - 6)
	frameLabel:SetText("Team frame on this toon:")
	local frameBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	frameBtn:SetSize(90, 22)
	frameBtn:SetPoint("LEFT", frameLabel, "RIGHT", 10, 0)
	local function showFrameMode() frameBtn:SetText(HB.db.teamFrame) end
	frameBtn:SetScript("OnClick", function()
		local cur = HB.db.teamFrame
		for i, m in ipairs(FRAME_MODES) do
			if m == cur then HB.db.teamFrame = FRAME_MODES[i % #FRAME_MODES + 1] break end
		end
		showFrameMode()
		if HB.LayoutPartyFrame then HB.LayoutPartyFrame() end
	end)
	local frameHint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	frameHint:SetPoint("LEFT", frameBtn, "RIGHT", 10, 0)
	frameHint:SetText("auto = leader only")
	refreshers[#refreshers + 1] = showFrameMode
	y = y - 40

	for _, s in ipairs(SOUNDS) do
		local key, label = s[1], s[2]
		local l = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		l:SetPoint("TOPLEFT", 20, y - 4)
		l:SetWidth(240)
		l:SetJustifyH("LEFT")
		l:SetText(label)
		local eb = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
		eb:SetSize(220, 20)
		eb:SetPoint("TOPLEFT", 270, y)
		eb:SetAutoFocus(false)
		local function save(self)
			local v = self:GetText()
			if v == "" then v = false elseif tonumber(v) then v = tonumber(v) end
			HB.db.sounds[key] = v
			self:ClearFocus()
		end
		eb:SetScript("OnEnterPressed", save)
		eb:SetScript("OnEditFocusLost", save)
		eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
		local test = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
		test:SetSize(50, 20)
		test:SetPoint("LEFT", eb, "RIGHT", 8, 0)
		test:SetText("Test")
		test:SetScript("OnClick", function()
			HB.lastSound = {}
			HB.PlaySound(key)
		end)
		refreshers[#refreshers + 1] = function()
			local v = HB.db.sounds[key]
			eb:SetText(v and tostring(v) or "")
			eb:SetCursorPosition(0)
		end
		y = y - 26
	end

	local alertBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	alertBtn:SetSize(160, 22)
	alertBtn:SetPoint("TOPLEFT", 16, y - 10)
	alertBtn:SetText("Test leader alert")
	alertBtn:SetScript("OnClick", function() SlashCmdList.HAPLOBOX("test alert") end)

	panel:SetHeight(-y + 50)
	outer:SetScript("OnShow", function() for _, r in ipairs(refreshers) do r() end end)

	if Settings and Settings.RegisterCanvasLayoutCategory then
		local category = Settings.RegisterCanvasLayoutCategory(outer, outer.name)
		Settings.RegisterAddOnCategory(category)
		HB.OpenOptions = function() Settings.OpenToCategory(category:GetID()) end
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(outer)
		HB.OpenOptions = function()
			InterfaceOptionsFrame_OpenToCategory(outer)
			InterfaceOptionsFrame_OpenToCategory(outer)
		end
	end
end
