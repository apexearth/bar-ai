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

// Where we already fired, so the director never re-nukes the same crater
// while richer ground stands -- apexearth: "us keep nuking a spot which we'd
// already nuked a bunch... we know it isn't important." Bounded ring.
array<AIFloat3> gNukedPos;
array<int>      gNukedFrame;

bool RecentlyNuked(const AIFloat3 &in p)
{
	const int keep = int(ai.GetTunable("apex_nuke_repeat_secs", 300.f)) * SECOND;
	const float sqR = 900.f * 900.f;
	for (uint i = 0; i < gNukedPos.length(); ) {
		if (ai.frame - gNukedFrame[i] > keep) {
			gNukedPos.removeAt(i);
			gNukedFrame.removeAt(i);
			continue;
		}
		if (gNukedPos[i].SqDistance2D(p) < sqR)
			return true;
		++i;
	}
	return false;
}

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

	// A volley in progress holds its orders; re-evaluate once it is spent or
	// stale (targets die, the ground gets nuked -- 90s is plenty).
	if ((ai.frame < gVolleyUntil) && (stock > 0))
		return;

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
		if (RecentlyNuked(p))
			continue;      // the crater is not a target
		const float cost = aiEnemyMgr.GetEnemyGroupCost(i);
		if (cost < minValue)
			continue;
		const int antis = AntisCovering(p);
		const float score = cost / float(1 + antis);
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
	for (uint i = 0; i < silos.length(); ++i)
		silos[i].CmdAttackGround(bestPos);
	gVolleyAt = bestPos;
	gVolleyUntil = ai.frame + 90 * SECOND;
	gNukedPos.insertLast(bestPos);
	gNukedFrame.insertLast(ai.frame);
	if (gNukedPos.length() > 32) {
		gNukedPos.removeAt(0);
		gNukedFrame.removeAt(0);
	}
	AiLog(Factory::T() + "apex: NUKE VOLLEY " + stock + " missiles ("
		+ needed + " needed) at " + int(bestPos.x) + "," + int(bestPos.z)
		+ " worth " + formatFloat(bestCost, "", 0, 0)
		+ " antis=" + bestAntis);
}

}  // namespace Brain
