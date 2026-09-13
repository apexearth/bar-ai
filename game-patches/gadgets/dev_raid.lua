--------------------------------------------------------------------------------
-- dev_raid.lua -- scripted enemy raids at fixed minutes, so the first minutes
-- of a harness game contain the fight docs/24 wants judged.
--
-- Stock BARb on the benchmark makes first contact at 8-12 minutes, so a test
-- judged at five minutes measured nothing. This gadget spawns waves for a
-- holder team (a NullAI on the enemy's ally, added with run_match.py
-- --extra-ai NullAI:0.1@1) at a point between the two starts and fight-moves
-- them at the target's start position, re-ordering any raider that goes idle.
-- The AI under test sees exactly what a human raid looks like: units appear on
-- radar from the enemy's direction and walk at the base.
--
-- Inert unless the start script sets dev_raid=1.
--
--   dev_raid        "1" to enable
--   dev_raid_team   the holder team id (required)
--   dev_raid_waves  "MIN:ROSTER|MIN:ROSTER..." -- minute and roster per wave,
--                   roster as "armpw*2,armflea*3" (default below)
--   dev_raid_from   spawn distance from the target's base, as a fraction of
--                   the base-to-enemy distance (default 0.6). The point is
--                   then pushed out along its bearing until it is outside
--                   the target's LOS and radar (apexearth: "sometimes these
--                   enemies spawn right on top of us").
--   dev_raid_angle  bearing the raid comes from: "enemy" (default, straight
--                   from the enemy side), "random" (a new bearing per group),
--                   or degrees
--   dev_raid_split  groups per wave, each from its own bearing (default 1);
--                   with "enemy" the groups fan across +-60 degrees
--   dev_raid_stagger  seconds between a wave's groups (default 0)
--   dev_raid_ratio  size each wave from the target's own army: the raiders
--                   total the target's mobile armed metal divided by this,
--                   drawn in the roster's proportions, at least one per
--                   group (0 = the roster as written, default). Nothing is
--                   ever spawned for the target.
--   dev_raid_target "base" (centroid of the target's buildings, default),
--                   "edge" (the building nearest the group's spawn), "mex"
--                   (the extractor nearest it), "eco" (the extractor or
--                   energy building nearest it) or "con" (the constructor
--                   nearest it -- falls back to edge)
--
-- Lines, read by tools/test_raid.py:
--   [BARAI_RAID]    wave=N group=G/K frame= n= metal= x= z= tx= tz= bearing= target=
--   [BARAI_BASE]    frame= team= bld= rms= max= mex= mexmax= army= armyM= armyRms= raiders= raidM=
--       the target's buildings at the wave's first spawn: count, RMS and
--       max distance from their centroid, extractor count and max distance;
--       then its mobile army: count, metal, RMS distance from the base
--       centroid, and the raiders and raider metal the wave was sized to.
--   [BARAI_RAIDEND] wave=N frame= spawned= killed= alive= dur= closest= seen= engaged= resp= peak= army=
--       dur is frames from spawn to the last raider's death (or game end);
--       closest is the wave's nearest approach to the target's base, in elmos;
--       seen is frames from spawn until a raider first shows on the target's
--       radar or in its LOS, engaged until one is first damaged by the target,
--       resp the target's mobile armed units within RESP_R of a raider at
--       that moment, peak the most at any time, army its mobile armed total
--       then (-1 = never).
--------------------------------------------------------------------------------

local modOptions = Spring.GetModOptions() or {}
local enabled = tostring(modOptions.dev_raid or "") == "1"

-- Telemetry goes through the log sink (dev_log_sink.lua), not the console.
local function BARAI_Echo(line)
	if GG and GG.BARAI_LOG then
		GG.BARAI_LOG(line)
	else
		Spring.Echo(line)
	end
end

function gadget:GetInfo()
	return {
		name    = "Dev Raid",
		desc    = "Scripted enemy raids at fixed minutes for the early-fight test.",
		author  = "bar-ai",
		date    = "2026",
		license = "GNU GPL, v2 or later",
		layer   = 1003,
		enabled = enabled,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return
end

local HOLDER = tonumber(modOptions.dev_raid_team or -1) or -1
local FROM = tonumber(modOptions.dev_raid_from or 0.6) or 0.6
local ANGLE = tostring(modOptions.dev_raid_angle or "enemy")
local SPLIT = math.max(1, math.floor(tonumber(modOptions.dev_raid_split or 1) or 1))
local STAGGER = math.floor((tonumber(modOptions.dev_raid_stagger or 0) or 0) * 30)
local TARGET = tostring(modOptions.dev_raid_target or "base")
local RATIO = tonumber(modOptions.dev_raid_ratio or 0) or 0
local WAVES_SPEC = tostring(modOptions.dev_raid_waves or "")
if WAVES_SPEC == "" then
	-- "|" between waves: a ";" would end the start-script value.
	WAVES_SPEC = "3:armpw*2|5:armpw*3,armflea*2|7:armpw*5|9:armpw*4,armham*2"
end
local REORDER_EVERY = 90       -- frames between idle checks
local TRACK_EVERY = 15
local PITCH = 48               -- elmos between spawned units in a rank
local RESP_R = 600             -- a unit this near a raider counts as responding
local targetAlly = nil
local mobileArmed = {}

local mapX = Game.mapSizeX
local mapZ = Game.mapSizeZ

local waves = {}               -- {frame, roster={{id,n}}, spawned=..., ...}
local targetTeam = nil
local holderAlly = nil
local targetX, targetZ = nil, nil   -- the current wave's aim point
local raiderWave = {}          -- unitID -> wave
local raiderAim = {}           -- unitID -> {x, z} the unit was sent at

local function parseWaves(spec)
	local out = {}
	for part in string.gmatch(spec, "[^|]+") do
		local min, roster = string.match(part, "^%s*([%d%.]+)%s*:%s*(.-)%s*$")
		if min and roster then
			local list, ok = {}, true
			for item in string.gmatch(roster, "[^,]+") do
				local name, n = string.match(item, "^%s*(%w+)%s*%*%s*(%d+)%s*$")
				if not name then
					name, n = string.match(item, "^%s*(%w+)%s*$"), 1
				end
				local ud = name and UnitDefNames[name]
				if ud then
					list[#list + 1] = { id = ud.id, n = tonumber(n) or 1, cost = ud.metalCost or 0 }
				else
					BARAI_Echo("[BARAI_RAID] unknown unit in dev_raid_waves: " .. tostring(item))
					ok = false
				end
			end
			if ok and #list > 0 then
				-- Split the roster round-robin across the wave's groups.
				local groups = {}
				for gi = 1, SPLIT do
					groups[gi] = { index = gi, roster = {}, at = nil,
						frame = math.floor(tonumber(min) * 60 * 30) + (gi - 1) * STAGGER }
				end
				local gi = 0
				for _, e in ipairs(list) do
					for _ = 1, e.n do
						gi = gi % SPLIT + 1
						local r = groups[gi].roster
						if r[#r] and r[#r].id == e.id then
							r[#r].n = r[#r].n + 1
						else
							r[#r + 1] = { id = e.id, n = 1, cost = e.cost }
						end
					end
				end
				local total = 0
				for _, e in ipairs(list) do
					total = total + e.n
				end
				out[#out + 1] = { frame = math.floor(tonumber(min) * 60 * 30), roster = list, groups = groups, total = total,
					spawned = 0, killed = 0, metal = 0, at = nil, closest = 1e9, done = false,
					seen = nil, engaged = nil, resp = -1, peak = -1, army = -1 }
			end
		end
	end
	table.sort(out, function(a, b) return a.frame < b.frame end)
	return out
end

-- The first point at least `minR` out along a bearing from (cx,cz) that the
-- target's ally team neither sees nor has on radar, on the map. nil when the
-- bearing runs off the map while still watched.
local function unseenAlong(cx, cz, dx, dz, minR)
	local r = minR
	while true do
		local x, z = cx + dx * r, cz + dz * r
		if x < 128 or z < 128 or x > mapX - 128 or z > mapZ - 128 then
			return nil
		end
		local y = Spring.GetGroundHeight(x, z)
		if targetAlly == nil
			or (not Spring.IsPosInLos(x, y, z, targetAlly)
				and not Spring.IsPosInRadar(x, y, z, targetAlly)) then
			return x, z, r
		end
		r = r + 64
	end
end

local function landNear(x, z)
	local step = 128
	for r = 0, 12 do
		for _, d in ipairs({ { 0, 0 }, { r, 0 }, { -r, 0 }, { 0, r }, { 0, -r }, { r, r }, { -r, -r } }) do
			local px = math.max(128, math.min(mapX - 128, x + d[1] * step))
			local pz = math.max(128, math.min(mapZ - 128, z + d[2] * step))
			if Spring.GetGroundHeight(px, pz) > 8 then
				return px, pz
			end
		end
	end
	return math.max(128, math.min(mapX - 128, x)), math.max(128, math.min(mapZ - 128, z))
end

function gadget:Initialize()
	if HOLDER < 0 or not Spring.GetTeamInfo(HOLDER, false) then
		BARAI_Echo("[BARAI_RAID] no holder team (dev_raid_team); gadget off")
		gadgetHandler:RemoveGadget(self)
		return
	end
	waves = parseWaves(WAVES_SPEC)
	if #waves == 0 then
		BARAI_Echo("[BARAI_RAID] no waves parsed from dev_raid_waves; gadget off")
		gadgetHandler:RemoveGadget(self)
		return
	end
end

-- Centroid of a team's units, buildings only when it has any: a start
-- position is NOT where the base is (CircuitAI chooses its own start in game),
-- so every wave aims at where the target's buildings actually stand.
local function centroid(teams, buildingsOnly)
	local ax, az, an = 0, 0, 0
	for _, t in ipairs(teams) do
		for _, id in ipairs(Spring.GetTeamUnits(t) or {}) do
			local udid = Spring.GetUnitDefID(id)
			local ud = udid and UnitDefs[udid]
			if ud and ((not buildingsOnly) or (ud.speed or 0) <= 0) then
				local x, _, z = Spring.GetUnitPosition(id)
				if x then
					ax, az, an = ax + x, az + z, an + 1
				end
			end
		end
	end
	if an == 0 then
		return nil
	end
	return ax / an, az / an
end

local function teamPos(teams)
	local x, z = centroid(teams, true)
	if x == nil then
		x, z = centroid(teams, false)
	end
	return x, z
end

function gadget:GameStart()
	local _, _, _, _, _, ally = Spring.GetTeamInfo(HOLDER, false)
	holderAlly = ally
	-- The target is the enemy team nearest the holder's side at game start:
	-- in a 1v1 that is the AI under test.
	local hx, hz = teamPos(Spring.GetTeamList(holderAlly) or {})
	local best = nil
	for _, t in ipairs(Spring.GetTeamList() or {}) do
		local _, _, _, _, _, a = Spring.GetTeamInfo(t, false)
		if a ~= holderAlly and t ~= Spring.GetGaiaTeamID() then
			local x, z = teamPos({ t })
			if x and hx then
				local d = (x - hx) ^ 2 + (z - hz) ^ 2
				if best == nil or d < best then
					best, targetTeam = d, t
				end
			end
		end
	end
	if targetTeam == nil then
		BARAI_Echo("[BARAI_RAID] no target team; gadget off")
		gadgetHandler:RemoveGadget(self)
		return
	end
	local _, _, _, _, _, ta = Spring.GetTeamInfo(targetTeam, false)
	targetAlly = ta
	-- The holder's own start units go: its commander would otherwise stand in
	-- the enemy's box as a 2500-metal target that shoots back, which is a
	-- fight neither AI chose.
	for _, id in ipairs(Spring.GetTeamUnits(HOLDER) or {}) do
		Spring.DestroyUnit(id, false, true)
	end
	BARAI_Echo(string.format("[BARAI_RAID] init holder=%d waves=%d targetTeam=%d",
		HOLDER, #waves, targetTeam))
end

local function orderAt(id, x, z)
	local y = Spring.GetGroundHeight(x, z)
	Spring.GiveOrderToUnit(id, CMD.FIGHT, { x, y, z }, 0)
end

-- Where the enemy side stands, for the "enemy" bearing and the spawn radius.
local function enemySide()
	local mates = {}
	for _, t in ipairs(Spring.GetTeamList(holderAlly) or {}) do
		if t ~= HOLDER then
			mates[#mates + 1] = t
		end
	end
	local hx, hz = teamPos(mates)
	if hx == nil then
		hx, hz = teamPos({ HOLDER })
	end
	return hx, hz
end

-- The target's buildings, with the base-spread numbers the test reports.
local function baseShape()
	local pts = {}
	local cx, cz, n = 0, 0, 0
	for _, id in ipairs(Spring.GetTeamUnits(targetTeam) or {}) do
		local udid = Spring.GetUnitDefID(id)
		local ud = udid and UnitDefs[udid]
		if ud and (ud.speed or 0) <= 0 then
			local x, _, z = Spring.GetUnitPosition(id)
			if x then
				local eco = (ud.extractsMetal or 0) > 0 or (ud.energyMake or 0) > 0
					or (ud.windGenerator or 0) > 0 or (ud.tidalGenerator or 0) > 0
				pts[#pts + 1] = { x, z, (ud.extractsMetal or 0) > 0, eco }
				cx, cz, n = cx + x, cz + z, n + 1
			end
		end
	end
	if n == 0 then
		return nil
	end
	cx, cz = cx / n, cz / n
	local sq, mx, mexN, mexMax = 0, 0, 0, 0
	for _, p in ipairs(pts) do
		local d2 = (p[1] - cx) ^ 2 + (p[2] - cz) ^ 2
		sq = sq + d2
		if d2 > mx then mx = d2 end
		if p[3] then
			mexN = mexN + 1
			if d2 > mexMax then mexMax = d2 end
		end
	end
	return { cx = cx, cz = cz, n = n, rms = math.sqrt(sq / n), max = math.sqrt(mx),
		mexN = mexN, mexMax = math.sqrt(mexMax), pts = pts }
end

-- What a group aims at, by TARGET, from its spawn point.
local function aimFor(shape, sx, sz)
	if TARGET == "base" then
		return shape.cx, shape.cz, "base"
	end
	local bestD, bx, bz, kind = nil, shape.cx, shape.cz, "base"
	if TARGET == "con" then
		for _, id in ipairs(Spring.GetTeamUnits(targetTeam) or {}) do
			local udid = Spring.GetUnitDefID(id)
			local ud = udid and UnitDefs[udid]
			if ud and ud.isBuilder and (ud.speed or 0) > 0 then
				local x, _, z = Spring.GetUnitPosition(id)
				if x then
					local d = (x - sx) ^ 2 + (z - sz) ^ 2
					if bestD == nil or d < bestD then
						bestD, bx, bz, kind = d, x, z, "con"
					end
				end
			end
		end
		if bestD ~= nil then
			return bx, bz, kind
		end
	end
	local wantMex, wantEco = (TARGET == "mex"), (TARGET == "eco")
	for _, p in ipairs(shape.pts) do
		if (wantMex and p[3]) or (wantEco and p[4]) or (not wantMex and not wantEco) then
			local d = (p[1] - sx) ^ 2 + (p[2] - sz) ^ 2
			if bestD == nil or d < bestD then
				bestD, bx, bz = d, p[1], p[2]
				kind = wantMex and "mex" or (wantEco and (p[3] and "mex" or "energy") or "edge")
			end
		end
	end
	return bx, bz, kind
end

-- The target's mobile army: count, metal, and RMS distance from the base
-- centroid (how spread out it stands).
local function armyOf(shape)
	local n, metal, sq = 0, 0, 0
	for _, id in ipairs(Spring.GetTeamUnits(targetTeam) or {}) do
		local udid = Spring.GetUnitDefID(id)
		local ud = udid and UnitDefs[udid]
		if ud and (ud.speed or 0) > 0 and ud.weapons ~= nil and #ud.weapons > 0
			and (ud.customParams or {}).iscommander == nil then
			local x, _, z = Spring.GetUnitPosition(id)
			if x then
				n, metal = n + 1, metal + (ud.metalCost or 0)
				sq = sq + (x - shape.cx) ^ 2 + (z - shape.cz) ^ 2
			end
		end
	end
	return n, metal, (n > 0) and math.sqrt(sq / n) or 0
end

-- Size the wave from the target's army (apexearth: "tailor the enemy army
-- size based on our army size"): raider metal is the army's metal / RATIO,
-- the roster cycled in its own proportions, at least one raider per group.
local function scaleWave(w, budget)
	local tmpl = {}
	for _, e in ipairs(w.roster) do
		for _ = 1, e.n do
			tmpl[#tmpl + 1] = e
		end
	end
	for _, g in ipairs(w.groups) do
		g.roster = {}
	end
	local spent, count, i, gi = 0, 0, 0, 0
	while spent < budget or count < #w.groups do
		local e = tmpl[i % #tmpl + 1]
		i = i + 1
		gi = gi % #w.groups + 1
		local r = w.groups[gi].roster
		if r[#r] and r[#r].id == e.id then
			r[#r].n = r[#r].n + 1
		else
			r[#r + 1] = { id = e.id, n = 1, cost = e.cost }
		end
		spent, count = spent + e.cost, count + 1
	end
	w.total = count
	return count, spent
end

local function spawnGroup(w, g, frame)
	local shape = baseShape()
	local hx, hz = enemySide()
	if shape == nil or hx == nil then
		g.at = frame
		BARAI_Echo(string.format("[BARAI_RAID] wave=%d group=%d/%d frame=%d skipped: no target or holder units",
			w.index, g.index, #w.groups, frame))
		return
	end
	if w.at == nil then
		-- The wave's aim point for `closest` is the base centroid at first spawn.
		w.tx, w.tz = shape.cx, shape.cz
		local armyN, armyM, armyRms = armyOf(shape)
		local raiders, raidM = -1, -1
		if RATIO > 0 then
			raiders, raidM = scaleWave(w, armyM / RATIO)
		end
		BARAI_Echo(string.format("[BARAI_BASE] frame=%d team=%d bld=%d rms=%d max=%d mex=%d mexmax=%d army=%d armyM=%d armyRms=%d raiders=%d raidM=%d",
			frame, targetTeam, shape.n, shape.rms, shape.max, shape.mexN, shape.mexMax,
			armyN, armyM, armyRms, raiders, raidM))
	end
	local ex, ez = hx - shape.cx, hz - shape.cz
	local eLen = math.sqrt(ex * ex + ez * ez)
	if eLen < 1 then
		eLen = 1
	end
	local baseDeg = math.deg(math.atan2(ez, ex))
	local deg, dx, dz, sx, sz
	local minR = eLen * FROM
	if ANGLE == "random" then
		-- A base in a map corner has most bearings pointing off the map, and
		-- a base with radar sees most of the rest. Draw bearings until one
		-- reaches unwatched ground on the map; failing that, keep the draw
		-- that got farthest out.
		local bestR = nil
		for _ = 1, 24 do
			local d = math.random() * 360
			local cx, cz = math.cos(math.rad(d)), math.sin(math.rad(d))
			local ux, uz, ur = unseenAlong(shape.cx, shape.cz, cx, cz, minR)
			if ux then
				deg, dx, dz, sx, sz = d, cx, cz, ux, uz
				break
			end
			-- Watched all the way to the edge: remember the edge point.
			local ex2 = math.max(128, math.min(mapX - 128, shape.cx + cx * minR))
			local ez2 = math.max(128, math.min(mapZ - 128, shape.cz + cz * minR))
			local rr = math.sqrt((ex2 - shape.cx) ^ 2 + (ez2 - shape.cz) ^ 2)
			if bestR == nil or rr > bestR then
				bestR, deg, dx, dz, sx, sz = rr, d, cx, cz, ex2, ez2
			end
		end
	else
		deg = tonumber(ANGLE) or baseDeg
		if #w.groups > 1 then
			deg = deg + (g.index - 1) / (#w.groups - 1) * 120 - 60
		end
		dx, dz = math.cos(math.rad(deg)), math.sin(math.rad(deg))
		local ux, uz = unseenAlong(shape.cx, shape.cz, dx, dz, minR)
		if ux then
			sx, sz = ux, uz
		else
			sx = math.max(128, math.min(mapX - 128, shape.cx + dx * minR))
			sz = math.max(128, math.min(mapZ - 128, shape.cz + dz * minR))
		end
	end
	sx, sz = landNear(sx, sz)
	local ax, az, kind = aimFor(shape, sx, sz)
	local total = 0
	for _, e in ipairs(g.roster) do
		total = total + e.n
	end
	local perpX, perpZ = -dz, dx
	local i, n, metal = 0, 0, 0
	for _, e in ipairs(g.roster) do
		for _ = 1, e.n do
			local off = (i - (total - 1) / 2) * PITCH
			i = i + 1
			local ux = math.max(64, math.min(mapX - 64, sx + perpX * off))
			local uz = math.max(64, math.min(mapZ - 64, sz + perpZ * off))
			local id = Spring.CreateUnit(e.id, ux, Spring.GetGroundHeight(ux, uz), uz, 0, HOLDER)
			if id then
				raiderWave[id] = w
				raiderAim[id] = { ax, az }
				n, metal = n + 1, metal + e.cost
				orderAt(id, ax, az)
			end
		end
	end
	w.spawned = w.spawned + n
	local sy = Spring.GetGroundHeight(sx, sz)
	local seenAt = (targetAlly and (Spring.IsPosInLos(sx, sy, sz, targetAlly)
		or Spring.IsPosInRadar(sx, sy, sz, targetAlly))) and 1 or 0
	w.metal = w.metal + metal
	if w.at == nil then
		w.at = frame
	end
	g.at = frame
	BARAI_Echo(string.format(
		"[BARAI_RAID] wave=%d group=%d/%d frame=%d n=%d metal=%d x=%d z=%d tx=%d tz=%d bearing=%d target=%s seen=%d",
		w.index, g.index, #w.groups, frame, n, metal, sx, sz, ax, az, math.floor(deg % 360), kind, seenAt))
end

local function allSpawned(w)
	for _, g in ipairs(w.groups) do
		if g.at == nil then
			return false
		end
	end
	return true
end

local function finishWave(w, frame)
	if w.done or w.at == nil then
		return
	end
	w.done = true
	local alive = w.spawned - w.killed
	BARAI_Echo(string.format(
		"[BARAI_RAIDEND] wave=%d frame=%d spawned=%d killed=%d alive=%d dur=%d closest=%d seen=%d engaged=%d resp=%d peak=%d army=%d",
		w.index, frame, w.spawned, w.killed, alive, frame - w.at,
		(w.closest < 1e9) and math.floor(w.closest) or -1,
		w.seen and (w.seen - w.at) or -1, w.engaged and (w.engaged - w.at) or -1,
		w.resp, w.peak, w.army))
end

function gadget:UnitDamaged(unitID, unitDefID, unitTeam, damage, paralyzer,
		weaponDefID, projectileID, attackerID, attackerDefID, attackerTeam)
	local w = raiderWave[unitID]
	if w == nil or w.engaged ~= nil or attackerTeam ~= targetTeam then
		return
	end
	w.engaged = Spring.GetGameFrame()
	-- Responders at first contact: the target's mobile armed units within
	-- RESP_R of the raider that was hit.
	local n = 0
	local rx, _, rz = Spring.GetUnitPosition(unitID)
	for _, id in ipairs(Spring.GetTeamUnits(targetTeam) or {}) do
		local udid = Spring.GetUnitDefID(id)
		if udid and mobileArmed[udid] then
			local x, _, z = Spring.GetUnitPosition(id)
			if x and rx and (x - rx) ^ 2 + (z - rz) ^ 2 <= RESP_R * RESP_R then
				n = n + 1
			end
		end
	end
	w.resp = n
end

function gadget:UnitDestroyed(unitID, unitDefID, unitTeam)
	local w = raiderWave[unitID]
	if w == nil then
		return
	end
	raiderWave[unitID] = nil
	raiderAim[unitID] = nil
	w.killed = w.killed + 1
	if allSpawned(w) and w.killed >= w.spawned then
		finishWave(w, Spring.GetGameFrame())
	end
end

function gadget:GameFrame(frame)
	if targetTeam == nil then
		return
	end
	for i, w in ipairs(waves) do
		w.index = i
		for _, g in ipairs(w.groups) do
			if g.at == nil and frame >= g.frame then
				spawnGroup(w, g, frame)
			end
		end
	end
	if frame % TRACK_EVERY == 0 then
		local pos = {}   -- wave -> list of live raider positions
		for id, w in pairs(raiderWave) do
			local x, _, z = Spring.GetUnitPosition(id)
			if x then
				local d = math.sqrt((x - w.tx) ^ 2 + (z - w.tz) ^ 2)
				if d < w.closest then
					w.closest = d
				end
				if w.seen == nil and targetAlly and
					(Spring.IsUnitInRadar(id, targetAlly) or Spring.IsUnitInLos(id, targetAlly)) then
					w.seen = frame
				end
				pos[w] = pos[w] or {}
				pos[w][#pos[w] + 1] = { x, z }
			end
		end
		if next(pos) ~= nil then
			-- The target's mobile armed units, and how many stand near each wave.
			local army, near = 0, {}
			for _, id in ipairs(Spring.GetTeamUnits(targetTeam) or {}) do
				local udid = Spring.GetUnitDefID(id)
				if udid then
					local ma = mobileArmed[udid]
					if ma == nil then
						local ud = UnitDefs[udid]
						ma = ud ~= nil and (ud.speed or 0) > 0 and ud.weapons ~= nil and #ud.weapons > 0
						mobileArmed[udid] = ma
					end
					if ma then
						army = army + 1
						local x, _, z = Spring.GetUnitPosition(id)
						if x then
							for w, list in pairs(pos) do
								for _, p in ipairs(list) do
									if (x - p[1]) ^ 2 + (z - p[2]) ^ 2 <= RESP_R * RESP_R then
										near[w] = (near[w] or 0) + 1
										break
									end
								end
							end
						end
					end
				end
			end
			for w in pairs(pos) do
				local n = near[w] or 0
				if n > w.peak then
					w.peak = n
				end
				w.army = army
			end
		end
	end
	if frame % REORDER_EVERY == 0 then
		for id in pairs(raiderWave) do
			local cmds = Spring.GetUnitCommands(id, 1)
			if cmds == nil or #cmds == 0 then
				-- Arrived or lost its order: roam the base rather than stand.
				local ang = math.random() * 2 * math.pi
				local r = 200 + math.random() * 400
				local aim = raiderAim[id] or { raiderWave[id].tx, raiderWave[id].tz }
				local x, z = landNear(aim[1] + math.cos(ang) * r, aim[2] + math.sin(ang) * r)
				orderAt(id, x, z)
			end
		end
	end
end

function gadget:GameOver()
	local frame = Spring.GetGameFrame()
	for _, w in ipairs(waves) do
		finishWave(w, frame)
	end
end

function gadget:Shutdown()
	local frame = Spring.GetGameFrame()
	for _, w in ipairs(waves) do
		finishWave(w, frame)
	end
end
