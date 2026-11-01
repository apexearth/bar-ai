namespace Market {

// ROOM FOR AN IMPORTANT BUILDING THE BASE HAS NO ROOM FOR (his 2026-10-13 for the gantry; 10-29 "the lack of location
// for gantry should immediately trigger mass reclaim so it can get space ... same goes for any important building").
// A LatheSite that fits nowhere marks its def; a plot is the cheapest ground whose occupants may all be cleared, held
// for that def with a C++ zone while every turret in reach and the constructors eat it, and LatheSite answers it first.
// SEVERAL AT ONCE (his 10-30: "let multiple plots run at once per seat"): one plot per waiting def, each with its own
// ground, occupants and rounds; no two on the same ground.

const int PLOT_MEMORY = 120 * SECOND;   // a no-room mark older than this is stale
const int PLOT_SCAN = 5 * SECOND;
const int PLOT_ROUNDS = 3;
const int PLOT_UNIT_WAITS = 6;   // scans (5 s) a cleared plot waits for units standing on it
const int PLOT_GRID_MAX = 48;   // flat grid cells a scan may test

final class Plot {
	int def = -1;
	AIFloat3 at;
	float gain = 0.f;
	float value = 0.f;
	array<Id> occ;
	int round = 0;
	int unitWaits = 0;
}
array<Plot@> gPlots;

// no-room marks, one per waiting def
array<int> gNoRoomDefs;
array<int> gNoRoomAts;
array<int> gNoRoomLogAts;

array<int> gPlantAskDef;
array<float> gPlantAskGain;
array<float> gPlantAskValue;

int gPlotNextAt = 0;
int gPlotN = 0, gPlotClearedN = 0, gPlotBadN = 0;
array<AIFloat3> gPlotBad;

void NotePlantAsk(int d, float gain, float value)
{
	for (uint i = 0; i < gPlantAskDef.length(); ++i) {
		if (gPlantAskDef[i] == d) {
			gPlantAskGain[i] = gain;
			gPlantAskValue[i] = value;
			return;
		}
	}
	gPlantAskDef.insertLast(d);
	gPlantAskGain.insertLast(gain);
	gPlantAskValue.insertLast(value);
}

int PlantAskIdx(int d)
{
	for (uint i = 0; i < gPlantAskDef.length(); ++i) {
		if (gPlantAskDef[i] == d)
			return int(i);
	}
	return -1;
}

// An advanced plant, the gantry, a big reactor or converter.
bool PlotImportant(int d)
{
	return Catalog::ValidId(d) && ((IsPlant(d) && (PlantTier(d) >= 2)) || BigEcoDef(d));
}

// The site is probed before the ask is priced, so the mark waits for the ask.
void NoteNoRoom(int d)
{
	if (!PlotImportant(d))
		return;
	const int k = gNoRoomDefs.find(d);
	if (k >= 0) {
		gNoRoomAts[uint(k)] = ai.frame;
		return;
	}
	gNoRoomDefs.insertLast(d);
	gNoRoomAts.insertLast(ai.frame);
	gNoRoomLogAts.insertLast(-1);
}

// A big reactor or converter found no site within PLOT_MEMORY: the eco ground is short (factories stay in the front
// half, his 10-30, so a plant waiting is not).
bool EcoRoomShort()
{
	for (uint k = 0; k < gNoRoomDefs.length(); ++k) {
		if (BigEcoDef(gNoRoomDefs[k]) && (ai.frame - gNoRoomAts[k] <= PLOT_MEMORY))
			return true;
	}
	return false;
}

int NoRoomAt(int d)
{
	const int k = gNoRoomDefs.find(d);
	return (k >= 0) ? gNoRoomAts[uint(k)] : -999999;
}

void ForgetNoRoom(int d)
{
	const int k = gNoRoomDefs.find(d);
	if (k < 0)
		return;
	gNoRoomDefs.removeAt(uint(k));
	gNoRoomAts.removeAt(uint(k));
	gNoRoomLogAts.removeAt(uint(k));
}

bool IsPlant(int d)
{
	return !Catalog::gMobile[d] && (Catalog::gBuildsList[d].length() > 0) && (Catalog::gBuildPower[d] > 0.f);
}

bool IsNanoTurret(int d)
{
	return !Catalog::gMobile[d] && (Catalog::gBuildPower[d] > 0.f) && (Catalog::gBuildsList[d].length() == 0);
}

// THE DOORWAY'S APRON (block_map.json): a ground plant's blocker runs offset + yard/2 squares out of its door -- a land
// lab 7 + 10, the gantry 12 + 10, 16 elmos each. An air plant's ignores eco and nanos.
float PlotApronFront(int bd)
{
	if (!IsPlant(bd) || AirPlant(bd))
		return 0.f;
	return (PlantTier(bd) >= 3) ? 352.f : 272.f;
}

AIFloat3 PlotExitDir()
{
	AIFloat3 e(0.f, 0.f, 1.f);
	if (Base::Ready()) {
		e = Base::gFwd;
		if (Base::AxisIsRearward()) {
			e.x = -e.x;
			e.z = -e.z;
		}
	}
	return e;
}

// What may be cleared for an important building: anything that is not an extractor or geo, a plant (those go by
// PlotCovered), a big reactor or converter, or a building worth half the one waiting for the ground.
bool PlotClearable(int ud, int bd)
{
	if ((Catalog::gExtractsM[ud] > 0.f) || Catalog::gNeedGeo[ud] || IsPlant(ud) || BigEcoDef(ud) || Catalog::gMobile[ud])
		return false;
	// a gun goes only when it is cheap beside the building waiting (rich10: towers blocked 24 of 108 plots); the
	// defence target buys a replacement where it is needed
	if (Catalog::gMaxRange[ud] > 0.f)
		return Catalog::gCostM[ud] < 0.25f * Catalog::gCostM[bd];
	return Catalog::gCostM[ud] < 0.5f * Catalog::gCostM[bd];
}

// Every square of the footprint by the engine's water and maxHeightDif rules (C++ GroundTakes; rich12: 15 cleared plots
// had a shore under them and 4 were too steep against a 5x5 sample).
bool PlotGround(int d, const AIFloat3& in c)
{
	return ai.GroundTakes(Catalog::Def(d), c);
}

// Ground no reclaim can free: a base lane through the footprint, or what the blocking map itself reserves -- a factory's
// exit path, a metal or geo spot (C++ PlotReserved; rich19: 10 of 14 map refusals after clearing were b=0x2000/0x2 that
// a lane-and-spot guess missed).
bool PlotUnfreeable(int d, const AIFloat3& in c)
{
	const float hx = float(Catalog::gFootX[d]) * 4.f, hz = float(Catalog::gFootZ[d]) * 4.f;
	for (int ix = -1; ix <= 1; ++ix)
		for (int iz = -1; iz <= 1; ++iz)
			if (ai.InAnyBaseLane(AIFloat3(c.x + float(ix) * hx, 0.f, c.z + float(iz) * hz)))
				return true;
	return ai.PlotReserved(Catalog::Def(d), c);
}

bool HasUnit(const array<CCircuitUnit@>& in a, CCircuitUnit@ u)
{
	for (uint i = 0; i < a.length(); ++i) {
		if (a[i] is u)
			return true;
	}
	return false;
}

// What the plants outside `gone` still make covers everything the plants in it make.
bool PlotCovered(const array<CCircuitUnit@>& in gone)
{
	for (uint g = 0; g < gone.length(); ++g) {
		const array<int>@ prods = Catalog::gBuildsList[int(gone[g].circuitDef.id)];
		for (uint pi = 0; pi < prods.length(); ++pi) {
			if (!Catalog::gMobile[prods[pi]])
				continue;
			bool elsewhere = false;
			for (uint oi = 0; !elsewhere && (oi < Factory::gFacUnits.length()); ++oi) {
				CCircuitUnit@ o = Factory::gFacUnits[oi];
				if ((o is null) || (o.circuitDef is null) || HasUnit(gone, o))
					continue;
				elsewhere = Catalog::gBuildsList[int(o.circuitDef.id)].find(prods[pi]) >= 0;
			}
			if (!elsewhere)
				return false;
		}
	}
	return true;
}

Plot@ PlotOf(int d)
{
	for (uint i = 0; i < gPlots.length(); ++i) {
		if (gPlots[i].def == d)
			return gPlots[i];
	}
	return null;
}

// The plot's occupants still standing.
uint PlotLeft(Plot@ p)
{
	uint n = 0;
	for (uint i = 0; i < p.occ.length(); ++i) {
		if (ai.GetTeamUnit(p.occ[i]) !is null)
			++n;
	}
	return n;
}

// Some important building's ground is still being cleared for def d.
bool PlotClearing(int d)
{
	Plot@ p = PlotOf(d);
	return (p !is null) && (PlotLeft(p) > 0);
}

// What stands on the plot's ground now (a cleared plot that still does not fit names its blocker).
string PlotStanding(Plot@ p)
{
	const float hx = float(Catalog::gFootX[p.def]) * 8.f, hz = float(Catalog::gFootZ[p.def]) * 8.f;
	string s;
	array<CCircuitUnit@>@ on = ai.PlotBlockers(Catalog::Def(p.def), p.at, sqrt(hx * hx + hz * hz) + 480.f);
	for (uint i = 0; (on !is null) && (i < on.length()) && (s.length() < 120); ++i) {
		if ((on[i] !is null) && (on[i].circuitDef !is null))
			s += " " + on[i].circuitDef.GetName();
	}
	return s;
}

// THE CLEARED GROUND IS HELD (rich4: 47 plots emptied by the turrets and still no fit): a zone over each plot's
// footprint and apron refuses every other building the C++ placement would put there. Zones are one set for all plots.
void PlotZones()
{
	ai.ClearZones();
	for (uint i = 0; i < gPlots.length(); ++i) {
		const int bd = gPlots[i].def;
		const AIFloat3 c = gPlots[i].at;
		const float apron = IsPlant(bd) ? 48.f : 16.f;
		const float hx = float(Catalog::gFootX[bd]) * 4.f + apron, hz = float(Catalog::gFootZ[bd]) * 4.f + apron;
		ai.ReserveZone(c.x - hx, c.z - hz, c.x + hx, c.z + hz, Catalog::Def(bd));
		const float front = PlotApronFront(bd);
		if (front > 0.f) {
			const AIFloat3 e = PlotExitDir();
			const float half = float((Catalog::gFootX[bd] > Catalog::gFootZ[bd]) ? Catalog::gFootX[bd] : Catalog::gFootZ[bd]) * 4.f;
			const AIFloat3 far = c + e * (half + front);
			const float w = half + 64.f;
			const float wx = abs(e.z) * w, wz = abs(e.x) * w;
			ai.ReserveZone(((c.x < far.x) ? c.x : far.x) - wx, ((c.z < far.z) ? c.z : far.z) - wz,
					((c.x > far.x) ? c.x : far.x) + wx, ((c.z > far.z) ? c.z : far.z) + wz, Catalog::Def(bd));
		}
	}
}

void PlotDrop(Plot@ p, const string why)
{
	AiLog("apex: plot-drop t=" + ai.teamId + " " + Catalog::Def(p.def).GetName()
		+ " at=" + int(p.at.x) + "," + int(p.at.z) + " left=" + PlotLeft(p) + " why=" + why
		+ " standing=" + PlotStanding(p) + " plots=" + (gPlots.length() - 1));
	for (uint i = 0; i < gPlots.length(); ++i) {
		if (gPlots[i] is p) {
			gPlots.removeAt(i);
			break;
		}
	}
	PlotZones();
}

// Ground another plot holds.
bool PlotTaken(int bd, const AIFloat3& in c)
{
	const float mine = float((Catalog::gFootX[bd] > Catalog::gFootZ[bd]) ? Catalog::gFootX[bd] : Catalog::gFootZ[bd]) * 8.f;
	for (uint i = 0; i < gPlots.length(); ++i) {
		const int od = gPlots[i].def;
		const float theirs = float((Catalog::gFootX[od] > Catalog::gFootZ[od]) ? Catalog::gFootX[od] : Catalog::gFootZ[od]) * 8.f;
		if (gPlots[i].at.distance2D(c) < mine + theirs + PlotApronFront(od) * 0.5f)
			return true;
	}
	return false;
}

// Once per PLOT_SCAN: retire built and stale plots, then one new plot for the oldest waiting def without one.
void RefreshPlot()
{
	if (gPlsDef >= 0) {
		const double _tPs = Perf::T0();
		PlotSearchStep();
		Perf::Add("plot.search", _tPs);
		return;
	}
	if (ai.frame < gPlotNextAt)
		return;
	gPlotNextAt = ai.frame + PLOT_SCAN;
	for (uint i = 0; i < gPlots.length(); ) {
		Plot@ p = gPlots[i];
		bool built = false;
		array<CCircuitUnit@>@ on = ai.GetOwnStructsNear(p.at, 64.f);
		for (uint k = 0; (on !is null) && (k < on.length()) && !built; ++k)
			built = (on[k] !is null) && (on[k].circuitDef !is null) && (int(on[k].circuitDef.id) == p.def);
		if (built) {
			AiLog("apex: plot-built t=" + ai.teamId + " " + Catalog::Def(p.def).GetName()
				+ " at=" + int(p.at.x) + "," + int(p.at.z) + " plots=" + (gPlots.length() - 1));
			ForgetNoRoom(p.def);
			gPlots.removeAt(i);
			PlotZones();
			continue;
		}
		if (ai.frame - NoRoomAt(p.def) > 3 * PLOT_MEMORY) {
			PlotDrop(p, "stale");
			continue;
		}
		Base::ReserveSite(p.at);
		++i;
	}
	int pick = -1;
	for (uint k = 0; k < gNoRoomDefs.length(); ++k) {
		const int d = gNoRoomDefs[k];
		if ((ai.frame - gNoRoomAts[k] > PLOT_MEMORY) || (PlotOf(d) !is null) || (PlantAskIdx(d) < 0))
			continue;
		if ((pick < 0) || (gNoRoomAts[k] < gNoRoomAts[uint(pick)]))
			pick = int(k);
	}
	if (pick < 0)
		return;
	if (EcoDangerNear()) {
		if (gNoRoomLogAts[uint(pick)] != gNoRoomAts[uint(pick)]) {
			gNoRoomLogAts[uint(pick)] = gNoRoomAts[uint(pick)];
			AiLog("apex: plot-none t=" + ai.teamId + " why=danger");
		}
		return;
	}
	const double _tPs = Perf::T0();
	PlotSearchBegin(gNoRoomDefs[uint(pick)]);
	PlotSearchStep();
	Perf::Add("plot.search", _tPs);
}

// The cheapest clearable ground for a waiting def, a slice at a time: the grid walk and the candidate tests stop at
// PLOT_SLICE_US and resume on the next ask (one search took up to 35 ms in one frame, perfrev1031-shadow).
const double PLOT_SLICE_US = 1000.0;
int gPlsDef = -1;
int gPlsPhase = 0;
array<AIFloat3> gPlsCand;
uint gPlsCi = 0;
int gPlsRing = 1, gPlsKk = -1, gPlsSide = 0, gPlsFlat = 0;
bool gPlsGrid = false;
int gPlsTier = 0, gPlsYoung = 0, gPlsBad = 0, gPlsForeignN = 0, gPlsUncovered = 0;
int gPlsCandN = 0, gPlsGround = 0, gPlsLeash = 0, gPlsFront = 0, gPlsDepth = 0, gPlsTaken = 0;
string gPlsForeign;
float gPlsBestCost = 1e30f;
AIFloat3 gPlsBestAt;
array<Id> gPlsBestOcc;

void PlotSearchBegin(int bd)
{
	gPlsDef = bd;
	gPlsPhase = 1;
	gPlsCi = 0;
	gPlsRing = 1;
	gPlsKk = -1;
	gPlsSide = 0;
	gPlsFlat = 0;
	gPlsTier = 0; gPlsYoung = 0; gPlsBad = 0; gPlsForeignN = 0; gPlsUncovered = 0;
	gPlsCandN = 0; gPlsGround = 0; gPlsLeash = 0; gPlsFront = 0; gPlsDepth = 0; gPlsTaken = 0;
	gPlsForeign = "";
	gPlsBestCost = 1e30f;
	gPlsBestAt = AIFloat3();
	gPlsBestOcc.resize(0);
	gPlsCand.resize(0);
	gPlsGrid = Base::gAnchorSet;
	const int tier = PlantTier(bd);
	// The ground to clear: a lesser plant's, the turret blocks (where the lathe is), the converter fields, and every
	// flat cell of the eco leash the depth rule admits (his 10-30: factories stay in the front half).
	for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
		CCircuitUnit@ f = Factory::gFacUnits[fi];
		if ((f is null) || (f.circuitDef is null))
			continue;
		const int fd = int(f.circuitDef.id);
		if ((fd == bd) || (PlantTier(fd) >= tier)) {
			++gPlsTier;
			continue;
		}
		if (BuiltYoung(f)) {
			++gPlsYoung;
			continue;
		}
		gPlsCand.insertLast(f.GetPos(ai.frame));
	}
	const uint nStep = (gOwnNanoPos.length() > 12) ? (gOwnNanoPos.length() / 12) : 1;
	for (uint i = 0; i < gOwnNanoPos.length(); i += nStep)
		gPlsCand.insertLast(gOwnNanoPos[i]);
	const uint cStep = (gOwnConv.length() > 12) ? (gOwnConv.length() / 12) : 1;
	for (uint i = 0; i < gOwnConv.length(); i += cStep) {
		if (gOwnConv[i] !is null)
			gPlsCand.insertLast(gOwnConv[i].GetPos(ai.frame));
	}
}

void PlotSearchStep()
{
	const double t0 = ai.ClockUs();
	const int bd = gPlsDef;
	const int tier = PlantTier(bd);
	const float apron = IsPlant(bd) ? 48.f : 16.f;
	const float hx = float(Catalog::gFootX[bd]) * 8.f + apron, hz = float(Catalog::gFootZ[bd]) * 8.f + apron;
	const float r = sqrt(hx * hx + hz * hz) + 120.f + PlotApronFront(bd);
	const float leash = ai.GetTunable("apex_eco_leash", TUNE_ECO_LEASH);
	const bool doorPlant = !AirPlant(bd) && (Catalog::gBuildsList[bd].length() > 0);
	if (gPlsPhase == 1) {
		if (!gPlsGrid)
			gPlsPhase = 2;
		const float step = float((Catalog::gFootX[bd] > Catalog::gFootZ[bd]) ? Catalog::gFootX[bd] : Catalog::gFootZ[bd]) * 8.f;
		while (gPlsPhase == 1) {
			if ((gPlsFlat >= PLOT_GRID_MAX) || (float(gPlsRing) * step > leash)) {
				gPlsPhase = 2;
				break;
			}
			if (gPlsSide > 3) {
				gPlsSide = 0;
				++gPlsKk;
				continue;
			}
			if (gPlsKk > gPlsRing) {
				++gPlsRing;
				gPlsKk = -gPlsRing;
				gPlsSide = 0;
				continue;
			}
			const int ring = gPlsRing, kk = gPlsKk, side = gPlsSide;
			++gPlsSide;
			if ((side >= 2) && ((kk == -ring) || (kk == ring)))
				continue;
			const float ox = (side < 2) ? float(kk) : float((side == 2) ? -ring : ring);
			const float oz = (side < 2) ? float((side == 0) ? -ring : ring) : float(kk);
			const AIFloat3 g(Base::gAnchor.x + ox * step, 0.f, Base::gAnchor.z + oz * step);
			if (OnMap(g) && LatheDepthOk(bd, doorPlant, g) && PlotGround(bd, g)) {
				gPlsCand.insertLast(g);
				++gPlsFlat;
			}
			if (ai.ClockUs() - t0 >= PLOT_SLICE_US)
				return;
		}
	}
	while (gPlsCi < gPlsCand.length()) {
		if (ai.ClockUs() - t0 >= PLOT_SLICE_US)
			return;
		const AIFloat3 c = ai.SnapToLattice(Catalog::Def(bd), gPlsCand[gPlsCi]);
		++gPlsCi;
		++gPlsCandN;
		if (!OnMap(c) || !PlotGround(bd, c) || PlotUnfreeable(bd, c)) {
			++gPlsGround;
			continue;
		}
		if (gPlsGrid) {
			if (c.distance2D(Base::gAnchor) > leash) {
				++gPlsLeash;
				continue;
			}
			if (Builder::PastFront(c)) {
				++gPlsFront;
				continue;
			}
			if (!LatheDepthOk(bd, doorPlant, c)) {
				++gPlsDepth;
				continue;
			}
		}
		if (PlotTaken(bd, c)) {
			++gPlsTaken;
			continue;
		}
		bool bad = false;
		for (uint b = 0; (b < gPlotBad.length()) && !bad; ++b)
			bad = gPlotBad[b].distance2D(c) < hx;
		if (bad) {
			++gPlsBad;
			continue;
		}
		// exactly what refuses the building here, by the C++ blocking map's rules (yards, ignores, the doorway apron)
		array<CCircuitUnit@>@ near = ai.PlotBlockers(Catalog::Def(bd), c, r);
		if (near is null)
			continue;
		array<CCircuitUnit@> plants;
		array<Id> occ;
		float cost = 0.f;
		bool ok = true;
		for (uint q = 0; ok && (q < near.length()); ++q) {
			CCircuitUnit@ u = near[q];
			if ((u is null) || (u.circuitDef is null))
				continue;
			const int ud = int(u.circuitDef.id);
			if (IsPlant(ud) && (PlantTier(ud) < tier) && HasUnit(Factory::gFacUnits, u))
				plants.insertLast(u);
			else if (!IsNanoTurret(ud) && !PlotClearable(ud, bd)) {
				ok = false;
				++gPlsForeignN;
				if (gPlsForeign.length() < 80)
					gPlsForeign += " " + u.circuitDef.GetName();
			}
			occ.insertLast(u.id);
			cost += Catalog::gCostM[ud];
		}
		if (!ok || (occ.length() == 0))
			continue;
		if (!PlotCovered(plants)) {
			++gPlsUncovered;
			continue;
		}
		if (cost >= gPlsBestCost)
			continue;
		gPlsBestCost = cost;
		gPlsBestAt = c;
		gPlsBestOcc = occ;
	}
	gPlsDef = -1;
	PlotSearchFinish(bd);
}

void PlotSearchFinish(int bd)
{
	const int k = gNoRoomDefs.find(bd);
	const int ai0 = PlantAskIdx(bd);
	if ((k < 0) || (ai0 < 0) || (PlotOf(bd) !is null))
		return;
	if (gPlsBestOcc.length() == 0) {
		if (gNoRoomLogAts[uint(k)] != gNoRoomAts[uint(k)]) {
			gNoRoomLogAts[uint(k)] = gNoRoomAts[uint(k)];
			AiLog("apex: plot-none t=" + ai.teamId + " " + Catalog::Def(bd).GetName()
				+ " plants=" + Factory::gFacUnits.length() + " tier=" + gPlsTier + " young=" + gPlsYoung
				+ " bad=" + gPlsBad + " foreign=" + gPlsForeignN + " uncovered=" + gPlsUncovered + " cand=" + gPlsCandN
				+ " ground=" + gPlsGround + " leash=" + gPlsLeash + " front=" + gPlsFront + " depth=" + gPlsDepth
				+ " taken=" + gPlsTaken + " by=" + gPlsForeign);
		}
		return;
	}
	Plot p;
	p.def = bd;
	p.at = gPlsBestAt;
	p.occ = gPlsBestOcc;
	p.gain = gPlantAskGain[uint(ai0)];
	p.value = gPlantAskValue[uint(ai0)];
	gPlots.insertLast(p);
	++gPlotN;
	Base::ReserveSite(p.at);
	PlotZones();
	string names;
	for (uint i = 0; i < p.occ.length(); ++i) {
		CCircuitUnit@ u = ai.GetTeamUnit(p.occ[i]);
		if (u !is null)
			names += " " + u.circuitDef.GetName();
	}
	AiLog("apex: plot t=" + ai.teamId + " " + Catalog::Def(bd).GetName()
		+ " at=" + int(p.at.x) + "," + int(p.at.z) + " cost=" + int(gPlsBestCost)
		+ " v=" + formatFloat(p.value, "", 0, 3) + " plots=" + gPlots.length() + " clear=" + names);
}

// LatheSite's first answer for a plotted def: the cleared ground, once clear.
bool PlotSite(int d, AIFloat3& out site)
{
	Plot@ p = PlotOf(d);
	if ((p is null) || (PlotLeft(p) > 0))
		return false;
	AIFloat3 cell;
	bool fit = ai.CanPlaceCell(Catalog::Def(d), p.at, cell);
	if (!fit) {
		// the cleared ground, a footprint either way: the lattice cell itself can still sit on a lane or a lip
		const AIFloat3 near = ai.FindBuildSiteNear(Catalog::Def(d), p.at, float(Catalog::gFootX[d]) * 8.f);
		fit = OnMap(near) && (near.distance2D(p.at) <= float(Catalog::gFootX[d]) * 8.f)
				&& ai.CanPlaceCell(Catalog::Def(d), near, cell);
	}
	if (fit) {
		if (p.occ.length() > 0) {
			++gPlotClearedN;
			AiLog("apex: plot-clear t=" + ai.teamId + " " + Catalog::Def(d).GetName()
				+ " at=" + int(cell.x) + "," + int(cell.z));
		}
		p.occ.resize(0);
		site = cell;
		return true;
	}
	// UNITS ON THE CLEARED GROUND MOVE ON (rich13: 14 of 24 engine refusals had 1-9 of them standing on it, the
	// reclaimers among them): they are moved off, and the plot holds up to PLOT_UNIT_WAITS scans rather than dropping
	// ground that is clear (rich19: 13 of 34 drops still had 1-9 standing there after the wait alone).
	{
		const string why = ai.PlaceWhy(Catalog::Def(d), p.at);
		if ((why.findFirst("engine:") == 0) && (why.findFirst("units=0") < 0) && (p.unitWaits < PLOT_UNIT_WAITS)) {
			++p.unitWaits;
			const int moved = ai.PlotShoo(Catalog::Def(d), p.at);
			if (p.unitWaits == 1)
				AiLog("apex: plot-shoo t=" + ai.teamId + " " + Catalog::Def(d).GetName() + " at=" + int(p.at.x) + ","
					+ int(p.at.z) + " moved=" + moved + " " + why);
			return false;
		}
	}
	// WHAT STANDS THERE NOW IS THE NEXT ROUND (plotsmoke: a turret whose frame was rising when the plot was drawn --
	// frames are not our structures yet -- finished on the cleared ground): the blocking map's own blockers, if every
	// one may be cleared, become the plot's occupants again, up to PLOT_ROUNDS times.
	if (p.round < PLOT_ROUNDS) {
		const float fx = float(Catalog::gFootX[d]) * 8.f, fz = float(Catalog::gFootZ[d]) * 8.f;
		array<CCircuitUnit@>@ now = ai.PlotBlockers(Catalog::Def(d), p.at, sqrt(fx * fx + fz * fz) + 480.f);
		bool clearable = (now !is null) && (now.length() > 0);
		for (uint i = 0; clearable && (i < now.length()); ++i) {
			const int ud = (now[i].circuitDef !is null) ? int(now[i].circuitDef.id) : -1;
			clearable = (ud >= 0) && (IsNanoTurret(ud) || PlotClearable(ud, d));
		}
		if (clearable) {
			++p.round;
			p.occ.resize(0);
			string names;
			for (uint i = 0; i < now.length(); ++i) {
				p.occ.insertLast(now[i].id);
				names += " " + now[i].circuitDef.GetName();
			}
			AiLog("apex: plot-reclear t=" + ai.teamId + " " + Catalog::Def(d).GetName() + " at=" + int(p.at.x) + ","
				+ int(p.at.z) + " round=" + p.round + " clear=" + names);
			return false;
		}
	}
	++gPlotBadN;
	gPlotBad.insertLast(p.at);
	AiLog("apex: plot-nofit t=" + ai.teamId + " " + Catalog::Def(d).GetName() + " at=" + int(p.at.x) + ","
		+ int(p.at.z) + " cell=" + int(cell.x) + "," + int(cell.z) + " cellMoved=" + int(cell.distance2D(p.at))
		+ " lane=" + (ai.InAnyBaseLane(p.at) ? 1 : 0) + " why=" + ai.PlaceWhy(Catalog::Def(d), p.at));
	PlotDrop(p, "cleared-no-fit");
	return false;
}

// The reclaim of a plot's next occupant, the nearest standing one over all plots, priced at its building's own value.
CCircuitUnit@ PlotVictim(CCircuitUnit@ unit, float& out value, float& out gain)
{
	value = 0.f;
	gain = 0.f;
	CCircuitUnit@ best = null;
	float bestD = 1e30f;
	const AIFloat3 here = unit.GetPos(ai.frame);
	for (uint pi = 0; pi < gPlots.length(); ++pi) {
		Plot@ p = gPlots[pi];
		const uint left = PlotLeft(p);
		if (left == 0)
			continue;
		for (uint i = 0; i < p.occ.length(); ++i) {
			CCircuitUnit@ u = ai.GetTeamUnit(p.occ[i]);
			if ((u is null) || ReclaimClaimed(u.id, unit.id))
				continue;
			const float dd = here.distance2D(u.GetPos(ai.frame));
			if (dd < bestD) {
				bestD = dd;
				@best = u;
				value = p.value;
				gain = p.gain / float(left);
			}
		}
	}
	return best;
}

// Every plot's standing occupants, for the turrets (NanoReclaimAssist).
void PlotOccupants(array<CCircuitUnit@>& out units)
{
	units.resize(0);
	for (uint pi = 0; pi < gPlots.length(); ++pi) {
		for (uint i = 0; i < gPlots[pi].occ.length(); ++i) {
			CCircuitUnit@ u = ai.GetTeamUnit(gPlots[pi].occ[i]);
			if ((u !is null) && (u.circuitDef !is null))
				units.insertLast(u);
		}
	}
}

}  // namespace Market
