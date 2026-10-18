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
void NoteNoRoom(int d)
{
	if (PlantTier(d) < 3)
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

void PlotDrop(const string why)
{
	AiLog("apex: plot-drop t=" + ai.teamId + " " + Catalog::Def(gPlotDef).GetName()
		+ " at=" + int(gPlotAt.x) + "," + int(gPlotAt.z) + " left=" + PlotLeft() + " why=" + why);
	gPlotDef = -1;
	gPlotOcc.resize(0);
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
	const float hx = float(Catalog::gFootX[bd]) * 8.f, hz = float(Catalog::gFootZ[bd]) * 8.f;
	const float r = sqrt(hx * hx + hz * hz) + 120.f;
	float bestCost = 1e30f;
	AIFloat3 bestAt;
	array<Id> bestOcc;
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
		const AIFloat3 c = ai.SnapToLattice(Catalog::Def(bd), f.GetPos(ai.frame));
		if (!OnMap(c))
			continue;
		bool bad = false;
		for (uint b = 0; (b < gPlotBad.length()) && !bad; ++b)
			bad = gPlotBad[b].distance2D(c) < hx;
		if (bad) {
			++nBad;
			continue;
		}
		array<CCircuitUnit@>@ near = ai.GetOwnStructsNear(c, r);
		if (near is null)
			continue;
		array<CCircuitUnit@> plants;
		array<Id> occ;
		float cost = 0.f;
		bool ok = true;
		for (uint k = 0; ok && (k < near.length()); ++k) {
			CCircuitUnit@ u = near[k];
			if ((u is null) || (u.circuitDef is null) || !PlotOverlaps(u, c, hx, hz))
				continue;
			const int ud = int(u.circuitDef.id);
			if (IsPlant(ud) && (PlantTier(ud) < tier) && HasUnit(Factory::gFacUnits, u))
				plants.insertLast(u);
			else if (!IsNanoTurret(ud)) {
				ok = false;
				++nForeign;
				if (foreign.length() < 80)
					foreign += " " + u.circuitDef.GetName();
			}
			occ.insertLast(u.id);
			cost += Catalog::gCostM[ud];
		}
		if (!ok || (plants.length() == 0))
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
	gPlotGain = gPlantAskGain[uint(ai0)];
	gPlotValue = gPlantAskValue[uint(ai0)];
	++gPlotN;
	Base::ReserveSite(gPlotAt);
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
	if (ai.CanPlaceCell(Catalog::Def(d), gPlotAt, cell)) {
		if (gPlotOcc.length() > 0) {
			++gPlotClearedN;
			AiLog("apex: plot-clear t=" + ai.teamId + " " + Catalog::Def(d).GetName()
				+ " at=" + int(cell.x) + "," + int(cell.z));
		}
		gPlotOcc.resize(0);
		site = cell;
		return true;
	}
	++gPlotBadN;
	gPlotBad.insertLast(gPlotAt);
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
