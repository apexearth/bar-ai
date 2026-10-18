namespace Requests {

// ONE TEST FOR A HAND SENT INTO WORK ALREADY UNDER WAY (TUNE_JOIN_ARRIVE; his
// 2026-10-16: nothing is fed in one at a time where it arrives too late to help,
// "fix them all through the same rule"). The hand's clock starts when it gets
// there: the work left at its arrival, with the hands already on it, is what it
// can shorten. Every join, assist, guard, rescue, gift and lift path asks here;
// tools/check.py holds the call sites to it.

const int JA_DEFJOIN = 0;
const int JA_UNLOCK = 1;
const int JA_ASSIST = 2;
const int JA_FLOOR = 3;
const int JA_BIG = 4;
const int JA_REZ = 5;
const int JA_GIFT = 6;
const int JA_LIFT = 7;
const int JA_SITE = 8;
const int JA_N = 9;
const int JA_WHY_LATE = 0;
const int JA_WHY_FULL = 1;
const int JA_WHY_COST = 2;
const int JA_WHY_TAKEN = 3;

bool gJaOnSet = false;
bool gJaOnV = false;
bool JoinArriveOn()
{
	if (!gJaOnSet) {
		gJaOnSet = true;
		gJaOnV = ai.GetTunable("apex_join_arrive", TUNE_JOIN_ARRIVE) > 0.f;
	}
	return gJaOnV;
}

string JaPathName(int p)
{
	if (p == JA_DEFJOIN) return "defjoin";
	if (p == JA_UNLOCK) return "unlock";
	if (p == JA_ASSIST) return "assist";
	if (p == JA_FLOOR) return "floor";
	if (p == JA_BIG) return "big";
	if (p == JA_REZ) return "rez";
	if (p == JA_GIFT) return "gift";
	if (p == JA_LIFT) return "lift";
	if (p == JA_SITE) return "site";
	return "?";
}

array<int> gJaAsked(JA_N, 0);
array<int> gJaRefLate(JA_N, 0);
array<int> gJaRefFull(JA_N, 0);
array<int> gJaRefCost(JA_N, 0);
array<int> gJaRefTaken(JA_N, 0);
array<int> gJaTaken(JA_N, 0);
array<int> gJaLate(JA_N, 0);
array<int> gJaOnTime(JA_N, 0);
array<int> gJaUsefulN(JA_N, 0);
array<float> gJaUsefulS(JA_N, 0.f);

// What the last evaluation found, for the callers that price the join.
float gJaArrive = 0.f;
float gJaSaved = 0.f;
float gJaOcc = 0.f;
float gJaRisk = 0.f;
float gJaWalkCost = 0.f;

void JoinCountAsk(int path)
{
	if ((path >= 0) && (path < JA_N))
		++gJaAsked[path];
}

void JoinCountRefuse(int path, int why)
{
	if ((path < 0) || (path >= JA_N))
		return;
	if (why == JA_WHY_LATE) ++gJaRefLate[path];
	else if (why == JA_WHY_FULL) ++gJaRefFull[path];
	else if (why == JA_WHY_COST) ++gJaRefCost[path];
	else ++gJaRefTaken[path];
}

float JaHorizon()
{
	const float h = ai.GetTunable("apex_payback_h", TUNE_PAYBACK_H);
	return (h > 1.f) ? h : 900.f;
}

// Straight line over the unit's own speed: ai.GetPathLength desyncs paired
// network games (unblock.as), so the walk is a lower bound and the test errs
// toward letting a hand go.
float JoinArriveSec(CCircuitUnit@ unit, const AIFloat3& in site)
{
	if ((unit is null) || !OnMap(site))
		return 0.f;
	const float v = Catalog::gSpeed[int(unit.circuitDef.id)];
	return unit.GetPos(ai.frame).distance2D(site) / ((v > 1.f) ? v : ASSUMED_CON_SPEED);
}

// Seconds the job lands sooner for one more hand of handBP that starts arriveSec
// from now, the crew's crewBP working on until then. `remain` is in the units of
// BP x seconds. 0 when it lands before the hand gets there. With no crew the job
// stands still until this hand starts it: the horizon left after the walk.
float JoinSavedSec(float remain, float crewBP, float handBP, float arriveSec)
{
	gJaOcc = 0.f;
	if ((remain <= 0.f) || (handBP <= 0.f))
		return 0.f;
	if (crewBP <= 0.f) {
		gJaOcc = remain / handBP;
		const float h = JaHorizon();
		return (arriveSec < h) ? (h - arriveSec) : 0.f;
	}
	const float left = remain - crewBP * arriveSec;
	if (left <= 0.f)
		return 0.f;
	gJaOcc = left / (crewBP + handBP);
	return left * handBP / (crewBP * (crewBP + handBP));
}

// The road's price: none up to the threat a constructor is sent through
// (CON_THREAT_VETO), the whole hand and what its job returns until replaced at
// the hostile reading ThreatFor gives ground past the front or foes in sight.
float JoinTripRisk(CCircuitUnit@ unit, const AIFloat3& in site)
{
	if ((unit is null) || !OnMap(site))
		return 0.f;
	float t = Builder::ThreatFor(unit, site) - Builder::CON_THREAT_VETO;
	if (t <= 0.f)
		return 0.f;
	if (t > 1.f)
		t = 1.f;
	return t * Market::WorkerLossM(unit);
}

// Metal: the job's rate times the seconds it lands sooner for this hand, less
// the trip's risk. A rate unknown is the hand's own wage. 0 when the job lands
// first, the crew is full, or the risk eats it. path < 0 is not counted.
float JoinWorth(int path, CCircuitUnit@ unit, const AIFloat3& in site, float arriveSec,
		float remain, float crewBP, float handBP, float rate, bool full = false)
{
	JoinCountAsk(path);
	gJaArrive = arriveSec;
	gJaSaved = 0.f;
	gJaRisk = 0.f;
	const float wage = (unit !is null) ? Market::WageOf(unit) : Market::Wage();
	gJaWalkCost = wage * arriveSec;
	if (full) {
		gJaOcc = 0.f;
		JoinCountRefuse(path, JA_WHY_FULL);
		return 0.f;
	}
	const float saved = JoinSavedSec(remain, crewBP, handBP, arriveSec);
	if (saved <= 0.f) {
		JoinCountRefuse(path, JA_WHY_LATE);
		return 0.f;
	}
	gJaSaved = saved;
	gJaRisk = JoinTripRisk(unit, site);
	const float worth = ((rate > 0.f) ? rate : wage) * saved - gJaRisk;
	if (worth <= 0.f) {
		JoinCountRefuse(path, JA_WHY_COST);
		return 0.f;
	}
	return worth;
}

// A yes for the callers that only take or leave: worth the walk's own wage.
bool JoinOk(int path, CCircuitUnit@ unit, const AIFloat3& in site, float arriveSec,
		float remain, float crewBP, float handBP, float rate, bool full = false)
{
	const float w = JoinWorth(path, unit, site, arriveSec, remain, crewBP, handBP, rate, full);
	if (w <= 0.f)
		return false;
	if (w <= gJaWalkCost) {
		JoinCountRefuse(path, JA_WHY_COST);
		return false;
	}
	return true;
}

// Every guard of ours on this job: those following its crew and those on its frame.
int JaGuards(IUnitTask@ job)
{
	int n = Market::GuardsOnJob(job);
	if ((job !is null) && (job.target !is null)) {
		const Id fid = job.target.id;
		for (uint g = 0; g < Market::gGuardBId.length(); ++g) {
			if (Market::gGuardBId[g] == fid)
				++n;
		}
	}
	return n;
}

// A live build: what is left of it, the lathe on it by the time this hand gets
// there (hands arrived, walkers nearer, the ring seen lathing it, the guards on
// it at this hand's power), and the ring already clearing it (NanoFed).
float JoinWorthTask(int path, CCircuitUnit@ unit, IUnitTask@ job, float rate,
		bool full = false, float arriveSec = -1.f, float handBP = -1.f)
{
	if ((unit is null) || (job is null) || job.IsDead() || (job.buildDef is null)) {
		JoinCountAsk(path);
		JoinCountRefuse(path, JA_WHY_LATE);
		return 0.f;
	}
	const int bd = int(job.buildDef.id);
	const AIFloat3 site = job.GetBuildPos();
	const int uid = int(unit.circuitDef.id);
	const float dist = OnMap(site) ? unit.GetPos(ai.frame).distance2D(site) : 0.f;
	const float arrive = (arriveSec >= 0.f) ? arriveSec : JoinArriveSec(unit, site);
	const float hand = (handBP > 0.f) ? handBP : Catalog::gBuildPower[uid];
	const float remain = Catalog::ValidId(bd)
			? Catalog::gBuildTime[bd] * (1.f - Progress(job)) : 0.f;
	uint arrived = 0;
	float crew = ArrivedLathe(job, arrived, dist);
	crew += RingSeen(job) + float(JaGuards(job)) * hand;
	const bool fed = NanoFed(job, (Workers(job) > 0) ? Workers(job) : 1, dist,
			Catalog::gSpeed[uid]);
	return JoinWorth(path, unit, site, arrive, remain, crew, hand, rate, full || fed);
}

bool JoinOkTask(int path, CCircuitUnit@ unit, IUnitTask@ job, float rate,
		bool full = false, float arriveSec = -1.f, float handBP = -1.f)
{
	const float w = JoinWorthTask(path, unit, job, rate, full, arriveSec, handBP);
	if (w <= 0.f)
		return false;
	if (w <= gJaWalkCost) {
		JoinCountRefuse(path, JA_WHY_COST);
		return false;
	}
	return true;
}

// An activity with an end rather than a bill -- a corpse that rots, an ally's
// fight: the seconds between this unit's arrival and that end. 0 when it gets
// there too late, or somebody else already has it.
float JoinSlackSec(int path, CCircuitUnit@ unit, const AIFloat3& in site, float endSec,
		bool taken = false)
{
	JoinCountAsk(path);
	gJaArrive = JoinArriveSec(unit, site);
	if (taken) {
		JoinCountRefuse(path, JA_WHY_TAKEN);
		return 0.f;
	}
	const float slack = endSec - gJaArrive;
	if (slack <= 0.f) {
		JoinCountRefuse(path, JA_WHY_LATE);
		return 0.f;
	}
	return slack;
}

// -- did they get there in time ---------------------------------------------
// Every join taken, whichever arm, until the hand reaches the work or the work
// ends first. Late = the job finished before the hand got there.
array<int> gJtUnit;
array<int> gJtPath;
array<IUnitTask@> gJtJob;
array<IUnitTask@> gJtGiven;
array<AIFloat3> gJtSite;
array<float> gJtReach;
array<int> gJtEnd;
array<int> gJtArrived;
array<int> gJtDeadline;
const uint JT_MAX = 256;

void JtDrop(uint i)
{
	if (gJtPath[i] == JA_REZ)
		Builder::ComRezRelease(gJtUnit[i]);
	gJtUnit.removeAt(i);
	gJtPath.removeAt(i);
	gJtJob.removeAt(i);
	gJtGiven.removeAt(i);
	gJtSite.removeAt(i);
	gJtReach.removeAt(i);
	gJtEnd.removeAt(i);
	gJtArrived.removeAt(i);
	gJtDeadline.removeAt(i);
}

// endFrame >= 0 for a job with no task (a corpse): it ends then, or when the
// wreck is gone.
void JoinTaken(int path, CCircuitUnit@ unit, IUnitTask@ job, IUnitTask@ given,
		const AIFloat3& in site, int endFrame = -1)
{
	if ((unit is null) || (path < 0) || (path >= JA_N) || !OnMap(site))
		return;
	const int uid = int(unit.id);
	for (uint i = 0; i < gJtUnit.length(); ++i) {
		if (gJtUnit[i] != uid)
			continue;
		if ((gJtPath[i] == path) && (gJtJob[i] is job) && (gJtSite[i].distance2D(site) < 1.f)) {
			@gJtGiven[i] = given;
			return;
		}
		JtDrop(i);
		break;
	}
	if (gJtUnit.length() >= JT_MAX)
		JtDrop(0);
	++gJaTaken[path];
	const int ud = int(unit.circuitDef.id);
	float half = 0.f;
	if ((job !is null) && (job.buildDef !is null) && Catalog::ValidId(int(job.buildDef.id))) {
		const int bd = int(job.buildDef.id);
		half = 8.f * float((Catalog::gFootX[bd] > Catalog::gFootZ[bd])
				? Catalog::gFootX[bd] : Catalog::gFootZ[bd]);
	}
	const float reach = Catalog::gBuildDist[ud] + half + 32.f;
	const float arrive = JoinArriveSec(unit, site);
	gJtUnit.insertLast(uid);
	gJtPath.insertLast(path);
	gJtJob.insertLast(job);
	gJtGiven.insertLast(given);
	gJtSite.insertLast(site);
	gJtReach.insertLast((reach > 100.f) ? reach : 100.f);
	gJtEnd.insertLast(endFrame);
	gJtArrived.insertLast(-1);
	gJtDeadline.insertLast(ai.frame + int((3.f * arrive + 120.f) * float(SECOND)));
}

bool JtJobOver(uint i)
{
	IUnitTask@ job = gJtJob[i];
	if (job !is null)
		return job.IsDead() || (Progress(job) >= 1.f);
	if ((gJtEnd[i] >= 0) && (ai.frame > gJtEnd[i]))
		return true;
	return ai.GetWreckValueAt(gJtSite[i], gJtReach[i]) <= 0.f;
}

int gJaStatAt = 0;
void JoinArriveTick()
{
	for (uint i = 0; i < gJtUnit.length(); ) {
		CCircuitUnit@ u = ai.GetTeamUnit(Id(gJtUnit[i]));
		const int p = gJtPath[i];
		if (u is null) {
			JtDrop(i);
			continue;
		}
		const bool over = JtJobOver(i);
		const bool left = (gJtGiven[i] !is null) && (u.task !is gJtGiven[i]);
		if (gJtArrived[i] < 0) {
			if (over) {
				++gJaLate[p];
				JtDrop(i);
				continue;
			}
			if (u.GetPos(ai.frame).distance2D(gJtSite[i]) <= gJtReach[i]) {
				gJtArrived[i] = ai.frame;
				++gJaOnTime[p];
			} else if (left || (ai.frame > gJtDeadline[i])) {
				JtDrop(i);
				continue;
			}
		} else if (over || left || (ai.frame > gJtDeadline[i])) {
			gJaUsefulS[p] += float(ai.frame - gJtArrived[i]) / float(SECOND);
			++gJaUsefulN[p];
			JtDrop(i);
			continue;
		}
		++i;
	}
	if (ai.frame < gJaStatAt)
		return;
	gJaStatAt = ai.frame + 60 * SECOND;
	string s = "";
	for (int p = 0; p < JA_N; ++p) {
		if ((gJaAsked[p] + gJaTaken[p] + gJaLate[p] + gJaOnTime[p] + gJaUsefulN[p]) == 0)
			continue;
		s += " " + JaPathName(p) + "=ask:" + gJaAsked[p]
			+ ",ref:" + gJaRefLate[p] + "/" + gJaRefFull[p] + "/" + gJaRefCost[p] + "/" + gJaRefTaken[p]
			+ ",take:" + gJaTaken[p] + ",late:" + gJaLate[p] + ",ok:" + gJaOnTime[p]
			+ ",useS:" + formatFloat((gJaUsefulN[p] > 0) ? gJaUsefulS[p] / float(gJaUsefulN[p]) : 0.f, "", 0, 1);
		gJaAsked[p] = 0; gJaRefLate[p] = 0; gJaRefFull[p] = 0; gJaRefCost[p] = 0;
		gJaRefTaken[p] = 0; gJaTaken[p] = 0; gJaLate[p] = 0; gJaOnTime[p] = 0;
		gJaUsefulN[p] = 0; gJaUsefulS[p] = 0.f;
	}
	AiLog(Factory::T() + "apex: joinarrive-stat t=" + ai.teamId + " on=" + (JoinArriveOn() ? 1 : 0)
		+ " track=" + gJtUnit.length() + " ref=late/full/cost/taken |"
		+ (s.isEmpty() ? " none" : s));
}

}  // namespace Requests
