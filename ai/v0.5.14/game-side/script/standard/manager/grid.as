//------------------------------------------------------------------------------
// A BUCKET GRID over points. Every "what is near here" question in this AI was
// a full array walk, so its cost was (asks) x (things we own) -- the shape that
// turns an hour-long game into a slideshow while a 10-minute one looks fine.
//
// EXACTNESS IS THE WHOLE POINT. A query returns a SUPERSET of the points inside
// an axis-aligned box of half-extent `r`, and the caller applies its own test
// unchanged. The bucket range is derived from the query box rather than fixed at
// 3x3, so no cell size can make a query miss a point; anything that lands
// outside the built box goes in `spill`, which every query returns.
//------------------------------------------------------------------------------
namespace Grid {

final class Cells
{
	float cell = 256.f;
	float minX = 0.f;
	float minZ = 0.f;
	int nx = 1;
	int nz = 1;
	array<int> head;    // first item id in each bucket, -1 for empty
	// A BUCKET IS EMPTY UNLESS THIS BUILD TOUCHED IT. Clearing the whole table
	// per Begin is the one cost a rebuild-on-change owner pays even when nothing
	// is near, and a big map is thousands of buckets; the generation makes Begin
	// O(1) instead.
	array<int> gen;
	int era = 0;
	array<int> next;    // per item: the next id in its bucket
	array<float> px;
	array<float> pz;
	array<int> spill;   // items outside the box: always candidates
	array<int> hit;     // the last query's candidates, reused between queries
	int n = 0;

	// A box and a cell size. Rebuilt from scratch by its owner; the arrays keep
	// their capacity, so a rebuild allocates nothing after the first one.
	void Begin(float cellSize, float x0, float z0, float x1, float z1)
	{
		cell = (cellSize > 16.f) ? cellSize : 16.f;
		minX = x0;
		minZ = z0;
		float fx = (x1 - x0) / cell;
		float fz = (z1 - z0) / cell;
		nx = (fx > 0.f) ? (int(fx) + 1) : 1;
		nz = (fz > 0.f) ? (int(fz) + 1) : 1;
		// A grid nobody can afford to clear is worse than the walk it replaces;
		// one bucket degrades to that walk rather than to a wrong answer.
		if ((nx * nz) > 16384) {
			nx = 1;
			nz = 1;
		}
		const uint want = uint(nx * nz);
		if (head.length() != want) {
			head.resize(want);
			gen.resize(want);
		}
		++era;   // every bucket is now stale, and none had to be written
		next.resize(0);
		px.resize(0);
		pz.resize(0);
		spill.resize(0);
		n = 0;
	}

	// Ids are handed out in insertion order, so an owner whose own array only
	// ever appends can Add the new tail instead of rebuilding.
	int Add(float x, float z)
	{
		const int id = n;
		px.insertLast(x);
		pz.insertLast(z);
		++n;
		const float fx = (x - minX) / cell;
		const float fz = (z - minZ) / cell;
		if ((fx < 0.f) || (fz < 0.f)) {
			next.insertLast(-1);
			spill.insertLast(id);
			return id;
		}
		const int bx = int(fx);
		const int bz = int(fz);
		if ((bx >= nx) || (bz >= nz)) {
			next.insertLast(-1);
			spill.insertLast(id);
			return id;
		}
		const uint b = uint(bz * nx + bx);
		if (gen[b] != era) {
			gen[b] = era;
			head[b] = -1;
		}
		next.insertLast(head[b]);
		head[b] = id;
		return id;
	}

	// Every id whose point lies in [x-r, x+r] x [z-r, z+r], plus the spill --
	// left in `hit`. The bucket span is taken from the box itself, which is what
	// makes any cell size exact: a point at |dx| <= r is inside the x span, so
	// its bucket column is inside the scanned column range.
	void Query(float x, float z, float r)
	{
		hit.resize(0);
		for (uint s = 0; s < spill.length(); ++s)
			hit.insertLast(spill[s]);
		if (n == 0)
			return;
		float flo = (x - r - minX) / cell;
		float fhi = (x + r - minX) / cell;
		if (fhi < 0.f)
			return;
		int bx0 = (flo < 0.f) ? 0 : int(flo);
		int bx1 = int(fhi);
		if (bx0 >= nx)
			return;
		if (bx1 >= nx)
			bx1 = nx - 1;
		flo = (z - r - minZ) / cell;
		fhi = (z + r - minZ) / cell;
		if (fhi < 0.f)
			return;
		int bz0 = (flo < 0.f) ? 0 : int(flo);
		int bz1 = int(fhi);
		if (bz0 >= nz)
			return;
		if (bz1 >= nz)
			bz1 = nz - 1;
		for (int bz = bz0; bz <= bz1; ++bz) {
			const int row = bz * nx;
			for (int bx = bx0; bx <= bx1; ++bx) {
				const uint b = uint(row + bx);
				if (gen[b] != era)
					continue;
				for (int id = head[b]; id >= 0; id = next[uint(id)]) {
					// The bucket is coarser than the box; the box test is the
					// one the caller's own test is layered on.
					const uint u = uint(id);
					if ((abs(px[u] - x) <= r) && (abs(pz[u] - z) <= r))
						hit.insertLast(id);
				}
			}
		}
	}
}

}  // namespace Grid
