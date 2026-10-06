// THE T2 DECISION (his 2026-10-05: "is building T2 right now a good idea? and
// later we discover, was it?"). Until an advanced lab stands, every 30 s:
// NOW or WAIT. The rule's pick is what the market did in the window (a T2 lab
// at the top of an election); the T2 net (NNT_*) moves it once it has earned
// trust, and discovery games mix in a per-game share of the other answer so
// both timings get seen in similar states. NOW hoists the lab until one is
// under way; WAIT takes it off the table for the window.
namespace Market {

const string NNT_TECH = "labM,techSeen,techTop,techPick,elN,techV,topV,minute";
const int TECH_WAIT = 0, TECH_NOW = 1, TECH_N = 2;
const float TECH_EPS = 0.01f;

int gTechOv = -1;            // the decision in force when it differs from the rule
int gTechLogAt = 0;
int gTechNextAt = -1;
bool gTechHeader = false;
float gTechFlat = -1.f;      // discovery games: share of the uniform draw, rolled once
int gTechDecN = 0, gTechDevN = 0, gTechHoistN = 0, gTechHeldN = 0;
// what the market did since the last decision
float gTwLabM = 0.f, gTwSeen = 0.f, gTwTop = 0.f, gTwPick = 0.f, gTwEl = 0.f, gTwV = 0.f, gTwTopV = 0.f;

string TechName(int o) { return (o == TECH_NOW) ? "NOW" : "WAIT"; }

bool IsT2Lab(Want@ w)
{
	return (w !is null) && (w.kind == WK_TECH) && (w.def !is null) && (PlantTier(int(w.def.id)) >= 2);
}

bool T2LabComing()
{
	for (uint li = 0; li < Requests::gLive.length(); ++li) {
		IUnitTask@ lt = Requests::gLive[li];
		if ((lt !is null) && !lt.IsDead() && (lt.buildDef !is null)
			&& (Catalog::gBuildsList[int(lt.buildDef.id)].length() > 0)
			&& !Catalog::gMobile[int(lt.buildDef.id)] && (PlantTier(int(lt.buildDef.id)) >= 2))
			return true;
	}
	return false;
}

bool TechOpen()
{
	return TopOwnPlantTier() < 2;
}

float NnTechScore(const array<float>& in st, const array<float>& in f, array<float>& w)
{
	return NnHeadScore(NNT_ON, NNT_STATE, NNT_TECH, NNT_S, NNT_O, NNT_H, NNT_XM, NNT_XS, NNT_W1,
		NNT_B1, NNT_W2, NNT_B2, NNT_WO, NNT_BO, NNT_TRUST, st, f, w);
}

void NnTechDecide()
{
	const int rule = ((gTwTop > 0.f) || (gTwPick > 0.f)) ? TECH_NOW : TECH_WAIT;
	const bool explore = gNnExploreRolled && gNnExplore;
	if (explore && (gTechFlat < 0.f))
		gTechFlat = float(AiRandom(0, 10000)) / 10000.f * 0.3f;
	array<float> st;
	NnState(null, st);
	const float techV = (gTwSeen > 0.f) ? gTwV / gTwSeen : 0.f;
	const float topV = (gTwEl > 0.f) ? gTwTopV / gTwEl : 0.f;
	array<float> tf;
	tf.insertLast(gTwLabM);
	tf.insertLast(gTwSeen);
	tf.insertLast(gTwTop);
	tf.insertLast(gTwPick);
	tf.insertLast(gTwEl);
	tf.insertLast(techV);
	tf.insertLast(topV);
	tf.insertLast(float(ai.frame) / 1800.f);
	array<float> w(TECH_N);
	for (int o = 0; o < TECH_N; ++o)
		w[o] = (o == rule) ? 1.f : TECH_EPS;
	const float trust = NnTechScore(st, tf, w);
	float sum = 0.f;
	for (int o = 0; o < TECH_N; ++o)
		sum += w[o];
	const float flat = explore ? gTechFlat : 0.f;
	array<float> p(TECH_N);
	for (int o = 0; o < TECH_N; ++o) {
		if ((trust > 0.f) || (flat > 0.f))
			p[o] = (1.f - flat) * w[o] / sum + flat / float(TECH_N);
		else
			p[o] = (o == rule) ? 1.f : 0.f;
	}
	int chosen = rule;
	if ((trust > 0.f) || (flat > 0.f)) {
		const float r = float(AiRandom(0, 10000)) / 10000.f;
		chosen = (r < p[TECH_WAIT]) ? TECH_WAIT : TECH_NOW;
	}
	gTechOv = (chosen == rule) ? -1 : chosen;
	++gTechDecN;
	if (chosen != rule)
		++gTechDevN;
	if (!gTechHeader) {
		gTechHeader = true;
		AiLog("apex: nntech-schema v1 state=" + NN_STATE + " tech=" + NNT_TECH
			+ " opt=name,w,p opts=WAIT,NOW");
	}
	string ln = "apex: nntech t=" + ai.teamId + " f=" + ai.frame + " why=clock rule=" + TechName(rule)
		+ " ex=" + (explore ? 1 : 0) + " trust=" + NnF(trust, 2) + " |";
	for (uint k = 0; k < st.length(); ++k)
		ln += ((k == 0) ? " " : ",") + NnF(st[k], 2);
	ln += " |";
	for (uint k = 0; k < tf.length(); ++k)
		ln += ((k == 0) ? " " : ",") + NnF(tf[k], 3);
	for (int o = 0; o < TECH_N; ++o)
		ln += ((o == 0) ? " | " : " ; ") + TechName(o) + "," + NnF(w[o], 4) + "," + NnF(p[o], 6);
	ln += " | chosen=" + chosen;
	AiLog(ln);
	gTwLabM = gTwSeen = gTwTop = gTwPick = gTwEl = gTwV = gTwTopV = 0.f;
}

// After the market and the nets ranked an election: note what it offered, run
// the decision on its clock, and take the lab off the table under WAIT.
void NnTechNote(array<Want@>@ ranked)
{
	if (!TechOpen() || (ranked.length() == 0)) {
		gTechOv = -1;
		return;
	}
	gTwEl += 1.f;
	gTwTopV += ranked[0].value;
	bool seen = false;
	for (uint r = 0; r < ranked.length(); ++r) {
		if (!IsT2Lab(ranked[r]))
			continue;
		if (!seen) {
			seen = true;
			gTwSeen += 1.f;
			gTwV += ranked[r].value;
			gTwLabM = Catalog::gCostM[int(ranked[r].def.id)];
			if (r == 0)
				gTwTop += 1.f;
		}
	}
	if (gTechNextAt < 0)
		gTechNextAt = 60 * SECOND + (ai.teamId % 15) * 2 * SECOND;
	if ((ai.frame >= gTechNextAt) && !T2LabComing()) {
		gTechNextAt = ai.frame + 30 * SECOND;
		NnTechDecide();
		if (ai.frame >= gTechLogAt) {
			gTechLogAt = ai.frame + 60 * SECOND;
			AiLog("apex: nntech-stat t=" + ai.teamId + " dec=" + gTechDecN + " dev=" + gTechDevN
				+ " ov=" + gTechOv + " hoist=" + gTechHoistN + " held=" + gTechHeldN
				+ " flat=" + NnF(gTechFlat, 2));
		}
	}
	if (gTechOv == TECH_WAIT) {
		for (int r = int(ranked.length()) - 1; r >= 0; --r) {
			if (IsT2Lab(ranked[r])) {
				ranked.removeAt(uint(r));
				++gTechHeldN;
			}
		}
	}
}

// After the draw: whether the election finally went to a T2 lab.
void NnTechPicked(array<Want@>@ ranked)
{
	if (TechOpen() && (ranked.length() > 0) && IsT2Lab(ranked[0]))
		gTwPick += 1.f;
}

// Ahead of the draw: NOW puts the lab first until one is under way. Returns
// true when it did, so the draw keeps it.
bool NnTechHoist(array<Want@>@ ranked)
{
	if (!TechOpen() || (ranked.length() == 0) || (gTechOv != TECH_NOW))
		return false;
	if (IsT2Lab(ranked[0]))
		return true;
	if (T2LabComing()) {
		gTechOv = -1;
		return false;
	}
	for (uint r = 1; r < ranked.length(); ++r) {
		if (IsT2Lab(ranked[r])) {
			Want@ tw = ranked[r];
			ranked.removeAt(r);
			ranked.insertAt(0, tw);
			++gTechHoistN;
			return true;
		}
	}
	return false;
}

}  // namespace Market
