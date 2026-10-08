namespace Market {

// TOWERS FLOWN FORWARD (apexearth 2026-09-24, docs/24): a front tower slot is
// filled either by building on site or by building at home and flying the
// finished tower up. Each is charged what the market already charges a build
// -- ExpectedLossAt over the frame's build seconds, frame and crew -- and the
// flight pays the same rate for the plane and tower over the drop.

array<Ferry@> gFerries;
int gFerryPlans = 0, gFerried = 0, gFerryDropped = 0, gFerryOnsite = 0;

// A front tower built on site that a plane would have flown for less: the
// metal of the difference, remembered for the production market. One entry
// per slot -- the same slot re-elected is one tower, not several.
array<int> gFerryMissAt;
array<int> gFerryMissDef;
array<float> gFerryMissM;
array<AIFloat3> gFerryMissPos;

void FerryNoteMissed(int d, const AIFloat3& in site, float m)
{
	++gFerryOnsite;
	for (uint i = 0; i < gFerryMissAt.length(); ++i) {
		if ((gFerryMissDef[i] == d) && (gFerryMissPos[i].distance2D(site) < 600.f)) {
			gFerryMissAt[i] = ai.frame;
			if (m > gFerryMissM[i])
				gFerryMissM[i] = m;
			return;
		}
	}
	gFerryMissAt.insertLast(ai.frame);
	gFerryMissDef.insertLast(d);
	gFerryMissM.insertLast(m);
	gFerryMissPos.insertLast(site);
}

// A ferry whose home build has no live request this long has been abandoned.
// Same staleness the election's approach test uses.
const int FERRY_LAPSE_S = 30;
int gNextFerryWeighLog = 0;
int gFerryRepriced = 0;

array<int> gLiftDefs;
bool gLiftDefsListed = false;

void LiftDefsList()
{
	if (gLiftDefsListed)
		return;
	gLiftDefsListed = true;
	for (uint d = 0; d < Catalog::gCostM.length(); ++d) {
		if (Catalog::ValidId(int(d)) && Catalog::gAvailable[d] && IsLiftDef(int(d)))
			gLiftDefs.insertLast(int(d));
	}
}

// The cheapest plane that can carry def c, or -1.
int CheapestLifter(int c)
{
	LiftDefsList();
	int best = -1;
	for (uint i = 0; i < gLiftDefs.length(); ++i) {
		const int t = gLiftDefs[i];
		if (!LiftFits(t, c))
			continue;
		if ((best < 0) || (Catalog::gCostM[t] < Catalog::gCostM[best]))
			best = t;
	}
	return best;
}

bool OwnPlaneFits(int c)
{
	for (uint j = 0; j < gLift.length(); ++j) {
		if (LiftFits(int(gLift[j].plane.circuitDef.id), c))
			return true;
	}
	return false;
}

// Cargo a plane we own, or one already ordered, can carry is demand that is
// met; misses remembered from before the plane existed must not buy another.
bool LiftServed(int c)
{
	if (OwnPlaneFits(c))
		return true;
	LiftDefsList();
	for (uint i = 0; i < gLiftDefs.length(); ++i) {
		if ((Brain::PendAnyOf(gLiftDefs[i]) > 0) && LiftFits(gLiftDefs[i], c))
			return true;
	}
	return false;
}

Ferry@ FerryNear(int d, const AIFloat3& in site)
{
	for (uint i = 0; i < gFerries.length(); ++i) {
		Ferry@ f = gFerries[i];
		if ((f.def == d) && (f.site.distance2D(site) < 600.f))
			return f;
	}
	return null;
}

// Standing on their side of the map is dangerous for every second of it, seen
// or not (apexearth 2026-09-24). The seen-force hazard reads ~0 at a quiet
// front, so the depth term the trip already uses is turned into a rate over
// the time a raid takes to find you, less what our guns there would stop.
float TerritoryRate(const AIFloat3& in at)
{
	const float tau = ai.GetTunable("apex_eco_raid_tau", TUNE_ECO_RAID_TAU);
	if (tau <= 1.f)
		return 0.f;
	return TripRisk(at) * ShortfallAt(at) / tau;
}

float BuildLossAt(const AIFloat3& in at, int d, float crewM, float buildSec,
		float lossH, float frameK)
{
	const float seen = (ExpectedLossAt(at, Catalog::gCostM[d]) * frameK
			+ ExpectedLossAt(at, crewM)) * buildSec / lossH;
	float p = TerritoryRate(at) * buildSec;
	if (p > 1.f)
		p = 1.f;
	const float territory = (Catalog::gCostM[d] * frameK + crewM) * p;
	return (seen > territory) ? seen : territory;
}


// A front tower need not be built at the front (apexearth 2026-09-24): with a
// plane that carries it, it is built wherever the builder is safe and flown
// up. Both routes in metal -- build exposure, the builder's walk at its wage,
// the road's TripRisk -- and where the ferry would build. False when no plane
// in the catalog can carry the def.
bool FerryWeigh(CCircuitUnit@ unit, int d, float buildSec, const AIFloat3& in site,
		AIFloat3& out home, float& out onsite, float& out ferry,
		float& out walkSite, float& out walkHome, float& out flightLoss)
{
	const int plane = CheapestLifter(d);
	if (plane < 0)
		return false;
	const float lossH = ai.GetTunable("apex_exposed_loss_s", TUNE_EXPOSED_LOSS_S);
	const float frameK = ai.GetTunable("apex_frame_risk", TUNE_FRAME_RISK);
	if (lossH <= 1.f)
		return false;
	const int ud = int(unit.circuitDef.id);
	const float crewM = Catalog::gCostM[ud];
	float bs = buildSec;
	if ((bs <= 0.f) && (Catalog::gBuildPower[ud] > 0.f))
		bs = Catalog::gBuildTime[d] / Catalog::gBuildPower[ud];
	const float walkRate = WalkRate(Catalog::gBuildPower[ud]);
	const AIFloat3 up = unit.GetPos(ai.frame);
	walkSite = WalkSecTo(unit, site);
	onsite = BuildLossAt(site, d, crewM, bs, lossH, frameK)
			+ walkSite * walkRate
			+ TripRiskFrom(up, site) * crewM;
	const float reach = (Catalog::gMaxRange[d] > 100.f) ? Catalog::gMaxRange[d] : 100.f;
	// Where it is built: the builder's own ground when that is shallower than
	// the slot and not already on it, or the base -- whichever costs less.
	bool any = false;
	float bestHome = 0.f;
	AIFloat3 hc;
	if ((up.distance2D(site) > reach) && (TripRisk(up) < TripRisk(site))) {
		hc = up;
		bestHome = BuildLossAt(up, d, crewM, bs, lossH, frameK);
		walkHome = 0.f;
		any = true;
	}
	if (Base::gAnchorSet) {
		const float wa = WalkSecTo(unit, Base::gAnchor);
		const float al = BuildLossAt(Base::gAnchor, d, crewM, bs, lossH, frameK)
				+ wa * walkRate + TripRiskFrom(up, Base::gAnchor) * crewM;
		if (!any || (al < bestHome)) {
			hc = Base::gAnchor;
			bestHome = al;
			walkHome = wa;
			any = true;
		}
	}
	if (!any)
		return false;
	home = hc;
	const float speed = (Catalog::gSpeed[plane] > 1.f) ? Catalog::gSpeed[plane] : 100.f;
	const float dropSec = 2.f * reach / speed;
	const float conSpeed = Catalog::gSpeed[ud];
	const float airShare = ((conSpeed > 1.f) && (conSpeed < speed)) ? (conSpeed / speed) : 1.f;
	const float carriedM = Catalog::gCostM[d] + Catalog::gCostM[plane];
	const float hoverSeen = ExpectedLossAt(site, carriedM) * dropSec / lossH;
	const float hoverTerr = carriedM * TerritoryRate(site) * dropSec;
	flightLoss = ((hoverSeen > hoverTerr) ? hoverSeen : hoverTerr)
			+ TripRiskFrom(hc, site) * airShare * carriedM;
	ferry = bestHome + flightLoss;
	return true;
}

// The election sees the ferry too: with a plane that can carry it, a front
// tower's price is the builder's walk and road to where it would build plus
// the flight, not the walk to the front -- or only the builders already near
// the front ever elect one. Runs after ChargeTrip has billed the road.
bool FerryKind(int kind)
{
	return (kind == WK_PROTECT) || (kind == WK_SENSE) || (kind == WK_AIRDEF);
}

// `denom` is ChargeTrip's c + tripM. tCost already holds the walk to the
// front, so the ferry takes it out there and bills its own costs as the
// trip; tripM stays positive because ChargeTrip reads <= 0 as "not charged".
float FerryReprice(Want@ w, CCircuitUnit@ unit, float c, float denom)
{
	if (!FerryKind(w.kind) || (w.def is null) || !OwnPlaneFits(int(w.def.id)))
		return denom;
	AIFloat3 home;
	float onsite = 0.f, ferry = 0.f, walkSite = 0.f, walkHome = 0.f, flight = 0.f;
	if (!FerryWeigh(unit, int(w.def.id), w.buildSec, w.pos, home, onsite, ferry,
			walkSite, walkHome, flight) || (ferry >= onsite))
		return denom;
	const float refund = w.walkSec * WalkRate(Catalog::gBuildPower[int(unit.circuitDef.id)]);
	w.tripM = (ferry > 0.001f) ? ferry : 0.001f;
	float dn = c - refund + w.tripM;
	if (dn < 0.1f * c)
		dn = 0.1f * c;
	++gFerryRepriced;
	return dn;
}

// -1 build on site as before; 0 the slot is already being ferried and has
// nothing left to build; 1 build at `home` for the ferry.
int FerryRoute(CCircuitUnit@ unit, Want@ w, const AIFloat3& in site, AIFloat3& out home)
{
	if (w.def is null)
		return -1;
	const int d = int(w.def.id);
	Ferry@ f = FerryNear(d, site);
	if (f !is null) {
		if (f.stage > 0)
			return 0;
		home = f.home;
		return 1;
	}
	AIFloat3 hc;
	float onsite = 0.f, ferryLoss = 0.f, walkSite = 0.f, walkHome = 0.f, flightLoss = 0.f;
	if (!FerryWeigh(unit, d, w.buildSec, site, hc, onsite, ferryLoss,
			walkSite, walkHome, flightLoss))
		return -1;
	if (ferryLoss >= onsite) {
		if (ai.frame >= gNextFerryWeighLog) {
			gNextFerryWeighLog = ai.frame + 30 * SECOND;
			AiLog("apex: ferry weigh t=" + ai.teamId + " " + w.def.GetName()
					+ " onsite=" + formatFloat(onsite, "", 0, 1)
					+ " (walk " + int(walkSite) + "s)"
					+ " ferry=" + formatFloat(ferryLoss, "", 0, 1)
					+ " (walk " + int(walkHome) + "s flight "
					+ formatFloat(flightLoss, "", 0, 1) + ") -> onsite");
		}
		return -1;
	}
	if (!OwnPlaneFits(d)) {
		FerryNoteMissed(d, site, onsite - ferryLoss);
		return -1;
	}
	home = ai.FindBuildSiteNear(w.def, hc, 300.f);
	if (!OnMap(home))
		return -1;
	Ferry@ nf = Ferry();
	nf.def = d;
	nf.home = home;
	nf.site = site;
	nf.madeAt = ai.frame;
	nf.seenAt = ai.frame + int(walkHome * float(SECOND));
	@gFerryPending = nf;
	gFerryPendingLog = "apex: ferry plan t=" + ai.teamId + " " + w.def.GetName()
			+ " site=" + int(site.x) + "," + int(site.z)
			+ " home=" + int(home.x) + "," + int(home.z)
			+ " onsite=" + formatFloat(onsite, "", 0, 1)
			+ " (walk " + int(walkSite) + "s)"
			+ " ferry=" + formatFloat(ferryLoss, "", 0, 1)
			+ " (walk " + int(walkHome) + "s flight "
			+ formatFloat(flightLoss, "", 0, 1) + ")";
	return 1;
}

// The plan claims the slot only once its home request exists: the request
// chokepoint may hold it, and a claim with no build behind it blocked the
// slot until it lapsed (20 of 28 plans, one game).
Ferry@ gFerryPending;
string gFerryPendingLog;
int gFerryHeld = 0;

void FerryCommit(bool made)
{
	if (gFerryPending is null)
		return;
	if (made) {
		gFerries.insertLast(gFerryPending);
		++gFerryPlans;
		AiLog(gFerryPendingLog);
	} else {
		++gFerryHeld;
	}
	@gFerryPending = null;
}

// What the pricing would see now, over the same window.
float FerryMissSum()
{
	float fill = ai.GetTunable("apex_army_fill_s", TUNE_ARMY_FILL_S);
	if (fill <= 1.f)
		fill = 180.f;
	FerryMissedFor(-1, fill);
	float m = 0.f;
	for (uint i = 0; i < gFerryMissM.length(); ++i)
		m += gFerryMissM[i];
	return m;
}

float FerryMissedFor(int t, float fillSec)
{
	const int since = ai.frame - int(fillSec * float(SECOND));
	float m = 0.f;
	for (int i = int(gFerryMissAt.length()) - 1; i >= 0; --i) {
		if (gFerryMissAt[i] < since) {
			gFerryMissAt.removeAt(i);
			gFerryMissDef.removeAt(i);
			gFerryMissM.removeAt(i);
			gFerryMissPos.removeAt(i);
			continue;
		}
		if ((t >= 0) && LiftFits(t, gFerryMissDef[i]) && !LiftServed(gFerryMissDef[i]))
			m += gFerryMissM[i];
	}
	return m;
}

void FerryNoteFinished(CCircuitUnit@ unit)
{
	const int d = int(unit.circuitDef.id);
	const AIFloat3 p = unit.GetPos(ai.frame);
	for (uint i = 0; i < gFerries.length(); ++i) {
		Ferry@ f = gFerries[i];
		if ((f.stage != 0) || (f.def != d) || (f.home.distance2D(p) > 200.f))
			continue;
		@f.tower = unit;
		f.stage = 1;
		f.builtAt = ai.frame;
		ProtCensusMove(unit, f.site);
		AiLog("apex: ferry built t=" + ai.teamId + " " + unit.circuitDef.GetName()
				+ " #" + unit.id + " for site=" + int(f.site.x) + "," + int(f.site.z));
		return;
	}
}

void FerryRemove(Ferry@ f)
{
	for (uint i = 0; i < gFerries.length(); ++i) {
		if (gFerries[i] is f) {
			gFerries.removeAt(i);
			return;
		}
	}
}

void FerryDrop(Ferry@ f, const string& in why)
{
	if (f.tower !is null)
		ProtCensusMove(f.tower, f.tower.GetPos(ai.frame));
	++gFerryDropped;
	AiLog("apex: ferry dropped t=" + ai.teamId + " def="
			+ Catalog::Def(f.def).GetName() + " stage=" + f.stage + " -- " + why);
	FerryRemove(f);
}

void FerryLanded(Ferry@ f)
{
	++gFerried;
	AiLog("apex: ferry landed t=" + ai.teamId + " " + Catalog::Def(f.def).GetName()
			+ " at site=" + int(f.site.x) + "," + int(f.site.z)
			+ " after " + ((ai.frame - f.madeAt) / SECOND) + "s ferried=" + gFerried);
	FerryRemove(f);
}

void FerryNoteDead(CCircuitUnit@ unit)
{
	for (uint i = 0; i < gFerries.length(); ++i) {
		if ((gFerries[i].stage == 1) && (gFerries[i].tower is unit)) {
			@gFerries[i].tower = null;
			FerryDrop(gFerries[i], "tower died at home");
			return;
		}
	}
}

bool FerryDispatch(LiftJob@ jb)
{
	const int pd = int(jb.plane.circuitDef.id);
	const AIFloat3 pp = jb.plane.GetPos(ai.frame);
	Ferry@ best = null;
	float bestD = 0.f;
	for (uint i = 0; i < gFerries.length(); ++i) {
		Ferry@ f = gFerries[i];
		if ((f.stage != 1) || (f.tower is null) || !LiftFits(pd, f.def))
			continue;
		if (Builder::SiteHot(f.site))
			continue;
		const float dd = pp.distance2D(f.home);
		if ((best is null) || (dd < bestD)) {
			@best = f;
			bestD = dd;
		}
	}
	if (best is null)
		return false;
	AIFloat3 to = ai.FindBuildSiteNear(Catalog::Def(best.def), best.site, 200.f);
	to = ai.FindBuildSiteNear(Catalog::Def(best.def), OffAllyBuildings(OffFactoryExit(to)), 150.f);
	if (!OnMap(to))
		to = best.site;
	@jb.cargo = best.tower;
	@jb.ferry = best;
	jb.src = best.tower.GetPos(ai.frame);
	jb.to = to;
	jb.stage = 1;
	jb.retried = false;
	jb.deadline = ai.frame + int((bestD / LiftSpeed(jb.plane) * 3.f + 30.f) * float(SECOND));
	best.stage = 2;
	jb.plane.CmdLoadUnit(best.tower);
	AiLog("apex: ferry go t=" + ai.teamId + " " + jb.plane.circuitDef.GetName()
			+ " #" + jb.plane.id + " takes " + best.tower.circuitDef.GetName()
			+ " #" + best.tower.id + " to=" + int(to.x) + "," + int(to.z));
	return true;
}

void FerryUpdate()
{
	for (int i = int(gFerries.length()) - 1; i >= 0; --i) {
		Ferry@ f = gFerries[i];
		if (f.stage == 0) {
			for (uint k = 0; k < Requests::gLive.length(); ++k) {
				IUnitTask@ t = Requests::gLive[k];
				if ((t !is null) && (t.buildDef !is null) && (int(t.buildDef.id) == f.def)
					&& (t.GetBuildPos().distance2D(f.home) < 200.f))
				{
					f.seenAt = ai.frame;
					break;
				}
			}
			if (ai.frame - f.seenAt > FERRY_LAPSE_S * SECOND)
				FerryDrop(f, "home build lapsed");
		} else if ((f.stage == 1) && !OwnPlaneFits(f.def)) {
			FerryDrop(f, "no plane can carry it");
		} else if ((f.stage == 1) && (ai.frame - f.builtAt > FERRY_LAPSE_S * SECOND)) {
			// Counted at the front while it waits; a tower that never flies must
			// stop covering ground it is not standing on.
			FerryDrop(f, "waited too long for a plane");
		}
	}
}

}  // namespace Market
