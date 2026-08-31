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

bool WorthScorable(int di)
{
	return Catalog::gMobile[di] && !Catalog::gBuilder[di]
		&& (Catalog::gPower[di] > 1.f) && (Catalog::gCostM[di] > 0.f)
		&& (Catalog::gHealth[di] > 0.f) && !Catalog::gKamikaze[di];
}

void WorthMeans()
{
	if (gWMDps > 0.f)
		return;
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

// The score. Raw, before any of the situational multipliers -- this is what
// normalizes the line, so it must not carry anything that varies per election.
//
// THE COST EXPONENT IS A CHOICE OF LANCHESTER LAW, not a taste for expensive
// things. gCombat is quadratic in quality (dps and hp both rise with cost), so
// combat/cost rises with cost. The caller divides by cost once more, making the
// total power of cost 1 + apex_worth_cost: at 1 that is cost^2, the LINEAR law
// where bodies trade one for one and chaff wins; at 0 it is cost^1, the SQUARE
// law where a massed army fires at once and quality wins superlinearly.
float UnitCore(int d)
{
	WorthMeans();
	if (gWMDps <= 0.f)
		return Catalog::gCombat[d] / Catalog::gCostM[d];
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

// ...and with the per-election terms the candidate is judged on. The line
// normalizer uses UnitCore, the candidate uses this, which is what lets the
// ratio exceed 1 -- the same asymmetry the raw gCombat/linePPC pair had.
float UnitPPC(int d)
{
	float v = UnitCore(d) * WorthModOf(d);
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
			if (safe > 0.f)
				v /= pow(relHp, wHp * safe);
		}
	}
	v *= OutrangeMul(d);
	v *= FoeTierMul(d);
	v *= OwnTierMul(d);
	return v;
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
		const float s = UnitCore(d) * WorthModOf(d);
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
