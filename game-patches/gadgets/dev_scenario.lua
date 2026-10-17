--------------------------------------------------------------------------------
-- dev_scenario.lua -- a short scripted fight: fixed units at fixed places, the
-- AIs' starting units removed, judged by tools/scenario.py.
--
-- Inert unless the start script sets dev_scenario=<name>. tools/scenario.py
-- writes every option below from a scenario spec.
--
--   dev_scenario        scenario name (enables the gadget)
--   dev_scenario_units  groups joined by "|", each
--                         side:def:n:ref:x:z:spacing:order[:tref:tx:tz]
--                       side 0|1 (ally); ref c (map centre), s0, s1 (an
--                       ally's start); x runs from ally 0 toward ally 1 along
--                       the map's start axis, z across it. order ai (the
--                       ally's AI owns it), hold, guard, fight, move (owned by
--                       the ally's holder team, a NullAI; buildings always go
--                       to the AI's team). fight/move take a target point.
--   dev_scenario_spawn  spawn frame (default 90)
--   dev_scenario_len    seconds from spawn to the end report (default 120)
--   dev_scenario_coms   remove (default) | park | keep: the starting units
--   dev_scenario_los    global (default) | normal
--   dev_scenario_clear  1 (default): destroy every feature at spawn
--
-- Lines:
--   [BARAI_SCEN] name= frame= axis= c= s0= s1=
--   [BARAI_SCEN_SPAWN] group= side= team= def= n= x= z= order=
--   [BARAI_SCEN_DEATH] frame= uid= side= def= cost= mob= near= disp3= contact= fired= atkdef=
--       near: distance to the nearest living mobile armed friend (-1 none
--       within 2000); disp3: elmos moved over the last ~3 s; contact: frame it
--       first came within weapon reach of an opposing scenario unit (-1 never);
--       fired: it damaged an opposing scenario unit at least once
--   [BARAI_SCEN_UNIT] uid= side= group= def= mob= alive= contact= moved=
--   [BARAI_SCEN_END] frame= side= alive= spawned= metal= metalSpawned=
--------------------------------------------------------------------------------

local modOptions = Spring.GetModOptions() or {}
local NAME = tostring(modOptions.dev_scenario or "")
local enabled = NAME ~= ""

local function Echo(line)
	if GG and GG.BARAI_LOG then
		GG.BARAI_LOG(line)
	else
		Spring.Echo(line)
	end
end

function gadget:GetInfo()
	return {
		name    = "Dev Scenario",
		desc    = "Short scripted fights for AI behaviour tests.",
		author  = "bar-ai",
		date    = "2026",
		license = "GNU GPL, v2 or later",
		layer   = 1004,
		enabled = enabled,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return
end

local SPAWN = math.floor(tonumber(modOptions.dev_scenario_spawn) or 90)
local LEN = tonumber(modOptions.dev_scenario_len) or 120
local ENDF = SPAWN + math.floor(LEN * 30)
local COMS = tostring(modOptions.dev_scenario_coms or "remove")
local LOS = tostring(modOptions.dev_scenario_los or "global")
local CLEAR = tostring(modOptions.dev_scenario_clear or "1") == "1"
local TICK = 15
local HIST = 6

local mapX, mapZ = Game.mapSizeX, Game.mapSizeZ
local groups = {}
local units = {}       -- uid -> record
local starters = {}
local parked = {}
local ended = false
local fwdX, fwdZ = 1, 0
local starts = {}
local mainTeam, holderTeam = {}, {}

local function defFacts(udid)
	local ud = UnitDefs[udid]
	local mobile = ud ~= nil and (ud.speed or 0) > 0
	local armed = ud ~= nil and ud.weapons ~= nil and #ud.weapons > 0
	return ud, mobile, armed, (ud and ud.maxWeaponRange) or 0
end

local function parseGroups(spec)
	for part in tostring(spec):gmatch("[^|]+") do
		local f = {}
		for tok in part:gmatch("[^:]+") do
			f[#f + 1] = tok
		end
		local ud = UnitDefNames[f[2] or ""]
		if not ud then
			Echo("[BARAI_SCEN] ERROR unknown def " .. tostring(f[2]))
		else
			groups[#groups + 1] = {
				side = tonumber(f[1]) or 0, def = ud.id, name = ud.name,
				n = tonumber(f[3]) or 1, ref = f[4] or "c",
				x = tonumber(f[5]) or 0, z = tonumber(f[6]) or 0,
				sp = tonumber(f[7]) or 48, order = f[8] or "ai",
				tref = f[9], tx = tonumber(f[10]), tz = tonumber(f[11]),
			}
		end
	end
end

local function toWorld(ref, x, z)
	local ox, oz = mapX / 2, mapZ / 2
	if ref == "s0" and starts[0] then
		ox, oz = starts[0][1], starts[0][2]
	elseif ref == "s1" and starts[1] then
		ox, oz = starts[1][1], starts[1][2]
	end
	local px, pz = -fwdZ, fwdX
	local wx = ox + x * fwdX + z * px
	local wz = oz + x * fwdZ + z * pz
	return math.max(48, math.min(mapX - 48, wx)), math.max(48, math.min(mapZ - 48, wz))
end

local function readFrame()
	for ally = 0, 1 do
		local teams = Spring.GetTeamList(ally) or {}
		mainTeam[ally] = teams[1]
		holderTeam[ally] = teams[2] or teams[1]
		if teams[1] then
			local x, _, z = Spring.GetTeamStartPosition(teams[1])
			if x and x > 0 then
				starts[ally] = { x, z }
			end
		end
	end
	local dx, dz = 1, 0
	if starts[0] and starts[1] then
		dx, dz = starts[1][1] - starts[0][1], starts[1][2] - starts[0][2]
	end
	if math.abs(dx) >= math.abs(dz) then
		fwdX, fwdZ = (dx >= 0) and 1 or -1, 0
	else
		fwdX, fwdZ = 0, (dz >= 0) and 1 or -1
	end
end

local function facingFor(side)
	local fx, fz = fwdX, fwdZ
	if side == 1 then
		fx, fz = -fx, -fz
	end
	if fz > 0 then return 0 elseif fx > 0 then return 1 elseif fz < 0 then return 2 end
	return 3
end

local function issue(rec)
	local g = rec.g
	if g.order == "fight" or g.order == "move" then
		local cmd = (g.order == "fight") and CMD.FIGHT or CMD.MOVE
		Spring.GiveOrderToUnit(rec.uid, cmd, { rec.tx, Spring.GetGroundHeight(rec.tx, rec.tz), rec.tz }, 0)
	end
end

local function spawnAll()
	for gi, g in ipairs(groups) do
		local ud, mobile = defFacts(g.def)
		local team = (g.order == "ai" or not mobile) and mainTeam[g.side] or holderTeam[g.side]
		local cx, cz = toWorld(g.ref, g.x, g.z)
		local tx, tz
		if g.tref then
			tx, tz = toWorld(g.tref, g.tx or 0, g.tz or 0)
		end
		local cols = math.max(1, math.ceil(math.sqrt(g.n)))
		local rows = math.ceil(g.n / cols)
		local px, pz = -fwdZ, fwdX
		local made = 0
		for i = 0, g.n - 1 do
			local r, c = math.floor(i / cols), i % cols
			local a = (r - (rows - 1) / 2) * g.sp
			local b = (c - (cols - 1) / 2) * g.sp
			local ux = cx + a * fwdX + b * px
			local uz = cz + a * fwdZ + b * pz
			if not mobile then
				ux, uz = math.floor(ux / 16) * 16 + 8, math.floor(uz / 16) * 16 + 8
			end
			local uid = team and Spring.CreateUnit(g.def, ux, Spring.GetGroundHeight(ux, uz), uz, facingFor(g.side), team)
			if uid then
				made = made + 1
				local rec = { uid = uid, g = g, gi = gi, side = g.side, def = ud.name,
					cost = ud.metalCost or 0, mob = mobile, contact = -1, moved = 0, hist = {},
					lx = ux, lz = uz, tx = tx, tz = tz }
				units[uid] = rec
				if mobile and g.order ~= "ai" then
					local ms = (g.order == "hold") and 0 or ((g.order == "guard") and 1 or 2)
					Spring.GiveOrderToUnit(uid, CMD.MOVE_STATE, { ms }, 0)
					Spring.GiveOrderToUnit(uid, CMD.FIRE_STATE, { 2 }, 0)
					issue(rec)
				end
			end
		end
		Echo(string.format("[BARAI_SCEN_SPAWN] group=%d side=%d team=%s def=%s n=%d x=%d z=%d order=%s",
			gi, g.side, tostring(team), g.name, made, cx, cz, g.order))
	end
end

local function clearStarters(frame)
	for _, teamID in ipairs(Spring.GetTeamList() or {}) do
		for _, uid in ipairs(Spring.GetTeamUnits(teamID) or {}) do
			if not units[uid] and not starters[uid] then
				starters[uid] = true
				if COMS == "remove" then
					Spring.DestroyUnit(uid, false, true)
				elseif COMS == "park" then
					local _, _, _, _, _, ally = Spring.GetTeamInfo(teamID, false)
					local cx = (ally == 0) and 96 or mapX - 96
					local cz = (ally == 0) and 96 or mapZ - 96
					Spring.MoveCtrl.Enable(uid)
					Spring.MoveCtrl.SetPosition(uid, cx, Spring.GetGroundHeight(cx, cz), cz)
					Spring.SetUnitNeutral(uid, true)
					parked[uid] = true
				end
			end
		end
	end
end

local function topUp(frame)
	for _, teamID in ipairs(Spring.GetTeamList() or {}) do
		Spring.SetTeamResource(teamID, "es", 100000)
		Spring.SetTeamResource(teamID, "ms", 20000)
		Spring.SetTeamResource(teamID, "e", 100000)
		Spring.SetTeamResource(teamID, "m", 20000)
	end
	for uid in pairs(parked) do
		if Spring.ValidUnitID(uid) then
			local maxH = select(2, Spring.GetUnitHealth(uid)) or 1000
			Spring.SetUnitHealth(uid, { paralyze = maxH * 100 })
		else
			parked[uid] = nil
		end
	end
end

local function nearestFriend(rec, x, z)
	local best = -1
	for _, uid in ipairs(Spring.GetUnitsInCylinder(x, z, 2000) or {}) do
		if uid ~= rec.uid and not Spring.GetUnitIsDead(uid) then
			local t = Spring.GetUnitTeam(uid)
			local _, _, _, _, _, ally = Spring.GetTeamInfo(t, false)
			if ally == rec.side then
				local _, mobile, armed = defFacts(Spring.GetUnitDefID(uid))
				if mobile and armed then
					local ux, _, uz = Spring.GetUnitPosition(uid)
					local d = math.sqrt((ux - x) ^ 2 + (uz - z) ^ 2)
					if best < 0 or d < best then
						best = d
					end
				end
			end
		end
	end
	return best
end

local function track(frame)
	local live = {}
	for uid, rec in pairs(units) do
		if rec.dead == nil then
			local x, _, z = Spring.GetUnitPosition(uid)
			if x then
				rec.moved = rec.moved + math.sqrt((x - rec.lx) ^ 2 + (z - rec.lz) ^ 2)
				rec.lx, rec.lz = x, z
				local h = rec.hist
				h[#h + 1] = { x, z }
				if #h > HIST then
					table.remove(h, 1)
				end
				local _, _, armed, range = defFacts(Spring.GetUnitDefID(uid))
				live[#live + 1] = { rec = rec, x = x, z = z, r = armed and range or 0 }
			end
		end
	end
	for i = 1, #live do
		local a = live[i]
		if a.rec.contact < 0 then
			for j = 1, #live do
				local b = live[j]
				if b.rec.side ~= a.rec.side then
					local reach = math.max(a.r, b.r) + 20
					if (a.x - b.x) ^ 2 + (a.z - b.z) ^ 2 <= reach * reach then
						a.rec.contact = frame
						break
					end
				end
			end
		end
		local rec = a.rec
		if rec.tx and frame % 90 == 0 and Spring.ValidUnitID(rec.uid)
			and #(Spring.GetUnitCommands(rec.uid, 1) or {}) == 0
			and (a.x - rec.tx) ^ 2 + (a.z - rec.tz) ^ 2 > 150 * 150 then
			issue(rec)
		end
	end
end

local function report(frame)
	ended = true
	local alive, spawned, metal, metalSpawned = { [0] = 0, [1] = 0 }, { [0] = 0, [1] = 0 },
		{ [0] = 0, [1] = 0 }, { [0] = 0, [1] = 0 }
	local ids = {}
	for uid in pairs(units) do
		ids[#ids + 1] = uid
	end
	table.sort(ids)
	for _, uid in ipairs(ids) do
		local rec = units[uid]
		local up = rec.dead == nil and Spring.ValidUnitID(uid) and not Spring.GetUnitIsDead(uid)
		spawned[rec.side] = spawned[rec.side] + 1
		metalSpawned[rec.side] = metalSpawned[rec.side] + rec.cost
		if up then
			alive[rec.side] = alive[rec.side] + 1
			metal[rec.side] = metal[rec.side] + rec.cost
		end
		Echo(string.format("[BARAI_SCEN_UNIT] uid=%d side=%d group=%d def=%s mob=%d alive=%d contact=%d moved=%d",
			uid, rec.side, rec.gi, rec.def, rec.mob and 1 or 0, up and 1 or 0, rec.contact, math.floor(rec.moved)))
	end
	for side = 0, 1 do
		Echo(string.format("[BARAI_SCEN_END] frame=%d side=%d alive=%d spawned=%d metal=%d metalSpawned=%d",
			frame, side, alive[side], spawned[side], metal[side], metalSpawned[side]))
	end
end

function gadget:Initialize()
	parseGroups(modOptions.dev_scenario_units or "")
	if #groups == 0 then
		Echo("[BARAI_SCEN] ERROR no groups; disabled")
		gadgetHandler:RemoveGadget(self)
	end
end

function gadget:UnitDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID, projectileID, attackerID)
	local rec = attackerID and units[attackerID]
	local victim = units[unitID]
	if rec and victim and victim.side ~= rec.side and damage and damage > 0 then
		rec.fired = true
	end
end

function gadget:UnitDestroyed(unitID, unitDefID, unitTeam, attackerID, attackerDefID)
	local rec = units[unitID]
	if rec == nil or rec.dead ~= nil or ended then
		return
	end
	local frame = Spring.GetGameFrame()
	rec.dead = frame
	local x, _, z = Spring.GetUnitPosition(unitID)
	x, z = x or rec.lx, z or rec.lz
	local h = rec.hist
	local disp = -1
	if #h > 0 then
		disp = math.sqrt((x - h[1][1]) ^ 2 + (z - h[1][2]) ^ 2)
	end
	local _, mobile = defFacts(unitDefID)
	local atk = (attackerDefID and UnitDefs[attackerDefID] and UnitDefs[attackerDefID].name) or "?"
	Echo(string.format("[BARAI_SCEN_DEATH] frame=%d uid=%d side=%d def=%s cost=%d mob=%d near=%d disp3=%d contact=%d fired=%d atkdef=%s",
		frame, unitID, rec.side, rec.def, rec.cost, mobile and 1 or 0,
		math.floor(nearestFriend(rec, x, z)), math.floor(disp), rec.contact, rec.fired and 1 or 0, atk))
end

function gadget:GameFrame(frame)
	if ended then
		return
	end
	if frame == 30 and COMS ~= "keep" then
		clearStarters(frame)
	end
	if frame == SPAWN then
		readFrame()
		if LOS == "global" then
			Spring.SetGlobalLos(0, true)
			Spring.SetGlobalLos(1, true)
		end
		if CLEAR then
			for _, fid in ipairs(Spring.GetAllFeatures() or {}) do
				Spring.DestroyFeature(fid)
			end
		end
		local function p(t) return t and string.format("%d,%d", t[1], t[2]) or "-" end
		Echo(string.format("[BARAI_SCEN] name=%s frame=%d axis=%d,%d c=%d,%d s0=%s s1=%s len=%d coms=%s los=%s",
			NAME, frame, fwdX, fwdZ, mapX / 2, mapZ / 2, p(starts[0]), p(starts[1]), LEN, COMS, LOS))
		spawnAll()
	end
	if frame % 30 == 11 then
		topUp(frame)
	end
	if frame > SPAWN and frame % TICK == 0 then
		track(frame)
	end
	if frame >= ENDF then
		report(frame)
	end
end
