namespace Lattice {

//------------------------------------------------------------------------------
// THE BASE LATTICE, and the chain-explosion model that sets its strides.
//
// Every structure tiles on a lattice anchored to the base frame. A def's stride
// is its FOOTPRINT -- the only pitch on which two of them touch -- unless its
// own death explosion makes a flush pack a single-bomb loss, in which case the
// stride widens past the blast. Widened strides stay whole multiples of the
// footprint, so the gap they open is an exact number of footprint cells that
// other defs tile into: separation costs no ground, only company.
//
// C++ (CCircuitAI::SnapToBaseGrid) snaps every non-fixed placement onto these,
// so the model reaches stock task selection too, not just our own rules.
//------------------------------------------------------------------------------

const float CELL = 16.f;   // the engine's build square
// A def nothing can chain: either it does not explode, or the pack would have
// to be wiped by the enemy first. Also the clamp on ChainK, so the number
// stays printable.
const int CHAIN_IMMUNE = 99;

// Damage a structure of footprint `foot` cells takes from a death explosion
// `dist` elmos away, centre to centre. The engine measures to the target's
// COLLISION VOLUME surface, not its centre (GameHelper.cpp DoExplosionDamage),
// and its falloff divides by the rim rather than the radius --
// (R - d) / (R - d*edge) -- which is why the curve is far flatter than a
// linear one and why half-spacing buys almost nothing.
float BlastAt(int defId, float dist)
{
	const float r = Catalog::gBlastR[defId];
	const float base = Catalog::gBlastD[defId];
	if ((r <= 0.f) || (base <= 0.f))
		return 0.f;
	const float half = float(Catalog::gFootX[defId] > Catalog::gFootZ[defId]
			? Catalog::gFootX[defId] : Catalog::gFootZ[defId]) * (CELL * .5f);
	float d = dist - half;
	if (d < 0.f)
		d = 0.f;
	if (d > r)
		return 0.f;
	const float e = Catalog::gBlastE[defId];
	if ((e >= 1.f) || (d < 1.f))
		return base;
	return base * (r - d) / (r - d * e);
}

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

// How many neighbour deaths this def survives when packed flush. 1 means one
// loss takes the whole pack; a high number means the pack is chain-immune and
// should be tiled as tightly as the engine allows.
int ChainK(int defId)
{
	const float pitch = FootPitch(defId);
	const float hit = BlastAt(defId, pitch);
	if (hit <= 0.f)
		return CHAIN_IMMUNE;
	const float hp = Catalog::gHealth[defId];
	if (hp <= 0.f)
		return 1;
	int k = int(hp / hit);
	if (float(k) * hit < hp)
		++k;
	return (k < 1) ? 1 : ((k > CHAIN_IMMUNE) ? CHAIN_IMMUNE : k);
}

// Centre spacing at which the blast cannot reach a neighbour at all.
float Firebreak(int defId)
{
	const float r = Catalog::gBlastR[defId];
	if (r <= 0.f)
		return 0.f;
	const float half = float(Catalog::gFootX[defId] > Catalog::gFootZ[defId]
			? Catalog::gFootX[defId] : Catalog::gFootZ[defId]) * (CELL * .5f);
	return r + half;
}

array<int> gK;
array<float> gStride;

int KOf(int defId) { return (uint(defId) < gK.length()) ? gK[defId] : CHAIN_IMMUNE; }
float StrideOf(int defId) { return (uint(defId) < gStride.length()) ? gStride[defId] : CELL; }

void Init()
{
	const int n = Catalog::gDefCount + 1;
	gK.resize(n);
	gStride.resize(n);
	const int safeK = int(ai.GetTunable("apex_chain_safe_k", TUNE_CHAIN_SAFE_K));
	int widened = 0;
	for (int i = 1; i <= Catalog::gDefCount; ++i) {
		gK[i] = CHAIN_IMMUNE;
		gStride[i] = CELL;
		CCircuitDef@ cdef = Catalog::Def(i);
		if ((cdef is null) || Catalog::gMobile[i])
			continue;
		const float pitch = FootPitch(i);
		gStride[i] = pitch;
		gK[i] = ChainK(i);
		// A def that survives enough neighbour deaths cannot start a cascade
		// from a single loss, so it packs flush whatever its blast radius:
		// an attacker has to kill k of them before the k+1th dies for free.
		if (gK[i] < safeK) {
			const float fb = Firebreak(i);
			float steps = fb / pitch;
			int whole = int(steps);
			if (float(whole) * pitch < fb)
				++whole;
			if (whole < 1)
				whole = 1;
			gStride[i] = float(whole) * pitch;
			if (whole > 1)
				++widened;
		}
		cdef.SetLatticeStride(gStride[i], gStride[i]);
	}
	AiLog("apex: lattice built, safeK=" + safeK + " widened=" + widened);
	Report();
}

// DID IT ACTUALLY TILE? The one question the layout has to answer, and the one
// neither a placement count nor a base area can. Every finished structure is
// scored against the nearest standing kin of its own def: FLUSH means they are
// touching at the lattice pitch, APART means there is ground between them that
// nothing will ever use. Islands are counted separately -- a widened stride is
// meant to be apart, and must not read as a failure to pack.
array<AIFloat3> gSeen;
array<int> gSeenDef;
int gFlush = 0;
int gApart = 0;
int gIsle = 0;

void NotePlaced(int defId, const AIFloat3& in p)
{
	// ONLY WHAT THE FARM PLACES. Extractors sit on a spot, geothermals on a
	// vent, and towers and radar are sited by coverage -- all three are meant
	// to be apart, and scoring them reports the map's own spacing as a layout
	// failure. The lattice's job is the economy block.
	if (!OnMap(p) || Catalog::gMobile[defId]
		|| (Catalog::gExtractsM[defId] > 0.f) || Catalog::gNeedGeo[defId])
		return;
	if ((Catalog::gMakeE[defId] < 1.f) && (Catalog::gConvCapacity[defId] < 1.f)
		&& (Catalog::gStoreE[defId] < 1.f) && (Catalog::gStoreM[defId] < 1.f))
		return;
	const float pitch = FootPitch(defId);
	float best = -1.f;
	for (uint i = 0; i < gSeen.length(); ++i) {
		if (gSeenDef[i] != defId)
			continue;
		const float d = gSeen[i].distance2D(p);
		if ((best < 0.f) || (d < best))
			best = d;
	}
	if (best >= 0.f) {
		// Only a def whose stride was WIDENED is allowed to read as an island.
		// Where the stride is the footprint, anything past touching is a gap.
		const float stride = StrideOf(defId);
		// A DIAGONAL NEIGHBOUR IS STILL TOUCHING. On a square lattice the
		// nearest kin of a corner-packed block sits at pitch * sqrt(2), so an
		// orthogonal-only bar scores a perfectly tiled 2x2 as four failures.
		if (best <= pitch * 1.4143f + CELL)
			++gFlush;
		else if ((stride > pitch + CELL) && (best >= stride - CELL))
			++gIsle;
		else {
			++gApart;
			if (gApart <= 12) {
				AiLog("apex: tiling-miss " + Catalog::Def(defId).GetName()
					+ " nearest kin " + int(best) + " want " + int(pitch)
					+ " stride " + int(stride));
			}
		}
	}
	gSeen.insertLast(p);
	gSeenDef.insertLast(defId);
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
		+ " island=" + gIsle + " of " + n
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
			+ " hp=" + int(Catalog::gHealth[i])
			+ " blast=" + int(Catalog::gBlastD[i]) + "@" + int(Catalog::gBlastR[i])
			+ " k=" + gK[i]
			+ " pitch=" + int(FootPitch(i))
			+ " stride=" + int(gStride[i]));
	}
}

}  // namespace Lattice
