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

// Army metal ORDERED but not yet standing. gOwnCount counts FINISHED units and
// an order takes a whole lag window to become visible, so without this every
// slot of a batch -- and every election inside the lag window -- prices against
// the same gap and buys it over again.
float ArmyInFlightM()
{
	float m = 0.f;
	for (uint i = 0; i < Brain::gFQPendDef.length(); ++i) {
		CCircuitDef@ pd = Brain::gFQPendDef[i];
		if (pd is null)
			continue;
		const int d = int(pd.id);
		if (!Catalog::gMobile[d] || Catalog::gBuilder[d]
			|| (Catalog::gPower[d] <= 1.f) || Catalog::gKamikaze[d])
			continue;
		m += Catalog::gCostM[d];
	}
	return m;
}

// Why the last ConOrderFor call declined. The facqueue logs it when a line
// comes back with nothing: an election that orders nothing is idle factory
// time, and until this existed the reason was invisible.
string gNoOrder = "";

// `slot` is the position in the line's batch: the facqueue asks repeatedly
// until the queue is deep enough, and every ask is priced against a ledger
// that already carries the slots before it.
// Every mobile radar we own and every mobile jammer, whatever def. The demand
// is a pair per squad; counting per def multiplied it by however many sensor
// types the labs happened to offer.
int gSupHaveAt = -1;
int gSupRadarN = 0;
int gSupJamN = 0;
void SupportCensus()
{
	if (gSupHaveAt == ai.frame)
		return;
	gSupHaveAt = ai.frame;
	gSupRadarN = 0;
	gSupJamN = 0;
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		const int di = int(d);
		if (!Catalog::gMobile[di] || Catalog::gBuilder[di])
			continue;
		if (!Catalog::gRadar[di] && !Catalog::gJammer[di])
			continue;
		if (Catalog::gSurfT[di] + Catalog::gAirT[di] > 0.01f)
			continue;
		// What we OWN plus what we have already SENT for: gOwnCount only counts
		// finished units, so topping up against it re-orders for the whole walk
		// window.
		const int nHave = gOwnCount[d] + Brain::PendAnyOf(di);
		if (Catalog::gRadar[di])
			gSupRadarN += nHave;
		else
			gSupJamN += nHave;
	}
}

CCircuitDef@ ConOrderFor(CCircuitUnit@ fac, int line, int slot)
{
	if (fac is null)
		return null;
	WorthDiag();      // self-gated, once, and only when asked for
	LineClassDiag();  // likewise: the class split, once the field is known
	gNoOrder = "";
	// Production pays the E-flow discipline too: a factory pumping pawns
	// through a stall both causes it and starves the opening (watched:
	// hard e-stall, a minute without a mex).
	if (HardEStall()) {
		gNoOrder = "e-stall";
		return null;
	}
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
		&& (ArmyTarget() - ArmyValue() - ArmyInFlightM() <= 0.5f)
		&& (OverflowM() <= 0.5f))
	{
		gNoOrder = "all-quiet";
		return null;
	}
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
	float armyGap = ArmyTarget() - ArmyValue() - ArmyInFlightM();
	const float fillS = ai.GetTunable("apex_army_fill_s", TUNE_ARMY_FILL_S);
	// METAL WE FAIL TO SPEND IS ARMY DEMAND (his standing law: the economy
	// is for spending; waste is free army). The same overflow signal that
	// buys nanos floors the gap, so a satisfied target never idles the lines
	// while metal rots -- measured: lines at buf0s with 31% of a 44-minute
	// game's metal overflowing.
	{
		const float waste = OverflowM() * ((fillS > 1.f) ? fillS : 180.f);
		if (waste > armyGap)
			armyGap = waste;
	}
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
	// T1 AIR ARMY ENDS AT T2 (apexearth: "We need to stop making T1 air army
	// when we have T2 available"): armed fliers from a basic air plant price
	// out once our own advanced air plant stands -- the same metal buys the
	// advanced airframe. Builders and unarmed scouts keep flowing.
	bool t1AirMute = false;
	if ((PlantClass(fid) == PC_AIR) && (PlantTier(fid) == 1)) {
		for (uint ad = 1; ad < gOwnCount.length(); ++ad) {
			const int adi = int(ad);
			if ((gOwnCount[ad] <= 0) || Catalog::gMobile[adi]
				|| (Catalog::gBuildsList[adi].length() == 0))
				continue;
			if ((PlantClass(adi) == PC_AIR) && (PlantTier(adi) >= 2)) {
				t1AirMute = true;
				break;
			}
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
		const float ppc = UnitCore(d);
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
		if (t1AirMute && !Catalog::gBuilder[d] && (Catalog::gPower[d] > 1.f))
			continue;
		// SUPPORT: mobile eyes and static-cover. One radar and one jammer per
		// squad that can actually take one (apexearth: "we only need up to 2 of
		// these per squad that we have"); attachment is the military layer's,
		// production is ours.
		//
		// AN ARMED UNIT IS ARMY. gRadar/gJammer also flag anything carrying
		// radarDistance > 900 or jam > 100, which is a Commando, a Phantom and
		// a battleship -- priced here they never entered the army market at
		// all, and each one drew its own copy of the demand below.
		if (Catalog::gMobile[d] && !Catalog::gBuilder[d]
			&& (Catalog::gSurfT[d] + Catalog::gAirT[d] < 0.01f)
			&& (Catalog::gRadar[d] || Catalog::gJammer[d]))
		{
			SupportCensus();
			const bool isJamS = !Catalog::gRadar[d];
			const int haveS = isJamS ? gSupJamN : gSupRadarN;
			// THE DEMAND IS SQUADS, AND IT IS ONE QUESTION PER CLASS.
			// It was AdvArmyValue/squadM asked once per DEF: eight sensor defs
			// each targeting the same fifteen "squads" is a hundred and twenty
			// units, which is what he counted. EscortSquadCount is the live
			// number of groups CSupportTask will actually attach one to.
			const float squadM = ai.GetTunable("apex_squad_m", TUNE_SQUAD_M);
			const float squads = float(int(Military::EscortSquadCount()));
			float need = AdvArmyValue() / ((squadM > 1.f) ? squadM : 2000.f);
			if (squads < need)
				need = squads;
			if ((need < 1.f) && (squads >= 1.f))
				need = 1.f;
			if (ai.frame >= gSupportDiagAt) {
				gSupportDiagAt = ai.frame + 60 * SECOND;
				AiLog("apex: support-diag t=" + ai.teamId + " def="
					+ Catalog::Def(d).GetName()
					+ " cls=" + (isJamS ? "jam" : "radar")
					+ " have=" + haveS
					+ " own=" + gOwnCount[d]
					+ " pend=" + Brain::PendAnyOf(int(d))
					+ " R=" + gSupRadarN + "/J=" + gSupJamN
					+ " need=" + formatFloat(need, "", 0, 2)
					+ " squads=" + int(squads)
					+ " adv=" + formatFloat(AdvArmyValue(), "", 0, 0));
			}
			if (need <= 0.f)
				continue;
			// WHAT THE NEXT ONE IS WORTH IS THE SQUAD IT FINDS WITHOUT ONE.
			// The old form paid the full shortfall rate below the line and
			// nothing above it, so the tenth bid as hard as the first. Priced
			// per unit on the share of squads still uncovered, it falls with
			// every one bought and reaches zero when every squad has one --
			// not a limit: an escort with no squad to attach to escorts
			// nothing. `need` is the live squad count, so this grows with the
			// army like everything else.
			float uncov = (need - float(haveS)) / need;
			if (uncov > 1.f)
				uncov = 1.f;
			const float gainS = (uncov > 0.f)
					? (uncov * squadM
						* ai.GetTunable("apex_intel_rate", TUNE_INTEL_RATE)
						/ 60.f * roleMul)
					: 0.f;
			if (gainS > 0.f) {
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
			// The golden metrics, weighted by exponent (market/worth.as).
			// Carries the by-name worth override, the reach-vs-shield bonus
			// and the reach-answers-reach response with it.
			float ppc = UnitPPC(d);
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
			// A SCOUT IS NOT A BAD SOLDIER. UnitCore prices dps and hp against
			// cost, and on that yardstick a Tick -- 60 hp, 50 dps, 21 metal --
			// scores far below a Pawn, a gap no speed or sight multiplier on
			// top of it can close because they all multiply that same near-zero
			// core. What a screen sells is ground seen and fire drawn, neither
			// of which is combat, so it is priced on its own axis and the unit
			// is worth the BETTER of the two readings (apexearth: "the arm tick
			// is actually a better choice than the pawn -- super high speed,
			// los, and affordability"). Saturates on the same patrol shortfall
			// the coverage term uses, so the screen stops being bought once the
			// ground is watched.
			{
				WorthMeans();
				const float mineM = Catalog::gCostM[d];
				const float kS = ai.GetTunable("apex_screen_worth", TUNE_SCREEN_WORTH);
				if ((kS > 0.f) && (mineM > 1.f) && (gWMCost > 1.f)
					&& !Catalog::gFlyer[d])
				{
					const float dash = 1.f + Catalog::gSpeed[d] / FoeSpeedCap();
					const float screen = kS * (Catalog::gLosR[d] / 1000.f)
							* dash * PatrolShort() / (mineM / gWMCost);
					if (screen > ppc)
						ppc = screen;
				}
			}
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
	if ((candDef.length() == 0) || (sumV <= 0.f)) {
		gNoOrder = "no-candidate";
		return null;
	}
	// Deterministic weighted pick: seeded from frame+line so replays hold.
	uint h = uint(ai.frame) * 2654435761 + uint(fac.id) * 40503
			+ uint(slot) * 2246822519;
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
			* ai.GetTunable("apex_line_floor", TUNE_LINE_FLOOR))) {
		gNoOrder = "line-floor v=" + formatFloat(bestV * 1000.f, "", 0, 2)
				+ " ema=" + formatFloat(gWantEmaV * 1000.f, "", 0, 2);
		return null;
	}
	AiLog("apex: decide t=" + ai.teamId + " " + fac.circuitDef.GetName() + " #" + fac.id
		+ " -> produce:" + Catalog::Def(best).GetName()
		+ " v=" + formatFloat(bestV * 1000.f, "", 0, 2)
		+ " (gain=" + formatFloat(bestGain, "", 0, 2)
		+ " m=" + formatFloat(Catalog::gCostM[best], "", 0, 0)
		+ " serving=" + ServingCons() + ")");
	return Catalog::Def(best);
}


}  // namespace Market
