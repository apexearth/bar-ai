namespace Factory {

// The advanced plant has to be one our own constructors can actually build --
// AdvCounterpart() below matches by T1_FAC index, so an entry here must be
// buildable by that same T1 factory's own constructor.
// Index-paired: T2_FAC[i] is the advanced counterpart of T1_FAC[i]. corasy
// appears twice because it serves both Cortex and Legion; that is safe because
// AdvCounterpart returns on the first T1_FAC name match and OwnAdvProgress takes
// a max over the whole array.
// legap/legaap are deliberately NOT in these arrays -- no confirmed win-rate
// effect either way once retested at power. See notes/open-issues.md #38/#45/#47
// before re-adding.
array<string> T1_FAC = {armlab, armvp, armsy, armap,
                        corlab, corvp, corsy, corap,
                        leglab, legvp, legsy};
array<string> T2_FAC = {armalab, armavp, armasy, armaap,
                        coralab, coravp, corasy, coraap,
                        legalab, legavp, corasy};

// Do we own OR are we building any advanced plant? GetDefBuildProgress is -1
// only when we hold none of that def at all, so a nanoframe counts -- which is
// the point: gHaveT2 must not drop while a replacement is going up, or the
// !gHaveT2 rebuild branch starts a second one. Unlike OwnAdvProgress this does
// NOT skip air plants; the question here is "do we hold the tier", not "is this
// player a credible ground-push tech lead".
bool AnyAdvPlant()
{
	for (uint i = 0; i < T2_FAC.length(); ++i) {
		CCircuitDef@ def = ai.GetCircuitDef(T2_FAC[i]);
		if ((def !is null) && (ai.GetDefBuildProgress(def) >= 0.f))
			return true;
	}
	return false;
}

// Our best progress toward an advanced plant, 0..1, or -1 if we hold none.
// Nanoframes count -- commitment is the question the election asks, and the
// fraction is what separates two teams that have both committed.
//
// Air plants are skipped: the team pools its metal expecting a T2 ground push,
// which an air plant cannot deliver. The previous election excluded air leads
// for the same reason.
//
// Declared here rather than beside the election because T2_FAC is a global, and
// AngelScript needs globals declared before use. Functions are order-free.
float OwnAdvProgress()
{
	float best = -1.f;
	for (uint i = 0; i < T2_FAC.length(); ++i) {
		CCircuitDef@ def = ai.GetCircuitDef(T2_FAC[i]);
		if ((def is null) || IsAirFactory(def))
			continue;
		const float p = ai.GetDefBuildProgress(def);
		if (p > best)
			best = p;
	}
	return best;
}

// Two reasons to refuse an air OPENING: on a small team, one of four players
// contributing no ground army is a quarter of the team missing; on any team
// size, the team pools metal into the lead expecting a T2 ground push, which an
// air opening cannot deliver. Gates the opening factory only -- a later air
// plant, once the ground game is established, is left alone.
const uint BIG_TEAM = 6;   // same threshold the rush attack quota uses

array<string> AIR_FAC = {armap, armaap, corap, coraap, legap, legaap};

bool IsSmallTeam()
{
	array<Id>@ mates = ai.GetTeamIds();
	return (mates is null) || (mates.length() < BIG_TEAM);
}

// const handle: CCircuitUnit::circuitDef is a const CCircuitDef@, and a
// non-const parameter refuses it outright. The other two callers pass mutable
// handles, which a const parameter still accepts.
array<string> NAVAL_FAC = {armsy, armasy, corsy, corasy, legsy};

bool IsNavalFactory(const CCircuitDef@ def)
{
	if (def is null)
		return false;
	const string n = def.GetName();
	for (uint i = 0; i < NAVAL_FAC.length(); ++i) {
		if (NAVAL_FAC[i] == n)
			return true;
	}
	return false;
}

bool IsAirFactory(const CCircuitDef@ def)
{
	if (def is null)
		return false;
	const string name = def.GetName();
	for (uint i = 0; i < AIR_FAC.length(); ++i) {
		if (AIR_FAC[i] == name)
			return true;
	}
	return false;
}

// At most ONE air opening per ally team on a big team.
//
// Each instance decides its opening alone from the same map data, so on an 8v8
// several would pick air independently. One slot is chosen deterministically
// from the ally roster instead -- every instance computes the same answer at
// frame 0, with no signalling. Highest team id, to avoid landing on the same
// player as the engine's GetLeadTeamId (the early tech lead).
//
// A cap, not a quota: if the slot holder does not want air, the team opens
// none.
int AirSlotTeamId()
{
	array<Id>@ mates = ai.GetTeamIds();
	if ((mates is null) || (mates.length() == 0))
		return -1;
	// The eco lead builds no combat units at all, so handing it the team's one
	// air slot means the air plant produces constructors and nothing else.
	// RushLeadTeamId is the eco lead: IsEcoLead() is
	// IsDesignatedLead() && (teamId == RushLeadTeamId()).
	const int lead = RushLeadTeamId();
	int slot = -1;
	for (uint i = 0; i < mates.length(); ++i) {
		const int cand = int(mates[i]);
		if ((cand != lead) && (cand > slot))
			slot = cand;
	}
	return slot;   // -1 when the lead is the only candidate: no air rather than dead air
}

// May this instance open with an air factory at all?
bool MayOpenAir()
{
	if (IsSmallTeam())
		return false;             // under BIG_TEAM: nobody opens air
	if (IsDesignatedLead())
		return false;             // the rusher techs on the ground
	return ai.teamId == AirSlotTeamId();
}

// Ground opening when the default picks air. An even bot/vehicle split; bots
// climb terrain vehicles cannot and carry the rez bot, vehicles bring the
// heavier guns on open ground.
// ALONE ON AN ISLAND, LAND ARMY IS DEAD WEIGHT -- apexearth: "make our AI
// smart enough to not make land army when it is on an island alone." The
// question is the terrain analysis's own: can this side's basic tank WALK
// from home to the enemy? Cached once the answer is real (both positions
// known); re-asked until then. When false, the opening goes naval/air and
// the T1 core skips land roles (see facqueue's use).
int gIslandState = -1;   // -1 unknown, 0 connected, 1 island

bool AloneOnIsland()
{
	if (gIslandState >= 0)
		return gIslandState == 1;
	if (!Builder::gHomeSet)
		return false;
	const AIFloat3 e = aiEnemyMgr.GetEnemyPos();
	if (!OnMap(e))
		return false;
	CCircuitDef@ walker = SideDef3("armstump", "corraid", "leggob");
	if (walker is null)
		@walker = SideDef3("armpw", "corak", "leggob");
	if (walker is null)
		return false;
	gIslandState = ai.CanDefReach(walker, Builder::gHomePos, e) ? 0 : 1;
	if (gIslandState == 1)
		AiLog(Factory::T() + "apex: ISLAND START -- no land path to the enemy,"
			+ " land army suppressed");
	return gIslandState == 1;
}

CCircuitDef@ GroundOpening()
{
	const string side = ai.GetSideName();
	// 50/50, was 3-in-4 bots -- apexearth: "we never seem to care about
	// vehicles." Rolled per call; only the first factory ever consumes it.
	const bool wantBots = (AiRandom(0, 99) < 50);
	if (side == "cortex")
		return ai.GetCircuitDef(wantBots ? corlab : corvp);
	if (side == "legion")
		return ai.GetCircuitDef(wantBots ? leglab : legvp);
	return ai.GetCircuitDef(wantBots ? armlab : armvp);
}

// The overrides below run ahead of the engine's own pick and all name land defs,
// so each needs a water branch or it silently replaces a naval choice.
//
// 40 is factory.json's own select.min_land, the value
// CFactoryManager::GetRepresenter reads to choose a factory's water variant.
const float MIN_LAND_PCT = 40.f;

bool IsWaterMap()
{
	return !aiTerrainMgr.IsWaterAVoid()
		&& (aiTerrainMgr.GetLandPercent() < MIN_LAND_PCT);
}

// A map can carry a great deal of water and still not be a "water map".
// IsWaterMap gates on land < 40% -- the right test for the OPENING factory,
// since you do not open naval on a land majority -- but every other naval
// branch hangs off it too, so without this test the AI built no naval unit of
// any kind on a map with water in the 20-60% range.
const float NAVY_MIN_WATER_PCT = 20.f;
// A T1 shipyard is ~700 metal before a single hull comes out of it, so it waits
// for an economy rather than competing with the opening.
const float NAVY_MIN_INCOME = 15.f;
// Separate, lower floor for the ExpansionStalled() rescue case below. A player
// genuinely boxed onto a small peninsula plateaus BELOW NAVY_MIN_INCOME
// precisely because it has no more land to expand onto -- gating the escape
// valve on the same income bar it exists to unblock is a deadlock, not a
// safeguard. This is a rescue, not a luxury expansion, so it asks only for
// enough to not immediately go bankrupt building the yard.
const float NAVY_MIN_INCOME_STALLED = 6.f;
// Land share at or below which a MIXED map counts as water-heavy and uses the
// stalled floor above. Crater Islands is 63%; a 75-80% land map is not really
// a naval map and keeps the luxury bar.
const float NAVY_HEAVY_LAND_PCT = 70.f;

bool IsMixedWaterMap()
{
	return !aiTerrainMgr.IsWaterAVoid()
		&& !IsWaterMap()
		&& (aiTerrainMgr.GetLandPercent() <= (100.f - NAVY_MIN_WATER_PCT));
}

// Are we standing in the sea?
//
// Map-wide land percentage is the wrong question for the OPENING. A map can be
// mostly land and still put this player's start in the water -- an island start,
// a lagoon, the far side of a channel -- and no land factory can be placed there
// at all, whatever GetLandPercent says. The position handed to
// AiGetFactoryToBuild is where the factory would actually go, and Spring puts sea
// level at y = 0, so its height is the direct test.
//
// The margin is a judgement call, not a measurement: a commander a metre into the
// shallows can still build on land, and only a real depth means a land factory is
// impossible. Shallower than this and we keep the land opening.
const float WATER_START_DEPTH = -8.f;

// The position argument is not always resolved when isStart runs: observed
// y=-0.0 for several instances in one run and correct heights for all eight in
// another, on the same map and seed -- the DLL is multithreaded and this is a
// race. The commander is a registered unit with a real position, so prefer it and
// keep the argument as the fallback.
//
// Both readings failing means an unresolved height, which is NOT water: an
// unknown reads as 0, and 0 is above WATER_START_DEPTH, so the land opening
// stands. Missing a water start costs an opening; forcing a shipyard onto dry
// land costs the game.
bool IsWaterAt(const AIFloat3& in p)
{
	if (aiTerrainMgr.IsWaterAVoid())
		return false;
	const float y = Builder::gHomeSet ? Builder::gHomePos.y : p.y;
	return y < WATER_START_DEPTH;
}

bool HaveShipyard()
{
	CCircuitDef@ sy = NavalOpening();
	// count covers the nanoframe (RegisterTeamUnit runs for it), so one already
	// under construction cannot be re-requested.
	return (sy !is null) && (sy.count > 0);
}

CCircuitDef@ NavalOpening()
{
	return SideDef3(armsy, corsy, legsy);
}

// The opening factory, remembered so we can tech into its own advanced version.
CCircuitDef@ gT1Fac = null;

CCircuitDef@ AdvCounterpart()
{
	if (gT1Fac is null)
		return null;
	const string name = gT1Fac.GetName();
	for (uint i = 0; i < T1_FAC.length(); ++i) {
		if (T1_FAC[i] == name)
			return ai.GetCircuitDef(T2_FAC[i]);
	}
	return null;
}

// Which T2 counterpart is actually about to be built, not just the ONE
// remembered opening factory's (gT1Fac/AdvCounterpart above). A team that
// switches its active T1 factory before teching builds a DIFFERENT def's T2
// first, and AdvCounterpart keeps answering for the stale opening choice --
// silently, since it just returns a def nobody is building instead of an
// error. Measured 2026-08-15: armalab (T2 bot lab) was the actual first T2
// built, with zero "T2 plant ... at the rear" log lines for it at all (only
// armavp got them, later, after this armalab died 3.6 minutes post-completion
// -- exactly the exposed-placement report). Checks every T1 factory type we
// currently OWN a standing instance of, not just the opening one, and
// returns the first whose T2 counterpart has not yet started.
CCircuitDef@ NextT2Counterpart()
{
	for (uint i = 0; i < T1_FAC.length(); ++i) {
		CCircuitDef@ t1 = ai.GetCircuitDef(T1_FAC[i]);
		if ((t1 is null) || (t1.count <= 0))
			continue;
		CCircuitDef@ t2 = ai.GetCircuitDef(T2_FAC[i]);
		if ((t2 !is null) && (ai.GetDefBuildProgress(t2) < 0.f))
			return t2;
	}
	return null;
}

// T3 is this variant's declared win condition -- hold cheaply, out-eco behind
// the wall, then finish with T3. Gated on a real economy rather than a clock:
// starting a gantry the economy cannot finish is the same trap an unaffordable
// T2 plant was.
const float T3_METAL_INCOME = 100.f;

// Income alone is the wrong gate: a gantry is only worth starting from a
// position that is not collapsing.
//   gTurtle       -- Military sets this when our army value fell 18% in 20s
//                    while the enemy still fields a mobile force: "we are
//                    losing trades right now".
//   army vs threat -- and we should at least be matching what they field, not
//                    merely have stopped bleeding.
const float T3_ARMY_RATIO = 1.0f;

// Metal income above which the gTurtle and army-ratio vetoes stop applying, so
// a gantry gets placed even while we are losing -- at high income a gantry is
// a small fraction of one tick of income, so refusing to spend it on the
// counter to what's killing us is wrong at any army ratio. See T3Worthwhile().
const float T3_INCOME_URGENT = 150.f;

// One gantry per this much metal income, floor 1. No hard cap: the energy
// bound below and the income term are the ceiling, and both scale.
//
// gHaveT3 is a latch set the moment the first gantry appears; both build
// decisions used to test !gHaveT3, so the AI built exactly ONE gantry per game
// at any income. gHaveT3 itself stays -- military.as reads it for big-gun
// placement -- it just no longer gates whether to build another.
const float GANTRY_PER_INCOME = 100.f;
// Extra plants allowed while the bank is at the cap.
const int   GANTRY_SURPLUS_BONUS = 4;
// A gantry that is actually building draws 460-620 energy/second on its own, and
// every rung above is gated on METAL income alone, which says nothing about that.
// The bar is well above one plant's draw because the base has to keep running
// too: factories, nanos and converters are all on the same grid.
const float GANTRY_PER_ENERGY = 5000.f;

// A T1 bot lab is wanted for the whole game, not just the opening: it is the
// cheap assault spam and the only source of rez bots.
CCircuitDef@ T1BotLab()
{
	return SideDef3(armlab, corlab, leglab);
}

bool HaveT1BotLab()
{
	CCircuitDef@ lab = T1BotLab();
	// count is incremented in RegisterTeamUnit, which runs for the nanoframe, so
	// a lab already under construction counts and this cannot re-request one.
	return (lab !is null) && (lab.count > 0);
}

// Do we want another gantry? Counts nanoframes: CCircuitDef::count is
// incremented in RegisterTeamUnit, which runs for the nanoframe, so one already
// under construction is counted and this cannot double-request.
bool WantMoreGantries()
{
	CCircuitDef@ gant = T3Gantry();
	if (gant is null)
		return false;
	int want = int(aiEconomyMgr.metal.income / GANTRY_PER_INCOME);
	if (want < 1)
		want = 1;
	// A full bank means the cap is the wrong number: income says what we can
	// sustain, a full bank says we are already failing to spend what we have.
	if (aiEconomyMgr.isMetalFull)
		want += GANTRY_SURPLUS_BONUS;
	// One gantry per GANTRY_PER_ENERGY of income, and none below it.
	int engyWant = int(aiEconomyMgr.energy.income / GANTRY_PER_ENERGY);
	if (want > engyWant)
		want = engyWant;
	return int(gant.count) < want;
}

bool T3Worthwhile()
{
	const float inc = aiEconomyMgr.metal.income;
	if (inc <= T3_METAL_INCOME)
		return false;
	// Above a large economy the two vetoes below block exactly the case they
	// should permit -- enemy T3 already in the base is precisely what sets
	// gTurtle and drags our armyCost below theirs -- so they stop applying.
	if (inc >= T3_INCOME_URGENT)
		return true;
	if (Military::gTurtle)
		return false;
	return aiMilitaryMgr.armyCost >= Military::EnemyArmyCost() * T3_ARMY_RATIO;
}
bool gHaveT3 = false;

CCircuitDef@ T3Gantry()
{
	const string side = ai.GetSideName();
	// Legion deliberately falls through to the land branch below.
	if (IsWaterMap()) {
		if (side == "cortex")
			return ai.GetCircuitDef(corgantuw);
		if (side != "legion")
			return ai.GetCircuitDef(armshltxuw);
	}
	if (side == "cortex")
		return ai.GetCircuitDef(corgant);
	if (side == "legion")
		return ai.GetCircuitDef(leggant);
	return ai.GetCircuitDef(armshltx);
}

// THE ONE BIG UNIT A GANTRY IS FOR, per faction and per land/water plant.
//
// Named rather than resolved by role: GetFacRoleDef draws at random among a
// factory's role defs and skips any whose factory.json tier probability is zero,
// and the super column is 0.00 at tier0 -- so a role lookup answers null exactly
// when the plant is new. Each name is checked against that plant's own
// buildoptions; corgantuw cannot build corjugg, and Legion's heaviest carries
// role "heavy" rather than "super", so no role lookup could ever have found it.
CCircuitDef@ SuperDefFor(const CCircuitDef@ facDef)
{
	if (facDef is null)
		return null;
	const string fac = facDef.GetName();
	if (fac == corgant)
		return ai.GetCircuitDef("corjugg");
	if (fac == corgantuw)
		return ai.GetCircuitDef("corkorg");
	if ((fac == armshltx) || (fac == armshltxuw))
		return ai.GetCircuitDef("armbanth");
	if (fac == leggant)
		return ai.GetCircuitDef("legeheatraymech");
	return null;
}

}  // namespace Factory
