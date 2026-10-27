namespace Market {
// CALIBRATION, STEP ONE: WHAT THE PRICE ASSUMED (his 10-27: make the pricing sound, then train a new net). Every
// structure of ours that finishes logs the risk the survival discount priced at its spot -- StreamRisk, a rate per
// second -- with its hazard and shortfall parts and its forward fraction; tools/calib.py joins it to the building's
// death (BARAI_DEATH by uid) and sets the predicted rate against the observed one, per kind and forward band.
void CalibNoteBorn(CCircuitUnit@ unit)
{
	if ((unit is null) || (unit.circuitDef is null) || unit.circuitDef.IsMobile() || !Builder::gHomeSet)
		return;
	const AIFloat3 p = unit.GetPos(ai.frame);
	if (!OnMap(p))
		return;
	AiLog("apex: calib-born t=" + ai.teamId + " uid=" + int(unit.id) + " def=" + unit.circuitDef.GetName()
		+ " fwd=" + NnF(Military::ForwardFraction(p), 2) + " risk=" + NnF(StreamRisk(p), 5)
		+ " hz=" + NnF(HazardAt(p), 5) + " short=" + NnF(ShortfallAt(p), 2));
}

}  // namespace Market
