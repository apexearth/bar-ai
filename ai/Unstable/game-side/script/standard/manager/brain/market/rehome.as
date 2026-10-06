namespace Market {

// A LOST BASE IS LEFT, NOT HAUNTED (his 2026-10-05: when the original base
// falls the commander builds nowhere else, "we still have plenty of income,
// we can totally start a new base somewhere else"). Home, the base anchor, the
// nano farm and the commander's retreat point all came from the first base and
// never moved: he retreated into the army that took it, and every site the
// plan offered stood on enemy ground. Once we have had a plant, own none, and
// the old anchor is held (SpotHot: their threat beats our influence there),
// home moves to the metal spot or standing building of ours farthest from
// every enemy we know of, less the commander's walk to it.
bool gRhHadPlant = false;
int gRhAt = -1;
int gRhN = 0;

void RehomeUpdate()
{
	if (ai.frame < gRhAt + 10 * SECOND)
		return;
	gRhAt = ai.frame;
	if (Factory::gFacUnits.length() > 0) {
		gRhHadPlant = true;
		return;
	}
	if (!gRhHadPlant || !Builder::gHomeSet || !Base::gAnchorSet || !SpotHot(Base::gAnchor))
		return;
	CCircuitUnit@ com = Builder::gComm;
	const AIFloat3 from = (com !is null) ? com.GetPos(ai.frame) : Builder::gHomePos;
	array<AIFloat3> foe = {Base::gAnchor};
	const AIFloat3 fa = Front::FoeAnchor();
	if (OnMap(fa))
		foe.insertLast(fa);
	if (Military::PushIncoming() && OnMap(Military::gIncomingPos))
		foe.insertLast(Military::gIncomingPos);
	CacheSpots();
	array<AIFloat3> cand;
	for (uint s = 0; s < gAllSpots.length(); ++s)
		cand.insertLast(gAllSpots[s]);
	for (uint i = 0; i < ComLen(); ++i) {
		if ((gComState[i] & CS_COMING) == 0)
			cand.insertLast(gComPos[i]);
	}
	float bestScore = -1e30f;
	AIFloat3 best;
	bool found = false;
	for (uint c = 0; c < cand.length(); ++c) {
		const AIFloat3 p = cand[c];
		if (!OnMap(p) || SpotHot(p))
			continue;
		float dFoe = 1e30f;
		for (uint k = 0; k < foe.length(); ++k) {
			const float d = p.distance2D(foe[k]);
			dFoe = (d < dFoe) ? d : dFoe;
		}
		const float score = dFoe - p.distance2D(from);
		if (score > bestScore) {
			bestScore = score;
			best = p;
			found = true;
		}
	}
	if (!found)
		return;
	++gRhN;
	AiLog(Factory::T() + "apex: rehome t=" + ai.teamId + " #" + gRhN
		+ " from=" + int(Base::gAnchor.x) + "," + int(Base::gAnchor.z)
		+ " to=" + int(best.x) + "," + int(best.z)
		+ " walk=" + int(best.distance2D(from)) + " foeD=" + int(bestScore + best.distance2D(from)));
	Builder::gHomePos = best;
	Base::gAnchor = best;
	gFarmSet = false;
}

}  // namespace Market
