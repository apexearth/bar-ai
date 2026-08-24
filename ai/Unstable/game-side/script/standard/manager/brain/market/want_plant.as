namespace Market {
// Geothermal: same shape as mex -- a def that must stand on its own spot.
Want@ ProposeGeo(CCircuitUnit@ unit)
{
	Want w;
	const int uid = int(unit.circuitDef.id);
	int geoId = -1;
	const array<int>@ builds = Catalog::BuildsOf(uid);
	for (uint i = 0; i < builds.length(); ++i) {
		const int d = builds[i];
		if (!Catalog::gAvailable[d] || !Catalog::gNeedGeo[d])
			continue;
		if ((geoId < 0) || (Catalog::gMakeE[d] > Catalog::gMakeE[geoId]))
			geoId = d;
	}
	if (geoId < 0)
		return w;
	const AIFloat3 here = unit.GetPos(ai.frame);
	const int spot = aiEconomyMgr.FindOpenGeoSpot(unit, here);
	if (spot < 0)
		return w;
	const AIFloat3 pos = aiEconomyMgr.GetGeoSpotPos(spot);
	if (EcoFar(pos) || (Front::FoeKnown() && Builder::PastFront(pos)))
		return w;
	const float speed = Catalog::gSpeed[uid];
	const float walkSec = (speed > 1.f) ? (here.distance2D(pos) / speed) : 60.f;
	const float gain = Catalog::gMakeE[geoId]
			* EPriceAt(Catalog::BuildSecondsAt(geoId, EffBP(Catalog::gBuildPower[uid])));
	w.kind = WK_GEO;
	@w.def = Catalog::Def(geoId);
	w.pos = pos;
	w.spotId = spot;
	ValueOf(geoId, gain, walkSec, Catalog::gBuildPower[uid], w);
	return w;
}

// A plant's future output discounts by its own LATENCY (temporal
// consistency, same law as EPriceAt): the pipeline delivers its first con
// at lab-build + con-build seconds, and value that far out is worth
// horizon/(horizon+latency) of value now. This is what makes the natural
// opening (mex, mex, solar, THEN lab) emerge without a scripted order --
// at frame zero the lab's 70s latency halves it below the immediate mex.
// Seconds from deciding on a plant to its first constructor existing: the
// plant itself, then the cheapest builder it makes. Both the latency discount
// and the survival discount are built from this one number.
float PipeLatencySec(int plantId, float askerBP)
{
	const float labSec = Catalog::BuildSecondsAt(plantId, EffBP(askerBP));
	float conSec = 45.f;
	const array<int>@ prods = Catalog::gBuildsList[plantId];
	for (uint p = 0; p < prods.length(); ++p) {
		if (Catalog::gMobile[prods[p]] && Catalog::gBuilder[prods[p]]) {
			const float cs = Catalog::BuildSecondsAt(prods[p],
					Catalog::gBuildPower[plantId]);
			if (cs < conSec)
				conSec = cs;
		}
	}
	return labSec + conSec;
}

float PipeLatencyMult(int plantId, float askerBP)
{
	const float H = ai.GetTunable("apex_pipe_latency_h", TUNE_PIPE_LATENCY_H);
	const float h = (H > 1.f) ? H : 60.f;
	return h / (h + PipeLatencySec(plantId, askerBP));
}

// MODEL: a plant's return is its constructor pipeline -- each con carries
// roughly one open spot's stream while expansion ground remains, plus the
// overflow the pipeline would capture (arithmetic, see OverflowM). One named
// discount (apex_plant_pipe) prices the pipeline's losses; no spot ground
// left means no plant value at all.
Want@ ProposePlant(CCircuitUnit@ unit)
{
	Want w;
	// The MARGINAL plant: worth anything only if income supports another
	// line (~50 m/s each, apexearth's number). Not a cap -- a price of zero
	// past what the economy can feed, of any lab type.
	TrackIncome();
	const float per = ai.GetTunable("apex_plant_income_per", TUNE_PLANT_INCOME_PER);
	const float structInc = (gIncEma > 0.f) ? gIncEma : aiEconomyMgr.metal.income;
	const int supported = 1 + int(structInc / ((per > 1.f) ? per : 50.f));
	if (Factory::gFactoryCount
			+ Requests::LiveCountOf(int(Task::BuildType::FACTORY)) >= supported)
		return w;
	const int uid = int(unit.circuitDef.id);
	const array<int>@ builds = Catalog::BuildsOf(uid);
	// Expansion stream while ground remains, PLUS the production appetite a
	// new line would serve -- a lost lab re-prices itself from the army gap
	// even when every spot is claimed.
	const float fillS0 = ai.GetTunable("apex_army_fill_s", TUNE_ARMY_FILL_S);
	const float aGap = ArmyTarget() - ArmyValue();
	const float prodTerm = (aGap > 0.f)
			? (aGap / ((fillS0 > 1.f) ? fillS0 : 180.f))
				/ float(1 + Factory::gFactoryCount)
			: 0.f;
	const float gain = ((gMexOpen ? SpotM() : 0.f) + BPGap() + prodTerm)
			* ai.GetTunable("apex_plant_pipe", TUNE_PLANT_PIPE)
			* Utilization();
	if (gain <= 0.05f)
		return w;
	for (uint i = 0; i < builds.length(); ++i) {
		const int d = builds[i];
		if (!Catalog::gAvailable[d] || Catalog::gMobile[d] || Catalog::gFloater[d] || Catalog::gSub[d])
			continue;   // floaters need water; land-base v1 (see armfmkr churn)
		if (Catalog::gBuildsList[d].length() == 0)
			continue;   // not a factory
		// A plant that cannot produce a mobile builder buys no expansion --
		// and the builder must be able to EXIST here: a shipyard's ship-cons
		// have no connected area at a land base (measured: armsy chosen on
		// Comet Catcher, a game-long placement failure).
		// The plant inherits its best product's MOBILITY: an air lab's cons
		// fly, which is what lets it compete once the base packs.
		const AIFloat3 here = unit.GetPos(ai.frame);
		float bestMob = 0.f;
		const array<int>@ prods = Catalog::gBuildsList[d];
		for (uint p = 0; p < prods.length(); ++p) {
			const int pd = prods[p];
			if (Catalog::gMobile[pd] && Catalog::gBuilder[pd]
				&& ai.CanDefReach(Catalog::Def(pd), here, here))
			{
				const float m = MobilityMult(pd);
				if (m > bestMob)
					bestMob = m;
			}
		}
		if (bestMob <= 0.f)
			continue;
		// A DUPLICATE line is only parallel capacity: value divides per
		// copy owned (watched: T1 air labs multiplying). And a plant whose
		// cons reach the extraction ceiling outranks a T1 copy -- "we want
		// multiple T2 air labs, not T1 air labs."
		// ...and a "copy" is any plant of the SAME REACH from the same
		// ground/air class, not the same def -- a T2 bot lab and a T2
		// vehicle lab are parallel capacity of one tier (watched: both
		// bought when one was barely affordable).
		int reachKin = Catalog::Def(d).count;
		{
			float myReach = 0.f;
			bool myAir = false;
			for (uint pr0 = 0; pr0 < prods.length(); ++pr0) {
				if (!Catalog::gMobile[prods[pr0]] || !Catalog::gBuilder[prods[pr0]])
					continue;
				if (Catalog::gFlyer[prods[pr0]])
					myAir = true;
				const array<int>@ pr0b = Catalog::gBuildsList[prods[pr0]];
				for (uint rz = 0; rz < pr0b.length(); ++rz) {
					if (Catalog::gExtractsM[pr0b[rz]] > myReach)
						myReach = Catalog::gExtractsM[pr0b[rz]];
				}
			}
			for (uint kd2 = 1; kd2 < gOwnCount.length(); ++kd2) {
				if ((gOwnCount[kd2] <= 0) || (int(kd2) == d)
					|| Catalog::gMobile[int(kd2)]
					|| (Catalog::gBuildsList[int(kd2)].length() == 0))
					continue;
				const array<int>@ kb2 = Catalog::gBuildsList[int(kd2)];
				float kReach = 0.f;
				bool kAir = false;
				for (uint kq2 = 0; kq2 < kb2.length(); ++kq2) {
					if (!Catalog::gMobile[kb2[kq2]] || !Catalog::gBuilder[kb2[kq2]])
						continue;
					if (Catalog::gFlyer[kb2[kq2]])
						kAir = true;
					const array<int>@ kpb2 = Catalog::gBuildsList[kb2[kq2]];
					for (uint kz2 = 0; kz2 < kpb2.length(); ++kz2) {
						if (Catalog::gExtractsM[kpb2[kz2]] > kReach)
							kReach = Catalog::gExtractsM[kpb2[kz2]];
					}
				}
				if ((kReach >= myReach) && (kAir == myAir))
					reachKin += gOwnCount[kd2];
			}
		}
		float dupGain = gain / float(1 + reachKin);
		{
			float prodReach = 0.f;
			for (uint pr = 0; pr < prods.length(); ++pr) {
				if (!Catalog::gMobile[prods[pr]] || !Catalog::gBuilder[prods[pr]])
					continue;
				const array<int>@ prb = Catalog::gBuildsList[prods[pr]];
				for (uint rr = 0; rr < prb.length(); ++rr) {
					if (Catalog::gExtractsM[prb[rr]] > prodReach)
						prodReach = Catalog::gExtractsM[prb[rr]];
				}
			}
			const float ceilX = BestExtract();
			if (ceilX > 0.f)
				dupGain *= 1.f + prodReach / ceilX;
		}
		// The quiet rear's expansion is AIR (apexearth: "the goal should be
		// air cons... stop making ground labs"): flying cons don't jam the
		// packed farm, and its army era is gantry-only. Ground plants stop
		// pricing once one stands; air keeps its full value.
		if (EcoQuiet() && (Factory::gFactoryCount >= 1)) {
			bool airLab = false;
			for (uint p4 = 0; p4 < prods.length(); ++p4) {
				if (Catalog::gMobile[prods[p4]] && Catalog::gBuilder[prods[p4]]
					&& Catalog::gFlyer[prods[p4]]) {
					airLab = true;
					break;
				}
			}
			if (!airLab)
				continue;
		}
		Want c;
		ValueOf(d, dupGain * bestMob * PipeLatencyMult(d, Catalog::gBuildPower[uid]),
				0.f, Catalog::gBuildPower[uid], c);
		if (c.value > w.value) {
			w = c;
			w.kind = WK_PLANT;
			@w.def = Catalog::Def(d);
			// Plants stand at the base anchor -- the middle of what we own.
			w.pos = InteriorSite(EcoSiteFor(unit));
		}
	}
	return w;
}


}  // namespace Market
