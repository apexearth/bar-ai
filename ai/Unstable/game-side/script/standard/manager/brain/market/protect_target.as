namespace Market {
//------------------------------------------------------------------------------
// TARGETS, not appetites.
//
// Army has had a target since the beginning and so it SATURATES: build until
// ArmyValue reaches ArmyTarget and the gap closes. Static defence never had
// one. It was bought marginally, turret by turret, priced as "expected loss
// prevented" with no notion of enough -- and its marginal value never decayed,
// because the hazard it multiplies is floored by a prior that scales with our
// OWN economy. So defence tracked the economy at a fixed ratio forever:
// measured 175% of eco against stock BARb's 52%, on a quarter of their income.
//
// A target is also how a role says what it is FOR without anyone being
// forbidden anything (apexearth: "why not just have eco players with
// ArmyTarget and DefenseTarget at 0? Make AATarget too?"). The rear
// specialist's numbers fall out near zero because nothing reaches it -- and
// rise again on their own if something does.
//------------------------------------------------------------------------------

// MINIMUM PROTECTION PER MEX, in turret metal.
//
// The rest of this file prices defence against what it can SEE arriving. That
// is right for a contested lane and useless for the opening: a fresh mex has
// never been shot at, so its wave reads zero, so it is not a candidate at all.
// This is the other half -- what a mex is worth covering before anything has
// happened to it -- expressed in the faction's own light tower so it means the
// same thing on every faction and at every tier.
float MexCoverFloorM()
{
	return ai.GetTunable("apex_mex_cover_floor", TUNE_MEX_COVER_FLOOR)
			* LightTowerCostM();
}

// THE FLOOR SCALES WITH EXPOSURE BOTH WAYS (his rulings, three times over:
// "the closer our mex is to the enemy and furthest from our army, the
// stronger the defenses should be"; "move 8 spread out defenses from mexes
// into less choke points"; and, watching the team game, "an unusual amount
// of T1 turrets in bases"). The flat floor bought a light tower per mex
// across the safe interior -- only the scale-UP half of the ruling was ever
// built. The no-evidence MINIMUM now runs from ~zero on rear ground to
// full-plus-apex_mex_expose at the front; the gate-concentration floors
// carry the interior's protection duty, and threat-priced buys are
// untouched -- a mex anything real approaches still buys its guard through
// the auction. Shared by the site loop AND the cover-push queue-jump, so
// the jump cannot keep buying what the auction's floor no longer asks for.
float MexFloorFactor(const AIFloat3& in pos)
{
	float fwd = Military::ForwardFraction(pos);
	if (fwd < 0.f)
		fwd = 0.f;
	if (fwd > 1.f)
		fwd = 1.f;
	float f = fwd * (1.f + fwd
			* ai.GetTunable("apex_mex_expose", TUNE_MEX_EXPOSE));
	// EARLY, EVERY MEX IS THE FRONTIER. The forwardness scaling is a
	// late-game truth -- rear ground is safe because the army screens it.
	// With no army fielded there is no screen, and the first mexes sit AT
	// or BEHIND the worth centroid, so their floor read exactly zero: the
	// commander capped three, walked behind a hill to the factory, and one
	// enemy scout -- the cheapest unit in the game -- erased ~1,000 metal
	// of build and income (apexearth, watching, 2026-08-30: "If we know
	// we're about to leave something unguarded we should defend it").
	// Until our fielded army reaches the leak screen, every standing mex
	// carries the full floor whatever its bearing; the term fades as the
	// army takes over the job.
	const float screen = ai.GetTunable("apex_leak_screen_m",
			TUNE_LEAK_SCREEN_M);
	if (screen > 1.f) {
		float early = 1.f - ArmyValue() / screen;
		if (early > f)
			f = early;
	}
	return f;
}

// THE MEX'S VALUE IS ITS STREAM, not its 50-metal shell (apexearth
// 2026-08-28: "we run around building a lot of mexes but we lose them all
// to enemies" -- the guard want priced insurance on the shell, came out at
// v=0.01-2.7, and lost every decide roulette: 677 site-auction wins, zero
// decide wins, 14 towers, none at a mex, in one watched game). The
// extraction in reach, capitalized over the same amortization horizon
// reclaim uses, is what a guard actually protects.
float MexStreamM(const AIFloat3& in s, float reach)
{
	const float hzS = ai.GetTunable("apex_reclaim_amort", TUNE_RECLAIM_AMORT);
	const float hz = (hzS > 1.f) ? hzS : 300.f;
	float m = 0.f;
	for (uint i = 0; i < gLPos.length(); ++i) {
		if ((gLExtract[i] > 0.f) && (gLPos[i].distance2D(s) < reach))
			m += gLIncome[i] * IncomeMult() * gLExtract[i] * hz;
	}
	return m;
}

// How many mexes of ours are standing. A claim that has not finished has no
// extraction and is not one.
int OwnMexCount()
{
	int n = 0;
	for (uint i = 0; i < gLExtract.length(); ++i) {
		if (gLExtract[i] > 0.f)
			++n;
	}
	return n;
}

// Is this position one of our standing mexes? Diagnostics only: it is how
// "did it cover the spot it was standing on" is read off a log.
bool SiteIsMex(const AIFloat3& in pos)
{
	for (uint i = 0; i < gLPos.length(); ++i) {
		if ((gLExtract[i] > 0.f) && (gLPos[i].distance2D(pos) < 200.f))
			return true;
	}
	return false;
}

// Would a post here cover a standing mex? The per-mex floor is a claim about
// mexes, and a guard site is the value-weighted centre of a cluster rather
// than the extractor itself, so the floor asks about reach and not identity.
bool MexInReach(const AIFloat3& in pos, float r)
{
	for (uint i = 0; i < gLPos.length(); ++i) {
		if ((gLExtract[i] > 0.f) && (gLPos[i].distance2D(pos) < r))
			return true;
	}
	return false;
}

// Static ground defence we own, in metal.
float DefenceValue()
{
	float m = 0.f;
	for (uint i = 0; i < gProtDefId[PROT_DEF].length(); ++i)
		m += Catalog::gCostM[gProtDefId[PROT_DEF][i]];
	return m;
}

// What the wave arriving at OUR ground is worth, less the share our own mobile
// army answers, converted to turret metal at the same exchange rate coverage
// uses. Everything here is measured at home: a player nothing reaches wants no
// turrets, which is the whole of the rear specialist's case.
float gMexFloorSum = 0.f;
int gMexFloorSumAt = -999999;

float DefenceTarget()
{
	if (!Builder::gHomeSet)
		return 0.f;
	// HOW MUCH DEFENCE WE MAY OWN IS AN ECONOMIC QUESTION. Where a post goes
	// and whether it is worth building is the threat question, and it is asked
	// per site below; this is only the size of the standing holding.
	//
	// It used to be (expected wave - our own army x share) / trade, which made
	// our own army cancel the target: measured at 400 metal/s with a 38k army,
	// the whole static-defence budget came to 2,817 metal -- less than one
	// Pulsar -- and TargetFill then returned a hard zero, so ground defence
	// switched off for the rest of the game. That is also backwards about
	// where the army is: a fielded army is out on the line, which is precisely
	// why the base needs guns of its own.
	//
	// apexearth chose the economy as the basis (2026-08-27), the same one
	// ProposeSuper already budgets against. Seconds of economic power, so it
	// scales with income at every stage and needs no cap: at 40 metal/s it is
	// a handful of light towers, at 400 it can carry a heavy gun.
	const float hold = ai.GetTunable("apex_def_eco_s", TUNE_DEF_ECO_S);
	float t = EcoPowerM() * ((hold > 0.f) ? hold : 30.f);
	if (EcoRoleActive())
		t *= ai.GetTunable("apex_eco_def_mul", TUNE_ECO_DEF_MUL);
	// ...and the per-mex floor is a target too. The site loop will not buy a
	// turret the global target says we already have enough of, so the two must
	// agree about the floor or it never gets built -- and the floor applies to
	// the rear specialist as well, whose ground is where the economy lives.
	// SCALED floors summed, not flat-floor x count: the site loop now asks
	// for MexFloorFactor at each mex, and the global allowance must deflate
	// with the rear floors or it licenses spend the sites no longer request.
	if (ai.frame >= gMexFloorSumAt + 5 * SECOND) {
		gMexFloorSumAt = ai.frame;
		float fsum = 0.f;
		for (uint i = 0; i < gLPos.length(); ++i) {
			if (gLExtract[i] > 0.f)
				fsum += MexFloorFactor(gLPos[i]);
		}
		gMexFloorSum = MexCoverFloorM() * fsum;
	}
	if (gMexFloorSum > t)
		t = gMexFloorSum;
	return (t > 0.f) ? t : 0.f;
}

// How much of each target is still unmet, as a fraction. The want's gain is
// scaled by this, so the last turret before the target prices at nearly
// nothing and the first one after it prices at zero -- the same shape as the
// army gap, and the reason neither runs away.
float TargetFill(float have, float target)
{
	if (target <= 0.f)
		return 0.f;
	const float gap = target - have;
	if (gap <= 0.f)
		return 0.f;
	return (gap > target) ? 1.f : (gap / target);
}

// ENEMY LRPCs SEEN, whole map, cached -- his ruling: "if enemy has LRPC we
// need to build shields." The def set is derived, not named: every
// non-stockpile superweapon of any faction (IsSuperWeapon), counted by
// CountEnemyDefNear from map center -- the silo detector's pattern
// (nukes.as EnemyNukeSilos). Not cached across frames beyond 10s: the
// availability-derived range threshold inside IsSuperWeapon must not latch.
int gFoeLrpcN = 0;
int gFoeLrpcNext = 89;   // phase offset -- see AiUpdate lockstep note
float gFoeLrpcCost = 0.f;

int EnemyLRPCs()
{
	if (ai.frame < gFoeLrpcNext)
		return gFoeLrpcN;
	gFoeLrpcNext = ai.frame + 10 * SECOND;
	const float w = float(AiTerrainWidth());
	const float h = float(AiTerrainHeight());
	AIFloat3 mid(w * 0.5f, 0.f, h * 0.5f);
	const float r = sqrt(w * w + h * h) * 0.5f + 1.f;
	int n = 0;
	float cost = 0.f;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!IsSuperWeapon(d) || Catalog::gStock[d])
			continue;
		CCircuitDef@ cd = Catalog::Def(d);
		if (cd is null)
			continue;
		const int k = ai.CountEnemyDefNear(cd.id, mid, r);
		if (k > 0) {
			n += k;
			cost += float(k) * Catalog::gCostM[d];
		}
	}
	if ((n > 0) && (gFoeLrpcN == 0))
		AiLog("apex: enemy LRPC seen t=" + ai.teamId + " n=" + n
			+ " cost=" + int(cost));
	gFoeLrpcN = n;
	gFoeLrpcCost = cost;
	return n;
}

int gNextTargetLog = 0;
void TargetLog()
{
	if (ai.frame < gNextTargetLog)
		return;
	gNextTargetLog = ai.frame + 60 * SECOND;
	AiLog("apex: targets t=" + ai.teamId
		+ " def=" + int(DefenceValue()) + "/" + int(DefenceTarget())
		+ " aa=" + int(gProtDefId[PROT_AA].length())
		+ " army=" + int(ArmyValue()) + "/" + int(ArmyTarget())
		+ " threatHome=" + int(Builder::gHomeSet ? ThreatM(Builder::gHomePos) : 0.f)
		+ " floor=" + int(ArmyTargetFull() * ai.GetTunable("apex_def_prior_share", TUNE_DEF_PRIOR_SHARE))
		+ " expo=" + formatFloat(TeamExposure(), "", 0, 2)
		+ " ourArmy=" + int(ArmyValue())
		+ " share=" + formatFloat(AnswerShare(), "", 0, 2)
		+ " eco=" + (EcoRoleActive() ? 1 : 0));
}
}  // namespace Market
