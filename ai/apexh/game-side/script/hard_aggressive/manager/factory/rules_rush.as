namespace Factory {

// The tech rush and the two things that replace ordinary army production
// while it runs.

IUnitTask@ RushBuildPower(CCircuitUnit@ unit, bool &out taken)
{
	taken = false;
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
		taken = true;
		return null;   // never fall through to army production during the rush
	}
	return null;
}

void ConBranchLog(CCircuitUnit@ unit)
{
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
}

IUnitTask@ ShareAdvancedCon(CCircuitUnit@ unit)
{
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
	return null;
}

IUnitTask@ LosingArmyPush(CCircuitUnit@ unit)
{
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
	return null;
}

}  // namespace Factory
