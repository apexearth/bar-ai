namespace Builder {

// THE DEDICATED CREWS' OWN LADDERS (apexearth 2026-08-21). An ENERGY or
// METAL constructor works its domain before anything else can claim it --
// continuity is the point: energy used to advance only in the gaps between
// mex offers and assists, which read as "we simply expand our energy
// slowly, always". Sensors and local defence stay allowed (his spec), and
// when a domain genuinely has nothing to build the holder falls through to
// the shared ladder rather than idling -- dedication is a floor, not a
// fence, and it never gates what OTHER constructors may build.

IUnitTask@ EnergyCrewTask(CCircuitUnit@ unit)
{
	IUnitTask@ t = HoldWorkInProgress(unit, false);
	if (t !is null)
		return t;
	// SPILLING ENERGY FLIPS THE LADDER: a dedicated energy con building yet
	// another generator while the grid overflows is the inversion apexearth
	// keeps watching ("crazy overflowing energy and not making nearly enough
	// converters... everyone feels energy is so crazy important") -- while
	// EnergyWasting(), converters ARE the energy crew's job, and only then
	// the reactor chain. In balance-or-short states the reactor stays first.
	if (EnergyWasting()) {
		@t = EnergyConverter(unit);
		if (t !is null)
			return t;
	}
	@t = EcoFusion(unit);
	if (t !is null)
		return t;
	@t = AlwaysEco(unit);
	if (t !is null)
		return t;
	@t = HomeEnergy(unit);
	if (t !is null)
		return t;
	@t = EnergyConverter(unit);
	if (t !is null)
		return t;
	// No defence/radar exceptions -- apexearth rescinded them ("I think that
	// was a mistake to ask for"): the crews do their domain, full stop.
	return null;
}

IUnitTask@ MetalCrewTask(CCircuitUnit@ unit)
{
	IUnitTask@ t = HoldWorkInProgress(unit, false);
	if (t !is null)
		return t;
	// CONVERTERS ARE METAL WORK (apexearth: "some portion of that metal crew
	// to stay home and make converters"). While energy spills, a converter
	// pays 1 m/s per metal invested -- better than any walk to a far spot --
	// so the crew converts at home before it travels. EnergyConverter
	// self-gates on the spill, so this rung is silent on a tight grid.
	if (EnergyWasting()) {
		@t = EnergyConverter(unit);
		if (t !is null)
			return t;
	}
	const AIFloat3 me = unit.GetPos(ai.frame);
	const int spot = aiEconomyMgr.FindOpenMexSpot(unit, me,
			ai.GetTunable("apex_mex_threat", TUNE_MEX_THREAT));
	if (spot >= 0) {
		const AIFloat3 sp = aiEconomyMgr.GetMexSpotPos(spot);
		if (OnMap(sp)) {
			float heat = ThreatFor(unit, sp);
			heat = MexHeat(sp, heat);
			if (heat <= CON_THREAT_VETO) {
				IUnitTask@ dig = aiEconomyMgr.EnqueueMexAt(unit, spot);
				if (dig !is null)
					return dig;
			}
		}
	}
	// UPGRADES ARE THE CREW'S OWN JOB, NOT THE AUCTION'S. Routed through
	// the shared ladder they died in the draw (measured: mexup mean chance
	// 0.0%, score 0.002 -- "only our core mexes get the upgrade"), and the
	// one-slot MexUpLane cannot carry a map. A metal-crew adv con upgrades
	// the nearest un-upgraded mex directly; the crew ratio (1 per
	// apex_dedicate_per_adv) bounds total dedication -- the fleet share
	// apexearth asked for, instead of the auction's starvation.
	if (IsAdvConDef(unit)) {
		Brain::Want@ up = Brain::MexUpgradeWant(unit);
		if ((up !is null) && (up.def !is null)
			&& unit.circuitDef.CanBuild(up.def)
			&& (ThreatFor(unit, up.pos) <= CON_THREAT_VETO))
		{
			IUnitTask@ dig2 = aiBuilderMgr.EnqueueMexUp(up.pos, up.def);
			if (dig2 !is null)
				return dig2;
		}
	}
	return null;
}

}  // namespace Builder
