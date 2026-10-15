namespace Market {
// DEFENCE AS A CRUTCH (his 2026-10-14, docs/doctrine.md "Defending the base"): five
// switches, each turning one rule that bypassed the draw into a priced offer.
// The counters below are what `apex: ecodef-stat` prints once a minute.

bool gEdOnSet = false;
bool gEdRadar = false, gEdDefJoin = false, gEdField = false, gEdCover = false, gEdDanger = false;
void EdLatch()
{
	if (gEdOnSet)
		return;
	gEdOnSet = true;
	gEdRadar = ai.GetTunable("apex_radar_price", TUNE_RADAR_PRICE) > 0.5f;
	gEdDefJoin = ai.GetTunable("apex_defjoin_price", TUNE_DEFJOIN_PRICE) > 0.5f;
	gEdField = ai.GetTunable("apex_field_priced", TUNE_FIELD_PRICED) > 0.5f;
	gEdCover = ai.GetTunable("apex_cover_priced", TUNE_COVER_PRICED) > 0.5f;
	gEdDanger = ai.GetTunable("apex_def_danger", TUNE_DEF_DANGER) > 0.5f;
}
bool RadarPriceOn() { EdLatch(); return gEdRadar; }
bool DefJoinPriceOn() { EdLatch(); return gEdDefJoin; }
bool FieldPricedOn() { EdLatch(); return gEdField; }
bool CoverPricedOn() { EdLatch(); return gEdCover; }
bool DefDangerOn() { EdLatch(); return gEdDanger; }

// per builder id: the gain of the want its current task was elected on
array<float> gIncGain(32001, 0.f);

// the defence assist's own boss, kept apart from gAssistTarget: offered to the
// draw, it may lose to a priced assist that needs the shared slot intact
CCircuitUnit@ gDjTarget = null;
Id gDjTargetId = -1;
int gDjGuardS = 60;

int gEdRadarN = 0;          // radar gains priced on the army's stake
float gEdRadarOldG = 0.f;   // ...what the old rule would have paid, summed
float gEdRadarNewG = 0.f;   // ...and what it pays now
int gEdDjOffer = 0, gEdDjWin = 0, gEdDjNoGain = 0;
float gEdDjV = 0.f;         // summed value x1000 of the offers
int gEdFieldDraw = 0, gEdFieldWin = 0;
int gEdCovOffer = 0, gEdCovWin = 0, gEdCovNoPrice = 0;
int gEdBfOffer = 0, gEdBfWin = 0;
float gEdDangerShare = 1.f, gEdThreat = 0.f, gEdMeet = 0.f;
int gNextEdLog = 0;

// The going rate of each tower def: the gain the defence market last priced it
// at, at its own best site, if within 10 s (an election can span frames). A
// cover tower bids at it.
array<float> gEdDefGain;
array<int> gEdDefGainAt;
void EdDefGainNote(int d, float gain)
{
	if (d < 0)
		return;
	if (uint(d) >= gEdDefGain.length()) {
		gEdDefGain.resize(uint(d) + 1);
		gEdDefGainAt.resize(uint(d) + 1);
	}
	gEdDefGain[uint(d)] = gain;
	gEdDefGainAt[uint(d)] = ai.frame;
}
float EdDefGainNow(int d)
{
	if ((d < 0) || (uint(d) >= gEdDefGain.length()) || (ai.frame - gEdDefGainAt[uint(d)] > 10 * SECOND))
		return 0.f;
	return gEdDefGain[uint(d)];
}

void RadarPriceNote(float oldG, float newG)
{
	++gEdRadarN;
	gEdRadarOldG += oldG;
	gEdRadarNewG += newG;
}

void EcoDefLog()
{
	if (ai.frame < gNextEdLog)
		return;
	gNextEdLog = ai.frame + 60 * SECOND;
	EdLatch();
	AiLog(Factory::T() + "apex: ecodef-stat t=" + ai.teamId
		+ " on=" + (gEdRadar ? 1 : 0) + (gEdDefJoin ? 1 : 0) + (gEdField ? 1 : 0)
			+ (gEdCover ? 1 : 0) + (gEdDanger ? 1 : 0)
		+ " radar=" + gEdRadarN
			+ " gOld=" + formatFloat((gEdRadarN > 0) ? gEdRadarOldG / float(gEdRadarN) : 0.f, "", 0, 2)
			+ " gNew=" + formatFloat((gEdRadarN > 0) ? gEdRadarNewG / float(gEdRadarN) : 0.f, "", 0, 2)
		+ " djOffer=" + gEdDjOffer + " djWin=" + gEdDjWin + " djNoGain=" + gEdDjNoGain
			+ " djV=" + formatFloat((gEdDjOffer > 0) ? gEdDjV / float(gEdDjOffer) : 0.f, "", 0, 2)
		+ " fieldDraw=" + gEdFieldDraw + " fieldWin=" + gEdFieldWin
		+ " covOffer=" + gEdCovOffer + " covWin=" + gEdCovWin
		+ " bfOffer=" + gEdBfOffer + " bfWin=" + gEdBfWin + " covNoPrice=" + gEdCovNoPrice
		+ " danger=" + formatFloat(gEdDangerShare, "", 0, 2)
			+ " threat=" + int(gEdThreat) + " meet=" + int(gEdMeet));
}

}  // namespace Market
