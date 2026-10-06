namespace Market {
// The best extraction any AVAILABLE def in the game reaches -- the ceiling
// upgrade demand is measured against.
float gBestExtract = -1.f;
float BestExtract()
{
	// NEVER CACHE A ZERO: Catalog::gAvailable is frame-dependent, so a first
	// call before extractors unlock would latch 0 forever -- and UpDemand, and
	// with it the entire tech want, would read 0 for the rest of the game.
	if (gBestExtract > 0.f)
		return gBestExtract;
	gBestExtract = 0.f;
	int bestDef = -1;
	// OUR TREE: everything reachable through build lists from what we own (the
	// commander at the start). The ceiling was read off every def in the game,
	// and in his lobby that is a scav Legion moho (0.023) or a tweaked
	// underwater one (0.0126) no con of ours builds: every T2 con read ceil=0,
	// the t2-con floor never fired and no Butler was an assist unit.
	array<bool> tree(uint(Catalog::gDefCount + 1), false);
	array<int> open;
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		if (gOwnCount[d] > 0) {
			tree[d] = true;
			open.insertLast(int(d));
		}
	}
	while (open.length() > 0) {
		const int cur = open[open.length() - 1];
		open.removeLast();
		const array<int>@ bl = Catalog::gBuildsList[cur];
		for (uint q = 0; q < bl.length(); ++q) {
			if (!tree[bl[q]]) {
				tree[bl[q]] = true;
				open.insertLast(bl[q]);
			}
		}
	}
	for (int i = 1; i <= Catalog::gDefCount; ++i) {
		if (!Catalog::gAvailable[i] || !tree[i] || (Catalog::gExtractsM[i] <= gBestExtract))
			continue;
		// ...and a LAND extractor: one a non-naval con of ours builds.
		const array<int>@ by = Catalog::gBuiltBy[i];
		bool land = false;
		for (uint b = 0; (b < by.length()) && !land; ++b) {
			const int bd = by[b];
			land = tree[bd] && Catalog::gAvailable[bd] && Catalog::gMobile[bd]
				&& Catalog::gBuilder[bd] && !Catalog::gFloater[bd] && !Catalog::gSub[bd]
				&& !Catalog::Def(bd).IsRoleAny(Unit::Role::COMM.mask);
		}
		if (!land)
			continue;
		gBestExtract = Catalog::gExtractsM[i];
		bestDef = i;
	}
	if (bestDef > 0) {
		string who = "";
		const array<int>@ by = Catalog::gBuiltBy[bestDef];
		for (uint b = 0; b < by.length(); ++b) {
			const int bd = by[b];
			who += " " + Catalog::Def(bd).GetName() + "(a" + (Catalog::gAvailable[bd] ? 1 : 0)
				+ "m" + (Catalog::gMobile[bd] ? 1 : 0) + "f" + (Catalog::gFloater[bd] ? 1 : 0)
				+ "s" + (Catalog::gSub[bd] ? 1 : 0)
				+ "c" + (Catalog::Def(bd).IsRoleAny(Unit::Role::COMM.mask) ? 1 : 0) + ")";
		}
		AiLog("apex: best-extract " + Catalog::Def(bestDef).GetName()
			+ " m=" + formatFloat(gBestExtract, "", 0, 4) + " by" + who);
	}
	return gBestExtract;
}

// Metal/s still extractable from ground we already hold, if every standing
// mex were upgraded to the game's best extractor. The tech want's fuel.
float UpDemand()
{
	const float ceil = BestExtract();
	float d = 0.f;
	for (uint i = 0; i < gLSpot.length(); ++i) {
		if (gLExtract[i] > 0.f)
			d += gLIncome[i] * IncomeMult() * (ceil - gLExtract[i]);
	}
	return (d > 0.f) ? d : 0.f;
}

// HANDS FOR THE UPGRADES (apexearth 2026-09-30: "we got to 500 really fast and
// then to get to 800 took a really long time" -- one T2 con per seat went round
// the extractors). Only a ceiling hand upgrades. With h hands a backlog of B
// upgrades of t seconds each lands on average B*t/(2h) from now, so hand h+1
// brings the waiting stream U forward by B*t*U/(2h(h+1)) metal: it is worth its
// cost C while h(h+1) < B*t*U/(2C).
int gUpHandsAt = -1000;
int gNextUpHandsLog = 0;
int gUpHandsN = 0;
int gUpHandsB = 0;
float gUpHandsT = 0.f;
int UpgradeHandsWant()
{
	if (ai.frame - gUpHandsAt < 5 * SECOND)
		return gUpHandsN;
	gUpHandsAt = ai.frame;
	gUpHandsN = 0;
	gUpHandsB = 0;
	const float ceil = BestExtract();
	if (ceil <= 0.f)
		return 0;
	int con = -1;
	float conPerBp = 0.f;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!Catalog::gAvailable[d] || !Catalog::gMobile[d] || !Catalog::gBuilder[d]
				|| (Catalog::gBuildPower[d] <= 0.f) || !ReachesCeiling(d)
				|| Catalog::Def(d).IsRoleAny(Unit::Role::COMM.mask))
			continue;
		const float c = (Catalog::gCostM[d] + Catalog::gCostE[d] / 60.f) / Catalog::gBuildPower[d];
		if ((con < 0) || (c < conPerBp)) {
			con = d;
			conPerBp = c;
		}
	}
	if (con < 0)
		return 0;
	float upBt = 0.f;
	const array<int>@ bl = Catalog::gBuildsList[con];
	for (uint q = 0; q < bl.length(); ++q) {
		if ((Catalog::gExtractsM[bl[q]] >= ceil) && (Catalog::gBuildTime[bl[q]] > upBt))
			upBt = Catalog::gBuildTime[bl[q]];
	}
	array<AIFloat3> todo;
	float u = 0.f;
	for (uint i = 0; i < gLSpot.length(); ++i) {
		if ((gLExtract[i] > 0.f) && (gLExtract[i] < ceil)) {
			todo.insertLast(gLSpot[i]);
			u += gLIncome[i] * IncomeMult() * (ceil - gLExtract[i]);
		}
	}
	const int b = int(todo.length());
	gUpHandsB = b;
	if ((b == 0) || (upBt <= 0.f) || (u <= 0.f))
		return 0;
	float walk = 0.f;
	for (uint i = 0; i < todo.length(); ++i) {
		float nearest = -1.f;
		for (uint j = 0; j < todo.length(); ++j) {
			if (i == j)
				continue;
			const float dd = todo[i].distance2D(todo[j]);
			if ((nearest < 0.f) || (dd < nearest))
				nearest = dd;
		}
		if (nearest > 0.f)
			walk += nearest;
	}
	walk /= float(b);
	const float speed = (Catalog::gSpeed[con] > 1.f) ? Catalog::gSpeed[con] : 40.f;
	const float t = upBt / Catalog::gBuildPower[con] + walk / speed;
	gUpHandsT = t;
	const float cost = Catalog::gCostM[con] + Catalog::gCostE[con] / 60.f;
	const float x = float(b) * t * u / (2.f * ((cost > 1.f) ? cost : 1.f));
	int n = 1;
	while ((n < b) && (float(n) * float(n + 1) < x))
		++n;
	gUpHandsN = n;
	if (ai.frame >= gNextUpHandsLog) {
		gNextUpHandsLog = ai.frame + 60 * SECOND;
		AiLog(Factory::T() + "apex: uphands want=" + n + " have=" + CeilingConsOwned()
			+ " backlog=" + b + " t=" + int(t) + "s U=" + formatFloat(u, "", 0, 1)
			+ " con=" + Catalog::Def(con).GetName() + " outForUp=" + gOutForUp
			+ " upFirstLifted=" + gUpFirstLifted);
		gOutForUp = 0;
		gUpFirstLifted = 0;
	}
	return n;
}

// UPGRADES FIRST (apexearth 2026-09-30: a T2 con walked to a T1 extractor and
// raised a Pulsar there -- "upgrade the mexes first, then do this other stuff";
// the economy compounds). A ceiling hand offered an upgrade drops every job but
// a claim, a reclaim and the home work (generators, converters, nanos, assist). A hand
// OutForUpgrades sent out takes the upgrade outright (true: no draw); the home
// hand draws it against its home work. A refused upgrade falls to the rest.
int gUpFirstLifted = 0;
bool UpgradesFirst(CCircuitUnit@ unit, array<Want@>@ ranked)
{
	if (!ReachesCeiling(int(unit.circuitDef.id)) || unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask))
		return false;
	if (CrewSplitOn() && !CrewIsField(unit))
		return false;   // home crew: the upgrades are the field crew's
	int upAt = -1;
	for (uint i = 0; (i < ranked.length()) && (upAt < 0); ++i)
		if (ranked[i].kind == WK_MEXUP)
			upAt = int(i);
	if (upAt < 0)
		return false;
	for (uint i = 0; i < ranked.length(); ) {
		const int k = ranked[i].kind;
		if ((k == WK_MEXUP) || (k == WK_MEX) || (k == WK_RECLAIM) || (k == WK_ENERGY)
				|| (k == WK_CONVERT) || (k == WK_ASSIST) || (k == WK_STORE) || (k == WK_NANO)) {
			++i;
			continue;
		}
		ranked.removeAt(i);
	}
	++gUpFirstLifted;
	if (!OutForUpgrades(unit))
		return false;
	for (uint i = 0; i < ranked.length(); ++i) {
		if (ranked[i].kind != WK_MEXUP)
			continue;
		if (i > 0) {
			Want@ up = ranked[i];
			ranked.removeAt(i);
			ranked.insertAt(0, up);
		}
		break;
	}
	return true;
}

// ONE ADVANCED HAND STAYS HOME (apexearth 2026-09-30: "one stays home and makes
// the fusion, the Tier 1 cons help that guy; send more of them out to upgrade").
// While upgrades wait, a ceiling hand is not offered generators, converters or
// assist once another ceiling hand is already on a generator or converter.
int gOutForUp = 0;
array<int> gHomeHandIds;
int gHomeHandsAt = -1;
bool OutForUpgrades(CCircuitUnit@ unit)
{
	const int ud = int(unit.circuitDef.id);
	if (!ReachesCeiling(ud) || unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask))
		return false;
	if (CrewSplitOn())
		return CrewIsField(unit);
	UpgradeHandsWant();
	if (gUpHandsB <= 0)
		return false;
	if (gHomeHandsAt != ai.frame) {
		gHomeHandsAt = ai.frame;
		gHomeHandIds.resize(0);
		for (uint i = 0; i < gWorkers.length(); ++i) {
			CCircuitUnit@ u = gWorkers[i];
			if ((u is null) || (u.task is null))
				continue;
			if (!ReachesCeiling(int(u.circuitDef.id)) || u.circuitDef.IsRoleAny(Unit::Role::COMM.mask))
				continue;
			const CCircuitDef@ bd = u.task.buildDef;
			if (bd is null)
				continue;
			const int b = int(bd.id);
			if ((Catalog::gMakeE[b] > 0.f) || (Catalog::gConvCapacity[b] > 0.f))
				gHomeHandIds.insertLast(int(u.id));
		}
	}
	const uint n = gHomeHandIds.length();
	if ((n == 0) || ((n == 1) && (gHomeHandIds[0] == int(unit.id))))
		return false;
	++gOutForUp;
	return true;
}

// THE ARMY A LONG BUILD CANNOT AFFORD. apexearth: "during that entire time
// you're making an AFUS you can afford military better and protect yourself.
// You're giving yourself options." Two of the three costs he names are already
// priced -- the build may die (the survival discount) and it delays extraction
// (the streams below). The third was not: income and lathes committed to a
// frame for eighteen minutes are income and lathes the army and defence wanted,
// and a build that delivers in forty seconds surrenders almost none of that.
// Same currency and the same unserved-demand shape as the extraction streams.
float ArmyGapStream()
{
	const float gap = ArmyTarget() - ArmyValue();
	if (gap <= 0.f)
		return 0.f;
	const float fill = ai.GetTunable("apex_army_fill_s", TUNE_ARMY_FILL_S);
	return gap / ((fill > 1.f) ? fill : 180.f);
}

// UpDemand BOUNDED BY HANDS THAT CAN SERVE IT. Catalog::gAvailable is not
// tier-gated, so BestExtract() names the moho from frame zero and UpDemand
// reports the full upgrade stream while we own no constructor able to place
// one. Charging that against every build taxes a T1 solar for work nobody
// could do. Zero until some owned mobile builder reaches the ceiling.
float ServableUpDemand()
{
	const float ceil = BestExtract();
	const array<int>@ _own37 = OwnedDefs();
	for (uint _oi37 = 0; _oi37 < _own37.length(); ++_oi37) {
		const uint d = uint(_own37[_oi37]);
		const int di = int(d);
		if ((gOwnCount[d] <= 0) || !Catalog::gMobile[di] || !Catalog::gBuilder[di])
			continue;
		const array<int>@ bb = Catalog::gBuildsList[di];
		for (uint q = 0; q < bb.length(); ++q) {
			if (Catalog::gExtractsM[bb[q]] >= ceil)
				return UpDemand();
		}
	}
	return 0.f;
}

// THE EXPANSION STREAM A LONG BUILD POSTPONES. UpDemand is the metal/s waiting
// on mex UPGRADES; this is the metal/s waiting on mex CLAIMS. Charging only the
// first meant a build that eats the economy for minutes was billed nothing on a
// map where we hold almost nothing to upgrade -- measured on Supreme Isthmus,
// held=4 of mapSpots=90 with upD=16, so an afus postponed "nothing" while what
// it actually postponed was eighty-four spots (apexearth, watching it happen
// again). Bounded by the hands that could actually claim them, the same
// unserved-demand shape used everywhere else.
// SPOTS WE COULD ACTUALLY CLAIM: not ours, not under a seen enemy building,
// not ground the reach veto or a constructor's death has marked. "All spots
// minus ours" counted the enemy's whole half of the map as open and bought
// air cons by the hundred to fly at it.
int gClaimableAt = -1000;
int gClaimableN = 0;
int ClaimableSpots()
{
	if (ai.frame - gClaimableAt < 5 * SECOND)
		return gClaimableN;
	gClaimableAt = ai.frame;
	CacheSpots();
	const array<int>@ lidx = LedgerIdx();
	const array<bool>@ allyHeld = AllyHeldSpots();
	int n = 0;
	for (uint si = 0; si < gAllSpots.length(); ++si) {
		if ((int(si) < int(lidx.length())) && (lidx[si] >= 0))
			continue;
		if ((si < allyHeld.length()) && allyHeld[si])
			continue;
		const AIFloat3 sp = gAllSpots[si];
		if (!OnMap(sp) || NearBlocked(sp) || NearConDeath(sp))
			continue;
		if (ai.GetEnemyCostAt(sp, 48.f) > 0.f)
			continue;
		++n;
	}
	gClaimableN = n;
	return n;
}

float OpenSpotStream()
{
	CacheSpots();
	const int open = ClaimableSpots();
	if (open <= 0)
		return 0.f;
	float claimers = 0.f;
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		if ((gOwnCount[d] > 0) && Catalog::gMobile[int(d)] && Catalog::gBuilder[int(d)])
			claimers += float(gOwnCount[d]);
	}
	if (claimers < 1.f)
		claimers = 1.f;
	const float reach = (float(open) < claimers) ? float(open) : claimers;
	return reach * SpotM();
}

// THE DISPLACEMENT CHARGE, ONCE PER FRAME INSTEAD OF ONCE PER CANDIDATE.
// ValueOf prices every candidate def of every want through this sum, and both
// halves are full walks of the def table (580 slots) and the spot ledger -- so
// ProposeMexUp, which calls ValueOf once per held spot per extractor def, paid
// them held-spots x extractors times over. Both are functions of the owned
// counts, the ledger, the handicap and the last probed yield; every one of
// those either bumps a stamp here or cannot move without the frame moving.
int gDsFrame = -30000;
int gDsOwn = -1;
int gDsLedger = -1;
float gDsSpotM = -1.f;
float gDsVal = 0.f;
float DisplacedStreamM()
{
	CacheSpots();
	if ((gDsFrame == ai.frame) && (gDsOwn == gOwnStamp)
		&& (gDsLedger == int(gLSpot.length())) && (gDsSpotM == gLastSpotM))
	{
		return gDsVal;
	}
	gDsFrame = ai.frame;
	gDsOwn = gOwnStamp;
	gDsLedger = int(gLSpot.length());
	gDsSpotM = gLastSpotM;
	// Upgrades only: a 50-metal claim waits on a hand, never on income.
	gDsVal = ServableUpDemand();
	return gDsVal;
}

// TWO HALF-BUILT FUSIONS ARE WORSE THAN ONE FINISHED: an expensive def
// already in progress takes the next asker as a JOINER -- doubling build
// speed on the standing frame -- instead of opening a parallel copy
// (apexearth: "not too many of the same building in parallel; assist
// should count the time saved").
IUnitTask@ JoinBig(CCircuitDef@ def)
{
	if ((def is null)
		|| (def.costM < ai.GetTunable("apex_join_min_m", TUNE_JOIN_MIN_M)))
		return null;
	return Requests::LiveTaskOf(def);
}

// CROSS-TIER: the gate above reads the WANT's cost and LiveTaskOf matches
// the same def only, so a T1 con that elected a 370m advsol never saw the
// 9,000m fusion being built beside it and went to place the advsol instead
// (apexearth 2026-08-28: "our T1 cons will then go make an advanced solar
// instead of going to help the T2 fusion being made. Our join logic seems
// to only care about assisting our own tier"). Any live energy job at
// least ~150m big takes the asker: capability is needed to PLACE a def,
// not to lathe a standing frame. WorthJoining still prices the walk
// against the job's own remaining bill.
//
// RANKED BY TIME-TO-ENERGY (apexearth 2026-08-30, six energy frames rising
// at once, one at ETA 64m: "they should all focus their efforts on the most
// efficient energy project. (taking in to account the TTE efficiency (time
// to energy))"): e/s per second of remaining build with this asker's hands
// added, so a 55% fusion outranks an 11% afus however big the afus is.
float EnergyTTE(float makeE, float costM, float prog, uint busy)
{
	return EnergyTTEWith(makeE, costM, 0.f, prog, busy);
}

// The remaining energy bill stretches the time exactly as it stretches a
// build (EStretch): in a stall a 5,000 E advanced solar at 0% outscored a
// zero-E solar and drew every hand, 293 consolidations in twelve minutes.
float EnergyTTEWith(float makeE, float costM, float costE, float prog, uint busy)
{
	const float p = (prog < 0.f) ? 0.f : prog;
	const float remainM = costM * (1.f - p);
	if (remainM <= 1.f)
		return 0.f;   // effectively done; another pair of hands adds nothing
	float drain = ai.GetTunable("apex_request_drain", TUNE_REQUEST_DRAIN);
	if (drain <= 1.f)
		drain = 7.f;
	float sec = remainM / (float(busy + 1) * drain);
	if (costE > 1.f)
		sec *= EStretch(costE * (1.f - p), sec);
	return makeE / ((sec > 0.1f) ? sec : 0.1f);
}

IUnitTask@ JoinBigEnergy(CCircuitUnit@ unit, CCircuitDef@ want)
{
	// 150, not apex_join_min_m: the 500 bar excluded the 370m advanced
	// solar, and three cons opened three solo advsols in one screen
	// (apexearth, watching twice: "wasteful spending... They should each
	// work on 1 together"). Solars and wind stay below the bar; the crew
	// cap and WorthJoining's walk-vs-remaining still bound every fold.
	float minM = ai.GetTunable("apex_join_min_m", TUNE_JOIN_MIN_M);
	if (minM > 150.f)
		minM = 150.f;
	// HANDS BEFORE SITES, unconditionally: a bigger elected want folds onto
	// the smaller job already rising, because hands on a standing frame bring
	// power sooner than a fresh, larger hole in the ground. This was first
	// gated on a stall/overflow regime, and the regime FLICKERED: the moment
	// two ordered fusions covered the deficit, EnergyShortOfOrdered read
	// clean, the fold-down switched off, and an afus want founded site #3
	// beside them (watched live, 20.7m). The trinket case the old
	// one-direction rule protected against is already bounded: the >=150m
	// bar, the candidate's own crew cap, and WorthJoining's walk-vs-remaining.
	IUnitTask@ best = null;
	float bestScore = 0.f;
	for (uint i = 0; i < Requests::gLive.length(); ++i) {
		IUnitTask@ cand = Requests::gLive[i];
		if ((cand is null) || cand.IsDead() || (cand.buildDef is null))
			continue;
		const float cost = cand.buildDef.costM;
		if (cost < minM)
			continue;
		const float makeE = aiEconomyMgr.GetEnergyMake(cand.buildDef);
		if (makeE <= 1.f)
			continue;
		const uint busy = Requests::Workers(cand);
		// An abandoned frame IS a candidate: its bill is part-paid and
		// nobody else will finish it. Unmanned with no frame yet stays
		// claim business (placing needs build capability).
		if ((busy == 0) && (cand.target is null))
			continue;
		if ((busy > 0) && (busy >= Requests::SiteWorkerCap(cand.buildDef)))
			continue;
		if ((unit !is null) && !unit.circuitDef.CanBuild(cand.buildDef)
			&& (cand.target is null))
			continue;   // cannot place it and no frame stands yet
		const AIFloat3 where = cand.GetBuildPos();
		if (!OnMap(where))
			continue;
		const float prog = Requests::Progress(cand);
		if ((unit !is null) && !Requests::WorthJoiningSite(cand,
				unit.GetPos(ai.frame).distance2D(where),
				Catalog::gSpeed[int(unit.circuitDef.id)],
				Catalog::gBuildPower[int(unit.circuitDef.id)]))
			continue;
		const float score = EnergyTTEWith(makeE, cost,
				Catalog::gCostE[int(cand.buildDef.id)], prog, busy);
		if ((best is null) || (score > bestScore)) {
			bestScore = score;
			@best = cand;
		}
	}
	if ((best !is null) && (unit !is null) && (best.buildDef !is null)
		&& !unit.circuitDef.CanBuild(best.buildDef))
	{
		AiLog("apex: join assist t=" + ai.teamId + " "
			+ unit.circuitDef.GetName() + " #" + unit.id
			+ " -> " + best.buildDef.GetName()
			+ " (cross-tier: wanted "
			+ ((want !is null) ? want.GetName() : "?") + ")");
	}
	if (best !is null)
		return best;
	// A frame with NO task at all (the request died with its builder) only
	// ever came back through the per-def resume in Requests::Take, so an
	// orphaned fusion frame sat at "ETA ???" while new energy founded beside
	// it. Adopt the best energy orphan by the same TTE ranking.
	if (unit is null)
		return null;
	const AIFloat3 uAt = unit.GetPos(ai.frame);
	CCircuitUnit@ frame = null;
	float frameScore = 0.f;
	for (uint i = 0; i < gComDef.length(); ++i) {
		if (!ComIsOrphan(i))
			continue;
		const int d = gComDef[i];
		if (!Catalog::ValidId(d) || (Catalog::gMakeE[d] <= 1.f)
			|| (Catalog::gCostM[d] < minM))
			continue;
		CCircuitUnit@ f = ai.GetTeamUnit(gComId[i]);
		if (f is null)
			continue;
		const float h = f.GetHealthPercent();
		const float score = EnergyTTEWith(Catalog::gMakeE[d], Catalog::gCostM[d],
				Catalog::gCostE[d], (h < 0.f) ? 0.f : h, 0);
		if ((frame is null) || (score > frameScore)) {
			frameScore = score;
			@frame = f;
		}
	}
	if (frame is null)
		return null;
	const AIFloat3 at = frame.GetPos(ai.frame);
	if (Builder::ThreatFor(unit, at) > Builder::CON_THREAT_VETO)
		return null;   // abandoned because the ground is hot; still is
	float done = frame.GetHealthPercent();
	if (done < 0.f)
		done = 0.f;
	else if (done > 1.f)
		done = 1.f;
	const float costA = (frame.circuitDef !is null) ? frame.circuitDef.costM : 500.f;
	if (!Requests::WorthJoining(uAt.distance2D(at), done, costA, 0))
		return null;
	float drain = ai.GetTunable("apex_request_drain", TUNE_REQUEST_DRAIN);
	if (drain <= 1.f)
		drain = 7.f;
	const int hold = int(costA * (1.f - done) / drain) + 10;
	IUnitTask@ res = aiBuilderMgr.Enqueue(
			TaskB::Guard(Task::Priority::NORMAL, frame, false, hold * SECOND));
	if (res !is null)
		AiLog("apex: adopt energy orphan t=" + ai.teamId + " "
			+ unit.circuitDef.GetName() + " #" + unit.id + " -> "
			+ ((frame.circuitDef !is null) ? frame.circuitDef.GetName() : "?")
			+ " done=" + formatFloat(done, "", 0, 2));
	return res;
}

// THE WALK IS THE RISK, not just the destination (apexearth, after a fresh
// T2 con marched into the enemy army while 4 home mexes sat unupgraded).
// The road is read off the threat map -- the sensor that reads 100-460 at
// every con death -- against the hot gate's own bar: ground our guns do not
// reach that is hot for a builder is not walked through, whatever the spot
// pays. (This compared GetEnemyCostAt, a visible-unit COUNT, against the
// walker's metal: it never once fired, docs/25 S28.)
bool SpotHot(const AIFloat3& in p)
{
	const float hot = ai.GetThreatAt(p);
	return (hot > 1.f) && (hot > ai.GetAllyDefendInflAt(p));
}

bool DeathWalk(CCircuitUnit@ unit, const AIFloat3& in dest)
{
	const AIFloat3 here = unit.GetPos(ai.frame);
	for (int s = 1; s <= 4; ++s) {
		AIFloat3 p = here;
		const float f = float(s) / 4.f;
		p.x += (dest.x - here.x) * f;
		p.z += (dest.z - here.z) * f;
		if (OnMap(p) && SpotHot(p))
			return true;
	}
	return false;
}

// Claims started, by who and by the spot's trip risk from home (<0.1, <0.3, more),
// and the commander's past his leash; with the metal reclaim want's counts.
array<int> gClaimCom(3, 0);
array<int> gClaimCon(3, 0);
int gClaimComFar = 0;
int gRcmProposed = 0, gRcmWon = 0;
float gRcmMetal = 0.f;
int gNextClaimLog = 0;
void NoteClaim(CCircuitUnit@ unit, Want@ w)
{
	if (w.kind == WK_RECLAIM) {
		++gRcmWon;
		gRcmMetal += ai.GetWreckValueAt(w.pos, Builder::WRECK_RADIUS);
	} else {
		const float r = TripRisk(w.pos);
		const int b = (r < 0.1f) ? 0 : ((r < 0.3f) ? 1 : 2);
		if (unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask)) {
			++gClaimCom[b];
			if (ComFar(w.pos))
				++gClaimComFar;
		} else {
			++gClaimCon[b];
		}
	}
	if (ai.frame >= gNextClaimLog) {
		gNextClaimLog = ai.frame + 60 * SECOND;
		AiLog(Factory::T() + "apex: claimband t=" + ai.teamId
			+ " com=" + gClaimCom[0] + "/" + gClaimCom[1] + "/" + gClaimCom[2]
			+ " comFar=" + gClaimComFar
			+ " con=" + gClaimCon[0] + "/" + gClaimCon[1] + "/" + gClaimCon[2]
			+ " rcm=" + gRcmProposed + "/" + gRcmWon + " rcmM=" + int(gRcmMetal)
			+ " reclaimM=" + int(ai.GetTeamRulesParam("apexReclaimM", -1.f)));
	}
}

// WHY A MEX WANT DID NOT HAPPEN. apexearth: "our largest problem is still that
// we are not making enough mexes. If we aren't capturing half the map worth of
// mexes in a 1v1 then we're losing the game." Each refusal is counted at its
// own gate so the answer is read, not guessed.
int gMexNoOpen = 0, gMexDeathWalk = 0, gMexEcoFar = 0, gMexComFar = 0;
// Last single sweep (see PickSpot): total spots, on our ledger, at a trip
// risk of half or worse, surviving candidates, and the home->FoeAnchor span.
int gSwTotal = 0, gSwLedger = 0, gSwPast = 0, gSwCand = 0, gSwHot = 0, gSwAlly = 0;
float gSwSpan = 0.f;
int gMexEcoQuiet = 0, gMexClaimed = 0, gMexPriced = 0, gNextMexDiag = 0;
float gMexRiskSum = 0.f;   // TripRisk over priced proposals, for mexdiag
int gNextRebuildLog = 0;
int gMexDeep = 0;
void MexDiag()
{
	if (ai.frame < gNextMexDiag)
		return;
	gNextMexDiag = ai.frame + 60 * SECOND;
	CacheSpots();
	// How DEEP the ground we hold is: 0 = our own start, 1 = theirs. The whole
	// point of the gradient is to keep the opening constructors off contested
	// centre spots (apexearth: "stop our initial constructors from taking what
	// are often thought of as more valuable mexes or geos in the center of the
	// map - highly contested areas"), so it is the number to watch.
	float gMax = 0.f, gSum = 0.f;
	for (uint gi = 0; gi < gLPos.length(); ++gi) {
		const float gg = ThreatGradient(gLPos[gi]);
		gSum += gg;
		if (gg > gMax) gMax = gg;
	}
	const float gAvg = (gLPos.length() > 0) ? (gSum / float(gLPos.length())) : 0.f;
	// The ledger against the census: rows below the ceiling are the upgrade
	// backlog, and the census is what actually stands.
	const float ceilD = BestExtract();
	int ledLow = 0, ledTop = 0, ledClaim = 0, ownLow = 0, ownTop = 0;
	for (uint li = 0; li < gLExtract.length(); ++li) {
		if (gLExtract[li] <= 0.f)
			++ledClaim;
		else if (gLExtract[li] < ceilD)
			++ledLow;
		else
			++ledTop;
	}
	const array<int>@ ownD = OwnedDefs();
	for (uint oi = 0; oi < ownD.length(); ++oi) {
		const int od = ownD[oi];
		if ((gOwnCount[uint(od)] <= 0) || (Catalog::gExtractsM[od] <= 0.f) || Catalog::gMobile[od])
			continue;
		if (Catalog::gExtractsM[od] < ceilD)
			ownLow += gOwnCount[uint(od)];
		else
			ownTop += gOwnCount[uint(od)];
	}
	AiLog("apex: mexdiag t=" + ai.teamId + " mapSpots=" + gAllSpots.length()
		+ " held=" + gLSpot.length()
		+ " ledLow=" + ledLow + " ledTop=" + ledTop + " ledClaim=" + ledClaim
		+ " ownLow=" + ownLow + " ownTop=" + ownTop
		+ " depthAvg=" + formatFloat(gAvg, "", 0, 2)
		+ " depthMax=" + formatFloat(gMax, "", 0, 2)
		+ " | noOpen=" + gMexNoOpen + " claimed=" + gMexClaimed
		+ " deathWalk=" + gMexDeathWalk
		+ " ecoFar=" + gMexEcoFar + " comFar=" + gMexComFar + " ecoQuiet=" + gMexEcoQuiet
		+ " deep=" + gMexDeep
		+ " priced=" + gMexPriced
		+ " riskAvg=" + formatFloat((gMexPriced > 0) ? (gMexRiskSum / float(gMexPriced)) : 0.f, "", 0, 2)
		+ " share=" + formatFloat(TripShare(), "", 0, 2)
		+ " | sweep " + gSwPast + "risky+" + gSwHot + "hot+" + gSwLedger + "own+" + gSwAlly + "ally/" + gSwTotal
		+ " cand=" + gSwCand + " span=" + int(gSwSpan)
		+ " | supCall=" + gSupCalls + " supDone=" + gSupDone + " supOpen=" + gSupWorker.length()
		+ " supWorth=" + int(SupportWorth()));
	gSupCalls = 0; gSupDone = 0;
	gMexNoOpen = 0; gMexDeathWalk = 0; gMexEcoFar = 0; gMexComFar = 0;
	gMexEcoQuiet = 0; gMexClaimed = 0; gMexPriced = 0;
	gMexDeep = 0; gMexRiskSum = 0.f;
}

// THE REFERENCE POINT IS THE DECISION. FindOpenMexSpot answers with ONE spot
// near whatever position it is handed, so asking only from the builder's feet
// made the search stop at the nearest cluster -- and when that one answer was
// already ours, the want returned empty and expansion left the auction
// entirely for that election (apexearth: "we easily get into funks where we
// don't even try to capture additional mex locations"). The map's own spot
// list is already cached, so rank every spot we do not hold by what it pays
// against the walk, and let the engine confirm what is actually open near the
// best of them. The engine keeps sole authority over occupancy, reachability
// and buildability; the ranking only chooses where to ask.
// HOW MANY RANKED SPOTS GET OFFERED TO THE ENGINE before the election gives up
// on extraction entirely. At 3, a builder whose three best spots are all taken
// or unbuildable proposes NO mex want at all that tick -- with `claimed=29` in
// one diag window that is a routine outcome, and it reads as "no ground left"
// rather than "we did not look far enough". A bound on WORK (each try is one
// FindOpenMexSpot probe), not on how much we may expand.
int gMexTries = -1;
int MexTries()
{
	if (gMexTries < 0) {
		const int n = int(ai.GetTunable("apex_mex_tries", TUNE_MEX_TRIES));
		gMexTries = (n < 1) ? 1 : n;
	}
	return gMexTries;
}
// WHERE A DEAD EXTRACTOR'S SPOT GOES. apexearth, watching: "we spend minutes
// not rebuilding mexes even though they're perfectly safe." Each of our dead
// spots is watched for four minutes and the sweep names the gate that
// refuses it (sampled 15 s a spot).
array<AIFloat3> gDeadSpotPos;
array<int> gDeadSpotAt;
array<int> gDeadSpotLogAt;
void NoteMexDeath(const AIFloat3& in at)
{
	gDeadSpotPos.insertLast(at);
	gDeadSpotAt.insertLast(ai.frame);
	gDeadSpotLogAt.insertLast(0);
}
// The dead records near each spot, found once per sweep through the spot grid
// instead of every record against every spot.
array<int> gDsOf;
void DeadSpotPrep()
{
	const uint n = gAllSpots.length();
	gDsOf.resize(n);
	for (uint si = 0; si < n; ++si)
		gDsOf[si] = -1;
	for (uint i = 0; i < gDeadSpotPos.length(); ) {
		if (ai.frame - gDeadSpotAt[i] > 4 * MINUTE) {
			gDeadSpotPos.removeAt(i);
			gDeadSpotAt.removeAt(i);
			gDeadSpotLogAt.removeAt(i);
			continue;
		}
		gSpotGrid.Query(gDeadSpotPos[i].x, gDeadSpotPos[i].z, 100.f);
		for (uint q = 0; q < gSpotGrid.hit.length(); ++q) {
			const uint si = uint(gSpotGrid.hit[q]);
			if ((si < n) && (gDsOf[si] < 0) && (gDeadSpotPos[i].distance2D(gAllSpots[si]) < 100.f))
				gDsOf[si] = int(i);
		}
		++i;
	}
}
int DeadSpotOf(uint si)
{
	if (si >= gDsOf.length())
		return -1;
	const int i = gDsOf[si];
	if ((i < 0) || (ai.frame < gDeadSpotLogAt[uint(i)]))
		return -1;
	gDeadSpotLogAt[uint(i)] = ai.frame + 15 * SECOND;
	return i;
}

void DeadSpotSay(int w, const AIFloat3& in sp, const string& in gate)
{
	if (w < 0)
		return;
	AiLog(Factory::T() + "apex: deadspot " + int(sp.x) + "," + int(sp.z)
		+ " dead=" + int((ai.frame - gDeadSpotAt[uint(w)]) / SECOND) + "s"
		+ " gate=" + gate
		+ " threat=" + formatFloat(ai.GetThreatAt(sp), "", 0, 0)
		+ " infl=" + formatFloat(ai.GetAllyDefendInflAt(sp), "", 0, 1)
		+ " foe=" + formatFloat(ai.GetEnemyCostAt(sp, 600.f), "", 0, 0));
}

// The sweep's working set, kept between calls. Ninety insertLast into two
// freshly-constructed arrays, every election, was the sweep's own overhead.
array<int> gPsCand;
array<float> gPsScore;
// THE SPOTS' OWN STATE, EVERY 4 S. Everything PickSpot asked per spot but the
// walk is the same for every asker -- marks, heat, trip risk -- and it was
// re-read for every spot on every mex election. The ledger is NOT in it: it
// moves on every claim, and PickSpot reads it live.
const int PT_OPEN = 0, PT_BLOCKED = 2, PT_CONDEATH = 3, PT_HOT = 4, PT_NONE = 5, PT_ALLY = 6;

// SPOTS AN ALLY ALREADY EXTRACTS: our ledger knows only our own, and an
// allied spot offered as a claim is refused at the site.
array<bool> gAllyHeld;
int gAllyHeldAt = -1;
const array<bool>@ AllyHeldSpots()
{
	AllyStaticsSync();
	CacheSpots();
	if ((gAllyHeldAt == gAllyStAt) && (gAllyHeld.length() == gAllSpots.length()))
		return gAllyHeld;
	gAllyHeldAt = gAllyStAt;
	gAllyHeld.resize(gAllSpots.length());
	for (uint s = 0; s < gAllyHeld.length(); ++s)
		gAllyHeld[s] = false;
	for (uint i = 0; i < gAllyStPos.length(); ++i) {
		if (Catalog::gExtractsM[gAllyStDef[i]] <= 0.f)
			continue;
		gSpotGrid.Query(gAllyStPos[i].x, gAllyStPos[i].z, 64.f);
		for (uint q = 0; q < gSpotGrid.hit.length(); ++q) {
			const uint si = uint(gSpotGrid.hit[q]);
			if ((si < gAllyHeld.length()) && (gAllSpots[si].distance2D(gAllyStPos[i]) < 64.f))
				gAllyHeld[si] = true;
		}
	}
	return gAllyHeld;
}
array<int> gPtState;
array<float> gPtRisk;
int gPtAt = -1000;
float gPtShare = 0.f;
array<int> gPtMark;
void PtMarkNear(const AIFloat3& in at, int st)
{
	const float nearSq = BLOCK_NEAR * BLOCK_NEAR;
	gSpotGrid.Query(at.x, at.z, BLOCK_NEAR);
	for (uint q = 0; q < gSpotGrid.hit.length(); ++q) {
		const uint si = uint(gSpotGrid.hit[q]);
		if ((si >= gPtMark.length()) || (gPtMark[si] == PT_BLOCKED))
			continue;
		const float dx = at.x - gAllSpots[si].x, dz = at.z - gAllSpots[si].z;
		if ((dx * dx + dz * dz) < nearSq)
			gPtMark[si] = st;
	}
}
void SpotTableFill()
{
	if ((ai.frame - gPtAt < 4 * SECOND) && (gPtState.length() == gAllSpots.length()))
		return;
	gPtAt = ai.frame;
	const uint n = gAllSpots.length();
	gPtState.resize(n);
	gPtRisk.resize(n);
	gPtShare = TripShare();
	const float incMul = IncomeMult();
	// The live marks, once: NearBlocked/NearConDeath polled the engine and
	// walked both rings for every spot.
	BlockPoll();
	// Each live mark marks the spots near it through the spot grid: every spot
	// against every mark was the table's whole cost late in a game.
	gPtMark.resize(n);
	for (uint si = 0; si < n; ++si)
		gPtMark[si] = PT_OPEN;
	for (uint k = 0; k < gBlockPos.length(); ++k) {
		if (ai.frame - gBlockAt[k] <= BLOCK_TTL)
			PtMarkNear(gBlockPos[k], PT_BLOCKED);
	}
	// A constructor's death near a spot no longer bans it for three minutes:
	// the danger that killed him is read live (PT_HOT, the risk price), and the
	// ban kept our own home extractors down for minutes after a raid had gone.
	const array<bool>@ allyHeld = AllyHeldSpots();
	for (uint si = 0; si < n; ++si) {
		const AIFloat3 sp = gAllSpots[si];
		gPtRisk[si] = 0.f;
		if (!OnMap(sp) || (gAllSpotInc[si] * incMul <= 0.f)) {
			gPtState[si] = PT_NONE;
			continue;
		}
		if ((si < allyHeld.length()) && allyHeld[si]) {
			gPtState[si] = PT_ALLY;
			continue;
		}
		if (gPtMark[si] != PT_OPEN) {
			gPtState[si] = gPtMark[si];
			continue;
		}
		gPtRisk[si] = TripRiskWith(sp, gPtShare);
		gPtState[si] = SpotHot(sp) ? PT_HOT : PT_OPEN;
	}
}

int PickSpot(CCircuitUnit@ unit, const AIFloat3& in here, float speed)
{
	CacheSpots();
	const double _tTbl = Perf::T0();
	SpotTableFill();
	Perf::Add("mx.table", _tTbl);
	const double _tScan = Perf::T0();
	gPsCand.resize(0);
	gPsScore.resize(0);
	// Everything but the spot is fixed for the sweep -- the army share, the
	// role and the leash. Read once: on an 8v8 map this loop runs over a
	// hundred spots per election per builder.
	const AIFloat3 foeAt = Front::FoeAnchor();
	const float fex = foeAt.x - Builder::gHomePos.x;
	const float fez = foeAt.z - Builder::gHomePos.z;
	const float share = gPtShare;
	const bool ecoOn = EcoQuiet() && Builder::gHomeSet;
	const bool comm = unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask);
	const float ecoLeash = ai.GetTunable("apex_eco_leash", TUNE_ECO_LEASH);
	const float incMul = IncomeMult();
	// One sweep's composition, kept for mexdiag.
	gSwTotal = 0; gSwLedger = 0; gSwPast = 0; gSwCand = 0; gSwHot = 0; gSwAlly = 0;
	gSwSpan = sqrt(fex * fex + fez * fez);
	const array<int>@ lidx = LedgerIdx();
	const int lidxN = int(lidx.length());
	const bool supFree = SupportFree();
	const bool dsOn = gDeadSpotPos.length() > 0;
	if (dsOn)
		DeadSpotPrep();
	float bestHotScore = 0.f;
	int bestHot = -1;
	for (uint si = 0; si < gAllSpots.length(); ++si) {
		++gSwTotal;
		const AIFloat3 sp = gAllSpots[si];
		const int dw = dsOn ? DeadSpotOf(si) : -1;
		const int st = gPtState[si];
		if ((int(si) < lidxN) ? (lidx[si] >= 0) : (LedgerFind(int(si)) >= 0)) {
			++gSwLedger;
			if (dw >= 0) {
				const int row = LedgerFind(int(si));
				DeadSpotSay(dw, sp, ((row >= 0) && (gLExtract[uint(row)] > 0.f)) ? "standing" : "claimed");
			}
			continue;
		}
		if (st == PT_NONE)
			continue;
		if (st == PT_ALLY) {
			++gSwAlly;
			continue;
		}
		const float inc = gAllSpotInc[si] * incMul;
		// A spot a hand could not reach in the last three minutes is not
		// offered to the next hand (the stuck watch and the C++ path test
		// both write the mark).
		if ((st == PT_BLOCKED) || (st == PT_CONDEATH)) {
			++gSwPast;
			DeadSpotSay(dw, sp, (st == PT_BLOCKED) ? "blocked" : "condeath");
			continue;
		}
		// THE EXECUTOR'S OWN BAR, ASKED HERE. The builder task refuses a site
		// hotter than our guns' influence on it (CanReachAtSafe, safeBar),
		// and a spot chosen past that bar is a walk, an abort and the same
		// election again: at +0 on Isthmus 68 of 86 mex elections in one
		// four-minute window died so, our extractor count peaking at
		// minute 8 while theirs kept climbing. A hot spot is not offered;
		// the ground it sits on is the defence market's starved-spot stake.
		// Hot for a constructor; the commander takes it where nothing there can kill him.
		const float comF = (comm && !gCsT2) ? ComRaidF(unit, sp) : 1.f;   // caution (T2) ends his dangerous claims
		if ((st == PT_HOT) && !(comm && (comF < 1.f))) {
			++gSwHot;
			DeadSpotSay(dw, sp, "hot");
			if (supFree) {
				const float hw = (speed > 1.f) ? (here.distance2D(sp) / speed) : 60.f;
				const float raw = inc / (hw + 1.f);
				if (raw > bestHotScore) {
					const float hs = raw * (1.f - gPtRisk[si]);
					if (hs > bestHotScore) {
						bestHotScore = hs;
						bestHot = int(si);
					}
				}
			}
			continue;
		}
		// The rear-specialist leash is geometry and applied here so a refused
		// spot does not consume an engine probe; the trip risk is a PRICE, not
		// a veto, and ranks the spot below a safer one of equal yield.
		if (ecoOn && (sp.distance2D(Builder::gHomePos) > ecoLeash)) {
			++gMexEcoFar;
			DeadSpotSay(dw, sp, "ecofar");
			continue;
		}
		// The commander's leash likewise: a spot the election would refuse
		// (ComFar) must not be his one mex want, or the refusal's fallback
		// buys energy while the next spot in stands unclaimed.
		// ...but as the SAME price the two gates above are, when
		// apex_com_mex_price > 0: as a veto it is the largest single refuser
		// of extraction and it does not keep him alive. See docs/27.
		float comPen = 1.f;
		if (comm && (comF >= 1.f) && ComFar(sp)) {
			++gMexComFar;
			const float cp = ai.GetTunable("apex_com_mex_price",
					TUNE_COM_MEX_PRICE);
			if (cp <= 0.f) {
				DeadSpotSay(dw, sp, "comfar");
				continue;
			}
			comPen = cp;
		}
		const float walk = (speed > 1.f) ? (here.distance2D(sp) / speed) : 60.f;
		const float risk = gPtRisk[si];
		if (dw >= 0)
			DeadSpotSay(dw, sp, "priced risk=" + formatFloat(risk, "", 0, 2));
		if (risk >= 0.5f)
			++gSwPast;
		gPsCand.insertLast(int(si));
		// The commander's edge at a spot is the risk a constructor would carry
		// there that he does not: he keeps 1 - risk*comF and spares a con risk*(1 - comF).
		gPsScore.insertLast(comPen * inc * (comm ? (1.f + risk * (1.f - 2.f * comF)) : (1.f - risk))
				/ (walk + 1.f));
	}
	gSwCand = int(gPsCand.length());
	float bestCand = 0.f;
	for (uint i = 0; i < gPsScore.length(); ++i) {
		if (gPsScore[i] > bestCand)
			bestCand = gPsScore[i];
	}
	if ((bestHot >= 0) && (bestHotScore > bestCand))
		CallSupport(unit, bestHot, gAllSpotInc[bestHot] * incMul * MexWorthHorizon());
	Perf::Add("mx.scan", _tScan);
	const int tries = MexTries();
	for (int k = 0; k < tries; ++k) {
		int bi = -1;
		float bs = 0.f;
		for (uint i = 0; i < gPsScore.length(); ++i) {
			if (gPsScore[i] > bs) {
				bs = gPsScore[i];
				bi = int(i);
			}
		}
		if (bi < 0)
			break;
		const int sid = gPsCand[bi];
		gPsScore[bi] = -1.f;
		// Threat ceiling is generous on purpose: a contested spot is priced,
		// not hidden (the leaf era's FindOpenMexSpot went silent exactly under
		// attack).
		const int open = aiEconomyMgr.FindOpenMexSpot(unit, gAllSpots[sid], 99.f);
		if (open < 0)
			continue;
		if (LedgerFind(open) >= 0) {
			++gMexClaimed;
			continue;
		}
		// A hot road moves this hand to the next spot, not to no want.
		// PRICED, NOT HIDDEN, when apex_deathwalk_price is on: the comment
		// above this loop says a contested spot is priced, and TripRisk does
		// price it -- this gate hides the same spot the price would have
		// discounted, and on Glacier Pass it refuses 6-14 candidates a window
		// while `priced` reads 0.
		if (DeathWalk(unit, aiEconomyMgr.GetMexSpotPos(open))
			&& !(comm && (ComRaidF(unit, aiEconomyMgr.GetMexSpotPos(open)) < 1.f))) {
			++gMexDeathWalk;
			if (ai.GetTunable("apex_deathwalk_price", TUNE_DEATHWALK_PRICE) <= 0.f)
				continue;
		}
		return open;
	}
	return -1;
}

Want@ ProposeMex(CCircuitUnit@ unit)
{
	Want w;
	MexDiag();
	const int uid = int(unit.circuitDef.id);
	const AIFloat3 here = unit.GetPos(ai.frame);
	const double _tPk = Perf::T0();
	int spot = PickSpot(unit, here, Catalog::gSpeed[uid]);
	Perf::Add("mx.pick", _tPk);
	gMexOpen = (spot >= 0);
	if (spot < 0) {
		++gMexNoOpen;
		return w;
	}
	const AIFloat3 pos = aiEconomyMgr.GetMexSpotPos(spot);
	// Deadly for THIS walker; the spot itself stays open for a safer angle,
	// so gMexOpen is not cleared.
	if (DeathWalk(unit, pos) && !(unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask)
			&& (ComRaidF(unit, pos) < 1.f))) {
		++gMexDeathWalk;
		return w;
	}
	// The quiet rear stays home: no claim meaningfully closer to the enemy
	// than its own base depth (the mirror reference works pre-contact too).
	if (EcoFar(pos)) {
		++gMexEcoFar;
		gMexOpen = false;
		return w;
	}
	if (EcoQuiet() && (gEcoRefX >= 0.f)) {
		const float sdx = pos.x - gEcoRefX;
		const float sdz = pos.z - gEcoRefZ;
		const float hdx = Builder::gHomePos.x - gEcoRefX;
		const float hdz = Builder::gHomePos.z - gEcoRefZ;
		const float f = ai.GetTunable("apex_eco_reach_frac", TUNE_ECO_REACH_FRAC);
		if (sdx * sdx + sdz * sdz < (hdx * hdx + hdz * hdz) * f * f) {
			++gMexEcoQuiet;
			gMexOpen = false;
			return w;
		}
	}
	++gMexPriced;
	// The walker may not arrive: the stream is worth its survival share and
	// the trip costs the con's expected loss (TripRisk, coverage.as).
	const bool isCom = unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask);
	// For him only what there can kill him counts (ComRaidF).
	const float risk = TripRiskFrom(here, pos) * (isCom ? ComRaidF(unit, pos) : 1.f);
	gMexRiskSum += risk;
	// What the trip stakes: the hand's price -- or, for the commander,
	// everything we own, because his death is the game.
	const float conRiskM = risk * (isCom ? (gAssetsM + ArmyValue()) : Catalog::gCostM[uid]);
	const float spotIncome = aiEconomyMgr.GetMexSpotIncome(spot) * IncomeMult();
	const float speed = Catalog::gSpeed[uid];
	const float dist = here.distance2D(pos);
	gAvgWalkDist = 0.8f * gAvgWalkDist + 0.2f * dist;
	const float walkSec = (speed > 1.f) ? (dist / speed) : 60.f;
	// Every extractor this builder can place, priced; the VALUE picks the
	// def (a same-yield mex at 4.7x the cost lost the nomination it used to
	// win on raw extraction -- measured: armamex over armmex).
	const array<int>@ builds = Catalog::BuildsOf(uid);
	// The economy and this builder's effective lathe do not vary with which
	// extractor is being priced; both were re-derived per rung.
	const float mxPower = EcoPowerM();
	const float mxGrowK = ai.GetTunable("apex_mex_growth", TUNE_MEX_GROWTH);
	const float mxBP = EffBP(Catalog::gBuildPower[uid]);
	for (uint i = 0; i < builds.length(); ++i) {
		const int d = builds[i];
		if (!Catalog::gAvailable[d] || (Catalog::gExtractsM[d] <= 0.f))
			continue;
		Want c;
		// RELATIVE growth: a spot worth 3.4 at 16 m/s income is a 21% raise
		// to everything downstream (apexearth's arithmetic); the same spot
		// at 200 m/s is noise. The multiplier decays with wealth, so
		// expansion prioritizes itself exactly while we are behind.
		float gain = spotIncome * Catalog::gExtractsM[d];
		// The metal/s actually added, before any premium -- what the realize
		// share has to be asked about (see MRealizeShare in price.as).
		const float rawAddM = gain;
		// Share of TOTAL economic power, the same denominator the energy
		// premium uses -- see want_energy.as.
		gain *= 1.f + mxGrowK * gain / ((mxPower > gain) ? mxPower : gain);
		// Only what we expect to still be collecting: an unguarded spot keeps
		// its income for as long as it lives, and no longer.
		// Survival over the mex's own delivery time, the horizon energy
		// pays (TechSurvival), not a fixed 300 s: the longer horizon priced
		// a home mex at half of a solar standing beside it. The trip risk
		// is his distance-and-army-share model (docs/24 era directives).
		const float surv = StreamSurvivalOver(pos, walkSec + Catalog::BuildSecondsAt(d, mxBP));
		gain *= surv * (1.f - risk);
		// Metal we cannot spend scales nothing, so it is not priced as though
		// it did -- the twin of the share energy has always had to prove.
		gain *= MRealizeShare(rawAddM, walkSec + Catalog::BuildSecondsAt(d, mxBP));
		ValueOf(d, gain, walkSec, Catalog::gBuildPower[uid], c, true, conRiskM);
		// A spot with a recent loss near it is a rebuild: say what it is
		// priced at and why (sampled 10 s).
		// ...and any spot, sampled the same way, so a collapse in the value
		// names its factor.
		if (ai.frame >= gNextRebuildLog) {
			gNextRebuildLog = ai.frame + 10 * SECOND;
			AiLog(Factory::T() + ((LossRateAt(pos) > 0.f) ? "apex: rebuild " : "apex: mexprice ")
				+ unit.circuitDef.GetName() + " #" + unit.id
				+ " spot=" + int(pos.x) + "," + int(pos.z)
				+ " inc=" + formatFloat(spotIncome * Catalog::gExtractsM[d], "", 0, 2)
				+ " grow=" + formatFloat(1.f + mxGrowK * rawAddM / ((mxPower > rawAddM) ? mxPower : rawAddM), "", 0, 2)
				+ " real=" + formatFloat(MRealizeShare(rawAddM, walkSec + Catalog::BuildSecondsAt(d, mxBP)), "", 0, 2)
				+ " surv=" + formatFloat(surv, "", 0, 2)
				+ " cover=" + formatFloat(CoverAt(pos), "", 0, 0)
				+ " threat=" + formatFloat(ThreatAt(pos), "", 0, 0)
				+ " risk=" + formatFloat(risk, "", 0, 2)
				+ " walk=" + formatFloat(walkSec, "", 0, 0)
				+ " m=" + formatFloat(c.mCost, "", 0, 0)
				+ "(M" + formatFloat(Catalog::gCostM[d] * MCostScale(), "", 0, 0)
				+ "+E" + formatFloat(Catalog::gCostE[d] * EPriceCostAt(c.buildSec, Catalog::gCostE[d]), "", 0, 0)
				+ "+A" + Catalog::gAreaCells[d] + ")"
				+ " t=" + formatFloat(c.tCost, "", 0, 0)
				+ "(walk" + formatFloat(walkSec * WalkRate(Catalog::gBuildPower[uid]), "", 0, 0)
				+ "+build" + formatFloat(c.buildSec * Wage(), "", 0, 0)
				+ "+risk" + formatFloat(conRiskM, "", 0, 0)
				+ "+late" + formatFloat(gain * walkSec, "", 0, 0) + ")"
				+ " v=" + formatFloat(c.value * 1000.f, "", 0, 2));
		}
		if (c.value > w.value) {
			w = c;
			w.kind = WK_MEX;
			@w.def = Catalog::Def(d);
			w.pos = pos;
			w.spotId = spot;
			// The RAW yield. Storing the premium- and survival-scaled gain
			// here made SpotM -- and through it OpenSpotStream and every
			// build's displacement charge -- a number that is not a yield.
			gLastSpotM = spotIncome * Catalog::gExtractsM[d];
		}
	}
	return w;
}


}  // namespace Market
