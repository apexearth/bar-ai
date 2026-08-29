--------------------------------------------------------------------------------
-- dev_arena.lua -- hand both AIs an identical army and see which one fights
-- better with it.
--
-- A normal match measures fighting logic through the economy that paid for the
-- army, the build order that chose its composition and the map position it
-- arrived at. Those dominate: a side that out-produces its opponent wins the
-- fight regardless of how it micros. This gadget removes all of that. Both
-- sides get the SAME units, the SAME count, at MIRRORED positions, and the only
-- variable left is what each AI does with them.
--
-- Rounds repeat inside one match, so a five-minute run yields ~15 independent
-- samples instead of one. Sides swap positions on alternate rounds, so terrain
-- advantage at either spawn cancels out across a pair.
--
-- Installed by tools/deploy_ai.py into BAR.sdd/luarules/gadgets/. Inert unless
-- the start script sets dev_arena, so it cannot affect a normal game.
--
--   dev_arena         "1" to enable
--   dev_arena_def     unit def, or a mixed list "armrock*8,armham*6"
--                     (default armpw; bare names use dev_arena_count)
--   dev_arena_def_b   override for ally 1 only; blank = same as dev_arena_def
--   dev_arena_count   units per side per round          (default 8)
--   dev_arena_start   first spawn frame                 (default 900)
--   dev_arena_round   max frames per round              (default 1800)
--   dev_arena_gap     frames between rounds             (default 150)
--   dev_arena_sep     elmos between the two lines       (default 700)
--   dev_arena_pure    "1": park the commanders in the corners, paralyzed and
--                     neutral -- no economy, no building, ONLY the arena
--                     armies act. The game cannot end (they stay alive).
--
-- Output, one line per round, parsed by tools/arena.py:
--   [BARAI_ARENA] round=N ally=A team=T def=D n=K x=.. z=..
--   [BARAI_ARENA_END] round=N frames=F winner=A alive0=.. alive1=..
--                     metal0=.. metal1=.. spawn0=.. spawn1=.. flip=0|1
--------------------------------------------------------------------------------

local modOptions = Spring.GetModOptions() or {}
local enabled = tostring(modOptions.dev_arena or "") == "1"

function gadget:GetInfo()
	return {
		name    = "Dev Arena",
		desc    = "Mirrored equal-army fights for AI combat benchmarking.",
		author  = "bar-ai",
		date    = "2026",
		license = "GNU GPL, v2 or later",
		layer   = 1001,
		enabled = enabled,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return
end

local function opt(name, default)
	local v = modOptions[name]
	if v == nil or v == "" then
		return default
	end
	return v
end

local function optNum(name, default)
	return tonumber(opt(name, default)) or default
end

local DEF_A      = tostring(opt("dev_arena_def", "armpw"))
local DEF_B      = tostring(opt("dev_arena_def_b", ""))
if DEF_B == "" then DEF_B = DEF_A end
local COUNT      = math.floor(optNum("dev_arena_count", 8))
local START      = math.floor(optNum("dev_arena_start", 900))
local ROUND      = math.floor(optNum("dev_arena_round", 1800))
local GAP        = math.floor(optNum("dev_arena_gap", 150))
-- 500, was 700: "They need to start a little closer to each other so
-- they'll start fighting. Sometimes they just run away from each other."
local SEP        = optNum("dev_arena_sep", 500)
-- 0 none, 1 ally 0, 2 ally 1, 3 both. CircuitAI drops a unit carrying
-- disableAiControl from its own control, so the engine's default auto-fight is
-- all that remains. Setting 3 asks whether the two AIs' ORDERS explain the
-- measured gap at all: with neither side commanding, any residual edge must
-- come from the arena itself rather than from tactics.
local NOCTRL     = math.floor(optNum("dev_arena_nocontrol", 0))

-- Spacing between neighbours in a spawn line. Wide enough that the engine does
-- not have to shove overlapping units apart on the first frame, which would
-- scatter the formation before either AI issues an order.
local PITCH = 64

local mapX = Game.mapSizeX
local mapZ = Game.mapSizeZ

local defIDs = {}   -- ally -> unitDefID
local metalOf = {}  -- ally -> metal cost per unit

local spawned = { [0] = {}, [1] = {} }  -- ally -> { unitID = true }
local roundNo = 0
local dirty = false  -- an outsider joined this round; see UnitDestroyed
local roundStart = 0
local waitUntil = START
local active = false
local flip = false
local anchorA, anchorB  -- {x, z} spawn centres, before flip

-- PURE MODE (apexearth: "they still have commanders and are building stuff.
-- So not quite what I want"): every starting unit is teleported to its own
-- map corner, permanently paralyzed and set neutral -- alive so the game
-- cannot end, invisible to targeting, building nothing. The arena armies are
-- the only actors left.
local PURE       = tostring(opt("dev_arena_pure", "")) == "1"
local pureDone = false
local parked = {}   -- unitID -> true, re-stunned every second

local function parkStarters()
	for ally = 0, 1 do
		local corner = (ally == 0) and { 96, 96 }
				or { mapX - 96, mapZ - 96 }
		local teams = Spring.GetTeamList(ally) or {}
		for _, teamID in ipairs(teams) do
			for _, uID in ipairs(Spring.GetTeamUnits(teamID) or {}) do
				if not (spawned[0][uID] or spawned[1][uID]) then
					Spring.SetUnitPosition(uID, corner[1], corner[2])
					Spring.MoveCtrl.Enable(uID)
					Spring.MoveCtrl.SetPosition(uID, corner[1],
						Spring.GetGroundHeight(corner[1], corner[2]), corner[2])
					Spring.SetUnitNeutral(uID, true)
					parked[uID] = true
				end
			end
		end
	end
	pureDone = true
	Spring.Echo("[BARAI_ARENA] pure mode: starters parked and neutralized")
end

local function restun(frame)
	if frame % 30 ~= 7 then
		return
	end
	for uID in pairs(parked) do
		if Spring.ValidUnitID(uID) then
			local maxH = select(2, Spring.GetUnitHealth(uID)) or 1000
			Spring.SetUnitHealth(uID, { paralyze = maxH * 100 })
		else
			parked[uID] = nil
		end
	end
end

--------------------------------------------------------------------------------

local function resolveDef(name)
	local ud = UnitDefNames[name]
	if not ud then
		Spring.Echo("[BARAI_ARENA] ERROR unknown unit def '" .. tostring(name) .. "'")
		return nil
	end
	return ud.id, ud.metalCost
end

-- MIXED ARMIES (apexearth: "would be good if it is a variety of unit types
-- in the fights"). The def option accepts "armrock*8,armham*6,armwar*6";
-- a bare name keeps the old one-def behaviour at dev_arena_count. The line
-- spawns in the order given, so the spec controls the layout, mirrored on
-- both sides.
local rosterOf = {}   -- ally -> { {id, n, name}... }
local sideTotal = {}  -- ally -> units per spawn

local function parseRoster(spec)
	local roster, total, metal, minSight = {}, 0, 0, 1e9
	for part in tostring(spec):gmatch("[^,]+") do
		local name, cnt = part:match("^%s*([%w_]+)%s*%*%s*(%d+)%s*$")
		if not name then
			name = part:match("^%s*([%w_]+)%s*$")
			cnt = COUNT
		end
		if not name then
			return nil
		end
		local id, m = resolveDef(name)
		if not id then
			return nil
		end
		local los = UnitDefs[id].losRadius or 300
		if los < minSight then
			minSight = los
		end
		cnt = math.floor(tonumber(cnt) or COUNT)
		roster[#roster + 1] = { id = id, n = cnt, name = name }
		total = total + cnt
		metal = metal + m * cnt
	end
	if total == 0 then
		return nil
	end
	return roster, total, metal / total, minSight
end

-- The two spawn centres, offset from the map middle along the line joining the
-- start positions. Falls back to the map's long axis when start positions are
-- unavailable, which happens with some box configurations.
local function computeAnchors()
	local cx, cz = mapX / 2, mapZ / 2
	local dx, dz = 1, 0
	local p = {}
	for ally = 0, 1 do
		local teams = Spring.GetTeamList(ally)
		if teams and teams[1] then
			local x, _, z = Spring.GetTeamStartPosition(teams[1])
			if x and x > 0 then
				p[ally] = { x, z }
			end
		end
	end
	if p[0] and p[1] then
		dx, dz = p[1][1] - p[0][1], p[1][2] - p[0][2]
		local len = math.sqrt(dx * dx + dz * dz)
		if len > 1 then
			dx, dz = dx / len, dz / len
		else
			dx, dz = 1, 0
		end
	elseif mapZ > mapX then
		dx, dz = 0, 1
	end
	local h = SEP / 2
	anchorA = { cx - dx * h, cz - dz * h, -dz, dx }  -- x, z, and the perpendicular
	anchorB = { cx + dx * h, cz + dz * h, -dz, dx }
end

-- Nudge a spawn point off water or off the map edge. Units created underwater
-- would be a different fight entirely, and CreateUnit off-map silently fails.
local function landNear(x, z)
	local step = 128
	for r = 0, 8 do
		for _, d in ipairs({ { 0, 0 }, { r, 0 }, { -r, 0 }, { 0, r }, { 0, -r } }) do
			local px = math.max(256, math.min(mapX - 256, x + d[1] * step))
			local pz = math.max(256, math.min(mapZ - 256, z + d[2] * step))
			if Spring.GetGroundHeight(px, pz) > 8 then
				return px, pz
			end
		end
	end
	return math.max(256, math.min(mapX - 256, x)),
	       math.max(256, math.min(mapZ - 256, z))
end

local function spawnSide(ally, anchor, facingAway)
	local teams = Spring.GetTeamList(ally)
	local team = teams and teams[1]
	if not team then
		return 0
	end
	local px, pz, perpX, perpZ = anchor[1], anchor[2], anchor[3], anchor[4]
	px, pz = landNear(px, pz)

	local n = 0
	local total = sideTotal[ally]
	local i = 0
	for _, entry in ipairs(rosterOf[ally]) do
		for _ = 1, entry.n do
			-- Centre the line on the anchor, roster order along it.
			local off = (i - (total - 1) / 2) * PITCH
			i = i + 1
			local ux = px + perpX * off
			local uz = pz + perpZ * off
			ux = math.max(64, math.min(mapX - 64, ux))
			uz = math.max(64, math.min(mapZ - 64, uz))
			local y = Spring.GetGroundHeight(ux, uz)
			local id = Spring.CreateUnit(entry.id, ux, y, uz, facingAway and 2 or 0, team)
			if id then
				if (NOCTRL == 3) or (NOCTRL == ally + 1) then
					Spring.SetUnitRulesParam(id, "disableAiControl", 1)
				end
				spawned[ally][id] = true
				n = n + 1
			end
		end
	end
	Spring.Echo(string.format(
		"[BARAI_ARENA] round=%d ally=%d team=%d def=%s n=%d x=%d z=%d",
		roundNo, ally, team, ally == 0 and DEF_A or DEF_B, n, px, pz))
	return n
end

local function aliveCount(ally)
	local n = 0
	for id in pairs(spawned[ally]) do
		if Spring.ValidUnitID(id) and not Spring.GetUnitIsDead(id) then
			n = n + 1
		else
			spawned[ally][id] = nil
		end
	end
	return n
end

local function clearRound()
	for ally = 0, 1 do
		for id in pairs(spawned[ally]) do
			if Spring.ValidUnitID(id) and not Spring.GetUnitIsDead(id) then
				Spring.DestroyUnit(id, false, true)
			end
		end
		spawned[ally] = {}
	end
end

local function beginRound(frame)
	roundNo = roundNo + 1
	roundStart = frame
	dirty = false
	flip = (roundNo % 2 == 0)
	local a = flip and anchorB or anchorA
	local b = flip and anchorA or anchorB
	local n0 = spawnSide(0, a, flip)
	local n1 = spawnSide(1, b, not flip)
	active = (n0 > 0 and n1 > 0)
	if not active then
		Spring.Echo("[BARAI_ARENA] ERROR spawn failed, arena disabled")
		waitUntil = math.huge
	end
end

local function endRound(frame)
	local a0, a1 = aliveCount(0), aliveCount(1)
	local winner = -1
	if a0 > 0 and a1 == 0 then
		winner = 0
	elseif a1 > 0 and a0 == 0 then
		winner = 1
	end
	Spring.Echo(string.format(
		"[BARAI_ARENA_END] round=%d frames=%d winner=%d alive0=%d alive1=%d "
		.. "metal0=%.0f metal1=%.0f spawn0=%d spawn1=%d flip=%d clean=%d",
		roundNo, frame - roundStart, winner, a0, a1,
		a0 * metalOf[0], a1 * metalOf[1], sideTotal[0], sideTotal[1], flip and 1 or 0,
		dirty and 0 or 1))
	clearRound()
	active = false
	waitUntil = frame + GAP
end

--------------------------------------------------------------------------------

function gadget:Initialize()
	local rosterA, totalA, avgA, sightA = parseRoster(DEF_A)
	local rosterB, totalB, avgB, sightB = parseRoster(DEF_B)
	if not rosterA or not rosterB then
		gadgetHandler:RemoveGadget(self)
		return
	end
	rosterOf[0], sideTotal[0], metalOf[0] = rosterA, totalA, avgA
	rosterOf[1], sideTotal[1], metalOf[1] = rosterB, totalB, avgB
	-- WITHIN LOS OF EACH OTHER (apexearth: "Important to make sure each side
	-- is within LOS of each other" -- blind spawns wandered instead of
	-- fighting). Unless the sep option is set explicitly, the lines stand
	-- just inside the SHORTEST sight range in the fight.
	if tostring(modOptions.dev_arena_sep or "") == "" then
		local sight = math.min(sightA, sightB)
		SEP = math.max(200, math.min(SEP, sight * 0.85))
	end
	computeAnchors()
	Spring.Echo(string.format(
		"[BARAI_ARENA] init defA=%s defB=%s count=%d/%d sep=%d round=%d",
		DEF_A, DEF_B, totalA, totalB, SEP, ROUND))
end

-- The arena sits at the map centre of a live match, so each AI's real army can
-- wander in and decide a round. A round where anything outside the two spawned
-- sets dealt a killing blow measures the surrounding game, not the fight, and is
-- dropped by tools/arena.py. Without this the instrument reported a 0.72
-- unit/round gap even with BOTH sides' units removed from AI control, which is a
-- fight neither AI was steering.
function gadget:UnitDestroyed(unitID, unitDefID, teamID, attackerID)
	if not active then
		return
	end
	if not (spawned[0][unitID] or spawned[1][unitID]) then
		return
	end
	if attackerID == nil then
		return  -- terrain, self-destruct, or our own end-of-round cleanup
	end
	if not (spawned[0][attackerID] or spawned[1][attackerID]) then
		dirty = true
	end
end

function gadget:GameFrame(frame)
	-- Pure mode parks the starters just before the first spawn: late enough
	-- that every starting unit exists, early enough that nothing was built.
	if PURE then
		-- Frame 90: after every starting unit exists, before anything builds.
		if (not pureDone) and (frame >= 90) then
			parkStarters()
		end
		if pureDone then
			restun(frame)
		end
	end
	if active then
		if aliveCount(0) == 0 or aliveCount(1) == 0 or (frame - roundStart) >= ROUND then
			endRound(frame)
		end
	elseif frame >= waitUntil then
		beginRound(frame)
	end
end
