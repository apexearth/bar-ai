namespace Market {
// Standing defense metal near a point -- the crowding divisor that makes
// a 247-LLT carpet impossible (apexearth's screenshot: the whole eco lost
// to in-base turret sprawl).
// Distance to the nearest map wall -- diagnostics only.
float EdgeDist(const AIFloat3& in p)
{
	float d = p.x;
	if (p.z < d) d = p.z;
	if (float(AiTerrainWidth()) - p.x < d) d = float(AiTerrainWidth()) - p.x;
	if (float(AiTerrainHeight()) - p.z < d) d = float(AiTerrainHeight()) - p.z;
	return (d < 0.f) ? 0.f : d;
}

float DefCrowdM(const AIFloat3& in pos, float r)
{
	float m = 0.f;
	for (uint i = 0; i < gProtPos[PROT_DEF].length(); ++i) {
		if (gProtPos[PROT_DEF][i].distance2D(pos) < r)
			m += Catalog::gCostM[gProtDefId[PROT_DEF][i]];
	}
	return m;
}

// Does a STANDING radar already watch this ground? Judged by that radar's own
// range -- asking it about the CANDIDATE's range is why a 60-metal armrad at
// the farm permanently blocked the 3500-range armarad, and why we finished
// every game with exactly one radar (apexearth: "our radar coverage is only
// partial").
bool RadarSees(const AIFloat3& in pos)
{
	// apexearth 2026-08-29: "radar might just be set wrong so you can tweak
	// it." 0.8 of a standing radar's own radius blocked any second radar
	// inside a 1,700-elmo circle (corrad 2100): coverage with ZERO
	// redundancy, so one radar death opened a dark zone mid-fight -- and the
	// threat map holds only radar/LOS contacts, so the engage logic then
	// accepted fights against armies it could not count (foeMass read 3-6k
	// of stock's ~15k standing; trades 0.2). Stock stands 26 T1 radars to
	// our 13. The overlap fraction buys depth: a gap must sit outside this
	// share of every standing radar's reach before a new mast is blocked.
	const float overlap = ai.GetTunable("apex_radar_overlap", TUNE_RADAR_OVERLAP);
	for (uint i = 0; i < gProtPos[PROT_RADAR].length(); ++i) {
		const int rd = gProtDefId[PROT_RADAR][i];
		const float rr = Catalog::gRadarR[rd];
		if ((rr > 1.f) && (pos.distance2D(gProtPos[PROT_RADAR][i]) < rr * overlap))
			return true;
	}
	return false;
}

// The ground we care about that nothing watches, and how much of it there is.
// Candidates are the front posts and our standing mexes. The NEAREST gap wins,
// not the most forward one: picking the deepest gap produced 38 radar bids and
// zero radars in a 28-minute game, because a builder re-elects during a long
// walk and abandons a frame it has not started. Coverage still spreads -- once
// this gap is watched the nearest remaining one is somewhere else. The unseen
// share is the diminishing return: cover everything and the want prices itself
// out without a count anywhere.
bool RadarGap(const AIFloat3& in from, AIFloat3& out at, float& out unseenFrac)
{
	array<AIFloat3> pts;
	if (ai.GetTunable("apex_front_line", TUNE_FRONT_LINE) > 0.f) {
		array<AIFloat3> line;
		if (Military::FrontBuildSpots(line)) {
			for (uint i = 0; i < line.length(); ++i)
				pts.insertLast(line[i]);
		}
	}
	for (uint li = 0; li < gLPos.length(); ++li) {
		if (gLExtract[li] > 0.f)
			pts.insertLast(gLPos[li]);
	}
	if (pts.length() == 0)
		return false;
	int unseen = 0;
	float bestD = -1.f;
	bool found = false;
	const bool foeKnown = Front::FoeKnown();
	for (uint i = 0; i < pts.length(); ++i) {
		if (!OnMap(pts[i]) || RadarSees(pts[i]))
			continue;
		// A GAP WE MAY NOT SAFELY BUILD AT IS NOT DEMAND (apexearth,
		// watching sense outbid nanos at v=108: "that seems a bit crazy...
		// they probably already have all the radar they can make in any
		// safe area"). Hot gaps kept unseenFrac -- and with it the
		// wealth-scaled gain -- above zero forever, for radars the safety
		// gate then refused or the enemy ate. Cover every SAFE gap and
		// this want now prices itself out, as its own comment promises.
		if (foeKnown && Builder::PastFront(pts[i]))
			continue;
		++unseen;
		const float dd = from.distance2D(pts[i]);
		if (!found || (dd < bestD)) {
			bestD = dd;
			at = pts[i];
			found = true;
		}
	}
	unseenFrac = float(unseen) / float(pts.length());
	return found;
}

// A POST SHIELDS WHAT IS BEHIND IT ONLY IF THE ENEMY CANNOT WALK AROUND IT.
// apexearth: "ShieldedStakeAt is technically correct as long as we've closed
// the loop - created a net with no holes in it. Otherwise it's moreso a
// 'partial' truth."
//
// Closure is the share of approach bearings some standing post actually
// covers. The shielded credit a candidate earns is the closure it would ADD,
// so plugging the last hole is worth the whole base behind it and a redundant
// post beside an existing one is worth nothing. That is what makes defence
// saturate: without it every candidate site claimed the entire base, measured
// at stake 13,606 against an economy of 8,751, and the price never fell however
// many turrets stood.
//
// A bearing that runs off the map counts as closed -- the edge is the wall.
// AN ALLY'S BASE IS A WALL TOO (apexearth, refusing to host the 8v8: "all
// our AI makes tons of turrets in their own base instead of in front of
// their allies base who is in front of them. It looks too stupid."): a
// bearing whose outward corridor passes a TEAMMATE'S HOME is theirs to
// hold, counted closed exactly as the edge is -- which is what stops a
// back-line player ringing itself while an ally stands between it and the
// war. Homes come off the team blackboard (air/update.as publishes
// homex/homez per player), never GetAllyInflAt: that read counts ourselves
// (measured 3.71 in a solo game, coverage.as) and would close the
// enemy-facing bearings on our own massing army. Filled by ClosurePrep on
// the same field stamp as the ring.
const int CLOSE_RAYS = 16;
array<bool> gClAllyShield;
array<Id>@  gShieldMates = null;
int gNextAllyFLog = 0;

float LineClosure(const AIFloat3& in extraAt, float extraReach)
{
	PfRebuild();
	ClosurePrep();
	AIFloat3 c;
	float extent = 0.f;
	if (!BaseCentroid(c, extent))
		return 0.f;
	const float ring = extent + Military::FoeReach();
	if (ring <= 1.f)
		return 0.f;
	int closed = 0;
	for (int b = 0; b < CLOSE_RAYS; ++b) {
		const float ang = 6.2831853f * float(b) / float(CLOSE_RAYS);
		const AIFloat3 p = c + AIFloat3(cos(ang), 0.f, sin(ang)) * ring;
		if (!OnMap(p)) {
			++closed;
			continue;
		}
		if ((b < int(gClAllyShield.length())) && gClAllyShield[b]) {
			++closed;
			continue;
		}
		bool ok = (extraReach > 0.f) && (extraAt.distance2D(p) <= extraReach);
		for (uint i = 0; !ok && (i < gPfTwPos.length()); ++i) {
			if (gPfTwPos[i].distance2D(p) <= gPfTwReach[i])
				ok = true;
		}
		if (ok)
			++closed;
	}
	return float(closed) / float(CLOSE_RAYS);
}

// THE STANDING RING, RESOLVED ONCE. The closure a candidate ADDS is
// LineClosure(site, reach) - LineClosure(x, 0): both sweeps walk the same 16
// bearings against the same standing towers, and only the extra post differs.
// So the bearings a post could still plug are a property of the field, not of
// the candidate -- read them once and a site costs 16 distance checks instead
// of 16 x every tower we own.
array<AIFloat3> gClRingP;
array<bool>     gClRingOpen;
bool            gClRingOk = false;
// The ring's own centre and radius, kept for the candidate generator below --
// and a memo on the field stamp: the ring is a function of the field and the
// standing towers, both of which only move on a PfRebuild.
AIFloat3        gClMid;
float           gClRingR = 0.f;
int             gClRingAt = -999999;

void ClosurePrep()
{
	PfRebuild();
	if (gClRingAt == gPfAt)
		return;
	gClRingAt = gPfAt;
	gClRingOk = false;
	gClRingP.resize(0);
	gClRingOpen.resize(0);
	AIFloat3 c;
	float extent = 0.f;
	if (!BaseCentroid(c, extent))
		return;
	const float ring = extent + Military::FoeReach();
	if (ring <= 1.f)
		return;
	gClRingOk = true;
	gClMid = c;
	gClRingR = ring;
	// The teammates' homes, read once per stamp -- see the ally-wall comment
	// above LineClosure. Self is excluded by construction.
	array<float> hx;
	array<float> hz;
	if (gShieldMates is null)
		@gShieldMates = ai.GetTeamIds();
	if (gShieldMates !is null) {
		for (uint m = 0; m < gShieldMates.length(); ++m) {
			if (int(gShieldMates[m]) == ai.teamId)
				continue;
			const float mx = ai.ReadTeamValue(int(gShieldMates[m]), "homex", -1.f);
			const float mz = ai.ReadTeamValue(int(gShieldMates[m]), "homez", -1.f);
			if ((mx < 0.f) || (mz < 0.f))
				continue;
			hx.insertLast(mx);
			hz.insertLast(mz);
		}
	}
	gClAllyShield.resize(0);
	for (int b = 0; b < CLOSE_RAYS; ++b) {
		const float ang = 6.2831853f * float(b) / float(CLOSE_RAYS);
		const AIFloat3 p = c + AIFloat3(cos(ang), 0.f, sin(ang)) * ring;
		// A ~17-degree half-cone about the bearing (lateral within 30% of
		// the along distance): geometry of "roughly this way", not policy.
		bool shielded = false;
		const float dxb = (p.x - c.x) / ring;
		const float dzb = (p.z - c.z) / ring;
		for (uint m = 0; !shielded && (m < hx.length()); ++m) {
			const float vx = hx[m] - c.x;
			const float vz = hz[m] - c.z;
			const float along = vx * dxb + vz * dzb;
			if (along <= extent)
				continue;
			const float lx = vx - dxb * along;
			const float lz = vz - dzb * along;
			if (lx * lx + lz * lz <= 0.09f * along * along)
				shielded = true;
		}
		gClAllyShield.insertLast(shielded);
		bool open = OnMap(p) && !shielded;
		for (uint i = 0; open && (i < gPfTwPos.length()); ++i) {
			if (gPfTwPos[i].distance2D(p) <= gPfTwReach[i])
				open = false;
		}
		gClRingP.insertLast(p);
		gClRingOpen.insertLast(open);
	}
}

// Share of approach bearings something standing already covers; -1 before the
// field exists. The number the all-angles work is judged on.
float ClosureFrac()
{
	ClosurePrep();
	if (!gClRingOk || (gClRingOpen.length() == 0))
		return -1.f;
	int closed = 0;
	for (uint b = 0; b < gClRingOpen.length(); ++b) {
		if (!gClRingOpen[b])
			++closed;
	}
	return float(closed) / float(gClRingOpen.length());
}

float ClosureAdds(const AIFloat3& in extraAt, float extraReach)
{
	if (!gClRingOk || (extraReach <= 0.f))
		return 0.f;
	int add = 0;
	for (uint b = 0; b < gClRingP.length(); ++b) {
		if (gClRingOpen[b] && (extraAt.distance2D(gClRingP[b]) <= extraReach))
			++add;
	}
	return float(add) / float(CLOSE_RAYS);
}

// THE OUTSKIRTS, AND SPREAD AROUND THEM. apexearth: "we put our AA defense in
// the center of our base, but if the enemy bombers reached that place then
// bombs are already dropped. Need AA around the outskirts."
//
// AA never set a position at all -- it fell through to `core`, the anchor,
// which is the start position -- so every battery of every kind landed on the
// same spot. This walks the perimeter the protection field already computes and
// returns the rim bearing FURTHEST from anything of this class we already own,
// so the ring fills itself out one gap at a time and widens as the base does.
// No radius and no count: the geometry is the rim, and the auction decides how
// many are worth buying.
bool RimGapSite(int cls, AIFloat3& out at)
{
	PfRebuild();
	if (!gPfRimOk)
		return false;
	float bestD = -1.f;
	AIFloat3 best;
	bool found = false;
	for (int b = 0; b < PF_RAYS; ++b) {
		const float ang = (6.2831853f / float(PF_RAYS)) * (float(b) + 0.5f);
		const AIFloat3 dir(cos(ang), 0.f, sin(ang));
		const AIFloat3 p = gPfMid + dir * gPfRimR[b];
		const AIFloat3 q(p.x, 0.f, p.z);
		if (!OnMap(q))
			continue;
		float near = 1e9f;
		for (uint i = 0; i < gProtPos[cls].length(); ++i) {
			const float dd = q.distance2D(gProtPos[cls][i]);
			if (dd < near)
				near = dd;
		}
		if (near > bestD) {
			bestD = near;
			best = q;
			found = true;
		}
	}
	if (found)
		at = best;
	return found;
}

// ANYTHING OF THIS CLASS STANDING *OR COMING*, anywhere. The emergency in
// decide.as asked gProtPos alone, which is written at AiUnitFinished -- so
// while the first AA tower was still a nanoframe every other builder read
// "zero AA standing" and panicked too. Each panic hoists AA to the front and
// skips the draw, so 5 metal of enemy scout produced 35 AA requests and 51 of
// the first 168 elections, while metal took 23 (apexearth, watching: "we don't
// care enough about capturing mexes early on... we end up trying to do other
// things even though we're out of metal"). The emergency is meant to end at
// the FIRST tower, which is what this counts.
bool ProtAnyComing(int cls)
{
	// One source: the commitment ledger holds standing, framed and ordered
	// alike (flipped 2026-08-27, shadow clean across the proving games).
	for (uint ci = 0; ci < ComLen(); ++ci) {
		if (ProtClassOf(gComDef[ci]) == cls)
			return true;
	}
	return false;
}

// A jammer's exclusion radius, floored so a dead binding cannot mean "no
// limit". Logged once because an engine callback returning zero is
// indistinguishable from a real answer at the call site.
bool gJamLogged = false;

float JamSpacing(int d)
{
	const float raw = Catalog::gJamR[d];
	if (!gJamLogged) {
		gJamLogged = true;
		AiLog(Factory::T() + "apex: jammer " + Catalog::Def(d).GetName()
			+ " GetJammerRadius=" + formatFloat(raw, "", 0, 1));
	}
	float r = raw * 0.8f;
	if (r < 300.f)
		r = 300.f;
	return r;
}

bool ProtCovered(int cls, const AIFloat3& in pos, float r)
{
	// ONE ALREADY COMING COVERS THIS GROUND, whoever remembers it: standing,
	// half-built, orphaned frame and outstanding order are all one ledger
	// (flipped 2026-08-27). The OnMap guard skips orders not yet sited.
	bool old = false;
	for (uint ci = 0; ci < ComLen(); ++ci) {
		if (ProtClassOf(gComDef[ci]) != cls)
			continue;
		if (OnMap(gComPos[ci]) && (pos.distance2D(gComPos[ci]) < r)) {
			old = true;
			break;
		}
	}
	return old;
}

// Insurance pricing: protection is worth a fraction of the assets it
// covers, per second of exposure. ONE modeled rate for eyes and turrets,
// one for the nuke risk (value-paradigm: a single named quantity each).
// Timing EMERGES: at 5k assets an anti-nuke prices at ~0.4 and loses; at
// 100k it prices at ~8 and wins.
const int HALF_GROUND = 0;
const int HALF_SENSE = 1;
const int HALF_AIRDEF = 2;
// Not a half of this market at all: the strategic statics are priced on what
// the economy can carry, in want_super.as. Listed here so ProposeProtectHalf
// skips them rather than pricing a silo as a turret.
const int HALF_SUPER = 3;

int HalfOfClass(int cls)
{
	if ((cls == PROT_RADAR) || (cls == PROT_JAM) || (cls == PROT_TARGFAC))
		return HALF_SENSE;
	if (cls == PROT_AA)
		return HALF_AIRDEF;
	if ((cls == PROT_ANTINUKE) || (cls == PROT_SUPER))
		return HALF_SUPER;
	return HALF_GROUND;
}

// Mobile AA standing over the base answers the same bombers a tower does, so it
// counts against the same cover target -- but ONLY while it is here. Beyond
// apex_intercept_r (the radius that already defines "raiding us" for the
// interceptors) it has left with the army, and the towers its credit displaced
// would have been what stayed. Cached per frame: this walks the team's units.
int gAAMobAt = -1;
float gAAMobM = 0.f;
float MobileAACoverM()
{
	if (gAAMobAt == ai.frame)
		return gAAMobM;
	gAAMobAt = ai.frame;
	gAAMobM = 0.f;
	if (!Builder::gHomeSet)
		return 0.f;
	const float r = ai.GetTunable("apex_intercept_r", TUNE_INTERCEPT_R);
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		if ((gOwnCount[d] <= 0) || !Catalog::gMobile[int(d)])
			continue;
		CCircuitDef@ cd = ai.GetCircuitDef(Id(d));
		if ((cd is null) || !cd.IsRoleAny(Unit::Role::AA.mask))
			continue;
		array<CCircuitUnit@>@ have = ai.GetOwnUnitsOfDef(cd, Builder::gHomePos, r);
		gAAMobM += float(have.length()) * Catalog::gCostM[int(d)];
	}
	return gAAMobM;
}

// Three questions, three tickets: shooting the ground, seeing, and shooting
// the sky. `half` picks which set of protection classes this call bids for;
// everything else about the auction is shared. See CAT_SENSE / CAT_AIRDEF.
}  // namespace Market
