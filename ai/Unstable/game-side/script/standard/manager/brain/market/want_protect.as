namespace Market {
CCircuitUnit@ gReclaimTarget = null;
CCircuitUnit@ gAssistTarget = null;

// Which kind of ground the defence auction keeps choosing. Without this the
// only way to tell a forward post from a tower at a mex is to read positions
// out of the log by hand.
int gDefSiteFront = 0;
int gDefSiteAsset = 0;
int gNextDefSiteLog = 0;
int gNextDefFwdLog = 0;
// EVERY TERM OF THE DEFENCE PRICE, so "why so many turrets" is read rather than
// guessed (apexearth: "what is the connection causing this? We need to not
// guess here").
float gDbgStake = 0.f, gDbgHz = 0.f, gDbgSiege = 0.f, gDbgHazard = 0.f;
float gDbgShort0 = 0.f, gDbgShort1 = 0.f, gDbgThreat = 0.f, gDbgCover0 = 0.f;
float gDbgCover1 = 0.f;
int gNextDefPriceLog = 0;
float gDbgFrontBest = 0.f;
float gDbgAssetBest = 0.f;
int gDbgLineN = 0;
void NoteDefSite(bool isFront)
{
	if (isFront)
		++gDefSiteFront;
	else
		++gDefSiteAsset;
	if (ai.frame < gNextDefSiteLog)
		return;
	gNextDefSiteLog = ai.frame + 60 * SECOND;
	AiLog("apex: defsite front=" + gDefSiteFront + " asset=" + gDefSiteAsset
		+ " lineSpots=" + gDbgLineN
		+ " foeReach=" + formatFloat(Military::FoeReach(), "", 0, 0)
		+ " bestFrontGain=" + formatFloat(gDbgFrontBest, "", 0, 2)
		+ " bestAssetGain=" + formatFloat(gDbgAssetBest, "", 0, 2));
	gDbgFrontBest = 0.f;
	gDbgAssetBest = 0.f;
}

// Standing defense metal near a point -- the crowding divisor that makes
// a 247-LLT carpet impossible (apexearth's screenshot: the whole eco lost
// to in-base turret sprawl).
// Distance to the nearest map wall -- diagnostics only.
float EdgeDist(const AIFloat3& in p)
{
	float d = p.x;
	if (p.z < d) d = p.z;
	if (float(AiTerrainWidth()) - p.x < d) d = float(AiTerrainWidth()) - p.x;
	if (float(AiTerrainHeight()) - p.z < d) d = float(AiTerrainHeight()) - p.z;
	return (d < 0.f) ? 0.f : d;
}

float DefCrowdM(const AIFloat3& in pos, float r)
{
	float m = 0.f;
	for (uint i = 0; i < gProtPos[PROT_DEF].length(); ++i) {
		if (gProtPos[PROT_DEF][i].distance2D(pos) < r)
			m += Catalog::gCostM[gProtDefId[PROT_DEF][i]];
	}
	return m;
}

// Does a STANDING radar already watch this ground? Judged by that radar's own
// range -- asking it about the CANDIDATE's range is why a 60-metal armrad at
// the farm permanently blocked the 3500-range armarad, and why we finished
// every game with exactly one radar (apexearth: "our radar coverage is only
// partial").
bool RadarSees(const AIFloat3& in pos)
{
	for (uint i = 0; i < gProtPos[PROT_RADAR].length(); ++i) {
		const int rd = gProtDefId[PROT_RADAR][i];
		const float rr = Catalog::gRadarR[rd];
		if ((rr > 1.f) && (pos.distance2D(gProtPos[PROT_RADAR][i]) < rr * 0.8f))
			return true;
	}
	return false;
}

// The ground we care about that nothing watches, and how much of it there is.
// Candidates are the front posts and our standing mexes. The NEAREST gap wins,
// not the most forward one: picking the deepest gap produced 38 radar bids and
// zero radars in a 28-minute game, because a builder re-elects during a long
// walk and abandons a frame it has not started. Coverage still spreads -- once
// this gap is watched the nearest remaining one is somewhere else. The unseen
// share is the diminishing return: cover everything and the want prices itself
// out without a count anywhere.
bool RadarGap(const AIFloat3& in from, AIFloat3& out at, float& out unseenFrac)
{
	array<AIFloat3> pts;
	if (ai.GetTunable("apex_front_line", TUNE_FRONT_LINE) > 0.f) {
		array<AIFloat3> line;
		if (Military::FrontBuildSpots(line)) {
			for (uint i = 0; i < line.length(); ++i)
				pts.insertLast(line[i]);
		}
	}
	for (uint li = 0; li < gLPos.length(); ++li) {
		if (gLExtract[li] > 0.f)
			pts.insertLast(gLPos[li]);
	}
	if (pts.length() == 0)
		return false;
	int unseen = 0;
	float bestD = -1.f;
	bool found = false;
	for (uint i = 0; i < pts.length(); ++i) {
		if (!OnMap(pts[i]) || RadarSees(pts[i]))
			continue;
		++unseen;
		const float dd = from.distance2D(pts[i]);
		if (!found || (dd < bestD)) {
			bestD = dd;
			at = pts[i];
			found = true;
		}
	}
	unseenFrac = float(unseen) / float(pts.length());
	return found;
}

// A POST SHIELDS WHAT IS BEHIND IT ONLY IF THE ENEMY CANNOT WALK AROUND IT.
// apexearth: "ShieldedStakeAt is technically correct as long as we've closed
// the loop - created a net with no holes in it. Otherwise it's moreso a
// 'partial' truth."
//
// Closure is the share of approach bearings some standing post actually
// covers. The shielded credit a candidate earns is the closure it would ADD,
// so plugging the last hole is worth the whole base behind it and a redundant
// post beside an existing one is worth nothing. That is what makes defence
// saturate: without it every candidate site claimed the entire base, measured
// at stake 13,606 against an economy of 8,751, and the price never fell however
// many turrets stood.
//
// A bearing that runs off the map counts as closed -- the edge is the wall.
const int CLOSE_RAYS = 16;
float LineClosure(const AIFloat3& in extraAt, float extraReach)
{
	AIFloat3 c;
	float extent = 0.f;
	if (!BaseCentroid(c, extent))
		return 0.f;
	const float ring = extent + Military::FoeReach();
	if (ring <= 1.f)
		return 0.f;
	int closed = 0;
	for (int b = 0; b < CLOSE_RAYS; ++b) {
		const float ang = 6.2831853f * float(b) / float(CLOSE_RAYS);
		const AIFloat3 p = c + AIFloat3(cos(ang), 0.f, sin(ang)) * ring;
		if (!OnMap(p)) {
			++closed;
			continue;
		}
		bool ok = (extraReach > 0.f) && (extraAt.distance2D(p) <= extraReach);
		for (uint i = 0; !ok && (i < gProtPos[PROT_DEF].length()); ++i) {
			const int d = gProtDefId[PROT_DEF][i];
			if (gProtPos[PROT_DEF][i].distance2D(p) <= Catalog::gMaxRange[d])
				ok = true;
		}
		if (ok)
			++closed;
	}
	return float(closed) / float(CLOSE_RAYS);
}

bool ProtCovered(int cls, const AIFloat3& in pos, float r)
{
	for (uint i = 0; i < gProtPos[cls].length(); ++i) {
		if (pos.distance2D(gProtPos[cls][i]) < r)
			return true;
	}
	return false;
}

// Insurance pricing: protection is worth a fraction of the assets it
// covers, per second of exposure. ONE modeled rate for eyes and turrets,
// one for the nuke risk (value-paradigm: a single named quantity each).
// Timing EMERGES: at 5k assets an anti-nuke prices at ~0.4 and loses; at
// 100k it prices at ~8 and wins.
const int HALF_GROUND = 0;
const int HALF_SENSE = 1;
const int HALF_AIRDEF = 2;

int HalfOfClass(int cls)
{
	if ((cls == PROT_RADAR) || (cls == PROT_JAM) || (cls == PROT_TARGFAC))
		return HALF_SENSE;
	if (cls == PROT_AA)
		return HALF_AIRDEF;
	return HALF_GROUND;
}

// Mobile AA standing over the base answers the same bombers a tower does, so it
// counts against the same cover target -- but ONLY while it is here. Beyond
// apex_intercept_r (the radius that already defines "raiding us" for the
// interceptors) it has left with the army, and the towers its credit displaced
// would have been what stayed. Cached per frame: this walks the team's units.
int gAAMobAt = -1;
float gAAMobM = 0.f;
float MobileAACoverM()
{
	if (gAAMobAt == ai.frame)
		return gAAMobM;
	gAAMobAt = ai.frame;
	gAAMobM = 0.f;
	if (!Builder::gHomeSet)
		return 0.f;
	const float r = ai.GetTunable("apex_intercept_r", TUNE_INTERCEPT_R);
	for (uint d = 1; d < gOwnCount.length(); ++d) {
		if ((gOwnCount[d] <= 0) || !Catalog::gMobile[int(d)])
			continue;
		CCircuitDef@ cd = ai.GetCircuitDef(Id(d));
		if ((cd is null) || !cd.IsRoleAny(Unit::Role::AA.mask))
			continue;
		array<CCircuitUnit@>@ have = ai.GetOwnUnitsOfDef(cd, Builder::gHomePos, r);
		gAAMobM += float(have.length()) * Catalog::gCostM[int(d)];
	}
	return gAAMobM;
}

// Three questions, three tickets: shooting the ground, seeing, and shooting
// the sky. `half` picks which set of protection classes this call bids for;
// everything else about the auction is shared. See CAT_SENSE / CAT_AIRDEF.
Want@ ProposeProtectHalf(CCircuitUnit@ unit, int half)
{
	Want w;
	if (gAssetsM < 1.f)
		return w;
	// DEFENCE MUST NOT WAIT ON A NANO. This used to require gFarmSet, which
	// only flips when the first nano TURRET finishes -- measured at frame
	// 5718, so no LLT, AA, radar or shield could even be proposed for the
	// first 3.2 minutes, which is exactly when raiders take undefended mexes
	// and solars (apexearth, watched: "we made several solars/mexes which we
	// did not protect with a sentry turret... our llt defense early game is
	// not strong enough"). The farm is only ever a DEFAULT POSITION; the
	// anchor serves before it exists, and PROT_DEF/PROT_RADAR pick their own
	// sites anyway.
	const int uid = int(unit.circuitDef.id);
	const array<int>@ builds = Catalog::BuildsOf(uid);
	const float rate = ai.GetTunable("apex_insure_rate", TUNE_INSURE_RATE);
	const float nukeRate = ai.GetTunable("apex_nuke_risk", TUNE_NUKE_RISK);
	AIFloat3 core = gFarmPos;
	if (!gFarmSet) {
		core = Base::gAnchorSet ? Base::gAnchor : Builder::gHomePos;
		if (!OnMap(core))
			return w;
	}
	for (uint i = 0; i < builds.length(); ++i) {
		const int d = builds[i];
		if (!Catalog::gAvailable[d] || Catalog::gMobile[d]
			|| Catalog::gFloater[d] || Catalog::gSub[d])
			continue;
		const int cls = ProtClassOf(d);
		if (cls < 0)
			continue;
		if (HalfOfClass(cls) != half)
			continue;
		float gain = 0.f;
		AIFloat3 at = core;
		if (cls == PROT_RADAR) {
			AIFloat3 gapAt;
			float unseenFrac = 0.f;
			if (!RadarGap(unit.GetPos(ai.frame), gapAt, unseenFrac))
				continue;
			at = gapAt;
			// Eyes for the army too: blind units chase shadows (apexearth:
			// "build radars so our units have intelligence"). Worth what is
			// still unwatched, so coverage follows the front instead of one
			// tower sitting at home for the whole game.
			gain = (gAssetsM + ArmyValue()) * rate * unseenFrac;
		} else if (cls == PROT_JAM) {
			// Tower concentrations want jamming first (apexearth): find a
			// cluster of >=3 defenses with no jammer in reach.
			AIFloat3 jat = core;
			bool found = false;
			for (uint jd = 0; jd < gProtPos[PROT_DEF].length() && !found; ++jd) {
				int nearDef = 0;
				for (uint jk = 0; jk < gProtPos[PROT_DEF].length(); ++jk) {
					if (gProtPos[PROT_DEF][jd].distance2D(gProtPos[PROT_DEF][jk]) < 300.f)
						++nearDef;
				}
				if ((nearDef >= 3)
					&& !ProtCovered(PROT_JAM, gProtPos[PROT_DEF][jd],
							Catalog::gJamR[d] * 0.8f))
				{
					jat = gProtPos[PROT_DEF][jd];
					found = true;
				}
			}
			if (!found && ProtCovered(PROT_JAM, core, Catalog::gJamR[d] * 0.8f))
				continue;
			// A JAMMER DENIES RADAR, so it is worth nothing until something is
			// USING radar against us -- indirect fire that shoots what it cannot
			// see. Priced on assets alone it won an early sense ticket over the
			// sentries and mexes we actually needed (apexearth, watched: "we're
			// making a jammer long before it would ever provide value"). Same
			// shape as the shield gate below, and for the same reason.
			const float indirect = Military::EnemyCostOf(Unit::Role::ARTY.type)
					+ Military::EnemyCostOf(Unit::Role::SKIRM.type) * 0.5f;
			if (indirect < 200.f)
				continue;
			at = found ? jat : core;
			gain = ((indirect < gAssetsM) ? indirect : gAssetsM)
					* rate * (found ? 0.8f : 0.5f);
		} else if (cls == PROT_ANTINUKE) {
			if (ProtCovered(PROT_ANTINUKE, core, 2000.f))
				continue;
			gain = gAssetsM * nukeRate;
		} else if (cls == PROT_SHIELD) {
			// Shields answer bombardment: worth the arty mass they blank,
			// covering the interior (the stock feature our gap survey ranked
			// first; their arty ground our statics 38k:7k).
			const float artyS = Military::EnemyCostOf(Unit::Role::ARTY.type)
					+ Military::EnemyCostOf(Unit::Role::SKIRM.type) * 0.5f;
			if (artyS < 200.f)
				continue;
			// ...and only when a threat is actually NEAR: a global arty
			// census bought shield stacks in a base nothing could reach
			// (apexearth: "too many shields while theres still no threat
			// very close"). The bombardier must be within twice its reach
			// of what the shield would cover.
			if (ai.GetEnemyCostAt(core, 1800.f) < 200.f)
				continue;
			if (ProtCovered(PROT_SHIELD, core, 400.f))
				continue;
			gain = ((artyS < gAssetsM) ? artyS : gAssetsM) * rate * 4.f;
		} else if (cls == PROT_AA) {
			// AS SOON AS WE HAVE SEEN ANY (apexearth: "just make the AA if
			// we've seen enemy air... it doesn't have to be a ton"). Sized off
			// AirSeenEver, which has no AA_IGNORE floor and no freshness
			// window: a bomber that has flown home is still a bomber, and
			// AirThreatNow read zero for exactly the moments between raids.
			// OUR SHARE OF A SIDE-WIDE READING: the enemy census sums what the
			// whole team can see, and each of us covers our own base, so charging
			// one player the team's answer builds it once per ally. RoleTarget
			// already divides the same census on the mobile side.
			const float allies = Military::AllyCount();
			float air = Military::AirSeenEver()
					/ ((allies > 1.f) ? allies : 1.f);
			// The rear specialist is a FATTER TARGET than its share suggests:
			// it holds the team's economy, builds no ground defence, and keeps
			// no army over its base, so bombers that get past the front go
			// there. It carries a larger share of the same census, which the
			// saturation point below then turns into proportionally more AA.
			if (EcoRoleActive())
				air *= ai.GetTunable("apex_eco_aa_mult", TUNE_ECO_AA_MULT);
			if (air <= 0.f)
				continue;
			// WHAT THE BOMBS ARE ACTUALLY COSTING US, priced like a turret:
			// the metal/s we are measurably losing to aircraft, times the
			// share of their air this tower newly stops. The old form was an
			// insurance rate on the base with a x4 urgency fudge bolted on,
			// which read ~1 metal/s while bombers ate the economy -- and it
			// lost every auction (apexearth, watched: "T1 anti air is very
			// cheap yet we still have not made it... I estimate a team cost
			// of around 250-300 would have saved us more than that").
			// AA metal counted against air metal at the cover ratio, so cover
			// reaches the target -- and the want prices itself out -- at
			// exactly apex_aa_cover_frac of our share of the air we have seen.
			// No count, no cap. Mobile AA over the base counts here too, so the
			// two AA budgets saturate against each other instead of both
			// answering the same bombers.
			float aaFrac = ai.GetTunable("apex_aa_cover_frac", TUNE_AA_COVER_FRAC);
			if (aaFrac < 0.01f)
				aaFrac = 0.01f;
			const float aaTrade = 1.f / aaFrac;
			float aaCover = MobileAACoverM() * aaTrade;
			for (uint ai2 = 0; ai2 < gProtDefId[PROT_AA].length(); ++ai2)
				aaCover += Catalog::gCostM[gProtDefId[PROT_AA][ai2]] * aaTrade;
			const float aaAdds = Catalog::gCostM[d] * aaTrade;
			float aShort0 = (air - aaCover) / air;
			if (aShort0 < 0.f)
				aShort0 = 0.f;
			float aShort1 = (air - (aaCover + aaAdds)) / air;
			if (aShort1 < 0.f)
				aShort1 = 0.f;
			const float stopped = aShort0 - aShort1;
			if (stopped <= 0.f)
				continue;
			// THE SAME THREE TERMS AS A GROUND TURRET: what is at risk, how
			// often it gets hit, and the share this tower newly stops. AA used
			// an insurance rate on min(their air, our base), which capped the
			// value at risk by the SIZE of their air force -- and `stopped`
			// already measures our cover against exactly that force. That is
			// the double count ThreatM records and rejects on the ground side,
			// and it is why AA priced at gain=0.09 against energy's 4.75 and we
			// fielded exactly one Nettle per game however many bombers came.
			//
			// Turrets are excluded from the stake for the same reason
			// SiegeRiskAt excludes them: defence must not be its own reason.
			// Saturation is arithmetic -- every tower raises aaCover, which
			// lowers both the arrival rate and the next tower's share.
			float econA = gAssetsM - gProtM;
			if (econA < 0.f)
				econA = 0.f;
			const float horizA = ai.GetTunable("apex_exposed_loss_s", TUNE_EXPOSED_LOSS_S);
			const float anchorA = 1.f / ((horizA > 1.f) ? horizA : 120.f);
			const float airHz = anchorA * (air / (air + aaCover))
					* ai.GetTunable("apex_aa_urgency", TUNE_AA_URGENCY);
			float gainA = econA * airHz * stopped;
			// Measured losses are a FLOOR, not the whole price: they are what
			// air has already cost us, which arrives after the mex is dead.
			const float measured = Military::AirLossRate() * stopped;
			gain = (measured > gainA) ? measured : gainA;
		} else if (cls == PROT_TARGFAC) {
			// apexearth's spec: three wanted, diminishing.
			const int have = int(gProtPos[PROT_TARGFAC].length());
			const int want3 = int(ai.GetTunable("apex_targfac_want", TUNE_TARGFAC_WANT));
			if (have >= want3)
				continue;
			gain = gAssetsM * rate * float(want3 - have) / float(want3);
		} else if (cls == PROT_DEF) {
			// ONE AUCTION OVER PLACES, not an ordered cascade. Gain is the
			// expected loss this turret would PREVENT: the stake standing in
			// its reach, times how often lethal force arrives there, times
			// the share of the local threat it newly stops.
			//
			// Diminishing returns are arithmetic here rather than a crowding
			// divisor -- once standing cover already exceeds the threat, the
			// next turret prevents nothing and prices itself out. That is
			// also what retired the quiet-rear veto: a rear nothing can
			// reach has no threat, so it buys no towers without being
			// forbidden to.
			const float trade = ai.GetTunable("apex_def_trade", TUNE_DEF_TRADE);
			const float reach = (Catalog::gMaxRange[d] > 1.f)
					? Catalog::gMaxRange[d] : 500.f;
			const float adds = Catalog::gCostM[d] * trade;
			array<AIFloat3> sites;
			for (uint li = 0; li < gLPos.length(); ++li) {
				if (gLExtract[li] > 0.f)
					sites.insertLast(gLPos[li]);
			}
			for (uint bg = 0; bg < gOwnBig.length(); ++bg) {
				if (gOwnBig[bg] !is null)
					sites.insertLast(gOwnBig[bg].GetPos(ai.frame));
			}
			// ...AND THE ENERGY. Only structures over 1200 metal enter gOwnBig,
			// so a solar field -- the thing raiders actually drive into -- was
			// never a candidate SITE at all, however much StakeAt valued it
			// (apexearth: "the enemy just drives right up and kills all our
			// energy easily, nothings really protecting it").
			for (uint gn = 0; gn < gOwnGen.length(); ++gn) {
				if (gOwnGen[gn] !is null)
					sites.insertLast(gOwnGen[gn].GetPos(ai.frame));
			}
			// The choke and the base front are places too: their stake is
			// whatever stands behind them, read by the same StakeAt.
			if (Base::gAnchorSet) {
				AIFloat3 cp;
				if (Front::FrontChoke(Base::gAnchor, cp)) {
					AIFloat3 site;
					if (!Front::BehindChoke(cp, 180.f, site))
						site = cp;
					sites.insertLast(site);
				}
				if (Base::gAxisSet)
					sites.insertLast(Base::gAnchor + Base::gFwd * 150.f);
			}
			// THE LINE ITSELF. FrontBuildSpots is the spaced ring of workable
			// posts along our own front -- already set back so the builder is
			// not parked in the fight, already dropped on bearings with no
			// reachable ground. It was orphaned when statics.as died; nothing
			// has offered a forward post since (apexearth: "front line style
			// defenses, placed up ahead, so a T2 lab can be safely placed
			// behind"). They compete on the same price as every other site.
			// THE SHIELD ARC, from the base's own mass centre toward the
			// enemy and wrapping past both flanks. Every asset site above sits
			// ON something we own, so a tower there meets the raider only after
			// it has arrived; these sit one denied radius OUTSIDE the base edge
			// and meet it first (apexearth: "place our defenses towards the
			// enemy base/start box. ensure our sides are also covered").
			const uint nAsset = sites.length();
			{
				array<AIFloat3> arc;
				// Sized by the turret's OWN reach, not by reach minus their
				// reach: the latter went to zero the moment they fielded
				// anything out-ranging our towers and the arc then vanished
				// for the rest of the game (measured: lineSpots 22 -> 0,
				// permanently). Whether a post still helps against a standoff
				// attacker is CoverAt's question, and it already asks it.
				if (ShieldArcSpots(arc, reach)) {
					for (uint ai3 = 0; ai3 < arc.length(); ++ai3)
						sites.insertLast(arc[ai3]);
				}
			}
			if (ai.GetTunable("apex_front_line", TUNE_FRONT_LINE) > 0.f) {
				array<AIFloat3> line;
				// A NET AROUND THE BASE, layered inward, spaced by the turret's
				// OWN reach -- the same radius ShieldArcSpots uses. Spacing it
				// by reach-minus-standoff made denyR negative whenever the
				// enemy out-ranged the turret (measured: FoeReach 616-943
				// against a 450-700 turret), so NetSpots bailed and lineSpots
				// collapsed to 0-5 with bestFrontGain 0.00. That is the same
				// double-count FrontedStakeAt already records as having dropped
				// defence to 1.9%: standoff is CoverAt's question, not the
				// spacing's.
				const float denyR = reach;
				if ((ai.GetTunable("apex_def_net", TUNE_DEF_NET) > 0.f)
					&& Military::NetSpots(line, denyR))
				{
					for (uint fi = 0; fi < line.length(); ++fi)
						sites.insertLast(line[fi]);
				} else if (Military::FrontBuildSpots(line)) {
					for (uint fi = 0; fi < line.length(); ++fi)
						sites.insertLast(line[fi]);
				}
			}
			AIFloat3 bestAt = at;
			float bestGain = 0.f;
			bool bestIsFront = false;
			// Closure as it stands, computed once: it does not depend on which
			// candidate site we are pricing.
			const float gClose0 = LineClosure(at, 0.f);
			for (uint si = 0; si < sites.length(); ++si) {
				const AIFloat3 s = sites[si];
				if (!OnMap(s))
					continue;
				const float threat = ThreatM(s);
				if (threat <= 1.f)
					continue;
				// What it can shoot over, plus what it stands between the
				// enemy and. The second term is why a post on empty forward
				// ground is worth anything at all.
				// What this post directly covers, plus what it shields --
				// the latter only to the extent this post CLOSES the net.
				float dClose = LineClosure(s, reach) - gClose0;
				if (dClose < 0.f)
					dClose = 0.f;
				const float stake = FrontedStakeAt(s, reach)
						+ ShieldedStakeAt(s, reach) * dClose;
				if (stake <= 1.f)
					continue;
				// BOTH READINGS THROUGH ONE FUNCTION. short1 asks CoverWith
				// what the field would measure with this turret standing at s,
				// so a post that cannot raise the weakest bearing prevents
				// nothing -- which is what makes an in-base carpet price itself
				// out while a forward post or an out-ranging turret does not.
				const float cover0 = CoverAt(s);
				const float cover1 = CoverWith(s, s, reach, adds);
				float short0 = (threat - cover0) / threat;
				if (short0 < 0.f)
					short0 = 0.f;
				float short1 = (threat - cover1) / threat;
				if (short1 < 0.f)
					short1 = 0.f;
				// A post against the map edge faces FEWER approaches, so the
				// wave it must beat is smaller in proportion. This used to
				// multiply by EdgeExposure, which is the same geometry with the
				// opposite sign and paid DOUBLE at the wall.
				// The siege prior BUYS THE ANSWER, it does not only forbid the
				// bet. Discounting tech and energy for a threat we cannot see
				// while defence still priced off HazardAt's floor left the
				// worst of both: no T2 and no turrets either (measured, 12
				// games -- first T2 13.3 -> 14.6 min while defence at minute
				// 25 fell 3240 -> 1698). The same expectation that says a big
				// economy with no army is a target has to raise what answers
				// it. Self-limiting: SiegeRisk falls as CoverAt rises, so each
				// turret lowers the price of the next.
				float hz = HazardAt(s);
				const float sg = SiegeExpect(s);
				if (sg > hz)
					hz = sg;
				float prevented = stake * hz * (short0 - short1);
				prevented *= Military::OpenFraction(s, reach);
				if (si >= nAsset) {
					if (prevented > gDbgFrontBest) gDbgFrontBest = prevented;
				} else if (prevented > gDbgAssetBest) {
					gDbgAssetBest = prevented;
				}
				if (prevented > bestGain) {
					bestGain = prevented;
					bestAt = s;
					bestIsFront = (si >= nAsset);
					gDbgStake = stake;
					gDbgHz = hz;
					gDbgSiege = sg;
					gDbgHazard = HazardAt(s);
					gDbgShort0 = short0;
					gDbgShort1 = short1;
					gDbgThreat = threat;
					gDbgCover0 = cover0;
					gDbgCover1 = cover1;
				}
			}
			gDbgLineN = int(sites.length() - nAsset);
			if (bestGain <= 0.f)
				continue;
			gain = bestGain;
			at = bestAt;
			if (ai.frame >= gNextDefPriceLog) {
				gNextDefPriceLog = ai.frame + 30 * SECOND;
				AiLog("apex: defprice t=" + ai.teamId
					+ " gain=" + formatFloat(gain, "", 0, 2)
					+ " stake=" + formatFloat(gDbgStake, "", 0, 0)
					+ " threat=" + formatFloat(gDbgThreat, "", 0, 0)
					+ " cover=" + formatFloat(gDbgCover0, "", 0, 0)
					+ "->" + formatFloat(gDbgCover1, "", 0, 0)
					+ " short=" + formatFloat(gDbgShort0, "", 0, 2)
					+ "->" + formatFloat(gDbgShort1, "", 0, 2)
					+ " hz=" + formatFloat(gDbgHz, "", 0, 5)
					+ " (hazard=" + formatFloat(gDbgHazard, "", 0, 5)
					+ " siege=" + formatFloat(gDbgSiege, "", 0, 5) + ")"
					+ " | econM=" + formatFloat(gAssetsM - gProtM, "", 0, 0)
					+ " protM=" + formatFloat(gProtM, "", 0, 0)
					+ " army=" + formatFloat(ArmyValue(), "", 0, 0)
					+ " foeSeen=" + formatFloat(Military::EnemyArmyCost(), "", 0, 0));
			}
			NoteDefSite(bestIsFront);
			// Is the chosen post in FRONT of the base or behind it? He reports
			// towers landing behind, which the site list alone cannot show.
			if (ai.frame >= gNextDefFwdLog) {
				gNextDefFwdLog = ai.frame + 30 * SECOND;
				AiLog("apex: defplace " + Catalog::Def(d).GetName()
					+ " fwd=" + formatFloat(Military::ForwardFraction(bestAt), "", 0, 2)
					+ " anchorFwd=" + formatFloat(Base::gAnchorSet
						? Military::ForwardFraction(Base::gAnchor) : -9.f, "", 0, 2)
					+ " front=" + (bestIsFront ? 1 : 0)
					// Distance to the nearest map wall, and the share of the
					// approach that is real map there. The wall used to PAY.
					+ " edgeD=" + int(EdgeDist(bestAt))
					+ " open=" + formatFloat(Military::OpenFraction(bestAt, 500.f), "", 0, 2)
					+ " gain=" + formatFloat(bestGain, "", 0, 2));
			}
		}
		if (gain <= 0.f)
			continue;
		Want c;
		const float speed = Catalog::gSpeed[uid];
		const float walkSec = (speed > 1.f)
				? (unit.GetPos(ai.frame).distance2D(at) / speed) : 60.f;
		ValueOf(d, gain, walkSec, Catalog::gBuildPower[uid], c);
		if (c.value > w.value) {
			w = c;
			w.kind = (half == HALF_SENSE) ? WK_SENSE
					: ((half == HALF_AIRDEF) ? WK_AIRDEF : WK_PROTECT);
			@w.def = Catalog::Def(d);
			w.pos = at;
			w.spotId = cls;
		}
	}
	return w;
}

// A WANT NOBODY MAY EXECUTE MUST NOT ENTER THE AUCTION.
//
// Role::DefenceAllowed() is enforced at Requests::Take -- downstream of the
// arbiter -- so for the rear specialist the market kept electing ground
// defence and Take kept handing back null: no task, builder idles, re-elects,
// elects it again. Measured on Supreme Isthmus 8v8: 2,491 of the eco player's
// 2,933 decisions (85%) went to defence/protect and produced NOTHING, one of
// them picking a turret at v=1.65 over the tech want at v=103.60 sitting
// beside it. It finished the game on 1,180 eco against a 21,108 teammate.
//
// The gate stays exactly where the policy says it is; it just has to be
// visible to the thing doing the choosing. Sense and air defence are other
// halves and stay legal -- eyes are not porc, and the rear still answers
// bombers.
Want@ ProposeProtect(CCircuitUnit@ unit)
{
	if (!Role::DefenceAllowed()) {
		Want none;
		return none;
	}
	return ProposeProtectHalf(unit, HALF_GROUND);
}

Want@ ProposeSense(CCircuitUnit@ unit)
{
	return ProposeProtectHalf(unit, HALF_SENSE);
}

Want@ ProposeAirDef(CCircuitUnit@ unit)
{
	return ProposeProtectHalf(unit, HALF_AIRDEF);
}


}  // namespace Market
