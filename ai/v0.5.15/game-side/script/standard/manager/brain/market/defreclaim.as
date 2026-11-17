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
array<float> gDrcCellX;
array<float> gDrcCellZ;
array<int> gDrcStamp;
int gDrcStampEra = 0;
int gDrcCoverEra = -1;
float gDrcCell = 0.f;
float gDrcQueryR = 0.f;

// A round is one sweep of every cell, spread over the update chunks.
uint gDrcScanI = 0;
int gDrcRound = 1;   // the stamp arrays start at 0, which must never read as this round
array<int> gDrcSeen;      // enemy id -> round it was priced
array<int> gDrcSentAt;    // turret id -> round it was sent
array<int> gDrcRateAt;    // turret id -> round its job was read
array<float> gDrcRate;    // turret id -> metal-equivalent/s its job returns (-1 held)
array<float> gDrcFlow;    // turret id -> metal/s it was moving into a frame
float gDrcAbsorb = 0.f;   // metal/s of starved pull left this round to take up the flow a turret drops

int gDrcTargets = 0, gDrcHands = 0;
int gDrcLogAt = 0;
int gDrcLogTargets = 0, gDrcLogHands = 0;
int gDrcLoggedKills = 0;

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
	if (gDrcCoverEra == gNanoGridEra)
		return;
	gDrcCoverEra = gNanoGridEra;
	gDrcCellX.resize(0);
	gDrcCellZ.resize(0);
	gDrcCell = (gNanoGridMaxReach > 64.f) ? gNanoGridMaxReach : 64.f;
	gDrcQueryR = gDrcCell * 0.7072f + gNanoGridMaxReach;
	const int nx = int(float(AiTerrainWidth()) / gDrcCell) + 1;
	const int nz = int(float(AiTerrainHeight()) / gDrcCell) + 1;
	if (int(gDrcStamp.length()) < nx * nz)
		gDrcStamp.resize(nx * nz);
	++gDrcStampEra;
	for (uint i = 0; i < gOwnNanoPos.length(); ++i) {
		int bx = int(gOwnNanoPos[i].x / gDrcCell);
		int bz = int(gOwnNanoPos[i].z / gDrcCell);
		bx = (bx < 0) ? 0 : ((bx >= nx) ? nx - 1 : bx);
		bz = (bz < 0) ? 0 : ((bz >= nz) ? nz - 1 : bz);
		const int k = bz * nx + bx;
		if (gDrcStamp[k] == gDrcStampEra)
			continue;
		gDrcStamp[k] = gDrcStampEra;
		gDrcCellX.insertLast((float(bx) + 0.5f) * gDrcCell);
		gDrcCellZ.insertLast((float(bz) + 0.5f) * gDrcCell);
	}
	if (gDrcScanI > gDrcCellX.length())
		gDrcScanI = 0;
}

// What turret `id` gives up, metal-equivalent per second: the metal it is moving into a frame, less what starved
// lathes take up when it stops (marginal build power at a fed site is worth nothing), plus a repair's or a wreck's
// return. -1: held on a reclaim it must finish.
float DrOpp(CCircuitUnit@ u, int id)
{
	DrGrowI(gDrcRateAt, id);
	DrGrowF(gDrcRate, id);
	DrGrowF(gDrcFlow, id);
	if (gDrcRateAt[id] != gDrcRound) {
		gDrcRateAt[id] = gDrcRound;
		gDrcRate[id] = ai.LatheJobRate(u);
		gDrcFlow[id] = (gDrcRate[id] >= 0.f) ? ai.GetResUse(u, false) : 0.f;
	}
	if (gDrcRate[id] < 0.f)
		return -1.f;
	const float flow = gDrcFlow[id];
	return gDrcRate[id] + flow - ((flow < gDrcAbsorb) ? flow : gDrcAbsorb);
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
		DrGrowI(gDrcSentAt, hid);
		if (gDrcSentAt[hid] == gDrcRound)
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
		flowGo += gDrcFlow[hid];
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
		gDrcSentAt[goId[h]] = gDrcRound;
	gDrcAbsorb -= (flowGo < gDrcAbsorb) ? flowGo : gDrcAbsorb;
	++gDrcTargets;
	gDrcHands += sent;
	++gDrcLogTargets;
	gDrcLogHands += sent;
	if (ai.frame < gDrcLogAt)
		return;
	gDrcLogAt = ai.frame + 5 * SECOND;
	AiLog(Factory::T() + "apex: def-reclaim t=" + ai.teamId + " tgt=" + Catalog::Def(e.def).GetName()
		+ "#" + e.id + " hands=" + sent + "/" + e.hands.length()
		+ " g=" + formatFloat(e.g, "", 0, 3) + " oMax=" + formatFloat(oMax, "", 0, 3)
		+ " gain=" + formatFloat(e.gain, "", 0, 0) + " work=" + formatFloat(e.work, "", 0, 0)
		+ " kill=" + formatFloat(killS, "", 0, 1) + "s"
		+ " | since=" + gDrcLogTargets + "/" + gDrcLogHands
		+ " total=" + gDrcTargets + "/" + gDrcHands
		+ " eaten=" + ai.DefReclaimedN() + " m=" + formatFloat(ai.DefReclaimedM(), "", 0, 0));
	gDrcLogTargets = 0;
	gDrcLogHands = 0;
	gDrcLoggedKills = ai.DefReclaimedN();
}

// The kills no send line has reported, once the fight has gone quiet.
void DrTally()
{
	if ((gDrcTargets == 0) || (ai.frame < gDrcLogAt + 10 * SECOND))
		return;
	const int n = ai.DefReclaimedN();
	if (n == gDrcLoggedKills)
		return;
	gDrcLoggedKills = n;
	AiLog(Factory::T() + "apex: def-reclaim tally t=" + ai.teamId + " total=" + gDrcTargets + "/" + gDrcHands
		+ " eaten=" + n + " m=" + formatFloat(ai.DefReclaimedM(), "", 0, 0));
}

void DefReclaimStep(int chunks)
{
	if (gOwnNano.length() == 0)
		return;
	DrCover();
	const uint k = gDrcCellX.length();
	if (k == 0)
		return;
	if (gDrcScanI >= k) {
		gDrcScanI = 0;
		++gDrcRound;
		gDrcAbsorb = Eco::MPull() - Eco::MInc() - Eco::MCur() / 60.f - TeamTechInflow();
		if (gDrcAbsorb < 0.f)
			gDrcAbsorb = 0.f;
		DrTally();
	}
	const uint per = k / uint((chunks > 0) ? chunks : 1) + 1;
	const uint end = (gDrcScanI + per < k) ? gDrcScanI + per : k;
	array<DrFoe@> foes;
	for (; gDrcScanI < end; ++gDrcScanI) {
		const array<float>@ f = ai.EnemiesToReclaimNear(AIFloat3(gDrcCellX[gDrcScanI], 0.f, gDrcCellZ[gDrcScanI]),
				gDrcQueryR);
		if (f is null)
			continue;
		for (uint at = 0; at + 7 < f.length(); at += 8) {
			const int id = int(f[at]);
			if (id < 0)
				continue;
			DrGrowI(gDrcSeen, id);
			if (gDrcSeen[id] == gDrcRound)
				continue;
			gDrcSeen[id] = gDrcRound;
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
