-- Test registration and shared setup. Loaded after the addon, before a test file.
TEST_NAMES, TEST_FNS = {}, {}
function reloadAddonFile(name)
	local f = assert(loadstring(ADDON_SOURCE[name], "@" .. name))
	f("HaploBox")
end

function test(name, fn)
	TEST_NAMES[#TEST_NAMES + 1] = name
	TEST_FNS[#TEST_FNS + 1] = fn
end

function eq(actual, expected, what)
	if actual ~= expected then
		error((what or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
	end
end

HB = HaploBox

-- Loads the saved variables and logs in, as the game does.
function login(db, team)
	HaploBoxDB, HaploBoxTeam = db, team
	fire("ADDON_LOADED", "HaploBox")
	fire("PLAYER_LOGIN")
	advance(5)
	W.sent, W.printed = {}, {}
end

-- A party of the leader Haplo (this toon unless W.me says otherwise) and followers.
function party(...)
	W.units = {}
	for i, name in ipairs({ ... }) do W.units["party" .. i] = name end
end

function standardTeam(leader)
	return {
		leader = leader or "Haplo",
		order = { "Haplo", "Elya", "Nyra" },
		roles = { Haplo = "tank", Elya = "healer", Nyra = "dps" },
	}
end

-- an addon message from another toon
function addon(sender, msg, channel)
	fire("CHAT_MSG_ADDON", "HaploBox", msg, channel or "PARTY", sender)
end
