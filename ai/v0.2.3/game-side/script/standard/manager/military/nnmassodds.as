namespace Military {

// TWO PRIORS AS CONTINUOUS HEADS (docs/24 section 7), each on a 60 s clock per
// team, 1x being today's play.
// mass -- how big a pool must be before it leaves: x v on the bar UpdateMassing
//         sets (quota.attack); with the DLL also on the biggest-enemy-group term
//         of the C++ promotion bar.
// odds -- the odds an attack squad needs: x v on the enemy influence
//         CAttackTask::FindTarget refuses against. C++ only, so it records
//         nothing until the DLL acknowledges the team board.
const string NNM_MASS = "base,floor,quota,ownPow,atkPow,foeTop,foeMob,foeThr,ours,str,bleed,standing,"
	+ "holdWhy,incoming,turtle,cur,minute";
const string NNO_ODDS = "atkPow,foeTop,foeMob,foeThr,ours,str,bleed,standing,quota,"
	+ "holdWhy,incoming,turtle,push,cur,minute";
const float MO_LO = 0.25f, MO_HI = 6.f;
// slots mirrored in C++ CMilitaryManager (BOARD_ODDS / BOARD_MASS / BOARD_MIL_ACK)
const int BOARD_ODDS = 1400, BOARD_MASS = 1500, BOARD_MIL_ACK = 1600;
const int MO_EVERY = 60 * SECOND;

int gMoNextAt = -1;
int gMoLogAt = 0;
float gOddsMul = 1.f;
int gMoMassN = 0, gMoOddsN = 0, gMoNoDll = 0, gMoNoArmy = 0;
int gMoMassOv = 0, gMoOddsOv = 0;

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
	array<float> st;
	Market::NnState(null, st);
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
	gMassMul = Market::NnValDecide("mass", NNM_MASS, MO_LO, MO_HI, 1.f, Market::NNM_ON, Market::NNM_STATE,
		Market::NNM_S, Market::NNM_O, Market::NNM_H, Market::NNM_XM, Market::NNM_XS, Market::NNM_W1, Market::NNM_B1,
		Market::NNM_W2, Market::NNM_B2, Market::NNM_WO, Market::NNM_BO, Market::NNM_TRUST, Market::NNM_LO,
		Market::NNM_HI, st, fm);
	ai.SetTeamBoard(BOARD_MASS + ai.teamId, gMassMul);
	++gMoMassN;
	if (gMassMul != 1.f)
		++gMoMassOv;

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
	gOddsMul = Market::NnValDecide("odds", NNO_ODDS, MO_LO, MO_HI, 1.f, Market::NNO_ON, Market::NNO_STATE,
		Market::NNO_S, Market::NNO_O, Market::NNO_H, Market::NNO_XM, Market::NNO_XS, Market::NNO_W1, Market::NNO_B1,
		Market::NNO_W2, Market::NNO_B2, Market::NNO_WO, Market::NNO_BO, Market::NNO_TRUST, Market::NNO_LO,
		Market::NNO_HI, st, fo);
	ai.SetTeamBoard(BOARD_ODDS + ai.teamId, gOddsMul);
	++gMoOddsN;
	if (gOddsMul != 1.f)
		++gMoOddsOv;
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
			AiLog(Factory::T() + "apex: massodds-stat t=" + ai.teamId + " mass=" + gMoMassN + " massOv=" + gMoMassOv
				+ " odds=" + gMoOddsN + " oddsOv=" + gMoOddsOv + " noDll=" + gMoNoDll + " noArmy=" + gMoNoArmy
				+ " massMul=" + Market::NnF(gMassMul, 2) + " oddsMul=" + Market::NnF(gOddsMul, 2)
				+ " quota=" + int(aiMilitaryMgr.quota.attack));
	}
}

}  // namespace Military
