--------------------------------------------------------------------------------
-- dev_combat_log.lua -- per-unit combat telemetry for fight reconstruction.
--
-- dev_stats_export answers "how did the game go" in aggregates. This gadget
-- answers "how did each FIGHT go": every death with its attacker and the
-- victim's velocity at the instant it died, plus a periodic snapshot of every
-- mobile armed unit on the field. From those two streams tools/battles.py
-- rebuilds individual battles offline -- who was present, at what odds the
-- engagement started, which way the losers were moving when they died, and how
-- tightly each side's squads were grouped.
--
-- Velocity at death is the retreat evidence: a unit killed while moving toward
-- its own start position was trying to leave; one moving toward the enemy was
-- still committed. The AI's own logs say what it DECIDED; this says what the
-- unit was physically DOING.
--
-- Inert unless the start script sets `dev_combatlog=1`.
--------------------------------------------------------------------------------

local modOptions = Spring.GetModOptions() or {}
local enabled = tostring(modOptions.dev_combatlog or "") == "1"

function gadget:GetInfo()
	return {
		name    = "Dev Combat Log",
		desc    = "Per-unit death events and army snapshots for offline battle reconstruction.",
		author  = "bar-ai",
		date    = "2026",
		license = "GNU GPL, v2 or later",
		layer   = 1002,
		enabled = enabled,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return
end

local SNAP_INTERVAL = 30 * 10  -- army snapshot every 10 game-seconds
local nextSnap = SNAP_INTERVAL

local aiTeam = {}      -- teamID -> true for AI-controlled teams
local startX, startZ = {}, {}  -- teamID -> start position, for retreat headings

-- def caches
local costOf, mobileArmed, isCommander = {}, {}, {}

local function defFacts(udid)
	local c = costOf[udid]
	if c == nil then
		local ud = UnitDefs[udid]
		c = (ud and ud.metalCost) or 0
		costOf[udid] = c
		mobileArmed[udid] = ud ~= nil and (ud.speed or 0) > 0
			and ud.weapons ~= nil and #ud.weapons > 0
		isCommander[udid] = ud ~= nil and (ud.customParams or {}).iscommander ~= nil
	end
	return c
end

function gadget:GameStart()
	for _, teamID in ipairs(Spring.GetTeamList()) do
		local _, _, _, isAI = Spring.GetTeamInfo(teamID, false)
		if isAI then
			aiTeam[teamID] = true
			local x, _, z = Spring.GetTeamStartPosition(teamID)
			startX[teamID], startZ[teamID] = x or 0, z or 0
			Spring.Echo(string.format("[BARAI_START] team=%d x=%d z=%d",
				teamID, startX[teamID], startZ[teamID]))
		end
	end
end

function gadget:UnitDestroyed(unitID, unitDefID, unitTeam, attackerID, attackerDefID, attackerTeam)
	if not aiTeam[unitTeam] then
		return
	end
	local cost = defFacts(unitDefID)
	local ud = UnitDefs[unitDefID]
	local x, _, z = Spring.GetUnitPosition(unitID)
	if x == nil then
		return
	end
	local vx, _, vz = Spring.GetUnitVelocity(unitID)
	local _, buildProgress = Spring.GetUnitIsBeingBuilt(unitID)
	local built = 1
	if buildProgress ~= nil and buildProgress < 1 then
		built = 0
	end
	local atkName, ax, az = "?", -1, -1
	if attackerDefID ~= nil and UnitDefs[attackerDefID] ~= nil then
		atkName = UnitDefs[attackerDefID].name
	end
	if attackerID ~= nil then
		local px, _, pz = Spring.GetUnitPosition(attackerID)
		if px then
			ax, az = px, pz
		end
	end
	Spring.Echo(string.format(
		"[BARAI_DEATH] frame=%d team=%d unit=%s cost=%d x=%d z=%d vx=%.1f vz=%.1f built=%d mob=%d atkteam=%d atk=%s atkx=%d atkz=%d",
		Spring.GetGameFrame(), unitTeam, (ud and ud.name) or "?", cost, x, z,
		vx or 0, vz or 0, built, mobileArmed[unitDefID] and 1 or 0,
		attackerTeam or -1, atkName, ax, az))
end

local function snapshot(frame)
	for teamID in pairs(aiTeam) do
		local out = {}
		for _, uid in ipairs(Spring.GetTeamUnits(teamID) or {}) do
			local udid = Spring.GetUnitDefID(uid)
			if udid then
				defFacts(udid)
				if mobileArmed[udid] then
					local x, _, z = Spring.GetUnitPosition(uid)
					local hp, maxhp = Spring.GetUnitHealth(uid)
					if x and hp and maxhp and maxhp > 0 then
						local ud = UnitDefs[udid]
						out[#out + 1] = string.format("%d:%s:%d:%d:%d",
							uid, ud.name, x, z,
							math.floor(hp / maxhp * 100 + 0.5))
					end
				end
			end
		end
		if #out > 0 then
			Spring.Echo(string.format("[BARAI_ARMY] frame=%d team=%d n=%d %s",
				frame, teamID, #out, table.concat(out, ",")))
		end
	end
end

function gadget:GameFrame(frame)
	if frame >= nextSnap then
		nextSnap = frame + SNAP_INTERVAL
		snapshot(frame)
	end
end
