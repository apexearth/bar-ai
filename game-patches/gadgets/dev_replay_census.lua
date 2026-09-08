--------------------------------------------------------------------------------
-- dev_replay_census.lua -- what stood, and what each team earned, minute by
-- minute, while WATCHING A REPLAY.
--
-- Unsynced only, so it cannot touch the simulation and a replay stays valid.
-- The synced stats gadget needs the dev_stats modoption, which a lobby game
-- never sets, so a human's canon game (apexearth, 2026-09-08: "you should be
-- able to replay my game from the demo file") has no census without this.
-- Inert outside replays.
--------------------------------------------------------------------------------

function gadget:GetInfo()
	return {
		name    = "Dev Replay Census",
		desc    = "Per-team income and standing units every minute of a replay.",
		author  = "bar-ai",
		date    = "2026",
		license = "GNU GPL, v2 or later",
		layer   = 1003,
		enabled = true,
	}
end

if gadgetHandler:IsSyncedCode() then
	return
end

local INTERVAL = 1800   -- one game minute

function gadget:Initialize()
	if not Spring.IsReplay() then
		gadgetHandler:RemoveGadget(self)
		return
	end
	-- A spectator without full view reads nothing; the replay is a spectator.
	Spring.SendCommands({"specfullview 3"})
end

function gadget:GameFrame(frame)
	if frame % INTERVAL ~= 0 then
		return
	end
	local gaia = Spring.GetGaiaTeamID()
	for _, teamID in ipairs(Spring.GetTeamList()) do
		if teamID ~= gaia then
			local mc, ms, mp, mi = Spring.GetTeamResources(teamID, "metal")
			local ec, es, ep, ei = Spring.GetTeamResources(teamID, "energy")
			local counts = {}
			local builders, busy = 0, 0
			for _, uid in ipairs(Spring.GetTeamUnits(teamID) or {}) do
				local udid = Spring.GetUnitDefID(uid)
				local ud = udid and UnitDefs[udid]
				if ud ~= nil and not Spring.GetUnitIsBeingBuilt(uid) then
					counts[ud.name] = (counts[ud.name] or 0) + 1
					if ud.isBuilder and not ud.isFactory then
						builders = builders + 1
						if Spring.GetUnitIsBuilding(uid) then
							busy = busy + 1
						end
					end
				end
			end
			local parts = {}
			for name, n in pairs(counts) do
				parts[#parts + 1] = name .. ":" .. n
			end
			table.sort(parts)
			Spring.Echo(string.format(
				"[BARAI_CENSUS] frame=%d team=%d mInc=%.1f mPull=%.1f mCur=%.0f/%.0f eInc=%.1f ePull=%.1f eCur=%.0f/%.0f builders=%d busy=%d units=%s",
				frame, teamID, mi or 0, mp or 0, mc or 0, ms or 0, ei or 0, ep or 0, ec or 0, es or 0,
				builders, busy, table.concat(parts, ",")))
		end
	end
end
