--------------------------------------------------------------------------------
-- dev_yardjam.lua -- seal a team's factory doors at a fixed minute, so the
-- yard watch (ai/Unstable/.../manager/brain/yard.as) can be judged on demand.
-- apexearth 2026-10-04: units stuck inside their factory area cannot leave.
--
-- At dev_yardjam_min, every finished ground factory of dev_yardjam_team gets a
-- row of its faction's nano turrets (owned by that team) across its door, the
-- side the engine's build facing names, flush against the footprint.
--
-- Inert unless the start script sets dev_yardjam=1.
--
--   dev_yardjam        "1" to enable
--   dev_yardjam_team   team whose plants are sealed (default 0)
--   dev_yardjam_min    minute of the seal (default 8)
--   dev_yardjam_rows   rows of turrets (default 1)
--
-- Lines:
--   [BARAI_YARDJAM]   frame= team= fac= id= facing= placed=
--   [BARAI_YARDSTATE] frame= team= fac= id= blockers= produced=
--       every 30 s after the seal: turrets of the seal still standing, and
--       units the plant has finished since it was sealed.
--------------------------------------------------------------------------------

local modOptions = Spring.GetModOptions() or {}
local enabled = tostring(modOptions.dev_yardjam or "") == "1"

local function BARAI_Echo(line)
	if GG and GG.BARAI_LOG then
		GG.BARAI_LOG(line)
	else
		Spring.Echo(line)
	end
end

function gadget:GetInfo()
	return {
		name    = "Dev Yard Jam",
		desc    = "Seals factory doors with turrets at a fixed minute for the yard test.",
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

local TEAM = tonumber(modOptions.dev_yardjam_team or 0) or 0
local AT = math.floor((tonumber(modOptions.dev_yardjam_min or 8) or 8) * 1800)
local ROWS = math.max(1, math.floor(tonumber(modOptions.dev_yardjam_rows or 1) or 1))

local sealed = {}   -- factory id -> { name, blockers = {ids}, produced = n }

local function groundPlant(ud)
	if not ud or not ud.isFactory or not ud.buildOptions then
		return false
	end
	for _, bo in ipairs(ud.buildOptions) do
		local b = UnitDefs[bo]
		if b and not b.canFly then
			return true
		end
	end
	return false
end

local function nanoFor(name)
	if name:sub(1, 3) == "cor" then return "cornanotc" end
	if name:sub(1, 3) == "leg" then return "legnanotc" end
	return "armnanotc"
end

local DIRS = { [0] = { 0, 1 }, [1] = { 1, 0 }, [2] = { 0, -1 }, [3] = { -1, 0 } }

local function seal(fid)
	local ud = UnitDefs[Spring.GetUnitDefID(fid)]
	local facing = Spring.GetUnitBuildFacing(fid) or 0
	local d = DIRS[facing] or DIRS[0]
	local x, _, z = Spring.GetUnitPosition(fid)
	local fx, fz = ud.xsize * 4, ud.zsize * 4
	local halfD = (facing % 2 == 0) and fz or fx
	local halfW = (facing % 2 == 0) and fx or fz
	local nname = nanoFor(ud.name)
	local nd = UnitDefNames[nname]
	if not nd then
		return
	end
	local nh = nd.xsize * 4
	local rec = { name = ud.name, blockers = {}, produced = 0 }
	-- Rings around the whole plant: a front row alone is walked around.
	for r = 0, ROWS - 1 do
		local ra = halfD + nh + r * 2 * nh   -- ring half-extent along the facing
		local rc = halfW + nh + r * 2 * nh   -- ...and across it
		local cells = {}
		local c = -rc
		while c <= rc + 0.1 do
			cells[#cells + 1] = { ra, c }
			cells[#cells + 1] = { -ra, c }
			c = c + 2 * nh
		end
		local a = -ra + 2 * nh
		while a <= ra - 2 * nh + 0.1 do
			cells[#cells + 1] = { a, rc }
			cells[#cells + 1] = { a, -rc }
			a = a + 2 * nh
		end
		for _, cell in ipairs(cells) do
			local along, across = cell[1], cell[2]
			local px = x + d[1] * along + d[2] * across
			local pz = z + d[2] * along - d[1] * across
			px = math.floor(px / 16 + 0.5) * 16
			pz = math.floor(pz / 16 + 0.5) * 16
			local id = Spring.CreateUnit(nname, px, Spring.GetGroundHeight(px, pz), pz, 0, TEAM)
			if id then
				rec.blockers[#rec.blockers + 1] = id
			end
		end
	end
	sealed[fid] = rec
	BARAI_Echo(string.format("[BARAI_YARDJAM] frame=%d team=%d fac=%s id=%d facing=%d placed=%d",
		Spring.GetGameFrame(), TEAM, ud.name, fid, facing, #rec.blockers))
end

function gadget:UnitFromFactory(unitID, unitDefID, unitTeam, factID)
	local rec = sealed[factID]
	if rec then
		rec.produced = rec.produced + 1
	end
end

-- Orders the team's static builders receive after the seal, by command id: who
-- keeps re-tasking a turret handed a reclaim.
local turretCmds = {}
function gadget:UnitCommand(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOpts, cmdTag, playerID, fromSynced, fromLua)
	if unitTeam ~= TEAM or Spring.GetGameFrame() < AT then
		return
	end
	local ud = UnitDefs[unitDefID]
	if not (ud and ud.isBuilder and not ud.canMove and not ud.isFactory) then
		return
	end
	local k = tostring(cmdID) .. ((cmdOpts and cmdOpts.shift) and "s" or "")
	if (cmdID == CMD.REPAIR or cmdID == CMD.RECLAIM) and cmdParams and #cmdParams == 1 then
		local onSeal = false
		for _, rec in pairs(sealed) do
			for _, b in ipairs(rec.blockers) do
				if b == cmdParams[1] then onSeal = true end
			end
		end
		k = k .. (onSeal and "seal" or "other") .. (fromLua and "L" or "") .. "p" .. tostring(playerID)
	end
	turretCmds[k] = (turretCmds[k] or 0) + 1
end

function gadget:GameFrame(frame)
	if frame > AT and (frame - AT) % 300 == 0 and next(turretCmds) then
		local s = ""
		for k, v in pairs(turretCmds) do
			s = s .. k .. ":" .. v .. ","
		end
		BARAI_Echo(string.format("[BARAI_YARDCMDS] frame=%d team=%d %s", frame, TEAM, s))
		turretCmds = {}
	end
	if frame == AT then
		for _, uid in ipairs(Spring.GetTeamUnits(TEAM) or {}) do
			local ud = UnitDefs[Spring.GetUnitDefID(uid)]
			local _, _, _, _, bp = Spring.GetUnitHealth(uid)
			if groundPlant(ud) and (bp or 0) >= 1 then
				seal(uid)
			end
		end
	end
	if frame > AT and (frame - AT) % 300 == 0 then
		for fid, rec in pairs(sealed) do
			local alive = 0
			for _, b in ipairs(rec.blockers) do
				if Spring.ValidUnitID(b) and not Spring.GetUnitIsDead(b) then
					alive = alive + 1
				end
			end
			-- What the turrets around the plant are doing, and how whole the
			-- seal is: a reclaim out-healed by patrol repair shows as orders
			-- standing against full health.
			local hp, n = 0, 0
			for _, b in ipairs(rec.blockers) do
				if Spring.ValidUnitID(b) and not Spring.GetUnitIsDead(b) then
					local h, mh = Spring.GetUnitHealth(b)
					if h and mh and mh > 0 then
						hp = hp + h / mh
						n = n + 1
					end
				end
			end
			local cmds = {}
			if Spring.ValidUnitID(fid) then
				local x, _, z = Spring.GetUnitPosition(fid)
				for _, u in ipairs(Spring.GetUnitsInCylinder(x, z, 500, TEAM) or {}) do
					local ud = UnitDefs[Spring.GetUnitDefID(u)]
					if ud and ud.isBuilder and not ud.canMove then
						local q = Spring.GetUnitCommands(u, 1)
						local c = (q and q[1]) and tostring(q[1].id) or "idle"
						cmds[c] = (cmds[c] or 0) + 1
					end
				end
			end
			local cs = ""
			for k, v in pairs(cmds) do
				cs = cs .. k .. ":" .. v .. ","
			end
			BARAI_Echo(string.format("[BARAI_YARDSTATE] frame=%d team=%d fac=%s id=%d blockers=%d/%d produced=%d dead=%d hp=%.2f turrets=%s",
				frame, TEAM, rec.name, fid, alive, #rec.blockers, rec.produced,
				Spring.ValidUnitID(fid) and 0 or 1, (n > 0) and (hp / n) or 0, cs))
		end
	end
end
