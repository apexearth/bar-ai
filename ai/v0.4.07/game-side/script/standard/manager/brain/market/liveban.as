namespace Market {

// LIVE, NOT BANNED (apex_live_not_ban, his 2026-10-16 after the three-minute mex ban): a
// judgement about a site is read from the live state or priced against the runner-up, never
// held on a clock. A refusal of one footprint refuses only footprints that hold it.
bool gLnbRead = false;
bool gLnbOn = false;
bool LiveNotBan()
{
	if (!gLnbRead) {
		gLnbRead = true;
		gLnbOn = ai.GetTunable("apex_live_not_ban", TUNE_LIVE_NOT_BAN) > 0.f;
	}
	return gLnbOn;
}

bool MarkBlocks(int markDef, int def)
{
	if ((markDef < 0) || (def < 0) || (markDef == def))
		return true;
	if (!Catalog::ValidId(markDef) || !Catalog::ValidId(def))
		return false;
	const int ma = Catalog::gFootX[markDef], mb = Catalog::gFootZ[markDef];
	const int da = Catalog::gFootX[def], db = Catalog::gFootZ[def];
	const int mHi = (ma > mb) ? ma : mb, mLo = (ma > mb) ? mb : ma;
	const int dHi = (da > db) ? da : db, dLo = (da > db) ? db : da;
	return (dHi >= mHi) && (dLo >= mLo);
}

bool NearBlockedDef(const AIFloat3& in p, int def)
{
	return LiveNotBan() ? NearBlockedFor(p, def) : NearBlocked(p);
}

int LnbMexDef()
{
	const int md = Military::NrMexDef();
	return (md > 0) ? md : -1;
}

int gLnbRefDef = 0, gLnbRefPath = 0, gLnbSpared = 0;
int gLnbGraveLive = 0, gLnbGraveDead = 0, gLnbGraveMoved = 0, gLnbGraveDropped = 0;
int gLnbStuckMarked = 0, gLnbStuckSpared = 0;
int gLnbAbortThreat = 0, gLnbAbortFrame = 0, gLnbAbortCounted = 0, gLnbAbortPriced = 0, gLnbAbortKept = 0;
int gLnbUpHot = 0, gLnbUpCleared = 0, gLnbUpRefused = 0;

// What killed our guns, seen or remembered now: the registry's armed units of a grave's
// killer def, once a frame.
array<int> gGfDef;
array<AIFloat3> gGfPos;
int gGfAt = -1;
void GraveFoesFill()
{
	if (gGfAt == ai.frame)
		return;
	gGfAt = ai.frame;
	gGfDef.resize(0);
	gGfPos.resize(0);
	const int n = aiEnemyMgr.GetEnemyUnitTotal();
	for (int i = 0; i < n; ++i) {
		const int d = aiEnemyMgr.GetEnemyUnitDefAt(i);
		if ((d <= 0) || (gGraveBy.find(d) < 0))
			continue;
		const int los = aiEnemyMgr.GetEnemyUnitLosAt(i);
		if ((los < 0) || ((los & (8 | 32 | 64)) != 0))
			continue;
		gGfDef.insertLast(d);
		gGfPos.insertLast(aiEnemyMgr.GetEnemyUnitPosAt(i));
	}
}

// Metal of the killers of a gun no stronger than d near p, standing where they reach p
// before d does (their range plus their walk over d's build).
float GraveDangerM(const AIFloat3& in p, int d, float buildSec)
{
	if (!OnMap(p) || !Catalog::ValidId(d) || (gGravePos.length() == 0))
		return 0.f;
	const float cost = Catalog::gCostM[d];
	array<int> by;
	for (uint i = 0; i < gGravePos.length(); ++i) {
		if ((gGravePos[i].distance2D(p) < BLOCK_NEAR) && (cost <= gGraveCost[i])
			&& Catalog::ValidId(gGraveBy[i]) && (by.find(gGraveBy[i]) < 0))
			by.insertLast(gGraveBy[i]);
	}
	if (by.length() == 0)
		return 0.f;
	GraveFoesFill();
	float m = 0.f;
	for (uint k = 0; k < gGfDef.length(); ++k) {
		const int kd = gGfDef[k];
		if (by.find(kd) < 0)
			continue;
		const float reach = Catalog::gLandRange[kd] + Catalog::gSpeed[kd] * buildSec;
		if (gGfPos[k].distance2D(p) <= reach)
			m += Catalog::gCostM[kd];
	}
	return m;
}

bool GraveNearAny(const AIFloat3& in p, float costM)
{
	for (uint i = 0; i < gGravePos.length(); ++i) {
		if ((gGravePos[i].distance2D(p) < BLOCK_NEAR) && (costM <= gGraveCost[i]))
			return true;
	}
	return false;
}

// The share of the fight there that our side holds: this gun plus the cover standing.
float GraveSurv(const AIFloat3& in p, int d, float buildSec)
{
	const float foe = GraveDangerM(p, d, buildSec);
	if (foe <= 0.f)
		return 1.f;
	const float own = Catalog::gCostM[d] + CoverAt(p);
	return own / (own + foe);
}

// Here or a step back toward the base while the gun still reaches the post: the site worth
// most once the live danger is priced in.
AIFloat3 GraveBestSite(Want@ w, CCircuitUnit@ unit, const AIFloat3& in at, const AIFloat3& in ask, float bs)
{
	const int d = int(w.def.id);
	AIFloat3 best = at;
	float bestV = SmValueAt(w, unit, at) * GraveSurv(at, d, bs);
	AIFloat3 dir = (gPfRimOk ? gPfMid : Builder::gHomePos) - at;
	if (dir.SqLength2D() < 1.f)
		return best;
	dir.SafeNormalize2D();
	const float step = 0.5f * BLOCK_NEAR;
	for (int k = 1; float(k) * step <= Catalog::gMaxRange[d]; ++k) {
		const AIFloat3 p = at + dir * (step * float(k));
		if (InteriorGunSite(d, p))
			break;
		if (!DefSiteOk(d, p, ask))
			continue;
		const float s = GraveSurv(p, d, bs);
		const float v = SmValueAt(w, unit, p) * s;
		if (v > bestV) {
			bestV = v;
			best = p;
		}
		if (s >= 1.f)
			break;
	}
	return best;
}

// The priced site against what the want had to beat (SiteMoveKeeps' bar).
bool GraveKeeps(Want@ w, CCircuitUnit@ unit, const AIFloat3& in at, float bs)
{
	const float v0 = SmValueAt(w, unit, w.pos);
	const float v1 = SmValueAt(w, unit, at) * GraveSurv(at, int(w.def.id), bs);
	const float v = (v0 > 0.f) ? (w.value * v1 / v0) : v1;
	float bar = w.value;
	if ((gExecRunnerV >= 0.f) && (gExecRunnerV < bar))
		bar = gExecRunnerV;
	return v >= bar;
}

int gLnbLogAt = 1800;
void LiveBanStat()
{
	if (ai.frame < gLnbLogAt)
		return;
	gLnbLogAt = ai.frame + 60 * SECOND;
	dictionary byDef;
	array<string> keys;
	int path = 0;
	for (uint i = 0; i < gBlockPos.length(); ++i) {
		if (ai.frame - gBlockAt[i] > BLOCK_TTL)
			continue;
		if (gBlockDef[i] < 0) {
			++path;
			continue;
		}
		const string nm = Catalog::ValidId(gBlockDef[i]) ? Catalog::Def(gBlockDef[i]).GetName() : "?";
		int64 c = 0;
		if (!byDef.get(nm, c))
			keys.insertLast(nm);
		byDef.set(nm, c + 1);
	}
	string marks = "";
	for (uint k = 0; k < keys.length(); ++k) {
		int64 c = 0;
		byDef.get(keys[k], c);
		marks += ((k > 0) ? "," : "") + keys[k] + "=" + c;
	}
	int graveLive = 0;
	GraveFoesFill();
	for (uint i = 0; i < gGravePos.length(); ++i) {
		for (uint k = 0; k < gGfDef.length(); ++k) {
			if ((gGfDef[k] == gGraveBy[i]) && Catalog::ValidId(gGfDef[k])
				&& (gGfPos[k].distance2D(gGravePos[i]) <= Catalog::gLandRange[gGfDef[k]] + BLOCK_NEAR)) {
				++graveLive;
				break;
			}
		}
	}
	AiLog(Factory::T() + "apex: liveban-stat t=" + ai.teamId + " on=" + (LiveNotBan() ? 1 : 0)
		+ " marks(path=" + path + (marks == "" ? "" : ("," + marks)) + ")"
		+ " refused(def=" + gLnbRefDef + " path=" + gLnbRefPath + " spared=" + gLnbSpared + ")"
		+ " graves=" + gGravePos.length() + "/live" + graveLive
		+ " graveExec(live=" + gLnbGraveLive + " dead=" + gLnbGraveDead + " moved=" + gLnbGraveMoved
		+ " dropped=" + gLnbGraveDropped + ")"
		+ " stuck(marked=" + gLnbStuckMarked + " spared=" + gLnbStuckSpared + ")"
		+ " abort(threat=" + gLnbAbortThreat + " frame=" + gLnbAbortFrame + " counted=" + gLnbAbortCounted
		+ " priced=" + gLnbAbortPriced + " kept=" + gLnbAbortKept + " sites=" + Builder::AbortSiteSay() + ")"
		+ " up(drops=" + gUpDropPos.length() + " hot=" + gLnbUpHot + " cleared=" + gLnbUpCleared
		+ " refused=" + gLnbUpRefused + ")"
		+ " backoff=" + Requests::gGateRef[Requests::G_BACKOFF]);
}

}  // namespace Market
