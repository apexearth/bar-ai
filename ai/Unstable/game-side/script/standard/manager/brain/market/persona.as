namespace Market {
// PERSONALITY (his 10-24: "personalities can bend/change"; 10-26: "not all AIs are just a straight copy of each
// other's gameplay"). Each seat draws its dials once, each in [-1, 1], and a dial leans the prices it touches by
// PERS_AMP^dial -- his 10-26 ruling, up to about 1.5x either way, so a clearly better buy still wins. Air: the air
// plants. Tech: the T2/T3 plants and the tech unlock. Aggression: the army's raw budget weight (low is greed, never a
// turtle). Class: what the factories favour among the army's four line classes. TUNE_PERSONA.
const float PERS_AMP = 1.5f;
const int PD_AIR = 0, PD_TECH = 1, PD_AGGR = 2, PD_CLASS = 3, PD_N = PD_CLASS + LC_N;
array<float> gPd(PD_N, 0.f);
int gPdOn = -1;

bool PersOn()
{
	if (gPdOn < 0) {
		gPdOn = (ai.GetTunable("apex_persona", TUNE_PERSONA) > 0.f) ? 1 : 0;
		if (gPdOn > 0) {
			for (int i = 0; i < PD_N; ++i)
				gPd[i] = float(AiRandom(0, 20000)) / 10000.f - 1.f;
			AiLog("apex: persona t=" + ai.teamId + " air=" + NnF(gPd[PD_AIR], 2) + " tech=" + NnF(gPd[PD_TECH], 2)
				+ " aggr=" + NnF(gPd[PD_AGGR], 2) + " tank=" + NnF(gPd[PD_CLASS + LC_TANK], 2)
				+ " mid=" + NnF(gPd[PD_CLASS + LC_MID], 2) + " reach=" + NnF(gPd[PD_CLASS + LC_REACH], 2)
				+ " dps=" + NnF(gPd[PD_CLASS + LC_DPS], 2));
		}
	}
	return gPdOn > 0;
}

float PersMul(int dial)
{
	if (!PersOn() || (dial < 0) || (dial >= PD_N))
		return 1.f;
	return pow(PERS_AMP, gPd[dial]);
}

// a plant: the air lean on an air plant, the tech lean on a plant above T1 (both, for an advanced air plant)
float PersPlantMul(int d)
{
	if (!PersOn() || !Catalog::ValidId(d))
		return 1.f;
	float m = 1.f;
	if (PlantClass(d) == PC_AIR)
		m *= PersMul(PD_AIR);
	if (PlantTier(d) >= 2)
		m *= PersMul(PD_TECH);
	return m;
}

// a builder want: a plant (or the gantry, a plant) by PersPlantMul, the tech unlock by the tech lean
float PersWantMul(Want@ w)
{
	if (!PersOn() || (w is null) || (w.def is null))
		return 1.f;
	if (w.kind == WK_PLANT)
		return PersPlantMul(int(w.def.id));
	if (w.kind == WK_TECH)
		return PersMul(PD_TECH) * ((PlantClass(int(w.def.id)) == PC_AIR) ? PersMul(PD_AIR) : 1.f);
	if ((w.kind == WK_SUPER) && IsGantryDef(int(w.def.id)))
		return PersMul(PD_TECH);
	return 1.f;
}

float PersClassMul(int lineClass)
{
	if ((lineClass < 0) || (lineClass >= LC_N))
		return 1.f;
	return PersMul(PD_CLASS + lineClass);
}

}  // namespace Market
