namespace Military {

// A jammer denies the radar that siege artillery needs to shoot at range, so it
// belongs ON the defensive line rather than back beside a fusion, where the two
// existing hubs put it. apexearth: "Jammers need to be part of that defensive
// line. So all this logic that we've built to really shore up our defenses need
// to include a jammer with them. This is what allows us to less easily go under
// siege."
// There is no T2 jammer tower in this game -- corjamt (115m, jam 360),
// armjamt (240m, 500) and legjam (140m, 390) are the only immobile jammers, so
// the T1 tower IS the answer. Cheap enough that one per placed tower is a
// rounding error against a 195-480 metal tower.
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


// No suicide runs while the army IS the defence.
//
// apexearth: "really early in the game, you don't wanna be doing suicide runs.
// Imagine you do a suicide run that fails, and then your army is half size, and
// you fed all that metal or resurrection ability to the enemy. Bam. Now you're
// fucked." A deep strike that trades units for their economy is a good deal
// LATER, when losses are replaceable -- and this AI's whole plan is to make the
// enemy pay by dying on our defences and leaving wrecks, so handing them ours is
// the same mistake in reverse.
//
// raid.min is the maxPower of the Defend task raiders sit in before it promotes
// (MilitaryManager.cpp:1696), i.e. the size a raid group leaves at. Raising it
// keeps them home massing instead of trickling out.
//
// Reached via quota.raid.min, NOT the quotaRaidMin shorthand: that shorthand is
// registered in the current C++ source but is absent from the deployed
// SkirmishAI.dll, which predates it. Source is not the binary.
//
// Keyed on OWNING T2, not on a clock -- apexearth: "usually doing things by time
// is wrong". Before the advanced plant the army is the entire defence and every
// loss is a large share of it; after, there is economy behind it to replace
// what a strike costs.
const float JAMMER_COVER = 900.f;
const float RAID_MIN_EARLY = 45.f;   // hold them home
float gRaidMinStock = -1.f;

}  // namespace Military
