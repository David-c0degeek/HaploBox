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

test("debug traces a report end to end; sent only once the game took it", function()
	asFollower({ debug = true })
	W.sendResults = { 3, 3 }  -- the whisper is held back in Core's queue first
	hoverMinimap("Earthroot", 30, 0, "UIParent")
	advance(0.1)
	eq(printedMatching("node: queued Earthroot at 0%.533, 0%.500 %(map 1429%)"), 1, "queued")
	eq(printedMatching("node: sent Earthroot"), 0, "not sent while throttled")
	advance(5)
	eq(printedMatching("node: sent Earthroot to Haplo"), 1, "sent once the game took it")
	hoverMinimap("Earthroot", 30, 0, "UIParent")
	eq(printedMatching("already queued within a minute"), 1, "repeat said")
end)

test("a failing send is reported as failed, not as sent", function()
	asFollower({ debug = true })
	W.sendResults = { 3, 3, 3, 3, 3, 3 }
	hoverMinimap("Earthroot", 30, 0, "UIParent")
	advance(10)
	eq(printedMatching("node: sending Earthroot to Haplo failed"), 1, "failed")
	eq(printedMatching("node: sent "), 0, "never claimed sent")
	hoverMinimap("Earthroot", 30, 0, "UIParent")
	eq(printedMatching("already queued within a minute"), 1, "the repeat does not claim a send")
	eq(printedMatching("already sent"), 0, "no false sent")
end)

test("an error in the hover code shows under debug instead of vanishing", function()
	asFollower({ debug = true })
	local real = C_Map.GetBestMapForUnit
	C_Map.GetBestMapForUnit = function() error("boom") end
	hoverMinimap("Earthroot", 30, 0, "UIParent")
	C_Map.GetBestMapForUnit = real
	eq(printedMatching("minimap hover: error .*boom"), 1, "error shown")
	eq(printedMatching("node: queued"), 0, "nothing claimed")
end)

test("the leader says what it did with each report", function()
	asLeader({ debug = true })
	addon("Elya", N("h", 5333, 5000, "h", 0, "Peacebloom"), "WHISPER")
	eq(printedMatching("node: Peacebloom from Elya stored %(1 markers%)"), 1, "stored")
	addon("Elya", N("h", 5333, 5000, "h", 11 * 60, "Peacebloom"), "WHISPER")
	eq(printedMatching("too old or in the future %(age 660 s%)"), 1, "age given")
	addon("Nyra", N("h", 5333, 5000, "g", 0, "Peacebloom"), "WHISPER")
	eq(printedMatching("node: Peacebloom gathered by Nyra"), 1, "gather")
	party("Nyra")
	addon("Elya", N("h", 5333, 5000, "h", 0, "Peacebloom"), "WHISPER")
	eq(printedMatching("ignored: not in my group"), 1, "not in group")
end)

test("with debug off the trace prints nothing", function()
	asFollower()
	hoverMinimap("Earthroot", 30, 0, "UIParent")
	advance(2)
	eq(printedMatching("node:"), 0, "silent")
end)

-- the shown tooltip's text changes without OnShow or SetText (as on WoW Forever)
local function nativeHover(text, px, py, seconds)
	local s = W.minimapScale or 1
	W.cursorX, W.cursorY = (Minimap.cx + px) * s, (Minimap.cy + py) * s
	GameTooltip.owner = UIParent
	GameTooltipTextLeft1.text = text
	local runs = 0
	for _ = 1, math.floor((seconds or 0.3) / 0.02) do
		advance(0.02)
		for _, fn in ipairs((GameTooltip.hooks or {}).OnUpdate or {}) do fn(GameTooltip, 0.02) runs = runs + 1 end
	end
	return runs
end

test("a minimap tooltip whose text changes natively is read while shown", function()
	asFollower()
	GetMouseFoci = function() return { Minimap } end
	nativeHover("Peacebloom", 30, 0)
	advance(2)
	eq(#reports(), 1, "reported without OnShow or SetText")
	assert(reports()[1].msg:find("|Peacebloom$"), reports()[1].msg)
end)

test("a node hovered in the world is reported where the player stands; other frames do not count", function()
	asFollower({ debug = true })
	where(0.4, 0.6)
	GetMouseFoci = function() return { WorldFrame } end
	hoverMinimap("Earthroot", 300, -200, "UIParent")   -- far from the minimap: the world
	GetMouseFoci = function() return {} end              -- nothing under the mouse: the world too
	hoverMinimap("Silverleaf", 500, 0, "UIParent")
	advance(3)
	local r = reports()
	eq(#r, 2, "both")
	assert(r[1].msg:find("^N|h|" .. MAP .. "|4000|6000|w|%d+|Earthroot$"), r[1].msg)
	assert(r[2].msg:find("|w|%d+|Silverleaf$"), r[2].msg)
	local bag = CreateFrame("Frame", "ContainerFrame1")
	GetMouseFoci = function() return { bag } end
	hoverMinimap("Peacebloom", 30, 0, "UIParent")
	advance(2)
	eq(#reports(), 2, "another frame: nothing")
	eq(printedMatching("over another frame %(ContainerFrame1%) %(Peacebloom%)"), 1, "other frame said")
	local pin = CreateFrame("Frame", nil, Minimap)  -- a pin on the minimap counts as the minimap
	GetMouseFoci = function() return { pin } end
	hoverMinimap("Peacebloom", 30, 0, "UIParent")
	advance(2)
	eq(#reports(), 3, "pin on the minimap")
	assert(reports()[3].msg:find("|h|%d+|Peacebloom$"), "an exact minimap sighting")
end)

test("walking while hovering one node in the world leaves no trail", function()
	asFollower({ debug = true })
	GetMouseFoci = function() return { WorldFrame } end
	for step = 0, 20 do
		where(0.5 + step * 0.002, 0.5)   -- farther than the leader's merge distance each few steps
		nativeHover("Earthroot", 0, 0, 1)
	end
	advance(3)
	eq(#reports(), 1, "one report within 30 seconds")
	assert(printedMatching("hovered in the world again within 30 seconds") >= 1, "said")
	advance(10)
	where(0.6, 0.5)
	nativeHover("Earthroot", 0, 0, 1.5)
	advance(3)
	eq(#reports(), 2, "again after the cooldown")
end)

test("a secret tooltip is never read; on the minimap debug says so", function()
	asFollower({ debug = true })
	local secretText = "Peacebloom"
	W.secrets = { [secretText] = true }
	GetMouseFoci = function() return { Minimap } end
	hoverMinimap(secretText, 30, 0, "UIParent")
	GetMouseFoci = function() return { WorldFrame } end
	hoverMinimap(secretText, 300, 0, "UIParent")
	nativeHover(secretText, 30, 0, 1)
	advance(3)
	eq(#reports(), 0, "nothing")
	eq(printedMatching("minimap tooltip is secret on this client"), 1, "said once, for the minimap only")
end)

test("the leader marks world sightings as near, until an exact one merges in", function()
	asLeader()
	addon("Elya", N("h", 5000, 5000, "w", 0, "Earthroot"), "WHISPER")
	local m = HB.NodeMarkers()[1]
	eq(m.src, "w", "approximate")
	addon("Nyra", N("h", 5010, 5000, "h", 0, "Earthroot"), "WHISPER")
	eq(#HB.NodeMarkers(), 1, "merged")
	eq(HB.NodeMarkers()[1].src, "h", "exact now")
	addon("Elya", N("h", 5005, 5000, "w", 0, "Earthroot"), "WHISPER")
	eq(HB.NodeMarkers()[1].src, "h", "stays exact")
end)

test("a missing, failing or odd focus API falls back to the minimap circle", function()
	asFollower()
	GetMouseFoci = function() error("nope") end
	GetMouseFocus = nil
	hoverMinimap("Earthroot", 30, 0, "UIParent")
	GetMouseFoci = function() return "odd" end
	GetMouseFocus = function() return Minimap end  -- the legacy API is used instead
	hoverMinimap("Silverleaf", 0, 30, "UIParent")
	GetMouseFoci, GetMouseFocus = nil, nil
	hoverMinimap("Peacebloom", 0, -30, "UIParent")
	hoverMinimap("Copper Vein", 200, 0, "UIParent")  -- outside the circle: still not
	advance(4)
	eq(#reports(), 3, "three inside the circle")
end)

test("the same tooltip becomes valid when the mouse moves onto the minimap; reading is throttled", function()
	asFollower()
	local bag = CreateFrame("Frame", "ContainerFrame1")
	GetMouseFoci = function() return { bag } end
	local runs = nativeHover("Earthroot", 30, 0, 2)
	advance(1)
	eq(#reports(), 0, "another frame: nothing")
	GetMouseFoci = function() return { Minimap } end
	nativeHover("Earthroot", 30, 0, 1.5)
	advance(2)
	eq(#reports(), 1, "on the minimap within a second or so")
	assert(runs >= 90, "OnUpdate ran every frame")
	nativeHover("Earthroot", 30, 0, 10)
	advance(2)
	eq(#reports(), 1, "no repeat report within a minute")
end)

-- a secret value that fails on any use except identity: never read, joined or keyed
local function opaqueSecret()
	local p = setmetatable({}, {
		__index = function() error("secret indexed") end,
		__tostring = function() error("secret turned into text") end,
		__concat = function() error("secret joined") end,
		__eq = function() error("secret compared") end,
		__len = function() error("secret measured") end,
		__call = function() error("secret called") end,
	})
	W.secrets = { [p] = true }
	return p
end

test("unknown minimap icons: off by default; on, a secret minimap tooltip sends only \"?\" and the spot", function()
	asFollower({ debug = true })
	local s = opaqueSecret()
	GetMouseFoci = function() return { Minimap } end
	hoverMinimap(s, 30, 0, "UIParent")
	advance(2)
	eq(#reports(), 0, "off by default")
	eq(printedMatching("minimap tooltip is secret on this client"), 1, "the hint as before")
	asFollower({ debug = true, nodeUnknown = true })
	s = opaqueSecret()
	GetMouseFoci = function() return { Minimap } end
	hoverMinimap(s, 30, 0, "UIParent")
	nativeHover(s, 30, 0, 1)
	advance(2)
	local r = reports()
	eq(#r, 1, "one report, also with the tooltip read again natively")
	eq(r[1].msg, "N|u|1429|5333|5000|h|" .. GetServerTime() - 2 .. "|?", "kind u, the hovered spot, name ?")
	eq(printedMatching("error"), 0, "the secret was never used")
	eq(printedMatching("unknown minimap icon reported"), 1, "debug says so")
end)

test("unknown minimap icons: the world, no focus API, outside the circle or not sharing send nothing", function()
	asFollower({ nodeUnknown = true })
	local s = opaqueSecret()
	GetMouseFoci = function() return { WorldFrame } end
	hoverMinimap(s, 30, 0, "UIParent")
	GetMouseFoci, GetMouseFocus = nil, nil
	hoverMinimap(s, 0, 30, "UIParent")
	GetMouseFoci = function() return { Minimap } end
	hoverMinimap(s, 200, 0, "UIParent")
	HB.db.nodeShare = false
	hoverMinimap(s, 0, -30, "UIParent")
	advance(4)
	eq(#reports(), 0, "nothing")
	eq(printedMatching("error"), 0, "no error")
end)

test("the leader checks unknown reports and shows them as ?", function()
	asLeader()
	where(0.48, 0.5)  -- 60 yards from the markers: arriving would clear a ?
	for _, bad in ipairs({ N("u", 5000, 5000, "h", 0, "Peacebloom"), N("h", 5000, 5000, "h", 0, "?"),
		N("u", 5000, 5000, "g", 0, "?"), N("u", 5000, 5000, "w", 0, "?") }) do
		addon("Elya", bad, "WHISPER")
	end
	eq(#HB.NodeMarkers(), 0, "named unknowns, ? as a name, unknown gathers and world unknowns refused")
	addon("Elya", N("u", 5000, 5000, "h", 0, "?"), "WHISPER")
	addon("Nyra", N("u", 5005, 5000, "h", 0, "?"), "WHISPER")
	eq(#HB.NodeMarkers(), 1, "stored, nearby merged")
	local m = HB.NodeMarkers()[1]
	eq(m.kind, "u", "kind")
	eq(m.name, "?", "name")
	HB.SetOption("nodeHerbs", false)
	HB.SetOption("nodeOre", false)
	eq(#HB.NodePinsShown(), 1, "shown although herbs and ore are hidden")
	eq(HB.NodePinsShown()[1].icon.texture, "Interface\\Icons\\INV_Misc_QuestionMark", "a question mark")
	HB.SetOption("nodeUnknownShow", false)
	eq(#HB.NodePinsShown(), 0, "hidden on its own")
end)

test("a named sighting replaces an unknown one; an unknown never downgrades a named one", function()
	asLeader()
	where(0.48, 0.5)  -- 60 yards from the markers: arriving would clear a ?
	addon("Elya", N("u", 5000, 5000, "h", 0, "?"), "WHISPER")
	addon("Nyra", N("h", 5005, 5000, "w", 0, "Earthroot"), "WHISPER")
	eq(#HB.NodeMarkers(), 1, "one marker")
	eq(HB.NodeMarkers()[1].name, "Earthroot", "named now")
	addon("Elya", N("u", 5003, 5000, "h", 0, "?"), "WHISPER")
	eq(#HB.NodeMarkers(), 1, "no ? added beside it")
	eq(HB.NodeMarkers()[1].kind, "h", "still a herb")
end)

test("a gather removes an unknown marker, and an older unknown cannot bring it back", function()
	asLeader()
	where(0.48, 0.5)  -- 60 yards from the markers: arriving would clear a ?
	addon("Elya", N("u", 5000, 5000, "h", 30, "?"), "WHISPER")
	addon("Nyra", N("h", 5005, 5000, "g", 10, "Earthroot"), "WHISPER")
	eq(#HB.NodeMarkers(), 0, "gathered")
	addon("Elya", N("u", 5002, 5000, "h", 20, "?"), "WHISPER")
	eq(#HB.NodeMarkers(), 0, "an unknown seen before the gather stays gone")
	addon("Elya", N("u", 5002, 5000, "h", 0, "?"), "WHISPER")
	eq(#HB.NodeMarkers(), 1, "a newer one shows (the node may have come back)")
end)

test("unknown icons need the visible round minimap also when the minimap owns the tooltip", function()
	asFollower({ nodeUnknown = true })
	local s = opaqueSecret()
	GetMouseFoci, GetMouseFocus = nil, nil
	hoverMinimap(s, 200, 0)             -- owner Minimap, far outside
	hoverMinimap(s, 60, 60)             -- owner Minimap, a corner of the frame
	Minimap.shown = false
	hoverMinimap(s, 10, 0)              -- owner Minimap, hidden
	Minimap.shown = true
	advance(4)
	eq(#reports(), 0, "nothing")
	hoverMinimap(s, 10, 0)              -- owner Minimap, inside: counts even without a focus API
	advance(2)
	eq(#reports(), 1, "inside")
end)

test("a rejected old named sighting leaves a newer unknown marker alone", function()
	asLeader()
	where(0.48, 0.5)  -- 60 yards from the markers: arriving would clear a ?
	addon("Nyra", N("h", 5000, 5000, "g", 50, "Earthroot"), "WHISPER")
	addon("Elya", N("u", 5003, 5000, "h", 40, "?"), "WHISPER")
	eq(#HB.NodeMarkers(), 1, "newer ? shows")
	addon("Elya", N("h", 5002, 5000, "h", 55, "Earthroot"), "WHISPER")
	eq(#HB.NodeMarkers(), 1, "old named report rejected, ? kept")
	eq(HB.NodeMarkers()[1].kind, "u", "still ?")
end)

test("a follower sends at most one ? every 15 seconds", function()
	asFollower({ nodeUnknown = true, debug = true })
	local s = opaqueSecret()
	GetMouseFoci = function() return { Minimap } end
	hoverMinimap(s, 30, 0, "UIParent")
	advance(5)
	hoverMinimap(s, 0, 30, "UIParent")
	advance(9.9)
	hoverMinimap(s, -30, 0, "UIParent")
	advance(2)
	eq(#reports(), 1, "one within 15 seconds")
	eq(printedMatching("another %? within 15 seconds"), 2, "said why")
	hoverMinimap(s, 0, -30, "UIParent")
	advance(2)
	eq(#reports(), 2, "allowed again after 15 seconds")
end)

test("? markers: 2 minutes, merged when close, at most 3, named markers keep 10 minutes", function()
	asLeader()
	where(0.48, 0.5)
	addon("Elya", N("u", 5000, 5000, "h", 0, "?"), "WHISPER")
	addon("Nyra", N("u", 5100, 5000, "h", 0, "?"), "WHISPER")
	eq(#HB.NodeMarkers(), 1, "close ? merge")
	addon("Elya", N("h", 5000, 6000, "h", 0, "Peacebloom"), "WHISPER")
	W.now = W.now + 121
	HB.RefreshNodePins()
	eq(#HB.NodeMarkers(), 1, "? gone after 2 minutes")
	eq(HB.NodeMarkers()[1].name, "Peacebloom", "the herb stays")
	addon("Elya", N("u", 5000, 5000, "h", 130, "?"), "WHISPER")
	eq(#HB.NodeMarkers(), 1, "a ? older than 2 minutes is refused")
	HB.ClearNodeMarkers()
	for i, ago in ipairs({ 40, 30, 20, 10 }) do
		addon("Elya", N("u", 5000, 5000 + i * 300, "h", ago, "?"), "WHISPER")
	end
	eq(#HB.NodeMarkers(), 3, "at most 3")
	for _, m in ipairs(HB.NodeMarkers()) do assert(GetServerTime() - m.t <= 30, "the newest stay") end
end)

test("the leader arriving within 25 yards clears a ?, not a named marker", function()
	asLeader()
	where(0.4, 0.5)
	addon("Elya", N("u", 5090, 5000, "h", 0, "?"), "WHISPER")
	addon("Elya", N("h", 5000, 5300, "h", 0, "Peacebloom"), "WHISPER")  -- far enough not to replace the ?
	where(0.5, 0.5)            -- 27 yards from the ?
	HB.RefreshNodePins()
	eq(#HB.NodeMarkers(), 2, "27 yards: still there")
	where(0.502, 0.5)          -- 21 yards
	HB.RefreshNodePins()
	eq(#HB.NodeMarkers(), 1, "arrived: ? gone")
	eq(HB.NodeMarkers()[1].name, "Peacebloom", "the herb stays")
	HB.SetOption("nodeShow", false)
	addon("Elya", N("u", 5030, 5000, "h", 0, "?"), "WHISPER")
	HB.RefreshNodePins()
	eq(#HB.NodeMarkers(), 1, "also while markers are hidden")
end)
