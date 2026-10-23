namespace Market {

// THE STRICT ECO SEAT (TUNE_ECO_SEAT_STRICT). While the seat grows, its
// builders and factories serve the economy; the other seats already leave it
// out of their parity and answer shares (TV_ECOSEAT). EcoDangerNear still ends
// the growth, and AA stays open while aircraft are killing our things.
int gEsOn = -1;
int gEsAt = -1;
bool gEsGrow = false;
bool gEsStrict = false;

void EcoSeatTick()
{
	if (gEsAt == ai.frame)
		return;
	gEsAt = ai.frame;
	if (gEsOn < 0)
		gEsOn = (ai.GetTunable("apex_eco_seat_strict", TUNE_ECO_SEAT_STRICT) > 0.f) ? 1 : 0;
	gEsGrow = EcoRoleGrowing();
	gEsStrict = gEsGrow && (gEsOn > 0);
}

bool EcoSeatStrict()
{
	EcoSeatTick();
	return gEsStrict;
}

bool EcoSeatAirDanger()
{
	return Military::AirLossRate() > 0.f;
}

bool EcoSeatAADef(int d)
{
	return (Catalog::gAirT[d] > 0.01f) && (Catalog::gSurfT[d] <= 0.01f);
}

bool EcoSeatDef(int d)
{
	return (Catalog::gMakeE[d] > 1.f) || (Catalog::gExtractsM[d] > 0.f)
		|| (Catalog::gConvCapacity[d] > 0.f) || (Catalog::gMakeM[d] > 0.f)
		|| (Catalog::gStoreE[d] > 0.f) || (Catalog::gStoreM[d] > 0.f)
		|| (!Catalog::gMobile[d] && Catalog::gBuilder[d]);
}

bool EcoSeatKeeps(Want@ w)
{
	const int k = w.kind;
	if ((k == WK_MEX) || (k == WK_MEXUP) || (k == WK_ENERGY) || (k == WK_GEO)
		|| (k == WK_CONVERT) || (k == WK_STORE) || (k == WK_NANO) || (k == WK_TECH)
		|| (k == WK_RECLAIM))
		return true;
	if (k == WK_PLANT) {
		if (Factory::gFacUnits.length() == 0)
			return true;   // no lab, no hands
		// air cons spend an overflowing bank in parallel where walkers crowd the ground (his 10-15)
		if (w.def is null)
			return false;
		const int pd = int(w.def.id);
		return AirPlant(pd) && (!FlyingConLab(false) || ((PlantTier(pd) >= 2) && !FlyingConLab(true)));
	}
	if (k == WK_ASSIST) {
		const CCircuitDef@ ad = w.def;
		if (ad is null) {
			CCircuitUnit@ boss = ai.GetTeamUnit(Id(w.spotId));
			if ((boss is null) || !boss.circuitDef.IsMobile())
				return true;   // a lab here makes only hands, a nano feeds what it reaches
			if ((boss.task is null) || (boss.task.GetType() != Task::Type::BUILDER))
				return true;
			@ad = boss.task.buildDef;
			if (ad is null)
				return true;
		}
		return EcoSeatDef(int(ad.id));
	}
	if (w.def is null)
		return false;
	const int d = int(w.def.id);
	if (Catalog::gAntiNuke[d])
		return true;
	if (EcoSeatAADef(d))
		return EcoSeatAirDanger();
	return false;
}

bool EcoSeatFacKeeps(int d)
{
	if (Catalog::gBuilder[d])
		return true;
	if ((Catalog::gRole[d] == int(Unit::Role::AA.type)) || EcoSeatAADef(d))
		return EcoSeatAirDanger();
	return false;
}

array<int> gEsJobs(20, 0);
array<int> gEsRef(20, 0);
int gEsFacRef = 0;
float gEsTowerM = 0.f;
float gEsArmyM = 0.f;
float gEsTowerSum = 0.f;
float gEsArmySum = 0.f;
int gEsStatAt = 0;

bool EcoSeatGuns(int k)
{
	return (k == WK_PROTECT) || (k == WK_SENSE) || (k == WK_AIRDEF)
		|| (k == WK_TEETH) || (k == WK_SUPER);
}

void EcoSeatRefuse(Want@ w)
{
	if ((w.kind >= 0) && (w.kind < int(gEsRef.length())))
		++gEsRef[w.kind];
}

void EcoSeatNoteJob(Want@ w)
{
	EcoSeatTick();
	if (!gEsGrow)
		return;
	if ((w.kind >= 0) && (w.kind < int(gEsJobs.length())))
		++gEsJobs[w.kind];
	if (EcoSeatGuns(w.kind) && (w.def !is null))
		gEsTowerM += w.def.costM;
}

void EcoSeatNoteOrder(const CCircuitDef@ o)
{
	if ((o is null) || Catalog::gBuilder[int(o.id)])
		return;
	EcoSeatTick();
	if (gEsGrow)
		gEsArmyM += o.costM;
}

void EcoSeatStat()
{
	if (ai.frame < gEsStatAt)
		return;
	gEsStatAt = ai.frame + 60 * SECOND;
	if (!gEcoRole && !gWasEcoSeat)
		return;
	EcoSeatTick();
	int jobs = 0;
	for (uint k = 0; k < gEsJobs.length(); ++k)
		jobs += gEsJobs[k];
	string js = "";
	string rs = "";
	for (uint k = 0; k < gEsJobs.length(); ++k) {
		if (gEsJobs[k] > 0)
			js += ((js.length() > 0) ? " " : "") + KindName(int(k)) + "="
				+ int(100.f * float(gEsJobs[k]) / float(jobs)) + "%";
		if (gEsRef[k] > 0)
			rs += ((rs.length() > 0) ? " " : "") + KindName(int(k)) + "=" + gEsRef[k];
	}
	gEsTowerSum += gEsTowerM;
	gEsArmySum += gEsArmyM;
	AiLog(Factory::T() + "apex: ecoseat-stat t=" + ai.teamId + " strict=" + gEsOn
		+ " growing=" + (gEsGrow ? 1 : 0)
		+ " P=" + int(EcoPowerM()) + "/" + int(EcoRoleTargetM())
		+ " ramp=" + formatFloat(EcoRoleRamp(), "", 0, 2)
		+ " danger=" + (EcoDangerNear() ? 1 : 0)
		+ " airLoss=" + formatFloat(Military::AirLossRate(), "", 0, 2)
		+ " jobs=" + jobs + " [" + js + "]"
		+ " towerM=" + int(gEsTowerM) + "/" + int(gEsTowerSum)
		+ " armyM=" + int(gEsArmyM) + "/" + int(gEsArmySum)
		+ " refused=[" + rs + "]"
		+ " facRefused=" + gEsFacRef);
	for (uint k = 0; k < gEsJobs.length(); ++k) {
		gEsJobs[k] = 0;
		gEsRef[k] = 0;
	}
	gEsFacRef = 0;
	gEsTowerM = 0.f;
	gEsArmyM = 0.f;
}

}  // namespace Market
