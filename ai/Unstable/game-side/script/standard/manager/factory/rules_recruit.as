namespace Factory {

// Recruiting floors: things a factory must produce some of, regardless of
// what the ratios in factory.json would otherwise pick.

// AiMakeTask is demand-driven (CIdleTask::Update re-asks whenever idle), so
// call rate is the factory's idle rate. CFactoryManager exposes no way to read
// the pending queue (no GetTasks/CanEnqueueTask), so every Enqueue here is
// blind to what's already queued -- this diagnostic is the only visibility.
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

// Turret id -> next frame its patrol may be re-issued. Orders persist on a
// static unit, so the re-issue is only self-healing after a retreat/damage
// interruption, not the mechanism itself.
dictionary gNanoPatrolNext;
// True when AssistantWork handled a nano turret (elected OR deferred): the
// caller must stop either way -- a deferred turret falling through the
// recruit ladder was 124s of a 60m sim walking rules that cannot produce
// anything for a turret.
bool gAssistHandled = false;

IUnitTask@ AssistantWork(CCircuitUnit@ unit)
{
	// Nano turrets register with the FACTORY manager alongside factories, so
	// they arrive here -- but every branch below is about RECRUITING and none
	// can produce a task for one, so an unconditional `return null` here left
	// every turret permanently idle. Only DefaultMakeTask routes an assistant to
	// CreateAssistTask, so hand it there directly.
	//
	// BUDGETED: DefaultMakeTask runs the engine's full assist election with
	// its spatial scans, and 100+ idle turrets per player re-running it every
	// pass was mt.factory's 203s -- the single largest script cost of a whole
	// 8v8 sim (2.86ms/call, 71k calls). At most two turret elections per
	// frame per player, staggered on team-id parity when rich; the rest wait
	// a frame, which an idle turret cannot tell from waiting for work.
	gAssistHandled = false;
	CCircuitDef@ nano = Builder::NanoDef();
	if ((nano !is null) && (unit.circuitDef.id == nano.id)) {
		gAssistHandled = true;
		// A STANDING PATROL, not an assist election: idle turrets do NOT work
		// on their own (watched live 2026-08-18 -- rows of them sat idle beside
		// building factories once the election budget throttled DefaultMakeTask),
		// and per-turret elections were mt.factory's 203s. Patrol hands the job
		// to the engine's own builder AI -- assist/repair/reclaim in range,
		// forever, no script cost. The order persists, so the periodic re-issue
		// below only heals an interrupted turret.
		const string key = "" + int(unit.id);
		int next = 0;
		gNanoPatrolNext.get(key, next);
		if (ai.frame >= next) {
			gNanoPatrolNext.set(key, ai.frame + 120 * SECOND);
			AIFloat3 p = unit.GetPos(ai.frame);
			p.x += 64.f;
			if (OnMap(p))
				unit.CmdPatrolTo(p);
		}
		return null;
	}
	return null;
}

IUnitTask@ RezBotFloor(CCircuitUnit@ unit)
{
	// Rez bots from the bot lab, only once there is something to reclaim or
	// resurrect -- at game start nothing has died, so this floor would otherwise
	// compete HIGH-priority against the opening mex/army push for no benefit.
	// Gated on the same wreck search EnqueueWreckReclaim uses (builder.as), so it
	// self-corrects the moment a wreck actually exists rather than guessing a
	// fixed delay. Placed high once armed, same as the fighter floor: it's a
	// floor, not a strategy, and the branches below would otherwise take every
	// slot the lab has.
	if (HaveT1BotLab() && (ai.frame >= gNextRez)) {
		CCircuitDef@ lab = T1BotLab();
		CCircuitDef@ rez = RezBotDef();
		if ((lab !is null) && (rez !is null) && (unit.circuitDef.id == lab.id)
			&& rez.IsAvailable(ai.frame))
		{
			// getFeaturesIn is LOS-gated (SSkirmishAICallbackImpl::getFeaturesIn
			// -> GetCallBack(id)->GetFeatures), not a plain spatial query, so
			// querying from a point with no unit standing there returns empty
			// regardless of radius. Reads Builder::NoteWreckSeen instead, which
			// mobile builders populate from their own in-vision wreck scan.
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
	// A full bank buys build power, faction-agnostic (replaces a hand-tuned
	// armfark-only ratio bump). Gated on the bank rather than a count, so it
	// self-corrects: once the extra build power drains it, ordinary ratios take
	// the slot back.
	if (aiEconomyMgr.isMetalFull && (ai.frame >= gNextAssistBot)) {
		// Ask THIS factory for its support-role unit and only take it if it's the
		// assist bot -- enqueueing a def the factory can't build is a silent no-op
		// (see CLAUDE.md), so the factory's own build options must be the
		// authority, not a name list.
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
	// Late-game radar planes to find a surviving commander before it rebuilds.
	// Named directly rather than left to factory ratios: armawac/corawac sit at
	// 0.05/0.0 in the advanced air plant's list and legwhisper has no role or
	// ratio in behaviour.json at all, so ratio-driven production would rarely
	// or never build one.
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
	// Standing late-game fighter screen from any air plant. A floor, not a
	// strategy -- placed above every other branch so it's never the thing
	// skipped. Air::MakeFactoryTask still outranks it since the assassin strike
	// is timed and this isn't. GetRoleDef(AA) returns whatever this plant can
	// build, so it never asks for an aircraft the factory can't make.
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
