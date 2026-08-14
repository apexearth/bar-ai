namespace Builder {

// Pulsars, and cheap AA. Both are things stock does that we do not.
//
// apexearth: "I don't see all that many pulsars in our defense lineup either.
// Pulsars would be a pretty good counter to hold back the onslaught." Pulsar is
// armanni -- and it is stock BARb's single largest metal sink, 14.0% of
// everything it builds, while ours is ~0%. Their defence outspends their army.
// It sits at porcupine.land index 12, which an ordinary cluster never reaches
// because porcupine.prevent is 2.
//
// And on AA: "lots of the time people just make AA because its so cheap, and if
// you have like 3 or 4 of them then the enemy air actively avoids you." That is
// DETERRENCE, not attrition -- armrl is 80 metal against flak's 820, so four of
// them is 320 metal to change the enemy's target selection. An earlier design
// sized flak at 45% of enemy air VALUE, up to 30 turrets and 24,600 metal, to
// kill an air force it could have simply discouraged.
string armanni("armanni");   string cordoom("cordoom");   string legbastion("legbastion");
string armrl("armrl");       string corrl("corrl");       string legrl("legrl");

const float PULSAR_MIN_INCOME = 60.f;
// apexearth: "we need at least 1000 energy per second before we should start
// thinking about making those". One fusion is armfus 1000 / corfus 1100 / legfus 1200.
const float PULSAR_MIN_ENERGY = 1000.f;
// Derived, not fixed. A flat 1 meant a player on 400 metal/second held exactly
// as many T3 defence towers as one on 60 -- and it was the reason "make more T3
// defence" produced nothing even after the LRPC stopped stealing the pick.
//
// The comment this replaces recorded that 4 towers reached 22% of all metal
// "while we held one T2 constructor"; that ratio was a symptom of an economy
// that could not spend, and the constructor caps that caused it are gone.
// apexearth: "we need to be making way more t3 defense when we're metal full".
// One per this much metal income. Halved from 120: at 120 a player on 240 metal/s
// -- a normal hosted mid-game -- was allowed THREE, and apexearth rates these as
// the best defensive metal in the game: "they're so good for defense we should
// try not to [cap them]". Still derived rather than flat, so a poor player does
// not bankrupt itself on 3,000-4,200 metal towers.
const float PULSAR_PER_INCOME = 60.f;
// And more headroom while the bank is full, which is the state where a tower is
// paid for out of metal we are otherwise wasting.
const int   PULSAR_FULL_BONUS = 5;
// How many may be under construction simultaneously.
const int   PULSAR_CONCURRENT = 2;
int gPulsarsAsked = 0;

// NO HARD CAP. apexearth, twice now: "we shouldn't have any hard caps,
// everything needs to be balanced based on the economy/game progression", and
// on this specific number: "no no no don't you ever do such a thing like limit
// to 4 max T3 towers."
//
// A ceiling of 4 was added here after he saw twenty go up and removed the same
// day. It is the wrong tool: at 400 metal/s twenty big guns may well be
// affordable, and the real complaint was that they were built INSTEAD of
// advancing, not that they existed. What bounds them now is the Brain's
// ranking -- a want's value decays per copy already standing (value / (1 +
// have)), so the eighth gun scores an eighth of the first and loses to
// everything else long before the metal runs out.
int PulsarCap()
{
	int cap = 1 + int(aiEconomyMgr.metal.income / PULSAR_PER_INCOME);
	if (aiEconomyMgr.isMetalFull)
		cap += PULSAR_FULL_BONUS;
	return cap;
}
// TWO TERMS, NOT ONE RATIO. apexearth, 2026-08-12: "Ensure we have basic coverage
// of our bases with air defense. Then do a basic 10% metal ratio on top of that.
// SO if the enemy makes 10 dragons we'd add on some good AA defense to counter
// that."
//
// FLOOR -- basic cover, per player, once air has been SEEN. It does not scale with
// the economy and it is not a share of anything: a base either has something
// shooting upwards or it does not. Where those turrets go is the coverage half of
// the same sentence, and Brain::AirCoverWant owns it -- least-covered extractor
// first, counting work already ordered.
const int   AA_MIN            = 2;
// TOP-UP -- metal of AA per metal of their air, ON TOP of the floor, and delivered
// end to end. In METAL rather than in turrets, so the same 10% buys more Thistles
// (80) than Plutos (820) and one number covers all six defs.
//
// What this replaces multiplied 0.2 against a per-metal divisor as well (the old
// AA_PER_AIR 1000 / AA_HEAVY_PER_AIR 1800), so what actually arrived was 1.6-3.5%
// of enemy air value -- two dampeners stacked, one of them by accident.
const float AA_VS_AIR = 0.10f;

// Turrets the side should hold BEYOND basic cover. Rounded, not truncated --
// apexearth: "round it." int() was turning a want of 1.98 into 1, which threw
// away most of a turret at every value.
int AATopUp(float enemyAir, float costM)
{
	if ((enemyAir <= 0.f) || (costM <= 1.f))
		return 0;
	const float k = ai.GetTunable("apex_aa_vs_air", AA_VS_AIR);
	return int((enemyAir * k) / costM + 0.5f);
}

// A TURRET MUST COVER SOMETHING. apexearth: "purple is still making lots of
// towers in the back of their base."
//
// CheapAA and Fortify both place at the CONSTRUCTOR'S OWN POSITION -- wherever it
// happened to be standing when the rule fired. Constructors idle in the back of
// the base, so that is where the towers go, and the blob audit shows the result:
// 27 turrets at forward fraction 0.03, eight of them AA and eight dig-ins,
// covering nothing.
//
// Every gate added to this so far measured the POSITION and let them through:
// "nothing behind us" refuses ForwardFraction < 0, and a base's back yard reads
// +0.01 to +0.09 -- forward of the territory centroid, technically.
//
// The honest test is DENSITY, not position.
// The anti-blob rule, and it is about DENSITY rather than position, because
// position is what every previous attempt tested and none of them caught this.
// The same radius the audit clusters on, so what the tool calls a blob is what
// the AI refuses to start.
//
// NOT a cap on how much defence we may hold -- it says nothing about the total,
// only that the eighth turret within 420 elmos of the same spot adds nothing the
// seventh did not. On the line, where the fighting actually concentrates, the
// allowance is higher: apexearth, "in late game if theres like 10 pulsars all
// near each other, thats not a bad thing."
const float BLOB_RADIUS = 420.f;

// The circle one AA request covers. apexearth's own example of an AREA request
// rather than a point, and deliberately smaller than BLOB_RADIUS: this says
// "that order is already placed", not "this ground has enough AA", which is
// what TooCrowded above answers.
const float AA_AREA = 200.f;

bool TooCrowded(const AIFloat3& in at)
{
	const bool onLine = Military::OnBorder(at) || Military::NearFront(at);
	const float most = ai.GetTunable(onLine ? "apex_blob_front" : "apex_blob_rear",
			onLine ? 10.f : 4.f);
	return float(Military::FenceCountNear(at, BLOB_RADIUS)) >= most;
}

// Placing one, once something has decided another is wanted. Shared by the
// per-base floor and the team-wide answer so both obey the same defence policy
// and log the same line.
IUnitTask@ AAOrder(CCircuitUnit@ unit, CCircuitDef@ aa, int want, float enemyAir)
{
	const AIFloat3 here = unit.GetPos(ai.frame);
	if (!OnMap(here))
		return null;
	// Placed at the constructor's own feet, so this is the rule most able to
	// build a heap in the back of the base. See TooCrowded.
	if (TooCrowded(here))
		return null;
	// ANTI-AIR IS DEFENCE AND ANSWERS TO THE DEFENCE POLICY. Measured, armferret
	// and armrl were 31 of the ~57 towers we held, and neither rule had ever been
	// asked whether another one was affordable or wanted here -- they place at the
	// CONSTRUCTOR'S OWN POSITION, which is wherever it happened to be standing.
	// apexearth: "We're definitely out of control with building certain things
	// like the light laser turrets and popup air defense turrets."
	if (!Military::DefenceAllowedAt(here, aa))
		return null;
	// AA is the area case apexearth described -- "I want AA defense built in this
	// 200 elmo circle" -- so the request owns a circle, not a point: another AA
	// of this def already ordered anywhere in it is this order, already placed.
	bool created = false;
	IUnitTask@ post = Requests::Take(unit, aa, Task::BuildType::DEFENCE,
			Task::Priority::NORMAL, here, AA_AREA, DEF_SHAKE, created);
	if (post is null)
		return null;
	if (!created)
		return post;
	gNextAA = ai.frame + AA_PERIOD;
	AiLog(Factory::T() + "apex: cheap-aa " + aa.GetName() + " mine=" + aa.count
		+ " team=" + formatFloat(Military::TeamAA(), "", 0, 0)
		+ "/" + want + " enemyAir=" + formatFloat(enemyAir, "", 0, 0));
	return post;
}
const int   AA_PERIOD         = 20 * SECOND;
const uint  DEF_CON_FLOOR     = 3;      // never take the last builders
int gNextPulsar = 0;
int gNextAA = 0;
int gNextAADiag = 0;  // temporary diagnostic, see CheapAA

// armrl/corrl/legrl is DETERRENCE, not an answer: 80 metal. apexearth, watching a
// game lost from this exact hole: "the enemies attacked us with
// like ten gunships on one of our bases, and we had like eight of the light
// AA. They did nothing. Light AA is so bad versus T2 gunships."
//
// So a second, heavier tier: cormadsam/armferret/legflak. All VTOL-only
// structures, one tier up in cost (315-820 metal against corrl's 80) and
// correspondingly harder-hitting. Which tier AADefFor picks is a question about
// ground, not about how much they fly; AATopUp then sizes either one by its own
// cost, so the choice of tier changes the turret, never the metal.
//
// OFF. Measured worse, not better -- the same failure this comment set out to
// avoid. 8-game control vs BARb:stable:hard_aggressive, Comet Catcher 4v4 +25%
// Cortex/Cortex, 25 min, against the back-wall-fix baseline (see CHANGES.md,
// commander back-wall hiding): head to head 1-1 -> 0-5, metal produced
// 40,743 -> 27,382, static defence share 10.6% -> 11.5%, wiped-out player-games
// 9/32 -> 13/32. One game in a smaller trial run did win the economy and K/D
// outright (265,925 metal, K/D 1.13), so the mechanism is not obviously always
// bad -- it may need a higher income floor, a lower AA_HEAVY_MAX, or gating on
// SUSTAINED enemy air rather than a one-shot cost reading. Left in place,
// disabled, rather than deleted, since re-testing a narrower version is
// plausible future work.
// Back ON. It was switched off after a version that sized flak at 45% of enemy
// air VALUE -- up to 30 turrets and 24,600 metal to kill an air force it could
// have discouraged. The constants below are that design's replacement and are
// bounded at 1..4, so the reason for the kill switch no longer applies, and the
// switch meant we have been building NO good AA at all.
// apexearth: "we arent making the better AA early enough in our bases."
const bool  AA_HEAVY_ON          = true;
const float AA_HEAVY_MIN_INCOME  = 20.f;
const int   AA_HEAVY_PERIOD      = 25 * SECOND;
int gNextHeavyAA = 0;
string armferret("armferret"); string cormadsam("cormadsam"); string legflak("legflak");

// A FEW TOWERS AT HOME, EARLY, TO NOT BE WORTH RAIDING.
//
// apexearth: "need more t1.5 defenses around our home base in the early game...
// enemy raids are able to get all the way in, the t1.5 defense would deter them
// from even trying - we don't need a ton, just enough to convince them not to do
// it." Same argument the cheap-AA floor already rests on: deterrence changes the
// enemy's target selection, which is worth far more than the turret's own dps.
//
// This is a SPEND rule, the class CLAUDE.md records as having cut metal
// production 4.3x when twelve of them were added at once, so it is bounded hard:
// a standing count of DETER_HOME_MAX, only near home, only before an advanced
// factory exists, and only once there is income to pay for it. Beamer 190 /
// Twin Guard 195 against a Sentry's 85 -- the point is a tower a raider cannot
// simply run past, not a cheaper one we build more of.
string armbeamer("armbeamer"); string corhllt("corhllt"); string legmg("legmg");
const int   DETER_HOME_MAX    = 3;
const float DETER_MIN_INCOME  = 8.f;
const float DETER_RADIUS      = 900.f;
const int   DETER_PERIOD      = 30 * SECOND;
int gNextDeter = 0;

// SHIELDS OVER THE BASE. apexearth: "If we can have these really surrounding our
// base it is greatttt defense. + add shields."
//
// armgate Keeper 3,000m/54,000e, corgate Overseer 3,200m/55,000e, legdeflector
// Soteria 3,200m/55,000e -- near-identical, so one rule covers all three.
//
// I first recorded "Legion has no equivalent, verified" after `leggate` returned
// nothing. That was one guessed name and it was wrong; apexearth: "legion does
// have shields!" Found properly by reading how armgate declares its own -- the
// field is `weapontype = "Shield"`, not the `shieldpower` I grepped for -- which
// lists legdeflector and leggatet3. Exactly the absence-from-one-search trap
// CLAUDE.md is written against.
//
// Gated on ENERGY rather than metal: a shield's real cost is its upkeep, and one
// running dry is 3,000 metal doing nothing. Placed by the coverage score, so
// shields spread across the approaches instead of stacking on one.
string armgate("armgate"); string corgate("corgate"); string legdeflector("legdeflector");
// WHAT A SHIELD ACTUALLY COSTS TO RUN, read from the def rather than guessed at:
// all three declare energyupkeep 0 and powerregenenergy 562.5, so a dome draws
// nothing idle and 562.5 energy/second while regenerating what it just absorbed.
// That draw is the honest gate. The margin covers the rest of the base continuing
// to run through the burst; it is a chosen number, and isEnergyStalling above is
// the real-time backstop either way.
const float SHIELD_REGEN_DRAW  = 562.5f;
const float SHIELD_DRAW_MARGIN = 1.5f;
// HOW MANY, AS ECONOMY RATHER THAN AS A CEILING. apexearth: "We should be making
// tons of T3 defenses and shields late in the game", against his standing rule
// that nothing gets a hard cap. Seconds of income per dome, against the def's OWN
// cost so the three factions differ correctly and the count follows the economy
// with nothing to raise later.
const float SHIELD_INCOME_SECS = 100.f;
const int   SHIELD_PERIOD     = 60 * SECOND;
int gNextShield = 0;
int gShieldsAsked = 0;

int ShieldsAfforded(CCircuitDef@ dome)
{
	if ((dome is null) || (dome.costM <= 0.f))
		return 0;
	const float secs = ai.GetTunable("apex_shield_income_secs", SHIELD_INCOME_SECS);
	return 1 + int(aiEconomyMgr.metal.income * secs / dome.costM);
}

IUnitTask@ Shield(CCircuitUnit@ unit)
{
	if (aiEconomyMgr.isEnergyStalling)
		return null;
	if (unit.circuitDef.costM < ADV_CON_COST)
		return null;                       // T2 constructors only
	// The rate limit the old ceiling was doing implicitly. gNextShield was
	// assigned below and never read, so with the ceiling gone nothing spaced these
	// out at all.
	if (ai.frame < gNextShield)
		return null;
	if (aiEconomyMgr.energy.income < SHIELD_REGEN_DRAW
			* ai.GetTunable("apex_shield_draw_margin", SHIELD_DRAW_MARGIN))
		return null;
	if (aiBuilderMgr.GetWorkerCount() <= DEF_CON_FLOOR)
		return null;
	CCircuitDef@ dome = SideDef3(armgate, corgate, legdeflector);
	if ((dome is null) || !dome.IsAvailable(ai.frame)
		|| (dome.count >= ShieldsAfforded(dome)))
		return null;
	if (gShieldsAsked - dome.count >= 1)
		return null;                       // one at a time; they are not cheap
	AIFloat3 spot;
	if (!Military::BorderPos(spot, uint(dome.count)) && !Military::FrontLinePos(spot))
		return null;
	bool created = false;
	IUnitTask@ post = Requests::Take(unit, dome, Task::BuildType::DEFENCE,
			Task::Priority::NORMAL, spot, 0.f, 0.f, created);
	if (post is null)
		return null;
	if (!created)
		return post;
	++gShieldsAsked;
	gNextShield = ai.frame + SHIELD_PERIOD;
	AiLog(Factory::T() + "apex: shield " + dome.GetName() + " standing=" + dome.count
		+ "/" + ShieldsAfforded(dome)
		+ " eInc=" + formatFloat(aiEconomyMgr.energy.income, "", 0, 0)
		+ " mInc=" + formatFloat(aiEconomyMgr.metal.income, "", 0, 0));
	return post;
}

// JAMMERS OVER THE BASE. apexearth: "we need to ensure our base is covered by
// jammers."
//
// Nothing was placing them deliberately. The only jammer entries in the game are
// build_chain.json hubs hanging off armrad/corrad/armfrad/corfrad, and a hub fires
// only when its exact parent unit FINISHES -- so base jamming was a side effect of
// whether a radar tower happened to get built, at "low" priority, behind a Pulsar
// and a Big Bertha in the same list. armjamt/corjamt/legjam are 115-240 metal;
// this asks for them directly instead.
//
// The def names, IsJammerDef and the AreaHasJammer anti-clustering ledger already
// exist in digin.as -- built for the chain path, which stacked three jammers on
// top of each other. Orders made here are recorded in the same ledger so the two
// paths cannot cluster against each other either.
//
// THE ADVANCED JAMMER, AND IT IS ALSO THE CHEAP ONE. apexearth: "we also have no
// t2 jammer (the advanced kind) in the middle of our base to help protect from
// enemy artillery."
//
// armveil Veil / corshroud Shroud / legajam Erebus are each named "Long-Range
// Jamming Tower" in the game's own defs: 125-130 metal against armjamt's 240, and
// 700-760 elmos of jam radius against 360-500 -- two to four times the AREA
// hidden, for less metal. What they cost is ENERGY: 19,000-20,000 to build and
// 125/second forever, against the short tower's 5,200-8,500 and 40/second. The
// short defs stay as the fallback so a side that cannot build the long one yet is
// not left with nothing.
const int   JAMMER_PERIOD     = 45 * SECOND;
const float JAMMER_UPKEEP_LONG  = 125.f;
const float JAMMER_UPKEEP_SHORT = 40.f;
// Jam radius of the SMALLEST of each triple (corshroud 700, corjamt 360), so the
// placement is right for every faction rather than for the best one.
const float JAMMER_COVER_LONG   = 700.f;
const float JAMMER_COVER_SHORT  = 360.f;
// Income per unit of upkeep before we will run one. The rule already ran a
// 40/second tower on 150/second of income; this is that same ratio rounded up,
// applied to whichever def we actually place, so the number moves with the tower
// instead of being a constant that only ever suited the short one.
const float JAMMER_UPKEEP_MARGIN = 4.f;
// How much of our energy income jamming may hold in total. This replaces a hard
// JAMMER_MAX of 3. Metal is not the constraint -- 125 metal is nothing -- so the
// bound is on the resource that actually pays, which is why this is not the
// shield's metal-seconds rule.
const float JAMMER_ENERGY_SHARE  = 0.10f;
int gNextJammer   = 0;
int gJammersAsked = 0;

// The long-range tower if we can build it, the short one otherwise. `isLong` is
// what the upkeep, the coverage radius and the affordable count all read.
CCircuitDef@ JammerDefFor(bool& out isLong)
{
	isLong = true;
	CCircuitDef@ far = SideDef3(armveil, corshroud, legajam);
	if ((far !is null) && far.IsAvailable(ai.frame))
		return far;
	isLong = false;
	return SideDef3(armjamt, corjamt, legjam2);
}

int JammersAfforded(float upkeep)
{
	if (upkeep <= 0.f)
		return 0;
	const float share = ai.GetTunable("apex_jammer_energy_share", JAMMER_ENERGY_SHARE);
	return 1 + int(aiEconomyMgr.energy.income * share / upkeep);
}

IUnitTask@ BaseJammer(CCircuitUnit@ unit)
{
	// THE ONE GUARD THAT READS THE ACTUAL GRID. An energy stall stops the whole
	// economy, not just this -- UpdateEconomyTasks returns early on it -- and it is
	// the only signal here that moves when something else (a converter rule, say)
	// starts eating the surplus. The income test below cannot see that.
	if (aiEconomyMgr.isEnergyStalling)
		return null;
	if (!gHomeSet)
		return null;
	if (ai.frame < gNextJammer)
		return null;
	if (aiBuilderMgr.GetWorkerCount() <= DEF_CON_FLOOR)
		return null;
	bool isLong = false;
	CCircuitDef@ jam = JammerDefFor(isLong);
	if ((jam is null) || !jam.IsAvailable(ai.frame))
		return null;
	const float upkeep = isLong ? JAMMER_UPKEEP_LONG : JAMMER_UPKEEP_SHORT;
	const float cover  = isLong ? JAMMER_COVER_LONG  : JAMMER_COVER_SHORT;
	if (aiEconomyMgr.energy.income
		< upkeep * ai.GetTunable("apex_jammer_upkeep_margin", JAMMER_UPKEEP_MARGIN))
		return null;
	if (int(jam.count) >= JammersAfforded(upkeep))
		return null;
	// Asked-minus-standing, the same idiom NukeSilo and Shield use: Enqueue does
	// not dedup and a jammer takes a while, so counting only what stands orders
	// the whole set at once.
	if (gJammersAsked - int(jam.count) >= 1)
		return null;

	// THE MIDDLE OF THE BASE, WHICH IS NOT WHERE WE SPAWNED. apexearth wants this
	// one central, against artillery hunting what we have built. gHomePos is the
	// START position and never moves, so as the base grows forward it ends up
	// behind everything worth hiding -- the same fault territory.as records for
	// every other positional measure. TerritoryCentre is the centroid of the metal
	// clusters we hold, and falls back to gHomePos before we hold any.
	//
	// Later ones move out to the approaches, which is where something worth hiding
	// from radar is actually walking.
	AIFloat3 anchor = Military::TerritoryCentre();
	if (jam.count > 0) {
		AIFloat3 border;
		if (Military::BorderPos(border, uint(jam.count) - 1))
			anchor = border;
	}
	if (!OnMap(anchor))
		return null;
	// Half the jam radius, so wherever the spiral lands the anchor is still inside
	// the disc this tower hides. A flat 700 was wider than corjamt covers at all.
	const AIFloat3 site = ai.FindBuildSiteNear(jam, anchor, cover * 0.5f);
	if (!OnMap(site) || (ThreatFor(unit, site) > CON_THREAT_VETO))
		return null;
	if (AreaHasJammer(site))
		return null;   // would stack on one we already have; try again next period

	bool created = false;
	IUnitTask@ post = Requests::Take(unit, jam, Task::BuildType::RADAR,
			Task::Priority::NORMAL, site, 0.f, 0.f, created);
	if (post is null)
		return null;
	if (!created)
		return post;
	gJammerPos.insertLast(site);
	gJammerAt.insertLast(ai.frame);
	++gJammersAsked;
	gNextJammer = ai.frame + JAMMER_PERIOD;
	AiLog(Factory::T() + "apex: base-jammer " + jam.GetName()
		+ " standing=" + jam.count + "/" + JammersAfforded(upkeep)
		+ (isLong ? " long" : " short")
		+ " eInc=" + formatFloat(aiEconomyMgr.energy.income, "", 0, 0));
	return post;
}

IUnitTask@ HomeDeter(CCircuitUnit@ unit)
{
	if (aiEconomyMgr.isEnergyStalling)
		return null;
	if (!gHomeSet || Factory::gHaveT2)
		return null;                       // early game only; porc takes over later
	if (aiEconomyMgr.metal.income < DETER_MIN_INCOME)
		return null;
	if (aiBuilderMgr.GetWorkerCount() <= DEF_CON_FLOOR)
		return null;
	if (int(Military::FenceCountNear(gHomePos, DETER_RADIUS)) >= DETER_HOME_MAX)
		return null;
	CCircuitDef@ tower = SideDef3(armbeamer, corhllt, legmg);
	if ((tower is null) || !tower.IsAvailable(ai.frame))
		return null;
	const AIFloat3 site = ai.FindBuildSiteNear(tower, gHomePos, DETER_RADIUS);
	if (!OnMap(site))
		return null;
	bool created = false;
	IUnitTask@ post = Requests::Take(unit, tower, Task::BuildType::DEFENCE,
			Task::Priority::NORMAL, site, 0.f, 0.f, created);
	if (post is null)
		return null;
	if (!created)
		return post;
	gNextDeter = ai.frame + DETER_PERIOD;
	AiLog(Factory::T() + "apex: home-deter " + tower.GetName()
		+ " standing=" + Military::FenceCountNear(gHomePos, DETER_RADIUS)
		+ "/" + DETER_HOME_MAX
		+ " mInc=" + formatFloat(aiEconomyMgr.metal.income, "", 0, 0));
	return post;
}

// The heavy gun that holds ground. T2 constructors only -- armck/armcv cannot
// build it, and asking would be dropped in silence.
IUnitTask@ Pulsar(CCircuitUnit@ unit)
{
	// No period. What should stop this is the economy and the standing count,
	// both checked below -- a clock refuses to reinforce a line being broken
	// through for reasons that have nothing to do with the line.
	if (aiEconomyMgr.isEnergyStalling)
		return null;
	if (unit.circuitDef.costM < ADV_CON_COST)
		return null;
	if (aiBuilderMgr.GetWorkerCount() <= DEF_CON_FLOOR)
		return null;
	if (aiEconomyMgr.metal.income < PULSAR_MIN_INCOME)
		return null;
	// These are energy monsters, not metal ones: cordoom 37,000E, legbastion 58,000E,
	// armanni 74,000E, against 3000-4200 metal. The metal gate above is reachable on
	// T1 mexes alone, which is how a gun went up at 24.0 min ahead of the fusion at
	// 26.0. One fusion is 1000-1200 E/s, so this is "not before a fusion is paying".
	if (aiEconomyMgr.energy.income < PULSAR_MIN_ENERGY)
		return null;
	CCircuitDef@ gun = SideDef3(armanni, cordoom, legbastion);
	if ((gun is null) || !gun.IsAvailable(ai.frame) || (gun.count >= PulsarCap()))
		return null;
	// Cap how many are going up AT ONCE, which is a different question from how
	// many we end up with. Each is 3,000-4,200 metal, so six simultaneous
	// nanoframes is most of a mid-game bank frozen in half-built towers that
	// defend nothing until they finish. apexearth: "probably you want to limit
	// how many we make at once to like 2 or 3. (sometimes I see 6 going up all at
	// once)". Same asked-minus-standing idiom NukeSilo uses.
	if (gPulsarsAsked - gun.count >= PULSAR_CONCURRENT)
		return null;
	// On the line, not in the base. StandoffPos walks from the point it is handed
	// TOWARD home and stops at the first safe step -- right for ContestDefence,
	// which hands it a real enemy hotspot, but this call handed it the
	// constructor's own position, and the constructors that pass the T2 cost gate
	// are standing in the base. Every gun therefore landed one step further into
	// the base, which is the same border-ranked placement the porc path already
	// uses correctly.
	// apexearth: "they're still good for a frontline, but i just see a lot made
	// way back behind in the base... taking up valuable room."
	AIFloat3 spot;
	string where = "border";
	if (!Military::BorderPos(spot, uint(gun.count))) {
		where = "front";
		if (!Military::FrontLinePos(spot)) {
			where = "standoff";
			if (!StandoffPos(unit, unit.GetPos(ai.frame), spot))
				return null;
		}
	}
	bool created = false;
	IUnitTask@ post = Requests::Take(unit, gun, Task::BuildType::DEFENCE,
			Task::Priority::NORMAL, spot, 0.f, DEF_SHAKE, created);
	if (post is null)
		return null;
	if (!created)
		return post;
	++gPulsarsAsked;
	AiLog(Factory::T() + "apex: pulsar " + gun.GetName() + " standing=" + gun.count
		+ "/" + PulsarCap() + " at-" + where
		+ " mInc=" + formatFloat(aiEconomyMgr.metal.income, "", 0, 0));
	return post;
}

// One nuclear launcher per player, as early as the economy can carry it -- and
// as many as we like once both banks are over 80% and the income is going to
// waste anyway.
//
// apexearth: "Let's make sure all our guys make at least 1 nuke launcher per
// game - seems like they'd be effective. Usually the earlier the better."
//
// CONFIRMED FIRING 2026-08-08 -- apexearth watching: "i did see nuke silos going
// up". What is still unknown is whether they are USED well: the one that landed
// was not on an enemy base. Nuke target selection lives in the C++ SuperTask and
// has not been audited.
//
// Costs from the pinned tree: armsilo 8100 metal / 90,000 energy, corsilo and
// legsilo 7700 / 82,000. The energy is what actually gates it -- that is roughly
// a fusion-minute -- so the bar is set on energy income rather than on metal or a
// clock. Advanced constructors only: armsilo's buildoptions list armack/armacv/
// armaca and their heavy variants, so asking a T1 constructor is a silent no-op.
string armsilo("armsilo"); string corsilo("corsilo"); string legsilo("legsilo");

// Measured on a 6v6 medium map at Handicap 50: peak energy income 1230 with zero
// fusions standing, so a bar of 1800 was unreachable and "one per game" never
// happened there. Set below what a mid-sized game actually reaches -- apexearth:
// "make sure all our guys make at least 1 nuke launcher per game... usually the
// earlier the better."
// 1000/50 was set for a medium map before this had ever been watched, and it
// measured badly -- apexearth: "making nukes hurt us because we weren't healthy
// enough." A silo is 8,100 metal and 90,000 energy BEFORE a single missile, and
// we already build only 40-60% of stock's metal, so it has to come out of real
// surplus rather than out of the army budget.
const float NUKE_MIN_ENERGY = 2500.f;
const float NUKE_MIN_INCOME = 150.f;

// Both banks over this share of storage is the "we are wasting income" state.
// aiEconomyMgr's own flags do not agree on a threshold -- isMetalFull is 0.8 but
// isEnergyFull is 0.88 -- so both sides are read directly against one number.
const float NUKE_FULL_FRAC = 0.8f;
int gNukesAsked = 0;
// High-water standing count. Asked-minus-standing would read a DESTROYED silo as
// one still in flight and block every rebuild for the rest of the game; against
// the peak, a loss lowers standing and the cap lets the replacement through.
int gNukesPeak = 0;

CCircuitDef@ NukeDef()
{
	return SideDef3(armsilo, corsilo, legsilo);
}

// apexearth: "when we are full on metal and energy (>80%) we should keep making
// more nuke launchers." A silo is 8,100 metal and 90,000 energy, and the energy
// is the half that actually hurts -- so a metal bank at the cap on its own is
// not enough to say the next one is free.
bool NukeSurplus()
{
	return (aiEconomyMgr.metal.storage > 0.f) && (aiEconomyMgr.energy.storage > 0.f)
		&& (aiEconomyMgr.metal.current > aiEconomyMgr.metal.storage * NUKE_FULL_FRAC)
		&& (aiEconomyMgr.energy.current > aiEconomyMgr.energy.storage * NUKE_FULL_FRAC);
}

int NukeCap()
{
	// One is the point of the rule. Both banks at the cap removes the cap
	// entirely -- apexearth: "if we are full on metal we should make the limit
	// unlimited to allow us to keep making more." Resources sitting at storage
	// are already wasted, so there is nothing left for another silo to displace.
	//
	// Note this is a cap on how many may STAND, not on how many at once: the
	// outstanding test below still allows only one in flight, which serialises
	// them and matches "build expensive structures ONE AT A TIME, assisted".
	return NukeSurplus() ? 999 : 1;
}

IUnitTask@ NukeSilo(CCircuitUnit@ unit)
{
	if (aiEconomyMgr.isEnergyStalling)
		return null;
	if (unit.circuitDef.costM < ADV_CON_COST)
		return null;
	// The income and half-bank bars are a proxy for "can we afford one without
	// starving the rest". Both banks sitting over 80% answers that question
	// directly, so the proxy is skipped rather than allowed to veto it.
	// THE ENERGY FLOOR IS NOT A PROXY, IT IS THE RUNNING COST. A missile is
	// 90,000 energy to stockpile, so a silo on a thin grid does not merely cost
	// its build price, it holds the whole economy down for as long as it stands.
	// A full bank does not answer that: storage is small next to a reactor's
	// output, and it was full precisely because nothing else was spending.
	// apexearth, watching live: "now we have no energy because we have a nuke
	// launcher with only 1500 energy income."
	if (aiEconomyMgr.energy.income < NUKE_MIN_ENERGY)
		return null;
	const bool surplus = NukeSurplus();
	if (!surplus) {
		if (aiEconomyMgr.metal.income < NUKE_MIN_INCOME)
			return null;
		// Only out of surplus. A silo started on a tight bank starves everything
		// else for the several minutes it takes to finish.
		if (aiEconomyMgr.isMetalEmpty || (aiEconomyMgr.metal.current
				< aiEconomyMgr.metal.storage * 0.5f))
			return null;
	}
	CCircuitDef@ silo = NukeDef();
	if ((silo is null) || !silo.IsAvailable(ai.frame))
		return null;
	const int standing = int(silo.count);
	if (standing > gNukesPeak)
		gNukesPeak = standing;
	// Outstanding as well as standing: a silo takes a long time to build and
	// Enqueue does not dedup, so counting only what stands orders a second one
	// while the first is still a nanoframe.
	if ((standing >= NukeCap()) || (gNukesAsked - gNukesPeak >= 1))
		return null;

	// Behind the base, in the nano field where it will actually get finished.
	// WIDEN, DO NOT GIVE UP. This copied GANTRY_NEAR_NANO from the gantry rule
	// but not the gantry's fallback: the nano cluster is the densest patch of the
	// base, a silo is 112 elmos, and a 700 search there routinely finds nothing.
	// A nuke silo is a once-per-game structure gated behind a long income ramp,
	// so one failed search WAS the whole behaviour, and it returned null in
	// silence. Same shape the gantry rule already fixed for itself.
	AIFloat3 near;
	const bool haveNano = NanoCluster(near);
	if (!haveNano)
		near = gHomePos;
	AIFloat3 site = ai.FindBuildSiteNear(silo, near, GANTRY_NEAR_NANO);
	if (!OnMap(site) && haveNano)
		site = ai.FindBuildSiteNear(silo, gHomePos, GANTRY_NEAR_NANO);
	if (!OnMap(site))
		site = ai.FindBuildSiteNear(silo, gHomePos, GANTRY_SEARCH_WIDE);
	if (!OnMap(site) || (ThreatFor(unit, site) > CON_THREAT_VETO))
		return null;

	bool created = false;
	IUnitTask@ post = Requests::Take(unit, silo, Task::BuildType::BIG_GUN,
			Task::Priority::NORMAL, site, 0.f, 0.f, created);
	if (post is null)
		return null;
	if (!created)
		return post;
	++gNukesAsked;
	AiLog(Factory::T() + "apex: nuke silo " + silo.GetName()
		+ " standing=" + silo.count + " asked=" + gNukesAsked
		+ (surplus ? " surplus" : "")
		+ " eInc=" + formatFloat(aiEconomyMgr.energy.income, "", 0, 0));
	return post;
}

// Pinpointers, three for the WHOLE TEAM.
//
// apexearth: "Ensure that we make pinpointer style units (for Armada, Cortex,
// and Legion) - the entire team only needs 3 max."
//
// armtarg/cortarg/legtarg, "Enhanced Radar Targeting, more facilities enhance
// accuracy". 800-810 metal and 7,200-7,500 energy each, so three is ~2,400 metal
// spread across the whole side -- but the cap has to be a TEAM cap, not a per
// player one, or eight instances each build "just one" and the side pays eight
// times for an effect that stopped stacking at three.
//
// Advanced constructors only: armtarg lists armaca/armack/armacv and their heavy
// variants, and asking a T1 constructor is a silent no-op.
string armtarg("armtarg"); string cortarg("cortarg"); string legtarg("legtarg");

// Published as this player's standing-plus-outstanding count; every instance
// sums the roster before ordering one.
const string TV_TARG = "targ";

const int   PINPOINT_TEAM_MAX   = 3;
const int   PINPOINT_PER_PLAYER = 1;   // spread them, so one death is not all three
const float PINPOINT_MIN_ENERGY = 500.f;
const float PINPOINT_MIN_INCOME = 30.f;
const int   PINPOINT_PERIOD     = 30 * SECOND;
// An order that never becomes a building would otherwise hold a team slot for
// the rest of the game, since the slot is released by the standing count.
const int   PINPOINT_ASK_TTL    = 5 * MINUTE;
int gNextPinpoint    = 0;
int gPinpointAskedAt = -1;

CCircuitDef@ PinpointDef()
{
	return SideDef3(armtarg, cortarg, legtarg);
}

bool PinpointPending()
{
	if (gPinpointAskedAt < 0)
		return false;
	if (ai.frame >= gPinpointAskedAt + PINPOINT_ASK_TTL)
		return false;
	CCircuitDef@ targ = PinpointDef();
	return (targ is null) || (int(targ.count) == 0);
}

int OwnPinpoints()
{
	CCircuitDef@ targ = PinpointDef();
	const int standing = (targ is null) ? 0 : int(targ.count);
	return standing + (PinpointPending() ? 1 : 0);
}

// Our own contribution comes from OwnPinpoints() rather than the blackboard:
// UpdateTeamCoord publishes once a second, and a rule that read its own stale
// slot would order a second one inside that window.
int TeamPinpoints()
{
	array<Id>@ mates = ai.GetTeamIds();
	if ((mates is null) || (mates.length() == 0))
		return OwnPinpoints();
	int n = 0;
	bool sawSelf = false;
	for (uint i = 0; i < mates.length(); ++i) {
		const int t = int(mates[i]);
		if (t == ai.teamId) {
			sawSelf = true;
			n += OwnPinpoints();
		} else {
			n += int(ai.ReadTeamValue(t, TV_TARG, 0.f));
		}
	}
	return sawSelf ? n : (n + OwnPinpoints());
}

// One asker at a time, by rank in the ally roster. Without this the team cap is
// only as tight as the publish cadence: every instance that passed the economy
// gates inside the same second would read the same total and all of them would
// order, which is exactly how a cap of 3 becomes a 5.
bool PinpointTurn()
{
	array<Id>@ mates = ai.GetTeamIds();
	if ((mates is null) || (mates.length() <= 1))
		return true;
	uint rank = 0;
	for (uint i = 0; i < mates.length(); ++i) {
		if (int(mates[i]) < ai.teamId)
			++rank;
	}
	// If the roster does not list us, every id is below ours and rank lands one
	// past the end -- a slot that never comes round, i.e. we would never build.
	if (rank >= mates.length())
		rank = mates.length() - 1;
	return (uint(ai.frame / (2 * SECOND)) % mates.length()) == rank;
}

IUnitTask@ Pinpointer(CCircuitUnit@ unit)
{
	if (aiEconomyMgr.isEnergyStalling)
		return null;
	if (unit.circuitDef.costM < ADV_CON_COST)
		return null;
	if (aiBuilderMgr.GetWorkerCount() <= DEF_CON_FLOOR)
		return null;
	// Energy is what this costs -- 7,200-7,500 to build against 810 metal, and
	// then energyupkeep 100 for the rest of the game -- so it is gated on the
	// grid the way the silo is, rather than on a clock the way the base-defence
	// list it replaces was.
	if ((aiEconomyMgr.energy.income < PINPOINT_MIN_ENERGY)
		|| (aiEconomyMgr.metal.income < PINPOINT_MIN_INCOME))
		return null;
	CCircuitDef@ targ = PinpointDef();
	if ((targ is null) || !targ.IsAvailable(ai.frame))
		return null;
	if (OwnPinpoints() >= PINPOINT_PER_PLAYER)
		return null;
	if (!PinpointTurn())
		return null;
	if (TeamPinpoints() >= PINPOINT_TEAM_MAX)
		return null;

	// Behind the base with the nanos. It has no weapon and its whole value is
	// standing up for the rest of the game.
	// Widen rather than give up -- see the silo above for why 700 in the nano
	// field is not a search, it is a coin flip that loses silently.
	AIFloat3 near;
	const bool haveNano = NanoCluster(near);
	if (!haveNano)
		near = gHomePos;
	AIFloat3 site = ai.FindBuildSiteNear(targ, near, GANTRY_NEAR_NANO);
	if (!OnMap(site) && haveNano)
		site = ai.FindBuildSiteNear(targ, gHomePos, GANTRY_NEAR_NANO);
	if (!OnMap(site))
		site = ai.FindBuildSiteNear(targ, gHomePos, GANTRY_SEARCH_WIDE);
	if (!OnMap(site) || (ThreatFor(unit, site) > CON_THREAT_VETO))
		return null;

	bool created = false;
	IUnitTask@ post = Requests::Take(unit, targ, Task::BuildType::RADAR,
			Task::Priority::NORMAL, site, 0.f, 0.f, created);
	if (post is null)
		return null;
	if (!created)
		return post;
	gPinpointAskedAt = ai.frame;
	gNextPinpoint = ai.frame + PINPOINT_PERIOD;
	AiLog(Factory::T() + "apex: pinpointer " + targ.GetName()
		+ " team=" + TeamPinpoints() + "/" + PINPOINT_TEAM_MAX
		+ " eInc=" + formatFloat(aiEconomyMgr.energy.income, "", 0, 0));
	return post;
}

// THE SIZING, KEPT; THE PLACEMENT, GONE. CheapAA and HeavyAA chose a def and a
// count correctly and then put the turret at the constructor's feet, which is a
// third of the rearward blobs. Brain::AirCoverWant asks these two and places over
// an extractor -- what their air is actually hunting.
CCircuitDef@ AADefFor(CCircuitUnit@ unit)
{
	CCircuitDef@ heavy = SideDef3(armferret, cormadsam, legflak);
	if (LandIsPrecious() && (heavy !is null) && heavy.IsAvailable(ai.frame))
		return heavy;
	return SideDef3(armrl, corrl, legrl);
}

// WHAT THE WHOLE SIDE SHOULD HOLD: everyone's basic cover, plus the shared top-up.
// Military::TeamAA() sums the side, so the floor has to be multiplied by how many
// of us there are -- comparing a team-wide count against one player's floor is the
// arithmetic that let one player's turrets answer the side's entire air threat
// while three players held none.
//
// No tier branch. The divisor is the def's OWN cost, so Armada, Cortex and Legion
// size identically without any of them being named. The `costM > 400` test this
// replaces was true for legflak (820) and false for armferret (360) and cormadsam
// (315), so two factions out of three sized their good turret with the cheap
// tier's constants.
//
// No ceiling either: 10% of their air metal is its own bound, which is what the
// old AA_MAX of 12 was overriding.
int AAWantedNow(CCircuitUnit@ unit, float enemyAir)
{
	CCircuitDef@ aa = AADefFor(unit);
	array<Id>@ mates = ai.GetTeamIds();
	const int players = ((mates is null) || (mates.length() == 0))
			? 1 : int(mates.length());
	int want = players * AA_MIN;
	if (aa !is null)
		want += AATopUp(enemyAir, aa.costM);
	return (want < 1) ? 1 : want;
}

}  // namespace Builder
