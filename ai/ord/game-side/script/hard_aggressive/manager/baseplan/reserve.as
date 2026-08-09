namespace Base {


// Band coordinates of a world position: how far BACK of the anchor, and how far
// to the side. Only meaningful once the frame is latched.
void Coords(const AIFloat3& in p, float& out depth, float& out lat)
{
	const float dx = p.x - gAnchor.x;
	const float dz = p.z - gAnchor.z;
	depth = -(dx * gFwd.x + dz * gFwd.z);
	lat = dx * gAcross.x + dz * gAcross.z;
}

bool CellPos(int kind, int index, AIFloat3& out cell)
{
	float lat, depth;
	if (!SlotAt(kind, index, lat, depth))
		return false;
	cell = gAnchor - gFwd * depth + gAcross * lat;
	return true;
}

void Reserve(int kind, int index)
{
	const int key = kind * 100000 + index;
	for (uint i = 0; i < gResIdx.length(); ++i) {
		if (gResIdx[i] == key) {
			gResFrame[i] = ai.frame;
			return;
		}
	}
	gResIdx.insertLast(key);
	gResFrame.insertLast(ai.frame);
}

bool Reserved(int kind, int index)
{
	const int key = kind * 100000 + index;
	for (uint i = 0; i < gResIdx.length(); ++i) {
		if ((gResIdx[i] == key) && (ai.frame < gResFrame[i] + RESERVE_TTL))
			return true;
	}
	return false;
}

void ReserveSite(const AIFloat3& in site)
{
	gResX.insertLast(site.x);
	gResZ.insertLast(site.z);
	gResSiteFrame.insertLast(ai.frame);
}

bool SiteTaken(const AIFloat3& in site)
{
	for (uint i = 0; i < gResX.length(); ++i) {
		if (ai.frame >= gResSiteFrame[i] + RESERVE_TTL)
			continue;
		const float dx = site.x - gResX[i];
		const float dz = site.z - gResZ[i];
		if ((dx * dx + dz * dz) < (RESERVE_R * RESERVE_R))
			return true;
	}
	return false;
}

void SweepReserves()
{
	for (uint i = 0; i < gResIdx.length();) {
		if (ai.frame >= gResFrame[i] + RESERVE_TTL) {
			gResIdx.removeAt(i);
			gResFrame.removeAt(i);
		} else {
			++i;
		}
	}
	for (uint i = 0; i < gResX.length();) {
		if (ai.frame >= gResSiteFrame[i] + RESERVE_TTL) {
			gResX.removeAt(i);
			gResZ.removeAt(i);
			gResSiteFrame.removeAt(i);
		} else {
			++i;
		}
	}
}

void Grow(int kind, int index)
{
	float lat, depth;
	if (!SlotAt(kind, index, lat, depth))
		return;
	if (!gGrown) {
		gGrown = true;
		gMinLat = lat;
		gMaxLat = lat;
		gMaxDepth = depth;
		return;
	}
	if (lat < gMinLat) gMinLat = lat;
	if (lat > gMaxLat) gMaxLat = lat;
	if (depth > gMaxDepth) gMaxDepth = depth;
}

// The committed rectangle, in elmos squared. Reported rather than acted on: it
// is the measure of whether the layout is holding, and it can be read without a
// win rate.
float Area()
{
	return gGrown ? ((gMaxLat - gMinLat) * gMaxDepth) : 0.f;
}

bool Inside(const AIFloat3& in p)
{
	if (!Ready() || !gGrown)
		return false;
	float depth, lat;
	Coords(p, depth, lat);
	return (depth >= -BAND_BACK[NANO]) && (depth <= gMaxDepth + BAND_ROW[HEAVY])
		&& (lat >= gMinLat - BAND_LAT_SLACK) && (lat <= gMaxLat + BAND_LAT_SLACK);
}

// Is this position standing in a walkway? Only asked of things already known to
// be inside the footprint.
bool InLaneAt(const AIFloat3& in p)
{
	if (!Ready())
		return false;
	float depth, lat;
	Coords(p, depth, lat);
	return LaneGap(lat) < LANE_HALF;
}

}  // namespace Base
