function widget:GetInfo()
	return { name = "BARAI replay census", desc = "per-team census each minute, fast replay",
		author = "bar-ai", layer = 0, enabled = true }
end

function widget:Initialize()
	if not Spring.IsReplay() then
		widgetHandler:RemoveWidget(self)
		return
	end
	Spring.SendCommands({"specfullview 3", "setmaxspeed 80", "setminspeed 80"})
end

local nextSpeed = 300
function widget:GameFrame(frame)
	if frame >= nextSpeed then
		nextSpeed = frame + 300
		Spring.SendCommands({"setmaxspeed 80", "setminspeed 80"})
	end
	if frame % 1800 ~= 0 then
		return
	end
	for _, teamID in ipairs(Spring.GetTeamList()) do
		if teamID ~= Spring.GetGaiaTeamID() then
			local _, _, _, mi = Spring.GetTeamResources(teamID, "metal")
			local _, _, _, ei = Spring.GetTeamResources(teamID, "energy")
			local counts, builders, busy = {}, 0, 0
			for _, uid in ipairs(Spring.GetTeamUnits(teamID) or {}) do
				local ud = UnitDefs[Spring.GetUnitDefID(uid) or -1]
				if ud and not Spring.GetUnitIsBeingBuilt(uid) then
					counts[ud.name] = (counts[ud.name] or 0) + 1
					if ud.isBuilder and not ud.isFactory and ud.canMove then
						builders = builders + 1
						if Spring.GetUnitIsBuilding(uid) then busy = busy + 1 end
					end
				end
			end
			local parts = {}
			for name, n in pairs(counts) do parts[#parts + 1] = name .. ":" .. n end
			table.sort(parts)
			Spring.Echo(string.format("[BARAI_CENSUS] frame=%d team=%d mInc=%.1f eInc=%.1f builders=%d busy=%d units=%s",
				frame, teamID, mi or 0, ei or 0, builders, busy, table.concat(parts, ",")))
		end
	end
end
