-- Leader handover and role controls (#4).
--
-- Handover: "Take over as leader" (/hb lead, a key binding) makes this toon the
-- HaploBox leader and keeps the team, its order and its roles. It sends
-- H|<epoch>|<rosterHash> to the group. A toon takes it only from an accepted team
-- member who is in its group, only when both have the same team, and only when it
-- is newer than the leader change it has. Two offers with the same epoch: the lower
-- name wins, so every toon picks the same leader. Nothing is replaced automatically
-- when a leader dies or disconnects.
--
-- Role controls: three secure buttons for key bindings, set out of combat only:
--   HaploBoxFollowLeader   /follow <leader>
--   HaploBoxAssistLeader   assist <leader> (type "assist": also works from the player's
--                          own macro, where a type "macro" button would be ignored)
--   HaploBoxFollowHealer   /follow <the team's one healer> (the healer follows the leader;
--                          on the leader it follows the healer, owner decision)
-- They do nothing solo, in a raid, in a group with someone outside the team, and
-- before the group is confirmed. HaploBox never presses them.
local HB = HaploBox

local MAX_EPOCH = 4102444800  -- year 2100; anything larger is not a real time

local function now()
	local t = (GetServerTime and GetServerTime()) or (time and time()) or 0
	return math.floor(t)
end

-- ---------------------------------------------------------------- roster hash
-- Same team, any order and any roles: names normalized, sorted, length-prefixed.
function HB.RosterHash(order)
	local keys, seen = {}, {}
	for _, n in ipairs(order or {}) do
		local k = HB.Norm(n)
		if k and not seen[k] then seen[k] = true keys[#keys + 1] = k end
	end
	table.sort(keys)
	local parts = {}
	for i, k in ipairs(keys) do parts[i] = #k .. ":" .. k end
	local s = table.concat(parts, ";")
	local a, b = 1, 0
	for i = 1, #s do
		a = (a + s:byte(i)) % 65521
		b = (b + a) % 65521
	end
	return tostring(b * 65536 + a)
end

local function teamHash() return HB.RosterHash(HaploBoxTeam and HaploBoxTeam.order) end

-- (epoch, name) order: higher epoch wins; equal epoch: lower normalized name wins.
local function newer(epoch, key)
	local have = tonumber(HaploBoxTeam.leaderEpoch) or 0
	if epoch ~= have then return epoch > have end
	local haveKey = HaploBoxTeam.leaderEpochName
	if type(haveKey) ~= "string" then return true end
	return key < haveKey
end

local function record(epoch, name)
	HaploBoxTeam.leaderEpoch = epoch
	HaploBoxTeam.leaderEpochName = HB.Norm(name)
end

-- Called by Core whenever a full team (M) or /hb leader sets the leader: the epoch
-- only ever goes up, so an older handover arriving late cannot undo it.
function HB.BumpLeaderEpoch(name)
	local e = math.max(tonumber(HaploBoxTeam.leaderEpoch) or 0, now())
	record(e, name)
end

-- ---------------------------------------------------------------- handover
function HB.TakeLead()
	local me = HB.UnitIdent("player")
	if not IsInGroup() then HB.print("join a party with your team first") return end
	if IsInRaid() then HB.print("taking over as leader works in a party, not in a raid") return end
	if not (HaploBoxTeam.order and #HaploBoxTeam.order > 0) then HB.print("no team yet: use /hb team on the leader first") return end
	if not HB.IsTeamName(me) then HB.print("this toon is not in the team") return end
	if HB.IAmLeader() then HB.print("you are already the leader") return end
	local epoch = math.max((tonumber(HaploBoxTeam.leaderEpoch) or 0) + 1, now())
	record(epoch, me)
	HB.SetLeaderRaw(me)
	HB.RefreshTeam()
	HB.SendGroup("H|" .. epoch .. "|" .. teamHash())
	HB.print("you are the leader now; the team keeps its order and roles")
end

function HB.OnHandover(sender, msg)
	local epoch, hash = msg:match("^H|(%d+)|(%d+)$")
	epoch = tonumber(epoch)
	if not epoch or #msg > 40 or epoch ~= epoch or epoch > MAX_EPOCH then
		HB.debug("handover from " .. tostring(sender) .. " ignored: malformed")
		return
	end
	if IsInRaid() then HB.debug("handover from " .. sender .. " ignored: in a raid") return end
	if not HB.InGroup(sender) then HB.debug("handover from " .. sender .. " ignored: not in my group") return end
	if hash ~= teamHash() then
		HB.print("|cffffff00" .. sender:gsub("%-.*$", "") .. "|r took the lead, but its team is different from mine. Ask it for /hb team.")
		return
	end
	if not newer(epoch, HB.Norm(sender)) then
		HB.debug("handover from " .. sender .. " ignored: older than the current leader")
		return
	end
	record(epoch, sender)
	if HB.IsLeaderName(sender) then return end
	HB.SetLeaderRaw(sender)
	HB.RefreshTeam()
	HB.print("|cffffff00" .. sender:gsub("%-.*$", "") .. "|r is the leader now")
end

-- ---------------------------------------------------------------- role controls
local CONTROLS = {
	{ key = "followLeader", button = "HaploBoxFollowLeader", verb = "/follow", label = "Follow leader" },
	{ key = "assistLeader", button = "HaploBoxAssistLeader", verb = "/assist", label = "Assist leader", action = "assist" },
	{ key = "followHealer", button = "HaploBoxFollowHealer", verb = "/follow", label = "Follow healer" },
}
local buttons, applied, pending = {}, {}, false
for _, c in ipairs(CONTROLS) do
	local b = CreateFrame("Button", c.button, UIParent, "SecureActionButtonTemplate")
	b:RegisterForClicks("AnyUp", "AnyDown")
	-- act once, on the up edge: a key binding sends both edges, /click only an up one
	b:SetAttribute("useOnKeyDown", false)
	b:Hide()  -- reached through its key binding, or /click in the player's own macro
	buttons[c.key] = b
end

local function units()
	local out = { "player" }
	for i = 1, 4 do if UnitExists("party" .. i) then out[#out + 1] = "party" .. i end end
	return out
end

-- The one accepted team member in the group with the Blizzard healer role. Shared
-- by the Follow healer key and the team frame's follow labels. A role that cannot
-- be read makes the answer unknown rather than "not a healer".
local function healer()
	if not UnitGroupRolesAssigned then return nil, "this client has no group roles" end
	if not IsInGroup() then return nil, "solo" end
	local found
	local count = 0
	for _, u in ipairs(units()) do
		local name = HB.UnitIdent(u)
		if name and HB.IsTeamName(name) then
			local ok, role = pcall(UnitGroupRolesAssigned, u)
			if not ok or HB.secret(role) or type(role) ~= "string" then return nil, "group roles cannot be read" end
			if role == "HEALER" then
				count = count + 1
				found = name
			end
		end
	end
	if count == 0 then return nil, "no healer role in the team" end
	if count > 1 then return nil, count .. " healer roles in the team" end
	return found
end
HB.TeamHealer = healer

-- What each control should do now: { target = name } or { reason = text }.
function HB.ResolveRoleControls()
	local out = {}
	local function all(why)
		for _, c in ipairs(CONTROLS) do out[c.key] = { reason = why } end
		return out
	end
	if not IsInGroup() then return all("solo") end
	if IsInRaid() then return all("in a raid") end
	local status = HB.GroupStatus()
	if status == "mixed" then return all("someone outside the team is in the group") end
	if status ~= "team" then return all("group not confirmed yet") end
	local leader = HB.Leader()
	if not leader then return all("no leader set") end
	local meLeader = HB.IAmLeader()
	if not meLeader and not HB.InGroup(leader) then return all("the leader is not in the group") end
	local toLeader = meLeader and { reason = "you are the leader" } or { target = leader }
	out.followLeader, out.assistLeader = toLeader, toLeader
	local h, why = healer()
	local me = HB.Norm(HB.UnitIdent("player"))
	if meLeader then
		-- the leader follows the healer when asked (owner decision); a healer that
		-- also presses its own key follows the leader back: two manual presses
		if not h then
			out.followHealer = { reason = why }
		elseif HB.Norm(h) == me then
			out.followHealer = { reason = "you are the leader and the healer" }
		else
			out.followHealer = { target = h }
		end
	elseif not h then
		out.followHealer = { reason = why }
	elseif HB.Norm(h) == me or HB.IsLeaderName(h) then
		out.followHealer = toLeader  -- the healer follows the leader: no loops, never itself
	else
		out.followHealer = { target = h }
	end
	return out
end

function HB.UpdateRoleControls()
	if InCombatLockdown() then
		if not pending then
			pending = true
			if HB.OnRoleControlsPending then HB.OnRoleControlsPending(true) end
		end
		return
	end
	local want = HB.ResolveRoleControls()
	for _, c in ipairs(CONTROLS) do
		local w, b = want[c.key], buttons[c.key]
		if w.target and c.action then
			b:SetAttribute("type", c.action)
			b:SetAttribute("unit", w.target)
			b:SetAttribute("macrotext", nil)
		elseif w.target then
			b:SetAttribute("type", "macro")
			b:SetAttribute("macrotext", c.verb .. " " .. w.target)
		else
			b:SetAttribute("type", nil)
			b:SetAttribute("unit", nil)
			b:SetAttribute("macrotext", "")
		end
		applied[c.key] = w
	end
	if pending then
		pending = false
		if HB.OnRoleControlsPending then HB.OnRoleControlsPending(false) end
	end
end

function HB.RoleControlsPending() return pending end

function HB.PrintRoleControls()
	for _, c in ipairs(CONTROLS) do
		local a = applied[c.key]
		local text = not a and "not set yet" or a.target and ("|cff66ff66" .. c.verb .. " " .. a.target .. "|r")
			or ("|cff999999does nothing: " .. a.reason .. "|r")
		HB.print(c.label .. ": " .. text)
	end
	if pending then HB.print("|cffffaa00the group changed in combat: updated when combat ends|r") end
	HB.print("Key bindings: Keybindings > AddOns > HaploBox")
end

local ev = CreateFrame("Frame")
local crown
ev:SetScript("OnEvent", function(_, event)
	if event == "PARTY_LEADER_CHANGED" then
		for _, r in ipairs(HB.ShownRows()) do if r.partyLead then crown(r) end end
		return
	end
	if event == "PLAYER_ROLES_ASSIGNED" and HB.OnFollowStateChanged then HB.OnFollowStateChanged() end
	if event == "PLAYER_LOGIN" then
		C_Timer.After(3, HB.UpdateRoleControls)  -- after the roster is known
	else
		C_Timer.After(0.2, HB.UpdateRoleControls)
	end
end)
for _, e in ipairs({ "PLAYER_LOGIN", "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "PLAYER_REGEN_ENABLED",
	"UNIT_NAME_UPDATE", "PARTY_LEADER_CHANGED" }) do
	pcall(ev.RegisterEvent, ev, e)
end

-- ---------------------------------------------------------------- team frame
-- The Blizzard party leader gets a small crown on its row (it can differ from the
-- HaploBox leader). Pending controls show as a line under the team frame.
local CROWN = "Interface\\GroupFrame\\UI-Group-LeaderIcon"
table.insert(HB.RowHooks.create, function(r)
	r.partyLead = r:CreateTexture(nil, "OVERLAY")
	r.partyLead:SetSize(12, 12)
	r.partyLead:SetTexture(CROWN)
	r.partyLead:SetPoint("TOPRIGHT", r.bg, "TOPRIGHT", -2, -2)
	r.partyLead:Hide()
end)
function crown(r)
	local ok, lead = false, false
	if r.unit and UnitIsGroupLeader then ok, lead = pcall(UnitIsGroupLeader, r.unit) end
	r.partyLead:SetShown(ok and not HB.secret(lead) and lead and IsInGroup() and true or false)
end
table.insert(HB.RowHooks.refresh, crown)
table.insert(HB.RowHooks.clear, function(r) r.partyLead:Hide() end)

local note
function HB.OnRoleControlsPending(on)
	local frame = HaploBoxPartyFrame
	if not frame then return end
	if not note then
		note = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		note:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 2, -2)
		note:SetText("|cffffaa00follow/assist keys: updated after combat|r")
	end
	note:SetShown(on and true or false)
end
