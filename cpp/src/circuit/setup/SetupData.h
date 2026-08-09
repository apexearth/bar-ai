/*
 * SetupData.h
 *
 *  Created on: Aug 10, 2014
 *      Author: rlcevg
 */

#ifndef SRC_CIRCUIT_STATIC_SETUPDATA_H_
#define SRC_CIRCUIT_STATIC_SETUPDATA_H_

#include "util/math/Region.h"

#include "Game/GameSetup.h"

#include <map>
#include <vector>

namespace springai {
	class Game;
}

namespace circuit {

class CCircuitAI;
class CAllyTeam;
class CMap;

class CSetupData {
public:
	using ModOptions = std::unordered_map<std::string, std::string>;
	using BoxMap = std::map<int, utils::CRegion>;  // <start_box_id, box>
	using AllyMap = std::vector<CAllyTeam*>;

	CSetupData();
	~CSetupData();
	void ParseSetupScript(CCircuitAI* circuit, const char* setupScript);

	bool IsInitialized() const { return isInitialized; }
	bool CanChooseStartPos() const { return false/*startPosType == CGameSetup::StartPos_ChooseInGame*/; }

	CAllyTeam* GetAllyTeam(int allyTeamId) { return allyTeams[allyTeamId]; }

	// game->GetMyAllyTeam() answers 0 for every AI: aiGetTeamResource()'s gate,
	// AI_TEAM_IDS in rts/ExternalAI/SSkirmishAICallbackImpl.cpp, is declared
	// {{-1}} and never assigned. The start script carries the real assignment
	// and ParseSetupScript already read it, so look our own teamId up instead.
	// Defined in the .cpp: CAllyTeam is only forward-declared here.
	int FindAllyTeamOf(int teamId) const;
	const utils::CRegion& GetStartBox(int boxId) { return boxes[boxId]; }

	const ModOptions& GetModOptions() const { return modoptions; }

private:
	void Init(AllyMap&& ats, BoxMap&& bm,
			  CGameSetup::StartPosType spt = CGameSetup::StartPosType::StartPos_ChooseInGame);
	BoxMap ReadStartBoxes(const std::string& script, CMap* map, springai::Game* game);

	bool isInitialized;
	CGameSetup::StartPosType startPosType;
	AllyMap allyTeams;  // owner
	BoxMap boxes;

	ModOptions modoptions;
};

} // namespace circuit

#endif // SRC_CIRCUIT_STATIC_SETUPDATA_H_
