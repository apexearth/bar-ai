--------------------------------------------------------------------------------
-- dev_stats_export.lua -- per-team benchmark telemetry.
--
-- Win/loss is one bit per match, so a 10-point effect needs ~100 games to see.
-- These counters are continuous and paired (both sides observed on the same map
-- and seed), so a change can be judged on far fewer matches -- and they say
-- *why* it helped, which a win rate never does.
--
-- Deliberately NOT simplified to unit counts. Engine TeamStats reports
-- unitsKilled/unitsDied as raw counts, which scores ten dead Fleas the same as
-- a dead Titan and would reward exactly the wrong behaviour. So this gadget
-- hooks UnitDestroyed and accumulates METAL VALUE, split into:
--
--   cheap  (metalCost <  SPAM_COST)  -- chaff; losing these is not a real loss,
--                                       and killing them is not an achievement
--   real   (metalCost >= SPAM_COST)  -- the number that actually matters
--
-- Damage received is reported but should be read with care: a high figure can
-- mean the AI is tanking behind con-turret repair and wasting enemy effort,
-- which is good play. Prefer real-value K/D and economic efficiency.
--
-- Inert unless the start script sets `dev_stats=1`.
--------------------------------------------------------------------------------

local modOptions = Spring.GetModOptions() or {}
local enabled = tostring(modOptions.dev_stats or "") == "1"

function gadget:GetInfo()
	return {
		name    = "Dev Stats Export",
		desc    = "Per-team economic and value-weighted combat telemetry.",
		author  = "bar-ai",
		date    = "2026",
		license = "GNU GPL, v2 or later",
		layer   = 1001,
		enabled = enabled,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return  -- synced only: UnitDestroyed and UnitDefs live here
end

-- Roughly "costs less than a T1 raider". Flea ~40, Tick ~55, Pawn ~50.
local SPAM_COST = tonumber(modOptions.dev_spamcost or 0) or 0
if SPAM_COST <= 0 then
	SPAM_COST = 120
end

local ECON = {
	"metalProduced", "metalUsed", "metalExcess",
	"energyProduced", "energyUsed", "energyExcess",
	"damageDealt", "damageReceived",
}

local DUMP_INTERVAL = 30 * 60 * 2  -- every 2 game-minutes
local nextDump = DUMP_INTERVAL

-- team -> accumulated metal value
local lostReal, lostCheap = {}, {}
local killReal, killCheap = {}, {}
-- Who did the killing, and what died. apexearth, watching: "we make them suffer
-- a lot with our defenses, but our units are still losing the battles" -- a
-- combined K/D cannot tell those apart, and reads healthy while the army loses.
local killByStatic, killByMobile = {}, {}
-- Standing jammer towers. They cost 115-240 metal, far too little to ever show
-- in the `top` sinks field, so "we build none" was previously unanswerable.
local jamTowers = {}
local lostMobile = {}
local builtReal = {}
-- Testing whether the ~10 min collapse is a tech-transition problem: teching too
-- early leaves you too poor to hold the line, too late leaves you outclassed.
local mReclaim = {}       -- team -> metal gained from reclaiming wrecks
local mRezSpend = {}      -- team -> metal invested resurrecting wrecks
local featMetal = {}      -- featureDefID -> metal (cached)
local techFrame = {}      -- team -> frame its first techlevel>=2 factory finished
local techStart = {}      -- team -> frame its first techlevel>=2 factory was PLACED
-- Finish time conflates three very different failures: never deciding to tech,
-- deciding late, and deciding on time but taking forever to build. Only the
-- placement frame separates them.
local facSpend = {}       -- team -> cumulative metal sunk into factories
local techLvl = {}        -- unitDefID -> techlevel (cached)
-- What each side actually fielded, so a win can be attributed to a composition
-- (a T2 mass, a T3 push) rather than guessed at.
local builtByTech = {}    -- team -> {tech -> metal built}
-- The entire economic case for teching first is 4x metal from upgraded mexes.
-- Holding T2 for eight minutes and still finishing BEHIND stock on metal means
-- those upgrades are probably not happening -- but nothing measured them, so it
-- could only be guessed at.
local t2Mex = {}          -- team -> advanced extractors finished
-- Mex COUNT over time, not just the T2 upgrades above. apexearth, watching:
-- "we often accept having just 1 mex for too long". Nothing measured the
-- early expansion curve, so how long a team sat on one extractor was
-- invisible. mexAt[n] is the frame the nth extractor finished.
-- T1 AA turrets are 80 metal, so they never reach the top= list and the
-- infolog does not record defence construction at all -- the change that
-- added them could not be confirmed either way. Count them explicitly.
local AA_T1 = {armrl = true, corrl = true, legrl = true}
local aaT1 = {}           -- team -> T1 AA turrets finished
local mexCount = {}       -- team -> extractors finished, any tier
local mexAt = {}          -- team -> {n -> frame the nth finished}
-- Losing a commander usually loses the game, and nothing here recorded it -- so
-- an attrition loss and a decapitation looked identical in the telemetry. Games
-- ending at 12-13 minutes are commander-death timing, not attrition timing.
local commLost = {}       -- team -> frame its commander died (-1 if alive)
local builtTop = {}       -- team -> {unitName -> metal built}
local cheapBuilt = {}     -- team -> {unitName -> metal built}, BELOW SPAM_COST
-- WHERE THE METAL WENT, as exclusive buckets summing to everything finished.
-- mBuiltReal/defSpend/facSpend each answer one question and overlap or omit:
-- army production had no counter at all, and cheap units were outside every
-- one of them. Assigned once per unit, in a fixed order, so eco+army+def+
-- defAA+bp+fac+other is the whole spend.
local ecoSpend = {}       -- team -> mex, energy, converters, storage
local armySpend = {}      -- team -> mobile armed non-builders
local bpSpend = {}        -- team -> constructors and nano turrets (no commander)
local otherSpend = {}     -- team -> everything else (unarmed static, transports)
-- Unit COUNTS, not metal. "how many Pawns did we build" was only answerable by
-- dividing a metal sum by a cost read from another tree, and every count in a
-- report so far was derived that way.
local builtCount = {}     -- team -> {unitName -> units finished}
-- Metal sunk into STATIC defence. It was invisible: the army tally counts only
-- units with speed > 0, and the composition buckets are factories, constructors
-- and army, so towers landed in mBuiltReal and nowhere else. apexearth: "the
-- side effect is wasteful defense and then we have less army and are losing the
-- overall fight" -- that trade cannot be judged without measuring both halves.
local defSpend = {}       -- team -> cumulative metal on finished static defence
local defAASpend = {}     -- team -> cumulative metal on finished static ANTI-AIR
-- Orders issued, i.e. APM. A player whose decision logic has wedged keeps its
-- units and its income and simply stops ACTING, which every counter above
-- reads as "fine, just slow". Counted here for BOTH AIs because a synced
-- gadget sees UnitCommand for every team, so stock is measurable too.
--
-- cmdCount is cumulative; cmdWindow is orders since the last sample, which is
-- the one that shows a stall as it happens rather than as a flattening slope.
-- Read them against ownUnits/ownBuilders in the same row: zero orders while
-- holding thirty units is a wedge, zero orders while holding two is just a
-- player that has been killed, and those must not look alike.
local cmdCount = {}       -- team -> commands issued, cumulative
local cmdWindow = {}      -- team -> commands issued since the previous sample

-- COMMANDER IDLE TIME. apexearth, watching a 4v4: "prioritize fixing this
-- commander idle time. could be one big reason we underperform."
--
-- Nothing here could see it. cmds/cmdsWin are team-wide, so a commander standing
-- still is hidden by fifty other units taking orders, and the AI's own logs
-- record the decisions it MADE, never the ticks where it decided nothing. The
-- commander is the biggest builder on the field for the whole opening, so its
-- idle fraction is build power that was paid for and not spent.
--
-- Sampled rather than event-driven: a command queue emptying is not an event,
-- and UnitIdle fires on transitions that a re-order immediately cancels. Idle
-- here means the engine holds zero commands for it at the sample instant.
-- Counted for both AIs, so stock is the control.
local commIdle = {}       -- team -> samples where a live commander had no orders
local commSamp = {}       -- team -> samples taken over a live commander
local COMM_SAMPLE = 15    -- frames between samples (2/second)
local nextCommSample = 0

-- WHAT IT IS DOING, NOT WHETHER IT WAS TOLD TO DO SOMETHING.
--
-- commIdle above measures an empty command queue, and that turned out to answer
-- the wrong question: feeding the commander a job on almost every tick (end-of-
-- pipeline nulls 105-407 -> 7-23) moved it by under a point. So the orders are
-- being issued and the time is going somewhere else.
--
-- These buckets split a sample by OUTCOME. The one that matters is commStall:
-- it holds an order, it is not building, and it did not move -- work that was
-- assigned and is achieving nothing. commAssistIdle is the specific suspicion
-- that ties this to the factory complaint: a commander assisting a factory that
-- has nothing queued looks busy and produces nothing.
local commBuild = {}      -- constructing something right now
local commMove = {}       -- has an order and its position changed
local commAssistIdle = {} -- guarding/repairing a factory with an empty queue
local commAssist = {}     -- guarding/repairing something else
local commStall = {}      -- has an order, not building, did not move
-- Cloak TRANSITIONS, not cloak state. The commander flip-flopping is the
-- complaint, and a state sample cannot show it -- only the number of times
-- the bit changed between samples can.
local commCloakFlips = {} -- team -> cloak state changes observed
local commPrevCloak = {}  -- unitID -> last sampled cloak state
local commPrevX = {}      -- unitID -> last sampled position
local commPrevZ = {}

-- FACTORY DUTY CYCLE, both teams. The nano-turret complaint has two competing
-- mechanisms -- "not enough lathe at the line" vs "the line has no orders" --
-- and only the engine can tell them apart: a factory with an empty build is
-- idle whatever the AI's ledgers say. Busy = the engine reports a unit
-- currently being built by it. Nanos the same, so an over-bought idle farm is
-- distinguishable from a starved one.
local facSamp = {}        -- team -> samples over live factories
local facBusy = {}        -- team -> samples where the factory was building
local nanoSamp = {}       -- team -> samples over finished nano turrets
local nanoBusy = {}       -- team -> samples where the nano was lathing
local CMD_REPAIR = CMD.REPAIR
local CMD_GUARD = CMD.GUARD

local function techOf(ud)
    local t = techLvl[ud.id]
    if t == nil then
        t = tonumber((ud.customParams or {}).techlevel or 1) or 1
        techLvl[ud.id] = t
    end
    return t
end

local function bump(t, team, v)
	t[team] = (t[team] or 0) + v
end

-- Reclaim and resurrect both flow through this callin: part < 0 is reclaim,
-- part > 0 is refill/resurrect. Holding the field after a won fight and eating
-- the wrecks is a large metal swing that metalProduced alone hides, because it
-- folds reclaim in with mex and converter income.
function gadget:AllowFeatureBuildStep(builderID, builderTeam, featureID, featureDefID, part)
	local m = featMetal[featureDefID]
	if m == nil then
		local fd = FeatureDefs[featureDefID]
		m = (fd and fd.metal) or 0
		featMetal[featureDefID] = m
	end
	if m > 0 then
		if part < 0 then
			bump(mReclaim, builderTeam, -part * m)
		else
			bump(mRezSpend, builderTeam, part * m)
		end
	end
	return true
end

local function isJammerTower(ud)
	return ud ~= nil and ud.isBuilding and (ud.radarDistanceJam or 0) > 0
end

function gadget:UnitDestroyed(unitID, unitDefID, unitTeam, attackerID, attackerDefID, attackerTeam)
	if isJammerTower(UnitDefs[unitDefID]) then
		jamTowers[unitTeam] = (jamTowers[unitTeam] or 0) - 1
	end
	do
		local cd = UnitDefs[unitDefID]
		if cd ~= nil and (cd.customParams or {}).iscommander and commLost[unitTeam] == nil then
			commLost[unitTeam] = Spring.GetGameFrame()
			Spring.Echo(string.format("[BARAI_COMMLOST] team=%d ally=%d frame=%d min=%.1f",
				unitTeam, select(6, Spring.GetTeamInfo(unitTeam, false)) or 0,
				commLost[unitTeam], commLost[unitTeam] / 1800))
		end
	end
	local ud = UnitDefs[unitDefID]
	if ud == nil then
		return
	end
	local cost = ud.metalCost or 0
	local cheap = cost < SPAM_COST

	if cheap then
		bump(lostCheap, unitTeam, cost)
	else
		bump(lostReal, unitTeam, cost)
	end

	-- attackerTeam is nil for self-destructs, reclaim and terrain deaths; those
	-- are losses but nobody's kill.
	if not ud.isBuilding then
		bump(lostMobile, unitTeam, cost)
	end

	if attackerTeam ~= nil and attackerTeam ~= unitTeam then
		if cheap then
			bump(killCheap, attackerTeam, cost)
		else
			bump(killReal, attackerTeam, cost)
		end
		-- Immobile killer = a tower did this; mobile = our army did.
		-- attackerDefID is nil when the killer is out of LOS, so those land in
		-- neither bucket rather than being guessed at.
		local ad = attackerDefID and UnitDefs[attackerDefID]
		if ad ~= nil then
			if ad.isBuilding then
				bump(killByStatic, attackerTeam, cost)
			else
				bump(killByMobile, attackerTeam, cost)
			end
		end
	end
end

-- Fires when the nanoframe is placed, i.e. the moment the AI commits to T2.
function gadget:UnitCreated(unitID, unitDefID, unitTeam, builderID)
	local ud = UnitDefs[unitDefID]
	if ud == nil or not ud.isFactory or techOf(ud) < 2 then
		return
	end
	if techStart[unitTeam] == nil then
		local f = Spring.GetGameFrame()
		techStart[unitTeam] = f
		Spring.Echo(string.format("[BARAI_T2START] team=%d ally=%d frame=%d min=%.1f unit=%s cost=%d",
			unitTeam, select(6, Spring.GetTeamInfo(unitTeam, false)) or 0,
			f, f / 1800, ud.name, ud.metalCost or 0))
	end
end

function gadget:UnitFinished(unitID, unitDefID, unitTeam)
	local ud = UnitDefs[unitDefID]
	if ud == nil then
		return
	end
	-- Per-building completion EVENT, not a periodic snapshot. dump() below only
	-- fires every 2 game-minutes, so "what did we build in the first N minutes"
	-- for an arbitrary N had to be read off the nearest snapshot. One line per
	-- building gives an exact frame, so any window can be answered precisely.
	-- speed==0 too: isBuilding is false for immobile BUILDERS, so construction
	-- turrets (and dragon's teeth) never appeared here at all -- "0 nanos
	-- built" was unmeasurable, not zero.
	if ud.isBuilding or ((ud.speed or 0) == 0) then
		local f = Spring.GetGameFrame()
		Spring.Echo(string.format("[BARAI_BUILD] team=%d ally=%d frame=%d min=%.2f unit=%s cost=%d",
			unitTeam, select(6, Spring.GetTeamInfo(unitTeam, false)) or 0,
			f, f / 1800, ud.name, ud.metalCost or 0))
	end
	if isJammerTower(ud) then
		jamTowers[unitTeam] = (jamTowers[unitTeam] or 0) + 1
	end
	do
		builtCount[unitTeam] = builtCount[unitTeam] or {}
		builtCount[unitTeam][ud.name] = (builtCount[unitTeam][ud.name] or 0) + 1
		local cost = ud.metalCost or 0
		local static = (ud.speed or 0) == 0
		local armed = #ud.weapons > 0
		local isComm = (ud.customParams or {}).iscommander
		if ud.isFactory then
			-- counted in facSpend below; kept out of the other buckets
		elseif ud.isBuilder and not isComm then
			bump(bpSpend, unitTeam, cost)
		elseif static and armed then
			-- def/defAA below
		elseif not static and armed then
			bump(armySpend, unitTeam, cost)
		-- BAR states a solar's output as NEGATIVE energyupkeep, not energyMake,
		-- and a converter only by customparams.energyconv_capacity -- testing
		-- the obvious fields alone filed every solar under "other".
		elseif (ud.extractsMetal or 0) > 0 or (ud.energyMake or 0) > 0
			or (ud.windGenerator or 0) > 0 or (ud.tidalGenerator or 0) > 0
			or (ud.energyUpkeep or 0) < 0
			or (ud.customParams or {}).energyconv_capacity ~= nil
			or (ud.energyStorage or 0) > 100 or (ud.metalStorage or 0) > 100
		then
			bump(ecoSpend, unitTeam, cost)
		elseif not isComm then
			bump(otherSpend, unitTeam, cost)
		end
	end
	-- CHEAP UNITS WERE INVISIBLE IN EVERY COUNTER. A Pawn is 54 metal against
	-- SPAM_COST 120, so armyReal, mBuiltReal, allBuilt and top= all excluded it --
	-- cumulative chaff production was simply not in the telemetry, which is why a
	-- claim about how many Pawns we build had to be estimated from a rate-limited
	-- log line and was wrong. Counted here per def, outside the branch below.
	if (ud.metalCost or 0) > 0 and (ud.metalCost or 0) < SPAM_COST then
		cheapBuilt[unitTeam] = cheapBuilt[unitTeam] or {}
		cheapBuilt[unitTeam][ud.name] = (cheapBuilt[unitTeam][ud.name] or 0) + ud.metalCost
	end
	if (ud.metalCost or 0) >= SPAM_COST then
		bump(builtReal, unitTeam, ud.metalCost)
		-- Record composition so a win can be attributed to what was actually
		-- fielded (a T2 mass, a T3 push) instead of guessed at.
		local tl = techOf(ud)
		builtByTech[unitTeam] = builtByTech[unitTeam] or {}
		builtByTech[unitTeam][tl] = (builtByTech[unitTeam][tl] or 0) + ud.metalCost
		builtTop[unitTeam] = builtTop[unitTeam] or {}
		builtTop[unitTeam][ud.name] = (builtTop[unitTeam][ud.name] or 0) + ud.metalCost
	end
	if AA_T1[ud.name] then
		aaT1[unitTeam] = (aaT1[unitTeam] or 0) + 1
	end
	if (ud.extractsMetal or 0) > 0 then
		local n = (mexCount[unitTeam] or 0) + 1
		mexCount[unitTeam] = n
		mexAt[unitTeam] = mexAt[unitTeam] or {}
		mexAt[unitTeam][n] = Spring.GetGameFrame()
		if techOf(ud) >= 2 then
			t2Mex[unitTeam] = (t2Mex[unitTeam] or 0) + 1
		end
	end
	-- Immobile and armed = static defence. Excludes mexes, solars and nanos.
	-- Anti-air (every weapon vtol-only) is counted separately: the eco role
	-- may buy AA but no ground defence, and the audit needs to tell them apart.
	if (ud.speed or 0) == 0 and #ud.weapons > 0 and not ud.isFactory then
		local aaOnly = true
		for _, w in ipairs(ud.weapons) do
			if not (w.onlyTargets and w.onlyTargets.vtol) then
				aaOnly = false
				break
			end
		end
		if aaOnly then
			bump(defAASpend, unitTeam, ud.metalCost or 0)
		else
			bump(defSpend, unitTeam, ud.metalCost or 0)
		end
	end
	if ud.isFactory then
		bump(facSpend, unitTeam, ud.metalCost or 0)
		if techOf(ud) >= 2 and techFrame[unitTeam] == nil then
			local f = Spring.GetGameFrame()
			techFrame[unitTeam] = f
			Spring.Echo(string.format("[BARAI_T2DONE] team=%d ally=%d frame=%d min=%.1f unit=%s build=%.1fm",
				unitTeam, select(6, Spring.GetTeamInfo(unitTeam, false)) or 0,
				f, f / 1800, ud.name, (f - (techStart[unitTeam] or f)) / 1800))
		end
	end
end

-- Every order any of our units receives, from an AI or from a widget. The AI
-- interface issues real engine commands, so this is a faithful APM for both
-- sides. Deliberately not filtered by cmdID: a stalled player issues nothing
-- of any kind, and filtering to "interesting" commands would need a whitelist
-- that silently rots as the game adds command types.
function gadget:UnitCommand(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOpts, cmdTag)
	bump(cmdCount, unitTeam, 1)
	bump(cmdWindow, unitTeam, 1)
end

-- Units held, and how many can build. The denominators that stop a dead player
-- reading as a wedged one -- see cmdCount's comment.
-- ONE WALK, not five. ownUnitCounts/builderCounts/armyValue/factoryQueueDepth
-- and the armed/setTarget loop each called Spring.GetTeamUnits and re-resolved
-- every UnitDef; at minute 30 that is five passes over ~450 units per team on a
-- single frame. Each caller was used exactly once, from dump(), so they are one
-- pass returning a record. Field semantics are unchanged -- see the notes on the
-- originals in git history for why each counts what it counts.
local function teamSnapshot(teamID)
	local r = {
		units = 0, builders = 0,            -- ownUnitCounts
		conT1 = 0, conT2 = 0, conMetal = 0, -- builderCounts (commanders excluded)
		army = 0, armyCheap = 0,            -- armyValue (mobile, armed, non-builder)
		facs = 0, facOrders = 0,            -- factoryQueueDepth
		armed = 0, targeted = 0,            -- CmdSetTarget landing rate
	}
	for _, uid in ipairs(Spring.GetTeamUnits(teamID) or {}) do
		local udid = Spring.GetUnitDefID(uid)
		local ud = udid and UnitDefs[udid]
		r.units = r.units + 1
		if ud ~= nil then
			local mobile = (ud.speed or 0) > 0
			if ud.isBuilder then
				r.builders = r.builders + 1
				if mobile and not (ud.customParams or {}).iscommander then
					r.conMetal = r.conMetal + (ud.metalCost or 0)
					if techOf(ud) >= 2 then r.conT2 = r.conT2 + 1
					else r.conT1 = r.conT1 + 1 end
				end
			elseif mobile and #ud.weapons > 0 then
				local c = ud.metalCost or 0
				if c >= SPAM_COST then r.army = r.army + c
				else r.armyCheap = r.armyCheap + c end
			end
			if ud.isFactory then
				r.facs = r.facs + 1
				local q = Spring.GetFactoryCommands(uid, -1)
				if q then r.facOrders = r.facOrders + #q end
			end
			if ud.canAttack and (ud.maxWeaponRange or 0) > 0 then
				r.armed = r.armed + 1
				-- GetUnitRulesParam returns nil when unset, and tonumber(nil)
				-- RAISES rather than returning nil -- which took the whole
				-- export down on the first untargeted unit.
				local raw = Spring.GetUnitRulesParam(uid, "targetID")
				local t = raw ~= nil and tonumber(raw) or nil
				if t ~= nil and t >= 0 then r.targeted = r.targeted + 1 end
			end
		end
	end
	return r
end

-- STALLING, which the cumulative counters cannot show. metalExcess says metal
-- was thrown away; nothing said the opposite -- that the team asked for more
-- than it could pay and every builder on the field slowed down. Read from the
-- engine's own arithmetic rather than a threshold: `pull` is what was asked
-- for this frame and `expense` is what was actually granted, so a shortfall
-- between them IS the stall, with no invented percentage of storage in it.
--
-- Sampled twice a second and counted, so the dashboard can difference two
-- samples into "what fraction of these two minutes was spent stalled".
local eStall, mStall, resSamp = {}, {}, {}
local mFillSum, eFillSum = {}, {}   -- summed bank/storage, for a mean fill

local function sampleResources()
	for _, teamID in ipairs(Spring.GetTeamList()) do
		local _, _, _, isAI = Spring.GetTeamInfo(teamID, false)
		if isAI then
			bump(resSamp, teamID, 1)
			local mc, ms, mp, _, me = Spring.GetTeamResources(teamID, "metal")
			local ec, es, ep, _, ee = Spring.GetTeamResources(teamID, "energy")
			if mp ~= nil and me ~= nil and mp > me * 1.001 + 0.01 then
				bump(mStall, teamID, 1)
			end
			if ep ~= nil and ee ~= nil and ep > ee * 1.001 + 0.01 then
				bump(eStall, teamID, 1)
			end
			if mc ~= nil and (ms or 0) > 0 then
				bump(mFillSum, teamID, mc / ms)
			end
			if ec ~= nil and (es or 0) > 0 then
				bump(eFillSum, teamID, ec / es)
			end
		end
	end
end

-- `io` is nil in the gadget sandbox, so emit through Spring.Echo and let the
-- harness parse the infolog it already collects. Last line per team wins.
local function sampleCommIdle()
	for _, teamID in ipairs(Spring.GetTeamList()) do
		local _, _, _, isAI = Spring.GetTeamInfo(teamID, false)
		if isAI then
			for _, uid in ipairs(Spring.GetTeamUnits(teamID) or {}) do
				local udid = Spring.GetUnitDefID(uid)
				local ud = udid and UnitDefs[udid]
				if ud ~= nil and not Spring.GetUnitIsBeingBuilt(uid) then
					if ud.isFactory then
						bump(facSamp, teamID, 1)
						if Spring.GetUnitIsBuilding(uid) then
							bump(facBusy, teamID, 1)
						end
					elseif ud.isBuilder and (ud.speed or 0) == 0 then
						bump(nanoSamp, teamID, 1)
						if Spring.GetUnitIsBuilding(uid) then
							bump(nanoBusy, teamID, 1)
						end
					end
				end
				if ud ~= nil and (ud.customParams or {}).iscommander then
					bump(commSamp, teamID, 1)
					local cloaked = Spring.GetUnitIsCloaked(uid) and true or false
					if commPrevCloak[uid] ~= nil and commPrevCloak[uid] ~= cloaked then
						bump(commCloakFlips, teamID, 1)
					end
					commPrevCloak[uid] = cloaked
					local cmds = Spring.GetUnitCommands(uid, 1)
					local x, _, z = Spring.GetUnitPosition(uid)
					local px, pz = commPrevX[uid], commPrevZ[uid]
					local moved = (px == nil) or (x == nil)
							or ((x - px) * (x - px) + (z - pz) * (z - pz) > 16)
					commPrevX[uid], commPrevZ[uid] = x, z

					if cmds == nil or #cmds == 0 then
						bump(commIdle, teamID, 1)
					elseif Spring.GetUnitIsBuilding(uid) then
						bump(commBuild, teamID, 1)
					else
						local c = cmds[1]
						local isAssist = (c.id == CMD_REPAIR or c.id == CMD_GUARD)
						local tgt = isAssist and c.params and c.params[1]
						if tgt then
							-- An assisted factory with nothing queued is the
							-- commander's time going nowhere.
							local q = Spring.GetFactoryCommands(tgt, 1)
							local tdid = Spring.GetUnitDefID(tgt)
							local tud = tdid and UnitDefs[tdid]
							if tud ~= nil and tud.isFactory and (q == nil or #q == 0) then
								bump(commAssistIdle, teamID, 1)
							else
								bump(commAssist, teamID, 1)
							end
						elseif moved then
							bump(commMove, teamID, 1)
						else
							bump(commStall, teamID, 1)
						end
					end
				end
			end
		end
	end
end

-- onlyTeam/atFrame drive the per-frame SLICE (see gadget:GameFrame). With both
-- nil this behaves exactly as before, which is what GameOver/Shutdown want.
local function dump(reason, onlyTeam, atFrame)
	for _, teamID in ipairs(Spring.GetTeamList()) do
		local _, _, _, isAI = Spring.GetTeamInfo(teamID, false)
		if isAI and (onlyTeam == nil or teamID == onlyTeam) then
			local parts = {
				string.format("team=%d", teamID),
				string.format("ally=%d", select(6, Spring.GetTeamInfo(teamID, false)) or 0),
				"reason=" .. reason,
				string.format("frame=%d", atFrame or Spring.GetGameFrame()),
				string.format("spamCost=%d", SPAM_COST),
				string.format("mLostReal=%.0f", lostReal[teamID] or 0),
				string.format("mLostCheap=%.0f", lostCheap[teamID] or 0),
				string.format("mKillReal=%.0f", killReal[teamID] or 0),
				string.format("jamT=%d", jamTowers[teamID] or 0),
				string.format("mKillStatic=%.0f", killByStatic[teamID] or 0),
				string.format("mKillMobile=%.0f", killByMobile[teamID] or 0),
				string.format("mLostMobile=%.0f", lostMobile[teamID] or 0),
				string.format("mKillCheap=%.0f", killCheap[teamID] or 0),
				string.format("mBuiltReal=%.0f", builtReal[teamID] or 0),
				string.format("mFactories=%.0f", facSpend[teamID] or 0),
				string.format("mDefence=%.0f", defSpend[teamID] or 0),
				string.format("mEco=%.0f", ecoSpend[teamID] or 0),
				string.format("mArmy=%.0f", armySpend[teamID] or 0),
				string.format("mBP=%.0f", bpSpend[teamID] or 0),
				string.format("mOther=%.0f", otherSpend[teamID] or 0),
				string.format("mDefAA=%.0f", defAASpend[teamID] or 0),
				string.format("mReclaim=%.0f", mReclaim[teamID] or 0),
				string.format("mRezSpend=%.0f", mRezSpend[teamID] or 0),
				string.format("techFrame=%d", techFrame[teamID] or -1),
				string.format("techStart=%d", techStart[teamID] or -1),
				string.format("t2Mex=%d", t2Mex[teamID] or 0),
				string.format("mex=%d", mexCount[teamID] or 0),
				string.format("aaT1=%d", aaT1[teamID] or 0),
				string.format("mex2=%d", (mexAt[teamID] or {})[2] or -1),
				string.format("mex4=%d", (mexAt[teamID] or {})[4] or -1),
				string.format("mex8=%d", (mexAt[teamID] or {})[8] or -1),
				string.format("commLost=%d", commLost[teamID] or -1),
			}
			local bt = builtByTech[teamID] or {}
			parts[#parts + 1] = string.format("mT1=%.0f", bt[1] or 0)
			parts[#parts + 1] = string.format("mT2=%.0f", bt[2] or 0)
			parts[#parts + 1] = string.format("mT3=%.0f", (bt[3] or 0) + (bt[4] or 0))
			-- top few unit types by metal invested
			local names = {}
			for n, v in pairs(builtTop[teamID] or {}) do names[#names + 1] = {n, v} end
			table.sort(names, function(a, b) return a[2] > b[2] end)
			local top = {}
			for i = 1, math.min(4, #names) do
				top[#top + 1] = string.format("%s:%.0f", names[i][1], names[i][2])
			end
			if #top > 0 then
				parts[#parts + 1] = "top=" .. table.concat(top, ",")
			end
			-- Full unit-type list, not just the top 4. apexearth: "make sure that the
			-- units we expect to be created are actually created" -- top= alone cannot
			-- answer that, since a cheap or rare unit (an unused factory, a T3 unit
			-- built once) never displaces the big spenders. Every unit type with any
			-- metal invested this game, so a config weight can be checked against
			-- what actually got built rather than inferred from the top spenders.
			local all = {}
			for i = 1, #names do
				all[#all + 1] = string.format("%s:%.0f", names[i][1], names[i][2])
			end
			if #all > 0 then
				parts[#parts + 1] = "allBuilt=" .. table.concat(all, ",")
			end
			local counts = {}
			for name, n in pairs(builtCount[teamID] or {}) do
				counts[#counts + 1] = string.format("%s:%d", name, n)
			end
			table.sort(counts)
			if #counts > 0 then
				parts[#parts + 1] = "unitCount=" .. table.concat(counts, ",")
			end

			local snap = teamSnapshot(teamID)
			parts[#parts + 1] = string.format("armyReal=%.0f", snap.army)
			parts[#parts + 1] = string.format("armyCheap=%.0f", snap.armyCheap)

			parts[#parts + 1] = string.format("conT1=%d", snap.conT1)
			parts[#parts + 1] = string.format("conT2=%d", snap.conT2)
			parts[#parts + 1] = string.format("mCon=%.0f", snap.conMetal)

			-- APM, plus the denominators that tell a wedged player from a dead
			-- one. cmdWindow is zeroed here so the next sample measures only
			-- its own interval.
			parts[#parts + 1] = string.format("cmds=%d", cmdCount[teamID] or 0)
			parts[#parts + 1] = string.format("cmdsWin=%d", cmdWindow[teamID] or 0)
			parts[#parts + 1] = string.format("ownUnits=%d", snap.units)
			parts[#parts + 1] = string.format("ownBuilders=%d", snap.builders)
			parts[#parts + 1] = string.format("commIdle=%d", commIdle[teamID] or 0)
			parts[#parts + 1] = string.format("commSamp=%d", commSamp[teamID] or 0)
			parts[#parts + 1] = string.format("commBuild=%d", commBuild[teamID] or 0)
			parts[#parts + 1] = string.format("commMove=%d", commMove[teamID] or 0)
			parts[#parts + 1] = string.format("commAssistIdle=%d", commAssistIdle[teamID] or 0)
			parts[#parts + 1] = string.format("commAssist=%d", commAssist[teamID] or 0)
			parts[#parts + 1] = string.format("commStall=%d", commStall[teamID] or 0)
			parts[#parts + 1] = string.format("commCloakFlips=%d", commCloakFlips[teamID] or 0)

			parts[#parts + 1] = string.format("facCount=%d", snap.facs)
			parts[#parts + 1] = string.format("facQueued=%d", snap.facOrders)

			-- The bank, and what is being asked of it. GetTeamStatsHistory is
			-- cumulative only: it can say 40k energy was wasted and never that
			-- the team is sitting full at this instant, which is the reading
			-- that says whether the next converter pays for itself.
			local mc, ms, mp, mi, mx = Spring.GetTeamResources(teamID, "metal")
			local ec, es, ep, ei, ex = Spring.GetTeamResources(teamID, "energy")
			parts[#parts + 1] = string.format("mNow=%.0f", mc or 0)
			parts[#parts + 1] = string.format("mStore=%.0f", ms or 0)
			parts[#parts + 1] = string.format("mInc=%.2f", mi or 0)
			parts[#parts + 1] = string.format("mPull=%.2f", mp or 0)
			parts[#parts + 1] = string.format("mSpend=%.2f", mx or 0)
			parts[#parts + 1] = string.format("eNow=%.0f", ec or 0)
			parts[#parts + 1] = string.format("eStore=%.0f", es or 0)
			parts[#parts + 1] = string.format("eInc=%.2f", ei or 0)
			parts[#parts + 1] = string.format("ePull=%.2f", ep or 0)
			parts[#parts + 1] = string.format("eSpend=%.2f", ex or 0)
			-- Cumulative stall samples against the sample count, so any two
			-- rows difference into the stalled fraction of that window.
			parts[#parts + 1] = string.format("resSamp=%d", resSamp[teamID] or 0)
			parts[#parts + 1] = string.format("mStall=%d", mStall[teamID] or 0)
			parts[#parts + 1] = string.format("eStall=%d", eStall[teamID] or 0)
			parts[#parts + 1] = string.format("mFillSum=%.2f", mFillSum[teamID] or 0)
			parts[#parts + 1] = string.format("eFillSum=%.2f", eFillSum[teamID] or 0)

			-- Does CmdSetTarget actually land for an AI-owned unit? The AI has
			-- issued it for a long time and nothing has ever confirmed it took.
			-- unit_target_on_the_move.lua (BAR's own) writes this rules param on
			-- success, and rules params are not behind the AI_TEAM_IDS gate that
			-- makes the resource callbacks read -1.
			parts[#parts + 1] = string.format("armed=%d", snap.armed)
			parts[#parts + 1] = string.format("setTarget=%d", snap.targeted)

			local cb = cheapBuilt[teamID]
			if cb ~= nil then
				local out = {}
				for name, metal in pairs(cb) do
					out[#out + 1] = string.format("%s:%d", name, metal)
				end
				table.sort(out)
				if #out > 0 then
					parts[#parts + 1] = "cheapBuilt=" .. table.concat(out, ",")
				end
			end
			cmdWindow[teamID] = 0

			local n = Spring.GetTeamStatsHistory(teamID)
			if n and n > 0 then
				local hist = Spring.GetTeamStatsHistory(teamID, n - 1, n - 1)
				local st = hist and hist[1]
				if st then
					for _, f in ipairs(ECON) do
						parts[#parts + 1] = string.format("%s=%.1f", f, st[f] or 0)
					end
				end
			end
			Spring.Echo("[BARAI_STATS] " .. table.concat(parts, " "))
			Spring.Echo(string.format(
				"[BARAI_DUTY] team=%d frame=%d facSamp=%d facBusy=%d nanoSamp=%d nanoBusy=%d",
				teamID, atFrame or Spring.GetGameFrame(),
				facSamp[teamID] or 0, facBusy[teamID] or 0,
				nanoSamp[teamID] or 0, nanoBusy[teamID] or 0))
		end
	end
end

-- Building POSITIONS, as a separate line so nothing parsing BARAI_STATS breaks.
-- There was no positional telemetry in this project at all, so every claim about
-- base layout was inferred from reading placement code rather than measured.
-- Static buildings only, and only their footprint-relevant facts: id, x, z and
-- the def's footprint in build squares. That is enough to compute packing
-- density, nearest-neighbour spacing and row/column alignment offline.
local function dumpPositions(onlyTeam, atFrame)
	for _, teamID in ipairs(Spring.GetTeamList()) do
		local _, _, _, isAI = Spring.GetTeamInfo(teamID, false)
		if isAI and (onlyTeam == nil or teamID == onlyTeam) then
			-- isBuilding alone excluded nano turrets (immobile UNITS, not
			-- buildings, in Spring def terms) -- and the nanos-per-factory
			-- audit needs them. Factories report canMove=true (they pass move
			-- orders to their units), so the canMove guard must not exclude
			-- them: without isFactory here no factory ever appeared in
			-- BARAI_POS and the nanos-at-best-factory audit was silently dead.
			-- Factories and builders go FIRST: Spring.Echo truncates around
			-- 4KB, and a truncated tail must lose dragon's teeth, not labs.
			local head, rest = {}, {}
			for _, uid in ipairs(Spring.GetTeamUnits(teamID) or {}) do
				local udid = Spring.GetUnitDefID(uid)
				local ud = udid and UnitDefs[udid]
				if ud and (ud.isFactory
						or ((ud.isBuilding or (ud.speed or 0) == 0) and not ud.canMove)) then
					local x, _, z = Spring.GetUnitPosition(uid)
					if x then
						local tok = string.format("%s:%d:%d:%d:%d",
								ud.name, x, z, ud.xsize or 0, ud.zsize or 0)
						if ud.isFactory or ud.isBuilder then
							head[#head + 1] = tok
						else
							rest[#rest + 1] = tok
						end
					end
				end
			end
			for i = 1, #rest do head[#head + 1] = rest[i] end
			if #head > 0 then
				Spring.Echo(string.format("[BARAI_POS] team=%d ally=%d frame=%d n=%d %s",
						teamID, select(6, Spring.GetTeamInfo(teamID, false)) or 0,
						atFrame or Spring.GetGameFrame(), #head, table.concat(head, ",")))
			end
		end
	end
end

-- PARALLEL BIG-ENERGY CENSUS. The AI's own request log answers "what did one
-- rule decide"; this answers "how many expensive energy buildings are ACTUALLY
-- rising at once", which is the thing complained about and is blind to which
-- layer ordered them (script rule, Brain want, or C++ build_chain). Unfinished
-- only: buildProgress < 1. The cost bar excludes wind and solar, whose parallel
-- construction is intended and cheap.
local EFRAME_COST = tonumber(modOptions.dev_eframe_cost or 0) or 0
if EFRAME_COST <= 0 then
	EFRAME_COST = 300
end
local EFRAME_SAMPLE = 90        -- frames between censuses (3 game-seconds)
local nextEFrame = EFRAME_SAMPLE
local eframePeak = {}           -- team -> most simultaneous ever seen
local eframeBad = {}            -- team -> samples with 2+ standing at once
local eframeSamp = {}           -- team -> samples taken

local function isBigEnergy(ud)
	if ud == nil or (ud.speed or 0) ~= 0 then
		return false
	end
	-- A GEOTHERMAL IS SPOT WORK, not a duplicate. It can only stand on a vent,
	-- so two of them are two different things wanted for their own sake -- the
	-- same reason extractors are exempt from the AI's own duplicate rules. The
	-- AI founds them through the spot path and the class gate never sees them;
	-- counting them here reported a violation the rule does not make.
	if ((ud.customParams or {}).geothermal or 0) ~= 0 then
		return false
	end
	if (ud.metalCost or 0) < EFRAME_COST then
		return false
	end
	local make = ud.energyMake or 0
	local wind = ud.windGenerator or 0
	local tidal = ud.tidalGenerator or 0
	return (make > 1) or (wind > 1) or (tidal > 1)
end

local function sampleEFrames(frame)
	for _, teamID in ipairs(Spring.GetTeamList()) do
		local n, names = 0, {}
		for _, uid in ipairs(Spring.GetTeamUnits(teamID) or {}) do
			local _, _, _, _, prog = Spring.GetUnitHealth(uid)
			if prog ~= nil and prog < 1 then
				local ud = UnitDefs[Spring.GetUnitDefID(uid) or -1]
				if isBigEnergy(ud) then
					n = n + 1
					names[#names + 1] = string.format("%s:%.2f", ud.name, prog)
				end
			end
		end
		eframeSamp[teamID] = (eframeSamp[teamID] or 0) + 1
		if n > (eframePeak[teamID] or 0) then
			eframePeak[teamID] = n
		end
		if n >= 2 then
			eframeBad[teamID] = (eframeBad[teamID] or 0) + 1
			Spring.Echo(string.format(
				"[BARAI_EFRAMES] team=%d ally=%d frame=%d min=%.2f n=%d defs=%s",
				teamID, select(6, Spring.GetTeamInfo(teamID, false)) or 0,
				frame, frame / 1800, n, table.concat(names, ",")))
		end
	end
end

local function dumpEFrames(reason)
	for _, teamID in ipairs(Spring.GetTeamList()) do
		Spring.Echo(string.format(
			"[BARAI_EPEAK] team=%d ally=%d reason=%s peak=%d badSamples=%d"
			.. " samples=%d costBar=%d",
			teamID, select(6, Spring.GetTeamInfo(teamID, false)) or 0, reason,
			eframePeak[teamID] or 0, eframeBad[teamID] or 0,
			eframeSamp[teamID] or 0, EFRAME_COST))
	end
end

local dumpQ, dumpQI, dumpQAt = {}, 1, 0

function gadget:GameFrame(frame)
	if frame >= nextEFrame then
		nextEFrame = frame + EFRAME_SAMPLE
		sampleEFrames(frame)
	end
	if frame >= nextCommSample then
		nextCommSample = frame + COMM_SAMPLE
		sampleCommIdle()
		sampleResources()
	end
	-- ONE TEAM-PHASE PER FRAME. Doing every team's stats line AND every team's
	-- position line on one frame is what a 406 ms sim frame looked like:
	-- measured Supreme Isthmus v2.1 1v1 at minute 30, the worst wall-clock
	-- frames in the whole game landed on 32400/36000/.../54000 -- exactly this
	-- dump -- while the AI's own AiFrame never exceeded 49 ms. The gadget, not
	-- the AI. atFrame is frozen at the due frame so every line still reports the
	-- frame the sample belongs to and nothing parsing it shifts.
	if frame >= nextDump then
		nextDump = frame + DUMP_INTERVAL
		dumpQ = {}
		for _, teamID in ipairs(Spring.GetTeamList()) do
			local _, _, _, isAI = Spring.GetTeamInfo(teamID, false)
			if isAI then
				dumpQ[#dumpQ + 1] = { teamID, "stats" }
				dumpQ[#dumpQ + 1] = { teamID, "pos" }
			end
		end
		dumpQAt = frame
		dumpQI = 1
	end
	if dumpQI <= #dumpQ then
		local job = dumpQ[dumpQI]
		dumpQI = dumpQI + 1
		if job[2] == "stats" then
			dump("periodic", job[1], dumpQAt)
		else
			dumpPositions(job[1], dumpQAt)
		end
	end
end

function gadget:GameOver()
	dumpEFrames("gameover")
	dump("gameover")
end

function gadget:Shutdown()
	dumpEFrames("shutdown")
	dump("shutdown")
end
