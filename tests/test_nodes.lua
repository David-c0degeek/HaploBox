-- Gathering nodes found by followers, shown on the leader's minimap (#5).

local MAP = 1429
local function where(x, y) W.map = { id = MAP, x = x or 0.5, y = y or 0.5, w = 3000, h = 2000 } end

local function asFollower(db)
	W.me = "Elya"
	party("Haplo", "Nyra")
	login(db or {}, standardTeam("Haplo"))
	where()
end

local function asLeader(db)
	party("Elya", "Nyra")
	login(db or {}, standardTeam("Haplo"))
	where()
end

local function reports() return sentMatching("^N|", "WHISPER") end

local function gather(guid, name, spell, ok)
	fire("UNIT_SPELLCAST_SENT", "player", name, guid, spell or 2366)
	if ok == false then
		fire("UNIT_SPELLCAST_FAILED", "player", guid, spell or 2366)
	else
		fire("UNIT_SPELLCAST_SUCCEEDED", "player", guid, spell or 2366)
	end
end

local function N(kind, x, y, src, ago, name)
	return string.format("N|%s|%d|%d|%d|%s|%d|%s", kind, MAP, x, y, src, GetServerTime() - (ago or 0), name)
end

test("hovering a known node on the minimap reports it to the leader only", function()
	asFollower()
	hoverMinimap("Peacebloom", 30, 0)  -- 30 px east: 100 yards at zoom 0
	advance(2)
	local r = reports()
	eq(#r, 1, "one report")
	eq(r[1].target, "Haplo", "to the leader")
	eq(r[1].msg, "N|h|1429|5333|5000|h|" .. GetServerTime() - 2 .. "|Peacebloom", "type, map, position, source, time, name")
	eq(#sentMatching("^N|", "PARTY"), 0, "never to the group")
end)

test("WoW Forever: a tooltip anchored to UIParent counts only while the cursor is on the round minimap", function()
	asFollower()
	W.minimapScale = 1.25
	hoverMinimap("Earthroot", 30, 0, "UIParent")
	advance(2)
	eq(#reports(), 1, "reported")
	assert(reports()[1].msg:find("^N|h|1429|5333|5000|h|"), reports()[1].msg)
	hoverMinimap("Peacebloom", 200, 0, "UIParent")    -- off the minimap
	hoverMinimap("Silverleaf", 65, 65, "UIParent")    -- in the frame's corner, outside the circle
	local other = CreateFrame("Button", "SomeButton")
	hoverMinimap("Mageroyal", 10, 0, other)          -- a minimap button's own tooltip
	advance(3)
	eq(#reports(), 1, "none of those")
	hoverMinimap("Briarthorn", 0, 30, "UIParent", true)  -- the text arrives through SetText
	advance(2)
	eq(#reports(), 2, "SetText path")
end)

test("WoW Forever: a mouse-over test that wrongly says no cannot stop a hover inside the circle", function()
	asFollower()
	Minimap.IsMouseOver = function() return false end  -- as seen in the game: false at dx 4, dy -1
	MouseIsOver = function() return false end
	hoverMinimap("Earthroot", 4, -1, "UIParent")
	advance(2)
	eq(#reports(), 1, "reported")
	hoverMinimap("Peacebloom", 200, 0, "UIParent")
	hoverMinimap("Silverleaf", 65, 65, "UIParent")
	advance(3)
	eq(#reports(), 1, "outside the circle: nothing")
end)

test("a hidden minimap, or one under a hidden parent, never counts", function()
	asFollower({ debug = true })
	Minimap:Hide()
	hoverMinimap("Earthroot", 30, 0, "UIParent")
	Minimap:Show()
	W.minimapParentHidden = true
	hoverMinimap("Peacebloom", 0, 30, "UIParent")
	advance(3)
	eq(#reports(), 0, "nothing")
	eq(printedMatching("the minimap is hidden"), 1, "said, once per 5 s")
	W.minimapParentHidden = false
	hoverMinimap("Peacebloom", 0, 30, "UIParent")
	advance(2)
	eq(#reports(), 1, "visible again")
end)

test("debug says why a minimap hover was dropped, without spam", function()
	asFollower({ debug = true })
	hoverMinimap("Hogger", 30, 0, "UIParent")       -- any other tooltip: silent
	eq(printedMatching("minimap hover"), 0, "nothing for unrelated UIParent tooltips")
	hoverMinimap("Hogger", 30, 0)                   -- owned by the minimap: say so
	hoverMinimap("Hogger", 30, 0)
	eq(printedMatching("no known herb or ore"), 1, "once")
	W.map = nil
	hoverMinimap("Earthroot", 30, 0, "UIParent")
	eq(printedMatching("no map position here %(Earthroot%)"), 1, "no position, named")
	hoverMinimap("Earthroot", 65, 65, "UIParent")    -- the frame's corner: outside the circle
	hoverMinimap("Earthroot", 66, 64, "UIParent")
	eq(printedMatching("outside the minimap circle %(dx 65, dy 65, radius 70%)"), 1, "outside, with offsets, once")
	Minimap:Hide()
	hoverMinimap("Earthroot", 30, 0, "UIParent")
	eq(printedMatching("the minimap is hidden %(Earthroot%)"), 1, "hidden, named")
end)

test("WoW Forever's marker before a node name is removed; learned names keep every letter", function()
	asFollower()
	hoverMinimap("\226\150\190 Silverleaf", 30, 0, "UIParent")
	hoverMinimap("\226\128\162 Copper Vein", 0, 30, "UIParent")
	advance(3)
	eq(#reports(), 2, "both reported")
	assert(reports()[1].msg:find("|Silverleaf$"), reports()[1].msg)
	assert(reports()[2].msg:find("|Copper Vein$"), reports()[2].msg)
	local accented = "\195\137lune"  -- learned, starts with a non-ASCII letter
	HB.db.nodeNames = HB.db.nodeNames or {}
	HB.db.nodeNames[accented] = "h"
	hoverMinimap("\226\150\190 " .. accented, 0, -30, "UIParent")
	advance(2)
	eq(#reports(), 3, "reported")
	assert(reports()[3].msg:find("|" .. accented .. "$"), "name kept whole")
	eq(HB.NodeCleanName("x Silverleaf"), "x Silverleaf", "other prefixes stay")
end)

test("a rotating minimap is turned back to north", function()
	asFollower()
	W.rotate, W.facing = true, math.pi / 2  -- facing west: up on the minimap is west
	hoverMinimap("Copper Vein", 0, 30)
	advance(2)
	assert(reports()[1].msg:find("^N|o|1429|4667|5000|h|"), reports()[1].msg)
end)

test("facing south turns the minimap half way", function()
	asFollower()
	W.rotate, W.facing = true, math.pi  -- up on the minimap is south
	hoverMinimap("Copper Vein", 30, 0)   -- right of the player is west
	advance(2)
	assert(reports()[1].msg:find("^N|o|1429|4667|5000|h|"), reports()[1].msg)
end)

test("indoor zoom uses the indoor scale; the client's view radius wins when it has one", function()
	asFollower()
	W.zoom, W.inZoom, W.outZoom = 3, 3, 0  -- indoors at zoom 3: 120 yards across
	hoverMinimap("Peacebloom", 35, 0)       -- a quarter of the width: 30 yards east
	advance(2)
	assert(reports()[1].msg:find("^N|h|1429|5100|5000|h|"), reports()[1].msg)
	C_Minimap = { GetViewRadius = function() return 140 end }  -- 280 yards across
	hoverMinimap("Silverleaf", 35, 0)       -- 70 yards east
	advance(2)
	assert(reports()[2].msg:find("^N|h|1429|5233|5000|h|"), reports()[2].msg)
end)

test("unknown tooltip text, instances and missing positions report nothing", function()
	asFollower()
	hoverMinimap("Hogger", 30, 0)
	W.instance = true
	hoverMinimap("Peacebloom", 30, 0)
	W.instance = false
	W.map = nil
	hoverMinimap("Silverleaf", 30, 0)
	advance(3)
	eq(#reports(), 0, "nothing")
end)

test("several names in one tooltip, sent one per second, the same one only once a minute", function()
	asFollower()
	hoverMinimap("|TInterface\\x:0|tPeacebloom\nSilverleaf", 30, 0)
	hoverMinimap("Peacebloom", 30, 0)
	advance(0.5)
	eq(#reports(), 1, "first at once")
	advance(1)
	eq(#reports(), 2, "second a second later, no repeat")
	advance(5)
	eq(#reports(), 2, "still no repeat")
end)

test("gathering reports and learns the node only when that exact cast succeeds", function()
	asFollower()
	gather("Cast-1", "Strange Herb", 2366, false)  -- failed
	fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", 2366)  -- a success with another GUID
	advance(2)
	eq(#reports(), 0, "nothing from a failed or unmatched cast")
	gather("Cast-3", "Strange Herb")
	advance(2)
	eq(reports()[1].msg, "N|h|1429|5000|5000|g|" .. GetServerTime() - 2 .. "|Strange Herb", "gathered here")
	eq(HB.db.nodeNames["Strange Herb"], "h", "learned")
	hoverMinimap("Strange Herb", 0, 30)
	advance(2)
	eq(#reports(), 2, "learned name now counts on hover")
end)

test("a new cast replaces a pending one", function()
	asFollower()
	fire("UNIT_SPELLCAST_SENT", "player", "Peacebloom", "Cast-1", 2366)
	fire("UNIT_SPELLCAST_SENT", "player", "Mob", "Cast-2", 133)
	fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 2366)
	advance(2)
	eq(#reports(), 0, "old cast no longer pending")
end)

test("sharing off stops at once, also for queued reports", function()
	asFollower()
	hoverMinimap("Peacebloom\nSilverleaf\nEarthroot", 30, 0)
	advance(0.1)
	eq(#reports(), 1, "first sent")
	HB.SetOption("nodeShare", false)
	advance(5)
	eq(#reports(), 1, "nothing more")
	hoverMinimap("Briarthorn", 30, 0)
	advance(2)
	eq(#reports(), 1, "nothing new")
end)

test("queued reports go to whoever leads when they are sent", function()
	asFollower()
	hoverMinimap("Peacebloom\nSilverleaf", 30, 0)
	advance(0.1)
	HaploBoxTeam.leader = "Nyra"
	advance(2)
	local r = reports()
	eq(#r, 2, "both")
	eq(r[1].target, "Haplo", "first to the old leader")
	eq(r[2].target, "Nyra", "second to the new one")
end)

test("no reports solo, in a raid, or on the leader", function()
	asFollower()
	W.raid = true
	hoverMinimap("Peacebloom", 30, 0)
	W.raid = false
	W.units = {}
	hoverMinimap("Peacebloom", 30, 0)
	advance(2)
	eq(#reports(), 0, "none")
	W.me = "Haplo"
	asLeader()
	hoverMinimap("Peacebloom", 30, 0)
	advance(2)
	eq(#reports(), 0, "leader sends none")
end)

test("the leader shows a marker where it was seen, by whom and how long ago", function()
	asLeader()
	addon("Elya", N("h", 5333, 5000, "h", 120, "Peacebloom"), "WHISPER")
	local pins = HB.NodePinsShown()
	eq(#pins, 1, "one pin")
	local pt = pins[1].point
	assert(math.abs(pt[4] - 30) < 0.1, "30 px east, got " .. tostring(pt[4]))
	assert(math.abs(pt[5]) < 1e-6, "same height")
	HB.NodePinTooltip(pins[1])
	eq(GameTooltip.text, "Peacebloom", "name")
	local last = GameTooltip.lines[#GameTooltip.lines]
	assert(last:find("seen by Elya 2 min ago, may be gone"), last)
end)

test("reports are checked: format, age, future, sender, leader, channel", function()
	asLeader()
	addon("Elya", N("h", 5333, 5000, "h", 11 * 60, "Peacebloom"), "WHISPER")  -- older than 10 min
	addon("Elya", N("h", 5333, 5000, "h", -120, "Peacebloom"), "WHISPER")    -- 2 min in the future
	addon("Elya", N("h", 5333, 5000, "h", 0, "Peace\nbloom"), "WHISPER")
	addon("Elya", N("x", 5333, 5000, "h", 0, "Peacebloom"), "WHISPER")
	addon("Elya", N("h", 20000, 5000, "h", 0, "Peacebloom"), "WHISPER")
	addon("Mallory", N("h", 5333, 5000, "h", 0, "Peacebloom"), "WHISPER")
	addon("Elya", N("h", 5333, 5000, "h", 0, "Peacebloom"), "PARTY")
	eq(#HB.NodeMarkers(), 0, "all refused")
	W.me = "Nyra"
	asFollower()
	addon("Elya", N("h", 5333, 5000, "h", 0, "Peacebloom"), "WHISPER")
	eq(#HB.NodeMarkers(), 0, "a follower keeps none")
end)

test("nearby reports merge; gathering removes the marker; an older hover cannot bring it back", function()
	asLeader()
	addon("Elya", N("h", 5333, 5000, "h", 300, "Peacebloom"), "WHISPER")
	addon("Nyra", N("h", 5340, 5005, "h", 60, "Peacebloom"), "WHISPER")
	eq(#HB.NodeMarkers(), 1, "merged")
	eq(HB.NodeMarkers()[1].by, "Nyra", "newest sighting kept")
	addon("Nyra", N("h", 5335, 5000, "g", 30, "Peacebloom"), "WHISPER")
	eq(#HB.NodeMarkers(), 0, "gathered")
	addon("Elya", N("h", 5333, 5000, "h", 200, "Peacebloom"), "WHISPER")  -- seen before the gather, arrived late
	eq(#HB.NodeMarkers(), 0, "not brought back")
	addon("Elya", N("h", 5333, 5000, "h", 0, "Peacebloom"), "WHISPER")    -- seen after the gather
	eq(#HB.NodeMarkers(), 1, "seen again after it")
end)

test("markers expire, herbs and ore can be hidden, and only this map shows", function()
	asLeader()
	addon("Elya", N("h", 5333, 5000, "h", 0, "Peacebloom"), "WHISPER")
	addon("Elya", N("o", 4667, 5000, "h", 0, "Copper Vein"), "WHISPER")
	eq(#HB.NodePinsShown(), 2, "both")
	HB.SetOption("nodeOre", false)
	eq(#HB.NodePinsShown(), 1, "ore hidden")
	W.map.id = 1430
	HB.RefreshNodePins()
	eq(#HB.NodePinsShown(), 0, "other map")
	W.map.id = MAP
	W.now = W.now + 11 * 60
	HB.RefreshNodePins()
	eq(#HB.NodeMarkers(), 0, "expired")
	eq(#HB.NodePinsShown(), 0, "no pins")
end)

test("a gather while markers are hidden still removes the marker", function()
	asLeader()
	addon("Elya", N("h", 5333, 5000, "h", 60, "Peacebloom"), "WHISPER")
	HB.SetOption("nodeShow", false)
	eq(#HB.NodePinsShown(), 0, "hidden")
	addon("Nyra", N("h", 5333, 5000, "g", 30, "Peacebloom"), "WHISPER")
	HB.SetOption("nodeShow", true)
	eq(#HB.NodeMarkers(), 0, "gathered while hidden")
	eq(#HB.NodePinsShown(), 0, "no pin")
end)

test("one refresh reads the map once, however many markers", function()
	asLeader()
	for i = 1, 50 do addon("Elya", N("h", 5000 + i * 40, 5000, "h", 0, "Peacebloom"), "WHISPER") end
	local calls, real = 0, C_Map.GetPlayerMapPosition
	C_Map.GetPlayerMapPosition = function(...) calls = calls + 1 return real(...) end
	HB.RefreshNodePins()
	C_Map.GetPlayerMapPosition = real
	eq(calls, 1, "one position read")
end)

test("a marker out of minimap range is not drawn", function()
	asLeader()
	addon("Elya", N("h", 6000, 5000, "h", 0, "Peacebloom"), "WHISPER")  -- 300 yards east
	eq(#HB.NodeMarkers(), 1, "kept")
	eq(#HB.NodePinsShown(), 0, "outside the minimap")
end)
