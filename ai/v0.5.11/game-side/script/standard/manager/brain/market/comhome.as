namespace Market {

// What the commander's pull at a lab makes in army, m/s: his build power x 7/80 x the energy feed, at most income
// plus a minute of bank. The effigy rush (comrush.as) weighs a job's worth against it.
float ComHomeLathe(CCircuitUnit@ u)
{
	const int uid = int(u.circuitDef.id);
	float eFeed = 1.f;
	const float eInc = Eco::EInc();
	const float ePull = Eco::EPull();
	if ((ePull > 1.f) && (eInc < ePull))
		eFeed = eInc / ePull;
	const float lathe = Catalog::gBuildPower[uid] * (7.f / 80.f) * eFeed;
	const float feed = Eco::MInc() + Eco::MCur() / 60.f;
	return (lathe < feed) ? lathe : feed;
}

}  // namespace Market
