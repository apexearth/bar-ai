namespace Market {

//------------------------------------------------------------------------------
// THE SHELLED CENSUS (apexearth 2026-10-09: jammers over the defence "become
// wanted when a defence emplacement is taking long-range fire from something
// like an Ambassador or an LRPC"). Our statics are read a slice per update for
// new damage; a hit counts when the shooter out-reaches what it hit -- a static
// gun its shell names with the longer reach, or nothing we know of inside the
// victim's own reach (our longest gun's, for the backline). Kept by place as a
// decaying ledger, published on the team board, priced by the jammer want.
//------------------------------------------------------------------------------

const int SH_PER_TICK = 96;
const int SH_SRC = 6;
const int SH_MAX = 24;
const int SH_PUB = 6;
const float SH_MERGE_R = 300.f;   // JamReach's floor: one jammer of any kind covers a spot this wide

array<int> gShSeenF;              // per unit id: the frame we last read it
array<float> gShMiss;             // per unit id: missing health then
int gShSrc = 0;
uint gShIdx = 0;
float gShRefR = 0.f;
int gShRefAt = -999999;

array<float> gShX;
array<float> gShZ;
array<float> gShM;
array<int> gShFirstF;
array<float> gShR;
int gShDecayAt = 0;

int gShLogAt = 0;
int gShLogN = 0;
int gShHits = 0;
int gShHitsMin = 0;
float gShHitMMin = 0.f;
int gShCoverLogAt = 0;
int gShPubAt = -999999;

array<float> gShAX;
array<float> gShAZ;
array<float> gShAM;
int gShAllyAt = -999999;
int gShVer = 0;

uint ShSrcLen(int s)
{
	if (s == 0) return gProtUnit[PROT_DEF].length();
	if (s == 1) return gProtUnit[PROT_AA].length();
	if (s == 2) return gProtUnit[PROT_SHIELD].length();
	if (s == 3) return gOwnBig.length();
	if (s == 4) return gOwnGen.length();
	return gOwnConv.length();
}

CCircuitUnit@ ShSrcAt(int s, uint i)
{
	if (s == 0) return gProtUnit[PROT_DEF][i];
	if (s == 1) return gProtUnit[PROT_AA][i];
	if (s == 2) return gProtUnit[PROT_SHIELD][i];
	if (s == 3) return gOwnBig[i];
	if (s == 4) return gOwnGen[i];
	return gOwnConv[i];
}

// What an unarmed building is out-ranged against: the longest gun we field.
float ShRefReach()
{
	if (ai.frame - gShRefAt < 10 * SECOND)
		return gShRefR;
	gShRefAt = ai.frame;
	float r = Brain::LightTowerRange();
	for (uint i = 0; i < gProtDefId[PROT_DEF].length(); ++i) {
		const float g = Catalog::gMaxRange[gProtDefId[PROT_DEF][i]];
		if (g > r)
			r = g;
	}
	gShRefR = r;
	return r;
}

float gShAirSpd = 0.f;
bool gShAirSpdSet = false;
float ShFastestFlyer()
{
	if (gShAirSpdSet || (Catalog::gDefCount <= 0))
		return gShAirSpd;
	gShAirSpdSet = true;
	gShAirSpd = 0.f;
	for (int d = 0; d <= Catalog::gDefCount; ++d) {
		if (Catalog::ValidId(d) && Catalog::gFlyer[d] && (Catalog::gMaxRange[d] > 1.f)
			&& (Catalog::gSpeed[d] > gShAirSpd))
			gShAirSpd = Catalog::gSpeed[d];
	}
	return gShAirSpd;
}

void ShDecay()
{
	const int step = ai.frame - gShDecayAt;
	if (step <= 0)
		return;
	gShDecayAt = ai.frame;
	float k = 1.f - (float(step) / float(SECOND)) / Military::BLEED_TAU;
	if (k < 0.f)
		k = 0.f;
	for (int i = int(gShM.length()) - 1; i >= 0; --i) {
		const uint u = uint(i);
		gShM[u] *= k;
		if (gShM[u] < 1.f) {
			gShX.removeAt(u);
			gShZ.removeAt(u);
			gShM.removeAt(u);
			gShFirstF.removeAt(u);
			gShR.removeAt(u);
		}
	}
}

// Is this hit from something that out-reaches what it hit? byDef is the static
// gun the shell names, or -1.
bool ShLongHit(int vd, const AIFloat3& in at, int weapon, int framesAgo,
		float& out shooterR, int& out byDef)
{
	shooterR = -1.f;
	const float refR = (Catalog::gMaxRange[vd] > 1.f) ? Catalog::gMaxRange[vd] : ShRefReach();
	byDef = ai.GetWeaponStaticOwner(weapon);
	if (Catalog::ValidId(byDef)) {
		shooterR = Catalog::gMaxRange[byDef];
		return shooterR > refR;
	}
	byDef = -1;
	if (ai.GetEnemyCostAt(at, refR) > 0.f)
		return false;
	// A bomber that has flown on is not artillery: anything airborne that could
	// have been over the building since the hit disqualifies it.
	const float flown = refR + ShFastestFlyer() * (float(framesAgo) / float(SECOND) + 1.f);
	return ai.GetEnemyAirCostNear(at, flown) <= 0.f;
}

// seen: 1 the engine named a visible shooter, 0 it did not, -1 a polled hit
// (the poll cannot tell).
void ShelledNote(int vd, const AIFloat3& in at, float dmgM, float shooterR,
		int byDef, int seen, int weapon)
{
	if ((dmgM <= 0.f) || !OnMap(at))
		return;
	ShDecay();
	++gShHits;
	++gShVer;
	++gShHitsMin;
	gShHitMMin += dmgM;
	int s = -1;
	for (uint i = 0; i < gShX.length(); ++i) {
		const float dx = gShX[i] - at.x;
		const float dz = gShZ[i] - at.z;
		if (dx * dx + dz * dz < SH_MERGE_R * SH_MERGE_R) {
			s = int(i);
			break;
		}
	}
	if (s < 0) {
		if (int(gShX.length()) >= SH_MAX) {
			uint worst = 0;
			for (uint i = 1; i < gShM.length(); ++i) {
				if (gShM[i] < gShM[worst])
					worst = i;
			}
			if (gShM[worst] >= dmgM)
				return;
			gShX.removeAt(worst);
			gShZ.removeAt(worst);
			gShM.removeAt(worst);
			gShFirstF.removeAt(worst);
			gShR.removeAt(worst);
		}
		gShX.insertLast(at.x);
		gShZ.insertLast(at.z);
		gShM.insertLast(0.f);
		gShFirstF.insertLast(ai.frame);
		gShR.insertLast(0.f);
		s = int(gShX.length()) - 1;
	}
	gShM[s] += dmgM;
	if (shooterR > gShR[s])
		gShR[s] = shooterR;
	++gShLogN;
	if (ai.frame < gShLogAt)
		return;
	gShLogAt = ai.frame + 5 * SECOND;
	AiLog(Factory::T() + "apex: shelled t=" + ai.teamId + " at=" + int(at.x) + "," + int(at.z)
		+ " def=" + Catalog::Def(vd).GetName() + " dmg=" + int(dmgM)
		+ " shooterR=" + int(shooterR) + " seen=" + seen
		+ " since=" + int(float(ai.frame - gShFirstF[s]) / float(SECOND))
		+ " by=" + (Catalog::ValidId(byDef) ? Catalog::Def(byDef).GetName() : "?")
		+ " w=" + weapon + " spotM=" + int(gShM[s]) + " spots=" + gShX.length()
		+ " n=" + gShLogN);
	gShLogN = 0;
}

// One of our statics died: what was left of it went to whatever shelled it.
void ShelledNoteDeath(CCircuitUnit@ unit, const CCircuitDef@ attackerDef, bool attackerSeen)
{
	if ((unit is null) || (unit.circuitDef is null))
		return;
	const int vd = int(unit.circuitDef.id);
	if (!Catalog::ValidId(vd) || Catalog::gMobile[vd])
		return;
	const int id = int(unit.id);
	const float left = ((id >= 0) && (id < int(gShMiss.length()))) ? (1.f - gShMiss[id]) : 1.f;
	const AIFloat3 at = unit.GetPos(ai.frame);
	const int weapon = unit.GetDamagedWeapon();
	float sR = -1.f;
	int by = -1;
	if ((attackerDef !is null) && Catalog::ValidId(int(attackerDef.id))) {
		const int ad = int(attackerDef.id);
		const float refR = (Catalog::gMaxRange[vd] > 1.f) ? Catalog::gMaxRange[vd] : ShRefReach();
		if (Catalog::gFlyer[ad] || (Catalog::gMaxRange[ad] <= refR))
			return;
		sR = Catalog::gMaxRange[ad];
		by = ad;
	} else if (!ShLongHit(vd, at, weapon, ai.frame - unit.GetDamagedFrame(), sR, by)) {
		return;
	}
	ShelledNote(vd, at, Catalog::gCostM[vd] * ((left > 0.f) ? left : 0.f), sR, by,
			attackerSeen ? 1 : 0, weapon);
}

void ShVisit(CCircuitUnit@ u)
{
	if ((u is null) || (u.circuitDef is null))
		return;
	const int id = int(u.id);
	if (id < 0)
		return;
	if (id >= int(gShSeenF.length())) {
		gShSeenF.resize(uint(id) + 256);
		gShMiss.resize(uint(id) + 256);
	}
	const int df = u.GetDamagedFrame();
	const int was = gShSeenF[id];
	gShSeenF[id] = ai.frame;
	if (df <= was) {
		// repaired since: the next hit is measured from where it stands now
		if (gShMiss[id] > 0.f) {
			const float rm = 1.f - u.GetHealthPercent();
			gShMiss[id] = (rm > 0.f) ? rm : 0.f;
		}
		return;
	}
	float miss = 1.f - u.GetHealthPercent();
	if (miss < 0.f)
		miss = 0.f;
	const float prev = gShMiss[id];
	gShMiss[id] = miss;
	if ((was <= 0) || (miss <= prev))
		return;
	const int vd = int(u.circuitDef.id);
	if (!Catalog::ValidId(vd))
		return;
	const AIFloat3 at = u.GetPos(ai.frame);
	const int weapon = u.GetDamagedWeapon();
	float sR = -1.f;
	int by = -1;
	if (!ShLongHit(vd, at, weapon, ai.frame - df, sR, by))
		return;
	ShelledNote(vd, at, Catalog::gCostM[vd] * (miss - prev), sR, by, -1, weapon);
}

void ShelledPublish()
{
	if (ai.frame - gShPubAt < 5 * SECOND)
		return;
	gShPubAt = ai.frame;
	array<bool> used(gShM.length(), false);
	for (int k = 0; k < SH_PUB; ++k) {
		int b = -1;
		for (uint i = 0; i < gShM.length(); ++i) {
			if (!used[i] && ((b < 0) || (gShM[i] > gShM[uint(b)])))
				b = int(i);
		}
		const string key = "sh" + k;
		if (b < 0) {
			ai.PublishTeamValue(key + "m", 0.f);
			continue;
		}
		used[uint(b)] = true;
		ai.PublishTeamValue(key + "x", gShX[uint(b)]);
		ai.PublishTeamValue(key + "z", gShZ[uint(b)]);
		ai.PublishTeamValue(key + "m", gShM[uint(b)]);
		ai.PublishTeamValue(key + "f", float(ai.frame));
	}
}

// The allies' shelled spots as they published them, aged by our own decay.
void ShelledAllySync()
{
	if (ai.frame - gShAllyAt < 5 * SECOND)
		return;
	gShAllyAt = ai.frame;
	++gShVer;
	gShAX.resize(0);
	gShAZ.resize(0);
	gShAM.resize(0);
	if (gShieldMates is null)
		@gShieldMates = ai.GetTeamIds();
	for (uint m = 0; (gShieldMates !is null) && (m < gShieldMates.length()); ++m) {
		const int t = int(gShieldMates[m]);
		if (t == ai.teamId)
			continue;
		for (int k = 0; k < SH_PUB; ++k) {
			const string key = "sh" + k;
			const float mm = ai.ReadTeamValue(t, key + "m", 0.f);
			const float f = ai.ReadTeamValue(t, key + "f", -1.f);
			if ((mm < 1.f) || (f < 0.f))
				continue;
			const float age = (float(ai.frame) - f) / float(SECOND);
			const float kk = 1.f - age / Military::BLEED_TAU;
			if (kk <= 0.f)
				continue;
			const AIFloat3 p(ai.ReadTeamValue(t, key + "x", -1.f), 0.f,
					ai.ReadTeamValue(t, key + "z", -1.f));
			if (!OnMap(p))
				continue;
			gShAX.insertLast(p.x);
			gShAZ.insertLast(p.z);
			gShAM.insertLast(mm * kk);
		}
	}
}

float gJamMaxR = 300.f;
bool gJamMaxRSet = false;
float JamMaxReach()
{
	if (gJamMaxRSet || (Catalog::gDefCount <= 0))
		return gJamMaxR;
	gJamMaxRSet = true;
	gJamMaxR = 300.f;
	for (int d = 0; d <= Catalog::gDefCount; ++d) {
		if (Catalog::ValidId(d) && Catalog::gJammer[d] && !Catalog::gMobile[d]
			&& (JamReach(d) > gJamMaxR))
			gJamMaxR = JamReach(d);
	}
	return gJamMaxR;
}

// Inside some jammer's own radius -- ours or an ally's, standing, rising or
// ordered -- or a fresh claim within claimR.
bool JamCoveredAt(const AIFloat3& in p, float claimR)
{
	const float mr = JamMaxReach();
	ComNear(p, mr);
	for (uint q = 0; q < gComGrid.hit.length(); ++q) {
		const uint ci = uint(gComGrid.hit[q]);
		const int cd = gComDef[ci];
		if (!Catalog::ValidId(cd) || !Catalog::gJammer[cd] || Catalog::gMobile[cd]
			|| !OnMap(gComPos[ci]))
			continue;
		if (p.distance2D(gComPos[ci]) < JamReach(cd))
			return true;
	}
	AllyStaticsSync();
	gAllyStGrid.Query(p.x, p.z, mr);
	for (uint q = 0; q < gAllyStGrid.hit.length(); ++q) {
		const uint i = uint(gAllyStGrid.hit[q]);
		const int ad = gAllyStDef[i];
		if (Catalog::gJammer[ad] && !Catalog::gMobile[ad]
			&& (p.distance2D(gAllyStPos[i]) < JamReach(ad)))
			return true;
	}
	AllyClaimsSync();
	for (uint i = 0; i < gClaimPos.length(); ++i) {
		if ((gClaimCls[i] == PROT_JAM) && (p.distance2D(gClaimPos[i]) < claimR))
			return true;
	}
	return false;
}

// Metal of ours and our allies' standing within r: what the fire is landing on.
float ShStakeNear(const AIFloat3& in p, float r)
{
	float m = 0.f;
	ComNear(p, r);
	for (uint q = 0; q < gComGrid.hit.length(); ++q) {
		const uint ci = uint(gComGrid.hit[q]);
		if ((gComState[ci] == CS_FINISHED) && Catalog::ValidId(gComDef[ci])
			&& OnMap(gComPos[ci]) && (p.distance2D(gComPos[ci]) < r))
			m += Catalog::gCostM[gComDef[ci]];
	}
	AllyStaticsSync();
	gAllyStGrid.Query(p.x, p.z, r);
	for (uint q = 0; q < gAllyStGrid.hit.length(); ++q) {
		const uint i = uint(gAllyStGrid.hit[q]);
		if (p.distance2D(gAllyStPos[i]) < r)
			m += Catalog::gCostM[gAllyStDef[i]];
	}
	return m;
}

// THE JAMMER UNDER FIRE. A jammer blanks the radar a long-range gun aims by, so
// it is worth the shelling it would stop: the decayed hit metal landing inside
// its radius on spots no jammer covers yet, as a rate, never more than the
// metal standing there over the exposure horizon. Sited half its radius behind
// the worst spot, toward the middle of the base, where the guns stand in front.
array<int> gJshF;
array<int> gJshCom;
array<int> gJshVer;
array<float> gJshG;
array<AIFloat3> gJshAt;
int gJshLogAt = 0;
float JamShelledGain(int d, AIFloat3& out at)
{
	at = AIFloat3(-1.f, 0.f, -1.f);
	if (int(gJshF.length()) <= d) {
		gJshF.resize(uint(d) + 1);
		gJshCom.resize(uint(d) + 1);
		gJshVer.resize(uint(d) + 1);
		gJshG.resize(uint(d) + 1);
		gJshAt.resize(uint(d) + 1);
	}
	ShelledAllySync();
	if ((gJshF[d] > 0) && (ai.frame - gJshF[d] < SECOND)
		&& (gJshCom[d] == gComStamp) && (gJshVer[d] == gShVer))
	{
		at = gJshAt[d];
		return gJshG[d];
	}
	gJshF[d] = (ai.frame > 0) ? ai.frame : 1;
	gJshCom[d] = gComStamp;
	gJshVer[d] = gShVer;
	gJshG[d] = 0.f;
	ShDecay();
	const uint nOwn = gShX.length();
	const uint n = nOwn + gShAX.length();
	if (n == 0)
		return 0.f;
	const float R = JamReach(d);
	array<float> px(n);
	array<float> pz(n);
	array<float> pr(n);
	array<bool> open(n);
	uint nOpen = 0;
	for (uint i = 0; i < n; ++i) {
		px[i] = (i < nOwn) ? gShX[i] : gShAX[i - nOwn];
		pz[i] = (i < nOwn) ? gShZ[i] : gShAZ[i - nOwn];
		pr[i] = ((i < nOwn) ? gShM[i] : gShAM[i - nOwn]) / Military::BLEED_TAU;
		open[i] = !JamCoveredAt(AIFloat3(px[i], 0.f, pz[i]), R);
		if (open[i])
			++nOpen;
	}
	if (nOpen == 0)
		return 0.f;
	const AIFloat3 mid = gPfRimOk ? gPfMid : Builder::gHomePos;
	float bestSum = 0.f;
	int bestA = -1;
	AIFloat3 bestSite;
	for (uint a = 0; a < n; ++a) {
		if (!open[a])
			continue;
		AIFloat3 site(px[a], 0.f, pz[a]);
		AIFloat3 back = mid - site;
		const float bl = sqrt(back.x * back.x + back.z * back.z);
		if (bl > 1.f) {
			const float pull = (bl < 0.5f * R) ? bl : (0.5f * R);
			site = site + back * (pull / bl);
		}
		float sum = 0.f;
		for (uint j = 0; j < n; ++j) {
			if (!open[j])
				continue;
			const float dx = px[j] - site.x;
			const float dz = pz[j] - site.z;
			if (dx * dx + dz * dz < R * R)
				sum += pr[j];
		}
		if (sum > bestSum) {
			bestSum = sum;
			bestA = int(a);
			bestSite = site;
		}
	}
	if (bestA < 0)
		return 0.f;
	const AIFloat3 anchor(px[uint(bestA)], 0.f, pz[uint(bestA)]);
	const AIFloat3 jsite = ai.FindBuildSiteNear(Catalog::Def(d), bestSite, 0.5f * R);
	if (Gate(GATE_JAM_SITE, !OnMap(jsite) || (jsite.distance2D(anchor) >= R)))
		return 0.f;
	float horiz = ai.GetTunable("apex_exposed_loss_s", TUNE_EXPOSED_LOSS_S);
	if (horiz <= 1.f)
		horiz = TUNE_EXPOSED_LOSS_S;
	const float stake = ShStakeNear(jsite, R);
	const float cap = stake / horiz;
	const float g = (bestSum < cap) ? bestSum : cap;
	gJshG[d] = g;
	gJshAt[d] = jsite;
	at = jsite;
	if (ai.frame >= gJshLogAt) {
		gJshLogAt = ai.frame + 20 * SECOND;
		AiLog(Factory::T() + "apex: jamshell t=" + ai.teamId + " def=" + Catalog::Def(d).GetName()
			+ " R=" + int(R) + " gain=" + formatFloat(g, "", 0, 2)
			+ " rate=" + formatFloat(bestSum, "", 0, 2) + " stake=" + int(stake)
			+ " at=" + int(jsite.x) + "," + int(jsite.z)
			+ " anchor=" + int(anchor.x) + "," + int(anchor.z)
			+ " spots=" + n + " open=" + nOpen + " ally=" + gShAX.length());
	}
	return g;
}

void JamCoverLog()
{
	if (ai.frame < gShCoverLogAt)
		return;
	gShCoverLogAt = ai.frame + 60 * SECOND;
	ShelledAllySync();
	float all = 0.f;
	float jammed = 0.f;
	float maxR = 0.f;
	const uint nOwn = gShX.length();
	for (uint i = 0; i < nOwn + gShAX.length(); ++i) {
		const bool own = i < nOwn;
		const float m = own ? gShM[i] : gShAM[i - nOwn];
		const AIFloat3 p(own ? gShX[i] : gShAX[i - nOwn], 0.f, own ? gShZ[i] : gShAZ[i - nOwn]);
		all += m;
		if (JamCoveredAt(p, 0.f))
			jammed += m;
		if (own && (gShR[i] > maxR))
			maxR = gShR[i];
	}
	int t2 = 0;
	for (uint i = 0; i < gProtDefId[PROT_JAM].length(); ++i) {
		if (!T1Tower(gProtDefId[PROT_JAM][i]))
			++t2;
	}
	AllyStaticsSync();
	int allyJ = 0;
	for (uint i = 0; i < gAllyStDef.length(); ++i) {
		if (Catalog::gJammer[gAllyStDef[i]] && !Catalog::gMobile[gAllyStDef[i]])
			++allyJ;
	}
	AiLog(Factory::T() + "apex: jamcover t=" + ai.teamId + " shelledM=" + int(all)
		+ " jammedShare=" + formatFloat((all > 1.f) ? (jammed / all) : 0.f, "", 0, 2)
		+ " jammers=" + gProtDefId[PROT_JAM].length() + " t2jammers=" + t2
		+ " allyJammers=" + allyJ + " spots=" + nOwn + "+" + gShAX.length()
		+ " hits=" + gShHitsMin + "/" + gShHits + " hitM=" + int(gShHitMMin)
		+ " maxShooterR=" + int(maxR));
	gShHitsMin = 0;
	gShHitMMin = 0.f;
}

// A slice of our statics per update; the whole set within a few seconds.
void ShelledUpdate()
{
	if (!Builder::gHomeSet)
		return;
	int left = SH_PER_TICK;
	int guard = SH_SRC + 1;
	while ((left > 0) && (guard > 0)) {
		const uint len = ShSrcLen(gShSrc);
		if (gShIdx >= len) {
			gShSrc = (gShSrc + 1) % SH_SRC;
			gShIdx = 0;
			--guard;
			continue;
		}
		ShVisit(ShSrcAt(gShSrc, gShIdx));
		++gShIdx;
		--left;
	}
	ShDecay();
	ShelledPublish();
	JamCoverLog();
}

}  // namespace Market
