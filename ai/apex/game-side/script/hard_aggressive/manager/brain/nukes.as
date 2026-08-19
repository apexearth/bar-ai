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
bool gVolleyDef = false; // defensive strike: the target is an army, and it moves

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

// ENEMY NUKE LAUNCHERS WE HAVE SEEN, whole map, cached. The antinuke want
// matches this count (apexearth 2026-08-19: "match needs based on how many
// nuke launchers the enemy has. Always assume 1 is needed") -- a hidden silo
// is covered by the floor of one, a second seen silo asks for a second anti.
int gFoeSiloN = 0;
int gFoeSiloNext = 0;

int EnemyNukeSilos()
{
	if (ai.frame < gFoeSiloNext)
		return gFoeSiloN;
	gFoeSiloNext = ai.frame + 10 * SECOND;
	const float w = float(AiTerrainWidth());
	const float h = float(AiTerrainHeight());
	AIFloat3 mid(w * 0.5f, 0.f, h * 0.5f);
	const float r = sqrt(w * w + h * h) * 0.5f + 1.f;
	int n = 0;
	CCircuitDef@ a = ai.GetCircuitDef("armsilo");
	CCircuitDef@ c = ai.GetCircuitDef("corsilo");
	CCircuitDef@ l = ai.GetCircuitDef("legsilo");
	if (a !is null) n += ai.CountEnemyDefNear(a.id, mid, r);
	if (c !is null) n += ai.CountEnemyDefNear(c.id, mid, r);
	if (l !is null) n += ai.CountEnemyDefNear(l.id, mid, r);
	gFoeSiloN = n;
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
		// A DEFENSIVE VOLLEY TRACKS ITS ARMY. The aim points were laid where the
		// group stood at launch; an attacking army keeps walking, so each tick
		// the whole spread shifts to the group's current position. If our own
		// army has since closed to that ground, the strike is called off --
		// missiles already flying are spent, but no more follow into our line.
		if (gVolleyDef) {
			if (ai.GetAllyInflAt(gVolleyAt) > ai.GetTunable("apex_nuke_ally_max", 0.f)) {
				for (uint i = 0; i < silos.length(); ++i)
					silos[i].CmdStop();
				gVolleyUntil = ai.frame;
				AiLog(Factory::T() + "apex: defensive volley aborted -- our army holds the target ground");
				return;
			}
			const int nG = aiEnemyMgr.GetEnemyGroupCount();
			float bestD = 1500.f * 1500.f;
			AIFloat3 now = gVolleyAt;
			bool found = false;
			for (int i = 0; i < nG; ++i) {
				const AIFloat3 gp = aiEnemyMgr.GetEnemyGroupPos(i);
				if (!OnMap(gp))
					continue;
				const float d = gp.SqDistance2D(gVolleyAt);
				if (d < bestD) {
					bestD = d;
					now = gp;
					found = true;
				}
			}
			if (found && (now.SqDistance2D(gVolleyAt) > 100.f * 100.f)) {
				const AIFloat3 delta = now - gVolleyAt;
				for (uint i = 0; i < gVolleySpots.length(); ++i) {
					AIFloat3 moved = gVolleySpots[i] + delta;
					if (OnMap(moved))
						gVolleySpots[i] = moved;
				}
				gVolleyAt = now;
			}
		}
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
		// Defensive volleys re-issue even a single spot: the shift above only
		// lands if the standing order is refreshed.
		if ((gVolleySpots.length() > 1) || (gVolleyDef && gVolleySpots.length() > 0)) {
			for (uint i = 0; i < silos.length(); ++i) {
				const uint s = (i + gVolleyTick) % gVolleySpots.length();
				silos[i].CmdAttackGround(gVolleySpots[s]);
			}
			++gVolleyTick;
		}
		return;
	}

	// Pick the target: richest enemy cluster per antinuke covering it. Two
	// classes of target, one ranking:
	//  - BASE targets, deep on their ground (fwd >= 0.35): the original case.
	//  - DEFENSIVE targets, an army on OUR side of the midfield (apexearth
	//    2026-08-19: "prioritize nuking armies which are attacking us"). These
	//    outrank base targets by apex_nuke_def_bias, qualify at a lower value
	//    floor (a few missiles' worth, since the alternative is that army
	//    reaching our base), and are refused wherever our own army already
	//    stands -- a warhead must never land on our own fight. The
	//    apex_nuke_def_minfwd floor keeps it off the base itself: inside that
	//    the blast costs us more than the army does.
	const int nGroups = aiEnemyMgr.GetEnemyGroupCount();
	float bestScore = 0.f;
	AIFloat3 bestPos;
	int bestAntis = 0;
	float bestCost = 0.f;
	bool bestDef = false;
	// 10k floor (apexearth: "filter the metal to target areas of 10k metal
	// or more if possible") -- with no qualifying target the missiles KEEP
	// SAVING, which is the point; the stockpile only grows.
	const float minValue = ai.GetTunable("apex_nuke_min_value", 10000.f);
	// A defensive strike pays once the army is worth several missiles.
	const float missileM = ai.GetTunable("apex_nuke_missile_cost", 1500.f);
	const float defMin = missileM * ai.GetTunable("apex_nuke_payoff", 3.f);
	const float allyMax = ai.GetTunable("apex_nuke_ally_max", 0.f);
	for (int i = 0; i < nGroups; ++i) {
		const AIFloat3 p = aiEnemyMgr.GetEnemyGroupPos(i);
		if (!OnMap(p))
			continue;
		const float fwd = Military::ForwardFraction(p);
		const bool defensive = (fwd < 0.35f);
		if (defensive && (fwd < ai.GetTunable("apex_nuke_def_minfwd", 0.12f)))
			continue;
		const float cost = aiEnemyMgr.GetEnemyGroupCost(i);
		if (cost < (defensive ? defMin : minValue))
			continue;
		if (defensive && (ai.GetAllyInflAt(p) > allyMax))
			continue;
		const int antis = AntisCovering(p);
		float score = cost / float(1 + antis);
		if (defensive) {
			score *= ai.GetTunable("apex_nuke_def_bias", 2.f);
		} else {
			// The repeat-strike dampener: halved per prior volley on this
			// ground. Base ground only -- each attacking wave through the same
			// lane is a new army, and the intel-spend already stops re-fires
			// until the ground is re-sighted.
			const float decay = ai.GetTunable("apex_nuke_repeat_decay", 0.5f);
			int hits = StrikesOn(p);
			if (hits > 6)
				hits = 6;
			for (int h = 0; h < hits; ++h)
				score *= decay;
		}
		if (score > bestScore) {
			bestScore = score;
			bestPos = p;
			bestAntis = antis;
			bestCost = cost;
			bestDef = defensive;
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
	// A defensive volley is additionally sized to the ARMY's worth: one blast
	// covers a clump, and each further missile pays only if there is another
	// apex_nuke_value_per of army spread beyond it -- "an optimum # of nukes",
	// derived from value per missile rather than a flat count.
	int needed = 1 + bestAntis * int(ai.GetTunable("apex_nuke_per_anti", 8.f));
	if (bestDef) {
		int extra = int(bestCost / ai.GetTunable("apex_nuke_value_per", 12000.f));
		if (extra > 3)
			extra = 3;
		needed += extra;
	}
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
	// A defensive window is short: the army either dies to the volley or walks
	// out of the picture, and the next evaluation should be free to re-decide.
	gVolleyUntil = ai.frame + (bestDef
		? int(ai.GetTunable("apex_nuke_def_window", 25.f)) * SECOND
		: 90 * SECOND);
	gVolleyStock0 = stock;
	gVolleyNeed = needed;
	gVolleyDef = bestDef;
	// The permanent repeat dampener is for ground that gets rebuilt; each
	// attacking wave through the same lane is a new army and must stay
	// targetable, so defensive strikes leave no mark on it.
	if (!bestDef)
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
		+ " antis=" + bestAntis + (bestDef ? " DEFENSIVE" : ""));
}

}  // namespace Brain
