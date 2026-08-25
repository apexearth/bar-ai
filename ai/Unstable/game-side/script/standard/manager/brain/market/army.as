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

// THE METAL STANDING UNESCORTED OUTSIDE SAFE GROUND, and the share of our
// build power that is actually protected.
//
// apexearth's value math: "a con outside of our home safe territory
// immediately has 0 value and making the cheap pawn would add the pawns value
// + the constructor value back." So an escort is not worth ~one cheap unit --
// it is worth the CONSTRUCTOR IT RESTORES, and build power we walk out alone
// should be priced as the write-off it is.
float EscortMetalAtRisk()
{
	if (!gFarmSet)
		return 0.f;
	const float expoR = ai.GetTunable("apex_expose_r", TUNE_EXPOSE_R);
	float m = 0.f;
	for (uint i = 0; i < gWorkers.length(); ++i) {
		CCircuitUnit@ wkr = gWorkers[i];
		if ((wkr is null) || (wkr.task is null))
			continue;
		const int wd = int(wkr.circuitDef.id);
		if (Catalog::gFlyer[wd])
			continue;
		if (wkr.circuitDef.IsRoleAny(Unit::Role::COMM.mask))
			continue;
		if (wkr.GetPos(ai.frame).distance2D(gFarmPos)
				/ ((expoR > 1.f) ? expoR : 1200.f) < 0.5f)
			continue;
		bool has = false;
		for (uint e = 0; e < gEscWorker.length(); ++e) {
			if (gEscWorker[e] == wkr.id) { has = true; break; }
		}
		if (!has)
			m += Catalog::gCostM[wd];
	}
	return m;
}

// 1.0 when every worker is home or escorted, falling toward 0 as more of our
// build power walks out alone. Multiplies what a NEW constructor is worth:
// buying more of something that dies unattended is buying less than it costs.
float BPProtectedFrac()
{
	float safe = 0.f;
	float risk = EscortMetalAtRisk();
	for (uint i = 0; i < gWorkers.length(); ++i) {
		CCircuitUnit@ wkr = gWorkers[i];
		if (wkr is null)
			continue;
		safe += Catalog::gCostM[int(wkr.circuitDef.id)];
	}
	safe -= risk;
	if (safe < 0.f)
		safe = 0.f;
	const float tot = safe + risk;
	if (tot <= 1.f)
		return 1.f;
	return safe / tot;
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
		// Escort demand is the CONSTRUCTOR METAL it brings back, not a flat
		// 60 per head: a pawn beside a 200-metal con is worth the pawn plus
		// the con it stops us writing off.
		counter = EscortMetalAtRisk()
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

// ARMY COMPOSITION AS A STANDING TARGET. apexearth, across one session:
// "we keep making spiders (Recluse), they're mostly only good against
// buildings... we need multiple fatboys with snipers behind them. Please
// think 'I need tanks, and I need damage behind the tanks'"; "we make a lot
// of T1 rocket bots. Low HP units with more range... on their own they're
// garbage"; and then the shape itself -- "how many tanky units do I have?
// How many higher range units? how much in the middle? and how much high dps
// unit?"
//
// Four classes, read off unit DATA so nothing here names a unit. DPS is not
// bound to script, but the DLL builds power = sqrt(dps)*dmg^0.25*sqrt(hp+
// shield)/128, so power*power/hp recovers dps up to constants -- and every
// consumer below normalizes, so the constants do not matter.
//
// Classification is against the GAME's own mobile combat units, not against
// what we happen to own: our own army is empty at the start and a mean taken
// over nothing classifies everything as middling. Shares are measured against
// our army; the class each candidate belongs to is a fact about the unit.
const int LC_TANK = 0, LC_MID = 1, LC_REACH = 2, LC_DPS = 3, LC_N = 4;

bool LineCombat(int di)
{
	return Catalog::gMobile[di] && !Catalog::gBuilder[di]
		&& (Catalog::gPower[di] > 1.f) && (Catalog::gCostM[di] > 0.f)
		&& (Catalog::gHealth[di] > 0.f) && !Catalog::gKamikaze[di];
}

float gLMeanHpm = -1.f, gLMeanDpm = 0.f, gLMeanR = 0.f, gLMeanSpc = 0.f;
void LineMeans()
{
	// Availability is frame-dependent; recompute until the field is non-empty
	// rather than latching a mean taken over nothing (see BestConvRatio).
	if (gLMeanHpm > 0.f)
		return;
	float hp = 0.f, dp = 0.f, rr = 0.f, sp = 0.f;
	int n = 0;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!Catalog::gAvailable[d] || !LineCombat(d))
			continue;
		hp += Catalog::gHealth[d] / Catalog::gCostM[d];
		dp += (Catalog::gPower[d] * Catalog::gPower[d] / Catalog::gHealth[d])
				/ Catalog::gCostM[d];
		rr += Catalog::gMaxRange[d];
		sp += Catalog::gSpeed[d] / Catalog::gCostM[d];
		++n;
	}
	if (n <= 0) {
		gLMeanHpm = -1.f;   // not yet knowable; ask again next call
		return;
	}
	gLMeanHpm = hp / float(n);
	gLMeanDpm = dp / float(n);
	gLMeanR = rr / float(n);
	gLMeanSpc = sp / float(n);
}

// Which of the four a unit IS: whichever axis it stands out on most. Nothing
// clearly above the field is the middle, which is a real role and not a
// leftover -- it is what holds a line together when the shields are gone.
int LineClassOf(int di)
{
	LineMeans();
	if ((gLMeanHpm <= 0.f) || !LineCombat(di))
		return LC_MID;
	const float hpR = (Catalog::gHealth[di] / Catalog::gCostM[di]) / gLMeanHpm;
	const float dpR = (gLMeanDpm > 0.f)
			? ((Catalog::gPower[di] * Catalog::gPower[di] / Catalog::gHealth[di])
				/ Catalog::gCostM[di]) / gLMeanDpm : 0.f;
	const float rR = (gLMeanR > 0.f) ? (Catalog::gMaxRange[di] / gLMeanR) : 0.f;
	float best = hpR;
	int cls = LC_TANK;
	if (rR > best) { best = rR; cls = LC_REACH; }
	if (dpR > best) { best = dpR; cls = LC_DPS; }
	const float edge = ai.GetTunable("apex_line_edge", TUNE_LINE_EDGE);
	return (best >= edge) ? cls : LC_MID;
}

// What we actually field, by class, as shares of army metal.
array<float> gLineM(LC_N, 0.f);
int gLineAt = 0;
void TrackLine()
{
	if (ai.frame < gLineAt)
		return;
	gLineAt = ai.frame + 5 * SECOND;
	for (int c = 0; c < LC_N; ++c)
		gLineM[c] = 0.f;
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		const int di = int(d);
		if ((gOwnCount[d] <= 0) || !LineCombat(di))
			continue;
		gLineM[LineClassOf(di)] += float(gOwnCount[d]) * Catalog::gCostM[di];
	}
}

float LineTarget(int cls)
{
	if (cls == LC_TANK)  return ai.GetTunable("apex_line_tank", TUNE_LINE_TANK);
	if (cls == LC_MID)   return ai.GetTunable("apex_line_mid", TUNE_LINE_MID);
	if (cls == LC_REACH) return ai.GetTunable("apex_line_reach", TUNE_LINE_REACH);
	return ai.GetTunable("apex_line_dps", TUNE_LINE_DPS);
}

// How far below its target a class is, 0..1. Proportional, never a veto
// (apexearth's call): a class at half its share is worth about twice as much
// per metal, a class at target is worth no extra, and one over target simply
// stops being favoured. Tanks die first, so their share falls and this pulls
// straight back to them -- which is also what stops reach units piling up.
float LineShortfall(int cls)
{
	TrackLine();
	float tot = 0.f;
	for (int c = 0; c < LC_N; ++c)
		tot += gLineM[c];
	if (tot <= 1.f)
		return 1.f;   // nothing fielded: every class is wanted
	const float share = gLineM[cls] / tot;
	const float want = LineTarget(cls);
	if (want <= 0.f)
		return 0.f;
	const float miss = (want - share) / want;
	return (miss > 0.f) ? ((miss > 1.f) ? 1.f : miss) : 0.f;
}

// ASSUME THEY BUILT THE FASTEST THING THEY COULD (apexearth: "in the early
// game enemy units will be FAST. assume they'll make the fastest units").
// The fastest ground combat unit the GAME offers is the bar, not a mean over
// what we happen to have seen -- the whole point is that the assumption has to
// hold while we are blind, which is exactly when raiders arrive. A unit slower
// than this cannot catch what is eating our mexes, whatever else it is good
// at. Air is excluded: it is a different answer to a different problem.
float gFoeSpeedCap = -1.f;
float FoeSpeedCap()
{
	// Availability is frame-dependent; a zero must never be cached (see
	// BestConvRatio).
	if (gFoeSpeedCap > 0.f)
		return gFoeSpeedCap;
	gFoeSpeedCap = 0.f;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!Catalog::gAvailable[d] || !LineCombat(d) || Catalog::gFlyer[d])
			continue;
		if (Catalog::gSpeed[d] > gFoeSpeedCap)
			gFoeSpeedCap = Catalog::gSpeed[d];
	}
	if (gFoeSpeedCap < 1.f)
		gFoeSpeedCap = 100.f;
	return gFoeSpeedCap;
}

// COVERAGE IS QUANTITY TIMES SPEED (apexearth: "security coverage requires
// quantity and speed"). One expensive unit cannot be in two places, and a
// spread base is many places. To shadow raiders across the ground we hold
// takes roughly one body as fast as they are per thing worth hitting, so the
// need is our standing sites times the speed we must match, and what we have
// is the ground speed we field. Falls to zero as the fleet fills, so it buys
// bodies while we are thin and stops on its own -- and it is a want, never a
// cap on anything bigger.
float PatrolShort()
{
	float sites = float(gLSpot.length());
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		const int di = int(d);
		if ((gOwnCount[d] <= 0) || Catalog::gMobile[di])
			continue;
		if ((Catalog::gMakeE[di] > 1.f) || (Catalog::gBuildsList[di].length() > 0))
			sites += float(gOwnCount[d]);
	}
	if (sites < 1.f)
		return 0.f;
	float have = 0.f;
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		const int di = int(d);
		if ((gOwnCount[d] <= 0) || !LineCombat(di) || Catalog::gFlyer[di])
			continue;
		have += float(gOwnCount[d]) * Catalog::gSpeed[di];
	}
	const float need = sites * FoeSpeedCap();
	if (need <= 0.f)
		return 0.f;
	const float miss = 1.f - have / need;
	return (miss > 0.f) ? ((miss > 1.f) ? 1.f : miss) : 0.f;
}

// Ground a unit can cover per metal spent, against the field's own mean.
float CoverPerMetal(int di)
{
	LineMeans();
	if ((gLMeanSpc <= 0.f) || (Catalog::gCostM[di] <= 0.f))
		return 1.f;
	return (Catalog::gSpeed[di] / Catalog::gCostM[di]) / gLMeanSpc;
}

// WHAT A PLANT'S LINE IS WORTH, against the field. A plant is bought for what
// its CONSTRUCTOR unlocks, and two plants can unlock exactly the same thing --
// a hovercraft platform's con reaches mohos just as a T2 bot lab's does -- at
// which point the cheaper one wins on price alone and we buy a line of units
// that are not tough for their metal (apexearth: "yes it has mobility but the
// units are generally not as tough for their price... I don't want to see us
// making hovers on a land only map like the one I'm on").
//
// Combat worth per metal across the plant's mobile combat products, against
// the game-wide mean of the same. No unit is named and no map type is tested:
// a line that trades badly is worth less wherever it is built, and a line that
// trades well is unaffected.
float gCpmMean = -1.f;
float CombatPerMetalMean()
{
	if (gCpmMean > 0.f)
		return gCpmMean;
	float sum = 0.f;
	int n = 0;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!Catalog::gAvailable[d] || !LineCombat(d))
			continue;
		sum += Catalog::gPower[d] / Catalog::gCostM[d];
		++n;
	}
	if (n <= 0)
		return 1.f;   // not yet knowable; do not cache
	gCpmMean = sum / float(n);
	return gCpmMean;
}

float PlantLineWorth(int d)
{
	const float ref = CombatPerMetalMean();
	if (ref <= 0.f)
		return 1.f;
	const array<int>@ prods = Catalog::gBuildsList[d];
	float sum = 0.f;
	int n = 0;
	for (uint i = 0; i < prods.length(); ++i) {
		const int pd = prods[i];
		if (!Catalog::gAvailable[pd] || !LineCombat(pd))
			continue;
		sum += Catalog::gPower[pd] / Catalog::gCostM[pd];
		++n;
	}
	if (n <= 0)
		return 1.f;   // a pure constructor plant is judged on its unlock alone
	return (sum / float(n)) / ref;
}

// Share of the line that can absorb for the rest -- what makes a fragile
// long-range unit worth its range at all.
float ShieldShare()
{
	TrackLine();
	float tot = 0.f;
	for (int c = 0; c < LC_N; ++c)
		tot += gLineM[c];
	if (tot <= 1.f)
		return 0.f;
	return (gLineM[LC_TANK] + gLineM[LC_MID]) / tot;
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
