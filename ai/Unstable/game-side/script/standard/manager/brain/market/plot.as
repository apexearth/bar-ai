namespace Market {

// ROOM FOR A GANTRY THE BASE HAS NO ROOM FOR (his 2026-10-13: on a tight map the
// base fills with T1 and T2 labs and the gantry never goes up -- reclaim the
// worst labs and put it there). A gantry LatheSite fits nowhere marks itself;
// the plot is a lesser plant's ground widened to the gantry's footprint, whose
// every occupant is a spare plant (what it makes, a plant outside the plot
// still makes) or a nano turret. Each reclaim is priced at the gantry's own
// value; the cleared ground is reserved for it and LatheSite answers it first.

const int PLOT_MEMORY = 120 * SECOND;   // a no-room mark older than this is stale
const int PLOT_SCAN = 5 * SECOND;

int gNoRoomDef = -1;
int gNoRoomAt = -999999;
array<int> gPlantAskDef;
array<float> gPlantAskGain;
array<float> gPlantAskValue;

int gPlotDef = -1;
AIFloat3 gPlotAt;
float gPlotGain = 0.f;
float gPlotValue = 0.f;
array<Id> gPlotOcc;
int gPlotNextAt = 0;
int gPlotN = 0, gPlotClearedN = 0, gPlotBadN = 0;
int gPlotRound = 0;
const int PLOT_ROUNDS = 3;
const int PLOT_GRID_MAX = 48;   // flat grid cells a scan may test
int gPlotWhyAt = -1;
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

// The site is probed before the ask is priced, so the mark waits for the ask.
// ANY IMPORTANT BUILDING, NOT ONLY THE GANTRY (his 10-29: "the lack of location for gantry should immediately trigger
// mass reclaim so it can get space ... same goes for any important building"): an advanced plant, the gantry, a big
// reactor or converter.
bool PlotImportant(int d)
{
	return Catalog::ValidId(d) && ((IsPlant(d) && (PlantTier(d) >= 2)) || BigEcoDef(d));
}

void NoteNoRoom(int d)
{
	if (!PlotImportant(d))
		return;
	gNoRoomDef = d;
	gNoRoomAt = ai.frame;
}

bool PlotOverlaps(CCircuitUnit@ u, const AIFloat3& in c, float hx, float hz)
{
	const int ud = int(u.circuitDef.id);
	const AIFloat3 p = u.GetPos(ai.frame);
	const float ux = float(Catalog::gFootX[ud]) * 8.f, uz = float(Catalog::gFootZ[ud]) * 8.f;
	return (abs(p.x - c.x) < hx + ux) && (abs(p.z - c.z) < hz + uz);
}

bool IsPlant(int d)
{
	return !Catalog::gMobile[d] && (Catalog::gBuildsList[d].length() > 0) && (Catalog::gBuildPower[d] > 0.f);
}

// THE DOORWAY'S APRON (block_map.json, rich6: 32 cleared plots with nothing on the footprint still refused, the site
// search finding nothing within 600 in half): a ground plant's blocker runs offset + yard/2 squares out of its door --
// a land lab 7 + 10, the gantry 12 + 10, 16 elmos each -- and only nanos may stand in the gantry's. An air plant's
// ignores eco and nanos.
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

// u stands in bd's apron at c: within the footprint's width, out of the door by up to PlotApronFront.
bool PlotInApron(CCircuitUnit@ u, int bd, const AIFloat3& in c)
{
	const float front = PlotApronFront(bd);
	if (front <= 0.f)
		return false;
	const int ud = int(u.circuitDef.id);
	if (IsNanoTurret(ud) && (PlantTier(bd) >= 3))
		return false;
	const AIFloat3 e = PlotExitDir();
	const AIFloat3 p = u.GetPos(ai.frame);
	const float dx = p.x - c.x, dz = p.z - c.z;
	const float along = dx * e.x + dz * e.z;
	const float across = abs(dx * e.z - dz * e.x);
	const float us = float((Catalog::gFootX[ud] > Catalog::gFootZ[ud]) ? Catalog::gFootX[ud] : Catalog::gFootZ[ud]) * 4.f;
	const float half = float((Catalog::gFootX[bd] > Catalog::gFootZ[bd]) ? Catalog::gFootX[bd] : Catalog::gFootZ[bd]) * 4.f;
	return (along > -us) && (along < half + front + us) && (across < half + 64.f + us);
}

// What may be cleared for an important building: anything that is not an extractor or geo, a gun, a plant (those go by
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

// The ground under the footprint could take the building once cleared: dry for a land building, wet for a
// floating or underwater one, and no steeper than the land plants stand on (rich3: an underwater fusion plotted on
// a land converter field, cleared, and never fit).
bool PlotGround(int d, const AIFloat3& in c)
{
	// every square, by the engine's water and maxHeightDif rules (C++ GroundTakes; rich12: 15 cleared plots had a shore
	// under them and 4 were too steep against the 5x5 sample below)
	return ai.GroundTakes(Catalog::Def(d), c);
}

bool PlotGroundSampled(int d, const AIFloat3& in c)
{
	const float hx = float(Catalog::gFootX[d]) * 4.f, hz = float(Catalog::gFootZ[d]) * 4.f;
	const bool wet = Catalog::gFloater[d] || Catalog::gSub[d] || (Catalog::Def(d).GetMinWaterDepth() > 0.f);
	float lo = 1e9f, hi = -1e9f;
	for (int ix = -2; ix <= 2; ++ix) {
		for (int iz = -2; iz <= 2; ++iz) {
			const float e = ai.GetElevationAt(AIFloat3(c.x + float(ix) * hx * 0.5f, 0.f, c.z + float(iz) * hz * 0.5f));
			if (wet ? (e >= 0.f) : (e < 0.f))
				return false;
			lo = (e < lo) ? e : lo;
			hi = (e > hi) ? e : hi;
		}
	}
	// the engine's flatness test: each square within maxHeightDif of the build height, about the middle of the
	// range (rich9: 37 of 43 cleared plots refused by the engine, on 5-28 of rise against a gantry's maxslope 10)
	return wet || (hi - lo <= 2.f * Catalog::Def(d).GetMaxHeightDif());
}

bool IsNanoTurret(int d)
{
	return !Catalog::gMobile[d] && (Catalog::gBuildPower[d] > 0.f) && (Catalog::gBuildsList[d].length() == 0);
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

// The plot's occupants still standing.
uint PlotLeft()
{
	uint n = 0;
	for (uint i = 0; i < gPlotOcc.length(); ++i) {
		if (ai.GetTeamUnit(gPlotOcc[i]) !is null)
			++n;
	}
	return n;
}

// What stands on the plot's ground now (a cleared plot that still does not fit names its blocker).
string PlotStanding()
{
	const float hx = float(Catalog::gFootX[gPlotDef]) * 8.f, hz = float(Catalog::gFootZ[gPlotDef]) * 8.f;
	string s;
	array<CCircuitUnit@>@ on = ai.PlotBlockers(Catalog::Def(gPlotDef), gPlotAt, sqrt(hx * hx + hz * hz) + 480.f);
	for (uint i = 0; (on !is null) && (i < on.length()) && (s.length() < 120); ++i) {
		if ((on[i] !is null) && (on[i].circuitDef !is null))
			s += " " + on[i].circuitDef.GetName();
	}
	return s;
}

void PlotDrop(const string why)
{
	AiLog("apex: plot-drop t=" + ai.teamId + " " + Catalog::Def(gPlotDef).GetName()
		+ " at=" + int(gPlotAt.x) + "," + int(gPlotAt.z) + " left=" + PlotLeft() + " why=" + why
		+ " standing=" + PlotStanding());
	gPlotDef = -1;
	gPlotOcc.resize(0);
	ai.ClearZones();
}

// THE CLEARED GROUND IS HELD FOR IT (rich4: 47 plots emptied by the turrets and still no fit): a zone over the
// footprint and its apron refuses every other building the C++ placement would put there while the turrets eat.
void PlotHold(int bd, const AIFloat3& in c)
{
	const float apron = IsPlant(bd) ? 48.f : 16.f;
	const float hx = float(Catalog::gFootX[bd]) * 4.f + apron, hz = float(Catalog::gFootZ[bd]) * 4.f + apron;
	ai.ClearZones();
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

// Once per PLOT_SCAN while a gantry has no room: the cheapest clearable plot.
void RefreshPlot()
{
	if (ai.frame < gPlotNextAt)
		return;
	gPlotNextAt = ai.frame + PLOT_SCAN;
	if (gPlotDef >= 0) {
		array<CCircuitUnit@>@ on = ai.GetOwnStructsNear(gPlotAt, 64.f);
		for (uint i = 0; (on !is null) && (i < on.length()); ++i) {
			if ((on[i] !is null) && (on[i].circuitDef !is null) && (int(on[i].circuitDef.id) == gPlotDef)) {
				AiLog("apex: plot-built t=" + ai.teamId + " " + Catalog::Def(gPlotDef).GetName()
					+ " at=" + int(gPlotAt.x) + "," + int(gPlotAt.z));
				gPlotDef = -1;
				ai.ClearZones();
				gNoRoomDef = -1;
				return;
			}
		}
		Base::ReserveSite(gPlotAt);
		return;
	}
	if ((gNoRoomDef < 0) || (ai.frame - gNoRoomAt > PLOT_MEMORY) || (PlantAskIdx(gNoRoomDef) < 0))
		return;
	if (EcoDangerNear()) {
		if (gPlotWhyAt != gNoRoomAt) {
			gPlotWhyAt = gNoRoomAt;
			AiLog("apex: plot-none t=" + ai.teamId + " why=danger");
		}
		return;
	}
	int nTier = 0, nYoung = 0, nBad = 0, nForeign = 0, nUncovered = 0;
	string foreign;
	const int bd = gNoRoomDef;
	const int tier = PlantTier(bd);
	// a plant's doorway and apron are part of what must be clear (rich3: 115 plots emptied, then no fit)
	const float apron = IsPlant(bd) ? 48.f : 16.f;
	const float hx = float(Catalog::gFootX[bd]) * 8.f + apron, hz = float(Catalog::gFootZ[bd]) * 8.f + apron;
	const float r = sqrt(hx * hx + hz * hz) + 120.f + PlotApronFront(bd);
	float bestCost = 1e30f;
	AIFloat3 bestAt;
	array<Id> bestOcc;
	// The ground to clear: a lesser plant's, the turret blocks (where the lathe is), and the converter fields --
	// his 10-29 bases had no plant to swap, only T1 nanos and converters on every spot.
	array<AIFloat3> cand;
	for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
		CCircuitUnit@ f = Factory::gFacUnits[fi];
		if ((f is null) || (f.circuitDef is null))
			continue;
		const int fd = int(f.circuitDef.id);
		if ((fd == bd) || (PlantTier(fd) >= tier)) {
			++nTier;
			continue;
		}
		if (BuiltYoung(f)) {
			++nYoung;
			continue;
		}
		cand.insertLast(f.GetPos(ai.frame));
	}
	const uint nStep = (gOwnNanoPos.length() > 12) ? (gOwnNanoPos.length() / 12) : 1;
	for (uint i = 0; i < gOwnNanoPos.length(); i += nStep)
		cand.insertLast(gOwnNanoPos[i]);
	const uint cStep = (gOwnConv.length() > 12) ? (gOwnConv.length() / 12) : 1;
	for (uint i = 0; i < gOwnConv.length(); i += cStep) {
		if (gOwnConv[i] !is null)
			cand.insertLast(gOwnConv[i].GetPos(ai.frame));
	}
	const float leash = ai.GetTunable("apex_eco_leash", TUNE_ECO_LEASH);
	const bool doorPlant = !AirPlant(bd) && (Catalog::gBuildsList[bd].length() > 0);
	// ...and every FLAT cell of the eco leash, nearest the anchor first (rich10: with the engine's flatness held, the
	// plants' and blocks' own ground was flat nowhere in 117 of 225 searches)
	if (Base::gAnchorSet) {
		const float step = float((Catalog::gFootX[bd] > Catalog::gFootZ[bd]) ? Catalog::gFootX[bd] : Catalog::gFootZ[bd]) * 8.f;
		int flat = 0;
		for (int ring = 1; (flat < PLOT_GRID_MAX) && (float(ring) * step <= leash); ++ring) {
			for (int k = -ring; (k <= ring) && (flat < PLOT_GRID_MAX); ++k) {
				for (int side = 0; (side < 4) && (flat < PLOT_GRID_MAX); ++side) {
					const float ox = (side < 2) ? float(k) : float((side == 2) ? -ring : ring);
					const float oz = (side < 2) ? float((side == 0) ? -ring : ring) : float(k);
					if ((side >= 2) && ((k == -ring) || (k == ring)))
						continue;
					const AIFloat3 g(Base::gAnchor.x + ox * step, 0.f, Base::gAnchor.z + oz * step);
					if (OnMap(g) && PlotGround(bd, g)) {
						cand.insertLast(g);
						++flat;
					}
				}
			}
		}
	}
	for (uint ci = 0; ci < cand.length(); ++ci) {
		const AIFloat3 c = ai.SnapToLattice(Catalog::Def(bd), cand[ci]);
		if (!OnMap(c) || !PlotGround(bd, c))
			continue;
		if (Base::gAnchorSet && ((c.distance2D(Base::gAnchor) > leash) || Builder::PastFront(c)
				|| !LatheDepthOk(bd, doorPlant, c)))
			continue;
		bool bad = false;
		for (uint b = 0; (b < gPlotBad.length()) && !bad; ++b)
			bad = gPlotBad[b].distance2D(c) < hx;
		if (bad) {
			++nBad;
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
		for (uint k = 0; ok && (k < near.length()); ++k) {
			CCircuitUnit@ u = near[k];
			if ((u is null) || (u.circuitDef is null))
				continue;
			const int ud = int(u.circuitDef.id);
			if (IsPlant(ud) && (PlantTier(ud) < tier) && HasUnit(Factory::gFacUnits, u))
				plants.insertLast(u);
			else if (!IsNanoTurret(ud) && !PlotClearable(ud, bd)) {
				ok = false;
				++nForeign;
				if (foreign.length() < 80)
					foreign += " " + u.circuitDef.GetName();
			}
			occ.insertLast(u.id);
			cost += Catalog::gCostM[ud];
		}
		if (!ok || (occ.length() == 0))
			continue;
		if (!PlotCovered(plants)) {
			++nUncovered;
			continue;
		}
		if (cost >= bestCost)
			continue;
		bestCost = cost;
		bestAt = c;
		bestOcc = occ;
	}
	if (bestOcc.length() == 0) {
		if (gPlotWhyAt != gNoRoomAt) {
			gPlotWhyAt = gNoRoomAt;
			AiLog("apex: plot-none t=" + ai.teamId + " " + Catalog::Def(bd).GetName()
				+ " plants=" + Factory::gFacUnits.length() + " tier=" + nTier + " young=" + nYoung
				+ " bad=" + nBad + " foreign=" + nForeign + " uncovered=" + nUncovered + " by=" + foreign);
		}
		return;
	}
	const int ai0 = PlantAskIdx(bd);
	gPlotDef = bd;
	gPlotAt = bestAt;
	gPlotOcc = bestOcc;
	gPlotRound = 0;
	gPlotGain = gPlantAskGain[uint(ai0)];
	gPlotValue = gPlantAskValue[uint(ai0)];
	++gPlotN;
	Base::ReserveSite(gPlotAt);
	PlotHold(bd, gPlotAt);
	string names;
	for (uint i = 0; i < gPlotOcc.length(); ++i) {
		CCircuitUnit@ u = ai.GetTeamUnit(gPlotOcc[i]);
		if (u !is null)
			names += " " + u.circuitDef.GetName();
	}
	AiLog("apex: plot t=" + ai.teamId + " " + Catalog::Def(bd).GetName()
		+ " at=" + int(gPlotAt.x) + "," + int(gPlotAt.z) + " cost=" + int(bestCost)
		+ " v=" + formatFloat(gPlotValue, "", 0, 3) + " clear=" + names);
}

// LatheSite's first answer for the plot's def: the cleared ground, once clear.
bool PlotSite(int d, AIFloat3& out site)
{
	if ((gPlotDef < 0) || (d != gPlotDef) || (PlotLeft() > 0))
		return false;
	AIFloat3 cell;
	bool fit = ai.CanPlaceCell(Catalog::Def(d), gPlotAt, cell);
	if (!fit) {
		// the cleared ground, a footprint either way: the lattice cell itself can still sit on a lane or a lip
		const AIFloat3 near = ai.FindBuildSiteNear(Catalog::Def(d), gPlotAt, float(Catalog::gFootX[d]) * 8.f);
		fit = OnMap(near) && (near.distance2D(gPlotAt) <= float(Catalog::gFootX[d]) * 8.f)
				&& ai.CanPlaceCell(Catalog::Def(d), near, cell);
	}
	if (fit) {
		if (gPlotOcc.length() > 0) {
			++gPlotClearedN;
			AiLog("apex: plot-clear t=" + ai.teamId + " " + Catalog::Def(d).GetName()
				+ " at=" + int(cell.x) + "," + int(cell.z));
		}
		gPlotOcc.resize(0);
		site = cell;
		return true;
	}
	// WHAT STANDS THERE NOW IS THE NEXT ROUND (plotsmoke: a turret whose frame was rising when the plot was drawn --
	// frames are not our structures yet -- finished on the cleared ground): the blocking map's own blockers, if every
	// one may be cleared, become the plot's occupants again, up to PLOT_ROUNDS times.
	if (gPlotRound < PLOT_ROUNDS) {
		const float fx = float(Catalog::gFootX[d]) * 8.f, fz = float(Catalog::gFootZ[d]) * 8.f;
		array<CCircuitUnit@>@ now = ai.PlotBlockers(Catalog::Def(d), gPlotAt, sqrt(fx * fx + fz * fz) + 480.f);
		bool clearable = (now !is null) && (now.length() > 0);
		for (uint i = 0; clearable && (i < now.length()); ++i) {
			const int ud = (now[i].circuitDef !is null) ? int(now[i].circuitDef.id) : -1;
			clearable = (ud >= 0) && (IsNanoTurret(ud) || PlotClearable(ud, d));
		}
		if (clearable) {
			++gPlotRound;
			gPlotOcc.resize(0);
			string names;
			for (uint i = 0; i < now.length(); ++i) {
				gPlotOcc.insertLast(now[i].id);
				names += " " + now[i].circuitDef.GetName();
			}
			AiLog("apex: plot-reclear t=" + ai.teamId + " " + Catalog::Def(d).GetName() + " at=" + int(gPlotAt.x) + ","
				+ int(gPlotAt.z) + " round=" + gPlotRound + " clear=" + names);
			return false;
		}
	}
	++gPlotBadN;
	gPlotBad.insertLast(gPlotAt);
	// which part of the placement test refused the empty ground (rich5: 80 of 95 drops with nothing of ours on it)
	{
		const float hx = float(Catalog::gFootX[d]) * 4.f, hz = float(Catalog::gFootZ[d]) * 4.f;
		float lo = 1e9f, hi = -1e9f;
		for (int ix = -1; ix <= 1; ++ix)
			for (int iz = -1; iz <= 1; ++iz) {
				const float e = ai.GetElevationAt(AIFloat3(gPlotAt.x + float(ix) * hx, 0.f, gPlotAt.z + float(iz) * hz));
				lo = (e < lo) ? e : lo;
				hi = (e > hi) ? e : hi;
			}
		const AIFloat3 nb = ai.FindBuildSiteNear(Catalog::Def(d), gPlotAt, 600.f);
		AiLog("apex: plot-nofit t=" + ai.teamId + " " + Catalog::Def(d).GetName() + " at=" + int(gPlotAt.x) + ","
			+ int(gPlotAt.z) + " cell=" + int(cell.x) + "," + int(cell.z) + " cellMoved=" + int(cell.distance2D(gPlotAt))
			+ " lane=" + (ai.InAnyBaseLane(gPlotAt) ? 1 : 0) + " rise=" + int(hi - lo)
			+ " wreck=" + int(ai.GetWreckValueAt(gPlotAt, hx + hz))
			+ " near600=" + (OnMap(nb) ? int(nb.distance2D(gPlotAt)) : -1)
			+ " why=" + ai.PlaceWhy(Catalog::Def(d), gPlotAt));
	}
	PlotDrop("cleared-no-fit");
	return false;
}

// The reclaim of the plot's next occupant, priced at the gantry's own value.
CCircuitUnit@ PlotVictim(CCircuitUnit@ unit, float& out value, float& out gain)
{
	value = 0.f;
	gain = 0.f;
	if (gPlotDef < 0)
		return null;
	if (ai.frame - gNoRoomAt > 3 * PLOT_MEMORY) {
		PlotDrop("stale");
		return null;
	}
	const uint left = PlotLeft();
	if (left == 0)
		return null;
	CCircuitUnit@ best = null;
	float bestD = 1e30f;
	const AIFloat3 here = unit.GetPos(ai.frame);
	for (uint i = 0; i < gPlotOcc.length(); ++i) {
		CCircuitUnit@ u = ai.GetTeamUnit(gPlotOcc[i]);
		if ((u is null) || ReclaimClaimed(u.id, unit.id))
			continue;
		const float dd = here.distance2D(u.GetPos(ai.frame));
		if (dd < bestD) {
			bestD = dd;
			@best = u;
		}
	}
	if (best !is null) {
		value = gPlotValue;
		gain = gPlotGain / float(left);
	}
	return best;
}

}  // namespace Market
