// Map geometry shared by every manager.
//
// Not in a namespace: this was Builder::OnMap and five other namespaces reached
// across for it, which is the shape of a helper that belongs to nobody.

// CThreatMap indexes its arrays straight from the position and range-checks only
// under assert; the bound is a strict less-than against the terrain extent.
// -RgtVector, the engine's "no position", fails the first test.
bool OnMap(const AIFloat3& in p)
{
	return (p.x >= 0.f) && (p.z >= 0.f)
		&& (p.x < float(AiTerrainWidth())) && (p.z < float(AiTerrainHeight()));
}
