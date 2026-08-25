namespace Market {
//------------------------------------------------------------------------------
// The production market's first Want: one constructor at a time while open
// expansion ground remains. Serialized by the sent-ledger, never by a count.
//------------------------------------------------------------------------------

// A "T2 con" in play terms: a constructor whose build list reaches the best
// extractor the game offers. Tracks the CEILING rather than a tier name, so
// it moves with the game rather than with a hardcoded def.
bool ReachesCeiling(int defId)
{
	const float ceilM = BestExtract();
	if (ceilM <= 0.f)
		return false;
	const array<int>@ b = Catalog::gBuildsList[defId];
	for (uint q = 0; q < b.length(); ++q) {
		if (Catalog::gExtractsM[b[q]] >= ceilM)
			return true;
	}
	return false;
}

// THE COMMANDER IS NOT A CONSTRUCTOR FOR THIS PURPOSE. It is mobile, it is a
// builder, and it reaches the ceiling (it builds the T1 extractor), so it
// satisfied the floor on its own from frame zero: want = 1 + inc/25 is 1.4 at
// 10 metal/s, have = 1, so need came out 0 and the line ordered NOTHING until
// income passed 25 (apexearth, watched: "we aren't making early game
// constructors. We should have 2 or 3 constructors within the first 5
// minutes"). It also has its own job -- the opening, and it cannot be replaced
// if it dies working -- so counting it as one of the crew both hides the
// shortfall and puts it in the crowd.
int CeilingConsOwned()
{
	int n = 0;
	for (uint c = 1; c < gOwnCount.length(); ++c) {
		if ((gOwnCount[c] <= 0) || !Catalog::gMobile[int(c)]
			|| !Catalog::gBuilder[int(c)]
			|| Catalog::Def(int(c)).IsRoleAny(Unit::Role::COMM.mask))
			continue;
		if (ReachesCeiling(int(c)))
			n += gOwnCount[c];
	}
	return n;
}

// Ceiling cons ordered but not yet standing -- the factory queues plus the
// send-ledger. gOwnCount counts FINISHED units only, so without this the
// floor below re-orders for the whole build and lands a crowd.
int CeilingConsInFlight()
{
	int n = 0;
	for (uint i = 0; i < Brain::gFQPendDef.length(); ++i) {
		CCircuitDef@ pd = Brain::gFQPendDef[i];
		if ((pd !is null) && ReachesCeiling(int(pd.id)))
			++n;
	}
	for (uint f = 0; f < Factory::gFacUnits.length(); ++f) {
		CCircuitUnit@ fu = Factory::gFacUnits[f];
		if ((fu is null) || (fu.circuitDef is null))
			continue;
		const array<int>@ ps = Catalog::BuildsOf(int(fu.circuitDef.id));
		for (uint q = 0; q < ps.length(); ++q) {
			if (Catalog::gBuilder[ps[q]] && ReachesCeiling(ps[q]))
				n += fu.CountQueued(Catalog::Def(ps[q]));
		}
	}
	return n;
}

// EVERY CONSTRUCTOR WE OWN, ANY TIER, EXCLUDING THE COMMANDER.
//
// CeilingConsOwned above answers a narrower question -- cons that reach
// BestExtract(), which scans every available def and so means the MOHO. No T1
// con qualifies, and neither does the commander, so that floor is a T2-con
// floor exactly as its name says: measured firing at 9.5 minutes ordering an
// armack, never in the opening. Nothing anywhere asked for constructors as
// such, which is why the opening had none and whether a player got any early
// came down to the proportional draw (measured 3v3: two teams ordered armck at
// factory picks 1-2, the third at picks 5-6, and looked from outside like it
// never built them at all).
//
// The commander is excluded because it is not one of the crew -- it has the
// opening to run and cannot be replaced if it dies working.
int ConsOwnedAny()
{
	int n = 0;
	for (uint c = 1; c < gOwnCount.length(); ++c) {
		if ((gOwnCount[c] <= 0) || !Catalog::gMobile[int(c)]
			|| !Catalog::gBuilder[int(c)]
			|| Catalog::Def(int(c)).IsRoleAny(Unit::Role::COMM.mask))
			continue;
		n += gOwnCount[c];
	}
	return n;
}

// Ordered but not standing. gOwnCount counts FINISHED units, and an order is
// not applied on the frame it is issued, so without this the floor re-orders
// for the whole build and lands a crowd.
int ConsInFlightAny()
{
	int n = 0;
	for (uint i = 0; i < Brain::gFQPendDef.length(); ++i) {
		CCircuitDef@ pd = Brain::gFQPendDef[i];
		if ((pd !is null) && pd.IsMobile() && pd.IsBuilder()
			&& !pd.IsRoleAny(Unit::Role::COMM.mask))
			++n;
	}
	return n;
}

// THE CONSTRUCTOR FLOOR, from apexearth's own two readings: "at like 12 income
// we still want 2 or 3 cons... often I want 3 even at just 12 income" and "at
// 100 metal per second we should have at least 5". Those two points fix the
// line: 2.7 + inc/44 gives 3.0 at 12 m/s and 5.0 at 100. Not a cap -- nothing
// stops the auction buying more when they are worth more.
int ConsNeedAny()
{
	const float per = ai.GetTunable("apex_con_per_m", TUNE_CON_PER_M);
	const float want = ai.GetTunable("apex_con_base", TUNE_CON_BASE)
			+ aiEconomyMgr.metal.income / ((per > 1.f) ? per : 44.f);
	const int have = ConsOwnedAny() + ConsInFlightAny();
	return (float(have) < want) ? (int(want) - have) : 0;
}

// How far under the floor we are. The floor SCALES WITH INCOME -- one con
// plus one per 25 metal/s (apexearth 2026-08-23: "at 100 metal per second we
// should have at least 5"). Any lab qualifies: air, bot or vehicle cons all
// reach the ceiling, and the ReachesCeiling test is def-based, not lab-based.
int CeilingConsNeed()
{
	const float per = ai.GetTunable("apex_t2_con_per_m", TUNE_T2_CON_PER_M);
	const float want = ai.GetTunable("apex_t2_con_base", TUNE_T2_CON_BASE)
			+ aiEconomyMgr.metal.income / ((per > 1.f) ? per : 25.f);
	const int have = CeilingConsOwned() + CeilingConsInFlight();
	return (float(have) < want) ? (int(want) - have) : 0;
}

// Deep demand check for the facqueue's lookahead batch: six more of this
// def must still be justified by the gap (or the overflow sink).
bool BatchWorthy(CCircuitDef@ d)
{
	if ((d is null) || d.IsBuilder())
		return false;   // builders stay single: their demand saturates fast
	const int di = int(d.id);
	const float need = ArmyTarget() - ArmyValue();
	const float sink = OverflowM() * 60.f;
	const float deep = (need > sink) ? need : sink;
	return deep > 6.f * Catalog::gCostM[di];
}

CCircuitDef@ ConOrderFor(CCircuitUnit@ fac, int line)
{
	if (fac is null)
		return null;
	// Production pays the E-flow discipline too: a factory pumping pawns
	// through a stall both causes it and starves the opening (watched:
	// hard e-stall, a minute without a mex).
	if (HardEStall())
		return null;
	gEscortFloor = false;
	// THE ESCORT FLOOR, ahead of everything: a constructor working without a
	// guard is a write-off waiting to happen, and the cheapest answer costs a
	// few seconds of one line. It outranks the all-quiet gate and the
	// in-flight gate below -- like the con floor, this is a rule, not a bid,
	// and it self-limits to the number of unescorted workers.
	{
		CCircuitDef@ esc = EscortOrderFor(fac);
		if (esc !is null) {
			gEscortFloor = true;
			AiLog("apex: decide t=" + ai.teamId + " " + fac.circuitDef.GetName()
				+ " #" + fac.id + " -> produce:" + esc.GetName()
				+ " (escort floor short=" + EscortShortfall()
				+ " inflight=" + EscortInFlight(esc)
				+ " risk=" + formatFloat(EscortMetalAtRisk(), "", 0, 0) + ")");
			return esc;
		}
	}
	// The T2-con floor outranks the all-quiet gate: "at least 2" is not
	// contingent on there being other demand.
	const int ceilNeed = CeilingConsNeed();
	if ((ceilNeed <= 0) && !gMexOpen && (UpDemand() <= 0.5f) && (BPGap() <= 0.5f)
		&& (ArmyTarget() - ArmyValue() <= 0.5f))
		return null;
	// Two in flight per line: one building, one queued, so production is
	// continuous (one-at-a-time left the line idle between orders).
	if ((fac.CountQueued(null) + Brain::PendCount(line, null)) > 1)
		return null;
	const int fid = int(fac.circuitDef.id);
	const array<int>@ prods = Catalog::BuildsOf(fid);
	// Each product priced, best value ordered. A constructor's gain: the
	// tier-unique upgrade demand it unlocks, at DIMINISHING returns per con
	// already serving (the binary version stopped at exactly one T2 con);
	// plus its worth as mobile build power (overflow capture at its drain);
	// plus the open-spot stream if ground remains to claim.
	const float util = Utilization();
	const float over = BPGap() * util;
	const float upD = UpDemand();
	const float mobileCeil = OwnedMobileCeil();
	LossDecay();
	const float armyGap = ArmyTarget() - ArmyValue();
	const float fillS = ai.GetTunable("apex_army_fill_s", TUNE_ARMY_FILL_S);
	float roleMul = EcoRoleActive()
			? ai.GetTunable("apex_eco_army_mul", TUNE_ECO_ARMY_MUL) : 1.f;
	if ((roleMul < 1.f) && EcoDangerNear())
		roleMul = 1.f;
	// THE STAKE (apexearth 2026-08-23): "all the value we have built up will
	// be lost if we have insufficient army." Under-matched, a unit's worth
	// scales with EVERYTHING we own -- expected loss = total value x defeat
	// probability -- tapering to normal at parity. One modeled weight.
	float stakeMul = 1.f;
	{
		const float aT0 = ArmyTarget();
		if ((aT0 > 1.f) && (armyGap > 0.f)) {
			// Towers lighten the stake, but only LOCALLY (apexearth): static
			// defense standing in the core counts toward the army at an
			// immobility discount; a remote mex sentry defends its patch,
			// not the base.
			float coreStaticM = 0.f;
			if (gFarmSet) {
				for (uint sd2 = 0; sd2 < gProtUnit[PROT_DEF].length(); ++sd2) {
					if (gProtUnit[PROT_DEF][sd2] is null)
						continue;
					const AIFloat3 sp2 = gProtPos[PROT_DEF][sd2];
					if ((sp2.distance2D(gFarmPos) < 1200.f)
						|| (Base::gAnchorSet && (sp2.distance2D(Base::gAnchor) < 1200.f)))
						coreStaticM += Catalog::gCostM[gProtDefId[PROT_DEF][sd2]];
				}
			}
			const float lightened = armyGap - coreStaticM
					* ai.GetTunable("apex_static_guard", TUNE_STATIC_GUARD);
			const float effGapS = (lightened > 0.f) ? lightened : 0.f;
			const float deficit = effGapS / aT0;
			stakeMul = 1.f + deficit
					* ((gAssetsM + ArmyValue()) / aT0)
					* ai.GetTunable("apex_stake_weight", TUNE_STAKE_WEIGHT);
			if (stakeMul > 8.f)
				stakeMul = 8.f;
		}
	}
	// Best power-per-cost this line can produce, for normalizing army bids.
	float linePPC = 0.f;
	for (uint i = 0; i < prods.length(); ++i) {
		const int d = prods[i];
		if (!Catalog::gAvailable[d] || !Catalog::gMobile[d]
			|| Catalog::gBuilder[d] || (Catalog::gPower[d] <= 1.f)
			|| Catalog::gKamikaze[d])
			continue;
		const float ppc = Catalog::gCombat[d] / Catalog::gCostM[d];
		if (ppc > linePPC)
			linePPC = ppc;
	}
	// PROPORTIONAL DRAW, not argmax: a persistent 10% price edge under
	// winner-take-all became 29 cons and zero army from a vehicle lab
	// (measured, ladder t001) -- the same lesson the old Brain's roulette
	// carved into project memory. Candidates weight by value.
	array<int> candDef;
	array<float> candV;
	array<float> candGain;
	float sumV = 0.f;
	int best = -1;
	float bestV = 0.f;
	float bestGain = 0.f;
	for (uint i = 0; i < prods.length(); ++i) {
		const int d = prods[i];
		if (!Catalog::gAvailable[d] || !Catalog::gMobile[d])
			continue;
		// SUPPORT: mobile eyes and static-cover. One radar and one jammer
		// per ~squad's worth of fielded army (apexearth: "ideally we attach
		// 1 of each to each squad"); attachment is the military layer's,
		// production is ours.
		if (Catalog::gMobile[d] && !Catalog::gBuilder[d]
			&& (Catalog::gRadar[d] || Catalog::gJammer[d]))
		{
			const int haveS = (int(d) < int(gOwnCount.length())) ? gOwnCount[d] : 0;
			if (ai.frame >= gSupportDiagAt) {
				gSupportDiagAt = ai.frame + 120 * SECOND;
				AiLog("apex: support-diag t=" + ai.teamId + " def="
					+ Catalog::Def(d).GetName() + " have=" + haveS
					+ " army=" + formatFloat(ArmyValue(), "", 0, 0)
					+ " land=" + formatFloat(aiTerrainMgr.GetLandPercent(), "", 0, 2));
			}
			// One radar + one jammer per squad's worth of army (apexearth:
			// "those should have boosted priority... support squads which
			// are ~2k metal value or higher"). A pair's worth is a fraction
			// of the squad value it serves per minute -- which prices them
			// just behind constructors, scaling with the army, no caps.
			const float squadM = ai.GetTunable("apex_squad_m", TUNE_SQUAD_M);
			const float squads = ArmyValue() / ((squadM > 1.f) ? squadM : 2000.f);
			if (float(haveS) < squads) {
				const float gainS = (squads - float(haveS)) * squadM
						* ai.GetTunable("apex_intel_rate", TUNE_INTEL_RATE)
						/ 60.f * roleMul;
				const float vS = gainS / Catalog::gCostM[d];
				candDef.insertLast(d);
				candV.insertLast(vS);
				candGain.insertLast(gainS);
				sumV += vS;
			}
			continue;
		}
		// THE ASSASSIN'S WING. The air eco-raid is the one demand the army gap
		// cannot express: these bombers are bought to delete an enemy economy in
		// one pass, not to hold a line. Priced per bomber over the whole raid its
		// type would need, so a type requiring a hundred to survive their AA
		// carries that. Nothing here is a gate -- if the raid does not pay, the
		// gain is zero and the line builds army as before.
		if (!Catalog::gBuilder[d] && Air::IsBomberDef(d)) {
			const float gainB = Air::StrikeGainFor(d, fillS) * roleMul;
			if (gainB > 0.f) {
				const float vB = gainB / Catalog::gCostM[d];
				candDef.insertLast(d);
				candV.insertLast(vB);
				candGain.insertLast(gainB);
				sumV += vB;
				continue;
			}
		}
		// ARMY: fill the gap, best power-per-cost first, diminishing per
		// copy owned so the mix diversifies by arithmetic, not by table.
		// Overflowing metal keeps the line running past the target: idle
		// factory time is free, and army beats waste (watched: "way too
		// much idle time on our T1 lab").
		if (!Catalog::gBuilder[d]) {
			// A suicide unit's power is one detonation -- ammunition, not
			// standing army ("we're just making tumbleweeds", watched 8v8).
			// It never enters the army market; a munitions want can price
			// it honestly later if ever wanted.
			if (Catalog::gKamikaze[d])
				continue;
			// REZ BOTS classify as non-builders (empty build list), so they
			// land HERE, not the builder branch -- which is why none were
			// ever made (watched, twice). Their gain: the recoverable loss
			// pool plus a standing medic share of the army.
			if (Catalog::gRezzer[d]) {
				const int haveRz = (int(d) < int(gOwnCount.length()))
						? gOwnCount[d] : 0;
				const float medic = ArmyValue()
						* ai.GetTunable("apex_medic_frac", TUNE_MEDIC_FRAC) / 60.f;
				const float gainRz = (gLossPool
						/ ai.GetTunable("apex_rez_horizon", TUNE_REZ_HORIZON)
						+ medic) / (1.f + float(haveRz) * 0.33f) * roleMul;
				if (gainRz > 0.05f) {
					const float vRz = gainRz / Catalog::gCostM[d];
					candDef.insertLast(d);
					candV.insertLast(vRz);
					candGain.insertLast(gainRz);
					sumV += vRz;
				}
				continue;
			}
		// Until T3-grade units, the quiet rear builds NO army (apexearth);
			// the bar is the cheapest gantry-tier assault (corshiva 1550,
			// read from the defs 2026-07-30). FIGHTERS are the exception
			// once an air lab stands ("we *do* want fighters"): they guard
			// the air-con fleet, sized by the AA target below.
			const bool airGuard = Catalog::gFlyer[d] && (Catalog::gAirT[d] > 0.f);
			if ((roleMul < 1.f) && !airGuard && (Catalog::gCostM[d]
					< ai.GetTunable("apex_eco_army_min_m", TUNE_ECO_ARMY_MIN_M)))
				continue;
			const float sinkGap = OverflowM() * ((fillS > 1.f) ? fillS : 60.f) * roleMul;
			const float effGap = (armyGap > sinkGap) ? armyGap : sinkGap;
			if ((effGap <= 0.f) || (Catalog::gPower[d] <= 1.f) || (linePPC <= 0.f))
				continue;
			float ppc = Catalog::gCombat[d] / Catalog::gCostM[d];
			// FIELD REPORTS OVERRIDE STATS where the stats cannot see the
			// mechanism (projectile speed, accuracy): the user table in
			// tunables.as. And amphibious capability is dead weight on a
			// dry map -- the price paid for swimming buys nothing here.
			ppc *= UnitWorthMod(Catalog::Def(d).GetName());
			// x0 ON DRY MAPS (apexearth: "amphib should be x0" -- and a
			// tiny pond flips the engine's water flag, so the bar is real
			// water share of the map, ~15%).
			if (Catalog::gAmphib[d]) {
				float lp = aiTerrainMgr.GetLandPercent();
				if (lp <= 1.5f)
					lp *= 100.f;   // scale-proof: fraction or percent
				if (aiTerrainMgr.IsWaterAVoid()
					|| (lp > 100.f - ai.GetTunable("apex_water_pct", TUNE_WATER_PCT)))
					continue;
			}
			// The rear specialist buys quality: weight by unit size so the
			// draw lands on the biggest thing the lab offers, not spam that
			// arrives late or never.
			if (EcoRoleActive()) {
				float qual = Catalog::gCostM[d] / 1000.f;
				if (qual < 0.1f)
					qual = 0.1f;
				if (qual > 5.f)
					qual = 5.f;
				ppc *= qual;
			}
			// RANGE IS INTRINSIC VALUE (apexearth: "more strongly value
			// range"): reach means free damage before the enemy answers, in
			// every fight, not only against skirm pressure. A standing
			// preference on top of the reactive term below.
			// REACH IS ONLY WORTH WHAT SOMETHING ELSE IS ABSORBING (apexearth:
			// "low HP units with more range... they are only valuable if we
			// have tanky units in front of them tanking the damage... on their
			// own they're garbage"). The bonus is scaled by the share of our
			// line that can stand in front, so reach pays exactly as much as
			// we have shield to buy it with, and nothing at all when we have
			// none. The base combat-per-metal is untouched, so this can never
			// stop a long-range unit being built -- only stop it being
			// preferred while it would fight alone.
			ppc *= 1.f + (Catalog::gMaxRange[d] / 1000.f)
					* ai.GetTunable("apex_range_worth", TUNE_RANGE_WORTH)
					* ShieldShare();
			// AND THE STANDING COMPOSITION TARGET: tank / middle / reach / dps
			// as shares of army metal, each class worth more per metal the
			// further below its share it is. Proportional, never a veto.
			ppc *= 1.f + ai.GetTunable("apex_line_bite", TUNE_LINE_BITE)
					* LineShortfall(LineClassOf(d));
			// SPEED IS VALUE (apexearth: "they're fast, we need to properly
			// value speed"). A fast unit reaches the fight, catches raiders,
			// and disengages -- none of which shows up in combat-per-metal.
			// Normalised on 100 elmos/s, roughly a T1 bot.
			// Measured against the fastest ground unit the GAME offers, not a
			// flat 100 elmos/s: the bar is what may be raiding us, and we
			// assume they built the fastest thing they could (apexearth).
			ppc *= 1.f + (Catalog::gSpeed[d] / FoeSpeedCap())
					* ai.GetTunable("apex_speed_worth", TUNE_SPEED_WORTH);
			// AND COVERAGE: ground patrolled per metal, worth something only
			// while the fleet is short of the sites it has to watch. This is
			// what buys pawns early -- cheap and fast is the most coverage per
			// metal there is -- and it fades as the fleet fills.
			ppc *= 1.f + ai.GetTunable("apex_cover_worth", TUNE_COVER_WORTH)
					* CoverPerMetal(d) * PatrolShort();
			// EYES (apexearth: "we tend to lack scouts... need some kind of
			// value requirement on raider style units and scouts"). Sight is
			// what every other sense in this AI is built on -- the danger
			// model, the army target and the commander's engage test all read
			// zero while we are blind (EnemyArmyCost logged 0 for entire
			// games). A unit's LOS is therefore worth something on its own.
			ppc *= 1.f + (Catalog::gLosR[d] / 1000.f)
					* ai.GetTunable("apex_los_worth", TUNE_LOS_WORTH);
			// AFFORDABLE NOW BEATS STRONG LATER WHILE WE ARE POOR (apexearth:
			// "pawns are good early game when we cannot afford much stronger
			// things"). Seconds of income the unit costs, against the window
			// we are trying to fill the army gap in. Self-cancelling: as
			// income grows the same unit costs fewer seconds and the discount
			// fades, so this is an economy term, never a clock.
			{
				const float incA = aiEconomyMgr.metal.income;
				if (incA > 0.1f) {
					const float fieldSec = Catalog::gCostM[d] / incA;
					const float hA = (fillS > 1.f) ? fillS : 60.f;
					ppc *= hA / (hA + fieldSec);
				}
			}
			// RANGE ANSWERS RANGE (apexearth: banishers outranged and killed
			// our T1 too easily; snipers/fatboys came too late). Enemy skirm
			// and arty mass is outranging pressure: reach above 500 gains by
			// it, reach below fades toward the raider-spam share the role
			// portfolio already grants. T1 obsolescence emerges from the
			// same term.
			{
				const float outP = (Military::EnemyCostOf(Unit::Role::SKIRM.type)
						+ Military::EnemyCostOf(Unit::Role::ARTY.type)) / 3000.f;
				const float oP = (outP > 1.f) ? 1.f : outP;
				if (oP > 0.05f) {
					const float rNorm = (Catalog::gMaxRange[d] - 500.f) / 500.f;
					float rMul = 1.f + rNorm * oP * 1.2f;
					if (rMul < 0.3f)
						rMul = 0.3f;
					if (rMul > 2.5f)
						rMul = 2.5f;
					ppc *= rMul;
				}
			}
			const float have = float((int(d) < int(gOwnCount.length()))
					? gOwnCount[d] : 0);
			// The gap is a STREAM the line fills; clamping the gain to one
			// unit's cost made a Pawn bid 0.6 against any gap size and army
			// never outbid a constructor (two straight BARb losses).
			float eFeedA = 1.f;
			{
				const float eI = aiEconomyMgr.energy.income;
				const float eP = aiEconomyMgr.energy.pull;
				if ((eP > 1.f) && (eI < eP))
					eFeedA = eI / eP;
				// (the metal-feed throttle is gone: a zero bank spending its
				// whole income is PERFECT efficiency, not danger -- apexearth:
				// "'out of metal' is simply failing to spend... we need to
				// spend more." Builds at an empty bank slow to income speed
				// by the engine's own physics, which is the correct state.)
			}
			// This unit's role fills its own NEED gap; a saturated role's
			// units price to the floor whatever their power-per-cost.
			const float rTarget = RoleTarget(Catalog::gRole[d], ArmyTarget());
			const float rGap = rTarget - RoleValue(Catalog::gRole[d]);
			float roleW = (rTarget > 1.f) ? (rGap / rTarget) : 0.f;
			if (roleW < 0.05f)
				roleW = 0.05f;   // never exactly zero: portfolio floor
			float gainA = (effGap / ((fillS > 1.f) ? fillS : 60.f))
					* (ppc / linePPC) * roleW * stakeMul
					/ (1.f + have * 0.05f) * eFeedA;
			// The quiet rear's fighters ignore the suppressed army gap and
			// price straight off their own AA gap -- the air census is not
			// role-suppressed, so the guard fleet tracks REAL enemy air.
			if ((roleMul < 1.f) && airGuard) {
				gainA = ((rGap > 0.f) ? rGap : 0.f)
						/ ((fillS > 1.f) ? fillS : 60.f)
						* (ppc / linePPC) / (1.f + have * 0.05f) * eFeedA;
			}
			if (gainA <= 0.01f)
				continue;
			const float vA = gainA / Catalog::gCostM[d];
			candDef.insertLast(d);
			candV.insertLast(vA);
			candGain.insertLast(gainA);
			sumV += vA;
			continue;
		}
		// An ARMED producible builder is a decoy-class unit: it pays for a
		// gun and a disguise nobody asked for (apexearth: "do not want
		// them; maybe useful for later logic").
		if (Catalog::gSurfT[d] + Catalog::gAirT[d] > 0.01f)
			continue;
		float gain = 0.f;
		float reach = 0.f;
		const array<int>@ pb = Catalog::gBuildsList[d];
		for (uint q = 0; q < pb.length(); ++q) {
			if (Catalog::gExtractsM[pb[q]] > reach)
				reach = Catalog::gExtractsM[pb[q]];
		}
		// THE T2 CON FLOOR. Under it this is not an auction: the line
		// orders one now, ahead of the proportional draw and the
		// opportunity floor below. A ceiling con priced against army
		// loses whenever the army gap is open, and the stake multiplier
		// keeps it open -- so the floor is a rule, not a bid. The
		// hard-e-stall and in-flight gates above still hold.
		// THE PLAIN CONSTRUCTOR FLOOR, ahead of the proportional draw for the
		// same reason the T2 one is: a con priced against army loses whenever
		// the army gap is open, and the symmetric prior keeps it open by
		// construction. Any tier counts -- this asks for hands, not reach.
		if (ConsNeedAny() > 0) {
			AiLog("apex: decide t=" + ai.teamId + " " + fac.circuitDef.GetName()
				+ " #" + fac.id + " -> produce:" + Catalog::Def(d).GetName()
				+ " (con floor need=" + ConsNeedAny()
				+ " have=" + ConsOwnedAny()
				+ " inflight=" + ConsInFlightAny()
				+ " inc=" + formatFloat(aiEconomyMgr.metal.income, "", 0, 1) + ")");
			return Catalog::Def(d);
		}
		if ((ceilNeed > 0) && ReachesCeiling(d)) {
			AiLog("apex: decide t=" + ai.teamId + " " + fac.circuitDef.GetName()
				+ " #" + fac.id + " -> produce:" + Catalog::Def(d).GetName()
				+ " (t2-con floor need=" + ceilNeed
				+ " have=" + CeilingConsOwned()
				+ " inflight=" + CeilingConsInFlight()
				+ " inc=" + formatFloat(aiEconomyMgr.metal.income, "", 0, 1) + ")");
			return Catalog::Def(d);
		}
		// The quiet rear caps LAND con production at its keep-fleet (+2 for
		// attrition): the bank-driven BP gap must buy nanos and air cons,
		// not a walking crowd the reclaimer eats back (watched churn; conT1
		// hit 24 at 15m on the bank term).
		if (EcoQuiet() && !Catalog::gFlyer[d]
			&& (reach < BestExtract())) {
			int landT1 = 0;
			for (uint lc = 1; lc < gOwnCount.length(); ++lc) {
				if ((gOwnCount[lc] > 0) && Catalog::gMobile[int(lc)]
					&& Catalog::gBuilder[int(lc)] && !Catalog::gFlyer[int(lc)]) {
					if (!ReachesCeiling(int(lc)))
						landT1 += gOwnCount[lc];
				}
			}
			if (float(landT1) >= ai.GetTunable("apex_eco_con_keep", TUNE_ECO_CON_KEEP) + 2.f)
				continue;
		}
		// >= the game ceiling, not > our own: requiring the next con to
		// EXCEED what the first one reaches made a second armack impossible
		// (measured: one T2 con per game, forever).
		const float mob = MobilityMult(d);
		// Rez bots: the loss pool is recoverable value on the field; a rez
		// bot's stream is its share of it, diminishing per bot fielded.
		// From def DATA, not ownership: the owned-rezzer flag was a
		// bootstrap deadlock (production waited for a rezzer we could
		// never have ordered).
		if (Catalog::gRezzer[d]) {
			const int haveRez = (int(d) < int(gOwnCount.length())) ? gOwnCount[d] : 0;
			gain += gLossPool
					/ ai.GetTunable("apex_rez_horizon", TUNE_REZ_HORIZON)
					/ float(1 + haveRez);
		}
		if ((upD > 0.5f) && (reach >= BestExtract())) {
			// The upgrade stream divides among cons who can REACH it -- a
			// T1 fleet cannot moho anything, so the first T2 con serves
			// the whole 4x stream alone and prices like it (apexearth,
			// watching: "we make a T2 lab but don't even make a T2 con to
			// start off"). Dividing by ServingCons counted busy T1 hands
			// against demand only a T2 con can touch.
			const int ceilCons = CeilingConsOwned();
			gain += mob * upD / float(1 + ceilCons);
		}
		const float drain = Catalog::gBuildPower[d] * (7.f / 80.f);
		gain += mob * ((over < drain) ? over : drain);
		if (gMexOpen && (reach > 0.f)) {
			// A con claims spot after spot -- a stream of STREAMS -- but the
			// STREAMS ARE FINITE: 37 cons once chased 13 spots and easy BARb
			// walked over an armyless base (measured, ladder game 1). The
			// claim gain divides by claimers per open spot -- the unserved-
			// demand law, fourth application.
			CacheSpots();
			const float open = float(int(gAllSpots.length()) - int(gLSpot.length()));
			float claimers = 0.f;
			for (uint cd2 = 1; cd2 < gOwnCount.length(); ++cd2) {
				if ((gOwnCount[cd2] > 0) && Catalog::gMobile[int(cd2)]
					&& Catalog::gBuilder[int(cd2)])
					claimers += float(gOwnCount[cd2]);
			}
			float share = (open > 0.f) ? (open / (claimers + 1.f)) : 0.f;
			if (share > 1.f)
				share = 1.f;
			gain += mob * util * SpotM() * (((fillS > 1.f) ? fillS : 180.f) / 60.f)
					* share;
		}
		// UNPROTECTED BUILD POWER IS DISCOUNTED BUILD POWER (apexearth: "we
		// are currently walking our constructors out alone and they die...
		// a con outside of our home safe territory immediately has 0 value").
		// Buying another pair of hands to send out unescorted buys less than
		// it costs, so what a new con is worth scales with the share of the
		// build power we already have that is actually protected. It lifts by
		// itself the moment escorts exist -- and the escort want is priced on
		// the same metal (EscortMetalAtRisk), so the two trade against each
		// other honestly instead of both being flat.
		gain *= BPProtectedFrac();
		if (gain <= 0.5f)
			continue;
		const float v = gain / Catalog::gCostM[d];
		candDef.insertLast(d);
		candV.insertLast(v);
		candGain.insertLast(gain);
		sumV += v;
	}
	if ((candDef.length() == 0) || (sumV <= 0.f))
		return null;
	// Deterministic weighted pick: seeded from frame+line so replays hold.
	uint h = uint(ai.frame) * 2654435761 + uint(fac.id) * 40503;
	h ^= (h >> 13);
	float roll = float(h % 10000) / 10000.f * sumV;
	uint pick = 0;
	for (uint ci = 0; ci < candV.length(); ++ci) {
		roll -= candV[ci];
		if (roll <= 0.f) {
			pick = ci;
			break;
		}
	}
	best = candDef[pick];
	bestV = candV[pick];
	bestGain = candGain[pick];
	// Priced in the same currency; factory time is free while the line idles.
	// OPPORTUNITY FLOOR: the draw compares a line's candidates only against
	// each other, so a saturated line kept producing v=1.2 cons while
	// fusion money earned v=30+ outside (measured: 22 armacks, 1 fusion).
	// The floor is a SCARCITY question, gated on FreeMetalFlow: with
	// unspent flow standing, an idle line is pure waste whatever the EMA
	// says. The old OverflowM gate (bank at 80% storage) opened far too
	// late, and the per-metal EMA compare structurally idled every
	// expensive T2 line meanwhile (A/B, seed 5: 1 produce decide in 5.5
	// minutes at floor 0.25 vs a real stream at 0). In true scarcity the
	// per-metal compare is right -- metal IS the constraint there.
	if ((FreeMetalFlow() <= 0.5f) && (gWantEmaV > 0.f)
		&& (bestV < gWantEmaV
			* ai.GetTunable("apex_line_floor", TUNE_LINE_FLOOR)))
		return null;
	AiLog("apex: decide t=" + ai.teamId + " " + fac.circuitDef.GetName() + " #" + fac.id
		+ " -> produce:" + Catalog::Def(best).GetName()
		+ " v=" + formatFloat(bestV * 1000.f, "", 0, 2)
		+ " (gain=" + formatFloat(bestGain, "", 0, 2)
		+ " m=" + formatFloat(Catalog::gCostM[best], "", 0, 0)
		+ " serving=" + ServingCons() + ")");
	return Catalog::Def(best);
}


}  // namespace Market
