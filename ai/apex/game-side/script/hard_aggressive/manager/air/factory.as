namespace Air {

CCircuitDef@ NextAirDef(bool advanced)
{
	CCircuitDef@ bomber  = advanced ? gBomber  : gBomber1;
	CCircuitDef@ fighter = advanced ? gFighter : gFighter1;
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
