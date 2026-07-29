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

-- Income is a smoothed per-second figure already; a 1s refresh is plenty and
-- keeps this off the per-frame path.
local INTERVAL = 30
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
			Spring.SetGameRulesParam("ai_minc_" .. teamID, income)
		end
	end
end
