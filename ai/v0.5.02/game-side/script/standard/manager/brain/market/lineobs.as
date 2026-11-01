namespace Market {

// TUNE_LINE_OBSOLETE: a lower line's combat unit keeps the share of per-metal
// worth that the best unit of its role, from a higher-tier plant we own and can
// afford, would deliver for the same metal (DefObsoleteShare's idea for towers).
const int LO_COMBAT = 0, LO_AA = 1, LO_BOMB = 2;

array<int> gLoDef;
array<int> gLoTier;
array<float> gLoCore;
array<int> gLoRole;
int gLoAt = -999999;
float gLoBudget = 0.f;
array<float> gLoCov;
array<float> gLoMemo;
array<int> gLoMemoAt;
array<int> gLoMemoBy;

int gLoAsk = 0, gLoCut = 0, gLoOrders = 0, gLoDefer = 0, gNextLoLog = 0;
float gLoMin = 1.f;
string gLoLast = "";

bool LineObsOn()
{
	return ai.GetTunable("apex_line_obsolete", TUNE_LINE_OBSOLETE) > 0.f;
}

bool LineObsUnit(int d)
{
	return Catalog::ValidId(d) && Catalog::gMobile[d] && !Catalog::gBuilder[d]
		&& !Catalog::gRezzer[d] && (Catalog::gPower[d] > 1.f) && !Catalog::gKamikaze[d]
		&& !IsLateScout(d);
}

int LineObsRole(int d)
{
	if (Catalog::gRole[d] == int(Unit::Role::AA.type))
		return LO_AA;
	if (Catalog::gFlyer[d] && (Catalog::gRole[d] == int(Unit::Role::BOMBER.type)))
		return LO_BOMB;
	return LO_COMBAT;
}

float LineObsCov(int d)
{
	if (int(gLoCov.length()) <= Catalog::gDefCount) {
		gLoCov.resize(Catalog::gDefCount + 1);
		for (uint i = 0; i < gLoCov.length(); ++i)
			gLoCov[i] = -1.f;
	}
	if (gLoCov[d] < 0.f)
		gLoCov[d] = ai.DefMapCoverage(Catalog::Def(d));
	return gLoCov[d];
}

// o can stand wherever d is needed: fliers against fliers, ships against
// ships, and a ground unit only by one whose ground covers at least as much.
bool LineObsReaches(int o, int d)
{
	if (Catalog::gFlyer[d] || Catalog::gFlyer[o])
		return Catalog::gFlyer[d] && Catalog::gFlyer[o];
	if (IsNavyDef(d) || IsNavyDef(o))
		return IsNavyDef(d) && IsNavyDef(o);
	return LineObsCov(o) >= LineObsCov(d) - 2.f;
}

void LineObsRefresh()
{
	if (ai.frame < gLoAt + 10 * SECOND)
		return;
	gLoAt = ai.frame;
	gLoDef.resize(0);
	gLoTier.resize(0);
	gLoCore.resize(0);
	gLoRole.resize(0);
	gLoBudget = Eco::MInc() * ai.GetTunable("apex_unit_afford_s", TUNE_UNIT_AFFORD_S);
	for (uint fi = 0; fi < Factory::gFacUnits.length(); ++fi) {
		CCircuitUnit@ f = Factory::gFacUnits[fi];
		if ((f is null) || (f.circuitDef is null))
			continue;
		const int fd = int(f.circuitDef.id);
		const int tier = PlantTier(fd);
		if (tier < 2)
			continue;   // a basic plant is the lowest line; it outdates nothing
		const array<int>@ pl = Catalog::BuildsOf(fd);
		for (uint i = 0; i < pl.length(); ++i) {
			const int o = pl[i];
			if (!Catalog::gAvailable[o] || !LineObsUnit(o) || ReachDead(o))
				continue;
			if ((gLoBudget > 1.f) && (Catalog::gCostM[o] >= gLoBudget))
				continue;   // the aff0 bar: a unit we cannot afford outdates nothing
			const int at = gLoDef.find(o);
			if (at >= 0) {
				if (tier > gLoTier[at])
					gLoTier[at] = tier;
				continue;
			}
			gLoDef.insertLast(o);
			gLoTier.insertLast(tier);
			gLoCore.insertLast(UnitCore(o));
			gLoRole.insertLast(LineObsRole(o));
		}
	}
}

float LineObsShare(int d, int askTier)
{
	if (!LineObsUnit(d))
		return 1.f;
	LineObsRefresh();
	const int k = d * 4 + ((askTier > 3) ? 3 : askTier);
	if (int(gLoMemo.length()) <= k) {
		gLoMemo.resize(Catalog::gDefCount * 4 + 4);
		gLoMemoAt.resize(Catalog::gDefCount * 4 + 4);
		gLoMemoBy.resize(Catalog::gDefCount * 4 + 4);
		for (uint i = 0; i < gLoMemoAt.length(); ++i)
			gLoMemoAt[i] = -999999;
	}
	float share = 1.f;
	int by = -1;
	if (gLoMemoAt[k] == gLoAt) {
		share = gLoMemo[k];
		by = gLoMemoBy[k];
	} else {
		const float myK = UnitCore(d);
		const int role = LineObsRole(d);
		for (uint i = 0; (myK > 0.f) && (i < gLoDef.length()); ++i) {
			const int o = gLoDef[i];
			if ((gLoTier[i] <= askTier) || (gLoRole[i] != role) || (o == d)
				|| (gLoCore[i] <= myK) || !LineObsReaches(o, d))
				continue;
			const float s = myK / gLoCore[i];
			if (s < share) {
				share = s;
				by = o;
			}
		}
		gLoMemo[k] = share;
		gLoMemoAt[k] = gLoAt;
		gLoMemoBy[k] = by;
	}
	++gLoAsk;
	if (share < 1.f) {
		++gLoCut;
		if (share < gLoMin)
			gLoMin = share;
		gLoLast = Catalog::Def(d).GetName() + ">" + Catalog::Def(by).GetName()
			+ "=" + formatFloat(share, "", 0, 3);
	}
	return share;
}

void LineObsLog()
{
	if (ai.frame < gNextLoLog)
		return;
	gNextLoLog = ai.frame + 60 * SECOND;
	AiLog(Factory::T() + "apex: lineobs-stat t=" + ai.teamId
		+ " on=" + (LineObsOn() ? 1 : 0)
		+ " lines=" + gLoDef.length() + " afford=" + int(gLoBudget)
		+ " ask=" + gLoAsk + " cut=" + gLoCut
		+ " minShare=" + formatFloat(gLoMin, "", 0, 3)
		+ " orders=" + gLoOrders + " defer=" + gLoDefer
		+ " last=" + gLoLast);
}

}  // namespace Market
