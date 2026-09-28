namespace Market {
array<int> gOwnCount;   // finished units we own, by def id
// Bumped on every change; gOwnSetStamp only when a def crosses zero. The
// derived walks below are functions of one or the other plus the static
// catalog, so a stamp match means the answer cannot have moved.
int gOwnStamp = 0;
int gOwnSetStamp = 0;
void OwnAdd(int defId, int delta)
{
	if (gOwnCount.length() == 0)
		gOwnCount.resize(Catalog::gDefCount + 1);
	if ((defId >= 1) && (defId < int(gOwnCount.length()))) {
		const bool had = (gOwnCount[defId] > 0);
		gOwnCount[defId] += delta;
		if (gOwnCount[defId] < 0)
			gOwnCount[defId] = 0;
		++gOwnStamp;
		if (had != (gOwnCount[defId] > 0))
			++gOwnSetStamp;
	}
}

// Assist build power standing over the plants, as a fraction of the plants'
// own. A factory line's throughput is its workertime plus whatever nano
// turrets reach it; which turret serves which line is not tracked, so the
// pool is shared evenly -- the queue only has to outlast the re-election gap,
// and an even share is enough to size one with.
int gAssistShareAt = -1;
float gAssistShare = 0.f;
float AssistBPShare()
{
	if (gAssistShareAt == ai.frame)
		return gAssistShare;
	gAssistShareAt = ai.frame;
	float plant = 0.f;
	float assist = 0.f;
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		const int n = gOwnCount[d];
		if ((n <= 0) || Catalog::gMobile[int(d)] || !Catalog::gBuilder[int(d)])
			continue;
		const float bp = Catalog::gBuildPower[int(d)] * float(n);
		if (Catalog::BuildsOf(int(d)).length() > 0)
			plant += bp;
		else
			assist += bp;
	}
	gAssistShare = (plant > 0.f) ? (assist / plant) : 0.f;
	return gAssistShare;
}

// The extraction our standing capability can already reach: any owned mobile
// builder directly, or any owned factory through the builders it can make.
// This is what the tech want measures unlock against -- the ASKER's own
// reach read a T1 con as needing a T2 lab we already had three of.
// THE BEST ENERGY PER METAL ANY CONSTRUCTOR WE ACTUALLY OWN COULD PUT DOWN.
//
// ProposeEnergy only ever sees the ASKER's own build options, so a commander --
// which builds armsolar and cannot build armadvsol at all (that is lvl3+, or any
// armck/armcv/armca) -- prices a basic solar against nothing and wins with it.
// apexearth: "workers should not build inferior work. They're smarter to apply
// their build power to better buildings."
//
// Standing MOBILE builders only, deliberately: a factory that could one day
// produce a con that could build advanced solars is not somebody who can do
// this better right now, and counting it would discount the opening's energy to
// nothing. With only the commander alive the best IS a solar, the ratio is 1,
// and nothing changes.
int gBestEPMAt = -1;
float gBestEPM = 0.f;
float OwnedBestEPerM()
{
	if (gBestEPMAt == ai.frame)
		return gBestEPM;
	gBestEPMAt = ai.frame;
	gBestEPM = 0.f;
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		if ((gOwnCount[d] <= 0) || !Catalog::gMobile[int(d)])
			continue;
		const array<int>@ builds = Catalog::gBuildsList[int(d)];
		for (uint i = 0; i < builds.length(); ++i) {
			const int b = builds[i];
			if (!Catalog::gAvailable[b] || Catalog::gMobile[b]
				|| Catalog::gNeedGeo[b] || (Catalog::gMakeE[b] <= 1.f)
				|| (Catalog::gCostM[b] <= 0.f))
				continue;
			const float epm = Catalog::gMakeE[b] / Catalog::gCostM[b];
			if (epm > gBestEPM)
				gBestEPM = epm;
		}
	}
	return gBestEPM;
}

// THE COSTLIEST MOBILE UNIT ANYTHING WE OWN CAN PRODUCE. Paired with
// ai.GetEnemyMaxMobileCostM(), this says whether their best outclasses ours --
// a tier comparison drawn from cost rather than from a named tier, so it needs
// no table and works for any faction or unit the game adds.
int gBestMobAt = -1;
float gBestMob = 0.f;
float OwnedBestMobileCostM()
{
	if (gBestMobAt == ai.frame)
		return gBestMob;
	gBestMobAt = ai.frame;
	gBestMob = 0.f;
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		if (gOwnCount[d] <= 0)
			continue;
		const array<int>@ builds = Catalog::gBuildsList[int(d)];
		for (uint i = 0; i < builds.length(); ++i) {
			const int b = builds[i];
			if (!Catalog::gAvailable[b] || !Catalog::gMobile[b]
				|| Catalog::gBuilder[b])
				continue;
			if (Catalog::gCostM[b] > gBestMob)
				gBestMob = Catalog::gCostM[b];
		}
	}
	return gBestMob;
}

// The three ceilings below and CanBuildEver read only WHICH defs we own, never
// how many, so one refresh per ownership-set change serves every caller.
int gCeilStamp = -1;
float gOwnedCeil = 0.f;
float gOwnedProdCeil = 1.f;
float gOwnedMobCeil = 0.f;
array<bool> gCanBuild;
void RefreshOwnedSet()
{
	if (gCeilStamp == gOwnSetStamp)
		return;
	gCeilStamp = gOwnSetStamp;
	if (int(gCanBuild.length()) <= Catalog::gDefCount)
		gCanBuild.resize(Catalog::gDefCount + 1);
	for (uint k = 0; k < gCanBuild.length(); ++k)
		gCanBuild[k] = false;
	gOwnedCeil = 0.f;
	gOwnedMobCeil = 0.f;
	float prodCeil = 0.f;
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		if (gOwnCount[d] <= 0)
			continue;
		const array<int>@ builds = Catalog::gBuildsList[int(d)];
		if (Catalog::gMobile[int(d)]) {
			for (uint i = 0; i < builds.length(); ++i) {
				const int b = builds[i];
				if ((b >= 0) && (b < int(gCanBuild.length())))
					gCanBuild[b] = true;
				if (Catalog::gExtractsM[b] > gOwnedCeil)
					gOwnedCeil = Catalog::gExtractsM[b];
				if (Catalog::gExtractsM[b] > gOwnedMobCeil)
					gOwnedMobCeil = Catalog::gExtractsM[b];
			}
			continue;
		}
		// A standing factory reaches what its producible builders reach.
		for (uint i = 0; i < builds.length(); ++i) {
			const int pd = builds[i];
			if (Catalog::gMobile[pd] && (Catalog::gCostM[pd] > prodCeil))
				prodCeil = Catalog::gCostM[pd];
			if (!Catalog::gMobile[pd] || !Catalog::gBuilder[pd])
				continue;
			const array<int>@ pb = Catalog::gBuildsList[pd];
			for (uint q = 0; q < pb.length(); ++q) {
				const int b2 = pb[q];
				if ((b2 >= 0) && (b2 < int(gCanBuild.length())))
					gCanBuild[b2] = true;
				if (Catalog::gExtractsM[b2] > gOwnedCeil)
					gOwnedCeil = Catalog::gExtractsM[b2];
			}
		}
	}
	gOwnedProdCeil = (prodCeil > 1.f) ? prodCeil : 1.f;
}

float OwnedCeil()
{
	RefreshOwnedSet();
	return gOwnedCeil;
}

// Can anything we own put this def on the ground -- directly, or through a
// standing factory's constructors? A price anchored on a unit nobody can build
// is not a price. Asked once per candidate def inside catalog-wide loops
// (eta's PoolFill, EPriceFloor), so it is a table lookup, not a walk.
bool CanBuildEver(int defId)
{
	RefreshOwnedSet();
	return ((defId >= 0) && (defId < int(gCanBuild.length()))) && gCanBuild[defId];
}

// Mobile builders we own whose reach hits the game's extraction ceiling --
// the fleet already serving upgrade demand. Counts, not just the owned set, so
// it rides gOwnStamp.
int gServingStamp = -1;
int gServingCons = 0;
int ServingCons()
{
	const float ceilX = BestExtract();
	// NEVER LATCH A ZERO CEILING: BestExtract latches only once positive, and
	// at ceilX == 0 every build option passes, so a cache taken then reads
	// every mobile builder as serving for the rest of that stamp.
	if ((gServingStamp == gOwnStamp) && (ceilX > 0.f))
		return gServingCons;
	gServingStamp = (ceilX > 0.f) ? gOwnStamp : -1;
	int nServing = 0;
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		if ((gOwnCount[d] <= 0) || !Catalog::gMobile[int(d)] || !Catalog::gBuilder[int(d)])
			continue;
		const array<int>@ builds = Catalog::gBuildsList[int(d)];
		for (uint i = 0; i < builds.length(); ++i) {
			if (Catalog::gExtractsM[builds[i]] >= ceilX) {
				nServing += gOwnCount[d];
				break;
			}
		}
	}
	gServingCons = nServing;
	return nServing;
}

// The costliest mobile unit our standing factories can produce.
float OwnedProdCostCeil()
{
	RefreshOwnedSet();
	return gOwnedProdCeil;
}

float OwnedMobileCeil()
{
	RefreshOwnedSet();
	return gOwnedMobCeil;
}

// Own standing generators, for the obsolete-reclaim want. NOCOUNT handles:
// every entry MUST leave via NoteDead.
array<CCircuitUnit@> gOwnGen;
array<Id> gOwnGenIds;
// Converters are ECO STRUCTURES THAT OCCUPY GROUND, and gOwnGen holds only
// things that MAKE energy -- so a T1 converter was never a reclaim candidate
// at all, whatever stood next to it (apexearth 2026-08-27: "we have wind,
// advanced solar, and T1 converters all over the place not being reclaimed...
// we have no space").
array<CCircuitUnit@> gOwnConv;
array<Id> gOwnConvIds;
// High-value structures (labs, fusions, gantries...): each deserves its
// own turret ring (apexearth: "so shit at protecting important buildings
// like T2 -- 2700 metal investment dying").
array<CCircuitUnit@> gOwnBig;
array<Id> gOwnBigIds;

// The protection ledger: what stands where, per coverage class, plus the
// total structure value at risk. PROT_* index the class arrays.
const int PROT_RADAR = 0;
const int PROT_JAM = 1;
const int PROT_ANTINUKE = 2;
const int PROT_TARGFAC = 3;
const int PROT_DEF = 4;
const int PROT_SHIELD = 5;
const int PROT_AA = 6;
// Strategic statics: nuke silos and long-range guns. Kept out of PROT_DEF
// because the ground-defence auction reads a class member's gMaxRange as a
// coverage radius, and a silo reports 72,000 elmos.
const int PROT_SUPER = 7;
const int PROT_N = 8;
array<array<AIFloat3>> gProtPos(PROT_N);
array<array<Id>> gProtIds(PROT_N);
array<array<CCircuitUnit@>> gProtUnit(PROT_N);
array<array<int>> gProtDefId(PROT_N);
float gAssetsM = 0.f;   // summed costM of standing structures
// ...of which this much is PROTECTION. Defence must never be its own reason:
// the siege prior mirrors our economy into their army, so counting turrets in
// that basis made every turret raise the threat that justified the next one
// (apexearth: "our entire defence lineup is probably also going into that? So
// defences required even more defences to protect the defences").
float gProtM = 0.f;
// ...and of which this much is standing LATHE. Same law as gProtM one line up,
// for the same reason: build power is an answer to demand, not wealth that
// attracts an attack, and counting it made every nano turret raise the army
// target that bought the next one -- while builders are excluded from
// ArmyValue, so a turret can never close the gap it widens.
float gBPM = 0.f;

// A standing structure whose whole job is build power: immobile, has worker
// time, builds nothing of its own (a factory has build options, a nano does
// not).
bool IsLatheDef(int defId)
{
	return !Catalog::gMobile[defId] && (Catalog::gBuildPower[defId] > 0.f)
			&& (Catalog::gBuildsList[defId].length() == 0);
}

// PURE IN THE DEF ID, so it is answered from a table. Every input is a static
// catalog column plus IsSuperWeapon's light-tower reach, which latches with the
// def table -- and this is asked once per standing structure per protect pass,
// once per candidate in the protect market, and on every finish and death.
// Stored as class+2 so 0 means "not computed" and -1 (not protection) fits.
// Nothing is written before the light tower is readable: until then
// IsSuperWeapon compares against the 430 fallback, which is not the answer.
array<int> gProtClass;

int ProtClassCompute(int defId)
{
	// A factory is never protection: armaap carries radarDistance 1000, and
	// the sense market bought it as a radar.
	if (Catalog::gBuildsList[defId].length() > 0)
		return -1;
	if (Catalog::gShield[defId] && !Catalog::gMobile[defId]) return PROT_SHIELD;
	if (Catalog::gAntiNuke[defId]) return PROT_ANTINUKE;
	if (IsSuperWeapon(defId)) return PROT_SUPER;
	if (Catalog::gTargFac[defId]) return PROT_TARGFAC;
	if (Catalog::gRadar[defId]) return PROT_RADAR;
	if (Catalog::gJammer[defId]) return PROT_JAM;
	// AN ARMED EXTRACTOR IS ECONOMY, NOT DEFENCE. corexp ("Exploiter", an
	// Armed Metal Extractor) has a weapon, no build options and does not move,
	// so it filed as ground defence and the protect market bought it as a
	// turret -- 299 of 397 defence placements in one 12-game batch, sited by
	// defence value rather than on a metal spot. Same shape as the Juno bug.
	// Extraction makes it the mex want's business.
	if (Catalog::gExtractsM[defId] > 0.f)
		return -1;
	if ((Catalog::gMaxRange[defId] > 1.f) && !Catalog::gMobile[defId]
		&& !Catalog::gBuilder[defId] && (Catalog::gBuildsList[defId].length() == 0))
	{
		// A ground-shooting weapon is ground defence; a mainly-air one is AA and
		// gets its own class. AA used to fall out of ProtClassOf entirely (-1),
		// which is why nothing ever bought a single anti-air tower -- apexearth,
		// watching: "we don't make AA when we're getting bombed."
		if (Catalog::gSurfT[defId] > 0.5f * Catalog::gAirT[defId])
			return PROT_DEF;   // AA never counts as ground coverage (watched: AA at mexes)
		// A torpedo launcher's only weapon hits IN the water: surface and air
		// threat both read 0, so it filed as nothing and was never bought
		// (his watch 2026-09-28: "why is it so hard to build a torpedo launcher").
		if ((Catalog::gWaterT[defId] > 0.01f) && (Catalog::gAirT[defId] <= 0.f))
			return PROT_DEF;
		if (Catalog::gAirT[defId] > 0.f)
			return PROT_AA;
	}
	return -1;
}

int ProtClassOf(int defId)
{
	if ((defId >= 0) && (defId < int(gProtClass.length()))
		&& (gProtClass[defId] != 0))
	{
		return gProtClass[defId] - 2;
	}
	// The memo's own instrument: once the table is warm this counter stops
	// climbing, and every ProtClassOf above it is a single array read.
	Perf::Note("prot.class.miss");
	const int c = ProtClassCompute(defId);
	// Asked here too: LightTowerRange is what LATCHES the reach IsSuperWeapon
	// compares against, and a def that exits early above never reaches it.
	const bool ready = (Brain::LightTowerRange() > 0.f) && Brain::LightTowerReady();
	if ((defId >= 1) && (defId <= Catalog::gDefCount) && ready) {
		if (int(gProtClass.length()) <= Catalog::gDefCount)
			gProtClass.resize(Catalog::gDefCount + 1);
		gProtClass[defId] = c + 2;
	}
	return c;
}

// When each of our STRUCTURES finished, by unit id -- the age gate that stops
// obsolete-reclaim eating a thing the market paid for minutes ago. 0 = unknown
// (born before this record, or id past the cap), which reads as old enough.
array<int> gBuiltFrame(32001, 0);
int BuiltFrameOf(CCircuitUnit@ u)
{
	const int id = int(u.id);
	return ((id >= 0) && (id < int(gBuiltFrame.length()))) ? gBuiltFrame[id] : 0;
}

void NoteFinished(CCircuitUnit@ unit)
{
	if (unit is null)
		return;
	const int defId = int(unit.circuitDef.id);
	OwnAdd(defId, 1);
	if (!Catalog::gMobile[defId] && (int(unit.id) >= 0)
		&& (int(unit.id) < int(gBuiltFrame.length())))
		gBuiltFrame[int(unit.id)] = (ai.frame > 0) ? ai.frame : 1;
	Lattice::NotePlaced(defId, unit.GetPos(ai.frame), unit.id);
	NoteSquatter(unit);
	if (!Catalog::gMobile[defId] && (Catalog::gMakeE[defId] > 1.f)
		&& !Catalog::gNeedGeo[defId])
	{
		gOwnGen.insertLast(unit);
		gOwnGenIds.insertLast(unit.id);
	}
	if (!Catalog::gMobile[defId] && (Catalog::gConvCapacity[defId] > 1.f)) {
		gOwnConv.insertLast(unit);
		gOwnConvIds.insertLast(unit.id);
	}
	if (!Catalog::gMobile[defId]) {
		gAssetsM += Catalog::gCostM[defId];
		if (ProtClassOf(defId) >= 0)
			gProtM += Catalog::gCostM[defId];
		if (IsLatheDef(defId))
			gBPM += Catalog::gCostM[defId];
	}
	if (!Catalog::gMobile[defId] && (Catalog::gCostM[defId] >= 1200.f)) {
		gOwnBig.insertLast(unit);
		gOwnBigIds.insertLast(unit.id);
	}
	// STATIC PROTECTION ONLY. gProtPos records a FIXED position, and
	// ProtClassOf answers PROT_RADAR/PROT_JAM for radar and jammer BOTS too --
	// so a mobile radar was recorded at the spot it rolled off the line and
	// RadarSees treated that factory apron as permanent coverage for the rest
	// of the game, suppressing every real radar tower near it.
	const int pc = Catalog::gMobile[defId] ? -1 : ProtClassOf(defId);
	if (pc >= 0) {
		gProtPos[pc].insertLast(unit.GetPos(ai.frame));
		gProtIds[pc].insertLast(unit.id);
		gProtUnit[pc].insertLast(unit);
		gProtDefId[pc].insertLast(defId);
	}
	if (Catalog::gExtractsM[defId] <= 0.f)
		return;
	const AIFloat3 mp = unit.GetPos(ai.frame);
	int i = LedgerNearest(mp);
	// No row: the mex under this moho died first and took it (BAR's
	// mex_upgrade_reclaimer; the death handler keeps the row only when the
	// moho's finish came first). The spot is ours, so it is re-entered.
	if (i < 0) {
		CacheSpots();
		for (uint s = 0; s < gAllSpots.length(); ++s) {
			if (gAllSpots[s].distance2D(mp) < 150.f) {
				LedgerClaim(int(s), gAllSpots[s], aiEconomyMgr.GetMexSpotIncome(int(s)));
				i = LedgerFind(int(s));
				break;
			}
		}
	}
	if (i >= 0)
		gLExtract[i] = Catalog::gExtractsM[defId];
}
// Fallback anchor: the first finished nano, only if no plan latched first.
array<AIFloat3> gOwnNanoPos;
array<Id> gOwnNanoIds;
array<float> gOwnNanoReach;
array<float> gOwnNanoBP;
// The handles, for the retirement market: the other three are read by position.
array<CCircuitUnit@> gOwnNano;
// Last frame the turret was seen spending anything (lift.as samples it).
array<int> gOwnNanoWorkAt;

// THE TURRET CENSUS, BUCKETED. NanoLatheReaching and RingBPAt walked every
// standing turret, and Requests::Take asks NanoFed once per live request, so
// their cost was (asks) x (turrets) -- and apexearth has watched a single
// cluster of 217. Same discipline as the commitment ledger: a death removes by
// index and shifts everything after it, so the grid is thrown away and the next
// query rebuilds it; a new turret appends, which shifts nothing and goes in
// directly. A turret moves only by air (lift.as), which drops the grid too.
Grid::Cells gNanoGrid;
bool gNanoGridDirty = true;
uint gNanoGridN = 0;
float gNanoGridMaxReach = 0.f;

void NanoGridDrop()
{
	gNanoGridDirty = true;
}

void NanoGridBuild()
{
	if (!gNanoGridDirty && (gNanoGridN == gOwnNanoPos.length()))
		return;
	gNanoGrid.Begin(256.f, 0.f, 0.f,
			float(AiTerrainWidth()), float(AiTerrainHeight()));
	gNanoGridMaxReach = 0.f;
	for (uint i = 0; i < gOwnNanoPos.length(); ++i) {
		gNanoGrid.Add(gOwnNanoPos[i].x, gOwnNanoPos[i].z);
		const float r = (i < gOwnNanoReach.length()) ? gOwnNanoReach[i] : 400.f;
		if (r > gNanoGridMaxReach)
			gNanoGridMaxReach = r;
	}
	gNanoGridN = gOwnNanoPos.length();
	gNanoGridDirty = false;
}

void NanoGridAppend()
{
	if (gNanoGridDirty || (gNanoGridN + 1 != gOwnNanoPos.length())) {
		gNanoGridDirty = true;
		return;
	}
	const uint i = gNanoGridN;
	gNanoGrid.Add(gOwnNanoPos[i].x, gOwnNanoPos[i].z);
	const float r = (i < gOwnNanoReach.length()) ? gOwnNanoReach[i] : 400.f;
	if (r > gNanoGridMaxReach)
		gNanoGridMaxReach = r;
	gNanoGridN = gOwnNanoPos.length();
}

// The longest build reach any standing turret has. Through the build, because a
// stale-LOW reach is a query that misses a turret the walk would have found.
float NanoMaxReach()
{
	NanoGridBuild();
	return gNanoGridMaxReach;
}

// Turrets within the box of half-extent `r` around `at`, left in gNanoGrid.hit
// as indices into gOwnNanoPos. A superset; the caller's own reach test decides.
void NanoNear(const AIFloat3 &in at, float r)
{
	NanoGridBuild();
	gNanoGrid.Query(at.x, at.z, r);
}

void NoteFarm(CCircuitUnit@ unit)
{
	if (unit is null)
		return;
	const int d = int(unit.circuitDef.id);
	// A finished FACTORY reserves its apron: three posts of open ground in
	// front so units can get out (apexearth -- the walled-in vehicle lab).
	if (!Catalog::gMobile[d] && (Catalog::gBuildsList[d].length() > 0)
		&& Base::gAxisSet)
	{
		const AIFloat3 fp0 = unit.GetPos(ai.frame);
		for (int ap = 1; ap <= 3; ++ap)
			Base::ReserveSite(fp0 + Base::gFwd * (80.f * float(ap)));
	}
	if (Catalog::gMobile[d] || (Catalog::gBuildPower[d] <= 0.f)
		|| (Catalog::gBuildsList[d].length() > 0))
	{
		return;
	}
	// A nano without a patrol order does NOTHING (apexearth 2026-08-23:
	// "give them a patrol order after they are created. Then they will do
	// work" -- the player's 'stop' shortcut). Patrol to a nearby point;
	// auto-assist/repair/reclaim in range follows.
	AIFloat3 p = unit.GetPos(ai.frame);
	p.x += 48.f;
	p.z += 48.f;
	unit.CmdPatrolTo(p);
	gOwnNanoPos.insertLast(unit.GetPos(ai.frame));
	gOwnNanoIds.insertLast(unit.id);
	gOwnNanoReach.insertLast(Catalog::gBuildDist[d]);
	gOwnNanoBP.insertLast(Catalog::gBuildPower[d]);
	gOwnNano.insertLast(unit);
	gOwnNanoWorkAt.insertLast(ai.frame);
	NanoGridAppend();
	if (gFarmSet)
		return;
	gFarmPos = unit.GetPos(ai.frame);
	gFarmSet = true;
	AiLog("apex: nano farm anchored at "
		+ formatFloat(gFarmPos.x, "", 0, 0) + "," + formatFloat(gFarmPos.z, "", 0, 0));
}
void NoteDead(CCircuitUnit@ unit)
{
	if (unit is null)
		return;
	WorkerGone(unit.id);
	EscortGone(unit.id);
	GuardGone(unit.id);
	if (gAssistTargetId == unit.id) {
		@gAssistTarget = null;
		gAssistTargetId = -1;
	}
	Lattice::NoteDead(unit.id);
	LossNote(int(unit.circuitDef.id));
	for (uint gi = 0; gi < gOwnGenIds.length(); ++gi) {
		if (gOwnGenIds[gi] == unit.id) {
			gOwnGen.removeAt(gi);
			gOwnGenIds.removeAt(gi);
			break;
		}
	}
	for (uint ci = 0; ci < gOwnConvIds.length(); ++ci) {
		if (gOwnConvIds[ci] == unit.id) {
			gOwnConv.removeAt(ci);
			gOwnConvIds.removeAt(ci);
			break;
		}
	}
	// BRACES, NOT INDENTATION. Without them the gProtM decrement ran for EVERY
	// dead unit, and ProtClassOf answers PROT_RADAR/PROT_JAM for MOBILE defs
	// (any radarR > 900 or jamR > 100), so every radar or jammer bot lost in a
	// fight drained gProtM below zero -- and econM = gAssetsM - gProtM then
	// reads MORE than we own, inflating the siege basis that sizes defence.
	// ONLY WHAT WAS ADDED MAY BE SUBTRACTED. NoteFinished credits a structure
	// when it FINISHES; this fires for every death, so a building killed on the
	// pad debited a cost it never carried. gProtM ran to -5840 against an
	// 8k economy, and econM = gAssetsM - gProtM then reported assets we do not
	// own -- inflating the very siege basis that sizes defence, so each dead
	// half-built turret bought the next one.
	if (Main::WasFinished(int(unit.id))
		&& !Catalog::gMobile[int(unit.circuitDef.id)])
	{
		gAssetsM -= Catalog::gCostM[int(unit.circuitDef.id)];
		if (ProtClassOf(int(unit.circuitDef.id)) >= 0)
			gProtM -= Catalog::gCostM[int(unit.circuitDef.id)];
		if (IsLatheDef(int(unit.circuitDef.id)))
			gBPM -= Catalog::gCostM[int(unit.circuitDef.id)];
	}
	for (uint bb = 0; bb < gOwnBigIds.length(); ++bb) {
		if (gOwnBigIds[bb] == unit.id) {
			gOwnBig.removeAt(bb);
			gOwnBigIds.removeAt(bb);
			break;
		}
	}
	for (uint nn = 0; nn < gOwnNanoIds.length(); ++nn) {
		if (gOwnNanoIds[nn] == unit.id) {
			gOwnNanoPos.removeAt(nn);
			gOwnNanoIds.removeAt(nn);
			if (nn < gOwnNanoReach.length())
				gOwnNanoReach.removeAt(nn);
			if (nn < gOwnNanoBP.length())
				gOwnNanoBP.removeAt(nn);
			if (nn < gOwnNano.length())
				gOwnNano.removeAt(nn);
			if (nn < gOwnNanoWorkAt.length())
				gOwnNanoWorkAt.removeAt(nn);
			NanoGridDrop();
			NanoSentDrop(unit);
			break;
		}
	}
	for (int pcl = 0; pcl < PROT_N; ++pcl) {
		for (uint pi = 0; pi < gProtIds[pcl].length(); ++pi) {
			if (gProtIds[pcl][pi] == unit.id) {
				gProtPos[pcl].removeAt(pi);
				gProtIds[pcl].removeAt(pi);
				gProtUnit[pcl].removeAt(pi);
				gProtDefId[pcl].removeAt(pi);
				break;
			}
		}
	}
	// Same WasFinished guard as the aggregates above: gOwnCount is "finished
	// units we own", and a nanoframe that dies unfinished was never in it --
	// the unconditional debit made per-def counts read LOW (invisible under
	// the 0-clamp; the ledger's engine cross-check is its regression test).
	if (Main::WasFinished(int(unit.id)))
		OwnAdd(int(unit.circuitDef.id), -1);
	if (Catalog::gExtractsM[int(unit.circuitDef.id)] <= 0.f)
		return;
	const int i = LedgerNearest(unit.GetPos(ai.frame));
	// The moho's finish is what kills the mex under it (BAR's
	// mex_upgrade_reclaimer), so a row already carrying more is an upgrade.
	if ((i >= 0) && (gLExtract[i] > Catalog::gExtractsM[int(unit.circuitDef.id)]))
		return;
	if (Main::WasFinished(int(unit.id)))
		NoteMexDeath(unit.GetPos(ai.frame));
	if (i < 0)
		return;
	gLSpot.removeAt(i);
	gLPos.removeAt(i);
	gLIncome.removeAt(i);
	gLExtract.removeAt(i);
	gLClaimAt.removeAt(i);
	++gLStamp;   // rows shifted: LedgerFind's spot->row table must be rebuilt
}


}  // namespace Market
