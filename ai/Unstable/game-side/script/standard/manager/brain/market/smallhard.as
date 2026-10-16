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

bool gShOn = false;
bool gShOnRead = false;
int gShAt = -999999;
int gShLogAt = 1800;
float gShK = 0.f;
float gShTc = -1.f, gShTcLine = -1.f, gShRho = 1.f;
float gShWalk = -1.f, gShLine = 0.f;
int gShWalkId = -1;
int gShWalkAt = -999999;
int gShWalkDef = 0;
float gShTA = 0.f;
float gShFoeExtr = 0.f, gShFoeInc = 0.f, gShR = 0.f, gShOcc = 0.f;
int gShFoeSeenN = 0, gShFoeLikelyN = 0;
float gShSeen = 0.f, gShComM = 0.f, gShArrive = 0.f;
float gShFloorX = 0.f;
float gShHold = 0.f, gShPhi = 0.f;
float gShGapFrac = 0.f;
int gShFoes = 1;
int gShComDef = 0;
float gShMps = 0.f;          // metal per unit of strength, basic fighters
int gShComSeen = 0;
AIFloat3 gShBox;
bool gShHasTgt = false;
AIFloat3 gShTgt;
float gShTgtNet = 0.f;
int gShCand = 0, gShPickAt = -1, gShOps = 0;
int gShRaidFoe = 0, gShMexKilled = 0, gShComPriced = 0, gShRaidPriced = 0;
array<int> gShMixN = {0, 0, 0, 0};       // scout, raider, main, con
array<float> gShMixM = {0.f, 0.f, 0.f, 0.f};
array<int> gShJobN = {0, 0, 0, 0, 0, 0, 0, 0};  // assist, mex, eco, plant, defence, fight, retreat, other
const array<string> SH_JOBS = {"assist", "mex", "eco", "plant", "def", "fight", "retreat", "other"};

bool SmallHardOn()
{
	if (!gShOnRead) {
		gShOnRead = true;
		gShOn = ai.GetTunable("apex_small_hard", TUNE_SMALL_HARD) > 0.f;
	}
	return gShOn;
}

float SmallHardK() { return gShK; }
float SmallHardFloorExtra() { return gShFloorX; }
float SmallHardRaidW() { return gShK * gShPhi; }
float SmallHardComArmyW() { return gShK * gShGapFrac; }

// Seconds of their income an extractor kill denies beyond their rebuild: the rest of the
// horizon, as often as we hold the ground.
float SmallHardDenyS(float rebuildS)
{
	if (gShK <= 0.f)
		return 0.f;
	PrTuneFill();
	const float left = gPrPaybackH - rebuildS;
	return (left > 0.f) ? gShK * gShHold * left : 0.f;
}

// Their commanders we do not see, as a presence weight at their box (0 on long contact).
float SmallHardComPrior(AIFloat3 &out at, int &out def)
{
	def = gShComDef;
	at = gShBox;
	if ((gShK <= 0.f) || (gShComDef <= 0))
		return 0.f;
	const int n = gShFoes - gShComSeen;
	return (n > 0) ? gShK * float(n) : 0.f;
}

// Our own commander's def stands in for theirs; its strength in the metal of the
// cheapest ground fighter each basic land plant makes. Never cache a zero.
void ShPriorsFill()
{
	if (gShComDef <= 0) {
		const array<int>@ own = OwnedDefs();
		for (uint i = 0; i < own.length(); ++i) {
			const int d = own[i];
			if ((gOwnCount[d] > 0) && Catalog::gMobile[d] && Catalog::Def(d).IsRoleAny(Unit::Role::COMM.mask)) {
				gShComDef = d;
				break;
			}
		}
	}
	if ((gShMps > 0.f) && (gShWalkDef > 0))
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
		gShMps = sumM / sumS;
	gShWalkDef = walkDef;
}

// Their box to our home over our own pathfinder's grid, re-flooded each minute.
void ShWalkStep(const AIFloat3& in box)
{
	const float ring = 256.f;
	if (gShWalkId >= 0) {
		const float c = ai.WalkMapCost(gShWalkId, Builder::gHomePos, ring);
		if (c > -1.5f) {
			gShLine = box.distance2D(Builder::gHomePos);
			gShWalk = (c >= 0.f) ? (c + ring) : -1.f;
			float rho = ((c >= 0.f) && (gShLine > 1.f)) ? (gShWalk / gShLine) : 1.f;
			gShRho = (rho > 1.f) ? rho : 1.f;   // a walk is never shorter than the line
			gShWalkId = -1;
		}
	}
	if ((gShWalkId < 0) && (gShWalkDef > 0) && (ai.frame >= gShWalkAt + 60 * SECOND)) {
		gShWalkAt = ai.frame;
		gShWalkId = ai.WalkMapStart(Catalog::Def(gShWalkDef), box);
	}
}

// Their likely extraction income from the public spot map: what we have seen them hold,
// plus their side's open spots at the share of our own side we hold.
void ShFoeIncome(const AIFloat3& in box)
{
	gShFoeExtr = 0.f;
	gShFoeSeenN = 0;
	gShFoeLikelyN = 0;
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
			gShFoeExtr += gAllSpotInc[s] * Catalog::gExtractsM[gMsFoeDef[s]];
			++gShFoeSeenN;
		} else if (theirs) {
			if (m == 0) {
				openInc += gAllSpotInc[s];
				++gShFoeLikelyN;
			}
		} else {
			++ourSide;
			if (m == 1)
				++ourHeld;
		}
	}
	gShOcc = (ourSide > 0) ? float(ourHeld) / float(ourSide) : 0.f;
	gShFoeExtr += gShOcc * openInc * LeastExtract();
}

void ShComSeenScan()
{
	gShComSeen = 0;
	const int nG = aiEnemyMgr.GetEnemyGroupCount();
	for (int gi = 0; gi < nG; ++gi) {
		const int nU = aiEnemyMgr.GetEnemyGroupUnitCount(gi);
		for (int k = 0; k < nU; ++k) {
			const int d = aiEnemyMgr.GetEnemyGroupUnitDef(gi, k);
			if (Catalog::ValidId(d) && Catalog::gMobile[d] && Catalog::Def(d).IsRoleAny(Unit::Role::COMM.mask))
				++gShComSeen;
		}
	}
}

// Their extractor whose income denied for the rest of the horizon, as often as we hold
// the ground, plus the structures there, best beats the expected loss of taking it.
void ShPickTarget(const AIFloat3& in box)
{
	gShHasTgt = false;
	gShTgtNet = 0.f;
	gShCand = 0;
	if ((gShK <= 0.f) || (gMsHeld.length() != gAllSpots.length()))
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
		++gShCand;
		const float prize = aiEnemyMgr.GetEnemyStructCostAt(p, Military::HUNT_R)
				+ gAllSpotInc[s] * Catalog::gExtractsM[gMsFoeDef[s]] * H * gShHold;
		float E = aiMilitaryMgr.GetEnemyInflNear(p, Military::HUNT_R + PUSH_STAND);
		if ((cw > 0.f) && (cAt.distance2D(p) <= Military::HUNT_R + PUSH_STAND + Catalog::gMaxRange[cDef]))
			E += cw * Catalog::gPower[cDef];
		const float lossF = Military::NrLossFrac(E, F);
		const float net = prize * (1.f - lossF) - lossF * teamM;
		if ((net > 0.f) && (!gShHasTgt || (net > gShTgtNet))) {
			gShTgtNet = net;
			gShTgt = p;
			gShHasTgt = true;
		}
	}
}

void ShRefresh()
{
	gShAt = ai.frame;
	gShK = 0.f;
	gShFloorX = 0.f;
	if (!Builder::gHomeSet)
		return;
	ShPriorsFill();
	const AIFloat3 box = aiSetupMgr.GetEnemyBoxCentre();
	if (!OnMap(box))
		return;
	gShBox = box;
	ShWalkStep(box);
	ShComSeenScan();
	ShFoeIncome(box);
	gShTcLine = gRushTc;
	gShTc = (gRushTc >= 0.f) ? gRushTc * gShRho : -1.f;
	array<Id>@ mates = ai.GetTeamIds();
	const int ours = ((mates is null) || (mates.length() < 1)) ? 1 : int(mates.length());
	gShFoes = int(ai.GetEnemyTeamSize());
	if (gShFoes < 1)
		gShFoes = ours;
	float ourExtr = 0.f;
	for (uint i = 0; i < gLSpot.length(); ++i)
		ourExtr += gLIncome[i] * gLExtract[i];
	ourExtr *= IncomeMult();
	const float mInc = Eco::MInc();
	const float other = mInc - ourExtr;
	gShFoeInc = gShFoeExtr + ((other > 0.f) ? other : 0.f) * float(gShFoes) / float(ours);
	// their energy carried at our own power-to-metal ratio, the currency ArmyTargetBase is in
	const float powPerM = (mInc > 0.1f) ? EcoPowerM() / mInc : 1.f;
	gShR = gShFoeInc * ((powPerM > 1.f) ? powPerM : 1.f) * gRushShare;
	const int fighting = (gRushFighting > 0) ? gRushFighting : 1;
	gShSeen = Military::EnemyArmyCost();
	gShComM = ((gShComDef > 0) && (gShMps > 0.f)) ? UnitStrength(gShComDef) * gShMps * float(gShFoes) : 0.f;
	const float prod = (gShTc > 0.f) ? gShR * gShTc : 0.f;
	gShArrive = gShSeen + gShComM + prod;
	const float rSeat = gShR / float(fighting);
	gShTA = (rSeat > 0.f) ? ArmyTargetBase() * ARMY_FLOOR_PARITY / rSeat : 0.f;
	if ((gShTc >= 0.f) && (gShTA > gShTc))
		gShK = (gShTA - gShTc) / (gShTA + gShTc);
	gShFloorX = gShK * (gShComM + prod) * ARMY_FLOOR_PARITY / float(fighting);
	const float A = Military::TeamArmyCost();
	gShHold = (A + gShArrive > 1.f) ? A / (A + gShArrive) : 0.f;
	const float U = gShFoeExtr * ((gShTc > 0.f) ? gShTc : 0.f);
	gShPhi = (U + gShArrive > 1.f) ? U / (U + gShArrive) : 0.f;
	const float tgt = ArmyTarget();
	const float gap = tgt - ArmyValue();
	gShGapFrac = ((tgt > 1.f) && (gap > 0.f)) ? gap / tgt : 0.f;
	ShPickTarget(box);
}

bool SmallHardExpansion(AIFloat3 &out at, float &out r)
{
	if (!gShHasTgt || (gShK <= 0.f))
		return false;
	at = gShTgt;
	r = Military::HUNT_R;
	gShPickAt = ai.frame;
	return true;
}

// Under the NORMAL plan the team operation runs while a target stands; an expansion
// operation under way is let finish.
bool SmallHardPush()
{
	if (!gShOn)
		return false;
	return (gShHasTgt && (gShK > 0.f)) || (TeamOpOn() && (int(ai.GetTeamBoard(BOARD_TA_KIND, 0.f)) == 5));
}

void SmallHardNoteOp(int kind)
{
	if ((kind == 5) && (gShPickAt == ai.frame))
		++gShOps;
}

void SmallHardNoteRaid(const AIFloat3& in at)
{
	if (!gShOn || (gShK <= 0.f))
		return;
	const int s = MsSpotOf(at);
	if ((s >= 0) && (uint(s) < gMsHeld.length()) && (gMsHeld[s] != 1))
		++gShRaidFoe;
}

void SmallHardNoteDeath(int d, bool byUs)
{
	if (byUs && gShOn && Catalog::ValidId(d) && !Catalog::gMobile[d] && (Catalog::gExtractsM[d] > 0.f))
		++gShMexKilled;
}

void SmallHardNoteOrder(const CCircuitDef@ o)
{
	if (!gShOn || (o is null))
		return;
	const int d = int(o.id);
	int c = 2;
	if (Catalog::gBuilder[d])
		c = 3;
	else if (o.IsRoleAny(Unit::Role::SCOUT.mask) || (Catalog::gPower[d] <= 1.01f))
		c = 0;
	else if (o.IsRoleAny(Unit::Role::RAIDER.mask))
		c = 1;
	++gShMixN[c];
	gShMixM[c] += Catalog::gCostM[d];
}

void SmallHardComTick(CCircuitUnit@ u)
{
	if (!gShOn || (u is null))
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
	++gShJobN[c];
}

void SmallHardNoteComPriced() { ++gShComPriced; }
void SmallHardNoteRaidPriced() { ++gShRaidPriced; }

void SmallHardUpdate()
{
	if (!SmallHardOn())
		return;
	if (ai.frame >= gShAt + 5 * SECOND)
		ShRefresh();
	if (ai.frame < gShLogAt)
		return;
	gShLogAt = ai.frame + 60 * SECOND;
	string mix = "";
	const array<string> names = {"scout", "raider", "main", "con"};
	for (uint i = 0; i < 4; ++i) {
		mix += " " + names[i] + "=" + gShMixN[i] + "/" + int(gShMixM[i]);
		gShMixN[i] = 0;
		gShMixM[i] = 0.f;
	}
	string jobs = "";
	for (uint i = 0; i < gShJobN.length(); ++i) {
		jobs += ((i == 0) ? "" : ",") + SH_JOBS[i] + "=" + gShJobN[i];
		gShJobN[i] = 0;
	}
	AiLog(Factory::T() + "apex: smallhard-stat t=" + ai.teamId
		+ " Tc=" + formatFloat(gShTc, "", 0, 0) + " line=" + formatFloat(gShTcLine, "", 0, 0)
		+ " rho=" + formatFloat(gShRho, "", 0, 2)
		+ " walk=" + formatFloat(gShWalk, "", 0, 0) + "/" + formatFloat(gShLine, "", 0, 0)
		+ " TA=" + formatFloat(gShTA, "", 0, 0) + " k=" + formatFloat(gShK, "", 0, 2)
		+ " foeInc=" + formatFloat(gShFoeInc, "", 0, 1) + " extr=" + formatFloat(gShFoeExtr, "", 0, 1)
		+ " mex=" + gShFoeSeenN + "+" + gShFoeLikelyN + "x" + formatFloat(gShOcc, "", 0, 2)
		+ " R=" + formatFloat(gShR, "", 0, 2)
		+ " arrive=" + formatFloat(gShArrive, "", 0, 0) + "(seen " + formatFloat(gShSeen, "", 0, 0)
		+ " com " + formatFloat(gShComM, "", 0, 0) + " comSeen " + gShComSeen + ")"
		+ " floor=" + formatFloat(gArmyFloorRaw, "", 0, 0) + "->" + formatFloat(gArmyFloorRaw + RushFloorExtra() + gShFloorX, "", 0, 0)
		+ " full=" + formatFloat(ArmyTargetFull(), "", 0, 0)
		+ " tgt=" + formatFloat(ArmyTarget(), "", 0, 0) + " army=" + formatFloat(ArmyValue(), "", 0, 0)
		+ " hold=" + formatFloat(gShHold, "", 0, 2) + " phi=" + formatFloat(gShPhi, "", 0, 2)
		+ " comArmyW=" + formatFloat(SmallHardComArmyW(), "", 0, 2)
		+ " mix:" + mix
		+ " cand=" + gShCand + " tgtNet=" + formatFloat(gShTgtNet, "", 0, 0) + " ops=" + gShOps
		+ " raidFoe=" + gShRaidFoe + " mexKilled=" + gShMexKilled
		+ " comPrior=" + gShComPriced + "/" + gShRaidPriced
		+ " comJobs=" + jobs);
	gShComPriced = 0;
	gShRaidPriced = 0;
}

}  // namespace Market
