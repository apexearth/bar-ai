namespace Market {
//------------------------------------------------------------------------------
// THE EFFIGY RUSH (his 2026-11-03): while a finished effigy of ours stands, his death costs the
// effigy, not the game, so he walks into their base and D-guns their dearest buildings.
//   death(t) = effigy metal + its energy at the floor price + lathe x (respawn stun from t + rebuild)
//   V(t)     = metal destroyed at t before their fire kills him - (he dies ? death(t) : 0)
//              - lathe x (walk + fight)
// Targets are their base and the cells of their unarmed things, never their army; a raid under way
// is re-priced on its own target. No finished effigy: nothing here runs.
//------------------------------------------------------------------------------

// unit_respawning.lua with the commander defs' minimum_respawn_stun 5, distance_stun_multiplier 1
const float EFFIGY_STUN_S = 5.f;
const float EFFIGY_STUN_PER_ELMO = 1.f / 250.f;

// ---- our effigy, read once a frame ----
int gEfyAt = -1;
int gEfyDef = -1;         // a finished one's def, -1 none
bool gEfyAny = false;     // one stands or is being built
AIFloat3 gEfyPos;
bool gEfyWas = false;
int gEfyLost = 0;         // respawns, or killed: gone with no frame left (a level-up swap keeps one standing)
int gEfyBuildN = 0;
int gEfyMoveN = 0;
int gEfyKeepLogAt = 0;
array<int> gEfyBuildOf;   // per commander def: the effigy it lists, -1 none, -2 unread

void EffigyRead()
{
	if (gEfyAt == ai.frame)
		return;
	gEfyAt = ai.frame;
	EffigyScan();
	gEfyDef = -1;
	gEfyAny = false;
	for (uint i = 0; i < gEffigyDefs.length(); ++i) {
		CCircuitDef@ d = Catalog::Def(gEffigyDefs[i]);
		if (ai.GetDefBuildProgress(d) >= 0.f)
			gEfyAny = true;
		if (gEfyDef >= 0)
			continue;
		array<CCircuitUnit@>@ us = ai.GetOwnUnitsOfDef(d, Builder::gHomePos, 0.f);
		if ((us !is null) && (us.length() > 0)) {
			gEfyDef = gEffigyDefs[i];
			gEfyPos = us[0].GetPos(ai.frame);
		}
	}
}

int EffigyBuildDef(int cd)
{
	if (int(gEfyBuildOf.length()) <= cd) {
		const uint was = gEfyBuildOf.length();
		gEfyBuildOf.resize(cd + 1);
		for (uint i = was; i < gEfyBuildOf.length(); ++i)
			gEfyBuildOf[i] = -2;
	}
	if (gEfyBuildOf[cd] == -2) {
		gEfyBuildOf[cd] = -1;
		const array<int>@ b = Catalog::BuildsOf(cd);
		for (uint i = 0; (b !is null) && (i < b.length()); ++i) {
			if (IsEffigyDef(b[i])) {
				gEfyBuildOf[cd] = b[i];
				break;
			}
		}
	}
	return gEfyBuildOf[cd];
}

// A seen armed foe of the registry reaches pos within one reaction.
bool EffigyExposed(const AIFloat3& in pos)
{
	if (Military::gCfEDef.length() == 0)
		return false;
	Military::gCfEGrid.Query(pos.x, pos.z, Military::gCfEReach);
	for (uint h = 0; h < Military::gCfEGrid.hit.length(); ++h) {
		const int e = Military::gCfEGrid.hit[h];
		if (e >= int(Military::gCfEDef.length()))
			continue;
		const int d = Military::gCfEDef[e];
		if (Military::CfDist(Military::gCfEX[e], Military::gCfEZ[e], pos.x, pos.z)
			<= Catalog::gLandRange[d] + Catalog::gSpeed[d] * Military::CF_REACT_S)
			return true;
	}
	return false;
}

// KEEP ONE STANDING, at home: rebuilt when gone; moved home when their army reaches it and home is
// clear, while what it would cost to replace beats his walk (a move costs the game 1 metal).
// The def to build at `site`, or null; decide.as takes the request.
string gEfyKeepWhy = "";
float gEfyKeepM = 0.f, gEfyKeepWalkS = 0.f;
CCircuitDef@ EffigyKeepAsk(CCircuitUnit@ u, AIFloat3& out site)
{
	site = Builder::gHomePos;
	const int cd = int(u.circuitDef.id);
	const int ed = EffigyBuildDef(cd);
	if (ed < 0)
		return null;
	if ((gComDec != COM_WORK) || gCsThreat || gShip || gEfrOn || !Builder::gHomeSet)
		return null;
	EffigyRead();
	const float spd = (Catalog::gSpeed[cd] > 1.f) ? Catalog::gSpeed[cd] : 1.f;
	gEfyKeepWalkS = u.GetPos(ai.frame).distance2D(site) / spd;
	gEfyKeepWhy = "";
	if (gEfyDef < 0) {
		gEfyKeepWhy = "rebuild";
		gEfyKeepM = Catalog::gCostM[ed] + Catalog::gCostE[ed] * EPriceFloor();
	} else if ((gEfyPos.distance2D(site) > Catalog::gBuildDist[cd]) && EffigyExposed(gEfyPos)
		&& !EffigyExposed(site))
	{
		gEfyKeepM = Catalog::gCostM[gEfyDef] + Catalog::gCostE[gEfyDef] * EPriceFloor();
		if (gEfyKeepM > ComHomeLathe(u) * gEfyKeepWalkS)
			gEfyKeepWhy = "relocate";
	}
	return gEfyKeepWhy.isEmpty() ? null : Catalog::Def(ed);
}

void EffigyKeepNote(CCircuitUnit@ u, CCircuitDef@ d, const AIFloat3& in site)
{
	if (gEfyKeepWhy == "rebuild")
		++gEfyBuildN;
	else
		++gEfyMoveN;
	if (ai.frame < gEfyKeepLogAt)
		return;
	gEfyKeepLogAt = ai.frame + 10 * SECOND;
	AiLog(Factory::T() + "apex: effigy-keep t=" + ai.teamId + " why=" + gEfyKeepWhy
		+ " def=" + d.GetName() + " site=" + int(site.x) + "," + int(site.z)
		+ ((gEfyDef >= 0) ? (" from=" + int(gEfyPos.x) + "," + int(gEfyPos.z)) : "")
		+ " effM=" + int(gEfyKeepM) + " walkS=" + formatFloat(gEfyKeepWalkS, "", 0, 1)
		+ " lathe=" + formatFloat(ComHomeLathe(u), "", 0, 1)
		+ " built=" + gEfyBuildN + " moved=" + gEfyMoveN + " lost=" + gEfyLost);
}

// ---- their unarmed units: what a raid takes once the armed ones are dealt with ----
array<float> gEfrUX, gEfrUZ, gEfrUM, gEfrUH;
Grid::Cells gEfrUGrid;
array<float> gEfrAX, gEfrAZ, gEfrAD, gEfrAR;
Grid::Cells gEfrAGrid;
float gEfrARMax = 0.f;

void EfrUnarmedScan()
{
	gEfrUX.resize(0); gEfrUZ.resize(0); gEfrUM.resize(0); gEfrUH.resize(0);
	gEfrUGrid.Begin(512.f, 0.f, 0.f, float(AiTerrainWidth()), float(AiTerrainHeight()));
	gEfrAX.resize(0); gEfrAZ.resize(0); gEfrAD.resize(0); gEfrAR.resize(0);
	gEfrAGrid.Begin(512.f, 0.f, 0.f, float(AiTerrainWidth()), float(AiTerrainHeight()));
	gEfrARMax = 0.f;
	const int nT = aiEnemyMgr.GetEnemyUnitTotal();
	for (int i = 0; i < nT; ++i) {
		const int d = aiEnemyMgr.GetEnemyUnitDefAt(i);
		if (!Catalog::ValidId(d) || Catalog::gFlyer[d] || Catalog::gKamikaze[d] || (Catalog::gCostM[d] <= 0.f))
			continue;
		const int los = aiEnemyMgr.GetEnemyUnitLosAt(i);
		if ((los < 0) || ((los & (4 | 8 | 32 | 64)) != 0))
			continue;
		if (((los & 3) == 0) && Catalog::gMobile[d])
			continue;
		const AIFloat3 p = aiEnemyMgr.GetEnemyUnitPosAt(i);
		if (!OnMap(p))
			continue;
		if ((Catalog::gSurfDps[d] > 0.f) && (Catalog::gSurfT[d] > 0.f) && (Catalog::gLandRange[d] > 0.f)) {
			gEfrAX.insertLast(p.x);
			gEfrAZ.insertLast(p.z);
			gEfrAD.insertLast(Catalog::gSurfDps[d]);
			gEfrAR.insertLast(Catalog::gLandRange[d]);
			if (Catalog::gLandRange[d] > gEfrARMax)
				gEfrARMax = Catalog::gLandRange[d];
			gEfrAGrid.Add(p.x, p.z);
			continue;
		}
		gEfrUX.insertLast(p.x);
		gEfrUZ.insertLast(p.z);
		gEfrUM.insertLast(Catalog::gCostM[d]);
		gEfrUH.insertLast(Catalog::gHealth[d]);
		gEfrUGrid.Add(p.x, p.z);
	}
}

void EfrUnarmedAt(float x, float z, float r, float& out m, float& out h)
{
	m = 0.f;
	h = 0.f;
	if (gEfrUX.length() == 0)
		return;
	gEfrUGrid.Query(x, z, r);
	for (uint k = 0; k < gEfrUGrid.hit.length(); ++k) {
		const int i = gEfrUGrid.hit[k];
		if ((i >= int(gEfrUX.length())) || (Military::CfDist(gEfrUX[i], gEfrUZ[i], x, z) > r))
			continue;
		m += gEfrUM[i];
		h += gEfrUH[i];
	}
}

// ---- the decision ----
const int EFR_BASE = 0;
const int EFR_ECO = 1;
const int EFR_ARMY = 2;
bool gEfrOn = false;
AIFloat3 gEfrAt(-1.f, 0.f, -1.f);
int gEfrKind = -1;
int gEfrNextAt = 0;
int gEfrLogAt = 0;
int gEfrFrom = -1;
int gEfrN = 0;
int gEfrSec = 0;
string gEfrWhy = "-";
float gEfrEffM = 0.f, gEfrDeathM = 0.f, gEfrLathe = 0.f, gEfrStunS = 0.f, gEfrBuildS = 0.f;
float gEfrK = 0.f, gEfrL = 0.f, gEfrE = 0.f, gEfrTimeM = 0.f, gEfrV = 0.f, gEfrWalk = 0.f, gEfrDg = 0.f;
float gEfrThemM = 0.f;
int gEfrThemN = 0;
int gEfrCands = 0, gEfrAsked = 0;
bool gEfrLives = false;

string EfrKindName(int k)
{
	if (k == EFR_BASE) return "base";
	if (k == EFR_ECO) return "eco";
	if (k == EFR_ARMY) return "army";
	return "-";
}

// Their fire on him standing at (x, z) with his own reach r: every armed unit seen whose range covers him.
float EfrFireAt(float x, float z, float r)
{
	float d = 0.f;
	if (gEfrAX.length() == 0)
		return 0.f;
	gEfrAGrid.Query(x, z, r + gEfrARMax);
	for (uint k = 0; k < gEfrAGrid.hit.length(); ++k) {
		const int i = gEfrAGrid.hit[k];
		if ((i < int(gEfrAX.length())) && (Military::CfDist(gEfrAX[i], gEfrAZ[i], x, z) <= r + gEfrAR[i]))
			d += gEfrAD[i];
	}
	return d;
}

// What he destroys at (x, z) in s seconds: a D-gun shot every dgI on the dearest building in reach, his
// guns on the rest. Out: the metal, the seconds to clear it all (1e9 if he cannot), the D-gun share.
float EfrKillAt(float x, float z, float r, float s, float dgI, float dps, float& out clearS, float& out dgM)
{
	clearS = 0.f;
	dgM = 0.f;
	if (gEfrUX.length() == 0)
		return 0.f;
	array<float> m, h;
	gEfrUGrid.Query(x, z, r);
	for (uint k = 0; k < gEfrUGrid.hit.length(); ++k) {
		const int i = gEfrUGrid.hit[k];
		if ((i < int(gEfrUX.length())) && (Military::CfDist(gEfrUX[i], gEfrUZ[i], x, z) <= r)) {
			m.insertLast(gEfrUM[i]);
			h.insertLast(gEfrUH[i]);
		}
	}
	const int n = int(m.length());
	if (n == 0)
		return 0.f;
	array<int> ord(n);
	for (int i = 0; i < n; ++i)
		ord[i] = i;
	for (int a = 1; a < n; ++a) {
		const int oi = ord[a];
		int b = a - 1;
		while ((b >= 0) && (m[ord[b]] < m[oi])) {
			ord[b + 1] = ord[b];
			--b;
		}
		ord[b + 1] = oi;
	}
	int shots = 0;
	if (dgI > 0.f)
		shots = (s >= 1e8f) ? n : (int(s / dgI) + 1);
	if (shots > n)
		shots = n;
	float restM = 0.f, restH = 0.f;
	for (int q = 0; q < n; ++q) {
		if (q < shots)
			dgM += m[ord[q]];
		else {
			restM += m[ord[q]];
			restH += h[ord[q]];
		}
	}
	const float dgS = (shots > 0) ? float(shots - 1) * dgI : 0.f;
	const float gunS = (dps > 0.f) ? restH / dps : ((restH > 0.f) ? 1e9f : 0.f);
	clearS = (dgS > gunS) ? dgS : gunS;
	float gunM = restM;
	if ((s < clearS) && (restH > 0.f)) {
		const float frac = (dps > 0.f) ? dps * s / restH : 0.f;
		gunM = restM * ((frac < 1.f) ? frac : 1.f);
	}
	return dgM + gunM;
}

void EfrPrice(CCircuitUnit@ u)
{
	const bool committed = gEfrOn;
	const AIFloat3 was = gEfrAt;
	gEfrOn = false;
	gEfrV = 0.f;
	gEfrKind = -1;
	gEfrCands = 0;
	gEfrAsked = 0;
	const int cd = int(u.circuitDef.id);
	const AIFloat3 here = u.GetPos(ai.frame);
	if (!OnMap(here)) {
		gEfrWhy = "offmap";
		return;
	}
	const float spd = (Catalog::gSpeed[cd] > 1.f) ? Catalog::gSpeed[cd] : 1.f;
	const float rng = Catalog::gLandRange[cd];
	gEfrLathe = ComHomeLathe(u);
	int ed = EffigyBuildDef(cd);
	if (ed < 0)
		ed = gEfyDef;
	gEfrEffM = Catalog::gCostM[ed] + Catalog::gCostE[ed] * EPriceFloor();
	const float bp = Catalog::gBuildPower[cd];
	gEfrBuildS = (bp > 0.f) ? Catalog::gBuildTime[ed] / bp : 0.f;
	EfrUnarmedScan();
	float dgI = 0.f;
	{
		const float cost = u.DGunCostE();
		const float eInc = Eco::EInc();
		if ((cost > 0.f) && (eInc > 0.f)) {
			dgI = cost / eInc;
			if (dgI < u.DGunReload())
				dgI = u.DGunReload();
		}
	}
	gEfrDg = (dgI > 0.f) ? 1.f / dgI : 0.f;
	const float dps = Catalog::gSurfDps[cd];
	const float hp = Catalog::gHealth[cd] * u.GetHealthPercent();
	if (((dps <= 0.f) && (dgI <= 0.f)) || (hp <= 0.f)) {
		gEfrWhy = "unarmed";
		return;
	}

	// candidates: their base and the cells of their unarmed things -- labs, extractors, generators, builders.
	// Their army is not a target: on our ground the base's own answer fights it.
	array<float> cx, cz;
	array<int> ck;
	float fbx, fbz;
	Military::SqFoeBase(fbx, fbz);
	if ((fbx >= 0.f) && OnMap(AIFloat3(fbx, 0.f, fbz))) {
		cx.insertLast(fbx); cz.insertLast(fbz); ck.insertLast(EFR_BASE);
	}
	const float cell = (rng * 1.41421356f > 64.f) ? rng * 1.41421356f : 64.f;
	const int nx = int(float(AiTerrainWidth()) / cell) + 1;
	const int nz = int(float(AiTerrainHeight()) / cell) + 1;
	array<float> bm(nx * nz, 0.f);
	array<float> bx(nx * nz, 0.f);
	array<float> bz(nx * nz, 0.f);
	for (uint i = 0; i < gEfrUX.length(); ++i) {
		int ix = int(gEfrUX[i] / cell), iz = int(gEfrUZ[i] / cell);
		ix = (ix < 0) ? 0 : ((ix >= nx) ? nx - 1 : ix);
		iz = (iz < 0) ? 0 : ((iz >= nz) ? nz - 1 : iz);
		const int k = ix + iz * nx;
		bm[k] += gEfrUM[i];
		bx[k] += gEfrUX[i] * gEfrUM[i];
		bz[k] += gEfrUZ[i] * gEfrUM[i];
	}
	for (int k = 0; k < nx * nz; ++k) {
		if (bm[k] <= 0.f)
			continue;
		cx.insertLast(bx[k] / bm[k]); cz.insertLast(bz[k] / bm[k]); ck.insertLast(EFR_ECO);
	}
	// A raid under way is priced on its own target only: the walk already made is spent.
	if (committed && OnMap(was)) {
		int best = -1;
		float bestD = 1e30f;
		for (uint c = 0; c < cx.length(); ++c) {
			const float dd = Military::CfDist(cx[c], cz[c], was.x, was.z);
			if (dd < bestD) {
				bestD = dd;
				best = int(c);
			}
		}
		if ((best < 0) || (bestD > cell)) {
			cx.resize(0); cz.resize(0); ck.resize(0);
		} else {
			const float bxv = cx[best], bzv = cz[best];
			const int bk = ck[best];
			cx.resize(1); cz.resize(1); ck.resize(1);
			cx[0] = bxv; cz[0] = bzv; ck[0] = bk;
		}
	}
	const int nC = int(cx.length());
	gEfrCands = nC;
	bool any = false;
	for (int c = 0; c < nC; ++c) {
		AIFloat3 t(cx[c], 0.f, cz[c]);
		if (!ai.CanDefReachAt(Catalog::Def(cd), here, t, rng))
			continue;
		++gEfrAsked;
		const float walkS = here.distance2D(t) / spd;
		const float stunS = EFFIGY_STUN_S + t.distance2D(gEfyPos) * EFFIGY_STUN_PER_ELMO;
		const float deathM = gEfrEffM + gEfrLathe * (stunS + gEfrBuildS);
		const float fire = EfrFireAt(t.x, t.z, rng);
		const float s = (fire > 0.f) ? hp / fire : 1e9f;
		float clearS, dgM;
		const float killM = EfrKillAt(t.x, t.z, rng, s, dgI, dps, clearS, dgM);
		if (killM <= 0.f)
			continue;
		const bool lives = s >= clearS;
		const float L = lives ? 0.f : deathM;
		const float fightS = lives ? clearS : s;
		const float timeM = gEfrLathe * (walkS + fightS);
		const float v = killM - L - timeM;
		if (any && (v <= gEfrV))
			continue;
		any = true;
		gEfrV = v;
		gEfrAt = t;
		gEfrKind = ck[c];
		gEfrK = dgM;
		gEfrL = L;
		gEfrE = killM - dgM;
		gEfrTimeM = timeM;
		gEfrWalk = walkS;
		gEfrStunS = stunS;
		gEfrDeathM = deathM;
		gEfrLives = lives;
		gEfrThemN = int(fire);
		gEfrThemM = s;
	}
	if (!any) {
		gEfrWhy = (nC == 0) ? (committed ? "cleared" : "no-target") : "unreachable";
		return;
	}
	gEfrOn = gEfrV > 0.f;
	gEfrWhy = committed ? "held" : "priced";
}

// Once a second from ComDecideTick, after the ship's test.
void EffigyRushTick(CCircuitUnit@ u)
{
	const int cd = int(u.circuitDef.id);
	EffigyRead();
	const bool stands = gEfyDef >= 0;
	if (gEfyWas && !stands && !gEfyAny)
		++gEfyLost;
	gEfyWas = stands;
	const bool was = gEfrOn;
	if (!stands || gShip || (gCaVerdict == COM_RETREAT)) {
		gEfrOn = false;
		gEfrWhy = !stands ? "no-effigy" : (gShip ? "ship" : "air");
	} else if (ai.frame >= gEfrNextAt) {
		EfrPrice(u);
		gEfrNextAt = ai.frame + ((gEfrOn || gCsThreat) ? SECOND : 5 * SECOND);
	}
	if (gEfrOn) {
		++gEfrSec;
		// he fights it out: the engine's damage retreat would pull him from the fight priced to the end
		// (ComShipAssess put the line back this tick, so a level-up's new def is the one zeroed)
		ShipRetreatLine(u, true);
	}
	if (gEfrOn && !was) {
		++gEfrN;
		gEfrFrom = ai.frame;
	}
	if (!stands && (EffigyBuildDef(cd) < 0))
		return;
	const bool edge = gEfrOn != was;
	if (!edge && (ai.frame < gEfrLogAt))
		return;
	gEfrLogAt = ai.frame + 30 * SECOND;
	AiLog(Factory::T() + "apex: effigy-rush t=" + ai.teamId
		+ " choice=" + (gEfrOn ? "RUSH" : (was ? "END" : "WORK")) + " why=" + gEfrWhy
		+ " effigy=" + (stands ? (Catalog::Def(gEfyDef).GetName() + "@" + int(gEfyPos.x) + "," + int(gEfyPos.z)) : "-")
		+ " def=" + u.circuitDef.GetName() + " hp=" + int(u.GetHealthPercent() * 100.f)
		+ " effM=" + int(gEfrEffM) + " deathM=" + int(gEfrDeathM)
		+ " stun=" + formatFloat(gEfrStunS, "", 0, 1) + "s rebuild=" + formatFloat(gEfrBuildS, "", 0, 1) + "s"
		+ " lathe=" + formatFloat(gEfrLathe, "", 0, 1)
		+ " tgt=" + EfrKindName(gEfrKind) + "@" + int(gEfrAt.x) + "," + int(gEfrAt.z)
		+ " walk=" + formatFloat(gEfrWalk, "", 0, 1) + "s"
		+ " fire=" + gEfrThemN + " surv=" + ((gEfrThemM >= 1e8f) ? "inf" : formatFloat(gEfrThemM, "", 0, 0) + "s")
		+ " K=" + int(gEfrK) + " E=" + int(gEfrE) + " L=" + int(gEfrL) + " timeM=" + int(gEfrTimeM)
		+ " dgDps=" + int(gEfrDg) + " lives=" + (gEfrLives ? 1 : 0)
		+ " v=" + int(gEfrV) + " cands=" + gEfrCands + " asked=" + gEfrAsked
		+ " rushes=" + gEfrN + " rushSec=" + gEfrSec
		+ ((!gEfrOn && was && (gEfrFrom >= 0)) ? (" secs=" + ((ai.frame - gEfrFrom) / SECOND)) : "")
		+ " lost=" + gEfyLost + " built=" + gEfyBuildN + " moved=" + gEfyMoveN);
}

}  // namespace Market
