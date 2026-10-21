namespace Market {

// THE SCALES THE MARKET COMPARES (TODO.md, the valuation job, step 1). Read-only: each election notes the top
// value of every want kind it priced, each lab order its best constructor and best army candidate, and once a
// minute a seat logs the means. `apex: vscale t= <kind>=mean/n ... | lab con=mean/n army=mean/n`.
const int VS_N = 17;
array<double> gVsSum(VS_N, 0.0);
array<int> gVsN(VS_N, 0);
array<float> gVsTop(VS_N, 0.f);
double gVsConSum = 0.0, gVsArmySum = 0.0;
int gVsConN = 0, gVsArmyN = 0;
int gVsLogAt = 0;

void VScaleNote(const array<Want@>@ ranked)
{
	if (ranked is null)
		return;
	for (uint k = 0; k < VS_N; ++k)
		gVsTop[k] = -1.f;
	for (uint i = 0; i < ranked.length(); ++i) {
		Want@ w = ranked[i];
		if ((w is null) || (w.kind < 0) || (w.kind >= VS_N))
			continue;
		if (w.value > gVsTop[uint(w.kind)])
			gVsTop[uint(w.kind)] = w.value;
	}
	for (uint k = 0; k < VS_N; ++k) {
		if (gVsTop[k] > 0.f) {
			gVsSum[k] += gVsTop[k];
			++gVsN[k];
		}
	}
	VScaleLog();
}

void VScaleLabNote(const array<int>& in defs, const array<float>& in vals)
{
	float con = -1.f, army = -1.f;
	for (uint i = 0; (i < defs.length()) && (i < vals.length()); ++i) {
		if (Catalog::gBuilder[defs[i]]) {
			if (vals[i] > con)
				con = vals[i];
		} else if (vals[i] > army) {
			army = vals[i];
		}
	}
	if (con > 0.f) {
		gVsConSum += con;
		++gVsConN;
	}
	if (army > 0.f) {
		gVsArmySum += army;
		++gVsArmyN;
	}
}

string VsMean(double s, int n)
{
	return (n > 0) ? (formatFloat(s / double(n), "", 0, 4) + "/" + n) : "-";
}

void VScaleLog()
{
	if (ai.frame < gVsLogAt)
		return;
	gVsLogAt = ai.frame + 60 * SECOND;
	string ln = Factory::T() + "apex: vscale t=" + ai.teamId;
	for (int k = 1; k < VS_N; ++k) {
		if (gVsN[uint(k)] > 0)
			ln += " " + KindName(k) + "=" + VsMean(gVsSum[uint(k)], gVsN[uint(k)]);
		gVsSum[uint(k)] = 0.0;
		gVsN[uint(k)] = 0;
	}
	ln += " | lab con=" + VsMean(gVsConSum, gVsConN) + " army=" + VsMean(gVsArmySum, gVsArmyN);
	gVsConSum = 0.0;
	gVsArmySum = 0.0;
	gVsConN = 0;
	gVsArmyN = 0;
	AiLog(ln);
}

}  // namespace Market
