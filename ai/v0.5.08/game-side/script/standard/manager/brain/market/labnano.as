namespace Market {

// LAB NANO (apex_lab_nano; his 2026-10-16: "we make tons of towers and have no con turrets
// supporting our labs"). Every other nano term is bounded by spare metal, so once towers spend
// the income they all read zero (feed=0, floor gated on a fifth of storage banked). Here a
// turret at a lab is worth the army metal per second it adds there, bounded by the lab's share
// of income: the ruling's income / labs / turret drain is the count this prices out.
//   need = income / labs - ring at the lab (built + ordered), in m/s at the lab's density
//   gain = min(turret drain, need) x run, run = feed / (pull + its own draw), metal and energy
// Under a stall every lathe runs at that share, so a turret at the lab claims it from the rest.
const int NS_LAB = 8;

bool gLnOn = false;
bool gLnOnRead = false;
int gLnAt = -1;
int gLnLogAt = 3600;
int gLnLabs = 0;
float gLnInc = 0.f, gLnNeed = 0.f, gLnDens = 7.f / 80.f, gLnEDens = 0.f;
float gLnTurrets = 0.f;
int gLnTurretsMin = 0;
AIFloat3 gLnPos(-1.f, 0.f, -1.f);
// per minute: elections offering a lab nano, its gain/value, the best tower beside it, wins
int gLnOffers = 0, gLnBeatTower = 0, gLnWon = 0, gLnTowerWon = 0, gLnBoth = 0;
float gLnGainSum = 0.f, gLnVSum = 0.f, gLnTowerVSum = 0.f, gLnLastGain = 0.f;

bool LabNanoOn()
{
	if (!gLnOnRead) {
		gLnOnRead = true;
		gLnOn = ai.GetTunable("apex_lab_nano", TUNE_LAB_NANO) > 0.f;
	}
	return gLnOn;
}

bool LabNanoServes(CCircuitUnit@ f)
{
	if ((f is null) || (f.circuitDef is null))
		return false;
	const array<int>@ pr = Catalog::BuildsOf(int(f.circuitDef.id));
	for (uint q = 0; q < pr.length(); ++q) {
		const int d = pr[q];
		if (Catalog::gAvailable[d] && Catalog::gMobile[d] && !Catalog::gBuilder[d]
			&& (Catalog::gPower[d] > 1.f))
			return true;
	}
	return false;
}

void LabNanoScan()
{
	if (gLnAt == ai.frame)
		return;
	gLnAt = ai.frame;
	gLnNeed = 0.f;
	gLnPos = AIFloat3(-1.f, 0.f, -1.f);
	gLnLabs = 0;
	TrackIncome();
	gLnInc = (gIncEma > 0.f) ? gIncEma : Eco::MInc();
	const uint nF = Factory::gFacUnits.length();
	for (uint fi = 0; fi < nF; ++fi) {
		if (LabNanoServes(Factory::gFacUnits[fi]))
			++gLnLabs;
	}
	if (gLnLabs == 0)
		return;
	const float per = gLnInc / float(gLnLabs);
	bool any = false;
	for (uint fi = 0; fi < nF; ++fi) {
		CCircuitUnit@ f = Factory::gFacUnits[fi];
		if (!LabNanoServes(f))
			continue;
		const AIFloat3 fp = f.GetPos(ai.frame);
		if (!OnMap(fp))
			continue;
		float ring = RingBPAt(fp);
		for (uint li = 0; li < Requests::gLive.length(); ++li) {
			IUnitTask@ lt = Requests::gLive[li];
			if ((lt is null) || lt.IsDead() || (lt.buildDef is null)
				|| (lt.GetBuildType() != Task::BuildType::NANO))
				continue;
			const int ld = int(lt.buildDef.id);
			const AIFloat3 lp = lt.GetBuildPos();
			if (OnMap(lp) && (fp.distance2D(lp) < 0.9f * Catalog::gBuildDist[ld]))
				ring += Catalog::gBuildPower[ld];
		}
		const float dens = LineDensity(f);
		const float need = per - ring * dens;
		if (!any || (need > gLnNeed)) {
			any = true;
			gLnNeed = need;
			gLnPos = fp;
			gLnDens = dens;
			gLnEDens = LineEDensity(f);
		}
	}
	if (gLnNeed < 0.f)
		gLnNeed = 0.f;
}

void LabNanoCensus()
{
	gLnTurrets = 0.f;
	gLnTurretsMin = 0;
	int n = 0;
	for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
		CCircuitUnit@ f = Factory::gFacUnits[fi];
		if (!LabNanoServes(f))
			continue;
		const int have = NanosReaching(f.GetPos(ai.frame));
		gLnTurrets += float(have);
		if ((n == 0) || (have < gLnTurretsMin))
			gLnTurretsMin = have;
		++n;
	}
	if (n > 0)
		gLnTurrets /= float(n);
}

// The share of its ask a lathe drawing (dM, dE) more would run at now: feed over pull, the
// bank over the stall horizon, the tighter of metal and energy.
float LabNanoRun(float dM, float dE)
{
	const float h0 = EGenBuildSeconds();
	const float h = (h0 > 1.f) ? h0 : 1.f;
	float s = 1.f;
	const float mp = Eco::MPull() + dM;
	if (mp > 0.01f) {
		const float sm = (Eco::MInc() + Eco::MCur() / h) / mp;
		if (sm < s)
			s = sm;
	}
	const float ep = Eco::EPull() + dE;
	if (ep > 0.01f) {
		const float se = (Eco::EInc() + Eco::ECur() / h) / ep;
		if (se < s)
			s = se;
	}
	return (s > 0.f) ? s : 0.f;
}

float LabNanoGain(int d, float need)
{
	const float dM = Catalog::gBuildPower[d] * gLnDens;
	const float dE = Catalog::gBuildPower[d] * gLnEDens;
	const float g = (need < dM) ? need : dM;
	gLnLastGain = g * LabNanoRun(dM, dE);
	return gLnLastGain;
}

// After the ranking: what a lab nano was worth against the best ground tower beside it.
void LabNanoNoteRanked(array<Want@>@ ranked)
{
	if (!LabNanoOn() || (ranked is null))
		return;
	float nv = -1.f, tv = -1.f, ng = 0.f;
	for (uint i = 0; i < ranked.length(); ++i) {
		Want@ r = ranked[i];
		if (r is null)
			continue;
		if ((r.kind == WK_NANO) && (r.spotId == NS_LAB) && (r.value > nv)) {
			nv = r.value;
			ng = r.gain;
		} else if ((r.kind == WK_PROTECT) && (r.spotId == PROT_DEF) && (r.value > tv)) {
			tv = r.value;
		}
	}
	if (nv < 0.f)
		return;
	++gLnOffers;
	gLnGainSum += ng;
	gLnVSum += nv;
	if (tv >= 0.f) {
		++gLnBoth;
		gLnTowerVSum += tv;
		if (nv > tv)
			++gLnBeatTower;
	}
}

void LabNanoNoteTop(Want@ top)
{
	if (!LabNanoOn() || (top is null))
		return;
	if ((top.kind == WK_NANO) && (top.spotId == NS_LAB))
		++gLnWon;
	else if ((top.kind == WK_PROTECT) && (top.spotId == PROT_DEF))
		++gLnTowerWon;
}

// Logged on or off, so the off arm reads the same lab numbers.
void LabNanoLog()
{
	if (ai.frame < gLnLogAt)
		return;
	gLnLogAt = ai.frame + 60 * SECOND;
	LabNanoScan();
	LabNanoCensus();
	const float per = (gLnLabs > 0) ? (gLnInc / float(gLnLabs)) : 0.f;
	AiLog(Factory::T() + "apex: labnano-stat t=" + ai.teamId + " on=" + (LabNanoOn() ? 1 : 0)
		+ " labs=" + gLnLabs
		+ " turrets/lab=" + formatFloat(gLnTurrets, "", 0, 1) + " min=" + gLnTurretsMin
		+ " inc/lab=" + formatFloat(per, "", 0, 1)
		+ " need=" + formatFloat(gLnNeed, "", 0, 1)
		+ " dens=" + formatFloat(gLnDens, "", 0, 3)
		+ " run=" + formatFloat(LabNanoRun(200.f * gLnDens, 200.f * gLnEDens), "", 0, 2)
		+ " offers=" + gLnOffers
		+ " gain=" + formatFloat((gLnOffers > 0) ? (gLnGainSum / float(gLnOffers)) : 0.f, "", 0, 2)
		+ " v=" + formatFloat((gLnOffers > 0) ? (1000.f * gLnVSum / float(gLnOffers)) : 0.f, "", 0, 2)
		+ " towerV=" + formatFloat((gLnBoth > 0) ? (1000.f * gLnTowerVSum / float(gLnBoth)) : 0.f, "", 0, 2)
		+ " beat=" + gLnBeatTower + "/" + gLnBoth
		+ " won=" + gLnWon + " towerWon=" + gLnTowerWon
		+ " def=" + formatFloat(Brain::ShareOf(Brain::DEFENCE), "", 0, 2)
		+ "/" + formatFloat(Brain::TargetShare(Brain::DEFENCE), "", 0, 2)
		+ " bp=" + formatFloat(Brain::ShareOf(Brain::BUILDPOWER), "", 0, 2)
		+ "/" + formatFloat(Brain::TargetShare(Brain::BUILDPOWER), "", 0, 2));
	gLnOffers = 0;
	gLnBeatTower = 0;
	gLnWon = 0;
	gLnTowerWon = 0;
	gLnBoth = 0;
	gLnGainSum = 0.f;
	gLnVSum = 0.f;
	gLnTowerVSum = 0.f;
}

}  // namespace Market
