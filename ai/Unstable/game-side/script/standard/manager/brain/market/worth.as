namespace Market {
//------------------------------------------------------------------------------
// WHAT A COMBAT UNIT IS WORTH -- one function, weighted by exponent.
//
// apexearth 2026-08-25: "We don't seem to value range and damage enough, maybe
// not AOE effects enough... RANGE, DAMAGE, HP. These are the golden metrics."
//
// Every metric is normalised by the mean over the GAME's own mobile combat
// units, so the exponents are scale-free and no divisor has to be invented.
// The exponents are tunables: this file states the shape of the answer, and
// which algorithm we are actually running is an experiment, not a decree.
//------------------------------------------------------------------------------

// Means over the field, not over what we own -- a mean taken over an empty
// army calls everything average. Never latch a zero: availability is
// frame-dependent, so recompute until the field is non-empty (BestConvRatio,
// LineMeans, same rule).
float gWMDps = -1.f, gWMAlpha = 0.f, gWMHp = 0.f, gWMRng = 0.f, gWMAoe = 0.f, gWMCost = 0.f;

// NOTHING WE CANNOT BUILD BELONGS IN THE YARDSTICK.
//
// apexearth: "Well the defs shouldn't show things we can't even use, right???"
// -- and he is right. gAvailable is `maxThisUnit > 0`, which is the GAME's
// permission, not ours: critters and Scavenger units pass it while no factory
// we could ever own produces them. Measured, the worth ranking's top twelve
// held critter_penguinking (20,000 metal), corblackhy (21,000), corprince and
// two drones, and the means every real unit is normalised against were
// dps=256.4 and hp=7,741 -- inflated by units that are not in the game we
// play, which shifts every score in the model.
//
// Producible is the honest test: something builds it. A critter is spawned by
// the map and a drone by its parent unit, so neither appears in any
// buildoptions list.
// gBuiltBy alone was not enough: it drops critters and drones (nothing lists
// them) but keeps SCAVENGER units, which have their own factories in the def
// tree and so are "built by something" -- corblackhy at 21,000 metal still
// ranked 5th, and the range mean was still being set by guns we will never
// own. The honest test is reachability from OUR OWN commander: breadth-first
// over buildoptions, so a def counts only if a chain of things we can build
// leads to it.
array<bool> gOurTree;
bool gOurTreeOk = false;

void BuildOurTree()
{
	if (gOurTreeOk)
		return;
	gOurTree.resize(Catalog::gDefCount + 1);
	for (int i = 0; i <= Catalog::gDefCount; ++i)
		gOurTree[i] = false;
	array<int> queue;
	// Seed: everything we actually own right now. The commander is there from
	// frame 0, and anything gifted or captured legitimately joins the tree.
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		if ((gOwnCount[d] > 0) && !gOurTree[int(d)]) {
			gOurTree[int(d)] = true;
			queue.insertLast(int(d));
		}
	}
	if (queue.length() == 0)
		return;   // nothing owned yet: ask again next call
	for (uint qi = 0; qi < queue.length(); ++qi) {
		const array<int>@ b = Catalog::gBuildsList[queue[qi]];
		for (uint i = 0; i < b.length(); ++i) {
			const int nd = b[i];
			if (!gOurTree[nd] && Catalog::gAvailable[nd]) {
				gOurTree[nd] = true;
				queue.insertLast(nd);
			}
		}
	}
	gOurTreeOk = true;
}

bool Producible(int di)
{
	BuildOurTree();
	if (!gOurTreeOk)
		return Catalog::gBuiltBy[di].length() > 0;   // pre-seed fallback
	return gOurTree[di];
}

bool WorthScorable(int di)
{
	return Catalog::gMobile[di] && !Catalog::gBuilder[di]
		&& (Catalog::gPower[di] > 1.f) && (Catalog::gCostM[di] > 0.f)
		&& (Catalog::gHealth[di] > 0.f) && !Catalog::gKamikaze[di]
		&& Producible(di);
}

void WorthMeans()
{
	if (gWMDps > 0.f)
		return;
	// Not before the build tree is known, or the means latch on the fallback.
	BuildOurTree();
	if (!gOurTreeOk) {
		gWMDps = -1.f;
		return;
	}
	float dp = 0.f, al = 0.f, hp = 0.f, rr = 0.f, ao = 0.f, cm = 0.f;
	int n = 0;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!Catalog::gAvailable[d] || !WorthScorable(d))
			continue;
		dp += Catalog::gDps[d];
		al += Catalog::gAlpha[d];
		hp += Catalog::gHealth[d];
		rr += Catalog::gMaxRange[d];
		ao += Catalog::gAoe[d];
		cm += Catalog::gCostM[d];
		++n;
	}
	if ((n <= 0) || (dp <= 0.f)) {
		gWMDps = -1.f;   // not yet knowable; ask again next call
		return;
	}
	gWMDps = dp / float(n);
	gWMAlpha = al / float(n);
	gWMHp = hp / float(n);
	gWMRng = rr / float(n);
	gWMAoe = ao / float(n);
	gWMCost = cm / float(n);
}

// REACH YOU CANNOT LAND ON A MOVER IS REACH AGAINST BUILDINGS (apexearth,
// reading the reach class: "those reach units were probably the terribly
// inaccurate rocket launcher dudes... they're only good vs structures").
// An unguided rocket flies where it was pointed; a cannon shell is aimed with
// lead and a tracking missile steers.
//
// CLASSIFICATION ONLY. Discounting this in the PRICE as well was measured worse
// on every counter (10 games: army 17.1% -> 12.5%, built 142k -> 85k): the
// discount also drags the field's range reference down, which pushes the same
// units back into MID and re-saturates the class the correction just emptied.
// What the evidence supports is narrower -- a dumb rocket is not a REACH unit --
// and its combat worth is left exactly as the stats state it.
float ClassRange(int d)
{
	if (!Catalog::gDumbFire[d])
		return Catalog::gMaxRange[d];
	return Catalog::gMaxRange[d] * ai.GetTunable("apex_aim_miss", TUNE_AIM_MISS);
}

// A def's own worth multiplier. The hardcoded table is the DEFAULT, so a game
// that sets nothing behaves exactly as before; the per-def tunable is the
// "force build what I say is best" lever, and reaches every unit in the game
// without a code edit. Read lazily -- GetTunable caches its first answer for
// the whole game, including a miss, and the gadget publishes after init.
array<float> gWorthMod;
float WorthModOf(int d)
{
	if (int(gWorthMod.length()) <= Catalog::gDefCount)
		gWorthMod.resize(Catalog::gDefCount + 1);
	if (gWorthMod[d] > 0.f)
		return gWorthMod[d];
	const string nm = Catalog::Def(d).GetName();
	const float v = ai.GetTunable("apex_worth_" + nm, UnitWorthMod(nm));
	gWorthMod[d] = (v > 0.f) ? v : 0.0001f;
	return gWorthMod[d];
}

// behaviour.json's "power" key hand-corrects a def the raw stats misread, and
// the DLL applies it to `power` only -- so a score rebuilt from dps/alpha/hp
// would silently discard it (22 defs here: armvader x100, armthor x0.1,
// corak x0.9). Recovered as the ratio between the fused number and its own
// inputs, which is exactly the override and nothing else.
float PowerMod(int d)
{
	const float base = Catalog::gDps[d] * sqrt(Catalog::gAlpha[d])
			* Catalog::gHealth[d] / 16384.f;   // THREAT_MOD = 1/128, squared
	// Only a MISSING basis falls back to 1. A small ratio is a real override
	// -- a commander's power is modded to nearly nothing -- and snapping that
	// up to 1 turns a def the old score called worthless into a top pick.
	if (base <= 0.0001f)
		return 1.f;
	return Catalog::gCombat[d] / base;
}

// RANGE ANSWERS RANGE (apexearth: banishers outranged and killed our T1 too
// easily). Enemy skirm and arty mass is outranging pressure: reach above the
// field mean gains by it, reach below fades. Reactive, on top of whatever
// standing preference apex_worth_range expresses.
float OutrangeMul(int d)
{
	// MY SHARE of the outranging census -- side-wide, it saturated the
	// pressure at 1.0 for every ally in any team game.
	const float outP = (Military::EnemyCostOf(Unit::Role::SKIRM.type)
			+ Military::EnemyCostOf(Unit::Role::ARTY.type))
			* AnswerShare() / 3000.f;
	const float oP = (outP > 1.f) ? 1.f : outP;
	if (oP <= 0.05f)
		return 1.f;
	const float rNorm = (Catalog::gMaxRange[d] - gWMRng) / gWMRng;
	float rMul = 1.f + rNorm * oP * 1.2f;
	if (rMul < 0.3f)
		rMul = 0.3f;
	if (rMul > 2.5f)
		rMul = 2.5f;
	return rMul;
}

// A LOWER TIER IS WORTH LESS AGAINST A HIGHER ONE (apexearth: "T3 units make
// T2 units much less useful. We should want less and less T2 units and labs
// when enemy has higher tier units"). Continuous in the share of identified
// enemy metal that outranks this def's own tier, and it never reaches zero --
// a fielded T1 still shoots. 0 is the control arm.
float FoeTierMul(int d)
{
	const float k = ai.GetTunable("apex_foe_tier_fade", TUNE_FOE_TIER_FADE);
	if (k <= 0.f)
		return 1.f;
	return 1.f / (1.f + k * Military::FoeTierAbove(DefTier(d)));
}

// ...AND AGAINST OUR OWN ECONOMY'S TIER (apexearth 2026-08-27: "In late game,
// aside from spam we should mostly only be putting our resources into T3
// units and advanced air units. I still see us making T1 hover units and they
// aren't worth the time/effort. If anything they just make more lag").
// Continuous in how far the best line we FIELD outranks this def's tier --
// once a gantry stands, T1 metal is metal the T3 line wanted. Spam is exempt
// by his ruling: cheap fast bodies keep their coverage job at any stage.
int gTopTier = 1;
int gTopTierAt = -1;
int TopOwnPlantTier()
{
	if (ai.frame < gTopTierAt)
		return gTopTier;
	gTopTierAt = ai.frame + 10 * SECOND;
	gTopTier = 1;
	for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
		CCircuitUnit@ f = Factory::gFacUnits[fi];
		if ((f is null) || (f.circuitDef is null))
			continue;
		const int at = Factory::userData[int(f.circuitDef.id)].attr;
		if (((at & Factory::Attr::T3) != 0) && (gTopTier < 3))
			gTopTier = 3;
		else if (((at & Factory::Attr::T2) != 0) && (gTopTier < 2))
			gTopTier = 2;
	}
	return gTopTier;
}

float OwnTierMul(int d)
{
	const float k = ai.GetTunable("apex_own_tier_fade", TUNE_OWN_TIER_FADE);
	if (k <= 0.f)
		return 1.f;
	// ONE FODDER BAR, not two. This read apex_spam_cost (150) while the
	// military routing read apex_fodder_cost (100) for the same idea, and 150
	// exempted exactly the units apexearth wants gone: "we're still making
	// thugs, rocket bots, which at the T2 stage become super duper
	// worthless... Grunts are still good because they are just fodder (rascal
	// vehicle scouts too)." Rocko 120 and Hammer 130 sat under the old bar and
	// so never faded; Grunt 42, Rascal 31 and Pawn 54 sit under the shared one
	// and still do. His spec draws the line between those two groups, and
	// unifying the bars is what puts it there.
	if (Catalog::gCostM[d] < Military::FODDER_COST())
		return 1.f;
	const int above = TopOwnPlantTier() - DefTier(d);
	if (above <= 0)
		return 1.f;
	return 1.f / (1.f + k * float(above));
}

// Once a T2 plant stands no T1 ground unit is made, fodder included -- the
// count is the lag (apexearth 2026-09-27). A drop, not a price:
// OwnTierMul only reorders a lab whose whole list is one tier, so the T1 lab
// still made 367 Thugs at T3. Ground AA is left alone -- it answers air.
// Only a LAND plant replaces the T1 ground line: an advanced air plant or
// shipyard is T2 too, and counting it would leave no ground army at all.
int gTopLandTier = 1;
int gTopLandTierAt = -1;
int TopOwnLandPlantTier()
{
	if (ai.frame < gTopLandTierAt)
		return gTopLandTier;
	gTopLandTierAt = ai.frame + 10 * SECOND;
	gTopLandTier = 1;
	for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
		CCircuitUnit@ f = Factory::gFacUnits[fi];
		if ((f is null) || (f.circuitDef is null))
			continue;
		const int fd = int(f.circuitDef.id);
		if (PlantClass(fd) != PC_LAND)
			continue;
		const int at = Factory::userData[fd].attr;
		if (((at & Factory::Attr::T3) != 0) && (gTopLandTier < 3))
			gTopLandTier = 3;
		else if (((at & Factory::Attr::T2) != 0) && (gTopLandTier < 2))
			gTopLandTier = 2;
	}
	return gTopLandTier;
}

int gTopWaterTier = 1;
int gTopWaterTierAt = -1;
int TopOwnWaterPlantTier()
{
	if (ai.frame < gTopWaterTierAt)
		return gTopWaterTier;
	gTopWaterTierAt = ai.frame + 10 * SECOND;
	gTopWaterTier = 1;
	for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
		CCircuitUnit@ f = Factory::gFacUnits[fi];
		if ((f is null) || (f.circuitDef is null))
			continue;
		const int fd = int(f.circuitDef.id);
		if ((PlantClass(fd) == PC_WATER) && (LineTier(fd) > gTopWaterTier))
			gTopWaterTier = LineTier(fd);
	}
	return gTopWaterTier;
}

// A ground scout that is not also a raider.
bool IsLateScout(int d)
{
	if (!Catalog::ValidId(d) || !Catalog::gMobile[d] || Catalog::gFlyer[d]
		|| Catalog::gBuilder[d])
		return false;
	const CCircuitDef@ cd = Catalog::Def(d);
	return (cd !is null) && cd.IsRoleAny(Unit::Role::SCOUT.mask)
		&& !cd.IsRoleAny(Unit::Role::RAIDER.mask);
}

// Ground scouts standing plus queued, capped like rez bots and constructors.
int ScoutFleetHave()
{
	int n = 0;
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		if (IsLateScout(int(d)))
			n += gOwnCount[d] + Brain::PendAnyOf(int(d));
	}
	return n;
}

bool Outgrown(int d)
{
	const int top = TopOwnPlantTier();
	if ((top < 2) || Catalog::gFlyer[d])
		return false;
	if ((Catalog::gAirT[d] > 0.f) && (Catalog::gSurfT[d] <= 0.f))
		return false;
	const int tier = DefTier(d);
	// A land lab replaces nothing on the water: a ship waits for our T2 yard.
	if (Catalog::gFloater[d] || Catalog::gSub[d])
		return TopOwnWaterPlantTier() > tier;   // no gantry unit replaces a ship
	if ((tier == 1) && SurfaceCrosser(d))
		return false;
	// Scouts are exempt (his ruling 2026-09-29): they keep taking fire while
	// the army attacks. T1 raiders are not.
	if ((tier == 1) && IsLateScout(d))
		return false;
	// T2 is not stopped by T3 (his 2026-09-29): fewer of them, through the
	// gantry's yield and OwnTierMul, never none.
	if (tier == 1)
		return TopOwnLandPlantTier() >= 2;
	return false;
}

// The score. Raw, before any of the situational multipliers -- this is what
// normalizes the line, so it must not carry anything that varies per election.
//
// THE COST EXPONENT IS A CHOICE OF LANCHESTER LAW, not a taste for expensive
// things. gCombat is quadratic in quality (dps and hp both rise with cost), so
// combat/cost rises with cost. The caller divides by cost once more, making the
// total power of cost 1 + apex_worth_cost: at 1 that is cost^2, the LINEAR law
// where bodies trade one for one and chaff wins; at 0 it is cost^1, the SQUARE
// law where a massed army fires at once and quality wins superlinearly.
array<float> gUcRaw;
float UnitCoreRaw(int d)
{
	WorthMeans();
	if (gWMDps <= 0.f)
		return Catalog::gCombat[d] / Catalog::gCostM[d];
	// Catalog stats over means latched for the game: one answer per def.
	if (int(gUcRaw.length()) <= Catalog::gDefCount) {
		gUcRaw.resize(Catalog::gDefCount + 1);
		for (uint i = 0; i < gUcRaw.length(); ++i)
			gUcRaw[i] = -1.f;
	}
	if (gUcRaw[d] < 0.f)
		gUcRaw[d] = UnitCoreRawCalc(d);
	return gUcRaw[d];
}

float UnitCoreRawCalc(int d)
{
	float v = 1.f;
	const float wDps = ai.GetTunable("apex_worth_dps", TUNE_WORTH_DPS);
	const float wAlpha = ai.GetTunable("apex_worth_alpha", TUNE_WORTH_ALPHA);
	const float wHp = ai.GetTunable("apex_worth_hp", TUNE_WORTH_HP);
	const float wRng = ai.GetTunable("apex_worth_range", TUNE_WORTH_RANGE);
	const float wAoe = ai.GetTunable("apex_worth_aoe", TUNE_WORTH_AOE);
	const float wCost = ai.GetTunable("apex_worth_cost", TUNE_WORTH_COST);
	if (wDps != 0.f)
		v *= pow(Catalog::gDps[d] / gWMDps, wDps);
	if (wAlpha != 0.f)
		v *= pow(Catalog::gAlpha[d] / gWMAlpha, wAlpha);
	if (wHp != 0.f)
		v *= pow(Catalog::gHealth[d] / gWMHp, wHp);
	if (wRng != 0.f)
		v *= pow(Catalog::gMaxRange[d] / gWMRng, wRng);
	// 1 + share, not a bare power: aoe == 0 is a real value for most units and
	// must not zero the product.
	if ((wAoe != 0.f) && (gWMAoe > 0.f))
		v *= pow(1.f + Catalog::gAoe[d] / gWMAoe, wAoe);
	if (wCost != 0.f)
		v /= pow(Catalog::gCostM[d] / gWMCost, wCost);
	return v * PowerMod(d);
}

// A DEF THE MODEL HAS NO EVIDENCE ABOUT IS PRICED AT ITS CLASS, NOT AT ITS
// STATS -- the fallback RecordRatioVs already applies to a matchup with no
// history, moved onto the SCORE, because the record cannot reach a def nobody
// has fought with yet. docs/27 `TUNE_EVIDENCE_SHRINK` has the measurement.
//
// Median and interquartile range, never a mean and a deviation: a mean over a
// population containing the outlier is the outlier's own average, which is the
// argument this file's header already makes about the field means. Both are
// static, so the table is built once.
array<float> gEvidCeil;
array<float> gEvidSig;
bool gEvidStatsOk = false;

void EvidenceStats()
{
	if (gEvidStatsOk)
		return;
	WorthMeans();
	if (gWMDps <= 0.f)
		return;
	gEvidCeil.resize(LC_N);
	gEvidSig.resize(LC_N);
	array<array<float>> byCls(LC_N);
	for (int i = 1; i <= Catalog::gDefCount; ++i) {
		if (!Catalog::ValidId(i) || !Catalog::gAvailable[i] || !WorthScorable(i))
			continue;
		byCls[LineClassOf(i)].insertLast(UnitCoreRaw(i));
	}
	int filled = 0;
	for (int c = 0; c < LC_N; ++c) {
		gEvidCeil[c] = 0.f;
		gEvidSig[c] = 0.f;
		const uint n = byCls[c].length();
		if (n < 8)
			continue;
		byCls[c].sortAsc();
		// IQR / 1.349 is the normal-distribution equivalent of a standard
		// deviation; nothing here is a chosen number.
		const float sig = (byCls[c][(n * 3) / 4] - byCls[c][n / 4]) / 1.349f;
		if (sig <= 0.f)
			continue;
		gEvidCeil[c] = byCls[c][n / 2] + sig;
		gEvidSig[c] = sig;
		++filled;
	}
	// Before LineMeans() can answer, LineClassOf calls everything LC_MID and
	// three of the four buckets are empty -- latching there would fix every
	// class's reference to the one that happened to be filled.
	if (filled >= 2)
		gEvidStatsOk = true;
}

array<float> gEvidKeep;
array<float> gEvidKeepLog;
int gEvidKeepAt = -999999;

float EvidenceShrink(int d, float core)
{
	const float k = ai.GetTunable("apex_evidence_shrink", TUNE_EVIDENCE_SHRINK);
	if ((k <= 0.f) || (core <= 0.f))
		return core;
	EvidenceStats();
	if (!gEvidStatsOk)
		return core;
	if (int(gEvidKeep.length()) <= Catalog::gDefCount) {
		gEvidKeep.resize(Catalog::gDefCount + 1);
		gEvidKeepLog.resize(Catalog::gDefCount + 1);
	}
	if (ai.frame >= gEvidKeepAt + 30 * SECOND) {
		gEvidKeepAt = ai.frame;
		for (int i = 0; i <= Catalog::gDefCount; ++i)
			gEvidKeep[i] = 0.f;   // 0 = not yet answered this window
	}
	float keep = gEvidKeep[d];
	if (keep == 0.f) {
		const int c = LineClassOf(d);
		const float cl = gEvidCeil[c];
		const float sig = gEvidSig[c];
		if ((sig <= 0.f) || (core <= cl)) {
			gEvidKeep[d] = 1.f;   // inside its class's own spread: ordinary
			return core;
		}
		// Evidence is the record's own count -- A-equivalents of metal lost --
		// against the prior the matrix already weighs a matchup by, so a type
		// earns its stats back at exactly the rate the record trusts them.
		const CCircuitDef@ cdef = Catalog::Def(d);
		const float prior = ai.GetTunable("apex_record_prior", 10.f);
		const float n = float(ai.RecordCount(cdef, -1));
		const float w = ((n + prior) > 0.f) ? (n / (n + prior)) : 0.f;
		const float over = (core - cl) / sig;
		keep = w + (1.f - w) / (1.f + over);
		keep = 1.f - k * (1.f - keep);
		// Never exactly zero: 0 is the "not answered this window" sentinel, and
		// pow(x, 0.001) is the full collapse to the ceiling anyway.
		if (keep < 0.001f)
			keep = 0.001f;
		if (keep > 1.f)
			keep = 1.f;
		gEvidKeep[d] = keep;
		if (abs(keep - gEvidKeepLog[d]) > 0.02f) {
			gEvidKeepLog[d] = keep;
			AiLog(Factory::T() + "apex: evidence " + cdef.GetName()
				+ " keep=" + formatFloat(keep, "", 0, 3)
				+ " core=" + formatFloat(core, "", 0, 4)
				+ " -> " + formatFloat(cl * pow(core / cl, keep), "", 0, 4)
				+ " ceil=" + formatFloat(cl, "", 0, 4)
				+ " sig=" + formatFloat(sig, "", 0, 4)
				+ " over=" + formatFloat(over, "", 0, 1)
				+ " n=" + int(n) + " cls=" + c);
		}
	}
	if (keep >= 1.f)
		return core;
	const float cl2 = gEvidCeil[LineClassOf(d)];
	if (core <= cl2)
		return core;
	return cl2 * pow(core / cl2, keep);
}

float UnitCore(int d)
{
	return EvidenceShrink(d, UnitCoreRaw(d));
}

// ...and with the per-election terms the candidate is judged on. The line
// normalizer uses UnitCore, the candidate uses this, which is what lets the
// ratio exceed 1 -- the same asymmetry the raw gCombat/linePPC pair had.
// WHAT A BODY IS WORTH IN A FIGHT, no metal in it (apexearth: "value himself
// based on what we perceive his power to be from his hp, range, dps, speed...
// and we should value enemies like this too, not based on metal"). The same
// metrics and exponents as UnitCore, minus the cost divisor, times the
// production line's speed term. 1.0 is the game's average mobile combat unit.
float UnitStrength(int d)
{
	WorthMeans();
	if (gWMDps <= 0.f)
		return Catalog::gCombat[d];
	float v = 1.f;
	const float wDps = ai.GetTunable("apex_worth_dps", TUNE_WORTH_DPS);
	const float wAlpha = ai.GetTunable("apex_worth_alpha", TUNE_WORTH_ALPHA);
	const float wHp = ai.GetTunable("apex_worth_hp", TUNE_WORTH_HP);
	const float wRng = ai.GetTunable("apex_worth_range", TUNE_WORTH_RANGE);
	const float wAoe = ai.GetTunable("apex_worth_aoe", TUNE_WORTH_AOE);
	if (wDps != 0.f)
		v *= pow(Catalog::gDps[d] / gWMDps, wDps);
	if (wAlpha != 0.f)
		v *= pow(Catalog::gAlpha[d] / gWMAlpha, wAlpha);
	if (wHp != 0.f)
		v *= pow(Catalog::gHealth[d] / gWMHp, wHp);
	if (wRng != 0.f)
		v *= pow(Catalog::gMaxRange[d] / gWMRng, wRng);
	if ((wAoe != 0.f) && (gWMAoe > 0.f))
		v *= pow(1.f + Catalog::gAoe[d] / gWMAoe, wAoe);
	v *= 1.f + (Catalog::gSpeed[d] / FoeSpeedCap())
			* ai.GetTunable("apex_speed_worth", TUNE_SPEED_WORTH);
	return v * PowerMod(d);
}

// An enemy group's strength: its visible members, each by UnitStrength.
float EnemyGroupStrength(int gi)
{
	float s = 0.f;
	const int n = aiEnemyMgr.GetEnemyGroupUnitCount(gi);
	for (int k = 0; k < n; ++k) {
		const int d = aiEnemyMgr.GetEnemyGroupUnitDef(gi, k);
		if ((d > 0) && (d <= Catalog::gDefCount) && Catalog::gMobile[d]
			&& (Catalog::gPower[d] > 1.f))
			s += UnitStrength(d);
	}
	return s;
}

// Strength per metal on each side, so a metal comparison becomes a strength
// one (apexearth: "compare strength"). A side with nothing fielded reads
// as the other side's quality, and both empty leaves the metal ratio alone.
int gQualAt = -1;
float gFoeQual = 0.f;
float gOurQual = 0.f;
bool QualityDef(int d)
{
	return (d > 0) && (d <= Catalog::gDefCount) && Catalog::gMobile[d]
		&& !Catalog::gBuilder[d] && (Catalog::gPower[d] > 1.f)
		&& (Catalog::gCostM[d] > 0.f);
}
void UpdateQuality()
{
	if (ai.frame - gQualAt < 5 * SECOND)
		return;
	gQualAt = ai.frame;
	float oS = 0.f, oM = 0.f;
	const array<int>@ _own49 = OwnedDefs();
	for (uint _oi49 = 0; _oi49 < _own49.length(); ++_oi49) {
		const uint d = uint(_own49[_oi49]);
		if ((gOwnCount[d] <= 0) || !QualityDef(int(d)))
			continue;
		oS += float(gOwnCount[d]) * UnitStrength(int(d));
		oM += float(gOwnCount[d]) * Catalog::gCostM[d];
	}
	float fS = 0.f, fM = 0.f;
	const int nG = aiEnemyMgr.GetEnemyGroupCount();
	for (int gi = 0; gi < nG; ++gi) {
		const int n = aiEnemyMgr.GetEnemyGroupUnitCount(gi);
		for (int k = 0; k < n; ++k) {
			const int d = aiEnemyMgr.GetEnemyGroupUnitDef(gi, k);
			if (!QualityDef(d))
				continue;
			fS += UnitStrength(d);
			fM += Catalog::gCostM[d];
		}
	}
	gOurQual = (oM > 0.f) ? oS / oM : 0.f;
	gFoeQual = (fM > 0.f) ? fS / fM : 0.f;
	if (gOurQual <= 0.f)
		gOurQual = (gFoeQual > 0.f) ? gFoeQual : 1.f;
	if (gFoeQual <= 0.f)
		gFoeQual = gOurQual;
}
float FoeQualityM() { UpdateQuality(); return gFoeQual; }
float OurQualityM() { UpdateQuality(); return gOurQual; }
// theirs/ours as strength, from the two metal totals.
float StrRatio(float theirsM, float oursM)
{
	if (theirsM <= 0.f)
		return 0.f;
	if (oursM <= 1.f)
		return 1e6f;
	return (theirsM * FoeQualityM()) / (oursM * OurQualityM());
}

// The hold multiplier, live only while ground is being lost; the tunable
// reaches every def the way apex_worth_<name> does.
array<float> gHoldMod;
float HoldModOf(int d)
{
	if (!(Military::LosingGround() || Military::BaseContested()))
		return 1.f;
	if (int(gHoldMod.length()) <= Catalog::gDefCount)
		gHoldMod.resize(Catalog::gDefCount + 1);
	if (gHoldMod[d] > 0.f)
		return gHoldMod[d];
	const string nm = Catalog::Def(d).GetName();
	const float v = ai.GetTunable("apex_hold_" + nm, UnitHoldMod(nm));
	gHoldMod[d] = (v > 0.f) ? v : 1.f;
	return gHoldMod[d];
}

float UnitPPC(int d)
{
	float v = UnitCore(d) * WorthModOf(d) * HoldModOf(d);
	// REACH IS ONLY WORTH WHAT SOMETHING ELSE IS ABSORBING (apexearth: "low HP
	// units with more range... on their own they're garbage"). Scaled by the
	// share of our line that can stand in front, so reach pays exactly as much
	// as we have shield to buy it with.
	v *= 1.f + (Catalog::gMaxRange[d] / gWMRng)
			* ai.GetTunable("apex_range_worth", TUNE_RANGE_WORTH) * ShieldShare();
	// STANDOFF SURVIVABILITY: hit points are only worth paying for by a unit
	// that can actually be shot. apexearth 2026-08-30: "we outrange most of
	// what can shoot back at us and we have the speed to stay far enough
	// away... make HP matter less when range is higher."
	//
	// EXPOSURE is the share of the armed mobile field that can reach us, after
	// allowing for the two ways of not being reached: outrunning what outranges
	// us, or standing behind something that absorbs. PfOutrangedFrac is read
	// off the game's own range distribution, so the pivot is where the units
	// actually are and not a mean anybody chose.
	//
	// Applied in UnitPPC, NOT UnitCore. UnitCore normalises the line, so a
	// change there moves the candidate and the yardstick together -- three
	// attempts at this on 2026-08-30 did exactly that, and the last one took
	// reach from 0.19 to 0.03 of the army while tanks went to 0.65, because
	// scaling the hp EXPONENT by range hands the biggest bonus to whoever owns
	// the most hit points, which is the short-range brawlers. This form can
	// only ever DISCOUNT the hp term UnitCore already charged: at full exposure
	// it changes nothing at all.
	{
		const float wHp = ai.GetTunable("apex_worth_hp", TUNE_WORTH_HP);
		const float relHp = (gWMHp > 0.f) ? (Catalog::gHealth[d] / gWMHp) : 0.f;
		if ((wHp != 0.f) && (relHp > 0.f)) {
			float keep = ShieldShare();
			const float cap = FoeSpeedCap();
			if (cap > 1.f) {
				const float sp = Catalog::gSpeed[d] / cap;
				if (sp > keep)
					keep = (sp > 1.f) ? 1.f : sp;
			}
			float safe = PfOutrangedFrac(d) * keep;
			if (safe > 1.f)
				safe = 1.f;
			// ONLY A DISCOUNT, WHICH IS WHAT THE NOTE ABOVE ALREADY CLAIMS THIS
			// IS: "This form can only ever DISCOUNT the hp term UnitCore already
			// charged". That holds for relHp > 1 and inverts below it -- pow()
			// of a number under one is under one, and dividing by it MULTIPLIES.
			// So a unit with below-average hit points was not merely forgiven
			// its fragility, it was paid for it, and the bonus grew with speed
			// because `keep` rises with speed.
			//
			// Measured 2026-09-08 from a standing T2 bot lab, both units
			// available: Platypus (260m, 1170hp, speed 90) scored p=10.956
			// against Fatboy (1400m, 7800hp, speed 30) at p=0.120 -- 91x --
			// while their RAW power per metal is 0.034 against 0.029, a factor
			// of 1.2. apexearth: "we could have made a fatboy easily and kicked
			// the enemies butt but we made like 1 hound, then a fuckin platypus
			// which is USELESS here."
			if ((safe > 0.f) && (relHp > 1.f))
				v /= pow(relHp, wHp * safe);
		}
	}
	v *= OutrangeMul(d);
	v *= FoeTierMul(d);
	v *= OwnTierMul(d);
	v *= RecordMul(d);
	return v;
}

// THE TRACK RECORD (apexearth 2026-09-16): a type is bought at what it
// has actually traded, not what its stats promise -- a ranking around the
// army's mean, never a ban (the prior in the DLL keeps the floor at
// prior/(prior+window)). Fodder is bought to die and fighters are always
// needed, so neither is judged.
//
// READ AGAINST WHAT THEY FIELD (apexearth 2026-09-19: "if the enemy has
// Tzars or Fatboys ... I shouldn't be building crappy short-range units").
// The DLL keeps one bucket per (our type, what killed it) and weights them
// by the enemy attackers it currently knows of, by metal; a matchup with no
// deaths of its own reads as its killer's tier, then as the pool. The tier
// table is pushed once so the DLL can do that fallback.
// A TANK IS JUDGED AS A TANK (apexearth 2026-09-19: "it's supposed to take
// more damage, it's supposed to have a lower damage efficiency"). The bar a
// type must clear is what its own line class measurably achieves -- the
// deaths-weighted record of every scorable def in the class, shrunk toward
// 1 by the prior -- capped at 1 so dealing its own health is still the
// ceiling. Recomputed every 30 s.
array<float> gRecordBar;   // sized on first use: army.as's LC_N is declared later
int gRecordBarAt = -1;
float RecordBar(int cls)
{
	if (gRecordBar.length() == 0) {
		gRecordBar.resize(LC_N);
		for (int c = 0; c < LC_N; ++c)
			gRecordBar[c] = 1.f;
	}
	if ((gRecordBarAt >= 0) && (ai.frame < gRecordBarAt + 30 * SECOND))
		return gRecordBar[cls];
	gRecordBarAt = ai.frame;
	const float prior = ai.GetTunable("apex_record_prior", 10.f);
	array<float> num(LC_N, prior), den(LC_N, prior);
	for (int i = 1; i <= Catalog::gDefCount; ++i) {
		if (!Catalog::ValidId(i) || !Catalog::gAvailable[i] || !WorthScorable(i))
			continue;
		const CCircuitDef@ cd = Catalog::Def(i);
		const int n = ai.RecordCount(cd, -1);
		if (n <= 0)
			continue;
		const int c = LineClassOf(i);
		num[c] += float(n) * ai.RecordRatio(cd, -1);
		den[c] += float(n);
	}
	for (int c = 0; c < LC_N; ++c) {
		const float b = num[c] / den[c];
		gRecordBar[c] = (b < 1.f) ? b : 1.f;
	}
	return gRecordBar[cls];
}

// THE RECORD RANKS, IT DOES NOT SHRINK THE ARMY. A raw discount lowers a
// unit's worth, and worth is what army wants bid against economy and
// defence with -- measured 2026-09-20, 20 paired games: army metal -15%,
// metal -10%, D% worse in 16 of 20. So every multiplier is divided by the
// mean over the buildable army (recomputed every 30 s): the average price
// is unchanged and only the order moves.
float gRecordMean = 1.f;
int gRecordMeanAt = -1;
float RecordRaw(int d)
{
	const CCircuitDef@ cdef = Catalog::Def(d);
	if (Military::IsFodder(cdef)
		|| (cdef.IsAbleToFly() && cdef.IsRoleAny(Unit::Role::AA.mask)))
		return 1.f;
	const float bar = RecordBar(LineClassOf(d));
	// Uncapped (apexearth 2026-09-20: "we would prefer to try to use the
	// better units"): a type trading above its class bar prices above 1,
	// and the mean below holds the army's total worth where it was.
	return ai.RecordRatioMix(cdef) / ((bar > 0.01f) ? bar : 1.f);
}

float RecordMean()
{
	if ((gRecordMeanAt >= 0) && (ai.frame < gRecordMeanAt + 30 * SECOND))
		return gRecordMean;
	gRecordMeanAt = ai.frame;
	float sum = 0.f;
	int n = 0;
	for (int i = 1; i <= Catalog::gDefCount; ++i) {
		if (!Catalog::ValidId(i) || !Catalog::gAvailable[i] || !WorthScorable(i))
			continue;
		sum += RecordRaw(i);
		++n;
	}
	gRecordMean = (n > 0) ? (sum / float(n)) : 1.f;
	if (gRecordMean < 0.05f)
		gRecordMean = 0.05f;
	return gRecordMean;
}

bool gRecordTiersSet = false;
array<float> gRecordMulLast;
float RecordMul(int d)
{
	if (ai.GetTunable("apex_record_bite", TUNE_RECORD_BITE) <= 0.f)
		return 1.f;
	const CCircuitDef@ cdef = Catalog::Def(d);
	if (Military::IsFodder(cdef)
		|| (cdef.IsAbleToFly() && cdef.IsRoleAny(Unit::Role::AA.mask)))
		return 1.f;
	if (!gRecordTiersSet) {
		gRecordTiersSet = true;
		for (int i = 1; i <= Catalog::gDefCount; ++i)
			if (Catalog::ValidId(i))
				ai.RecordSetTier(Catalog::Def(i), DefTier(i));
	}
	const float bar = RecordBar(LineClassOf(d));
	const float m = RecordRaw(d) / RecordMean();
	// The proof that the record reaches a price: logged when it moves.
	if (int(gRecordMulLast.length()) <= Catalog::gDefCount)
		gRecordMulLast.resize(Catalog::gDefCount + 1);
	if ((gRecordMulLast[d] == 0.f) ? (abs(m - 1.f) > 0.05f) : (abs(m - gRecordMulLast[d]) > 0.05f)) {
		gRecordMulLast[d] = m;
		AiLog(Factory::T() + "apex: record-mul " + cdef.GetName() + " " + formatFloat(m, "", 0, 2)
			+ " raw=" + formatFloat(RecordRaw(d), "", 0, 2) + " mean=" + formatFloat(gRecordMean, "", 0, 2)
			+ " bar=" + formatFloat(bar, "", 0, 2) + " cls=" + LineClassOf(d)
			+ " pooled=" + formatFloat(ai.RecordRatio(cdef, -1), "", 0, 2)
			+ " n=" + ai.RecordCount(cdef, -1)
			+ " t1=" + formatFloat(ai.RecordRatio(cdef, 1), "", 0, 2)
			+ " t2=" + formatFloat(ai.RecordRatio(cdef, 2), "", 0, 2)
			+ " t3=" + formatFloat(ai.RecordRatio(cdef, 3), "", 0, 2));
	}
	return m;
}

// The cheapest measurement there is: what the current exponents actually rank,
// before a single game is spent finding out. apex_worth_diag=1 prints the
// exponents once; 2 also dumps every scorable def, sorted.
bool gWorthDiagDone = false;
void WorthDiag()
{
	const float lvl = ai.GetTunable("apex_worth_diag", TUNE_WORTH_DIAG);
	if ((lvl < 1.f) || gWorthDiagDone)
		return;
	WorthMeans();
	if (gWMDps <= 0.f)
		return;
	gWorthDiagDone = true;
	AiLog("apex: worth t=" + ai.teamId
		+ " dps=" + formatFloat(ai.GetTunable("apex_worth_dps", TUNE_WORTH_DPS), "", 0, 2)
		+ " alpha=" + formatFloat(ai.GetTunable("apex_worth_alpha", TUNE_WORTH_ALPHA), "", 0, 2)
		+ " hp=" + formatFloat(ai.GetTunable("apex_worth_hp", TUNE_WORTH_HP), "", 0, 2)
		+ " rng=" + formatFloat(ai.GetTunable("apex_worth_range", TUNE_WORTH_RANGE), "", 0, 2)
		+ " aoe=" + formatFloat(ai.GetTunable("apex_worth_aoe", TUNE_WORTH_AOE), "", 0, 2)
		+ " cost=" + formatFloat(ai.GetTunable("apex_worth_cost", TUNE_WORTH_COST), "", 0, 2)
		+ " | means dps=" + formatFloat(gWMDps, "", 0, 1)
		+ " alpha=" + formatFloat(gWMAlpha, "", 0, 1)
		+ " hp=" + formatFloat(gWMHp, "", 0, 0)
		+ " rng=" + formatFloat(gWMRng, "", 0, 0)
		+ " aoe=" + formatFloat(gWMAoe, "", 0, 1)
		+ " cost=" + formatFloat(gWMCost, "", 0, 0));
	if (lvl < 2.f)
		return;
	// Insertion sort into a bounded top list: the full field is ~250 defs and
	// only the head of the ranking answers "would this arm prefer a Tzar".
	array<int> top;
	array<float> topV;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!Catalog::gAvailable[d] || !WorthScorable(d))
			continue;
		const float s = UnitCore(d) * WorthModOf(d) * HoldModOf(d);
		uint at = topV.length();
		for (uint i = 0; i < topV.length(); ++i) {
			if (s > topV[i]) {
				at = i;
				break;
			}
		}
		if (at >= 40)
			continue;
		top.insertAt(at, d);
		topV.insertAt(at, s);
		if (top.length() > 40) {
			top.removeLast();
			topV.removeLast();
		}
	}
	for (uint i = 0; i < top.length(); ++i) {
		const int d = top[i];
		AiLog("apex: worth-rank " + (i + 1) + " " + Catalog::Def(d).GetName()
			+ " core=" + formatFloat(topV[i], "", 0, 4)
			+ " m=" + formatFloat(Catalog::gCostM[d], "", 0, 0)
			+ " dps=" + formatFloat(Catalog::gDps[d], "", 0, 1)
			+ " alpha=" + formatFloat(Catalog::gAlpha[d], "", 0, 0)
			+ " hp=" + formatFloat(Catalog::gHealth[d], "", 0, 0)
			+ " rng=" + formatFloat(Catalog::gMaxRange[d], "", 0, 0)
			+ " aoe=" + formatFloat(Catalog::gAoe[d], "", 0, 0));
	}
}

}  // namespace Market
