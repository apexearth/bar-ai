namespace Market {
// EVERY GENERATOR THIS ASKER PRICED, best value first. The proposer returns one
// rung, and the executor can be refused exactly that rung -- an advanced solar
// is strictly serial, a def at its in-flight cap is "full" -- with nothing to
// fall back on, so the asker ends the election holding nothing. Recorded per
// asker id, because StallWatch dry-runs this for other units.
array<int> gEAlt;
array<float> gEAltV;
int gEAltFor = -1;
int gNextEPickLog = 0;
int gNextEBigLog = 0;

// Wasted e/s beyond what the converters already in flight will eat. Read by
// both proposers: a generator while this is positive buys more of what is
// being thrown away.
float EnergyUnconverted()
{
	const float eWasted = (gEExcessEma > gESurplusEma) ? gEExcessEma : gESurplusEma;
	return eWasted - ConvCapInFlight();
}

// The smallest converter we can build eats this much e/s: the unit of waste
// that is a converter's job rather than noise (the opening's full energy
// bank otherwise reads as waste).
float gConvUnit = -1.f;
float ConverterUnitE()
{
	if (gConvUnit > 0.f)
		return gConvUnit;
	float best = 0.f;
	for (int i = 1; i <= Catalog::gDefCount; ++i) {
		if (!Catalog::gAvailable[i] || Catalog::gMobile[i] || (Catalog::gConvCapacity[i] <= 0.f))
			continue;
		if ((best <= 0.f) || (Catalog::gConvCapacity[i] < best))
			best = Catalog::gConvCapacity[i];
	}
	gConvUnit = (best > 0.f) ? best : 70.f;
	return gConvUnit;
}

// Waste a converter is the answer to: at least one converter's own eat.
bool EnergyWasting()
{
	return EnergyUnconverted() >= ConverterUnitE();
}

int gGenHeldLogAt = 0;
Want@ ProposeEnergy(CCircuitUnit@ unit)
{
	Want w;
	const int uid = int(unit.circuitDef.id);
	// NO GENERATOR WHILE ENERGY IS BEING THROWN AWAY (apexearth 2026-09-16,
	// 5,800 e/s income, 2,000 wasted, a fusion elected 41 times: "instead
	// we're making even more energy... very stupid"). Reverses the 09-11
	// "energy always" ruling for exactly this case: the converters are the
	// answer to waste, and a rung priced beside them was drawn anyway.
	// Not a gate on the rungs (tried, measured worse -- commit 28504349):
	// the waste is the converters' price. The instrument stays.
	if (EnergyWasting() && (ai.frame >= gGenHeldLogAt)) {
		gGenHeldLogAt = ai.frame + 30 * SECOND;
		AiLog("apex: gen-wasting t=" + ai.teamId + " unconverted="
			+ int(EnergyUnconverted()) + " e/s");
	}
	const double _tPre = Perf::T0();
	const AIFloat3 eSite = EcoSiteFor(unit);
	gEAlt.resize(0);
	gEAltV.resize(0);
	gEAltFor = int(unit.id);
	const array<int>@ builds = Catalog::BuildsOf(uid);
	// STALLED AND SMALL MEANS SOLAR, FULL STOP (apexearth: "the best thing to
	// build for energy when you have 100e/s income is a basic solar because it
	// costs no energy to make. There's no question about it... if we are
	// e-stalling and we have less than 300 energy per second, MAKE A BASIC
	// SOLAR"). Identified by the property that decides it -- a generator whose
	// own build costs no energy -- not by name, so it holds for all three
	// factions (armsolar/corsolar/legsolar are 0 E; wind is 175, advanced solar
	// 5,000). Nothing else can be paid for out of an economy that has no energy.
	// Above the bar, or with no zero-E generator in this builder's options, the
	// whole ladder competes on price as before.
	bool solarOnly = false;
	if (HardEStall()
		&& (aiEconomyMgr.energy.income
			< ai.GetTunable("apex_stall_solar_e", TUNE_STALL_SOLAR_E)))
	{
		for (uint z = 0; z < builds.length(); ++z) {
			const int zd = builds[z];
			if (!Catalog::gAvailable[zd] || Catalog::gMobile[zd]
				|| Catalog::gFloater[zd] || Catalog::gSub[zd]
				|| Catalog::gNeedGeo[zd])
				continue;
			if ((Catalog::gMakeE[zd] > 1.f) && (Catalog::gCostE[zd] <= 0.f)) {
				solarOnly = true;
				break;
			}
		}
	}
	// NOTHING IN THIS BLOCK VARIES WITH THE RUNG. Every one of them was re-asked
	// for each generator in the ladder: two of them walk the def table, one
	// walks every standing turret, and the tunables build a string and hit a map.
	const float genBP = EffBP(Catalog::gBuildPower[uid]);
	const float genRatio = BestConvRatio();
	const float genPower = EcoPowerM();
	const float genGrowK = ai.GetTunable("apex_energy_growth", TUNE_ENERGY_GROWTH);
	const bool  genSurvOn = ai.GetTunable("apex_eco_survival", TUNE_ECO_SURVIVAL) > 0.f;
	const bool  genInferiorOn = ai.GetTunable("apex_inferior_discount",
			TUNE_INFERIOR_DISCOUNT) > 0.f;
	const float genBestEPerM = genInferiorOn ? OwnedBestEPerM() : 0.f;
	// SpaceRentM is perCell x cells x k, so one cell's worth answers every
	// footprint -- it walked the whole defence field per rung for the same number.
	const float genRentCell = SpaceRentM(eSite, 1);
	const bool  genDiag = ai.GetTunable("apex_efloor_diag", 0.f) > 0.f;
	// ROOM IS LOCAL (protect_field.as on PfCrowd: the base-wide fill FALLS as
	// the base grows, 0.024 in a full base against 0.15 at the site). The
	// ground a reactor competes for is the ground around where it would stand.
	const float genCrowdCell = PfCrowdAt(eSite, 400.f) * PfMetalPerCell()
			* ai.GetTunable("apex_room_worth", TUNE_ROOM_WORTH);
	// A STALL IS ENDED BY WHAT ARRIVES SOONEST, not by the best rate of return:
	// the growth premium scales with a generator's size, so an afus out-valued
	// a fusion 4:1 while taking four times as long to close the same deficit
	// (apexearth 2026-09-08: "too early btw, fusion would have been smarter").
	const float stallDef = HardEStall() ? EnergyDeficitNowE() : 0.f;
	float bestClose = 0.f;
	const bool etaOn = EtaOn();
	const float etaP = EcoPowerM();
	// ...AND THE SAME ERROR IS LIVE ONE RUNG HIGHER, outside the stall: the
	// growth premium below is linear in a generator's output and so is its
	// cost, so value rises with size and the biggest reactor on the list wins
	// for being big. Charged instead on the share of the plan's own horizon
	// the generator would be paying over (docs/27 TUNE_ENERGY_GROWTH_ARRIVE).
	const bool genArriveOn = ai.GetTunable("apex_energy_growth_arrive",
			TUNE_ENERGY_GROWTH_ARRIVE) > 0.f;
	// One number for every rung; the ETA arm below asked the turret grid for it
	// once per generator.
	const float genNanoBP = (genArriveOn || etaOn) ? NanoLatheReaching(eSite) : 0.f;
	// Seconds to the target following the ladder AS IT STANDS: the window new
	// income has to compound in before the plan is over.
	const float genHorizonS = genArriveOn ? EtaWith(0, 0.f, 0.f, false) : 0.f;
	string bigLine = "";
	int etaD = -1;
	float etaS = 0.f;
	Want etaW;
	Perf::Add("en.pre", _tPre);
	for (uint i = 0; i < builds.length(); ++i) {
		const int d = builds[i];
		if (!Catalog::gAvailable[d] || Catalog::gMobile[d] || Catalog::gFloater[d] || Catalog::gSub[d])
			continue;   // floaters need water; land-base v1 (see armfmkr churn)
		if (Catalog::gMakeE[d] <= 1.f)
			continue;
		// NEVER BUILD WHAT WE WOULD EAT: a rung the per-cell dwarf test
		// already marks edible is obsolete ON ARRIVAL (his "we should never
		// want to create obsolete buildings" -- the reclaim-rebuild loop was
		// this ladder re-placing the wind the reclaim side had just eaten).
		// The hard-stall basic solar keeps its "full stop" ruling.
		// ...EXCEPT WHILE ENERGY IS SHORT: the dwarf law made the advanced
		// solar obsolete the moment a fusion-capable hand existed, so a stall
		// at 1,300 E/s was answered with a ten-minute fusion by the T2 hands
		// and basic solars by the T1 ones, and nothing in between (his Comet
		// 1v1: 27 basic solars, 10 advanced, one fusion, the enemy at 250
		// m/s). A deficit is closed by what ARRIVES soonest; the ETA pick
		// below chooses among all rungs while it lasts.
		if (GenObsoleteOnArrival(d) && !HardEStall()
			&& !(solarOnly && (Catalog::gCostE[d] <= 0.f)))
			continue;
		// A PREFERENCE THAT STILL LEAVES AN ANSWER. The zero-E rung cannot win
		// ground it has none of -- on a water base solar has nowhere to stand --
		// so the dearer rungs stay in the ladder below as fallbacks and only
		// lose their claim on the WINNER.
		const bool barred = solarOnly && (Catalog::gCostE[d] > 0.f);
		if (Catalog::gNeedGeo[d])
			continue;   // vents are the geo want's ground, not free placement
		Want c;
		float bSec = Catalog::BuildSecondsAt(d, genBP);
		bSec *= EStretch(Catalog::gCostE[d], bSec);
		const float fPrice = EPriceAt(bSec);
		// The hands that would actually stand on this site. Shared with the
		// ETA arm at the foot of the loop, which fills it if this does not.
		float crewBP = 0.f;
		if (genArriveOn)
			crewBP = Catalog::gBuildPower[uid]
					* float(Requests::SiteWorkerCap(Catalog::Def(d))) + genNanoBP;
		float fArr = 1.f;
		float fGrow = 1.f, fSurv = 1.f, fInf = 1.f, fReal = 1.f, fRent = 0.f;
		float gain = Catalog::gMakeE[d] * fPrice;
		// ECO COMPOUNDS, AND ENERGY IS ECO (apexearth: "we are not properly
		// multiplying the benefits of a strong eco... the more we boost eco the
		// more all of our other metrics get boosted"). Decays with wealth on
		// its own, so it stops mattering once we are rich.
		// ONE CURRENCY, ONE DENOMINATOR. Measured against ENERGY income alone
		// this premium saturated: a fusion roughly doubles energy income and
		// so took the full 9x, while a moho adding 5 m/s onto 40 m/s of metal
		// took 1.6x out of the identical formula. That gap was an artefact of
		// the two economies' granularity, not a fact about the game
		// (apexearth: "all our T2 cons are going for a fusion before making
		// any T2 mexes... T2 mex is much faster, and quadruples the mex value.
		// The math MUST reflect this"). Both sides now ask one question --
		// what share of TOTAL economic power does this add -- with energy
		// carried at what a converter would actually pay for it.
		{
			// At the conversion floor: the compounding part is the permanent
			// income, and pricing it at the stall premium saturated the 9x
			// on any big generator mid-stall (an advanced solar at 64 e/s).
			const float mkM = Catalog::gMakeE[d] * genRatio;
			float mkEff = mkM;
			// The CREW's seconds, not one lathe's: priced solo every reactor
			// misses every horizon and the ladder would stop at fusions.
			if (genArriveOn && (genHorizonS > 1.f)) {
				float aSec = Catalog::BuildSecondsAt(d,
						(crewBP > genBP) ? crewBP : genBP);
				aSec *= EStretch(Catalog::gCostE[d], aSec);
				const float pay = genHorizonS - aSec;
				fArr = (pay > 0.f) ? (pay / genHorizonS) : 0.f;
				mkEff = mkM * fArr;
			}
			// THE PREMIUM MUST NOT BE BOUGHT WITH SIZE. gain is already linear
			// in a generator's output, so multiplying it again by that output's
			// share of the economy counts the addition twice -- and because the
			// denominator is max(economy, output), anything bigger than the whole
			// economy collects the FULL multiplier. One 30,000 E reactor took 9x
			// where thirty 1,000 E ones adding the same energy take 1.27x each,
			// which is why the biggest rung always won and why the scavenger
			// pack's t3 reactors cost a third of the economy.
			// Read the appetite off the ECONOMY instead: every rung in one
			// election then carries the same premium, and the ranking is left to
			// gain over cost, when it arrives, and what we can absorb.
			float growNum = mkEff;
			const bool growFlat =
					ai.GetTunable("apex_energy_growth_flat", TUNE_ENERGY_GROWTH_FLAT) > 0.f;
			if (growFlat)
				growNum = EnergyDeficitE() * genRatio;
			fGrow = 1.f + genGrowK
					* growNum / ((genPower > growNum) ? genPower : ((growNum > 0.f) ? growNum : 1.f));
			gain *= fGrow;
			// The arrival discount rode inside mkEff; with the premium flat it has
			// to be charged on its own or a ten-minute build pays nothing for the
			// wait.
			if (growFlat && genArriveOn && (fArr >= 0.f) && (fArr < 1.f))
				gain *= fArr;
		}
		// A DEFERRED PURCHASE IS WORTH ONLY WHAT SURVIVES TO PAY IT BACK. An
		// afus is minutes of building and more of payback, and if the base
		// falls first its gain was zero -- the energy price said nothing about
		// that, which is the same hole the tech want already closed
		// (apexearth: "we keep making AFUS and its so insanely stupid. Enemy
		// walks up to us with a tzar and just completely annihilates us. one
		// damn unit and we have nothing to defend ourselves against it").
		// Scales with the build's own latency, so cheap fast generators are
		// untouched and only the long bets are discounted; and with measured
		// hazard, so it lifts by itself once the base is actually covered.
		if (genSurvOn) {
			const double _tSv = Perf::T0();
			fSurv = TechSurvival(d, Catalog::gBuildPower[uid]);
			Perf::Add("en.surv", _tSv);
			gain *= fSurv;
		}
		// INFERIOR WORK IS WORTH LESS, IT IS NOT FORBIDDEN. The same build
		// power spent through a constructor that CAN build the better
		// generator returns more energy per metal, so this one's gain carries
		// the ratio. A preference, not a veto: with nobody able to do better
		// the ratio is 1, so the opening is untouched, and a worker whose only
		// option is the inferior one still takes it when nothing else competes
		// -- it just loses to assisting the better build first.
		// Void while the stall bars the better rung: nobody can build it either.
		if (genInferiorOn && !solarOnly) {
			const float mine = (Catalog::gCostM[d] > 0.f)
					? (Catalog::gMakeE[d] / Catalog::gCostM[d]) : 0.f;
			if ((genBestEPerM > mine) && (mine > 0.f)) {
				fInf = mine / genBestEPerM;
				gain *= fInf;
			}
		}
		// AND ONLY THE PART OF IT ANYTHING WOULD USE. Generation on top of an
		// already-wasted band makes no metal until a converter chews it, so its
		// gain decays across the waste line instead of being priced as though a
		// converter were free and standing. See ERealizeShare in price.as.
		fReal = ERealizeShare(Catalog::gMakeE[d], bSec);
		gain *= fReal;
		if (gain <= 0.f)
			continue;
		const float walkSec = WalkSecTo(unit, eSite);
		const double _tVo = Perf::T0();
		ValueOf(d, gain, walkSec, Catalog::gBuildPower[uid], c);
		Perf::Add("en.value", _tVo);
		// Rent on the defended ground this footprint would occupy -- PLUS the
		// measured scarcity of base room, the same term RetireGain charges.
		// Priced only on the reclaim side, the pair could not converge: the
		// buy side kept placing wind (best E per METAL) on ground the retire
		// side was clearing for being worst E per CELL -- 232 winds built
		// across one watched 8v8 whose players already owned AFUS and had
		// "run out of building room" (apexearth). One law, both halves.
		{
			const float cellsE = float((Catalog::gAreaCells[d] > 0)
					? Catalog::gAreaCells[d] : 1);
			const double _tBl = Perf::T0();
			const float blast = BlastCollateralM(eSite, d);   // its fuse, and its neighbours'
			Perf::Add("en.blast", _tBl);
			const float rent = ((Catalog::gAreaCells[d] > 0)
						? (genRentCell * float(Catalog::gAreaCells[d])) : 0.f)
					+ genCrowdCell * cellsE
					+ blast;
			if (rent > 0.f) {
				fRent = rent;
				c.mCost += rent;
				c.value = (c.gain > 0.f) ? (c.gain / (c.mCost + c.tCost)) : 0.f;
			}
		}
		if (genDiag) {
			const float wage = Wage();
			const float walkM = walkSec * WalkRateWith(Catalog::gBuildPower[uid], wage);
			const float buildM = c.buildSec * wage;
			AiLog("apex: ewant t=" + ai.teamId + " " + unit.circuitDef.GetName()
				+ " #" + unit.id + " " + Catalog::Def(d).GetName()
				+ (barred ? " barred" : "")
				+ " v=" + formatFloat(c.value, "", 0, 2)
				+ " close=" + formatFloat((stallDef > 0.f)
					? (((Catalog::gMakeE[d] < stallDef) ? Catalog::gMakeE[d] : stallDef)
						/ (walkSec + ((bSec > c.buildSec) ? bSec : c.buildSec) + 1.f)) : 0.f, "", 0, 2)
				+ " gain=" + formatFloat(c.gain, "", 0, 2)
				+ " (mkE=" + formatFloat(Catalog::gMakeE[d], "", 0, 1)
				+ " P=" + formatFloat(fPrice, "", 0, 3)
				+ " grow=" + formatFloat(fGrow, "", 0, 2)
				+ " arr=" + formatFloat(fArr, "", 0, 2)
				+ " surv=" + formatFloat(fSurv, "", 0, 2)
				+ " inf=" + formatFloat(fInf, "", 0, 2)
				+ " real=" + formatFloat(fReal, "", 0, 2) + ")"
				+ " m=" + formatFloat(c.mCost, "", 0, 0)
				+ " (M" + formatFloat(Catalog::gCostM[d] * MCostScale(), "", 0, 0)
				+ "+E" + formatFloat(Catalog::gCostE[d]
					* EPriceCostAt(c.buildSec, Catalog::gCostE[d]), "", 0, 0)
				+ "+A" + Catalog::gAreaCells[d]
				+ "+rent" + formatFloat(fRent, "", 0, 0) + ")"
				+ " t=" + formatFloat(c.tCost, "", 0, 0)
				+ " (walk" + formatFloat(walkM, "", 0, 0)
				+ "+build" + formatFloat(buildM, "", 0, 0)
				+ "+late" + formatFloat(c.gain * walkSec, "", 0, 0)
				+ "+rest" + formatFloat(c.tCost - walkM - buildM - c.gain * walkSec, "", 0, 0)
				+ ") walk=" + formatFloat(walkSec, "", 0, 0)
				+ "s build=" + formatFloat(c.buildSec, "", 0, 0)
				+ "s | e " + int(aiEconomyMgr.energy.current) + "/" + int(aiEconomyMgr.energy.storage)
				+ " inc=" + int(aiEconomyMgr.energy.income)
				+ " pull=" + int(aiEconomyMgr.energy.pull)
				+ " drainIF=" + int(EDrainInFlight())
				+ " makeIF=" + int(EMakeInFlight())
				+ " spot=" + formatFloat(EPrice(), "", 0, 3)
				+ " floor=" + formatFloat(EPriceFloor(), "", 0, 4)
				+ " mPull=" + int(aiEconomyMgr.metal.pull)
				+ " mInc=" + formatFloat(aiEconomyMgr.metal.income, "", 0, 1)
				+ " stall=" + (HardEStall() ? 1 : 0)
				+ " solarOnly=" + (solarOnly ? 1 : 0));
		}
		if (c.value > 0.f) {
			uint at = 0;
			while ((at < gEAltV.length()) && (gEAltV[at] >= c.value))
				++at;
			gEAlt.insertAt(at, d);
			gEAltV.insertAt(at, c.value);
		}
		bool wins = !barred && (c.value > w.value);
		if (!barred && (stallDef > 0.f)) {
			float wait = walkSec + ((bSec > c.buildSec) ? bSec : c.buildSec);
			// An energy-costing rung is fed from the SURPLUS and the bank, and in
			// a hard stall that is nothing: 37 advsol executions stood one advsol
			// in 16 minutes at a bank of 6 (canon game 2026-09-08). The zero-E
			// rung's wait is its build; the others' is their energy bill over
			// what can actually feed it.
			if (Catalog::gCostE[d] > 0.f) {
				float feedE = aiEconomyMgr.energy.income - aiEconomyMgr.energy.pull;
				if (feedE < 0.f)
					feedE = 0.f;   // in-flight make is what is starved, not feed (EStretch)
				const float lookE = ai.GetTunable("apex_e_lookahead", TUNE_E_LOOKAHEAD);
				feedE += aiEconomyMgr.energy.current / ((lookE > 1.f) ? lookE : 30.f);
				const float waitE = walkSec + Catalog::gCostE[d] / ((feedE > 1.f) ? feedE : 1.f);
				if (waitE > wait)
					wait = waitE;
			}
			const float closes = (Catalog::gMakeE[d] < stallDef) ? Catalog::gMakeE[d] : stallDef;
			const float close = closes / ((wait > 1.f) ? wait : 1.f);
			wins = (close > bestClose);
			if (wins)
				bestClose = close;
		}
		if (wins) {
			w = c;
			w.kind = WK_ENERGY;
			@w.def = Catalog::Def(d);
			w.pos = eSite;
		}
		// WHICH GENERATOR: the one that brings the target soonest, not the one
		// the multiplier stack rates highest. The ladder already decides which
		// KIND of growth holds the economy's ticket; the proposer chose the DEF
		// with premiums that priced a plant by the square of its size, so it
		// offered the ladder an advanced fusion and never a fusion (apexearth:
		// "we lose because we try to make AFUS before making fusion"). Same
		// question, same arithmetic, one level down -- in a stall too: the
		// closes-soonest rule is a RATE, so a deficit past 3,000 e/s handed
		// every stalled election to the advanced fusion (measured, 14 of 16),
		// where the ladder's energy arm makes a 69,000 E bill wait its turn.
		if (etaOn && !barred && (c.value > 0.f)) {
			const double _tEt = Perf::T0();
			const float gM = Catalog::gMakeE[d] * ConvRate();
			if (crewBP <= 0.f)
				crewBP = Catalog::gBuildPower[uid]
						* float(Requests::SiteWorkerCap(Catalog::Def(d))) + genNanoBP;
			const float s = walkSec + EtaWithN(d, gM, 0.f, false, EtaBatchN(gM, etaP), crewBP);
			Perf::Add("en.eta", _tEt);
			if ((etaD < 0) || (s < etaS)) {
				etaS = s;
				etaD = d;
				etaW = c;
			}
			if (Catalog::gCostM[d] > 3000.f)
				bigLine += " " + Catalog::Def(d).GetName() + "=" + int(s);
		}
	}
	// A reactor-class election is logged whether or not the two agree: the
	// pick that mattered was the one the disagreement filter never showed.
	if (etaOn && (bigLine.length() > 0) && (w.def !is null) && (ai.frame >= gNextEBigLog)) {
		gNextEBigLog = ai.frame + 5 * SECOND;
		AiLog(Factory::T() + "apex: ebig t=" + ai.teamId + " " + unit.circuitDef.GetName()
			+ " #" + unit.id + " mkt=" + w.def.GetName()
			+ " eta=" + ((etaD > 0) ? Catalog::Def(etaD).GetName() : "-")
			+ " |" + bigLine
			// The room terms, so "value the space more" can be read against
			// what the site actually charges (apexearth 2026-09-13).
			+ " | hz=" + int(genHorizonS)
			+ " rentCell=" + formatFloat(genRentCell, "", 0, 2)
			+ " crowdCell=" + formatFloat(genCrowdCell, "", 0, 2)
			+ " crowd=" + formatFloat(PfCrowd(), "", 0, 3)
			+ " local=" + formatFloat(PfCrowdAt(eSite, 400.f), "", 0, 3)
			+ " m/cell=" + formatFloat(PfMetalPerCell(), "", 0, 1));
	}
	if (etaOn && (etaD > 0) && (w.def !is null) && (int(w.def.id) != etaD)) {
		const float mktS = w.walkSec + EtaWithN(int(w.def.id),
				Catalog::gMakeE[int(w.def.id)] * ConvRate(), 0.f, false,
				EtaBatchN(Catalog::gMakeE[int(w.def.id)] * ConvRate(), etaP), 0.f);
		// A TIE GOES TO THE MARKET. The ladder's seconds carry a per-order
		// latency guess on every rung of the plan; a reactor it calls sooner
		// by less than that guess is not sooner (measured: fusion 7800 s
		// against the advanced fusion's 8257 at 1,142 income, every election,
		// so the AFUS never came -- his "we keep building fusion for too
		// long"). The market's pick carries survival, the crew it would get,
		// the room and the compounding the ladder does not price.
		// THE TIE-BREAK WAS SYMMETRIC AND THE CONSEQUENCES ARE NOT. The market's
		// pick is the bigger reactor in every disagreement measured (168 of 221
		// in a watched game, never once smaller), so a flat latency allowance
		// always hands the tie to the larger commitment. Being wrong about a
		// fusion costs its build; being wrong about an epic fusion freezes the
		// whole fleet for the length of one. Charge the difference: the market
		// must beat the ladder by a share of the extra fleet-time it locks up.
		float latBar = gLadderLatS;
		{
			const float cb = ai.GetTunable("apex_eta_commit_bonus", TUNE_ETA_COMMIT_BONUS);
			if (cb > 0.f) {
				const float ubp = Catalog::gBuildPower[uid];
				const float bp = (ubp > 1.f) ? ubp : 100.f;
				const float extra = Catalog::BuildSecondsAt(int(w.def.id), bp)
						- Catalog::BuildSecondsAt(etaD, bp);
				if (extra > 0.f)
					latBar -= cb * extra;
			}
		}
		const bool sooner = etaS < mktS - latBar;
		if (ai.frame >= gNextEPickLog) {
			gNextEPickLog = ai.frame + 15 * SECOND;
			AiLog(Factory::T() + "apex: epick t=" + ai.teamId + " " + unit.circuitDef.GetName()
				+ " mkt=" + w.def.GetName() + " v=" + formatFloat(w.value * 1000.f, "", 0, 2)
				+ " eta=" + Catalog::Def(etaD).GetName() + " s=" + int(etaS)
				+ " mktS=" + int(mktS) + " lat=" + int(latBar)
				+ (sooner ? " eta-wins" : " tie-mkt"));
		}
		if (sooner) {
			w = etaW;
			w.kind = WK_ENERGY;
			@w.def = Catalog::Def(etaD);
			w.pos = eSite;
		}
	}
	return w;
}

// TOTAL ECONOMIC POWER, in metal/s. Metal income alone is not how big the
// economy is: what pays for buildings is metal AND the energy a converter
// would turn into metal, and reading only the metal side made every
// "how big are we" question answer near zero whenever energy ran ahead.
// Measured on a map with no metal spots at all: 183 e/s of income, 46k
// energy wasted, 3 m/s of metal, BPGap pinned at zero, and so the factory
// want never cleared its own floor -- one builder, no factory and nothing
// built for a whole game, with the enemy AI stuck the same way. Only the
// surplus nothing already converts is counted; standing converters' output
// is inside metal.income already (apexearth: "if math is not prioritizing
// what would double or triple our total economic power, then the math is
// wrong").
float StandingConvCap()
{
	float cap = 0.f;
	for (uint cd = 1; cd < gOwnCount.length(); ++cd) {
		if (gOwnCount[cd] > 0)
			cap += float(gOwnCount[cd]) * Catalog::gConvCapacity[int(cd)];
	}
	return cap;
}

// GROUND TRUTH FOR THE CONVERTER FLEET. BAR's own converter gadget
// (game_energy_conversion.lua) publishes the team's maker capacity and what
// they are actually chewing as team rules params, and it charges that draw as
// each maker's unit energy use -- which lands in the team's energy PULL. So
// pull is already net of standing converters, and anything reading a surplus
// must not subtract them a second time. Falls back to the catalog when the
// params are absent (a game without that gadget).
float ConvCapE()
{
	const float cap = ai.GetTeamRulesParam("mmCapacity", -1.f);
	return (cap >= 0.f) ? cap : StandingConvCap();
}

float ConvUseE()
{
	const float use = ai.GetTeamRulesParam("mmUse", -1.f);
	if ((use >= 0.f) && (ai.GetTunable("apex_e_realize", TUNE_E_REALIZE) > 0.f))
		return use;
	// No param: assume the fleet chews whatever surplus it can hold.
	const float sur = aiEconomyMgr.energy.income - aiEconomyMgr.energy.pull;
	const float cap = StandingConvCap();
	if (sur <= 0.f)
		return 0.f;
	return (sur < cap) ? sur : cap;
}

// Converter capacity ORDERED and not yet standing: not in pull, not in the
// rules params, and the only reason a second converter want should read a
// smaller surplus than the first.
// Capacity that is COMING, not merely ordered: an order no hand is on
// counts only for what stands of it. Ordered-but-unstaffed converters read
// as capacity, the want priced at zero behind them, and 10k E/s overflowed
// for ten minutes with 7,200 metal of converters "in flight" (watched).
float ConvCapInFlight()
{
	float cap = 0.f;
	for (uint i = 0; i < Requests::gLive.length(); ++i) {
		IUnitTask@ t = Requests::gLive[i];
		if ((t is null) || t.IsDead() || (t.buildDef is null))
			continue;
		const float c = Catalog::gConvCapacity[int(t.buildDef.id)];
		if (c <= 0.f)
			continue;
		if (Requests::Workers(t) > 0)
			cap += c;
		else
			cap += c * Requests::Progress(t);
	}
	return cap;
}

// ENERGY WE HAVE ALREADY ORDERED AND ARE NOT YET DRAWING. energy.pull is what
// the fleet draws NOW, so the bill for work already committed is invisible
// until its frames are placed -- which is why the first energy want cannot
// price above the converter floor until the stall it should have prevented has
// already arrived (measured: first energy decision 73 seconds in, with pull
// already 2.5x income at two minutes). Same shape as ConvCapInFlight above:
// live requests, remaining cost over remaining time.
// ENERGY WE HAVE ALREADY ORDERED AND WILL SOON MAKE. The mirror of the drain
// above, and the number that says whether the answer to a stall is big enough
// yet.
// A WHOLE-LEDGER SUM HAS NO RADIUS, so the index cannot help it; what it has is
// gComStamp. Every asker in one election reads the same ledger, so the second
// walk onward is the first walk's answer -- and the stamp, not the frame alone,
// is what makes that safe: a task added mid-frame moves it. The rest of what
// this reads (def catalogue) is fixed for the game.
float gEMakeVal = 0.f;
int   gEMakeFrame = -1;
int   gEMakeStamp = -1;

// HOW LONG A NEW GENERATOR TAKES TO STAND UP, for the cheapest rung we can
// actually build. HardEStall asks it whether the energy bank outlasts the fix:
// a stall is a stall the moment the store will run dry before a generator
// finishes, whatever share of the bank is left. Same filters the generator
// ladder itself uses, so the two cannot disagree about what a generator is.
float EGenBuildSeconds()
{
	float best = -1.f;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!Catalog::gAvailable[d] || Catalog::gMobile[d] || Catalog::gFloater[d]
			|| Catalog::gSub[d] || Catalog::gNeedGeo[d])
			continue;
		if (Catalog::gMakeE[d] <= 1.f)
			continue;
		const float sec = Catalog::BuildSecondsAt(d, EffBP(0.f));
		if ((sec > 0.f) && ((best < 0.f) || (sec < best)))
			best = sec;
	}
	return best;
}

float EMakeInFlight()
{
	if ((gEMakeFrame == ai.frame) && (gEMakeStamp == gComStamp))
		return gEMakeVal;
	// Ledger COMING rows (flipped 2026-08-27): an orphaned generator frame
	// is energy on the way exactly as an ordered one is -- nanos finish it.
	// Energy-costing generation counts only at the share its own bill can be
	// fed: ordered advanced solars stuck at a dry bank read as hundreds of
	// e/s of coming supply, which priced the nanos that kept them stuck
	// (seed 12, minutes 12-19: nano gain at its full 17.2 with the bank at 1).
	float s = 1.f;
	{
		const float need = aiEconomyMgr.energy.pull + EDrainInFlight();
		const float have = aiEconomyMgr.energy.income + aiEconomyMgr.energy.current / 30.f;
		if ((need > have) && (have > 0.f))
			s = have / need;
	}
	float e = 0.f;
	for (uint i = 0; i < ComLen(); ++i) {
		if (gComState[i] == CS_FINISHED)
			continue;
		const int d = gComDef[i];
		e += Catalog::gMakeE[d] * ((Catalog::gCostE[d] > 1.f) ? s : 1.f);
	}
	gEMakeFrame = ai.frame;
	gEMakeStamp = gComStamp;
	gEMakeVal = e;
	return e;
}

// What the ordered generators make ONCE FED -- the make the stall hoist
// has to compare its answer against: a second frame started beside a
// crawling reactor draws on the same feed, so it arrives no sooner than
// the first would have with the hands on it.
float EMakeOrderedE()
{
	float e = 0.f;
	for (uint i = 0; i < ComLen(); ++i) {
		if (gComState[i] == CS_FINISHED)
			continue;
		e += Catalog::gMakeE[gComDef[i]];
	}
	return e;
}

// IS THE ANSWER TO THIS STALL BIG ENOUGH? Energy asks fold onto one standing
// request unless the bank is overflowing -- and during a stall it never is, so
// every builder that wanted energy joined the SAME turbine and we answered a
// three-hundred-a-second deficit thirty-five at a time (apexearth: "when we run
// out of energy we'll make 1 or 2 more wind... and we keep running out of
// energy"). Parallel sites open exactly while what we have ordered still does
// not cover the shortfall, and close by themselves the moment it does. The
// in-flight request cap still bounds how many.
// Headroom-scaled pull less income less what is ordered: the one number the
// stall hoist, the interrupt and the parallel-site rule all answer to.
float EnergyDeficitE()
{
	float need = (aiEconomyMgr.energy.pull + EDrainInFlight())
			* ai.GetTunable("apex_e_headroom", TUNE_E_HEADROOM);
	// ...and never below the standing fleet's full-speed ask.
	{
		const float ask = FleetAskE();
		if (need < ask)
			need = ask;
	}
	return need - aiEconomyMgr.energy.income - EMakeInFlight();
}

// The deficit as it stands, with nothing in flight credited: what a generator
// started now would close. Crediting the frames already crawling in the stall
// read a deep stall as covered and handed the pick back to plain price.
float EnergyDeficitNowE()
{
	float need = aiEconomyMgr.energy.pull
			* ai.GetTunable("apex_e_headroom", TUNE_E_HEADROOM);
	const float ask = FleetAskE();
	if (need < ask)
		need = ask;
	return need - aiEconomyMgr.energy.income;
}

bool EnergyShortOfOrdered()
{
	if (ai.GetTunable("apex_e_parallel", TUNE_E_PARALLEL) <= 0.f)
		return false;
	return EnergyDeficitE() > 0.f;
}

// Same memo, same reason. Build progress and EffBP are both settled for the
// frame, so the stamp is the only thing that can move under it.
float gEDrainVal = 0.f;
int   gEDrainFrame = -1;
int   gEDrainStamp = -1;

float EDrainInFlight()
{
	if (ai.GetTunable("apex_e_committed", TUNE_E_COMMITTED) <= 0.f)
		return 0.f;
	if ((gEDrainFrame == ai.frame) && (gEDrainStamp == gComStamp))
		return gEDrainVal;
	// Ledger COMING rows (flipped 2026-08-27): orphaned frames carry their
	// remaining E bill exactly as live requests do.
	// ONE FLEET, SHARED: each row was priced at the whole fleet's assist share
	// lathing it alone, so N frames read as N half-fleets (2,658 e/s of "drain"
	// on 621 e/s of income, 2026-09-08). The fleet is divided among the rows.
	uint rows = 0;
	for (uint i = 0; i < ComLen(); ++i) {
		if ((gComState[i] != CS_FINISHED) && (Catalog::gCostE[gComDef[i]] > 1.f)
			&& (ComProgress(i) < 1.f))
			++rows;
	}
	const float bpEach = EffBP(0.f) / float((rows > 0) ? rows : 1);
	float e = 0.f;
	for (uint i = 0; i < ComLen(); ++i) {
		if (gComState[i] == CS_FINISHED)
			continue;
		const int d = gComDef[i];
		if (Catalog::gCostE[d] <= 1.f)
			continue;
		float left = 1.f - ComProgress(i);
		if (left <= 0.f)
			continue;
		if (left > 1.f)
			left = 1.f;
		const float sec = Catalog::BuildSecondsAt(d, bpEach);
		if (sec > 1.f)
			e += Catalog::gCostE[d] * left / sec;
	}
	gEDrainFrame = ai.frame;
	gEDrainStamp = gComStamp;
	gEDrainVal = e;
	return e;
}

// The energy the LINES will pull once they run, that the pull does not
// show yet: a factory in flight, or standing with nothing queued, draws
// nothing today and its full production drain the moment it works. Priced
// in before the stall (apexearth: "make energy earlier, that'll save us
// metal in the long run" -- the stall rule then buys 155-metal solars where
// 40-metal winds would have done). E per buildtime of the dearest mobile
// product, the same product LineDensity reads for metal.
float ProductDrainE(int facId)
{
	float dens = 0.f;
	float best = 0.f;
	const array<int>@ pr = Catalog::BuildsOf(facId);
	for (uint q = 0; q < pr.length(); ++q) {
		if (!Catalog::gMobile[pr[q]] || (Catalog::gCostM[pr[q]] <= best))
			continue;
		best = Catalog::gCostM[pr[q]];
		if (Catalog::gBuildTime[pr[q]] > 1.f)
			dens = Catalog::gCostE[pr[q]] / Catalog::gBuildTime[pr[q]];
	}
	return Catalog::gBuildPower[facId] * dens;
}

// ONLY THE LEDGER HALF IS MEMOED. LineWorking reads the factory's pending
// queue, and the executor enqueues INSIDE a frame, so a frame-keyed answer for
// the standing lines would be one order out of date.
// Energy per build-power-second of the hungriest standing line: what one
// point of assisting lathe asks of the energy economy.
float LineEnergyDensity()
{
	float dens = 0.f;
	for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
		CCircuitUnit@ f = Factory::gFacUnits[fi];
		if ((f is null) || (f.circuitDef is null))
			continue;
		const int fd = int(f.circuitDef.id);
		if (Catalog::gBuildPower[fd] <= 0.f)
			continue;
		const float d = ProductDrainE(fd) / Catalog::gBuildPower[fd];
		if (d > dens)
			dens = d;
	}
	return dens;
}

float gLineDrainComVal = 0.f;
int   gLineDrainComFrame = -1;
int   gLineDrainComStamp = -1;

float LineDrainE()
{
	float e = 0.f;
	for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
		CCircuitUnit@ f = Factory::gFacUnits[fi];
		if ((f is null) || (f.circuitDef is null) || LineWorking(f))
			continue;   // working: its draw is already in the pull
		e += ProductDrainE(int(f.circuitDef.id));
	}
	if ((gLineDrainComFrame == ai.frame) && (gLineDrainComStamp == gComStamp))
		return e + gLineDrainComVal;
	float c = 0.f;
	for (uint i = 0; i < ComLen(); ++i) {
		if (gComState[i] == CS_FINISHED)
			continue;
		const int d = gComDef[i];
		if (Catalog::gMobile[d] || (Catalog::gBuildsList[d].length() == 0))
			continue;
		c += ProductDrainE(d);
	}
	gLineDrainComFrame = ai.frame;
	gLineDrainComStamp = gComStamp;
	gLineDrainComVal = c;
	return e + c;
}

// Best metal-per-energy any converter we could actually build reaches.
float gBestConvRatio = -1.f;
float BestConvRatio()
{
	// NEVER CACHE A ZERO. Catalog::gAvailable is frame-dependent (the DLL's
	// IsAvailable(frame)), so a first call before converters unlock would latch
	// 0 forever -- and with it EcoPowerM collapses to metal income and the whole
	// no-mex-map fix goes inert. It did exactly that once the growth premium
	// started calling this from the first election onward.
	if (gBestConvRatio > 0.f)
		return gBestConvRatio;
	gBestConvRatio = 0.f;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (Catalog::gAvailable[d] && (Catalog::gConvCapacity[d] > 0.f)
			&& (Catalog::gConvRatio[d] > gBestConvRatio))
			gBestConvRatio = Catalog::gConvRatio[d];
	}
	return gBestConvRatio;
}

float EcoPowerM()
{
	TrackEPull();
	// ALL the energy we make, not just the part we are wasting (apexearth:
	// "it's not just the converter from T2 that matters, it's the units, the
	// energy, many things"). Every unit and every building costs energy as
	// well as metal, so energy the economy is usefully SPENDING is economic
	// power too -- counting only the surplus said an economy running hot on
	// energy had no energy value at all, which is backwards. What standing
	// converters chew is subtracted because their metal output is already
	// inside metal.income; the rest is carried at the conversion anchor, the
	// game's own exchange rate and the floor price of energy everywhere else
	// in this market.
	float p = aiEconomyMgr.metal.income;
	// Subtract what converters ACTUALLY chew, not their nameplate capacity.
	// Converters run on surplus and idle when energy is tight, so subtracting
	// full capacity erased real energy income -- with capacity above income it
	// valued all of our energy at zero, which is the opposite of the intent.
	// The gadget publishes the draw itself; the surplus-vs-capacity estimate
	// under it is the fallback (ConvUseE).
	const float chewed = ConvUseE();
	// And at a rate we can actually REALIZE: the game's best converter is no
	// use if nothing we own can place it.
	const float own = OwnConvCeil();
	const float rate = (own > 0.f) ? own : BestConvRatio();
	const float eNet = aiEconomyMgr.energy.income - chewed;
	if (eNet > 0.f)
		p += eNet * rate;
	return p;
}

// WHAT TIER UNLOCKS ON THE ENERGY SIDE. The tech want's whole demand is
// UpDemand -- the mex-upgrade stream -- so on a map with no metal spots it is
// identically zero and ProposeTech returns before pricing anything. No T2 lab
// is ever proposed, which means no advanced converter and no AFUS, and the
// economy has no way to grow at all (apexearth: "T1 lab -> t1 con -> t2 lab ->
// fusion/afus + advanced converter, absolutely good right???" -- yes, and we
// could not express it).
//
// Same shape as UpDemand, in the same currency: the extra metal per second a
// better conversion ratio would make from the energy we already have. Zero
// once we own the best converter in the game, exactly like the upgrade stream
// goes to zero once every spot is mohoed.
float ConvRatioReach(const array<int>@ builds)
{
	float best = 0.f;
	if (builds is null)
		return best;
	for (uint i = 0; i < builds.length(); ++i) {
		const int d = builds[i];
		if (Catalog::gAvailable[d] && (Catalog::gConvCapacity[d] > 0.f)
			&& (Catalog::gConvRatio[d] > best))
			best = Catalog::gConvRatio[d];
	}
	return best;
}

// The best ratio anything we already own can place.
// Same reason as BPCapacity: EcoPowerM runs this per candidate through every
// growth premium in the market, and it is a 580-slot walk with a build-options
// walk inside it.
int gOccFrame = -30000;
int gOccOwn = -1;
float gOccVal = 0.f;
// THE SAME CEILING IN CELLS. The converter want discounts a rung that converts
// less per cell than the best one -- but it measured "best" against what the
// ASKING HAND can build, and the commander cannot build the advanced one, so
// its basic converter always priced at full value and the commander went on
// filling a squeezed base with them at 300 metal/s (apexearth 2026-09-09: "we
// don't have enough room so we really shouldn't be making stuff like this";
// 17 of 24 basic-converter elections in one game were the commander's).
// A ceiling, not a refusal: a hand may still build the basic, it is simply
// worth what its ground is worth.
int gOccCellFrame = -30000;
int gOccCellOwn = -1;
float gOccCellVal = 0.f;

float ConvPerCellReach(const array<int>@ builds)
{
	float best = 0.f;
	if (builds is null)
		return best;
	for (uint i = 0; i < builds.length(); ++i) {
		const int d = builds[i];
		if (!Catalog::gAvailable[d] || (Catalog::gConvCapacity[d] <= 0.f))
			continue;
		const float cells = float((Catalog::gAreaCells[d] > 0)
				? Catalog::gAreaCells[d] : 1);
		const float pc = Catalog::gConvCapacity[d] * Catalog::gConvRatio[d] / cells;
		if (pc > best)
			best = pc;
	}
	return best;
}

float OwnConvCellCeil()
{
	if ((gOccCellFrame == ai.frame) && (gOccCellOwn == gOwnStamp))
		return gOccCellVal;
	gOccCellFrame = ai.frame;
	gOccCellOwn = gOwnStamp;
	float best = 0.f;
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		const int di = int(d);
		if ((gOwnCount[d] <= 0) || !Catalog::gMobile[di] || !Catalog::gBuilder[di])
			continue;
		const float pc = ConvPerCellReach(Catalog::gBuildsList[di]);
		if (pc > best)
			best = pc;
	}
	gOccCellVal = best;
	return best;
}

float OwnConvCeil()
{
	if ((gOccFrame == ai.frame) && (gOccOwn == gOwnStamp))
		return gOccVal;
	gOccFrame = ai.frame;
	gOccOwn = gOwnStamp;
	float best = 0.f;
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		const int di = int(d);
		if ((gOwnCount[d] <= 0) || !Catalog::gMobile[di] || !Catalog::gBuilder[di])
			continue;
		const float r = ConvRatioReach(Catalog::gBuildsList[di]);
		if (r > best)
			best = r;
	}
	gOccVal = best;
	return best;
}

// Energy nothing is already converting -- what a better ratio would act on.
float ConvertibleE()
{
	const float e = aiEconomyMgr.energy.income - StandingConvCap();
	return (e > 0.f) ? e : 0.f;
}

float ConvUpDemand()
{
	const float gapR = BestConvRatio() - OwnConvCeil();
	if (gapR <= 0.f)
		return 0.f;
	return ConvertibleE() * gapR;
}

// The BP closed loop: the fleet's standing lathe capacity vs what income
// can feed. Idle builders do not PULL, so "overflow" reads high exactly
// when parked BP is the problem -- capacity is the honest measure
// (measured: 18 assist bots bought against overflow their own idleness
// sustained).
// ONCE PER FRAME, NOT ONCE PER CANDIDATE. EffBP calls this, ValueOf calls
// EffBP, and every want prices every candidate def through ValueOf -- so this
// 580-slot walk (with a GetTunable inside it) ran hundreds of times a frame
// during a mexup proposal. Its inputs are the owned counts and the catalog.
int gBpCapFrame = -30000;
int gBpCapOwn = -1;
float gBpCapVal = 0.f;
// WHAT THE HANDS WE OWN ASK OF THE ENERGY ECONOMY AT FULL SPEED. Pull is what
// the lathes draw this second, throttled by the very stall being priced; the
// standing fleet's ask is fixed by its build power and its line's energy
// density, and it is the demand generation has to lead if energy is ever
// to be ahead of the nanos that create the pull (apexearth: "we should
// have a concept of 'always making energy'... energy is the staple").
float gFleetAskVal = 0.f;
int   gFleetAskFrame = -1;
float FleetAskE()
{
	if (gFleetAskFrame == ai.frame)
		return gFleetAskVal;
	gFleetAskFrame = ai.frame;
	float ask = 0.f;
	for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
		CCircuitUnit@ f = Factory::gFacUnits[fi];
		if ((f !is null) && (f.circuitDef !is null))
			ask += ProductDrainE(int(f.circuitDef.id));
	}
	// Nano turrets assist the lines and ask at the line's density; mobile
	// constructors build structures and ask at the structures' density (a
	// commander on mexes and a lab is ~80 e/s, not the lab's product rate --
	// priced at the line's rate it bought energy before the second mex).
	const float lineDens = LineEnergyDensity();
	const float buildDens = BuildEnergyDensity();
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		if ((gOwnCount[d] <= 0) || (Catalog::gBuildPower[int(d)] <= 0.f))
			continue;
		const int id = int(d);
		if (!Catalog::gMobile[id] && (Catalog::gBuildsList[id].length() > 0))
			continue;   // a factory: counted above at its own product rate
		const float dens = Catalog::gMobile[id] ? buildDens : lineDens;
		ask += float(gOwnCount[d]) * Catalog::gBuildPower[id] * dens;
	}
	// Hands the metal feed cannot run do not ask for energy. Same bound EPrice
	// already puts on this same fleet (price.as). Unbounded, the ask rises with
	// our own build power and floors four separate demand terms, so
	// ERealizeShare read 1.00 -- "all of it will be used" -- at income 499
	// against pull 278 with the bank full.
	if (ai.GetTunable("apex_e_feed_bound", TUNE_E_FEED_BOUND) > 0.f) {
		const float cap = BPCapacity();
		const float look = (gPrELookahead > 1.f) ? gPrELookahead : 30.f;
		const float feed = aiEconomyMgr.metal.income
				+ aiEconomyMgr.metal.current / look;
		if ((cap > 0.f) && (feed < cap))
			ask *= feed / cap;
	}
	gFleetAskVal = ask;
	return ask;
}

// Energy per build-power-second of the structures our constructors can
// place: the mean over the available immobile, non-factory catalogue.
float gBuildDensVal = -1.f;
float BuildEnergyDensity()
{
	if (gBuildDensVal > 0.f)
		return gBuildDensVal;
	float sum = 0.f;
	int n = 0;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!Catalog::gAvailable[d] || Catalog::gMobile[d]
			|| (Catalog::gBuildsList[d].length() > 0) || (Catalog::gBuildTime[d] <= 1.f))
			continue;
		sum += Catalog::gCostE[d] / Catalog::gBuildTime[d];
		++n;
	}
	if (n <= 0)
		return 0.f;   // not cached: defs may not be available yet
	gBuildDensVal = sum / float(n);
	return gBuildDensVal;
}

float BPCapacity()
{
	if ((gBpCapFrame == ai.frame) && (gBpCapOwn == gOwnStamp))
		return gBpCapVal;
	gBpCapFrame = ai.frame;
	gBpCapOwn = gOwnStamp;
	float cap = 0.f;
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		if (gOwnCount[d] <= 0)
			continue;
		if (Catalog::gBuildPower[int(d)] <= 0.f)
			continue;
		float unitCap = float(gOwnCount[d]) * Catalog::gBuildPower[int(d)] * (7.f / 80.f);
		// A walking con is not a lathe: mobile BP spends much of its life in
		// transit, so it counts at a discount -- full-weight counting read
		// 40 road-bound cons as 280 m/s of build power and starved the nano
		// farm while metal overflowed (apexearth: "the solution is nano
		// turrets").
		if (Catalog::gMobile[int(d)])
			unitCap *= ai.GetTunable("apex_mobile_bp_eff", TUNE_MOBILE_BP_EFF);
		cap += unitCap;
	}
	gBpCapVal = cap;
	return cap;
}

// The mobile part of BPCapacity, same discount.
float MobileBPCapacity()
{
	float cap = 0.f;
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		if ((gOwnCount[d] <= 0) || !Catalog::gMobile[int(d)]
			|| (Catalog::gBuildPower[int(d)] <= 0.f))
			continue;
		cap += float(gOwnCount[d]) * Catalog::gBuildPower[int(d)] * (7.f / 80.f)
				* ai.GetTunable("apex_mobile_bp_eff", TUNE_MOBILE_BP_EFF);
	}
	return cap;
}

// Smoothed income growth rate, m/s per second -- the compounding signal.
float gIncPrev = -1.f;
int gIncPrevAt = 0;
float gIncGrowth = 0.f;
float gIncEma = -1.f;
float gMSpareEma = 0.f;
float gReclaimCumPrev = -1.f;

void TrackIncome()
{
	if (ai.frame < gIncPrevAt + 10 * SECOND)
		return;
	float inc = aiEconomyMgr.metal.income;
	// STRUCTURAL income: a reclaim burst is a spike, not a standard of
	// living -- labs must not be licensed off it (apexearth). The EMA alone
	// still followed a minutes-long post-battle wreck feast, so the reclaim
	// RATE (dev_team_income's cumulative apexReclaimM, differentiated over
	// this same sample) is subtracted before smoothing. Param absent (a
	// hosted game without our gadgets) reads -1 and the raw income stands.
	const float recCum = ai.GetTeamRulesParam("apexReclaimM", -1.f);
	if ((recCum >= 0.f) && (gReclaimCumPrev >= 0.f)
		&& (recCum > gReclaimCumPrev))
	{
		const float dts = float(ai.frame - gIncPrevAt) / float(SECOND);
		const float recRate = (recCum - gReclaimCumPrev)
				/ ((dts > 1.f) ? dts : 1.f);
		inc -= recRate;
		if (inc < 0.f)
			inc = 0.f;
	}
	if (recCum >= 0.f)
		gReclaimCumPrev = recCum;
	gIncEma = (gIncEma < 0.f) ? inc : (0.85f * gIncEma + 0.15f * inc);
	if (gIncPrev >= 0.f) {
		const float dt = float(ai.frame - gIncPrevAt) / float(SECOND);
		const float g = (inc - gIncPrev) / ((dt > 1.f) ? dt : 1.f);
		gIncGrowth = 0.7f * gIncGrowth + 0.3f * g;
	}
	// Metal nothing is already spending, smoothed. Raw pull dips to nothing
	// whenever the fleet is between jobs, so an instantaneous read calls a
	// fully committed economy idle one tick and starving the next -- the same
	// trap TrackEPull documents on the energy side.
	const float sur = inc - aiEconomyMgr.metal.pull;
	gMSpareEma = 0.85f * gMSpareEma + 0.15f * ((sur > 0.f) ? sur : 0.f);
	gIncPrev = inc;
	gIncPrevAt = ai.frame;
}

// The metal rate a NEW consumer could actually be fed at: what nothing is
// spending, plus what we are already throwing away.
float SpareMetalRate()
{
	return gMSpareEma + OverflowM();
}

// Lathe capacity still worth buying: income x headroom minus the fleet --
// plus the income the compounding economy will have within the lookahead
// (apexearth 2026-08-23: idle cons were "not valuing the forward-looking
// compounding effect" of standing build power).
// WORK WE HAVE COMMITTED TO AND NOT BUILT, in metal. Live requests priced at
// what is left of them, so a queue of unstarted frames reads as demand for
// hands rather than as nothing at all.
float gBacklogVal = 0.f;
int   gBacklogFrame = -1;
int   gBacklogStamp = -1;
int   gBacklogRows = 0;   // unfinished rows behind gBacklogVal, for the bpgap line

float BacklogM()
{
	if ((gBacklogFrame == ai.frame) && (gBacklogStamp == gComStamp))
		return gBacklogVal;
	// Ledger COMING rows (flipped 2026-08-27): the orphaned-frame mass is
	// backlog too -- it is exactly the committed work gLive forgot.
	float m = 0.f;
	int rows = 0;
	for (uint i = 0; i < ComLen(); ++i) {
		if (gComState[i] == CS_FINISHED)
			continue;
		const float left = 1.f - ComProgress(i);
		if (left <= 0.f)
			continue;
		m += Catalog::gCostM[gComDef[i]] * left;
		++rows;
	}
	gBacklogFrame = ai.frame;
	gBacklogStamp = gComStamp;
	gBacklogVal = m;
	gBacklogRows = rows;
	return m;
}

// The structural-income EMA, for callers outside this file (the front
// budget publishes it as the team's minc-net lane; the gantry budget sums
// that lane). Functions are module-wide, market globals are not.
float StructuralIncomeEma()
{
	TrackIncome();
	return (gIncEma > 0.f) ? gIncEma : aiEconomyMgr.metal.income;
}

int gBpGapLogAt = 0;

// The fraction of the fleet's lathe time energy permits: income plus ordered
// generation over pull, 1 when nothing throttles.
// Metal is being thrown away: the bank is full and income exceeds what the
// fleet draws. In that state metal is not the cost of anything, hands and
// energy are (canon game 2026-09-08: 34k of 65k metal made was wasted by
// minute 20 against an inactive opponent while 35 stall answers were held).
bool MetalWasting()
{
	return aiEconomyMgr.isMetalFull
		&& (aiEconomyMgr.metal.income > aiEconomyMgr.metal.pull);
}

float EFeedShare()
{
	const float pull = aiEconomyMgr.energy.pull;
	if (pull <= 0.01f)
		return 1.f;
	const float s = (aiEconomyMgr.energy.income + EMakeInFlight()) / pull;
	return (s < 0.f) ? 0.f : ((s > 1.f) ? 1.f : s);
}

float BPGap()
{
	TrackIncome();
	const float head = ai.GetTunable("apex_bp_headroom", TUNE_BP_HEADROOM);
	const float ahead = ai.GetTunable("apex_bp_lookahead", TUNE_BP_LOOKAHEAD);
	const float ecoP = EcoPowerM();
	const float futureInc = ecoP
			+ ((gIncGrowth > 0.f) ? gIncGrowth * ahead : 0.f);
	const float tgt = futureInc * ((head > 0.f) ? head : 1.15f);
	const float cap = BPCapacity();
	float gap = tgt - cap;
	// A bank climbing past half storage is deferred spend the standing
	// lathe already failed to serve (measured: 9.4k banked at 234 m/s
	// income with ~30 nanos - the income target alone reads "satisfied"
	// exactly when the backlog is worst).
	const float bank = aiEconomyMgr.metal.current;
	const float st2 = aiEconomyMgr.metal.storage;
	float bankTerm = 0.f;
	if ((st2 > 1.f) && (bank > 0.5f * st2))
		bankTerm = (bank - 0.5f * st2) / 60.f;
	// Only the share energy lets the lathes run: a bank that fills because
	// the hands are e-throttled is not a hands shortage, and reading it as
	// one bought 3,200-E nano turrets into the stall that filled it.
	gap += bankTerm * EFeedShare();
	// AND THE WORK ALREADY ORDERED. Income headroom alone cannot see a queue:
	// order fifteen turrets and this number does not move, so the turrets come
	// out of expansion's hands instead of buying their own (apexearth: "we'll
	// need some more constructors built... ideally the brain is in charge of
	// detecting whether or not we have a proper balance"). Same horizon as the
	// bank clause above, and distinct from it -- bank is metal nothing spent,
	// backlog is work nothing built. Self-limiting: BPCapacity is subtracted
	// above, so the gap closes as the hands arrive.
	const float bl = ai.GetTunable("apex_bp_backlog_s", TUNE_BP_BACKLOG_S);
	const bool logNow = (ai.frame >= gBpGapLogAt);
	// The ledger walk stays off the path in the control arm; the log still
	// needs the raw number, so it is asked for on the logging frame only.
	const float rawBl = ((bl > 1.f) || logNow) ? BacklogM() : 0.f;
	float blTerm = 0.f;
	if (bl > 1.f)
		blTerm = rawBl / bl;
	// A FLOOR, NOT AN ADDEND. Added to the income clause the backlog was
	// swallowed whole: nameplate BPCapacity runs 4-6x actual income, so `net`
	// sits at -120 to -200 and no positive term survives it. Measured 196 of
	// 225 logged bpgap minutes at gap=0.0 -- and a constructor's whole
	// build-power gain is BPGap()*util (production.as), so hands were worth
	// nothing to buy while 6,020 metal of ordered work stood unbuilt and the
	// bank read 0%. Unfinished work is its own evidence and does not need the
	// income clause's permission. Still self-limiting: the backlog closes as
	// the hands arrive.
	if (gap < blTerm)
		gap = blTerm;
	const float gapM = (gap > 0.f) ? gap : 0.f;
	// EVERY CLAUSE SEPARATELY, once a minute. The three clauses are in the same
	// currency and nothing printed which of them carries the number, so a gap
	// that never closes could not be told from one that closes and reopens --
	// `net` is the income clause after capacity, and it is the only one that
	// can go negative.
	if (logNow) {
		gBpGapLogAt = ai.frame + 60 * SECOND;
		AiLog(Factory::T() + "apex: bpgap gap=" + formatFloat(gapM, "", 0, 1)
			+ " tgt=" + formatFloat(tgt, "", 0, 1)
			+ " eco=" + formatFloat(ecoP, "", 0, 1)
			+ " grow=" + formatFloat(futureInc - ecoP, "", 0, 1)
			+ " cap=" + formatFloat(cap, "", 0, 1)
			+ " net=" + formatFloat(tgt - cap, "", 0, 1)
			+ " bank=" + formatFloat(bankTerm, "", 0, 1)
			+ " blog=" + formatFloat(blTerm, "", 0, 1)
			+ " rawM=" + int(rawBl)
			+ " rows=" + gBacklogRows
			+ " mInc=" + formatFloat(aiEconomyMgr.metal.income, "", 0, 1)
			+ " bank%=" + int((st2 > 1.f) ? (100.f * bank / st2) : -1.f));
	}
	return gapM;
}

// Metal income nothing is spending: the arithmetic case for more build
// capacity. A new builder's return includes the overflow it would capture --
// this is the closed-loop build-power term, not a model.
float OverflowM()
{
	const float over = aiEconomyMgr.metal.income - aiEconomyMgr.metal.pull;
	if (over <= 0.f)
		return 0.f;
	// Only real once the bank is filling; a draining bank absorbs the gap.
	const float st = aiEconomyMgr.metal.storage;
	if ((st > 1.f) && (aiEconomyMgr.metal.current < 0.8f * st))
		return 0.f;
	return over;
}

// THE BANK IS PINNED: we are producing more energy than we consume, right now,
// whatever the surplus arithmetic says.
//
// `income - pull` measured 782-2,249 e/s in a game whose own excess counter
// says ~31,000 e/s was thrown away (Red Comet 1v1 +100%: 46% and 56% of all
// energy produced, wasted). Pull is DEMAND, and a fleet of 250 nano turrets
// asks for energy it is not drawing -- so the difference understates the waste
// by more than an order of magnitude, and the converter want priced a 600 e/s
// machine against a 1,000 e/s surplus that one order exhausted. That is why
// the fleet stalled at 11-13 while half the grid was lost.
//
// A full bank cannot be mistaken in the same way: it means the next converter
// runs at its FULL capacity until it stops being full. And it is self-limiting
// -- absorb enough and the pin breaks, and the ordinary surplus pricing takes
// over again. No threshold on how much waste is too much, and no cap on the
// fleet; the same shape SlackFrac uses on the metal side.
// ...AND THE ENERGY FILLING IT IS OURS. An ally's periodic overflow tops the
// bank up for a moment, this read full, and the converter want bought for
// energy we do not make (apexearth: "1 team is overflowing into the other team
// periodically... we're getting tricked into making more converters"). Full
// means what we make exceeds what we use; the engine's own usage says so.
bool EnergyPinned()
{
	const float st = aiEconomyMgr.energy.storage;
	return (st > 1.f) && (aiEconomyMgr.energy.current >= 0.98f * st)
			&& (aiEconomyMgr.energy.income >= aiEconomyMgr.energy.usage);
}

int gCwCalls = 0;      // ProposeConvert entries
int gCwBank = 0;       // ...refused: the energy bank is not near full
int gCwNoSurplus = 0;  // ...refused: nothing left after what is ordered
int gCwCand = 0;       // buildable converter defs seen
int gCwObsolete = 0;   // ...dropped as edible by a better one
int gCwNoDef = 0;      // reached the loop and priced nothing
int gCwProposed = 0;   // a Want came out
float gCwSurplus = 0.f;
float gCwVal = 0.f;
int gCwLogAt = 0;

void ConvWhyLog()
{
	if (ai.frame < gCwLogAt)
		return;
	gCwLogAt = ai.frame + 30 * SECOND;
	const float st = aiEconomyMgr.energy.storage;
	AiLog("apex: convwhy t=" + ai.teamId
		+ " calls=" + gCwCalls
		+ " bankRefused=" + gCwBank
		+ " noSurplus=" + gCwNoSurplus
		+ " cand=" + gCwCand
		+ " obsolete=" + gCwObsolete
		+ " nodef=" + gCwNoDef
		+ " proposed=" + gCwProposed
		+ " surplus=" + int(gCwSurplus)
		+ " wasted=" + int((gEExcessEma > gESurplusEma) ? gEExcessEma : gESurplusEma)
		+ " excess=" + int(aiEconomyMgr.energy.excess)
		+ " ema=" + int(gESurplusEma)
		+ " inflight=" + int(ConvCapInFlight())
		+ " standing=" + int(StandingConvCap())
		+ " bank%=" + int((st > 1.f) ? (100.f * aiEconomyMgr.energy.current / st) : -1.f)
		+ " pinned=" + (EnergyPinned() ? 1 : 0)
		+ " v=" + formatFloat(gCwVal, "", 0, 3));
}

// Converters: worth exactly the energy surplus they would chew, at their own
// ratio. Pure catalog arithmetic, no model.
int gNextConvPriceLog = 0;
Want@ ProposeConvert(CCircuitUnit@ unit)
{
	Want w;
	TrackEPull();
	// Converters recycle OVERFLOW only: the conversion ratio IS the energy
	// floor price, so converting non-overflowing E is value-neutral by our
	// own definitions -- a converter never outbids a slightly-longer mex
	// walk again (apexearth's call, twice). Overflow = the surplus the E bank
	// cannot absorb.
	const float eStore2 = aiEconomyMgr.energy.storage;
	// WHY THERE IS NO CONVERTER. Measured 2026-08-31 on Red Comet 1v1 +100%:
	// 46-56% of all energy thrown away, the bank pinned at 87-99% of storage
	// for the whole game, and `energy/convert` winning ZERO elections while
	// nanos won 1,709 -- so the parallel-site fix landed on a path that was
	// carrying no traffic. Each early exit below is now countable rather than
	// silent; the last line says which one is eating the want.
	++gCwCalls;
	if ((eStore2 > 1.f)
		&& (aiEconomyMgr.energy.current < 0.85f * eStore2)) {
		++gCwBank;
		ConvWhyLog();
		return w;
	}
	// Energy pull ALREADY carries what standing converters draw (see ConvCapE
	// above), so the surplus EMA is net of them; subtracting their capacity a
	// second time hid a saturated fleet's remaining waste entirely and is why
	// capacity stopped growing while energy overflowed. What is NOT in pull is
	// the capacity we have already ordered.
	const bool realize = ai.GetTunable("apex_e_realize", TUNE_E_REALIZE) > 0.f;
	const float eWasted = (gEExcessEma > gESurplusEma) ? gEExcessEma : gESurplusEma;
	const float eSurplus = realize
			? (eWasted - ConvCapInFlight())
			: (eWasted - StandingConvCap());
	gCwSurplus = eSurplus;
	// A pinned bank is its own evidence -- see EnergyPinned. The EMA is the
	// wrong instrument there, so it does not get to veto.
	// A FULL BANK IS NOT WASTE AT FRAME ZERO. The game grants full energy
	// storage at the start, so EnergyPinned() reads pinned=1 with excess,
	// surplus and the waste EMA all at zero, and the first election of the
	// game bought a converter -- 1.64 of them per player before minute 4
	// against BARb's none, each one eating the energy that then forced the
	// stall rule to buy basic solars. His ruling is converters on WASTE;
	// with nothing wasted there is nothing for one to modulate.
	const bool pinned = EnergyPinned() && (eWasted > 1.f);
	if ((eSurplus <= 1.f) && !pinned) {
		++gCwNoSurplus;
		ConvWhyLog();
		return w;
	}
	const int uid = int(unit.circuitDef.id);
	const AIFloat3 cSite = EcoSiteFor(unit);
	const array<int>@ builds = Catalog::BuildsOf(uid);
	// Invariant across the rungs -- see the same hoist in the generator ladder.
	const float cvPower = EcoPowerM();
	const float cvGrowK = ai.GetTunable("apex_energy_growth", TUNE_ENERGY_GROWTH);
	const float cvRentCell = SpaceRentM(cSite, 1);
	const float cvCrowdCell = PfCrowd() * PfMetalPerCell()
			* ai.GetTunable("apex_room_worth", TUNE_ROOM_WORTH);
	// INFERIOR WORK IS WORTH LESS here as on the generator side: metal per
	// cell against the best converter THIS asker can place. Priced per metal
	// alone the 1-metal T1 converter always won -- 207 of them and 2 advanced
	// by minute 20 of the canon game against his 94 advanced.
	float cvBestPerCell = 0.f;
	for (uint i = 0; i < builds.length(); ++i) {
		const int d = builds[i];
		if (!Catalog::gAvailable[d] || Catalog::gMobile[d] || Catalog::gFloater[d]
			|| Catalog::gSub[d] || (Catalog::gConvCapacity[d] <= 0.f))
			continue;
		const float cells = float((Catalog::gAreaCells[d] > 0) ? Catalog::gAreaCells[d] : 1);
		const float pc = Catalog::gConvCapacity[d] * Catalog::gConvRatio[d] / cells;
		if (pc > cvBestPerCell)
			cvBestPerCell = pc;
	}
	// ...against what ANY of our hands could put on that ground, not only this
	// one. See OwnConvCellCeil.
	{
		const float teamCell = OwnConvCellCeil();
		if (teamCell > cvBestPerCell)
			cvBestPerCell = teamCell;
	}
	for (uint i = 0; i < builds.length(); ++i) {
		const int d = builds[i];
		if (!Catalog::gAvailable[d] || Catalog::gMobile[d] || Catalog::gFloater[d] || Catalog::gSub[d])
			continue;   // floaters need water; land-base v1 (see armfmkr churn)
		if (Catalog::gConvCapacity[d] <= 0.f)
			continue;
		++gCwCand;
		// Same law as the generator ladder: never build a converter the
		// per-cell dwarf test already marks edible.
		// Per HAND, not globally -- see ConvObsoleteFor. Most constructors
		// can only build the basic one, and refusing it there converts
		// nothing at all.
		// ...unless the bank is pinned and the denser fleet, standing or
		// staffed, does not cover the surplus: then any converter beats the
		// energy thrown away (his rule: overflowing means converters, the
		// only question is how many). Watched: standing=0, 4-5k E/s excess,
		// T1 hands refusing the basic as obsolete-on-arrival while the T2
		// hands priced the advanced one out.
		if (ConvObsoleteFor(unit, d)) {
			const bool starved = EnergyPinned()
					&& (DenserConvStandingE(d) + ConvCapInFlight() < eSurplus);
			if (!starved) {
				++gCwObsolete;
				continue;
			}
		}
		// A full bank prices the NEXT converter at full capacity -- and the
		// ones already ordered are that next converter. Pricing it at the
		// engine's measured excess instead was tried 2026-09-11 and lost on
		// both maps (ISSUES); the excess is logged beside it, unused.
		float chew = (eSurplus < Catalog::gConvCapacity[d])
				? eSurplus : Catalog::gConvCapacity[d];
		if (pinned) {
			// Capacity standing idle is what the pin is NOT: the bank pinned
			// full through five idle converters and bought a sixth at full
			// chew each time.
			float idle = ConvCapE() - ConvUseE();
			if (idle < 0.f)
				idle = 0.f;
			const float open = Catalog::gConvCapacity[d] - ConvCapInFlight() - idle;
			if (open > chew)
				chew = open;
		}
		if (chew < 0.f)
			chew = 0.f;
		Want c;
		// THE SAME ECO-COMPOUNDING PREMIUM THE GENERATOR GETS. A generator is
		// priced as though its energy were already metal and then multiplied by
		// what that adds to total economic power; the converter that actually
		// makes that metal was the only half of the pair paying flat, so the
		// pair could never be bought in the order that realizes it.
		float cGain = chew * Catalog::gConvRatio[d];
		if (cvBestPerCell > 0.f) {
			const float cellsI = float((Catalog::gAreaCells[d] > 0) ? Catalog::gAreaCells[d] : 1);
			const float mine = Catalog::gConvCapacity[d] * Catalog::gConvRatio[d] / cellsI;
			if (mine < cvBestPerCell)
				cGain *= mine / cvBestPerCell;
		}
		if (realize) {
			cGain *= 1.f + cvGrowK
					* cGain / ((cvPower > cGain) ? cvPower : ((cGain > 0.f) ? cGain : 1.f));
		}
		ValueOf(d, cGain, WalkSecTo(unit, cSite),
				Catalog::gBuildPower[uid], c);
		// SPACE IS WHAT THE ADVANCED CONVERTER BUYS. Ratio alone says T1 is
		// nearly as good and far cheaper; what T2 actually buys is ten times
		// the throughput behind the same guns, and a body that does not die to
		// one hit (apexearth). The rent prices the first; the second is the
		// stream's own survival, which cover already raises.
		{
			const float cellsC = float((Catalog::gAreaCells[d] > 0)
					? Catalog::gAreaCells[d] : 1);
			const float rent = ((Catalog::gAreaCells[d] > 0)
						? (cvRentCell * float(Catalog::gAreaCells[d])) : 0.f)
					+ cvCrowdCell * cellsC
					+ BlastCollateralM(cSite, d);   // its fuse, and its neighbours'
			if (rent > 0.f) {
				c.mCost += rent;
				c.value = (c.gain > 0.f) ? (c.gain / (c.mCost + c.tCost)) : 0.f;
			}
		}
		if (c.value > w.value) {
			w = c;
			w.kind = WK_CONVERT;
			@w.def = Catalog::Def(d);
			w.pos = cSite;
		}
	}
	if (w.value > 0.f) {
		++gCwProposed;
		gCwVal = w.value;
		// The price, term by term: the seat wasted 24k E/s with the converter
		// at v=8 under an assist at v=17, and only m= and t= were readable.
		if (ai.frame >= gNextConvPriceLog) {
			gNextConvPriceLog = ai.frame + 30 * SECOND;
			const int cd2 = int(w.def.id);
			const float wage = Wage();
			const float lock = (gPrPaybackH > 1.f)
					? (Catalog::gCostM[cd2] * (w.buildSec / gPrPaybackH) * gPrLockup) : 0.f;
			AiLog("apex: convprice t=" + ai.teamId + " " + w.def.GetName()
				+ " v=" + formatFloat(w.value * 1000.f, "", 0, 2)
				+ " gain=" + formatFloat(w.gain, "", 0, 2)
				+ " m=" + int(w.mCost) + " (metal=" + int(Catalog::gCostM[cd2] * MCostScale())
				+ " e=" + int(Catalog::gCostE[cd2] * EPriceCostAt(w.buildSec, Catalog::gCostE[cd2]))
				+ " space=" + int(float(Catalog::gAreaCells[cd2]) * gPrSpaceM)
				+ " rent=" + int(w.mCost - Catalog::gCostM[cd2] * MCostScale()
					- Catalog::gCostE[cd2] * EPriceCostAt(w.buildSec, Catalog::gCostE[cd2])
					- float(Catalog::gAreaCells[cd2]) * gPrSpaceM) + ")"
				+ " t=" + int(w.tCost) + " (build=" + int(w.buildSec) + "s walk=" + int(w.walkSec)
				+ "s wage=" + formatFloat(wage, "", 0, 1)
				+ " late=" + int(w.gain * w.walkSec) + " lock=" + int(lock)
				+ " rest=" + int(w.tCost - w.walkSec * WalkRateWith(Catalog::gBuildPower[uid], wage)
					- w.buildSec * wage - w.gain * w.walkSec - lock) + ")");
		}
	} else {
		++gCwNoDef;
	}
	ConvWhyLog();
	return w;
}

Want@ ProposeStore(CCircuitUnit@ unit)
{
	// Storage is never proposed (apexearth 2026-08-27: "We make tons of metal
	// storage - we don't need it. Stop making storage."). The reclaim-headroom
	// niche it served read gReclaimTarget, a global every reclaim PROPOSAL
	// set, so the lab-reclaim churn kept it armed and 31 storages stood in
	// one 44-minute 1v1. A refund past headroom just overflows.
	Want w;
	return w;
}


}  // namespace Market
