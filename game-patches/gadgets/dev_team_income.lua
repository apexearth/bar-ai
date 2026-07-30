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
				Spring.Echo(string.format(
					"[BARAI_LEAD] ally=%d team=%d inc=%.1f frame=%d min=%.1f why=committed-to-t2",
					allyID, pick, avg[pick] or 0, frame, frame / 1800))
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Team front.
--
-- Every AI reasons only about its own clusters, so a back-line player builds its
-- big guns in its own base where nothing is attacking -- apexearth, watching:
-- "he makes a T3 defence in his base, instead of going to the front player's
-- base and placing it there to protect them ... T3 is good kinda like at the
-- 75% or 80% edge of the TEAM border, not just their own border".
--
-- Publish that point: from the ally's own centroid, FRONT_FRAC of the way toward
-- the enemy's. Start positions, because bases do not move and this must be
-- stable -- a front that wanders makes placement flap.
local FRONT_FRAC = 0.78
local frontDone = false

local function publishFront()
	if frontDone then
		return
	end
	local byAlly = {}
	for _, t in ipairs(Spring.GetTeamList()) do
		local _, _, _, _, _, allyID = Spring.GetTeamInfo(t, false)
		local x, _, z = Spring.GetTeamStartPosition(t)
		if allyID ~= nil and x ~= nil then
			local a = byAlly[allyID] or {x = 0, z = 0, n = 0, pts = {}}
			a.x, a.z, a.n = a.x + x, a.z + z, a.n + 1
			a.pts[#a.pts + 1] = {x = x, z = z}
			byAlly[allyID] = a
		end
	end
	if next(byAlly) == nil then
		return
	end
	for _, t in ipairs(Spring.GetTeamList()) do
		local _, _, _, isAI, _, allyID = Spring.GetTeamInfo(t, false)
		local mine = allyID ~= nil and byAlly[allyID]
		if isAI and mine and mine.n > 0 then
			local ex, ez, en = 0, 0, 0
			for a, v in pairs(byAlly) do
				if a ~= allyID then ex, ez, en = ex + v.x, ez + v.z, en + v.n end
			end
			if en > 0 then
				local mx, mz = mine.x / mine.n, mine.z / mine.n
				local tx, tz = ex / en, ez / en
				-- The front is a LINE, not a point. A single centroid sends every
				-- player's defence to the same spot and leaves the flanks open.
				-- Project each team's own start onto the axis perpendicular to
				-- "toward the enemy", and give it a front point at the same
				-- lateral offset -- so a left-flank player defends the left of the
				-- line and a right-flank player the right, each covering its own
				-- stretch rather than piling onto one spot.
				local dx, dz = tx - mx, tz - mz
				local len = math.sqrt(dx * dx + dz * dz)
				if len > 1 then
					local px, pz = -dz / len, dx / len   -- perpendicular, unit
					-- team half-width along that perpendicular
					local half = 0
					for _, q in ipairs(mine.pts) do
						local d = math.abs((q.x - mx) * px + (q.z - mz) * pz)
						if d > half then half = d end
					end
					if half < 256 then half = 256 end
					local bx = mx + dx * FRONT_FRAC
					local bz = mz + dz * FRONT_FRAC
					-- Which slot is this team's? Nearest by its own offset.
					local mine_x, _, mine_z = Spring.GetTeamStartPosition(t)
					local off = ((mine_x or mx) - mx) * px + ((mine_z or mz) - mz) * pz
					local frac = math.max(-1, math.min(1, off / half))
					Spring.SetGameRulesParam("ai_frontx_" .. t, bx + px * half * frac)
					Spring.SetGameRulesParam("ai_frontz_" .. t, bz + pz * half * frac)
					frontDone = true
				end
			end
		end
	end
	if frontDone then
		Spring.Echo("[BARAI_FRONT] published at " .. FRONT_FRAC .. " toward the enemy")
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
	publishFront()
end
