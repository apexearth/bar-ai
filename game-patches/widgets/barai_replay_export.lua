--------------------------------------------------------------------------------
-- barai_replay_export.lua -- the dev gadgets' event lines, from a REPLAY.
--
-- His multiplayer games (2026-10-07) run on the official archive, so none of
-- the dev gadgets (dev_stats_export, dev_combat_log, dev_team_income,
-- dev_autoquit) ran in them and our AI's decisions have no outcomes to learn
-- from. Played back headless (tools/replay_extract.py), this widget -- a
-- spectator with full view, unsynced, so the replay stays valid -- writes the
-- same [BARAI_*] lines tools/decisions.py reads: PROD, BUILD, DEATH, DMG,
-- WASTE, STATS and RESULT, for every team.
--------------------------------------------------------------------------------

function widget:GetInfo()
	return {
		name    = "BARAI replay export",
		desc    = "Event lines for training, written while a replay plays.",
		author  = "bar-ai",
		date    = "2026",
		license = "GNU GPL, v2 or later",
		layer   = 0,
		enabled = true,
	}
end

local echo = Spring.Echo
local GetGameFrame = Spring.GetGameFrame
local GetTeamInfo = Spring.GetTeamInfo
local GetTeamResources = Spring.GetTeamResources
local GetUnitPosition = Spring.GetUnitPosition

local allyOf = {}
local fromFactory = {}
local dmg = {}       -- team -> {dm, ds, rm, rs}
local waste = {}     -- team -> {mW, mI, eW, eI}
local isStatic = {}
local mobileArmed = {}

local function ally(team)
	local a = allyOf[team]
	if a == nil then
		a = select(6, GetTeamInfo(team, false)) or 0
		allyOf[team] = a
	end
	return a
end

local function d(team)
	local t = dmg[team]
	if t == nil then
		t = { dm = 0, ds = 0, rm = 0, rs = 0 }
		dmg[team] = t
	end
	return t
end

function widget:Initialize()
	if not Spring.IsReplay() then
		widgetHandler:RemoveWidget(self)
		return
	end
	for id, ud in pairs(UnitDefs) do
		isStatic[id] = ud.isBuilding or ((ud.speed or 0) == 0)
		mobileArmed[id] = (not isStatic[id]) and (#(ud.weapons or {}) > 0)
	end
	-- a replay plays at 1x unless told otherwise
	Spring.SendCommands("setmaxspeed 200", "setminspeed 200")
	echo("[BARAI_REPLAY] export on")
end

function widget:UnitFromFactory(unitID, unitDefID, unitTeam, factID, factDefID)
	local ud, fd = UnitDefs[unitDefID], UnitDefs[factDefID]
	if ud == nil or fd == nil then
		return
	end
	fromFactory[unitID] = true
	local f = GetGameFrame()
	echo(string.format("[BARAI_PROD] team=%d ally=%d frame=%d min=%.2f unit=%s cost=%d fac=%s uid=%d facid=%d",
		unitTeam, ally(unitTeam), f, f / 1800, ud.name, ud.metalCost or 0, fd.name, unitID, factID))
end

function widget:UnitFinished(unitID, unitDefID, unitTeam)
	local ud = UnitDefs[unitDefID]
	if ud == nil or not isStatic[unitDefID] then
		return
	end
	local f = GetGameFrame()
	local bx, _, bz = GetUnitPosition(unitID)
	echo(string.format("[BARAI_BUILD] team=%d ally=%d frame=%d min=%.2f unit=%s cost=%d x=%d z=%d uid=%d",
		unitTeam, ally(unitTeam), f, f / 1800, ud.name, ud.metalCost or 0,
		math.floor(bx or -1), math.floor(bz or -1), unitID))
end

function widget:UnitDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID, projectileID,
		attackerID, attackerDefID, attackerTeam)
	if paralyzer or (damage or 0) <= 0 then
		return
	end
	local hp = Spring.GetUnitHealth(unitID)
	local eff = damage
	if hp ~= nil and hp > 0 and hp < eff then
		eff = hp
	end
	local vs = isStatic[unitDefID]
	local v = d(unitTeam)
	if vs then v.rs = v.rs + eff else v.rm = v.rm + eff end
	if attackerTeam ~= nil and attackerTeam ~= unitTeam then
		local a = d(attackerTeam)
		if vs then a.ds = a.ds + eff else a.dm = a.dm + eff end
	end
end

function widget:UnitDestroyed(unitID, unitDefID, unitTeam, attackerID, attackerDefID, attackerTeam)
	local ud = UnitDefs[unitDefID]
	local x, _, z = GetUnitPosition(unitID)
	fromFactory[unitID] = nil
	if ud == nil or x == nil then
		return
	end
	local vx, _, vz = Spring.GetUnitVelocity(unitID)
	local _, prog = Spring.GetUnitIsBeingBuilt(unitID)
	local built = ((prog ~= nil) and (prog < 1)) and 0 or 1
	local atkName, ax, az = "?", -1, -1
	if attackerDefID ~= nil and UnitDefs[attackerDefID] ~= nil then
		atkName = UnitDefs[attackerDefID].name
	end
	if attackerID ~= nil then
		local px, _, pz = GetUnitPosition(attackerID)
		if px then
			ax, az = px, pz
		end
	end
	echo(string.format(
		"[BARAI_DEATH] frame=%d team=%d unit=%s cost=%d x=%d z=%d vx=%.1f vz=%.1f built=%d mob=%d atkteam=%d atk=%s atkx=%d atkz=%d st=%d ffdg=0 uid=%d atkid=%d",
		GetGameFrame(), unitTeam, ud.name, ud.metalCost or 0, x, z, vx or 0, vz or 0, built,
		mobileArmed[unitDefID] and 1 or 0, attackerTeam or -1, atkName, ax, az,
		isStatic[unitDefID] and 1 or 0, unitID, attackerID or -1))
end

function widget:GameFrame(f)
	if f % 30 == 0 then
		for _, team in ipairs(Spring.GetTeamList()) do
			if team ~= Spring.GetGaiaTeamID() then
				local _, _, _, mInc, _, _, _, _, mExc = GetTeamResources(team, "metal")
				local _, _, _, eInc, _, _, _, _, eExc = GetTeamResources(team, "energy")
				if mInc ~= nil then
					local w = waste[team]
					if w == nil then
						w = { mW = 0, mI = 0, eW = 0, eI = 0 }
						waste[team] = w
					end
					w.mW = w.mW + (mExc or 0)
					w.mI = w.mI + mInc
					w.eW = w.eW + (eExc or 0)
					w.eI = w.eI + (eInc or 0)
				end
			end
		end
	end
	if f % 300 == 0 then
		for team, t in pairs(dmg) do
			echo(string.format("[BARAI_DMG] frame=%d team=%d dm=%d ds=%d rm=%d rs=%d", f, team, t.dm, t.ds, t.rm, t.rs))
		end
	end
	if f % 1800 == 0 then
		for team, w in pairs(waste) do
			echo(string.format("[BARAI_WASTE] frame=%d team=%d mWaste=%.0f mMade=%.0f eWaste=%.0f eMade=%.0f",
				f, team, w.mW, w.mI, w.eW, w.eI))
			echo(string.format("[BARAI_STATS] team=%d ally=%d frame=%d mReclaim=0", team, ally(team), f))
		end
	end
end

function widget:GameOver(winners)
	local list = {}
	for _, a in ipairs(winners or {}) do
		list[#list + 1] = tostring(a)
	end
	echo(string.format("[BARAI_RESULT] reason=gameover frame=%d winners=%s", GetGameFrame(), table.concat(list, ",")))
	Spring.SendCommands("quitforce")
end
