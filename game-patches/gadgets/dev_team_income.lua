--------------------------------------------------------------------------------
-- dev_team_income.lua -- publish per-team metal income as game rules params.
--
-- Why this exists: an AI cannot ask the engine what its allies are earning.
-- Game_getTeamResourceIncome() and every other Game_getTeamResource* call route
-- through aiGetTeamResource() in rts/ExternalAI/SSkirmishAICallbackImpl.cpp,
-- which gates on AI_TEAM_IDS[skirmishAIId]. That array is declared
--
--     static std::array<int, MAX_AIS> AI_TEAM_IDS = {{-1}};
--
-- and is never assigned anywhere in the engine -- so element 0 is -1, the rest
-- are 0, and the alliance check fails. Every such call returns -1.0. Verified
-- live: an AI querying its OWN team id got -1.0 back.
--
-- Synced Lua has no such restriction, so it publishes the figures instead and
-- the AI reads them with Game_getRulesParamFloat, which is not gated.
--
-- Consumed by CCircuitAI::GetTeamMetalIncome. If this gadget is absent the AI
-- reads the -1 default and falls back to the engine's own lead choice, so the
-- dependency degrades quietly rather than breaking.
--------------------------------------------------------------------------------

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
		name    = "Dev Team Income",
		desc    = "Publishes per-team metal income for AI ally coordination.",
		author  = "bar-ai",
		date    = "2026",
		license = "GNU GPL, v2 or later",
		layer   = 1002,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return
end

local INTERVAL = 30   -- 1s; keeps this off the per-frame path

-- The raw figure is NOT a usable measure of economic strength. Spring's income
-- (resPrevIncome) counts reclaim, so a builder eating one wreck spikes it for a
-- few seconds. The consumer picks which player the whole team will pool its
-- metal behind and then latches that choice, so a spike would hand the role to
-- whoever happened to be chewing a rock at that instant -- observed live: a team
-- read 25.8 metal/s at 2 minutes on what was almost certainly a reclaim event.
--
-- So publish an exponential moving average instead. ALPHA 0.03 at 1s samples is
-- roughly a 30-second time constant: a brief reclaim barely moves it, while a
-- genuinely better economy -- more mexes, more converters -- shows through.
-- Sustained reclaim is real economic strength and correctly still counts.
local ALPHA = 0.03

local avg = {}   -- teamID -> smoothed metal income
local next_at = 0

-- Cumulative metal gained from reclaiming wrecks, per team. Published as a
-- TEAM rules param so the AI can subtract the reclaim RATE from its income
-- anchors: labs and gantries are licensed off STRUCTURAL income (mex +
-- converters), not off a post-battle wreck feast (apexearth 2026-08-28:
-- "Make sure we aren't tricked by reclaim events which temporarily boost
-- our income"). Same callin as dev_stats_export's mReclaim.
local mRec = {}
local featMetalCache = {}

function gadget:AllowFeatureBuildStep(builderID, builderTeam, featureID, featureDefID, part)
	if part < 0 then
		local m = featMetalCache[featureDefID]
		if m == nil then
			local fd = FeatureDefs[featureDefID]
			m = (fd and fd.metal) or 0
			featMetalCache[featureDefID] = m
		end
		if m > 0 then
			mRec[builderTeam] = (mRec[builderTeam] or 0) - part * m
		end
	end
	return true
end

-- Cumulative waste ledger. resPrevExcess is the per-second overflow the engine
-- threw away after storage and sharing -- income that bought nothing. Summed at
-- 1s samples it approximates total wasted units; cumulative income is summed
-- the same way so the two are comparable as a share.
local waste = {}       -- teamID -> {mW, mI, eW, eI}
local next_waste_echo = 0
local WASTE_ECHO = 30 * 60   -- one report line per team per minute

--------------------------------------------------------------------------------
-- Tech-lead selection: whoever COMMITS first.
--
-- This used to elect the richest ally by smoothed income at 5 minutes. That
-- needed an EMA to survive reclaim spikes, a latch, hysteresis, a takeover path
-- for a lead that died or never teched, and a grace period so one missed
-- deadline did not cascade through the roster -- and it still had to guess who
-- WOULD tech from who was momentarily rich.
--
-- Commitment is the honest signal. An ally that has an advanced factory
-- nanoframe on the ground has already spent its own metal saying "I am teching";
-- fund that instead of predicting it. Everything above collapses:
--   - no income table needed for the choice, no EMA, no decision frame
--   - death needs no handling: if nobody has a T2 nanoframe the slot reopens
--     and the next committer takes it
--   - a lead that never techs cannot be chosen in the first place
--
-- Air is still excluded. An air opener cannot hold the ground the team is
-- buying, and pooling behind one is how a team ends up with no front line.
local AIR_FAC = {
	armap = true, armaap = true, corap = true,
	coraap = true, legap = true, legaap = true,
}

local techLvl = {}
local function techOf(ud)
	local t = techLvl[ud.id]
	if t == nil then
		t = tonumber((ud.customParams or {}).techlevel or 1) or 1
		techLvl[ud.id] = t
	end
	return t
end

-- Counts nanoframes: GetTeamUnits includes units under construction, which is
-- the whole point -- we want the moment of commitment, not of completion.
local function teching(teamID)
	local adv, air = false, false
	for _, uid in ipairs(Spring.GetTeamUnits(teamID) or {}) do
		local ud = UnitDefs[Spring.GetUnitDefID(uid)]
		if ud ~= nil then
			if AIR_FAC[ud.name] then air = true end
			if ud.isFactory and techOf(ud) >= 2 then adv = true end
		end
	end
	return adv, air
end

local LEAD_MIN_INCOME = 14.0   -- must match Factory::RUSH_MIN_METAL

local leadOf = {}   -- allyTeamID -> current target, or nil

local function updateLeads(frame)
	local byAlly = {}
	for _, t in ipairs(Spring.GetTeamList()) do
		local _, _, isDead, isAI, _, allyID = Spring.GetTeamInfo(t, false)
		if isAI and allyID ~= nil and not isDead then
			byAlly[allyID] = byAlly[allyID] or {}
			byAlly[allyID][#byAlly[allyID] + 1] = t
		end
	end

	-- No `goto`: Spring runs Lua 5.1 and `goto continue` is 5.2+. It does not
	-- warn -- the gadget simply fails to load and every AI silently falls back
	-- to the engine's own lead pick.
	for allyID, teams in pairs(byAlly) do
		local cur = leadOf[allyID]
		-- Keep the current target while it still holds an advanced factory.
		if cur ~= nil and not teching(cur) then
			leadOf[allyID] = nil   -- died, or lost the plant: reopen the slot
			cur = nil
		end
		if cur == nil then
			-- Lowest team id among those committed and not on air, so every
			-- reader agrees and the choice cannot flap between two simultaneous
			-- starters.
				-- Income floor. Commitment alone is not enough: a player that slaps
			-- down a lab at 3 minutes on 6 metal/s becomes the team's sink and
			-- everyone pools behind someone who cannot build anything with it.
			local pick = nil
			for _, t in ipairs(teams) do
				local adv, air = teching(t)
				if adv and not air and (avg[t] or 0) >= LEAD_MIN_INCOME
					and (pick == nil or t < pick) then pick = t end
			end
			if pick ~= nil then
				leadOf[allyID] = pick
				for _, t in ipairs(teams) do
					Spring.SetGameRulesParam("ai_lead_" .. t, pick)
				end
				BARAI_Echo(string.format(
					"[BARAI_LEAD] ally=%d team=%d inc=%.1f frame=%d min=%.1f why=committed-to-t2",
					allyID, pick, avg[pick] or 0, frame, frame / 1800))
			end
		end
	end
end

--------------------------------------------------------------------------------
-- TEAM FRONT: REMOVED 2026-08-11.
--
-- This published ai_frontx_<team>/ai_frontz_<team>, a point 78% of the way from
-- an ally's start position toward the enemy's, and Military::FrontPos read it.
-- apexearth: "remove the old gadget, we don't want a distraction which will
-- never work in multiplayer" -- and he is right twice over. A gadget lives in
-- BAR.sdd, which a hosted game does not load, so the whole of the defence
-- policy that keyed on it behaved one way on the bench and another in the games
-- this AI is for. It was also computed from START POSITIONS, so it never moved
-- as the battle did.
--
-- The front is computed from the influence map now -- Military::RebuildFront in
-- territory.as walks lanes across the map and takes the zero crossing of ally
-- minus enemy influence. That is engine-side, present in every game, and it
-- follows the fighting.

local handicapPublished = false

function gadget:GameFrame(frame)
	if frame < next_at then
		return
	end
	next_at = frame + INTERVAL

	-- Each team's income multiplier (Handicap=100 -> 2.0), once: the AI has
	-- no engine path to its own handicap, and role behaviour keys on it
	-- (gifting off at >= +50). Read via Game_getRulesParamFloat, ungated.
	if not handicapPublished then
		handicapPublished = true
		for _, teamID in ipairs(Spring.GetTeamList()) do
			local mult = select(7, Spring.GetTeamInfo(teamID, false))
			if type(mult) == "number" and mult > 0 then
				Spring.SetGameRulesParam("ai_handicap_" .. teamID, mult)
			end
		end
	end

	for _, teamID in ipairs(Spring.GetTeamList()) do
		-- GetTeamResources returns: current, storage, pull, income, expense,
		-- share, sent, received, excess
		local _, _, _, income, _, _, _, _, mExcess =
			Spring.GetTeamResources(teamID, "metal")
		if income ~= nil then
			local prev = avg[teamID]
			if prev == nil then
				avg[teamID] = income
			else
				avg[teamID] = prev + ALPHA * (income - prev)
			end
			Spring.SetGameRulesParam("ai_minc_" .. teamID, avg[teamID])
			-- Raw value kept alongside for diagnostics.
			Spring.SetGameRulesParam("ai_mincraw_" .. teamID, income)
			Spring.SetTeamRulesParam(teamID, "apexReclaimM", mRec[teamID] or 0)

			local _, _, _, eIncome, _, _, _, _, eExcess =
				Spring.GetTeamResources(teamID, "energy")
			local w = waste[teamID]
			if w == nil then
				w = { mW = 0, mI = 0, eW = 0, eI = 0, eC = 0 }
				waste[teamID] = w
			end
			w.mW = w.mW + (mExcess or 0)
			w.mI = w.mI + income
			w.eW = w.eW + (eExcess or 0)
			w.eI = w.eI + (eIncome or 0)
			-- energy the converters burned (game_energy_conversion's per-second mmUse): eMade
			-- is gross, so a converter's metal was counted on top of the energy it ate
			w.eC = w.eC + (Spring.GetTeamRulesParam(teamID, "mmUse") or 0)
			Spring.SetGameRulesParam("ai_mwaste_" .. teamID, w.mW)
			Spring.SetGameRulesParam("ai_ewaste_" .. teamID, w.eW)
		end
	end

	if frame >= next_waste_echo then
		next_waste_echo = frame + WASTE_ECHO
		for teamID, w in pairs(waste) do
			BARAI_Echo(string.format(
				"[BARAI_WASTE] frame=%d team=%d mWaste=%.0f mMade=%.0f eWaste=%.0f eMade=%.0f eConv=%.0f",
				frame, teamID, w.mW, w.mI, w.eW, w.eI, w.eC or 0))
		end
	end

	-- After the incomes above are current, never against a half-updated table.
	updateLeads(frame)
end
