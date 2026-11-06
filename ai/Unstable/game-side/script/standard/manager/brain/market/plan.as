// THE SEAT PLAN (his 11-05; todo/seat-plan.md): decide what the SEAT does with all it has, top down, and let the
// builders be its hands. "These are the resources I have available. Of all the things that I could do, what is it I
// want to be doing right now? ... only upgrade this one metal extractor."
//
// Every 5 s: the jobs are every frame in progress, priced on what it still needs (sunk metal is gone, so a half-built
// frame pays back on half its bill and outranks the same building fresh), and the growth ladder's pool rungs. Economy
// jobs carry catalog gains in metal/s, never market gains. Ranked by the ladder's own key -- seconds of the binding
// feed per metal/s added, over survival -- and admitted in order while the metal feed, the energy feed and the build
// power last. Kinds outside the economy keep their place by the target's spend shares.
//
// apex_seat_plan 0: shadow -- the plan is computed and logged beside what the builders actually chose.

namespace Market {

const int PJ_FRAME = 0, PJ_RUNG = 1;
array<int> gPjKind;        // frame or rung
array<int> gPjDef;
array<AIFloat3> gPjPos;    // frames: where; rungs: unset
array<float> gPjRemM;      // metal still to pay
array<float> gPjRemW;      // build work still to do (engine buildtime units)
array<float> gPjGain;      // metal/s it adds once standing (economy), 0 for other kinds
array<float> gPjKey;       // seconds per metal/s; lower first
array<float> gPjBP;        // build power admitted to it
array<float> gPjHave;      // build power on it now: its crew, and each hand dispatched since the plan
array<int> gPjN;           // rungs: copies admitted
array<IUnitTask@> gPjTask; // frames: the task (null for a frame whose request died, until a hand is sent)
array<int> gPjUnit;        // frames: the frame's unit id (-1 for a rung)
int gPlanAt = -999999;
int gPlanAddUnit = -1;   // the frame unit the next PlanAdd records
// The window a plan is for: a walk and a build of the work at hand, and twelve re-plans of 5 s.
const float PLAN_WINDOW_S = 60.f;
int gPlanAdmitted = 0;
float gPlanFeedM = 0.f, gPlanBP = 0.f, gPlanBPUsed = 0.f, gPlanFeedUsed = 0.f;

bool SeatPlanOn() { return ai.GetTunable("apex_seat_plan", TUNE_SEAT_PLAN) > 0.f; }

// What a building adds, in metal/s, from the catalog and the spot it stands on (the ladder's DPowerOf, without a
// market want): an extractor at a held spot adds its extraction over what stands there.
float PlanGainAt(int d, const AIFloat3& in at)
{
	if (Catalog::gExtractsM[d] > 0.f) {
		int best = -1;
		float bd = 160.f;
		for (uint i = 0; i < gLPos.length(); ++i) {
			const float dd = gLPos[i].distance2D(at);
			if (dd < bd) {
				bd = dd;
				best = int(i);
			}
		}
		if (best >= 0) {
			const float up = Catalog::gExtractsM[d] - gLExtract[best];
			return (up > 0.f) ? gLIncome[best] * IncomeMult() * up : 0.f;
		}
		return SpotM();
	}
	if (Catalog::gConvCapacity[d] > 0.f) {
		float spill = (gEExcessEma > gESurplusEma) ? gEExcessEma : gESurplusEma;
		const float cap = Catalog::gConvCapacity[d];
		const float chew = (spill < cap) ? spill : cap;
		return (chew > 0.f) ? chew * Catalog::gConvRatio[d] : 0.f;
	}
	float dI = Catalog::gMakeM[d];
	if (Catalog::gMakeE[d] > 0.f)
		dI += Catalog::gMakeE[d] * ConvRate();
	return (dI > 0.f) ? dI : 0.f;
}

float PlanFeedM()
{
	const float look = ai.GetTunable("apex_e_lookahead", TUNE_E_LOOKAHEAD);
	return Eco::MInc() + Eco::MCur() / ((look > 1.f) ? look : 30.f);
}

float PlanBP()
{
	float bp = 0.f;
	for (uint i = 0; i < gWorkers.length(); ++i) {
		CCircuitUnit@ u = gWorkers[i];
		if ((u !is null) && (u.circuitDef !is null))
			bp += Catalog::gBuildPower[int(u.circuitDef.id)];
	}
	return bp;
}

float PlanKey(int d, float remM, float remW, float gain, float feed, float bp)
{
	if (gain <= 0.0001f)
		return ETA_BIG;
	float t = remM / ((feed > 0.1f) ? feed : 0.1f);
	const float tb = remW / ((bp > 1.f) ? bp : 1.f);
	if (tb > t)
		t = tb;
	float surv = TechSurvival(d, gPoolSurvBP);
	if (surv < 0.05f)
		surv = 0.05f;
	return t / gain / surv;
}

void PlanAdd(int kind, int d, const AIFloat3& in at, float remM, float remW, float gain, IUnitTask@ t, float feed,
		float bp)
{
	const float key = PlanKey(d, remM, remW, gain, feed, bp);
	uint i = 0;
	while ((i < gPjKey.length()) && (gPjKey[i] <= key))
		++i;
	gPjKind.insertAt(i, kind);
	gPjDef.insertAt(i, d);
	gPjPos.insertAt(i, at);
	gPjRemM.insertAt(i, remM);
	gPjRemW.insertAt(i, remW);
	gPjGain.insertAt(i, gain);
	gPjKey.insertAt(i, key);
	gPjBP.insertAt(i, 0.f);
	gPjHave.insertAt(i, 0.f);
	gPjN.insertAt(i, 0);
	gPjTask.insertAt(i, t);
	gPjUnit.insertAt(i, gPlanAddUnit);
}

void SeatPlanUpdate()
{
	if (ai.frame - gPlanAt < 5 * SECOND)
		return;
	gPlanAt = ai.frame;
	gPjKind.resize(0); gPjDef.resize(0); gPjPos.resize(0); gPjRemM.resize(0); gPjRemW.resize(0);
	gPjGain.resize(0); gPjKey.resize(0); gPjBP.resize(0); gPjHave.resize(0); gPjN.resize(0); gPjTask.resize(0); gPjUnit.resize(0);
	const float feed = PlanFeedM();
	const float bp = PlanBP();
	gPlanFeedM = feed;
	gPlanBP = bp;
	// frames in progress, on what they still need
	for (uint i = 0; i < Requests::gLive.length(); ++i) {
		IUnitTask@ t = Requests::gLive[i];
		if ((t is null) || t.IsDead() || (t.buildDef is null) || (t.GetType() != Task::Type::BUILDER))
			continue;
		const int d = int(t.buildDef.id);
		if (!Catalog::ValidId(d) || Catalog::gMobile[d])
			continue;
		const float done = Requests::Progress(t);
		const AIFloat3 at = t.GetBuildPos();
		PlanAdd(PJ_FRAME, d, at, Catalog::gCostM[d] * (1.f - done), Catalog::gBuildTime[d] * (1.f - done),
				PlanGainAt(d, at), t, feed, bp);
		{
			float have = 0.f;
			array<CCircuitUnit@>@ crew = t.GetUnits();
			for (uint c = 0; (crew !is null) && (c < crew.length()); ++c)
				if ((crew[c] !is null) && (crew[c].circuitDef !is null))
					have += Catalog::gBuildPower[int(crew[c].circuitDef.id)];
			for (uint k = 0; k < gPjTask.length(); ++k)
				if (gPjTask[k] is t)
					gPjHave[k] = have;
		}
	}
	// FRAMES WHOSE REQUEST DIED (his 11-05 watch: 17 of 44 unfinished upgrade frames decayed with nobody on them; an
	// aborted task leaves its frame standing with no task, so a plan read from the live tasks never saw it). They
	// are in the commitment ledger as orphans, priced on what they still need like any frame.
	for (uint c = 0; c < gComDef.length(); ++c) {
		if (!ComIsOrphan(c))
			continue;
		CCircuitUnit@ fu = ai.GetTeamUnit(gComId[c]);
		if ((fu is null) || (fu.circuitDef is null))
			continue;
		const int d = int(fu.circuitDef.id);
		if (!Catalog::ValidId(d) || Catalog::gMobile[d])
			continue;
		float done = fu.GetHealthPercent();
		if (done < 0.f)
			done = 0.f;
		if (done > 0.99f)
			done = 0.99f;
		const AIFloat3 at = fu.GetPos(ai.frame);
		gPlanAddUnit = int(fu.id);
		PlanAdd(PJ_FRAME, d, at, Catalog::gCostM[d] * (1.f - done), Catalog::gBuildTime[d] * (1.f - done),
				PlanGainAt(d, at), null, feed, bp);
		gPlanAddUnit = -1;
	}
	// new growth from the ladder's pool (what our constructors can build now)
	PoolRefresh();
	if (gPoolNow !is null) {
		for (uint r = 0; r < gPoolNow.def.length(); ++r) {
			const int d = gPoolNow.def[r];
			PlanAdd(PJ_RUNG, d, AIFloat3(-1.f, 0.f, -1.f), gPoolNow.cost[r], Catalog::gBuildTime[d],
					gPoolNow.gain[r], null, feed, bp);
			gPjN[gPjN.length() - 1] = gPoolNow.n[r];   // the copies the map still holds, admitted one at a time below
		}
	}
	// ADMIT OVER THE NEXT MINUTE, NOT THIS INSTANT (bench plan1: admitting only what today's flow could feed at once
	// left half the build power with nothing admitted -- a hand walking draws nothing -- and cost 13 m/s at minute 16
	// and 6 extractors). Over the window the feed pays feed x H metal and the hands do bp x H of work; jobs are taken in
	// payback order, each as much of its remaining work as fits, so cheap claims go out together and a big build
	// stays concentrated; no job takes more hands than can reach it before it is done.
	const float H = PLAN_WINDOW_S;
	// The economy's share of the feed, not all of it (his 11-05: resources by the target's shares): the army's share
	// stays with the factories, defence's with its election (bench plan2: the whole feed planned for economy, army -56%).
	const float ecoShare = Brain::TargetShare(Brain::ECONOMY) + Brain::TargetShare(Brain::BUILDPOWER);
	float metalLeft = feed * H * ((ecoShare > 0.05f) ? ecoShare : 0.05f);
	float eLeft = EtaEnergyAvail() * H + Eco::ECur();
	// and the economy's share of the hands: the rest help the factories, raise defence, reclaim (bench plan2: 96% of
	// the hands planned for economy, frames absorbing them, army -56%, extractors -5.7 at minute 16)
	const float handShare = (ecoShare > 0.05f) ? ecoShare : 0.05f;
	float workLeft = bp * H * handShare;
	float bpLeft = bp * handShare;
	gPlanAdmitted = 0;
	const float walkS = (gPoolSpotWalkS > 10.f) ? gPoolSpotWalkS : 10.f;
	for (uint i = 0; i < gPjKey.length(); ++i) {
		const int copiesSeen = gPjN[i];
		gPjN[i] = 0;
		if ((metalLeft <= 1.f) || (workLeft <= H) || (bpLeft <= 1.f))
			continue;
		if (gPjGain[i] <= 0.f)
			continue;   // not an economy job: its kind's share decides it, not this walk
		const int d = gPjDef[i];
		const float W = gPjRemW[i];
		if (W <= 1.f)
			continue;
		const float mPerW = gPjRemM[i] / W;
		const float ePerW = Catalog::gCostE[d] / ((Catalog::gBuildTime[d] > 1.f) ? Catalog::gBuildTime[d] : 1.f);
		const float bpCap = W / walkS;   // the build power that still lands after the walk
		const int copies = (gPjKind[i] == PJ_RUNG) ? ((copiesSeen > 0) ? copiesSeen : 1) : 1;
		int took = 0;
		float given = 0.f;
		for (int c = 0; (c < copies) && (metalLeft > 1.f) && (workLeft > H) && (bpLeft > 1.f); ++c) {
			// as many hands as still land before it is done, so it finishes as fast as walking allows
			float b = (bpCap < bpLeft) ? bpCap : bpLeft;
			float w = W;
			if (w > b * H)
				w = b * H;
			if (w > workLeft)
				w = workLeft;
			if ((mPerW > 0.f) && (w * mPerW > metalLeft))
				w = metalLeft / mPerW;
			if ((ePerW > 0.f) && (w * ePerW > eLeft))
				w = (eLeft > 0.f) ? (eLeft / ePerW) : 0.f;
			// a job the window can only part-pay gets hands for the part it pays
			const float full = (W < b * H) ? W : (b * H);
			if ((full > 0.f) && (w < full))
				b *= w / full;
			if (b < 1.f)
				break;
			metalLeft -= w * mPerW;
			eLeft -= w * ePerW;
			workLeft -= w;
			bpLeft -= b;
			given += b;
			++took;
		}
		if (took > 0) {
			gPjBP[i] = given;
			gPjN[i] = took;
			gPlanAdmitted += took;
		}
	}
	gPlanFeedUsed = feed - metalLeft / H;
	gPlanBPUsed = bp * handShare - bpLeft;
}

// The plan's job for this builder: the highest admitted job it can serve -- lathe a frame that stands (any hand can),
// or found an admitted def it can build. -1 when the plan has nothing for it.
int PlanJobFor(CCircuitUnit@ unit)
{
	if ((unit is null) || (unit.circuitDef is null))
		return -1;
	// WHERE THIS HAND'S TIME DOES THE MOST GOOD (bench plan3: the hands' output fell 14% -- each went to the top job
	// however far, and walked). A hand is worth to a job its return per unit of work times the seconds it will
	// actually lathe inside the window, the window less its walk; the planned job that scores highest takes it.
	const AIFloat3 me = unit.GetPos(ai.frame);
	const float speed = Catalog::gSpeed[int(unit.circuitDef.id)];
	const float v = (speed > 1.f) ? speed : 60.f;
	const float rungWalk = (gPoolSpotWalkS > 1.f) ? gPoolSpotWalkS : 30.f;
	int best = -1;
	float bestS = 0.f;
	for (uint i = 0; i < gPjKey.length(); ++i) {
		if ((gPjN[i] <= 0) || (gPjBP[i] <= 0.f) || (gPjHave[i] >= gPjBP[i]) || (gPjRemW[i] <= 1.f))
			continue;
		const int d = gPjDef[i];
		float walk = rungWalk;
		if (gPjKind[i] == PJ_FRAME) {
			IUnitTask@ t = gPjTask[i];
			if ((t is null) && (gPjUnit[i] < 0))
				continue;
			if ((t !is null) && (t.IsDead() || ((t.target is null) && !unit.circuitDef.CanBuild(Catalog::Def(d)))))
				continue;
			walk = me.distance2D(gPjPos[i]) / v;
		} else if (!unit.circuitDef.CanBuild(Catalog::Def(d))) {
			continue;
		}
		const float working = PLAN_WINDOW_S - walk;
		if (working <= 0.f)
			continue;
		const float s = gPjGain[i] / gPjRemW[i] * working;
		if (s > bestS) {
			bestS = s;
			best = int(i);
		}
	}
	// THE JOB IN HAND, ON ITS REAL WALK AND REAL REMAINING WORK (bench plan2v2b: 1,025 plan switches, 961 of them a
	// claim left for another claim -- every claim priced on the mean walk scored alike and the first in the list took
	// the hand, so the half-walked claim decayed). Kept while it scores at least the best other job.
	gPlanStay = false;
	const int uid = int(unit.id);
	if ((uid >= 0) && (uid < int(gSpLast.length()))) {
		IUnitTask@ cur = gSpLast[uid];
		if ((cur !is null) && !cur.IsDead() && (cur.buildDef !is null)) {
			const int cd = int(cur.buildDef.id);
			const float done = Requests::Progress(cur);
			const float remW = Catalog::gBuildTime[cd] * (1.f - done);
			const AIFloat3 cp = cur.GetBuildPos();
			const float working = PLAN_WINDOW_S - (OnMap(cp) ? me.distance2D(cp) / v : 0.f);
			const float g = PlanGainAt(cd, cp);
			if ((done < 1.f) && (remW > 1.f) && (working > 0.f) && (g > 0.f) && (g / remW * working >= bestS)) {
				gPlanStay = true;
				return -1;
			}
		}
	}
	return best;
}
bool gPlanStay = false;

// SHADOW: per election, does the builder's choice match what the plan would send it to?
int gSpnElect = 0, gSpnAgree = 0, gSpnNoJob = 0, gSpnHelp = 0, gSpnFound = 0, gSpnAt = 0;
void SeatPlanNote(CCircuitUnit@ unit, Want@ top)
{
	if (top is null)
		return;
	++gSpnElect;
	const int j = PlanJobFor(unit);
	if (j < 0) {
		++gSpnNoJob;
	} else {
		if (gPjKind[j] == PJ_FRAME)
			++gSpnHelp;
		else
			++gSpnFound;
		if ((top.def !is null) && (int(top.def.id) == gPjDef[j]))
			++gSpnAgree;
	}
	if (ai.frame < gSpnAt)
		return;
	gSpnAt = ai.frame + 60 * SECOND;
	string head = "";
	int shown = 0;
	for (uint i = 0; (i < gPjKey.length()) && (shown < 4); ++i) {
		if (gPjN[i] <= 0)
			continue;
		head += " " + ((gPjKind[i] == PJ_FRAME) ? "frame:" : "new:") + Catalog::Def(gPjDef[i]).GetName()
			+ "x" + gPjN[i] + "@" + int(gPjBP[i]) + "bp/k" + int(gPjKey[i]);
		++shown;
	}
	int frames = 0;
	for (uint i = 0; i < gPjKind.length(); ++i)
		if (gPjKind[i] == PJ_FRAME)
			++frames;
	AiLog(Factory::T() + "apex: seatplan t=" + ai.teamId + " feed=" + NnF(gPlanFeedM, 1) + " used=" + NnF(gPlanFeedUsed, 1)
		+ " bp=" + int(gPlanBP) + " bpUsed=" + int(gPlanBPUsed) + " frames=" + frames + " admitted=" + gPlanAdmitted
		+ " | elections=" + gSpnElect + " agree=" + gSpnAgree + " noJob=" + gSpnNoJob + " planHelp=" + gSpnHelp
		+ " planFound=" + gSpnFound + " | steer=" + (SeatPlanOn() ? 1 : 0) + " disp=" + gSpDisp + " help=" + gSpDispHelp
		+ " found=" + gSpDispFound + " yield=" + gSpYield + " dropped=" + gSpDrop + " orphans=" + gSpOrphan + " switches=" + gSpSwitch + " stays=" + gSpStay
		+ " riskyFound=" + gSpRiskyFound + " |" + head);
	gSpDisp = 0; gSpDispHelp = 0; gSpDispFound = 0; gSpYield = 0; gSpDrop = 0; gSpOrphan = 0; gSpRiskyFound = 0; gSpStay = 0;
	gSpnElect = 0; gSpnAgree = 0; gSpnNoJob = 0; gSpnHelp = 0; gSpnFound = 0;
}

}  // namespace Market

namespace Market {

// THE PLAN STEERS (apex_seat_plan 1). A builder takes its planned job: a frame that stands is handed to it as is (the
// task lathes the frame, CmdRepair, so any hand can); a planned new building goes to the best site the proposers
// priced for that def. Defence, air defence, sensors and plants stay with the election while their kind is under
// its spend share (his 11-05 share ruling); economy is started only by the plan.
int gSpDisp = 0, gSpDispHelp = 0, gSpDispFound = 0, gSpYield = 0, gSpDrop = 0, gSpOrphan = 0;
int gSpSwitch = 0, gSpSwitchAt = 0, gSpRiskyFound = 0, gSpStay = 0;
array<IUnitTask@> gSpLast(32001);
// THE PLAN'S OWN CHURN (bench plan2v2: T1 claims left under 10% built 3.0 -> 8.1 a game with the plan on): a hand
// moved to a new job while the last one the plan gave it still stands unfinished.
void PlanNoteGiven(CCircuitUnit@ unit, IUnitTask@ t)
{
	const int id = int(unit.id);
	if ((id < 0) || (id >= int(gSpLast.length())))
		return;
	IUnitTask@ old = gSpLast[id];
	if ((old !is null) && (old !is t) && !old.IsDead() && (old.buildDef !is null) && (Requests::Progress(old) < 1.f)) {
		++gSpSwitch;
		if (ai.frame >= gSpSwitchAt) {
			gSpSwitchAt = ai.frame + 30 * SECOND;
			AiLog(Factory::T() + "apex: plan-switch t=" + ai.teamId + " " + unit.circuitDef.GetName() + " #" + unit.id
				+ " left " + old.buildDef.GetName() + " done=" + NnF(Requests::Progress(old), 2)
				+ " for " + ((t.buildDef !is null) ? t.buildDef.GetName() : "-") + " total=" + gSpSwitch);
		}
	}
	@gSpLast[id] = t;
}
bool PlanEcoCat(int cat)
{
	return (cat == CAT_METAL) || (cat == CAT_ENERGY) || (cat == CAT_BP);
}
bool PlanAdmitsDef(int d)
{
	for (uint i = 0; i < gPjDef.length(); ++i)
		if ((gPjDef[i] == d) && (gPjN[i] > 0) && (gPjBP[i] > 0.f))
			return true;
	return false;
}
IUnitTask@ SeatPlanDispatch(CCircuitUnit@ unit, const array<Want@>@ ranked, Want@ top)
{
	// The opening is the election's until the first factory stands: an economy-only plan cannot see that a seat with
	// no lab has no army (the first controlled game: no army at minute 9, every extractor lost).
	if (Factory::gFactoryCount == 0)
		return null;
	const int j = PlanJobFor(unit);
	if (gPlanStay) {
		++gSpStay;
		const int sid = int(unit.id);
		return gSpLast[sid];
	}
	if (j < 0)
		return null;
	// a want outside the economy whose kind is under its share keeps the hand: defence, sensors and anti-air by
	// their own shares; a plant by the army's (a lab is what turns metal into army), and always while no factory
	// stands (the first controlled game built none and lost every extractor by minute 9); the advanced lab and
	// the strategic buildings by their own pricing
	// helping a factory is how build power becomes army (bench plan1: army -41% when the plan took these hands)
	if ((top !is null) && (top.kind == WK_ASSIST) && (top.joinPath != Requests::JA_ASSIST)
		&& !gNpCatOver[int(Brain::ARMY)]) {
		++gSpYield;
		return null;
	}
	if ((top !is null) && !PlanEcoCat(CategoryOf(top.kind))) {
		bool yields = false;
		if ((top.kind == WK_PROTECT) || (top.kind == WK_SENSE))
			yields = !gNpCatOver[int(Brain::DEFENCE)];
		else if (top.kind == WK_AIRDEF)
			yields = !gNpCatOver[int(Brain::AIRDEF)];
		else if (top.kind == WK_PLANT)
			yields = (Factory::gFactoryCount == 0) || !gNpCatOver[int(Brain::ARMY)];
		else
			yields = true;
		if (yields && PlanFits(top)) {
			++gSpYield;
			return null;
		}
	}
	if (gPjKind[j] == PJ_FRAME) {
		IUnitTask@ t = gPjTask[j];
		if ((t is null) && (gPjUnit[j] >= 0)) {
			// an orphan: the executor adopts the nearest standing frame of a def before it founds one (execute.as,
			// frame-adopt), so the hand goes through its own want for that def -- the arbiter's path, no leaf spend
			for (uint i = 0; i < ranked.length(); ++i) {
				Want@ w = ranked[i];
				if ((w is null) || (w.def is null) || (int(w.def.id) != gPjDef[j]))
					continue;
				IUnitTask@ ta = ExecuteWant(unit, w);
				if (ta !is null) {
					++gSpDisp;
					++gSpOrphan;
					gPjHave[j] += Catalog::gBuildPower[int(unit.circuitDef.id)];
					PlanNoteGiven(unit, ta);
					return ta;
				}
			}
			return null;
		}
		if ((t is null) || t.IsDead())
			return null;
		++gSpDisp;
		++gSpDispHelp;
		gPjHave[j] += Catalog::gBuildPower[int(unit.circuitDef.id)];
		PlanNoteGiven(unit, t);
		return t;
	}
	for (uint i = 0; i < ranked.length(); ++i) {
		Want@ w = ranked[i];
		if ((w is null) || (w.def is null) || (int(w.def.id) != gPjDef[j]))
			continue;
		IUnitTask@ t = ExecuteWant(unit, w);
		if (t !is null) {
			++gSpDisp;
			++gSpDispFound;
			gPjHave[j] += Catalog::gBuildPower[int(unit.circuitDef.id)];
			// a start the election itself rated far below its best want: the plan took a site the price called risky
			if ((ranked.length() > 0) && (ranked[0] !is null) && (w.value < 0.25f * ranked[0].value))
				++gSpRiskyFound;
			PlanNoteGiven(unit, t);
			return t;
		}
	}
	return null;
}
// EVERY SPEND THROUGH THE PLAN (his 11-05: "every single spend we make needs to be considered in this way"; a seat
// pulling 150-160 m/s on 89 of income with a fusion, an advanced air plant, an upgrade, an advanced converter, an
// advanced solar and an anti-nuke all open at once). A start outside the economy fits its kind's share of the
// window's metal, counting the frames of that kind already open; a kind with nothing open may always start one, so
// a building dearer than a window's share (an anti-nuke) is never shut out. Economy starts only as the plan admits.
float PlanOpenM(int cat)
{
	float m = 0.f;
	for (uint i = 0; i < gPjKind.length(); ++i)
		if ((gPjKind[i] == PJ_FRAME) && (NpKindOf(gPjDef[i]) == cat))
			m += gPjRemM[i];
	return m;
}
bool PlanFits(Want@ w)
{
	if ((w is null) || (w.def is null) || (w.kind == WK_ASSIST) || (w.kind == WK_RECLAIM))
		return true;
	const int d = int(w.def.id);
	if (PlanEcoCat(CategoryOf(w.kind)))
		return PlanAdmitsDef(d);
	const int cat = NpKindOf(d);
	const float open = PlanOpenM(cat);
	if (open <= 0.f)
		return true;
	return open + Catalog::gCostM[d] <= gPlanFeedM * PLAN_WINDOW_S * Brain::TargetShare(Brain::Cat(cat));
}
Want@ SeatPlanFilterTop(const array<Want@>@ ranked, Want@ top)
{
	if (PlanFits(top))
		return top;
	for (uint i = 0; i < ranked.length(); ++i) {
		Want@ w = ranked[i];
		if ((w is null) || (w.value <= 0.f) || !PlanFits(w))
			continue;
		++gSpDrop;
		return w;
	}
	++gSpDrop;
	return null;
}
// The crew the plan admits to a frame, in hands, for the peel: -1 when the plan does not hold it.
int PlanCrewFor(IUnitTask@ t)
{
	if (!SeatPlanOn() || (t is null))
		return -1;
	for (uint i = 0; i < gPjTask.length(); ++i) {
		if (gPjTask[i] is t) {
			if ((gPjN[i] <= 0) || (gPjBP[i] <= 0.f))
				return -1;
			const float avg = (gWorkers.length() > 0) ? (gPlanBP / float(gWorkers.length())) : 100.f;
			const int n = int(ceil(gPjBP[i] / ((avg > 1.f) ? avg : 1.f)));
			return (n > 1) ? n : 1;
		}
	}
	return -1;
}

}  // namespace Market
