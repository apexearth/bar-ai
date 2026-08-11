namespace Brain {

//------------------------------------------------------------------------------
// WHAT MIX NOW, NOT WHAT NEXT.
//
// apexearth: "imagine we know that we want a certain mix of plain composition...
// then as long as that factory is on and building, it's just constantly pumping
// out the units, and there's never any time when it's not doing that work. It
// also saves the AI time on setting these tasks. It's just pre-setup the proper
// ratio." And: "we set up our queues and over time our composition shifts
// towards the target."
//
// The existing pipeline asks "what should this factory build NEXT" and lets the
// first rule that answers win, so the army mix is an OUTCOME of tier tables,
// response weights and role gates interacting -- nobody can point at where
// "35% raiders" is decided. Here the target is stated, and each decision is
// simply "which role is furthest below it".
//
// Measured motivation, 60 games across five team sizes vs BARb medium: we
// out-produce 1.10-1.76x and field 0.57-0.90x their army in every bracket.
// Production is the weak axis, and it is the one thing the Brain did not touch.
//
// Convergence, not enforcement: one unit is chosen per call, so the composition
// walks toward the target rather than being reset to it. A factory that cannot
// build the wanted role falls through to the rules below, which keeps every
// existing behaviour reachable.
//------------------------------------------------------------------------------

// Target shares of ARMY METAL by role. They sum to 1; what matters is the
// ratios between them, since the choice is always "furthest below target".
//
// Raider-heavy on purpose: USER-FEEDBACK.md records that apex had zeroed the
// raider out of the T1 bot lab and that "we never harass their economy while
// they constantly harass ours" -- stock's bot lab is a raiding factory and ours
// had become an assault factory.
class MixTarget
{
	Type role;
	float share;
	MixTarget(Type r, float s) { role = r; share = s; }
}

array<MixTarget@> gMix;
int gNextMixLog = 0;
int gMixPicks = 0;

// WHICH FACTORIES THE BRAIN OWNS.
//
// apexearth: "make sure the old system doesn't interact with that factory and
// add its own things." Two systems taking turns on one production line is worse
// than either alone -- the mix would aim for a composition while the old floors
// inserted rez bots, radar planes and fighters behind its back, and neither
// would be responsible for the result.
//
// Ownership is claimed the first time the mix successfully enqueues for a
// factory, and from then on that line is the Brain's: the apex production rules
// are skipped for it entirely. The engine's own DefaultMakeTask remains the
// safety net so an owned line never idles.
array<Id> gMixOwned;

bool OwnsFactory(CCircuitUnit@ fac)
{
	if (fac is null)
		return false;
	const Id id = fac.id;
	for (uint i = 0; i < gMixOwned.length(); ++i) {
		if (gMixOwned[i] == id)
			return true;
	}
	return false;
}

void ClaimFactory(CCircuitUnit@ fac)
{
	if ((fac is null) || OwnsFactory(fac))
		return;
	gMixOwned.insertLast(fac.id);
	AiLog(Factory::T() + "apex: mix claims " + fac.circuitDef.GetName()
		+ " #" + fac.id + " (old production rules off for this line)");
}

void ReleaseFactory(Id id)
{
	for (uint i = 0; i < gMixOwned.length(); ++i) {
		if (gMixOwned[i] == id) {
			gMixOwned.removeAt(i);
			return;
		}
	}
}

void InitMix()
{
	if (gMix.length() > 0)
		return;
	gMix.insertLast(MixTarget(Unit::Role::RAIDER.type,  0.30f));
	gMix.insertLast(MixTarget(Unit::Role::ASSAULT.type, 0.30f));
	gMix.insertLast(MixTarget(Unit::Role::SKIRM.type,   0.15f));
	gMix.insertLast(MixTarget(Unit::Role::RIOT.type,    0.10f));
	gMix.insertLast(MixTarget(Unit::Role::ARTY.type,    0.08f));
	gMix.insertLast(MixTarget(Unit::Role::AA.type,      0.07f));
}

// What we currently HOLD of a role, in metal. CCircuitDef::count is our own
// count, which is what NanoCap and the rez-bot floor already rely on.
float HeldOfRole(CCircuitUnit@ fac, Type role)
{
	CCircuitDef@ d = aiFactoryMgr.GetRoleDef(fac.circuitDef, role);
	if (d is null)
		return -1.f;             // this factory cannot make the role at all
	return float(d.count) * d.costM;
}

// The role furthest below its target share, among those this factory can build.
CCircuitDef@ NextForMix(CCircuitUnit@ fac)
{
	InitMix();
	float total = 0.f;
	array<float> held(gMix.length(), -1.f);
	for (uint i = 0; i < gMix.length(); ++i) {
		held[i] = HeldOfRole(fac, gMix[i].role);
		if (held[i] > 0.f)
			total += held[i];
	}
	if (total < 1.f)
		total = 1.f;             // opening: every share reads as zero, so the
		                         // first pick is simply the highest target

	CCircuitDef@ best = null;
	float worstGap = 0.f;
	for (uint i = 0; i < gMix.length(); ++i) {
		if (held[i] < 0.f)
			continue;            // not buildable here
		const float have = held[i] / total;
		const float gap = gMix[i].share - have;
		if (gap <= worstGap)
			continue;
		CCircuitDef@ d = aiFactoryMgr.GetRoleDef(fac.circuitDef, gMix[i].role);
		if ((d is null) || !d.IsAvailable(ai.frame))
			continue;
		worstGap = gap;
		@best = d;
	}
	return best;
}

// The factory-side entry point. Returns a recruit task, or null to let the
// existing pipeline answer.
// BUILD POWER IS NOT PART OF THE ARMY MIX.
//
// It was a share (0.15) alongside the combat roles, and it never won: combat
// shares start at zero and are constantly emptied by losses, so the largest gap
// is ALWAYS a combat role and the constructor is never chosen. Measured in a 1v1
// against hard: our advanced constructors stayed at 1 from minute 14 to the end
// while hard reached 15 by minute 16, and the old constructor rules had been
// switched off for the claimed line. That is how a mix that looks reasonable
// starves the thing that builds the economy.
//
// So it is a FLOOR, checked before the ratio: below what the income justifies,
// the next unit off this line is a constructor.
IUnitTask@ BuildPowerFirst(CCircuitUnit@ fac)
{
	CCircuitDef@ con = aiFactoryMgr.GetRoleDef(fac.circuitDef, Unit::Role::BUILDER.type);
	if ((con is null) || !con.IsAvailable(ai.frame))
		return null;
	// The same shape as Builder::NeedsAdvCon: one per this much metal income.
	const float per = ai.GetTunable("apex_mix_con_income", 30.f);
	const int want = 1 + int(aiEconomyMgr.metal.income / per);
	if (con.count >= want)
		return null;
	return aiFactoryMgr.Enqueue(TaskS::Recruit(
			Task::RecruitType::BUILDPOWER, Task::Priority::HIGH,
			con, fac.GetPos(ai.frame), 0.f));
}

IUnitTask@ MixTask(CCircuitUnit@ fac)
{
	if (ai.GetTunable("apex_mix", 1.f) <= 0.f)
		return null;
	IUnitTask@ bp = BuildPowerFirst(fac);
	if (bp !is null) {
		ClaimFactory(fac);
		return bp;
	}
	CCircuitDef@ want = NextForMix(fac);
	if (want is null)
		return null;

	IUnitTask@ rec = aiFactoryMgr.Enqueue(TaskS::Recruit(
			Task::RecruitType::FIREPOWER, Task::Priority::NORMAL,
			want, fac.GetPos(ai.frame), 0.f));
	if (rec is null)
		return null;

	ClaimFactory(fac);
	++gMixPicks;
	if (ai.frame >= gNextMixLog) {
		gNextMixLog = ai.frame + 60 * SECOND;
		AiLog(Factory::T() + "apex: mix -> " + want.GetName()
			+ " picks=" + gMixPicks);
	}
	return rec;
}

}  // namespace Brain
