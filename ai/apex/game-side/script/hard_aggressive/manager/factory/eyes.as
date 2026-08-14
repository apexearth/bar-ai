namespace Factory {

// Mobile radar for units whose guns outrange their own LOS. The escort itself
// is stock and correct (radar/jammer carry role "support", CSupportTask joins
// the nearest squad) -- what was missing is the unit: these sit at 0.00-0.05 in
// factory.json's ratios against 0.40 for the guns they'd spot for. Recruited
// directly here, same as LateRadarPlane.

// Which defs are "blind guns" is DERIVED rather than listed: GetMaxRange() and
// losRadius are both bound, so the set is read off the unit defs at runtime and
// covers all three factions, every terrain block, and anything added later.
const float EYES_GAP       = 1.6f;    // range/los above which a gun is blind
const float EYES_MIN_RANGE = 650.f;   // below this the gap is not worth paying for
const float EYES_MAX_RANGE = 3000.f;  // anti-ship missiles carry range 72000

const int EYES_PER_RADAR = 5;   // blind guns fielded per mobile radar wanted
// No ceiling: scales with blind-gun count all the way up.
const int EYES_PER_JAM   = 10;  // the jammer is the second-order want
// No ceiling on jammers either, same reason as the radar above.
const int EYES_SPACING   = 30 * SECOND;

int gNextEyes = 0;
bool gEyesScanned = false;
array<int> gBlindGun;

void ScanBlindGuns()
{
	gEyesScanned = true;
	for (Id defId = 1, count = ai.GetDefCount(); defId <= count; ++defId) {
		CCircuitDef@ cdef = ai.GetCircuitDef(defId);
		if ((cdef is null) || !cdef.IsMobile() || cdef.IsAbleToFly())
			continue;
		// AA shoots what radar has already found, the commander carries its own
		// radar (700 against 450 sight), and a builder is not a gun.
		if (cdef.IsRoleAny(Unit::Role::AA.mask | Unit::Role::COMM.mask
				| Unit::Role::BUILDER.mask | Unit::Role::SUPPORT.mask))
			continue;
		const float range = cdef.GetMaxRange();
		if ((range < EYES_MIN_RANGE) || (range > EYES_MAX_RANGE))
			continue;
		if ((cdef.losRadius > NEAR_ZERO) && (range > cdef.losRadius * EYES_GAP))
			gBlindGun.insertLast(defId);
	}
}

int BlindGunCount()
{
	if (!gEyesScanned)
		ScanBlindGuns();
	int n = 0;
	for (uint i = 0; i < gBlindGun.length(); ++i) {
		CCircuitDef@ cdef = ai.GetCircuitDef(gBlindGun[i]);
		if (cdef !is null)
			n += cdef.count;
	}
	return n;
}

// Named per factory rather than by role: radar, jammer and the assist bot all
// carry role "support", so GetRoleDef(SUPPORT) can't tell them apart (same
// reason RezBotDef names its defs). Naval is excluded -- a T2 ship already
// carries its own radar, so a shipyard has nothing to fix here.
CCircuitDef@ EyeDefFor(const CCircuitDef@ facDef, bool jammer)
{
	if (facDef is null)
		return null;
	const string fac = facDef.GetName();
	string radar, jam;
	if      (fac == armalab) { radar = "armmark";  jam = "armaser";  }
	else if (fac == coralab) { radar = "corvoyr";  jam = "corspec";  }
	else if (fac == legalab) { radar = "legaradk"; jam = "legajamk"; }
	else if (fac == armavp)  { radar = "armseer";  jam = "armjam";   }
	else if (fac == coravp)  { radar = "corvrad";  jam = "coreter";  }
	else if (fac == legavp)  { radar = "legavrad"; jam = "legavjam"; }
	else                     { return null; }
	if (jammer)
		return ai.GetCircuitDef(jam);
	return ai.GetCircuitDef(radar);
}

IUnitTask@ EyesForTheGuns(CCircuitUnit@ unit)
{

	// Gated on guns already in the field, so this cannot displace the opening
	// or the tech rush: the units it serves are T2 and it needs five of them.
	const int guns = BlindGunCount();
	if (guns < EYES_PER_RADAR)
		return null;

	int want = guns / EYES_PER_RADAR;
	CCircuitDef@ eye = EyeDefFor(unit.circuitDef, false);
	bool haveRadar = (eye !is null) && (eye.count >= want);

	if ((eye is null) || haveRadar || !eye.IsAvailable(ai.frame)) {
		// The jammer only earns its slot once the radar is already out there:
		// it denies the enemy's targeting, which matters after we can see.
		want = guns / EYES_PER_JAM;
		@eye = EyeDefFor(unit.circuitDef, true);
		if ((eye is null) || (eye.count >= want) || !eye.IsAvailable(ai.frame))
			return null;
	}

	IUnitTask@ rec = aiFactoryMgr.Enqueue(TaskS::Recruit(
			Task::RecruitType::FIREPOWER, Task::Priority::NORMAL,
			eye, unit.GetPos(ai.frame), 0.f));
	if (rec is null)
		return null;

	gNextEyes = ai.frame + EYES_SPACING;
	AiLog(T() + "apex: eyes-for-the-guns " + eye.GetName()
		+ " standing=" + eye.count + " blindGuns=" + guns
		+ " blindDefs=" + int(gBlindGun.length()));
	return rec;
}

}  // namespace Factory
