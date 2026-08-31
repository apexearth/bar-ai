namespace Market {
// Does any STANDING advanced builder of ours (mobile, not a T1 hand) produce
// ground defence? 5s memo -- read once per candidate loop, not per def.
int gT2HandAt = -999999;
bool gT2HandUp = false;
bool T2DefHandsStanding()
{
	if (ai.frame - gT2HandAt < 5 * SECOND)
		return gT2HandUp;
	gT2HandAt = ai.frame;
	gT2HandUp = false;
	for (uint c = 1; c < gOwnCount.length(); ++c) {
		const int ci = int(c);
		if ((gOwnCount[c] <= 0) || !Catalog::gMobile[ci])
			continue;
		if ((ci < int(Catalog::gT1Hand.length())) && Catalog::gT1Hand[ci])
			continue;
		const array<int>@ bl = Catalog::gBuildsList[ci];
		for (uint q = 0; q < bl.length(); ++q) {
			if (!Catalog::gMobile[bl[q]] && (Catalog::gSurfT[bl[q]] > 0.f)) {
				gT2HandUp = true;
				return true;
			}
		}
	}
	return false;
}

// THE TEETH LINE. apexearth's concentration ruling, 2026-08-29: "slow them
// down with some walls outside so enemy army is broken up before they get
// to us... We need to ensure that enemies cannot walk past our choke
// points and get a free path to our economy." One tooth per election,
// across the span of the strongest DEFENDED gate (a wall only works inside
// our own fire), offset a step enemy-ward of the doorway. The def is
// derived (Catalog::WallDef), the gain is a preference priced like
// apex_mexup_boost -- his ruling is the basis -- and each tooth is cheap
// enough that the walk is the real cost.
int gTeethNextScan = 0;
AIFloat3 gTeethPoint(-1.f, 0.f, -1.f);
int gDEnds = 0;
int gDLen = 0;
int gDBlocked = 0;

Want@ ProposeTeeth(CCircuitUnit@ unit)
{
	Want w;
	if (ai.GetTunable("apex_teeth", TUNE_TEETH) <= 0.f)
		return w;
	if (!Builder::gHomeSet)
		return w;
	const int wd = Catalog::WallDef();
	if (wd <= 0)
		return w;
	if (ai.frame >= gTeethNextScan) {
		const bool diag = (gTeethNextScan > 0)
			&& (ai.frame >= gTeethNextScan + 50 * SECOND);   // ~once a minute
		gTeethNextScan = ai.frame + 10 * SECOND;
		gTeethPoint = AIFloat3(-1.f, 0.f, -1.f);
		array<int> gidx;
		Front::GateChokeIdxs(gidx);
		// Nearest gate to home first -- his ruling puts the walls BEFORE the
		// push arrives, so teeth do not wait for the gate's towers (that
		// prerequisite deadlocked: 14 minutes, 3 towers, none at a gate,
		// zero teeth in 24 tournament games). A cheap wall unbacked by guns
		// still slows and splits; the guns follow it.
		for (uint pass = 0; pass < gidx.length(); ++pass) {
			int gi = -1;
			float bestD = 1e12f;
			for (uint g = 0; g < gidx.length(); ++g) {
				if (gidx[g] < 0)
					continue;
				const float dd = ai.GetChokePointPos(gidx[g])
						.distance2D(Builder::gHomePos);
				if (dd < bestD) {
					bestD = dd;
					gi = int(g);
				}
			}
			if (gi < 0)
				break;
			const AIFloat3 cp = ai.GetChokePointPos(gidx[gi]);
			const int gateIdx = gidx[gi];
			gidx[gi] = -1;   // consumed for this scan pass
			AIFloat3 e1;
			AIFloat3 e2;
			if (!ai.GetChokePointEnds(gateIdx, e1, e2)) {
				++gDEnds;
				continue;
			}
			AIFloat3 span = e2 - e1;
			const float len = sqrt(span.SqLength2D());
			if ((len < 32.f) || (len > 1400.f)) {
				++gDLen;
				continue;
			}
			span *= (1.f / len);
			AIFloat3 outDir = cp - Builder::gHomePos;
			const float olen = sqrt(outDir.SqLength2D());
			if (olen < 1.f)
				continue;
			outDir *= (1.f / olen);
			const float pitch = 48.f;
			const int nT = int(len / pitch) + 1;
			for (int k = 0; k < nT; ++k) {
				AIFloat3 p = e1 + span * (pitch * float(k)) + outDir * 140.f;
				if (!OnMap(p)) {
					++gDBlocked;
					continue;
				}
				array<CCircuitUnit@>@ near = ai.GetOwnStructsNear(p, 40.f);
				if ((near !is null) && (near.length() > 0)) {
					++gDBlocked;
					continue;
				}
				gTeethPoint = p;
				break;
			}
			if (OnMap(gTeethPoint))
				break;
		}
		if (diag || (ai.frame % (60 * SECOND) < 10 * SECOND))
			AiLog(Factory::T() + "apex: teeth-scan wall=" + wd
				+ " gates=" + gidx.length()
				+ " towers=" + gProtPos[PROT_DEF].length()
				+ " point=" + int(gTeethPoint.x) + "," + int(gTeethPoint.z)
				+ " endsF=" + gDEnds + " lenF=" + gDLen + " blkF=" + gDBlocked);
	}
	if (!OnMap(gTeethPoint))
		return w;
	const int uid = int(unit.circuitDef.id);
	const float speed = Catalog::gSpeed[uid];
	const float walkSec = (speed > 1.f)
			? (unit.GetPos(ai.frame).distance2D(gTeethPoint) / speed) : 60.f;
	Want c;
	ValueOf(wd, ai.GetTunable("apex_teeth_gain", TUNE_TEETH_GAIN), walkSec,
			Catalog::gBuildPower[uid], c);
	w = c;
	w.kind = WK_TEETH;
	@w.def = Catalog::Def(wd);
	w.pos = gTeethPoint;
	return w;
}
}  // namespace Market
