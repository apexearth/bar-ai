namespace Market {

// JOIN OR NEW (his 2026-10-07: advanced converters went up one constructor
// each beside each other -- "is somebody doing this nearby me? Or is somebody
// also doing the thing nearby where I'm planning on doing it? ... the sort of
// thing a NN can have a hand at"). Where the rule opens a parallel site of a
// converter or energy building, the live site of the same def with room that
// is the shortest walk from this hand is offered: JOIN it or open a NEW one.
// The rule joins when the walk past the planned spot is shorter than the
// site's remaining build time (Requests::WorthJoining). One row per decision.
const string NNJ_JOIN = "dMe,dSpot,dNew,walkS,leftS,progress,crew,cap,costM,myBP,eSurplus,frames,minute";
const int NJ_JOIN = 0, NJ_NEW = 1;
bool gJoinHeader = false;
int gJoinN = 0, gJoinNewN = 0, gJoinLogAt = 0;

IUnitTask@ JoinOrNew(CCircuitUnit@ unit, CCircuitDef@ def, const AIFloat3& in spot)
{
	if ((unit is null) || (def is null) || (unit.circuitDef is null))
		return null;
	const AIFloat3 me = unit.GetPos(ai.frame);
	const uint cap = Requests::SiteWorkerCap(def);
	IUnitTask@ best = null;
	float bestMe = 1e9f;
	int frames = 0;
	for (uint i = 0; i < Requests::gLive.length(); ++i) {
		IUnitTask@ t = Requests::gLive[i];
		if ((t is null) || t.IsDead() || (t.buildDef !is def))
			continue;
		++frames;
		if (Requests::Workers(t) >= cap)
			continue;
		const AIFloat3 where = t.GetBuildPos();
		if (!OnMap(where) || (Builder::ThreatFor(unit, where) > Builder::CON_THREAT_VETO))
			continue;
		if (!unit.circuitDef.CanBuild(def) && (t.target is null))
			continue;
		const float d = me.distance2D(where);
		if (d < bestMe) {
			bestMe = d;
			@best = t;
		}
	}
	if (best is null)
		return null;
	const AIFloat3 where = best.GetBuildPos();
	const float dSpot = OnMap(spot) ? spot.distance2D(where) : 1e5f;
	const float dNew = OnMap(spot) ? me.distance2D(spot) : 0.f;
	const float speed = Catalog::gSpeed[int(unit.circuitDef.id)];
	const float v = (speed > 1.f) ? speed : Requests::ASSUMED_CON_SPEED;
	const float extra = (bestMe > dNew) ? (bestMe - dNew) : 0.f;
	const float progress = Requests::Progress(best);
	const uint crew = Requests::Workers(best);
	const float leftS = Catalog::gCostM[int(def.id)] * (1.f - progress)
			/ (Requests::DRAIN * float((crew > 0) ? crew : 1));
	const int rule = Requests::WorthJoining(extra, progress, Catalog::gCostM[int(def.id)], crew, speed)
			? NJ_JOIN : NJ_NEW;
	const bool explore = gNnExploreRolled && gNnExplore;
	if (explore && (gEcoFlat < 0.f))
		gEcoFlat = float(AiRandom(0, 10000)) / 10000.f * 0.5f;
	const float flat = explore ? gEcoFlat : 0.f;
	if (!gJoinHeader) {
		gJoinHeader = true;
		AiLog("apex: nnjoin-schema v1 state=" + NN_STATE + " join=" + NNJ_JOIN + " opt=name,w,p opts=JOIN,NEW");
	}
	array<float> st;
	NnState(unit, st);
	array<float> f;
	f.insertLast(bestMe);
	f.insertLast(dSpot);
	f.insertLast(dNew);
	f.insertLast(extra / v);
	f.insertLast(leftS);
	f.insertLast(progress);
	f.insertLast(float(crew));
	f.insertLast(float(cap));
	f.insertLast(Catalog::gCostM[int(def.id)]);
	f.insertLast(Catalog::gBuildPower[int(unit.circuitDef.id)]);
	f.insertLast(gESurplusEma);
	f.insertLast(float(frames));
	f.insertLast(float(ai.frame) / 1800.f);
	array<float> w(2, NE2_EPS);
	w[rule] = 1.f;
	const float trust = NnHeadScore(NNJ_ON, NNJ_STATE, NNJ_JOIN, NNJ_S, NNJ_O, NNJ_H, NNJ_XM, NNJ_XS,
		NNJ_W1, NNJ_B1, NNJ_W2, NNJ_B2, NNJ_WO, NNJ_BO, NNJ_TRUST, st, f, w);
	array<float> p(2);
	const int c = EcoDraw(rule, trust, w, p, flat);
	array<string> names = {"JOIN", "NEW"};
	AiLog(EcoLine("nnjoin", names[rule], explore, trust, st, f, names, w, p, c));
	if (c == NJ_JOIN)
		++gJoinN;
	else
		++gJoinNewN;
	if (ai.frame >= gJoinLogAt) {
		gJoinLogAt = ai.frame + 60 * SECOND;
		AiLog("apex: join t=" + ai.teamId + " joined=" + gJoinN + " new=" + gJoinNewN
			+ " last=" + def.GetName() + " dMe=" + int(bestMe) + " dNew=" + int(dNew)
			+ " leftS=" + int(leftS) + " crew=" + crew + "/" + cap);
	}
	return (c == NJ_JOIN) ? best : null;
}

}  // namespace Market
