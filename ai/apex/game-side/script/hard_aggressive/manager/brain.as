namespace Brain {

//------------------------------------------------------------------------------
// THE MACRO VIEW. Rules propose; this decides.
//
// apexearth: "what if we created a stack/list of all the things we wanted to do
// and then properly prioritized them after in some process which has a better
// macro view?" and "I want it to generally be a macro-view brain/logic center."
//
// The ladder in builder/maketask.as makes POSITION the only priority: the first
// rule that returns a task wins, so importance is expressed by where a rule sits
// rather than by what it is worth. Measured 2026-08-10: CommanderMexGuard sat
// one line above DefaultMakeTask and took 162 constructor-picks against 4 mex
// upgrades in a single game.
//
// Here a rule states a WANT -- what it would do, what that is worth, what it
// costs -- with no side effects. Decide() ranks the list and only then acts, and
// the whole ranking is logged so a pick can be argued with. docs/18-brain.md
// describes what is built here and what is still only designed.
//
// Only the mex-upgrade want is enqueued by this file. Every other kind names an
// existing rule in Execute(), which keeps its own preconditions -- the ranking
// decides ORDER, not eligibility. A new want therefore needs a Propose() call
// AND a line in Execute(), or it ranks and can never fire.
//
// VALUE IS METAL PER SECOND GAINED, PER METAL SPENT. That is the one unit every
// economic want can be expressed in, and it is why an upgrade can be compared to
// a reactor at all. Defence and offence need their own terms (threat denied,
// enemy metal removed) and are deliberately not here yet.
//------------------------------------------------------------------------------

// How far a constructor will look for one of our extractors to upgrade.
const float MEXUP_REACH = 2400.f;
// What a moho adds over a plain mex, in metal/second, at standard extraction.
// Read from the defs rather than assumed: armmex 1.8/s, armmoho 5.4/s here.
const float MEXUP_INCOME_GAIN = 3.6f;
// A converter turns energy into metal at roughly this rate, which is how an
// energy build is put on the same scale as a metal one.
const float ENERGY_TO_METAL = 0.014f;
// What the one-off investments are worth, in metal/second equivalent. These are
// ESTIMATES and the log prints the score they produce, so they are meant to be
// argued with from a game rather than defended from a desk.
const float GANTRY_VALUE   = 2.0f;   // opens T3 production
const float SILO_VALUE     = 4.0f;   // enemy metal removed, amortised
const float PULSAR_VALUE   = 1.5f;   // area denial near the base
const float PINPOINT_VALUE = 0.5f;   // targeting support, cheap and bounded
// The standing eco rules, as values rather than as "always".
//
// A converter eats 70 energy/s and returns 1 metal/s for ~1 metal to build
// (energyconv_capacity 70, efficiency 1/70, read from armmakr.lua), so while
// energy is spilling it is the best metal-per-metal in the game by a wide
// margin -- and that is exactly the state measured at 41.5% metal waste with
// idle factories. Energy itself is scored on what it unlocks, and is URGENT
// rather than merely valuable when the grid is stalling: UpdateEconomyTasks
// returns early on IsEnergyStalling, so a stall stops every other economy task
// including mex upgrades.
const float CONVERT_VALUE     = 1.0f;    // metal/s per converter, while spilling
const float ENERGY_VALUE      = 1.2f;    // metal/s equivalent of a generator step
const float ENERGY_STALL_MULT = 6.0f;    // a stall blocks the whole economy
// BOTH BANKS FULL MEANS INCOME IS NOT THE PROBLEM. apexearth: "if we are full on
// energy AND metal, then we can probably decrease all of our eco priority by
// some multiplier." More income buys nothing when neither resource can be
// stored or spent -- the constraint has moved to build power and to what we do
// with the surplus, so everything economic drops behind the things that spend.
const float ECO_SATED_MULT    = 0.25f;
// BUILD POWER IS WHAT A FULL BANK ACTUALLY NEEDS. apexearth: "in matches where
// we are +100 handicap it's easy to max out the economy and have a hard time
// using all the resources." A nano turret converts banked metal back into units
// at ~7 metal/s of build power for ~300 metal, which beats every income want
// once income is no longer the constraint. Scored high only while sated, so it
// cannot crowd out expansion in a normal game.
const float NANO_VALUE        = 7.0f;
// A front turret repairs instead of producing, so its value is what it keeps
// alive rather than what it builds. Lower than a base nano's build power, and
// it only proposes once there is a front to stand behind.
const float FRONT_NANO_VALUE  = 3.0f;

bool EcoSated()
{
	return aiEconomyMgr.isMetalFull && aiEconomyMgr.isEnergyFull;
}

// The kinds whose whole purpose is more income.
bool IsEcoKind(const string& in kind)
{
	return (kind == "mexup") || (kind == "energy") || (kind == "convert");
}

class Want
{
	string kind;          // "mexup", "gantry", "silo" ... for the log
	float value = 0.f;    // metal/second this is expected to add
	float cost = 1.f;     // metal it takes to get there
	AIFloat3 pos;
	CCircuitDef@ def;
	bool needsAdvCon = false;

	int have = 0;         // how many of this we already hold

	// VALUE PER METAL, WITH DIMINISHING RETURNS.
	//
	// Ranking on value/cost alone hands the game to whatever is cheapest: a
	// Pinpointer at 0.5 metal/s and ~800 metal scores higher than a silo at 4.0
	// and 8,100, so the first ranked run picked pinpoint whenever no upgrade was
	// in reach. Halving the value per copy already standing is what stops one
	// cheap thing winning forever, and it is the real shape -- the second
	// Pinpointer is worth much less than the first.
	float Score() const
	{
		float scaled = value / (1.f + float(have));
		if (IsEcoKind(kind) && EcoSated())
			scaled *= ECO_SATED_MULT;
		return (cost > 1.f) ? (scaled / cost) : scaled;
	}
}

array<Want@> gWants;
int gNextBrainLog = 0;
int gMexUpOrders = 0;
int gNextPickLog = 0;

void Clear()
{
	gWants.resize(0);
}

void Propose(Want@ w)
{
	if (w !is null)
		gWants.insertLast(w);
}

// The one want that is executed today. Everything else is proposed and logged so
// the ranking can be read before behaviour is handed to it.
Want@ MexUpgradeWant(CCircuitUnit@ unit)
{
	CCircuitDef@ moho = SideDef3("armmoho", "cormoho", "legmoho");
	if ((moho is null) || !moho.IsAvailable(ai.frame))
		return null;
	CCircuitDef@ mex = SideDef3("armmex", "cormex", "legmex");
	if ((mex is null) || (mex.count <= 0))
		return null;

	// Nearest extractor of ours that the moho out-yields. GetOwnUnitsOfDef is
	// the authoritative "ours" answer -- a register of our own drifted to 4
	// entries on a side holding 150.
	const AIFloat3 here = unit.GetPos(ai.frame);
	array<CCircuitUnit@>@ mine = ai.GetOwnUnitsOfDef(mex, here, MEXUP_REACH);
	if ((mine is null) || (mine.length() == 0))
		return null;

	CCircuitUnit@ best = null;
	float bestDist = MEXUP_REACH;
	for (uint i = 0; i < mine.length(); ++i) {
		if (mine[i] is null)
			continue;
		const AIFloat3 at = mine[i].GetPos(ai.frame);
		if (!OnMap(at))
			continue;
		const float d = here.distance2D(at);
		if (d < bestDist) {
			bestDist = d;
			@best = mine[i];
		}
	}
	if (best is null)
		return null;

	Want@ w = Want();
	w.kind = "mexup";
	// A moho roughly triples a mex's extraction. Expressed as metal/second so it
	// is comparable with a reactor's, rather than as a unitless preference.
	w.value = MEXUP_INCOME_GAIN;
	w.cost = moho.costM;
	w.pos = best.GetPos(ai.frame);
	@w.def = moho;
	w.needsAdvCon = true;
	return w;
}

// A want the Brain does not execute itself: it names the rule that does, and
// Decide() calls that rule only if this want wins. The rule keeps its own
// preconditions -- this decides ORDER, not eligibility.
Want@ Simple(string kind, float value, CCircuitDef@ def)
{
	if ((def is null) || !def.IsAvailable(ai.frame))
		return null;
	Want@ w = Want();
	w.kind = kind;
	w.value = value;
	w.cost = def.costM;
	w.have = def.count;
	@w.def = def;
	w.needsAdvCon = true;
	return w;
}

// Run the rule behind a want. Returns null when its own preconditions refuse,
// in which case Decide falls through to the next-ranked want.
IUnitTask@ Execute(const string& in kind, CCircuitUnit@ unit)
{
	if (kind == "gantry")
		return Builder::SurplusGantry(unit);
	if (kind == "silo")
		return Builder::NukeSilo(unit);
	if (kind == "pulsar")
		return Builder::Pulsar(unit);
	if (kind == "pinpoint")
		return Builder::Pinpointer(unit);
	if (kind == "energy")
		return Builder::HomeEnergy(unit);
	if (kind == "convert")
		return Builder::EnergyConverter(unit);
	if (kind == "nano")
		return Builder::EcoNano(unit);
	if (kind == "frontnano")
		return Builder::FrontNano(unit);
	return null;
}

// Rank, log, and act on the best want whose rule accepts.
IUnitTask@ Decide(CCircuitUnit@ unit, bool isAdvCon)
{
	Clear();
	if (!isAdvCon)
		return null;

	// NOTHING OPTIONAL BEFORE T2 EXISTS.
	//
	// apexearth, watching a 4v4 at +25: "something's going wrong this game where
	// our guys are not going to t2." The lead logged "building advanced plant
	// coravp" fifty times with haveT2 still 0 -- the plant was requested over and
	// over while constructors went to converters, nanos and reactors, all of
	// which this session had just ungated for every player. Each was individually
	// reasonable and together they starved the one building that unlocks the
	// rest.
	//
	// Before an advanced factory stands, the only thing worth a constructor is
	// expansion. This is the 2026-08-01 displacement finding arriving through the
	// Brain rather than through the ladder.
	const bool preT2 = !Factory::gHaveT2;

	Propose(MexUpgradeWant(unit));
	// The optional class. Costs are read from the defs so a score means
	// something; where a def is missing the want is simply not proposed.
	// ALWAYS MAKE ENERGY, AND CONVERT WHEN IT SPILLS -- as scores, so they can
	// be compared rather than merely obeyed. apexearth: "we had built custom eco
	// logic... always make energy, and if max energy make energy converters."
	if (aiEconomyMgr.isEnergyStalling) {
		Want@ e = Simple("energy", ENERGY_VALUE * ENERGY_STALL_MULT,
				SideDef3("armsolar", "corsolar", "legsolar"));
		if (e !is null) {
			e.have = 0;   // a stall is not "we have enough of these"
			Propose(e);
		}
	}
	if (!preT2 && Builder::EnergyWasting())
		Propose(Simple("convert", CONVERT_VALUE, SideDef3("armmakr", "cormakr", "legeconv")));

	// Spend the surplus rather than growing it further.
	if (!preT2 && (EcoSated() || aiEconomyMgr.isMetalFull))
		Propose(Simple("nano", NANO_VALUE, SideDef3("armnanotc", "cornanotc", "legnanotc")));
	// ON by default. Attribution showed the income gate, not these, caused the
	// army drop -- and K/D was the one number that went UP with them (1.49 ->
	// 1.54). apexearth: "notice how our KD went up with the nanodefense. Maybe
	// we're just building them a little bit too early, or making too many at
	// once. Probably a good thing to have on, just be reasonable about it."
	// So: kept, later and fewer (see FRONT_NANO_* in builder/nano.as).
	if (!preT2 && (ai.GetTunable("apex_front_nano", 1.f) > 0.f))
		Propose(Simple("frontnano", FRONT_NANO_VALUE, SideDef3("armnanotc", "cornanotc", "legnanotc")));

	if (!preT2) {
	Propose(Simple("gantry", GANTRY_VALUE, SideDef3("armshltx", "corgant", "leggant")));
	Propose(Simple("silo", SILO_VALUE, SideDef3("armsilo", "corsilo", "legsilo")));
	Propose(Simple("pulsar", PULSAR_VALUE, SideDef3("armanni", "cordoom", "legstarfall")));
	Propose(Simple("pinpoint", PINPOINT_VALUE, SideDef3("armtarg", "cortarg", "legtarg")));
	}

	if (gWants.length() == 0)
		return null;

	// Descending by score, first rule that accepts wins.
	array<Want@> order = gWants;
	for (uint i = 0; i < order.length(); ++i) {
		for (uint j = i + 1; j < order.length(); ++j) {
			if (order[j].Score() > order[i].Score()) {
				Want@ tmp = order[i];
				@order[i] = order[j];
				@order[j] = tmp;
			}
		}
	}

	if (ai.frame >= gNextBrainLog) {
		gNextBrainLog = ai.frame + 30 * SECOND;
		string line = "apex: brain wants=" + order.length();
		for (uint i = 0; i < order.length(); ++i)
			line += " | " + order[i].kind + "=" + formatFloat(order[i].Score(), "", 0, 4);
		AiLog(Factory::T() + line);
	}

	// UPGRADES ARE NOT OPTIONAL SPENDING. If an upgrade is in reach, this
	// constructor's job is the upgrade -- and if the enqueue happens to fail
	// (spot taken, already upgrading), it goes back to the engine's own work
	// rather than starting a Pulsar instead.
	//
	// Measured: with the optional class executing whenever it outranked nothing,
	// picks rose from 13 to 20 per batch and T2 mex share fell 17.6% -> 15.1%.
	// Ranking decides order among optional things; it does not get to displace
	// the economy that pays for them.
	bool haveMexUp = false;
	for (uint i = 0; i < order.length(); ++i) {
		if (order[i].kind == "mexup") {
			haveMexUp = true;
			break;
		}
	}
	// With both banks full the upgrade is no longer the thing standing between
	// us and spending, so it stops blocking everything else.
	if (EcoSated())
		haveMexUp = false;

	for (uint i = 0; i < order.length(); ++i) {
		Want@ w = order[i];
		if (w.kind != "mexup" && haveMexUp)
			continue;
		if (w.kind == "mexup") {
			// The binding added 2026-08-10. A MEXUP task carries a metal-spot
			// index as well as a position, so the generic Enqueue could not
			// express it -- which is why no rule of ours could order an upgrade.
			IUnitTask@ t = aiBuilderMgr.EnqueueMexUp(w.pos, w.def);
			if (t !is null) {
				++gMexUpOrders;
				if (gMexUpOrders <= 3 || (gMexUpOrders % 25 == 0)) {
					AiLog(Factory::T() + "apex: brain orders mexup #" + gMexUpOrders
						+ " by " + unit.circuitDef.GetName());
				}
				return t;
			}
			continue;
		}
		IUnitTask@ t = Execute(w.kind, unit);
		if (t !is null) {
			if (ai.frame >= gNextPickLog) {
				gNextPickLog = ai.frame + 60 * SECOND;
				AiLog(Factory::T() + "apex: brain picks " + w.kind
					+ " score=" + formatFloat(w.Score(), "", 0, 4));
			}
			return t;
		}
	}
	return null;
}

}  // namespace Brain
