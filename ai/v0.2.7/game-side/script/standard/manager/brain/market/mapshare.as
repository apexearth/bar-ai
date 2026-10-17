namespace Market {

// MAP SHARE (apex_map_share, his 2026-10-15: keep aggression high early to capture
// territory; hold at least our share of the map before leaning on economy).
//   share = extractor spots our team holds (ours and every ally's) / the map's spots
//   fair  = our seats / all seats            gap = max(0, fair - share)
// While gap > 0: army target x (1 + gap), the group's leave bar / (1 + gap), the stance
// hold needs them stronger by (1 + gap), a free spot's mex gain and their extractors'
// raid prize x (1 + gap), and the team operation may contest their extractors on the
// ground between. The horizon and every other economic price stay as they are.
// Their extractors are seen or remembered ones only. Census on the 2 s clock, a fifth
// of the enemy registry and of the allied statics per tick; elections read the cache.

bool gMsOn = false;
bool gMsOnRead = false;
array<int> gMsMark;          // per spot, this sweep: 1 ours or an ally's, 2 a known enemy extractor
array<int> gMsHeld;          // the last finished sweep's marks
array<int> gMsFoeDef;
array<AIFloat3> gMsFoePos;
int gMsIdx = 0, gMsTotal = 0, gMsChunk = 1;
int gMsAIdx = 0, gMsAChunk = 1;
bool gMsSweeping = false;
int gMsOurs = 0, gMsFoe = 0, gMsSpots = 0, gMsSweeps = 0;
float gMsShare = 0.f, gMsFair = 0.f, gMsGap = 0.f;
bool gMsHasTgt = false;
AIFloat3 gMsTgt;
float gMsTgtNet = 0.f;
int gMsCand = 0;
int gMsPickAt = -1;
int gMsLeanN = 0, gMsTaOps = 0, gMsRaidFoe = 0, gMsRaidOpen = 0;
int gMsLogAt = 1800;

bool MapShareOn()
{
	if (!gMsOnRead) {
		gMsOnRead = true;
		gMsOn = ai.GetTunable("apex_map_share", TUNE_MAP_SHARE) > 0.f;
	}
	return gMsOn;
}

float MapShareGap() { return gMsGap; }
float MapShareMul() { return 1.f + gMsGap; }

// A position's spot, nearest within 64 elmo (the cache want_tech's ally upgrade walk keeps).
int MsSpotOf(const AIFloat3& in p)
{
	const string key = formatInt(int(p.x) * 65536 + int(p.z));
	int64 got;
	if (gAuSpotOf.get(key, got))
		return int(got);
	int best = -1;
	float bestD = 64.f;
	for (uint s = 0; s < gAllSpots.length(); ++s) {
		const float dd = gAllSpots[s].distance2D(p);
		if (dd < bestD) {
			bestD = dd;
			best = int(s);
		}
	}
	gAuSpotOf.set(key, int64(best));
	return best;
}

void MsBegin()
{
	const uint n = gAllSpots.length();
	gMsMark.resize(n);
	gMsFoeDef.resize(n);
	gMsFoePos.resize(n);
	for (uint s = 0; s < n; ++s)
		gMsMark[s] = 0;
	gMsTotal = aiEnemyMgr.GetEnemyUnitTotal();
	gMsChunk = gMsTotal / 5 + 1;
	gMsIdx = 0;
	AllyStaticsSync();
	gMsAChunk = int(gAllyStPos.length()) / 5 + 1;
	gMsAIdx = 0;
	gMsSweeping = true;
	SprFoeBegin();
}

void MsStep()
{
	const int end = (gMsIdx + gMsChunk < gMsTotal) ? gMsIdx + gMsChunk : gMsTotal;
	for (int i = gMsIdx; i < end; ++i) {
		const int d = aiEnemyMgr.GetEnemyUnitDefAt(i);
		if ((d <= 0) || (d > Catalog::gDefCount))
			continue;
		if (Catalog::gMobile[d]) {
			if (gOrcOn && Catalog::gBuilder[d])
				SprFoeNote(i, d);
			continue;
		}
		if (Catalog::gExtractsM[d] <= 0.f)
			continue;
		const int los = aiEnemyMgr.GetEnemyUnitLosAt(i);
		if ((los < 0) || ((los & (4 | 8 | 32 | 64)) != 0))
			continue;
		const AIFloat3 p = aiEnemyMgr.GetEnemyUnitPosAt(i);
		if (!OnMap(p))
			continue;
		const int s = MsSpotOf(p);
		if ((s < 0) || (uint(s) >= gMsMark.length()) || (gMsMark[s] == 1))
			continue;
		gMsMark[s] = 2;
		gMsFoeDef[s] = d;
		gMsFoePos[s] = p;
	}
	gMsIdx = end;
	// allied statics are rebuilt every 5 s; a sweep that straddles one reads the new list on
	const int na = int(gAllyStPos.length());
	const int aEnd = (gMsAIdx + gMsAChunk < na) ? gMsAIdx + gMsAChunk : na;
	for (int i = gMsAIdx; i < aEnd; ++i) {
		if (Catalog::gExtractsM[gAllyStDef[i]] <= 0.f)
			continue;
		const int s = MsSpotOf(gAllyStPos[i]);
		if ((s >= 0) && (uint(s) < gMsMark.length()))
			gMsMark[s] = 1;
	}
	gMsAIdx = (aEnd > gMsAIdx) ? aEnd : gMsAIdx;
}

// Their extractor on the ground between (nearer our lane than their base, outside it)
// whose income denied over the payback horizon, plus the structures there, best beats
// the Lanchester loss of the team's army taking it.
void MsPickTarget()
{
	gMsHasTgt = false;
	gMsTgtNet = 0.f;
	gMsCand = 0;
	if ((gMsGap <= 0.f) || (gMsFoe == 0))
		return;
	AIFloat3 from = Military::gLaneAt;
	if (!OnMap(from)) {
		if (!Builder::gHomeSet)
			return;
		from = Builder::gHomePos;
	}
	const AIFloat3 box = aiSetupMgr.GetEnemyBoxCentre();
	const bool boxOn = OnMap(box);
	PrTuneFill();
	const float H = gPrPaybackH;
	const float teamM = Military::TeamArmyCost();
	float F = teamM * 0.017f;   // Grunt-class power per metal, as massing.as
	const float gath = TaSum(BOARD_GATHER);
	const float atk = TaSum(BOARD_TA_ATK);
	F = (gath > F) ? gath : F;
	F = (atk > F) ? atk : F;
	for (uint s = 0; s < gMsMark.length(); ++s) {
		if (gMsMark[s] != 2)
			continue;
		const AIFloat3 p = gMsFoePos[s];
		if (boxOn && ((p.distance2D(box) < Builder::BASE_DANGER_DIST) || (p.distance2D(from) > p.distance2D(box))))
			continue;
		++gMsCand;
		const float prize = aiEnemyMgr.GetEnemyStructCostAt(p, Military::HUNT_R)
				+ gAllSpotInc[s] * Catalog::gExtractsM[gMsFoeDef[s]] * H;
		const float E = aiMilitaryMgr.GetEnemyInflNear(p, Military::HUNT_R + PUSH_STAND);
		const float lossF = Military::NrLossFrac(E, F);
		const float net = prize * (1.f - lossF) - lossF * teamM;
		if ((net > 0.f) && (!gMsHasTgt || (net > gMsTgtNet))) {
			gMsTgtNet = net;
			gMsTgt = p;
			gMsHasTgt = true;
		}
	}
}

void MsFinish()
{
	gMsSweeping = false;
	++gMsSweeps;
	const uint n = gMsMark.length();
	for (uint li = 0; li < gLSpot.length(); ++li) {
		const int s = gLSpot[li];
		if ((gLExtract[li] > 0.f) && (s >= 0) && (uint(s) < n))
			gMsMark[s] = 1;
	}
	int ours = 0, foe = 0;
	for (uint s = 0; s < n; ++s) {
		if (gMsMark[s] == 1)
			++ours;
		else if (gMsMark[s] == 2)
			++foe;
	}
	gMsHeld = gMsMark;
	SprFoeFinish();
	gMsOurs = ours;
	gMsFoe = foe;
	gMsSpots = int(n);
	gMsShare = (n > 0) ? float(ours) / float(n) : 0.f;
	array<Id>@ mates = ai.GetTeamIds();
	const int seats = ((mates is null) || (mates.length() < 1)) ? 1 : int(mates.length());
	int foes = int(ai.GetEnemyTeamSize());
	if (foes < 1)
		foes = seats;
	gMsFair = float(seats) / float(seats + foes);
	gMsGap = (gMsOn && (gMsFair > gMsShare)) ? (gMsFair - gMsShare) : 0.f;   // the sweep also runs for small_hard
	MsPickTarget();
}

// The team operation's expansion target while we hold less than our share.
bool MapShareExpansion(AIFloat3 &out at, float &out r)
{
	if (!gMsHasTgt || (gMsGap <= 0.f))
		return false;
	at = gMsTgt;
	r = Military::HUNT_R;
	gMsPickAt = ai.frame;
	return true;
}

// The team operation runs under the NORMAL plan while a contest target stands, and an
// expansion operation already under way is let finish.
bool MapSharePush()
{
	if (!gMsOn)
		return false;
	return (gMsHasTgt && (gMsGap > 0.f)) || (TeamOpOn() && (int(ai.GetTeamBoard(BOARD_TA_KIND, 0.f)) == 5));
}

void MapShareNoteOp(int kind)
{
	if ((kind == 5) && (gMsPickAt == ai.frame))
		++gMsTaOps;
}

void MapShareNoteRaid(const AIFloat3& in at)
{
	if (!gMsOn || (gMsGap <= 0.f))
		return;
	const int s = MsSpotOf(at);
	if ((s < 0) || (uint(s) >= gMsHeld.length()))
		return;
	if (gMsHeld[s] == 2)
		++gMsRaidFoe;
	else if (gMsHeld[s] == 0)
		++gMsRaidOpen;
}

void MapShareUpdate()
{
	if (!MapShareOn() && !SmallHardOn())
		return;
	CacheSpots();
	if (gAllSpots.length() == 0)
		return;
	if (!gMsSweeping)
		MsBegin();
	MsStep();
	if ((gMsIdx >= gMsTotal) && (gMsAIdx >= int(gAllyStPos.length())))
		MsFinish();
	if (gMsGap > 0.f) {
		const float sr = Military::StanceRatio();
		if ((sr > 1.f) && (sr <= MapShareMul()))
			++gMsLeanN;
	}
	if (!gMsOn || (ai.frame < gMsLogAt))
		return;
	gMsLogAt = ai.frame + 60 * SECOND;
	const float before = ArmyTargetBase() * gPressHoldMul;
	AiLog(Factory::T() + "apex: mapshare-stat t=" + ai.teamId
		+ " ours=" + gMsOurs + " foe=" + gMsFoe + " spots=" + gMsSpots
		+ " share=" + formatFloat(gMsShare, "", 0, 2)
		+ " fair=" + formatFloat(gMsFair, "", 0, 2)
		+ " gap=" + formatFloat(gMsGap, "", 0, 2)
		+ " armyTgt=" + formatFloat(before, "", 0, 0) + "->" + formatFloat(ArmyTargetFull(), "", 0, 0)
		+ " stanceBar=" + formatFloat(MapShareMul(), "", 0, 2)
		+ " leanTicks=" + gMsLeanN
		+ " massBarMul=" + formatFloat(1.f / MapShareMul(), "", 0, 2)
		+ " cand=" + gMsCand + " tgt=" + (gMsHasTgt ? (formatInt(int(gMsTgt.x)) + "," + formatInt(int(gMsTgt.z))) : "-")
		+ " net=" + formatFloat(gMsTgtNet, "", 0, 0)
		+ " teamOps=" + gMsTaOps + " raidFoe=" + gMsRaidFoe + " raidOpen=" + gMsRaidOpen
		+ " sweeps=" + gMsSweeps);
}

}  // namespace Market
