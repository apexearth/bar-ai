namespace Market {

// A sense want's spotId for a sight post (apex_jam_sight): no protection class.
const int SPOT_SIGHT = -7;

// The sight post this hand can raise over a suspected force (Military::JsUpdate
// prices each place), standing at our side of it; better than `best`, it takes
// the sense ticket.
void JamSightPropose(CCircuitUnit@ unit, Want@ best)
{
	if (!Military::JamSightOn() || (Military::gJpUid.length() == 0) || (unit is null) || (unit.circuitDef is null))
		return;
	const int uid = int(unit.circuitDef.id);
	const int post = Catalog::SightPostFor(uid);
	if (post <= 0)
		return;
	for (uint i = 0; i < Military::gJpUid.length(); ++i) {
		const float gain = Military::gJpW[i];
		if ((gain <= 0.f) || Military::gJpCovered[i])
			continue;
		const AIFloat3 at = Military::JsSightSite(i, post);
		if (!OnMap(at))
			continue;
		Want c;
		ValueOf(post, gain, WalkSecTo(unit, at), Catalog::gBuildPower[uid], c);
		if (c.value > best.value) {
			best = c;
			best.kind = WK_SENSE;
			@best.def = Catalog::Def(post);
			best.pos = at;
			best.spotId = SPOT_SIGHT;
		}
	}
}

}  // namespace Market
