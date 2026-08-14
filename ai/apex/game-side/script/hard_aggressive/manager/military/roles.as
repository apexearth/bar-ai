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
// any turtle hold are over. Not gAttackBase: that is stock BARb's config value
// (15 in a live multiplayer game), which caps only fifteen units per player at
// attacking and fills first-come, so a T3 unit finished later never gets a
// slot. Set well above any realistic standing army so the quota stops deciding
// and the engage test (which looks at the odds) decides instead.
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
	//
	// Solo has no one to rush for: the rusher trades its own army for the
	// team's tech, and a quota of 400 means never attacking. With no allies
	// that is a player who neither fights nor is covered by anyone.
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

// The eco lead as the team's bank: it is measurably the richest player on the
// team and the one least able to use metal in a hurry, so when someone else is
// in trouble the metal is worth more in their hands than banked in ours.
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

	// Stop while the lead is at cap: metal banked above storage is wasted while
	// the givers run empty and stop expanding.
	if (Factory::LeadIsSaturated(lead))
		return;

	// Do not feed someone already banking metal -- that just moves waste around;
	// only sling while the lead is actually spending everything.
	// ai.GetTeamMetalFill() reports 1.0 unconditionally (the engine does not
	// expose another team's storage to us), so the fallback read "unknown" as
	// "full" and withheld every transfer. Dropped; the feeder already only gives
	// away what it holds above SLING_KEEP, so it cannot starve itself.
	// Over half full while the lead is still paying for its plant, send the
	// whole excess rather than trickling a lump -- that metal is doing nothing
	// and the lead is the only thing the team is waiting on.
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
// army. A low value attacks with whatever is to hand and feeds units into
// fights piecemeal, which grinds an army down without ever threatening
// anything. Lowering minAttackers globally is known to be catastrophic
// (15 -> 6 scored 0-10); this file's values move the other way.
//
// quota.attack is a POWER sum (CAttackTask's minPower), not a unit count and
// not metal -- armyCost/EnemyArmyCost() are metal, so only the dimensionless
// ratio theirs/ours bridges the two; the output stays in quota units. A Grunt
// is ~0.9 power, so MASS_FLOOR of 12 is roughly 13 Grunts or 8 Thugs: a real
// group, not a trickle.
const float MASS_FLOOR  = 12.f;   // even when ahead, never trickle 2-3 units
// Ratio at or above which we stop attacking and let them come to the defences.
const float MASS_HOLD_RATIO = 1.5f;
const float MASS_CAP    = 48.f;
// A metal-vs-metal ratio, so 1.0 is a real parity point. EnemyArmyCost() sums
// GetEnemyCost over the fighting roles, the same unit as armyCost -- not
// aiEnemyMgr.mobileThreat, which is a different scale and never approaches 1.
const float ATTACK_EDGE = 0.95f;
int gNextMassLog = 0;

// EnemyArmyCost() sums only the mobile fighting roles, so a defended
// chokepoint reads identically to open ground as long as mobile counts match
// -- static defence is otherwise invisible to the massing decision.
//
// Weighted at half, not 1:1: a turret is a sunk cost with no upkeep, cannot
// retreat or redeploy, and only threatens the ground it covers, unlike a
// mobile unit of the same value. Folding it in at full weight would let a
// static-heavy base pin quota.attack at MASS_CAP for the rest of the game, so
// this is scoped to MassWant()/UpdateMassing() only -- KillingBlow() and
// T3Worthwhile(), which read EnemyArmyCost() directly, are unaffected, and the
// killing-blow override still bypasses this once we are dominant.
const float STATIC_DEFENSE_WEIGHT = 0.5f;

}  // namespace Military
