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

// A GANTRY IS NEVER RECLAIMED (his 2026-10-05: it is the reason for the
// economy -- reclaiming it for room and building eco in its place means a new
// gantry, and new converters to feed it, later). A plant at the top of the
// build tree is refused by every reclaim of a unit of ours.
int gGantryKeptN = 0;
bool GantryKept(CCircuitUnit@ u)
{
	if ((u is null) || (u.circuitDef is null))
		return false;
	const int d = int(u.circuitDef.id);
	if (!IsPlantDef(d) || (TreeTier(d) < gMaxTier) || (gMaxTier < 3))
		return false;
	if ((gGantryKeptN++ % 20) == 0)
		AiLog("apex: gantry-kept t=" + ai.teamId + " " + u.circuitDef.GetName() + " #" + u.id
			+ " refused=" + gGantryKeptN);
	return true;
}

int gTechTierAt = 0, gTechTierSeen = 0;  // the frame our top tier last rose
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
	if (gOwnTier > gTechTierSeen) {
		gTechTierSeen = gOwnTier;
		gTechTierAt = ai.frame;
	}
	return gOwnTier;
}

int gTechCur = -1;           // the decision in force: binding whichever answer was drawn
int gTechLogAt = 0;
int gTechNextAt = -1;
bool gTechHeader = false;
float gTechFlat = -1.f;      // discovery games: the head flat last applied (NnHeadFlat)
int gTechExpTier = -1, gTechExpAt = 0;   // discovery: the tier being timed and the moment drawn for it
int gTechDecN = 0, gTechDevN = 0, gTechHoistN = 0, gTechHeldN = 0;
// what the market did since the last decision
float gTwLabM = 0.f, gTwSeen = 0.f, gTwTop = 0.f, gTwPick = 0.f, gTwEl = 0.f, gTwV = 0.f, gTwTopV = 0.f;
float gTwEta = 0.f;   // elections whose ladder reached the target sooner through the plant, each at its funded share
int gTwNext = 0;   // the lowest tier above ours on offer
int gTechSkipN = 0;

string TechName(int o) { return (o == TECH_NOW) ? "NOW" : "WAIT"; }

// THE TEAM'S NEXT TIER (TUNE_TECH_PICK; his 10-17: an air lab is expensive, and quadrupling our metal
// income before making it is more economically efficient). The hoist moved ANY plant above our tier, so the
// T1 air con that asked first made the advanced air plant the T2 step at v=0.12 against a tower's 233
// (t2eco t1-comet-s145, why=nntech). The step is the next-tier plant we can start whose upgrade-capable
// builder brings build power for the least metal: the plant plus that builder, energy at our best
// conversion ratio. An air plant ordered first no longer counts as the next tier coming (T2LabComing).
int gTpOn = -1;
bool TechPickOn()
{
	if (gTpOn < 0)
		gTpOn = (ai.GetTunable("apex_tech_pick", TUNE_TECH_PICK) > 0.f) ? 1 : 0;
	return gTpOn > 0;
}
int gTpDef = -1, gTpAt = -1;
float TpCostEq(int d, float r)
{
	return Catalog::gCostM[d] + ((r > 0.f) ? Catalog::gCostE[d] * r : 0.f);
}
int TechPickDef()
{
	if (ai.frame < gTpAt)
		return gTpDef;
	gTpAt = ai.frame + 10 * SECOND;
	gTpDef = -1;
	const int next = OwnTopTier() + 1;
	const float r = BestConvRatio();
	float bestS = 0.f;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!Catalog::gAvailable[d] || !IsPlantDef(d) || (TreeTier(d) != next))
			continue;
		bool startable = false;
		const array<int>@ by = Catalog::gBuiltBy[d];
		for (uint i = 0; (i < by.length()) && !startable; ++i)
			startable = (by[i] < int(gOwnCount.length())) && (gOwnCount[by[i]] > 0);
		if (!startable)
			continue;
		const array<int>@ prods = Catalog::gBuildsList[d];
		for (uint p = 0; p < prods.length(); ++p) {
			const int b = prods[p];
			if (!Catalog::gAvailable[b] || !Catalog::gMobile[b] || !Catalog::gBuilder[b] || (Catalog::gBuildPower[b] <= 0.f))
				continue;
			bool upgrades = false;
			const array<int>@ bs = Catalog::gBuildsList[b];
			for (uint q = 0; (q < bs.length()) && !upgrades; ++q)
				upgrades = (Catalog::gExtractsM[bs[q]] > 0.f) && (TreeTier(bs[q]) >= next);
			if (!upgrades)
				continue;
			const float s = Catalog::gBuildPower[b] / (TpCostEq(d, r) + TpCostEq(b, r));
			if (s > bestS) {
				bestS = s;
				gTpDef = d;
			}
		}
	}
	return gTpDef;
}

bool IsTechPick(Want@ w)
{
	if (!IsT2Lab(w))
		return false;
	if (!TechPickOn())
		return true;
	const int pick = TechPickDef();
	return (pick < 0) || (int(w.def.id) == pick);
}

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
			&& (TreeTier(int(lt.buildDef.id)) > OwnTopTier())
			&& (!TechPickOn() || (TechPickDef() < 0) || (int(lt.buildDef.id) == TechPickDef()))) {
			if (Requests::AbandonedAt(li)) {
				Requests::NoteOrderRelease(lt, Requests::gLiveAt[li], "t2lab", Requests::ORL_GATE);
				continue;
			}
			return true;
		}
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
	const bool mktNow = (gTwTop > 0.f) || (gTwPick > 0.f);
	const bool etaNow = gTwEta >= 1.f;
	T2EcoNoteWindow(mktNow, etaNow);
	const int rule = (mktNow || (etaNow && T2EcoOn())) ? TECH_NOW : TECH_WAIT;
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
	const float flat = NnHeadFlat();
	const bool explore = flat > 0.f;
	if (gNnExplore)
		gTechFlat = flat;
	array<float> p(TECH_N);
	for (int o = 0; o < TECH_N; ++o) {
		if ((trust > 0.f) || (flat > 0.f))
			p[o] = (1.f - flat) * w[o] / sum + flat / float(TECH_N);
		else
			p[o] = (o == rule) ? 1.f : 0.f;
	}
	int chosen = rule;
	if ((flat > 0.f) && (gTwNext < 2)) {
		const float r = float(AiRandom(0, 10000)) / 10000.f;
		chosen = (r < p[TECH_WAIT]) ? TECH_WAIT : TECH_NOW;
	} else if (trust > 0.f) {
		chosen = NnTop(p, rule);
		NnOneHot(p, chosen);
	}
	// DISCOVERY TRIES A TIME, NOT A COIN: a flip every 30 s sent nearly every
	// discovery game to T2 within two minutes. Each discovery game, trusted net or not, draws one
	// moment 2-15 min after reaching its current tier and switches there --
	// earlier or later than the rule would -- so similar games differ only in
	// when. Never for the first plant (tier 1): that is never held back.
	if (explore && (gTwNext >= 2)) {
		if (gTechExpTier != gTwNext) {
			gTechExpTier = gTwNext;
			gTechExpAt = gTechTierAt + int((2.f + 13.f * float(AiRandom(0, 10000)) / 10000.f) * float(MINUTE));
		}
		chosen = (ai.frame >= gTechExpAt) ? TECH_NOW : TECH_WAIT;
		p[TECH_NOW] = (chosen == TECH_NOW) ? 1.f : 0.f;
		p[TECH_WAIT] = 1.f - p[TECH_NOW];
	}
	gTechCur = chosen;
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
	gTwLabM = gTwSeen = gTwTop = gTwPick = gTwEl = gTwV = gTwTopV = gTwEta = 0.f;
	gTwNext = 0;
}

// After the market and the nets ranked an election: note what it offered, run
// the decision on its clock, and take the lab off the table under WAIT.
void NnTechNote(array<Want@>@ ranked)
{
	if (!TechOpen() || (ranked.length() == 0)) {
		gTechCur = -1;
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
			gTwLabM = gTwSeen = gTwTop = gTwPick = gTwEl = gTwV = gTwTopV = gTwEta = 0.f;
			gTwNext = 0;
		}
		if (ai.frame >= gTechLogAt) {
			gTechLogAt = ai.frame + 60 * SECOND;
			AiLog("apex: nntech-stat t=" + ai.teamId + " dec=" + gTechDecN + " dev=" + gTechDevN
				+ " cur=" + gTechCur + " hoist=" + gTechHoistN + " held=" + gTechHeldN
				+ " flat=" + NnF(gTechFlat, 2));
		}
	}
}

// After the draw: whether the market would have built the plant now (the
// rule's evidence), then WAIT keeps it from being built by any later path --
// the record must say what actually happened.
void NnTechPicked(array<Want@>@ ranked)
{
	if (!TechOpen() || (ranked.length() == 0))
		return;
	if (IsT2Lab(ranked[0]))
		gTwPick += 1.f;
	if (gTechCur != TECH_WAIT)
		return;
	for (int r = int(ranked.length()) - 1; r >= 0; --r) {
		if (IsT2Lab(ranked[r])) {
			ranked.removeAt(uint(r));
			++gTechHeldN;
		}
	}
}

// Ahead of the draw: NOW puts the lab first until one is under way. Returns
// true when it did, so the draw keeps it.
bool NnTechHoist(array<Want@>@ ranked)
{
	if (!TechOpen() || (ranked.length() == 0) || (gTechCur != TECH_NOW))
		return false;
	if (IsTechPick(ranked[0]))
		return true;
	if (T2LabComing()) {
		gTechCur = -1;
		return false;
	}
	for (uint r = 1; r < ranked.length(); ++r) {
		if (IsTechPick(ranked[r])) {
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
