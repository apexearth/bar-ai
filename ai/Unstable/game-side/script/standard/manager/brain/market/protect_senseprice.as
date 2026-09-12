namespace Market {

// THE SENSE AND AIR-DEFENCE PRICES -- radar, jammer, shield, AA and targeting
// facility. Lifted out of ProposeProtectHalf's candidate loop with the
// arithmetic untouched; `false` is that loop's `continue`, and every one of
// them is still counted by the same gate, so the census reads as before.
bool SenseGainOf(CCircuitUnit@ unit, int d, int cls, const AIFloat3& in core,
		float rate, AIFloat3& out at, float& out gain)
{
	at = core;
	gain = 0.f;
	// THE HELD LINE GETS ITS EYES, ITS JAMMER AND ITS AA FIRST (his doctrine:
	// "T2 radar and T2 jammer... only after all that, AA flak", and after the
	// 4v4 whose line stood ten minutes without any: "One thing we didn't do
	// well that game was making Jammers/radar up front, and anti air"). One
	// of each per line section, sited a pitch behind the guns, only on quiet
	// ground; the base's own logic below is untouched once the line has them.
	AIFloat3 lineAt;
	int lineN = 0;
	// ...and only ground our army plainly owns.
	const bool lineUp = WallLineQuiet(lineAt, lineN);
	if (cls == PROT_RADAR) {
		AIFloat3 gapAt;
		float unseenFrac = 0.f;
		if (lineUp && (Catalog::gRadarR[d] > 1.f)
			&& !ProtCovered(PROT_RADAR, lineAt, Catalog::gRadarR[d] * 0.6f))
		{
			at = lineAt;
			gain = (gProtM + ArmyValue()) * rate;
			return gain > 0.f;
		}
		if (Gate(GATE_RADAR_GAP,
				!RadarGap(unit.GetPos(ai.frame), gapAt, unseenFrac)))
			return false;
		// The gap is watched FROM SAFETY, never stood in. Gap sites past
		// the front or on hot ground ate constructors all game (2,069
		// sense elections, 33 radars standing at once never; 84 radar
		// frames died) -- the same "never send a con to build a tower in a
		// dangerous place" ruling every other static build already obeys.
		if (Gate(GATE_RADAR_FRONT,
				Front::FoeKnown() && Builder::PastFront(gapAt)))
			return false;
		if (Gate(GATE_RADAR_HOT, ai.GetEnemyCostAt(gapAt, 900.f)
				> Catalog::gCostM[int(unit.circuitDef.id)]))
			return false;
		at = gapAt;
		// Eyes for the army too: blind units chase shadows (apexearth:
		// "build radars so our units have intelligence"). Worth what is
		// still unwatched, so coverage follows the front instead of one
		// tower sitting at home for the whole game.
		gain = (gAssetsM + ArmyValue()) * rate * unseenFrac;
		// THE WARNING IS COVER. A guard reaches what it can get to before
		// the building dies, and radar warning extends that reach for every
		// guard at once, so the base needs fewer light units to be covered.
		// The metal of units the mast makes unnecessary, over the army's
		// fill horizon, is its gain -- the same currency ArmyGapStream uses
		// (apexearth: "we need vision and speed in order to properly defend
		// ourselves"; "it's cheap and we should make it").
		{
			float fill = ai.GetTunable("apex_army_fill_s", TUNE_ARMY_FILL_S);
			if (fill <= 1.f)
				fill = 180.f;
			gain += Military::EyesSavedM() / fill * unseenFrac;
		}
	} else if (cls == PROT_JAM) {
		// Tower concentrations want jamming first (apexearth): find a
		// cluster of >=3 defenses with no jammer in reach.
		//
		// THE SPACING NEVER TRUSTS THE BINDING ALONE. Every overlap test
		// here is CCircuitDef::GetJammerRadius, and a binding that reads
		// zero makes `distance < 0` false for every standing jammer, so
		// nothing is ever covered and each election sites another one on
		// top of the last (apexearth, watched: "purple has 11 jammers
		// too, many of them right next to each other. they provide no
		// coverage benefit"). Floored by the 300-elmo cluster radius this
		// same rule uses to decide what a cluster IS -- one jammer per
		// cluster is the stated intent, so a dead radius degrades to that
		// instead of to no limit at all. The raw value is logged once.
		const float jr = JamSpacing(d);
		// A point is covered by the jammer's REAL radius, and the tower is
		// sited where it can stand inside it: the engine may place up to 1600
		// elmos from the ask, so a cover test at the ask alone never closes.
		const float jamR = JamReach(d);
		AIFloat3 jat = core;
		bool found = false;
		int how = 0;
		if (lineUp && !ProtCovered(PROT_JAM, lineAt, jamR)) {
			jat = lineAt;
			found = true;
			how = 2;
		}
		for (uint jd = 0; jd < gProtPos[PROT_DEF].length() && !found; ++jd) {
			int nearDef = 0;
			for (uint jk = 0; jk < gProtPos[PROT_DEF].length(); ++jk) {
				if (gProtPos[PROT_DEF][jd].distance2D(gProtPos[PROT_DEF][jk]) < 300.f)
					++nearDef;
			}
			if ((nearDef >= 3)
				&& !ProtCovered(PROT_JAM, gProtPos[PROT_DEF][jd], jamR))
			{
				jat = gProtPos[PROT_DEF][jd];
				found = true;
				how = 1;
			}
		}
		if (Gate(GATE_JAM_COVER, !found && ProtCovered(PROT_JAM, core, jamR)))
			return false;
		const AIFloat3 jsite = ai.FindBuildSiteNear(Catalog::Def(d), jat, jamR);
		if (Gate(GATE_JAM_SITE, !OnMap(jsite) || (jsite.distance2D(jat) > jamR)))
			return false;
		// A SECOND JAMMER MUST CLEAR THE FIRST wherever it is going.
		if (Gate(GATE_JAM_COVER, ProtCovered(PROT_JAM, jsite, jr)))
			return false;
		jat = jsite;
		JamSiteLog(d, jat, how, jamR);
		if (how == 2) {
			at = jat;
			gain = gProtM * rate * 0.8f;
			return gain > 0.f;
		}
		// A JAMMER DENIES RADAR, so it is worth nothing until something is
		// USING radar against us -- indirect fire that shoots what it cannot
		// see. Priced on assets alone it won an early sense ticket over the
		// sentries and mexes we actually needed (apexearth, watched: "we're
		// making a jammer long before it would ever provide value"). Same
		// shape as the shield gate below, and for the same reason.
		const float indirect = Military::EnemyCostOf(Unit::Role::ARTY.type)
				+ Military::EnemyCostOf(Unit::Role::SKIRM.type) * 0.5f;
		if (Gate(GATE_JAM_ARTY, indirect < 200.f))
			return false;
		at = jat;
		gain = ((indirect < gAssetsM) ? indirect : gAssetsM)
				* rate * (found ? 0.8f : 0.5f);
	} else if (cls == PROT_SHIELD) {
		// Shields answer bombardment: worth the arty mass they blank,
		// covering the interior (the stock feature our gap survey ranked
		// first; their arty ground our statics 38k:7k).
		// An enemy LRPC is bombardment too -- it is STATIC, so the
		// mobile-role census above never counts it, and it fires from
		// across the map, so "no threat within 1800" is exactly what
		// its presence looks like (apexearth: "if enemy has LRPC we
		// need to build shields"). Its seen mass joins the basis and
		// waives the nearness gate.
		// LrpcStake, not gFoeLrpcCost: the raw census is live visibility and
		// flickers to zero whenever we lose eyes on their base, which is
		// almost always. See LrpcStake in protect_target.as.
		const float lrpcS = LrpcStake();
		const int lrpc = (lrpcS > 0.f) ? 1 : 0;
		const float artyS = Military::EnemyCostOf(Unit::Role::ARTY.type)
				+ Military::EnemyCostOf(Unit::Role::SKIRM.type) * 0.5f
				+ lrpcS;
		if (Gate(GATE_SHLD_ARTY, artyS < 200.f))
			return false;
		// ...and only when a threat is actually NEAR: a global arty
		// census bought shield stacks in a base nothing could reach
		// (apexearth: "too many shields while theres still no threat
		// very close"). The bombardier must be within twice its reach
		// of what the shield would cover -- unless it is an LRPC, whose
		// reach covers everything.
		if (Gate(GATE_SHLD_FAR,
				(lrpc <= 0) && (ai.GetEnemyCostAt(core, 1800.f) < 200.f)))
			return false;
		if (Gate(GATE_SHLD_COVER, ProtCovered(PROT_SHIELD, core, 400.f)))
			return false;
		// THE SAME THREE TERMS AS AA BELOW: what is at risk, how often it is
		// being hit, and the share THIS dome newly blanks. What stood here
		// was an insurance rate with a x4 fudge -- the shape AA was rewritten
		// away from, and it lost every auction for the same reason.
		// Saturation is arithmetic: each dome raises cover, which lowers both
		// the arrival rate and the next dome's share, so no cap is needed.
		float shFrac = ai.GetTunable("apex_shield_cover_frac", TUNE_SHIELD_COVER_FRAC);
		if (shFrac < 0.01f)
			shFrac = 0.01f;
		const float shTrade = 1.f / shFrac;
		float shCover = 0.f;
		for (uint si = 0; si < gProtDefId[PROT_SHIELD].length(); ++si)
			shCover += Catalog::gCostM[gProtDefId[PROT_SHIELD][si]] * shTrade;
		const float shAdds = Catalog::gCostM[d] * shTrade;
		float sShort0 = (artyS - shCover) / artyS;
		if (sShort0 < 0.f)
			sShort0 = 0.f;
		float sShort1 = (artyS - (shCover + shAdds)) / artyS;
		if (sShort1 < 0.f)
			sShort1 = 0.f;
		const float stoppedS = sShort0 - sShort1;
		if (Gate(GATE_SHLD_SAT, stoppedS <= 0.f))
			return false;
		// Turrets are excluded from the stake for the same reason AA and
		// SiegeRiskAt exclude them: defence must not be its own reason.
		float econS = gAssetsM - gProtM;
		if (econS < 0.f)
			econS = 0.f;
		const float horizS = ai.GetTunable("apex_exposed_loss_s", TUNE_EXPOSED_LOSS_S);
		const float anchorS = 1.f / ((horizS > 1.f) ? horizS : 120.f);
		const float shHz = anchorS * (artyS / (artyS + shCover))
				* ai.GetTunable("apex_shield_urgency", TUNE_SHIELD_URGENCY);
		const float gainS = econS * shHz * stoppedS;
		// Measured bombardment losses are a FLOOR, not the whole price --
		// they are what plasma has already cost us, which arrives after the
		// mex is dead. Exactly AA's use of AirLossRate.
		const float measuredS = Military::PlasmaLossRate() * stoppedS;
		gain = (measuredS > gainS) ? measuredS : gainS;
	} else if (cls == PROT_AA) {
		// On the perimeter, not the anchor: AA set no position at all, so
		// every battery landed on the start position.
		{
			AIFloat3 aat;
			if (RimGapSite(PROT_AA, aat))
				at = aat;
			// ...and the held line before the rim, once air has been seen
			// (the gate below), while nothing that shoots up covers it.
			if (lineUp && (Catalog::gMaxRange[d] > 1.f)
				&& !ProtCovered(PROT_AA, lineAt, Catalog::gMaxRange[d] * 0.8f))
				at = lineAt;
		}
		// AS SOON AS WE HAVE SEEN ANY (apexearth: "just make the AA if
		// we've seen enemy air... it doesn't have to be a ton"). Sized off
		// AirSeenEver, which has no AA_IGNORE floor and no freshness
		// window: a bomber that has flown home is still a bomber, and
		// AirThreatNow read zero for exactly the moments between raids.
		// OUR SHARE OF A SIDE-WIDE READING: the enemy census sums what the
		// whole team can see, and each of us covers our own base, so charging
		// one player the team's answer builds it once per ally. RoleTarget
		// already divides the same census on the mobile side.
		const float allies = Military::AllyCount();
		float air = Military::AirSeenEver()
				/ ((allies > 1.f) ? allies : 1.f);
		// The rear specialist is a FATTER TARGET than its share suggests:
		// it holds the team's economy, builds no ground defence, and keeps
		// no army over its base, so bombers that get past the front go
		// there. It carries a larger share of the same census, which the
		// saturation point below then turns into proportionally more AA.
		if (EcoRoleActive())
			air *= ai.GetTunable("apex_eco_aa_mult", TUNE_ECO_AA_MULT);
		if (Gate(GATE_AA_NOAIR, air <= 0.f))
			return false;
		// WHAT THE BOMBS ARE ACTUALLY COSTING US, priced like a turret:
		// the metal/s we are measurably losing to aircraft, times the
		// share of their air this tower newly stops. The old form was an
		// insurance rate on the base with a x4 urgency fudge bolted on,
		// which read ~1 metal/s while bombers ate the economy -- and it
		// lost every auction (apexearth, watched: "T1 anti air is very
		// cheap yet we still have not made it... I estimate a team cost
		// of around 250-300 would have saved us more than that").
		// AA metal counted against air metal at the cover ratio, so cover
		// reaches the target -- and the want prices itself out -- at
		// exactly apex_aa_cover_frac of our share of the air we have seen.
		// No count, no cap. Mobile AA over the base counts here too, so the
		// two AA budgets saturate against each other instead of both
		// answering the same bombers.
		float aaFrac = ai.GetTunable("apex_aa_cover_frac", TUNE_AA_COVER_FRAC);
		if (aaFrac < 0.01f)
			aaFrac = 0.01f;
		const float aaTrade = 1.f / aaFrac;
		float aaCover = MobileAACoverM() * aaTrade;
		for (uint ai2 = 0; ai2 < gProtDefId[PROT_AA].length(); ++ai2)
			aaCover += Catalog::gCostM[gProtDefId[PROT_AA][ai2]] * aaTrade;
		const float aaAdds = Catalog::gCostM[d] * aaTrade;
		float aShort0 = (air - aaCover) / air;
		if (aShort0 < 0.f)
			aShort0 = 0.f;
		float aShort1 = (air - (aaCover + aaAdds)) / air;
		if (aShort1 < 0.f)
			aShort1 = 0.f;
		const float stopped = aShort0 - aShort1;
		if (Gate(GATE_AA_SAT, stopped <= 0.f))
			return false;
		// THE SAME THREE TERMS AS A GROUND TURRET: what is at risk, how
		// often it gets hit, and the share this tower newly stops. AA used
		// an insurance rate on min(their air, our base), which capped the
		// value at risk by the SIZE of their air force -- and `stopped`
		// already measures our cover against exactly that force. That is
		// the double count ThreatM records and rejects on the ground side,
		// and it is why AA priced at gain=0.09 against energy's 4.75 and we
		// fielded exactly one Nettle per game however many bombers came.
		//
		// Turrets are excluded from the stake for the same reason
		// SiegeRiskAt excludes them: defence must not be its own reason.
		// Saturation is arithmetic -- every tower raises aaCover, which
		// lowers both the arrival rate and the next tower's share.
		float econA = gAssetsM - gProtM;
		if (econA < 0.f)
			econA = 0.f;
		const float horizA = ai.GetTunable("apex_exposed_loss_s", TUNE_EXPOSED_LOSS_S);
		const float anchorA = 1.f / ((horizA > 1.f) ? horizA : 120.f);
		const float airHz = anchorA * (air / (air + aaCover))
				* ai.GetTunable("apex_aa_urgency", TUNE_AA_URGENCY);
		float gainA = econA * airHz * stopped;
		// Measured losses are a FLOOR, not the whole price: they are what
		// air has already cost us, which arrives after the mex is dead.
		const float measured = Military::AirLossRate() * stopped;
		gain = (measured > gainA) ? measured : gainA;
	} else if (cls == PROT_TARGFAC) {
		// apexearth's spec: three wanted, diminishing.
		const int have = int(gProtPos[PROT_TARGFAC].length());
		const int want3 = int(ai.GetTunable("apex_targfac_want", TUNE_TARGFAC_WANT));
		if (Gate(GATE_TF_ENOUGH, have >= want3))
			return false;
		gain = gAssetsM * rate * float(want3 - have) / float(want3);
	}
	return true;
}

}  // namespace Market
