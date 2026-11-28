// Every economy reading the script prices on, through one seam so a test can
// pose a situation (tools/wanttest.py). Unset, each returns the engine's value.
namespace Eco {

bool gOn = false;
float gMInc = 0.f, gEInc = 0.f, gMCur = 0.f, gECur = 0.f;
float gMPull = 0.f, gEPull = 0.f, gMStor = 0.f, gEStor = 0.f;
float gConvCap = -1.f, gConvUse = -1.f;   // converter capacity and draw, E/s; -1 = the game's

void Pose(float mInc, float eInc, float mCur, float eCur,
		float mPull, float ePull, float mStor, float eStor)
{
	gOn = true;
	gMInc = mInc; gEInc = eInc; gMCur = mCur; gECur = eCur;
	gMPull = mPull; gEPull = ePull; gMStor = mStor; gEStor = eStor;
}

void PoseConverters(float cap, float use) { gConvCap = cap; gConvUse = use; }

void Clear() { gOn = false; gConvCap = -1.f; gConvUse = -1.f; }

float MInc()  { return gOn ? gMInc  : aiEconomyMgr.metal.income; }
float EInc()  { return gOn ? gEInc  : aiEconomyMgr.energy.income; }
float MCur()  { return gOn ? gMCur  : aiEconomyMgr.metal.current; }
float ECur()  { return gOn ? gECur  : aiEconomyMgr.energy.current; }
float MPull() { return gOn ? gMPull : aiEconomyMgr.metal.pull; }
float EPull() { return gOn ? gEPull : aiEconomyMgr.energy.pull; }
float MStor() { return gOn ? gMStor : aiEconomyMgr.metal.storage; }
float EStor() { return gOn ? gEStor : aiEconomyMgr.energy.storage; }

}  // namespace Eco
