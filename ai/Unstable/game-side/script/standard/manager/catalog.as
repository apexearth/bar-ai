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
	gUpkeepM.resize(n); gUpkeepE.resize(n); gMakeM.resize(n); gMakeE.resize(n);
	gStoreM.resize(n); gStoreE.resize(n); gConvCapacity.resize(n); gConvRatio.resize(n);
	gMobile.resize(n); gFlyer.resize(n); gBuilder.resize(n); gWind.resize(n);
	gNeedGeo.resize(n); gFloater.resize(n);
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
		// NOT IsAvailable(frame): that folds in behaviour.json "since" clocks
		// (leaf-era policy the market must not inherit) and ai.frame is -2 at
		// AiMain anyway. Available = the game ships it and no zero limit.
		gAvailable[i]    = cdef.maxThisUnit > 0;
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
			+ " builds=" + gBuildsList[i].length());
	}
}

}  // namespace Catalog
