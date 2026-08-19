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

// One jammer per tower placed on the line, so the cover grows with the line
// instead of being a single point the enemy can shoot out.
void PlaceLineJammer(const AIFloat3& in spot)
{
	CCircuitDef@ jam = JammerDef();
	if ((jam is null) || !jam.IsAvailable(ai.frame))
		return;
	// One per tower on the line. This counted against gPorcAdded, which belonged
	// to the deleted base-defence rule and is now permanently zero -- which would
	// have capped us at a single jammer for the whole game. The line's own tower
	// count is the honest bound.
	if (int(jam.count) >= int(FenceCountNear(spot, JAMMER_COVER)) )
		return;
	// Behind the tower it covers: the jammer is the thing being protected.
	AIFloat3 back = spot;
	if (Builder::gHomeSet) {
		const float dx = Builder::gHomePos.x - spot.x;
		const float dz = Builder::gHomePos.z - spot.z;
		const float len = sqrt(dx * dx + dz * dz);
		if (len > 1.f) {
			back.x += dx / len * JAMMER_BACK;
			back.z += dz / len * JAMMER_BACK;
		}
	}
	if (!OnMap(back))
		return;
	// No builder in hand: this places the order for whoever the engine elects,
	// and gets the same one-order-per-patch-of-ground protection.
	bool created = false;
	Requests::Take(null, jam, Task::BuildType::DEFENCE,
			Task::Priority::NORMAL, back, 0.f, SQUARE_SIZE * 16, created);
	if (created) {
		AiLog(Factory::T() + "apex: line-jammer " + jam.GetName()
			+ " standing=" + jam.count);
	}
}


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
const float RAID_MIN_EARLY = 45.f;   // hold them home
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
	const float notice = ai.GetTunable("apex_push_notice_r", 4500.f);
	const float minCost = ai.GetTunable("apex_push_cost", 2500.f);
	const float closingBar = ai.GetTunable("apex_push_closing", 150.f);
	const int nG = aiEnemyMgr.GetEnemyGroupCount();
	for (int i = 0; i < nG; ++i) {
		const AIFloat3 p = aiEnemyMgr.GetEnemyGroupPos(i);
		if (!OnMap(p))
			continue;
		const float cost = aiEnemyMgr.GetEnemyGroupCost(i);
		if (cost < minCost)
			continue;
		const float d = p.distance2D(Builder::gHomePos);
		if (d > notice)
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

AIFloat3 IncomingPos() { return gIncomingPos; }
float IncomingCost()   { return gIncomingCost; }

}  // namespace Military
