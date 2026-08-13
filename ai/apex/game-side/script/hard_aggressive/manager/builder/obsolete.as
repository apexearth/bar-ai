namespace Builder {

// Reclaiming OUR OWN buildings, for two reasons that share one mechanism.
//
// 1. apexearth: "when theres no room to build a gantry we need to reclaim
//    older t1 buildings." C++ reports where a large footprint failed to place
//    (CBFactoryTask::FindBuildSite -> NoteBuildBlocked); we clear T1 clutter
//    near that spot.
// 2. apexearth: "once game is clearly in t3/t2 stage we need to reclaim all
//    our t1 and t1.5 defenses." Those towers stop earning against T2/T3 units
//    and their metal is better in something current.
//
// Targets are named defs, NOT a computed tier. CCircuitDef carries no tech
// level, so any tier test would be a heuristic -- and the failure mode here is
// reclaiming our own base, which is not a thing to be approximate about. These
// are exactly the towers ContestTower/MetalFullTower build, and the solar every
// opening puts down, so the list cannot drift away from what we actually own.
// Never mexes, never factories, never anything armed above T1.5.
const int OBSOLETE_PERIOD = 20 * SECOND;
const float OBSOLETE_NEAR = 900.f;     // around a blocked build site
// Income a T2 player must clear before stripping its own T1 defences. A player
// that has merely touched T2 may still be holding a line against T1 armies, and
// those towers are the line.
const float OBSOLETE_T2_INCOME = 60.f;
const int   OBSOLETE_MIN_PERIOD = 3 * SECOND;
// One fusion reactor's output. The unit of "how far past T1 the grid is".
const float OBSOLETE_ENERGY_SCALE = 1000.f;
int gNextObsolete = 0;
uint gObsoleteTurn = 0;

// What a piece of ground is WORTH, expressed as the energy income standing on
// the base.
//
// apexearth: "late into a game, land becomes very valuable... To have very cheap
// ineffective buildings taking up your space is very bad, and it only becomes
// more and more bad", and then the arithmetic: "you can fit, like, four wind
// turbines on the same amount of land that you can fit an advanced fusion...
// do you want sixty energy from that land? or do you want three thousand energy
// from that land?"
//
// Read from the defs: armafus produces 3000 energy, armfus 1000, armsolar 20,
// a wind turbine varies around 60. So the cost of leaving T1 eco standing is not
// its metal, it is the reactor that cannot go there -- and that cost rises with
// every reactor we could otherwise afford. Energy income is the direct measure
// of how far past T1 the grid is, so it is what sets the clearing rate.
//
// A clock cannot express that, and neither can a clutter count: at one reclaim
// per 20 seconds the live game had junk RISE from 43 to 67 while 27 reclaims
// fired.
int ObsoletePeriod()
{
	const float e = aiEconomyMgr.energy.income;
	int p = int(float(OBSOLETE_PERIOD) / (1.f + e / OBSOLETE_ENERGY_SCALE));
	if (p < OBSOLETE_MIN_PERIOD)
		p = OBSOLETE_MIN_PERIOD;
	return p;
}

// The grid is past the tier that T1 buildings were worth their ground for.
// One fusion's worth of income; an advanced fusion is three of these.
const float LAND_PRECIOUS_ENERGY = 1000.f;

bool LandIsPrecious()
{
	return aiEconomyMgr.energy.income >= LAND_PRECIOUS_ENERGY;
}

// Targets we have already asked for. CBuilderManager::Enqueue returns the
// EXISTING task when a reclaim is already marked on a target, and the victim
// pick below is deterministic -- so without this the same still-standing
// building is re-picked every period and the rate limit is spent on a task that
// already exists.
array<int> gReclaimAsked;

bool AskedFor(int id)
{
	for (uint i = 0; i < gReclaimAsked.length(); ++i) {
		if (gReclaimAsked[i] == id)
			return true;
	}
	return false;
}

// Cheap mobile build power, unlocked at the moment it can no longer cost us the
// advanced constructor.
//
// armfark (Butler, 210m, 140 build power) and corfast (Twitcher, 210m) are
// parked as role "support" in behaviour.json rather than "builder".
// CFactoryManager::GetFacRoleDef filters the recruit draw on GetMainRole, so at
// builder weight they win a share of it against armack -- delaying the team's
// single shared advanced constructor, which is what gates T2 mex upgrades.
//
// That objection is entirely about the RACE for the first one. Once we hold an
// advanced constructor there is nothing left to delay, and 210 metal for 140
// build power is the cheapest build power there is. Legion needs no equivalent:
// legaceb is already role builder in behaviour_leg.json.
//
// apexearth: "don't forget about those t2 assist bots with build power. those
// little guys are like mobile nano turrets and might be useful for AI even
// moreso than humans."
string armfark("armfark"); string corfast("corfast"); string legaceb("legaceb");
bool gAssistPromoted = false;

// Assist bots and advanced constructors get their limit from the economy every
// tick, not from a number in behaviour.json.
//
// apexearth: "same with adv cons, make tons of them... we shouldn't have any hard
// caps, everything needs to be balanced based on the economy/game progression",
// and "in a game like that we'd need like a ton of nano turrets, 100s of butlers,
// all working to make the expensive stuff."
const float ASSIST_PER_INCOME = 3.f;
const float ASSIST_CAP_SHARE  = 0.20f;

void SetDefCap(CCircuitDef@ d, int want)
{
	if ((d is null) || (want < 1))
		return;
	if (d.GetMaxThisUnit() != want)
		d.SetMaxThisUnit(want);
}

CCircuitDef@ AssistBotDef()
{
	return SideDef3(armfark, corfast, legaceb);
}

void UpdateEconomicCaps()
{
	int want = 2 + int(aiEconomyMgr.metal.income / ASSIST_PER_INCOME);
	if (aiEconomyMgr.isMetalFull)
		want *= 2;
	const int ceiling = CapShare(ASSIST_CAP_SHARE);
	if (want > ceiling)
		want = ceiling;
	SetDefCap(AssistBotDef(), want);
	SetDefCap(NanoDef(), NanoCap());
}

void PromoteAssistBots()
{
	if (gAssistPromoted || !gHaveAdvCon)
		return;
	const string side = ai.GetSideName();
	if (side == "legion") {
		gAssistPromoted = true;
		return;
	}
	CCircuitDef@ bot = (side == "cortex") ? ai.GetCircuitDef(corfast)
	                                      : ai.GetCircuitDef(armfark);
	if (bot is null)
		return;
	gAssistPromoted = true;
	bot.SetMainRole(RT::BUILDER);
	AiLog(Factory::T() + "apex: assist bot " + bot.GetName()
		+ " promoted to builder (advanced constructor held)");
}

// Past the tier T1 defences and T1 economy were built for. gHaveT3 is a gantry
// standing; the T2 half additionally wants a real economy, so a player that has
// merely touched T2 does not strip its own defences while still fighting T1
// armies. One definition, read by both the reclaim below and ContestTower --
// they were separate judgements about the same moment, and only one of them
// existed.
// Do we hold anything heavier than a T1 turret? Defs from mexguard.as, which the
// shim includes first.
bool HaveHeavyDefence()
{
	array<CCircuitDef@> heavy = {
		SideDef3(armtoast, cortoastd, legramp),
		SideDef3(armpulsar, corpulsar, legpulsar),
		SideDef3(armpb, corvipe, legapopupdef)
	};
	for (uint i = 0; i < heavy.length(); ++i) {
		if ((heavy[i] !is null) && (heavy[i].count > 0))
			return true;
	}
	return false;
}

bool PastT1Tier()
{
	return Factory::gHaveT3
		|| (Factory::gHaveT2 && (aiEconomyMgr.metal.income >= OBSOLETE_T2_INCOME));
}

// How much T1 junk has to be standing before clearing it outranks the ordinary
// build queue. Below this the end-of-queue path is fine; above it the base is
// visibly cluttered and the clutter is what is stopping us teching up.
const int OBSOLETE_URGENT_COUNT = 6;

// The T1 and T1.5 towers this AI builds -- tiers 0 and 1 of the same ladder
// MexGuardTower/FrontTower/CoverDef climb.
//
// The T2 pop-ups are deliberately NOT here: they are one of the three defs
// HaveHeavyDefence() reads, so listing them made that guard authorise eating the
// very tier it gates on. The mid tier is in no part of that set, so it can be
// listed without touching the gate.
array<string> ObsoleteDefenceNames()
{
	const string side = ai.GetSideName();
	array<string> names;
	if (side == "cortex") {
		names.insertLast(corllt);
		names.insertLast(corhllt);
	} else if (side == "legion") {
		names.insertLast(leglht);
		names.insertLast(legmg);
	} else {
		names.insertLast(armllt);
		names.insertLast(armbeamer);
	}
	return names;
}

string ObsoleteSolarName()
{
	return SideName3(armsolar, corsolar, legsolar);
}

IUnitTask@ ReclaimOwnDef(CCircuitUnit@ unit, const string& in defName,
		const AIFloat3& in near, float radius, const string& in why,
		bool isDefence = false)
{
	CCircuitDef@ def = ai.GetCircuitDef(defName);
	if ((def is null) || (def.count <= 0))
		return null;
	array<CCircuitUnit@>@ owned = ai.GetOwnUnitsOfDef(def, near, radius);
	if ((owned is null) || (owned.length() == 0))
		return null;

	// WHICH of our copies to eat is a space question, not an arbitrary one.
	// apexearth: "reclaim what's stranded outside the footprint or sitting in a
	// lane". A structure standing in a walkway is what makes the base
	// uncrossable; one stranded outside the footprint is what makes it sprawl.
	// Both were previously indistinguishable from a tidy row -- the loop took
	// whichever copy the engine happened to list first.
	//
	// A TURRET IS SCORED THE OTHER WAY ROUND. The eco entries are ranked by where
	// they waste ground, and "stranded outside the footprint" is a description of
	// every tower on the line -- the ones still doing the job they were built for.
	// apexearth: "we reclaim our t1.5 defenses far before we even build our T2+
	// defenses, and we have a horrible lack of T2+ defenses." So a defence entry
	// is eligible only where it is base clutter: inside the footprint, or standing
	// in a walkway. Same boundary Base publishes for placement, so a tower the
	// grid would refuse to place there is a tower the grid will take back.
	CCircuitUnit@ pick = null;
	int bestScore = -1;
	string bestWhy = why;
	const bool sited = Base::Ready();
	for (uint i = 0; i < owned.length(); ++i) {
		CCircuitUnit@ victim = owned[i];
		if ((victim is null) || (victim is unit) || AskedFor(victim.id))
			continue;
		const AIFloat3 at = victim.GetPos(ai.frame);
		const bool inLane = Base::InLaneAt(at);
		const bool inside = sited && Base::Inside(at);
		if (isDefence && sited && !inLane && !inside)
			continue;
		int score = 0;
		string tag = why;
		if (inLane) {
			score = 2;
			tag = "in a lane";
		} else if (isDefence && inside) {
			score = 1;
			tag = "clutter inside the base";
		} else if (!isDefence && sited && !inside) {
			score = 1;
			tag = "stranded outside the base";
		}
		if (score > bestScore) {
			bestScore = score;
			@pick = victim;
			bestWhy = tag;
		}
	}
	if (pick is null)
		return null;

	IUnitTask@ eat = aiBuilderMgr.Enqueue(TaskB::Reclaim(Task::Priority::NORMAL, pick));
	if (eat is null)
		return null;
	gReclaimAsked.insertLast(pick.id);
	if (gReclaimAsked.length() > 64)
		gReclaimAsked.removeAt(0);
	gNextObsolete = ai.frame + ObsoletePeriod();
	AiLog(Factory::T() + "apex: obsolete-reclaim " + defName + " #" + pick.id
		+ " (" + bestWhy + ")");
	return eat;
}

// How many T1 structures we are still standing on. Counted from the same name
// lists the reclaim uses, so the trigger and the target cannot drift apart.
int ObsoleteJunkCount()
{
	int n = 0;
	array<string> junk = ObsoleteEcoNames();
	for (uint i = 0; i < junk.length(); ++i) {
		CCircuitDef@ d = ai.GetCircuitDef(junk[i]);
		if (d !is null)
			n += d.count;
	}
	array<string> towers = ObsoleteDefenceNames();
	for (uint i = 0; i < towers.length(); ++i) {
		CCircuitDef@ d = ai.GetCircuitDef(towers[i]);
		if (d !is null)
			n += d.count;
	}
	return n;
}

int gNextJunkLog = 0;

// The promoted path: same act, but ahead of the economy offers instead of behind
// everything. Gated hard so it cannot become a constructor sink.
IUnitTask@ ObsoleteUrgent(CCircuitUnit@ unit)
{
	if (!PastT1Tier())
		return null;
	const int junk = ObsoleteJunkCount();
	if (ai.frame >= gNextJunkLog) {
		gNextJunkLog = ai.frame + 60 * SECOND;
		AiLog(Factory::T() + "apex: obsolete junk standing=" + junk
			+ " income=" + formatFloat(aiEconomyMgr.metal.income, "", 0, 0)
			+ " t2=" + (Factory::gHaveT2 ? "1" : "0")
			+ " t3=" + (Factory::gHaveT3 ? "1" : "0"));
	}
	if (junk < OBSOLETE_URGENT_COUNT)
		return null;
	return ObsoleteReclaim(unit);
}

IUnitTask@ ObsoleteReclaim(CCircuitUnit@ unit, bool allowAdv = false)
{
	// NOT THE ADVANCED CONSTRUCTORS. apexearth: "I see T2 con time is being used
	// to reclaim obsolete buildings. Let's not have that be important for them at
	// all. Rezbots, T1 cons, and con turrets can do that." An advanced con is the
	// only unit that can build a moho, a reactor or a heavy turret, and there are
	// never many; tidying is work anything else can do.
	//
	// allowAdv is the one exception, and only the caller can establish it: the
	// last-resort path runs after the engine's own offer came back null and after
	// every rule above declined, so there is no moho for this constructor to be
	// taken off. It is passed the bank state as well -- apexearth, watching an
	// 8v8: "These guys have tons of metal so they could spend some time reclaiming
	// old stuff." The promoted path above the economy offers never passes it.
	if (IsAdvConDef(unit) && !allowAdv)
		return null;
	if (ai.frame < gNextObsolete)
		return null;

	// Case 1: something large could not be placed. Clear the cheapest clutter
	// first -- a solar is 155 metal and rebuildable anywhere, a T1 tower is
	// dead weight by the time we are placing gantries.
	AIFloat3 blocked;
	if (ai.GetBlockedBuildPos(blocked)) {
		array<string> clutter;
		clutter.insertLast(ObsoleteSolarName());
		array<string> towers = ObsoleteDefenceNames();
		for (uint i = 0; i < towers.length(); ++i)
			clutter.insertLast(towers[i]);
		for (uint i = 0; i < clutter.length(); ++i) {
			IUnitTask@ eat = ReclaimOwnDef(unit, clutter[i], blocked, OBSOLETE_NEAR, "blocked build");
			if (eat !is null)
				return eat;
		}
	}

	// Case 2: we are clearly past the tier these towers defend against.
	if (!PastT1Tier())
		return null;

	// ONE list, entered at a ROTATING offset.
	//
	// Two fixed lists each returning on their first hit meant whichever ran first
	// took nearly everything: measured in a live 37-minute game, 272 armwin and
	// 63 armmakr against 3 armllt. Wind is rebuilt continuously by the stock
	// economy manager, so index 0 always had a candidate and the tower list was
	// unreachable -- which is precisely the thing apexearth keeps seeing standing.
	// Rotating the entry point costs nothing and gives every def its turn.
	array<string> all = ObsoleteEcoNames();
	// A TOWER IS ONLY OBSOLETE ONCE ITS REPLACEMENT EXISTS. apexearth: "we
	// reclaim our t1.5 defenses far before we even build our T2+ defenses, and we
	// have a horrible lack of T2+ defenses." PastT1Tier is a TECH test -- T2 plant
	// plus income -- and says nothing about whether a heavier turret was ever
	// built. HeavyDefenceFor needs an advanced constructor to be the one asking,
	// and conT2 is often zero, so the old tower came down and nothing replaced it.
	// Economy junk still goes at the tech gate; only defence waits for its heir.
	array<string> towers;
	if (HaveHeavyDefence()) {
		towers = ObsoleteDefenceNames();
		for (uint i = 0; i < towers.length(); ++i)
			all.insertLast(towers[i]);
	}
	if (all.length() == 0)
		return null;

	const uint n = all.length();
	for (uint k = 0; k < n; ++k) {
		const uint i = (gObsoleteTurn + k) % n;
		const bool isTower = (i >= n - towers.length());
		IUnitTask@ eat = ReclaimOwnDef(unit, all[i], gHomePos, 0.f,
				isTower ? "past its tier" : "obsolete tier-1 eco", isTower);
		if (eat !is null) {
			gObsoleteTurn = (i + 1) % n;
			return eat;
		}
	}
	return null;
}

// T1 economy and AA that a T2/T3 base has outgrown. Per-faction, because a
// name list that only covers Cortex is the recurring faction-parity trap.
//
// The T1 converter and the T1 AA turret belong here -- apexearth: "those become
// trash long into a game". What had to change is the two rules that were
// REBUILDING them behind us: CheapAA and the generic EnergyConverter both now
// stand down past T1 tier, so reclaiming one no longer queues its replacement.
// REPLACE, DO NOT JUST REMOVE. apexearth, watching: "I saw us reclaiming t1
// converters before t2 converters were even made. Should replace t1s with t2s
// otherwise we just lower our metal income."
//
// PastT1Tier() asks whether we have TECHED, never whether the replacement was
// actually built -- so a base at T2 with the income for it tore out its cheap
// converters and its solars while nothing had taken over the job. Both of those
// are income: a converter IS metal income, and a solar is what runs it.
//
// So each of those two entries now waits for its own successor to be standing.
// Wind and the T1 AA turret are unconditional: wind is superseded by any
// generator at all, and the AA turret is not economy.
bool HaveReplacementFor(const string& in name)
{
	CCircuitDef@ better = null;
	if ((name == armmakr) || (name == cormakr) || (name == legeconv))
		@better = SideDef3(armmmkr, cormmkr, legadveconv);
	else if ((name == armsolar) || (name == corsolar) || (name == legsolar))
		@better = SideDef3(armadvsol, coradvsol, legadvsol);
	// A reactor is the advanced collector's successor: once one stands the panels
	// are footprint and metal the base wants back.
	else if ((name == armadvsol) || (name == coradvsol) || (name == legadvsol))
		@better = SideDef3(armfus, corfus, legfus);
	else
		return true;   // no successor to wait for
	return (better !is null) && (better.count > 0);
}

array<string> ObsoleteEcoNames()
{
	array<string> names;
	const string side = ai.GetSideName();
	if (side == "cortex") {
		names.insertLast(corwin);
		if (HaveReplacementFor(corsolar))
			names.insertLast(corsolar);
		if (HaveReplacementFor(cormakr))
			names.insertLast(cormakr);
		if (HaveReplacementFor(coradvsol))
			names.insertLast(coradvsol);
		names.insertLast(corrl);
	} else if (side == "legion") {
		names.insertLast(legwin);
		if (HaveReplacementFor(legsolar))
			names.insertLast(legsolar);
		if (HaveReplacementFor(legeconv))
			names.insertLast(legeconv);
		if (HaveReplacementFor(legadvsol))
			names.insertLast(legadvsol);
		names.insertLast(legrl);
	} else {
		names.insertLast(armwin);
		if (HaveReplacementFor(armsolar))
			names.insertLast(armsolar);
		if (HaveReplacementFor(armmakr))
			names.insertLast(armmakr);
		if (HaveReplacementFor(armadvsol))
			names.insertLast(armadvsol);
		names.insertLast(armrl);
	}
	return names;
}

bool StandoffPos(CCircuitUnit@ unit, const AIFloat3& in hot, AIFloat3& out spot)
{
	if (!gHomeSet)
		return false;
	AIFloat3 dir = gHomePos - hot;
	if (dir.SqLength2D() < NEAR_ZERO)
		return false;
	dir.SafeNormalize2D();
	for (int i = 1; i <= DEF_STEPS; ++i) {
		const AIFloat3 back = hot + dir * (DEF_STEP * float(i));
		if (!OnMap(back))
			continue;
		if (ThreatFor(unit, back) <= CON_THREAT_VETO) {
			spot = back;
			return true;
		}
	}
	return false;
}

IUnitTask@ ContestDefence(CCircuitUnit@ unit, const string& in kind,
		float heat, const AIFloat3& in hot)
{
	// A tower is 680-15,000 energy, and handing a task over directly bypasses
	// CanAssignTo, which is where the engine's own energy test lives.
	if ((ai.frame < gNextConDef) || aiEconomyMgr.isEnergyStalling)
		return null;
	CCircuitDef@ tower = ContestTower(unit);
	if ((tower is null) || !tower.IsAvailable(ai.frame))
		return null;
	AIFloat3 spot;
	if (!StandoffPos(unit, hot, spot))
		return null;
	if (gConDefPlaced && (gConDefPos.distance2D(spot) < DEF_SPACING))
		return null;
	if (!AreaNeedsDefence(spot))
		return null;
	IUnitTask@ post = aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::DEFENCE,
			Task::Priority::NORMAL, tower, spot, DEF_SHAKE));
	if (post is null)
		return null;
	NoteDigOrder(spot);
	gNextConDef = ai.frame + DEF_PERIOD;
	gConDefPos = spot;
	gConDefPlaced = true;
	++gConDefended;
	if (ai.frame >= gNextDefenceLog) {
		gNextDefenceLog = ai.frame + 5 * SECOND;
		AiLog(Factory::T() + "apex: con-defend " + unit.circuitDef.GetName()
			+ " " + kind + " threat=" + formatFloat(heat, "", 0, 0)
			+ " -> " + tower.GetName()
			+ " back=" + formatFloat(hot.distance2D(spot), "", 0, 0)
			+ " defended=" + gConDefended);
	}
	return post;
}

}  // namespace Builder
