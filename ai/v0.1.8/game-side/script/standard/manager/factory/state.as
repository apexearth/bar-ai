namespace Factory {


// Team tech coordination: humans designate one player to tech and share
// advanced constructors out; everyone else follows once eco supports it.
bool gHaveT2 = false;   // set once we own an advanced factory
bool gHaveT3 = false;   // ...and a T3 gantry
// The real trigger is energy, not metal: take the nearby mexes, reach roughly
// 500 energy/sec, then commit to T2. The rusher is the one player the whole
// team is funding, so it is the last one that should be teching on thin energy.
// 800, was 400 with a CLOCKED fallback to 240 after minute 5 -- the exact
// pattern apexearth has banned twice, and the generator of his "super
// frustrated every time i see us go T2 with only around 500 energy income"
// (2026-08-20). The T2 program is an energy program: the lab's builds, moho
// upkeep, and the fusion the T2 con must immediately raise (~600 E/s draw
// while building). A reactor already on the grid halves the bar, because
// the ramp is coming -- see RushReady.

// The whole team pools metal behind the rusher, so it must not be the poorest
// player on it -- feeding a starved economy just moves the starvation around.
// The richest ally is picked outright rather than merely vetoing a poor pick,
// since a veto alone cancels the rush without anyone else taking it.
//
// The election runs here, over the in-process blackboard, rather than in
// synced Lua: synced Lua has to exist on every client and cannot ship to a
// hosted multiplayer game, whereas every AI the host adds shares one process,
// so the blackboard reaches exactly the same set of instances a gadget would.
// ONE writer: the lowest team id in the ally roster elects and publishes;
// everyone else only reads -- this is what prevents a double election, where
// two instances elect different leads because they sampled state at different
// instants.
//
// The rule itself is commitment, not income: the lead is whoever is building
// an advanced plant, and if two are building, whichever plant is closest to
// finished. Nanoframes count -- ai.GetDefBuildProgress returns fractional
// progress, which is exactly the tie-break.
const string TV_ADV  = "adv";    // this team's best advanced-plant progress
const string TV_LEAD = "lead";   // the elector's answer, read by everyone
// Metal income while this team could commit to a plant, 0 when it could not.
// Electing on commitment ALONE cannot stop a stampede: nobody is designated
// until somebody has already started, so the gate stands open and every team
// that comes good in the same window starts its own plant.
const string TV_READY = "ready";
// Distance from our own base to the enemy centroid. A player that techs stops
// defending itself, so the one who can least afford that is the one closest
// to the enemy.
const string TV_DIST = "dist";
// What share of this team's PEAK extractor count it still holds, 1.0 while it
// has never lost one. Published by everyone; the eco lead reads it as "is
// somebody being taken apart". A share rather than a flag, because the bar for
// standing our own ground and the bar for an ally being killed are not the same
// number and only the reader knows which it is asking.
const string TV_MEX = "mexhold";
// How full this team's metal storage is, 0..1. Slinging reads it off the lead so
// it can stop feeding a player who is already at cap. The check it restores was
// dropped because ai.GetTeamMetalFill() returns 1.0 unconditionally -- the check
// was right, its data source was not.
const string TV_FILL = "fill";

// Stop feeding at this share of the lead's storage. Has to mean "overflowing",
// not "comfortable": a commander starts on 1000/1400 storage, so a lower bar
// reads the lead as full before it has spent anything and blocks donations
// through the whole window where they matter.
const float SLING_STOP_FILL = 0.92f;

// Lowest team id in the ally roster. Every instance computes the same answer
// from the same roster with no signalling, so all of them know whose blackboard
// slot carries a shared value (the team-push window, for one).
int ElectorTeamId()
{
	array<Id>@ mates = ai.GetTeamIds();
	if ((mates is null) || (mates.length() == 0))
		return ai.teamId;
	int low = int(mates[0]);
	for (uint i = 1; i < mates.length(); ++i) {
		if (int(mates[i]) < low)
			low = int(mates[i]);
	}
	return low;
}

bool TeamPlay()
{
	array<Id>@ roster = ai.GetTeamIds();
	return (roster !is null) && (roster.length() > 1);
}

}  // namespace Factory
