namespace Market {
//------------------------------------------------------------------------------
// HE GOES DOWN WITH HIS SHIP (his 2026-10-10, docs/24): while the base is being
// destroyed and what defends it cannot win without him, he does not run -- he
// fights the attackers at the base, the D-gun on the heaviest. If the guns and
// army there hold on their own, he stays safe.
//
// Being destroyed: a structure of ours lost on home ground in the last 45 s
// (Military::BaseRaided) and an enemy ground army standing on home ground.
// Holding is the intercept's own test: StrRatio(their ground metal, the guns
// that reach them + our ground army within apex_threat_r) at his home parity.
//------------------------------------------------------------------------------

bool gShip = false;
AIFloat3 gShipAt;
int gShipG = -1;
int gShipHome = 0;
int gShipUnheld = 0;
float gShipFoeM = 0.f;
float gShipAtM = 0.f;
float gShipGuns = 0.f;
float gShipArmyM = 0.f;
float gShipStr = 0.f;
float gShipStrCom = 0.f;
bool gShipHopeless = false;
int gShipN = 0;
int gShipSec = 0;
int gShipFrom = -1;
int gShipLogAt = 0;
int gShipDgAt = 0;
float gShipRetWas = -1.f;
CCircuitDef@ gShipDef = null;
array<float> gCsX, gCsZ, gCsM;

bool ComShip() { return gShip; }

void ComShipCensus()
{
	gCsX.resize(0);
	gCsZ.resize(0);
	gCsM.resize(0);
	for (uint i = 0; i < Military::gCombatId.length(); ++i) {
		CCircuitUnit@ c = ai.GetTeamUnit(Id(Military::gCombatId[i]));
		if ((c is null) || (c.circuitDef is null) || c.circuitDef.IsAbleToFly())
			continue;
		const AIFloat3 p = c.GetPos(ai.frame);
		gCsX.insertLast(p.x);
		gCsZ.insertLast(p.z);
		gCsM.insertLast(c.circuitDef.costM);
	}
}

// A group of nothing but raiders and scouts outruns him; the guns answer those.
bool ShipAllRaiders(int g)
{
	const int nU = aiEnemyMgr.GetEnemyGroupUnitCount(g);
	for (int k = 0; k < nU; ++k) {
		const int d = aiEnemyMgr.GetEnemyGroupUnitDef(g, k);
		if (!Catalog::ValidId(d) || !Catalog::gMobile[d] || Catalog::gFlyer[d] || Catalog::gBuilder[d]
			|| (Catalog::gPower[d] <= 1.f))
			continue;
		if (!Catalog::Def(d).IsRoleAny(Unit::Role::RAIDER.mask | Unit::Role::SCOUT.mask))
			return false;
	}
	return true;
}

// The heaviest member of the group he is fighting, for the line.
string ShipHeavy()
{
	if ((gShipG < 0) || (gShipG >= aiEnemyMgr.GetEnemyGroupCount()))
		return "-";
	int best = -1, n = 0;
	const int nU = aiEnemyMgr.GetEnemyGroupUnitCount(gShipG);
	for (int k = 0; k < nU; ++k) {
		const int d = aiEnemyMgr.GetEnemyGroupUnitDef(gShipG, k);
		if (!Catalog::ValidId(d) || !Catalog::gMobile[d] || Catalog::gFlyer[d])
			continue;
		++n;
		if ((best < 0) || (Catalog::gPower[d] > Catalog::gPower[best]))
			best = d;
	}
	if (best < 0)
		return "-";
	return Catalog::Def(best).GetName() + "/" + n;
}

void ShipRetreatLine(CCircuitUnit@ u, bool on)
{
	if (on) {
		if (gShipDef !is null)
			return;
		@gShipDef = ai.GetCircuitDef(u.circuitDef.id);
		if (gShipDef is null)
			return;
		gShipRetWas = gShipDef.GetRetreat();
		gShipDef.SetRetreat(0.f);
	} else if (gShipDef !is null) {
		gShipDef.SetRetreat(gShipRetWas);
		@gShipDef = null;
	}
}

// Once a second from ComDecideTick; nothing to do unless the base is raided.
void ComShipAssess(CCircuitUnit@ u)
{
	const bool was = gShip;
	gShip = false;
	gShipHome = 0;
	gShipUnheld = 0;
	gShipFoeM = 0.f;
	gShipAtM = 0.f;
	gShipGuns = 0.f;
	gShipArmyM = 0.f;
	gShipStr = 0.f;
	gShipG = -1;
	if (Builder::gHomeSet && Military::BaseRaided()) {
		const float r = ai.GetTunable("apex_threat_r", TUNE_THREAT_R);
		const float r2 = r * r;
		bool census = false;
		const int nG = aiEnemyMgr.GetEnemyGroupCount();
		for (int g = 0; g < nG; ++g) {
			const AIFloat3 gp = aiEnemyMgr.GetEnemyGroupPos(g);
			if (!OnMap(gp) || (Military::ForwardFraction(gp) > Military::FWD_HOME))
				continue;
			float sl = 0.f;
			const float m = Military::GroundArmyOf(g, sl);
			if (m <= 0.f)
				continue;
			++gShipHome;
			gShipFoeM += m;
			if (ShipAllRaiders(g))
				continue;
			if (!census) {
				census = true;
				ComShipCensus();
			}
			float army = 0.f;
			for (uint i = 0; i < gCsX.length(); ++i) {
				const float dx = gCsX[i] - gp.x, dz = gCsZ[i] - gp.z;
				if (dx * dx + dz * dz <= r2)
					army += gCsM[i];
			}
			float guns = Military::GunsAt(gp);
			if (guns < 0.f)
				guns = 0.f;
			const float str = StrRatio(m, guns + army);
			const bool held = str * Military::ANSWER_PARITY <= 1.f;
			if (!held)
				++gShipUnheld;
			// his target is the heaviest group not held; the line shows the
			// heaviest held one when none is
			const bool better = held ? ((gShipUnheld == 0) && (m > gShipAtM))
				: ((gShipUnheld == 1) || (m > gShipAtM));
			if (!better)
				continue;
			gShipAtM = m;
			gShipAt = gp;
			gShipG = g;
			gShipGuns = guns;
			gShipArmyM = army;
			gShipStr = str;
		}
	}
	gShip = gShipUnheld > 0;
	gShipStrCom = 0.f;
	if (gShipAtM > 0.f) {
		const float ours = (gShipGuns + gShipArmyM) * OurQualityM()
			+ UnitStrength(int(u.circuitDef.id)) * u.GetHealthPercent();
		gShipStrCom = (ours > 0.f) ? gShipAtM * FoeQualityM() / ours : 1e6f;
	}
	// a team game where even with him the base loses: he runs and rebuilds with the team
	// (his 10-10: "if it looks too hopeless -- run"); in a 1v1 he goes down with the ship
	gShipHopeless = gShip && (Military::AllyCount() > 0) && (gShipStrCom * Military::ANSWER_PARITY > 1.f);
	if (gShipHopeless)
		gShip = false;
	if (gShip) {
		++gShipSec;
		ai.PublishTeamValue("comship", float(ai.frame));
		ShipRetreatLine(u, true);
	} else {
		ShipRetreatLine(u, false);
	}
	if (gShip && !was) {
		++gShipN;
		gShipFrom = ai.frame;
	}
	const bool edge = gShip != was;
	if ((gShipHome > 0 || edge) && (edge || (ai.frame >= gShipLogAt))) {
		gShipLogAt = ai.frame + 10 * SECOND;
		const int dgo = u.DGunOrders();
		AiLog(Factory::T() + "apex: com-ship t=" + ai.teamId
			+ " dying=" + (Military::BaseRaided() ? ("yes raidM=" + int(Military::gRaidM)) : "no")
			+ " decision=" + (gShip ? "STEP-IN" : (gShipHopeless ? "RUN-hopeless" : ((gShipHome > 0) ? "SAFE-held" : "SAFE-gone")))
			+ " foeM=" + int(gShipFoeM) + " homeGroups=" + gShipHome + " unheld=" + gShipUnheld
			+ " tgtM=" + int(gShipAtM) + " heavy=" + ShipHeavy()
			+ " defM=" + int(gShipGuns + gShipArmyM) + " (guns=" + int(gShipGuns) + " army=" + int(gShipArmyM) + ")"
			+ " str=" + formatFloat(gShipStr, "", 0, 2) + " strCom=" + formatFloat(gShipStrCom, "", 0, 2)
			+ " parity=" + formatFloat(Military::ANSWER_PARITY, "", 0, 1)
			+ " flips=" + ((gShip && (gShipStrCom * Military::ANSWER_PARITY <= 1.f)) ? 1 : 0)
			+ " dec=" + ComOptName(gComDec) + " hp=" + int(u.GetHealthPercent() * 100.f)
			+ " dgReady=" + (u.DGunReady(ai.frame, Eco::ECur()) ? 1 : 0)
			+ " dgOrders=" + (dgo - gShipDgAt) + " e=" + int(Eco::ECur()) + "/" + int(Eco::EInc() - Eco::EPull())
			+ " cloakAsk=" + (gShip ? 1 : 0)
			+ " homeD=" + int(u.GetPos(ai.frame).distance2D(Builder::gHomePos))
			+ ((gShip && OnMap(gShipAt)) ? (" tgtD=" + int(u.GetPos(ai.frame).distance2D(gShipAt))) : "")
			+ " retreat=" + formatFloat(u.circuitDef.GetRetreat(), "", 0, 2)
			+ ((!gShip && was) ? (" secs=" + ((ai.frame - gShipFrom) / SECOND)) : "")
			+ " n=" + gShipN);
		gShipDgAt = dgo;
	}
}

}  // namespace Market
