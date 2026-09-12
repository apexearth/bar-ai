namespace Base {

CCircuitDef@ AxisProbeDef()
{
	return SideDef3("armsolar", "corsolar", "legsolar");
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
		// Promote once from the commander's start to the factory; moving the anchor
		// after anything is standing would slide every row out from under it.
		gAnchor = Factory::gT1FacUnit.GetPos(ai.frame);
	} else if (!gAnchorFinal) {
		// Before the lab stands the anchor is the middle of what we have built
		// (apexearth: "the base anchor should depend on where our buildings
		// are placed. So if we made 3 mexes then our anchorpoint is between
		// them all"), so the lab lands among the mexes, not at the start.
		Market::PfRebuild();
		const uint n = Market::gPfPos.length();
		if (n > 0) {
			float cx = 0.f, cz = 0.f;
			for (uint i = 0; i < n; ++i) {
				cx += Market::gPfPos[i].x;
				cz += Market::gPfPos[i].z;
			}
			const AIFloat3 c(cx / float(n), 0.f, cz / float(n));
			if (OnMap(c))
				gAnchor = c;
		}
	}
	if (!gAnchorFinal
			&& ((Factory::gT1FacUnit !is null) || (ai.frame >= ANCHOR_DEADLINE)))
		gAnchorFinal = true;

	if (!gAxisSet) {
		AIFloat3 toward;
		string axisSrc = "front";
		bool have = Front::FrontNear(gAnchor, toward);
		// Every other GetEnemyPos() caller in this AI waits for gHomeSet first;
		// this was the one spot that didn't, and it runs as early as frame 0.
		if (!have && Builder::gHomeSet) {
			toward = aiEnemyMgr.GetEnemyPos();
			// (0,0,0) is GetEnemyPos's "nobody seen yet", and it IS on-map
			// (the standing uninitialized-AIFloat3 trap) -- the axis aimed
			// at the MAP CORNER and every band, exit lane and fusion marched
			// enemy-ward off it (his game 2026-08-28: anchor 581,396,
			// fwd -1,0, front=0, "we're building this stuff towards the
			// enemy base - fusions included").
			have = OnMap(toward)
				&& ((toward.x > 1.f) || (toward.z > 1.f));
			if (have)
				axisSrc = "enemy";
		}
		if (!have && Builder::gHomeSet) {
			axisSrc = "mirror";
			// NO INFORMATION MEANS THE MIRROR -- the same symmetric-start
			// prior GradAt already stands on: the enemy is at the map-center
			// reflection of our own anchor until seen otherwise.
			toward = AIFloat3(float(AiTerrainWidth()) - gAnchor.x, 0.f,
					float(AiTerrainHeight()) - gAnchor.z);
			have = OnMap(toward);
		}
		if (!have)
			return false;
		AIFloat3 f = toward - gAnchor;
		if (f.SqLength2D() < NEAR_ZERO)
			return false;
		f.SafeNormalize2D();
		// TO THE NEAREST CARDINAL. FindBuildSiteByMask derives its corner from
		// int(pos.x / 16), int(pos.z / 16), so a band frame at any other angle
		// turns a step of one pitch into a diagonal offset and the rows stagger
		// into a staircase instead of tiling. Also makes the four candidates below
		// the four cardinals.
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
		// The 180 flip is never a candidate: bands are laid at gAnchor - fwd,
		// so the flip lays every eco building TOWARD the enemy. A start close
		// to a map edge scores the true rear at zero (the band probe walks off
		// the map) and the flip then wins on any count at all -- watched on
		// Altair Crossing, anchor 465 from the west wall, front=0 kept=44,
		// solars marching at the enemy. If the rear is unbuildable the
		// perpendiculars are the acceptable fallback, not the enemy's lap.
		for (int t = 2; t < 4; ++t) {
			AIFloat3 cf;
			if (t == 2)
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

		// THE MIRROR HAS THE LAST WORD ON SIGN. An edge start zeroes the
		// true rear's band score and a PERPENDICULAR wins -- and its sign is
		// arbitrary, so the base laid sideways with its bands opening
		// enemy-ward (Prismatic 2v2: anchor 671,7674, front=0 kept=31,
		// src=front, fwd=-1,0 pointing at the west wall). Whatever candidate
		// wins, fwd must not point AWAY from where a symmetric start puts
		// the enemy; if it does, the flip of the winner is the same band
		// geometry with the bands opening rearward, so take it.
		string mir = "ok";
		{
			const float mx = float(AiTerrainWidth()) * 0.5f;
			const float mz = float(AiTerrainHeight()) * 0.5f;
			const float ex2 = (mx - gAnchor.x) * 2.f + gAnchor.x;
			const float ez2 = (mz - gAnchor.z) * 2.f + gAnchor.z;
			const float dot = bf.x * (ex2 - gAnchor.x) + bf.z * (ez2 - gAnchor.z);
			if (dot < 0.f) {
				bf.x = -bf.x;
				bf.z = -bf.z;
				ba.x = -ba.x;
				ba.z = -ba.z;
				mir = "flip";
			}
		}
		gFwd = bf;
		gAcross = ba;
		gAxisSet = true;
		AiLog("apex: base frame anchor=" + int(gAnchor.x) + "," + int(gAnchor.z)
			+ " fwd=" + formatFloat(gFwd.x, "", 0, 2) + "," + formatFloat(gFwd.z, "", 0, 2)
			+ " axis front=" + front + " kept=" + best + " src=" + axisSrc
			+ " mir=" + mir);
	}

	// Hand the frame down to C++, which snaps every non-fixed placement onto it,
	// including stock task selection's. Held back until the anchor is final: a
	// grid that moves puts everything already standing off it.
	// No grid handed to C++: the engine's spiral from the farm centre and
	// the stock block map lay the base out (FarmSlot).
	if (!gPublished && gAnchorFinal)
		gPublished = true;
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
