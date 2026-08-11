namespace Military {

int gNextFenceCapLog = 0;

string armanni("armanni");
string cordoom("cordoom");
string legbastion("legbastion");

CCircuitDef@ BigGun()
{
	return SideDef3(armanni, cordoom, legbastion);
}

// The big gun used to hang off the T3 gantry's build chain, so it was placed
// beside whichever base owned the gantry -- a back-line player walling its own
// empty base while the front player got nothing. Same unit, same trigger, but
// put it where the fighting is.
const float BIGGUN_INCOME = 18.f;
bool gBigGunPlaced = false;

void UpdateFrontGun()
{
	if (gBigGunPlaced || !Factory::gHaveT3)
		return;
	if (aiEconomyMgr.metal.income <= BIGGUN_INCOME)
		return;
	CCircuitDef@ gun = BigGun();
	if (gun is null)
		return;
	AIFloat3 front;
	if (!BorderPos(front, 0) && !FrontPos(front))
		return;
	gBigGunPlaced = true;
	AiLog(Factory::T() + "apex: big gun " + gun.GetName() + " at the territory edge");
	// BUNKER takes only a def and a position -- no target, no spot id.
	aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::BUNKER,
			Task::Priority::NORMAL, gun, front, 0.f));
}

// Is this cluster near the gadget-published front? A second opinion alongside
// OnBorder, and only available in this harness -- dev_team_income.lua publishes
// it and does not exist in a hosted game.
const float FRONT_RADIUS = 1600.f;

bool NearFront(const AIFloat3& in pos)
{
	AIFloat3 f;
	if (!FrontPos(f))
		return false;
	const float dx = pos.x - f.x;
	const float dz = pos.z - f.z;
	return (dx * dx + dz * dz) < (FRONT_RADIUS * FRONT_RADIUS);
}

void AiMakeDefence(int cluster, const AIFloat3& in pos)
{
	if (!ApexActive()) {
		aiMilitaryMgr.DefaultMakeDefence(cluster, pos);
		return;
	}

	NoteSite(cluster, pos);

	if (gTurtle) {
		aiMilitaryMgr.DefaultMakeDefence(cluster, pos);  // porc hard while holding
		return;
	}

	const float armyFloor = EnemyArmyFloor();
	const float threat = aiEnemyMgr.mobileThreat;
	if (gPorcArmed ? (threat < armyFloor * PORC_RELEASE) : (threat >= armyFloor)) {
		gPorcArmed = !gPorcArmed;
		AiLog(Factory::T() + "apex: porc " + (gPorcArmed ? "ON" : "OFF") + " frame=" + ai.frame
			+ " mobileThreat=" + formatFloat(threat, "", 0, 1)
			+ "/" + formatFloat(armyFloor, "", 0, 1)
			+ " enemies=" + ai.GetEnemyTeamSize());
	}

	// Something to defend against. Frontier sites skip this test, and so does the
	// opening: before either side has an army a single known raider still justifies
	// one tower, which is what the old gate's `mobileThreat > 0` clause bought.
	// A site on the team's defence line is worth building whatever the global
	// threat gate says: that is where the attacks land, and a tower there that
	// arrives late is a tower that arrives never. apexearth: "treat defenses
	// more important, at least when they're at that team defense area in the
	// middle".
	// The tech lead's job is narrow: get the plant up, make advanced cons, make
	// T2 mexes, then keep scaling economy. apexearth: "they shouldn't even really
	// be building too many defenses unless they are feeling threatened -- focus
	// on eco and the T2". Every tower it builds is metal the team pooled for tech
	// spent on something else. Threat still overrides: staying alive is the one
	// early job it does have.
	if (Factory::IsDesignatedLead() && !gPorcArmed && !gTurtle && !LosingGround())
		return;

	// The edge of what we hold, with the gadget front kept as a second opinion
	// where it exists.
	const bool onLine = OnBorder(pos) || NearFront(pos);

	const bool early = (ai.frame <= 5 * MINUTE) && (threat > 0.f);
	// A BACK-LINE cluster needs more than "the enemy owns an army somewhere".
	// gPorcArmed is global and trips as early as 2.3 min, so on its own it let
	// every quiet rear mex through and they got walled while the front had
	// nothing. apexearth: "too much defenses being spent in the back line when
	// they could have been made up front to support the front line."
	//
	// Border sites are unchanged -- that is where the fighting is.
	//
	// LosingGround() used to open this gate too, which made every rear cluster on
	// the map eligible the moment we fell behind. Being behind is precisely when
	// build power must go to army instead, and the border is already covered by
	// the clause above, so it no longer bypasses the rear guard.
	if (!onLine && !early)
		return;

	// Something to pay with. Unchanged from the old gate, including the way that
	// same opening clause bypassed the income requirement outright.
	if ((ai.frame <= 5 * MINUTE) && (aiEconomyMgr.metal.income <= 10.f)
		&& !early && !onLine)
		return;

	// A front-line cluster still needs an enemy army to be worth walling. On a
	// small map almost every cluster reads as on-line, so `onLine` alone approved
	// the whole map and DefaultMakeDefence put a tower on every defence point.
	// Measured over five tournaments: static defence 15.5-21% of our metal
	// against stock's 7-8.4%, and halving our own front-tower rule
	// (PORC_ADD_CAP 4 -> 2) moved it 16.4% -> 16.8%, i.e. not at all -- the spend
	// is this call, not ours.
	if (!gPorcArmed && !gTurtle && !LosingGround() && !early)
		return;

	// HOW MUCH DEFENCE THE ECONOMY IS WORTH.
	//
	// This call is where the defence metal actually goes -- the comment above
	// says so from five tournaments -- and nothing bounded it but the clock that
	// has now been removed. Measured over 6 games at minute 14, removing those
	// cooldowns moved static defence from 17.5% of metal produced to 21.6% while
	// our standing army fell 4,637 -> 3,816 and losses rose 2,850 -> 3,811. The
	// towers were eating the army.
	//
	// The bound is the count our income supports, fitted to what the pre-Brain
	// build actually did rather than picked: it held ~2,525 metal of defence at
	// ~16 metal/second of income, and at ~190 metal a tower that is about 13 of
	// them -- 0.8 per point of income. gFenceId is every defence structure we
	// own, whoever placed it, so this bounds our own rules too, not just this
	// call. A turtle or a real push through our ground overrides it: being
	// attacked is when towers are worth more than the curve says.
	// Scaled by the category budget as well as by income, so defence answers
	// to the same table as everything else: over its share it buys fewer
	// towers, under its share it buys more. brain/budget.as.
	const float per = ai.GetTunable("apex_fence_per_income", 0.8f)
			* Brain::BudgetMult(Brain::DEFENCE);
	const int budget = 1 + int(aiEconomyMgr.metal.income * per);

	// NINETY PERCENT OF DEFENCE BELONGS ON THE FRONT LINE. apexearth: "We're
	// making tons of defenses but few of them are on the front line. We need to be
	// putting 90% of our defenses on the front line", and in USER-FEEDBACK.md
	// before that: "90% of a human's defences sit on the front line."
	//
	// The share was never enforced, only hoped for: onLine gated WHETHER a rear
	// cluster was eligible, and several clauses above bypass that gate entirely --
	// the opening, a turtle, losing ground. So rear towers competed for the same
	// budget as front ones and, there being far more rear clusters than border
	// ones on a small map, they won on sheer number.
	//
	// gFencePos records where every defence structure we own actually stands, so
	// the split can be counted rather than assumed. A rear site is refused once
	// the rear already holds its tenth; the front is never refused on this basis.
	if (!onLine) {
		const float rearShare = ai.GetTunable("apex_fence_rear_share", 0.10f);
		uint rear = 0;
		for (uint i = 0; i < gFencePos.length(); ++i) {
			if (!OnBorder(gFencePos[i]) && !NearFront(gFencePos[i]))
				++rear;
		}
		if (float(rear) >= float(budget) * rearShare) {
			if (ai.frame >= gNextFenceCapLog) {
				gNextFenceCapLog = ai.frame + 60 * SECOND;
				AiLog(Factory::T() + "apex: rear defence at its share " + rear
					+ "/" + formatFloat(float(budget) * rearShare, "", 0, 1)
					+ " of " + budget + " -- front line only");
			}
			return;
		}
	}
	if (!gTurtle && !BaseContested() && (int(gFenceId.length()) >= budget)) {
		if (ai.frame >= gNextFenceCapLog) {
			gNextFenceCapLog = ai.frame + 60 * SECOND;
			AiLog(Factory::T() + "apex: defence at budget " + gFenceId.length()
				+ "/" + budget + " for " + formatFloat(aiEconomyMgr.metal.income, "", 0, 0)
				+ " m/s -- army instead");
		}
		return;
	}

	aiMilitaryMgr.DefaultMakeDefence(cluster, pos);
}

//------------------------------------------------------------------------------
// Anti-air, sized to the enemy's actual ground-vs-air mix.
//
// Static and mobile AA are counted separately and need separate levers: only
// mobile units reach CMilitaryManager::AddResponse, so the response table's
// figures are mobile-only. Static AA is bounded through CCircuitDef::maxThisUnit,
// which IsAvailable() gates on in every path that can place one -- build chain
// hubs, DefaultMakeDefence, base defence, factory. Neither lever exists in
// build_chain.json, whose conditions are sampled once when the parent finishes
// and never re-checked.
//
// GetEnemyCost(AIR) is not "enemy aircraft". Air constructors and scouts carry
// ["builder", "air"] / ["scout", "air"] in behaviour.json, and CFactoryManager
// gives the AIR enemy role to every def that IsAbleToFly. Two enemy air
// constructors read as 680 metal of "air".
//------------------------------------------------------------------------------
// Enemy air value below which we build no AA at all beyond the cheap tiers.
// One Armada air constructor is 340 metal, one Cortex 360.
const float AA_IGNORE    = 500.f;
// Air share at which we answer their air at full stock strength. Below it, scale
// down; scale is never above 1, so this only ever builds less AA than stock.
const float AA_SHARE_REF = 0.25f;
const float AA_SCALE_MIN = 0.10f;
// Ceiling on AA as a share of our own army. response.json's own max_percent.
const float AA_MAX_PCT   = 0.50f;
// Enemy air metal, scaled, that buys one heavy AA turret (armflak/armcir
// 820/750, corflak/corerad 850/800, legflak 820).
const float AA_HEAVY_PER = 1500.f;
// No ceiling: heavy AA is already proportional to the enemy's observed air
// value through AA_HEAVY_PER. apexearth: "no AA heavy max".

// Air is over-counted and ground under-counted by simple visibility: aircraft
// fly over us constantly, ground sits in fog. Weight ground up, and average both
// so a single overflight does not swing the answer.
const float GROUND_UNSEEN  = 3.0f;
const float AIR_AVG_SECONDS = 240.f;
// Enemy air builders and scouts are counted as AIR. They cannot be separated
// from ground ones by role, so discount by the most that could plausibly be air.
const float SOFT_AIR_WEIGHT = 0.10f;
// Cap the discount: enemy builders+scouts include ground ones, so an uncapped
// subtraction erases a real bomber fleet. ~7 air constructors' worth.
const float SOFT_AIR_CAP = 2500.f;
float gAirAvg    = -1.f;
float gGroundAvg = -1.f;

}  // namespace Military
