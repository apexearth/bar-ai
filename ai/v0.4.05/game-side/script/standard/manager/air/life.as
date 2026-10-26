namespace Air {

// How long our units of a def live, from our own losses: lived seconds (the living counted
// so far) over deaths, with the window itself as one prior life, so nothing moves before a
// loss is seen. A buy is worth the work over the life it is expected to have.
bool gLifeRead = false;
bool gLifeOn = false;
array<int> gLifeBorn(32001, -1);
array<float> gLifeLived;
array<float> gLifeBornSum;
array<int> gLifeAlive;
array<int> gLifeDead;

bool UnitLifeOn()
{
	if (!gLifeRead) {
		gLifeRead = true;
		gLifeOn = ai.GetTunable("apex_unit_life", TUNE_UNIT_LIFE) > 0.f;
	}
	return gLifeOn;
}

void LifeSize()
{
	const uint n = Catalog::gCostM.length();
	if (gLifeLived.length() < n) {
		gLifeLived.resize(n);
		gLifeBornSum.resize(n);
		gLifeAlive.resize(n);
		gLifeDead.resize(n);
	}
}

void LifeNoteBorn(CCircuitUnit@ u)
{
	if ((u is null) || (u.circuitDef is null) || (int(u.id) < 0) || (int(u.id) >= int(gLifeBorn.length())))
		return;
	LifeSize();
	const int d = int(u.circuitDef.id);
	if ((d < 0) || (d >= int(gLifeLived.length())) || (gLifeBorn[u.id] >= 0))
		return;
	gLifeBorn[u.id] = ai.frame;
	gLifeAlive[d]++;
	gLifeBornSum[d] += float(ai.frame);
}

void LifeNoteDead(CCircuitUnit@ u)
{
	if ((u is null) || (u.circuitDef is null) || (int(u.id) < 0) || (int(u.id) >= int(gLifeBorn.length())))
		return;
	const int b = gLifeBorn[u.id];
	gLifeBorn[u.id] = -1;
	const int d = int(u.circuitDef.id);
	if ((b < 0) || (d < 0) || (d >= int(gLifeLived.length())))
		return;
	gLifeAlive[d]--;
	gLifeBornSum[d] -= float(b);
	gLifeLived[d] += float(ai.frame - b) / 30.f;
	gLifeDead[d]++;
}

// Expected life in seconds of a def's unit, the window h as the prior.
float LifeOf(int d, float h)
{
	if ((d < 0) || (d >= int(gLifeLived.length())))
		return h;
	const float aliveS = (float(gLifeAlive[d]) * float(ai.frame) - gLifeBornSum[d]) / 30.f;
	return (gLifeLived[d] + aliveS + h) / float(gLifeDead[d] + 1);
}

// The share of the window h a unit bought now works: L(1 - e^(-h/L)) / h.
float LifeShare(int d, float h)
{
	if (!UnitLifeOn() || (h <= 0.f))
		return 1.f;
	const float l = LifeOf(d, h);
	if (l <= 0.f)
		return 0.f;
	return l * (1.f - pow(2.7182818f, -h / l)) / h;
}

void LifeStat()
{
	string s = "";
	for (uint d = 1; d < gLifeLived.length(); ++d) {
		if ((gLifeDead[d] == 0) || !Catalog::gFlyer[d] || Catalog::gBuilder[d])
			continue;
		const float l = LifeOf(int(d), 180.f);
		s += " " + Catalog::Def(int(d)).GetName() + "=" + gLifeAlive[d] + "/" + gLifeDead[d]
			+ ",L" + int(l) + ",x" + formatFloat(l * (1.f - pow(2.7182818f, -180.f / l)) / 180.f, "", 0, 2);
	}
	AiLog(Factory::T() + "apex: life-stat t=" + ai.teamId + " on=" + (UnitLifeOn() ? 1 : 0) + s);
}

}
