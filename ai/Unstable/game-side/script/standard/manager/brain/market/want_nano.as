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
	AIFloat3 sinkPos = AIFloat3(-1.f, 0.f, -1.f);
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
		// The sink's own metal density prices what lathe here can absorb:
		// an AFUS runs 0.11 m per buildtime-unit where the 7/80 flat said
		// 0.0875 for everything.
		const float sdens = (Catalog::gBuildTime[bd] > 1.f)
				? (Catalog::gCostM[bd] / Catalog::gBuildTime[bd])
				: (7.f / 80.f);
		const float ringEat = RingBPAt(sp3) * sdens;
		// ONE LAW FOR EVERY SITE: demand is what the economy can feed the
		// site, less the lathe already standing on it. A binary "fewer than
		// three" priced a frame at full free flow and counted its crew as
		// demand rather than as supply, in a currency no factory could
		// match -- so build sites took the turrets a queued, nano-less lab
		// was asking for (apexearth: "we rarely make them around factories
		// that are building units").
		float crew3 = 0.f;
		array<CCircuitUnit@>@ cu3 = st.GetUnits();
		if (cu3 !is null) {
			for (uint ci = 0; ci < cu3.length(); ++ci) {
				if ((cu3[ci] !is null) && (cu3[ci].circuitDef !is null))
					crew3 += Catalog::gBuildPower[int(cu3[ci].circuitDef.id)]
							* sdens;
			}
		}
		// WHAT THE SITE CAN BE FED, NOT A NUMBER. This clamped demand at a
		// bare 35 metal/s, and one nano absorbs NANO_ABSORB (17.5) -- so TWO
		// turrets zeroed the demand at any income, forever. Measured in a
		// watched game: five T2 bot labs with at most four nanos between them
		// and a gantry on five, against an enemy gantry running 38 (apexearth:
		// "they're going to kick our ass"). Spare metal flow is the honest
		// bound and it already scales with the economy and the bank, so the
		// turret count rises with income on its own and needs no ceiling.
		const float free3 = FreeMetalFlow()
				* ai.GetTunable("apex_nano_site_share", TUNE_NANO_SITE_SHARE);
		float need = free3 - crew3 - ringEat;
		// A FRAME'S STREAM DIES AT COMPLETION where a line's runs forever, so
		// the sink's need is scaled by its remaining life over the payback
		// horizon: cost over what the crew already eats. A bare afus reads
		// minutes of life and takes its first turrets (his ruling); a crewed
		// frame reads seconds and stops outbidding every working lab with the
		// whole feed -- measured 2074 sink sitings against 2 line sitings,
		// mean priced need 389 m/s, while 46% of income overflowed.
		{
			const float eat = crew3 + ringEat;
			const float oneNano = 200.f * sdens;
			const float H = ai.GetTunable("apex_payback_h", TUNE_PAYBACK_H);
			float life = Catalog::gCostM[bd]
					/ ((eat > oneNano) ? eat : oneNano);
			float sh = life / ((H > 1.f) ? H : 900.f);
			if (sh < 1.f)
				need *= sh;
		}
		if (need > sinkNeed) {
			sinkNeed = need;
			sinkPos = sp3;
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
				armyNeed = wantRate - lathe;
				if (armyNeed < 0.f)
					armyNeed = 0.f;
			}
		}
	}
	float over = (sinkNeed > lineNeed) ? sinkNeed : lineNeed;
	if (armyNeed > over)
		over = armyNeed;
	// METAL WE FAIL TO SPEND IS NANO DEMAND IN ITS OWN RIGHT (apexearth
	// 2026-08-27: "We didn't have nearly enough nano turrets to spend the
	// amount of metal we were making... we'd need 20x the amount"). Overflow
	// is the measured failure to spend, so the lathe fleet grows until the
	// waste stops -- no count, no cooldown, and it reads zero the moment the
	// economy is actually being spent. Sited by the fallback chain below.
	{
		const float wasted = OverflowM();
		if (wasted > over)
			over = wasted;
	}
	if (over <= 0.5f)
		return w;
	// The turret STANDS where the demand is. A nano bought to serve a line was
	// sited at the eco farm, which is behind the anchor and outside assist
	// reach -- so it could never touch the line that priced it.
	AIFloat3 site = EcoSiteFor(unit);
	// The line takes the tie: a factory converts lathe into army for the rest
	// of the game where a frame stops paying at completion, and the >= the
	// other way sent every overflow-bought turret to a sink. An unset sinkPos
	// is (-1,-1), so the zero-vs-zero case no longer reads as an on-map sink.
	if ((armyNeed >= over) && OnMap(armyPos))
		site = armyPos;
	else if (haveLine && (lineNeed >= sinkNeed))
		site = linePos;
	else if ((sinkNeed > 0.f) && OnMap(sinkPos))
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
		ValueOf(d, (over < drain) ? over : drain, WalkSecTo(unit, site),
				Catalog::gBuildPower[uid], c);
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
