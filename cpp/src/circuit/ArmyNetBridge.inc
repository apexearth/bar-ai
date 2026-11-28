/*
 * apex: the army model bridge inside the AI (AI option "armynet", his 11-23: "set it up so my next game online could be
 * with the armynet"). The dev gadget game-patches/gadgets/dev_armynet.lua did this from synced Lua, which a hosted
 * multiplayer game cannot load; here the AI does it host-side:
 *   - armynet-t<team>/armynet_static.txt once: map size, unit types (id, name, class; tools/armynet/serve.py fills the
 *     stats from runtime/armynet/defs.json by the recorder's own formula), ally teams, teams, holder, metal spots,
 *     heights -- the gadget's line format;
 *   - armynet_state.txt every 10 frames: every unit this side sees (own and allied in full, enemies in sight or on
 *     radar as the AI is told of them -- no hidden information), with this side's sight bits, and the hits taken;
 *   - armynet_orders.txt from serve.py: orders for the units the model holds;
 *   - the model's units (mobile, armed or a sensor, not the commander, a builder or a scout) are taken off the AI's
 *     own control when they finish, as the gadget's disableAiControl mark did.
 * Orders go out as ordinary unit commands (netted, desync-safe); the files are host-local.
 */

// included at the end of CircuitAI.cpp (a new .cpp is not picked up without a CMake reconfigure)
#include "CircuitAI.h"
#include "resource/MetalManager.h"
#include "terrain/TerrainManager.h"
#include "unit/CircuitUnit.h"
#include "unit/ally/AllyUnit.h"
#include "unit/ally/AllyTeam.h"
#include "unit/enemy/EnemyUnit.h"
#include "task/UnitTask.h"
#include "util/Utils.h"

#include "Game.h"
#include "Unit.h"
#include "UnitDef.h"
#include "WeaponMount.h"
#include "Command.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <set>
#include <sstream>
#include <vector>
#ifdef _WIN32
#include <process.h>
#else
#include <spawn.h>
extern char** environ;
#endif

namespace circuit {

using namespace springai;

static const char* ArmyNetClass(CCircuitDef* d)
{
	// the gadget's cls(): com, static, builder, jammer, radar (unarmed), air, army (armed), other
	if (d->IsRoleComm()) {
		return "com";
	}
	if (!d->IsMobile()) {
		return "static";
	}
	UnitDef* ud = d->GetDef();
	if (d->IsBuilder() || ((ud != nullptr) && (ud->GetBuildSpeed() > 0.f))) {
		return "builder";
	}
	int weapons = 0;
	if (ud != nullptr) {
		std::vector<WeaponMount*> mounts = ud->GetWeaponMounts();
		weapons = (int)mounts.size();
		for (WeaponMount* m : mounts) {
			delete m;
		}
	}
	if (d->GetJammerRadius() > 0.f) {
		return "jammer";
	}
	if ((d->GetRadarRadius() > 0.f) && (weapons == 0)) {
		return "radar";
	}
	if (d->IsAbleToFly()) {
		return "air";
	}
	if (weapons > 0) {
		return "army";
	}
	return "other";
}

bool CCircuitAI::ArmyNetFocus(CCircuitUnit* unit) const
{
	// the gadget's isFocus(): mobile, not a commander, a builder or one of the AI's own scouts; armed or a sensor
	CCircuitDef* d = unit->GetCircuitDef();
	if ((d == nullptr) || !d->IsMobile() || d->IsRoleComm() || d->IsBuilder() || d->IsRoleScout()) {
		return false;
	}
	// the same builder rule as ArmyNetClass: a unit with build speed is a "builder" the model does not command
	UnitDef* ud = d->GetDef();
	if ((ud != nullptr) && (ud->GetBuildSpeed() > 0.f)) {
		return false;
	}
	return (d->GetRawDps() > 0.f) || (d->GetRadarRadius() > 0.f) || (d->GetJammerRadius() > 0.f);
}

void CCircuitAI::ArmyNetUpdate(int frame)
{
	if (armyNetDir.empty()) {
		return;
	}
	if (!armyNetStaticDone) {
		armyNetStaticDone = true;
		std::string dir = armyNetDir;
		if (!dir.empty() && (dir.back() != '/') && (dir.back() != '\\')) {
			dir += "/";
		}
		dir += "armynet-t" + std::to_string(teamId) + "/";
		std::error_code ec;
		std::filesystem::create_directories(dir, ec);
		if (ec) {
			LOG("apex: armynet t=%i cannot create %s", teamId, dir.c_str());
			armyNetDir.clear();
			return;
		}
		armyNetDir = dir;
		// the folder outlives the game: a previous game's orders (a later frame) would block this one's
		std::filesystem::remove(armyNetDir + "armynet_orders.txt", ec);
		std::filesystem::remove(armyNetDir + "armynet_state.txt", ec);
		for (int t = 0; t < game->GetTeams(); ++t) {
			if ((t != teamId) && (game->GetTeamAllyTeam(t) != allyTeamId)) {
				armyNetEnemyTeam = t;
				break;
			}
		}
		ArmyNetWriteStatic();
		LOG("apex: armynet t=%i bridge on dir=%s", teamId, armyNetDir.c_str());
		ArmyNetLaunch(dir.substr(0, dir.size() - std::string("armynet-t" + std::to_string(teamId) + "/").size()));
	}
	if (frame % FRAMES_PER_SEC == 7) {
		CScheduler::STimed timed(scheduler.get(), "anet.hold");
		ArmyNetHold();
	}
	// a bot no server answers writes its state every 10 s, enough for one to find it; served (an answer inside the
	// same 20 s that holds the army), every 10 frames. With the option on for every seat, only the served one pays.
	const bool served = (armyNetLastOrders >= 0) && (frame - armyNetLastOrders <= FRAMES_PER_SEC * 20);
	if ((frame % 10 == 0) && (served || (frame % (FRAMES_PER_SEC * 10) == 0))) {
		CScheduler::STimed timed(scheduler.get(), "anet.write");
		ArmyNetWriteState(frame);
	}
	if (frame % 10 == 5) {
		CScheduler::STimed timed(scheduler.get(), "anet.read");
		ArmyNetReadOrders();
	}
	if ((frame % (FRAMES_PER_SEC * 60) == 0) && (frame > 0)) {
		// who the model commands, by kind: held air / all armed air of ours, and focus units it does not hold
		int heldAir = 0, air = 0, focusFree = 0;
		for (auto& kv : teamUnits) {
			CCircuitUnit* unit = kv.second;
			if ((unit == nullptr) || unit->IsDead() || (unit->GetCircuitDef() == nullptr)) {
				continue;
			}
			const bool held = armyNetHeld.find(kv.first) != armyNetHeld.end();
			const bool focus = ArmyNetFocus(unit);
			if (focus && unit->GetCircuitDef()->IsAbleToFly()) {
				++air;
				heldAir += held ? 1 : 0;
			}
			focusFree += (focus && !held) ? 1 : 0;
		}
		LOG("apex: armynet t=%i f=%i held=%i applied=%i lastOrders=%i released=%i heldAir=%i/%i focusNotHeld=%i", teamId,
			frame, (int)armyNetHeld.size(), armyNetApplied, armyNetLastOrders, armyNetReleased, heldAir, air, focusFree);
	}
}

// his 11-24: "can the 'server' auto launch through the DLL". armynet-launch.txt, in the version folder or the Apex folder
// above it, holds the model server's command, one argument per line (python, serve.py, --model, ...); each bot with the
// option starts its own server on its own folder. No file, no launch: the option then waits for an outside server and
// the bot keeps its army meanwhile (ArmyNetHold).
void CCircuitAI::ArmyNetLaunch(const std::string& verDir)
{
	std::vector<std::string> args;
	std::filesystem::path base;
	for (const std::string& at : {verDir + "armynet-launch.txt",
	                              std::filesystem::path(verDir).parent_path().parent_path().string() + "/armynet-launch.txt"}) {
		base = std::filesystem::path(at).parent_path();
		std::ifstream fh(at);
		std::string ln;
		while (fh && std::getline(fh, ln)) {
			while (!ln.empty() && ((ln.back() == '\r') || (ln.back() == ' '))) {
				ln.pop_back();
			}
			if (!ln.empty() && (ln[0] != '#')) {
				args.push_back(ln);
			}
		}
		if (!args.empty()) {
			break;
		}
	}
	if (args.empty()) {
		return;
	}
	// the packaged server's file names its parts relative to its own folder (tools/armynet/package_serve.py)
	for (std::string& s : args) {
		std::error_code ec;
		const std::filesystem::path p(s);
		if ((s[0] != '-') && p.is_relative() && std::filesystem::exists(base / p, ec)) {
			s = (base / p).lexically_normal().string();
		}
	}
	args.insert(args.end(), {"--dir", armyNetDir, "--log", armyNetDir + "serve.log"});
#ifdef _WIN32
	std::vector<std::string> quoted;
	for (const std::string& s : args) {
		quoted.push_back((s.find(' ') != std::string::npos) ? ("\"" + s + "\"") : s);
	}
	std::vector<const char*> argv;
	for (const std::string& s : quoted) {
		argv.push_back(s.c_str());
	}
	argv.push_back(nullptr);
	const intptr_t rc = _spawnv(_P_DETACH, args[0].c_str(), argv.data());
	const bool ok = (rc != -1);
#else
	std::vector<char*> argv;
	for (std::string& s : args) {
		argv.push_back(&s[0]);
	}
	argv.push_back(nullptr);
	pid_t pid;
	const bool ok = (posix_spawnp(&pid, args[0].c_str(), nullptr, nullptr, argv.data(), environ) == 0);
#endif
	LOG("apex: armynet t=%i launch %s: %s", teamId, ok ? "started" : "FAILED", args[0].c_str());
}

void CCircuitAI::ArmyNetWriteStatic()
{
	std::ofstream fh(armyNetDir + "armynet_static.txt", std::ios::out | std::ios::trunc);
	if (!fh) {
		LOG("apex: armynet t=%i cannot write static", teamId);
		return;
	}
	const int mapX = CTerrainManager::GetTerrainWidth();
	const int mapZ = CTerrainManager::GetTerrainHeight();
	fh << "V 2 " << mapX << " " << mapZ << "\n";
	for (CCircuitDef& d : GetCircuitDefs()) {
		UnitDef* ud = d.GetDef();
		if (ud == nullptr) {
			continue;
		}
		fh << "D " << d.GetId() << " " << ud->GetName() << " " << ArmyNetClass(&d) << "\n";
	}
	const int nTeams = game->GetTeams();
	std::set<int> allies;
	for (int t = 0; t < nTeams; ++t) {
		allies.insert(game->GetTeamAllyTeam(t));
	}
	fh << "A";
	for (int a : allies) {
		fh << " " << a;
	}
	fh << "\n";
	for (int t = 0; t < nTeams; ++t) {
		fh << "T " << t << " " << game->GetTeamAllyTeam(t) << " " << ((t == teamId) ? "true" : "false") << "\n";
	}
	fh << "Q " << teamId << " " << teamId << "\n";
	int i = 0;
	for (const auto& spot : metalManager->GetSpots()) {
		++i;
		fh << "S " << i << " " << (int)std::lround(spot.position.x) << " " << (int)std::lround(spot.position.z) << "\n";
	}
	const int step = 64;
	fh << "H " << step;
	for (int z = step / 2; z <= mapZ; z += step) {
		for (int x = step / 2; x <= mapX; x += step) {
			fh << " " << (int)std::lround(GetElevationAt(AIFloat3(x, 0.f, z)));
		}
	}
	fh << "\n";
}

void CCircuitAI::ArmyNetWriteState(int frame)
{
	// this side's bits in the sight mask: two bits per ally team, in ally-id order (the gadget's sightMask)
	int k = 0;
	{
		const int nTeams = game->GetTeams();
		std::set<int> allies;
		for (int t = 0; t < nTeams; ++t) {
			allies.insert(game->GetTeamAllyTeam(t));
		}
		for (int a : allies) {
			if (a == allyTeamId) {
				break;
			}
			++k;
		}
	}
	const long long shift = 1LL << (2 * k);
	std::ostringstream out;
	out << "F " << frame << "\n";
	char line[256];
	std::map<ICoreUnit::Id, float> hpNow;
	// BUILDINGS EVERY 10 S, as the replay recorder writes them (the training data): the model's memory keeps them in
	// between. Every building of the whole ally team every 10 frames, five engine calls each, was most of the served
	// seat's 2.6 s a game-minute (his 11-25 8v8, 4.2 s vs 1.6 for a plain seat). Our own still read their health, for
	// the hits they take.
	const bool bldStep = (frame % (FRAMES_PER_SEC * 10) == 0);
	for (auto& kv : allyTeam->GetFriendlyUnits()) {
		CAllyUnit* au = kv.second;
		CCircuitDef* d = (au != nullptr) ? au->GetCircuitDef() : nullptr;
		Unit* u = (au != nullptr) ? au->GetUnit() : nullptr;
		if ((d == nullptr) || (u == nullptr)) {
			continue;
		}
		if (!bldStep && !d->IsMobile() && !u->IsBeingBuilt()) {
			if (u->GetTeam() == teamId) {
				hpNow[au->GetId()] = u->GetHealth();
			}
			continue;
		}
		const AIFloat3 pos = au->GetPos(frame);
		const AIFloat3 vel = u->GetVel();
		const float mh = std::max(u->GetMaxHealth(), 1.f);
		const float h = u->GetHealth();
		const float bp = u->IsBeingBuilt() ? u->GetBuildProgress() : 1.f;
		const int team = u->GetTeam();
		int c = -1;
		float tx = -1.f, tz = -1.f;
		if (team == teamId) {
			hpNow[au->GetId()] = h;
			if (d->IsMobile()) {
				std::vector<springai::Command*> cmds = u->GetCurrentCommands();
				if (!cmds.empty()) {
					c = cmds[0]->GetId();
					std::vector<float> p = cmds[0]->GetParams();
					if (p.size() >= 3) {
						tx = p[0];
						tz = p[2];
					} else if (p.size() == 1) {
						CEnemyInfo* en = GetEnemyInfo((ICoreUnit::Id)p[0]);
						if (en != nullptr) {
							tx = en->GetPos().x;
							tz = en->GetPos().z;
						}
					}
				}
				for (springai::Command* cmd : cmds) {
					delete cmd;
				}
			}
		}
		std::snprintf(line, sizeof(line), "U %d %d %d %d %.0f %.0f %.1f %.1f %.2f %.2f %lld %d %.0f %.0f\n", frame,
			au->GetId(), d->GetId(), team, pos.x, pos.z, vel.x * 30.f, vel.z * 30.f, h / mh, bp, 3LL * shift, c, tx, tz);
		out << line;
	}
	for (auto& kv : GetEnemyInfos()) {
		CEnemyInfo* e = kv.second;
		if (e == nullptr) {
			continue;
		}
		CCircuitDef* d = e->GetCircuitDef();
		if (!bldStep && (d != nullptr) && !d->IsMobile() && !e->IsBeingBuilt()) {
			continue;
		}
		const AIFloat3& pos = e->GetPos();
		const AIFloat3& vel = e->GetVel();
		const bool los = e->IsInLOS();
		// out of sight the engine names no team (-1) and data.py drops such a unit as no enemy: its team when last in
		// sight, or an enemy team for a blip never seen (a player knows a blip is hostile)
		int team = -1;
		Unit* u = e->GetUnit();
		if ((u != nullptr) && los) {
			team = u->GetTeam();
			if (team >= 0) {
				armyNetFoeTeam[e->GetId()] = team;
			}
		}
		if (team < 0) {
			auto it = armyNetFoeTeam.find(e->GetId());
			team = (it != armyNetFoeTeam.end()) ? it->second : armyNetEnemyTeam;
		}
		const bool radar = e->IsInRadarOrLOS() && !los;   // CEnemyInfo exposes "radar or sight"; radar here means radar without sight
		if (!los && !radar) {
			continue;  // a remembered ghost: the model keeps its own memory of what it saw
		}
		const long long bits = los ? 1LL : 2LL;   // the recorder's bits for this side: 1 in sight, 2 on radar only
		const float hp = ((d != nullptr) && los) ? e->GetHealth() / std::max(d->GetHealth(), 1.f) : 1.f;
		std::snprintf(line, sizeof(line), "U %d %d %d %d %.0f %.0f %.1f %.1f %.2f %.2f %lld %d %.0f %.0f\n", frame,
			e->GetId(), (d != nullptr) ? d->GetId() : 0, team, pos.x, pos.z, vel.x * 30.f, vel.z * 30.f, hp,
			(los && e->IsBeingBuilt()) ? 0.5f : 1.f,
			bits * shift, -1, -1.f, -1.f);
		out << line;
	}
	// the hits our units took since the last write: health lost, credited to the last attacker the engine named
	for (auto& kv : armyNetHitBy) {
		auto was = armyNetHp.find(kv.first);
		auto now = hpNow.find(kv.first);
		if ((was == armyNetHp.end()) || (now == hpNow.end())) {
			continue;
		}
		const float dmg = was->second - now->second;
		if (dmg > 0.f) {
			std::snprintf(line, sizeof(line), "X %d %d %d %.0f\n", frame, kv.second, kv.first, dmg);
			out << line;
		}
	}
	armyNetHitBy.clear();
	armyNetHp.swap(hpNow);
	out << "E " << frame << "\n";
	std::ofstream fh(armyNetDir + "armynet_state.txt", std::ios::out | std::ios::trunc);
	if (fh) {
		fh << out.str();
	}
}

void CCircuitAI::ArmyNetDamaged(CCircuitUnit* unit, ICoreUnit::Id attackerId)
{
	if (unit != nullptr) {
		armyNetHitBy[unit->GetId()] = attackerId;
	}
}

void CCircuitAI::ArmyNetHold()
{
	// NO MODEL, NO HOLD: the option on with serve.py not running (or stopped) would leave the army standing where it
	// was made. Units are held only while new orders arrive; after 20 s without, every held unit goes back to the AI.
	const bool modelLive = (armyNetOrdersAt >= 0) && (lastFrame - armyNetOrdersAt <= FRAMES_PER_SEC * 20);
	if (!modelLive) {
		if (!armyNetHeld.empty()) {
			int back = 0;
			for (ICoreUnit::Id id : armyNetHeld) {
				CCircuitUnit* unit = GetTeamUnit(id);
				if ((unit != nullptr) && UnitControl(unit, true)) {
					++back;
				}
			}
			armyNetHeld.clear();
			LOG("apex: armynet t=%i f=%i no orders for 20 s: %i units back to the AI", teamId, lastFrame, back);
		}
		return;
	}
	// a held id whose unit is gone (dead, given away): drop it, so a reused id is not taken as held
	for (auto it = armyNetHeld.begin(); it != armyNetHeld.end(); ) {
		CCircuitUnit* unit = GetTeamUnit(*it);
		it = ((unit == nullptr) || unit->IsDead()) ? armyNetHeld.erase(it) : std::next(it);
	}
	for (auto it = armyNetReleasedUntil.begin(); it != armyNetReleasedUntil.end(); ) {
		it = (it->second <= lastFrame) ? armyNetReleasedUntil.erase(it) : std::next(it);
	}
	for (auto& kv : teamUnits) {
		CCircuitUnit* unit = kv.second;
		if ((unit == nullptr) || unit->IsDead() || (armyNetHeld.find(kv.first) != armyNetHeld.end()) || !ArmyNetFocus(unit)
			|| (armyNetReleasedUntil.find(kv.first) != armyNetReleasedUntil.end()))
		{
			continue;
		}
		if (unit->GetUnit()->IsBeingBuilt()) {
			continue;
		}
		if ((unit->GetTask() != nullptr) && (unit->GetTask()->GetType() != IUnitTask::Type::PLAYER)) {
			UnitControl(unit, false);
		}
		// the model commands it now: clear a set target our fight logic left on (his 11-25)
		unit->GetUnit()->ExecuteCustomCommand(CMD_UNIT_CANCEL_TARGET, {});
		armyNetHeld.insert(kv.first);
	}
}

void CCircuitAI::ArmyNetReadOrders()
{
	// the server writes about once a decision; most reads would find the file unchanged
	std::error_code ec;
	const std::string path = armyNetDir + "armynet_orders.txt";
	const auto stamp = std::filesystem::last_write_time(path, ec);
	if (ec) {
		return;
	}
	const uintmax_t size = std::filesystem::file_size(path, ec);
	const long long stampN = (long long)stamp.time_since_epoch().count();
	if (!ec && (stampN == armyNetOrdersStamp) && ((long long)size == armyNetOrdersSize)) {
		return;
	}
	std::ifstream fh(path);
	if (!fh) {
		return;
	}
	std::string head;
	if (!std::getline(fh, head) || (head.rfind("O ", 0) != 0)) {
		return;
	}
	const int frame = std::atoi(head.c_str() + 2);
	if (frame <= armyNetLastOrders) {   // already applied
		armyNetOrdersStamp = stampN;
		armyNetOrdersSize = (long long)size;
		return;
	}
	if (frame > lastFrame + FRAMES_PER_SEC) {   // from another game
		return;
	}
	std::vector<std::string> lines;
	std::string ln;
	bool complete = false;
	while (std::getline(fh, ln)) {
		if (!ln.empty() && (ln.back() == '\r')) {
			ln.pop_back();
		}
		if (ln == "E") {
			complete = true;
			break;
		}
		if (!ln.empty()) {
			lines.push_back(ln);
		}
	}
	if (!complete) {
		return;  // serve.py is still writing it
	}
	armyNetLastOrders = frame;
	armyNetOrdersAt = lastFrame;
	armyNetOrdersStamp = stampN;
	armyNetOrdersSize = (long long)size;
	std::vector<CCircuitUnit*> released;
	for (const std::string& item : lines) {
		std::vector<float> f;
		std::stringstream ss(item);
		std::string tok;
		while (std::getline(ss, tok, ',')) {
			f.push_back((float)std::atof(tok.c_str()));
		}
		if (f.size() < 2) {
			continue;
		}
		const ICoreUnit::Id uid = (ICoreUnit::Id)f[0];
		const int cmd = (int)f[1];
		if ((cmd == -1) && (f.size() == 3)) {
			// serve --hybrid: a unit in contact goes to the AI's own fight logic for f[2] frames, renewed while in contact
			armyNetReleasedUntil[uid] = lastFrame + (int)f[2];
			if (armyNetHeld.erase(uid) > 0) {
				CCircuitUnit* unit = GetTeamUnit(uid);
				if ((unit != nullptr) && !unit->IsDead()) {
					released.push_back(unit);
					++armyNetReleased;
				}
			}
			continue;
		}
		if (armyNetHeld.find(uid) == armyNetHeld.end()) {
			continue;
		}
		CCircuitUnit* unit = GetTeamUnit(uid);
		if (unit == nullptr) {
			continue;
		}
		++armyNetApplied;
		if (cmd == 0) {
			TRY_UNIT(this, unit,
				unit->CmdStop();
			)
		} else if ((cmd == 20) && (f.size() == 3)) {
			CEnemyInfo* enemy = GetEnemyInfo((ICoreUnit::Id)f[2]);
			if (enemy != nullptr) {
				TRY_UNIT(this, unit,
					unit->CmdAttack(enemy);
				)
			}
		} else if (f.size() >= 4) {
			AIFloat3 pos(f[2], 0.f, f[3]);
			CTerrainManager::CorrectPosition(pos);
			pos.y = GetElevationAt(pos);
			TRY_UNIT(this, unit,
				if (cmd == 16) {
					unit->CmdFightTo(pos);
				} else if (cmd == 15) {
					unit->CmdPatrolTo(pos);
				} else {
					unit->CmdMoveTo(pos);
				}
			)
		}
	}
	ArmyNetFightHere(released);
}

// serve --hybrid: units handed back mid-fight fight where they stand, as squads of the ones within 800 of each other.
// Returned as fresh units (the massing pool) they walked home: Mac 11-24, -941 a unit-minute toward home, damage 264 a
// unit-minute in contact against stock's 631.
void CCircuitAI::ArmyNetFightHere(std::vector<CCircuitUnit*>& units)
{
	CMilitaryManager* mil = GetMilitaryManager();
	std::vector<bool> done(units.size(), false);
	for (size_t i = 0; i < units.size(); ++i) {
		if (done[i] || (units[i]->GetTask() == nullptr) || (units[i]->GetTask()->GetType() != IUnitTask::Type::PLAYER)) {
			continue;
		}
		IFighterTask* task = mil->Enqueue(TaskF::Common(IFighterTask::FightType::ATTACK));
		const AIFloat3 p = units[i]->GetPos(lastFrame);
		for (size_t j = i; j < units.size(); ++j) {
			if (done[j] || (units[j]->GetTask() == nullptr) || (units[j]->GetTask()->GetType() != IUnitTask::Type::PLAYER)
				|| (units[j]->GetPos(lastFrame).SqDistance2D(p) > SQUARE(800.f)))
			{
				continue;
			}
			done[j] = true;
			mil->AssignTask(units[j], task);
			if (units[j]->GetTask()->GetType() == IUnitTask::Type::PLAYER) {
				UnitControl(units[j], true);  // the join refused: never leave it on the model's hold
			}
		}
	}
}

}  // namespace circuit
