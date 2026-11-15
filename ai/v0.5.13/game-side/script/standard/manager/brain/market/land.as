namespace Market {
// LAND VALUE (apex_land_value; his 10-27: "a land value which grows proportionate to the surrounding building values
// we see"). Ground is worth what stands around it: our standing structures within LAND_R, their metal over the
// circle's cells, so a footprint pays that metal per cell for every cell it takes. Cheap, sparse builds (a basic
// solar's 20 E on the ground a fusion block wants) pay core rent or go to the edge; dense ones can afford the core.
// A want is not standing, so it never raises its own rent. Extractors and geo are spot-bound and pay none.
const float LAND_R = 300.f;
array<float> gLvVal;
array<int> gLvAt;
int gLvCellsZ = 0;
int gLvOn = -1;
bool LandValueOn()
{
	if (gLvOn < 0)
		gLvOn = (ai.GetTunable("apex_land_value", TUNE_LAND_VALUE) > 0.f) ? 1 : 0;
	return gLvOn > 0;
}

// our standing structure metal per footprint cell around pos, cached per 256-elmo cell for 5 s
float LandPerCell(const AIFloat3& in pos)
{
	if (!OnMap(pos))
		return 0.f;
	if (gLvCellsZ == 0) {
		gLvCellsZ = (AiTerrainHeight() >> 8) + 1;
		const uint n = uint(((AiTerrainWidth() >> 8) + 1) * gLvCellsZ);
		gLvVal.resize(n);
		gLvAt.resize(n);
		for (uint i = 0; i < n; ++i)
			gLvAt[i] = -1000000;
	}
	const uint slot = uint((int(pos.x) >> 8) * gLvCellsZ + (int(pos.z) >> 8));
	if (slot >= gLvAt.length())
		return 0.f;
	if (ai.frame - gLvAt[slot] < 5 * SECOND)
		return gLvVal[slot];
	// COMPARABLES x HOW FULL THE GROUND IS: what stands here per cell it occupies (a fusion block ~93 metal a cell, a
	// solar field ~6) times the occupied share of the neighbourhood -- a cell costs something only as far as it pushes
	// another build out. The product is the neighbours' metal over the circle's cells. Comparables alone charged a
	// solar 155-268 metal at 16-20 m/s with the ground around it empty.
	ComNear(pos, LAND_R);
	float m = 0.f;
	for (uint q = 0; q < gComGrid.hit.length(); ++q) {
		const uint c = uint(gComGrid.hit[q]);
		const int cd = gComDef[c];
		if (!Catalog::ValidId(cd) || Catalog::gMobile[cd] || (gComState[c] != CS_FINISHED)
			|| (Catalog::gExtractsM[cd] > 0.f))
			continue;
		if (gComPos[c].distance2D(pos) < LAND_R)
			m += Catalog::gCostM[cd];
	}
	const float v = m / (3.14159f * LAND_R * LAND_R / 256.f);
	gLvAt[slot] = ai.frame;
	gLvVal[slot] = v;
	return v;
}

// the rent a want's footprint pays, in metal; the flat per-cell price (apex_space_m) is its floor
float LandRentM(Want@ w)
{
	if (!LandValueOn() || (w is null) || (w.def is null) || !OnMap(w.pos))
		return 0.f;
	const int d = int(w.def.id);
	if (Catalog::gMobile[d] || (Catalog::gExtractsM[d] > 0.f) || Catalog::gNeedGeo[d] || (Catalog::gAreaCells[d] <= 0))
		return 0.f;
	return LandPerCell(w.pos) * float(Catalog::gAreaCells[d]);
}

// in the decision loop: the rent joins the bill and the value scales by the bill's growth
void LandApply(Want@ w)
{
	const float rent = LandRentM(w);
	if (rent <= 0.f)
		return;
	const float bill = w.mCost + w.tCost;
	w.mCost += rent;
	w.pcLand += rent;
	if (bill > 0.f)
		w.value *= bill / (bill + rent);
}

}  // namespace Market
