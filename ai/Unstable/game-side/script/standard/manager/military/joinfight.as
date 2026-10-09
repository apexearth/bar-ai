namespace Military {

// JOIN A FIGHT ONLY IF WE GET THERE IN TIME (apexearth 2026-10-08). C++
// (CAttackTask::FindTarget) asks when a squad's new target is where our side
// is already fighting; the net answers GO or STAY from the walk and the
// powers there. Its outcome is whether the squad arrived while the fight
// still raged: the record's "done" (decisions.py), so the objective credits
// a march that participated and not one that came too late. The rule is GO,
// which is what every squad did before.
const string NNV_REINF = "travelS,allyPow,foePow,ownPow,sideRatio,homeD,minute";
const int RF_GO = 0, RF_STAY = 1;
bool gRfHeader = false;
int gRfAsked = 0, gRfStay = 0, gRfIn = 0, gRfOver = 0, gRfLate = 0, gRfDied = 0;
int gRfLogAt = 0;
array<int> gRfLead;
array<AIFloat3> gRfAt;
array<int> gRfFrame;
array<int> gRfDeadline;

bool AiJoinFight(const AIFloat3& in at, float travelS, float allyPow, float foePow, float ownPow, int leaderId)
{
	if (!gRfHeader) {
		gRfHeader = true;
		AiLog("apex: nnreinf-schema v1 state=" + Market::NN_STATE + " reinf=" + NNV_REINF + " opt=name,w,p opts=GO,STAY");
	}
	array<float> st;
	Market::NnState(null, st);
	array<float> f;
	f.insertLast(travelS);
	f.insertLast(allyPow);
	f.insertLast(foePow);
	f.insertLast(ownPow);
	f.insertLast((ownPow + allyPow) / ((foePow > 1.f) ? foePow : 1.f));
	f.insertLast(Builder::gHomeSet ? at.distance2D(Builder::gHomePos) : 0.f);
	f.insertLast(float(ai.frame) / 1800.f);
	array<float> w(2, Market::NE2_EPS);
	w[RF_GO] = 1.f;
	const float trust = Market::NnHeadScore(Market::NNV_ON, Market::NNV_STATE, NNV_REINF, Market::NNV_S, Market::NNV_O,
		Market::NNV_H, Market::NNV_XM, Market::NNV_XS, Market::NNV_W1, Market::NNV_B1, Market::NNV_W2, Market::NNV_B2,
		Market::NNV_WO, Market::NNV_BO, Market::NNV_TRUST, st, f, w);
	array<float> p(2);
	const float flat = Market::NnHeadFlat();
	const int c = Market::EcoDraw(RF_GO, trust, w, p, flat);
	array<string> names = {"GO", "STAY"};
	AiLog(Market::EcoLine("nnreinf", "GO", flat > 0.f, trust, st, f, names, w, p, c));
	++gRfAsked;
	if (c != RF_GO) {
		++gRfStay;
		return false;
	}
	gRfLead.insertLast(leaderId);
	gRfAt.insertLast(at);
	gRfFrame.insertLast(ai.frame);
	gRfDeadline.insertLast(ai.frame + int((2.f * travelS + 30.f) * float(SECOND)));
	return true;
}

// Each GO's outcome: arrived while their power was still there (1), arrived
// after it was gone or never arrived in twice the walk (0), died on the way (0).
void JoinFightWatch()
{
	for (int i = int(gRfLead.length()) - 1; i >= 0; --i) {
		CCircuitUnit@ u = ai.GetTeamUnit(Id(gRfLead[i]));
		string why = "";
		int done = 0;
		if (u is null) {
			why = "died";
			++gRfDied;
		} else if (u.GetPos(ai.frame).distance2D(gRfAt[i]) <= 600.f) {
			const bool on = aiMilitaryMgr.GetEnemyInflNear(gRfAt[i], 800.f) > 0.f;
			done = on ? 1 : 0;
			why = on ? "in" : "over";
			if (on)
				++gRfIn;
			else
				++gRfOver;
		} else if (ai.frame > gRfDeadline[i]) {
			why = "late";
			++gRfLate;
		} else {
			continue;
		}
		AiLog("apex: nnreinf-done t=" + ai.teamId + " f=" + gRfFrame[i] + " done=" + done + " why=" + why);
		gRfLead.removeAt(i);
		gRfAt.removeAt(i);
		gRfFrame.removeAt(i);
		gRfDeadline.removeAt(i);
	}
	if (ai.frame >= gRfLogAt) {
		gRfLogAt = ai.frame + 60 * SECOND;
		if (gRfAsked > 0)
			AiLog(Factory::T() + "apex: reinf-stat t=" + ai.teamId + " asked=" + gRfAsked + " stay=" + gRfStay
				+ " in=" + gRfIn + " over=" + gRfOver + " late=" + gRfLate + " died=" + gRfDied
				+ " pending=" + gRfLead.length());
	}
}

}  // namespace Military
