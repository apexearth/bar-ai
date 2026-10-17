namespace Market {

// RUSH AWARENESS (apex_rush_aware, his 2026-10-15: small maps, a T2 lab and many
// constructors while humans storm us with grunts). A race between their army
// and a big investment of ours:
//   Tc       = walk from their nearest base to our edge / their ground speed
//   lock     = metal of the investment, less the bank's feed share, / our metal income
//   rate     = their army output: our power per seat x their seats x army share
//   threat   = seen + rate x (lock - Tc)
// Built while the investment holds our income, their army walks in after Tc;
// with lock < Tc our own output answers in time and nothing is added.
// Refreshed every 5 s on AiUpdate; elections read the cache.

float gRushTc = -1.f;
float gRushDist = -1.f;
float gRushSpd = 0.f;
bool gRushSpdSeen = false;
float gRushSeen = 0.f;
float gRushRate = 0.f;
float gRushShare = 0.f;
float gRushNextLock = 0.f;
float gRushParity = 0.f;    // parity / fighting seats: team threat -> this seat's share
int gRushFighting = 1;
float gRushMInc = 0.f;
float gRushBank = 0.f;
float gRushOnHand = 0.f;
bool gRushOn = false;
bool gRushOnRead = false;
int gRushAt = -999999;
int gRushLogAt = 0;
int gRushAsked = 0;
int gRushPriced = 0;
float gRushMinMul = 1.f;
float gRushSpdPrior = -1.f;

bool RushOn()
{
	if (!gRushOnRead) {
		gRushOnRead = true;
		gRushOn = ai.GetTunable("apex_rush_aware", TUNE_RUSH_AWARE) > 0.f;
	}
	return gRushOn;
}

// Their early ground army while unseen: the cheapest ground fighter each basic
// land plant makes, mean speed. Never cache a zero (availability settles late).
float RushSpeedPrior()
{
	if (gRushSpdPrior > 0.f)
		return gRushSpdPrior;
	float sum = 0.f;
	int n = 0;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!Catalog::gAvailable[d] || Catalog::gMobile[d]
			|| (PlantTier(d) != 1)
			|| (PlantClass(d) != PC_LAND))
			continue;
		const array<int>@ pr = Catalog::gBuildsList[d];
		int best = -1;
		for (uint q = 0; q < pr.length(); ++q) {
			const int pd = pr[q];
			if (!Catalog::gAvailable[pd] || !LineCombat(pd) || Catalog::gFlyer[pd]
				|| (Catalog::gSpeed[pd] <= 1.f))
				continue;
			if ((best < 0) || (Catalog::gCostM[pd] < Catalog::gCostM[best]))
				best = pd;
		}
		if (best > 0) {
			sum += Catalog::gSpeed[best];
			++n;
		}
	}
	if (n > 0)
		gRushSpdPrior = sum / float(n);
	return (n > 0) ? gRushSpdPrior : FoeSpeedCap();
}

// The cheapest plant of the tier above the highest we own; 0 past the gantry.
int gRushTierKey = -1;
float gRushTierCost = 0.f;
float RushNextTierCostM()
{
	const int want = !Factory::gHaveT2 ? int(Factory::Attr::T2)
			: (!Factory::gHaveT3 ? int(Factory::Attr::T3) : 0);
	if (want == 0)
		return 0.f;
	if ((want == gRushTierKey) && (gRushTierCost > 0.f))
		return gRushTierCost;
	gRushTierKey = want;
	float best = 0.f;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!Catalog::gAvailable[d] || Catalog::gMobile[d]
			|| ((Factory::userData[d].attr & want) == 0))
			continue;
		if ((best <= 0.f) || (Catalog::gCostM[d] < best))
			best = Catalog::gCostM[d];
	}
	gRushTierCost = best;
	return best;
}

void RushRefresh()
{
	gRushAt = ai.frame;
	gRushTc = -1.f;
	if (!Builder::gHomeSet)
		return;
	bool found = false;
	float dist = 0.f;
	const AIFloat3 box = aiSetupMgr.GetEnemyBoxCentre();
	if (OnMap(box)) {
		dist = Military::DgRim(box);
		found = true;
	}
	const AIFloat3 anc = Front::FoeAnchor();
	if (OnMap(anc)) {
		const float da = Military::DgRim(anc);
		if (!found || (da < dist))
			dist = da;
		found = true;
	}
	if (!found)
		return;
	if (dist < 0.f)
		dist = 0.f;
	gRushDist = dist;
	gRushSpdSeen = Military::gDgFoeSpd > 1.f;
	gRushSpd = gRushSpdSeen ? Military::gDgFoeSpd : RushSpeedPrior();
	if (gRushSpd <= 1.f)
		return;
	gRushTc = dist / gRushSpd;

	gRushSeen = Military::EnemyArmyCost();
	// Army share of what they field: what we have seen of them, weighted
	// against our own target share as if we had seen one seat's economy.
	const float prior = Brain::TargetShare(Brain::ARMY);
	const float k = EconAssetsM();
	const float foeStruct = aiEnemyMgr.GetEnemyStructCost();
	const float seenAll = gRushSeen + ((foeStruct > 0.f) ? foeStruct : 0.f);
	gRushShare = (seenAll + k > 1.f) ? ((gRushSeen + prior * k) / (seenAll + k)) : prior;

	array<Id>@ mates = ai.GetTeamIds();
	const int ours = ((mates is null) || (mates.length() < 1)) ? 1 : int(mates.length());
	int foes = int(ai.GetEnemyTeamSize());
	if (foes < 1)
		foes = ours;
	gRushRate = EcoPowerM() * float(foes) * gRushShare;

	int fighting = 0;
	for (uint m = 0; (mates !is null) && (m < mates.length()); ++m)
		if (ai.ReadTeamValue(int(mates[m]), Military::TV_ECOSEAT, 0.f) < 0.5f)
			++fighting;
	if (fighting < 1)
		fighting = 1;
	gRushFighting = fighting;
	gRushParity = ARMY_FLOOR_PARITY / float(fighting);

	gRushMInc = Eco::MInc();
	gRushBank = Eco::MCur() * ai.GetTunable("apex_vw_feed_bank", TUNE_VW_FEED_BANK);
	gRushNextLock = RushLockS(RushNextTierCostM());
	gRushOnHand = ArmyValue() + gProtM;
}

// Seconds of income the build holds, the bank's share paid up front (ValueOf's feed).
float RushLockS(float costM)
{
	if ((costM <= 0.f) || (gRushMInc <= 0.1f))
		return 0.f;
	const float owed = costM - gRushBank;
	return (owed > 0.f) ? (owed / gRushMInc) : 0.f;
}

// What a lock of `lockS` seconds adds on top of the seen army, this seat's share.
float RushExtra(float lockS)
{
	if ((gRushTc < 0.f) || (lockS <= gRushTc))
		return 0.f;
	return gRushRate * (lockS - gRushTc) * gRushParity;
}

// Added to ArmyFloor: the window our next tier opens.
float RushFloorExtra()
{
	if (!RushOn())
		return 0.f;
	return RushExtra(gRushNextLock) * EcoReturnArmyMul();
}

// A big non-defending investment's gain is scaled by the share of the rush its
// window opens that we can hold, over the share the seen army alone allows.
float RushMul(float costM)
{
	if (!RushOn() || (gRushTc < 0.f) || (gRushMInc <= 0.1f))
		return 1.f;
	++gRushAsked;
	const float extra = RushExtra(RushLockS(costM));
	if (extra <= 0.f)
		return 1.f;
	const float base = gRushSeen * gRushParity;
	// one second of income on both sides: no army is a very low price, never a zero (no hard vetoes)
	const float have = gRushOnHand + gRushMInc;
	float with = have / (base + extra + gRushMInc);
	if (with >= 1.f)
		return 1.f;
	float without = (base > 0.f) ? (have / (base + gRushMInc)) : 1.f;
	if (without > 1.f)
		without = 1.f;
	const float mul = (without > 0.f) ? (with / without) : 0.f;
	++gRushPriced;
	if (mul < gRushMinMul)
		gRushMinMul = mul;
	return mul;
}

void RushUpdate()
{
	if (!RushOn() && !PressureOn() && !SmallHardOn())
		return;
	if (ai.frame >= gRushAt + 5 * SECOND)
		RushRefresh();
	if (!RushOn() || (ai.frame < gRushLogAt))
		return;
	gRushLogAt = ai.frame + 60 * SECOND;
	const float raw = gArmyFloorRaw;
	const float extra = RushFloorExtra();
	AiLog(Factory::T() + "apex: rush-stat t=" + ai.teamId
		+ " Tc=" + formatFloat(gRushTc, "", 0, 0)
		+ " dist=" + formatFloat(gRushDist, "", 0, 0)
		+ " spd=" + formatFloat(gRushSpd, "", 0, 1) + (gRushSpdSeen ? "(seen)" : "(prior)")
		+ " seen=" + formatFloat(gRushSeen, "", 0, 0)
		+ " share=" + formatFloat(gRushShare, "", 0, 2)
		+ " rate=" + formatFloat(gRushRate, "", 0, 2)
		+ " lock=" + formatFloat(gRushNextLock, "", 0, 0)
		+ " threat=" + formatFloat(gRushSeen + ((gRushParity > 0.f) ? extra / gRushParity : 0.f), "", 0, 0)
		+ " army=" + formatFloat(ArmyValue(), "", 0, 0)
		+ " onHand=" + formatFloat(gRushOnHand, "", 0, 0)
		+ " full=" + formatFloat(ArmyTargetFull(), "", 0, 0)
		+ " floor=" + formatFloat(raw, "", 0, 0) + "->" + formatFloat(raw + extra, "", 0, 0)
		+ " minMul=" + formatFloat(gRushMinMul, "", 0, 2)
		+ " priced=" + gRushPriced + "/" + gRushAsked);
	gRushAsked = 0;
	gRushPriced = 0;
	gRushMinMul = 1.f;
}

}  // namespace Market
