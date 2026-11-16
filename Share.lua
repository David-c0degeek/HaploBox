-- Share the team frame layout (#14): the leader sends a chosen set of display
-- settings and positions to accepted team members by addon whisper. A follower
-- takes it only from its stored leader, keeps a copy of what it had, and can go back
-- with /hb frame undo. Gameplay, team, privacy and automation settings are never
-- part of it, nor the Main / Mini Heal choice.
--   U|<id>|<i>|<n>|<piece>   leader -> toon, the settings in pieces
--   A|<id>|<result>          toon -> leader: applied, waiting, rejected:<why>
local HB = HaploBox

local VERSION = 1
local MAX_PIECES, PIECE_TTL, MAX_ASSEMBLIES, SEEN_PER_SENDER = 8, 30, 4, 8
local RETRY_AFTER = 8

-- the versioned allowlist: key -> kind
local FIELDS = {
	partyScale = "scale",
	teamW = "width", teamRowH = "height", teamMiniW = "miniwidth", teamMiniH = "height",
	teamClassColors = "bool", teamShowXP = "bool", teamShowGold = "bool", teamShowBags = "bool",
	teamShowBuffs = "bool", teamHealPrediction = "bool", teamCastBars = "bool", teamManaRule = "bool",
	teamShowHots = "bool", teamBuffOverview = "bool", teamDebuffOverview = "bool",
	teamHotNames = "text", teamRequiredBuffs = "text",
	pos = "pos", buffsPos = "pos", debuffsPos = "pos",
}
local ORDER = {}
for k in pairs(FIELDS) do ORDER[#ORDER + 1] = k end
table.sort(ORDER)
HB.SHARE_FIELDS = FIELDS
local BOUNDS = { width = { 150, 500 }, miniwidth = { 90, 500 }, height = { 28, 70 }, scale = { 0.5, 2 } }

-- "d" on the wire: the leader uses the default here, so the follower drops its own
-- override instead of keeping it
local DEFAULT = {}
HB.SHARE_DEFAULT = DEFAULT

local function finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end

local function checksum(s)
	local a, b = 1, 0
	for i = 1, #s do
		a = (a + s:byte(i)) % 65521
		b = (b + a) % 65521
	end
	return tostring(b * 65536 + a)
end

local function screenSize()
	local w, h = UIParent:GetWidth(), UIParent:GetHeight()
	if finite(w) and finite(h) and w > 0 and h > 0 then return w, h end
end

-- ---------------------------------------------------------------- encode / decode
-- This toon's current values for the allowlist, as wire text.
function HB.ShareText()
	local db, parts = HB.db, { "v=" .. VERSION }
	for _, k in ipairs(ORDER) do
		local kind, v = FIELDS[k], nil
		if kind == "bool" then
			v = db[k] and "1" or "0"
		elseif kind == "text" then
			v = (db[k] or ""):gsub("[;=|]", "")
		elseif kind == "pos" then
			local w, h = screenSize()
			if k == "pos" then
				local p, s = db.partyPos, HB.PartyFrameScale()
				if w and type(p) == "table" and finite(p[3]) and finite(p[4]) and finite(s) then
					v = string.format("%.4f,%.4f", math.min(1, math.max(0, p[3] * s / w)), math.min(1, math.max(0, p[4] * s / h)))
				end
			else
				local p = HB.ClampAuraPos(db.auraPos and db.auraPos[k == "buffsPos" and "buffs" or "debuffs"])
				if p then v = string.format("%.4f,%.4f", p.x, p.y) end
			end
			v = v or "d"
		elseif finite(db[k]) then
			v = tostring(db[k])
		else
			v = "d"
		end
		if v then parts[#parts + 1] = k .. "=" .. v end
	end
	local body = table.concat(parts, ";")
	return body .. ";sum=" .. checksum(body)
end

-- Checks a whole payload. Returns a table key -> value, or nil and the reason.
function HB.DecodeShare(text)
	if type(text) ~= "string" or #text > 2000 then return nil, "size" end
	local body, sum = text:match("^(.*);sum=(%d+)$")
	if not body or checksum(body) ~= sum then return nil, "checksum" end
	local out, seen, version = {}, {}, nil
	for part in body:gmatch("[^;]+") do
		local k, v = part:match("^([%w]+)=(.*)$")
		if not k or seen[k] then return nil, "format" end
		seen[k] = true
		if k == "v" then
			version = tonumber(v)
		else
			local kind = FIELDS[k]
			if not kind then return nil, "unknown " .. k end
			if kind == "bool" then
				if v ~= "0" and v ~= "1" then return nil, "bad " .. k end
				out[k] = v == "1"
			elseif kind == "text" then
				if #v > 200 or v:find("[|]") then return nil, "bad " .. k end
				out[k] = v
			elseif v == "d" and kind ~= "scale" then
				out[k] = DEFAULT
			elseif kind == "pos" then
				local x, y = v:match("^([%d%.%-]+),([%d%.%-]+)$")
				x, y = tonumber(x), tonumber(y)
				if not (finite(x) and finite(y)) or x < 0 or x > 1 or y < 0 or y > 1 then return nil, "bad " .. k end
				out[k] = { x = x, y = y }
			else
				local n = tonumber(v)
				local b = BOUNDS[kind]
				if not finite(n) or n < b[1] or n > b[2] then return nil, "bad " .. k end
				out[k] = n
			end
		end
	end
	if version ~= VERSION then return nil, "version" end
	return out
end

-- ---------------------------------------------------------------- snapshot and apply
-- Every key the share can touch, with absence kept: { key = { value } or { absent = true } }.
local SNAP_KEYS = { "partyPos", "auraPos" }
for _, k in ipairs(ORDER) do if FIELDS[k] ~= "pos" then SNAP_KEYS[#SNAP_KEYS + 1] = k end end

local function copy(v)
	if type(v) ~= "table" then return v end
	local t = {}
	for k, x in pairs(v) do t[k] = copy(x) end
	return t
end

local function snapshot()
	local snap = {}
	for _, k in ipairs(SNAP_KEYS) do
		if HB.db[k] == nil then snap[k] = { absent = true } else snap[k] = { value = copy(HB.db[k]) } end
	end
	return snap
end

local function relayout()
	if HB.LayoutPartyFrame then HB.LayoutPartyFrame() end
	if HB.ApplyPartyPosition then HB.ApplyPartyPosition() end
	if HB.PlaceAuraOverviews then HB.PlaceAuraOverviews() end
	if HB.RefreshAuraOverviews then HB.RefreshAuraOverviews() end
	if HB.RefreshSettingsViews then HB.RefreshSettingsViews() end
end

-- Puts every value back (false stays false, absent stays absent) before drawing,
-- so a drawing error cannot keep the old values from coming back.
local function restore(snap)
	for _, k in ipairs(SNAP_KEYS) do
		local e = snap[k]
		if e then
			if e.absent then HB.db[k] = nil else HB.db[k] = copy(e.value) end
		end
	end
	pcall(relayout)
end

-- Writes a checked payload. Everything was validated before; a refusal here still
-- puts every value back. Returns true or nil and the reason.
local function apply(values)
	local snap = snapshot()
	local ok, err = pcall(function()
		for _, k in ipairs(ORDER) do
			local v, kind = values[k], FIELDS[k]
			if v ~= nil then
				if v == DEFAULT then
					if k == "pos" then
						HB.db.partyPos = nil
					elseif kind == "pos" then
						if HB.db.auraPos then HB.db.auraPos[k == "buffsPos" and "buffs" or "debuffs"] = nil end
					else
						HB.db[k] = nil
					end
				elseif kind == "pos" then
					if k == "pos" then
						local w, h = screenSize()
						local s = values.partyScale or HB.db.partyScale or 1
						if w then HB.db.partyPos = { "TOPLEFT", "BOTTOMLEFT", v.x * w / s, v.y * h / s } end
					else
						HB.db.auraPos = HB.db.auraPos or {}
						HB.db.auraPos[k == "buffsPos" and "buffs" or "debuffs"] = { x = v.x, y = v.y }
					end
				elseif kind == "bool" or kind == "text" or kind == "scale" then
					if HB.SetOption(k, v) == nil then error("refused " .. k) end
				else
					HB.db[k] = math.floor(v + 0.5)
				end
			end
		end
		relayout()  -- inside the pcall: a drawing error puts everything back too
	end)
	if not ok then
		restore(snap)
		return nil, tostring(err):match("refused %w+") or "error"
	end
	HB.db.uiBackup = snap
	return true
end

function HB.UndoSharedUI()
	local snap = HB.db.uiBackup
	if type(snap) ~= "table" then HB.print("no shared layout to undo") return end
	if InCombatLockdown() then HB.print("not in combat") return end
	HB.db.uiBackup = nil
	restore(snap)
	HB.print("team frame layout put back as it was before the shared one")
end

-- ---------------------------------------------------------------- follower side
local assemblies = {}   -- sender:id -> { at, n, pieces = {}, count }
local queued            -- { sender, id, text } waiting for the end of combat

local function answer(sender, id, result) HB.Whisper(sender, "A|" .. id .. "|" .. result) end

-- Ids grow with time on the leader, also across reloads. Per sender the follower
-- saves the newest id it took and its answer: an older id is refused as stale, the
-- same id again only gets the same answer. Saved, so a replay after a reload fails too.
local function newest(sender)
	local t = HB.db.shareNewest
	return type(t) == "table" and t[HB.Norm(sender)]
end

local function remember(sender, id, result)
	if type(HB.db.shareNewest) ~= "table" then HB.db.shareNewest = {} end
	local t, key = HB.db.shareNewest, HB.Norm(sender)
	local e = t[key]
	if e and e.id > id then return end
	t[key] = { id = id, result = result, name = sender }
	local count, oldest, oldestKey = 0, nil, nil
	for k, x in pairs(t) do
		count = count + 1
		if not oldest or x.id < oldest then oldest, oldestKey = x.id, k end
	end
	if count > SEEN_PER_SENDER then t[oldestKey] = nil end
end

local function senderOk(sender)
	return HB.IsLeaderName(sender) and HB.InGroup(sender) and HB.IsTeamName(HB.UnitIdent("player"))
end

local function finish(sender, id, values)
	local result
	if not HB.db.acceptSharedUI then
		result = "rejected:off"
	elseif not senderOk(sender) then
		result = "rejected:not leader"
	else
		local ok, why = apply(values)
		result = ok and "applied" or ("rejected:" .. why)
		if ok then HB.print("team frame layout from |cffffff00" .. sender:gsub("%-.*$", "") .. "|r applied (/hb frame undo puts yours back)") end
	end
	remember(sender, id, result)
	answer(sender, id, result)
end

local function onPayload(sender, id, text)
	local last = newest(sender)
	if last and id < last.id then answer(sender, id, "rejected:stale") return end
	-- a resend gets the same answer and nothing is applied again; "waiting" with
	-- nothing waiting here (a reload in between) is not an answer, so it is processed again
	if last and id == last.id and not (last.result == "waiting" and not (queued and queued.id == id)) then
		answer(sender, id, last.result)
		return
	end
	local values, why = HB.DecodeShare(text)
	if not values then
		remember(sender, id, "rejected:" .. why)
		answer(sender, id, "rejected:" .. why)
		return
	end
	if not HB.db.acceptSharedUI then finish(sender, id, values) return end
	if InCombatLockdown() then
		if queued then  -- older: it was not stale, so this one is newer
			remember(queued.sender, queued.id, "rejected:superseded")
			answer(queued.sender, queued.id, "rejected:superseded")
		end
		queued = { sender = sender, id = id }
		remember(sender, id, "waiting")
		answer(sender, id, "waiting")
		queued.text = text
		return
	end
	finish(sender, id, values)
end

local function onPiece(sender, msg)
	local id, i, n, piece = msg:match("^U|(%d+)|(%d+)|(%d+)|(.*)$")
	id, i, n = tonumber(id), tonumber(i), tonumber(n)
	if not (id and i and n) or id > 9999999999 or n < 1 or n > MAX_PIECES or i < 1 or i > n then return end
	local now = GetTime()
	for key, a in pairs(assemblies) do if now - a.at > PIECE_TTL then assemblies[key] = nil end end
	local key = HB.Norm(sender) .. ":" .. id
	local a = assemblies[key]
	if not a then
		local count, oldest, oldestKey = 0, nil, nil
		for k, x in pairs(assemblies) do
			count = count + 1
			if not oldest or x.at < oldest then oldest, oldestKey = x.at, k end
		end
		if count >= MAX_ASSEMBLIES then assemblies[oldestKey] = nil end
		a = { at = now, n = n, pieces = {}, count = 0 }
		assemblies[key] = a
	end
	if a.n ~= n or a.pieces[i] then return end
	a.pieces[i], a.count = piece, a.count + 1
	if a.count < n then return end
	assemblies[key] = nil
	onPayload(sender, id, table.concat(a.pieces, "", 1, n))
end

local function applyQueued()
	local q = queued
	queued = nil
	if not q then return end
	local values = HB.DecodeShare(q.text)  -- checked again, as at arrival
	if not values then
		remember(q.sender, q.id, "rejected:format")
		answer(q.sender, q.id, "rejected:format")
		return
	end
	finish(q.sender, q.id, values)
end

-- After a reload nothing waits here any more: a share saved as "waiting" is answered
-- as lost, so the leader does not show "waiting" forever. Its leader can share again.
local function reconcile()
	local t = HB.db and HB.db.shareNewest
	if type(t) ~= "table" then return end
	for key, e in pairs(t) do
		if type(e) == "table" and e.result == "waiting" and not (queued and queued.id == e.id) then
			e.result = "rejected:reload"
			local to = type(e.name) == "string" and e.name or key
			if HB.IsLeaderName(to) then answer(to, e.id, e.result) end
		end
	end
end
HB.ReconcileShares = reconcile

local combat = CreateFrame("Frame")
combat:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		C_Timer.After(2, reconcile)  -- after HaploBox has read its saved settings
	else
		applyQueued()
	end
end)
pcall(combat.RegisterEvent, combat, "PLAYER_REGEN_ENABLED")
pcall(combat.RegisterEvent, combat, "PLAYER_LOGIN")

-- ---------------------------------------------------------------- leader side
local job       -- the newest share: { id, text, members = { name = state } }
local confirm   -- what the confirmation popup showed: { names, text }
-- the last id this account sent, saved so ids keep growing after a reload

local RESULT_TEXT = {
	sent = "sent, no answer yet", waiting = "waiting for the end of combat", applied = "applied",
	failed = "could not be sent", noanswer = "no answer (older HaploBox, offline or out of reach)",
	left = "left the group, not sent",
	["rejected:reload"] = "was waiting, then the UI reloaded; share again",
}

local function stillTarget(name) return HB.IsTeamName(name) and HB.InGroup(name) end

local function report(name, state)
	local text = RESULT_TEXT[state] or ("refused: " .. tostring(state):gsub("^rejected:", ""))
	HB.print("shared layout, |cffffff00" .. name:gsub("%-.*$", "") .. "|r: " .. text)
end

local function sendTo(j, name)
	if not stillTarget(name) then j.members[name] = "left" report(name, "left") return end
	local pieces = HB.SplitText("U|" .. j.id, j.text)
	if not pieces then j.members[name] = "failed" report(name, "failed") return end
	local failed = false
	for k, p in ipairs(pieces) do
		HB.Whisper(name, "U|" .. j.id .. "|" .. k .. "|" .. #pieces .. "|" .. p, function()
			if failed or job ~= j then return end
			failed = true
			local gone = not stillTarget(name)
			j.members[name] = gone and "left" or "failed"
			report(name, j.members[name])
		end, nil, function() return job == j and stillTarget(name) end)
	end
end

local function recipients()
	local names, me = {}, HB.Norm(HB.UnitIdent("player"))
	for _, n in ipairs(HaploBoxTeam.order or {}) do
		if HB.Norm(n) ~= me and stillTarget(n) then names[#names + 1] = n end
	end
	return names
end

-- Sends exactly what the popup showed, to exactly the names it showed.
local function startShare(names, text)
	local now = math.floor((GetServerTime and GetServerTime()) or (time and time()) or 0)
	local last = tonumber(HB.db.shareLastId) or 0
	local id = math.max(last + 1, now)
	HB.db.shareLastId = id
	local j = { id = id, text = text, members = {} }
	job = j  -- a newer share replaces the old one; its answers are ignored
	for _, name in ipairs(names) do
		j.members[name] = "sent"
		sendTo(j, name)
	end
	C_Timer.After(RETRY_AFTER, function()
		if job ~= j then return end
		for name, state in pairs(j.members) do if state == "sent" then sendTo(j, name) end end
		C_Timer.After(RETRY_AFTER, function()
			if job ~= j then return end
			for name, state in pairs(j.members) do
				if state == "sent" then j.members[name] = "noanswer" report(name, "noanswer") end
			end
		end)
	end)
end

local SHARE_POPUP = "HAPLOBOX_SHARE_UI"
HB.SHARE_PREVIEW = "what the team frame shows, its size, scale and position, and the aura windows"
	.. ". Not shared: Main / Mini Heal, team and roles, automation, sounds and key bindings."

function HB.ShareUI()
	if not HB.IAmLeader() then HB.print("only the team leader can share the layout") return end
	local names = recipients()
	if #names == 0 then HB.print("no team member in the group to share the layout with") return end
	local short = {}
	for i, n in ipairs(names) do short[i] = n:gsub("%-.*$", "") end
	confirm = { names = names, text = HB.ShareText() }
	HB.print("share this layout with " .. table.concat(short, ", ") .. "? Confirm in the popup.")
	if StaticPopupDialogs and StaticPopup_Show then
		StaticPopupDialogs[SHARE_POPUP] = {
			text = "HaploBox: share your team frame layout with %s?\n\nShared: %s",
			button1 = ACCEPT or "Accept",
			button2 = CANCEL or "Cancel",
			OnAccept = function()
				local c = confirm
				confirm = nil
				if c then startShare(c.names, c.text) end
			end,
			OnCancel = function() confirm = nil end,
			timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
		}
		if StaticPopup_Hide then StaticPopup_Hide(SHARE_POPUP) end
		StaticPopup_Show(SHARE_POPUP, table.concat(short, ", "), HB.SHARE_PREVIEW)
	end
end

local function onAnswer(sender, msg)
	local id, result = msg:match("^A|(%d+)|(.+)$")
	id = tonumber(id)
	if not (job and id == job.id) then return end
	local name
	for n in pairs(job.members) do if HB.Norm(n) == HB.Norm(sender) then name = n end end
	if not name then return end
	local state = (result == "applied" or result == "waiting") and result or result:sub(1, 40)
	if job.members[name] == state then return end
	job.members[name] = state
	report(name, state)
end

function HB.OnShareMessage(kind, sender, msg)
	if kind == "U" then onPiece(sender, msg) else onAnswer(sender, msg) end
end

function HB.ShareJob() return job end
