/*
 * Section self-profiler over ai.ClockUs(). Wrap a hotspot with
 *   double t0 = Perf::T0();  ...  Perf::Add("name", t0);
 * and Flush() (called from AiUpdate) logs one line per section per game-minute:
 *   apex: perf sec <name> calls=N totalMs=X maxMs=Y
 * tools/frametime.py breaks these out. apex_perf=0 turns it all off.
 */

namespace Perf {

bool gInit = false;
bool gOn = false;
array<string> gNames;
dictionary gIndex;  // name -> gNames slot; Add() runs on every scope close
array<double> gTotalUs;
array<double> gMaxUs;
array<uint> gCalls;
int gNextLog = 0;

bool On()
{
	if (!gInit) {
		gInit = true;
		gOn = ai.GetTunable("apex_perf", TUNE_PERF) > 0.5f;
	}
	return gOn;
}

double T0()
{
	return On() ? ai.ClockUs() : 0.0;
}

void Add(const string &in name, double t0)
{
	if (t0 <= 0.0)
		return;
	const double us = ai.ClockUs() - t0;
	int idx = -1;
	int64 slot = 0;
	if (gIndex.get(name, slot)) {
		idx = int(slot);
	} else {
		gNames.insertLast(name);
		gTotalUs.insertLast(0.0);
		gMaxUs.insertLast(0.0);
		gCalls.insertLast(0);
		idx = int(gNames.length()) - 1;
		gIndex.set(name, int64(idx));
	}
	gTotalUs[idx] += us;
	gCalls[idx] += 1;
	if (us > gMaxUs[idx])
		gMaxUs[idx] = us;
}

// Count-only section: an event worth tallying that has no duration.
void Note(const string &in name)
{
	if (!On())
		return;
	const double t0 = ai.ClockUs();
	Add(name, t0);
}

// MEASURED SIM SPEED vs realtime, smoothed -- the AI's own lag detector
// (apexearth 2026-08-18: "if the host can't handle what we're doing we need
// to clean up after ourselves"). Sampled over 3-second windows of game time
// against ai.ClockUs wall time; EMA so one hitch does not flip the state.
// Headless benchmark runs read far above 1x and never trigger it.
float gLagSev = 0.f;
int gNextLagLog = 0;
double gSpeedWall = 0.0;
int gSpeedFrame = -1;
float gSimSpeed = 1.f;

void TickSpeed()
{
	if (gSpeedFrame < 0) {
		gSpeedFrame = ai.frame;
		gSpeedWall = ai.ClockUs();
		return;
	}
	const int df = ai.frame - gSpeedFrame;
	if (df < 90)
		return;
	const double now = ai.ClockUs();
	const double wallS = (now - gSpeedWall) / 1.0e6;
	if (wallS > 0.001) {
		const float inst = float((double(df) / 30.0) / wallS);
		gSimSpeed = gSimSpeed * 0.7f + inst * 0.3f;
	}
	gSpeedFrame = ai.frame;
	gSpeedWall = now;
	// THE SEVERITY LADDER (apexearth: "keep cutting back until we've caught
	// up"): every window still under the bar climbs it, every recovered
	// window walks it back down. 0 = fine; past 1 the deeper cuts unlock
	// (towers anywhere, surplus builders); past 2 the deepest (T2 army stops
	// when T3 runs). Recovery is measured, not assumed.
	if (gSimSpeed < SetSpeed() * ai.GetTunable("apex_lag_speed", TUNE_LAG_SPEED)) {
		gLagSev += ai.GetTunable("apex_lag_step", TUNE_LAG_STEP);
		if (gLagSev > 3.f)
			gLagSev = 3.f;
	} else if (gSimSpeed >= 0.995f * SetSpeed()) {
		gLagSev -= 0.2f;
		if (gLagSev < 0.f)
			gLagSev = 0.f;
	}
	if ((gLagSev > 0.f) && (ai.frame >= gNextLagLog)) {
		gNextLagLog = ai.frame + 30 * SECOND;
		AiLog("apex: LAG speed=" + formatFloat(gSimSpeed, "", 0, 2) + " set=" + formatFloat(SetSpeed(), "", 0, 1)
			+ " severity=" + formatFloat(gLagSev, "", 0, 1));
	}
}


float LagSeverity()
{
	return gLagSev;
}

// THE SPEED THE HOST ASKED FOR, and never under realtime (apexearth 2026-10-03:
// watching at 10-20x the realtime bar never fired; "we don't want to let it get
// that bad"). In multiplayer the server's speed control lowers this factor once
// the busiest client's CPU passes ~75% (GameServer.cpp), so measured against
// realtime the first throttle already reads as lag -- before the game is
// visibly slow. Above 40x is a benchmark asking for "as fast as possible".
float SetSpeed()
{
	const float s = ai.GetSpeedFactor();
	if (s > 40.f)
		return 0.f;
	return (s > 1.f) ? s : 1.f;
}

float SimSpeed()
{
	return gSimSpeed;
}

bool GameLagging()
{
	return gSimSpeed < SetSpeed() * ai.GetTunable("apex_lag_speed", TUNE_LAG_SPEED);
}

void Flush()
{
	if (!On() || ai.frame < gNextLog)
		return;
	gNextLog = ai.frame + 1800;
	for (uint i = 0; i < gNames.length(); ++i) {
		if (gCalls[i] == 0)
			continue;
		AiLog("apex: perf sec " + gNames[i] + " calls=" + gCalls[i]
			+ " totalMs=" + formatFloat(gTotalUs[i] / 1000.0, "", 0, 1)
			+ " maxMs=" + formatFloat(gMaxUs[i] / 1000.0, "", 0, 1));
		gTotalUs[i] = 0.0;
		gMaxUs[i] = 0.0;
		gCalls[i] = 0;
	}
}

}  // namespace Perf
