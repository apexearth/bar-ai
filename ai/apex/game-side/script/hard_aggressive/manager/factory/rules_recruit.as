namespace Factory {

// Recruiting floors: things a factory must produce some of, regardless of
// what the ratios in factory.json would otherwise pick.

// WHICH RULE ANSWERS THE FACTORY, AND HOW OFTEN IT IS ASKED.
//
// AiMakeTask is demand-driven: CIdleTask::Update assigns, and the engine
// re-asks whenever the line has nothing to do. So the CALL RATE is the
// factory's idle rate, and the winner names the rule that answered.
//
// This is the only way to see any of it from script. CFactoryManager exposes
// DefaultMakeTask, Enqueue, GetRoleDef and GetFactoryCount and nothing else --
// neither GetTasks nor CanEnqueueTask is bound, so the pending recruit queue's
// depth is invisible here. Every Enqueue we make is therefore blind: it cannot
// see what is already queued.
array<string> gFacWho;
array<int>    gFacHits;
int gFacCalls = 0;

IUnitTask@ FacWon(const string &in who, IUnitTask@ t)
{
	for (uint i = 0; i < gFacWho.length(); ++i) {
		if (gFacWho[i] == who) {
			++gFacHits[i];
			return t;
		}
	}
	gFacWho.insertLast(who);
	gFacHits.insertLast(1);
	return t;
}

void FactoryDiag(CCircuitUnit@ unit)
{
	++gFacCalls;
	// Diagnostic for the "factory goes idle with a full bank" reports:
	// distinguishes this hook still being called and declining every branch
	// from it not being called at all. See CHANGES.md 2026-08-06.
	if (ai.frame >= gNextFactoryDiag) {
		gNextFactoryDiag = ai.frame + 30 * SECOND;
		string census = "";
		for (uint i = 0; i < gFacWho.length(); ++i)
			census += " " + gFacWho[i] + "=" + gFacHits[i];
		AiLog(T() + "apex: factory-diag " + unit.circuitDef.GetName()
			+ " mInc=" + formatFloat(aiEconomyMgr.metal.income, "", 0, 1)
			+ " mCur=" + formatFloat(aiEconomyMgr.metal.current, "", 0, 0)
			+ " mStor=" + formatFloat(aiEconomyMgr.metal.storage, "", 0, 0)
			+ " isMetalFull=" + (aiEconomyMgr.isMetalFull ? "1" : "0")
			+ " hasTask=" + ((unit.task !is null) ? "1" : "0")
			+ " calls=" + gFacCalls
			+ " queue=" + QueueDepth() + " unstarted=" + QueueUnstarted()
			+ " facs=" + aiFactoryMgr.GetFactoryCount()
			+ " won:" + census);
	}
}

IUnitTask@ AssistantWork(CCircuitUnit@ unit)
{
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
	return null;
}

IUnitTask@ RezBotFloor(CCircuitUnit@ unit)
{
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
			// so for every 500 wrecked metal seen make 1 rezbot???"
			const float wreckValue = Builder::WreckSeenValue();
			const int want = RezBotsWanted();
			if (ai.frame >= gNextRezDiag) {
				gNextRezDiag = ai.frame + 15 * SECOND;
				AiLog(T() + "apex: rez-diag lab=" + (lab !is null ? lab.GetName() : "null")
					+ " rez=" + (rez !is null ? rez.GetName() : "null")
					+ " rezCount=" + (rez !is null ? rez.count : -1)
					+ " wreckSeen=" + formatFloat(wreckValue, "", 0, 0)
					+ " inc=" + formatFloat(SteadyIncome(), "", 0, 0)
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
	return null;
}

IUnitTask@ BankBuysBuildPower(CCircuitUnit@ unit)
{
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
	return null;
}

IUnitTask@ LateRadarPlane(CCircuitUnit@ unit)
{
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
		if ((eye !is null) && eye.IsAvailable(ai.frame) && (eye.count < 1 + int(aiEconomyMgr.metal.income / LATE_SCOUT_INCOME))) {
			IUnitTask@ rec = aiFactoryMgr.Enqueue(TaskS::Recruit(
					Task::RecruitType::FIREPOWER, Task::Priority::NORMAL,
					eye, unit.GetPos(ai.frame), 0.f));
			if (rec !is null) {
				gNextScout = ai.frame + LATE_SCOUT_SPACING;
				return rec;
			}
		}
	}
	return null;
}

IUnitTask@ LateFighterScreen(CCircuitUnit@ unit)
{
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
		if ((fig !is null) && (fig.count < 1 + int(aiEconomyMgr.metal.income / LATE_FIGHTER_INCOME))) {
			IUnitTask@ rec = aiFactoryMgr.Enqueue(TaskS::Recruit(
					Task::RecruitType::FIREPOWER, Task::Priority::HIGH,
					fig, unit.GetPos(ai.frame), 0.f));
			if (rec !is null) {
				gNextFighter = ai.frame + LATE_FIG_SPACING;
				return rec;
			}
		}
	}
	return null;
}

}  // namespace Factory
