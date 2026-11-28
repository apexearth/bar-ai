-- Every UnitDef and its weapons, as the game itself has them (after BAR's own post-processing), to defs.json in the
-- write dir. Inert unless the start script sets dev_defs_dump=1:
--   python tools/run_match.py ... --minutes 1 --modoption dev_defs_dump=1
-- his 11-22: "The model needs to know the unit's hp, range, damage, fire rate, movement speed, it needs to understand
-- all the factors". The army net's unit stats come from this file (tools/armynet/unitstats.py). Ported from
-- tools/defs_dump_widget.lua so it runs headless.

function gadget:GetInfo()
	return { name = "BARAI defs dump", desc = "UnitDefs and WeaponDefs to defs.json (dev_defs_dump=1)",
		author = "bar-ai", layer = 0, enabled = true }
end

if gadgetHandler:IsSyncedCode() then
	return
end

local mo = Spring.GetModOptions and Spring.GetModOptions() or {}
if tostring(mo.dev_defs_dump or "0") ~= "1" then
	return
end

local function esc(s)
	return '"' .. tostring(s):gsub('\\', '\\\\'):gsub('"', '\\"') .. '"'
end

local function val(v)
	local t = type(v)
	if t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then return "0" end
		return string.format("%.6g", v)
	elseif t == "boolean" then
		return v and "true" or "false"
	elseif t == "string" then
		return esc(v)
	end
	return "null"
end

local function weapon(w)
	local wd = WeaponDefs[w.weaponDef]
	if not wd then return nil end
	local dmg = {}
	for i = 0, #(Game.armorTypes or {}) do
		local d = 0
		pcall(function() d = wd.damages[i] or 0 end)
		dmg[#dmg + 1] = val(d)
	end
	local only, bad = {}, {}
	for k, on in pairs(w.onlyTargets or {}) do if on then only[#only + 1] = esc(k) end end
	for k, on in pairs(w.badTargets or {}) do if on then bad[#bad + 1] = esc(k) end end
	local f = {
		'"name":' .. esc(wd.name), '"type":' .. esc(wd.type), '"range":' .. val(wd.range),
		'"reload":' .. val(wd.reload), '"salvo":' .. val(wd.salvoSize), '"projectiles":' .. val(wd.projectiles),
		'"aoe":' .. val(wd.damageAreaOfEffect), '"edge":' .. val(wd.edgeEffectiveness),
		'"speed":' .. val(wd.projectilespeed), '"accuracy":' .. val(wd.accuracy), '"spray":' .. val(wd.sprayAngle),
		'"paralyzer":' .. val(wd.paralyzer), '"high":' .. val(wd.highTrajectory), '"beamtime":' .. val(wd.beamtime),
		'"stockpile":' .. val(wd.stockpile), '"water":' .. val(wd.waterWeapon), '"interceptor":' .. val(wd.interceptor),
		'"selfexp":' .. val(wd.selfExplode), '"tracks":' .. val(wd.tracks), '"turret":' .. val(wd.turret),
		'"heightmod":' .. val(wd.heightMod), '"cylinder":' .. val(wd.cylinderTargeting),
		'"damages":[' .. table.concat(dmg, ",") .. ']', '"only":[' .. table.concat(only, ",") .. ']',
		'"bad":[' .. table.concat(bad, ",") .. ']',
	}
	return "{" .. table.concat(f, ",") .. "}"
end

-- headless BAR skips an unsynced gadget whose only call-in is Initialize (gadgets.lua
-- ShouldSkipHeadlessUnsyncedGadget), so the dump runs once from the first GameFrame
local dumped = false
local function dump()
	local path = tostring(mo.dev_defs_out or "defs.json")
	local out = io.open(path, "w")
	if not out then
		Spring.Echo("[BARAI_DEFS] cannot open " .. path)
		return
	end
	local armor = {}
	for name, id in pairs(Game.armorTypes or {}) do
		if type(name) == "string" then armor[#armor + 1] = '"' .. name .. '":' .. tostring(id) end
	end
	out:write('{"armor":{' .. table.concat(armor, ",") .. '},"units":{\n')
	local first = true
	for id, ud in pairs(UnitDefs) do
		local ws = {}
		for _, w in ipairs(ud.weapons or {}) do
			local s = weapon(w)
			if s then ws[#ws + 1] = s end
		end
		local shieldPower = 0
		pcall(function()
			if ud.shieldWeaponDef and WeaponDefs[ud.shieldWeaponDef] then
				shieldPower = WeaponDefs[ud.shieldWeaponDef].shieldPower or 0
			end
		end)
		local f = {
			'"id":' .. id, '"metal":' .. val(ud.metalCost), '"energy":' .. val(ud.energyCost),
			'"health":' .. val(ud.health), '"speed":' .. val(ud.speed), '"turn":' .. val(ud.turnRate),
			'"accel":' .. val(ud.maxAcc), '"buildtime":' .. val(ud.buildTime), '"armor":' .. val(ud.armorType),
			'"fly":' .. val(ud.canFly), '"cloak":' .. val(ud.canCloak), '"stealth":' .. val(ud.stealth),
			'"sonarstealth":' .. val(ud.sonarStealth), '"shield":' .. val(shieldPower), '"sight":' .. val(ud.sightDistance),
			'"radar":' .. val(ud.radarDistance), '"jammer":' .. val(ud.radarDistanceJam), '"mass":' .. val(ud.mass),
			'"fx":' .. val(ud.xsize), '"fz":' .. val(ud.zsize), '"building":' .. val(ud.isBuilding),
			'"builder":' .. val(ud.isBuilder), '"buildspeed":' .. val(ud.buildSpeed), '"selfd":' .. val(ud.selfDCountdown),
			'"autoheal":' .. val(ud.autoHeal), '"idleheal":' .. val(ud.idleAutoHeal),
			'"weapons":[' .. table.concat(ws, ",") .. ']',
		}
		out:write((first and "" or ",\n") .. esc(ud.name) .. ":{" .. table.concat(f, ",") .. "}")
		first = false
	end
	out:write("\n}}\n")
	out:close()
	Spring.Echo("[BARAI_DEFS] wrote " .. path)
end

function gadget:GameFrame()
	if not dumped then
		dumped = true
		dump()
	end
end
