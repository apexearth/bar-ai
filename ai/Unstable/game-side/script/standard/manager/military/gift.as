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
	// Ships are not spare for a land front: the team counts on what can go.
	const float spare = aiMilitaryMgr.armyCost - Market::NavyValue() - keep;
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
			// A gift has to be able to GET there: our water player's boat
			// went to the frontline land player (his watch 2026-09-28).
			float reachR = Catalog::gMaxRange[d];
			if (reachR < 200.f)
				reachR = 200.f;
			if (!ai.CanDefReachAt(cdef, p, toHome, reachR))
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

//------------------------------------------------------------------------------
// FEWER SEATS ON A CROWDED MAP (apexearth 2026-09-30): once, at the start, each
// seat's share of our buildable half (nearest home) is measured identically on
// every seat; while the smallest share is under one base's footprint, that seat
// gives its commander to its nearest kept neighbour. ReadTeamValue sees only
// this library's instances, so nothing goes to a human or other code.
//------------------------------------------------------------------------------
// One base's cells (256 elmo) at minute 40; the measurement is in the commit.
const float SEAT_CELL = 256.f;
const int SEAT_NEED_CELLS = 80;
bool gSeatMergeDone = false;
// A merged seat feeds the seat it joined what that seat has room to store,
// every second, until it is empty (apexearth 2026-09-30: "give them all our
// resources as they need it"). Every seat publishes its free storage.
int gMergedTo = -1;
int gMergeFeedAt = 0;
void FeedMergedSeat()
{
	if (ai.frame < gMergeFeedAt)
		return;
	gMergeFeedAt = ai.frame + SECOND;
	ai.PublishTeamValue("mroom", aiEconomyMgr.metal.storage - aiEconomyMgr.metal.current);
	ai.PublishTeamValue("eroom", aiEconomyMgr.energy.storage - aiEconomyMgr.energy.current);
	if (gMergedTo < 0)
		return;
	float m = aiEconomyMgr.metal.current;
	float e = aiEconomyMgr.energy.current;
	const float mRoom = ai.ReadTeamValue(gMergedTo, "mroom", 0.f);
	const float eRoom = ai.ReadTeamValue(gMergedTo, "eroom", 0.f);
	if (m > mRoom)
		m = mRoom;
	if (e > eRoom)
		e = eRoom;
	if ((m >= 1.f) || (e >= 1.f))
		ai.SendResources((m > 0.f) ? m : 0.f, (e > 0.f) ? e : 0.f, gMergedTo);
}

void UpdateSeatMerge()
{
	FeedMergedSeat();
	if (gSeatMergeDone || (ai.frame < 3 * SECOND))
		return;
	if (ai.frame > 20 * SECOND) {
		gSeatMergeDone = true;
		AiLog(Factory::T() + "apex: seatmerge skipped -- homes not all published");
		return;
	}
	if (Builder::gHomeSet) {
		ai.PublishTeamValue("homex", Builder::gHomePos.x);
		ai.PublishTeamValue("homez", Builder::gHomePos.z);
	}
	array<Id>@ mates = ai.GetTeamIds();
	if ((mates is null) || (mates.length() < 2)) {
		gSeatMergeDone = true;
		return;
	}
	array<int> seat;
	array<AIFloat3> home;
	for (uint i = 0; i < mates.length(); ++i) {
		const int id = int(mates[i]);
		const float hx = ai.ReadTeamValue(id, "homex", -1.f);
		const float hz = ai.ReadTeamValue(id, "homez", -1.f);
		if ((hx < 0.f) || (hz < 0.f))
			return;   // not everyone yet: ask again next update
		uint at = 0;
		while ((at < seat.length()) && (seat[at] < id))
			++at;
		seat.insertAt(at, id);
		home.insertAt(at, AIFloat3(hx, 0.f, hz));
	}
	gSeatMergeDone = true;
	CCircuitUnit@ com = Builder::gComm;
	CCircuitDef@ plant = null;
	if (com !is null) {
		const array<int>@ bl = Catalog::gBuildsList[int(com.circuitDef.id)];
		for (uint q = 0; (q < bl.length()) && (plant is null); ++q) {
			const int p = bl[q];
			if (Catalog::gMobile[p] || Catalog::gFloater[p])
				continue;
			const array<int>@ prods = Catalog::gBuildsList[p];
			for (uint o = 0; o < prods.length(); ++o) {
				if (Catalog::gMobile[prods[o]] && !Catalog::gFlyer[prods[o]] && !Catalog::gFloater[prods[o]]
					&& !Catalog::gAmphib[prods[o]] && !Catalog::gSub[prods[o]]) {
					@plant = Catalog::Def(p);
					break;
				}
			}
		}
	}
	if (plant is null)
		return;
	AIFloat3 mid;
	for (uint i = 0; i < home.length(); ++i)
		mid += home[i];
	mid *= 1.f / float(home.length());
	AIFloat3 foe = aiSetupMgr.GetEnemyBoxCentre();
	if (!OnMap(foe))
		foe = AIFloat3(float(AiTerrainWidth()) - mid.x, 0.f, float(AiTerrainHeight()) - mid.z);
	array<AIFloat3> ground;
	for (float z = SEAT_CELL * 0.5f; z < float(AiTerrainHeight()); z += SEAT_CELL) {
		for (float x = SEAT_CELL * 0.5f; x < float(AiTerrainWidth()); x += SEAT_CELL) {
			const AIFloat3 p(x, 0.f, z);
			if ((p.distance2D(mid) < p.distance2D(foe)) && ai.CanBeBuiltAt(plant, p))
				ground.insertLast(p);
		}
	}
	array<bool> kept(seat.length(), true);
	array<int> giveTo(seat.length(), -1);
	int keptN = int(seat.length());
	string why = "";
	while (keptN > 1) {
		array<int> cells(seat.length(), 0);
		for (uint g = 0; g < ground.length(); ++g) {
			int best = -1;
			float bestD = 0.f;
			for (uint s = 0; s < seat.length(); ++s) {
				if (!kept[s])
					continue;
				const float dd = ground[g].distance2D(home[s]);
				if ((best < 0) || (dd < bestD)) {
					best = int(s);
					bestD = dd;
				}
			}
			++cells[best];
		}
		int small = -1;
		for (uint s = 0; s < seat.length(); ++s) {
			if (kept[s] && ((small < 0) || (cells[s] < cells[small])))
				small = int(s);
		}
		if (cells[small] >= SEAT_NEED_CELLS)
			break;
		int to = -1;
		float toD = 0.f;
		for (uint s = 0; s < seat.length(); ++s) {
			if (!kept[s] || (int(s) == small))
				continue;
			const float dd = home[s].distance2D(home[small]);
			if ((to < 0) || (dd < toD)) {
				to = int(s);
				toD = dd;
			}
		}
		kept[small] = false;
		giveTo[small] = seat[to];
		--keptN;
		why += " t" + seat[small] + "(" + cells[small] + ")->t" + seat[to];
	}
	// A seat merged into one that merged later hands straight to where the chain
	// ends: every seat gives in the same frame.
	for (uint s = 0; s < seat.length(); ++s) {
		for (uint hop = 0; (hop < seat.length()) && (giveTo[s] >= 0); ++hop) {
			int at = -1;
			for (uint k = 0; k < seat.length(); ++k) {
				if (seat[k] == giveTo[s])
					at = int(k);
			}
			if ((at < 0) || kept[at])
				break;
			giveTo[s] = giveTo[at];
		}
	}
	string to = "";
	for (uint s = 0; s < seat.length(); ++s) {
		if (!kept[s])
			to += " t" + seat[s] + "=>t" + giveTo[s];
	}
	AiLog(Factory::T() + "apex: seatmerge seats=" + seat.length() + " kept=" + keptN
		+ " ground=" + ground.length() + " need=" + SEAT_NEED_CELLS + " plant=" + plant.GetName()
		+ (why.isEmpty() ? " none" : why) + " |" + to);
	for (uint s = 0; s < seat.length(); ++s) {
		if ((seat[s] != ai.teamId) || kept[s] || (com is null))
			continue;
		array<CCircuitUnit@> give = {com};
		ai.GiveUnits(give, giveTo[s]);
		gMergedTo = giveTo[s];
		AiLog(Factory::T() + "apex: seatmerge gave commander to t" + giveTo[s]
			+ " and feeds it m=" + int(aiEconomyMgr.metal.current) + " e=" + int(aiEconomyMgr.energy.current));
	}
}

//------------------------------------------------------------------------------
// A T2 CON FOR THE ALLY WITH NONE (apexearth 2026-09-30: "if an ally has no T2
// con and we have lots, we should give one to them, at least if they're nearby
// -- help each other out"). Every seat publishes its count; an ally at zero
// gets one from the seat with two or more whose home is nearest it, so exactly
// one seat gives, and the giver keeps at least one. The hand nearest the ally,
// safe, reachable and not mid-build, goes.
//------------------------------------------------------------------------------
const string TV_T2CON = "t2con";
int gConGiftAt = 0;
int gConGiftTo = -1;
int gConGiftLastAt = -1000000;
int gConGiftShipped = 0;
void UpdateConGift()
{
	if (ai.frame < gConGiftAt)
		return;
	gConGiftAt = ai.frame + 5 * SECOND;
	const int mineN = Market::CeilingConsOwned();
	ai.PublishTeamValue(TV_T2CON, float(mineN));
	array<Id>@ mates = ai.GetTeamIds();
	if ((mates is null) || (mates.length() < 2) || (mineN < 2))
		return;
	for (uint i = 0; i < mates.length(); ++i) {
		const int to = int(mates[i]);
		if (to == ai.teamId)
			continue;
		if (float(ai.frame) - ai.ReadTeamValue(to, TV_GAT, -1000000.f) > 10 * SECOND)
			continue;
		if (ai.ReadTeamValue(to, TV_T2CON, -1.f) != 0.f)
			continue;
		if ((to == gConGiftTo) && (ai.frame - gConGiftLastAt < 60 * SECOND))
			continue;
		const float hx = ai.ReadTeamValue(to, "homex", -1.f);
		const float hz = ai.ReadTeamValue(to, "homez", -1.f);
		if ((hx < 0.f) || (hz < 0.f))
			continue;
		const AIFloat3 toHome(hx, 0.f, hz);
		// The giver: two or more, nearest that home; ties to the lower id.
		int giver = -1;
		float giverD = 0.f;
		for (uint k = 0; k < mates.length(); ++k) {
			const int id = int(mates[k]);
			if (id == to)
				continue;
			if (float(ai.frame) - ai.ReadTeamValue(id, TV_GAT, -1000000.f) > 10 * SECOND)
				continue;
			if (ai.ReadTeamValue(id, TV_T2CON, 0.f) < 2.f)
				continue;
			const float gx = ai.ReadTeamValue(id, "homex", -1.f);
			const float gz = ai.ReadTeamValue(id, "homez", -1.f);
			if ((gx < 0.f) || (gz < 0.f))
				continue;
			const float dd = AIFloat3(gx, 0.f, gz).distance2D(toHome);
			if ((giver < 0) || (dd < giverD) || ((dd == giverD) && (id < giver))) {
				giver = id;
				giverD = dd;
			}
		}
		if (giver != ai.teamId)
			continue;
		CCircuitUnit@ best = null;
		float bestD = 0.f;
		for (uint w = 0; w < Market::gWorkers.length(); ++w) {
			CCircuitUnit@ u = Market::gWorkers[w];
			if (u is null)
				continue;
			const int d = int(u.circuitDef.id);
			if (!Market::ReachesCeiling(d) || u.circuitDef.IsRoleAny(Unit::Role::COMM.mask))
				continue;
			if ((u.task !is null) && (Requests::Progress(u.task) > 0.01f))
				continue;
			const AIFloat3 p = u.GetPos(ai.frame);
			if (!OnMap(p) || (ai.GetUnitThreatAt(u, p) > 0.f))
				continue;
			if (!Catalog::gFlyer[d] && !ai.CanDefReachAt(Catalog::Def(d), p, toHome, 200.f))
				continue;
			const float dd = p.distance2D(toHome);
			if ((best is null) || (dd < bestD)) {
				@best = u;
				bestD = dd;
			}
		}
		if (best is null)
			continue;
		array<CCircuitUnit@> give = {best};
		ai.GiveUnits(give, to);
		++gConGiftShipped;
		gConGiftTo = to;
		gConGiftLastAt = ai.frame;
		AiLog(Factory::T() + "apex: congift -> t=" + to + " " + best.circuitDef.GetName()
			+ " #" + best.id + " dist=" + int(bestD) + " mine=" + mineN
			+ " (total " + gConGiftShipped + ")");
		return;
	}
}

}  // namespace Military
