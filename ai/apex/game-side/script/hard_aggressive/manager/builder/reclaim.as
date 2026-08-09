namespace Builder {

// Eating the field after a won fight is a large metal swing, and while the team
// is funding one player's tech it is the cheapest metal going -- nobody has to
// pay for it. But a plain area reclaim takes whatever is inside the circle, so
// a builder sent to a battlefield is as likely to chew a 12-metal tree as a
// dead Gollum. ai.GetBestWreckPos finds the richest body and we centre the
// circle on that, so corpses get valued rather than merely counted.
// This variant's whole plan is to make the enemy pay for our economy: let them
// attack into static defence backed by a massed army, and then eat the bodies.
// The third step is the one that funds everything, so it is worth reaching
// further and accepting smaller bodies than a tempo variant would -- after a
// repelled push the field is dense with wrecks and every one of them is metal
// the enemy bought for us.
const float WRECK_SEARCH  = 2200.f;  // reach the whole approach, not just home
const float WRECK_MIN     = 55.f;    // a repelled push leaves many small bodies
// A body worth INTERRUPTING a build for, and how far we will go to reach one.
// Reclaim previously required either an empty bank or an idle builder, so a
// constructor holding any task walked straight past a field of wrecks.
// apexearth, after a repelled push: "theres 1000+ metal in front of us and we
// don't even care". This variant's plan is to make the enemy pay for our
// economy and then eat the bodies -- that third step is the one that funds
// everything, and it was not happening.
// Deliberately a HIGH bar and a SHORT reach: this displaces real work, so it
// must only fire for a body big enough to be worth more than what it interrupts,
// and close enough that the walk is not the cost.
// TOTAL metal in the field, not the biggest single body: a repelled push leaves
// a dozen dead T1s, none of them individually large, and that is exactly the
// pile worth eating. apexearth: "often its a dozen t1 that just died... still
// its a lot of metal we should be eating... the building will still get made
// faster if we grab the metal - then we can make the building without waiting!"
const float WRECK_RICH    = 400.f;   // total reclaimable within WRECK_RICH_R
const float WRECK_RICH_R  = 1400.f;
const float WRECK_RADIUS  = 320.f;   // sweep the cluster, not one corpse
const int   WRECK_TIMEOUT = 1 * MINUTE;
int gNextWreck = 0;
int gNextMetalEmptyDiag = 0;  // temporary diagnostic, see ScavengeWrecks
// Spacing on the safe-mex grab. Short: an unclaimed spot is income we are not
// earning, and the check itself is one lookup.
const int REAR_MEX_PERIOD = 2 * SECOND;
int gNextRearMex = 0;
int gNextMexLog = 0;
int gNextRichLog = 0;

// ai.GetWreckValueAt/GetBestWreckPos were dead for every non-resigned team
// until the C++ fix in CircuitAI.cpp (2026-08): both used the CCircuitAI::
// metalRes member, which is only ever assigned inside NotifyResign() and so
// stayed null all game, making both calls return zero/invalid unconditionally.
// Fixed at the source, but every mobile builder already scans WRECK_RICH_R
// around itself every ~3s below regardless -- record what it sees here and let
// anyone without their own vantage point (factory.as's rez-bot floor) read the
// sighting instead of taking a fresh sample from wherever they happen to be.
//
// A DECAYING PEAK, not the last reading. The only samplers are ordinary mobile
// constructors reporting GetWreckValueAt within WRECK_RICH_R of wherever they
// happen to stand, so consecutive readings are unrelated points, not a series:
// one con parked in a corpse field and the next one home at the mex line both
// write here. A last-reading-wins value therefore spends most of its life at
// whatever the most recent con happened to be standing on, and its consumer
// (factory.as's rez-bot floor) is sizing a STANDING count of units that take
// 2800 buildtime to arrive -- a quantity that cannot track a signal which
// changes every three seconds. Holding the peak and bleeding it out over
// WRECK_SEEN_TTL makes the value mean "this much was on the field recently",
// which is the question the floor is actually asking.
float gWreckSeenValue = 0.f;
int gWreckSeenAt = 0;
const int WRECK_SEEN_TTL = 3 * MINUTE;

void NoteWreckSeen(float value)
{
	if ((value <= 0.f) || (value < WreckSeenValue()))
		return;
	gWreckSeenValue = value;
	gWreckSeenAt = ai.frame;
}

float WreckSeenValue()
{
	const int age = ai.frame - gWreckSeenAt;
	if ((age < 0) || (age >= WRECK_SEEN_TTL))
		return 0.f;
	return gWreckSeenValue * (1.f - float(age) / float(WRECK_SEEN_TTL));
}

// The engine's own build-site safety check is an AND of three terms
// (BuilderManager::MakeBuilderTask): near-zero power in the thing being built,
// hot threat map, AND influence already reading enemy-owned. Contested ground
// no enemy structure has claimed yet fails the third, so the task stays
// selectable and a constructor walks to it. This is the middle term alone.
//
// The threat map paints enemy damage-vs-builder times sqrt(health) over each
// enemy's weapon range and is still half its peak at the rim -- so a covered
// tile reads in the hundreds and an uncovered one reads zero, while an
// unidentified radar blip contributes 0.1. 4.0 is THREAT_MIN * 4, the engine's
// own "an enemy holds this ground" bar in MilitaryManager::DefaultMakeDefence.
//
// Declared here, ahead of its first use in EnqueueWreckReclaim just below:
// AngelScript has no forward declarations for globals (functions are visible
// module-wide regardless of order, but a global const must be declared before
// the line that reads it), and this constant used to live much further down,
// declared only once ThreatFor() -- which needs it -- was already in scope.
const float CON_THREAT_VETO = 4.0f;

// Declared here rather than beside its use in rules_commander.as: AngelScript
// needs globals declared before use, and the shims fix the order of the files.
int gNextCommFleeLog = 0;

// apexearth: "have our units never assist another unit build something if
// we are out of a resource (<5%)." Declared here, ahead of AiMakeTask's use
// of it, for the same forward-declaration reason as CON_THREAT_VETO above.
const float RESOURCE_CRISIS_FRAC = 0.05f;

IUnitTask@ EnqueueWreckReclaim(CCircuitUnit@ unit, Task::Priority priority)
{
	const AIFloat3 pos = unit.GetPos(ai.frame);
	const AIFloat3 wreck = ai.GetBestWreckPos(pos, WRECK_SEARCH, WRECK_MIN);
	if (wreck.x < 0.f)
		return null;   // nothing worth the trip
	// apexearth, watching live: "even our advanced cons are chasing wrecks
	// which are dangerous." Shared by the idle-builder fallback and the
	// rezzer-eats-wreck path; neither checked whether the wreck itself sits
	// somewhere safe before sending a constructor to it.
	if (ThreatFor(unit, wreck) > CON_THREAT_VETO)
		return null;
	return aiBuilderMgr.Enqueue(TaskB::Reclaim(priority, wreck,
			1000.f, WRECK_TIMEOUT, WRECK_RADIUS, true));
}

// Rez bots are the only units in BAR that can resurrect at all -- armrectr,
// cornecro and legrezbot plus their three ship counterparts are the whole list,
// and every faction's T1 bot lab builds one. The engine hands them a resurrect
// unconditionally: CEconomyManager::UpdateReclaimTasks takes isResurrect
// straight from IsAbleToResurrect() with no economy test, so for those units it
// only ever queues RESURRECT and never a feature RECLAIM. Resurrecting spends to
// turn a corpse back into a unit; reclaiming turns it into metal, and the field
// after a won fight is the cheapest metal in the game -- which is exactly what a
// team pooling its income behind one player's tech is short of.
//
// The flag is not reachable from here, so pre-empt the task instead: hand the
// bot a wreck reclaim ourselves and DefaultMakeTask, the thing that would have
// created the resurrect, never runs. It cannot cost us build work: these bots
// are builder=true with no buildoptions, so the most it displaces is a repair.
// Only rez bots need this. Every other constructor already gets a RECLAIM from
// the same function, because for them isResurrect is false.
//
// The gate is deliberately short. A bot that loses this race is given a
// resurrect task with a 300-second timeout and is out of the metal business
// until it expires, which costs far more than the feature scan does.
const int REZ_WRECK_PERIOD = 1 * SECOND;
int gNextRezWreck = 0;
int gNextRezFleeLog = 0;

// Which defs resurrect, learned from the engine rather than named: BuilderManager
// routes exactly the canresurrect units through UseAs::REZZER. A name list would
// need armrectr/armrecl, cornecro/correcl and legrezbot/legnavyrezsub kept in
// sync, and the config roles cannot stand in for it either -- they disagree
// across factions ("support" for Armada and Legion, "rezzer" for Cortex).
// Both ends of the index are range-checked: the array is sized once at load, and
// an id past it raises a script exception that kills the enclosing callback
// without saying so.
array<bool> gRezzerDefs(ai.GetDefCount() + 1);
array<int> gRezzerIds;

bool IsRezzer(CCircuitUnit@ unit)
{
	const int id = unit.circuitDef.id;
	return (id >= 0) && (uint(id) < gRezzerDefs.length()) && gRezzerDefs[id];
}

// Rez bots we hold. CBuilderManager routes them through rezzFinishedHandler,
// which inserts into `workers` but never calls AddBuildPower -- so a rez bot
// raises GetWorkerCount() while contributing nothing to GetBuildPower(). Any
// cap written against GetWorkerCount() has to take them back out, the same way
// the nano turrets are taken out.
int RezCount()
{
	int n = 0;
	for (uint i = 0; i < gRezzerIds.length(); ++i) {
		CCircuitDef@ d = ai.GetCircuitDef(gRezzerIds[i]);
		if (d !is null)
			n += int(d.count);
	}
	return n;
}

// Reclaim turns a corpse into raw metal; resurrect returns the WHOLE unit for a
// fraction of its build cost. That is the same efficiency argument that makes
// T1 spam good -- a resurrected Thug is far cheaper than a built one.
//
// This used to require a FULL bank before it would allow a resurrect, which in
// practice never happened, so rez bots only ever reclaimed. Measured on
// Glitters: stock spent 27,385 metal resurrecting in a game it dominated on
// army 96k to 23.6k, while apex spent 0.
//
// Reclaim is now preferred only while metal is genuinely the binding
// constraint: before we own an advanced factory, or when the bank is actually
// empty and a build is stalled on it.
// apexearth: "requiring full is a bit nuts, I think 90% is a good limit", and
// earlier "if we have absolutely no metal, then reclaim". Read together: keep
// resurrecting across almost the whole band and fall back to reclaim only when
// the bank is genuinely scarce.
//
// Note isMetalFull is already storage*0.8 and isMetalEmpty storage*0.2
// (economy.as), so the original gate was "above 80%", not literally full.
const float REZ_METAL_FLOOR = 0.10f;   // reclaim below this share of storage

bool PreferReclaim()
{
	// No commander: rez ahead of everything else, including the pre-T2
	// default. gComm is null only for the real gap between death and rebuild.
	if (gComm is null)
		return false;
	if (!Factory::gHaveT2)
		return true;
	// Behind on the field, the completion risk is the whole argument: a resurrect
	// credits nothing until it finishes, so a bot pushed off one has spent the
	// time for no metal, while reclaim banks continuously and survives being
	// interrupted. Same reasoning as RezSpotHot, on the team's position instead of
	// this bot's tile. apexearth: "our resurrection box should be more likely to
	// reclaim when we're losing."
	if (Military::LosingGround())
		return true;
	return aiEconomyMgr.metal.current
	     < aiEconomyMgr.metal.storage * REZ_METAL_FLOOR;
}

}  // namespace Builder
