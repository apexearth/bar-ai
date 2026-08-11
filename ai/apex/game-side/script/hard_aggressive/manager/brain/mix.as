namespace Brain {

//------------------------------------------------------------------------------
// WHAT MIX NOW, NOT WHAT NEXT.
//
// apexearth: "imagine we know that we want a certain mix of plain composition...
// then as long as that factory is on and building, it's just constantly pumping
// out the units, and there's never any time when it's not doing that work. It
// also saves the AI time on setting these tasks. It's just pre-setup the proper
// ratio." And: "we set up our queues and over time our composition shifts
// towards the target."
//
// The existing pipeline asks "what should this factory build NEXT" and lets the
// first rule that answers win, so the army mix is an OUTCOME of tier tables,
// response weights and role gates interacting -- nobody can point at where
// "35% raiders" is decided. Here the target is stated, and each decision is
// simply "which role is furthest below it".
//
// Measured motivation, 60 games across five team sizes vs BARb medium: we
// out-produce 1.10-1.76x and field 0.57-0.90x their army in every bracket.
// Production is the weak axis, and it is the one thing the Brain did not touch.
//
// Convergence, not enforcement: one unit is chosen per call, so the composition
// walks toward the target rather than being reset to it. A factory that cannot
// build the wanted role falls through to the rules below, which keeps every
// existing behaviour reachable.
//------------------------------------------------------------------------------

// Target shares of ARMY METAL by role. They sum to 1; what matters is the
// ratios between them, since the choice is always "furthest below target".
//
// Raider-heavy on purpose: USER-FEEDBACK.md records that apex had zeroed the
// raider out of the T1 bot lab and that "we never harass their economy while
// they constantly harass ours" -- stock's bot lab is a raiding factory and ours
// had become an assault factory.
// A role, what we want of it in a vacuum, and which enemy roles make it worth
// more than that. The counter list is what turns a fixed table into a reading of
// the game -- see CounterShares().
class MixTarget
{
	Type role;
	// The curve from targets.as, read against income every time the mix decides.
	// apexearth: "Raiders at .3 to start is OK but later on I want it lower."
	array<float>@ curve;
	array<Type> counters;
	MixTarget(Type r, array<float>@ c) { role = r; @curve = c; }
	float Share() const { return Targets::At(curve); }
	void Counter(Type enemyRole) { counters.insertLast(enemyRole); }
}

array<MixTarget@> gMix;
int gNextMixLog = 0;
int gMixPicks = 0;
int gScoutPicks = 0;

// How far a perfectly-scouted enemy may pull the composition away from the base
// table. Not 1.0: the roles we hold for reasons the enemy does not dictate --
// something to raid with, something to hold ground -- must survive a reading of
// their army, or one sighting empties the rest of the composition.
const float MIX_COUNTER_MAX = Targets::COUNTER_MAX;

// WHICH FACTORIES THE BRAIN OWNS.
//
// apexearth: "make sure the old system doesn't interact with that factory and
// add its own things." Two systems taking turns on one production line is worse
// than either alone -- the mix would aim for a composition while the old floors
// inserted rez bots, radar planes and fighters behind its back, and neither
// would be responsible for the result.
//
// Ownership is claimed the first time the mix successfully enqueues for a
// factory, and from then on that line is the Brain's: the apex production rules
// are skipped for it entirely. The engine's own DefaultMakeTask remains the
// safety net so an owned line never idles.
array<Id> gMixOwned;

bool OwnsFactory(CCircuitUnit@ fac)
{
	if (fac is null)
		return false;
	const Id id = fac.id;
	for (uint i = 0; i < gMixOwned.length(); ++i) {
		if (gMixOwned[i] == id)
			return true;
	}
	return false;
}

void ClaimFactory(CCircuitUnit@ fac)
{
	if ((fac is null) || OwnsFactory(fac))
		return;
	gMixOwned.insertLast(fac.id);
	AiLog(Factory::T() + "apex: mix claims " + fac.circuitDef.GetName()
		+ " #" + fac.id + " (old production rules off for this line)");
}

void ReleaseFactory(Id id)
{
	for (uint i = 0; i < gMixOwned.length(); ++i) {
		if (gMixOwned[i] == id) {
			gMixOwned.removeAt(i);
			return;
		}
	}
}

// The counter relations are CircuitAI's own, stated in behaviour.json where the
// roles are defined: "riot ... is built when enemy has many raiders", "assault
// ... when enemy has many statics", "skirmish ... when enemy has many riots or
// assaults". response.json expresses the same idea, and an owned line never
// reaches it -- which is how an enemy could field a role we had no answer to and
// nothing in the production path noticed.
void InitMix()
{
	if (gMix.length() > 0)
		return;
	MixTarget@ raid = MixTarget(RT::RAIDER, @Targets::ROLE_RAIDER);
	raid.Counter(RT::ARTY);        // artillery cannot defend itself up close
	raid.Counter(RT::SKIRM);
	gMix.insertLast(raid);

	MixTarget@ assault = MixTarget(RT::ASSAULT, @Targets::ROLE_ASSAULT);
	assault.Counter(RT::STATIC);   // what walks into defences
	assault.Counter(RT::RIOT);
	gMix.insertLast(assault);

	MixTarget@ skirm = MixTarget(RT::SKIRM, @Targets::ROLE_SKIRM);
	skirm.Counter(RT::RIOT);
	skirm.Counter(RT::ASSAULT);
	gMix.insertLast(skirm);

	// THE ANSWER TO BEING RAIDED. apexearth, watching a 4v4: "enemy super light
	// units would harass our early game mexes very effectively and we didn't have
	// any super lights of our own to catch them."
	MixTarget@ riot = MixTarget(RT::RIOT, @Targets::ROLE_RIOT);
	riot.Counter(RT::RAIDER);
	riot.Counter(RT::SCOUT);
	gMix.insertLast(riot);

	MixTarget@ arty = MixTarget(RT::ARTY, @Targets::ROLE_ARTY);
	arty.Counter(RT::STATIC);
	gMix.insertLast(arty);

	MixTarget@ aa = MixTarget(RT::AA, @Targets::ROLE_AA);
	aa.Counter(RT::AIR);
	aa.Counter(RT::BOMBER);
	gMix.insertLast(aa);

	// THE T2 ROLES THE TABLE COULD NOT NAME.
	//
	// apexearth, watching a T2 bot line: "could really use a few snipers in our
	// base or fatboys when we are t2 bots... we seem to only make hounds right
	// now and thats not working out." The mechanism is exact -- behaviour.json
	// gives armfboy the HEAVY role and armsnipe anti_heavy_ass, and NEITHER was in
	// this table, so an owned line could not build them at all. Hound (armfido) is
	// Armada's only assault-role T2 bot, so the whole ASSAULT share became Hounds.
	//
	// Both defs are T2, so IsAvailable keeps these out of the T1 phase without a
	// clock: before the advanced plant stands they are simply skipped.
	MixTarget@ heavy = MixTarget(RT::HEAVY, @Targets::ROLE_HEAVY);
	heavy.Counter(RT::STATIC);
	heavy.Counter(RT::ASSAULT);
	gMix.insertLast(heavy);

	MixTarget@ ah = MixTarget(RT::AH, @Targets::ROLE_AH);
	ah.Counter(RT::HEAVY);
	ah.Counter(RT::SUPER);
	gMix.insertLast(ah);

	MixTarget@ aha = MixTarget(RT::AHA, @Targets::ROLE_AHA);
	aha.Counter(RT::HEAVY);
	aha.Counter(RT::SUPER);
	gMix.insertLast(aha);

	// No normalising here any more: a share is read from its curve at the income
	// of the moment, so BaseShares() normalises what it reads.
}

// WHAT THE ENEMY IS ACTUALLY FIELDING, AS A TARGET COMPOSITION.
//
// Each role's demand is the enemy metal in the roles it counters; the demands
// normalise into a second set of shares, which Target() blends with the base
// table. GetEnemyCost only accumulates on EnemyEnterLOS, so a zero means "not
// seen" rather than "not there" -- that is why this is a BLEND WEIGHTED BY HOW
// MUCH WE HAVE SEEN and not a replacement. With nothing scouted the weight is
// zero and the base table is used unchanged, so ignorance keeps the balanced
// composition instead of reading as "the enemy has nothing".
array<float> CounterShares(CCircuitUnit@ fac, float &out weight)
{
	array<float> out_(gMix.length(), 0.f);
	weight = 0.f;
	float seen = 0.f;
	float total = 0.f;
	for (uint i = 0; i < gMix.length(); ++i) {
		float demand = 0.f;
		for (uint c = 0; c < gMix[i].counters.length(); ++c) {
			// AIR IS THE ONE ROLE WHOSE RAW COST LIES. apexearth, watching:
			// "wow our team has 38 anti air units...." Air constructors and air
			// scouts both carry the AIR role, so GetEnemyCost(AIR) reads a few
			// hundred metal of enemy ECONOMY as aircraft -- and because these
			// demands are normalised against each other, that was often the
			// largest number seen and pulled the AA share toward the cap.
			// Military::AirThreatSeen is the discounted, time-averaged value the
			// static-AA code already trusts, and it reads 0 below AA_IGNORE.
			if (gMix[i].counters[c] == RT::AIR)
				demand += Military::AirThreatSeen();
			else
				demand += aiEnemyMgr.GetEnemyCost(gMix[i].counters[c]);
		}
		out_[i] = demand;
		total += demand;
	}
	// Everything we have laid eyes on, counted once, as the scale against which
	// our own army says whether that sighting is worth steering by.
	seen = total;
	if (total <= 1.f)
		return out_;
	for (uint i = 0; i < out_.length(); ++i)
		out_[i] /= total;

	float ours = 0.f;
	for (uint i = 0; i < gMix.length(); ++i) {
		const float held = HeldOfRole(fac, gMix[i].role);
		if (held > 0.f)
			ours += held;
	}
	// Seen against held: a glimpse of one squad while we hold an army barely
	// moves the target; a well-scouted enemy army moves it most of the way.
	const float frac = seen / (seen + ((ours > 1.f) ? ours : 1.f));
	weight = MIX_COUNTER_MAX * frac * ai.GetTunable("apex_mix_counter", 1.f);
	if (weight > MIX_COUNTER_MAX)
		weight = MIX_COUNTER_MAX;
	return out_;
}

// The base table read through what we know of the enemy.
// The chaff fade lives in targets.as now, as the ROLE_RAIDER curve itself --
// "at 15 metal start to taper, 20 metal .66, 30 metal .25, 100 metal .05" is a
// shape, and a shape belongs in the table of shapes rather than as a multiplier
// bolted onto one. Scouts fade the same way through SCOUT_PER_MEX.
// The base table read through the economy, renormalised so the weight a fading
// role gives up is taken by the roles that still earn it rather than simply
// vanishing from the total.
array<float> BaseShares()
{
	array<float> b(gMix.length(), 0.f);
	float sum = 0.f;
	for (uint i = 0; i < gMix.length(); ++i) {
		// Straight from the curve. The old chaff multiplier is gone: ROLE_RAIDER
		// in targets.as fades on its own, and applying both taped one fade on top
		// of another.
		b[i] = gMix[i].Share();
		sum += b[i];
	}
	if (sum > 0.f) {
		for (uint i = 0; i < b.length(); ++i)
			b[i] /= sum;
	}
	return b;
}

float Target(uint i, const array<float>& in base, const array<float>& in counter,
		float weight)
{
	return base[i] * (1.f - weight) + counter[i] * weight;
}

// What we currently HOLD of a role, in metal. CCircuitDef::count is our own
// count, which is what NanoCap and the rez-bot floor already rely on.
float HeldOfRole(CCircuitUnit@ fac, Type role)
{
	CCircuitDef@ d = aiFactoryMgr.GetRoleDef(fac.circuitDef, role);
	if (d is null)
		return -1.f;             // this factory cannot make the role at all
	return float(d.count) * d.costM;
}

// The role furthest below its target share, among those this factory can build.
CCircuitDef@ NextForMix(CCircuitUnit@ fac)
{
	InitMix();
	float total = 0.f;
	array<float> held(gMix.length(), -1.f);
	for (uint i = 0; i < gMix.length(); ++i) {
		held[i] = HeldOfRole(fac, gMix[i].role);
		if (held[i] > 0.f)
			total += held[i];
	}
	if (total < 1.f)
		total = 1.f;             // opening: every share reads as zero, so the
		                         // first pick is simply the highest target

	float weight = 0.f;
	array<float> counter = CounterShares(fac, weight);
	array<float> base = BaseShares();

	// A RATIO BEING MET IS NOT A REASON TO STOP BUILDING.
	//
	// worstGap started at 0, so once no role was below its target this returned
	// null -- and an owned line does not fall through to our production rules, it
	// falls to the engine, which has its own reasons to decline. A factory then
	// stands idle on a full bank. apexearth, watching: "we often aren't even
	// using all of our resources yet the factory will remain idle."
	//
	// The target is a composition, not a quantity. Starting below every possible
	// gap means the line always has an answer: whichever role is furthest below
	// target, or when all are at or above it, the one that is least over. The
	// composition still converges -- building the least-over role is what keeps it
	// there -- and the line never goes quiet while it can build something.
	CCircuitDef@ best = null;
	float worstGap = -1000.f;
	for (uint i = 0; i < gMix.length(); ++i) {
		if (held[i] < 0.f)
			continue;            // not buildable here
		const float have = held[i] / total;
		const float gap = Target(i, base, counter, weight) - have;
		if (gap <= worstGap)
			continue;
		CCircuitDef@ d = aiFactoryMgr.GetRoleDef(fac.circuitDef, gMix[i].role);
		if ((d is null) || !d.IsAvailable(ai.frame))
			continue;
		worstGap = gap;
		@best = d;
	}
	return best;
}

// The factory-side entry point. Returns a recruit task, or null to let the
// existing pipeline answer.
// BUILD POWER IS NOT PART OF THE ARMY MIX.
//
// It was a share (0.15) alongside the combat roles, and it never won: combat
// shares start at zero and are constantly emptied by losses, so the largest gap
// is ALWAYS a combat role and the constructor is never chosen. Measured in a 1v1
// against hard: our advanced constructors stayed at 1 from minute 14 to the end
// while hard reached 15 by minute 16, and the old constructor rules had been
// switched off for the claimed line. That is how a mix that looks reasonable
// starves the thing that builds the economy.
//
// So it is a FLOOR, checked before the ratio: below what the income justifies,
// the next unit off this line is a constructor.
IUnitTask@ BuildPowerFirst(CCircuitUnit@ fac)
{
	CCircuitDef@ con = aiFactoryMgr.GetRoleDef(fac.circuitDef, Unit::Role::BUILDER.type);
	if ((con is null) || !con.IsAvailable(ai.frame))
		return null;
	// ONE CONSTRUCTOR PER 30 METAL/S WAS A CAP OF TWO, and one per 6 was a line
	// with no top. Both are replaced by Builder::ConsWantedFor, which is the same
	// logarithmic curve the advanced constructors use -- see its comment for the
	// numbers and where they came from. The tier is read off the def's own cost,
	// and an air constructor is unbounded because a ceiling here is about room in
	// the base, which air does not use.
	const int want = Builder::ConsWantedFor(con);
	// A full bank overrides the curve outright: metal we cannot spend is the
	// economy saying it needs more build power, whatever the shape says.
	if ((con.count >= want) && !aiEconomyMgr.isMetalFull)
		return null;
	return aiFactoryMgr.Enqueue(TaskS::Recruit(
			Task::RecruitType::BUILDPOWER, Task::Priority::HIGH,
			con, fac.GetPos(ai.frame), 0.f));
}

// EYES ARE A FLOOR, NOT A SHARE -- AND AN OWNED LINE HAD NEITHER.
//
// The mix table is combat roles only, and a claimed factory skips every rule
// below it, so from the moment the mix took the bot lab nothing on that line
// could ever build a SCOUT. That is the whole mechanism behind apexearth,
// watching a 4v4 at +25: "enemy super light units would harass our early game
// mexes very effectively and we didn't have any super lights of our own to catch
// them." Armada's is a 21-metal Tick; the enemy's were being built from the tier
// table we had stopped consulting.
//
// A share cannot express it. Scouts are the cheapest units in the game, so a
// metal share large enough to yield a useful COUNT is a large share of the army,
// and one small enough not to distort the army yields none. What we want is a
// standing number, and the honest thing for that number to follow is how much
// ground there is to watch -- so it scales with the extractors we hold, the same
// way everything else here scales with the economy. The def's own availability
// still bounds it, which is where behaviour.json's limit is enforced.
IUnitTask@ ScoutFloor(CCircuitUnit@ fac)
{
	CCircuitDef@ scout = aiFactoryMgr.GetRoleDef(fac.circuitDef, RT::SCOUT);
	if ((scout is null) || !scout.IsAvailable(ai.frame))
		return null;
	const float per = ai.GetTunable("apex_mix_scout_per_mex",
			Targets::At(Targets::SCOUT_PER_MEX));
	int want = 1;
	if (per >= 1.f) {
		CCircuitDef@ mex = SideDef3("armmex", "cormex", "legmex");
		if (mex !is null)
			want = 1 + int(float(mex.count) / per);
	}
	if (scout.count >= want)
		return null;
	IUnitTask@ rec = aiFactoryMgr.Enqueue(TaskS::Recruit(
			Task::RecruitType::FIREPOWER, Task::Priority::NORMAL,
			scout, fac.GetPos(ai.frame), 0.f));
	if (rec !is null) {
		++gScoutPicks;
		if (gScoutPicks <= 3 || (gScoutPicks % 20 == 0)) {
			AiLog(Factory::T() + "apex: mix scout #" + gScoutPicks + " "
				+ scout.GetName() + " have=" + scout.count + " want=" + want);
		}
	}
	return rec;
}

IUnitTask@ MixTask(CCircuitUnit@ fac)
{
	if (ai.GetTunable("apex_mix", 1.f) <= 0.f)
		return null;
	IUnitTask@ bp = BuildPowerFirst(fac);
	if (bp !is null) {
		ClaimFactory(fac);
		return bp;
	}
	if (ai.GetTunable("apex_mix_scout", 1.f) > 0.f) {
		IUnitTask@ sc = ScoutFloor(fac);
		if (sc !is null) {
			ClaimFactory(fac);
			return sc;
		}
	}
	CCircuitDef@ want = NextForMix(fac);
	if (want is null)
		return null;

	IUnitTask@ rec = aiFactoryMgr.Enqueue(TaskS::Recruit(
			Task::RecruitType::FIREPOWER, Task::Priority::NORMAL,
			want, fac.GetPos(ai.frame), 0.f));
	if (rec is null)
		return null;

	ClaimFactory(fac);
	++gMixPicks;
	if (ai.frame >= gNextMixLog) {
		gNextMixLog = ai.frame + 60 * SECOND;
		float weight = 0.f;
		array<float> counter = CounterShares(fac, weight);
		array<float> base = BaseShares();
		string line = Factory::T() + "apex: mix -> " + want.GetName()
			+ " picks=" + gMixPicks
			+ " counterW=" + formatFloat(weight, "", 0, 2);
		for (uint i = 0; i < gMix.length(); ++i)
			line += " | " + formatFloat(Target(i, base, counter, weight), "", 0, 2);
		AiLog(line);
	}
	return rec;
}

}  // namespace Brain
