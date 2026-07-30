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

--------------------------------------------------------------------------------
-- Tech-lead election.
--
-- Elected here, not per-AI. Each AI instance reads this table at a different
-- frame (SlowUpdate is offset by skirmishAIId), and the table is rewritten every
-- INTERVAL frames, so instances scanning it themselves could disagree and elect
-- two leads -- seen in 1 of 533 archived matches. One synced writer removes the
-- race by construction.
--
-- Factory::RushLeadTeamId() only reads the result; the policy lives here.
local DECIDE_FRAME  = 5 * 60 * 30   -- 5 minutes: before this, income is noise
local DECIDE_INCOME = 15.0          -- ...unless someone is already clearly ahead

-- Takeover: the team's whole investment rides on the lead, so replace one that
-- cannot deliver. Two triggers -- dead (immediate), and no advanced factory by
-- TECH_DEADLINE. hasAdvancedFactory() counts nanoframes, so a lead that has
-- committed and is building passes; only "never started" fails.
local TECH_DEADLINE  = 10 * 60 * 30
-- Past this, a takeover cannot pay for itself: every follower has had its own
-- no-bank switch since FOLLOWER_TECH_FRAME (10 min) and is teching anyway, so
-- starting a fresh pooling round just takes a second player out of the fight.
local TAKEOVER_UNTIL = 15 * 60 * 30
-- Grace before a new appointee is judged. Without it one missed deadline
-- cascaded through all eight teams in 210 frames (seen in an 8v8). Death is
-- exempt.
local TAKEOVER_GRACE = 3 * 60 * 30

local leadOf = {}      -- allyTeamID -> current lead teamID
local failed = {}      -- teamID -> true; never elected again
local abandoned = {}   -- allyTeamID -> true; no eligible successor, stop trying
local judgeAt = {}     -- allyTeamID -> frame the current lead may first be judged

local techLvl = {}  -- unitDefID -> techlevel (cached)
local function techOf(ud)
	local t = techLvl[ud.id]
	if t == nil then
		t = tonumber((ud.customParams or {}).techlevel or 1) or 1
		techLvl[ud.id] = t
	end
	return t
end

local function isAlive(teamID)
	local _, _, isDead = Spring.GetTeamInfo(teamID, false)
	if isDead then
		return false
	end
	-- Formally alive but stripped of every unit counts as gone.
	local units = Spring.GetTeamUnits(teamID)
	return units ~= nil and #units > 0
end

-- Counts nanoframes: GetTeamUnits includes units under construction, which is
-- exactly the distinction between "slow" and "never committed".
local function hasAdvancedFactory(teamID)
	for _, uid in ipairs(Spring.GetTeamUnits(teamID) or {}) do
		local ud = UnitDefs[Spring.GetUnitDefID(uid)]
		if ud ~= nil and ud.isFactory and techOf(ud) >= 2 then
			return true
		end
	end
	return false
end

local function pickLead(teams)
	local best, bestInc = nil, -1
	for _, teamID in ipairs(teams) do
		if not failed[teamID] and isAlive(teamID) then
			local inc = avg[teamID]
			-- Ties break on lowest team id. `best == nil` first: comparing against
			-- a nil best would throw and silently kill the election.
			if inc ~= nil and (best == nil or inc > bestInc
				or (inc == bestInc and teamID < best))
			then
				best, bestInc = teamID, inc
			end
		end
	end
	return best, bestInc
end

-- Keyed by the READING team's id, not by ally. ai.allyTeamId reads 0 for every
-- instance in the shipped DLL, so an ally-keyed param had ally 1's followers
-- adopt ally 0's lead and sling their metal to an enemy team.
local function setLead(allyID, teams, teamID, inc, frame, why)
	leadOf[allyID] = teamID
	judgeAt[allyID] = frame + TAKEOVER_GRACE
	for _, t in ipairs(teams) do
		Spring.SetGameRulesParam("ai_lead_" .. t, teamID)
	end
	Spring.Echo(string.format(
		"[BARAI_LEAD] ally=%d team=%d inc=%.1f frame=%d min=%.1f why=%s",
		allyID, teamID, inc, frame, frame / 1800, why))
end

--------------------------------------------------------------------------------
-- Enemy bearing.
--
-- CEnemyManager::GetEnemyPos() exists in C++ and DefaultMakeDefence already
-- orients towers along it, but it is not bound to AngelScript -- so the script
-- cannot tell which way the enemy is. Publish it here, same pattern as the
-- income table.
--
-- Start positions, not live unit centroids: bases do not move, roaming armies
-- do, and what defence wants is "which way is their base", not "where is their
-- raiding party this second".
local enemyPos = {}   -- teamID -> {x, z}, computed once

local function publishEnemyPos()
	if next(enemyPos) ~= nil then
		return
	end
	local byAlly = {}
	for _, t in ipairs(Spring.GetTeamList()) do
		local _, _, _, _, _, allyID = Spring.GetTeamInfo(t, false)
		local x, y, z = Spring.GetTeamStartPosition(t)
		if allyID ~= nil and x ~= nil then
			byAlly[allyID] = byAlly[allyID] or {}
			table.insert(byAlly[allyID], {x = x, z = z})
		end
	end
	for _, t in ipairs(Spring.GetTeamList()) do
		local _, _, _, isAI, _, allyID = Spring.GetTeamInfo(t, false)
		if isAI and allyID ~= nil then
			local sx, sz, n = 0, 0, 0
			for a, list in pairs(byAlly) do
				if a ~= allyID then
					for _, q in ipairs(list) do sx, sz, n = sx + q.x, sz + q.z, n + 1 end
				end
			end
			if n > 0 then
				enemyPos[t] = true
				Spring.SetGameRulesParam("ai_enemyx_" .. t, sx / n)
				Spring.SetGameRulesParam("ai_enemyz_" .. t, sz / n)
			end
		end
	end
	if next(enemyPos) ~= nil then
		Spring.Echo("[BARAI_ENEMYPOS] published for " .. tostring(#Spring.GetTeamList()) .. " teams")
	end
end

local function updateLeads(frame)
	-- Group AI teams by ally. Non-AI teams are excluded: a human is not running
	-- this strategy and cannot be pooled behind.
	local byAlly = {}
	for _, teamID in ipairs(Spring.GetTeamList()) do
		local _, _, _, isAI, _, allyID = Spring.GetTeamInfo(teamID, false)
		if isAI and allyID ~= nil then
			byAlly[allyID] = byAlly[allyID] or {}
			byAlly[allyID][#byAlly[allyID] + 1] = teamID
		end
	end

	for allyID, teams in pairs(byAlly) do
		local cur = leadOf[allyID]
		if cur == nil then
			local best, inc = pickLead(teams)
			if best ~= nil and (frame >= DECIDE_FRAME or inc >= DECIDE_INCOME) then
				setLead(allyID, teams, best, inc, frame, "elected")
			end
		elseif frame <= TAKEOVER_UNTIL and not abandoned[allyID] then
			local why = nil
			if not isAlive(cur) then
				why = "lead-lost"
			elseif frame >= TECH_DEADLINE and frame >= (judgeAt[allyID] or 0)
				and not hasAdvancedFactory(cur) then
				why = "no-t2-by-deadline"
			end
			if why ~= nil then
				failed[cur] = true
				local best, inc = pickLead(teams)
				if best ~= nil then
					setLead(allyID, teams, best, inc, frame, why .. "-took-over-from-" .. cur)
				else
					-- Nobody eligible left. Leave the param as-is and stop trying,
					-- or the same dead lead re-triggers every check.
					abandoned[allyID] = true
					Spring.Echo(string.format(
						"[BARAI_LEAD] ally=%d team=-1 inc=0.0 frame=%d min=%.1f why=%s-no-successor",
						allyID, frame, frame / 1800, why))
				end
			end
		end
	end
end

function gadget:GameFrame(frame)
	if frame < next_at then
		return
	end
	next_at = frame + INTERVAL

	for _, teamID in ipairs(Spring.GetTeamList()) do
		-- GetTeamResources returns: current, storage, pull, income, expense,
		-- share, sent, received
		local _, _, _, income = Spring.GetTeamResources(teamID, "metal")
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
		end
	end

	-- After the incomes above are current, never against a half-updated table.
	updateLeads(frame)
	publishEnemyPos()
end
