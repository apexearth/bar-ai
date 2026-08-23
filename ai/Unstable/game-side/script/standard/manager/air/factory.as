namespace Air {

CCircuitDef@ NextAirDef(bool advanced)
{
	CCircuitDef@ bomber  = advanced ? gBomber  : gBomber1;
	CCircuitDef@ fighter = advanced ? gFighter : gFighter1;
	// ONCE THE ADVANCED FIGHTER EXISTS, THE BASIC PLANT STOPS BUILDING THE OLD
	// ONE. Fighters are counted across both tiers, so a T1 plant kept topping the
	// escort up with 73-metal Falcons and the wing never became a T2 wing --
	// apexearth: "late game it needs to be T2 fighters, not T1." The plant still
	// builds its bomber and its constructor; only the obsolete fighter stops.
	// IsAvailable is true as soon as the def is unlocked, which can be well
	// before an advanced plant exists -- gating on it stopped T1 fighters while
	// nothing could yet build T2, i.e. no fighters at all. The honest test is
	// that replacements are actually ARRIVING.
	if (!advanced && (gFighter !is null) && (gFighter.count > 0))
		@fighter = null;
	// Progress is counted across BOTH tiers, so a basic plant stops producing
	// once the advanced one has finished the job and vice versa.
	const int nb = Bombers();
	const int nf = Fighters();
	// Grow the escort in step with the strike force rather than after it.
	// Ratio-based, not scaled-count-based, so it holds regardless of how big
	// ScaledBombers()/ScaledFighters() have grown -- AIR_BOMBERS/AIR_FIGHTERS
	// is the same proportion ScaledFighters()/ScaledBombers() scales from.
	if ((fighter !is null) && fighter.IsAvailable(ai.frame)
		&& (nf * AIR_BOMBERS < nb * AIR_FIGHTERS))
	{
		return fighter;
	}
	if ((bomber !is null) && bomber.IsAvailable(ai.frame) && (nb < ScaledBombers()))
		return bomber;
	if ((fighter !is null) && fighter.IsAvailable(ai.frame) && (nf < ScaledFighters()))
		return fighter;
	return null;
}

// Called from Factory::AiMakeTask. Null means "not my business", not "idle".
// Queue AIR_BATCH of the same aircraft and hand back the first. The rest sit in
// factoryTasks and the plant takes them itself as it finishes each one, with no
// round trip through the script.
IUnitTask@ EnqueueBatch(CCircuitUnit@ fac, CCircuitDef@ want)
{
	const AIFloat3 pos = fac.GetPos(ai.frame);
	IUnitTask@ first = null;
	for (int i = 0; i < AIR_BATCH; ++i) {
		IUnitTask@ rec = aiFactoryMgr.Enqueue(TaskS::Recruit(
				Task::RecruitType::FIREPOWER, Task::Priority::NOW,
				want, pos, 0.f));
		if (rec is null)
			break;
		if (first is null)
			@first = rec;
	}
	return first;
}

IUnitTask@ MakeFactoryTask(CCircuitUnit@ fac)
{
	if (!Armed() || gStrike)
		return null;
	ResolveDefs();

	// The BASIC plant's one job: an air constructor, because FactoryToBuild will
	// not ask for the advanced plant until HaveAirCon() is true.
	if ((gPlant1 !is null) && (fac.circuitDef.id == gPlant1.id)) {
		// The air constructor first -- it is the only route to the advanced
		// plant, and nothing else was ever going to build one.
		if (!HaveAirCon() && (gCon1 !is null) && gCon1.IsAvailable(ai.frame)) {
			IUnitTask@ con = aiFactoryMgr.Enqueue(TaskS::Recruit(
					Task::RecruitType::BUILDPOWER, Task::Priority::HIGH,
					gCon1, fac.GetPos(ai.frame), 0.f));
			if (con !is null) {
				gNextAirOrder = ai.frame + AIR_ORDER_SPACING;
				AiLog(Factory::T() + "apex: air assassin building " + gCon1.GetName()
					+ " to reach the advanced plant");
			}
			return con;
		}
		// Then the strike force itself, in the BASIC tier -- do not wait for the
		// advanced plant.
		CCircuitDef@ want1 = NextAirDef(false);
		if (want1 is null)
			return null;
		IUnitTask@ rec1 = EnqueueBatch(fac, want1);
		if (rec1 !is null)
			gNextAirOrder = ai.frame + AIR_ORDER_SPACING;
		return rec1;
	}

	if ((gPlant2 is null) || (fac.circuitDef.id != gPlant2.id))
		return null;

	// T2 AIR CONSTRUCTORS BEFORE THE WING. apexearth 2026-08-21: "an air
	// plant making T2 constructors... very useful late game and help us
	// build and expand really fast. By ~200 metal you should definitely be
	// having one." The advanced plant only ever recruited wing units; the
	// count scales with income (one per apex_aca_per_income), never a cap --
	// air cons have no ground hitbox, so the base-crowding argument that
	// bounds ground builders does not apply.
	if ((gCon2 !is null) && gCon2.IsAvailable(ai.frame)) {
		const int acaWant = int(aiEconomyMgr.metal.income
				/ ai.GetTunable("apex_aca_per_income", TUNE_ACA_PER_INCOME));
		if (gCon2.count < acaWant) {
			IUnitTask@ aca = aiFactoryMgr.Enqueue(TaskS::Recruit(
					Task::RecruitType::BUILDPOWER, Task::Priority::HIGH,
					gCon2, fac.GetPos(ai.frame), 0.f));
			if (aca !is null) {
				gNextAirOrder = ai.frame + AIR_ORDER_SPACING;
				AiLog(Factory::T() + "apex: advanced plant recruits "
					+ gCon2.GetName() + " (" + gCon2.count + "/" + acaWant + ")");
				return aca;
			}
		}
	}

	CCircuitDef@ want = NextAirDef(true);
	if (want is null)
		return null;
	IUnitTask@ rec = EnqueueBatch(fac, want);
	if (rec is null)
		return null;
	gNextAirOrder = ai.frame + AIR_ORDER_SPACING;
	return rec;
}

}  // namespace Air
