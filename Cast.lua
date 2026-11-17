-- Assist-or-cast spell buttons (#8). Not yet checked in the game: do not rely on it.
--
-- The player registers spells in fixed slots (/hb cast add harm|help <spell>) and puts
-- "/click HaploBoxCast<n>" in a macro of their own; HaploBox never edits macros and
-- never presses a button. Each button's text is set out of combat:
--   help, active:   /cast [mod:shift,@player][@mouseover,help,nodead][@<leader>,help,nodead] <spell>
--   help, inactive: /cast [mod:shift,@player][@mouseover,help,nodead][] <spell>
--   harm, active:   /cast [@<leader's party token>target,harm,nodead] <spell>
--   harm, inactive: /cast <spell>
-- Active means: this toon is a follower in a party of only the accepted team, the
-- leader is in it, and the player turned it on since logging in (/hb cast on).
--
-- Harm uses a party token, which can move to someone else in combat. So an armed harm
-- button is disarmed (its text emptied: pressing it does nothing) by secure code the
-- moment the group changes in any way, also in combat:
--   * a group header that lists only the leader runs DISARM on every roster or name
--     update (refreshUnitChange), and when the leader's row loses its unit;
--   * a state driver runs DISARM whenever the group is no longer a party.
-- HaploBox arms it again only out of combat, after checking the group again.
local HB = HaploBox

local MAX = 12
local buttons = {}
local assistOn = false   -- never saved: off after every login
local pending = false
local warned = false

for i = 1, MAX do
	local b = CreateFrame("Button", "HaploBoxCast" .. i, UIParent, "SecureActionButtonTemplate")
	b:RegisterForClicks("AnyUp")
	b:Hide()  -- reached with /click from the player's macro
	b:SetAttribute("type", "macro")
	b:SetAttribute("macrotext", "")
	buttons[i] = b
end

local DISARM = [[
for i = 1, 12 do
	local b = self:GetFrameRef("cast" .. i)
	if b and b:GetAttribute("hb-armed") then
		b:SetAttribute("macrotext", "")
		b:SetAttribute("hb-armed", nil)
	end
end
]]
HB.CAST_DISARM = DISARM

local function refAll(frame)
	for i, b in ipairs(buttons) do SecureHandlerSetFrameRef(frame, "cast" .. i, b) end
end

-- ---------------------------------------------------------------- secure disarm
local leaderHeader, leaderChild, ctx
local harmReady = nil  -- nil: not tried; false: not available on this client

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
	refAll(c)
	c:SetAttribute("refreshUnitChange", DISARM)
	c:SetAttribute("_onattributechanged", "if name == 'unit' then " .. DISARM .. " end")
	ok, ctx = pcall(CreateFrame, "Frame", "HaploBoxCastContext", UIParent, "SecureHandlerStateTemplate")
	if not ok or not ctx then h:Hide() return false end
	refAll(ctx)
	ctx:SetAttribute("_onstate-hbctx", "if newstate ~= 'party' then " .. DISARM .. " end")
	RegisterStateDriver(ctx, "hbctx", "[group:raid] raid; [group:party] party; solo")
	leaderHeader, leaderChild = h, c
	harmReady = true
	return true
end

-- ---------------------------------------------------------------- spells
local function validSpell(s)
	return type(s) == "string" and #s > 0 and #s <= 60 and not s:find("[\r\n|;%[%]]")
end

local function spells()
	if type(HB.db.castSpells) ~= "table" then HB.db.castSpells = {} end
	local t = HB.db.castSpells
	for i = 1, MAX do
		local e = t[i]
		if e ~= nil and not (type(e) == "table" and validSpell(e.spell) and (e.kind == "harm" or e.kind == "help")) then
			t[i] = nil
		end
	end
	for k in pairs(t) do
		if type(k) ~= "number" or k < 1 or k > MAX or k % 1 ~= 0 then t[k] = nil end
	end
	return t
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
	if status == "mixed" then return nil, nil, "someone outside the team is in the group" end
	if status ~= "team" then return nil, nil, "group not confirmed yet" end
	if HB.IAmLeader() then return nil, nil, "you are the leader" end
	local leader = HB.Leader()
	local token = leader and partyToken(leader)
	if not token then return nil, nil, "the leader is not in the group" end
	return leader, token
end

local function headerName(n) return HB.HeaderName(n) end

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
	if pending then
		text = "|cffffaa00assisted casting: " .. (assistOn and "on" or "off") .. ", buttons update after combat|r"
	elseif assistOn then
		text = harmReady == false and "|cffffaa00assisted casting: heals only (damage not available here)|r"
			or "|cff66ff66assisted casting: on|r"
	end
	note:SetText(text or "")
	note:SetShown(text and true or false)
end
HB.CastStateText = function() return note and note:IsShown() and note:GetText() or nil end

function HB.UpdateCastButtons()
	-- the intent is checked at once, also in combat: once the group stops being the
	-- team, the player has to turn it on again
	local leader, token, why = context()
	if assistOn and not leader then
		assistOn = false
		HB.print("assisted casting turned off: " .. why .. " (/hb cast on to turn it on again)")
	end
	if InCombatLockdown() then
		pending = true
		showState()
		return
	end
	pending = false
	local active = assistOn and leader
	local harm = active and setupSecure()
	if active and not harm and not warned then
		warned = true
		HB.print("assisted damage spells are not available on this client; they do nothing while assisted casting is on")
	end
	-- name list first: the header's own update disarms, then the texts are set below
	if leaderHeader then leaderHeader:SetAttribute("nameList", harm and headerName(leader) or "") end
	local t = spells()
	for i, b in ipairs(buttons) do
		local e, text, armed = t[i], "", nil
		if e and e.kind == "help" then
			text = active and ("/cast [mod:shift,@player][@mouseover,help,nodead][@" .. leader .. ",help,nodead] " .. e.spell)
				or ("/cast [mod:shift,@player][@mouseover,help,nodead][] " .. e.spell)
		elseif e then
			if harm then
				text, armed = "/cast [@" .. token .. "target,harm,nodead] " .. e.spell, true
			elseif active then
				text = ""  -- assisted, but no secure disarm here: do nothing rather than cast at your own target
			else
				text = "/cast " .. e.spell
			end
		end
		b:SetAttribute("macrotext", text)
		b:SetAttribute("hb-armed", armed)
	end
	showState()
end

function HB.CastPending() return pending end
function HB.AssistCastOn() return assistOn end

function HB.SetAssistCast(on)
	if on then
		local leader, _, why = context()
		if not leader then HB.print("assisted casting stays off: " .. why) return end
		assistOn = true
		HB.print("assisted casting on until you log out or the group changes. Not yet checked in the game.")
	else
		assistOn = false
		HB.print("assisted casting off")
	end
	HB.UpdateCastButtons()
	if pending then HB.print("|cffffaa00takes effect when combat ends|r") end
end

function HB.CastCommand(rest)
	local cmd, arg = (rest or ""):match("^(%S*)%s*(.-)%s*$")
	cmd = cmd:lower()
	local t = spells()
	if cmd == "on" or cmd == "off" then
		HB.SetAssistCast(cmd == "on")
	elseif (cmd == "add" or cmd == "remove") and InCombatLockdown() then
		HB.print("change the spell slots after combat")
	elseif cmd == "add" then
		local kind, spell = arg:match("^(%a+)%s+(.+)$")
		kind = kind and kind:lower()
		if not (kind == "harm" or kind == "help") or not validSpell(spell) then
			HB.print("usage: /hb cast add harm|help <spell name>")
			return
		end
		for i = 1, MAX do
			if not t[i] then
				t[i] = { kind = kind, spell = spell }
				HB.UpdateCastButtons()
				HB.print(spell .. " is in slot " .. i .. ": make a macro with |cffffff00/click HaploBoxCast" .. i .. "|r")
				return
			end
		end
		HB.print("all " .. MAX .. " slots are used; /hb cast remove <slot> first")
	elseif cmd == "remove" then
		local i = tonumber(arg)
		if not (i and t[i]) then HB.print("no spell in that slot") return end
		t[i] = nil  -- the other slots keep their numbers, so other macros stay right
		HB.UpdateCastButtons()
		HB.print("slot " .. i .. " is empty now")
	else
		local any = false
		for i = 1, MAX do
			local e = t[i]
			if e then
				any = true
				HB.print(i .. ": " .. e.kind .. " " .. e.spell .. "  (/click HaploBoxCast" .. i .. ")")
			end
		end
		if not any then HB.print("no spells yet: /hb cast add harm Frostbolt") end
		local _, _, why = context()
		HB.print("assisted casting: " .. (assistOn and "on" or "off") .. (why and (" (" .. why .. ")") or "")
			.. (pending and ", |cffffaa00waits for the end of combat|r" or ""))
	end
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		assistOn = false
		C_Timer.After(3, HB.UpdateCastButtons)
	else
		HB.UpdateCastButtons()  -- at once: an outsider passing through in combat still turns it off
		C_Timer.After(0.2, HB.UpdateCastButtons)
	end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED", "UNIT_NAME_UPDATE", "PARTY_LEADER_CHANGED" }) do
	pcall(ev.RegisterEvent, ev, e)
end
