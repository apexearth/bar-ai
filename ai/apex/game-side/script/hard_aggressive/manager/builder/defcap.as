namespace Builder {

// HOW MUCH OF THE CONSTRUCTOR POOL MAY BE POINTED AT DEFENCE.
//
// apexearth, as policy: "We should limit how many cons can be making defenses to
// 50% of our cons unless our base is under attack and we need to panic build."
//
// A SHARE, not a count -- it needs no revisiting as the pool grows, and it is the
// same shape as the rest of this codebase's bounds.
//
// What he is solving, said immediately after: "Our cons kept dying that game
// because no military was protecting them while they tried to make defenses. They
// built a bit too far up on the front line."

// The share above which no NEW defence election is accepted. Read from a tunable
// so it is an experiment rather than a decree.
const float DEF_SHARE_CAP = 0.5f;

int gDefCapRefused = 0;
int gDefCapPassed = 0;

bool IsDefenceBuild(IUnitTask@ t)
{
	if ((t is null) || (t.GetType() != Task::Type::BUILDER))
		return false;
	const int bt = t.GetBuildType();
	return (bt == int(Task::BuildType::DEFENCE))
		|| (bt == int(Task::BuildType::BUNKER))
		|| (bt == int(Task::BuildType::BIG_GUN));
}

// Constructors holding a defence build task, over constructors we hold.
//
// Counts one WALKING to a tower as well as one building it -- the task is held
// for the whole walk, and the walk is when they die. It also counts one that
// JOINED a tower someone else started, because the question is what share of our
// build power is pointed at defence, not how many separate towers are going up;
// three constructors on one tower is three constructors not expanding.
//
// The commander is deliberately outside both halves: it is not one of "our cons"
// in the sentence above, it has its own safety ladder, and its single home sentry
// is asked for once and never again.
float DefenceShare(int &out onDef, int &out pool)
{
	onDef = 0;
	pool = 0;
	for (uint i = 0; i < Crew::gId.length(); ++i) {
		CCircuitUnit@ c = ai.GetTeamUnit(Id(Crew::gId[i]));
		if (c is null)
			continue;
		++pool;
		if (IsDefenceBuild(c.task))
			++onDef;
	}
	return (pool > 0) ? (float(onDef) / float(pool)) : 0.f;
}

// ---------------------------------------------------------------------------
// THE PANIC CLAUSE, AND A SECOND CANDIDATE FOR IT MEASURED BESIDE IT.
//
// Two sensors, both evaluated every sample, both reported, only one acting:
//
//   contested -- Military::BaseContested(), net influence at home below zero.
//                Already shipped and already trusted by the posture hold-release
//                and the army's defend-home rule, so using it here adds no new
//                risk. This is what lifts the cap.
//
//   siege     -- enemies actually present inside our own committed footprint AND
//                that ground contested. Strictly narrower than `contested` by
//                construction. Sensed and logged unconditionally at zero cost;
//                it only lifts the cap when apex_siege is turned on.
//
// Neither duty cycle has ever been measured, and an exception clause that is true
// most of the time is not an exception. The log line below is what settles it: if
// either reads much above 20% on, it is the wrong trigger and we know before it
// has cost anything.

const int   SIEGE_SAMPLE = 2 * SECOND;
// Anti-flicker. An influence reading that crosses zero twice in a second must not
// switch a build policy twice in a second.
const int   SIEGE_HOLD   = 20 * SECOND;
// Enemies inside the footprint before it is a siege rather than a scout. digin.as
// makes the same distinction in the same words.
const float SIEGE_FOES   = 3.f;

bool gSiegeOn = false;
int  gSiegeUntil = 0;
int  gSiegeSamples = 0;
int  gSiegeOnSamples = 0;
int  gContestedSamples = 0;
int  gNextSiegeSample = 0;
int  gNextSiegeLog = 0;

// Radius of our own committed footprint, from the base plan's own record of the
// slots it actually USED -- half the diagonal of that rectangle. Floored at the
// home crew's radius so an opening with nothing committed yet still has a base.
float SiegeRadius()
{
	float r = Crew::HOME_RADIUS;
	if (Base::gGrown) {
		const float w = (Base::gMaxLat - Base::gMinLat) * 0.5f;
		const float d = Base::gMaxDepth;
		const float half = sqrt(w * w + d * d);
		if (half > r)
			r = half;
	}
	return r;
}

void UpdateSiege()
{
	if (ai.frame < gNextSiegeSample)
		return;
	gNextSiegeSample = ai.frame + SIEGE_SAMPLE;
	if (!gHomeSet || !OnMap(gHomePos))
		return;

	++gSiegeSamples;
	const bool contested = Military::BaseContested();
	if (contested)
		++gContestedSamples;

	// GetEnemyCostAt returns a COUNT despite its name, and is LOS-gated --
	// acceptable here for the same reason ThreatFor accepts it: a siege of our own
	// base is close enough to see.
	const bool foes = ai.GetEnemyCostAt(gHomePos, SiegeRadius()) >= SIEGE_FOES;
	const bool raw = contested && foes;

	if (raw) {
		gSiegeOn = true;
		gSiegeUntil = ai.frame + SIEGE_HOLD;
	} else if (gSiegeOn && (ai.frame >= gSiegeUntil)) {
		gSiegeOn = false;
	}
	if (gSiegeOn)
		++gSiegeOnSamples;

	if (ai.frame < gNextSiegeLog)
		return;
	gNextSiegeLog = ai.frame + 60 * SECOND;
	int onDef = 0, pool = 0;
	const float share = DefenceShare(onDef, pool);
	AiLog(Factory::T() + "apex: defcap share=" + onDef + "/" + pool
		+ " (" + int(share * 100.f) + "%) refused=" + gDefCapRefused
		+ " passed=" + gDefCapPassed
		+ " | siege on=" + int(100.f * float(gSiegeOnSamples)
			/ float((gSiegeSamples > 0) ? gSiegeSamples : 1)) + "%"
		+ " contested=" + int(100.f * float(gContestedSamples)
			/ float((gSiegeSamples > 0) ? gSiegeSamples : 1)) + "%"
		+ " r=" + int(SiegeRadius()));
}

// The cap is lifted while the base is being fought over. apex_siege swaps the
// incumbent sensor for the narrower new one once its duty cycle is known.
bool PanicBuild()
{
	if (ai.GetTunable("apex_siege", 0.f) > 0.f)
		return gSiegeOn;
	return Military::BaseContested();
}

// ---------------------------------------------------------------------------
// THE SCREEN ITSELF.
//
// ONE SITE, because a cap applied at one producer and not the others is not a
// cap. Defence work reaches a constructor from at least eleven script Enqueues
// (the Brain's fence want, the mex guard, ContestDefence, HomeDeter, CheapAA,
// HeavyAA, Pulsar, the obsolete-tower replacement, the crew's front tower, the
// base jammer, the wall) AND from the engine's own elector and build_chain
// porcupine entries, which no script-side Enqueue cap could ever see. The one
// point every one of them passes through is the answer AiMakeTask returns.
//
// It blocks the INFLOW and measures the STOCK. A constructor already on a tower
// is never pulled off it -- abandoning a half-built tower spends the metal and
// buys nothing.
IUnitTask@ DefenceShareScreen(CCircuitUnit@ unit, bool isComm, IUnitTask@ ans)
{
	// ApexActive is false where we deliberately play as stock; our policy must not
	// reach into that run.
	if ((unit is null) || !ApexActive() || !IsDefenceBuild(ans) || isComm)
		return ans;
	if (ai.GetTunable("apex_def_share", DEF_SHARE_CAP) >= 1.f)
		return ans;
	// Already on defence: this is a re-election onto work in progress, not a new
	// claim, and IsDefenceBuild is exactly what the share counted it as.
	if (IsDefenceBuild(unit.task)) {
		++gDefCapPassed;
		return ans;
	}
	if (PanicBuild()) {
		++gDefCapPassed;
		return ans;
	}
	int onDef = 0, pool = 0;
	const float share = DefenceShare(onDef, pool);
	// A pool too small to have a half is not a pool with a majority on defence.
	// With one constructor any share test is a coin flip on a single unit, and
	// refusing it is how a rule takes the LAST constructor away from the job.
	if ((pool < 2) || (share < ai.GetTunable("apex_def_share", DEF_SHARE_CAP))) {
		++gDefCapPassed;
		return ans;
	}

	++gDefCapRefused;
	// WHERE IT GOES INSTEAD. Never null on this path if it can be helped: a
	// refusal that leaves the unit holding nothing is the idle-constructor bug,
	// and CIdleTask simply re-asks in 8 frames for the same refusal.
	//
	// Expansion first -- it is what the freed constructor time is FOR, and
	// ScreenOffer's factory-cap refusal already reroutes the same way. Then the
	// terminal assist, with defence sites excluded: joining a forward tower walks
	// the constructor to the same place the cap just refused to send it.
	IUnitTask@ mex = FallbackMex(unit);
	if (mex !is null)
		return mex;
	return Assist::Fallback(unit, isComm, false);
}

}  // namespace Builder
