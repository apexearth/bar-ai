namespace Market {

// ONE SEAT TECHS FOR THE TEAM (TUNE_TEAM_TECH, his 10-15). One seat per team is
// elected once and takes its advanced lab at the normal time; its lab keeps
// turning out advanced constructors for the team's uncovered upgrade hands and
// gift.as hands them out. The other seats price their own first advanced lab
// down by the share of their upgrade hands the handouts cover, so they stay T1.
const string TV_TT_SEAT  = "ttseat";
const string TV_TT_WANT  = "ttwant";
const string TV_TT_LAB   = "ttlab";
const string TV_TT_READY = "ttready";
const string TV_TT_RATE  = "ttrate";
// THE TEAM PAYS FOR IT (his 10-29: "they can even pay the team which goes for the advanced lab to get there earlier"):
// while the tech seat's lab, or its constructors for the team, waits on metal, it publishes the shortfall and every
// other seat sends its income share of it out of its bank. The inflow counts in the seat's published rate and ready
// time, so the others see the shared lab as the fast path it is.
const string TV_TT_SHORT = "ttshort";
const string TV_TT_PAID  = "ttpaid";
const string TV_TT_INC   = "ttinc";
const string TV_TT_OWN   = "ttown";   // every seat's own advanced lab: 2 standing, 1 coming, 0 none
int gTtPayOn = -1;
float gTtPaid = 0.f;
float gTtShort = 0.f;
float gTtInflow = 0.f;
float gTtExtraInc = 0.f;
array<float> gTtSeenPaid;

int gTtOn = -1;
int gTtAt = 0;
int gTtSeat = -1;
array<int> gTtRoster;
float gTtCover = 0.f;
float gTtUpShare = 0.f;
float gTtOwed = 0.f;
int gTtOwnAdv = 0;
int gTtLabState = 0;
float gTtTown = 0.f;
float gTtReadyS = 0.f;
float gTtRateA = 0.f;
// stats, reset each minute
int gTtStatAt = 0;
int gTtDiscN = 0;
float gTtDiscSum = 0.f;
int gTtAnyway = 0;
int gTtBuilt = 0;
int gTtGiven = 0;
int gTtLastMine = -1;
int gTtGivenTick = 0;
array<int> gTtGivenTo;
array<int> gTtGivenAt;
array<float> gTtCredit;

bool TeamTechOn()
{
	if (gTtOn < 0)
		gTtOn = (ai.GetTunable("apex_team_tech", TUNE_TEAM_TECH) > 0.f) ? 1 : 0;
	return gTtOn > 0;
}

bool TeamTechActive()
{
	return TeamTechOn() && (gTtSeat >= 0) && (gTtRoster.length() >= 3);
}

bool TeamTechIsSeat()
{
	return TeamTechActive() && (gTtSeat == ai.teamId);
}

int TeamTechSeat()
{
	return TeamTechActive() ? gTtSeat : -1;
}

bool TtAlive(int id)
{
	return (float(ai.frame) - ai.ReadTeamValue(id, Military::TV_GAT, -1000000.f) <= 10 * SECOND)
		&& (ai.ReadTeamValue(id, "seatout", 0.f) <= 0.f);
}

const array<int>@ TeamTechRoster()
{
	return gTtRoster;
}

// Uncovered upgrade hands a seat published: what it wants less what it holds.
float TtUncovered(int id)
{
	const float w = ai.ReadTeamValue(id, TV_TT_WANT, 0.f);
	const float h = ai.ReadTeamValue(id, Military::TV_T2CON, 0.f);
	return (w > h) ? (w - h) : 0.f;
}

void TtSlot(int id)
{
	while (int(gTtCredit.length()) <= id) {
		gTtCredit.insertLast(0.f);
		gTtGivenTo.insertLast(0);
		gTtGivenAt.insertLast(-1000000);
	}
}

void TtElect()
{
	gTtRoster.resize(0);
	array<Id>@ mates = ai.GetTeamIds();
	if (mates is null)
		return;
	array<float> hx, hz;
	for (uint i = 0; i < mates.length(); ++i) {
		const int id = int(mates[i]);
		if (!TtAlive(id))
			continue;
		const float x = ai.ReadTeamValue(id, "homex", -1.f);
		const float z = ai.ReadTeamValue(id, "homez", -1.f);
		if ((x < 0.f) || (z < 0.f))
			continue;
		gTtRoster.insertLast(id);
		hx.insertLast(x);
		hz.insertLast(z);
	}
	if (gTtRoster.length() < 3)
		return;
	int eco = -1;
	int claim = -1;
	for (uint i = 0; i < gTtRoster.length(); ++i) {
		const int id = gTtRoster[i];
		if ((eco < 0) && (ai.ReadTeamValue(id, Military::TV_ECOSEAT, 0.f) > 0.5f))
			eco = id;
		if ((claim < 0) && (ai.ReadTeamValue(id, TV_TT_SEAT, 0.f) > 0.5f))
			claim = id;
	}
	if ((gTtSeat >= 0) && TtAlive(gTtSeat)) {
		if (ai.ReadTeamValue(gTtSeat, TV_TT_OWN, 0.f) >= 0.5f)
			return;
		// THE FIRST ADVANCED LAB COMMITTED IS THE TEAM'S (10-29 pay test: in 3 of 12 setups the elected seat never
		// ordered one while two others built their own): a seat with one standing or coming takes the role from a
		// seat with none, standing before coming, then the lowest id.
		int lead = -1;
		float leadSt = 0.f;
		for (uint i = 0; i < gTtRoster.length(); ++i) {
			const float s = ai.ReadTeamValue(gTtRoster[i], TV_TT_OWN, 0.f);
			if (s > leadSt + 0.5f) {
				lead = gTtRoster[i];
				leadSt = s;
			}
		}
		if (lead >= 0) {
			gTtSeat = lead;
			return;
		}
		// The eco seat already makes only constructors; it takes the role while no lab is committed.
		if ((eco >= 0) && (eco != gTtSeat))
			gTtSeat = eco;
		return;
	}
	gTtSeat = -1;
	if (claim >= 0) {
		gTtSeat = claim;
		return;
	}
	if (eco >= 0) {
		gTtSeat = eco;
		return;
	}
	if ((gTtRoster.length() < mates.length()) && (ai.frame < 30 * SECOND))
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
	uint best = 0;
	float bestD = -1.f;
	for (uint i = 0; i < hx.length(); ++i) {
		const float d = (hx[i] - ex) * (hx[i] - ex) + (hz[i] - ez) * (hz[i] - ez);
		if ((i == 0) || (sh[i] > sh[best]) || ((sh[i] == sh[best]) && (d > bestD))) {
			best = i;
			bestD = d;
		}
	}
	gTtSeat = gTtRoster[best];
	AiLog(Factory::T() + "apex: teamtech-elect t=" + ai.teamId + " seat=t" + gTtSeat
		+ " seats=" + gTtRoster.length() + " shelter=" + int(sh[best]));
}

bool TtAdvPlant(int d)
{
	return Catalog::ValidId(d) && !Catalog::gMobile[d] && (Catalog::gBuildsList[d].length() > 0)
		&& ((Factory::userData[d].attr & (Factory::Attr::T2 | Factory::Attr::T3)) != 0);
}

// The cheapest advanced constructor a plant turns out, or -1.
int TtConOf(int lab)
{
	int con = -1;
	const array<int>@ bl = Catalog::gBuildsList[lab];
	for (uint q = 0; q < bl.length(); ++q) {
		const int c = bl[q];
		if (!Catalog::gMobile[c] || !Catalog::gBuilder[c] || !ReachesCeiling(c)
				|| Catalog::Def(c).IsRoleAny(Unit::Role::COMM.mask))
			continue;
		if ((con < 0) || (Catalog::gCostM[c] < Catalog::gCostM[con]))
			con = c;
	}
	return con;
}

float TtFeedSec(float costM)
{
	const float inc = Eco::MInc() + gTtExtraInc;
	const float s = (costM - 0.5f * Eco::MCur()) / ((inc > 0.1f) ? inc : 0.1f);
	return (s > 0.f) ? s : 0.f;
}

float TtLabSec(int lab, float prog)
{
	const float left = 1.f - prog;
	const float b = Catalog::BuildSecondsAt(lab, EffBP(0.f)) * left;
	const float f = TtFeedSec(Catalog::gCostM[lab] * left);
	return (b > f) ? b : f;
}

float TeamTechInflow()
{
	return TeamTechIsSeat() ? gTtInflow : 0.f;
}

// The lab's real lathe: its own arm plus the nano ring reaching it (Brain::LineBuildPower), once it stands.
float TtLabBP(int lab)
{
	for (uint i = 0; i < Factory::gFacUnits.length(); ++i) {
		CCircuitUnit@ f = Factory::gFacUnits[i];
		if ((f !is null) && (f.circuitDef !is null) && (int(f.circuitDef.id) == lab))
			return Brain::LineBuildPower(f);
	}
	return Catalog::gBuildPower[lab];
}

float TtConSec(int con, int lab, float bp = -1.f)
{
	const float b = Catalog::BuildSecondsAt(con, (bp > 0.f) ? bp : Catalog::gBuildPower[lab]);
	const float inc = Eco::MInc() + gTtExtraInc;
	const float f = Catalog::gCostM[con] / ((inc > 0.1f) ? inc : 0.1f);
	return (b > f) ? b : f;
}

// Our advanced plants in the ledger: 2 one stands, 1 one is coming, 0 none.
int TtOwnLab(float &out prog, int &out lab)
{
	prog = 0.f;
	lab = -1;
	int st = 0;
	int n = 0;
	for (uint ci = 0; ci < ComLen(); ++ci) {
		const int d = gComDef[ci];
		if (!TtAdvPlant(d) || (TtConOf(d) < 0))
			continue;
		if ((gComState[ci] == CS_ORDERED) && (gComTask[ci] !is null)
				&& (Requests::Workers(gComTask[ci]) == 0))
			continue;
		++n;
		if (gComState[ci] == CS_FINISHED) {
			if (st < 2)
				lab = d;
			st = 2;
		} else if (st < 2) {
			const float p = ComProgress(ci);
			if ((st == 0) || (p > prog)) {
				prog = p;
				lab = d;
			}
			st = 1;
		}
	}
	gTtOwnAdv = n;
	return st;
}

// What our own first advanced lab would take to deliver one advanced hand.
float TtOwnPathSec()
{
	int lab = -1;
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!Catalog::gAvailable[d] || !TtAdvPlant(d)
				|| ((Factory::userData[d].attr & Factory::Attr::T2) == 0) || !CanBuildEver(d))
			continue;
		if (((lab < 0) || (Catalog::gCostM[d] < Catalog::gCostM[lab])) && (TtConOf(d) >= 0))
			lab = d;
	}
	if (lab < 0)
		return 0.f;
	return TtLabSec(lab, 0.f) + TtConSec(TtConOf(lab), lab);
}

void TeamTechTick()
{
	if (!TeamTechOn() || (ai.frame < gTtAt))
		return;
	gTtAt = ai.frame + 5 * SECOND;
	const int want = UpgradeHandsWant();
	ai.PublishTeamValue(TV_TT_WANT, float(want));
	const int advBefore = gTtOwnAdv;
	const float coverBefore = gTtCover;
	TtElect();
	const bool me = TeamTechIsSeat();
	ai.PublishTeamValue(TV_TT_SEAT, me ? 1.f : 0.f);
	float prog = 0.f;
	int lab = -1;
	const int st = TtOwnLab(prog, lab);
	if (!me && (coverBefore > 0.f) && (gTtOwnAdv > advBefore))
		gTtAnyway += gTtOwnAdv - advBefore;
	ai.PublishTeamValue(TV_TT_INC, Eco::MInc());
	ai.PublishTeamValue(TV_TT_OWN, float(st));
	gTtExtraInc = 0.f;
	gTtShort = 0.f;
	if (gTtPayOn < 0)
		gTtPayOn = (ai.GetTunable("apex_team_pay", TUNE_TEAM_PAY) > 0.f) ? 1 : 0;
	if (gTtPayOn == 0) {
	} else if (me) {
		float got = 0.f;
		for (uint i = 0; i < gTtRoster.length(); ++i) {
			const int id = gTtRoster[i];
			if (id == ai.teamId)
				continue;
			while (int(gTtSeenPaid.length()) <= id)
				gTtSeenPaid.insertLast(0.f);
			const float p = ai.ReadTeamValue(id, TV_TT_PAID, 0.f);
			if (p > gTtSeenPaid[id])
				got += p - gTtSeenPaid[id];
			gTtSeenPaid[id] = p;
		}
		gTtInflow += 0.3f * (got / 5.f - gTtInflow);
		gTtExtraInc = gTtInflow;
		float drain = 0.f;
		if ((st == 1) && (lab > 0)) {
			const float bs = Catalog::BuildSecondsAt(lab, EffBP(0.f));
			drain = Catalog::gCostM[lab] / ((bs > 1.f) ? bs : 1.f);
		} else if ((st == 2) && (lab > 0) && (TtConOf(lab) >= 0)) {
			float owed = 0.f;
			for (uint i = 0; i < gTtRoster.length(); ++i)
				if (gTtRoster[i] != ai.teamId)
					owed += TtUncovered(gTtRoster[i]);
			if (owed > 0.5f) {
				const int con = TtConOf(lab);
				const float bs = Catalog::BuildSecondsAt(con, TtLabBP(lab));
				drain = Catalog::gCostM[con] / ((bs > 1.f) ? bs : 1.f);
			}
		}
		const float gap = Eco::MPull() - Eco::MInc();
		if ((gap > 0.f) && (Eco::MCur() < 5.f * gap))
			gTtShort = (gap < drain) ? gap : drain;
		ai.PublishTeamValue(TV_TT_SHORT, gTtShort);
	} else if (TeamTechActive()) {
		const float short = ai.ReadTeamValue(gTtSeat, TV_TT_SHORT, 0.f);
		if (short > 0.f) {
			float all = 0.f;
			for (uint i = 0; i < gTtRoster.length(); ++i)
				if (gTtRoster[i] != gTtSeat)
					all += ai.ReadTeamValue(gTtRoster[i], TV_TT_INC, 0.f);
			const float mine = Eco::MInc();
			float amt = (all > 0.f) ? (short * 5.f * mine / all) : 0.f;
			if (amt > Eco::MCur())
				amt = Eco::MCur();
			if (amt >= 1.f) {
				ai.SendResources(amt, 0.f, gTtSeat);
				gTtPaid += amt;
			}
		}
		ai.PublishTeamValue(TV_TT_PAID, gTtPaid);
	}
	gTtOwed = 0.f;
	gTtCover = 0.f;
	gTtLabState = 0;
	gTtTown = 0.f;
	gTtReadyS = 0.f;
	gTtRateA = 0.f;
	if (me) {
		gTtLabState = st;
		ai.PublishTeamValue(TV_TT_LAB, float(st));
		float rate = 0.f;
		float ready = float(ai.frame);
		if ((st > 0) && (lab > 0)) {
			const int con = TtConOf(lab);
			const float cs = TtConSec(con, lab, (st == 2) ? TtLabBP(lab) : -1.f);
			rate = (cs > 0.f) ? (1.f / cs) : 0.f;
			if (st == 1)
				ready += float(SECOND) * (TtLabSec(lab, prog) + cs);
		}
		ai.PublishTeamValue(TV_TT_RATE, rate);
		ai.PublishTeamValue(TV_TT_READY, ready);
		for (uint i = 0; i < gTtRoster.length(); ++i) {
			if (gTtRoster[i] != ai.teamId)
				gTtOwed += TtUncovered(gTtRoster[i]);
		}
		const int mine = CeilingConsAny();
		if (gTtLastMine >= 0) {
			const int add = mine - gTtLastMine + gTtGivenTick;
			if (add > 0)
				gTtBuilt += add;
		}
		gTtLastMine = mine;
		gTtGivenTick = 0;
		return;
	}
	if (!TeamTechActive())
		return;
	gTtLabState = int(ai.ReadTeamValue(gTtSeat, TV_TT_LAB, 0.f) + 0.5f);
	if ((gTtLabState <= 0) || (want <= 0))
		return;
	{
		const float up = UpDemand();
		const float cv = ConvUpDemand();
		float outclass = 0.f;
		const float theirs = ai.GetEnemyMaxMobileCostM();
		const float ours = OwnedBestMobileCostM();
		if ((ours > 0.f) && (theirs > ours))
			outclass = theirs / ours - 1.f;
		const float all = up + cv + outclass;
		gTtUpShare = (all > 0.f) ? (up / all) : 0.f;
	}
	const int have = CeilingConsAny();
	if (have >= want) {
		gTtCover = 1.f;
		return;
	}
	const float d = float(want - have);
	float dAll = d;
	for (uint i = 0; i < gTtRoster.length(); ++i) {
		const int id = gTtRoster[i];
		if ((id != ai.teamId) && (id != gTtSeat))
			dAll += TtUncovered(id);
	}
	const float techU = TtUncovered(gTtSeat);
	gTtRateA = ai.ReadTeamValue(gTtSeat, TV_TT_RATE, 0.f) * dAll / (dAll + techU);
	const float readyF = ai.ReadTeamValue(gTtSeat, TV_TT_READY, float(ai.frame));
	gTtReadyS = (readyF > float(ai.frame)) ? ((readyF - float(ai.frame)) / float(SECOND)) : 0.f;
	gTtTown = TtOwnPathSec();
	const float span = gTtTown - gTtReadyS;
	float served = (span > 0.f) ? (gTtRateA * span * d / dAll) : 0.f;
	if (served > d)
		served = d;
	gTtCover = (float(have) + served) / float(want);
}

// The price multiplier on a seat's own first advanced lab: the handouts cover
// gTtCover of its upgrade hands, and upgrades are gTtUpShare of what the lab is for.
float TeamTechMul(int d, bool count)
{
	if ((gTtCover <= 0.f) || (gTtOwnAdv > 0) || !Catalog::ValidId(d)
			|| ((Factory::userData[d].attr & Factory::Attr::T2) == 0) || Catalog::gMobile[d])
		return 1.f;
	float m = 1.f - gTtCover * gTtUpShare;
	if (m < 0.f)
		m = 0.f;
	if (count) {
		++gTtDiscN;
		gTtDiscSum += m;
	}
	return m;
}

// The tech seat's extra advanced hands: the allies' uncovered upgrade hands.
float TeamTechOwed()
{
	return TeamTechIsSeat() ? gTtOwed : 0.f;
}

void TeamTechNoteGift(int to)
{
	TtSlot(to);
	++gTtGivenTo[to];
	gTtGivenAt[to] = ai.frame;
	++gTtGiven;
	++gTtGivenTick;
}

void TeamTechStat()
{
	if (!TeamTechOn() || (ai.frame < gTtStatAt))
		return;
	gTtStatAt = ai.frame + 60 * SECOND;
	string allies = "";
	for (uint i = 0; i < gTtRoster.length(); ++i) {
		const int id = gTtRoster[i];
		if (id == gTtSeat)
			continue;
		TtSlot(id);
		allies += " t" + id + "=" + int(ai.ReadTeamValue(id, TV_TT_WANT, 0.f))
			+ "/" + int(ai.ReadTeamValue(id, Military::TV_T2CON, 0.f))
			+ "/" + gTtGivenTo[id];
	}
	AiLog(Factory::T() + "apex: teamtech-stat t=" + ai.teamId + " active=" + (TeamTechActive() ? 1 : 0)
		+ " seats=" + gTtRoster.length() + " seat=t" + gTtSeat + " me=" + (TeamTechIsSeat() ? 1 : 0)
		+ " lab=" + gTtLabState
		+ " | built=" + gTtBuilt + " given=" + gTtGiven + " owed=" + int(gTtOwed)
		+ " | want/have/got" + (allies.isEmpty() ? " -" : allies)
		+ " | own want=" + UpgradeHandsWant() + " have=" + CeilingConsAny()
		+ " cover=" + formatFloat(gTtCover, "", 0, 2) + " upShare=" + formatFloat(gTtUpShare, "", 0, 2)
		+ " ready=" + int(gTtReadyS) + "s ownPath=" + int(gTtTown) + "s rate=" + formatFloat(gTtRateA, "", 0, 3)
		+ " disc=" + gTtDiscN + " mul=" + formatFloat((gTtDiscN > 0) ? (gTtDiscSum / float(gTtDiscN)) : 1.f, "", 0, 2)
		+ " ownAdv=" + gTtOwnAdv + " anyway=" + gTtAnyway
		+ " | pay short=" + formatFloat(gTtShort, "", 0, 1) + " inflow=" + formatFloat(gTtInflow, "", 0, 1)
		+ " paid=" + int(gTtPaid));
	gTtDiscN = 0;
	gTtDiscSum = 0.f;
	gTtAnyway = 0;
	gTtBuilt = 0;
	gTtGiven = 0;
}

}  // namespace Market
