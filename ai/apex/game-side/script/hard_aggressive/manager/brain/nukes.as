namespace Brain {

//------------------------------------------------------------------------------
// THE NUKE DIRECTOR. The C++ CSuperTask auto-fired each missile at the current
// best enemy cluster with no awareness of antinukes -- "in most of the games I
// watch we waste our nukes" (apexearth). With apex_brain_nuke on (default),
// the DLL cedes stockpile-super targeting to this: save a volley sized
// against the antinuke count covering the target, then spam it all at one
// location until it dies. "We don't just do static #s, we see how many
// anti-nukes the enemy has in that area and configure our attack according
// to that."
//------------------------------------------------------------------------------

array<int> gSiloIds;
int  gNukeNextEval = 0;
int  gVolleyUntil = 0;          // frames: standing orders are left alone
AIFloat3 gVolleyAt;
int  gNukeNextLog = 0;

// The blast is knowledge: 30s after a volley lands, anything the enemy model
// still REMEMBERS (unsensed) inside the blast ground is forgotten -- the
// missile either killed it or it fled. Fixes the model, not the targeting:
// apexearth rejected a fired-here ledger for exactly that reason ("should
// fix the memory to be updated"). The LOS purge (HostileInLOS) keeps doing
// the same for scouted ground.
AIFloat3 gForgetAt;
int gForgetFrame = -1;
float gForgetR = 960.f;

// EVERY REPEAT STRIKE HALVES THE GROUND'S WORTH. apexearth, after an
// (amazing) volley turned into ~100 missiles at one spot: "each send should
// diminish that value more and more." Not a cooldown -- a compounding value
// dampener per ground, so the second volley needs a target twice as rich as
// the first did, the fifth needs one 16x richer, and genuinely rebuilt
// bases can still out-bid the skepticism. Persistent for the game; bounded.
array<AIFloat3> gHitPos;
array<int>      gHitN;

int StrikesOn(const AIFloat3 &in p)
{
	for (uint i = 0; i < gHitPos.length(); ++i) {
		if (gHitPos[i].SqDistance2D(p) < 900.f * 900.f)
			return gHitN[i];
	}
	return 0;
}

void NoteStrikeOn(const AIFloat3 &in p)
{
	for (uint i = 0; i < gHitPos.length(); ++i) {
		if (gHitPos[i].SqDistance2D(p) < 900.f * 900.f) {
			++gHitN[i];
			return;
		}
	}
	gHitPos.insertLast(p);
	gHitN.insertLast(1);
	if (gHitPos.length() > 32) {
		gHitPos.removeAt(0);
		gHitN.removeAt(0);
	}
}

// The volley's aim points: a line through the target, perpendicular to our
// approach, stepped at apex_nuke_spread so the blasts tile the base instead
// of stacking in one crater. Silos rotate across it between launches.
array<AIFloat3> gVolleySpots;
uint gVolleyTick = 0;
int gVolleyStock0 = 0;   // pooled stock when the volley launched
int gVolleyNeed = 0;     // missiles this volley is sized to spend

bool IsSiloDef(const CCircuitDef@ d)
{
	if (d is null)
		return false;
	CCircuitDef@ silo = SideDef3("armsilo", "corsilo", "legsilo");
	return (silo !is null) && (d.id == silo.id);
}

void NoteSiloFinished(CCircuitUnit@ unit)
{
	if ((unit !is null) && IsSiloDef(unit.circuitDef))
		gSiloIds.insertLast(int(unit.id));
}

// Antinukes covering pos, all three factions' defs. 2500 is the interceptor
// coverage radius in this game tree, close enough for "is this spot shielded".
int AntisCovering(const AIFloat3 &in pos)
{
	const float r = ai.GetTunable("apex_anti_cover", 2500.f);
	int n = 0;
	CCircuitDef@ a = ai.GetCircuitDef("armamd");
	CCircuitDef@ c = ai.GetCircuitDef("corfmd");
	CCircuitDef@ l = ai.GetCircuitDef("legabm");
	if (a !is null) n += ai.CountEnemyDefNear(a.id, pos, r);
	if (c !is null) n += ai.CountEnemyDefNear(c.id, pos, r);
	if (l !is null) n += ai.CountEnemyDefNear(l.id, pos, r);
	return n;
}

void UpdateNukes()
{
	if (ai.GetTunable("apex_brain_nuke", 1.f) <= 0.f)
		return;
	if ((gSiloIds.length() == 0) || (ai.frame < gNukeNextEval))
		return;
	gNukeNextEval = ai.frame + 5 * SECOND;

	// Live silos and the pooled stockpile.
	array<CCircuitUnit@> silos;
	int stock = 0;
	for (uint i = 0; i < gSiloIds.length(); ) {
		CCircuitUnit@ u = ai.GetTeamUnit(Id(gSiloIds[i]));
		if (u is null) {
			gSiloIds.removeAt(i);
			continue;
		}
		silos.insertLast(u);
		stock += u.GetStockpile();
		++i;
	}
	if (silos.length() == 0)
		return;

	// The scheduled post-impact forget, volley in progress or not.
	if ((gForgetFrame >= 0) && (ai.frame >= gForgetFrame)) {
		gForgetFrame = -1;
		const int n = ai.ForgetEnemiesNear(gForgetAt, gForgetR);
		AiLog(Factory::T() + "apex: nuke ground confirmed -- forgot "
			+ n + " remembered enemies at the impact");
	}

	// A volley in progress WALKS its aim across the spread line each tick: a
	// silo's standing order sends every missile to one point, so scatter has
	// to come from re-aiming between launches -- apexearth: "if we're
	// launching 5 give them a little bit of area or line/curve so they don't
	// land all in exactly the same spot."
	if ((ai.frame < gVolleyUntil) && (stock > 0)) {
		// THE VOLLEY SPENDS ITS SIZE, NOT THE WHOLE POOL: a 20-deep stockpile
		// against a 1-missile target drained entirely into one window
		// (apexearth: "we sent like 20 nukes there"). Fired = stock delta;
		// at the sized count every silo stands down and the rest keeps
		// saving for the next target.
		if (gVolleyStock0 - stock >= gVolleyNeed) {
			for (uint i = 0; i < silos.length(); ++i)
				silos[i].CmdStop();
			gVolleyUntil = ai.frame;
			AiLog(Factory::T() + "apex: volley complete -- " + (gVolleyStock0 - stock)
				+ " fired, " + stock + " saved");
			return;
		}
		if (gVolleySpots.length() > 1) {
			for (uint i = 0; i < silos.length(); ++i) {
				const uint s = (i + gVolleyTick) % gVolleySpots.length();
				silos[i].CmdAttackGround(gVolleySpots[s]);
			}
			++gVolleyTick;
		}
		return;
	}

	// Pick the target: richest enemy cluster per antinuke covering it. The
	// forward gate keeps this off our own ground -- home defense is the
	// army's job, not a warhead's.
	const int nGroups = aiEnemyMgr.GetEnemyGroupCount();
	float bestScore = 0.f;
	AIFloat3 bestPos;
	int bestAntis = 0;
	float bestCost = 0.f;
	// 10k floor (apexearth: "filter the metal to target areas of 10k metal
	// or more if possible") -- with no qualifying target the missiles KEEP
	// SAVING, which is the point; the stockpile only grows.
	const float minValue = ai.GetTunable("apex_nuke_min_value", 10000.f);
	for (int i = 0; i < nGroups; ++i) {
		const AIFloat3 p = aiEnemyMgr.GetEnemyGroupPos(i);
		if (!OnMap(p) || (Military::ForwardFraction(p) < 0.35f))
			continue;
		const float cost = aiEnemyMgr.GetEnemyGroupCost(i);
		if (cost < minValue)
			continue;
		const int antis = AntisCovering(p);
		float score = cost / float(1 + antis);
		// The repeat-strike dampener: halved per prior volley on this ground.
		const float decay = ai.GetTunable("apex_nuke_repeat_decay", 0.5f);
		int hits = StrikesOn(p);
		if (hits > 6)
			hits = 6;
		for (int h = 0; h < hits; ++h)
			score *= decay;
		if (score > bestScore) {
			bestScore = score;
			bestPos = p;
			bestAntis = antis;
			bestCost = cost;
		}
	}
	if (bestScore <= 0.f) {
		if (ai.frame >= gNukeNextLog) {
			gNukeNextLog = ai.frame + 60 * SECOND;
			AiLog(Factory::T() + "apex: nukes saving, no target worth a warhead"
				+ " (stock " + stock + ")");
		}
		return;
	}

	// Volley size scales with the shield, not a flat number: an undefended
	// base eats the first missile; each antinuke costs apex_nuke_per_anti
	// extra missiles to saturate. Fire only when the pool covers it.
	const int needed = 1 + bestAntis * int(ai.GetTunable("apex_nuke_per_anti", 8.f));
	if (stock < needed) {
		if (ai.frame >= gNukeNextLog) {
			gNukeNextLog = ai.frame + 60 * SECOND;
			AiLog(Factory::T() + "apex: nukes saving " + stock + "/" + needed
				+ " for a target worth " + formatFloat(bestCost, "", 0, 0)
				+ " behind " + bestAntis + " antinukes");
		}
		return;
	}

	// THE VOLLEY: every silo, one location, until it is gone. A standing
	// attack-ground order drains the whole stockpile as fast as launches
	// reload; the 90s window then lets the next evaluation retarget.
	// Aim points: center first (the scored cluster), then steps outward along
	// the line perpendicular to silo->target, sized to how many missiles are
	// flying. Every point is clamped on-map.
	gVolleySpots.resize(0);
	gVolleyTick = 0;
	gVolleySpots.insertLast(bestPos);
	{
		AIFloat3 dir = bestPos - silos[0].GetPos(ai.frame);
		if (dir.SqLength2D() > 1.f) {
			dir.SafeNormalize2D();
			const AIFloat3 perp(-dir.z, 0.f, dir.x);
			const float step = ai.GetTunable("apex_nuke_spread", 450.f);
			const int arms = (stock >= 5) ? 2 : 1;
			for (int a = 1; a <= arms; ++a) {
				AIFloat3 p1 = bestPos + perp * (step * float(a));
				AIFloat3 p2 = bestPos - perp * (step * float(a));
				if (OnMap(p1)) gVolleySpots.insertLast(p1);
				if (OnMap(p2)) gVolleySpots.insertLast(p2);
			}
		}
	}
	for (uint i = 0; i < silos.length(); ++i)
		silos[i].CmdAttackGround(gVolleySpots[i % gVolleySpots.length()]);
	gVolleyAt = bestPos;
	gVolleyUntil = ai.frame + 90 * SECOND;
	gVolleyStock0 = stock;
	gVolleyNeed = needed;
	NoteStrikeOn(bestPos);
	// COMMITTING THE VOLLEY SPENDS THE INTEL. Everything remembered in the
	// whole target area is marked unseen NOW, not 30s later: the missiles are
	// paid for, and until a scout or radar actually sights enemies there
	// again (which un-hides them through the engine's own LOS events) the
	// ground cannot re-qualify -- apexearth, after 20 nukes on one spot:
	// "diminish the urge to send nukes to the same place until we sight
	// enemies there again." Lag-proof by construction: no timer, only
	// sighting revives a target.
	const int spent = ai.ForgetEnemiesNear(bestPos,
			ai.GetTunable("apex_nuke_resight_r", 1600.f));
	AiLog(Factory::T() + "apex: nuke intel spent -- " + spent
		+ " remembered enemies need re-sighting before this ground qualifies again");
	gForgetAt = bestPos;
	gForgetFrame = ai.frame + 30 * SECOND;   // stragglers seen mid-flight
	// The forget covers the whole spread line, not just the center blast.
	gForgetR = 960.f + ai.GetTunable("apex_nuke_spread", 450.f)
			* float(gVolleySpots.length() / 2);
	AiLog(Factory::T() + "apex: NUKE VOLLEY " + stock + " missiles ("
		+ needed + " needed) at " + int(bestPos.x) + "," + int(bestPos.z)
		+ " worth " + formatFloat(bestCost, "", 0, 0)
		+ " antis=" + bestAntis);
}

}  // namespace Brain
