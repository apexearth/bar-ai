namespace Builder {

// Rez bots: the three places their needs differ from an ordinary constructor,
// plus the reclaim pre-empt that runs after everything else has declined.

// Per-bot ledger: last seen health and a trouble window (something shot us,
// HERE), plus the repair-scan throttle. Replaces the dead fortify machinery.
array<int>   gConSlotId;
array<float> gConHp;
array<int>   gConHitUntil;
array<int>   gConNextRepair;
array<int>   gConNextWreck;
// The front sweep gets its OWN clock. It shared gConNextWreck with the eat and
// resurrect rules below it and consumed that clock on every scan, found or not
// -- so a sweep that came back empty (the common case while the front veto was
// refusing the whole line) locked the resurrect rule out of the same election.
// rez=0 for whole games, with the bot idle.
array<int>   gConNextSweep;

// How long one hit keeps a rez bot in flight, and how far apart its own wreck
// scans sit. Both were fixed numbers, and both read as idling on screen.
int RezFleeWindow()
{
	return int(ai.GetTunable("apex_rez_flee_s", TUNE_REZ_FLEE_S)) * SECOND;
}

// "They should always angle themselves BEHIND our units in combat. Never
// stand in front of them where they're likely to become collateral damage"
// (apexearth, seed 20). A work site is behind the line when it is no
// further toward the enemy than our units' lane; with no lane there is
// nothing to be in front of.
int gRzFrontVeto = 0;
// Where our combat units actually stand: the forward-most tenth of them,
// so one runaway raider is not the line. The lane point read 0.1-0.3 of
// the way to the enemy while the wrecks lay at 0.6-1.0 (rez-inst set).
int gArmyFrontAt = -1;
float gArmyFrontFf = -1.f;
AIFloat3 gArmyFrontPos(-1.f, 0.f, -1.f);
float ArmyFront(AIFloat3 &out pos)
{
	if (ai.frame - gArmyFrontAt >= 5 * SECOND) {
		gArmyFrontAt = ai.frame;
		array<float> ffs;
		array<AIFloat3> at;
		const AIFloat3 centre = Builder::gHomeSet ? Builder::gHomePos : AIFloat3(0.f, 0.f, 0.f);
		for (uint d = 1; d < Market::gOwnCount.length(); ++d) {
			if ((Market::gOwnCount[d] <= 0) || !Catalog::gMobile[d] || Catalog::gBuilder[d]
				|| (Catalog::gPower[d] <= 1.f) || Catalog::gFlyer[d])
				continue;
			array<CCircuitUnit@>@ us = ai.GetOwnUnitsOfDef(Catalog::Def(int(d)), centre, 30000.f);
			if (us is null)
				continue;
			for (uint k = 0; k < us.length(); ++k) {
				if (us[k] is null)
					continue;
				const AIFloat3 p = us[k].GetPos(ai.frame);
				if (!OnMap(p))
					continue;
				ffs.insertLast(Military::ForwardFraction(p));
				at.insertLast(p);
			}
		}
		gArmyFrontFf = -1.f;
		if (ffs.length() > 0) {
			const uint want = uint(float(ffs.length() - 1) * 0.9f);
			// The 90th-percentile unit, by SORT rather than by ranking each
			// element against every other: the pairwise rank was O(army^2) and
			// the army is the fastest-growing n we have. Same element -- rank is
			// stable ascending order, so it is the want-th value with the
			// want-below-it count of equal values ahead of it.
			array<float> sorted = ffs;
			sorted.sortAsc();
			const float v = sorted[want];
			uint below = 0;
			for (uint j = 0; j < ffs.length(); ++j)
				if (ffs[j] < v)
					++below;
			uint seen = 0;
			for (uint i = 0; i < ffs.length(); ++i) {
				if (ffs[i] != v)
					continue;
				if (below + seen == want) {
					gArmyFrontFf = ffs[i];
					gArmyFrontPos = at[i];
					break;
				}
				++seen;
			}
		}
	}
	pos = gArmyFrontPos;
	return gArmyFrontFf;
}
bool BehindLine(const AIFloat3 &in site, bool reachClear = false)
{
	// NOTHING CAN SHOOT IT, SO THERE IS NOTHING TO BE IN FRONT OF. Every branch
	// below then answers true (see the note under the forward test), so with the
	// reach already read as clear this is a decided answer, not a skipped test --
	// and it saves the army percentile scan, a ForwardFraction and a second
	// whole-enemy-set sweep on the hot path. RezSiteOk is the only caller and it
	// always arrives here having just read the reach; ffVetoAvg logged 0.00 in
	// all 459 rez-time lines of the 60-minute 8v8, which is that in the log.
	if (reachClear)
		return true;
	AIFloat3 fp;
	const float front = ArmyFront(fp);
	if (front < 0.f)
		return true;
	const float ff = Military::ForwardFraction(site);
	if (ff <= front)
		return true;
	// In front of our units -- but he named it IN COMBAT: "never stand in
	// front of them where they're likely to become collateral damage".
	// Ahead of the line with nothing able to shoot the spot there is no
	// fight to be in front of, and the corpse field is ahead of the line by
	// definition.
	if (!InEnemyReach(site))
		return true;
	gRzVetoFfSum += ff;
	return false;
}

// The one question every rez rule asks of ground it is about to send a bot to:
// is it behind our units, and can anything shoot it? The second half is the
// same envelope the DLL's guard walks bots out of six times a second, so the
// election and the reflex cannot disagree and pull the bot back and forth.
bool RezSiteOk(const AIFloat3 &in site)
{
	if (InEnemyReach(site))
		return false;
	return BehindLine(site, true);
}

int RezScanPeriod()
{
	const int s = int(ai.GetTunable("apex_rez_scan_s", TUNE_REZ_SCAN_S) + 0.5f);
	return (s <= 0) ? 1 : (s * SECOND);
}

// Slot by unit id. gConSlotId never shrinks -- every rez bot the game ever
// builds keeps its row -- so the linear search was O(elections x cons-ever),
// and both of those grow all game. Same Spring 32k id cap as gRzDecideAt; an
// id past it falls back to the walk and behaves exactly as before.
array<int> gConSlotOf(32001, -1);
int ConSlot(CCircuitUnit@ unit)
{
	const int id = int(unit.id);
	const bool indexed = (id >= 0) && (id < int(gConSlotOf.length()));
	if (indexed && (gConSlotOf[id] >= 0))
		return gConSlotOf[id];
	for (uint i = 0; i < gConSlotId.length(); ++i) {
		if (gConSlotId[i] == id) {
			if (indexed)
				gConSlotOf[id] = int(i);
			return int(i);
		}
	}
	gConSlotId.insertLast(id);
	gConHp.insertLast(unit.GetHealthPercent());
	gConHitUntil.insertLast(0);
	gConNextRepair.insertLast(0);
	gConNextWreck.insertLast(0);
	gConNextSweep.insertLast(0);
	const int slot = int(gConSlotId.length()) - 1;
	if (indexed)
		gConSlotOf[id] = slot;
	return slot;
}

// Refresh the bot's hit window from its health delta.
void ConDugIn(CCircuitUnit@ unit)
{
	const int s = ConSlot(unit);
	const float hp = unit.GetHealthPercent();
	if (hp < gConHp[s] - 0.001f)
		gConHitUntil[s] = ai.frame + RezFleeWindow();
	gConHp[s] = hp;
}

IUnitTask@ RezzerFlee(CCircuitUnit@ unit)
{
	// Rez bots have no buildoptions and cannot dig in like an ordinary
	// constructor -- Fortify/ContestTower never apply to them -- so a hit here
	// means flee, not fortify. Nothing else in the pipeline calls ConDugIn for
	// them either, since every rez rule returns early.
	//
	// RezSpotHot/PreferReclaim below only gate which task gets ASSIGNED, and
	// RezSpotHot's ThreatFor falls back to PastFront() geometry once the
	// position threat map reads zero (the common case -- see ThreatFor's own
	// comment), so an enemy push short of the front's 72% line still reads
	// "safe" while standing on the bot. ConDugIn's HP-drop tracking is a real
	// positional signal instead: something shot us, HERE. One hit is enough --
	// unlike an armed constructor, a rez bot cannot dig in, only leave.
	if (IsRezzer(unit)) {
		ConDugIn(unit);   // refreshes the hit window from the health delta
		if (ai.frame < gConHitUntil[ConSlot(unit)]) {
			IUnitTask@ flee = Retreat(unit);
			if (flee !is null) {
				// TROUBLE_WINDOW holds this true for up to 90s per hit, so without a
				// log throttle this re-logs on every AiMakeTask re-entry while fleeing.
				// Retreat() (sitesafety.as) reuses the held RETREAT task instead of
				// re-enqueuing fresh each time -- EnqueueRetreat itself always
				// allocates a new CRetreatTask with no dedup.
				if (ai.frame >= gNextRezFleeLog) {
					gNextRezFleeLog = ai.frame + 20 * SECOND;
					AiLog(Factory::T() + "apex: rez bot taking fire, retreating with whatever it banked");
				}
				return flee;
			}
		}
	}
	return null;
}

// BATTLEFIELD MEDICS (apexearth 2026-08-21): a share of the rez fleet stays
// with the army instead of working the corpse geometry -- repair the wounded
// where the fight is, eat the aftermath where it fell. Deterministic by unit
// id so the split is stable across elections; the flee rule above still wins,
// so a medic under fire leaves like any other rez bot.
bool MedicBot(CCircuitUnit@ unit)
{
	const float share = ai.GetTunable("apex_medic_share", TUNE_MEDIC_SHARE);
	if (share <= 0.f)
		return false;
	return float(int(unit.id) % 100) < share * 100.f;
}

int gNextMedicLog = 0;
int gNextRezLog = 0;

// WHERE A REZ BOT WAITS. apexearth 2026-08-22: "medic bots also need to stay
// safe and not die"; 2026-09-06: "in combat they should stand behind allied
// units away from enemies". Behind the forward-most of our own combat units by
// the bot's own build reach -- it still touches the line, and nothing has to
// walk through it to get there.
bool RezStationPos(CCircuitUnit@ unit, AIFloat3 &out at)
{
	AIFloat3 lane;
	if (ArmyFront(lane) < 0.f)
		lane = Military::LanePos();
	if (!OnMap(lane) || (lane.SqLength2D() < 1.f))
		return false;
	float setback = ai.GetTunable("apex_medic_setback", TUNE_MEDIC_SETBACK);
	if (setback <= 0.f)
		setback = Catalog::gBuildDist[int(unit.circuitDef.id)];
	if ((setback > 0.f) && Builder::gHomeSet) {
		AIFloat3 toHome = Builder::gHomePos - lane;
		const float len = sqrt(toHome.SqLength2D());
		if (len > 1.f) {
			const AIFloat3 back = lane + toHome * (setback / len);
			if (OnMap(back))
				lane = back;
		}
	}
	at = lane;
	return true;
}

IUnitTask@ RezzerMedic(CCircuitUnit@ unit)
{
	if (!IsRezzer(unit) || !MedicBot(unit))
		return null;
	AIFloat3 lane;
	if (!RezStationPos(unit, lane))
		return null;
	const int slot = ConSlot(unit);
	if (ai.frame < gConNextRepair[slot])
		return null;
	// The staging anchor is meant to be OUR ground; if it currently is not,
	// the medic waits rather than walking into what the army retreated from.
	if (ThreatFor(unit, lane) > CON_THREAT_VETO)
		return null;
	gConNextRepair[slot] = ai.frame + REZ_WRECK_PERIOD;
	const float reach = ai.GetTunable("apex_medic_r", TUNE_MEDIC_R);
	// The wounded near the fight come first, wherever the medic stands now.
	array<CCircuitUnit@>@ hurt = ai.GetOwnDamagedNear(lane, reach);
	if (hurt !is null) {
		CCircuitUnit@ best = null;
		float bestDist = 1.0e18f;
		const AIFloat3 here = unit.GetPos(ai.frame);
		for (uint i = 0; i < hurt.length(); ++i) {
			CCircuitUnit@ u = hurt[i];
			if ((u is null) || (u is unit) || !u.circuitDef.IsMobile())
				continue;
			if (!RezSiteOk(u.GetPos(ai.frame))) {
				++gRzFrontVeto;
				continue;
			}
			const float d = here.distance2D(u.GetPos(ai.frame));
			if (d < bestDist) {
				bestDist = d;
				@best = u;
			}
		}
		if (best !is null) {
			if (ai.frame >= gNextMedicLog) {
				gNextMedicLog = ai.frame + 60 * SECOND;
				AiLog(Factory::T() + "apex: medic moving to repair at the line");
			}
			return aiBuilderMgr.Enqueue(TaskB::Repair(Task::Priority::NORMAL, best));
		}
	}
	// Nobody hurt: hold station at the lane, eating whatever the last fight
	// left there. The area reclaim is also the move order.
	const AIFloat3 here = unit.GetPos(ai.frame);
	if (here.distance2D(lane) > reach)
		return aiBuilderMgr.Enqueue(TaskB::Reclaim(
				Task::Priority::NORMAL, lane, 1000.f, WRECK_TIMEOUT, WRECK_RADIUS, true));
	// Already on station and nobody is hurt: the aftermath underfoot is the
	// work. Returning null here left medics standing in a corpse field, because
	// every rule below is gated on being behind, exposed, or short of metal.
	// Bounded to the station radius rather than EnqueueWreckReclaim's own
	// 2200-elmo reach, which would walk the medic off the army it serves.
	const AIFloat3 spoil = BestWreckAt(here, reach, WRECK_MIN);
	if ((spoil.x >= 0.f) && (spoil.distance2D(lane) <= reach)
		&& (ThreatFor(unit, spoil) <= CON_THREAT_VETO) && RezSiteOk(spoil))
	{
		return aiBuilderMgr.Enqueue(TaskB::Reclaim(
				Task::Priority::NORMAL, spoil, 1000.f, WRECK_TIMEOUT, WRECK_RADIUS, true));
	}
	return null;
}

uint gRezSweepIdx = 0;
int gNextRezSweepLog = 0;

IUnitTask@ RezzerFrontSalvage(CCircuitUnit@ unit)
{
	// Rez bots work the DEFENCE LINE, not wherever they happen to stand. The
	// corpses pile up where the fighting is, and the search below only reaches
	// 2200 elmos from the bot itself, so a bot idling at home never finds them.
	// Search from the front whenever we are behind, OR whenever nothing local
	// is worth eating -- a LosingGround()-only gate left rez bots entirely
	// home-bound while winning, which is exactly when the front piles up the
	// most corpses.
	// PER BOT, not one team-wide clock. A single shared gate handed out one
	// salvage assignment per period for the whole fleet, so with several bots
	// idle most of them lost the race every period and stood still.
	if (!IsRezzer(unit))
		return null;
	const int slot = ConSlot(unit);
	if (ai.frame >= gConNextSweep[slot]
			&& (Military::LosingGround() || (BestWreckAt(unit.GetPos(ai.frame), WRECK_SEARCH, WRECK_MIN).x < 0.f))) {
		gConNextSweep[slot] = ai.frame + RezScanPeriod();
		// THE WHOLE LINE, NOT ONE POINT -- and blind where vision is missing.
		// A single FrontLinePos search per period left most of a 10k-elmo
		// front untouched, and wreck queries are LOS-gated (a corpse field
		// nobody stands in reads empty), so the battlefield accumulates
		// thousands of features the engine pays for every frame -- the
		// late-game slowdown itself. Successive sweeps rotate across the
		// front stretches; a stretch with no KNOWN wreck is swept blind --
		// the bot's own arrival provides the vision and the area reclaim
		// eats whatever stands there. An empty blind sweep costs one walk by
		// a bot that had nothing local to do anyway.
		array<AIFloat3> line;
		if (Military::FrontLineSpots(line, WRECK_RADIUS * 1.5f, WRECK_RADIUS)
			&& (line.length() > 0))
		{
			for (uint tryN = 0; tryN < line.length(); ++tryN) {
				const AIFloat3 stretch = line[gRezSweepIdx % line.length()];
				++gRezSweepIdx;
				if (ThreatFor(unit, stretch) > CON_THREAT_VETO)
					continue;
				AIFloat3 spoil = BestWreckAt(stretch, WRECK_SEARCH, WRECK_MIN);
				if (spoil.x < 0.f)
					spoil = stretch;
				if (!RezSiteOk(spoil)) {
				++gRzFrontVeto;
					continue;
				}
				IUnitTask@ harvest = aiBuilderMgr.Enqueue(TaskB::Reclaim(
						Task::Priority::HIGH, spoil, 1000.f, WRECK_TIMEOUT, WRECK_RADIUS, true));
				if (harvest !is null) {
					if (ai.frame >= gNextRezSweepLog) {
						gNextRezSweepLog = ai.frame + 60 * SECOND;
						AiLog(Factory::T() + "apex: rez sweep stretch "
							+ (gRezSweepIdx % line.length()) + "/" + line.length());
					}
					return harvest;
				}
				break;
			}
		}
		AIFloat3 front;
		if (Military::FrontLinePos(front)) {
			const AIFloat3 spoil = BestWreckAt(front, WRECK_SEARCH, WRECK_MIN);
			if ((spoil.x >= 0.f) && RezSiteOk(spoil)) {
				IUnitTask@ harvest = aiBuilderMgr.Enqueue(TaskB::Reclaim(
						Task::Priority::HIGH, spoil, 1000.f, WRECK_TIMEOUT, WRECK_RADIUS, true));
				if (harvest !is null)
					return harvest;
			}
		}
	}
	return null;
}

IUnitTask@ RezzerEatCorpse(CCircuitUnit@ unit)
{
	// Eat the corpse rather than rebuild it, before the engine gets the chance
	// to queue a resurrect for this bot.
	if (!IsRezzer(unit))
		return null;
	const int slot = ConSlot(unit);
	if ((ai.frame >= gConNextWreck[slot])
			&& (PreferReclaim() || RezSpotHot(unit) || RezBotExposed(unit))) {
		gConNextWreck[slot] = ai.frame + RezScanPeriod();
		IUnitTask@ eat = EnqueueWreckReclaim(unit, Task::Priority::HIGH);
		if (eat !is null)
			return eat;
	}
	return null;
}

// The floor for a rez bot that has nothing else claiming it: repair a nearby
// damaged mobile unit rather than stand still. Rez bots are explicitly a
// rez/repair/reclaim unit (armrectr/cornecro/legrezbot's own tooltip), but
// nothing in the engine ever proposes this for them -- CBuilderManager only
// registers a damagedHandler for builders/rez-bots taking damage themselves
// and for static structures (BuilderManager.cpp's InitHandlers), never for an
// ordinary mobile combat unit, so no REPAIR task is ever created for one no
// matter how long it stands there hurt. Reuses WRECK_SEARCH above, the same
// bot's own existing search reach, rather than a new number -- Assist::
// ASSIST_RANGE would fit as well but assist.as is included after builder.as
// (see main.as), so its constants are not visible here yet.
//
// Ranked ABOVE the tree-reclaim floor (IdleFeatureReclaim in maketask.as):
// keeping an existing unit alive is worth more than a handful of scrap metal,
// and this returns null immediately whenever nothing needs it, so it never
// competes with real work above it in the pipeline.
//
// Gated PER BOT (via ConSlot), not by one shared clock. A single global gate
// caps the whole team to one new assignment per period regardless of how many
// rez bots are idle -- during a fight where several units take chip damage at
// once, that serializes response across the whole squad instead of each idle
// bot claiming its own nearest target immediately. The wreck scans above were
// moved off their shared clock for the same reason.

IUnitTask@ RezzerRepairNearby(CCircuitUnit@ unit)
{
	if (!IsRezzer(unit))
		return null;
	const int slot = ConSlot(unit);
	if (ai.frame < gConNextRepair[slot])
		return null;
	gConNextRepair[slot] = ai.frame + REZ_WRECK_PERIOD;

	const AIFloat3 here = unit.GetPos(ai.frame);
	array<CCircuitUnit@>@ hurt = ai.GetOwnDamagedNear(here, WRECK_SEARCH);
	if ((hurt is null) || (hurt.length() == 0))
		return null;

	CCircuitUnit@ best = null;
	float bestDist = WRECK_SEARCH;
	for (uint i = 0; i < hurt.length(); ++i) {
		CCircuitUnit@ u = hurt[i];
		if ((u is null) || (u is unit))
			continue;
		const float dist = here.distance2D(u.GetPos(ai.frame));
		if (dist >= bestDist)
			continue;
		if (!RezSiteOk(u.GetPos(ai.frame))) {
			++gRzFrontVeto;
			continue;
		}
		bestDist = dist;
		@best = u;
	}
	if (best is null)
		return null;
	if (ThreatFor(unit, best.GetPos(ai.frame)) > CON_THREAT_VETO)
		return null;

	return aiBuilderMgr.Enqueue(TaskB::Repair(Task::Priority::NORMAL, best));
}

// The rez half of the job. NOTHING ELSE IN THE PIPELINE EVER ISSUES A
// RESURRECT: the kill-phase rewrite of AiMakeTask dropped the only caller of
// this rule and there is no fall-through to DefaultMakeTask any more, so from
// then until now a rez bot could only ever reclaim. Wired back in as an
// ordinary rule.
//
// A FALLEN COMMANDER OUTRANKS EVERYTHING A REZ BOT COULD DO (apexearth:
// "make sure we resurrect our commanders instead of reclaiming them"). Each
// ally publishes where its commander fell (comwx/comwz/comwf, main.as); any
// rez bot within reach races there and resurrects, whatever the AFUS
// doctrine says -- a commander back on its feet is worth more than any
// reactor sequencing. The window is short: BAR corpses decay to _heap and a
// battlefield gets eaten, so a record older than 4 minutes is a memorial,
// not a job. Threat still vetoes -- a rez bot dying on the corpse rescues
// nobody.
const int COM_WRECK_FRESH_S = 240;
int gNextComRezLog = 0;

IUnitTask@ RezzerComRescue(CCircuitUnit@ unit)
{
	if (!IsRezzer(unit))
		return null;
	array<Id>@ mates = ai.GetTeamIds();
	if (mates is null)
		return null;
	for (uint i = 0; i < mates.length(); ++i) {
		const int t = int(mates[i]);
		const float wf = ai.ReadTeamValue(t, "comwf", -1.f);
		if ((wf < 0.f) || (ai.frame > int(wf) + COM_WRECK_FRESH_S * SECOND))
			continue;
		const AIFloat3 at(ai.ReadTeamValue(t, "comwx", -1.f), 0.f,
				ai.ReadTeamValue(t, "comwz", -1.f));
		if (!OnMap(at))
			continue;
		if ((ThreatFor(unit, at) > CON_THREAT_VETO) || !RezSiteOk(at))
			continue;
		IUnitTask@ rez = aiBuilderMgr.Enqueue(TaskB::Resurrect(
				Task::Priority::HIGH, at, 100.f, 120 * SECOND, WRECK_RADIUS));
		if (rez !is null) {
			if (ai.frame >= gNextComRezLog) {
				gNextComRezLog = ai.frame + 30 * SECOND;
				AiLog("apex: com rescue t=" + ai.teamId + " "
					+ unit.circuitDef.GetName() + " #" + unit.id
					+ " -> resurrect commander of t" + t
					+ " at " + int(at.x) + "," + int(at.z));
			}
			return rez;
		}
	}
	return null;
}

// Reclaim versus resurrect is a question about what the metal is FOR. Before
// the advanced reactor exists a field of corpses is the fastest way to it;
// after it stands the corpse is worth more back on its feet (apexearth: "if
// they feel safe they should prefer to resurrect"). And only where the bot can
// afford the time: an interrupted resurrect returns nothing at all, where a
// reclaim banks metal continuously as it goes.
IUnitTask@ RezzerRezOrEat(CCircuitUnit@ unit)
{
	if (!IsRezzer(unit))
		return null;
	const int slot = ConSlot(unit);
	if (ai.frame < gConNextWreck[slot])
		return null;
	gConNextWreck[slot] = ai.frame + RezScanPeriod();

	// A RICH CORPSE IS RESURRECTED WHATEVER THE DOCTRINE SAYS (apexearth,
	// watching: "I just saw us reclaim our T3 artillery unit which we made
	// from the gantry - we shouldn't be reclaiming something like that").
	// The pre-AFUS eat-everything rule was written for solar-and-pawn
	// fields; a 3,300m Vanguard corpse is a unit for the rez cost, at any
	// stage of the economy. GetBestWreckPos with a high floor finds only
	// such corpses; threat still vetoes.
	if (!(unit.circuitDef.IsFloater() || unit.circuitDef.IsSubmarine())
		&& (ThreatFor(unit, unit.GetPos(ai.frame)) <= CON_THREAT_VETO))
	{
		// Resurrect pays whenever the unit is worth more standing than as
		// scrap and the army is short (apexearth: "plenty of resurrection
		// ability here too but I only seem to see them reclaim"); the 900-
		// metal bar left every T1 wreck to the reclaim beam.
		const bool rezPays = (Market::ArmyTarget() > Market::ArmyValue())
				&& !aiEconomyMgr.isEnergyStalling;
		const AIFloat3 rich = BestRezAt(unit.GetPos(ai.frame), WRECK_SEARCH,
				rezPays ? WRECK_MIN : ai.GetTunable("apex_rez_rich_m", TUNE_REZ_RICH_M));
		if ((rich.x >= 0.f) && (ThreatFor(unit, rich) <= CON_THREAT_VETO) && RezSiteOk(rich)) {
			IUnitTask@ rr = aiBuilderMgr.Enqueue(TaskB::Resurrect(
					Task::Priority::HIGH, rich, 100.f, 90 * SECOND, WRECK_RADIUS));
			if (rr !is null) {
				if (ai.frame >= gNextRezLog) {
					gNextRezLog = ai.frame + 60 * SECOND;
					AiLog("apex: rez rich corpse t=" + ai.teamId
						+ " at " + int(rich.x) + "," + int(rich.z));
				}
				return rr;
			}
		}
	}

	if (!PreferReclaim()
		&& !(unit.circuitDef.IsFloater() || unit.circuitDef.IsSubmarine())
		&& (ThreatFor(unit, unit.GetPos(ai.frame)) <= CON_THREAT_VETO))
	{
		CCircuitDef@ afus = SideDef3("armafus", "corafus", "legafus");
		// Centred on a corpse we can actually see, not on the bot's own feet.
		// A resurrect pays out only on completion, so an area order over empty
		// ground is 60 seconds of standing still with nothing to show.
		const AIFloat3 body = BestWreckAt(unit.GetPos(ai.frame), WRECK_SEARCH, WRECK_MIN);
		if ((afus !is null) && (afus.count > 0) && (body.x >= 0.f)
			&& (ThreatFor(unit, body) <= CON_THREAT_VETO) && RezSiteOk(body))
		{
			IUnitTask@ rez = aiBuilderMgr.Enqueue(TaskB::Resurrect(Task::Priority::NORMAL,
					body, 100.f, 60 * SECOND, WRECK_RADIUS));
			if (rez !is null) {
				if (ai.frame >= gNextRezLog) {
					gNextRezLog = ai.frame + 60 * SECOND;
					AiLog(Factory::T() + "apex: rez bot resurrecting, reactor is up");
				}
				return rez;
			}
		}
	}
	return EnqueueWreckReclaim(unit, Task::Priority::NORMAL);
}

// A rez bot with nothing to do standing on hot ground is the worst of both:
// it is not working and it is being shot. Every rule above vetoes hot work,
// but a veto only refuses the job -- it never moved the bot. Leave instead.
IUnitTask@ RezzerIdle(CCircuitUnit@ unit)
{
	IUnitTask@ scrap = IdleFeatureReclaim(unit, false);
	if (scrap !is null)
		return scrap;
	const AIFloat3 here = unit.GetPos(ai.frame);
	if ((ThreatFor(unit, here) > CON_THREAT_VETO) || InEnemyReach(here))
		return Retreat(unit);
	// NOTHING TO DO IS NOT A REASON TO STAND HERE. The worst bot in the
	// rez-front set went 89-215 s without a job, waiting wherever its last one
	// ended; the corpses and the wounded both appear at the line. Wait behind
	// our own units instead -- the area reclaim is the move order, and it eats
	// whatever it finds on the way.
	AIFloat3 station;
	if (RezStationPos(unit, station) && !InEnemyReach(station)
		&& (here.distance2D(station) > ai.GetTunable("apex_medic_r", TUNE_MEDIC_R)))
	{
		IUnitTask@ walk = aiBuilderMgr.Enqueue(TaskB::Reclaim(
				Task::Priority::LOW, station, 1000.f, WRECK_TIMEOUT, WRECK_RADIUS, true));
		if (walk !is null)
			return walk;
	}
	// GEOMETRY, NOT THE THREAT READ. ThreatFor is the documented mostly-zero
	// sensor, so "standing around dangerous areas" (apexearth, watching,
	// 2026-08-29) read safe to it. Forward of rear-crew ground with no job and
	// no station to hold, it retires to the haven.
	if (Military::ForwardFraction(here)
		> ai.GetTunable("apex_rezzer_fwd", TUNE_REZZER_FWD))
	{
		return Retreat(unit);
	}
	return null;
}

}  // namespace Builder
