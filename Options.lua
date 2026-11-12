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
}

local SOUNDS = {
	{ "followOn", "Follow started (this toon)" },
	{ "followOff", "Follow stopped (this toon)" },
	{ "leaderAlert", "Leader: a follower stopped following" },
	{ "shareError", "Quest share failed" },
	{ "inviteAccept", "Invite accepted" },
	{ "mountOn", "Passenger mount: on" },
	{ "mountOff", "Passenger mount: off" },
}

local SHARE_MODES = { "leader", "all", "off" }
local FRAME_MODES = { "auto", "show", "hide" }

function HB.CreateOptions()
	local panel = CreateFrame("Frame")
	panel.name = "HaploBox"

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("HaploBox")

	local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	sub:SetText("Sound values: a SOUNDKIT name (RAID_WARNING), a sound kit id, file:<id>, or a file path. Empty = off.")

	local y = -60
	local refreshers = {}

	for _, t in ipairs(TOGGLES) do
		local key, label = t[1], t[2]
		local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
		cb:SetPoint("TOPLEFT", 16, y)
		local text = cb.Text or cb.text or cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		if not (cb.Text or cb.text) then text:SetPoint("LEFT", cb, "RIGHT", 2, 0) end
		text:SetText(label)
		cb:SetScript("OnClick", function(self) HB.db[key] = self:GetChecked() and true or false end)
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
	frameHint:SetText("auto = leader only. Shift-drag moves it.")
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

	panel:SetScript("OnShow", function() for _, r in ipairs(refreshers) do r() end end)

	if Settings and Settings.RegisterCanvasLayoutCategory then
		local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
		Settings.RegisterAddOnCategory(category)
		HB.OpenOptions = function() Settings.OpenToCategory(category:GetID()) end
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(panel)
		HB.OpenOptions = function()
			InterfaceOptionsFrame_OpenToCategory(panel)
			InterfaceOptionsFrame_OpenToCategory(panel)
		end
	end
end
