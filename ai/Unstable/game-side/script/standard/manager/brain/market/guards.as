namespace Market {
// A hard stall re-opens held decisions: abort non-energy builds (the
// commander first), as many as the shortfall needs, so their holders fall
// back into the market,
// where the stall-priced solar now wins. Held tasks are otherwise never
// re-asked -- the engine stops re-electing once a builder is in range
// (apexearth 2026-08-23: "interrupt that commander's action and switch to
// make a basic solar").
int gNextStallSweep = 211;   // phase offset -- see AiUpdate lockstep note

// Who the market sent to assist what. A guard on an IDLE factory is a
// locked builder doing nothing while mexes sit open (apexearth 2026-08-23);
// the sweep releases them the moment the boss has no work.
//
// IDS BESIDE THE HANDLES, because CCircuitUnit is NOCOUNT: the engine does NOT
// null a stored handle when it destroys the unit, so `b is null` cannot detect
// a dead boss and GuardSweep's next line -- b.circuitDef.IsMobile() -- reads
// freed memory. Measured 2026-08-31, watch-army40: the commander died at frame
// 27571 and the AI took an access violation (0xc0000005) inside SkirmishAI.dll
// at frame 27600, one AiUpdate later. Nothing pruned these two arrays; every
// other handle store in the market is dropped by Market::NoteDead and this pair
// was simply never added to it.
//
// It had never fired before because nothing had ever died: `COMMANDER LOST`
// appears zero times in every run of this session before the army target was
// switched on.
array<CCircuitUnit@> gGuardUnit;
array<CCircuitUnit@> gGuardBoss;
array<Id> gGuardUId;
array<Id> gGuardBId;
int gGuardStamp = 0;   // bumped on every insert and removal of the ledger
void GuardNote(CCircuitUnit@ u, CCircuitUnit@ boss)
{
	if ((u is null) || (boss is null))
		return;
	gGuardUnit.insertLast(u);
	gGuardBoss.insertLast(boss);
	gGuardUId.insertLast(u.id);
	gGuardBId.insertLast(boss.id);
	++gGuardStamp;
}

// How many guards follow the workers of this job. The assist want counts a
// job's crew to divide the return; the guards it had already sent were not
// in that count, so every asker saw a lonely job (apexearth 2026-09-14: "we
// have a dude walking around to make a single nano turret and he's followed
// by like 30 dollars").
int GuardsOnJob(IUnitTask@ t)
{
	if (t is null)
		return 0;
	array<CCircuitUnit@>@ crew = t.GetUnits();
	if (crew is null)
		return 0;
	int n = 0;
	for (uint c = 0; c < crew.length(); ++c) {
		if (crew[c] is null)
			continue;
		const Id bid = crew[c].id;
		for (uint g = 0; g < gGuardBId.length(); ++g) {
			if (gGuardBId[g] == bid)
				++n;
		}
	}
	return n;
}

// Either party dying drops the pair -- before any sweep can dereference it.
void GuardGone(Id id)
{
	for (uint i = 0; i < gGuardUId.length(); ) {
		if ((gGuardUId[i] == id) || (gGuardBId[i] == id)) {
			gGuardUnit.removeAt(i);
			gGuardBoss.removeAt(i);
			gGuardUId.removeAt(i);
			gGuardBId.removeAt(i);
			++gGuardStamp;
			continue;
		}
		++i;
	}
}
// Constructor escorts (apexearth 2026-08-23: "we need to escort our
// constructors with at least 1 grunt or better"). The market knows which
// workers are exposed; the military election asks here before pooling a
// unit. One escort per worker; entries drop when either party dies or the
// escort's task ends.
array<Id> gEscWorker;
array<Id> gEscUnit;
// The escort's def, kept beside the pairing so the army model can tell what is
// standing from what is committed -- there is no unit-by-id lookup bound.
array<int> gEscDef;
// ESCORT METAL PER WORKER, kept as the pairing changes rather than re-summed.
// The sum ran once per exposed worker on EVERY military election, so its cost
// was (workers) x (pairs) and both fleets grow all game. Same 32k id table as
// the enemy-cost memo above; an id outside it falls back to the walk, which is
// the same answer.
array<float> gEscHaveM(32001, 0.f);
array<int> gEscHaveN(32001, 0);

bool EscIdOk(Id id)
{
	return (int(id) >= 0) && (int(id) < int(gEscHaveN.length()));
}

float EscortMetalOn(Id wid)
{
	if (EscIdOk(wid))
		return gEscHaveM[int(wid)];
	float m = 0.f;
	for (uint e = 0; e < gEscWorker.length(); ++e) {
		if ((gEscWorker[e] == wid) && (e < gEscDef.length()))
			m += Catalog::gCostM[gEscDef[e]];
	}
	return m;
}

// Guards an exposed constructor is owed (his 2026-10-04: "more escorts on our
// constructors so they don't die so often"); a worker short of them still counts
// as exposed, so the escort floor keeps producing.
float EscortsPerCon()
{
	const float n = ai.GetTunable("apex_escorts_per_con", TUNE_ESCORTS_PER_CON);
	return (n > 1.f) ? n : 1.f;
}

bool EscortedWorker(Id wid)
{
	if (EscIdOk(wid))
		return gEscHaveN[int(wid)] >= int(EscortsPerCon());
	for (uint e = 0; e < gEscWorker.length(); ++e) {
		if (gEscWorker[e] == wid)
			return true;
	}
	return false;
}

int gEscDiagAt = 0;
// GetEnemyCostAt is an engine sweep of the enemy registry, and EscortNeeded ran
// one per exposed worker on EVERY military election -- several elections land
// in the same frame, where neither the registry nor the worker's position can
// have moved. Same Spring 32k id cap as the other id-keyed tables.
array<int> gEnMFrame(32001, -30000);
array<float> gEnMVal(32001, 0.f);
float WorkerEnemyM(CCircuitUnit@ wkr, float r)
{
	const int id = int(wkr.id);
	if ((id < 0) || (id >= int(gEnMFrame.length())))
		return ai.GetEnemyCostAt(wkr.GetPos(ai.frame), r);
	if (gEnMFrame[id] == ai.frame)
		return gEnMVal[id];
	gEnMFrame[id] = ai.frame;
	gEnMVal[id] = ai.GetEnemyCostAt(wkr.GetPos(ai.frame), r);
	return gEnMVal[id];
}

// THEIR BIGGEST WALKING GROUP, in mobile metal, held as a peak that halves over
// apex_seen_halflife: a pack seen once and then lost in fog has not gone away.
float gRaidMassPk = 0.f;
int gRaidMassAt = -1;
float FoeRaidMassM()
{
	if (gRaidMassAt == ai.frame)
		return gRaidMassPk;
	RiskFill();
	float top = 0.f;
	for (uint g = 0; g < gRkApM.length(); ++g) {
		if (gRkApM[g] > top)
			top = gRkApM[g];
	}
	const float hl = ai.GetTunable("apex_seen_halflife", TUNE_SEEN_HALFLIFE);
	const int dt = (gRaidMassAt < 0) ? 0 : (ai.frame - gRaidMassAt);
	if ((hl > 0.f) && (dt > 0))
		gRaidMassPk *= pow(0.5f, (float(dt) / float(SECOND)) / hl);
	if (top > gRaidMassPk)
		gRaidMassPk = top;
	gRaidMassAt = ai.frame;
	return gRaidMassPk;
}

// SPREAD ONLY WHILE THE THREAT IS SPREAD (apexearth 2026-10-05: "if all of our
// escorts are spread out and we die to their massed raiders one by one ... you
// kind of have to meet mass for mass"). One post is what a single worker is
// owed; once their biggest group outguns a post, every post loses alone, so
// the escorts gather on one worker until they meet the group.
bool EscortsPool(float postM)
{
	const float g = FoeRaidMassM();
	if ((g <= 1.f) || (StrRatio(g, postM) <= 1.f))
		return false;
	// ...only while our raiders together could meet it; short of the mass,
	// each exposed con keeps its own post.
	const float ours = RoleValue(int(Unit::Role::RAIDER.type)) + RoleCommitted(int(Unit::Role::RAIDER.type));
	return StrRatio(g, ours) <= 1.f;
}

// What one worker's escort must hold: the enemy that can reach it, floored by
// its exposure's share of a post -- and, while they mass, by their group.
float EscortOwedM(CCircuitUnit@ wkr, float expo, float unitM, float expoR, bool air)
{
	float needM = WorkerEnemyM(wkr, (expoR > 1.f) ? expoR : 1200.f);
	const float postM = unitM * EscortsPerCon();
	const float floorM = expo * postM;
	if (floorM > needM)
		needM = floorM;
	if (!air && (expo > 0.f) && EscortsPool(postM)) {
		const float g = FoeRaidMassM();
		if (g > needM)
			needM = g;
	}
	return needM * gEscMul;   // the escort net's strength (escnet.as)
}

int gEscPooled = 0;
int gEscSpread = 0;
CCircuitUnit@ EscortNeeded(CCircuitUnit@ mil)
{
	if (mil is null)
		return null;
	// Three at most, stock's own cap (apexearth 2026-10-01, approving it; 09-13:
	// "We have so many escorts in the base it is ludicrous"). A third to half
	// of each army stood on escort duty in his 8v8.
	if (gEscWorker.length() >= EscortCap())
		return null;
	const float expoR = ai.GetTunable("apex_expose_r", TUNE_EXPOSE_R);
	const float mineM = Catalog::gCostM[int(mil.circuitDef.id)];
	const bool air = Catalog::gFlyer[int(mil.circuitDef.id)];
	// Pooled, the escort joins the worker that already holds the most escort,
	// so one mass grows instead of several pairs; spread, the first in need.
	const bool pooled = !air && EscortsPool(mineM * EscortsPerCon());
	CCircuitUnit@ pick = null;
	float pickHave = -1.f;
	float pickExpo = -1.f;
	for (uint i = 0; i < gWorkers.length(); ++i) {
		CCircuitUnit@ wkr = gWorkers[i];
		if (!EscortableWorker(wkr, air))
			continue;
		const float expo = WorkerExposure(wkr);
		if (expo <= 0.f)
			continue;
		// ESCORT SCALES WITH HOW EXPOSED THE WORKER IS. apexearth
		// 2026-08-30: "If we're too far forward an entire squad or two should
		// be escorting us." The demand is METAL: the enemy value that can
		// reach the worker, floored by the exposure's share of one escort so
		// a forward worker is covered before contact rather than after it.
		// A unit takes the duty when at least half of it is still wanted.
		const float haveM = EscortMetalOn(wkr.id);
		const float needM = EscortOwedM(wkr, expo, mineM, expoR, air);
		if (needM - haveM < 0.5f * mineM)
			continue;
		// Only a NEARBY unit takes the duty: a cross-map death march
		// delivered 16 of 63 army losses as lone escorts (ladder autopsy).
		// A far worker's escort comes from the next unit produced closer,
		// or from its own raider demand (EscortShortfall).
		const float ms = Catalog::gSpeed[int(mil.circuitDef.id)];
		const bool far = (ms > 1.f)
			&& (mil.GetPos(ai.frame).distance2D(wkr.GetPos(ai.frame)) / ms > 45.f);
		if (!pooled) {
			if (far)
				continue;
			@pick = wkr;
			break;
		}
		// Pooled, the mass is chosen first and the walk asked of it alone: a
		// nearer worker would start a second pair the sweep then dissolves.
		if ((haveM > pickHave) || ((haveM == pickHave) && (expo > pickExpo))) {
			if (far)
				@pick = null;
			else
				@pick = wkr;
			pickHave = haveM;
			pickExpo = expo;
		}
	}
	if (pick !is null) {
		CCircuitUnit@ wkr = pick;
		if (pooled)
			++gEscPooled;
		else
			++gEscSpread;
		gEscWorker.insertLast(wkr.id);
		gEscUnit.insertLast(mil.id);
		gEscDef.insertLast(int(mil.circuitDef.id));
		if (EscIdOk(wkr.id)) {
			gEscHaveM[int(wkr.id)] += mineM;
			++gEscHaveN[int(wkr.id)];
		}
		return wkr;
	}
	return null;
}
// Escorts ORDERED but not yet standing beside anyone. An escort queued behind
// a busy line took 77 seconds to arrive, so a time-decayed order ledger
// expires and the floor re-orders. The sent-ledger alone is the answer: it
// holds every order until the unit is finished, so adding CountQueued to it
// would count the same escort twice.
int EscortInFlight(CCircuitDef@ d)
{
	if (d is null)
		return 0;
	int n = 0;
	for (uint i = 0; i < Brain::gFQFac.length(); ++i) {
		CCircuitUnit@ f = Brain::gFQFac[i];
		if (f is null)
			continue;
		n += Brain::PendCount(int(i), d);
	}
	return n;
}

// WHAT MAY ESCORT AT ALL (apexearth 2026-08-25: "we want fast or tough units
// on escort, rocket bots die in a 1v1 vs a pawn/grunt so not good protection
// vs raiders"). What kills a constructor is something fast in its face, so an
// escort has to either CATCH it or SURVIVE it -- above the ground field's own
// average on one axis or the other. A Rocketeer is neither, and its role tag
// is `assault`, which is why a SKIRM/ARTY filter never caught it.
float gEscMeanSpd = -1.f;
// The same field's mean POWER. apexearth 2026-09-07: "we are using rascals as
// escorts and they really suck at it. Need incisors if you want a good enough
// vehicle escort." The two tests below ask whether an escort can CATCH what
// comes for a worker or SURVIVE it -- neither asks whether it can KILL it, so
// a Rascal (26 metal, Light Scout Vehicle) qualifies on speed alone and then
// loses the fight it caught. Measured before it is enforced: see the
// `escort-field` census.
float gEscMeanPow = -1.f;
void EscortMeans()
{
	if (gEscMeanSpd > 0.f)
		return;   // frame-dependent availability: never cache a mean over nothing
	float sp = 0.f;
	float pw = 0.f;
	int n = 0;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!Catalog::gAvailable[d] || !LineCombat(d) || Catalog::gFlyer[d])
			continue;
		sp += Catalog::gSpeed[d];
		pw += Catalog::gPower[d];
		++n;
	}
	gEscMeanSpd = (n > 0) ? (sp / float(n)) : -1.f;
	gEscMeanPow = (n > 0) ? (pw / float(n)) : -1.f;
}


// The air half: a fighter (an armed flyer that shoots up) escorts an air con.
bool FighterEscortWorthy(int di)
{
	return Catalog::gAvailable[di] && Catalog::gMobile[di] && Catalog::gFlyer[di]
		&& !Catalog::gBuilder[di] && !Catalog::gKamikaze[di]
		&& (Catalog::gAirT[di] > 0.01f) && (Catalog::gCostM[di] > 0.f)
		&& !Air::IsBomberDef(di);
}

// The median unit strength of the enemy's mobile ground army we know of,
// counted per def over the map; -1 before any is known. 30 s clock.
// The strongest unit our standing plants can make that could escort a con:
// armed ground, keeps pace with our cons, under the escort cost cap, not
// indirect fire. 30 s clock.
float gOwnEscPow = -1.f;
int gOwnEscAt = -100000;
float OwnEscortPowBest()
{
	if (ai.frame - gOwnEscAt < 30 * SECOND)
		return gOwnEscPow;
	gOwnEscAt = ai.frame;
	gOwnEscPow = -1.f;
	const float conSpd = Military::NrConSpeed();
	const float capM = ai.GetTunable("apex_escort_max_cost", TUNE_ESCORT_MAX_COST);
	for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
		CCircuitUnit@ f = Factory::gFacUnits[fi];
		if ((f is null) || (f.circuitDef is null))
			continue;
		const array<int>@ bo = Catalog::BuildsOf(int(f.circuitDef.id));
		for (uint k = 0; (bo !is null) && (k < bo.length()); ++k) {
			const int d = bo[k];
			if (!Catalog::gAvailable[d] || !Catalog::gMobile[d] || Catalog::gFlyer[d] || Catalog::gBuilder[d]
				|| Catalog::gKamikaze[d] || (Catalog::gPower[d] <= 1.f) || (Catalog::gCostM[d] > capM)
				|| (Catalog::gSpeed[d] < conSpd))
				continue;
			CCircuitDef@ cd = Catalog::Def(d);
			if (cd.IsRoleAny(Unit::Role::SKIRM.mask) || cd.IsRoleAny(Unit::Role::ARTY.mask))
				continue;
			if (Catalog::gPower[d] > gOwnEscPow)
				gOwnEscPow = Catalog::gPower[d];
		}
	}
	return gOwnEscPow;
}

array<int> gFpmCnt;
float gFoePowMed = -1.f;
int gFoePowAt = -100000;
float FoeGroundPowMedian()
{
	if (ai.frame - gFoePowAt < 30 * SECOND)
		return gFoePowMed;
	gFoePowAt = ai.frame;
	// One pass over the enemies we know, tallied by def (a pass per def was a
	// thousand engine scans in one update).
	if (int(gFpmCnt.length()) <= Catalog::gDefCount)
		gFpmCnt.resize(Catalog::gDefCount + 1);
	array<int> seenDefs;
	int tot = 0;
	const int total = aiEnemyMgr.GetEnemyUnitTotal();
	for (int i = 0; i < total; ++i) {
		const int d = aiEnemyMgr.GetEnemyUnitDefAt(i);
		if ((d < 1) || (d > Catalog::gDefCount) || !Catalog::gMobile[d] || Catalog::gFlyer[d]
			|| Catalog::gBuilder[d] || (Catalog::gPower[d] <= 1.f))
			continue;
		if (gFpmCnt[d] == 0)
			seenDefs.insertLast(d);
		++gFpmCnt[d];
		++tot;
	}
	array<float> pw;
	array<int> n;
	for (uint k = 0; k < seenDefs.length(); ++k) {
		pw.insertLast(Catalog::gPower[seenDefs[k]]);
		n.insertLast(gFpmCnt[seenDefs[k]]);
		gFpmCnt[seenDefs[k]] = 0;
	}
	gFoePowMed = -1.f;
	if (tot <= 0)
		return gFoePowMed;
	int seen = 0;
	while (seen * 2 < tot) {
		int lo = 0;
		for (uint i = 1; i < pw.length(); ++i)
			if (pw[i] < pw[lo])
				lo = int(i);
		seen += n[lo];
		gFoePowMed = pw[lo];
		pw.removeAt(lo);
		n.removeAt(lo);
	}
	return gFoePowMed;
}

bool EscortWorthy(int di)
{
	if (!Catalog::gAvailable[di] || !Catalog::gMobile[di] || Catalog::gBuilder[di]
		|| Catalog::gKamikaze[di] || Catalog::gFlyer[di]
		|| (Catalog::gPower[di] <= 1.f) || (Catalog::gCostM[di] <= 0.f))
		return false;
	if (Catalog::gCostM[di]
			> ai.GetTunable("apex_escort_max_cost", TUNE_ESCORT_MAX_COST))
		return false;
	if (ReachDead(di))
		return false;
	CCircuitDef@ cd = Catalog::Def(di);
	// An escort beats most of what comes for a con: at least the median
	// strength of the enemy ground units we know of, capped at the strongest
	// escort our plants can make, so outclassed we still field our best.
	const float bestOwn = OwnEscortPowBest();
	float foeMed = FoeGroundPowMedian();
	if ((bestOwn > 0.f) && ((foeMed <= 0.f) || (foeMed > bestOwn)))
		foeMed = bestOwn;
	if ((foeMed > 0.f) ? (Catalog::gPower[di] < foeMed) : Military::IsFodder(cd))
		return false;
	if (cd.IsRoleAny(Unit::Role::SKIRM.mask)
		|| cd.IsRoleAny(Unit::Role::ARTY.mask))
		return false;   // indirect fire cannot answer what kills cons
	EscortMeans();
	if (gEscMeanSpd <= 0.f)
		return false;
	// Strong enough (above), it need only keep pace with the cons it guards.
	if ((foeMed > 0.f) && (Catalog::gSpeed[di] >= Military::NrConSpeed()))
		return true;
	// FAST: above the ground field's own mean speed, so it can stay with a
	// worker and catch what comes for it.
	if (Catalog::gSpeed[di] >= gEscMeanSpd
			* ai.GetTunable("apex_escort_speed", TUNE_ESCORT_SPEED))
		return true;
	// TOUGH: a RIOT unit, which is the game's own name for the answer to
	// raiders -- a health bar cannot express this, because the tanky cheap
	// bot at T1 IS the rocket bot (Rocketeer 720hp against a Pawn's 370).
	return cd.IsRoleAny(Unit::Role::RIOT.mask);
}

// WHAT THE ESCORT FILTER IS ACTUALLY CHOOSING FROM, once, in full. A bar set
// from a mean is only as good as the field it averages, and the field is not
// knowable from the source -- it depends on which factory is standing. Printed
// before anything is enforced so the bar can be read off real data instead of
// guessed (docs/25: the silent no-op is this repo's only real bug class).
bool gEscFieldLogged = false;
void EscortFieldCensus()
{
	if (gEscFieldLogged)
		return;
	EscortMeans();
	if (gEscMeanSpd <= 0.f)
		return;
	gEscFieldLogged = true;
	AiLog("apex: escort-field t=" + ai.teamId
		+ " spdBar=" + formatFloat(gEscMeanSpd, "", 0, 1)
		+ " powBar=" + formatFloat(gEscMeanPow, "", 0, 1));
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!Catalog::gAvailable[d] || !LineCombat(d) || Catalog::gFlyer[d])
			continue;
		CCircuitDef@ cd = Catalog::Def(d);
		AiLog("apex: escort-cand t=" + ai.teamId
			+ " " + ((cd is null) ? ("def" + d) : cd.GetName())
			+ " cost=" + formatFloat(Catalog::gCostM[d], "", 0, 0)
			+ " spd=" + formatFloat(Catalog::gSpeed[d], "", 0, 1)
			+ " pow=" + formatFloat(Catalog::gPower[d], "", 0, 1)
			+ " hp=" + formatFloat(Catalog::gHealth[d], "", 0, 0)
			+ " worthy=" + (EscortWorthy(d) ? 1 : 0));
	}
}

// A CONSTRUCTOR STANDING WITHOUT A GUARD IS DEMAND FOR ONE, NOT A BID
// (apexearth 2026-08-25: "make producing guards a high priority when we have
// a constructor with no guard"). The raider role target already carries the
// metal at risk, but a role weight is a share of a draw -- it can lose for
// minutes while the con it would have saved dies. This is the floor: the line
// orders one cheap escort now, ahead of the proportional draw.
// WHAT AN ESCORT IS WORTH, as a rate, so it can be priced instead of decreed.
//
// apexearth's own math, already stated for EscortMetalAtRisk: "a con outside of
// our home safe territory immediately has 0 value and making the cheap pawn
// would add the pawns value + the constructor value back." So the gain of ONE
// escort is the share of that write-off it prevents -- the exposed metal
// divided among the workers still unescorted -- collected over the same fill
// horizon every other army want amortizes against.
//
// This replaces a FLOOR that returned before the auction ran. The floor could
// not be out-ranked by anything, however cheap the alternative or dear the
// escort, which is the shape docs/23-the-plan.md forbids: "a choice that should
// not happen is one whose ETA is worse", not one a rule forbids.
float EscortGain(float fillS)
{
	const int need = EscortShortfall();
	if (need <= 0)
		return 0.f;
	const float risk = EscortMetalAtRisk();
	if (risk <= 0.f)
		return 0.f;
	const float horizon = (fillS > 1.f) ? fillS : 180.f;
	return (risk / float(need)) / horizon;
}

void EscortDiag()
{
	if (ai.frame < gEscDiagAt)
		return;
	gEscDiagAt = ai.frame + 60 * SECOND;
	EscortMeans();
	AiLog("apex: escort-diag t=" + ai.teamId
		+ " workers=" + gWorkers.length()
		+ " short=" + gExpoN
		+ " paired=" + gEscWorker.length()
		+ " risk=" + formatFloat(gExpoM, "", 0, 0)
		// What escort duty has taken out of the free army, and what is
		// left standing for everything else.
		+ " committed=" + formatFloat(RoleCommitted(int(Unit::Role::RAIDER.type)), "", 0, 0)
		+ " freeRaid=" + formatFloat(RoleValue(int(Unit::Role::RAIDER.type)), "", 0, 0)
		+ " spdBar=" + formatFloat(gEscMeanSpd, "", 0, 0)
		+ " top=" + formatFloat(gExpoMax, "", 0, 2) + " " + gExpoMaxWhy
		+ " released=" + gEscReleased
		+ " foeMass=" + formatFloat(FoeRaidMassM(), "", 0, 0)
		+ " pooled=" + gEscPooled + " spread=" + gEscSpread + " foePowMed=" + formatFloat(gFoePowMed, "", 0, 1) + " ownBest=" + formatFloat(gOwnEscPow, "", 0, 1));
}

// AN ESCORT THE WORKER NO LONGER NEEDS GOES BACK TO THE ARMY. Pairings only
// ever grew: a worker that met an enemy army kept every escort it was given
// after the enemy left and after it walked home, and in his 8v8 (10-01) a third
// to half of each army followed constructors around our own base while the
// enemy's stood at the front. The need is EscortNeeded's own: the enemy metal
// that can reach the worker, floored by its exposure.
int gEscReleased = 0;
void EscortSweep()
{
	const float expoR = ai.GetTunable("apex_expose_r", TUNE_EXPOSE_R);
	// Pooled, the pairs left on other workers from the spread phase go back to
	// the election, which sends them to the worker holding the mass.
	Id anchor = Id(-1);
	float anchorM = 0.f;
	for (uint e = 0; e < gEscWorker.length(); ++e) {
		if ((e >= gEscDef.length()) || Catalog::gFlyer[gEscDef[e]])
			continue;
		const float m = EscortMetalOn(gEscWorker[e]);
		if (m > anchorM) {
			anchorM = m;
			anchor = gEscWorker[e];
		}
	}
	for (int e = int(gEscWorker.length()) - 1; e >= 0; --e) {
		if (uint(e) >= gEscWorker.length())
			continue;
		const Id wid = gEscWorker[uint(e)];
		const Id uid = gEscUnit[uint(e)];
		CCircuitUnit@ w = ai.GetTeamUnit(wid);
		CCircuitUnit@ u = ai.GetTeamUnit(uid);
		if (u is null) {
			EscortGone(uid);
			continue;
		}
		const float cost = Catalog::gCostM[gEscDef[uint(e)]];
		const bool airE = Catalog::gFlyer[gEscDef[uint(e)]];
		const bool offMass = !airE && (w !is null) && (wid != anchor)
				&& (EscortMetalOn(wid) < anchorM)
				&& (anchorM + cost <= FoeRaidMassM())   // the mass still has room for it
				&& EscortsPool(cost * EscortsPerCon());
		if ((w !is null) && !offMass) {
			// The owed metal EscortNeeded paired against: a floor of one escort
			// here released the second of every pair the moment it arrived.
			const float need = EscortOwedM(w, WorkerExposure(w), cost, expoR,
					Catalog::gFlyer[gEscDef[uint(e)]]);
			if (EscortMetalOn(wid) - cost < need)
				continue;   // still wanted
		}
		IUnitTask@ t = u.task;
		EscortGone(uid);
		if ((t !is null) && (t.GetType() == Task::Type::FIGHTER)
			&& (t.GetFightType() == Task::FightType::GUARD))
			t.RemoveUnit(u);
		++gEscReleased;
	}
}

void EscortGone(Id id)
{
	for (uint e = 0; e < gEscWorker.length(); ) {
		if ((gEscWorker[e] == id) || (gEscUnit[e] == id)) {
			const Id w = gEscWorker[e];
			if (EscIdOk(w) && (e < gEscDef.length())) {
				gEscHaveM[int(w)] -= Catalog::gCostM[gEscDef[e]];
				if (gEscHaveM[int(w)] < 0.f)
					gEscHaveM[int(w)] = 0.f;
				--gEscHaveN[int(w)];
				if (gEscHaveN[int(w)] < 0)
					gEscHaveN[int(w)] = 0;
			}
			gEscWorker.removeAt(e);
			gEscUnit.removeAt(e);
			gEscDef.removeAt(e);
			continue;
		}
		++e;
	}
	ClearSupport(id);
}

// Support, then build: a constructor whose best mex spot is hot hands that
// spot to the army's target choice (C++ CAttackTask::FindTarget), which prices
// the enemies covering it at the spot's worth. Once they are gone the spot is
// no longer hot and is picked like any other, its constructor escorted as any
// outside the base is. One spot at a time, held until it is claimed, cools,
// or its constructor dies -- never moved by re-election, so the army is not
// sent one place and then another, and the fight logic is nudged, not led.
array<Id> gSupWorker;
array<int> gSupSpot;
array<float> gSupWorth;
bool gSupDirty = false;
int gSupCalls = 0;
int gSupDone = 0;

void CallSupport(CCircuitUnit@ wkr, int si, float worth)
{
	if ((wkr is null) || (gSupWorker.length() > 0))
		return;
	++gSupCalls;
	AiLog("apex: support call t=" + ai.teamId + " spot=" + si
		+ " at=" + int(gAllSpots[si].x) + "," + int(gAllSpots[si].z) + " worth=" + int(worth));
	gSupWorker.insertLast(wkr.id);
	gSupSpot.insertLast(si);
	gSupWorth.insertLast(worth);
	gSupDirty = true;
}

void ClearSupport(Id wid)
{
	for (uint s = 0; s < gSupWorker.length(); ++s) {
		if (gSupWorker[s] == wid) {
			AiLog("apex: support done t=" + ai.teamId + " spot=" + gSupSpot[s] + " why=lost");
			gSupWorker.removeAt(s);
			gSupSpot.removeAt(s);
			gSupWorth.removeAt(s);
			gSupDirty = true;
			return;
		}
	}
}

void SupportSweep()
{
	for (int s = int(gSupWorker.length()) - 1; s >= 0; --s) {
		const int si = gSupSpot[s];
		const bool claimed = LedgerFind(si) >= 0;
		if (claimed || !SpotHot(gAllSpots[si])) {
			AiLog("apex: support done t=" + ai.teamId + " spot=" + si
				+ " at=" + int(gAllSpots[si].x) + "," + int(gAllSpots[si].z)
				+ " why=" + (claimed ? "claimed" : "cooled"));
			gSupWorker.removeAt(s);
			gSupSpot.removeAt(s);
			gSupWorth.removeAt(s);
			++gSupDone;
			gSupDirty = true;
		}
	}
	// The army is not given these spots: the nudge pulled every squad onto the
	// one target beside a spot. Opportunism alone (his 09-30): the spot is
	// taken when the fighting clears it.
	if (!gSupDirty)
		return;
	gSupDirty = false;
	aiMilitaryMgr.ClearSupportSpots();
}

bool SupportFree()
{
	return gSupWorker.length() == 0;
}

float SupportWorth()
{
	float w = 0.f;
	for (uint s = 0; s < gSupWorth.length(); ++s)
		w += gSupWorth[s];
	return w;
}

int gComLabLeft = 0;   // commander guard stints at a lab ended because metal ran out
void GuardSweep()
{
	for (uint i = 0; i < gGuardUnit.length(); ) {
		CCircuitUnit@ u = gGuardUnit[i];
		CCircuitUnit@ b = gGuardBoss[i];
		bool drop = (u is null) || (b is null) || (u.task is null)
			|| (int(u.task.GetBuildType()) != int(Task::BuildType::GUARD));
		if (!drop) {
			// A factory boss with nothing queued (and nothing in flight) is
			// idle: release the guard into the market.
			const bool bossIsFac = !b.circuitDef.IsMobile();
			// (a frame being raised queues nothing either)
			if (bossIsFac && (b.CountQueued(null) == 0) && !ComFramedById(b.id)) {
				u.task.Abort();
				drop = true;
			}
			// Out of metal the commander leaves the lab to get more (his 2026-10-05).
			if (!drop && bossIsFac && u.circuitDef.IsRoleAny(Unit::Role::COMM.mask)
				&& MetalShort(0.f)) {
				u.task.Abort();
				drop = true;
				++gComLabLeft;
			}
			// A mobile boss that stopped building releases its guards too.
			if (!bossIsFac && ((b.task is null)
					|| (b.task.GetType() != Task::Type::BUILDER))) {
				u.task.Abort();
				drop = true;
			}
		}
		if (drop) {
			gGuardUnit.removeAt(i);
			gGuardBoss.removeAt(i);
			gGuardUId.removeAt(i);
			gGuardBId.removeAt(i);
			++gGuardStamp;
			continue;
		}
		++i;
	}
}

// A PAUSE HIDES THE STALL FROM THE ONLY TEST THAT LOOKS FOR IT. pull > income
// is what a stall looks like from the outside, but the moment the throttle
// parks the fleet, pull falls BELOW income while the bank sits empty --
// measured live: cur=203/1250 (16%), income 102, pull 76, and every gate here
// read "healthy" while nothing could be built (apexearth: "there is some logic
// which puts units in 'wait' mode when e gets low, i wonder if the e-stall
// isn't triggering because of the pausing"). The drained bank is the stall
// whatever the pull says -- isEnergyStalling is the engine's own reading of it
// (empty bank, or income under pull with the bank low), and it is the same
// signal that pauses the work, so our answer now fires exactly when the
// throttle engages instead of never.
// METAL FIRST (apexearth 2026-09-19): while the metal unlock -- an advanced
// plant, or the first mex upgrade -- is in flight and the metal feed is short
// of what is pulling on it, the plants make no army: a T2 lab crawled for
// three minutes at 26-50 metal/s beside a T1 lab that put 1,800 metal into
// Pawns. Feed-bound, not hand-bound, so the answer is fewer sinks, not more
// hands.
int  gMetalPathAt = -1;
bool gMetalPathVal = false;
int  gMetalPathTicks = 0;
int  gNextMetalPathLog = 0;
bool MetalPathStarved()
{
	if (gMetalPathAt == ai.frame)
		return gMetalPathVal;
	gMetalPathAt = ai.frame;
	gMetalPathVal = false;
	bool unlock = AdvPlantInFlight();
	if (!unlock && (MohoStanding() == 0)) {
		for (uint li = 0; li < Requests::gLive.length(); ++li) {
			IUnitTask@ lt = Requests::gLive[li];
			if ((lt !is null) && !lt.IsDead()
				&& (lt.GetBuildType() == Task::BuildType::MEXUP)) {
				unlock = true;
				break;
			}
		}
	}
	if (!unlock)
		return false;
	const float mInc = Eco::MInc();
	const float mPull = Eco::MPull();
	const float mCur = Eco::MCur();
	const float h = EGenBuildSeconds();
	const float share = (mPull > 0.01f) ? ((mInc + mCur / ((h > 1.f) ? h : 1.f)) / mPull) : 9.f;
	gMetalPathVal = (share < 1.f);
	if (gMetalPathVal) {
		++gMetalPathTicks;
		if (ai.frame >= gNextMetalPathLog) {
			gNextMetalPathLog = ai.frame + 30 * SECOND;
			AiLog(Factory::T() + "apex: metal-path starved share="
				+ formatFloat(share, "", 0, 2) + " inc=" + formatFloat(mInc, "", 0, 0)
				+ " pull=" + formatFloat(mPull, "", 0, 0)
				+ " advPlant=" + (AdvPlantInFlight() ? 1 : 0)
				+ " mohos=" + MohoStanding()
				+ " ticks=" + gMetalPathTicks);
		}
	}
	return gMetalPathVal;
}

// The metal feed with no unlock attached [m/s]: income plus the bank over the
// stall horizon, less what is asked of it. Smoothed as SlackFrac is, because
// pull drops to nothing between jobs.
float gMFreeEma = 0.f;
int gMFreeAt = -999999;
float MetalFreeRate()
{
	if (ai.frame - gMFreeAt >= SECOND) {
		const bool first = (gMFreeAt < 0);
		gMFreeAt = ai.frame;
		const float h = EGenBuildSeconds();
		const float raw = Eco::MInc() + Eco::MCur() / ((h > 1.f) ? h : 1.f) - Eco::MPull();
		gMFreeEma = first ? raw : (0.9f * gMFreeEma + 0.1f * raw);
	}
	return gMFreeEma;
}

// OUT OF METAL: the feed cannot cover what is asked of it plus `addDrain`, and
// metal is the tighter of the two feeds (HardEStallNow's test, mirrored).
bool MetalShort(float addDrain)
{
	if (MetalFreeRate() >= addDrain)
		return false;
	const float mPull = Eco::MPull() + addDrain;
	const float ePull = Eco::EPull();
	if (mPull <= 0.01f)
		return false;
	if (ePull <= 0.01f)
		return true;
	const float sec = EGenBuildSeconds();
	const float h = (sec > 1.f) ? sec : 1.f;
	const float mShare = (Eco::MInc() + Eco::MCur() / h) / mPull;
	const float eShare = (Eco::EInc() + Eco::ECur() / h) / ePull;
	return mShare <= eShare;
}

// Finished upgraded extractors we own: ledger rows extracting more than the
// basic extractor does.
float gMohoBasic = 0.f;   // the catalog's least extractor, found once
int MohoStanding()
{
	if (gMohoBasic <= 0.f) {
		for (int d = 1; d <= Catalog::gDefCount; ++d) {
			const float e = Catalog::gExtractsM[d];
			if ((e > 0.f) && !Catalog::gMobile[d] && ((gMohoBasic <= 0.f) || (e < gMohoBasic)))
				gMohoBasic = e;
		}
	}
	const float basic = gMohoBasic;
	int n = 0;
	for (uint i = 0; i < gLExtract.length(); ++i) {
		if (gLExtract[i] > basic * 1.5f)
			++n;
	}
	return n;
}

int  gHardEAt = -1;
bool gHardEVal = false;
bool HardEStall()
{
	if (gHardEAt == ai.frame)
		return gHardEVal;
	gHardEAt = ai.frame;
	gHardEVal = HardEStallNow();
	return gHardEVal;
}

bool HardEStallNow()
{
	const float eInc = Eco::EInc();
	const float eCur = Eco::ECur();
	const float eStore = Eco::EStor();
	if (eStore <= 1.f)
		return false;
	const float ePull = Eco::EPull();
	const float sec = EGenBuildSeconds();
	// ENERGY STALLS ONLY WHEN IT IS THE TIGHTER FEED. A lathe runs at the
	// smaller of the two feed shares, so with the metal bank also dry more
	// energy unlocks nothing -- measured at minute 10: metal 10.6 in against
	// 30.7 asked with 20 banked, energy 191 against 412, and every builder
	// hoisted onto solars the metal could not pay for while 27 spots stood open.
	{
		const float mInc = Eco::MInc();
		const float mPull = Eco::MPull();
		const float h = (sec > 1.f) ? sec : 1.f;
		if ((mPull > 0.01f) && (ePull > 0.01f)) {
			const float mShare = (mInc + Eco::MCur() / h) / mPull;
			const float eShare = (eInc + eCur / h) / ePull;
			if ((mShare < 1.f) && (mShare < eShare))
				return false;
		}
	}
	if (aiEconomyMgr.isEnergyStalling)
		return true;
	const float over = ePull - eInc;
	if (over <= 0.f)
		return false;
	// Stalling NOW if the bank runs dry before a generator can stand: a fixed
	// quarter-bank bar only said how long the stall took to notice.
	if (sec > 0.f)
		return (eCur / over) < sec;
	return eCur < 0.25f * eStore;
}

// Builders known to the market: upserted as they pass through Decide (the
// commander included), dropped on death. CCircuitUnit is NOCOUNT -- every
// handle here MUST be removed by NoteDead or it dangles on freed memory.
array<CCircuitUnit@> gWorkers;
array<Id> gWorkerIds;
array<int> gWorkerBorn;   // first-seen frame: the age gate for reclaim
void WorkerSeen(CCircuitUnit@ u)
{
	for (uint i = 0; i < gWorkerIds.length(); ++i) {
		if (gWorkerIds[i] == u.id)
			return;
	}
	gWorkers.insertLast(u);
	gWorkerIds.insertLast(u.id);
	gWorkerBorn.insertLast(ai.frame);
}
void WorkerGone(Id id)
{
	for (uint i = 0; i < gWorkerIds.length(); ++i) {
		if (gWorkerIds[i] == id) {
			ConRoleForget(int(id));
			CrewForget(int(id));
			gWorkerBorn.removeAt(i);
			gWorkers.removeAt(i);
			gWorkerIds.removeAt(i);
			return;
		}
	}
}


}  // namespace Market
