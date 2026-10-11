namespace Military {

// THE ARMY'S POSTURE AS A DECISION (his 2026-10-05: the net should be able to
// form the whole counterattack). Every ~30 s, and when the rule's verdict
// changes or a push starts closing on home, the army picks DEFEND, HOLD,
// ATTACK or RAID by a draw, and an `apex: nnpost` line records the state, the
// weights, the odds and the pick. The default weights are the rule chain's own
// verdict; outside discovery games, with no trust in a net, the rule's pick
// runs with p=1 and nothing below changes behaviour (gPostOv stays -1).
// Carried out by the existing machinery: HoldReason/HoldHome (massing.as), the
// raid-promoting pool (hooks.as MassPoolTask), the lane anchor (posture.as).

const string NNP_POST = "armyM,armyFwd,atkM,raidM,defM,armyDist,foeGrpM,foeGrpFwd,foeGrpNet,"
	+ "foeGrpDist,foeGrps,incoming,homeCover,homeThreat,foeBaseM,foeBaseInfl,sep,str,strAll,"
	+ "quota,heldM,turtle,holdWhy";
// default weight of each option the rule did not pick: room for a net to tilt
const float POST_EPS = 0.01f;

int gPostRule = -1;        // the rule's verdict at the last decision
int gPostChosen = -1;
int gPostNextAt = -1;
int gPostLastAt = -999999;
int gPostTickAt = -1;
bool gPostIncoming = false;
bool gPostHeader = false;
bool gPostTurtleLift = false;
int gPostDecN = 0;
int gPostExploreN = 0;
int gPostDevN = 0;
array<int> gPostChosenN(POST_N, 0);
array<int> gPostRuleN(POST_N, 0);
array<int> gPostEffF(POST_N, 0);   // frames spent under each effective posture
double gPostUsSum = 0.0;
double gPostUsMax = 0.0;
double gPostUsMaxState = 0.0;
double gPostUsState = 0.0;   // of the sum: the shared state vector
double gPostUsPost = 0.0;    // ... the posture fields (the rest is the log line)
int gPostureLogAt = 0;

string PostName(int o)
{
	if (o == POST_DEFEND) return "DEFEND";
	if (o == POST_HOLD) return "HOLD";
	if (o == POST_ATTACK) return "ATTACK";
	if (o == POST_RAID) return "RAID";
	return "-";
}

int PostOverride()
{
	if ((gPostOv < 0) || AllIn())
		return -1;
	return gPostOv;
}

bool PostHolds(int o)
{
	return (o == POST_DEFEND) || (o == POST_HOLD);
}

// What today's rule chain does: the turtle and the stance hold stand at the
// lane, a hit/contested/raided base holds home against it, otherwise attack.
// Today's rules never send the main army raiding.
int PostRule()
{
	if (gTurtle)
		return POST_HOLD;
	const int why = HoldWhy();
	if (why < 0)
		return POST_ATTACK;
	return (why == 3) ? POST_HOLD : POST_DEFEND;
}

// Our ground army by where it stands and what it is doing, metal-weighted.
float gPaM = 0.f, gPaFwd = 0.f, gPaAtk = 0.f, gPaRaid = 0.f, gPaDef = 0.f, gPaDist = -1.f;

void PostArmyCensus(const AIFloat3& in foe)
{
	float m = 0.f, fwd = 0.f, atk = 0.f, raid = 0.f, def = 0.f, cx = 0.f, cz = 0.f;
	for (uint i = 0; i < gCombatId.length(); ++i) {
		CCircuitUnit@ u = ai.GetTeamUnit(Id(gCombatId[i]));
		if ((u is null) || (u.circuitDef is null) || u.circuitDef.IsAbleToFly())
			continue;
		const AIFloat3 p = u.GetPos(ai.frame);
		if (!OnMap(p))
			continue;
		const float c = u.circuitDef.costM;
		m += c;
		fwd += c * ForwardFraction(p);
		cx += c * p.x;
		cz += c * p.z;
		IUnitTask@ t = u.task;
		if ((t is null) || (t.GetType() != Task::Type::FIGHTER))
			continue;
		const int ft = t.GetFightType();
		if (ft == int(Task::FightType::ATTACK))
			atk += c;
		else if (ft == int(Task::FightType::RAID))
			raid += c;
		else if (ft == int(Task::FightType::DEFEND))
			def += c;
	}
	gPaM = m;
	gPaFwd = (m > 0.f) ? fwd / m : 0.f;
	gPaAtk = atk;
	gPaRaid = raid;
	gPaDef = def;
	gPaDist = ((m > 0.f) && OnMap(foe)) ? AIFloat3(cx / m, 0.f, cz / m).distance2D(foe) : -1.f;
}

// Their biggest MOBILE group (a group whose fastest member stands still is
// buildings).
bool PostFoeGroup(AIFloat3& out at, float& out cost, int& out n)
{
	bool have = false;
	cost = 0.f;
	n = aiEnemyMgr.GetEnemyGroupCount();
	for (int i = 0; i < n; ++i) {
		if (aiEnemyMgr.GetEnemyGroupVel(i) <= 0.f)
			continue;
		const AIFloat3 gp = aiEnemyMgr.GetEnemyGroupPos(i);
		if (!OnMap(gp))
			continue;
		const float c = aiEnemyMgr.GetEnemyGroupCost(i);
		if (!have || (c > cost)) {
			have = true;
			cost = c;
			at = gp;
		}
	}
	return have;
}

void PostFields(array<float>& out f)
{
	const AIFloat3 home = Builder::gHomePos;
	const AIFloat3 foe = Front::FoeAnchor();
	const bool foeOn = OnMap(foe);
	PostArmyCensus(foe);
	AIFloat3 gp;
	float gm = 0.f;
	int nG = 0;
	const bool grp = PostFoeGroup(gp, gm, nG);
	f.resize(0);
	f.insertLast(gPaM);
	f.insertLast(gPaFwd);
	f.insertLast(gPaAtk);
	f.insertLast(gPaRaid);
	f.insertLast(gPaDef);
	f.insertLast(gPaDist);
	f.insertLast(gm);
	f.insertLast(grp ? ForwardFraction(gp) : -1.f);
	f.insertLast(grp ? ai.GetNetInflAt(gp) : 0.f);
	f.insertLast(grp ? gp.distance2D(home) : -1.f);
	f.insertLast(float(nG));
	f.insertLast(PushIncoming() ? IncomingCost() : 0.f);
	f.insertLast(Market::CoverAt(home));
	f.insertLast(Market::ThreatM(home));
	f.insertLast(foeOn ? aiEnemyMgr.GetEnemyStructCostAt(foe, Builder::BASE_DANGER_DIST) : 0.f);
	f.insertLast(foeOn ? ai.GetEnemyInflAt(foe) : 0.f);
	f.insertLast(foeOn ? foe.distance2D(home) : -1.f);
	f.insertLast(Market::StrRatio(gm, gPaM));
	f.insertLast(Market::StrRatio(FoeMobileMassing(), OurArmyNow()));
	f.insertLast(aiMilitaryMgr.quota.attack);
	f.insertLast(gHoldHeldM);
	f.insertLast(gTurtle ? 1.f : 0.f);
	f.insertLast(float(HoldWhy()));
}

// The net's hook. The trainer will add NNP_* to nnweights.as; until then the
// default weights pass through and trust is 0.
// THE POSTURE NET (Market::NNP_*, written by tools/nntrain.py): it scores each
// option from the state, the posture fields, the option and what the rules
// chose, and mixes its policy into the rule's by the trust it has earned
// (Market::NnHeadMix). Returns that trust (0 = rules alone).
float NnPostScore(const array<float>& in st, const array<float>& in post, array<float>& w)
{
	const int pnh = Market::PnHead(NNP_POST);
	if (pnh >= 0) {
		Market::PnTilt(pnh, st, post, w);
		return 1.f;
	}
	float t =ai.GetTunable("apex_nn_blend", TUNE_NN_BLEND) * Market::NNP_TRUST;
	t = (t > 1.f) ? 1.f : t;
	const int S = Market::NNP_S, O = Market::NNP_O, H = Market::NNP_H, N = S + O;
	if ((t <= 0.f) || (Market::NN_TRUST_KIND < 2) || !Market::NNP_ON || (Market::NNP_STATE != Market::NN_STATE + "|" + NNP_POST)
		|| (O != 2 * POST_N) || (S != int(st.length() + post.length())) || (H <= 0)
		|| (Market::NNP_XM.length() != uint(N)) || (Market::NNP_W1.length() != uint(H * N))
		|| !Market::NnBlkOk(H, Market::NNP_W2.length()) || (Market::NNP_WO.length() != uint(H)))
		return 0.f;
	int rule = 0;
	for (int o = 1; o < POST_N; ++o)
		rule = (w[o] > w[rule]) ? o : rule;
	array<float> a(H);
	for (int h = 0; h < H; ++h)
		a[h] = Market::NNP_B1[h];
	for (int i = 0; i < S; ++i) {
		const float v = (uint(i) < st.length()) ? st[i] : post[i - st.length()];
		float z = (Market::NnSlog(v) - Market::NNP_XM[i]) / Market::NNP_XS[i];
		z = (z > 6.f) ? 6.f : ((z < -6.f) ? -6.f : z);
		for (int h = 0; h < H; ++h)
			a[h] += Market::NNP_W1[h * N + i] * z;
	}
	array<float> score(POST_N), h1(H);
	for (int o = 0; o < POST_N; ++o) {
		for (int h = 0; h < H; ++h)
			h1[h] = a[h];
		for (int i = 0; i < O; ++i) {
			const float x = (i < POST_N) ? ((i == o) ? 1.f : 0.f) : ((i - POST_N == rule) ? 1.f : 0.f);
			float z = (x - Market::NNP_XM[S + i]) / Market::NNP_XS[S + i];
			z = (z > 6.f) ? 6.f : ((z < -6.f) ? -6.f : z);
			for (int h = 0; h < H; ++h)
				h1[h] += Market::NNP_W1[h * N + S + i] * z;
		}
		float sc = Market::NNP_BO;
		for (int h2 = 0; h2 < H; ++h2) {
			float acc = Market::NNP_B2[h2];
			const int b0 = h2 - h2 % Market::NN_BLK;
			for (int j = 0; j < Market::NN_BLK; ++j) {
				if (h1[b0 + j] > 0.f)
					acc += Market::NNP_W2[h2 * Market::NN_BLK + j] * h1[b0 + j];
			}
			if (acc > 0.f)
				sc += Market::NNP_WO[h2] * acc;
		}
		score[o] = sc;
	}
	Market::NnHeadMix(score, t, w);
	return t;
}

void PostDecide(int rule, const string& in why)
{
	const double t0 = ai.ClockUs();
	array<float> st;
	Market::NnState(null, st);
	const double t1 = ai.ClockUs();
	array<float> post;
	PostFields(post);
	const double t2 = ai.ClockUs();
	gPostUsState += t1 - t0;
	gPostUsPost += t2 - t1;
	array<float> w(POST_N);
	for (int o = 0; o < POST_N; ++o)
		w[o] = (o == rule) ? 1.f : POST_EPS;
	const float trust0 = NnPostScore(st, post, w);
	// All in, no posture runs but the rule's (PostOverride): no draw to log.
	const bool allIn = AllIn();
	const float trust = allIn ? 0.f : trust0;
	const float flat = allIn ? 0.f : Market::NnHeadFlat();
	const bool explore = flat > 0.f;
	float sum = 0.f;
	for (int o = 0; o < POST_N; ++o)
		sum += w[o];
	array<float> p(POST_N);
	for (int o = 0; o < POST_N; ++o) {
		if (explore)
			p[o] = (1.f - flat) * w[o] / sum + flat / float(POST_N);
		else if (trust > 0.f)
			p[o] = w[o] / sum;
		else
			p[o] = (o == rule) ? 1.f : 0.f;
	}
	int chosen = rule;
	// No AiRandom on the rule's own one-hot: the shared RNG stream stays as it was.
	if (explore || (trust > 0.f)) {
		// AiRandom is rand() underneath: RAND_MAX is 32767 on Windows
		const float r = float(AiRandom(0, 10000)) / 10000.f;
		float acc = 0.f;
		chosen = POST_N - 1;
		for (int o = 0; o < POST_N; ++o) {
			acc += p[o];
			if (r < acc) {
				chosen = o;
				break;
			}
		}
	}
	// A drawn posture is held as drawn even when it is the rule's: the rule's
	// own HOLD/DEFEND cap the hold and follow the rule as it flips, so the
	// same name would run two ways and the row would not say which.
	gPostOv = (explore || (trust > 0.f)) ? chosen : -1;
	gPostRule = rule;
	gPostChosen = chosen;
	gPostLastAt = ai.frame;
	gPostNextAt = ai.frame + 30 * SECOND;
	++gPostDecN;
	++gPostChosenN[chosen];
	++gPostRuleN[rule];
	if (explore)
		++gPostExploreN;
	if (chosen != rule)
		++gPostDevN;

	if (!gPostHeader) {
		gPostHeader = true;
		AiLog("apex: nnpost-schema v1 state=" + Market::NN_STATE + " post=" + NNP_POST
			+ " opt=name,w,p opts=DEFEND,HOLD,ATTACK,RAID explore=" + (Market::gNnExplore ? 1 : 0)
			+ " net=-1");
	}
	string ln = "apex: nnpost t=" + ai.teamId + " f=" + ai.frame + " why=" + why
		+ " rule=" + PostName(rule) + " ex=" + (explore ? 1 : 0)
		+ " trust=" + Market::NnF(trust, 2) + " |";
	for (uint k = 0; k < st.length(); ++k)
		ln += ((k == 0) ? " " : ",") + Market::NnF(st[k], 2);
	ln += " |";
	for (uint k = 0; k < post.length(); ++k)
		ln += ((k == 0) ? " " : ",") + Market::NnF(post[k], 2);
	for (int o = 0; o < POST_N; ++o)
		ln += ((o == 0) ? " | " : " ; ") + PostName(o) + "," + Market::NnF(w[o], 4)
			+ "," + Market::NnF(p[o], 6);
	ln += " | chosen=" + chosen + " ov=" + gPostOv;
	AiLog(ln);
	const double us = ai.ClockUs() - t0;
	gPostUsSum += us;
	if (us > gPostUsMax) {
		gPostUsMax = us;
		gPostUsMaxState = t1 - t0;
	}
}

// A drawn DEFEND meets the push on our own ground: the group closing on home
// (or their biggest mobile group on our half), walked back toward home until
// the ground is ours. With nothing coming, the defensive lane.
bool PostAnchor(AIFloat3& out at)
{
	if ((PostOverride() != POST_DEFEND) || !Builder::gHomeSet)
		return false;
	const AIFloat3 home = Builder::gHomePos;
	AIFloat3 gp;
	bool have = false;
	if (PushIncoming() && OnMap(gIncomingPos)) {
		gp = gIncomingPos;
		have = true;
	} else {
		float gm = 0.f;
		int nG = 0;
		have = PostFoeGroup(gp, gm, nG) && (ForwardFraction(gp) < 0.5f);
	}
	if (!have) {
		const AIFloat3 e = aiEnemyMgr.GetEnemyPos();
		if (!OnMap(e))
			return false;
		gp = home + (e - home) * ai.GetTunable("apex_lane_defensive", TUNE_LANE_DEFENSIVE);
	}
	AIFloat3 toHome = home - gp;
	const float len = sqrt(toHome.SqLength2D());
	if (len > 1.f) {
		toHome *= (1.f / len);
		const float step = ai.GetTunable("apex_lane_back_step", TUNE_LANE_BACK_STEP);
		int steps = 0;
		while ((steps < 10) && OnMap(gp) && (float(steps) * step < len) && (ai.GetNetInflAt(gp) < 0.f)) {
			gp += toHome * step;
			++steps;
		}
	}
	at = gp;
	return OnMap(at);
}

void UpdateNnPost()
{
	if (!Builder::gHomeSet)
		return;
	const int rule = PostRule();
	const int ovNow = PostOverride();
	if (gPostTickAt >= 0) {
		const int eff = (ovNow >= 0) ? ovNow : rule;
		gPostEffF[eff] += ai.frame - gPostTickAt;
	}
	gPostTickAt = ai.frame;
	if (gPostNextAt < 0)
		gPostNextAt = 30 * SECOND + (ai.teamId % 15) * 2 * SECOND;
	const bool inc = PushIncoming();
	string why = "";
	if (ai.frame >= gPostNextAt)
		why = "clock";
	else if ((gPostOv >= 0) && AllIn())
		why = "allin";
	else if (ai.frame - gPostLastAt >= 5 * SECOND) {
		// A drawn deviation keeps its window: the rule chain flips every few
		// seconds while a base is raided, which cut deviations to 3 s.
		if ((gPostRule >= 0) && (rule != gPostRule) && (gPostOv < 0))
			why = "rule";
		else if (inc && !gPostIncoming)
			why = "incoming";
	}
	if (why != "") {
		gPostIncoming = inc;
		PostDecide(rule, why);
	}
	// An ATTACK or RAID drawn against the turtle needs the bar the turtle froze.
	const int ov = PostOverride();
	if (gTurtle && ((ov == POST_ATTACK) || (ov == POST_RAID))) {
		gPostTurtleLift = true;
		aiMilitaryMgr.quota.attack = MassWant() * gMassMul;
	} else if (gPostTurtleLift) {
		gPostTurtleLift = false;
		if (gTurtle)
			aiMilitaryMgr.quota.attack = TURTLE_ATTACK;
	}
	if (ai.frame >= gPostureLogAt) {
		gPostureLogAt = ai.frame + 60 * SECOND;
		if (gPostDecN == 0)
			return;
		PostArmyCensus(Front::FoeAnchor());
		string cn = "", rn = "", en = "";
		for (int o = 0; o < POST_N; ++o) {
			cn += ((o == 0) ? "" : "/") + gPostChosenN[o];
			rn += ((o == 0) ? "" : "/") + gPostRuleN[o];
			en += ((o == 0) ? "" : "/") + (gPostEffF[o] / SECOND);
		}
		AiLog(Factory::T() + "apex: posture t=" + ai.teamId + " dec=" + gPostDecN
			+ " explore=" + gPostExploreN + " dev=" + gPostDevN
			+ " chosen(D/H/A/R)=" + cn + " rule=" + rn + " effSec=" + en
			+ " now=" + PostName((ov >= 0) ? ov : rule) + " ruleNow=" + PostName(rule) + " ov=" + ov
			+ " | armyM=" + int(gPaM) + " fwd=" + formatFloat(gPaFwd, "", 0, 2)
			+ " atkM=" + int(gPaAtk) + " raidM=" + int(gPaRaid) + " defM=" + int(gPaDef)
			+ " quota=" + int(aiMilitaryMgr.quota.attack) + " heldM=" + int(gHoldHeldM)
			+ " | us avg=" + int(gPostUsSum / double(gPostDecN)) + " max=" + int(gPostUsMax) + "(state " + int(gPostUsMaxState) + ")"
			+ " state=" + int(gPostUsState / double(gPostDecN))
			+ " post=" + int(gPostUsPost / double(gPostDecN)));
	}
}

}  // namespace Military
