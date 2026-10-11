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
	if (ai.GetTunable("apex_policy", 1.f) <= 0.f) {
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
	const int given = ai.LoadOptionFloats("apex_pw_file");
	gPnW.resize(n);
	string src = "middle";
	if (given == n) {
		for (int i = 0; i < n; ++i)
			gPnW[i] = ai.OptionFloat(i);
		src = "file";
	} else if (PN_BEST.length() == uint(n)) {
		for (int i = 0; i < n; ++i)
			gPnW[i] = PN_BEST[i];
		src = "best";
	} else {
		for (int i = 0; i < n; ++i)
			gPnW[i] = 0.f;
	}
	gPnMode = 1;
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
void PnTrunk(const array<float>& in st)
{
	if (gPnA1At == ai.frame)
		return;
	gPnA1At = ai.frame;
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
	const uint n = (ranked.length() < NN_K) ? ranked.length() : NN_K;
	const AIFloat3 up = unit.GetPos(ai.frame);
	array<array<float>> opts(n);
	float best = -1e30f, bestEta = 1e30f;
	for (uint r = 0; r < n; ++r) {
		NnOpt(ranked[r], up, opts[r]);
		best = (opts[r][0] > best) ? opts[r][0] : best;
		bestEta = (opts[r][9] < bestEta) ? opts[r][9] : bestEta;
	}
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
