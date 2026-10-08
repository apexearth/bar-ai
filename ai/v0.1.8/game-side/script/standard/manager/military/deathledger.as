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
float gLossAll   = 0.f;          // decayed metal: ALL combat deaths, any ground
float gRezLost   = 0.f;          // decayed metal: rez bots of ours that died
float gScreenLost = 0.f;         // decayed metal: screen units (the Tick class) of ours that died
float gKillAll   = 0.f;          // decayed metal: ALL kills by our own units
float gWreckWet  = 0.f;          // decayed metal: the part of both that fell in water
// What killed our army, by attacker class -- observability first; consumers
// get their own measured pass.
float gDeadToStatic = 0.f;
float gDeadToAir    = 0.f;
float gDeadToMobile = 0.f;
// WHAT BOMBARDMENT IS ACTUALLY COSTING US. The air twin of this drives AA's
// measured floor; the plasma side had no ledger at all, so "are we being
// shelled" -- which is what decides whether a remembered LRPC still matters
// (apexearth 2026-09-06: "remember it, fade if nothing shells us") -- could not
// be asked. Fed from STRUCTURE deaths as well as army: an LRPC's whole point is
// that it kills buildings, and the army-only filter discarded exactly its
// victims.
float gDeadToPlasma = 0.f;
float gPlasmaGunM = 0.f;   // the dearest static long-range gun that has killed something of ours
// WHAT TIER THEY ARE FIELDING. The only enemy DEFS script ever holds are the
// ones the two death hooks hand us -- there is no per-def enemy enumeration
// binding, only role-aggregated cost -- so this is contact-attested and reads
// zero in a game where the fronts never meet. That is the honest no-change
// case: we learn they have T3 by meeting it, which is also when it matters.
array<float> gFoeTierM(4, 0.f);
int   gBleedLast = 0;
int   gNextBleedLog = 0;

void NoteCombatLoss(float costM, float fwd, bool wet)
{
	gLossAll += costM;
	if (wet)
		gWreckWet += costM;
	if (fwd >= FWD_DEEP)
		gBleedFwd += costM;
	else if (fwd <= FWD_HOME)
		gBleedHome += costM;
}

// Only kills by OUR OWN units count (byUs); an identified enemy corpse deep on
// their ground is the payoff that justifies being there -- eco and army alike.
void NoteEnemyKill(float costM, float fwd, bool byUs, bool wet)
{
	if (!byUs)
		return;
	gKillAll += costM;
	if (wet)
		gWreckWet += costM;
	if (fwd >= FWD_DEEP)
		gKillFwd += costM;
}

void NoteFoeDef(float costM, const CCircuitDef@ edef)
{
	if ((edef is null) || (costM <= 0.f) || !edef.IsMobile())
		return;
	const int t = Market::DefTier(int(edef.id));
	if ((t >= 1) && (t < int(gFoeTierM.length())))
		gFoeTierM[t] += costM;
}

// Share of the enemy metal we have IDENTIFIED that outranks this tier.
float FoeTierAbove(int tier)
{
	float tot = 0.f, above = 0.f;
	for (uint i = 1; i < gFoeTierM.length(); ++i) {
		tot += gFoeTierM[i];
		if (int(i) > tier)
			above += gFoeTierM[i];
	}
	return (tot > 1.f) ? (above / tot) : 0.f;
}

// Where their turrets kill us: metal-weighted sums, decayed with the rest of
// the ledger.
float gStaticDeathX = 0.f;
float gStaticDeathZ = 0.f;

void NoteDeathSource(float costM, const CCircuitDef@ attackerDef, const AIFloat3 &in at)
{
	if (attackerDef is null)
		return;
	if (attackerDef.IsAbleToFly())
		gDeadToAir += costM;
	else if (!attackerDef.IsMobile()) {
		gDeadToStatic += costM;
		gStaticDeathX += costM * at.x;
		gStaticDeathZ += costM * at.z;
	} else
		gDeadToMobile += costM;
}

float StaticLossRate()
{
	return gDeadToStatic / BLEED_TAU;
}

// THE TURRETS WE MEAN TO HIT: of the enemy groups we know that hold armed
// buildings, the one nearest where their turrets have been killing us. Its
// reach is the longest gun in it; its metal is those guns.
int gTurretAt = -1;
int gTurretLogAt = 0;
bool gTurretOk = false;
AIFloat3 gTurretPos;
float gTurretReach = 0.f;
float gTurretM = 0.f;
float gTurretLineReach = 0.f;   // the line's own guns: no supers, no stockpiles
float TurretLineReach() { return gTurretLineReach; }
bool TurretTarget(AIFloat3 &out at, float &out reach, float &out metal)
{
	if (gDeadToStatic < 1.f)
		return false;
	if ((gTurretAt < 0) || (ai.frame >= gTurretAt + 5 * SECOND)) {
		gTurretAt = ai.frame;
		gTurretOk = false;
		const AIFloat3 died(gStaticDeathX / gDeadToStatic, 0.f, gStaticDeathZ / gDeadToStatic);
		float bestD = 1e30f;
		const int n = aiEnemyMgr.GetEnemyGroupCount();
		int armed = 0, units = 0;
		for (int g = 0; g < n; ++g) {
			float m = 0.f, r = 0.f, lr = 0.f;
			const int k = aiEnemyMgr.GetEnemyGroupUnitCount(g);
			units += k;
			for (int i = 0; i < k; ++i) {
				const int d = aiEnemyMgr.GetEnemyGroupUnitDef(g, i);
				if ((d < 1) || (d > Catalog::gDefCount) || Catalog::gMobile[d]
						|| (Catalog::gMaxRange[d] <= 1.f) || (Catalog::gSurfT[d] <= 0.f)
						|| (Catalog::gBuildsList[d].length() > 0))
					continue;
				m += Catalog::gCostM[d];
				if (Catalog::gMaxRange[d] > r)
					r = Catalog::gMaxRange[d];
				if (!Market::IsSuperWeapon(d) && !Catalog::gStock[d] && (Catalog::gMaxRange[d] > lr))
					lr = Catalog::gMaxRange[d];
			}
			if (m <= 0.f)
				continue;
			++armed;
			const AIFloat3 gp = aiEnemyMgr.GetEnemyGroupPos(g);
			const float dd = gp.distance2D(died);
			if (dd < bestD) {
				bestD = dd;
				gTurretPos = gp;
				gTurretReach = r;
				gTurretLineReach = lr;
				gTurretM = m;
				gTurretOk = true;
			}
		}
		if (ai.frame >= gTurretLogAt) {
			gTurretLogAt = ai.frame + 60 * SECOND;
			AiLog("apex: turret-target t=" + ai.teamId + " groups=" + n + " units=" + units
				+ " armed=" + armed + " died=" + int(died.x) + "," + int(died.z)
				+ " ok=" + (gTurretOk ? 1 : 0) + " at=" + int(gTurretPos.x) + "," + int(gTurretPos.z)
				+ " m=" + int(gTurretM) + " r=" + int(gTurretReach));
		}
	}
	at = gTurretPos;
	reach = gTurretReach;
	metal = gTurretM;
	return gTurretOk;
}

// Metal per second we are CURRENTLY losing to aircraft. The ledger decays over
// BLEED_TAU, so ledger/TAU is a rate -- the same currency a turret's prevented
// loss is priced in, which is what lets AA compete on measured evidence rather
// than on an insurance rate (apexearth, watched: "I see the enemy bombing us
// for minutes and we haven't built any T1 anti air").
float AirLossRate()
{
	return gDeadToAir / BLEED_TAU;
}

// ANYTHING OF OURS KILLED BY A STATIC LONG-RANGE GUN, structures included.
// Called before the army filters, so it sees the mexes and generators an LRPC
// exists to remove.
void NotePlasmaLoss(float costM, const CCircuitDef@ attackerDef)
{
	if ((attackerDef is null) || (costM <= 0.f))
		return;
	if (attackerDef.IsMobile())
		return;
	// The same derived set EnemyLRPCs counts -- a non-stockpile superweapon of
	// any faction -- so the ledger and the sighting census can never disagree
	// about what "shelled us" means.
	const int ad = int(attackerDef.id);
	if (!Market::IsSuperWeapon(ad) || Catalog::gStock[ad])
		return;
	gDeadToPlasma += costM;
	if (Catalog::gCostM[ad] > gPlasmaGunM)
		gPlasmaGunM = Catalog::gCostM[ad];
}

// Metal per second we are CURRENTLY losing to bombardment. Same currency as
// AirLossRate: the ledger decays over BLEED_TAU, so ledger/TAU is a rate.
float PlasmaLossRate()
{
	return gDeadToPlasma / BLEED_TAU;
}

// Metal per second of NEW WRECK appearing on ground we fight over: our combat
// dead plus the enemy our own units killed, both already carried by the same
// decaying ledger, so ledger/TAU is the rate. This is rez-bot demand -- what
// the fleet is asked to serve per second -- as opposed to the pile standing on
// the field, which is a stock and grows all game whether or not anyone can
// reach it (market/army.as).
float WreckRateM()
{
	return (gLossAll + gKillAll) / BLEED_TAU;
}

// A boat cannot reach a wreck on land, nor a bot one at sea.
float WreckWetShare()
{
	const float all = gLossAll + gKillAll;
	return (all > 1.f) ? (gWreckWet / all) : 0.f;
}

// THE FLEET'S OWN DEATHS ARE THE WRECKS IT CANNOT HAVE. A wreck field
// under the enemy's guns reads as a stream and bought bots by the dozen to
// walk into the same guns. What the fleet loses per second comes off the
// stream it is sized to.
void NoteRezLoss(float costM)
{
	gRezLost += costM;
}
float RezLostRateM()
{
	return gRezLost / BLEED_TAU;
}
// The screen's deaths over the window, in units of one screen unit: a scout
// that dies at the post it was bought to watch is not eyes, it is feed.
void NoteScreenLoss(float costM)
{
	gScreenLost += costM;
}
float ScreenLostM()
{
	return gScreenLost;
}

// NET deep-forward burn as a fraction of metal income: losses minus what we
// killed out there. A bloody push that pays for itself must not read as a
// bleed. Ledger holds roughly BLEED_TAU seconds, so ledger/TAU is metal/s.
float ForwardBleedFrac()
{
	const float inc = Eco::MInc();
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
	float m = 1.f + ForwardBleedFrac() * ai.GetTunable("apex_bleed_engage", TUNE_BLEED_ENGAGE);
	const float cap = ai.GetTunable("apex_bleed_cap", TUNE_BLEED_CAP);
	if (m > cap)
		m = cap;
	return m;
}

//------------------------------------------------------------------------------
// THE TRADE, EVERYWHERE -- not just deep forward. apexearth 2026-08-19: "if our
// army keeps getting killed then we need to focus on making more army, and
// using that army in defense." Metal killed over metal lost, decayed over the
// same window; only meaningful once real metal has died, so the opening (no
// losses) and a quiet game both read as a neutral trade.
//------------------------------------------------------------------------------

// Enough recent combat to judge by: losses worth this many seconds of income.
bool TradeMeaningful()
{
	const float inc = Eco::MInc();
	return gLossAll > inc * ai.GetTunable("apex_trade_vol", TUNE_TRADE_VOL);
}

float TradeRatio()
{
	if (!TradeMeaningful() || (gLossAll <= 1.f))
		return 1.f;
	return gKillAll / gLossAll;
}

// Trading badly enough to change posture: we die and they mostly don't.
bool TradeBad()
{
	return TradeRatio() < ai.GetTunable("apex_trade_bad", TUNE_TRADE_BAD);
}

// NET combat burn as a fraction of income, all grounds -- the "army keeps
// getting killed" pressure. Same construction as ForwardBleedFrac but total.
float LossPressureFrac()
{
	const float inc = Eco::MInc();
	if (inc <= 0.5f)
		return 0.f;
	const float net = gLossAll - gKillAll;
	if (net <= 0.f)
		return 0.f;
	return (net / BLEED_TAU) / inc;
}

// >1 tilts the budget split toward ARMY while the army is being eaten faster
// than it eats back. Scaled by the pressure, bounded so a massacre cannot
// starve the economy that has to pay for the rebuild.
float LossArmyMult()
{
	float m = 1.f + LossPressureFrac() * ai.GetTunable("apex_loss_army", TUNE_LOSS_ARMY);
	const float cap = ai.GetTunable("apex_loss_army_cap", TUNE_LOSS_ARMY_CAP);
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
	gLossAll *= k;
	gRezLost *= k;
	gScreenLost *= k;
	gKillAll *= k;
	gWreckWet *= k;
	gDeadToStatic *= k;
	gStaticDeathX *= k;
	gStaticDeathZ *= k;
	gDeadToAir *= k;
	gDeadToMobile *= k;
	gDeadToPlasma *= k;
	for (uint fi = 0; fi < gFoeTierM.length(); ++fi)
		gFoeTierM[fi] *= k;
	if ((ai.frame >= gNextBleedLog) && (gBleedFwd + gBleedHome + gKillFwd > 50.f)) {
		gNextBleedLog = ai.frame + 30 * SECOND;
		AiLog(Factory::T() + "apex: foetier t1="
			+ formatFloat(gFoeTierM[1], "", 0, 0)
			+ " t2=" + formatFloat(gFoeTierM[2], "", 0, 0)
			+ " t3=" + formatFloat(gFoeTierM[3], "", 0, 0)
			+ " above1=" + formatFloat(FoeTierAbove(1), "", 0, 2)
			+ " above2=" + formatFloat(FoeTierAbove(2), "", 0, 2));
		AiLog(Factory::T() + "apex: bleed fwd=" + formatFloat(gBleedFwd, "", 0, 0)
			+ " kill=" + formatFloat(gKillFwd, "", 0, 0)
			+ " home=" + formatFloat(gBleedHome, "", 0, 0)
			+ " frac=" + formatFloat(ForwardBleedFrac(), "", 0, 2)
			+ " caution=" + formatFloat(BleedCaution(), "", 0, 2)
			+ " trade=" + formatFloat(TradeRatio(), "", 0, 2)
			+ (TradeBad() ? " BAD" : "")
			+ " armyMult=" + formatFloat(LossArmyMult(), "", 0, 2)
			+ " by[stat/air/mob]=" + formatFloat(gDeadToStatic, "", 0, 0)
			+ "/" + formatFloat(gDeadToAir, "", 0, 0)
			+ "/" + formatFloat(gDeadToMobile, "", 0, 0));
	}
}

}  // namespace Military
