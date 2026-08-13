namespace Factory {

// The advanced plant has to be one our own constructors can actually build.
// Measured: the rusher opened a BOT lab, whose constructor (corck) can build
// only coralab, while this function forced coravp -- the advanced VEHICLE plant.
// All 33 rush requests in a 14-minute game asked for a factory nothing on the
// field could place, were silently dropped, and T2 never started. The earlier
// "prefer Gollums over Sumos" bias that introduced coravp here was measured on
// games where a vehicle plant happened to be the opening, so it never showed up
// as a failure -- it just quietly disabled the whole rush on bot openings.
// Index-paired: T2_FAC[i] is the advanced counterpart of T1_FAC[i]. corasy
// appears twice because it serves both Cortex and Legion; that is safe because
// AdvCounterpart returns on the first T1_FAC name match and OwnAdvProgress takes
// a max over the whole array.
// legap/legaap are deliberately NOT in these arrays. Adding them (so
// AdvCounterpart() resolves a T2 counterpart and enables the T1-lab-reclaim
// rush for Legion air openers) was tried in isolation and confirmed, clean
// and solo, as a severe regression: legion-t1fac-only-16 went 2-14 (12.5%,
// 95% CI excludes 50%) against a established clean 43.8% baseline -- worse
// than leaving the "bug" alone. Whatever the mechanism (legap/legaap's
// cost/build-time/role may make the reclaim trade bad specifically for
// Legion), this is NOT free to fix the way it looked from the code alone.
// See notes/open-issues.md #35/#37/#38. Do not re-add without a new,
// isolated, positive confirmation.
// legap/legaap are deliberately NOT in these arrays. Two independent solo
// batches (legion-t1fac-only-16: 12.5%, legion-t1fac-retest-16: 37.5%)
// pool to 25% (8/32) against Legion's own pooled baseline of 37.5%
// (12/32) -- z=-1.08, not statistically significant. This is the fully
// resolved conclusion after two rounds of testing: adding legap/legaap
// has NO confirmed effect on Legion's win rate, positive or negative,
// once properly powered. Left out (no positive evidence to keep the
// change) rather than re-added. See notes/open-issues.md #38/#45/#47 for
// the full arc of this investigation, including the initial single-batch
// result that looked like a real regression before more data resolved it.
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

// Two separate reasons to refuse an air OPENING.
//
// 1. On a small team it is simply a losing choice: "on a 4v4 nobody should go
//    air, to main air on a 4v4 is a recipe for loss -- we'd beat BARb if we just
//    did 4x ground". One of four players contributing no ground army is a
//    quarter of the team missing. On a big team one air player is affordable and
//    can be useful, so only the lead is barred there.
// 2. Air is a bad sling target regardless of team size: the team pools its metal
//    into one player expecting a T2 ground push, and an air opening cannot give
//    them one.
//
// This gates the opening factory only. A later air plant, once the ground game
// is established, is fine and is left alone.
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

// Ground opening when the default picks air.
//
// This returned the VEHICLE plant unconditionally, on a "Gollums push where
// Sumos hold" argument. Measured over two 8v8 games: apex fielded 83% and 86%
// of its army metal as vehicles, against stock's 43% and 63% as BOTS.
// apexearth: "We tend to have a high portion of our units be vehicles. Can we
// try to split more evenly?"
//
// Bots preferred, three in four. apexearth: "i think we should prefer bots".
// Keyed on team id so an ally team divides in a fixed proportion and each
// player's choice is stable across the game rather than changing if it is asked
// twice. Bots climb terrain vehicles cannot and carry the rez bot, which is the
// single biggest measured gap against stock; the remaining quarter keeps the
// heavy assault line available.
CCircuitDef@ GroundOpening()
{
	const string side = ai.GetSideName();
	const bool wantBots = ((ai.teamId % 4) != 0);
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
//
// IsWaterMap gates on land < 40%, i.e. water > 60%. That is the right test for
// the OPENING factory -- you do not open naval on a land majority -- but every
// other naval branch hangs off it too, so on anything in between the AI builds
// no naval unit of any kind. Observed on Supreme Isthmus: the boat move-types
// (boat4/boat5/boat9) cover 39-40% of the map and the side finished the game
// with zero shipyards, zero ships, and the sea uncontested.
const float NAVY_MIN_WATER_PCT = 20.f;
// A T1 shipyard is ~700 metal before a single hull comes out of it, so it waits
// for an economy rather than competing with the opening.
const float NAVY_MIN_INCOME = 15.f;
// Separate, lower floor for the ExpansionStalled() rescue case below. A player
// genuinely boxed onto a small peninsula plateaus BELOW NAVY_MIN_INCOME
// precisely because it has no more land to expand onto -- gating the escape
// valve on the same income bar the AI needs the escape valve to reach is a
// deadlock, not a safeguard. This is a rescue, not a luxury expansion, so it
// asks only for enough to not immediately go bankrupt building the yard.
// Measured on Crater Islands (63% land, 4v4): the four players finished the
// game on 2.4, 5.1, 5.2 and 13.3 metal/s, so even 6 was out of reach for three
// of them and exactly one ever built a yard. On a map where a third of the
// metal is across water, the yard is not a luxury bought out of surplus -- it
// is the only route to any surplus at all, so the bar has to sit below what the
// map actually produces before it is contested. The branch this gates still
// sits below the tech rush, the bot lab and the gantry, so it only ever takes a
// factory slot nothing else wanted.
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

// T3 is this variant's WIN CONDITION, and it has never once been reached: mean
// T3 metal across 36 measured player-games is exactly zero. The doctrine is
// hold cheaply, out-eco behind the wall, then finish with T3 -- but nothing ever
// decided to build the gantry, so every game was decided at T2 by whoever had
// more army. Without this the rest of the plan has no ending.
//
// Gated on a real economy rather than a clock: the gantry is expensive and
// starting one the economy cannot finish is the same trap that starting an
// unaffordable T2 plant was.
// Was 38. apex's economy runs poorer than stock's by design-cost, so 38 was
// reached only near game end -- 420 metal of T3 fielded, a token rather than the
// hammer the doctrine calls for. 26 is still a real economy and leaves time to
// actually build a T3 force with it.
// apexearth, on when a human commits to T3: "you shouldn't really be making big
// T3 until you're usually over 100m per second. That's after having 1 or 2 afus
// usually." That matches the arithmetic measured here -- a Korgoth is ~11,000
// metal, so at 40 m/s one unit costs 275 seconds of the whole team's income, and
// the two or three we ever fielded were exactly what that affords.
//
// The gate was 26, roughly four times too low: it committed to a gantry the
// economy could not feed, which is why T3 spend sat near 3,500 for a whole game
// while the metal would have bought a real T2 force instead. 100 is the real
// bar, and reaching it is an ECONOMY problem -- advanced fusion first.
const float T3_METAL_INCOME = 100.f;

// Income alone is the wrong gate. Observed live: the team reached 100 metal/s,
// committed to an ~8000-metal gantry, and lost every engagement on the map
// while it built -- the same metal spent on T2 units would have held the line.
// A gantry is only worth starting from a position that is not collapsing.
//
// Two conditions, both from signals already maintained here:
//   gTurtle       -- Military sets this when our army value fell 18% in 20s
//                    while the enemy still fields a mobile force. That is
//                    precisely "we are losing trades right now".
//   army vs threat -- and we should at least be matching what they field, not
//                    merely have stopped bleeding.
const float T3_ARMY_RATIO = 1.0f;

// Metal income above which the gTurtle and army-ratio vetoes stop applying, so a
// gantry gets placed while we are LOSING -- which is the case they were refusing.
// See T3Worthwhile().
//
// 150, only 50 above the T3_METAL_INCOME floor, because the point is to catch
// the situation early rather than to mark an elite economy. At 150 m/s a gantry
// is 56 seconds of income and a Shiva is 10; if enemy T3 is in the base, that is
// already worth spending whatever the army ratio says. The live observation that
// prompted this was a player at 398 m/s building nothing, so the bar only has to
// sit far enough below that to trigger well before the game is decided.
const float T3_INCOME_URGENT = 150.f;

// One gantry per this much metal income, floor 1, cap GANTRY_MAX.
//
// gHaveT3 is a latch set the moment the first gantry appears, and both build
// decisions tested !gHaveT3 -- so the AI built exactly ONE gantry per game at any
// income. Reported from a hosted game: "for a very long time no gantries were
// being made, except for the first one." A gantry builds one unit at a time, so
// at the 400 m/s these games reach that single plant is the throughput ceiling on
// the whole T3 win condition.
//
// gHaveT3 itself stays -- military.as reads it for big-gun placement -- it just
// no longer decides whether to build another.
// Measured 2026-08-08, 6-game 8v8 at Handicap 50: we field 2 T3 plants where
// stock fields 7, and 16 "building T3 gantry" decisions produced 2 gantries. At
// 150 a player on 400 metal/second wants only 2 -- so the cap, not the economy,
// is the throughput ceiling. Space is not the constraint either: techroom=-1
// occurred zero times in 1,907 samples, so there was always somewhere to put one.
//
// 100/6 gives 4 gantries at 400 m/s and 6 at 600, still short of stock's 7.
const float GANTRY_PER_INCOME = 100.f;
const int   GANTRY_MAX        = 6;
// Extra plants allowed while the bank is at the cap.
const int   GANTRY_SURPLUS_BONUS = 4;
// A gantry that is actually building draws 460-620 energy/second on its own, and
// every rung above is gated on METAL income alone, which says nothing about that.
// The bar is well above one plant's draw because the base has to keep running
// too: factories, nanos and converters are all on the same grid.
const float GANTRY_PER_ENERGY = 5000.f;

// A T1 bot lab is wanted for the whole game, not just the opening: it is the
// cheap assault spam and the only source of rez bots. apexearth: "one T2
// assault unit costs like 5 or 6 T1 assault units, and that many T1s can kill
// the T2 if the T2 doesn't have a good mass".
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
	else if (want > GANTRY_MAX)
		want = GANTRY_MAX;
	// A full bank means the cap is the wrong number: income says what we can
	// sustain, a full bank says we are already failing to spend what we have.
	// apexearth: "If we are metal full we need to just keep making more gantries."
	if (aiEconomyMgr.isMetalFull)
		want += GANTRY_SURPLUS_BONUS;
	// One gantry per GANTRY_PER_ENERGY of income, and none below it.
	// apexearth, watching two go up on 1,300 energy: "I think you can do
	// something like 1 gantry for every 5000 energy as a limit."
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
	// should permit, so they stop applying.
	//
	// Observed live in a hosted +40% game: the best player was on 398 metal/s
	// with enemy T3 already in the base, and built no gantry at all. gTurtle was
	// set -- that is what "their army is on our doorstep" looks like -- and our
	// armyCost was below theirs precisely because they had T3 and we did not. So
	// both vetoes fired for the same reason, and the AI stood still.
	//
	// Those vetoes were calibrated when a gantry was a large, irreversible bet.
	// It is not at this income. Real costs: corgant 8400, corshiva 1550,
	// armbanth 13500. At 398 m/s that is 21 s, 4 s and 34 s of income. Refusing
	// to spend 21 seconds of income on the counter to the thing killing you is
	// the wrong answer at any army ratio.
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
