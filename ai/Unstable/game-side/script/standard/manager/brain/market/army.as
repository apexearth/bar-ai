namespace Market {
//------------------------------------------------------------------------------
// THE ARMY MODEL -- one modeled quantity (value-paradigm): the army value
// worth standing. Insurance on what we own, plus matching what the enemy
// has been SEEN to field (a blind census reads low; the guard term is the
// floor that covers blindness).
//------------------------------------------------------------------------------

// Army value held in one role -- the portfolio sense. An army is role
// COVERAGE (apexearth: only ticks, pawns, rovers -- "where's the rest?");
// each next unit's gain diminishes by its role's share, so raiders
// saturate and the empty roles win the auction.
float RoleValue(int role)
{
	float v = 0.f;
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		if ((gOwnCount[d] <= 0) || !Catalog::gMobile[int(d)])
			continue;
		if (Catalog::gBuilder[int(d)] || (Catalog::gPower[int(d)] <= 1.f))
			continue;
		if (Catalog::gRole[int(d)] == role)
			v += float(gOwnCount[d]) * Catalog::gCostM[int(d)];
	}
	return v;
}

// Role TARGETS from what the enemy fields (apexearth 2026-08-23: "balance
// the army based on our needs" -- siege wants range, soak wants HP, air
// wants AA). BAR's counter mechanics, priced: AA tracks enemy air, riot
// tracks enemy raiders, skirm/arty track enemy static, assault carries the
// general line. A uniform baseline keeps a portfolio before contact.
// Exposed workers without an escort -- each is standing demand for one
// cheap raider (apexearth: "a *need* is cheap escorts for cons").
int EscortShortfall()
{
	if (!gFarmSet)
		return 0;
	const float expoR = ai.GetTunable("apex_expose_r", TUNE_EXPOSE_R);
	int n = 0;
	for (uint i = 0; i < gWorkers.length(); ++i) {
		CCircuitUnit@ wkr = gWorkers[i];
		if ((wkr is null) || (wkr.task is null))
			continue;
		if (Catalog::gFlyer[int(wkr.circuitDef.id)])
			continue;
		if (wkr.circuitDef.IsRoleAny(Unit::Role::COMM.mask))
			continue;   // the commander is his own escort
		if (wkr.GetPos(ai.frame).distance2D(gFarmPos)
				/ ((expoR > 1.f) ? expoR : 1200.f) < 0.5f)
			continue;
		bool has = false;
		for (uint e = 0; e < gEscWorker.length(); ++e) {
			if (gEscWorker[e] == wkr.id) {
				has = true;
				break;
			}
		}
		if (!has)
			++n;
	}
	return n;
}

float RoleTarget(int role, float armyTarget)
{
	// AA is a PURE COUNTER: it has no value without enemy air, so it gets
	// no baseline share (watched: AA against a ground-only 1v1 enemy).
	if (role == int(Unit::Role::AA.type)) {
		// FRESH air only (GetEnemyCost never forgets a plane once seen --
		// 25k of AA vs an enemy that quit flying, watched 8v8), and OUR
		// SHARE of the team's counter: the census sums all enemies while
		// every ally instance would otherwise build the full answer.
		const float team = Military::TeamArmyCost();
		const float mine = aiMilitaryMgr.armyCost;
		const float share = (team > mine && team > 1.f) ? (mine / team) : 1.f;
		return aiEnemyMgr.GetEnemyCostFresh(RT::AIR)
				* ai.GetTunable("apex_aa_match", TUNE_AA_MATCH) * share;
	}
	const float base = armyTarget / 6.f;   // maximum-entropy prior over combat roles
	float counter = 0.f;
	if (role == int(Unit::Role::RAIDER.type))
		counter = float(EscortShortfall()) * 60.f   // ~ one cheap escort each
			+ (Military::EnemyCostOf(Unit::Role::SKIRM.type)
				+ Military::EnemyCostOf(Unit::Role::ARTY.type)) * 0.6f;
			// rocket bots die to what closes fast (apexearth's counter-chain)
	else if (role == int(Unit::Role::RIOT.type))
		counter = Military::EnemyCostOf(Unit::Role::RAIDER.type);
	else if ((role == int(Unit::Role::SKIRM.type))
			|| (role == int(Unit::Role::ARTY.type)))
		counter = aiEnemyMgr.GetEnemyCost(RT::STATIC) * 0.5f;
	else if (role == int(Unit::Role::ASSAULT.type))
		counter = Military::EnemyCostOf(Unit::Role::ASSAULT.type);
	return base + counter;
}

// The production appetite one standing line carries, metal/s -- what a
// factory's existence is WORTH beyond expansion, what its nano ring must
// absorb, and what an assist bid against it can earn. (Watched: a lab
// killed by artillery never rebuilt -- the plant want only priced open
// spots; and hot lines ran on one nano with no help.)
float LineSpend()
{
	const float fillS = ai.GetTunable("apex_army_fill_s", TUNE_ARMY_FILL_S);
	const float gap = ArmyTarget() - ArmyValue();
	float s = (gap > 0.f) ? (gap / ((fillS > 1.f) ? fillS : 180.f)) : 0.f;
	const float ovf = OverflowM();
	if (ovf > s)
		s = ovf;
	const int lines = (Factory::gFactoryCount > 0) ? Factory::gFactoryCount : 1;
	return s / float(lines);
}

float ArmyValue()
{
	float v = 0.f;
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		if ((gOwnCount[d] <= 0) || !Catalog::gMobile[int(d)])
			continue;
		if (Catalog::gBuilder[int(d)] || (Catalog::gPower[int(d)] <= 1.f)
			|| Catalog::gKamikaze[int(d)])
			continue;
		v += float(gOwnCount[d]) * Catalog::gCostM[int(d)];
	}
	return v;
}

// THE REAR SPECIALIST (apexearth 2026-08-23): in a big team game one
// player starts obviously farther from the enemy than everyone else.
// Fighting from there wastes walk time; scaling from there compounds.
// That player suppresses the army market -- the freed spend rides the
// existing eco ladder to fusions/AFUS/gantry -- and its late army budget
// carries a QUALITY bias so it buys the biggest units its labs offer
// (T3, heavy air) instead of T1/T2 it would never deliver in time.
// Election: allies' homes off the team blackboard; the enemy reference is
// the ally centroid mirrored through map center (symmetric starts, no
// sighting needed). Rear-most wins only with a clear margin over #2.
bool gEcoRole = false;
bool gEcoDiagDone = false;
int gEcoRoleAt = -999999;
bool EcoRoleActive()
{
	if (ai.frame < gEcoRoleAt + 10 * SECOND)
		return gEcoRole;
	gEcoRoleAt = ai.frame;
	EcoStatusLog();
	const bool was = gEcoRole;
	gEcoRole = false;
	if (!Builder::gHomeSet)
		return false;
	array<Id>@ mates = ai.GetTeamIds();
	if ((mates is null) || (mates.length() < 4))
		return false;
	array<float> hx, hz;
	float cx = 0.f, cz = 0.f;
	for (uint i = 0; i < mates.length(); ++i) {
		const float x = ai.ReadTeamValue(int(mates[i]), "homex", -1.f);
		const float z = ai.ReadTeamValue(int(mates[i]), "homez", -1.f);
		if ((x < 0.f) || (z < 0.f))
			continue;
		hx.insertLast(x);
		hz.insertLast(z);
		cx += x;
		cz += z;
	}
	if (hx.length() < 4)
		return false;
	cx /= float(hx.length());
	cz /= float(hx.length());
	const float ex = float(AiTerrainWidth()) - cx;
	const float ez = float(AiTerrainHeight()) - cz;
	gEcoRefX = ex;
	gEcoRefZ = ez;
	array<float> ds;
	float d1 = 0.f;
	for (uint i = 0; i < hx.length(); ++i) {
		const float dx = hx[i] - ex;
		const float dz = hz[i] - ez;
		const float dd = dx * dx + dz * dz;
		ds.insertLast(dd);
		if (dd > d1)
			d1 = dd;
	}
	ds.sortAsc();
	const float dmed = ds[ds.length() / 2];
	const float mx = Builder::gHomePos.x - ex;
	const float mz = Builder::gHomePos.z - ez;
	const float mine = mx * mx + mz * mz;
	const float margin = ai.GetTunable("apex_eco_rear_margin", TUNE_ECO_REAR_MARGIN);
	gEcoRole = (mine >= d1) && (dmed > 1.f) && (mine >= dmed * margin * margin);
	if (!gEcoDiagDone) {
		gEcoDiagDone = true;
		AiLog("apex: rear-elect homes=" + hx.length() + " mine=" + sqrt(mine)
				+ " far=" + sqrt(d1) + " median=" + sqrt(dmed));
	}
	if (gEcoRole != was) {
		AiLog("apex: rear-specialist " + (gEcoRole ? "ON" : "off")
				+ " team=" + ai.teamId
				+ " mine=" + sqrt(mine) + " median=" + sqrt(dmed));
		// A chat line survives on screen; log lines scroll away (apexearth).
		ai.SendChat(gEcoRole
				? ("I am the eco specialist (team " + ai.teamId
					+ ", rear position): scaling economy, no army until T3.")
				: ("Eco specialist role off (team " + ai.teamId + ")."));
	}
	return gEcoRole;
}

// The specialist's exemption ends when the war reaches it: a KNOWN front
// inside the safe radius restores every normal response.
// Danger is ENEMY AT THE DOOR, not geometry: front-line distance read
// structurally true in a packed team box (audited: the exempted specialist
// built 8.6k army, 510 defence, teched LAST -- quiet mode never engaged).
// Sustained presence arms danger; one clear read disarms. A single plane
// overflight flipped quiet mode for one refresh and bought dragon-claw
// towers at 13m (audited flicker -- danger=0 at every 2-min sample).
int gEcoDangerStreak = 0;
int gEcoDangerTickAt = 0;
bool gEcoDangerArmed = false;
bool EcoDangerNear()
{
	if (!Builder::gHomeSet)
		return false;
	// The streak ticks on a CLOCK, not per call -- EcoQuiet runs many
	// times per decide sweep, so a per-call streak armed in one frame off
	// a single overflight (claw at 4.8m with danger=0 at every sample).
	if (ai.frame >= gEcoDangerTickAt) {
		gEcoDangerTickAt = ai.frame + 10 * SECOND;
		const bool hot = ai.GetEnemyCostAt(Builder::gHomePos,
					ai.GetTunable("apex_eco_safe_r", TUNE_ECO_SAFE_R))
				> ai.GetTunable("apex_eco_danger_m", TUNE_ECO_DANGER_M);
		gEcoDangerStreak = hot ? (gEcoDangerStreak + 1) : 0;
		const bool armed = gEcoDangerStreak >= 3;   // 30s sustained
		if (armed != gEcoDangerArmed)
			AiLog("apex: eco-danger " + (armed ? "ARMED" : "cleared")
					+ " team=" + ai.teamId + " f=" + ai.frame);
		gEcoDangerArmed = armed;
	}
	return gEcoDangerArmed;
}

bool EcoQuiet()
{
	return EcoRoleActive() && !EcoDangerNear();
}

// The specialist works from home: any job farther than the leash is
// someone else's (apexearth: "keep our eco cons at home... not walking
// across the map").
bool EcoFar(const AIFloat3& in p)
{
	return EcoQuiet() && Builder::gHomeSet
		&& (p.distance2D(Builder::gHomePos)
			> ai.GetTunable("apex_eco_leash", TUNE_ECO_LEASH));
}

int gEcoStatusAt = 0;
void EcoStatusLog()
{
	if (!gEcoRole || (ai.frame < gEcoStatusAt))
		return;
	gEcoStatusAt = ai.frame + 120 * SECOND;
	AiLog("apex: eco-status team=" + ai.teamId
			+ " danger=" + (EcoDangerNear() ? 1 : 0)
			+ " foeNear=" + ai.GetEnemyCostAt(Builder::gHomePos,
					ai.GetTunable("apex_eco_safe_r", TUNE_ECO_SAFE_R))
			+ " bank=" + aiEconomyMgr.metal.current
			+ " inc=" + aiEconomyMgr.metal.income);
}

float ArmyTarget()
{
	// The SYMMETRIC PRIOR: pre-contact the census is blind, and blind read
	// as safe lost the first BARb game with three army units built. The
	// enemy's economy mirrors ours from the same start, so expect their
	// army to be a share of OUR total value until seen otherwise; the
	// observed census takes over as it grows past the prior.
	const float ourTotal = gAssetsM + ArmyValue();
	const float prior = ourTotal * ai.GetTunable("apex_enemy_prior", TUNE_ENEMY_PRIOR);
	const float seen = Military::EnemyArmyCost();
	const float expectedEnemy = (seen > prior) ? seen : prior;
	const float t = gAssetsM * ai.GetTunable("apex_guard_rate", TUNE_GUARD_RATE)
		+ expectedEnemy * ai.GetTunable("apex_match_ratio", TUNE_MATCH_RATIO);
	return EcoRoleActive()
			? (t * ai.GetTunable("apex_eco_army_mul", TUNE_ECO_ARMY_MUL)) : t;
}

// The target with NO role suppression: what the war actually asks for.
// The gantry want reads this one -- T3 is exactly what the eco role is FOR.
float ArmyTargetFull()
{
	const float ourTotal = gAssetsM + ArmyValue();
	const float prior = ourTotal * ai.GetTunable("apex_enemy_prior", TUNE_ENEMY_PRIOR);
	const float seen = Military::EnemyArmyCost();
	const float expectedEnemy = (seen > prior) ? seen : prior;
	return gAssetsM * ai.GetTunable("apex_guard_rate", TUNE_GUARD_RATE)
		+ expectedEnemy * ai.GetTunable("apex_match_ratio", TUNE_MATCH_RATIO);
}

// Own combat losses, decaying -- wrecks on the field are rez-bot demand.
float gLossPool = 0.f;
int gLossDecayAt = 0;
void LossNote(int defId)
{
	if (Catalog::gMobile[defId] && !Catalog::gBuilder[defId]
		&& (Catalog::gPower[defId] > 1.f))
	{
		gLossPool += Catalog::gCostM[defId];
	}
}
void LossDecay()
{
	if (ai.frame < gLossDecayAt + 10 * SECOND)
		return;
	gLossDecayAt = ai.frame;
	gLossPool *= 0.95f;   // wrecks get reclaimed, rezzed, or destroyed
}

// Round-robin over owned ceiling-reaching cons, for the guard floor-want.
uint gServeIdx = 0;
CCircuitUnit@ NextServingCon()
{
	const float ceilX = BestExtract();
	array<CCircuitUnit@> serving;
	for (uint i = 0; i < gWorkers.length(); ++i) {
		CCircuitUnit@ u = gWorkers[i];
		if (u is null)
			continue;
		const array<int>@ b = Catalog::BuildsOf(int(u.circuitDef.id));
		for (uint q = 0; q < b.length(); ++q) {
			if (Catalog::gExtractsM[b[q]] >= ceilX) {
				serving.insertLast(u);
				break;
			}
		}
	}
	if (serving.length() == 0)
		return null;
	gServeIdx = (gServeIdx + 1) % serving.length();
	return serving[gServeIdx];
}

// Fraction of known workers actually holding work. Idle cons mean labs and
// more cons are OVER-valued -- capability nobody uses is not capability
// (apexearth 2026-08-23: "we have cons we aren't even using so the value of
// making labs is over-estimated").
float Utilization()
{
	if (gWorkers.length() == 0)
		return 1.f;
	int busy = 0;
	for (uint i = 0; i < gWorkers.length(); ++i) {
		CCircuitUnit@ u = gWorkers[i];
		if ((u !is null) && (u.task !is null))
			++busy;
	}
	return float(busy) / float(gWorkers.length());
}

// Retreat pays only if the survivor gets HEALED: thresholds rise with the
// rez/repair fleet (apexearth: "we stay in the fight until death" + "rez
// bots heal our troops -- they make a big difference" -- the two are one
// design). Refreshed here as the fleet changes.
int gNextRetreatRefresh = 0;
void RetreatRefresh()
{
	if (ai.frame < gNextRetreatRefresh)
		return;
	gNextRetreatRefresh = ai.frame + 15 * SECOND;
	int rezzers = 0;
	for (uint d2 = 1; d2 < gOwnCount.length(); ++d2) {
		if ((gOwnCount[d2] > 0) && Catalog::gRezzer[int(d2)])
			rezzers += gOwnCount[d2];
	}
	float healBonus = 0.05f * float(rezzers);
	if (healBonus > 0.25f)
		healBonus = 0.25f;
	const float scale = ai.GetTunable("apex_retreat_cost_scale", TUNE_RETREAT_COST_SCALE);
	for (Id rd = 1; rd <= Id(Catalog::gDefCount); ++rd) {
		const int ri = int(rd);
		if (!Catalog::gMobile[ri] || Catalog::gBuilder[ri]
			|| (Catalog::gPower[ri] <= 1.f) || Catalog::gKamikaze[ri]
			|| Catalog::gRezzer[ri])
			continue;
		CCircuitDef@ rdef = ai.GetCircuitDef(rd);
		if (rdef is null)
			continue;
		float rt = 0.08f + Catalog::gCostM[ri] / ((scale > 1.f) ? scale : 3000.f)
				+ healBonus;
		if (rt > 0.55f)
			rt = 0.55f;
		rdef.SetRetreat(rt);
	}
}

void StallWatch()
{
	if (ai.frame < gNextStallSweep)
		return;
	gNextStallSweep = ai.frame + 5 * SECOND;
	RetreatRefresh();
	GuardSweep();
	if (!HardEStall())
		return;
	CCircuitUnit@ pick = null;
	for (uint i = 0; i < gWorkers.length(); ++i) {
		CCircuitUnit@ u = gWorkers[i];
		if (u is null)
			continue;
		IUnitTask@ t = u.task;
		if ((t is null) || (t.GetType() != Task::Type::BUILDER))
			continue;
		if (int(t.GetBuildType()) == int(Task::BuildType::ENERGY))
			continue;
		// (guard/patrol holders pass straight through: their work is worth
		// ~nothing mid-stall, so the dry-run below decides.)
		// Only interrupt a unit that could actually answer with energy.
		bool canE = false;
		const array<int>@ mine = Catalog::BuildsOf(int(u.circuitDef.id));
		for (uint b = 0; b < mine.length(); ++b) {
			if (Catalog::gMakeE[mine[b]] > 1.f) {
				canE = true;
				break;
			}
		}
		if (!canE)
			continue;
		// Dry-run the market (proposers are pure): interrupt only a unit
		// whose TOP want right now is energy -- a blind abort thrashed 73
		// times in one game, re-deciding the same mex it left.
		Want@ e = ProposeEnergy(u);
		if ((e is null) || (e.value <= 0.f))
			continue;
		Want@ mx = ProposeMex(u);
		if ((mx !is null) && (mx.value > e.value))
			continue;
		@pick = u;
		if (u.circuitDef.GetName() == "armcom" || u.circuitDef.GetName() == "corcom")
			break;   // the commander first when present
	}
	if (pick is null)
		return;
	AiLog("apex: STALL interrupt -- " + pick.circuitDef.GetName() + " #" + pick.id
		+ " leaves its build to answer the energy stall");
	pick.task.Abort();
}


}  // namespace Market
