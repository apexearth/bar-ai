namespace Military {

// HOLDING MUST BE BOUNDED IN TIME.
//
// quota.attack is a MINIMUM attacker count before the engine will form an
// attack, and MassWant() pins it at MASS_CAP whenever the enemy out-values us
// by MASS_HOLD_RATIO -- a feedback trap where falling behind economically
// raises the bar to attack at all, so ground is never contested and the
// economy falls further behind. The hold itself stays (a trickle just dies for
// nothing) but gets a deadline: once pinned at the cap this long, fall back to
// MASS_FLOOR so something goes out and the ratio can change.
int gHoldSince = -1;
int gNextFeedLog = 0;

// The enemy mass we SIZE AGAINST, counted pessimistically: raw GetEnemyCost
// (no ghost discount) over every fighting role INCLUDING heavy and super,
// plus a discounted share of statics. The 0.3 ghost weight is right for the
// posture gates -- leaning defensive off dead units loses maps -- and wrong
// here: a mass seen once and now hidden is exactly the thing that kills our
// groups one by one, and reading their Korgoths as absent is the unsafe
// error (see EnemyFieldCost). apexearth: "We don't know how big they are
// until its too late because we can't see them all" -- unknown must not read
// as a small army, the same rule air already applies to unseen AA.
// Rolling peak of RECENTLY-SEEN fighting cost -- apexearth: "if we have
// seen 100 thugs in/out of fog over 90s but we've only ever seen at max 10
// at one time... the enemy army is probably sized around ~10." Distinct
// ids cycling through fog never double-count (verified in the registry),
// so the case this catches is distinct units DYING unseen while the raw
// count remembers them. The peak decays so a real army briefly hidden does not
// evaporate, but a peak from a fight we already won stops being evidence.
float gSeenPeak = 0.f;
int gSeenPeakFrame = 0;

float FreshMassingThreat()
{
	return aiEnemyMgr.GetEnemyCostFresh(RT::ASSAULT)
	     + aiEnemyMgr.GetEnemyCostFresh(RT::RAIDER)
	     + aiEnemyMgr.GetEnemyCostFresh(RT::RIOT)
	     + aiEnemyMgr.GetEnemyCostFresh(RT::SKIRM)
	     + aiEnemyMgr.GetEnemyCostFresh(RT::ARTY)
	     + aiEnemyMgr.GetEnemyCostFresh(RT::AH)
	     + aiEnemyMgr.GetEnemyCostFresh(RT::HEAVY)
	     + aiEnemyMgr.GetEnemyCostFresh(RT::SUPER);
}

float EnemyMassingThreat()
{
	const float fresh = FreshMassingThreat();
	if (fresh > gSeenPeak) {
		gSeenPeak = fresh;
	} else {
		// DECAY PER FRAME, NOT PER CALL. This is read from six places and
		// several times per update, so the old per-call 0.9999 decayed at a
		// rate set by how often other code happened to ask -- nowhere near the
		// half-life the comment above claimed. The peak is the denominator of
		// the killing blow, so a stale one is what keeps a won game from being
		// finished: kill their army and the bar to commit is still the biggest
		// force they ever showed.
		const float hl = ai.GetTunable("apex_seen_halflife", TUNE_SEEN_HALFLIFE);
		const int dt = ai.frame - gSeenPeakFrame;
		if ((hl > 0.f) && (dt > 0))
			gSeenPeak *= pow(0.5f, (float(dt) / float(SECOND)) / hl);
	}
	gSeenPeakFrame = ai.frame;
	float raw = aiEnemyMgr.GetEnemyCost(RT::ASSAULT)
	     + aiEnemyMgr.GetEnemyCost(RT::RAIDER)
	     + aiEnemyMgr.GetEnemyCost(RT::RIOT)
	     + aiEnemyMgr.GetEnemyCost(RT::SKIRM)
	     + aiEnemyMgr.GetEnemyCost(RT::ARTY)
	     + aiEnemyMgr.GetEnemyCost(RT::AH)
	     + aiEnemyMgr.GetEnemyCost(RT::HEAVY)
	     + aiEnemyMgr.GetEnemyCost(RT::SUPER)
	     + STATIC_DEFENSE_WEIGHT() * aiEnemyMgr.GetEnemyCost(RT::STATIC);
	// The sanity ceiling: a GENEROUS multiple of the most we ever saw at
	// once, never the estimate itself -- limited sensor coverage makes the
	// peak an undercount, and sizing on an undercount is the 2v6 regression.
	const float cap = gSeenPeak * ai.GetTunable("apex_seen_cap_mult", TUNE_SEEN_CAP_MULT);
	if ((gSeenPeak > 1.f) && (raw > cap))
		raw = cap;
	return raw;
}

// THE ARMY WE HAVE ALIVE, AGAINST THE ONE WALKING AT US. 0..1, 1 at parity or
// better. Every "can we afford this luxury" gate here used to ask Brain::ShareOf
// (cumulative metal SPENT on army), which stays high after the army it paid for
// is dead -- so the silo, the extra air lab and the escort floors all opened at
// the moment we were weakest. This asks what is standing instead.
//
// An unscouted enemy reads small, so a small estimate returns 1 and never damps
// anything -- ignorance is not safety, but it is also not evidence of danger.
float ArmyStandingRatio()
{
	const float theirs = EnemyMassingThreat();
	if (theirs <= 1.f)
		return 1.f;
	const float ours = TeamArmyCost();
	const float ratio = ours / theirs;
	return (ratio > 1.f) ? 1.f : ratio;
}

// Their field power outweighs our standing army. The bar is the one already
// calibrated for the constructor cap below it in facqueue.
bool Outmassed()
{
	// Stated as the comparison, not as 1/ratio: a tunable of 0 -- the obvious
	// way to switch this off -- divided to infinity and read as permanently
	// outmassed, and the ratio's clamp at 1 also swallowed multipliers below 1.
	const float theirs = EnemyMassingThreat();
	if (theirs <= 1.f)
		return false;
	return theirs > TeamArmyCost()
			* ai.GetTunable("apex_con_outmassed", TUNE_CON_OUTMASSED);
}

// The size a group commits at, from the armies on the field.
//
// CDefendTask is created with maxPower = minAttackers and stops accepting units
// once it reaches it, then promotes to an attack and leaves. So this number IS
// the size each group leaves at -- not a threshold it grows past.
// The biggest enemy group we can currently see, as POWER. Their groups are what
// our group actually walks into, so this is the honest size to match -- unlike
// their whole army, which answers "can we beat all of them" and is not the
// question a single attack asks.
float EnemyGroupPower()
{
	float top = 0.f;
	const int n = aiEnemyMgr.GetEnemyGroupCount();
	for (int i = 0; i < n; ++i) {
		const float c = aiEnemyMgr.GetEnemyGroupCost(i);
		if (c > top)
			top = c;
	}
	return top * 0.017f;   // Grunt-class power per metal, LogUnitPower
}

// ARE WE THE AGGRESSOR? apexearth 2026-08-19: "we can't be throwing [army] away
// to a superior force unless we know confidently we're putting most of our
// resources into army and *should* have a stronger army than our opponent. If
// we know we're being conservative then we shouldn't ever attack them if
// they're being aggressive."
//
// Two readings, both ours and both already measured: what share of our own
// metal has gone into army against what we intended to spend there, and what
// they field against what we field. Below our own army target while they
// out-field us means we chose economy and they chose offence -- the one case
// where walking out is giving away the only army we bought.
// MOBILE against MOBILE, shared by every "may the army leave home" gate.
// EnemyMassingThreat carries 0.5x their STATIC defence, and by mid-game more
// than half the figure was towers (census 2026-08-20: foeMass 3032 with
// foeStatic 3493) -- towers cannot walk at us, so counting them here held the
// army home against an enemy we outfielded. Static still counts fully in
// MassWant: walking INTO porc needs mass; refusing to leave home because
// porc exists does not.
float FoeMobileMassing()
{
	return EnemyMassingThreat()
		- (1.f - ai.GetTunable("apex_feed_static_w", TUNE_FEED_STATIC_W))
			* STATIC_DEFENSE_WEIGHT() * aiEnemyMgr.GetEnemyCost(RT::STATIC);
}

// TeamArmyCost read ~40% of the field telemetry (2026-08-20: 2054 against
// armyReal 5500); the withdraw register's live cost is the honest floor.
float OurArmyNow()
{
	const float ours = TeamArmyCost();
	return (gTrackedCost > ours) ? gTrackedCost : ours;
}

bool ConservativeStance()
{
	if (ai.GetTunable("apex_conservative_hold", TUNE_CONSERVATIVE_HOLD) <= 0.f)
		return false;
	if (Brain::gSpentTotal <= 1.f)
		return false;   // nothing spent yet: no stance to read
	const float share = Brain::ShareOf(Brain::ARMY);
	const float target = Brain::TargetShare(Brain::ARMY);
	if (share >= target)
		return false;   // we ARE buying army: our army is meant to be used
	const float ours = OurArmyNow();
	const float theirs = FoeMobileMassing();
	// WE CANNOT SEE THEM MOST OF THE TIME. apexearth: "there are a lot of times
	// in the game when we cannot see any enemy army" -- confirmed by logs where
	// enemyArmy read 0 for whole stretches. A reading far below our own army is
	// almost never "they have nothing"; it is "we are looking at fog", and
	// treating it as weakness is what sends the army out. Unknown holds, the
	// same rule EnemyMassingThreat's own pre-T2 parity clause applies.
	const float floorSeen = ours * ai.GetTunable("apex_unseen_hold", TUNE_UNSEEN_HOLD);
	// A low reading is fog ONLY if they have ever shown an army that size:
	// gSeenPeak is the most massing threat we ever saw at once (slow decay).
	// Without this, being 2x ahead was indistinguishable from being blind and
	// the hold tightened exactly as we pulled ahead (measured 2026-08-20:
	// "outmatched 2198 vs 4567" -- held while outfielding them two to one).
	if ((theirs < floorSeen) && (gSeenPeak > floorSeen))
		return true;
	return (theirs > ours) && (ours >= 0.f);
}

float MassWant()
{
	// Sized against what the group can actually kill, not against the enemy's
	// whole army: comparing to their total army answers "can we beat all of
	// them", but the objective is usually undefended economy, which only needs
	// enough to kill the extractor. Falling behind on army would otherwise raise
	// this demand and we never go, losing more ground.
	//
	// Safety is not given up, it moves to target selection: the attack task
	// refuses a target whose local defence outweighs the group (localInfl and
	// the strength test in CAttackTask::FindTarget), and target selection
	// prefers UNDEFENDED economy outright (FREE_ECO_PRIORITY). A floor-sized
	// group can go out and pick something it can actually kill.
	//
	// The floor is tunable and calibrated by LogUnitPower() below: quota.attack
	// is a POWER sum (CFighterTask: attackPower += cdef->GetPower()), not a
	// unit count or metal value, so it cannot be derived directly from a metal
	// figure.
	// ON by default since 2026-08-16: with it off every group committed at the
	// floor (~20% of our army) whatever the enemy massed, which is the "they
	// kill our smaller masses one by one" report, made twice.
	if (ai.GetTunable("apex_mass_vs_army", TUNE_MASS_VS_ARMY) <= 0.f)
		return MassFloor();

	const float ours = TeamArmyCost();
	float theirs = EnemyMassingThreat();
	// Pre-T2 the enemy model is mostly unscouted ground, and GetEnemyCost only
	// counts what has entered LOS -- "ahead" in the opening is usually
	// ignorance. Unknown must not read as zero: until T2 (when the radar net
	// exists and the model is real) assume a peer fields at least our own army
	// scaled by apex_unseen_parity, so opening groups commit at real size
	// instead of trickling across at the floor.
	if (!Factory::gHaveT2) {
		const float assumed = ours * ai.GetTunable("apex_unseen_parity", TUNE_UNSEEN_PARITY);
		if (theirs < assumed)
			theirs = assumed;
	}
	if (ours <= 1.f)
		return MASS_CAP();
	const float floorNow = MassFloor();
	// The ceiling scales with the floor: a flat MASS_CAP of 48 sits BELOW the
	// army-scaled floor past ~14k of standing army, which silently collapsed
	// the whole outmatched branch back to the floor. Against a bigger enemy
	// mass the group is a multiple of our normal share, not a constant.
	float capNow = floorNow * ai.GetTunable("apex_mass_cap_mult", TUNE_MASS_CAP_MULT);
	if (capNow < MASS_CAP())
		capNow = MASS_CAP();
	const float ratio = theirs / ours;
	// OUTMATCHED IS ABOUT THEM, NOT US. Floor and cap both scale with OUR
	// army, so losing a big fight collapsed the hold bar exactly when it
	// should be highest, and the survivors trickled out into the army that
	// had just won -- apexearth 2026-08-19: "why even bother leaving the base
	// AT ALL if we just lost a big fight and have very few units?" While they
	// out-mass us the bar is a share of THEIR army (Grunt-class
	// power-per-metal ~0.017), which holds the pool home until it is rebuilt
	// toward parity -- and releases by itself as it does.
	// Real units, not metal conversions: aiEnemyMgr.mobileThreat is the
	// engine's own aggregated threat of known mobile enemies, and the bar is
	// per PLAYER -- the whole enemy side's threat divided by our roster, or an
	// 8v8 sets a bar no single player's pool could ever fill (the measured
	// Fatboy-loiter trap).
	{
		float allies = 1.f;
		array<Id>@ roster = ai.GetTeamIds();
		if ((roster !is null) && (roster.length() > 0))
			allies = float(roster.length());
		const float foeBar = (aiEnemyMgr.mobileThreat / allies)
				* ai.GetTunable("apex_mass_vs_enemy", TUNE_MASS_VS_ENEMY);
		if ((ratio > 1.f) && (foeBar > capNow))
			capNow = foeBar;
	}
	// Bleeding on their ground also grows the group: the same caution signal
	// the engage margin uses, applied to how much leaves at once.
	const float bleed = BleedCaution();
	if (ratio <= ATTACK_EDGE())
		return floorNow * bleed;              // ahead: move, but as a group
	if (ratio >= MASS_HOLD_RATIO())
		return capNow;                        // outmatched: hold
	const float t = (ratio - ATTACK_EDGE()) / (MASS_HOLD_RATIO() - ATTACK_EDGE());
	return (floorNow + t * (capNow - floorNow)) * bleed;
}

// The floor scales with our own army: a fixed 12-power squad is a real group
// over a 2k-metal army and a suicide trickle over 100k. Sized as a share of
// standing army value, converted at Grunt-class power-per-metal (~0.017,
// LogUnitPower); floored at the old constant so the opening is unchanged.
// apexearth 2026-08-15: the squad minimum scales with economy/army, not flat.
float gQuotaConfig = -1.f;   // behaviour.json's quota.attack, read once at start

float MassFloor()
{
	if (gQuotaConfig < 0.f)
		gQuotaConfig = aiMilitaryMgr.quota.attack;
	// NO FLAT OPENING MINIMUM. The config's 60 exceeded the whole army until
	// ~3.5k metal, so no pool could legitimately promote in the opening and
	// every early attack was born through the any-attack-exists bypass as a
	// solo -- measured 2026-08-17, first-10m squad avg 1.3 vs enemy 2.6.
	// apexearth: "sizing needs to be dynamic based on what we have." The share
	// of standing army below is the size; the tunable is only a degenerate-case
	// guard (~2 Pawns) for an army of nearly nothing.
	float base = ai.GetTunable("apex_mass_floor", TUNE_MASS_FLOOR);
	// OWN army, not TeamArmyCost: the promotion quota this feeds is per
	// PLAYER, and scaling it by the whole ally side's army in an 8v8 set a
	// bar no single player's pool could fill -- measured live as Fatboys
	// loitering at the home guard anchor all late game, waiting to promote.
	// 0.006 is ~35% of standing army metal per group at Grunt-class
	// power-per-metal. Was 0.0017 (~10%), then 0.0035 (~20%) 2026-08-15 --
	// apexearth has now said twice that the enemy masses bigger and kills our
	// smaller groups one by one, so the share rises again; the ratio branch in
	// MassWant() above is what scales it further when they actually out-mass us.
	// ~70% of OWN standing army per group (0.012 metal->power at Grunt-class
	// 0.017): one force that can win the fight it meets, not two that each
	// lose it. Was 0.006 (~35%) -- measured 2026-08-17 with the solo-stream
	// fixed, first-10m groups still averaged 1.5 units against the enemy's
	// 2.3 with 8-stacks; the share was the remaining term.
	const float scaled = aiMilitaryMgr.armyCost
			* ai.GetTunable("apex_mass_per_army", TUNE_MASS_PER_ARMY);
	float want = (scaled > base) ? scaled : base;
	// THE FLOOR MUST NOT FOLLOW OUR ARMY DOWN.
	//
	// A share of OUR standing army is a death spiral once we are losing: the
	// army dies, the floor falls, smaller groups leave, they die faster, the
	// floor falls further. Measured in the 4v4 of 2026-08-19: army 570 against
	// 104,580, floor collapsed to 5 (one or two units), our squads n=0 against
	// their 11 averaging 8.4. Nothing in the loop pushed back.
	//
	// So the floor is also bounded below by what we would actually MEET -- the
	// biggest enemy group we can see, at the same power-per-metal the rest of
	// this file uses. If we cannot reach that, the answer is to not go, which
	// is what the pool does on its own.
	const float meet = EnemyGroupPower()
			* ai.GetTunable("apex_mass_meet_frac", TUNE_MASS_MEET_FRAC);
	if (meet > want)
		want = meet;
	return want;
}

void UpdateMassing()
{
	LogUnitPower();
	// The killing blow owns the quota once it is on: massing is what was holding
	// the win up, so re-raising the minimum here would undo it every tick.
	if (gKilling)
		return;
	if (gTurtle)
		return;   // an active hold is stricter; do not loosen it

	// TEAM against team: aiMilitaryMgr.armyCost is THIS player's army while
	// EnemyArmyCost() sums every enemy, so comparing them directly on a 4v4 is
	// one player against four and reads far too pessimistic. TeamArmyCost()
	// sums the ally side over TV_ARMY, the same figure the killing blow uses.
	const float ours = TeamArmyCost();
	const float theirs = EnemyMassingThreat();
	float want = MassWant();

	// Bound the hold. MassWant returns MASS_CAP only in the outmatched case, so
	// that is the signal we are holding rather than committing.
	const float holdSecs = ai.GetTunable("apex_mass_hold_secs", TUNE_MASS_HOLD_SECS);
	// Keyed on "demanding more than the floor", not on reaching the cap: the
	// interpolated want can sit just under MASS_HOLD_RATIO and never touch
	// MASS_CAP, so a deadline keyed on the cap would never fire.
	const float floorNow = MassFloor();
	// THE DEADLINE MUST NOT FIRE INTO AN ARMY WE CANNOT FIGHT.
	//
	// It exists so a hold cannot last forever "so the ratio can change". At the
	// ratios actually measured (183:1 in the 4v4 of 2026-08-19) the ratio cannot
	// change -- it fired 55 times in one game and each firing was a group handed
	// to them. Holding forever is strictly better than feeding; the outmatched
	// branch already releases by itself as the pool rebuilds toward parity.
	// See FoeMobileMassing/OurArmyNow: mobile against mobile, honest self-count.
	// A MAP-WIDE COMPARISON IS NOT THE FIGHT IN FRONT OF US. Both terms are
	// side-wide sums, so a group standing on a weakly-held enemy base reads
	// "outmatched" from armies on the far side of the map and circles instead
	// of taking it (apexearth 2026-08-21: "we just had the ability to take out
	// an enemy base... instead we walked around in circles nearby for two or
	// three minutes until the enemy came, surrounded us, and killed us"). If
	// our massed pool locally outweighs what is actually defending the ground
	// it stands on, the suppression does not apply -- that is the definition
	// of a fight we are winning.
	bool localEdge = false;
	if (ai.GetTunable("apex_local_edge_on", TUNE_LOCAL_EDGE_ON) > 0.f) {
		const AIFloat3 at = gLaneAt;
		if (OnMap(at)) {
			// What is actually defending the ground we stand on: enemy group
			// value within reach of the lane, not every enemy on the map.
			const float r = ai.GetTunable("apex_local_edge_r", TUNE_LOCAL_EDGE_R);
			const float r2 = r * r;
			float foeHere = 0.f;
			const int nG = aiEnemyMgr.GetEnemyGroupCount();
			for (int i = 0; i < nG; ++i) {
				const AIFloat3 gp = aiEnemyMgr.GetEnemyGroupPos(i);
				if (OnMap(gp) && (gp.SqDistance2D(at) <= r2))
					foeHere += aiEnemyMgr.GetEnemyGroupCost(i);
			}
			const float oursNow = OurArmyNow();
			localEdge = (oursNow > 1.f)
				&& (oursNow > foeHere
					* ai.GetTunable("apex_local_edge", TUNE_LOCAL_EDGE));
		}
	}
	const bool feeding = !localEdge
			&& (ConservativeStance()
				|| (FoeMobileMassing() > OurArmyNow()
					* ai.GetTunable("apex_mass_no_commit_ratio", TUNE_MASS_NO_COMMIT_RATIO)));
	if (feeding && (gHoldSince >= 0) && (ai.frame >= gNextFeedLog)) {
		gNextFeedLog = ai.frame + 60 * SECOND;
		AiLog(Factory::T() + "apex: hold deadline suppressed -- outmatched "
			+ formatFloat(FoeMobileMassing(), "", 0, 0) + " vs "
			+ formatFloat(OurArmyNow(), "", 0, 0)
			+ (ConservativeStance() ? ", and we are not the aggressor" : ""));
	}
	if (want > floorNow + 1.f) {
		if (gHoldSince < 0)
			gHoldSince = ai.frame;
		if (!feeding && (holdSecs > 0.f) && (ai.frame - gHoldSince > int(holdSecs) * SECOND)) {
			// Commit partway toward the cap, NOT at the floor: expiring straight
			// to the floor sent a 20%-of-army group into the exact mass we had
			// been refusing to fight -- the one-by-one deaths again, on a timer.
			want = floorNow + ai.GetTunable("apex_mass_commit_frac", TUNE_MASS_COMMIT_FRAC)
					* (want - floorNow);
			gHoldSince = ai.frame;   // restart, so we alternate hold and commit
			AiLog(Factory::T() + "apex: mass hold expired, committing at "
				+ formatFloat(want, "", 0, 0));
		}
	} else {
		gHoldSince = -1;
	}

	if (ai.frame >= gNextMassLog) {
		gNextMassLog = ai.frame + 60 * SECOND;
		AiLog(Factory::T() + "apex: mass want=" + formatFloat(want, "", 0, 0)
			+ " floor=" + formatFloat(floorNow, "", 0, 0)
			+ " army=" + formatFloat(ours, "", 0, 0)
			+ " enemyArmy=" + formatFloat(theirs, "", 0, 0)
			+ " ratio=" + formatFloat((ours > 0.f) ? theirs / ours : 0.f, "", 0, 2));
		// HOW BIG "HOME GROUND" IS: CAttackTask's isHome waives the odds check
		// wherever net influence >= INFL_SAFE (2.0). Walk the home->enemy axis
		// and log where that isoline actually ends, against the full distance,
		// so the exemption's reach is a measured number and not a guess.
		if (Builder::gHomeSet) {
			const AIFloat3 foe = aiEnemyMgr.GetEnemyPos();
			const float total = Builder::gHomePos.distance2D(foe);
			if ((total > 1.f) && OnMap(foe)) {
				float safeDist = 0.f;
				for (float d = 200.f; d < total; d += 200.f) {
					AIFloat3 p = Builder::gHomePos + (foe - Builder::gHomePos) * (d / total);
					if (!OnMap(p) || (ai.GetAllyInflAt(p) - ai.GetEnemyInflAt(p) < 2.f))
						break;
					safeDist = d;
				}
				AiLog(Factory::T() + "apex: home-edge safe=" + int(safeDist)
					+ " of " + int(total) + " ("
					+ formatFloat(100.f * safeDist / total, "", 0, 0) + "%)");
			}
		}
	}
	// Tracks the want BOTH ways: with an army-scaled floor, a ratchet that only
	// rises would leave the bar stuck at a dead army's size -- a side that just
	// lost 30k of army could never form another attack. gKilling/gTurtle return
	// early above, so nothing else owns the quota while this writes it.
	aiMilitaryMgr.quota.attack = want;
}

//------------------------------------------------------------------------------
// KILLING BLOW: once clearly winning, stop waiting for a bigger army.
//
// UpdateMassing walks quota.attack up to MASS_CAP and pins it there outright
// whenever the enemy out-values us. Once we are far ahead that gate is pure
// delay: we hold an army several times their size and keep waiting for a
// bigger one. So when clearly winning, drop the minimum so attacks form
// continuously and release the turtle if it is holding -- conditional on
// holding KILL_EDGE times the enemy's army value, so even a partial commitment
// outnumbers everything they can field. Lowering minAttackers globally is known
// to be catastrophic; this only lowers it once we are already dominant.
float KILL_EDGE() { return ai.GetTunable("apex_kill_edge", TUNE_KILL_EDGE); }
float KILL_FLOOR() { return ai.GetTunable("apex_kill_floor", TUNE_KILL_FLOOR); }
bool gKilling = false;

// Our whole side's army value, pooled over the same blackboard the tech lead
// election uses. Has to be TEAM against TEAM: aiMilitaryMgr.armyCost is one
// player's army while EnemyArmyCost() sums the entire enemy side, so a direct
// comparison asks "is one of us worth more than all of them" and is
// unreachable by construction.
const string TV_ARMY = "army";

}  // namespace Military

// One-off calibration: quota.attack is a POWER SUM (CFighterTask::attackPower
// += cdef->GetPower()), not a unit count, so MASS_FLOOR cannot be set without
// knowing what a unit is worth. Logs a few representative units' power once.
bool gPowerLogged = false;
void LogUnitPower()
{
	if (gPowerLogged || (ai.frame < 30 * SECOND))
		return;
	gPowerLogged = true;
	array<string> names = {"armpw", "armrock", "armwar", "corak", "corthud", "armzeus", "armjeth",
	                       "armbanth", "corkorg", "corshiva", "armmanni"};
	string msg = "apex: unit power --";
	for (uint i = 0; i < names.length(); ++i) {
		CCircuitDef@ d = ai.GetCircuitDef(names[i]);
		if (d !is null)
			msg += " " + names[i] + "=" + formatFloat(d.power, "", 0, 1);
	}
	AiLog(msg);
}
