namespace Builder {

// Construction turrets for the eco lead, laid out as rows behind the base rather
// than piled where a constructor happens to stand. A turret only assists what
// is inside its radius, so stacking them on one yard saturates: the tenth
// turret queues behind the same work as the first.
string armnanotc("armnanotc"); string cornanotc("cornanotc"); string legnanotc("legnanotc");

// Nanos take the band nearest the anchor so their assist radius reaches both the
// factory and the first economy rows; reactors take the deepest band, where one
// going up does not take the rest of the base with it.
bool BandSpot(CCircuitUnit@ unit, CCircuitDef@ def, bool nano, AIFloat3& out spot)
{
	return Base::Spot(unit, def, nano ? Base::NANO : Base::HEAVY, spot);
}

// Only while metal is genuinely piling up. Gating on the bank rather than on
// income keeps this off the list of rules that quietly eat the economy: when
// metal is tight this cannot fire at all, so it never displaces a mex upgrade.
const float NANO_MIN_BANK = 0.5f;   // share of metal storage standing unspent
const float NANO_RICH_BANK = 0.2f;  // ...once income alone justifies the turret
// Building nanos below this income measured as taking metal from the expansion
// that would have paid for more of them later, on the benchmark's short-game
// format; a human keeps early turrets busy in a way the benchmark does not
// model, so this is left tunable rather than trusted as a general answer.
const float NANO_INCOME_GATE_DEF = 60.f;

float NanoIncomeGate()
{
	return ai.GetTunable("apex_nano_income_gate", NANO_INCOME_GATE_DEF);
}
// Raised with the shift away from ground engineers: a turret is 210 metal and
// never walks anywhere, which is why it is the build power this player should
// hold most of. Two rows of twenty is the rectangle it fills out.
// The engine's own per-player unit limit, from the `maxunits` modoption
// (modoptions.lua: default 2000, min 500, max 32000).
//
// This is the only real ceiling there is: slots spent on build power buy the
// few slots that matter for the expensive units this cap otherwise starves.
int gUnitCap = 0;

int UnitCap()
{
	if (gUnitCap > 0)
		return gUnitCap;
	gUnitCap = 2000;
	const string v = string(aiSetupMgr.GetModOptions()["maxunits"]);
	if (v != "") {
		const int n = parseInt(v);
		if (n > 0)
			gUnitCap = n;
	}
	AiLog("apex: unit cap " + gUnitCap);
	return gUnitCap;
}

int CapShare(float share)
{
	const int n = int(float(UnitCap()) * share);
	return (n < 1) ? 1 : n;
}

// Turrets wanted, from income, ceilinged by a share of the unit cap rather than
// by a number someone picked. A turret is 210 metal and 140 build power that
// never walks anywhere, so on a large economy it is the best thing a full bank
// can become.
// 4 per income, 0.16 share, 8s pacing -- bisect-confirmed (leg 2, 10 games):
// reverting these cost 4.6pt of army share and pushed metal-full from 25% to
// 39% median. The nano raise spends the bank; the caretaker ceiling was the
// batch's actual regression.
const float NANO_PER_INCOME = 4.f;
const int   NANO_FULL_BONUS = 20;
const float NANO_CAP_SHARE  = 0.16f;

int NanoCap()
{
	int cap = 2 + int(aiEconomyMgr.metal.income / NANO_PER_INCOME);
	if (aiEconomyMgr.isMetalFull)
		cap += NANO_FULL_BONUS;
	const int ceiling = CapShare(NANO_CAP_SHARE);
	return (cap > ceiling) ? ceiling : cap;
}
// HOW MANY MAY BE UNDER CONSTRUCTION AT ONCE -- this, not NanoCap(), was what
// was actually limiting turret counts: NanoCap() allowed far more than were
// ever reached because only a handful could be in flight at one order per
// period. A trickle-in-flight limit starves a cap that would otherwise be paid
// for by the economy.
const int   NANO_INFLIGHT_BASE = 4;
const float NANO_INFLIGHT_PER_INCOME = 25.f;   // one more in flight per this much
const int   NANO_INFLIGHT_FULL = 12;           // extra while the bank is at the cap

int NanoInFlight()
{
	int n = NANO_INFLIGHT_BASE + int(aiEconomyMgr.metal.income / NANO_INFLIGHT_PER_INCOME);
	if (aiEconomyMgr.isMetalFull)
		n += NANO_INFLIGHT_FULL;
	return n;
}
const int   NANO_STALE    = 12;   // beyond this the counter has drifted, resync
const int   NANO_PERIOD   = 8 * SECOND;
// While the bank is at the cap, order them as fast as placement allows and let
// far more be in flight at once -- a period is the wrong bound here, since what
// should stop us is running out of bank or of ground, both checked anyway.
const int   NANO_FULL_PERIOD   = 1 * SECOND;
const int   NANO_FULL_INFLIGHT = 24;
int gNextNano = 0;
int gNanosAsked = 0;

CCircuitDef@ NanoDef()
{
	return SideDef3(armnanotc, cornanotc, legnanotc);
}

// armnanotc.lua builddistance = 400. Past that a turret assists nothing, and the
// nano band runs out to 1345 from an anchor latched to the FIRST factory -- so
// only its first 26 slots of 160 could ever reach the thing they were built for.
const float NANO_ASSIST_R = 400.f;

// Our factories, thinnest first by construction turrets already inside assist
// range. EVERY one is returned, not just the thinnest: a single factory's
// 400-elmo neighbourhood fills, FindBuildSiteNear fails, and the nano falls all
// the way back to a band slot far away. What bounds this is the ground running
// out at every plant we own, not a count.
array<CCircuitUnit@> FactoriesByNeed()
{
	array<CCircuitUnit@> ranked;
	array<int> need;
	CCircuitDef@ nano = NanoDef();
	if (nano is null)
		return ranked;
	for (uint i = 0; i < Factory::gFacUnits.length(); ++i) {
		CCircuitUnit@ f = Factory::gFacUnits[i];
		if (f is null)
			continue;
		const AIFloat3 at = f.GetPos(ai.frame);
		if (!OnMap(at))
			continue;
		array<CCircuitUnit@>@ have = ai.GetOwnUnitsOfDef(nano, at, NANO_ASSIST_R);
		const int n = (have is null) ? 0 : int(have.length());
		uint slot = ranked.length();
		for (uint j = 0; j < need.length(); ++j) {
			if (n < need[j]) {
				slot = j;
				break;
			}
		}
		ranked.insertAt(slot, f);
		need.insertAt(slot, n);
	}
	return ranked;
}

// One turret site at a factory, packed: FindBuildSiteNear from the factory
// centre spirals to any free ground inside 400, which scattered the turrets
// across the whole neighbourhood. Searching tight from the centroid of the
// block the factory already has packs them shoulder to shoulder; the
// assist-range check keeps the block from creeping away from the factory.
bool NanoSiteAt(CCircuitUnit@ unit, CCircuitDef@ want, CCircuitUnit@ fac,
		AIFloat3& out here)
{
	const AIFloat3 fpos = fac.GetPos(ai.frame);
	array<CCircuitUnit@>@ block = ai.GetOwnUnitsOfDef(want, fpos, NANO_ASSIST_R);
	if ((block !is null) && (block.length() > 0)) {
		float x = 0.f, z = 0.f, n = 0.f;
		for (uint i = 0; i < block.length(); ++i) {
			if (block[i] is null)
				continue;
			const AIFloat3 at = block[i].GetPos(ai.frame);
			x += at.x; z += at.z; n += 1.f;
		}
		if (n >= 1.f) {
			AIFloat3 c;
			c.x = x / n;
			c.z = z / n;
			AIFloat3 site = ai.FindBuildSiteNear(want, c,
					ai.GetTunable("apex_nano_pack_r", 180.f));
			if (OnMap(site) && (site.distance2D(fpos) <= NANO_ASSIST_R)
					&& !Base::SiteTaken(Base::NANO, site)
					&& (ThreatFor(unit, site) <= CON_THREAT_VETO)) {
				{ AIFloat3 sn; if (SnapToNanoGrid(unit, want, site, sn)) site = sn; }
				Base::ReserveSite(site);
				here = site;
				return true;
			}
		}
	}
	AIFloat3 site = ai.FindBuildSiteNear(want, fpos, NANO_ASSIST_R);
	if (OnMap(site) && !Base::SiteTaken(Base::NANO, site)
			&& (ThreatFor(unit, site) <= CON_THREAT_VETO)) {
		{ AIFloat3 sn; if (SnapToNanoGrid(unit, want, site, sn)) site = sn; }
		Base::ReserveSite(site);
		here = site;
		return true;
	}
	return false;
}

// Turrets we hold. aiBuilderMgr.GetWorkerCount() counts these as workers, so any
// cap meant for MOBILE constructors has to subtract them.
int NanoCount()
{
	CCircuitDef@ d = NanoDef();
	return (d is null) ? 0 : d.count;
}

// Where our construction turrets actually stand, as a centroid: a gantry built
// inside an assist field finishes in a fraction of the time one outside it does.
bool NanoCluster(AIFloat3& out spot)
{
	CCircuitDef@ d = NanoDef();
	if ((d is null) || (d.count <= 0) || !gHomeSet)
		return false;
	array<CCircuitUnit@>@ have = ai.GetOwnUnitsOfDef(d, gHomePos, 0.f);
	if ((have is null) || (have.length() == 0))
		return false;
	float x = 0.f, z = 0.f, n = 0.f;
	for (uint i = 0; i < have.length(); ++i) {
		if (have[i] is null)
			continue;
		const AIFloat3 at = have[i].GetPos(ai.frame);
		x += at.x; z += at.z; n += 1.f;
	}
	if (n < 1.f)
		return false;
	AIFloat3 p;
	p.x = x / n;
	p.z = z / n;
	if (!OnMap(p))
		return false;
	spot = p;
	return true;
}

// Metal is at the cap and we are not converting it into anything.
bool MetalFull()
{
	return aiEconomyMgr.isMetalFull;
}

// A gantry, placed in the assist field of our turret rows, paid for out of a
// bank we are otherwise wasting. Advanced constructors only -- asking a T1
// constructor for a gantry is the silent no-op this repo has been bitten by.
const float GANTRY_NEAR_NANO = 700.f;
int gSurplusGantries = 0;

// How far from home to look once the tidy spots are exhausted. A gantry across
// the base beats no gantry.
const float GANTRY_SEARCH_WIDE = 2600.f;
int gNextGantryFailLog = 0;
int gGantrySiteFails = 0;
int gBigBuildAt = -999;
int gBigBuildId = -1;
int gGantrySiteBackoffUntil = 0;

IUnitTask@ SurplusGantry(CCircuitUnit@ unit)
{
	if (!MetalFull() || !Factory::WantMoreGantries())
		return null;
	if (unit.circuitDef.costM < ADV_CON_COST)
		return null;
	CCircuitDef@ gant = Factory::T3Gantry();
	if ((gant is null) || !gant.IsAvailable(ai.frame))
		return null;

	// A gantry is a 16x16 footprint -- the largest thing we ever place -- and on
	// a hilly map there may be no flat square that big anywhere near the nanos.
	// DEBOUNCE a failing site search: 94 asks against the same packed base in
	// one game (watched live MP 2026-08-18) -- the ground does not un-fill in
	// five seconds, and each retry walks three FindBuildSiteNear searches.
	// The backoff doubles per consecutive failure (30s -> 4min cap) and
	// resets the moment a site is found.
	if (ai.frame < gGantrySiteBackoffUntil)
		return null;
	// Widen instead of giving up: assisting nanos are a preference, not a
	// requirement, and a gantry built across the base beats one never placed.
	AIFloat3 near;
	const bool haveNano = NanoCluster(near);
	if (!haveNano)
		near = gHomePos;
	AIFloat3 site = ai.FindBuildSiteNear(gant, near, GANTRY_NEAR_NANO);
	if (!OnMap(site) && haveNano)                    // anywhere in the base
		site = ai.FindBuildSiteNear(gant, gHomePos, GANTRY_NEAR_NANO);
	if (!OnMap(site))                                // anywhere we can reach
		site = ai.FindBuildSiteNear(gant, gHomePos, GANTRY_SEARCH_WIDE);
	if (!OnMap(site)) {
		gGantrySiteFails = (gGantrySiteFails < 4) ? gGantrySiteFails + 1 : 4;
		gGantrySiteBackoffUntil = ai.frame
				+ (30 * SECOND) * (1 << (gGantrySiteFails - 1));
		if (ai.frame >= gNextGantryFailLog) {
			gNextGantryFailLog = ai.frame + 60 * SECOND;
			AiLog(Factory::T() + "apex: gantry NO SITE for " + gant.GetName()
				+ " nano=" + (haveNano ? "1" : "0")
				+ " tried=" + formatFloat(GANTRY_NEAR_NANO, "", 0, 0)
				+ "/" + formatFloat(GANTRY_SEARCH_WIDE, "", 0, 0)
				+ " backoff=" + (30 * (1 << (gGantrySiteFails - 1))) + "s");
		}
		return null;
	}
	gGantrySiteFails = 0;
	if (ThreatFor(unit, site) > CON_THREAT_VETO)
		return null;

	// A factory task carries a reprDef Requests cannot know, so this one builds
	// its own and asks permission instead of handing the job over.
	if (!Requests::Allowed(gant, Task::BuildType::FACTORY, site, 0.f))
		return null;
	// THE ONE GATE: every plant enqueue passes Factory::PlantApproved -- the
	// per-def cap, the ledger and the approval log. A gantry bypassing it was
	// the same class of silent second entrance as the T2-lab reports.
	if (!Factory::PlantApproved(gant))
		return null;
	IUnitTask@ post = aiBuilderMgr.Enqueue(TaskB::Factory(Task::Priority::HIGH,
			gant, site, null, 0.f));
	if (post is null)
		return null;
	++gSurplusGantries;
	AiLog(Factory::T() + "apex: surplus gantry " + gant.GetName()
		+ " by the nanos, bank=" + formatFloat(aiEconomyMgr.metal.current, "", 0, 0)
		+ "/" + formatFloat(aiEconomyMgr.metal.storage, "", 0, 0)
		+ " placed=" + gSurplusGantries);
	return post;
}

// Front repair turrets are GONE -- apexearth 2026-08-18, "kill the concept":
// the trail they left as the front moved was the sparse waste he kept
// reporting. Turrets exist only as clusters at factories and the economy;
// army repair is mobile builders' work.

// A turret must reach WORK at birth: something within its 400 build distance
// that is not another turret, or construction in progress. Without this the
// band kept placing rows into open ground out to 1345 elmos -- 77% of all
// placements, each born an orphan for the reclaim to eat later (watched live
// 2026-08-18, seed 112). Placement stops when useful ground runs out,
// whatever the cap still allows.
bool NanoCanReachWork(CCircuitDef@ want, const AIFloat3& in site)
{
	array<CCircuitUnit@>@ near = ai.GetOwnStructsNear(site, NANO_ASSIST_R);
	if (near is null)
		return false;
	// By VALUE, not existence: a lone 40-metal turbine was justifying a
	// 210-metal turret beside it (screenshot, 2026-08-18). The reachable
	// non-turret structure value must be worth the turret itself.
	float worth = 0.f;
	const float need = ai.GetTunable("apex_nano_work_min", 400.f);
	for (uint k = 0; k < near.length(); ++k) {
		CCircuitUnit@ o = near[k];
		if ((o is null) || (o.circuitDef is null))
			continue;
		if ((want !is null) && (o.circuitDef.id == want.id))
			continue;
		worth += o.circuitDef.costM;
		if (worth >= need)
			return true;
	}
	return false;
}

// Snap a turret site onto the grid of an existing neighbour: with another
// turret within apex_nano_snap_r, the new one goes directly to its top/
// bottom/left/right at footprint pitch, so blocks form as a perfect grid
// (apexearth 2026-08-18). Falls back to the free-search site when all four
// cardinal slots are taken.
bool SnapToNanoGrid(CCircuitUnit@ unit, CCircuitDef@ want,
		const AIFloat3& in from, AIFloat3& out snapped)
{
	const float snapR = ai.GetTunable("apex_nano_snap_r", 200.f);
	array<CCircuitUnit@>@ near = ai.GetOwnUnitsOfDef(want, from, snapR);
	if ((near is null) || (near.length() == 0))
		return false;
	CCircuitUnit@ anchor = null;
	float bestD = snapR + 1.f;
	for (uint i = 0; i < near.length(); ++i) {
		if (near[i] is null)
			continue;
		const float d = from.distance2D(near[i].GetPos(ai.frame));
		if (d < bestD) {
			bestD = d;
			@anchor = near[i];
		}
	}
	if (anchor is null)
		return false;
	const AIFloat3 at = anchor.GetPos(ai.frame);
	// 3x3 footprint = 24 elmos; touching centres one footprint apart.
	const float pitch = ai.GetTunable("apex_nano_grid_pitch", 24.f);
	array<float> dx = {pitch, -pitch, 0.f, 0.f};
	array<float> dz = {0.f, 0.f, pitch, -pitch};
	for (uint k = 0; k < 4; ++k) {
		AIFloat3 cand = at;
		cand.x += dx[k];
		cand.z += dz[k];
		if (!OnMap(cand))
			continue;
		const AIFloat3 site = ai.FindBuildSiteNear(want, cand, pitch * 0.5f);
		if (!OnMap(site) || (site.distance2D(cand) > pitch * 0.5f))
			continue;
		if (Base::SiteTaken(Base::NANO, site))
			continue;
		if (ThreatFor(unit, site) > CON_THREAT_VETO)
			continue;
		snapped = site;
		return true;
	}
	return false;
}

IUnitTask@ EcoNano(CCircuitUnit@ unit)
{
	// BUILD POWER SHOULD TRACK INCOME, NOT ONLY A FULL BANK: a full bank is a
	// rare instant, not a state, so gating solely on "eco lead, or metal full"
	// starved turret count on a compounding economy. Above NANO_INCOME_GATE,
	// income alone pays for one every few seconds, so the bank check below is
	// what should decide, not a cap event.
	const bool richEnough = (aiEconomyMgr.metal.income >= NanoIncomeGate());
	// Three independent reasons, not a role gate: the eco lead builds them as its
	// job, anyone at the metal cap needs the sink, and any real income justifies
	// the build power. Solo reaches this through the last two.
	if (!Factory::EcoLeadActive() && !MetalFull() && !richEnough)
		return null;
	// Half the bank while poor, a fifth once the income itself justifies it.
	const float bankNeed = richEnough ? NANO_RICH_BANK : NANO_MIN_BANK;
	if (aiEconomyMgr.metal.current < aiEconomyMgr.metal.storage * bankNeed)
		return null;
	// A turret costs 3200 energy to put up; buying build power on a grid that
	// cannot pay for it stalls both.
	if (aiEconomyMgr.isEnergyStalling)
		return null;

	CCircuitDef@ want = SideDef3(armnanotc, cornanotc, legnanotc);
	if ((want is null) || !want.IsAvailable(ai.frame) || (want.count >= NanoCap()))
		return null;

	// Bound what is OUTSTANDING, not just what stands. want.count sees finished
	// turrets only and Enqueue does not dedup, so the cap alone let this run to
	// asked=40 against standing=11 in one 20-minute stretch -- ordering a fresh
	// turret every period while thirty were already queued. Same failure the
	// rush constructor cap hit, and spacing alone does not fix it.
	//
	// The counter is resynced rather than trusted forever: a turret that dies
	// leaves asked permanently ahead of count, which would otherwise wedge this
	// rule shut for the rest of the game.
	int outstanding = gNanosAsked - want.count;
	if (outstanding > NANO_STALE) {
		gNanosAsked = want.count;
		outstanding = 0;
	}
	if (outstanding >= NanoInFlight())
		return null;

	// A caretaker has to reach something: the band is tried only once no factory
	// has room left.
	AIFloat3 here;
	bool sited = false;
	array<CCircuitUnit@> facs = FactoriesByNeed();
	// GetOwnUnitsOfDef skips nanoframes, so a turret already on the way is
	// invisible to FactoriesByNeed; the site reservation is what stops the
	// same factory being picked for the same ground every period.
	for (uint i = 0; (i < facs.length()) && !sited; ++i)
		sited = NanoSiteAt(unit, want, facs[i], here);
	// With the factories covered and metal healthy, the next-best lathe spot
	// is the biggest build IN PROGRESS: a reactor going up alone takes
	// minutes a nano beside it halves -- apexearth: "boost priority on
	// making more nanos near the buildings we're trying to make when we are
	// not low on metal." Unfinished = a struct unit that never hit
	// AiUnitFinished; the fresh-nanoframe case IS the point.
	if (!sited && richEnough) {
		// Memoized per second, cheap fields checked FIRST: this scan ran per
		// EcoNano call and put every struct through Main::WasFinished -- a
		// linear 4096-ring walk -- which made op.econano the top section of a
		// whole 8v8 sim (52.8s at 1223us/call). The cost filter drops all but
		// a handful of candidates before any ring lookup, and the pick holds
		// for 30 frames.
		if (ai.frame - gBigBuildAt >= 30) {
			gBigBuildAt = ai.frame;
			gBigBuildId = -1;
			array<CCircuitUnit@>@ around = ai.GetOwnStructsNear(
					unit.GetPos(ai.frame), 3000.f);
			float bigCost = ai.GetTunable("apex_nano_site_min", 1500.f);
			if (around !is null) {
				for (uint i = 0; i < around.length(); ++i) {
					CCircuitUnit@ s = around[i];
					if ((s is null) || (s.circuitDef is null)
						|| (s.circuitDef.costM <= bigCost))
						continue;
					if (Main::WasFinished(int(s.id)))
						continue;
					bigCost = s.circuitDef.costM;
					gBigBuildId = int(s.id);
				}
			}
		}
		CCircuitUnit@ bigBuild = (gBigBuildId >= 0)
				? ai.GetTeamUnit(Id(gBigBuildId)) : null;
		if (bigBuild !is null) {
			AIFloat3 site = ai.FindBuildSiteNear(want,
					bigBuild.GetPos(ai.frame), NANO_ASSIST_R);
			if (OnMap(site) && !Base::SiteTaken(Base::NANO, site)
					&& (ThreatFor(unit, site) <= CON_THREAT_VETO)) {
				{ AIFloat3 sn; if (SnapToNanoGrid(unit, want, site, sn)) site = sn; }
				Base::ReserveSite(site);
				here = site;
				sited = true;
				AiLog(Factory::T() + "apex: nano sited at the "
					+ bigBuild.circuitDef.GetName() + " build");
			}
		}
	}
	if (!sited && !BandSpot(unit, want, true, here))
		return null;
	if (!sited)
		{ AIFloat3 sn; if (SnapToNanoGrid(unit, want, here, sn)) here = sn; }
	// The birth rule, on EVERY path's final site: no reachable work, no turret.
	if (!NanoCanReachWork(want, here))
		return null;

	// Nanos go TIGHT, right next to each other, on a grid pitch that leaves the
	// walkways clear -- spreading them out was the wrong trade against a naval
	// builder walling itself in; tight rows plus lanes buys both.
	bool created = false;
	IUnitTask@ post = Requests::Take(unit, want, Task::BuildType::NANO,
			Task::Priority::NORMAL, here, 0.f, 0.f, created);
	if (post is null)
		return null;
	if (!created)
		return post;
	gNextNano = ai.frame + NANO_PERIOD;
	++gNanosAsked;
	// BURST on a deep bank -- apexearth: "if a building we want to make is
	// cheap and we have tons of resources we should queue up more than just 1
	// request... nano turrets, sometimes you can queue up 5 or more at a time
	// ~20 minutes into the game." One extra per apex_burst_bank_frac (4)
	// nano-costs of banked metal, bounded by the in-flight headroom, each at
	// its own reserved site; stops at the first refused request.
	int batch = int(aiEconomyMgr.metal.current
			/ (want.costM * ai.GetTunable("apex_burst_bank_frac", 4.f)));
	const int head = NanoInFlight() - (gNanosAsked - int(want.count));
	if (batch > head)
		batch = head;
	int burst = 1;
	for (int b = 1; b < batch; ++b) {
		AIFloat3 more;
		bool ok = false;
		array<CCircuitUnit@> facs2 = FactoriesByNeed();
		for (uint i = 0; (i < facs2.length()) && !ok; ++i)
			ok = NanoSiteAt(unit, want, facs2[i], more);
		if (!ok && !BandSpot(unit, want, true, more))
			break;
		if (!NanoCanReachWork(want, more))
			break;
		bool made2 = false;
		// parallel=true: the burst has already reserved a distinct site; without
		// it JoinFor folded every extra request onto site one (burst=1 forever).
		Requests::Take(unit, want, Task::BuildType::NANO,
				Task::Priority::NORMAL, more, 0.f, 0.f, made2, true);
		if (!made2)
			break;
		++gNanosAsked;
		++burst;
	}
	AiLog(Factory::T() + "apex: eco nano " + want.GetName()
		+ " at=" + (sited ? "fac" : "band") + " burst=" + burst
		+ " standing=" + want.count + " asked=" + gNanosAsked
		+ " bank=" + formatFloat(aiEconomyMgr.metal.current, "", 0, 0)
		+ "/" + formatFloat(aiEconomyMgr.metal.storage, "", 0, 0));
	return post;
}

}  // namespace Builder
