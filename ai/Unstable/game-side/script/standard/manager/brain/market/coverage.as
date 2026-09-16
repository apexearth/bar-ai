namespace Market {
//------------------------------------------------------------------------------
// WHAT IS ACTUALLY DEFENDED, AND WHAT IS ACTUALLY BEING LOST.
//
// The protect market's risk terms were frozen constants: one global insurance
// rate, one loss horizon, and five hardcoded "is anything nearby" radii that
// asked no turret whether its weapon reaches. Both terms here are measured
// instead, so the same equations react on an axis they could not previously
// see -- and the loop closes on the enemy's behaviour rather than on our own
// opinion of how defended we look.
//------------------------------------------------------------------------------

// Standing defence that can actually SHOOT at pos, in metal of enemy wave it
// is expected to stop. A turret covers what its own weapon reaches; the flat
// radii counted an LLT and a Pulsar identically.
// THE ATTACKER NEVER STANDS ON THE TARGET. It stands at its own weapon range
// and shoots in, so a turret that merely reaches the mex denies nothing: the
// raider parks just outside the turret's range and kills the mex for free
// (apexearth: "If our tower has a mex in the outer edge of it's range then we
// count that as covered. But an enemy can just stand right next to that mex and
// still shoot it, while staying outside the range of the turret").
//
// So cover is measured on the RING of positions they can shoot from, and the
// value is the WEAKEST bearing on it -- they pick where to stand, not us. With
// no observed enemy reach yet the ring collapses to the point itself, which is
// the old behaviour.
// A CANDIDATE MUST BE PRICED THE WAY THE STANDING FIELD IS MEASURED. The
// marginal term below is a DIFFERENCE of this function against itself, so the
// proposed turret enters as a hypothetical member of gProtPos -- same ring,
// same weakest-bearing rule, same trade. Adding its cost to a ring reading
// compares a metal figure against a coverage figure, and the field never
// saturates: the Nth turret prices exactly like the first.
const int COVER_RAYS = 6;

// COVER IS KILLING POWER, NOT A PRICE TAG. Summing costM made every turret in
// the game identically strong per metal by construction, so ten Guards read as
// one Bulwark and the auction -- which divides by cost -- could never reach a
// heavy gun. PfTowerKill reports the same quantity in light-tower metal, so an
// LLT scores exactly what it used to and everything else scores what it is.
// `trade` is folded in there; the parameter stays for the callers that pass it.
float CoverPointM(const AIFloat3& in at, float trade,
		const AIFloat3& in extraAt, float extraReach, float extraM)
{
	PfRebuild();
	return PfCoverPoint(at, extraAt, extraReach, extraM);
}

// The standoff ring's bearings are the same COVER_RAYS for the whole game, and
// every site of every fill re-derived their sines and cosines.
array<float> gCrCos;
array<float> gCrSin;
void CoverRaysPrep()
{
	if (gCrCos.length() > 0)
		return;
	gCrCos.resize(uint(COVER_RAYS));
	gCrSin.resize(uint(COVER_RAYS));
	for (int b = 0; b < COVER_RAYS; ++b) {
		const float ang = 6.2831853f * float(b) / float(COVER_RAYS);
		gCrCos[uint(b)] = cos(ang);
		gCrSin[uint(b)] = sin(ang);
	}
}

// Latched: GetTunable is frozen for the game on first read, and these two are
// read once per candidate site of every defence fill (CoverWith) and again for
// the same site by CoverAddsAt.
bool  gCwTuneSet = false;
float gCwTradeV = 0.f;
bool  gCwStandoffOn = false;

void CwTuneFill()
{
	if (gCwTuneSet)
		return;
	gCwTuneSet = true;
	gCwTradeV = ai.GetTunable("apex_def_trade", TUNE_DEF_TRADE);
	gCwStandoffOn = ai.GetTunable("apex_standoff_cover", TUNE_STANDOFF_COVER) > 0.f;
}

float CoverWith(const AIFloat3& in pos, const AIFloat3& in extraAt,
		float extraReach, float extraM)
{
	// Posted guards cover a spot the same as turrets (apexearth: "a unit
	// protecting a building also should be counting as cover"); without
	// them a no-turret base read cover=0 everywhere and every dead mex spot
	// was priced as uncovered for as long as the loss memory lasted.
	// MOBILE COVER CANCELS A PERMANENT WANT. apexearth 2026-09-07: "I wonder
	// if we need the turret because the ground is unsafe, but then because a
	// con comes over with an escort, the escort adds safety and then defense
	// no longer perceived as necessary?" A posted guard counts here exactly
	// like a turret -- his own earlier ruling -- but a guard walks away and a
	// turret does not, so cover that will not be there tomorrow can still zero
	// today's shortfall and abort the build mid-walk. 1 = his ruling as it
	// stands; 0 measures the loop by removing the mobile half.
	const float unitCover = Military::UnitCoverAt(pos)
			* ai.GetTunable("apex_unit_cover", 1.f);
	if ((gProtPos[PROT_DEF].length() == 0) && (extraReach <= 0.f))
		return unitCover;
	CwTuneFill();
	const float trade = gCwTradeV;
	const float standoff = gCwStandoffOn ? Military::FoeReach() : 0.f;
	if (standoff <= 1.f)
		return CoverPointM(pos, trade, extraAt, extraReach, extraM) + unitCover;
	CoverRaysPrep();
	float worst = -1.f;
	// One traversal over the union of the ring, not one per bearing; a ring
	// entirely off the map falls back to the point, as it always did.
	if (PfCoverRing(pos, standoff, gCrCos, gCrSin,
			extraAt, extraReach, extraM, worst))
		return worst + unitCover;
	return CoverPointM(pos, trade, extraAt, extraReach, extraM) + unitCover;
}

// WHAT ONE MORE TURRET AT `pos` WOULD ADD TO THE COVER READ AT `pos`.
//
// CoverWith takes the WORST of the standoff ring, and a turret standing at the
// centre either reaches every point of that ring or none of them -- so its
// contribution is the same constant on every ray and the minimum shifts by
// exactly that constant. Reading it directly saves a second full ray sweep per
// candidate site per turret def, which was half of what made the defence price
// the most expensive thing in the market.
float CoverAddsAt(const AIFloat3& in pos, float reach, float adds)
{
	CwTuneFill();
	const float standoff = gCwStandoffOn ? Military::FoeReach() : 0.f;
	if (standoff <= 1.f)
		return adds;   // the point path: the turret stands on the point it covers
	CoverRaysPrep();
	for (int b = 0; b < COVER_RAYS; ++b) {
		const AIFloat3 fp = pos
				+ AIFloat3(gCrCos[uint(b)], 0.f, gCrSin[uint(b)]) * standoff;
		if (OnMap(fp))
			return (standoff <= reach) ? adds : 0.f;
	}
	return adds;   // no ray on the map: CoverWith falls back to the point path
}

float CoverAt(const AIFloat3& in pos)
{
	return CoverWith(pos, pos, -1.f, 0.f);
}

// THE STAKE AT A PLACE: our own metal standing within r, mexes counted at
// their capitalized stream rather than their build cost -- a 620m extractor
// earning 3 m/s is worth far more than 620 to lose. One value field, so
// raising what a mex is worth raises both how fast we claim it and how hard
// we insure it; a cluster is automatically worth more than a lone building,
// which is what collapses the old separate big-structure/cluster/mex rules
// into one number.
float StakeAt(const AIFloat3& in pos, float r)
{
	return PfStakeAt(pos, r);
}

// WHAT A POST SHIELDS RATHER THAN WHAT IT STANDS ON.
//
// StakeAt asks what a turret can shoot over, which is the right question at a
// mex and the wrong one on a line: a forward post's job is to stop the wave
// before it reaches the base behind it, and by that measure empty ground
// prices at zero. Anything BEHIND the post on the enemy axis and laterally
// inside its own weapon reach passes through its corridor, so it is what the
// post is bought to protect. Beyond `reach` only -- nearer value is already
// counted by StakeAt, and adding both would count it twice.
// ...along an EXPLICIT bearing. A front post faces the enemy; a perimeter post
// faces outward from the middle of our own footprint, which on a flank is
// nowhere near the same direction. With only the first form the argmax sits at
// the base centroid by construction and a rim post is worth its own disc.
float ShieldedStakeAlong(const AIFloat3& in pos, float reach,
		const AIFloat3& in dirIn)
{
	// Same corridor test, same assets; PfStakeShield walks the bucket index
	// instead of every asset we own, and hands the fill both this and the
	// in-reach stake out of one traversal.
	float inReach = 0.f;
	float beyond = 0.f;
	PfStakeShield(pos, reach, dirIn, true, inReach, beyond);
	return beyond;
}

// The enemy-facing form, unchanged for every existing caller. The TRUE enemy
// bearing, not Base::gFwd: gFwd is snapped to a cardinal, so on a map where
// the enemy sits diagonally the "is it behind me" test was wrong by up to 45
// degrees and rejected the entire base -- forward posts priced at exactly 0.00
// gain and never won an auction.
float ShieldedStakeAt(const AIFloat3& in pos, float reach)
{
	const AIFloat3 foe = aiEnemyMgr.GetEnemyPos();
	if (!OnMap(foe))
		return 0.f;
	return ShieldedStakeAlong(pos, reach, foe - pos);
}

// STAKE A POST ACTUALLY DEFENDS: plain distance, everything of ours inside
// this post's weapon range. Distance alone is honest -- a tower at the back of
// the base cannot reach a mex 800 elmos forward -- and the two sharper-looking
// forms are both wrong. A SIDE test ("is the post between this asset and the
// enemy") zeroes any home tower, since half the base is in front of it.
// Subtracting the attacker's standoff demands a post deny EVERY firing
// position; standoff is CoverAt's question and charging it twice double
// counts. ShieldedStakeAt adds what a FORWARD post intercepts beyond its own
// range, which is what makes the line worth building at all.
float FrontedStakeAt(const AIFloat3& in pos, float reach)
{
	return StakeAt(pos, reach);
}

// Is this mex defended -- the question the boolean radius test could not
// answer. Fraction of the local threat our standing coverage fails to stop.
// WHAT PROTECTS THIS GROUND IS NOT ONLY OURS.
//
// CoverAt sums OUR OWN towers and nothing else, so a rear player standing
// behind four teammates reads as completely unprotected -- the safest ground
// on the map, priced as the most dangerous. That number multiplies
// StreamSurvival, TechSurvival and the defence want's own size, so one wrong
// reading suppresses economy, tech and sensible defence together, and drives
// us to the one thing a rear player should not buy: more turrets of our own.
//
// apexearth: "we don't want to build this eco on unprotected ground. Sounds
// like the same eco role armytarget/defensetarget stuff needs to be
// considered in our protection desires too."
//
// Ally influence is the engine's own answer to who holds a piece of ground,
// and the frontline senses already read it. Counted at the same exchange
// rate as our own towers so the two are one currency.
// MEASURED, AND IT IS NOT WHAT IT SOUNDS LIKE: ai.GetAllyInflAt counts the
// whole ALLIANCE, ourselves included. In a 1v1 with no teammates at all it
// read 3.71 at our own base -- entirely our own units. It cannot answer "am I
// standing behind my team", which is the question, so nothing here may use it
// for that. The team-relative exposure below is the honest form: a rank among
// the team's own homes, which excludes us by construction.
float AllyCoverAt(const AIFloat3& in pos)
{
	return 0.f;
}

// HOW EXPOSED THIS PLAYER IS, relative to its own team: 0 if it sits furthest
// from the enemy of anyone on the team, 1 if it is the most forward -- or if
// it is alone, which is the whole wave arriving at one base. The enemy
// reference is the team centroid mirrored through map centre, the same one the
// rear-specialist election already uses, so no sighting is needed.
float gExpAt = -999999;
float gExposure = 1.f;
float TeamExposure()
{
	if (ai.frame < gExpAt + 10 * SECOND)
		return gExposure;
	gExpAt = ai.frame;
	gExposure = 1.f;
	if (!Builder::gHomeSet)
		return gExposure;
	array<Id>@ mates = ai.GetTeamIds();
	if ((mates is null) || (mates.length() < 2))
		return gExposure;
	array<float> hx, hz;
	float cx = 0.f, cz = 0.f;
	for (uint i = 0; i < mates.length(); ++i) {
		const float x = ai.ReadTeamValue(int(mates[i]), "homex", -1.f);
		const float z = ai.ReadTeamValue(int(mates[i]), "homez", -1.f);
		if ((x < 0.f) || (z < 0.f))
			continue;
		hx.insertLast(x); hz.insertLast(z); cx += x; cz += z;
	}
	if (hx.length() < 2)
		return gExposure;
	cx /= float(hx.length());
	cz /= float(hx.length());
	const float ex = float(AiTerrainWidth()) - cx;
	const float ez = float(AiTerrainHeight()) - cz;
	float near = -1.f, far = -1.f, mine = -1.f;
	for (uint i = 0; i < hx.length(); ++i) {
		const float dx = hx[i] - ex, dz = hz[i] - ez;
		const float d = sqrt(dx * dx + dz * dz);
		if ((near < 0.f) || (d < near)) near = d;
		if ((far < 0.f) || (d > far)) far = d;
	}
	{
		const float dx = Builder::gHomePos.x - ex, dz = Builder::gHomePos.z - ez;
		mine = sqrt(dx * dx + dz * dz);
	}
	if ((far - near) < 1.f)
		return gExposure;
	float f = (far - mine) / (far - near);
	if (f < 0.f) f = 0.f;
	if (f > 1.f) f = 1.f;
	gExposure = f;
	return gExposure;
}

float ShortWith(const AIFloat3& in pos, float cover, float threat)
{
	if (threat <= 1.f)
		return 0.f;
	const float gap = threat - (cover + AllyCoverAt(pos));
	if (gap <= 0.f)
		return 0.f;
	return gap / threat;
}

float ShortfallAt(const AIFloat3& in pos)
{
	RiskFill();
	return ShortWith(pos, CoverAt(pos), ThreatAt(pos));
}

//------------------------------------------------------------------------------
// The observed loss field: where our structures are dying, with a decaying
// memory. Same construction as the death ledger's bleed, keyed by place.
//------------------------------------------------------------------------------

const int LOSS_MAX = 24;
const float LOSS_MERGE_R = 600.f;
array<AIFloat3> gLossPos;
array<float> gLossM;
// The same points as flat floats. LossRateAt is asked twice for every site the
// protect fill prices (ThreatAt and HazardWith each ask), once per asset in the
// guard-post pass, and per mex claim -- and every one of those was 24 distance2D
// method calls over an array of AIFloat3. The compare is unchanged; only what it
// reads is.
array<float> gLossX;
array<float> gLossZ;
int gLossLast = 0;
// GetTunable is frozen for the game on first read (CircuitAI.cpp), so latching
// it here is exact, not approximate.
bool  gLossTauSet = false;
float gLossTauV = 180.f;

float LossTau()
{
	if (!gLossTauSet) {
		gLossTauSet = true;
		const float t = ai.GetTunable("apex_eco_raid_tau", TUNE_ECO_RAID_TAU);
		gLossTauV = (t > 1.f) ? t : 180.f;
	}
	return gLossTauV;
}

// ONE POINT, ONE FRAME, ONE ANSWER. ThreatAt and HazardWith are asked about the
// same site in the same frame and each walked the field; the field only moves
// when NoteEcoLoss fires or the frame advances, and both of those drop the memo.
int   gLrAt = -1;
float gLrX = 0.f;
float gLrZ = 0.f;
float gLrV = 0.f;

void DecayLossField()
{
	const int step = ai.frame - gLossLast;
	if (step <= 0)
		return;
	gLossLast = ai.frame;
	const float tau = LossTau();
	float k = 1.f - (float(step) / 30.f) / tau;
	if (k < 0.f)
		k = 0.f;
	for (uint i = 0; i < gLossM.length(); ++i)
		gLossM[i] *= k;
}

// A finished structure of ours died here. Unlike Military::NoteStructureLoss
// this keeps no forward-fraction filter: an outlying mex dies well past the
// home line, which is exactly the loss that ledger drops.
void NoteEcoLoss(const AIFloat3& in at, float costM)
{
	if ((costM <= 0.f) || !OnMap(at))
		return;
	DecayLossField();
	gLrAt = -1;   // the field is about to move: the frame memo below is void
	for (uint i = 0; i < gLossPos.length(); ++i) {
		if (gLossPos[i].distance2D(at) < LOSS_MERGE_R) {
			gLossM[i] += costM;
			return;
		}
	}
	if (int(gLossPos.length()) >= LOSS_MAX) {
		uint worst = 0;
		for (uint i = 1; i < gLossM.length(); ++i) {
			if (gLossM[i] < gLossM[worst])
				worst = i;
		}
		if (gLossM[worst] >= costM)
			return;
		gLossPos.removeAt(worst);
		gLossM.removeAt(worst);
		gLossX.removeAt(worst);
		gLossZ.removeAt(worst);
	}
	gLossPos.insertLast(at);
	gLossM.insertLast(costM);
	gLossX.insertLast(at.x);
	gLossZ.insertLast(at.z);
}

// Metal per second of our own structures currently dying near pos. The ledger
// holds roughly tau seconds, so ledger/tau is a rate.
float LossRateAt(const AIFloat3& in pos)
{
	DecayLossField();
	if ((gLrAt == ai.frame) && (gLrX == pos.x) && (gLrZ == pos.z))
		return gLrV;
	const float rr = LOSS_MERGE_R * 2.f;
	const float rr2 = rr * rr;
	float m = 0.f;
	for (uint i = 0; i < gLossX.length(); ++i) {
		const float dx = gLossX[i] - pos.x;
		const float dz = gLossZ[i] - pos.z;
		if ((dx * dx + dz * dz) < rr2)
			m += gLossM[i];
	}
	const float v = m / LossTau();
	gLrAt = ai.frame;
	gLrX = pos.x;
	gLrZ = pos.z;
	gLrV = v;
	return v;
}

// OUR OWN METAL DYING PER SECOND, ANYWHERE. LossRateAt is a point sample and
// every caller asked it about home, so a base eaten from its outlying mexes
// inward reads zero.
int   gBleedAt = -1;
float gBleedV = 0.f;

float BleedM()
{
	if (gBleedAt == ai.frame)
		return gBleedV;
	DecayLossField();
	gBleedAt = ai.frame;
	float m = 0.f;
	for (uint i = 0; i < gLossM.length(); ++i)
		m += gLossM[i];
	gBleedV = m / LossTau();
	return gBleedV;
}

//------------------------------------------------------------------------------
// The two risk senses every protect price is built from.
//------------------------------------------------------------------------------

// How far out on a limb this ground is: 0 at the core, 1 a walk away from
// where the army lives.
float ExposureAt(const AIFloat3& in pos)
{
	if (!Builder::gHomeSet)
		return 1.f;
	const float r = ai.GetTunable("apex_expose_r", TUNE_EXPOSE_R);
	float e = pos.distance2D(Builder::gHomePos) / ((r > 1.f) ? r : 1200.f);
	if (e > 1.f)
		e = 1.f;
	return e;
}

//------------------------------------------------------------------------------
// THE PART OF A RISK READING THAT DOES NOT DEPEND ON WHERE YOU ASK.
//
// Threat, hazard and the siege prior each mix a local term with side-wide
// aggregates, and the protect market asks all three at every candidate site of
// every defence def of every builder election -- ArmyValue alone walks the
// whole def table. RiskFill() reads the aggregates into these globals; the
// *At/*With forms take them from there. The wrappers below fill
// unconditionally, so a single-position caller is never a frame stale, while a
// loop over sites fills once and keeps the arithmetic identical.
//------------------------------------------------------------------------------
float gRkThreatR = 0.f;
float gRkTau = 180.f;
float gRkAnchor = 0.f;
float gRkFloorP = 0.f;
float gRkRaid = 0.f;
float gRkHost = 0.f;
float gRkOurArmy = 0.f;
float gRkFoeMass = 0.f;
float gRkEconM = 0.f;
float gRkArmyV = 0.f;
float gRkSeen = 0.f;
// 0 = gradient disabled (flat 1.0), 1 = no usable bearing (0.0), 2 = project.
int   gRkGrad = 0;
float gRkGHx = 0.f, gRkGHz = 0.f, gRkGDx = 0.f, gRkGDz = 0.f, gRkGSpan = 1.f;
// The enemy formations that are WALKING somewhere, gathered once a frame:
// position, metal, and velocity. See ApproachP.
array<float> gRkApX;
array<float> gRkApZ;
array<float> gRkApM;
array<float> gRkApVx;
array<float> gRkApVz;
float gRkHoriz = 120.f;
float gRkApproachW = 0.f;
int   gRkApAt = -999999;
// Frame memos: every input below moves on event/frame granularity, so within
// one frame a refill returns the same numbers -- and the protect stack asks
// per def per builder election.
int gRkFillAt = -1;
int gRkSiegeFillAt = -1;

void RiskFill()
{
	if (gRkFillAt == ai.frame)
		return;
	gRkFillAt = ai.frame;
	gRkThreatR = ai.GetTunable("apex_threat_r", TUNE_THREAT_R);
	gRkTau = ai.GetTunable("apex_eco_raid_tau", TUNE_ECO_RAID_TAU);
	const float horiz = ai.GetTunable("apex_exposed_loss_s", TUNE_EXPOSED_LOSS_S);
	gRkAnchor = 1.f / ((horiz > 1.f) ? horiz : 120.f);
	gRkFloorP = ai.GetTunable("apex_risk_floor", TUNE_RISK_FLOOR);
	gRkOurArmy = Military::OurArmyNow();
	const float pr = gRkOurArmy
			* ai.GetTunable("apex_enemy_prior", TUNE_ENEMY_PRIOR);
	// MY SHARE OF THE TEAM'S ANSWER, the same law ArmyTargetFull already
	// carries: EnemyArmyCost is the SIDE-WIDE census, and pricing every
	// site of every ally against the whole enemy team bought each of N
	// players the defence for all of it (apexearth, on the 8v8: "the
	// number of turrets we are creating is to compensate for the entire
	// enemy team, not just one eighth of that team... we just spend a
	// stupid amount of resources on turrets"). The our-anchored prior is
	// already self-scaled and stays whole; a 1v1's share is exactly 1.
	const float shr = AnswerShare();
	gRkRaid = Military::EnemyCostOf(Unit::Role::RAIDER.type) * shr;
	float host = Military::EnemyArmyCost() * shr;
	if (host < pr)
		host = pr;
	if (host < gRkRaid)
		host = gRkRaid;
	gRkHost = host;
	// Same share on the massing carrier: gRkFoeMass's consumer (the hazard
	// presence fraction) weighs it against MY defended -- the
	// one-against-all-of-them comparison the massing code already refuses
	// ("unreachable by construction").
	float foe = Military::FoeMobileMassing() * shr;
	if (pr > foe)
		foe = pr;
	gRkFoeMass = foe;
	// THE WALK IS THE WARNING. Group data is LOS-slaved, so this is evidence
	// and never a prior: it can only ever raise the hazard, and reads nothing
	// while we are blind.
	gRkHoriz = (horiz > 1.f) ? horiz : 120.f;
	gRkApproachW = ai.GetTunable("apex_hz_approach", TUNE_HZ_APPROACH);
	// Once a second, not once a frame: a formation moves ~60 elmos in that
	// time and the distances this feeds are thousands. The per-member walk is
	// the only unbounded work in RiskFill.
	if (ai.frame - gRkApAt >= SECOND) {
		gRkApAt = ai.frame;
		gRkApX.resize(0);
		gRkApZ.resize(0);
		gRkApM.resize(0);
		gRkApVx.resize(0);
		gRkApVz.resize(0);
		const int nAG = aiEnemyMgr.GetEnemyGroupCount();
		for (int ag = 0; ag < nAG; ++ag) {
			const AIFloat3 gp = aiEnemyMgr.GetEnemyGroupPos(ag);
			if (!OnMap(gp))
				continue;
			// MOBILE METAL ONLY. GetEnemyGroupCost counts the group's
			// buildings too, and velVec is its FASTEST member -- so a group
			// centred on their base would walk its whole economy at us at
			// scout speed. Their fielded army is the thing that arrives.
			float gm = 0.f;
			const int nU = aiEnemyMgr.GetEnemyGroupUnitCount(ag);
			for (int k = 0; k < nU; ++k) {
				const int ud = aiEnemyMgr.GetEnemyGroupUnitDef(ag, k);
				if ((ud > 0) && (ud <= Catalog::gDefCount) && Catalog::gMobile[ud]
					&& !Catalog::gBuilder[ud] && (Catalog::gPower[ud] > 1.f))
				{
					gm += Catalog::gCostM[ud];
				}
			}
			if (gm <= 1.f)
				continue;
			const AIFloat3 gv = aiEnemyMgr.GetEnemyGroupVelVec(ag);
			gRkApX.insertLast(gp.x);
			gRkApZ.insertLast(gp.z);
			gRkApM.insertLast(gm);
			gRkApVx.insertLast(gv.x);
			gRkApVz.insertLast(gv.z);
		}
	}
	if (ai.GetTunable("apex_threat_gradient", TUNE_THREAT_GRADIENT) <= 0.f) {
		gRkGrad = 0;
		return;
	}
	if (!Builder::gHomeSet) {
		gRkGrad = 1;
		return;
	}
	const AIFloat3 home = Builder::gHomePos;
	// Their structures, else the mirrored start -- the same anchor the
	// past-front tests use, so depth and the vetoes agree on the axis.
	AIFloat3 foeP = Front::FoeAnchor();
	if (!OnMap(foeP)) {
		foeP = AIFloat3(float(AiTerrainWidth()) - home.x, 0.f,
				float(AiTerrainHeight()) - home.z);
	}
	const float dx = foeP.x - home.x;
	const float dz = foeP.z - home.z;
	const float span = dx * dx + dz * dz;
	if (span < NEAR_ZERO) {
		gRkGrad = 1;
		return;
	}
	gRkGrad = 2;
	gRkGHx = home.x;
	gRkGHz = home.z;
	gRkGDx = dx;
	gRkGDz = dz;
	gRkGSpan = span;
}

// The siege prior's own aggregates: our economy, our army and what we have
// seen of theirs. Split from RiskFill because ArmyValue walks the def table
// and only this reading needs it.
void RiskFillSiege()
{
	if (gRkSiegeFillAt == ai.frame)
		return;
	gRkSiegeFillAt = ai.frame;
	float econM = gAssetsM - gProtM;
	if (econM < 0.f)
		econM = 0.f;
	gRkEconM = econM;
	gRkArmyV = ArmyValue();
	// MY SHARE of the census, as RiskFill above: SiegeWith weighs this
	// against MY army plus one site's cover.
	gRkSeen = Military::EnemyArmyCost() * AnswerShare();
	gRkOurArmy = Military::OurArmyNow();
	gRkTau = ai.GetTunable("apex_eco_raid_tau", TUNE_ECO_RAID_TAU);
}

// HOW FAR TOWARD THEM THIS GROUND IS: 0 at our start, 1 at theirs.
//
// apexearth: "preload some measure of threat at a gradient towards the enemy's
// side of the map. Our start box centerpoint compared to their starbox
// centerpoint and a gradient of safe to unsafe." This exists from frame 0 and
// needs no scouting, which matters because EnemyArmyCost reads 0 for entire
// games. ForwardFraction is the projection when the enemy centroid is known;
// before contact the MIRRORED start is the stable answer, where the centroid is
// noise.
float GradAt(const AIFloat3& in pos)
{
	if (gRkGrad == 0)
		return 1.f;
	if (gRkGrad != 2)
		return 0.f;
	// THIS AXIS AND ForwardFraction'S DISAGREED COMPLETELY, AND THIS ONE WAS
	// WRONG. Measured 2026-09-08 on Supreme Isthmus, at mex-upgrade sites:
	//
	//   fwd=1.00  grad=0.000      <- the enemy end of the map
	//   fwd=0.97  grad=0.007
	//   fwd=0.73  grad=0.000
	//
	// So the presence term of HazardWith -- GradAt(pos) * foeMass / ... -- was
	// multiplied by ~0 at every position, not merely at home as its comment
	// claims. The only term left moving was the RETROSPECTIVE loss rate, so a
	// spot priced as perfectly safe until something had already died on it, and
	// the mex upgrades went to the most exposed extractors we owned (apexearth:
	// "the dumbass AI has upgraded our most dangerous mexes - the first ones
	// that would die... We have logic where building stuff is perceived as less
	// valuable when it is in a dangerous place. So what the heck is going on?").
	//
	// The cause is the ANCHOR. This projected against Front::FoeAnchor(), which
	// falls back to the mirrored start when we have seen no enemy structure --
	// and on a diagonal-start map the mirror points the wrong way, so forward
	// ground projects NEGATIVE and clamps to zero. ForwardFraction projects
	// against the enemy we can actually see (FoeMid, else GetEnemyPos) from the
	// territory centre, and reported 1.00 on the same spots in the same frame.
	//
	// One axis, the one that is right. The local projection stays as the
	// fallback for the frames before ForwardFraction has an enemy to point at.
	const float fwd = Military::ForwardFraction(pos);
	if (fwd > 0.f) {
		return (fwd > 1.f) ? 1.f : fwd;
	}
	float t = ((pos.x - gRkGHx) * gRkGDx + (pos.z - gRkGHz) * gRkGDz) / gRkGSpan;
	if (t < 0.f) t = 0.f;
	if (t > 1.f) t = 1.f;
	return t;
}

// Enemy metal that actually ARRIVES here -- the size of the wave a turret on
// this spot would have to beat. Local sightings, floored by what has recently
// been killing us here, because a raider we cannot currently see is still
// evidence of a wave (visible-strength gates read "safe" exactly when we are
// blind).
//
// Their whole army does NOT belong in this number. It is what could
// eventually come, not what shows up at one mex, and mixing the two prices a
// turret as though it had to defeat the enemy's entire mobile mass -- which
// made every single tower look 70% useless. Army scale belongs in HazardAt,
// where it says how OFTEN something arrives.
//
// THE PRIOR IS A GRADIENT, not one number for the whole map. At our own start
// the credible wave is a RAID that leaked through; at theirs it is their whole
// mobile army, because that is what stands there. Both ends are measured, and
// the enemy end is floored by the symmetric prior so an unscouted enemy is not
// assumed absent -- "if we don't know the enemy strength then we shouldn't be
// making a T2 lab".
float ThreatAt(const AIFloat3& in pos)
{
	if (!OnMap(pos))
		return 0.f;
	float t = ai.GetEnemyCostAt(pos, gRkThreatR);
	const float implied = LossRateAt(pos) * gRkTau;
	if (implied > t)
		t = implied;
	const float baseline = gRkRaid + (gRkHost - gRkRaid) * GradAt(pos);
	return (baseline > t) ? baseline : t;
}

// Per-second hazard at pos: how often lethal force ARRIVES here. Whether it
// then succeeds is the shortfall's job -- keeping the two apart is what stops
// threat magnitude being counted twice.
//
// Both terms are ratios of measured quantities against other measured
// quantities, so neither carries an invented scale: what fraction of the local
// stake we have recently lost, and how their army compares to everything
// defending this ground. A quiet rear sits at the floor; ground being raided
// with nothing covering it approaches certainty within the anchor horizon.
//
// `cover` is CoverAt(pos); the caller passes it because the protect market
// already has it and it is the second most expensive read in the market.
// Hazard floor from formations WALKING at this ground: horizon/ETA, clipped
// at 1, against what defends here. HazardWith's other two terms cannot see a
// force on its way -- the loss term is retrospective and the presence term is
// scaled by GradAt, which is zero at our own base by construction.
//
// LOS-slaved, so it reads zero where nothing was seen and can only ever raise.
// Mobile metal only: group cost counts buildings and velVec is the fastest
// member, so a group on their base would walk its economy at us at scout speed.
// MEASURED INERT, kept at 0 as an instrument -- docs/27.
float ApproachP(const AIFloat3& in pos, float defended)
{
	RiskFill();   // stamped per frame; never reached from inside RiskFill
	// THE WAVE DOES NOT SPLIT ITSELF -- the same law the site fill states. The
	// group model cuts one push into a dozen clusters, so a max over groups
	// reads a push as a skirmish; sum what is on its way, then take the ratio
	// once.
	float mass = 0.f;
	for (uint g = 0; g < gRkApM.length(); ++g) {
		const float dx = pos.x - gRkApX[g];
		const float dz = pos.z - gRkApZ[g];
		float d = sqrt(dx * dx + dz * dz);
		if (d < 1.f)
			d = 1.f;
		// Closing speed toward THIS ground; a formation walking away is let go.
		// velVec is the group's FASTEST member, so this is the earliest the
		// force could land -- an upper bound on urgency, which is the safe
		// direction for a floor.
		const float closing = (gRkApVx[g] * dx + gRkApVz[g] * dz) / d;
		if (closing <= 0.f)
			continue;
		float reach = closing * gRkHoriz / d;
		if (reach > 1.f)
			reach = 1.f;
		mass += gRkApM[g] * reach;
	}
	if (mass <= 0.f)
		return 0.f;
	return mass / (mass + ((defended > 0.f) ? defended : 0.f));
}

float HazardWith(const AIFloat3& in pos, float cover)
{
	const float stake = StakeAt(pos, gRkThreatR);
	float p = 0.f;
	if (stake > 1.f)
		p = LossRateAt(pos) * gRkTau / stake;
	// Their mobile mass against everything that defends THIS ground. The
	// ExposureAt factor that used to multiply this is gone for the same
	// reason as in ThreatAt: it is zero at home, so the one place with
	// everything to lose reported the floor hazard all game. Position
	// still matters here -- through cover, which is what actually differs
	// between a guarded core and an outlying mex. ARRIVAL RATE RISES TOWARD
	// THEM: their strength against what defends this ground says how badly
	// it goes; the gradient says how OFTEN it happens at all.
	const float defended = gRkOurArmy + cover;
	if (gRkFoeMass > 0.f) {
		const float pres = GradAt(pos) * gRkFoeMass
				/ (gRkFoeMass + ((defended > 0.f) ? defended : 0.f));
		if (pres > p)
			p = pres;
	}
	// ...and what is on its way here, whatever the map geometry says about
	// this ground. See ApproachP.
	if (gRkApproachW > 0.f) {
		const float appr = ApproachP(pos, defended) * gRkApproachW;
		if (appr > p)
			p = appr;
	}
	if (p < gRkFloorP)
		p = gRkFloorP;
	if (p > 1.f)
		p = 1.f;
	return gRkAnchor * p;
}

// THEY ARE COMING WHETHER WE HAVE SEEN THEM OR NOT. HazardAt is deliberately
// zero at our own start -- its pressure term is scaled by the gradient, and
// its unscouted prior is a share of OUR ARMY, which is near zero exactly when
// we are teching instead of arming. So a base with a large economy and no
// units priced a long build as almost risk-free (apexearth: "the issue is you
// think we have the time to build an AFUS. we don't. They've gone T2 - and
// they're coming. We didn't see it yet, but we should know - they are
// coming"). The honest mirror is their ECONOMY, which started equal to ours
// and is what ArmyTarget already expects to fight, measured against what
// actually defends this ground.
// TWO DIFFERENT QUESTIONS, TWO DIFFERENT PRIORS. Whether a long bet has time
// to pay is a worst-case question -- assume they spent everything on army. How
// much defence to BUY is an expectation, because buying against the worst case
// is a feedback loop: bigger economy -> more assumed enemy army -> more
// turrets -> economy stalls (apexearth: "we make far too many turrets around
// our base... our want for defense is outweighing our interest in more eco").
// The expectation is apex_enemy_prior. ArmyTarget no longer reads it -- army
// is sized from our own economy -- and turrets are excluded from our own
// total, or defence becomes its own justification and the loop runs away.
float SiegeWith(const AIFloat3& in pos, float cover, float priorFrac)
{
	// ...AND THE EXPECTATION ANCHORS ON OUR ARMY, the same basis RiskFill's
	// own prior already uses. What this returns is a RATE, and the gain it
	// feeds multiplies by the stake as well, so anchoring it on our economy
	// counted our wealth twice: a tower's worth grew with the SQUARE of what
	// we owned and the loop above ran anyway at a quarter strength. What an
	// unseen enemy can send is bounded by what a mirror of us has committed
	// to war, not by what we own.
	const float prior = gRkOurArmy * priorFrac;
	const float foe = (gRkSeen > prior) ? gRkSeen : prior;
	if (foe <= 0.f)
		return 0.f;
	const float defended = gRkOurArmy + cover;
	return (foe / (foe + ((defended > 0.f) ? defended : 0.f)))
			/ ((gRkTau > 1.f) ? gRkTau : 180.f);
}

float ThreatGradient(const AIFloat3& in pos)
{
	RiskFill();
	return GradAt(pos);
}

// THE CHANCE A CONSTRUCTOR DIES ON A TRIP TO pos (apexearth: "the further
// out we go the more likely our constructor is to die... the more army we
// have relative to our overall mass the safer we should feel"): depth toward
// them, scaled by the share of everything we own that is NOT army. A spot at
// their start with no army is a dead con; the same spot with an army as big
// as the base is a coin flip. No line anywhere -- this replaces the
// past-front veto on mex claims.
float TripShare()
{
	const float army = ArmyValue();
	const float mass = army + gAssetsM;
	return (mass > 1.f) ? (army / mass) : 0.f;
}

float TripRiskWith(const AIFloat3& in pos, float share)
{
	RiskFill();
	return GradAt(pos) * (1.f - share);
}

float TripRisk(const AIFloat3& in pos)
{
	return TripRiskWith(pos, TripShare());
}

float ThreatM(const AIFloat3& in pos)
{
	RiskFill();
	return ThreatAt(pos);
}

float HazardAt(const AIFloat3& in pos)
{
	RiskFill();
	return HazardWith(pos, CoverAt(pos));
}

float SiegeRiskAt(const AIFloat3& in pos, float priorFrac)
{
	RiskFillSiege();
	return SiegeWith(pos, CoverAt(pos), priorFrac);
}

// The worst case: what a deferred bet is measured against.
float SiegeRisk(const AIFloat3& in pos)
{
	return SiegeRiskAt(pos, ai.GetTunable("apex_siege_prior", TUNE_SIEGE_PRIOR));
}

// The expectation: what defence is SIZED against.
float SiegeExpect(const AIFloat3& in pos)
{
	return SiegeRiskAt(pos, ai.GetTunable("apex_enemy_prior", TUNE_ENEMY_PRIOR));
}

// AN UNGUARDED STREAM IS NOT A STREAM. apexearth, twice: "I'm upset every time
// I see we make stuff and walk away from it without guarding it at all... a mex
// should have almost NO VALUE! until it is protected by a tower."
//
// The mex wants price a spot's income as though we keep it, and the only risk
// charge, ExpectedLossAt in decide.as, bills the BUILDING's 620 metal -- never
// the income we stop collecting when it dies, the larger number over any real
// horizon. Without this an unheld forward spot and a towered one behind our
// line price within a few percent of each other.
//
// The share of a stream we expect to actually collect, over the horizon the
// stake is already counted across. ShortfallAt is what our guns fail to stop,
// so a tower within reach RAISES this directly -- the coupling he asks for:
// cover makes the next claim beside it worth more, and expansion clusters
// behind the line instead of scattering.
// Memoized on a 256-elmo grid with a 3s clock: three field sweeps per call,
// and the mexup proposer asks per held spot per election.
array<float> gSsVal(64, 1.f);
array<int> gSsAt(64, 0);
array<int> gSsKey(64, 0);
// The per-second risk a stream at `pos` runs (hazard or siege, times the
// cover shortfall); cached 3 s per 256-elmo cell.
float StreamRisk(const AIFloat3& in pos)
{
	if (!OnMap(pos))
		return 0.f;
	const int key = (int(pos.x) >> 8) * 4096 + (int(pos.z) >> 8) + 1;
	const uint slot = uint(key) & 63;
	if ((gSsKey[slot] == key) && (ai.frame - gSsAt[slot] < 3 * SECOND))
		return gSsVal[slot];
	// Shortfall, hazard and the siege prior all read the cover at this one
	// point and all three side-wide fills. Read each once.
	RiskFill();
	RiskFillSiege();
	const float cover = CoverAt(pos);
	float shortP = ShortWith(pos, cover, ThreatAt(pos));
	// INSIDE THE TEAM'S LINE, THE LINE IS THE COVER. Ground behind a held
	// front is exposed only through the worst open hole, whatever gun stands
	// beside the building: the guns went to the front (docs/32) and every
	// home mex read a 45% chance of loss with hazard 0 -- halving every
	// economy want at home. The hole rule prices the hole; the interior
	// carries its open share, not a shortfall of its own.
	{
		const float holeShort = InteriorShortfall(pos);
		if ((holeShort >= 0.f) && (holeShort < shortP))
			shortP = holeShort;
	}
	float risk = HazardWith(pos, cover) * shortP;
	const float siege = SiegeWith(pos, cover,
			ai.GetTunable("apex_siege_prior", TUNE_SIEGE_PRIOR)) * shortP;
	if (siege > risk)
		risk = siege;
	gSsKey[slot] = key;
	gSsAt[slot] = ai.frame;
	gSsVal[slot] = risk;
	return risk;
}

// Survival of a stream at `pos` over `T` seconds: 1/(1 + risk x T).
float StreamSurvivalOver(const AIFloat3& in pos, float T)
{
	if (ai.GetTunable("apex_stream_survival", TUNE_STREAM_SURVIVAL) <= 0.f)
		return 1.f;
	const float risk = StreamRisk(pos);
	if ((risk <= 0.f) || (T <= 0.f))
		return 1.f;
	return 1.f / (1.f + risk * T);
}

float StreamSurvival(const AIFloat3& in pos)
{
	const float T = ai.GetTunable("apex_stake_horizon_s", TUNE_STAKE_HORIZON_S);
	return StreamSurvivalOver(pos, (T > 1.f) ? T : 300.f);
}

// WHAT A BUILDING'S DEATH COSTS ITS NEIGHBOURS, AND THEIRS COSTS IT. Every
// structure carries its death explosion off the def (Catalog::gBlast*); a
// basic converter is 167 HP that goes off for 660 in a 105-elmo radius, so in
// a packed block each one is a fuse for the next (apexearth: "they're a big
// risk for a huge chain explosion since they take up so much room"). Expected
// metal lost over the stake horizon at this ground's hazard: what d's blast
// would kill standing within its reach, plus d itself if any neighbour's blast
// reaches it with enough left to kill it. First neighbours only -- the chain
// past them is not counted, which is the conservative side.
float BlastDamageAt(int d, float dist)
{
	const float R = Catalog::gBlastR[d];
	if ((R <= 0.f) || (dist >= R))
		return 0.f;
	const float e = Catalog::gBlastE[d];
	return Catalog::gBlastD[d] * (1.f - (1.f - e) * (dist / R));
}

float BlastCollateralM(const AIFloat3& in site, int d)
{
	if (!Catalog::ValidId(d) || !OnMap(site))
		return 0.f;
	float reach = Catalog::gBlastR[d];
	array<CCircuitUnit@>@ near = ai.GetOwnStructsNear(site, (reach > 160.f) ? reach : 160.f);
	if (near is null)
		return 0.f;
	float m = 0.f;
	bool dies = false;
	for (uint i = 0; i < near.length(); ++i) {
		CCircuitUnit@ u = near[i];
		if ((u is null) || (u.circuitDef is null))
			continue;
		const int n = int(u.circuitDef.id);
		const float dist = u.GetPos(ai.frame).distance2D(site);
		if (BlastDamageAt(d, dist) >= Catalog::gHealth[n])
			m += Catalog::gCostM[n];
		if (!dies && (BlastDamageAt(n, dist) >= Catalog::gHealth[d]))
			dies = true;
	}
	if (dies)
		m += Catalog::gCostM[d];
	if (m <= 0.f)
		return 0.f;
	const float T = ai.GetTunable("apex_stake_horizon_s", TUNE_STAKE_HORIZON_S);
	float p = HazardAt(site) * ((T > 1.f) ? T : 300.f);
	if (p > 1.f)
		p = 1.f;
	return m * p;
}

// DEFENDED GROUND IS A SCARCE RESOURCE. A turret protects an AREA, and the same
// ring of guns can cover a field of one-metal converters or a pack of advanced
// ones worth ten times as much (apexearth: "if you are in a well protected area
// - you should want to reclaim the T1 converter in favor of a T2 - all that
// defence can defend a unit that has ~9 or 10x the value... value going up over
// time - static metal cost, perpetual income").
//
// So a building pays RENT on the defence covering the ground it takes: each
// covering turret's metal spread over the area its own weapon reaches, charged
// per cell of footprint. Outside our cover the rent is zero and sprawl is free,
// which is the right answer on an open map with room to spare -- and it rises
// on its own as the perimeter fills, which is when space starts to matter.
// Nothing here names a unit or a tier: dense wins inside the wall because dense
// is what the wall is cheap to protect.
float SpaceRentM(const AIFloat3& in pos, int areaCells)
{
	if (areaCells <= 0)
		return 0.f;
	const float k = ai.GetTunable("apex_space_rent", TUNE_SPACE_RENT);
	if ((k <= 0.f) || !OnMap(pos))
		return 0.f;
	float perCell = 0.f;
	for (uint i = 0; i < gProtPos[PROT_DEF].length(); ++i) {
		const int d = gProtDefId[PROT_DEF][i];
		const float r = Catalog::gMaxRange[d];
		if ((r <= 1.f) || (gProtPos[PROT_DEF][i].distance2D(pos) > r))
			continue;
		// Cells of 16 elmos inside that turret's own coverage circle.
		const float cells = 3.14159f * r * r / 256.f;
		if (cells > 1.f)
			perCell += Catalog::gCostM[d] / cells;
	}
	return perCell * float(areaCells) * k;
}

// The expected-loss stream on value standing at pos, in metal/s -- the one
// quantity both the protect gain and the exposure premium are built from.
float ExpectedLossAt(const AIFloat3& in pos, float valueM)
{
	if (valueM <= 0.f)
		return 0.f;
	RiskFill();
	const float cover = CoverAt(pos);
	return valueM * HazardWith(pos, cover)
			* ShortWith(pos, cover, ThreatAt(pos));
}

// The risk field as the AI sees it: the most exposed standing mex, and the
// totals behind it. Reads "is this mex defended" out loud, which the boolean
// radius test could never be asked.
int gNextRiskLog = 0;
void RiskDiag()
{
	if (ai.frame < gNextRiskLog)
		return;
	gNextRiskLog = ai.frame + 60 * SECOND;
	int worst = -1;
	float worstEL = 0.f;
	float coveredM = 0.f;
	float shortSum = 0.f;
	int standing = 0;
	const array<int>@ mexRows = MexRows();
	for (uint q = 0; q < mexRows.length(); ++q) {
		const uint i = uint(mexRows[q]);
		++standing;
		// Covered means a turret reaches it, NOT merely that we see no
		// threat -- conflating the two reported a naked base as safe.
		if (CoverAt(gLPos[i]) > 0.f)
			coveredM += 1.f;
		shortSum += ShortfallAt(gLPos[i]);
		const float el = ExpectedLossAt(gLPos[i], 620.f);
		if (el > worstEL) {
			worstEL = el;
			worst = int(i);
		}
	}
	if (standing <= 0)
		return;
	float lossTotal = 0.f;
	for (uint i = 0; i < gLossM.length(); ++i)
		lossTotal += gLossM[i];
	string ln = "apex: risk mex=" + standing + " covered=" + int(coveredM)
			+ " meanShort=" + formatFloat(shortSum / float(standing), "", 0, 2)
			+ " lostM=" + formatFloat(lossTotal, "", 0, 0);
	// The two terms every DEFERRED want is discounted by (TechSurvival): the
	// rate value dies at home, and the share our own guns fail to stop.
	if (Builder::gHomeSet && OnMap(Builder::gHomePos)) {
		// appr is printed whether or not apex_hz_approach is on -- it is the
		// measurement, and a run with the term off must still show what it
		// would have said. groups is the LOS-slaved sample it is drawn from.
		ln += " home[hazard=" + formatFloat(HazardAt(Builder::gHomePos) * 1000.f, "", 0, 2)
			+ "/ks short=" + formatFloat(ShortfallAt(Builder::gHomePos), "", 0, 2)
			+ " appr=" + formatFloat(ApproachP(Builder::gHomePos,
					gRkOurArmy + CoverAt(Builder::gHomePos)), "", 0, 3)
			+ " groups=" + gRkApM.length() + "]";
	}
	if (worst >= 0) {
		const AIFloat3 wp = gLPos[worst];
		ln += " worst=" + int(wp.x) + "," + int(wp.z)
			+ " cover=" + formatFloat(CoverAt(wp), "", 0, 0)
			+ " threat=" + formatFloat(ThreatM(wp), "", 0, 0)
			+ " short=" + formatFloat(ShortfallAt(wp), "", 0, 2)
			+ " hazard=" + formatFloat(HazardAt(wp) * 1000.f, "", 0, 2) + "/ks"
			+ " EL=" + formatFloat(worstEL, "", 0, 3);
	}
	AiLog(Factory::T() + ln);
}


}  // namespace Market
