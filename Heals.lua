-- Incoming heals from the team's own healers, for clients without
-- UnitGetIncomingHeals (WoW Forever). Not yet checked in the game.
--
-- A healer running HaploBox announces its own cast-time single-target heals:
--   I|<id>|<target>|<amount>|<ms left>   when the cast starts
--   I|<id>|-                             when it stops, fails, is interrupted or lands
-- The amount is an estimate: the base size from the spell's own description for
-- the rank being cast ("for 135 to 158" -> 147), without bonus healing or talents.
-- WoW Forever forbids addons the combat log, so landed heals cannot be measured.
-- Only English descriptions are read; another format announces nothing.
-- Group heals, instant heals and heal-over-time ticks are not covered.
-- Routes follow the stats rule: the group channel while the group is only the team;
-- with anyone else in it, a whisper to the leader alone; nothing in a raid or solo.
-- The client's own UnitGetIncomingHeals always wins where it exists.
local HB = HaploBox

-- Single-target heals with a cast time, by base spell ID; the client gives the
-- localized names, and every rank shares the name.
local SUPPORTED_IDS = { 2050, 2054, 2060, 2061, 5185, 8936, 331, 8004, 635, 19750 }
local supported
local secret = HB.secret
local function plain(v) return v ~= nil and not secret(v) end
local function spellName(id)
	if not plain(id) then return nil end
	local n
	if C_Spell and C_Spell.GetSpellName then n = C_Spell.GetSpellName(id)
	elseif GetSpellInfo then n = (GetSpellInfo(id)) end
	if type(n) == "string" and not secret(n) then return n end
end
-- a size usable in arithmetic: a plain finite positive number
local function goodSize(v)
	return type(v) == "number" and not secret(v) and v == v and v > 0 and v < 1000000
end
local function isSupported(id)
	if not supported then
		supported = {}
		for _, sid in ipairs(SUPPORTED_IDS) do
			local n = spellName(sid)
			if n then supported[n] = true end
		end
	end
	local n = id and spellName(id)
	return n and supported[n] and n or nil
end

local MAX_OPEN = 4

-- "1,200" -> 1200
local function number(s) return s and tonumber((s:gsub(",", ""))) end

-- The base size of one rank from its description: the first "X to Y" range (the
-- direct heal; Regrowth's heal-over-time total comes later), else the first
-- "for X". nil while the description is not loaded or not readable.
local sizeCache = {}
local function parseSize(text)
	local lo, hi = text:match("(%d[%d,]*) to (%d[%d,]*)")
	lo, hi = number(lo), number(hi)
	if lo and hi then return (lo + hi) / 2 end
	return number(text:match("for (%d[%d,]*)"))
end
HB.HealSizeFromText = parseSize
local function sizeOf(spellID)
	if not plain(spellID) then return nil end
	if sizeCache[spellID] then return sizeCache[spellID] end
	local get = (C_Spell and C_Spell.GetSpellDescription) or GetSpellDescription
	if type(get) ~= "function" then return nil end
	local ok, text = pcall(get, spellID)
	if not ok or type(text) ~= "string" or secret(text) or text == "" then return nil end
	local size = parseSize(text)
	if not goodSize(size) then return nil end
	size = math.floor(size + 0.5)
	sizeCache[spellID] = size
	return size
end

-- ---------------------------------------------------------------- incoming (all toons)
local incoming = {}  -- target key -> { [sender:id] = { amount, expires, token } }
local tokens = 0

local function changed(key)
	if not HB.ShownRows then return end
	for _, r in ipairs(HB.ShownRows()) do
		if HB.Norm(r.name) == key and HB.UpdateHealPrediction then HB.UpdateHealPrediction(r) end
	end
end

local function drop(key, entryKey)
	local list = incoming[key]
	if not (list and list[entryKey]) then return end
	list[entryKey] = nil
	if next(list) == nil then incoming[key] = nil end  -- no empty tables left behind
	changed(key)
end

local function removeEntry(entryKey)
	local keys = {}
	for key, list in pairs(incoming) do if list[entryKey] then keys[#keys + 1] = key end end
	for _, key in ipairs(keys) do drop(key, entryKey) end
end

local function addEntry(target, entryKey, amount, seconds, sender)
	local key = HB.Norm(target)
	if not key then return end
	removeEntry(entryKey)
	tokens = tokens + 1
	local token = tokens
	incoming[key] = incoming[key] or {}
	incoming[key][entryKey] = { amount = amount, expires = GetTime() + seconds + 0.5, token = token, sender = sender, target = target }
	changed(key)
	C_Timer.After(seconds + 0.6, function()
		local e = incoming[key] and incoming[key][entryKey]
		if e and e.token == token then drop(key, entryKey) end  -- an older timer never removes a newer cast
	end)
end

-- me, or an accepted team member in my group
local function teamTarget(name)
	if HB.Norm(name) == HB.Norm(HB.UnitIdent("player")) then return true end
	return HB.IsTeamName(name) and HB.InGroup(name)
end

-- Sum of the heals announced on that name and not yet expired.
function HB.TeamIncoming(name)
	local list = incoming[HB.Norm(name) or ""]
	if not list then return 0 end
	local now, sum = GetTime(), 0
	for _, e in pairs(list) do if e.expires > now then sum = sum + e.amount end end
	return sum
end

function HB.OnIncomingHeal(sender, msg)
	if #msg > 80 or not HB.InGroup(sender) then return end
	local id, rest = msg:match("^I|(%d+)|(.+)$")
	if not id or #id > 4 then return end
	local entryKey = HB.Norm(sender) .. ":" .. id
	if rest == "-" then removeEntry(entryKey) return end
	local target, amount, ms = rest:match("^([^|\r\n]+)|(%d+)|(%d+)$")
	amount, ms = tonumber(amount), tonumber(ms)
	if not target or #target > 60 or not amount or amount < 1 or amount > 100000 or ms > 10000 then return end
	if not teamTarget(target) then return end
	local prefix, open = HB.Norm(sender) .. ":", 0
	for _, list in pairs(incoming) do
		for k in pairs(list) do if k ~= entryKey and k:sub(1, #prefix) == prefix then open = open + 1 end end
	end
	if open >= MAX_OPEN then return end
	addEntry(target, entryKey, amount, ms / 1000, sender)
end

-- After a roster or team change: heals from a healer, or on a target, that is no
-- longer a team member in my group go at once (they never come back on a rejoin).
local function revalidate()
	local gone = {}
	for key, list in pairs(incoming) do
		for entryKey, e in pairs(list) do
			if (e.sender and not teamTarget(e.sender)) or not teamTarget(e.target) then
				gone[#gone + 1] = { key, entryKey }
			end
		end
	end
	for _, g in ipairs(gone) do drop(g[1], g[2]) end
end
HB.RevalidateIncomingHeals = revalidate

-- ---------------------------------------------------------------- my casts (healer)
local nextId = 0
local casts = {}     -- castGUID -> { id, target, spellID, routes = {}, started }

-- the unit in my party with that name: full name-realm, or a bare name that fits one
local function resolve(name)
	if type(name) ~= "string" or name == "" or HB.secret(name) then return nil end
	local key = HB.Norm(name)
	local found
	for _, u in ipairs({ "player", "party1", "party2", "party3", "party4" }) do
		local ident = UnitExists(u) and HB.UnitIdent(u)
		if ident then
			local short = ident:gsub("%-.*$", "")
			local bare = not name:find("-", 1, true)
			if HB.Norm(ident) == key or (bare and HB.Norm(short) == key) then
				if found then return nil end  -- two people fit that name: unknown
				found = ident
			end
		end
	end
	return found
end

local function myKey(id) return HB.Norm(HB.UnitIdent("player")) .. ":" .. id end

-- where announcements go now: "group", a leader's name, or nil
local function route()
	if not HB.db.teamSendHeals or not IsInGroup() or IsInRaid() then return nil end
	local status = HB.GroupStatus()
	if status == "team" then return "group" end
	if HB.IAmLeader() then return nil end
	local leader = HB.Leader()
	if leader and HB.InGroup(leader) then return leader end
end

local function deliver(c, msg, to, check)
	local function ok() c.routes[to] = true end
	if to == "group" then
		HB.SendGroupChecked(msg, nil, ok, check)
	else
		HB.Whisper(to, msg, nil, ok, check)
	end
end

local function stopCast(guid)
	local c = casts[guid]
	if not c then return end
	casts[guid] = nil
	c.stopped = true  -- a start still in the send queue is dropped
	removeEntry(myKey(c.id))
	-- every route that saw the start hears the stop, even if the group changed since
	for to in pairs(c.routes) do
		if to == "group" then
			if IsInGroup() then HB.SendGroupChecked("I|" .. c.id .. "|-") end
		elseif HB.InGroup(to) then
			HB.Whisper(to, "I|" .. c.id .. "|-")
		end
	end
end

local function startCast(guid, again)
	local c = casts[guid]
	if not c or (c.started and not again) then return end
	local amount = sizeOf(c.spellID)
	local _, _, _, _, endMS = UnitCastingInfo("player")
	if not goodSize(amount) or type(endMS) ~= "number" or secret(endMS) then return end
	local ms = math.max(0, math.min(10000, math.floor(endMS - GetTime() * 1000)))
	c.started = true
	addEntry(c.target, myKey(c.id), amount, ms / 1000)
	local to = route()
	if not to then return end
	local msg = "I|" .. c.id .. "|" .. c.target .. "|" .. math.floor(amount) .. "|" .. ms
	-- the time left is fixed in the message, so a copy held up in the send queue
	-- for more than half a second is dropped rather than shown too long
	local queued = GetTime()
	deliver(c, msg, to, function()
		return not c.stopped and route() == to and teamTarget(c.target) and GetTime() - queued <= 0.5
	end)
end

local function onCast(event, unit, a, b, c)
	if not plain(unit) or unit ~= "player" then return end
	if (a ~= nil and secret(a)) or (b ~= nil and secret(b)) or (c ~= nil and secret(c)) then return end
	if event == "UNIT_SPELLCAST_SENT" then
		local target, guid, spellID = a, b, c
		if not (guid and spellID and isSupported(spellID)) then return end
		local who = resolve(target)
		if not who or not teamTarget(who) then return end
		nextId = nextId % 9999 + 1
		casts[guid] = { id = nextId, target = who, spellID = spellID, routes = {} }
	elseif event == "UNIT_SPELLCAST_START" then
		startCast(a)
	elseif event == "UNIT_SPELLCAST_DELAYED" then  -- pushback: announce the new end
		startCast(a, true)
	else  -- SUCCEEDED, STOP, FAILED, FAILED_QUIET, INTERRUPTED
		stopCast(a)
	end
end

-- sending turned off: stop every open announcement at once
function HB.StopHealAnnouncements()
	for guid in pairs(casts) do stopCast(guid) end
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, ...)
	if event == "GROUP_ROSTER_UPDATE" or event == "UNIT_NAME_UPDATE" then revalidate() return end
	onCast(event, ...)
end)
for _, e in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_STOP",
	"UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED", "GROUP_ROSTER_UPDATE", "UNIT_NAME_UPDATE" }) do
	-- never COMBAT_LOG_EVENT_UNFILTERED: WoW Forever forbids it to addons
	pcall(ev.RegisterEvent, ev, e)
end
