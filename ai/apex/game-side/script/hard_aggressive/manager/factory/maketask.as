namespace Factory {

IUnitTask@ AiMakeTask(CCircuitUnit@ unit)
{
	// Diagnostic for the "factory goes idle with a full bank" reports:
	// distinguishes this hook still being called and declining every branch
	// from it not being called at all. See CHANGES.md 2026-08-06.
	if (ai.frame >= gNextFactoryDiag) {
		gNextFactoryDiag = ai.frame + 30 * SECOND;
		AiLog(T() + "apex: factory-diag " + unit.circuitDef.GetName()
			+ " mInc=" + formatFloat(aiEconomyMgr.metal.income, "", 0, 1)
			+ " mCur=" + formatFloat(aiEconomyMgr.metal.current, "", 0, 0)
			+ " mStor=" + formatFloat(aiEconomyMgr.metal.storage, "", 0, 0)
			+ " isMetalFull=" + (aiEconomyMgr.isMetalFull ? "1" : "0")
			+ " hasTask=" + ((unit.task !is null) ? "1" : "0"));
	}

	// Nano turrets register with the FACTORY manager (CFactoryManager keeps
	// assistants alongside factories), so they arrive here -- but every branch
	// below is written about a factory choosing what to RECRUIT, and none can
	// produce a valid task for one. Several end in `return null`, and for an
	// assistant that means no task at all: CFactoryManager::DefaultMakeTask is
	// the only thing that routes it to CreateAssistTask. The eco lead's block
	// is the worst case -- an unconditional `return null` for anything that is
	// not an air plant or a constructor-capable factory -- which left every
	// turret that player owned permanently idle. apexearth, watching an 8v8
	// live: "blue's turrets are not doing anything at all"; blue was team 0,
	// the eco lead. Hand assistants straight to DefaultMakeTask.
	CCircuitDef@ nano = Builder::NanoDef();
	if ((nano !is null) && (unit.circuitDef.id == nano.id))
		return aiFactoryMgr.DefaultMakeTask(unit);

	// Safe to sit first: this answers only for the advanced air plant, so the
	// ground line's branches below are untouched.
	IUnitTask@ air = Air::MakeFactoryTask(unit);
	if (air !is null)
		return air;

	// Rez bots from the bot lab, before anything else that lab would make --
	// but only once there is something to reclaim or resurrect. apexearth,
	// watching a Comet Catcher 4v4 live: "we build rez bots before we build
	// anything else. Resurrection bots are certainly useful, but at t zero,
	// it's not important. It isn't really important until you have stuff to
	// reclaim or to resurrect." At game start nothing has died on either
	// side, so this floor was competing HIGH-priority for the bot lab's very
	// first slots against the opening mex/army push for a benefit that does
	// not exist yet. Gated on the same wreck search EnqueueWreckReclaim
	// already uses (WRECK_SEARCH/WRECK_MIN in builder.as) rather than a
	// clock: it self-corrects the moment the first skirmish or scout death
	// actually produces something worth reclaiming, instead of guessing a
	// fixed early-game delay.
	//
	// Placed high (once armed) for the same reason the fighter floor is: it
	// is a floor, not a strategy, and the branches below it -- the catch-up
	// push, the constructor line -- would otherwise take every slot the lab
	// has.
	if (HaveT1BotLab() && (ai.frame >= gNextRez)) {
		CCircuitDef@ lab = T1BotLab();
		CCircuitDef@ rez = RezBotDef();
		if ((lab !is null) && (rez !is null) && (unit.circuitDef.id == lab.id)
			&& rez.IsAvailable(ai.frame))
		{
			// Replaced the binary "is there a wreck at all" armed-check, then
			// a scaled-but-still-blind-query version. Root cause found: found
			// via SSkirmishAICallbackImpl::getFeaturesIn -- the non-cheat path
			// is `GetCallBack(id)->GetFeatures(...)`, which is LOS-gated, not
			// a plain spatial query. There is no unit standing at home or at
			// an enemy-centroid midpoint, so those queries return empty no
			// matter the radius -- confirmed live: even a 50000-elmo sanity
			// radius from home returned wreckValueHuge=0 in a game with
			// mKillReal in the thousands. This matches the project's other
			// LOS/vision-gated-callback surprises.
			//
			// Fix: stop querying from a point with no vision. Every mobile
			// builder already scans WRECK_RICH_R around itself for the
			// "rich corpse pile" check every ~3s (builder.as); that scan DOES
			// have vision, because a unit is standing right there. It now
			// records what it sees via Builder::NoteWreckSeen, and this reads
			// the sighting back instead of taking its own blind sample.
			// apexearth: "if theres any reclaim we've seen on the map...
			// start making some... a rezbot costs like what, 130 metal?...
			// so for every 500 wrecked metal seen make 1 rezbot???" REZ_FLOOR
			// still caps the ceiling so a battlefield's worth of corpses
			// cannot balloon this past a sane standing count.
			const float wreckValue = Builder::WreckSeenValue();
			const int wantByReclaim = int(wreckValue / REZ_METAL_PER_BOT);
			const int want = (wantByReclaim < REZ_FLOOR) ? wantByReclaim : REZ_FLOOR;
			if (ai.frame >= gNextRezDiag) {
				gNextRezDiag = ai.frame + 15 * SECOND;
				AiLog(T() + "apex: rez-diag lab=" + (lab !is null ? lab.GetName() : "null")
					+ " rez=" + (rez !is null ? rez.GetName() : "null")
					+ " rezCount=" + (rez !is null ? rez.count : -1)
					+ " wreckSeen=" + formatFloat(wreckValue, "", 0, 0)
					+ " want=" + want);
			}
			if (rez.count < want) {
				IUnitTask@ rec = aiFactoryMgr.Enqueue(TaskS::Recruit(
						Task::RecruitType::BUILDPOWER, Task::Priority::HIGH,
						rez, unit.GetPos(ai.frame), 0.f));
				if (rec !is null) {
					gNextRez = ai.frame + REZ_SPACING;
					return rec;
				}
			}
		}
	}

	// A FULL BANK BUYS BUILD POWER, whatever faction we are.
	//
	// apexearth: "it could be the sort of thing where you see that you're full of
	// metal, and so you have greater odds to make a butler because of the excess
	// build power. would be same for any faction in that logic."
	//
	// This replaces a hand-tuned ratio bump for armfark alone, which would have
	// been an Armada-only fix to a problem all three factions have -- exactly the
	// faction-parity trap CLAUDE.md records. Being metal-full is the condition
	// that makes the trade obviously right: 210 metal for 140 build power turns a
	// bank we are visibly failing to spend into the thing that spends it, and the
	// standing limit is already 200, so the cap was never what stopped us.
	//
	// Gated on the bank rather than a count, so it self-corrects: the moment the
	// extra build power drains the bank, this stops asking and the ordinary
	// ratios take the slot back.
	if (aiEconomyMgr.isMetalFull && (ai.frame >= gNextAssistBot)) {
		// Ask THIS factory for its support-role unit and only take it if that is
		// the assist bot. Enqueueing a def the factory cannot build is a silent
		// no-op -- 33 dropped requests and zero errors, per CLAUDE.md -- so the
		// factory's own build options have to be the authority, not a name list.
		CCircuitDef@ bot = Assist::OurBotDef();
		CCircuitDef@ sup = aiFactoryMgr.GetRoleDef(unit.circuitDef, Unit::Role::SUPPORT.type);
		if ((bot !is null) && (sup !is null) && (sup.id == bot.id)
			&& bot.IsAvailable(ai.frame))
		{
			IUnitTask@ rec = aiFactoryMgr.Enqueue(TaskS::Recruit(
					Task::RecruitType::BUILDPOWER, Task::Priority::NORMAL,
					bot, unit.GetPos(ai.frame), 0.f));
			if (rec !is null) {
				gNextAssistBot = ai.frame + ASSIST_BOT_SPACING;
				AiLog(T() + "apex: bank-buys-buildpower " + bot.GetName()
					+ " standing=" + bot.count
					+ " mCur=" + formatFloat(aiEconomyMgr.metal.current, "", 0, 0)
					+ "/" + formatFloat(aiEconomyMgr.metal.storage, "", 0, 0));
				return rec;
			}
		}
	}

	// Radar planes in the late game, to find what is left.
	//
	// apexearth: "when we're clearly winning we should make T2 radar planes and
	// find the last com so we know where to send our armies." A surviving
	// commander rebuilds, and a won game that runs another fifteen minutes is
	// how that happens.
	//
	// Recruited directly rather than left to the factory ratios: armawac and
	// corawac appear ONLY in the advanced air plant's list (0.05/0.0), and that
	// plant is exactly the one that does not get built -- every sample of a
	// hosted 11v13 read plants=1,0. Legion's legwhisper is not in behaviour.json
	// at all, so it has no role and no ratio anywhere. Naming the def sidesteps
	// all three problems and covers every faction.
	if (IsAirFactory(unit.circuitDef) && LateGame() && (ai.frame >= gNextScout)) {
		CCircuitDef@ eye = RadarPlaneDef();
		if ((eye !is null) && eye.IsAvailable(ai.frame) && (eye.count < LATE_SCOUTS)) {
			IUnitTask@ rec = aiFactoryMgr.Enqueue(TaskS::Recruit(
					Task::RecruitType::FIREPOWER, Task::Priority::NORMAL,
					eye, unit.GetPos(ai.frame), 0.f));
			if (rec !is null) {
				gNextScout = ai.frame + LATE_SCOUT_SPACING;
				return rec;
			}
		}
	}

	// A standing fighter screen in the late game, from ANY air plant we own.
	//
	// Above every other branch, including the eco lead's constructor line: this
	// is a floor of eight aircraft, not a strategy, and the whole point is that
	// it is never the thing that gets skipped. Air::MakeFactoryTask keeps
	// priority over it because the assassin strike is timed and this is not.
	//
	// GetRoleDef(AA) returns whatever THIS plant can build -- the T1 plant's
	// fighter, or Hawk/Vamp/Venator from the advanced one -- so it never asks for
	// an aircraft the factory cannot make.
	if (IsAirFactory(unit.circuitDef) && LateGame() && (ai.frame >= gNextFighter)) {
		CCircuitDef@ fig = aiFactoryMgr.GetRoleDef(unit.circuitDef, Unit::Role::AA.type);
		if ((fig !is null) && (fig.count < LATE_FIGHTERS)) {
			IUnitTask@ rec = aiFactoryMgr.Enqueue(TaskS::Recruit(
					Task::RecruitType::FIREPOWER, Task::Priority::HIGH,
					fig, unit.GetPos(ai.frame), 0.f));
			if (rec !is null) {
				gNextFighter = ai.frame + LATE_FIG_SPACING;
				return rec;
			}
		}
	}

	// aiMilitaryMgr.quota.attack only caps how many units get SENT to attack; it
	// does not stop the factory building them. Measured: the rusher's standing
	// army grew 240 -> 3400 metal while its bank sat at 1 metal, so every sling
	// its allies sent was converted straight into T1 units instead of into the
	// plant. Idle the line outright once the rush window is open, until the
	// advanced plant exists.
	// Do NOT simply idle here. Measured on Comet Catcher: the lead sat with
	// rushReady since 5.0 min and its bank climbing to 2261 unspent metal, and
	// still placed no plant until 13.9 min. The blocker is ENERGY, not metal --
	// EconomyManager checks (engyFactor < energyPower) and returns before it ever
	// consults IsSwitchAllowed, and unlike the metal check that branch is not
	// bypassed by isSwitchTime. So banked metal is simply wasted metal here.
	//
	// Turn it into build power instead: more constructors means solars and
	// converters go up faster, which is the thing the gate is actually waiting
	// on. Those constructors are also exactly what we need afterwards to upgrade
	// mexes and to hand to allies.
	// CAPPED. This had no limit at all: it recruited a constructor on every
	// factory decision from RushReady until the advanced plant existed, which on
	// an 8v8 is the entire rush window. Observed live -- the player going for T2
	// sitting on 15-20 T1 constructors. That is thousands of metal in build power
	// that cannot be spent, buying nothing, at exactly the moment the team has
	// pooled everything behind this player.
	//
	// A handful is enough to finish a plant quickly; past that each one is pure
	// waste. GetWorkerCount() is the engine's own count of our builders, so this
	// counts what we actually hold rather than what we have ever ordered.
	if (MayPursueT2() && !gHaveT2 && RushReady() && !IsSmallTeam()
		&& RushWindowOpen())
	{
		// Cap AND spacing: the cap alone cannot hold, because GetWorkerCount()
		// only sees finished builders (see RUSH_CON_SPACING above).
		if ((int(aiBuilderMgr.GetWorkerCount()) - Builder::RezCount() < int(RUSH_CON_CAP))
			&& (ai.frame >= gNextConOrder))
		{
			CCircuitDef@ con = aiFactoryMgr.GetRoleDef(unit.circuitDef, Unit::Role::BUILDER.type);
			if (con !is null) {
				IUnitTask@ rec = aiFactoryMgr.Enqueue(TaskS::Recruit(
						Task::RecruitType::BUILDPOWER, Task::Priority::HIGH,
						con, unit.GetPos(ai.frame), 0.f));
				if (rec !is null) {
					gNextConOrder = ai.frame + RUSH_CON_SPACING;
					return rec;
				}
			}
		}
		return null;   // never fall through to army production during the rush
	}

	// The tech lead buys roughly four or five minutes of T2 before the enemy
	// catches up, and spending that on one advanced tank is close to wasting it.
	// Spent on constructors it compounds instead: ours upgrades our own mexes,
	// and every one handed to an ally lets them upgrade theirs -- T2 mexes are
	// four times the metal, across the whole team, for the rest of the game.
	// So build nothing but build power until every teammate has one.
	// Both overrides are for BIG teams only. On a four-player team the rusher
	// producing no army at all is a quarter of the team's army missing -- the
	// same arithmetic that rules out an air player on a 4v4. Measured across 5
	// maps: standing army 17.8k against stock's 25.4k and real K/D 0.70 against
	// 1.24, while the tech lead itself was up 8 minutes. A tech lead that cannot
	// hold the ground it techs on does not convert. Small teams keep stock
	// production and lean on quota.attack = RUSH_SKIP_T1_SMALL to stay eco-first.
	// Small teams were excluded after enabling this at NOW priority lost 3-13 with
	// t2Mex falling 3.2 -> 1.8. That test conflated two separate things: sharing
	// constructors at all, versus MONOPOLISING the factory line to do it. NOW
	// means the lead builds nothing else, which a four-player team cannot afford.
	// Observed live with sharing off: "we went t2 but didn't share any cons" and
	// then all four built their own advanced plants late -- the expensive outcome
	// that sharing exists to prevent. So share everywhere, but only pre-empt the
	// line on a big team.
	// Two reasons to build an advanced constructor, and the second was missing.
	// The lead builds them to SHARE, which is the design. But anyone who reaches
	// T2 and holds no advanced con needs one for themselves -- otherwise a
	// follower that techs while the designated lead does not ends up with a T2
	// plant and nothing to upgrade mexes with. Observed in an 8v8: a player
	// finished its advanced lab at 10:01 and immediately built Banishers, mobile
	// radars and a Tiger, while the team upgraded ZERO mexes in 45 minutes.
	// Instrumented because four mex upgrades across eight players (stock: 96) and
	// zero gifts means this branch is barely firing, and guessing which of five
	// conditions fails has already wasted a run. Log every input, once per 30s.
	if (ai.frame >= gNextConLog) {
		gNextConLog = ai.frame + 30 * SECOND;
		CCircuitDef@ probe = aiFactoryMgr.GetRoleDef(unit.circuitDef, Unit::Role::BUILDER.type);
		AiLog(T() + "conbranch fac=" + unit.circuitDef.GetName()
			+ " haveT2=" + (gHaveT2 ? "1" : "0")
			+ " lead=" + (IsTechLead() ? "1" : "0")
			+ " owes=" + (Builder::OwesAdvCons() ? "1" : "0")
			+ " haveCon=" + (Builder::gHaveAdvCon ? "1" : "0")
			+ " roleDef=" + ((probe is null) ? "NULL" : probe.GetName()));
	}
	// Behind on the field, with T2 and a mex upgraded: pour income into the cheap
	// mainstay rather than anything else. apexearth, watching a game lost from a
	// winning tech position: "if we just built T1 labs and spammed out a lot of
	// those Thug units, that would be enough to turn the tide, and it would be
	// way cheaper". GetRoleDef(ASSAULT) returns whatever THIS factory can make --
	// Thug from a bot lab, Brute from a vehicle plant -- so it never asks for a
	// unit the factory cannot build.
	//
	// Spaced, for the same reason RUSH_CON_SPACING exists: Enqueue does not dedup
	// and the cap it would otherwise respect only counts finished units.
	// Was T1 factories ONLY, on the reasoning that the advanced plant returns
	// Reaper and Bulldog -- "exactly the expensive T2 units this is meant to avoid
	// buying while behind". That reasoning is inverted once the enemy has teched.
	//
	// apexearth, watching: "we're throwing t one units at t two and t three armies
	// ... they just get absolutely demolished by pretty much everything the enemy
	// is fielding, so they're almost like a complete waste of space and effort."
	//
	// It was also self-reinforcing. This branch bypasses the factory tier weights
	// entirely -- it asks GetRoleDef(ASSAULT) directly -- so losing produced Stumpy
	// spam, which lost harder, which produced more: measured at 18.1% of all metal
	// in one 8-game run, against stock's 2.0%. Cutting the tier weights could not
	// touch it, because this path never reads them.
	//
	// Once we hold T2, the advanced plant answers instead. Expensive units are the
	// point when the cheap ones cannot trade.
	const bool isT1Fac =
		((Factory::userData[unit.circuitDef.id].attr & (Factory::Attr::T2 | Factory::Attr::T3)) == 0);
	const bool isT2Fac =
		((Factory::userData[unit.circuitDef.id].attr & Factory::Attr::T2) != 0);
	// !gEcoActive: the eco lead is BY CONSTRUCTION behind on the field -- it
	// fields no army, so LosingGround() is true for it permanently, and this
	// branch would otherwise be the one thing that turns its whole income into
	// units. Its own release conditions are what decide when it fights.
	// The economic gates (HaveT2Mex, ARMY_PUSH_MIN_INCOME) apply to the ADVANCED
	// plant only. They are the right test for a T2 unit and exactly the wrong
	// one for the case this rule exists to catch: a player being overrun loses
	// its mexes and its income first, so both gates go false precisely when it
	// is losing hardest, and the push is switched off for the only players that
	// need it. Measured in a 4v4: t2Mex stayed 0 all game for three of four apex
	// players and income peaked at 17 and 11 for the two that died, so "behind
	// on the field" fired 6x and 4x for the two healthy players and NEVER for
	// the two that were being killed. Fodder from a T1 lab is cheap enough that
	// a collapsing player can still pay for it, which is the whole point.
	const bool advPushOk = isT2Fac && HaveT2Mex()
			&& (aiEconomyMgr.metal.income >= ARMY_PUSH_MIN_INCOME);
	if (!gEcoActive && (isT1Fac ? !gHaveT2 : advPushOk) && Military::LosingGround()
		&& (ai.frame >= gNextArmyPush))
	{
		// Spam means SPAM. apexearth: "i said long ago to make spam units when
		// we're dying. a stumpy is not a spam unit." TODO.md is specific -- ticks,
		// grunts, pawns, rascals, wheelies, "the cheap but fast units", whose
		// purpose is vision and distraction.
		//
		// This asked for the ASSAULT role two pushes in three, which is the
		// mainstay tank: armstump for a vehicle plant. So "spam when dying" bought
		// 180-metal tanks that trade badly against a teched enemy, and displaced
		// the real army while doing it -- 18.1% of all metal in one 8-game run.
		//
		// Now split by what the factory IS: a T1 lab makes fodder, the advanced
		// plant makes the army that can actually trade.
		++gArmyPushCount;
		CCircuitDef@ want = null;
		if (isT1Fac)
			@want = Fodder(unit.circuitDef);
		else
			@want = aiFactoryMgr.GetRoleDef(unit.circuitDef, Unit::Role::ASSAULT.type);
		if (want !is null) {
			IUnitTask@ rec = aiFactoryMgr.Enqueue(TaskS::Recruit(
					Task::RecruitType::FIREPOWER, Task::Priority::HIGH,
					want, unit.GetPos(ai.frame), 0.f));
			if (rec !is null) {
				gNextArmyPush = ai.frame + ARMY_PUSH_SPACING;
				if (ai.frame >= gNextArmyLog) {
					gNextArmyLog = ai.frame + 30 * SECOND;
					AiLog(T() + "apex: behind on the field, massing " + want.GetName()
						+ " army=" + formatFloat(aiMilitaryMgr.armyCost, "", 0, 0)
						+ " enemyArmy=" + formatFloat(Military::EnemyArmyCost(), "", 0, 0));
				}
				return rec;
			}
		}
	}

	if (gHaveT2 && ((IsDesignatedLead() && Builder::OwesAdvCons()) || !Builder::gHaveAdvCon)) {
		// BUILDER, not BUILDER2. builderT2 is registered as a SUBROLE of builder
		// (AiAddRole("builderT2", BUILDER.type)) and the factory role map is
		// indexed by BASE roles only -- FactoryManager.cpp:1057 looks up
		// ROLE_TYPE(BUILDER) itself. Asking for BUILDER2 returned NULL every time,
		// so this branch silently fell through to normal production: a plant would
		// finish and immediately build Banishers and radars while the team upgraded
		// no mexes at all. For an advanced plant the base builder IS the advanced
		// constructor -- coravp's only builder is coracv.
		CCircuitDef@ con = aiFactoryMgr.GetRoleDef(unit.circuitDef, Unit::Role::BUILDER.type);
		if (con !is null) {
			IUnitTask@ rec = aiFactoryMgr.Enqueue(TaskS::Recruit(
					Task::RecruitType::BUILDPOWER,
					IsSmallTeam() ? Task::Priority::NORMAL : Task::Priority::NOW,
					con, unit.GetPos(ai.frame), 0.f));
			if (rec !is null)
				return rec;
		}
	}

	// The eco lead's factory. Build power while it is short of it, then nothing
	// at all -- an idle line is the point, not a failure. Every unit this factory
	// does not make is income the builders spend on mexes, energy and the T2/T3
	// economy instead, which is the entire reason the role exists.
	//
	// This sits AFTER the advanced-constructor branch above deliberately: handing
	// advanced cons to the rest of the team is the tech lead's job and the eco
	// lead is still the tech lead. It only replaces what would otherwise be army.
	// The advanced air plant can only be built by an AIR constructor, and the T1
	// air plant's own ratios give constructors about 5% -- so a player can hold
	// the air slot all game and never produce one. Without the advanced plant
	// there are no fighters at all, because FactoryManager's isAvailableDef
	// requires (isActive || IsAttrRare()) and isActive goes false for a T1
	// factory the moment its owner has any T2 factory. Fighters are not rare.
	// One constructor unlocks the plant; after that the ratios decide.
	if (IsAirFactory(unit.circuitDef) && (AirConCount() < AIR_CON_MIN)
		&& (ai.frame >= gNextEcoAirCon))
	{
		CCircuitDef@ acon = aiFactoryMgr.GetRoleDef(unit.circuitDef, Unit::Role::BUILDER.type);
		if (acon !is null) {
			IUnitTask@ rec = aiFactoryMgr.Enqueue(TaskS::Recruit(
					Task::RecruitType::BUILDPOWER, Task::Priority::NORMAL,
					acon, unit.GetPos(ai.frame), 0.f));
			if (rec !is null) {
				gNextEcoAirCon = ai.frame + ECO_AIR_SPACING;
				return rec;
			}
		}
	}

	// A gantry is the declared win condition, and the eco lead builds no army by
	// design -- so a gantry it came by, built or resurrected, produced nothing at
	// all. It has no BUILDER-role unit either, so the constructor branch below
	// cannot absorb it and it falls through to `return null` every call.
	// apexearth: "our eco guy ressurrected a gantry and then never made any unit
	// from it". Owning one overrides the rule.
	CCircuitDef@ gantDef = T3Gantry();
	const bool isOwnGantry = (gantDef !is null)
			&& (unit.circuitDef.id == gantDef.id);

	if (gEcoActive && !isOwnGantry) {
		// The aircraft plant makes constructors and nothing else. Every other
		// branch above has already had its say, so reaching here with an air
		// factory means this player has one purely as build power.
		if (IsAirFactory(unit.circuitDef)) {
			if ((AirConCount() < ECO_AIR_CON_CAP) && (ai.frame >= gNextEcoAirCon)) {
				CCircuitDef@ acon = aiFactoryMgr.GetRoleDef(unit.circuitDef, Unit::Role::BUILDER.type);
				if (acon !is null) {
					IUnitTask@ rec = aiFactoryMgr.Enqueue(TaskS::Recruit(
							Task::RecruitType::BUILDPOWER, Task::Priority::NORMAL,
							acon, unit.GetPos(ai.frame), 0.f));
					if (rec !is null) {
						gNextEcoAirCon = ai.frame + ECO_AIR_SPACING;
						return rec;
					}
				}
			}
			return null;
		}
		// GetWorkerCount() counts every worker we own, and a nano turret IS one --
		// observed live, the eco lead logged cons=25 against a cap of 16 while
		// standing on eleven turrets. Left alone, the rectangle eats the mobile
		// constructor budget and the player ends up with turrets and nobody to
		// walk to the next mex. Count the turrets back out -- and rez bots too,
		// which CBuilderManager puts in `workers` without any build power.
		if ((int(aiBuilderMgr.GetWorkerCount()) - Builder::NanoCount() - Builder::RezCount()
				< int(ECO_CON_CAP))
			&& (ai.frame >= gNextEcoCon))
		{
			CCircuitDef@ con = aiFactoryMgr.GetRoleDef(unit.circuitDef, Unit::Role::BUILDER.type);
			if (con !is null) {
				IUnitTask@ rec = aiFactoryMgr.Enqueue(TaskS::Recruit(
						Task::RecruitType::BUILDPOWER, Task::Priority::NORMAL,
						con, unit.GetPos(ai.frame), 0.f));
				if (rec !is null) {
					gNextEcoCon = ai.frame + ECO_CON_SPACING;
					return rec;
				}
			}
		}
		if (ai.frame >= gNextEcoLog) {
			gNextEcoLog = ai.frame + 60 * SECOND;
			AiLog(T() + "apex: eco lead idle line, cons="
				+ aiBuilderMgr.GetWorkerCount()
				+ " mInc=" + formatFloat(aiEconomyMgr.metal.income, "", 0, 1)
				+ " eInc=" + formatFloat(aiEconomyMgr.energy.income, "", 0, 0));
		}
		return null;
	}

	// An air plant that Air:: did not claim above falls through to
	// DefaultMakeTask like every other factory.
	//
	// This used to return null for ANY air factory unless the air role had been
	// permanently abandoned, on the reasoning that every sanctioned use of an air
	// plant claims it earlier in this function. That reasoning holds only for the
	// air lead's plants while it is armed. It is false for the air-slot opener,
	// which is never the lead (the lead is elected on highest income and the
	// opener has the worst economy on the team), and it is false for the lead
	// itself whenever Air:: declines -- quota met, enemy AA too high, not yet
	// committed. In all of those cases the plant produced NOTHING, permanently.
	//
	// apexearth: "our air player made just 1 con and thats it... air lab just
	// sitting there doing nothing else", then "i bet we have some special flag or
	// branching path of logic that is breaking our air opening player", then
	// "Can we not have this whole Air::RoleAbandoned logic in here? I bet that is
	// the cause of a lot of air labs i see sitting there doing nothing."
	//
	// The concern this originally answered -- trickling bombers one at a time
	// into enemy AA -- is about how bombers are USED, not about starving every
	// air plant on the team.
	return aiFactoryMgr.DefaultMakeTask(unit);
}

}  // namespace Factory
