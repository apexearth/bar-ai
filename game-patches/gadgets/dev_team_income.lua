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
end
