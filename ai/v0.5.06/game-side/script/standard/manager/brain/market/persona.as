namespace Market {
// PERSONALITY v2 (his 11-01). The team plays one style (persona_style.as); each seat draws its own flavour inside it
// here: dials in [-1, 1], each leaning the prices it touches by PERS_SEAT_AMP^dial (the army row by PERS_AGGR_AMP^dial,
// low is greed, never a turtle). The dial a style is built on is folded non-negative, so a seat sharpens the team's
// style and never cancels it. Every lean is a price; with TUNE_PERSONA off every function here returns 1.
const float PERS_SEAT_AMP = 2.f;
const float PERS_AGGR_AMP = 1.5f;
const int PD_AIR = 0, PD_TECH = 1, PD_AGGR = 2, PD_CLASS = 3, PD_FAST = PD_CLASS + LC_N, PD_SCOUT = PD_FAST + 1;
const int PD_BOMB = PD_SCOUT + 1, PD_GUN = PD_BOMB + 1, PD_FIGHT = PD_GUN + 1, PD_TURTLE = PD_FIGHT + 1, PD_N = PD_TURTLE + 1;
array<float> gPd(PD_N, 0.f);
int gPdOn = -1;

bool PersOn()
{
	if (gPdOn < 0)
		gPdOn = (ai.GetTunable("apex_persona", TUNE_PERSONA) > 0.f) ? 1 : 0;
	return gPdOn > 0;
}

void PersSeatDraw(int keyDial)
{
	for (int i = 0; i < PD_N; ++i)
		gPd[i] = float(AiRandom(0, 20000)) / 10000.f - 1.f;
	if ((keyDial >= 0) && (keyDial < PD_N))
		gPd[keyDial] = abs(gPd[keyDial]);
	gPdTurtleRaw = gPd[PD_TURTLE];
	gPd[PD_TURTLE] = 0.f;
	if (gPdPlaced)
		PersPlace();
}

// THE SEAT'S PLACE PICKS ITS TYPE (his 11-02): the front player likes shields and defences, the back player air,
// the middle the army -- only on a team with a front, a middle and a back (a lone seat is no turtle). Applied once
// the team's homes are known (30 s; at the first draw every seat read as the front), and on every redraw after.
bool gPdPlaced = false;
float gPdTurtleRaw = 0.f;
void PersPlace()
{
	array<Id>@ mates = ai.GetTeamIds();
	int seats = 0;
	if (mates !is null)
		for (uint i = 0; i < mates.length(); ++i)
			if (TtAlive(int(mates[i])))
				++seats;
	const float ex = TeamExposure();
	gPd[PD_TURTLE] = -abs(gPdTurtleRaw);
	if ((seats >= 3) && (ex >= 2.f / 3.f))
		gPd[PD_TURTLE] = abs(gPdTurtleRaw);
	else if ((seats >= 3) && (ex <= 1.f / 3.f))
		gPd[PD_AIR] = abs(gPd[PD_AIR]);
	if ((seats >= 3) && (ex > 1.f / 3.f) && (ex < 2.f / 3.f))
		gPd[PD_TURTLE] = gPdTurtleRaw;
}

void PersPlaceTick()
{
	if (gPdPlaced || !PersOn() || (ai.frame < 30 * SECOND))
		return;
	gPdPlaced = true;
	PersPlace();
	AiLog("apex: persona-seat t=" + ai.teamId + " exposure=" + NnF(TeamExposure(), 2) + " " + PersSeatLine());
}

string PersSeatLine()
{
	return "air=" + NnF(gPd[PD_AIR], 2) + " tech=" + NnF(gPd[PD_TECH], 2) + " aggr=" + NnF(gPd[PD_AGGR], 2)
		+ " tank=" + NnF(gPd[PD_CLASS + LC_TANK], 2) + " mid=" + NnF(gPd[PD_CLASS + LC_MID], 2)
		+ " reach=" + NnF(gPd[PD_CLASS + LC_REACH], 2) + " dps=" + NnF(gPd[PD_CLASS + LC_DPS], 2)
		+ " fast=" + NnF(gPd[PD_FAST], 2) + " scout=" + NnF(gPd[PD_SCOUT], 2) + " bomb=" + NnF(gPd[PD_BOMB], 2)
		+ " gun=" + NnF(gPd[PD_GUN], 2) + " fight=" + NnF(gPd[PD_FIGHT], 2) + " turtle=" + NnF(gPd[PD_TURTLE], 2);
}

float PersMul(int dial)
{
	if (!PersOn() || (dial < 0) || (dial >= PD_N))
		return 1.f;
	return pow((dial == PD_AGGR) ? PERS_AGGR_AMP : PERS_SEAT_AMP, gPd[dial]);
}

// the army row: the seat's aggression and the style's pressure
float PersArmyMul()
{
	if (!PersOn())
		return 1.f;
	return PersMul(PD_AGGR) * PsArmyLean();
}

// a plant: the air lean on an air plant, the tech lean on a plant above T1, and the team style by what it fields
float PersPlantMul(int d)
{
	if (!PersOn() || !Catalog::ValidId(d))
		return 1.f;
	float m = PsPlantLean(d);
	if (PlantClass(d) == PC_AIR)
		m *= PersMul(PD_AIR);
	if (PlantTier(d) >= 2)
		m *= PersMul(PD_TECH);
	return m;
}

float PersWantMul(Want@ w)
{
	if (!PersOn() || (w is null) || (w.def is null))
		return 1.f;
	const int d = int(w.def.id);
	if (w.kind == WK_PLANT)
		return PersPlantMul(d);
	if (w.kind == WK_TECH)
		return PersMul(PD_TECH) * PsTechLean() * PsPlantLean(d) * ((PlantClass(d) == PC_AIR) ? PersMul(PD_AIR) : 1.f);
	if (w.kind == WK_SUPER)
		return (IsGantryDef(d) ? PersMul(PD_TECH) : 1.f) * PsSuperLean(d);
	if (w.kind == WK_SENSE)
		return PsSenseLean(d) * (Catalog::gRadar[d] ? PersMul(PD_SCOUT) : 1.f);
	// shield domes and the defensive layer (the shield style's fits; every other style fits none of them)
	if ((w.kind == WK_PROTECT) || (w.kind == WK_AIRDEF))
		return PsUnitLean(d) * PersMul(PD_TURTLE);
	return 1.f;
}

float PersClassMul(int lineClass)
{
	if ((lineClass < 0) || (lineClass >= LC_N))
		return 1.f;
	return PersMul(PD_CLASS + lineClass);
}

// the seat's flavour on one unit: air by role (bomber, gunship, fighter), ground by speed, scouts
float PersSeatUnitMul(int d)
{
	if (Catalog::gFlyer[d] && LineCombat(d)) {
		int role = PD_GUN;
		if (Catalog::gAirT[d] > Catalog::gSurfT[d])
			role = PD_FIGHT;
		else if (Air::IsBomberDef(d))
			role = PD_BOMB;
		return PersMul(PD_AIR) * PersMul(role);
	}
	if (LineCombat(d))
		return pow(PERS_SEAT_AMP, gPd[PD_FAST] * PsSpeedAxis(d));
	if (PsIsScout(d))
		return PersMul(PD_SCOUT);
	return 1.f;
}

float PersUnitMul(int d)
{
	if (!PersOn() || !Catalog::ValidId(d) || !Catalog::gMobile[d] || Catalog::gBuilder[d])
		return 1.f;
	return PersSeatUnitMul(d) * PsUnitLean(d);
}

// A factory's draw: the leans move WHICH unit, not how much army; the army candidates keep their total.
int gPsOrd = 0, gPsOrdLean = 0, gPsPick = 0, gPsPickLean = 0;
float PersProdApply(const array<int>@ candDef, array<float>@ candV, float sumV)
{
	float before = 0.f, after = 0.f;
	array<float> mul(candDef.length(), 1.f);
	for (uint i = 0; i < candDef.length(); ++i) {
		const int d = candDef[i];
		if (!Catalog::ValidId(d) || !Catalog::gMobile[d] || Catalog::gBuilder[d])
			continue;
		mul[i] = PersUnitMul(d);
		before += candV[i];
		after += candV[i] * mul[i];
	}
	++gPsOrd;
	if ((before <= 0.f) || (after <= 0.f))
		return sumV;
	const float k = before / after;
	bool leaned = false;
	for (uint i = 0; i < candDef.length(); ++i) {
		if (mul[i] == 1.f)
			continue;
		leaned = true;
		const float nv = candV[i] * mul[i] * k;
		sumV += nv - candV[i];
		candV[i] = nv;
	}
	for (uint i = 0; i < candDef.length(); ++i) {
		if (!Catalog::ValidId(candDef[i]) || !Catalog::gMobile[candDef[i]] || Catalog::gBuilder[candDef[i]] || (mul[i] != 1.f))
			continue;
		const float nv = candV[i] * k;
		sumV += nv - candV[i];
		candV[i] = nv;
	}
	if (leaned)
		++gPsOrdLean;
	return sumV;
}

void PersNotePick(int d)
{
	++gPsPick;
	if (Catalog::ValidId(d) && (PsUnitLean(d) > 1.05f))
		++gPsPickLean;
}

int gPsTop = 0, gPsTopUp = 0, gPsTopDown = 0;
void PersNoteTop(Want@ top)
{
	if (top is null)
		return;
	++gPsTop;
	if (top.persMul > 1.05f)
		++gPsTopUp;
	else if (top.persMul < 0.95f)
		++gPsTopDown;
}

float PersScoutCapMul()
{
	return PsScoutCapLean() * PersMul(PD_SCOUT);
}

float PersLineMul(int cls)
{
	return PsLineLean(cls);
}

}  // namespace Market
