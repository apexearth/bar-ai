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
-- Metal sunk into STATIC defence. It was invisible: armyValue() counts only
-- units with speed > 0, and the composition buckets are factories, constructors
-- and army, so towers landed in mBuiltReal and nowhere else. apexearth: "the
-- side effect is wasteful defense and then we have less army and are losing the
-- overall fight" -- that trade cannot be judged without measuring both halves.
local defSpend = {}       -- team -> cumulative metal on finished static defence
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
	if isJammerTower(ud) then
		jamTowers[unitTeam] = (jamTowers[unitTeam] or 0) + 1
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
	if (ud.speed or 0) == 0 and #ud.weapons > 0 and not ud.isFactory then
		bump(defSpend, unitTeam, ud.metalCost or 0)
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
local function ownUnitCounts(teamID)
	local units, builders = 0, 0
	for _, uid in ipairs(Spring.GetTeamUnits(teamID) or {}) do
		units = units + 1
		local udid = Spring.GetUnitDefID(uid)
		local ud = udid and UnitDefs[udid]
		if ud ~= nil and ud.isBuilder then
			builders = builders + 1
		end
	end
	return units, builders
end

-- Constructors held, split by tech. The tech lead deliberately converts the
-- team's pooled metal into build power, so this is the number that separates
-- "enough to finish the plant" from "metal that cannot be spent". Held rather
-- than built, to match the quantity RUSH_CON_CAP thinks it is capping.
-- Commanders excluded: not a production choice.
local function builderCounts(teamID)
	local t1, t2, metal = 0, 0, 0
	for _, uid in ipairs(Spring.GetTeamUnits(teamID) or {}) do
		local udid = Spring.GetUnitDefID(uid)
		local ud = udid and UnitDefs[udid]
		if ud ~= nil and ud.isBuilder and ud.speed and ud.speed > 0
			and not (ud.customParams or {}).iscommander
		then
			metal = metal + (ud.metalCost or 0)
			if techOf(ud) >= 2 then t2 = t2 + 1 else t1 = t1 + 1 end
		end
	end
	return t1, t2, metal
end

-- Standing army value: kills and losses say how trades went, but not whether
-- you actually had an army at the moment of the fight. Mobile, armed, non-chaff.
local function armyValue(teamID)
	local total, cheap = 0, 0
	for _, uid in ipairs(Spring.GetTeamUnits(teamID) or {}) do
		local udid = Spring.GetUnitDefID(uid)
		local ud = udid and UnitDefs[udid]
		if ud ~= nil and ud.speed and ud.speed > 0 and #ud.weapons > 0 then
			local c = ud.metalCost or 0
			if c >= SPAM_COST then total = total + c else cheap = cheap + c end
		end
	end
	return total, cheap
end

-- TEMPORARY DIAGNOSTIC: the real factory build queue, read synced. The AI-side
-- CCircuitUnit::CountQueued reads it through the skirmish callback and is under
-- suspicion of always answering 0; this is the independent number.
local function factoryQueueDepth(teamID)
	local facs, orders = 0, 0
	for _, uid in ipairs(Spring.GetTeamUnits(teamID) or {}) do
		local udid = Spring.GetUnitDefID(uid)
		local ud = udid and UnitDefs[udid]
		if ud ~= nil and ud.isFactory then
			facs = facs + 1
			local q = Spring.GetFactoryCommands(uid, -1)
			if q then orders = orders + #q end
		end
	end
	return facs, orders
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

local function dump(reason)
	for _, teamID in ipairs(Spring.GetTeamList()) do
		local _, _, _, isAI = Spring.GetTeamInfo(teamID, false)
		if isAI then
			local parts = {
				string.format("team=%d", teamID),
				string.format("ally=%d", select(6, Spring.GetTeamInfo(teamID, false)) or 0),
				"reason=" .. reason,
				string.format("frame=%d", Spring.GetGameFrame()),
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

			local av, ac = armyValue(teamID)
			parts[#parts + 1] = string.format("armyReal=%.0f", av)
			parts[#parts + 1] = string.format("armyCheap=%.0f", ac)

			local c1, c2, cm = builderCounts(teamID)
			parts[#parts + 1] = string.format("conT1=%d", c1)
			parts[#parts + 1] = string.format("conT2=%d", c2)
			parts[#parts + 1] = string.format("mCon=%.0f", cm)

			-- APM, plus the denominators that tell a wedged player from a dead
			-- one. cmdWindow is zeroed here so the next sample measures only
			-- its own interval.
			local ou, ob = ownUnitCounts(teamID)
			parts[#parts + 1] = string.format("cmds=%d", cmdCount[teamID] or 0)
			parts[#parts + 1] = string.format("cmdsWin=%d", cmdWindow[teamID] or 0)
			parts[#parts + 1] = string.format("ownUnits=%d", ou)
			parts[#parts + 1] = string.format("ownBuilders=%d", ob)
			parts[#parts + 1] = string.format("commIdle=%d", commIdle[teamID] or 0)
			parts[#parts + 1] = string.format("commSamp=%d", commSamp[teamID] or 0)
			parts[#parts + 1] = string.format("commBuild=%d", commBuild[teamID] or 0)
			parts[#parts + 1] = string.format("commMove=%d", commMove[teamID] or 0)
			parts[#parts + 1] = string.format("commAssistIdle=%d", commAssistIdle[teamID] or 0)
			parts[#parts + 1] = string.format("commAssist=%d", commAssist[teamID] or 0)
			parts[#parts + 1] = string.format("commStall=%d", commStall[teamID] or 0)
			parts[#parts + 1] = string.format("commCloakFlips=%d", commCloakFlips[teamID] or 0)

			local nf, nq = factoryQueueDepth(teamID)
			parts[#parts + 1] = string.format("facCount=%d", nf)
			parts[#parts + 1] = string.format("facQueued=%d", nq)

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
		end
	end
end

-- Building POSITIONS, as a separate line so nothing parsing BARAI_STATS breaks.
-- There was no positional telemetry in this project at all, so every claim about
-- base layout was inferred from reading placement code rather than measured.
-- Static buildings only, and only their footprint-relevant facts: id, x, z and
-- the def's footprint in build squares. That is enough to compute packing
-- density, nearest-neighbour spacing and row/column alignment offline.
local function dumpPositions()
	for _, teamID in ipairs(Spring.GetTeamList()) do
		local _, _, _, isAI = Spring.GetTeamInfo(teamID, false)
		if isAI then
			local out = {}
			for _, uid in ipairs(Spring.GetTeamUnits(teamID) or {}) do
				local udid = Spring.GetUnitDefID(uid)
				local ud = udid and UnitDefs[udid]
				if ud and ud.isBuilding and not ud.canMove then
					local x, _, z = Spring.GetUnitPosition(uid)
					if x then
						out[#out + 1] = string.format("%s:%d:%d:%d:%d",
								ud.name, x, z, ud.xsize or 0, ud.zsize or 0)
					end
				end
			end
			if #out > 0 then
				Spring.Echo(string.format("[BARAI_POS] team=%d ally=%d frame=%d n=%d %s",
						teamID, select(6, Spring.GetTeamInfo(teamID, false)) or 0,
						Spring.GetGameFrame(), #out, table.concat(out, ",")))
			end
		end
	end
end

function gadget:GameFrame(frame)
	if frame >= nextCommSample then
		nextCommSample = frame + COMM_SAMPLE
		sampleCommIdle()
	end
	if frame >= nextDump then
		nextDump = frame + DUMP_INTERVAL
		dump("periodic")
		dumpPositions()
	end
end

function gadget:GameOver()
	dump("gameover")
end

function gadget:Shutdown()
	dump("shutdown")
end
