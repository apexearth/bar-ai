namespace Market {

//------------------------------------------------------------------------------
// THE CHOKE: the line stands across the narrowest passage between us and them.
//
// apexearth 2026-09-02, watching the 4v4 on Aethermoor Creek: "Ideally we hold
// a frontline at a narrower part of the map - the map you ran does have a nice
// chokepoint in the middle. holding that line is best."
//
// CircuitAI's terrain analysis (map/GridAnalyzer, BWEM-style) already finds
// the map's choke points -- each with a centre and two ends, i.e. where the
// passage is and how wide it is -- and its own DefenceData sites turrets on
// them. ai.GetChokeCount/Center/End1/End2 expose that (InitScript.cpp).
//
// A build-site probe sweep was tried first and read Aethermoor as uniformly
// open (30-40 buildable samples on every lateral cut): a light tower fits
// almost anywhere, and a full-map lateral count measures the map's width, not
// the passage the enemy must cross.
//
// The pick: among chokes lying between our home and their base (fraction
// 0.12..0.55 of the way along the home->enemy axis, within half the
// separation of it laterally), the one nearest the axis, narrowness breaking
// ties. That is the passage on OUR lane; a narrow gap off to the side is
// somebody else's. In a team game each player's axis runs to the mirror of
// the team's homes, so the picks are the passages of one front.
//------------------------------------------------------------------------------

const float CHOKE_T0 = 0.12f;
const float CHOKE_T1 = 0.55f;

bool     gChokeOk = false;
int      gChokePick = -1;
AIFloat3 gChokeC;          // centre
AIFloat3 gChokeE1;
AIFloat3 gChokeE2;
float    gChokeWidth = 0.f;
float    gChokeT = 0.f;
AIFloat3 gChokeHome;       // the axis it was picked on
AIFloat3 gChokeFoe;
int      gChokeAt = -999999;
bool     gChokeLogged = false;

void ChokeUpdate()
{
	if (!Builder::gHomeSet)
		return;
	if (ai.frame - gChokeAt < 20 * SECOND)
		return;
	gChokeAt = ai.frame;
	AIFloat3 foe;
	if (!FoeRef(foe))
		return;
	// The TEAM's axis when the team hull stands: eight players picking
	// chokes on eight axes stand eight different lines.
	const AIFloat3 home = (gThOk && (gThMates > 0)) ? gThMid : Builder::gHomePos;
	const float sep = home.distance2D(foe);
	if (sep < 1000.f)
		return;
	if (gChokeOk && (gChokeFoe.distance2D(foe) < 0.05f * sep)
		&& (gChokeHome.distance2D(home) < 0.05f * sep))
		return;   // same axis, same answer
	gChokeHome = home;
	gChokeFoe = foe;
	AIFloat3 fd = foe - home;
	fd.SafeNormalize2D();
	const AIFloat3 lat(-fd.z, 0.f, fd.x);
	const int n = ai.GetChokeCount();
	int best = -1;
	float bestScore = 0.f;
	string all = "";
	for (int i = 0; i < n; ++i) {
		const AIFloat3 c = ai.GetChokeCenter(i);
		if (!OnMap(c))
			continue;
		const AIFloat3 e1 = ai.GetChokeEnd1(i);
		const AIFloat3 e2 = ai.GetChokeEnd2(i);
		const float width = e1.distance2D(e2);
		const AIFloat3 rel = c - home;
		const float t = (rel.x * fd.x + rel.z * fd.z) / sep;
		float off = rel.x * lat.x + rel.z * lat.z;
		if (off < 0.f)
			off = -off;
		if (!gChokeLogged)
			all += " #" + i + ":" + int(c.x) + "," + int(c.z)
				+ " w=" + int(width) + " t=" + formatFloat(t, "", 0, 2)
				+ " off=" + int(off);
		if ((t < CHOKE_T0) || (t > CHOKE_T1) || (off > 0.5f * sep))
			continue;
		// A passage one light tower spans end to end is a crack in a
		// cliff, not a front (Aethermoor lists 21 chokes, most 16-113
		// elmos wide); a re-pick once picked a 16-elmo one.
		if (width < Brain::LightTowerRange())
			continue;
		const float score = off + 0.5f * width;
		if ((best < 0) || (score < bestScore)) {
			best = i;
			bestScore = score;
		}
	}
	gChokeOk = (best >= 0);
	gChokePick = best;
	if (gChokeOk) {
		gChokeC = ai.GetChokeCenter(best);
		gChokeE1 = ai.GetChokeEnd1(best);
		gChokeE2 = ai.GetChokeEnd2(best);
		gChokeWidth = gChokeE1.distance2D(gChokeE2);
		const AIFloat3 rel = gChokeC - home;
		gChokeT = (rel.x * fd.x + rel.z * fd.z) / sep;
	}
	if (!gChokeLogged || gChokeOk) {
		gChokeLogged = true;
		AiLog("apex: choke t=" + ai.teamId + " n=" + n + " pick=" + best
			+ (gChokeOk ? (" at=" + int(gChokeC.x) + "," + int(gChokeC.z)
				+ " width=" + int(gChokeWidth)
				+ " frac=" + formatFloat(gChokeT, "", 0, 2)) : " (none on our lane)")
			+ " home=" + int(home.x) + "," + int(home.z)
			+ " foe=" + int(foe.x) + "," + int(foe.z)
			+ ((all.length() > 0) ? (" |" + all) : ""));
	}
}

// The choke itself, held or not: its centre, its cross-section direction
// (end1 -> end2) and its half-width. Where the army goes to take it; the wall
// steps its anchor back from here to the nearest safe ground
// (protect_wall.as), so this is the target, not where the guns stand. False
// while no choke sits on our lane.
bool ChokeTarget(AIFloat3& out at, AIFloat3& out across, float& out halfW)
{
	if (!gChokeOk)
		return false;
	at = gChokeC;
	across = gChokeE2 - gChokeE1;
	if (across.SqLength2D() < 1.f)
		return false;
	across.SafeNormalize2D();
	halfW = gChokeWidth * 0.5f;
	return OnMap(at);
}

bool ChokeOnLane()
{
	AIFloat3 at;
	AIFloat3 across;
	float halfW = 0.f;
	return ChokeTarget(at, across, halfW);
}

}  // namespace Market
