namespace Builder {

// KILL PHASE (docs/20-brain-overhaul.md): the ladder is holds -> Brain::Decide
// -> idle. Every leaf spending rule is gone, and there is deliberately NO
// fall-through to aiBuilderMgr.DefaultMakeTask -- the engine's native economy
// is leaf logic too. A constructor the Brain has no answer for idles visibly.
//
// Rez-bot unit thoughts (flee, medic, salvage, corpse reclaim) are kept per
// the overhaul's KEEP list; they act on units that exist, they build nothing.
IUnitTask@ AiMakeTask(CCircuitUnit@ unit)
{
	if (unit is null)
		return null;
	const double _mt = Perf::T0();
	// EVERY BUILDER UPDATE PAYS INTO THE PENDING ELECTIONS, not just the ones
	// that reach the auction. 9,200 of 15,891 calls measured here return early
	// holding a task or on the rez gate; without this those frames do nothing
	// for the half-built sets, and an election's step rate collapses to how
	// often the engine hands that ONE builder back (Market::ElecPump).
	{ double _tP = Perf::T0(); Market::ElecPump(); Perf::Add("bld.pump", _tP); }
	IUnitTask@ _r = MakeTaskInner(unit);
	Perf::Add("hk.maketask.builder", _mt);
	return _r;
}

// The rezzer chain keeps Decide's per-unit cadence: an idle rez bot
// otherwise re-runs the whole corpse/medic/salvage scan every idle update
// (flee is not rate-limited -- safety stays live). Spring unit ids cap at
// 32k, same sizing as Market::gLastDecideAt.
array<int> gRzDecideVer(32001, -1);
// Per unit: when the held build's ground was last checked for danger.
array<int> gHotCheckAt(32001, -30000);
int gLetGo = 0;
int gNextLetGoLog = 0;

// A fallen commander outranks every other rez job -- flee alone comes
// first (a dead rez bot rescues nobody).
// What each rez election came to, per minute (apexearth, seed 20: "rezbots
// idling between actions... analyze what they're doing"). A null here
// hands the bot to the DLL, which parks it on a 10 s patrol.
float ArmyFrontFfLog()
{
	AIFloat3 p;
	return ArmyFront(p);
}
float FrontFf()
{
	AIFloat3 fp;
	if (!Military::FrontLinePos(fp))
		return -1.f;
	return Military::ForwardFraction(fp);
}
string HeldBtStr()
{
	string s = "";
	for (int k = 0; k < 32; ++k)
		if (gRzHeldBt[k] > 0)
			s += k + ":" + gRzHeldBt[k] + ",";
	return s;
}
const int RZ_RULES = 9;
array<int> gRzRule(RZ_RULES, 0);   // rescue medic salvage eat rez repair idle none retire
int gRzGate = 0;
// Elections held while something could already shoot the bot where it stands:
// the DLL's guard is walking it out at the same moment (BuilderManager's
// UpdateRezGuard), and this says how much of the fleet's time that is.
int gRzPressed = 0;
int gRzHeldPatrol = 0;
int gRzHeldOther = 0;
int gRzNoTask = 0;
int gRzBots = 0;
int gNextRzTimeLog = 0;
array<int> gRzLastJobAt;
float gRzWorstS = 0.f;
int gRzWorstId = -1;
float gRzVetoFfSum = 0.f;
array<int> gRzHeldBt(32, 0);
// ONE BOT THINKS, ITS NEIGHBOURS FOLLOW (apexearth 2026-09-20): the job the
// chain just chose is handed to every bot electing within the scan period
// whose own search reach covers it, instead of each running the chain.
IUnitTask@ gRzShared = null;
int gRzSharedAt = -30000;
AIFloat3 gRzSharedPos;
int gRzHandOff = 0;
IUnitTask@ RezzerChain(CCircuitUnit@ unit)
{
	if ((gRzShared !is null) && !gRzShared.IsDead()
		&& (ai.frame - gRzSharedAt <= REZ_WRECK_PERIOD)
		&& (unit.GetPos(ai.frame).distance2D(gRzSharedPos) <= WRECK_SEARCH))
	{
		++gRzHandOff;
		return gRzShared;
	}
	double _tR = Perf::T0();
	IUnitTask@ t = RezzerComRescue(unit);
	Perf::Add("rz.rescue", _tR);
	int why = 0;
	if (t is null) { _tR = Perf::T0(); @t = RezzerMedic(unit); why = 1; Perf::Add("rz.medic", _tR); }
	if (t is null) { _tR = Perf::T0(); @t = RezzerFrontSalvage(unit); why = 2; Perf::Add("rz.salvage", _tR); }
	if (t is null) { _tR = Perf::T0(); @t = RezzerEatCorpse(unit); why = 3; Perf::Add("rz.eat", _tR); }
	if (t is null) { _tR = Perf::T0(); @t = RezzerRezOrEat(unit); why = 4; Perf::Add("rz.rezeat", _tR); }
	if (t is null) { _tR = Perf::T0(); @t = RezzerRetire(unit); why = 8; Perf::Add("rz.retire", _tR); }
	if (t is null) { _tR = Perf::T0(); @t = RezzerRepairNearby(unit); why = 5; Perf::Add("rz.repair", _tR); }
	if (t is null) { _tR = Perf::T0(); @t = RezzerIdle(unit); why = 6; Perf::Add("rz.idle", _tR); }
	if (t is null)
		why = 7;
	++gRzRule[why];
	NoteRezJob(unit, t);
	// A retreat is about the electing bot's own ground, not a job: shared, a
	// patrol home lands on every bot already standing at home.
	if ((t !is null) && !((t.GetType() == Task::Type::BUILDER)
		&& (t.GetBuildType() == Task::BuildType::PATROL)))
	{
		CCircuitUnit@ tg = t.target;
		gRzSharedPos = (tg !is null) ? tg.GetPos(ai.frame) : t.GetBuildPos();
		@gRzShared = OnMap(gRzSharedPos) ? t : null;
		gRzSharedAt = ai.frame;
	}
	if (InEnemyReach(unit.GetPos(ai.frame)))
		++gRzPressed;
	const int slot = ConSlot(unit);
	while (int(gRzLastJobAt.length()) <= slot)
		gRzLastJobAt.insertLast(ai.frame);
	if (t !is null) {
		gRzLastJobAt[slot] = ai.frame;
	} else {
		IUnitTask@ held = unit.task;
		if (held is null)
			++gRzNoTask;
		else if ((held.GetType() == Task::Type::BUILDER)
			&& (held.GetBuildType() == Task::BuildType::PATROL))
			++gRzHeldPatrol;
		else {
			++gRzHeldOther;
			// A non-builder task used to be counted as one bucket, 31, so every
			// empty election read the same and said nothing about what the bot
			// was actually holding. Idle (2) and retreat (4) are different
			// problems: one is standing around, the other is leaving.
			const int bt = (held.GetType() == Task::Type::BUILDER)
					? int(held.GetBuildType()) : (24 + int(held.GetType()));
			if ((bt >= 0) && (bt < 32))
				++gRzHeldBt[bt];
		}
		const float since = float(ai.frame - gRzLastJobAt[slot]) / float(SECOND);
		if (since > gRzWorstS) {
			gRzWorstS = since;
			gRzWorstId = int(unit.id);
		}
	}
	if (ai.frame >= gNextRzTimeLog) {
		gNextRzTimeLog = ai.frame + 60 * SECOND;
		int bots = 0;
		for (uint d = 1; d < Market::gOwnCount.length(); ++d)
			if ((Market::gOwnCount[d] > 0) && Catalog::gRezzer[d])
				bots += Market::gOwnCount[d];
		AiLog(Factory::T() + "apex: rez-time bots=" + bots
			+ " rescue=" + gRzRule[0] + " medic=" + gRzRule[1] + " salvage=" + gRzRule[2]
			+ " eat=" + gRzRule[3] + " rez=" + gRzRule[4] + " retire=" + gRzRule[8] + "+" + gRzBlindToRetire + " repair=" + gRzRule[5]
			+ " idleRule=" + gRzRule[6] + " none=" + gRzRule[7]
			+ " gate=" + gRzGate + " frontVeto=" + gRzFrontVeto + " blocked=" + gRzVetoBlocked + " handoff=" + gRzHandOff
			+ " hurtOk=" + gRzOkHurt + "/" + (gRzOkHurt + gRzVetoHurt)
			+ " groundOk=" + gRzOkGround + "/" + (gRzOkGround + gRzVetoGround)
			// Whether the cover branch of RezSiteOk is deciding anything at all.
			// cover=0/N means GetAllyInflAt reads empty to us and the siting
			// rule has silently fallen back to the old exclusion zone.
			+ " cover=" + gRzOkCover + "/" + gRzSiteCalls
			+ " pressed=" + gRzPressed
			+ " noneHeld=" + gRzNoTask + "/" + gRzHeldPatrol + "/" + gRzHeldOther
			+ " worst=#" + gRzWorstId + " " + formatFloat(gRzWorstS, "", 0, 0) + "s"
			+ " ffLane=" + formatFloat(Military::ForwardFraction(Military::LanePos()), "", 0, 2)
			+ " ffFront=" + formatFloat(FrontFf(), "", 0, 2)
			+ " ffArmy=" + formatFloat(ArmyFrontFfLog(), "", 0, 2)
			+ " ffVetoAvg=" + formatFloat((gRzFrontVeto > 0) ? gRzVetoFfSum / float(gRzFrontVeto) : 0.f, "", 0, 2)
			+ " heldBt=" + HeldBtStr() + RzCensusStr());
		gRzSwLocal = 0;
		gRzFldNone = 0;
		gRzFldThreat = 0;
		gRzFldSite = 0;
		gRzHealPick = 0;
		gRzHealDist = 0.f;
		gRzHealMoving = 0;
		gRzHealOutrun = 0;
		gRzHealWreckWin = 0;
		gRzHealRetreatSkip = 0;
		gRzMedWalkBack = 0;
		gRzStageEv = 0;
		gRzStageTook = 0;
		gRzStageWaitS = 0.f;
		gRzStageGone = 0;
		gRzIdleAtStand = 0;
		for (int k = 0; k < RZ_RULES; ++k)
			gRzRule[k] = 0;
		gRzGate = 0;
		gRzPressed = 0;
		gRzFrontVeto = 0;
		gRzBlindToRetire = 0;
		gRzVetoBlocked = 0;
		gRzHandOff = 0;
		gRzOkHurt = 0;
		gRzVetoHurt = 0;
		gRzOkGround = 0;
		gRzVetoGround = 0;
		gRzSiteCalls = 0;
		gRzOkCover = 0;
		gRzNoTask = 0;
		gRzHeldPatrol = 0;
		gRzHeldOther = 0;
		gRzWorstS = 0.f;
		gRzWorstId = -1;
		gRzVetoFfSum = 0.f;
		for (int k = 0; k < 32; ++k)
			gRzHeldBt[k] = 0;
	}
	return t;
}

// Where the commander's elections go, per minute (apexearth: "ensure the
// commander's time isn't wasted"). Exec lines say what he built; nothing
// said how often he was handed nothing.
int gComJobs = 0;
int gComNull = 0;
int gComRet = 0;
int gComBounce = 0;
int gNextComTimeLog = 0;

// The commander's idle gaps, as a census: one opens when his task is removed or
// he is asked while idle, and closes when he is handed a job. Its cause is what
// it met: 1 the re-election gate, 2 a sliced election not yet finished, 4 an
// election that came back empty, none of them the engine's settle-and-ask
// cadence. Walking is sampled once a second.
const int COM_IDLE_MINUTES = 10;
int gCiFrom = -1;
int gCiMet = 0;
int gCiIdleF = 0, gCiGaps = 0, gCiWorstF = 0, gCiWalkS = 0;
array<int> gCiCauseN(4, 0);
array<int> gCiCauseF(4, 0);
int gCiTotIdleF = 0, gCiTotGaps = 0, gCiTotWorstF = 0, gCiTotWalkS = 0;
array<int> gCiTotCauseN(4, 0);
array<int> gCiTotCauseF(4, 0);
int gCiMinute = 0;

bool ComIdleOn()
{
	return ai.frame <= COM_IDLE_MINUTES * 60 * SECOND;
}
void ComIdleBegin()
{
	if ((gCiFrom < 0) && ComIdleOn()) {
		gCiFrom = ai.frame;
		gCiMet = 0;
	}
}
void ComIdleEnd()
{
	if (gCiFrom < 0)
		return;
	const int gap = ai.frame - gCiFrom;
	gCiFrom = -1;
	const int c = ((gCiMet & 1) != 0) ? 1 : (((gCiMet & 2) != 0) ? 2 : (((gCiMet & 4) != 0) ? 3 : 0));
	gCiIdleF += gap;
	++gCiGaps;
	if (gap > gCiWorstF)
		gCiWorstF = gap;
	++gCiCauseN[c];
	gCiCauseF[c] += gap;
}
string ComIdleCauses(const array<int>& in n, const array<int>& in f)
{
	return " ask=" + n[0] + "/" + formatFloat(float(f[0]) / float(SECOND), "", 0, 1)
		+ " gate=" + n[1] + "/" + formatFloat(float(f[1]) / float(SECOND), "", 0, 1)
		+ " slice=" + n[2] + "/" + formatFloat(float(f[2]) / float(SECOND), "", 0, 1)
		+ " none=" + n[3] + "/" + formatFloat(float(f[3]) / float(SECOND), "", 0, 1);
}
// Once a second, from CommWatch: a job handed to him outside AiMakeTask closes
// the gap here, a second late at most.
void ComIdleTick(bool onTask, bool walking)
{
	if (gCiMinute >= COM_IDLE_MINUTES)
		return;
	if (onTask)
		ComIdleEnd();
	if (walking)
		++gCiWalkS;
	if (ai.frame < (gCiMinute + 1) * 60 * SECOND)
		return;
	++gCiMinute;
	AiLog(Factory::T() + "apex: com-idle t=" + ai.teamId + " min=" + gCiMinute
		+ " idleS=" + formatFloat(float(gCiIdleF) / float(SECOND), "", 0, 1)
		+ " walkS=" + gCiWalkS + " gaps=" + gCiGaps
		+ " worstS=" + formatFloat(float(gCiWorstF) / float(SECOND), "", 0, 1)
		+ " open=" + ((gCiFrom >= 0) ? (ai.frame - gCiFrom) : -1)
		+ ComIdleCauses(gCiCauseN, gCiCauseF));
	gCiTotIdleF += gCiIdleF;
	gCiTotGaps += gCiGaps;
	gCiTotWalkS += gCiWalkS;
	if (gCiWorstF > gCiTotWorstF)
		gCiTotWorstF = gCiWorstF;
	for (uint k = 0; k < 4; ++k) {
		gCiTotCauseN[k] += gCiCauseN[k];
		gCiTotCauseF[k] += gCiCauseF[k];
		gCiCauseN[k] = 0;
		gCiCauseF[k] = 0;
	}
	gCiIdleF = 0;
	gCiGaps = 0;
	gCiWorstF = 0;
	gCiWalkS = 0;
	if (gCiMinute == COM_IDLE_MINUTES) {
		AiLog(Factory::T() + "apex: com-idle-sum t=" + ai.teamId + " mins=" + COM_IDLE_MINUTES
			+ " idleS=" + formatFloat(float(gCiTotIdleF) / float(SECOND), "", 0, 1)
			+ " walkS=" + gCiTotWalkS + " gaps=" + gCiTotGaps
			+ " meanS=" + formatFloat((gCiTotGaps > 0) ? float(gCiTotIdleF) / float(gCiTotGaps * SECOND) : 0.f, "", 0, 2)
			+ " worstS=" + formatFloat(float(gCiTotWorstF) / float(SECOND), "", 0, 1)
			+ ComIdleCauses(gCiTotCauseN, gCiTotCauseF));
		gCiFrom = -1;
	}
}

void NoteCommDecide(CCircuitUnit@ unit, IUnitTask@ dec, bool bounced)
{
	if (dec is null) {
		if (bounced) {
			gCiMet |= 1;
			return;   // counted by Decide's rate gate, not an empty election
		}
		if (Market::ElecPending(unit)) {
			gCiMet |= 2;
			return;   // mid-slice, not an empty election
		}
		gCiMet |= 4;
		++gComNull;
	}
	else if (dec.GetType() == Task::Type::RETREAT)
		++gComRet;
	else
		++gComJobs;
	if (dec !is null)
		ComIdleEnd();
	if (ai.frame >= gNextComTimeLog) {
		gNextComTimeLog = ai.frame + 60 * SECOND;
		AiLog(Factory::T() + "apex: com-time jobs=" + gComJobs + " none=" + gComNull
			+ " retreat=" + gComRet + " bounce=" + gComBounce
			+ " hp=" + int(unit.GetHealthPercent() * 100.f)
			+ " fwd=" + formatFloat(Military::ForwardFraction(unit.GetPos(ai.frame)), "", 0, 2));
		gComJobs = 0;
		gComNull = 0;
		gComRet = 0;
		gComBounce = 0;
	}
}

IUnitTask@ MakeTaskInner(CCircuitUnit@ unit)
{

	// Unit thoughts for rez bots: safety first, then opportunism.
	const double _tFl = Perf::T0();
	IUnitTask@ t = RezzerFlee(unit);
	Perf::Add("bld.flee", _tFl);
	if (t !is null)
		return t;
	if (IsRezzer(unit)) {
		// Once per wreck-field rebuild, and not at all while something can
		// shoot it. The chain's questions are answered from that field, so a
		// bot that found nothing is asked again when the field has new
		// information and not before -- the field rebuilds about once a
		// second, inside apexearth's 2026-09-06 "delays of more than a second
		// are unacceptable"; the earlier half-second clock re-ran the whole
		// chain on unchanged data.
		if ((int(unit.id) >= 0) && (int(unit.id) < int(gRzDecideVer.length()))) {
			const int ver = ai.GetWreckFieldVersion();
			if ((gRzDecideVer[int(unit.id)] == ver)
				&& !InEnemyReach(unit.GetPos(ai.frame)))
			{
				++gRzGate;
				return null;
			}
			gRzDecideVer[int(unit.id)] = ver;
		}
		const double _tRz = Perf::T0();
		IUnitTask@ rz = RezzerChain(unit);
		Perf::Add("bld.rezzer", _tRz);
		Market::RcmNoteRez(unit, rz);
		return rz;
	}

	// Hold work already in progress: a task the unit is on stays its task.
	// Safety, not spending -- nothing here creates work.
	//
	// ...UNLESS THE GROUND IT IS WALKING TO HAS TURNED HOT. apexearth
	// 2026-09-02: "They're trying to walk straight into the fight to make the
	// defensive turrets... If it's too dangerous then they should pull back
	// or build further away." A constructor still on its way to a build
	// whose site the enemy now holds (Builder::SiteHot) lets the task go and
	// re-elects; the site election offers the same slot stepped back to quiet
	// ground, so "build further away" is what the re-election returns. One
	// already in build range stays -- a frame half up is worth finishing or
	// is the C++ retreat's business. The commander keeps his own rules.
	IUnitTask@ held = unit.task;
	const bool isCom = unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask);
	if (isCom) {
		if ((held is null) || (held.GetType() == Task::Type::IDLE))
			ComIdleBegin();
		else if (held.GetType() == Task::Type::BUILDER)
			ComIdleEnd();
	}
	if ((held !is null) && (held.GetType() == Task::Type::BUILDER)) {
		const int uidx = int(unit.id);
		if ((uidx >= 0) && (uidx < int(gHotCheckAt.length()))
			&& (ai.frame - gHotCheckAt[uidx] >= 2 * SECOND)
			&& !unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask))
		{
			gHotCheckAt[uidx] = ai.frame;
			const AIFloat3 at = held.GetBuildPos();
			const float reach = Catalog::gBuildDist[int(unit.circuitDef.id)] + 64.f;
			if (OnMap(at) && (unit.GetPos(ai.frame).distance2D(at) > reach)
				&& SiteLiveHot(at) && !EscortCovers(unit, at))
			{
				held.RemoveUnit(unit);
				++gLetGo;
				if (ai.frame >= gNextLetGoLog) {
					gNextLetGoLog = ai.frame + 30 * SECOND;
					AiLog(Factory::T() + "apex: con-letgo " + unit.circuitDef.GetName()
						+ " #" + unit.id + " site=" + int(at.x) + "," + int(at.z)
						+ " total=" + gLetGo);
				}
				@held = null;
			}
		}
		if (held !is null)
			return held;
	}

	// The arbiter. Empty market during the kill phase: Decide returns null
	// and the constructor idles.
	//
	// THE ELECTION CHARGES ITSELF AS IT SPENDS, and this settles only the
	// remainder -- the prologue above, the safety rungs, the execution. Charging
	// the whole call out here was the bug it replaces: the budget was tested at
	// the DOOR of an election that then ran to completion, so a 28.5 ms election
	// was never bounded by an 8 ms slice and the frame it landed on carried all
	// of it. Every return path still counts, and nothing counts twice.
	const double _tD = ai.ClockUs();
	const int bounce0 = gComBounce;
	IUnitTask@ dec = Brain::Decide(unit);
	Perf::Add("bld.decide", _tD);
	Market::ElecSpendRest(ai.ClockUs() - _tD);
	if (isCom)
		NoteCommDecide(unit, dec, gComBounce != bounce0);
	return dec;
}

}  // namespace Builder
