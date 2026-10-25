--------------------------------------------------------------------------------
-- dev_ai_thoughts_panel.lua -- what each Apex AI seat is thinking, on screen.
--
-- His 10-24: "a UI widget which showed everything about what the AI is thinking/doing to help in realtime visual
-- debugging"; "ideally I should be able to move around this widget window and shrink it". With apex_verbose=1 each
-- seat sends `ai_think:<team>\n<lines>` every 3 s (ai.SendToLua); the LuaRules gadget dev_ai_thoughts.lua hands each
-- one to this widget (Script.LuaUI.AiThoughts).
--
--   drag a seat's header bar to move the panel; click [-]/[+] on a header to collapse or expand that seat;
--   mouse wheel over the panel to shrink or grow it. Position, size and collapsed seats are remembered.
--
-- Unsynced widget, local only: it reads what the AI sent and draws; it cannot affect or desync a game.
-- Install: python tools/deploy_ai.py widgets
--------------------------------------------------------------------------------

function widget:GetInfo()
	return {
		name    = "Apex AI Thoughts",
		desc    = "Each Apex AI seat's plan, phase, threat modifier, prices and recent decisions (apex_verbose=1).",
		author  = "bar-ai",
		date    = "2026-10-24",
		license = "GNU GPL, v2 or later",
		layer   = 1000,   -- drawn after the other widgets
		enabled = true,
	}
end

local BASE_H     = 1080
local HEAD_FONT  = 16
local ROW_FONT   = 14
local LINE_BASE  = 18
local WIDTH_BASE = 760
local STALE_S    = 30

local vsx, vsy = Spring.GetViewGeometry()
local zoom = 1.0          -- the wheel's size factor
local posX, posY = nil, nil   -- top-left corner of the panel, screen pixels
local collapsed = {}      -- team -> true
local scale, headFont, rowFont, lineH, width, pad

local function rescale()
	scale = math.max(1, vsy / BASE_H) * zoom
	headFont = HEAD_FONT * scale
	rowFont  = ROW_FONT * scale
	lineH    = LINE_BASE * scale
	width    = WIDTH_BASE * scale
	pad      = 8 * scale
end
rescale()

local glText  = gl.Text
local glColor = gl.Color
local glRect  = gl.Rect

local seats = {}
local order = {}
local headers = {}        -- {team, x0, y0, x1, y1, tx0} for hit tests, rebuilt each draw
local panelBox = nil      -- {x0, y0, x1, y1}
local dragging = false
local dragDX, dragDY = 0, 0

local function onThought(team, msg)
	if type(msg) ~= "string" or msg:sub(1, 9) ~= "ai_think:" then
		return
	end
	local lines = {}
	for line in msg:sub(10):gmatch("[^\n]+") do
		lines[#lines + 1] = line
	end
	local t = tonumber(lines[1]) or team
	table.remove(lines, 1)
	if not seats[t] then
		order[#order + 1] = t
	end
	seats[t] = { lines = lines, at = Spring.GetGameSeconds() }
end

function widget:Initialize()
	widgetHandler:RegisterGlobal("AiThoughts", onThought)
end

function widget:Shutdown()
	widgetHandler:DeregisterGlobal("AiThoughts")
end

function widget:ViewResize(x, y)
	vsx, vsy = x, y
	rescale()
end

function widget:GetConfigData()
	local c = {}
	for t, v in pairs(collapsed) do
		if v then c[#c + 1] = t end
	end
	return { posX = posX, posY = posY, zoom = zoom, collapsed = c }
end

function widget:SetConfigData(data)
	posX = data.posX
	posY = data.posY
	zoom = data.zoom or 1.0
	collapsed = {}
	for _, t in ipairs(data.collapsed or {}) do
		collapsed[t] = true
	end
	rescale()
end

function widget:DrawScreen()
	headers = {}
	panelBox = nil
	if #order == 0 then
		return
	end
	-- his 10-24: "It is behind the map now" -- a depth test left on by another drawer put the terrain in front
	gl.DepthTest(false)
	gl.DepthMask(false)
	gl.Blending(true)
	gl.Texture(false)
	local now = Spring.GetGameSeconds()
	local x = posX or (16 * scale)
	local top = posY or (vsy - 90 * scale)
	local y0 = top
	for _, t in ipairs(order) do
		local s = seats[t]
		if s and (now - s.at) < STALE_S then
			local rows = collapsed[t] and 0 or #s.lines
			local h = (rows + 1) * lineH
			glColor(0, 0, 0, 0.6)
			glRect(x - pad, top - h - pad, x + width + pad, top + pad)
			local r, g, b = Spring.GetTeamColor(t)
			glColor(r or 1, g or 1, b or 1, 0.35)
			glRect(x - pad, top - lineH - pad * 0.5, x + width + pad, top + pad)
			glColor(r or 1, g or 1, b or 1, 1)
			local head = "APEX SEAT " .. t
			if collapsed[t] and s.lines[1] then
				head = head .. "   " .. s.lines[1]
			end
			glText(head, x, top - lineH, headFont, "o")
			glColor(1, 1, 1, 1)
			glText(collapsed[t] and "[+]" or "[-]", x + width - 2 * headFont, top - lineH, headFont, "o")
			headers[#headers + 1] = { t, x - pad, top - lineH - pad * 0.5, x + width + pad, top + pad, x + width - 2.5 * headFont }
			if not collapsed[t] then
				for i, line in ipairs(s.lines) do
					glColor(1, 1, 1, (i <= 3) and 1.0 or 0.8)
					glText(line, x, top - lineH - i * lineH, rowFont, "o")
				end
			end
			top = top - h - 3 * pad
		end
	end
	panelBox = { x - pad, top + 2 * pad, x + width + pad, y0 + pad }
	glColor(1, 1, 1, 1)
end

local function headerAt(mx, my)
	for _, hd in ipairs(headers) do
		if (mx >= hd[2]) and (mx <= hd[4]) and (my >= hd[3]) and (my <= hd[5]) then
			return hd
		end
	end
	return nil
end

function widget:IsAbove(mx, my)
	return panelBox ~= nil and mx >= panelBox[1] and mx <= panelBox[3] and my >= panelBox[2] and my <= panelBox[4]
end

function widget:MousePress(mx, my, button)
	if button ~= 1 then
		return false
	end
	local hd = headerAt(mx, my)
	if not hd then
		return false
	end
	if mx >= hd[6] then
		collapsed[hd[1]] = not collapsed[hd[1]]
		return true
	end
	dragging = true
	local x = posX or (16 * scale)
	local top = posY or (vsy - 90 * scale)
	dragDX, dragDY = mx - x, my - top
	return true
end

function widget:MouseMove(mx, my)
	if dragging then
		posX = math.max(0, math.min(vsx - 40, mx - dragDX))
		posY = math.max(40, math.min(vsy, my - dragDY))
	end
end

function widget:MouseRelease()
	dragging = false
	return false
end

function widget:MouseWheel(up, value)
	local mx, my = Spring.GetMouseState()
	if not widget:IsAbove(mx, my) then
		return false
	end
	zoom = math.max(0.5, math.min(2.0, zoom * (up and 1.1 or (1 / 1.1))))
	rescale()
	return true
end
