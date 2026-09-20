namespace Market {

const int WK_NONE = 0;
const int WK_MEX = 1;
const int WK_ENERGY = 2;
const int WK_PLANT = 3;
const int WK_GEO = 4;
const int WK_CONVERT = 5;
const int WK_STORE = 6;
const int WK_MEXUP = 7;
const int WK_TECH = 8;
const int WK_NANO = 9;
const int WK_RECLAIM = 10;
const int WK_ASSIST = 11;
const int WK_PROTECT = 12;
const int WK_SENSE = 13;
const int WK_AIRDEF = 14;
const int WK_SUPER = 15;
const int WK_TEETH = 16;

class Want {
	int kind = WK_NONE;
	CCircuitDef@ def;
	AIFloat3 pos;
	int spotId = -1;
	// The unit this want acts ON, where it acts on one. Reclaim used to pass it
	// through a namespace global, so a second reclaim proposer running in the
	// same election overwrote the first's target and the executor -- which
	// checks the global against spotId -- silently dropped whichever won.
	CCircuitUnit@ target;
	// Set only by the OBSOLETE reclaim proposer: this reclaim is a
	// RETIREMENT decision, so its execution arms the rebuy discount. A
	// blocker or penned reclaim eats a thing that is in the way, which says
	// nothing about wanting the def again elsewhere.
	bool retire = false;
	float gain = 0.f;
	float mCost = 0.f;
	float tCost = 0.f;
	float value = 0.f;
	// How long this want stands as a defenceless nanoframe. Set by ValueOf,
	// read by the construction-risk charge in Decide.
	float buildSec = 0.f;
	float walkSec = 0.f;    // the asker's road to pos, so the ladder can charge it
	float tripM = 0.f;      // the asker's expected loss on that road (TripRisk x its worth)
	float valueRaw = 0.f;   // value before the trip was charged
}

// Wants compete as CATEGORIES, not as kinds. A kind is one proposer; a
// category is one economic question ("more metal out of ground", "more
// energy work"). Four separate energy kinds each drew their own lottery
// ticket, so the energy question was asked four times per election and the
// extraction question twice -- 672 wind turbines against 1 moho upgrade.
// One ticket per category, argmax inside it.
const int CAT_NONE = -1;
const int CAT_METAL = 0;
const int CAT_ENERGY = 1;
const int CAT_PRODUCE = 2;
const int CAT_BP = 3;
const int CAT_DEFENCE = 4;
const int CAT_RECLAIM = 5;
// SEEING is not SHOOTING. Radar, jammers and targeting shared one ticket with
// ground defence and lost the argmax inside it every time, so the AI built no
// sensors of any kind at all. A turret's
// gain is the loss it prevents outright, which is always larger than an
// insurance rate on the same assets -- so the two never belonged in one
// question (his own rule, first applied to energy).
const int CAT_SENSE = 6;
// AIR DEFENCE IS NOT GROUND DEFENCE. They share no substitutability -- an LLT
// stops nothing that flies -- yet AA argmaxed against ground turrets, whose
// gain is loss prevented outright, and lost every election. Watched: minutes
// of bombing with no T1 AA bought, on a unit that costs ~60 metal.
const int CAT_AIRDEF = 7;
// THE STRATEGIC QUESTION IS NOT THE TURRET QUESTION. A gantry, a silo, an
// anti-nuke and a long-range gun are bought because the economy can carry
// them, not because they out-earn a mex per metal -- priced against ground
// defence they lose every election, and the AI has never built one
// (apexearth: "if I can afford this, I'll insert it as a want so we make
// one"). Own category, own ticket, argmax inside it.
const int CAT_SUPER = 8;
const int CAT_N = 9;

// A new mex and a moho are the SAME purchase, so they argmax against each
// other: new spots outbid upgrades while ground remains (25.4 vs 9.05,
// measured), and once ProposeMex runs dry the upgrade takes the category
// uncontested. The sequencing falls out of the prices, not a rule.
int CategoryOf(int k)
{
	if ((k == WK_MEX) || (k == WK_MEXUP)) return CAT_METAL;
	if ((k == WK_ENERGY) || (k == WK_GEO) || (k == WK_CONVERT) || (k == WK_STORE))
		return CAT_ENERGY;
	if ((k == WK_PLANT) || (k == WK_TECH)) return CAT_PRODUCE;
	if ((k == WK_NANO) || (k == WK_ASSIST)) return CAT_BP;
	if ((k == WK_PROTECT) || (k == WK_TEETH)) return CAT_DEFENCE;
	if (k == WK_SENSE) return CAT_SENSE;
	if (k == WK_AIRDEF) return CAT_AIRDEF;
	if (k == WK_SUPER) return CAT_SUPER;
	if (k == WK_RECLAIM) return CAT_RECLAIM;
	return CAT_NONE;
}

string CatName(int c)
{
	if (c == CAT_METAL) return "metal";
	if (c == CAT_ENERGY) return "energy";
	if (c == CAT_PRODUCE) return "produce";
	if (c == CAT_BP) return "buildpower";
	if (c == CAT_DEFENCE) return "defence";
	if (c == CAT_SENSE) return "sense";
	if (c == CAT_AIRDEF) return "airdef";
	if (c == CAT_SUPER) return "super";
	if (c == CAT_RECLAIM) return "reclaim";
	return "none";
}

string KindName(int k)
{
	if (k == WK_MEX) return "mex";
	if (k == WK_ENERGY) return "energy";
	if (k == WK_PLANT) return "plant";
	if (k == WK_GEO) return "geo";
	if (k == WK_CONVERT) return "convert";
	if (k == WK_STORE) return "store";
	if (k == WK_MEXUP) return "mexup";
	if (k == WK_TECH) return "tech";
	if (k == WK_NANO) return "nano";
	if (k == WK_RECLAIM) return "reclaim";
	if (k == WK_ASSIST) return "assist";
	if (k == WK_PROTECT) return "protect";
	if (k == WK_SENSE) return "sense";
	if (k == WK_AIRDEF) return "airdef";
	if (k == WK_SUPER) return "super";
	if (k == WK_TEETH) return "teeth";
	return "none";
}


}  // namespace Market
