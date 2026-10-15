namespace Market {

// THE GAP AN ENEMY JUST BLEW IS THE ONE IT COMES BACK THROUGH (his 10-14). A
// finished gun of ours killed by an enemy leaves a refill: the same gun on the
// same ground, priced by what the hole exposes behind it on the way to our
// base, at the exposure window's arrival rate while the loss is fresh.
// TUNE_DEF_REFILL; docs/27.

const int RF_MAX = 16;
const int RF_LEDGER = 48;
const float RF_ORDER_MATCH = 300.f;

array<AIFloat3> gRfPos;
array<int>   gRfDef;
array<int>   gRfId;
array<int>   gRfAt;
array<float> gRfRec;      // the gain the market ordered the dead gun at, 0 unknown
array<float> gRfExpM;     // our metal in reach and on the corridor behind the gap
array<float> gRfCover;
array<float> gRfThreat;
array<float> gRfHz;
array<bool>  gRfHot;
array<int>   gRfFresh;
int gRfOfferLogAt = 0;
int gRfNextId = 0;

array<AIFloat3> gRoPos;
array<int>   gRoDef;
array<float> gRoGain;

int gRfRecorded = 0;
int gRfOffered = 0;
int gRfWon = 0;
int gRfOrdered = 0;
int gRfStood = 0;
int gRfFaded = 0;
int gRfHotDrop = 0;
int gRfHotSkip = 0;
int gRfNextLog = 0;

bool gRfOnSet = false;
bool gRfOnV = false;
bool RefillOn()
{
	if (!gRfOnSet) {
		gRfOnSet = true;
		gRfOnV = ai.GetTunable("apex_def_refill", TUNE_DEF_REFILL) > 0.f;
	}
	return gRfOnV;
}

bool RefillGun(int d)
{
	return Catalog::ValidId(d) && !Catalog::gMobile[d] && (ProtClassOf(d) == PROT_DEF)
		&& (Catalog::gSurfT[d] > 0.01f) && (Catalog::gMaxRange[d] > 1.f);
}

void RfRemove(uint i)
{
	gRfPos.removeAt(i);  gRfDef.removeAt(i);   gRfId.removeAt(i);    gRfAt.removeAt(i);
	gRfRec.removeAt(i);  gRfExpM.removeAt(i);  gRfCover.removeAt(i); gRfThreat.removeAt(i);
	gRfHz.removeAt(i);   gRfHot.removeAt(i);   gRfFresh.removeAt(i);
}

// A gun order the protect market placed, with the gain it was bought at.
void RefillNoteOrder(int d, const AIFloat3& in at, float gain)
{
	if (!RefillOn() || !RefillGun(d))
		return;
	for (uint i = 0; i < gRoPos.length(); ++i) {
		if ((gRoDef[i] == d) && (gRoPos[i].distance2D(at) < 100.f)) {
			gRoGain[i] = gain;
			return;
		}
	}
	gRoPos.insertLast(at);
	gRoDef.insertLast(d);
	gRoGain.insertLast(gain);
	while (gRoPos.length() > uint(RF_LEDGER)) {
		gRoPos.removeAt(0);
		gRoDef.removeAt(0);
		gRoGain.removeAt(0);
	}
}

void RefillNoteDeath(int d, const AIFloat3& in at)
{
	if (!RefillOn() || !RefillGun(d) || !OnMap(at))
		return;
	float rec = 0.f;
	int best = -1;
	float bestD = RF_ORDER_MATCH;
	for (uint i = 0; i < gRoPos.length(); ++i) {
		if (gRoDef[i] != d)
			continue;
		const float dd = gRoPos[i].distance2D(at);
		if (dd < bestD) {
			bestD = dd;
			best = int(i);
		}
	}
	if (best >= 0) {
		rec = gRoGain[uint(best)];
		gRoPos.removeAt(uint(best));
		gRoDef.removeAt(uint(best));
		gRoGain.removeAt(uint(best));
	}
	++gRfRecorded;
	const float half = 0.5f * Catalog::gMaxRange[d];
	for (uint i = 0; i < gRfPos.length(); ++i) {
		if ((gRfDef[i] == d) && (gRfPos[i].distance2D(at) < half)) {
			gRfAt[i] = ai.frame;
			if (rec > gRfRec[i])
				gRfRec[i] = rec;
			gRfFresh[i] = -1;
			return;
		}
	}
	if (gRfPos.length() >= uint(RF_MAX)) {
		RfRemove(0);
		++gRfFaded;
	}
	gRfPos.insertLast(at);
	gRfDef.insertLast(d);
	gRfId.insertLast(gRfNextId++);
	gRfAt.insertLast(ai.frame);
	gRfRec.insertLast(rec);
	gRfExpM.insertLast(0.f);
	gRfCover.insertLast(0.f);
	gRfThreat.insertLast(0.f);
	gRfHz.insertLast(0.f);
	gRfHot.insertLast(false);
	gRfFresh.insertLast(-1);
}

bool RefillLive(int id)
{
	return (id >= 0) && (gRfId.find(id) >= 0);
}
void RefillNoteWon() { ++gRfWon; }
void RefillNoteOrdered() { ++gRfOrdered; }
void RefillNoteOffered() { ++gRfOffered; }

// A gun of ours finished within the dead gun's reach: the gap is closed.
void RefillNoteBuilt(const AIFloat3& in at)
{
	if (!RefillOn())
		return;
	for (uint i = 0; i < gRfPos.length(); ) {
		if (gRfPos[i].distance2D(at) <= Catalog::gMaxRange[gRfDef[i]]) {
			RfRemove(i);
			++gRfStood;
		} else
			++i;
	}
}

// One stale entry per call: the corridor walk and the risk reads.
void RefillRefreshOne()
{
	const float tau = LossTau();
	int pick = -1;
	for (uint i = 0; i < gRfPos.length(); ++i) {
		if ((pick < 0) || (gRfFresh[i] < gRfFresh[uint(pick)]))
			pick = int(i);
	}
	if ((pick < 0) || ((gRfFresh[uint(pick)] >= 0) && (ai.frame - gRfFresh[uint(pick)] < 5 * SECOND)))
		return;
	const uint i = uint(pick);
	const AIFloat3 s = gRfPos[i];
	const float age = float(ai.frame - gRfAt[i]) / 30.f;
	if (age > 3.f * tau) {
		RfRemove(i);
		++gRfFaded;
		return;
	}
	gRfHot[i] = Builder::SiteHot(s);
	if (gRfHot[i] && (age > tau)) {
		RfRemove(i);
		++gRfHotDrop;
		return;
	}
	const int d = gRfDef[i];
	const AIFloat3 mid = gPfRimOk ? gPfMid : Builder::gHomePos;
	float inReach = 0.f;
	float beyond = 0.f;
	PfStakeShield(s, Catalog::gMaxRange[d], s - mid, true, inReach, beyond);
	gRfExpM[i] = inReach + beyond;
	gRfCover[i] = CoverAt(s);
	gRfThreat[i] = ThreatAt(s);
	gRfHz[i] = HazardAt(s);
	gRfFresh[i] = ai.frame;
}

// Prevented loss per second of def d standing at refill i again.
float RefillGain(uint i, int d, float horizS)
{
	const AIFloat3 s = gRfPos[i];
	const float tau = LossTau();
	const float fade = pow(2.718282f, -(float(ai.frame - gRfAt[i]) / 30.f) / tau);
	const float reach = Catalog::gMaxRange[d];
	float threat = gRfThreat[i];
	if (threat < 1.f)
		threat = 1.f;
	const float cover0 = gRfCover[i];
	const float cover1 = cover0 + CoverAddsAt(s, reach, PfTowerKill(d));
	const float stopped = ShortWith(s, cover0, threat) - ShortWith(s, cover1, threat);
	if (stopped <= 0.f)
		return gRfRec[i] * fade;
	float stakeK = gRfExpM[i];
	const float capM = PfKillCapM(d);
	if ((capM > 0.f) && (stakeK > capM))
		stakeK = capM;
	float hz = gRfHz[i];
	if ((horizS > 1.f) && (hz < fade / horizS))
		hz = fade / horizS;
	float g = stakeK * hz * stopped;
	if (gRfRec[i] * fade > g)
		g = gRfRec[i] * fade;
	return g + LossNearM(s, reach) / tau * stopped;
}

// The dead def when this hand may build it, else its cheapest gun at least as dear.
int RefillDefFor(CCircuitUnit@ unit, int uid, int d0, bool t1Out)
{
	if (unit.circuitDef.CanBuild(Catalog::Def(d0)) && !(t1Out && T1Tower(d0)))
		return d0;
	const array<int>@ b = Catalog::BuildsOf(uid);
	int best = -1;
	for (uint q = 0; q < b.length(); ++q) {
		const int d = b[q];
		if (!Catalog::gAvailable[d] || Catalog::gFloater[d] || Catalog::gSub[d]
			|| Catalog::gNeedGeo[d] || !RefillGun(d)
			|| (Catalog::gCostM[d] < Catalog::gCostM[d0]) || (t1Out && T1Tower(d)))
			continue;
		if ((best < 0) || (Catalog::gCostM[d] < Catalog::gCostM[best]))
			best = d;
	}
	return best;
}

void RefillLog()
{
	if (ai.frame < gRfNextLog)
		return;
	gRfNextLog = ai.frame + 60 * SECOND;
	AiLog("apex: refill-stat t=" + ai.teamId + " recorded=" + gRfRecorded + " offered=" + gRfOffered
		+ " won=" + gRfWon + " ordered=" + gRfOrdered + " stood=" + gRfStood + " faded=" + gRfFaded
		+ " hot=" + gRfHotDrop + " hotSkip=" + gRfHotSkip + " exempt=" + Requests::RefillExemptN()
		+ " live=" + gRfPos.length());
}

// The best refill this hand can place, or null.
Want@ RefillPropose(CCircuitUnit@ unit, bool t1Out)
{
	if (!RefillOn())
		return null;
	RefillLog();
	if (gRfPos.length() == 0)
		return null;
	RefillRefreshOne();
	const int uid = int(unit.circuitDef.id);
	const AIFloat3 here = unit.GetPos(ai.frame);
	const float speed = Catalog::gSpeed[uid];
	float horizS = ai.GetTunable("apex_exposed_loss_s", TUNE_EXPOSED_LOSS_S);
	if (horizS <= 1.f)
		horizS = TUNE_EXPOSED_LOSS_S;
	Want@ best = null;
	for (uint i = 0; i < gRfPos.length(); ++i) {
		if (gRfFresh[i] < 0)
			continue;
		if (gRfHot[i]) {
			++gRfHotSkip;
			continue;
		}
		const int d = RefillDefFor(unit, uid, gRfDef[i], t1Out);
		if (d < 0)
			continue;
		const float gain = RefillGain(i, d, horizS);
		if (gain <= 0.f)
			continue;
		Want c;
		const float walkSec = (speed > 1.f) ? (here.distance2D(gRfPos[i]) / speed) : 60.f;
		ValueOf(d, gain, walkSec, Catalog::gBuildPower[uid], c, false);
		if ((best is null) || (c.value > best.value)) {
			c.kind = WK_PROTECT;
			@c.def = Catalog::Def(d);
			c.pos = gRfPos[i];
			c.spotId = PROT_DEF;
			c.refill = gRfId[i];
			@best = c;
		}
	}
	return best;
}

}  // namespace Market
