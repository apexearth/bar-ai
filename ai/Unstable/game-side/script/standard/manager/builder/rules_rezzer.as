namespace Builder {

// Rez bots: the three places their needs differ from an ordinary constructor,
// plus the reclaim pre-empt that runs after everything else has declined.

// Per-bot ledger: last seen health and a trouble window (something shot us,
// HERE), plus the repair-scan throttle. Replaces the dead fortify machinery.
array<int>   gConSlotId;
array<float> gConHp;
array<int>   gConHitUntil;
array<int>   gConNextRepair;
array<int>   gConNextRetire;
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

// WHERE THE WRECKS ARE, off the line (apexearth 2026-09-29: a wreck field
// mid-map, nobody near, no bot sent). The sweep walks our front line and the
// local search the bot's own radius; neither reaches the middle. Deaths, ours
// and theirs, merged per reclaim radius, richest kept; a field is spent when a
// bot is sent to it and refills as the fighting goes on.
const uint WRECK_FIELDS = 48;
array<AIFloat3> gFieldPos;
array<float> gFieldM;
int gRzFieldSent = 0;
int gNextFieldLog = 0;

void NoteWreckField(const AIFloat3& in at, float costM)
{
	if (!OnMap(at) || (costM <= 0.f))
		return;
	for (uint i = 0; i < gFieldPos.length(); ++i) {
		if (gFieldPos[i].distance2D(at) < WRECK_RADIUS) {
			gFieldM[i] += costM;
			return;
		}
	}
	if (gFieldPos.length() < WRECK_FIELDS) {
		gFieldPos.insertLast(at);
		gFieldM.insertLast(costM);
		return;
	}
	uint low = 0;
	for (uint i = 1; i < gFieldM.length(); ++i) {
		if (gFieldM[i] < gFieldM[low])
			low = i;
	}
	if (gFieldM[low] < costM) {
		gFieldPos[low] = at;
		gFieldM[low] = costM;
	}
}

// EnqueueWreckReclaim's refusals, without its counters: a local wreck the eat
// rules will refuse is not local work, and must not hold the bot off the sweep.
bool LocalWreckTakeable(CCircuitUnit@ unit, const AIFloat3 &in at)
{
	return !Market::NearBlocked(at) && !Market::NearPathBlocked(at)
		&& !Market::NearConDeath(at) && (RezThreat(unit, at) <= CON_THREAT_VETO)
		&& !InEnemyReach(at) && RezReaches(unit, at);
}
int gRzSwLocal = 0;
int gRzFldNone = 0;
int gRzFldThreat = 0;
int gRzFldSite = 0;
// The richest field this bot may be sent to, spent on SEND; null if none.
// Asked only after the line offered nothing, eight fields at most a sweep. A
// refused field is skipped, not dropped: wrecks are born mid-fight, so the
// first ask nearly always reads hot, and dropping it then lost the field for
// good once the fight moved on.
IUnitTask@ RezzerWreckField(CCircuitUnit@ unit)
{
	if (gFieldPos.length() == 0)
		++gRzFldNone;
	array<bool> tried(gFieldPos.length(), false);
	for (uint tries = 0; tries < 8; ++tries) {
		int pick = -1;
		for (uint i = 0; i < gFieldM.length(); ++i) {
			if (!tried[i] && ((pick < 0) || (gFieldM[i] > gFieldM[uint(pick)])))
				pick = int(i);
		}
		if (pick < 0)
			return null;
		const uint best = uint(pick);
		tried[best] = true;
		const AIFloat3 at = gFieldPos[best];
		const float m = gFieldM[best];
		if (m < WRECK_MIN)
			return null;
		if (RezThreat(unit, at) > CON_THREAT_VETO) {
			++gRzFldThreat;
			NoteRezWant(unit, at, m);
			continue;
		}
		AIFloat3 spoil = BestWreckAt(at, WRECK_RADIUS * 2.f, WRECK_MIN);
		if (spoil.x < 0.f)
			spoil = at;
		if (!RezSiteOk(unit, spoil)) {
			if (gRzSiteDanger)
				NoteRezWant(unit, spoil, m);
			++gRzFldSite;
			++gRzFrontVeto;
			++gRzVetoGround;
			continue;
		}
		++gRzOkGround;
		IUnitTask@ harvest = aiBuilderMgr.Enqueue(TaskB::Reclaim(
				Task::Priority::HIGH, spoil, 1000.f, WRECK_TIMEOUT, WRECK_RADIUS, true));
		if (harvest is null)
			return null;
		gFieldPos.removeAt(best);
		gFieldM.removeAt(best);
		++gRzFieldSent;
		if (ai.frame >= gNextFieldLog) {
			gNextFieldLog = ai.frame + 60 * SECOND;
			AiLog(Factory::T() + "apex: rez field " + int(spoil.x) + "," + int(spoil.z)
				+ " m=" + int(m) + " sent=" + gRzFieldSent + " left=" + gFieldPos.length());
		}
		return harvest;
	}
	return null;
}

// Where the fleet stands (forward-fraction quarters) and what it holds, and the
// live wreck metal in the remembered fields, our half / theirs. Once a minute.
string RzCensusStr()
{
	array<int> bots(4, 0);
	array<int> held(7, 0);   // idle patrol reclaim rez repair retreat other
	int stagedNow = 0;
	const AIFloat3 centre = Builder::gHomeSet ? Builder::gHomePos : AIFloat3(0.f, 0.f, 0.f);
	for (uint i = 0; i < gRezzerIds.length(); ++i) {
		CCircuitDef@ d = ai.GetCircuitDef(gRezzerIds[i]);
		if (d is null)
			continue;
		array<CCircuitUnit@>@ us = ai.GetOwnUnitsOfDef(d, centre, 30000.f);
		if (us is null)
			continue;
		for (uint k = 0; k < us.length(); ++k) {
			if (us[k] is null)
				continue;
			const float ff = Military::ForwardFraction(us[k].GetPos(ai.frame));
			++bots[(ff < 0.25f) ? 0 : (ff < 0.5f) ? 1 : (ff < 0.75f) ? 2 : 3];
			IUnitTask@ t = us[k].task;
			if ((t is null) || (t.GetType() == Task::Type::IDLE))
				++held[0];
			else if ((t.GetType() == Task::Type::BUILDER) && (t.GetBuildType() == Task::BuildType::PATROL))
				++held[1];
			else if ((t.GetType() == Task::Type::BUILDER) && (t.GetBuildType() == Task::BuildType::RECLAIM))
				++held[2];
			else if ((t.GetType() == Task::Type::BUILDER) && (t.GetBuildType() == Task::BuildType::RESURRECT))
				++held[3];
			else if ((t.GetType() == Task::Type::BUILDER) && (t.GetBuildType() == Task::BuildType::REPAIR))
				++held[4];
			else if (t.GetType() == Task::Type::RETREAT)
				++held[5];
			else
				++held[6];
			const int sl = ConSlot(us[k]);
			if ((sl < int(gRzStagedAt.length())) && (gRzStagedAt[sl] >= 0))
				++stagedNow;
		}
	}
	float ours = 0.f;
	float theirs = 0.f;
	for (uint i = 0; i < gFieldPos.length(); ++i) {
		const float v = ai.GetWreckValueAt(gFieldPos[i], WRECK_RADIUS);
		if (Military::ForwardFraction(gFieldPos[i]) < 0.5f)
			ours += v;
		else
			theirs += v;
	}
	return " botsFf=" + bots[0] + "/" + bots[1] + "/" + bots[2] + "/" + bots[3]
		+ " task=" + held[0] + "/" + held[1] + "/" + held[2] + "/" + held[3] + "/" + held[4] + "/" + held[5] + "/" + held[6]
		+ " swLocal=" + gRzSwLocal + " fld=" + gFieldPos.length() + " fldNone=" + gRzFldNone
		+ " fldThr=" + gRzFldThreat + " fldSite=" + gRzFldSite + " fldSent=" + gRzFieldSent
		+ " fldM=" + int(ours) + "/" + int(theirs)
		+ " heal=" + gRzHealPick + "/" + int((gRzHealPick > 0) ? gRzHealDist / float(gRzHealPick) : 0.f)
		+ "/" + gRzHealMoving + "/" + gRzHealOutrun + "/" + gRzHealWreckWin + "/" + gRzHealRetreatSkip
		+ " walkBack=" + gRzMedWalkBack + RzStageStr(stagedNow);
}
int gRzBlindToRetire = 0;
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
// From where the bot stands: the best wreck is picked by value in a radius, and
// on a sea map it was often across the water, and each was a task, a path
// query and an election.
bool RezReaches(CCircuitUnit@ unit, const AIFloat3 &in site)
{
	const int ud = int(unit.circuitDef.id);
	// The area model says yes to some walks the pathfinder then refuses; a
	// refusal into that sector is remembered for a minute (C++ NoteNoPath).
	if (ai.IsNoPath(Catalog::Def(ud), site))
		return false;
	return ai.CanDefReachAt(Catalog::Def(ud), unit.GetPos(ai.frame), site,
			Catalog::gBuildDist[ud] + 64.f);
}

bool RezSiteOk(CCircuitUnit@ unit, const AIFloat3 &in site)
{
	++gRzSiteCalls;
	gRzSiteDanger = false;
	if (!RezReaches(unit, site))
		return false;
	// Ground a constructor of ours just died on: the reach test reads the
	// enemies it can see, and 22 rez bots walked into the same Bulls in
	// one minute where it saw none.
	if (Market::NearConDeath(site))
		return false;
	// Ground no builder could path to: the DLL marks a no-path target and
	// this chain re-picked it every second (7,629 nopath by armrectr in four
	// minutes of his Carrot 8v8, a task and a path query each).
	if (Market::NearPathBlocked(site)) {
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
	gRzSiteDanger = true;
	return false;
}

// Ground a bot must STAND STILL on for a minute -- the narrower permission in
// "if they feel safe they should prefer to resurrect" (apexearth). A resurrect
// pays out only on completion, so a bot driven off one banks nothing, where a
// reclaim credits as it goes and RezzerRezOrEat falls through to it. Contested
// cover is enough to work on, not enough to bet a whole timeout on. The
// commander rescue keeps RezSiteOk: him back on his feet outranks the minute.
bool RezRezSiteOk(CCircuitUnit@ unit, const AIFloat3 &in site)
{
	if (!RezReaches(unit, site) || Market::NearConDeath(site) || InEnemyReach(site))
		return false;
	// The same no-path mark RezSiteOk honours: one unreachable rich corpse
	// took 1,878 aborted walks in five minutes through this door.
	if (Market::NearPathBlocked(site)) {
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
	gConNextRetire.insertLast(0);
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
// THE HEAL STATION (apexearth 2026-09-30: "as close to the army as possible
// while staying safe"): from the forward-most of our combat units, the first
// point toward home the enemy cannot reach. The medics stand there and the
// wounded retreat to it (CRetreatTask reads it through SetHealPos).
int gHealAt = -999999;
bool gHealOk = false;
AIFloat3 gHealPos;
bool HealStation(AIFloat3 &out at)
{
	if (ai.frame - gHealAt >= 5 * SECOND) {
		gHealAt = ai.frame;
		gHealOk = false;
		AIFloat3 front;
		if ((ArmyFront(front) >= 0.f) && Builder::gHomeSet && OnMap(front)) {
			AIFloat3 dir = Builder::gHomePos - front;
			const float len = sqrt(dir.SqLength2D());
			if (len > 1.f) {
				dir *= (1.f / len);
				for (float s = 128.f; s < len; s += 128.f) {
					const AIFloat3 p = front + dir * s;
					if (OnMap(p) && !InEnemyReach(p) && !Market::NearConDeath(p)) {
						gHealPos = p;
						gHealOk = true;
						break;
					}
				}
			}
		}
		ai.SetHealPos(gHealOk ? gHealPos : AIFloat3(-1.f, 0.f, -1.f));
	}
	at = gHealPos;
	return gHealOk;
}

bool RezStationPos(CCircuitUnit@ unit, AIFloat3 &out at)
{
	if (HealStation(at))
		return true;
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

// HEALING PRICES THE WALK (apexearth 2026-10-04: rez bots "run past wreckage to
// chase down a unit to heal it"). A heal and a wreck are both metal -- the
// health missing, the wreck's content -- over the seconds to get there, and a
// target walking away is chased at our speed less its own. One that outruns us
// is no job. The floor is the scan period: the next look comes then anyway.
const bool RZ_HEAL_PRICE = true;
float RzMax(float a, float b) { return (a > b) ? a : b; }
array<float> gMotX(32001, 0.f);
array<float> gMotZ(32001, 0.f);
array<int> gMotAt(32001, -1);
int gRzHealPick = 0;
float gRzHealDist = 0.f;
int gRzHealMoving = 0;
int gRzHealOutrun = 0;
int gRzHealWreckWin = 0;
int gRzMedWalkBack = 0;
int gRzHealRetreatSkip = 0;
const bool RZ_HEAL_RETREAT = true;

float HealArriveS(CCircuitUnit@ bot, CCircuitUnit@ u, const AIFloat3 &in here,
		const AIFloat3 &in at, bool &out moving, bool &out known)
{
	const int bd = int(bot.circuitDef.id);
	const float spd = RzMax(Catalog::gSpeed[bd], 1.f);
	const float gap = RzMax(0.f, here.distance2D(at) - Catalog::gBuildDist[bd]);
	moving = false;
	known = false;
	float away = 0.f;
	const int id = int(u.id);
	if ((id >= 0) && (id < int(gMotAt.length()))) {
		const int dtF = ai.frame - gMotAt[id];
		if ((gMotAt[id] >= 0) && (dtF >= SECOND / 2) && (dtF <= 6 * SECOND)) {
			const AIFloat3 prev(gMotX[id], at.y, gMotZ[id]);
			const float dt = float(dtF) / float(SECOND);
			known = true;
			moving = at.distance2D(prev) > 4.f * SQUARE_SIZE;
			away = (here.distance2D(at) - here.distance2D(prev)) / dt;
		}
		if ((gMotAt[id] < 0) || (dtF >= SECOND)) {
			gMotX[id] = at.x;
			gMotZ[id] = at.z;
			gMotAt[id] = ai.frame;
		}
	}
	if (gap <= 0.f)
		return 0.f;
	const float closing = spd - RzMax(away, 0.f);
	if (closing <= 0.f)
		return -1.f;
	return gap / closing;
}

float RzRate(float valueM, float arriveS)
{
	return valueM / (arriveS + float(REZ_WRECK_PERIOD) / float(SECOND));
}

float HealValueM(CCircuitUnit@ u)
{
	return Catalog::gCostM[int(u.circuitDef.id)] * RzMax(0.f, 1.f - u.GetHealthPercent());
}

// The best heal in a hurt list by metal per second of getting there (or the
// nearest, with pricing off); rate out, null if none.
CCircuitUnit@ PickHeal(CCircuitUnit@ unit, array<CCircuitUnit@>@ hurt, bool mobileOnly,
		float maxDist, float &out bestRate, bool &out bestMoving, float &out bestDist)
{
	CCircuitUnit@ best = null;
	bestRate = 0.f;
	bestMoving = false;
	bestDist = maxDist;
	const AIFloat3 here = unit.GetPos(ai.frame);
	for (uint i = 0; i < hurt.length(); ++i) {
		CCircuitUnit@ u = hurt[i];
		if ((u is null) || (u is unit))
			continue;
		if (mobileOnly && !u.circuitDef.IsMobile())
			continue;
		const AIFloat3 at = u.GetPos(ai.frame);
		const float d = here.distance2D(at);
		bool moving = false;
		bool known = false;
		const float arrive = HealArriveS(unit, u, here, at, moving, known);
		float rate = 0.f;
		if (RZ_HEAL_PRICE) {
			// A unit on its way somewhere is healed where it stops, not chased
			// (apexearth 2026-10-04); one still in the fight may be.
			if (RZ_HEAL_RETREAT && (moving || !known)) {
				IUnitTask@ ut = u.task;
				const bool leaving = (ut !is null) && (ut.GetType() == Task::Type::RETREAT);
				if (leaving || (moving && (FoesNear(at) < CON_FOE_COUNT))) {
					++gRzHealRetreatSkip;
					continue;
				}
			}
			if (arrive < 0.f) {
				++gRzHealOutrun;
				continue;
			}
			rate = RzRate(HealValueM(u), arrive);
			if ((best !is null) && (rate <= bestRate))
				continue;
		} else if (d >= bestDist) {
			continue;
		}
		// Ranked first, so the enemy walk inside RezSiteOk is paid only by a
		// candidate that would win.
		if (!RezSiteOk(unit, at)) {
			++gRzFrontVeto;
			++gRzVetoHurt;
			continue;
		}
		++gRzOkHurt;
		bestRate = rate;
		bestDist = d;
		bestMoving = moving;
		@best = u;
	}
	return best;
}

// The wreck a medic may take instead: richer per second of walking than the
// heal on offer, or the only work there is.
IUnitTask@ MedicWreckInstead(CCircuitUnit@ unit, float reach, float healRate)
{
	const AIFloat3 here = unit.GetPos(ai.frame);
	const AIFloat3 spoil = BestWreckAt(here, reach, WRECK_MIN);
	if (spoil.x < 0.f)
		return null;
	const int bd = int(unit.circuitDef.id);
	const float walk = RzMax(0.f, here.distance2D(spoil) - Catalog::gBuildDist[bd])
			/ RzMax(Catalog::gSpeed[bd], 1.f);
	if (RzRate(ai.GetWreckValueAt(spoil, WRECK_RADIUS), walk) <= healRate)
		return null;
	if ((RezThreat(unit, spoil) > CON_THREAT_VETO) || !RezSiteOk(unit, spoil))
		return null;
	return aiBuilderMgr.Enqueue(TaskB::Reclaim(
			Task::Priority::NORMAL, spoil, 1000.f, WRECK_TIMEOUT, WRECK_RADIUS, true));
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
	if (RezThreat(unit, lane) > CON_THREAT_VETO)
		return null;
	gConNextRepair[slot] = ai.frame + REZ_WRECK_PERIOD;
	const float reach = MedicReach();
	// The wounded near the fight come first, wherever the medic stands now.
	array<CCircuitUnit@>@ hurt = ai.GetOwnDamagedNear(lane, reach);
	if (hurt !is null) {
		float rate;
		bool moving;
		float dist;
		CCircuitUnit@ best = PickHeal(unit, hurt, true, 1.0e18f, rate, moving, dist);
		if (best !is null) {
			if (RZ_HEAL_PRICE) {
				IUnitTask@ eat = MedicWreckInstead(unit, reach, rate);
				if (eat !is null) {
					++gRzHealWreckWin;
					return eat;
				}
			}
			++gRzHealPick;
			gRzHealDist += dist;
			if (moving)
				++gRzHealMoving;
			if (ai.frame >= gNextMedicLog) {
				gNextMedicLog = ai.frame + 60 * SECOND;
				AiLog(Factory::T() + "apex: medic moving to repair at the line");
			}
			return aiBuilderMgr.Enqueue(TaskB::Repair(Task::Priority::NORMAL, best));
		}
	}
	// Nobody hurt: hold station at the lane, eating whatever the last fight
	// left there. The area reclaim is also the move order -- but not past a
	// wreck the medic is standing beside.
	const AIFloat3 here = unit.GetPos(ai.frame);
	if (here.distance2D(lane) > reach) {
		if (RZ_HEAL_PRICE) {
			IUnitTask@ eat = MedicWreckInstead(unit, reach, 0.f);
			if (eat !is null)
				return eat;
		}
		++gRzMedWalkBack;
		return aiBuilderMgr.Enqueue(TaskB::Reclaim(
				Task::Priority::NORMAL, lane, 1000.f, WRECK_TIMEOUT, WRECK_RADIUS, true));
	}
	// Already on station and nobody is hurt: the aftermath underfoot is the
	// work. Returning null here left medics standing in a corpse field, because
	// every rule below is gated on being behind, exposed, or short of metal.
	// Bounded to the station radius rather than EnqueueWreckReclaim's own
	// 2200-elmo reach, which would walk the medic off the army it serves.
	const AIFloat3 spoil = BestWreckAt(here, reach, WRECK_MIN);
	if ((spoil.x >= 0.f) && (spoil.distance2D(lane) <= reach)
		&& (RezThreat(unit, spoil) <= CON_THREAT_VETO) && RezSiteOk(unit, spoil))
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
	bool sweep = (ai.frame >= gConNextSweep[slot]);
	if (sweep && !LosingNow()) {
		const AIFloat3 loc = BestWreckAt(unit.GetPos(ai.frame), WRECK_SEARCH, WRECK_MIN);
		sweep = (loc.x < 0.f) || !LocalWreckTakeable(unit, loc);
		if (!sweep)
			++gRzSwLocal;
	}
	if (sweep) {
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
			// Four stretches a call: the rotation index carries on from where
			// this stopped, so the line is still covered, a few at a time.
			for (uint tryN = 0; (tryN < line.length()) && (tryN < 4); ++tryN) {
				const AIFloat3 stretch = line[gRezSweepIdx % line.length()];
				++gRezSweepIdx;
				if (RezThreat(unit, stretch) > CON_THREAT_VETO)
					continue;
				AIFloat3 spoil = BestWreckAt(stretch, WRECK_SEARCH, WRECK_MIN);
				if (spoil.x < 0.f) {
					// A priced obsolete building is known work; a blind sweep
					// is a guess. Ahead of it in the chain, retire never ran.
					IUnitTask@ old = RezzerRetire(unit);
					if (old !is null) {
						++gRzBlindToRetire;
						return old;
					}
					spoil = stretch;
				}
				if (!RezSiteOk(unit, spoil)) {
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
			if ((spoil.x >= 0.f) && RezSiteOk(unit, spoil)) {
				IUnitTask@ harvest = aiBuilderMgr.Enqueue(TaskB::Reclaim(
						Task::Priority::HIGH, spoil, 1000.f, WRECK_TIMEOUT, WRECK_RADIUS, true));
				if (harvest !is null)
					return harvest;
			}
		}
		IUnitTask@ field = RezzerWreckField(unit);
		if (field !is null)
			return field;
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
	// Memoised like the constructors' step: uncached, an idle fleet re-ran the
	// whole obsolete search every election and found nothing. And asked once
	// per bot per REZ_RETIRE_PERIOD: retirement is never urgent, and each miss
	// was ~750 us (rz.retire, his-settings 8v8).
	const int slot = ConSlot(unit);
	if (ai.frame < gConNextRetire[slot])
		return null;
	gConNextRetire[slot] = ai.frame + REZ_RETIRE_PERIOD;
	Market::Want@ w = Market::MemoPropose(4, unit);
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

	float rate;
	bool moving;
	float dist;
	CCircuitUnit@ best = PickHeal(unit, hurt, false, WRECK_SEARCH, rate, moving, dist);
	if (best is null)
		return null;
	++gRzHealPick;
	gRzHealDist += dist;
	if (moving)
		++gRzHealMoving;
	if (RezThreat(unit, best.GetPos(ai.frame)) > CON_THREAT_VETO)
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
		if ((RezThreat(unit, at) > CON_THREAT_VETO) || !RezSiteOk(unit, at))
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
		&& (RezThreat(unit, unit.GetPos(ai.frame)) <= CON_THREAT_VETO))
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
		if ((rich.x >= 0.f) && (RezThreat(unit, rich) <= CON_THREAT_VETO) && RezRezSiteOk(unit, rich)) {
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
		&& (RezThreat(unit, unit.GetPos(ai.frame)) <= CON_THREAT_VETO))
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
			&& (RezThreat(unit, body) <= CON_THREAT_VETO) && RezRezSiteOk(unit, body))
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

// WAIT BESIDE THE JOB (apexearth 2026-10-04: "I'd love to be reclaiming all
// these wrecks here, but it feels a little dangerous right now, so I'll wait
// right outside them for things to get safe"). The richest job each bot was
// refused for visible danger alone; it stands on the first ground toward home
// the visible enemies cannot reach -- the HealStation walk -- and the chain
// takes the job the moment the refusal lifts.
bool gRzSiteDanger = false;
array<float> gRzWantX;
array<float> gRzWantZ;
array<float> gRzWantM;
array<int> gRzStagedAt;
array<float> gRzStageX;
array<float> gRzStageZ;
array<int> gRzStageCalcAt;
int gRzStageEv = 0;
int gRzStageTook = 0;
float gRzStageWaitS = 0.f;
int gRzStageGone = 0;
int gRzIdleAtStand = 0;

void RzWantRoom(int slot)
{
	while (int(gRzWantX.length()) <= slot) {
		gRzWantX.insertLast(-1.f);
		gRzWantZ.insertLast(-1.f);
		gRzWantM.insertLast(0.f);
		gRzStagedAt.insertLast(-1);
		gRzStageX.insertLast(-1.f);
		gRzStageZ.insertLast(-1.f);
		gRzStageCalcAt.insertLast(-30000);
	}
}

void NoteRezWant(CCircuitUnit@ unit, const AIFloat3 &in at, float m)
{
	const int s = ConSlot(unit);
	RzWantRoom(s);
	if ((gRzWantX[s] >= 0.f) && (gRzWantM[s] >= m))
		return;
	gRzWantX[s] = at.x;
	gRzWantZ[s] = at.z;
	gRzWantM[s] = m;
	gRzStageCalcAt[s] = -30000;
}

void ClearRezWant(int s)
{
	gRzWantX[s] = -1.f;
	gRzWantM[s] = 0.f;
	gRzStagedAt[s] = -1;
}

// Called with the job the chain chose: one at the staged want is the payoff.
void NoteRezJob(CCircuitUnit@ unit, IUnitTask@ t)
{
	const int s = ConSlot(unit);
	RzWantRoom(s);
	if ((gRzWantX[s] < 0.f) || (t is null))
		return;
	const AIFloat3 want(gRzWantX[s], 0.f, gRzWantZ[s]);
	CCircuitUnit@ tg = t.target;
	const AIFloat3 at = (tg !is null) ? tg.GetPos(ai.frame) : t.GetBuildPos();
	if (!OnMap(at) || (at.distance2D(want) > WRECK_RADIUS * 2.f))
		return;
	if (gRzStagedAt[s] >= 0) {
		++gRzStageTook;
		gRzStageWaitS += float(ai.frame - gRzStagedAt[s]) / float(SECOND);
	}
	ClearRezWant(s);
}

// First ground from the want toward home that no visible enemy reaches or
// stands near, at HealStation's step; recomputed once a scan period.
bool RezStagePos(int s, AIFloat3 &out at)
{
	if (ai.frame - gRzStageCalcAt[s] < REZ_WRECK_PERIOD) {
		at = AIFloat3(gRzStageX[s], 0.f, gRzStageZ[s]);
		return gRzStageX[s] >= 0.f;
	}
	gRzStageCalcAt[s] = ai.frame;
	gRzStageX[s] = -1.f;
	if (!Builder::gHomeSet)
		return false;
	const AIFloat3 want(gRzWantX[s], 0.f, gRzWantZ[s]);
	AIFloat3 dir = Builder::gHomePos - want;
	const float len = sqrt(dir.SqLength2D());
	if (len < 1.f)
		return false;
	dir *= (1.f / len);
	for (float d = 128.f; d < len; d += 128.f) {
		const AIFloat3 p = want + dir * d;
		if (OnMap(p) && !InEnemyReach(p) && (FoesNear(p) < CON_FOE_COUNT)
			&& !Market::NearConDeath(p))
		{
			gRzStageX[s] = p.x;
			gRzStageZ[s] = p.z;
			break;
		}
	}
	at = AIFloat3(gRzStageX[s], 0.f, gRzStageZ[s]);
	return gRzStageX[s] >= 0.f;
}

string RzStageStr(int now)
{
	return " stage=" + gRzStageEv + "/" + now + "/" + gRzStageTook
		+ "/" + int((gRzStageTook > 0) ? gRzStageWaitS / float(gRzStageTook) : 0.f)
		+ "/" + gRzStageGone + " atStand=" + gRzIdleAtStand;
}

// Stand at a point: walk there with the area reclaim (it eats on the way),
// hold still once inside its circle.
IUnitTask@ RezHoldAt(CCircuitUnit@ unit, const AIFloat3 &in at, bool &out walking)
{
	walking = false;
	if (unit.GetPos(ai.frame).distance2D(at) <= WRECK_RADIUS)
		return null;
	walking = true;
	return aiBuilderMgr.Enqueue(TaskB::Reclaim(
			Task::Priority::LOW, at, 1000.f, WRECK_TIMEOUT, WRECK_RADIUS, true));
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
	if ((RezThreat(unit, here) > CON_THREAT_VETO) || InEnemyReach(here))
		return Retreat(unit);
	const int s = ConSlot(unit);
	RzWantRoom(s);
	if (gRzWantX[s] >= 0.f) {
		const AIFloat3 want(gRzWantX[s], 0.f, gRzWantZ[s]);
		if (BestWreckAt(want, WRECK_RADIUS * 2.f, WRECK_MIN).x < 0.f) {
			++gRzStageGone;
			ClearRezWant(s);
		} else {
			AIFloat3 stage;
			if (RezStagePos(s, stage) && !Market::NearBlocked(stage)) {
				if (gRzStagedAt[s] < 0) {
					gRzStagedAt[s] = ai.frame;
					++gRzStageEv;
				}
				bool walking;
				IUnitTask@ go = RezHoldAt(unit, stage, walking);
				if ((go !is null) || !walking)
					return go;
			}
		}
	}
	// NOTHING TO DO: WAIT AT THE MEDIC STAND (apexearth 2026-10-04), where the
	// wounded come to be healed and the next fight's corpses are closest. A
	// stand no bot could path to is not walked to again for the mark's life
	// (19,325 nopath by armrectr in one Carrot 8v8: the station sat across a
	// cliff and every bot re-took the walk each second).
	AIFloat3 station;
	if (RezStationPos(unit, station) && !InEnemyReach(station)
		&& !Market::NearBlocked(station))
	{
		bool walking;
		IUnitTask@ walk = RezHoldAt(unit, station, walking);
		if (!walking)
			++gRzIdleAtStand;
		if ((walk !is null) || !walking)
			return walk;
	}
	// GEOMETRY, NOT THE THREAT READ, and only with no stand to hold: "standing
	// around dangerous areas" (apexearth, watching, 2026-08-29). Reached before
	// with a stand inside MedicReach, it sent the bot home and the stand walk
	// sent it back -- the patrol back and forth.
	RzTuneFill();
	if (Military::ForwardFraction(here) > gRzFwdBar)
		return Retreat(unit);
	return null;
}

}  // namespace Builder
