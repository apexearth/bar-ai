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
	IUnitTask@ _r = MakeTaskInner(unit);
	Perf::Add("hk.maketask.builder", _mt);
	return _r;
}

// The rezzer chain keeps Decide's per-unit cadence: an idle rez bot
// otherwise re-runs the whole corpse/medic/salvage scan every idle update
// (flee is not rate-limited -- safety stays live). Spring unit ids cap at
// 32k, same sizing as Market::gLastDecideAt.
array<int> gRzDecideAt(32001, -30000);
// Per unit: when the held build's ground was last checked for danger.
array<int> gHotCheckAt(32001, -30000);
int gLetGo = 0;
int gNextLetGoLog = 0;

// A fallen commander outranks every other rez job -- flee alone comes
// first (a dead rez bot rescues nobody).
IUnitTask@ RezzerChain(CCircuitUnit@ unit)
{
	IUnitTask@ t = RezzerComRescue(unit);
	if (t !is null)
		return t;
	@t = RezzerMedic(unit);
	if (t !is null)
		return t;
	@t = RezzerFrontSalvage(unit);
	if (t !is null)
		return t;
	@t = RezzerEatCorpse(unit);
	if (t !is null)
		return t;
	@t = RezzerRezOrEat(unit);
	if (t !is null)
		return t;
	@t = RezzerRepairNearby(unit);
	if (t !is null)
		return t;
	return RezzerIdle(unit);
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
		if ((int(unit.id) >= 0) && (int(unit.id) < int(gRzDecideAt.length()))) {
			if (ai.frame - gRzDecideAt[int(unit.id)] < 2 * SECOND)
				return null;
			gRzDecideAt[int(unit.id)] = ai.frame;
		}
		const double _tRz = Perf::T0();
		IUnitTask@ rz = RezzerChain(unit);
		Perf::Add("bld.rezzer", _tRz);
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
				&& SiteHot(at))
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
	// and the constructor idles. The wall time of the whole election feeds
	// the frame budget (Market::ELEC_FRAME_US) from out here, so every
	// return path inside counts without instrumenting each one.
	const double _tD = ai.ClockUs();
	IUnitTask@ dec = Brain::Decide(unit);
	Market::ElecSpend(ai.ClockUs() - _tD);
	return dec;
}

}  // namespace Builder
