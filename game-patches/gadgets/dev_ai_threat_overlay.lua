--------------------------------------------------------------------------------
-- dev_ai_threat_overlay.lua -- paint the AI's OWN influence/threat grid on the map.
--
-- CircuitAI already ships the whole pipeline and nothing was listening to it:
--   * `~widraw <teamId>` / `~wtdraw <teamId>` in chat toggle it (CircuitAI.cpp),
--   * the AI then asks LuaRules `ai_thr_draw:` and only enables itself if
--     something answers "1" (InfluenceMap.cpp ToggleWidgetDraw),
--   * once on it sends `ai_thr_size:<squareSize> <base>` and then, every update,
--     `ai_thr_data:` followed by the raw float array of the whole grid.
-- Without a listener the handshake fails silently and the AI never sends, which
-- is why `~widraw 0` appeared to do nothing.
--
-- RecvSkirmishAIMessage is ALWAYS unsynced (LuaHandle.cpp: "the AI call-in is
-- always unsynced"), and CircuitAI uses CallRules, so this must be the unsynced
-- half of a LuaRules gadget -- not a widget, and not the synced half.
--
-- Dev only: it never ships to multiplayer, and it draws nothing until asked.
--------------------------------------------------------------------------------

function gadget:GetInfo()
	return {
		name    = "Dev AI Threat Overlay",
		desc    = "Draws the AI's influence/threat grid. Toggle with ~widraw <team> or ~wtdraw <team>.",
		author  = "apex",
		date    = "2026-08-22",
		license = "GPL v2 or later",
		layer   = 0,
		enabled = true,
	}
end

if gadgetHandler:IsSyncedCode() then
	return   -- the AI call-in is unsynced; the synced half has no part in this
end

local drawing    = false
local squareSize = 0
local base       = 0
local gw, gh     = 0, 0
local cells      = nil     -- flat array of floats, row-major: z * gw + x
local dirty      = false
local dlist      = nil

-- What counts as "worth colouring". The array is ally-minus-enemy with a base
-- offset, so values sit near zero over most of the map and painting those just
-- fogs the screen.
local EPS = 0.5
-- Full saturation at this magnitude. The AI's own SDL debug view divides by 200,
-- so the same scale keeps this readable against it.
local FULL = 200.0

local glColor           = gl.Color
local glDrawGroundQuad  = gl.DrawGroundQuad
local glDepthTest       = gl.DepthTest
local glBlending        = gl.Blending
local glCreateList      = gl.CreateList
local glCallList        = gl.CallList
local glDeleteList      = gl.DeleteList

-- Derive the grid shape. width/height come from the AI's sector grid
-- (InfluenceMap.cpp: width = SectorXSize/4, squareSize = ConvertStoP*4), so the
-- division below reproduces them -- but the float count is authoritative, so it
-- is checked and the aspect ratio used as the fallback.
local function shapeGrid(count)
	if squareSize <= 0 then return false end
	local w = math.floor(Game.mapSizeX / squareSize)
	local h = math.floor(Game.mapSizeZ / squareSize)
	if w * h ~= count then
		-- Recover a shape with the map's aspect that multiplies out exactly.
		w = math.max(1, math.floor(math.sqrt(count * Game.mapSizeX / Game.mapSizeZ) + 0.5))
		while w > 1 and (count % w) ~= 0 do w = w - 1 end
		h = math.floor(count / w)
	end
	if w * h ~= count then return false end
	gw, gh = w, h
	return true
end

local function unpackFloats(data)
	-- The payload is raw little-endian float32s straight out of a std::vector.
	local n = math.floor(#data / 4)
	if n < 1 then return nil, 0 end
	-- UnpackF32(str, pos, count) returns a TABLE when count is given (LuaVFS.cpp
	-- UnpackType), not a vararg list -- wrapping it in braces would nest it.
	local ok, vals = pcall(VFS.UnpackF32, data, 1, n)
	if ok and vals and #vals == n then
		return vals, n
	end
	return nil, 0
end

function gadget:RecvSkirmishAIMessage(aiTeam, msg)
	if type(msg) ~= "string" then return end

	if msg:sub(1, 12) == "ai_thr_draw:" then
		-- The AI sets its own flag from THIS answer, so alternating makes the
		-- chat command a real toggle instead of a one-way switch.
		drawing = not drawing
		if not drawing then
			cells = nil
			dirty = true
		end
		Spring.Echo("[ai-overlay] " .. (drawing and "ON" or "OFF") .. " for AI team " .. tostring(aiTeam))
		return drawing and "1" or "0"
	end

	if msg:sub(1, 12) == "ai_thr_size:" then
		local s, b = msg:match("^ai_thr_size:(%-?%d+)%s+(%-?[%d%.eE%+]+)")
		squareSize = tonumber(s) or 0
		base = tonumber(b) or 0
		gw, gh = 0, 0
		Spring.Echo("[ai-overlay] cell " .. tostring(squareSize) .. " elmos, base " .. tostring(base))
		return
	end

	if msg:sub(1, 12) == "ai_thr_data:" then
		if not drawing then return end
		local vals, n = unpackFloats(msg:sub(13))
		if not vals then return end
		if (gw * gh) ~= n and not shapeGrid(n) then return end
		cells = vals
		dirty = true
		return
	end
end

-- Enemy influence reads red, ours reads green, and the band between is left
-- clear so the contested edge is the thing that stands out.
local function colourFor(v)
	local m = math.min(math.abs(v) / FULL, 1.0)
	local a = 0.15 + 0.45 * m
	if v < 0 then
		return 1.0, 0.85 - 0.85 * m, 0.0, a      -- yellow -> red as it worsens
	end
	return 0.0, 0.9, 0.35, a * 0.7               -- our ground, quieter
end

local function buildList()
	if not cells or gw <= 0 or gh <= 0 then return nil end
	return glCreateList(function()
		for z = 0, gh - 1 do
			local row = z * gw
			for x = 0, gw - 1 do
				local v = cells[row + x + 1]
				if v then
					v = v - base
					if v > EPS or v < -EPS then
						glColor(colourFor(v))
						glDrawGroundQuad(x * squareSize, z * squareSize,
								(x + 1) * squareSize, (z + 1) * squareSize)
					end
				end
			end
		end
	end)
end

function gadget:DrawWorldPreUnit()
	if not drawing then return end
	if dirty then
		if dlist then glDeleteList(dlist) end
		dlist = buildList()
		dirty = false
	end
	if not dlist then return end
	glDepthTest(false)
	glBlending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)
	glCallList(dlist)
	glColor(1, 1, 1, 1)
	glBlending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)
	glDepthTest(true)
end

function gadget:Shutdown()
	if dlist then glDeleteList(dlist) end
	dlist = nil
end
