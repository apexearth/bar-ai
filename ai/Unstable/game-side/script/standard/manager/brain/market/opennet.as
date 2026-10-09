namespace Market {

// THE OPENING ORDER, one recorded draw per game (his 2026-10-08: learned, not
// ruled -- with a high bonus the commander's income carries factory-first, at
// +0 the factory must not come first). Decided at the commander's first
// election; its steps lead his elections until the plant is ordered, then the
// draw has him. LAB plant first; MEXn n extractors then the plant; MEX2E two
// extractors, one generator, then the plant.
// Rule: LAB when the bank plus his own income (x the bonus) over the lab's and
// its first constructor's build times pays for both, metal and energy; else MEX2.
const string NNOP_OPEN = "comM,comE,bankM,bankE,labM,labE,labS,conM,conE,conS,carryM,carryE,"
	+ "mexOffers,mexWalkS,mexGain,plantWalkS,energyOffers";
const int OP_LAB = 0, OP_MEX1 = 1, OP_MEX2 = 2, OP_MEX3 = 3, OP_MEX2E = 4, OP_N = 5;
const array<string> OP_NAMES = {"LAB", "MEX1", "MEX2", "MEX3", "MEX2E"};

int gOpenPlan = -1;
int gOpenStep = 0;
int gOpenSkips = 0;
int gOpenAt = -1;
bool gOpenDone = false;

int OpenMexSteps(int plan)
{
	if (plan == OP_MEX1)
		return 1;
	if ((plan == OP_MEX2) || (plan == OP_MEX2E))
		return 2;
	return (plan == OP_MEX3) ? 3 : 0;
}

int OpenSteps(int plan)
{
	return OpenMexSteps(plan) + ((plan == OP_MEX2E) ? 1 : 0) + 1;
}

int OpenStepKind(int plan, int step)
{
	const int nm = OpenMexSteps(plan);
	if (step < nm)
		return WK_MEX;
	if ((plan == OP_MEX2E) && (step == nm))
		return WK_ENERGY;
	return WK_PLANT;
}

string OpenName(int plan)
{
	return ((plan >= 0) && (plan < OP_N)) ? OP_NAMES[plan] : "-";
}

void OpenEnd(const string& in why)
{
	if (gOpenDone)
		return;
	gOpenDone = true;
	AiLog("apex: open-done t=" + ai.teamId + " plan=" + OpenName(gOpenPlan)
		+ " step=" + gOpenStep + "/" + ((gOpenPlan >= 0) ? OpenSteps(gOpenPlan) : 0)
		+ " skips=" + gOpenSkips + " decidedF=" + gOpenAt + " why=" + why);
}

void OpenDecide(CCircuitUnit@ unit, array<Want@>@ ranked)
{
	Want@ plant = null;
	Want@ mex = null;
	int mexN = 0, eN = 0;
	for (uint ri = 0; ri < ranked.length(); ++ri) {
		Want@ c = ranked[ri];
		if ((c.kind == WK_PLANT) && (plant is null) && (c.def !is null))
			@plant = c;
		if (c.kind == WK_MEX) {
			++mexN;
			if (mex is null)
				@mex = c;
		}
		if (c.kind == WK_ENERGY)
			++eN;
	}
	if (plant is null)
		return;   // no plant on offer yet: asked again at his next election
	const int cd = int(unit.circuitDef.id);
	const int ld = int(plant.def.id);
	int con = -1;
	const array<int>@ made = Catalog::BuildsOf(ld);
	for (uint i = 0; i < made.length(); ++i) {
		const int d = made[i];
		if (!Catalog::gBuilder[d] || !Catalog::gMobile[d])
			continue;
		if ((con < 0) || (Catalog::gCostM[d] < Catalog::gCostM[con]))
			con = d;
	}
	NnBonusRefresh();
	const float k = (gNnOurBonus > -1.f) ? (1.f + gNnOurBonus) : 0.f;
	const float comBp = (Catalog::gBuildPower[cd] > 1.f) ? Catalog::gBuildPower[cd] : 1.f;
	const float labBp = (Catalog::gBuildPower[ld] > 1.f) ? Catalog::gBuildPower[ld] : 1.f;
	const float labS = Catalog::gBuildTime[ld] / comBp;
	const float conS = (con >= 0) ? (Catalog::gBuildTime[con] / labBp) : 0.f;
	const float conM = (con >= 0) ? Catalog::gCostM[con] : 0.f;
	const float conE = (con >= 0) ? Catalog::gCostE[con] : 0.f;
	const float comM = k * Catalog::gMakeM[cd];
	const float comE = k * Catalog::gMakeE[cd];
	const float needM = Catalog::gCostM[ld] + conM;
	const float needE = Catalog::gCostE[ld] + conE;
	const float carryM = (Eco::MCur() + comM * (labS + conS)) / ((needM > 1.f) ? needM : 1.f);
	const float carryE = (Eco::ECur() + comE * (labS + conS)) / ((needE > 1.f) ? needE : 1.f);
	const int rule = ((carryM >= 1.f) && (carryE >= 1.f)) ? OP_LAB : OP_MEX2;
	const AIFloat3 up = unit.GetPos(ai.frame);
	const float spd = (Catalog::gSpeed[cd] > 1.f) ? Catalog::gSpeed[cd] : 1.f;
	array<float> st;
	NnState(null, st);
	array<float> f;
	f.insertLast(comM);
	f.insertLast(comE);
	f.insertLast(Eco::MCur());
	f.insertLast(Eco::ECur());
	f.insertLast(Catalog::gCostM[ld]);
	f.insertLast(Catalog::gCostE[ld]);
	f.insertLast(labS);
	f.insertLast(conM);
	f.insertLast(conE);
	f.insertLast(conS);
	f.insertLast(carryM);
	f.insertLast(carryE);
	f.insertLast(float(mexN));
	f.insertLast((mex !is null) ? (up.distance2D(mex.pos) / spd) : -1.f);
	f.insertLast((mex !is null) ? mex.gain : 0.f);
	f.insertLast(up.distance2D(plant.pos) / spd);
	f.insertLast(float(eN));
	array<float> w(OP_N, NE2_EPS);
	w[rule] = 1.f;
	const float trust = NnHeadScore(NNOP_ON, NNOP_STATE, NNOP_OPEN, NNOP_S, NNOP_O, NNOP_H, NNOP_XM, NNOP_XS,
		NNOP_W1, NNOP_B1, NNOP_W2, NNOP_B2, NNOP_WO, NNOP_BO, NNOP_TRUST, st, f, w);
	// One decision a game: an explorer draws it evenly while the net has no
	// trust, half net / half even once it has (the plan net's discovery).
	NnExploreRoll();
	const float flat = gNnExplore ? ((trust > 0.f) ? 0.5f : 1.f) : 0.f;
	array<float> p(OP_N);
	gOpenPlan = EcoDraw(rule, trust, w, p, flat);
	gOpenAt = ai.frame;
	AiLog("apex: nnopen-schema v1 state=" + NN_STATE + " open=" + NNOP_OPEN
		+ " opt=name,w,p opts=LAB,MEX1,MEX2,MEX3,MEX2E");
	AiLog(EcoLine("nnopen", OP_NAMES[rule], flat > 0.f, trust, st, f, OP_NAMES, w, p, gOpenPlan, "first"));
	AiLog("apex: open-plan t=" + ai.teamId + " plan=" + OpenName(gOpenPlan) + " rule=" + OP_NAMES[rule]
		+ " p=" + NnF(p[gOpenPlan], 3) + " k=" + NnF(k, 2)
		+ " carryM=" + NnF(carryM, 2) + " carryE=" + NnF(carryE, 2)
		+ " lab=" + plant.def.GetName() + " con=" + ((con >= 0) ? Catalog::Def(con).GetName() : "-")
		+ " trust=" + NnF(trust, 2) + " flat=" + NnF(flat, 2));
}

// Moves every want of the plan's current step kind to the front of `ranked`,
// in value order, so a refused one (a mex past his leash) falls to the next of
// its kind; true when it did. A step with nothing on offer is passed over,
// except the plant: the plan waits for one.
bool OpenHoist(CCircuitUnit@ unit, array<Want@>@ ranked)
{
	if (gOpenDone || !unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask))
		return false;
	if ((Factory::gFacUnits.length() > 0) || AnyPlantInFlight()) {
		OpenEnd("plant");
		return false;
	}
	if (gOpenPlan < 0) {
		OpenDecide(unit, ranked);
		if (gOpenPlan < 0)
			return false;
	}
	const int n = OpenSteps(gOpenPlan);
	while (gOpenStep < n) {
		const int sk = OpenStepKind(gOpenPlan, gOpenStep);
		uint lead = 0;
		for (uint ri = 0; ri < ranked.length(); ++ri) {
			if (ranked[ri].kind != sk)
				continue;
			if (ri > lead) {
				Want@ ow = ranked[ri];
				ranked.removeAt(ri);
				ranked.insertAt(lead, ow);
			}
			++lead;
		}
		if (lead > 0)
			return true;
		if (sk == WK_PLANT)
			return false;
		++gOpenSkips;
		AiLog("apex: open-step t=" + ai.teamId + " plan=" + OpenName(gOpenPlan) + " step=" + gOpenStep
			+ " kind=" + KindName(sk) + " why=absent");
		++gOpenStep;
	}
	return false;
}

// An executed want: the commander's advances the plan when it is the current
// step's kind; any plant ordered ends it.
void OpenNoteExec(bool isComm, int kind)
{
	if (gOpenDone || (gOpenPlan < 0))
		return;
	if (kind == WK_PLANT) {
		OpenEnd("ordered");
		return;
	}
	if (isComm && (gOpenStep < OpenSteps(gOpenPlan)) && (OpenStepKind(gOpenPlan, gOpenStep) == kind)) {
		++gOpenStep;
		AiLog("apex: open-step t=" + ai.teamId + " plan=" + OpenName(gOpenPlan) + " step=" + gOpenStep
			+ " kind=" + KindName(kind) + " why=exec");
	}
}

}  // namespace Market
