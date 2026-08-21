namespace Brain {

// THE SENTINEL: the brain checking on its own concepts, out loud.
//
// apexearth 2026-08-21: "Our brain needs to be smart enough to know all these
// concepts and prioritize them... If something is wrong we need to rectify
// the situation. We could even report in the log our brain thoughts and
// assertions. If it decides it wants to fix certain things, it can be the
// guard that helps us tweak/tune the proper behavior in all our 'leaf logic'."
//
// OBSERVER-FIRST, on purpose. Every check states its verdict with the numbers
// that produced it, every pass -- that log IS the deliverable: it names which
// leaf logic to tune. A check only ACTS where a measured lever already exists,
// and each enforcement is earned separately -- the 2026-08-01 lesson is twelve
// individually-reasonable silent rules quartering the economy together.
//
// Log lines: `apex: thought <name> CONCERN <numbers>` per concern, and one
// `apex: thoughts ok: a b c ...` line for everything healthy.

int gNextThink = 0;
// Fusion-ask ageing: first frame the standing ask was seen; -1 while none.
int gFusionAskSince = -1;
// Metal-scaling window: income sampled a window ago.
float gPrevMetalIncome = -1.f;
int gPrevMetalFrame = 0;

string Num(float v) { return formatFloat(v, "", 0, 1); }

void Think()
{
	if (ai.GetTunable("apex_brain_thoughts", TUNE_BRAIN_THOUGHTS) <= 0.f)
		return;
	if (ai.frame < gNextThink)
		return;
	gNextThink = ai.frame + 45 * SECOND;
	string ok = "";
	const string T = Factory::T();

	// -- Am I scaling energy? ------------------------------------------------
	// The grid wants ENERGY_LEAD_RATIO energy per metal income (the ladder's
	// own bar); persistent stalling is the louder version of the same answer.
	{
		const float mInc = aiEconomyMgr.metal.income;
		const float eInc = aiEconomyMgr.energy.income;
		const float wantE = mInc * Builder::ENERGY_LEAD_RATIO;
		// Out of the opening only: the 12:1 lead is an established-economy
		// rule, and the opening (mInc under the first income bracket) reads
		// healthy at far lower ratios -- the first live session flagged a
		// perfectly normal 50 e/s start every pass.
		if ((mInc > 10.f) && (eInc < wantE * 0.7f)) {
			AiLog(T + "apex: thought energy CONCERN eInc " + Num(eInc)
				+ " under " + Num(wantE) + " wanted for mInc " + Num(mInc)
				+ (aiEconomyMgr.isEnergyStalling ? " STALLING" : "")
				+ " -- always-eco floor and the ladder should be buying");
		} else {
			ok += " energy";
		}
	}

	// -- Am I scaling metal? -------------------------------------------------
	// Growth over a window, not a level: a flat income at minute 20 is a
	// stalled expansion whatever its absolute number is.
	{
		const float mInc = aiEconomyMgr.metal.income;
		if (gPrevMetalIncome < 0.f) {
			gPrevMetalIncome = mInc;
			gPrevMetalFrame = ai.frame;
			ok += " metal";
		} else if (ai.frame - gPrevMetalFrame >= 3 * MINUTE) {
			const float grew = mInc - gPrevMetalIncome;
			// Sated banks mean income is not the constraint right now.
			if ((grew < mInc * 0.05f) && !Brain::EcoSated()
				&& (ai.frame > 8 * MINUTE))
			{
				AiLog(T + "apex: thought metal CONCERN income flat "
					+ Num(gPrevMetalIncome) + " -> " + Num(mInc)
					+ " over 3m -- expansion or mexup is stalled");
			} else {
				ok += " metal";
			}
			gPrevMetalIncome = mInc;
			gPrevMetalFrame = ai.frame;
		} else {
			ok += " metal";
		}
	}

	// -- Is my army OK? ------------------------------------------------------
	// Spend share vs its budget target, and standing value vs the most the
	// enemy has ever shown at once (blindness must not read as safety).
	{
		const float share = Brain::ShareOf(Brain::ARMY);
		const float target = Brain::TargetShare(Brain::ARMY);
		const float ours = Military::OurArmyNow();
		const float peak = Military::gSeenPeak;
		if ((Brain::gSpentTotal > 1000.f) && (target > 0.01f)
			&& (share < target * 0.6f))
		{
			AiLog(T + "apex: thought army CONCERN spend share " + Num(share * 100.f)
				+ "% of " + Num(target * 100.f) + "% target -- the budget tilt"
				+ " and facqueue should be feeding it");
		} else if ((peak > 500.f) && (ours < peak * 0.5f)) {
			AiLog(T + "apex: thought army CONCERN standing " + Num(ours)
				+ " under half the enemy's seen peak " + Num(peak));
		} else {
			ok += " army";
		}
	}

	// -- Do I need to create spam? -------------------------------------------
	// Standing fodder vs the stream the quota is meant to keep (post-T2).
	{
		if (Military::SpamPhase()) {
			float fodder = 0.f;
			for (uint i = 0; i < Military::gPostureDef.length(); ++i) {
				if (Military::gPostureFodder[i])
					fodder += float(Military::gPostureDef[i].count);
			}
			const float wantN = 2.f + aiEconomyMgr.metal.income
				/ ai.GetTunable("apex_spam_per_income", TUNE_SPAM_PER_INCOME);
			if (fodder < wantN * 0.5f) {
				AiLog(T + "apex: thought spam CONCERN " + Num(fodder)
					+ " standing of " + Num(wantN) + " wanted -- the stream is dry");
			} else {
				ok += " spam";
			}
		} else {
			ok += " spam";
		}
	}

	// -- Do I have too many T1 labs? -----------------------------------------
	// The stated policy is ONE until the reactor; past it the income curve
	// governs and this check goes quiet.
	{
		const int t1 = Factory::T1PlantCount();
		if ((t1 > 1) && Factory::T1CapHolds()) {
			AiLog(T + "apex: thought labs CONCERN " + t1
				+ " T1 plants pre-reactor -- the cap is one; check the"
				+ " unattributed entrance (hooks reclaim should have fired)");
		} else {
			ok += " labs";
		}
	}

	// -- Should I apply more build power to the fusion? ----------------------
	// An ask that stays unbuilt is ageing dedication elsewhere; the mexup cap
	// is the lever, this is the clock on it.
	{
		CCircuitDef@ fusD = SideDef3("armfus", "corfus", "legfus");
		const bool asked = (fusD !is null) && !Builder::HaveReactor()
			&& (Requests::InFlight(fusD) > 0);
		if (asked) {
			if (gFusionAskSince < 0)
				gFusionAskSince = ai.frame;
			const float ageM = float(ai.frame - gFusionAskSince) / float(MINUTE);
			if (ageM > 3.f) {
				AiLog(T + "apex: thought fusion CONCERN asked "
					+ Num(ageM) + "m ago and still not standing -- mexup cap"
					+ " holds half the adv cons; check who is actually on it");
			} else {
				ok += " fusion";
			}
		} else {
			gFusionAskSince = -1;
			ok += " fusion";
		}
	}

	// -- Is the army too far from home while the base is at risk? ------------
	{
		// NOT BaseContested: net influence at home reads negative on a
		// 90-second-old base whose own influence barely exists yet -- the
		// first live session cried recall from minute 1.5 of an empty map.
		// Risk means losses at home or enemy influence physically on it.
		const bool risk = Builder::BaseUnderAttack()
			|| (Builder::gHomeSet && (ai.GetEnemyInflAt(Builder::gHomePos) > 1.f));
		if (risk && OnMap(Military::gLaneAt)
			&& (Military::ForwardFraction(Military::gLaneAt) > 0.5f))
		{
			AiLog(T + "apex: thought recall CONCERN base at risk with the lane at fwd "
				+ Num(Military::ForwardFraction(Military::gLaneAt))
				+ " -- posture's defensive lane should be pulling back");
		} else {
			ok += " recall";
		}
	}

	if (ok != "")
		AiLog(T + "apex: thoughts ok:" + ok);
}

}  // namespace Brain
