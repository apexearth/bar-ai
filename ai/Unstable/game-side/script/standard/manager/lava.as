// PERIODIC RISING LAVA, LEARNED BY WATCHING IT.
//
// BAR's map_lava gadget walks the lava to a target level, holds, then walks to
// the next; everything under the surface takes damage per second. The tide
// TABLE is not readable -- it lives in a Lua config the AI cannot open, and a
// gadget to publish it would not survive a hosted game. One public game rules
// param is: `lavaLevel`, the exact number the gadget damages against. So the
// schedule is measured instead, and the level a climb ENDS at is a target the
// gadget reached and held -- exact, not inferred.
//
// One output, Eta(height): seconds until the tide covers that ground.
// Everything else prices through it, so "mexes and cheap guns in the basin,
// the fusion on the shelf" falls out of comparing Eta against what a build
// costs to earn, with no unit name or height anywhere in it.
namespace Lava {

// The gadget publishes -99999 before its first frame and removes itself
// entirely on a map with no lava, in which case the param never appears and
// our own default stands. Anything below this is "no answer".
const float NO_ANSWER = -99998.f;

// Elmo/s below which the surface counts as still. Ramp speeds in every shipped
// config are 1.5 to 30 elmo/s, so this separates motion from float noise on a
// one-second sample; it is an epsilon, not a policy.
const float STILL = 0.05f;

// Stands for "not in any horizon we price against".
const float NEVER = 1.0e9f;

bool  gActive  = false;   // this map is running the lava gadget
float gLevel   = 0.f;     // world Y of the surface, right now
float gRate    = 0.f;     // signed elmo/s over the last sample
float gRise    = 0.f;     // fastest climb ever seen: the ramp speed
float gCrest   = 0.f;     // highest level a climb has ENDED at -- the ceiling
int   gCrests  = 0;       // how many climbs we have watched end
bool  gClimbing = false;  // was the last sample a climb
bool  gEscalate = false;  // a later crest MATERIALLY beat an earlier one
float gStep    = 0.f;     // largest level move between two samples
float gLastLvl = 0.f;
int   gLastAt  = -1;
int   gNextLog = 7;       // prime offset; see the note over AiUpdate

// -- The schedule, read rather than guessed -------------------------------
//
// The gadget's tide table is a Lua config in the game or map archive, and the
// engine hands an AI File_getContent with none of the alliance gating that
// makes half the resource callbacks useless. So the answer to "will this map's
// lava rise, how fast, and how high" is available at frame 0 -- which is the
// only time it is worth anything, because the first fusion is sited long
// before a crest could be watched.
//
// Observation stays, as the cross-check: MODOPTIONS can replace the rhythm
// (map_lavatiderhythm), and those we cannot see. If the tide ever goes higher
// than the file said, the file is wrong about this game and we drop it.

bool   gCfgRead  = false;  // we have tried
bool   gCfgOk    = false;  // ...and got a rhythm out of it
bool   gCfgRises = false;  // does the tide ever climb on this map
bool   gCfgStale = false;  // the live tide contradicted the file
float  gCfgCeil  = 0.f;    // highest target in the rhythm
float  gCfgRise  = 0.f;    // fastest speed in it
float  gCfgLevel = 1.f;    // where the tide starts
string gCfgFrom;           // which path answered, for the log

// The rhythm itself: the tide walks to target[i] at speed[i], holds dwell[i],
// then walks to the next, wrapping forever.
array<float> gTgt;
array<float> gSpd;
array<float> gDwl;

// WHEN DOES THIS GROUND FIRST FLOOD? One table, built once, from the schedule.
//
// The binary "does the tide ever reach here" this replaced was worthless on the
// maps that need it most: Special Hotstepper's rhythm ends at 4000, above all
// terrain, so every cell answered "floods" and the whole layer went inert for
// the entire game. But that 4000 arrives at ~58 minutes and everything before
// it tops out at 1210 -- so ground at 900 is safe for forty minutes, which is
// most of a game and the difference between a good lab site and a bad one.
// Time is the answer; the extremes are not.
const float BUCKET_M = 8.f;      // one build square
const float SIM_HORIZON_S = 3600.f;   // an hour; past it "never" is the same answer
array<float> gReachAt;           // game seconds this bucket first goes under
float gReachLo = 0.f;            // height of bucket 0
bool  gReachOk = false;

// Lua line comments, so a commented-out setting is not read as a live one.
string StripComments(const string& in src)
{
	string kept;
	uint at = 0;
	while (at < src.length()) {
		int nl = src.findFirst("
", at);
		const uint end = (nl < 0) ? src.length() : uint(nl);
		string line = src.substr(at, end - at);
		const int c = line.findFirst("--");
		if (c >= 0)
			line = line.substr(0, uint(c));
		kept += line + "
";
		at = end + 1;
	}
	return kept;
}

bool IsWordChar(const string& in s, uint i)
{
	if (i >= s.length())
		return false;
	const string c = s.substr(i, 1);
	return ((c >= "a") && (c <= "z")) || ((c >= "A") && (c <= "Z"))
		|| ((c >= "0") && (c <= "9")) || (c == "_");
}

// `key = <number>`, with key as a whole word. False when it is not there.
bool CfgFloat(const string& in text, const string& in key, float& out val)
{
	int at = 0;
	while (true) {
		at = text.findFirst(key, uint(at));
		if (at < 0)
			return false;
		const uint after = uint(at) + key.length();
		if ((at > 0) && IsWordChar(text, uint(at) - 1)) {
			at = int(after);
			continue;
		}
		uint j = after;
		while ((j < text.length()) && (text.substr(j, 1) == " ")) ++j;
		if ((j < text.length()) && (text.substr(j, 1) == "=")) {
			val = parseFloat(text.substr(j + 1, 32));
			return true;
		}
		at = int(after);
	}
	return false;
}

bool CfgTrue(const string& in text, const string& in key)
{
	int at = text.findFirst(key);
	if (at < 0)
		return false;
	return text.findFirst("true", uint(at)) == int(uint(at) + key.length() + 3)
		|| text.substr(uint(at), 40).findFirst("true") >= 0;
}

// tideRhythm = { { target, speed, dwell }, ... }. Only the first two entries of
// each tide matter here; the dwell may be an expression (5*6000) and is skipped.
bool ParseRhythm(const string& in text)
{
	int at = text.findFirst("tideRhythm");
	if (at < 0)
		return false;
	int depth = 0;
	uint innerAt = 0;
	int tides = 0;
	float ceil = -1.0e9f;
	float floor = 1.0e9f;
	float fast = 0.f;
	// The tide walks from where the map starts, so the first target is a climb
	// only if it stands above the starting level.
	float startLevel = 1.f;   // the module's own default when a config omits it
	CfgFloat(text, "level", startLevel);
	float prev = startLevel;
	for (uint i = uint(at); i < text.length(); ++i) {
		const string c = text.substr(i, 1);
		if (c == "{") {
			++depth;
			if (depth == 2)
				innerAt = i + 1;
		} else if (c == "}") {
			if (depth == 2) {
				const string body = text.substr(innerAt, i - innerAt);
				const int c1 = body.findFirst(",");
				if (c1 > 0) {
					const float target = parseFloat(body.substr(0, uint(c1)));
					int c2 = body.findFirst(",", uint(c1) + 1);
					if (c2 < 0)
						c2 = int(body.length());
					const float speed = parseFloat(
							body.substr(uint(c1) + 1, uint(c2) - uint(c1) - 1));
					++tides;
					gTgt.insertLast(target);
					gSpd.insertLast(speed);
					gDwl.insertLast(ParseDwell(body));
					if (target > ceil) ceil = target;
					if (target < floor) floor = target;
					// A tide's speed is the speed of walking TO its target, so
					// only tides that walk upward say anything about how fast
					// the lava climbs. Ghenna's 3.0 is its descent.
					if ((target > prev) && (speed > fast))
						fast = speed;
					prev = target;
				}
			}
			--depth;
			if (depth <= 0)
				break;
		}
	}
	if (tides < 1)
		return false;
	gCfgLevel = startLevel;
	gCfgCeil = ceil;
	gCfgRise = fast;
	// It climbs if any target stands above another, or above where it starts.
	gCfgRises = (ceil > floor) || (ceil > startLevel);
	return true;
}

// The map's own config wins unless the game's copy claims overrideMap, which is
// the gadget's own precedence (modules/lava.lua getLavaConfig).
void LoadConfig()
{
	if (gCfgRead)
		return;
	gCfgRead = true;
	const string name = ai.GetMapName();
	// GetMapName may hand back the display name with a version, or the archive
	// name with underscores. Try what the gadget tries, then those variants.
	array<string> paths = { "mapconfig/lava.lua" };
	array<string> names = { name };
	string spaced;
	for (uint i = 0; i < name.length(); ++i) {
		const string c = name.substr(i, 1);
		spaced += (c == "_") ? " " : c;
	}
	if (spaced != name)
		names.insertLast(spaced);
	for (uint i = 0; i < names.length(); ++i) {
		// ...and again with a trailing " 4.0.1" version stripped.
		string n = names[i];
		int cut = -1;
		for (int j = int(n.length()) - 1; j > 0; --j) {
			const string c = n.substr(uint(j), 1);
			if ((c == ".") || ((c >= "0") && (c <= "9")))
				continue;
			if (c == " ")
				cut = j;
			break;
		}
		paths.insertLast("common/configs/LavaMaps/" + n + ".lua");
		if (cut > 0)
			paths.insertLast("common/configs/LavaMaps/" + n.substr(0, uint(cut)) + ".lua");
	}
	string mapCfg;
	string gameCfg;
	string mapFrom;
	string gameFrom;
	for (uint i = 0; i < paths.length(); ++i) {
		const string raw = ai.ReadVfsFile(paths[i]);
		if (raw.length() < 8)
			continue;
		if (i == 0) {
			mapCfg = StripComments(raw);
			mapFrom = paths[i];
		} else if (gameCfg.length() == 0) {
			gameCfg = StripComments(raw);
			gameFrom = paths[i];
		}
	}
	string use;
	if ((mapCfg.length() > 0) && (gameCfg.length() > 0)
		&& CfgTrue(gameCfg, "overrideMap")) {
		use = gameCfg;
		gCfgFrom = gameFrom + " (overrides map)";
	} else if (mapCfg.length() > 0) {
		use = mapCfg;
		gCfgFrom = mapFrom;
	} else {
		use = gameCfg;
		gCfgFrom = gameFrom;
	}
	if (use.length() == 0) {
		AiLog("apex: lava config not found for map '" + name
			+ "' -- falling back to watching the tide");
		return;
	}
	gCfgOk = ParseRhythm(use);
	if (gCfgOk)
		BuildReachTable();
	AiLog("apex: lava config " + (gCfgOk ? "read" : "UNPARSED") + " from "
		+ gCfgFrom + " -- rises=" + (gCfgRises ? "yes" : "no")
		+ " ceiling=" + formatFloat(gCfgCeil, "", 0, 1)
		+ " ramp=" + formatFloat(gCfgRise, "", 0, 2)
		+ " tides=" + gTgt.length());
	if (!gReachOk)
		return;
	// The table itself, so a wrong simulation is visible rather than inferred.
	// Read it against the map's own rhythm: on Special Hotstepper ground at 128
	// should stand for ~9 minutes and 400 for ~17, while on Ghenna nothing
	// above 415 floods at all.
	string sample;
	array<float> hs = {64.f, 128.f, 256.f, 400.f, 880.f, 1300.f};
	for (uint i = 0; i < hs.length(); ++i) {
		const float r = ReachIn(hs[i]);
		sample += " " + int(hs[i]) + "=" + ((r >= NEVER) ? "never"
				: (formatFloat(r / 60.f, "", 0, 1) + "m"));
	}
	AiLog("apex: lava schedule -- safe" + int(SafeHorizon()) + "s>="
		+ int(SafeHeightFor(SafeHorizon())) + " floods-at:" + sample);
}

// The third entry of a tide, which is written as an expression often enough
// (`5*6000`, `4*60`, `10*60`) that a plain parseFloat reads only the first
// factor and turns a ten-minute dwell into ten seconds.
float ParseDwell(const string& in body)
{
	int c1 = body.findFirst(",");
	if (c1 < 0)
		return 0.f;
	int c2 = body.findFirst(",", uint(c1) + 1);
	if (c2 < 0)
		return 0.f;
	const string tail = body.substr(uint(c2) + 1, body.length() - uint(c2) - 1);
	float v = parseFloat(tail);
	const int star = tail.findFirst("*");
	if (star >= 0)
		v *= parseFloat(tail.substr(uint(star) + 1, 24));
	return v;
}

// Walk the schedule forward and note, for every height, the first moment the
// lava covers it. Segment by segment, not frame by frame: each tide is a ramp
// of known speed followed by a known dwell, so an hour of tide is a couple of
// dozen steps of arithmetic instead of a hundred thousand.
void BuildReachTable()
{
	gReachOk = false;
	const uint n = gTgt.length();
	if ((n < 1) || !gCfgRises)
		return;
	float lo = gCfgLevel;
	float hi = gCfgLevel;
	for (uint i = 0; i < n; ++i) {
		if (gTgt[i] < lo) lo = gTgt[i];
		if (gTgt[i] > hi) hi = gTgt[i];
	}
	const int buckets = int((hi - lo) / BUCKET_M) + 2;
	if ((buckets < 2) || (buckets > 20000))
		return;
	gReachLo = lo;
	gReachAt.resize(uint(buckets));
	for (uint b = 0; b < gReachAt.length(); ++b)
		gReachAt[b] = NEVER;
	// Everything at or below where it starts is already wet.
	float level = gCfgLevel;
	float peak = level;
	for (int b = 0; b <= int((level - lo) / BUCKET_M); ++b) {
		if ((b >= 0) && (b < buckets))
			gReachAt[uint(b)] = 0.f;
	}
	float t = 0.f;
	for (uint step = 0; (step < 512) && (t < SIM_HORIZON_S); ++step) {
		const uint i = step % n;
		const float target = gTgt[i];
		const float speed = (gSpd[i] > 0.01f) ? gSpd[i] : 1.f;
		const float travel = Fabs(target - level) / speed;
		if (target > peak) {
			// A climb into ground the tide has never covered: every bucket it
			// passes gets the moment it passes it.
			int b0 = int((peak - gReachLo) / BUCKET_M) + 1;
			const int b1 = int((target - gReachLo) / BUCKET_M);
			for (int b = b0; b <= b1; ++b) {
				if ((b < 0) || (b >= buckets))
					continue;
				const float h = gReachLo + float(b) * BUCKET_M;
				gReachAt[uint(b)] = t + Fabs(h - level) / speed;
			}
			peak = target;
		}
		t += travel + gDwl[i];
		level = target;
	}
	gReachOk = true;
}

float Fabs(float v) { return (v < 0.f) ? -v : v; }

// Seconds until the tide covers height `h`, from the schedule. Negative means
// we have no table.
float ReachIn(float h)
{
	if (!gReachOk)
		return -1.f;
	const int b = int((h - gReachLo) / BUCKET_M);
	if (b < 0)
		return 0.f;
	if (b >= int(gReachAt.length()))
		return NEVER;   // above every target the schedule contains
	const float at = gReachAt[uint(b)];
	if (at >= NEVER)
		return NEVER;
	const float now = float(ai.frame) / float(SECOND);
	return (at > now) ? (at - now) : 0.f;
}

// The horizon the rest of the market already prices a standing asset over, so
// "safe ground" here means the same thing it means everywhere else.
float SafeHorizon()
{
	const float T = ai.GetTunable("apex_stake_horizon_s", TUNE_STAKE_HORIZON_S);
	return (T > 1.f) ? T : 300.f;
}

// The lowest ground that stays dry for the next `T` seconds. What the DLL's
// farm search is given, since it cannot read a schedule of its own.
float SafeHeightFor(float T)
{
	if (!gReachOk)
		return -99999.f;
	const float now = float(ai.frame) / float(SECOND);
	for (uint b = 0; b < gReachAt.length(); ++b) {
		if (gReachAt[b] >= now + T)
			return gReachLo + float(b) * BUCKET_M;
	}
	return gReachLo + float(gReachAt.length()) * BUCKET_M;
}

// Does the tide ever climb on this map? The file answers at frame 0; without it
// we can only say whether we have SEEN it climb.
bool Rises()
{
	if (gCfgOk && !gCfgStale)
		return gCfgRises;
	return gRise > STILL;
}

// The fastest climb the tide is capable of.
float RampSpeed()
{
	if (gRise > STILL)
		return gRise;   // measured beats declared
	return (gCfgOk && !gCfgStale) ? gCfgRise : 0.f;
}

bool Active()
{
	return gActive;
}

// Does the tide PRICE anything? The sense keeps running either way, so the
// instrument still reports on a map whose behaviour is switched off for an A/B.
bool Enabled()
{
	return gActive && (ai.GetTunable("apex_lava", TUNE_LAVA) > 0.f);
}

void Update()
{
	const float lvl = ai.GetGameRulesParam("lavaLevel", -99999.f);
	if (lvl < NO_ANSWER)
		return;
	if (!gActive) {
		gActive = true;
		gLevel = lvl;
		gLastLvl = lvl;
		gLastAt = ai.frame;
		AiLog("apex: lava map detected, level=" + formatFloat(lvl, "", 0, 1));
		LoadConfig();
		return;
	}
	const float prev = gLastLvl;
	const float dt = float(ai.frame - gLastAt) / float(SECOND);
	if (dt > 0.f) {
		gRate = (lvl - gLastLvl) / dt;
		gLastLvl = lvl;
		gLastAt = ai.frame;
	}
	gLevel = lvl;
	const float move = (lvl > prev) ? (lvl - prev) : (prev - lvl);
	if (move > gStep)
		gStep = move;
	const bool climbing = (gRate > STILL);
	if (climbing) {
		if (gRate > gRise)
			gRise = gRate;
	} else if (gClimbing) {
		// A CLIMB THAT STOPPED IS A TARGET REACHED. This is the one number
		// the tide's own schedule gives away for free: the gadget walks to a
		// target and holds, so the level a rise ENDS at is that target,
		// exactly. Every crest we watch teaches us one more of them, and the
		// highest is the ceiling -- ground above it has never been reached.
		//
		// The sample that catches the stop can be up to one interval late, so
		// a crest is only read as HIGHER than the last when it beats it by
		// more than the biggest move a single sample has ever shown. Without
		// that margin Ghenna Rising's second 415 read as an escalation over
		// its first and threw the ceiling away for the rest of the game.
		++gCrests;
		const float top = (prev > gLevel) ? prev : gLevel;
		if ((gCrests > 1) && (top > gCrest + gStep))
			gEscalate = true;   // this map raises its own ceiling
		if (top > gCrest)
			gCrest = top;
	}
	gClimbing = climbing;
	// THE FILE IS ABOUT THE MAP; THE MODOPTIONS ARE ABOUT THIS GAME.
	// map_lavatiderhythm can replace the rhythm wholesale and we cannot read
	// modoptions, so the live tide is the arbiter: the moment it goes above
	// what the file promised, or climbs on a map the file called static, the
	// file is describing a game we are not playing.
	if (gCfgOk && !gCfgStale
		&& ((gLevel > gCfgCeil + 1.f) || (climbing && !gCfgRises))) {
		gCfgStale = true;
		AiLog("apex: lava config CONTRADICTED (level "
			+ formatFloat(gLevel, "", 0, 1) + " vs ceiling "
			+ formatFloat(gCfgCeil, "", 0, 1)
			+ ") -- modoptions replaced the rhythm; watching instead");
	}
	// Hand the crest down to the site search. The farm's ground is chosen
	// inside the DLL with no way back into script, and the DLL cannot learn a
	// crest -- it only ever sees where the surface is today. gCrest, not
	// Ceiling(): an escalating map has no ceiling to promise, but "higher than
	// anything it has reached yet" is exactly the right place to stand there.
	{
		// Hand the DLL's farm search a HEIGHT, not a high-water mark: the
		// lowest ground that stays dry for as long as the stake horizon the
		// rest of the market already prices against. On a map whose tide
		// eventually covers everything this is still a real number, where the
		// high-water mark was the top of the map and meant nothing.
		float safe = -99999.f;
		if (Enabled() && Rises()) {
			safe = SafeHeightFor(SafeHorizon());
			if (safe <= -99998.f) {
				const float c = Ceiling();
				safe = (c < NEVER) ? c : ((gCrests > 0) ? gCrest : gLevel);
			}
		}
		ai.SetLavaCrest(safe);
	}

	if (ai.frame < gNextLog)
		return;
	gNextLog = ai.frame + 60 * SECOND;
	AiLog(Factory::T() + "apex: lava level=" + formatFloat(gLevel, "", 0, 1)
		+ " rate=" + formatFloat(gRate, "", 0, 2)
		+ " ramp=" + formatFloat(gRise, "", 0, 2)
		+ " crest=" + formatFloat(gCrest, "", 0, 1)
		+ " crests=" + gCrests
		+ (gEscalate ? " escalating" : "")
		+ " ceil=" + (Ceiling() >= NEVER ? "?" : formatFloat(Ceiling(), "", 0, 1))
		+ " src=" + (gCfgOk ? (gCfgStale ? "watched(cfg-stale)" : "config") : "watched")
		+ Census());
}

// WHAT DID THE PRICING ACTUALLY MOVE?
//
// Not "how much do we have standing in the flood zone" -- that number is
// survivorship: an arm that DID build in the basin loses those buildings to
// the tide and then reads clean. The honest measure is cumulative: every
// structure we ever finished, at the ground height it was finished on, scored
// against the crest at the end. A build that burned still counts as a build we
// should not have made.
array<float> gPlacedM;   // what each finished structure cost
array<int>   gPlacedBad; // ...and whether the tide was going to take it early

array<int> gMobile;   // our ground units, for the retreat sweep

void NoteFinished(CCircuitUnit@ unit)
{
	if (!gActive || (unit is null) || (unit.circuitDef is null))
		return;
	if (unit.circuitDef.IsMobile()) {
		// Fliers are untouched by the tide, so they never enter the sweep.
		if (!unit.circuitDef.IsAbleToFly() && (gMobile.length() < 2000))
			gMobile.insertLast(int(unit.id));
		return;
	}
	const AIFloat3 p = unit.GetPos(ai.frame);
	if (!OnMap(p))
		return;
	if (gPlacedM.length() > 2000)
		return;   // a census, not a ledger
	// SCORED WHEN IT IS PLACED, NOT AT THE END. The safe height climbs all game
	// on an escalating map, so asking later whether a building sits in the
	// flood measures the tide rather than the decision: a solar put on good
	// ground at minute two reads as a blunder at minute twenty. The question is
	// whether the tide was going to reach it before it paid for itself, on the
	// day we chose the spot.
	const int d = int(unit.circuitDef.id);
	const float bp = Catalog::gBuildPower[d];
	gPlacedM.insertLast(Catalog::gCostM[d]);
	gPlacedBad.insertLast((Eta(HeightAt(p)) < PayHorizon(d, bp)) ? 1 : 0);
}


// -- Retreat -----------------------------------------------------------------
//
// apexearth watched a commander walk toward the lava as the game ended: "there
// didn't seem to be any self preservation logic against lava". There was none.
// Placement keeps BUILDINGS out of the flood; nothing told a unit standing in
// a basin that the basin was about to fill.
//
// The rule has no threshold in it: a unit leaves when it can no longer afford
// to wait -- when the ground it stands on floods sooner than it could walk to
// ground that does not. Everything before that moment it goes on doing its job.
//
// CmdMoveTo ALONE IS NOT ENOUGH, and this is why Builder::UpdateCommanderSafety
// sits disabled in posture.as: C++ re-tasks a unit every few seconds and simply
// overrides the order, and the fight between the two drove engine aborts from
// 0-2 to 14-17 per 20 games. So a fleeing unit is detached into a CPlayerTask
// (UnitControl false), walked out, and handed back the moment it is safe. Every
// hold is released -- on arrival, on the ground going safe, on a hard timeout,
// and on the tide stopping -- because a commander left detached is a commander
// that never builds again.
array<int>      gHeldId;
array<int>      gHeldAt;
array<AIFloat3> gHeldTo;
int gFleeCursor = 0;
int gFleeHeld = 0;    // instrument: how many retreats we have started
int gFleeNoRoom = 0;  // ...and how often there was nowhere to go
int gFleeComm = 0;    // ...of which were commanders pulled out early

const int   FLEE_SLICE = 24;      // units looked at per tick: spread, never batched
const float FLEE_ARRIVE = 96.f;   // close enough to count as out
const int   FLEE_MAX_HOLD = 90;   // seconds; a hold that outlives this is a bug

// The nearest ground that outlives the walk to it.
bool Refuge(const AIFloat3& in from, float speed, AIFloat3& out to)
{
	if (speed < 1.f)
		return false;
	for (int r = 0; r < 4; ++r) {
		const float rad = 256.f * float(1 << r);
		const float travel = rad / speed;
		float bestEta = -1.f;
		bool ok = false;
		AIFloat3 pick;
		for (int b = 0; b < 12; ++b) {
			const float a = float(b) * 0.5235988f;
			const AIFloat3 c = from
					+ AIFloat3(cos(a), 0.f, sin(a)) * rad;
			if (!OnMap(c))
				continue;
			const float eta = Eta(HeightAt(c));
			if (eta <= travel)
				continue;   // floods before we could get there
			if (eta > bestEta) {
				bestEta = eta;
				pick = c;
				ok = true;
			}
		}
		if (ok) {          // nearest ring that offers anything wins
			to = pick;
			return true;
		}
	}
	return false;
}

bool HeldAlready(int id)
{
	for (uint i = 0; i < gHeldId.length(); ++i) {
		if (gHeldId[i] == id)
			return true;
	}
	return false;
}

void Release(uint i)
{
	CCircuitUnit@ u = ai.GetTeamUnit(gHeldId[i]);
	if (u !is null)
		ai.UnitControl(u, true);
	gHeldId.removeAt(i);
	gHeldAt.removeAt(i);
	gHeldTo.removeAt(i);
}

void UpdateFlee()
{
	if (!Enabled() || !Rises()) {
		while (gHeldId.length() > 0)
			Release(0);
		return;
	}
	// Hand back everyone who is out, safe, or has been held too long.
	for (uint i = 0; i < gHeldId.length(); ) {
		CCircuitUnit@ u = ai.GetTeamUnit(gHeldId[i]);
		if (u is null) {
			gHeldId.removeAt(i);
			gHeldAt.removeAt(i);
			gHeldTo.removeAt(i);
			continue;
		}
		const AIFloat3 p = u.GetPos(ai.frame);
		const bool clear = !OnMap(p)
				|| (p.distance2D(gHeldTo[i]) < FLEE_ARRIVE)
				|| (Eta(HeightAt(p)) > SafeHorizon())
				|| (ai.frame - gHeldAt[i] > FLEE_MAX_HOLD * SECOND);
		if (clear)
			Release(i);
		else
			++i;
	}
	// THE COMMANDER IS SWEPT EVERY TICK, NOT ON THE SLICE.
	//
	// gMobile is built from the unit-FINISHED event, which the commander we
	// start the game holding never fires -- so the one unit that matters most
	// was the one unit never checked. Market::gComId is the registry that does
	// know about it. It also gets a longer fuse than everything else: a rifle
	// bot deciding at the last second is a rifle bot, but a commander standing
	// on ground that floods inside the horizon the rest of the market prices
	// against is already in the wrong place, and losing one ends the game.
	for (uint c = 0; c < Market::gComId.length(); ++c)
		Consider(int(Market::gComId[c]), true);

	// A slice of the fleet, so a big army never costs one long frame.
	const uint n = gMobile.length();
	if (n == 0)
		return;
	for (int k = 0; k < FLEE_SLICE; ++k) {
		if (gFleeCursor >= int(n))
			gFleeCursor = 0;
		const int id = gMobile[uint(gFleeCursor)];
		++gFleeCursor;
		if (ai.GetTeamUnit(id) is null) {
			gMobile.removeAt(uint(gFleeCursor - 1));
			if (gMobile.length() == 0)
				return;
			--gFleeCursor;
			continue;
		}
		Consider(id, false);
	}
}

// Should this unit leave, and if so, start it moving. `early` gives the unit
// the full horizon rather than the last moment it could still escape.
void Consider(int id, bool early)
{
	CCircuitUnit@ u = ai.GetTeamUnit(id);
	if ((u is null) || (u.circuitDef is null) || HeldAlready(id))
		return;
	if (u.circuitDef.IsAbleToFly())
		return;
	const AIFloat3 p = u.GetPos(ai.frame);
	if (!OnMap(p))
		return;
	const float here = Eta(HeightAt(p));
	if (here > SafeHorizon())
		return;   // this ground is not the problem
	const float speed = Catalog::gSpeed[int(u.circuitDef.id)];
	AIFloat3 to;
	if (!Refuge(p, speed, to)) {
		++gFleeNoRoom;
		return;   // nowhere better; it stays and does its job
	}
	if (!early) {
		// LEAVE ONLY WHEN WAITING WOULD COST THE UNIT. Until the walk no longer
		// fits in the time this ground has left, it keeps working.
		if (here > p.distance2D(to) / ((speed > 1.f) ? speed : 1.f))
			return;
	}
	if (!ai.UnitControl(u, false))
		return;
	u.CmdMoveTo(to);
	gHeldId.insertLast(id);
	gHeldAt.insertLast(ai.frame);
	gHeldTo.insertLast(to);
	++gFleeHeld;
	if (early)
		++gFleeComm;
}

// The one number that says whether the commander is standing somewhere it
// should not be. "-" when we hold none; "never" when its ground is safe.
string CommEta()
{
	string out2;
	for (uint c = 0; c < Market::gComId.length(); ++c) {
		CCircuitUnit@ u = ai.GetTeamUnit(int(Market::gComId[c]));
		if (u is null)
			continue;
		const AIFloat3 p = u.GetPos(ai.frame);
		if (!OnMap(p))
			continue;
		const float e = Eta(HeightAt(p));
		out2 += (out2.length() > 0 ? "," : "")
				+ ((e >= NEVER) ? "never" : (formatFloat(e, "", 0, 0) + "s"));
	}
	return (out2.length() > 0) ? out2 : "-";
}

string Census()
{
	float wetM = 0.f;
	float allM = 0.f;
	int wetN = 0;
	for (uint i = 0; i < gPlacedM.length(); ++i) {
		allM += gPlacedM[i];
		if (gPlacedBad[i] != 0) {
			wetM += gPlacedM[i];
			++wetN;
		}
	}
	// The SHARE, not the metal: two arms of an A/B end with economies that
	// differ by 2x, and the raw figure then says which arm was richer rather
	// than which one stayed out of the flood.
	const int pct = (allM > 1.f) ? int(100.f * wetM / allM) : 0;
	return " | doomed-when-placed " + pct + "% (" + int(wetM) + "m of "
		+ int(allM) + "m, " + wetN + "/" + gPlacedM.length() + " bldgs)"
		+ " | fled=" + gFleeHeld + " (comm=" + gFleeComm + ")"
		+ " holding=" + gHeldId.length() + " noroom=" + gFleeNoRoom
		+ " commEta=" + CommEta();
}

// Seconds until lava is expected to cover ground at height `h`.
//
// Rising: the ramp speed is being measured right now, so this is arithmetic.
// Still: it will climb again, and the longest calm we have already sat through
// is the only evidence we have for how long this one runs -- so a map that has
// been quiet for ten minutes stops being treated as about to erupt, while one
// that has never held still for more than ten seconds keeps its short fuse.
// Never seen it climb at all: we do not invent a rise it has not shown us.
// The height the tide is expected to reach -- "what lava height is targeted to
// be". NEVER while we have no answer.
//
// One crest is a target the gadget walked to and held, so it is exact. Two
// crests that ESCALATE say the map raises its own ceiling every cycle (Special
// Hotstepper steps 120 -> 250 -> 400 -> 880), and then no height we have seen
// bounds the next one -- so we stop claiming a ceiling rather than hand back a
// number the map is about to beat.
float Ceiling()
{
	if (!gActive)
		return NEVER;
	if (gCfgOk && !gCfgStale)
		return gCfgCeil;   // every target the schedule contains
	// No file, or the file is wrong about this game. One crest is a target the
	// gadget reached and held, so it is exact; two crests that ESCALATE say the
	// map raises its own ceiling and no height we have seen bounds the next.
	if ((gCrests < 1) || gEscalate)
		return NEVER;
	return gCrest;
}

// Seconds until lava is expected to cover ground at height `h`.
//
// Climbing: the ramp speed is being measured right now, so this is arithmetic
// and exact. Below the ceiling but not climbing: the tide comes back, and we
// do not pretend to know when the next ramp starts -- assuming it starts NOW
// is the conservative read, and being wrong that way puts a building on higher
// ground, which costs nothing. Above the ceiling, or on a map we have never
// seen climb at all: never.
float Eta(float h)
{
	if (!gActive)
		return NEVER;
	if (h <= gLevel)
		return 0.f;
	if (!Rises())
		return NEVER;   // this map's lava does not climb
	// The schedule, when we have it and it still describes this game: an exact
	// answer that knows the tide holds low for five minutes before the next
	// climb, and that the surge to 4000 is forty minutes away.
	if (!gCfgStale) {
		const float sched = ReachIn(h);
		if (sched >= 0.f)
			return sched;
	}
	// Watching only. Climbing now is arithmetic; otherwise assume it starts
	// climbing this second, which is the conservative read.
	if (gRate > STILL)
		return (h - gLevel) / gRate;
	if (h > Ceiling())
		return NEVER;
	const float ramp = RampSpeed();
	if (ramp <= STILL)
		return NEVER;
	return (h - gLevel) / ramp;
}

// Ground height under a position. The engine's height map, not pos.y: a base
// grid cell or a lattice step carries a y that came out of vector arithmetic.
float HeightAt(const AIFloat3& in pos)
{
	return ai.GetElevationAt(pos);
}

float EtaAt(const AIFloat3& in pos)
{
	if (!gActive || !OnMap(pos))
		return NEVER;
	return Eta(HeightAt(pos));
}

// The per-second rate at which value standing here is destroyed by the tide.
// The same units as HazardAt, so it composes with the rest of the risk model --
// but deliberately NOT part of HazardAt: no turret ever stopped lava, and a
// hazard the guns cannot answer must not read as a reason to buy guns.
float RiskAt(const AIFloat3& in pos)
{
	if (!Enabled())
		return 0.f;
	const float eta = EtaAt(pos);
	if (eta >= NEVER)
		return 0.f;
	return 1.f / ((eta > 1.f) ? eta : 1.f);
}

// The share of a return over `T` seconds that this ground actually delivers.
// Same 1/(1 + risk x T) shape every other survival discount in the market uses.
float Survival(const AIFloat3& in pos, float T)
{
	if (!Enabled() || (T <= 0.f))
		return 1.f;
	const float risk = RiskAt(pos);
	if (risk <= 0.f)
		return 1.f;
	return 1.f / (1.f + risk * T);
}

// What a build is bought against, in seconds: the time to raise it plus the
// time our income needs to earn what it cost. The same horizon TechSurvival
// prices a deferred bet over, so "worth putting here" means the same thing in
// both places.
float PayHorizon(int defId, float buildPower)
{
	float T = Catalog::BuildSecondsAt(defId, buildPower);
	const float inc = Eco::MInc();
	if (inc > 0.1f)
		T += Catalog::gCostM[defId] / inc;
	return T;
}

// Will the tide take this before it has paid for itself? The temporary half of
// the rule: a 620-metal extractor earns itself back in under a minute and can
// sit in a basin that floods in five.
bool Doomed(const AIFloat3& in pos, CCircuitDef@ def, float buildPower)
{
	if (!Enabled() || (def is null) || !OnMap(pos))
		return false;
	return EtaAt(pos) < PayHorizon(int(def.id), buildPower);
}

// Will the tide take this before it has earned itself back?
//
// apexearth: "we should not even want to make a factory down where it will
// die, the lava will kill it." That is this test with the horizon a factory
// actually has -- build time plus the time our income needs to replace its
// cost -- against an ETA that now comes from the schedule rather than a guess.
// A 620-metal extractor clears in under a minute and can sit in a basin that
// floods in five; a lab cannot, and neither can a fusion.
//
// A binary "does it EVER flood" stood here for one session and was worse than
// nothing: on a map whose rhythm ends above all terrain it answered yes
// everywhere and the layer went inert. Time is the answer.
bool Floods(const AIFloat3& in pos, CCircuitDef@ def, float buildPower)
{
	if (!Enabled() || !OnMap(pos) || !Rises() || (def is null))
		return false;
	float rest = HeightAt(pos);
	if (Catalog::gFloater[int(def.id)] && (rest < 0.f))
		rest = 0.f;
	return Eta(rest) < PayHorizon(int(def.id), buildPower);
}

// Ground that is under the surface right now. Nothing may be built here at any
// price -- it is taking damage before the nanoframe is up. A floating def rests
// at the waterline, not on the seabed, which is what the gadget damages against
// (same rule as CCircuitAI::IsUnderLava, which backstops every build path).
bool Submerged(const AIFloat3& in pos, CCircuitDef@ def = null)
{
	if (!Enabled() || !OnMap(pos))
		return false;
	float rest = HeightAt(pos);
	if ((def !is null) && Catalog::gFloater[int(def.id)] && (rest < 0.f))
		rest = 0.f;
	return rest <= gLevel;
}

}  // namespace Lava
