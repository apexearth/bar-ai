--
-- The options a lobby shows when you click into this bot. Format: the spring
-- source's AI/Skirmish/NullAI/data/AIOptions.lua. Every apex_* key reaches the
-- AI through GetTunable, which reads the value as a number -- a list's item
-- keys are numbers for that reason, and a key that is not one ('auto') leaves
-- the AI's own default.
--------------------------------------------------------------------------------

local options = {
	{ -- section
		key    = 'play',
		name   = 'Strategy and play style',
		desc   = 'How THIS bot plays. Each bot in the lobby has its own settings.',
		type   = 'section',
	},
	{ -- list
		key     = 'apex_plan_force',
		name    = 'Team strategy',
		desc    = 'The way this bot\'s team means to win. "Let the AI choose" is normal play: the strategy net picks and changes it as the game goes. Any other choice holds that strategy all game -- set the same on every bot of the team.',
		type    = 'list',
		section = 'play',
		def     = 'auto',
		items   = {
			{ key = 'auto', name = 'Let the AI choose', desc = 'Normal play: the strategy net decides.' },
			{ key = '0', name = 'Normal', desc = 'Balanced economy and army, no special push.' },
			{ key = '1', name = 'Mass T3', desc = 'Gantries and experimental units, then a team push.' },
			{ key = '2', name = 'Nukes and missiles', desc = 'Nuke silos, tactical and EMP launchers, then a team push.' },
			{ key = '3', name = 'Long-range artillery', desc = 'LRPCs, Ragnarok and Starfall, then a team push.' },
			{ key = '4', name = 'Mass and push', desc = 'Normal production; the army gathers and pushes together.' },
			{ key = '5', name = 'Mass air', desc = 'Air plants early (the AI picks how many), air army, then a team push.' },
			{ key = '6', name = 'Rush', desc = 'Twice the army, early attacks together.' },
			{ key = '7', name = 'Greed', desc = 'Half the army while the enemy is seen sitting passive; the rest into economy.' },
			{ key = '9', name = 'Deep greed', desc = 'A quarter of the army while the enemy is seen passive. Risky.' },
			{ key = '8', name = 'Turtle', desc = 'Heavy defences and anti-air, no push.' },
		},
	},
	{ -- number
		key     = 'apex_plan_explore',
		name    = 'Try strategies (training)',
		desc    = '1 = this bot picks its team\'s strategy at random and plays everything else normally, so the AI learns which strategies work against people. Use it on one bot per team. Ignored when Team strategy is set. 0 = off.',
		type    = 'number',
		section = 'play',
		def     = 0,
		min     = 0,
		max     = 1,
		step    = 1,
	},
	{ -- number
		key     = 'apex_eco_force',
		name    = 'Economy player',
		desc    = '0 = off. Above 0 makes THIS bot the team\'s economy player: it builds economy first, to that share of its economy target, before army and defence. 1 = full economy phase, 0.5 = half as long. A threat to its base brings army and defence back.',
		type    = 'number',
		section = 'play',
		def     = 0,
		min     = 0,
		max     = 1,
		step    = 0.1,
	},
	{ -- number
		key     = 'apex_nn_blend',
		name    = 'Neural net influence',
		desc    = 'How much the trained nets steer decisions. 1 = full (each net still only has the say it has earned). 0 = the hand-written rules alone -- use it if the nets misbehave.',
		type    = 'number',
		section = 'play',
		def     = 1,
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
		key     = 'ally_base',
		name    = 'Keep out of allied bases',
		desc    = 'Do not build near an allied player\'s factories. Leave on.',
		type    = 'bool',
		section = 'advanced',
		def     = true,
	},
	{ -- bool
		key     = 'comm_merge',
		name    = 'Merge nearby allied bots',
		desc    = 'Bots that start next to each other hand their commanders to one bot. Leave off.',
		type    = 'bool',
		section = 'advanced',
		def     = false,
	},
	{ -- string
		key     = 'disabledunits',
		name    = 'Units this bot never builds',
		desc    = 'Unit names joined by +, e.g. armwar+armpw+raveparty. Empty = none.',
		type    = 'string',
		section = 'advanced',
		def     = '',
	},
	{ -- bool
		key     = 'game_config',
		name    = 'Use this AI\'s game-side files',
		desc    = 'Leave on. Off loads the copy shipped with the engine-side install instead.',
		type    = 'bool',
		section = 'advanced',
		def     = true,
	},
	-- One profile on purpose: the easy/medium/hard/rush trees were stock BARb
	-- variants carrying none of this AI's work.
	{ -- list
		key     = 'profile',
		name    = 'Profile',
		desc    = 'There is one: the full AI.',
		type    = 'list',
		section = 'advanced',
		def     = 'standard',
		items   = {
			{ key = 'standard', name = 'Standard', desc = 'The full AI.' },
		},
	},
}

return options
