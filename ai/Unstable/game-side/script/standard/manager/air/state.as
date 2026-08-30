namespace Air {


//------------------------------------------------------------------------------
// Surprise air eco-assassination: one player per ally team quietly builds a T2
// air force, holds it at home while it grows, then throws all of it at the
// enemy economy and never brings it back. The value is in hitting before the
// enemy's anti-air exists -- see AIR_AA_CEILING.
//------------------------------------------------------------------------------

// Mid-game only: before this the whole team is pooling metal behind the tech
// lead, and an air plant competes with it. Kept short of the T1->T2 transition
// itself, since that transition IS the pooling window this AI's team strategy
// is built on.
const int   AIR_FROM       = 11 * MINUTE;

// The candidate's OWN metal income, out of reach of the 4v4 benchmark and
// comfortable at hosted-game income. Kept low deliberately: waiting for a
// bigger income is waiting for the enemy to build the anti-air that cancels
// the strategy's whole premise of surprise.
const float AIR_MIN_INCOME = 40.f;

// Enemy anti-air already on the field, in metal, above which we do not start.
// GetEnemyCost sums what we have SEEN, so it is a floor on their AA rather than a
// measurement of it -- which biases this gate towards committing.
const float AIR_AA_CEILING = 2500.f;

// 12 basic bombers is ~1,800 metal, a real strike on economy, with 8 fighters
// as escort rather than a matching wing.
const int   AIR_BOMBERS    = 12;
const int   AIR_FIGHTERS   = 8;

// Scale the strike size with our own economy: AIR_BOMBERS/AIR_FIGHTERS above
// are the floor; a stronger economy affords, and profits more from, a bigger
// strike.
const float AIR_SCALE_INCOME = 30.f;   // extra metal/s per extra bomber above the floor
const int   AIR_BOMBERS_MAX  = 30;

// HOW PACKED THEIR BASE IS. Bombing pays in proportion to what one run can
// reach, and a dense economy chains -- an AFUS going up takes its neighbours
// with it (apexearth: "blow up their AFUS to cause a huge chain reaction").
// Enemy cost sampled in one cluster radius around their centroid is the proxy;
// it includes army as well as economy, which biases the read UP where their
// army sits at home -- exactly where the bombs land anyway.
float EcoDensity()
{
	const AIFloat3 at = aiEnemyMgr.GetEnemyPos();
	if (!OnMap(at))
		return 0.f;
	return ai.GetEnemyCostAt(at,
			ai.GetTunable("apex_air_cluster_r", TUNE_AIR_CLUSTER_R));
}

// DURABILITY IS WHAT SHRUGS OFF AA, not headcount. An Archaic Dragon carries
// 16,700 hp against a Hailstorm's 1,520 and a Thunder's 670, so twenty heavies
// are a wall of health no light wing of any size matches (apexearth: "those
// things can far more easily shrug off AA... send 20 of them in and the enemy
// will definitely have a hard time"). Soak is therefore wing HEALTH, and the
// def we price is the toughest bomber we can actually field.
float BomberHP()
{
	float hp = 0.f;
	if ((gBomberH !is null) && gBomberH.IsAvailable(ai.frame))
		hp = Catalog::gHealth[int(gBomberH.id)];
	if ((hp <= 0.f) && (gBomber !is null))
		hp = Catalog::gHealth[int(gBomber.id)];
	if ((hp <= 0.f) && (gBomber1 !is null))
		hp = Catalog::gHealth[int(gBomber1.id)];
	return hp;
}

// A STRIKE OVERFLIES ONE BASE. Static AA cannot concentrate the way a field
// army does -- the exact inverse of the defence market's wave ruling -- so
// the whole-map census overstates what one raid must soak by the number of
// bases it is spread across, mirrored from our own team size (TeamExposure's
// symmetric trick; a 1v1 divides by nothing). Sized on the census, want read
// 125 bombers off enemyAA=16,670 while 50 real ones hovered ten minutes at
// home, and STANDING DOWN latched because half of 125 was out of reach.
float StrikeAACost()
{
	float aa = EnemyAACost();
	if (ai.GetTunable("apex_air_aa_split", TUNE_AIR_AA_SPLIT) > 0.f) {
		const float bases = Military::AllyCount();
		if (bases > 1.f)
			aa /= bases;
	}
	return aa;
}

// WHAT FRACTION OF A STRIKE OF n GETS THROUGH. AA is a rate, not a wall: it
// engages one target at a time, so wing health dilutes it and enough bombers
// from enough angles always land some (apexearth: "think 50 or 100 bombers
// coming in from different angles... some will likely get through"). Never
// zero, never a veto -- the old absolute ceiling stood the assassin down
// against 2.5k of AA in a game already won.
float Throughput(int n)
{
	const float aa = StrikeAACost();
	if (aa <= 0.f)
		return 1.f;
	// MEASURED BEATS MODELLED: once a run of this type has been scored, its
	// own survival is the answer -- flak splash, interception and the flight
	// home are all in the number and none of them are in the model.
	const float obs = ObsSurv(DominantBomberDef());
	if (obs >= 0.f)
		return obs;
	const float soak = float(n) * BomberHP()
			* ai.GetTunable("apex_air_aa_soak", TUNE_AIR_AA_SOAK);
	if (soak <= 0.f)
		return 0.f;
	return soak / (soak + aa);
}

// Is the raid worth its own metal? Expected damage is what one pass can reach
// times the share that survives to deliver it; the bar is the strike's own
// cost at a payoff multiple. Density and AA both enter here as PRICES, which
// is what lets a thin economy behind heavy AA be declined while a packed one
// behind the same AA is still worth overwhelming.
bool StrikeWorth()
{
	const int n = ScaledBombers();
	if (n <= 0)
		return false;
	// Damage is measured per bomber where a run has been scored, and bounded by
	// what the cluster actually holds; unmeasured, it falls back to "the wing
	// destroys what it reaches", which is the optimistic prior that makes the
	// first cheap probe worth flying.
	const float obsPer = ObsDmg(DominantBomberDef());
	float dmg = EcoDensity() * Throughput(n);
	if (obsPer >= 0.f) {
		const float measured = obsPer * float(n);
		if (measured < dmg)
			dmg = measured;
	}
	float spend = 0.f;
	if (gBomber !is null)
		spend = float(n) * gBomber.costM;
	else if (gBomber1 !is null)
		spend = float(n) * gBomber1.costM;
	if (spend <= 1.f)
		return true;   // no bomber priced yet; do not veto on a missing def
	return dmg >= spend * ai.GetTunable("apex_air_payoff", TUNE_AIR_PAYOFF);
}

int ScaledBombers()
{
	const int extra = int(aiEconomyMgr.metal.income * Persona::AirEagerness()
			/ AIR_SCALE_INCOME);
	const int want = AIR_BOMBERS + extra;
	// AA RAISES THE MASS NEEDED, it does not forbid the raid: enough bombers
	// saturate it. No flat ceiling here -- income bounds the strike on one side
	// and their AA sizes it on the other.
	const float perBomber = BomberHP()
			* ai.GetTunable("apex_air_aa_soak", TUNE_AIR_AA_SOAK);
	const int forAA = (perBomber > 0.01f)
			? int(StrikeAACost() / perBomber) : 0;
	const int capped = want + forAA;
	// A ONE-SHOT basic bomber (Legion's Martyr): each sortie expends the whole
	// wing, so a reusable-bomber count buys one alpha strike and a pile of
	// corpses. Until the reusable advanced bomber exists, want a fraction.
	// apexearth 2026-08-15: "we made too many martyrs... those guys are 1 shot"
	if ((gBomber1 !is null) && (gBomber1.GetName() == "legkam")
		&& (Have(gBomber) == 0))
	{
		const float s = ai.GetTunable("apex_oneshot_bomber_scale", TUNE_ONESHOT_BOMBER_SCALE);
		const int scaled = int(float(capped) * s + 0.99f);
		return (scaled < 1) ? 1 : scaled;
	}
	return capped;
}

int ScaledFighters()
{
	// Same escort ratio as the floor (8 fighters per 12 bombers), scaled
	// with the bomber count rather than income directly.
	return int(float(ScaledBombers()) * float(AIR_FIGHTERS) / float(AIR_BOMBERS));
}

// Enqueue does not dedup and CCircuitDef::count only moves when a unit is
// registered, so back-to-back orders overshoot the target. Same reason
// Factory::RUSH_CON_SPACING exists.
const int   AIR_ORDER_SPACING = 2 * SECOND;

// How many aircraft to queue per order, so the plant never stands idle between
// them. CmdBuild takes one def per call and Spring's CMD_REPEAT is not bound to
// the script; CFactoryManager::DefaultMakeTask picks up queued-but-unassigned
// recruits as the plant frees up, so queue depth substitutes for a repeat flag.
// Overshoot is bounded by the same check that gates a single order: only issued
// while short of ScaledBombers()/ScaledFighters().
const int   AIR_BATCH = 6;

// Massing forever is its own failure. Past this, strike with whatever is built
// provided it is at least half a force.
const int   AIR_DEADLINE   = 4 * MINUTE;

// How far behind on the ground cancels the whole strategy. Above parity by a
// clear margin, so an even fight does not veto it; see the check in Update().
const float GROUND_LOST_RATIO = 1.5f;

// One writer per slot, as with the tech-lead election in factory.as: every
// instance publishes its own income, and only the elector publishes the answer.
const string TV_AIRINC  = "airinc";
const string TV_AIRLEAD = "airlead";
// The team interceptor pool (apexearth 2026-08-18): every player publishes
// enemy AIR value over its own home plus its home coords; players holding
// fighters fly them to the worst-hit ally and re-issue while the raid lasts.
const string TV_AIRRAID = "airraid";
const string TV_HOMEX   = "homex";
const string TV_HOMEZ   = "homez";
int gNextRaidPub = 0;
int gNextInterceptCmd = 0;
int gInterceptTarget = -1;
array<Id>@ gMatesCache = null;

// The aircraft one strike owns: filled at Release, pruned as they die, empty
// while nothing is out. Anything not in it is held at home, whatever gStrike
// says -- see wave.as.
array<Id> gWave;
array<Id> gRunWave;      // the bombers of the run being SCORED, for SettleStrike
// The base is being invaded: every aircraft flies, wave or not. NOT a strike --
// routing it through gStrike released a single bomber as a "wave", ReArm called
// that wave spent on the same tick, and the pair flapped every update.
bool gDefendHome   = false;
int  gWaveBombers  = 0;
int  gWaveFighters = 0;

int  gAirLead      = -1;
int  gLeadCheckedAt = -1000;
int  gCommitFrame  = -1;
// The wing size promised when the strike was committed to (and again when a
// run ends), frozen so the go-anyway bar has a fixed number to be half of.
// Measured live (37-min 1v1, ~1700 m/s): ScaledBombers tracked income and
// their growing AA to 93 while 30 bombers stood at home, so every release
// gate that compared against the LIVE want chased a treadmill and the whole
// air arm sat out the game.
int  gCommitBombers = 0;

// The bomber count past which a wave goes anyway: half the force committed
// to, decaying by half again each further deadline period past the first,
// never under the floor wing. Frozen at commit (see gCommitBombers) so a
// want that grows with income and their AA cannot outrun the wave forever.
float DeadlineBombBar()
{
	float bar = 0.5f * float(gCommitBombers);
	if (gCommitFrame >= 0) {
		const int past = ai.frame - (gCommitFrame + AIR_DEADLINE);
		if (past > 0)
			bar /= 1.f + float(past) / float(AIR_DEADLINE);
	}
	if (bar < float(AIR_BOMBERS))
		bar = float(AIR_BOMBERS);
	return bar;
}
bool gStrike       = false;
bool gAbort        = false;
int  gNextAirOrder = 0;
int  gNextProbe    = 0;
int  gNextLog      = 0;
int  gNextElectLog = 0;
bool gAnnounced    = false;

bool gDefsResolved = false;
CCircuitDef@ gPlant1  = null;   // T1 air plant
CCircuitDef@ gPlant2  = null;   // T2 air plant
CCircuitDef@ gCon1    = null;   // T1 air constructor
CCircuitDef@ gCon2    = null;   // T2 air constructor

//------------------------------------------------------------------------------
// STRIKE OUTCOME LEDGER. apexearth: "if you were able to gauge the success of a
// bombing run then that tells you if hailstorms are viable... sometimes you
// don't know until you try." Survival and delivered damage are MEASURED per
// bomber type and fed back, so the choice between a cheap probe and a heavy
// wing stops being a modelling guess. The model below is only the prior, and
// the prior deliberately favours the cheap fast bomber -- trying a Hailstorm
// run first is correct, and a failed one is what buys Dragons.
//------------------------------------------------------------------------------
array<float> gObsSurv;   // per def: measured survival fraction, <0 unmeasured
array<float> gObsDmg;    // per def: measured metal destroyed per bomber sent
int   gRunDef      = -1;
int   gRunSent     = 0;
float gRunEcoBefore = 0.f;
int   gRunSettleAt = 0;

void ObsInit()
{
	if (gObsSurv.length() == 0) {
		gObsSurv.resize(Catalog::gDefCount + 1);
		gObsDmg.resize(Catalog::gDefCount + 1);
		for (uint i = 0; i < gObsSurv.length(); ++i) {
			gObsSurv[i] = -1.f;
			gObsDmg[i] = -1.f;
		}
	}
}

// The type that actually flew, so the outcome is attributed to it.
bool IsBomberDef(int d)
{
	if ((gBomberH !is null) && (int(gBomberH.id) == d)) return true;
	if ((gBomber  !is null) && (int(gBomber.id)  == d)) return true;
	if ((gBomber1 !is null) && (int(gBomber1.id) == d)) return true;
	if ((gBomberN !is null) && (int(gBomberN.id) == d)) return true;
	return false;
}

// What one more bomber of THIS type returns, per second, to the assassin's
// strike -- the value the production draw prices it on. Zero unless we are the
// elected air player, the raid is on, and the wing is still short.
float StrikeGainFor(int d, float fillSec)
{
	if (!IsAirLead() || gAbort || !IsBomberDef(d))
		return 0.f;
	if (ai.frame < AIR_FROM)
		return 0.f;
	// Priced against the force AT HOME, so a wave already out neither counts
	// towards the next one nor stops it being built. Production used to stop
	// dead for the length of a strike, which is what made every run smaller
	// than the one before it.
	const int need = ScaledBombers();
	if ((need <= 0) || (HeldBombers() >= need))
		return 0.f;
	// Priced on the WHOLE raid this type would mount, then shared over its
	// bombers: a type that needs a hundred to punch through carries the cost of
	// a hundred. Measured survival and delivered damage override the prior as
	// soon as one run of this type has been scored.
	float surv = ObsSurv(d);
	if (surv < 0.f) {
		const float aa = EnemyAACost();
		const float soak = float(need) * Catalog::gHealth[d]
				* ai.GetTunable("apex_air_aa_soak", TUNE_AIR_AA_SOAK);
		surv = (aa <= 0.f) ? 1.f : ((soak <= 0.f) ? 0.f : soak / (soak + aa));
	}
	float dmg = EcoDensity() * surv;
	const float obsPer = ObsDmg(d);
	if (obsPer >= 0.f) {
		const float measured = obsPer * float(need);
		if (measured < dmg)
			dmg = measured;
	}
	if (dmg <= 0.f)
		return 0.f;
	return (dmg / float(need)) / ((fillSec > 1.f) ? fillSec : 180.f);
}

int DominantBomberDef()
{
	int bestId = -1;
	int bestN = 0;
	if ((gBomberH !is null) && (Have(gBomberH) > bestN)) { bestN = Have(gBomberH); bestId = int(gBomberH.id); }
	if ((gBomber  !is null) && (Have(gBomber)  > bestN)) { bestN = Have(gBomber);  bestId = int(gBomber.id); }
	if ((gBomber1 !is null) && (Have(gBomber1) > bestN)) { bestN = Have(gBomber1); bestId = int(gBomber1.id); }
	if ((gBomberN !is null) && (Have(gBomberN) > bestN)) { bestN = Have(gBomberN); bestId = int(gBomberN.id); }
	return bestId;
}

void NoteStrikeLaunched()
{
	ObsInit();
	gRunDef = DominantBomberDef();
	gRunSent = gWaveBombers;
	gRunEcoBefore = EcoDensity();
	gRunSettleAt = ai.frame
			+ int(ai.GetTunable("apex_air_settle_s", TUNE_AIR_SETTLE_S)) * SECOND;
}

// One run, scored. Damage is the drop in the target cluster's value; survival
// is what came home. Both are crude -- the cluster also loses units to our
// ground army, and reinforcements refill it -- so they smooth into an EMA
// rather than replacing the prior outright.
void SettleStrike()
{
	if ((gRunDef < 0) || (ai.frame < gRunSettleAt))
		return;
	const int sent = gRunSent;
	const int d = gRunDef;
	gRunDef = -1;
	if (sent <= 0)
		return;
	const int left = RunSurvivors();
	float surv = float(left) / float(sent);
	if (surv < 0.f) surv = 0.f;
	if (surv > 1.f) surv = 1.f;
	float dmg = gRunEcoBefore - EcoDensity();
	if (dmg < 0.f) dmg = 0.f;
	const float per = dmg / float(sent);
	if ((d < 0) || (d >= int(gObsSurv.length())))
		return;
	const float w = ai.GetTunable("apex_air_obs_w", TUNE_AIR_OBS_W);
	gObsSurv[d] = (gObsSurv[d] < 0.f) ? surv : (1.f - w) * gObsSurv[d] + w * surv;
	gObsDmg[d]  = (gObsDmg[d]  < 0.f) ? per  : (1.f - w) * gObsDmg[d]  + w * per;
	AiLog(Factory::T() + "apex: air run scored def=" + Catalog::Def(d).GetName()
		+ " sent=" + sent + " home=" + left
		+ " surv=" + formatFloat(gObsSurv[d], "", 0, 2)
		+ " dmg/bomber=" + formatFloat(gObsDmg[d], "", 0, 0));
}

float ObsSurv(int defId)
{
	ObsInit();
	return ((defId >= 0) && (defId < int(gObsSurv.length()))) ? gObsSurv[defId] : -1.f;
}

float ObsDmg(int defId)
{
	ObsInit();
	return ((defId >= 0) && (defId < int(gObsDmg.length()))) ? gObsDmg[defId] : -1.f;
}

CCircuitDef@ gBomber  = null;   // advanced bomber
CCircuitDef@ gFighter = null;   // advanced fighter
// BASIC tier, built off the T1 plant rather than waiting on the advanced one --
// cheaper, and surprise is cheapest early.
CCircuitDef@ gBomber1  = null;
CCircuitDef@ gBomberH  = null;  // heavy: the AA-shrugging tier, may be null
CCircuitDef@ gBomberN  = null;  // atomic bomber, may be null (Armada only)
CCircuitDef@ gFighter1 = null;

}  // namespace Air
