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

// LATCHED. GetTunable is frozen for the game on its first read (CircuitAI
// caches per name), and every one of these is a std::string built from the
// literal plus a map walk. This chain asked for seven of them on EVERY
// election of EVERY rez bot -- MedicBot, RezStationPos, RezScanPeriod three
// times over, the rich-corpse floor and two in the idle rule.
bool  gRzTuneSet = false;
float gRzFleeS = 0.f;
float gRzMedicShare = 0.f;
float gRzMedicSetback = 0.f;
float gRzMedicR = 0.f;
int   gRzScanFrames = 0;
float gRzRichM = 0.f;
float gRzFwdBar = 0.f;

void RzTuneFill()
{
	if (gRzTuneSet)
		return;
	gRzTuneSet = true;
	gRzFleeS = ai.GetTunable("apex_rez_flee_s", TUNE_REZ_FLEE_S);
	gRzMedicShare = ai.GetTunable("apex_medic_share", TUNE_MEDIC_SHARE);
	gRzMedicSetback = ai.GetTunable("apex_medic_setback", TUNE_MEDIC_SETBACK);
	gRzMedicR = ai.GetTunable("apex_medic_r", TUNE_MEDIC_R);
	const int s = int(ai.GetTunable("apex_rez_scan_s", TUNE_REZ_SCAN_S) + 0.5f);
	gRzScanFrames = (s <= 0) ? 1 : (s * SECOND);
	gRzRichM = ai.GetTunable("apex_rez_rich_m", TUNE_REZ_RICH_M);
	gRzFwdBar = ai.GetTunable("apex_rezzer_fwd", TUNE_REZZER_FWD);
}

// How far a medic works from its station. Read by the medic rule and again by
// the idle rule's station test.
float MedicReach()
{
	RzTuneFill();
	return gRzMedicR;
}

// How long one hit keeps a rez bot in flight, and how far apart its own wreck
// scans sit. Both were fixed numbers, and both read as idling on screen.
int RezFleeWindow()
{
	RzTuneFill();
	return int(gRzFleeS) * SECOND;
}

// "They should always angle themselves BEHIND our units in combat. Never
// stand in front of them where they're likely to become collateral damage"
// (apexearth, seed 20). A work site is behind the line when it is no
// further toward the enemy than our units' lane; with no lane there is
// nothing to be in front of.
int gRzFrontVeto = 0;
int gRzVetoBlocked = 0;
// The same refusals split by WHAT was refused and counted against what got
// through, because the rez demand prices damaged units and wrecks as separate
// streams and one lumped veto total cannot say which stream is unreachable.
int gRzOkHurt = 0;
int gRzVetoHurt = 0;
int gRzOkGround = 0;
int gRzVetoGround = 0;
// Did the cover branch of RezSiteOk decide anything? It is the whole of this
// change and it rests on an engine map nothing in the script had read before,
// so a run where cover=0/N means the map is empty to us and the rule is inert,
// not that the ground was hostile.
int gRzSiteCalls = 0;
int gRzOkCover = 0;
// Where our combat units actually stand: the forward-most tenth of them,
// so one runaway raider is not the line. The lane point read 0.1-0.3 of
// the way to the enemy while the wrecks lay at 0.6-1.0 (rez-inst set).
int gArmyFrontAt = -1;
float gArmyFrontFf = -1.f;
AIFloat3 gArmyFrontPos(-1.f, 0.f, -1.f);
// The defs this walk can ever care about. The filter is pure catalog -- mobile,
// not a builder, armed, not a flyer -- and the catalog is written once at Init
// and never again, so re-testing all 580 def ids on every rebuild reached the
// ~40 that can match the long way round. Ascending def id, which is the order
// the walk already ran in, so ffs/at keep their exact previous ordering and the
// percentile picks the same element.
array<int> gArmyDefs;
bool gArmyDefsSet = false;

float ArmyFront(AIFloat3 &out pos)
{
	if (ai.frame - gArmyFrontAt >= 5 * SECOND) {
		gArmyFrontAt = ai.frame;
		if (!gArmyDefsSet && (Catalog::gMobile.length() > 1)) {
			gArmyDefsSet = true;
			for (uint d = 1; d < Catalog::gMobile.length(); ++d) {
				if (!Catalog::gMobile[d] || Catalog::gBuilder[d]
					|| (Catalog::gPower[d] <= 1.f) || Catalog::gFlyer[d])
					continue;
				gArmyDefs.insertLast(int(d));
			}
		}
		array<float> ffs;
		array<AIFloat3> at;
		const AIFloat3 centre = Builder::gHomeSet ? Builder::gHomePos : AIFloat3(0.f, 0.f, 0.f);
		const uint own = Market::gOwnCount.length();
		for (uint q = 0; q < gArmyDefs.length(); ++q) {
			const uint d = uint(gArmyDefs[q]);
			if ((d >= own) || (Market::gOwnCount[d] <= 0))
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
// COVER, NOT A NO-GO MAP. This asked !InEnemyReach(site), refusing every spot
// an enemy weapon covers -- the ground docs/24 sends the bot to ("heal units
// while they fight", "eat their wrecks"), since a unit that is fighting is
// inside enemy reach by definition. The question is his other one: "stand
// behind allied units away from enemies." Only ARMED allies paint allyInfl
// (AddUnarmed writes the defend layer only), each fading out at its own weapon
// range, so ours >= theirs is "our guns hold this spot" -- the map and the
// sentence UpdateRezGuard already steers its evade fan by. ours == 0 is no
// cover at all and the old bar still decides it. The exclusion stays on the
// BOT, in RezzerIdle and that guard, which is where he put it.
bool RezSiteOk(const AIFloat3 &in site)
{
	++gRzSiteCalls;
	// Ground a constructor of ours just died on: the reach test reads the
	// enemies it can see, and 22 rez bots walked into the same Bulls in
	// one minute where it saw none.
	if (Market::NearConDeath(site))
		return false;
	// Ground no builder could path to: the DLL marks a no-path target and
	// this chain re-picked it every second (7,629 nopath by armrectr in four
	// minutes of his Carrot 8v8, a task and a path query each).
	if (Market::NearBlocked(site)) {
		++gRzVetoBlocked;
		return false;
	}
	// THE COVER BRANCH IS REVERTED, ON THE BATTERY. Letting a bot take work
	// wherever our influence merely matched theirs -- docs/24's "heal units
	// while they fight" read literally -- collapsed army from 11.7% to 5.6% of
	// spend over 18 games while metal produced fell 37,432 -> 33,975. His
	// doctrine stands; this reading of it does not, and the veto is not what
	// makes the fleet idle (the rate fix below it is).
	if (!InEnemyReach(site))
		return true;
	// Kept live now that something can actually reach this line: how far toward
	// the enemy the refusals sit. It read 0.00 for whole games because the test
	// that fed it was short-circuited before it could run.
	gRzVetoFfSum += Military::ForwardFraction(site);
	return false;
}

// Ground a bot must STAND STILL on for a minute -- the narrower permission in
// "if they feel safe they should prefer to resurrect" (apexearth). A resurrect
// pays out only on completion, so a bot driven off one banks nothing, where a
// reclaim credits as it goes and RezzerRezOrEat falls through to it. Contested
// cover is enough to work on, not enough to bet a whole timeout on. The
// commander rescue keeps RezSiteOk: him back on his feet outranks the minute.
bool RezRezSiteOk(const AIFloat3 &in site)
{
	if (Market::NearConDeath(site) || InEnemyReach(site))
		return false;
	// The same no-path mark RezSiteOk honours: one unreachable rich corpse
	// took 1,878 aborted walks in five minutes through this door.
	if (Market::NearBlocked(site)) {
		++gRzVetoBlocked;
		return false;
	}
	return true;
}

int RezScanPeriod()
{
	RzTuneFill();
	return gRzScanFrames;
}

// Slot by unit id. gConSlotId never shrinks -- every rez bot the game ever
// builds keeps its row -- so the linear search was O(elections x cons-ever),
// and both of those grow all game. Same Spring 32k id cap as gRzDecideVer; an
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
		// ...or standing where a constructor of ours just died: the fleet
		// walks to one field together, and the first death is the only
		// warning the rest get before the same guns reach them.
		if ((ai.frame < gConHitUntil[ConSlot(unit)])
			|| Market::NearConDeath(unit.GetPos(ai.frame))) {
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
	RzTuneFill();
	const float share = gRzMedicShare;
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
	RzTuneFill();
	float setback = gRzMedicSetback;
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
	const float reach = MedicReach();
	// The wounded near the fight come first, wherever the medic stands now.
	array<CCircuitUnit@>@ hurt = ai.GetOwnDamagedNear(lane, reach);
	if (hurt !is null) {
		CCircuitUnit@ best = null;
		float bestDist = 1.0e18f;
		const AIFloat3 here = unit.GetPos(ai.frame);
		for (uint i = 0; i < hurt.length(); ++i) {
			CCircuitUnit@ u = hurt[i];
			if ((u is null) || (u is unit))
				continue;
			// DISTANCE FIRST. Only the nearest survivor is ever taken, and every
			// test here is a pure predicate, so a candidate already beaten on
			// distance cannot change the answer whatever else is true of it --
			// while RezSiteOk is a walk of every enemy we can see and was being
			// paid for all of them. Same winner, one sweep per running minimum
			// instead of one per casualty. (gRzFrontVeto therefore counts only
			// the vetoes that still decided something.)
			const AIFloat3 at = u.GetPos(ai.frame);
			const float d = here.distance2D(at);
			if (d >= bestDist)
				continue;
			if (!u.circuitDef.IsMobile())
				continue;
			if (!RezSiteOk(at)) {
				++gRzFrontVeto;
				++gRzVetoHurt;
				continue;
			}
			++gRzOkHurt;
			bestDist = d;
			@best = u;
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
			&& (LosingNow() || (BestWreckAt(unit.GetPos(ai.frame), WRECK_SEARCH, WRECK_MIN).x < 0.f))) {
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
					++gRzVetoGround;
					continue;
				}
				++gRzOkGround;
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

// OLD BUILDINGS ARE THE REZ BOT'S TO EAT (apexearth 2026-09-13: "Do rezbots
// reclaim old buildings? We need to increase the speed at which we reclaim
// old stuff"). The market's retirement want discounts every constructor's
// bid by the rez bias the moment a rez bot exists -- on the reasoning that
// the bot will take the work -- and this chain never asked for it, so
// obsolete solars, dwarfed converters and walled-in towers stood for the
// game. The market prices the victim; the bot eats it.
IUnitTask@ RezzerRetire(CCircuitUnit@ unit)
{
	Market::Want@ w = Market::ProposeReclaimObsolete(unit);
	if ((w is null) || (w.value <= 0.f) || (w.kind != Market::WK_RECLAIM))
		return null;
	return Market::ExecuteWant(unit, w);
}

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
		// One GetPos, not three: it was read for the distance, again for the
		// site test, and a third time below for the winner.
		const AIFloat3 at = u.GetPos(ai.frame);
		const float dist = here.distance2D(at);
		if (dist >= bestDist)
			continue;
		if (!RezSiteOk(at)) {
			++gRzFrontVeto;
			++gRzVetoHurt;
			continue;
		}
		++gRzOkHurt;
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

// Our ally team's roster, read once. CAllyTeam takes its team ids in its
// constructor and never writes them again, while ai.GetTeamIds() looks the
// element type up BY NAME through the script engine and allocates a fresh
// script array every call. This is the FIRST rung of seven and runs on every
// election of every rez bot, so that was one type-name lookup and one array
// allocation per election, all game, for a list that cannot change.
array<int> gComRezMates;
bool gComRezMatesSet = false;

IUnitTask@ RezzerComRescue(CCircuitUnit@ unit)
{
	if (!IsRezzer(unit))
		return null;
	if (!gComRezMatesSet) {
		array<Id>@ mates = ai.GetTeamIds();
		if (mates is null)
			return null;
		gComRezMatesSet = true;
		for (uint i = 0; i < mates.length(); ++i)
			gComRezMates.insertLast(int(mates[i]));
	}
	for (uint i = 0; i < gComRezMates.length(); ++i) {
		const int t = gComRezMates[i];
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
CCircuitDef@ gRzAfus = null;

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
		float floorM = WRECK_MIN;
		if (!rezPays) {
			RzTuneFill();
			floorM = gRzRichM;
		}
		const AIFloat3 rich = BestRezAt(unit.GetPos(ai.frame), WRECK_SEARCH, floorM);
		if ((rich.x >= 0.f) && (ThreatFor(unit, rich) <= CON_THREAT_VETO) && RezRezSiteOk(rich)) {
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
		// Latched, the same law as Brain::LightTowerRange: SideDef3 is a side-name
		// read plus a def lookup BY NAME, the answer is constant once the def
		// table is up, and .count stays live off the handle. Never latched off a
		// null def -- that is "the table is not up yet".
		if (gRzAfus is null)
			@gRzAfus = SideDef3("armafus", "corafus", "legafus");
		CCircuitDef@ afus = gRzAfus;
		// Centred on a corpse we can actually see, not on the bot's own feet.
		// A resurrect pays out only on completion, so an area order over empty
		// ground is 60 seconds of standing still with nothing to show.
		const AIFloat3 body = BestWreckAt(unit.GetPos(ai.frame), WRECK_SEARCH, WRECK_MIN);
		if ((afus !is null) && (afus.count > 0) && (body.x >= 0.f)
			&& (ThreatFor(unit, body) <= CON_THREAT_VETO) && RezRezSiteOk(body))
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
	// A station no bot could path to is not walked to again for the mark's
	// life (19,325 nopath by armrectr in one Carrot 8v8: the station sat
	// across a cliff and every bot re-took the walk each second).
	if (RezStationPos(unit, station) && !InEnemyReach(station)
		&& (here.distance2D(station) > MedicReach())
		&& !Market::NearBlocked(station))
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
	RzTuneFill();
	if (Military::ForwardFraction(here) > gRzFwdBar)
		return Retreat(unit);
	return null;
}

}  // namespace Builder
