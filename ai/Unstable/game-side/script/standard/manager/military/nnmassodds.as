namespace Military {

// TWO PRIORS AS RECORDED DECISIONS (docs/24 section 7), each on a 60 s clock
// per team, the rule option being today's play.
// nnmass -- how big a pool must be before it leaves: x0.5 / x1 / x2 on the bar
//           UpdateMassing sets (quota.attack); with the DLL also on the
//           biggest-enemy-group term of the C++ promotion bar.
// nnodds -- the odds an attack squad needs: x0.5 / x1 / x2 on the enemy
//           influence CAttackTask::FindTarget refuses against. C++ only, so it
//           records nothing until the DLL acknowledges the team board.
const string NNM_MASS = "base,floor,quota,ownPow,atkPow,foeTop,foeMob,foeThr,ours,str,bleed,standing,"
	+ "holdWhy,incoming,turtle,cur,minute";
const string NNO_ODDS = "atkPow,foeTop,foeMob,foeThr,ours,str,bleed,standing,quota,"
	+ "holdWhy,incoming,turtle,push,cur,minute";
const int MO_HALF = 0, MO_ONE = 1, MO_TWO = 2;
const array<float> MO_MUL = {0.5f, 1.f, 2.f};
// slots mirrored in C++ CMilitaryManager (BOARD_ODDS / BOARD_MASS / BOARD_MIL_ACK)
const int BOARD_ODDS = 1400, BOARD_MASS = 1500, BOARD_MIL_ACK = 1600;
const int MO_EVERY = 60 * SECOND;

int gMoNextAt = -1;
int gMoLogAt = 0;
bool gMoHeader = false;
float gOddsMul = 1.f;
int gMoMassN = 0, gMoOddsN = 0, gMoExN = 0, gMoNoDll = 0, gMoNoArmy = 0;
array<int> gMoMassPick(3, 0);
array<int> gMoOddsPick(3, 0);

bool MilBoardAcked()
{
	const float ack = ai.GetTeamBoard(BOARD_MIL_ACK + ai.teamId, -1.f);
	return (ack >= 0.f) && (float(ai.frame) - ack < float(15 * SECOND));
}

void MoCommon(array<float>& f)
{
	const float foeMob = FoeMobileMassing();
	const float ours = OurArmyNow();
	f.insertLast(aiMilitaryMgr.GetAttackPower());
	f.insertLast(EnemyGroupPower());
	f.insertLast(foeMob);
	f.insertLast(aiEnemyMgr.mobileThreat);
	f.insertLast(ours);
	f.insertLast(Market::StrRatio(foeMob, ours));
	f.insertLast(BleedCaution());
	f.insertLast(ArmyStandingRatio());
}

void MassOddsDecide()
{
	const bool acked = MilBoardAcked();
	if (!gMoHeader) {
		gMoHeader = true;
		AiLog("apex: nnmass-schema v1 state=" + Market::NN_STATE + " mass=" + NNM_MASS + " opt=name,w,p opts=X05,X1,X2");
		AiLog("apex: nnodds-schema v1 state=" + Market::NN_STATE + " odds=" + NNO_ODDS + " opt=name,w,p opts=X05,X1,X2");
	}
	array<float> st;
	Market::NnState(null, st);
	array<string> names = {"X05", "X1", "X2"};
	const float minute = float(ai.frame) / 1800.f;
	const float holdWhy = float(HoldWhy());
	const float incoming = PushIncoming() ? 1.f : 0.f;
	const float turtle = gTurtle ? 1.f : 0.f;

	array<float> fm;
	fm.insertLast(gMassBase);
	fm.insertLast(MassFloor());
	fm.insertLast(aiMilitaryMgr.quota.attack);
	fm.insertLast(aiMilitaryMgr.armyCost * 0.017f);
	MoCommon(fm);
	fm.insertLast(holdWhy);
	fm.insertLast(incoming);
	fm.insertLast(turtle);
	fm.insertLast(gMassMul);
	fm.insertLast(minute);
	array<float> wm(3, Market::NE2_EPS);
	wm[MO_ONE] = 1.f;
	const float tm = Market::NnHeadScore(Market::NNM_ON, Market::NNM_STATE, NNM_MASS, Market::NNM_S, Market::NNM_O,
		Market::NNM_H, Market::NNM_XM, Market::NNM_XS, Market::NNM_W1, Market::NNM_B1, Market::NNM_W2, Market::NNM_B2,
		Market::NNM_WO, Market::NNM_BO, Market::NNM_TRUST, st, fm, wm);
	array<float> pm(3);
	const float flatM = Market::NnHeadFlat(tm);
	const int cm = Market::EcoDraw(MO_ONE, tm, wm, pm, flatM);
	AiLog(Market::EcoLine("nnmass", "X1", flatM > 0.f, tm, st, fm, names, wm, pm, cm));
	gMassMul = MO_MUL[cm];
	ai.SetTeamBoard(BOARD_MASS + ai.teamId, gMassMul);
	++gMoMassN;
	++gMoMassPick[cm];
	if (flatM > 0.f)
		++gMoExN;

	if (!acked) {
		++gMoNoDll;
		return;
	}
	array<float> fo;
	MoCommon(fo);
	fo.insertLast(aiMilitaryMgr.quota.attack);
	fo.insertLast(holdWhy);
	fo.insertLast(incoming);
	fo.insertLast(turtle);
	AIFloat3 pushAt;
	float pushR = 0.f;
	fo.insertLast(Market::PushGoAt(pushAt, pushR) ? 1.f : 0.f);
	fo.insertLast(gOddsMul);
	fo.insertLast(minute);
	array<float> wo(3, Market::NE2_EPS);
	wo[MO_ONE] = 1.f;
	const float to = Market::NnHeadScore(Market::NNO_ON, Market::NNO_STATE, NNO_ODDS, Market::NNO_S, Market::NNO_O,
		Market::NNO_H, Market::NNO_XM, Market::NNO_XS, Market::NNO_W1, Market::NNO_B1, Market::NNO_W2, Market::NNO_B2,
		Market::NNO_WO, Market::NNO_BO, Market::NNO_TRUST, st, fo, wo);
	array<float> po(3);
	const float flatO = Market::NnHeadFlat(to);
	const int co = Market::EcoDraw(MO_ONE, to, wo, po, flatO);
	AiLog(Market::EcoLine("nnodds", "X1", flatO > 0.f, to, st, fo, names, wo, po, co));
	gOddsMul = MO_MUL[co];
	ai.SetTeamBoard(BOARD_ODDS + ai.teamId, gOddsMul);
	++gMoOddsN;
	++gMoOddsPick[co];
	if (flatO > 0.f)
		++gMoExN;
}

void UpdateMassOdds()
{
	if (!Builder::gHomeSet)
		return;
	if (gMoNextAt < 0)
		gMoNextAt = 60 * SECOND + (ai.teamId % 15) * 4 * SECOND;
	if (ai.frame >= gMoNextAt) {
		gMoNextAt = ai.frame + MO_EVERY;
		if (OurArmyNow() > 1.f)
			MassOddsDecide();
		else
			++gMoNoArmy;
	}
	if (ai.frame >= gMoLogAt) {
		gMoLogAt = ai.frame + 60 * SECOND;
		if (gMoMassN + gMoNoArmy > 0)
			AiLog(Factory::T() + "apex: massodds-stat t=" + ai.teamId + " mass=" + gMoMassN
				+ " (" + gMoMassPick[0] + "/" + gMoMassPick[1] + "/" + gMoMassPick[2] + ") odds=" + gMoOddsN
				+ " (" + gMoOddsPick[0] + "/" + gMoOddsPick[1] + "/" + gMoOddsPick[2] + ") ex=" + gMoExN
				+ " noDll=" + gMoNoDll + " noArmy=" + gMoNoArmy + " massMul=" + Market::NnF(gMassMul, 2)
				+ " oddsMul=" + Market::NnF(gOddsMul, 2) + " quota=" + int(aiMilitaryMgr.quota.attack));
	}
}

}  // namespace Military
