namespace Military {

// THE ARMY'S SHAPE AS CONTINUOUS HEADS (his 10-14: squad size, split, where the army stands,
// staging and the retreat point on the network; the default is one big army). Each on a 30 s
// clock per team, 1x being the rule. Ranges are log-symmetric about 1, so a policy head whose
// outputs are all 0 (its log-middle) plays exactly the rule.
// split   -- C++: how far the main army pulls the other attack squads (x the map's diagonal) and,
//            above 1, the merge reach. Small = every squad its own, as before 10-14.
// commit  -- C++: the target hysteresis TGT_MARGIN (x v), and with it the commit window.
// stage   -- C++: the main army's and the push's stand-off short of a target, and the odds that
//            send it; script: the hunt's go odds.
// stand   -- script: the lane fractions (0.35 forward, 0.15 defensive) and the front lane's
//            distance from home.
// retreat -- the fall-back distances (C++ heal post 600, withdraw 220) x v; the outgunned odds
//            (1.5) and losing-trade ratio (3) / v. Above 1 retreats sooner and further.
const string NNSP_SPLIT = "atkPow,foeTop,foeMob,foeThr,ours,str,bleed,standing,squads,mainPow,mainShare,spread,"
	+ "mapD,quota,incoming,cur,minute";
const string NNCM_COMMIT = "atkPow,foeTop,foeMob,foeThr,ours,str,bleed,standing,squads,mainShare,switches,"
	+ "incoming,turtle,cur,minute";
const string NNSG_STAGE = "atkPow,foeTop,foeMob,foeThr,ours,str,bleed,standing,squads,mainShare,spread,"
	+ "holdWhy,incoming,push,cur,minute";
const string NNSD_STAND = "ours,foeMob,foeThr,str,bleed,standing,trade,tradeBad,laneFwd,holdWhy,incoming,"
	+ "turtle,allIn,cur,minute";
const string NNRT_RETREAT = "atkPow,foeTop,foeMob,foeThr,ours,str,bleed,standing,trade,tradeBad,laneFwd,"
	+ "incoming,turtle,cur,minute";
const float SP_LO = 0.125f, SP_HI = 8.f;
const float CM_LO = 0.25f, CM_HI = 4.f;
const float SG_LO = 0.25f, SG_HI = 4.f;
const float SD_LO = 0.4f, SD_HI = 2.5f;
const float RT_LO = 0.25f, RT_HI = 4.f;
// slots mirrored in C++ CMilitaryManager
const int BOARD_SPLIT = 1800, BOARD_COMMIT = 1900, BOARD_STAGE = 2500, BOARD_RETREAT = 2600;
const int BOARD_ARMY_N = 2700, BOARD_ARMY_MAIN = 2800, BOARD_ARMY_SPREAD = 2900, BOARD_ARMY_SW = 3000;
const int AH_EVERY = 30 * SECOND;
// these heads have no per-head net of their own: only the policy net decides them
const array<float> AH_NONE = {};

int gAhNextAt = -1;
int gAhLogAt = 0;
float gSplitMul = 1.f;
float gCommitMul = 1.f;
float gAhSwSeen = 0.f;
int gAhN = 0, gAhNoDll = 0, gAhNoArmy = 0;

float AhDecide(const string& in tag, const string& in own, float lo, float hi, const array<float>& in st,
	const array<float>& in f)
{
	return Market::NnValDecide(tag, own, lo, hi, 1.f, false, "", 0, 0, 0, AH_NONE, AH_NONE, AH_NONE, AH_NONE,
		AH_NONE, AH_NONE, AH_NONE, 0.f, 0.f, lo, hi, st, f);
}

void ArmyHeadsDecide()
{
	const bool acked = MilBoardAcked();
	array<float> st;
	Market::NnState(null, st);
	const float minute = float(ai.frame) / 1800.f;
	const float holdWhy = float(HoldWhy());
	const float incoming = PushIncoming() ? 1.f : 0.f;
	const float turtle = gTurtle ? 1.f : 0.f;
	const float squads = ai.GetTeamBoard(BOARD_ARMY_N + ai.teamId, 0.f);
	const float mainPow = ai.GetTeamBoard(BOARD_ARMY_MAIN + ai.teamId, 0.f);
	const float atkPow = aiMilitaryMgr.GetAttackPower();
	const float mainShare = (atkPow > 0.f) ? mainPow / atkPow : 0.f;
	const float spread = ai.GetTeamBoard(BOARD_ARMY_SPREAD + ai.teamId, 0.f);
	const float swAll = ai.GetTeamBoard(BOARD_ARMY_SW + ai.teamId, 0.f);
	const float switches = (swAll > gAhSwSeen) ? swAll - gAhSwSeen : 0.f;
	gAhSwSeen = swAll;
	const float w = float(AiTerrainWidth());
	const float h = float(AiTerrainHeight());
	const float trade = TradeRatio();
	const float tradeBad = TradeBad() ? 1.f : 0.f;
	const float laneFwd = OnMap(gLaneAt) ? ForwardFraction(gLaneAt) : 0.f;
	++gAhN;

	array<float> fd;
	MoCommon(fd);
	fd.insertLast(trade);
	fd.insertLast(tradeBad);
	fd.insertLast(laneFwd);
	fd.insertLast(incoming);
	fd.insertLast(turtle);
	fd.insertLast(gRetreatMul);
	fd.insertLast(minute);
	gRetreatMul = AhDecide("retreat", NNRT_RETREAT, RT_LO, RT_HI, st, fd);
	ai.SetTeamBoard(BOARD_RETREAT + ai.teamId, gRetreatMul);

	array<float> fs;
	fs.insertLast(OurArmyNow());
	fs.insertLast(FoeMobileMassing());
	fs.insertLast(aiEnemyMgr.mobileThreat);
	fs.insertLast(Market::StrRatio(FoeMobileMassing(), OurArmyNow()));
	fs.insertLast(BleedCaution());
	fs.insertLast(ArmyStandingRatio());
	fs.insertLast(trade);
	fs.insertLast(tradeBad);
	fs.insertLast(laneFwd);
	fs.insertLast(holdWhy);
	fs.insertLast(incoming);
	fs.insertLast(turtle);
	fs.insertLast(AllIn() ? 1.f : 0.f);
	fs.insertLast(gStandMul);
	fs.insertLast(minute);
	gStandMul = AhDecide("stand", NNSD_STAND, SD_LO, SD_HI, st, fs);

	array<float> fg;
	MoCommon(fg);
	fg.insertLast(squads);
	fg.insertLast(mainShare);
	fg.insertLast(spread);
	fg.insertLast(holdWhy);
	fg.insertLast(incoming);
	AIFloat3 pushAt;
	float pushR = 0.f;
	fg.insertLast(Market::PushGoAt(pushAt, pushR) ? 1.f : 0.f);
	fg.insertLast(gStageMul);
	fg.insertLast(minute);
	gStageMul = AhDecide("stage", NNSG_STAGE, SG_LO, SG_HI, st, fg);
	ai.SetTeamBoard(BOARD_STAGE + ai.teamId, gStageMul);

	if (!acked) {
		++gAhNoDll;
		return;
	}
	array<float> fp;
	MoCommon(fp);
	fp.insertLast(squads);
	fp.insertLast(mainPow);
	fp.insertLast(mainShare);
	fp.insertLast(spread);
	fp.insertLast(sqrt(w * w + h * h));
	fp.insertLast(aiMilitaryMgr.quota.attack);
	fp.insertLast(incoming);
	fp.insertLast(gSplitMul);
	fp.insertLast(minute);
	gSplitMul = AhDecide("split", NNSP_SPLIT, SP_LO, SP_HI, st, fp);
	ai.SetTeamBoard(BOARD_SPLIT + ai.teamId, gSplitMul);

	array<float> fc;
	MoCommon(fc);
	fc.insertLast(squads);
	fc.insertLast(mainShare);
	fc.insertLast(switches);
	fc.insertLast(incoming);
	fc.insertLast(turtle);
	fc.insertLast(gCommitMul);
	fc.insertLast(minute);
	gCommitMul = AhDecide("commit", NNCM_COMMIT, CM_LO, CM_HI, st, fc);
	ai.SetTeamBoard(BOARD_COMMIT + ai.teamId, gCommitMul);
}

void UpdateArmyHeads()
{
	if (!Builder::gHomeSet)
		return;
	if (gAhNextAt < 0)
		gAhNextAt = 60 * SECOND + (ai.teamId % 15) * 4 * SECOND + 2 * SECOND;
	if (ai.frame >= gAhNextAt) {
		gAhNextAt = ai.frame + AH_EVERY;
		if (OurArmyNow() > 1.f)
			ArmyHeadsDecide();
		else
			++gAhNoArmy;
	}
	if (ai.frame >= gAhLogAt) {
		gAhLogAt = ai.frame + 60 * SECOND;
		if (gAhN + gAhNoArmy > 0)
			AiLog(Factory::T() + "apex: armyheads-stat t=" + ai.teamId + " n=" + gAhN + " noDll=" + gAhNoDll
				+ " noArmy=" + gAhNoArmy + " split=" + Market::NnF(gSplitMul, 2) + " commit=" + Market::NnF(gCommitMul, 2)
				+ " stage=" + Market::NnF(gStageMul, 2) + " stand=" + Market::NnF(gStandMul, 2)
				+ " retreat=" + Market::NnF(gRetreatMul, 2)
				+ " squads=" + int(ai.GetTeamBoard(BOARD_ARMY_N + ai.teamId, 0.f))
				+ " spread=" + int(ai.GetTeamBoard(BOARD_ARMY_SPREAD + ai.teamId, 0.f)));
	}
}

}  // namespace Military
