-- dev_armynet.lua -- let the army model (tools/armynet/serve.py) fight for our side in a local game.
--
-- Inert unless the start script sets dev_armynet=1 (run_match.py --modoption dev_armynet=1). On the ally
-- dev_armynet_ally (default 0), each finished army/air/radar/jammer unit of an Apex team is marked
-- disableAiControl, and barai_handsoff is set, so our AI drops it from its own control (CCircuitAI::Update)
-- while still owning and counting it: our AI keeps the economy and production, the model the army.
-- Every game second the unsynced half writes the side's view to armynet_state.txt in the write dir (the replay
-- recorder's line format, tools/replay_orders.py); serve.py answers in armynet_orders.txt, which this
-- half reads and passes to the synced half, which orders marked units only. Local games only.

function gadget:GetInfo()
	return { name = "BARAI armynet bridge", desc = "the army model fights for our side (dev)", author = "bar-ai",
		date = "2026-11-18", license = "GNU GPL, v2 or later", layer = 0, enabled = true }
end

local mo = Spring.GetModOptions and Spring.GetModOptions() or {}
if mo.dev_armynet ~= "1" then
	return
end
local ALLY = tonumber(mo.dev_armynet_ally or "0") or 0
-- unit types our AI keeps (dev_armynet_keep, its own scout role list): it scouts with them (11-20)
local KEEP = {}
for name in (mo.dev_armynet_keep or ""):gmatch("[^,]+") do KEEP[name] = true end

local function isFocus(ud)
	if not ud or ud.isBuilding or (ud.speed or 0) <= 0 then return false end
	if KEEP[ud.name] then return false end
	if ud.customParams and ud.customParams.iscommander then return false end
	if ud.isBuilder or (ud.buildSpeed or 0) > 0 then return false end
	if #(ud.weapons or {}) > 0 then return true end
	return (ud.radarDistance or ud.radarRadius or 0) > 0 or (ud.radarDistanceJam or ud.jammerRadius or 0) > 0
end

local function holders()
	-- the Apex teams on ALLY; each is its own holder (the pairs format is kept: team,team)
	local map = {}
	for _, t in ipairs(Spring.GetTeamList()) do
		local _, _, _, isAI, _, ally = Spring.GetTeamInfo(t)
		if isAI and ally == ALLY then
			local _, _, _, short = Spring.GetAIInfo(t)
			if (short or ""):sub(1, 4) == "Apex" then map[t] = t end
		end
	end
	return map
end

if gadgetHandler:IsSyncedCode() then
	local controlled = {}
	local marked, applied, released, retaken = 0, 0, 0, 0
	local relUntil = {}   -- serve --hybrid: uid -> the frame it returns to the model

	local function mark(uid)
		if Spring.GetUnitRulesParam(uid, "disableAiControl") ~= 1 then
			Spring.SetUnitRulesParam(uid, "disableAiControl", 1)
			marked = marked + 1
		end
	end

	-- synced code cannot read AI names (GetAIInfo hides them here); the unsynced half sends the teams
	local function setPairs(body)
		for a in body:gmatch("(%d+),%d+") do
			local t = tonumber(a)
			if not controlled[t] then
				controlled[t] = true
				for _, uid in ipairs(Spring.GetTeamUnits(t)) do
					local _, _, _, _, bp = Spring.GetUnitHealth(uid)
					if (bp or 0) >= 1 and isFocus(UnitDefs[Spring.GetUnitDefID(uid)]) then mark(uid) end
				end
				Spring.Echo("[BARAI_ARMYNET] model commands team " .. t)
			end
		end
	end

	function gadget:Initialize()
		Spring.SetGameRulesParam("barai_handsoff", 1)
	end

	function gadget:UnitFinished(unitID, unitDefID, unitTeam)
		if controlled[unitTeam] and isFocus(UnitDefs[unitDefID]) then mark(unitID) end
	end

	function gadget:UnitGiven(unitID, unitDefID, newTeam)
		if controlled[newTeam] and isFocus(UnitDefs[unitDefID]) then mark(unitID) end
	end

	-- hits on our side's units over the second, attacker included (a gadget is told it; a widget is not), for the
	-- model's incoming-fire layers (tools/armynet/data.py _fire_layers; the recorder's X lines in replays)
	local hits = {}
	local ourAlly = {}
	function gadget:UnitDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID, projectileID, attackerID)
		if paralyzer or not damage or damage <= 0 then return end
		if ourAlly[unitTeam] == nil then
			local _, _, _, _, _, ally = Spring.GetTeamInfo(unitTeam)
			ourAlly[unitTeam] = (ally == ALLY)
		end
		if not ourAlly[unitTeam] then return end
		-- by attacker, then victim (one packed number loses the victim's low digits in Lua's floats)
		local a = attackerID or -1
		local row = hits[a]
		if not row then row = {} hits[a] = row end
		row[unitID] = (row[unitID] or 0) + damage
	end

	local function flushHits(f)
		local parts = {}
		for a, row in pairs(hits) do
			for v, amount in pairs(row) do
				parts[#parts + 1] = string.format("%d,%d,%.0f", a, v, amount)
			end
		end
		hits = {}
		SendToUnsynced("armynetHits", f, table.concat(parts, ";"))
	end

	function gadget:GameFrame(f)
		if f % 10 == 9 then flushHits(f + 1) end
		if f % 15 == 0 then
			for uid, backAt in pairs(relUntil) do
				if f >= backAt then
					relUntil[uid] = nil
					if Spring.ValidUnitID(uid) and not Spring.GetUnitIsDead(uid) then
						Spring.SetUnitRulesParam(uid, "disableAiControl", 1)
						retaken = retaken + 1
					end
				end
			end
		end
		if f % 1800 == 0 and f > 0 then
			Spring.Echo(string.format("[BARAI_ARMYNET] minute %d units marked %d orders applied %d released %d retaken %d", f / 1800, marked, applied, released, retaken))
		end
	end

	-- "armynet:uid,cmd,x,z;uid,20,target;..."
	function gadget:RecvLuaMsg(msg, playerID)
		if msg:sub(1, 13) == "armynetpairs:" then
			setPairs(msg:sub(14))
			return true
		end
		if msg:sub(1, 8) ~= "armynet:" then return end
		for item in msg:sub(9):gmatch("[^;]+") do
			local f = {}
			for v in item:gmatch("[^,]+") do f[#f + 1] = tonumber(v) end
			local uid, cmd = f[1], f[2]
			if cmd == -1 and uid and f[3] and Spring.ValidUnitID(uid) and controlled[Spring.GetUnitTeam(uid)] then
				-- serve --hybrid: the unit goes back to the AI's own fight logic for f[3] frames, renewed while in contact
				if Spring.GetUnitRulesParam(uid, "disableAiControl") == 1 then
					Spring.SetUnitRulesParam(uid, "disableAiControl", 0)
					released = released + 1
				end
				relUntil[uid] = Spring.GetGameFrame() + f[3]
			elseif uid and cmd and Spring.ValidUnitID(uid) and controlled[Spring.GetUnitTeam(uid)]
				and Spring.GetUnitRulesParam(uid, "disableAiControl") == 1 then
				applied = applied + 1
				if cmd == CMD.STOP then
					Spring.GiveOrderToUnit(uid, CMD.STOP, {}, 0)
				elseif cmd == CMD.ATTACK and #f == 3 then
					if Spring.ValidUnitID(f[3]) then Spring.GiveOrderToUnit(uid, CMD.ATTACK, { f[3] }, 0) end
				elseif #f >= 4 then
					local x, z = f[3], f[4]
					Spring.GiveOrderToUnit(uid, cmd, { x, Spring.GetGroundHeight(x, z), z }, 0)
				end
			end
		end
		return true
	end
else
	local STATE, ORDERS, STATIC = "armynet_state.txt", "armynet_orders.txt", "armynet_static.txt"
	local classOf, allies, holderList = {}, {}, {}
	local lastOrders = -1

	local function cls(ud)
		if ud.customParams and ud.customParams.iscommander then return "com" end
		if (ud.speed or 0) <= 0 or ud.isBuilding then return "static" end
		if ud.isBuilder or (ud.buildSpeed or 0) > 0 then return "builder" end
		if (ud.radarDistanceJam or ud.jammerRadius or 0) > 0 then return "jammer" end
		if (ud.radarDistance or ud.radarRadius or 0) > 0 and #(ud.weapons or {}) == 0 then return "radar" end
		if ud.canFly then return "air" end
		if #(ud.weapons or {}) > 0 then return "army" end
		return "other"
	end

	local function weaponStats(ud)
		local range, ground, aa = 0, 0, 0
		for _, w in ipairs(ud.weapons or {}) do
			local wd = WeaponDefs[w.weaponDef]
			if wd then
				local d = 0
				pcall(function() d = (wd.damages and (wd.damages[0] or wd.damages.default)) or 0 end)
				local per = d * (wd.salvoSize or 1) * (wd.projectiles or 1) / math.max(wd.reload or 1, 0.03)
				local only = w.onlyTargets or {}
				if only.vtol and not only.notair and not only.surface and not only.ground then
					aa = aa + per
				else
					ground = ground + per
					range = math.max(range, wd.range or 0)
				end
			end
		end
		return range, ground, aa
	end

	local lastHits = {}
	local function onHits(_, f, body)
		lastHits = { frame = f, body = body }
	end

	function gadget:Initialize()
		gadgetHandler:AddSyncAction("armynetHits", onHits)
		local m = holders()
		local seen = {}
		for src, h in pairs(m) do
			if not seen[h] then holderList[#holderList + 1] = { h, src } seen[h] = true end
		end
		local fh = io.open(STATIC, "w")
		if not fh then
			Spring.Echo("[BARAI_ARMYNET] cannot write " .. STATIC)
			return
		end
		fh:write(string.format("V 2 %d %d\n", Game.mapSizeX, Game.mapSizeZ))
		for id, ud in pairs(UnitDefs) do
			classOf[id] = cls(ud)
			local r, g, a = weaponStats(ud)
			fh:write(string.format("D %d %s %s %.0f %.0f %.1f %.0f %.1f %.1f %.0f %.0f %.0f\n", id, ud.name, classOf[id],
				ud.metalCost or 0, ud.health or 0, ud.speed or 0, r, g, a, ud.sightDistance or ud.losRadius or 0,
				ud.radarDistance or ud.radarRadius or 0, ud.radarDistanceJam or ud.jammerRadius or 0))
		end
		local gaiaAlly = select(6, Spring.GetTeamInfo(Spring.GetGaiaTeamID()))
		for _, a in ipairs(Spring.GetAllyTeamList()) do
			if a ~= gaiaAlly then allies[#allies + 1] = a end
		end
		fh:write("A " .. table.concat(allies, " ") .. "\n")
		for _, t in ipairs(Spring.GetTeamList()) do
			local _, _, _, isAI, _, ally = Spring.GetTeamInfo(t)
			fh:write(string.format("T %d %d %s\n", t, ally or -1, tostring(isAI)))
		end
		for _, hs in ipairs(holderList) do fh:write(string.format("Q %d %d\n", hs[1], hs[2])) end
		local n = Spring.GetGameRulesParam("mex_count") or 0
		for i = 1, n do
			fh:write(string.format("S %d %.0f %.0f\n", i, Spring.GetGameRulesParam("mex_x" .. i) or -1,
				Spring.GetGameRulesParam("mex_z" .. i) or -1))
		end
		local step, hs = 64, {}
		for z = step / 2, Game.mapSizeZ, step do
			for x = step / 2, Game.mapSizeX, step do
				hs[#hs + 1] = string.format("%.0f", Spring.GetGroundHeight(x, z))
			end
		end
		fh:write("H " .. step .. " " .. table.concat(hs, " ") .. "\n")
		fh:close()
		Spring.Echo("[BARAI_ARMYNET] bridge on, holders " .. #holderList)
	end

	local function sightMask(uid)
		local m = 0
		for i, a in ipairs(allies) do
			local raw = Spring.GetUnitLosState(uid, a, true) or 0
			m = m + (raw % 4) * (4 ^ (i - 1))
		end
		return m
	end

	local function writeState(frame)
		local out = {}
		out[#out + 1] = "F " .. frame
		for _, uid in ipairs(Spring.GetAllUnits()) do
			local d = Spring.GetUnitDefID(uid)
			if d then
				local x, _, z = Spring.GetUnitPosition(uid)
				local vx, _, vz = Spring.GetUnitVelocity(uid)
				local h, mh, _, _, bp = Spring.GetUnitHealth(uid)
				local c, tx, tz = -1, -1, -1
				if classOf[d] ~= "static" then
					local q = Spring.GetUnitCommands(uid, 1)
					if q and q[1] then
						c = q[1].id
						local p = q[1].params or {}
						if #p >= 3 then tx, tz = p[1], p[3]
						elseif #p == 1 then
							local ux, _, uz = Spring.GetUnitPosition(p[1])
							tx, tz = ux or -1, uz or -1
						end
					end
				end
				out[#out + 1] = string.format("U %d %d %d %d %.0f %.0f %.1f %.1f %.2f %.2f %d %d %.0f %.0f", frame, uid, d,
					Spring.GetUnitTeam(uid), x or -1, z or -1, (vx or 0) * 30, (vz or 0) * 30,
					(h or 0) / math.max(mh or 1, 1), bp or 1, sightMask(uid), c, tx, tz)
			end
		end
		-- the last second's hits on our side, "X frame attacker victim damage" as the replay recorder writes them
		for item in (lastHits.body or ""):gmatch("[^;]+") do
			local a, v, dmg = item:match("(-?%d+),(%d+),([%d.]+)")
			if a then out[#out + 1] = string.format("X %d %s %s %s", lastHits.frame or frame, a, v, dmg) end
		end
		out[#out + 1] = "E " .. frame
		local fh = io.open(STATE, "w")
		if fh then
			fh:write(table.concat(out, "\n") .. "\n")
			fh:close()
		end
	end

	local function readOrders()
		local fh = io.open(ORDERS, "r")
		if not fh then return end
		local head = fh:read("*l")
		local frame = head and tonumber(head:match("^O (%d+)"))
		if not frame or frame <= lastOrders then
			fh:close()
			return
		end
		local body = fh:read("*a") or ""
		fh:close()
		if not body:find("\nE\n") and body:sub(-2) ~= "E\n" then return end
		lastOrders = frame
		local batch, n = {}, 0
		for ln in body:gmatch("[^\n]+") do
			if ln ~= "E" then
				batch[#batch + 1] = ln
				n = n + 1
				if #batch >= 40 then
					Spring.SendLuaRulesMsg("armynet:" .. table.concat(batch, ";"))
					batch = {}
				end
			end
		end
		if #batch > 0 then Spring.SendLuaRulesMsg("armynet:" .. table.concat(batch, ";")) end
		if frame % 900 == 0 or n > 0 and frame % 300 == 0 then
			Spring.Echo(string.format("[BARAI_ARMYNET] frame %d orders %d", frame, n))
		end
	end

	function gadget:GameFrame(frame)
		if #holderList == 0 then return end
		if frame < 300 and frame % 30 == 1 then
			local p = {}
			for _, hs in ipairs(holderList) do p[#p + 1] = hs[2] .. "," .. hs[1] end
			Spring.SendLuaRulesMsg("armynetpairs:" .. table.concat(p, ";"))
		end
		if frame % 10 == 0 then writeState(frame) end  -- every 10 frames (his 11-19: decisions under 500 ms)
		if frame % 10 == 5 then readOrders() end
	end
end
