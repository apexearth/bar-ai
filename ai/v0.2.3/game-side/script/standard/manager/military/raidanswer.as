namespace Military {

// A RAIDER THAT KILLS A BUILDING ON OUR GROUND GETS A SQUAD ITS SIZE (docs/24:
// size a squad for each threat and hunt it down; home defence at 1.2x parity;
// guns there mean it will be fine). CDefendTask::Detach does it only inside a
// DEFEND pool, which in a 1v1 holds about one unit. The nearest units within
// PostReach -- spare escorts, DEFEND pools, packs the raid net holds home,
// attack squads -- go together on a RAID task aimed at the spot, or none go;
// they re-elect when the spot is clear or after BaseRaided's 45 s. An army
// out of reach is met by the hunt's intercept (nnhunt.as).

const float ANSWER_PARITY = 1.2f;
const int   ANSWER_LIFE = 45 * SECOND;

array<int>      gAnsId;
array<AIFloat3> gAnsPos;
array<float>    gAnsR;
array<int>      gAnsAt;
array<int>      gAnsBorn;
array<int>      gAnsSent;
array<IUnitTask@> gAnsTask;
array<int>      gAnsClaim;
array<int>      gAnsClaimSlot;
int gAnsNextId = 1;

array<AIFloat3> gAnsEvPos;
array<int>      gAnsEvDef;

int gAnsEvents = 0, gAnsSentN = 0, gAnsPulled = 0, gAnsShort = 0, gAnsCovered = 0;
int gAnsMerged = 0, gAnsClear = 0, gAnsTimeout = 0, gAnsGone = 0;
int gAnsLogAt = 0;
int gAnsStatAt = 0;

bool IsAnswerTask(IUnitTask@ t)
{
	if (t is null)
		return false;
	for (uint i = 0; i < gAnsTask.length(); ++i) {
		if (gAnsTask[i] is t)
			return true;
	}
	return false;
}

bool AnswerClaimed(int id)
{
	return gAnsClaim.find(id) >= 0;
}

// The pulled unit's re-election: the answer's task, created on the first claim
// to arrive so the manager never reaps an empty one.
IUnitTask@ AnswerTaskFor(int id)
{
	const int c = gAnsClaim.find(id);
	if (c < 0)
		return null;
	const int slot = gAnsClaimSlot[c];
	gAnsClaim.removeAt(c);
	gAnsClaimSlot.removeAt(c);
	for (uint i = 0; i < gAnsId.length(); ++i) {
		if (gAnsId[i] != slot)
			continue;
		if ((gAnsTask[i] is null) || gAnsTask[i].IsDead()) {
			@gAnsTask[i] = aiMilitaryMgr.Enqueue(TaskF::Common(Task::FightType::RAID));
			if (gAnsTask[i] !is null)
				gAnsTask[i].SetRaidGoal(gAnsPos[i], gAnsR[i]);
		}
		return gAnsTask[i];
	}
	return null;
}

bool OnOurGround(const AIFloat3& in at)
{
	if (!Builder::gHomeSet)
		return false;
	const AIFloat3 foe = Front::FoeAnchor();
	return !OnMap(foe) || (at.distance2D(foe) >= at.distance2D(Builder::gHomePos));
}

// Our guns that reach `at`, units standing there left out.
float GunsAt(const AIFloat3& in at)
{
	return Market::CoverAt(at) - UnitCoverAt(at) * ai.GetTunable("apex_unit_cover", 1.f);
}

// From the death hook: a finished structure of ours killed by a ground unit.
void NoteRaidOn(const AIFloat3& in at, int killerDef)
{
	if (!OnMap(at) || !Catalog::ValidId(killerDef) || !OnOurGround(at))
		return;
	++gAnsEvents;
	for (uint i = 0; i < gAnsPos.length(); ++i) {
		if (gAnsPos[i].distance2D(at) <= gAnsR[i]) {
			gAnsAt[i] = ai.frame;
			++gAnsMerged;
			return;
		}
	}
	gAnsEvPos.insertLast(at);
	gAnsEvDef.insertLast(killerDef);
}

bool AnswerLogOk()
{
	if (ai.frame < gAnsLogAt)
		return false;
	gAnsLogAt = ai.frame + 5 * SECOND;
	return true;
}

// No base-under-attack gate: BaseUnderAttack reads BaseRaided, which this very
// death has just set, and an army bigger than what is in reach reads "short".
void AnswerRaid(const AIFloat3& in at, int kd)
{
	for (uint i = 0; i < gAnsPos.length(); ++i) {
		if (gAnsPos[i].distance2D(at) <= gAnsR[i]) {
			gAnsAt[i] = ai.frame;
			++gAnsMerged;
			return;
		}
	}
	const float r = PostReach(kd);
	float foeM = ai.GetEnemyArmedCostNear(at, r);
	if (foeM < Catalog::gCostM[kd])
		foeM = Catalog::gCostM[kd];
	const float need = foeM * ANSWER_PARITY;
	const float guns = GunsAt(at);
	if (guns >= foeM) {
		++gAnsCovered;
		if (AnswerLogOk())
			AiLog(Factory::T() + "apex: raid-answer t=" + ai.teamId + " covered at=" + int(at.x) + "," + int(at.z)
				+ " by=" + Catalog::Def(kd).GetName() + " foe=" + int(foeM) + " guns=" + int(guns));
		return;
	}

	array<CCircuitUnit@> cu;
	array<IUnitTask@> ct;
	array<float> cd;
	array<bool> ce;
	for (uint i = 0; i < gSquads.length(); ++i) {
		IUnitTask@ t = gSquads[i];
		if ((t is null) || t.IsDead() || IsAnswerTask(t))
			continue;
		const int ft = t.GetFightType();
		const bool escort = ft == int(Task::FightType::GUARD);
		// a pack the raid net holds home is idle (escnet recruits from it too)
		const bool heldRaid = (ft == int(Task::FightType::RAID)) && NrOn() && (gNrNow == NR_WAIT)
				&& !((gAskTask !is null) && (t is gAskTask));
		if (!escort && !heldRaid && (ft != int(Task::FightType::DEFEND)) && (ft != int(Task::FightType::ATTACK)))
			continue;
		array<CCircuitUnit@>@ on = t.GetUnits();
		if (on is null)
			continue;
		for (uint j = 0; j < on.length(); ++j) {
			CCircuitUnit@ u = on[j];
			if (!RaidWorthPulling(u) || IsRollingBomb(u.circuitDef))
				continue;
			const int uid = int(u.id);
			if (RaidClaimed(uid) || AnswerClaimed(uid))
				continue;
			const float d = u.GetPos(ai.frame).distance2D(at);
			if (d > PostReach(int(u.circuitDef.id)))
				continue;
			if (escort && !EscortSpare(u.id))
				continue;
			uint k = cd.length();
			while ((k > 0) && (cd[k - 1] > d))
				--k;
			cu.insertAt(k, u);
			ct.insertAt(k, t);
			cd.insertAt(k, d);
			ce.insertAt(k, escort);
		}
	}
	float have = 0.f;
	uint take = 0;
	while ((take < cu.length()) && (have < need)) {
		have += Catalog::gCostM[int(cu[take].circuitDef.id)];
		++take;
	}
	if (have < need) {
		++gAnsShort;
		if (AnswerLogOk())
			AiLog(Factory::T() + "apex: raid-answer t=" + ai.teamId + " short at=" + int(at.x) + "," + int(at.z)
				+ " by=" + Catalog::Def(kd).GetName() + " foe=" + int(foeM) + " need=" + int(need)
				+ " have=" + int(have) + "/" + cu.length() + " r=" + int(r));
		return;
	}

	const int id = gAnsNextId++;
	gAnsId.insertLast(id);
	gAnsPos.insertLast(at);
	gAnsR.insertLast(r);
	gAnsAt.insertLast(ai.frame);
	gAnsBorn.insertLast(ai.frame);
	gAnsSent.insertLast(int(take));
	gAnsTask.insertLast(null);
	int nEsc = 0, nAtk = 0;
	for (uint k = 0; k < take; ++k) {
		gAnsClaim.insertLast(int(cu[k].id));
		gAnsClaimSlot.insertLast(id);
		if (ce[k]) {
			Market::EscortGone(cu[k].id);
			++nEsc;
		}
		if (ct[k].GetFightType() == int(Task::FightType::ATTACK))
			++nAtk;
		ct[k].RemoveUnit(cu[k]);
	}
	++gAnsSentN;
	gAnsPulled += int(take);
	if (AnswerLogOk())
		AiLog(Factory::T() + "apex: raid-answer t=" + ai.teamId + " sent at=" + int(at.x) + "," + int(at.z)
			+ " by=" + Catalog::Def(kd).GetName() + " foe=" + int(foeM) + " need=" + int(need)
			+ " m=" + int(have) + " n=" + take + " esc=" + nEsc + " atk=" + nAtk + " near=" + int(cd[0]) + " r=" + int(r));
}

void EndAnswer(uint i, const string why)
{
	if ((gAnsTask[i] !is null) && !gAnsTask[i].IsDead())
		gAnsTask[i].Abort();
	if (AnswerLogOk())
		AiLog(Factory::T() + "apex: raid-answer t=" + ai.teamId + " end " + why
			+ " at=" + int(gAnsPos[i].x) + "," + int(gAnsPos[i].z)
			+ " lifeS=" + int((ai.frame - gAnsBorn[i]) / SECOND) + " n=" + gAnsSent[i]);
	for (int c = int(gAnsClaim.length()) - 1; c >= 0; --c) {
		if (gAnsClaimSlot[c] == gAnsId[i]) {
			gAnsClaim.removeAt(c);
			gAnsClaimSlot.removeAt(c);
		}
	}
	gAnsId.removeAt(i);
	gAnsPos.removeAt(i);
	gAnsR.removeAt(i);
	gAnsAt.removeAt(i);
	gAnsBorn.removeAt(i);
	gAnsSent.removeAt(i);
	gAnsTask.removeAt(i);
}

void UpdateRaidAnswer()
{
	for (int i = int(gAnsId.length()) - 1; i >= 0; --i) {
		const uint u = uint(i);
		const bool started = (gAnsTask[u] !is null);
		const bool waiting = gAnsClaimSlot.find(gAnsId[u]) >= 0;
		if (ai.frame - gAnsAt[u] > ANSWER_LIFE) {
			++gAnsTimeout;
			EndAnswer(u, "timeout");
		} else if (started && gAnsTask[u].IsDead() && !waiting) {
			++gAnsGone;
			EndAnswer(u, "gone");
		} else if (started && (ai.GetEnemyArmedCostNear(gAnsPos[u], gAnsR[u]) <= 0.f)) {
			++gAnsClear;
			EndAnswer(u, "clear");
		}
	}
	if (gAnsClaim.length() > 32) {
		gAnsClaim.removeRange(0, gAnsClaim.length() - 32);
		gAnsClaimSlot.removeRange(0, gAnsClaimSlot.length() - 32);
	}
	for (uint e = 0; e < gAnsEvPos.length(); ++e)
		AnswerRaid(gAnsEvPos[e], gAnsEvDef[e]);
	gAnsEvPos.resize(0);
	gAnsEvDef.resize(0);
	if (ai.frame >= gAnsStatAt) {
		gAnsStatAt = ai.frame + 60 * SECOND;
		AiLog(Factory::T() + "apex: raid-answer-stat t=" + ai.teamId + " events=" + gAnsEvents
			+ " sent=" + gAnsSentN + " pulled=" + gAnsPulled + " short=" + gAnsShort
			+ " covered=" + gAnsCovered + " merged=" + gAnsMerged
			+ " clear=" + gAnsClear + " timeout=" + gAnsTimeout + " gone=" + gAnsGone
			+ " live=" + gAnsId.length());
	}
}

}  // namespace Military
