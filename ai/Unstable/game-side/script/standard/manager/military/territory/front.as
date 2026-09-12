namespace Military {

// THE FRONT LINE, AS A CURVE ACROSS THE MAP, COMPUTED FROM THE BATTLEFIELD.
//
// Not one marker, a CURVE. The influence map is engine-side and always present
// -- GetNetInflAt is ally minus enemy -- so the front is where that crosses
// zero: "where OUR territory ends and the ENEMY'S begins". Sampled once per
// lane across the width of the map, the crossings form a line that bulges
// where they have pushed into us and recedes where we have pushed into them.
//
// Nothing here is a gadget. The old source read ai_frontx_<team>, published by
// dev_team_income.lua, which exists only in BAR.sdd, so in a hosted game it
// returned nothing at all.
//
// Forward is the bearing from our base to the enemy centroid: a poor answer to
// "where is that raider", a fine one to "which way is the enemy", which is all
// it is asked. Lanes run perpendicular to it. Before contact there is no
// crossing and the opening answer is the one the start boxes give -- halfway.
// LANES SPAN THE MAP, they are not a fixed width: the count is fixed and the
// SPACING follows the map's diagonal, so the line always reaches both edges
// whatever it is playing on -- a fixed-width lane visibly stopped a third of
// the way down an 8v8 map.
const int FRONT_LANES = 6;            // each side of centre, so 13 lanes

float FrontLaneGap()
{
	const float w = float(AiTerrainWidth());
	const float h = float(AiTerrainHeight());
	const float diag = sqrt(w * w + h * h);
	return diag / float(2 * FRONT_LANES);
}
const int   FRONT_SAMPLES  = 14;
const float FRONT_SCAN_END = 1.15f;   // a little past their centroid
const float FRONT_BAND     = 0.18f;   // how wide "on the line" is, as a fraction
const float FRONT_SETBACK  = 0.12f;   // build this far inside it, not on it

// THE FRONT IS A RING AROUND WHAT WE HOLD, NOT A LINE ACROSS ONE BEARING.
//
// Lanes are laid perpendicular to ONE bearing -- our centre to the enemy
// CENTROID -- so the front they describe is always a straight line facing one
// direction. A team in a corner is surrounded across ninety degrees or more,
// and the average of all those enemies points somewhere down the middle, so
// the lanes end up perpendicular to a direction no individual enemy is
// actually on.
//
// Sampling RADIALLY has no preferred direction: one ray per bearing, each
// finding its own crossing, and the shape that falls out is whatever the
// situation is -- a straight line when the enemy is on one side, an arc cutting
// off a corner when we are boxed into one, a full ring when surrounded. It is
// also less code than the lane version: no perpendicular, no lane gap, no map
// diagonal.
const int FRONT_RAYS = 24;            // every 15 degrees
// Radius, in elmos, at which each bearing's ray meets the front. Index 0 points
// along +x and they run counter-clockwise.
array<float> gRayR;
// The same per bearing, but as far out as a BUILDER may actually work.
array<float> gRaySafe;
// DID THIS BEARING ACTUALLY MEET ANYBODY. A ray that ran its whole length
// without finding enemy influence, or that walked off the map, has no front on
// it -- it is our own rear, or the edge of the world. Emitting every ray as a
// build point turns the ring into a literal circle of towers around the base,
// most of them facing nothing; sampling all the way round is still right --
// that is what lets a corner read as an arc -- but only the contested arc of
// it is the front.
array<bool> gRayHot;
// DID THIS BEARING STOP AT THE MAP EDGE. A ray that walks off the map breaks out
// of the sample loop before it can meet anybody, so it records hot=false and both
// FrontLineSpots and FrontBuildSpots skip it -- the two failures are
// indistinguishable in gRayHot alone, and they need opposite answers.
array<bool> gRayWall;
// DID THIS BEARING MEET THE ENEMY. gRayHot answers "we hold ground out to here",
// which is true on every forward bearing around a base whether or not anybody is
// out there -- the ray simply runs to `march` and records its own edge. The two
// break out of the sample loop at the same place and were indistinguishable
// afterwards, so the DRAWN line traced our own territory boundary: a ring around
// the base, running off the map wherever the base sits near an edge (apexearth,
// watched at ourMid 575,5427 with R=651). Contested is the stricter question and
// the one the front is.
array<bool> gRayMet;
// Was ANY bearing contested this rebuild. Nothing contested means we cannot
// see them, not that they are absent, so placement must not tighten on it.
bool gAnyMet = false;

// THE RING'S OWN SAMPLE COUNT. The march below stops at the edge of our own
// territory instead of running to the map edge, so most rays break after a
// handful of samples and a finer step costs almost nothing -- while the step is
// what the radius is quantised to, and at 14 samples over half the map diagonal
// that was 366 elmos on a 16x12 map.
const int RING_SAMPLES = 28;
// THE RING'S TWO PASSES READ THE SAME CELLS. Pass 1 exists only to find the two
// peaks, and it walks exactly the samples pass 2 marches -- so the influence
// map was asked for every one of them twice a rebuild. Pass 1 keeps what it
// read here and pass 2 indexes it: same numbers, half the engine reads. Pass 2
// can never want a sample pass 1 did not take, because both guard on the same
// `d > march` and OnMap tests before reading.
array<float> gRingSA;   // ally influence at ray r, sample i-1
array<float> gRingSF;   // ...and enemy influence
array<float> gRingST;   // ...and builder threat
array<int>   gRingN;    // samples filled on ray r
array<float> gRingOwn;  // per ray: the furthest committed structure on its corridor
int   gRingOwnStamp = -1;
float gRingOwnHx = -1.f;
float gRingOwnHz = -1.f;
array<float> gRingCos;
array<float> gRingSin;
// TWO FIELDS, TWO BARS -- never their difference.
//
// GetNetInflAt is allyInfl - enemyInfl, both refilled to INFL_BASE = 0 every
// update and accumulated only from friendly units and KNOWN enemies
// (CInfluenceMap::Prepare/AddEnemy). So it reads exactly 0 over every cell
// nobody has been near, and a `< 0` test walks straight through no-man's-land to
// the first cell an enemy is standing in. Same trap Front::Scan documents: net
// influence reads 77 beside our base and exactly 0 on ground nobody has been
// near, and most of the map is the second kind.
//
// So ally and enemy are tested SEPARATELY, each against a share of its own peak
// over this same sample set. The two fields are not on one scale -- ally counts
// every armed unit the whole ally team owns, enemy counts only what we have
// seen -- so one absolute floor cannot serve both.
//
// The fractions are Front::TERRITORY_FRAC and Front::FOE_FRAC, restated rather
// than referenced: manager/military.as is included before manager/frontline.as
// (see main.as), so the Front:: namespace does not exist yet at this line and
// naming it is a `No matching symbol` that disables the whole variant.
const float RING_ALLY_FRAC  = 0.03f;
const float RING_ALLY_FLOOR = 1.0f;
const float RING_FOE_FRAC   = 0.10f;
const float RING_FOE_FLOOR  = 1.0f;
// How many rays stopped at a teammate's ground this rebuild -- the instrument
// for the sector split, so "the line is ours alone" is readable rather than
// assumed.
int gRaySector = 0;
float gRingAllyBar = RING_ALLY_FLOOR;
float gRingFoeBar  = RING_FOE_FLOOR;

// Per lane: the fraction along home->enemy at which that lane's influence
// crosses. Index 0 is the leftmost lane.
array<float> gFrontLane;
// How far out a BUILDER can actually work in each lane, as a fraction of the
// same axis. Not the same question as where the line is, and it is the one that
// decides whether a tower can exist: IBuilderTask::FindBuildSite searches with a
// CanReachAtSafe predicate, which rejects any cell whose builder threat is above
// THREAT_MIN, so an order past this point is refused by the engine's own site
// search and left queued with nobody on it.
//
// Threat does not time out. CMapManager::HostileInLOS keeps an enemy's threat
// until we have line of sight on where it was and it is gone, or it dies -- so
// this edge moves outward when the army takes ground, and not otherwise.
array<float> gFrontSafe;
int gFrontStamp = -1;
AIFloat3 gFrontFwd;      // home -> enemy, unnormalised (the axis' own length)
AIFloat3 gFrontSide;     // unit perpendicular
AIFloat3 gFrontHome;
bool gFrontValid = false;

void RebuildFront()
{
	// Economy-scaled cadence: the later the game, the more slowly the front
	// moves -- apexearth: "5-10s no big deal". Rich = 5s, else 1s.
	const int frontPeriod = (aiEconomyMgr.metal.income
			>= ai.GetTunable("apex_elect_rich_income", TUNE_ELECT_RICH_INCOME)) ? 150 : 30;
	if ((gFrontStamp >= 0) && (ai.frame - gFrontStamp < frontPeriod))
		return;
	gFrontStamp = ai.frame;
	gFrontValid = false;
	gFrontLane.resize(0);
	gFrontSafe.resize(0);

	if (!Builder::gHomeSet)
		return;
	const AIFloat3 home = TerritoryCentre();
	const AIFloat3 e = aiEnemyMgr.GetEnemyPos();
	if (!OnMap(e))
		return;
	AIFloat3 fwd = e - home;
	if (fwd.SqLength2D() < NEAR_ZERO)
		return;
	AIFloat3 side = AIFloat3(-fwd.z, 0.f, fwd.x);
	side.SafeNormalize2D();

	gFrontHome = home;
	gFrontFwd = fwd;
	gFrontSide = side;

	// Same bar for every lane and every sample, and GetTunable is frozen for the
	// game once read -- inside the loop it was a string lookup 13 x 14 times a
	// rebuild for a constant. RebuildRing already reads it once for the same
	// reason.
	const float laneBar = ai.GetTunable("apex_build_threat_bar", TUNE_BUILD_THREAT_BAR);
	const double _tLn = Perf::T0();
	for (int lane = -FRONT_LANES; lane <= FRONT_LANES; ++lane) {
		const AIFloat3 origin = home + side * (float(lane) * FrontLaneGap());
		float found = -1.f;
		float ours = -1.f;
		float safe = 0.f;
		for (int i = 1; i <= FRONT_SAMPLES; ++i) {
			const float t = FRONT_SCAN_END * float(i) / float(FRONT_SAMPLES);
			const AIFloat3 p = origin + fwd * t;
			if (!OnMap(p))
				break;
			// THE SAFE GROUND CLOSEST TO THE LINE: the FURTHEST workable sample,
			// not the first threatened one. The engine's own CanReachAtSafe tests
			// threat at the DESTINATION plus whether a path exists, not a clear
			// straight line, so stopping at the first threat wrongly collapsed
			// the whole lane onto the base whenever one raider sat close in.
			//
			// THE SAME BAR THE ENGINE USES: CanReachAtSafe tests
			// `GetBuilderThreatAt(pos) > THREAT_MIN` (1.0, util/Defines.h), and
			// the accessor has already subtracted THREAT_BASE, so testing `> 0`
			// instead put the safe edge one step from the base in every lane.
			if (ai.GetBuilderThreatAt(p) <= laneBar)
				safe = t;
			// EMPTY GROUND IS NOBODY'S, NOT THEIRS. GetNetInflAt is ally minus
			// enemy, so ground neither side has been near reads exactly 0, and
			// testing `<= 0` called the first such sample the crossing -- putting
			// the front one step from our own base on any flank not yet walked.
			const float inf = ai.GetNetInflAt(p);
			if (inf > 0.f) {
				ours = t;      // still ours out to here
				continue;
			}
			if (inf < 0.f) {
				found = t;     // theirs: this is the crossing
				break;
			}
			// exactly 0: no man's land, keep walking
		}
		// Held all the way to the last positive sample and never met them: the line
		// is out past there, not back at the base.
		if ((found < 0.f) && (ours > 0.5f))
			found = ours;
		// A lane with no crossing is one we hold all the way, or one nobody has
		// contested. Halfway is the start-box answer and is right for both.
		gFrontLane.insertLast((found < 0.f) ? 0.5f : found);
		gFrontSafe.insertLast(safe);
	}
	Perf::Add("fr.lanes", _tLn);
	const double _tRg = Perf::T0();
	RebuildRing(home);
	Perf::Add("fr.ring", _tRg);
	gFrontValid = true;
	FrontDiag();
}

// One ray per bearing, each finding THE EDGE OF WHAT WE HOLD on that bearing.
//
// It used to walk until GetNetInflAt went negative, which is not the edge of
// our territory -- it is the first cell where a KNOWN enemy outweighs us, i.e.
// their own front rank. Every ray therefore crossed the whole of no-man's-land
// (net influence is exactly 0 there) and stopped on top of them, sending
// constructors to build too far forward and get killed doing it.
//
// Now: our own influence says how far out we hold, theirs says where they are,
// each against its own bar, and the radius is the last sample that was ours and
// free of them. That answer needs no vision at all -- it exists from minute one
// and it does not move when a raid drives past -- which is the same reason
// Front:: settled on the outer edge of our own influence region after three
// definitions that needed to see the enemy died against measurement.
// The furthest committed structure on each bearing's corridor (within 900
// elmo of the ray, ahead of home). One pass over the ledger, each row tested
// against the few rays whose corridor can hold it -- the angular window is a
// superset of the corridor test, which is then applied unchanged -- and only
// when the ledger or home has moved. Walked per ray per rebuild, this was
// rays x rows every second.
void RingOwnFill(const AIFloat3& in home)
{
	if (gRingOwn.length() != uint(FRONT_RAYS)) {
		gRingOwn.resize(uint(FRONT_RAYS));
		gRingCos.resize(uint(FRONT_RAYS));
		gRingSin.resize(uint(FRONT_RAYS));
		for (int r = 0; r < FRONT_RAYS; ++r) {
			const float ang = 6.2831853f * float(r) / float(FRONT_RAYS);
			gRingCos[uint(r)] = cos(ang);
			gRingSin[uint(r)] = sin(ang);
		}
	}
	if ((gRingOwnStamp == Market::gComStamp) && (gRingOwnHx == home.x) && (gRingOwnHz == home.z))
		return;
	gRingOwnStamp = Market::gComStamp;
	gRingOwnHx = home.x;
	gRingOwnHz = home.z;
	for (int r = 0; r < FRONT_RAYS; ++r)
		gRingOwn[uint(r)] = 0.f;
	const float rayStep = 6.2831853f / float(FRONT_RAYS);
	const uint n = Market::ComLen();
	for (uint hi = 0; hi < n; ++hi) {
		const int hd = Market::gComDef[hi];
		if (!Catalog::ValidId(hd) || Catalog::gMobile[hd]
			|| !OnMap(Market::gComPos[hi]))
			continue;
		const float rx = Market::gComPos[hi].x - home.x;
		const float rz = Market::gComPos[hi].z - home.z;
		const float rho = sqrt(rx * rx + rz * rz);
		if (rho <= 0.f)
			continue;   // along is 0 on every ray
		const float w = (rho > 900.f) ? asin(900.f / rho) : 1.5707964f;
		const float th = atan2(rz, rx);
		const int r0 = int(floor((th - w) / rayStep)) - 1;
		const int r1 = int(ceil((th + w) / rayStep)) + 1;
		for (int rr = r0; rr <= r1; ++rr) {
			const uint r = uint(((rr % FRONT_RAYS) + FRONT_RAYS) % FRONT_RAYS);
			const float along = rx * gRingCos[r] + rz * gRingSin[r];
			if (along <= 0.f)
				continue;   // behind us on this bearing
			const float lat = rx * gRingSin[r] - rz * gRingCos[r];
			if ((lat > 900.f) || (lat < -900.f))
				continue;   // not on this bearing's corridor
			if (along > gRingOwn[r])
				gRingOwn[r] = along;
		}
	}
}

void RebuildRing(const AIFloat3& in home)
{
	gRayR.resize(0);
	gRaySafe.resize(0);
	gRayHot.resize(0);
	gRayWall.resize(0);
	gRayMet.resize(0);
	gRaySector = 0;
	const float w = float(AiTerrainWidth());
	const float h = float(AiTerrainHeight());
	const float reach = sqrt(w * w + h * h) * 0.5f;   // half the map diagonal
	const float step = reach / float(RING_SAMPLES);
	const float bar = ai.GetTunable("apex_build_threat_bar", TUNE_BUILD_THREAT_BAR);

	// NOTHING BEHIND US IS FRONT.
	//
	// Firmer than asking the influence map, which answers about this tick: a
	// bearing pointing away from every enemy cannot become the front line
	// because there is nobody back there to make one. Excluding the rear half
	// outright also stops the ring closing on itself, which is what wrapped the
	// drawn line around our own half of the map.
	//
	// apex_front_rear_arc=1 restores the full ring for a genuinely surrounded
	// base.
	const bool rearToo = ai.GetTunable("apex_front_rear_arc", TUNE_FRONT_REAR_ARC) > 0.f;
	AIFloat3 toEnemy = aiEnemyMgr.GetEnemyPos() - home;
	const bool haveBearing = toEnemy.SqLength2D() > NEAR_ZERO;
	const float sep = haveBearing ? sqrt(toEnemy.SqLength2D()) : 0.f;
	if (haveBearing)
		toEnemy.SafeNormalize2D();

	// AND NOT PAST THE ENEMY. GetAllyInflAt is ally-WIDE, so a bearing running
	// sideways along the team's holdings never leaves friendly influence and would
	// report a radius of half the map -- ground an ally holds, drawn as our front
	// and offered as our build line. BorderPos in this same file already states
	// the rule this reuses: "A site further from home than the enemy centroid is
	// not ours to hold -- that is an ally's ground on the far side of the map."
	float march = reach;
	if (haveBearing && (sep > step) && (sep < march))
		march = sep;

	// PASS 1: the two peaks, over exactly the samples pass 2 will march. Every
	// read is OnMap-guarded -- CInfluenceMap::PosToXZ does no bounds check at all
	// (`x = (int)pos.x / squareSize`) and indexes enemyInfl[z * width + x] off the
	// raw position, the same unchecked pattern that made GetBuilderThreatAt kill
	// the engine at frame 3.
	float maxAlly = 0.f;
	float maxFoe = 0.f;
	if (gRingSA.length() != uint(FRONT_RAYS * RING_SAMPLES)) {
		gRingSA.resize(uint(FRONT_RAYS * RING_SAMPLES));
		gRingSF.resize(uint(FRONT_RAYS * RING_SAMPLES));
		gRingST.resize(uint(FRONT_RAYS * RING_SAMPLES));
		gRingN.resize(uint(FRONT_RAYS));
	}
	// One binding call per ray fills the three reads for every sample: asked
	// per sample, the cost was the script-to-engine call, not the read.
	for (int r = 0; r < FRONT_RAYS; ++r) {
		const float ang = 6.2831853f * float(r) / float(FRONT_RAYS);
		const AIFloat3 dir = AIFloat3(cos(ang), 0.f, sin(ang));
		gRingN[uint(r)] = 0;
		if (!rearToo && haveBearing
			&& ((dir.x * toEnemy.x + dir.z * toEnemy.z) <= 0.f))
			continue;
		float mA = 0.f;
		float mF = 0.f;
		gRingN[uint(r)] = ai.GetInflRay(home, dir, step, RING_SAMPLES, march,
				gRingSA, gRingSF, gRingST, r * RING_SAMPLES, mA, mF);
		if (mA > maxAlly) maxAlly = mA;
		if (mF > maxFoe) maxFoe = mF;
	}
	RingOwnFill(home);
	gRingAllyBar = maxAlly * RING_ALLY_FRAC;
	if (gRingAllyBar < RING_ALLY_FLOOR)
		gRingAllyBar = RING_ALLY_FLOOR;
	// NOTHING SEEN IS NOT NOTHING THERE. With maxFoe at 0 the bar sits on its
	// floor and no sample can ever reach it, so the ray falls through to the ally
	// test and answers "our territory ends here" -- a real measurement rather than
	// a guess about an enemy we have not found. That is the point of splitting the
	// two tests: a rear player, whose own influence map holds no enemy at all,
	// still gets a line instead of concluding there is no front.
	gRingFoeBar = maxFoe * RING_FOE_FRAC;
	if (gRingFoeBar < RING_FOE_FLOOR)
		gRingFoeBar = RING_FOE_FLOOR;

	// PASS 2: march.
	for (int r = 0; r < FRONT_RAYS; ++r) {
		const float ang = 6.2831853f * float(r) / float(FRONT_RAYS);
		const AIFloat3 dir = AIFloat3(cos(ang), 0.f, sin(ang));
		if (!rearToo && haveBearing
			&& ((dir.x * toEnemy.x + dir.z * toEnemy.z) <= 0.f))
		{
			gRayR.insertLast(reach);
			gRaySafe.insertLast(0.f);
			gRayHot.insertLast(false);
			gRayWall.insertLast(false);
			gRayMet.insertLast(false);
			continue;
		}
		float edge = 0.f;        // last sample that was still ours
		float safe = 0.f;
		bool met = false;        // did the ray break on THEM, or just run out
		float metAt = 0.f;       // ...and at what distance
		bool wall = false;       // did it run out of map
		const int rowS = r * RING_SAMPLES;
		const int nS = gRingN[uint(r)];
		for (int i = 1; i <= RING_SAMPLES; ++i) {
			const float d = step * float(i);
			if (d > march)
				break;
			if (i > nS) {   // the ray stopped short of march: it left the map
				wall = true;
				break;
			}
			// A TEAMMATE'S GROUND IS NOT OUR FRONT. GetAllyInflAt is ally-wide,
			// so a bearing running along the team's own band never leaves
			// friendly influence and marches until the enemy-centroid cap --
			// measured on Supreme Isthmus 8v8 (watch-isthmus-trbl, 26 min):
			// ring-diag r/sep max=0.98, front-diag max=1.15, i.e. a line drawn
			// past the enemy (apexearth, watching: "our line draws through the
			// middle of them"). The cap at `sep` was the band-aid for this and
			// the numbers above are it being hit, not a battlefield.
			//
			// Front::Mine is the split the perimeter already uses: a cell
			// belongs to the ally whose home is nearest it. In a 1v1, or
			// before any mate has published a home, it answers true and this
			// costs nothing.
			// (The sector split that used to live here is gone. It stopped a
			// ray the moment it crossed into a teammate's half, which emptied
			// the ring on a line-abreast team -- rays=0/24 -- and it was never
			// shown to help. Reverted 2026-09-02.)
			// THEM FIRST, so a cell they hold can never be recorded as ours. This
			// is also what keeps the line out of the battle itself: where both
			// fields are up, the last ground a builder can be sent to is the cell
			// BEFORE the one they are standing in.
			// THEIRS MEANS THEY ARE STRONGER HERE, NOT MERELY PRESENT.
			//
			// The bar is 10% of their peak influence, and enemy influence
			// bleeds over a unit's whole threat range -- so one scout within a
			// thousand elmos trips it, and every forward ray broke at its FIRST
			// sample. Measured: r/sep 0.03, a "front line" ninety elmos from
			// our own centre, which is why front defence had nowhere to stand
			// (apexearth: "I just want to see us make a frontline of turrets").
			//
			// Ground where our own influence still dominates is ours whoever is
			// standing on it. The ray stops where theirs actually wins.
			const float foeHere = gRingSF[uint(rowS + i - 1)];
			const float allyHere = gRingSA[uint(rowS + i - 1)];
			if ((foeHere >= gRingFoeBar) && (foeHere > allyHere)) {
				met = true;
				metAt = d;   // remember WHERE, so a first-sample contact is
				break;       // still a bearing we hold, not a discarded ray
			}
			if (allyHere < gRingAllyBar)
				break;   // our territory ended at the previous sample
			edge = d;
			if (gRingST[uint(rowS + i - 1)] <= bar)
				safe = d;
		}
		// A bearing we hold nothing on carries `reach`, not 0. OnBorder compares a
		// position against gRayR on its own bearing WITHOUT consulting gRayHot, so
		// a 0 here would make every position in that sector read "on the border" --
		// this is the same sentinel the rear arc above already uses.
		// A RAY THAT MEETS THEM AT THE FIRST SAMPLE IS THE MOST FRONT-LINE
		// BEARING THERE IS, AND WE WERE THROWING IT AWAY.
		//
		// `edge` is only recorded AFTER the enemy test passes, so a bearing
		// where their influence reaches within one step of our own centre
		// breaks with edge = 0, takes the `reach` sentinel, and reads hot =
		// false. Every ray can meet the enemy and not one be left hot, so
		// FrontBuildSpots has nothing to
		// offer and front-line defence was impossible however many other
		// gates were opened. The ring emptied itself exactly when the enemy
		// got close, which is precisely when the front line matters.
		//
		// Contact is not the absence of a front, it IS the front. A met ray
		// holds ground up to where we met them; with no clear sample behind
		// that, half the contact distance is the honest answer -- far enough
		// to be ours, short of where they are standing.
		if (met && (edge <= 0.f) && (metAt > 0.f))
			edge = metAt * 0.5f;
		// AND NEVER PAST THE GROUND WE ACTUALLY HOLD. Stopping only where the
		// enemy DOMINATES fixed the ring collapsing to our doorstep (r/sep
		// 0.03) and immediately overshot the other way -- ally influence is
		// team-wide, so a ray kept finding friendly ground almost all the way
		// to them: r/sep mean 0.86, max 0.99, a "front line" drawn on their
		// side of the map. Neither reading is a front.
		//
		// Our territory ends where our BUILDINGS end -- the same rule
		// Front::StampHeld settled on for the other territory field ("a
		// structure cannot walk, so a structure is what owning ground means").
		// The ray may reach one hold-radius past the furthest thing we own on
		// its bearing, and no further.
		{
			const float own = gRingOwn[uint(r)];
			const float cap = own + Front::HoldRadius();
			if ((own > 0.f) && (edge > cap))
				edge = cap;
		}
		gRayR.insertLast((edge > 0.f) ? edge : reach);
		gRaySafe.insertLast(safe);
		gRayHot.insertLast(edge > 0.f);
		gRayWall.insertLast(wall);
		gRayMet.insertLast(met);
	}

	// THE WALL IS PART OF THE LINE, NOT THE END OF IT. A bearing that ran out of
	// map records hot=false, and FrontLineSpots/FrontBuildSpots skip a cold
	// bearing outright -- so for a player sitting against the map edge the whole
	// sector between us and that wall emits no build point at all. It is also the
	// sector a raider hugs to get behind us.
	//
	// A wall bearing whose NEIGHBOUR met the enemy is the same front, ending at
	// the wall, so it adopts that classification. Seeded from copies so the
	// adoption cannot cascade round the ring in whichever direction the loop
	// happens to run.
	//
	// Its radius is then capped at that neighbour's: a ray that left the map at
	// long range carries the map's geometry, not the battlefield's, and would
	// otherwise place a point deeper than the front it is borrowing from.
	// It adopts the neighbour's SAFE EDGE as well as its radius. Under the older
	// rule a wall ray accumulated `safe` for every on-map sample before it broke;
	// `safe` is now only recorded inside our own territory, so a wall ray holding
	// none of its own would carry safe=0 and FrontLineSpots would drop it again
	// for a different reason. Where the borrowed point actually lands is still
	// re-checked by Builder::ThreatFor and FindBuildSiteNear before anything is
	// ordered there.
	array<bool> seed = gRayHot;
	array<float> seedR = gRayR;
	array<float> seedS = gRaySafe;
	array<bool> seedMet = gRayMet;
	for (uint i = 0; i < gRayHot.length(); ++i) {
		if (seed[i] || !gRayWall[i])
			continue;
		const uint prev = (i + gRayHot.length() - 1) % gRayHot.length();
		const uint next = (i + 1) % gRayHot.length();
		uint src = 0;
		bool haveSrc = false;
		if (seed[prev] && !gRayWall[prev]) {
			src = prev;
			haveSrc = true;
		}
		if (seed[next] && !gRayWall[next]
			&& (!haveSrc || (seedR[next] < seedR[src])))
		{
			src = next;
			haveSrc = true;
		}
		if (!haveSrc)
			continue;
		gRayHot[i] = true;
		// A front that ends AT the wall is still a front; a wall bearing whose
		// neighbour met nobody is just the edge of the world, and stays cold so
		// nothing draws a line along it.
		if (seedMet[src])
			gRayMet[i] = true;
		if (gRayR[i] > seedR[src])
			gRayR[i] = seedR[src];
		if (gRaySafe[i] <= 0.f)
			gRaySafe[i] = seedS[src];
		if (gRaySafe[i] > gRayR[i])
			gRaySafe[i] = gRayR[i];
	}

	gAnyMet = false;
	for (uint i = 0; i < gRayMet.length(); ++i) {
		if (gRayMet[i]) {
			gAnyMet = true;
			break;
		}
	}
}

// DOES THIS BEARING FACE THE FIGHT -- the question every front placement meant
// to ask. gRayHot only says we hold ground out that way, which is true all the
// way round a base, so the net layered turrets inward on all 24 bearings and
// most of them faced our own rear (apexearth: "so many turrets behind our
// base"). The front has WIDTH, so a bearing beside a contested one faces the
// same approach and counts.
//
// With nothing contested anywhere we are blind, not safe -- fall back to the
// held arc rather than emitting no line, which is the trap of keying a gate on
// visible enemies.
bool RayFacesFront(uint i)
{
	if ((i >= gRayHot.length()) || !gRayHot[i])
		return false;
	const uint n = gRayMet.length();
	if (!gAnyMet || (n == 0))
		return true;
	if ((i < n) && gRayMet[i])
		return true;
	return gRayMet[(i + n - 1) % n] || gRayMet[(i + 1) % n];
}

// Which ray a position falls on.
int RayOf(const AIFloat3& in pos)
{
	const float dx = pos.x - gFrontHome.x;
	const float dz = pos.z - gFrontHome.z;
	float ang = atan2(dz, dx);
	if (ang < 0.f)
		ang += 6.2831853f;
	int r = int(ang / 6.2831853f * float(FRONT_RAYS) + 0.5f);
	if (r >= FRONT_RAYS)
		r = 0;
	if (r < 0)
		r = 0;
	return r;
}

}  // namespace Military
