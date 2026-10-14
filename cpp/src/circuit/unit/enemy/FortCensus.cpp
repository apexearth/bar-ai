/*
 * FortCensus.cpp
 *
 * apex: see FortCensus.h.
 */

#include "unit/enemy/FortCensus.h"
#include "module/MilitaryManager.h"
#include "scheduler/Scheduler.h"
#include "unit/enemy/EnemyUnit.h"
#include "unit/CircuitDef.h"
#include "CircuitAI.h"
#include "util/Utils.h"

#include "angelscript/include/angelscript.h"

#include <algorithm>
#include <cmath>
#include <map>

namespace circuit {

using namespace springai;

// Turrets whose reach covers half the map (LRPC) cannot be stood outside of; SquadTask's ring skips them too.
static constexpr float GUN_REACH_MAX = 2500.f;
static constexpr float GUN_SLACK = 100.f;
static constexpr int WALK_SLICE = 64;
static constexpr int LINK_SLICE = 16;
static constexpr unsigned PART_SLICE = 64;
static constexpr int WALK_EVERY = FRAMES_PER_SEC * 10;

CFortCensus::CFortCensus(CMilitaryManager* mgr)
		: manager(mgr)
		, circuit(mgr->GetCircuit())
{
	const int offset = circuit->GetSkirmishAIId() % 4;
	circuit->GetScheduler()->RunJobEvery(CScheduler::GameJob(&CFortCensus::Step, this), 1, offset, "fortCensus");
}

CFortCensus::~CFortCensus()
{
}

CFortCensus* CMilitaryManager::GetFortCensus()
{
	if (fortCensus == nullptr) {
		fortCensus = std::make_shared<CFortCensus>(this);
	}
	return fortCensus.get();
}

void CFortCensus::Step()
{
	switch (phase) {
		case Phase::REST: {
			if (circuit->GetLastFrame() < nextWalk) {
				return;
			}
			nextWalk = circuit->GetLastFrame() + WALK_EVERY;
			guns.clear();
			parts.clear();
			walkKey = -1;
			phase = Phase::WALK;
			Walk();
		} break;
		case Phase::WALK: {
			Walk();
		} break;
		case Phase::LINK: {
			Link();
		} break;
		case Phase::BUILD: {
			Build();
		} break;
	}
}

void CFortCensus::Walk()
{
	const CCircuitAI::EnemyInfos& enemies = circuit->GetEnemyInfos();
	auto it = enemies.lower_bound(walkKey + 1);
	int n = 0;
	for (; (it != enemies.end()) && (n < WALK_SLICE); ++it, ++n) {
		walkKey = it->first;
		CEnemyInfo* e = it->second;
		if (e->IsHidden() || e->IsBeingBuilt()) {
			continue;
		}
		CCircuitDef* edef = e->GetCircuitDef();
		if ((edef == nullptr) || edef->IsMobile()) {
			continue;
		}
		CCircuitDef* own = circuit->GetCircuitDefSafe(edef->GetId());
		if ((own != nullptr) && own->IsIgnore()) {
			continue;
		}
		const float landR = edef->HasSurfToLand() ? edef->GetMaxRange(CCircuitDef::RangeType::LAND) : 0.f;
		if ((landR > 0.f) && (landR <= GUN_REACH_MAX)) {
			const float h = std::max(edef->GetHealth(), 1.f);
			guns.push_back(SGun{e->GetPos(), landR, h, edef->GetSurfThreat() / std::sqrt(h),
					e->GetCost(), e->GetId(), -1});
			continue;
		}
		if (edef->IsShieldDef() && (edef->GetShieldRadius() > 0.f)) {
			const float sp = (e->GetShieldPower() > 0.f) ? e->GetShieldPower() : edef->GetMaxShield();
			parts.push_back(SPart{e->GetPos(), edef->GetShieldRadius(), sp, e->GetCost(), PartKind::SHIELD});
			continue;
		}
		if (edef->GetMaxRange() > 0.f) {
			continue;  // AA, LRPC: armed, but neither a gun the siege can outrange nor economy
		}
		if (edef->GetJammerRadius() > 0.f) {
			parts.push_back(SPart{e->GetPos(), edef->GetJammerRadius(), 0.f, e->GetCost(), PartKind::JAMMER});
		} else if (edef->GetRadarRadius() > 0.f) {
			parts.push_back(SPart{e->GetPos(), edef->GetRadarRadius(), 0.f, e->GetCost(), PartKind::RADAR});
		} else if (e->GetCost() > 0.f) {
			parts.push_back(SPart{e->GetPos(), 0.f, 0.f, e->GetCost(), PartKind::ECO});
		}
	}
	if (it == enemies.end()) {
		parent.resize(guns.size());
		for (size_t i = 0; i < guns.size(); ++i) {
			parent[i] = (int)i;
		}
		linkAt = 0;
		phase = Phase::LINK;
	}
}

static int FindRoot(std::vector<int>& parent, int i)
{
	while (parent[i] != i) {
		parent[i] = parent[parent[i]];
		i = parent[i];
	}
	return i;
}

// Two guns are one fortification when either covers the other.
void CFortCensus::Link()
{
	const int n = (int)guns.size();
	const int end = std::min(n, linkAt + LINK_SLICE);
	for (int i = linkAt; i < end; ++i) {
		for (int j = i + 1; j < n; ++j) {
			const float r = std::max(guns[i].reach, guns[j].reach);
			if (guns[i].pos.SqDistance2D(guns[j].pos) < SQUARE(r)) {
				const int a = FindRoot(parent, i);
				const int b = FindRoot(parent, j);
				if (a != b) {
					parent[std::max(a, b)] = std::min(a, b);
				}
			}
		}
	}
	linkAt = end;
	if (linkAt < n) {
		return;
	}

	building.clear();
	std::map<int, int> rootFort;
	for (int i = 0; i < n; ++i) {
		const int root = FindRoot(parent, i);
		auto it = rootFort.find(root);
		int f;
		if (it == rootFort.end()) {
			f = (int)building.size();
			rootFort[root] = f;
			building.emplace_back();
			building[f].pos = ZeroVector;
		} else {
			f = it->second;
		}
		SGun& g = guns[i];
		g.fort = f;
		SFort& fort = building[f];
		fort.pos += g.pos * g.h;
		++fort.gunN;
		fort.gunH += g.h;
		fort.gunD += g.d;
		fort.reach = std::max(fort.reach, g.reach);
		fort.metalM += g.cost;
		fort.key = (fort.key < 0) ? g.id : std::min(fort.key, g.id);
	}
	for (SFort& fort : building) {
		fort.pos /= std::max(fort.gunH, 1.f);
	}
	for (const SGun& g : guns) {
		SFort& fort = building[g.fort];
		fort.radius = std::max(fort.radius, std::sqrt(g.pos.SqDistance2D(fort.pos)));
	}
	buildAt = 0;
	phase = Phase::BUILD;
}

// Each shield, jammer, radar and economy building goes to the nearest cluster it serves.
void CFortCensus::Build()
{
	const unsigned end = std::min<unsigned>(parts.size(), buildAt + PART_SLICE);
	for (unsigned i = buildAt; i < end; ++i) {
		const SPart& p = parts[i];
		int best = -1;
		float bestSq = 0.f;
		for (size_t f = 0; f < building.size(); ++f) {
			const SFort& fort = building[f];
			const float reachR = ((p.kind == PartKind::SHIELD) || (p.kind == PartKind::JAMMER))
					? (p.r + fort.radius) : (fort.reach + fort.radius);
			const float sq = p.pos.SqDistance2D(fort.pos);
			if ((sq < SQUARE(reachR)) && ((best < 0) || (sq < bestSq))) {
				best = (int)f;
				bestSq = sq;
			}
		}
		if (best < 0) {
			continue;
		}
		SFort& fort = building[best];
		switch (p.kind) {
			case PartKind::SHIELD: {
				++fort.shieldN;
				fort.shieldH += p.h;
				fort.metalM += p.cost;
			} break;
			case PartKind::JAMMER: {
				++fort.jamN;
				fort.jamM += p.cost;
				fort.metalM += p.cost;
			} break;
			case PartKind::RADAR: {
				++fort.radarN;
				fort.metalM += p.cost;
			} break;
			case PartKind::ECO: {
				fort.ecoM += p.cost;
			} break;
		}
	}
	buildAt = end;
	if (buildAt < parts.size()) {
		return;
	}
	Publish();
	phase = Phase::REST;
}

void CFortCensus::Publish()
{
	forts.swap(building);
	pubGuns.swap(guns);
	building.clear();
	guns.clear();
	parts.clear();
	stamp = circuit->GetLastFrame();
	MatchSiege();

	if (stamp < logAt) {
		return;
	}
	logAt = stamp + FRAMES_PER_SEC * 60;
	std::vector<int> order(forts.size());
	for (size_t i = 0; i < order.size(); ++i) {
		order[i] = (int)i;
	}
	std::sort(order.begin(), order.end(), [this](int a, int b) { return forts[a].metalM > forts[b].metalM; });
	std::string top;
	for (size_t k = 0; (k < order.size()) && (k < 3); ++k) {
		const SFort& f = forts[order[k]];
		top += utils::string_format(" [key=%i at=%i,%i guns=%i hd=%.0f reach=%.0f r=%.0f shield=%i/%.0f jam=%i radar=%i m=%.0f eco=%.0f]",
				f.key, (int)f.pos.x, (int)f.pos.z, f.gunN, f.gunH * f.gunD, f.reach, f.radius,
				f.shieldN, f.shieldH, f.jamN, f.radarN, f.metalM, f.ecoM);
	}
	circuit->LOG("apex: fort-census t=%i forts=%i guns=%i siege=%i fort=%i%s",
			circuit->GetTeamId(), (int)forts.size(), (int)pubGuns.size(),
			siege.on ? siege.key : -1, siege.fort, top.c_str());
}

void CFortCensus::MatchSiege()
{
	if (!siege.on) {
		return;
	}
	int best = -1;
	for (size_t f = 0; f < forts.size(); ++f) {
		if (forts[f].key == siege.key) {
			best = (int)f;
			break;
		}
	}
	if (best < 0) {
		// the key gun died; what remains of the cluster still stands where it stood
		float bestSq = 0.f;
		for (size_t f = 0; f < forts.size(); ++f) {
			const float sq = forts[f].pos.SqDistance2D(siege.pos);
			if ((sq < SQUARE(siege.radius + forts[f].radius + GUN_SLACK)) && ((best < 0) || (sq < bestSq))) {
				best = (int)f;
				bestSq = sq;
			}
		}
	}
	siege.fort = best;
	if (best >= 0) {
		const SFort& f = forts[best];
		siege.pos = f.pos;
		siege.radius = f.radius;
		siege.reach = f.reach;
		siege.key = f.key;
	}
}

float CFortCensus::GunHDAt(const AIFloat3& p) const
{
	float gh = 0.f, gd = 0.f;
	for (const SGun& g : pubGuns) {
		if (p.SqDistance2D(g.pos) < SQUARE(g.reach)) {
			gh += g.h;
			gd += g.d;
		}
	}
	return gh * gd;
}

float CFortCensus::GunReachAt(const AIFloat3& p) const
{
	float r = 0.f;
	for (const SGun& g : pubGuns) {
		if (p.SqDistance2D(g.pos) < SQUARE(g.reach)) {
			r = std::max(r, g.reach);
		}
	}
	return r;
}

void CFortCensus::SetSiege(const AIFloat3& pos, float radius, float reach, int key)
{
	siege.on = true;
	siege.pos = pos;
	siege.radius = radius;
	siege.reach = reach;
	siege.key = key;
	siege.setFrame = circuit->GetLastFrame();
	MatchSiege();
	circuit->GetAllyTeam()->ClaimSiege(key, circuit->GetTeamId());
}

void CFortCensus::ClearSiege()
{
	siege = SSiege();
	circuit->GetAllyTeam()->ReleaseSiege(circuit->GetTeamId());
}

static int Fort_Count(CMilitaryManager* mgr)
{
	return (int)mgr->GetFortCensus()->GetForts().size();
}

static int Fort_Stamp(CMilitaryManager* mgr)
{
	return mgr->GetFortCensus()->GetStamp();
}

static AIFloat3 Fort_Pos(CMilitaryManager* mgr, int i)
{
	const std::vector<CFortCensus::SFort>& forts = mgr->GetFortCensus()->GetForts();
	if ((i < 0) || (i >= (int)forts.size())) {
		return AIFloat3(-RgtVector);
	}
	return forts[i].pos;
}

// The ally sieging fort i, -1 when none or it is ours.
static int Fort_AllyClaim(CMilitaryManager* mgr, int i)
{
	const std::vector<CFortCensus::SFort>& forts = mgr->GetFortCensus()->GetForts();
	if ((i < 0) || (i >= (int)forts.size())) {
		return -1;
	}
	CCircuitAI* circuit = mgr->GetCircuit();
	const int team = circuit->GetAllyTeam()->SiegeClaimant(forts[i].key);
	return (team == circuit->GetTeamId()) ? -1 : team;
}

static float Fort_Val(CMilitaryManager* mgr, int i, int field)
{
	const std::vector<CFortCensus::SFort>& forts = mgr->GetFortCensus()->GetForts();
	if ((i < 0) || (i >= (int)forts.size())) {
		return 0.f;
	}
	const CFortCensus::SFort& f = forts[i];
	switch (field) {
		case CFortCensus::GUN_N:    return (float)f.gunN;
		case CFortCensus::GUN_H:    return f.gunH;
		case CFortCensus::GUN_D:    return f.gunD;
		case CFortCensus::REACH:    return f.reach;
		case CFortCensus::RADIUS:   return f.radius;
		case CFortCensus::SHIELD_N: return (float)f.shieldN;
		case CFortCensus::SHIELD_H: return f.shieldH;
		case CFortCensus::JAM_N:    return (float)f.jamN;
		case CFortCensus::JAM_M:    return f.jamM;
		case CFortCensus::RADAR_N:  return (float)f.radarN;
		case CFortCensus::METAL_M:  return f.metalM;
		case CFortCensus::ECO_M:    return f.ecoM;
		case CFortCensus::KEY:      return (float)f.key;
		default: return 0.f;
	}
}

static void Fort_SetSiege(CMilitaryManager* mgr, const AIFloat3& pos, float radius, float reach, int key)
{
	mgr->GetFortCensus()->SetSiege(pos, radius, reach, key);
}

static void Fort_ClearSiege(CMilitaryManager* mgr)
{
	mgr->GetFortCensus()->ClearSiege();
}

static void Fort_SetSiegeReady(CMilitaryManager* mgr, bool ready)
{
	mgr->GetFortCensus()->SetSiegeReady(ready);
}

static int Fort_SiegeFort(CMilitaryManager* mgr)
{
	const CFortCensus::SSiege& s = mgr->GetFortCensus()->GetSiege();
	return s.on ? s.fort : -1;
}

static float Fort_GunHDAt(CMilitaryManager* mgr, const AIFloat3& pos)
{
	return mgr->GetFortCensus()->GunHDAt(pos);
}

void CFortCensus::RegisterScript(asIScriptEngine* engine)
{
	int r = engine->RegisterObjectMethod("CMilitaryManager", "int GetFortCount()", asFUNCTION(Fort_Count), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CMilitaryManager", "int GetFortStamp()", asFUNCTION(Fort_Stamp), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CMilitaryManager", "AIFloat3 GetFortPos(int)", asFUNCTION(Fort_Pos), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CMilitaryManager", "float GetFortVal(int, int)", asFUNCTION(Fort_Val), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CMilitaryManager", "int GetFortAllyClaim(int)", asFUNCTION(Fort_AllyClaim), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CMilitaryManager", "void SetSiege(const AIFloat3& in, float, float, int)", asFUNCTION(Fort_SetSiege), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CMilitaryManager", "void ClearSiege()", asFUNCTION(Fort_ClearSiege), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CMilitaryManager", "void SetSiegeReady(bool)", asFUNCTION(Fort_SetSiegeReady), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CMilitaryManager", "int GetSiegeFort()", asFUNCTION(Fort_SiegeFort), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
	r = engine->RegisterObjectMethod("CMilitaryManager", "float GetGunHDAt(const AIFloat3& in)", asFUNCTION(Fort_GunHDAt), asCALL_CDECL_OBJFIRST); ASSERT(r >= 0);
}

} // namespace circuit
