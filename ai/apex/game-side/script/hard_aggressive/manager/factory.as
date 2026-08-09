#include "../../define.as"
#include "../../unit.as"
#include "../../task.as"
#include "../misc/commander.as"
#include "economy.as"


namespace Factory {

// Team tech coordination. Measured in a 4v4: stock has none -- each instance
// decides independently, so 0 of 4 teched on the losing side and 2 of 4 on the
// winner, essentially at random. Humans designate one player to tech and share
// advanced constructors out; everyone else follows once eco supports it.
bool gHaveT2 = false;   // set once we own an advanced factory
// The real trigger is energy, not metal: take the nearby mexes, reach roughly
// 500 energy/sec, then commit to T2. That lands around 5 minutes, and T2 should
// exist before 10. Gating on metal income 12 held the rusher on T1 until minute
// 12 and the plant only finished at 20 -- later than stock reached it unaided.
// Raised 150 -> 400, and the floor with it. 150 was far under this comment's own
// stated design of "roughly 500 energy/sec": it let the rusher commit to an
// advanced plant on a grid that could not run it, and the plant then crawled.
// The rusher is the one player the whole team is funding, so it is the last one
// that should be teching on thin energy -- and it should keep scaling energy
// afterwards, which is what the raised economy.energy.factor is for.
//
// This DELAYS the rush at today's energy curve: measured ~130 e/s at 5 min and
// ~290 at 8, so 400 is not cleared until roughly 8-9 min against 5.5 today. The
// bet is that the factor change pulls that curve up to meet it. If first-T2
// slips badly, the factor is too low -- raise it before lowering these.
const float RUSH_ENERGY_TARGET = 400.f;
const float RUSH_ENERGY_FLOOR  = 240.f;      // same 0.6 ratio to target as before
const int   RUSH_LATEST        = 5 * MINUTE; // T2 should exist before 10 min

// The whole team pools metal behind the rusher, so it must not be the poorest
// player on it -- feeding a starved economy just moves the starvation around.
// Observed live: on a map where some starts have a single mex, the AI's own
// GetLeadTeamId() picked a player on 4 metal/sec and the whole team pooled
// behind it. Merely vetoing a poor lead is not enough -- that just cancels the
// rush and nobody else takes it. The richest ally has to be picked outright.
//
// The election runs here, over the in-process blackboard. It used to run in
// synced Lua (dev_team_income.lua) because a per-instance election elected two
// leads in 1 of 533 archived matches -- not because the instances disagreed on
// the facts, but because they sampled them at different instants. Synced Lua
// cannot ship to a hosted multiplayer game, though: it has to exist on every
// client. Every AI the host adds shares one process, so the blackboard reaches
// exactly the same set of instances the gadget did, and nothing else.
//
// The property that fixed the double election is kept: ONE writer. The lowest
// team id in the ally roster elects and publishes; everyone else only reads.
//
// The rule itself is now commitment, not income: the lead is whoever is
// building an advanced plant, and if two are building, whichever plant is
// closest to finished. Nanoframes count -- ai.GetDefBuildProgress returns
// fractional progress, which is exactly the tie-break.
const string TV_ADV  = "adv";    // this team's best advanced-plant progress
const string TV_LEAD = "lead";   // the elector's answer, read by everyone
// Metal income while this team could commit to a plant, 0 when it could not.
// Electing on commitment ALONE cannot stop a stampede: nobody is designated until
// somebody has already started, so the gate stands open and every team that comes
// good in the same window starts its own plant. Observed live, twice: three
// commanders teching within 40 seconds of each other at the 5 minute mark.
const string TV_READY = "ready";
// Distance from our own base to the enemy centroid. apexearth: "if you can find a
// way to make it less likely that the AI at the front line is teching, then
// that's a good idea." A player that techs stops defending itself, so the one
// who can least afford that is the one closest to the enemy.
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
// was right, its data source was not. Measured 2026-08-02: without it, eleven
// followers pushed ~269,000 metal into one lead that sat over storage from
// minute 8 and fielded no army for fourteen minutes.
const string TV_FILL = "fill";

// Stop feeding at this share of the lead's storage.
//
// This has to mean "overflowing", not "comfortable". 0.60 was tried and cut
// pooling from ~269,000 metal to 312: a commander starts on 1000 metal against
// 1400 storage, so the lead reads 71% full before it has spent anything, and
// the check blocked donations through the whole window where they matter. The
// plant went from ~5-8 min to 18.7 min and never finished.
//
// The waste being targeted is far past this line -- measured at 1305/1300 and
// 1735/1300, i.e. at and over cap -- so the bar belongs just under 1.0 where it
// catches real overflow and nothing else.
const float SLING_STOP_FILL = 0.92f;

// The elector publishes one team id per lead slot. Slot 0 keeps the bare "lead"
// key so every existing reader -- slinging, the air lead, the army suppression --
// still finds the primary lead where it always was.
string LeadKey(uint slot)
{
	return (slot == 0) ? TV_LEAD : (TV_LEAD + slot);
}

// How many players may rush T2 at once. apexearth, watching an 8v8: "on an 8v8
// you might expect 2 players to go T2 early, not 5 or 6 ... 1 per ~6 guys seems
// ok. so at 8 we get 2". Ceiling, so a small team still gets one.
uint TechLeadQuota()
{
	array<Id>@ mates = ai.GetTeamIds();
	const uint n = ((mates is null) || (mates.length() == 0)) ? 1 : mates.length();
	return (n + 5) / 6;
}

// Total builders the tech lead may hold while rushing. Enough to finish an
// advanced plant fast; beyond that each constructor is metal that buys nothing
// while the whole team is funding this one player.
const uint  RUSH_CON_CAP = 6;

// Minimum gap between two constructor orders during the rush.
//
// RUSH_CON_CAP reads GetWorkerCount(), which counts FINISHED builders only, and
// Enqueue does not dedup -- so without spacing the cap can be overshot by
// however many orders fit in one constructor's build time. An interval is used
// rather than an in-flight counter because an aborted recruit would leak a
// counter permanently and silently stop constructor production.
const int   RUSH_CON_SPACING = 12 * SECOND;
int gNextConOrder = 0;

// Army catch-up production when behind. Short: this is the thing we want a
// lot of, and the units are cheap.
// The catch-up push has no budget, and that is what makes it dangerous. It fires
// while LosingGround(), which is nearly always true once behind, so it converts
// the whole economy into army and then loses harder for want of an economy.
//
// Measured after it was pointed at the advanced plant: armbull 33.8% and armanni
// 22.0% of ALL metal -- 56% on army and defence -- against ONE T2 constructor and
// 5 mex upgrades to stock's 15 and 12. The unit choice was right and the spend was
// ruinous. At 3 seconds it was buying 180-metal Stumpies; at the same cadence it
// buys 800-metal Bulldogs.
const int   ARMY_PUSH_SPACING = 12 * SECOND;
// And it stops entirely when the economy behind it is too thin to carry it: an
// army bought by starving the mexes cannot be replaced when it dies.
const float ARMY_PUSH_MIN_INCOME = 30.f;
int gNextArmyPush = 0;
int gNextArmyLog = 0;

// Every third catch-up push buys fodder instead of the assault mainstay.
//
// Measured over eight 4v4 infologs: apex's standing cheap-unit value (mobile,
// armed, under 120 metal) runs 3-6x below stock BARb's from minute 14 on -- 851
// against 3,727 at eighteen minutes -- while its total army value is comparable.
// The factory weights are not the cause; they still carry 10-17% cheap. This
// branch is: it overrides the configured mix every 3 seconds while behind, and
// it only ever asks for ASSAULT.
//
// One in three REQUESTS is about 7% of the metal, because a Tick is 21 and a
// Hammer 130. The stream of bodies is what is wanted, not the spend.
const int   FODDER_EVERY = 3;
int gArmyPushCount = 0;

int gRushLead = -1;   // last PRIMARY lead this instance saw published
bool gAmLead = false;   // this team holds one of the lead slots
bool gT1Reclaimed = false;   // one-shot: we fed our T1 lab into the plant

// ECO LEAD. One player -- the primary tech lead slot -- stops playing the map
// and does nothing but grow an economy, so the team arrives at the late game
// with something to spend there instead of four mid-sized economies that all
// stop at T2. apexearth: "they don't make army unless endangered or our allies
// are dying. they just focus on building up a huge economy."
//
// Big teams only, and for the reason already measured on the tech lead itself:
// on a four-player team one player fielding no army is a quarter of the army
// missing, and the note on the constructor monopoly below records what that
// cost (standing army 17.8k against 25.4k, real K/D 0.70 against 1.24). At
// eight players it is an eighth.
//
// Held for the whole game, not to Military::RUSH_GIVEUP: the point is the LATE
// game, so a role that expires at fifteen minutes is the one part of it that
// cannot pay off.
bool gEcoActive = false;   // this instance is running as the eco lead right now
int  gEcoLoggedFor = -1;   // team we last announced the role for

// "Being taken apart" is measured as EXTRACTORS LOST off this team's own peak.
//
// Metal income was the obvious measure and is the wrong one: apexearth, "they
// can reclaim and get a temporary boost to metal income and then later on it
// falls", which sets a peak nothing can live up to and then reads the return to
// normal as death. Energy income is worse still -- it rises and falls with the
// wind. A standing extractor count moves in one direction for one reason.
//
// Deliberately not Military::LosingGround() either: that compares the enemy's
// army value to OURS, and a player that builds no army reads "losing"
// permanently, so the release would be stuck on from the moment the role began.
// Two bars, because they answer two different questions.
//
// OURS is "we are being pushed off our own ground" -- the eco lead is the player
// least able to fight back, so it reacts early.
//
// An ALLY's is "that player is being killed", and it has to be a much harder bar
// on a big team. Seven allies each with an independent chance of standing a
// couple of mexes below their peak means "any ally at 70%" is true essentially
// all the time, which is what a first 8v8 run showed: the role was elected at
// 7.6 minutes and never once activated.
//
// Both bars are also SUSTAINED rather than instantaneous, and this is the part
// that was wrong. Upgrading a mex destroys the T1 extractor and leaves a
// nanoframe, so the standing count dips for the whole build -- and the eco lead
// upgrades more mexes than anyone (measured, 20 games: 5 against a teammate
// average of 3). The role was therefore tripping its own release on the exact
// behaviour it exists to produce: "losing our own mexes" was the single largest
// cause of standing down, 45 times across those games.
const float HURT_SELF_FRAC = 0.55f;
const float HURT_ALLY_FRAC = 0.40f;
const uint  HURT_MIN_MEX   = 6;   // under this a single lost mex is not a trend
// A mex takes well under this to rebuild or upgrade; a base being eaten does not
// recover inside it.
const int   HURT_SUSTAIN   = 40 * SECOND;
int gHurtSince = -1;   // frame our own share first went under the bar, -1 if not
// Both tiers, all three sides; we only ever hold our own side's units, so the
// others contribute zero. T1 first, advanced second -- MexCount indexes on that
// split. Summing the two tiers is NOT by itself enough to make an upgrade
// neutral, because the old unit is destroyed before the new one exists.
array<string> MEX_DEFS = {"armmex", "cormex", "legmex",
                          "armmoho", "cormoho", "legmoho"};
bool  gHurt = false;
float gMexHold = 1.f;   // our own share of peak, published for our allies
uint  gPeakMex = 0;

// How long the role survives losing its slot.
//
// Measured, 8v8 Comet Catcher at +40%: the primary slot moved team 5 -> lost ->
// 5 -> 3 -> 5 inside two minutes, so the role was taken and dropped four times
// and never ran for longer than six seconds. The election keeps an incumbent
// only while RushReady() holds, and that reads ENERGY income, which rises and
// falls with the wind -- apexearth, "wind energy goes up and down due to wind
// speed". Taking the role is immediate; giving it up waits, so a slot that
// flickers does not turn the whole strategy on and off with it.
//
// Two players can briefly believe they are the eco lead when the slot genuinely
// moves. That costs one idle factory line for this long, against the strategy
// not existing at all, which is what the flapping produced.
// 45s was not enough: across 20 games "role lost" was still the second largest
// cause of standing down, 31 times, behind only the mex dip. The election's
// incumbency test is what flickers, not the player's fitness for the job.
const int ECO_ROLE_GRACE = 150 * SECOND;
int gEcoSlotSeen = -1000000;

// Build power is the one thing the eco lead does buy from its factory. Past
// this it buys nothing at all and the income goes to the builders instead --
// mexes, energy, converters, the T2 and T3 economy.
//
// Spaced for the same reason RUSH_CON_SPACING is: Enqueue does not dedup and
// GetWorkerCount() counts only FINISHED builders, so the cap alone cannot hold.
// BUILD POWER IS THE ECONOMY, and 10 was starving the one player whose whole job
// is to grow.
//
// Measured over 7 sixty-minute games: the eco lead PRODUCED 23% more metal than
// its teammates and BUILT 36% less of it, holding 12 T1 constructors against
// their 28. It banks income it has no capacity to spend, which is why it is also
// the one player that never reaches T3 (1,557 against 22,179). At 30 minutes
// this was invisible -- the margin still looked like +71% metal -- because there
// had not yet been enough income for the ceiling to bind.
//
// A cap this size only binds late, and the spacing is what stops it being
// bought all at once. apexearth's own note: "if above ~50% metal then we can
// keep making construction turrets ... sometimes making ~4 more at a time is
// more efficient."
// Split between ground and AIR, and the ground half deliberately falls back.
// apexearth: "the eco player should try to get more air constructors and more
// nanos, less ground engineers." A ground engineer walks; at the scale this
// player is working at -- 240,000 metal produced in an hour, spread over mexes,
// fusions and a second base -- walking is most of what it does. Air constructors
// cross the same distance in seconds, and a nano turret does not travel at all.
// TODO.md carries the same rule and its caveat: air cons "allow you to scale
// everything much faster ... HOWEVER - air cons are easily shot down near the
// front line", which is survivable for THIS player because it works behind its
// own team.
const uint  ECO_CON_CAP     = 16;   // ground engineers, down from 28
const int   ECO_CON_SPACING = 10 * SECOND;
const int   ECO_AIR_CON_CAP = 12;
// Enough to unlock the advanced air plant, which is the only durable source of
// fighters. Anything above this is left to the factory ratios.
const int   AIR_CON_MIN     = 1;
const int   ECO_AIR_SPACING = 8 * SECOND;
// The eco lead earns its own aircraft plant once it is clearly the team's bank.
// Not before: a second factory this player cannot yet feed is the "rules that
// spend" trap, and the air plant is only worth it for what it builds.
const float ECO_AIR_PLANT_INCOME = 45.f;
int gNextEcoAirCon = 0;
int gNextEcoCon = 0;
int gNextEcoLog = 0;
int gNextEcoGateLog = 0;

// LATE GAME, and a standing fighter screen once it arrives.
//
// apexearth: "make sure we always make air in the late game, even if it's just
// fighters." The Air namespace next door is a different thing entirely -- one
// player, a surprise bomber strike, gated behind income 60 and the enemy's
// anti-air. That is a strategy that may never fire; this is a floor that always
// does, so the team is never simply handed the sky.
//
// TODO.md's own definition of late game: "usually 25 minutes + into the game,
// but you can gauge late game based on if we have things like fusions or afus".
// Both, so a fast economy counts as late early and a slow one still qualifies.
const int LATE_GAME_FRAME = 25 * MINUTE;
// Fighters, not an air force. Enough to contest scouting and punish bombers.
const int LATE_FIGHTERS   = 8;
const int LATE_FIG_SPACING = 10 * SECOND;
// Income before a player without any air plant builds one purely for this.
const float LATE_AIR_INCOME = 55.f;

// Reactive fallback, separate from the income-gated one above: apexearth,
// watching an 8v8 live, "enemy air is really becoming brutal this game. They
// have two air players... if we see the enemy has air and we do not have any
// air, by ten minutes, we should probably be making an air lab and making
// fighters. At the very least, we need some fighter defense." The income gate
// exists to stop a plant we do not need; it says nothing about a threat we can
// already see, so this triggers off Military::gAirAvg instead of our own
// economy. Above AA_IGNORE (500): a floor meant to ignore a single air
// constructor, not a real commitment worth answering with a plant.
const int   EARLY_AIR_REACT_FRAME = 10 * MINUTE;
const float EARLY_AIR_ENEMY_MIN   = 800.f;
int gNextFighter = 0;

// Two radar planes is enough to sweep for a hiding commander; they are ~175
// metal each and are vision, not army, so this is a floor rather than a build.
const int LATE_SCOUTS       = 2;
const int LATE_SCOUT_SPACING = 30 * SECOND;
int gNextScout = 0;

string armawac("armawac");  string corawac("corawac");  string legwhisper("legwhisper");

CCircuitDef@ RadarPlaneDef()
{
	const string side = ai.GetSideName();
	if (side == "cortex")
		return ai.GetCircuitDef(corawac);
	if (side == "legion")
		return ai.GetCircuitDef(legwhisper);
	return ai.GetCircuitDef(armawac);
}

// A bot lab is worth having early for one reason above all others: it is the
// ONLY source of a resurrection bot. armrectr/cornecro/legrezbot are 130 metal
// and no other factory in the game can make them.
const int BOTLAB_FROM = 8 * MINUTE;

// Rez bots to keep once we own a lab.
//
// Measured, one 8v8: stock's rez spend was 32,890 against our 436, and we never
// built a single rez bot in 27 minutes. Resurrection returns the UNIT, not scrap
// -- an army that gets rebuilt off the field beats one that gets reclaimed for
// metal, which is exactly the kill-exchange gap we keep losing.
//
// By name, not by role: BuilderManager routes these through UseAs::REZZER, but
// the config ROLES disagree across factions ("support" for Armada and Legion,
// "rezzer" for Cortex), so GetRoleDef is not a reliable way to ask for one.
const int REZ_FLOOR    = 8;
// apexearth: "a rezbot costs like what, 130 metal?... so for every 500
// wrecked metal seen make 1 rezbot???" armrectr is 130m; 500 leaves real
// margin (a rez bot earns back multiples of its own cost per wreck it
// actually processes) rather than breaking even on the first pile it finds.
const float REZ_METAL_PER_BOT = 500.f;
const int REZ_SPACING  = 20 * SECOND;
int gNextRez = 0;
int gNextRezDiag = 0;  // temporary diagnostic, see the rez-bot armed check below
int gNextFactoryDiag = 0;  // temporary diagnostic, see the AiMakeTask entry log below
int gNextT2GateBlockLog = 0;  // temporary diagnostic, see AiIsSwitchAllowed's FollowerEconomyReady check

// HaveT1BotLab() only clears once CCircuitDef::count increments, which happens
// at the nanoframe -- construction actually starting, not the build order
// being issued. A constructor sent to place a lab still has to walk there
// first, and every OTHER idle constructor offered AiGetFactoryToBuild during
// that walk also reads !HaveT1BotLab() and picks the same lab. Observed live,
// team 2 in matches/watch-comet-catcher-4v4-8: six separate corlab placements,
// two of them 92 frames (~3s) apart, while mCon/armyReal/metalProduced were
// all rising the whole time -- not combat replacement, just uncoordinated
// duplicate requests. This cooldown closes the gap the same way REZ_SPACING
// closes the rez-bot one: once a lab request is handed out, no second one
// within BOTLAB_REQUEST_COOLDOWN, whether or not HaveT1BotLab() has cleared
// yet. Short enough to not delay a genuine rebuild after a real loss -- a lab
// destroyed mid-game is gone for many minutes, not 45 seconds.
const int BOTLAB_REQUEST_COOLDOWN = 45 * SECOND;
int gNextBotLabRequest = 0;
string armrectr("armrectr"); string cornecro("cornecro"); string legrezbot("legrezbot");

CCircuitDef@ RezBotDef()
{
	const string side = ai.GetSideName();
	if (side == "cortex")
		return ai.GetCircuitDef(cornecro);
	if (side == "legion")
		return ai.GetCircuitDef(legrezbot);
	return ai.GetCircuitDef(armrectr);
}

// False once the pooling strategy has been given up on (Military::RUSH_GIVEUP).
// The rush branch below returns null rather than producing army, so a lead that
// never reaches T2 would otherwise sit out the entire game building nothing.
bool RushWindowOpen()
{
	return ai.frame <= Military::RUSH_GIVEUP;
}

// Re-read at most once a second. Un-cached, this ran a string concatenation and
// an engine callback on EVERY IsTechLead() -- 15 call sites, several on hot
// paths -- including from inside Builder::AiUnitAdded, which ai.GiveUnits
// invokes re-entrantly while it is transferring a unit. A second is far shorter
// than any takeover deadline, so the role still moves promptly.
int gLeadCheckedAt = -1000;

// Lowest team id in the ally roster. Every instance computes the same answer
// from the same roster with no signalling, so all of them know whose blackboard
// slot carries the election result.
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

// Only the elector runs this, and it publishes under its OWN slot.
void RunElection()
{
	array<Id>@ mates = ai.GetTeamIds();
	if (mates is null)
		return;

	const uint quota = TechLeadQuota();

	// Incumbents first. A slot is kept while its holder still has a plant or a
	// nanoframe, or is still able to pay for one -- reopening only on a genuine
	// loss is what stops the role flapping between two teams whose progress is
	// neck and neck.
	//
	// Deliberately NOT bounded by Military::RUSH_GIVEUP: that made retention
	// unconditional past 15 min, so a lead that lost its plant kept the slot
	// and it never reopened. TV_ADV already tracks the loss live.
	array<int> leads;
	for (uint s = 0; s < quota; ++s) {
		const int held = int(ai.ReadTeamValue(ai.teamId, LeadKey(s), -1.f));
		if (held < 0)
			continue;
		if ((ai.ReadTeamValue(held, TV_ADV, -1.f) > 0.f)
			|| (ai.ReadTeamValue(held, TV_READY, 0.f) > 0.f))
		{
			leads.insertLast(held);
		}
	}

	// Fill whatever is left. Committed teams rank first, by how far along their
	// plant is; then, for slots still empty, the FURTHEST-BACK team that could
	// afford one -- the player who goes helpless should be the one least likely
	// to be attacked while it is. Richest-that-is-ready ignored position
	// entirely, which is how the front-line player ended up teching.
	while (leads.length() < quota) {
		int best = -1;
		float bestProgress = 0.f;
		for (uint i = 0; i < mates.length(); ++i) {
			const int t = int(mates[i]);
			if (IsInLeadList(leads, t))
				continue;
			const float p = ai.ReadTeamValue(t, TV_ADV, -1.f);
			if (p <= 0.f)
				continue;   // has not committed to an advanced plant
			if ((p > bestProgress) || ((p == bestProgress) && (t < best))) {
				bestProgress = p;
				best = t;
			}
		}
		if (best < 0) {
			float bestDist = -1.f;
			for (uint i = 0; i < mates.length(); ++i) {
				const int t = int(mates[i]);
				if (IsInLeadList(leads, t))
					continue;
				if (ai.ReadTeamValue(t, TV_READY, 0.f) <= 0.f)
					continue;   // cannot afford it anyway
				const float d = ai.ReadTeamValue(t, TV_DIST, 0.f);
				if ((d > bestDist) || ((d == bestDist) && (best >= 0) && (t < best))) {
					bestDist = d;
					best = t;
				}
			}
		}
		if (best < 0)
			break;   // no further candidate; leave the slot empty
		leads.insertLast(best);
	}

	for (uint s = 0; s < quota; ++s)
		ai.PublishTeamValue(LeadKey(s), (s < leads.length()) ? float(leads[s]) : -1.f);
}

bool IsInLeadList(const array<int>@ leads, int team)
{
	for (uint i = 0; i < leads.length(); ++i) {
		if (leads[i] == team)
			return true;
	}
	return false;
}

// BUILD_PHASE, per docs/12-build-phases.md (apexearth's design). Diagnostic
// only: computes and logs a phase number so a future session can check it
// against real telemetry before gating any existing rule behind it. Gating
// rules is the actual fix for the crowding-out pattern this session
// independently reconfirmed five times (see notes/open-issues.md, "SESSION
// SYNTHESIS") -- this is deliberately NOT that yet. Doing that blind, this
// late in an unsupervised session, risks becoming "one more && on rules that
// still all want to fire", which the design doc itself names as the way this
// fails to help.
//
// Driven from STATE per the doc's own first rule (never a clock), so it can
// fall back down on its own the moment a signal drops -- no ratchet, no
// separate distress flag needed, because nothing is being latched here.
// Thresholds are a first approximation from constants already used elsewhere
// in this file (RUSH_MIN_METAL-scale for pre-T2, FUSION_KEEP for pre-T3) --
// calibrate against composition.py's own per-phase breakdown once telemetry
// exists, per the doc's measurement plan.
int gLastPhase = -1;
int gNextPhaseLog = 0;

bool HaveGantry()
{
	CCircuitDef@ d = Builder::SideDef3(armshltx, corgant, leggant);
	return (d !is null) && (d.count > 0);
}

// Income that stands in for "four mexes" and "one mex" of economic power. A T1
// mex yields roughly 2-3 metal/s, so four is about 10.
const float PHASE_BUILDUP_INCOME = 10.f;
const float PHASE_EXPAND_INCOME  = 3.f;

int ComputePhase()
{
	const float mInc = aiEconomyMgr.metal.income;
	const uint mex = MexCount();
	const uint fusions = Builder::gFusions.length();
	const bool hasT3 = HaveGantry();

	if (hasT3 || (fusions >= 3))
		return (hasT3 && (fusions >= 3)) ? 7 : 6;          // T3 / late
	if (gHaveT2 && (fusions >= 1 || mInc >= 40.f))
		return 5;                                          // pre-T3
	if (gHaveT2)
		return 4;                                          // T2
	if (MayPursueT2() && RushReady())
		return 3;                                          // pre-T2
	// ECONOMIC POWER, not mex count. apexearth: "we should never gate purely on
	// mex count. you can gate by economic power."
	//
	// A count is the wrong measure twice over: it ignores where the metal is
	// actually coming from (reclaim, converters, a richer spot), and it traps a
	// player that cannot expand. Measured: t0 and t3 sat at 2 mexes and phase 1
	// for thirty minutes, and phase 1 is below every economic rule in the AI --
	// the whole cluster needs phase >= 4 -- so they could not build the economy
	// that would have got them out. Mex count is kept only as an alternative way
	// to reach the rung, never as the sole way.
	// NO mex-count clause, not even as an alternative route to the rung.
	// apexearth, twice: "we should never gate purely on mex count", then
	// "remember, NO gates based on mex count. DO NOT DO THAT."
	if (mInc >= PHASE_BUILDUP_INCOME)
		return 2;                                          // build up
	if (mInc >= PHASE_EXPAND_INCOME)
		return 1;                                          // expand
	return 0;                                              // opening
}

void UpdatePhase()
{
	const int phase = ComputePhase();
	if ((phase != gLastPhase) || (ai.frame >= gNextPhaseLog)) {
		gNextPhaseLog = ai.frame + 60 * SECOND;
		AiLog(T() + "apexphase: " + gLastPhase + " -> " + phase
			+ " mInc=" + formatFloat(aiEconomyMgr.metal.income, "", 0, 0)
			+ " mex=" + MexCount() + " haveT2=" + (gHaveT2 ? "1" : "0")
			+ " fusions=" + Builder::gFusions.length());
		gLastPhase = phase;
	}
}

// Driven from AiUpdate, so every instance publishes on a fixed cadence.
// Publishing as a side effect of RushLeadTeamId() instead would make a team's
// visibility depend on which code paths happened to ask for the lead that tick,
// and a team that went quiet would look like it had lost its plant.
void UpdateTeamCoord()
{
	UpdatePhase();
	// gHaveT2 latches on in AiUnitAdded and had no way back down, but the
	// branch that REBUILDS an advanced plant is gated on !gHaveT2 -- so a
	// player whose lab died still read "we have T2" and could never start
	// another. Recomputed here rather than in AiUnitRemoved because that hook
	// gives no guarantee the dying unit has left the def yet; on this cadence
	// it self-corrects either way.
	if (gHaveT2 && !AnyAdvPlant())
		gHaveT2 = false;
	ai.PublishTeamValue(TV_ADV, OwnAdvProgress());
	ai.PublishTeamValue(TV_READY, RushReady() ? aiEconomyMgr.metal.income : 0.f);
	ai.PublishTeamValue(TV_DIST, Builder::gHomeSet
			? Builder::gHomePos.distance2D(aiEnemyMgr.GetEnemyPos()) : 0.f);
	ai.PublishTeamValue(TV_MEX, UpdateMexHold());
	ai.PublishTeamValue(TV_FILL, (aiEconomyMgr.metal.storage > 0.f)
			? aiEconomyMgr.metal.current / aiEconomyMgr.metal.storage : 0.f);
	if (ElectorTeamId() == ai.teamId)
		RunElection();
	UpdateEcoLead();
}

// Extractors we hold, counting one under construction as still held.
//
// An upgrade REPLACES the unit: the T1 extractor is destroyed and an advanced
// one is laid down in its place, so a plain unit count reads every upgrade as a
// lost mex for the whole build -- 14,100 build time for legmoho. The eco lead
// upgrades more mexes than anyone on its team, so the release condition fired
// hardest on the player doing the most of what the role exists to do.
//
// GetDefBuildProgress reports the best progress toward a def and -1 when none is
// being built, so a nanoframe of any advanced extractor credits one back. It
// cannot distinguish two simultaneous upgrades; the sustain window below covers
// what this does not.
uint MexCount()
{
	uint n = 0;
	for (uint i = 0; i < MEX_DEFS.length(); ++i) {
		CCircuitDef@ d = ai.GetCircuitDef(MEX_DEFS[i]);
		if (d is null)
			continue;
		n += uint(d.count);
		if (IsAdvancedMex(i) && (ai.GetDefBuildProgress(d) > 0.f))
			++n;
	}
	return n;
}

// MEX_DEFS holds the three T1 extractors first, then the three advanced ones.
// Only the advanced half is credited: a T1 mex under construction is expansion,
// not an upgrade, and counting it would inflate the peak we measure against.
bool IsAdvancedMex(uint i)
{
	return i >= 3;
}

// What share of our peak extractor count we still hold. Peak-tracked here rather
// than recomputed at each reader, so the peak advances exactly once per update.
// Until the peak is meaningful this reports full health rather than a ratio off
// two or three opening mexes.
int gLastMexGrowth = 0;   // frame gPeakMex was last raised

float UpdateMexHold()
{
	const uint mex = MexCount();
	if (mex > gPeakMex) {
		gPeakMex = mex;
		gLastMexGrowth = ai.frame;
	}
	gMexHold = (gPeakMex < HURT_MIN_MEX) ? 1.f : (float(mex) / float(gPeakMex));
	if (gMexHold >= HURT_SELF_FRAC)
		gHurtSince = -1;
	else if (gHurtSince < 0)
		gHurtSince = ai.frame;
	gHurt = (gHurtSince >= 0) && ((ai.frame - gHurtSince) >= HURT_SUSTAIN);
	return gMexHold;
}

// Detects a player boxed in -- out of reachable expansion for its CURRENT
// move type, not merely "the map has some water". apexearth, watching an
// 8v8 live: a player started on a small strip of land, chose bots, and
// stood doing nothing once local mexes ran out, with an ocean it could not
// build ships on (no shipyard, bots-only) and mexes on a nearby hill it
// could not reach (no air con) -- IsMixedWaterMap() gates the shipyard
// trigger on the MAP's average land%, which reads "mostly land" and never
// fires for a player boxed onto a small peninsula regardless of THEIR own
// situation. No terrain-height query is registered to script (checked
// vendor/engine/.../InitScript.cpp), so a true geometric "am I landlocked"
// test would need a new C++ binding -- too large a change to add blind this
// late in an unsupervised session, especially after this session's own
// experience with an under-tested C++ addition crashing the engine.
//
// This is the binding-free alternative: detect the SYMPTOM instead of the
// geometric cause. A player with spare build capacity whose mex count has
// not grown in a long time, well past the opening, is out of reachable
// expansion for SOME reason -- water, cliffs, an enemy wall, a hill --
// and trying an alternative move type (naval here; air is the harder case,
// left for a future session per the note below) is a reasonable response
// regardless of which reason it is.
const int   STALL_MIN_FRAME  = 6 * MINUTE;   // let the opening actually happen first
const int   STALL_DURATION   = 3 * MINUTE;   // no mex growth for this long
const uint  STALL_MIN_MEX    = 2;            // had at least a normal opening

bool ExpansionStalled()
{
	if (ai.frame < STALL_MIN_FRAME)
		return false;
	if (gPeakMex < STALL_MIN_MEX)
		return false;
	return (ai.frame - gLastMexGrowth) >= STALL_DURATION;
}

// Is any ALLY being killed? Read straight off their own published share -- each
// team is the only one that can count its own extractors.
bool AlliesHurting()
{
	array<Id>@ mates = ai.GetTeamIds();
	if (mates is null)
		return false;
	for (uint i = 0; i < mates.length(); ++i) {
		const int t = int(mates[i]);
		if (t == ai.teamId)
			continue;
		if (ai.ReadTeamValue(t, TV_MEX, 1.f) < HURT_ALLY_FRAC)
			return true;
	}
	return false;
}

// The eco lead is the PRIMARY tech lead, not a separate election. It is already
// chosen for exactly the properties the eco player wants -- furthest from the
// enemy, able to pay -- and it is already the sling target, so the team's spare
// metal is already going there.
// Whether the role is allowed on a team under BIG_TEAM.
//
// Off by default, and the reason is measured: on a four-player team a player
// fielding no army is a quarter of the army missing, which is the same
// arithmetic that bars the air opening and the constructor monopoly there
// (standing army 17.8k against 25.4k, real K/D 0.70 against 1.24).
//
// RE-TESTED 2026-08-02 against the current, much stronger role and the verdict
// held. Six 4v4 games each way, same three maps and seeds, only this flag
// differing: OFF went 2-1 on 904,267 metal and 166,643 army; ON went 0-4 on
// 516,702 metal and 80,671 army, and its games ended SOONER (41 min against 48)
// -- it is not slower, it is dead earlier. Build power, converters and air
// constructors do not buy back the quarter of the team that stops fighting.
const bool ECO_ON_SMALL_TEAMS = false;

bool IsEcoLead()
{
	if (IsSmallTeam() && !ECO_ON_SMALL_TEAMS)
		return false;
	return IsDesignatedLead() && (ai.teamId == RushLeadTeamId());
}

// Resolved once per update and cached: EcoLeadActive() is read from three files,
// one of them CBuilderManager's task hook, and this walks the ally roster.
void UpdateEcoLead()
{
	const bool was = gEcoActive;
	if (IsEcoLead())
		gEcoSlotSeen = ai.frame;
	const bool mine = (ai.frame - gEcoSlotSeen) <= ECO_ROLE_GRACE;
	const bool allies = mine && AlliesHurting();

	// Military::gTurtle is deliberately NOT a condition here, for the same reason
	// LosingGround() is not: the hold fires when our own army SHRINKS, and this
	// player builds no army, so it can neither avoid the hold nor recover from
	// it. Measured in the same run: HOLD at 8.7 min on army 1897 -> 1266, RESUME
	// only at 15.0 on army 110 -- the maximum hold, six minutes, expiring rather
	// than recovering. As a gate it removed the role from the game.
	gEcoActive = mine && !gHurt && !allies;

	// Which gate is holding it off, sampled while we hold the slot. The first
	// version of this role was elected and then never activated for a whole
	// game, and there was no way to tell from the log which of four conditions
	// was responsible -- so state them rather than guessing at them later.
	if (mine && !gEcoActive && (ai.frame >= gNextEcoGateLog)) {
		gNextEcoGateLog = ai.frame + 60 * SECOND;
		AiLog(T() + "apex: eco lead held off"
			+ " ourMex=" + formatFloat(gMexHold, "", 0, 2)
			+ " allyDying=" + (allies ? "1" : "0"));
	}

	if (gEcoActive == was)
		return;
	if (gEcoActive) {
		gEcoLoggedFor = ai.teamId;
		AiLog(T() + "apex: ECO LEAD -- no army, economy only");
	} else if (gEcoLoggedFor == ai.teamId) {
		AiLog(T() + "apex: eco lead standing down"
			+ (gHurt ? " (losing our own mexes)"
			 : allies ? " (an ally is dying)" : " (role lost)"));
	}
}

bool EcoLeadActive()
{
	return gEcoActive;
}

// Has the late game arrived? Either the clock, or a fusion standing -- a reactor
// IS the late game economically, whenever it turns up.
bool LateGame()
{
	return (ai.frame >= LATE_GAME_FRAME) || (Builder::gFusions.length() > 0);
}

string armca("armca");   string corca("corca");   string legca("legca");

CCircuitDef@ AirConDef()
{
	const string side = ai.GetSideName();
	if (side == "cortex")
		return ai.GetCircuitDef(corca);
	if (side == "legion")
		return ai.GetCircuitDef(legca);
	return ai.GetCircuitDef(armca);
}

int AirConCount()
{
	CCircuitDef@ d = AirConDef();
	return (d is null) ? 0 : d.count;
}

// Any aircraft plant of ours, basic or advanced. AIR_FAC already names all six.
bool HaveAirFactory()
{
	for (uint i = 0; i < AIR_FAC.length(); ++i) {
		CCircuitDef@ d = ai.GetCircuitDef(AIR_FAC[i]);
		if ((d !is null) && (d.count > 0))
			return true;
	}
	return false;
}

// The eco lead's aircraft plant exists to make CONSTRUCTORS, not an air force,
// which is why it is not gated on MayOpenAir(): that rule is about who fights in
// the air, and bars the tech lead outright. This asks for a plant only once the
// economy is large enough that ground engineers are the thing holding it back.
bool EcoWantsAirPlant()
{
	return gEcoActive && gHaveT2 && !HaveAirFactory()
		&& (aiEconomyMgr.metal.income >= ECO_AIR_PLANT_INCOME);
}

// The ally holding least of its own peak, whatever the bar. Used when the team
// is under pressure but nobody is dying yet: somebody still has it worst, and
// they are the one to push metal at.
int LowestHoldAlly()
{
	array<Id>@ mates = ai.GetTeamIds();
	if (mates is null)
		return -1;
	int worst = -1;
	float worstHold = 2.f;
	for (uint i = 0; i < mates.length(); ++i) {
		const int t = int(mates[i]);
		if (t == ai.teamId)
			continue;
		const float hold = ai.ReadTeamValue(t, TV_MEX, 1.f);
		if (hold < worstHold) {
			worstHold = hold;
			worst = t;
		}
	}
	return worst;
}

// The ally in the worst trouble, by its own published share of peak extractors,
// or -1 when nobody is under the bar. Used for aid, so it deliberately reads the
// same number the release condition does.
int NeediestAlly()
{
	array<Id>@ mates = ai.GetTeamIds();
	if (mates is null)
		return -1;
	int worst = -1;
	float worstHold = HURT_ALLY_FRAC;
	for (uint i = 0; i < mates.length(); ++i) {
		const int t = int(mates[i]);
		if (t == ai.teamId)
			continue;
		const float hold = ai.ReadTeamValue(t, TV_MEX, 1.f);
		if (hold < worstHold) {
			worstHold = hold;
			worst = t;
		}
	}
	return worst;
}

// Refresh the primary lead and whether THIS team holds any lead slot. Both come
// off one cadence because they read the same blackboard: un-cached this ran a
// string concatenation and an engine callback on every IsTechLead().
void RefreshLead()
{
	if (ai.frame < gLeadCheckedAt + 1 * SECOND)
		return;
	gLeadCheckedAt = ai.frame;

	// Read the ELECTOR's slots, not our own, and never anything keyed on
	// ai.allyTeamId: that read 0 for every instance in the shipped DLL, which
	// had ally 1 pooling behind ally 0's lead.
	const int elector = ElectorTeamId();
	const uint quota = TechLeadQuota();
	bool mine = false;
	for (uint s = 0; s < quota; ++s) {
		if (int(ai.ReadTeamValue(elector, LeadKey(s), -1.f)) == ai.teamId) {
			mine = true;
			break;
		}
	}
	if (mine != gAmLead) {
		AiLog(T() + "apex: tech lead role " + (mine ? "TAKEN" : "released")
			+ " (quota " + quota + ")");
		gAmLead = mine;
	}

	const int lead = int(ai.ReadTeamValue(elector, TV_LEAD, -1.f));
	// Nobody has committed yet. Keep the last known lead if we ever had one,
	// rather than reporting "nobody".
	if (lead < 0)
		return;

	// Not latched here: the elector can hand a slot over if its holder loses its
	// plant before the give-up frame.
	if (lead != gRushLead) {
		AiLog(T() + "apex: tech lead "
			+ ((gRushLead < 0) ? "= team " + lead
			                   : "CHANGED team " + gRushLead + " -> " + lead));
		gRushLead = lead;
		// gT1Reclaimed is deliberately NOT cleared: the reclaim stays one-shot
		// per instance.
	}
}

// Is the lead saturated -- i.e. is a donation now just overflow?
bool LeadIsSaturated(int lead)
{
	return ai.ReadTeamValue(lead, TV_FILL, 0.f) >= SLING_STOP_FILL;
}

// Has the lead got the plant the pooling was paying for?
bool LeadHasPlant(int lead)
{
	return ai.ReadTeamValue(lead, TV_ADV, -1.f) >= 1.f;
}

// The PRIMARY lead (slot 0). Slinging and the air lead want a single target, not
// the whole set -- donations split across two leads fund neither.
int RushLeadTeamId()
{
	RefreshLead();
	return (gRushLead >= 0) ? gRushLead : ai.GetLeadTeamId();
}

string armmoho ("armmoho");
string cormoho ("cormoho");
string legmoho ("legmoho");

// One advanced extractor standing. A T2 mex is roughly a 300% increase on that
// spot's metal and pays for the next constructor by itself, so it comes before
// a second constructor and before the T1.5 defence rung.
bool gHaveT2Mex = false;   // latched: an upgraded mex does not un-upgrade

bool HaveT2Mex()
{
	if (gHaveT2Mex)
		return true;
	const string side = ai.GetSideName();
	CCircuitDef@ moho = ai.GetCircuitDef((side == "cortex") ? cormoho
	                                   : ((side == "legion") ? legmoho : armmoho));
	gHaveT2Mex = (moho !is null) && (moho.count > 0);
	return gHaveT2Mex;
}

bool IsTechLead()
{
	RefreshLead();
	if (gAmLead)
		return true;
	// Nobody has been elected yet: defer to the engine's own pick, exactly as
	// this did when there was only ever one slot.
	return !LeadIsDesignated() && (ai.teamId == RushLeadTeamId());
}

// Has anyone actually been designated yet?
//
// Until the gadget publishes one, RushLeadTeamId falls back to
// ai.GetLeadTeamId() -- the engine's ally leader, which is always the lowest
// team id. That made team 0 declare itself the rusher at frame 0, so it was the
// only player that ever tried to tech, so it was always first to commit, so it
// was always elected. Observed live: blue built the first advanced plant every
// single game, even when green was richer and ready sooner. "Whoever commits
// first" had quietly collapsed into "team 0".
bool LeadIsDesignated()
{
	return ai.ReadTeamValue(ElectorTeamId(), TV_LEAD, -1.f) >= 0.f;
}

// May THIS instance pursue the advanced plant?
//
// Before anyone is designated the answer is "whoever is ready" -- that is the
// whole point of selecting on commitment rather than prediction, and RushReady
// already demands a real economy behind it. Once someone is designated, only
// they continue, so the team pools behind one player instead of four.
bool MayPursueT2()
{
	// Only the designated lead. The elector now designates on READINESS as well as
	// commitment, so there is no window where nobody holds the title and everyone
	// is therefore free to spend. "Whoever is ready" was open to all of them at
	// once. This cannot deadlock the way gating on commitment did: that needed a
	// plant nobody was allowed to start, whereas readiness is earned by the economy
	// growing. The frame clause is a backstop only -- past it the rush window is
	// over and followers are released anyway.
	// The release used to be a clock, and the clock is what let everyone in: past
	// FOLLOWER_TECH_FRAME this returned true for every player at once, and the
	// rush branch then asked only for RUSH_MIN_METAL. A non-lead now earns T2
	// with its economy instead of by waiting.
	return IsDesignatedLead() || FollowerEconomyReady();
}

// Am I the ACTUAL designated lead? Distinct from IsTechLead(), which is true for
// team 0 from frame 0 via the fallback. Role behaviour -- suppressing our army,
// being the sling target, skipping defence -- must key on this, or team 0 idles
// its army from the opening and the whole team feeds it before anyone has
// earned the role.
bool IsDesignatedLead()
{
	return LeadIsDesignated() && IsTechLead();
}

// Minimum METAL income before committing to T2. The energy gates below say
// "can we power a plant"; nothing said "can we afford to be the player the whole
// team pools behind". Measured on Quicksilver 4v4: apex committed at 2.9 min on
// 6.0 metal/s while stock waited until 9.1 min on 35.9, and apex lost. A lead
// that cannot feed itself turns the pooling into one starving player plus three
// donors. apexearth: "don't do T2 unless you got like fourteen metal per second
// ... instead we just have one useless team member".
const float RUSH_MIN_METAL = 14.f;

bool RushReady()
{
	if (aiEconomyMgr.metal.income < RUSH_MIN_METAL)
		return false;
	return (aiEconomyMgr.energy.income > RUSH_ENERGY_TARGET)
		|| ((ai.frame > RUSH_LATEST) && (aiEconomyMgr.energy.income > RUSH_ENERGY_FLOOR));
}

// Metal a NON-LEAD must be making before it may take T2. This constant existed
// and was never read by anything -- the follower routes all gated on metal 18 or
// on nothing at all.
//
// apexearth, watching an 8v8: "if someone is not rushing T2 then they really
// need more metal and energy income before they try for it ... ~25+ metal per
// second along with ~600+ energy".
const float FOLLOWER_TECH_INCOME = 25.f;
// Was 13 min, tuned when the lead itself only reached T2 around 20. The lead now
// has its plant at a median of 6.3 min and starts handing out advanced
// constructors well before 13, so holding followers that long leaves them
// sitting on cons they are not allowed to use. Measured: followers teched at
// 15-21 min while the rusher was done at 5.4.
// Tried 9 minutes, on the reasoning that the lead now techs at 6.3 so followers
// should not wait until 13. Measured across 5 maps it went the wrong way: real
// K/D fell from ~1.00 to 0.64 and standing army from 19.3k to 15.9k, because
// each follower started its OWN advanced plant during the window where the team
// still has to hold the ground -- which is the "4 AI all trying to make T2 =
// SLOW" failure this whole pooling strategy exists to avoid. Followers get T2
// from the constructors the lead hands them, not from their own factories.
// THE economy bottleneck, found by comparing composition: stock builds 14,625
// metal of T2 units to apex's 4,595 and upgrades 2.9 mexes to our 1.4. The
// pooling design gets ONE player to T2 quickly, but stock's everyone-techs-
// independently ends up with far more T2 economy in total -- measured, three of
// four followers still read haveT2=0 at eighteen minutes while earning 30-73
// metal/s. A fast tech lead is worthless if it is the team's only one.
//
// 9 minutes was tried before and looked bad, but that measurement contained the
// duplicate-factory bug (AiIsSwitchTime held permanently open), so it is void.
// Tried 10 minutes to unblock follower teching. It did NOT work: t2Mex moved
// 1.4 -> 1.5 and T2 unit spend 4,595 -> 4,652, i.e. nothing, while the run lost
// 4-13 with the CI excluding 50%. So the clock was never the blocker.
//
// What actually blocks a follower is the SAME stock gate that once blocked the
// lead, in AiIsSwitchAllowed below: armyCost > 1.2 x cost x facCount, or the
// full plant cost banked. A follower never holds 2800 metal, so it never techs
// whatever the clock says. The lead only escapes because the rush branch above
// grants it a no-bank switch. Giving followers an equivalent -- place it and
// pour income in -- is the actual fix, and is untested.
// Retested at 10 now that the metal gate below is released. The earlier 10-min
// test was CONFOUNDED: followers were blocked by AiIsSwitchAllowed's bank
// requirement whatever the clock said, so moving the clock could not show an
// effect and t2Mex went 1.4 -> 1.5. With the gate open the clock is finally the
// binding constraint, and followers still convert only 7.7k of T2 against
// stock's 12.2k -- they tech, but too late to compound.
const int   FOLLOWER_TECH_FRAME  = 10 * MINUTE;

// Energy a FOLLOWER must be making before it may take T2. An advanced plant and
// its units are energy-hungry, and teching on a thin grid stalls the base rather
// than growing it -- followers were being granted T2 on metal alone.
//
// Deliberately above what the AI currently reaches: measured across a 20-minute
// 4v4, energy income ran ~130/s at 5 min, ~290 at 8 and ~415 at 14. Those peaks
// are low BECAUSE energy was under-prioritised, which the raised
// economy.energy.factor is meant to correct; this bar is what the economy should
// clear, not what it clears today. If followers stop teching at all, that is the
// factor being too low, not this number being wrong -- check eInc in the T2GATE
// log before lowering it.
const float FOLLOWER_TECH_ENERGY = 600.f;

// May a non-lead take an advanced plant yet? Both halves, because teching on
// metal alone stalls the base rather than growing it.
//
// This replaces a pure clock. The clock is what produced the stampede: every
// follower gate was bounded by FOLLOWER_TECH_FRAME, so at ten minutes they all
// expired at once and the rush branch below granted T2 to anyone holding
// RUSH_MIN_METAL. Measured, 8v8 Supreme Isthmus: seven of eight players
// committed to an advanced plant, five of them inside fifteen minutes, and
// every single one did it at 14-16 metal/s. Army share came out 19.3% against
// stock's 31.7% and T1 spend 11,671 against 26,879.
bool FollowerEconomyReady()
{
	return (aiEconomyMgr.metal.income >= FOLLOWER_TECH_INCOME)
		&& (aiEconomyMgr.energy.income >= FOLLOWER_TECH_ENERGY);
}


enum Attr {
	T1 = 0x0001, T2 = 0x0002, T3 = 0x0004, T4 = 0x0008
}

class SUserData {
	SUserData(int a) {
		attr = a;
	}
	SUserData() {}
	int attr = 0;
}

// Example of userData per UnitDef
array<SUserData> userData(ai.GetDefCount() + 1);

string armlab  ("armlab");
string armalab ("armalab");
string armvp   ("armvp");
string armavp  ("armavp");
string armsy   ("armsy");
string armasy  ("armasy");
string armap   ("armap");
string armaap  ("armaap");
string armshltx("armshltx");

string corlab  ("corlab");
string coralab ("coralab");
string corvp   ("corvp");
string coravp  ("coravp");
string corsy   ("corsy");
string corasy  ("corasy");
string corap   ("corap");
string coraap  ("coraap");
string corgant ("corgant");

string leglab  ("leglab");
string legalab ("legalab");
string legvp   ("legvp");
string legavp  ("legavp");
string legsy   ("legsy");
string legap   ("legap");
string legaap  ("legaap");
string leggant ("leggant");

string armshltxuw("armshltxuw");
string corgantuw ("corgantuw");

int switchInterval = MakeSwitchInterval();

// The cheapest body THIS factory can actually make. Scout first, then raider:
// armlab answers armflea, corlab has no scout unit and falls through to corak,
// leglab answers leggob. Military::IsFodder is the gate, so a factory whose
// cheapest option is not actually cheap returns null and the caller buys the
// assault mainstay as before.
CCircuitDef@ Fodder(const CCircuitDef@ facDef)
{
	CCircuitDef@ d = aiFactoryMgr.GetRoleDef(facDef, Unit::Role::SCOUT.type);
	if (Military::IsFodder(d))
		return d;
	@d = aiFactoryMgr.GetRoleDef(facDef, Unit::Role::RAIDER.type);
	if (Military::IsFodder(d))
		return d;
	return null;
}

// A screen only defends if it stays home. Without this, a newly built screen
// fighter got a normal military task and was sent to attack alone like any
// other AA-role unit. apexearth, watching an 8v8 live: "I see us making air
// and immediately sending them into the enemy to die. Can't be using air like
// this... you build fighters, you leave them in your base to defend your
// base." Same mechanism as Air::HoldsUnit -- returning null from
// Military::AiMakeTask leaves the unit idle, and an idle unit still
// auto-fires on anything that comes into weapon range, so parking at home IS
// the defence.
//
// Skipped for the air lead: Air:: already owns the lifecycle of its own
// aircraft (held pre-strike, released at Air::Release()), and the advanced
// AA-role def can be the exact same def the assassin escort flies -- an
// unconditional hold here would trap the escort right after release.
//
// Restricted to big teams. LateGame() goes true off EITHER the 25-minute
// clock OR any fusion existing -- and this AA-role check is not scoped to
// only the freshly-recruited screen floor, it holds EVERY unit of that
// role, including ones already mid-fight. On a 25-minute-capped 4v4 with
// the phase-gated economy now pushing tech faster, a fusion before the
// cap is plausible, and this session's dominant finding is that any new
// unconditional behavior change costs the benchmark. Diagnosed entirely
// from 8v8 observation; gating it there matches earlyReaction/stalled in
// factory.as, both restricted for the same reason.
bool HoldsLateFighter(CCircuitUnit@ unit)
{
	if (IsSmallTeam() || !LateGame() || Air::IsAirLead())
		return false;
	const CCircuitDef@ cdef = unit.circuitDef;
	return (cdef !is null) && cdef.IsAbleToFly() && cdef.IsRoleAny(Unit::Role::AA.mask);
}

IUnitTask@ AiMakeTask(CCircuitUnit@ unit)
{
	// Diagnostic for the "factory goes idle with a full bank" reports:
	// distinguishes this hook still being called and declining every branch
	// from it not being called at all. See CHANGES.md 2026-08-06.
	if (ai.frame >= gNextFactoryDiag) {
		gNextFactoryDiag = ai.frame + 30 * SECOND;
		AiLog(T() + "apex: factory-diag " + unit.circuitDef.GetName()
			+ " mInc=" + formatFloat(aiEconomyMgr.metal.income, "", 0, 1)
			+ " mCur=" + formatFloat(aiEconomyMgr.metal.current, "", 0, 0)
			+ " mStor=" + formatFloat(aiEconomyMgr.metal.storage, "", 0, 0)
			+ " isMetalFull=" + (aiEconomyMgr.isMetalFull ? "1" : "0")
			+ " hasTask=" + ((unit.task !is null) ? "1" : "0"));
	}

	// Nano turrets register with the FACTORY manager (CFactoryManager keeps
	// assistants alongside factories), so they arrive here -- but every branch
	// below is written about a factory choosing what to RECRUIT, and none can
	// produce a valid task for one. Several end in `return null`, and for an
	// assistant that means no task at all: CFactoryManager::DefaultMakeTask is
	// the only thing that routes it to CreateAssistTask. The eco lead's block
	// is the worst case -- an unconditional `return null` for anything that is
	// not an air plant or a constructor-capable factory -- which left every
	// turret that player owned permanently idle. apexearth, watching an 8v8
	// live: "blue's turrets are not doing anything at all"; blue was team 0,
	// the eco lead. Hand assistants straight to DefaultMakeTask.
	CCircuitDef@ nano = Builder::NanoDef();
	if ((nano !is null) && (unit.circuitDef.id == nano.id))
		return aiFactoryMgr.DefaultMakeTask(unit);

	// Safe to sit first: this answers only for the advanced air plant, so the
	// ground line's branches below are untouched.
	IUnitTask@ air = Air::MakeFactoryTask(unit);
	if (air !is null)
		return air;

	// Rez bots from the bot lab, before anything else that lab would make --
	// but only once there is something to reclaim or resurrect. apexearth,
	// watching a Comet Catcher 4v4 live: "we build rez bots before we build
	// anything else. Resurrection bots are certainly useful, but at t zero,
	// it's not important. It isn't really important until you have stuff to
	// reclaim or to resurrect." At game start nothing has died on either
	// side, so this floor was competing HIGH-priority for the bot lab's very
	// first slots against the opening mex/army push for a benefit that does
	// not exist yet. Gated on the same wreck search EnqueueWreckReclaim
	// already uses (WRECK_SEARCH/WRECK_MIN in builder.as) rather than a
	// clock: it self-corrects the moment the first skirmish or scout death
	// actually produces something worth reclaiming, instead of guessing a
	// fixed early-game delay.
	//
	// Placed high (once armed) for the same reason the fighter floor is: it
	// is a floor, not a strategy, and the branches below it -- the catch-up
	// push, the constructor line -- would otherwise take every slot the lab
	// has.
	if (HaveT1BotLab() && (ai.frame >= gNextRez)) {
		CCircuitDef@ lab = T1BotLab();
		CCircuitDef@ rez = RezBotDef();
		if ((lab !is null) && (rez !is null) && (unit.circuitDef.id == lab.id)
			&& rez.IsAvailable(ai.frame))
		{
			// Replaced the binary "is there a wreck at all" armed-check, then
			// a scaled-but-still-blind-query version. Root cause found: found
			// via SSkirmishAICallbackImpl::getFeaturesIn -- the non-cheat path
			// is `GetCallBack(id)->GetFeatures(...)`, which is LOS-gated, not
			// a plain spatial query. There is no unit standing at home or at
			// an enemy-centroid midpoint, so those queries return empty no
			// matter the radius -- confirmed live: even a 50000-elmo sanity
			// radius from home returned wreckValueHuge=0 in a game with
			// mKillReal in the thousands. This matches the project's other
			// LOS/vision-gated-callback surprises.
			//
			// Fix: stop querying from a point with no vision. Every mobile
			// builder already scans WRECK_RICH_R around itself for the
			// "rich corpse pile" check every ~3s (builder.as); that scan DOES
			// have vision, because a unit is standing right there. It now
			// records what it sees via Builder::NoteWreckSeen, and this reads
			// the sighting back instead of taking its own blind sample.
			// apexearth: "if theres any reclaim we've seen on the map...
			// start making some... a rezbot costs like what, 130 metal?...
			// so for every 500 wrecked metal seen make 1 rezbot???" REZ_FLOOR
			// still caps the ceiling so a battlefield's worth of corpses
			// cannot balloon this past a sane standing count.
			const float wreckValue = Builder::WreckSeenValue();
			const int wantByReclaim = int(wreckValue / REZ_METAL_PER_BOT);
			const int want = (wantByReclaim < REZ_FLOOR) ? wantByReclaim : REZ_FLOOR;
			if (ai.frame >= gNextRezDiag) {
				gNextRezDiag = ai.frame + 15 * SECOND;
				AiLog(T() + "apex: rez-diag lab=" + (lab !is null ? lab.GetName() : "null")
					+ " rez=" + (rez !is null ? rez.GetName() : "null")
					+ " rezCount=" + (rez !is null ? rez.count : -1)
					+ " wreckSeen=" + formatFloat(wreckValue, "", 0, 0)
					+ " want=" + want);
			}
			if (rez.count < want) {
				IUnitTask@ rec = aiFactoryMgr.Enqueue(TaskS::Recruit(
						Task::RecruitType::BUILDPOWER, Task::Priority::HIGH,
						rez, unit.GetPos(ai.frame), 0.f));
				if (rec !is null) {
					gNextRez = ai.frame + REZ_SPACING;
					return rec;
				}
			}
		}
	}

	// Radar planes in the late game, to find what is left.
	//
	// apexearth: "when we're clearly winning we should make T2 radar planes and
	// find the last com so we know where to send our armies." A surviving
	// commander rebuilds, and a won game that runs another fifteen minutes is
	// how that happens.
	//
	// Recruited directly rather than left to the factory ratios: armawac and
	// corawac appear ONLY in the advanced air plant's list (0.05/0.0), and that
	// plant is exactly the one that does not get built -- every sample of a
	// hosted 11v13 read plants=1,0. Legion's legwhisper is not in behaviour.json
	// at all, so it has no role and no ratio anywhere. Naming the def sidesteps
	// all three problems and covers every faction.
	if (IsAirFactory(unit.circuitDef) && LateGame() && (ai.frame >= gNextScout)) {
		CCircuitDef@ eye = RadarPlaneDef();
		if ((eye !is null) && eye.IsAvailable(ai.frame) && (eye.count < LATE_SCOUTS)) {
			IUnitTask@ rec = aiFactoryMgr.Enqueue(TaskS::Recruit(
					Task::RecruitType::FIREPOWER, Task::Priority::NORMAL,
					eye, unit.GetPos(ai.frame), 0.f));
			if (rec !is null) {
				gNextScout = ai.frame + LATE_SCOUT_SPACING;
				return rec;
			}
		}
	}

	// A standing fighter screen in the late game, from ANY air plant we own.
	//
	// Above every other branch, including the eco lead's constructor line: this
	// is a floor of eight aircraft, not a strategy, and the whole point is that
	// it is never the thing that gets skipped. Air::MakeFactoryTask keeps
	// priority over it because the assassin strike is timed and this is not.
	//
	// GetRoleDef(AA) returns whatever THIS plant can build -- the T1 plant's
	// fighter, or Hawk/Vamp/Venator from the advanced one -- so it never asks for
	// an aircraft the factory cannot make.
	if (IsAirFactory(unit.circuitDef) && LateGame() && (ai.frame >= gNextFighter)) {
		CCircuitDef@ fig = aiFactoryMgr.GetRoleDef(unit.circuitDef, Unit::Role::AA.type);
		if ((fig !is null) && (fig.count < LATE_FIGHTERS)) {
			IUnitTask@ rec = aiFactoryMgr.Enqueue(TaskS::Recruit(
					Task::RecruitType::FIREPOWER, Task::Priority::HIGH,
					fig, unit.GetPos(ai.frame), 0.f));
			if (rec !is null) {
				gNextFighter = ai.frame + LATE_FIG_SPACING;
				return rec;
			}
		}
	}

	// aiMilitaryMgr.quota.attack only caps how many units get SENT to attack; it
	// does not stop the factory building them. Measured: the rusher's standing
	// army grew 240 -> 3400 metal while its bank sat at 1 metal, so every sling
	// its allies sent was converted straight into T1 units instead of into the
	// plant. Idle the line outright once the rush window is open, until the
	// advanced plant exists.
	// Do NOT simply idle here. Measured on Comet Catcher: the lead sat with
	// rushReady since 5.0 min and its bank climbing to 2261 unspent metal, and
	// still placed no plant until 13.9 min. The blocker is ENERGY, not metal --
	// EconomyManager checks (engyFactor < energyPower) and returns before it ever
	// consults IsSwitchAllowed, and unlike the metal check that branch is not
	// bypassed by isSwitchTime. So banked metal is simply wasted metal here.
	//
	// Turn it into build power instead: more constructors means solars and
	// converters go up faster, which is the thing the gate is actually waiting
	// on. Those constructors are also exactly what we need afterwards to upgrade
	// mexes and to hand to allies.
	// CAPPED. This had no limit at all: it recruited a constructor on every
	// factory decision from RushReady until the advanced plant existed, which on
	// an 8v8 is the entire rush window. Observed live -- the player going for T2
	// sitting on 15-20 T1 constructors. That is thousands of metal in build power
	// that cannot be spent, buying nothing, at exactly the moment the team has
	// pooled everything behind this player.
	//
	// A handful is enough to finish a plant quickly; past that each one is pure
	// waste. GetWorkerCount() is the engine's own count of our builders, so this
	// counts what we actually hold rather than what we have ever ordered.
	if (MayPursueT2() && !gHaveT2 && RushReady() && !IsSmallTeam()
		&& RushWindowOpen())
	{
		// Cap AND spacing: the cap alone cannot hold, because GetWorkerCount()
		// only sees finished builders (see RUSH_CON_SPACING above).
		if ((aiBuilderMgr.GetWorkerCount() < RUSH_CON_CAP)
			&& (ai.frame >= gNextConOrder))
		{
			CCircuitDef@ con = aiFactoryMgr.GetRoleDef(unit.circuitDef, Unit::Role::BUILDER.type);
			if (con !is null) {
				IUnitTask@ rec = aiFactoryMgr.Enqueue(TaskS::Recruit(
						Task::RecruitType::BUILDPOWER, Task::Priority::HIGH,
						con, unit.GetPos(ai.frame), 0.f));
				if (rec !is null) {
					gNextConOrder = ai.frame + RUSH_CON_SPACING;
					return rec;
				}
			}
		}
		return null;   // never fall through to army production during the rush
	}

	// The tech lead buys roughly four or five minutes of T2 before the enemy
	// catches up, and spending that on one advanced tank is close to wasting it.
	// Spent on constructors it compounds instead: ours upgrades our own mexes,
	// and every one handed to an ally lets them upgrade theirs -- T2 mexes are
	// four times the metal, across the whole team, for the rest of the game.
	// So build nothing but build power until every teammate has one.
	// Both overrides are for BIG teams only. On a four-player team the rusher
	// producing no army at all is a quarter of the team's army missing -- the
	// same arithmetic that rules out an air player on a 4v4. Measured across 5
	// maps: standing army 17.8k against stock's 25.4k and real K/D 0.70 against
	// 1.24, while the tech lead itself was up 8 minutes. A tech lead that cannot
	// hold the ground it techs on does not convert. Small teams keep stock
	// production and lean on quota.attack = RUSH_SKIP_T1_SMALL to stay eco-first.
	// Small teams were excluded after enabling this at NOW priority lost 3-13 with
	// t2Mex falling 3.2 -> 1.8. That test conflated two separate things: sharing
	// constructors at all, versus MONOPOLISING the factory line to do it. NOW
	// means the lead builds nothing else, which a four-player team cannot afford.
	// Observed live with sharing off: "we went t2 but didn't share any cons" and
	// then all four built their own advanced plants late -- the expensive outcome
	// that sharing exists to prevent. So share everywhere, but only pre-empt the
	// line on a big team.
	// Two reasons to build an advanced constructor, and the second was missing.
	// The lead builds them to SHARE, which is the design. But anyone who reaches
	// T2 and holds no advanced con needs one for themselves -- otherwise a
	// follower that techs while the designated lead does not ends up with a T2
	// plant and nothing to upgrade mexes with. Observed in an 8v8: a player
	// finished its advanced lab at 10:01 and immediately built Banishers, mobile
	// radars and a Tiger, while the team upgraded ZERO mexes in 45 minutes.
	// Instrumented because four mex upgrades across eight players (stock: 96) and
	// zero gifts means this branch is barely firing, and guessing which of five
	// conditions fails has already wasted a run. Log every input, once per 30s.
	if (ai.frame >= gNextConLog) {
		gNextConLog = ai.frame + 30 * SECOND;
		CCircuitDef@ probe = aiFactoryMgr.GetRoleDef(unit.circuitDef, Unit::Role::BUILDER.type);
		AiLog(T() + "conbranch fac=" + unit.circuitDef.GetName()
			+ " haveT2=" + (gHaveT2 ? "1" : "0")
			+ " lead=" + (IsTechLead() ? "1" : "0")
			+ " owes=" + (Builder::OwesAdvCons() ? "1" : "0")
			+ " haveCon=" + (Builder::gHaveAdvCon ? "1" : "0")
			+ " roleDef=" + ((probe is null) ? "NULL" : probe.GetName()));
	}
	// Behind on the field, with T2 and a mex upgraded: pour income into the cheap
	// mainstay rather than anything else. apexearth, watching a game lost from a
	// winning tech position: "if we just built T1 labs and spammed out a lot of
	// those Thug units, that would be enough to turn the tide, and it would be
	// way cheaper". GetRoleDef(ASSAULT) returns whatever THIS factory can make --
	// Thug from a bot lab, Brute from a vehicle plant -- so it never asks for a
	// unit the factory cannot build.
	//
	// Spaced, for the same reason RUSH_CON_SPACING exists: Enqueue does not dedup
	// and the cap it would otherwise respect only counts finished units.
	// Was T1 factories ONLY, on the reasoning that the advanced plant returns
	// Reaper and Bulldog -- "exactly the expensive T2 units this is meant to avoid
	// buying while behind". That reasoning is inverted once the enemy has teched.
	//
	// apexearth, watching: "we're throwing t one units at t two and t three armies
	// ... they just get absolutely demolished by pretty much everything the enemy
	// is fielding, so they're almost like a complete waste of space and effort."
	//
	// It was also self-reinforcing. This branch bypasses the factory tier weights
	// entirely -- it asks GetRoleDef(ASSAULT) directly -- so losing produced Stumpy
	// spam, which lost harder, which produced more: measured at 18.1% of all metal
	// in one 8-game run, against stock's 2.0%. Cutting the tier weights could not
	// touch it, because this path never reads them.
	//
	// Once we hold T2, the advanced plant answers instead. Expensive units are the
	// point when the cheap ones cannot trade.
	const bool isT1Fac =
		((Factory::userData[unit.circuitDef.id].attr & (Factory::Attr::T2 | Factory::Attr::T3)) == 0);
	const bool isT2Fac =
		((Factory::userData[unit.circuitDef.id].attr & Factory::Attr::T2) != 0);
	// !gEcoActive: the eco lead is BY CONSTRUCTION behind on the field -- it
	// fields no army, so LosingGround() is true for it permanently, and this
	// branch would otherwise be the one thing that turns its whole income into
	// units. Its own release conditions are what decide when it fights.
	// The economic gates (HaveT2Mex, ARMY_PUSH_MIN_INCOME) apply to the ADVANCED
	// plant only. They are the right test for a T2 unit and exactly the wrong
	// one for the case this rule exists to catch: a player being overrun loses
	// its mexes and its income first, so both gates go false precisely when it
	// is losing hardest, and the push is switched off for the only players that
	// need it. Measured in a 4v4: t2Mex stayed 0 all game for three of four apex
	// players and income peaked at 17 and 11 for the two that died, so "behind
	// on the field" fired 6x and 4x for the two healthy players and NEVER for
	// the two that were being killed. Fodder from a T1 lab is cheap enough that
	// a collapsing player can still pay for it, which is the whole point.
	const bool advPushOk = isT2Fac && HaveT2Mex()
			&& (aiEconomyMgr.metal.income >= ARMY_PUSH_MIN_INCOME);
	if (!gEcoActive && (isT1Fac ? !gHaveT2 : advPushOk) && Military::LosingGround()
		&& (ai.frame >= gNextArmyPush))
	{
		// Spam means SPAM. apexearth: "i said long ago to make spam units when
		// we're dying. a stumpy is not a spam unit." TODO.md is specific -- ticks,
		// grunts, pawns, rascals, wheelies, "the cheap but fast units", whose
		// purpose is vision and distraction.
		//
		// This asked for the ASSAULT role two pushes in three, which is the
		// mainstay tank: armstump for a vehicle plant. So "spam when dying" bought
		// 180-metal tanks that trade badly against a teched enemy, and displaced
		// the real army while doing it -- 18.1% of all metal in one 8-game run.
		//
		// Now split by what the factory IS: a T1 lab makes fodder, the advanced
		// plant makes the army that can actually trade.
		++gArmyPushCount;
		CCircuitDef@ want = null;
		if (isT1Fac)
			@want = Fodder(unit.circuitDef);
		else
			@want = aiFactoryMgr.GetRoleDef(unit.circuitDef, Unit::Role::ASSAULT.type);
		if (want !is null) {
			IUnitTask@ rec = aiFactoryMgr.Enqueue(TaskS::Recruit(
					Task::RecruitType::FIREPOWER, Task::Priority::HIGH,
					want, unit.GetPos(ai.frame), 0.f));
			if (rec !is null) {
				gNextArmyPush = ai.frame + ARMY_PUSH_SPACING;
				if (ai.frame >= gNextArmyLog) {
					gNextArmyLog = ai.frame + 30 * SECOND;
					AiLog(T() + "apex: behind on the field, massing " + want.GetName()
						+ " army=" + formatFloat(aiMilitaryMgr.armyCost, "", 0, 0)
						+ " enemyArmy=" + formatFloat(Military::EnemyArmyCost(), "", 0, 0));
				}
				return rec;
			}
		}
	}

	if (gHaveT2 && ((IsDesignatedLead() && Builder::OwesAdvCons()) || !Builder::gHaveAdvCon)) {
		// BUILDER, not BUILDER2. builderT2 is registered as a SUBROLE of builder
		// (AiAddRole("builderT2", BUILDER.type)) and the factory role map is
		// indexed by BASE roles only -- FactoryManager.cpp:1057 looks up
		// ROLE_TYPE(BUILDER) itself. Asking for BUILDER2 returned NULL every time,
		// so this branch silently fell through to normal production: a plant would
		// finish and immediately build Banishers and radars while the team upgraded
		// no mexes at all. For an advanced plant the base builder IS the advanced
		// constructor -- coravp's only builder is coracv.
		CCircuitDef@ con = aiFactoryMgr.GetRoleDef(unit.circuitDef, Unit::Role::BUILDER.type);
		if (con !is null) {
			IUnitTask@ rec = aiFactoryMgr.Enqueue(TaskS::Recruit(
					Task::RecruitType::BUILDPOWER,
					IsSmallTeam() ? Task::Priority::NORMAL : Task::Priority::NOW,
					con, unit.GetPos(ai.frame), 0.f));
			if (rec !is null)
				return rec;
		}
	}

	// The eco lead's factory. Build power while it is short of it, then nothing
	// at all -- an idle line is the point, not a failure. Every unit this factory
	// does not make is income the builders spend on mexes, energy and the T2/T3
	// economy instead, which is the entire reason the role exists.
	//
	// This sits AFTER the advanced-constructor branch above deliberately: handing
	// advanced cons to the rest of the team is the tech lead's job and the eco
	// lead is still the tech lead. It only replaces what would otherwise be army.
	// The advanced air plant can only be built by an AIR constructor, and the T1
	// air plant's own ratios give constructors about 5% -- so a player can hold
	// the air slot all game and never produce one. Without the advanced plant
	// there are no fighters at all, because FactoryManager's isAvailableDef
	// requires (isActive || IsAttrRare()) and isActive goes false for a T1
	// factory the moment its owner has any T2 factory. Fighters are not rare.
	// One constructor unlocks the plant; after that the ratios decide.
	if (IsAirFactory(unit.circuitDef) && (AirConCount() < AIR_CON_MIN)
		&& (ai.frame >= gNextEcoAirCon))
	{
		CCircuitDef@ acon = aiFactoryMgr.GetRoleDef(unit.circuitDef, Unit::Role::BUILDER.type);
		if (acon !is null) {
			IUnitTask@ rec = aiFactoryMgr.Enqueue(TaskS::Recruit(
					Task::RecruitType::BUILDPOWER, Task::Priority::NORMAL,
					acon, unit.GetPos(ai.frame), 0.f));
			if (rec !is null) {
				gNextEcoAirCon = ai.frame + ECO_AIR_SPACING;
				return rec;
			}
		}
	}

	// A gantry is the declared win condition, and the eco lead builds no army by
	// design -- so a gantry it came by, built or resurrected, produced nothing at
	// all. It has no BUILDER-role unit either, so the constructor branch below
	// cannot absorb it and it falls through to `return null` every call.
	// apexearth: "our eco guy ressurrected a gantry and then never made any unit
	// from it". Owning one overrides the rule.
	CCircuitDef@ gantDef = T3Gantry();
	const bool isOwnGantry = (gantDef !is null)
			&& (unit.circuitDef.id == gantDef.id);

	if (gEcoActive && !isOwnGantry) {
		// The aircraft plant makes constructors and nothing else. Every other
		// branch above has already had its say, so reaching here with an air
		// factory means this player has one purely as build power.
		if (IsAirFactory(unit.circuitDef)) {
			if ((AirConCount() < ECO_AIR_CON_CAP) && (ai.frame >= gNextEcoAirCon)) {
				CCircuitDef@ acon = aiFactoryMgr.GetRoleDef(unit.circuitDef, Unit::Role::BUILDER.type);
				if (acon !is null) {
					IUnitTask@ rec = aiFactoryMgr.Enqueue(TaskS::Recruit(
							Task::RecruitType::BUILDPOWER, Task::Priority::NORMAL,
							acon, unit.GetPos(ai.frame), 0.f));
					if (rec !is null) {
						gNextEcoAirCon = ai.frame + ECO_AIR_SPACING;
						return rec;
					}
				}
			}
			return null;
		}
		// GetWorkerCount() counts every worker we own, and a nano turret IS one --
		// observed live, the eco lead logged cons=25 against a cap of 16 while
		// standing on eleven turrets. Left alone, the rectangle eats the mobile
		// constructor budget and the player ends up with turrets and nobody to
		// walk to the next mex. Count the turrets back out.
		if ((int(aiBuilderMgr.GetWorkerCount()) - Builder::NanoCount() < int(ECO_CON_CAP))
			&& (ai.frame >= gNextEcoCon))
		{
			CCircuitDef@ con = aiFactoryMgr.GetRoleDef(unit.circuitDef, Unit::Role::BUILDER.type);
			if (con !is null) {
				IUnitTask@ rec = aiFactoryMgr.Enqueue(TaskS::Recruit(
						Task::RecruitType::BUILDPOWER, Task::Priority::NORMAL,
						con, unit.GetPos(ai.frame), 0.f));
				if (rec !is null) {
					gNextEcoCon = ai.frame + ECO_CON_SPACING;
					return rec;
				}
			}
		}
		if (ai.frame >= gNextEcoLog) {
			gNextEcoLog = ai.frame + 60 * SECOND;
			AiLog(T() + "apex: eco lead idle line, cons="
				+ aiBuilderMgr.GetWorkerCount()
				+ " mInc=" + formatFloat(aiEconomyMgr.metal.income, "", 0, 1)
				+ " eInc=" + formatFloat(aiEconomyMgr.energy.income, "", 0, 0));
		}
		return null;
	}

	// An air plant that Air:: did not claim above falls through to
	// DefaultMakeTask like every other factory.
	//
	// This used to return null for ANY air factory unless the air role had been
	// permanently abandoned, on the reasoning that every sanctioned use of an air
	// plant claims it earlier in this function. That reasoning holds only for the
	// air lead's plants while it is armed. It is false for the air-slot opener,
	// which is never the lead (the lead is elected on highest income and the
	// opener has the worst economy on the team), and it is false for the lead
	// itself whenever Air:: declines -- quota met, enemy AA too high, not yet
	// committed. In all of those cases the plant produced NOTHING, permanently.
	//
	// apexearth: "our air player made just 1 con and thats it... air lab just
	// sitting there doing nothing else", then "i bet we have some special flag or
	// branching path of logic that is breaking our air opening player", then
	// "Can we not have this whole Air::RoleAbandoned logic in here? I bet that is
	// the cause of a lot of air labs i see sitting there doing nothing."
	//
	// The concern this originally answered -- trickling bombers one at a time
	// into enemy AA -- is about how bombers are USED, not about starving every
	// air plant on the team.
	return aiFactoryMgr.DefaultMakeTask(unit);
}

void AiTaskAdded(IUnitTask@ task)
{
}

void AiTaskRemoved(IUnitTask@ task, bool done)
{
}

// The lead's own T1 lab, kept so it can be fed back into the T2 plant.
// gT1Reclaimed is declared with the other rush state above, because
// RushLeadTeamId() clears it on a handover and AngelScript resolves globals in
// declaration order.
CCircuitUnit@ gT1FacUnit = null;

// How many factories THIS instance currently has standing, of any kind or
// tier. Nothing in this codebase asked "do we have any factory at all" --
// grepped, zero hits for BuildType::FACTORY logic anywhere in builder.as --
// so a player that lost its last one had no way back. See HaveAnyFactory()
// and its use in the commander branch below.
int gFactoryCount = 0;

void AiUnitAdded(CCircuitUnit@ unit, Unit::UseAs usage)
{
	if (usage == Unit::UseAs::FACTORY)
		++gFactoryCount;
	if ((Factory::userData[unit.circuitDef.id].attr & Factory::Attr::T2) != 0)
		gHaveT2 = true;
	if ((Factory::userData[unit.circuitDef.id].attr & Factory::Attr::T3) != 0)
		gHaveT3 = true;
	if ((usage == Unit::UseAs::FACTORY)
		&& ((Factory::userData[unit.circuitDef.id].attr & Factory::Attr::T2) == 0))
	{
		@gT1FacUnit = unit;
		AiLog(T() + "apex: T1 lab on field: " + unit.circuitDef.GetName());
	}
//	if (!factories.empty() || (this->circuit->GetBuilderManager()->GetWorkerCount() > 2)) return;
	if (usage != Unit::UseAs::FACTORY)
		return;

	const CCircuitDef@ facDef = unit.circuitDef;
	if (userData[facDef.id].attr & Attr::T3 != 0) {
		// if (ai.teamId != ai.GetLeadTeamId()) then this change affects only target selection,
		// while threatmap still counts "ignored" here units.
// 		AiLog("ignore newly created armpw, corak, armflea, armfav, corfav");
		array<string> spam = {"armpw", "corak", "armflea", "armfav", "corfav", "leggob", "legscout"};
		for (uint i = 0; i < spam.length(); ++i) {
			CCircuitDef@ cdef = ai.GetCircuitDef(spam[i]);
			if (cdef !is null)
				cdef.SetIgnore(true);
		}
	}

	if (Air::SuppressesOpener(facDef))
		return;

	const array<Opener::SO>@ opener = Opener::GetOpener(facDef);
	if (opener is null)
		return;

	const AIFloat3 pos = unit.GetPos(ai.frame);
	for (uint i = 0, icount = opener.length(); i < icount; ++i) {
		CCircuitDef@ buildDef = aiFactoryMgr.GetRoleDef(facDef, opener[i].role);
		if ((buildDef is null) || !buildDef.IsAvailable(ai.frame))
			continue;

		Task::Priority priority;
		Task::RecruitType recruit;
		if (opener[i].role == Unit::Role::BUILDER.type) {
			priority = Task::Priority::NORMAL;
			recruit  = Task::RecruitType::BUILDPOWER;
		} else {
			priority = Task::Priority::HIGH;
			recruit  = Task::RecruitType::FIREPOWER;
		}
		for (uint j = 0, jcount = opener[i].count; j < jcount; ++j)
			aiFactoryMgr.Enqueue(TaskS::Recruit(recruit, priority, buildDef, pos, 64.f));
	}
}

void AiUnitRemoved(CCircuitUnit@ unit, Unit::UseAs usage)
{
	if (usage == Unit::UseAs::FACTORY)
		--gFactoryCount;
	// CCircuitUnit is registered NOCOUNT, so a handle is not nulled when the
	// engine destroys the unit and `is null` stays false on freed memory.
	// Leaving this unset crashed UpdateRushReclaim's Enqueue (0xc0000005).
	if (gT1FacUnit is unit)
		@gT1FacUnit = null;
}

// Any factory at all, of any kind or tier -- not just the T1 opener.
// apexearth, watching a Comet Catcher 4v4 live: "something still seems to
// make our AI go super dumb and just stop making any progress... it feels
// more like we disappeared." Traced with tools/spending_timeline.py: a
// player's last factory died at exactly the minute its spending (T1/T2/
// factories/defence, all of it) flatlined to zero, and its commander then
// did nothing for the next three minutes -- banking metal it never spent --
// before dying to an ambush. See the commander branch in builder.as, which
// is the only place this matters: any other builder that could have used
// this is, by definition of the state being checked, already dead.
bool HaveAnyFactory()
{
	return gFactoryCount > 0;
}

void AiLoad(IStream& istream)
{
}

void AiSave(OStream& ostream)
{
}

/*
 * New factory switch condition; switch event is also based on eco + caretakers.
 */
// Every AiLog line was unanchored in time, so a log could show the rush firing
// while saying nothing about *when* -- which is the only thing that matters for a
// deadline of "T2 before 10 minutes". Stamp everything.
// Log prefix: game time AND team id.
//
// Every AI instance on the map writes to one infolog behind the same
// "Skirmish AI <BARbarIAn Apex-apex>:" prefix, so without the team id four
// players' lines are indistinguishable. That made the questions this strategy
// actually raises -- who is the lead, who is slinging, who teched first --
// unanswerable from a log, and forced them to be guessed at instead. Prefix
// every line and they become a per-team timeline. tools/trace_flow.py parses it.
string T()
{
	return "[" + formatFloat(float(ai.frame) / float(MINUTE), "", 0, 1) + "m t"
		+ ai.teamId + "] ";
}

// Periodic dump of every input the rush decision reads, so a slow tech can be
// attributed to a specific gate rather than guessed at. One line per 30s.
// The T1 lab is ~600-900 metal standing idle -- the rush already stops it
// producing, so it is pure banked metal doing nothing. Feed it into the plant it
// is being replaced by; a T1 lab can be rebuilt later once T2 economy is up.
void UpdateRushReclaim()
{
	if (gT1Reclaimed || gHaveT2 || !IsTechLead() || !RushWindowOpen())
		return;
	if (gT1FacUnit is null)
		return;
	// The advanced plant must EXIST, not merely have been chosen.
	// AiGetFactoryToBuild returning it is a preference; placement came minutes
	// later. Eating the T1 lab in that gap leaves the lead with no factory, and
	// CircuitAI answers by building a fresh T1 one -- observed live: vehicle lab
	// reclaimed, bot lab built, T2 plant only minutes after that.
	// CCircuitDef::count is incremented in RegisterTeamUnit, which runs for the
	// nanoframe, so this is true as soon as construction actually starts.
	CCircuitDef@ adv = AdvCounterpart();
	if ((adv is null) || (adv.count <= 0))
		return;
	gT1Reclaimed = true;
	AiLog(T() + "apex: reclaiming T1 lab " + gT1FacUnit.circuitDef.GetName()
		+ " into the advanced plant");
	aiBuilderMgr.Enqueue(TaskB::Reclaim(Task::Priority::HIGH, gT1FacUnit));
}

int gNextRushLog = 0;
void LogRushState()
{
	if (ai.frame < gNextRushLog)
		return;
	gNextRushLog = ai.frame + 30 * SECOND;

	const bool lead = IsTechLead();
	if (!lead && gHaveT2)
		return;   // followers that already teched are not interesting

	const bool rushReady = RushReady();
	CCircuitDef@ adv = AdvCounterpart();
	const float advCost = (adv is null) ? 0.f : adv.costM;

	AiLog(T() + "rush team=" + ai.teamId + (lead ? " LEAD" : " follower")
		+ " haveT2=" + (gHaveT2 ? "1" : "0")
		+ " eInc=" + formatFloat(aiEconomyMgr.energy.income, "", 0, 0)
		+ "/" + formatFloat(RUSH_ENERGY_TARGET, "", 0, 0)
		+ " mInc=" + formatFloat(aiEconomyMgr.metal.income, "", 0, 0)
		+ " mCur=" + formatFloat(aiEconomyMgr.metal.current, "", 0, 0)
		+ "/" + formatFloat(advCost * 0.5f, "", 0, 0)
		+ " rushReady=" + (rushReady ? "1" : "0")
		+ " facs=" + aiFactoryMgr.GetFactoryCount()
		+ " army=" + formatFloat(aiMilitaryMgr.armyCost, "", 0, 0));
}

int gNextSwitchProbe = 0;
int gNextConLog = 0;
const int T3_MAX_PROBES = 4;   // bounded: enough to place one gantry, never a pile
int gT3Probes = 0;
int gNextT3Probe = 0;

bool AiIsSwitchTime(int lastSwitchFrame)
{
	// THE bug behind late teching: MakeSwitchInterval() is AiRandom(550,900)
	// seconds, so the AI only *considers* a factory change every 9-15 minutes.
	// The rush override was correct but never got asked -- hence T2 at 22.9m
	// instead of before 10. While the designated rusher still lacks T2, let it
	// reconsider every tick.
	// Returning true on EVERY call was a real bug, not just noise. In
	// EconomyManager the same flag disables the metal gate:
	//   if ((metalFactor < factoryPower) && !isSwitchTime && ...) return nullptr;
	// so a permanently-true isSwitchTime means the AI starts another factory
	// whenever it holds any metal at all. Observed live: one AI with THREE T1
	// bot labs. The intent was only to stop the stock 9-15 minute reconsider
	// interval from making the rush unreachable, which a short probe interval
	// achieves without leaving the gate open.
	// MayPursueT2, not IsTechLead. This probe is what makes teching reachable at
	// all -- the stock interval is AiRandom(550,900) seconds -- and gating it on
	// IsTechLead handed team 0 a probe every 10s while everyone else waited 9-15
	// minutes. Blue therefore built the first advanced plant in every game
	// regardless of income, because nobody else was ever asked. RushReady still
	// demands >= 14 metal/s before anything is actually placed.
	if (MayPursueT2() && !gHaveT2) {
		if (ai.frame < gNextSwitchProbe)
			return false;
		gNextSwitchProbe = ai.frame + 10 * SECOND;
		return true;
	}
	// T3 probe REMOVED after measurement, not after theorising. Bounded probing
	// worked mechanically -- 3645 metal of T3 fielded, the first time this AI has
	// ever reached T3, against stock's 0 -- and lost 4-12 with the CI excluding
	// 50%. Metal fell 136k -> 88k and army 25k -> 13k: a gantry plus its units
	// costs more than the game gives back at these income levels, and the match
	// is decided long before the investment pays.
	//
	// The doctrine is not wrong; the economy is not yet big enough to afford its
	// win condition. T3 belongs behind an economy that can carry it, which means
	// the eco half has to come good FIRST. Re-enable this only alongside a
	// measured economy that outpaces stock's ~136k.
	// Everyone should at least be trying for T2 by ~20 minutes.
	if (!gHaveT2 && (ai.frame > 20 * MINUTE))
		return true;
	if (Air::WantsSwitchProbe())
		return true;
	if (lastSwitchFrame + switchInterval <= ai.frame) {
		switchInterval = MakeSwitchInterval();
		return true;
	}
	return false;
}

bool AiIsSwitchAllowed(CCircuitDef@ facDef)
{
	// First, ahead of the non-lead guard below. The advanced air plant carries the
	// T2 attribute, so FollowerEconomyReady would refuse it on any grid under
	// FOLLOWER_TECH_ENERGY -- and the air assassin is by construction not a
	// designated tech lead, so that guard applies to it. Place it and pour income
	// in, same as the rush plant.
	if (Air::WantsFactory(facDef)) {
		aiFactoryMgr.isAssistRequired = Economy::isSwitchAssist = true;
		return true;
	}
	// One guard for every non-lead route to an advanced plant.
	//
	// It has to be a single early guard rather than a clause on the no-bank
	// branch below, because a non-lead has FOUR routes to T2 in this function --
	// the no-bank branch, the turtle branch, and both halves of the stock
	// fallback -- and every one of them grants it on metal alone, or in the
	// turtle case on banked metal with no income test whatsoever. Gating one
	// leaves the others open.
	//
	// This used to be two guards, both bounded by ai.frame < FOLLOWER_TECH_FRAME,
	// which is what produced the stampede: at ten minutes both expired for
	// everyone simultaneously and the whole team teched on RUSH_MIN_METAL. The
	// bound is now the economy, so a player is held until it can actually carry
	// a second tech base and released the moment it can.
	//
	// LeadIsDesignated() is load-bearing, not belt-and-braces. Gate every
	// non-lead and nobody can start a plant, so nobody becomes lead, so nobody
	// can start a plant. That deadlock was measured: the first election landed at
	// 10.5 min in two runs -- the frame the old gate opened -- against a 5.7 min
	// baseline. It cannot recur here, because the elector designates on TV_READY
	// (published from RushReady, no plant required) as well as on commitment, so
	// slots fill without anyone having to spend first.
	if (LeadIsDesignated() && !IsDesignatedLead()
		&& ((Factory::userData[facDef.id].attr & Factory::Attr::T2) != 0)
		&& !FollowerEconomyReady())
	{
		// The "T2GATE reached" log below only fires on the PASSING path, so a
		// player permanently short of the bar left no record of how short.
		if (ai.frame >= gNextT2GateBlockLog) {
			gNextT2GateBlockLog = ai.frame + 60 * SECOND;
			AiLog(T() + "T2GATE blocked FollowerEconomyReady"
				+ " eInc=" + formatFloat(aiEconomyMgr.energy.income, "", 0, 0)
				+ "/" + formatFloat(FOLLOWER_TECH_ENERGY, "", 0, 0)
				+ " mInc=" + formatFloat(aiEconomyMgr.metal.income, "", 0, 1)
				+ "/" + formatFloat(FOLLOWER_TECH_INCOME, "", 0, 1));
		}
		return false;
	}
	// The designated player is rushing: buy T2 as soon as the metal is on hand,
	// without the stock army-value requirement. It is not meant to be
	// contributing T1 army at all, so that requirement can never be met.
	// Was 0.5 * factory cost banked (~1450 metal). The rusher never holds that
	// much because it spends as the slings arrive, so the plant did not start
	// until 12 min. It does not need the whole cost up front -- construction
	// draws from income, and seven feeders keep paying into it.
	// Measured, 8v8 Glitters: energy cleared the rush bar at 5.0 min and stayed
	// clear, but the bank sat at 1-120 metal for the entire game against a
	// required 1400 (0.5 * plant cost), so this branch never once fired. The
	// requirement was never reachable -- metal income is ~13/s and every point of
	// it is spent as it arrives. Banking is the wrong model anyway: in BAR you
	// place the plant and pour income into the nanoframe. So place it on zero
	// metal and let income, seven slinging allies and assisting builders finish
	// it. isAssistRequired is now true for exactly that reason -- with no bank,
	// build power is the only thing that closes the gap.
	if (MayPursueT2() && !gHaveT2 && RushReady()
		&& ((Factory::userData[facDef.id].attr & Factory::Attr::T2) != 0))
	{
		// EconomyManager returns before this on (engyFactor < energyPower) and on
		// the sticky isEnergyRequired, neither of which isSwitchTime bypasses.
		// This line marks the frame we were actually reached on.
		AiLog(T() + "T2GATE reached IsSwitchAllowed"
			+ " lead=" + (IsDesignatedLead() ? "1" : "0")
			+ " eInc=" + formatFloat(aiEconomyMgr.energy.income, "", 0, 0)
			+ " mInc=" + formatFloat(aiEconomyMgr.metal.income, "", 0, 1));
		aiFactoryMgr.isAssistRequired = Economy::isSwitchAssist = true;
		return true;
	}
	if (Military::gTurtle && (aiEconomyMgr.metal.current > facDef.costM * 0.6f)) {
		aiFactoryMgr.isAssistRequired = Economy::isSwitchAssist = false;
		return true;
	}
	// T3 is this variant's declared win condition and it has NEVER been fielded:
	// zero across every measured game, while stock manages 670 with no T3 logic
	// at all. AiGetFactoryToBuild already asks for the gantry -- the request dies
	// here. The stock gate wants either armyCost > 1.2x cost x facCount or the
	// full cost banked, and a gantry runs several thousand metal, so neither is
	// reachable for an eco variant that deliberately holds a modest army.
	//
	// Same reasoning as the T2 plant: you do not bank for a factory in BAR, you
	// place it and pour income into it. Require a real economy behind it rather
	// than a pile of metal, and turn assist ON so builders actually finish it --
	// with no bank, build power is the only thing that closes the gap.
	if (WantMoreGantries() && ((userData[facDef.id].attr & Attr::T3) != 0)
		&& T3Worthwhile())
	{
		aiFactoryMgr.isAssistRequired = Economy::isSwitchAssist = true;
		return true;
	}
	// Followers could never tech. Measured: 4.6k of T2 unit spend against stock's
	// 11-14k, 1.4 mex upgrades against 2.5-2.9, and three of four followers still
	// reading haveT2=0 at eighteen minutes while earning 30-73 metal/s. Releasing
	// the clock changed nothing, which proved the clock was never the blocker --
	// this gate is. It wants armyCost > 1.2x cost x facCount or the full plant
	// cost banked, and a follower holds neither.
	//
	// The lead escapes this via the rush branch above. Give followers the same
	// once the pooling window has closed: place the plant on income rather than
	// banking for it, with assist on so build power finishes it. Pooling behind
	// one player is only worth it if the others follow afterwards.
	// Staggering by team id was tried and LOST 2-14 (CI 71-100%). It did flatten
	// the army curve slightly -- 10.9k vs 17.8k at fourteen minutes, up from 8.9k
	// vs 25.1k -- but pushing the last follower to minute 16 costs more T2
	// economy than the smoother curve is worth. The synchronised transition is a
	// real cost; delaying teching is not the way to pay it.
	// !gHaveT2 was missing here, so a follower that ALREADY owned an advanced
	// plant kept being granted a no-bank switch to build ANOTHER one. Observed
	// live: a player with a T2 vehicle plant went and built a T2 bot lab as well,
	// and all four teched simultaneously late in the game. One advanced plant per
	// follower is the whole point -- the second is metal that should have been
	// army or mex upgrades, spent at the worst possible moment.
	// The clock and the metal-18 bar are both gone: reaching here at all now means
	// the guard at the top of this function passed, i.e. FollowerEconomyReady().
	if (!IsDesignatedLead() && !gHaveT2
		&& ((Factory::userData[facDef.id].attr & Factory::Attr::T2) != 0)
		&& FollowerEconomyReady())
	{
		aiFactoryMgr.isAssistRequired = Economy::isSwitchAssist = true;
		return true;
	}
	const bool isOK = (aiMilitaryMgr.armyCost > 1.2f * facDef.costM * aiFactoryMgr.GetFactoryCount())
		|| (aiEconomyMgr.metal.current > facDef.costM);
	aiFactoryMgr.isAssistRequired = Economy::isSwitchAssist = !isOK;
	return isOK;
}

// The advanced plant has to be one our own constructors can actually build.
// Measured: the rusher opened a BOT lab, whose constructor (corck) can build
// only coralab, while this function forced coravp -- the advanced VEHICLE plant.
// All 33 rush requests in a 14-minute game asked for a factory nothing on the
// field could place, were silently dropped, and T2 never started. The earlier
// "prefer Gollums over Sumos" bias that introduced coravp here was measured on
// games where a vehicle plant happened to be the opening, so it never showed up
// as a failure -- it just quietly disabled the whole rush on bot openings.
// Index-paired: T2_FAC[i] is the advanced counterpart of T1_FAC[i]. corasy
// appears twice because it serves both Cortex and Legion; that is safe because
// AdvCounterpart returns on the first T1_FAC name match and OwnAdvProgress takes
// a max over the whole array.
// legap/legaap are deliberately NOT in these arrays. Adding them (so
// AdvCounterpart() resolves a T2 counterpart and enables the T1-lab-reclaim
// rush for Legion air openers) was tried in isolation and confirmed, clean
// and solo, as a severe regression: legion-t1fac-only-16 went 2-14 (12.5%,
// 95% CI excludes 50%) against a established clean 43.8% baseline -- worse
// than leaving the "bug" alone. Whatever the mechanism (legap/legaap's
// cost/build-time/role may make the reclaim trade bad specifically for
// Legion), this is NOT free to fix the way it looked from the code alone.
// See notes/open-issues.md #35/#37/#38. Do not re-add without a new,
// isolated, positive confirmation.
// legap/legaap are deliberately NOT in these arrays. Two independent solo
// batches (legion-t1fac-only-16: 12.5%, legion-t1fac-retest-16: 37.5%)
// pool to 25% (8/32) against Legion's own pooled baseline of 37.5%
// (12/32) -- z=-1.08, not statistically significant. This is the fully
// resolved conclusion after two rounds of testing: adding legap/legaap
// has NO confirmed effect on Legion's win rate, positive or negative,
// once properly powered. Left out (no positive evidence to keep the
// change) rather than re-added. See notes/open-issues.md #38/#45/#47 for
// the full arc of this investigation, including the initial single-batch
// result that looked like a real regression before more data resolved it.
array<string> T1_FAC = {armlab, armvp, armsy, armap,
                        corlab, corvp, corsy, corap,
                        leglab, legvp, legsy};
array<string> T2_FAC = {armalab, armavp, armasy, armaap,
                        coralab, coravp, corasy, coraap,
                        legalab, legavp, corasy};

// Do we own OR are we building any advanced plant? GetDefBuildProgress is -1
// only when we hold none of that def at all, so a nanoframe counts -- which is
// the point: gHaveT2 must not drop while a replacement is going up, or the
// !gHaveT2 rebuild branch starts a second one. Unlike OwnAdvProgress this does
// NOT skip air plants; the question here is "do we hold the tier", not "is this
// player a credible ground-push tech lead".
bool AnyAdvPlant()
{
	for (uint i = 0; i < T2_FAC.length(); ++i) {
		CCircuitDef@ def = ai.GetCircuitDef(T2_FAC[i]);
		if ((def !is null) && (ai.GetDefBuildProgress(def) >= 0.f))
			return true;
	}
	return false;
}

// Our best progress toward an advanced plant, 0..1, or -1 if we hold none.
// Nanoframes count -- commitment is the question the election asks, and the
// fraction is what separates two teams that have both committed.
//
// Air plants are skipped: the team pools its metal expecting a T2 ground push,
// which an air plant cannot deliver. The previous election excluded air leads
// for the same reason.
//
// Declared here rather than beside the election because T2_FAC is a global, and
// AngelScript needs globals declared before use. Functions are order-free.
float OwnAdvProgress()
{
	float best = -1.f;
	for (uint i = 0; i < T2_FAC.length(); ++i) {
		CCircuitDef@ def = ai.GetCircuitDef(T2_FAC[i]);
		if ((def is null) || IsAirFactory(def))
			continue;
		const float p = ai.GetDefBuildProgress(def);
		if (p > best)
			best = p;
	}
	return best;
}

// Two separate reasons to refuse an air OPENING.
//
// 1. On a small team it is simply a losing choice: "on a 4v4 nobody should go
//    air, to main air on a 4v4 is a recipe for loss -- we'd beat BARb if we just
//    did 4x ground". One of four players contributing no ground army is a
//    quarter of the team missing. On a big team one air player is affordable and
//    can be useful, so only the lead is barred there.
// 2. Air is a bad sling target regardless of team size: the team pools its metal
//    into one player expecting a T2 ground push, and an air opening cannot give
//    them one.
//
// This gates the opening factory only. A later air plant, once the ground game
// is established, is fine and is left alone.
const uint BIG_TEAM = 6;   // same threshold the rush attack quota uses

array<string> AIR_FAC = {armap, armaap, corap, coraap, legap, legaap};

bool IsSmallTeam()
{
	array<Id>@ mates = ai.GetTeamIds();
	return (mates is null) || (mates.length() < BIG_TEAM);
}

// const handle: CCircuitUnit::circuitDef is a const CCircuitDef@, and a
// non-const parameter refuses it outright. The other two callers pass mutable
// handles, which a const parameter still accepts.
bool IsAirFactory(const CCircuitDef@ def)
{
	if (def is null)
		return false;
	const string name = def.GetName();
	for (uint i = 0; i < AIR_FAC.length(); ++i) {
		if (AIR_FAC[i] == name)
			return true;
	}
	return false;
}

// At most ONE air opening per ally team on a big team.
//
// Each instance decides its opening alone from the same map data, so on an 8v8
// several would pick air independently. One slot is chosen deterministically
// from the ally roster instead -- every instance computes the same answer at
// frame 0, with no signalling. Highest team id, to avoid landing on the same
// player as the engine's GetLeadTeamId (the early tech lead).
//
// A cap, not a quota: if the slot holder does not want air, the team opens
// none.
int AirSlotTeamId()
{
	array<Id>@ mates = ai.GetTeamIds();
	if ((mates is null) || (mates.length() == 0))
		return -1;
	// The eco lead builds no combat units at all, so handing it the team's one
	// air slot means the air plant produces constructors and nothing else.
	// RushLeadTeamId is the eco lead: IsEcoLead() is
	// IsDesignatedLead() && (teamId == RushLeadTeamId()).
	const int lead = RushLeadTeamId();
	int slot = -1;
	for (uint i = 0; i < mates.length(); ++i) {
		const int cand = int(mates[i]);
		if ((cand != lead) && (cand > slot))
			slot = cand;
	}
	return slot;   // -1 when the lead is the only candidate: no air rather than dead air
}

// May this instance open with an air factory at all?
bool MayOpenAir()
{
	if (IsSmallTeam())
		return false;             // under BIG_TEAM: nobody opens air
	if (IsDesignatedLead())
		return false;             // the rusher techs on the ground
	return ai.teamId == AirSlotTeamId();
}

// Ground opening when the default picks air.
//
// This returned the VEHICLE plant unconditionally, on a "Gollums push where
// Sumos hold" argument. Measured over two 8v8 games: apex fielded 83% and 86%
// of its army metal as vehicles, against stock's 43% and 63% as BOTS.
// apexearth: "We tend to have a high portion of our units be vehicles. Can we
// try to split more evenly?"
//
// Bots preferred, three in four. apexearth: "i think we should prefer bots".
// Keyed on team id so an ally team divides in a fixed proportion and each
// player's choice is stable across the game rather than changing if it is asked
// twice. Bots climb terrain vehicles cannot and carry the rez bot, which is the
// single biggest measured gap against stock; the remaining quarter keeps the
// heavy assault line available.
CCircuitDef@ GroundOpening()
{
	const string side = ai.GetSideName();
	const bool wantBots = ((ai.teamId % 4) != 0);
	if (side == "cortex")
		return ai.GetCircuitDef(wantBots ? corlab : corvp);
	if (side == "legion")
		return ai.GetCircuitDef(wantBots ? leglab : legvp);
	return ai.GetCircuitDef(wantBots ? armlab : armvp);
}

// The overrides below run ahead of the engine's own pick and all name land defs,
// so each needs a water branch or it silently replaces a naval choice.
//
// 40 is factory.json's own select.min_land, the value
// CFactoryManager::GetRepresenter reads to choose a factory's water variant.
const float MIN_LAND_PCT = 40.f;

bool IsWaterMap()
{
	return !aiTerrainMgr.IsWaterAVoid()
		&& (aiTerrainMgr.GetLandPercent() < MIN_LAND_PCT);
}

// A map can carry a great deal of water and still not be a "water map".
//
// IsWaterMap gates on land < 40%, i.e. water > 60%. That is the right test for
// the OPENING factory -- you do not open naval on a land majority -- but every
// other naval branch hangs off it too, so on anything in between the AI builds
// no naval unit of any kind. Observed on Supreme Isthmus: the boat move-types
// (boat4/boat5/boat9) cover 39-40% of the map and the side finished the game
// with zero shipyards, zero ships, and the sea uncontested.
const float NAVY_MIN_WATER_PCT = 20.f;
// A T1 shipyard is ~700 metal before a single hull comes out of it, so it waits
// for an economy rather than competing with the opening.
const float NAVY_MIN_INCOME = 15.f;
// Separate, lower floor for the ExpansionStalled() rescue case below. A player
// genuinely boxed onto a small peninsula plateaus BELOW NAVY_MIN_INCOME
// precisely because it has no more land to expand onto -- gating the escape
// valve on the same income bar the AI needs the escape valve to reach is a
// deadlock, not a safeguard. This is a rescue, not a luxury expansion, so it
// asks only for enough to not immediately go bankrupt building the yard.
// Measured on Crater Islands (63% land, 4v4): the four players finished the
// game on 2.4, 5.1, 5.2 and 13.3 metal/s, so even 6 was out of reach for three
// of them and exactly one ever built a yard. On a map where a third of the
// metal is across water, the yard is not a luxury bought out of surplus -- it
// is the only route to any surplus at all, so the bar has to sit below what the
// map actually produces before it is contested. The branch this gates still
// sits below the tech rush, the bot lab and the gantry, so it only ever takes a
// factory slot nothing else wanted.
const float NAVY_MIN_INCOME_STALLED = 6.f;
// Land share at or below which a MIXED map counts as water-heavy and uses the
// stalled floor above. Crater Islands is 63%; a 75-80% land map is not really
// a naval map and keeps the luxury bar.
const float NAVY_HEAVY_LAND_PCT = 70.f;

bool IsMixedWaterMap()
{
	return !aiTerrainMgr.IsWaterAVoid()
		&& !IsWaterMap()
		&& (aiTerrainMgr.GetLandPercent() <= (100.f - NAVY_MIN_WATER_PCT));
}

// Are we standing in the sea?
//
// Map-wide land percentage is the wrong question for the OPENING. A map can be
// mostly land and still put this player's start in the water -- an island start,
// a lagoon, the far side of a channel -- and no land factory can be placed there
// at all, whatever GetLandPercent says. The position handed to
// AiGetFactoryToBuild is where the factory would actually go, and Spring puts sea
// level at y = 0, so its height is the direct test.
//
// The margin is a judgement call, not a measurement: a commander a metre into the
// shallows can still build on land, and only a real depth means a land factory is
// impossible. Shallower than this and we keep the land opening.
const float WATER_START_DEPTH = -8.f;

// The position argument is not always resolved when isStart runs: observed
// y=-0.0 for several instances in one run and correct heights for all eight in
// another, on the same map and seed -- the DLL is multithreaded and this is a
// race. The commander is a registered unit with a real position, so prefer it and
// keep the argument as the fallback.
//
// Both readings failing means an unresolved height, which is NOT water: an
// unknown reads as 0, and 0 is above WATER_START_DEPTH, so the land opening
// stands. Missing a water start costs an opening; forcing a shipyard onto dry
// land costs the game.
bool IsWaterAt(const AIFloat3& in p)
{
	if (aiTerrainMgr.IsWaterAVoid())
		return false;
	const float y = Builder::gHomeSet ? Builder::gHomePos.y : p.y;
	return y < WATER_START_DEPTH;
}

bool HaveShipyard()
{
	CCircuitDef@ sy = NavalOpening();
	// count covers the nanoframe (RegisterTeamUnit runs for it), so one already
	// under construction cannot be re-requested.
	return (sy !is null) && (sy.count > 0);
}

CCircuitDef@ NavalOpening()
{
	const string side = ai.GetSideName();
	if (side == "cortex")
		return ai.GetCircuitDef(corsy);
	if (side == "legion")
		return ai.GetCircuitDef(legsy);
	return ai.GetCircuitDef(armsy);
}

// The opening factory, remembered so we can tech into its own advanced version.
CCircuitDef@ gT1Fac = null;

CCircuitDef@ AdvCounterpart()
{
	if (gT1Fac is null)
		return null;
	const string name = gT1Fac.GetName();
	for (uint i = 0; i < T1_FAC.length(); ++i) {
		if (T1_FAC[i] == name)
			return ai.GetCircuitDef(T2_FAC[i]);
	}
	return null;
}

// T3 is this variant's WIN CONDITION, and it has never once been reached: mean
// T3 metal across 36 measured player-games is exactly zero. The doctrine is
// hold cheaply, out-eco behind the wall, then finish with T3 -- but nothing ever
// decided to build the gantry, so every game was decided at T2 by whoever had
// more army. Without this the rest of the plan has no ending.
//
// Gated on a real economy rather than a clock: the gantry is expensive and
// starting one the economy cannot finish is the same trap that starting an
// unaffordable T2 plant was.
// Was 38. apex's economy runs poorer than stock's by design-cost, so 38 was
// reached only near game end -- 420 metal of T3 fielded, a token rather than the
// hammer the doctrine calls for. 26 is still a real economy and leaves time to
// actually build a T3 force with it.
// apexearth, on when a human commits to T3: "you shouldn't really be making big
// T3 until you're usually over 100m per second. That's after having 1 or 2 afus
// usually." That matches the arithmetic measured here -- a Korgoth is ~11,000
// metal, so at 40 m/s one unit costs 275 seconds of the whole team's income, and
// the two or three we ever fielded were exactly what that affords.
//
// The gate was 26, roughly four times too low: it committed to a gantry the
// economy could not feed, which is why T3 spend sat near 3,500 for a whole game
// while the metal would have bought a real T2 force instead. 100 is the real
// bar, and reaching it is an ECONOMY problem -- advanced fusion first.
const float T3_METAL_INCOME = 100.f;

// Income alone is the wrong gate. Observed live: the team reached 100 metal/s,
// committed to an ~8000-metal gantry, and lost every engagement on the map
// while it built -- the same metal spent on T2 units would have held the line.
// A gantry is only worth starting from a position that is not collapsing.
//
// Two conditions, both from signals already maintained here:
//   gTurtle       -- Military sets this when our army value fell 18% in 20s
//                    while the enemy still fields a mobile force. That is
//                    precisely "we are losing trades right now".
//   army vs threat -- and we should at least be matching what they field, not
//                    merely have stopped bleeding.
const float T3_ARMY_RATIO = 1.0f;

// Metal income above which the gTurtle and army-ratio vetoes stop applying, so a
// gantry gets placed while we are LOSING -- which is the case they were refusing.
// See T3Worthwhile().
//
// 150, only 50 above the T3_METAL_INCOME floor, because the point is to catch
// the situation early rather than to mark an elite economy. At 150 m/s a gantry
// is 56 seconds of income and a Shiva is 10; if enemy T3 is in the base, that is
// already worth spending whatever the army ratio says. The live observation that
// prompted this was a player at 398 m/s building nothing, so the bar only has to
// sit far enough below that to trigger well before the game is decided.
const float T3_INCOME_URGENT = 150.f;

// One gantry per this much metal income, floor 1, cap GANTRY_MAX.
//
// gHaveT3 is a latch set the moment the first gantry appears, and both build
// decisions tested !gHaveT3 -- so the AI built exactly ONE gantry per game at any
// income. Reported from a hosted game: "for a very long time no gantries were
// being made, except for the first one." A gantry builds one unit at a time, so
// at the 400 m/s these games reach that single plant is the throughput ceiling on
// the whole T3 win condition.
//
// gHaveT3 itself stays -- military.as reads it for big-gun placement -- it just
// no longer decides whether to build another.
// Measured 2026-08-08, 6-game 8v8 at Handicap 50: we field 2 T3 plants where
// stock fields 7, and 16 "building T3 gantry" decisions produced 2 gantries. At
// 150 a player on 400 metal/second wants only 2 -- so the cap, not the economy,
// is the throughput ceiling. Space is not the constraint either: techroom=-1
// occurred zero times in 1,907 samples, so there was always somewhere to put one.
//
// 100/6 gives 4 gantries at 400 m/s and 6 at 600, still short of stock's 7.
const float GANTRY_PER_INCOME = 100.f;
const int   GANTRY_MAX        = 6;
// Extra plants allowed while the bank is at the cap.
const int   GANTRY_SURPLUS_BONUS = 4;
// A gantry that is actually building draws 460-620 energy/second on its own, and
// every rung above is gated on METAL income alone, which says nothing about that.
// The bar is well above one plant's draw because the base has to keep running
// too: factories, nanos and converters are all on the same grid.
const float GANTRY_PER_ENERGY = 5000.f;

// A T1 bot lab is wanted for the whole game, not just the opening: it is the
// cheap assault spam and the only source of rez bots. apexearth: "one T2
// assault unit costs like 5 or 6 T1 assault units, and that many T1s can kill
// the T2 if the T2 doesn't have a good mass".
CCircuitDef@ T1BotLab()
{
	const string side = ai.GetSideName();
	if (side == "cortex")
		return ai.GetCircuitDef(corlab);
	if (side == "legion")
		return ai.GetCircuitDef(leglab);
	return ai.GetCircuitDef(armlab);
}

bool HaveT1BotLab()
{
	CCircuitDef@ lab = T1BotLab();
	// count is incremented in RegisterTeamUnit, which runs for the nanoframe, so
	// a lab already under construction counts and this cannot re-request one.
	return (lab !is null) && (lab.count > 0);
}

// Do we want another gantry? Counts nanoframes: CCircuitDef::count is
// incremented in RegisterTeamUnit, which runs for the nanoframe, so one already
// under construction is counted and this cannot double-request.
bool WantMoreGantries()
{
	CCircuitDef@ gant = T3Gantry();
	if (gant is null)
		return false;
	int want = int(aiEconomyMgr.metal.income / GANTRY_PER_INCOME);
	if (want < 1)
		want = 1;
	else if (want > GANTRY_MAX)
		want = GANTRY_MAX;
	// A full bank means the cap is the wrong number: income says what we can
	// sustain, a full bank says we are already failing to spend what we have.
	// apexearth: "If we are metal full we need to just keep making more gantries."
	if (aiEconomyMgr.isMetalFull)
		want += GANTRY_SURPLUS_BONUS;
	// One gantry per GANTRY_PER_ENERGY of income, and none below it.
	// apexearth, watching two go up on 1,300 energy: "I think you can do
	// something like 1 gantry for every 5000 energy as a limit."
	int engyWant = int(aiEconomyMgr.energy.income / GANTRY_PER_ENERGY);
	if (want > engyWant)
		want = engyWant;
	return int(gant.count) < want;
}

bool T3Worthwhile()
{
	const float inc = aiEconomyMgr.metal.income;
	if (inc <= T3_METAL_INCOME)
		return false;
	// Above a large economy the two vetoes below block exactly the case they
	// should permit, so they stop applying.
	//
	// Observed live in a hosted +40% game: the best player was on 398 metal/s
	// with enemy T3 already in the base, and built no gantry at all. gTurtle was
	// set -- that is what "their army is on our doorstep" looks like -- and our
	// armyCost was below theirs precisely because they had T3 and we did not. So
	// both vetoes fired for the same reason, and the AI stood still.
	//
	// Those vetoes were calibrated when a gantry was a large, irreversible bet.
	// It is not at this income. Real costs: corgant 8400, corshiva 1550,
	// armbanth 13500. At 398 m/s that is 21 s, 4 s and 34 s of income. Refusing
	// to spend 21 seconds of income on the counter to the thing killing you is
	// the wrong answer at any army ratio.
	if (inc >= T3_INCOME_URGENT)
		return true;
	if (Military::gTurtle)
		return false;
	return aiMilitaryMgr.armyCost >= Military::EnemyArmyCost() * T3_ARMY_RATIO;
}
bool gHaveT3 = false;

CCircuitDef@ T3Gantry()
{
	const string side = ai.GetSideName();
	// Legion deliberately falls through to the land branch below.
	if (IsWaterMap()) {
		if (side == "cortex")
			return ai.GetCircuitDef(corgantuw);
		if (side != "legion")
			return ai.GetCircuitDef(armshltxuw);
	}
	if (side == "cortex")
		return ai.GetCircuitDef(corgant);
	if (side == "legion")
		return ai.GetCircuitDef(leggant);
	return ai.GetCircuitDef(armshltx);
}

CCircuitDef@ AiGetFactoryToBuild(const AIFloat3& in pos, bool isStart, bool isReset)
{
	CCircuitDef@ pick = aiFactoryMgr.DefaultGetFactoryToBuild(pos, isStart, isReset);
	if (isStart || (pick is null)) {
		// Logged unconditionally: IsWaterAt is built on pos.y, and a binding that
		// quietly returns 0 for everything would look exactly like "no water start
		// here" on every map. This line is what says the height is real.
		if (isStart) {
			AiLog(T() + "apex: start pos y=" + formatFloat(pos.y, "", 0, 1)
				+ " commSet=" + (Builder::gHomeSet ? "1" : "0")
				+ " commY=" + (Builder::gHomeSet
					? formatFloat(Builder::gHomePos.y, "", 0, 1) : "n/a")
				+ " land=" + formatFloat(aiTerrainMgr.GetLandPercent(), "", 0, 0) + "%");
		}
		// A water start outranks every other opening rule, including the air
		// override below: if the spot is sea then a land lab cannot go there, so
		// there is nothing to weigh up. DefaultGetFactoryToBuild picks its water
		// variant off factory.json's select.min_land, which is the same map-wide
		// 40% test as IsWaterMap and so misses this case entirely.
		if (isStart && IsWaterAt(pos)) {
			CCircuitDef@ sea = NavalOpening();
			AiLog(T() + "apex: water start (y="
				+ formatFloat(pos.y, "", 0, 0) + ") -- opening "
				+ ((sea is null) ? "FAILED, no shipyard def" : sea.GetName())
				+ ((pick is null) ? "" : " instead of " + pick.GetName()));
			if (sea !is null) {
				@gT1Fac = sea;
				return sea;
			}
		}
		if (isStart && IsAirFactory(pick) && !MayOpenAir()) {
			CCircuitDef@ ground = IsWaterMap() ? NavalOpening() : GroundOpening();
			if (ground !is null) {
				AiLog(T() + "apex: opening " + pick.GetName() + " -> "
					+ ground.GetName()
					+ (IsSmallTeam() ? " (no air on a small team)"
					 : IsTechLead()  ? " (no air tech lead)"
					                 : " (air slot is team " + AirSlotTeamId() + ")"));
				@pick = ground;
			}
		}
		if (pick !is null)
			@gT1Fac = pick;
		return pick;   // opening factory is always T1
	}
	if ((gT1Fac is null) && ((Factory::userData[pick.id].attr & Factory::Attr::T2) == 0))
		@gT1Fac = pick;

	// The rusher builds the advanced plant directly rather than waiting for a
	// production switch that never comes.
	// Once the economy carries it, tech to T3 rather than adding another T2 line.
	// No bot lab: get one. It is the ONLY source of ground rez bots -- corlab ->
	// cornecro, armlab -> armrectr; the vehicle plant and the advanced plant
	// cannot build them at all. A team that opens vehicles and stays there has no
	// reclaim or resurrect capability whatsoever, which is what happened: 6 of 8
	// teams opened corvp and the side resurrected nothing all game.
	//
	// Not gated on gHaveT2 alone, or a player that never techs never gets one.
	// Past FOLLOWER_TECH_FRAME the rush window is over and a second factory is
	// affordable regardless.
	// ABOVE the bot lab, because the bot lab branch returns and would otherwise
	// make this unreachable. Measured: the eco lead asked for armlab three times
	// in one 40-minute game and never once reached the air plant below.
	//
	// The bot lab is there for spam units and rez bots. This player builds no
	// spam by construction, so for it the aircraft plant -- which is pure build
	// power -- is worth more than the lab it is displacing.
	if (EcoWantsAirPlant()) {
		const string side = ai.GetSideName();
		CCircuitDef@ ap = (side == "cortex") ? ai.GetCircuitDef(corap)
		                : ((side == "legion") ? ai.GetCircuitDef(legap)
		                                      : ai.GetCircuitDef(armap));
		if (ap !is null) {
			AiLog(T() + "apex: eco lead building " + ap.GetName()
				+ " for air constructors at "
				+ formatFloat(aiEconomyMgr.metal.income, "", 0, 0) + " m/s");
			return ap;
		}
	}

	// The air assassin's plant, ABOVE the bot lab and the navy.
	//
	// It used to sit last in this function, "so it never pre-empts the tech rush,
	// the bot lab or the gantry" -- and the consequence was that it pre-empted
	// nothing and got nothing. Measured across 8 games: 133 of 134 status samples
	// read `plants=0,0 cons=0 want=corap`, i.e. the strategy armed, committed, and
	// asked for its first plant every single time while some branch above it
	// returned first. It built 0 bombers and launched 0 strikes. apexearth: "I
	// haven't been seeing our air eco assassination strategy, I only saw something
	// akin to it once in dozens of games."
	//
	// Armed() is already narrow -- the air lead only, past 15 minutes, at 60+
	// metal/s, with enemy anti-air under the ceiling -- so this cannot run away.
	//
	// It sits above the gantry as well, which IS a real trade for that one
	// player: the bot lab branch is itself above the gantry, so anything placed
	// below the bot lab is starved by it, and there is no slot that clears the
	// bot lab without also clearing the gantry. One air lead per team delays its
	// own gantry; the other seven players are untouched.
	if (Air::Armed()) {
		CCircuitDef@ airFac = Air::FactoryToBuild();
		if (airFac !is null) {
			AiLog(T() + "apex: air assassin building " + airFac.GetName());
			return airFac;
		}
	}

	// Somebody has to OWN an air plant for the fighter floor to mean anything.
	// The eco lead builds one for constructors on a big team; this covers every
	// other case -- small teams, and games where the eco role never activated.
	// Bounded to the air slot holder, the same one-per-team cap the air opening
	// uses, so eight players do not each build a plant.
	const bool lateFallback  = LateGame() && (aiEconomyMgr.metal.income >= LATE_AIR_INCOME);
	// Restricted to big teams, unlike lateFallback above (which is deliberately
	// small-team-inclusive per its own comment, but at a 25-minute gate that a
	// 25-minute-capped 4v4 benchmark match almost never reaches). Diagnosed
	// entirely from 8v8 observation, and this session's dominant finding is
	// that any new spend competing with the phase-gated cluster costs a 4v4 --
	// this trigger has no BUILD_PHASE gate of its own, so keep it off the
	// benchmark the goal is actually measured against until it can be
	// threaded through that gate properly.
	const bool earlyReaction = !IsSmallTeam() && (ai.frame >= EARLY_AIR_REACT_FRAME)
		&& (Military::gAirAvg >= EARLY_AIR_ENEMY_MIN);
	if (!HaveAirFactory() && (ai.teamId == AirSlotTeamId()) && (lateFallback || earlyReaction))
	{
		const string aside = ai.GetSideName();
		CCircuitDef@ lap = (aside == "cortex") ? ai.GetCircuitDef(corap)
		                 : ((aside == "legion") ? ai.GetCircuitDef(legap)
		                                        : ai.GetCircuitDef(armap));
		if (lap !is null) {
			AiLog(T() + "apex: " + (earlyReaction ? "enemy air seen (" +
				formatFloat(Military::gAirAvg, "", 0, 0) + "), no air of our own"
				: "late game with no air") + " -- building " + lap.GetName()
				+ " for a fighter screen");
			return lap;
		}
	}

	// Skipped on water: this branch returns before every other pick in the
	// function, so it would pre-empt any naval choice for the rest of the game.
	// BOTLAB_FROM, not the follower tech clock. Waiting for T2 or thirteen minutes
	// costs us the whole early game of resurrection, and resurrection is the
	// single biggest measured gap against stock: over 6 games stock spent 21,460
	// metal a game raising its dead to our 10,396, and in one watched 8v8 it was
	// 32,890 to our 436 -- one stock player's largest sink of any kind was
	// cornecro at 17,940. We built ZERO rez bots in that game. A lab is ~600
	// metal and the bot is 130.
	// IsWaterMap() is a MAP test (land < 40%) and the failure is PER PLAYER: on a
	// mostly-land map a water starter's constructors are naval and cannot place a
	// land lab, so !HaveT1BotLab() never clears and this branch returns on every
	// call, pre-empting the naval, T2 and gantry picks below it for the rest of
	// the game. Measured: "no T1 bot lab" logged 206 times for one water player
	// and 59 for another, against 1-3 for land players, both ending techStart=-1.
	if (!IsWaterMap() && !(Builder::gHomeSet && IsWaterAt(Builder::gHomePos))
		&& !HaveT1BotLab()
		&& (ai.frame >= gNextBotLabRequest)
		&& (gHaveT2 || (ai.frame > BOTLAB_FROM)))
	{
		CCircuitDef@ lab = T1BotLab();
		if (lab !is null) {
			gNextBotLabRequest = ai.frame + BOTLAB_REQUEST_COOLDOWN;
			AiLog(T() + "apex: no T1 bot lab -- building " + lab.GetName()
				+ " for spam and rez bots");
			return lab;
		}
	}

	if (WantMoreGantries() && T3Worthwhile()) {
		CCircuitDef@ gant = T3Gantry();
		if (gant !is null) {
			AiLog(T() + "apex: building T3 gantry " + gant.GetName()
				+ " at " + formatFloat(aiEconomyMgr.metal.income, "", 0, 0) + " m/s"
				+ " army=" + formatFloat(aiMilitaryMgr.armyCost, "", 0, 0)
				+ " enemyArmy=" + formatFloat(Military::EnemyArmyCost(), "", 0, 0));
			return gant;
		}
	}

	// No rush-window clause. RushWindowOpen() is `frame <= 15 minutes`, and it was
	// gating the only route to an advanced plant -- so a player that had not
	// teched by minute 15, for any reason, could never tech again however rich it
	// became. Measured live at 33 minutes: t6 on 257 metal/s with two fusions and
	// a bank of 13,478 overflowing 9,185 of storage, still haveT2=0.
	//
	// The rush window is about who gets there FIRST; it should never have decided
	// who may get there at all. What remains is economic: MayPursueT2() is the
	// designated lead or a follower whose income has earned it, and RushReady()
	// checks we can actually power the plant.
	//
	// apexearth: "some of our guys havent made a t2 lab... they only have 1
	// advanced con (the one shared to them)", and separately the general rule --
	// "game progression is almost always based on the size of the economy."
	if (MayPursueT2() && !gHaveT2 && RushReady()) {
		CCircuitDef@ adv = AdvCounterpart();
		if (adv !is null) {
			AiLog(T() + "apex: building advanced plant " + adv.GetName()
				+ " (from " + gT1Fac.GetName() + ")");
			return adv;
		}
		AiLog(T() + "apex: rush WANTS T2 but no counterpart for "
			+ ((gT1Fac is null) ? "<unknown T1 factory>" : gT1Fac.GetName()));
	}

	// Contest the water on a map that has plenty of it but is not a water map,
	// OR try it as a fallback once our own expansion has stalled -- see
	// ExpansionStalled() above for why the map-average test alone misses a
	// player boxed onto a small peninsula on an otherwise land-majority map.
	// Nothing else in this function will ever ask for a shipyard there, so the
	// sea is a flank we can neither use nor defend.
	//
	// Placed here, below the tech rush, the bot lab and the gantry, because this
	// is a rule that SPENDS -- a factory plus the ships it makes is real metal,
	// and the last batch of individually-reasonable spending rules cut metal
	// production 4.3x between them. It takes the slot only when nothing more
	// important wants it, and only once the economy can carry it.
	// stalled is restricted to big teams for the same reason earlyReaction is
	// above: diagnosed entirely from an 8v8 live observation (a player boxed
	// onto a small land strip), it has no BUILD_PHASE gate of its own, and
	// this session's dominant finding is that any new unconditional spend
	// costs a 4v4. IsMixedWaterMap() below is unaffected -- that branch
	// predates this fix and already applied to every team size.
	// IsWaterMap() is in this test, not just IsMixedWaterMap(). The two are
	// DISJOINT by construction -- IsMixedWaterMap() is defined as
	// `!IsWaterMap() && land <= 80%` -- so on a genuine water map this branch
	// used to be unreachable, and `stalled` could not rescue it either because
	// that is restricted to big teams. Net effect: on a true water map at 4v4, a
	// player whose opening happened to land on dry ground had NO path to a
	// shipyard for the rest of the game.
	//
	// Measured on Silent Sea (4v4, 14x14): two players opened naval and spent
	// 48% and 61% of their metal on it; the other two finished on 0% and 3.7%
	// with no shipyard at all, and the game ran to the time limit with the sea
	// half-contested. apexearth: "be sure that the AI works well on water/mix
	// maps. Our AI should actively cross into water and build water units."
	const bool stalled = !IsSmallTeam() && !aiTerrainMgr.IsWaterAVoid() && ExpansionStalled();
	// A true water map uses the STALLED income floor, not the luxury one. The
	// deadlock NAVY_MIN_INCOME_STALLED exists for -- "gating the escape valve on
	// the same income bar the AI needs the escape valve to reach" -- is the
	// normal condition there, not an edge case: half the metal spots are under
	// water, so income cannot climb until we can build on them, and we cannot
	// build on them without a yard. Measured on Silent Sea: all four players
	// plateaued at 16-24 m/s, and the one that eventually cleared 15 asked for
	// its first shipyard at 21.9 minutes of a 25 minute game.
	// A water-HEAVY mixed map is the same deadlock as a true water map, just
	// less extreme, so it gets the same lower floor. Measured on Crater Islands
	// (63% land): the four players finished on 5.1, 5.2, 2.4 and 13.3 metal/s,
	// every one of them under NAVY_MIN_INCOME's 15, and exactly one ever built a
	// shipyard -- the one whose opening happened to start in water. Income
	// cannot climb past that bar precisely BECAUSE a third of the map's metal is
	// across water we never contest.
	//
	// Bounded to genuinely water-heavy maps: a mixed map that is mostly land
	// keeps the luxury floor, since there a yard really is optional.
	const bool waterHeavy = IsMixedWaterMap()
			&& (aiTerrainMgr.GetLandPercent() <= NAVY_HEAVY_LAND_PCT);
	const bool waterEscape = IsWaterMap() || stalled || waterHeavy;
	if ((IsWaterMap() || IsMixedWaterMap() || stalled) && !HaveShipyard()
		&& (aiEconomyMgr.metal.income >= (waterEscape ? NAVY_MIN_INCOME_STALLED : NAVY_MIN_INCOME)))
	{
		CCircuitDef@ sy = NavalOpening();
		if (sy !is null) {
			AiLog(T() + "apex: " + (stalled ? "expansion stalled"
				: (IsWaterMap() ? "water map (" : "mixed map (") +
				formatFloat(aiTerrainMgr.GetLandPercent(), "", 0, 0) + "% land)")
				+ " -- building " + sy.GetName() + " to contest the water"
				+ " at " + formatFloat(aiEconomyMgr.metal.income, "", 0, 0) + " m/s");
			return sy;
		}
	}

	return pick;
}

/* --- Utils --- */

int MakeSwitchInterval()
{
	return AiRandom(550, 900) * SECOND;
}

}  // namespace Factory
