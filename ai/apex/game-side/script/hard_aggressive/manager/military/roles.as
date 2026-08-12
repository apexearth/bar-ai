namespace Military {

float RushAttackQuota()
{
	array<Id>@ mates = ai.GetTeamIds();
	const uint size = (mates is null) ? 1 : mates.length();
	return (size >= 6) ? RUSH_SKIP_T1_BIG : RUSH_SKIP_T1_SMALL;
}

// While the team is paying for one player's tech, everyone else is deliberately
// poorer than the enemy and should not be picking fights on those terms. Hold,
// let static defence do the trading, and stall until the T2 lands -- then the
// tech advantage decides the game instead of a T1 fight we funded ourselves out
// of. Followers only; the rusher has its own, stricter quota.
//
// Deliberately not the full turtle value (400 = never attack). Sitting entirely
// passive hands the enemy the map, and the map is where the reclaim is. This is
// "defend and stall", not "do nothing".
const float RUSH_TEAM_DEFEND = 60.f;

// The attack quota to hold for the REST of the game, once the rush window and
// any turtle hold are over. Not gAttackBase: that is stock BARb's value, read
// off the config at startup, and in apexearth's live multiplayer game it was
// 15 -- so from mid-game on, only fifteen units per player were ever allowed to
// attack and everything above that stood in the base. apexearth, watching that
// game: "our units don't attack enough... i see a lot of our T3 units just
// hangin out and not fighting", and separately "we aren't aggressive enough vs
// humans early on".
//
// A cap that low also wastes the expensive end of the army first: the fifteen
// slots fill with whatever exists when the window opens, and a T3 unit finished
// afterwards simply never gets one. Set well above any realistic standing army
// so the quota stops being the thing that decides, and the engage test (which
// actually looks at the odds) decides instead.
const float LATE_ATTACK_QUOTA = 200.f;

bool gRushDefenceHeld = false;

void UpdateRushDefence()
{
	if (ai.frame > RUSH_GIVEUP) {
		// Hand the follower quota back too, or "give up on the strategy" leaves
		// everyone still holding its passive value. Only if nothing else has
		// since claimed the field -- a turtle hold or a massing target outranks
		// this and must not be clobbered.
		if (gRushDefenceHeld) {
			gRushDefenceHeld = false;
			if (aiMilitaryMgr.quota.attack == RUSH_TEAM_DEFEND) {
				aiMilitaryMgr.quota.attack = LATE_ATTACK_QUOTA;
				AiLog(Factory::T() + "apex: rush over, attack quota -> " + LATE_ATTACK_QUOTA);
			}
		}
		return;
	}
	if (ai.frame < SLING_FROM)
		return;
	if (Factory::IsDesignatedLead())
		return;          // the lead is handled by UpdateRushRole
	if (gTurtle)
		return;          // an active turtle hold is stricter; do not loosen it
	if (aiMilitaryMgr.quota.attack < RUSH_TEAM_DEFEND) {
		aiMilitaryMgr.quota.attack = RUSH_TEAM_DEFEND;
		gRushDefenceHeld = true;
	}
}

// Set while we hold the rusher's attack quota, so it can be handed back.
bool gRushQuotaHeld = false;

void UpdateRushRole()
{
	// Past the deadline this must still run, to hand the quota back. Returning
	// early instead left the lead pinned at RushAttackQuota() -- 400, i.e. never
	// attack -- for the entire rest of the game.
	// SOLO HAS NO ONE TO RUSH FOR. The rusher trades its own army for the
	// team's tech, and its quota of 400 means "never attack". With no allies
	// that is a player that neither fights nor is covered by anyone -- observed
	// live in a 1v1: "designated T2 rusher -- skipping T1 army until 15m".
	array<Id>@ roster = ai.GetTeamIds();
	const bool haveTeam = (roster !is null) && (roster.length() > 1);
	if (!haveTeam || (ai.frame > RUSH_GIVEUP) || !Factory::IsDesignatedLead()) {
		// The role can move -- before the election lands this falls back to the
		// engine's pick, usually a different team. quota.attack was assigned and
		// never undone, so a team that was briefly the rusher kept the
		// do-not-attack quota all game (measured: lowest army on its team by 4x).
		if (gRushQuotaHeld) {
			gRushQuotaHeld = false;
			// LATE_ATTACK_QUOTA, not the stock value: see its comment -- stock
			// is 15 here and that cap, not the odds, was deciding who fought.
			aiMilitaryMgr.quota.attack = LATE_ATTACK_QUOTA;
			AiLog(Factory::T() + "apex: rusher role released, attack quota -> "
				+ aiMilitaryMgr.quota.attack);
		}
		return;
	}
	if (gRushLoggedFor != ai.teamId) {
		gRushLoggedFor = ai.teamId;
		AiLog(Factory::T() + "apex: designated T2 rusher -- skipping T1 army until " + (RUSH_GIVEUP / MINUTE) + "m");
	}
	gRushQuotaHeld = true;
	aiMilitaryMgr.quota.attack = RushAttackQuota();
}

// The eco lead as the team's bank.
//
// apexearth: "if allies are hurting or we see our army losing it could share
// metal to teammates. It can also share a fus or afus to help them." This is the
// other half of the role -- it is measurably the richest player on the team
// (+59% metal produced over its teammates) and the one least able to use metal
// in a hurry, so when someone else is in trouble the metal is worth more in
// their hands than banked in ours.
//
// Deliberately keyed on IsEcoLead(), NOT EcoLeadActive(): an ally dying is one
// of the conditions that STANDS THE ROLE DOWN, so gating aid on the role being
// active would mean it could never pay out at exactly the moment it should.
const int   ECO_AID_PERIOD  = 5 * SECOND;
const float ECO_AID_KEEP    = 0.25f;    // share of storage kept as working float
const float ECO_AID_LUMP    = 1000.f;   // cap per transfer
const int   ECO_FUSION_GAP  = 2 * MINUTE;
int gNextEcoAid = 0;
int gNextEcoFusion = 0;
float gEcoAidTotal = 0.f;

void UpdateEcoAid()
{
	if (!Factory::IsEcoLead() || (ai.frame < gNextEcoAid))
		return;

	const int dying = Factory::NeediestAlly();
	const bool pressed = (dying >= 0) || gTurtle || LosingGround();
	if (!pressed)
		return;
	gNextEcoAid = ai.frame + ECO_AID_PERIOD;

	const int to = (dying >= 0) ? dying : Factory::LowestHoldAlly();
	if (to < 0)
		return;

	// A reactor outlives any amount of metal, so it goes first -- but only to
	// someone actually being killed, and never down to our own last two.
	if ((dying >= 0) && (ai.frame >= gNextEcoFusion)) {
		if (Builder::GiveFusion(dying))
			gNextEcoFusion = ai.frame + ECO_FUSION_GAP;
	}

	const float spare = aiEconomyMgr.metal.current
		- (aiEconomyMgr.metal.storage * ECO_AID_KEEP);
	if (spare <= 0.f)
		return;
	const float amount = (spare < ECO_AID_LUMP) ? spare : ECO_AID_LUMP;
	ai.SendResources(amount, 0.f, to);
	gEcoAidTotal += amount;
	if (gEcoAidTotal < amount + 1.f)   // first payment only
		AiLog(Factory::T() + "apex: eco lead aiding team " + to
			+ (dying >= 0 ? " (dying)" : " (team under pressure)"));
}

// Set while we hold the ECO lead's attack quota, so it can be handed back.
bool gEcoQuotaHeld = false;

// The eco lead keeps whatever army it has at home for the whole game.
//
// UpdateRushRole hands its quota back at RUSH_GIVEUP, which is right for a tech
// rush -- the bet has either landed or lost by then. The eco role is a bet on
// the LATE game, so expiring at fifteen minutes would remove it exactly where it
// was meant to pay. Runs after UpdateRushRole so it wins on the frames both
// apply, and after UpdateMassing, which only ever raises the quota.
void UpdateEcoRole()
{
	if (!Factory::EcoLeadActive()) {
		if (gEcoQuotaHeld) {
			gEcoQuotaHeld = false;
			// Not while turtling: the hold set 400 for its own reasons and
			// restoring the baseline here would quietly cancel it.
			if (!gTurtle) {
				aiMilitaryMgr.quota.attack = LATE_ATTACK_QUOTA;
				AiLog(Factory::T() + "apex: eco lead released, attack quota -> "
					+ aiMilitaryMgr.quota.attack);
			}
		}
		return;
	}
	gEcoQuotaHeld = true;
	aiMilitaryMgr.quota.attack = RUSH_SKIP_T1_BIG;
}

void UpdateSling()
{
	// Nothing to pool in the first half-minute, and the engine has not settled
	// team ids that early either.
	if ((ai.frame < SLING_FROM) || (ai.frame > RUSH_GIVEUP) || (ai.frame < gSlingNext))
		return;
	// Small amounts need a short period or the trickle is worthless: at 20-30
	// metal a transfer, ten seconds apart is 2-3 metal/s.
	gSlingNext = ai.frame + 3 * SECOND;

	if (Builder::gGotAdvCon)
		return;   // we already got our advanced con; the pooling is done
	if (!Factory::LeadIsDesignated())
		return;   // nobody has earned the role yet -- do not feed the fallback
	const int lead = Factory::RushLeadTeamId();
	if (lead == ai.teamId)
		return;                        // the lead is the one being fed

	if (lead < 0)
		return;

	// Stop once the plant we were funding exists. The window used to run to a
	// flat RUSH_GIVEUP clock, so donations continued long after the thing they
	// paid for was standing.
	if (Factory::LeadHasPlant(lead))
		return;

	// Stop while the lead is at cap. Measured 2026-08-02: ~269,000 metal went
	// into a lead whose bank sat above storage from minute 8 -- every point of
	// it wasted, while the givers ran empty and stopped expanding.
	if (Factory::LeadIsSaturated(lead))
		return;

	// Do not feed someone who is already banking metal -- that is just moving
	// waste around. Only sling while the lead is actually spending everything.
	// ai.GetTeamMetalFill() reports 1.0 unconditionally: the engine does not
	// expose another team's storage to us, so the C++ fallback read "unknown" as
	// "full" and withheld every single transfer -- slinging never once fired in
	// any test tonight. Observed live: it logged fill=1 while the lead sat under
	// half metal. Drop the dependency; the feeder already only gives away what
	// it holds above SLING_KEEP, so it cannot starve itself.
	// Over half full while the lead is still paying for its plant: that metal is
	// doing nothing, and the lead is the only thing the team is waiting on. Send
	// the whole excess instead of trickling a lump -- observed live, a follower
	// sat on a full bank at 9 min while the plant crawled to 75%.
	const float store = aiEconomyMgr.metal.storage;
	const float flood = store * SLING_FLOOD_FRAC;
	float amount = 0.f;
	if ((store > 0.f) && (aiEconomyMgr.metal.current > flood)) {
		amount = aiEconomyMgr.metal.current - flood;
	} else {
		const float spare = aiEconomyMgr.metal.current - SLING_KEEP;
		if (spare <= 0.f)
			return;
		// Otherwise a lump big enough to buy the T2 constructor, rather than
		// dribbling amounts that get spent on T1.
		amount = (spare < SLING_LUMP) ? spare : SLING_LUMP;
	}
	ai.SendResources(amount, 0.f, lead);
	gSlingTotal += amount;
	if (gSlingSent++ % 40 == 0)
		AiLog(Factory::T() + "apex: sent " + formatFloat(amount, "", 0, 0)
			+ " to lead " + lead + " (total " + formatFloat(gSlingTotal, "", 0, 0) + ")");
}

// Attack in a mass, not a trickle.
//
// quota.attack is a MINIMUM: the AI will not launch until it has that much
// army. Stock sits low, so it attacks with whatever happens to be to hand and
// feeds units into fights piecemeal -- which is exactly how an army gets ground
// down without ever threatening anything. apexearth: "store up an army until
// it's a really nice size and then attack with a big mass".
//
// The threshold grows with the game rather than being one number: a 12-unit
// push is a real threat at 8 minutes and an irrelevance at 25, when the enemy
// fields T2 and T3. Growing it also means the accumulated mass keeps pace with
// what it has to break through.
//
// Direction matters and is already measured: lowering minAttackers 15 -> 6 was
// catastrophic (0-10). This moves the other way.
// Timeline of eleven LOST games, sampled every 2 game-minutes: apex and stock
// are level on army and metal through minute 8, then diverge hard -- army 10.4k
// vs 15.9k at ten minutes, 9.9k vs 22.4k at fourteen. And apex's army PEAKS
// at minute 4 and declines from there (11.8k -> 9.9k -> 7.0k) while stock's
// grows continuously. We stop replacing losses exactly as the T2 transition
// begins, and never recover.
//
// Massing started at 8 minutes, precisely where the divergence begins: holding
// units back during the transition, when the army is already shrinking, compounds
// it. Push it past the transition so the force is rebuilt first and massed after.
// How much army we insist on before committing, driven by the armies on the
// field rather than by a clock.
//
// apexearth: "can you make massing based on how large the armies are? doesn't
// seem like it should be a time based thing. In fact, usually doing things by
// time is wrong." The clock version started at 14 minutes; measured 2026-08-02,
// apex and stock are indistinguishable through minute 4 and apex collapses at
// minute 6, so the gate arrived eight minutes after the bleeding started. Its
// first sample read "army=820 enemyArmy=11973 ratio=14.60".
//
// UNITS. quota.attack is CAttackTask's minPower, in the engine's power units.
// armyCost and EnemyArmyCost() are metal. Observed together in one line:
// want=48, army=820, enemyArmy=11973 -- three different scales. They must never
// be assigned or compared across. Only the RATIO theirs/ours is dimensionless,
// so that is the sole bridge used here; the output stays in quota units and
// inside the range below that is already known to work.
// POWER, not units: a Grunt is 0.9, so 30 demanded ~33 of them before any attack
// would form at all -- and apexearth's own figure, quoted in MassWant above, is
// "~10 grunts". 12 is roughly 13 Grunts or 8 Thugs: a real group, not a trickle,
// and reachable. At 30 the army regrouped and never went. apexearth, watching:
// "we will lose this game because we keep moving our army towards the back of
// the base... our regrouping behavior makes it so we never are able to push."
const float MASS_FLOOR  = 12.f;   // even when ahead, never trickle 2-3 units
// Ratio at or above which we stop attacking and let them come to the defences.
const float MASS_HOLD_RATIO = 1.5f;
const float MASS_CAP    = 48.f;
// Now a metal-vs-metal ratio, so 1.0 is a real parity point. It used to compare
// aiEnemyMgr.mobileThreat against armyCost; across eight 4v4 infologs that ratio
// logged 0.02-0.14 and never once approached 0.95, so the clause below could not
// fire and "refuse bad trades" did nothing all game. EnemyArmyCost() sums
// GetEnemyCost over the fighting roles, which is the same unit as armyCost.
const float ATTACK_EDGE = 0.95f;
int gNextMassLog = 0;

// EnemyArmyCost() sums only the mobile fighting roles (its own comment says
// "the enemy's MOBILE army"), so a defended chokepoint -- several turrets --
// reads identically to open ground as long as mobile counts match. apexearth,
// watching: "we do something in the early game which is running into enemy
// towers ... I've seen us lose ~10 army to a single tower." Confirmed in
// matches/watch-comet-catcher-4v4-8/infolog.txt: "mass want=30 army=4250
// enemyArmy=4072 ratio=0.96" at 10.0min, then armyReal 4250 -> 0 by 11.5min --
// the ratio said "even fight, go," and the enemy's static defence was invisible
// to it the whole time.
//
// Weighted at half, not 1:1 with EnemyArmyCost(): a turret is a sunk cost with
// no upkeep, cannot retreat or redeploy, and only threatens the ground it
// covers, unlike a mobile unit of the same value which threatens everywhere
// and is continuously replaced. Folding it in at full weight would let a
// static-heavy base pin quota.attack at MASS_CAP for the rest of the game
// (EnemyArmyCost() only ever grows once a wall is up); this is scoped to
// MassWant()/UpdateMassing() only, not EnemyArmyCost() itself, so
// KillingBlow() and T3Worthwhile() -- which read EnemyArmyCost() directly --
// are unaffected, and the killing-blow override (gKilling, above) still bypasses
// this entirely once we are dominant. Unweighted, unmeasured constant; retune
// from a watched game rather than a benchmark tournament, per the T3-worthwhile
// income lesson above -- turret density is a map/base-layout property a
// standard-scale benchmark may not reproduce at all.
const float STATIC_DEFENSE_WEIGHT = 0.5f;

}  // namespace Military
