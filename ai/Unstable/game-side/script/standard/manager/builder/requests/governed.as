namespace Requests {

// -- what is governed --------------------------------------------------------
//
// NOT mex/mexup/geo/geoup: two extractor spots are two different things wanted
// for their own sake, there is no duplicate to prevent, and stacking builders on
// one is the opposite of what expansion wants. Those keep their own path.
//
// The rest splits in two, because "duplicate" means different things for them:
//
//   ECONOMY   a second one started at the same time is redundancy. Serialized
//             hard: join an existing one anywhere within reach, and never hold
//             more requests of one def than the income can feed.
//   POSITIONAL(DEFENCE) two towers at two places on the front are BOTH wanted,
//             so only the site itself is exclusive -- one request per patch of
//             ground. How much defence we may hold at all is Builder's
//             DefenceShareScreen and Military::DefenceAllowedAt, which already
//             exist; a second ceiling here would be the same bound twice.
// Live requests of one build type, dead excluded -- the market's plant
// gates count these against the income-support rule, because a factory
// REQUESTED is a factory the count does not see yet (measured: 41 lines
// licensed while gFactoryCount lagged the pipeline).
int LiveCountOf(int bt)
{
	int n = 0;
	for (uint i = 0; i < gLive.length(); ++i) {
		if ((gLive[i] !is null) && !gLive[i].IsDead()
			&& (gLive[i].GetBuildType() == Task::BuildType(bt)))
			++n;
	}
	return n;
}

// An unmanned live request for this def, wherever it stands -- the market
// adopts these before founding a new site (a stall interrupt pulls a con
// off a nano; the re-decided nano must FINISH that frame, not start a
// fresh slot -- watched: nanoframes abandoned beside new starts).
IUnitTask@ OrphanOf(CCircuitDef@ def)
{
	if (def is null)
		return null;
	for (uint i = 0; i < gLive.length(); ++i) {
		IUnitTask@ t = gLive[i];
		if ((t is null) || t.IsDead())
			continue;
		if ((t.buildDef is null) || (t.buildDef !is def))
			continue;
		if (Workers(t) == 0)
			return t;
	}
	return null;
}

// The live task itself, for joining an in-progress build of this def.
IUnitTask@ LiveTaskOf(CCircuitDef@ def)
{
	if (def is null)
		return null;
	for (uint i = 0; i < gLive.length(); ++i) {
		if ((gLive[i] !is null) && !gLive[i].IsDead()
			&& (gLive[i].buildDef !is null) && (gLive[i].buildDef is def))
			return gLive[i];
	}
	return null;
}

// Any live request (manned or not) for exactly this def.
bool LiveOfDef(CCircuitDef@ def)
{
	if (def is null)
		return false;
	for (uint i = 0; i < gLive.length(); ++i) {
		if ((gLive[i] !is null) && !gLive[i].IsDead()
			&& (gLive[i].buildDef !is null) && (gLive[i].buildDef is def))
			return true;
	}
	return false;
}

// METAL WORK IS GOVERNED TOO. MEX and MEXUP were absent here, so an extractor
// or an upgrade never entered the register at all: it could not be joined (the
// join rung only sees registered tasks), and it did not count in
// LiveSiteCount, so every other site's crew was sized as though no metal work
// were happening -- while those hands were drawing metal the whole time
// (apexearth 2026-08-25: "if a want is still in progress (like a mexup) we
// should be willing to put more guys on it to build it faster").
bool Governed(int bt)
{
	return (bt == int(Task::BuildType::MEX))
		|| (bt == int(Task::BuildType::MEXUP))
		|| (bt == int(Task::BuildType::FACTORY))
		|| (bt == int(Task::BuildType::NANO))
		|| (bt == int(Task::BuildType::STORE))
		|| (bt == int(Task::BuildType::ENERGY))
		|| (bt == int(Task::BuildType::CONVERT))
		|| (bt == int(Task::BuildType::DEFENCE))
		|| (bt == int(Task::BuildType::BUNKER))
		|| (bt == int(Task::BuildType::BIG_GUN))
		|| (bt == int(Task::BuildType::RADAR))
		|| (bt == int(Task::BuildType::SONAR));
}

bool Positional(int bt)
{
	return (bt == int(Task::BuildType::DEFENCE));
}

// How close counts as the same ground for an EXACT-POINT request. Comfortably
// bigger than any T1/T2 economy footprint, so a real second site a short walk
// away is untouched. An AREA request passes its own radius instead.
const float SAME_SITE = 150.f;

// Beyond this, helping costs more in walk time than it saves, and the script
// cannot ask whether a position is even reachable.
const float REACH = 1500.f;

// How much nearer a request somebody is already working is treated as being,
// when choosing between it and one merely sitting in the queue.
const float ASSIGNED_BIAS = 400.f;

// Below this cost, walking across the base to help is worse than building your
// own -- solar is 155, wind 43, a construction turret 210, a T1 lab 500. It
// bounds JOINING only. Whether a second request may EXIST is a different
// question and is asked at every cost -- without that, cheap defs pile
// duplicates onto one tile.
const float JOIN_MIN_COST = 200.f;

// WORTH THE WALK. A site's remaining build time is (unbuilt metal) / (build
// power already on it); if that is shorter than this unit's walk there, the
// walk buys nothing -- the site finishes, or gets close enough that one more
// constructor is negligible, before it could arrive. apexearth, watching
// 2026-08-14: "our units are willing to walk long distances to build a
// building which would be built by the time they get there." APPROXIMATE, not
// exact, for two reasons: CCircuitDef exposes no move-speed binding to script,
// so travel time uses one flat assumed speed rather than the joining unit's
// own -- a fast vehicle con may be turned away from a join that would in fact
// still be worth it, while a slow bot con is the case this actually protects.
// And the site's current build power is read as DRAIN per worker already
// assigned (the same per-constructor pull InFlightCap uses elsewhere), not the
// site's true buildSpeed, which script cannot read either.
const float ASSUMED_CON_SPEED = 40.f;  // elmos/s; armck/corck are 36, armcv/corcv 54 (unit defs, 2026-08-14)

bool WorthJoining(float dist, float progress, float costM, uint busy,
		float speed = 0.f)
{
	if (dist <= 0.f)
		return true;
	const float remainingMetal = costM * (1.f - progress);
	if (remainingMetal <= 0.f)
		return false;   // effectively done; nothing left for another builder to add
	const float buildRate = DRAIN * float((busy > 0) ? busy : 1);
	const float remainingTime = remainingMetal / buildRate;
	// THE ASKER'S OWN LEGS (apexearth: "our T1 air cons should be making
	// tons of those" -- a flying con at ~5x ASSUMED_CON_SPEED was refused
	// joins it could make in seconds, 78k tooFar refusals in one watched
	// game, its elections wasted on re-asking).
	const float v = (speed > 1.f) ? speed : ASSUMED_CON_SPEED;
	const float travelTime = dist / v;
	return travelTime <= remainingTime;
}

// THE CREW IS SIZED BY THE TIME IT SAVES: one more pair of hands is worth
// its walk when the seconds it takes off the site's remaining build time
// exceed the seconds it spends walking there. Lathe is what is actually on
// the site -- hands arrived, walkers nearer than this one, the nano ring --
// in real build power; a walker farther out lathes nothing yet, and counting
// it closed sites that had minutes left. The saving falls as the square of
// the crew, which is the whole bound.
bool WorthJoiningSite(IUnitTask@ cand, float dist, float speed = 0.f,
		float handBP = 0.f)
{
	if ((cand is null) || (cand.buildDef is null))
		return true;
	if (dist <= 0.f)
		return true;
	const int bd = int(cand.buildDef.id);
	if (!Catalog::ValidId(bd))
		return true;
	const float remainingBt = Catalog::gBuildTime[bd] * (1.f - Progress(cand));
	if (remainingBt <= 0.f)
		return false;
	uint arrived = 0;
	float lathe = ArrivedLathe(cand, arrived, dist);
	if (cand.target !is null)
		lathe += RingSeen(cand);
	if (lathe <= 0.f)
		return true;
	const float b = (handBP > 0.f) ? handBP : lathe / float((arrived > 0) ? arrived : 1);
	const float saved = remainingBt * b / (lathe * (lathe + b));
	const float v = (speed > 1.f) ? speed : ASSUMED_CON_SPEED;
	return (dist / v) <= saved;
}

int gTooFar = 0;    // refused: this site will finish (or near enough) before the walk

// HOW MANY REQUESTS OF ONE DEF MAY BE IN FLIGHT AT ONCE, from what the ECONOMY
// can feed -- never a flat number and never a clock.
//
// A lathe pulls a roughly constant metal/s while it builds, set by its
// buildSpeed and not by what it is building; the cost only decides how long the
// drain lasts. So the number of parallel jobs an economy can keep fed is
// income/drain. Above that, K buildings in parallel all land at K*T and nothing
// pays until then -- the metal is spent either way, and the only thing more
// parallel sites can buy is taking it off everything else.
const float DRAIN = 7.0f;   // metal/s one constructor pulls
const uint  MIN_INFLIGHT = 2;

uint InFlightCap()
{
	const float drain = ai.GetTunable("apex_request_drain", TUNE_REQUEST_DRAIN);
	if (drain <= 0.f)
		return MIN_INFLIGHT;
	// Income AND the bank's spendable flow, the same feed ValueOf prices by:
	// on income alone a 97%-full bank still capped energy at two sites
	// while the Isthmus mid-game stalled (minutes 12-15, pull 480-760
	// against 380-500 made).
	const float look = ai.GetTunable("apex_e_lookahead", TUNE_E_LOOKAHEAD);
	const float bankFlow = aiEconomyMgr.metal.current / ((look > 1.f) ? look : 30.f);
	const float want = (aiEconomyMgr.metal.income + bankFlow) / drain;
	if (want <= float(MIN_INFLIGHT))
		return MIN_INFLIGHT;
	return uint(want);
}

// A DUPLICATE COSTS THE WHOLE BUILDING AGAIN. InFlightCap answers how many
// requests the INCOME can feed across a def -- it knows nothing about what one
// of them costs, so the same income licensed several parallel advanced solars
// and duplicate T3 defence on an empty bank (apexearth 2026-08-21: "We are
// still making duplicate buildings at the same time when we are not wealthy
// enough to do so"; earlier, on Pulsars: "Do we want 1 T3 defense in 1/3rd the
// time, or 3 T3 defense in 3/3rds that time..?"). The extra site is allowed
// only while the BANK already holds the duplicate's cost -- banked metal is
// the one honest signal of "wealthy enough to pay twice at once". The first
// site is never blocked; this only serializes duplicates.
uint EffectiveCap(const CCircuitDef@ want)
{
	// ADVANCED SOLARS ARE STRICTLY SERIAL, whatever the bank. apexearth
	// 2026-08-21: "A new advanced solar order should not be wanted while we
	// already have one being fulfilled." The pack rule keeps them adjacent;
	// the ORDER is one at a time -- a second asker folds onto the live one
	// through JoinFor and helps finish it instead of opening another.
	if (ai.GetTunable("apex_advsol_serial", TUNE_ADVSOL_SERIAL) > 0.f) {
		const string n = want.GetName();
		if ((n == "armadvsol") || (n == "coradvsol") || (n == "legadvsol"))
			return 1;
	}
	uint cap = InFlightCap();
	// The cap is a metal-feed cap; with metal being wasted the feed is not the
	// limit, the hands are.
	if (Market::MetalWasting()) {
		const uint hands = uint(Market::ConsOwnedAny());
		if (hands > cap)
			cap = hands;
	}
	const float per = want.costM * ai.GetTunable("apex_dup_bank", TUNE_DUP_BANK);
	if (per > 0.f) {
		// ...AND THE FLOW NOTHING IS SPENDING, over the duplicate's own
		// build. A bank capped by storage under one reactor's price read
		// "not wealthy" while a thousand metal a second was thrown away
		// (the eco seat: storage 3,400, fusion 4,500, one site forever).
		float paid = aiEconomyMgr.metal.current;
		const float unspent = aiEconomyMgr.metal.income - aiEconomyMgr.metal.pull;
		const uint crew = ArrivalCrew(want);
		if ((unspent > 0.f) && (crew > 0)) {
			const float hand = Market::ConWorkerBP() * (80.f / 7.f);
			const float secs = StartLatencyS()
					+ Catalog::gBuildTime[int(want.id)] / (float(crew) * hand);
			paid += unspent * secs;
		}
		const uint wealth = 1 + uint(paid / per);
		if (wealth < cap)
			cap = wealth;
	}
	// SERIAL UNTIL SATURATED (apexearth 2026-08-30: four cons on four fusions
	// is power in four minutes; the same four on ONE fusion is power in one --
	// "there's no reason we should ever make two identical, really expensive
	// things right next to each other at the same time"). The metal is spent
	// either way; parallel only moves the first completion LATER. So wealth
	// licenses a duplicate only once every manned site of this def already
	// holds its full crew -- hands that could still join must join first.
	// Cheap defs saturate at two or three hands, so converters and nanos still
	// parallelize freely; "really expensive" falls out of the crew arithmetic.
	if (!SitesSaturated(want)) {
		const uint have = InFlight(want);
		if (have < cap)
			cap = (have > 0) ? have : 1;
	}
	return cap;
}

// Every manned live site of this def carries its full crew. An unmanned
// PROPOSAL does not block (it is claimable, not a working site) -- but an
// unmanned task with a STANDING FRAME does: the consolidation rung strips
// worse energy sites to zero hands on purpose, and reading those as "not a
// site" licensed a fresh duplicate beside the stripped frame (watched live
// 20.0m: `request new armfus inFlight=1` right after consolidation).
bool SitesSaturated(const CCircuitDef@ want)
{
	const uint cap = SiteWorkerCap(want);
	for (uint i = 0; i < gLive.length(); ++i) {
		IUnitTask@ t = gLive[i];
		if ((t is null) || t.IsDead() || (t.GetType() != Task::Type::BUILDER))
			continue;
		const CCircuitDef@ has = t.buildDef;
		if ((has is null) || (has.id != want.id))
			continue;
		const uint busy = Workers(t);
		if ((busy < cap) && ((busy > 0) || (t.target !is null))) {
			// ...unless the lathe already on it finishes it before another
			// hand could arrive: counted by crew, a reactor with five hands
			// and a ring stayed "unsaturated" for its whole build and the
			// next one waited (seat: 7 reactors in 26 min, take.full x805).
			if (t.target !is null) {
				uint arrived = 0;
				const float lathe = ArrivedLathe(t, arrived) + RingSeen(t);
				const float lat = StartLatencyS();
				if ((lathe > 0.f) && (lat > 1.f)) {
					const int bd = int(has.id);
					const float left = Catalog::gBuildTime[bd] * (1.f - Progress(t));
					if (left / lathe <= lat)
						continue;
				}
			}
			return false;
		}
	}
	return true;
}

// HOW MANY WORKERS ONE SITE IS WORTH, from the building's own cost. Piling the
// whole pool onto one site was the old bound (InFlightCap, an ECONOMY-wide
// number), which serialized every def to one site until it saturated -- a rich
// economy that wants several converters or nanos AT ONCE could never open a
// second site. Each worker adds ~DRAIN metal/s of lathe, so cost/per is the
// point past which another pair of hands shortens the build less than opening
// the next site would; parallel site count stays bounded by InFlightCap, i.e.
// by income. apexearth: "we should be willing to make more than 1 of any
// building at one time if we are wealthy enough."
// The cost-derived arm on its own: how many hands the SITE is worth before
// another pair shortens the build less than opening the next site would.
// OVERFLOW FEEDS HANDS (apexearth 2026-08-28: "If we're overflowing
// metal our *want* ... should increase even more, we should be willing
// to create a whole bunch of them at the same time ... I have a hunch
// that we only think about making more buildings every ~N seconds, and
// often just 1 or 2 at a time"). His hunch was the CREW: cost/300 caps
// an advanced solar at ~2 hands, so "3 cons on one build" was
// arithmetically impossible -- joins refused as full, the parallel
// opener the only outlet, and metal rotting anyway. Wasted metal is
// exactly the feed for more hands: every DRAIN of overflow funds one
// more worker on any site.
// ...and the crew is sized by the WORK, not only by the price.
//
// apexearth: "probably have plenty of constructors, but they're all joined and
// working on fewer things." Measured (convlathe-s11, Comet Catcher 8v8 +100%):
// a median of 126 builders a team against 28 live requests, joins outnumbering
// new sites 2,192 to 286 -- and the advanced converter, the most buildtime-
// dense building we make, holding a mean of 1.8 hands against a cap of 24.
//
// The cap was the reason. cost/300 asks how EXPENSIVE a site is, and build
// time is what a pair of hands actually shortens:
//
//     armmmkr   380 metal ->  2 hands, for 35,000 buildtime
//     armfus  4,300 metal -> 15 hands, for 70,000 buildtime
//
// Half the work, an eighth of the crew. Same category error the nano-sink test
// made: the question is how much work is there, not how much did it cost.
//
// Taken as the MAX of the two arms so nothing loses crew -- this only raises
// the cap where the work is denser than the price suggests. The divisor is set
// so the reference building keeps the crew it has today (70,000 / 4,700 ~ 15,
// the same 15 that 4,300/300 gives), which makes this a correction to the
// buildtime-dense outliers rather than a re-tuning of every site.
uint CostCrew(const CCircuitDef@ want)
{
	const float per = ai.GetTunable("apex_site_cost_per_worker", TUNE_SITE_COST_PER_WORKER);
	uint n = (per > 0.f) ? uint(1.f + want.costM / per) : MIN_INFLIGHT;
	const float perBt = ai.GetTunable("apex_site_bt_per_worker", TUNE_SITE_BT_PER_WORKER);
	if ((perBt > 0.f) && (want !is null)) {
		const int wd = int(want.id);
		if (Catalog::ValidId(wd)) {
			const uint nb = uint(1.f + Catalog::gBuildTime[wd] / perBt);
			if (nb > n)
				n = nb;
		}
	}
	n += uint(Market::OverflowM()
			/ ((ai.GetTunable("apex_request_drain", TUNE_REQUEST_DRAIN) > 1.f)
				? ai.GetTunable("apex_request_drain", TUNE_REQUEST_DRAIN) : 7.f));
	return (n < MIN_INFLIGHT) ? MIN_INFLIGHT : n;
}

// THE BANK PREPAYS THE JOB. The two clamps below ration hands by what the
// INCOME can keep fed -- but a site whose whole bill is already banked draws
// nothing from income, and every hand it is denied is metal left rotting
// while the building arrives later (apexearth: "putting all that total build
// power onto one fusion would make it build that much faster"). With the
// bill covered, only the cost-derived crew bounds the site.
bool BankCovers(const CCircuitDef@ want)
{
	// ...AND EVERYTHING ELSE IT HAS ALREADY BEEN PROMISED TO. This asked whether
	// one bank could pay for ONE building and then licensed the site's whole
	// cost-derived crew -- 15 hands on a fusion -- with no regard for the other
	// claims standing against the same metal. That is why PeelSurplus had
	// nothing to peel while three cons ground on a reactor with an empty bank:
	// three is a fifth of quota. If this want is itself already ordered its cost
	// sits inside MOrderedM, which only makes the test stricter -- and it
	// relaxes again the moment the row is framed and drawing.
	return (want !is null)
			&& ((aiEconomyMgr.metal.current - Market::MOrderedM()) >= want.costM);
}

// A CREW IS BOUNDED BY ARRIVAL. Past the hands that finish the site within
// the fleet's measured order-to-ground wait, the next hand walks up to a
// finished building -- so those hands are a second site, not a bigger crew.
// Without this the overflow term above put ~140 hands on ONE reactor,
// SitesSaturated never held, and a 1,000 m/s eco seat ran its reactors one at
// a time ~60 s apart (measured: 20 hands each, 38 s latency, 200k of 590k
// metal wasted). Zero until the first ground is broken.
uint ArrivalCrew(const CCircuitDef@ want)
{
	const float lat = StartLatencyS();
	const float hand = Market::ConWorkerBP() * (80.f / 7.f);
	if ((lat <= 1.f) || (hand <= 1.f) || (want is null))
		return 0;
	const int wd = int(want.id);
	if (!Catalog::ValidId(wd))
		return 0;
	const uint n = uint(1.f + Catalog::gBuildTime[wd] / (hand * lat));
	return (n < MIN_INFLIGHT) ? MIN_INFLIGHT : n;
}

uint SiteWorkerCap(const CCircuitDef@ want)
{
	uint n = SiteWorkerCapFed(want);
	const uint arrive = ArrivalCrew(want);
	return ((arrive > 0) && (n > arrive)) ? arrive : n;
}

uint SiteWorkerCapFed(const CCircuitDef@ want)
{
	if (want is null)
		return MIN_INFLIGHT;
	uint n = CostCrew(want);
	if (BankCovers(want))
		return n;
	const uint pool = InFlightCap();
	if (n > pool)
		n = pool;
	// BIG ENERGY TAKES THE WHOLE HAND POOL, on one site. Two numbers were
	// wrong here at once. FeedableCrew divides the pool by how many sites
	// stand, so each read "full" the moment a few were open -- and "full" is
	// what licenses the next one (measured: peak 6 frames, t2 12.6m). And
	// CostCrew prices a 370m advanced solar at TWO hands, so sites saturated
	// instantly and wealth then licensed seven at once (measured: peak 7).
	// Neither number is about the site. What actually bounds useful hands on
	// one building is metal throughput -- income/DRAIN, InFlightCap -- because
	// a lathe pulls the same drain whatever it builds. So the whole feedable
	// pool may work the one reactor, which is the point: apexearth, "putting
	// all that total build power onto one fusion would make it build that much
	// faster". Saturation is then genuinely rare, and the class gate below
	// keeps the second site shut until it happens.
	// ...IN THE ECO ROLE. That statement was made of the eco player; in a
	// standard game the pool is owed to army and defence too (apexearth
	// 2026-09-11, on a mean crew of 14 and a peak of 49: "You're putting all
	// our build power into that? In an eco role sure, but that's not what
	// we're doing here"). Outside it a reactor keeps its cost-derived crew
	// under the pool, never the per-site share: that share read ONE hand per
	// fusion with twenty sites open (337 s a reactor against 88, measured),
	// and WorthJoiningSite is what actually sizes the crew below the cap.
	if (IsBigEnergy(want))
		return (Market::EcoQuiet() || Market::EcoOnly()) ? ((n > pool) ? n : pool) : n;
	// The metal unlock likewise takes the whole pool: split evenly over eight
	// live sites the T2 lab got one hand, the same as a solar.
	if (IsMetalUnlock(want))
		return (n > pool) ? n : pool;
	const uint fed = FeedableCrew(want);
	return (n > fed) ? fed : n;
}

}  // namespace Requests
