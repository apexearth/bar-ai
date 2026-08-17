namespace Military {

//------------------------------------------------------------------------------
// CAUSE-OF-DEATH KNOWLEDGE, fed back into caution.
//
// The map sweep made the failure contextual: the same aggression that wins an
// open map (Geyser Plains, K/D 0.78) bleeds out at a fortified doorstep on a
// small one (Altair 8x8, K/D 0.25) -- deaths peaking at forward fraction
// 0.89-0.99. No static margin can see that; the ledger can. Combat metal that
// dies DEEP on their ground accumulates here and decays over BLEED_TAU, so
// "forward fighting is currently unprofitable" is a live, self-correcting
// signal: caution rises, the bleed stops, the ledger drains, aggression
// returns -- and if the bleed resumes, so does the caution.
//------------------------------------------------------------------------------

const float BLEED_TAU = 180.f;   // seconds of memory
const float FWD_DEEP  = 0.55f;   // beyond this the death was on their ground
const float FWD_HOME  = 0.35f;   // below this it died defending home

float gBleedFwd  = 0.f;          // decayed metal: deep-forward combat deaths
float gBleedHome = 0.f;          // decayed metal: home-ground combat deaths
float gKillFwd   = 0.f;          // decayed metal: enemy things WE killed deep forward
// What killed our army, by attacker class -- observability first; consumers
// get their own measured pass.
float gDeadToStatic = 0.f;
float gDeadToAir    = 0.f;
float gDeadToMobile = 0.f;
int   gBleedLast = 0;
int   gNextBleedLog = 0;

void NoteCombatLoss(float costM, float fwd)
{
	if (fwd >= FWD_DEEP)
		gBleedFwd += costM;
	else if (fwd <= FWD_HOME)
		gBleedHome += costM;
}

// Only kills by OUR OWN units count (byUs); an identified enemy corpse deep on
// their ground is the payoff that justifies being there -- eco and army alike.
void NoteEnemyKill(float costM, float fwd, bool byUs)
{
	if (byUs && (fwd >= FWD_DEEP))
		gKillFwd += costM;
}

void NoteDeathSource(float costM, const CCircuitDef@ attackerDef)
{
	if (attackerDef is null)
		return;
	if (attackerDef.IsAbleToFly())
		gDeadToAir += costM;
	else if (!attackerDef.IsMobile())
		gDeadToStatic += costM;
	else
		gDeadToMobile += costM;
}

// NET deep-forward burn as a fraction of metal income: losses minus what we
// killed out there. A bloody push that pays for itself must not read as a
// bleed. Ledger holds roughly BLEED_TAU seconds, so ledger/TAU is metal/s.
float ForwardBleedFrac()
{
	const float inc = aiEconomyMgr.metal.income;
	if (inc <= 0.5f)
		return 0.f;
	const float net = gBleedFwd - gKillFwd;
	if (net <= 0.f)
		return 0.f;
	return (net / BLEED_TAU) / inc;
}

// >1 wants better odds and bigger groups before crossing again. Multiplies
// the same engage-margin lever personality uses, and the massing want.
float BleedCaution()
{
	float m = 1.f + ForwardBleedFrac() * ai.GetTunable("apex_bleed_engage", 2.f);
	const float cap = ai.GetTunable("apex_bleed_cap", 1.6f);
	if (m > cap)
		m = cap;
	return m;
}

void UpdateDeathLedger()
{
	const int step = ai.frame - gBleedLast;
	if (step <= 0)
		return;
	gBleedLast = ai.frame;
	float k = 1.f - (float(step) / 30.f) / BLEED_TAU;
	if (k < 0.f)
		k = 0.f;
	gBleedFwd *= k;
	gBleedHome *= k;
	gKillFwd *= k;
	gDeadToStatic *= k;
	gDeadToAir *= k;
	gDeadToMobile *= k;
	if ((ai.frame >= gNextBleedLog) && (gBleedFwd + gBleedHome + gKillFwd > 50.f)) {
		gNextBleedLog = ai.frame + 30 * SECOND;
		AiLog(Factory::T() + "apex: bleed fwd=" + formatFloat(gBleedFwd, "", 0, 0)
			+ " kill=" + formatFloat(gKillFwd, "", 0, 0)
			+ " home=" + formatFloat(gBleedHome, "", 0, 0)
			+ " frac=" + formatFloat(ForwardBleedFrac(), "", 0, 2)
			+ " caution=" + formatFloat(BleedCaution(), "", 0, 2)
			+ " by[stat/air/mob]=" + formatFloat(gDeadToStatic, "", 0, 0)
			+ "/" + formatFloat(gDeadToAir, "", 0, 0)
			+ "/" + formatFloat(gDeadToMobile, "", 0, 0));
	}
}

}  // namespace Military
