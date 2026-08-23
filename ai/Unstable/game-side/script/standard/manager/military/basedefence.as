namespace Military {

// A jammer denies the radar siege artillery needs to shoot at range, so it
// belongs on the defensive line rather than back beside a fusion. There is no
// T2 jammer tower in this game -- corjamt/armjamt/legjam are the only
// immobile jammers, so the T1 tower is the answer.
string armjamt("armjamt");
string corjamt("corjamt");
string legjam("legjam");

CCircuitDef@ JammerDef()
{
	return SideDef3(armjamt, corjamt, legjam);
}

// (The line-jammer placement rule died in the overhaul kill; JammerDef stays
// as a def lookup.)

// No suicide raids while the army IS the defence: before the advanced plant, a
// lost raid group is a large share of our whole defence, and losses only
// become replaceable once the economy behind T2 exists.
//
// raid.min is the maxPower of the Defend task raiders sit in before it
// promotes (MilitaryManager.cpp:1696), i.e. the size a raid group leaves at.
// Raising it keeps them home massing instead of trickling out.
//
// Reached via quota.raid.min, NOT the quotaRaidMin shorthand: that shorthand
// is registered in the current C++ source but absent from the deployed
// SkirmishAI.dll, which predates it.
const float JAMMER_COVER = 900.f;
float RAID_MIN_EARLY() { return ai.GetTunable("apex_raid_min_early", TUNE_RAID_MIN_EARLY); }
float gRaidMinStock = -1.f;

//------------------------------------------------------------------------------
// THE APPROACH SENSOR. apexearth 2026-08-19, watching a heavy park outside his
// base: "It is visible long before they even get to our base that they're
// pushing towards our base. Why aren't we preparing for it?" The enemy model
// already tracks the group; nothing converted "closing on home" into a signal.
// Each pass matches known groups to their last sighting and declares a push
// incoming when a group worth real metal has CLOSED distance on our home
// inside the notice radius. Consumed by Builder::PushAnswer, which sites
// defence on the approach line while the walk is still in progress.
//------------------------------------------------------------------------------
array<AIFloat3> gAppPos;
array<float>    gAppDist;
array<int>      gAppSeen;
AIFloat3 gIncomingPos;
float    gIncomingCost = 0.f;
int      gIncomingAt = -999999;
int      gNextApproach = 0;
int      gNextApproachLog = 0;

void UpdateApproach()
{
	if ((ai.frame < gNextApproach) || !Builder::gHomeSet)
		return;
	gNextApproach = ai.frame + 5 * SECOND;
	const float notice = ai.GetTunable("apex_incoming_notice_r", TUNE_INCOMING_NOTICE_R);
	const float minCost = ai.GetTunable("apex_incoming_cost", TUNE_INCOMING_COST);
	const float closingBar = ai.GetTunable("apex_incoming_closing", TUNE_INCOMING_CLOSING);
	const int nG = aiEnemyMgr.GetEnemyGroupCount();
	for (int i = 0; i < nG; ++i) {
		const AIFloat3 p = aiEnemyMgr.GetEnemyGroupPos(i);
		if (!OnMap(p))
			continue;
		const float cost = aiEnemyMgr.GetEnemyGroupCost(i);
		const float d = p.distance2D(Builder::gHomePos);
		if (d > notice)
			continue;
		// DANGER BY REACH, NOT ONLY BY MOTION. A group standing still is
		// dangerous the moment our base edge is inside ITS longest weapon
		// range plus a margin -- apexearth: "some artillery has close to 1500
		// range... it depends on their range." Edge = the nearest of our own
		// defences (the fence ring is the base's measured extent).
		{
			const float edgeD = Military::NearestFenceDist(p);
			const float dEdge = (edgeD < d) ? edgeD : d;
			const float reach = aiEnemyMgr.GetEnemyGroupRange(i)
					+ ai.GetTunable("apex_incoming_danger_pad", TUNE_INCOMING_DANGER_PAD);
			if ((dEdge < reach)
				&& (cost >= ai.GetTunable("apex_incoming_danger_cost", TUNE_INCOMING_DANGER_COST)))
			{
				gIncomingPos = p;
				gIncomingCost = cost;
				gIncomingAt = ai.frame;
				if (ai.frame >= gNextApproachLog) {
					gNextApproachLog = ai.frame + 30 * SECOND;
					AiLog(Factory::T() + "apex: DANGER IN REACH -- "
						+ formatFloat(cost, "", 0, 0) + " metal, range "
						+ formatFloat(reach, "", 0, 0) + ", "
						+ formatFloat(dEdge, "", 0, 0) + " from our edge");
				}
			}
		}
		// Below here is the CLOSING tracker, which is about pushes of real
		// size; the reach clause above has its own smaller bar.
		if (cost < minCost)
			continue;
		// Match against the tracked sightings; the group is the same one if it
		// stands within a step of where one stood last pass.
		int hit = -1;
		for (uint j = 0; j < gAppPos.length(); ++j) {
			if (gAppPos[j].SqDistance2D(p) < 900.f * 900.f) {
				hit = int(j);
				break;
			}
		}
		if (hit < 0) {
			gAppPos.insertLast(p);
			gAppDist.insertLast(d);
			gAppSeen.insertLast(ai.frame);
			continue;
		}
		const float closed = gAppDist[hit] - d;
		gAppPos[hit] = p;
		gAppDist[hit] = d;
		gAppSeen[hit] = ai.frame;
		if (closed > closingBar) {
			gIncomingPos = p;
			gIncomingCost = cost;
			gIncomingAt = ai.frame;
			if (ai.frame >= gNextApproachLog) {
				gNextApproachLog = ai.frame + 30 * SECOND;
				AiLog(Factory::T() + "apex: PUSH INCOMING -- "
					+ formatFloat(cost, "", 0, 0) + " metal at "
					+ formatFloat(d, "", 0, 0) + " from home, closing");
			}
		}
	}
	for (int j = int(gAppSeen.length()) - 1; j >= 0; --j) {
		if (ai.frame - gAppSeen[j] > 60 * SECOND) {
			gAppPos.removeAt(j);
			gAppDist.removeAt(j);
			gAppSeen.removeAt(j);
		}
	}
}

bool PushIncoming()
{
	return (ai.frame - gIncomingAt) < 45 * SECOND;
}

//------------------------------------------------------------------------------
// THE RAID SENSOR: our own buildings dying on our own ground.
//
// Every escalation that was supposed to answer an invasion -- the defence-share
// panic clause, the doubled front budget, the exemption that lets a tower go
// behind the territory centre -- hung on Military::BaseContested(), which asks
// whether the enemy holds NET INFLUENCE over our start position. Measured over
// four runs it reads 0% of samples in three of them and never above 9%: an
// enemy can walk in, kill a T2 lab and leave without it ever being true, because
// our own buildings dominate the influence there. Structure deaths are not
// inferred; AiUnitDestroyed already carries the position and the cost of every
// one, and nothing consumed them.
//
// Deliberately NOT a new spend rule. It sets the same incoming signal the
// approach sensor sets, so Builder::PushAnswer answers it with the tier, the
// siting and the metal sizing it already had -- an answer worth a fraction of
// what is being lost, which stops on its own once the ground is covered.
float RAID_TAU() { return ai.GetTunable("apex_raid_tau", TUNE_RAID_TAU); }
float    gRaidM = 0.f;
AIFloat3 gRaidPos;
int      gRaidAt = -999999;
int      gRaidLast = 0;
int      gNextRaidLog = 0;

void DecayRaid()
{
	const int step = ai.frame - gRaidLast;
	if (step <= 0)
		return;
	gRaidLast = ai.frame;
	float k = 1.f - (float(step) / 30.f) / RAID_TAU();
	if (k < 0.f)
		k = 0.f;
	gRaidM *= k;
}

// A finished structure of ours, killed on home ground. FWD_HOME is the death
// ledger's own line for "died defending home", reused rather than re-invented.
void NoteStructureLoss(const AIFloat3& in at, float costM)
{
	if ((costM <= 0.f) || !OnMap(at) || !Builder::gHomeSet)
		return;
	if (ForwardFraction(at) > FWD_HOME)
		return;
	DecayRaid();
	gRaidM += costM;
	gRaidPos = at;
	gRaidAt = ai.frame;
	// Never weaken a live approach reading: a bigger fight keeps the signal.
	if (!PushIncoming() || (gRaidM > gIncomingCost)) {
		gIncomingPos = gRaidPos;
		gIncomingCost = gRaidM;
		gIncomingAt = ai.frame;
	}
	if (ai.frame >= gNextRaidLog) {
		gNextRaidLog = ai.frame + 20 * SECOND;
		AiLog(Factory::T() + "apex: RAIDED -- lost "
			+ formatFloat(gRaidM, "", 0, 0) + " metal of buildings at "
			+ int(at.x) + "," + int(at.z) + " on our own ground");
	}
}

// Are they in our base killing our things RIGHT NOW. The trigger BaseContested
// was meant to be, read from what we are actually losing.
bool BaseRaided()
{
	if ((ai.frame - gRaidAt) >= 45 * SECOND)
		return false;
	DecayRaid();
	return gRaidM > 0.f;
}

// How badly, as a multiplier, so the escalation is graduated rather than a step:
// structure metal lost on home ground against what our economy makes in the
// same window. Losing a minute of income to a raid doubles the allowance.
float RaidPressure()
{
	if (!BaseRaided())
		return 1.f;
	const float inc = aiEconomyMgr.metal.income;
	if (inc <= 0.5f)
		return 1.f;
	return 1.f + gRaidM / (inc * RAID_TAU());
}

AIFloat3 IncomingPos() { return gIncomingPos; }
float IncomingCost()   { return gIncomingCost; }

}  // namespace Military
