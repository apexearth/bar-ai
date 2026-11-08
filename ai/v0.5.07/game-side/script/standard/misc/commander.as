#include "../manager/factory.as"


namespace Commander {

string armcom("armcom");
string corcom("corcom");
string legcom("legcom");

//------------------------------------------------------------------------------
// Telemetry only -- no lever here. `aiBuilderMgr.dangerHysteresis` exists in
// vendor/circuitai but not on the registered CBuilderManager in the tree we
// actually deploy (vendor/engine/AI/Skirmish/BARb); its surface is only
// DefaultMakeTask, Enqueue, EnqueueRetreat, GetWorkerCount. Assigning it is a
// compile error that disables the whole AI silently. Check bindings against
// vendor/engine, never vendor/circuitai. Scaling commander caution needs a
// commander.json hide.threat change or a new C++ binding; this just logs the
// input.

// Cost-based, not threat-based: defThreat is cost-independent
// (sqrt(dps) * dmg^0.25 * sqrt(hp) / 128), so a metal threshold reads "one
// enemy T2 heavy is on the field" where a threat threshold does not fire until
// several are alive at once. GetEnemyCost(RT::HEAVY) is a standing live count
// (CEnemyManager adds on first LOS, subtracts on death), not an LOS snapshot.
// 900 sits at roughly the cheapest T2 "heavy"-role unit cost, below which a
// commander (2700 metal, 3700 hp) starts losing 1:1 fights.
const float COM_HEAVY_METAL = 900.f;

bool gCautious = false;
int  gNextLog  = 0;

void UpdateCaution()
{
	const float heavy = aiEnemyMgr.GetEnemyCost(RT::HEAVY);
	const bool careful = (heavy >= COM_HEAVY_METAL);
	if (careful != gCautious) {
		gCautious = careful;
		AiLog(Factory::T() + "apex: commander " + (careful ? "CAUTIOUS" : "loose")
			+ " frame=" + ai.frame
			+ " enemyHeavy=" + formatFloat(heavy, "", 0, 0));
	}

	// Heartbeat, since a transition-only log can't distinguish "never fired"
	// from "input is dead". workers is logged because the C++ gate also
	// requires GetWorkerCount() > 2 before any commander caution applies.
	if (ai.frame >= gNextLog) {
		gNextLog = ai.frame + 2 * MINUTE;
		AiLog(Factory::T() + "apex: comm heavy=" + formatFloat(heavy, "", 0, 0)
			+ "/" + formatFloat(COM_HEAVY_METAL, "", 0, 0)
			+ " mobileThr=" + formatFloat(aiEnemyMgr.mobileThreat, "", 0, 1)
			+ " workers=" + int(aiBuilderMgr.GetWorkerCount())
			+ (gCautious ? " CAUTIOUS" : " loose"));
	}
}

}


namespace Opener {

class SO {  // SOrder
	SO(Type r, uint c = 1) {
		role = r;
		count = c;
	}
	SO() {}
	Type role;
	uint count;
}

class SQueue {
	SQueue(float w, array<SO>& in o) {
		weight = w;
		orders = o;
	}
	SQueue() {}
	float weight;
	array<SO> orders;
}

class SOpener {
	SOpener(dictionary f, array<SO>& in d) {
		factory = f;
		def = d;
	}
	dictionary factory;
	array<SO> def;
}

SOpener@ GetOpenInfo()
{
	return SOpener({
		{Factory::armlab, array<SQueue> = {
			SQueue(0.9f, {SO(RT::BUILDER), SO(RT::SCOUT), SO(RT::RAIDER), SO(RT::BUILDER), SO(RT::RAIDER, 3), SO(RT::BUILDER), SO(RT::RAIDER, 2)}),
			SQueue(0.1f, {SO(RT::RAIDER), SO(RT::BUILDER), SO(RT::RIOT), SO(RT::BUILDER), SO(RT::RAIDER, 4), SO(RT::BUILDER), SO(RT::RAIDER, 2)})
		}},
		{Factory::armalab, array<SQueue> = {
			SQueue(1.0f, {SO(RT::BUILDER2), SO(RT::RAIDER, 3), SO(RT::BUILDER2), SO(RT::ARTY, 2), SO(RT::ASSAULT), SO(RT::BUILDER2), SO(RT::AA)})
		}},
		{Factory::armavp, array<SQueue> = {
			SQueue(1.0f, {SO(RT::BUILDER2), SO(RT::SKIRM, 2), SO(RT::BUILDER2), SO(RT::SKIRM), SO(RT::BUILDER2), SO(RT::ARTY), SO(RT::AA), SO(RT::BUILDER2)})
		}},
		{Factory::armasy, array<SQueue> = {
			SQueue(1.0f, {SO(RT::BUILDER2), SO(RT::SKIRM, 2), SO(RT::BUILDER2), SO(RT::SKIRM), SO(RT::BUILDER2), SO(RT::ARTY), SO(RT::AA), SO(RT::BUILDER2)})
		}},
		{Factory::armap, array<SQueue> = {
			SQueue(1.0f, {SO(RT::BUILDER, 5)})
		}},
		{Factory::corlab, array<SQueue> = {
			SQueue(0.9f, {SO(RT::BUILDER), SO(RT::SCOUT), SO(RT::RAIDER), SO(RT::BUILDER), SO(RT::RAIDER, 3), SO(RT::BUILDER), SO(RT::RAIDER, 2)}),
			SQueue(0.1f, {SO(RT::RAIDER), SO(RT::BUILDER), SO(RT::RIOT), SO(RT::BUILDER), SO(RT::RAIDER, 4), SO(RT::BUILDER), SO(RT::RAIDER, 2)})
		}},
		{Factory::coralab, array<SQueue> = {
			SQueue(1.0f, {SO(RT::BUILDER2), SO(RT::RAIDER, 3), SO(RT::BUILDER2), SO(RT::ARTY, 2), SO(RT::ASSAULT), SO(RT::BUILDER2), SO(RT::AA)})
		}},
		{Factory::coravp, array<SQueue> = {
			SQueue(1.0f, {SO(RT::BUILDER2), SO(RT::SKIRM, 2), SO(RT::BUILDER2), SO(RT::SKIRM), SO(RT::BUILDER2), SO(RT::ARTY), SO(RT::AA), SO(RT::BUILDER2)})
		}},
		{Factory::corasy, array<SQueue> = {
			SQueue(1.0f, {SO(RT::BUILDER2), SO(RT::SKIRM, 2), SO(RT::BUILDER2), SO(RT::SKIRM), SO(RT::BUILDER2), SO(RT::ARTY), SO(RT::AA), SO(RT::BUILDER2)})
		}},
		{Factory::corap, array<SQueue> = {
			SQueue(1.0f, {SO(RT::BUILDER, 5)})
		}},
		{Factory::leglab, array<SQueue> = {
			SQueue(0.9f, {SO(RT::BUILDER), SO(RT::SCOUT), SO(RT::RAIDER), SO(RT::BUILDER), SO(RT::RAIDER, 3), SO(RT::BUILDER), SO(RT::RAIDER, 2)}),
			SQueue(0.1f, {SO(RT::RAIDER), SO(RT::BUILDER), SO(RT::RIOT), SO(RT::BUILDER), SO(RT::RAIDER, 4), SO(RT::BUILDER), SO(RT::RAIDER, 2)})
		}},
		{Factory::legalab, array<SQueue> = {
			SQueue(1.0f, {SO(RT::BUILDER2), SO(RT::RAIDER, 3), SO(RT::BUILDER2), SO(RT::ARTY, 2), SO(RT::ASSAULT), SO(RT::BUILDER2), SO(RT::AA)})
		}},
		{Factory::legavp, array<SQueue> = {
			SQueue(1.0f, {SO(RT::BUILDER2), SO(RT::SKIRM, 2), SO(RT::BUILDER2), SO(RT::SKIRM), SO(RT::BUILDER2), SO(RT::ARTY), SO(RT::AA), SO(RT::BUILDER2)})
		}},
		{Factory::legap, array<SQueue> = {
			SQueue(1.0f, {SO(RT::BUILDER, 5)})
		}},

		// GANTRIES. Without an entry here a plant takes the default opener at the
		// bottom of this function, and both consumers of it -- Factory::AiUnitAdded
		// and Brain::OpenerFirst -- skip any slot whose role GetRoleDef cannot
		// resolve on that plant. A gantry resolves neither BUILDER nor SCOUT, so the
		// default reduces to its RAIDER slots alone.
		//
		// One of each front-line role instead, in the order targets.as ranks them at
		// the income a gantry stands at: ASSAULT, SKIRM, RIOT. That same skip is what
		// lets one list serve all three factions -- Armada's gantry has no
		// assault-role def, Cortex's has no riot-role one.
		//
		// Artillery, heavy and raider are deliberately absent. Each stays reachable
		// through the quota, which reads a demand for it, and the plant's big unit is
		// already guaranteed one in flight per plant by Factory::SuperDefFor -- naming
		// it here would buy it twice.
		{Factory::armshltx, array<SQueue> = {
			SQueue(1.0f, {SO(RT::ASSAULT), SO(RT::SKIRM), SO(RT::RIOT)})
		}},
		{Factory::armshltxuw, array<SQueue> = {
			SQueue(1.0f, {SO(RT::ASSAULT), SO(RT::SKIRM), SO(RT::RIOT)})
		}},
		{Factory::corgant, array<SQueue> = {
			SQueue(1.0f, {SO(RT::ASSAULT), SO(RT::SKIRM), SO(RT::RIOT)})
		}},
		{Factory::corgantuw, array<SQueue> = {
			SQueue(1.0f, {SO(RT::ASSAULT), SO(RT::SKIRM), SO(RT::RIOT)})
		}},
		{Factory::leggant, array<SQueue> = {
			SQueue(1.0f, {SO(RT::ASSAULT), SO(RT::SKIRM), SO(RT::RIOT)})
		}}
		}, {SO(RT::BUILDER), SO(RT::SCOUT), SO(RT::RAIDER, 3), SO(RT::BUILDER), SO(RT::RAIDER), SO(RT::BUILDER), SO(RT::RAIDER)}
	);
}

const array<SO>@ GetOpener(const CCircuitDef@ facDef)
{
	SOpener@ open = GetOpenInfo();

	const string facName = facDef.GetName();
	array<SQueue>@ queues;
	if (!open.factory.get(facName, @queues))
		return open.def;

	array<float> weights;
	for (uint i = 0, l = queues.length(); i < l; ++i)
		weights.insertLast(queues[i].weight);

	int choice = AiDice(weights);
	if (choice < 0)
		return open.def;

	return queues[choice].orders;
}

}  // namespace Opener


/*
namespace Hide {

// Commander hides if ("frame" elapsed) and ("threat" exceeds value or enemy has "air")
shared class SHide {
	SHide(int f, float t, bool a) {
		frame = f;
		threat = t;
		isAir = a;
	}
	int frame;
	float threat;
	bool isAir;
}

dictionary hideInfo = {
	{Commander::armcom, SHide(480 * 30, 30.f, true)},
	{Commander::corcom, SHide(470 * 30, 20.f, true)}
};

map<Id, SHide@> hideUnitDef;  // cache map<UnitDef_Id, SHide>

const SHide@ CacheHide(const CCircuitDef@ cdef)
{
	Id cid = cdef.GetId();
	const string name = cdef.GetName();
	array<string>@ keys = hideInfo.getKeys();
	for (uint i = 0, l = keys.length(); i < l; ++i) {
		if (name.findFirst(keys[i]) >= 0) {
			SHide@ hide = cast<SHide>(hideInfo[keys[i]]);
			hideUnitDef.insert(cid, hide);
			return hide;
		}
	}
	hideUnitDef.insert(cid, null);
	return null;
}


const SHide@ GetForUnitDef(const CCircuitDef@ cdef)
{
	bool success;
	SHide@ hide = hideUnitDef.find(cdef.GetId(), success);
	return success ? hide : CacheHide(cdef);
}

}  // namespace Hide
*/
