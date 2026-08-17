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
array<double> gTotalUs;
array<double> gMaxUs;
array<uint> gCalls;
int gNextLog = 0;

bool On()
{
	if (!gInit) {
		gInit = true;
		gOn = ai.GetTunable("apex_perf", 1.f) > 0.5f;
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
	for (uint i = 0; i < gNames.length(); ++i) {
		if (gNames[i] == name) {
			idx = int(i);
			break;
		}
	}
	if (idx < 0) {
		gNames.insertLast(name);
		gTotalUs.insertLast(0.0);
		gMaxUs.insertLast(0.0);
		gCalls.insertLast(0);
		idx = int(gNames.length()) - 1;
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
