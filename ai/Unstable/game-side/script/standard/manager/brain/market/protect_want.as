namespace Market {
// A T1 tower is one the T1 LINE can build -- gT1Line, not gT1Hand, because
// gT1Hand includes the commander and a levelled commander reaches well above
// its tier. corcomlvl5..10 build cordoom (Bulwark, 3000m), so gT1Hand called it
// a T1 tower and it took the late-T1 discount; the Cerberus, whose builder list
// has no commander, did not. Same tier, 50x apart on a technicality.
// Does this build list hold a tower above T1?
bool HandHasT2Tower(const array<int>@ b)
{
	if (b is null)
		return false;
	for (uint i = 0; i < b.length(); ++i) {
		const int o = b[i];
		if (Catalog::gMobile[o] || !Catalog::gAvailable[o]
			|| (ProtClassOf(o) != PROT_DEF))
			continue;
		if (!T1Tower(o))
			return true;
	}
	return false;
}

// Metal standing in towers a basic hand can build.
float T1TowerStandingM()
{
	float m = 0.f;
	for (uint i = 0; i < gProtDefId[PROT_DEF].length(); ++i) {
		const int d = gProtDefId[PROT_DEF][i];
		if (T1Tower(d))
			m += Catalog::gCostM[d];
	}
	return m;
}

bool T1Tower(int d)
{
	const array<int>@ bb = Catalog::gBuiltBy[d];
	for (uint q = 0; q < bb.length(); ++q) {
		const int b = bb[q];
		if ((b < int(Catalog::gT1Line.length())) && Catalog::gT1Line[b])
			return true;
	}
	return false;
}

// A DEFENCE SLOT HOLDS ONE BUILDING, SO THE QUESTION IS NOT VALUE PER METAL.
//
// apexearth 2026-09-01, watching 15 Gauntlets die to Juggernauts: "Even on
// paper gauntlet isn't that good because you very quickly end up with a single
// building that covers more range and more than triples the DPS (a pulsar!) So
// why build something that so quickly becomes outdated?... idk how to turn that
// into a mathematical result."
//
// This is the turn. Per-metal ranking is correct when you buy QUANTITY; a wall
// slot is a PLACE, and a place holds exactly one gun. Measured, the per-metal
// rule is monotonically decreasing in price -- kill rises 207 -> 445 (2.15x)
// across armllt -> armguard while cost rises 85 -> 1250 (14.7x) -- so it buys
// the cheapest thing on the shelf every time, and the game bore that out: 83
// light towers and 27 beamers against one Pulsar.
//
// The player's rule is DOMINANCE, not efficiency: a Gauntlet reaches 1,220 for
// 105 dps and a Pulsar reaches 1,400 for 1,091, so the Gauntlet is beaten on
// both axes at once and its metal is stranded the moment the better gun is
// affordable. Same shape as ConvObsoleteOnArrival, which already refuses a
// converter a denser one dwarfs.
//
// AFFORDABILITY IS THE WHOLE GUARD. Without it a Pulsar we cannot pay for
// would make every tower obsolete and we would build nothing at all -- so the
// dominating gun must be one this economy can actually buy, which is exactly
// his "once we can afford it we need to build them". Below that, the Gauntlet
// is not outdated, it is what we can have.
// `affordM` is EcoPowerM() x apex_def_afford_s, read once per election by the
// caller: it is the same number for every candidate and every build option.
bool DefObsoleteOnArrival(const array<int>@ b, int d, float affordM)
{
	if (b is null)
		return false;
	const float myR = Catalog::gMaxRange[d];
	const float myK = PfTowerKill(d);
	if ((myR <= 0.f) || (myK <= 0.f))
		return false;
	for (uint i = 0; i < b.length(); ++i) {
		const int o = b[i];
		if ((o == d) || Catalog::gMobile[o] || !Catalog::gAvailable[o]
			|| (ProtClassOf(o) != PROT_DEF))
			continue;
		if (Catalog::gCostM[o] > affordM)
			continue;   // cannot have it yet: d is not outdated, it is the answer
		// Beaten on BOTH axes -- reach and killing power. Either alone is a
		// trade-off; both together is obsolescence.
		if ((Catalog::gMaxRange[o] >= myR) && (PfTowerKill(o) > myK))
			return true;
	}
	return false;
}

bool gWallEffDiag = false;

Want@ ProposeProtectHalf(CCircuitUnit@ unit, int half)
{
	Want w;
	Want own;
	if (Gate(GATE_ASSETS, gAssetsM < 1.f))
		return w;
	// DEFENCE MUST NOT WAIT ON A NANO. This used to require gFarmSet, which
	// only flips when the first nano TURRET finishes -- measured at frame
	// 5718, so no LLT, AA, radar or shield could even be proposed for the
	// first 3.2 minutes, which is exactly when raiders take undefended mexes
	// and solars (apexearth, watched: "we made several solars/mexes which we
	// did not protect with a sentry turret... our llt defense early game is
	// not strong enough"). The farm is only ever a DEFAULT POSITION; the
	// anchor serves before it exists, and PROT_DEF/PROT_RADAR pick their own
	// sites anyway.
	const int ruid = int(unit.circuitDef.id);
	if (int(gNextDefRankOf.length()) <= Catalog::gDefCount)
		gNextDefRankOf.resize(Catalog::gDefCount + 1);
	const bool rankNow = (half == HALF_GROUND)
			&& (ai.frame >= gNextDefRankOf[ruid]);
	// Why is the first defence price MINUTES late? (first defprice measured
	// at 8.8 and 16.2 min in back-to-back games while targets logged from
	// frame 25). One line per half-minute: is this function even reached,
	// and with what candidate list.
	if ((half == HALF_GROUND) && (ai.frame >= gNextProtEnterLog)) {
		gNextProtEnterLog = ai.frame + 30 * SECOND;
		AiLog("apex: prot-enter by=" + unit.circuitDef.GetName()
			+ " builds=" + Catalog::BuildsOf(ruid).length()
			+ " assets=" + int(gAssetsM)
			+ " defsClassed=" + gProtDefId[PROT_DEF].length());
	}
	if (rankNow) {
		gDefRankDef.resize(0);
		gDefRankV.resize(0);
	}
	gWhyDef.resize(0);
	const int uid = int(unit.circuitDef.id);
	const array<int>@ builds = Catalog::BuildsOf(uid);
	const float rate = ai.GetTunable("apex_insure_rate", TUNE_INSURE_RATE);
	// The no-turret test (docs/24): radar and units are the whole defence.
	const bool defOff = ai.GetTunable("apex_def_off", TUNE_DEF_OFF) > 0.f;
	// (Normalising the TTD discount against the quickest buildable turret --
	// so defence as a category paid nothing and only the ordering inside it
	// moved -- was tried and REVERTED: it raised defence's share of spend but
	// bought MORE of the slow turret, not less. The absolute discount below is
	// what actually moves the mix.)
	AIFloat3 core = gFarmPos;
	if (!gFarmSet) {
		core = Base::gAnchorSet ? Base::gAnchor : Builder::gHomePos;
		if (Gate(GATE_CORE, !OnMap(core)))
			return w;
	}
	// THE CANDIDATE LIST IS THE TEAM'S, NOT THE ASKER'S. Ground defence is
	// ranked over every tower any of our builders can make, so an Agitator is
	// compared against the Cerberus that will actually be built instead of
	// against the two other T1 towers this particular hand happens to own.
	// Every other class stays local: a radar or a jammer is answered by
	// whoever is standing there, and there is no tier argument to lose.
	array<int> cand = builds;
	if (half == HALF_GROUND) {
		const array<int>@ team = TeamDefenceDefs();
		for (uint tq = 0; tq < team.length(); ++tq) {
			bool have = false;
			for (uint bq = 0; bq < cand.length() && !have; ++bq)
				have = (cand[bq] == team[tq]);
			if (!have)
				cand.insertLast(team[tq]);
		}
	}
	// EVERYTHING BELOW THAT DOES NOT DEPEND ON THE CANDIDATE, READ ONCE.
	// Five towers reach the ground branch in a normal election, and each of
	// these re-derived a side-wide aggregate for an answer identical across
	// all five: DefenceValue walks every standing turret, EcoPowerM and
	// ArmyTargetFull the def table, PfCrowd the rim's PF_RAYS wedges.
	const bool isGround = (half == HALF_GROUND);
	const float hUSpeed = Catalog::gSpeed[uid];
	const AIFloat3 hUPos = unit.GetPos(ai.frame);
	float hTrade = 0.f;
	float hMexFloorWave = 0.f;
	float hSiteWave = 0.f;
	float hEnemyPrior = 0.f;
	float hWage = 0.f;
	float hWalkRate = 0.f;
	float hWalkW = 0.f;
	float hUGuardM = 0.f;
	float hHorizS = 0.f;
	float hHorizPay = 0.f;
	float hGap = -1.f;      // unmet defence target, or <0 for "no wall pull"
	bool  hWallUp = false;
	float hRentPerCell = 0.f;
	float hFill = 0.f;
	float hEffBP = 0.f;
	float hTeamPow = 0.f;
	float hTeamPowAll = 0.f;
	float hAffordM = 0.f;
	float hTtdH = 0.f;
	bool  hDomOn = false;
	bool  hEffOn = false;
	float hLineW = 1.f;     // read inside the slot loop, same for every slot
	float hBestEff = -1.f;  // the wall-efficiency benchmark, built on first ask
	if (isGround) {
		hTrade = ai.GetTunable("apex_def_trade", TUNE_DEF_TRADE);
		hMexFloorWave = MexCoverFloorM() * hTrade;
		hSiteWave = ArmyTargetFull()
				* ai.GetTunable("apex_def_prior_share", TUNE_DEF_PRIOR_SHARE)
				* TeamExposure();
		hEnemyPrior = ai.GetTunable("apex_enemy_prior", TUNE_ENEMY_PRIOR);
		hWage = Wage();
		hWalkRate = WalkRate(Catalog::gBuildPower[uid]);
		hWalkW = ai.GetTunable("apex_def_site_walk", TUNE_DEF_SITE_WALK);
		hUGuardM = (PfKillRef() > 0.f)
				? (Catalog::gSurfT[uid] / PfKillRef()) : 0.f;
		hHorizS = ai.GetTunable("apex_exposed_loss_s", TUNE_EXPOSED_LOSS_S);
		if (hHorizS <= 1.f)
			hHorizS = TUNE_EXPOSED_LOSS_S;
		hHorizPay = ai.GetTunable("apex_reclaim_amort", TUNE_RECLAIM_AMORT);
		if (hHorizPay <= 1.f)
			hHorizPay = 300.f;
		const float dHave = DefenceValue();
		const float dWant = DefenceTarget();
		if (PlantFramed())   // see the fill: no wall before a base
			hGap = dWant - dHave - DefenceInFlightM();
		hWallUp = WallStands();
		hRentPerCell = hWallUp ? (PfMetalPerCell() * PfCrowd()) : 0.f;
		hFill = TargetFill(dHave, dWant);
		hEffBP = EffBP(Catalog::gBuildPower[uid]);
		const float affS = ai.GetTunable("apex_def_afford_s", TUNE_DEF_AFFORD_S);
		hAffordM = EcoPowerM() * ((affS > 1.f) ? affS : 30.f);
		// Rank against the best tower we could BUY, not the best that exists --
		// see TeamBestTowerPowerAffordable. 0 restores the old behaviour for
		// the A/B; both numbers are printed in `apex: defwhy`.
		hTeamPowAll = TeamBestTowerPower();
		hTeamPow = (ai.GetTunable("apex_def_teampow_afford", 1.f) > 0.f)
				? TeamBestTowerPowerAffordable(hAffordM)
				: hTeamPowAll;
		if (hTeamPow <= 0.f)
			hTeamPow = hTeamPowAll;   // nothing affordable yet: unchanged
		hTtdH = ai.GetTunable("apex_def_ttd_h", TUNE_DEF_TTD_H);
		hDomOn = ai.GetTunable("apex_def_dominance", TUNE_DEF_DOMINANCE) > 0.f;
		hEffOn = ai.GetTunable("apex_wall_efficient", TUNE_WALL_EFFICIENT) > 0.f;
		hLineW = ai.GetTunable("apex_wall_line_w", TUNE_WALL_LINE_W);
	}
	for (uint i = 0; i < cand.length(); ++i) {
		const int d = cand[i];
		if (Gate(GATE_AVAIL, !Catalog::gAvailable[d] || Catalog::gMobile[d]
			|| Catalog::gFloater[d] || Catalog::gSub[d]))
			continue;
		const int cls = ProtClassOf(d);
		if (Gate(GATE_CLASS, cls < 0))
			continue;
		if (Gate(GATE_HALF, HalfOfClass(cls) != half))
			continue;
		if (defOff && ((cls == PROT_DEF) || (cls == PROT_AA)))
			continue;
		// Recorded HERE, before any gate: a candidate that never reaches the
		// price is exactly the one worth seeing, and a list built at the end
		// cannot show it. -1 means "classed as a turret and then dropped".
		if (rankNow && (cls == PROT_DEF)) {
			gDefRankDef.insertLast(d);
			gDefRankV.insertLast(-1.f);
		}
		float gain = 0.f;
		AIFloat3 at = core;
		if (cls == PROT_DEF) {
			// ONE AUCTION OVER PLACES, not an ordered cascade. Gain is the
			// expected loss this turret would PREVENT: the stake standing in
			// its reach, times how often lethal force arrives there, times
			// the share of the local threat it newly stops.
			//
			// Diminishing returns are arithmetic here rather than a crowding
			// divisor -- once standing cover already exceeds the threat, the
			// next turret prevents nothing and prices itself out. That is
			// also what retired the quiet-rear veto: a rear nothing can
			// reach has no threat, so it buys no towers without being
			// forbidden to.
			const float reach = (Catalog::gMaxRange[d] > 1.f)
					? Catalog::gMaxRange[d] : 500.f;
			const float adds = PfTowerKill(d);
			// THE WAVE A POST MUST BEAT IS THE ONE THAT ARRIVES TOGETHER, not
			// the reading at this instant. Under that floor one cheap tower
			// saturates the shortfall -- measured, `short=1.00->0.00` off a
			// single Beamer -- and everything a heavy gun brings past it is
			// discarded by the clip below while its full metal and energy bill
			// is charged, so the auction can only ever buy the cheapest turret
			// in the list. Same symmetric expectation DefenceTarget already
			// floors on, apportioned by the share of our worth standing in
			// this post's reach: near zero early, and it grows with the army.
			DefSiteFill(d, reach, adds, hMexFloorWave, hSiteWave, hEnemyPrior);
			const float kCost = Catalog::gCostM[d]
					+ Catalog::BuildSecondsAt(d, hEffBP) * hWage;
			AIFloat3 bestAt = at;
			float bestGain = 0.f;
			float bestScore = 0.f;
			bool bestIsFront = false;
			bool bestIsRing = false;
			bool bestIsWall = false;
			bool bestIsLine = false;
			// THE ASKER'S OWN GUNS ARE TOLERANCE (his ruling: commanders are
			// good early wall makers because they can defend themselves). A
			// negative cached prev is a wall slot the danger gate refused,
			// holding the enemy cost that refused it; this builder may take
			// it if its kill power -- in the same light-tower-metal currency
			// cover uses -- covers the difference. Zero for an unarmed con.
			float wallPullP = 0.f;
			if (hGap > 0.f) {
				// Bounded at one building, for the reason DefSiteFill is:
				// a slot holds one gun, so it answers one gun's worth of
				// the shortfall and no more.
				float gapP = hGap;
				if (gapP > Catalog::gCostM[d])
					gapP = Catalog::gCostM[d];
				if (gapP > 0.f)
					wallPullP = gapP / hHorizS;
			}
			const float rentCells = float((Catalog::gAreaCells[d] > 0)
					? Catalog::gAreaCells[d] : 1);
			const array<float>@ prevs = gDsPrev[d];
			if (prevs !is null) {
				// The five site arrays are handles into a per-def cache;
				// indexing gDsX[d][si] resolved the outer array on every
				// read of every slot.
				const array<float>@ dsX = gDsX[d];
				const array<float>@ dsZ = gDsZ[d];
				const array<bool>@ dsFront = gDsFront[d];
				const array<bool>@ dsRing = gDsRing[d];
				const array<bool>@ dsWall = gDsWall[d];
				for (uint si = 0; si < prevs.length(); ++si) {
					float prev = prevs[si];
					if (prev < 0.f) {
						if (Gate(GATE_SLOT_MARK,
								(-prev >= Catalog::gCostM[d] + hUGuardM)
								|| (wallPullP <= 0.f)))
							continue;
						prev = wallPullP
								* (WallSlotLine(si) ? hLineW : 1.f);
					}
					if (Gate(GATE_SLOT_DEAD, prev <= 0.f))
						continue;
					const AIFloat3 s = AIFloat3(dsX[si], 0.f, dsZ[si]);
					const float wSec = ((hUSpeed > 1.f)
							? (hUPos.distance2D(s) / hUSpeed) : 60.f) * hWalkW;
					// AN INTERIOR TOWER PAYS FOR ITS GROUND (apexearth:
					// "we fill our bases up with tons of turrets... while
					// they're there we have no room to build a lot of
					// other stuff"). Behind the wall is base interior;
					// when the base is crowded those cells carry the same
					// metal-per-cell price the obsolete-reclaim market
					// puts on ground. Free on the wall, the line and the
					// open flanks -- an empty base charges nothing.
					float rentS = 0.f;
					if (hWallUp && (WallRimDist(s) < 0.f))
						rentS = hRentPerCell * rentCells;
					// WHAT THE POST PREVENTS OVER ITS PAYBACK HORIZON, per
					// metal spent -- the walk shortens the window it stands
					// for and bills the builder's time, nothing more.
					//
					// The horizon is the amortisation window the mex stream
					// is capitalised over (apex_reclaim_amort, 300 s), not
					// the 120 s exposure window and not the 900 s payback
					// horizon. Against 120 s a 72-second walk to the map's
					// choke (3,800 elmos on Aethermoor) left a slot 40% of
					// its worth while a ring slot ten seconds away kept 92%,
					// and no tower ever stood on the choke; against 900 s
					// the walk stopped mattering at all and opening cons
					// walked 1,500 elmos to line slots past the mex they
					// were standing on (guard 4/8 at minute 8, three
					// openings with one tower). At 300 s the choke keeps
					// three quarters and the mex underfoot still wins.
					//
					// It was prev / (kCost + wSec*wage + prev*wSec): the
					// walk charged at the site's own prevention rate. That
					// is 1/(payback + walk), and a pull-priced slot pays
					// back in a second or two, so among wall slots the
					// score reduced to 1/walk and the nearest open slot won
					// whatever it was worth -- the line lost to the rear
					// ring on distance alone until the ring closed.
					float standS = hHorizPay - wSec;
					if (standS < 0.f)
						standS = 0.f;
					const float score = prev * standS
							/ (kCost + rentS + wSec * hWalkRate);
					if (score > bestScore) {
						bestScore = score;
						bestGain = prev;
						bestAt = s;
						bestIsFront = dsFront[si];
						bestIsRing = dsRing[si];
						bestIsWall = dsWall[si];
						bestIsLine = bestIsWall && WallSlotLine(si);
					}
				}
			}
			gDbgLineN = gDsLineN[d];
			if (Gate(GATE_DEF_NOSITE, bestGain <= 0.f))
				continue;
			DwEnsure(d);
			gDwRaw[d] = bestGain;
			gDwTtd[d] = 1.f;
			gDwT1[d] = 1.f;
			gDwEff[d] = 1.f;
			gDwFill[d] = 1.f;
			gDwTeam[d] = 1.f;
			gDwVal[d] = 0.f;
			gDwSite[d] = bestIsWall ? 3 : (bestIsFront ? 1 : (bestIsRing ? 2 : 0));
			// SATURATE. Every other major want has a target it reaches and then
			// stops asking; ground defence never had one, so it was bought
			// marginally forever at a value that never decayed -- the hazard it
			// multiplies is floored by a prior scaling with our OWN economy, so
			// turrets simply tracked the economy: 175% of it, against stock's 52%.
			// This is the same shape the AA branch above already uses against
			// AirSeenEver, and the same shape ArmyTarget has always had.
			// TIME TO DEFENCE (apexearth: "we need to build the quicker
			// defenses there on the front line. TTD can be very important").
			// A turret prevents nothing while it is still a nanoframe, so its
			// gain is worth only the share of the threat window it will
			// actually be standing for -- the same temporal-consistency
			// discount ProposePlant applies to a lab's first constructor and
			// EPriceAt applies to energy.
			//
			// Build time barely reached the price before this: it entered only
			// as BuildSecondsAt * Wage, about 116 metal against an Agitator's
			// 1300, so a turret taking seven times as long as a Guard paid
			// about nine percent for the privilege. Measured, 94% of the
			// Agitators we lost died unfinished.
			//
			// The horizon is apex_exposed_loss_s -- the window this AI already
			// uses for "an exposed asset is expected to be lost" -- so a turret
			// that takes as long to build as the thing it guards takes to die
			// is worth half. Reused rather than invented; apex_def_ttd_h
			// separates the two if the front wants sharper pressure than the
			// rear.
			{
				// THE LATHE ALREADY STANDING ON THAT GROUND IS BUILD POWER.
				//
				// apexearth 2026-08-31: "we should like to make even more
				// defenses when we have nanos nearby when we're closer to the
				// enemy." This is that, and it needs no new multiplier: the
				// discount above is the share of the threat window the turret
				// will actually be STANDING for, and a site inside a nano ring
				// finishes in a fraction of the time. Only the asking
				// builder's own BP was counted, so a slot covered by six
				// turrets priced exactly like bare ground.
				//
				// It aims itself at the front, which is why it answers the
				// second half of his sentence too. The discount is
				// ttdH/(ttdH+bSec), so it bites hardest where bSec is largest
				// against the window -- the exposed forward ground where 94%
				// of the Agitators we lost died unfinished. A rear slot whose
				// discount is already near 1 has nothing to gain from it.
				const float bSec = Catalog::BuildSecondsAt(d,
						hEffBP + RingBPAt(bestAt));
				if ((hTtdH > 1.f) && (bSec > 0.f)) {
					gDwTtd[d] = hTtdH / (hTtdH + bSec);
					bestGain *= gDwTtd[d];
				}
			}
			// apexearth 2026-08-30: a Gauntlet-class tower "competes heavily
			// with our transition to T2 and is completely outclassed by the
			// T2 it's expected to be fighting."
			//
			// A REFUSAL, NOT A DISCOUNT -- and the measurement is why. This was
			// a 0.02 multiplier for a day, and Agitators kept appearing.
			// `apex: defwhy` finally showed the reason: `priced=1`,
			// `RUNNERUP none`. Every discount DID apply (xT1late 0.020,
			// xWallEff 0.031, xTeamPow 0.139, driving val to 0.0000) and the
			// Agitator won anyway, because it was the ONLY defence candidate
			// that reached pricing -- the cheaper towers were dropped at
			// site.nostop, their ground already covered, while a 1245-elmo gun
			// still found open ground. No multiplier can lose an auction of
			// one -- so what stops a T1 tower now is the team-wide candidate
			// list plus GATE_DEF_ROUTE, and this term only breaks the tie
			// between two towers that both reached pricing (apexearth, twice,
			// the second time: "We've gone over and proved how they are
			// low-value defense... Fix it with priority").
			// Dominated on reach AND killing power by something we can
			// afford right now: its metal is stranded on arrival.
			// Both refusals below are counted: they hid 320 of 418
			// candidates a game and every defwhy read "RUNNERUP none".
			if (Gate(GATE_DEF_OBSOLETE,
					hDomOn && DefObsoleteOnArrival(builds, d, hAffordM))) {
				gDwT1[d] = 0.f;
				continue;
			}
			// ...outclassed by a gun THIS hand can build: a T1 hand filling
			// the shortfall (below) has no better option to be discounted
			// against, and a T2 hand's light tower still is.
			if (T1Tower(d) && HandHasT2Tower(builds)) {
				gDwT1[d] = ai.GetTunable("apex_t1_def_late", TUNE_T1_DEF_LATE);
				bestGain *= gDwT1[d];
			}
			// ONCE AN ADVANCED HAND EXISTS, NO BASIC TOWER AT ALL (apexearth
			// 2026-09-19: "spend as much money as it would take to upgrade a
			// T2 Mex on tier 1 towers in the center of our base... at the
			// same time as we're slowly upgrading a Mex"). The shortfall
			// waits for the advanced hand's gun; the basic hand's one
			// stopgap (own-fill) is the only light tower after T2.
			if (Gate(GATE_DEF_T1LATE, T1Tower(d) && (CeilingConsOwned() > 0)
				&& (ai.GetTunable("apex_t1_tower_late", TUNE_T1_TOWER_LATE) > 0.f))) {
				gDwT1[d] = 0.f;
				continue;
			}
			// A WALL SLOT IS DEMAND FOR A WALL, NOT FOR A BIG GUN. Its gain
			// is the def-INDEPENDENT unmet-target pull, so the only thing
			// separating two towers there is the power scaling further down,
			// which rewards the highest power the builder can make -- and for
			// a T1 hand that is the Agitator. Measured in a watched game: 35
			// of them placed on wall slots at forward fraction -0.40 to -0.64,
			// i.e. BEHIND the base, at gain 0.00 (apexearth: "why the heck is
			// a T1 con making defenses anyways... teal is about to have 7 of
			// them"). On a slot priced by pull rather than by threat, rank by
			// cover per metal -- the currency the rest of this auction uses.
			// ...NOT ON THE LINE. A line slot holds the strongest gun this
			// economy affords -- the dominance rule above has already
			// dropped what a better affordable gun outclasses -- because a
			// line of the cheapest tower per metal is the half-built line
			// he is watching fail ("It needs to be really strong to
			// succeed"). The per-metal ranking stays for the ring.
			// ...and not on a slot carrying the SHORTFALL pull either: that
			// pull asks for the strongest gun the economy affords, and by
			// cover per metal it bought a ring of light towers (his watch).
			if (bestIsWall && !bestIsLine && hEffOn && (wallPullP <= 0.f)
				&& (Catalog::gCostM[d] > 1.f)) {
				const float eff = PfTowerKill(d) / Catalog::gCostM[d];
				// The benchmark is over the ASKER's build list, so it is the
				// same number for every candidate; built on the first ask.
				if (hBestEff < 0.f) {
					hBestEff = 0.f;
					for (uint bq = 0; bq < builds.length(); ++bq) {
						const int bd = builds[bq];
						if (Catalog::gMobile[bd] || !Catalog::gAvailable[bd]
							|| (ProtClassOf(bd) != PROT_DEF)
							|| (Catalog::gCostM[bd] <= 1.f))
						{
							continue;
						}
						const float be = PfTowerKill(bd) / Catalog::gCostM[bd];
						if (be > hBestEff)
							hBestEff = be;
					}
				}
				if ((hBestEff > 0.f) && (eff < hBestEff)) {
					gDwEff[d] = eff / hBestEff;
					bestGain *= gDwEff[d];
				}
				// WHICH TOWER DOES THIS RULE ACTUALLY PICK, AND WHY.
				// apexearth, watching: "I wanna scream at teal here for making
				// 15 god damn Gauntlet turrets... 5 pulsars would save our
				// asses right now." The numbers say he is right -- Gauntlet
				// 105 dps for 1,250 metal against Pulsar 1,091 for 3,500, so
				// 3.7x the damage per metal -- and this ranking is what stands
				// between them. One census of every candidate the builder can
				// make, so the term that decides is a fact and not a theory.
				if (!gWallEffDiag) {
					gWallEffDiag = true;
					for (uint bq2 = 0; bq2 < builds.length(); ++bq2) {
						const int bd2 = builds[bq2];
						if (Catalog::gMobile[bd2] || !Catalog::gAvailable[bd2]
							|| (ProtClassOf(bd2) != PROT_DEF)
							|| (Catalog::gCostM[bd2] <= 1.f))
							continue;
						AiLog("apex: wall-eff t=" + ai.teamId
							+ " " + Catalog::Def(bd2).GetName()
							+ " m=" + int(Catalog::gCostM[bd2])
							+ " hp=" + int(Catalog::gHealth[bd2])
							+ " surfDps=" + formatFloat(PfSurfDps(bd2), "", 0, 1)
							+ " kill=" + formatFloat(PfTowerKill(bd2), "", 0, 3)
							+ " eff=" + formatFloat(PfTowerKill(bd2) / Catalog::gCostM[bd2], "", 0, 5));
					}
				}
			}

			gDwFill[d] = hFill;
			gain = bestGain * gDwFill[d];
			if (Gate(GATE_DEF_FILL, gain <= 0.f))
				continue;
			at = bestAt;
			if (ai.frame >= gNextDefPriceLog) {
				gNextDefPriceLog = ai.frame + 30 * SECOND;
				AiLog("apex: defprice t=" + ai.teamId
					+ " gain=" + formatFloat(gain, "", 0, 2)
					+ " stake=" + formatFloat(gDbgStake, "", 0, 0)
					+ " threat=" + formatFloat(gDbgThreat, "", 0, 0)
					+ " cover=" + formatFloat(gDbgCover0, "", 0, 0)
					+ "->" + formatFloat(gDbgCover1, "", 0, 0)
					// How much of the cover at the chosen site is MOBILE. A
					// turret bought because units happened to be standing there
					// is a turret whose reason walks away.
					+ " unitCover=" + formatFloat(Military::UnitCoverAt(bestAt), "", 0, 0)
					+ " short=" + formatFloat(gDbgShort0, "", 0, 2)
					+ "->" + formatFloat(gDbgShort1, "", 0, 2)
					+ " hz=" + formatFloat(gDbgHz, "", 0, 5)
					+ " (hazard=" + formatFloat(gDbgHazard, "", 0, 5)
					+ " siege=" + formatFloat(gDbgSiege, "", 0, 5)
					// Printed whether or not apex_hz_approach is on: the term
					// has to be readable at the site where the decision is
					// actually made, not only at home.
					+ " appr=" + formatFloat(ApproachP(bestAt,
							Military::OurArmyNow() + gDbgCover0), "", 0, 3) + ")"
					+ " | econM=" + formatFloat(gAssetsM - gProtM, "", 0, 0)
					+ " protM=" + formatFloat(gProtM, "", 0, 0)
					+ " army=" + formatFloat(ArmyValue(), "", 0, 0)
					+ " foeSeen=" + formatFloat(Military::EnemyArmyCost(), "", 0, 0)
					+ " | mex=" + OwnMexCount()
					+ " mexFloor=" + int(MexCoverFloorM() * float(OwnMexCount()))
					+ " defHave=" + int(DefenceValue())
					+ " defTarget=" + int(DefenceTarget()));
			}
			NoteDefSite(bestIsFront, bestIsRing, bestIsWall);
			// Is the chosen post in FRONT of the base or behind it? He reports
			// towers landing behind, which the site list alone cannot show.
			if (ai.frame >= gNextDefFwdLog) {
				gNextDefFwdLog = ai.frame + 30 * SECOND;
				AiLog("apex: defplace " + Catalog::Def(d).GetName()
					+ " walk=" + int(unit.GetPos(ai.frame).distance2D(bestAt))
					+ " mexSite=" + ((SiteIsMex(bestAt)) ? 1 : 0)
					+ " fwd=" + formatFloat(Military::ForwardFraction(bestAt), "", 0, 2)
					+ " anchorFwd=" + formatFloat(Base::gAnchorSet
						? Military::ForwardFraction(Base::gAnchor) : -9.f, "", 0, 2)
					+ " front=" + (bestIsFront ? 1 : 0)
					+ " ring=" + (bestIsRing ? 1 : 0)
					+ " wall=" + (bestIsWall ? 1 : 0)
					+ " line=" + (bestIsLine ? 1 : 0)
					// Distance to the nearest map wall, and the share of the
					// approach that is real map there. The wall used to PAY.
					+ " edgeD=" + int(EdgeDist(bestAt))
					+ " open=" + formatFloat(Military::OpenFraction(bestAt, 500.f), "", 0, 2)
					+ " rimD=" + int(PfRimDist(bestAt))
					+ " wallD=" + int(WallStands() ? WallRimDist(bestAt) : -9999.f)
					+ " rimR=" + int(PfRimAt(bestAt))
					+ " gain=" + formatFloat(bestGain, "", 0, 2));
			}
		} else if (!SenseGainOf(unit, d, cls, core, rate, at, gain)) {
			continue;
		}
		// GROUND THE C++ REACH VETO REFUSED IS NOT A SITE. Bought anyway, the
		// executor's probe ring put the want on the base ring far from the
		// line it was priced for, which stayed uncovered, so it won again.
		// A gun is re-sited within its own range by the executor's probe and
		// keeps its worth; it is the unarmed classes whose fallback served
		// nothing.
		if ((cls != PROT_DEF) && Gate(GATE_SITE_BLOCKED, NearBlocked(at)))
			continue;
		// ROUTE THE WANT TO A HAND THAT CAN FULFIL IT. apexearth 2026-08-27:
		// "if our defence want is for T3 we should *not* be routing it through
		// T1 cons. It should only get to the cons which could potentially
		// fulfill it." The candidate list is this unit's OWN build options, so
		// a T1 con can only ever answer a defence want with a light tower --
		// measured over one game, 187 of 201 defence elections were run by T1
		// constructors and 32 of 36 defence wins were armllt, while the Pulsar
		// reached the ranking 9 times in the whole match. Scaling the T1
		// answer by how far short of the team's best tower it falls stops the
		// budget being spent on light towers before the heavy gun is ever
		// asked for. Continuous, and 1 while nothing better is owned -- early
		// game, and any faction/con that already holds the best option.
		if (cls == PROT_DEF) {
			const float mine = Catalog::Def(d).power;
			const float team = hTeamPow;
			if ((team > 0.f) && (mine > 0.f) && (team > mine)) {
				DwEnsure(d);
				gDwTeam[d] = mine / team;
				gain *= gDwTeam[d];
			}
			if (Gate(GATE_DEF_TEAM, gain <= 0.f))
				continue;
		}
		if (Gate(GATE_ZERO_GAIN, gain <= 0.f))
			continue;
		Want c;
		const float walkSec = (hUSpeed > 1.f)
				? (hUPos.distance2D(at) / hUSpeed) : 60.f;
		ValueOf(d, gain, walkSec, Catalog::gBuildPower[uid], c,
				cls != PROT_DEF);
		if (rankNow && (cls == PROT_DEF) && (gDefRankDef.length() > 0))
			gDefRankV[gDefRankV.length() - 1] = c.value;
		if (cls == PROT_DEF) {
			DwEnsure(d);
			gDwVal[d] = c.value;
			gWhyDef.insertLast(d);
		}
		if (c.value > w.value) {
			w = c;
			w.kind = (half == HALF_SENSE) ? WK_SENSE
					: ((half == HALF_AIRDEF) ? WK_AIRDEF : WK_PROTECT);
			@w.def = Catalog::Def(d);
			w.pos = at;
			w.spotId = cls;
		}
		// The best gun THIS hand can place, for the shortfall below.
		if ((cls == PROT_DEF) && (c.value > own.value)
			&& unit.circuitDef.CanBuild(Catalog::Def(d))) {
			own = c;
			own.kind = WK_PROTECT;
			@own.def = Catalog::Def(d);
			own.pos = at;
			own.spotId = cls;
		}
	}
	if (rankNow && (gDefRankDef.length() > 0)) {
		gNextDefRankOf[ruid] = ai.frame + 60 * SECOND;
		string r = "";
		for (uint q = 0; q < gDefRankDef.length(); ++q) {
			r += " " + Catalog::Def(gDefRankDef[q]).GetName()
				+ "=" + formatFloat(gDefRankV[q], "", 0, 4)
				+ "/kill" + formatFloat(PfTowerKill(gDefRankDef[q]), "", 0, 1);
		}
		// ...and what this builder could offer but never did. A candidate list
		// of two out of a T2 constructor is a filter question, not a price one.
		string dropped = "";
		for (uint q2 = 0; q2 < builds.length(); ++q2) {
			const int dq = builds[q2];
			if (Catalog::gMobile[dq] || (Catalog::gMaxRange[dq] <= 1.f))
				continue;
			if (Catalog::gAvailable[dq] && !Catalog::gFloater[dq]
				&& !Catalog::gSub[dq] && (ProtClassOf(dq) == PROT_DEF))
				continue;
			dropped += " " + Catalog::Def(dq).GetName()
				+ ":avail=" + (Catalog::gAvailable[dq] ? 1 : 0)
				+ ",float=" + (Catalog::gFloater[dq] ? 1 : 0)
				+ ",sub=" + (Catalog::gSub[dq] ? 1 : 0)
				+ ",cls=" + ProtClassOf(dq);
		}
		AiLog(Factory::T() + "apex: defrank by="
			+ unit.circuitDef.GetName() + " n=" + gDefRankDef.length()
			+ " aRef=" + int(PfAlphaRef())
			+ " foeSeen=" + int(ai.GetEnemyMaxMobileCostM())
			+ " ourBest=" + int(OwnedBestMobileCostM()) + r
			+ " | dropped:" + dropped);
	}
	// WHY THIS TOWER AND NOT THE OTHER ONE. Only the Want that actually won
	// this election, decomposed against the def that came second, because a
	// product of a dozen terms cannot be attributed from the product alone.
	// Rate-limited, and the line says how many wins it stands for.
	if ((half == HALF_GROUND) && (w.def !is null) && (w.spotId == PROT_DEF)) {
		++gDefWhyWins;
		if (ai.frame >= gNextDefWhyLog) {
			gNextDefWhyLog = ai.frame + 20 * SECOND;
			const int wd = int(w.def.id);
			DwEnsure(wd);
			int rd = -1;
			for (uint q = 0; q < gWhyDef.length(); ++q) {
				const int cd = gWhyDef[q];
				if (cd == wd)
					continue;
				if ((rd < 0) || (gDwVal[cd] > gDwVal[rd]))
					rd = cd;
			}
			AiLog(Factory::T() + "apex: defwhy by=" + unit.circuitDef.GetName()
				+ " SAMPLE 1of" + gDefWhyWins + "wins"
				+ " priced=" + gWhyDef.length()
				+ " || WIN " + DefWhyTerms(wd)
				+ " || RUNNERUP "
				+ ((rd >= 0) ? DefWhyTerms(rd) : "none"));
			gDefWhyWins = 0;
		}
	}
	// ROUTE, DO NOT SUBSTITUTE. His ruling twice over -- 2026-08-27, "if our
	// defence want is for T3 we should *not* be routing it through T1 cons. It
	// should only get to the cons which could potentially fulfill it", and
	// 2026-08-30, "why are you letting the little guy make the decision?".
	// It was implemented as a discount (xTeamPow) both times, which cannot
	// work: a discount still leaves the inferior tower as the asker's best
	// answer, and it gets spent. So the hand that cannot build what the team
	// decided on proposes NOTHING here and goes and does something else; the
	// want waits for a hand that can fulfil it.
	if ((w.def !is null) && (half == HALF_GROUND)
		&& !unit.circuitDef.CanBuild(w.def)) {
		// ...UNLESS THE SHORTFALL STANDS. apexearth 2026-09-18: "let the T1
		// cons fill the shortfall with their best gun." The team's gun still
		// waits for a hand that can build it; this hand answers the unmet
		// target with the best it has, and stops when the target is met.
		// ...not the commander: he stays home.
		// ...and bounded at ONE gun of its own kind standing: the fill is
		// the stopgap until the hand that can build the team's gun arrives,
		// not a wall of light towers (25 inside 250 elmos of one base, his
		// watch).
		if ((hGap > 0.f) && (own.def !is null)
			&& !unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask)
			&& (T1TowerStandingM() + DefenceInFlightM() < Catalog::gCostM[int(own.def.id)])) {
			Gate(GATE_DEF_OWN, true);
			return own;
		}
		Gate(GATE_DEF_ROUTE, true);
		Want none;
		return none;
	}
	return w;
}

// NO ROLE VETO HERE, DELIBERATELY. What the rear specialist should build is
// decided by what the want is WORTH to it -- covered ground behind teammates
// prices near nothing, so it loses the auction on arithmetic. apexearth:
// "if want for defence or army is 0 then we should have none. It should
// really be that simple."
Want@ ProposeProtect(CCircuitUnit@ unit)
{
	TargetLog();
	LogDefGates();
	return ProposeProtectHalf(unit, HALF_GROUND);
}

Want@ ProposeSense(CCircuitUnit@ unit)
{
	return ProposeProtectHalf(unit, HALF_SENSE);
}

Want@ ProposeAirDef(CCircuitUnit@ unit)
{
	return ProposeProtectHalf(unit, HALF_AIRDEF);
}


}  // namespace Market
