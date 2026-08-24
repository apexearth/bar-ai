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
	const float lineNeed = UnservedLineSpend();
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
			if (need > sinkNeed)
				sinkNeed = need;
		}
	}
	float over = (sinkNeed > lineNeed) ? sinkNeed : lineNeed;
	if (over <= 0.5f)
		return w;
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
			w.pos = EcoSiteFor(unit);
		}
	}
	return w;
}


}  // namespace Market
