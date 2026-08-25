namespace Market {
array<int> gOwnCount;   // finished units we own, by def id
void OwnAdd(int defId, int delta)
{
	if (gOwnCount.length() == 0)
		gOwnCount.resize(Catalog::gDefCount + 1);
	if ((defId >= 1) && (defId < int(gOwnCount.length()))) {
		gOwnCount[defId] += delta;
		if (gOwnCount[defId] < 0)
			gOwnCount[defId] = 0;
	}
}

// The extraction our standing capability can already reach: any owned mobile
// builder directly, or any owned factory through the builders it can make.
// This is what the tech want measures unlock against -- the ASKER's own
// reach read a T1 con as needing a T2 lab we already had three of.
float OwnedCeil()
{
	float ceil = 0.f;
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		if (gOwnCount[d] <= 0)
			continue;
		const array<int>@ builds = Catalog::gBuildsList[int(d)];
		if (Catalog::gMobile[int(d)]) {
			for (uint i = 0; i < builds.length(); ++i) {
				if (Catalog::gExtractsM[builds[i]] > ceil)
					ceil = Catalog::gExtractsM[builds[i]];
			}
		} else {
			// A standing factory reaches what its producible builders reach.
			for (uint i = 0; i < builds.length(); ++i) {
				const int pd = builds[i];
				if (!Catalog::gMobile[pd] || !Catalog::gBuilder[pd])
					continue;
				const array<int>@ pb = Catalog::gBuildsList[pd];
				for (uint q = 0; q < pb.length(); ++q) {
					if (Catalog::gExtractsM[pb[q]] > ceil)
						ceil = Catalog::gExtractsM[pb[q]];
				}
			}
		}
	}
	return ceil;
}

// Can anything we own put this def on the ground -- directly, or through a
// standing factory's constructors? Same walk as OwnedCeil, asked about one
// def: a price anchored on a unit nobody can build is not a price.
bool CanBuildEver(int defId)
{
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		if (gOwnCount[d] <= 0)
			continue;
		const array<int>@ builds = Catalog::gBuildsList[int(d)];
		if (Catalog::gMobile[int(d)]) {
			for (uint i = 0; i < builds.length(); ++i) {
				if (builds[i] == defId)
					return true;
			}
			continue;
		}
		for (uint i = 0; i < builds.length(); ++i) {
			const int pd = builds[i];
			if (!Catalog::gMobile[pd] || !Catalog::gBuilder[pd])
				continue;
			const array<int>@ pb = Catalog::gBuildsList[pd];
			for (uint q = 0; q < pb.length(); ++q) {
				if (pb[q] == defId)
					return true;
			}
		}
	}
	return false;
}

// Mobile builders we own whose reach hits the game's extraction ceiling --
// the fleet already serving upgrade demand.
int ServingCons()
{
	int nServing = 0;
	const float ceilX = BestExtract();
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
	return nServing;
}

// The costliest mobile unit our standing factories can produce.
float OwnedProdCostCeil()
{
	float ceil = 0.f;
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		if ((gOwnCount[d] <= 0) || Catalog::gMobile[int(d)])
			continue;
		const array<int>@ pb = Catalog::gBuildsList[int(d)];
		for (uint q = 0; q < pb.length(); ++q) {
			if (Catalog::gMobile[pb[q]] && (Catalog::gCostM[pb[q]] > ceil))
				ceil = Catalog::gCostM[pb[q]];
		}
	}
	return (ceil > 1.f) ? ceil : 1.f;
}

float OwnedMobileCeil()
{
	float ceil = 0.f;
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		if ((gOwnCount[d] <= 0) || !Catalog::gMobile[int(d)])
			continue;
		const array<int>@ builds = Catalog::gBuildsList[int(d)];
		for (uint i = 0; i < builds.length(); ++i) {
			if (Catalog::gExtractsM[builds[i]] > ceil)
				ceil = Catalog::gExtractsM[builds[i]];
		}
	}
	return ceil;
}

// Own standing generators, for the obsolete-reclaim want. NOCOUNT handles:
// every entry MUST leave via NoteDead.
array<CCircuitUnit@> gOwnGen;
array<Id> gOwnGenIds;
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
const int PROT_N = 7;
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

int ProtClassOf(int defId)
{
	if (Catalog::gShield[defId] && !Catalog::gMobile[defId]) return PROT_SHIELD;
	if (Catalog::gAntiNuke[defId]) return PROT_ANTINUKE;
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
		if (Catalog::gAirT[defId] > 0.f)
			return PROT_AA;
	}
	return -1;
}

void NoteFinished(CCircuitUnit@ unit)
{
	if (unit is null)
		return;
	const int defId = int(unit.circuitDef.id);
	OwnAdd(defId, 1);
	if (!Catalog::gMobile[defId] && (Catalog::gMakeE[defId] > 1.f)
		&& !Catalog::gNeedGeo[defId])
	{
		gOwnGen.insertLast(unit);
		gOwnGenIds.insertLast(unit.id);
	}
	if (!Catalog::gMobile[defId]) {
		gAssetsM += Catalog::gCostM[defId];
		if (ProtClassOf(defId) >= 0)
			gProtM += Catalog::gCostM[defId];
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
	const int i = LedgerNearest(unit.GetPos(ai.frame));
	if (i >= 0)
		gLExtract[i] = Catalog::gExtractsM[defId];
}
// Fallback anchor: the first finished nano, only if no plan latched first.
array<AIFloat3> gOwnNanoPos;
array<Id> gOwnNanoIds;

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
	LossNote(int(unit.circuitDef.id));
	for (uint gi = 0; gi < gOwnGenIds.length(); ++gi) {
		if (gOwnGenIds[gi] == unit.id) {
			gOwnGen.removeAt(gi);
			gOwnGenIds.removeAt(gi);
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
	OwnAdd(int(unit.circuitDef.id), -1);
	if (Catalog::gExtractsM[int(unit.circuitDef.id)] <= 0.f)
		return;
	const int i = LedgerNearest(unit.GetPos(ai.frame));
	if (i < 0)
		return;
	gLSpot.removeAt(i);
	gLPos.removeAt(i);
	gLIncome.removeAt(i);
	gLExtract.removeAt(i);
	gLClaimAt.removeAt(i);
}


}  // namespace Market
