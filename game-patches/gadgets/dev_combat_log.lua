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
-- Units per [BARAI_ARMY] line. Every console line reaches gui_chat, whose
-- string.lines is quadratic in the line's length: one 25 KB census line
-- froze the game for 1.5 s every 10 s.
local SNAP_CHUNK = 10

local aiTeam = {}      -- teamID -> true for AI-controlled teams
local startX, startZ = {}, {}  -- teamID -> start position, for retreat headings

-- def caches
local costOf, mobileArmed, isCommander = {}, {}, {}
local isStatic, isConstructor = {}, {}

-- Damage accounting for docs/24's first-five-minute test, per team and
-- cumulative: damage DEALT and RECEIVED split by whether the victim was a
-- building, damage received FROM buildings, and the constructor
-- interruptions the test scores. An interruption is a constructor taking
-- enemy damage after INTERRUPT_GAP frames without any; `bib` counts only
-- those that were actually building at the time. Damage is clamped to the
-- victim's remaining health so overkill does not inflate efficiency.
local INTERRUPT_GAP = 30 * 10
local dmg = {}                 -- team -> table of counters
local conLastHit = {}          -- unitID -> frame of last enemy hit
local DMG_KEYS = { "dm", "ds", "rm", "rs", "rfs", "bi", "bib", "bd", "bdmg", "dg", "dgm", "mfo", "dgp",
	"ffdg", "ffdgm", "ffdgk" }
local isDGunWeapon = {}        -- weaponDefID -> the D-gun (type DGun), watched for projectiles
for wdid = 0, #WeaponDefs do
	local wd = WeaponDefs[wdid]
	if wd and (wd.type == "DGun" or wd.manualFire == true) then
		isDGunWeapon[wdid] = true
		Script.SetWatchProjectile(wdid, true)
	end
end
local manualEchoed = false     -- the D-gun weapon's name, echoed once when first seen
local isManual = {}            -- weaponDefID -> manual fire (the D-gun)
local lastManual = {}          -- unitID -> its last hit was a D-gun
local lastManualFF = {}        -- unitID -> that D-gun was OURS (kept apart so a
                               -- later enemy kill is not credited as a D-gun)

local function dmgOf(team)
	local t = dmg[team]
	if t == nil then
		t = {}
		for _, k in ipairs(DMG_KEYS) do
			t[k] = 0
		end
		dmg[team] = t
	end
	return t
end

local function defFacts(udid)
	local c = costOf[udid]
	if c == nil then
		local ud = UnitDefs[udid]
		c = (ud and ud.metalCost) or 0
		costOf[udid] = c
		isStatic[udid] = ud ~= nil and (ud.speed or 0) <= 0
		isConstructor[udid] = ud ~= nil and ud.isBuilder and (ud.speed or 0) > 0
		mobileArmed[udid] = ud ~= nil and (ud.speed or 0) > 0
			and ud.weapons ~= nil and #ud.weapons > 0
		isCommander[udid] = ud ~= nil and (ud.customParams or {}).iscommander ~= nil
	end
	return c
end

-- D-gun projectiles actually fired, per team: the shot itself, whatever its
-- damage is later attributed to.
function gadget:ProjectileCreated(proID, proOwnerID, weaponDefID)
	if isDGunWeapon[weaponDefID] and proOwnerID then
		local team = Spring.GetUnitTeam(proOwnerID)
		if team and aiTeam[team] then
			dmgOf(team).dgp = dmgOf(team).dgp + 1
		end
	end
end

-- Manual-fire (D-gun) orders reaching the engine, per team: whether the AI's
-- order arrives at all, against dg (hits) which says whether it fired.
local mfTrace = {}             -- unitID -> frame of its last manual-fire order
local mfCheck = {}             -- unitID -> frame at which to echo its queue (did the order land?)
function gadget:AllowCommand(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOptions, cmdTag, playerID, fromSynced, fromLua)
	if not aiTeam[unitTeam] then
		return true
	end
	local frame = Spring.GetGameFrame()
	if cmdID == CMD.MANUALFIRE then
		dmgOf(unitTeam).mfo = dmgOf(unitTeam).mfo + 1
		mfTrace[unitID] = frame
		local tx, tz = -1, -1
		if #cmdParams >= 3 then
			tx, tz = cmdParams[1], cmdParams[3]
		elseif #cmdParams == 1 then
			local px, _, pz = Spring.GetUnitPosition(cmdParams[1])
			tx, tz = px or -1, pz or -1
		end
		local ux, _, uz = Spring.GetUnitPosition(unitID)
		local dist = (ux and tx >= 0) and math.floor(math.sqrt((ux - tx) ^ 2 + (uz - tz) ^ 2)) or -1
		local _, reloaded = Spring.GetUnitWeaponState(unitID, 3)
		local eCur = Spring.GetTeamResources(unitTeam, "energy")
		local q = Spring.GetUnitCommands(unitID, 3) or {}
		local qs = {}
		for i = 1, #q do
			qs[#qs + 1] = tostring(q[i].id)
		end
		BARAI_Echo(string.format("[BARAI_MF] frame=%d team=%d unit=%d params=%d target=%s dist=%d e=%d opts=%s queue=%s",
			frame, unitTeam, unitID, #cmdParams, tostring(cmdParams[1]), dist, math.floor(eCur or 0),
			tostring(cmdOptions.coded), table.concat(qs, ",")))
		mfCheck[unitID] = frame + 1
	elseif mfTrace[unitID] and frame - mfTrace[unitID] <= 90 then
		-- What follows a D-gun order inside three seconds: the order that
		-- cancels it, if one does.
		local q = Spring.GetUnitCommands(unitID, 3) or {}
		local qs = {}
		for i = 1, #q do
			qs[#qs + 1] = tostring(q[i].id)
		end
		BARAI_Echo(string.format("[BARAI_MFNEXT] frame=%d team=%d unit=%d after=%d cmd=%d shift=%s lua=%s player=%s queue=%s",
			frame, unitTeam, unitID, frame - mfTrace[unitID], cmdID, tostring(cmdOptions.shift),
			tostring(fromLua), tostring(playerID), table.concat(qs, ",")))
	end
	return true
end

function gadget:GameStart()
	for _, teamID in ipairs(Spring.GetTeamList()) do
		local _, _, _, isAI = Spring.GetTeamInfo(teamID, false)
		if isAI then
			aiTeam[teamID] = true
			local x, _, z = Spring.GetTeamStartPosition(teamID)
			startX[teamID], startZ[teamID] = x or 0, z or 0
			BARAI_Echo(string.format("[BARAI_START] team=%d x=%d z=%d",
				teamID, startX[teamID], startZ[teamID]))
		end
	end
end

function gadget:UnitDestroyed(unitID, unitDefID, unitTeam, attackerID, attackerDefID, attackerTeam)
	if not aiTeam[unitTeam] then
		return
	end
	local cost = defFacts(unitDefID)
	if lastManual[unitID] and attackerTeam ~= nil and aiTeam[attackerTeam] and attackerTeam ~= unitTeam then
		dmgOf(attackerTeam).dgm = dmgOf(attackerTeam).dgm + cost
	end
	lastManual[unitID] = nil
	-- Killed by our OWN D-gun. Distinct from the reclaim and death-blast
	-- attributions that made every previous own-kill count wrong: this one
	-- required a manual-fire damage event from our own team first.
	local ffKill = 0
	if lastManualFF[unitID] and attackerTeam ~= nil and attackerTeam == unitTeam then
		local t = dmgOf(unitTeam)
		t.ffdgk = t.ffdgk + 1
		ffKill = 1
	end
	lastManualFF[unitID] = nil
	if isConstructor[unitDefID] then
		dmgOf(unitTeam).bd = dmgOf(unitTeam).bd + 1
	end
	conLastHit[unitID] = nil
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
	-- uid/atkid appended last (prefix parsers unchanged): a building's lifetime
	-- kills are credited by the killer's unit id (tools/decisions.py)
	BARAI_Echo(string.format(
		"[BARAI_DEATH] frame=%d team=%d unit=%s cost=%d x=%d z=%d vx=%.1f vz=%.1f built=%d mob=%d atkteam=%d atk=%s atkx=%d atkz=%d st=%d ffdg=%d uid=%d atkid=%d",
		Spring.GetGameFrame(), unitTeam, (ud and ud.name) or "?", cost, x, z,
		vx or 0, vz or 0, built, mobileArmed[unitDefID] and 1 or 0,
		attackerTeam or -1, atkName, ax, az, isStatic[unitDefID] and 1 or 0, ffKill,
		unitID, attackerID or -1))
end

function gadget:UnitDamaged(unitID, unitDefID, unitTeam, damage, paralyzer,
		weaponDefID, projectileID, attackerID, attackerDefID, attackerTeam)
	if paralyzer or damage == nil or damage <= 0 then
		return
	end
	-- OUR OWN D-GUN, WHICH NOTHING MEASURED: the same-team return below is
	-- what hid it, so every earlier count of "commander killed our units" was
	-- reclaims and the death blast instead. The D-gun does not stop at its
	-- target, so ours standing in the beam are hit by design.
	if attackerTeam ~= nil and attackerTeam == unitTeam and aiTeam[unitTeam]
		and weaponDefID ~= nil and isDGunWeapon[weaponDefID] then
		local t = dmgOf(unitTeam)
		t.ffdg = t.ffdg + 1
		local h, mh = Spring.GetUnitHealth(unitID)
		if mh ~= nil and mh > 0 then
			local d = damage
			if h ~= nil and d > h then d = h end   -- overkill is not metal lost
			t.ffdgm = t.ffdgm + defFacts(unitDefID) * d / mh
		end
		lastManualFF[unitID] = true
	end
	if attackerTeam == nil or attackerTeam == unitTeam then
		return   -- own D-gun, crashes, decay: not the fight
	end
	local victimAI, attackerAI = aiTeam[unitTeam], aiTeam[attackerTeam]
	if not victimAI and not attackerAI then
		return
	end
	defFacts(unitDefID)
	local hp = Spring.GetUnitHealth(unitID)
	local eff = damage
	if hp ~= nil and hp < eff then
		eff = hp
	end
	if eff <= 0 then
		return   -- already dead: a negative health reads as negative damage
	end
	local vStatic = isStatic[unitDefID]
	local aStatic = attackerDefID ~= nil and defFacts(attackerDefID) ~= nil
		and isStatic[attackerDefID]
	if victimAI then
		local t = dmgOf(unitTeam)
		if vStatic then
			t.rs = t.rs + eff
		else
			t.rm = t.rm + eff
		end
		if aStatic then
			t.rfs = t.rfs + eff
		end
		if isConstructor[unitDefID] then
			t.bdmg = t.bdmg + eff
			local frame = Spring.GetGameFrame()
			local last = conLastHit[unitID]
			if last == nil or frame - last > INTERRUPT_GAP then
				t.bi = t.bi + 1
				if Spring.GetUnitIsBuilding(unitID) ~= nil then
					t.bib = t.bib + 1
				end
			end
			conLastHit[unitID] = frame
		end
	end
	local manual = false
	if weaponDefID ~= nil and weaponDefID >= 0 then
		manual = isManual[weaponDefID]
		if manual == nil then
			local wd = WeaponDefs[weaponDefID]
			manual = wd ~= nil and (wd.manualFire == true or wd.type == "DGun")
			isManual[weaponDefID] = manual
			if manual and not manualEchoed then
				manualEchoed = true
				BARAI_Echo("[BARAI_DGUNWD] " .. tostring(wd.name))
			end
		end
	end
	lastManual[unitID] = manual or nil
	if attackerAI then
		local t = dmgOf(attackerTeam)
		if vStatic then
			t.ds = t.ds + eff
		else
			t.dm = t.dm + eff
		end
		if manual then
			t.dg = t.dg + 1
		end
	end
end

local function snapshot(frame)
	for teamID in pairs(aiTeam) do
		local t = dmgOf(teamID)
		local eCur, eStore = Spring.GetTeamResources(teamID, "energy")
		BARAI_Echo(string.format(
			"[BARAI_DMG] frame=%d team=%d dm=%d ds=%d rm=%d rs=%d rfs=%d bi=%d bib=%d bd=%d bdmg=%d dg=%d dgm=%d mfo=%d dgp=%d e=%d es=%d ffdg=%d ffdgm=%d ffdgk=%d",
			frame, teamID, t.dm, t.ds, t.rm, t.rs, t.rfs, t.bi, t.bib, t.bd, t.bdmg, t.dg, t.dgm, t.mfo, t.dgp,
			math.floor(eCur or 0), math.floor(eStore or 0),
			t.ffdg, math.floor(t.ffdgm), t.ffdgk))
	end
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
		local parts = math.ceil(#out / SNAP_CHUNK)
		for p = 1, parts do
			BARAI_Echo(string.format("[BARAI_ARMY] frame=%d team=%d n=%d part=%d/%d %s",
				frame, teamID, #out, p, parts,
				table.concat(out, ",", (p - 1) * SNAP_CHUNK + 1, math.min(p * SNAP_CHUNK, #out))))
		end
	end
end

function gadget:GameFrame(frame)
	for uid, at in pairs(mfCheck) do
		if frame >= at then
			mfCheck[uid] = nil
			local q = Spring.GetUnitCommands(uid, 3) or {}
			local qs = {}
			for i = 1, #q do
				qs[#qs + 1] = tostring(q[i].id)
			end
			local _, _, _, _, bp = Spring.GetUnitHealth(uid)
			BARAI_Echo(string.format("[BARAI_MFQ] frame=%d unit=%d queue=%s", frame, uid, table.concat(qs, ",")))
		end
	end
	if frame >= nextSnap then
		nextSnap = frame + SNAP_INTERVAL
		snapshot(frame)
	end
end
