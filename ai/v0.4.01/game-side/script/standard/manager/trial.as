// A SEAT-LEVEL TRIAL (his 10-23: "keep track of it and measure it over time so that when I play a multiplayer game
// I can show through the game whether or not it's working"). While apex_trial_<name> is on, each seat flips a coin
// once for the switch apex_<name>, logs its arm, and logs every minute what the change did and how the seat is
// doing; tools/trial_report.py compares the arms across his archived games. Off, the switch reads as always.

namespace Trial {

array<string> gName;
array<int> gArm;
array<string> gKey;    // "<trial>.<key>"
array<float> gVal;
float gKilledM = 0.f;  // enemy metal killed by this seat
float gLostM = 0.f;    // own metal lost
int gNextLog = 1800;   // a minute of frames

bool Running(const string& in name, float trialDefault)
{
	return ai.GetTunable("apex_trial_" + name, trialDefault) > 0.f;
}

// The switch's value for this seat: its coin while the trial runs (apex_trial_<name>, default trialDefault),
// else apex_<name> as usual.
bool On(const string& in name, float tuneDefault, float trialDefault)
{
	if (!Running(name, trialDefault))
		return ai.GetTunable("apex_" + name, tuneDefault) > 0.f;
	for (uint i = 0; i < gName.length(); ++i)
		if (gName[i] == name)
			return gArm[i] == 1;
	const int arm = AiRandom(0, 1);
	gName.insertLast(name);
	gArm.insertLast(arm);
	AiLog("apex: trial name=" + name + " arm=" + arm + " t=" + ai.teamId);
	return arm == 1;
}

void Note(const string& in name, const string& in key, float v)
{
	const string k = name + "." + key;
	for (uint i = 0; i < gKey.length(); ++i) {
		if (gKey[i] == k) {
			gVal[i] += v;
			return;
		}
	}
	gKey.insertLast(k);
	gVal.insertLast(v);
}

void NoteKill(float m) { gKilledM += m; }
void NoteLoss(float m) { gLostM += m; }

// Once a minute, one line per trial this seat is in: its arm, the trial's own counters, and the seat's state.
void Tick()
{
	if ((gName.length() == 0) || (ai.frame < gNextLog))
		return;
	gNextLog = ai.frame + 1800;
	for (uint i = 0; i < gName.length(); ++i) {
		string s = "apex: trial-stat name=" + gName[i] + " arm=" + gArm[i] + " t=" + ai.teamId
				+ " min=" + (ai.frame / (60 * SECOND))
				+ " mInc=" + int(Eco::MInc()) + " eInc=" + int(Eco::EInc())
				+ " killedM=" + int(gKilledM) + " lostM=" + int(gLostM);
		const string pre = gName[i] + ".";
		for (uint k = 0; k < gKey.length(); ++k)
			if (gKey[k].findFirst(pre) == 0)
				s += " " + gKey[k].substr(pre.length()) + "=" + int(gVal[k]);
		AiLog(s);
	}
}

}  // namespace Trial
