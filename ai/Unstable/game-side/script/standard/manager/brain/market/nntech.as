// THE NEXT-TIER DECISION (his 2026-10-05: "is now the time to make the factory
// that offers us the next thing? and later we discover, was it?"). While a
// plant of a higher tier than any we own is on offer, every 30 s: NOW or WAIT.
// T2, T3, air -- one decision. The rule's pick is what the market did in the
// window (such a plant at the top of an election, or picked); the net (NNT_*)
// moves it once it has earned trust, and discovery games mix in a per-game
// share of the other answer so both timings get seen in similar states. NOW
// hoists the plant until one is under way; WAIT takes it off the table.
namespace Market {

const string NNT_TECH = "labM,techSeen,techTop,techPick,elN,techV,topV,minute,ownTier,nextTier";
const int TECH_WAIT = 0, TECH_NOW = 1, TECH_N = 2;
const float TECH_EPS = 0.01f;

// A plant's tier from the build tree alone, so a faction, mod or unit no
// config has heard of still has one: what a commander builds is tier 1; a
// constructor takes the tier of the plant that makes it; a plant no lower
// hand can build is one above the lowest hand that can. 0 = not a plant.
array<int> gDefTier;
int gMaxTier = 0;

bool IsPlantDef(int d)
{
	return (d >= 0) && (d < int(Catalog::gCostM.length())) && !Catalog::gMobile[d]
		&& (Catalog::gBuildsList[d].length() > 0) && (Catalog::gBuildPower[d] > 0.f)
		&& Catalog::gAvailable[d];
}

void TreeTierBuild()
{
	const int D = int(Catalog::gCostM.length());
	gDefTier.resize(D);
	array<int> hand(D);
	array<int> q;
	for (int d = 0; d < D; ++d) {
		gDefTier[d] = 0;
		hand[d] = 99;
		if (Catalog::gT1Hand[d] && !Catalog::gT1Line[d] && Catalog::gMobile[d] && (Catalog::gBuildsList[d].length() > 0)) {
			hand[d] = 0;
			q.insertLast(d);
		}
	}
	for (uint qi = 0; qi < q.length(); ++qi) {
		const int u = q[qi];
		const array<int>@ bl = Catalog::gBuildsList[u];
		if (Catalog::gMobile[u]) {
			for (uint k = 0; k < bl.length(); ++k) {
				const int b = bl[k];
				if (IsPlantDef(b) && ((gDefTier[b] == 0) || (gDefTier[b] > hand[u] + 1))) {
					gDefTier[b] = hand[u] + 1;
					q.insertLast(b);
				}
			}
		} else {
			for (uint k = 0; k < bl.length(); ++k) {
				const int b = bl[k];
				if (Catalog::gMobile[b] && (Catalog::gBuildsList[b].length() > 0) && (hand[b] > gDefTier[u])) {
					hand[b] = gDefTier[u];
					q.insertLast(b);
				}
			}
		}
	}
	for (int d = 0; d < D; ++d)
		gMaxTier = (gDefTier[d] > gMaxTier) ? gDefTier[d] : gMaxTier;
	array<int> per(gMaxTier + 1);
	string ex = "";
	int roots = 0;
	for (int d = 0; d < D; ++d) {
		per[gDefTier[d]] += 1;
		roots += (hand[d] == 0) ? 1 : 0;
		const CCircuitDef@ cd = Catalog::Def(d);
		if ((gDefTier[d] > 0) && (cd !is null) && (ex.length() < 160))
			ex += " " + cd.GetName() + "=" + gDefTier[d];
	}
	string pt = "";
	for (int t = 1; t <= gMaxTier; ++t)
		pt += ((t == 1) ? "" : "/") + per[t];
	AiLog("apex: def-tier t=" + ai.teamId + " defs=" + D + " roots=" + roots + " maxTier=" + gMaxTier
		+ " plants=" + pt + " |" + ex);
}

int TreeTier(int d)
{
	if (gDefTier.length() == 0)
		TreeTierBuild();
	return ((d >= 0) && (uint(d) < gDefTier.length())) ? gDefTier[d] : 0;
}

int gOwnTierAt = -1, gOwnTier = 0;
int OwnTopTier()
{
	if (ai.frame < gOwnTierAt)
		return gOwnTier;
	gOwnTierAt = ai.frame + 10 * SECOND;
	gOwnTier = 0;
	for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
		CCircuitUnit@ fu = Factory::gFacUnits[fi];
		if ((fu !is null) && (fu.circuitDef !is null)) {
			const int t = TreeTier(int(fu.circuitDef.id));
			gOwnTier = (t > gOwnTier) ? t : gOwnTier;
		}
	}
	return gOwnTier;
}

int gTechOv = -1;            // the decision in force when it differs from the rule
int gTechLogAt = 0;
int gTechNextAt = -1;
bool gTechHeader = false;
float gTechFlat = -1.f;      // discovery games: share of the uniform draw, rolled once
int gTechDecN = 0, gTechDevN = 0, gTechHoistN = 0, gTechHeldN = 0;
// what the market did since the last decision
float gTwLabM = 0.f, gTwSeen = 0.f, gTwTop = 0.f, gTwPick = 0.f, gTwEl = 0.f, gTwV = 0.f, gTwTopV = 0.f;
int gTwNext = 0;   // the lowest tier above ours on offer
int gTechSkipN = 0;

string TechName(int o) { return (o == TECH_NOW) ? "NOW" : "WAIT"; }

// the option this decision is about: a plant above every tier we own
bool IsT2Lab(Want@ w)
{
	return (w !is null) && (w.def !is null) && (TreeTier(int(w.def.id)) > OwnTopTier());
}

bool T2LabComing()
{
	for (uint li = 0; li < Requests::gLive.length(); ++li) {
		IUnitTask@ lt = Requests::gLive[li];
		if ((lt !is null) && !lt.IsDead() && (lt.buildDef !is null)
			&& (TreeTier(int(lt.buildDef.id)) > OwnTopTier()))
			return true;
	}
	return false;
}

bool TechOpen()
{
	return OwnTopTier() < gMaxTier;
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
	tf.insertLast(float(OwnTopTier()));
	tf.insertLast(float(gTwNext));
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
		AiLog("apex: nntech-schema v2 state=" + NN_STATE + " tech=" + NNT_TECH
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
	gTwNext = 0;
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
		const int nt = TreeTier(int(ranked[r].def.id));
		gTwNext = ((gTwNext == 0) || (nt < gTwNext)) ? nt : gTwNext;
	}
	if (gTechNextAt < 0)
		gTechNextAt = ai.frame + (ai.teamId % 15) * SECOND;
	if ((ai.frame >= gTechNextAt) && !T2LabComing()) {
		gTechNextAt = ai.frame + 30 * SECOND;
		// nothing of a higher tier on offer all window: no question to answer
		if (gTwSeen > 0.f)
			NnTechDecide();
		else {
			if (gTechSkipN++ < 3)
				AiLog("apex: nntech-skip t=" + ai.teamId + " el=" + int(gTwEl) + " own=" + OwnTopTier()
					+ " max=" + gMaxTier + " top=" + ((ranked[0].def is null) ? "-" : ranked[0].def.GetName())
					+ " topTier=" + ((ranked[0].def is null) ? -1 : TreeTier(int(ranked[0].def.id))));
			gTwLabM = gTwSeen = gTwTop = gTwPick = gTwEl = gTwV = gTwTopV = 0.f;
			gTwNext = 0;
		}
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
