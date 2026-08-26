namespace Market {
Want@ ProposeNano(CCircuitUnit@ unit)
{
	Want w;
	// Overflow is nano demand in its own right: a nano never walks, so it
	// absorbs overflow at face value even when the mobile fleet's paper
	// capacity looks sufficient. And a WORKING factory with no nano in
	// reach is full demand by itself -- the first lab must not build cons
	// unassisted while metal overflows (apexearth 2026-08-23, twice).
	// Raw overflow is NOT nano demand: overflow that persists after the
	// last nano proves nanos are not absorbing it (a full-metal stall
	// bought nanos at face value forever while the T2 lab priced at
	// nothing -- watched). BP demand sizes against income (BPGap) and
	// against lines with real work (UnservedLineSpend) -- the honest-
	// feedback law; overflow's buyers are converters, storage and tech.
	// NANOS SERVE FACTORIES AND BIG BUILDS ONLY (apexearth: "these nano
	// farms are just not working out... ditch that idea entirely. The
	// nanos are just for factories and expensive buildings like fusions
	// and afus"). Demand: working lines short of hands, or a fusion-tier
	// frame standing without its ring of ~3 (his read of stock's
	// caretaker logic). The income-headroom gap (BPGap) buys constructors
	// now, never farm turrets.
	AIFloat3 linePos;
	const float lineNeed = NeediestLine(linePos);
	bool haveLine = (lineNeed > 0.f) && OnMap(linePos);
	AIFloat3 sinkPos;
	float sinkNeed = 0.f;
	for (uint si = 0; si < Requests::gLive.length(); ++si) {
		IUnitTask@ st = Requests::gLive[si];
		if ((st is null) || (st.buildDef is null))
			continue;
		const int bd = int(st.buildDef.id);
		if ((Catalog::gCostM[bd] < ai.GetTunable("apex_nano_sink_m", TUNE_NANO_SINK_M))
			&& (Catalog::gMakeE[bd] < ai.GetTunable("apex_big_e", TUNE_BIG_E)))
			continue;
		const AIFloat3 sp3 = st.GetBuildPos();
		if (!OnMap(sp3))
			continue;
		int nAt = 0;
		for (uint ni = 0; ni < gOwnNanoPos.length(); ++ni) {
			if (sp3.distance2D(gOwnNanoPos[ni]) < 350.f)
				++nAt;
		}
		if (nAt < 3) {
			const float free3 = FreeMetalFlow();
			const float need = (free3 < 35.f) ? free3 : 35.f;
			if (need > sinkNeed) {
				sinkNeed = need;
				sinkPos = sp3;
			}
		}
	}
	// AN ARMY SHORTFALL IS NANO DEMAND (apexearth: "if we have need for more
	// army, one solution is adding a nano turret near the factory"). A line's
	// own spend can be fully served while the army we need is still short --
	// the answer then is not another line, it is more lathe on the one we have.
	// Bounded by what the economy can actually feed, so it never buys hands
	// that would stand idle.
	float armyNeed = 0.f;
	AIFloat3 armyPos;
	{
		const float gap = ArmyTarget() - ArmyValue();
		if (gap > 0.f) {
			const float fillS = ai.GetTunable("apex_army_fill_s", TUNE_ARMY_FILL_S);
			float wantRate = gap / ((fillS > 1.f) ? fillS : 180.f);
			const float free4 = FreeMetalFlow();
			if (wantRate > free4)
				wantRate = free4;
			// NET OFF THE LATHE ALREADY THERE. Every other demand term here
			// subtracts the hands already serving the site; this one did not, so
			// an army below target bought a turret however many were standing --
			// and the turret, being a structure, raised gAssetsM and so raised
			// ArmyTarget, while builders are excluded from ArmyValue and so can
			// never close the gap. Build power demanding build power.
			float lathe = 0.f;
			if ((wantRate > 0.f) && AnyLineSite(armyPos, lathe)) {
				armyNeed = wantRate - lathe * NANO_ABSORB;
				if (armyNeed < 0.f)
					armyNeed = 0.f;
			}
		}
	}
	float over = (sinkNeed > lineNeed) ? sinkNeed : lineNeed;
	if (armyNeed > over)
		over = armyNeed;
	if (over <= 0.5f)
		return w;
	// The turret STANDS where the demand is. A nano bought to serve a line was
	// sited at the eco farm, which is behind the anchor and outside assist
	// reach -- so it could never touch the line that priced it.
	AIFloat3 site = EcoSiteFor(unit);
	if ((armyNeed >= over) && OnMap(armyPos))
		site = armyPos;
	else if ((sinkNeed >= lineNeed) && OnMap(sinkPos))
		site = sinkPos;
	else if (haveLine)
		site = linePos;
	const int uid = int(unit.circuitDef.id);
	const array<int>@ builds = Catalog::BuildsOf(uid);
	for (uint i = 0; i < builds.length(); ++i) {
		const int d = builds[i];
		if (!Catalog::gAvailable[d] || Catalog::gMobile[d] || Catalog::gFloater[d] || Catalog::gSub[d])
			continue;
		if ((Catalog::gBuildPower[d] <= 0.f) || (Catalog::gBuildsList[d].length() > 0))
			continue;
		const float drain = Catalog::gBuildPower[d] * (7.f / 80.f);
		Want c;
		ValueOf(d, (over < drain) ? over : drain, 0.f, Catalog::gBuildPower[uid], c);
		if (c.value > w.value) {
			w = c;
			w.kind = WK_NANO;
			@w.def = Catalog::Def(d);
			w.pos = site;
		}
	}
	return w;
}


}  // namespace Market
