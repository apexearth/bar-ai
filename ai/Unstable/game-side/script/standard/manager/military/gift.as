namespace Military {

//------------------------------------------------------------------------------
// ARMY GOES TO THE ALLY THAT NEEDS IT (apexearth 2026-09-27, watching a huge
// army walk around the enemy that was killing Purple's base: "have teammates
// give army to the ally that seems to need it the most"). Ownership moves, so
// the units defend and retreat to the receiver's base as its own.
//
// Bounded at every step so no ally ever pulls the whole team:
// - a seat NEEDS the enemy metal at its home less its own army; a seat with no
//   factory left needs nothing (its base is lost, and units sent there die);
// - a seat can SPARE its army less what it keeps: the enemy at its own home,
//   or its share of their known army, whichever is more -- nothing while its
//   own home is contested;
// - the neediest ally is covered by the NEAREST donors, each giving only the
//   part of the shortfall the nearer ones have not, so the gifts sum to the
//   need; every seat computes the same allocation from the same blackboard;
// - if all spare together cannot cover it, nobody gives -- a trickle into a
//   fight we cannot win only feeds it.
// Human allies never publish, so nothing is ever given to a person.
//------------------------------------------------------------------------------

const string TV_GNEED  = "gneed";
const string TV_GSPARE = "gspare";
const string TV_GAT    = "gat";
const string TV_GFOE   = "gfoe";

int gGiftPubAt = 0;
int gGiftNextAt = 0;
int gGiftShipped = 0;
int gGiftLastTo = -1;
int gGiftLastAt = -1000000;
int gGiftLogAt = 0;

// Enemy metal at home: groups inside the danger radius, and the metal they are
// killing there when they cannot be seen. HoldNeedM without its stance clause,
// which adds their whole massed army and would make every seat read needy.
float FoeAtHomeM()
{
	if (!Builder::gHomeSet)
		return 0.f;
	float m = 0.f;
	const int nG = aiEnemyMgr.GetEnemyGroupCount();
	for (int i = 0; i < nG; ++i) {
		if (aiEnemyMgr.GetEnemyGroupPos(i).distance2D(Builder::gHomePos) <= Builder::BASE_DANGER_DIST)
			m += aiEnemyMgr.GetEnemyGroupCost(i);
	}
	return (gRaidM > m) ? gRaidM : m;
}

bool HaveFactory()
{
	for (uint i = 0; i < Factory::gFacUnits.length(); ++i) {
		if (Factory::gFacUnits[i] !is null)
			return true;
	}
	return false;
}

float GiftNeedM()
{
	if (!HaveFactory())
		return 0.f;
	const float gap = FoeAtHomeM() - aiMilitaryMgr.armyCost;
	return (gap > 0.f) ? gap : 0.f;
}

// Our share of the enemy army that is NOT already standing at one of our
// homes: the army attacking the ally we would help is not also a threat to
// hold back against, and counting it twice leaves every seat nothing to spare.
float FreeFoeShareM()
{
	float free = EnemyArmyCost();
	array<Id>@ mates = ai.GetTeamIds();
	if (mates !is null) {
		for (uint i = 0; i < mates.length(); ++i) {
			const int id = int(mates[i]);
			if (float(ai.frame) - ai.ReadTeamValue(id, TV_GAT, -1000000.f) > 10 * SECOND)
				continue;
			free -= ai.ReadTeamValue(id, TV_GFOE, 0.f);
		}
	}
	return (free > 0.f) ? (free / AllyCount()) : 0.f;
}

float GiftSpareM()
{
	if (Builder::BaseUnderAttack() || BaseContested())
		return 0.f;
	float keep = FoeAtHomeM();
	const float share = FreeFoeShareM();
	if (share > keep)
		keep = share;
	const float spare = aiMilitaryMgr.armyCost - keep;
	return (spare > 0.f) ? spare : 0.f;
}

bool GiftableDef(int d)
{
	return Catalog::gMobile[d] && !Catalog::gBuilder[d] && !Catalog::gFlyer[d]
		&& !Catalog::gRezzer[d] && (Catalog::gPower[d] > 1.f);
}

void UpdateGifts()
{
	if (ai.frame >= gGiftPubAt) {
		gGiftPubAt = ai.frame + 2 * SECOND;
		ai.PublishTeamValue(TV_GFOE, FoeAtHomeM());
		ai.PublishTeamValue(TV_GNEED, GiftNeedM());
		ai.PublishTeamValue(TV_GSPARE, GiftSpareM());
		ai.PublishTeamValue(TV_GAT, float(ai.frame));
	}
	if (ai.frame < gGiftNextAt)
		return;
	gGiftNextAt = ai.frame + 10 * SECOND;
	array<Id>@ mates = ai.GetTeamIds();
	if ((mates is null) || (mates.length() < 2))
		return;

	// The neediest fresh ally with a home on the board.
	int to = -1;
	float need = 0.f;
	AIFloat3 toHome;
	for (uint i = 0; i < mates.length(); ++i) {
		const int id = int(mates[i]);
		if (float(ai.frame) - ai.ReadTeamValue(id, TV_GAT, -1000000.f) > 10 * SECOND)
			continue;
		const float n = ai.ReadTeamValue(id, TV_GNEED, 0.f);
		const float hx = ai.ReadTeamValue(id, "homex", -1.f);
		const float hz = ai.ReadTeamValue(id, "homez", -1.f);
		if ((n > need) && (hx >= 0.f) && (hz >= 0.f)) {
			need = n;
			to = id;
			toHome = AIFloat3(hx, 0.f, hz);
		}
	}
	if ((to < 0) || (to == ai.teamId))
		return;
	// Gifted units reach the receiver's army at once, but its need is only
	// republished every 2 s: give it the time to read the gift before the
	// same seat is covered again.
	if ((to == gGiftLastTo) && (ai.frame - gGiftLastAt < 30 * SECOND))
		return;

	// Donors nearest the receiver first; the same order on every seat.
	array<int> dId;
	array<float> dSpare;
	array<float> dDist;
	float total = 0.f;
	for (uint i = 0; i < mates.length(); ++i) {
		const int id = int(mates[i]);
		if (id == to)
			continue;
		if (float(ai.frame) - ai.ReadTeamValue(id, TV_GAT, -1000000.f) > 10 * SECOND)
			continue;
		const float s = ai.ReadTeamValue(id, TV_GSPARE, 0.f);
		const float hx = ai.ReadTeamValue(id, "homex", -1.f);
		const float hz = ai.ReadTeamValue(id, "homez", -1.f);
		if ((s <= 0.f) || (hx < 0.f) || (hz < 0.f))
			continue;
		const float dd = AIFloat3(hx, 0.f, hz).distance2D(toHome);
		uint at = 0;
		while ((at < dDist.length())
			&& ((dDist[at] < dd) || ((dDist[at] == dd) && (dId[at] < id))))
			++at;
		dId.insertAt(at, id);
		dSpare.insertAt(at, s);
		dDist.insertAt(at, dd);
		total += s;
	}
	if (total < need) {
		if (ai.frame >= gGiftLogAt) {
			gGiftLogAt = ai.frame + 30 * SECOND;
			AiLog(Factory::T() + "apex: gift none -- t=" + to + " needs " + int(need)
				+ ", the team can spare " + int(total));
		}
		return;
	}
	float left = need;
	float mine = 0.f;
	for (uint k = 0; (k < dId.length()) && (left > 0.f); ++k) {
		const float take = (dSpare[k] < left) ? dSpare[k] : left;
		if (dId[k] == ai.teamId)
			mine = take;
		left -= take;
	}
	if (mine <= 0.f)
		return;

	// Our units nearest the receiver, none already in a fight of its own.
	array<CCircuitUnit@> cand;
	array<float> candD;
	const AIFloat3 home = Builder::gHomeSet ? Builder::gHomePos : toHome;
	const float r = float(AiTerrainWidth() + AiTerrainHeight());
	for (int d = 1; d <= Catalog::gDefCount; ++d) {
		if (!GiftableDef(d))
			continue;
		CCircuitDef@ cdef = Catalog::Def(d);
		if ((cdef is null) || (cdef.count <= 0))
			continue;
		array<CCircuitUnit@>@ us = ai.GetOwnUnitsOfDef(cdef, home, r);
		if (us is null)
			continue;
		for (uint i = 0; i < us.length(); ++i) {
			CCircuitUnit@ u = us[i];
			if (u is null)
				continue;
			const AIFloat3 p = u.GetPos(ai.frame);
			if (!OnMap(p) || (ai.GetUnitThreatAt(u, p) > 0.f))
				continue;
			const float dd = p.distance2D(toHome);
			uint at = 0;
			while ((at < candD.length()) && (candD[at] < dd))
				++at;
			cand.insertAt(at, u);
			candD.insertAt(at, dd);
		}
	}
	array<CCircuitUnit@> give;
	float gave = 0.f;
	for (uint i = 0; (i < cand.length()) && (gave < mine); ++i) {
		give.insertLast(cand[i]);
		gave += Catalog::gCostM[int(cand[i].circuitDef.id)];
	}
	if (give.length() == 0)
		return;
	ai.GiveUnits(give, to);
	gGiftShipped += int(give.length());
	gGiftLastTo = to;
	gGiftLastAt = ai.frame;
	AiLog(Factory::T() + "apex: gift -> t=" + to + " need=" + int(need)
		+ " mine=" + int(mine) + " gave=" + int(gave) + " units=" + give.length()
		+ " (total " + gGiftShipped + ")");
}

}  // namespace Military
