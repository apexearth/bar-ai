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
	const array<int>@ _own27 = OwnedDefs();
	for (uint _oi27 = 0; _oi27 < _own27.length(); ++_oi27) {
		const uint c = uint(_own27[_oi27]);
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
int gTeethNextScan = 103;   // phase offset -- see AiUpdate lockstep note
// TEETH AROUND A TOWER (his 10-13: "if you make dragons defense turrets and put dragons teeth
// around them the teeth can block some of the hits"). Slots in an arc on the tower's enemy side;
// a tooth is worth the share of the tower's guarding (the stake in its reach at the expected
// siege) that its health takes off the tower, halved per tooth already standing there.
// Scanned with the gates, every 10 s; at most a few towers by a few slots.
// Inside the base, teeth only clutter it (his 10-13: "found its way into the center of our base
// and it's not very good there"): a point with our own buildings around it, guns, walls and
// extractors aside, is base.
bool TeethInBase(const AIFloat3& in p, int wd)
{
	array<CCircuitUnit@>@ near = ai.GetOwnStructsNear(p, 400.f);
	int n = 0;
	for (uint q = 0; (near !is null) && (q < near.length()); ++q) {
		if ((near[q] is null) || (near[q].circuitDef is null))
			continue;
		const int d = int(near[q].circuitDef.id);
		if ((d != wd) && (ProtClassOf(d) < 0) && (Catalog::gExtractsM[d] <= 0.f))
			++n;
	}
	return n >= 3;
}

// Each tooth takes a unit slot (his 10-13): worth falls with the share of the limit we fill.
float TeethCapRoom()
{
	int lim = int(parseInt(string(aiSetupMgr.GetModOptions()["maxunits"])));
	if (lim <= 0)
		lim = 2000;
	int have = 0;
	for (uint d = 1; d < gOwnCount.length(); ++d)
		have += gOwnCount[d];
	const float room = 1.f - float(have) / float(lim);
	return (room > 0.f) ? room : 0.f;
}

float gTeethCapRoom = 1.f;   // TeethCapRoom at the last scan
AIFloat3 gRingPoint(-1.f, 0.f, -1.f);
float gRingGain = 0.f;
int gRingBuilt = 0;   // teeth standing in ring slots, at the last scan
void ScanTowerRing(int wd)
{
	gRingPoint = AIFloat3(-1.f, 0.f, -1.f);
	gRingGain = 0.f;
	gRingBuilt = 0;
	const AIFloat3 foe = aiEnemyMgr.GetEnemyPos();
	if (!OnMap(foe))
		return;
	const float wallHp = Catalog::gHealth[wd];
	for (uint t = 0; t < gProtPos[PROT_DEF].length(); ++t) {
		const int td = gProtDefId[PROT_DEF][t];
		const AIFloat3 tp = gProtPos[PROT_DEF][t];
		const float thp = Catalog::gHealth[td];
		if ((thp <= 0.f) || (Catalog::gMaxRange[td] <= 1.f) || !OnMap(tp) || TeethInBase(tp, wd))
			continue;
		AIFloat3 dir = foe - tp;
		dir.SafeNormalize2D();
		const AIFloat3 side(-dir.z, 0.f, dir.x);
		const float r = 8.f * float((Catalog::gFootX[td] > Catalog::gFootZ[td]) ? Catalog::gFootX[td] : Catalog::gFootZ[td]) + 40.f;
		int have = 0;
		AIFloat3 free(-1.f, 0.f, -1.f);
		for (int k = -2; k <= 2; ++k) {
			const AIFloat3 p = tp + dir * r + side * (40.f * float(k));
			if (!OnMap(p))
				continue;
			array<CCircuitUnit@>@ near = ai.GetOwnStructsNear(p, 20.f);
			bool wall = false, other = false;
			for (uint q = 0; (near !is null) && (q < near.length()); ++q) {
				if ((near[q] !is null) && (near[q].circuitDef !is null) && (int(near[q].circuitDef.id) == wd))
					wall = true;
				else
					other = true;
			}
			if (wall)
				++have;
			else if (!other && !OnMap(free))
				free = p;
		}
		gRingBuilt += have;
		if (!OnMap(free))
			continue;
		float hz = HazardAt(tp);
		const float sg = SiegeExpect(tp);
		if (sg > hz)
			hz = sg;
		const float g = StakeAt(tp, Catalog::gMaxRange[td]) * hz
				* (wallHp / (wallHp + thp)) / float(1 << have);
		if (g > gRingGain) {
			gRingGain = g;
			gRingPoint = free;
		}
	}
}

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
	const int wd = Catalog::WallDefFor(int(unit.circuitDef.id));
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
		// No gate: the line's own front row, where mains stand behind.
		if (!OnMap(gTeethPoint)) {
			AIFloat3 lp;
			if (WallTeethPoint(lp))
				gTeethPoint = lp;
		}
		gTeethCapRoom = TeethCapRoom();
		if (OnMap(gTeethPoint) && (TeethInBase(gTeethPoint, wd) || Builder::PastFront(gTeethPoint)))
			gTeethPoint = AIFloat3(-1.f, 0.f, -1.f);
		if (diag || (ai.frame % (60 * SECOND) < 10 * SECOND))
			AiLog(Factory::T() + "apex: teeth-scan wall=" + wd
				+ " gates=" + gidx.length()
				+ " towers=" + gProtPos[PROT_DEF].length()
				+ " point=" + int(gTeethPoint.x) + "," + int(gTeethPoint.z)
				+ " endsF=" + gDEnds + " lenF=" + gDLen + " blkF=" + gDBlocked
				+ " ring=" + int(gRingPoint.x) + "," + int(gRingPoint.z) + "/" + formatFloat(gRingGain, "", 0, 2)
				+ " ringBuilt=" + gRingBuilt);
		ScanTowerRing(wd);
	}
	if (!OnMap(gTeethPoint) && !OnMap(gRingPoint))
		return w;
	const int uid = int(unit.circuitDef.id);
	const float speed = Catalog::gSpeed[uid];
	// PRICED AS THE SOAK IT IS, not a preference: the same prevented loss a
	// front-row slot earns (protect_fill.as) -- the team metal behind the
	// gap, the hazard there, and the share of the wave this tooth's health
	// absorbs for the guns behind it. A fixed gain of 40 outbid every real
	// gun (1517 of 1548 defence elections were teeth, guns priced 2-15).
	float gain = 0.f;
	if (OnMap(gTeethPoint)) {
		const float wave = ArmyTargetFull()
				* ai.GetTunable("apex_def_prior_share", TUNE_DEF_PRIOR_SHARE)
				* TeamExposure();
		const float cover0 = CoverAt(gTeethPoint);
		if (wave > 1.f) {
			float mainsFrac = cover0 / wave;
			if (mainsFrac > 1.f)
				mainsFrac = 1.f;
			const float cover1 = cover0 + PfAbsorb(wd) * mainsFrac;
			float short0 = (wave - cover0) / wave;
			if (short0 < 0.f)
				short0 = 0.f;
			float short1 = (wave - cover1) / wave;
			if (short1 < 0.f)
				short1 = 0.f;
			float stake = GapBehindAt(gTeethPoint);
			const float near = StakeAt(gTeethPoint, Brain::LightTowerRange());
			if (near > stake)
				stake = near;
			gain = stake * HazardWith(gTeethPoint, cover0) * (short0 - short1);
		}
	}
	AIFloat3 at = gTeethPoint;
	if (gRingGain > gain) {
		gain = gRingGain;
		at = gRingPoint;
	}
	gain *= gTeethCapRoom;
	if (gain <= 0.f)
		return w;
	const float walkSec = (speed > 1.f) ? (unit.GetPos(ai.frame).distance2D(at) / speed) : 60.f;
	Want c;
	ValueOf(wd, gain, walkSec, Catalog::gBuildPower[uid], c);
	w = c;
	w.kind = WK_TEETH;
	@w.def = Catalog::Def(wd);
	w.pos = at;
	return w;
}
}  // namespace Market
