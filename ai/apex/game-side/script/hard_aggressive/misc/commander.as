#include "../manager/factory.as"


namespace Commander {

string armcom("armcom");
string corcom("corcom");
string legcom("legcom");

//------------------------------------------------------------------------------
// "At T1 he can be our action hero. Once there is heavy T2 in the game the
// commander needs to be careful."
//
// This is telemetry only. There is no lever here, and the reason is worth
// keeping: an earlier revision wrote aiBuilderMgr.dangerHysteresis, which exists
// in vendor/circuitai (CBuilderManager stamps a dangerTime and keeps the comm
// near base while dangerTime + dangerHysteresis >= frame) but NOT in the tree we
// actually deploy. vendor/engine/AI/Skirmish/BARb is the tree matching the
// shipped DLL -- it alone defines GetBestWreckPos and SendResources, which these
// scripts already call successfully -- and there the comm branch of
// CBuilderManager::MakeTask (BuilderManager.cpp:967-984) is stateless: it
// re-reads GetEnemyInflAt(comm pos) against commander.json's hide.threat on every
// call. No dangerTime, no dangerHysteresis field, and no such property on the
// registered CBuilderManager, whose entire surface is DefaultMakeTask, Enqueue,
// EnqueueRetreat and GetWorkerCount. Assigning it was a compile error, and per
// CLAUDE.md one of those disables the WHOLE AI silently while the match still
// runs near-stock -- so it would have invalidated every result it was measured by.
//
// Scaling commander caution therefore needs either a commander.json hide.threat
// change or a new C++ binding. Until then, log the input so the next attempt
// starts from data. Check bindings against vendor/engine, never vendor/circuitai.

// Trigger on metal we have actually identified. CEnemyManager adds a unit's metal
// cost to its role buckets when it first enters LOS and only subtracts it when
// the unit dies, so GetEnemyCost(RT::HEAVY) is a standing count of live enemy
// heavies rather than an LOS snapshot; it does not flicker as they move in and
// out of vision.
//
// Calibrated off real unit costs rather than a guess. The cheapest def carrying
// the "heavy" role in this profile's behaviour configs is armmar at 970 metal,
// then legaheattank 1250, armfboy 1400, corshiva 1550, corgol 1650, cortrem 1850,
// corsumo 2200, leginc 2300, corkarg 2500. A commander is 2700 metal and 3700 hp
// and loses to any one of them. 900 therefore reads as "one enemy T2 heavy, any
// faction, is on the field", which is the line the user drew.
//
// The 400 that never fired was measured against a THREAT figure, and threat is
// cost-independent: defThreat = sqrt(dps) * dmg^0.25 * sqrt(hp) / 128, roughly 1.5
// for a T1 raider and 30 for a Sumo. 400 of that needed a dozen heavies alive at
// once, so no game reached it. Cost is the scale that matches the sentence.
const float COM_HEAVY_METAL = 900.f;

bool gCautious = false;
int  gNextLog  = 0;

void UpdateCaution()
{
	const float heavy = aiEnemyMgr.GetEnemyCost(RT::HEAVY);
	const bool careful = (heavy >= COM_HEAVY_METAL);
	if (careful != gCautious) {
		gCautious = careful;
		AiLog("apex: commander " + (careful ? "CAUTIOUS" : "loose")
			+ " frame=" + ai.frame
			+ " enemyHeavy=" + formatFloat(heavy, "", 0, 0));
	}

	// Heartbeat. "The threshold never fired" and "the input is dead" look
	// identical in a log that only prints on transitions, which is exactly how the
	// 400 went unnoticed. workers is in here because the C++ gate also wants
	// GetWorkerCount() > 2 before any commander caution applies at all.
	if (ai.frame >= gNextLog) {
		gNextLog = ai.frame + 2 * MINUTE;
		AiLog("apex: comm heavy=" + formatFloat(heavy, "", 0, 0)
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
