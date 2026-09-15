namespace Market {

//------------------------------------------------------------------------------
// THE PROTECTION FIELD: what we own, what guards it, and where a guard could go.
//
// One rebuild per apex_protect_field_s of game time, read by every defence
// price. It exists for two reasons.
//
// FIRST, WHAT WE DEFEND. The stake used to be mexes, structures over 1200
// metal, and energy generators -- so a lab, a nano, a converter or a radar was
// worth exactly zero to defend (apexearth: "we should be interested in
// defending any/all buildings that we have"). ai.GetOwnStructsNear with no
// radius is the engine's own list of every standing structure of ours.
//
// SECOND, WHERE. The old candidate sites were a ring of radius
// (base extent + turret range) about the metal centroid, plus polar rings
// layered inward around home -- two circles about the start position, which is
// what "our base defense only builds in a circle around where we started"
// looks like from the inside. Guard sites are now derived FROM the buildings:
// value-weighted cluster centres on a grid pitched at the candidate turret's own
// reach, so posts appear where our metal actually stands and nowhere else.
//
// Protection is excluded from the stake by the same law census.as states for
// gProtM: defence must never be its own reason to exist.
//------------------------------------------------------------------------------

array<AIFloat3> gPfPos;     // every standing asset of ours worth defending
array<float>    gPfWorth;   // ...and what losing it costs, in metal
array<bool>     gPfIsMex;   // ledger extractors: stream worth, not a building
float           gPfTotal = 0.f;
// Build cells our own structures stand on, every class of them. The rim below
// gives the base's AREA; this gives how much of it is used, and the ratio is
// the only honest answer to "is there room?" -- which SpaceRentM cannot give,
// because it prices ground by the turret cover over it and reads ~0 in a base
// with few turrets (apexearth 2026-08-27: "we have wind, advanced solar, and
// T1 converters all over the place not being reclaimed... we have no space").
float           gPfCells = 0.f;
int             gPfAt = -999999;

// WHICH ASSET A SLOT IS, so a cache may be keyed to the asset and not to a
// position in an array. The field is refilled from an engine query every two
// seconds, and the engine decides the order -- so index i meant a different
// building from one pass to the next, and every index-parallel cache
// downstream was silently attached to the wrong asset (ISSUES.md, gPostReq).
// gPfKey is the unit id for a structure and -(ledger index + 1) for an
// extractor slot; gPfStamp changes ONLY when the SET of keys changes, so a
// downstream cache that stored the stamp knows its indices still line up.
array<int> gPfKey;
int        gPfStamp = 0;

// Towers, flattened out of gProtPos[PROT_DEF] with their reach and kill power
// resolved once instead of per candidate site per def per builder.
array<AIFloat3> gPfTwPos;
array<float>    gPfTwReach;
array<float>    gPfTwKill;
// WHAT A COVER READING DEPENDS ON. gPfStamp cannot serve as the validity token
// for a cached PfCoverPoint: defence is excluded from gPfPos above, so a turret
// finishing or dying never moves it. This does -- it changes exactly when the
// three arrays above do, and they are read-only between rebuilds.
int gPfTwRev = 0;

//------------------------------------------------------------------------------
// THE RIM: the star-shaped hull of our own buildings.
//
// apexearth: "I still see us making a lot of defenses just around our starting
// position... Create a perimeter of defenses around our base. As our base
// grows, reclaim old defenses as needed and extend defense outwards."
//
// The cluster centroids below put a post in the MIDDLE of each blob of our
// metal, and the densest blob is always the spawn. The rim is the other half:
// the furthest thing we own on each bearing from the worth-weighted centre of
// the footprint. Nothing is chosen by hand -- gPfPos is rebuilt from
// GetOwnStructsNear every couple of seconds, so a new mex out to one side
// pushes that bearing's rim out on the next rebuild, and the perimeter grows
// with the base for free.
const int PF_RAYS = 24;
AIFloat3     gPfMid;
array<float> gPfRimR;
bool         gPfRimOk = false;

int PfRayOf(const AIFloat3& in p)
{
	const float dx = p.x - gPfMid.x;
	const float dz = p.z - gPfMid.z;
	float a = atan2(dz, dx);
	if (a < 0.f)
		a += 6.2831853f;
	int b = int(a / (6.2831853f / float(PF_RAYS)));
	if (b < 0)
		b = 0;
	if (b >= PF_RAYS)
		b = PF_RAYS - 1;
	return b;
}

// Rim radius on this position's own bearing.
float PfRimAt(const AIFloat3& in p)
{
	if (!gPfRimOk)
		return 0.f;
	return gPfRimR[PfRayOf(p)];
}

// How far OUTSIDE the perimeter this position is. Negative is inside; the
// magnitude is how deep.
float PfRimDist(const AIFloat3& in p)
{
	if (!gPfRimOk)
		return 0.f;
	return p.distance2D(gPfMid) - gPfRimR[PfRayOf(p)];
}

// The base's own footprint in build cells, from the measured rim: a fan of
// PF_RAYS wedges about the asset centroid.
float PfBaseCells()
{
	if (!gPfRimOk)
		return 0.f;
	float area = 0.f;
	for (int b = 0; b < PF_RAYS; ++b)
		area += (3.14159f / float(PF_RAYS)) * gPfRimR[b] * gPfRimR[b];
	return area / 256.f;   // 16-elmo build cells
}

// How full the base is, 0..1. Ground is only worth freeing when it is scarce,
// so every scarcity price is scaled by this and vanishes on an empty map.
float PfCrowd()
{
	const float cells = PfBaseCells();
	if (cells <= 1.f)
		return 0.f;
	const float f = gPfCells / cells;
	return (f > 1.f) ? 1.f : f;
}

// What one build cell of our base is worth, in metal of standing assets. The
// price of the room an obsolete building is sitting on.
// ROOM IS LOCAL. PfCrowd divides our footprint by the area inside the rim, and
// the rim grows with every outlying claim -- so the measure FALLS as the base
// fills: 0.06 at minute 2 and 0.01 from minute 7 on, in a game where he could
// see we had no room ("we're squeezed by the enemy and don't have enough room
// so we really shouldn't be making stuff like this"). What a placement
// competes for is the ground one gun covers, right here.
AIFloat3 gPfCrowdAtP;
float    gPfCrowdAtR = 0.f;
float    gPfCrowdAtV = 0.f;
int      gPfCrowdAtF = -999999;

float PfCrowdAt(const AIFloat3& in pos, float r)
{
	if ((r < 16.f) || !OnMap(pos))
		return PfCrowd();
	if ((gPfCrowdAtF == ai.frame) && (gPfCrowdAtR == r)
		&& (gPfCrowdAtP.distance2D(pos) < 16.f))
		return gPfCrowdAtV;
	const float cells = 3.14159f * r * r / 256.f;
	if (cells <= 1.f)
		return PfCrowd();
	float occ = 0.f;
	array<CCircuitUnit@>@ st = ai.GetOwnStructsNear(pos, r);
	for (uint i = 0; i < st.length(); ++i) {
		CCircuitUnit@ u = st[i];
		if ((u is null) || (u.circuitDef is null))
			continue;
		const int d = int(u.circuitDef.id);
		occ += float((Catalog::gAreaCells[d] > 0) ? Catalog::gAreaCells[d] : 1);
	}
	float f = occ / cells;
	if (f > 1.f)
		f = 1.f;
	gPfCrowdAtF = ai.frame;
	gPfCrowdAtP = pos;
	gPfCrowdAtR = r;
	gPfCrowdAtV = f;
	return f;
}

float PfMetalPerCell()
{
	return (gPfCells > 1.f) ? (gPfTotal / gPfCells) : 0.f;
}

float PfHorizon()
{
	const float h = ai.GetTunable("apex_stake_horizon_s", TUNE_STAKE_HORIZON_S);
	return (h > 1.f) ? h : 300.f;
}

//------------------------------------------------------------------------------
// WHAT A TURRET IS WORTH AS COVER: its killing power, not its price tag.
//
// Cover was summed as costM * apex_def_trade, which makes every turret in the
// game identically strong per metal by construction -- ten Guards read exactly
// as one Bulwark. Measured off the engine's own threat numbers that is false in
// both directions: corhllt delivers 0.103 surface threat per metal and corpun
// delivers 0.013, an eight-fold difference the auction could not see, and we
// bought 88 Agitators in 54 games.
//
// Reported in LIGHT-TOWER METAL so the number stays in the same currency as the
// wave it is compared against: a tower's cover is the metal of light towers it
// takes to kill as fast as it does.
//------------------------------------------------------------------------------
// WHAT A TURRET OUTRANGES, as a share of everything that can walk at it.
//
// Range's value is not smooth. apexearth on why the Beamer is the T1.5 pick:
// "It can outrange rocket bots, has great dps, and is still affordable" -- and
// the margin is FIVE elmos (Beamer 480, Rocko/Storm 475), while the Sentry at
// 430 loses to the same bot by 45. That is the difference between firing for
// free and being fired on for free, and to an area term it is 18% of covered
// ground. So the share of the attacker set a def outranges enters the kill
// power directly, where a step in range makes a step in value.
//
// The attacker set is our OWN mobile non-builder armed defs -- the same
// symmetric expectation PfAlphaPerMetal and PfAlphaRef already stand on,
// because nothing enumerates enemy defs and their unit table is ours mirrored.
array<float> gPfFoeRange;

void PfFoeRangeBuild()
{
	if (gPfFoeRange.length() > 0)
		return;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!Catalog::gMobile[d] || Catalog::gBuilder[d])
			continue;
		if ((Catalog::gMaxRange[d] <= 1.f) || (Catalog::gPower[d] <= 0.f))
			continue;
		gPfFoeRange.insertLast(Catalog::gMaxRange[d]);
	}
	gPfFoeRange.sortAsc();
	// The set is only as good as what Catalog holds, so it says so once:
	// a diluted or tiny set makes the outrange term meaningless rather than
	// wrong, and that is invisible from the price alone.
	const uint n = gPfFoeRange.length();
	if (n > 0) {
		AiLog(Factory::T() + "apex: outrange set n=" + n
			+ " p10=" + int(gPfFoeRange[n / 10])
			+ " p50=" + int(gPfFoeRange[n / 2])
			+ " p90=" + int(gPfFoeRange[(n * 9) / 10])
			+ " hpPerM=" + formatFloat(PfHpPerMetal(), "", 0, 2));
	}
}

float PfOutrangedFrac(int d)
{
	PfFoeRangeBuild();
	const uint n = gPfFoeRange.length();
	if (n == 0)
		return 0.f;
	const float r = Catalog::gMaxRange[d];
	uint under = 0;
	for (uint i = 0; i < n; ++i) {
		if (gPfFoeRange[i] < r)
			++under;
		else
			break;   // sorted
	}
	return float(under) / float(n);
}

// WHAT THE PRICE ACTUALLY USED, per def, stamped as it is computed.
//
// A decomposition log that recomputes its own terms can print a number the
// auction never saw: the first version printed this branch's dps and reference
// while the price had taken the engine-threat branch, so both read 0 and a zero
// in a product of multipliers reads as "this term annihilated it". -1 means the
// active branch did not use the term at all, and is printed as n/a.
array<float> gPkDps;     // surface DPS, linear branch only
array<float> gPkOutr;    // outrange lift, linear branch only
array<float> gPkBase;    // the damage figure the branch divided by the reference
array<float> gPkRef;     // ...and that reference
array<float> gPkDur;     // durability weight, -1 when apex_def_alpha_w is off
array<float> gPkTrade;
array<float> gPkOut;     // the value returned
array<int> gPkLin;       // 1 dps branch, 0 engine-threat branch, -1 never priced

void PkEnsure(int d)
{
	uint n = uint(Catalog::gDefCount + 1);
	if (uint(d) + 1 > n)
		n = uint(d) + 1;
	const uint had = gPkOut.length();
	if (had >= n)
		return;
	gPkDps.resize(n);  gPkOutr.resize(n);  gPkBase.resize(n);
	gPkRef.resize(n);  gPkDur.resize(n);   gPkTrade.resize(n);
	gPkOut.resize(n);  gPkLin.resize(n);
	for (uint q = had; q < n; ++q)
		gPkLin[q] = -1;
}

// A turret's kill power BEFORE it is denominated in light-tower metal: damage
// rate, lifted by the share of attackers it can hit first. Bounded at
// (1 + apex_def_outrange) so a long gun with no damage cannot buy its way up
// on reach alone -- which is the whole complaint against the Gauntlet.
float PfKillRaw(int d)
{
	const float w = ai.GetTunable("apex_def_outrange", TUNE_DEF_OUTRANGE);
	float m = PfSurfDps(d);
	PkEnsure(d);
	gPkDps[d] = m;
	gPkOutr[d] = 1.f;
	if (w > 0.f) {
		gPkOutr[d] = 1.f + w * PfOutrangedFrac(d);
		m *= gPkOutr[d];
	}
	return m;
}

// HIT POINTS PER METAL of what walks at us, so a damage rate can be converted
// into the metal of attackers it destroys. Median over the same set, for the
// same reason.
float gPfHpPerM = -1.f;

float PfHpPerMetal()
{
	if (gPfHpPerM >= 0.f)
		return gPfHpPerM;
	array<float> r;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!Catalog::gMobile[d] || Catalog::gBuilder[d])
			continue;
		if ((Catalog::gHealth[d] <= 0.f) || (Catalog::gCostM[d] <= 1.f))
			continue;
		r.insertLast(Catalog::gHealth[d] / Catalog::gCostM[d]);
	}
	if (r.length() == 0) {
		gPfHpPerM = 0.f;
		return gPfHpPerM;
	}
	r.sortAsc();
	gPfHpPerM = r[r.length() / 2];
	return gPfHpPerM;
}

// THE METAL A TURRET CAN ACTUALLY KILL in the window an exposed asset is
// expected to survive. A post's stake is everything inside its own reach
// (PfStakeIn buckets at the candidate's range), so a 1220-elmo gun is credited
// with 6.5x a 480-elmo gun's economy -- which would be right if it defended
// all of it at once, and it shoots one thing at a time (apexearth: "So we
// value range a bit too generously"). Damage rate over the horizon, converted
// through the attacker set's hit points per metal, is that ceiling. Negative
// means no ceiling.
float PfKillCapM(int d)
{
	if (ai.GetTunable("apex_def_kill_cap", TUNE_DEF_KILL_CAP) <= 0.f)
		return -1.f;
	const float hpm = PfHpPerMetal();
	const float h = ai.GetTunable("apex_exposed_loss_s", TUNE_EXPOSED_LOSS_S);
	if ((hpm <= 0.f) || (h <= 1.f))
		return -1.f;
	return PfSurfDps(d) * h / hpm;
}

float gPfKillRef = -1.f;   // surface DPS per metal of the faction's light tower
float gPfKillRefT = -1.f;  // ...and its surface THREAT per metal, for the A/B

float PfKillRef()
{
	if (gPfKillRef > 0.f)
		return gPfKillRef;
	CCircuitDef@ light = SideDef3("armllt", "corllt", "leglht");
	if (light !is null) {
		const int ld = int(light.id);
		const float dps = PfKillRaw(ld);
		if ((dps > 0.f) && (Catalog::gCostM[ld] > 0.f))
			gPfKillRef = dps / Catalog::gCostM[ld];
	}
	if (gPfKillRef <= 0.f)
		gPfKillRef = 2.8f;   // the measured light-tower figure, if the def is missing
	return gPfKillRef;
}

// The engine-threat reference the linear term replaced, kept so
// apex_def_dps_linear=0 restores the previous pricing exactly.
float PfKillRefT()
{
	if (gPfKillRefT > 0.f)
		return gPfKillRefT;
	CCircuitDef@ light = SideDef3("armllt", "corllt", "leglht");
	if (light !is null) {
		const int ld = int(light.id);
		if ((Catalog::gSurfT[ld] > 0.f) && (Catalog::gCostM[ld] > 0.f))
			gPfKillRefT = Catalog::gSurfT[ld] / Catalog::gCostM[ld];
	}
	if (gPfKillRefT <= 0.f)
		gPfKillRefT = 0.08f;
	return gPfKillRefT;
}

//------------------------------------------------------------------------------
// A TURRET ONLY SHOOTS WHILE IT IS ALIVE.
//
// Threat per metal alone still cannot tell a Twin Guard from a Bulwark -- 0.103
// against 0.082, so the cheap tower wins every auction and the T3 guns are
// never reachable on merit. The term it is missing is durability: 1,670 hit
// points against 9,400. Against a raider that difference does not matter and
// the cheap tower is correctly the better buy; against something whose alpha
// erases a Twin Guard before it fires twice, twelve of them are not one
// Bulwark. That is the whole of "the T3 defences are by far the best late game
// defence" and no per-metal ratio can express it.
//
// The reference blow is DERIVED, not chosen: their best mobile unit's cost
// (ai.GetEnemyMaxMobileCostM) converted through our own unit table's median
// alpha-per-metal. So it is near zero while they field raiders, and it is a
// Korgoth's punch once they field one -- the weight emerges from the game
// rather than from a threshold anybody picked.
//------------------------------------------------------------------------------
float gPfAlphaPerM = -1.f;

float PfAlphaPerMetal()
{
	if (gPfAlphaPerM >= 0.f)
		return gPfAlphaPerM;
	array<float> r;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!Catalog::gMobile[d] || Catalog::gBuilder[d])
			continue;
		if ((Catalog::gAlpha[d] <= 0.f) || (Catalog::gCostM[d] <= 1.f))
			continue;
		r.insertLast(Catalog::gAlpha[d] / Catalog::gCostM[d]);
	}
	if (r.length() == 0) {
		gPfAlphaPerM = 0.f;
		return gPfAlphaPerM;
	}
	r.sortAsc();
	gPfAlphaPerM = r[r.length() / 2];
	return gPfAlphaPerM;
}

// A LOS READING IS NOT A THREAT MODEL. GetEnemyMaxMobileCostM is the costliest
// enemy mobile currently VISIBLE, and it was measured bouncing between 0, 26
// and 120 metal across whole games -- whichever raider happened to be on
// screen. So the reference blow was ~0, hp/(hp+a) read ~1.0 for every turret,
// and the durability term above -- the entire reason a Bulwark is not twelve
// Beamers -- was inert. The auction fell back to threat-per-metal, where the
// cheap tower wins by construction, which is why the big guns were never
// bought and why a Juggernaut walks in (apexearth: "we lost because we
// couldn't stop a Juggernaut fast enough").
//
// Two corrections, both from quantities this AI already owns:
//
// A HIGH-WATER MARK, because a Korgoth seen once means they own a gantry and
// that does not go away when it leaves our line of sight. Nothing about their
// capability gets cheaper.
//
// ...and OUR OWN best buildable mobile as the floor: the same symmetric
// expectation ArmyTarget and DefenceTarget already use (they had our start and
// our minutes). This is the term that matters for his complaint, because it
// needs no contact -- the big gun can be STANDING when the Juggernaut arrives
// instead of being priced correctly just after it lands.
float gPfAlphaHi = 0.f;

float PfAlphaRef()
{
	float best = ai.GetEnemyMaxMobileCostM();
	const float mine = OwnedBestMobileCostM();
	if (mine > best)
		best = mine;
	if (best > gPfAlphaHi)
		gPfAlphaHi = best;
	if (gPfAlphaHi <= 0.f)
		return 0.f;
	return gPfAlphaHi * PfAlphaPerMetal();
}

// The heaviest single attacker a post should expect, in METAL -- the same
// currency the stake and the wave are already in. High-water, and floored by
// our own best buildable mobile, exactly as PfAlphaRef.
float PfHeavyRef()
{
	PfAlphaRef();   // refreshes the high-water mark
	return gPfAlphaHi;
}

// SURFACE DPS, recovered from the engine's own threat figure.
//
// CircuitDef.cpp:622 builds surfThreat as
// sqrt(surfDps) * surfDmg^0.25 * THREAT_MOD * sqrt(health), so dividing that
// back out by sqrt(health) and alpha^0.25 and squaring leaves surfDps times a
// constant -- and the constant cancels against the light-tower reference this
// is always divided by. Recovered rather than read off Catalog::gDps because
// gDps counts every weapon: an AA turret would otherwise score as ground
// cover, and surfT is the only field that knows what a gun can shoot.
float PfSurfDps(int d)
{
	const float t = Catalog::gSurfT[d];
	const float hp = Catalog::gHealth[d];
	const float a = Catalog::gAlpha[d];
	if ((t <= 0.f) || (hp <= 0.f) || (a <= 0.f))
		return 0.f;
	const float r = t / (sqrt(hp) * pow(a, 0.25f));
	return r * r;
}

// Cover this def contributes at a point it reaches, in light-tower metal.
float PfTowerKill(int d)
{
	// DAMAGE RATE IS LINEAR HERE, unlike the engine's threat.
	//
	// Reach is already paid, and paid as area: PfStakeIn buckets our economy
	// at the candidate's OWN range, so a long gun is credited with every asset
	// the short one cannot reach. Hit points are paid twice -- sqrt(hp) inside
	// surfThreat, and again in the durability term below. Rate of fire was the
	// only term still under a square root, which is what let a gun with a
	// twelfth of a Beamer's damage per metal outprice it on reach alone.
	const bool lin = (ai.GetTunable("apex_def_dps_linear", TUNE_DEF_DPS_LINEAR) > 0.f);
	// Ahead of the stamps below: PfKillRef prices the LIGHT TOWER through
	// PfKillRaw, so when d is the light tower that call would otherwise leave
	// this def's dps stamped from a branch the price did not take.
	const float ref = lin ? PfKillRef() : PfKillRefT();
	PkEnsure(d);
	gPkLin[d] = lin ? 1 : 0;
	gPkRef[d] = ref;
	gPkDur[d] = -1.f;
	gPkTrade[d] = -1.f;
	if (ref <= 0.f) {
		gPkDps[d] = -1.f;
		gPkOutr[d] = -1.f;
		gPkBase[d] = 0.f;
		gPkOut[d] = 0.f;
		return 0.f;
	}
	float base = 0.f;
	if (lin) {
		base = PfKillRaw(d);   // stamps gPkDps / gPkOutr
	} else {
		base = Catalog::gSurfT[d];
		gPkDps[d] = -1.f;
		gPkOutr[d] = -1.f;
	}
	gPkBase[d] = base;
	float m = base / ref;
	// apex_def_alpha_w is a WEIGHT on the reference blow, not just a switch:
	// it was only ever tested > 0, so the dashboard knob could turn durability
	// off and could not tune it.
	{
		const float w = ai.GetTunable("apex_def_alpha_w", TUNE_DEF_ALPHA_W);
		const float a = PfAlphaRef() * w;
		const float hp = Catalog::gHealth[d];
		if ((w > 0.f) && (a > 0.f) && (hp > 0.f)) {
			gPkDur[d] = hp / (hp + a);
			m *= gPkDur[d];
		}
	}
	gPkTrade[d] = ai.GetTunable("apex_def_trade", TUNE_DEF_TRADE);
	gPkOut[d] = m * gPkTrade[d];
	return gPkOut[d];
}

//------------------------------------------------------------------------------
// THE KEY TABLE. key -> slot in the pass currently being gathered, so the
// commit below can ask "did this asset have a slot last time" in O(1) instead
// of searching. Written per pass and validated by the pass number rather than
// cleared, so a dead unit id never has to be hunted down.
//------------------------------------------------------------------------------
// THE FIRE A DEF SOAKS, in the same light-tower metal as PfTowerKill: its
// health against the light tower's, times what the light tower stops. What
// the front row is worth -- cheap things in front of the mains absorb the
// first volleys and split the attacker's fire while the mains behind kill.
array<float> gPkAbs;
float PfAbsorb(int d)
{
	if (int(gPkAbs.length()) <= Catalog::gDefCount) {
		const uint n0 = gPkAbs.length();
		gPkAbs.resize(uint(Catalog::gDefCount + 1));
		for (uint i = n0; i < gPkAbs.length(); ++i)
			gPkAbs[i] = -1.f;
	}
	if (gPkAbs[d] >= 0.f)
		return gPkAbs[d];
	float a = 0.f;
	CCircuitDef@ light = SideDef3("armllt", "corllt", "leglht");
	if (light !is null) {
		const int ld = int(light.id);
		if (Catalog::gHealth[ld] > 0.f)
			a = Catalog::gHealth[d] / Catalog::gHealth[ld] * PfTowerKill(ld);
	}
	if (PfKillRef() > 0.f)
		gPkAbs[d] = a;   // not cached before the light tower is readable
	return a;
}

int gPfPassN = 0;
array<int> gPfIdSeen;    // pass this unit id was written in...
array<int> gPfIdSlot;    // ...and the slot it took
array<int> gPfMexSeen;   // the same, for ledger extractor slots
array<int> gPfMexSlot;

void PfKeyPut(int key, int slot)
{
	if (key >= 0) {
		if (int(gPfIdSeen.length()) <= key) {
			gPfIdSeen.resize(uint(key + 256));
			gPfIdSlot.resize(uint(key + 256));
		}
		gPfIdSeen[uint(key)] = gPfPassN;
		gPfIdSlot[uint(key)] = slot;
		return;
	}
	const int m = -key - 1;
	if (int(gPfMexSeen.length()) <= m) {
		gPfMexSeen.resize(uint(m + 64));
		gPfMexSlot.resize(uint(m + 64));
	}
	gPfMexSeen[uint(m)] = gPfPassN;
	gPfMexSlot[uint(m)] = slot;
}

int PfKeyGet(int key)
{
	if (key >= 0) {
		if (int(gPfIdSeen.length()) <= key)
			return -1;
		return (gPfIdSeen[uint(key)] == gPfPassN) ? gPfIdSlot[uint(key)] : -1;
	}
	const int m = -key - 1;
	if ((m < 0) || (int(gPfMexSeen.length()) <= m))
		return -1;
	return (gPfMexSeen[uint(m)] == gPfPassN) ? gPfMexSlot[uint(m)] : -1;
}

// The pass just gathered, in whatever order the engine handed it over.
array<AIFloat3> gPfNPos;
array<float>    gPfNWorth;
array<bool>     gPfNIsMex;
array<int>      gPfNKey;

// LAND THE PASS WITHOUT SHUFFLING THE ASSETS THAT DID NOT MOVE.
//
// Every surviving key keeps the slot it already had and newcomers go on the
// end, so gPfStamp changes only when a building actually finished or died.
// The set and the per-asset values are exactly what the pass gathered -- this
// decides ORDER, nothing else -- and a downstream cache that stored the stamp
// now knows whether its index-parallel arrays still describe the same assets.
void PfCommit()
{
	const uint nN = gPfNKey.length();
	++gPfPassN;
	for (uint j = 0; j < nN; ++j)
		PfKeyPut(gPfNKey[j], int(j));
	bool same = (nN == gPfKey.length());
	for (uint i = 0; same && (i < nN); ++i)
		same = (gPfKey[i] == gPfNKey[i]);
	if (same) {
		// Same assets in the same places. A mex's worth is a live income and
		// a unit can be nudged, so the VALUES still land; the indices do not
		// move and the stamp does not change.
		gPfPos = gPfNPos;
		gPfWorth = gPfNWorth;
		gPfIsMex = gPfNIsMex;
		return;
	}
	array<bool> taken(nN, false);
	array<AIFloat3> oPos;
	array<float> oWorth;
	array<bool> oIsMex;
	array<int> oKey;
	for (uint i = 0; i < gPfKey.length(); ++i) {
		const int j = PfKeyGet(gPfKey[i]);
		if ((j < 0) || taken[uint(j)])
			continue;   // that asset is gone
		taken[uint(j)] = true;
		oPos.insertLast(gPfNPos[uint(j)]);
		oWorth.insertLast(gPfNWorth[uint(j)]);
		oIsMex.insertLast(gPfNIsMex[uint(j)]);
		oKey.insertLast(gPfNKey[uint(j)]);
	}
	for (uint j = 0; j < nN; ++j) {
		if (taken[j])
			continue;
		oPos.insertLast(gPfNPos[j]);
		oWorth.insertLast(gPfNWorth[j]);
		oIsMex.insertLast(gPfNIsMex[j]);
		oKey.insertLast(gPfNKey[j]);
	}
	gPfPos = oPos;
	gPfWorth = oWorth;
	gPfIsMex = oIsMex;
	gPfKey = oKey;
	++gPfStamp;
}

//------------------------------------------------------------------------------
// THE REBUILD. Bounded by game time, not by callers: the defence price is asked
// once per builder election and the walk over every team unit is the single
// most expensive thing in the market (measured: want.protect at 9.2 ms per call
// by minute 19, growing superlinearly with base size).
//------------------------------------------------------------------------------
// OUR HULL ON THE BLACKBOARD, for the team hull (protect_team.as): centre,
// the rim per bearing capped the way the wall caps it (one far mex must not
// balloon it), and the worth standing in each bearing.
const string TV_PF_MX = "pfmx";
const string TV_PF_MZ = "pfmz";
const string TV_PF_W  = "pfw";
const string TV_PF_WAVE = "pfwave";   // the wave prior we defend against
const string TV_PF_FX = "pffx";   // our furthest capped mex toward them
const string TV_PF_FZ = "pffz";
float gPfCapR = 0.f;
int gNextPfHullLog = 0;
int gPfDbgFoeOk = -1;
AIFloat3 gPfDbgFoe;
void PfPublishHull()
{
	if (!gPfRimOk) {
		ai.PublishTeamValue(TV_PF_MX, -1.f);
		return;
	}
	float sw = 0.f;
	float sd2 = 0.f;
	array<float> bw(PF_RAYS, 0.f);
	for (uint i = 0; i < gPfPos.length(); ++i) {
		bw[uint(PfRayOf(gPfPos[i]))] += gPfWorth[i];
		if ((i < gPfIsMex.length()) && gPfIsMex[i])
			continue;
		const float dd = gPfPos[i].distance2D(gPfMid);
		sd2 += gPfWorth[i] * dd * dd;
		sw += gPfWorth[i];
	}
	gPfCapR = (sw > 1.f)
			? sqrt(sd2 / sw) * ai.GetTunable("apex_wall_reach", TUNE_WALL_REACH)
			: 0.f;
	ai.PublishTeamValue(TV_PF_MX, gPfMid.x);
	ai.PublishTeamValue(TV_PF_MZ, gPfMid.z);
	ai.PublishTeamValue(TV_PF_W, gPfTotal);
	ai.PublishTeamValue(TV_PF_WAVE, ArmyTargetFull()
			* ai.GetTunable("apex_def_prior_share", TUNE_DEF_PRIOR_SHARE)
			* TeamExposure());
	// Our furthest capped extractor toward them: the team's frontier is the
	// furthest of these (protect_wall.as), not one player's.
	{
		AIFloat3 foe;
		float best = -1.f;
		AIFloat3 bestP(-1.f, 0.f, -1.f);
		const bool foeOk = FoeRef(foe);
		gPfDbgFoeOk = foeOk ? 1 : 0;
		gPfDbgFoe = foe;
		if (foeOk && Builder::gHomeSet) {
			AIFloat3 fd = foe - Builder::gHomePos;
			if (fd.SqLength2D() > 1.f) {
				fd.SafeNormalize2D();
				for (uint i = 0; i < gPfPos.length(); ++i) {
					if ((i >= gPfIsMex.length()) || !gPfIsMex[i])
						continue;
					const float df = (gPfPos[i].x - Builder::gHomePos.x) * fd.x
							+ (gPfPos[i].z - Builder::gHomePos.z) * fd.z;
					if (df > best) {
						best = df;
						bestP = gPfPos[i];
					}
				}
			}
		}
		ai.PublishTeamValue(TV_PF_FX, bestP.x);
		ai.PublishTeamValue(TV_PF_FZ, bestP.z);
		if (ai.frame >= gNextPfHullLog) {
			gNextPfHullLog = ai.frame + 60 * SECOND;
			int nMex = 0;
			for (uint i = 0; i < gPfIsMex.length(); ++i)
				if (gPfIsMex[i])
					++nMex;
			AiLog(Factory::T() + "apex: pfhull assets=" + gPfPos.length()
				+ " mex=" + nMex + " rows=" + MexRows().length()
				+ " fwd=" + int(bestP.x) + "," + int(bestP.z)
				+ " fwdD=" + int(best) + " cap=" + int(gPfCapR)
				+ " foeOk=" + gPfDbgFoeOk + " foe=" + int(gPfDbgFoe.x) + "," + int(gPfDbgFoe.z)
				+ " home=" + int(Builder::gHomePos.x) + "," + int(Builder::gHomePos.z)
				+ " mid=" + int(gPfMid.x) + "," + int(gPfMid.z));
		}
	}
	for (int b = 0; b < PF_RAYS; ++b) {
		float rb = gPfRimR[b];
		if ((gPfCapR > 1.f) && (rb > gPfCapR))
			rb = gPfCapR;
		ai.PublishTeamValue("pfr" + b, rb);
		ai.PublishTeamValue("pfw" + b, bw[uint(b)]);
	}
}

void PfRebuild()
{
	const float everyS = ai.GetTunable("apex_protect_field_s", TUNE_PROTECT_FIELD_S);
	const int every = int(((everyS > 0.1f) ? everyS : 2.f) * 30.f);
	if ((ai.frame - gPfAt) < every)
		return;
	gPfAt = ai.frame;
	const double _tPf = Perf::T0();

	gPfNPos.resize(0);
	gPfNWorth.resize(0);
	gPfNIsMex.resize(0);
	gPfNKey.resize(0);
	gPfTotal = 0.f;
	gPfCells = 0.f;
	const float h = PfHorizon();

	// EVERY STANDING BUILDING, not a hand-picked three classes. Extractors are
	// skipped here and added from the ledger below at their capitalized income:
	// a 620-metal extractor earning 3 metal/s is not worth 620 to lose.
	if (Builder::gHomeSet) {
		array<CCircuitUnit@>@ st = ai.GetOwnStructsNear(Builder::gHomePos, 0.f);
		for (uint i = 0; i < st.length(); ++i) {
			CCircuitUnit@ u = st[i];
			if ((u is null) || (u.circuitDef is null))
				continue;
			const int d = int(u.circuitDef.id);
			// Counted before the worth filters below: extractors and towers
			// take up ground exactly like everything else.
			gPfCells += float((Catalog::gAreaCells[d] > 0)
					? Catalog::gAreaCells[d] : 1);
			if (Catalog::gExtractsM[d] > 0.f)
				continue;
			if (ProtClassOf(d) >= 0)
				continue;   // defence is never its own reason (census.as, gProtM)
			const AIFloat3 p = u.GetPos(ai.frame);
			if (!OnMap(p))
				continue;
			gPfNPos.insertLast(p);
			gPfNWorth.insertLast(Catalog::gCostM[d]);
			gPfNIsMex.insertLast(false);
			gPfNKey.insertLast(int(u.id));
			gPfTotal += Catalog::gCostM[d];
		}
	}
	const array<int>@ mexRows = MexRows();
	for (uint q = 0; q < mexRows.length(); ++q) {
		const uint i = uint(mexRows[q]);
		const float w = gLIncome[i] * IncomeMult() * gLExtract[i] * h;
		gPfNPos.insertLast(gLPos[i]);
		gPfNWorth.insertLast(w);
		gPfNIsMex.insertLast(true);
		gPfNKey.insertLast(-int(i) - 1);
		gPfTotal += w;
	}
	PfCommit();

	// The rim, over the assets just gathered. One extra O(n) pass.
	gPfRimOk = false;
	if (gPfPos.length() > 0) {
		float sx = 0.f, sz = 0.f, sw = 0.f;
		for (uint i = 0; i < gPfPos.length(); ++i) {
			sx += gPfPos[i].x * gPfWorth[i];
			sz += gPfPos[i].z * gPfWorth[i];
			sw += gPfWorth[i];
		}
		if (sw > 1.f) {
			gPfMid = AIFloat3(sx / sw, 0.f, sz / sw);
			gPfRimR.resize(PF_RAYS);
			for (int b = 0; b < PF_RAYS; ++b)
				gPfRimR[b] = 0.f;
			for (uint i = 0; i < gPfPos.length(); ++i) {
				const int b = PfRayOf(gPfPos[i]);
				const float rr = gPfPos[i].distance2D(gPfMid);
				if (rr > gPfRimR[b])
					gPfRimR[b] = rr;
			}
			// A bearing that holds nothing takes the chord between its nearest
			// occupied neighbours -- the hull. Decaying to a notch instead read a
			// four-building opening as a FULL base (crowd ~1), which charged a
			// 155-metal solar 260-830 of room rent while a mex paid none.
			array<float> sm = gPfRimR;
			for (int b = 0; b < PF_RAYS; ++b) {
				if (gPfRimR[b] > 0.f)
					continue;
				int dl = 1, dh = 1;
				while ((dl < PF_RAYS) && (gPfRimR[(b + PF_RAYS - dl) % PF_RAYS] <= 0.f))
					++dl;
				while ((dh < PF_RAYS) && (gPfRimR[(b + dh) % PF_RAYS] <= 0.f))
					++dh;
				if ((dl >= PF_RAYS) || (dh >= PF_RAYS))
					continue;
				const float rl = gPfRimR[(b + PF_RAYS - dl) % PF_RAYS];
				const float rh = gPfRimR[(b + dh) % PF_RAYS];
				sm[b] = (rl * float(dh) + rh * float(dl)) / float(dl + dh);
			}
			gPfRimR = sm;
			gPfRimOk = true;
		}
	}
	PfPublishHull();

	// Gathered aside and compared, so gPfTwRev moves only when the towers
	// PfCoverPoint reads actually change.
	array<AIFloat3> tPos;
	array<float> tReach;
	array<float> tKill;
	for (uint i = 0; i < gProtPos[PROT_DEF].length(); ++i) {
		const int d = gProtDefId[PROT_DEF][i];
		const float r = Catalog::gMaxRange[d];
		if (r <= 1.f)
			continue;
		tPos.insertLast(gProtPos[PROT_DEF][i]);
		tReach.insertLast(r);
		tKill.insertLast(PfTowerKill(d));
	}
	// THE TEAM'S GUNS, NOT ONLY OURS. An ally's tower stops the same wave, so
	// the cover field reads it -- or every player buys its own gun beside a
	// mate's, and a bearing an ally holds reads open (measured: 79% of the
	// team's guns inside the team hull, each player ringing its own base).
	{
		const array<float>@ ad = ai.GetAllyDefences();
		if (ad !is null) {
			for (uint k = 0; k + 2 < ad.length(); k += 3) {
				const int d = int(ad[k + 2]);
				if ((d <= 0) || (d >= Catalog::gDefCount) || (ProtClassOf(d) != PROT_DEF))
					continue;
				const float r = Catalog::gMaxRange[d];
				if (r <= 1.f)
					continue;
				tPos.insertLast(AIFloat3(ad[k], 0.f, ad[k + 1]));
				tReach.insertLast(r);
				tKill.insertLast(PfTowerKill(d));
			}
		}
	}
	bool twSame = (tPos.length() == gPfTwPos.length());
	for (uint i = 0; twSame && (i < tPos.length()); ++i) {
		twSame = (tPos[i].x == gPfTwPos[i].x) && (tPos[i].z == gPfTwPos[i].z)
			&& (tReach[i] == gPfTwReach[i]) && (tKill[i] == gPfTwKill[i]);
	}
	gPfTwPos = tPos;
	gPfTwReach = tReach;
	gPfTwKill = tKill;
	if (!twSame)
		++gPfTwRev;
	PfGridBuild();
	PfTowerGridBuild();
	Perf::Add("prot.field", _tPf);
}

//------------------------------------------------------------------------------
// THE BUCKET INDEX over the two fields above. Every stake and cover reading is
// "what of ours is within r of this point", so a query walks the cells its own
// radius touches instead of everything we own.
//
// The answer is unchanged, not approximated: a cell is skipped only when no
// point inside it can satisfy the test, and every asset in a cell that IS
// walked runs the same compare it ran before.
//------------------------------------------------------------------------------
const float PF_CELL = 512.f;    // ~half apex_threat_r, the radius asked most
const int   PF_CELL_MAX = 256;  // ...coarsened past this, so a base spread
                                // across the map never costs more in empty
                                // cells than the walk it replaced
array<int> gPfGStart;          // CSR: first item of cell c, cells+1 long
array<int> gPfGItem;           // asset indices, grouped by cell
float      gPfGX0 = 0.f;
float      gPfGZ0 = 0.f;
float      gPfGCell = PF_CELL;
int        gPfGNX = 0;
int        gPfGNZ = 0;

// The cell size that keeps a grid over this extent under PF_CELL_MAX cells.
float PfCellSize(float w, float h)
{
	float c = PF_CELL;
	for (int k = 0; k < 8; ++k) {
		const int nx = int(w / c) + 1;
		const int nz = int(h / c) + 1;
		if (nx * nz <= PF_CELL_MAX)
			break;
		c *= 2.f;
	}
	return c;
}

array<int>   gPfTGStart;
array<int>   gPfTGItem;
array<float> gPfTGReach;       // the LONGEST reach in each cell: a cell whose
                               // farthest gun cannot reach the point is skipped
float        gPfTGX0 = 0.f;
float        gPfTGZ0 = 0.f;
float        gPfTGCell = PF_CELL;
float        gPfTGMaxR = 0.f;  // longest reach anywhere: the query's own window
int          gPfTGNX = 0;
int          gPfTGNZ = 0;

void PfGridBuild()
{
	gPfGStart.resize(0);
	gPfGItem.resize(0);
	gPfGNX = 0;
	gPfGNZ = 0;
	const uint n = gPfPos.length();
	if (n == 0)
		return;
	float x0 = gPfPos[0].x, x1 = gPfPos[0].x;
	float z0 = gPfPos[0].z, z1 = gPfPos[0].z;
	for (uint i = 1; i < n; ++i) {
		if (gPfPos[i].x < x0) x0 = gPfPos[i].x;
		if (gPfPos[i].x > x1) x1 = gPfPos[i].x;
		if (gPfPos[i].z < z0) z0 = gPfPos[i].z;
		if (gPfPos[i].z > z1) z1 = gPfPos[i].z;
	}
	gPfGX0 = x0;
	gPfGZ0 = z0;
	gPfGCell = PfCellSize(x1 - x0, z1 - z0);
	gPfGNX = int((x1 - x0) / gPfGCell) + 1;
	gPfGNZ = int((z1 - z0) / gPfGCell) + 1;
	const int nc = gPfGNX * gPfGNZ;
	gPfGStart.resize(uint(nc + 1));
	for (uint c = 0; c < gPfGStart.length(); ++c)
		gPfGStart[c] = 0;
	array<int> cellOf(n, 0);
	for (uint i = 0; i < n; ++i) {
		int cx = int((gPfPos[i].x - x0) / gPfGCell);
		int cz = int((gPfPos[i].z - z0) / gPfGCell);
		if (cx < 0) cx = 0;
		if (cx >= gPfGNX) cx = gPfGNX - 1;
		if (cz < 0) cz = 0;
		if (cz >= gPfGNZ) cz = gPfGNZ - 1;
		const int c = cz * gPfGNX + cx;
		cellOf[i] = c;
		++gPfGStart[uint(c + 1)];
	}
	for (int c = 0; c < nc; ++c)
		gPfGStart[uint(c + 1)] += gPfGStart[uint(c)];
	gPfGItem.resize(n);
	array<int> fill(uint(nc), 0);
	for (uint i = 0; i < n; ++i) {
		const int c = cellOf[i];
		gPfGItem[uint(gPfGStart[uint(c)] + fill[uint(c)])] = int(i);
		++fill[uint(c)];
	}
}

void PfTowerGridBuild()
{
	gPfTGStart.resize(0);
	gPfTGItem.resize(0);
	gPfTGReach.resize(0);
	gPfTGMaxR = 0.f;
	gPfTGNX = 0;
	gPfTGNZ = 0;
	const uint n = gPfTwPos.length();
	if (n == 0)
		return;
	float x0 = gPfTwPos[0].x, x1 = gPfTwPos[0].x;
	float z0 = gPfTwPos[0].z, z1 = gPfTwPos[0].z;
	for (uint i = 1; i < n; ++i) {
		if (gPfTwPos[i].x < x0) x0 = gPfTwPos[i].x;
		if (gPfTwPos[i].x > x1) x1 = gPfTwPos[i].x;
		if (gPfTwPos[i].z < z0) z0 = gPfTwPos[i].z;
		if (gPfTwPos[i].z > z1) z1 = gPfTwPos[i].z;
	}
	gPfTGX0 = x0;
	gPfTGZ0 = z0;
	gPfTGCell = PfCellSize(x1 - x0, z1 - z0);
	gPfTGNX = int((x1 - x0) / gPfTGCell) + 1;
	gPfTGNZ = int((z1 - z0) / gPfTGCell) + 1;
	const int nc = gPfTGNX * gPfTGNZ;
	gPfTGStart.resize(uint(nc + 1));
	for (uint c = 0; c < gPfTGStart.length(); ++c)
		gPfTGStart[c] = 0;
	gPfTGReach.resize(uint(nc));
	for (uint c = 0; c < gPfTGReach.length(); ++c)
		gPfTGReach[c] = 0.f;
	array<int> cellOf(n, 0);
	for (uint i = 0; i < n; ++i) {
		int cx = int((gPfTwPos[i].x - x0) / gPfTGCell);
		int cz = int((gPfTwPos[i].z - z0) / gPfTGCell);
		if (cx < 0) cx = 0;
		if (cx >= gPfTGNX) cx = gPfTGNX - 1;
		if (cz < 0) cz = 0;
		if (cz >= gPfTGNZ) cz = gPfTGNZ - 1;
		const int c = cz * gPfTGNX + cx;
		cellOf[i] = c;
		++gPfTGStart[uint(c + 1)];
		if (gPfTwReach[i] > gPfTGReach[uint(c)])
			gPfTGReach[uint(c)] = gPfTwReach[i];
		if (gPfTwReach[i] > gPfTGMaxR)
			gPfTGMaxR = gPfTwReach[i];
	}
	for (int c = 0; c < nc; ++c)
		gPfTGStart[uint(c + 1)] += gPfTGStart[uint(c)];
	gPfTGItem.resize(n);
	array<int> fill(uint(nc), 0);
	for (uint i = 0; i < n; ++i) {
		const int c = cellOf[i];
		gPfTGItem[uint(gPfTGStart[uint(c)] + fill[uint(c)])] = int(i);
		++fill[uint(c)];
	}
}

// Cell range covering [v - r, v + r] on one axis, clamped into the grid. The
// upper clamp keeps a cell that may still hold something rather than dropping
// it, so the range is always a superset of the cells the disc can touch.
int PfCellLo(float v, float r, float o, float cell, int n)
{
	const float f = (v - r - o) / cell;
	if (f <= 0.f)
		return 0;
	const int c = int(f);
	return (c > n - 1) ? (n - 1) : c;
}

int PfCellHi(float v, float r, float o, float cell, int n)
{
	const float f = (v + r - o) / cell;
	if (f < 0.f)
		return -1;   // the whole grid lies past v + r on this axis
	const int c = int(f);
	return (c > n - 1) ? (n - 1) : c;
}

// Everything of ours inside r of pos, in metal. The stake, over every building
// rather than over three classes of them.
float PfStakeAt(const AIFloat3& in pos, float r)
{
	PfRebuild();
	float m = 0.f;
	if (gPfGNX <= 0)
		return m;
	const int cx0 = PfCellLo(pos.x, r, gPfGX0, gPfGCell, gPfGNX);
	const int cx1 = PfCellHi(pos.x, r, gPfGX0, gPfGCell, gPfGNX);
	const int cz0 = PfCellLo(pos.z, r, gPfGZ0, gPfGCell, gPfGNZ);
	const int cz1 = PfCellHi(pos.z, r, gPfGZ0, gPfGCell, gPfGNZ);
	for (int cz = cz0; cz <= cz1; ++cz) {
		const int row = cz * gPfGNX;
		const int e = gPfGStart[uint(row + cx1 + 1)];
		for (int k = gPfGStart[uint(row + cx0)]; k < e; ++k) {
			const uint i = uint(gPfGItem[uint(k)]);
			if (gPfPos[i].distance2D(pos) < r)
				m += gPfWorth[i];
		}
	}
	return m;
}

// Standing cover at a point, in light-tower metal, optionally with one extra
// turret standing at extraAt.
float PfCoverPoint(const AIFloat3& in at, const AIFloat3& in extraAt,
		float extraReach, float extraKill)
{
	float m = 0.f;
	if (gPfTGNX > 0) {
		const int qx0 = PfCellLo(at.x, gPfTGMaxR, gPfTGX0, gPfTGCell, gPfTGNX);
		const int qx1 = PfCellHi(at.x, gPfTGMaxR, gPfTGX0, gPfTGCell, gPfTGNX);
		const int qz0 = PfCellLo(at.z, gPfTGMaxR, gPfTGZ0, gPfTGCell, gPfTGNZ);
		const int qz1 = PfCellHi(at.z, gPfTGMaxR, gPfTGZ0, gPfTGCell, gPfTGNZ);
		for (int cz = qz0; cz <= qz1; ++cz) {
			const int row = cz * gPfTGNX;
			// A cell's own longest gun bounds what it can contribute, so the
			// row scan below skips whole cells the point is out of reach of.
			const float bz0 = gPfTGZ0 + float(cz) * gPfTGCell;
			float dz = 0.f;
			if (at.z < bz0)
				dz = bz0 - at.z;
			else if (at.z > bz0 + gPfTGCell)
				dz = at.z - (bz0 + gPfTGCell);
			for (int cx = qx0; cx <= qx1; ++cx) {
				const int c = row + cx;
				const float rr = gPfTGReach[uint(c)];
				if (rr <= 0.f)
					continue;
				const float bx0 = gPfTGX0 + float(cx) * gPfTGCell;
				float dx = 0.f;
				if (at.x < bx0)
					dx = bx0 - at.x;
				else if (at.x > bx0 + gPfTGCell)
					dx = at.x - (bx0 + gPfTGCell);
				if (dx * dx + dz * dz > rr * rr)
					continue;   // nothing in this cell reaches the point
				const int e = gPfTGStart[uint(c + 1)];
				for (int k = gPfTGStart[uint(c)]; k < e; ++k) {
					const uint i = uint(gPfTGItem[uint(k)]);
					if (gPfTwPos[i].distance2D(at) <= gPfTwReach[i])
						m += gPfTwKill[i];
				}
			}
		}
	}
	if ((extraReach > 0.f) && (extraAt.distance2D(at) <= extraReach))
		m += extraKill;
	return m;
}

// Gun worth (light-tower metal, the team's) standing within r of a point.
float PfTowerKillNear(const AIFloat3& in at, float r)
{
	float m = 0.f;
	for (uint i = 0; i < gPfTwPos.length(); ++i) {
		if (gPfTwPos[i].distance2D(at) <= r)
			m += gPfTwKill[i];
	}
	return m;
}

// Does anything of ours already cover this point? The wall's open test, which
// asked the same question of every tower one at a time per slot.
bool PfCoveredAt(const AIFloat3& in at)
{
	if (gPfTGNX <= 0)
		return false;
	const int qx0 = PfCellLo(at.x, gPfTGMaxR, gPfTGX0, gPfTGCell, gPfTGNX);
	const int qx1 = PfCellHi(at.x, gPfTGMaxR, gPfTGX0, gPfTGCell, gPfTGNX);
	const int qz0 = PfCellLo(at.z, gPfTGMaxR, gPfTGZ0, gPfTGCell, gPfTGNZ);
	const int qz1 = PfCellHi(at.z, gPfTGMaxR, gPfTGZ0, gPfTGCell, gPfTGNZ);
	for (int cz = qz0; cz <= qz1; ++cz) {
		const int row = cz * gPfTGNX;
		const float bz0 = gPfTGZ0 + float(cz) * gPfTGCell;
		float dz = 0.f;
		if (at.z < bz0)
			dz = bz0 - at.z;
		else if (at.z > bz0 + gPfTGCell)
			dz = at.z - (bz0 + gPfTGCell);
		for (int cx = qx0; cx <= qx1; ++cx) {
			const int c = row + cx;
			const float rr = gPfTGReach[uint(c)];
			if (rr <= 0.f)
				continue;
			const float bx0 = gPfTGX0 + float(cx) * gPfTGCell;
			float dx = 0.f;
			if (at.x < bx0)
				dx = bx0 - at.x;
			else if (at.x > bx0 + gPfTGCell)
				dx = at.x - (bx0 + gPfTGCell);
			if (dx * dx + dz * dz > rr * rr)
				continue;
			const int e = gPfTGStart[uint(c + 1)];
			for (int k = gPfTGStart[uint(c)]; k < e; ++k) {
				const uint i = uint(gPfTGItem[uint(k)]);
				if (gPfTwPos[i].distance2D(at) <= gPfTwReach[i])
					return true;
			}
		}
	}
	return false;
}

// THE WORST BEARING OF A STANDOFF RING, IN ONE TRAVERSAL.
//
// CoverWith reads cover at each point of a ring around a site and keeps the
// smallest -- COVER_RAYS separate walks of the tower index for six sums over
// the same towers. Every ring point is within `standoff` of the centre, so one
// window of (standoff + the longest reach) holds every tower that can reach any
// of them, and each tower then runs the same per-ray compare and adds the same
// kill it did before. False when no ring point is on the map, which is the
// caller's signal to fall back to the point reading.
array<float>    gPfCrSum;
array<AIFloat3> gPfCrP;
array<bool>     gPfCrOn;

bool PfCoverRing(const AIFloat3& in at, float standoff,
		const array<float>& in rcos, const array<float>& in rsin,
		const AIFloat3& in extraAt, float extraReach, float extraKill,
		float& out worst)
{
	worst = -1.f;
	const uint nr = rcos.length();
	if (nr == 0)
		return false;
	PfRebuild();
	if (gPfCrSum.length() != nr) {
		gPfCrSum.resize(nr);
		gPfCrOn.resize(nr);
	}
	gPfCrP.resize(0);
	bool any = false;
	for (uint b = 0; b < nr; ++b) {
		gPfCrP.insertLast(at + AIFloat3(rcos[b], 0.f, rsin[b]) * standoff);
		gPfCrSum[b] = 0.f;
		gPfCrOn[b] = OnMap(gPfCrP[b]);
		if (gPfCrOn[b])
			any = true;
	}
	if (!any)
		return false;
	if (gPfTGNX > 0) {
		const float win = standoff + gPfTGMaxR;
		const int qx0 = PfCellLo(at.x, win, gPfTGX0, gPfTGCell, gPfTGNX);
		const int qx1 = PfCellHi(at.x, win, gPfTGX0, gPfTGCell, gPfTGNX);
		const int qz0 = PfCellLo(at.z, win, gPfTGZ0, gPfTGCell, gPfTGNZ);
		const int qz1 = PfCellHi(at.z, win, gPfTGZ0, gPfTGCell, gPfTGNZ);
		for (int cz = qz0; cz <= qz1; ++cz) {
			const int row = cz * gPfTGNX;
			const float bz0 = gPfTGZ0 + float(cz) * gPfTGCell;
			float dz = 0.f;
			if (at.z < bz0)
				dz = bz0 - at.z;
			else if (at.z > bz0 + gPfTGCell)
				dz = at.z - (bz0 + gPfTGCell);
			for (int cx = qx0; cx <= qx1; ++cx) {
				const int c = row + cx;
				if (gPfTGReach[uint(c)] <= 0.f)
					continue;
				const float rr = gPfTGReach[uint(c)] + standoff;
				const float bx0 = gPfTGX0 + float(cx) * gPfTGCell;
				float dx = 0.f;
				if (at.x < bx0)
					dx = bx0 - at.x;
				else if (at.x > bx0 + gPfTGCell)
					dx = at.x - (bx0 + gPfTGCell);
				if (dx * dx + dz * dz > rr * rr)
					continue;   // nothing in this cell reaches any ring point
				const int e = gPfTGStart[uint(c + 1)];
				for (int k = gPfTGStart[uint(c)]; k < e; ++k) {
					const uint i = uint(gPfTGItem[uint(k)]);
					const float tr = gPfTwReach[i];
					const float tk = gPfTwKill[i];
					for (uint b = 0; b < nr; ++b) {
						if (gPfCrOn[b]
							&& (gPfTwPos[i].distance2D(gPfCrP[b]) <= tr))
							gPfCrSum[b] += tk;
					}
				}
			}
		}
	}
	for (uint b = 0; b < nr; ++b) {
		if (!gPfCrOn[b])
			continue;
		if ((extraReach > 0.f)
			&& (extraAt.distance2D(gPfCrP[b]) <= extraReach))
			gPfCrSum[b] += extraKill;
		if ((worst < 0.f) || (gPfCrSum[b] < worst))
			worst = gPfCrSum[b];
	}
	return true;
}

// COVER AT EVERY ASSET AT ONCE, FROM THE TOWERS OUT.
//
// The guard posting asks PfCoverPoint per asset -- one walk of the tower index
// per asset, for a reading that is a SUM over towers. Measured late in a 16-AI
// hour: 60 assets against 8-12 standing turrets, so the loop runs the long way
// round. Each tower's own disc is one bucket query on the asset grid, and every
// asset in it runs the identical `distance2D <= reach` test and adds the
// identical kill, so the answer is the same array.
void PfCoverField(array<float>& inout cov)
{
	PfRebuild();
	const uint n = gPfPos.length();
	cov.resize(n);
	for (uint i = 0; i < n; ++i)
		cov[i] = 0.f;
	if ((gPfGNX <= 0) || (n == 0))
		return;
	for (uint t = 0; t < gPfTwPos.length(); ++t) {
		const float r = gPfTwReach[t];
		if (r <= 0.f)
			continue;
		const AIFloat3 tp = gPfTwPos[t];
		const float kill = gPfTwKill[t];
		const int cx0 = PfCellLo(tp.x, r, gPfGX0, gPfGCell, gPfGNX);
		const int cx1 = PfCellHi(tp.x, r, gPfGX0, gPfGCell, gPfGNX);
		const int cz0 = PfCellLo(tp.z, r, gPfGZ0, gPfGCell, gPfGNZ);
		const int cz1 = PfCellHi(tp.z, r, gPfGZ0, gPfGCell, gPfGNZ);
		for (int cz = cz0; cz <= cz1; ++cz) {
			const int row = cz * gPfGNX;
			const int e = gPfGStart[uint(row + cx1 + 1)];
			for (int k = gPfGStart[uint(row + cx0)]; k < e; ++k) {
				const uint i = uint(gPfGItem[uint(k)]);
				if (gPfPos[i].distance2D(tp) <= r)
					cov[i] += kill;
			}
		}
	}
}

// THE TWO STAKE READINGS A SITE NEEDS, IN ONE TRAVERSAL.
//
// A candidate is priced on what stands inside the gun's reach AND on what the
// gun shields beyond it, and the two tests share the one expensive term: the
// distance from the site to the asset. Asked separately they walked the field
// twice and computed that distance twice; the answers are complementary on it
// -- inside `reach` is the first, outside is the second -- so one pass gives
// both. Each asset still runs the identical test it ran in FrontedStakeAt and
// ShieldedStakeAlong; only the traversal is shared.
void PfStakeShield(const AIFloat3& in pos, float reach, const AIFloat3& in dirIn,
		bool wantShield, float& out sReach, float& out sShield)
{
	PfRebuild();
	sReach = 0.f;
	sShield = 0.f;
	if (gPfGNX <= 0)
		return;
	AIFloat3 dir = dirIn;
	bool shield = wantShield && (reach >= 1.f)
			&& (dir.SqLength2D() >= NEAR_ZERO);
	if (shield)
		dir.SafeNormalize2D();
	const AIFloat3 across(-dir.z, 0.f, dir.x);
	// The disc's own cell window; the shielded corridor runs backwards out of
	// it to the edge of the field, so when it is wanted the whole grid is in
	// play and the per-cell rejects below do the pruning instead.
	const int dx0 = PfCellLo(pos.x, reach, gPfGX0, gPfGCell, gPfGNX);
	const int dx1 = PfCellHi(pos.x, reach, gPfGX0, gPfGCell, gPfGNX);
	const int dz0 = PfCellLo(pos.z, reach, gPfGZ0, gPfGCell, gPfGNZ);
	const int dz1 = PfCellHi(pos.z, reach, gPfGZ0, gPfGCell, gPfGNZ);
	const int cx0 = shield ? 0 : dx0;
	const int cx1 = shield ? (gPfGNX - 1) : dx1;
	const int cz0 = shield ? 0 : dz0;
	const int cz1 = shield ? (gPfGNZ - 1) : dz1;
	// A cell lies inside a circle of this radius about its own centre, so a
	// cell whose centre is more than that outside the corridor cannot hold a
	// point inside it. Conservative in both tests, which is what keeps the
	// answer identical to the walk.
	const float cellR = gPfGCell * 0.70711f;
	for (int cz = cz0; cz <= cz1; ++cz) {
		const int row = cz * gPfGNX;
		const bool zIn = (cz >= dz0) && (cz <= dz1);
		const float rzC = gPfGZ0 + (float(cz) + 0.5f) * gPfGCell - pos.z;
		const float aRow = rzC * dir.z;
		const float lRow = rzC * across.z;
		for (int cx = cx0; cx <= cx1; ++cx) {
			const bool inDisc = zIn && (cx >= dx0) && (cx <= dx1);
			bool inCorr = false;
			if (shield) {
				const float rxC = gPfGX0 + (float(cx) + 0.5f) * gPfGCell - pos.x;
				const float a = aRow + rxC * dir.x;
				const float l = lRow + rxC * across.x;
				inCorr = (a - cellR <= 0.f) && (abs(l) - cellR <= reach);
			}
			if (!inDisc && !inCorr)
				continue;
			const int c = row + cx;
			const int e = gPfGStart[uint(c + 1)];
			for (int k = gPfGStart[uint(c)]; k < e; ++k) {
				const uint i = uint(gPfGItem[uint(k)]);
				const float d = gPfPos[i].distance2D(pos);
				if (inDisc && (d < reach))
					sReach += gPfWorth[i];
				if (!inCorr || (d < reach))
					continue;
				const float rx = gPfPos[i].x - pos.x;
				const float rz = gPfPos[i].z - pos.z;
				if ((rx * dir.x + rz * dir.z) > 0.f)
					continue;   // in front of the post: it shields nothing
				if (abs(rx * across.x + rz * across.z) > reach)
					continue;
				sShield += gPfWorth[i];
			}
		}
	}
}

//------------------------------------------------------------------------------
// GUARD SITES, DERIVED FROM THE BUILDINGS THEMSELVES.
//
// Grid-bucketed at the turret's own reach and weighted by worth, so one post is
// offered per cluster of our metal and none at all over empty ground. No ring,
// no centre, no radius anybody chose: move the base and the sites move with it.
//------------------------------------------------------------------------------
// ONE CACHE PER PITCH, not one pitch for everything.
//
// The bucket pitch is the candidate turret's own reach: a Bulwark's cluster is
// not a Guard's cluster, and forcing a single grid to make the cache work
// fragmented the base into buckets too small to hold real stake -- measured
// over two 12-game batches on one map, defence share 12.6% -> 8.2% and metal
// produced 30,575 -> 25,567. So the cache is keyed by pitch instead: a builder
// sees four to six defence defs, each set is built once per field rebuild
// rather than once per election, and the site list is the one the auction
// actually wants.
//
// Each slot carries the def-INDEPENDENT senses at its sites as well, so the
// auction reads cover, threat, hazard and the siege prior out of the field
// instead of recomputing a 16-ray sweep per site per def per builder.
array<float>           gPfPitch;
array<array<AIFloat3>> gPfSiteOf;
array<array<float>>    gPfWorthOf;
array<array<float>>    gPfCoverOf;
array<array<float>>    gPfThreatOf;
array<array<float>>    gPfHzOf;
array<array<float>>    gPfSiegeOf;
// Stake inside the post's own reach. The slot's pitch IS that reach, so this
// is PfStakeAt(site, pitch) and the auction need not re-walk every asset per
// site per def.
array<array<float>>    gPfStakeOf;
int                    gPfSiteAt = -999999;

// The slot the last PfGuardSites call filled, so the auction can index the
// cached senses alongside the sites it was just handed.
int gPfSlot = -1;

int PfSlotFor(float pitch)
{
	PfRebuild();
	if (gPfSiteAt != gPfAt) {
		gPfSiteAt = gPfAt;
		gPfPitch.resize(0);
		gPfSiteOf.resize(0);
		gPfWorthOf.resize(0);
		gPfCoverOf.resize(0);
		gPfThreatOf.resize(0);
		gPfHzOf.resize(0);
		gPfSiegeOf.resize(0);
		gPfStakeOf.resize(0);
	}
	for (uint k = 0; k < gPfPitch.length(); ++k) {
		if (gPfPitch[k] == pitch)
			return int(k);
	}
	const double _tSlot = Perf::T0();
	array<int> keyX;
	array<int> keyZ;
	array<float> sx;
	array<float> sz;
	array<float> sw;
	for (uint i = 0; i < gPfPos.length(); ++i) {
		const int kx = int(gPfPos[i].x / pitch);
		const int kz = int(gPfPos[i].z / pitch);
		int hit = -1;
		for (uint k = 0; k < keyX.length(); ++k) {
			if ((keyX[k] == kx) && (keyZ[k] == kz)) {
				hit = int(k);
				break;
			}
		}
		if (hit < 0) {
			keyX.insertLast(kx);
			keyZ.insertLast(kz);
			sx.insertLast(0.f);
			sz.insertLast(0.f);
			sw.insertLast(0.f);
			hit = int(keyX.length()) - 1;
		}
		sx[hit] += gPfPos[i].x * gPfWorth[i];
		sz[hit] += gPfPos[i].z * gPfWorth[i];
		sw[hit] += gPfWorth[i];
	}
	array<AIFloat3> site;
	array<float> worth;
	array<float> cover;
	array<float> threat;
	array<float> hz;
	array<float> siege;
	array<float> stake;
	// The side-wide half of every risk reading, read once for the whole sweep
	// instead of five times per site (coverage.as, RiskFill).
	RiskFill();
	RiskFillSiege();
	const float expFrac = ai.GetTunable("apex_enemy_prior", TUNE_ENEMY_PRIOR);
	// THE GUN STANDS IN FRONT OF WHAT IT GUARDS. The raw candidate is the
	// asset cell's worth centroid, which puts the tower AMONG the buildings --
	// and the site search then lands it on whichever side has room, behind
	// them as often as not (apexearth 2026-08-29: "i often see us putting the
	// defenses behind what we want to protect instead of in front of it").
	// Shift each candidate enemy-ward by a fraction of the tower's own reach
	// (pitch IS the def's reach here): the asset cell stays covered, and the
	// approach is met before it reaches the buildings. Pricing below runs on
	// the shifted point, so threat/cover/stake describe where the gun really
	// stands.
	const float fwdFrac = ai.GetTunable("apex_guard_forward", TUNE_GUARD_FORWARD);
	AIFloat3 foeAt;
	if (!FoeRef(foeAt))
		foeAt = AIFloat3(-1.f, 0.f, -1.f);
	for (uint k = 0; k < sw.length(); ++k) {
		if (sw[k] <= 1.f)
			continue;
		AIFloat3 c(sx[k] / sw[k], 0.f, sz[k] / sw[k]);
		if (!OnMap(c))
			continue;
		if ((fwdFrac > 0.f) && OnMap(foeAt)) {
			AIFloat3 toFoe = foeAt - c;
			const float len = sqrt(toFoe.SqLength2D());
			if (len > 1.f) {
				toFoe *= (1.f / len);
				const AIFloat3 cf = c + toFoe * (pitch * fwdFrac);
				if (OnMap(cf))
					c = cf;
			}
		}
		{
			const float cv = CoverAt(c);
			site.insertLast(c);
			worth.insertLast(sw[k]);
			cover.insertLast(cv);
			threat.insertLast(ThreatAt(c));
			hz.insertLast(HazardWith(c, cv));
			siege.insertLast(SiegeWith(c, cv, expFrac));
			stake.insertLast(PfStakeAt(c, pitch));
		}
	}
	gPfPitch.insertLast(pitch);
	gPfSiteOf.insertLast(site);
	gPfWorthOf.insertLast(worth);
	gPfCoverOf.insertLast(cover);
	gPfThreatOf.insertLast(threat);
	gPfHzOf.insertLast(hz);
	gPfSiegeOf.insertLast(siege);
	gPfStakeOf.insertLast(stake);
	Perf::Add("prot.slot", _tSlot);
	return int(gPfPitch.length()) - 1;
}

void PfGuardSites(float pitch, array<AIFloat3>& out sites)
{
	if (pitch < 64.f)
		pitch = 64.f;
	gPfSlot = PfSlotFor(pitch);
	sites = gPfSiteOf[gPfSlot];
}

float PfSiteCover(uint i)  { return gPfCoverOf[gPfSlot][i]; }
float PfSiteThreat(uint i) { return gPfThreatOf[gPfSlot][i]; }
float PfSiteHz(uint i)     { return gPfHzOf[gPfSlot][i]; }
float PfSiteSiege(uint i)  { return gPfSiegeOf[gPfSlot][i]; }
float PfSiteStake(uint i)  { return gPfStakeOf[gPfSlot][i]; }

//------------------------------------------------------------------------------
// WHAT A BUILDING IS WORTH WHILE NOTHING GUARDS IT.
//
// apexearth: "give buildings a ~20% reduced value when they are unprotected.
// And the more powerful we create defense around those buildings the more they
// become worth." One number, read wherever a structure's worth is asked: the
// discount is full over ground nothing covers and gone over ground our cover
// already beats the local wave on. Defence's gain is exactly the worth it
// gives back, so the two halves of the sentence are one function.
//------------------------------------------------------------------------------
float PfProtFrac(const AIFloat3& in pos)
{
	PfRebuild();
	const float threat = ThreatM(pos);
	if (threat <= 1.f)
		return 1.f;
	const float c = PfCoverPoint(pos, pos, -1.f, 0.f);
	const float f = c / threat;
	return (f > 1.f) ? 1.f : f;
}

float PfWorthMult(const AIFloat3& in pos)
{
	const float k = ai.GetTunable("apex_unprot_discount", TUNE_UNPROT_DISCOUNT);
	if (k <= 0.f)
		return 1.f;
	return 1.f - k * (1.f - PfProtFrac(pos));
}

}  // namespace Market
