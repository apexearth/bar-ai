namespace Market {

// THE POLICY NET (his 10-10): one network decides every head it lists -- the continuous values
// and the fixed-choice calls (strategy, tech, hunt, strike...). The live state goes through a
// shared hidden layer; each head adds its own decision's features through a hidden layer of
// its own. Weights are found by evolution, never by regression (tools/neuro.py): the file the
// per-AI option apex_pw_file names carries the candidate a game plays; without it PN_BEST (the
// all-time best, policydata.as) plays; with neither every weight is 0 -- every value at the log-middle
// of its range, every choice the rule's.

array<float> gPnW;
int gPnMode = -1;
array<int> gPnHOff;
array<int> gPnFOff;
array<float> gPnZ;
array<float> gPnA1;
int gPnA1At = -1;
array<float> gPnX;
array<float> gPnA2;

int PnHeadSize(int h)
{
	const int K = (PN_HK[h] > 0) ? PN_HK[h] : 1;
	return PN_H2 * (PN_H1 + PN_HF[h] + 1) + K * (PN_H2 + 1);
}

bool PnShapeOk()
{
	const uint H = PN_HEADS.length();
	if ((PN_STATE != NN_STATE) || (H == 0) || (PN_M.length() != PN_IDX.length())
		|| (PN_S.length() != PN_IDX.length()) || (PN_HK.length() != H) || (PN_HF.length() != H))
		return false;
	int nf = 0;
	for (uint h = 0; h < H; ++h)
		nf += PN_HF[h];
	return (PN_FM.length() == uint(nf)) && (PN_FS.length() == uint(nf));
}

bool PnOn()
{
	if (gPnMode >= 0)
		return gPnMode == 1;
	gPnMode = 0;
	if (ai.GetTunable("apex_policy", TUNE_POLICY) <= 0.f) {
		AiLog("apex: policy OFF t=" + ai.teamId + " (apex_policy=0)");
		return false;
	}
	if (!PnShapeOk()) {
		AiLog("apex: policy OFF t=" + ai.teamId + " layout=" + ((PN_STATE == NN_STATE) ? "ok" : "differs")
			+ " heads=" + PN_HEADS.length());
		return false;
	}
	const int N = int(PN_IDX.length());
	int n = PN_H1 * (N + 1), nf = 0;
	gPnHOff.resize(PN_HEADS.length());
	gPnFOff.resize(PN_HEADS.length());
	for (uint h = 0; h < PN_HEADS.length(); ++h) {
		gPnHOff[h] = n;
		gPnFOff[h] = nf;
		n += PnHeadSize(h);
		nf += PN_HF[h];
	}
	int nl = 0;
	gPnLOff.resize(PN_HEADS.length());
	for (uint h = 0; h < PN_HEADS.length(); ++h) {
		gPnLOff[h] = nl;
		nl += PnLeanSlots(h);
	}
	const int given = ai.LoadOptionFloats("apex_pw_file");
	gPnW.resize(n);
	string src = "middle";
	if ((given == n) || (given == n + nl) || (given == n + 3 * nl + 1)) {
		for (int i = 0; i < n; ++i)
			gPnW[i] = ai.OptionFloat(i);
		src = "file";
		if (given == n + 3 * nl + 1) {
			gPnTrained.resize(nl);
			gPnEvidence.resize(nl);
			for (int i = 0; i < nl; ++i) {
				gPnTrained[i] = ai.OptionFloat(n + nl + i);
				gPnEvidence[i] = ai.OptionFloat(n + 2 * nl + i);
			}
			gPnPairs = int(ai.OptionFloat(n + 3 * nl));
		}
		if (given > n) {
			gPnLean.resize(nl);
			int set = 0;
			for (int i = 0; i < nl; ++i) {
				gPnLean[i] = ai.OptionFloat(n + i);
				set += (gPnLean[i] != 0.f) ? 1 : 0;
			}
			AiLog("apex: pn-lean t=" + ai.teamId + " slots=" + nl + " set=" + set);
		}
	} else if (PN_BEST.length() == uint(n)) {
		for (int i = 0; i < n; ++i)
			gPnW[i] = PN_BEST[i];
		src = "best";
	} else {
		for (int i = 0; i < n; ++i)
			gPnW[i] = 0.f;
	}
	gPnMode = 1;
	gPnA1At = -1;
	gPnSigma = ai.GetTunable("apex_pn_explore", TUNE_PN_EXPLORE);
	gPnLogRate = ai.GetTunable("apex_pn_log_rate", TUNE_PN_LOG_RATE);
	gPnSigmaTilt = (gPnSigma > 0.f) ? ai.GetTunable("apex_pn_explore_tilt", TUNE_PN_EXPLORE_TILT) : 0.f;
	if (gPnSigma > 0.f)
		AiLog("apex: pnx-schema t=" + ai.teamId + " sigma=" + NnF(gPnSigma, 3) + " sigmaTilt=" + NnF(gPnSigmaTilt, 3) + " listRate=" + NnF(gPnLogRate, 3)
			+ " lgain=" + NnF(PN_LGAIN, 2) + " floor=" + NnF(PN_FLOOR, 3));
	AiLog("apex: policy ON t=" + ai.teamId + " src=" + src + " n=" + n + " given=" + given
		+ " in=" + N + " h1=" + PN_H1 + " h2=" + PN_H2 + " heads=" + PN_HEADS.length());
	return true;
}

// A continuous head is keyed by its tag, a choice head by its own-feature layout.
int PnHead(const string& in key)
{
	return PnOn() ? PN_HEADS.find(key) : -1;
}

float PnNorm(float x, float m, float s)
{
	const float z = (NnSlog(x) - m) / s;
	return (z > 5.f) ? 5.f : ((z < -5.f) ? -5.f : z);
}

// The shared layer, once a frame: its inputs are team-level.
// Keyed on the state's rebuild: every caller's st comes from NnState. A net that reads the asker's
// own two fields (commander, distance home) is recomputed per call instead.
int gPnAskerIn = -1;
void PnTrunk(const array<float>& in st)
{
	if (gPnAskerIn < 0) {
		gPnAskerIn = 0;
		for (uint i = 0; i < PN_IDX.length(); ++i)
			if ((PN_IDX[i] == int(NN_I_COMM)) || (PN_IDX[i] == int(NN_I_HOMED)))
				gPnAskerIn = 1;
	}
	if ((gPnTrained.length() > 0) && (ai.frame >= gPnSayAt))
		PnWatchSay(st);
	const int key = (gPnAskerIn > 0) ? -2 : gNnStAt;
	if ((key >= 0) && (gPnA1At == key))
		return;
	gPnA1At = key;
	const int N = int(PN_IDX.length());
	gPnZ.resize(N);
	for (int i = 0; i < N; ++i) {
		const int k = PN_IDX[i];
		gPnZ[i] = PnNorm((k < int(st.length())) ? st[k] : 0.f, PN_M[i], PN_S[i]);
	}
	int w = 0;
	gPnA1.resize(PN_H1);
	for (int h = 0; h < PN_H1; ++h) {
		float a = 0.f;
		for (int i = 0; i < N; ++i)
			a += gPnW[w++] * gPnZ[i];
		gPnA1[h] = tanh(a + gPnW[w++]);
	}
}

// Head h's outputs in [-1, 1]; a feature row shorter than the layout reads 0.
void PnHeadOut(int h, const array<float>& in st, const array<float>& in f, array<float>& out o)
{
	PnTrunk(st);
	const int F = PN_HF[h];
	const int fo = gPnFOff[h];
	gPnX.resize(F);
	for (int i = 0; i < F; ++i)
		gPnX[i] = PnNorm((i < int(f.length())) ? f[i] : 0.f, PN_FM[fo + i], PN_FS[fo + i]);
	int w = gPnHOff[h];
	gPnA2.resize(PN_H2);
	for (int j = 0; j < PN_H2; ++j) {
		float a = 0.f;
		for (int i = 0; i < PN_H1; ++i)
			a += gPnW[w++] * gPnA1[i];
		for (int i = 0; i < F; ++i)
			a += gPnW[w++] * gPnX[i];
		gPnA2[j] = tanh(a + gPnW[w++]);
	}
	const int K = (PN_HK[h] > 0) ? PN_HK[h] : 1;
	o.resize(K);
	for (int k = 0; k < K; ++k) {
		float a = 0.f;
		for (int j = 0; j < PN_H2; ++j)
			a += gPnW[w++] * gPnA2[j];
		o[k] = tanh(a + gPnW[w++]);
	}
	if (gPnLean.length() > 0) {
		const int lo = gPnLOff[h];
		if (PN_HK[h] < 0)
			o[0] += gPnLean[lo + PnLeanSlot(h, f)];
		else
			for (int k = 0; k < K; ++k)
				o[k] += gPnLean[lo + k];
	}
	if (gPnSigma > 0.f)
		PnExplore(h, F, o);
}

// A LEAN per output, held for the whole game (10-29): the training file carries one after the weights, the trained lean
// plus this game's push, so tools/leanloop.py credits the push with the game's result. A list head leans per kind of
// option: the auction per want kind, production per constructor / rez bot / aircraft / the rest.
array<float> gPnLean;
array<int> gPnLOff;
int PnLeanSlots(int h)
{
	if (PN_HK[h] >= 0)
		return (PN_HK[h] > 0) ? PN_HK[h] : 1;
	return (PN_HEADS[h] == "builder") ? WK_TEETH + 1 : 4;
}

int PnLeanSlot(int h, const array<float>& in f)
{
	if (PN_HEADS[h] == "builder") {
		for (int k = 0; (k <= WK_TEETH) && (k < int(f.length())); ++k)
			if (f[k] > 0.5f)
				return k;
		return 0;
	}
	if ((f.length() > 13) && (f[12] > 0.5f))
		return 1;
	if ((f.length() > 13) && (f[13] > 0.5f))
		return 2;
	return ((f.length() > 11) && (f[11] > 0.5f)) ? 3 : 0;
}

// A WATCHED TRAINING GAME (his 10-29: "see the training live ... periodic reports of our learnings"): a file that also
// carries the trained leans, each lean's evidence (t) and the pairs played makes one seat of the team say in chat what
// this game tries and what training has found, at the start and every 5 minutes.
array<float> gPnTrained;
array<float> gPnEvidence;
int gPnPairs = 0;
int gPnSayAt = 20 * SECOND;
const int BOARD_PN_SAY = 9100;

string PnSlotName(int i)
{
	for (uint h = PN_HEADS.length(); h-- > 0;) {
		if (gPnLOff[h] > i)
			continue;
		const int k = i - gPnLOff[h];
		const string tag = PN_HEADS[h];
		if (tag == "builder")
			return "auction " + KindName(k);
		if (tag == "factory")
			return "production " + ((k == 1) ? "constructors" : ((k == 2) ? "rez bots" : ((k == 3) ? "aircraft" : "combat units")));
		if (PN_HK[h] == 0) {
			const array<string> tags = {"con", "cap", "acap", "scap", "mex", "esc", "ecap", "cfear", "defamt", "mexg", "gunp", "aplant"};
			const array<string> says = {"constructors", "constructor cap", "air constructors", "scouts", "extractor claims",
				"escort strength", "escorts", "constructor caution", "defence amount", "extractor guards", "guns per post", "air plants"};
			const int at = tags.find(tag);
			return (at >= 0) ? says[at] : tag;
		}
		const string first = tag.split(",")[0];
		if (first == "hp") {
			const array<string> com = {"work", "fight", "turret", "retreat"};
			return "commander " + ((k < 4) ? com[k] : ("option " + k));
		}
		const array<string> firsts = {"foeStaticM", "labM", "comM", "travelS", "dMe", "kind", "defM", "ruleM", "grpM", "foeSeenM", "armyM"};
		const array<string> says = {"team plan", "tech", "opening", "reinforce", "join a build", "air wave", "defence site",
			"defence type", "hunt", "strike", "post"};
		const int at = firsts.find(first);
		return ((at >= 0) ? says[at] : ("choice " + h)) + " option " + k;
	}
	return "slot " + i;
}

string PnLeanSays(int i, float v)
{
	for (uint h = PN_HEADS.length(); h-- > 0;) {
		if (gPnLOff[h] > i)
			continue;
		if (PN_HK[h] == 0)
			return ((v >= 0.f) ? "more " : "less ") + NnF(abs(v), 2);
		return "x" + NnF(pow(2.718282f, PN_LGAIN * v), 2);
	}
	return NnF(v, 2);
}

void PnSay(const string& in s)
{
	// the engine drops an AI's text unless it is a /command (CAICallback::SendTextMsg): /echo puts it in the console
	ai.SendChat("/echo [Apex training] " + s);
	AiLog("apex: pn-say t=" + ai.teamId + " " + s);
}

void PnWatchSay(const array<float>& in st)
{
	gPnSayAt = ai.frame + 5 * MINUTE;
	const int report = ai.frame / (5 * MINUTE);
	if (ai.GetTeamBoard(BOARD_PN_SAY, -1.f) >= float(report))
		return;
	ai.SetTeamBoard(BOARD_PN_SAY, float(report));
	const int nl = int(gPnLean.length());
	if (report == 0) {
		PnSay("Apex training game: " + gPnPairs + " pairs played so far. Each pair plays one setup twice, every decision leaning opposite ways.");
		array<int> top;
		for (int pass = 0; pass < 4; ++pass) {
			int bi = -1;
			float bv = 0.f;
			for (int i = 0; i < nl; ++i) {
				const float d = abs(gPnLean[i] - gPnTrained[i]) / (PnLeanSlotIsAmount(i) ? 0.25f : 0.1f);
				if ((top.find(i) < 0) && (d > bv)) {
					bv = d;
					bi = i;
				}
			}
			if (bi >= 0)
				top.insertLast(bi);
		}
		string s = "This game tries:";
		for (uint j = 0; j < top.length(); ++j)
			s += ((j == 0) ? " " : "; ") + PnSlotName(top[j]) + " " + PnLeanSays(top[j], gPnLean[top[j]]);
		PnSay(s);
	} else if (st.length() > 32) {
		PnSay("Minute " + (report * 5) + ": metal income " + NnF(st[1], 1) + "/s, team army "
			+ NnF(st[25], 0) + " vs " + NnF(st[26], 0) + " seen, trade " + NnF(st[32], 2));
	}
	if ((report % 3) != 0)
		return;
	string m = "Learned so far:";
	int moved = 0;
	for (int i = 0; i < nl; ++i) {
		if (gPnTrained[i] != 0.f) {
			m += ((moved == 0) ? " " : "; ") + PnSlotName(i) + " " + PnLeanSays(i, gPnTrained[i]);
			++moved;
		}
	}
	if (moved == 0)
		m += " no lean has moved yet (one moves when its evidence passes 3).";
	PnSay(m);
	string e = "Strongest evidence:";
	array<int> used;
	for (int pass = 0; pass < 3; ++pass) {
		int bi = -1;
		float bt = 0.f;
		for (int i = 0; i < nl; ++i) {
			if ((used.find(i) < 0) && (abs(gPnEvidence[i]) > bt)) {
				bt = abs(gPnEvidence[i]);
				bi = i;
			}
		}
		if (bi < 0)
			break;
		used.insertLast(bi);
		e += ((pass == 0) ? " " : "; ") + PnSlotName(bi) + ((gPnEvidence[bi] > 0.f) ? " more pays" : " less pays")
			+ " (t " + NnF(gPnEvidence[bi], 1) + ")";
	}
	PnSay(e);
}

bool PnLeanSlotIsAmount(int i)
{
	for (uint h = PN_HEADS.length(); h-- > 0;)
		if (gPnLOff[h] <= i)
			return PN_HK[h] == 0;
	return false;
}

// LEARNING FROM OUR OWN CHOICES (his 10-28): in training games every output gets a push N(0, sigma), and the push is
// logged with the inputs that made the output, so tools/pgtrain.py can recompute the network and credit each push
// with what followed. A list head (auction, production) is called once per option: a sample of those is logged.
float gPnSigma = 0.f;       // amounts (a continuous head)
float gPnSigmaTilt = 0.f;   // choices and list options: their output is a tilt exp(PN_LGAIN x o), so a smaller push
float gPnLogRate = 0.f;
int gPnLogged = 0;
void PnExplore(int h, int F, array<float>& o)
{
	const bool listHead = PN_HK[h] < 0;
	const bool logIt = !listHead || (NnU01() < gPnLogRate);
	string ln;
	if (logIt) {
		ln = "apex: pnx h=" + h + " t=" + ai.teamId + " f=" + ai.frame + " |";
		for (uint i = 0; i < gPnZ.length(); ++i)
			ln += ((i == 0) ? " " : ",") + NnF(gPnZ[i], 3);
		ln += " |";
		for (int i = 0; i < F; ++i)
			ln += ((i == 0) ? " " : ",") + NnF(gPnX[i], 3);
		ln += " |";
	}
	for (uint k = 0; k < o.length(); ++k) {
		const float e = ((PN_HK[h] == 0) ? gPnSigma : gPnSigmaTilt) * NnGauss();
		if (logIt)
			ln += ((k == 0) ? " " : ",") + NnF(o[k], 4) + ":" + NnF(e, 4);
		o[k] += e;
	}
	if (logIt) {
		AiLog(ln);
		++gPnLogged;
	}
}

// Output 0 is the log-middle of [lo, hi]; +-1 its ends. A range from 0 starts at PN_FLOOR.
float PnValue(int h, const array<float>& in st, const array<float>& in f, float lo, float hi)
{
	array<float> o;
	PnHeadOut(h, st, f, o);
	const float l0 = log((lo > PN_FLOOR) ? lo : PN_FLOOR);
	const float l1 = log(hi);
	const float v = pow(2.718282f, l0 + (l1 - l0) * 0.5f * (1.f + o[0]));
	return (v < lo) ? lo : ((v > hi) ? hi : v);
}

// Output 0 is the rule's own value, +1 the top of [lo, hi] and -1 the bottom, in log steps. The
// log-middle above is not the rule for an uneven range: aa [0, 8] played 0.63x and gunp [0, 4] 0.45x
// at output 0, so every network sized AA below the rule (his 10-14: "we used to respond to air promptly").
float PnValueRule(int h, const array<float>& in st, const array<float>& in f, float lo, float hi, float rule)
{
	array<float> o;
	PnHeadOut(h, st, f, o);
	const float l0 = log((lo > PN_FLOOR) ? lo : PN_FLOOR);
	const float l1 = log(hi);
	float lr = log((rule > PN_FLOOR) ? rule : PN_FLOOR);
	lr = (lr < l0) ? l0 : ((lr > l1) ? l1 : lr);
	const float x = (o[0] > 1.f) ? 1.f : ((o[0] < -1.f) ? -1.f : o[0]);
	const float v = pow(2.718282f, lr + ((x >= 0.f) ? (l1 - lr) : (lr - l0)) * x);
	return (v < lo) ? lo : ((v > hi) ? hi : v);
}

// The rule's weights tilted by exp(PN_LGAIN x output): all outputs 0 leaves the rule's own
// odds; an option the rule gave no weight (impossible) stays at none.
void PnTilt(int h, const array<float>& in st, const array<float>& in f, array<float>& w)
{
	array<float> o;
	PnHeadOut(h, st, f, o);
	const int K = int(w.length());
	float sw = 0.f;
	for (int k = 0; k < K; ++k) {
		w[k] = (w[k] > 0.f) ? w[k] * pow(2.718282f, PN_LGAIN * ((k < int(o.length())) ? o[k] : 0.f)) : 0.f;
		sw += w[k];
	}
	if (sw > 0.f) {
		for (int k = 0; k < K; ++k)
			w[k] /= sw;
	}
}

// A list head scores each option from its own numbers, so one set of weights serves whatever
// the list holds. Each option's market value moves by exp(PN_LGAIN x output).
float PnListMult(int h, const array<float>& in st, const array<float>& in x)
{
	array<float> o;
	PnHeadOut(h, st, x, o);
	return pow(2.718282f, PN_LGAIN * o[0]);
}

// The builder auction: kind one-hot (0..WK_TEETH), NnOpt's numbers, value and eta against the
// best on offer, the list's length.
void PnBuilderTilt(int h, CCircuitUnit@ unit, array<Want@>@ ranked)
{
	const double _t = Perf::T0();
	array<float> s;
	NnState(unit, s);
	Perf::Add("nn.p.state", _t);
	const double _tO = Perf::T0();
	const uint n = (ranked.length() < NN_K) ? ranked.length() : NN_K;
	const AIFloat3 up = unit.GetPos(ai.frame);
	array<array<float>> opts(n);
	float best = -1e30f, bestEta = 1e30f;
	for (uint r = 0; r < n; ++r) {
		NnOpt(ranked[r], up, opts[r]);
		best = (opts[r][0] > best) ? opts[r][0] : best;
		bestEta = (opts[r][9] < bestEta) ? opts[r][9] : bestEta;
	}
	Perf::Add("nn.p.opt", _tO);
	const double _tE = Perf::T0();
	array<float> x(WK_TEETH + 1 + NN_ONUM + 3);
	for (uint r = 0; r < n; ++r) {
		if (ranked[r].value <= 0.f)
			continue;
		uint j = 0;
		for (int k = 0; k <= WK_TEETH; ++k)
			x[j++] = (ranked[r].kind == k) ? 1.f : 0.f;
		for (uint k = 0; k < NN_ONUM; ++k)
			x[j++] = opts[r][k];
		x[j++] = opts[r][0] - best;
		x[j++] = opts[r][9] - bestEta;
		x[j++] = float(n);
		const float m = PnListMult(h, s, x);
		ranked[r].value *= m;
		ranked[r].nnMult *= m;
	}
	Perf::Add("nn.p.eval", _tE);
	// DrawWeights takes the first of each category as its argmax: the list stays sorted
	for (uint r = 1; r < ranked.length(); ++r) {
		Want@ w = ranked[r];
		uint at = r;
		while ((at > 0) && (ranked[at - 1].value < w.value)) {
			@ranked[at] = ranked[at - 1];
			--at;
		}
		@ranked[at] = w;
	}

	Perf::Add("nn.policy", _t);
}

// Factory production: NnFacOpt's numbers, value against the best on offer, the list's length.
float PnFactoryTilt(int h, CCircuitUnit@ fac, const array<int>& in defs, array<float>& vals,
		const array<float>& in gains, array<float>& mult)
{
	array<float> s;
	NnState(fac, s);
	const uint n = (defs.length() < NNF_K) ? defs.length() : NNF_K;
	float best = -1e30f;
	for (uint r = 0; r < n; ++r)
		best = (vals[r] * 1000.f > best) ? vals[r] * 1000.f : best;
	array<float> o, x(NNF_ONUM + 2);
	float sum = 0.f;
	for (uint r = 0; r < defs.length(); ++r) {
		if ((r < n) && (vals[r] > 0.f)) {
			NnFacOpt(defs[r], vals[r] * 1000.f, gains[r], o);
			for (uint k = 0; k < NNF_ONUM; ++k)
				x[k] = o[k];
			x[NNF_ONUM] = o[0] - best;
			x[NNF_ONUM + 1] = float(n);
			mult[r] = PnListMult(h, s, x);
			vals[r] *= mult[r];
		}
		sum += vals[r];
	}
	return sum;
}

}  // namespace Market
