-- Ammo: each toon reports ammo left as the eighth stats field; the leader shows it
-- on the team frame and says when a toon runs low or out.

-- W.ranged: item id in the ranged slot; W.ammoItem / W.ammoCount: the ammo slot
local SUBCLASS = { [100] = 2, [101] = 3, [102] = 18, [103] = 19 }  -- bow, gun, crossbow, wand
function GetInventorySlotInfo(name)
	return ({ AmmoSlot = 0, RangedSlot = 18 })[name]
end
function GetInventoryItemID(_, slot)
	if slot == 0 then return W.ammoItem end
	if slot == 18 then return W.ranged end
end
function GetInventoryItemCount(_, slot)
	if slot == 0 then return W.ammoItem and W.ammoCount or 1 end  -- the game returns 1 for an empty slot
	return 0
end
function GetItemInfoInstant(id)
	if W.noItemInfo then return nil end
	local sub = SUBCLASS[id]
	if not sub then return nil end
	return id, "Weapon", "x", "INVTYPE_RANGED", 1, 2, sub
end

local function asElya(...)
	W.me = "Elya"
	party(...)
	login({}, standardTeam("Haplo"))
end
local function lastStats()
	local s = sentMatching("^S|")
	return s[#s] and s[#s].msg
end
local function ammoField() return (lastStats() or ""):match("|([^|]*)$") end
local function statsNow()
	addon("Haplo", "F|?")
	advance(1.5)
end

test("a hunter reports the ammo it has; a toon without ammo sends an empty field", function()
	W.ranged, W.ammoItem, W.ammoCount = 100, 2512, 840
	asElya("Haplo", "Nyra")
	statsNow()
	eq(ammoField(), "840", "arrows")
	W.ammoItem = nil
	W.sent = {}
	statsNow()
	eq(ammoField(), "0", "bow with nothing in the ammo slot")
	W.ranged = 103
	W.sent = {}
	statsNow()
	eq(ammoField(), "", "wand: no ammo")
	W.ranged = nil
	W.sent = {}
	statsNow()
	eq(ammoField(), "", "no ranged weapon")
	W.ranged, W.noItemInfo = 101, true
	fire("UNIT_INVENTORY_CHANGED", "player")
	advance(1.5)
	eq(HB.stats.elya.ammo, nil, "unknown weapon type stays unknown, not 0")
	W.noItemInfo = nil
	W.sent = {}
	fire("GET_ITEM_INFO_RECEIVED", 101, true)
	advance(1.5)
	eq(HB.stats.elya.ammo, 0, "known once the item data arrives")
	eq(ammoField(), "0", "and sent")
end)

test("ammo alone goes out at most every 5 seconds, the last count follows, and out goes at once", function()
	W.ranged, W.ammoItem, W.ammoCount = 101, 2519, 500
	asElya("Haplo", "Nyra")
	fire("BAG_UPDATE", 1)
	advance(1.5)
	W.sent = {}
	for n = 499, 496, -1 do
		W.ammoCount = n
		fire("BAG_UPDATE", 1)
		advance(1)
	end
	eq(#sentMatching("^S|"), 0, "held while within 5 seconds")
	advance(2)
	eq(#sentMatching("^S|"), 1, "trailing send")
	eq(ammoField(), "496", "the last count")
	W.sent = {}
	W.ammoCount = 495
	fire("BAG_UPDATE", 1)
	advance(1.5)
	eq(#sentMatching("^S|"), 0, "held again")
	W.ammoItem = nil
	fire("UNIT_INVENTORY_CHANGED", "player")
	advance(1.5)
	eq(#sentMatching("^S|"), 1, "out goes at once")
	eq(ammoField(), "0", "zero")
	W.sent = {}
	fire("UNIT_INVENTORY_CHANGED", "party1")
	advance(10)
	eq(#sentMatching("^S|"), 0, "another unit's inventory sends nothing")
end)

test("another stat still goes out within a second while ammo waits", function()
	W.ranged, W.ammoItem, W.ammoCount = 101, 2519, 500
	asElya("Haplo", "Nyra")
	fire("BAG_UPDATE", 1)
	advance(1.5)
	W.sent = {}
	GetMoney = function() return 99999 end
	W.ammoCount = 499
	fire("PLAYER_MONEY")
	advance(1.5)
	eq(#sentMatching("^S|"), 1, "money change not held")
	eq(ammoField(), "499", "carries the new count too")
end)

test("the leader is told once when ammo runs low and once when out, and again after a refill", function()
	party("Elya", "Nyra")
	login({}, standardTeam("Haplo"))
	addon("Elya", "S|10|5|20|0|100|8|16|500")
	addon("Elya", "S|10|5|20|0|100|8|16|190")
	eq(printedMatching("Elya: ammo low %(190%)"), 1, "low")
	addon("Elya", "S|10|5|20|0|100|8|16|150")
	eq(printedMatching("ammo low"), 1, "said once")
	addon("Elya", "S|10|5|20|0|100|8|16|0")
	eq(printedMatching("Elya: out of ammo"), 1, "out")
	addon("Elya", "S|10|5|20|0|100|8|16|1000")
	addon("Elya", "S|10|5|20|0|100|8|16|200")
	eq(printedMatching("ammo low"), 2, "re-armed by the refill")
	HB.SetOption("ammoLow", "400")
	addon("Elya", "S|10|5|20|0|100|8|16|1000")
	addon("Elya", "S|10|5|20|0|100|8|16|390")
	eq(printedMatching("ammo low %(390%)"), 1, "own threshold")
	eq(HB.SetOption("ammoLow", "250"), nil, "only the listed thresholds")
end)

test("older stats without ammo, an empty field, or the alert off say nothing", function()
	party("Elya", "Nyra")
	login({}, standardTeam("Haplo"))
	addon("Elya", "S|10|5|20|0|100|8|16")
	addon("Elya", "S|10|5|20|0|100|8|16|0")
	eq(printedMatching("ammo"), 0, "no earlier count: no alert")
	eq(HB.stats.elya.ammo, 0, "taken")
	addon("Nyra", "S|10|5|20|0|100|8|16|500")
	addon("Nyra", "S|10|5|20|0|100|8|16|")
	eq(HB.stats.nyra.ammo, nil, "empty field: unknown")
	addon("Nyra", "S|10|5|20|0|100|8|16|0")
	eq(printedMatching("ammo"), 0, "unknown in between: no alert")
	HB.SetOption("ammoAlert", false)
	addon("Nyra", "S|10|5|20|0|100|8|16|500")
	addon("Nyra", "S|10|5|20|0|100|8|16|10")
	eq(printedMatching("ammo"), 0, "alert off")
end)

test("a follower is never told", function()
	asElya("Haplo", "Nyra")
	addon("Nyra", "S|10|5|20|0|100|8|16|500")
	addon("Nyra", "S|10|5|20|0|100|8|16|0")
	eq(printedMatching("ammo"), 0, "follower: nothing")
end)

test("the team frame shows ammo after the bag slots, only for toons that report it", function()
	party("Elya", "Nyra")
	login({}, standardTeam("Haplo"))
	addon("Elya", "S|10|5|20|0|100|8|16|840")
	addon("Nyra", "S|10|5|20|0|100|8|16")
	local elya, nyra
	for i = 1, 3 do
		local r = _G["HaploBoxPartyRow" .. i]
		if r and r.name == "Elya" then elya = r elseif r and r.name == "Nyra" then nyra = r end
	end
	assert(elya and nyra, "rows")
	assert(elya.bagText.text:find("840"), "Elya's ammo shown: " .. tostring(elya.bagText.text))
	eq(elya.ammoShown, true, "takes room from the buffs")
	assert(not nyra.bagText.text:find("INV_Ammo"), "Nyra has none")
	addon("Elya", "S|10|5|20|0|100|8|16|0")
	assert(elya.bagText.text:find("|cffff55440|r", 1, true), "red when out")
	HB.SetOption("teamShowBags", false)
	addon("Elya", "S|10|5|20|0|100|8|16|840")
	eq(elya.bagText:IsShown(), true, "ammo shown with the bags hidden")
	assert(elya.bagText.text:find("840") and not elya.bagText.text:find("|cffdddddd8|r", 1, true), "ammo only: " .. elya.bagText.text)
	eq(elya.bagIcon:IsShown(), false, "no bag icon")
	HB.SetOption("teamShowBags", true)
	HB.SetOption("teamShowAmmo", false)
	HB.OnStatsChanged("elya")
	assert(not elya.bagText.text:find("INV_Ammo"), "hidden when turned off")
	eq(elya.ammoShown, false, "room back")
end)
