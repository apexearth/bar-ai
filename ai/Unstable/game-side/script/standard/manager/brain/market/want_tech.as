namespace Market {

// The share of a deferred return we expect to actually collect.
//
// HazardAt x ShortfallAt is already the per-second rate at which value here is
// destroyed net of what our turrets stop (coverage.as); over a horizon T that
// is the loss borne while waiting. T is the pipeline's own latency plus the
// time income needs to PAY for the thing -- so all three of his conditions
// price themselves without a threshold anywhere: battles lost feed the loss
// field, thin base defence raises the shortfall, and a lab we cannot afford
// waits longer and is discounted harder.
float TechSurvival(int defId, float askerBP)
{
	if (ai.GetTunable("apex_tech_survival", TUNE_TECH_SURVIVAL) <= 0.f)
		return 1.f;
	if (!Builder::gHomeSet)
		return 1.f;
	const AIFloat3 home = Builder::gHomePos;
	if (!OnMap(home))
		return 1.f;
	// UNSCOUTED IS NOT SAFE. ShortfallAt says what share of the wave our guns
	// fail to stop, but it is computed against the enemy we can SEE -- with no
	// fix on them it reads 0 and a long-payback lab prices as risk-free
	// exactly when we know least (apexearth: "theres lots of unknowns, if we
	// don't know the enemy strength then we shouldn't be making a T2 lab...
	// we need scouts"). Blind, our cover proves nothing, so it counts for
	// nothing. This deliberately touches ONLY the tech price -- the same prior
	// applied inside HazardAt repriced every want in the game and cost 87% of
	// our standing army (measured, 6 games).
	const float shortH = Front::FoeKnown() ? ShortfallAt(home) : 1.f;
	float risk = HazardAt(home) * shortH;
	// The siege prior stands whether or not anything has been seen; it is the
	// term that says a big economy with no army is a target.
	const float siege = SiegeRisk(home) * shortH;
	if (siege > risk)
		risk = siege;
	if (risk <= 0.f)
		return 1.f;
	float T = PipeLatencySec(defId, askerBP);
	// Same affordability the lathe actually sees (see ValueOf's feedSec):
	// half the bank is spendable now, the rest waits on income.
	const float inc = aiEconomyMgr.metal.income;
	if (inc > 0.1f) {
		const float payS = (Catalog::gCostM[defId]
				- aiEconomyMgr.metal.current * 0.5f) / inc;
		if (payS > 0.f)
			T += payS;
	}
	return 1.f / (1.f + risk * T);
}

// Upgrade a spot we hold: gain is the extraction delta on the spot's real
// income. Pure arithmetic; capability comes free from BuildsOf.
Want@ ProposeMexUp(CCircuitUnit@ unit)
{
	Want w;
	const int uid = int(unit.circuitDef.id);
	const array<int>@ builds = Catalog::BuildsOf(uid);
	const AIFloat3 here = unit.GetPos(ai.frame);
	const float speed = Catalog::gSpeed[uid];
	for (uint li = 0; li < gLSpot.length(); ++li) {
		if (gLExtract[li] <= 0.f)
			continue;   // not finished (or already being replaced)
		if (DeathWalk(unit, gLPos[li]))
			continue;   // a forward mex we hold can still be a lethal walk
		for (uint i = 0; i < builds.length(); ++i) {
			const int d = builds[i];
			if (!Catalog::gAvailable[d] || (Catalog::gExtractsM[d] <= gLExtract[li]))
				continue;
			float delta = gLIncome[li] * (Catalog::gExtractsM[d] - gLExtract[li]);
			{
				// Share of TOTAL economic power, the same denominator the
				// energy premium uses -- see want_energy.as.
				const float inc1 = EcoPowerM();
				delta *= 1.f + ai.GetTunable("apex_mex_growth", TUNE_MEX_GROWTH)
						* delta / ((inc1 > delta) ? inc1 : delta);
			}
			// Quadrupling the yield of a spot we cannot hold quadruples
			// nothing -- the same discount the claim itself takes.
			delta *= StreamSurvival(gLPos[li]);
			const float walkSec = (speed > 1.f)
					? (here.distance2D(gLPos[li]) / speed) : 60.f;
			Want c;
			ValueOf(d, delta, walkSec, Catalog::gBuildPower[uid], c);
			if (c.value > w.value) {
				w = c;
				w.kind = WK_MEXUP;
				@w.def = Catalog::Def(d);
				w.pos = gLPos[li];
				w.spotId = gLSpot[li];
			}
		}
	}
	return w;
}

// A plant priced by what it UNLOCKS: the upgrade demand its constructor
// products could serve that no builder we own can reach. Deliberately not
// gated by the lines-per-income rule (its return is better economics, not
// more parallel production). MODEL: the pipeline discount.
int gTechDiagAt = 0;
Want@ ProposeTech(CCircuitUnit@ unit)
{
	Want w;
	// Extraction upgrades AND conversion upgrades: both are "the same economy,
	// better", and on a map with no spots only the second one exists.
	//
	// ...AND BEING OUTCLASSED, which is demand for tech that has nothing to do
	// with the economy. Priced on economy alone this want returned at the gate
	// below with upD 0.02-0.11 against a bar of 0.5, while the enemy fielded
	// 14,070 metal of T2 and our best buildable unit was a 270-metal T1
	// (apexearth: "if we see the enemy has T2 then we should boost building our
	// own T2. We will 100% lose if we don't up to T2 to match them").
	//
	// How far ahead they are, as a ratio, so it is the same shape as the
	// extraction demand beside it: their best mobile over ours, less one. Dead
	// level contributes nothing and it fades as we catch up. Both readings
	// exclude builders -- a commander is mobile and costs 2700, and counting it
	// made this read "outclassed" from frame one.
	//
	// Only while we can still build something: with no factory at all the
	// answer is a plant, which is ProposePlant's business, not a tech upgrade.
	float outclass = 0.f;
	{
		const float theirs = ai.GetEnemyMaxMobileCostM();
		const float ours = OwnedBestMobileCostM();
		if ((ours > 0.f) && (theirs > ours))
			outclass = (theirs / ours) - 1.f;
	}
	const float demand = UpDemand() + ConvUpDemand() + outclass;
	if (ai.frame >= gTechDiagAt) {
		gTechDiagAt = ai.frame + 120 * SECOND;
		AiLog("apex: tech-diag team=" + ai.teamId + " upD=" + demand
				+ " outclass=" + formatFloat(outclass, "", 0, 2)
				+ " ceil=" + BestExtract() + " ownCeil=" + OwnedCeil()
				+ " spots=" + gLSpot.length() + " funded="
				+ (ArmyValue() / ((ArmyTarget() > 1.f) ? ArmyTarget() : 1.f)));
	}
	if (demand <= 0.5f)
		return w;
	// Dedup is PER DEF: a T1 rebuild in flight must not zero the T2 lab's
	// price (watched, 8v8: a team overflowing with no T2 -- any live plant
	// request blanket-blocked tech).
	const int uid = int(unit.circuitDef.id);
	const float ownCeil = OwnedCeil();
	// Best mobility among owned ceiling-reaching cons: a plant whose con
	// flies (T2 air) is an upgrade even when extraction reach ties.
	float ownMob = 0.f;
	{
		const float ceilX = BestExtract();
		for (uint dd = 1; dd < gOwnCount.length(); ++dd) {
			if ((gOwnCount[dd] <= 0) || !Catalog::gMobile[int(dd)] || !Catalog::gBuilder[int(dd)])
				continue;
			const array<int>@ bb = Catalog::gBuildsList[int(dd)];
			for (uint q = 0; q < bb.length(); ++q) {
				if (Catalog::gExtractsM[bb[q]] >= ceilX) {
					const float m0 = MobilityMult(int(dd));
					if (m0 > ownMob)
						ownMob = m0;
					break;
				}
			}
		}
	}
	const AIFloat3 here = unit.GetPos(ai.frame);
	const float pipe = ai.GetTunable("apex_tech_pipe", TUNE_TECH_PIPE);
	const array<int>@ builds = Catalog::BuildsOf(uid);
	for (uint i = 0; i < builds.length(); ++i) {
		const int d = builds[i];
		if (!Catalog::gAvailable[d] || Catalog::gMobile[d] || Catalog::gFloater[d] || Catalog::gSub[d])
			continue;
		if (Catalog::gBuildsList[d].length() == 0)
			continue;
		if (Requests::LiveOfDef(Catalog::Def(d)))
			continue;   // this def is already requested: help it, not double it
		// The plant's best feasible mobile builder, and the extraction IT
		// reaches; the plant unlocks only what exceeds our own ceiling.
		float prodCeil = 0.f;
		const array<int>@ prods = Catalog::gBuildsList[d];
		for (uint p = 0; p < prods.length(); ++p) {
			const int pd = prods[p];
			if (!Catalog::gMobile[pd] || !Catalog::gBuilder[pd])
				continue;
			if (!ai.CanDefReach(Catalog::Def(pd), here, here))
				continue;
			const array<int>@ pb = Catalog::gBuildsList[pd];
			for (uint q = 0; q < pb.length(); ++q) {
				if (Catalog::gExtractsM[pb[q]] > prodCeil)
					prodCeil = Catalog::gExtractsM[pb[q]];
			}
		}
		// Two ways a plant unlocks: reach beyond what we own, or the same
		// reach carried by a decisively more MOBILE con (the T2 air lab).
		float prodMob = 0.f;
		for (uint p2 = 0; p2 < prods.length(); ++p2) {
			const int pd2 = prods[p2];
			if (!Catalog::gMobile[pd2] || !Catalog::gBuilder[pd2])
				continue;
			const array<int>@ pb2 = Catalog::gBuildsList[pd2];
			for (uint q2 = 0; q2 < pb2.length(); ++q2) {
				if (Catalog::gExtractsM[pb2[q2]] >= BestExtract()) {
					const float m2 = MobilityMult(pd2);
					if (m2 > prodMob)
						prodMob = m2;
					break;
				}
			}
		}
		// KIN PIPES IN FLIGHT: no veto -- the MATH says it (apexearth:
		// "the math should be correct... we shouldn't need vetos"). A live
		// plant whose products reach this far is already delivering this
		// unlock, so the demand stream DIVIDES among the pipes being built
		// to serve it -- the unserved-demand law, applied to tech. A rich
		// economy can still buy parallel tier capacity when the divided
		// gain wins; a poor one finds the second pipe worth half at twice
		// the real duration (the affordability term in ValueOf).
		// Does this plant reach a better CONVERTER than anything we own?
		float prodConv = 0.f;
		for (uint pc = 0; pc < prods.length(); ++pc) {
			const int pd3 = prods[pc];
			if (!Catalog::gMobile[pd3] || !Catalog::gBuilder[pd3])
				continue;
			const float r3 = ConvRatioReach(Catalog::gBuildsList[pd3]);
			if (r3 > prodConv)
				prodConv = r3;
		}
		const float ownConv = OwnConvCeil();
		// KIN INCLUDES WHAT ALREADY STANDS, not only what is in flight. This
		// divisor counted live REQUESTS only, so the moment the first plant
		// FINISHED it stopped counting and the next one priced at full demand
		// again -- which is how a second lab kept arriving (apexearth: "why do
		// we make 2 T1 labs often and the second one is usually a hover?").
		// A standing plant whose constructors already reach this far is serving
		// the demand just as much as one being built.
		int liveKin = 0;
		for (uint sk = 1; sk < gOwnCount.length(); ++sk) {
			const int sd = int(sk);
			if ((gOwnCount[sk] <= 0) || Catalog::gMobile[sd]
				|| (Catalog::gBuildsList[sd].length() == 0))
				continue;
			const array<int>@ sb = Catalog::gBuildsList[sd];
			bool skin = false;
			for (uint sq = 0; sq < sb.length() && !skin; ++sq) {
				const int spd = sb[sq];
				if (!Catalog::gMobile[spd] || !Catalog::gBuilder[spd])
					continue;
				const array<int>@ spb = Catalog::gBuildsList[spd];
				for (uint sz = 0; sz < spb.length(); ++sz) {
					if (Catalog::gExtractsM[spb[sz]] >= prodCeil) {
						skin = true;
						break;
					}
				}
				if (!skin && (prodConv > 0.f)
					&& (ConvRatioReach(Catalog::gBuildsList[spd]) >= prodConv))
					skin = true;
			}
			if (skin)
				liveKin += gOwnCount[sk];
		}
		for (uint kl = 0; kl < Requests::gLive.length(); ++kl) {
			IUnitTask@ kt = Requests::gLive[kl];
			if ((kt is null) || (kt.buildDef is null))
				continue;
			const int kd = int(kt.buildDef.id);
			if (Catalog::gMobile[kd] || (Catalog::gBuildsList[kd].length() == 0))
				continue;
			bool kin = false;
			const array<int>@ kb = Catalog::gBuildsList[kd];
			for (uint kq = 0; kq < kb.length() && !kin; ++kq) {
				const int kpd = kb[kq];
				if (!Catalog::gMobile[kpd] || !Catalog::gBuilder[kpd])
					continue;
				const array<int>@ kpb = Catalog::gBuildsList[kpd];
				for (uint kz = 0; kz < kpb.length(); ++kz) {
					if (Catalog::gExtractsM[kpb[kz]] >= prodCeil) {
						kin = true;
						break;
					}
				}
				// KIN ON THE CONVERTER AXIS TOO. The unlock test now fires on
				// reaching a better converter as well as a better extractor,
				// but this divisor only ever looked at extraction -- so two
				// different T2 plants in flight each priced at the FULL
				// conversion unlock and neither counted the other (apexearth,
				// watched: "that game we did 2 t2 labs at the same time").
				if (!kin && (ConvRatioReach(Catalog::gBuildsList[kpd]) >= prodConv)
					&& (prodConv > 0.f))
					kin = true;
			}
			if (kin)
				++liveKin;
		}
		// A lab without follow-through is a statue: its price carries its
		// first constructor, and its VALUE scales with how funded the army
		// is -- an outgunned base defers tech exactly as much as it is
		// outgunned (apexearth: "we starve our army production by starting
		// a T2 lab too early... calculate the cost of making a lab's units
		// prior to making it"). No timer anywhere.
		const float aT = ArmyTarget();
		const float funded = (aT > 1.f) ? (ArmyValue() / aT) : 1.f;
		// The quiet rear is EXEMPT: its follow-through is mohos and
		// fusions, not an army -- gating its lab on the army it was told
		// not to build starved its whole mandate (measured: funded=0.024,
		// a 40x tech discount on the one player built to tech).
		float fundedMul = (funded > 1.f) ? 1.f : funded;
		if (EcoQuiet())
			fundedMul = 1.f;
		// BEING OUT-TECHED LIFTS THE FLOOR UNDER THAT DISCOUNT. apexearth: "if we
		// see the enemy has T2 then we should boost building our own T2. We will
		// 100% lose if we don't up to T2 to match them."
		//
		// The discount above is exactly backwards in this case: an army that
		// cannot match their units is UNDER-funded by construction, so the worse
		// they outclass us the harder it forbids the one thing that would let us
		// match -- measured funded=0.04, techStart=-1 in every game of a batch.
		// The floor is how far ahead they are, read from unit cost rather than a
		// tier table: dead level leaves the discount untouched, twice our best
		// halves it, ten times all but removes it. Never a boost above normal,
		// and it falls back to nothing the moment we can build their equal.
		{
			const float theirs = ai.GetEnemyMaxMobileCostM();
			const float ours = OwnedBestMobileCostM();
			if ((theirs > ours) && (theirs > 0.f)) {
				const float floorMul = 1.f - (ours / theirs);
				if (floorMul > fundedMul)
					fundedMul = floorMul;
			}
		}
		// Two plants can unlock the same thing; the one whose line trades
		// worse per metal is worth less for it. See PlantLineWorth.
		const float lineW = PlantLineWorth(d);
		float techGain = 0.f;
		if ((prodCeil > ownCeil) || (prodConv > ownConv))
			techGain = demand * pipe / float(1 + liveKin);
		else if ((ownMob > 0.f) && (prodMob > ownMob * 1.2f)) {
			// MOBILITY BUYS A PLANT ONLY WHEN IT BUYS WINGS. This channel was
			// written for one case -- the air lab, whose flying constructors are
			// the quiet rear's whole expansion plan because ground plants stop
			// pricing for it. Hovercraft clear the same 1.2x bar as collateral,
			// and a 750-metal platform arrived every game for a 23% walk-speed
			// edge, carrying a line of units that are not tough for their price
			// (apexearth: "yes it has mobility but the units are generally not
			// as tough for their price. So we shouldn't be making it. We can
			// work on logic like 'we NEED hovers' later on in the game").
			//
			// So the channel is scoped to what it was for: a flying builder we
			// do not own. Ground-to-ground mobility deltas buy nothing here --
			// they are a refinement of demand another plant already serves.
			// Needing hovers for ground we cannot otherwise reach is a real
			// want and a different one; it is not this.
			bool ownFlyingBuilder = false;
			for (uint fb = 1; fb < gOwnCount.length(); ++fb) {
				if ((gOwnCount[fb] > 0) && Catalog::gFlyer[int(fb)]
					&& Catalog::gBuilder[int(fb)] && Catalog::gMobile[int(fb)]) {
					ownFlyingBuilder = true;
					break;
				}
			}
			bool unlocksFlyer = false;
			for (uint pf = 0; pf < prods.length(); ++pf) {
				if (Catalog::gMobile[prods[pf]] && Catalog::gBuilder[prods[pf]]
					&& Catalog::gFlyer[prods[pf]]) {
					unlocksFlyer = true;
					break;
				}
			}
			if (!ownFlyingBuilder && unlocksFlyer) {
				// The quiet rear's wings are a full-demand want, not a
				// mobility-delta sliver (seed 23: no air lab in 15 min).
				techGain = EcoQuiet() ? (demand * pipe)
						: (demand * pipe * (prodMob / ownMob - 1.f)
							/ float(1 + liveKin));
			}
		}
		// Channel 3, the GANTRY case: a plant whose products dwarf anything
		// we can currently produce is the overflow SINK -- its value is the
		// wasted income its production line would absorb.
		{
			float prodMax = 0.f;
			for (uint p3 = 0; p3 < prods.length(); ++p3) {
				if (Catalog::gMobile[prods[p3]]
					&& (Catalog::gCostM[prods[p3]] > prodMax))
					prodMax = Catalog::gCostM[prods[p3]];
			}
			// A PLANT THAT UNLOCKS NOTHING IS NOT A SINK. "Dwarfs anything we
			// can produce" is 2x the cost ceiling we own, which a 50-metal
			// pawn baseline clears trivially -- so an ordinary T1 plant took
			// the gantry's whole army-gap stream and a hovercraft platform
			// that reached NO better extractor and NO better converter was
			// bought every game on it (measured: corhp prodCeil==ownCeil,
			// prodConv==ownConv, gain 1.02, apexearth: "I don't want to see us
			// making hovers on a land only map"). This channel's own comment
			// says the gap it may claim is the one ONLY its products can fill;
			// the code claimed the full army gap regardless. A plant our
			// existing lines can substitute for gets neither the gap nor the
			// penetration term, and is left with real overflow only.
			const bool unlocksTier = (prodCeil > ownCeil) || (prodConv > ownConv);
			if (prodMax > 2.f * OwnedProdCostCeil()) {
				// The gantry's value is PENETRATION plus the army gap that
				// ONLY its products can fill: at 250 m/s nobody built one
				// because porc-and-overflow were its only terms (watched).
				// The gap reads the FULL target -- T3 is what the eco role
				// suppressed everything else for.
				const float porc = aiEnemyMgr.GetEnemyCost(RT::STATIC);
				const float pen = (porc / 300.f) * pipe;
				const float sink = OverflowM() * pipe;
				const float fillS3 = ai.GetTunable("apex_army_fill_s", TUNE_ARMY_FILL_S);
				const float gapF = ArmyTargetFull() - ArmyValue();
				const float gapStream = (gapF > 0.f)
						? (gapF / ((fillS3 > 1.f) ? fillS3 : 60.f)) * pipe : 0.f;
				// Unlock-only. Overflow is a poor reason to buy a production
				// LINE -- nanos, converters and storage are already wants for
				// exactly that, and they do not commit us to a unit mix. A
				// plant that reaches no better extractor and no better
				// converter has no tech value at all.
				if (!unlocksTier)
					continue;
				float g3 = (pen > sink) ? pen : sink;
				g3 += gapStream;
				if (g3 > techGain)
					techGain = g3;
			}
		}
		if (techGain <= 0.f)
			continue;
		// SURVIVING LONG ENOUGH TO BE PAID. Teching is a deferred purchase --
		// the lab, then its constructors, then their upgrades -- and none of
		// that stream arrives if the base is overrun first. The gain is
		// discounted by the risk borne over the pipeline's own latency, which
		// is why an outgunned, uncovered, cash-poor base defers T2 and resumes
		// it unaided once the front settles (apexearth, watched: "we are
		// starting T2 while our danger is very high"). Defence wants are not
		// discounted -- their return is loss prevented NOW, the same exemption
		// decide.as makes for the exposure charge.
		techGain *= lineW;
		techGain *= TechSurvival(d, Catalog::gBuildPower[uid]);
		if (techGain <= 0.f)
			continue;
		// Overflowing metal escalates a justified tech want: the lab's
		// pipeline (mohos, fusion-building cons) is the spender the current
		// fleet lacks. Without this, 40-metal winds out-valued the 3300
		// tech bill at argmax for five straight minutes of full storage
		// (seed 23: T2 at 10.9m; seed 11's 3.3m was E-saturation luck).
		techGain += OverflowM() * pipe;
		if (ai.GetTunable("apex_techcand_diag", 0.f) > 0.f) {
			AiLog("apex: techcand " + Catalog::Def(d).GetName()
				+ " prodCeil=" + formatFloat(prodCeil, "", 0, 4)
				+ " ownCeil=" + formatFloat(ownCeil, "", 0, 4)
				+ " prodConv=" + formatFloat(prodConv, "", 0, 5)
				+ " ownConv=" + formatFloat(ownConv, "", 0, 5)
				+ " lineW=" + formatFloat(lineW, "", 0, 2)
				+ " kin=" + liveKin
				+ " gain=" + formatFloat(techGain, "", 0, 2)
				+ " costM=" + formatFloat(Catalog::gCostM[d], "", 0, 0));
		}
		// The lab lands at the interior anchor, so that -- not the asker's own
		// feet -- is the walk this want is priced against.
		const AIFloat3 lands = InteriorSite(here, Catalog::Def(int(unit.circuitDef.id)));
		Want c;
		ValueOf(d, techGain * fundedMul
					* PipeLatencyMult(d, Catalog::gBuildPower[uid]),
				WalkSecTo(unit, lands), Catalog::gBuildPower[uid], c);
		// the follow-through bill: cheapest constructor this lab produces
		{
			float conBill = 0.f;
			const array<int>@ pf = Catalog::gBuildsList[d];
			for (uint pi2 = 0; pi2 < pf.length(); ++pi2) {
				if (Catalog::gMobile[pf[pi2]] && Catalog::gBuilder[pf[pi2]]
					&& ((conBill <= 0.f) || (Catalog::gCostM[pf[pi2]] < conBill)))
					conBill = Catalog::gCostM[pf[pi2]];
			}
			if (conBill > 0.f) {
				c.mCost += conBill;
				c.value = c.gain / (c.mCost + c.tCost);
			}
		}
		if (c.value > w.value) {
			w = c;
			w.kind = WK_TECH;
			@w.def = Catalog::Def(d);
			// The tech lab is the most protection-hungry building we own:
			// at the base anchor, never at a forward asker (watched).
			w.pos = lands;
			// WHERE THE LAB ACTUALLY LANDS, and how deep that is toward the
			// enemy. Reported twice as wrong from a watched game, so it is
			// measured rather than reasoned about.
			AiLog("apex: techsite " + Catalog::Def(d).GetName()
				+ " at " + int(w.pos.x) + "," + int(w.pos.z)
				+ " fwd=" + formatFloat(Military::ForwardFraction(w.pos), "", 0, 2)
				+ " askerFwd=" + formatFloat(Military::ForwardFraction(here), "", 0, 2)
				+ " farmSet=" + (gFarmSet ? 1 : 0)
				+ " anchorSet=" + (Base::gAnchorSet ? 1 : 0)
				+ " axisSet=" + (Base::gAxisSet ? 1 : 0)
				+ " facs=" + Factory::gFactoryCount
				+ " anchorFwd=" + formatFloat(Base::gAnchorSet ? Military::ForwardFraction(Base::gAnchor) : -9.f, "", 0, 2)
				+ " farmFwd=" + formatFloat(gFarmSet ? Military::ForwardFraction(gFarmPos) : -9.f, "", 0, 2)
				+ " axisRearward=" + (Base::AxisIsRearward() ? 1 : 0)
				+ " armyOurs=" + formatFloat(ArmyValue(), "", 0, 0)
				+ " armyFoe=" + formatFloat(Military::EnemyArmyCost(), "", 0, 0)
				+ " funded=" + formatFloat(fundedMul, "", 0, 2)
				+ " theirBest=" + formatFloat(ai.GetEnemyMaxMobileCostM(), "", 0, 0)
				+ " ourBest=" + formatFloat(OwnedBestMobileCostM(), "", 0, 0));
		}
	}
	return w;
}


}  // namespace Market
