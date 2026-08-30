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

// Towers, flattened out of gProtPos[PROT_DEF] with their reach and kill power
// resolved once instead of per candidate site per def per builder.
array<AIFloat3> gPfTwPos;
array<float>    gPfTwReach;
array<float>    gPfTwKill;

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
float gPfKillRef = -1.f;   // surface threat per metal of the faction's light tower

float PfKillRef()
{
	if (gPfKillRef > 0.f)
		return gPfKillRef;
	CCircuitDef@ light = SideDef3("armllt", "corllt", "leglht");
	if (light !is null) {
		const int ld = int(light.id);
		if ((Catalog::gSurfT[ld] > 0.f) && (Catalog::gCostM[ld] > 0.f))
			gPfKillRef = Catalog::gSurfT[ld] / Catalog::gCostM[ld];
	}
	if (gPfKillRef <= 0.f)
		gPfKillRef = 0.08f;   // the measured light-tower figure, if the def is missing
	return gPfKillRef;
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

// Cover this def contributes at a point it reaches, in light-tower metal.
float PfTowerKill(int d)
{
	const float ref = PfKillRef();
	if (ref <= 0.f)
		return 0.f;
	float m = Catalog::gSurfT[d] / ref;
	// apex_def_alpha_w is a WEIGHT on the reference blow, not just a switch:
	// it was only ever tested > 0, so the dashboard knob could turn durability
	// off and could not tune it.
	{
		const float w = ai.GetTunable("apex_def_alpha_w", TUNE_DEF_ALPHA_W);
		const float a = PfAlphaRef() * w;
		const float hp = Catalog::gHealth[d];
		if ((w > 0.f) && (a > 0.f) && (hp > 0.f))
			m *= hp / (hp + a);
	}
	return m * ai.GetTunable("apex_def_trade", TUNE_DEF_TRADE);
}

//------------------------------------------------------------------------------
// THE REBUILD. Bounded by game time, not by callers: the defence price is asked
// once per builder election and the walk over every team unit is the single
// most expensive thing in the market (measured: want.protect at 9.2 ms per call
// by minute 19, growing superlinearly with base size).
//------------------------------------------------------------------------------
void PfRebuild()
{
	const float everyS = ai.GetTunable("apex_protect_field_s", TUNE_PROTECT_FIELD_S);
	const int every = int(((everyS > 0.1f) ? everyS : 2.f) * 30.f);
	if ((ai.frame - gPfAt) < every)
		return;
	gPfAt = ai.frame;
	const double _tPf = Perf::T0();

	gPfPos.resize(0);
	gPfWorth.resize(0);
	gPfIsMex.resize(0);
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
			gPfPos.insertLast(p);
			gPfWorth.insertLast(Catalog::gCostM[d]);
			gPfIsMex.insertLast(false);
			gPfTotal += Catalog::gCostM[d];
		}
	}
	for (uint i = 0; i < gLPos.length(); ++i) {
		if (gLExtract[i] <= 0.f)
			continue;
		const float w = gLIncome[i] * IncomeMult() * gLExtract[i] * h;
		gPfPos.insertLast(gLPos[i]);
		gPfWorth.insertLast(w);
		gPfIsMex.insertLast(true);
		gPfTotal += w;
	}

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
			// One smoothing pass, so a bearing that happens to hold nothing
			// does not punch a notch into the perimeter.
			array<float> sm = gPfRimR;
			for (int b = 0; b < PF_RAYS; ++b) {
				const int lo = (b + PF_RAYS - 1) % PF_RAYS;
				const int hi = (b + 1) % PF_RAYS;
				float nb = (gPfRimR[lo] > gPfRimR[hi]) ? gPfRimR[lo] : gPfRimR[hi];
				nb *= 0.85f;
				if (nb > sm[b])
					sm[b] = nb;
			}
			gPfRimR = sm;
			gPfRimOk = true;
		}
	}

	gPfTwPos.resize(0);
	gPfTwReach.resize(0);
	gPfTwKill.resize(0);
	for (uint i = 0; i < gProtPos[PROT_DEF].length(); ++i) {
		const int d = gProtDefId[PROT_DEF][i];
		const float r = Catalog::gMaxRange[d];
		if (r <= 1.f)
			continue;
		gPfTwPos.insertLast(gProtPos[PROT_DEF][i]);
		gPfTwReach.insertLast(r);
		gPfTwKill.insertLast(PfTowerKill(d));
	}
	Perf::Add("prot.field", _tPf);
}

// Everything of ours inside r of pos, in metal. The stake, over every building
// rather than over three classes of them.
float PfStakeAt(const AIFloat3& in pos, float r)
{
	PfRebuild();
	float m = 0.f;
	for (uint i = 0; i < gPfPos.length(); ++i) {
		if (gPfPos[i].distance2D(pos) < r)
			m += gPfWorth[i];
	}
	return m;
}

// Standing cover at a point, in light-tower metal, optionally with one extra
// turret standing at extraAt.
float PfCoverPoint(const AIFloat3& in at, const AIFloat3& in extraAt,
		float extraReach, float extraKill)
{
	float m = 0.f;
	for (uint i = 0; i < gPfTwPos.length(); ++i) {
		if (gPfTwPos[i].distance2D(at) <= gPfTwReach[i])
			m += gPfTwKill[i];
	}
	if ((extraReach > 0.f) && (extraAt.distance2D(at) <= extraReach))
		m += extraKill;
	return m;
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
	const AIFloat3 foeAt = aiEnemyMgr.GetEnemyPos();
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
