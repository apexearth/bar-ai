namespace Military {

// apex_stock_army: every combat unit runs stock BARb's fight code (docs/how-it-works.md, Army control layers).
// Each of our layers that would take or order one asks StockQuiet first and stands down; the C++ bindings
// drop and count whatever still reaches a combat unit (leak= in the stat line, 0 when the census is whole).
int gSaOn = -1;
array<int8> gSaDef;
array<string> gSaTag;
array<int> gSaN;
int gSaNextLog = 0;

bool StockArmy()
{
	if (gSaOn < 0)
		gSaOn = (ai.GetTunable("apex_stock_army", TUNE_STOCK_ARMY) > 0.f) ? 1 : 0;
	return gSaOn > 0;
}

// the C++ test is CCircuitAI::IsStockCtlDef: mobile, no builder, no commander, no transport, armed or a scout
bool StockDef(const CCircuitDef@ d)
{
	if (d is null)
		return false;
	const int id = int(d.id);
	if (int(gSaDef.length()) <= id)
		gSaDef.resize(id + 1);
	if (gSaDef[id] == 0) {
		const bool combat = d.IsMobile() && !d.IsBuilder()
			&& !d.IsRoleAny(Unit::Role::COMM.mask | Unit::Role::TRANS.mask)
			&& !Market::IsLiftDef(id)
			&& ((Catalog::gPower[id] > 0.f) || d.IsRoleAny(Unit::Role::SCOUT.mask) || !d.IsAbleToFly());
		gSaDef[id] = combat ? 1 : -1;
	}
	return gSaDef[id] > 0;
}

bool StockCtl(CCircuitUnit@ u)
{
	return StockArmy() && (u !is null) && StockDef(u.circuitDef);
}

// true: the layer stands down, counted under its tag
bool StockQuiet(const string &in tag)
{
	if (!StockArmy())
		return false;
	for (uint i = 0; i < gSaTag.length(); ++i) {
		if (gSaTag[i] == tag) {
			++gSaN[i];
			return true;
		}
	}
	gSaTag.insertLast(tag);
	gSaN.insertLast(1);
	return true;
}

bool StockQuietUnit(CCircuitUnit@ u, const string &in tag)
{
	return StockCtl(u) && StockQuiet(tag);
}

void StockArmyStat()
{
	if (ai.frame < gSaNextLog)
		return;
	gSaNextLog = ai.frame + 60 * SECOND;
	string q;
	for (uint i = 0; i < gSaTag.length(); ++i) {
		q += ((i == 0) ? "" : " ") + gSaTag[i] + "=" + gSaN[i];
		gSaN[i] = 0;
	}
	AiLog(Factory::T() + "apex: stockarmy-stat t=" + ai.teamId + " on=" + (StockArmy() ? 1 : 0)
		+ " " + aiMilitaryMgr.StockArmyStat() + " quiet=[" + q + "]");
}

}  // namespace Military
