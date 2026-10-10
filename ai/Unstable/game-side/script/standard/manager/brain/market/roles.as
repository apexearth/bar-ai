namespace Market {
// CONSTRUCTOR ROLES (apexearth 2026-09-08): "assign roles to our constructors
// by a % based on what it sees as a split of our needs... give an engineer a
// special role to do only that job until our brain decides it is no longer
// needed... leave some cons as open unroled cons."
//
// The split is the draw's own ticket share per category, smoothed over
// apex_role_tau seconds, floored by the unmet share of the category's own
// target where it has one (apexearth 2026-09-13: roles from target gaps --
// the ticket share alone starves exactly what the draw starves, and a
// category's target is the one number that says the hands are missing).
// apex_role_share of the hands hold a role; the rest stay open and elect as
// before. A roled hand elects inside its category until its
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
// When a category last fell: a role is not handed out again for ground the
// executor is refusing (measured: 823 role=sense elections in five minutes
// on one seat, each refused at the chokepoint and re-assigned the next tick).
array<int> gCatFellAt(CAT_N, -999999);
const int CAT_FELL_HOLD = 30 * SECOND;

void NoteCategoryFell(int c)
{
	if ((c >= 0) && (c < CAT_N))
		gCatFellAt[c] = ai.frame;
}

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

// The unmet share of a category's target, 0..1; 0 where no target exists.
float CatGapFrac(int c)
{
	if (c == CAT_DEFENCE) {
		const float t = DefenceTarget();
		if (t <= 1.f)
			return 0.f;
		const float g = t - DefenceValue() - DefenceInFlightM();
		return (g <= 0.f) ? 0.f : ((g > t) ? 1.f : g / t);
	}
	if (c == CAT_BP) {
		const float g = BPGap();
		const float t = BPCapacity() + g;
		return ((g <= 0.f) || (t <= 1.f)) ? 0.f : (g / t);
	}
	if (c == CAT_ENERGY) {
		// Energy thrown away is energy work too -- the converters only an
		// advanced hand can raise (a safe seat wasted two thirds of 15k E/s
		// while its T2 cons were all on the defence role).
		const float lack = 1.f - EFeedShare();
		const float eInc = Eco::EInc();
		float waste = (eInc > 1.f) ? (gEExcessEma / eInc) : 0.f;
		if (waste > 1.f)
			waste = 1.f;
		return (waste > lack) ? waste : lack;
	}
	return 0.f;
}

array<float> gRoleNeed(CAT_N, 0.f);

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
	float sum = 0.f;
	for (int c = 0; c < CAT_N; ++c) {
		const float gap = CatGapFrac(c);
		gRoleNeed[c] = (gap > gRoleShare[c]) ? gap : gRoleShare[c];
		sum += gRoleNeed[c];
	}
	for (int c = 0; c < CAT_N; ++c)
		gRoleQuota[c] = (sum > 0.f)
				? int(gRoleNeed[c] / sum * float(roled) * ((c == CAT_DEFENCE) ? gGunpMul : 1.f) + 0.5f) : 0;
}

// A ROLE RESERVES A HAND FOR WORK WORTH DOING, NOT FOR ANY WORK. A category
// earns one of the R roled hands when the draw itself would hand it at least
// one of R elections -- its sharpened ticket share is at least 1/R. Below
// that the category's best want is worthless by the market's own arithmetic
// (the eco seat's defence-roled hands bought Bulwarks in the safe corner at
// v=0.09 over assist at v=52), and the hand is released to the draw.
array<int> gRwCatBest;
array<float> gRwWt;
array<Want@>@ gRwRanked;
float gRwSum = 0.f;
void RoleWorthPrep(array<Want@>@ ranked)
{
	@gRwRanked = ranked;
	gRwSum = DrawWeights(ranked, gRwCatBest, gRwWt);
}

// Whether the category's best want is one its TARGET counts: a turret closes
// the defence gap, dragon's teeth do not (a T1 hand's only ground-defence
// candidate once the turret is routed out, and the role hoisted it 150 times
// a game at v=0.06).
bool RoleWantClosesGap(int c)
{
	if ((gRwRanked is null) || (gRwCatBest[c] < 0)
		|| (gRwCatBest[c] >= int(gRwRanked.length())))
		return false;
	const Want@ w = gRwRanked[uint(gRwCatBest[c])];
	if (c == CAT_DEFENCE)
		return (w.kind == WK_PROTECT) && (w.spotId == PROT_DEF);
	return true;
}

bool RoleWorthDoing(int c)
{
	if ((gRwSum <= 0.f) || (c < 0) || (c >= int(gRwWt.length())) || (gRwCatBest[c] < 0))
		return false;
	// A QUOTA THE TARGET GAP SET IS NOT RE-JUDGED BY THE DRAW: the gap floor
	// exists because a category the draw starves gets a starved ticket, and
	// testing the quota against that same ticket starved it again. Only for
	// a want that closes the gap; anything else in the category is judged as
	// the draw would.
	if ((CatGapFrac(c) > gRoleShare[c]) && RoleWantClosesGap(c))
		return true;
	const float shareK = ai.GetTunable("apex_role_share", TUNE_ROLE_SHARE);
	int roled = int(float(gWorkerIds.length()) * shareK);
	if (roled < 1)
		roled = 1;
	return gRwWt[c] * float(roled) >= gRwSum;
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

// The one hand of its tier: not a T1 hand, and no other advanced builder
// stands. It takes no role and upgrades a mex first (decide.as).
bool SoleAdvancedHand(CCircuitUnit@ unit)
{
	const int uid = int(unit.circuitDef.id);
	if ((uid < int(Catalog::gT1Hand.length())) && Catalog::gT1Hand[uid])
		return false;
	int advanced = 0;
	const array<int>@ _own28 = OwnedDefs();
	for (uint _oi28 = 0; _oi28 < _own28.length(); ++_oi28) {
		const uint c = uint(_own28[_oi28]);
		const int ci = int(c);
		if ((gOwnCount[c] <= 0) || !Catalog::gMobile[ci] || !Catalog::gBuilder[ci])
			continue;
		if ((ci < int(Catalog::gT1Hand.length())) && Catalog::gT1Hand[ci])
			continue;
		advanced += gOwnCount[c];
	}
	return advanced <= 1;
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
	// THE ONLY ADVANCED HAND TAKES NO ROLE: a role parks it in one category,
	// and the first T2 con was parked in DEFENCE at v=1.3 with a home moho
	// at v=8 that no other hand could build (gate: 3 of 3 opened with an
	// Ambusher, a radar or an anti-nuke). A category's quota is for hands
	// that have peers; the one hand of its tier serves the best job of it.
	if (SoleAdvancedHand(unit))
		return false;
	ConRoleRecount();
	RoleWorthPrep(ranked);
	int r = gRoleOf[id];
	if (r >= 0) {
		if ((gRoleCount[r] > gRoleQuota[r]) || !RankedHas(ranked, r)
			|| !RoleWorthDoing(r)) {
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
			if (ai.frame < gCatFellAt[c] + CAT_FELL_HOLD)
				continue;
			if ((gap > bestGap) && RankedHas(ranked, c) && RoleWorthDoing(c)) {
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
		if ((gRoleNeed[c] < 0.005f) && (gRoleCount[c] == 0))
			continue;
		ln += " " + CatName(c) + "=" + formatFloat(gRoleShare[c], "", 0, 2)
				+ "+" + formatFloat(CatGapFrac(c), "", 0, 2)
				+ ":" + gRoleCount[c] + "/" + gRoleQuota[c];
	}
	AiLog(ln);
}

}  // namespace Market
