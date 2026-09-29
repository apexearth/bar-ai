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
// is built on. THE AIR RAID OPENS ON AN ECONOMY, NOT A CLOCK. apexearth
// 2026-09-01: "bombers are for late game... when we have 200m/s or more... not
// really an early game thing... we don't want to make air too early, it makes
// us weak on ground." Measured over 122 games against BARb hard: corshad
// (Whirlwind) was 21.9% of ALL our combat metal against BARb's 4.8% -- a fifth
// of the army in bombers -- while our anti-air ran 1.4% against their 3.2% and
// our kill/loss ratio was 0.48 to their 0.93. We fielded the air force AND
// skipped the answer to theirs. AIR_FROM was 11 game-minutes, a timer, which
// is the one thing this AI is not allowed to gate progression on -- "late
// game" here always means economy size. AirEcoReady() is the replacement; the
// frame constant is kept only as the floor below which nothing has an economy
// worth reading.
const int   AIR_FROM       = 4 * MINUTE;

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
// strike. There is no ceiling: income bounds the strike on one side and their
// AA sizes it on the other (see ScaledBombers).
const float AIR_SCALE_INCOME = 30.f;   // extra metal/s per extra bomber above the floor

// THE STRIKE TARGET: enemy ECONOMY, ranked by value over the AA covering it
// (apexearth 2026-09-11: "build up bombers, and then eventually attack enemy
// eco in a large mass"). The map is swept in cells of apex_air_cluster_r, a
// few cells per update; a cell's prize is the metal of the structures in it
// and its cover the air-threat map read for one of our own bombers. The best
// cell of the last complete sweep is the target, and its prize is what the
// wing is worth. Not GetEnemyCostAt, which is a unit COUNT (docs/25 S28).
array<AIFloat3> gStrikeCells;
uint gStrikeCellI = 0;
bool gStrikeCurHas = false;
float gStrikeCurScore = 0.f, gStrikeCurPrize = 0.f, gStrikeCurAA = 0.f;
AIFloat3 gStrikeCurAt;
bool gStrikeHas = false;
float gStrikePrize = 0.f, gStrikeAA = 0.f;
AIFloat3 gStrikeAt;
int gStrikeSweeps = 0;
// The atomic bomber's cell from the same sweep: prize times ONE plane's chance
// over it, so a base under one flak outranks an empty cell of two mexes.
bool gAtomCellCurHas = false, gAtomCellHas = false;
float gAtomCellCurScore = 0.f, gAtomCellCurPrize = 0.f;
float gAtomCellPrize = 0.f;
AIFloat3 gAtomCellCurAt, gAtomCellAt;

CCircuitUnit@ AnyBomber()
{
	for (int i = 0; i < 4; ++i) {
		CCircuitDef@ d = StrikeDef(i);
		if (d is null)
			continue;
		array<CCircuitUnit@>@ us = ai.GetOwnUnitsOfDef(d, Builder::gHomePos, 0.f);
		if ((us is null) || (us.length() == 0))
			continue;
		for (uint k = 0; k < us.length(); ++k) {
			if (us[k] !is null)
				return us[k];
		}
	}
	return null;
}

void StrikeScanStep()
{
	if (!Builder::gHomeSet)
		return;
	const float r = ai.GetTunable("apex_air_cluster_r", TUNE_AIR_CLUSTER_R);
	if (r <= 1.f)
		return;
	if (gStrikeCells.length() == 0) {
		const float w = float(AiTerrainWidth());
		const float h = float(AiTerrainHeight());
		for (float z = r * 0.5f; z < h; z += r) {
			for (float x = r * 0.5f; x < w; x += r)
				gStrikeCells.insertLast(AIFloat3(x, 0.f, z));
		}
		if (gStrikeCells.length() == 0)
			return;
	}
	CCircuitUnit@ probe = AnyBomber();
	for (int step = 0; step < 4; ++step) {
		const AIFloat3 sp = gStrikeCells[gStrikeCellI];
		const float prize = aiEnemyMgr.GetEnemyStructCostAt(sp, r);
		if (prize > 1.f) {
			const float aa = CellAA(probe, sp, r);
			const float score = prize / (1.f + aa);
			if (!gStrikeCurHas || (score > gStrikeCurScore)) {
				gStrikeCurHas = true;
				gStrikeCurScore = score;
				gStrikeCurPrize = prize;
				gStrikeCurAA = aa;
				gStrikeCurAt = sp;
			}
			if (gBomberN !is null) {
				const float sN = Catalog::gHealth[int(gBomberN.id)]
						* ai.GetTunable("apex_air_aa_soak", TUNE_AIR_AA_SOAK);
				const float scoreN = (sN > 0.f) ? prize * sN / (sN + aa) : 0.f;
				if (!gAtomCellCurHas || (scoreN > gAtomCellCurScore)) {
					gAtomCellCurHas = true;
					gAtomCellCurScore = scoreN;
					gAtomCellCurPrize = prize;
					gAtomCellCurAt = sp;
				}
			}
		}
		if (++gStrikeCellI >= gStrikeCells.length()) {
			gStrikeCellI = 0;
			gStrikeHas = gStrikeCurHas;
			gStrikePrize = gStrikeCurPrize;
			gStrikeAA = gStrikeCurAA;
			gStrikeAt = gStrikeCurAt;
			gStrikeCurHas = false;
			gStrikeCurScore = 0.f;
			gAtomCellHas = gAtomCellCurHas;
			gAtomCellPrize = gAtomCellCurPrize;
			gAtomCellAt = gAtomCellCurAt;
			gAtomCellCurHas = false;
			gAtomCellCurScore = 0.f;
			++gStrikeSweeps;
		}
	}
}

// Metal standing in the target cell -- before the first sweep completes, in
// one cell around their structures' cost-weighted centre.
float EcoDensity()
{
	if (gStrikeHas)
		return gStrikePrize;
	const AIFloat3 at = aiEnemyMgr.GetEnemyStructPos();
	if (!OnMap(at))
		return 0.f;
	return aiEnemyMgr.GetEnemyStructCostAt(at,
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

int ScaledBombers()
{
	const int extra = int(Eco::MInc() * Persona::AirEagerness()
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
// ScaledBombers tracks income and their growing AA, so a release gate that
// compares against the LIVE want chases a treadmill and the wing never flies.
int  gCommitBombers = 0;
// HIS CADENCE (2026-08-29): "Maybe an attack every random between 5 and 10
// minutes for air attacks? We don't want to be too boring." The massing
// window before the wave goes with what stands is rolled per cycle -- at
// commit and again at each ReArm -- so strikes land on that rhythm without
// being predictable. AIR_DEADLINE remains only as the pre-roll default.
int  gDeadlineFrames = AIR_DEADLINE;

void RollDeadline()
{
	gDeadlineFrames = AiRandom(5 * MINUTE, 10 * MINUTE);
}

// The bomber count past which a wave goes anyway: half the force committed
// to, decaying by half again each further deadline period past the first,
// never under the floor wing. Frozen at commit (see gCommitBombers) so a
// want that grows with income and their AA cannot outrun the wave forever.
float DeadlineBombBar()
{
	float bar = 0.5f * float(gCommitBombers);
	if (gCommitFrame >= 0) {
		const int past = ai.frame - (gCommitFrame + gDeadlineFrames);
		if (past > 0)
			bar /= 1.f + float(past) / float(gDeadlineFrames);
	}
	if (bar < float(AIR_BOMBERS))
		bar = float(AIR_BOMBERS);
	return bar;
}
bool gStrike       = false;
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
float gRunKilled = 0.f;  // enemy structure metal that died in the target cell, by us
AIFloat3 gRunAt;         // the cell the run was sent at
int   gRunSettleAt = 0;
int   gWaveLaunched = 0; // bombers the current wave left with

// Fed from AiEnemyDestroyed: what the run is scored on. The cell's standing
// value before and after read 0 for three runs that the death log showed
// killing 3.6k -- they rebuild, and the registry lags -- so the deaths are
// counted as they happen. Not gated on byUs: a bomb whose plane is already
// dead when it lands reports no attacker, which is most of a wave's kills
// (docs/25 S30); the cell and the run's window are the attribution.
void NoteEnemyDeath(CCircuitDef@ edef, const AIFloat3& in pos, bool byUs)
{
	if ((gRunDef < 0) || (edef is null) || edef.IsMobile())
		return;
	if (!OnMap(pos) || !OnMap(gRunAt))
		return;
	if (pos.distance2D(gRunAt)
			<= ai.GetTunable("apex_air_cluster_r", TUNE_AIR_CLUSTER_R))
		gRunKilled += edef.costM;
}

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

// Is the economy big enough that air stops costing us the ground war?
//
// Stated at NO-BONUS scale and multiplied by the game's own handicap, the same
// treatment EcoRoleTargetM gets and for the same reason he gave there: a flat
// metal/s figure cannot travel between a bonused game and a plain one. His
// "200 m/s" is read as a +100% game, so the base is 100.
bool AirEcoReady()
{
	const float need = ai.GetTunable("apex_air_eco_base", TUNE_AIR_ECO_BASE)
			* Market::IncomeMult();
	return Market::EcoPowerM() >= need;
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

// The bomber the plant would build next: the advanced one where it exists.
int BuyableBomberDef()
{
	if ((gBomber !is null) && gBomber.IsAvailable(ai.frame))
		return int(gBomber.id);
	if (gBomber1 !is null)
		return int(gBomber1.id);
	if (gBomberH !is null)
		return int(gBomberH.id);
	return -1;
}

// WHAT THE NEXT BOMBER ADDS to the strike, in metal. Measured per bomber once
// a run of this type has been scored; before that, the target cell's prize
// times the share of the wing the model says gets through, differenced at
// the wing that stands. This is also where "eventually" comes from: the wing
// grows while the next plane raises what the strike destroys by more than
// the plane costs, and goes when it no longer does -- no clock. With no AA
// seen the model cannot rank, and the standing floor wing applies.
float MarginalGain(int d, int n)
{
	if (d < 0)
		return 0.f;
	const float obsPer = ObsDmg(d);
	if (obsPer >= 0.f)
		return obsPer;
	// Sized against everything they own, not one cell: a mass that survives
	// the AA works through their base cell by cell, and one cell's 16k
	// priced a six-plane wing (measured) -- not the mass he asked for. The
	// prior is optimistic on purpose; the scored run replaces it.
	// THEIR BASE IS AT LEAST OUR OWN, MIRRORED: the census only holds what
	// is in sight, so it read 36k against a mirror of 690k and the wing lost
	// every draw to fighters (apexearth: "I want to see us making bombers
	// and doing bombing raids... Our bombing logic is boring"). The same
	// floor the nuke director prices its mirrored target on.
	float prize = aiEnemyMgr.GetEnemyStructCost();
	const float mirror = MirrorPrize();
	if (mirror > prize)
		prize = mirror;
	return PrizeGain(d, n, prize);
}

// The model half of MarginalGain, for a prize the caller names.
float PrizeGain(int d, int n, float prize)
{
	if ((d < 0) || (prize <= 0.f))
		return 0.f;
	const float aa = StrikeAACost();
	const float s = Catalog::gHealth[d]
			* ai.GetTunable("apex_air_aa_soak", TUNE_AIR_AA_SOAK);
	if ((aa <= 0.f) || (s <= 0.f))
		return (n < ScaledBombers()) ? prize : 0.f;
	const float now = float(n) * s / (float(n) * s + aa);
	const float next = float(n + 1) * s / (float(n + 1) * s + aa);
	return prize * (next - now);
}

bool MarginalWorth(int d, int n)
{
	if (d < 0)
		return false;
	return MarginalGain(d, n)
			>= Catalog::gCostM[d] * ai.GetTunable("apex_air_payoff", TUNE_AIR_PAYOFF);
}

// Is the wing still worth growing? Asked of the plane we would buy next.
bool WingGrowing()
{
	const int d = BuyableBomberDef();
	return (d >= 0) && (HeldBombers() < ScaledBombers()) && MarginalWorth(d, HeldBombers());
}

// What one more bomber of THIS type returns, per second, to the wing -- the
// value the production draw prices it on. Zero unless we are the elected air
// player, the economy carries air, and the next plane still pays.
float StrikeGainFor(int d, float fillSec)
{
	// ANY PLAYER BUYS (his ruling 2026-09-29: there is not always a lead);
	// ShareWing pools what they hold on one ally, who flies them.
	if (!IsBomberDef(d))
		return 0.f;
	if (!WingBuys())
		return 0.f;
	if (IsAtomicDef(d))
		return IsAirLead() ? AtomicGainFor(fillSec) : 0.f;
	// Priced against the force AT HOME, so a wave already out neither counts
	// towards the next one nor stops it being built -- and against the POOLED
	// wing, or a donor that gave its planes away reads an empty wing forever.
	int held = HeldBombers();
	const int pool = int(TeamWingHeld());
	if (pool > held)
		held = pool;
	if ((ScaledBombers() <= 0) || (held >= ScaledBombers()))
		return 0.f;
	if (!MarginalWorth(d, held))
		return 0.f;
	return MarginalGain(d, held) / ((fillSec > 1.f) ? fillSec : 180.f);
}

// Would the wing buy a plane at all right now, prize aside: the economy
// carries air, and the ground war is not being lost badly before a wing is
// started (the same gate the commitment waits behind).
bool WingBuys()
{
	if ((ai.frame < AIR_FROM) || !AirEcoReady())
		return false;
	// (The "losing the ground war" hold-off that stood here is gone: it kept
	// a rich seat from buying a single bomber for the whole game -- seat seed
	// 4, `armpnix:wing0` at 34 min, "holding off -- losing the ground war
	// 60611 vs 103461" -- when a raid on their economy is the answer to a
	// ground war we are losing. apexearth 2026-09-14: "Need more air
	// plants, more air, more everything really.")
	return true;
}

// THE LOOK THE WING IS PRICED ON. MarginalGain reads the enemy structures we
// have SEEN, and nothing else in the air line ever goes to look, so an unseen
// base priced the wing at zero (apexearth: "we absolutely need scouts so we
// know what to hit"). The scout is worth what the look adds to the first
// bomber's gain: a mirror of our own economy against what the census already
// holds, fading to nothing right after a look and growing back over the
// horizon the census forgets on.
int gLookAt = -1;         // frame the last look was delivered, -1: never
int gLookScout = -1;      // the scout flying it, -1: none
int gLookDef = -1;
int gLookMiss = 0;        // passes in a row that showed nothing new
float gLookSeen0 = 0.f;   // the census when it left
AIFloat3 gLookTarget;
AIFloat3 gLookWay;        // the flank waypoint, when the straight line is worse
int gLookLeg = 1;         // 0 flying to the waypoint, 1 to the target
int gLookFlown = 0;
int gLookDelivered = 0;

// The air SCOUT: a transport is unarmed and cheap too, and flew the first one.
bool IsLookDef(int d)
{
	return (d > 0) && Catalog::gAvailable[d] && Catalog::gMobile[d]
		&& Catalog::gFlyer[d] && !Catalog::gBuilder[d]
		&& !Catalog::gKamikaze[d]
		&& (Catalog::gPower[d] <= 1.f) && (Catalog::gCostM[d] <= 100.f)
		&& Catalog::Def(d).IsRoleAny(Unit::Role::SCOUT.mask);
}

// The share of looks that came back with something, measured on this game's
// own flights and the only survival model a 52-metal plane gets.
float LookDelivery()
{
	return float(gLookDelivered + 1) / float(gLookFlown + 2);
}

// Their economy started equal to ours, base for base.
float MirrorPrize()
{
	return Market::gAssetsM * Military::AllyCount();
}

float LookStale()
{
	if (gLookAt < 0)
		return 1.f;
	const float horizon = ai.GetTunable("apex_ghost_stale_min", 15.f) * float(MINUTE);
	if (horizon <= 1.f)
		return 1.f;
	const float f = float(ai.frame - gLookAt) / horizon;
	return (f > 1.f) ? 1.f : ((f < 0.f) ? 0.f : f);
}

// What a look is worth: the wing's first purchase, or the atomic run waiting on it.
float LookWorth()
{
	const float a = AtomicLookWorth();
	const float w = WingLookWorth();
	return (a > w) ? a : w;
}

// What a look would add to the wing's first purchase, in metal.
float WingLookWorth()
{
	if (!IsAirLead() || !WingBuys())
		return 0.f;
	const int b = BuyableBomberDef();
	const int held = HeldBombers();
	if ((b < 0) || (ScaledBombers() <= 0) || (held >= ScaledBombers()))
		return 0.f;
	const float seen = aiEnemyMgr.GetEnemyStructCost();
	const float est = MirrorPrize();
	if (est <= seen)
		return 0.f;
	return (PrizeGain(b, held, est) - PrizeGain(b, held, seen)) * LookStale()
			* LookDelivery();
}

// The production draw's price for one more scout of THIS type. A second one
// in the air delivers the same picture the first will, so it adds nothing
// while one is pending or flying.
float LookGainFor(int d, float fillSec)
{
	if (!IsLookDef(d))
		return 0.f;
	if ((gLookScout >= 0) || (Brain::PendAnyOf(d) > 0))
		return 0.f;
	if (!LookPays(d))
		return 0.f;
	return LookWorth() / ((fillSec > 1.f) ? fillSec : 180.f);
}

// The same bar the wing holds its own planes to: the look must return the
// plane it risks, at the strike's payoff. Below it a standing scout is stock's.
bool LookPays(int d)
{
	return LookWorth() >= Catalog::gCostM[d]
			* ai.GetTunable("apex_air_payoff", TUNE_AIR_PAYOFF);
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
	gRunAt = gStrikeHas ? gStrikeAt : aiEnemyMgr.GetEnemyStructPos();
	gRunKilled = 0.f;
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
	const float dmg = gRunKilled;
	const float per = dmg / float(sent);
	if ((d < 0) || (d >= int(gObsSurv.length())))
		return;
	const float w = ai.GetTunable("apex_air_obs_w", TUNE_AIR_OBS_W);
	gObsSurv[d] = (gObsSurv[d] < 0.f) ? surv : (1.f - w) * gObsSurv[d] + w * surv;
	// The first run moves the model's own expectation, as later runs move the
	// estimate: taken outright, nine Phoenixes over an empty mirrored cell priced
	// every bomber at 42 metal for the rest of the game (apexearth 2026-09-26).
	float prior = per;
	if (gObsDmg[d] < 0.f) {
		float prize = aiEnemyMgr.GetEnemyStructCost();
		const float mirror = MirrorPrize();
		if (mirror > prize)
			prize = mirror;
		float sum = 0.f;
		for (int k = 0; k < sent; ++k)
			sum += PrizeGain(d, k, prize);
		prior = sum / float(sent);
	}
	gObsDmg[d]  = (gObsDmg[d]  < 0.f) ? ((1.f - w) * prior + w * per)
			: ((1.f - w) * gObsDmg[d] + w * per);
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
