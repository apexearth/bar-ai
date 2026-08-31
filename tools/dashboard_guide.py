"""The guided view of the AI: which knobs actually steer behaviour, grouped by
the question a person arrives with, each with a plain sentence about what
raising it does.

tunables.as ships 300+ defaults. That is the reference, not the control panel.
This file is the control panel: a curated subset, named by TUNE_ symbol so the
dashboard can resolve every one against the real file and drop anything that has
been renamed away rather than showing a value that is not there.

Adding a knob here is cheap and is the right move whenever tuning a behaviour
needed a knob that was hard to find. Keep `up` in the same voice: what the AI
DOES more of, not what the number means.
"""

# Each panel is a chart the dashboard draws itself; the names are what it reads.
PANELS = [
    {
        "id": "spend",
        "title": "Where the metal goes",
        "kind": "spend",
        "what": "The one top-level dial. Every want the Brain prices competes "
                "inside one of these five buckets, and the bucket's share is "
                "read off these curves against current metal income. They are "
                "relative weights, so raising one lowers the rest by itself.",
        "switch": "TUNE_BUDGET",
    },
    {
        "id": "stance",
        "title": "…and how the stance bends it",
        "kind": "stance",
        "what": "The split above is the neutral case. When the base is being "
                "hit or raid pressure is up the AI goes AGGRESSIVE; when the "
                "enemy is visibly quiet it goes PASSIVE (greedy). Each stance "
                "multiplies the buckets.",
        "switch": "TUNE_STANCE",
        "rows": [
            ("Aggressive", {"army": "TUNE_STANCE_AGGRO_ARMY",
                            "defence": "TUNE_STANCE_AGGRO_DEF",
                            "economy": "TUNE_STANCE_AGGRO_ECO"}),
            ("Passive (greed)", {"army": "TUNE_STANCE_GREED_ARMY",
                                 "economy": "TUNE_STANCE_GREED_ECO"}),
        ],
    },
    {
        "id": "army",
        "title": "What the army is made of",
        "kind": "shares",
        "what": "Shares of army metal per line class. Classes are read off the "
                "game's own unit data, not a hand-written unit list: tank = "
                "health per body, reach = weapon range, dps = damage per metal, "
                "mid = nothing clearly dominant.",
        "shares": [("Tank", "TUNE_LINE_TANK", "soaks damage, holds the line"),
                   ("Mid", "TUNE_LINE_MID", "the all-rounders"),
                   ("Reach", "TUNE_LINE_REACH", "outranges what walks in"),
                   ("DPS", "TUNE_LINE_DPS", "damage per metal, dies fast")],
        "extra": [
            ("TUNE_LINE_ALLOC", "OFF, and measured. Picks the line class the team "
             "owes the most metal and draws only within it, instead of nudging "
             "every candidate by apex_line_bite. The allocation half works — reach "
             "share 0.06 -> 0.12, the only thing that has ever moved it. The "
             "stand-down half deadlocks: reach is owed on every election, so T1 "
             "labs yield forever waiting on a plant that never pays. Army metal "
             "544k -> 60k. Do not enable until yielding requires the debt to be "
             "actively served, not merely servable"),
            ("TUNE_LINE_BITE", "favours a class further below its target share; "
             "0 turns the composition target off entirely"),
            ("TUNE_LINE_EDGE", "a unit must stand further above the field to "
             "count as a class at all, so more units land in 'mid'"),
            ("TUNE_LINE_MEDIAN", "judge each axis against the field's median "
             "rather than its mean"),
            ("TUNE_LINE_ADAPT", "how hard the enemy's SEEN static share bends "
             "the reach target up — the more of their metal stands still, the "
             "more of ours outranges it; 0 freezes the base split"),
        ],
    },
    {
        "id": "worth",
        "title": "How a combat unit is priced",
        "kind": "worth",
        "what": "The exponent on each stat when ranking what to build. "
                "0 means the stat is ignored entirely. These are scale-free — "
                "every stat is normalised against the field's own mean — so a "
                "1 and a 2 are 'counts' and 'counts twice as steeply'.",
        "axes": [("Damage", "TUNE_WORTH_DPS", "dps per metal"),
                 ("Burst", "TUNE_WORTH_ALPHA", "damage in one shot"),
                 ("Health", "TUNE_WORTH_HP", "how much it soaks"),
                 ("Range", "TUNE_WORTH_RANGE", "weapon reach"),
                 ("Splash", "TUNE_WORTH_AOE", "area damage"),
                 ("Cost", "TUNE_WORTH_COST", "see below — a law, not a weight")],
        "extra": [
            ("TUNE_WORTH_COST", "1 is the LINEAR law — bodies trade one for one "
             "and cheap chaff wins the draw. 0 is the SQUARE law, where a massed "
             "army fires at once and quality wins superlinearly. 0.5 is the middle"),
            ("TUNE_AIM_MISS", "credits full reach to a weapon that cannot hit a "
             "moving target; lower says half that range only ever lands on buildings"),
            ("TUNE_COVER_WORTH", "buys cheap fast bodies while the army is short "
             "of the ground it has to watch"),
            ("TUNE_RANGE_WORTH", "standing weight on weapon reach when picking "
             "what to build"),
            ("TUNE_MEXUP_BOOST", "what a mex UPGRADE's extra metal stream is "
             "worth over its honest arithmetic -- raise to make advanced cons "
             "upgrade extractors before energy and assist"),
            ("TUNE_DUP_BP_SUBST", "prices a SECOND lab's throughput against "
             "nano turrets on the first, which are ~9x the build power per "
             "metal. On, a duplicate line only wins when no line is short of "
             "hands. 0 is how one 1v1 built 15 T2 bot labs"),
            ("TUNE_REPLANT_DISCOUNT", "what a plant def we RECLAIMED ON "
             "PURPOSE prices at while the window runs -- lower makes a "
             "retirement harder to reverse; 1 lets the market re-buy the lab "
             "it just ate"),
            ("TUNE_REPLANT_WINDOW_S", "how long that retirement memory holds, "
             "in seconds"),
            ("TUNE_FOE_TIER_FADE", "fades a unit -- and a lab's production "
             "value -- as more of the enemy metal we have MET outranks its "
             "tier. Higher abandons the lower tier faster once they field T3; "
             "0 ignores their tier entirely"),
            ("TUNE_OWN_TIER_FADE", "fades lower-tier units once OUR OWN "
             "higher-tier line stands -- late game buys T3 and advanced air, "
             "not more T1. 0 keeps every tier at full price forever"),
            ("TUNE_SPEED_WORTH", "standing weight on speed"),
        ],
    },
    {
        "id": "growth",
        "title": "How big the AI grows",
        "kind": "curves",
        "what": "Constructors wanted, as a smooth curve over metal income. "
                "Nothing here is a count or a cap — set what you want at two "
                "incomes and the curve is solved for you.",
        "extra": [
            ("TUNE_CON_LOG_T1_A", ""), ("TUNE_CON_LOG_T1_B", ""),
            ("TUNE_CON_LOG_T2_A", ""), ("TUNE_CON_LOG_T2_B", ""),
        ],
        "hide_extra": True,
    },
]

# id -> the sentence a newcomer needs, then the knobs.
# knob rows are (TUNE_ symbol, "what raising it does").
GROUPS = [
    {
        "id": "economy",
        "title": "Economy",
        "what": "Metal spots, energy, converters. Everything else is paid for "
                "out of this, so a change here moves every other number.",
        "cards": [
            {"title": "Energy grid",
             "what": "How much generation the AI aims to stand up, relative to "
                     "what it is currently drawing.",
             "reads": "brain/market/want_energy.as",
             "knobs": [
                 ("TUNE_E_PER_METAL", "more energy per metal of income — a "
                  "bigger grid for the same economy"),
                 ("TUNE_E_HEADROOM", "builds further ahead of demand; lower "
                  "runs the grid tighter and stalls sooner"),
                 ("TUNE_ENERGY_GROWTH", "energy is worth more against "
                  "everything else, so generators win more auctions"),
                 ("TUNE_E_LOOKAHEAD", "prices in energy demand that has not "
                  "arrived yet"),
                 ("TUNE_STALL_SOLAR_E", "while e-stalled below this energy income, only build generators that cost NO energy to make -- the basic solar. Raise it to hold that rule further up the economy; 0 lets the auction pick the rung during a stall"),
                 ("TUNE_E_BILL_SHARE", "WHILE E-STALLED, prices a building's ENERGY bill against energy INCOME -- an advanced solar costs 5,000 E to make, which a 100 E/s economy cannot afford and a 400 E/s one barely notices. Off prices the bill by build length instead, which ignores income entirely"),
                 ("TUNE_E_COMMITTED", "counts the energy draw of work already ORDERED into the pull that prices energy, so a generator is worth buying BEFORE the stall rather than after it"),
                 ("TUNE_E_PARALLEL", "lets a STALL open parallel energy sites, not only an overflowing bank -- otherwise a big deficit is answered one small turbine at a time"),
                 ("TUNE_PLANT_INFLIGHT", "discounts a new lab by the labs of other domains already under construction -- stops the bot/vehicle/air rotation leaving three unfinished frames"),
                 ("TUNE_COVER_PUSH_S", "how affordable a mex sentry must be before it may JUMP the auction queue -- seconds of economic power. Lower delays the first turrets further"),
                 ("TUNE_INFERIOR_DISCOUNT", "stops building a generator tier "
                  "once a better one is available"),
             ]},
            {"title": "Metal converters",
             "what": "Turning surplus energy back into metal. These modulate "
                     "the grid — they outrank a new generator while energy is "
                     "actually overflowing.",
             "reads": "brain/market/want_nano.as, price.as",
             "knobs": [
                 ("TUNE_CONV_HORIZON", "converters must pay back sooner, so "
                  "fewer are built"),
                 ("TUNE_E_WASTE_WORTH", "wasted energy hurts more, so a "
                  "converter beats a generator harder during overflow"),
             ]},
            {"title": "The ETA objective (economy-only)",
             "what": "Instead of asking which build returns the most right "
                     "now, the AI names a target — four times the economic "
                     "power it has — and asks which build reaches it soonest. "
                     "Mexes before tech, upgrades after tech, and the switch "
                     "to reactors when the ground runs out all fall out of "
                     "that, with no ordering rule. Economy only so far: it "
                     "cannot price a factory, army or defence.",
             "reads": "brain/market/eta.as (skill: eta-objective)",
             "knobs": [
                 ("TUNE_ETA", "lets the target decide which economy want "
                  "competes — extraction, generation and build power stop "
                  "being three separate lottery tickets and become one "
                  "question. Off still writes the `apex: eta` log line, so "
                  "you can read what it WOULD have picked without changing "
                  "anything"),
             ]},
            {"title": "Metal expansion",
             "what": "Claiming spots and upgrading them. This is what every "
                     "new spending rule displaces, so watch mex counts after "
                     "any change anywhere.",
             "reads": "brain/market/want_plant.as, sites.as",
             "knobs": [
                 ("TUNE_MEX_GROWTH", "a spot is worth more, so expansion "
                  "outbids army and defence more often"),
                 ("TUNE_STREAM_SURVIVAL", "discounts a spot we do not expect "
                  "to hold; 0 values every spot as if it were safe forever"),
                 ("TUNE_STAKE_HORIZON_S", "counts more of a spot's future "
                  "income as worth defending now"),
             ]},
            {"title": "Reclaim",
             "what": "Eating our own obsolete buildings and the map's wrecks.",
             "reads": "brain/market/want_energy.as, kinds.as",
             "knobs": [
                 ("TUNE_RECLAIM_GEN_E", "raises the income floor below which "
                  "generators are never eaten — safer, slower to modernise"),
                 ("TUNE_RECLAIM_PAD", "keeps more headroom before eating a "
                  "generator"),
                 ("TUNE_OBSOLETE_RATIO", "a replacement must be further ahead "
                  "before the old one is torn down"),
             ]},
            {"title": "Rez bots",
             "what": "The bots that eat the battlefield and put units back on "
                     "their feet. A share of them stay with the army as "
                     "medics; the rest work the corpse geometry. They "
                     "resurrect once an advanced reactor stands and metal is "
                     "not the binding constraint, and reclaim otherwise.",
             "reads": "builder/rules_rezzer.as",
             "knobs": [
                 ("TUNE_MEDIC_SHARE", "more of the fleet follows the army "
                  "repairing the wounded instead of working wrecks; 0 "
                  "disables medics"),
                 ("TUNE_MEDIC_R", "how far around the staging anchor a medic "
                  "looks for wounded, and how close it holds station"),
                 ("TUNE_MEDIC_SETBACK", "holds the medic this far behind the "
                  "line, so the wounded step back to it instead of it "
                  "standing in the fight"),
                 ("TUNE_REZ_FLEE_S", "how long one hit keeps a rez bot "
                  "retreating — lower gets it back to work sooner and eats "
                  "more chip damage"),
                 ("TUNE_REZ_SCAN_S", "how often ONE bot looks for its next "
                  "wreck; lower is more responsive, at one feature query per "
                  "bot per period"),
                 ("TUNE_REZ_RICH_M", "a corpse at least this rich is "
                  "resurrected even while the eat-everything doctrine runs — "
                  "lower resurrects more of the battlefield instead of "
                  "eating it"),
             ]},
        ],
    },
    {
        "id": "buildpower",
        "title": "Build power",
        "what": "Constructors, nanos, and who is allowed to work on what. "
                "Constructor time IS the economy — a rule that spends it is "
                "never free, however cheap the thing it builds.",
        "cards": [
            {"title": "How many hands",
             "what": "Lathe capacity is tracked as a fraction of income, not "
                     "as a count. See the growth curves above for the T1/T2 "
                     "constructor targets themselves.",
             "reads": "brain/market/want_assist.as, brain/facqueue.as",
             "knobs": [
                 ("TUNE_BP_HEADROOM", "aims for more lathe capacity per metal "
                  "of income — builds faster, spends more on builders"),
                 ("TUNE_BP_LOOKAHEAD", "sizes build power against the economy "
                  "we are about to have rather than the one we have"),
                 ("TUNE_BP_BACKLOG_S", "counts committed-but-unstarted work as "
                  "demand for more builders"),
                 ("TUNE_MOBILE_BP_EFF", "credits mobile builders with more of "
                  "their nominal worker time (they walk, so it is under 1)"),
                 ("TUNE_GREED_CONS", "a quiet enemy licenses a bigger builder "
                  "fleet"),
             ]},
            {"title": "Crew size at one site",
             "what": "How many builders pile onto a single building, and when "
                     "the surplus is peeled back off.",
             "reads": "brain/market/want_assist.as",
             "knobs": [
                 ("TUNE_SITE_COST_PER_WORKER", "FEWER workers per site — one "
                  "more hand is only allowed per this much of the bill"),
                 ("TUNE_JOIN_MIN_M", "raises the cost a building must reach "
                  "before a second builder joins at all"),
                 ("TUNE_ASSIST_RELEASE", "peels surplus assisters off a site "
                  "back into the auction"),
                 ("TUNE_PEEL_ECO_KEEP", "eco builds keep more hands before "
                  "any are peeled"),
                 ("TUNE_NANO_FED_S", "cons stop assisting sites that standing "
                  "nano turrets will finish anyway and go found new buildings "
                  "instead — raise to free them sooner; 0 turns the gate off"),
                 ("TUNE_REQUEST_DRAIN", "FEWER builds in flight at once — a "
                  "higher number means one request per more income"),
             ]},
        ],
    },
    {
        "id": "production",
        "title": "Factories and tech",
        "what": "What comes out of the plants, and when the AI moves up a "
                "tier. factory.json is NOT in this loop while the Brain drives "
                "the lines — read the `decide … -> produce:` log lines.",
        "cards": [
            {"title": "Factory lines",
             "what": "The Brain aborts the engine's own recruit tasks and "
                     "issues the build orders itself.",
             "reads": "brain/facqueue.as, brain/market/production.as",
             "knobs": [
                 ("TUNE_FAC_QUEUE_BRAIN", "OFF hands every line back to stock "
                  "CircuitAI — the single biggest behaviour switch here"),
                 ("TUNE_REZ_UTIL", "how much real work one rez bot is assumed "
                  "to deliver — the fleet stops growing once bots × work rate "
                  "covers the recoverable wreck stream. RAISE it to field "
                  "FEWER rez bots (each one is credited with more), lower it "
                  "if wrecks rot uncollected. This is the knob that ended "
                  "the 256-rezbot fleet"),
                 ("TUNE_FAC_QUEUE", "keeps each line queued deeper, so it "
                  "idles less and reacts slower"),
                 ("TUNE_LINE_FLOOR", "a factory order must be worth more of "
                  "the line's best option before it is issued"),
                 ("TUNE_PLANT_INCOME_PER", "each production line is credited "
                  "with more income, so more plants are wanted"),
             ]},
            {"title": "Teching up",
             "what": "T2 is an economic decision, not a clock. One player is "
                     "elected to rush it and the rest follow on income.",
             "reads": "manager/techlead.as, factory/phase.as",
             "knobs": [
                 ("TUNE_T2_METAL", "T2 waits for a bigger metal economy"),
                 ("TUNE_T2_ENERGY", "T2 waits for a bigger grid"),
                 ("TUNE_T2_ENERGY_REACTOR", "the lower energy bar that applies "
                  "once a reactor already stands"),
                 ("TUNE_TECH_PIPE", "discounts a tech plant's unlock value "
                  "against the delay before it delivers"),
                 ("TUNE_TECH_SURVIVAL", "discounts tech by the risk borne "
                  "while it is being built; 0 assumes we survive"),
                 ("TUNE_T2_ARMY_HOLD", "hold the aggressive posture while "
                  "still short of the army the advanced plant needs"),
             ]},
            {"title": "Strategic structures",
             "what": "Gantries, nuke silos, anti-nukes, big guns. Bought on "
                     "affordability against total economic power.",
             "reads": "brain/market/want_super.as",
             "knobs": [
                 ("TUNE_SUPER_WANT", "OFF stops the AI ever wanting a gantry, "
                  "silo or big gun"),
                 ("TUNE_SUPER_SHARE", "hands the strategic market a bigger "
                  "slice of total economic power"),
                 ("TUNE_SUPER_AFFORD_S", "a strategic build must be payable "
                  "within more seconds of income — more gets built"),
                 ("TUNE_GANTRY_AFFORD_S", "the gantry's own horizon, over "
                  "TEAM income (one shared line, one team purse) — at 100 "
                  "the bill clears near 100 team metal/s"),
                 ("TUNE_GANTRY_INSURE", "the gantry is worth this share of "
                  "team income as T3 insurance even with no army gap — "
                  "higher means the answer to a Behemoth stands earlier"),
                 ("TUNE_OFFENSE_DEF_FLOOR", "raise toward 1 and the silo/LRPC "
                  "stop caring whether the base is defended; at the default "
                  "0.1 an undefended base all but silences the big gun until "
                  "the defence target fills"),
                 ("TUNE_GANTRY_HOST_INC", "the builder's OWN income at which "
                  "the gantry gain is whole — lower lets a poorer player "
                  "host it earlier (a 50 m/s host at the 100 default gets a "
                  "quarter of the gain)"),
                 ("TUNE_SUPER_PUSH", "an affordable strategic want skips the "
                  "category lottery and goes straight through"),
                 ("TUNE_SUPER_FLIGHT_PER", "one MORE strategic frame may stand "
                  "half-built per this much overflowing metal/s — lower and a "
                  "rich, wasteful economy starts gantries, silos and guns in "
                  "parallel sooner"),
                 ("TUNE_COPY_OVERFLOW_M", "the wealth waiver: overflow above "
                  "this metal/s lifts the plant-copy ban and the one-advanced-"
                  "plant-at-a-time rule — lower and a wasteful economy earns "
                  "its second gantry (or parallel T2 plants) earlier"),
                 ("TUNE_BLAST_AISLE", "gap in elmos between a big generator's "
                  "own clusters — bigger keeps more of the farm outside one "
                  "chain explosion, at the cost of longer walks"),
                 ("TUNE_CON_FEED_HEADROOM", "how many constructors the lines "
                  "may pay for, as a multiple of what income keeps fed — "
                  "lower means army sooner once the hands are hired"),
                 ("TUNE_UNIT_AFFORD_S", "seconds of income a unit may cost "
                  "before its bid dies — lower means mass-first harder and "
                  "T3 waits for a richer economy"),
                 ("TUNE_DEF_SETBACK", "how far behind the contested edge a "
                  "front tower is sited — bigger survives building more "
                  "often but covers less forward ground"),
                 ("TUNE_AID_RESPOND", "metal an ally must be losing at one "
                  "hotspot before our army's staging lane moves to that "
                  "fight — lower helps sooner, 0 never helps"),
                 ("TUNE_SCOUT_OVER_S", "how often an idle air scout overflies "
                  "the enemy base — lower is fresher intel and more dead "
                  "Peepers; 0 disables the overflight"),
                 ("TUNE_ECO_ROLE", "master switch for the rear-specialist "
                  "role — 0 (current) means every player plays the full "
                  "game; 1 re-arms the eco-specialist experiment"),
                 ("TUNE_ANTINUKE_INCOME", "the income at which insurance "
                  "(antinuke, shields) starts being worth buying"),
             ]},
        ],
    },
    {
        "id": "fighting",
        "title": "How the army fights",
        "what": "When to mass, when to commit, when to walk away. Losing "
                "fights is usually the decision BEFORE the fight.",
        "cards": [
            {"title": "Massing and committing",
             "what": "How big a group waits before it is allowed to attack.",
             "reads": "manager/military/*.as",
             "knobs": [
                 ("TUNE_ATTACK_EDGE", "demands a bigger army-vs-army edge "
                  "before attacking at all"),
                 ("TUNE_MASS_PER_ARMY", "waits for a bigger share of our own "
                  "army to gather — fewer, larger attacks"),
                 ("TUNE_MASS_COMMIT_FRAC", "commits further toward the cap "
                  "rather than at the floor"),
                 ("TUNE_MASS_HOLD_RATIO", "stops attacking sooner when the "
                  "enemy army is ahead"),
                 ("TUNE_MASS_HOLD_SECS", "lets a hold run longer before it "
                  "expires and the group goes anyway"),
                 ("TUNE_FODDER_COST", "more units count as fodder and are "
                  "sent immediately without waiting to mass"),
                 ("TUNE_RAIDER_MASSING", "ON stops raiders raiding once our "
                  "advanced lab stands — they join the massing pool and "
                  "fight as line army. OFF is stock BARb's behaviour: raiders "
                  "raid for the whole game, in packs capped by quota.raid.avg, "
                  "hunting enemy constructors. Measured with it ON: ZERO raid "
                  "tasks and zero attack tasks elected across 11 matches"),
                 ("TUNE_SPAM_RAIDERS", "ON sends cheap raiders out as solo "
                  "spotters after T2, one per unscouted metal cluster. That is "
                  "map coverage, not pressure — a scout task cannot group "
                  "with anything. OFF keeps them raiding; scout-role chaff "
                  "spreads out either way"),
                 ("TUNE_ARTY_MASS", "ON puts mobile artillery (Hound, "
                  "Pillager, Catapult…) into the squads as the back row, "
                  "standing at its own weapon range behind the front's "
                  "vision; OFF returns them to solo artillery tasks that "
                  "only shoot buildings and travel alone"),
             ]},
            {"title": "The push and the killing blow",
             "what": "The all-in: everything goes forward at once.",
             "reads": "manager/military/push.as",
             "knobs": [
                 ("TUNE_PUSH_TEAM_RATIO", "needs a bigger team advantage "
                  "before starting the all-in push"),
                 ("TUNE_PUSH_KEEP", "keeps a running push alive on thinner "
                  "odds (hysteresis, keep under the ratio above)"),
                 ("TUNE_PUSH_MIN_ARMY", "no push below this much of our own "
                  "army value"),
                 ("TUNE_KILL_EDGE", "the army multiple that arms the killing "
                  "blow"),
                 ("TUNE_KILL_FLOOR", "enemy army that must be on the books "
                  "before the killing blow is allowed"),
             ]},
            {"title": "Walking away",
             "what": "Withdrawal, recall and leashing. Every one of these is a "
                     "positioning decision, not a retreat toggle.",
             "reads": "manager/military/withdraw.as",
             "knobs": [
                 ("TUNE_WITHDRAW", "OFF leaves units fighting on lost ground"),
                 ("TUNE_WITHDRAW_ODDS", "tolerates worse local odds before "
                  "pulling a unit back"),
                 ("TUNE_WITHDRAW_BEHIND", "pulls back further behind the "
                  "sheltering tower"),
                 ("TUNE_RECALL_HOME", "squads reform on the chokepoint behind "
                  "our front while a hold is on"),
                 ("TUNE_DEFEND_LEASH", "lets a defending unit chase further "
                  "forward before it is recalled"),
                 ("TUNE_HOLD_COMMITTED", "units already under enemy fire are "
                  "never given solo pull-out orders — the force stands or was "
                  "never engaged. OFF restores per-unit withdrawal everywhere, "
                  "the split (half fights, half runs) that loses both halves"),
                 ("TUNE_RETREAT_FLOOR", "units start fleeing at a higher HP "
                  "fraction — the cheapest unit's threshold; each unit adds "
                  "cost/apex_retreat_cost_scale on top. Stock's 0.6 lost 93% "
                  "of combat metal died-retreating; too low and a sliver-HP "
                  "flee dies anyway"),
                 ("TUNE_RETREAT_COST_SCALE", "lower = expensive units flee "
                  "earlier (threshold adds cost divided by this)"),
                 ("TUNE_LOSING_TRADE", "the casualty-scoreboard pull-back: "
                  "lower = leave a fight sooner once our dead outweigh "
                  "theirs nearby; the map sensors both lag, dead units "
                  "don't"),
                 ("TUNE_LOSING_FLOOR", "our combat metal that must die "
                  "nearby before the scoreboard speaks — lower = more "
                  "trigger-happy on the first losses"),
                 ("TUNE_TRADE_WINDOW", "seconds the casualty scoreboard "
                  "remembers — longer = slower to forgive a bad spot"),
             ]},
            {"title": "Where the army stands",
             "what": "The staging anchor: the point the army gathers on and "
                     "falls back through.",
             "reads": "manager/frontline.as",
             "knobs": [
                 ("TUNE_LANE_FORWARD", "stages the army further toward the "
                  "enemy — more map control, more exposure"),
                 ("TUNE_LANE_DEFENSIVE", "how far back the anchor pulls while "
                  "we are trading badly"),
                 ("TUNE_LANE_STICKY", "the front must move further before the "
                  "army re-stages with it"),
                 ("TUNE_LANE_BEHIND_GUNS", "the anchor may never stand forward "
                  "of our own turrets"),
                 ("TUNE_FRONT_SETBACK", "draws the front line further back "
                  "from the influence edge"),
             ]},
        ],
    },
    {
        "id": "defence",
        "title": "Defence",
        "what": "Towers, walls and AA. Static defence is the cheapest way to "
                "hold ground and the easiest thing to overbuild — every tower "
                "is constructor time taken off expansion.",
        "cards": [
            {"title": "How much defence",
             "what": "Sized against what the enemy is expected to throw at a "
                     "position, not against a count.",
             "reads": "brain/market/want_protect.as",
             "knobs": [
                 ("TUNE_MEX_COVER_FLOOR", "MINIMUM PROTECTION PER MEX, in the "
                  "faction's own light towers. The only defence knob that acts "
                  "before anything has attacked us — every other one scales a "
                  "wave that reads zero at a mex nobody has come for yet. "
                  "0 restores the observed-threat-only behaviour"),
                 ("TUNE_COVER_PUSH", "let a tower on a mex the builder is "
                  "STANDING ON skip the category lottery. The draw is "
                  "proportional, so a tower worth twice the mex beside it still "
                  "loses the roll about half the time; this is what closes the "
                  "gap between building a thing and protecting it. It trades "
                  "expansion for cover by construction — watch the mex count"),
                 ("TUNE_DEF_SITE_WALK", "how hard a builder prefers the ground "
                  "it is already standing on. 1 ranks defence sites exactly as "
                  "the price will charge them, so a constructor that just "
                  "finished a mex covers THAT mex; 0 is the old distance-blind "
                  "choice that sent it across the base"),
                 ("TUNE_DEF_TRADE", "credits a turret with stopping more enemy "
                  "metal, so towers win more auctions. Measured 2026-08-26: "
                  "raising it 3 -> 8 moved defence share only 0.071 -> 0.087 "
                  "and cut total metal built by a third — defence is NOT gated "
                  "by this. Find what is before turning it up"),
                 ("TUNE_WALL_EFFICIENT", "ranks towers for a WALL slot by "
                  "cover per metal. A wall slot's demand is the unmet-target "
                  "pull, which is the same number for every tower — so "
                  "without this the only thing separating them is absolute "
                  "power, and a T1 constructor's most powerful option is the "
                  "Agitator. Measured: 35 of them on rear wall slots at "
                  "forward fraction -0.40 to -0.64"),
                 ("TUNE_DEF_OUTRANGE", "how much a turret's kill power is "
                  "lifted by the share of enemy units it OUTRANGES. This is "
                  "the term that separates a Beamer from a Sentry: 480 elmos "
                  "clears a rocket bot's 475, 430 does not, and covered area "
                  "cannot see a 5-elmo step. 1 means a gun that outranges "
                  "everything counts double; 0 removes it"),
                 ("TUNE_DEF_KILL_CAP", "caps what a defence site is worth at "
                  "the metal of attackers the turret can actually destroy in "
                  "the exposure window. Without it, reach pays as AREA — a "
                  "1220-elmo gun is credited with 6.5x a 480-elmo gun's "
                  "economy, as though it defended all of it at once instead "
                  "of shooting one thing at a time. 0 removes the ceiling"),
                 ("TUNE_DEF_DPS_LINEAR", "prices a turret's cover on its "
                  "surface DAMAGE PER SECOND directly, instead of the engine's "
                  "sqrt(dps) threat. The other two terms are already generous "
                  "— reach is paid as AREA (the stake bucket is the gun's own "
                  "range, so 1220 elmos covers 6.5x what 480 does) and hit "
                  "points are paid twice — so rate of fire was the only "
                  "under-weighted one. Measured on the pinned tree: a Beamer "
                  "does 12x a Gauntlet's damage per metal and that read as 3.7x. "
                  "0 restores the old pricing"),
                 ("TUNE_DEF_TTD_H", "TIME TO DEFENCE. The window a turret has "
                  "to be standing in to earn its gain — it keeps only "
                  "H/(H+buildtime) of what it prevents. LOWER buys quicker "
                  "turrets: a 2500-buildtime Guard over a 17400-buildtime "
                  "Agitator, which is what stops defences dying half-built on "
                  "the front line. 0 removes the pressure entirely"),
                 ("TUNE_DEF_ECO_S", "seconds of total economic power we may "
                  "hold in static defence -- the whole size of the standing "
                  "holding. RAISE for a turtle that can carry a Pulsar, LOWER "
                  "to spend the metal on army instead"),
                 ("TUNE_DEF_PRIOR_SHARE", "how much of the symmetric enemy "
                  "guess the defence target assumes before contact"),
                 ("TUNE_GUARD_RATE", "standing army wanted per metal of "
                  "structures owned"),
                 ("TUNE_FRAME_RISK", "charges every building for the chance it "
                  "is killed BEFORE it finishes, at the local hazard rate "
                  "across its own build time. Raise it and the AI stops "
                  "starting slow expensive things on contested ground — a "
                  "1300m Agitator over a 450m light tower, a fusion at the "
                  "front — because a nanoframe that dies bought nothing. "
                  "0 restores the old behaviour, where build duration carried "
                  "no risk at all"),
             ]},
            {"title": "Where defence goes",
             "what": "The front fence versus local guards on mexes.",
             "reads": "manager/military/frontspots.as, want_protect.as",
             "knobs": [
                 ("TUNE_FRONT_LINE", "offer the spaced front posts to the "
                  "defence auction at all"),
                 ("TUNE_UNPROT_DISCOUNT", "how much less a building is "
                  "worth to us while nothing guards it — and so how much a "
                  "turret covering it is worth. This is what makes the AI care "
                  "about defending buildings rather than a radius: 0 goes back "
                  "to pricing defence purely on the loss it prevents"),
                 ("TUNE_DEF_ALPHA_W", "weighs a turret's cover by whether it "
                  "SURVIVES the biggest thing the enemy fields. Near 1 for "
                  "everything while they field raiders; it is what lets a "
                  "9,400-hp Bulwark out-cover twelve 1,670-hp Twin Guards once "
                  "they field something that erases the latter in one pass. "
                  "0 prices every turret on raw damage per metal, which is why "
                  "the T3 guns were never built"),
                 ("TUNE_STANDOFF_COVER", "measure cover on the ring the enemy "
                  "can shoot from, not just whether a turret reaches"),
                 ("TUNE_DEFZONE_DYNAMIC", "the base-defence ring follows the "
                  "built base instead of a fixed radius"),
                 ("TUNE_CHOKE_GATES", "ON offers every doorway of our held "
                  "ground — chokepoints with our side ours and the far side "
                  "not — to the defence auction, so towers land at the "
                  "perimeter gates ahead of the mexes instead of inside the "
                  "base; OFF keeps only the single choke nearest the base "
                  "anchor"),
                 ("TUNE_GATE_DEPTH", "how far past parity a choke gate keeps "
                  "deepening — its cover target as a multiple of the wave "
                  "that arrives together. His concentration ruling: the gate "
                  "overwhelms the push or it is a speed bump"),
                 ("TUNE_WAVE_CONC", "ON prices a defence site against the "
                  "enemy's whole fielded army (capped by what actually "
                  "stands behind the site) instead of a per-site share of "
                  "it. Their mass all takes one approach, and under a small "
                  "assumed wave the auction can only ever buy the cheapest "
                  "turret — this is the switch that lets a Pulsar out-bid "
                  "an LLT carpet once the enemy fields real weight"),
                 ("TUNE_DEF_RING", "ON offers a defence site on every "
                  "approach bearing no standing gun covers yet — flanks and "
                  "the rear included, so a base can close the full circle "
                  "late game and a surround finds no free angle; map edges "
                  "count as walls and are never bought. OFF leaves only "
                  "asset, gate and front candidates, which is what let flank "
                  "attacks walk in on a cold bearing"),
                 ("TUNE_WALL", "ON sites every ground turret on THE WALL: "
                  "slots along the outer edge of our own buildings plus a "
                  "standoff, spaced so adjacent towers' fire overlaps into a "
                  "continuous line that wraps the base, grows outward as we "
                  "expand, and ends where an ally's base takes over the "
                  "bearing. Replaces the asset-cluster, front-line and "
                  "closure-ring candidates that piled towers around the "
                  "start position; gates keep their concentration. OFF "
                  "restores the old candidate set"),
                 ("TUNE_WALL_STANDOFF", "how far outside the outermost "
                  "building the wall stands, as a fraction of light-tower "
                  "range — higher meets the attack further from the "
                  "buildings, lower hugs them"),
                 ("TUNE_WALL_PITCH", "spacing between wall slots as a "
                  "fraction of light-tower range. Lower is a denser, more "
                  "expensive wall; above 2.0 adjacent towers' fire no "
                  "longer overlaps and the wall has holes"),
                 ("TUNE_WALL_REACH", "how far one bearing's buildings can "
                  "drag the wall outward, as a multiple of the typical "
                  "(worth-weighted RMS) radius of everything we own — low "
                  "keeps the wall tight around the base's mass and leaves a "
                  "lone far mex outside it; high lets single outposts pull "
                  "wall segments toward them, where unescorted builders die"),
                 ("TUNE_WALL_REAR", "how much of the wall-building urge a "
                  "slot on the AWAY side of the base keeps — enemy-facing "
                  "slots always get the full urge. Low builds the "
                  "enemy-facing arc first and closes the rear late; 1 "
                  "spreads the wall evenly in all directions"),
                 ("TUNE_WALL_LINE_W", "how hard finishing the FRONT LINE is "
                  "pushed over everything else the defence budget could buy "
                  "— an incomplete line can be walked around, so extension "
                  "outbids deepening until it reaches the map edge or an "
                  "ally's wall. Watch it in the apex: fronttowers lineFill "
                  "number"),
                 ("TUNE_GUARD_FORWARD", "how far in FRONT of the buildings "
                  "an asset-guard tower stands, as a fraction of its own "
                  "reach — between the assets and the enemy approach; 0 "
                  "sites it amid the buildings, where it as often ends up "
                  "behind them"),
                 ("TUNE_T1_DEF_LATE", "how much of its value a T1 tower "
                  "(Gauntlet, LLT — anything a T1 con can build) keeps once "
                  "a standing T2 builder can make defence. Low = the newer "
                  "guns win the auction; 1 prices tiers equally"),
             ]},
            {"title": "Cost of thinking",
             "what": "The protection field is rebuilt on a timer and every "
                     "defence price reads it. Rebuilding it more often tracks "
                     "the base more closely and costs sim time.",
             "reads": "brain/market/protect_field.as",
             "knobs": [
                 ("TUNE_STALL_ANSWER_S", "seconds between asks of \"who "
                  "should drop what they are doing to answer this energy "
                  "stall\". Lower answers a stall sooner and costs a little "
                  "more thinking; the scan stops at the first worker whose top "
                  "want is energy, commander first, so it is cheap either way"),
                 ("TUNE_STALL_ANSWER_MAX_E", "energy income above which the "
                  "AI stops interrupting builders to answer an energy stall "
                  "at all. Past this the economy is big enough that a stall is "
                  "a transient in the pull, not something worth pulling a "
                  "constructor off its task for -- and it is where the scan "
                  "costs most. 0 asks at every income"),
                 ("TUNE_PROTECT_FIELD_S", "seconds between rebuilds of the "
                  "list of what we own and what guards it. Lower is fresher "
                  "and slower; measured 2026-08-27, the defence price cost "
                  "3.6 ms per call before this field existed and 0.6 ms after"),
             ]},
            {"title": "Anti-air",
             "what": "AA is bought against air actually seen, plus a baseline.",
             "reads": "manager/air.as, want_protect.as",
             "knobs": [
                 ("TUNE_AA_MATCH", "more AA metal per metal of enemy air seen"),
                 ("TUNE_AA_URGENCY", "AA is treated as more urgent insurance"),
                 ("TUNE_FLAK_FLOOR_INCOME", "the income from which one flak is "
                  "always held, whatever is seen"),
                 ("TUNE_FLAK_PER", "one further baseline flak per this much "
                  "income"),
             ]},
        ],
    },
    {
        "id": "air",
        "title": "Air",
        "what": "The air line, the elected air lead, and eco assassination.",
        "cards": [
            {"title": "Getting into the air",
             "reads": "manager/air/state.as",
             "knobs": [
                 ("TUNE_INTEL_AIR_INCOME", "the elected air lead waits for "
                  "more income before its first plant"),
                 ("TUNE_AIR_MANDATORY_INCOME", "the income at which an air "
                  "plant becomes mandatory for everyone"),
                 ("TUNE_ADV_AIR_INCOME", "income per additional advanced air "
                  "plant"),
                 ("TUNE_EXTRA_PLANT_ARMY", "the advanced air plant waits for a "
                  "bigger share of army spend first"),
             ]},
            {"title": "What the air does",
             "reads": "manager/air/state.as, station.as",
             "knobs": [
                 ("TUNE_AIR_PAYOFF", "a raid must return more damage per metal "
                  "before it is launched — fewer, better raids"),
                 ("TUNE_AIR_AA_SOAK", "how much AA a wing's health is assumed "
                  "to absorb"),
                 ("TUNE_AIR_AA_SPLIT", "ON sizes the strike against the enemy "
                  "AA census divided by their base count — a raid overflies "
                  "one base, and static AA cannot concentrate. OFF sizes "
                  "against the whole map's AA, which demanded a 125-bomber "
                  "wing and held 50 real bombers at home forever"),
                 ("TUNE_INTERCEPT_MIN_FIGHTERS", "more fighters required "
                  "before an intercept launches"),
                 ("TUNE_AIR_SPREAD", "idle fighters patrol stations instead of "
                  "clumping at the plant"),
                 ("TUNE_AIR_HOME_WAVE", "non-lead players hold aircraft at the "
                  "plant until the wave releases"),
             ]},
        ],
    },
    {
        "id": "commander",
        "title": "Commander",
        "what": "Commander survival predicts the winner more than anything "
                "else in this game, and he is also the best early builder.",
        "cards": [
            {"title": "Caution",
             "reads": "manager/builder/comm.as",
             "knobs": [
                 ("TUNE_COMM_RULES", "OFF hands the commander back to stock "
                  "CircuitAI entirely"),
                 ("TUNE_COMM_FIGHT", "let him fight while he still outclasses "
                  "the field"),
                 ("TUNE_COMM_HEAVY_FRAC", "more fielded enemy heavies before "
                  "he turns cautious"),
                 ("TUNE_COMM_FWD_CAP", "lets a cautious commander work further "
                  "forward"),
                 ("TUNE_COMM_FLEE_HP", "he flees at a higher health — safer, "
                  "less work done"),
             ]},
        ],
    },
    {
        "id": "risk",
        "title": "Risk and intel",
        "what": "What the AI assumes about an enemy it cannot see. These gates "
                "read 'safe' exactly when we are blind, so the priors matter "
                "more than the sightings.",
        "cards": [
            {"title": "What we assume is out there",
             "reads": "brain/market/guards.as, price.as",
             "knobs": [
                 ("TUNE_ENEMY_PRIOR", "assume a bigger enemy army before we "
                  "have seen one"),
                 ("TUNE_SIEGE_PRIOR", "assume the enemy spent more of a "
                  "mirror-image economy on units"),
                 ("TUNE_UNSEEN_PARITY", "pre-T2, an unseen enemy is assumed to "
                  "field at least this multiple of our army"),
                 ("TUNE_MATCH_RATIO", "army fielded per metal of enemy army "
                  "actually seen"),
                 ("TUNE_ALLY_SHARE", "at 1, each ally answers only its income "
                  "share of the enemy team's army; at 0 every ally answers "
                  "all of it, which in a 4v4 had each player chasing 4x its "
                  "own economy"),
                 ("TUNE_GHOST_WEIGHT", "stale sightings count for more against "
                  "fresh ones"),
             ]},
            {"title": "Where danger is",
             "reads": "brain/market/guards.as, world.as",
             "knobs": [
                 ("TUNE_THREAT_GRADIENT", "a spatial prior: 0 at our start "
                  "box, 1 at theirs. 0 disables it"),
                 ("TUNE_RISK_FLOOR", "pressure a never-attacked asset still "
                  "carries, so cold starts are not treated as free"),
                 ("TUNE_EXPOSE_R", "distance from the core at which a building "
                  "counts as fully exposed"),
                 ("TUNE_ECO_RAID_TAU", "how long a structure loss stays fresh "
                  "in the risk field"),
             ]},
            {"title": "Scouting",
             "reads": "manager/brain/market/want_tech.as",
             "knobs": [
                 ("TUNE_SCOUT_BLIND_MULT", "scout more while the stance reads "
                  "UNKNOWN"),
                 ("TUNE_SQUAD_M", "army value that deserves its own mobile "
                  "radar and jammer"),
                 ("TUNE_INTEL_RATE", "share of a squad's value per minute "
                  "spent on its own sensors"),
                 ("TUNE_TARGFAC_WANT", "pinpointers wanted"),
                              ("TUNE_RADAR_OVERLAP", "how much of a standing radar's "
                  "reach blocks a NEW mast — lower = more overlapping "
                  "radars, so one radar dying no longer opens a dark zone "
                  "mid-fight; the threat map only counts what radar sees"),
]},
        ],
    },
    {
        "id": "auction",
        "title": "The auction itself",
        "what": "Every build in this AI is a priced Want, and one arbiter "
                "ranks them. These knobs change HOW it ranks, which moves "
                "everything at once — change one at a time and measure.",
        "cards": [
            {"title": "Picking a winner",
             "reads": "brain/market/decide.as",
             "knobs": [
                 ("TUNE_BUDGET", "OFF stops the category budget scaling wants "
                  "by target-vs-actual share"),
                 ("TUNE_DRAW_SHARP", "the draw follows value more sharply — "
                  "higher is closer to winner-takes-all, which has starved "
                  "every non-leading want before"),
                 ("TUNE_COMMIT_SHARP", "how much sharper the draw gets for an "
                  "expensive commitment"),
                 ("TUNE_BUDGET_LIVE", "price the spend curves against live "
                  "income instead of a smoothed read"),
             ]},
            {"title": "Pricing time",
             "what": "Cost includes time. A build that delivers nothing for "
                     "most of the horizon is discounted against small steps "
                     "that deliver now.",
             "reads": "brain/market/price.as",
             "knobs": [
                 ("TUNE_PAYBACK_H", "a longer horizon — big slow builds look "
                  "better against small fast ones"),
                 ("TUNE_LOCKUP", "penalises tying capital up in an unfinished "
                  "frame; 0 disables"),
                 ("TUNE_SPACE_RENT", "rewards building on ground our turrets "
                  "already cover — denser bases"),
             ]},
        ],
    },
    {
        "id": "layout",
        "title": "Base layout",
        "what": "Where buildings land. Sprawl costs walking time on every "
                "build after it, and walls the base in.",
        "cards": [
            {"title": "Packing",
             "reads": "manager/baseplan.as, brain/market/sites.as",
             "knobs": [
                 ("TUNE_FARM_ROW_W", "a wider energy farm row — wider rows "
                  "read as a line, narrower ones stack into a block"),
                 ("TUNE_FARM_ROWS", "how far rearward the farm scan walks "
                  "before giving up"),
                 ("TUNE_CLUSTER_N", "how many of one building stand together "
                  "before a fresh cluster starts"),
                 ("TUNE_FUS_BACK", "founds the first fusion deeper behind the "
                  "base anchor"),
                 ("TUNE_FARM_BACK", "plans the eco farm further behind the "
                  "base anchor"),
                 ("TUNE_SLOT_TRIES", "lattice slots tried before a placement "
                  "gives up"),
                 ("TUNE_ROOM_WORTH", "what the ground under an obsolete "
                  "building is worth once the base is full — raise it to "
                  "reclaim old wind, solar and converters to make room"),
                 ("TUNE_MEX_TRIES", "how many metal spots a builder offers to "
                  "the engine before giving up on expanding this tick"),
                 ("TUNE_NANO_SITE_SHARE", "how much of the metal nothing is "
                  "spending one factory or big build may claim as nano demand "
                  "— raise it for more turrets around labs and gantries"),
                 ("TUNE_RECLAIM_REZ_BIAS", "how much more a reclaim is worth "
                  "to a rezbot than to a constructor that could be claiming "
                  "ground — raise it to keep cons expanding"),
                 ("TUNE_AISLE_GROW", "a growing cluster must keep the walking "
                  "street to its neighbours instead of filling it in — fewer "
                  "units sealed into pockets, at the cost of more sprawl"),
             ]},
        ],
    },
    {
        "id": "diag",
        "title": "Diagnostics",
        "what": "Nothing here changes how the AI plays. Map overlays are "
                "visible to allies and spectators, so leave them off online.",
        "cards": [
            {"title": "Map overlays and logging",
             "reads": "tunables.as",
             "knobs": [
                 ("TUNE_DRAW_FRONT", "draw the computed front line on the map"),
                 ("TUNE_DRAW_DEFZONE", "draw the defence zone rings"),
                 ("TUNE_DRAW_LANE", "draw the army's staging anchor"),
                 ("TUNE_DRAW_HEAL", "ping the heal post"),
                 ("TUNE_WORTH_DIAG", "1 prints the pricing exponents once; "
                  "2 also dumps the whole ranked field"),
                 ("TUNE_CATALOG_DUMP", "dump every available unit def at init"),
                 ("TUNE_PERF", "the perf governor's production cuts under lag"),
             ]},
        ],
    },
]


# ---------------------------------------------------------------- goals
# People do not arrive wanting to change apex_mex_growth. They arrive wanting a
# bigger economy. Each goal is one intent, the order to try things in, and how
# to tell whether it worked.
#
# A step's `ref` is either a TUNE_ symbol or "spend:<ROW>", which points at the
# metal-split panel rather than duplicating its editor. `dir` is up/down/either.
GOALS = [
    {
        "id": "eco",
        "ask": "I want a bigger economy",
        "why": "Two different things are called this. The metal split decides "
               "how much of every 100 metal is even offered to economy builds; "
               "the knobs under it decide how hard an individual mex or "
               "generator competes once it is. Move the split first — it is the "
               "blunt instrument and its effect is visible in one game.",
        "steps": [
            {"ref": "spend:SPEND_ECONOMY", "dir": "up",
             "note": "the share of spend that reaches mexes, energy and tech"},
            {"ref": "TUNE_MEX_GROWTH", "dir": "up",
             "note": "makes a metal spot worth more against army and towers"},
            {"ref": "TUNE_STANCE_GREED_ECO", "dir": "up",
             "note": "spend harder on economy specifically while the enemy is quiet"},
            {"ref": "TUNE_PAYBACK_H", "dir": "up",
             "note": "a longer payback horizon favours big compounding builds "
                     "(fusion, moho) over small immediate ones"},
        ],
        "watch": "python tools/composition.py <tournament> — mex count, mex "
                 "upgrades and metal produced. If mex upgrades fall while metal "
                 "rises, something else ate the constructors.",
    },
    {
        "id": "army",
        "ask": "I want a bigger army",
        "why": "Army loses to economy and towers by design in the early "
               "brackets. Raise its share of the split before touching what "
               "units get chosen — a better mix of a small army is still a "
               "small army.",
        "steps": [
            {"ref": "spend:SPEND_ARMY", "dir": "up",
             "note": "the share of spend that becomes combat units"},
            {"ref": "TUNE_STANCE_AGGRO_ARMY", "dir": "up",
             "note": "how hard the army share rises when we are under pressure"},
            {"ref": "TUNE_MATCH_RATIO", "dir": "up",
             "note": "field more army per metal of enemy army actually seen"},
            {"ref": "TUNE_ENEMY_PRIOR", "dir": "up",
             "note": "assume a bigger enemy army before we have seen one — "
                     "this is what drives army production while blind"},
        ],
        "watch": "python tools/composition.py — army as a share of our metal. "
                 "Stock BARb runs 22–34%; under 15% is the symptom this fixes.",
    },
    {
        "id": "mexdef",
        "ask": "I want my metal spots defended",
        "why": "There are two separate reasons a mex ends up naked. Before "
               "anything has attacked it, the defence auction priced it against "
               "a wave of zero and skipped it entirely — apex_mex_cover_floor "
               "is the answer to that one and nothing else here is. After "
               "contact, it is a question of what the ground is worth against "
               "the front fence, which is what the rest of these move.",
        "steps": [
            {"ref": "TUNE_LEAK_SCREEN_M", "dir": "up",
             "note": "for EARLY deaths — how long every mex keeps its full "
                     "cover floor before the fielded army is trusted to catch "
                     "leaks instead. Raise it if early mexes still die to "
                     "single scouts while the army is tiny; this is the fix "
                     "for the capped-then-abandoned mex dying to one tick"},
            {"ref": "TUNE_MEX_COVER_FLOOR", "dir": "up",
             "note": "START HERE. A minimum number of light towers' worth of "
                     "cover at every standing mex, whatever we have seen. The "
                     "other knobs below all scale the threat that HAS arrived, "
                     "which is zero at a mex nobody has attacked yet — so they "
                     "do nothing about eco that is undefended from the start"},
            {"ref": "TUNE_COVER_PUSH", "dir": "up",
             "note": "the constructor that just finished a mex covers THAT mex "
                     "instead of re-entering the lottery. Costs expansion by "
                     "construction — the tower it now builds is a mex it does "
                     "not claim, so check the mex count when you change it"},
            {"ref": "TUNE_DEF_SITE_WALK", "dir": "up",
             "note": "makes a builder cover what it is standing next to rather "
                     "than walk to the best site on the map — this is what "
                     "turns 'it built a mex and wandered off' into 'it built a "
                     "mex and then a tower on it'"},
            {"ref": "spend:SPEND_DEFENCE", "dir": "up",
             "note": "the share of spend that becomes ground turrets"},
            {"ref": "TUNE_STREAM_SURVIVAL", "dir": "up",
             "note": "a spot we expect to lose is worth less, which is what "
                     "makes covering it pay"},
            {"ref": "TUNE_SPACE_RENT", "dir": "up",
             "note": "rewards building on ground our turrets already cover"},
            {"ref": "TUNE_DEF_ECO_S", "dir": "up",
             "note": "lets the standing defence holding grow -- it is a share "
                     "of economic power, so this is how much turtle the "
                     "economy buys"},
            {"ref": "TUNE_DEF_TRADE", "dir": "up",
             "note": "credits a turret with stopping more enemy metal"},
            {"ref": "TUNE_UNPROT_DISCOUNT", "dir": "up",
             "note": "makes every unguarded building worth measurably less "
                     "until something covers it, so the auction chases the "
                     "buildings we actually own rather than a perimeter"},
        ],
        "watch": "python tools/deaths.py <run> — where our buildings died. If "
                 "losses move from mexes to the front line, it worked.",
    },
    {
        "id": "fights",
        "ask": "I keep losing fights",
        "why": "Almost always the decision BEFORE the fight: attacking at bad "
               "odds, or standing on ground we cannot hold. Try the odds gates "
               "before the unit-pricing knobs.",
        "steps": [
            {"ref": "TUNE_ATTACK_EDGE", "dir": "up",
             "note": "demand a bigger army advantage before attacking at all"},
            {"ref": "TUNE_MASS_PER_ARMY", "dir": "up",
             "note": "gather a larger group first — fewer, heavier attacks"},
            {"ref": "TUNE_WITHDRAW_ODDS", "dir": "down",
             "note": "pull a unit back sooner when the local odds are bad"},
            {"ref": "TUNE_MASS_HOLD_RATIO", "dir": "down",
             "note": "stop attacking sooner once the enemy army is ahead"},
            {"ref": "TUNE_LANE_FORWARD", "dir": "down",
             "note": "stage the army further back, so a losing fight is fought "
                     "closer to our own guns"},
            {"ref": "TUNE_ARTY_MASS", "dir": "up",
             "note": "long-range units (snipers, Hounds, artillery) fight from "
                     "the squads' back row on the front rows' vision instead of "
                     "walking up blind on their own"},
        ],
        "watch": "python tools/fight1v1.py <run-dir> — army trade efficiency in "
                 "metal. Read a single game deeply; win rate will not tell you.",
    },
    {
        "id": "aggro",
        "ask": "I want the AI to attack more",
        "why": "The AI holds when it does not believe it is ahead. Lower the "
               "bars it is measuring itself against, and it commits earlier.",
        "steps": [
            {"ref": "TUNE_ATTACK_EDGE", "dir": "down",
             "note": "attack on a thinner army advantage"},
            {"ref": "TUNE_MASS_PER_ARMY", "dir": "down",
             "note": "commit smaller groups instead of waiting to mass"},
            {"ref": "TUNE_PUSH_TEAM_RATIO", "dir": "down",
             "note": "start the all-in team push on a smaller team advantage"},
            {"ref": "TUNE_KILL_EDGE", "dir": "down",
             "note": "arm the killing blow earlier"},
            {"ref": "TUNE_STANCE_PRESSURE", "dir": "down",
             "note": "turn AGGRESSIVE on less provocation"},
        ],
        "watch": "python tools/fight1v1.py — kills and losses both go up. If "
                 "losses go up and kills do not, the odds gates were right.",
    },
    {
        "id": "tech",
        "ask": "I want T2 sooner (or later)",
        "why": "T2 is gated on economy, never on a clock. One player is elected "
               "to rush it; everyone else follows on their own income. Judge it "
               "on the RUSHER's first-T2 time, not the team average.",
        "steps": [
            {"ref": "TUNE_T2_METAL", "dir": "either",
             "note": "metal income required before committing to T2 — lower is "
                     "sooner"},
            {"ref": "TUNE_T2_ENERGY", "dir": "either",
             "note": "energy income required before T2"},
            {"ref": "TUNE_TECH_PIPE", "dir": "up",
             "note": "discounts the delay before a tech plant delivers, so tech "
                     "outbids immediate spending"},
            {"ref": "TUNE_TECH_SURVIVAL", "dir": "down",
             "note": "stop discounting tech by the risk borne while building it"},
        ],
        "watch": "min(techStart) per side, not the median across all players — "
                 "followers tech late by design.",
    },
    {
        "id": "build",
        "ask": "I want things built faster",
        "why": "Build power is a closed loop with income: more lathes finish "
               "things sooner but are themselves metal not spent on the thing. "
               "The curve is the main dial; the crew knobs decide whether those "
               "hands pile onto one site or spread out.",
        "steps": [
            {"ref": "spend:SPEND_BUILDPOWER", "dir": "up",
             "note": "the share of spend that becomes constructors and nanos"},
            {"ref": "TUNE_CON_LOG_T1_A", "dir": "up",
             "note": "use the T1 constructor curve editor above rather than this "
                     "coefficient directly"},
            {"ref": "TUNE_BP_HEADROOM", "dir": "up",
             "note": "aim for more lathe capacity per metal of income"},
            {"ref": "TUNE_SITE_COST_PER_WORKER", "dir": "down",
             "note": "MORE workers allowed on one site — a lower number is more "
                     "hands"},
            {"ref": "TUNE_REQUEST_DRAIN", "dir": "down",
             "note": "MORE builds in flight at once"},
        ],
        "watch": "constructor count and metal produced together. Constructors up "
                 "with metal flat means the extra hands had nothing to do.",
    },
    {
        "id": "energy",
        "ask": "I am wasting energy / stalling on energy",
        "why": "Two opposite problems with the same two knobs. Waste means the "
               "grid outran demand and nothing is converting it; stalling means "
               "it did not outrun demand enough.",
        "steps": [
            {"ref": "TUNE_E_HEADROOM", "dir": "either",
             "note": "how far ahead of demand the grid is built — raise to stop "
                     "stalling, lower to stop wasting"},
            {"ref": "TUNE_E_WASTE_WORTH", "dir": "up",
             "note": "makes wasted energy hurt, so a converter beats another "
                     "generator while overflowing"},
            {"ref": "TUNE_CONV_HORIZON", "dir": "up",
             "note": "converters must pay back sooner, so fewer are built"},
            {"ref": "TUNE_E_PER_METAL", "dir": "either",
             "note": "the size of grid the AI aims at per metal of income"},
        ],
        "watch": "the Economy chart on any run detail page — energy waste and "
                 "stall bands.",
    },
    {
        "id": "units",
        "ask": "The AI builds the wrong units",
        "why": "factory.json decides almost nothing while the Brain drives the "
               "lines. Composition comes from the class target and the pricing "
               "exponents — read the `apex: decide … -> produce:` log lines "
               "before touching any config table.",
        "steps": [
            {"ref": "TUNE_LINE_TANK", "dir": "either",
             "note": "shares of army metal per class — see the composition panel "
                     "above"},
            {"ref": "TUNE_LINE_BITE", "dir": "up",
             "note": "enforce the class target harder"},
            {"ref": "TUNE_WORTH_RANGE", "dir": "up",
             "note": "reach starts counting in what a unit is worth (it is 0 by "
                     "default, i.e. ignored)"},
            {"ref": "TUNE_WORTH_HP", "dir": "up",
             "note": "favour units that soak damage"},
            {"ref": "TUNE_WORTH_COST", "dir": "down",
             "note": "toward the SQUARE law: quality wins over cheap mass"},
        ],
        "watch": "python tools/army_mix.py / composition.py, and the "
                 "`apex: worth` lines with apex_worth_diag=1.",
    },
    {
        "id": "air",
        "ask": "I want more (or less) air",
        "why": "One player is elected the air lead and builds a plant early; "
               "everyone else waits for a mandatory income bar.",
        "steps": [
            {"ref": "TUNE_INTEL_AIR_INCOME", "dir": "either",
             "note": "income at which the air lead builds its first plant — "
                     "lower is earlier"},
            {"ref": "TUNE_AIR_MANDATORY_INCOME", "dir": "either",
             "note": "income at which everyone else must have air"},
            {"ref": "TUNE_AIR_PAYOFF", "dir": "down",
             "note": "raid on thinner expected returns — more raids, worse ones"},
            {"ref": "TUNE_AA_MATCH", "dir": "up",
             "note": "answer enemy air with more AA of our own"},
        ],
        "watch": "the Units chart on a run detail page — air counts over time.",
    },
    {
        "id": "super",
        "ask": "I want gantries, nukes and big guns",
        "why": "Strategic structures are bought on affordability against total "
               "economic power, not on a tech flag. At benchmark income (~40 "
               "metal/s for a whole team) they are genuinely unaffordable; in a "
               "bonused online game at 250+ they are cheap. Check the income "
               "before deciding this is broken.",
        "steps": [
            {"ref": "TUNE_SUPER_WANT", "dir": "up",
             "note": "master switch — off means never"},
            {"ref": "TUNE_SUPER_AFFORD_S", "dir": "up",
             "note": "allow a build payable within more seconds of income"},
            {"ref": "TUNE_SUPER_SHARE", "dir": "up",
             "note": "hand the strategic market a bigger slice of economic power"},
            {"ref": "TUNE_SUPER_PUSH", "dir": "up",
             "note": "an affordable strategic want skips the category lottery"},
        ],
        "watch": "python tools/composition.py — metal in T3 and in superweapons.",
    },
    {
        "id": "base",
        "ask": "The base is sprawling / walling itself in",
        "why": "Sprawl costs walking time on every build after it, and a base "
               "with no room left cannot put down an advanced plant.",
        "steps": [
            {"ref": "TUNE_SPACE_RENT", "dir": "up",
             "note": "rewards dense building inside the perimeter"},
            {"ref": "TUNE_FARM_ROW_W", "dir": "down",
             "note": "narrower energy rows stack into a block instead of a line"},
            {"ref": "TUNE_CLUSTER_N", "dir": "down",
             "note": "start a fresh cluster sooner instead of one long row"},
            {"ref": "TUNE_FARM_BACK", "dir": "up",
             "note": "plan the energy farm further behind the base"},
        ],
        "watch": "watch a game. Layout is the one thing a replay reads better "
                 "than any tool.",
    },
    {
        "id": "comm",
        "ask": "My commander keeps dying",
        "why": "Commander survival predicts the winner more reliably than "
               "anything else in this game — and he is also the best early "
               "builder, so every point of caution costs opening tempo.",
        "steps": [
            {"ref": "TUNE_COMM_FLEE_HP", "dir": "up",
             "note": "flee at a higher health"},
            {"ref": "TUNE_COMM_FWD_CAP", "dir": "down",
             "note": "abandon work that sits further forward"},
            {"ref": "TUNE_COMM_HEAVY_FRAC", "dir": "down",
             "note": "turn cautious on less fielded enemy heavy mass"},
            {"ref": "TUNE_COMM_FIGHT", "dir": "down",
             "note": "stop letting him fight even while he outclasses the field"},
        ],
        "watch": "python tools/commander_trace.py <run>.",
    },
]

def build(sections):
    """Resolve every curated name against the parsed tunables.

    Returns the guide with each knob carrying its live value and file position,
    plus `missing`: curated names that no longer exist. A renamed knob drops out
    of the view rather than showing a value it does not have.
    """
    idx = {}
    for si, s in enumerate(sections):
        for i, e in enumerate(s["entries"]):
            idx[e["name"]] = dict(e, si=si, i=i, section=s["title"])
    missing = []

    def one(name, up=""):
        e = idx.get(name)
        if e is None:
            missing.append(name)
            return None
        return dict(e, up=up)

    panels = []
    for p in PANELS:
        p = dict(p)
        if p.get("switch"):
            p["switch"] = one(p["switch"])
        for key in ("shares", "axes"):
            if key in p:
                p[key] = [{"label": lbl, "knob": one(n), "note": note}
                          for lbl, n, note in p[key]
                          if idx.get(n)]
        if "rows" in p:
            p["rows"] = [{"label": lbl,
                          "cells": {k: one(v) for k, v in cells.items()
                                    if idx.get(v)}}
                         for lbl, cells in p["rows"]]
        if "extra" in p:
            p["extra"] = [x for x in (one(n, up) for n, up in p["extra"]) if x]
        panels.append(p)

    groups = []
    for g in GROUPS:
        g = dict(g)
        cards = []
        for c in g["cards"]:
            c = dict(c)
            c["knobs"] = [x for x in (one(n, up) for n, up in c["knobs"]) if x]
            if c["knobs"]:
                cards.append(c)
        g["cards"] = cards
        if cards:
            groups.append(g)

    goals = []
    for g in GOALS:
        g = dict(g)
        steps = []
        for st in g["steps"]:
            ref = st["ref"]
            if ref.startswith("spend:"):
                steps.append(dict(st, spend=ref.split(":", 1)[1]))
                continue
            e = one(ref)
            if e:
                steps.append(dict(st, knob=e))
        g["steps"] = steps
        if steps:
            goals.append(g)

    curated = {n for g in GROUPS for c in g["cards"] for n, _ in c["knobs"]}
    curated |= {st["ref"] for g in GOALS for st in g["steps"]
                if not st["ref"].startswith("spend:")}
    curated |= {n for p in PANELS for n, _ in p.get("extra", [])}
    curated |= {n for p in PANELS for k in ("shares", "axes")
                for _, n, _ in p.get(k, [])}
    curated |= {p["switch"] for p in PANELS if p.get("switch")}
    return {"panels": panels, "groups": groups, "goals": goals,
            "missing": sorted(set(missing)),
            "curated": sorted(curated),
            "total": len(idx)}
