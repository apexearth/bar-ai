namespace Base {

CCircuitDef@ AxisProbeDef()
{
	return SideDef3(Builder::armsolar, Builder::corsolar, Builder::legsolar);
}

int AxisScore(const AIFloat3& in fwd, const AIFloat3& in across, CCircuitDef@ probe)
{
	if (probe is null)
		return 0;
	const uint cols = ColCount(ECO);
	if (cols == 0)
		return 0;
	int ok = 0;
	for (int row = 0; row < AXIS_PROBE_ROWS; ++row) {
		const float depth = BAND_BACK[ECO] + float(row) * BAND_ROW[ECO] * 3.f;
		for (uint c = 0; c < cols; c += AXIS_PROBE_STEP) {
			const AIFloat3 cell = gAnchor - fwd * depth + across * ColAt(ECO, c);
			if (!OnMap(cell))
				continue;
			const AIFloat3 site = ai.FindBuildSiteNear(probe, cell, SEEK);
			if (OnMap(site) && (site.distance2D(cell) <= SEEK))
				++ok;
		}
	}
	return ok;
}

// Establish anchor and axis, latching each once it is real.
bool Frame()
{
	EnsureCols();
	if (!gAnchorSet) {
		if (Factory::gT1FacUnit !is null) {
			gAnchor = Factory::gT1FacUnit.GetPos(ai.frame);
			gAnchorSet = true;
		} else if (Builder::gHomeSet) {
			gAnchor = Builder::gHomePos;
			gAnchorSet = true;
		} else {
			return false;
		}
	} else if (!gAnchorFinal && (Factory::gT1FacUnit !is null)) {
		// Promote from the commander's start to the factory, once. Moving the
		// anchor after anything is standing would slide every row out from under
		// it, and what was a lane would become a row -- so the promotion is also
		// what makes the anchor final, and it is given a deadline in case no
		// factory ever appears.
		gAnchor = Factory::gT1FacUnit.GetPos(ai.frame);
	}
	if (!gAnchorFinal
			&& ((Factory::gT1FacUnit !is null) || (ai.frame >= ANCHOR_DEADLINE)))
		gAnchorFinal = true;

	if (!gAxisSet) {
		AIFloat3 toward;
		bool have = Front::FrontNear(gAnchor, toward);
		if (!have) {
			toward = aiEnemyMgr.GetEnemyPos();
			have = OnMap(toward);
		}
		if (!have)
			return false;
		AIFloat3 f = toward - gAnchor;
		if (f.SqLength2D() < NEAR_ZERO)
			return false;
		f.SafeNormalize2D();
		// TO THE NEAREST CARDINAL. A structure's footprint is an axis-aligned
		// rectangle on the world lattice -- CTerrainManager::FindBuildSiteByMask
		// derives its corner from int(pos.x / 16), int(pos.z / 16) and can only
		// return a position on it. A band frame at any other angle turns a step of
		// one pitch into a diagonal world offset, so two neighbours a pitch apart
		// have to be staggered in x and z to avoid overlapping, and the rows they
		// were meant to form come out as a staircase. Quantising here is what lets
		// depth and lateral map onto world x and z, and the pitches in EnsureCols
		// then tile exactly.
		//
		// It also makes the four candidates below the four cardinals.
		if (Abs(f.x) >= Abs(f.z))
			f = AIFloat3((f.x >= 0.f) ? 1.f : -1.f, 0.f, 0.f);
		else
			f = AIFloat3(0.f, 0.f, (f.z >= 0.f) ? 1.f : -1.f);
		AIFloat3 a(-f.z, 0.f, f.x);

		CCircuitDef@ probe = AxisProbeDef();
		const int front = AxisScore(f, a, probe);
		int best = front;
		AIFloat3 bf = f;
		AIFloat3 ba = a;
		for (int t = 1; t < 4; ++t) {
			AIFloat3 cf;
			if (t == 1)
				cf = AIFloat3(-f.x, 0.f, -f.z);
			else if (t == 2)
				cf = AIFloat3(-f.z, 0.f, f.x);
			else
				cf = AIFloat3(f.z, 0.f, -f.x);
			const AIFloat3 ca(-cf.z, 0.f, cf.x);
			const int s = AxisScore(cf, ca, probe);
			// Only a candidate that more than doubles the front-derived score can
			// take the axis; below that the front-facing one stands.
			if ((s > best) && (s > front * 2)) {
				best = s;
				bf = cf;
				ba = ca;
			}
		}

		gFwd = bf;
		gAcross = ba;
		gAxisSet = true;
		AiLog("apex: base frame anchor=" + int(gAnchor.x) + "," + int(gAnchor.z)
			+ " fwd=" + formatFloat(gFwd.x, "", 0, 2) + "," + formatFloat(gFwd.z, "", 0, 2)
			+ " axis front=" + front + " kept=" + best);
	}

	// Hand the frame down to C++, which snaps every non-fixed placement onto it
	// -- including the ones stock task selection makes, which is the whole base
	// rather than the handful of structures this file positions itself. Held back
	// until the anchor is final: a grid that moves is worse than none, because
	// everything already standing is then off it.
	if (!gPublished && gAnchorFinal) {
		gPublished = true;
		ai.SetBaseGrid(gAnchor, gFwd, GRID_CELL, LANE_PITCH, LANE_HALF, GRID_RANGE);
		AiLog("apex: base grid published cell=" + int(GRID_CELL)
			+ " lane=" + int(LANE_PITCH) + "/" + int(LANE_HALF)
			+ " range=" + int(GRID_RANGE));
	}
	return true;
}

// Bands are laid out as gAnchor - gFwd * depth (reserve.as, CellPos), so a
// deeper band is only further from the enemy while gFwd still points at them --
// and AxisScore above may replace the front-derived axis with its 180-flip.
bool AxisIsRearward()
{
	if (!gAxisSet)
		return false;
	const AIFloat3 foe = aiEnemyMgr.GetEnemyPos();
	if (!OnMap(foe))
		return false;
	const float ex = foe.x - gAnchor.x;
	const float ez = foe.z - gAnchor.z;
	if ((ex * ex + ez * ez) < NEAR_ZERO)
		return false;
	return ((gFwd.x * ex) + (gFwd.z * ez)) > 0.f;
}

bool Ready() { return gAnchorSet && gAxisSet; }

}  // namespace Base
