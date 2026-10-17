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
            ("TUNE_RECORD_BITE", "ON prices a unit type by what its DEAD actually "
             "dealt: a type whose units keep dying under their own health in "
             "damage is bought at that fraction, kept per matchup (our type vs "
             "the unit that killed it) and read against what the enemy fields "
             "now -- their Tzars price our Pawns by what Tzars did to Pawns -- as a moving average "
             "across games (fodder and fighters are never judged). OFF keeps the "
             "record but prices by stats alone. `record` on a run shows it"),
            ("TUNE_AOE_VS_BLOB", "ON: a ground unit with splash is worth the "
             "enemy units one shell catches in the ball their army walks in "
             "(a shell hitting 2 more is worth 3 single-target guns of its cost), "
             "and the more of their army is bunched, the more splash we keep "
             "beside it — the Fatboy stops sitting at the bottom of the lab's "
             "list against a blob. OFF prices splash as nothing. "
             "`apex: aoe-stat` shows their biggest group, how bunched it is, "
             "and our splash units' price with and without this"),
            ("TUNE_LAB_NANO", "ON: a construction turret beside a factory is "
             "worth the extra army it lets that factory make, up to the "
             "factory's share of our income: income split over the factories, "
             "less the turrets already beside each one. So one bot factory "
             "takes its first turret as soon as income can feed it, a second "
             "past about 13 metal a second, a third past 26. While we "
             "spend everything (towers included), a turret at the factory still "
             "takes its share of the metal instead of reading as worthless, and "
             "it competes with the towers on price. OFF: turrets are bought "
             "only from spare metal, so a spent economy builds none. "
             "`apex: labnano-stat` each minute (on or off): factories, turrets "
             "per factory, income per factory, what the next turret adds, how "
             "often a factory turret was offered and beat the best tower, and "
             "the defence and build-power shares against their targets"),
            ("TUNE_UNSTICK", "ON: a fighting unit that has an order and has not "
             "moved for 10 seconds (and is not shooting or being shot) is walked "
             "to the nearest open ground it can reach; if it still cannot move, "
             "the building of ours penning it is reclaimed, or blown up once what "
             "it traps has lost more than the building is worth. Builders the "
             "stuck watch frees get the same walk. Nano turrets and converters "
             "stop filling a lab's exit lane and stop closing the gaps between "
             "blocks. OFF: only the slower walled-in watch runs. "
             "`apex: unstick-stat` each minute counts both, on or off"),
            ("TUNE_RUSH_AWARE", "ON: the AI works out how soon their army can "
             "walk to our base. While we save for the next lab tier, the enemy "
             "keeps making army, so on a small map the army we keep at home is "
             "raised to meet what could arrive in that time. T2/T3 labs, the "
             "gantry and big energy builds are worth less until that army "
             "stands. On a big map their walk outlasts the saving and nothing "
             "changes. OFF: the army floor is only the enemy army we have seen. "
             "`apex: rush-stat` each minute shows the walk time, the threat, "
             "the floor before and after, and how hard tech was marked down"),
            ("TUNE_SMALL_PRESSURE", "ON: on a map where their army can walk "
             "to us faster than it could outbuild the army we keep, the AI "
             "plans for a shorter game: economy is valued over a shorter "
             "horizon and the army it keeps grows (up to double). Whether to "
             "leave home is judged on the whole team's army against theirs, "
             "not each player's own group, and the team marches together; "
             "only a player whose own base is being hit stays to defend. The "
             "team attack goes for their outer extractors when taking them "
             "pays, and our outer extractors lean on the army rather than "
             "extra towers. On a big map nothing changes. "
             "`apex: pressure-stat` each minute shows the walk time, the "
             "horizon, the army target before and after, team vs their army, "
             "pushes, players joined and their extractors taken"),
            ("TUNE_MAP_SHARE", "ON: while our team holds fewer of the map's "
             "metal spots than its fair share (our players over all players, "
             "half in an even game), the AI keeps a somewhat bigger army (up "
             "to 1 + the shortfall), groups leave home sooner and are less "
             "easily held back by a stronger enemy army, raids and the team "
             "attack go for their extractors on the ground between the bases, "
             "and a constructor values grabbing a free spot more. A base "
             "under attack still defends. The payback horizon and every other "
             "economy price are unchanged. Once we hold our share nothing "
             "changes. `apex: mapshare-stat` each minute shows our spots, "
             "theirs seen, the share, the gap, the army target before and "
             "after, how often the hold was lifted and contest targets taken"),
            ("TUNE_SMALL_HARD", "ON: on a map where the enemy army can walk "
             "to us (measured along the real path, not the straight line) "
             "sooner than it could outbuild our home army, the AI plans its "
             "army to beat what will be standing there when it arrives: the "
             "army it has seen, their commanders, and what their extractors "
             "pay for during the walk. Fast units are worth more for the "
             "income they can deny, raids and the team attack go for their "
             "extractors (worth their income for the rest of the game when "
             "we can hold the ground), the commander helps the factory when "
             "the army is short and metal is spare, and his trips out and our "
             "raids allow for their unseen commander at home. Extractor and "
             "expansion prices are unchanged. On a big map nothing changes. "
             "`apex: smallhard-stat` each minute shows the path and straight "
             "walk times, the contact weight, their income and strength at "
             "arrival, the army floor before and after, units ordered by "
             "kind, raids and kills on their extractors and the commander's "
             "jobs"),
            ("TUNE_COM_HOME", "ON: on a small map, while the army is short, "
             "the commander's time away from the factory costs the army he "
             "would have built there, so far jobs lose to helping the factory "
             "and helping the factory is worth the army it makes. He no longer "
             "thinks his D-gun kills an enemy commander (it does no damage to "
             "one) or that a single enemy's fire halves during a fight. An "
             "enemy commander wrecking our base counts as an attack on it; he "
             "defends when what stands there outweighs his risk of dying and "
             "runs home rather than sideways. Chasing a target with the D-gun "
             "counts the enemy towers and unseen commanders where it leads. "
             "On a big map almost nothing changes. `apex: comhome-stat` each "
             "minute shows his seconds by job and by how far forward, the "
             "factory help's value against what won, base-attack seconds and "
             "his answer, chases refused and fight/retreat swaps"),
            ("TUNE_EARLY_BALL", "ON (needs TUNE_SMALL_HARD): where their "
             "base is close, a cheap fast unit is worth the enemy metal a "
             "ball of them would destroy before the enemy's new units stop "
             "it, less what the ball loses getting in, so Pawns and Grunts "
             "win the factory over heavier units while their base is weakly "
             "held, fading as their towers and army grow. The army waits at "
             "home until it is that ball, then goes together. Every unit is "
             "also worth the ground it watches per metal (sight and speed) "
             "until our income fills the field. Scouts no longer count as "
             "patrolling our base. An air scout is worth the enemy metal we "
             "cannot see times the share of their unseen ground the next "
             "plane adds, so a few come and a big map stops buying them. "
             "Army against constructors is unchanged. `apex: earlyball-stat` "
             "each minute: the ball (unit, size, survival), the bar against "
             "what is gathered, attacks sent, kills and losses on their half, "
             "units ordered, scouts; `apex: earlyball-ppc` each factor of "
             "each unit's price per factory per minute"),
            ("TUNE_OPEN_RACE", "ON (needs TUNE_SMALL_HARD): each time the "
             "factory's 'make a constructor now' rule fires, it first weighs "
             "that constructor against the factory's best fighter on one "
             "clock: the constructor's income from the extractors it can "
             "reach, after its build and walk, kept only as far as our army "
             "can hold their raiders once they arrive; the fighter's worth in "
             "their extractors and constructors it kills after walking over, "
             "plus the share of our team's income it helps hold. Whichever "
             "pays more by the horizon is made. On a close map with no army "
             "yet, raiders come first; on a big map constructors do. A "
             "factory short of energy no longer stops: each unit is worth "
             "less by how much slower the shortage makes it. The spending "
             "plan counts units as soon as they are ordered. Fighting groups "
             "and escorts stop chasing an enemy that runs faster than they "
             "can close, and escorts stop chasing aircraft they cannot shoot. "
             "Once their army can reach us soon, a constructor is worth the "
             "extractor spots it reaches before their constructors do (their "
             "seen ones, the rest assumed as many as ours), and a fighter "
             "counts as many basic fighters as it really fights like, not "
             "more. The team army picks among their extractors, their "
             "constructors and the spots in that race, each against what "
             "defends it there, and goes as soon as it beats that; raiders "
             "contest them too. "
             "`apex: openrace-stat` for each order in the first 10 minutes "
             "(both values and their parts, the winner), `apex: openrace-sum` "
             "each minute, `apex: spotrace-stat` each minute (open spots, who "
             "reaches them first, constructor against fighter, the army's "
             "target, groups sent, kills, army idle at home), `apex: "
             "chase-stat` each minute (targets faster than "
             "us, seconds and distance spent on them, chases refused)"),
            ("TUNE_ECO_RETURN", "ON: extractors, generators, converters and "
             "energy storage are compared by one number, the metal each "
             "returns per metal spent over the horizon at the energy we "
             "actually have. A converter is worth only the energy no "
             "converter we have or have ordered can already reach (standing "
             "idle converters take any new spare energy first); a generator "
             "is worth only what something would use, and builders short of "
             "metal are not short of energy; every one of them pays for the "
             "energy it costs at what a converter would make of it, and a "
             "late start costs the share of the horizon it loses. The army "
             "extras (the small-map contact weight and its floor, the rush "
             "floor, the map-share nudge and the budget's army row) follow "
             "the threat that actually arrives -- their army at our edge and "
             "their raids on our economy in the last minutes -- or our odds "
             "of killing their army; in a pause we cannot use, economy takes "
             "the spend. `apex: ecoreturn-stat` each minute (on or off): "
             "the best and mean price of each kind, what was handed out and "
             "built, energy income, use, converter use and capacity, the "
             "spare energy and converter room, and the threat, kill odds "
             "and army scale with the targets they set"),
            ("TUNE_EXPAND_FAR", "ON: an extractor spot is worth its income "
             "times the chance we end up holding it: the chance it is still "
             "free when our constructor gets there (their constructors are "
             "assumed as many as ours, walking out from their start; a spot "
             "we have seen their extractor on is worth nothing), times the "
             "chance the constructor survives the walk, read off the enemy "
             "seen along the road against our own strength there. Spots and "
             "roads with enemies nearby are no longer refused outright, only "
             "priced; a constructor sent to a spot keeps walking through a "
             "dangerous road instead of turning back, and the engine sends it "
             "to the spot we chose rather than the nearest one it likes. A "
             "claim whose constructor died or gave up frees the spot at once "
             "instead of hiding it for two minutes. A constructor walking to a "
             "spot gives it up only when the road has become more dangerous "
             "than it was when the job was chosen, and an abandoned claim "
             "elsewhere is picked up instead only when it is the better buy. "
             "`apex: expand-stat` each "
             "minute (on or off): spots ours, an ally's, theirs and open on "
             "our side, the middle and their side, constructors on extractor "
             "jobs, claims sent by zone, refusals by reason, extractors built "
             "and lost, walkers kept and let go, abandoned claims picked up "
             "or passed over, what every constructor was doing (sampled every "
             "5 s) and the jobs handed out. Needs the rebuilt DLL for the road "
             "and spot part"),
            ("TUNE_COM_FIGHT", "ON: every second each of our ground groups "
             "that has an armed enemy within reach (their army, their towers, "
             "their commander, where we saw them) plays the fight out on paper: "
             "who kills whom first, counting splash weapons hitting several of "
             "our clumped units, the commander's healing and the disintegrator "
             "shots it can afford. Units a moving enemy kills in one hit, or "
             "beats head-on (grunts against a Janus), go around it to raid the "
             "nearest enemy extractor or constructor away from it, if they are "
             "faster. A group that wins attacks the nearest armed "
             "enemy first and then carries on with what it was doing; one that "
             "loses walks back to the nearest group, tower or home where all of "
             "it together would win, fights there, and leaves that defended "
             "point alone until something there or in the group changes (no "
             "walking in and out of tower range). A commander walking into "
             "our base pulls every group in the base onto it when together they "
             "win, otherwise they hold at home under the towers. Raids sent deep "
             "steer around towers they would lose to. `apex: comfight-stat` each "
             "minute: groups in reach, attacks, fall-backs, merges, base pulls, "
             "rings set/kept/lifted and walk-backs into a ring, splits, units "
             "sent round, one-hit threats avoided, what those units killed, "
             "the estimate against what those fights cost and killed, commander "
             "kills, how our units were moving when they died (still, retreating, "
             "advancing) and what killed them (commander, tower, splash, other). "
             "The paper is corrected by what really happened: the team keeps "
             "the ratio of metal really lost and killed to what the paper said, "
             "over every fight our groups took. A group stands and fights when "
             "what it would lose beyond what it kills is less than what walking "
             "away gives up (our extractors, buildings and constructors the "
             "enemy can reach, open spots there, the walk out and back); it "
             "changes its mind only once the estimate moves past its own measured "
             "error. Against their biggest army our groups fall back onto one "
             "point and fight it together; attack groups go after their smaller "
             "groups they beat clearly; raid packs go only at a size that wins "
             "where they are sent. `apex: comfight-cal` each minute: the ratios "
             "and errors, fights taken and their predicted vs real cost, "
             "decisions to fight for the ground, flips, their largest group vs "
             "ours, fights against their main army vs isolated groups, hunts, "
             "and raid launches by pack size (old estimate / calibrated); "
             "`apex: comfight-dec` each decision with both sides of the "
             "comparison. The paper's prediction is retaken whenever the group "
             "or the enemy in reach changes by more than its error, and losses "
             "and kills count only while the group is fighting, so the "
             "correction measures the paper's error and not a later wave"),
            ("TUNE_COUNTER_MIX", "ON: each factory prices its fighting units "
             "by how they fare, metal for metal, against the enemy army we "
             "have seen (remembered units fade as they age; before we see any, "
             "an even mix of every faction's basic factory units). Splash "
             "weapons count every one of our bunched units their blast covers, "
             "a unit that dies to one enemy shot does not fight that enemy, "
             "an outranged unit pays for the walk in, and a winner that is "
             "slower cannot catch what it beats. Where a unit outruns an enemy "
             "it cannot fight, it keeps a raiding value from the enemy "
             "economy we know of, less the raiders we already have. The army's "
             "share against constructors is unchanged; only which fighters "
             "are made moves. `apex: countermix-stat` each minute: their mix, "
             "their economy and our raiders, our candidates' values split into "
             "fight and raid, and the units ordered"),
            ("TUNE_SURF_DPS", "ON: a unit's damage against ground targets is "
             "what its ground weapons deal, and its damage against aircraft is "
             "what its anti-air weapons deal. Off, both read the larger of the "
             "two, so the Armada amphibious bot's anti-air missile (it cannot "
             "shoot anything on the ground) counted as ground firepower and the "
             "T2 bot lab rated it its best fighter per metal. Every ground fight "
             "estimate, unit worth, counter pick, commander and raid estimate "
             "and tower price reads the ground figure; anti-air pricing reads "
             "the air figure. `apex: surfdps` once at start: the old and "
             "per-domain figures for the amphibious bots, a pure anti-air bot "
             "and the switch. Needs the rebuilt DLL"),
            ("TUNE_FOCUS_FIRE", "ON: a ground group under enemy fire (an armed "
             "enemy whose range, plus three seconds of walking, covers one of "
             "ours) sets its targets together every second: first the enemy "
             "whose death takes away the most of the damage they deal us for "
             "each second of our fire (towers, the commander's gun and "
             "disintegrator, splash units counted against how tightly we "
             "stand), with just enough of our units to kill it within three "
             "seconds, the rest on the next one; units it would kill in one "
             "hit, or that cannot reach it, take the next one they can; "
             "extractors and other buildings that do not shoot come after "
             "everything armed in reach. Only what each unit shoots changes: "
             "nobody is moved, and a unit out of range of everything keeps "
             "its normal orders until it comes into range. With the fight estimate on, a "
             "group in contact keeps fighting until that estimate pulls it "
             "out. `apex: focus-stat` each minute: fights, kills by kind "
             "(tower, commander, riot, other, economy) and the order they "
             "died in, seconds to the first armed kill, the share of our "
             "units in a fight with something in range, our losses in fights "
             "and outside them, and the cost per tick"),
            ("TUNE_AA_THREAT", "ON: anti-air goes where their air is hurting "
             "us. A place is ground where their bombers or gunships were seen "
             "over our buildings, or killed something of ours. Anti-air there "
             "is worth what that air is costing us times the share of it the "
             "tower newly stops, judged by how much of their aircraft one "
             "metal of our anti-air beats (damage times health per metal, from "
             "the unit stats), so the first tower or bot where the air is "
             "hurting us wins at once and more there fall off as soon as the "
             "anti-air out-trades the air seen. Anti-air bots guard the army "
             "the air is killing, and the lab makes one when that army is "
             "short. The 'no anti-air' emergency only ends when a tower is "
             "finished or has a builder on it. The anti-air budget row is the "
             "air share of their fighting force, or of our losses, divided by "
             "that exchange rate. `apex: aathreat-stat` each minute: their "
             "air, our losses to air, the derived and actual anti-air share, "
             "anti-air ordered static/mobile, air we killed, each place with "
             "its air, losses, anti-air and the seconds from first damage to "
             "first anti-air"),
            ("TUNE_GATHER", "ON: a raid group's members are fixed when it "
             "sets off. New raiders gather at home and form the next group, "
             "which leaves whole only when the fight estimate says it wins at "
             "its target, counting every enemy unit that could get there while "
             "it walks and works; a group out in the field is never topped up "
             "by units walking out alone or in pairs. A group sent home joins "
             "the gathering again. Groups at home never walk out to join a "
             "squad already out, raider pools never leave on their own, and a "
             "raid's path keeps out of the reach of anything that beats it. "
             "`apex: gather-stat` each minute: raiders gathering, groups "
             "launched by size and their estimate margin, launches at targets "
             "with armed enemies in reach (and with one or two units), raiders held back, "
             "units added after launch, how many seconds their nearest army "
             "was from the chosen targets, and our deaths by how many of ours "
             "stood with the unit"),
            ("TUNE_STOCK_ARMY", "ON: every fighting unit -- ground, air and anti-air, not builders or the "
             "commander -- is run by stock BARb's own army code, as an unmodified BARb would: its squads, "
             "targets, regrouping and retreats. Everything we added that orders the army stands down; "
             "what gets built is still ours. `apex: stockarmy-stat` each minute: our fighting units by the "
             "task holding them, any order one of our systems still tried to give one (should be 0), and "
             "how often each stood down"),
            ("TUNE_OUR_AIR", "ON (needs the stock army switch on too): aircraft come back to our own air "
             "control -- the massed bomber strikes, gunship raids, fighter cover and intercepts -- while the "
             "ground army stays with stock BARb. `apex: stockarmy-stat` adds our_air=on and our aircraft by "
             "the task holding them; the stray-order count still covers only the ground army and should stay 0"),
            ("TUNE_SQUADS", "ON (needs the stock army switch on too): our own army layer runs the ground army -- "
             "not scouts, not air yet. Every ground fighter belongs to one squad and only that squad orders it. A "
             "squad gathers near home, answers an enemy at our buildings when it beats it, sets out whole when it "
             "beats what it will meet at a target, keeps together on the way, and turns back whole when a fight "
             "turns against it. `apex: squad` logs every change of a squad's state with the reason; "
             "`apex: squad-stat` each minute: squads by state, units held, launches, fall-backs and how many "
             "came back from them, deaths by state"),
            ("TUNE_JOIN_ARRIVE", "ON: one rule for every unit sent to help "
             "with something already under way. A constructor joining a "
             "tower, a lab or any build, a helper guarding a builder, a rez "
             "bot going to a fallen commander, army given to an ally under "
             "attack, a nano turret flown to a big frame: each counts only "
             "the work it can still do after it gets there, given the hands "
             "already on the job, against what the trip risks. Nothing walks "
             "to work that will be finished before it arrives or that already "
             "has all the hands it can use. One rez bot per fallen commander, "
             "and only if the body will not rot first. Army goes to an ally as "
             "one group that gets there before its fight ends, or not at all. "
             "`apex: joinarrive-stat` each minute, per path: joins weighed, "
             "refused (too late / crew full / not worth it / already taken), "
             "taken, arrivals after the job ended (should be near 0), arrived "
             "in time, and mean seconds worked after arriving"),
            ("TUNE_TEAM_AIR", "ON: the team weighs going all-in on air "
             "against playing normally, every 30 seconds, from what it has "
             "seen: how a ground fight goes with and without the next eight "
             "minutes of army spending, and how much one air raid of the size "
             "we could afford would kill through the anti-air we know of. When "
             "air wins twice running, every bot builds an air factory and makes "
             "bombers and gunships for the team's chosen target (fighters only "
             "if we have seen theirs), gathers them at one point behind our "
             "lines, and all bots launch together once the gathered wing is big "
             "enough to finish the target. Raids that lose more than they kill "
             "count against air at the next weighing. `apex: teamair-stat` each "
             "minute shows both values and their parts, the gathered wing, the "
             "target and what it needs, and each raid's metal sent, killed and lost"),
            ("TUNE_BUDGET_HOLD", "ON: while the army is below its share of "
             "what we spend, the purchases that used to skip the spending "
             "plan pay it like everything else: the factory's 'make a "
             "constructor now' rule fires only part of the time, constructors "
             "and rez bots at the factory are worth less, and builders sent "
             "straight to nano turrets, to defence or to help build defence "
             "are sometimes sent back to the normal choice instead -- each by how far "
             "their own row is over its share against how far the army is "
             "under. When the army is at its share, or the row is not over "
             "its own, nothing changes. `apex: budgethold-stat` each minute "
             "shows every row's actual and target share, how often each of "
             "those paths was held back, and the metal of army finished that "
             "minute"),
            ("TUNE_COVER_WORTH", "buys cheap fast bodies while the army is short "
             "of the ground it has to watch"),
            ("TUNE_RANGE_WORTH", "standing weight on weapon reach when picking "
             "what to build"),
            ("TUNE_MEXUP_BOOST", "what a mex UPGRADE's extra metal stream is "
             "worth over its honest arithmetic -- raise to make advanced cons "
             "upgrade extractors before energy and assist"),
            ("TUNE_T2CON_UNLOCK", "ON prices an advanced constructor by the "
             "extractor upgrades it brings forward -- the waiting upgrades, "
             "their walk and build time, and how many advanced hands already "
             "work them -- instead of by spare build power, so a seat at T2 "
             "with T1 mexes makes the hands to upgrade them. apex: mexup-stat "
             "each minute"),
            ("TUNE_UPGRADE_FIRST", "ON keeps our oldest advanced constructors "
             "(as many as the waiting upgrades are worth) on extractor "
             "upgrades while any T1 mex waits: towers, radar and supers leave "
             "their list. Not while the enemy army is at our base. "
             "apex: mexup-stat 'upfirst held'"),
            ("TUNE_MEXUP_HORIZON", "ON makes a far extractor upgrade lose "
             "only the share of the payback horizon its walk and build take, "
             "so a 1-2 minute walk no longer prices it below a fusion at "
             "home. apex: mexup line shows the cost breakdown"),
            ("TUNE_ECO_HORIZON", "ON prices fusions, generators and "
             "converters the same way: a long build costs its share of the "
             "payback horizon, not its whole gain for every second, so one "
             "slow constructor no longer prices a fusion at zero"),
            ("TUNE_ASSIST_ECO", "ON lets any constructor help the economy "
             "buildings already rising -- fusions, advanced converters, mex "
             "upgrades, the T2 lab, the gantry -- priced by how much sooner "
             "its build power finishes them, so late basic constructors join "
             "those instead of laying towers. apex: assisteco-stat each minute"),
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
                 ("TUNE_ENERGY_GROWTH_ARRIVE", "charges the premium above only on the income that lands BEFORE the plan's target is due, so a reactor stops out-valuing a smaller one purely for being bigger. Off (the default) the premium is flat in size, which is why the Epic Fusion was elected 54 times against the advanced fusion's 3 in his 8v8 while the AI's own ladder had the Epic at 4,832 s and a fusion at 560"),
                 ("TUNE_LATE_BUILD", "charges a building for the output it does "
                  "not make while it is being BUILT, not only while the builder "
                  "walks. Off, a nine-minute Epic Fusion paid almost nothing "
                  "for the wait and outbid fusions that would have been "
                  "producing for eight of those minutes"),
                 ("TUNE_ENERGY_GROWTH_FLAT", "takes the growth premium from how "
                  "much energy the ECONOMY still wants instead of from the "
                  "generator's own size. Off, a reactor bigger than the whole "
                  "economy collects the full premium, which is why one Epic "
                  "Fusion was priced 200x a fusion for 30x the energy"),
                 ("TUNE_CONV_FEED_CAP", "a converter is only worth the energy we "
                  "actually make. Off, a pinned energy bank prices every "
                  "converter at its nameplate and the shortfall is measured "
                  "against each one's OWN capacity, so idle capacity SELECTS the "
                  "biggest converter -- the 9,000-metal Epic at 2,000 e/s of income"),
                 ("TUNE_E_LOOKAHEAD", "prices in energy demand that has not "
                  "arrived yet"),
                 ("TUNE_E_BILL_SHARE", "WHILE E-STALLED, prices a building's ENERGY bill against energy INCOME -- an advanced solar costs 5,000 E to make, which a 100 E/s economy cannot afford and a 400 E/s one barely notices. Off prices the bill by build length instead, which ignores income entirely"),
                 ("TUNE_E_COMMITTED", "counts the energy draw of work already ORDERED into the pull that prices energy, so a generator is worth buying BEFORE the stall rather than after it"),
                 ("TUNE_E_PARALLEL", "lets a STALL open parallel energy sites, not only an overflowing bank -- otherwise a big deficit is answered one small turbine at a time"),
                 ("TUNE_E_FEED_BOUND", "stops the standing fleet asking for the energy of hands the METAL feed cannot run. Off (the default) the ask is the fleet's full nominal speed, which rises with our own build power and holds the 'would anything absorb this?' term at 1.00 even with the bank full. On, it was measured to move the e-stall and change no outcome -- see docs/tunables.md"),
                 ("TUNE_PLANT_INFLIGHT", "discounts a new lab by the labs of other domains already under construction -- stops the bot/vehicle/air rotation leaving three unfinished frames"),
                 ("TUNE_PLANT_COPY", "his 2026-08-27 ruling, on by default: no second plant of a type we already own. 0 lets a copy compete on price, which was measured worse -- -0.67 extractors at minute 4 and THEIRS +0.55 -- so the ruling is exonerated"),
                 ("TUNE_COVER_PUSH_S", "how affordable a mex sentry must be before it may JUMP the auction queue -- seconds of economic power. Lower delays the first turrets further"),
                 ("TUNE_MEX_LOSS_COVER", "share of our extractors the enemy recently killed (kills / standing + kills, fading over the structure-loss memory) at which every extractor's gun jumps the queue. Below it guns are bought only when worth more than the next claim; 0 restores the gun-always rule"),
                 ("TUNE_COM_LAB_EARLY", "before our first T2 lab, while the army is under its target, the commander spends every other minute assisting the lab. 0 turns it off"),
                 ("TUNE_ESCORT_CAP", "escorts on duty at once across all exposed constructors (stock 3)"),
                 ("TUNE_ESCORTS_PER_CON", "guards each exposed constructor is owed before it stops counting as exposed"),
                 ("TUNE_COM_ESCORT","while constructors are owed escorts, the commander assists the nearest lab with a queue for a minute at a time, so the escorts come out sooner. 0 turns it off"),
                 ("TUNE_BASE_FRONT","while the enemy is aggressive, medium and heavy lasers on the open base-edge slots facing them, as many as the enemy army we have seen takes to stop. 0 turns the push off"),
                 ("TUNE_REDECIDE_S","a builder that decided this recently is turned away by the election -- caps a task that keeps dying young. Lower answers a finished build sooner"),
                 ("TUNE_VW_WALK", "weight on the builder's wage over the WALK in every building's price (search scaffolding; 1 is the plain formula)"),
                 ("TUNE_VW_BUILD", "weight on the builder's wage over the BUILD in every building's price (search scaffolding)"),
                 ("TUNE_VW_DISP", "weight on the upgrade stream a build postpones (search scaffolding)"),
                 ("TUNE_VW_LATE", "weight on an income building's own late start -- its yield lost over the walk and build (search scaffolding)"),
                 ("TUNE_VW_FLOW", "weight on the fleet-wide slowdown an unfunded energy drain causes (search scaffolding)"),
                 ("TUNE_VW_ECOST", "weight on a building's energy bill (search scaffolding)"),
                 ("TUNE_VW_FEED_BANK", "share of the metal bank counted toward a build's feed time (search scaffolding)"),
                 ("TUNE_VW_MCS_FROM", "metal-bank fill at which the metal bill starts being forgiven (search scaffolding)"),
                 ("TUNE_VW_MCS_SPAN", "bank fill over which that forgiveness ramps to full (search scaffolding)"),
                 ("TUNE_VW_MCS_DEPTH", "how much of the metal bill a full bank forgives (search scaffolding)"),
                 ("TUNE_BUDGET_LEVER", "whether the category budget's target/actual multiplier actually SCALES wants or is only logged. Measured OFF: 32 games with it on won 3.1% against 48 games off at 12.5%, and his live read agreed -- it moves defence share 0.16 -> 0.23 and does not move economy at all, because economy is the category most often decided with no rival want to price against"),
                 ("TUNE_T2_FUSION_PULL", "while the T2 switch is on and no advanced generator stands, TAKE the fusion instead of drawing it. The switch already names fusions as its purpose but only removes army from the target, and the freed metal went to wind: measured first fusion at minute 16.2 against BARb's 9.7, from a T2 plant we finished FIRST at 8.0"),
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
                 ("TUNE_CONV_AFFORD_S", "seconds of economic power the "
                  "converter burst may commit at once. The bank is the wrong "
                  "bound because we run it near empty on purpose; a converter "
                  "pays back in ~37 s, so 30 s of power is a bill the economy "
                  "carries. Lower it and a wasting grid is answered one "
                  "converter at a time"),
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
                  "question"),
                 ("TUNE_ECO_ONLY", "economy-only benchmark: no army products and no "
                  "defence, AA or superweapon wants, for measuring how fast the "
                  "economy alone scales against an inactive opponent"),
                 ("TUNE_ETA_LOG", "writes the `apex: eta` shadow line while "
                  "the layer is off, so you can read what it WOULD have "
                  "picked without changing anything. Each line is a full "
                  "ladder simulation per ranked want (~15 ms), so it is off "
                  "unless you are reading the comparison"),
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
                 ("TUNE_M_REALIZE", "[toggle] prices a mex by the share of "
                  "its metal we could actually SPEND. Off, a spot keeps full "
                  "value while the bank sits full and spills — which is how "
                  "we came to bin 23.5% of our metal while energy-starved"),
                 ("TUNE_M_WASTE_WORTH", "what a spot is still worth once its "
                  "metal would only overflow. Never 0: demand grows and the "
                  "spot is still ours when it does. Raise it and extraction "
                  "keeps outbidding energy through an overflow"),
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
                 ("TUNE_REZ_REACT_S", "how much of the enemy's own walking "
                  "counts as being in range already — a rez bot backs away "
                  "while the nearest enemy is still this many seconds short "
                  "of firing on it, and refuses work inside that ring"),
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
                 ("TUNE_SITE_BT_PER_WORKER", "the other arm of the same cap, "
                  "sized by BUILD TIME instead of price, taken as a max so it "
                  "only ever adds hands. LOWER it to put more constructors on "
                  "slow builds -- the advanced converter is 35,000 buildtime "
                  "for 380 metal and the price arm gave it 2 hands"),
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
                 ("TUNE_REZ_LIFE", "ON prices a rez bot by the wrecks it "
                  "will eat before it dies, not over a whole 15 minutes: the "
                  "faster the fleet is dying where it works, the shorter that "
                  "life, and a bot that will not eat its own cost is not "
                  "built. apex: rezlife-stat each minute"),
                 ("TUNE_LINE_OBSOLETE", "ON makes a lower plant's fighting "
                  "unit (a T1 hover AA, a T1 fighter) worth only its share of "
                  "what the best unit of the same job from our higher plant "
                  "gives for the same metal, when we can afford that one; the "
                  "rest of its turn goes to the better plant, so it is made "
                  "that much less often. Constructors, rez bots and scouts are "
                  "never judged. apex: lineobs-stat each minute"),
                 ("TUNE_UNIT_UPKEEP", "ON: while the game lags, every unit a "
                  "factory makes pays rent for the space it takes in the "
                  "game, the same for a fighter as for a T3 walker, so cheap "
                  "fighters, rez bots and extra constructors are made less "
                  "often and the metal goes to fewer, bigger units. The rent "
                  "is zero while the game runs at its set speed and grows "
                  "with the lag and with how close the team is to its unit "
                  "limit. apex: upkeep-stat each minute"),
                 ("TUNE_FAC_QUEUE", "keeps each line queued deeper, so it "
                  "idles less and reacts slower"),
                 ("TUNE_LINE_FLOOR", "a factory order must be worth more of "
                  "the line's best option before it is issued"),
                 ("TUNE_PLANT_INCOME_PER", "each production line is credited "
                  "with more income, so more plants are wanted"),
                 ("TUNE_TEAM_LINE", "a plant the TEAM already owns is worth "
                  "less to a second player: the second copy of a line is worth "
                  "half, the third a third, so four allies open bot, vehicle "
                  "and air rather than four bot labs. Not exclusivity -- a "
                  "fourth bot lab is allowed, it just prices below the first "
                  "vehicle plant. 0 makes every player reason alone"),
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
                 ("TUNE_T1_AIR_CON_MIN", "basic air constructors kept once an "
                  "air lab stands (the nano-turret hands), ordered one at a "
                  "time between the lab's other air — higher means more "
                  "turrets go up, at the cost of air units"),
                 ("TUNE_UNIT_AFFORD_S", "seconds of income a unit may cost "
                  "before its bid dies — lower means mass-first harder and "
                  "T3 waits for a richer economy"),
                 ("TUNE_DEF_SETBACK", "how far behind the contested edge a "
                  "front tower is sited — bigger survives building more "
                  "often but covers less forward ground"),
                 ("TUNE_SCOUT_OVER_S", "how often an idle air scout overflies "
                  "the enemy base — lower is fresher intel and more dead "
                  "Peepers; 0 disables the overflight"),
                 ("TUNE_ECO_ROLE", "master switch for the rear-specialist "
                  "role — 0 (current) means every player plays the full "
                  "game; 1 re-arms the eco-specialist experiment"),
                 ("TUNE_ECO_FORCE", "makes this AI play the eco player "
                  "outright, and says how long for: 0 leaves the usual "
                  "rear-most election alone, 1 ecos the whole way to the "
                  "eco target before army and defence come back, 0.5 half "
                  "as far. Unlike the switch above it needs no big team — "
                  "it seats this AI in a 1v1 or a 2v2 as well"),
                 ("TUNE_ECO_LATCH", "ON keeps ONE eco player for the whole "
                  "game: elected at the start, it keeps the role unless it is "
                  "eliminated. OFF re-elects every 10 s by shelter, so a "
                  "neighbour's death can move the role mid-game"),
                 ("TUNE_TEAM_TECH", "ON (team games, 3+ of our players): "
                  "one player goes T2 and hands its T2 constructors to the "
                  "others as their mexes need them; the others hold off their "
                  "own T2 lab while those handouts cover their upgrades, and "
                  "spend on army and economy instead. They still build their "
                  "own lab later. apex: teamtech-stat each minute"),
                 ("TUNE_ECO_SEAT_STRICT", "ON makes the eco player only "
                  "build economy while it grows: no towers, radar, army or "
                  "big guns from its constructors or labs; its labs make "
                  "constructors, and anti-air only while aircraft are "
                  "killing its things. The other players already cover it. "
                  "Sustained enemies at its base still end the growth. "
                  "apex: ecoseat-stat each minute"),
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
                 ("TUNE_RAID_ASK", "ON lets higher-level knowledge ASK for a "
                  "raid: it finds enemy ground nothing is guarding, sizes a "
                  "pack against what does guard it, and pulls units out of "
                  "their current pools to make it happen. OFF leaves only the "
                  "stock pool, which waits for raiders to trickle in and merge "
                  "-- measured, 13 raiders reached that pool in one 16-minute "
                  "game and no raid ever formed"),
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
                 ("TUNE_HOLD_MEX_GROUND", "a unit within its own range of a mex "
                  "spot we hold or could claim stands through the influence and "
                  "incoming-group withdrawals while the odds are not against it "
                  "— the contested middle mexes are held, not handed over. OFF "
                  "restores the withdrawals"),
                 ("TUNE_BIRTH_DEFEND", "ON: a unit that comes out of a lab (or "
                  "is re-tasked) while enemies are attacking where it stands "
                  "defends that spot until they are gone, unless the odds there "
                  "are hopeless; and a defender next to our buildings counts "
                  "their guns and what the lab will finish, and regroups at "
                  "them instead of walking off to a rally point"),
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
                  "faction's own light towers per gun the spot earns. The only "
                  "defence knob that acts before anything has attacked us — "
                  "every other one scales a wave that reads zero at a mex "
                  "nobody has come for yet. 0 restores the observed-threat-only "
                  "behaviour"),
                 ("TUNE_MEX_GUARD_FAR", "how many MORE guns a mex earns at the "
                  "enemy's doorstep than at home (1 at home, 1+this at forward "
                  "fraction 1, linear between). His 09-17 ruling: the further "
                  "from home, the more defence the mex needs"),
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
                 ("TUNE_T1_TOWER_LATE", "his 2026-09-19 rule, on by default: "
                  "once an ADVANCED hand exists, no basic tower at all. 0 is "
                  "the arm that measures it, and it was measured innocent -- "
                  "with the rule off our light towers per 6-min bucket moved "
                  "4.31 -> 4.56 against BARb's 9.31, and mexes lost were "
                  "unchanged. What holds the tower count down is the hands and "
                  "the sites, not this"),
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
                 ("TUNE_DEF_OFF", "1 builds NO turrets at all, ground or AA: "
                  "radar, jammers and units are the whole defence. This is the "
                  "no-turret fighting test from docs/doctrine.md -- override it on a "
                  "launch (tools/test_earlyfight.py does), do not edit the "
                  "default"),
                 ("TUNE_DEF_PRIOR_SHARE", "how much of the symmetric enemy "
                  "guess the defence target assumes before contact"),
                 ("TUNE_SCREEN_GAP", "how far IN FRONT of the squad's longest "
                  "row a short-range row holds, elmos. Short units stop walking "
                  "to their own reach and stand as a shield for the guns "
                  "instead. 0 restores stand-at-your-own-range"),
                 ("TUNE_LINE_TERRAIN", "weigh a production line by how much "
                  "of the map its ARMY can move around in -- 1 on, 0 off. On a "
                  "flat map every line reads the same and this changes nothing; "
                  "on a hilly map the vehicle line is discounted against bots"),
                 ("TUNE_COVER_LEAVES", "a cover pool promotes to ATTACK like "
                  "stock's massing pool once its power bar fills, so home keeps "
                  "only what is still filling. 0 = the pool never leaves"),
                 ("TUNE_COVER_BY_RAID", "post no more metal to base cover than "
                  "our share of the raider metal they have fielded. 0 = the "
                  "coverage need alone decides (at scale it never closed)"),
                 ("TUNE_FLANK_GUARD", "ON stands small groups from the home "
                  "pools at the edge of the economy on each approach no tower "
                  "covers -- one group per flank, sized 1.2x the biggest raid "
                  "seen on our ground, no more groups than their raider metal "
                  "pays for. They fight what reaches their building and walk "
                  "back; they move only when the flanks change. Trap: that "
                  "metal is not in the attack army. apex: flank-stat each minute"),
                 ("TUNE_LINE_QUALITY", "weigh a production line -- its whole "
                  "price, and the tech want -- by its units (median army-per-"
                  "metal) times the ground they can cross, against the best line "
                  "of its class and tier: flat map, vehicles; hills everywhere, "
                  "bots. 1 on, 0 old pricing. apex: line-quality logs the census"),
                 ("TUNE_DEF_DOMINANCE", "refuse a tower that a gun we can "
                  "AFFORD RIGHT NOW beats on both reach and killing power -- a "
                  "defence slot holds one building, so a beaten tower is "
                  "stranded metal, not a cheaper option. 0 restores pure "
                  "value-per-metal ranking"),
                 ("TUNE_DEF_AFFORD_S", "seconds of economic power a defence "
                  "building may cost and still count as affordable. This is the "
                  "guard on the rule above: raise it and bigger guns count as "
                  "reachable sooner, lower it and we settle for what is cheap"),
                 ("TUNE_AIR_ECO_BASE", "the economy needed before the bomber "
                  "raid is worth mounting, in metal/s at no bonus -- the "
                  "handicap multiplies it, so 100 here is 200 m/s in a +100% "
                  "game. Below it bombers price at zero and the metal goes to "
                  "the ground army. RAISE to delay air further"),
                 ("TUNE_ECO_TARGET_BASE", "the economy the REAR SPECIALIST "
                  "builds before it spends anything on war, in metal/s at no "
                  "bonus -- the game's own handicap multiplies it, so 250 here "
                  "is 500 in a +100% game. Below it that player's target names "
                  "no army and no defence at all; above it the role stops "
                  "existing. RAISE for a longer greed phase"),
                 ("TUNE_ECO_TARGET_BASE_8", "the same economy for an "
                  "EIGHT-player team, at no bonus -- 500 here is 1000 m/s "
                  "in a +100% game (his 2026-09-14 ruling: 1k, not 2k; one of eight "
                  "spends the whole early game on economy). While it grows "
                  "the cover, spill and escort floors buy no army for that "
                  "player either; a raid on its home ends the growth"),
                 ("TUNE_ARMY_ECO_S", "seconds of total economic power we may "
                  "hold as ARMY -- the other half of the same split, on the "
                  "same basis as TUNE_DEF_ECO_S above, so the two numbers "
                  "together read as the priority split. RAISE to field more "
                  "army for the same economy"),
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
                 ("TUNE_DEF_REFILL", "ON puts a tower the enemy killed back "
                  "on the same gap: priced by everything behind the hole on "
                  "the way to our base, as if they will come straight back "
                  "through it, fading over a few minutes; skips the in-flight "
                  "cap. A grave still pulls the new gun back; it waits while "
                  "their units stand there and gives up if they stay. "
                  "apex: refill-stat each minute; 'deflag' button on a run"),
                 ("TUNE_DEF_TEAM_OBSOLETE", "ON stops basic constructors "
                  "filling late slots with T1 towers once our advanced "
                  "constructors can build and afford a gun that outreaches and "
                  "outkills it: the T1 tower keeps only its share of that gun's "
                  "kill, so the basic hand goes to economy. The share also "
                  "reaches the refill, the base-front and cover pushes, the "
                  "field crew and the defence role, which used to pick the "
                  "tower without it. apex: advobs-stat and t1tower-path "
                  "each minute"),
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
                 ("TUNE_WALL_CLUSTER", "guns per wall cluster — the wall's "
                  "slots are grouped this many at a time, packed tight "
                  "enough to cover each other, with the space saved taken "
                  "as a gap before the next cluster. Same number of guns "
                  "on the same perimeter, grouped instead of evenly "
                  "spread; 1 restores the even spread"),
                 ("TUNE_WALL_CLUSTER_TIGHT", "how tightly a cluster's guns "
                  "pack, as a fraction of the old spacing — lower is a "
                  "denser knot of fire and a wider hole between knots"),
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
            {"title": "Defence as a crutch (his 10-14)",
             "what": "Five rules that put a tower or a radar ahead of the "
                     "lottery instead of letting it bid. Each switch makes one "
                     "of them a priced offer that energy and army can outbid. "
                     "All off is the old behaviour; A/B each one alone.",
             "reads": "brain/market/ecodef.as, decide.as, crew.as, protect_senseprice.as",
             "knobs": [
                 ("TUNE_RADAR_PRICE", "radar worth only what it shows our ARMY "
                  "and the buildings it newly watches, not a share of "
                  "everything we own. On = fewer radars, built where the army "
                  "is blind; the stat line prints the old and new gain"),
                 ("TUNE_DEFJOIN_PRICE", "a free constructor helps a tower "
                  "being built only when finishing it sooner is worth more "
                  "than its other jobs. On = fewer hands pulled onto towers"),
                 ("TUNE_FIELD_PRICED", "the constructors out at the far "
                  "extractors build a tower or radar only when it beats "
                  "everything else in the lottery. On = the field crew builds "
                  "fewer towers and more of the rest"),
                 ("TUNE_COVER_PRICED", "the light tower on an unguarded "
                  "extractor and the guns on the base's front edge bid in the "
                  "lottery instead of jumping it. On = fewer towers, watch "
                  "extractors lost"),
                 ("TUNE_DEF_DANGER", "how much defence a seat holds follows "
                  "the part of the enemy army we have seen that our own army "
                  "cannot meet. On = a seat our army protects buys only its "
                  "extractor guards; a seat the enemy outweighs buys towers"),
                 ("TUNE_DEF_MEASURED", "towers are valued on how often the "
                  "enemy has actually come near our extractors and base, not "
                  "on the assumption that an unguarded extractor is attacked "
                  "every two minutes. On = an enemy that is not pushing gets "
                  "few towers built against it and the metal goes to economy "
                  "and army; one that pushes raises the demand where it came. "
                  "Read apex: defmeasured-stat"),
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
            {"title": "Shields",
             "what": "Shield domes are bought against bombardment actually "
                     "seen or actually landing -- an enemy LRPC is remembered "
                     "after the sighting and fades if nothing shells us.",
             "reads": "protect_senseprice.as, protect_target.as",
             "knobs": [
                 ("TUNE_SHIELD_COVER_FRAC", "more shield metal per metal of "
                  "enemy bombardment; this is what stops dome-stacking"),
                 ("TUNE_SHIELD_URGENCY", "bombardment is treated as arriving "
                  "more often"),
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
                 ("TUNE_AIR_COVER", "ON sends held fighters with every scout, "
                  "radar plane and bomber that leaves -- enough to match the "
                  "air threat on the route, never none -- and brings them home "
                  "when the mission ends. OFF flies them alone"),
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
            {"title": "Stuck builds",
             "reads": "manager/brain/market/stuck.as",
             "knobs": [
                 ("TUNE_STUCK_SECS", "seconds a builder may hold a build task "
                  "while standing still with no progress before it is "
                  "re-elected; 0 turns the watchdog off"),
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
                 ("TUNE_HZ_APPROACH", "treat an enemy formation WALKING at "
                  "this ground as danger, by how soon it arrives"),
                 ("TUNE_EXPOSE_R", "distance from the core at which a building "
                  "counts as fully exposed"),
                 ("TUNE_ECO_RAID_TAU", "how long a structure loss stays fresh "
                  "in the risk field"),
             ]},
            {"title": "Rising lava",
             "what": "Maps whose lava tide climbs on a schedule (Ghenna "
                     "Rising cycles 250↔415; Special Hotstepper "
                     "escalates all game). The AI reads the gadget's own "
                     "`lavaLevel` and learns the ramp speed and the crest by "
                     "watching them, then prices every site by how long it "
                     "has before the tide arrives — so extractors and "
                     "cheap guns go in the basin and anything with a long "
                     "payback climbs. Inert on every other map. Watch the "
                     "`apex: lava` line.",
             "reads": "manager/lava.as",
             "knobs": [
                 ("TUNE_LAVA", "[toggle] prices and places against the tide. "
                  "Off, the AI builds on a lava map exactly as it did before "
                  "— the only way to A/B this on the same map. The "
                  "sense keeps logging either way"),
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
                 ("TUNE_WALK_FORGONE", "ON prices every builder's walk and "
                  "build time at what its own build power would turn out "
                  "with the metal we can feed, so the commander's minute "
                  "costs about four constructors' and a long walk loses to "
                  "work beside him. OFF is income split over every hand. "
                  "apex: walkforgone-stat each minute"),
                 ("TUNE_NN_BLEND", "the trained value net (Net tab) steers "
                  "more: options it expects to grow the economy and win "
                  "trades get a bigger share of the draw. 0 = it only watches; "
                  "it only plays once the trainer has written its weights"),
                 ("TUNE_NNRAID", "raiders go after the enemy mexes and "
                  "constructors the raid price says are worth the trip, as a "
                  "recorded go/wait decision the raid net refines. 0 = the old "
                  "stock raid pools"),
                 ("TUNE_NN_IMITATE", "constructors lean more toward what BARb "
                  "would build in our situation (learned from ~1,000 games vs "
                  "BARb by tools/imitate.py): its mexes and defences over our "
                  "energy. 0 = off"),
                 ("TUNE_NN_EXPLORE", "more discovery games: with this chance an "
                  "AI makes a share of its decisions (posture, escorts, raids, "
                  "tech timing, defence...) at random all game, so the nets see "
                  "what the alternatives do. 0 = never experiment"),
                 ("TUNE_NN_PLAN_EXPLORE", "of those discovery games, more also "
                  "play one whole team strategy picked at random (mass T3, rush, "
                  "greed, turtle...) until the tech level rises. It changes the "
                  "whole game, so keep it rare. 0 = discovery never forces a "
                  "strategy"),
                 ("TUNE_PLAN_FORCE", "a test switch: every team plays one "
                  "plan all game -- 0 normal, 1 mass T3, 2 missiles and nukes, "
                  "3 long-range artillery, 4 mass and push together, 5 mass air, "
                  "6 rush, 7 greed, 8 turtle, 9 deep greed. -1 = the "
                  "plan net chooses (normal play)"),
                 ("TUNE_PLAN_EXPLORE", "try strategies: this AI picks its team's "
                  "strategy at random, keeps it until its tech level rises, and "
                  "plays everything else normally, so the "
                  "strategy net learns what works. Also a per-bot lobby option. "
                  "0 = off"),
                 ("TUNE_DRAW_SHARP", "the draw follows value more sharply — "
                  "higher is closer to winner-takes-all, which has starved "
                  "every non-leading want before"),
                 ("TUNE_COMMIT_SHARP", "how much sharper the draw gets for an "
                  "expensive commitment"),
                 ("TUNE_ROLE_SHARE", "more of the constructors hold a ROLE -- "
                  "one category (metal, energy, defence, nanos...) they keep "
                  "electing inside until the split of need moves. The rest "
                  "stay open. 0 switches roles off; 1 leaves no open hands"),
                 ("TUNE_ROLE_TAU", "the split of need looks further back, so "
                  "roles change hands more slowly"),
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
            {"title": "What one frame may spend on it",
             "what": "An election is eighteen proposers and an execution, and "
                     "the worst one measured 122.9 ms in a single call — a "
                     "visible hitch at 5x speed. It is now assembled a few "
                     "proposers at a time against a per-frame slice, so this "
                     "is the trade between how big the hitch can get and how "
                     "long a builder waits for its orders.",
             "reads": "brain/market/decide.as",
             "knobs": [
                 ("TUNE_MEMO_TTL", "frames a memoised proposer answer may be "
                  "served for. Seven of the eighteen proposers cache their "
                  "answer per asking-def; what makes an entry valid is the "
                  "stamps of the data it was computed from, and this only "
                  "caps the pricing, which moves every frame and no stamp "
                  "can bound. Higher is fewer recomputes and staler prices — "
                  "watch memo.hit/miss/defer in frametime.py and the want.* "
                  "totalMs against what the AI actually builds"),
                 ("TUNE_ELEC_FRAME_US", "microseconds one sim frame may spend "
                  "assembling builder elections. Lower spreads each election "
                  "over more frames: smaller hitch, slower orders. Raise it "
                  "past the cost of a whole election and nothing is sliced at "
                  "all. Watch `apex: elec-slice` for the worst wait, and "
                  "frametime.py's hk.maketask.builder maxMs for the hitch"),
                 ("TUNE_CREW_ELECT", "1 = constructors of one kind standing "
                  "together share one election: the first runs the market, "
                  "the others join its build or take the next job on its "
                  "list, and one heading somewhere dangerous decides alone. "
                  "Far fewer full elections in a big constructor fleet; the "
                  "trap is that the rest of the crew acts on one hand's "
                  "list, priced from where that hand stood. Watch `apex: "
                  "crew-elect-stat` (run, shared, breakoff, crew)"),
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
                 ("TUNE_COM_MEX_PRICE", "what a metal spot outside the "
                  "commander's leash is worth to him, 0..1 — 0 refuses it "
                  "outright, which is 89% of every extractor proposal in the "
                  "first three minutes"),
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
                 ("TUNE_PERF", "the perf governor's production cuts under lag, "
                  "and the per-section profiler behind frametime.py. Off by "
                  "default — the benchmark harness passes apex_perf=1, so a "
                  "live game does not pay for a profiler nobody reads"),
                 ("TUNE_DECIDE_LOG", "the `apex: decide` and `apex: exec` "
                  "lines. On, because every harness tool reads them; turn it "
                  "off for a live game and the election stops building a "
                  "20-term string and taking the log mutex per builder"),
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
            {"ref": "TUNE_T2CON_UNLOCK", "dir": "up",
             "note": "a seat at T2 makes the advanced constructors its T1 mexes "
                     "are waiting for (his 10-15)"},
            {"ref": "TUNE_UPGRADE_FIRST", "dir": "up",
             "note": "the first advanced constructors upgrade the mexes before "
                     "towers (his 10-03 / 10-15)"},
            {"ref": "TUNE_MEXUP_HORIZON", "dir": "up",
             "note": "a far mex upgrade is no longer priced out by its walk"},
            {"ref": "TUNE_ECO_SEAT_STRICT", "dir": "up",
             "note": "the 8v8 eco player spends its hands and labs on economy "
                     "only until it reaches its target (his 10-15)"},
            {"ref": "TUNE_ASSIST_ECO", "dir": "up",
             "note": "late basic constructors help finish fusions, converters "
                     "and upgrades instead of building towers (his 10-15)"},
            {"ref": "TUNE_WALK_FORGONE", "dir": "up",
             "note": "builders, the commander most, stop walking far for "
                     "work that pays less than staying put (his 10-15)"},
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
            {"ref": "TUNE_ARMY_ECO_S", "dir": "up",
             "note": "START HERE. Seconds of economic power we mean to hold as "
                     "army. This is the whole size of the standing army now — "
                     "it is sized from OUR economy and never from what we can "
                     "see of theirs, so it works the same while blind"},
            {"ref": "TUNE_LINE_OBSOLETE", "dir": "up",
             "note": "late, the army comes from the best plant we own, not "
                     "T1 hover AA and T1 fighters (his 10-15)"},
            {"ref": "TUNE_REZ_LIFE", "dir": "up",
             "note": "rez bots are not rebuilt by the dozen into a fight that "
                     "keeps killing them (his 10-15)"},
        ],
        "watch": "python tools/composition.py — army as a share of our metal. "
                 "Stock BARb runs a 39.9% median (measured over 122 games, "
                 "2026-08-31); the baseline target is 40%, so under ~30% is "
                 "the symptom this fixes.",
    },
    {
        "id": "crutch",
        "ask": "Less on towers and radar, more on units",
        "why": "From minute 15 our constructors spend 21-28% of their time on "
               "defence and 10-13% on radar, because five rules let a tower or "
               "a radar skip the lottery. Each step makes one of them bid at "
               "its price. Try them one at a time.",
        "steps": [
            {"ref": "TUNE_RADAR_PRICE", "dir": "up",
             "note": "radar priced by what our army sees through it"},
            {"ref": "TUNE_FIELD_PRICED", "dir": "up",
             "note": "the far crew's towers and radar bid like everything else"},
            {"ref": "TUNE_COVER_PRICED", "dir": "up",
             "note": "extractor and base-front towers bid instead of jumping the queue"},
            {"ref": "TUNE_DEFJOIN_PRICE", "dir": "up",
             "note": "helping a tower go up is priced, not automatic"},
            {"ref": "TUNE_DEF_DANGER", "dir": "up",
             "note": "a seat's tower budget follows the danger our army cannot meet"},
            {"ref": "TUNE_DEF_MEASURED", "dir": "up",
             "note": "towers valued on how often the enemy has actually come"},
            {"ref": "TUNE_FLANK_GUARD", "dir": "up",
             "note": "units, not towers, on the flanks raiders walk round to "
                     "the wind and converters"},
        ],
        "watch": "python tools/conjobs.py on the batch: defence and sense time "
                 "should fall and energy and army rise; the dashboard's "
                 "'Defence as a crutch' card shows each switch offered and won.",
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
            {"ref": "TUNE_MEX_GUARD_FAR", "dir": "up",
             "note": "more guns on the FAR mexes specifically — the ones raids "
                     "take first"},
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
            {"ref": "TUNE_DEF_REFILL", "dir": "up",
             "note": "a tower knocked out is rebuilt on the same gap first, "
                     "not somewhere still standing (his 10-14)"},
            {"ref": "TUNE_DEF_TEAM_OBSOLETE", "dir": "up",
             "note": "late towers come from the advanced hands, T2 and T3, "
                     "not a ring of T1 ones (his 10-14)"},
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
            {"ref": "TUNE_EVIDENCE_SHRINK", "dir": "up",
             "note": "a unit scoring far outside its class with no exchange "
                     "record of its own is priced back toward that class — the "
                     "scavenger Epics and drone carriers are what it is for "
                     "(0 = off)"},
            {"ref": "TUNE_UNIT_UPKEEP", "dir": "up",
             "note": "the game lags: fewer, bigger units instead of swarms of "
                     "fighters, rez bots and constructors (his 10-15)"},
        ],
        "watch": "python tools/army_mix.py / composition.py, and the "
                 "`apex: worth` lines with apex_worth_diag=1. Per unit: "
                 "apex_worth_<unit> (always) and apex_hold_<unit> (only while "
                 "ground is being lost; Behemoth corjugg defaults to 2).",
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
