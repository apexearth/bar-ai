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
const int COVER_RAYS = 6;

float CoverPointM(const AIFloat3& in at, float trade)
{
	float m = 0.f;
	for (uint i = 0; i < gProtPos[PROT_DEF].length(); ++i) {
		const int d = gProtDefId[PROT_DEF][i];
		if (gProtPos[PROT_DEF][i].distance2D(at) <= Catalog::gMaxRange[d])
			m += Catalog::gCostM[d] * trade;
	}
	return m;
}

float CoverAt(const AIFloat3& in pos)
{
	if (gProtPos[PROT_DEF].length() == 0)
		return 0.f;
	const float trade = ai.GetTunable("apex_def_trade", TUNE_DEF_TRADE);
	const float standoff = (ai.GetTunable("apex_standoff_cover", TUNE_STANDOFF_COVER) > 0.f)
			? Military::FoeReach() : 0.f;
	if (standoff <= 1.f)
		return CoverPointM(pos, trade);
	float worst = -1.f;
	for (int b = 0; b < COVER_RAYS; ++b) {
		const float ang = 6.2831853f * float(b) / float(COVER_RAYS);
		const AIFloat3 fp = pos + AIFloat3(cos(ang), 0.f, sin(ang)) * standoff;
		if (!OnMap(fp))
			continue;   // they cannot stand off the map to shoot from there
		const float m = CoverPointM(fp, trade);
		if ((worst < 0.f) || (m < worst))
			worst = m;
	}
	return (worst < 0.f) ? CoverPointM(pos, trade) : worst;
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
	const float horiz = ai.GetTunable("apex_stake_horizon_s", TUNE_STAKE_HORIZON_S);
	const float h = (horiz > 1.f) ? horiz : 300.f;
	float m = 0.f;
	for (uint i = 0; i < gLPos.length(); ++i) {
		if ((gLExtract[i] > 0.f) && (gLPos[i].distance2D(pos) < r))
			m += gLIncome[i] * gLExtract[i] * h;
	}
	for (uint i = 0; i < gOwnBig.length(); ++i) {
		if ((gOwnBig[i] !is null) && (gOwnBig[i].GetPos(ai.frame).distance2D(pos) < r))
			m += Catalog::gCostM[int(gOwnBig[i].circuitDef.id)];
	}
	for (uint i = 0; i < gOwnGen.length(); ++i) {
		if ((gOwnGen[i] !is null) && (gOwnGen[i].GetPos(ai.frame).distance2D(pos) < r))
			m += Catalog::gCostM[int(gOwnGen[i].circuitDef.id)];
	}
	return m;
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
float ShieldedStakeAt(const AIFloat3& in pos, float reach)
{
	if (!Base::gAxisSet || (reach < 1.f))
		return 0.f;
	const float horiz = ai.GetTunable("apex_stake_horizon_s", TUNE_STAKE_HORIZON_S);
	const float h = (horiz > 1.f) ? horiz : 300.f;
	float m = 0.f;
	for (uint i = 0; i < gLPos.length(); ++i) {
		if (gLExtract[i] <= 0.f)
			continue;
		const AIFloat3 rel = gLPos[i] - pos;
		if (rel.x * Base::gFwd.x + rel.z * Base::gFwd.z >= 0.f)
			continue;   // in front of the post: it shields nothing there
		const float lat = abs(rel.x * Base::gAcross.x + rel.z * Base::gAcross.z);
		if ((lat > reach) || (gLPos[i].distance2D(pos) <= reach))
			continue;
		m += gLIncome[i] * gLExtract[i] * h;
	}
	for (uint i = 0; i < gOwnBig.length(); ++i) {
		if (gOwnBig[i] is null)
			continue;
		const AIFloat3 bp = gOwnBig[i].GetPos(ai.frame);
		const AIFloat3 rel = bp - pos;
		if (rel.x * Base::gFwd.x + rel.z * Base::gFwd.z >= 0.f)
			continue;
		const float lat = abs(rel.x * Base::gAcross.x + rel.z * Base::gAcross.z);
		if ((lat > reach) || (bp.distance2D(pos) <= reach))
			continue;
		m += Catalog::gCostM[int(gOwnBig[i].circuitDef.id)];
	}
	return m;
}

// STAKE A POST ACTUALLY STANDS IN FRONT OF.
//
// StakeAt counts every asset inside the turret's weapon range whichever SIDE of
// it they sit on, so a tower at the back of the base is credited with the whole
// base in front of it -- which the enemy reaches first (apexearth: "they're made
// behind everything important we want to protect. Thus they protect hardly
// anything"). Here an asset counts only if the post stands between it and the
// enemy. Measured on the true enemy bearing, not the cardinal-snapped axis.
float FrontedStakeAt(const AIFloat3& in pos, float reach)
{
	const AIFloat3 foe = aiEnemyMgr.GetEnemyPos();
	if (!OnMap(foe))
		return StakeAt(pos, reach);   // no bearing known: no side to be on
	AIFloat3 dir = foe - pos;
	if (dir.SqLength2D() < NEAR_ZERO)
		return StakeAt(pos, reach);
	dir.SafeNormalize2D();
	const float horiz = ai.GetTunable("apex_stake_horizon_s", TUNE_STAKE_HORIZON_S);
	const float h = (horiz > 1.f) ? horiz : 300.f;
	float m = 0.f;
	for (uint i = 0; i < gLPos.length(); ++i) {
		if ((gLExtract[i] <= 0.f) || (gLPos[i].distance2D(pos) >= reach))
			continue;
		const AIFloat3 rel = gLPos[i] - pos;
		if ((rel.x * dir.x + rel.z * dir.z) > 0.f)
			continue;   // the enemy meets this one before the turret
		m += gLIncome[i] * gLExtract[i] * h;
	}
	for (uint i = 0; i < gOwnBig.length(); ++i) {
		if (gOwnBig[i] is null) continue;
		const AIFloat3 bp = gOwnBig[i].GetPos(ai.frame);
		if (bp.distance2D(pos) >= reach) continue;
		const AIFloat3 rel = bp - pos;
		if ((rel.x * dir.x + rel.z * dir.z) > 0.f) continue;
		m += Catalog::gCostM[int(gOwnBig[i].circuitDef.id)];
	}
	for (uint i = 0; i < gOwnGen.length(); ++i) {
		if (gOwnGen[i] is null) continue;
		const AIFloat3 gp = gOwnGen[i].GetPos(ai.frame);
		if (gp.distance2D(pos) >= reach) continue;
		const AIFloat3 rel = gp - pos;
		if ((rel.x * dir.x + rel.z * dir.z) > 0.f) continue;
		m += Catalog::gCostM[int(gOwnGen[i].circuitDef.id)];
	}
	return m;
}

// Is this mex defended -- the question the boolean radius test could not
// answer. Fraction of the local threat our standing coverage fails to stop.
float ShortfallAt(const AIFloat3& in pos)
{
	const float threat = ThreatM(pos);
	if (threat <= 1.f)
		return 0.f;
	const float gap = threat - CoverAt(pos);
	if (gap <= 0.f)
		return 0.f;
	return gap / threat;
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
float ThreatM(const AIFloat3& in pos)
{
	if (!OnMap(pos))
		return 0.f;
	float t = ai.GetEnemyCostAt(pos, ai.GetTunable("apex_threat_r", TUNE_THREAT_R));
	const float implied = LossRateAt(pos)
			* ai.GetTunable("apex_eco_raid_tau", TUNE_ECO_RAID_TAU);
	if (implied > t)
		t = implied;
	// Cold start: before anything has been lost or seen here, the wave to
	// expect is the enemy's RAIDING force -- the class that actually visits
	// an outlying mex. Measured, and raid-sized rather than army-sized.
	//
	// NOT scaled by ExposureAt any more. That factor is zero AT HOME by
	// construction (distance to home over a radius), so the base -- the thing
	// the enemy most wants dead -- priced as the safest ground on the map:
	// threat 0 gives shortfall 0, which zeroes every turret's gain there AND
	// makes the tech survival discount exactly 1.0. Watched: "2 enemy units
	// just destroyed our entire base. We made 0 defenses"; "we made a T2 lab
	// REALLY EARLY... all this tells me the threat/danger sense is tuned low".
	// Wave SIZE is the same wherever it goes; how OFTEN it arrives is
	// HazardAt's job, which is what this file's own header says.
	const float baseline = Military::EnemyCostOf(Unit::Role::RAIDER.type);
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
float HazardAt(const AIFloat3& in pos)
{
	const float horiz = ai.GetTunable("apex_exposed_loss_s", TUNE_EXPOSED_LOSS_S);
	const float anchor = 1.f / ((horiz > 1.f) ? horiz : 120.f);
	const float r = ai.GetTunable("apex_threat_r", TUNE_THREAT_R);
	const float tau = ai.GetTunable("apex_eco_raid_tau", TUNE_ECO_RAID_TAU);
	// What we have actually been losing here, against what is standing here.
	const float stake = StakeAt(pos, r);
	float p = 0.f;
	if (stake > 1.f)
		p = LossRateAt(pos) * tau / stake;
	// Their army against everything that defends this ground -- our own
	// mobile army plus the turrets that reach, scaled by how far out it is.
	const float defended = Military::OurArmyNow() + CoverAt(pos);
	const float foe = Military::FoeMobileMassing();
	if (foe > 0.f) {
		// Their mobile mass against everything that defends THIS ground. The
		// ExposureAt factor that used to multiply this is gone for the same
		// reason as in ThreatM: it is zero at home, so the one place with
		// everything to lose reported the floor hazard all game. Position
		// still matters here -- through CoverAt, which is what actually
		// differs between a guarded core and an outlying mex.
		const float pres = foe / (foe + ((defended > 0.f) ? defended : 0.f));
		if (pres > p)
			p = pres;
	}
	const float floorP = ai.GetTunable("apex_risk_floor", TUNE_RISK_FLOOR);
	if (p < floorP)
		p = floorP;
	if (p > 1.f)
		p = 1.f;
	return anchor * p;
}

// The expected-loss stream on value standing at pos, in metal/s -- the one
// quantity both the protect gain and the exposure premium are built from.
float ExpectedLossAt(const AIFloat3& in pos, float valueM)
{
	if (valueM <= 0.f)
		return 0.f;
	return valueM * HazardAt(pos) * ShortfallAt(pos);
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
