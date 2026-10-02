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

// THE ROWS THAT ACTUALLY EXTRACT. gLPos is the whole claim ledger -- measured
// 113 rows late in a 16-AI hour, 255 at the top -- and every mex question below
// is about the one to four of them standing. Each walked all 113 to find them,
// once per candidate site of every fill. gLStamp moves when a row is added or
// dropped and gOwnStamp when a mex finishes or dies (NoteFinished writes
// gLExtract between the two), so the pair covers every transition of the set.
array<int> gMexRow;
int gMexRowL = -1;
int gMexRowO = -1;

const array<int>@ MexRows()
{
	if ((gMexRowL != gLStamp) || (gMexRowO != gOwnStamp)) {
		gMexRowL = gLStamp;
		gMexRowO = gOwnStamp;
		gMexRow.resize(0);
		uint nr = gLExtract.length();
		if (gLPos.length() < nr)
			nr = gLPos.length();   // every reader indexes gLPos with these
		for (uint i = 0; i < nr; ++i) {
			if (gLExtract[i] > 0.f)
				gMexRow.insertLast(int(i));
		}
	}
	return gMexRow;
}

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
int   gMexEarlyAt = -999999;   // the screen term is per frame, not per site
float gMexEarly = 0.f;
bool  gMexEarlyOk = false;

float MexFloorFactor(const AIFloat3& in pos)
{
	if (gMexEarlyAt != ai.frame) {
		gMexEarlyAt = ai.frame;
		const float screen = ai.GetTunable("apex_leak_screen_m",
				TUNE_LEAK_SCREEN_M);
		gMexEarlyOk = (screen > 1.f);
		gMexEarly = gMexEarlyOk ? (1.f - ArmyValue() / screen) : 0.f;
	}
	// The floor is the guns the spot earns (MexGunsWanted), in light-tower
	// cover: one gun's worth at home, four at the doorstep. The old shape
	// (fwd * (1 + 1.5 fwd)) topped out at a gun and a quarter, so the cover
	// jump stopped after the first tower wherever the mex stood.
	float f = float(MexGunsWanted(pos));
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
	//
	// The screen term does not depend on `pos`, and ArmyValue walks the whole
	// def table -- so the site loop paid a table walk per candidate site per
	// def per builder for one number. Held on the frame, the same way RiskFill
	// holds the side-wide half of every risk reading. Read at the top.
	if (gMexEarlyOk && (gMexEarly > f))
		f = gMexEarly;
	return f;
}

// THE MEX'S VALUE IS ITS STREAM, not its 50-metal shell (apexearth
// 2026-08-28: "we run around building a lot of mexes but we lose them all
// to enemies" -- the guard want priced insurance on the shell, came out at
// v=0.01-2.7, and lost every decide roulette: 677 site-auction wins, zero
// decide wins, 14 towers, none at a mex, in one watched game). The
// extraction in reach, capitalized over the same amortization horizon
// reclaim uses, is what a guard actually protects.
float MexWorthHorizon()
{
	const float hzS = ai.GetTunable("apex_reclaim_amort", TUNE_RECLAIM_AMORT);
	return (hzS > 1.f) ? hzS : 300.f;
}

float MexStreamM(const AIFloat3& in s, float reach)
{
	const float hz = MexWorthHorizon();
	const float mult = IncomeMult();   // one handicap, not one per spot
	float m = 0.f;
	const array<int>@ rows = MexRows();
	for (uint q = 0; q < rows.length(); ++q) {
		const uint i = uint(rows[q]);
		if (gLPos[i].distance2D(s) < reach)
			m += gLIncome[i] * mult * gLExtract[i] * hz;
	}
	return m;
}

// How many mexes of ours are standing. A claim that has not finished has no
// extraction and is not one.
int OwnMexCount()
{
	return int(MexRows().length());
}

// Is this position one of our standing mexes? Diagnostics only: it is how
// "did it cover the spot it was standing on" is read off a log.
// The nearest extracting mex of ours within r of pos; off-map when none.
AIFloat3 NearestMex(const AIFloat3& in pos, float r)
{
	AIFloat3 best(-1.f, 0.f, -1.f);
	float bestD = r;
	const array<int>@ rows = MexRows();
	for (uint q = 0; q < rows.length(); ++q) {
		const float d = gLPos[uint(rows[q])].distance2D(pos);
		if (d < bestD) {
			bestD = d;
			best = gLPos[uint(rows[q])];
		}
	}
	return best;
}

bool SiteIsMex(const AIFloat3& in pos)
{
	const array<int>@ rows = MexRows();
	for (uint q = 0; q < rows.length(); ++q) {
		if (gLPos[uint(rows[q])].distance2D(pos) < 200.f)
			return true;
	}
	return false;
}

// Would a post here cover a standing mex? The per-mex floor is a claim about
// mexes, and a guard site is the value-weighted centre of a cluster rather
// than the extractor itself, so the floor asks about reach and not identity.
// ONE TURRET PER MEX, NOT A COVER QUOTA.
//
// apexearth 2026-09-02: "I want to see 1 sentry turret guarding each of our
// mexes at least. I don't want to see us making tons of turrets around mexes in
// the back of the map."
//
// The floor is a THREAT floor, so a site keeps pricing above zero until enough
// COVER accumulates -- and "enough" is measured in cover, never in turrets.
// Measured at 10 minutes: teams holding 15 turrets for 4 and 7 mexes, up to
// FOUR on a single extractor, while other mexes stood naked. This asks the
// question he actually asked: does a mex in reach still have NO gun of its own?
// GUNS A MEX EARNS BY WHERE IT STANDS (apexearth 2026-09-17, on BARb's 6.1k
// of towers against our 2.2k by minute 10 and 19 mexes to our 10 at minute
// 4: "they always defend their mexes... the further from home the more
// defenses the mex needs"). One at home, up to 1 + apex_mex_guard_far at the
// enemy's doorstep, by the spot's forward fraction.
int MexGunsWanted(const AIFloat3& in pos)
{
	float fwd = Military::ForwardFraction(pos);
	if (fwd < 0.f)
		fwd = 0.f;
	if (fwd > 1.f)
		fwd = 1.f;
	const float far = ai.GetTunable("apex_mex_guard_far", TUNE_MEX_GUARD_FAR);
	return 1 + int(fwd * ((far > 0.f) ? far : 0.f));
}

bool MexUnguardedInReach(const AIFloat3& in pos, float r)
{
	// THE NEAREST MEX, NOT ANY MEX. Asking "is some mex in reach unguarded"
	// keeps the floor switched on for every site in a cluster as long as ONE
	// extractor anywhere nearby lacks a gun -- so the subsidy lands again and
	// again on whichever site the auction likes best, which is the one already
	// guarded. Measured after the first attempt: up to FIVE turrets on one mex
	// and three to five stacked extractors a team, worse than before the fix.
	//
	// A site defends the mex it is closest to. That is the one whose guard
	// status decides whether this site is buying a first gun or a fourth.
	int near = -1;
	float bestD = -1.f;
	const array<int>@ rows = MexRows();
	for (uint q = 0; q < rows.length(); ++q) {
		const uint i = uint(rows[q]);
		const float d = gLPos[i].distance2D(pos);
		if (d >= r)
			continue;
		if ((bestD < 0.f) || (d < bestD)) {
			bestD = d;
			near = int(i);
		}
	}
	if (near < 0)
		return false;
	// Standing and ordered guns together against what the spot earns: the
	// ledger holds both, and a gun in flight is a gun (see below).
	int have = 0;
	const int wanted = MexGunsWanted(gLPos[near]);
	for (uint t = 0; t < gProtPos[PROT_DEF].length(); ++t) {
		if (gProtPos[PROT_DEF][t].distance2D(gLPos[near]) < r)
			++have;
	}
	if (have >= wanted)
		return false;
	// A GUN ORDERED IS A GUN. gProtPos holds FINISHED towers only, and a light
	// tower takes long enough to build that half a dozen more get ordered at
	// the same mex before the first one stands -- which is exactly the stack
	// he is looking at (five on one extractor). Every duplicate-purchase bug in
	// this AI's history has been a want priced inside that window, and the
	// commitment ledger is the answer to all of them: it holds ordered, framed
	// and finished alike.
	// Any match ends it, so bucket order costs nothing; the same test runs on
	// the rows the box hands back.
	ComNear(gLPos[near], r);
	for (uint q = 0; q < gComGrid.hit.length(); ++q) {
		const uint c = uint(gComGrid.hit[q]);
		const int cd = gComDef[c];
		if (!Catalog::ValidId(cd) || Catalog::gMobile[cd]
			|| (ProtClassOf(cd) != PROT_DEF) || !OnMap(gComPos[c]))
			continue;
		if ((gComState[c] != CS_FINISHED) && (gComPos[c].distance2D(gLPos[near]) < r))
			++have;   // on its way
	}
	return have < wanted;
}

// WHERE THE ENEMY'S BASE IS, for defence geometry: the mirror of the team's
// homes about the map centre -- the symmetric-start prior Base::Frame and
// GradAt already stand on.
//
// Not the live centroid: aiEnemyMgr.GetEnemyPos() answers (0,0,0) until
// something has been seen, and that IS on-map, so the wall's line and the
// pull's facing were aimed at the map corner for the whole opening, and every
// tower stood behind the base. And not the remembered centroid either:
// Front::FoeMid is the memory of every cell their influence has touched, raids
// into our own base included, so the line's perpendicular swings with the last
// fight and its lateral slots wander. Their base does not move; the line
// should not either.
bool FoeRefRaw(AIFloat3& out at)
{
	if (!Builder::gHomeSet)
		return false;
	float cx = Builder::gHomePos.x;
	float cz = Builder::gHomePos.z;
	float n = 1.f;
	array<Id>@ mates = ai.GetTeamIds();
	for (uint i = 0; (mates !is null) && (i < mates.length()); ++i) {
		if (int(mates[i]) == ai.teamId)
			continue;
		const float mx = ai.ReadTeamValue(int(mates[i]), "homex", -1.f);
		const float mz = ai.ReadTeamValue(int(mates[i]), "homez", -1.f);
		if ((mx < 0.f) || (mz < 0.f))
			continue;
		cx += mx;
		cz += mz;
		n += 1.f;
	}
	at = AIFloat3(float(AiTerrainWidth()) - cx / n, 0.f,
			float(AiTerrainHeight()) - cz / n);
	if (OnMap(at) && (at.distance2D(Builder::gHomePos) > 1.f))
		return true;
	at = aiEnemyMgr.GetEnemyPos();
	return OnMap(at) && ((at.x > 1.f) || (at.z > 1.f));
}

// THEIR BASE DOES NOT MOVE INSIDE A FRAME. Every read above is an engine call
// -- the team id list, then a published value per teammate -- and the defence
// loop asks this once per candidate site, so a 16-player game paid fifteen
// cross-team reads per slot per def per builder for one fixed point.
int      gFoeRefAt = -999999;
bool     gFoeRefOk = false;
AIFloat3 gFoeRefP;

bool FoeRef(AIFloat3& out at)
{
	if (gFoeRefAt != ai.frame) {
		gFoeRefAt = ai.frame;
		gFoeRefOk = FoeRefRaw(gFoeRefP);
	}
	at = gFoeRefP;
	return gFoeRefOk;
}

// ONE CANDIDATE SITE AT EACH MEX THAT HAS NO GUN. The wall offers slots on the
// building rim, so a mex's own ground was never for sale: the floor had
// nothing to price and the cover-push nothing to promote. The site sits a step
// toward the enemy so the gun covers the approach; a mex whose gun already
// stands or is ordered offers nothing, so this ends by itself.
void MexGuardSites(array<AIFloat3>& inout sites, float reach)
{
	AIFloat3 foe;
	const bool foeOk = FoeRef(foe);
	const array<int>@ rows = MexRows();
	for (uint q = 0; q < rows.length(); ++q) {
		const uint i = uint(rows[q]);
		if (!OnMap(gLPos[i]))
			continue;
		if (!MexUnguardedInReach(gLPos[i], reach))
			continue;
		AIFloat3 s = gLPos[i];
		if (foeOk) {
			AIFloat3 dir = foe - gLPos[i];
			if (dir.SqLength2D() > 1.f) {
				dir.SafeNormalize2D();
				const AIFloat3 s2 = gLPos[i] + dir * 150.f;
				if (OnMap(s2))
					s = s2;
			}
		}
		sites.insertLast(s);
	}
}

bool MexInReach(const AIFloat3& in pos, float r)
{
	const array<int>@ rows = MexRows();
	for (uint q = 0; q < rows.length(); ++q) {
		if (gLPos[uint(rows[q])].distance2D(pos) < r)
			return true;
	}
	return false;
}

// A PRODUCTION LINE IS WORTH COVERING BEFORE ANYTHING HAS SHOT AT IT.
//
// apexearth, three times tonight and again just now: "they don't make a turret
// before walking away from the first things that they've made and it becomes an
// issue every game. A panic to defend themselves because they didn't make a
// single LLT."
//
// The mechanism is the one apex_mex_cover_floor already exists to answer, one
// building over: every defence site is priced on MEASURED threat, and at minute
// two there is no measured threat, so every candidate is gated out at
// GATE_SITE_THREAT and nothing is ever worth building -- until the raid
// arrives, which is exactly too late. The mex floor fixes that for extractors
// and only for extractors: the floor is applied where MexInReach(s) is true, so
// a slot beside the lab, with no mex in range, still prices against a wave of
// zero.
//
// A lab is worth several mexes and is the thing whose loss ends the game, so it
// takes the same floor. Same wave, same exposure scaling -- this widens what
// counts as worth covering, it does not invent a second mechanism.
bool PlantInReach(const AIFloat3& in pos, float r)
{
	// Any match ends it, so bucket order costs nothing.
	ComNear(pos, r);
	for (uint q = 0; q < gComGrid.hit.length(); ++q) {
		const uint i = uint(gComGrid.hit[q]);
		const int d = gComDef[i];
		if (!Catalog::ValidId(d) || Catalog::gMobile[d]
			|| (Catalog::gBuildsList[d].length() == 0))
			continue;   // not a plant
		if (Catalog::gBuildPower[d] <= 0.f)
			continue;   // a plant, not a turret with a build list
		if (OnMap(gComPos[i]) && (gComPos[i].distance2D(pos) < r))
			return true;
	}
	return false;
}

// Static ground defence we own, in metal. Memoised on the frame: the census it
// sums only moves on a unit event, and the protect market asks it several
// times per candidate per election, once per tower we own each time.
float gDefValM = 0.f;
int   gDefValAt = -999999;

float DefenceValue()
{
	if (gDefValAt == ai.frame)
		return gDefValM;
	gDefValAt = ai.frame;
	float m = 0.f;
	for (uint i = 0; i < gProtDefId[PROT_DEF].length(); ++i)
		m += Catalog::gCostM[gProtDefId[PROT_DEF][i]];
	gDefValM = m;
	return m;
}

// 0 on target, 1 with nothing standing.
float DefenceShortfall()
{
	const float tgt = DefenceTarget();
	if (tgt <= 0.f)
		return 0.f;
	const float f = DefenceValue() / tgt;
	return (f >= 1.f) ? 0.f : 1.f - f;
}

// Tower metal already ordered. The gap that drives the pull counted only
// standing towers, so every slot kept asking at full gap while ten were framed.
// The defence target split like the army (docs/24, 2026-09-28): where our
// land is cut off, the water's share of it is held only by floating guns --
// torpedo launchers and floating towers out from our shore, so a yard stands.
// WHERE THE NEXT FLOATING GUN GOES (his watch 2026-09-28: three torpedo
// launchers side by side, and an enemy mex taken in our water we could
// neither see nor kill). The yard's front and every water mex spot within the
// eco leash of home are candidates; one a water gun of ours (standing or
// ordered) already covers is not. The asker takes the nearest uncovered one.
bool WaterGunCovers(const AIFloat3& in p, float cover)
{
	for (uint i = 0; i < gProtDefId[PROT_DEF].length(); ++i) {
		const int d = gProtDefId[PROT_DEF][i];
		if ((Catalog::gFloater[d] || Catalog::gSub[d])
			&& (gProtPos[PROT_DEF][i].distance2D(p) < cover))
			return true;
	}
	for (uint i = 0; i < Requests::gLive.length(); ++i) {
		IUnitTask@ t = Requests::gLive[i];
		if ((t is null) || (t.buildDef is null))
			continue;
		const int d = int(t.buildDef.id);
		if ((ProtClassOf(d) == PROT_DEF) && (Catalog::gFloater[d] || Catalog::gSub[d])
			&& OnMap(t.GetBuildPos()) && (t.GetBuildPos().distance2D(p) < cover))
			return true;
	}
	return false;
}

AIFloat3 WaterGunAnchor(int d, const AIFloat3& in yardFront, const AIFloat3& in here)
{
	float cover = Catalog::gMaxRange[d];
	if (cover < 200.f)
		cover = 200.f;
	cover *= 0.8f;
	const float leash = ai.GetTunable("apex_eco_leash", TUNE_ECO_LEASH);
	AIFloat3 best(-1.f, 0.f, -1.f);
	float bestD = 0.f;
	for (int k = -1; k < int(gAllSpots.length()); ++k) {
		const AIFloat3 c = (k < 0) ? yardFront : gAllSpots[k];
		if (!OnMap(c))
			continue;
		if ((k >= 0) && ((ai.GetElevationAt(c) >= 0.f) || !Builder::gHomeSet
				|| (c.distance2D(Builder::gHomePos) > leash)))
			continue;
		// Only water a hull sails into: a mex in a lake beside the base is
		// guarded by nothing an enemy boat can reach.
		if ((k >= 0) && gWcBuilt && !SailableWaterNear(c, 400.f))
			continue;
		if (WaterGunCovers(c, cover))
			continue;
		const float dd = c.distance2D(here);
		if (!OnMap(best) || (dd < bestD)) {
			best = c;
			bestD = dd;
		}
	}
	return best;
}

int WaterTorpHave()
{
	int n = 0;
	for (uint i = 0; i < gProtDefId[PROT_DEF].length(); ++i) {
		const int d = gProtDefId[PROT_DEF][i];
		if ((Catalog::gFloater[d] || Catalog::gSub[d]) && (Catalog::gWaterT[d] > 0.01f))
			++n;
	}
	return n;
}

float WaterDefenceHave()
{
	float have = 0.f;
	for (uint i = 0; i < gProtDefId[PROT_DEF].length(); ++i) {
		const int d = gProtDefId[PROT_DEF][i];
		if (Catalog::gFloater[d] || Catalog::gSub[d])
			have += Catalog::gCostM[d];
	}
	return have;
}

float WaterDefenceGap()
{
	const float share = NavyShare();
	if ((share <= 0.f) || !WaterReachesFoe())
		return 0.f;
	float have = WaterDefenceHave();
	for (uint i = 0; i < Requests::gLive.length(); ++i) {
		IUnitTask@ t = Requests::gLive[i];
		if ((t is null) || (t.buildDef is null))
			continue;
		const int d = int(t.buildDef.id);
		if ((ProtClassOf(d) == PROT_DEF) && (Catalog::gFloater[d] || Catalog::gSub[d]))
			have += Catalog::gCostM[d];
	}
	const float gap = DefenceTarget() * share - have;
	return (gap > 0.f) ? gap : 0.f;
}

float gDefFlyM = 0.f;
int   gDefFlyAt = -999999;

float DefenceInFlightM()
{
	if (gDefFlyAt == ai.frame)
		return gDefFlyM;
	gDefFlyAt = ai.frame;
	float m = 0.f;
	for (uint i = 0; i < Requests::gLive.length(); ++i) {
		IUnitTask@ t = Requests::gLive[i];
		if ((t is null) || (t.buildDef is null))
			continue;
		const int d = int(t.buildDef.id);
		if (ProtClassOf(d) == PROT_DEF)
			m += Catalog::gCostM[d];
	}
	gDefFlyM = m;
	return m;
}

// What the wave arriving at OUR ground is worth, less the share our own mobile
// army answers, converted to turret metal at the same exchange rate coverage
// uses. Everything here is measured at home: a player nothing reaches wants no
// turrets, which is the whole of the rear specialist's case.
float gMexFloorSum = 0.f;
int gMexFloorSumAt = -999999;
// Memoised on the frame for the same reason DefenceValue is: EcoPowerM walks
// the def table and this is asked once per defence candidate.
float gDefTgtM = 0.f;
int   gDefTgtAt = -999999;

float DefenceTarget()
{
	if (gDefTgtAt == ai.frame)
		return gDefTgtM;
	gDefTgtAt = ai.frame;
	gDefTgtM = 0.f;
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
	// THE REAR SPECIALIST BUILDS NO DEFENCE WHILE IT GROWS (apexearth
	// 2026-09-13, watching the eight-player seat: "they spend huge on
	// defenses. Almost 10k on defenses spent by minute 13, we would eco so
	// much faster if we didn't do that"). His 2026-09-02 correction went the
	// other way on a 4v4 where no seat was safe; the raid valve
	// (EcoDangerNear) is what ends the growth when the seat is not safe
	// after all, and the anti-nuke and the AA emergency are not this target.
	// ...ramping in from half the seat's target (EcoRoleRamp).
	float ecoRamp = 1.f;
	if (EcoRoleGrowing()) {
		ecoRamp = EcoRoleRamp();
		if (ecoRamp <= 0.f)
			return 0.f;
	}
	// N% OF WHAT WE HOLD, not N seconds of what we earn (apexearth: "we should
	// want our economy to be N% of our overall power, we want to keep all of
	// our aspects in balance with each other"). Seconds of income says nothing
	// about the size of the thing being guarded, and outruns it as income
	// grows: measured on Greenest Fields the target reached 6,615 while the
	// whole economy it protects stood at 5,478. The share is the budget's own
	// defence row, normalised against every other row, so the aspects are
	// balanced against each other instead of each against itself -- and
	// turrets count inside the total they are measured against, so defence
	// cannot become its own reason.
	float t = (gAssetsM + ArmyValue()) * Brain::TargetShare(Brain::DEFENCE);
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
		const array<int>@ rows = MexRows();
		for (uint q = 0; q < rows.length(); ++q)
			fsum += MexFloorFactor(gLPos[uint(rows[q])]);
		gMexFloorSum = MexCoverFloorM() * fsum;
	}
	if (gMexFloorSum > t)
		t = gMexFloorSum;
	gDefTgtM = ((t > 0.f) ? t : 0.f) * Persona::Trait(Persona::T_DEF) * ecoRamp;
	return gDefTgtM;
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

// REMEMBERED, THEN FADED (apexearth 2026-09-06: "remember it, fade if nothing
// shells us"). EnemyLRPCs counts what CountEnemyDefNear can SEE, and an LRPC
// sits deep in their base where we almost never have eyes, so the raw census
// flickers to zero and the shield gates refuse. Air gets a permanent latch;
// a plasma cannon must not, because it is static and can be killed. Decay uses
// the loss ledger's own BLEED_TAU rather than a new horizon.
float gLrpcEverCost = 0.f;
int   gLrpcHoldAt = -1;

float LrpcStake()
{
	if (EnemyLRPCs() > 0) {
		if (gFoeLrpcCost > gLrpcEverCost)
			gLrpcEverCost = gFoeLrpcCost;
		gLrpcHoldAt = ai.frame;
		return gLrpcEverCost;
	}
	if (gLrpcEverCost <= 0.f)
		return 0.f;
	if (Military::PlasmaLossRate() > 0.f) {
		gLrpcHoldAt = ai.frame;
		return gLrpcEverCost;
	}
	if (gLrpcHoldAt < 0)
		gLrpcHoldAt = ai.frame;
	const float since = float(ai.frame - gLrpcHoldAt) / float(SECOND);
	float k = 1.f - (since / Military::BLEED_TAU);
	if (k <= 0.f) {
		gLrpcEverCost = 0.f;
		gLrpcHoldAt = -1;
		return 0.f;
	}
	return gLrpcEverCost * k;
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
