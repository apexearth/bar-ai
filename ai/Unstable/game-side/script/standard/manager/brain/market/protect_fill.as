namespace Market {
// THE SITE AUCTION, CACHED PER DEF. Everything in the per-site loop except
// the walk is unit-independent (threat, stake, cover, hazard move on their
// own clocks), yet it re-ran for every defence def of every builder on every
// election: measured 61s of one 686s game inside prot.loop alone, and the
// 37-69ms spikes he can feel at 5x speed. The fill computes each site's
// PREVENTED loss at most once per def per two seconds; the election keeps
// only the walk-weighted argmax. The arithmetic inside is unchanged.
array<array<float>@> gDsPrev;
array<array<float>@> gDsX;
array<array<float>@> gDsZ;
array<array<bool>@> gDsFront;
array<array<bool>@> gDsRing;
array<array<bool>@> gDsWall;
array<int> gDsAt;
array<int> gDsLineN;
int gDsFillFrame = -1;
int gDsFillN = 0;
void DefSiteFill(int d, float reach, float adds, float mexFloorWave,
		float siteWave, float siegeFrac)
{
	if (int(gDsAt.length()) <= Catalog::gDefCount) {
		gDsPrev.resize(uint(Catalog::gDefCount + 1));
		gDsX.resize(uint(Catalog::gDefCount + 1));
		gDsZ.resize(uint(Catalog::gDefCount + 1));
		gDsFront.resize(uint(Catalog::gDefCount + 1));
		gDsRing.resize(uint(Catalog::gDefCount + 1));
		gDsWall.resize(uint(Catalog::gDefCount + 1));
		gDsAt.resize(uint(Catalog::gDefCount + 1));
		gDsLineN.resize(uint(Catalog::gDefCount + 1));
	}
	// 4s, not 2: with the election memo in front of this, misses concentrate
	// the fills -- want.protect still ran 1.2s/min at 1700 m/s on the 2s
	// clock. Defence siting tolerates 4s staleness; the 2-fills-per-frame
	// cap below still bounds the worst frame.
	if (Gate(GATE_FILL_CACHE, (gDsAt[d] > 0) && (ai.frame - gDsAt[d] < 4 * SECOND)))
		return;
	// A bound on WORK per frame, not on defence: one frame refreshes at most
	// two def fills; a def that already has a cache serves it one election
	// longer.
	//
	// THE CAP APPLIES TO UNCACHED DEFS TOO. It used to read
	// `(gDsAt[d] > 0) && (gDsFillN >= 2)`, so a def that had NEVER been filled
	// bypassed the throttle entirely -- the reasoning being that it "could
	// never enter at all" otherwise. That is false: elections run every frame,
	// so an uncached def gets its turn within a frame or two regardless. What
	// the exemption actually bought was an unbounded frame. Measured on
	// Supreme Isthmus v2.1, 1v1 cortex, +100%, minute 28: a 127.7 ms spike,
	// with prot.loop averaging 6.3 ms PER FILL -- and the team-wide defence
	// catalogue (2026-08-30) took the candidate list from ~3 defs to 8-14, so
	// every one of the new defs filled on the same frame the first time it
	// appeared. N x 6.3 ms, uncapped, in one sim frame.
	if (gDsFillFrame != ai.frame) {
		gDsFillFrame = ai.frame;
		gDsFillN = 0;
	}
	// ONE FILL PER FRAME, not two. Each costs ~5.5 ms once the base is large,
	// so two is an 11 ms frame from this source alone. The 4-second per-def
	// cache means one-per-frame still refreshes every def many times over --
	// spreading the same work across frames instead of stacking it, which is
	// the standing rule (apexearth: "we should calculate how many frames happen
	// in five seconds and spread out the processing unit by unit throughout the
	// frames... We split out that operation over time").
	if (Gate(GATE_FILL_FRAME, gDsFillN >= 1))
		return;
	++gDsFillN;
	gDsAt[d] = (ai.frame > 0) ? ai.frame : 1;
	const double _tSites = Perf::T0();
	// THE WALL REPLACES THE INTERIOR (apexearth 2026-08-30: towers blobbed
	// "right around our start area"; the asset-cluster candidates concentrate
	// where the metal is densest, which is always the spawn). With the wall on,
	// ground defence is offered perimeter slots instead of asset centroids,
	// front-line spots or closure-ring bearings; gates and the ally-front post
	// stay -- the concentration doctrine is orthogonal to the wall.
	const bool wallOn = ai.GetTunable("apex_wall", TUNE_WALL) > 0.f;
	array<AIFloat3> sites;
	uint nWall = 0;
	if (wallOn)
		nWall = PfWallSlots(sites);
	else
		PfGuardSites(reach, sites);
	const uint nAsset = sites.length();
	// THE DOORWAYS FIRST. apexearth 2026-08-29: "defend chokepoints ahead of
	// where the mexes are... prevent the enemy from getting in there." Every
	// gate of our held ground is a candidate; the fill's own pricing
	// (FrontedStakeAt + ShieldedStakeAlong on the enemy-away axis) already
	// values what a doorway shields, so gates win elections exactly where
	// something real stands behind them. The old single near-anchor choke
	// stays as the fallback while influence is too thin to own any ground.
	uint nGates = 0;
	if (ai.GetTunable("apex_choke_gates", TUNE_CHOKE_GATES) > 0.f)
		{
			array<AIFloat3> gates;
			nGates = Front::GateChokes(gates);
			for (uint gi = 0; gi < gates.length(); ++gi)
				sites.insertLast(gates[gi]);
		}
	if ((nGates == 0) && Base::gAnchorSet) {
		AIFloat3 cp;
		if (Front::FrontChoke(Base::gAnchor, cp)) {
			AIFloat3 site;
			if (!Front::BehindChoke(cp, 180.f, site))
				site = cp;
			sites.insertLast(site);
		}
	}
	if (!wallOn && (ai.GetTunable("apex_front_line", TUNE_FRONT_LINE) > 0.f)) {
		array<AIFloat3> line;
		if (Military::FrontBuildSpots(line)) {
			// BUILT A STEP BEHIND THE EDGE (his ruling: "both" -- setback
			// and escorts): a tower ON the contested edge dies as a frame
			// (s43: all defence task-deaths hurt-retreat/unreach); a few
			// hundred elmos back it finishes and still ranges the approach.
			const float back = ai.GetTunable("apex_def_setback", TUNE_DEF_SETBACK);
			for (uint fi = 0; fi < line.length(); ++fi) {
				AIFloat3 fp = line[fi];
				if (back > 1.f) {
					const AIFloat3 haven = gFarmSet ? gFarmPos
							: (Base::gAnchorSet ? Base::gAnchor : fp);
					AIFloat3 dirB = haven - fp;
					if (dirB.SqLength2D() > 1.f) {
						dirB.SafeNormalize2D();
						const AIFloat3 fp2 = fp + dirB * back;
						if (OnMap(fp2))
							fp = fp2;
					}
				}
				sites.insertLast(fp);
			}
		}
	}
	// EVERY OPEN APPROACH BEARING IS A CANDIDATE (apexearth: enemies attack
	// through the side; "our angle of defense has to be really flexible" --
	// on some maps we are completely surrounded). ClosureAdds already pays a
	// post for the bearings it newly closes, but the asset sites hug our own
	// metal and the front spots cover only hot bearings, so a cold flank
	// never held a site the credit could land on. One candidate per open ring
	// bearing, pulled inward so the def's own reach still covers the ring
	// point with margin (ProtCovered's 0.8). No arc constant: an off-map
	// bearing is a wall, a covered one is closed, and the auction prices the
	// rest individually -- surrounded means every bearing is for sale.
	const uint ringStart = sites.length();
	if (!wallOn && (ai.GetTunable("apex_def_ring", TUNE_DEF_RING) > 0.f)) {
		ClosurePrep();
		if (gClRingOk) {
			for (uint rb = 0; rb < gClRingP.length(); ++rb) {
				if (!gClRingOpen[rb])
					continue;
				AIFloat3 dirR = gClRingP[rb] - gClMid;
				if (dirR.SqLength2D() < NEAR_ZERO)
					continue;
				dirR.SafeNormalize2D();
				float rS = gClRingR - reach * 0.8f;
				if (rS < 64.f)
					rS = 64.f;
				const AIFloat3 rp = gClMid + dirR * rS;
				if (OnMap(rp))
					sites.insertLast(rp);
			}
		}
	}
	// A BACK PLAYER BUYS ITS DEFENCE AT THE FRONT ALLY'S DOOR (his ruling,
	// refusing to host the 8v8: turrets belong "in front of their allies
	// base who is in front of them"). Offered only while an ally actually
	// shields one of our bearings -- a front player, and every 1v1, adds
	// nothing here. One candidate: the most exposed teammate's home pushed
	// one base-edge-plus-reach toward the enemy. Its stake is that ally's
	// PUBLISHED economy (TV_ASSETM, defenceline.as) times our AnswerShare:
	// each back player buys its SHARE of the team's front guard -- each
	// instance sees only its own towers, so an unshared stake would stack
	// N players' full demand on the same door.
	const uint allyStart = sites.length();
	float allyStake = 0.f;
	if (wallOn)
		ClosurePrep();   // the ally-front post below reads the ring's ally cones
	if (gClRingOk && (wallOn
		|| (ai.GetTunable("apex_def_ring", TUNE_DEF_RING) > 0.f))) {
		bool behind = false;
		for (uint sb = 0; !behind && (sb < gClAllyShield.length()); ++sb)
			behind = gClAllyShield[sb];
		AIFloat3 foeAt = aiEnemyMgr.GetEnemyPos();
		if (behind && OnMap(foeAt) && (gShieldMates !is null)) {
			int mate = -1;
			float best = -1.f;
			AIFloat3 mh;
			for (uint m = 0; m < gShieldMates.length(); ++m) {
				if (int(gShieldMates[m]) == ai.teamId)
					continue;
				const float mx = ai.ReadTeamValue(int(gShieldMates[m]), "homex", -1.f);
				const float mz = ai.ReadTeamValue(int(gShieldMates[m]), "homez", -1.f);
				if ((mx < 0.f) || (mz < 0.f))
					continue;
				const AIFloat3 h(mx, 0.f, mz);
				const float mD = h.distance2D(foeAt);
				if ((best < 0.f) || (mD < best)) {
					best = mD;
					mate = int(gShieldMates[m]);
					mh = h;
				}
			}
			if (mate >= 0) {
				const float mAssets = ai.ReadTeamValue(mate,
						Military::TV_ASSETM, 0.f);
				AIFloat3 dirF = foeAt - mh;
				if ((mAssets > 1.f) && (dirF.SqLength2D() > 1.f)) {
					dirF.SafeNormalize2D();
					// Their perimeter, proxied by our own base extent (the
					// only extent a player can read), plus the def's reach.
					float fwdD = gClRingR - Military::FoeReach() + reach;
					if (fwdD < 256.f)
						fwdD = 256.f;
					const AIFloat3 ap = mh + dirF * fwdD;
					if (OnMap(ap)) {
						sites.insertLast(ap);
						allyStake = mAssets * AnswerShare();
					}
				}
			}
		}
	}
	Perf::Add("prot.sites", _tSites);
	const double _tLoop = Perf::T0();
	array<float> prevA(sites.length(), 0.f);
	array<float> xA(sites.length(), 0.f);
	array<float> zA(sites.length(), 0.f);
	array<bool> frontA(sites.length(), false);
	array<bool> ringA(sites.length(), false);
	array<bool> wallA(sites.length(), false);
	// AN UNMET TARGET IS DEMAND. DefenceTarget is the economic basis he chose
	// for the standing holding, but insurance pricing alone reads a quiet game
	// as no demand: threat at an unthreatened slot is ~0, every gate below
	// zeroes it, and the target sat at 680/20,021 while eight LLTs stood (the
	// per-def rank read armpb=0.0013 on a T2 hand -- defence could never win a
	// roulette). A wall standing BEFORE anything arrives is the product being
	// bought: every OPEN wall slot prices at least the unmet target amortized
	// over the exposure horizon. Only open slots -- a slot a standing tower
	// already covers earns nothing from the pull, so the ring completes one
	// tower per slot and then deepens only where real threat prices it.
	float wallPull = 0.f;
	if (wallOn) {
		const float horizW = ai.GetTunable("apex_exposed_loss_s",
				TUNE_EXPOSED_LOSS_S);
		const float gapM = DefenceTarget() - DefenceValue();
		if ((horizW > 1.f) && (gapM > 0.f))
			wallPull = gapM / horizW;
	}
	ClosurePrep();
	RiskFill();
	RiskFillSiege();
	float fillBest = 0.f;
	for (uint si = 0; si < sites.length(); ++si) {
		const AIFloat3 s = sites[si];
		if (Gate(GATE_SITE_OFFMAP, !OnMap(s)))
			continue;
		const bool isAllyF = (si >= allyStart);
		const bool isRing = (si >= ringStart) && !isAllyF;
		const bool isFront = ((si >= nAsset) && !isRing) || isAllyF;
		const bool isGate = isFront && !isAllyF && (si < nAsset + nGates);
		const bool isWall = wallOn && (si < nWall);
		// Only the asset prefix is in the field's slot cache; gates, front
		// spots and ring sites read their senses live. Wall slots have their
		// own stamp cache -- with the wall on, PfGuardSites never ran and
		// gPfSlot is stale, so PfSite* must not be indexed at all.
		const bool cached = !wallOn && (si < nAsset);
		xA[si] = s.x;
		zA[si] = s.z;
		frontA[si] = isFront;
		ringA[si] = isRing;
		wallA[si] = isWall;
		float threat = cached ? PfSiteThreat(si)
				: (isWall ? PfWallThreat(si) : ThreatAt(s));
		// THE GATE OVERWHELMS OR IT IS A SPEED BUMP (apexearth 2026-08-29:
		// "Have an unusual amount of tower at some spots. Try to deeply
		// cover those choke points. Easy wins there... It matches
		// concentration with concentration"). A gate's threat is floored at
		// a multiple of the wave that arrives together, so it keeps
		// deepening past parity -- the winrate6 ledger showed thin gates
		// dying WITH the base (81% of tower metal destroyed, K/D 0.65,
		// against stock's concentrated 1.04).
		if (isGate) {
			const float gateFloor = siteWave
					* ai.GetTunable("apex_gate_depth", TUNE_GATE_DEPTH);
			if (gateFloor > threat)
				threat = gateFloor;
		}
		// Exposure-scaled both ways -- see MexFloorFactor above.
		const float mexFloorHere = (mexFloorWave > 0.f)
				? (mexFloorWave * MexFloorFactor(s)) : 0.f;
		// ...and a PLANT takes the same floor as a mex -- see PlantInReach.
		// A slot beside the opening lab had no mex in range, so it priced
		// against a wave of zero and no LLT was ever worth building before
		// the first raid arrived.
		const bool floored = !isFront
				&& (MexInReach(s, reach) || PlantInReach(s, reach))
				&& (mexFloorHere > threat);
		if (floored)
			threat = mexFloorHere;
		if ((siteWave > 0.f) && (gPfTotal > 1.f)) {
			const float sStake = cached
					? PfSiteStake(si) : FrontedStakeAt(s, reach);
			float shr = sStake / gPfTotal;
			if (shr > 1.f)
				shr = 1.f;
			const float wHere = siteWave * shr;
			if (wHere > threat)
				threat = wHere;
			float heavy = PfHeavyRef();
			if (heavy > sStake)
				heavy = sStake;
			if (heavy > threat)
				threat = heavy;
			// THE WAVE DOES NOT SPLIT ITSELF. shr apportions the EXPECTED
			// wave among sites, but their massed force all takes one
			// approach -- hz already prices how often, so halving the
			// magnitude too is a double division, and under a small wave
			// `stopped` clips everything a heavy gun brings past it while
			// billing it in full: the cheapest turret wins by construction
			// (measured: threat 2153 against foeSeen 7420; Bulwark at half
			// a Toaster's value on 5x the kill; one Pulsar standing on a
			// massive economy). The wave a site must beat is their fielded
			// army, capped by the stake actually behind this site -- the
			// same cap the heaviest-single-attacker floor above uses.
			if (ai.GetTunable("apex_wave_conc", TUNE_WAVE_CONC) > 0.f) {
				float conc = gRkHost;
				if (conc > sStake)
					conc = sStake;
				if (conc > threat)
					threat = conc;
			}
		}
		// The pull keeps an OPEN wall slot alive through the evidence gates
		// below -- see the wallPull comment above the loop. Threat is floored
		// to 1 first so the shortfall arithmetic stays finite.
		//
		// NOT ON GROUND THE ENEMY IS STANDING ON -- UNLESS THE WALL IS
		// ALREADY BESIDE IT, OR THE BUILDER CAN FIGHT. The pull is
		// no-evidence demand; ungated, line slots deep in the contested
		// midfield fed frames to the enemy army one at a time (7 built, 7
		// lost, walks past 1,100). But gated on quiet alone the line only
		// extends where nothing is happening, and his ruling is
		// completeness: "a wall of towers is useless if the enemy can just
		// walk around it. So it needs to extend the whole way." The creep is
		// the resolution: a slot NEXT TO A HELD SECTION may rise under that
		// tower's fire whatever the ground reads, so the line extends
		// section by section from the base to the map edge or the ally's
		// lane, never by lone frames in an open field.
		//
		// A slot refused ONLY by this danger gate is not dead -- it is
		// marked with the enemy cost that refused it (negative prevA), and
		// the per-builder election lifts the mark when THAT builder's own
		// guns cover the difference (apexearth 2026-08-30: "Commanders are
		// good early game wall makers here because they can defend
		// themselves"). The mark lives in the per-def cache; the tolerance
		// is the asker's, applied outside it, so a con never inherits a
		// commander's courage from a shared fill.
		const bool pullBase = isWall && (wallPull > 0.f) && WallSlotOpen(si);
		float foeHere = -1.f;
		bool pullHere = false;
		if (pullBase) {
			if (WallSlotAdjHeld(si)) {
				pullHere = true;
			} else {
				foeHere = ai.GetEnemyCostAt(s, 900.f);
				pullHere = (foeHere < Catalog::gCostM[d]);
			}
		}
		if (pullBase && !pullHere && (foeHere >= 0.f))
			prevA[si] = -foeHere;   // overwritten if evidence prices it below
		if (pullHere && (threat < 1.f))
			threat = 1.f;
		if (Gate(GATE_SITE_THREAT, (threat <= 1.f) && !pullHere))
			continue;
		float stake = (cached && (reach >= 64.f))
				? PfSiteStake(si) : FrontedStakeAt(s, reach);
		// The stream the tower keeps flowing -- see MexStreamM above. Rear
		// sites only: a front site's stake is the fight, not the farm.
		if (!isFront)
			stake += MexStreamM(s, reach);
		{
			const float dClose = wallOn ? WallAdds(s, reach)
					: ClosureAdds(s, reach);
			AIFloat3 outDir = isFront
					? (aiEnemyMgr.GetEnemyPos() - s) : (s - gPfMid);
			if (isFront || gPfRimOk)
				stake += ShieldedStakeAlong(s, reach, outDir) * dClose;
		}
		// The ally-front post guards the ALLY'S holdings: our own stake
		// reads ~zero at their door, so the site is staked by what the
		// teammate published -- see the candidate's comment above.
		if (isAllyF)
			stake = allyStake;
		if (Gate(GATE_SITE_STAKE, (stake <= 1.f) && !pullHere))
			continue;
		const float cover0 = cached ? PfSiteCover(si)
				: (isWall ? PfWallCover(si) : CoverAt(s));
		const float cover1 = cover0 + CoverAddsAt(s, reach, adds);
		float short0 = (threat - cover0) / threat;
		if (short0 < 0.f)
			short0 = 0.f;
		float short1 = (threat - cover1) / threat;
		if (short1 < 0.f)
			short1 = 0.f;
		float stopped = short0 - short1;
		if (floored) {
			const float gained = cover1 - cover0;
			float step = mexFloorHere - cover0;
			if (step > gained)
				step = gained;
			stopped = (gained > 0.f) ? (step / gained) : 0.f;
		}
		if (Gate(GATE_SITE_STOP, (stopped <= 0.f) && !pullHere))
			continue;
		const float hazard = cached ? PfSiteHz(si)
				: (isWall ? PfWallHz(si) : HazardWith(s, cover0));
		float hz = hazard;
		const float sg = cached ? PfSiteSiege(si)
				: (isWall ? PfWallSiege(si) : SiegeWith(s, cover0, siegeFrac));
		// AN UNGUARDED MEX IS EXPECTED TO DIE WITHIN THE EXPOSURE WINDOW --
		// his prior, watched happen again 2026-08-30: "if we don't guard a
		// mex then it will 100% die in the early game... a tick... costs us
		// at least 1000 metal". The measured arrival rate at quiet ground
		// (~1/180s) is a truth about ATTACKS SEEN, not about what happens
		// to naked extractors; while NOTHING covers a floored mex slot, the
		// rate floors at once per exposure window. Any cover at all returns
		// the slot to the measured rates.
		if (floored && (cover0 <= 0.f)) {
			const float lossS = ai.GetTunable("apex_exposed_loss_s",
					TUNE_EXPOSED_LOSS_S);
			if ((lossS > 1.f) && (hz < 1.f / lossS))
				hz = 1.f / lossS;
		}
		if (sg > hz)
			hz = sg;
		// A POST CANNOT DEFEND MORE THAN IT CAN KILL. stake is everything
		// inside this def's own reach, which credits a long gun with the
		// whole economy a short one cannot see; PfKillCapM is the metal its
		// damage rate actually destroys over the exposure window. Ceiling,
		// not a scaling -- a tower well inside its own capacity is untouched.
		float stakeK = stake;
		{
			const float capM = PfKillCapM(d);
			if ((capM > 0.f) && (stakeK > capM))
				stakeK = capM;
		}
		float prevented = stakeK * hz * stopped;
		// THE PULL FACES THE ENEMY. Uniform, it grew the wall by walk
		// distance -- toward builder convenience, not the war (measured over
		// four normal-play games: median tower bearing 45-116 degrees off the
		// enemy base, vs the old blob's 21). A slot's share of the pull
		// follows its bearing: full toward the enemy, tapering to
		// apex_wall_rear directly behind -- his flexible-angle ruling keeps
		// the rear above zero, so the ring still closes once the front is
		// held. Real measured threat is untouched; this shapes only the
		// no-evidence floor.
		if (pullHere && (wallPull > 0.f)) {
			float dirW = 1.f;
			const AIFloat3 foeP = aiEnemyMgr.GetEnemyPos();
			// Line slots ARE the front -- full pull along their whole
			// lateral run, which is what makes the towers a line across the
			// lane instead of an arc hugging the base. And MORE than full
			// while the line is incomplete: his ruling ("a wall of towers
			// is useless if the enemy can just walk around it. So it needs
			// to extend the whole way") makes an extending section worth
			// more than a redundant deepening -- at flat urge the line sat
			// at fill 0.33 when a 44-minute game timed out.
			if (WallSlotLine(si)) {
				const float lw = ai.GetTunable("apex_wall_line_w",
						TUNE_WALL_LINE_W);
				if (lw > 1.f)
					dirW = lw;
			} else if (OnMap(foeP)) {
				AIFloat3 toS = s - gPfMid;
				AIFloat3 toF = foeP - gPfMid;
				const float lS = sqrt(toS.SqLength2D());
				const float lF = sqrt(toF.SqLength2D());
				if ((lS > 1.f) && (lF > 1.f)) {
					const float cosA = (toS.x * toF.x + toS.z * toF.z)
							/ (lS * lF);
					const float w01 = 0.5f + 0.5f * cosA;
					float rear = ai.GetTunable("apex_wall_rear",
							TUNE_WALL_REAR);
					if (rear < 0.f) rear = 0.f;
					if (rear > 1.f) rear = 1.f;
					dirW = rear + (1.f - rear) * w01;
				}
			}
			if (prevented < wallPull * dirW)
				prevented = wallPull * dirW;
		}
		prevented *= Military::OpenFraction(s, reach);
		{
			const float k = ai.GetTunable("apex_unprot_discount",
					TUNE_UNPROT_DISCOUNT);
			if (k > 0.f) {
				const float f0 = (cover0 < threat)
						? (cover0 / threat) : 1.f;
				const float f1 = (cover1 < threat)
						? (cover1 / threat) : 1.f;
				if (f1 > f0)
					prevented += stake * k * (f1 - f0) * hz;
			}
		}
		prevA[si] = prevented;
		if (isAllyF && (ai.frame >= gNextAllyFLog)) {
			gNextAllyFLog = ai.frame + 60 * SECOND;
			AiLog("apex: allyfront cand at=" + int(s.x) + "," + int(s.z)
				+ " stake=" + int(stake) + " threat=" + int(threat)
				+ " prev=" + formatFloat(prevented, "", 0, 2));
		}
		if (isWall) {
			if (prevented > gDbgWallBest) gDbgWallBest = prevented;
		} else if (isFront) {
			if (prevented > gDbgFrontBest) gDbgFrontBest = prevented;
		} else if (isRing) {
			if (prevented > gDbgRingBest) gDbgRingBest = prevented;
		} else if (prevented > gDbgAssetBest) {
			gDbgAssetBest = prevented;
		}
		// The defprice diag follows the fill's own argmax; the walk-adjusted
		// winner can differ slightly.
		if (prevented > fillBest) {
			fillBest = prevented;
			gDbgStake = stake;
			gDbgHz = hz;
			gDbgSiege = sg;
			gDbgHazard = hazard;
			gDbgShort0 = short0;
			gDbgShort1 = short1;
			gDbgStopped = stopped;
			gDbgThreat = threat;
			gDbgCover0 = cover0;
			gDbgCover1 = cover1;
		}
	}
	@gDsPrev[d] = prevA;
	@gDsX[d] = xA;
	@gDsZ[d] = zA;
	@gDsFront[d] = frontA;
	@gDsRing[d] = ringA;
	@gDsWall[d] = wallA;
	gDsLineN[d] = int(ringStart - nAsset);
	// This def's OWN argmax terms, stamped with the fill: gDbg* are shared
	// across defs, so reading them after a CACHED fill would report whichever
	// def filled last. Zero when no site priced at all.
	DwEnsure(d);
	gDwKill[d] = adds;
	gDwStake[d] = (fillBest > 0.f) ? gDbgStake : 0.f;
	gDwHz[d] = (fillBest > 0.f) ? gDbgHz : 0.f;
	gDwStop[d] = (fillBest > 0.f) ? gDbgStopped : 0.f;
	gDwThreat[d] = (fillBest > 0.f) ? gDbgThreat : 0.f;
	gDwCov0[d] = (fillBest > 0.f) ? gDbgCover0 : 0.f;
	gDwCov1[d] = (fillBest > 0.f) ? gDbgCover1 : 0.f;
	Perf::Add("prot.loop", _tLoop);
}
}  // namespace Market
