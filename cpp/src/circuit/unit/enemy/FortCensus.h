/*
 * FortCensus.h
 *
 * apex: the enemy's fortifications as we know them (seen or remembered statics
 * only), grouped into clusters of mutually covering guns, with the shields,
 * jammers and radars that protect them and the economy they cover. The walk is
 * sliced across frames; a finished walk replaces the published list at once.
 * Also holds the one siege goal the script has chosen (docs/doctrine.md "Siege a
 * fortification on purpose").
 */

#ifndef SRC_CIRCUIT_UNIT_ENEMY_FORTCENSUS_H_
#define SRC_CIRCUIT_UNIT_ENEMY_FORTCENSUS_H_

#include "AIFloat3.h"

#include <vector>

class asIScriptEngine;

namespace circuit {

class CCircuitAI;
class CMilitaryManager;

class CFortCensus {
public:
	struct SGun {
		springai::AIFloat3 pos;
		float reach;  // land range
		float h;      // health
		float d;      // surf threat / sqrt(health): the Lanchester damage term
		float cost;
		int id;
		int fort;     // cluster index, -1 until linked
	};
	enum class PartKind: char {SHIELD = 0, JAMMER, RADAR, ECO};
	struct SPart {
		springai::AIFloat3 pos;
		float r;      // shield / jammer / radar radius; 0 for economy
		float h;      // shield power for a shield
		float cost;
		PartKind kind;
	};
	struct SFort {
		springai::AIFloat3 pos;
		float radius = 0.f;   // farthest gun from the centre
		int gunN = 0;
		float gunH = 0.f;
		float gunD = 0.f;
		float reach = 0.f;    // the longest gun's reach
		int shieldN = 0;
		float shieldH = 0.f;
		int jamN = 0;
		float jamM = 0.f;
		int radarN = 0;
		float metalM = 0.f;   // guns, shields, jammers and radars of this cluster
		float ecoM = 0.f;     // unarmed structures inside its reach
		int key = -1;         // lowest gun id: the same cluster across walks
	};
	// Field order of GetFortVal; script/.../nnsiege.as mirrors it as FV_*.
	enum Field {GUN_N = 0, GUN_H, GUN_D, REACH, RADIUS, SHIELD_N, SHIELD_H, JAM_N, JAM_M,
		RADAR_N, METAL_M, ECO_M, KEY, _FIELDS_};

	struct SSiege {
		bool on = false;
		springai::AIFloat3 pos;
		float radius = 0.f;
		float reach = 0.f;
		int key = -1;
		int fort = -1;        // index in the published list, -1 once it is gone
		int setFrame = -1;
		bool ready = false;   // the script's verdict: the squad holds the strength the guns need
	};

	CFortCensus(CMilitaryManager* mgr);
	~CFortCensus();

	void Step();

	const std::vector<SFort>& GetForts() const { return forts; }
	const std::vector<SGun>& GetGuns() const { return pubGuns; }
	int GetStamp() const { return stamp; }
	// Sum health x sum damage of the published guns reaching p: SquadTask's safeAt measure.
	float GunHDAt(const springai::AIFloat3& p) const;
	float GunReachAt(const springai::AIFloat3& p) const;

	void SetSiege(const springai::AIFloat3& pos, float radius, float reach, int key);
	void ClearSiege();
	void SetSiegeReady(bool ready) { siege.ready = ready; }
	const SSiege& GetSiege() const { return siege; }

	static void RegisterScript(asIScriptEngine* engine);

private:
	void Walk();
	void Link();
	void Build();
	void Publish();
	void MatchSiege();

	CMilitaryManager* manager;
	CCircuitAI* circuit;

	enum class Phase: char {REST = 0, WALK, LINK, BUILD};
	Phase phase = Phase::REST;
	int nextWalk = 0;
	int walkKey = -1;
	int linkAt = 0;
	unsigned buildAt = 0;
	int stamp = -1;

	std::vector<SGun> guns;
	std::vector<SPart> parts;
	std::vector<int> parent;
	std::vector<SFort> building;

	std::vector<SGun> pubGuns;
	std::vector<SFort> forts;
	SSiege siege;
	int logAt = 0;
};

} // namespace circuit

#endif // SRC_CIRCUIT_UNIT_ENEMY_FORTCENSUS_H_
