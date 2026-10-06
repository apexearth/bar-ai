namespace Military {

// DANGER: their army against how soon it reaches our base (his 2026-10-05).
// Every seen or radar-known enemy ground unit is binned by the seconds it needs
// to bring its gun onto our base edge (distance past its range over its own
// speed); our ground army is binned the same way by its walk home, on top of
// the guns standing at the base. Map size enters only through those seconds.
// Strength is Market::UnitStrength; only ratios of it mean anything (a T1
// unit reads ~0.03). A pass every 5 s, staggered by team; accessors read prefix sums.
const float DG_BIN_S = 5.f;
const int DG_BINS = 120;    // 600 s; anything slower sits in the last bin

array<float> gDgFoe(DG_BINS + 1, 0.f);    // cumulative: arrives within (i+1)*DG_BIN_S
array<float> gDgOurs(DG_BINS + 1, 0.f);
array<float> gDgStrOf;
float gDgGuns = 0.f;        // standing guns covering the base, strength
int gDgGunN = 0;
float gDgFoeBaseD = -1.f;
float gDgFoeSpd = 0.f;      // metal-weighted speed of their seen ground army
float gDgUnseenM = 0.f;     // believed army not in any seen group, metal
float gDgUnseenEta = -1.f;
int gDgBfNoSlot = 0;        // base-front refusals while the gap stood
int gDgBfFar = 0;
float gDgNearEta = -1.f;    // the nearest armed enemy ground unit
int gDgUnknown = 0;         // radar members with no def, at their group mean cost
int gDgAt = -999999;
int gDgNextLog = 0;
bool gDgContact = false;
int gDgContactN = 0;
int gDgFirstContactAt = -1;
int gDgGunsAtFirst = -1;
int gDgPushes = 0;          // base-front guns handed out while the gap stood
int gDgPushesEarly = 0;     // ...of those, before the first contact

float DgStr(int d)
{
	if ((d <= 0) || (d > Catalog::gDefCount))
		return 1.f;
	if (int(gDgStrOf.length()) <= Catalog::gDefCount)
		gDgStrOf.resize(Catalog::gDefCount + 1);
	if (gDgStrOf[d] <= 0.f)
		gDgStrOf[d] = Market::UnitStrength(d);
	return gDgStrOf[d];
}

int DgBin(float etaS)
{
	int b = int(etaS / DG_BIN_S);
	return (b < 0) ? 0 : ((b > DG_BINS) ? DG_BINS : b);
}

// How far outside the base this point is: past the wall when it stands,
// else from home.
float DgRim(const AIFloat3& in p)
{
	if (Market::WallStands())
		return Market::WallRimDist(p);
	return p.distance2D(Builder::gHomePos);
}

void DangerUpdate()
{
	if (!Builder::gHomeSet || (ai.frame < gDgAt + 5 * SECOND + (ai.teamId % 5) * 3))
		return;
	gDgAt = ai.frame;
	// strength of a def moves only with the worth means; refresh it per pass
	gDgStrOf.resize(0);
	array<float> foe(DG_BINS + 1, 0.f);
	array<float> ours(DG_BINS + 1, 0.f);
	float near = -1.f;
	int unknown = 0;
	float seenM = 0.f, seenSpdM = 0.f;
	const float foeQ = Market::FoeQualityM();
	const int nG = aiEnemyMgr.GetEnemyGroupCount();
	for (int gi = 0; gi < nG; ++gi) {
		const AIFloat3 gp = aiEnemyMgr.GetEnemyGroupPos(gi);
		if (!OnMap(gp))
			continue;
		const float gVel = aiEnemyMgr.GetEnemyGroupVel(gi);
		const float rim = DgRim(gp);
		const int nU = aiEnemyMgr.GetEnemyGroupUnitCount(gi);
		for (int k = 0; k < nU; ++k) {
			const int d = aiEnemyMgr.GetEnemyGroupUnitDef(gi, k);
			float s, spd, rng;
			if ((d > 0) && (d <= Catalog::gDefCount)) {
				if (!Catalog::gMobile[d] || (Catalog::gPower[d] <= 1.f)
					|| Catalog::Def(d).IsAbleToFly())
					continue;
				s = DgStr(d);
				spd = Catalog::gSpeed[d];
				rng = Catalog::gMaxRange[d];
				seenM += Catalog::gCostM[d];
				seenSpdM += Catalog::gCostM[d] * spd;
			} else {
				// radar only: a moving group's unknown member at the group's mean cost
				if ((gVel <= 1.f) || (nU <= 0))
					continue;
				s = foeQ * aiEnemyMgr.GetEnemyGroupCost(gi) / float(nU);
				spd = gVel;
				rng = 0.f;
				++unknown;
			}
			if (spd <= 1.f)
				continue;
			float gap = rim - rng;
			if (gap < 0.f)
				gap = 0.f;
			const float eta = gap / spd;
			foe[DgBin(eta)] += s;
			if ((near < 0.f) || (eta < near))
				near = eta;
		}
	}
	for (uint i = 0; i < gCombatId.length(); ++i) {
		CCircuitUnit@ u = ai.GetTeamUnit(Id(gCombatId[i]));
		if ((u is null) || (u.circuitDef is null) || u.circuitDef.IsAbleToFly())
			continue;
		const int d = int(u.circuitDef.id);
		const float spd = Catalog::gSpeed[d];
		const AIFloat3 p = u.GetPos(ai.frame);
		if (!OnMap(p) || (spd <= 1.f))
			continue;
		float gap = DgRim(p);
		if (gap < 0.f)
			gap = 0.f;
		ours[DgBin(gap / spd)] += DgStr(d) * u.GetHealthPercent();
	}
	int gunN = 0;
	gDgGuns = Market::HomeGunStrength(gunN);
	gDgGunN = gunN;
	AIFloat3 fb = aiSetupMgr.GetEnemyBoxCentre();
	if (!OnMap(fb))
		fb = Front::FoeAnchor();
	gDgFoeBaseD = OnMap(fb) ? fb.distance2D(Builder::gHomePos) : -1.f;
	// The army we believe they have but cannot see is assumed at their base:
	// it arrives in the walk from there, which is where map size enters.
	if (seenM > 0.f)
		gDgFoeSpd = seenSpdM / seenM;
	float unseenM = EnemyArmyCost() - seenM;
	gDgUnseenM = (unseenM > 0.f) ? unseenM : 0.f;
	gDgUnseenEta = -1.f;
	if ((gDgUnseenM > 0.f) && OnMap(fb)) {
		const float spd = (gDgFoeSpd > 1.f) ? gDgFoeSpd : Market::FoeSpeedCap();
		float gap = DgRim(fb);
		if (gap < 0.f)
			gap = 0.f;
		if (spd > 1.f) {
			gDgUnseenEta = gap / spd;
			foe[DgBin(gDgUnseenEta)] += gDgUnseenM * foeQ;
		}
	}
	for (int b = 1; b <= DG_BINS; ++b) {
		foe[b] += foe[b - 1];
		ours[b] += ours[b - 1];
	}
	gDgFoe = foe;
	gDgOurs = ours;
	gDgNearEta = near;
	gDgUnknown = unknown;

	// contact: armed enemy ground on our edge now
	const bool contact = gDgFoe[0] > 0.f;
	if (contact && !gDgContact) {
		++gDgContactN;
		if (gDgFirstContactAt < 0) {
			gDgFirstContactAt = ai.frame;
			gDgGunsAtFirst = gDgGunN;
		}
		AiLog(Factory::T() + "apex: danger-contact t=" + ai.teamId + " n=" + gDgContactN
			+ " now=" + formatFloat(gDgFoe[0], "", 0, 3)
			+ " a60=" + formatFloat(DangerArriveS(60.f), "", 0, 3)
			+ " home=" + formatFloat(HomeStrength(), "", 0, 3)
			+ " guns=" + gDgGunN + " gunS=" + formatFloat(gDgGuns, "", 0, 3)
			+ " gapS=" + formatFloat(DangerGap(), "", 0, 3));
	}
	gDgContact = contact;
	if (ai.frame >= gDgNextLog) {
		gDgNextLog = ai.frame + 30 * SECOND;
		AiLog(Factory::T() + "apex: danger t=" + ai.teamId
			+ " a60=" + formatFloat(DangerArriveS(60.f), "", 0, 3)
			+ " a120=" + formatFloat(DangerArriveS(120.f), "", 0, 3)
			+ " a180=" + formatFloat(DangerArriveS(180.f), "", 0, 3)
			+ " h0=" + formatFloat(HomeStrength(), "", 0, 3)
			+ " h60=" + formatFloat(HomeStrengthS(60.f), "", 0, 3)
			+ " h180=" + formatFloat(HomeStrengthS(180.f), "", 0, 3)
			+ " r60=" + formatFloat(DangerRatio(60.f), "", 0, 2)
			+ " r180=" + formatFloat(DangerRatio(180.f), "", 0, 2)
			+ " gap=" + formatFloat(DangerGap(), "", 0, 3)
			+ " breach=" + formatFloat(DangerBreachS(), "", 0, 0)
			+ " near=" + formatFloat(gDgNearEta, "", 0, 0)
			+ " foeBase=" + formatFloat(gDgFoeBaseD, "", 0, 0)
			+ " guns=" + gDgGunN + "/" + formatFloat(gDgGuns, "", 0, 3)
			+ " unk=" + gDgUnknown
			+ " unseenM=" + formatFloat(gDgUnseenM, "", 0, 0)
			+ " unseenEta=" + formatFloat(gDgUnseenEta, "", 0, 0)
			+ " bfNoSlot=" + gDgBfNoSlot + " bfFar=" + gDgBfFar
			+ " contacts=" + gDgContactN
			+ " firstAt=" + formatFloat((gDgFirstContactAt < 0) ? -1.f : float(gDgFirstContactAt) / (60.f * SECOND), "", 0, 3)
			+ " gunsAtFirst=" + gDgGunsAtFirst
			+ " bfPush=" + gDgPushes + " bfEarly=" + gDgPushesEarly
			+ " t2=" + (Factory::gHaveT2 ? "1" : "0"));
	}
}

float DgCum(const array<float>& in a, float horizonS)
{
	if (horizonS < 0.f)
		return 0.f;
	return a[DgBin(horizonS)];
}

// ---- accessors for the nets (strength units; seconds; elmos) ----

// Enemy ground strength that can bring its guns onto our base edge within
// horizonS seconds.
float DangerArriveS(float horizonS) { return DgCum(gDgFoe, horizonS); }
// Our guns at the base plus our ground army that can be home within horizonS.
float HomeStrengthS(float horizonS) { return gDgGuns + DgCum(gDgOurs, horizonS); }
float HomeStrength() { return HomeStrengthS(0.f); }
// theirs/ours at a horizon; 0 with nothing coming.
float DangerRatio(float horizonS)
{
	const float a = DangerArriveS(horizonS);
	if (a <= 0.f)
		return 0.f;
	const float h = HomeStrengthS(horizonS);
	return a / ((h > 0.1f) ? h : 0.1f);
}
// The horizon the gap is read over: our army's own fill time -- past it,
// production answers what walks in.
float DangerHorizonS()
{
	const float h = ai.GetTunable("apex_army_fill_s", TUNE_ARMY_FILL_S);
	return (h > DG_BIN_S) ? h : DG_BIN_S;
}
// The worst shortfall of home strength against what has arrived, over the
// horizon. 0 when home holds everything that can reach it in time.
float DangerGap()
{
	const int last = DgBin(DangerHorizonS());
	float g = 0.f;
	for (int b = 0; b <= last; ++b) {
		const float x = gDgFoe[b] - gDgGuns - gDgOurs[b];
		if (x > g)
			g = x;
	}
	return g;
}
// Seconds until arriving strength first beats home strength; -1 if never
// inside the horizon.
float DangerBreachS()
{
	const int last = DgBin(DangerHorizonS());
	for (int b = 0; b <= last; ++b) {
		if (gDgFoe[b] > gDgGuns + gDgOurs[b])
			return float(b) * DG_BIN_S;
	}
	return -1.f;
}
// Seconds for the nearest armed enemy ground unit to reach gun range of our
// edge; -1 when none is known.
float NearestFoeEtaS() { return gDgNearEta; }
// Home to their start box (their structures as fallback), elmos.
float FoeBaseDist() { return gDgFoeBaseD; }
int HomeGunCount() { return gDgGunN; }

// Seconds for the army they have but we cannot see to walk from their base.
float UnseenFoeEtaS() { return gDgUnseenEta; }

void DangerNoteBfMiss(bool noSlot)
{
	if (noSlot)
		++gDgBfNoSlot;
	else
		++gDgBfFar;
}

void DangerNotePush()
{
	++gDgPushes;
	if (gDgFirstContactAt < 0)
		++gDgPushesEarly;
}

}  // namespace Military
