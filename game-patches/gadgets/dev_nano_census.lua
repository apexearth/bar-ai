--------------------------------------------------------------------------------
-- dev_nano_census.lua -- where each team's nano-turret build power goes.
--
-- An AI cannot see what a patrolling turret is working on; the engine picks its
-- assist target. Synced Lua can: GetUnitIsBuilding is the buildee whatever
-- ordered it. Every 10 s, per team, the turrets' build power is split by what it
-- is building -- a mobile unit (factory production), an economy structure, any
-- other structure, a repair -- or idle, plus how much of it went to ANOTHER
-- team's build (an ally's factory). Harness telemetry only; no game state.
--
--   [BARAI_NANO] frame= team= n= bp= units= eco= struct= repair= idle= ally=
--------------------------------------------------------------------------------

local function BARAI_Echo(line)
	if GG and GG.BARAI_LOG then
		GG.BARAI_LOG(line)
	else
		Spring.Echo(line)
	end
end

function gadget:GetInfo()
	return {
		name    = "Dev Nano Census",
		desc    = "Logs where each team's nano-turret build power goes.",
		author  = "bar-ai",
		date    = "2026",
		license = "GNU GPL, v2 or later",
		layer   = 1003,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return
end

local INTERVAL = 300   -- 10 s

local nanoDefs = {}      -- defID -> build speed, for turrets only
local nanoDefList = {}
local isEco = {}         -- defID -> true for economy structures

function gadget:Initialize()
	for id, ud in pairs(UnitDefs) do
		local name = ud.name or ""
		if ud.isBuilder and (ud.speed or 0) == 0 and string.find(name, "nanotc", 1, true) then
			nanoDefs[id] = ud.buildSpeed or 0
			nanoDefList[#nanoDefList + 1] = id
		end
		local cp = ud.customParams or {}
		if ((ud.speed or 0) == 0) and (
				(ud.extractsMetal or 0) > 0
				or (ud.energyMake or 0) > 0
				or (ud.energyUpkeep or 0) < 0
				or (ud.windGenerator or 0) > 0
				or (ud.tidalGenerator or 0) > 0
				or tonumber(cp.energyconv_capacity or 0) > 0) then
			isEco[id] = true
		end
	end
end

function gadget:GameFrame(n)
	if n % INTERVAL ~= 0 or #nanoDefList == 0 then
		return
	end
	for _, teamID in ipairs(Spring.GetTeamList()) do
		local units = Spring.GetTeamUnitsByDefs(teamID, nanoDefList)
		if units and #units > 0 then
			local bp, bUnits, bEco, bStruct, bRepair, bIdle, bAlly = 0, 0, 0, 0, 0, 0, 0
			for i = 1, #units do
				local u = units[i]
				local w = nanoDefs[Spring.GetUnitDefID(u)] or 0
				bp = bp + w
				local _, _, _, _, buildProgress = Spring.GetUnitHealth(u)
				local target = Spring.GetUnitIsBuilding(u)
				if buildProgress and buildProgress < 1 then
					bIdle = bIdle + w   -- the turret itself is still a frame
				elseif not target then
					bIdle = bIdle + w
				else
					local tdef = Spring.GetUnitDefID(target)
					local tud = tdef and UnitDefs[tdef]
					local _, _, _, _, tProg = Spring.GetUnitHealth(target)
					if (Spring.GetUnitTeam(target) ~= teamID) then
						bAlly = bAlly + w
					end
					if tProg and tProg >= 1 then
						bRepair = bRepair + w
					elseif tud and (tud.speed or 0) > 0 then
						bUnits = bUnits + w
					elseif isEco[tdef] then
						bEco = bEco + w
					else
						bStruct = bStruct + w
					end
				end
			end
			BARAI_Echo(string.format(
				"[BARAI_NANO] frame=%d team=%d n=%d bp=%d units=%d eco=%d struct=%d repair=%d idle=%d ally=%d",
				n, teamID, #units, bp, bUnits, bEco, bStruct, bRepair, bIdle, bAlly))
		end
	end
end
