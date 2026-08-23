namespace Builder {

// Pulsars and cheap AA. Cheap AA is deliberately sized as deterrence (metal to
// shift enemy targeting), not as attrition against measured enemy air value.
string armanni("armanni");   string cordoom("cordoom");   string legbastion("legbastion");
string armrl("armrl");       string corrl("corrl");       string legrl("legrl");

const float PULSAR_MIN_INCOME = 60.f;
// One fusion's output (armfus 1000 / corfus 1100 / legfus 1200).
const float PULSAR_MIN_ENERGY = 1000.f;
// Scaled by income rather than fixed, so the count of these T3 towers held
// tracks economy size instead of being the same at every income level.
const float PULSAR_PER_INCOME = 60.f;
// And more headroom while the bank is full, which is the state where a tower is
// paid for out of metal we are otherwise wasting.
const int   PULSAR_FULL_BONUS = 5;
// How many may be under construction simultaneously.
// SERIAL BY DOCTRINE. apexearth 2026-08-20: "Do we want 1 T3 defense in
// 1/3rd the time, or 3 T3 defense in 3/3rds that time..? :)" -- build power,
// not metal, is the constraint, so one gun FIGHTING beats three frames
// defending nothing. A full bank lifts this to 2, never more: money was
// never what the second frame was waiting on.
const int PULSAR_CONCURRENT = 1;
int gPulsarsAsked = 0;

// NO HARD CAP: count is bounded by economy (PulsarCap) and by the Brain's
// per-copy value decay, not by a fixed ceiling.
int PulsarCap()
{
	// "A lot more" (apexearth, third pulsar request today): one per 40 m/s,
	// was one per 60 -- income-derived, not a flat number.
	int cap = 1 + int(aiEconomyMgr.metal.income
			/ ai.GetTunable("apex_pulsar_per_income", TUNE_PULSAR_PER_INCOME));
	if (aiEconomyMgr.isMetalFull)
		cap += PULSAR_FULL_BONUS;
	// One more gun per enemy Behemoth-class unit seen: the pulsar is its
	// direct counter, and an income-only cap read a T3 spam as no reason
	// to thicken the line.
	cap += int((aiEnemyMgr.GetEnemyCost(RT::SUPER)
			+ aiEnemyMgr.GetEnemyCost(RT::HEAVY))
			/ ai.GetTunable("apex_counter_t3_norm", TUNE_COUNTER_T3_NORM));
	return cap;
}
// TWO TERMS: a flat per-player floor (basic cover, regardless of economy) plus
// a top-up sized in metal-of-AA per metal-of-enemy-air, so the ratio is not
// diluted by a second hidden divisor.
const int   AA_MIN            = 2;
// In METAL rather than turret count, so the same ratio buys more of a cheap
// turret than an expensive one and one constant covers all factions.
const float AA_VS_AIR = 0.10f;

// Turrets the side should hold BEYOND basic cover. Rounded, not truncated, so
// a want of 1.98 is not thrown away down to 1.
int AATopUp(float enemyAir, float costM)
{
	if ((enemyAir <= 0.f) || (costM <= 1.f))
		return 0;
	const float k = ai.GetTunable("apex_aa_vs_air", TUNE_AA_VS_AIR);
	return int((enemyAir * k) / costM + 0.5f);
}

// DENSITY, not position, is the anti-blob test: CheapAA and Fortify place at the
// constructor's own position, so a position-only gate (e.g. "not behind the
// front") never catches turrets piling up in the back of the base. Not a total
// cap -- the eighth turret within this radius adds nothing the seventh did not,
// but the line itself is allowed a higher density (see TooCrowded).
const float BLOB_RADIUS = 420.f;

// The circle one AA request covers. Smaller than BLOB_RADIUS on purpose: this
// answers "is that order already placed", not "does this ground have enough
// AA" (TooCrowded above answers that one).
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
	// Anti-air answers to the defence policy too, since it also places at the
	// constructor's own position rather than by where it's actually wanted.
	if (!Military::DefenceAllowedAt(here, aa))
		return null;
	// AA owns a circle, not a point: another AA of this def already ordered
	// anywhere in it counts as this order, already placed.
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

// armrl/corrl/legrl is DETERRENCE, not an answer versus T2 air. A second,
// heavier VTOL-only tier (cormadsam/armferret/legflak) sizes by the same
// metal-vs-enemy-air ratio; AADefFor picks the tier by ground, AATopUp sizes
// whichever one is picked by its own cost.
const bool  AA_HEAVY_ON          = true;
const float AA_HEAVY_MIN_INCOME  = 20.f;
const int   AA_HEAVY_PERIOD      = 25 * SECOND;
int gNextHeavyAA = 0;
string armferret("armferret"); string cormadsam("cormadsam"); string legflak("legflak");

// A few towers at home, early, so a raid is not worth attempting: the same
// deterrence argument the cheap-AA floor rests on. Bounded hard (standing cap,
// near home only, before an advanced factory) since this is a spend rule.
string armbeamer("armbeamer"); string corhllt("corhllt"); string legmg("legmg");
const int   DETER_HOME_MAX    = 3;
const float DETER_MIN_INCOME  = 8.f;
const float DETER_RADIUS      = 900.f;
const int   DETER_PERIOD      = 30 * SECOND;
int gNextDeter = 0;

// Shields over the base: armgate/corgate/legdeflector are near-identical
// (~3,000m/~55,000e), so one rule covers all three. Legion's is legdeflector,
// declared with weapontype "Shield" rather than a shieldpower field.
//
// Gated on ENERGY rather than metal: a shield's real cost is its upkeep, and one
// running dry is 3,000 metal doing nothing. Placed by the coverage score, so
// shields spread across the approaches instead of stacking on one.
string armgate("armgate"); string corgate("corgate"); string legdeflector("legdeflector");
// All three declare energyupkeep 0 and powerregenenergy 562.5, so a dome draws
// nothing idle and 562.5 energy/second while regenerating what it just absorbed.
// That draw is the real gate; the margin covers the rest of the base through it.
const float SHIELD_REGEN_DRAW  = 562.5f;
const float SHIELD_DRAW_MARGIN = 1.5f;
// Seconds of income per dome, against the def's OWN cost, so the count follows
// the economy rather than sitting at a fixed ceiling.
const float SHIELD_INCOME_SECS = 100.f;
const int   SHIELD_PERIOD     = 60 * SECOND;
int gNextShield = 0;
int gShieldsAsked = 0;

int ShieldsAfforded(CCircuitDef@ dome)
{
	if ((dome is null) || (dome.costM <= 0.f))
		return 0;
	const float secs = ai.GetTunable("apex_shield_income_secs", TUNE_SHIELD_INCOME_SECS);
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
			* ai.GetTunable("apex_shield_draw_margin", TUNE_SHIELD_DRAW_MARGIN))
		return null;
	// Not before the first reactor: a dome's value is what stands under it,
	// and pre-fusion nothing under it is worth the dome. Economy-staged, not
	// clocked. apexearth 2026-08-15: "we also started making a shield
	// generator too early."
	if (!HaveReactor())
		return null;
	if (aiBuilderMgr.GetWorkerCount() <= DEF_CON_FLOOR)
		return null;
	CCircuitDef@ dome = SideDef3(armgate, corgate, legdeflector);
	if ((dome is null) || !dome.IsAvailable(ai.frame)
		|| (dome.count >= ShieldsAfforded(dome)))
		return null;
	// In-flight allowance scales with income: one at a time was right when a
	// dome was a real spend, but at LRPC-era income the pace, not the count,
	// was the bottleneck (afforded ~17, ordered 1/minute).
	if (gShieldsAsked - dome.count
			>= 1 + int(aiEconomyMgr.metal.income
				/ ai.GetTunable("apex_shield_flight_per", TUNE_SHIELD_FLIGHT_PER)))
		return null;
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
	// The spacing shortens as income grows, same reasoning as the allowance.
	gNextShield = ai.frame + SHIELD_PERIOD
			/ (1 + int(aiEconomyMgr.metal.income
				/ ai.GetTunable("apex_shield_flight_per", TUNE_SHIELD_FLIGHT_PER)));
	AiLog(Factory::T() + "apex: shield " + dome.GetName() + " standing=" + dome.count
		+ "/" + ShieldsAfforded(dome)
		+ " eInc=" + formatFloat(aiEconomyMgr.energy.income, "", 0, 0)
		+ " mInc=" + formatFloat(aiEconomyMgr.metal.income, "", 0, 0));
	return post;
}

// Jammers over the base, ordered directly rather than left to the build_chain
// hubs on armrad/corrad/armfrad/corfrad -- a hub fires only when its exact
// parent finishes, so base jamming was a side effect of whether a radar tower
// happened to get built. Def names and the AreaHasJammer anti-clustering ledger
// are shared with digin.as so the two placement paths cannot cluster together.
//
// The long-range triple (armveil/corshroud/legajam) is cheaper in metal and
// covers 2-4x the area of the short tower, at the cost of far higher energy
// upkeep; the short defs remain the fallback for a side that cannot build the
// long one yet.
const int   JAMMER_PERIOD     = 45 * SECOND;
const float JAMMER_UPKEEP_LONG  = 125.f;
const float JAMMER_UPKEEP_SHORT = 40.f;
// Jam radius of the SMALLEST of each triple (corshroud 700, corjamt 360), so the
// placement is right for every faction rather than for the best one.
const float JAMMER_COVER_LONG   = 700.f;
const float JAMMER_COVER_SHORT  = 360.f;
// Income per unit of upkeep before we will run one, applied to whichever def we
// actually place so the bar moves with the tower rather than fitting only one.
const float JAMMER_UPKEEP_MARGIN = 4.f;
// Share of energy income jamming may hold in total. Metal is not the
// constraint here (125 metal is nothing), so the bound is on energy upkeep.
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
	const float share = ai.GetTunable("apex_jammer_energy_share", TUNE_JAMMER_ENERGY_SHARE);
	return int(aiEconomyMgr.energy.income * share / upkeep);
}

// EYES OVER THE GROUND WE HOLD. CMilitaryManager::DefaultMakeSensors refuses
// to place radar inside our own zone (IsZoneAlly early-return) and only fires
// at contested clusters, so held territory is radar-dark by construction --
// the enemy model reads near-zero all game and every engagement is a surprise.
// One radar at the territory centre, then one per border rank: coverage grows
// with the ground held, never a fixed count. Standing positions are tracked in
// gRadarStand (events.as) so a dead radar's rank re-opens.
const int   RADAR_PERIOD    = 20 * SECOND;
const float RADAR_COVER     = 1600.f;          // spacing well inside the T1 triple's radius
const int   RADAR_ORDER_TTL = 2 * 60 * SECOND; // an ask that never built stops blocking
array<AIFloat3> gRadarStand;   // standing radar towers, kept by events.as
array<AIFloat3> gRadarAskPos;  // asks in flight, TTL-bounded
array<int>      gRadarAskAt;
int gNextRadar = 0;

CCircuitDef@ RadarTowerDef()
{
	return SideDef3("armrad", "corrad", "legrad");
}

// Ledger accessors for main.as's AiUnitFinished/AiUnitDestroyed -- functions
// are visible module-wide regardless of include order, globals are not.
void RadarStandAdd(const AIFloat3& in pos)
{
	gRadarStand.insertLast(pos);
	AiLog(Factory::T() + "apex: radar-net standing +1 = " + gRadarStand.length());
}

void RadarStandRemoveNear(const AIFloat3& in pos)
{
	int nearest = -1;
	float best = 1.0e18f;
	for (uint i = 0; i < gRadarStand.length(); ++i) {
		const float d = gRadarStand[i].distance2D(pos);
		if (d < best) { best = d; nearest = int(i); }
	}
	if (nearest >= 0)
		gRadarStand.removeAt(uint(nearest));
}

bool AreaHasRadar(const AIFloat3& in pos)
{
	for (int i = int(gRadarAskAt.length()) - 1; i >= 0; --i) {
		if (ai.frame - gRadarAskAt[i] > RADAR_ORDER_TTL) {
			gRadarAskAt.removeAt(i);
			gRadarAskPos.removeAt(i);
		} else if (gRadarAskPos[i].distance2D(pos) <= RADAR_COVER) {
			return true;
		}
	}
	for (uint i = 0; i < gRadarStand.length(); ++i) {
		if (gRadarStand[i].distance2D(pos) <= RADAR_COVER)
			return true;
	}
	return false;
}

IUnitTask@ RadarNet(CCircuitUnit@ unit)
{
	if (!gHomeSet || !Factory::HaveAnyFactory())
		return null;                       // never touches the opening
	if (ai.frame < gNextRadar)
		return null;
	if (aiBuilderMgr.GetWorkerCount() <= DEF_CON_FLOOR)
		return null;
	CCircuitDef@ rad = RadarTowerDef();
	if ((rad is null) || !rad.IsAvailable(ai.frame)
		|| !unit.circuitDef.CanBuild(rad))
		return null;
	// THE HOME BASE IS RANK ZERO, unconditionally. TerritoryCentre walks
	// forward as ground is taken, so the base itself was never a rank of its
	// own and went dark whenever the early radar died -- apexearth: "we need
	// a radar in our home base." Then the centre of held ground, then out
	// along the border ranks, indexed by what actually STANDS -- a radar
	// dying re-opens its rank.
	AIFloat3 anchor;
	if (!AreaHasRadar(gHomePos)) {
		anchor = gHomePos;
	} else {
		anchor = Military::TerritoryCentre();
		const uint standing = gRadarStand.length();
		if (standing > 0) {
			AIFloat3 border;
			if (!Military::BorderPos(border, standing - 1))
				return null;               // every rank covered: done for now
			anchor = border;
		}
	}
	if (!OnMap(anchor) || AreaHasRadar(anchor))
		return null;
	const AIFloat3 site = ai.FindBuildSiteNear(rad, anchor, RADAR_COVER * 0.4f);
	if (!OnMap(site) || (ThreatFor(unit, site) > CON_THREAT_VETO))
		return null;
	if (AreaHasRadar(site))
		return null;
	bool created = false;
	IUnitTask@ post = Requests::Take(unit, rad, Task::BuildType::RADAR,
			Task::Priority::NORMAL, site, 0.f, 0.f, created);
	if (post is null)
		return null;
	if (!created)
		return post;
	gRadarAskPos.insertLast(site);
	gRadarAskAt.insertLast(ai.frame);
	gNextRadar = ai.frame + RADAR_PERIOD;
	AiLog(Factory::T() + "apex: radar-net " + rad.GetName()
		+ " standing=" + gRadarStand.length()
		+ " at=" + int(site.x) + "," + int(site.z));
	return post;
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
	if (int(jam.count) >= JammersAfforded(upkeep))
		return null;
	// Asked-minus-standing, the same idiom NukeSilo and Shield use: Enqueue does
	// not dedup and a jammer takes a while, so counting only what stands orders
	// the whole set at once.
	if (gJammersAsked - int(jam.count) >= 1)
		return null;

	// The middle of the base, not the spawn point: gHomePos never moves, so as the
	// base grows forward it ends up behind everything worth hiding. TerritoryCentre
	// is the centroid of the metal clusters we hold instead, falling back to
	// gHomePos before we hold any. Later ones move out to the approaches.
	// EVEN COVERAGE, NOT A HEAP AT THE MIDDLE. Indexing the border ring by our
	// own jammer count walks the ring in whatever order BorderPos returns it,
	// which is not the order that covers the base -- apexearth: "they should be
	// spread out evenly so we have jammer coverage over all of our base". The
	// pick is the candidate FURTHEST from any jamming we already have, the same
	// least-covered-first idea the front fence uses.
	AIFloat3 anchor = Military::TerritoryCentre();
	if (jam.count > 0) {
		float bestGap = Builder::NearestJammerDist(anchor);
		const int ring = int(ai.GetTunable("apex_jammer_ring", TUNE_JAMMER_RING));
		for (int k = 0; k < ring; ++k) {
			AIFloat3 cand;
			if (!Military::BorderPos(cand, uint(k)))
				continue;
			if (!OnMap(cand))
				continue;
			const float gap = Builder::NearestJammerDist(cand);
			if (gap < 0.f) {          // nothing jams this ground at all
				anchor = cand;
				break;
			}
			if (gap > bestGap) {
				bestGap = gap;
				anchor = cand;
			}
		}
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
	// A REACTOR MUST STAND FIRST, whatever the income reads: an advsolar farm
	// passes the income bar, and three T3 guns went up before any fusion --
	// apexearth, watching: "3 t3 defense before we even had a fusion
	// *facepalm*". The gun is 37,000-74,000 energy to fire; a farm that
	// merely reaches the income bar is spent the moment it shoots.
	if (!HaveReactor())
		return null;
	CCircuitDef@ gun = SideDef3(armanni, cordoom, legbastion);
	if ((gun is null) || !gun.IsAvailable(ai.frame) || (gun.count >= PulsarCap()))
		return null;
	// Caps how many are going up AT ONCE (a different question from how many we
	// end up with): each is 3,000-4,200 metal, so several simultaneous nanoframes
	// freeze most of a mid-game bank in towers that defend nothing until they
	// finish.
	// A full metal bank lifts the build-rate throttle: the freeze-the-bank
	// risk the base cap guards against is exactly the state we are in.
	// apexearth: "we're full on metal so we ought to be able to afford that."
	int conc = PULSAR_CONCURRENT;
	if (aiEconomyMgr.isMetalFull)
		conc = int(ai.GetTunable("apex_pulsar_conc_full", TUNE_PULSAR_CONC_FULL));
	// In-flight from the task registry, not asked-minus-standing: a pulsar
	// task that dies (front site lost, walker killed) never becomes standing,
	// so the asked ledger only ever grows and wedged this rule shut after
	// `conc` asks for the rest of the game.
	if (int(Requests::InFlight(gun)) >= conc)
		return null;
	// THE LINE THE BRAIN DRAWS, not the site ring. BorderPos picks among OUR
	// OWN sites on the territory ring, which in practice is the base edge --
	// watched 2026-08-16: 26 Annihilators standing, every one "at-border",
	// none on what apexearth calls a front line. Same influence-crossing curve
	// FrontDefenceWant holds, least-covered stretch first, pulled back a
	// quarter of the gun's own range so it goes up BEHIND the line; the old
	// border/standoff answers stay as fallbacks.
	AIFloat3 spot;
	string where = "line";
	bool sited = false;
	const float span = Brain::TowerReach(gun);
	// A BLOCK OF FOUR, NOT A LINE OF ONES. apexearth, twice: heavy guns should
	// stand right next to each other -- four in one compact square is four times
	// the damage over the same ground, and every siting rule below deliberately
	// spreads instead (each refuses ground already covered, and the front-line
	// branch picks the LEAST covered point). This runs first and is exempt from
	// that spacing by design; once a block reaches its size the rules below pick
	// where the next block starts.
	{
		const int per = int(ai.GetTunable("apex_pulsar_block", TUNE_PULSAR_BLOCK));
		const float blockR = ai.GetTunable("apex_pulsar_block_r", TUNE_PULSAR_BLOCK_R);
		array<CCircuitUnit@>@ have = (gun.count > 0)
				? ai.GetOwnUnitsOfDef(gun, gHomePos, 0.f) : null;
		CCircuitUnit@ seed = null;
		if (have !is null) {
			for (uint i = 0; i < have.length(); ++i) {
				if (have[i] is null)
					continue;
				const AIFloat3 at = have[i].GetPos(ai.frame);
				if (!OnMap(at))
					continue;
				// A REAR GUN DOES NOT SEED A BLOCK. The block rule runs first
				// and was position-blind, so one badly-placed early gun bred
				// a whole square of T3 defence in the back of the base --
				// apexearth, watching: "we make T3 defenses BEHIND our
				// factories which is stupid." A rearward gun is left alone;
				// the next gun falls through to the nano-cluster/front-line
				// siting, which is front-biased by construction.
				if (Military::ForwardFraction(at)
					< ai.GetTunable("apex_pulsar_block_fwd", TUNE_PULSAR_BLOCK_FWD))
				{
					continue;
				}
				int n = 0;
				for (uint j = 0; j < have.length(); ++j) {
					if ((have[j] !is null)
						&& (have[j].GetPos(ai.frame).distance2D(at) <= blockR))
						++n;
				}
				if (n < per) {
					@seed = have[i];
					break;
				}
			}
		}
		if (seed !is null) {
			const AIFloat3 s = ai.FindBuildSiteNear(gun,
					seed.GetPos(ai.frame), blockR);
			if (OnMap(s) && (ThreatFor(unit, s) <= CON_THREAT_VETO)) {
				spot = s;
				where = "block";
				sited = true;
			}
		}
	}
	// THE NANO CLUSTER FIRST, when it sits toward the front: the turrets
	// build the gun at lathe speed and repair it under fire -- apexearth:
	// "we should make more pulsars near where our groupings of nano turrets
	// are, towards the front of our bases." A rear (eco) cluster falls
	// through to the front-line siting below.
	{
		AIFloat3 nn;
		if (NanoCluster(nn)
			&& (Military::ForwardFraction(nn)
				>= ai.GetTunable("apex_pulsar_nano_fwd", TUNE_PULSAR_NANO_FWD)))
		{
			const AIFloat3 s = ai.FindBuildSiteNear(gun, nn, 450.f);
			if (OnMap(s) && (ThreatFor(unit, s) <= CON_THREAT_VETO)
				&& !Builder::DefenceTaskNear(s, span * 0.5f))
			{
				spot = s;
				where = "nano-cluster";
				sited = true;
			}
		}
	}
	if (!sited && (span > 200.f)) {
		array<AIFloat3> line;
		if (Military::FrontLineSpots(line, span * 0.8f, span) && (line.length() > 0)) {
			bool have = false;
			uint fewest = 0;
			for (uint i = 0; i < line.length(); ++i) {
				if (!OnMap(line[i]))
					continue;
				if (Builder::DefenceTaskNear(line[i], span * 0.8f))
					continue;
				AIFloat3 back = line[i];
				if (gHomeSet) {
					AIFloat3 dir = gHomePos - line[i];
					if (dir.SqLength2D() > NEAR_ZERO) {
						dir.SafeNormalize2D();
						back = line[i] + dir * (span * 0.25f);
					}
				}
				if (!OnMap(back) || (ThreatFor(unit, back) > CON_THREAT_VETO))
					continue;
				const uint cover = Military::FenceCountNear(line[i], span);
				if (!have || (cover < fewest)) {
					fewest = cover;
					spot = back;
					have = true;
				}
			}
			if (have) {
				const AIFloat3 site = ai.FindBuildSiteNear(gun, spot, span * 0.5f);
				if (OnMap(site)) {
					spot = site;
					sited = true;
				}
			}
		}
	}
	if (!sited) {
		where = "border";
		if (!Military::BorderPos(spot, uint(gun.count))) {
			where = "front";
			if (!Military::FrontLinePos(spot)) {
				where = "standoff";
				if (!StandoffPos(unit, unit.GetPos(ai.frame), spot))
					return null;
			}
		}
	}
	bool created = false;
	// NO SHAKE ON A BLOCK SITE. IBuilderTask applies get_near_pos(position,
	// shake) when shake > 0, so DEF_SHAKE's 256 elmos of jitter would scatter
	// the very adjacency the block branch just computed. Spread siting still
	// wants the jitter, so it keeps it.
	IUnitTask@ post = Requests::Take(unit, gun, Task::BuildType::DEFENCE,
			Task::Priority::NORMAL, spot, 0.f,
			(where == "block") ? 0.f : DEF_SHAKE, created);
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
// waste anyway. Nuke target selection itself lives in the C++ SuperTask and is
// not something this rule controls.
//
// The energy cost (90,000/82,000 to build) is what actually gates it, roughly a
// fusion-minute, so the bar is set on energy income rather than metal or a
// clock. Advanced constructors only -- a T1 constructor cannot build one.
string armsilo("armsilo"); string corsilo("corsilo"); string legsilo("legsilo");
string armamd("armamd");   string corfmd("corfmd");   string legabm("legabm");

// A silo is 8,100 metal and 90,000 energy before a single missile, so it has to
// come out of real surplus rather than the army budget.
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

// Energy is the half of the cost that actually hurts (90,000 to build), so a
// metal bank at the cap on its own is not enough to say the next one is free.
bool NukeSurplus()
{
	return (aiEconomyMgr.metal.storage > 0.f) && (aiEconomyMgr.energy.storage > 0.f)
		&& (aiEconomyMgr.metal.current > aiEconomyMgr.metal.storage * NUKE_FULL_FRAC)
		&& (aiEconomyMgr.energy.current > aiEconomyMgr.energy.storage * NUKE_FULL_FRAC);
}

int NukeCap()
{
	// Both banks at the cap removes the cap entirely: resources sitting at
	// storage are already wasted, so there is nothing left for another silo to
	// displace. Caps how many may STAND, not how many at once -- the outstanding
	// test below still serialises to one in flight.
	return NukeSurplus() ? 999 : 1;
}

IUnitTask@ NukeSilo(CCircuitUnit@ unit)
{
	if (aiEconomyMgr.isEnergyStalling)
		return null;
	if (unit.circuitDef.costM < ADV_CON_COST)
		return null;
	// The income and half-bank bars are a proxy for "can we afford one without
	// starving the rest"; both banks over 80% answers that directly, so the proxy
	// is skipped. The energy floor is not itself a proxy -- it is the running
	// cost: a missile is 90,000 energy to stockpile, so a silo on a thin grid
	// holds the whole economy down for as long as it stands, which a full bank
	// (storage is small next to a reactor's output) does not tell you.
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

	// Behind the base, in the nano field, widening the search rather than giving
	// up on the first failure: the nano cluster is the densest patch of the base
	// and a narrow radius there routinely finds nothing. Same fallback shape the
	// gantry rule uses.
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

// ANTINUKE -- apexearth: "standard for all games where nukes are allowed."
// One as soon as a T2 constructor and a modest economy exist; more as income
// grows (a bigger base has more to lose and more area to cover). No flat cap.
int gAntiAsked = 0;
int gAntiPeak = 0;

// Heavy AA is ORDERED, not merely uncapped: UpdateAirThreat computed a want
// and only raised maxThisUnit -- nothing ever elected the build. Measured
// (8v8 Isthmus, 22 min): 18,000 metal of enemy air, heavy=0/4, apexearth:
// "we have very few anti air buildings to handle when enemy air shows up."
// Same request shape as AntiNuke below, sited over the nano cluster.
int gFlakAsked = 0;
int gFlakPeak = 0;
int gFlakPostAt = 0;
int gNextFlak = 0;

IUnitTask@ HeavyFlak(CCircuitUnit@ unit)
{
	if (aiEconomyMgr.isEnergyStalling || (ai.frame < gNextFlak))
		return null;
	Military::ResolveHeavyAA();
	CCircuitDef@ flak = Military::gFlak;
	if ((flak is null) || !flak.IsAvailable(ai.frame))
		return null;
	const int want = Military::HeavyAAWant();
	if (want <= 0)
		return null;
	// Flak is T2-buildable only, and the adv cons rarely fall through to this
	// rule -- the same capability starvation that kept fusions at zero (see
	// EcoFusion). An incapable asker posts the task to the pool instead of
	// dropping the want (seed 33: heavy want 6, standing 0, for 12 minutes).
	if (!unit.circuitDef.CanBuild(flak)) {
		const int standingNow = int(flak.count) + Military::LiveCount(Military::gHeavy);
		// A posted task an adv con never took wedged this at asked=peak+2
		// forever (measured: want=1 from 24m to game end, zero flak). Same
		// resync the nano counter uses: if nothing has finished for a while,
		// the outstanding orders are orphans -- forget them and re-post.
		if ((gFlakAsked > gFlakPeak)
			&& (ai.frame - gFlakPostAt > 3 * MINUTE))
		{
			gFlakAsked = gFlakPeak;
		}
		if ((standingNow < want) && (gFlakAsked - gFlakPeak < 2)) {
			AIFloat3 poolAt;
			if (!NanoCluster(poolAt))
				poolAt = gHomePos;
			if (OnMap(poolAt)) {
				IUnitTask@ posted = Requests::Create(flak,
						Task::BuildType::DEFENCE, Task::Priority::HIGH,
						poolAt, SQUARE_SIZE * 32);
				if (posted !is null) {
					++gFlakAsked;
					gFlakPostAt = ai.frame;
					AiLog(Factory::T() + "apex: flak posted to the pool -- "
						+ standingNow + "/" + want + " standing");
				}
			}
		}
		return null;
	}
	const int standing = int(flak.count) + Military::LiveCount(Military::gHeavy);
	if (standing > gFlakPeak)
		gFlakPeak = standing;
	// Two outstanding at a time: air raids justify parallel builds in a way
	// one antinuke never does, but the want still bounds the total.
	if ((standing >= want) || (gFlakAsked - gFlakPeak >= 2))
		return null;
	// LATE GAME, FLAK GOES FORWARD: past apex_front_flak_income the front
	// line gets the flak, not just the base -- apexearth: "at late game we
	// should be aggressive with flak on our front lines... Right now we are
	// *not* aggressive with this at all." Base placement remains the early
	// answer and the fallback when no front spot stands.
	AIFloat3 near;
	bool sited = false;
	if (aiEconomyMgr.metal.income
			>= ai.GetTunable("apex_front_flak_income", TUNE_FRONT_FLAK_INCOME)) {
		sited = Military::BorderPos(near, uint(flak.count))
			|| Military::FrontLinePos(near);
	}
	if (!sited && !NanoCluster(near))
		near = gHomePos;
	AIFloat3 site = ai.FindBuildSiteNear(flak, near, GANTRY_NEAR_NANO);
	if (!OnMap(site))
		site = ai.FindBuildSiteNear(flak, gHomePos, GANTRY_SEARCH_WIDE);
	if (!OnMap(site) || (ThreatFor(unit, site) > CON_THREAT_VETO))
		return null;
	bool created = false;
	IUnitTask@ post = Requests::Take(unit, flak, Task::BuildType::DEFENCE,
			Task::Priority::HIGH, site, 0.f, 0.f, created);
	if (post is null)
		return null;
	if (!created)
		return post;
	++gFlakAsked;
	gNextFlak = ai.frame + 15 * SECOND;
	AiLog(Factory::T() + "apex: heavy-flak " + flak.GetName()
		+ " standing=" + standing + " want=" + want);
	return post;
}

// PIPELINE LANE: FRONT FORTRESSES. The old path to a front-line big turret
// needed five soft dependencies to align (a free adv con, winning the
// election, the fence want, the heavy ladder, the popup ratio) and produced
// ONE per game -- apexearth, repeatedly: "we still just have one T3 defense
// ... our logic is terrible around these things." This is the straight
// version: past apex_front_t3_income the front is OWED big turrets, one per
// apex_front_t3_per of income, built by the first free adv con, sited on the
// border ranks. Income-scaled, no cap, one in flight.
int gFortAsked = 0;
int gFortPeak = 0;

IUnitTask@ FrontFortress(CCircuitUnit@ unit)
{
	if (aiEconomyMgr.isEnergyStalling)
		return null;
	if (aiEconomyMgr.metal.income
			< ai.GetTunable("apex_front_t3_income", TUNE_FRONT_T3_INCOME))
		return null;
	CCircuitDef@ big = SideDef3(armpulsar, corpulsar, legpulsar);
	if ((big is null) || !big.IsAvailable(ai.frame)
		|| !unit.circuitDef.CanBuild(big))
		return null;
	const int standing = int(big.count);
	if (standing > gFortPeak)
		gFortPeak = standing;
	const int want = 1 + int(aiEconomyMgr.metal.income
			/ ai.GetTunable("apex_front_t3_per", TUNE_FRONT_T3_PER));
	if ((standing >= want) || (gFortAsked - gFortPeak >= 1))
		return null;
	AIFloat3 spot;
	if (!Military::BorderPos(spot, uint(standing))
		&& !Military::FrontLinePos(spot))
		return null;
	AIFloat3 site = ai.FindBuildSiteNear(big, spot, 700.f);
	if (!OnMap(site) || (ThreatFor(unit, site) > CON_THREAT_VETO))
		return null;
	bool created = false;
	IUnitTask@ post = Requests::Take(unit, big, Task::BuildType::DEFENCE,
			Task::Priority::HIGH, site, 0.f, 0.f, created);
	if (post is null)
		return null;
	if (!created)
		return post;
	++gFortAsked;
	AiLog(Factory::T() + "apex: front fortress " + big.GetName()
		+ " standing=" + standing + " want=" + want
		+ " at=" + int(site.x) + "," + int(site.z));
	return post;
}

IUnitTask@ AntiNuke(CCircuitUnit@ unit)
{
	if (aiEconomyMgr.isEnergyStalling)
		return null;
	if (unit.circuitDef.costM < ADV_CON_COST)
		return null;
	// The income bar is readiness, not permission: a SEEN enemy launcher
	// overrides it -- being poor does not make the incoming nuke cheaper.
	if ((aiEconomyMgr.metal.income < Policy::AntinukeIncome())
		&& (Brain::EnemyNukeSilos() == 0))
	{
		return null;
	}
	// The ASSUMED silo only exists once the enemy has the tech for one: no
	// enemy T2 on the field means no nuke is possible, whatever our income.
	if ((Brain::EnemyNukeSilos() == 0) && !Factory::gEnemyT2Seen)
		return null;
	CCircuitDef@ anti = SideDef3(armamd, corfmd, legabm);
	if ((anti is null) || !anti.IsAvailable(ai.frame))
		return null;
	const int standing = int(anti.count);
	if (standing > gAntiPeak)
		gAntiPeak = standing;
	// Matched to the THREAT, not the income: one anti per enemy launcher we
	// have seen, floored at one for the launcher we have not.
	int want = 1;
	const int foeSilos = Brain::EnemyNukeSilos();
	if (foeSilos > want)
		want = foeSilos;
	// Outstanding as well as standing, same reason as the silo: Enqueue does
	// not dedup and this builds slowly.
	if ((standing >= want) || (gAntiAsked - gAntiPeak >= 1))
		return null;

	AIFloat3 near;
	const bool haveNano = NanoCluster(near);
	if (!haveNano)
		near = gHomePos;
	AIFloat3 site = ai.FindBuildSiteNear(anti, near, GANTRY_NEAR_NANO);
	if (!OnMap(site) && haveNano)
		site = ai.FindBuildSiteNear(anti, gHomePos, GANTRY_NEAR_NANO);
	if (!OnMap(site))
		site = ai.FindBuildSiteNear(anti, gHomePos, GANTRY_SEARCH_WIDE);
	if (!OnMap(site) || (ThreatFor(unit, site) > CON_THREAT_VETO))
		return null;

	bool created = false;
	IUnitTask@ post = Requests::Take(unit, anti, Task::BuildType::DEFENCE,
			Task::Priority::NORMAL, site, 0.f, 0.f, created);
	if (post is null)
		return null;
	if (!created)
		return post;
	++gAntiAsked;
	AiLog(Factory::T() + "apex: antinuke " + anti.GetName()
		+ " standing=" + standing + " want=" + want
		+ " mInc=" + formatFloat(aiEconomyMgr.metal.income, "", 0, 0));
	return post;
}

//------------------------------------------------------------------------------
// LRPC SIEGE -> SHIELDS. apexearth 2026-08-19: "If we are being attacked by
// LRPC we need to make shields. If our shields are failing we need to make
// more shields." One deflector per bombarding gun, plus one for every shield
// of ours the guns have already broken -- the census is the trigger, the loss
// memory is the escalation. leggatet3 has no builder in the pinned tree, so
// the CanBuild guard makes this a no-op for Legion until a game ships one.
//------------------------------------------------------------------------------
string armgateS("armgate"); string corgateS("corgate"); string leggateS("legdeflector");

int gLrpcN = 0;
int gLrpcNext = 0;

int EnemyLRPCs()
{
	if (ai.frame < gLrpcNext)
		return gLrpcN;
	gLrpcNext = ai.frame + 10 * SECOND;
	const float w = float(AiTerrainWidth());
	const float h = float(AiTerrainHeight());
	AIFloat3 mid(w * 0.5f, 0.f, h * 0.5f);
	const float r = sqrt(w * w + h * h) * 0.5f + 1.f;
	array<string> guns = {"armbrtha", "corint", "leglrpc",
			"armvulc", "corbuzz", "legstarfall"};
	int n = 0;
	for (uint i = 0; i < guns.length(); ++i) {
		CCircuitDef@ d = ai.GetCircuitDef(guns[i]);
		if (d !is null)
			n += ai.CountEnemyDefNear(d.id, mid, r);
	}
	gLrpcN = n;
	return n;
}

// Our shields that have died, remembered for apex_shield_loss_memory seconds.
array<int> gShieldLostAt;

void NoteShieldLost(const CCircuitDef@ d)
{
	if (d is null)
		return;
	CCircuitDef@ sh = SideDef3(armgateS, corgateS, leggateS);
	if ((sh !is null) && (d.id == sh.id))
		gShieldLostAt.insertLast(ai.frame);
}

int ShieldsLostRecent()
{
	const int life = int(ai.GetTunable("apex_shield_loss_memory", TUNE_SHIELD_LOSS_MEMORY)) * SECOND;
	for (int i = int(gShieldLostAt.length()) - 1; i >= 0; --i) {
		if (ai.frame - gShieldLostAt[i] > life)
			gShieldLostAt.removeAt(i);
	}
	return int(gShieldLostAt.length());
}

int gShieldAsked = 0;
int gShieldPeak = 0;

IUnitTask@ ShieldCover(CCircuitUnit@ unit)
{
	if (aiEconomyMgr.isEnergyStalling)
		return null;
	CCircuitDef@ sh = SideDef3(armgateS, corgateS, leggateS);
	if ((sh is null) || !sh.IsAvailable(ai.frame)
		|| !unit.circuitDef.CanBuild(sh))
	{
		return null;
	}
	const int lrpc = EnemyLRPCs();
	if (lrpc <= 0)
		return null;
	// A dome the economy cannot carry is not insurance -- below the bar the
	// spread/dodge behaviors answer the gun (Policy::ShieldIncome).
	if (aiEconomyMgr.metal.income < Policy::ShieldIncome())
		return null;
	const int standing = int(sh.count);
	if (standing > gShieldPeak)
		gShieldPeak = standing;
	// One dome shields the whole core from every gun in reach, so per-gun
	// sizing overbuilt ~3x (apexearth 2026-08-19: "we are now making too many
	// shields... probably three times stronger than it needs to be"). One
	// dome, plus one per apex_shield_per additional guns-or-broken-shields.
	const int per = int(ai.GetTunable("apex_shield_per", TUNE_SHIELD_PER));
	const int want = 1 + ((lrpc - 1) + ShieldsLostRecent()) / ((per > 0) ? per : 3);
	if ((standing >= want) || (gShieldAsked - gShieldPeak >= 2))
		return null;
	AIFloat3 near;
	if (!NanoCluster(near))
		near = gHomePos;
	AIFloat3 site = ai.FindBuildSiteNear(sh, near, GANTRY_NEAR_NANO);
	if (!OnMap(site))
		site = ai.FindBuildSiteNear(sh, gHomePos, GANTRY_SEARCH_WIDE);
	if (!OnMap(site) || (ThreatFor(unit, site) > CON_THREAT_VETO))
		return null;
	bool created = false;
	IUnitTask@ post = Requests::Take(unit, sh, Task::BuildType::DEFENCE,
			Task::Priority::HIGH, site, 0.f, 0.f, created);
	if (post is null)
		return null;
	if (!created)
		return post;
	++gShieldAsked;
	AiLog(Factory::T() + "apex: shield " + sh.GetName()
		+ " vs " + lrpc + " LRPC, lost=" + ShieldsLostRecent()
		+ " standing=" + standing + " want=" + want);
	return post;
}

//------------------------------------------------------------------------------
// ANSWER THE PUSH WHILE IT IS STILL WALKING. Military::UpdateApproach declares
// a visible enemy group closing on our home; this sites heavy defence on the
// LINE it is walking, sized to what is coming -- one tower per
// apex_push_answer_per of incoming metal. HIGH priority: the whole point is
// beating the walk. apexearth 2026-08-19: "It is visible long before they even
// get to our base... Why aren't we preparing for it?"
//------------------------------------------------------------------------------
int gPushAnsLog = 0;

IUnitTask@ PushAnswer(CCircuitUnit@ unit)
{
	if (!Military::PushIncoming() || aiEconomyMgr.isEnergyStalling)
		return null;
	if (!gHomeSet)
		return null;
	// THE TIER FOLLOWS THE ECONOMY, NOT THE BUILDER. At 600 m/s the answer to
	// a push was still beamers and claws -- "largely not worth having at this
	// point... a two by two square of pulsars all tightly packed would be a
	// more advantageous setup taking less overall room" (apexearth, watching
	// at 40m). Dearest tower this builder can place whose cost is inside
	// apex_def_afford_secs of metal income; the basic tower stays as the
	// unconditional floor (something NOW beats the right tower never -- the
	// pre-T2 mute, measured).
	const float afford = aiEconomyMgr.metal.income
			* ai.GetTunable("apex_def_afford_secs", TUNE_DEF_AFFORD_SECS);
	array<CCircuitDef@> ladder = {
		SideDef3(armanni, cordoom, legbastion),   // the pulsar line
		PopupTowerDef(),
		MidTowerDef()
	};
	CCircuitDef@ tower = null;
	for (uint li = 0; li < ladder.length(); ++li) {
		CCircuitDef@ cand = ladder[li];
		if ((cand is null) || !cand.IsAvailable(ai.frame)
			|| !unit.circuitDef.CanBuild(cand) || (cand.costM > afford))
		{
			continue;
		}
		@tower = cand;
		break;
	}
	if (tower is null)
		@tower = SideDef3(armllt, corllt, leglht);
	if ((tower is null) || !tower.IsAvailable(ai.frame)
		|| !unit.circuitDef.CanBuild(tower))
	{
		return null;
	}
	// Stand on the approach line, at the base-side end of the walk.
	const AIFloat3 inc = Military::IncomingPos();
	AIFloat3 dir = inc - gHomePos;
	const float dist = sqrt(dir.SqLength2D());
	if (dist < 1.f)
		return null;
	dir *= (1.f / dist);
	float reach = dist * 0.5f;
	const float standMax = ai.GetTunable("apex_incoming_stand", TUNE_INCOMING_STAND);
	if (reach > standMax)
		reach = standMax;
	AIFloat3 stand = gHomePos + dir * reach;
	if (!OnMap(stand))
		return null;
	// Sized to the threat IN METAL: one standing LLT must not read as cover
	// against a 3k heavy. Standing guns plus orders in flight, against a
	// fraction of what is walking in (defences trade up, so a fraction is
	// parity).
	const float needM = Military::IncomingCost()
			* ai.GetTunable("apex_incoming_answer_frac", TUNE_INCOMING_ANSWER_FRAC);
	const float haveM = Military::FenceGunMetalNear(stand, 800.f)
			+ DefenceOrderMetalNear(stand, 800.f);
	if (haveM >= needM)
		return null;
	if (ThreatFor(unit, stand) > CON_THREAT_VETO)
		return null;
	AIFloat3 site = ai.FindBuildSiteNear(tower, stand, 700.f);
	if (!OnMap(site))
		return null;
	bool created = false;
	IUnitTask@ post = Requests::Take(unit, tower, Task::BuildType::DEFENCE,
			Task::Priority::HIGH, site, 0.f, 0.f, created);
	if (post is null)
		return null;
	if (created && (ai.frame >= gPushAnsLog)) {
		gPushAnsLog = ai.frame + 15 * SECOND;
		AiLog(Factory::T() + "apex: push answer " + tower.GetName()
			+ " on the approach, " + formatFloat(haveM, "", 0, 0) + "/"
			+ formatFloat(needM, "", 0, 0) + " metal vs "
			+ formatFloat(Military::IncomingCost(), "", 0, 0) + " incoming");
	}
	return post;
}

// Pinpointers (armtarg/cortarg/legtarg), capped at three for the WHOLE TEAM --
// the cap has to be a team cap rather than a per-player one, or every player
// builds "just" three and the side pays many times over for an effect that
// stops stacking at three. Advanced constructors only.
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

// Sizing only, not placement: Brain::AirCoverWant asks this for a def/count and
// places over an extractor rather than at the constructor's feet.
CCircuitDef@ AADefFor(CCircuitUnit@ unit)
{
	CCircuitDef@ heavy = SideDef3(armferret, cormadsam, legflak);
	if (LandIsPrecious() && (heavy !is null) && heavy.IsAvailable(ai.frame))
		return heavy;
	return SideDef3(armrl, corrl, legrl);
}

// THE RULE THAT CONSUMES THE SIZING BELOW. It had no caller at all -- the
// ladder's own comments described "CheapAA" while nothing invoked it, and the
// measured result was ZERO AA towers in a game the enemy won with 12k of
// bombers (2026-08-20 seed 33: aa spend 0.00 of an 0.06 target all game,
// three Samsons total). apexearth: "I do agree that we need some anti air
// even if we haven't seen any air yet" -- the no-scout floor in AAWantedNow
// is exactly that, and it only needed to be reachable again.
IUnitTask@ CheapAA(CCircuitUnit@ unit)
{
	if ((ai.frame < gNextAA) || aiEconomyMgr.isEnergyStalling)
		return null;
	if (aiEconomyMgr.metal.income < DETER_MIN_INCOME)
		return null;
	CCircuitDef@ aa = AADefFor(unit);
	if ((aa is null) || !aa.IsAvailable(ai.frame)
		|| !unit.circuitDef.CanBuild(aa))
	{
		return null;
	}
	const float enemyAir = Military::AirThreatSeen();
	const int want = AAWantedNow(unit, enemyAir);
	// This def's own standing count, not TeamAA() metal: the mix's couple of
	// Samsons satisfied a metal comparison and the TOWER floor never fired --
	// the floor is about static cover that cannot be lured away.
	if (int(aa.count) >= want)
		return null;
	return AAOrder(unit, aa, want, enemyAir);
}

// Team-wide want: Military::TeamAA() sums the side, so the floor is multiplied
// by player count rather than compared against one player's floor alone. No
// tier branch -- the divisor is the def's own cost, so all three factions size
// identically. No ceiling -- the ratio is its own bound.
int AAWantedNow(CCircuitUnit@ unit, float enemyAir)
{
	CCircuitDef@ aa = AADefFor(unit);
	array<Id>@ mates = ai.GetTeamIds();
	const int players = ((mates is null) || (mates.length() == 0))
			? 1 : int(mates.length());
	// NO SCOUTED AIR, LESS DETERRENCE FLOOR. apexearth, watching a 1v1 vs a
	// ground-only opponent: "if we don't see enemy air let's make less AA...
	// we can see the enemy is vehicles." The floor used to be unconditional
	// -- AA_MIN applied whether or not any air had ever been seen, which is
	// what made this read as a fixed tax rather than deterrence. enemyAir is
	// Military::AirThreatSeen(), already floored to 0 below AA_IGNORE, so
	// this reuses that signal rather than adding a second one.
	const int floorPer = (enemyAir > 0.f)
			? AA_MIN
			: int(ai.GetTunable("apex_aa_min_noscout", float(AA_MIN) * 0.5f));
	int want = players * floorPer;
	if (aa !is null)
		want += AATopUp(enemyAir, aa.costM);
	return (want < 1) ? 1 : want;
}

}  // namespace Builder
