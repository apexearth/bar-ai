namespace Market {

// ECO RETURN (apex_eco_return). Every economy build is priced by the metal it returns per metal over
// the horizon at the energy actually available:
//   free   = EMA(income - what everything but the converters actually spends)
//   room   = free + generation in flight - converter capacity standing and ordered
//            (a converter chews min(its capacity, room); idle capacity takes new surplus first)
//   demand = what non-converters spend + their unmet ask energy alone would unlock
//            (lathes run at min(metal share, energy share); a metal-bound ask is not energy demand)
// mex, generator, converter and storage all charge their late start as the share of the horizon lost
// and their energy bill at no less than the conversion floor.
// The army's extras follow the threat that arrives: q = a + (1 - a) x kill, a = their army on our edge
// (share of their known strength, a seen-halflife peak) combined with their raids on our economy
// against the army our share holds, kill = 1 - 1/r^2 for r = our team army over theirs above 1.
// small_hard's k, the rush floor, the map-share nudge and the budget's army row are scaled by q.

bool gErOn = false;
bool gErOnRead = false;
bool EcoReturnOn()
{
	if (!gErOnRead) {
		gErOnRead = true;
		gErOn = ai.GetTunable("apex_eco_return", TUNE_ECO_RETURN) > 0.f;
	}
	return gErOn;
}

float gErFreeEma = 0.f;
float gErDemEma = 0.f;
bool gErESet = false;

void ErTrackE()
{
	const float conv = ConvUseE();
	float use = aiEconomyMgr.energy.usage - conv;
	if (use < 0.f)
		use = 0.f;
	float ask = Eco::EPull() - conv;
	if (ask < use)
		ask = use;
	float unlock = 0.f;
	{
		const float h0 = EGenBuildSeconds();
		const float h = (h0 > 1.f) ? h0 : 1.f;
		const float mP = Eco::MPull();
		const float eP = Eco::EPull();
		float sm = (mP > 0.01f) ? (Eco::MInc() + Eco::MCur() / h) / mP : 1.f;
		float se = (eP > 0.01f) ? (Eco::EInc() + Eco::ECur() / h) / eP : 1.f;
		if (sm > 1.f) sm = 1.f;
		if (se > sm) se = sm;
		unlock = sm - se;
	}
	const float dem = use + (ask - use) * unlock;
	const float freeE = Eco::EInc() - use;
	if (!gErESet) {
		gErESet = true;
		gErFreeEma = freeE;
		gErDemEma = dem;
	} else {
		gErFreeEma = 0.9f * gErFreeEma + 0.1f * freeE;
		gErDemEma = 0.9f * gErDemEma + 0.1f * dem;
	}
}

float ErDemandE() { return (gErDemEma > 0.f) ? gErDemEma : 0.f; }

float ErConvRoomE()
{
	return gErFreeEma + EMakeInFlight() - ConvCapE() - ConvCapInFlight();
}

// ---- the army's share of the threat ----
float gErQ = 1.f;
float gErA = 0.f, gErContact = 0.f, gErRaid = 0.f, gErKill = 1.f, gErR = 0.f;
float gErContactPk = 0.f;
float gErLossPk = 0.f;
float gErLossSeen = 0.f;
int gErArmyAt = -1;
float gErKRaw = 0.f;

float EcoReturnArmyMul()
{
	// apex_er_q (the 10-24 review): q reads kill = 0 whenever we have less army than them, so all four consumers
	// (the budget row, the army target's map-share gap, the rush extra, small_hard's k) cut army when behind
	return (EcoReturnOn() && (ai.GetTunable("apex_er_q", TUNE_ER_Q) > 0.f)) ? gErQ : 1.f;
}

void ErArmyRefresh()
{
	const int dt = (gErArmyAt < 0) ? 0 : (ai.frame - gErArmyAt);
	gErArmyAt = ai.frame;
	const float hl = ai.GetTunable("apex_seen_halflife", TUNE_SEEN_HALFLIFE);
	const float decay = ((hl > 0.f) && (dt > 0)) ? pow(0.5f, (float(dt) / float(SECOND)) / hl) : 1.f;
	const float all = Military::DangerArriveS(float(Military::DG_BINS) * Military::DG_BIN_S);
	const float edge = Military::FoeMemReady() ? Military::FoeMemCum(true, 0.f) : Military::DangerArriveS(0.f);
	float c = 0.f;
	if (edge > 0.f)
		c = edge / ((all > edge) ? all : edge);
	gErContactPk *= decay;
	if (c > gErContactPk)
		gErContactPk = c;
	gErContact = gErContactPk;
	const float lostNow = Military::gNrEcoLostM;
	gErLossPk = gErLossPk * decay + ((lostNow > gErLossSeen) ? (lostNow - gErLossSeen) : 0.f);
	gErLossSeen = lostNow;
	const float base = ArmyTargetBase();
	gErRaid = (gErLossPk + base > 1.f) ? gErLossPk / (gErLossPk + base) : 0.f;
	gErA = 1.f - (1.f - gErContact) * (1.f - gErRaid);
	const float foe = Military::EnemyArmyCost();
	const float ours = Military::TeamArmyCost();
	gErR = (foe > 1.f) ? ours / foe : -1.f;
	if (foe <= 1.f)
		gErKill = 1.f;
	else
		gErKill = (gErR > 1.f) ? (1.f - 1.f / (gErR * gErR)) : 0.f;
	gErQ = gErA + (1.f - gErA) * gErKill;
}

// ---- the instrument ----
array<int> gErPN(3, 0);
array<float> gErPGain(3, 0.f);
array<float> gErPCost(3, 0.f);
array<float> gErPV(3, 0.f);
array<float> gErPBest(3, 0.f);
array<int> gErExec(3, 0);
array<int> gErBuilt(3, 0);
float gErChewSum = 0.f;
int gErChewN = 0;
int gErLogAt = 1800;

int ErSlot(int kind)
{
	if ((kind == WK_MEX) || (kind == WK_MEXUP))
		return 0;
	if ((kind == WK_ENERGY) || (kind == WK_GEO))
		return 1;
	if (kind == WK_CONVERT)
		return 2;
	return -1;
}

void ErNotePrice(int kind, Want@ w)
{
	const int s = ErSlot(kind);
	if ((s < 0) || (w is null) || (w.value <= 0.f))
		return;
	++gErPN[s];
	gErPGain[s] += w.gain;
	gErPCost[s] += w.mCost + w.tCost;
	gErPV[s] += w.value;
	if (w.value > gErPBest[s])
		gErPBest[s] = w.value;
}

void ErNoteChew(float chew)
{
	gErChewSum += chew;
	++gErChewN;
}

void ErNoteExec(int kind)
{
	const int s = ErSlot(kind);
	if (s >= 0)
		++gErExec[s];
}

void ErNoteBuilt(int defId)
{
	if (Catalog::gMobile[defId])
		return;
	if (Catalog::gExtractsM[defId] > 0.f)
		++gErBuilt[0];
	else if (Catalog::gConvCapacity[defId] > 0.f)
		++gErBuilt[2];
	else if (Catalog::gMakeE[defId] > 1.f)
		++gErBuilt[1];
}

void EcoReturnUpdate()
{
	TrackEPull();
	ErArmyRefresh();
	if (ai.frame < gErLogAt)
		return;
	gErLogAt = ai.frame + 60 * SECOND;
	const array<string> nm = {"mex", "energy", "conv"};
	string ps = "";
	for (uint s = 0; s < 3; ++s) {
		const float n = float((gErPN[s] > 0) ? gErPN[s] : 1);
		ps += " " + nm[s] + "=" + gErPN[s] + "@g" + formatFloat(gErPGain[s] / n, "", 0, 2)
			+ "/c" + formatFloat(gErPCost[s] / n, "", 0, 0)
			+ "/v" + formatFloat(1000.f * gErPV[s] / n, "", 0, 2)
			+ "/best" + formatFloat(1000.f * gErPBest[s], "", 0, 2);
		gErPN[s] = 0;
		gErPGain[s] = 0.f;
		gErPCost[s] = 0.f;
		gErPV[s] = 0.f;
		gErPBest[s] = 0.f;
	}
	const float conv = ConvUseE();
	AiLog(Factory::T() + "apex: ecoreturn-stat t=" + ai.teamId + " on=" + (EcoReturnOn() ? 1 : 0)
		+ " priced(n@gain/cost/v1000/best)" + ps
		+ " exec mex=" + gErExec[0] + " energy=" + gErExec[1] + " conv=" + gErExec[2]
		+ " built mex=" + gErBuilt[0] + " energy=" + gErBuilt[1] + " conv=" + gErBuilt[2]
		+ " | e inc=" + int(Eco::EInc()) + " use=" + int(aiEconomyMgr.energy.usage)
		+ " pull=" + int(Eco::EPull()) + " convUse=" + int(conv) + " convCap=" + int(ConvCapE())
		+ " convIF=" + int(ConvCapInFlight()) + " makeIF=" + int(EMakeInFlight())
		+ " free=" + int(gErFreeEma) + " room=" + int(ErConvRoomE()) + " demand=" + int(ErDemandE())
		+ " oldSurplus=" + int(gESurplusEma) + " oldWasted=" + int(gEExcessEma)
		+ " excess=" + int(aiEconomyMgr.energy.excess) + " sent=" + int(aiEconomyMgr.energy.sent)
		+ " chew=" + formatFloat((gErChewN > 0) ? gErChewSum / float(gErChewN) : 0.f, "", 0, 1)
		+ " | army q=" + formatFloat(gErQ, "", 0, 2) + " a=" + formatFloat(gErA, "", 0, 2)
		+ " contact=" + formatFloat(gErContact, "", 0, 2) + " raid=" + formatFloat(gErRaid, "", 0, 2)
		+ "(" + int(gErLossPk) + "m)" + " kill=" + formatFloat(gErKill, "", 0, 2)
		+ " r=" + formatFloat(gErR, "", 0, 2)
		+ " k=" + formatFloat(gErKRaw, "", 0, 2) + "->" + formatFloat(SmallHardK(), "", 0, 2)
		+ " rushX=" + int(RushFloorExtra()) + " mapGap=" + formatFloat(MapShareGap(), "", 0, 2)
		+ " armyRow=" + formatFloat(Brain::TargetShare(Brain::ARMY), "", 0, 2)
		+ " ecoRow=" + formatFloat(Brain::TargetShare(Brain::ECONOMY), "", 0, 2)
		+ " tgt=" + int(ArmyTarget()) + " army=" + int(ArmyValue()));
	for (uint s = 0; s < 3; ++s) {
		gErExec[s] = 0;
		gErBuilt[s] = 0;
	}
	gErChewSum = 0.f;
	gErChewN = 0;
}

}  // namespace Market
