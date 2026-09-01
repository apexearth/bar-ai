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
// instead compared a metal figure against a coverage figure: the candidate was
// credited in full at the site while the towers already standing were judged
// on a ring almost nothing reaches, so the field never saturated and the Nth
// turret priced exactly like the first (measured: cover=0 at protM=3450).
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

float CoverWith(const AIFloat3& in pos, const AIFloat3& in extraAt,
		float extraReach, float extraM)
{
	if ((gProtPos[PROT_DEF].length() == 0) && (extraReach <= 0.f))
		return 0.f;
	const float trade = ai.GetTunable("apex_def_trade", TUNE_DEF_TRADE);
	const float standoff = (ai.GetTunable("apex_standoff_cover", TUNE_STANDOFF_COVER) > 0.f)
			? Military::FoeReach() : 0.f;
	if (standoff <= 1.f)
		return CoverPointM(pos, trade, extraAt, extraReach, extraM);
	float worst = -1.f;
	for (int b = 0; b < COVER_RAYS; ++b) {
		const float ang = 6.2831853f * float(b) / float(COVER_RAYS);
		const AIFloat3 fp = pos + AIFloat3(cos(ang), 0.f, sin(ang)) * standoff;
		if (!OnMap(fp))
			continue;   // they cannot stand off the map to shoot from there
		const float m = CoverPointM(fp, trade, extraAt, extraReach, extraM);
		if ((worst < 0.f) || (m < worst))
			worst = m;
	}
	return (worst < 0.f)
			? CoverPointM(pos, trade, extraAt, extraReach, extraM) : worst;
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
	const float standoff = (ai.GetTunable("apex_standoff_cover", TUNE_STANDOFF_COVER) > 0.f)
			? Military::FoeReach() : 0.f;
	if (standoff <= 1.f)
		return adds;   // the point path: the turret stands on the point it covers
	for (int b = 0; b < COVER_RAYS; ++b) {
		const float ang = 6.2831853f * float(b) / float(COVER_RAYS);
		const AIFloat3 fp = pos + AIFloat3(cos(ang), 0.f, sin(ang)) * standoff;
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
// faces outward from the middle of our own footprint, which is not the same
// direction and on a flank is nowhere near it. Without the second form only
// front posts could ever collect the credit, so the price's argmax sat at the
// centroid of the base by construction and a rim post was worth its own disc
// and nothing more.
float ShieldedStakeAlong(const AIFloat3& in pos, float reach,
		const AIFloat3& in dirIn)
{
	if (reach < 1.f)
		return 0.f;
	AIFloat3 dir = dirIn;
	if (dir.SqLength2D() < NEAR_ZERO)
		return 0.f;
	dir.SafeNormalize2D();
	const AIFloat3 across(-dir.z, 0.f, dir.x);
	PfRebuild();
	float m = 0.f;
	for (uint i = 0; i < gPfPos.length(); ++i) {
		const AIFloat3 rel = gPfPos[i] - pos;
		if ((rel.x * dir.x + rel.z * dir.z) > 0.f)
			continue;   // in front of the post: it shields nothing there
		const float lat = abs(rel.x * across.x + rel.z * across.z);
		if ((lat > reach) || (gPfPos[i].distance2D(pos) < reach))
			continue;   // nearer than reach is FrontedStakeAt's to count
		m += gPfWorth[i];
	}
	return m;
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

// STAKE A POST ACTUALLY DEFENDS.
//
// Plain distance: everything of ours inside this post's weapon range. Two
// earlier shapes were both wrong. A SIDE test ("is the post between this asset
// and the enemy") reads correctly for a distant intercepting post but zeroes a
// tower standing inside the base -- half the base is in front of any home
// tower, so home defence priced to nothing and raiders walked in. Subtracting
// the attacker's standoff here was worse still: it demanded a post deny EVERY
// firing position, which at 450 reach against 300 standoff means 150 elmos, so
// almost nothing qualified and defence fell to 1.9% of our metal. Standoff is
// CoverAt's question -- charging it twice is double counting.
//
// Distance alone is honest and does the work the side test was reaching for: a
// tower at the back of the base simply cannot reach a mex 800 elmos forward.
// ShieldedStakeAt then adds what a FORWARD post intercepts beyond its own
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
// on the map, priced as the most dangerous. That number is a multiplier in
// three places at once (StreamSurvival discounts every eco build by it,
// TechSurvival discounts the T2 lab by it, and the defence want sizes itself
// off it), so one wrong reading suppresses economy, tech and sensible
// defence together -- and the answer it drives us to, more turrets of our
// own, is the one thing the rear player should not be buying.
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
int gLossLast = 0;

void DecayLossField()
{
	const int step = ai.frame - gLossLast;
	if (step <= 0)
		return;
	gLossLast = ai.frame;
	const float tau = ai.GetTunable("apex_eco_raid_tau", TUNE_ECO_RAID_TAU);
	float k = 1.f - (float(step) / 30.f) / ((tau > 1.f) ? tau : 180.f);
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
	}
	gLossPos.insertLast(at);
	gLossM.insertLast(costM);
}

// Metal per second of our own structures currently dying near pos. The ledger
// holds roughly tau seconds, so ledger/tau is a rate.
float LossRateAt(const AIFloat3& in pos)
{
	DecayLossField();
	const float tau = ai.GetTunable("apex_eco_raid_tau", TUNE_ECO_RAID_TAU);
	float m = 0.f;
	for (uint i = 0; i < gLossPos.length(); ++i) {
		if (gLossPos[i].distance2D(pos) < LOSS_MERGE_R * 2.f)
			m += gLossM[i];
	}
	return m / ((tau > 1.f) ? tau : 180.f);
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
// Threat, hazard and the siege prior each mix a local term (what is seen at
// pos, what stands there, what has died there) with side-wide aggregates --
// their raiding force, their army, ours, the enemy bearing. The aggregates
// were recomputed per call, and the protect market asks all three at every
// candidate site of every defence def of every builder election. ArmyValue
// alone walks the whole def table.
//
// RiskFill() reads the aggregates into these globals; the *At/*With forms take
// them from there. A caller with one position still pays exactly what it paid
// before -- the wrappers below fill unconditionally, so nothing is ever read a
// frame stale -- while a loop over sites fills once and keeps the arithmetic
// identical.
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
	if (ai.GetTunable("apex_threat_gradient", TUNE_THREAT_GRADIENT) <= 0.f) {
		gRkGrad = 0;
		return;
	}
	if (!Builder::gHomeSet) {
		gRkGrad = 1;
		return;
	}
	const AIFloat3 home = Builder::gHomePos;
	AIFloat3 foeP = aiEnemyMgr.GetEnemyPos();
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
// much defence to BUY is an expectation, and buying against the worst case is
// a feedback loop: bigger economy -> more assumed enemy army -> more turrets
// -> economy stalls, settling only once cover roughly equals our whole
// economy (apexearth, watching: "we make far too many turrets around our base.
// We stopped eco at around ~15-19m/s... our want for defense is outweighing
// our interest in more eco, and we aren't making any T2"). The expectation is
// apex_enemy_prior -- the expected-enemy share the defence side prices
// against. ArmyTarget no longer reads it: army is sized from our own economy.
// Turrets are excluded from our own total, or defence becomes its own
// justification and the loop runs away.
float SiegeWith(const AIFloat3& in pos, float cover, float priorFrac)
{
	const float prior = (gRkEconM + gRkArmyV) * priorFrac;
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
// The mex wants price the income a spot yields as though we keep it. The only
// risk charge anywhere was ExpectedLossAt in decide.as, and that bills the
// BUILDING's 620 metal -- never the income we stop collecting when it dies,
// which over any real horizon is the larger number by far. So an unheld
// forward spot and a towered one behind our own line priced within a few
// percent of each other.
//
// The share of a stream we expect to actually collect, over the horizon the
// stake is already counted across. ShortfallAt is what our guns fail to stop,
// so a tower within reach of the spot RAISES this directly -- which is the
// coupling he is asking for: cover makes the next claim beside it worth more,
// and expansion clusters behind the line instead of scattering.
// Memoized on a 256-elmo grid with a 3s clock: three field sweeps per call,
// and the mexup proposer asks per held spot per election.
array<float> gSsVal(64, 1.f);
array<int> gSsAt(64, 0);
array<int> gSsKey(64, 0);
float StreamSurvival(const AIFloat3& in pos)
{
	if (ai.GetTunable("apex_stream_survival", TUNE_STREAM_SURVIVAL) <= 0.f)
		return 1.f;
	if (!OnMap(pos))
		return 1.f;
	const int key = (int(pos.x) >> 8) * 4096 + (int(pos.z) >> 8) + 1;
	const uint slot = uint(key) & 63;
	if ((gSsKey[slot] == key) && (ai.frame - gSsAt[slot] < 3 * SECOND))
		return gSsVal[slot];
	// Shortfall, hazard and the siege prior all read the cover at this one
	// point and all three side-wide fills. Read each once.
	RiskFill();
	RiskFillSiege();
	const float cover = CoverAt(pos);
	const float shortP = ShortWith(pos, cover, ThreatAt(pos));
	float risk = HazardWith(pos, cover) * shortP;
	const float siege = SiegeWith(pos, cover,
			ai.GetTunable("apex_siege_prior", TUNE_SIEGE_PRIOR)) * shortP;
	if (siege > risk)
		risk = siege;
	float r = 1.f;
	if (risk > 0.f) {
		const float T = ai.GetTunable("apex_stake_horizon_s", TUNE_STAKE_HORIZON_S);
		r = 1.f / (1.f + risk * ((T > 1.f) ? T : 300.f));
	}
	gSsKey[slot] = key;
	gSsAt[slot] = ai.frame;
	gSsVal[slot] = r;
	return r;
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
	for (uint i = 0; i < gLPos.length(); ++i) {
		if (gLExtract[i] <= 0.f)
			continue;
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
		ln += " home[hazard=" + formatFloat(HazardAt(Builder::gHomePos) * 1000.f, "", 0, 2)
			+ "/ks short=" + formatFloat(ShortfallAt(Builder::gHomePos), "", 0, 2) + "]";
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
