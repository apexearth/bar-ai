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

function gadget:UnitDestroyed(unitID, unitDefID, unitTeam, attackerID, attackerDefID, attackerTeam)
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
	if attackerTeam ~= nil and attackerTeam ~= unitTeam then
		if cheap then
			bump(killCheap, attackerTeam, cost)
		else
			bump(killReal, attackerTeam, cost)
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

-- `io` is nil in the gadget sandbox, so emit through Spring.Echo and let the
-- harness parse the infolog it already collects. Last line per team wins.
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
				string.format("mKillCheap=%.0f", killCheap[teamID] or 0),
				string.format("mBuiltReal=%.0f", builtReal[teamID] or 0),
				string.format("mFactories=%.0f", facSpend[teamID] or 0),
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

			local av, ac = armyValue(teamID)
			parts[#parts + 1] = string.format("armyReal=%.0f", av)
			parts[#parts + 1] = string.format("armyCheap=%.0f", ac)

			local c1, c2, cm = builderCounts(teamID)
			parts[#parts + 1] = string.format("conT1=%d", c1)
			parts[#parts + 1] = string.format("conT2=%d", c2)
			parts[#parts + 1] = string.format("mCon=%.0f", cm)

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

function gadget:GameFrame(frame)
	if frame >= nextDump then
		nextDump = frame + DUMP_INTERVAL
		dump("periodic")
	end
end

function gadget:GameOver()
	dump("gameover")
end

function gadget:Shutdown()
	dump("shutdown")
end
