// THE T2 ECONOMY (TUNE_T2_ECO; his 10-17: "focus on getting the fusions and upgrading the mexes").
// Two consumers of the upgrade rung never read it. The next-tier decision waited for the lab to
// top one election by market price while the ladder already had it reaching the target sooner;
// on, an election whose ladder took the lab counts as the rule's evidence, at the lab's funded
// share (the T2 switch's army half). And the super push and the next-tier hoist took a ceiling
// hand ahead of the upgrades its own list offered; on, they yield to it, an anti-nuke against a
// seen silo excepted. t2eco-stat reads both arms.
namespace Market {

int gT2eOn = -1;
bool T2EcoOn()
{
	if (gT2eOn < 0)
		gT2eOn = (ai.GetTunable("apex_t2_eco", TUNE_T2_ECO) > 0.f) ? 1 : 0;
	return gT2eOn > 0;
}

bool T2EcoSuperGuards(const CCircuitDef@ d)
{
	return (d !is null) && Catalog::gAntiNuke[int(d.id)] && (Brain::EnemyNukeSilos() > 0);
}

int gT2eLadElec = -1;
int gT2eLadN = 0;
float gT2eLadF = 0.f;
void T2EcoLadderNote(Want@ lab)
{
	if ((lab is null) || (gT2eLadElec == gOfferN) || !IsT2Lab(lab))
		return;
	gT2eLadElec = gOfferN;
	gTwEta += lab.funded;
	++gT2eLadN;
	gT2eLadF += lab.funded;
}

int gT2eWinN = 0, gT2eMktN = 0, gT2eEtaN = 0, gT2eEtaOnlyN = 0, gT2eYieldN = 0;
void T2EcoNoteWindow(bool mktNow, bool etaNow)
{
	++gT2eWinN;
	if (mktNow)
		++gT2eMktN;
	if (etaNow)
		++gT2eEtaN;
	if (etaNow && !mktNow)
		++gT2eEtaOnlyN;
}

void T2EcoNoteYield()
{
	++gT2eYieldN;
}

int gT2eAt = -1, gT2eUid = -1;
float gT2eFusV = -1.f, gT2eUpV = -1.f;
int gT2eElec = 0, gT2eExec = 0;
int gT2eFusOff = 0, gT2eFusWon = 0, gT2eUpOff = 0, gT2eUpWon = 0;
float gT2eFusVSum = 0.f, gT2eUpVSum = 0.f, gT2eFusRel = 0.f, gT2eUpRel = 0.f;
int gT2eFusRelN = 0, gT2eUpRelN = 0;
array<int> gT2eWins(WK_TEETH + 1, 0);
array<string> gT2eLostK;
array<int> gT2eLostN;

bool T2EcoHand(CCircuitUnit@ unit)
{
	return (unit !is null) && ReachesCeiling(int(unit.circuitDef.id))
		&& !unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask);
}

// After the ranking, before any hoist: what a ceiling hand was offered.
void T2EcoNoteOffer(CCircuitUnit@ unit, array<Want@>@ ranked)
{
	if (!T2EcoHand(unit) || (ranked is null))
		return;
	gT2eAt = ai.frame;
	gT2eUid = int(unit.id);
	gT2eFusV = -1.f;
	gT2eUpV = -1.f;
	for (uint i = 0; i < ranked.length(); ++i) {
		Want@ r = ranked[i];
		if (r is null)
			continue;
		if ((r.kind == WK_MEXUP) && (r.value > gT2eUpV))
			gT2eUpV = r.value;
		else if ((r.kind == WK_ENERGY) && (r.value > gT2eFusV) && Requests::IsBigEnergy(r.def))
			gT2eFusV = r.value;
	}
	++gT2eElec;
	if (gT2eFusV >= 0.f) {
		++gT2eFusOff;
		gT2eFusVSum += gT2eFusV;
	}
	if (gT2eUpV >= 0.f) {
		++gT2eUpOff;
		gT2eUpVSum += gT2eUpV;
	}
}

void T2EcoLost(const string& in key)
{
	const int at = gT2eLostK.find(key);
	if (at >= 0) {
		++gT2eLostN[uint(at)];
		return;
	}
	gT2eLostK.insertLast(key);
	gT2eLostN.insertLast(1);
}

void T2EcoNoteExec(CCircuitUnit@ unit, Want@ w, const string& in why)
{
	if ((w is null) || (gT2eAt != ai.frame) || (gT2eUid != int(unit.id)))
		return;
	gT2eAt = -1;
	++gT2eExec;
	if ((w.kind >= 0) && (w.kind < int(gT2eWins.length())))
		++gT2eWins[w.kind];
	const bool fus = (w.kind == WK_ENERGY) && Requests::IsBigEnergy(w.def);
	if (gT2eFusV >= 0.f) {
		if (fus)
			++gT2eFusWon;
		else {
			T2EcoLost("fus:" + why + ">" + KindName(w.kind));
			if (w.value > 0.f) {
				gT2eFusRel += gT2eFusV / w.value;
				++gT2eFusRelN;
			}
		}
	}
	if (gT2eUpV >= 0.f) {
		if (w.kind == WK_MEXUP)
			++gT2eUpWon;
		else {
			T2EcoLost("up:" + why + ">" + KindName(w.kind));
			if (w.value > 0.f) {
				gT2eUpRel += gT2eUpV / w.value;
				++gT2eUpRelN;
			}
		}
	}
}

int gT2eLogAt = 0;
void T2EcoStat()
{
	if (ai.frame < gT2eLogAt)
		return;
	gT2eLogAt = ai.frame + 60 * SECOND;
	int hands = 0;
	const array<int>@ own = OwnedDefs();
	for (uint q = 0; q < own.length(); ++q) {
		const int d = own[q];
		if ((gOwnCount[d] > 0) && Catalog::gMobile[d] && Catalog::gBuilder[d] && ReachesCeiling(d)
			&& !Catalog::Def(d).IsRoleAny(Unit::Role::COMM.mask))
			hands += gOwnCount[d];
	}
	UpgradeHandsWant();
	string wins = "";
	for (uint k = 0; k < gT2eWins.length(); ++k) {
		if (gT2eWins[k] > 0)
			wins += ((wins.length() > 0) ? "," : "") + KindName(int(k)) + "=" + gT2eWins[k];
	}
	string lost = "";
	for (uint k = 0; k < gT2eLostK.length(); ++k)
		lost += ((lost.length() > 0) ? "," : "") + gT2eLostK[k] + "=" + gT2eLostN[k];
	AiLog(Factory::T() + "apex: t2eco-stat t=" + ai.teamId + " on=" + (T2EcoOn() ? 1 : 0)
		+ " hands=" + hands + " upHands=" + gUpHandsN + " backlog=" + gUpHandsB
		+ " | elec=" + gT2eElec + " exec=" + gT2eExec
		+ " | fus off=" + gT2eFusOff + " won=" + gT2eFusWon
		+ " v=" + formatFloat((gT2eFusOff > 0) ? (1000.f * gT2eFusVSum / float(gT2eFusOff)) : 0.f, "", 0, 2)
		+ " rel=" + formatFloat((gT2eFusRelN > 0) ? (gT2eFusRel / float(gT2eFusRelN)) : 0.f, "", 0, 2)
		+ " | up off=" + gT2eUpOff + " won=" + gT2eUpWon
		+ " v=" + formatFloat((gT2eUpOff > 0) ? (1000.f * gT2eUpVSum / float(gT2eUpOff)) : 0.f, "", 0, 2)
		+ " rel=" + formatFloat((gT2eUpRelN > 0) ? (gT2eUpRel / float(gT2eUpRelN)) : 0.f, "", 0, 2)
		+ " | wins " + ((wins.length() > 0) ? wins : "-")
		+ " | lost " + ((lost.length() > 0) ? lost : "-")
		+ " | superYield=" + gT2eYieldN
		+ " | tech own=" + OwnTopTier() + " windows=" + gT2eWinN + " mkt=" + gT2eMktN
		+ " eta=" + gT2eEtaN + " etaOnly=" + gT2eEtaOnlyN
		+ " ladder=" + gT2eLadN
		+ " funded=" + formatFloat((gT2eLadN > 0) ? (gT2eLadF / float(gT2eLadN)) : 0.f, "", 0, 2));
	gT2eElec = gT2eExec = 0;
	gT2eFusOff = gT2eFusWon = gT2eUpOff = gT2eUpWon = 0;
	gT2eFusVSum = gT2eUpVSum = gT2eFusRel = gT2eUpRel = 0.f;
	gT2eFusRelN = gT2eUpRelN = 0;
	for (uint k = 0; k < gT2eWins.length(); ++k)
		gT2eWins[k] = 0;
	gT2eLostK.resize(0);
	gT2eLostN.resize(0);
	gT2eYieldN = 0;
	gT2eWinN = gT2eMktN = gT2eEtaN = gT2eEtaOnlyN = 0;
	gT2eLadN = 0;
	gT2eLadF = 0.f;
}

}  // namespace Market
