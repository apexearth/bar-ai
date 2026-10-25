namespace Market {

// THE RUSH AS A PLAY, ON READINESS (apex_strike_phases; his 10-24: "maybe we wait on going to T2 by rushing T1 more
// as a strategy... the mindset should be 'big early attack, high aggression values on army' and while that attack is
// happening we can transition to T2 and stop production"; "How do you think we can do this where it is not based on
// time but instead based on readiness?"). Under the RUSH plan the team runs, decided by the plan-price leader and
// read by every seat:
//   OPEN    defence as usual (LLTs for the raiders), no tier-up (next-tier lab, gantry), no air plant, the labs never
//           short of army to make; until every seat's labs can spend its army share of income (FacMetalRate), or
//           that capacity stops growing over one ETA
//   PRODUCE no new factory of any kind -- army from what we have (his 10-24: "stop making factories and just build
//           army from what you have... this is a valid T2 activity as well"); no ground defence; the army gathers,
//           cautious while they outweigh us
//   STRIKE  when waiting no longer pays: the strike's value per second now is at least what it would be a minute
//           later, with both armies grown at their income (PpStrike); or their best unit outclasses ours; or four ETAs
//           have passed. Tier-ups and factories come back and the army share falls back so the metal goes to tech
//   AFTER   the strike army below 40% of its launch, or it stopped trading (less than a tenth of its launch destroyed
//           in the last ETA, once it has had one ETA to arrive); back to OPEN after two ETAs
// Every timing is the army's ETA to their nearest box (his 10-24: "take into account the army speed and ETA to enemy
// please, minute hardcodings are generally bad"): the walk at the cost-weighted speed of our ground army.
// Same seeds, 2v2 vs v0.4.02, 35 min: RUSH + attack_mod 0.3 throughout traded 1.53 (ahead 7/8) against 0.71.
const int SK_NONE = 0, SK_BUILD = 1, SK_STRIKE = 2, SK_AFTER = 3, SK_OPEN = 4;
const int BOARD_SK_PHASE = 8500, BOARD_SK_AT = 8501, BOARD_SK_ARMY = 8502, BOARD_SK_READY = 8700;
const array<string> SK_NAMES = {"NONE", "PRODUCE", "STRIKE", "AFTER", "OPEN"};
const int BOARD_SK_KILL = 8600, BOARD_SK_CAP = 8801, BOARD_SK_CAPAT = 8802, BOARD_SK_KILL0 = 8803, BOARD_SK_KILL0AT = 8804;
const int BOARD_SK_INC = 8805, BOARD_SK_INCAT = 8806;
float gSkKill = 0.f;   // metal this seat destroyed, published for the leader's stall test

void StrikeNoteKill(float m)
{
	gSkKill += m;
}

// the army's walk to their nearest box: the cost-weighted speed of our ground combat units, 1.3x the straight line
float gSkEta = -1.f;
int gSkEtaAt = -1;
float StrikeEta()
{
	if ((gSkEtaAt >= 0) && (ai.frame - gSkEtaAt < 10 * SECOND))
		return gSkEta;
	gSkEtaAt = ai.frame;
	float m = 0.f, ms = 0.f;
	const array<int>@ own = OwnedDefs();
	for (uint i = 0; i < own.length(); ++i) {
		const int d = own[i];
		if (!Catalog::ValidId(d) || !Catalog::gMobile[d] || Catalog::gFlyer[d] || Catalog::gBuilder[d]
			|| (Catalog::gSurfDps[d] <= 0.f) || (uint(d) >= gOwnCount.length()) || (Catalog::gSpeed[d] <= 1.f))
			continue;
		const float c = float(gOwnCount[d]) * Catalog::gCostM[d];
		m += c;
		ms += c * Catalog::gSpeed[d];
	}
	const float spd = (m > 0.f) ? ms / m : 60.f;
	const AIFloat3 box = ai.GetNearestEnemyBox(Builder::gHomePos);
	gSkEta = OnMap(box) ? (1.3f * Builder::gHomePos.distance2D(box) / spd) : 90.f;
	return gSkEta;
}
int gSkNextAt = 0;
int gSkLogPhase = -1;

// HIS TIMED VERSION (apex_strike_schedule, a test; his 10-24: "threat mod of current for 0-5m, then threat mod of 2
// (very high) for 5-10m, all while making only army and not doing T2 at all, and then threat mod 0 to do a full on
// attack, and so then from minute 10-15 go T2 while that attack happens"). The engine divides by the modifier
// (an attack task's margin is 0.8 / mod), so "0" is apex_sched_all (0.05).
bool ScheduleOn()
{
	return ai.GetTunable("apex_strike_schedule", TUNE_STRIKE_SCHEDULE) > 0.f;
}

bool StrikeOn()
{
	return ScheduleOn() || (ai.GetTunable("apex_strike_phases", TUNE_STRIKE_PHASES) > 0.f);
}

float SchedMod(float minute)
{
	if (minute < ai.GetTunable("apex_sched_hold_min", TUNE_SCHED_HOLD_MIN))
		return 1.f;
	if (minute < ai.GetTunable("apex_sched_go_min", TUNE_SCHED_GO_MIN))
		return ai.GetTunable("apex_sched_hold_mod", TUNE_SCHED_HOLD_MOD);
	return ai.GetTunable("apex_sched_all", TUNE_SCHED_ALL);
}

int StrikePhase()
{
	if (!StrikeOn() || (gPlan != NG_RUSH))
		return SK_NONE;
	if (ScheduleOn())
		return (float(ai.frame) / 1800.f < ai.GetTunable("apex_sched_go_min", TUNE_SCHED_GO_MIN)) ? SK_BUILD : SK_STRIKE;
	return int(ai.GetTeamBoard(BOARD_SK_PHASE, float(SK_OPEN)));
}

bool StrikeBuilding()
{
	const int ph = StrikePhase();
	return (ph == SK_BUILD) || (ph == SK_OPEN);
}

// what a tier-up's demand is multiplied by (ProposeTech): none before the strike
float StrikeTechMul()
{
	return StrikeBuilding() ? 0.f : 1.f;
}

// whether a plant may be proposed: none in PRODUCE; in OPEN, same tier only and no air plant
bool StrikeHoldsPlant(int d)
{
	const int ph = StrikePhase();
	if (ph == SK_BUILD)
		return true;
	if (ph != SK_OPEN)
		return false;
	return (PlantClass(d) == PC_AIR) || (PlantTier(d) > TopOwnPlantTier());
}

// THE MASS BUYS NO GROUND DEFENCE (his 10-24: "you can really put it all into army and 0 into def, just take FROM the
// def budget and go entirely on army"; "minutes 0-5 still have defense. llts just to deal with those pesky raiders").
// Watched at +50: 8-20% of our seats' metal went to turrets before minute 10 and army stayed at 26-27%. The budget
// cannot zero a row (BudgetMult is bounded 0.35-2), so the proposals stand down at their source in the mass; AA and
// the commander's own guns stay.
int gSkDefHeld = 0;
bool StrikeHoldsDefence()
{
	if (StrikePhase() != SK_BUILD)
		return false;
	if (ScheduleOn() && (float(ai.frame) / 1800.f < ai.GetTunable("apex_sched_hold_min", TUNE_SCHED_HOLD_MIN)))
		return false;
	++gSkDefHeld;
	return true;
}

// whether RUSH still raises the army share (PlanShareMult): not once the strike is out
bool StrikeArmyRaise()
{
	const int ph = StrikePhase();
	return (ph == SK_NONE) || StrikeBuilding();
}

// THE THREAT MODIFIER FOLLOWS THE BALANCE (apex_dyn_mod; his 10-24: "think about how we can better have a dynamic
// threat mod for these sorts of buildup and attack methods"; "we have 3x their army or more but i bet our threat mod is
// still kinda reserved, we might as well just make it super low and overrun them"). A fight's odds go with the square
// of the sides: outweighing what we would hit (their army and the turrets over the economy we would reach) by k, the
// enemy is counted at 1/k^2 (3x -> 0.11, floor apex_strike_mod); outweighed in the mass, the army waits -- 2x their
// share of ours, 1 to 3; otherwise the config's 1.
float DynModOn()
{
	return ai.GetTunable("apex_dyn_mod", TUNE_DYN_MOD);
}
float DynMod(int ph, float ours)
{
	// the leader's sighting (PlanPriceTick), stale after a minute; unseen is not none: never under 30% of a mirror of
	// ours at their estimated income
	if ((ours <= 1.f) || (float(ai.frame) - ai.GetTeamBoard(PP_THEIRS_AT, -1e9f) > float(60 * SECOND)))
		return 1.f;
	float theirs = ai.GetTeamBoard(PP_THEIRS, 0.f);
	const float mirror = 0.3f * ours * ai.GetTeamBoard(PP_IRATIO, 1.f);
	if (theirs < mirror)
		theirs = mirror;
	const float lo = ai.GetTunable("apex_strike_mod", TUNE_STRIKE_MOD);
	if (theirs < ours) {
		if (ph == SK_BUILD)
			return 1.f;   // the mass waits for the strike whatever the odds
		const float r = theirs / ours;
		const float m = r * r;
		return (m < lo) ? lo : m;
	}
	if (ph == SK_BUILD) {
		const float m = 2.f * theirs / ours;
		return (m < 1.f) ? 1.f : ((m > 3.f) ? 3.f : m);
	}
	return 1.f;
}

void StrikeTick()
{
	if (ai.frame < gSkNextAt)
		return;
	gSkNextAt = ai.frame + 5 * SECOND;
	const float army = Military::TeamArmyCost();
	if (!StrikeOn() || (gPlan != NG_RUSH)) {
		if (StrikeOn() && (int(ai.GetTeamBoard(BOARD_SK_PHASE, float(SK_NONE))) != SK_NONE))
			ai.SetTeamBoard(BOARD_SK_PHASE, float(SK_NONE));
		// outside the play the balance still sets it (DynMod), or the config does (AttackModTick)
		if (DynModOn() > 0.f)
			Military::AttackModSet(DynMod(SK_NONE, army));
		return;
	}
	if (ScheduleOn()) {
		const int sp = StrikePhase();
		Military::AttackModSet(SchedMod(float(ai.frame) / 1800.f));
		if (sp != gSkLogPhase) {
			gSkLogPhase = sp;
			AiLog(Factory::T() + "apex: strike-phase t=" + ai.teamId + " " + SK_NAMES[uint(sp)] + " (schedule) army="
				+ int(army) + " defHeld=" + gSkDefHeld);
		}
		return;
	}
	// this seat's readiness: its labs can spend its army share of income
	float cap = 0.f;
	for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
		CCircuitUnit@ f = Factory::gFacUnits[fi];
		if ((f !is null) && (f.circuitDef !is null) && (PlantClass(int(f.circuitDef.id)) == PC_LAND))
			cap += FacMetalRate(f);
	}
	const float needRate = Brain::TargetShare(Brain::ARMY) * Eco::MInc();
	ai.SetTeamBoard(BOARD_SK_READY + ai.teamId, ((cap > 0.f) && (cap >= 0.8f * needRate)) ? 1.f : 0.f);
	int ph = int(ai.GetTeamBoard(BOARD_SK_PHASE, float(SK_NONE)));
	int lead = ai.teamId;
	for (int t = 0; t < 64; ++t) {
		if (PpFresh(t)) {
			lead = t;
			break;
		}
	}
	ai.SetTeamBoard(BOARD_SK_KILL + ai.teamId, gSkKill);
	if (lead == ai.teamId) {
		const float since = float(ai.frame) - ai.GetTeamBoard(BOARD_SK_AT, float(ai.frame));
		const float eta = StrikeEta() * float(SECOND);
		float killed = 0.f;
		for (int t = 0; t < 64; ++t) {
			if (PpFresh(t))
				killed += ai.GetTeamBoard(BOARD_SK_KILL + t, 0.f);
		}
		if ((ph == SK_NONE) || ((ph == SK_AFTER) && (since > 2.f * eta))) {
			ph = SK_OPEN;
			ai.SetTeamBoard(BOARD_SK_AT, float(ai.frame));
		} else if (ph == SK_OPEN) {
			bool all = true;
			int seats = 0;
			for (int t = 0; t < 64; ++t) {
				if (!PpFresh(t))
					continue;
				++seats;
				all = all && (ai.GetTeamBoard(BOARD_SK_READY + t, 0.f) > 0.f);
			}
			// capacity that has stopped growing over one ETA is as ready as this economy gets
			const float capAt = ai.GetTeamBoard(BOARD_SK_CAPAT, -1.f);
			bool flat = false;
			if ((capAt < 0.f) || (cap > 1.1f * ai.GetTeamBoard(BOARD_SK_CAP, 0.f))) {
				ai.SetTeamBoard(BOARD_SK_CAP, cap);
				ai.SetTeamBoard(BOARD_SK_CAPAT, float(ai.frame));
			} else {
				flat = (float(ai.frame) - capAt) > eta;
			}
			// expansion first: the open lasts while the team's income still grows a quarter over one ETA
			float Inow = 0.f;
			for (int t = 0; t < 64; ++t) {
				if (PpFresh(t))
					Inow += ai.GetTeamBoard(PP_INC + t, 0.f);
			}
			const float incAt = ai.GetTeamBoard(BOARD_SK_INCAT, -1.f);
			bool growing = true;
			if ((incAt < 0.f) || (float(ai.frame) - incAt > eta)) {
				const float inc0 = ai.GetTeamBoard(BOARD_SK_INC, -1.f);
				growing = (incAt < 0.f) || (inc0 <= 0.f) || (Inow > 1.25f * inc0);
				ai.SetTeamBoard(BOARD_SK_INC, Inow);
				ai.SetTeamBoard(BOARD_SK_INCAT, float(ai.frame));
				ai.SetTeamBoard(BOARD_SK_INC + 100, growing ? 1.f : 0.f);
			} else {
				growing = ai.GetTeamBoard(BOARD_SK_INC + 100, 1.f) > 0.f;
			}
			if ((((seats > 0) && all) && !growing) || flat) {
				ph = SK_BUILD;
				ai.SetTeamBoard(BOARD_SK_AT, float(ai.frame));
				Say("OPEN -> PRODUCE (" + ((all && (seats > 0)) ? "labs ready" : "production stopped growing") + ", cap "
					+ int(cap) + "/" + int(needRate) + " m/s): no new factories, army from what we have");
				AiLog(Factory::T() + "apex: strike-produce t=" + ai.teamId + " why=" + ((all && (seats > 0)) ? "labs" : "flat")
					+ " cap=" + int(cap) + "/" + int(needRate) + " army=" + int(army) + " open=" + int(since / 30.f) + "s");
			}
		} else if (ph == SK_BUILD) {
			float I = 0.f;
			for (int t = 0; t < 64; ++t) {
				if (PpFresh(t))
					I += ai.GetTeamBoard(PP_INC + t, 0.f);
			}
			const float a = Brain::TargetShare(Brain::ARMY);
			const float If = (gPpIf > 0.f) ? gPpIf : I;
			const float q = Military::TradeRatio();
			const AIFloat3 box = ai.GetNearestEnemyBox(Builder::gHomePos);
			const float arr = OnMap(box) ? (Builder::gHomePos.distance2D(box) / 60.f) : 90.f;
			// unseen is not none: their army never under 30% of a mirror of ours at their income (as DynMod)
			float A = gPpArmy;
			const float mirror = 0.3f * army * ((I > 1.f) ? If / I : 1.f);
			if (A < mirror)
				A = mirror;
			const float netNow = PpStrike(army, A, gPpDef, gPpEcoFree, gPpEcoCov, q, gAssetsM, false);
			const float net60 = PpStrike(army + I * a * 60.f, A + If * a * 60.f, gPpDef, gPpEcoFree, gPpEcoCov,
					q, gAssetsM, false);
			const float rateNow = netNow / arr;
			const float rate60 = net60 / (60.f + arr);
			const float theirs = ai.GetEnemyMaxMobileCostM();
			const float ours = OwnedBestMobileCostM();
			string why = "";
			if ((netNow > 0.f) && (rateNow >= rate60))
				why = "peaked";
			else if ((ours > 0.f) && (theirs > 1.5f * ours))
				why = "outclassed";
			else if (since > 4.f * eta)
				why = "4eta";
			if (why != "") {
				ph = SK_STRIKE;
				ai.SetTeamBoard(BOARD_SK_AT, float(ai.frame));
				ai.SetTeamBoard(BOARD_SK_ARMY, army);
				ai.SetTeamBoard(BOARD_SK_KILL0, killed);
				ai.SetTeamBoard(BOARD_SK_KILL0AT, float(ai.frame));
				Say("STRIKE (" + why + "): army " + int(army) + " vs theirs " + int(gPpArmy) + " + turrets " + int(gPpDef)
					+ ", ETA " + int(eta / 30.f) + "s; tier-up and factories open");
				AiLog(Factory::T() + "apex: strike-go t=" + ai.teamId + " why=" + why + " army=" + int(army)
					+ " net=" + int(netNow) + " net60=" + int(net60) + " rate=" + NnF(rateNow, 1) + "/" + NnF(rate60, 1)
					+ " foeArmy=" + int(gPpArmy) + " foeDef=" + int(gPpDef) + " produce=" + int(since / 30.f) + "s eta="
					+ int(eta / 30.f) + "s");
			}
		} else if (ph == SK_STRIKE) {
			const float launch = ai.GetTeamBoard(BOARD_SK_ARMY, army);
			// a stall: one ETA to arrive, then less than a tenth of the launch destroyed over the last ETA
			bool stalled = false;
			if (float(ai.frame) - ai.GetTeamBoard(BOARD_SK_KILL0AT, 0.f) > eta) {
				if (since > eta)
					stalled = (killed - ai.GetTeamBoard(BOARD_SK_KILL0, 0.f)) < 0.1f * launch;
				ai.SetTeamBoard(BOARD_SK_KILL0, killed);
				ai.SetTeamBoard(BOARD_SK_KILL0AT, float(ai.frame));
			}
			if (stalled || (army < 0.4f * launch)) {
				ph = SK_AFTER;
				ai.SetTeamBoard(BOARD_SK_AT, float(ai.frame));
				Say("strike over (" + (stalled ? "stalled" : "spent") + "): " + int(army) + " of " + int(launch)
					+ " left, killed " + int(killed));
				AiLog(Factory::T() + "apex: strike-end t=" + ai.teamId + " why=" + (stalled ? "stalled" : "spent") + " army="
					+ int(army) + "/" + int(launch) + " killed=" + int(killed) + " after=" + int(since / 30.f) + "s eta="
					+ int(eta / 30.f) + "s");
			}
		}
		ai.SetTeamBoard(BOARD_SK_PHASE, float(ph));
	}
	ph = StrikePhase();
	float mod = 1.f;
	if (DynModOn() > 0.f)
		mod = DynMod(ph, army);
	else if (ph == SK_STRIKE)
		mod = ai.GetTunable("apex_strike_mod", TUNE_STRIKE_MOD);
	else if (ph == SK_BUILD)
		mod = ai.GetTunable("apex_sched_hold_mod", TUNE_SCHED_HOLD_MOD);
	Military::AttackModSet(mod);
	if (ph != gSkLogPhase) {
		gSkLogPhase = ph;
		AiLog(Factory::T() + "apex: strike-phase t=" + ai.teamId + " " + SK_NAMES[uint(ph)] + " army=" + int(army)
			+ " mod=" + NnF(mod, 2) + " defHeld=" + gSkDefHeld);
	}
}

}  // namespace Market
