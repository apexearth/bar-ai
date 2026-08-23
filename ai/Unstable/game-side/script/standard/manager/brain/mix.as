namespace Brain {

//------------------------------------------------------------------------------
// WHAT MIX NOW, NOT WHAT NEXT.
//
// The existing pipeline asks "what should this factory build NEXT" and lets the
// first rule that answers win, so the army mix is an OUTCOME of tier tables,
// response weights and role gates interacting -- nobody can point at where
// "35% raiders" is decided. Here the target is stated, and each decision is
// simply "which role is furthest below it".
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

// WHICH FACTORIES THE BRAIN OWNS. Two systems taking turns on one production
// line is worse than either alone -- the mix aiming for a composition while
// old floors insert rez bots, radar planes and fighters behind its back, with
// neither responsible for the result.
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
	FQForget(id);
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

	// THE ANSWER TO BEING RAIDED, with no super-light counter of our own before
	// this role existed.
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

	// THE T2 ROLES THE TABLE COULD NOT NAME. behaviour.json gives armfboy the
	// HEAVY role and armsnipe anti_heavy_ass, and neither was in this table, so
	// an owned line could not build them at all -- Hound (armfido) is Armada's
	// only assault-role T2 bot, so the whole ASSAULT share became Hounds.
	//
	// Both defs are T2, so IsAvailable keeps these out of the T1 phase without a
	// clock.
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
// Each role's demand is the enemy metal in the roles it counters, normalised
// into a second set of shares which Target() blends with the base table.
// GetEnemyCost only accumulates on EnemyEnterLOS, so a zero means "not seen"
// rather than "not there" -- this is a BLEND WEIGHTED BY HOW MUCH WE HAVE SEEN,
// so with nothing scouted the base table is used unchanged rather than reading
// as "the enemy has nothing".
array<float> CounterShares(CCircuitUnit@ fac, float &out weight)
{
	array<float> out_(gMix.length(), 0.f);
	weight = 0.f;
	float seen = 0.f;
	float total = 0.f;
	for (uint i = 0; i < gMix.length(); ++i) {
		float demand = 0.f;
		for (uint c = 0; c < gMix[i].counters.length(); ++c) {
			// AIR IS THE ONE ROLE WHOSE RAW COST LIES. Air constructors and air
			// scouts both carry the AIR role, so GetEnemyCost(AIR) reads enemy
			// ECONOMY as aircraft and pulled the AA share toward the cap.
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
	weight = MIX_COUNTER_MAX * frac * ai.GetTunable("apex_mix_counter", TUNE_MIX_COUNTER);
	if (weight > MIX_COUNTER_MAX)
		weight = MIX_COUNTER_MAX;
	return out_;
}

// The base table read through the economy. The chaff fade lives in targets.as
// as the ROLE_RAIDER curve itself, a shape rather than a multiplier bolted on;
// scouts fade the same way through SCOUT_PER_MEX. Renormalised so the weight a
// fading role gives up is taken by the roles that still earn it, rather than
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

// THE LINE, AND WHAT ONLY WORKS BEHIND IT.
//
// Artillery and the anti-heavy pair outrange everything and die to anything
// that reaches them, so their worth is conditional on a line standing in
// front -- apexearth, watching: Ambassadors "are only worth anything so long
// as we have a frontline army... without your basics those other units are
// helpless". Nothing in the share table said so: ARTY counters STATIC, so an
// enemy with defences pulled artillery toward the counter cap whether or not
// we still had anything to escort it.
//
// AA is deliberately NOT here: it answers aircraft, which do not care what
// our ground line looks like.
bool IsLineRole(Type r)
{
	return (r == RT::ASSAULT) || (r == RT::HEAVY) || (r == RT::SKIRM);
}

bool NeedsLine(Type r)
{
	return (r == RT::ARTY) || (r == RT::AH) || (r == RT::AHA);
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

	// How much of the line we asked for is actually standing, as a fraction of
	// its own target. A proportion, not a gate: at half a line the escorted
	// roles are worth half their share, and the term releases itself as the
	// line rebuilds. Roles this factory cannot build are excluded from both
	// sides, so a line-less factory is not damped for a line it could never
	// have made.
	float lineHave = 0.f;
	float lineWant = 0.f;
	for (uint i = 0; i < gMix.length(); ++i) {
		if ((held[i] < 0.f) || !IsLineRole(gMix[i].role))
			continue;
		lineHave += held[i] / total;
		lineWant += Target(i, base, counter, weight);
	}
	float lineMult = 1.f;
	if (lineWant > 0.001f) {
		lineMult = lineHave / lineWant;
		if (lineMult > 1.f)
			lineMult = 1.f;
	}

	// A RATIO BEING MET IS NOT A REASON TO STOP BUILDING. worstGap starting
	// at 0 meant once no role was below target this returned null, an owned
	// line does not fall through to the engine's own rules, and the factory
	// stood idle on a full bank.
	//
	// Starting below every possible gap means the line always has an answer:
	// whichever role is furthest below target, or when all are at or above
	// it, the one that is least over -- the line never goes quiet while it
	// can build something.
	CCircuitDef@ best = null;
	float worstGap = -1000.f;
	for (uint i = 0; i < gMix.length(); ++i) {
		if (held[i] < 0.f)
			continue;            // not buildable here
		const float have = held[i] / total;
		float tgt = Target(i, base, counter, weight);
		if (NeedsLine(gMix[i].role))
			tgt *= lineMult;
		const float gap = tgt - have;
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
// BUILD POWER IS NOT PART OF THE ARMY MIX. As a share alongside the combat
// roles it never won: combat shares start at zero and are constantly emptied
// by losses, so the largest gap is ALWAYS a combat role and the constructor is
// never chosen -- which starves the thing that builds the economy.
//
// So it is a FLOOR, checked before the ratio: below what the income justifies,
// the next unit off this line is a constructor.
IUnitTask@ BuildPowerFirst(CCircuitUnit@ fac)
{
	CCircuitDef@ con = aiFactoryMgr.GetRoleDef(fac.circuitDef, Unit::Role::BUILDER.type);
	if ((con is null) || !con.IsAvailable(ai.frame))
		return null;
	// Replaced by Builder::ConsWantedFor, the same logarithmic curve the
	// advanced constructors use. The tier is read off the def's own cost, and an
	// air constructor is unbounded because a ceiling here is about room in the
	// base, which air does not use.
	const int want = Builder::ConsWantedFor(con);
	// A FULL BANK RAISES THE LIMIT, IT DOES NOT REMOVE IT. `&& !isMetalFull`
	// let a full bank bypass the curve outright -- and a player that is LOSING
	// is permanently metal-full, since stalled production has nothing to spend,
	// so the limit switched itself off exactly when the game was going worst.
	// Full metal is still evidence more build power is wanted, so it buys
	// headroom on the curve rather than a blank cheque.
	int cap = want;
	if (aiEconomyMgr.isMetalFull)
		cap = int(float(want) * ai.GetTunable("apex_con_full_mult", TUNE_CON_FULL_MULT)) + 1;
	if (con.count >= cap)
		return null;
	return aiFactoryMgr.Enqueue(TaskS::Recruit(
			Task::RecruitType::BUILDPOWER, Task::Priority::HIGH,
			con, fac.GetPos(ai.frame), 0.f));
}

// EYES ARE A FLOOR, NOT A SHARE -- AND AN OWNED LINE HAD NEITHER. The mix table
// is combat roles only, so once a claimed factory skips every rule below it,
// nothing on that line could ever build a SCOUT.
//
// A share cannot express it: scouts are the cheapest units in the game, so a
// share large enough to yield a useful count is a large share of the army, and
// one small enough not to distort the army yields none. So it is a standing
// number that scales with the ground there is to watch, i.e. the extractors we
// hold, the same way everything else here scales with the economy.
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

// WHERE THE FACTORY'S METAL GOES, in metal rather than in decisions -- a
// constructor and a raider are one pick each and are not the same spend.
int gMixBPn = 0;    float gMixBPm = 0.f;
int gMixScn = 0;    float gMixScm = 0.f;
int gMixFin = 0;    float gMixFim = 0.f;

IUnitTask@ MixTask(CCircuitUnit@ fac)
{
	if (ai.GetTunable("apex_mix", TUNE_MIX) <= 0.f)
		return null;
	// DO NOT APPEND TO A QUEUE THAT ALREADY HAS WORK. Our Enqueue is blind --
	// see Factory::gQTask -- so without this every call adds another order on
	// top of the last. Declining hands the line to DefaultMakeTask, which scans
	// the pending list and ASSIGNS an existing task instead of creating one;
	// that reuse path is the only correct queue handling in the codebase and
	// our pipeline runs entirely ahead of it.
	if (!Factory::QueueHasRoom())
		return null;
	IUnitTask@ bp = BuildPowerFirst(fac);
	if (bp !is null) {
		ClaimFactory(fac);
		++gMixBPn;
		CCircuitDef@ bpd = aiFactoryMgr.GetRoleDef(fac.circuitDef, Unit::Role::BUILDER.type);
		if (bpd !is null)
			gMixBPm += bpd.costM;
		return bp;
	}
	if (ai.GetTunable("apex_mix_scout", TUNE_MIX_SCOUT) > 0.f) {
		IUnitTask@ sc = ScoutFloor(fac);
		if (sc !is null) {
			ClaimFactory(fac);
			++gMixScn;
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
	++gMixFin;
	gMixFim += want.costM;
	if (ai.frame >= gNextMixLog) {
		gNextMixLog = ai.frame + 60 * SECOND;
		float weight = 0.f;
		array<float> counter = CounterShares(fac, weight);
		array<float> base = BaseShares();
		string line = Factory::T() + "apex: mix -> " + want.GetName()
			+ " picks=" + gMixPicks
			+ " spend bp=" + gMixBPn + "/" + formatFloat(gMixBPm, "", 0, 0)
			+ " sc=" + gMixScn
			+ " fire=" + gMixFin + "/" + formatFloat(gMixFim, "", 0, 0)
			+ " counterW=" + formatFloat(weight, "", 0, 2);
		for (uint i = 0; i < gMix.length(); ++i)
			line += " | " + formatFloat(Target(i, base, counter, weight), "", 0, 2);
		AiLog(line);
	}
	return rec;
}

}  // namespace Brain
