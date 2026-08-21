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
int  gNukeNextLog = 0;

// The blast is knowledge: 30s after a volley lands, anything the enemy model
// still REMEMBERS (unsensed) inside the blast ground is forgotten -- the
// missile either killed it or it fled. Fixes the model, not the targeting:
// apexearth rejected a fired-here ledger for exactly that reason ("should
// fix the memory to be updated"). The LOS purge (HostileInLOS) keeps doing
// the same for scouted ground.

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
// SEVERAL LAUNCHES AT ONCE. apexearth 2026-08-21: "Make sure the AI can
// logistic several separate nuke launches simultaneously. If it can only
// ever think 'I'll nuke here' and then that's the only place that gets it
// -- that is bad." Each volley OWNS the silos assigned to it: targets are
// ranked and funded in priority order, a volley spends only its own size,
// tracks and aborts on its own, and a silo that frees up mid-window can
// immediately fund the next target instead of idling behind one thought.
class Volley {
	array<AIFloat3> spots;
	array<int> siloIds;   // exclusive: a silo serves one volley at a time
	AIFloat3 at;
	int until = 0;
	bool def = false;
	int need = 0;
	int stock0 = 0;       // summed stockpile of the assigned silos at launch
	uint tick = 0;
}
array<Volley@> gVolleys;

// Post-impact forgets, one entry per launched volley (stragglers seen
// mid-flight get forgotten 30s after launch, volley finished or not).
array<AIFloat3> gForgetAtQ;
array<int> gForgetFrameQ;
array<float> gForgetRQ;

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
	const float r = ai.GetTunable("apex_anti_cover", TUNE_ANTI_COVER);
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

bool VolleyServes(const AIFloat3 &in p)
{
	const float r = ai.GetTunable("apex_nuke_resight_r", TUNE_NUKE_RESIGHT_R);
	for (uint v = 0; v < gVolleys.length(); ++v) {
		if (gVolleys[v].at.distance2D(p) <= r)
			return true;
	}
	return false;
}

void UpdateNukes()
{
	if (ai.GetTunable("apex_brain_nuke", TUNE_BRAIN_NUKE) <= 0.f)
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

	// The scheduled post-impact forgets, volleys in progress or not.
	for (uint i = 0; i < gForgetFrameQ.length(); ) {
		if (ai.frame < gForgetFrameQ[i]) {
			++i;
			continue;
		}
		const int n = ai.ForgetEnemiesNear(gForgetAtQ[i], gForgetRQ[i]);
		AiLog(Factory::T() + "apex: nuke ground confirmed -- forgot "
			+ n + " remembered enemies at the impact");
		gForgetAtQ.removeAt(i);
		gForgetFrameQ.removeAt(i);
		gForgetRQ.removeAt(i);
	}

	// Each volley in progress WALKS its aim across its spread line each tick:
	// a silo's standing order sends every missile to one point, so scatter has
	// to come from re-aiming between launches -- apexearth: "if we're
	// launching 5 give them a little bit of area or line/curve so they don't
	// land all in exactly the same spot."
	for (uint v = 0; v < gVolleys.length(); ) {
		Volley@ vol = gVolleys[v];
		// Resolve this volley's silos; drop the dead.
		array<CCircuitUnit@> mine;
		int vStock = 0;
		for (uint i = 0; i < vol.siloIds.length(); ) {
			CCircuitUnit@ u = ai.GetTeamUnit(Id(vol.siloIds[i]));
			if (u is null) {
				vol.siloIds.removeAt(i);
				continue;
			}
			mine.insertLast(u);
			vStock += u.GetStockpile();
			++i;
		}
		bool done = (ai.frame >= vol.until) || (mine.length() == 0);
		// A DEFENSIVE VOLLEY TRACKS ITS ARMY, and is called off if our own
		// army has since closed to the ground -- missiles already flying are
		// spent, but no more follow into our line.
		if (!done && vol.def) {
			if (ai.GetNetInflAt(vol.at) >= ai.GetTunable("apex_nuke_ally_max", TUNE_NUKE_ALLY_MAX)) {
				for (uint i = 0; i < mine.length(); ++i)
					mine[i].CmdStop();
				AiLog(Factory::T() + "apex: defensive volley aborted -- our army holds the target ground");
				done = true;
			} else {
				const int nG = aiEnemyMgr.GetEnemyGroupCount();
				float bestD = 1500.f * 1500.f;
				AIFloat3 now = vol.at;
				bool found = false;
				for (int i = 0; i < nG; ++i) {
					const AIFloat3 gp = aiEnemyMgr.GetEnemyGroupPos(i);
					if (!OnMap(gp))
						continue;
					const float d = gp.SqDistance2D(vol.at);
					if (d < bestD) {
						bestD = d;
						now = gp;
						found = true;
					}
				}
				if (found && (now.SqDistance2D(vol.at) > 100.f * 100.f)) {
					const AIFloat3 delta = now - vol.at;
					for (uint i = 0; i < vol.spots.length(); ++i) {
						AIFloat3 moved = vol.spots[i] + delta;
						if (OnMap(moved))
							vol.spots[i] = moved;
					}
					vol.at = now;
				}
			}
		}
		// THE VOLLEY SPENDS ITS SIZE, NOT ITS SILOS' WHOLE STOCK: fired =
		// this volley's own stock delta; at the sized count its silos stand
		// down and go back in the pool for the next target.
		if (!done && (vol.stock0 - vStock >= vol.need)) {
			for (uint i = 0; i < mine.length(); ++i)
				mine[i].CmdStop();
			AiLog(Factory::T() + "apex: volley complete -- " + (vol.stock0 - vStock)
				+ " fired, " + vStock + " left in its silos");
			done = true;
		}
		if (done) {
			gVolleys.removeAt(v);
			continue;
		}
		// Defensive volleys re-issue even a single spot: the tracking shift
		// only lands if the standing order is refreshed.
		if ((vol.spots.length() > 1) || (vol.def && vol.spots.length() > 0)) {
			for (uint i = 0; i < mine.length(); ++i) {
				const uint sp = (i + vol.tick) % vol.spots.length();
				mine[i].CmdAttackGround(vol.spots[sp]);
			}
			++vol.tick;
		}
		++v;
	}

	// Silos not serving a volley are free to fund the next target.
	array<CCircuitUnit@> freeSilos;
	int freeStock = 0;
	for (uint i = 0; i < silos.length(); ++i) {
		bool busy = false;
		for (uint v = 0; v < gVolleys.length() && !busy; ++v) {
			if (gVolleys[v].siloIds.find(int(silos[i].id)) >= 0)
				busy = true;
		}
		if (!busy) {
			freeSilos.insertLast(silos[i]);
			freeStock += silos[i].GetStockpile();
		}
	}
	if (freeSilos.length() == 0)
		return;
	silos = freeSilos;
	stock = freeStock;

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
	const float minValue = ai.GetTunable("apex_nuke_min_value", TUNE_NUKE_MIN_VALUE);
	// A defensive strike pays once the army is worth several missiles.
	const float missileM = ai.GetTunable("apex_nuke_missile_cost", TUNE_NUKE_MISSILE_COST);
	const float defMin = missileM * ai.GetTunable("apex_nuke_payoff", TUNE_NUKE_PAYOFF);
	const float allyMax = ai.GetTunable("apex_nuke_ally_max", TUNE_NUKE_ALLY_MAX);
	for (int i = 0; i < nGroups; ++i) {
		const AIFloat3 p = aiEnemyMgr.GetEnemyGroupPos(i);
		if (!OnMap(p))
			continue;
		if (VolleyServes(p))
			continue;   // a volley already owns this ground
		const float fwd = Military::ForwardFraction(p);
		const bool defensive = (fwd < 0.35f);
		if (defensive && (fwd < ai.GetTunable("apex_nuke_def_minfwd", TUNE_NUKE_DEF_MINFWD)))
			continue;
		const float cost = aiEnemyMgr.GetEnemyGroupCost(i);
		if (cost < (defensive ? defMin : minValue))
			continue;
		// WHO OWNS THIS GROUND, not "is any of ours near". GetAllyInflAt is
		// positive across our whole territory, so an absolute bar of 0 vetoed
		// every army attacking us -- exactly the case worth nuking. The net
		// crossing (ally minus enemy, the same question BaseContested asks) says
		// the enemy holds it: our units are not standing there, theirs are.
		// ...except an army big enough to end the game: apexearth 2026-08-21,
		// watching catapults close on the base while six warheads hit mex
		// fields: "We nuke the other side of the map instead of the army that
		// is about to kill us." Past this worth, losing some of our own units
		// to the blast beats losing the base.
		if (defensive && (ai.GetNetInflAt(p) >= allyMax)
			&& (cost < ai.GetTunable("apex_nuke_emergency", TUNE_NUKE_EMERGENCY)))
		{
			continue;
		}
		// UNSEEN IS NOT ZERO. AntisCovering counts antinukes we have SIGHTED, and
		// their base is the ground we scout least, so a shielded base read as bare
		// and got a single missile. Past apex_nuke_assume_from minutes a base is
		// assumed covered (apexearth's number: by then any enemy has had time to
		// build one), so a base strike saves for a salvo instead.
		//
		// NOT YET the second half of the rule -- "believe otherwise once you have
		// scouted and seen the lack thereof". Nothing here can say whether we ever
		// LOOKED at that ground; the C++ wrapper exposes no LOS query. Until it
		// does, an unscouted base and a scouted-empty one read the same.
		//
		// Field targets keep the sighted count: an army in the open is usually
		// outside any interceptor's radius.
		int antis = AntisCovering(p);
		const int assumeFrom = int(ai.GetTunable("apex_nuke_assume_from", TUNE_NUKE_ASSUME_FROM)
				* 60.f) * SECOND;
		if (!defensive && (ai.frame >= assumeFrom)) {
			const int assume = int(ai.GetTunable("apex_nuke_assume_antis", TUNE_NUKE_ASSUME_ANTIS));
			if (antis < assume)
				antis = assume;
		}
		float score = cost / float(1 + antis);
		if (defensive) {
			score *= ai.GetTunable("apex_nuke_def_bias", TUNE_NUKE_DEF_BIAS);
		} else {
			// The repeat-strike dampener: halved per prior volley on this
			// ground. Base ground only -- each attacking wave through the same
			// lane is a new army, and the intel-spend already stops re-fires
			// until the ground is re-sighted.
			const float decay = ai.GetTunable("apex_nuke_repeat_decay", TUNE_NUKE_REPEAT_DECAY);
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
	// THE MIRRORED BASE, always a candidate. Group targeting is LOS-slaved
	// (hostileDatas keeps only units currently in LOS), so the enemy MAIN BASE
	// -- the ground we scout least -- can never win the ranking, and every
	// warhead chases whatever mex field our raiders happen to be looking at.
	// Measured live 2026-08-21: 6+ nukes at 14k field clusters, none at a
	// main base with no antinuke. In a boxed game the enemy production base
	// sits at our own start mirrored across the map; it enters the ranking at
	// a standing value and the same assume/decay rules as any base ground.
	{
		AIFloat3 mirror(AiTerrainWidth() - Builder::gHomePos.x, 0.f,
				AiTerrainHeight() - Builder::gHomePos.z);
		if (OnMap(mirror) && !VolleyServes(mirror)) {
			const float cost = ai.GetTunable("apex_nuke_base_value", TUNE_NUKE_BASE_VALUE);
			int antis = AntisCovering(mirror);
			const int assumeFrom2 = int(ai.GetTunable("apex_nuke_assume_from", TUNE_NUKE_ASSUME_FROM)
					* 60.f) * SECOND;
			if (ai.frame >= assumeFrom2) {
				const int assume = int(ai.GetTunable("apex_nuke_assume_antis", TUNE_NUKE_ASSUME_ANTIS));
				if (antis < assume)
					antis = assume;
			}
			float score = cost / float(1 + antis);
			const float decay = ai.GetTunable("apex_nuke_repeat_decay", TUNE_NUKE_REPEAT_DECAY);
			int hits = StrikesOn(mirror);
			if (hits > 6)
				hits = 6;
			for (int h = 0; h < hits; ++h)
				score *= decay;
			if (score > bestScore) {
				bestScore = score;
				bestPos = mirror;
				bestAntis = antis;
				bestCost = cost;
				bestDef = false;
			}
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
	// Sized against SIGHTED interceptors only. The assumed anti keeps shaping
	// the RANKING above, but a salvo bar of 1+8 against an anti nobody has
	// ever seen held 7 missiles in their silos for 17 minutes while catapults
	// closed (his game, 2026-08-21). If an unseen anti eats part of a lean
	// volley, the re-sight rules price the ground correctly next time.
	int needed = 1 + AntisCovering(bestPos)
			* int(ai.GetTunable("apex_nuke_per_anti", TUNE_NUKE_PER_ANTI));
	if (bestDef) {
		int extra = int(bestCost / ai.GetTunable("apex_nuke_value_per", TUNE_NUKE_VALUE_PER));
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

	// THE VOLLEY: a subset of the free silos, one location, sized to the
	// target. Silos join until their pooled stockpile covers the need; the
	// rest stay free, so a second target can be funded on the next tick --
	// several separate launches in flight at once.
	Volley vol;
	vol.at = bestPos;
	vol.def = bestDef;
	vol.need = needed;
	vol.until = ai.frame + (bestDef
		? int(ai.GetTunable("apex_nuke_def_window", TUNE_NUKE_DEF_WINDOW)) * SECOND
		: 90 * SECOND);
	int assigned = 0;
	for (uint i = 0; (i < silos.length()) && (assigned < needed); ++i) {
		vol.siloIds.insertLast(int(silos[i].id));
		assigned += silos[i].GetStockpile();
	}
	vol.stock0 = assigned;
	vol.spots.insertLast(bestPos);
	{
		AIFloat3 dir = bestPos - silos[0].GetPos(ai.frame);
		if (dir.SqLength2D() > 1.f) {
			dir.SafeNormalize2D();
			const AIFloat3 perp(-dir.z, 0.f, dir.x);
			const float step = ai.GetTunable("apex_nuke_spread", TUNE_NUKE_SPREAD);
			const int arms = (assigned >= 5) ? 2 : 1;
			for (int a = 1; a <= arms; ++a) {
				AIFloat3 p1 = bestPos + perp * (step * float(a));
				AIFloat3 p2 = bestPos - perp * (step * float(a));
				if (OnMap(p1)) vol.spots.insertLast(p1);
				if (OnMap(p2)) vol.spots.insertLast(p2);
			}
		}
	}
	for (uint i = 0; i < vol.siloIds.length(); ++i) {
		CCircuitUnit@ u = ai.GetTeamUnit(Id(vol.siloIds[i]));
		if (u !is null)
			u.CmdAttackGround(vol.spots[i % vol.spots.length()]);
	}
	gVolleys.insertLast(vol);
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
			ai.GetTunable("apex_nuke_resight_r", TUNE_NUKE_RESIGHT_R));
	AiLog(Factory::T() + "apex: nuke intel spent -- " + spent
		+ " remembered enemies need re-sighting before this ground qualifies again");
	gForgetAtQ.insertLast(bestPos);
	gForgetFrameQ.insertLast(ai.frame + 30 * SECOND);   // stragglers seen mid-flight
	// The forget covers the whole spread line, not just the center blast.
	gForgetRQ.insertLast(960.f + ai.GetTunable("apex_nuke_spread", TUNE_NUKE_SPREAD)
			* float(vol.spots.length() / 2));
	AiLog(Factory::T() + "apex: NUKE VOLLEY " + assigned + " missiles in "
		+ vol.siloIds.length() + " silo(s) (" + needed + " needed, "
		+ gVolleys.length() + " volleys live) at "
		+ int(bestPos.x) + "," + int(bestPos.z)
		+ " worth " + formatFloat(bestCost, "", 0, 0)
		+ " antis=" + bestAntis + (bestDef ? " DEFENSIVE" : ""));
}

}  // namespace Brain
