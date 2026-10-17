namespace Requests {

// The live request covering this ground, if there is one. `radius` 0 is an
// exact point (SAME_SITE around it); `radius` > 0 is the caller's own circle,
// anywhere in which counts as the same job.
IUnitTask@ CoverFor(CCircuitDef@ want, const AIFloat3& in spot, float radius)
{
	const float reach = (radius > 0.f) ? radius : SAME_SITE;
	const float sqReach = reach * reach;
	IUnitTask@ best = null;
	float bestDist = 0.f;
	for (uint i = 0; i < gLive.length(); ++i) {
		IUnitTask@ cand = gLive[i];
		if (cand is null)
			continue;
		const uint busy = Workers(cand);
		if (!SameJob(cand.buildDef, want, busy))
			continue;
		const AIFloat3 where = cand.GetBuildPos();
		if (!OnMap(where) || (spot.SqDistance2D(where) >= sqReach))
			continue;
		const float d = spot.distance2D(where);
		if ((best is null) || (d < bestDist)) {
			@best = cand;
			bestDist = d;
		}
	}
	return best;
}

// The best request of this def worth JOINING from `spot`, anywhere in reach and
// under its worker cap. Distance is measured from the SITE, not from the
// builder: five idle constructors scattered around one base each found nothing
// within reach of THEMSELVES and each then computed its own spot, landing the
// five spots within ~200 elmos of each other. Duplicate-ness is a property of
// the site, not of which builder happened to notice it.
// A SECOND PAIR OF HANDS ON THE SAME METAL SITE. Mex and mex-upgrade wants are
// enqueued straight onto the builder manager and never pass through Take, so
// they never reach JoinFor either -- there was no path by which a second
// constructor could help one, whatever the crew rung would have allowed. This
// is that path: same def, same ground, room under the site's crew.
//
// JOIN_MIN_COST still applies, so a ~50 metal T1 extractor is not worth a walk
// to assist -- for those the second asker takes ANOTHER SPOT, which is the
// same answer arrived at by not joining.
IUnitTask@ JoinSpot(CCircuitUnit@ unit, CCircuitDef@ want, const AIFloat3& in spot)
{
	if ((want is null) || (want.costM < JOIN_MIN_COST) || !OnMap(spot))
		return null;
	const uint cap = SiteWorkerCap(want);
	for (uint i = 0; i < gLive.length(); ++i) {
		IUnitTask@ cand = gLive[i];
		if ((cand is null) || cand.IsDead() || (cand.buildDef !is want))
			continue;
		if (Workers(cand) >= cap)
			continue;
		if (NanoFed(cand, Workers(cand), 0.f, 0.f))
			continue;
		if ((unit !is null) && !unit.circuitDef.CanBuild(want))
			continue;
		const AIFloat3 where = cand.GetBuildPos();
		if (!OnMap(where) || (spot.distance2D(where) > SAME_SITE))
			continue;
		return cand;
	}
	return null;
}

IUnitTask@ JoinFor(CCircuitUnit@ unit, CCircuitDef@ want, const AIFloat3& in spot)
{
	if (want.costM < JOIN_MIN_COST)
		return null;
	// Per-site saturation, not the economy-wide pool: see SiteWorkerCap.
	const uint cap = SiteWorkerCap(want);
	IUnitTask@ best = null;
	float bestProgress = -1.f;
	float bestDist = REACH;
	for (uint i = 0; i < gLive.length(); ++i) {
		IUnitTask@ cand = gLive[i];
		if (cand is null)
			continue;
		const uint busy = Workers(cand);
		// The site's crew cap belongs to the def actually being BUILT there:
		// pricing a fusion's crew off the advsol want that walked in read a
		// 2-hand cap against a job that feeds many more.
		const uint candCap = ((cand.buildDef is null) || (cand.buildDef is want))
				? cap : SiteWorkerCap(cand.buildDef);
		if ((busy >= candCap) || !SameJob(cand.buildDef, want, busy))
			continue;
		if ((unit !is null) && (cand.buildDef !is null)
			&& !unit.circuitDef.CanBuild(cand.buildDef)
			&& (cand.target is null))
			continue;   // cannot place the def and no frame stands yet; a
			            // standing nanoframe takes ANY hands (repair) -- the
			            // law SameJob already states for the commander's
			            // fusion rungs, now honored here too
		const AIFloat3 where = cand.GetBuildPos();
		if (!OnMap(where))
			continue;
		const float dist = spot.distance2D(where);
		// A BUILD THAT TRANSFORMS THE ECONOMY IS WORTH A LONGER WALK
		// (apexearth: "detect that this building will double our energy
		// output and thus be very much worth joining"). Impact is the def's
		// own yield against the matching CURRENT income, so a reactor equal
		// to the standing grid doubles this site's join reach and a solar
		// moves it nothing; capped so one late-game monolith cannot recruit
		// the whole map. WorthJoining's travel-vs-remaining test keeps the
		// final say.
		float reach = REACH;
		if (cand.buildDef !is null) {
			const float eMake = aiEconomyMgr.GetEnergyMake(cand.buildDef);
			const float mMake = aiEconomyMgr.GetMetalMake(cand.buildDef);
			float impact = 0.f;
			if (eMake > 0.f) {
				const float eInc = Eco::EInc();
				impact = eMake / ((eInc < 1.f) ? 1.f : eInc);
			} else if (mMake > 0.f) {
				const float mInc = Eco::MInc();
				impact = mMake / ((mInc < 1.f) ? 1.f : mInc);
			}
			if (impact > 3.f)
				impact = 3.f;
			reach *= 1.f + impact;
		}
		if (dist >= reach)
			continue;
		if ((unit !is null) && (Builder::ThreatFor(unit, where) > Builder::CON_THREAT_VETO))
			continue;
		if (NanoFed(cand, busy, dist,
			(unit !is null) ? Catalog::gSpeed[int(unit.circuitDef.id)] : 0.f))
			continue;
		const float progress = Progress(cand);
		// Remaining work is the CANDIDATE's bill, not the want's: pricing a
		// fusion's join by the 320m advsol that walked in read minutes of
		// remaining lathe as not worth a forty-second walk.
		if (!WorthJoiningSite(cand, dist,
				(unit !is null) ? Catalog::gSpeed[int(unit.circuitDef.id)] : 0.f,
				(unit !is null) ? Catalog::gBuildPower[int(unit.circuitDef.id)] : 0.f)) {
			++gTooFar;
			continue;
		}
		// PROGRESS FIRST, DISTANCE ONLY BREAKS A TIE. A half-built nanoframe
		// always outranks a fresh one within reach -- concentrating build
		// power on whichever is closer to done, rather than spreading it
		// thin across several that each individually take longer to finish
		// and so sit exposed to the idle/order-drop abort path longer.
		if ((progress < bestProgress) || ((progress == bestProgress) && (dist >= bestDist)))
			continue;
		@best = cand;
		bestProgress = progress;
		bestDist = dist;
	}
	if ((best !is null) && (unit !is null) && (best.buildDef !is null)
		&& !unit.circuitDef.CanBuild(best.buildDef))
	{
		AiLog("apex: join assist t=" + ai.teamId + " "
			+ unit.circuitDef.GetName() + " #" + unit.id
			+ " -> " + best.buildDef.GetName()
			+ " (cross-tier: wanted " + want.GetName() + ")");
	}
	return best;
}

// The request for this def that NOBODY is working, ranked by progress first
// (a nanoframe abandoned mid-build -- its worker died, got vetoed off, or
// hit the idle/order-drop retry ceiling -- is exactly the case to finish
// before starting anything fresh) and distance second. No cost floor: this
// is not "come and help", it is "this order is unowned, take it" -- so the
// walk is the walk the builder would have made to its own site anyway.
IUnitTask@ ClaimFor(CCircuitDef@ want, const AIFloat3& in spot)
{
	IUnitTask@ best = null;
	float bestProgress = -1.f;
	float bestDist = REACH;
	for (uint i = 0; i < gLive.length(); ++i) {
		IUnitTask@ cand = gLive[i];
		if (cand is null)
			continue;
		if (Workers(cand) > 0)
			continue;
		const CCircuitDef@ has = cand.buildDef;
		if ((has is null) || (has.id != want.id))
			continue;
		const AIFloat3 where = cand.GetBuildPos();
		if (!OnMap(where))
			continue;
		const float dist = spot.distance2D(where);
		if (dist >= REACH)
			continue;
		const float progress = Progress(cand);
		if ((progress < bestProgress) || ((progress == bestProgress) && (dist >= bestDist)))
			continue;
		@best = cand;
		bestProgress = progress;
		bestDist = dist;
	}
	return best;
}

// How many requests for this exact def are live, in any state.
uint InFlight(const CCircuitDef@ want)
{
	if (want is null)
		return 0;
	uint n = 0;
	for (uint i = 0; i < gLive.length(); ++i) {
		IUnitTask@ cand = gLive[i];
		if (cand is null)
			continue;
		const CCircuitDef@ has = cand.buildDef;
		if ((has !is null) && (has.id == want.id))
			++n;
	}
	return n;
}

}  // namespace Requests
