namespace Market {

// SMALL-MAP PRESSURE (apex_small_pressure, his 2026-10-15: on small maps go harder on
// military, deny them the map, aim for a shorter game). Everything is scaled by the
// rush model's contact time Tc (rush.as) against their army rate:
//   r     = their army output per fighting seat of ours (rush rate / fighting seats)
//   T_A   = our base army target x 1.2 / r: their time to field what beats our holding army
//   H_eff = H x min(1, (Tc + T_A) / (2 T_A))          H = apex_payback_h
//   hold  = H / H_eff on ArmyTargetFull                (1 .. 2)
// Walk outlasting that build (Tc >= T_A) leaves every price and target as it was.
// Team push: A = our seats' armies (board), each x min(1, Tc / its walk to the target),
// seats whose own base is raided or contested left out; B = their mobile army (seen or
// believed) + their whole team's rate x Tc. GO while StrRatio(B, A) < 1 lifts the soft
// holds (enemy near home, the stance hold). Map control: the team operation may target
// their extractor within Tc's reach whose denied income over H_eff, less the Lanchester
// loss, nets most; outer extractors want guns beyond the first x (1 - kappa x A/(A+B)),
// kappa = hold - 1. Refreshed on the rush clock; elections read the cached results.

const string TV_PRESS_PIN = "presspin";
const string TV_PRESS_GO = "pressgo";

bool gPressOn = false;
bool gPressOnRead = false;
int gPressAt = -999999;
int gPressLogAt = 0;
float gPressH = 0.f;          // effective horizon; 0 while off (PayH falls back)
float gPressHoldMul = 1.f;
float gPressKappa = 0.f;
float gPressTA = 0.f;
float gPressR = 0.f;
float gPressGunMul = 1.f;
float gPressJoin = 0.f;
float gPressFront = 0.f;
float gPressStr = 0.f;
bool gPressGo = false;
bool gPressPinned = false;
int gPressJoined = 0;
int gPressSeats = 0;
int gPressLaunchN = 0;
int gPressExpOps = 0;
int gPressExpKills = 0;
float gPressExpNet = 0.f;

bool PressureOn()
{
	if (!gPressOnRead) {
		gPressOnRead = true;
		gPressOn = ai.GetTunable("apex_small_pressure", TUNE_SMALL_PRESSURE) > 0.f;
	}
	return gPressOn;
}

float PayH()
{
	PrTuneFill();
	return (gPressH > 0.f) ? gPressH : gPrPaybackH;
}

bool PressGo() { return gPressGo; }
bool PressShort() { return gPressKappa > 0.f; }

void PressRefresh()
{
	gPressAt = gRushAt;
	PrTuneFill();
	const float H = gPrPaybackH;
	gPressH = H;
	gPressHoldMul = 1.f;
	gPressKappa = 0.f;
	gPressTA = 0.f;
	gPressR = gRushRate / float((gRushFighting > 0) ? gRushFighting : 1);
	if ((gRushTc >= 0.f) && (gPressR > 0.f) && (H > 1.f)) {
		gPressTA = ArmyTargetBase() * ARMY_FLOOR_PARITY / gPressR;
		if (gPressTA > gRushTc) {
			const float f = (gRushTc + gPressTA) / (2.f * gPressTA);
			gPressH = H * f;
			gPressHoldMul = 1.f / f;
			gPressKappa = gPressHoldMul - 1.f;
		}
	}

	gPressPinned = Military::BaseRaided() || Military::BaseContested();
	ai.PublishTeamValue(TV_PRESS_PIN, gPressPinned ? 1.f : 0.f);
	float tr = 0.f;
	AIFloat3 tgt = Front::FoeAnchor();
	if (TeamOpOn())
		tgt = TaTarget(tr);
	const bool tgtOn = OnMap(tgt) && (gRushSpd > 1.f) && (gRushTc >= 0.f);
	array<Id>@ mates = ai.GetTeamIds();
	float join = 0.f;
	int seats = 0, joined = 0;
	for (uint m = 0; (mates !is null) && (m < mates.length()); ++m) {
		const int t = int(mates[m]);
		const float armyM = ai.ReadTeamValue(t, Military::TV_ARMY, 0.f);
		if (armyM <= 0.f)
			continue;
		++seats;
		if (ai.ReadTeamValue(t, TV_PRESS_GO, 0.f) > 0.5f)
			++joined;
		if (ai.ReadTeamValue(t, TV_PRESS_PIN, 0.f) > 0.5f)
			continue;
		float w = 1.f;
		const float hx = ai.GetTeamBoard(BOARD_TA_HOMEX + t, -1.f);
		if (tgtOn && (hx >= 0.f)) {
			const float walkS = tgt.distance2D(AIFloat3(hx, 0.f, ai.GetTeamBoard(BOARD_TA_HOMEZ + t, 0.f))) / gRushSpd;
			if (walkS > gRushTc)
				w = gRushTc / walkS;
		}
		join += armyM * w;
	}
	gPressJoin = join;
	gPressSeats = seats;
	gPressJoined = joined;
	float foe = Military::FoeMobileMassing();
	const float believed = Military::FoeBelievedM();
	foe = (believed > foe) ? believed : foe;
	gPressFront = foe + ((gRushTc > 0.f) ? gRushRate * gRushTc : 0.f);
	gPressStr = StrRatio(gPressFront, gPressJoin);   // the side: TeamArmyCost's per-seat terms, arrival-weighted
	const bool go = PressShort() && !gPressPinned && (gPressStr < 1.f);
	if (go && !gPressGo)
		++gPressLaunchN;
	gPressGo = go;
	ai.PublishTeamValue(TV_PRESS_GO, go ? 1.f : 0.f);

	const float share = (gPressJoin + gPressFront > 1.f) ? (gPressJoin / (gPressJoin + gPressFront)) : 0.f;
	float gm = 1.f - ((gPressKappa < 1.f) ? gPressKappa : 1.f) * share;
	gPressGunMul = (gm > 0.f) ? gm : 0.f;
}

// Their extractor within our contact reach, outside their base, whose income denied over
// the effective horizon (plus the structures there) best beats the expected loss taking it.
// Read by the team operation's leader when it opens an operation, never per election.
bool PressExpansion(AIFloat3 &out at, float &out r)
{
	gPressExpNet = 0.f;
	if (!PressShort() || (gRushDist <= 0.f) || (gAllSpots.length() == 0))
		return false;
	AIFloat3 from = Military::gLaneAt;
	if (!OnMap(from)) {
		if (!Builder::gHomeSet)
			return false;
		from = Builder::gHomePos;
	}
	const AIFloat3 box = aiSetupMgr.GetEnemyBoxCentre();
	const bool boxOn = OnMap(box);
	const float teamM = gPressJoin;
	float F = teamM * 0.017f;   // Grunt-class power per metal, as massing.as
	const float gath = TaSum(BOARD_GATHER);
	const float atk = TaSum(BOARD_TA_ATK);
	F = (gath > F) ? gath : F;
	F = (atk > F) ? atk : F;
	float best = 0.f;
	bool have = false;
	const int total = aiEnemyMgr.GetEnemyUnitTotal();
	for (int i = 0; i < total; ++i) {
		const int d = aiEnemyMgr.GetEnemyUnitDefAt(i);
		if ((d <= 0) || (d > Catalog::gDefCount) || Catalog::gMobile[d] || (Catalog::gExtractsM[d] <= 0.f))
			continue;
		const int los = aiEnemyMgr.GetEnemyUnitLosAt(i);
		if ((los < 0) || ((los & (8 | 32 | 64)) != 0))
			continue;
		const AIFloat3 p = aiEnemyMgr.GetEnemyUnitPosAt(i);
		if (!OnMap(p) || (p.distance2D(from) > gRushDist))
			continue;
		if (boxOn && (p.distance2D(box) < Builder::BASE_DANGER_DIST))
			continue;
		float inc = 0.f, dBest = -1.f;
		for (uint s = 0; s < gAllSpots.length(); ++s) {
			const float dd = gAllSpots[s].SqDistance2D(p);
			if ((dBest < 0.f) || (dd < dBest)) {
				dBest = dd;
				inc = gAllSpotInc[s];
			}
		}
		const float prize = aiEnemyMgr.GetEnemyStructCostAt(p, Military::HUNT_R)
				+ inc * Catalog::gExtractsM[d] * PayH();
		const float E = aiMilitaryMgr.GetEnemyInflNear(p, Military::HUNT_R + PUSH_STAND);
		const float lossF = Military::NrLossFrac(E, F);
		const float net = prize * (1.f - lossF) - lossF * teamM;
		if ((net > 0.f) && (!have || (net > best))) {
			best = net;
			at = p;
			have = true;
		}
	}
	if (!have)
		return false;
	r = Military::HUNT_R;
	gPressExpNet = best;
	return true;
}

void PressNoteDeath(int d, const AIFloat3& in pos, bool byUs)
{
	if (!byUs || !gPressOn || !Catalog::ValidId(d) || Catalog::gMobile[d] || (Catalog::gExtractsM[d] <= 0.f))
		return;
	const AIFloat3 box = aiSetupMgr.GetEnemyBoxCentre();
	if (OnMap(box) && (pos.distance2D(box) < Builder::BASE_DANGER_DIST))
		return;
	++gPressExpKills;
}

void PressUpdate()
{
	if (!PressureOn())
		return;
	if (gPressAt != gRushAt)
		PressRefresh();
	if (ai.frame < gPressLogAt)
		return;
	gPressLogAt = ai.frame + 60 * SECOND;
	AiLog(Factory::T() + "apex: pressure-stat t=" + ai.teamId
		+ " Tc=" + formatFloat(gRushTc, "", 0, 0)
		+ " TA=" + formatFloat(gPressTA, "", 0, 0)
		+ " Heff=" + formatFloat(gPressH, "", 0, 0) + "/" + formatFloat(gPrPaybackH, "", 0, 0)
		+ " hold=" + formatFloat(gPressHoldMul, "", 0, 2)
		+ " armyTgt=" + formatFloat(ArmyTargetBase(), "", 0, 0) + "->" + formatFloat(ArmyTargetFull(), "", 0, 0)
		+ " army=" + formatFloat(ArmyValue(), "", 0, 0)
		+ " team=" + formatFloat(gPressJoin, "", 0, 0)
		+ " front=" + formatFloat(gPressFront, "", 0, 0)
		+ " str=" + formatFloat(gPressStr, "", 0, 2)
		+ " go=" + (gPressGo ? 1 : 0) + " pinned=" + (gPressPinned ? 1 : 0)
		+ " pushes=" + gPressLaunchN + " joined=" + gPressJoined + "/" + gPressSeats
		+ " holdWhy=" + Military::HoldWhy()
		+ " expOps=" + gPressExpOps + " expNet=" + formatFloat(gPressExpNet, "", 0, 0)
		+ " expKilled=" + gPressExpKills
		+ " gunMul=" + formatFloat(gPressGunMul, "", 0, 2));
}

}  // namespace Market
