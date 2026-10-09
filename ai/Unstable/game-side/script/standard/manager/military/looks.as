namespace Military {

// WANTED LOOKS (priority #7, 2026-10-08). A decision waiting on something it
// cannot see registers a look: a place, and the metal its expected outcome
// moves by if it knew. Scouts are bought and sent on the trips those looks
// make; how many is an output of the looks, not a rule.
const int LOOK_SIEGE = 0, LOOK_RAID = 1, LOOK_HUNT = 2, LOOK_WING = 3, LOOK_SILENCE = 4, LOOK_KINDS = 5;
const int LOOK_MAX = 32;          // memory: the cheapest look is evicted
const float LOOK_MERGE_R = 500.f; // the DLL's spot-wanted merge radius
const float LOOK_TRIP_R = 600.f;  // one cheap scout's sight, near enough
const int LOOK_AIR = 0, LOOK_GROUND = 1;

array<int> gLkKind;
array<AIFloat3> gLkPos;
array<float> gLkVal;
array<int> gLkUntil;
array<int> gLkBy;        // the scout flying to it, -1 none

array<int> gLcId;        // one claim per scout on a trip
array<int> gLcDom;
array<int> gLcUntil;
array<AIFloat3> gLcPos;
array<int> gLcSeen;

array<AIFloat3> gLtPos;  // unclaimed trips, best first
array<float> gLtVal;

array<int> gLkScoutOf;   // by def: 0 not a scout, 1 air, 2 ground
array<int> gLkScoutDefs;

array<int> gLkSent = {0, 0};
array<int> gLkGot = {0, 0};
array<int> gLkLost = {0, 0};
array<int> gLkNoted(LOOK_KINDS, 0);
array<int> gLkSettled(LOOK_KINDS, 0);
int gLkOwnFree = 0;
int gLkNextAt = 0, gLkLogAt = 0, gLkEvictN = 0, gLkPullN = 0, gLkTakeN = 0;

string LookKindName(int k)
{
	if (k == LOOK_SIEGE) return "siege";
	if (k == LOOK_RAID) return "raid";
	if (k == LOOK_HUNT) return "hunt";
	if (k == LOOK_WING) return "wing";
	return "silence";
}

void LookRemove(uint i)
{
	gLkKind.removeAt(i);
	gLkPos.removeAt(i);
	gLkVal.removeAt(i);
	gLkUntil.removeAt(i);
	gLkBy.removeAt(i);
}

void NoteLook(int kind, const AIFloat3& in at, float valueM, int ttlS)
{
	if ((valueM <= 0.f) || (kind < 0) || (kind >= LOOK_KINDS) || !OnMap(at) || ai.IsPosInLos(at))
		return;
	++gLkNoted[kind];
	const int until = ai.frame + ttlS * SECOND;
	int low = -1;
	for (uint i = 0; i < gLkKind.length(); ++i) {
		if ((gLkKind[i] == kind) && (gLkPos[i].distance2D(at) < LOOK_MERGE_R)) {
			gLkVal[i] = valueM;
			if (until > gLkUntil[i])
				gLkUntil[i] = until;
			return;
		}
		if ((gLkBy[i] < 0) && ((low < 0) || (gLkVal[i] < gLkVal[low])))
			low = int(i);
	}
	if (int(gLkKind.length()) >= LOOK_MAX) {
		if ((low < 0) || (gLkVal[low] >= valueM))
			return;
		++gLkEvictN;
		LookRemove(uint(low));
	}
	gLkKind.insertLast(kind);
	gLkPos.insertLast(at);
	gLkVal.insertLast(valueM);
	gLkUntil.insertLast(until);
	gLkBy.insertLast(-1);
}

void LookDrop(int kind)
{
	for (int i = int(gLkKind.length()) - 1; i >= 0; --i) {
		if ((gLkKind[i] == kind) && (gLkBy[i] < 0))
			LookRemove(uint(i));
	}
}

bool LookGroundDef(int d)
{
	return Market::IsLateScout(d) && !Catalog::gFloater[d] && !Catalog::gSub[d];
}

int LookScoutOf(int d)
{
	return ((d > 0) && (d < int(gLkScoutOf.length()))) ? gLkScoutOf[d] : 0;
}

void LookDefs()
{
	if (gLkScoutOf.length() > 0)
		return;
	gLkScoutOf.resize(uint(Catalog::gDefCount + 1));
	gLkScoutDefs.resize(0);
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		int k = 0;
		if (Air::IsLookDef(d))
			k = 1;
		else if (Catalog::gAvailable[d] && LookGroundDef(d))
			k = 2;
		gLkScoutOf[d] = k;
		if (k > 0)
			gLkScoutDefs.insertLast(d);
	}
}

// The share of trips that came back with something, this game's own flights.
float LookP(int dom)
{
	return float(gLkGot[dom] + 1) / float(gLkSent[dom] + 2);
}

int LookClaimIdx(int id)
{
	for (uint c = 0; c < gLcId.length(); ++c) {
		if (gLcId[c] == id)
			return int(c);
	}
	return -1;
}

void LookEndClaim(uint c, const string& in why)
{
	const int id = gLcId[c];
	const int dom = gLcDom[c];
	if (gLcSeen[c] > 0)
		++gLkGot[dom];
	else if (why == "lost")
		++gLkLost[dom];
	for (uint i = 0; i < gLkBy.length(); ++i) {
		if (gLkBy[i] == id)
			gLkBy[i] = -1;
	}
	AiLog(Factory::T() + "apex: look-done t=" + ai.teamId + " #" + id
		+ " dom=" + ((dom == LOOK_AIR) ? "air" : "ground") + " why=" + why
		+ " seen=" + gLcSeen[c] + " p=" + formatFloat(LookP(dom), "", 0, 2));
	gLcId.removeAt(c);
	gLcDom.removeAt(c);
	gLcUntil.removeAt(c);
	gLcPos.removeAt(c);
	gLcSeen.removeAt(c);
}

// Seen places settle their looks; a scout's trip ends when it arrives, dies
// or runs out of time.
void LookSettle()
{
	for (int i = int(gLkKind.length()) - 1; i >= 0; --i) {
		if (ai.IsPosInLos(gLkPos[i])) {
			++gLkSettled[gLkKind[i]];
			if (gLkBy[i] >= 0) {
				const int c = LookClaimIdx(gLkBy[i]);
				if (c >= 0)
					++gLcSeen[c];
			}
			LookRemove(uint(i));
		} else if ((gLkBy[i] < 0) && (ai.frame > gLkUntil[i])) {
			LookRemove(uint(i));
		}
	}
	for (int c = int(gLcId.length()) - 1; c >= 0; --c) {
		CCircuitUnit@ u = ai.GetTeamUnit(Id(gLcId[c]));
		if (u is null)
			LookEndClaim(uint(c), "lost");
		else if (u.GetPos(ai.frame).distance2D(gLcPos[c]) < 300.f)
			LookEndClaim(uint(c), "arrived");
		else if (ai.frame > gLcUntil[c])
			LookEndClaim(uint(c), "timeout");
	}
}

void LookTrips()
{
	gLtPos.resize(0);
	gLtVal.resize(0);
	const uint n = gLkKind.length();
	array<float> s(n, 0.f);
	array<bool> used(n, false);
	for (uint i = 0; i < n; ++i) {
		if (gLkBy[i] >= 0) {
			used[i] = true;
			continue;
		}
		for (uint j = 0; j < n; ++j) {
			if ((gLkBy[j] < 0) && (gLkPos[i].distance2D(gLkPos[j]) < LOOK_TRIP_R))
				s[i] += gLkVal[j];
		}
	}
	for (uint pass = 0; pass < n; ++pass) {
		int b = -1;
		for (uint i = 0; i < n; ++i) {
			if (!used[i] && ((b < 0) || (s[i] > s[b])))
				b = int(i);
		}
		if (b < 0)
			break;
		float v = 0.f;
		for (uint j = 0; j < n; ++j) {
			if (!used[j] && (gLkPos[b].distance2D(gLkPos[j]) < LOOK_TRIP_R)) {
				v += gLkVal[j];
				used[j] = true;
			}
		}
		uint at = gLtVal.length();
		while ((at > 0) && (gLtVal[at - 1] < v))
			--at;
		gLtVal.insertAt(at, v);
		gLtPos.insertAt(at, gLkPos[b]);
	}
}

// Scouts standing that no trip holds; the queue is added live by the buyer.
void LookFleet()
{
	int own = 0;
	for (uint k = 0; k < gLkScoutDefs.length(); ++k) {
		const int d = gLkScoutDefs[k];
		if (d < int(Market::gOwnCount.length()))
			own += Market::gOwnCount[d];
	}
	own -= int(gLcId.length());
	if (Air::LookOut())
		--own;
	gLkOwnFree = (own > 0) ? own : 0;
}

int LookPendScouts()
{
	int n = 0;
	for (uint k = 0; k < gLkScoutDefs.length(); ++k)
		n += Brain::PendAnyOf(gLkScoutDefs[k]);
	return n;
}

// The trip one more scout would fly: past every trip the scouts we have and
// have queued can already take.
float LookMarginal()
{
	const int k = gLkOwnFree + LookPendScouts();
	return (k < int(gLtVal.length())) ? gLtVal[k] : 0.f;
}

// The production price of one more scout of def d, metal/s: the trip it would
// fly times the share of trips that deliver, and only if that returns the
// scout's own cost.
float LookBuyGain(int d, float fillSec)
{
	const int dom = (LookScoutOf(d) == 1) ? LOOK_AIR : ((LookScoutOf(d) == 2) ? LOOK_GROUND : -1);
	if ((dom < 0) || (gLtVal.length() == 0))
		return 0.f;
	if ((dom == LOOK_AIR) && Air::ScoutsDie())
		return 0.f;
	const float v = LookMarginal() * LookP(dom);
	if (v < Catalog::gCostM[d])
		return 0.f;
	return v / ((fillSec > 1.f) ? fillSec : 180.f);
}

// Hand the best trip this scout should fly to it: claimed, so no other scout
// is sent the same way. Worth it when what the look delivers beats what the
// scout is expected to lose getting there.
bool LookTake(CCircuitUnit@ u, int dom, AIFloat3& out over)
{
	if ((u is null) || (u.circuitDef is null) || (gLtVal.length() == 0))
		return false;
	if (LookClaimIdx(int(u.id)) >= 0)
		return false;
	const int d = int(u.circuitDef.id);
	const float p = LookP(dom);
	if (gLtVal[0] * p < Catalog::gCostM[d] * (1.f - p))
		return false;
	over = gLtPos[0];
	const float val = gLtVal[0];
	gLtPos.removeAt(0);
	gLtVal.removeAt(0);
	for (uint i = 0; i < gLkKind.length(); ++i) {
		if ((gLkBy[i] < 0) && (gLkPos[i].distance2D(over) < LOOK_TRIP_R))
			gLkBy[i] = int(u.id);
	}
	const float dist = u.GetPos(ai.frame).distance2D(over);
	const float spd = (Catalog::gSpeed[d] > 1.f) ? Catalog::gSpeed[d] : 30.f;
	gLcId.insertLast(int(u.id));
	gLcDom.insertLast(dom);
	gLcUntil.insertLast(ai.frame + int(2.f * dist / spd + 15.f) * SECOND);
	gLcPos.insertLast(over);
	gLcSeen.insertLast(0);
	++gLkSent[dom];
	if (gLkOwnFree > 0)
		--gLkOwnFree;
	AiLog(Factory::T() + "apex: look-send t=" + ai.teamId + " " + u.circuitDef.GetName()
		+ " #" + u.id + " -> " + int(over.x) + "," + int(over.z)
		+ " v=" + int(val) + " p=" + formatFloat(p, "", 0, 2) + " trips=" + gLtVal.length());
	return true;
}

// Called from AiMakeTask for every unit: a scout on a trip keeps its move
// order, and a fresh ground scout takes the best trip before stock routing.
bool LookHolds(CCircuitUnit@ unit)
{
	const int k = LookScoutOf(int(unit.circuitDef.id));
	if (k == 0)
		return false;
	if (LookClaimIdx(int(unit.id)) >= 0)
		return true;
	if (k != 2)
		return false;
	AIFloat3 over;
	if (!LookTake(unit, LOOK_GROUND, over))
		return false;
	unit.CmdMoveTo(over);
	++gLkTakeN;
	return true;
}

// One ground scout a clock is taken off map-coverage or the attack for the
// best trip no one flies.
void LookPull()
{
	if (gLtVal.length() == 0)
		return;
	const AIFloat3 to = gLtPos[0];
	CCircuitUnit@ best = null;
	float bd = 0.f;
	for (uint k = 0; k < gLkScoutDefs.length(); ++k) {
		const int d = gLkScoutDefs[k];
		if ((LookScoutOf(d) != 2) || (d >= int(Market::gOwnCount.length())) || (Market::gOwnCount[d] <= 0))
			continue;
		array<CCircuitUnit@>@ us = ai.GetOwnUnitsOfDef(Catalog::Def(d), to, 0.f);
		if (us is null)
			continue;
		for (uint i = 0; i < us.length(); ++i) {
			CCircuitUnit@ u = us[i];
			if ((u is null) || (LookClaimIdx(int(u.id)) >= 0))
				continue;
			IUnitTask@ t = u.task;
			if (t is null)
				continue;
			const int tt = t.GetType();
			if (tt == Task::Type::FIGHTER) {
				const int ft = t.GetFightType();
				if ((ft != int(Task::FightType::SCOUT)) && (ft != int(Task::FightType::ATTACK)))
					continue;
			} else if (tt != Task::Type::IDLE) {
				continue;
			}
			const float dd = u.GetPos(ai.frame).distance2D(to);
			if ((best is null) || (dd < bd)) {
				@best = u;
				bd = dd;
			}
		}
	}
	if (best is null)
		return;
	AIFloat3 over;
	if (!LookTake(best, LOOK_GROUND, over))
		return;
	IUnitTask@ bt = best.task;
	if ((bt !is null) && (bt.GetType() == Task::Type::FIGHTER))
		bt.RemoveUnit(best);
	best.CmdMoveTo(over);
	++gLkPullN;
}

void LookSiege()
{
	const int n = aiMilitaryMgr.GetSpotWantedCount();
	for (int i = 0; i < n; ++i) {
		const AIFloat3 p = aiMilitaryMgr.GetSpotWantedAt(i);
		if (!OnMap(p))
			continue;
		NoteLook(LOOK_SIEGE, p, aiEnemyMgr.GetEnemyStructCostAt(p, 400.f) + ai.GetEnemyArmedCostNear(p, 400.f), 20);
	}
}

// Too much silence demands scouting: their army we cannot see, sized no
// smaller than ours, is what the posture is deciding blind.
void LookSilence()
{
	if ((ai.GetTunable("apex_stance", TUNE_STANCE) <= 0.f) || !StanceUnknown())
		return;
	float foeEst = FoeBelievedM();
	const float ours = Market::ArmyValue();
	if (ours > foeEst)
		foeEst = ours;
	NoteLook(LOOK_SILENCE, Front::FoeAnchor(), foeEst - FoeLiveM(), 12);
}

void LookWing()
{
	Air::ResolveDefs();
	if (Air::LookOut())
		return;
	NoteLook(LOOK_WING, Front::FoeAnchor(), Air::WingLookWorth(), 12);
}

void LookLog()
{
	if (ai.frame < gLkLogAt)
		return;
	gLkLogAt = ai.frame + 60 * SECOND;
	array<int> cnt(LOOK_KINDS, 0);
	array<float> val(LOOK_KINDS, 0.f);
	for (uint i = 0; i < gLkKind.length(); ++i) {
		++cnt[gLkKind[i]];
		val[gLkKind[i]] += gLkVal[i];
	}
	string per = "";
	for (int k = 0; k < LOOK_KINDS; ++k)
		per += " " + LookKindName(k) + "=" + cnt[k] + "/" + int(val[k])
			+ "/n" + gLkNoted[k] + "/s" + gLkSettled[k];
	AiLog(Factory::T() + "apex: looks t=" + ai.teamId + " n=" + gLkKind.length() + per
		+ " trips=" + gLtVal.length()
		+ " top=" + ((gLtVal.length() > 0) ? int(gLtVal[0]) : 0)
		+ " marg=" + int(LookMarginal())
		+ " free=" + gLkOwnFree + " claims=" + gLcId.length()
		+ " air=" + gLkGot[LOOK_AIR] + "/" + gLkSent[LOOK_AIR] + "/l" + gLkLost[LOOK_AIR]
		+ " ground=" + gLkGot[LOOK_GROUND] + "/" + gLkSent[LOOK_GROUND] + "/l" + gLkLost[LOOK_GROUND]
		+ " take=" + gLkTakeN + " pull=" + gLkPullN + " evict=" + gLkEvictN);
}

void UpdateLooks()
{
	if (!Builder::gHomeSet || (Catalog::gDefCount <= 0))
		return;
	if (ai.frame < gLkNextAt)
		return;
	gLkNextAt = ai.frame + 4 * SECOND;
	LookDefs();
	LookSiege();
	LookSilence();
	LookWing();
	LookSettle();
	LookTrips();
	LookFleet();
	LookPull();
	LookLog();
}

}  // namespace Military
