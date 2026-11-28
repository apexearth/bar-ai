--
-- The options a lobby shows when you click into this bot. Format: the spring
-- source's AI/Skirmish/NullAI/data/AIOptions.lua. Every apex_* key reaches the
-- AI through GetTunable, which reads the value as a number -- a list's item
-- keys are numbers for that reason. A key not listed here plays the AI's own
-- default (11-18: the team strategy lists, net influence, commander merge,
-- game-side files and the one-item profile list were removed; the C++ falls
-- back to game-side files on, merge off, profile 'standard').
--------------------------------------------------------------------------------

local options = {
	{ -- section
		key    = 'play',
		name   = 'Play style',
		desc   = 'How THIS bot plays. Each bot in the lobby has its own settings. The defaults are the strongest play.',
		type   = 'section',
	},
	{ -- list
		key     = 'apex_persona',
		name    = 'Personalities',
		desc    = 'Off: the standard AI, its strongest play. On: each game the team secretly picks a style (balanced, artillery, snipers and stealth, air, T3, nukes or rush) and leans its building toward it, switching style if it keeps trading badly; each bot also gets its own random tastes. More varied games, measured somewhat weaker. Set it the same on every bot of a team.',
		type    = 'list',
		section = 'play',
		def     = '0',
		items   = {
			{ key = '0', name = 'Off', desc = 'The standard AI (strongest).' },
			{ key = '1', name = 'On', desc = 'A hidden team style and per-bot tastes: more varied, somewhat weaker.' },
		},
	},
	{ -- number
		key     = 'apex_eco_force',
		name    = 'Economy player',
		desc    = '0 = off. Above 0 makes this bot its team\'s economy player: it builds economy first and holds back army and defence until its economy is halfway to its goal, then brings them in. 1 = a full economy phase, 0.5 = half as long. An enemy army near its base brings army and defence back while it stays. Suits a bot at the back of a team. Not measured.',
		type    = 'number',
		section = 'play',
		def     = 0,
		min     = 0,
		max     = 1,
		step    = 0.1,
	},
	{ -- section
		key    = 'advanced',
		name   = 'Advanced',
		desc   = 'Engine-level switches. The defaults are right for normal games.',
		type   = 'section',
	},
	{ -- bool
		key     = 'cheating',
		name    = 'Cheat: see the whole map',
		desc    = 'The bot sees every enemy unit everywhere. Off = fair play (it scouts like a player).',
		type    = 'bool',
		section = 'advanced',
		def     = false,
	},
	{ -- bool
		key     = 'armynet',
		name    = 'Army model (experimental)',
		desc    = 'A trained model commands this bot\'s army; the bot keeps its economy and production. Needs the model server running on the host PC (tools/armynet/serve.py). Off = the normal army.',
		type    = 'bool',
		section = 'advanced',
		def     = true,
	},
	{ -- bool
		key     = 'ally_base',
		name    = 'Keep out of allied bases',
		desc    = 'Do not build near an allied player\'s factories. Leave on.',
		type    = 'bool',
		section = 'advanced',
		def     = true,
	},
	{ -- string
		key     = 'disabledunits',
		name    = 'Units this bot never builds',
		desc    = 'Unit names joined by +, e.g. armwar+armpw+raveparty. Empty = none.',
		type    = 'string',
		section = 'advanced',
		def     = '',
	},
}

return options
