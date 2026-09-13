--------------------------------------------------------------------------------
-- dev_order_counter.lua -- count every unit order per team, bucketed by class.
--
-- Why this exists: the AI's own timers measure time spent DECIDING; they miss
-- what the engine spends EXECUTING those decisions (command processing,
-- pathfinding, movement). AllowCommand is the one funnel every order passes
-- through -- C++ tasks and AngelScript alike -- so counting here is the
-- ground truth for "how many actions does each AI put into the sim".
--
-- One line per team per game-minute:
--   ORDERS team=3 min=12 total=843 move=120 fight=85 build=310 repair=190
--          reclaim=60 guard=40 stop=18 other=20 oth34923=18 oth45=2
-- othNNN is the raw command id behind "other", biggest first.
-- Parsed by tools/orders.py.
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
		name    = "Dev Order Counter",
		desc    = "Counts unit orders per team per minute, by command class.",
		author  = "bar-ai",
		date    = "2026",
		license = "GNU GPL, v2 or later",
		layer   = 1003,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return
end

local INTERVAL = 1800  -- one game-minute

local CMD_MOVE      = CMD.MOVE
local CMD_FIGHT     = CMD.FIGHT
local CMD_ATTACK    = CMD.ATTACK
local CMD_PATROL    = CMD.PATROL
local CMD_REPAIR    = CMD.REPAIR
local CMD_RECLAIM   = CMD.RECLAIM
local CMD_GUARD     = CMD.GUARD
local CMD_STOP      = CMD.STOP
local CMD_WAIT      = CMD.WAIT

local counts = {}  -- teamID -> {class -> n}

local function bucket(cmdID)
	if cmdID < 0 then return "build" end  -- negative ids are build orders
	if cmdID == CMD_MOVE then return "move" end
	if cmdID == CMD_FIGHT or cmdID == CMD_ATTACK then return "fight" end
	if cmdID == CMD_PATROL then return "patrol" end
	if cmdID == CMD_REPAIR then return "repair" end
	if cmdID == CMD_RECLAIM then return "reclaim" end
	if cmdID == CMD_GUARD then return "guard" end
	if cmdID == CMD_STOP or cmdID == CMD_WAIT then return "stop" end
	return "other"
end

function gadget:AllowCommand(unitID, unitDefID, unitTeam, cmdID, cmdParams,
		cmdOptions, cmdTag, playerID, fromSynced, fromLua)
	local t = counts[unitTeam]
	if not t then
		t = { total = 0, oth = {} }
		counts[unitTeam] = t
	end
	t.total = t.total + 1
	local b = bucket(cmdID)
	t[b] = (t[b] or 0) + 1
	-- "other" was the second-largest bucket and named nothing. Keep the raw ids
	-- so the line says WHICH command it is (34923 is set-target, and so on).
	if b == "other" then
		t.oth[cmdID] = (t.oth[cmdID] or 0) + 1
	end
	return true
end

local ORDER = { "move", "fight", "patrol", "build", "repair", "reclaim",
	"guard", "stop", "other" }

function gadget:GameFrame(f)
	if f == 0 or (f % INTERVAL) ~= 0 then
		return
	end
	local minute = f / INTERVAL
	for teamID, t in pairs(counts) do
		if t.total > 0 then
			local parts = { "ORDERS team=" .. teamID .. " min=" .. minute
				.. " total=" .. t.total }
			for i = 1, #ORDER do
				local k = ORDER[i]
				if t[k] then
					parts[#parts + 1] = k .. "=" .. t[k]
				end
			end
			local ids = {}
			for id, n in pairs(t.oth) do
				ids[#ids + 1] = { id = id, n = n }
			end
			table.sort(ids, function(a, b) return a.n > b.n end)
			for i = 1, math.min(6, #ids) do
				parts[#parts + 1] = "oth" .. ids[i].id .. "=" .. ids[i].n
			end
			BARAI_Echo(table.concat(parts, " "))
		end
	end
	counts = {}
end
