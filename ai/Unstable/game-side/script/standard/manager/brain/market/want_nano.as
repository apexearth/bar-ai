namespace Market {
int gNextNanoWantLog = 0;
// Which demand sited the want (w.spotId). Execute honours the first three
// instead of re-deriving the ground, so a line-bought turret stands at the line.
const int NS_FORT = 1;
const int NS_ARMY = 2;
const int NS_LINE = 3;
const int NS_SINK = 4;
const int NS_FARM = 5;
const int NS_FLOOR = 6;

// BARb's floor (apexearth 2026-09-11, twice: "we have to do at least that
// good"; "factories with insufficient supporting nanos should have nanos as
// very important placement by them"): every standing factory keeps 2 / 4 / 9
// caretakers in reach for a T1 / T2 / T3 plant, as stock counts them. Returns
// the worst shortfall and that factory; live nano requests in reach count.
int FactoryNanoShort(AIFloat3& out at)
{
	int worst = 0;
	for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
		CCircuitUnit@ f = Factory::gFacUnits[fi];
		if (f is null)
			continue;
		const AIFloat3 fp = f.GetPos(ai.frame);
		if (!OnMap(fp))
			continue;
		const int tier = PlantTier(int(f.circuitDef.id));
		const int want = (tier >= 3) ? 9 : ((tier == 2) ? 4 : 2);
		// A plant whose ground is being raided does not hoist its turret
		// past the draw: the floor sent a nano to the same raided row 104
		// times in one game, every frame killed (watched). Priced like any
		// other want there, it waits for the gun the loss field is buying.
		if (LossNearM(fp, NanoMaxReach()) > 200.f)
			continue;
		int have = 0;
		NanoNear(fp, NanoMaxReach());
		for (uint q = 0; q < gNanoGrid.hit.length(); ++q) {
			const uint i = uint(gNanoGrid.hit[q]);
			const float r = (i < gOwnNanoReach.length()) ? gOwnNanoReach[i] : 400.f;
			if (fp.distance2D(gOwnNanoPos[i]) < 0.9f * r)
				++have;
		}
		for (uint li = 0; li < Requests::gLive.length(); ++li) {
			IUnitTask@ lt = Requests::gLive[li];
			if ((lt is null) || lt.IsDead() || (lt.buildDef is null)
				|| (lt.GetBuildType() != Task::BuildType::NANO))
				continue;
			const AIFloat3 lp = lt.GetBuildPos();
			if (OnMap(lp) && (fp.distance2D(lp)
					< 0.9f * Catalog::gBuildDist[int(lt.buildDef.id)]))
				++have;
		}
		if (want - have > worst) {
			worst = want - have;
			at = fp;
		}
	}
	return worst;
}

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
	// The free flow and the two shares are the same question for every site --
	// they were re-asked once per live request.
	const float snFree = FreeMetalFlow()
			* ai.GetTunable("apex_nano_site_share", TUNE_NANO_SITE_SHARE);
	const float snH = ai.GetTunable("apex_payback_h", TUNE_PAYBACK_H);
	for (uint si = 0; si < Requests::gLive.length(); ++si) {
		IUnitTask@ st = Requests::gLive[si];
		if ((st is null) || (st.buildDef is null))
			continue;
		const int bd = int(st.buildDef.id);
		if (!NanoSinkWorthy(bd))
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
		float need = snFree - crew3 - ringEat;
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
			float life = Catalog::gCostM[bd]
					/ ((eat > oneNano) ? eat : oneNano);
			float sh = life / ((snH > 1.f) ? snH : 900.f);
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
	// ...NET OF THE TURRETS ALREADY IDLE: waste beside lathe with nothing to
	// lathe is a shortage of sites, not of turrets.
	{
		const float wasted = OverflowM() - IdleNanoLatheM();
		if (wasted > over)
			over = wasted;
	}
	// THE FORTIFICATION WANTS LATHE. apexearth 2026-08-30: "T1 cons around
	// that frontline make the nano turrets. These are to help build faster,
	// and to heal up these defenses when they come under attack. The result
	// is a strong fortification that will survive."
	//
	// A nano was priced purely as build power, so the repair half of that was
	// worth nothing anywhere in this AI. A lathe standing in the guns returns
	// the tower metal it keeps alive, and the ground where that pays is the
	// ground that has already been eating towers -- Military::FenceLostNear is
	// a freshness-weighted count of our OWN guns lost near a point, so the
	// demand appears where defences actually die and decays on its own when
	// they stop dying. No count, no timer: a quiet wall prices zero.
	float fortNeed = 0.f;
	AIFloat3 fortPos;
	{
		// The reach this builder could actually stand a lathe with.
		float nanoReach = 0.f;
		const array<int>@ nb = Catalog::BuildsOf(int(unit.circuitDef.id));
		for (uint ni = 0; ni < nb.length(); ++ni) {
			const int nd = nb[ni];
			if (Catalog::gAvailable[nd] && IsLatheDef(nd)
				&& (Catalog::gBuildDist[nd] > nanoReach))
				nanoReach = Catalog::gBuildDist[nd];
		}
		AIFloat3 fwd;
		if ((nanoReach > 1.f) && Military::ForwardMostFence(fwd) && OnMap(fwd)) {
			const float fenceM = Military::FenceGunMetalNear(fwd, nanoReach);
			const float lost = Military::FenceLostNear(fwd, nanoReach);
			const float h = ai.GetTunable("apex_exposed_loss_s",
					TUNE_EXPOSED_LOSS_S);
			if ((fenceM > 1.f) && (lost > 0.f) && (h > 1.f)) {
				// Metal per second of gun that this ground has been losing --
				// the rate a lathe here is answering. Same currency as every
				// other term above (FreeMetalFlow), so it competes rather
				// than overrides.
				fortNeed = fenceM * lost / h;
				fortPos = fwd;
			}
		}
		// THE HELD LINE WANTS ITS LATHE BEFORE IT STARTS DYING (apexearth
		// 2026-09-02: "make nano turrets up there. If we're fighting enemies,
		// we can fight within range of our nano turrets and then get healed
		// while we fight"). Worth the gun metal standing on the line times
		// the hazard there -- what a lathe keeps alive per second -- while no
		// lathe stands or is ordered within reach of it.
		AIFloat3 fl;
		float flGuns = 0.f;
		if ((nanoReach > 1.f) && WallSupportSlot(nanoReach, fl, flGuns)) {
			const float lineNano = flGuns * HazardWith(fl, CoverAt(fl));
			if (lineNano > fortNeed) {
				fortNeed = lineNano;
				fortPos = fl;
			}
		}
	}
	if (fortNeed > over)
		over = fortNeed;
	// The floor bids the turret's whole drain at the short factory; Decide
	// hoists a floor-sourced want ahead of the draw.
	AIFloat3 floorPos;
	const int floorShort = FactoryNanoShort(floorPos);
	const float floorNeed = ((floorShort > 0) && OnMap(floorPos)) ? 200.f * (7.f / 80.f) : 0.f;
	if (floorNeed > over)
		over = floorNeed;
	// What the nano want saw, whether or not it bids (sampled 10 s): the
	// line's free flow against what it eats is the whole "not supporting
	// the factory" question.
	if (ai.frame >= gNextNanoWantLog) {
		gNextNanoWantLog = ai.frame + 10 * SECOND;
		AIFloat3 lp0;
		float lathe0 = 0.f;
		AnyLineSite(lp0, lathe0);
		AiLog(Factory::T() + "apex: nanowant " + unit.circuitDef.GetName()
			+ " feed=" + formatFloat(FreeMetalFlow(), "", 0, 1)
			+ " line=" + formatFloat(lineNeed, "", 0, 1)
			+ " lathe=" + formatFloat(lathe0, "", 0, 1)
			+ " sink=" + formatFloat(sinkNeed, "", 0, 1)
			+ " army=" + formatFloat(armyNeed, "", 0, 1)
			+ " waste=" + formatFloat(OverflowM(), "", 0, 1)
			+ " idle=" + formatFloat(IdleNanoLatheM(), "", 0, 1)
			+ " fort=" + formatFloat(fortNeed, "", 0, 1)
			+ " floor=" + floorShort
			+ " over=" + formatFloat(over, "", 0, 1)
			+ " bank=" + int(aiEconomyMgr.metal.current) + "/" + int(aiEconomyMgr.metal.storage));
	}
	if (over <= 0.5f)
		return w;
	// The turret STANDS where the demand is. A nano bought to serve a line was
	// sited at the eco farm, which is behind the anchor and outside assist
	// reach -- so it could never touch the line that priced it.
	AIFloat3 site = EcoSiteFor(unit);
	int src = NS_FARM;
	// The line takes the tie: a factory converts lathe into army for the rest
	// of the game where a frame stops paying at completion, and the >= the
	// other way sent every overflow-bought turret to a sink. An unset sinkPos
	// is (-1,-1), so the zero-vs-zero case no longer reads as an on-map sink.
	// The fortification takes the site whenever it priced the demand: a lathe
	// bought to hold the wall is worth nothing at the eco farm.
	if ((floorNeed > 0.f) && OnMap(floorPos)) {
		site = floorPos;
		src = NS_FLOOR;
	} else if ((fortNeed >= over) && OnMap(fortPos)) {
		site = fortPos;
		src = NS_FORT;
	} else if ((armyNeed >= over) && OnMap(armyPos)) {
		site = armyPos;
		src = NS_ARMY;
	} else if (haveLine && (lineNeed >= sinkNeed)) {
		site = linePos;
		src = NS_LINE;
	} else if ((sinkNeed > 0.f) && OnMap(sinkPos)) {
		site = sinkPos;
		src = NS_SINK;
	} else if (haveLine) {
		site = linePos;
		src = NS_LINE;
	}
	const int uid = int(unit.circuitDef.id);
	const array<int>@ builds = Catalog::BuildsOf(uid);
	for (uint i = 0; i < builds.length(); ++i) {
		const int d = builds[i];
		if (!Catalog::gAvailable[d] || Catalog::gMobile[d] || Catalog::gFloater[d] || Catalog::gSub[d])
			continue;
		if ((Catalog::gBuildPower[d] <= 0.f) || (Catalog::gBuildsList[d].length() > 0))
			continue;
		const float drain = Catalog::gBuildPower[d] * (7.f / 80.f);
		float gainN = (over < drain) ? over : drain;
		// A lathe pulls energy as well as metal, so it is worth the share of
		// its ask the energy economy can feed: overflow caused by an e-stall
		// bought the nanos that deepened it (apexearth, watching: "even our
		// nano turrets... are stalling because we lack energy").
		{
			const float askE = Catalog::gBuildPower[d] * LineEnergyDensity();
			if (askE > 1.f) {
				const float spare = aiEconomyMgr.energy.income + EMakeInFlight()
						- aiEconomyMgr.energy.pull;
				gainN *= (spare <= 0.f) ? 0.f : ((spare < askE) ? (spare / askE) : 1.f);
			}
		}
		Want c;
		ValueOf(d, gainN, WalkSecTo(unit, site),
				Catalog::gBuildPower[uid], c);
		if (c.value > w.value) {
			w = c;
			w.kind = WK_NANO;
			@w.def = Catalog::Def(d);
			w.pos = site;
			w.spotId = src;
		}
	}
	return w;
}


}  // namespace Market
