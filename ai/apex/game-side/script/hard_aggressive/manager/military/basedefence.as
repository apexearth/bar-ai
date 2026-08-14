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

}  // namespace Military
