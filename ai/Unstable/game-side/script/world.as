// Map geometry shared by every manager.
//
// Not in a namespace: this was Builder::OnMap and five other namespaces reached
// across for it, which is the shape of a helper that belongs to nobody.

// CThreatMap indexes its arrays straight from the position and range-checks only
// under assert; the bound is a strict less-than against the terrain extent.
// -RgtVector, the engine's "no position", fails the first test.
// The terrain extent does not change after the map loads, and this is the most
// called function in the script -- every loop over positions ends in it. Two
// registered engine calls per test is two calls per position tested.
float gMapW = 0.f;
float gMapH = 0.f;

bool OnMap(const AIFloat3& in p)
{
	if (gMapW <= 0.f) {
		gMapW = float(AiTerrainWidth());
		gMapH = float(AiTerrainHeight());
	}
	return (p.x >= 0.f) && (p.z >= 0.f) && (p.x < gMapW) && (p.z < gMapH);
}

// Does apex's own game-side behaviour run at all? Always yes -- apex ran its
// own logic only when it had allies (2026-08-10), on the measurement that a
// solo game had nobody to pool metal with, hold ground for, or share a front
// line with. Removed 2026-08-14: that measurement predates multiple crash
// fixes, the commander opening fixes, and squad cohesion/positioning fixes,
// and apexearth wants apex running its own logic regardless of ally count.
// Every call site still calls this rather than being ripped out directly, so
// reinstating the gate (if ever warranted) is a one-function change again.
bool ApexActive()
{
	return true;
}
