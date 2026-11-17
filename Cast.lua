-- Assist-or-cast buttons (#8). Not yet checked in the game: do not rely on it.
--
-- Two hidden secure buttons take the spell from the player's own macro:
--   /click HaploBoxAssist Frostbolt        damage
--   /click HaploBoxHelp Flash_Heal         heals, HoTs, buffs ("_" stands for a space)
-- /click passes the second word as the mouse button; a secure pre-click snippet
-- turns it into the macro text, so HaploBox never edits macros, never presses a
-- button and needs no list of spells. Spell names are read as typed (any language);
-- control characters and ; [ ] / | \ are refused, and so are the real mouse button
-- names (a key binding click without a spell does nothing).
--   Assist, active:   /cast [@<leader's party token>target,harm,nodead] <spell>
--   Assist, inactive: /cast <spell>
--   Help, active:     /cast [mod:shift,@player][@<leader>,help,nodead][] <spell>
--   Help, inactive:   /cast [mod:shift,@player][] <spell>
-- No mouseover anywhere (owner decision). Active means: this toon is a follower in a
-- party of only the accepted team, the leader is in it, and the player turned it on
-- (/hb cast on, saved; someone outside the team joining turns it off again).
--
-- Assist uses a party token, which can move to someone else in combat. So once
-- armed, it is disarmed (its prefix and any built text emptied: a click does
-- nothing) by secure code the moment the group changes in any way, also in combat:
--   * a group header that lists only the leader runs DISARM on every roster or name
--     update (refreshUnitChange), and when the leader's row loses its unit;
--   * a state driver runs DISARM whenever the group is no longer a party.
-- HaploBox arms it again only out of combat, after checking the group again.
local HB = HaploBox

local pending = false
local warned = false

local function newButton(name)
	local b = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
	b:RegisterForClicks("AnyUp", "AnyDown")
	b:Hide()  -- reached with /click from the player's macro
	b:SetAttribute("type", "macro")
	-- /click gives no "down" edge: act on the up click whatever ActionButtonUseKeyDown says
	b:SetAttribute("useOnKeyDown", false)
	b:SetAttribute("macrotext", "")
	b:SetAttribute("hb-prefix", "")
	return b
end
local assistBtn = newButton("HaploBoxAssist")
local helpBtn = newButton("HaploBoxHelp")

local DISARM = [[
local b = self:GetFrameRef("assist")
if b and b:GetAttribute("hb-armed") then
	b:SetAttribute("hb-prefix", "")
	b:SetAttribute("macrotext", "")
	b:SetAttribute("hb-armed", nil)
end
]]
HB.CAST_DISARM = DISARM

-- Runs before the button's own click: the clicked "button" is the spell.
local BUILD = [==[
local spell = button
local ok = type(spell) == "string" and strlen(spell) >= 1 and strlen(spell) <= 60
	and not strfind(spell, "[%c;%[%]/|\\]")
	and spell ~= "LeftButton" and spell ~= "RightButton" and spell ~= "MiddleButton"
	and spell ~= "Button4" and spell ~= "Button5"
local prefix = self:GetAttribute("hb-prefix") or ""
if ok and prefix ~= "" then
	self:SetAttribute("macrotext", prefix .. gsub(spell, "_", " "))
else
	self:SetAttribute("macrotext", "")
end
]==]
HB.CAST_BUILD = BUILD

-- ---------------------------------------------------------------- secure parts
local leaderHeader, ctx
local wrapReady = nil  -- the click builder; nil: not tried; false: not on this client
local harmReady = nil  -- the secure disarm for Assist

local function setupWrap()
	if wrapReady ~= nil then return wrapReady end
	wrapReady = false
	if not SecureHandlerWrapScript then return false end
	local ok, w = pcall(CreateFrame, "Frame", "HaploBoxCastWrap", UIParent, "SecureHandlerBaseTemplate")
	if not ok or not w then return false end
	local ok1 = pcall(SecureHandlerWrapScript, assistBtn, "OnClick", w, BUILD)
	local ok2 = pcall(SecureHandlerWrapScript, helpBtn, "OnClick", w, BUILD)
	wrapReady = (ok1 and ok2) and true or false
	return wrapReady
end

local function setupSecure()
	if harmReady ~= nil then return harmReady end
	harmReady = false
	if not (SecureHandlerSetFrameRef and RegisterStateDriver) then return false end
	local ok, h = pcall(CreateFrame, "Frame", "HaploBoxLeaderHeader", UIParent, "SecureGroupHeaderTemplate")
	if not ok or not h then return false end
	for k, v in pairs({
		template = "SecureHandlerAttributeTemplate", templateType = "Frame",
		showParty = true, showPlayer = false, showRaid = false, showSolo = false,
		sortMethod = "NAMELIST", nameList = "", unitsPerColumn = 1, maxColumns = 1,
	}) do h:SetAttribute(k, v) end
	h:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -100, 100)  -- holds no visible rows
	h:SetAttribute("startingIndex", 0)  -- one row even with nobody listed
	h:Show()
	h:SetAttribute("startingIndex", 1)
	local c = h:GetAttribute("child1")
	if not c then h:Hide() return false end
	SecureHandlerSetFrameRef(c, "assist", assistBtn)
	c:SetAttribute("refreshUnitChange", DISARM)
	c:SetAttribute("_onattributechanged", "if name == 'unit' then " .. DISARM .. " end")
	ok, ctx = pcall(CreateFrame, "Frame", "HaploBoxCastContext", UIParent, "SecureHandlerStateTemplate")
	if not ok or not ctx then h:Hide() return false end
	SecureHandlerSetFrameRef(ctx, "assist", assistBtn)
	ctx:SetAttribute("_onstate-hbctx", "if newstate ~= 'party' then " .. DISARM .. " end")
	RegisterStateDriver(ctx, "hbctx", "[group:raid] raid; [group:party] party; solo")
	leaderHeader = h
	harmReady = true
	return true
end

-- ---------------------------------------------------------------- state
local function partyToken(name)
	local key = HB.Norm(name)
	for i = 1, 4 do
		local u = "party" .. i
		if UnitExists(u) and HB.Norm(HB.UnitIdent(u)) == key then return u end
	end
end

-- The leader's name and token when assisted casting applies, else nil and why.
local function context()
	if not IsInGroup() then return nil, nil, "solo" end
	if IsInRaid() then return nil, nil, "in a raid" end
	local status = HB.GroupStatus()
	if status == "mixed" then return nil, nil, "someone outside the team is in the group", "mixed" end
	if status ~= "team" then return nil, nil, "group not confirmed yet" end
	if HB.IAmLeader() then return nil, nil, "you are the leader" end
	local leader = HB.Leader()
	local token = leader and partyToken(leader)
	if not token then return nil, nil, "the leader is not in the group" end
	return leader, token
end


-- A small line under the team frame while assisted casting is on or waiting.
local note
local function showState()
	local frame = HaploBoxPartyFrame
	if not frame then return end
	if not note then
		note = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		note:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 2, -16)
	end
	local text
	local on = HB.db.castAssist
	if pending then
		text = "|cffffaa00assisted casting: " .. (on and "on" or "off") .. ", buttons update after combat|r"
	elseif on then
		text = harmReady == false and "|cffffaa00assisted casting: heals only (damage not available here)|r"
			or "|cff66ff66assisted casting: on|r"
	end
	note:SetText(text or "")
	note:SetShown(text and true or false)
end
HB.CastStateText = function() return note and note:IsShown() and note:GetText() or nil end

function HB.UpdateCastButtons()
	-- someone outside the team joining clears the intent at once, also in combat;
	-- solo, a raid or a group not confirmed yet only make the buttons cast normally
	local leader, token, why, status = context()
	if HB.db.castAssist and status == "mixed" then
		HB.db.castAssist = false
		HB.print("assisted casting turned off: " .. why .. " (/hb cast on to turn it on again)")
	end
	if InCombatLockdown() then
		pending = true
		showState()
		return
	end
	pending = false
	if not setupWrap() then
		if not warned then
			warned = true
			HB.print("HaploBoxAssist and HaploBoxHelp are not available on this client: they do nothing")
		end
		for _, b in ipairs({ assistBtn, helpBtn }) do
			b:SetAttribute("hb-prefix", "")
			b:SetAttribute("macrotext", "")
		end
		showState()
		return
	end
	local active = HB.db.castAssist and leader
	local harm = active and setupSecure()
	-- name list first: the header's own update disarms, then the prefixes are set below
	if leaderHeader then leaderHeader:SetAttribute("nameList", harm and HB.HeaderName(leader) or "") end
	local assist, armed
	if harm then
		assist, armed = "/cast [@" .. token .. "target,harm,nodead] ", true
	elseif active then
		assist = ""  -- assisted, but no secure disarm here: do nothing rather than cast at your own target
	else
		assist = "/cast "
	end
	assistBtn:SetAttribute("hb-prefix", assist)
	assistBtn:SetAttribute("hb-armed", armed)
	assistBtn:SetAttribute("macrotext", "")
	helpBtn:SetAttribute("hb-prefix", active and ("/cast [mod:shift,@player][@" .. leader .. ",help,nodead][] ")
		or "/cast [mod:shift,@player][] ")
	helpBtn:SetAttribute("macrotext", "")
	showState()
end

function HB.CastPending() return pending end
function HB.AssistCastOn() return HB.db.castAssist and true or false end

function HB.SetAssistCast(on)
	if on then
		local leader, _, why = context()
		HB.db.castAssist = true
		HB.print("assisted casting on (kept after logging in). Not yet checked in the game."
			.. (leader and "" or (" Casting normally for now: " .. why .. ".")))
	else
		HB.db.castAssist = false
		HB.print("assisted casting off")
	end
	HB.UpdateCastButtons()
	if pending then HB.print("|cffffaa00takes effect when combat ends|r") end
end

function HB.CastCommand(rest)
	local cmd = ((rest or ""):match("^(%S*)") or ""):lower()
	if cmd == "on" or cmd == "off" then
		HB.SetAssistCast(cmd == "on")
		return
	end
	HB.print("make your own macros, for example:")
	HB.print("  |cffffff00/click HaploBoxAssist Frostbolt|r  damage at the leader's target")
	HB.print("  |cffffff00/click HaploBoxHelp Flash_Heal|r  heal, HoT or buff on the leader (Shift: yourself; _ for spaces)")
	local _, _, why = context()
	HB.print("assisted casting: " .. (HB.db.castAssist and "on" or "off") .. (why and (" (" .. why .. ")") or "")
		.. (pending and ", |cffffaa00waits for the end of combat|r" or "") .. ". /hb cast on|off")
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		C_Timer.After(3, HB.UpdateCastButtons)
	else
		HB.UpdateCastButtons()  -- at once: an outsider passing through in combat still turns it off
		C_Timer.After(0.2, HB.UpdateCastButtons)
	end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED", "UNIT_NAME_UPDATE", "PARTY_LEADER_CHANGED" }) do
	pcall(ev.RegisterEvent, ev, e)
end
