--
-- Custom Options Definition Table format
--
-- A detailed example of how this format works can be found
-- in the spring source under:
-- AI/Skirmish/NullAI/data/AIOptions.lua
--
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local options = {
	{ -- section
		key    = 'performance',
		name   = 'Performance Relevant Settings',
		desc   = 'These settings may be relevant for both CPU usage and AI difficulty.',
		type   = 'section',
	},
	{ -- bool
		key     = 'cheating',
		name    = 'LOS vision',
		desc    = 'Enable global sight',
		type    = 'bool',
		section = 'performance',
		def     = false,
	},
	{ -- bool
		key     = 'comm_merge',
		name    = 'Merge neighbour BARbarIAns',
		desc    = 'Merge spatially close BARbarIAn ally commanders',
		type    = 'bool',
		section = 'performance',
		def     = false,
	},
	{ -- bool
		key     = 'ally_base',
		name    = 'Avoid building in allied bases',
		desc    = 'Do not build units near allied factories',
		type    = 'bool',
		section = 'performance',
		def     = true,
	},
-- 	{ -- number (int->uint)
-- 		key     = 'random_seed',
-- 		name    = 'Random seed',
-- 		desc    = 'Seed for random number generator (int)',
-- 		type    = 'number',
-- 		def     = 1337
-- 	},

	{ -- string
		key     = 'disabledunits',
		name    = 'Disabled units',
		desc    = 'Disable usage of specific units.\nSyntax: armwar+armpw+raveparty\nkey: disabledunits',
		type    = 'string',
		def     = '',
	},
--	{ -- string
--		key     = 'json',
--		name    = 'JSON',
--		desc    = 'Per-AI config.\nkey: json',
--		type    = 'string',
--		def     = '',
--	},

	{ -- bool
		key     = 'game_config',
		name    = 'Load game config',
		desc    = 'Enable loading of game-side config',
		type    = 'bool',
		def     = true,
	},
	-- One profile on purpose. The easy/medium/hard/rush trees were stock BARb
	-- variants carrying none of this AI's work, and maintaining them meant every
	-- change had to be made four more times or silently not exist there.
	{ -- list
		key     = 'profile',
		name    = 'Difficulty profile',
		desc    = 'Difficulty or play-style of AI (see init.as).\nkey: profile',
		type    = 'list',
		def     = 'standard',
		items   = {
			{
				key  = 'standard',
				name = 'Hard | Aggressive',
				desc = 'Difficulty: Hard |Playstyle: Aggressive',
			},
		},
	},
	{ -- section
		key    = 'play',
		name   = 'Play style',
		desc   = 'How this particular bot plays, independent of the others.',
		type   = 'section',
	},
	{ -- number
		key     = 'apex_eco_force',
		name    = 'Economy focus',
		desc    = 'Seat THIS bot as the eco player.
'
		       .. '0 = off (normal play).
'
		       .. '1 = full eco phase, 0.5 = half as long.
'
		       .. 'It grows to that share of the eco target before army and '
		       .. 'defence return; home danger still restores them.',
		type    = 'number',
		section = 'play',
		def     = 0,
		min     = 0,
		max     = 1,
		step    = 0.1,
	},
}

return options
