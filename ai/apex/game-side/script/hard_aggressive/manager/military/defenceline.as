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
	if (!BorderPos(front, 0) && !FrontLinePos(front))
		return;
	gBigGunPlaced = true;
	AiLog(Factory::T() + "apex: big gun " + gun.GetName() + " at the territory edge");
	// BUNKER takes only a def and a position -- no target, no spot id.
	aiBuilderMgr.Enqueue(TaskB::Common(Task::BuildType::BUNKER,
			Task::Priority::NORMAL, gun, front, 0.f));
}

// Near the front line, in metres rather than as a fraction -- for callers that
// think in map distance.
//
// This used to read the gadget-published position (ai_frontx_<team>, from
// dev_team_income.lua) and so answered FALSE in every hosted game while being
// permissive on the bench: measured, it passed towers sitting at -0.17 along the
// home->enemy axis as "near the front". Both halves of that were wrong, and in
// opposite directions. It is the influence crossing now, same as OnBorder, so
// the bench and a real game agree.
const float FRONT_RADIUS = 1600.f;

bool NearFront(const AIFloat3& in pos)
{
	AIFloat3 f;
	if (!FrontLinePos(f))
		return false;
	const float dx = pos.x - f.x;
	const float dz = pos.z - f.z;
	return (dx * dx + dz * dz) < (FRONT_RADIUS * FRONT_RADIUS);
}

// THE FRONT LINE IS A TEAM OBJECT, SO ITS BUDGET IS A TEAM BUDGET.
//
// apexearth, from a hosted 8v8: "lol its always teal doing this, idk why."
//
// Two mechanisms, both deterministic, both mine. Factory::ElectorTeamId picks
// the LOWEST team id and hands out the lead roles, so the same slots hold the
// same roles in every game -- and AiMakeDefence returned outright for a lead,
// meaning defence landed entirely on whoever the election never picks. Teal was
// not behaving oddly; teal was never elected.
//
// And each player sized the front against its OWN income and counted only its
// OWN towers, so four players each independently decided how much line to hold.
// The line in front of our bases is one object, its length does not depend on
// how many of us there are, and the budget for it should not either.
//
// Published per player and summed: same mechanism the killing blow already uses
// for army value, and it needs no gadget.
const string TV_FFENCE = "ffence";
const string TV_MINC   = "minc";

void PublishDefence()
{
	uint front = 0;
	for (uint i = 0; i < gFencePos.length(); ++i) {
		if (OnBorder(gFencePos[i]) || NearFront(gFencePos[i]))
			++front;
	}
	ai.PublishTeamValue(TV_FFENCE, float(front));
	ai.PublishTeamValue(TV_MINC, aiEconomyMgr.metal.income);
}

float TeamSum(const string& in key, float own)
{
	array<Id>@ mates = ai.GetTeamIds();
	if ((mates is null) || (mates.length() == 0))
		return own;
	float total = 0.f;
	for (uint i = 0; i < mates.length(); ++i)
		total += ai.ReadTeamValue(int(mates[i]), key, 0.f);
	return (total > own) ? total : own;
}

// THE ONE ANSWER TO "MAY A TOWER GO HERE".
//
// apexearth: "Clean up those other systems that are placing the unwanted
// towers." Three of them placed defence without ever consulting the defence
// policy -- MexGuard put one on every extractor, Fortify put one wherever a
// constructor happened to be shot, and build_chain.json bolted one onto every
// factory -- so the income budget, the front-line rule and the rear share
// applied to a minority of what we actually built. Measured: 50 defence
// structures, 21 of them armllt, effectively none forward.
//
// Every placement now asks this first. It answers three questions in the order
// they matter, and each of them is economic or positional -- never a count typed
// in here:
//   1. is defence already over the share targets.as gives it,
//   2. is this the rear, and has the rear had its tenth,
//   3. ...unless we are actually being attacked, when a tower beats the curve.
bool DefenceAllowedAt(const AIFloat3& in pos)
{
	// BEING ATTACKED RAISES THE BUDGET; IT DOES NOT REMOVE IT.
	//
	// This returned true outright while contested, and measured at +50 the base
	// reads contested for most of the game -- so the gate switched itself off
	// exactly while the towers were being built, and the count went back to 70
	// with none of them forward. Under attack we can afford more defence, not
	// unlimited defence, and the rear share still has to hold or we wall the
	// wrong end of the map.
	// ONE MULTIPLIER, NOT TWO MULTIPLIED. apexearth: "We're definitely out of
	// control with building certain things like the light laser turrets and popup
	// air defense turrets."
	//
	// He is right and it was arithmetic, not the removed limits. This read
	// income * 0.8 * BudgetMult * pressure, and BudgetMult reaches 2.0 while
	// pressure is another 2.0 -- so a base under attack whose defence share was
	// still low allowed 1 + 40 * 0.8 * 4 = 129 towers at 40 metal/s. Both factors
	// say "more defence than usual is justified", and taking the larger of the two
	// says that once instead of squaring it.
	const float pressure = (gTurtle || BaseContested()) ? 2.f : 1.f;
	const float share = Brain::BudgetMult(Brain::DEFENCE);
	float boost = (pressure > share) ? pressure : share;
	// ROLE CHANGES HOW MUCH, NEVER WHETHER. A lead used to return outright, which
	// put the whole job on the players the election never picks. It buys less
	// now -- its metal is wanted for the plant and the T2 mexes -- but it is not
	// forbidden, which is his standing rule and the same fault as the eco-lead
	// exclusivity he caught before.
	if (Factory::IsDesignatedLead() && !gPorcArmed && !gTurtle && !LosingGround())
		boost *= ai.GetTunable("apex_lead_defence", 0.35f);
	const float per = ai.GetTunable("apex_fence_per_income", 0.8f) * boost;
	const float budget = 1.f + aiEconomyMgr.metal.income * per;

	// TWO JOBS, TWO ALLOWANCES. apexearth: "I just want to make sure we are
	// staying organized... I was wondering if we're depending on unrelated things
	// to get our frontline defence created."
	//
	// We were. Holding the line and guarding an extractor shared one budget, and
	// mex guards are numerous and near home -- so they spent the allowance and the
	// Brain's front request was then refused for being over it. The front line
	// depended on how many mexes we happened to own, which is exactly the coupling
	// he is asking about. Each job now counts only its own standing towers against
	// its own share, from targets.as DEF_FRONT / DEF_LOCAL.
	// NOTHING BEHIND OUR OWN BASE. apexearth, watching: "we're basically making
	// tons of defense, but we're making it all, like, behind our base."
	//
	// The gate only ever asked "is this forward?", and treated everything else as
	// local work worth an allowance -- which lumps a tower covering a rear mex in
	// with a tower on the far side of our own start position. Measured, our
	// players' median defence sat at -0.17 to -0.12 along the home->enemy axis:
	// past the base, away from the enemy. Ground the enemy can only reach by
	// walking through everything else we own does not need a turret.
	//
	// Exception is the same one as everywhere else: if they are actually in our
	// ground, they got there somehow and the geometry no longer argues.
	if ((ForwardFraction(pos) < 0.f) && !gTurtle && !BaseContested())
		return false;

	const float fShare = Targets::At(Targets::DEF_FRONT);
	const float lShare = Targets::At(Targets::DEF_LOCAL);
	const float total = (fShare + lShare > 0.f) ? (fShare + lShare) : 1.f;
	const bool forward = OnBorder(pos) || NearFront(pos);

	uint front = 0;
	uint local = 0;
	for (uint i = 0; i < gFencePos.length(); ++i) {
		if (OnBorder(gFencePos[i]) || NearFront(gFencePos[i]))
			++front;
		else
			++local;
	}
	if (forward) {
		// Team-wide: one line, one budget, however many of us are holding it.
		const float teamFront = TeamSum(TV_FFENCE, float(front));
		const float teamInc = TeamSum(TV_MINC, aiEconomyMgr.metal.income);
		const float teamBudget = 1.f + teamInc
				* ai.GetTunable("apex_fence_per_income", 0.8f) * boost;
		return teamFront < teamBudget * (fShare / total);
	}
	// Local work stays local: a mex guard defends OUR extractor with OUR metal.
	return float(local) < budget * (lShare / total);
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
	// The lead's reticence is a smaller budget now, not a refusal -- see
	// DefenceAllowedAt.

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

	// One policy, asked the same way every other placement asks it.
	if (!DefenceAllowedAt(pos)) {
		if (ai.frame >= gNextFenceCapLog) {
			gNextFenceCapLog = ai.frame + 60 * SECOND;
			AiLog(Factory::T() + "apex: defence refused here -- "
				+ gFenceId.length() + " standing, "
				+ (OnBorder(pos) ? "front" : "rear"));
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
