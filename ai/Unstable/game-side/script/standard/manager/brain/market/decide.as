namespace Market {
//------------------------------------------------------------------------------
// The arbiter's builder side. Called only from Brain::Decide.
//------------------------------------------------------------------------------

int gNextIdleLog = 0;
int gNextAuctionDiag = 0;
int gNextAaPanicLog = 0;
int gNextDefPanicLog = 0;
array<int> gLastDecideAt(32001, -30000);   // per-unit-id, Spring ids cap at 32k
// Per-unit approach tracking: how far its site was at the last election, so
// "still closing" can be distinguished from "stalled".
array<float> gApproachD(32001, -1.f);
array<int> gApproachAt(32001, -30000);
// Which builder may drop its work for the first AA tower, and when it claimed
// that. One at a time: the tower is 80 metal, abandoning every frame in the
// base is not.
int gAaClaim   = -1;
int gAaClaimAt = -30000;

// Why a builder ends an election holding nothing: per-kind count of wants
// that ranked but could not be turned into a task.
array<int> gExecFail(32, 0);
int gExecNone = 0;
int gNextExecLog = 0;

IUnitTask@ Decide(CCircuitUnit@ unit)
{
	if ((unit is null) || !unit.circuitDef.IsBuilder() || !unit.circuitDef.IsMobile())
		return null;
	// A unit whose task keeps dying young re-enters every frame; 2s per
	// unit caps the global decide rate without touching legit elections
	// (a successful decide holds its task far longer than this).
	if ((int(unit.id) >= 0) && (int(unit.id) < int(gLastDecideAt.length()))) {
		if (ai.frame - gLastDecideAt[int(unit.id)] < 2 * SECOND)
			return null;
		gLastDecideAt[int(unit.id)] = ai.frame;
	}
	WorkerSeen(unit);
	LedgerSweep();
	RiskDiag();
	// STAYING ALIVE OUTRANKS THE JOB, and it is asked BEFORE the
	// finish-what's-started return below -- a commander with progress on a
	// frame would otherwise never reach this at all, which is exactly the
	// state he dies in (apexearth, watching: "he did *nothing* to protect
	// himself").
	{
		IUnitTask@ safe = CommanderSafety(unit);
		if (safe !is null)
			return safe;
	}
	// SEEN THEIR AIR WITH NOTHING THAT SHOOTS UP INTERRUPTS THE JOB
	// (apexearth: "it should interrupt what we are currently doing as a
	// builder. AA coverage is cheap and easy"). The panic below only reorders
	// an election, and a builder with progress on a frame returns under this
	// and never has one. Ends the moment the first tower stands.
	bool aaEmerg = (gProtPos[PROT_AA].length() == 0)
			&& (Military::AirSeenEver() > 0.f);
	if (aaEmerg) {
		const bool stale = (ai.frame - gAaClaimAt) > 20 * SECOND;
		if ((gAaClaim == int(unit.id)) || (gAaClaim < 0) || stale) {
			gAaClaim = int(unit.id);
			gAaClaimAt = ai.frame;
		} else {
			aaEmerg = false;   // someone else is already on it
		}
	} else {
		gAaClaim = -1;
	}
	// FINISH WHAT'S STARTED (his rule: "focus as much build power as we
	// can on just the one building"): a builder whose current frame has
	// real progress holds it -- the roulette explores at the next FREE
	// election, never by abandoning work. Without this, re-election
	// re-rolled every ~2s and the engine reassigns on build-type change:
	// 61 sentry requests, 850 metal into nanoframes, zero finished
	// (measured, 25-minute game). The stall sweep still aborts held tasks
	// explicitly when the economy demands it.
	if (!aaEmerg && (unit.task !is null) && (unit.task.GetType() == Task::Type::BUILDER)) {
		if (Requests::Progress(unit.task) > 0.01f)
			return null;
		// ...and the FINAL APPROACH counts as started: a walker near its
		// site finishes the trip (walk-phase re-rolls left sentry sites
		// nobody ever arrived at). Far walkers may still reconsider --
		// a long walk is a real opportunity cost worth re-asking about.
		const AIFloat3 tp0 = unit.task.GetBuildPos();
		if (OnMap(tp0)) {
			const float dNow = unit.GetPos(ai.frame).distance2D(tp0);
			if (dNow < 600.f)
				return null;
			// A WALK IN PROGRESS IS WORK IN PROGRESS. Re-rolling every 2s while
			// still approaching meant a distant site was never reached: measured
			// in one 1v1, 461 decisions to build an LLT, 21 requests created and
			// ZERO defences standing at the end -- 46% of all constructor
			// elections spent walking away from the last one. So a builder that
			// is genuinely CLOSING on its site holds; one that has stopped
			// closing (blocked, or the site moved) re-elects as before.
			const int uw = int(unit.id);
			if ((uw >= 0) && (uw < int(gApproachD.length()))) {
				const float prev = gApproachD[uw];
				const bool stale = (ai.frame - gApproachAt[uw]) > 30 * SECOND;
				gApproachD[uw] = dNow;
				gApproachAt[uw] = ai.frame;
				if (!stale && (prev > 0.f) && (dNow < prev - 1.f))
					return null;
			}
		}
	}

	array<Want@> wants = {
		ProposeMex(unit), ProposeEnergy(unit), ProposeGeo(unit),
		ProposePlant(unit), ProposeConvert(unit), ProposeStore(unit),
		ProposeMexUp(unit), ProposeTech(unit), ProposeNano(unit),
		ProposeReclaimObsolete(unit), ProposeReclaimBlocker(unit), ProposeAssist(unit),
		ProposeProtect(unit), ProposeSense(unit), ProposeAirDef(unit)
	};
	// EXPOSURE IS A COST THE ASSET ITSELF PAYS. A want's return is reduced by
	// the rate at which the thing is expected to be destroyed where it would
	// stand, so an expensive structure on uninsured ground prices itself down
	// -- and either moves somewhere covered, waits for the cover to be worth
	// buying first, or stops being worth building at all. Without this the
	// two decisions are independent and a fusion can win every auction while
	// nothing on the map protects it (apexearth). Same law decide.as already
	// applies to the commander, generalized past him.
	// Protect wants are exempt: their gain is already the loss they prevent,
	// so charging them again would price a turret for its own exposure twice.
	for (uint i = 0; i < wants.length(); ++i) {
		Want@ c = wants[i];
		if ((c is null) || (c.value <= 0.f) || (c.def is null))
			continue;
		if ((c.kind == WK_PROTECT) || c.def.IsMobile() || !OnMap(c.pos))
			continue;
		// An unset pos is the origin, and the origin reads as maximally
		// exposed ground -- charging it would quietly suppress every want
		// that forgot to name a site.
		if ((c.pos.x < 1.f) && (c.pos.z < 1.f))
			continue;
		const float exposed = ExpectedLossAt(c.pos, c.def.costM);
		if (exposed <= 0.f)
			continue;
		c.gain -= exposed;
		c.value = (c.gain > 0.f) ? (c.gain / (c.mCost + c.tCost)) : 0.f;
	}
	// Highest value first; a want the executor refuses (ground taken, request
	// standing, join out of reach) falls out and the runner-up is tried --
	// a builder never idles while a positive want remains executable.
	array<Want@> ranked;
	for (uint i = 0; i < wants.length(); ++i) {
		Want@ c = wants[i];
		if ((c is null) || (c.value <= 0.f))
			continue;
		uint at = 0;
		while ((at < ranked.length()) && (ranked[at].value >= c.value))
			++at;
		ranked.insertAt(at, c);
	}
	// THEIR AIR WITH NOTHING THAT SHOOTS UP IS AN EMERGENCY, NOT A BID.
	// apexearth: "when enemy starts bombing us and we have 0 AA I expect the
	// very next thing we build to be AA" -- and, later, not to wait for the
	// bombing: seeing their air is the trigger. While it holds, the airdef
	// want skips the lottery rather than taking a proportional share of it.
	// It stops the instant the first tower stands.
	bool aaPanic = false;
	if (aaEmerg) {
		for (uint ri = 0; ri < ranked.length(); ++ri) {
			if (ranked[ri].kind != WK_AIRDEF)
				continue;
			if (ri > 0) {
				Want@ aa = ranked[ri];
				ranked.removeAt(ri);
				ranked.insertAt(0, aa);
			}
			aaPanic = true;
			if (ai.frame >= gNextAaPanicLog) {
				gNextAaPanicLog = ai.frame + 15 * SECOND;
				AiLog("apex: AA PANIC -- seen "
					+ formatFloat(Military::AirSeenEver(), "", 0, 0)
					+ " metal of enemy air with zero AA standing; "
					+ ((ranked[0].def is null) ? "?" : ranked[0].def.GetName())
					+ " jumps the queue");
			}
			break;
		}
	}
	// A HOME WITH NOTHING DEFENDING IT IS ALSO AN EMERGENCY (apexearth: "I'd
	// also argue a home base with 0 defense on a small 1v1 map vs barb ai is an
	// emergency"). Same shape as the AA panic: both halves measured -- we own
	// zero ground defence AND something is actually killing our structures --
	// so it cannot fire on a hunch and it ends the moment the first tower
	// stands. Ranked ahead of the lottery rather than given a share of it.
	if (!aaPanic && (gProtPos[PROT_DEF].length() == 0)
		&& (LossRateAt(Builder::gHomePos) > 0.f))
	{
		for (uint ri = 0; ri < ranked.length(); ++ri) {
			if (ranked[ri].kind != WK_PROTECT)
				continue;
			if (ri > 0) {
				Want@ dw = ranked[ri];
				ranked.removeAt(ri);
				ranked.insertAt(0, dw);
			}
			aaPanic = true;   // reuse the skip-the-lottery flag
			if (ai.frame >= gNextDefPanicLog) {
				gNextDefPanicLog = ai.frame + 15 * SECOND;
				AiLog("apex: DEF PANIC -- losing "
					+ formatFloat(LossRateAt(Builder::gHomePos), "", 0, 2)
					+ " m/s at home with zero defence standing; "
					+ ((ranked[0].def is null) ? "?" : ranked[0].def.GetName())
					+ " jumps the queue");
			}
			break;
		}
	}
	// PROPORTIONAL DRAW OVER CATEGORIES, argmax inside one (apexearth:
	// "think about eco related things by category... then we pick the
	// highest value energy"). The draw still exists -- winner-takes-all
	// starved every want that never ranked #1 (team 3 bought nanos at
	// v=20-275 for 8 minutes while the T2 lab bid 16.7 once and never won).
	// What changed is WHO gets a ticket: energy/geo/convert/store used to
	// draw four times per election against extraction's two, which is how
	// 672 wind turbines were bought against 1 moho upgrade (measured). One
	// question, one ticket, weighted by that question's best answer.
	if ((ranked.length() > 1) && !aaPanic) {
		array<int> catBest(CAT_N, -1);   // index into ranked, or -1
		for (uint ri = 0; ri < ranked.length(); ++ri) {
			const int c = CategoryOf(ranked[ri].kind);
			if (c < 0)
				continue;
			// ranked is sorted by value descending, so the FIRST want seen
			// for a category is that category's argmax -- this is the
			// "highest value energy" pick, made once per election.
			if (catBest[c] < 0)
				catBest[c] = int(ri);
		}
		// HOW SHARP THE DRAW IS. Weighting each ticket by its raw value means a
		// want the market itself rates six times worse still wins one election
		// in six -- measured: 34% of elections took a lower-valued want, and a
		// mex valued 594 lost to a wind generator valued 99 (apexearth: "is it
		// a random 'luck of the draw' sort of event in that moment?"). Odds are
		// taken on the value RATIO to the leader raised to a power, so the
		// exponent alone moves between proportional (1, the old behaviour) and
		// argmax (large) without a threshold anywhere: at 2 a six-fold gap is
		// one election in thirty-six, which keeps a never-first category from
		// starving without letting it outbid arithmetic.
		const float lead = ranked[0].value;
		const float sharp = ai.GetTunable("apex_draw_sharp", TUNE_DRAW_SHARP);
		array<float> wt(CAT_N, 0.f);
		float sumV2 = 0.f;
		for (int c = 0; c < CAT_N; ++c) {
			if (catBest[c] < 0)
				continue;
			const float v = ranked[catBest[c]].value;
			// A COMMITMENT IS NOT SAMPLED. The cost of drawing a worse option
			// scales with what that option costs: a wrong 40-metal wind is
			// noise, a wrong 9700-metal afus is the game (apexearth: "for these
			// things that are so impactful I feel like we need to go with
			// winner takes all. There is only one right choice here"). Measured
			// the same session: EVERY afus bought was a draw override, priced
			// BELOW the runner-up each time -- 6.30 against 11.58, 8.53 against
			// 13.29 -- so the pricing was right and the lottery bought it
			// anyway at ~30% weight.
			//
			// So the exponent rises with how big a bite this candidate takes
			// out of what the economy can produce over the payback horizon.
			// Continuous and threshold-free: cheap wants keep their sampling,
			// and a want that would consume the whole horizon's output is
			// effectively argmax.
			float sh = sharp;
			{
				const float H = ai.GetTunable("apex_payback_h", TUNE_PAYBACK_H);
				const float cap = EcoPowerM() * ((H > 1.f) ? H : 900.f);
				if ((cap > 1.f) && (ranked[catBest[c]].def !is null)) {
					float bite = ranked[catBest[c]].def.costM / cap;
					if (bite > 1.f)
						bite = 1.f;
					sh += bite * ai.GetTunable("apex_commit_sharp",
							TUNE_COMMIT_SHARP);
				}
			}
			float t = v;
			if ((lead > 0.f) && (sh > 0.f) && (sh != 1.f))
				t = lead * pow(v / lead, sh);
			wt[c] = t;
			sumV2 += t;
		}
		if (sumV2 > 0.f) {
			uint h2 = uint(ai.frame) * 2654435761 + uint(unit.id) * 40503;
			h2 ^= (h2 >> 13);
			float roll2 = float(h2 % 10000) / 10000.f * sumV2;
			for (int c = 0; c < CAT_N; ++c) {
				if (catBest[c] < 0)
					continue;
				roll2 -= wt[c];
				if (roll2 <= 0.f) {
					const int ri = catBest[c];
					if (ri > 0) {
						Want@ drawn = ranked[ri];
						ranked.removeAt(uint(ri));
						ranked.insertAt(0, drawn);
					}
					break;
				}
			}
		}
	}
	Want@ top = (ranked.length() > 0) ? ranked[0] : null;
	Want@ next = (ranked.length() > 1) ? ranked[1] : null;
	// Auction dump for T2-capable builders, one per 30s, tunable-gated.
	if ((ai.GetTunable("apex_auction_diag", 0.f) > 0.f) && (ai.frame >= gNextAuctionDiag)) {
		bool t2able = false;
		const array<int>@ mm = Catalog::BuildsOf(int(unit.circuitDef.id));
		for (uint z = 0; z < mm.length(); ++z) {
			if (Catalog::gCostM[mm[z]] > 3000.f) {
				t2able = true;
				break;
			}
		}
		if (t2able) {
			gNextAuctionDiag = ai.frame + 30 * SECOND;
			string ln = "apex: auction " + unit.circuitDef.GetName() + " #" + unit.id + " |";
			for (uint z = 0; z < ranked.length(); ++z) {
				ln += " " + KindName(ranked[z].kind) + ":"
					+ ((ranked[z].def is null) ? "?" : ranked[z].def.GetName())
					+ " v=" + formatFloat(ranked[z].value * 1000.f, "", 0, 2)
					+ " (g=" + formatFloat(ranked[z].gain, "", 0, 1)
					+ " m=" + formatFloat(ranked[z].mCost, "", 0, 0)
					+ " t=" + formatFloat(ranked[z].tCost, "", 0, 0) + ")";
			}
			AiLog(ln);
		}
	}
	if (top is null) {
		// Floor want 1: a lesser con GUARDS a ceiling-reaching con -- guard
		// auto-assists whatever its target does, so 50 idle T1s (air cons
		// included) become T2 build power (apexearth 2026-08-23). Round-
		// robin spreads the guards.
		if (BestExtract() > 0.f) {
			float myCeil = 0.f;
			const array<int>@ mine = Catalog::BuildsOf(int(unit.circuitDef.id));
			for (uint i = 0; i < mine.length(); ++i) {
				if (Catalog::gExtractsM[mine[i]] > myCeil)
					myCeil = Catalog::gExtractsM[mine[i]];
			}
			if (myCeil < BestExtract()) {
				CCircuitUnit@ boss = NextServingCon();
				if (boss !is null) {
					if (ai.frame >= gNextIdleLog) {
						gNextIdleLog = ai.frame + 30 * SECOND;
						AiLog("apex: decide " + unit.circuitDef.GetName() + " #" + unit.id
							+ " -> guard:" + boss.circuitDef.GetName() + " #" + boss.id
							+ " (assist its work)");
					}
					IUnitTask@ gt2 = aiBuilderMgr.Enqueue(TaskB::Guard(
							Task::Priority::LOW, boss, false, 60 * SECOND));
					if (gt2 !is null)
						GuardNote(unit, boss);
					return gt2;
				}
			}
		}
		// Floor want 2: patrol the farm and auto-assist whatever builds there.
		if (gFarmSet) {
			if (ai.frame >= gNextIdleLog) {
				gNextIdleLog = ai.frame + 30 * SECOND;
				AiLog("apex: decide " + unit.circuitDef.GetName() + " #" + unit.id
					+ " -> assist (farm patrol; no positive want)");
			}
			return aiBuilderMgr.Enqueue(TaskB::Patrol(Task::Priority::LOW,
					gFarmPos, 20 * SECOND));
		}
		if (ai.frame >= gNextIdleLog) {
			gNextIdleLog = ai.frame + 30 * SECOND;
			AiLog("apex: decide " + unit.circuitDef.GetName() + " #" + unit.id
				+ " -> idle (no positive want)");
		}
		return null;
	}

	gWantEmaV = (gWantEmaV <= 0.f) ? top.value
			: (0.9f * gWantEmaV + 0.1f * top.value);
	AiLog("apex: decide t=" + ai.teamId + " " + unit.circuitDef.GetName() + " #" + unit.id
		+ " -> " + CatName(CategoryOf(top.kind))
		+ "/" + KindName(top.kind) + ":" + ((top.def is null) ? "-" : top.def.GetName())
		+ " v=" + formatFloat(top.value * 1000.f, "", 0, 2)
		+ " (gain=" + formatFloat(top.gain, "", 0, 2)
		+ " m=" + formatFloat(top.mCost, "", 0, 0)
		+ " t=" + formatFloat(top.tCost, "", 0, 0) + ")"
		+ ((next is null) ? " over nothing"
			: (" over " + CatName(CategoryOf(next.kind)) + "/" + KindName(next.kind)
				+ " v=" + formatFloat(next.value * 1000.f, "", 0, 2))));

	// THE COMMANDER NEVER TAKES EXPOSED WORK: his death is the game, so a
	// want's exposure is a cost HE pays at game-loss scale (measured: com
	// died at 15:00 building an LLT at a naked forward mex, medium anchor
	// t000 -- the insurance priced the mex's risk and forgot the asker's).
	const bool isComm = unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask);
	for (uint i = 0; i < ranked.length(); ++i) {
		// FORWARD of the anchor is what kills commanders; the farm-distance
		// radius also banned the rear-flank PLANT site and the commander --
		// early game's only builder -- never made a factory (watched, and it
		// poisoned a 20-game medium anchor). Behind the anchor is safe by
		// the grid's own construction.
		if (isComm && Base::gAnchorSet && Base::gAxisSet) {
			const AIFloat3 rel = ranked[i].pos - Base::gAnchor;
			const float fwdDist = rel.x * Base::gFwd.x + rel.z * Base::gFwd.z;
			// 400: the base-front turret post sits at anchor+150 and the old
			// 150 cutoff banned the commander from it -- mDefence read 0.0
			// for a whole game (apexearth: "in early game he can provide a
			// good defense"). Beyond 400 is the con-and-escort frontier.
			if (fwdDist > 400.f)
				continue;
		}
		IUnitTask@ t = ExecuteWant(unit, ranked[i]);
		if (t !is null)
			return t;
		if (uint(ranked[i].kind) < gExecFail.length())
			++gExecFail[ranked[i].kind];
	}
	// EVERY RANKED WANT REFUSED. The decide line above names what ranked
	// first, NOT what got built -- so a builder can log a decision every
	// update and hold no task at all, which is what sitting on a full bank
	// looks like from the inside. Nothing else reports the fall-through.
	++gExecNone;
	if (ai.frame >= gNextExecLog) {
		gNextExecLog = ai.frame + 30 * SECOND;
		string ln = "apex: exec-refused t=" + ai.teamId
				+ " allNull=" + gExecNone + " |";
		for (uint k = 0; k < gExecFail.length(); ++k) {
			if (gExecFail[k] > 0)
				ln += " " + KindName(int(k)) + "=" + gExecFail[k];
		}
		AiLog(ln);
	}
	return null;
}


}  // namespace Market
