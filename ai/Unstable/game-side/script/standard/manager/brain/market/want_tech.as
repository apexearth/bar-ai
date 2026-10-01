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
// The home risk is the same for every candidate in a frame; it is three
// cover queries, so it is not re-asked per rung.
int   gTsRiskFrame = -1;
float gTsRisk = 0.f;
float TechHomeRisk()
{
	if (gTsRiskFrame == ai.frame)
		return gTsRisk;
	gTsRiskFrame = ai.frame;
	gTsRisk = 0.f;
	if (ai.GetTunable("apex_tech_survival", TUNE_TECH_SURVIVAL) <= 0.f)
		return 0.f;
	if (!Builder::gHomeSet)
		return 0.f;
	const AIFloat3 home = Builder::gHomePos;
	if (!OnMap(home))
		return 0.f;
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
	gTsRisk = risk;
	return risk;
}

float TechSurvival(int defId, float askerBP)
{
	const float risk = TechHomeRisk();
	if (risk <= 0.f)
		return 1.f;
	float T = PipeLatencySec(defId, askerBP);
	// Same affordability the lathe actually sees (see ValueOf's feedSec):
	// half the bank is spendable now, the rest waits on income.
	const float inc = Eco::MInc();
	if (inc > 0.1f) {
		const float payS = (Catalog::gCostM[defId]
				- Eco::MCur() * 0.5f) / inc;
		if (payS > 0.f)
			T += payS;
	}
	return 1.f / (1.f + risk * T);
}

// Upgrade a spot we hold: gain is the extraction delta on the spot's real
// income. Pure arithmetic; capability comes free from BuildsOf.
// WHICH OF OUR CONSTRUCTORS CAN UPGRADE AN EXTRACTOR AT ALL, named once so a
// tool never has to guess it from a def name. apexearth wants the audit to
// fail when the cons that COULD be upgrading mexes are doing something else,
// and "which cons are those" is a build-graph question, not a naming one.
bool gUpConsLogged = false;
void LogUpgradeCons()
{
	if (gUpConsLogged || (Catalog::gDefCount <= 0))
		return;
	// The BASIC extractor's yield, read off the defs -- an "upgrade" is any
	// extractor that beats it. gExtractsM is the engine's extractsMetal, a
	// small float (a T1 mex is thousandths), not a multiplier, so a hardcoded
	// bar of 1.0 matched nothing and this line never printed once.
	float baseYield = -1.f;
	for (int e = 1; e <= Catalog::gDefCount; ++e) {
		if (!Catalog::gAvailable[e] || (Catalog::gExtractsM[e] <= 0.f))
			continue;
		if ((baseYield < 0.f) || (Catalog::gExtractsM[e] < baseYield))
			baseYield = Catalog::gExtractsM[e];
	}
	if (baseYield < 0.f)
		return;
	string names = "";
	int n = 0;
	for (int b = 1; b <= Catalog::gDefCount; ++b) {
		if (!Catalog::gMobile[b] || !Catalog::gBuilder[b])
			continue;
		const array<int>@ bl = Catalog::gBuildsList[b];
		bool canUp = false;
		for (uint q = 0; q < bl.length(); ++q) {
			// An extractor that outyields the basic one is an UPGRADE.
			if (Catalog::gExtractsM[bl[q]] > baseYield) {
				canUp = true;
				break;
			}
		}
		if (!canUp)
			continue;
		if (n > 0)
			names += ",";
		names += Catalog::Def(b).GetName();
		++n;
	}
	if (n <= 0)
		return;
	gUpConsLogged = true;
	AiLog(Factory::T() + "apex: upcons " + names);
}

// ONE HAND PER EXTRACTOR (apexearth 2026-09-30: the upgrade crew all walked to
// the same one -- "they'll just walk themselves into dangerous situations").
// A spot whose upgrade already has a hand is not offered again; each hand is
// priced onto its own, with its own walk and its own danger.
int gUpBusySkips = 0;
bool UpgradeUnderway(const AIFloat3& in spot)
{
	for (uint i = 0; i < Requests::gLive.length(); ++i) {
		IUnitTask@ t = Requests::gLive[i];
		if ((t is null) || t.IsDead() || (t.buildDef is null)
				|| (Catalog::gExtractsM[int(t.buildDef.id)] <= 0.f))
			continue;
		if ((Requests::Workers(t) > 0) && (t.GetBuildPos().distance2D(spot) <= Requests::SAME_SITE)) {
			++gUpBusySkips;
			return true;
		}
	}
	return false;
}

// Allied extractors below the best (apexearth 2026-09-30: "be willing to
// upgrade our allies' mexes"). BAR hands the new extractor to the owner of the
// one beneath it (unit_mex_upgrade_reclaimer), and CBMexUpTask's reclaim path
// only ever touches our own units.
void AllyUpgradeSpots(array<AIFloat3>@ pos, array<int>@ spot, array<float>@ inc, array<float>@ ext)
{
	AllyStaticsSync();
	CacheSpots();
	for (uint i = 0; i < gAllyStPos.length(); ++i) {
		const int d = gAllyStDef[i];
		if (Catalog::gExtractsM[d] <= 0.f)
			continue;
		int best = -1;
		float bestD = 64.f;
		for (uint s = 0; s < gAllSpots.length(); ++s) {
			const float dd = gAllSpots[s].distance2D(gAllyStPos[i]);
			if (dd < bestD) {
				bestD = dd;
				best = int(s);
			}
		}
		if (best < 0)
			continue;
		pos.insertLast(gAllyStPos[i]);
		spot.insertLast(best);
		inc.insertLast(gAllSpotInc[best]);
		ext.insertLast(Catalog::gExtractsM[d]);
	}
}

int gMuDiagAt = 0;
float gMuSurv = -1.f;
bool gMuAlly = false;
float gMuRaw = 0.f;
Want@ ProposeMexUp(CCircuitUnit@ unit)
{
	Want w;
	LogUpgradeCons();
	const int uid = int(unit.circuitDef.id);
	const array<int>@ builds = Catalog::BuildsOf(uid);
	const AIFloat3 here = unit.GetPos(ai.frame);
	const float speed = Catalog::gSpeed[uid];
	// Neither the economy nor a spot's survival odds depend on WHICH extractor
	// is being priced, and the survival read is three risk sweeps. Each is taken
	// at most once, on first use, so the call order is unchanged.
	float inc1 = 0.f;
	bool  incOk = false;
	const float growK = ai.GetTunable("apex_mex_growth", TUNE_MEX_GROWTH);
	// The handicap and the preference multiplier are the same for every spot
	// and every extractor; both sat in the inner loop.
	const float incMulU = IncomeMult();
	const float upBoost = ai.GetTunable("apex_mexup_boost", TUNE_MEXUP_BOOST);
	// Hoisted for the same reason as everything else here: it does not vary
	// with the spot or the extractor being priced.
	const float upBP = EffBP(Catalog::gBuildPower[uid]);
	array<AIFloat3> uPos;
	array<int> uSpot;
	array<float> uInc;
	array<float> uExt;
	for (uint li = 0; li < gLSpot.length(); ++li) {
		if (gLExtract[li] <= 0.f)
			continue;   // not finished (or already being replaced)
		uPos.insertLast(gLPos[li]);
		uSpot.insertLast(gLSpot[li]);
		uInc.insertLast(gLIncome[li]);
		uExt.insertLast(gLExtract[li]);
	}
	const uint nOwn = uPos.length();
	AllyUpgradeSpots(uPos, uSpot, uInc, uExt);
	for (uint li = 0; li < uPos.length(); ++li) {
		if (UpgradeUnderway(uPos[li]))
			continue;
		if (DeathWalk(unit, uPos[li]))
			continue;   // a forward mex we hold can still be a lethal walk
		// GROUND THE ENGINE HAS ALREADY REFUSED. An upgrade's position IS the
		// spot -- unlike a plant or a generator it cannot be moved -- so a spot
		// the reach-safe veto refuses can never be upgraded, and re-proposing
		// it is a pure loop -- thousands of moho task-deaths at one position,
		// and the churn behind want.mexup's frame cost.
		//
		// The mark expires, so a spot that becomes reachable -- the front
		// moves, a wreck clears -- returns to the ladder on its own.
		if (NearBlocked(uPos[li]))
			continue;
		float surv = -1.f;
		const float walkSecU = (speed > 1.f)
				? (here.distance2D(uPos[li]) / speed) : 60.f;
		// A spot under water takes a floating or submerged extractor and a
		// dry one a land extractor: an air con offered a land moho for a
		// naval mex, reclaimed the mex and could not build (his watch).
		const bool wet = ai.GetElevationAt(uPos[li]) < 0.f;
		for (uint i = 0; i < builds.length(); ++i) {
			const int d = builds[i];
			if (!Catalog::gAvailable[d] || (Catalog::gExtractsM[d] <= uExt[li]))
				continue;
			if (wet != (Catalog::gFloater[d] || Catalog::gSub[d]))
				continue;
			float delta = uInc[li] * incMulU
					* (Catalog::gExtractsM[d] - uExt[li]);
			// See want_mex.as: the raw metal/s, before any premium.
			const float rawUpM = delta;
			{
				// Share of TOTAL economic power, the same denominator the
				// energy premium uses -- see want_energy.as.
				if (!incOk) {
					inc1 = EcoPowerM();
					incOk = true;
				}
				delta *= 1.f + growK
						* delta / ((inc1 > delta) ? inc1 : delta);
			}
			// Quadrupling the yield of a spot we cannot hold quadruples
			// nothing -- the same discount the claim itself takes.
			if (surv < 0.f)
				surv = StreamSurvival(uPos[li]);
			delta *= surv;
			// HIS STATED PREFERENCE, PRICED TO THE MEASURED GAP. apexearth:
			// "We need to boost the priority on building upgraded metal
			// extractors. we go for doomsday and afus first... and that's not
			// good. Mex upgrade is the right choice."
			//
			// The audit says how far off it was: over one 60-minute game, of
			// 10,139 decisions by cons that COULD upgrade a mex, 505 (5%) were
			// upgrades, and 785 times an upgrade ranked second and lost --
			// 394 of those to energy, at a median winning/losing value ratio
			// of 2.79. So this is the size of the gap, not a number anybody
			// liked. It is a PREFERENCE expressed as a multiplier, not a
			// derived law: the honest alternative is that energy is overpriced
			// against extraction, which nobody has established.
			delta *= upBoost;
			// An upgrade is extraction too: same share, or the discount on
			// plain mexes would simply be arbitraged into mohos.
			delta *= MRealizeShare(rawUpM, walkSecU + Catalog::BuildSecondsAt(d, upBP));
			Want c;
			ValueOf(d, delta, walkSecU, Catalog::gBuildPower[uid], c);
			if (c.value > w.value) {
				w = c;
				w.kind = WK_MEXUP;
				@w.def = Catalog::Def(d);
				w.pos = uPos[li];
				w.spotId = uSpot[li];
				gMuAlly = (li >= nOwn);
				gMuSurv = surv;
				gMuRaw = rawUpM;
			}
		}
	}
	// WHICH SPOT THE UPGRADE PICKED, AND WHETHER DANGER MOVED THE CHOICE.
	// apexearth 2026-09-08: "the dumbass AI has upgraded our most dangerous
	// mexes - the first ones that would die... We have logic where building
	// stuff is perceived as less valuable when it is in a dangerous place. So
	// what the heck is going on?"
	//
	// The discount is real and IS applied (delta *= surv above). The suspect is
	// its input: StreamRisk reads HazardWith, and docs/24 already records that
	// reporting the FLOOR on our own ground while that ground was being taken
	// apart. If surv is the same at every spot, the discount cannot distinguish
	// a forward mex from a rear one and the pick is income-only. Nothing in the
	// risk model is logged anywhere, so this is the first reading of it.
	if ((w.kind == WK_MEXUP) && (ai.frame >= gMuDiagAt)) {
		gMuDiagAt = ai.frame + 15 * SECOND;
		AiLog("apex: mexup t=" + ai.teamId
			+ " at=" + int(w.pos.x) + "," + int(w.pos.z)
			+ " surv=" + formatFloat(gMuSurv, "", 0, 3)
			+ " raw=" + formatFloat(gMuRaw, "", 0, 2)
			+ " v=" + formatFloat(w.value, "", 0, 3)
			+ " homeD=" + int(w.pos.distance2D(Builder::gHomePos))
			+ " fwd=" + formatFloat(Military::ForwardFraction(w.pos), "", 0, 2)
			// The two halves of HazardWith, so the collapsing one is named:
			// grad scales the PREDICTIVE term and is ~0 on our own ground by
			// design; loss is RETROSPECTIVE and needs a death here first.
			+ " grad=" + formatFloat(GradAt(w.pos), "", 0, 3)
			+ " loss=" + formatFloat(LossRateAt(w.pos), "", 0, 4)
			+ " haz=" + formatFloat(HazardWith(w.pos, CoverAt(w.pos)), "", 0, 4)
			+ " ally=" + (gMuAlly ? 1 : 0) + " busySkips=" + gUpBusySkips);
	}
	return w;
}

// A plant priced by what it UNLOCKS: the upgrade demand its constructor
// products could serve that no builder we own can reach. Deliberately not
// gated by the lines-per-income rule (its return is better economics, not
// more parallel production). MODEL: the pipeline discount.
int gTechDiagAt = 0;

// The cheapest plant this builder can make whose products reach a better
// extractor or a better converter than anything we own -- the first move the
// tech ladder is measured with. 0 when there is none.
int CheapestAdvancedPlant(CCircuitUnit@ unit)
{
	const array<int>@ builds = Catalog::BuildsOf(int(unit.circuitDef.id));
	if (builds is null)
		return 0;
	const float ownCeil = OwnedCeil();
	const float ownConv = OwnConvCeil();
	int best = 0;
	for (uint i = 0; i < builds.length(); ++i) {
		const int d = builds[i];
		if (!Catalog::gAvailable[d] || Catalog::gMobile[d]
			|| (Catalog::gBuildsList[d].length() == 0))
			continue;
		float reach = 0.f;
		float conv = 0.f;
		const array<int>@ prod = Catalog::gBuildsList[d];
		for (uint q = 0; q < prod.length(); ++q) {
			const int pd = prod[q];
			if (!Catalog::gMobile[pd] || !Catalog::gBuilder[pd])
				continue;
			const array<int>@ pb = Catalog::gBuildsList[pd];
			for (uint r = 0; r < pb.length(); ++r) {
				if (Catalog::gExtractsM[pb[r]] > reach)
					reach = Catalog::gExtractsM[pb[r]];
			}
			const float cr = ConvRatioReach(pb);
			if (cr > conv)
				conv = cr;
		}
		if ((reach <= ownCeil) && (conv <= ownConv))
			continue;
		if ((best == 0) || (Catalog::gCostM[d] < Catalog::gCostM[best]))
			best = d;
	}
	return best;
}

// Does a plant we own or have in flight turn out a builder that lists x?
bool PlantDeliversBuild(int x)
{
	for (uint sk = 1; sk < gOwnCount.length(); ++sk) {
		const int sd = int(sk);
		if ((gOwnCount[sk] <= 0) || Catalog::gMobile[sd])
			continue;
		const array<int>@ sb = Catalog::gBuildsList[sd];
		for (uint q = 0; q < sb.length(); ++q) {
			if (Catalog::gMobile[sb[q]] && Catalog::gBuilder[sb[q]]
				&& (Catalog::gBuildsList[sb[q]].find(x) >= 0))
				return true;
		}
	}
	for (uint kl = 0; kl < Requests::gLive.length(); ++kl) {
		IUnitTask@ kt = Requests::gLive[kl];
		if ((kt is null) || (kt.buildDef is null) || Catalog::gMobile[int(kt.buildDef.id)])
			continue;
		const array<int>@ kb = Catalog::gBuildsList[int(kt.buildDef.id)];
		for (uint q = 0; q < kb.length(); ++q) {
			if (Catalog::gMobile[kb[q]] && Catalog::gBuilder[kb[q]]
				&& (Catalog::gBuildsList[kb[q]].find(x) >= 0))
				return true;
		}
	}
	return false;
}

bool OwnedBuilderLists(int x)
{
	for (uint dd = 1; dd < gOwnCount.length(); ++dd) {
		if ((gOwnCount[dd] > 0) && Catalog::gMobile[int(dd)] && Catalog::gBuilder[int(dd)]
			&& (Catalog::gBuildsList[int(dd)].find(x) >= 0))
			return true;
	}
	return false;
}

// THE WATER IS ITS OWN LADDER (apexearth 2026-09-28: a player in the water must
// always be able to reach the T2 yard). The naval moho extracts what the land
// moho does, so the value test read "nothing new" once T2 stood on land; a water
// plant unlocks when its builders reach an extractor nothing of ours can build
// and nothing we own or have ordered will deliver.
bool WaterPlantUnlocks(int d)
{
	if (PlantClass(d) != PC_WATER)
		return false;
	const array<int>@ prods = Catalog::gBuildsList[d];
	for (uint p = 0; p < prods.length(); ++p) {
		const int pd = prods[p];
		if (!Catalog::gMobile[pd] || !Catalog::gBuilder[pd])
			continue;
		const array<int>@ pb = Catalog::gBuildsList[pd];
		for (uint q = 0; q < pb.length(); ++q) {
			const int x = pb[q];
			if ((Catalog::gExtractsM[x] > 0.f) && Catalog::gAvailable[x]
				&& !OwnedBuilderLists(x) && !PlantDeliversBuild(x))
				return true;
		}
	}
	return false;
}

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
	float demand = UpDemand() + ConvUpDemand() + outclass;
	// THE CLIMB IS WORTH WHAT THE SIMULATOR SAYS IT SAVES. The demand terms
	// are proxies for one question -- does the world after an advanced plant
	// reach the target sooner -- and on a map with no spots the only proxy
	// left, conversion demand, reads zero once the basic converters cover our
	// income: 97 of them, no advanced lab in 33 minutes (apexearth: "the more
	// efficient energy is an obvious want"). The tech pool IS the world after
	// the plant; the seconds it saves, as a share of the journey, are the
	// power the climb brings forward, in the same metal/s the proxies speak.
	float etaSave = 0.f;
	if (EtaOn()) {
		const int lab = CheapestAdvancedPlant(unit);
		if (lab > 0) {
			const float base = EtaWith(0, 0.f, 0.f, false);
			const float tech = EtaWith(lab, 0.f, 0.f, true);
			if ((base < ETA_BIG) && (tech < base))
				etaSave = EcoPowerM() * (base - tech) / base;
		}
	}
	if (etaSave > demand)
		demand = etaSave;
	if (ai.frame >= gTechDiagAt) {
		gTechDiagAt = ai.frame + 120 * SECOND;
		AiLog("apex: tech-diag team=" + ai.teamId + " upD=" + demand
				+ " etaSave=" + formatFloat(etaSave, "", 0, 2)
				+ " outclass=" + formatFloat(outclass, "", 0, 2)
				+ " ceil=" + BestExtract() + " ownCeil=" + OwnedCeil()
				+ " spots=" + gLSpot.length() + " funded="
				+ (ArmyValue() / ((ArmyTarget() > 1.f) ? ArmyTarget() : 1.f)));
	}
	if (demand <= 0.5f)
		return w;
	// Dedup is PER DEF: a T1 rebuild in flight must not zero the T2 lab's
	// price.
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
		// A SUBMERGED plant has no placement model and is skipped. A FLOATING
		// one is not: this is the only lane that buys an advanced plant, and
		// excluding floaters is what made the T2 shipyard unreachable
		// altogether -- the plant lane picks the CHEAPEST shipyard by
		// construction (NavShipyardDef), so it only ever buys T1, and this
		// lane refused to look at corasy at all. That blocked the whole chain
		// apexearth asked for: advanced shipyard -> advanced construction sub
		// -> naval advanced mex (armuwmme/coruwmme, 620m, the same price as a
		// land moho). A floater still has to find water to stand in, which
		// WetPlantSite already answers, and it still has to win on price.
		if (!Catalog::gAvailable[d] || Catalog::gMobile[d] || Catalog::gSub[d])
			continue;
		if (Catalog::gFloater[d] && !MapHasWater())
			continue;
		if (Catalog::gBuildsList[d].length() == 0)
			continue;
		if (Requests::LiveOfDef(Catalog::Def(d)))
			continue;   // this def is already requested: help it, not double it
		// ONE ADVANCED PLANT AT A TIME, PER PLAYER -- the kin division below
		// only sees the extract/convert axes, so a T2 AIR lab in flight was
		// invisible to a T2 vehicle candidate and Purple raised both at once
		// ("a huge 'no no'"). Market::AdvPlantInFlight is the shared read the
		// air mandate defers on too.
		if (((Factory::userData[d].attr
			& (Factory::Attr::T2 | Factory::Attr::T3)) != 0)
			&& AdvPlantInFlight() && !WealthWaiver())
		{
			AdvDeferLog("tech:" + Catalog::Def(d).GetName());
			continue;
		}
		// HIS RULING, same law as ProposePlant's copy-zero: a tech plant we
		// already run unlocks nothing, and its throughput is the nano's job.
		// The door guard caught exactly this (a second armavp with one
		// finished) coming through the tech lane the plant lane had closed.
		if (!UnlocksProduct(d)
			&& ((ComCountOf(d, CS_FINISHED)
				+ ComCountManned(d, CS_FRAMED | CS_ORDERED)) >= 1)
			&& (DupBpSubstMul(d) < 1.f))
			continue;
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
		if (EcoQuiet() || EcoOnly())
			fundedMul = 1.f;   // no army mandate to fund in the economy-only benchmark
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
		// A WATER LAB IS FUNDED BY THE NAVY (his watched game 2026-09-28: a T2
		// yard started with no ship that could fight their subs). The land
		// target sits at zero under the T2 switch, which read as fully funded,
		// and their T2 fleet does not lift this floor: no fleet, no yard.
		// ...and the navy it needs is at least our share of the enemy army we
		// face, not the early target a couple of gunboats fill (his: a T2
		// yard at 3.5 minutes, "even with this bonus, way too early").
		// While we are blind the risk model's own prior stands in for their
		// fleet (SiegeExpect's basis). Below that navy the yard is not bought
		// at all -- a discount lost to a T2 gain this large (his: "3 minutes
		// in ... starting a tier 2 lab").
		float navyT = ArmyTargetFull() * NavyShare();
		const float foeShare = Military::EnemyArmyCost() * AnswerShare();
		if (foeShare > navyT)
			navyT = foeShare;
		const float foePrior = (gAssetsM - gProtM + ArmyValue())
				* ai.GetTunable("apex_enemy_prior", TUNE_ENEMY_PRIOR) * NavyShare();
		if (foePrior > navyT)
			navyT = foePrior;
		// The no-fleet-no-yard gate guards the too-early FIRST tier only; with
		// T2 standing on land it locked the water out for good.
		const bool firstTier = (prodCeil > ownCeil) || (prodConv > ownConv);
		if ((PlantClass(d) == PC_WATER) && (navyT > 1.f) && firstTier) {
			fundedMul = (NavyValue() >= navyT) ? 1.f : 0.f;
		} else {
			const float theirs = ai.GetEnemyMaxMobileCostM();
			const float ours = OwnedBestMobileCostM();
			if ((theirs > ours) && (theirs > 0.f)) {
				const float floorMul = 1.f - (ours / theirs);
				if (floorMul > fundedMul)
					fundedMul = floorMul;
			}
		}
		// Two plants can unlock the same thing; the one whose line is worth
		// less here -- its units times the ground they cross (want_plant
		// LineMul) -- is worth less for it. PlantLineWorth is the old
		// power-per-cost mean, kept as the control arm.
		const float lineW = (ai.GetTunable("apex_line_quality", TUNE_LINE_QUALITY) > 0.f)
				? LineMul(d) : PlantLineWorth(d);
		float techGain = 0.f;
		const bool waterUnlock = WaterPlantUnlocks(d);
		if ((prodCeil > ownCeil) || (prodConv > ownConv))
			techGain = demand * pipe / float(1 + liveKin);
		else if (waterUnlock)
			techGain = demand * pipe;
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
				// mobility-delta sliver.
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
			const bool unlocksTier = (prodCeil > ownCeil) || (prodConv > ownConv) || waterUnlock;
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
				// The lab adds only the flow the economy can feed it: while the
				// front is eating the army the spare is nil and the gap is the
				// lines' (apexearth: "a T2 lab while losing... never").
				float gapRate = (gapF > 0.f) ? gapF / ((fillS3 > 1.f) ? fillS3 : 60.f) : 0.f;
				if (gapRate > SpareMetalRate())
					gapRate = SpareMetalRate();
				const float gapStream = gapRate * pipe;
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
		// fleet lacks. Without this, 40-metal winds out-valued the 3300 tech
		// bill at argmax for five straight minutes of full storage.
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
		const AIFloat3 lands = LatheSite(Catalog::Def(d),
				Catalog::Def(int(unit.circuitDef.id)),
				InteriorSite(here, Catalog::Def(int(unit.circuitDef.id))));
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
			// ...but a FLOATING one cannot stand there at all -- it needs
			// water within the same rear leash, which WetPlantSite already
			// answers for the T1 shipyard.
			if (Catalog::gFloater[d]) {
				const AIFloat3 wet = WetPlantSite(Catalog::Def(d), lands);
				if (!OnMap(wet))
					continue;   // no reachable water: not a candidate here
				w.pos = wet;
			} else {
				w.pos = lands;
			}
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
