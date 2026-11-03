namespace Market {

// DEFENSIVE RECLAIM (his 11-03: "We can be attacked and we might have no defense in our base, but we might have a lot
// of nano turrets. We can reclaim the enemy units to protect ourselves.") A turret on its assist task never takes an
// enemy unit: the engine's patrol reclaims units only under META_KEY (BuilderCAI::ExecuteFight), and CreateAssistTask
// asks for features only.
//
// The engine's reclaim of a living unit (Unit::AddBuildPower, BAR reclaim.unitMethod = 1, unitDrainHealth): every
// reclaimer takes maxHealth * reclaimSpeed / buildTime hit points a second, so the unit dies after
// (health / maxHealth) * buildTime / (sum of reclaimSpeed) seconds and its whole metal comes back to us then.
// A turret goes when what its build power returns on that work beats what its own job returns per unit of build
// power; the work is fixed, so every turret that passes shortens the kill and costs nothing more.

const float DR_UNIT_EFF = 1.f;   // BAR modrules reclaim.unitEfficiency: the share of a reclaimed unit's metal we get

// One query disc per occupied cell of the turret census; the cell is a turret's reach.
array<float> gDrCellX;
array<float> gDrCellZ;
array<int> gDrStamp;
int gDrStampEra = 0;
int gDrCoverEra = -1;
float gDrCell = 0.f;
float gDrQueryR = 0.f;

// A round is one sweep of every cell, spread over the update chunks.
uint gDrScanI = 0;
int gDrRound = 1;   // the stamp arrays start at 0, which must never read as this round
array<int> gDrSeen;      // enemy id -> round it was priced
array<int> gDrSentAt;    // turret id -> round it was sent
array<int> gDrRateAt;    // turret id -> round its job was read
array<float> gDrRate;    // turret id -> metal-equivalent/s its job returns (-1 held)
array<float> gDrFlow;    // turret id -> metal/s it was moving into a frame
float gDrAbsorb = 0.f;   // metal/s of starved pull left this round to take up the flow a turret drops

int gDrTargets = 0, gDrHands = 0;
int gDrLogAt = 0;
int gDrLogTargets = 0, gDrLogHands = 0;
int gDrLoggedKills = 0;

void DrGrowI(array<int>& a, int id)
{
	if (id >= int(a.length()))
		a.resize(id + 1);
}

void DrGrowF(array<float>& a, int id)
{
	if (id >= int(a.length()))
		a.resize(id + 1);
}

void DrCover()
{
	NanoGridBuild();
	if (gDrCoverEra == gNanoGridEra)
		return;
	gDrCoverEra = gNanoGridEra;
	gDrCellX.resize(0);
	gDrCellZ.resize(0);
	gDrCell = (gNanoGridMaxReach > 64.f) ? gNanoGridMaxReach : 64.f;
	gDrQueryR = gDrCell * 0.7072f + gNanoGridMaxReach;
	const int nx = int(float(AiTerrainWidth()) / gDrCell) + 1;
	const int nz = int(float(AiTerrainHeight()) / gDrCell) + 1;
	if (int(gDrStamp.length()) < nx * nz)
		gDrStamp.resize(nx * nz);
	++gDrStampEra;
	for (uint i = 0; i < gOwnNanoPos.length(); ++i) {
		int bx = int(gOwnNanoPos[i].x / gDrCell);
		int bz = int(gOwnNanoPos[i].z / gDrCell);
		bx = (bx < 0) ? 0 : ((bx >= nx) ? nx - 1 : bx);
		bz = (bz < 0) ? 0 : ((bz >= nz) ? nz - 1 : bz);
		const int k = bz * nx + bx;
		if (gDrStamp[k] == gDrStampEra)
			continue;
		gDrStamp[k] = gDrStampEra;
		gDrCellX.insertLast((float(bx) + 0.5f) * gDrCell);
		gDrCellZ.insertLast((float(bz) + 0.5f) * gDrCell);
	}
	if (gDrScanI > gDrCellX.length())
		gDrScanI = 0;
}

// What turret `id` gives up, metal-equivalent per second: the metal it is moving into a frame, less what starved
// lathes take up when it stops (marginal build power at a fed site is worth nothing), plus a repair's or a wreck's
// return. -1: held on a reclaim it must finish.
float DrOpp(CCircuitUnit@ u, int id)
{
	DrGrowI(gDrRateAt, id);
	DrGrowF(gDrRate, id);
	DrGrowF(gDrFlow, id);
	if (gDrRateAt[id] != gDrRound) {
		gDrRateAt[id] = gDrRound;
		gDrRate[id] = ai.LatheJobRate(u);
		gDrFlow[id] = (gDrRate[id] >= 0.f) ? ai.GetResUse(u, false) : 0.f;
	}
	if (gDrRate[id] < 0.f)
		return -1.f;
	const float flow = gDrFlow[id];
	return gDrRate[id] + flow - ((flow < gDrAbsorb) ? flow : gDrAbsorb);
}

class DrFoe {
	int id = -1;
	int def = 0;
	float g = 0.f;      // metal-equivalent per build-power second the reclaim returns
	float gain = 0.f;   // metal: theirs removed, ours returned, and the damage it does while it stands
	float work = 0.f;   // build-power seconds to finish it
	float bp = 0.f;     // build power of every turret in reach
	array<int> hands;
	array<float> handBP;
}

DrFoe@ DrPrice(const array<float>@ f, uint at)
{
	const int def = int(f[at + 1]);
	if ((def <= 0) || (def > Catalog::gDefCount))
		return null;
	const AIFloat3 p(f[at + 2], f[at + 3], f[at + 4]);
	const float hpFrac = f[at + 5];
	const float rad = f[at + 6];
	const bool frame = f[at + 7] > 0.5f;
	const float bt = Catalog::gBuildTime[def];
	if ((bt <= 0.f) || (hpFrac <= 0.f))
		return null;
	DrFoe@ e = DrFoe();
	e.id = int(f[at]);
	e.def = def;
	float costIn = 0.f, hpIn = 0.f;
	NanoNear(p, gNanoGridMaxReach + rad);
	for (uint q = 0; q < gNanoGrid.hit.length(); ++q) {
		const uint i = uint(gNanoGrid.hit[q]);
		if ((i >= gOwnNanoPos.length()) || (i >= gOwnNano.length()) || (gOwnNano[i] is null))
			continue;
		const float r = gOwnNanoReach[i] + rad;
		if (gOwnNanoPos[i].SqDistance(p) > r * r)
			continue;
		const int nd = int(gOwnNano[i].circuitDef.id);
		costIn += Catalog::gCostM[nd];
		hpIn += Catalog::gHealth[nd];
		e.bp += gOwnNanoBP[i];
		e.hands.insertLast(int(gOwnNanoIds[i]));
		e.handBP.insertLast(gOwnNanoBP[i]);
	}
	if (e.bp <= 0.f)
		return null;
	e.work = hpFrac * bt;
	const float dps = Catalog::gSurfDpsOn ? Catalog::gSurfDps[def] : Catalog::gDps[def];
	const float mPerHp = (hpIn > 0.f) ? costIn / hpIn : 0.f;
	const float metal = Catalog::gCostM[def] * (frame ? hpFrac : 1.f);
	e.gain = metal * (1.f + DR_UNIT_EFF) + dps * mPerHp * (e.work / e.bp);
	e.g = e.gain / e.work;
	return e;
}

void DrSend(DrFoe@ e)
{
	array<CCircuitUnit@> go;
	array<int> goId;
	float bpGo = 0.f, oMax = 0.f, flowGo = 0.f;
	for (uint h = 0; h < e.hands.length(); ++h) {
		const int hid = e.hands[h];
		DrGrowI(gDrSentAt, hid);
		if (gDrSentAt[hid] == gDrRound)
			continue;
		CCircuitUnit@ u = ai.GetTeamUnit(hid);
		if (u is null)
			continue;
		const float opp = DrOpp(u, hid);
		if ((opp < 0.f) || (opp >= e.g * e.handBP[h]))
			continue;
		go.insertLast(u);
		goId.insertLast(hid);
		bpGo += e.handBP[h];
		flowGo += gDrFlow[hid];
		const float o = opp / e.handBP[h];
		if (o > oMax)
			oMax = o;
	}
	if (go.length() == 0)
		return;
	const float killS = e.work / bpGo;
	const int frames = int((killS + 1.f) * float(SECOND)) + 1;
	const int sent = ai.TurretsReclaimEnemy(e.id, go, frames);
	if (sent <= 0)
		return;
	for (uint h = 0; h < goId.length(); ++h)
		gDrSentAt[goId[h]] = gDrRound;
	gDrAbsorb -= (flowGo < gDrAbsorb) ? flowGo : gDrAbsorb;
	++gDrTargets;
	gDrHands += sent;
	++gDrLogTargets;
	gDrLogHands += sent;
	if (ai.frame < gDrLogAt)
		return;
	gDrLogAt = ai.frame + 5 * SECOND;
	AiLog(Factory::T() + "apex: def-reclaim t=" + ai.teamId + " tgt=" + Catalog::Def(e.def).GetName()
		+ "#" + e.id + " hands=" + sent + "/" + e.hands.length()
		+ " g=" + formatFloat(e.g, "", 0, 3) + " oMax=" + formatFloat(oMax, "", 0, 3)
		+ " gain=" + formatFloat(e.gain, "", 0, 0) + " work=" + formatFloat(e.work, "", 0, 0)
		+ " kill=" + formatFloat(killS, "", 0, 1) + "s"
		+ " | since=" + gDrLogTargets + "/" + gDrLogHands
		+ " total=" + gDrTargets + "/" + gDrHands
		+ " eaten=" + ai.DefReclaimedN() + " m=" + formatFloat(ai.DefReclaimedM(), "", 0, 0));
	gDrLogTargets = 0;
	gDrLogHands = 0;
	gDrLoggedKills = ai.DefReclaimedN();
}

// The kills no send line has reported, once the fight has gone quiet.
void DrTally()
{
	if ((gDrTargets == 0) || (ai.frame < gDrLogAt + 10 * SECOND))
		return;
	const int n = ai.DefReclaimedN();
	if (n == gDrLoggedKills)
		return;
	gDrLoggedKills = n;
	AiLog(Factory::T() + "apex: def-reclaim tally t=" + ai.teamId + " total=" + gDrTargets + "/" + gDrHands
		+ " eaten=" + n + " m=" + formatFloat(ai.DefReclaimedM(), "", 0, 0));
}

void DefReclaimStep()
{
	if (gOwnNano.length() == 0)
		return;
	DrCover();
	const uint k = gDrCellX.length();
	if (k == 0)
		return;
	if (gDrScanI >= k) {
		gDrScanI = 0;
		++gDrRound;
		gDrAbsorb = Eco::MPull() - Eco::MInc() - Eco::MCur() / 60.f - TeamTechInflow();
		if (gDrAbsorb < 0.f)
			gDrAbsorb = 0.f;
		DrTally();
	}
	const uint per = k / uint(UP_CHUNKS) + 1;
	const uint end = (gDrScanI + per < k) ? gDrScanI + per : k;
	array<DrFoe@> foes;
	for (; gDrScanI < end; ++gDrScanI) {
		const array<float>@ f = ai.EnemiesToReclaimNear(AIFloat3(gDrCellX[gDrScanI], 0.f, gDrCellZ[gDrScanI]),
				gDrQueryR);
		if (f is null)
			continue;
		for (uint at = 0; at + 7 < f.length(); at += 8) {
			const int id = int(f[at]);
			if (id < 0)
				continue;
			DrGrowI(gDrSeen, id);
			if (gDrSeen[id] == gDrRound)
				continue;
			gDrSeen[id] = gDrRound;
			DrFoe@ e = DrPrice(f, at);
			if (e is null)
				continue;
			uint j = foes.length();
			foes.insertLast(e);
			while ((j > 0) && (foes[j - 1].g < e.g)) {
				@foes[j] = foes[j - 1];
				--j;
			}
			@foes[j] = e;
		}
	}
	for (uint fi = 0; fi < foes.length(); ++fi)
		DrSend(foes[fi]);
}

}  // namespace Market
