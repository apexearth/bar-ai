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
	// The allowed exceptions: a sentry on a bare extractor underfoot costs
	// no walk and protects the ground the crew works on.
	return CommanderMexGuard(unit, false, false, true);
}

IUnitTask@ MetalCrewTask(CCircuitUnit@ unit)
{
	IUnitTask@ t = HoldWorkInProgress(unit, false);
	if (t !is null)
		return t;
	// The near-guard exception first: the mex just finished gets its sentry
	// before this con walks to the next spot.
	@t = CommanderMexGuard(unit, false, false, true);
	if (t !is null)
		return t;
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
	// No open spot: guard a bare extractor anywhere in reach.
	return CommanderMexGuard(unit, false);
}

}  // namespace Builder
