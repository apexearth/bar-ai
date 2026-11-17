namespace Market {

// THE TEAM'S FIRST GANTRY IS A MIDDLE SEAT'S, AND THE TEAM PAYS FOR IT (his 10-31: "a middle seat is often fine.
// Somewhere not too far, but also safe"). Each seat priced the gantry on its own purse, so the front seats (50-100
// m/s) never could and the eco seats may not while they grow: our first T3 lab stood at 22-26 min against BARb's
// 14-18. One seat that is neither an eco seat nor exposed hosts it; its purse is the team's income, and the other
// seats send their share of what it is short while it builds, as the shared T2 lab's payers do. TUNE_TEAM_GANTRY.
const string TV_TG_SEAT  = "tgseat";
const string TV_TG_STATE = "tgstate";   // 0 none, 1 committed, 2 standing
const string TV_TG_SHORT = "tgshort";
const string TV_TG_PAID  = "tgpaid";
const string TV_TG_INC   = "tginc";
int gTgOn = -1;
int gTgAt = 0;
int gTgSeat = -1;
float gTgPaid = 0.f;
float gTgInflow = 0.f;
float gTgShort = 0.f;
int gTgState = 0;
array<int> gTgRoster;
array<float> gTgSeenPaid;

bool TeamGantOn()
{
	if (gTgOn < 0)
		gTgOn = (ai.GetTunable("apex_team_gantry", TUNE_TEAM_GANTRY) > 0.f) ? 1 : 0;
	return gTgOn > 0;
}

// a big team only: in a small one every seat is the front
bool TeamGantActive()
{
	return TeamGantOn() && (gTgSeat >= 0) && (gTgRoster.length() >= 6);
}

bool TeamGantIsHost()
{
	return TeamGantActive() && (gTgSeat == ai.teamId);
}

bool TgEcoSeat(int id)
{
	return (ai.ReadTeamValue(id, Military::TV_ECOSEAT, 0.f) > 0.5f) || (id == gEcoLatch) || (id == gEcoLatch2);
}

// Our own gantry, as the commitment ledger has it: 0 none, 1 committed (ordered or framed), 2 standing.
int TgOwnState(int &out def)
{
	def = -1;
	int st = 0;
	for (uint ci = 0; ci < ComLen(); ++ci) {
		if (SuperClassOf(gComDef[ci]) != SC_GANTRY)
			continue;
		const int s = (gComState[ci] == CS_FINISHED) ? 2 : 1;
		if (s > st) {
			st = s;
			def = gComDef[ci];
		}
	}
	return st;
}

// The other seats' income: the host prices the gantry on its own purse plus theirs.
float TgPayersInc()
{
	float all = 0.f;
	for (uint i = 0; i < gTgRoster.length(); ++i)
		if (gTgRoster[i] != ai.teamId)
			all += ai.ReadTeamValue(gTgRoster[i], TV_TG_INC, 0.f);
	return all;
}

void TgElect()
{
	gTgRoster.resize(0);
	array<Id>@ mates = ai.GetTeamIds();
	if (mates is null)
		return;
	array<float> hx, hz;
	array<int> ids;
	for (uint i = 0; i < mates.length(); ++i) {
		const int id = int(mates[i]);
		if (!TtAlive(id))
			continue;
		const float x = ai.ReadTeamValue(id, "homex", -1.f);
		const float z = ai.ReadTeamValue(id, "homez", -1.f);
		if ((x < 0.f) || (z < 0.f))
			continue;
		gTgRoster.insertLast(id);
		ids.insertLast(id);
		hx.insertLast(x);
		hz.insertLast(z);
	}
	if (gTgRoster.length() < 6)
		return;
	// THE FIRST GANTRY COMMITTED IS THE TEAM'S: a seat already building or holding one takes the role
	int lead = -1;
	float leadSt = 0.f;
	for (uint i = 0; i < gTgRoster.length(); ++i) {
		const float s = ai.ReadTeamValue(gTgRoster[i], TV_TG_STATE, 0.f);
		if (s > leadSt + 0.5f) {
			lead = gTgRoster[i];
			leadSt = s;
		}
	}
	if (lead >= 0) {
		gTgSeat = lead;
		return;
	}
	if ((gTgSeat >= 0) && TtAlive(gTgSeat) && !TgEcoSeat(gTgSeat))
		return;
	if ((gTgRoster.length() < mates.length()) && (ai.frame < 30 * SECOND))
		return;
	float cx = 0.f, cz = 0.f;
	for (uint i = 0; i < hx.length(); ++i) {
		cx += hx[i];
		cz += hz[i];
	}
	cx /= float(hx.length());
	cz /= float(hx.length());
	const float ex = float(AiTerrainWidth()) - cx;
	const float ez = float(AiTerrainHeight()) - cz;
	array<float>@ sh = EcoShelter(hx, hz, ex, ez);
	// the most sheltered seat that is not an eco seat, the nearer the team's middle the better on a tie (every ally
	// reads the same roster in the same order, so all elect the same seat)
	int best = -1;
	float bestD = 0.f;
	for (uint i = 0; i < hx.length(); ++i) {
		if (TgEcoSeat(ids[i]))
			continue;
		const float d = (hx[i] - cx) * (hx[i] - cx) + (hz[i] - cz) * (hz[i] - cz);
		if ((best < 0) || (sh[i] > sh[uint(best)]) || ((sh[i] == sh[uint(best)]) && (d < bestD))) {
			best = int(i);
			bestD = d;
		}
	}
	if (best < 0)
		return;
	if (gTgSeat != ids[uint(best)])
		AiLog(Factory::T() + "apex: teamgant-elect t=" + ai.teamId + " seat=t" + ids[uint(best)]
			+ " seats=" + gTgRoster.length() + " shelter=" + int(sh[uint(best)]) + " fromMid=" + int(sqrt(bestD)));
	gTgSeat = ids[uint(best)];
}

void TeamGantTick()
{
	if (!TeamGantOn() || (ai.frame < gTgAt))
		return;
	gTgAt = ai.frame + 5 * SECOND;
	ai.PublishTeamValue(TV_TG_INC, Eco::MInc());
	int def = -1;
	gTgState = TgOwnState(def);
	ai.PublishTeamValue(TV_TG_STATE, float(gTgState));
	TgElect();
	const bool host = TeamGantIsHost();
	ai.PublishTeamValue(TV_TG_SEAT, host ? 1.f : 0.f);
	gTgShort = 0.f;
	if (host) {
		float got = 0.f;
		for (uint i = 0; i < gTgRoster.length(); ++i) {
			const int id = gTgRoster[i];
			if (id == ai.teamId)
				continue;
			while (int(gTgSeenPaid.length()) <= id)
				gTgSeenPaid.insertLast(0.f);
			const float p = ai.ReadTeamValue(id, TV_TG_PAID, 0.f);
			if (p > gTgSeenPaid[id])
				got += p - gTgSeenPaid[id];
			gTgSeenPaid[id] = p;
		}
		gTgInflow += 0.3f * (got / 5.f - gTgInflow);
		// short while the gantry builds and the bank cannot carry the pull
		if ((gTgState == 1) && Catalog::ValidId(def)) {
			const float bs = Catalog::BuildSecondsAt(def, EffBP(0.f));
			const float drain = Catalog::gCostM[def] / ((bs > 1.f) ? bs : 1.f);
			const float gap = Eco::MPull() - Eco::MInc();
			if ((gap > 0.f) && (Eco::MCur() < 5.f * gap))
				gTgShort = (gap < drain) ? gap : drain;
		}
		ai.PublishTeamValue(TV_TG_SHORT, gTgShort);
		return;
	}
	if (!TeamGantActive())
		return;
	const float short = ai.ReadTeamValue(gTgSeat, TV_TG_SHORT, 0.f);
	if (short <= 0.f)
		return;
	float all = 0.f;
	for (uint i = 0; i < gTgRoster.length(); ++i)
		if (gTgRoster[i] != gTgSeat)
			all += ai.ReadTeamValue(gTgRoster[i], TV_TG_INC, 0.f);
	const float mine = Eco::MInc();
	float amt = (all > 0.f) ? (short * 5.f * mine / all) : 0.f;
	if (amt > Eco::MCur())
		amt = Eco::MCur();
	if (amt >= 1.f) {
		ai.SendResources(amt, 0.f, gTgSeat);
		gTgPaid += amt;
		ai.PublishTeamValue(TV_TG_PAID, gTgPaid);
	}
}

int gTgStatAt = 0;
void TeamGantStat()
{
	if (!TeamGantOn() || (ai.frame < gTgStatAt))
		return;
	gTgStatAt = ai.frame + 60 * SECOND;
	AiLog(Factory::T() + "apex: teamgant-stat t=" + ai.teamId + " seat=t" + gTgSeat + " host=" + (TeamGantIsHost() ? 1 : 0)
		+ " seats=" + gTgRoster.length() + " state=" + gTgState + " purse=" + int(Eco::MInc() + (TeamGantIsHost() ? TgPayersInc() : 0.f))
		+ " short=" + formatFloat(gTgShort, "", 0, 1) + " inflow=" + formatFloat(gTgInflow, "", 0, 1)
		+ " paid=" + int(gTgPaid));
}

}  // namespace Market
