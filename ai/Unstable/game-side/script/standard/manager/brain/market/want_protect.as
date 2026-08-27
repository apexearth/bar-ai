namespace Market {
CCircuitUnit@ gReclaimTarget = null;
CCircuitUnit@ gAssistTarget = null;

// Which kind of ground the defence auction keeps choosing. Without this the
// only way to tell a forward post from a tower at a mex is to read positions
// out of the log by hand.
int gDefSiteFront = 0;
int gDefSiteAsset = 0;
int gNextDefSiteLog = 0;
int gNextDefFwdLog = 0;
// EVERY TERM OF THE DEFENCE PRICE, so "why so many turrets" is read rather than
// guessed (apexearth: "what is the connection causing this? We need to not
// guess here").
float gDbgStake = 0.f, gDbgHz = 0.f, gDbgSiege = 0.f, gDbgHazard = 0.f;
float gDbgShort0 = 0.f, gDbgShort1 = 0.f, gDbgThreat = 0.f, gDbgCover0 = 0.f;
float gDbgCover1 = 0.f;
int gNextDefPriceLog = 0;
float gDbgFrontBest = 0.f;
float gDbgAssetBest = 0.f;
int gDbgLineN = 0;
// The defence auction's own ranking, so "why did we never build a Pulsar" is
// read rather than argued: every turret this builder could place, with what
// the market thinks it is worth.
array<int> gDefRankDef;
array<float> gDefRankV;
// Per BUILDER DEF, not one clock for the fleet: a single global throttle
// samples whichever constructor happened to elect, and reads as "the advanced
// constructor never proposes defence" when it simply was not sampled.
array<int> gNextDefRankOf;
// COMPLETED, not won. gDefSiteFront counts auction wins, and a re-election
// counts again; a want whose builder dies or whose site is blocked never
// becomes a standing gun. Placement is Military::OnBorder -- the same ray
// model the front sites are drawn from, so won and built are comparable.
int gFrontTowerBuilt = 0;
int gFrontTowerLost = 0;
int gBackTowerBuilt = 0;
int gBackTowerLost = 0;
float gFrontTowerM = 0.f;
float gBackTowerM = 0.f;
int gNextFrontTowerLog = 0;

void NoteTowerBuilt(const AIFloat3& in at, float costM)
{
	if (Military::OnBorder(at)) {
		++gFrontTowerBuilt;
		gFrontTowerM += costM;
	} else {
		++gBackTowerBuilt;
		gBackTowerM += costM;
	}
}

void NoteTowerLost(const AIFloat3& in at)
{
	if (Military::OnBorder(at))
		++gFrontTowerLost;
	else
		++gBackTowerLost;
}

void LogFrontTowers()
{
	if (ai.frame < gNextFrontTowerLog)
		return;
	gNextFrontTowerLog = ai.frame + 30 * SECOND;
	AiLog(Factory::T() + "apex: fronttowers built=" + gFrontTowerBuilt
		+ " lost=" + gFrontTowerLost
		+ " standing=" + (gFrontTowerBuilt - gFrontTowerLost)
		+ " m=" + int(gFrontTowerM)
		+ " backBuilt=" + gBackTowerBuilt
		+ " backLost=" + gBackTowerLost
		+ " backStanding=" + (gBackTowerBuilt - gBackTowerLost)
		+ " backM=" + int(gBackTowerM)
		+ " wonFront=" + gDefSiteFront
		+ " wonAsset=" + gDefSiteAsset);
}

void NoteDefSite(bool isFront)
{
	if (isFront)
		++gDefSiteFront;
	else
		++gDefSiteAsset;
	if (ai.frame < gNextDefSiteLog)
		return;
	gNextDefSiteLog = ai.frame + 60 * SECOND;
	AiLog("apex: defsite front=" + gDefSiteFront + " asset=" + gDefSiteAsset
		+ " lineSpots=" + gDbgLineN
		+ " foeReach=" + formatFloat(Military::FoeReach(), "", 0, 0)
		+ " bestFrontGain=" + formatFloat(gDbgFrontBest, "", 0, 2)
		+ " bestAssetGain=" + formatFloat(gDbgAssetBest, "", 0, 2));
	gDbgFrontBest = 0.f;
	gDbgAssetBest = 0.f;
}

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
	for (uint i = 0; i < gProtPos[PROT_RADAR].length(); ++i) {
		const int rd = gProtDefId[PROT_RADAR][i];
		const float rr = Catalog::gRadarR[rd];
		if ((rr > 1.f) && (pos.distance2D(gProtPos[PROT_RADAR][i]) < rr * 0.8f))
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
	for (uint i = 0; i < pts.length(); ++i) {
		if (!OnMap(pts[i]) || RadarSees(pts[i]))
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
const int CLOSE_RAYS = 16;
float LineClosure(const AIFloat3& in extraAt, float extraReach)
{
	PfRebuild();
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

void ClosurePrep()
{
	gClRingOk = false;
	gClRingP.resize(0);
	gClRingOpen.resize(0);
	PfRebuild();
	AIFloat3 c;
	float extent = 0.f;
	if (!BaseCentroid(c, extent))
		return;
	const float ring = extent + Military::FoeReach();
	if (ring <= 1.f)
		return;
	gClRingOk = true;
	for (int b = 0; b < CLOSE_RAYS; ++b) {
		const float ang = 6.2831853f * float(b) / float(CLOSE_RAYS);
		const AIFloat3 p = c + AIFloat3(cos(ang), 0.f, sin(ang)) * ring;
		bool open = OnMap(p);
		for (uint i = 0; open && (i < gPfTwPos.length()); ++i) {
			if (gPfTwPos[i].distance2D(p) <= gPfTwReach[i])
				open = false;
		}
		gClRingP.insertLast(p);
		gClRingOpen.insertLast(open);
	}
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

bool ProtCovered(int cls, const AIFloat3& in pos, float r)
{
	for (uint i = 0; i < gProtPos[cls].length(); ++i) {
		if (pos.distance2D(gProtPos[cls][i]) < r)
			return true;
	}
	// ONE ALREADY COMING COVERS THIS GROUND. gProtPos is written at
	// AiUnitFinished, so ground a half-built anti-nuke already answers read as
	// answered by nothing and the market sited a second one beside it.
	for (uint i = 0; i < Requests::gLive.length(); ++i) {
		IUnitTask@ t = Requests::gLive[i];
		if ((t is null) || t.IsDead() || (t.buildDef is null))
			continue;
		if (ProtClassOf(int(t.buildDef.id)) != cls)
			continue;
		const AIFloat3 where = t.GetBuildPos();
		if (OnMap(where) && (pos.distance2D(where) < r))
			return true;
	}
	// ...and so does one nobody is working: the frame is standing whether or
	// not a request still remembers it.
	Requests::PendSweep();
	for (uint i = 0; i < Requests::gPendId.length(); ++i) {
		if (ProtClassOf(Requests::gPendDef[i]) != cls)
			continue;
		if (pos.distance2D(Requests::gPendPos[i]) < r)
			return true;
	}
	return false;
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
//------------------------------------------------------------------------------
// TARGETS, not appetites.
//
// Army has had a target since the beginning and so it SATURATES: build until
// ArmyValue reaches ArmyTarget and the gap closes. Static defence never had
// one. It was bought marginally, turret by turret, priced as "expected loss
// prevented" with no notion of enough -- and its marginal value never decayed,
// because the hazard it multiplies is floored by a prior that scales with our
// OWN economy. So defence tracked the economy at a fixed ratio forever:
// measured 175% of eco against stock BARb's 52%, on a quarter of their income.
//
// A target is also how a role says what it is FOR without anyone being
// forbidden anything (apexearth: "why not just have eco players with
// ArmyTarget and DefenseTarget at 0? Make AATarget too?"). The rear
// specialist's numbers fall out near zero because nothing reaches it -- and
// rise again on their own if something does.
//------------------------------------------------------------------------------

// MINIMUM PROTECTION PER MEX, in turret metal.
//
// The rest of this file prices defence against what it can SEE arriving. That
// is right for a contested lane and useless for the opening: a fresh mex has
// never been shot at, so its wave reads zero, so it is not a candidate at all.
// This is the other half -- what a mex is worth covering before anything has
// happened to it -- expressed in the faction's own light tower so it means the
// same thing on every faction and at every tier.
float MexCoverFloorM()
{
	return ai.GetTunable("apex_mex_cover_floor", TUNE_MEX_COVER_FLOOR)
			* LightTowerCostM();
}

// How many mexes of ours are standing. A claim that has not finished has no
// extraction and is not one.
int OwnMexCount()
{
	int n = 0;
	for (uint i = 0; i < gLExtract.length(); ++i) {
		if (gLExtract[i] > 0.f)
			++n;
	}
	return n;
}

// Is this position one of our standing mexes? Diagnostics only: it is how
// "did it cover the spot it was standing on" is read off a log.
bool SiteIsMex(const AIFloat3& in pos)
{
	for (uint i = 0; i < gLPos.length(); ++i) {
		if ((gLExtract[i] > 0.f) && (gLPos[i].distance2D(pos) < 200.f))
			return true;
	}
	return false;
}

// Would a post here cover a standing mex? The per-mex floor is a claim about
// mexes, and a guard site is the value-weighted centre of a cluster rather
// than the extractor itself, so the floor asks about reach and not identity.
bool MexInReach(const AIFloat3& in pos, float r)
{
	for (uint i = 0; i < gLPos.length(); ++i) {
		if ((gLExtract[i] > 0.f) && (gLPos[i].distance2D(pos) < r))
			return true;
	}
	return false;
}

// Static ground defence we own, in metal.
float DefenceValue()
{
	float m = 0.f;
	for (uint i = 0; i < gProtDefId[PROT_DEF].length(); ++i)
		m += Catalog::gCostM[gProtDefId[PROT_DEF][i]];
	return m;
}

// What the wave arriving at OUR ground is worth, less the share our own mobile
// army answers, converted to turret metal at the same exchange rate coverage
// uses. Everything here is measured at home: a player nothing reaches wants no
// turrets, which is the whole of the rear specialist's case.
float DefenceTarget()
{
	if (!Builder::gHomeSet)
		return 0.f;
	// A CREDIBLE WAVE BEFORE ANYTHING IS SEEN. ThreatM at our own base is what
	// has actually arrived there, which is nothing until it is -- and a target
	// of zero until the first raider lands is a strategy of owning no defence.
	// The floor is the same symmetric expectation ArmyTarget already uses (they
	// had our start and our minutes), taking the share of it that could reach
	// this base. Defence is excluded from that basis, so it cannot buy itself.
	float threat = ThreatM(Builder::gHomePos);
	{
		const float expected = ArmyTargetFull();
		// ...scaled by how exposed WE are of the team. The wave reaches the
		// front players first; the rear player is answered by the four in
		// front of it, not by turrets it has not built.
		const float floorM = expected
				* ai.GetTunable("apex_def_prior_share", TUNE_DEF_PRIOR_SHARE)
				* TeamExposure();
		if (floorM > threat)
			threat = floorM;
	}
	// The per-mex floor is a target too. The site loop below will not buy a
	// turret the global target says we already have enough of, so the two must
	// agree about the floor or it never gets built.
	const float mexFloor = MexCoverFloorM() * float(OwnMexCount());
	if (threat <= 1.f)
		return mexFloor;
	const float share = ai.GetTunable("apex_def_army_share", TUNE_DEF_ARMY_SHARE);
	// ...and what the TEAM already holds here. Same reason ShortfallAt counts
	// ally influence: the rear player's ground is answered by four teammates,
	// not by turrets it has not built.
	// OUR OWN ARMY, not the team's. Military::OurArmyNow() sums the whole
	// alliance, so every player subtracted all eight players' army from its own
	// local wave and every defence target came out zero (measured: threat 2550,
	// ourArmy 11003, target 0 on all eight).
	float unanswered = threat - ArmyValue() * share;
	if (unanswered <= 0.f)
		return mexFloor;
	const float trade = ai.GetTunable("apex_def_trade", TUNE_DEF_TRADE);
	float t = unanswered / ((trade > 0.f) ? trade : 2.f);
	if (EcoRoleActive())
		t *= ai.GetTunable("apex_eco_def_mul", TUNE_ECO_DEF_MUL);
	// ...and the floor applies to the rear specialist as well. apex_eco_def_mul
	// defaults to 0 on the argument that four teammates stand in front of it --
	// which is true of the wave and not of a raider that walked around them,
	// and the rear is where the economy lives.
	if (mexFloor > t)
		t = mexFloor;
	return (t > 0.f) ? t : 0.f;
}

// How much of each target is still unmet, as a fraction. The want's gain is
// scaled by this, so the last turret before the target prices at nearly
// nothing and the first one after it prices at zero -- the same shape as the
// army gap, and the reason neither runs away.
float TargetFill(float have, float target)
{
	if (target <= 0.f)
		return 0.f;
	const float gap = target - have;
	if (gap <= 0.f)
		return 0.f;
	return (gap > target) ? 1.f : (gap / target);
}

int gNextTargetLog = 0;
void TargetLog()
{
	if (ai.frame < gNextTargetLog)
		return;
	gNextTargetLog = ai.frame + 60 * SECOND;
	AiLog("apex: targets t=" + ai.teamId
		+ " def=" + int(DefenceValue()) + "/" + int(DefenceTarget())
		+ " aa=" + int(gProtDefId[PROT_AA].length())
		+ " army=" + int(ArmyValue()) + "/" + int(ArmyTarget())
		+ " threatHome=" + int(Builder::gHomeSet ? ThreatM(Builder::gHomePos) : 0.f)
		+ " floor=" + int(ArmyTargetFull() * ai.GetTunable("apex_def_prior_share", TUNE_DEF_PRIOR_SHARE))
		+ " expo=" + formatFloat(TeamExposure(), "", 0, 2)
		+ " ourArmy=" + int(ArmyValue())
		+ " eco=" + (EcoRoleActive() ? 1 : 0));
}

Want@ ProposeProtectHalf(CCircuitUnit@ unit, int half)
{
	Want w;
	if (gAssetsM < 1.f)
		return w;
	// DEFENCE MUST NOT WAIT ON A NANO. This used to require gFarmSet, which
	// only flips when the first nano TURRET finishes -- measured at frame
	// 5718, so no LLT, AA, radar or shield could even be proposed for the
	// first 3.2 minutes, which is exactly when raiders take undefended mexes
	// and solars (apexearth, watched: "we made several solars/mexes which we
	// did not protect with a sentry turret... our llt defense early game is
	// not strong enough"). The farm is only ever a DEFAULT POSITION; the
	// anchor serves before it exists, and PROT_DEF/PROT_RADAR pick their own
	// sites anyway.
	const int ruid = int(unit.circuitDef.id);
	if (int(gNextDefRankOf.length()) <= Catalog::gDefCount)
		gNextDefRankOf.resize(Catalog::gDefCount + 1);
	const bool rankNow = (half == HALF_GROUND)
			&& (ai.frame >= gNextDefRankOf[ruid]);
	if (rankNow) {
		gDefRankDef.resize(0);
		gDefRankV.resize(0);
	}
	const int uid = int(unit.circuitDef.id);
	const array<int>@ builds = Catalog::BuildsOf(uid);
	const float rate = ai.GetTunable("apex_insure_rate", TUNE_INSURE_RATE);
	// (Normalising the TTD discount against the quickest buildable turret --
	// so defence as a category paid nothing and only the ordering inside it
	// moved -- was tried and REVERTED: it raised defence's share of spend but
	// bought MORE of the slow turret, not less (Agitator 24% -> 38% of defence
	// metal, quick turrets 57% -> 46%, over 54 games each). The absolute
	// discount below is what actually moves the mix.)
	AIFloat3 core = gFarmPos;
	if (!gFarmSet) {
		core = Base::gAnchorSet ? Base::gAnchor : Builder::gHomePos;
		if (!OnMap(core))
			return w;
	}
	for (uint i = 0; i < builds.length(); ++i) {
		const int d = builds[i];
		if (!Catalog::gAvailable[d] || Catalog::gMobile[d]
			|| Catalog::gFloater[d] || Catalog::gSub[d])
			continue;
		const int cls = ProtClassOf(d);
		if (cls < 0)
			continue;
		if (HalfOfClass(cls) != half)
			continue;
		// Recorded HERE, before any gate: a candidate that never reaches the
		// price is exactly the one worth seeing, and a list built at the end
		// cannot show it. -1 means "classed as a turret and then dropped".
		if (rankNow && (cls == PROT_DEF)) {
			gDefRankDef.insertLast(d);
			gDefRankV.insertLast(-1.f);
		}
		float gain = 0.f;
		AIFloat3 at = core;
		if (cls == PROT_RADAR) {
			AIFloat3 gapAt;
			float unseenFrac = 0.f;
			if (!RadarGap(unit.GetPos(ai.frame), gapAt, unseenFrac))
				continue;
			at = gapAt;
			// Eyes for the army too: blind units chase shadows (apexearth:
			// "build radars so our units have intelligence"). Worth what is
			// still unwatched, so coverage follows the front instead of one
			// tower sitting at home for the whole game.
			gain = (gAssetsM + ArmyValue()) * rate * unseenFrac;
		} else if (cls == PROT_JAM) {
			// Tower concentrations want jamming first (apexearth): find a
			// cluster of >=3 defenses with no jammer in reach.
			AIFloat3 jat = core;
			bool found = false;
			for (uint jd = 0; jd < gProtPos[PROT_DEF].length() && !found; ++jd) {
				int nearDef = 0;
				for (uint jk = 0; jk < gProtPos[PROT_DEF].length(); ++jk) {
					if (gProtPos[PROT_DEF][jd].distance2D(gProtPos[PROT_DEF][jk]) < 300.f)
						++nearDef;
				}
				if ((nearDef >= 3)
					&& !ProtCovered(PROT_JAM, gProtPos[PROT_DEF][jd],
							Catalog::gJamR[d] * 0.8f))
				{
					jat = gProtPos[PROT_DEF][jd];
					found = true;
				}
			}
			if (!found && ProtCovered(PROT_JAM, core, Catalog::gJamR[d] * 0.8f))
				continue;
			// A JAMMER DENIES RADAR, so it is worth nothing until something is
			// USING radar against us -- indirect fire that shoots what it cannot
			// see. Priced on assets alone it won an early sense ticket over the
			// sentries and mexes we actually needed (apexearth, watched: "we're
			// making a jammer long before it would ever provide value"). Same
			// shape as the shield gate below, and for the same reason.
			const float indirect = Military::EnemyCostOf(Unit::Role::ARTY.type)
					+ Military::EnemyCostOf(Unit::Role::SKIRM.type) * 0.5f;
			if (indirect < 200.f)
				continue;
			at = found ? jat : core;
			gain = ((indirect < gAssetsM) ? indirect : gAssetsM)
					* rate * (found ? 0.8f : 0.5f);
		} else if (cls == PROT_SHIELD) {
			// Shields answer bombardment: worth the arty mass they blank,
			// covering the interior (the stock feature our gap survey ranked
			// first; their arty ground our statics 38k:7k).
			const float artyS = Military::EnemyCostOf(Unit::Role::ARTY.type)
					+ Military::EnemyCostOf(Unit::Role::SKIRM.type) * 0.5f;
			if (artyS < 200.f)
				continue;
			// ...and only when a threat is actually NEAR: a global arty
			// census bought shield stacks in a base nothing could reach
			// (apexearth: "too many shields while theres still no threat
			// very close"). The bombardier must be within twice its reach
			// of what the shield would cover.
			if (ai.GetEnemyCostAt(core, 1800.f) < 200.f)
				continue;
			if (ProtCovered(PROT_SHIELD, core, 400.f))
				continue;
			gain = ((artyS < gAssetsM) ? artyS : gAssetsM) * rate * 4.f;
		} else if (cls == PROT_AA) {
			// AS SOON AS WE HAVE SEEN ANY (apexearth: "just make the AA if
			// we've seen enemy air... it doesn't have to be a ton"). Sized off
			// AirSeenEver, which has no AA_IGNORE floor and no freshness
			// window: a bomber that has flown home is still a bomber, and
			// AirThreatNow read zero for exactly the moments between raids.
			// OUR SHARE OF A SIDE-WIDE READING: the enemy census sums what the
			// whole team can see, and each of us covers our own base, so charging
			// one player the team's answer builds it once per ally. RoleTarget
			// already divides the same census on the mobile side.
			const float allies = Military::AllyCount();
			float air = Military::AirSeenEver()
					/ ((allies > 1.f) ? allies : 1.f);
			// The rear specialist is a FATTER TARGET than its share suggests:
			// it holds the team's economy, builds no ground defence, and keeps
			// no army over its base, so bombers that get past the front go
			// there. It carries a larger share of the same census, which the
			// saturation point below then turns into proportionally more AA.
			if (EcoRoleActive())
				air *= ai.GetTunable("apex_eco_aa_mult", TUNE_ECO_AA_MULT);
			if (air <= 0.f)
				continue;
			// WHAT THE BOMBS ARE ACTUALLY COSTING US, priced like a turret:
			// the metal/s we are measurably losing to aircraft, times the
			// share of their air this tower newly stops. The old form was an
			// insurance rate on the base with a x4 urgency fudge bolted on,
			// which read ~1 metal/s while bombers ate the economy -- and it
			// lost every auction (apexearth, watched: "T1 anti air is very
			// cheap yet we still have not made it... I estimate a team cost
			// of around 250-300 would have saved us more than that").
			// AA metal counted against air metal at the cover ratio, so cover
			// reaches the target -- and the want prices itself out -- at
			// exactly apex_aa_cover_frac of our share of the air we have seen.
			// No count, no cap. Mobile AA over the base counts here too, so the
			// two AA budgets saturate against each other instead of both
			// answering the same bombers.
			float aaFrac = ai.GetTunable("apex_aa_cover_frac", TUNE_AA_COVER_FRAC);
			if (aaFrac < 0.01f)
				aaFrac = 0.01f;
			const float aaTrade = 1.f / aaFrac;
			float aaCover = MobileAACoverM() * aaTrade;
			for (uint ai2 = 0; ai2 < gProtDefId[PROT_AA].length(); ++ai2)
				aaCover += Catalog::gCostM[gProtDefId[PROT_AA][ai2]] * aaTrade;
			const float aaAdds = Catalog::gCostM[d] * aaTrade;
			float aShort0 = (air - aaCover) / air;
			if (aShort0 < 0.f)
				aShort0 = 0.f;
			float aShort1 = (air - (aaCover + aaAdds)) / air;
			if (aShort1 < 0.f)
				aShort1 = 0.f;
			const float stopped = aShort0 - aShort1;
			if (stopped <= 0.f)
				continue;
			// THE SAME THREE TERMS AS A GROUND TURRET: what is at risk, how
			// often it gets hit, and the share this tower newly stops. AA used
			// an insurance rate on min(their air, our base), which capped the
			// value at risk by the SIZE of their air force -- and `stopped`
			// already measures our cover against exactly that force. That is
			// the double count ThreatM records and rejects on the ground side,
			// and it is why AA priced at gain=0.09 against energy's 4.75 and we
			// fielded exactly one Nettle per game however many bombers came.
			//
			// Turrets are excluded from the stake for the same reason
			// SiegeRiskAt excludes them: defence must not be its own reason.
			// Saturation is arithmetic -- every tower raises aaCover, which
			// lowers both the arrival rate and the next tower's share.
			float econA = gAssetsM - gProtM;
			if (econA < 0.f)
				econA = 0.f;
			const float horizA = ai.GetTunable("apex_exposed_loss_s", TUNE_EXPOSED_LOSS_S);
			const float anchorA = 1.f / ((horizA > 1.f) ? horizA : 120.f);
			const float airHz = anchorA * (air / (air + aaCover))
					* ai.GetTunable("apex_aa_urgency", TUNE_AA_URGENCY);
			float gainA = econA * airHz * stopped;
			// Measured losses are a FLOOR, not the whole price: they are what
			// air has already cost us, which arrives after the mex is dead.
			const float measured = Military::AirLossRate() * stopped;
			gain = (measured > gainA) ? measured : gainA;
		} else if (cls == PROT_TARGFAC) {
			// apexearth's spec: three wanted, diminishing.
			const int have = int(gProtPos[PROT_TARGFAC].length());
			const int want3 = int(ai.GetTunable("apex_targfac_want", TUNE_TARGFAC_WANT));
			if (have >= want3)
				continue;
			gain = gAssetsM * rate * float(want3 - have) / float(want3);
		} else if (cls == PROT_DEF) {
			// ONE AUCTION OVER PLACES, not an ordered cascade. Gain is the
			// expected loss this turret would PREVENT: the stake standing in
			// its reach, times how often lethal force arrives there, times
			// the share of the local threat it newly stops.
			//
			// Diminishing returns are arithmetic here rather than a crowding
			// divisor -- once standing cover already exceeds the threat, the
			// next turret prevents nothing and prices itself out. That is
			// also what retired the quiet-rear veto: a rear nothing can
			// reach has no threat, so it buys no towers without being
			// forbidden to.
			const float trade = ai.GetTunable("apex_def_trade", TUNE_DEF_TRADE);
			const float reach = (Catalog::gMaxRange[d] > 1.f)
					? Catalog::gMaxRange[d] : 500.f;
			const float adds = PfTowerKill(d);
			const float mexFloorWave = MexCoverFloorM() * trade;
			// THE WAVE A POST MUST BEAT IS THE ONE THAT ARRIVES TOGETHER, not
			// the reading at this instant. Under that floor one cheap tower
			// saturates the shortfall -- measured, `short=1.00->0.00` off a
			// single Beamer -- and everything a heavy gun brings past it is
			// discarded by the clip below while its full metal and energy bill
			// is charged, so the auction can only ever buy the cheapest turret
			// in the list. Same symmetric expectation DefenceTarget already
			// floors on, apportioned by the share of our worth standing in
			// this post's reach: near zero early, and it grows with the army.
			const float siteWave = ArmyTargetFull()
					* ai.GetTunable("apex_def_prior_share", TUNE_DEF_PRIOR_SHARE)
					* TeamExposure();
			const double _tSites = Perf::T0();
			array<AIFloat3> sites;
			// GUARD SITES COME FROM THE BUILDINGS. The two ring generators this
			// replaced -- a circle of radius (base extent + turret reach) about
			// the metal centroid, and polar rings layered inward around home --
			// both described the start position rather than what we own
			// (apexearth: "our base defense only builds in a circle around
			// where we started... we should be interested in defending any/all
			// buildings that we have"). PfGuardSites buckets every standing
			// structure at the turret's own reach and returns the value-
			// weighted centre of each cluster, so a post is offered wherever
			// our metal actually stands and nowhere else.
			PfGuardSites(reach, sites);
			// Sites below this index guard something of ours; sites at or above
			// it are the line. The two are priced differently -- see below.
			const uint nAsset = sites.length();
			// THE LINE ITSELF, and the choke behind it. FrontBuildSpots is the
			// measured territory edge per bearing, already set back so the
			// builder is not standing in the fight -- not a ring about home.
			if (Base::gAnchorSet) {
				AIFloat3 cp;
				if (Front::FrontChoke(Base::gAnchor, cp)) {
					AIFloat3 site;
					if (!Front::BehindChoke(cp, 180.f, site))
						site = cp;
					sites.insertLast(site);
				}
			}
			if (ai.GetTunable("apex_front_line", TUNE_FRONT_LINE) > 0.f) {
				array<AIFloat3> line;
				if (Military::FrontBuildSpots(line)) {
					for (uint fi = 0; fi < line.length(); ++fi)
						sites.insertLast(line[fi]);
				}
			}
			// WHAT THE PRICE WILL CHARGE FOR GETTING THERE.
			//
			// The loop below used to rank sites on the raw loss a turret
			// prevents and hand the winner to ValueOf, which only then charged
			// the walk. So the builder standing on the mex it had just finished
			// was sent across the base to whichever site scored marginally
			// higher, and the tower it should have put down where it stood was
			// never proposed at all -- apexearth: "units making mex and then
			// not immediately making the light tower to cover it".
			Perf::Add("prot.sites", _tSites);
			const double _tLoop = Perf::T0();
			const float wage = Wage();
			const float walkW = ai.GetTunable("apex_def_site_walk",
					TUNE_DEF_SITE_WALK);
			const float uSpeed = Catalog::gSpeed[uid];
			const AIFloat3 uPos = unit.GetPos(ai.frame);
			const float kCost = Catalog::gCostM[d]
					+ Catalog::BuildSecondsAt(d,
							EffBP(Catalog::gBuildPower[uid])) * wage;
			AIFloat3 bestAt = at;
			float bestGain = 0.f;
			float bestScore = 0.f;
			bool bestIsFront = false;
			// Closure as it stands, computed once: it does not depend on which
			// candidate site we are pricing.
			ClosurePrep();
			// Same as the field sweep: the side-wide half of threat, hazard
			// and the siege prior does not depend on the site being priced.
			RiskFill();
			RiskFillSiege();
			const float siegeFrac = ai.GetTunable("apex_enemy_prior",
					TUNE_ENEMY_PRIOR);
			for (uint si = 0; si < sites.length(); ++si) {
				const AIFloat3 s = sites[si];
				if (!OnMap(s))
					continue;
				const bool isFront = (si >= nAsset);
				float threat = isFront ? ThreatAt(s) : PfSiteThreat(si);
				// A mex nothing has attacked yet still has to be able to meet
				// the floor. Judged by whether one stands in this post's reach,
				// since a guard site is a cluster centre rather than the mex.
				const bool floored = !isFront && MexInReach(s, reach)
						&& (mexFloorWave > threat);
				if (floored)
					threat = mexFloorWave;
				// ...and the share of the expected wave this post's own ground
				// is worth. gPfTotal is everything we own, so a post covering a
				// tenth of the base faces a tenth of the wave.
				if ((siteWave > 0.f) && (gPfTotal > 1.f)) {
					const float sStake = isFront
							? FrontedStakeAt(s, reach) : PfSiteStake(si);
					float shr = sStake / gPfTotal;
					if (shr > 1.f)
						shr = 1.f;
					const float wHere = siteWave * shr;
					if (wHere > threat)
						threat = wHere;
				}
				if (threat <= 1.f)
					continue;
				// FRONT AND GUARD ARE PRICED, NOT RANKED (apexearth: front and
				// shoreline defence preferred, "these structure guarding
				// defenses are just backup if the frontline fails or leaks
				// enemy units inside"). A line post keeps the shielded credit
				// for everything standing behind it -- to the extent it CLOSES
				// the net, so plugging the last hole is worth the whole base
				// and a redundant post beside an existing one is worth nothing.
				// A guard post is worth only what stands in its own reach. So
				// the line wins wherever it still shields something, and a
				// guard post wins once something inside is actually at risk,
				// without either being forbidden.
				float stake = (isFront || (reach < 64.f))
						? FrontedStakeAt(s, reach) : PfSiteStake(si);
				if (isFront) {
					const float dClose = ClosureAdds(s, reach);
					stake += ShieldedStakeAt(s, reach) * dClose;
				}
				if (stake <= 1.f)
					continue;
				// BOTH READINGS THROUGH ONE FUNCTION. short1 asks CoverWith
				// what the field would measure with this turret standing at s,
				// so a post that cannot raise the weakest bearing prevents
				// nothing -- which is what makes an in-base carpet price itself
				// out while a forward post or an out-ranging turret does not.
				// Both reads come out of the field for a guard site: cover
				// at a place does not depend on which turret is being priced,
				// and what one more turret standing there would ADD is a
				// constant across the standoff ring rather than a second sweep.
				const float cover0 = isFront ? CoverAt(s) : PfSiteCover(si);
				const float cover1 = cover0 + CoverAddsAt(s, reach, adds);
				float short0 = (threat - cover0) / threat;
				if (short0 < 0.f)
					short0 = 0.f;
				float short1 = (threat - cover1) / threat;
				if (short1 < 0.f)
					short1 = 0.f;
				float stopped = short0 - short1;
				// A FLOOR IS FILLED IN STEPS, NOT MET IN ONE JUMP. Against a
				// wave we can see, the share a turret newly stops is the right
				// price and it falls as cover rises. Against the floor -- a
				// wave nobody has seen -- that same arithmetic made each turret
				// worth LESS the higher the floor was set, because one tower is
				// a smaller fraction of a bigger assumed wave.
				if (floored) {
					const float gained = cover1 - cover0;
					float step = mexFloorWave - cover0;
					if (step > gained)
						step = gained;
					stopped = (gained > 0.f) ? (step / gained) : 0.f;
				}
				if (stopped <= 0.f)
					continue;
				// The siege prior BUYS THE ANSWER, it does not only forbid the
				// bet. Self-limiting: SiegeRisk falls as CoverAt rises, so each
				// turret lowers the price of the next.
				const float hazard = isFront ? HazardWith(s, cover0) : PfSiteHz(si);
				float hz = hazard;
				const float sg = isFront ? SiegeWith(s, cover0, siegeFrac)
						: PfSiteSiege(si);
				if (sg > hz)
					hz = sg;
				// A post against the map edge faces FEWER approaches, so the
				// wave it must beat is smaller in proportion.
				float prevented = stake * hz * stopped;
				prevented *= Military::OpenFraction(s, reach);
				// ...AND THE WORTH IT GIVES BACK. A building nothing guards is
				// worth apex_unprot_discount less to us than the same building
				// behind a gun, and covering it restores that share. Same
				// function the discount itself is read from, so the two halves
				// of "unprotected buildings are worth less, defence makes them
				// worth more" cannot drift apart.
				{
					const float k = ai.GetTunable("apex_unprot_discount",
							TUNE_UNPROT_DISCOUNT);
					if (k > 0.f) {
						const float f0 = (cover0 < threat)
								? (cover0 / threat) : 1.f;
						const float f1 = (cover1 < threat)
								? (cover1 / threat) : 1.f;
						if (f1 > f0)
							prevented += stake * k * (f1 - f0) * hz;
					}
				}
				if (isFront) {
					if (prevented > gDbgFrontBest) gDbgFrontBest = prevented;
				} else if (prevented > gDbgAssetBest) {
					gDbgAssetBest = prevented;
				}
				// The same denominator ValueOf builds: the builder's idle
				// seconds, plus the income the asset forgoes by starting late.
				const float wSec = ((uSpeed > 1.f)
						? (uPos.distance2D(s) / uSpeed) : 60.f) * walkW;
				const float score = prevented
						/ (kCost + wSec * wage + prevented * wSec);
				if (score > bestScore) {
					bestScore = score;
					bestGain = prevented;
					bestAt = s;
					bestIsFront = isFront;
					gDbgStake = stake;
					gDbgHz = hz;
					gDbgSiege = sg;
					gDbgHazard = hazard;
					gDbgShort0 = short0;
					gDbgShort1 = short1;
					gDbgThreat = threat;
					gDbgCover0 = cover0;
					gDbgCover1 = cover1;
				}
			}
			Perf::Add("prot.loop", _tLoop);
			gDbgLineN = int(sites.length() - nAsset);
			if (bestGain <= 0.f)
				continue;
			// SATURATE. Every other major want has a target it reaches and then
			// stops asking; ground defence never had one, so it was bought
			// marginally forever at a value that never decayed -- the hazard it
			// multiplies is floored by a prior scaling with our OWN economy, so
			// turrets simply tracked the economy: 175% of it, against stock's 52%.
			// This is the same shape the AA branch above already uses against
			// AirSeenEver, and the same shape ArmyTarget has always had.
			// TIME TO DEFENCE (apexearth: "we need to build the quicker
			// defenses there on the front line. TTD can be very important").
			// A turret prevents nothing while it is still a nanoframe, so its
			// gain is worth only the share of the threat window it will
			// actually be standing for -- the same temporal-consistency
			// discount ProposePlant applies to a lab's first constructor and
			// EPriceAt applies to energy.
			//
			// Build time barely reached the price before this: it entered only
			// as BuildSecondsAt * Wage, about 116 metal against an Agitator's
			// 1300, so a turret taking seven times as long as a Guard paid
			// about nine percent for the privilege. Measured, 94% of the
			// Agitators we lost died unfinished.
			//
			// The horizon is apex_exposed_loss_s -- the window this AI already
			// uses for "an exposed asset is expected to be lost" -- so a turret
			// that takes as long to build as the thing it guards takes to die
			// is worth half. Reused rather than invented; apex_def_ttd_h
			// separates the two if the front wants sharper pressure than the
			// rear.
			{
				const float ttdH = ai.GetTunable("apex_def_ttd_h", TUNE_DEF_TTD_H);
				const float bSec = Catalog::BuildSecondsAt(d,
						EffBP(Catalog::gBuildPower[uid]));
				if ((ttdH > 1.f) && (bSec > 0.f))
					bestGain *= ttdH / (ttdH + bSec);
			}
			gain = bestGain * TargetFill(DefenceValue(), DefenceTarget());
			if (gain <= 0.f)
				continue;
			at = bestAt;
			if (ai.frame >= gNextDefPriceLog) {
				gNextDefPriceLog = ai.frame + 30 * SECOND;
				AiLog("apex: defprice t=" + ai.teamId
					+ " gain=" + formatFloat(gain, "", 0, 2)
					+ " stake=" + formatFloat(gDbgStake, "", 0, 0)
					+ " threat=" + formatFloat(gDbgThreat, "", 0, 0)
					+ " cover=" + formatFloat(gDbgCover0, "", 0, 0)
					+ "->" + formatFloat(gDbgCover1, "", 0, 0)
					+ " short=" + formatFloat(gDbgShort0, "", 0, 2)
					+ "->" + formatFloat(gDbgShort1, "", 0, 2)
					+ " hz=" + formatFloat(gDbgHz, "", 0, 5)
					+ " (hazard=" + formatFloat(gDbgHazard, "", 0, 5)
					+ " siege=" + formatFloat(gDbgSiege, "", 0, 5) + ")"
					+ " | econM=" + formatFloat(gAssetsM - gProtM, "", 0, 0)
					+ " protM=" + formatFloat(gProtM, "", 0, 0)
					+ " army=" + formatFloat(ArmyValue(), "", 0, 0)
					+ " foeSeen=" + formatFloat(Military::EnemyArmyCost(), "", 0, 0)
					+ " | mex=" + OwnMexCount()
					+ " mexFloor=" + int(MexCoverFloorM() * float(OwnMexCount()))
					+ " defHave=" + int(DefenceValue())
					+ " defTarget=" + int(DefenceTarget()));
			}
			NoteDefSite(bestIsFront);
			// Is the chosen post in FRONT of the base or behind it? He reports
			// towers landing behind, which the site list alone cannot show.
			if (ai.frame >= gNextDefFwdLog) {
				gNextDefFwdLog = ai.frame + 30 * SECOND;
				AiLog("apex: defplace " + Catalog::Def(d).GetName()
					+ " walk=" + int(unit.GetPos(ai.frame).distance2D(bestAt))
					+ " mexSite=" + ((SiteIsMex(bestAt)) ? 1 : 0)
					+ " fwd=" + formatFloat(Military::ForwardFraction(bestAt), "", 0, 2)
					+ " anchorFwd=" + formatFloat(Base::gAnchorSet
						? Military::ForwardFraction(Base::gAnchor) : -9.f, "", 0, 2)
					+ " front=" + (bestIsFront ? 1 : 0)
					// Distance to the nearest map wall, and the share of the
					// approach that is real map there. The wall used to PAY.
					+ " edgeD=" + int(EdgeDist(bestAt))
					+ " open=" + formatFloat(Military::OpenFraction(bestAt, 500.f), "", 0, 2)
					+ " gain=" + formatFloat(bestGain, "", 0, 2));
			}
		}
		if (gain <= 0.f)
			continue;
		Want c;
		const float speed = Catalog::gSpeed[uid];
		const float walkSec = (speed > 1.f)
				? (unit.GetPos(ai.frame).distance2D(at) / speed) : 60.f;
		ValueOf(d, gain, walkSec, Catalog::gBuildPower[uid], c);
		if (rankNow && (cls == PROT_DEF) && (gDefRankDef.length() > 0))
			gDefRankV[gDefRankV.length() - 1] = c.value;
		if (c.value > w.value) {
			w = c;
			w.kind = (half == HALF_SENSE) ? WK_SENSE
					: ((half == HALF_AIRDEF) ? WK_AIRDEF : WK_PROTECT);
			@w.def = Catalog::Def(d);
			w.pos = at;
			w.spotId = cls;
		}
	}
	if (rankNow && (gDefRankDef.length() > 0)) {
		gNextDefRankOf[ruid] = ai.frame + 60 * SECOND;
		string r = "";
		for (uint q = 0; q < gDefRankDef.length(); ++q) {
			r += " " + Catalog::Def(gDefRankDef[q]).GetName()
				+ "=" + formatFloat(gDefRankV[q], "", 0, 4);
		}
		// ...and what this builder could offer but never did. A candidate list
		// of two out of a T2 constructor is a filter question, not a price one.
		string dropped = "";
		for (uint q2 = 0; q2 < builds.length(); ++q2) {
			const int dq = builds[q2];
			if (Catalog::gMobile[dq] || (Catalog::gMaxRange[dq] <= 1.f))
				continue;
			if (Catalog::gAvailable[dq] && !Catalog::gFloater[dq]
				&& !Catalog::gSub[dq] && (ProtClassOf(dq) == PROT_DEF))
				continue;
			dropped += " " + Catalog::Def(dq).GetName()
				+ ":avail=" + (Catalog::gAvailable[dq] ? 1 : 0)
				+ ",float=" + (Catalog::gFloater[dq] ? 1 : 0)
				+ ",sub=" + (Catalog::gSub[dq] ? 1 : 0)
				+ ",cls=" + ProtClassOf(dq);
		}
		AiLog(Factory::T() + "apex: defrank by="
			+ unit.circuitDef.GetName() + " n=" + gDefRankDef.length() + r
			+ " | dropped:" + dropped);
	}
	return w;
}

// NO ROLE VETO HERE, DELIBERATELY. What the rear specialist should build is
// decided by what the want is WORTH to it -- covered ground behind teammates
// prices near nothing, so it loses the auction on arithmetic. apexearth:
// "if want for defence or army is 0 then we should have none. It should
// really be that simple."
Want@ ProposeProtect(CCircuitUnit@ unit)
{
	TargetLog();
	return ProposeProtectHalf(unit, HALF_GROUND);
}

Want@ ProposeSense(CCircuitUnit@ unit)
{
	return ProposeProtectHalf(unit, HALF_SENSE);
}

Want@ ProposeAirDef(CCircuitUnit@ unit)
{
	return ProposeProtectHalf(unit, HALF_AIRDEF);
}


}  // namespace Market
