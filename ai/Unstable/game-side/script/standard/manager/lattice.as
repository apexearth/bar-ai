namespace Lattice {

//------------------------------------------------------------------------------
// THE BASE LATTICE -- one shared grid, and the four rules that lay a base out.
//
// apexearth 2026-08-25, rejecting a blast-radius-derived spacing model that
// pushed advanced fusions 768 elmos apart and converters one-by-one across the
// whole base: "Buildings which are not factories should prefer to be placed
// besides other buildings of the same type. On top, bottom, left, or right.
// Every once in a while, start a new location so they aren't all in one spot.
// Ensure there is enough room for big units to walk around. Prefer not to
// build units of differing types right next to each other."
//
// So the layout is not computed from what a building's death does. It is:
//   1. GROW  -- a new building goes orthogonally beside kin of its own def.
//   2. SEED  -- past a cluster's size, start a fresh cluster elsewhere.
//   3. AISLE -- clusters are parted by ground the biggest unit we field can
//               walk through.
//   4. SORT  -- a different def does not take a slot touching this cluster.
//
// Every def's stride is simply its FOOTPRINT, the only pitch on which two of
// them touch. C++ (CCircuitAI::SnapToBaseGrid) snaps every non-fixed placement
// onto that, so stock task selection lands on the same grid we do.
//------------------------------------------------------------------------------

const float CELL = 16.f;   // the engine's build square

// Onto a multiple of `pitch`, the same rounding C++ does in SnapToBaseGrid.
float Snap(float v, float pitch)
{
	if (pitch <= 0.f)
		return v;
	const float k = v / pitch;
	const int n = int((k >= 0.f) ? (k + .5f) : (k - .5f));
	return float(n) * pitch;
}

float FootPitch(int defId)
{
	const int f = (Catalog::gFootX[defId] > Catalog::gFootZ[defId])
			? Catalog::gFootX[defId] : Catalog::gFootZ[defId];
	return (f > 0) ? (float(f) * CELL) : CELL;
}

// AISLE: ground kept clear between two clusters, wide enough for the biggest
// thing we field to walk through rather than around. Derived from the widest
// mobile unit available to us, so a base that fields Korgoths leaves Korgoth-
// sized streets and a bot-only base does not waste the ground.
float gAisle = -1.f;
float AisleW()
{
	if (gAisle > 0.f)
		return gAisle;
	int widest = 0;
	for (int i = 1; i <= Catalog::gDefCount; ++i) {
		if (!Catalog::gMobile[i] || !Catalog::gAvailable[i] || Catalog::gFlyer[i])
			continue;
		const int f = (Catalog::gFootX[i] > Catalog::gFootZ[i])
				? Catalog::gFootX[i] : Catalog::gFootZ[i];
		if (f > widest)
			widest = f;
	}
	// Room to WALK, not just to fit: a lane exactly one hull wide is a lane
	// the pathfinder refuses under any crowding.
	gAisle = float(widest) * CELL * 2.f;
	if (gAisle < 64.f)
		gAisle = 64.f;
	return gAisle;
}

// CLUSTER: how many of one def stand together before the next starts somewhere
// else ("every once in a while, start a new location so they aren't all in one
// spot"). A count, deliberately -- what this bounds is how much of the base one
// raid or one blast reaches, and that is the same answer whatever the def costs.
int ClusterN()
{
	const int n = int(ai.GetTunable("apex_cluster_n", TUNE_CLUSTER_N));
	return (n < 1) ? 1 : n;
}

// Cells along one side of a full cluster: square, so a cluster is a block the
// crew works from one place instead of a line it walks end to end.
int ClusterSide()
{
	int b = int(sqrt(float(ClusterN())));
	return (b < 1) ? 1 : b;
}

array<float> gStride;

float StrideOf(int defId) { return (uint(defId) < gStride.length()) ? gStride[defId] : CELL; }

void Init()
{
	const int n = Catalog::gDefCount + 1;
	gStride.resize(n);
	for (int i = 1; i <= Catalog::gDefCount; ++i) {
		gStride[i] = CELL;
		CCircuitDef@ cdef = Catalog::Def(i);
		if ((cdef is null) || Catalog::gMobile[i])
			continue;
		gStride[i] = FootPitch(i);
		cdef.SetLatticeStride(gStride[i], gStride[i]);
	}
	AiLog("apex: lattice built, cluster=" + ClusterN()
		+ " side=" + ClusterSide() + " aisle=" + int(AisleW()));
	Report();
}

// DID IT ACTUALLY TILE? The one question the layout has to answer, and the one
// neither a placement count nor a base area can. Every finished structure is
// scored against the nearest standing kin of its own def: FLUSH means they are
// touching at the lattice pitch, APART means there is ground between them that
// nothing will ever use. Islands are counted separately -- a widened stride is
// meant to be apart, and must not read as a failure to pack.
// THE STRUCTURE REGISTER: what stands where, so a placement can ask what is
// already beside a slot without walking every unit we own. Ids are kept so
// death prunes it -- a stale entry is ground the layout would refuse forever.
array<AIFloat3> gSeen;
array<int> gSeenDef;
array<Id> gSeenId;
int gFlush = 0;
int gApart = 0;
int gIsle = 0;

// Ground between p and the nearest structure that is NOT this def. Rule 4:
// "prefer not to build units of differing types right next to each other".
// Negative when nothing foreign stands anywhere near.
float ForeignGap(int defId, const AIFloat3& in p)
{
	float best = -1.f;
	for (uint i = 0; i < gSeen.length(); ++i) {
		if (gSeenDef[i] == defId)
			continue;
		const float d = gSeen[i].distance2D(p);
		if ((best < 0.f) || (d < best))
			best = d;
	}
	return best;
}

void NoteDead(Id id)
{
	for (uint i = 0; i < gSeenId.length(); ++i) {
		if (gSeenId[i] == id) {
			gSeen.removeAt(i);
			gSeenDef.removeAt(i);
			gSeenId.removeAt(i);
			return;
		}
	}
}

void NotePlaced(int defId, const AIFloat3& in p, Id id)
{
	// Extractors sit on a spot and geothermals on a vent -- neither chose its
	// ground, so neither belongs in a register the layout rules read.
	if (!OnMap(p) || Catalog::gMobile[defId]
		|| (Catalog::gExtractsM[defId] > 0.f) || Catalog::gNeedGeo[defId])
		return;
	gSeen.insertLast(p);
	gSeenDef.insertLast(defId);
	gSeenId.insertLast(id);
	// ONLY WHAT THE FARM PLACES IS SCORED. Towers and radar are sited by
	// coverage and are meant to be apart; scoring them reports the map's own
	// spacing as a layout failure. The tiling report is about the economy block.
	if ((Catalog::gMakeE[defId] < 1.f) && (Catalog::gConvCapacity[defId] < 1.f)
		&& (Catalog::gStoreE[defId] < 1.f) && (Catalog::gStoreM[defId] < 1.f))
		return;
	const float pitch = FootPitch(defId);
	float best = -1.f;
	for (uint i = 0; i < gSeen.length(); ++i) {
		if ((gSeenDef[i] != defId) || (gSeen[i].distance2D(p) < 1.f))
			continue;   // skip the entry just made for p itself
		const float d = gSeen[i].distance2D(p);
		if ((best < 0.f) || (d < best))
			best = d;
	}
	if (best >= 0.f) {
		// AN AISLE IS NOT A GAP. Ground at least an aisle wide is the street
		// between two clusters and is meant to be there; anything short of it
		// is ground nothing will ever build on and nothing can walk down.
		// A DIAGONAL NEIGHBOUR IS STILL TOUCHING. On a square lattice the
		// nearest kin of a corner-packed block sits at pitch * sqrt(2), so an
		// orthogonal-only bar scores a perfectly tiled 2x2 as four failures.
		if (best <= pitch * 1.4143f + CELL)
			++gFlush;
		else if (best >= AisleW())
			++gIsle;
		else {
			++gApart;
			if (gApart <= 12) {
				AiLog("apex: tiling-miss " + Catalog::Def(defId).GetName()
					+ " nearest kin " + int(best) + " want " + int(pitch)
					+ " aisle " + int(AisleW()));
			}
		}
	}
}

int gNextLog = 0;
void Update()
{
	if (ai.frame < gNextLog)
		return;
	gNextLog = ai.frame + 60 * SECOND;
	const int n = gFlush + gApart + gIsle;
	if (n <= 0)
		return;
	AiLog("apex: tiling flush=" + gFlush + " apart=" + gApart
		+ " cluster=" + gIsle + " of " + n
		+ " (" + int(100.f * float(gFlush) / float(n)) + "% touching)");
}

// One line per interesting def, so the model can be read off a log instead of
// inferred from where buildings ended up.
void Report()
{
	for (int i = 1; i <= Catalog::gDefCount; ++i) {
		if (Catalog::gMobile[i])
			continue;
		if ((Catalog::gMakeE[i] < 1.f) && (Catalog::gConvCapacity[i] < 1.f)
			&& (Catalog::gStoreE[i] < 1.f))
			continue;
		AiLog("apex: lattice " + Catalog::Def(i).GetName()
			+ " foot=" + Catalog::gFootX[i] + "x" + Catalog::gFootZ[i]
			+ " pitch=" + int(FootPitch(i)));
	}
}

}  // namespace Lattice
