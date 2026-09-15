namespace Market {

// How far from a blocked lattice slot one of our own structures counts as the
// thing standing in it. A footprint's reach, not a search radius: further away
// and it is not what refused the slot.
const float BLOCKER_REACH = 160.f;

// Obsolete generators price their own metal back into the market: when the
// E economy is structurally in surplus (removing the candidate keeps it so)
// and the bank has room for the burst, a weak generator's banked metal
// beats its trickle. Weakest first (lowest makeE per metal).
// WHAT RETIRING ONE OF OUR OWN STRUCTURES IS WORTH -- one price, so a solar,
// a dominated turret and a superseded lab compare on the same scale. The metal
// back plus the defended ground it stops renting, minus the output it still
// makes. Ground is SpaceRentM, the same rent every eco placement already pays,
// so a building inside our own cover has to earn its cells.
// Do we own a dedicated reclaimer at all? Cached per frame -- the hand
// multiplier below is asked once per reclaim proposer per election.
bool gOwnRez = false;
int gOwnRezAt = -1;

bool OwnAnyRezzer()
{
	if (gOwnRezAt == ai.frame)
		return gOwnRez;
	gOwnRezAt = ai.frame;
	gOwnRez = false;
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		if ((gOwnCount[d] > 0) && Catalog::gRezzer[int(d)]
			&& Catalog::gMobile[int(d)])
		{
			gOwnRez = true;
			break;
		}
	}
	return gOwnRez;
}

// IN-FLIGHT RETIREMENTS, so reclaim runs in PARALLEL (apexearth: "We can do
// more than 1 at a time"). Without this every electing hand converged on the
// one argmax victim while its neighbours stood. A victim another worker has
// claimed is skipped, so the second con takes the next-best; a worker's own
// claim is not a skip, which keeps its re-elections stable. Claims expire on
// a walk-plus-eat clock so a dead worker frees its victim.
array<Id> gReclaimTgt;
array<Id> gReclaimBy;
array<int> gReclaimUntil;
// The victim's handle and its ground, for the nano pile-on below. The pos is
// stored at claim time so nothing ever calls GetPos on a stored handle:
// reading a deferred-dead unit is an access violation.
array<CCircuitUnit@> gReclaimHand;
array<AIFloat3> gReclaimPos;

bool ReclaimClaimed(Id tgt, Id worker)
{
	for (uint i = 0; i < gReclaimTgt.length(); ) {
		if (ai.frame >= gReclaimUntil[i]) {
			gReclaimTgt.removeAt(i);
			gReclaimBy.removeAt(i);
			gReclaimUntil.removeAt(i);
			gReclaimHand.removeAt(i);
			gReclaimPos.removeAt(i);
			continue;
		}
		if ((gReclaimTgt[i] == tgt) && (gReclaimBy[i] != worker))
			return true;
		++i;
	}
	return false;
}

void NoteReclaimClaim(Id tgt, Id worker, int untilFrame,
		CCircuitUnit@ hand = null, const AIFloat3& in at = AIFloat3(-1.f, 0.f, -1.f))
{
	for (uint i = 0; i < gReclaimTgt.length(); ++i) {
		if (gReclaimTgt[i] == tgt) {
			gReclaimBy[i] = worker;
			gReclaimUntil[i] = untilFrame;
			@gReclaimHand[i] = hand;
			gReclaimPos[i] = at;
			return;
		}
	}
	gReclaimTgt.insertLast(tgt);
	gReclaimBy.insertLast(worker);
	gReclaimUntil.insertLast(untilFrame);
	gReclaimHand.insertLast(hand);
	gReclaimPos.insertLast(at);
}

// TURRETS PILE ONTO THE RECLAIM (apexearth: "We have a lot of constructor
// units & turrets which could be doing this"; 2026-08-28 night: "those guys
// are great for reclaiming old buildings"). An idle nano in range of a
// claimed victim is handed the same target with CmdReclaimUnit -- raw on
// purpose: nanos are factory-manager units and cannot take builder tasks.
// The victim already sits in the reclaim registry through the constructor's
// own task, so nothing repairs it back; queue==0 keeps working assisters on
// their build.
array<int> gNanoDefs;
bool gNanoDefsSet = false;
int gNanoAssistNext = 0;

void NanoReclaimAssist()
{
	if (ai.frame < gNanoAssistNext)
		return;
	gNanoAssistNext = ai.frame + 15 * SECOND;
	if (!gNanoDefsSet) {
		gNanoDefsSet = true;
		for (int d = 1; d <= Catalog::gDefCount; ++d) {
			if (Catalog::gMobile[d] || (Catalog::gBuildPower[d] <= 0.f)
				|| (Catalog::gCostM[d] <= 1.f)
				|| (Catalog::gBuildsList[d].length() > 0))
				continue;
			gNanoDefs.insertLast(d);
		}
	}
	if (gNanoDefs.length() == 0)
		return;
	const float reach = NanoRange();
	int sent = 0;
	for (uint i = 0; (i < gReclaimTgt.length()) && (sent < 6); ++i) {
		if (ai.frame >= gReclaimUntil[i])
			continue;
		CCircuitUnit@ v = gReclaimHand[i];
		if (v is null)
			continue;
		const AIFloat3 vp = gReclaimPos[i];
		if (!OnMap(vp))
			continue;
		for (uint n = 0; (n < gNanoDefs.length()) && (sent < 6); ++n) {
			array<CCircuitUnit@>@ ns = ai.GetOwnUnitsOfDef(
					Catalog::Def(gNanoDefs[n]), vp, reach);
			if (ns is null)
				continue;
			for (uint k = 0; (k < ns.length()) && (sent < 6); ++k) {
				if ((ns[k] is null) || (ns[k].CmdQueueSize() > 0))
					continue;
				ns[k].CmdReclaimUnit(v);
				++sent;
			}
		}
	}
	if (sent > 0)
		AiLog("apex: nano-assist reclaim x" + sent);
}

// WHOSE HANDS THESE ARE. apexearth 2026-08-27: "we aren't expanding enough...
// can we prefer reclaims through rezbots instead of our cons which should be
// expanding?" A PREFERENCE, not a rule about who is allowed to reclaim -- a
// constructor still takes the job when nothing better is on its list, which is
// the only reason tidying ever happens on a map with no rezbot on it.
//
// A dedicated reclaimer is one that builds NOTHING: cornecro and armrectr have
// empty build lists, so they have no expansion to be pulled off. The penalty
// side applies only while there is ground left to claim -- once gMexOpen is
// false the con is not being distracted from anything.
float ReclaimHandMul(CCircuitUnit@ unit)
{
	const float bias = ai.GetTunable("apex_reclaim_rez_bias", TUNE_RECLAIM_REZ_BIAS);
	if (bias <= 1.f)
		return 1.f;
	const int uid = int(unit.circuitDef.id);
	if (Catalog::gRezzer[uid] || (Catalog::gBuildsList[uid].length() == 0))
		return bias;
	if (!gMexOpen)
		return 1.f;
	// NOBODY IS DISPLACED BEFORE THEIR REPLACEMENT EXISTS -- the same law the
	// generator, lab and con retirements here already follow. Penalising the
	// constructor while we own no rezbot hands the work to nothing, and
	// obsolete solars and duplicate plants then stand untouched.
	if (!OwnAnyRezzer())
		return 1.f;
	// Only a hand that could be claiming ground instead pays the penalty.
	const array<int>@ mine = Catalog::BuildsOf(uid);
	for (uint i = 0; i < mine.length(); ++i) {
		if (Catalog::gExtractsM[mine[i]] > 0.f)
			return 1.f / bias;
	}
	return 1.f;
}

float RetireGain(CCircuitUnit@ tgt, int d, float ePM, float hz)
{
	const int cells = (Catalog::gAreaCells[d] > 0) ? Catalog::gAreaCells[d] : 1;
	// ROOM IS WORTH SOMETHING ONLY WHEN IT IS SCARCE. SpaceRentM prices ground
	// by the turret cover standing over it, which is ~0 in a base with few
	// turrets -- so an obsolete wind farm paid nothing for the ground it was
	// squatting on and its trickle of energy always outweighed its refund.
	// PfCrowd is the measured fill of the base's own rim, and PfMetalPerCell
	// what a cell of it carries, so the freed ground is priced at what the base
	// actually puts on a cell, and the whole term vanishes on an empty map.
	// ROOM IS LOCAL (see PfCrowdAt): the base-wide fill falls toward zero as
	// the rim grows, in the very games he could see had no room.
	const AIFloat3 at = tgt.GetPos(ai.frame);
	// ...and the safest ground is scarce whatever the fill: the T1 eco that
	// went up first sits at the base centre, exactly where the advanced
	// fusion and converter are asked for (apexearth 2026-09-12: "all that T1
	// eco ends up sitting in the safest spot of our base -- the center --
	// which is where we'd much rather put AFUS and advanced converters").
	float crowd = PfCrowdAt(at, 400.f);
	const float core = BigEcoGroundAt(at, 700.f);
	if (core > crowd)
		crowd = core;
	const float room = crowd * PfMetalPerCell() * float(cells)
			* ai.GetTunable("apex_room_worth", TUNE_ROOM_WORTH);
	// THE GROUND YIELDS MORE UNDER ITS SUCCESSOR: what our best generator (or
	// converter) makes on these cells beyond what this one makes, realizable
	// to the extent the ground around it is already full -- on open ground
	// the successor simply goes next door and the upside is nothing.
	RefreshBestCells();
	float mine = 0.f, best = 0.f;
	if (Catalog::gMakeE[d] > 0.f) {
		mine = Catalog::gMakeE[d] / float(cells);
		best = gBestEcell;
	} else if (Catalog::gConvCapacity[d] > 0.f) {
		mine = Catalog::gConvCapacity[d] / float(cells);
		best = gBestMcell;
	}
	const float upside = ((best > mine) ? (best - mine) : 0.f) * float(cells) * ePM * crowd;
	// A DEF WE WOULD REFUSE TO BUILD KEEPS NO CREDIT FOR ITS TRICKLE
	// (apexearth 2026-09-13: "Our base ends up cluttered with buildings which
	// aren't worth the space they take up. Old energy, old converters, old
	// defenses. We need to clean up a lot faster"). Its output netted against
	// its refund held a solar at zero for the whole game once an advanced
	// fusion stood; the same per-cell dwarf test that refuses to build it
	// says its output is had cheaper on the same ground.
	const bool dwarfed = (Catalog::gMakeE[d] > 0.f) ? GenObsoleteOnArrival(d)
			: ((Catalog::gConvCapacity[d] > 0.f) ? ConvObsoleteOnArrival(d) : false);
	const float trickle = dwarfed ? 0.f
			: (Catalog::gMakeE[d] * ePM
				+ Catalog::gConvCapacity[d] * Catalog::gConvRatio[d]);   // the metal it converts
	return (Catalog::gCostM[d] + SpaceRentM(at, cells) + room) / hz
			+ upside
			- trickle;
}

float RetireValue(CCircuitUnit@ unit, CCircuitUnit@ tgt, int d, float ePM,
		float wage, float hz)
{
	// A JUST-BUILT STRUCTURE IS NEVER OBSOLETE -- same law the con path
	// already applies via apex_reclaim_age_s, at the window the rebuy
	// discount runs for. Without it the market eats the plant it just built.
	{
		const int born = BuiltFrameOf(tgt);
		const float win = ai.GetTunable("apex_replant_window_s",
				TUNE_REPLANT_WINDOW_S);
		if ((born > 0) && (float(ai.frame - born) < win * float(SECOND)))
			return 0.f;
	}
	const float gain = RetireGain(tgt, d, ePM, hz);
	if (gain <= 0.f)
		return 0.f;
	const float speed = Catalog::gSpeed[int(unit.circuitDef.id)];
	const float walkSec = (speed > 1.f)
			? (unit.GetPos(ai.frame).distance2D(tgt.GetPos(ai.frame)) / speed) : 60.f;
	return gain / (1.f + (walkSec + Catalog::gCostM[d] / 90.f) * wage);
}

// ONE LAW, BOTH SIDES (apexearth 2026-08-28: "When we reclaim obsolete
// buildings - we often recreate them in the exact same spot. We should never
// want to create obsolete buildings."): the per-cell dwarf test the victim
// election applies below is exactly the test a NEW build must pass first --
// a def our own best already dwarfs is obsolete ON ARRIVAL, and the energy
// and converter ladders refuse to propose it. Derived, no memory of what was
// eaten; the moment an AFUS stands, wind is unproposable by the same number
// that makes wind edible.
float gBestEcell = 0.f;
float gBestMcell = 0.f;
int gBestCellAt = -999999;

void RefreshBestCells()
{
	if (ai.frame < gBestCellAt + 5 * SECOND)
		return;
	gBestCellAt = ai.frame;
	gBestEcell = 0.f;
	gBestMcell = 0.f;
	for (uint i = 0; i < gOwnGen.length(); ++i) {
		if (gOwnGen[i] is null)
			continue;
		const int d = int(gOwnGen[i].circuitDef.id);
		const float ec = Catalog::gMakeE[d]
				/ float((Catalog::gAreaCells[d] > 0) ? Catalog::gAreaCells[d] : 1);
		if (ec > gBestEcell)
			gBestEcell = ec;
	}
	// WHAT WE COULD BUILD, not only what we happen to own.
	//
	// This scanned STANDING converters, so the basic one could never be
	// obsolete until an advanced one already stood -- and the basic one costs
	// ONE METAL, so it won every value election and we kept building it.
	// Measured (watch-ecorole, Comet Catcher 8v8 +100%, 30 min): 512 basic
	// converters standing against 52 advanced ones. apexearth, watching: "I
	// still see a lot of basic energy converters taking up space... they
	// really do take up a lot of room", and the reclaim "feels a bit too
	// late" at 26 minutes.
	//
	// The per-space arithmetic he is asking for is already the metric here and
	// it is decisive: armmakr is 3x3 = 9 cells for 70 e/s (7.8 per cell),
	// armmmkr 4x4 = 16 cells for 600 (37.5 per cell) -- 4.8x the throughput on
	// the same ground. Reading availability instead of ownership is what lets
	// that arithmetic fire the moment the better one unlocks, rather than one
	// build too late.
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!Catalog::gAvailable[d] || Catalog::gMobile[d]
			|| (Catalog::gConvCapacity[d] <= 0.f))
			continue;
		const float mc = Catalog::gConvCapacity[d]
				/ float((Catalog::gAreaCells[d] > 0) ? Catalog::gAreaCells[d] : 1);
		if (mc > gBestMcell)
			gBestMcell = mc;
	}
	// The owned fleet is still a floor: if the availability flag ever reads
	// wrong, what is standing is ground truth and the old behaviour returns.
	for (uint i = 0; i < gOwnConv.length(); ++i) {
		if (gOwnConv[i] is null)
			continue;
		const int d = int(gOwnConv[i].circuitDef.id);
		const float mc = Catalog::gConvCapacity[d]
				/ float((Catalog::gAreaCells[d] > 0) ? Catalog::gAreaCells[d] : 1);
		if (mc > gBestMcell)
			gBestMcell = mc;
	}
}

bool GenObsoleteOnArrival(int d)
{
	RefreshBestCells();
	const float ec = Catalog::gMakeE[d]
			/ float((Catalog::gAreaCells[d] > 0) ? Catalog::gAreaCells[d] : 1);
	return (ec > 0.f) && (gBestEcell
			>= ai.GetTunable("apex_obsolete_ratio", TUNE_OBSOLETE_RATIO) * ec);
}

// EDIBLE ONLY IF THIS PAIR OF HANDS COULD HAVE BUILT THE BETTER ONE.
//
// The global test below asks whether a better converter exists anywhere. That
// is the right question for RECLAIM -- a standing basic is worth eating once
// an advanced one is possible -- and the WRONG question for a builder choosing
// what to make, because most of our constructors can only build the basic one.
// Blocking the basic globally does clear the ground it wastes, and costs most
// of our conversion throughput doing it, because nothing replaces what those
// hands can no longer make. The ground was cheaper than the energy then thrown
// away, so a builder is refused the basic only when it could have made the
// better one itself. Team-wide refusal: docs/27, TUNE_OBSOLETE_RATIO.
// THE TRANSITION OFF THE BASIC CONVERTER (apexearth 2026-09-08: "we stop
// wanting to build and then ... we start wanting to reclaim... you remove
// them once you have more than enough advanced converters"). Denser
// conversion we own or have ordered, against everything there is to convert:
// no hand builds the basic once the denser capacity covers it all, and a
// standing basic is eaten once that capacity covers it all AND the basic's
// own share -- so the metal it was making is never lost to the transition.
array<int> gDenserAt;
array<float> gDenserE;
float DenserConvCapE(int d)
{
	if (int(gDenserAt.length()) <= d) {
		const uint n0 = gDenserAt.length();
		gDenserAt.resize(d + 1);
		gDenserE.resize(d + 1);
		for (uint k = n0; k <= uint(d); ++k) {
			gDenserAt[k] = -999999;
			gDenserE[k] = 0.f;
		}
	}
	if (ai.frame < gDenserAt[d] + 5 * SECOND)
		return gDenserE[d];
	gDenserAt[d] = ai.frame;
	const float mine = Catalog::gConvCapacity[d]
			/ float((Catalog::gAreaCells[d] > 0) ? Catalog::gAreaCells[d] : 1);
	float e = 0.f;
	for (uint cd = 1; cd < gOwnCount.length(); ++cd) {
		if ((gOwnCount[cd] <= 0) || (Catalog::gConvCapacity[int(cd)] <= 0.f))
			continue;
		const float mc = Catalog::gConvCapacity[int(cd)]
				/ float((Catalog::gAreaCells[int(cd)] > 0) ? Catalog::gAreaCells[int(cd)] : 1);
		if (mc > mine)
			e += float(gOwnCount[cd]) * Catalog::gConvCapacity[int(cd)];
	}
	for (uint i = 0; i < Requests::gLive.length(); ++i) {
		IUnitTask@ t = Requests::gLive[i];
		if ((t is null) || (t.buildDef is null))
			continue;
		const int od = int(t.buildDef.id);
		if (Catalog::gConvCapacity[od] <= 0.f)
			continue;
		const float mc = Catalog::gConvCapacity[od]
				/ float((Catalog::gAreaCells[od] > 0) ? Catalog::gAreaCells[od] : 1);
		if (mc > mine)
			e += Catalog::gConvCapacity[od];
	}
	gDenserE[d] = e;
	return e;
}

// The same, standing units only.
float DenserConvStandingE(int d)
{
	const float mine = Catalog::gConvCapacity[d]
			/ float((Catalog::gAreaCells[d] > 0) ? Catalog::gAreaCells[d] : 1);
	float e = 0.f;
	for (uint cd = 1; cd < gOwnCount.length(); ++cd) {
		if ((gOwnCount[cd] <= 0) || (Catalog::gConvCapacity[int(cd)] <= 0.f))
			continue;
		const float mc = Catalog::gConvCapacity[int(cd)]
				/ float((Catalog::gAreaCells[int(cd)] > 0) ? Catalog::gAreaCells[int(cd)] : 1);
		if (mc > mine)
			e += float(gOwnCount[cd]) * Catalog::gConvCapacity[int(cd)];
	}
	return e;
}

// Everything there is to convert: the surplus nothing converts plus what the
// standing fleet already chews.
float ConvTotalE()
{
	return ConvertibleE() + ConvUseE();
}

// THE HANDS THAT CAN MAKE THE DENSER ONE COULD CONVERT IT ALL THEMSELVES
// (apexearth 2026-09-12: "even at 1000 metal per second we're still making
// basic converters... too fragile and take up far too much space" -- 163
// basics in four minutes beside eleven fusions). Not a count of T2
// constructors: the seconds those hands need to build the whole convertible
// surplus's worth of their best converter, against the fill window the rest
// of the economy plans in. One T2 con beside three fusions cannot, so the
// basics that carried the 2026-09-08 arm (docs/27, TUNE_OBSOLETE_RATIO) are
// still made; ten of them at 1,000 m/s can, and no hand makes a basic.
bool DenserHandsCover(int d)
{
	const float mine = Catalog::gConvCapacity[d] * Catalog::gConvRatio[d]
			/ float((Catalog::gAreaCells[d] > 0) ? Catalog::gAreaCells[d] : 1);
	float bp = 0.f;
	int best = -1;
	float bestPc = 0.f;
	array<int> denserDef;
	for (uint cd = 1; cd < gOwnCount.length(); ++cd) {
		const int di = int(cd);
		if ((gOwnCount[cd] <= 0) || !Catalog::gMobile[di] || !Catalog::gBuilder[di])
			continue;
		const array<int>@ b = Catalog::gBuildsList[di];
		if (b is null)
			continue;
		bool denser = false;
		for (uint i = 0; i < b.length(); ++i) {
			const int o = b[i];
			if (!Catalog::gAvailable[o] || Catalog::gMobile[o]
				|| (Catalog::gConvCapacity[o] <= 0.f))
				continue;
			const float pc = Catalog::gConvCapacity[o] * Catalog::gConvRatio[o]
					/ float((Catalog::gAreaCells[o] > 0) ? Catalog::gAreaCells[o] : 1);
			if (pc <= mine)
				continue;
			denser = true;
			if (pc > bestPc) {
				bestPc = pc;
				best = o;
			}
		}
		if (denser)
			denserDef.insertLast(di);
	}
	if (best < 0)
		return false;
	const float horizon = ai.GetTunable("apex_army_fill_s", TUNE_ARMY_FILL_S);
	const float h = (horizon > 1.f) ? horizon : 180.f;
	// ...AND THOSE HANDS MUST BE FREE TO. Nominal build power read one T2
	// con raising a fusion as able to convert the whole surplus, so every T1
	// hand refused the basic and nobody converted (apexearth 2026-09-14:
	// "all our T2 was too busy to make any T1 converters so we still should
	// have made T1 converters"). A hand counts when its current job is done
	// within half the window.
	for (uint i = 0; i < gWorkers.length(); ++i) {
		CCircuitUnit@ u = gWorkers[i];
		if (u is null)
			continue;
		const int ud = int(u.circuitDef.id);
		if (denserDef.find(ud) < 0)
			continue;
		if (HandFreeWithin(u, 0.5f * h))
			bp += Catalog::gBuildPower[ud];
	}
	if (bp <= 0.f)
		return false;
	const float n = ConvertibleE() / Catalog::gConvCapacity[best];
	return n * Catalog::gBuildTime[best] / bp <= h;
}

// Is this hand's current job over within `secs`? Idle is free; a guard or a
// patrol is not (it is someone else's job); a build is judged by what is
// left of it at the lathe on it.
bool HandFreeWithin(CCircuitUnit@ u, float secs)
{
	if (u.task is null)
		return true;
	if (u.task.GetType() != Task::Type::BUILDER)
		return false;
	const int bt = int(u.task.GetBuildType());
	if ((bt == int(Task::BuildType::GUARD)) || (bt == int(Task::BuildType::PATROL)))
		return false;
	if (u.task.buildDef is null)
		return false;
	const int bd = int(u.task.buildDef.id);
	float lathe = Catalog::gBuildPower[int(u.circuitDef.id)];
	if (u.task.target !is null) {
		uint arrived = 0;
		const float on = Requests::ArrivedLathe(u.task, arrived);
		if (on > lathe)
			lathe = on;
	}
	if (lathe <= 0.f)
		return false;
	const float left = Catalog::gBuildTime[bd] * (1.f - Requests::Progress(u.task));
	return left / lathe <= secs;
}

bool ConvObsoleteFor(CCircuitUnit@ unit, int d)
{
	if (!ConvObsoleteOnArrival(d))
		return false;
	if (unit is null)
		return true;
	// Both sides are zero before there is any spare energy OR any denser
	// converter, and "0 covers 0" refused the basic for the whole opening:
	// 700 basic converters became 379 and metal produced halved.
	const float denser = DenserConvCapE(d);
	if ((denser > 0.f) && (denser >= ConvTotalE()))
		return true;   // the denser fleet covers it all: no hand builds the basic
	if (DenserHandsCover(d))
		return true;
	const float mine = Catalog::gConvCapacity[d]
			/ float((Catalog::gAreaCells[d] > 0) ? Catalog::gAreaCells[d] : 1);
	const array<int>@ b = Catalog::BuildsOf(int(unit.circuitDef.id));
	for (uint i = 0; i < b.length(); ++i) {
		const int o = b[i];
		if ((o == d) || !Catalog::gAvailable[o] || Catalog::gMobile[o]
			|| (Catalog::gConvCapacity[o] <= 0.f))
			continue;
		const float oc = Catalog::gConvCapacity[o]
				/ float((Catalog::gAreaCells[o] > 0) ? Catalog::gAreaCells[o] : 1);
		if (oc > mine)
			return true;   // this hand can make a denser one: take that instead
	}
	return false;
}

bool ConvObsoleteOnArrival(int d)
{
	RefreshBestCells();
	const float mc = Catalog::gConvCapacity[d]
			/ float((Catalog::gAreaCells[d] > 0) ? Catalog::gAreaCells[d] : 1);
	return (mc > 0.f) && (gBestMcell
			>= ai.GetTunable("apex_obsolete_ratio", TUNE_OBSOLETE_RATIO) * mc);
}

// GROUND HANDS EAT WHAT THEY CAN REACH (apexearth 2026-08-28: "we build so
// tightly packed that oftentimes the buildings we want to reclaim aren't
// accessible by ground units so we need to get the ones which are closer"):
// a victim a ground con's movetype cannot stand at quarter-prices, so the
// accessible ring wins the election; flyers see no walls.
float ReachVictimMul(CCircuitUnit@ unit, const AIFloat3& in at)
{
	const int uid = int(unit.circuitDef.id);
	if (Catalog::gFlyer[uid])
		return 1.f;
	return ai.CanDefReach(Catalog::Def(uid), at, at) ? 1.f : 0.25f;
}

Grid::Cells gDefGrid;
int  gDefGridStamp = -1;
uint gDefGridN = 0;
float gDefGridMaxR = 400.f;
void DefGridBuild()
{
	if ((gDefGridStamp == gOwnStamp) && (gDefGridN == gProtPos[PROT_DEF].length()))
		return;
	gDefGridStamp = gOwnStamp;
	gDefGridN = gProtPos[PROT_DEF].length();
	gDefGrid.Begin(256.f, 0.f, 0.f, float(AiTerrainWidth()), float(AiTerrainHeight()));
	gDefGridMaxR = 400.f;
	for (uint i = 0; i < gDefGridN; ++i) {
		gDefGrid.Add(gProtPos[PROT_DEF][i].x, gProtPos[PROT_DEF][i].z);
		const int d2 = gProtDefId[PROT_DEF][i];
		if (Catalog::ValidId(d2) && (Catalog::gMaxRange[d2] > gDefGridMaxR))
			gDefGridMaxR = Catalog::gMaxRange[d2];
	}
}

int gNextReclObsLog = 0;

Want@ ProposeReclaimObsolete(CCircuitUnit@ unit)
{
	Want w;
	// SURPLUS CONS (apexearth: "made too many t1 cons... we should reclaim
	// them"): the quiet rear with no claimable safe ground and no BP deficit
	// turns constructor metal back into ladder money. Only a con a standing
	// factory could re-make (never the commander), cheapest first; BPGap
	// turning positive stops the next one -- self-balancing....and only once
	// the SUCCESSOR fleet exists: reclaiming the claim fleet before any
	// ceiling con stands starved the ladder that was supposed to replace it.
	// Same law as generator reclaim -- obsolescence is RELATIVE efficiency,
	// and nothing is obsolete before its better.
	if (EcoQuiet() && !gMexOpen && (BPGap() <= 0.f) && (ServingCons() > 0)) {
		// Only a LESSER con spends its time on this: a ceiling con
		// reclaiming T1s traded scaling time for tidying (watched --
		// "T2 cons immediately try reclaiming T1 cons").
		bool lesser = true;
		{
			const array<int>@ mine0 = Catalog::BuildsOf(int(unit.circuitDef.id));
			for (uint mi = 0; mi < mine0.length(); ++mi) {
				if (Catalog::gExtractsM[mine0[mi]] >= BestExtract()) {
					lesser = false;
					break;
				}
			}
		}
		CCircuitUnit@ rc = null;
		int rcDef = -1;
		int landCons = 0;
		// WHAT OUR LINES CAN RE-MAKE, ASKED ONCE. The test below is a property
		// of the con's DEF, not of the con, and it was re-derived per worker:
		// workers x factories x buildoptions of string-free but real array work
		// every election. One pass over the lines answers it for all of them.
		array<bool> remakeable(uint(Catalog::gDefCount + 1), false);
		for (uint fi0 = 0; lesser && (fi0 < Factory::gFacUnits.length()); ++fi0) {
			if (Factory::gFacUnits[fi0] is null)
				continue;
			const array<int>@ fb0 = Catalog::BuildsOf(
					int(Factory::gFacUnits[fi0].circuitDef.id));
			for (uint q0 = 0; q0 < fb0.length(); ++q0) {
				const int fd0 = fb0[q0];
				if ((fd0 >= 0) && (fd0 <= Catalog::gDefCount))
					remakeable[uint(fd0)] = true;
			}
		}
		const int reclaimAgeF = int(ai.GetTunable("apex_reclaim_age_s",
				TUNE_RECLAIM_AGE_S)) * SECOND;
		for (uint wi = 0; lesser && (wi < gWorkers.length()); ++wi) {
			CCircuitUnit@ wu = gWorkers[wi];
			if ((wu is null) || (wu is unit))
				continue;
			const int wd = int(wu.circuitDef.id);
			// Air cons are exempt: no pathing cost, no placement blocking
			// (apexearth) -- and land cons below the keep-floor stay for
			// nano work. A JUST-BUILT con is never eaten: reclaiming what
			// we paid buildtime for minutes ago is churn, not tidying.
			if (Catalog::gFlyer[wd])
				continue;
			if (ReclaimClaimed(wu.id, unit.id))
				continue;
			if ((wi < gWorkerBorn.length())
				&& (ai.frame - gWorkerBorn[wi] < reclaimAgeF))
				continue;
			if ((wd < 0) || (wd > Catalog::gDefCount) || !remakeable[uint(wd)])
				continue;
			++landCons;
			if ((rcDef < 0) || (Catalog::gCostM[wd] < Catalog::gCostM[rcDef])) {
				@rc = wu;
				rcDef = wd;
			}
		}
		if ((rc !is null)
			&& (float(landCons) > ai.GetTunable("apex_eco_con_keep", TUNE_ECO_CON_KEEP))) {
			const float hz0 = ai.GetTunable("apex_reclaim_amort", TUNE_RECLAIM_AMORT);
			w.kind = WK_RECLAIM;
			@w.def = Catalog::Def(rcDef);
			w.pos = rc.GetPos(ai.frame);
			w.spotId = int(rc.id);
			w.gain = Catalog::gCostM[rcDef] / ((hz0 > 1.f) ? hz0 : 300.f);
			w.mCost = 1.f;
			w.tCost = (Catalog::gCostM[rcDef] / 90.f) * Wage();
			w.value = w.gain / (w.mCost + w.tCost);
			{
				const float hm = ReclaimHandMul(unit);
				w.gain *= hm;
				w.value *= hm;
			}
			@w.target = rc;
			w.retire = true;
			return w;
		}
	}
	// Obsolescence is RELATIVE efficiency: for generators the metric is E per
	// CELL of ground (measured from the defs -- solar 0.80, advsol 4.69,
	// fusion 33.3, AFUS 83.3, so the rungs are 5.9x, 7.1x and 2.5x;
	// apexearth: "eventually we need physical space"). For defences it is the
	// def's power under a far stronger neighbor's umbrella.
	//
	// The bank band that used to stand here (0.3-0.85 of storage, for "room
	// for the refund burst") gated on a FRACTION, and storage differs per
	// player -- measured 1300 against 4425 between two teams of one game, so
	// the same absolute headroom read "full" for one and "broke" for the
	// other. Both sat outside the band permanently, at 0.15 and 0.98, so this
	// want never evaluated once and mReclaim was 0. The refund's own worth is
	// already priced below (gain minus the generation given up), and the
	// energy-surplus test guards the stall the floor was reaching for.
	const float ratio = ai.GetTunable("apex_obsolete_ratio", TUNE_OBSOLETE_RATIO);
	const float hzR = ai.GetTunable("apex_reclaim_amort", TUNE_RECLAIM_AMORT);
	const float hz = (hzR > 1.f) ? hzR : 300.f;
	// The generation given up is priced as the buy side prices it -- at the
	// spot price, not the converter floor -- and NOTHING that makes energy is
	// eaten while what we PULL exceeds what we make (a team once ate five of
	// its own solars for room at 700 e/s flat and stalled for ten minutes).
	// The pull as it stands, not the fleet's potential ask: the buy side's
	// deficit carries that ask so a generator ladder never rests, which read
	// "short" in every healthy economy and retired nothing, ever.
	const float ePM = EPrice();
	// Converters are the elastic sink (see eFree below): they pull whatever
	// is spare, so pull with them in reads ~income by construction.
	const bool eShort = (aiEconomyMgr.energy.pull - ConvUseE())
			* ai.GetTunable("apex_e_headroom", TUNE_E_HEADROOM)
			> aiEconomyMgr.energy.income;
	const float wageR = Wage();
	// Converters are an elastic sink, not demand -- they are sized against
	// income by construction, so counting their chew as pull makes a
	// structural surplus read as fully spent while excess energy piles up.
	const float eFree = aiEconomyMgr.energy.income
			- (aiEconomyMgr.energy.pull - ConvUseE());
	CCircuitUnit@ best = null;
	int bestDef = -1;
	float bestValue = 0.f;
	// Generators, best-priced retirement first, only when dwarfed by the best.
	float ownBestEcell = 0.f;
	for (uint i = 0; i < gOwnGen.length(); ++i) {
		if (gOwnGen[i] is null)
			continue;
		const int d = int(gOwnGen[i].circuitDef.id);
		const float ec = Catalog::gMakeE[d]
				/ float((Catalog::gAreaCells[d] > 0) ? Catalog::gAreaCells[d] : 1);
		if (ec > ownBestEcell)
			ownBestEcell = ec;
	}
	int nGen = 0, nGenDwarf = 0, nGenFree = 0, nGenPriced = 0;
	int nConv = 0, nConvDwarf = 0, nConvDenser = 0, nConvPriced = 0;
	float bestGenV = 0.f, bestConvV = 0.f;
	int bestGenDef = -1, bestConvDef = -1;
	for (uint i = 0; i < gOwnGen.length(); ++i) {
		CCircuitUnit@ g = gOwnGen[i];
		if (g is null)
			continue;
		if (ReclaimClaimed(g.id, unit.id))
			continue;
		const int d = int(g.circuitDef.id);
		++nGen;
		const float ec = Catalog::gMakeE[d]
				/ float((Catalog::gAreaCells[d] > 0) ? Catalog::gAreaCells[d] : 1);
		if (ownBestEcell < ratio * ec)
			continue;   // not dwarfed: still pulling its weight per cell
		++nGenDwarf;
		// Removing it must LEAVE a surplus -- reclaim never causes a stall.
		// The margin is a share of the CANDIDATE'S own output, not of income:
		// scaled to income it grew with the economy, so the bigger we got the
		// less we could retire.
		if (eShort || (eFree - Catalog::gMakeE[d] <= 0.1f * Catalog::gMakeE[d]))
			continue;
		++nGenFree;
		// PRICED, not ranked by E-per-cell. An argmin on that metric puts the
		// worst generator we own permanently in front: a solar reads 0.80 and
		// an advanced solar 4.69, so while one T1 panel stands the advanced
		// solar can never even be the candidate.
		const float v = RetireValue(unit, g, d, ePM, wageR, hz)
				* ReachVictimMul(unit, g.GetPos(ai.frame));
		if (v > 0.f)
			++nGenPriced;
		if (v > bestGenV) {
			bestGenV = v;
			bestGenDef = d;
		}
		if (v > bestValue) {
			bestValue = v;
			@best = g;
			bestDef = d;
		}
	}
	// Converters, on the SAME LAW as generators: output per cell of ground,
	// against the best converter we own. A T1 converter beside a T2 one is
	// paying rent on ground its successor uses far better -- and the ground is
	// the point (apexearth 2026-08-27: "we have wind, advanced solar, and T1
	// converters all over the place not being reclaimed. That's a huge issue,
	// we have no space"). Removing one must leave the metal it was making
	// affordable to lose, which is what its own gain term already prices.
	float ownBestMcell = 0.f;
	for (uint i = 0; i < gOwnConv.length(); ++i) {
		if (gOwnConv[i] is null)
			continue;
		const int d = int(gOwnConv[i].circuitDef.id);
		const float mc = Catalog::gConvCapacity[d]
				/ float((Catalog::gAreaCells[d] > 0) ? Catalog::gAreaCells[d] : 1);
		if (mc > ownBestMcell)
			ownBestMcell = mc;
	}
	for (uint i = 0; i < gOwnConv.length(); ++i) {
		CCircuitUnit@ cv = gOwnConv[i];
		if (cv is null)
			continue;
		if (ReclaimClaimed(cv.id, unit.id))
			continue;
		const int d = int(cv.circuitDef.id);
		const float mc = Catalog::gConvCapacity[d]
				/ float((Catalog::gAreaCells[d] > 0) ? Catalog::gAreaCells[d] : 1);
		if (mc <= 0.f)
			continue;
		++nConv;
		if (ownBestMcell < ratio * mc)
			continue;   // not dwarfed: still earning its cells
		++nConvDwarf;
		// The denser fleet STANDING carries the load actually being converted
		// plus this one's. Not every joule that could be (waste included) --
		// no fleet ever covered that; not ordered ones -- they arrive minutes
		// after the basic is eaten; not the hands test -- it flips as basics
		// are eaten and rebuilt, and fed a churn.
		if (DenserConvStandingE(d) < ConvUseE() + Catalog::gConvCapacity[d])
			continue;
		++nConvDenser;
		const float v = RetireValue(unit, cv, d, ePM, wageR, hz)
				* ReachVictimMul(unit, cv.GetPos(ai.frame));
		if (v > 0.f)
			++nConvPriced;
		if (v > bestConvV) {
			bestConvV = v;
			bestConvDef = d;
		}
		if (v > bestValue) {
			bestValue = v;
			@best = cv;
			bestDef = d;
		}
	}
	// Where the obsolete-eco retirement dies, once a minute (apexearth
	// 2026-09-12: "we aren't reclaiming obsolete eco so we pretty easily run
	// out of room").
	if (ai.frame >= gNextReclObsLog) {
		gNextReclObsLog = ai.frame + 60 * SECOND;
		AiLog(Factory::T() + "apex: reclobs t=" + ai.teamId
			+ " gen=" + nGen + "/" + nGenDwarf + "/" + nGenFree + "/" + nGenPriced
			+ " best=" + ((bestGenDef >= 0) ? Catalog::Def(bestGenDef).GetName() : "-")
			+ ":" + formatFloat(bestGenV * 1000.f, "", 0, 2)
			+ " conv=" + nConv + "/" + nConvDwarf + "/" + nConvDenser + "/" + nConvPriced
			+ " best=" + ((bestConvDef >= 0) ? Catalog::Def(bestConvDef).GetName() : "-")
			+ ":" + formatFloat(bestConvV * 1000.f, "", 0, 2)
			+ " eFree=" + int(eFree) + " eShort=" + (eShort ? 1 : 0)
			+ " ePM=" + formatFloat(ePM, "", 0, 4)
			+ " crowd=" + formatFloat(PfCrowd(), "", 0, 2)
			+ " mpc=" + formatFloat(PfMetalPerCell(), "", 0, 2)
			+ " hz=" + int(hz) + " ratio=" + formatFloat(ratio, "", 0, 1)
			+ " bestEcell=" + formatFloat(ownBestEcell, "", 0, 2)
			+ " bestMcell=" + formatFloat(ownBestMcell, "", 0, 2));
	}
	// Defences: dominated by a much stronger one covering the same ground.
	// Neighbours from a grid, not every tower against every other: the
	// pairwise walk was turrets^2 distance tests per election.
	DefGridBuild();
	for (uint i = 0; i < gProtUnit[PROT_DEF].length(); ++i) {
		CCircuitUnit@ g = gProtUnit[PROT_DEF][i];
		if (g is null)
			continue;
		if (ReclaimClaimed(g.id, unit.id))
			continue;
		const int d = gProtDefId[PROT_DEF][i];
		bool dominated = false;
		gDefGrid.Query(gProtPos[PROT_DEF][i].x, gProtPos[PROT_DEF][i].z, gDefGridMaxR);
		for (uint q = 0; q < gDefGrid.hit.length(); ++q) {
			const uint j = uint(gDefGrid.hit[q]);
			if ((i == j) || (j >= gProtDefId[PROT_DEF].length()))
				continue;
			const int d2 = gProtDefId[PROT_DEF][j];
			// COVERS THE SAME GROUND, in the BETTER tower's own reach rather
			// than a flat 400 elmos. apexearth 2026-08-27: reclaim the lesser
			// defence "only where a better one already stands". A T2 gun
			// out-ranges a T1 tower by more than 400, so the successor was
			// standing over ground the flat radius said it did not cover and
			// the T1 underneath it never retired.
			if (Catalog::Def(d2) is null)
				continue;
			const float reach2 = (Catalog::gMaxRange[d2] > 400.f)
					? Catalog::gMaxRange[d2] : 400.f;
			if ((Catalog::Def(d2).power >= ratio * Catalog::Def(d).power)
				&& (gProtPos[PROT_DEF][i].distance2D(gProtPos[PROT_DEF][j]) < reach2))
			{
				dominated = true;
				break;
			}
		}
		// ...or the PERIMETER HAS GROWN PAST IT. apexearth: "as our base grows,
		// reclaim old defenses as needed and extend defense outwards." The
		// defence sites are already chosen on the rim of what we own -- the
		// measured problem is that the base then grows around them, so a tower
		// sited on the edge ends up 150-300 elmos inside it and is guarding
		// ground that is now interior. Retiring it is what funds the post at
		// the new edge; the auction picks that site on its own.
		//
		// "Whenever the rim has moved past it" is his ruling (2026-08-27), so
		// there is no still-covers-something clause. Depth is measured in the
		// tower's OWN reach, so a long gun has to be far deeper in than a
		// light one before it counts as stranded, and it is a share of the
		// rim as well so it means the same thing on a small base and a large.
		bool stranded = false;
		// WALL MODE: the tower retires when its fire can no longer even REACH
		// the wall on its own bearing -- it contributes nothing to the
		// perimeter fight, which is the whole of a wall tower's job
		// (apexearth 2026-08-30: "older towers in the back can eventually be
		// reclaimed as we push outwards"). No stake gate: the replacement is
		// a wall slot by construction, so the reclaim-then-resite-DEEPER loop
		// that gate was built against cannot recur here.
		if (!dominated && (ai.GetTunable("apex_wall", TUNE_WALL) > 0.f)) {
			if (WallStands()) {
				const float rrW = (Catalog::gMaxRange[d] > 1.f)
						? Catalog::gMaxRange[d] : 500.f;
				// A quantum of margin: the wall steps outward in WALL_QUANT
				// increments, and one ordinary step must not retire a tower
				// finished on the previous line. And the new line must be
				// STANDING first (WallAheadHeld) -- without that the wall's
				// own growth put the guns on a build-reclaim treadmill.
				stranded = (WallRimDist(gProtPos[PROT_DEF][i])
						< -(rrW + WALL_QUANT))
					&& WallAheadHeld(gProtPos[PROT_DEF][i]);
			}
		} else if (!dominated && gPfRimOk) {
			const AIFloat3 tp = gProtPos[PROT_DEF][i];
			const float rimHere = PfRimAt(tp);
			const float deep = -PfRimDist(tp);
			const float rr = (Catalog::gMaxRange[d] > 1.f)
					? Catalog::gMaxRange[d] : 500.f;
			// ...AND IT MUST BE GUARDING NOTHING. A heavy gun is the most
			// attractive candidate here by construction -- the refund rises
			// with cost -- so an interior test on its own retires the base's
			// main weapon and the auction re-sites it wherever it next scores,
			// which can be deeper in than it started (apexearth: "just saw us
			// reclaim a doomsday gun and then make one further behind in our
			// base"). Measured over two 60-minute games: 1,694 and 1,645
			// decisions to reclaim a cordoom.
			//
			// A cover-versus-threat test does NOT catch this: threat in a quiet
			// interior reads ~0, so removing the gun trivially "leaves the
			// ground covered". The honest question is whether the turret is
			// doing work, and the measure of that is the metal standing inside
			// its reach. Compared against its own price, so nothing is chosen:
			// a turret guarding less than it is worth is not paying for
			// itself; one standing over the base is, wherever the rim has got
			// to.
			stranded = (rimHere > rr) && (deep > rr)
					&& (PfStakeAt(tp, rr) <= Catalog::gCostM[d]);
		}
		if (!dominated && !stranded)
			continue;
		const float v = RetireValue(unit, g, d, ePM, wageR, hz);
		if (v > bestValue) {
			bestValue = v;
			@best = g;
			bestDef = d;
		}
	}
	// GROUND LABS RETIRE FOR THE QUIET REAR once an owned AIR lab fields
	// flying cons of equal reach (apexearth: "reclaim the T1 and T2 labs,
	// go for T1 and T2 air labs... then make the huge T3"). Successor-first,
	// same law as everything else here: nothing is obsolete before its
	// better is standing.
	//
	// DANGER, not the eco ROLE. EcoQuiet() is EcoRoleActive() && !EcoDangerNear(),
	// so a superseded lab could only ever be retired by whichever player held
	// the eco role -- a role deciding WHETHER rather than how often.
	if (!EcoDangerNear()) {
		for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
			CCircuitUnit@ f = Factory::gFacUnits[fi];
			if (f is null)
				continue;
			if (ReclaimClaimed(f.id, unit.id))
				continue;
			const int fd = int(f.circuitDef.id);
			float fReach = 0.f;
			bool fFlies = false;
			const array<int>@ fp = Catalog::gBuildsList[fd];
			for (uint q = 0; q < fp.length(); ++q) {
				if (!Catalog::gMobile[fp[q]] || !Catalog::gBuilder[fp[q]])
					continue;
				if (Catalog::gFlyer[fp[q]])
					fFlies = true;
				const array<int>@ fpb = Catalog::gBuildsList[fp[q]];
				for (uint r = 0; r < fpb.length(); ++r) {
					if (Catalog::gExtractsM[fpb[r]] > fReach)
						fReach = Catalog::gExtractsM[fpb[r]];
				}
			}
			if (fFlies)
				continue;   // air labs are the successors, never the retired
			// A plant that fields no mex-capable constructor reads fReach=0,
			// and zero is "superseded" by ANY air lab below -- which is how a
			// GANTRY became this law's victim (apexearth, watching: "Someone
			// in this game I'm watching is reclaiming our Gantry. That is a
			// silly thing to do" -- 7 reclaim-rebuild loops in one game).
			// Constructor reach is this law's whole jurisdiction; a plant
			// outside it is never retired by it.
			if (fReach <= 0.f)
				continue;
			bool succeeded = false;
			// A strictly deeper-reaching plant, standing OR under
			// construction, retires this one (apexearth: "reclaiming the
			// T1 lab while building the T2 lab").
			for (uint gi2 = 0; gi2 < Factory::gFacUnits.length() && !succeeded; ++gi2) {
				CCircuitUnit@ g3 = Factory::gFacUnits[gi2];
				if ((g3 is null) || (g3 is f))
					continue;
				float g3Reach = 0.f;
				const array<int>@ g3p = Catalog::gBuildsList[int(g3.circuitDef.id)];
				for (uint q3 = 0; q3 < g3p.length(); ++q3) {
					if (!Catalog::gMobile[g3p[q3]] || !Catalog::gBuilder[g3p[q3]])
						continue;
					const array<int>@ g3b = Catalog::gBuildsList[g3p[q3]];
					for (uint r3 = 0; r3 < g3b.length(); ++r3) {
						if (Catalog::gExtractsM[g3b[r3]] > g3Reach)
							g3Reach = Catalog::gExtractsM[g3b[r3]];
					}
				}
				if (g3Reach > fReach)
					succeeded = true;
			}
			for (uint gi = 0; gi < Factory::gFacUnits.length() && !succeeded; ++gi) {
				CCircuitUnit@ g2 = Factory::gFacUnits[gi];
				if ((g2 is null) || (g2 is f))
					continue;
				const array<int>@ gp = Catalog::gBuildsList[int(g2.circuitDef.id)];
				for (uint q2 = 0; q2 < gp.length(); ++q2) {
					if (!Catalog::gMobile[gp[q2]] || !Catalog::gBuilder[gp[q2]]
						|| !Catalog::gFlyer[gp[q2]])
						continue;
					float gReach = 0.f;
					const array<int>@ gpb = Catalog::gBuildsList[gp[q2]];
					for (uint r2 = 0; r2 < gpb.length(); ++r2) {
						if (Catalog::gExtractsM[gpb[r2]] > gReach)
							gReach = Catalog::gExtractsM[gpb[r2]];
					}
					if (gReach >= fReach) {
						succeeded = true;
						break;
					}
				}
			}
			// ...AND NOTHING IS LOST WITH IT. Reach compares CONSTRUCTORS, which
			// says nothing about what else a plant makes: a T2 or air plant
			// does not build the Rascal (corfav, T1 vehicle plant only), so
			// retiring on reach alone threw the faction's best spam unit away
			// with the building. apexearth 2026-08-27: "we need to keep at
			// least 1 t1 lab so we can make rezbots, spam units... we shouldn't
			// be dropping all of them. Just don't need so many extras."
			//
			// So a plant retires only when the plants that would REMAIN
			// standing build everything it does. That retires duplicates and
			// true supersets -- the extras -- and never the last plant that is
			// the only source of something.
			bool covered = succeeded;
			for (uint pi = 0; covered && (pi < Catalog::gBuildsList[fd].length()); ++pi) {
				const int prod = Catalog::gBuildsList[fd][pi];
				if (!Catalog::gMobile[prod])
					continue;
				bool elsewhere = false;
				for (uint oi = 0; !elsewhere && (oi < Factory::gFacUnits.length()); ++oi) {
					CCircuitUnit@ o = Factory::gFacUnits[oi];
					if ((o is null) || (o is f) || (o.circuitDef is null))
						continue;
					const array<int>@ op = Catalog::gBuildsList[int(o.circuitDef.id)];
					for (uint oq = 0; oq < op.length(); ++oq) {
						if (op[oq] == prod) {
							elsewhere = true;
							break;
						}
					}
				}
				if (!elsewhere)
					covered = false;
			}
			// A COPY BOUGHT FOR OVERFLOW IS KEPT FOR OVERFLOW. The wealth
			// waiver licenses duplicate lines, and this law then read the
			// copy as an extra and ate it -- so the market re-bought it, and
			// the pair cycled all game. A pure duplicate
			// (no deeper successor) retires only in a SQUEEZED economy: bank
			// under half and income not covering pull. A tier successor still
			// retires its predecessor whatever the bank says.
			if (covered && !succeeded) {
				const float st3 = aiEconomyMgr.metal.storage;
				const bool squeezed = (st3 > 1.f)
					&& (aiEconomyMgr.metal.current < 0.5f * st3)
					&& (aiEconomyMgr.metal.income <= aiEconomyMgr.metal.pull);
				if (!squeezed || RecentCopyWaiver(fd))
					covered = false;
			}
			if (covered) {
				const float v = RetireValue(unit, f, fd, ePM, wageR, hz);
				if (v > bestValue) {
					bestValue = v;
					@best = f;
					bestDef = fd;
				}
			}
		}
	}
	if (best is null)
		return w;
	// One-shot metal amortized at the market's payback scale -- 60s priced a
	// single refund like a perpetual stream and it outbid every mex.
	const AIFloat3 gp = best.GetPos(ai.frame);
	const float speed = Catalog::gSpeed[int(unit.circuitDef.id)];
	const float walkSec = (speed > 1.f)
			? (unit.GetPos(ai.frame).distance2D(gp) / speed) : 60.f;
	w.kind = WK_RECLAIM;
	@w.def = Catalog::Def(bestDef);
	w.pos = gp;
	w.spotId = int(best.id);
	w.gain = RetireGain(best, bestDef, ePM, hz);
	w.mCost = 1.f;
	w.tCost = (walkSec + Catalog::gCostM[bestDef] / 90.f) * wageR;
	w.value = bestValue;
	{
		const float hm = ReclaimHandMul(unit);
		w.gain *= hm;
		w.value *= hm;
	}
	@w.target = best;
	w.retire = true;
	return w;
}

// FREE A UNIT OUR OWN BASE HAS SEALED IN. Military::UpdateMoveTests proves the
// pen (motionless, then ordered to walk, then still motionless) and publishes
// the verdict; this prices it. apexearth 2026-08-27: "prevention is good, and
// then reclaim whichever is worth less" -- so the CHOICE between eating the
// wall and eating the trapped unit is made on cost, and only the gain differs:
// eating the wall puts the unit back in service, eating the unit does not.
//
// Terrain-penned units have no wall to blame (gPenWall 0) and are the unit case
// by construction -- a builder's lathe reaches over the lip the unit cannot
// walk over, so the metal comes home either way.
Want@ ProposeReclaimPenned(CCircuitUnit@ unit)
{
	Want w;
	if (ai.GetTunable("apex_unblock", TUNE_UNBLOCK) <= 0.f)
		return w;
	const float hzP = ai.GetTunable("apex_reclaim_amort", TUNE_RECLAIM_AMORT);
	const float hz = (hzP > 1.f) ? hzP : 300.f;
	const float wageP = Wage();
	const float speed = Catalog::gSpeed[int(unit.circuitDef.id)];
	const AIFloat3 here = unit.GetPos(ai.frame);
	float bestValue = 0.f;
	CCircuitUnit@ best = null;
	int bestDef = -1;
	float bestFree = 0.f;
	for (uint i = 0; i < Military::gPenVictim.length(); ++i) {
		CCircuitUnit@ victim = ai.GetTeamUnit(Military::gPenVictim[i]);
		if ((victim is null) || (victim.circuitDef is null))
			continue;
		// The commander may be the PENNED side of the trade -- the wall that
		// is eaten is a structure, never him (WallToEat).
		const int vd = int(victim.circuitDef.id);
		CCircuitUnit@ wall = null;
		int wd = -1;
		if (Military::gPenWall[i] != 0) {
			@wall = ai.GetTeamUnit(Military::gPenWall[i]);
			if ((wall !is null) && (wall.circuitDef !is null))
				wd = int(wall.circuitDef.id);
			else
				continue;   // the wall is already gone: the hole is walked, not the victim eaten
		}
		// WHICHEVER IS WORTH LESS. The unit is the only candidate when nothing
		// of ours is to blame, and the wall is never chosen when it costs more
		// than the unit it is trapping.
		CCircuitUnit@ eat = victim;
		int eatDef = vd;
		float freed = 0.f;   // metal put back in service by clearing the wall
		const bool comm = victim.circuitDef.IsRoleAny(Unit::Role::COMM.mask);
		if ((wall !is null) && (comm || (Catalog::gCostM[wd] < Catalog::gCostM[vd]))) {
			@eat = wall;
			eatDef = wd;
			freed = Catalog::gCostM[vd];
		} else if (comm) {
			continue;
		}
		const AIFloat3 ep = eat.GetPos(ai.frame);
		if (!OnMap(ep))
			continue;
		// Metal back plus, when the wall goes, the unit that starts working
		// again -- both one-shot, so both amortized the same way every other
		// reclaim here is.
		const float gain = (Catalog::gCostM[eatDef] + freed) / hz;
		if (gain <= 0.f)
			continue;
		const float walkSec = (speed > 1.f) ? (here.distance2D(ep) / speed) : 60.f;
		const float v = gain
				/ (1.f + (walkSec + Catalog::gCostM[eatDef] / 90.f) * wageP);
		if (v > bestValue) {
			bestValue = v;
			@best = eat;
			bestDef = eatDef;
			bestFree = freed;
		}
	}
	if (best is null)
		return w;
	const AIFloat3 bp = best.GetPos(ai.frame);
	const float walkSec = (speed > 1.f) ? (here.distance2D(bp) / speed) : 60.f;
	w.kind = WK_RECLAIM;
	@w.def = Catalog::Def(bestDef);
	w.pos = bp;
	w.spotId = int(best.id);
	w.gain = (Catalog::gCostM[bestDef] + bestFree) / hz;
	w.mCost = 1.f;
	w.tCost = (walkSec + Catalog::gCostM[bestDef] / 90.f) * wageP;
	w.value = bestValue;
	{
		const float hm = ReclaimHandMul(unit);
		w.gain *= hm;
		w.value *= hm;
	}
	@w.target = best;
	return w;
}

// RECLAIM WHAT IS STANDING IN THE SLOT. C++ records a lattice slot it could
// not place on (CCircuitAI::NoteBuildBlocked); this is the only thing that
// reads it. apexearth: "if we want to complete/extend a grid we should reclaim
// whatever building(s) are in the way so long as they are not much more
// valuable in comparison to the building we want to place."
//
// "Much more valuable" is not a ratio here -- it is the arithmetic. The ground
// is worth what the BEST generator we own would make on it instead of what is
// standing there, and clearing it costs that building's own output plus the
// time. A fusion blocking a wind slot prices itself out on the first term; a
// stray T1 solar does not.
Want@ ProposeReclaimBlocker(CCircuitUnit@ unit)
{
	Want w;
	if (ai.GetTunable("apex_reclaim_blocker", TUNE_RECLAIM_BLOCKER) < 0.5f)
		return w;
	AIFloat3 bp;
	if (!ai.GetBlockedBuildPos(bp) || !OnMap(bp))
		return w;
	// Best energy per cell we can actually build, and the eco structure of ours
	// nearest the blocked slot. Only ECONOMY is a candidate: extractors and
	// geothermals stand on ground they had to have, plants are the room the
	// lattice exists to protect, and towers and sensors were sited to cover
	// something rather than to sit in a row.
	float bestEcell = 0.f;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!Catalog::gAvailable[d] || Catalog::gMobile[d] || Catalog::gNeedGeo[d])
			continue;
		const int cells = (Catalog::gAreaCells[d] > 0) ? Catalog::gAreaCells[d] : 1;
		const float ec = Catalog::gMakeE[d] / float(cells);
		if (ec > bestEcell)
			bestEcell = ec;
	}
	CCircuitUnit@ blk = null;
	int blkDef = -1;
	float nearest = 1e9f;
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		const int di = int(d);
		if ((gOwnCount[d] <= 0) || Catalog::gMobile[di] || Catalog::gNeedGeo[di])
			continue;
		if ((Catalog::gExtractsM[di] > 0.f)
			|| (Catalog::gBuildsList[di].length() > 0))
			continue;
		if ((Catalog::gMakeE[di] < 1.f) && (Catalog::gConvCapacity[di] < 1.f)
			&& (Catalog::gStoreE[di] < 1.f) && (Catalog::gStoreM[di] < 1.f))
			continue;
		array<CCircuitUnit@>@ us = ai.GetOwnUnitsOfDef(Catalog::Def(di), bp,
				BLOCKER_REACH);
		if (us is null)
			continue;
		for (uint i = 0; i < us.length(); ++i) {
			if (us[i] is null)
				continue;
			const float dd = us[i].GetPos(ai.frame).distance2D(bp);
			if (dd < nearest) {
				nearest = dd;
				@blk = us[i];
				blkDef = di;
			}
		}
	}
	if (blk is null)
		return w;
	const int cells = (Catalog::gAreaCells[blkDef] > 0)
			? Catalog::gAreaCells[blkDef] : 1;
	const float ecell = Catalog::gMakeE[blkDef] / float(cells);
	const float horizon = ai.GetTunable("apex_reclaim_amort", TUNE_RECLAIM_AMORT);
	const AIFloat3 gp = blk.GetPos(ai.frame);
	const float speed = Catalog::gSpeed[int(unit.circuitDef.id)];
	const float walkSec = (speed > 1.f)
			? (unit.GetPos(ai.frame).distance2D(gp) / speed) : 60.f;
	w.kind = WK_RECLAIM;
	@w.def = Catalog::Def(blkDef);
	w.pos = gp;
	w.spotId = int(blk.id);
	// The metal back, plus the energy the ground would make once cleared minus
	// what it makes now. Both terms are zero or negative for anything already
	// pulling its weight, so this want simply never wins for those.
	w.gain = Catalog::gCostM[blkDef] / ((horizon > 1.f) ? horizon : 300.f)
			+ (bestEcell - ecell) * float(cells) * EPriceFloor();
	w.mCost = 1.f;
	w.tCost = (walkSec + Catalog::gCostM[blkDef] / 90.f) * Wage();
	w.value = (w.gain > 0.f) ? (w.gain / (w.mCost + w.tCost)) : 0.f;
	{
		const float hm = ReclaimHandMul(unit);
		w.gain *= hm;
		w.value *= hm;
	}
	@w.target = blk;
	return w;
}


}  // namespace Market
