namespace Market {

// SMALL MAP, HARD (apex_small_hard, his 2026-10-16: on a small map go really hard into
// military, starve their extractors, kill their army, control the map, the commander
// stays home supporting the factory). Every term is scaled by contact k, which is 0
// wherever their walk outlasts the time they need to outbuild our holding army, so a
// large map prices exactly as before. Refreshed every 5 s; elections read the cache.
//   Tc     = rush.as straight Tc x rho, rho = our pathfinder's walk / straight line
//   foeInc = their seen extractors + occ x their likely unseen spots (nearer their box)
//            + our non-extraction income per seat x their seats; occ = our share of our side
//   R      = foeInc x our EcoPowerM / metal income x their army share (rush.as)
//   T_A    = ArmyTargetBase x parity / (R / fighting seats)
//   k      = max(0, (T_A - Tc) / (T_A + Tc))
//   arrive = seen army + their commanders (strength in basic-fighter metal) + R x Tc
//   floor  += k x (commanders + R x Tc) x parity / fighting seats
//   hold   = our side's army / (ours + arrive)        phi = foeExtr x Tc / (that + arrive)
// Mex and expansion pricing, and the payback horizon, are untouched (the 10-15 lesson).

bool gSmhOn = false;
bool gSmhOnRead = false;
int gSmhAt = -999999;
int gSmhLogAt = 1800;
float gSmhK = 0.f;
float gSmhTc = -1.f, gSmhTcLine = -1.f, gSmhRho = 1.f;
float gSmhWalk = -1.f, gSmhLine = 0.f;
int gSmhWalkId = -1;
int gSmhWalkAt = -999999;
int gSmhWalkDef = 0;
float gSmhTA = 0.f;
float gSmhFoeExtr = 0.f, gSmhFoeInc = 0.f, gSmhR = 0.f, gSmhOcc = 0.f;
int gSmhFoeSeenN = 0, gSmhFoeLikelyN = 0;
float gSmhSeen = 0.f, gSmhComM = 0.f, gSmhArrive = 0.f;
float gSmhFloorX = 0.f;
float gSmhHold = 0.f, gSmhPhi = 0.f;
float gSmhGapFrac = 0.f;
int gSmhFoes = 1;
int gSmhComDef = 0;
float gSmhMps = 0.f;          // metal per unit of strength, basic fighters
int gSmhComSeen = 0;
AIFloat3 gSmhBox;
bool gSmhHasTgt = false;
AIFloat3 gSmhTgt;
float gSmhTgtNet = 0.f;
int gSmhCand = 0, gSmhPickAt = -1, gSmhOps = 0;
int gSmhRaidFoe = 0, gSmhMexKilled = 0, gSmhComPriced = 0, gSmhRaidPriced = 0;
array<int> gSmhMixN = {0, 0, 0, 0};       // scout, raider, main, con
array<float> gSmhMixM = {0.f, 0.f, 0.f, 0.f};
array<int> gSmhJobN = {0, 0, 0, 0, 0, 0, 0, 0};  // assist, mex, eco, plant, defence, fight, retreat, other
const array<string> SH_JOBS = {"assist", "mex", "eco", "plant", "def", "fight", "retreat", "other"};

bool SmallHardOn()
{
	if (!gSmhOnRead) {
		gSmhOnRead = true;
		gSmhOn = ai.GetTunable("apex_small_hard", TUNE_SMALL_HARD) > 0.f;
	}
	return gSmhOn;
}

float SmallHardK() { return gSmhK; }
float SmallHardFloorExtra() { return gSmhFloorX; }
float SmallHardRaidW() { return gSmhK * gSmhPhi; }
float SmallHardComArmyW() { return gSmhK * gSmhGapFrac; }

// Seconds of their income an extractor kill denies beyond their rebuild: the rest of the
// horizon, as often as we hold the ground.
float SmallHardDenyS(float rebuildS)
{
	if (gSmhK <= 0.f)
		return 0.f;
	PrTuneFill();
	const float left = gPrPaybackH - rebuildS;
	return (left > 0.f) ? gSmhK * gSmhHold * left : 0.f;
}

// Their commanders we do not see, as a presence weight at their box (0 on long contact).
float SmallHardComPrior(AIFloat3 &out at, int &out def)
{
	def = gSmhComDef;
	at = gSmhBox;
	if ((gSmhK <= 0.f) || (gSmhComDef <= 0))
		return 0.f;
	const int n = gSmhFoes - gSmhComSeen;
	return (n > 0) ? gSmhK * float(n) : 0.f;
}

// Our own commander's def stands in for theirs; its strength in the metal of the
// cheapest ground fighter each basic land plant makes. Never cache a zero.
void ShPriorsFill()
{
	if (gSmhComDef <= 0) {
		const array<int>@ own = OwnedDefs();
		for (uint i = 0; i < own.length(); ++i) {
			const int d = own[i];
			if ((gOwnCount[d] > 0) && Catalog::gMobile[d] && Catalog::Def(d).IsRoleAny(Unit::Role::COMM.mask)) {
				gSmhComDef = d;
				break;
			}
		}
	}
	if ((gSmhMps > 0.f) && (gSmhWalkDef > 0))
		return;
	float sumM = 0.f, sumS = 0.f, cheapest = 0.f;
	int walkDef = 0;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!Catalog::gAvailable[d] || Catalog::gMobile[d]
			|| ((Factory::userData[d].attr & Factory::Attr::T1) == 0)
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
		if (best <= 0)
			continue;
		sumM += Catalog::gCostM[best];
		sumS += UnitStrength(best);
		if ((walkDef <= 0) || (Catalog::gCostM[best] < cheapest)) {
			walkDef = best;
			cheapest = Catalog::gCostM[best];
		}
	}
	if (sumS > 0.f)
		gSmhMps = sumM / sumS;
	gSmhWalkDef = walkDef;
}

// Their box to our home over our own pathfinder's grid, re-flooded each minute.
void ShWalkStep(const AIFloat3& in box)
{
	const float ring = 256.f;
	if (gSmhWalkId >= 0) {
		const float c = ai.WalkMapCost(gSmhWalkId, Builder::gHomePos, ring);
		if (c > -1.5f) {
			gSmhLine = box.distance2D(Builder::gHomePos);
			gSmhWalk = (c >= 0.f) ? (c + ring) : -1.f;
			float rho = ((c >= 0.f) && (gSmhLine > 1.f)) ? (gSmhWalk / gSmhLine) : 1.f;
			gSmhRho = (rho > 1.f) ? rho : 1.f;   // a walk is never shorter than the line
			gSmhWalkId = -1;
		}
	}
	if ((gSmhWalkId < 0) && (gSmhWalkDef > 0) && (ai.frame >= gSmhWalkAt + 60 * SECOND)) {
		gSmhWalkAt = ai.frame;
		gSmhWalkId = ai.WalkMapStart(Catalog::Def(gSmhWalkDef), box);
	}
}

// Their likely extraction income from the public spot map: what we have seen them hold,
// plus their side's open spots at the share of our own side we hold.
void ShFoeIncome(const AIFloat3& in box)
{
	gSmhFoeExtr = 0.f;
	gSmhFoeSeenN = 0;
	gSmhFoeLikelyN = 0;
	if ((gMsHeld.length() == 0) || (gMsHeld.length() != gAllSpots.length()))
		return;
	int ourSide = 0, ourHeld = 0;
	float openInc = 0.f;
	const AIFloat3 home = Builder::gHomePos;
	for (uint s = 0; s < gMsHeld.length(); ++s) {
		const int m = gMsHeld[s];
		const AIFloat3 p = gAllSpots[s];
		const bool theirs = p.distance2D(box) < p.distance2D(home);
		if (m == 2) {
			gSmhFoeExtr += gAllSpotInc[s] * Catalog::gExtractsM[gMsFoeDef[s]];
			++gSmhFoeSeenN;
		} else if (theirs) {
			if (m == 0) {
				openInc += gAllSpotInc[s];
				++gSmhFoeLikelyN;
			}
		} else {
			++ourSide;
			if (m == 1)
				++ourHeld;
		}
	}
	gSmhOcc = (ourSide > 0) ? float(ourHeld) / float(ourSide) : 0.f;
	gSmhFoeExtr += gSmhOcc * openInc * LeastExtract();
}

void ShComSeenScan()
{
	gSmhComSeen = 0;
	const int nG = aiEnemyMgr.GetEnemyGroupCount();
	for (int gi = 0; gi < nG; ++gi) {
		const int nU = aiEnemyMgr.GetEnemyGroupUnitCount(gi);
		for (int k = 0; k < nU; ++k) {
			const int d = aiEnemyMgr.GetEnemyGroupUnitDef(gi, k);
			if (Catalog::ValidId(d) && Catalog::gMobile[d] && Catalog::Def(d).IsRoleAny(Unit::Role::COMM.mask))
				++gSmhComSeen;
		}
	}
}

// Their extractor whose income denied for the rest of the horizon, as often as we hold
// the ground, plus the structures there, best beats the expected loss of taking it.
void ShPickTarget(const AIFloat3& in box)
{
	gSmhHasTgt = false;
	gSmhTgtNet = 0.f;
	gSmhCand = 0;
	if ((gSmhK <= 0.f) || (gMsHeld.length() != gAllSpots.length()))
		return;
	PrTuneFill();
	const float H = gPrPaybackH;
	const float teamM = Military::TeamArmyCost();
	float F = teamM * 0.017f;   // Grunt-class power per metal, as massing.as
	const float gath = TaSum(BOARD_GATHER);
	const float atk = TaSum(BOARD_TA_ATK);
	F = (gath > F) ? gath : F;
	F = (atk > F) ? atk : F;
	AIFloat3 cAt;
	int cDef = 0;
	const float cw = SmallHardComPrior(cAt, cDef);
	for (uint s = 0; s < gMsHeld.length(); ++s) {
		if (gMsHeld[s] != 2)
			continue;
		const AIFloat3 p = gMsFoePos[s];
		++gSmhCand;
		const float prize = aiEnemyMgr.GetEnemyStructCostAt(p, Military::HUNT_R)
				+ gAllSpotInc[s] * Catalog::gExtractsM[gMsFoeDef[s]] * H * gSmhHold;
		float E = aiMilitaryMgr.GetEnemyInflNear(p, Military::HUNT_R + PUSH_STAND);
		if ((cw > 0.f) && (cAt.distance2D(p) <= Military::HUNT_R + PUSH_STAND + Catalog::gMaxRange[cDef]))
			E += cw * Catalog::gPower[cDef];
		const float lossF = Military::NrLossFrac(E, F);
		const float net = prize * (1.f - lossF) - lossF * teamM;
		if ((net > 0.f) && (!gSmhHasTgt || (net > gSmhTgtNet))) {
			gSmhTgtNet = net;
			gSmhTgt = p;
			gSmhHasTgt = true;
		}
	}
}

void ShRefresh()
{
	gSmhAt = ai.frame;
	gSmhK = 0.f;
	gSmhFloorX = 0.f;
	if (!Builder::gHomeSet)
		return;
	ShPriorsFill();
	const AIFloat3 box = aiSetupMgr.GetEnemyBoxCentre();
	if (!OnMap(box))
		return;
	gSmhBox = box;
	ShWalkStep(box);
	ShComSeenScan();
	ShFoeIncome(box);
	gSmhTcLine = gRushTc;
	gSmhTc = (gRushTc >= 0.f) ? gRushTc * gSmhRho : -1.f;
	array<Id>@ mates = ai.GetTeamIds();
	const int ours = ((mates is null) || (mates.length() < 1)) ? 1 : int(mates.length());
	gSmhFoes = int(ai.GetEnemyTeamSize());
	if (gSmhFoes < 1)
		gSmhFoes = ours;
	float ourExtr = 0.f;
	for (uint i = 0; i < gLSpot.length(); ++i)
		ourExtr += gLIncome[i] * gLExtract[i];
	ourExtr *= IncomeMult();
	const float mInc = Eco::MInc();
	const float other = mInc - ourExtr;
	gSmhFoeInc = gSmhFoeExtr + ((other > 0.f) ? other : 0.f) * float(gSmhFoes) / float(ours);
	// their energy carried at our own power-to-metal ratio, the currency ArmyTargetBase is in
	const float powPerM = (mInc > 0.1f) ? EcoPowerM() / mInc : 1.f;
	gSmhR = gSmhFoeInc * ((powPerM > 1.f) ? powPerM : 1.f) * gRushShare;
	const int fighting = (gRushFighting > 0) ? gRushFighting : 1;
	gSmhSeen = Military::EnemyArmyCost();
	gSmhComM = ((gSmhComDef > 0) && (gSmhMps > 0.f)) ? UnitStrength(gSmhComDef) * gSmhMps * float(gSmhFoes) : 0.f;
	const float prod = (gSmhTc > 0.f) ? gSmhR * gSmhTc : 0.f;
	gSmhArrive = gSmhSeen + gSmhComM + prod;
	const float rSeat = gSmhR / float(fighting);
	gSmhTA = (rSeat > 0.f) ? ArmyTargetBase() * ARMY_FLOOR_PARITY / rSeat : 0.f;
	if ((gSmhTc >= 0.f) && (gSmhTA > gSmhTc))
		gSmhK = (gSmhTA - gSmhTc) / (gSmhTA + gSmhTc);
	gSmhFloorX = gSmhK * (gSmhComM + prod) * ARMY_FLOOR_PARITY / float(fighting);
	const float A = Military::TeamArmyCost();
	gSmhHold = (A + gSmhArrive > 1.f) ? A / (A + gSmhArrive) : 0.f;
	const float U = gSmhFoeExtr * ((gSmhTc > 0.f) ? gSmhTc : 0.f);
	gSmhPhi = (U + gSmhArrive > 1.f) ? U / (U + gSmhArrive) : 0.f;
	const float tgt = ArmyTarget();
	const float gap = tgt - ArmyValue();
	gSmhGapFrac = ((tgt > 1.f) && (gap > 0.f)) ? gap / tgt : 0.f;
	ShPickTarget(box);
}

bool SmallHardExpansion(AIFloat3 &out at, float &out r)
{
	if (!gSmhHasTgt || (gSmhK <= 0.f))
		return false;
	at = gSmhTgt;
	r = Military::HUNT_R;
	gSmhPickAt = ai.frame;
	return true;
}

// Under the NORMAL plan the team operation runs while a target stands; an expansion
// operation under way is let finish.
bool SmallHardPush()
{
	if (!gSmhOn)
		return false;
	return (gSmhHasTgt && (gSmhK > 0.f)) || (TeamOpOn() && (int(ai.GetTeamBoard(BOARD_TA_KIND, 0.f)) == 5));
}

void SmallHardNoteOp(int kind)
{
	if ((kind == 5) && (gSmhPickAt == ai.frame))
		++gSmhOps;
}

void SmallHardNoteRaid(const AIFloat3& in at)
{
	if (!gSmhOn || (gSmhK <= 0.f))
		return;
	const int s = MsSpotOf(at);
	if ((s >= 0) && (uint(s) < gMsHeld.length()) && (gMsHeld[s] != 1))
		++gSmhRaidFoe;
}

void SmallHardNoteDeath(int d, bool byUs)
{
	if (byUs && gSmhOn && Catalog::ValidId(d) && !Catalog::gMobile[d] && (Catalog::gExtractsM[d] > 0.f))
		++gSmhMexKilled;
}

void SmallHardNoteOrder(const CCircuitDef@ o)
{
	if (!gSmhOn || (o is null))
		return;
	const int d = int(o.id);
	int c = 2;
	if (Catalog::gBuilder[d])
		c = 3;
	else if (o.IsRoleAny(Unit::Role::SCOUT.mask) || (Catalog::gPower[d] <= 1.01f))
		c = 0;
	else if (o.IsRoleAny(Unit::Role::RAIDER.mask))
		c = 1;
	++gSmhMixN[c];
	gSmhMixM[c] += Catalog::gCostM[d];
}

void SmallHardComTick(CCircuitUnit@ u)
{
	if (!gSmhOn || (u is null))
		return;
	int c = 7;
	if (gComDec == COM_FIGHT)
		c = 5;
	else if (gComDec == COM_RETREAT)
		c = 6;
	else if ((u.task !is null) && (u.task.GetType() == Task::Type::BUILDER)) {
		const int bt = int(u.task.GetBuildType());
		if ((bt == int(Task::BuildType::GUARD)) || (bt == int(Task::BuildType::REPAIR)))
			c = 0;
		else if ((bt == int(Task::BuildType::MEX)) || (bt == int(Task::BuildType::MEXUP)))
			c = 1;
		else if ((bt == int(Task::BuildType::ENERGY)) || (bt == int(Task::BuildType::CONVERT))
			|| (bt == int(Task::BuildType::STORE)) || (bt == int(Task::BuildType::GEO)))
			c = 2;
		else if ((bt == int(Task::BuildType::FACTORY)) || (bt == int(Task::BuildType::NANO)))
			c = 3;
		else if (bt == int(Task::BuildType::DEFENCE))
			c = 4;
	}
	++gSmhJobN[c];
}

void SmallHardNoteComPriced() { ++gSmhComPriced; }
void SmallHardNoteRaidPriced() { ++gSmhRaidPriced; }

void SmallHardUpdate()
{
	if (!SmallHardOn())
		return;
	if (ai.frame >= gSmhAt + 5 * SECOND)
		ShRefresh();
	if (ai.frame < gSmhLogAt)
		return;
	gSmhLogAt = ai.frame + 60 * SECOND;
	string mix = "";
	const array<string> names = {"scout", "raider", "main", "con"};
	for (uint i = 0; i < 4; ++i) {
		mix += " " + names[i] + "=" + gSmhMixN[i] + "/" + int(gSmhMixM[i]);
		gSmhMixN[i] = 0;
		gSmhMixM[i] = 0.f;
	}
	string jobs = "";
	for (uint i = 0; i < gSmhJobN.length(); ++i) {
		jobs += ((i == 0) ? "" : ",") + SH_JOBS[i] + "=" + gSmhJobN[i];
		gSmhJobN[i] = 0;
	}
	AiLog(Factory::T() + "apex: smallhard-stat t=" + ai.teamId
		+ " Tc=" + formatFloat(gSmhTc, "", 0, 0) + " line=" + formatFloat(gSmhTcLine, "", 0, 0)
		+ " rho=" + formatFloat(gSmhRho, "", 0, 2)
		+ " walk=" + formatFloat(gSmhWalk, "", 0, 0) + "/" + formatFloat(gSmhLine, "", 0, 0)
		+ " TA=" + formatFloat(gSmhTA, "", 0, 0) + " k=" + formatFloat(gSmhK, "", 0, 2)
		+ " foeInc=" + formatFloat(gSmhFoeInc, "", 0, 1) + " extr=" + formatFloat(gSmhFoeExtr, "", 0, 1)
		+ " mex=" + gSmhFoeSeenN + "+" + gSmhFoeLikelyN + "x" + formatFloat(gSmhOcc, "", 0, 2)
		+ " R=" + formatFloat(gSmhR, "", 0, 2)
		+ " arrive=" + formatFloat(gSmhArrive, "", 0, 0) + "(seen " + formatFloat(gSmhSeen, "", 0, 0)
		+ " com " + formatFloat(gSmhComM, "", 0, 0) + " comSeen " + gSmhComSeen + ")"
		+ " floor=" + formatFloat(gArmyFloorRaw, "", 0, 0) + "->" + formatFloat(gArmyFloorRaw + RushFloorExtra() + gSmhFloorX, "", 0, 0)
		+ " full=" + formatFloat(ArmyTargetFull(), "", 0, 0)
		+ " tgt=" + formatFloat(ArmyTarget(), "", 0, 0) + " army=" + formatFloat(ArmyValue(), "", 0, 0)
		+ " hold=" + formatFloat(gSmhHold, "", 0, 2) + " phi=" + formatFloat(gSmhPhi, "", 0, 2)
		+ " comArmyW=" + formatFloat(SmallHardComArmyW(), "", 0, 2)
		+ " mix:" + mix
		+ " cand=" + gSmhCand + " tgtNet=" + formatFloat(gSmhTgtNet, "", 0, 0) + " ops=" + gSmhOps
		+ " raidFoe=" + gSmhRaidFoe + " mexKilled=" + gSmhMexKilled
		+ " comPrior=" + gSmhComPriced + "/" + gSmhRaidPriced
		+ " comJobs=" + jobs);
	gSmhComPriced = 0;
	gSmhRaidPriced = 0;
}

}  // namespace Market
