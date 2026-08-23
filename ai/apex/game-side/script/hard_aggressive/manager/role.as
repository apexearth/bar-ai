namespace Role {

// THE ROLE POLICY LAYER. One place answers "what does the eco/tech role
// change about this instance's behaviour" -- the consumers read these
// methods instead of each re-asking Factory::IsEcoLead() and inventing a
// response (which is how the role grew to ~25 leaf gates across seven
// files). Election and latch stay in Factory (mexhold.as); this layer owns
// the POLICY those results imply. Same shape as Persona, plus the few
// switch-valued answers a Persona is forbidden.
//
// Resolve() runs once per AiUpdate, BEFORE Brain::UpdateFacQueues, so the
// facqueue consumes the same plan the builder ladder does in that tick.

// -- the build-power controller ----------------------------------------------
//
// apexearth: "enough build power to use the metal and not overflow, but not
// so much build power that you far exceed your metal income. The code should
// find that balance. It is not the sort of thing you can hard-code for given
// the dynamics of game settings and handicaps." So: measure standing build
// power in metal/s of lathe, target income x a headroom fraction, buy on
// deficit, trim on excess. The ONLY policy numbers are the two fractions;
// the per-class drains below are unit PHYSICS (DRAIN=7 is the repo's
// measured pull of a ~90-workerTime T1 con; other classes scale by their
// workerTime -- switch to a GetBuildSpeed binding read when the next DLL
// rebuild lands). The loop closes through Resolve(): each tick the deficit
// shrinks by what was built, so production self-stops at balance; the
// existing nano in-flight bound caps pipeline overshoot.
const float DRAIN_CON_T1  = 7.f;    // armck/corck ~90 workerTime
const float DRAIN_CON_AIR = 8.f;    // armca ~100
const float DRAIN_CON_ADV = 14.f;   // armack ~180
const float DRAIN_NANO    = 15.f;   // armnanotc ~200
const float DRAIN_COMM    = 23.f;   // armcom ~300

float gBP       = 0.f;
float gBPTarget = 0.f;

float CountDrain(CCircuitDef@ d, float per)
{
	return (d is null) ? 0.f : float(d.count) * per;
}

float StandingBP()
{
	float bp = 0.f;
	bp += CountDrain(SideDef3("armck",     "corck",     "legck"),     DRAIN_CON_T1);
	bp += CountDrain(SideDef3("armcv",     "corcv",     "legcv"),     DRAIN_CON_T1);
	bp += CountDrain(SideDef3("armca",     "corca",     "legca"),     DRAIN_CON_AIR);
	bp += CountDrain(SideDef3("armack",    "corack",    "legack"),    DRAIN_CON_ADV);
	bp += CountDrain(SideDef3("armacv",    "coracv",    "legacv"),    DRAIN_CON_ADV);
	bp += CountDrain(SideDef3("armaca",    "coraca",    "legaca"),    DRAIN_CON_ADV);
	bp += CountDrain(SideDef3("armnanotc", "cornanotc", "legnanotc"), DRAIN_NANO);
	// The commander is deliberately NOT counted: it is the opening's given,
	// not a controller purchase, and its 23 m/s of lathe alone exceeds
	// income x headroom for the first minutes -- counting it froze all con
	// growth at frame 0 (measured seed-47: holder #7 eco, tech 9.8m).
	return bp;
}

// -- the role's OBJECTIVE: one current intent, visible in the log ------------
//
// apexearth, watching cons AFK-assist a lab beside a full bank and no T2:
// "This is why you kinda need a brain on this stuff." The Brain design's
// Directives faculty (docs/18-brain.md), implemented for the role: ONE
// current objective computed from observable state, that the ladder rules
// defer to -- instead of each leaf rule acting on its own local condition.
// Logged on every change so a watched game shows the intent directly.
enum Obj { OPENING = 0, GROW = 1, T2LAB = 2, MOHO = 3, FUSION = 4, AIRSCALE = 5 }
int gObjective = Obj::OPENING;
int gObjectiveLogged = -1;

string ObjName(int o)
{
	if (o == Obj::GROW)     return "GROW (mexes+energy toward the T2 bar)";
	if (o == Obj::T2LAB)    return "T2LAB (everything into the advanced plant)";
	if (o == Obj::MOHO)     return "MOHO (upgrade every extractor)";
	if (o == Obj::FUSION)   return "FUSION (reactor 1 then 2)";
	if (o == Obj::AIRSCALE) return "AIRSCALE (air cons + nanos, retire land)";
	return "OPENING";
}

void ComputeObjective()
{
	if (!Active() || !Factory::HaveAnyFactory()) {
		gObjective = Obj::OPENING;
		return;
	}
	if (!Factory::gHaveT2) {
		// T2 the moment energy permits and metal is not exceedingly low --
		// and a FULL BANK counts as affordability whatever the income
		// (apexearth: reclaim surplus cons to pay for the lab if need be).
		const bool energyOk = aiEconomyMgr.energy.income >= T2EnergyBar();
		gObjective = (energyOk || Builder::MetalSurplusIsReal())
				? Obj::T2LAB : Obj::GROW;
		return;
	}
	CCircuitDef@ mex = SideDef3("armmex", "cormex", "legmex");
	if ((mex !is null) && (mex.count > 0)) {
		gObjective = Obj::MOHO;
		return;
	}
	gObjective = (Builder::gFusions.length() < 2) ? Obj::FUSION : Obj::AIRSCALE;
}

int Objective()
{
	return gObjective;
}

void Resolve()
{
	Factory::UpdateEcoLead();
	gBP = StandingBP();
	gBPTarget = Factory::SteadyIncome()
			* ai.GetTunable("apex_bp_headroom", TUNE_BP_HEADROOM);
	ComputeObjective();
	if (gObjective != gObjectiveLogged) {
		gObjectiveLogged = gObjective;
		if (Active()) {
			AiLog(Factory::T() + "apex: role objective -> " + ObjName(gObjective)
				+ " (eInc=" + formatFloat(aiEconomyMgr.energy.income, "", 0, 0)
				+ " mInc=" + formatFloat(Factory::SteadyIncome(), "", 0, 0)
				+ " bank=" + formatFloat(aiEconomyMgr.metal.current, "", 0, 0) + ")");
		}
	}
}

// Build-power deficit expressed in nano turrets. 0 when balanced or excess;
// role-only for now (the controller can serve every instance later).
int NanoWant()
{
	if (!Active())
		return 0;
	const float deficit = gBPTarget - gBP;
	return (deficit > 0.f) ? int(deficit / DRAIN_NANO) + 1 : 0;
}

// Is standing BP past the trim bar? (Consumed by the land-con retirement
// sweep once the post-fusion-2 stage lands.)
bool BPExcess()
{
	return gBP > gBPTarget
			* ai.GetTunable("apex_bp_trim_slack", TUNE_BP_TRIM_SLACK);
}

bool Active()
{
	return Factory::EcoLeadActive();
}

// Budget hook, beside Persona::ShareMult in budget.as. 1.0 for now: the
// role still expresses itself through the leaf methods below; moving its
// intent into budget shares is the follow-on step once behaviour parity of
// this refactor is confirmed.
float ShareMult(int cat)
{
	return 1.f;
}

// Army share a factory line keeps under the role. 0 = that line fields no
// army (mix, core floors and the spam stream all read THIS, so a new army
// channel added to the facqueue inherits the role by construction).
float ArmyMult(CCircuitUnit@ fac)
{
	if (!Factory::IsEcoLead())
		return 1.f;
	if (Factory::IsAirFactory(fac.circuitDef))
		return ai.GetTunable("apex_role_tech_air", TUNE_ROLE_TECH_AIR);
	const int a = Factory::userData[fac.circuitDef.id].attr;
	if ((a & Factory::Attr::T3) != 0)
		return ai.GetTunable("apex_role_tech_t3", TUNE_ROLE_TECH_T3);
	if ((a & Factory::Attr::T2) != 0)
		return ai.GetTunable("apex_role_tech_t2", TUNE_ROLE_TECH_T2);
	return ai.GetTunable("apex_role_tech_t1", TUNE_ROLE_TECH_T1);
}

// May this instance build static defence? Sensors are exempt at the call
// sites (eyes are not porc).
bool DefenceAllowed()
{
	return !(Factory::IsEcoLead()
		&& (ai.GetTunable("apex_role_tech_def", TUNE_ROLE_TECH_DEF) <= 0.f));
}

// The role's bound on a line's con want: cons may grow only into the BP
// DEFICIT (apexearth: bots are the most cost-efficient through the T2
// transition -- no flat suppression -- but total BP tracks income). The old
// pre-T2 income clamp (apex_role_con_per) is superseded by the controller.
int ConCap(CCircuitDef@ con, int cap)
{
	if (!Active() || (con is null))
		return cap;
	// PRE-T2 cons are income PRODUCERS (mex and energy builders), so the
	// income curve alone said 23 of them at +100 -- apexearth, watching:
	// "far too many. We only need ~6 max... I don't want you to set some
	// '6 max!' limit. I want you to be intelligent." The intelligent bound
	// is DEMAND: a con is worth building while queued work exists for it
	// (the same signal AdvConsWanted already clamps on) plus whatever the
	// BP deficit says income has outrun. His ~6 emerges from the demand at
	// a normal base; a map with more open jobs earns more hands.
	if (!Factory::gHaveT2) {
		const float per = ai.GetTunable("apex_con_tasks_each",
				TUNE_CON_TASKS_EACH);
		int demand = (per > 0.f)
				? int(float(aiBuilderMgr.GetBuildTaskCount()) / per) + 1
				: cap;
		const float deficit = gBPTarget - gBP;
		if (deficit > 0.f)
			demand += int(deficit / DRAIN_CON_T1) + 1;
		return (cap > demand) ? demand : cap;
	}
	const float deficit = gBPTarget - gBP;
	const int grow = (deficit > 0.f) ? int(deficit / DRAIN_CON_T1) + 1 : 0;
	const int allow = int(con.count) + grow;
	return (cap > allow) ? allow : cap;
}

// The role's own T2 energy bar (the lead bar held it at T1 to minute 15).
float T2EnergyBar()
{
	return ai.GetTunable("apex_role_t2_energy", TUNE_ROLE_T2_ENERGY);
}

// The steady-income bar at which fusion is chosen outright. The role's is a
// FRACTION of the general bar (scales with any retune of it): the reactor is
// the eco snowball's pivot, and on the general bar the role's first fusion
// landed 11m against the 2-by-10:00 rule at +100.
float FusionBar()
{
	const float bar = ai.GetTunable("apex_fusion_prefer_income",
			TUNE_FUSION_PREFER_INCOME);
	if (!Active())
		return bar;
	return bar * ai.GetTunable("apex_role_fus_frac", TUNE_ROLE_FUS_FRAC);
}

// MEXUPS BEFORE THE REACTOR (apexearth: "I saw the T2 con start a fusion
// prior to doing all the mexup"). A moho pays back in about a minute, the
// fusion in three -- so the role's fusion waits until no un-upgraded
// extractor remains, or a second adv con exists to run the moho lane in
// parallel with the reactor.
bool FusionAllowed()
{
	if (!Active())
		return true;
	if (Builder::AdvConCount() >= 2)
		return true;
	CCircuitDef@ mex = SideDef3("armmex", "cormex", "legmex");
	return (mex is null) || (mex.count <= 0);
}

// Does the lead deliver paid-for T2 cons? Off at a real resource bonus.
bool GiftsCons()
{
	return Factory::OwnHandicap()
			< ai.GetTunable("apex_role_gift_off_mult", TUNE_ROLE_GIFT_OFF_MULT);
}

}  // namespace Role
