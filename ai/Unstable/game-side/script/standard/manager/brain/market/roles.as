namespace Market {
// CONSTRUCTOR ROLES (apexearth 2026-09-08): "assign roles to our constructors
// by a % based on what it sees as a split of our needs... give an engineer a
// special role to do only that job until our brain decides it is no longer
// needed... leave some cons as open unroled cons."
//
// The split is the draw's own ticket share per category, smoothed over
// apex_role_tau seconds -- what the market itself would pick, not a second
// model of need. apex_role_share of the hands hold a role; the rest stay open
// and elect as before. A roled hand elects inside its category until its
// category is over quota or offers it nothing, and the commander is always
// open. A role changes which want a hand takes FIRST, never whether: the rest
// of its list stays behind the category, so a refused category falls through.
array<float> gRoleShare(CAT_N, 0.f);
int gRoleCensusAt = -999999;
array<int> gRoleOf(32001, -1);      // per unit id, Spring ids cap at 32k
array<int> gRoleCount(CAT_N, 0);
array<int> gRoleQuota(CAT_N, 0);
int gRoleCountAt = -999999;
int gNextRolesLog = 0;
int gRoleTaken = 0;
int gRoleDropped = 0;
int gRoleFell = 0;      // released because the category could not be executed

void ConRoleCensus(const array<float>& in wt, float sum)
{
	if (sum <= 0.f)
		return;
	const float tau = ai.GetTunable("apex_role_tau", TUNE_ROLE_TAU);
	float a = 1.f;
	if ((gRoleCensusAt > -999999) && (tau > 1.f)) {
		a = float(ai.frame - gRoleCensusAt) / (tau * float(SECOND));
		if (a > 1.f)
			a = 1.f;
	}
	gRoleCensusAt = ai.frame;
	for (int c = 0; c < CAT_N; ++c)
		gRoleShare[c] += (wt[c] / sum - gRoleShare[c]) * a;
}

void ConRoleRecount()
{
	if (gRoleCountAt == ai.frame)
		return;
	gRoleCountAt = ai.frame;
	for (int c = 0; c < CAT_N; ++c)
		gRoleCount[c] = 0;
	for (uint i = 0; i < gWorkerIds.length(); ++i) {
		const int id = int(gWorkerIds[i]);
		if ((id < 0) || (id >= int(gRoleOf.length())))
			continue;
		const int r = gRoleOf[id];
		if (r >= 0)
			++gRoleCount[r];
	}
	const float shareK = ai.GetTunable("apex_role_share", TUNE_ROLE_SHARE);
	const int roled = int(float(gWorkerIds.length()) * shareK);
	for (int c = 0; c < CAT_N; ++c)
		gRoleQuota[c] = int(gRoleShare[c] * float(roled) + 0.5f);
}

bool RankedHas(array<Want@>@ ranked, int c)
{
	for (uint i = 0; i < ranked.length(); ++i) {
		if (CategoryOf(ranked[i].kind) == c)
			return true;
	}
	return false;
}

void ConRoleForget(int id)
{
	if ((id >= 0) && (id < int(gRoleOf.length())))
		gRoleOf[id] = -1;
}

int ConRoleOf(CCircuitUnit@ unit)
{
	const int id = int(unit.id);
	return ((id >= 0) && (id < int(gRoleOf.length()))) ? gRoleOf[id] : -1;
}

// Assign, keep or release this hand's role, then hoist its category to the
// front of the list. True when the election is the category's own.
bool ConRoleApply(CCircuitUnit@ unit, array<Want@>@ ranked)
{
	const int id = int(unit.id);
	if ((id < 0) || (id >= int(gRoleOf.length())))
		return false;
	if (unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask))
		return false;
	ConRoleRecount();
	int r = gRoleOf[id];
	if (r >= 0) {
		if ((gRoleCount[r] > gRoleQuota[r]) || !RankedHas(ranked, r)) {
			gRoleOf[id] = -1;
			--gRoleCount[r];
			++gRoleDropped;
			r = -1;
		}
	}
	if (r < 0) {
		int best = -1;
		int bestGap = 0;
		for (int c = 0; c < CAT_N; ++c) {
			const int gap = gRoleQuota[c] - gRoleCount[c];
			if ((gap > bestGap) && RankedHas(ranked, c)) {
				best = c;
				bestGap = gap;
			}
		}
		if (best < 0)
			return false;
		r = best;
		gRoleOf[id] = r;
		++gRoleCount[r];
		++gRoleTaken;
	}
	uint at = 0;
	for (uint i = 0; i < ranked.length(); ++i) {
		if (CategoryOf(ranked[i].kind) != r)
			continue;
		if (i != at) {
			Want@ w = ranked[i];
			ranked.removeAt(i);
			ranked.insertAt(at, w);
		}
		++at;
	}
	return true;
}

void ConRoleLog()
{
	if (ai.frame < gNextRolesLog)
		return;
	gNextRolesLog = ai.frame + 30 * SECOND;
	ConRoleRecount();
	int roled = 0;
	for (int c = 0; c < CAT_N; ++c)
		roled += gRoleCount[c];
	string ln = Factory::T() + "apex: roles t=" + ai.teamId
			+ " workers=" + gWorkerIds.length() + " roled=" + roled
			+ " taken=" + gRoleTaken + " dropped=" + gRoleDropped
			+ " fell=" + gRoleFell + " |";
	for (int c = 0; c < CAT_N; ++c) {
		if ((gRoleShare[c] < 0.005f) && (gRoleCount[c] == 0))
			continue;
		ln += " " + CatName(c) + "=" + formatFloat(gRoleShare[c], "", 0, 2)
				+ ":" + gRoleCount[c] + "/" + gRoleQuota[c];
	}
	AiLog(ln);
}

}  // namespace Market
