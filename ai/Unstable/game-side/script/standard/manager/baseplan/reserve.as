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

// How close two resolved sites may be before the second is treated as the first.
// One build cell inside the band's pitch: a neighbour standing edge to edge is a
// whole pitch away and stays legal, while two cells that resolved onto the same
// ground are caught.
float SiteR(int kind)
{
	return BAND_COL[kind] - BUILD_CELL;
}

// Score a placement against the ones before it and remember it. A site within
// one pitch of an earlier site of the same kind is standing against it; further
// than that and there is ground between them that nothing will ever use.
void NoteTiling(int kind, const AIFloat3& in site)
{
	float best = -1.f;
	for (uint i = 0; i < gTileX.length(); ++i) {
		if (gTileKind[i] != kind)
			continue;
		const float dx = site.x - gTileX[i];
		const float dz = site.z - gTileZ[i];
		const float d = dx * dx + dz * dz;
		if ((best < 0.f) || (d < best))
			best = d;
	}
	if (best >= 0.f) {
		const float pitch = BAND_COL[kind] + BUILD_CELL;
		if (best <= (pitch * pitch))
			++gTouch;
		else
			++gApart;
	}
	if (gTileX.length() < uint(TILE_MEMORY)) {
		gTileX.insertLast(site.x);
		gTileZ.insertLast(site.z);
		gTileKind.insertLast(kind);
		return;
	}
	if (gTileNext >= TILE_MEMORY)
		gTileNext = 0;
	gTileX[uint(gTileNext)] = site.x;
	gTileZ[uint(gTileNext)] = site.z;
	gTileKind[uint(gTileNext)] = kind;
	++gTileNext;
}

void ReserveSite(const AIFloat3& in site)
{
	gResX.insertLast(site.x);
	gResZ.insertLast(site.z);
	gResSiteFrame.insertLast(ai.frame);
}

bool SiteTaken(int kind, const AIFloat3& in site)
{
	const float r = SiteR(kind);
	for (uint i = 0; i < gResX.length(); ++i) {
		if (ai.frame >= gResSiteFrame[i] + RESERVE_TTL)
			continue;
		const float dx = site.x - gResX[i];
		const float dz = site.z - gResZ[i];
		if ((dx * dx + dz * dz) < (r * r))
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
// WALKWAYS RUN FORWARD OF THE ANCHOR ONLY. Behind it is the economy, where
// nothing marches; a street there only pushed the next converter across it
// from the turrets that would have built it (apexearth 2026-09-14: "in the
// back of our base we don't need any lanes for units to walk... We need to
// designate certain zones as 'we don't care about pathing here' zones").
// The plants' doorways are kept by their own test.
bool LanesApply(float depth)
{
	return depth <= 0.f;
}

bool InLaneAt(const AIFloat3& in p)
{
	if (!Ready())
		return false;
	float depth, lat;
	Coords(p, depth, lat);
	if (!LanesApply(depth))
		return false;
	return (LaneGap(lat) < LaneHalf()) || (LaneGap(depth) < LaneHalf());
}

}  // namespace Base
