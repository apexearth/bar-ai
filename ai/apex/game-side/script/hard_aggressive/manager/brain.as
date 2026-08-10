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
// costs -- with no side effects. Decide() ranks the list and only then acts. See
// docs/18-task-arbiter.md for the staging; this is stage one, so the ranking is
// logged and only the mex-upgrade want is executed.
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

class Want
{
	string kind;          // "mexup", "gantry", "silo" ... for the log
	float value = 0.f;    // metal/second this is expected to add
	float cost = 1.f;     // metal it takes to get there
	AIFloat3 pos;
	CCircuitDef@ def;
	bool needsAdvCon = false;

	float Score() const
	{
		return (cost > 1.f) ? (value / cost) : value;
	}
}

array<Want@> gWants;
int gNextBrainLog = 0;
int gMexUpOrders = 0;

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

// Rank, log, and act on what we can act on.
IUnitTask@ Decide(CCircuitUnit@ unit, bool isAdvCon)
{
	Clear();
	if (isAdvCon)
		Propose(MexUpgradeWant(unit));

	if (gWants.length() == 0)
		return null;

	Want@ top = gWants[0];
	for (uint i = 1; i < gWants.length(); ++i) {
		if (gWants[i].Score() > top.Score())
			@top = gWants[i];
	}

	if (ai.frame >= gNextBrainLog) {
		gNextBrainLog = ai.frame + 30 * SECOND;
		string line = "apex: brain wants=" + gWants.length() + " top=" + top.kind
			+ " score=" + formatFloat(top.Score(), "", 0, 4);
		for (uint i = 0; i < gWants.length(); ++i) {
			line += " | " + gWants[i].kind + "=" + formatFloat(gWants[i].Score(), "", 0, 4);
		}
		AiLog(Factory::T() + line);
	}

	if (top.kind == "mexup") {
		// The binding added 2026-08-10. A MEXUP task carries a metal-spot index
		// as well as a position, so the generic Enqueue could not express it --
		// which is why no rule of ours could order an upgrade at all.
		IUnitTask@ t = aiBuilderMgr.EnqueueMexUp(top.pos, top.def);
		if (t !is null) {
			++gMexUpOrders;
			if (gMexUpOrders <= 3 || (gMexUpOrders % 10 == 0)) {
				AiLog(Factory::T() + "apex: brain orders mexup #" + gMexUpOrders
					+ " by " + unit.circuitDef.GetName());
			}
			return t;
		}
	}
	return null;
}

}  // namespace Brain
