function widget:GetInfo()
	return { name = "BARAI order capture", desc = "orders, per-allyteam sight, deaths and damage, from a replay",
		author = "bar-ai", layer = 0, enabled = true }
end

local out, maxFrame
local classOf, mobileDef = {}, {}
local allies = {}
local dmg = {}
local GetUnitLosState = Spring.GetUnitLosState

local function cls(ud)
	if ud.customParams and ud.customParams.iscommander then return "com" end
	local mobile = (ud.speed or 0) > 0 and not ud.isBuilding
	if not mobile then return "static" end
	if ud.isBuilder or (ud.buildSpeed or 0) > 0 then return "builder" end
	if (ud.radarDistanceJam or ud.jammerRadius or 0) > 0 then return "jammer" end
	if (ud.radarDistance or ud.radarRadius or 0) > 0 and #(ud.weapons or {}) == 0 then return "radar" end
	if ud.canFly then return "air" end
	if #(ud.weapons or {}) > 0 then return "army" end
	return "other"
end

local function weaponStats(ud)
	local range, dps, aa, ground = 0, 0, 0, 0
	for _, w in ipairs(ud.weapons or {}) do
		local wd = WeaponDefs[w.weaponDef]
		if wd then
			local d = 0
			pcall(function() d = (wd.damages and (wd.damages[0] or wd.damages.default)) or 0 end)
			local per = d * (wd.salvoSize or 1) * (wd.projectiles or 1) / math.max(wd.reload or 1, 0.03)
			local only = w.onlyTargets or {}
			local aaOnly = only.vtol and not only.notair and not only.surface and not only.ground
			if aaOnly then
				aa = aa + per
			else
				ground = ground + per
				range = math.max(range, wd.range or 0)
			end
			dps = dps + per
		end
	end
	return range, ground, aa
end

function widget:Initialize()
	if not Spring.IsReplay() then
		widgetHandler:RemoveWidget(self)
		return
	end
	local f = io.open("LuaUI/Config/orders_maxframe.txt", "r")
	maxFrame = f and tonumber(f:read("*l")) or 1e9
	if f then f:close() end
	out = io.open("LuaUI/Config/orders.txt", "w")
	out:write(string.format("V 2 %d %d\n", Game.mapSizeX, Game.mapSizeZ))
	for id, ud in pairs(UnitDefs) do
		classOf[id] = cls(ud)
		mobileDef[id] = classOf[id] ~= "static"
		local r, g, a = weaponStats(ud)
		out:write(string.format("D %d %s %s %.0f %.0f %.1f %.0f %.1f %.1f %.0f %.0f %.0f\n", id, ud.name, classOf[id],
			ud.metalCost or 0, ud.health or 0, ud.speed or 0, r, g, a, ud.sightDistance or ud.losRadius or 0,
			ud.radarDistance or ud.radarRadius or 0, ud.radarDistanceJam or ud.jammerRadius or 0))
	end
	for _, a in ipairs(Spring.GetAllyTeamList()) do
		if a ~= select(6, Spring.GetTeamInfo(Spring.GetGaiaTeamID())) then allies[#allies + 1] = a end
	end
	out:write("A " .. table.concat(allies, " ") .. "\n")
	for _, t in ipairs(Spring.GetTeamList()) do
		local _, _, _, isAI, _, ally = Spring.GetTeamInfo(t)
		out:write(string.format("T %d %d %s\n", t, ally or -1, tostring(isAI)))
	end
	local n = Spring.GetGameRulesParam("mex_count") or 0
	for i = 1, n do
		out:write(string.format("S %d %.0f %.0f\n", i, Spring.GetGameRulesParam("mex_x" .. i) or -1,
			Spring.GetGameRulesParam("mex_z" .. i) or -1))
	end
	local step = 64
	local hs = {}
	for z = step / 2, Game.mapSizeZ, step do
		for x = step / 2, Game.mapSizeX, step do
			hs[#hs + 1] = string.format("%.0f", Spring.GetGroundHeight(x, z))
		end
	end
	out:write("H " .. step .. " " .. table.concat(hs, " ") .. "\n")
	Spring.SendCommands({ "specfullview 1", "setmaxspeed 1000", "setminspeed 1000" })
end

local function optStr(o)
	if type(o) ~= "table" then return tostring(o) end
	return (o.shift and "s" or "") .. (o.ctrl and "c" or "") .. (o.alt and "a" or "") .. (o.meta and "m" or "") .. (o.right and "r" or "")
end

local function params(ps)
	local s = {}
	for i = 1, math.min(#ps, 4) do s[i] = string.format("%.0f", ps[i]) end
	return table.concat(s, ",")
end

function widget:UnitCommand(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOpts, cmdTag)
	if not out then return end
	local x, _, z = Spring.GetUnitPosition(unitID)
	out:write(string.format("C %d %d %d %d %d %s %.0f %.0f %s\n", Spring.GetGameFrame(), unitTeam, unitID,
		unitDefID or -1, cmdID, optStr(cmdOpts), x or -1, z or -1, params(cmdParams)))
end

function widget:UnitDestroyed(unitID, unitDefID, unitTeam, attackerID, attackerDefID, attackerTeam)
	if not out then return end
	local x, _, z = Spring.GetUnitPosition(unitID)
	out:write(string.format("K %d %d %d %d %.0f %.0f %d %d %d\n", Spring.GetGameFrame(), unitID, unitDefID or -1,
		unitTeam or -1, x or -1, z or -1, attackerID or -1, attackerDefID or -1, attackerTeam or -1))
end

function widget:UnitFinished(unitID, unitDefID, unitTeam)
	if not out then return end
	local x, _, z = Spring.GetUnitPosition(unitID)
	out:write(string.format("F %d %d %d %d %.0f %.0f\n", Spring.GetGameFrame(), unitID, unitDefID or -1, unitTeam, x or -1, z or -1))
end

function widget:UnitGiven(unitID, unitDefID, newTeam, oldTeam)
	if not out then return end
	out:write(string.format("G %d %d %d %d\n", Spring.GetGameFrame(), unitID, newTeam, oldTeam))
end

-- BAR's handler passes widgets no attacker (and refuses user widgets the handler); the engine's
-- last-attacker record names it. -1 when absent: tools/replay_dataset.py shares that among the enemies in reach.
local GetUnitLastAttacker = Spring.GetUnitLastAttacker
function widget:UnitDamaged(unitID, unitDefID, unitTeam, damage, paralyzer)
	if not out or paralyzer or not damage or damage <= 0 then return end
	local a = (GetUnitLastAttacker and GetUnitLastAttacker(unitID)) or -1
	-- by attacker, then victim: one number (a * 2^20 + victim) lost the victim's low digits in Lua's floats once
	-- attackers were known (11-19: victims read 2048, 3072, 768 ...)
	local row = dmg[a]
	if not row then row = {} dmg[a] = row end
	row[unitID] = (row[unitID] or 0) + damage
end

local function sightMask(uid)
	local m = 0
	for i, a in ipairs(allies) do
		local raw = GetUnitLosState(uid, a, true) or 0
		m = m + (raw % 4) * (4 ^ (i - 1))
	end
	return m
end

local function sample(frame, statics)
	for _, uid in ipairs(Spring.GetAllUnits()) do
		local d = Spring.GetUnitDefID(uid)
		if d and (mobileDef[d] or statics) then
			local x, _, z = Spring.GetUnitPosition(uid)
			local vx, _, vz = Spring.GetUnitVelocity(uid)
			local h, mh, _, _, bp = Spring.GetUnitHealth(uid)
			local c, tx, tz = -1, -1, -1
			if mobileDef[d] then
				local q = Spring.GetUnitCommands(uid, 1)
				if q and q[1] then
					c = q[1].id
					local p = q[1].params or {}
					if #p >= 3 then
						tx, tz = p[1], p[3]
					elseif #p == 1 then
						local ux, _, uz = Spring.GetUnitPosition(p[1])
						tx, tz = ux or -1, uz or -1
					end
				end
			end
			out:write(string.format("U %d %d %d %d %.0f %.0f %.1f %.1f %.2f %.2f %d %d %.0f %.0f\n", frame, uid, d,
				Spring.GetUnitTeam(uid), x or -1, z or -1, (vx or 0) * 30, (vz or 0) * 30, (h or 0) / math.max(mh or 1, 1),
				bp or 1, sightMask(uid), c, tx, tz))
		end
	end
end

local nextSpeed = 300
function widget:GameFrame(frame)
	if not out then return end
	-- every 10 frames (his 11-19: decisions under 500 ms; players re-order a unit in a fight every 0.23 s median)
	if frame % 10 == 0 then
		for a, row in pairs(dmg) do
			for v, amount in pairs(row) do
				out:write(string.format("X %d %d %d %.0f\n", frame, a, v, amount))
			end
		end
		dmg = {}
		sample(frame, frame % 300 == 0)
	end
	if frame >= nextSpeed then
		nextSpeed = frame + 300
		Spring.SendCommands({ "setmaxspeed 1000", "setminspeed 1000" })
		out:flush()
	end
	if frame >= maxFrame then
		out:close()
		out = nil
		Spring.SendCommands("quitforce")
	end
end

function widget:GameOver(winners)
	if out then
		out:write(string.format("W %d %s\n", Spring.GetGameFrame(), table.concat(winners or {}, ",")))
		out:close()
		out = nil
	end
	Spring.SendCommands("quitforce")
end

function widget:Shutdown()
	if out then out:close() out = nil end
end
