namespace Catalog {

//------------------------------------------------------------------------------
// THE CATALOG (docs/20-brain-overhaul.md step 0). Every def's economics and the
// who-builds-what graph, read ONCE at init from the engine's own def table.
// Data + accessors only: nothing here decides, spends, or enqueues. The Want
// market prices choices by arithmetic over these arrays plus live income.
// Index = def id (1..gDefCount); slot 0 unused.
//------------------------------------------------------------------------------

int gDefCount = 0;
int gEdges = 0;          // who-builds-what edges (builder -> buildable def)

array<float> gCostM;
array<float> gCostE;
array<float> gBuildTime;     // engine build-effort units; seconds = this / buildpower
array<float> gBuildPower;    // engine workertime -- real BP; GetBuildSpeed is overridden by behaviour.json build_speed
array<float> gSpeed;         // elmos/s
array<float> gLosR;          // sight radius, elmos
array<float> gHealth;
array<float> gExtractsM;     // mex extraction fraction
array<float> gUpkeepM;
array<float> gUpkeepE;       // NOTE: includes converter capacity (CircuitDef.cpp adds it)
array<float> gMakeM;         // net metal generation (excl. extraction, excl. conversion)
array<float> gMakeE;         // net energy generation; wind map-averaged, tidal map-scaled
array<float> gStoreM;
array<float> gStoreE;
array<float> gConvCapacity;  // energyconv_capacity, E/s consumed at full load
array<float> gConvRatio;     // energyconv_efficiency, M produced per E consumed
array<bool> gMobile;
array<bool> gFlyer;
array<bool> gBuilder;
array<bool> gWind;
array<bool> gNeedGeo;   // must stand on a geo vent (engine UnitDef flag)
array<bool> gFloater;   // stands on water
array<bool> gAmphib;    // moves through water and land both
array<bool> gSub;       // submerged (underwater structures dodge the floater test)
array<int> gAreaCells;  // footprint in 16-elmo build cells
array<int> gFootX;      // footprint per axis, in 16-elmo build cells
array<int> gFootZ;
// The death explosion, straight off the def. gBlastD is the "default" armour
// entry, which is what a structure of ours standing nearby takes.
array<float> gBlastR;   // area of effect, elmos (0 = does not explode)
array<float> gBlastD;   // damage at the centre
array<float> gBlastE;   // edgeEffectiveness, as the engine's falloff uses it
array<float> gBuildDist; // build/assist reach, elmos
array<bool> gRadar;
array<bool> gJammer;
array<float> gRadarR;
array<float> gJamR;
array<bool> gAntiNuke;   // carries a nuke interceptor
array<bool> gStock;      // stockpile weapon (silos, anti-nukes)
array<bool> gTargFac;    // targeting facility (pinpointer)
array<float> gMaxRange;  // longest weapon reach (0 = unarmed)
array<float> gPower;     // CircuitAI threat value -- combat worth
// COMBAT WORTH AS dps * (hp + shield) (apexearth 2026-08-23: "idk why we
// did that sqrt on the HP but it was a terrible idea ... it should be
// dps * (hp + shield) / some_divisor"). The DLL builds
//   power = sqrt(dps) * dmg^0.25 * sqrt(hp + shield * SHIELD_MOD) / 128
// so power SQUARED is dps * (hp + shield * SHIELD_MOD) * sqrt(dmg) / 128^2
// -- his formula, exactly, apart from a sqrt of per-shot damage. Squaring
// needs nothing and recovers the shield term too.
// The scale is arbitrary: every consumer divides by cost and normalizes
// against the best on the line.
// gPower itself is left alone -- it is also the threat-map number, and the
// defence-turret quality terms are calibrated against its scale.
array<float> gCombat;    // dps * (hp + shield) * sqrt(dmg), i.e. power^2
// The three terms power fuses, now bound separately, so a score can weigh
// them independently instead of only in the DLL's fixed combination.
array<float> gDps;       // sustained damage/s
array<float> gAlpha;     // per-shot damage
array<float> gAoe;       // weapon splash radius (NOT gBlastR, the death blast)
// Can this weapon actually hit something that is MOVING: instant-hit beams and
// rifles, cannons whose shell is fast for their range, and TRACKING missiles.
// A slow un-tracked rocket fails it -- reach it cannot land on a mover is reach
// against buildings only (apexearth: "those reach units were probably the
// terribly inaccurate rocket launcher dudes... only good vs structures").
array<bool> gAimTrue;
// Its longest land weapon is an UNGUIDED rocket -- the precise property; the
// flag above answers "can hit an aircraft", which is a stricter, different bar.
array<bool> gDumbFire;
array<int> gRole;        // CircuitAI main role (raider/riot/assault/...)
array<bool> gKamikaze;   // suicide unit: ammunition, not army
array<bool> gShield;     // projectile shield structure
array<bool> gRezzer;     // can resurrect wrecks
array<float> gSurfT;     // threat vs surface targets
array<float> gAirT;      // threat vs air
array<bool> gAvailable;

array<array<int>> gBuildsList;  // builder def id -> def ids it can build
array<array<int>> gBuiltBy;     // def id -> builder def ids able to build it

bool gInited = false;

void Init()
{
	if (gInited)
		return;
	gInited = true;

	gDefCount = ai.GetDefCount();
	const int n = gDefCount + 1;
	gCostM.resize(n); gCostE.resize(n); gBuildTime.resize(n); gBuildPower.resize(n);
	gSpeed.resize(n); gHealth.resize(n); gExtractsM.resize(n);
	gLosR.resize(n);
	gUpkeepM.resize(n); gUpkeepE.resize(n); gMakeM.resize(n); gMakeE.resize(n);
	gStoreM.resize(n); gStoreE.resize(n); gConvCapacity.resize(n); gConvRatio.resize(n);
	gMobile.resize(n); gFlyer.resize(n); gBuilder.resize(n); gWind.resize(n);
	gNeedGeo.resize(n); gFloater.resize(n); gSub.resize(n); gAreaCells.resize(n); gAmphib.resize(n);
	gFootX.resize(n); gFootZ.resize(n);
	gBlastR.resize(n); gBlastD.resize(n); gBlastE.resize(n);
	gBuildDist.resize(n);
	gRadar.resize(n); gJammer.resize(n); gRadarR.resize(n); gJamR.resize(n);
	gAntiNuke.resize(n); gTargFac.resize(n); gMaxRange.resize(n); gPower.resize(n);
	gStock.resize(n);
	gCombat.resize(n);
	gDps.resize(n); gAlpha.resize(n); gAoe.resize(n);
	gAimTrue.resize(n); gDumbFire.resize(n);
	gSurfT.resize(n); gAirT.resize(n); gRole.resize(n); gKamikaze.resize(n);
	gShield.resize(n); gRezzer.resize(n);
	gAvailable.resize(n);
	gBuildsList.resize(n); gBuiltBy.resize(n);

	for (Id defId = 1; defId <= gDefCount; ++defId) {
		CCircuitDef@ cdef = ai.GetCircuitDef(defId);
		if (cdef is null)
			continue;
		const int i = int(defId);
		gCostM[i]        = cdef.costM;
		gCostE[i]        = cdef.costE;
		gBuildTime[i]    = cdef.GetBuildTime();
		gBuildPower[i]   = cdef.GetWorkerTime();
		gSpeed[i]        = cdef.speed;
		gLosR[i]         = cdef.losRadius;
		gHealth[i]       = cdef.health;
		gExtractsM[i]    = cdef.GetExtractsM();
		gUpkeepM[i]      = cdef.GetUpkeepM();
		gUpkeepE[i]      = cdef.GetUpkeepE();
		gMakeM[i]        = cdef.GetMakeM();
		gMakeE[i]        = cdef.GetMakeE();
		gStoreM[i]       = cdef.GetStoreM();
		gStoreE[i]       = cdef.GetStoreE();
		gConvCapacity[i] = cdef.GetConvertCapacity();
		gConvRatio[i]    = cdef.GetConvertRatio();
		gMobile[i]       = cdef.IsMobile();
		gFlyer[i]        = cdef.IsAbleToFly();
		gBuilder[i]      = cdef.IsBuilder();
		gWind[i]         = cdef.IsWind();
		gNeedGeo[i]      = cdef.IsNeedGeo();
		gFloater[i]      = cdef.IsFloater();
		gAmphib[i]       = cdef.IsAmphibious();
		gSub[i]          = cdef.IsSubmarine();
		gAreaCells[i]    = cdef.GetAreaCells();
		gFootX[i]        = cdef.GetFootX();
		gFootZ[i]        = cdef.GetFootZ();
		gBlastR[i]       = cdef.GetBlastRadius();
		gBlastD[i]       = cdef.GetBlastDamage();
		gBlastE[i]       = cdef.GetBlastEdge();
		gBuildDist[i]    = cdef.GetBuildDistance();
		gRadarR[i]       = cdef.GetRadarRadius();
		gJamR[i]         = cdef.GetJammerRadius();
		// From the RADII, not IsRadarDef/IsJammerDef: the DLL sets those
		// flags only in the immobile branch of its def loop, so every
		// mobile radar and jammer reads false there forever (the reason
		// no Compass was ever produced). A real radar's radius dwarfs any
		// unit's incidental sensor suite.
		// ...but A DEF WITH A GUN IS AN EYE FOR ITSELF, NOT A SENSOR. Pulsar
		// carries a 1500-range dish and Bulwark 1200, so both read as radar
		// towers, went to the radar branch instead of the turret auction, and
		// could never be bought as guns at all -- which is exactly the two
		// heavy defences we were asked why we never build. Same threshold also
		// filed Commandos, Phantoms and battleships as squad escorts.
		const bool armedI = (cdef.GetSurfThreat() + cdef.GetAirThreat()) > 0.01f;
		gRadar[i]        = !armedI && (cdef.IsRadarDef() || (gRadarR[i] > 900.f));
		gJammer[i]       = !armedI && (cdef.IsJammerDef() || (gJamR[i] > 100.f));
		gAntiNuke[i]     = cdef.IsAntiNukeW();
		gStock[i]        = cdef.IsAttrAny(Unit::Attr::STOCK.mask);
		gTargFac[i]      = cdef.IsTargFac();
		gMaxRange[i]     = cdef.GetMaxRange();
		gPower[i]        = cdef.power;
		gCombat[i]       = cdef.power * cdef.power;
		gDps[i]          = cdef.GetRawDps();
		gAlpha[i]        = cdef.GetRawDmg();
		gAoe[i]          = cdef.GetAoe();
		gAimTrue[i]      = cdef.IsAlwaysHitDef();
		gDumbFire[i]     = cdef.IsDumbFireDef();
		gRole[i]         = int(cdef.GetMainRole());
		gKamikaze[i]     = cdef.IsKamikazeDef();
		gShield[i]       = cdef.IsShieldDef();
		gRezzer[i]       = cdef.IsRezAble();
		gSurfT[i]        = cdef.GetSurfThreat();
		gAirT[i]         = cdef.GetAirThreat();
		// NOT IsAvailable(frame): that folds in behaviour.json "since" clocks
		// (leaf-era policy the market must not inherit) and ai.frame is -2 at
		// AiMain anyway. Available = the game ships it and no zero limit.
		gAvailable[i]    = (cdef.maxThisUnit > 0) && !BlockedDef(cdef.GetName());
	}

	// Who-builds-what, both directions. Outer loop is builders only, so this
	// is (builders x defs) CanBuild lookups, once.
	for (Id b = 1; b <= gDefCount; ++b) {
		if (!gBuilder[int(b)])
			continue;
		CCircuitDef@ bdef = ai.GetCircuitDef(b);
		if (bdef is null)
			continue;
		for (Id d = 1; d <= gDefCount; ++d) {
			CCircuitDef@ ddef = ai.GetCircuitDef(d);
			if (ddef is null)
				continue;
			if (bdef.CanBuild(ddef)) {
				gBuildsList[int(b)].insertLast(int(d));
				gBuiltBy[int(d)].insertLast(int(b));
				++gEdges;
			}
		}
	}

	// RETREAT SCALES WITH VALUE (deaths.py over the 40-game anchor: 93% of
	// mobile-combat metal died RETREATING -- the stock 0.6 threshold makes
	// every unit flee at 60% hp and die shot in the back). A cheap unit's
	// last half-life is worth more spent shooting than fleeing; an expensive
	// unit preserves. One derived curve, commander and builders untouched.
	for (Id rd = 1; rd <= gDefCount; ++rd) {
		const int ri = int(rd);
		if (!gMobile[ri] || gBuilder[ri] || (gPower[ri] <= 1.f) || gKamikaze[ri])
			continue;
		CCircuitDef@ rdef = ai.GetCircuitDef(rd);
		if (rdef is null)
			continue;
		float rt = 0.08f + gCostM[ri]
				/ ai.GetTunable("apex_retreat_cost_scale", TUNE_RETREAT_COST_SCALE);
		if (rt > 0.5f)
			rt = 0.5f;
		rdef.SetRetreat(rt);
	}

	int nAvail = 0;
	for (int i = 1; i <= gDefCount; ++i) {
		if (gAvailable[i])
			++nAvail;
	}
	const float dump = ai.GetTunable("apex_catalog_dump", TUNE_CATALOG_DUMP);
	AiLog("apex: catalog init defs=" + gDefCount + " edges=" + gEdges
		+ " avail=" + nAvail + " frame=" + ai.frame
		+ " dump=" + formatFloat(dump, "", 0, 1));

	if (dump > 0.5f)
		Dump();
}

//------------------------------------------------------------------------------
// Accessors and derived helpers -- pure reads.
//------------------------------------------------------------------------------

bool ValidId(int defId)
{
	return (defId >= 1) && (defId <= gDefCount);
}

CCircuitDef@ Def(int defId)
{
	if (!ValidId(defId))
		return null;
	return ai.GetCircuitDef(Id(defId));
}

// Def ids the given builder def can build (empty for non-builders).
const array<int>@ BuildsOf(int builderId)
{
	if (!ValidId(builderId))
		return array<int>();
	return gBuildsList[builderId];
}

// Builder def ids able to build the given def.
const array<int>@ BuildersOf(int defId)
{
	if (!ValidId(defId))
		return array<int>();
	return gBuiltBy[defId];
}

// The cheapest (metal) builder def able to build this def; -1 if none.
int CheapestBuilderOf(int defId)
{
	if (!ValidId(defId))
		return -1;
	int best = -1;
	float bestCost = 0.f;
	const array<int>@ bs = gBuiltBy[defId];
	for (uint i = 0; i < bs.length(); ++i) {
		const int b = bs[i];
		if ((best < 0) || (gCostM[b] < bestCost)) {
			best = b;
			bestCost = gCostM[b];
		}
	}
	return best;
}

// UNITS WE DO NOT KNOW HOW TO USE, blocked at the one chokepoint every want
// already checks -- so no proposer needs to learn about them. Each of these
// carries a weapon and has no build options, so ProtClassOf files it as ground
// defence and the protect want buys it as a turret: a Juno is a one-shot area
// weapon against radar, jammers and minefields, and cortron/armemp are
// operator-aimed tactical missile silos with a manual target order. Neither
// fires usefully without logic that picks and commits a target.
// Lift with apex_allow_juno=1 / apex_allow_tacmissile=1.
bool BlockedDef(const string& in name)
{
	if ((name == "armjuno") || (name == "corjuno") || (name == "legjuno"))
		return ai.GetTunable("apex_allow_juno", 0.f) <= 0.f;
	if ((name == "cortron") || (name == "armemp"))
		return ai.GetTunable("apex_allow_tacmissile", 0.f) <= 0.f;
	return false;
}

// Seconds to build the def at the given total buildpower (workertime sum).
float BuildSecondsAt(int defId, float buildPower)
{
	if (!ValidId(defId) || (buildPower <= 0.f))
		return 1e9f;
	return gBuildTime[defId] / buildPower;
}

// Net energy of a converter running at full load: consumes capacity E/s,
// yields capacity*ratio M/s. Zero for non-converters.
float ConvertMakeM(int defId)
{
	return ValidId(defId) ? gConvCapacity[defId] * gConvRatio[defId] : 0.f;
}

//------------------------------------------------------------------------------
// Guarded dump: one line per AVAILABLE def, for tools/check_catalog.py.
//------------------------------------------------------------------------------

void Dump()
{
	for (int i = 1; i <= gDefCount; ++i) {
		if (!gAvailable[i])
			continue;
		CCircuitDef@ cdef = ai.GetCircuitDef(Id(i));
		if (cdef is null)
			continue;
		AiLog("apex: catalog " + cdef.GetName()
			+ " mCost=" + formatFloat(gCostM[i], "", 0, 1)
			+ " eCost=" + formatFloat(gCostE[i], "", 0, 1)
			+ " bt=" + formatFloat(gBuildTime[i], "", 0, 1)
			+ " bp=" + formatFloat(gBuildPower[i], "", 0, 1)
			+ " makeM=" + formatFloat(gMakeM[i], "", 0, 2)
			+ " makeE=" + formatFloat(gMakeE[i], "", 0, 2)
			+ " upkeepE=" + formatFloat(gUpkeepE[i], "", 0, 2)
			+ " storeM=" + formatFloat(gStoreM[i], "", 0, 1)
			+ " storeE=" + formatFloat(gStoreE[i], "", 0, 1)
			+ " convCap=" + formatFloat(gConvCapacity[i], "", 0, 1)
			+ " convRatio=" + formatFloat(gConvRatio[i], "", 0, 5)
			+ " extractsM=" + formatFloat(gExtractsM[i], "", 0, 4)
			+ " mob=" + (gMobile[i] ? 1 : 0)
			+ " fly=" + (gFlyer[i] ? 1 : 0)
			+ " wind=" + (gWind[i] ? 1 : 0)
			+ " amph=" + (gAmphib[i] ? 1 : 0)
			+ " sub=" + (gSub[i] ? 1 : 0)
			+ " float=" + (gFloater[i] ? 1 : 0)
			+ " power=" + formatFloat(gPower[i], "", 0, 1)
			+ " surfT=" + formatFloat(gSurfT[i], "", 0, 1)
			+ " airT=" + formatFloat(gAirT[i], "", 0, 1)
			+ " combat=" + formatFloat(gCombat[i], "", 0, 1)
			+ " dps=" + formatFloat(gDps[i], "", 0, 2)
			+ " alpha=" + formatFloat(gAlpha[i], "", 0, 1)
			+ " aoe=" + formatFloat(gAoe[i], "", 0, 1)
			+ " aim=" + (gAimTrue[i] ? 1 : 0)
			+ " dumb=" + (gDumbFire[i] ? 1 : 0)
			+ " rng=" + formatFloat(gMaxRange[i], "", 0, 0)
			+ " hp=" + formatFloat(gHealth[i], "", 0, 0)
			+ " role=" + gRole[i]
			+ " builds=" + gBuildsList[i].length());
	}
}

}  // namespace Catalog
