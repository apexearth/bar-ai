namespace Military {

//------------------------------------------------------------------------------
// THE RAID IS ASKED FOR, NOT WAITED FOR.
//
// apexearth 2026-09-05: "I don't see why higher level knowledge can't choose to
// do a raid. If we know that there are some pretty undefended areas we should
// be able to ask for a raid, and pull units from wherever seems appropriate in
// order to make a raid happen."
//
// The C++ pool is the opposite shape. DefaultMakeTask drops each raider into
// its own one-unit CDefendTask and a pack exists only if enough of them happen
// to merge before quota.raid.min; measured, thirteen raiders reached that pool
// in one 16-minute game and no raid ever formed. Here the decision comes first:
// find ground of theirs worth taking that nothing is holding, size the pack
// against what IS holding it, then take the units out of whatever they are
// doing and hand them to a raid task.
//
// What this does NOT do is choose where the pack goes. CRaidTask::FindTarget
// owns that and is already economy-first; nothing in the bindings can hand a
// fighter task a target. So the ground found here decides WHETHER to raid and
// HOW BIG, and the task picks the door.
//------------------------------------------------------------------------------

IUnitTask@ gAskTask;         // the pack being assembled, if one is
array<int> gAskClaim;        // pulled units, waiting to re-elect onto it
int   gAskAt = -999999;
float gAskNeed = 0.f;        // power the pack is being built to
AIFloat3 gAskTarget;
bool  gAskHas = false;
int   gAskLogAt = -999999;
int   gAskPulled = 0;        // cumulative, for the log

bool RaidClaimed(int id)
{
	for (uint i = 0; i < gAskClaim.length(); ++i) {
		if (gAskClaim[i] == id)
			return true;
	}
	return false;
}

void DropRaidClaim(int id)
{
	for (uint i = 0; i < gAskClaim.length(); ++i) {
		if (gAskClaim[i] == id) {
			gAskClaim.removeAt(i);
			return;
		}
	}
}

// The pack, created on the first claimed unit's re-election rather than up
// front: an empty fighter task is a task the manager may reap before anything
// reaches it.
IUnitTask@ RaidTaskFor()
{
	if ((gAskTask !is null) && !gAskTask.IsDead())
		return gAskTask;
	@gAskTask = aiMilitaryMgr.Enqueue(TaskF::Common(Task::FightType::RAID));
	return gAskTask;
}

float TaskPower(IUnitTask@ t)
{
	if ((t is null) || t.IsDead())
		return 0.f;
	array<CCircuitUnit@>@ on = t.GetUnits();
	if (on is null)
		return 0.f;
	float p = 0.f;
	for (uint i = 0; i < on.length(); ++i) {
		if ((on[i] !is null) && (on[i].circuitDef !is null))
			p += on[i].circuitDef.power;
	}
	return p;
}

// GROUND OF THEIRS THAT NOTHING IS HOLDING.
//
// Candidates are the map's own metal spots -- the only per-place list the
// script layer has, and the thing raids are for. A spot counts as theirs when
// it is nearer their anchor than ours, which needs no threshold and no
// scouting. `prize` is enemy metal standing on it, `guard` is the influence
// that would shoot at us there; the best spot is the most metal per unit of
// guard. Returns false when nothing of theirs has been seen at any of them,
// which is the honest reading before contact.
// METAL MAPS HAVE NO SPOTS, so the spot loop has nothing to score. A grid at
// the threat pitch stands in for the spot list there, a few cells per update,
// and the best of the last sweep is what RaidTarget answers with.
array<AIFloat3> gRaidCells;
uint  gRaidCellI = 0;
bool  gRaidGridHas = false;
AIFloat3 gRaidGridAt;
float gRaidGridGuard = 0.f;
float gRaidCurScore = 0.f;
bool  gRaidCurHas = false;
AIFloat3 gRaidCurAt;
float gRaidCurGuard = 0.f;

void RaidGridStep()
{
	if (!Builder::gHomeSet || !Market::gSpotsCached || (Market::gAllSpots.length() > 0))
		return;
	const float r = ai.GetTunable("apex_threat_r", TUNE_THREAT_R);
	if (r <= 1.f)
		return;
	if (gRaidCells.length() == 0) {
		const float w = float(AiTerrainWidth());
		const float h = float(AiTerrainHeight());
		for (float z = r * 0.5f; z < h; z += r) {
			for (float x = r * 0.5f; x < w; x += r)
				gRaidCells.insertLast(AIFloat3(x, 0.f, z));
		}
		if (gRaidCells.length() == 0)
			return;
	}
	const AIFloat3 foe = Front::FoeAnchor();
	// Four cells per one-second update: a sweep of the whole map in ~20 s,
	// the ask's own cadence.
	for (int step = 0; step < 4; ++step) {
		const AIFloat3 sp = gRaidCells[gRaidCellI];
		if (!OnMap(foe) || (sp.distance2D(foe) < sp.distance2D(Builder::gHomePos))) {
			const float prize = aiEnemyMgr.GetEnemyStructCostAt(sp, r);
			if (prize > 1.f) {
				const float g = ai.GetEnemyInflAt(sp);
				const float score = prize / (1.f + g);
				if (!gRaidCurHas || (score > gRaidCurScore)) {
					gRaidCurHas = true;
					gRaidCurScore = score;
					gRaidCurAt = sp;
					gRaidCurGuard = g;
				}
			}
		}
		if (++gRaidCellI >= gRaidCells.length()) {
			gRaidCellI = 0;
			gRaidGridHas = gRaidCurHas;
			gRaidGridAt = gRaidCurAt;
			gRaidGridGuard = gRaidCurGuard;
			gRaidCurHas = false;
			gRaidCurScore = 0.f;
		}
	}
}

bool gRaidPrizeLogged = false;
bool gRaidBlindLogged = false;

bool RaidTarget(AIFloat3& out at, float& out guard)
{
	// NEVER CacheSpots() from here. It latches on first call, and calling it
	// from this pass -- which runs from frame 1, before want_mex first asks --
	// moved when the whole map's spot list is taken. Measured 2026-09-05: metal
	// built 8,775 -> 3,150 on the same seed with this director doing nothing
	// else. Read the list its owner has already built, or wait.
	if (!Builder::gHomeSet)
		return false;
	if (Market::gAllSpots.length() == 0) {
		if (!gRaidGridHas)
			return false;
		at = gRaidGridAt;
		guard = gRaidGridGuard;
		return true;
	}
	AIFloat3 foe = Front::FoeAnchor();
	if (!OnMap(foe)) {
		foe = aiEnemyMgr.GetEnemyPos();
		if (!OnMap(foe))
			return false;
	}
	const float r = ai.GetTunable("apex_threat_r", TUNE_THREAT_R);
	float best = 0.f;
	bool have = false;
	for (uint i = 0; i < Market::gAllSpots.length(); ++i) {
		const AIFloat3 sp = Market::gAllSpots[i];
		if (!OnMap(sp))
			continue;
		if (sp.distance2D(foe) >= sp.distance2D(Builder::gHomePos))
			continue;   // our half: not a raid
		// REMEMBERED METAL, NOT WHAT WE CAN SEE RIGHT NOW. This read
		// GetEnemyCostAt, which despite the comment above returns a COUNT OF
		// VISIBLE ENEMY UNITS -- so a spot only scored while two of their units
		// happened to be standing on it in our line of sight. We ran zero scout
		// tasks in the measured game, so it was zero everywhere and all 58 asks
		// refused ("no enemy ground seen") while their base sat in our own
		// registry at 57,777 metal. Structures are also the right prize: a raid
		// is for their economy, not for meeting their army on their ground.
		const float prize = aiEnemyMgr.GetEnemyStructCostAt(sp, r);
		// S7 -- log the first call that could POSSIBLY be informative, not the
		// first call full stop: at frame 150 nothing of theirs has been seen,
		// so a raw 0 there proves only that the binding is callable. Waits for
		// the registry to hold enemy structures at all, then reports what this
		// spot read against the whole-map total.
		if (!gRaidPrizeLogged) {
			const float tot = aiEnemyMgr.GetEnemyStructCost();
			if (tot > 0.f) {
				gRaidPrizeLogged = true;
				AiLog("apex: raid-prize S7 raw GetEnemyStructCostAt=" + prize
					+ " structTotal=" + tot + " r=" + r);
			}
		}
		if (prize <= 1.f)
			continue;
		const float g = ai.GetEnemyInflAt(sp);
		const float score = prize / (1.f + g);
		if (score > best) {
			best = score;
			at = sp;
			guard = g;
			have = true;
		}
	}
	// THE SPOTS ARE THE TARGET EVEN WHEN NOTHING HAS BEEN SEEN. The prize
	// above is REMEMBERED structure metal, and in the first six minutes we
	// have scouted nothing, so it reads zero at every spot and the whole
	// director refuses -- 128 asks in eight games, two of them answered
	// (2026-09-22). A spot on their half is where their extractor and its
	// engineer are, whether or not we have looked: his directive is to
	// harass their engineers and mexes with cheap raiders, and the nearest
	// one is also the shortest walk. Only while we have seen nothing at
	// all; the moment a structure is remembered the scoring above owns it.
	if (!have && (aiEnemyMgr.GetEnemyStructCost() <= 1.f)) {
		float near = 0.f;
		for (uint i = 0; i < Market::gAllSpots.length(); ++i) {
			const AIFloat3 sp = Market::gAllSpots[i];
			if (!OnMap(sp))
				continue;
			const float dHome = sp.distance2D(Builder::gHomePos);
			if (sp.distance2D(foe) >= dHome)
				continue;   // our half: not a raid
			if (!have || (dHome < near)) {
				near = dHome;
				at = sp;
				guard = ai.GetEnemyInflAt(sp);
				have = true;
			}
		}
		if (have && !gRaidBlindLogged) {
			gRaidBlindLogged = true;
			AiLog("apex: raid blind-target at=" + int(at.x) + "," + int(at.z)
				+ " (nothing of theirs seen yet; nearest spot on their half)");
		}
	}
	return have;
}

// SIZE THE PACK AGAINST WHAT HOLDS THE GROUND, never a flat number: one
// Incisor cannot take an LLT and two can. The local defence is converted at
// the same Grunt-class power-per-metal the massing code uses, and beaten by
// apex_local_edge -- the margin already calibrated for "do we locally out-power
// them". Floored at quota.raid.min, which is the smallest pack the raid task
// itself is willing to be.
float RaidPackNeed(const AIFloat3& in at)
{
	const float r = ai.GetTunable("apex_threat_r", TUNE_THREAT_R);
	const float foeM = ai.GetEnemyCostAt(at, r);
	float need = foeM * 0.017f * ai.GetTunable("apex_local_edge", TUNE_LOCAL_EDGE);
	const float floorNow = aiMilitaryMgr.quota.raid.min;
	return (need > floorNow) ? need : floorNow;
}

// May we take units off what they are doing? Only with the base actually
// covered and quiet. CoverShort is the share of our own worth no turret or
// guard reaches, and 0.05 is VirtualPost's own definition of "covered" -- the
// same bar that decides when to stop buying light units, reused rather than
// invented.
bool RaidMayPull()
{
	if (Builder::BaseUnderAttack() || BaseContested() || BaseRaided())
		return false;
	return CoverShort() <= 0.05f;
}

// Worth pulling for a raid: it can fight, it is not a flyer or a builder, and
// it is not the one thing holding a post. Raiders first -- the class is built
// for this -- then whatever else is cheapest, because a raid that costs the
// line its heavy units is not a raid we wanted.
bool RaidWorthPulling(CCircuitUnit@ u)
{
	if ((u is null) || (u.circuitDef is null))
		return false;
	const CCircuitDef@ d = u.circuitDef;
	if (d.IsAbleToFly() || !d.IsMobile())
		return false;
	if (!Market::LineCombat(int(d.id)))
		return false;
	return d.power > 1.f;
}

// Power standing in every live RAID task, whoever assembled it.
float RaidPowerLive()
{
	float p = 0.f;
	for (uint i = 0; i < gSquads.length(); ++i) {
		IUnitTask@ t = gSquads[i];
		if ((t is null) || t.IsDead())
			continue;
		if (t.GetFightType() == int(Task::FightType::RAID))
			p += TaskPower(t);
	}
	return p;
}

// Is this escort surplus? Only if the worker it guards stands where the cover
// already up -- turrets and posted guards -- meets the wave that arrives there.
// Taking escorts regardless cost metal built 10,732 -> 7,963 over three seeds;
// taking none at all leaves raids short on a side whose spare army IS the
// escorts.
bool EscortSpare(IUnitTask@ t)
{
	CCircuitUnit@ vip = t.target;
	if (vip is null)
	    return true;   // guarding nothing we can name: no worker to expose
	const AIFloat3 at = vip.GetPos(ai.frame);
	if (!OnMap(at))
	    return false;
	return Market::CoverAt(at) >= Market::ThreatM(at);
}

void UpdateRaidAsk()
{
	if (ai.GetTunable("apex_raid_ask", TUNE_RAID_ASK) <= 0.f)
		return;
	RaidGridStep();
	if ((ai.frame - gAskAt) < 5 * SECOND)
		return;
	gAskAt = ai.frame;

	// Forget claims whose unit never came back (died between the pull and the
	// re-election), or the list grows for the whole match.
	if (gAskClaim.length() > 32)
		gAskClaim.removeRange(0, gAskClaim.length() - 32);

	AIFloat3 at;
	float guard = 0.f;
	gAskHas = RaidTarget(at, guard);
	if (!gAskHas) {
		if (ai.frame >= gAskLogAt + 30 * SECOND) {
			gAskLogAt = ai.frame;
			AiLog(Factory::T() + "apex: raid ask -- no enemy ground seen"
				+ " (spots=" + Market::gAllSpots.length()
				+ " home=" + (Builder::gHomeSet ? "y" : "n") + ")");
		}
		return;
	}
	gAskTarget = at;
	gAskNeed = RaidPackNeed(at);

	// The pack we already have is every LIVE raid task, not the one handle we
	// happen to hold: the handle goes dead when the task completes or merges,
	// and reading 0 through it meant the "big enough, stop pulling" test never
	// fired. This also counts packs the C++ pool formed on its own, so the
	// director tops up rather than duplicating them.
	const float have = RaidPowerLive() + float(gAskClaim.length());
	if (have >= gAskNeed)
		return;   // the pack is already the size the ground asks for
	if (!RaidMayPull())
		return;

	// Take them out of whatever they are doing. RemoveUnit drops the unit to
	// idle and CIdleTask re-asks AiMakeTask, where the claim routes it onto the
	// pack -- the only way the script layer can move a unit between tasks.
	int pulled = 0;
	const int cap = 4;   // per pass, so one sweep cannot strip the line at once
	for (uint pass = 0; pass < 2; ++pass) {
		for (uint i = 0; (i < gSquads.length()) && (pulled < cap); ++i) {
			IUnitTask@ t = gSquads[i];
			if ((t is null) || t.IsDead() || (t is gAskTask))
				continue;
			const int ft = t.GetFightType();
			if (ft == int(Task::FightType::GUARD)) {
				// An escort is free to take when its worker is standing
				// somewhere already answered -- cover at the worker meets the
				// wave that reaches it -- and expensive to take when it is not.
				if (!EscortSpare(t))
					continue;
			} else if (ft != int(Task::FightType::DEFEND)) {
				continue;
			}
			array<CCircuitUnit@>@ on = t.GetUnits();
			if ((on is null) || (on.length() == 0))
				continue;
			for (uint j = 0; (j < on.length()) && (pulled < cap); ++j) {
				CCircuitUnit@ u = on[j];
				if (!RaidWorthPulling(u))
					continue;
				// First pass takes only raiders; second takes anything, so a
				// raid still happens on a side whose lab makes none.
				const bool isRaider = u.circuitDef.IsRoleAny(Unit::Role::RAIDER.mask);
				if ((pass == 0) && !isRaider)
					continue;
				if (RaidClaimed(int(u.id)))
					continue;
				t.RemoveUnit(u);
				gAskClaim.insertLast(int(u.id));
				++pulled;
				++gAskPulled;
			}
		}
		if (pulled > 0)
			break;
	}

	if (ai.frame >= gAskLogAt + 30 * SECOND) {
		gAskLogAt = ai.frame;
		AiLog(Factory::T() + "apex: raid ask at=" + int(gAskTarget.x) + "," + int(gAskTarget.z)
			+ " guard=" + formatFloat(guard, "", 0, 1)
			+ " need=" + formatFloat(gAskNeed, "", 0, 1)
			+ " have=" + formatFloat(RaidPowerLive(), "", 0, 1)
			+ " claimed=" + gAskClaim.length()
			+ " pulled=" + gAskPulled
			+ (RaidMayPull() ? "" : " (base busy, not pulling)"));
	}
}

}  // namespace Military
