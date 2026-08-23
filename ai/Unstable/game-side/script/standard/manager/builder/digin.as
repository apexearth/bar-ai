namespace Builder {

// Contest the mex rather than sit on it: the standoff walks back toward our own
// start until the threat map reads clear, so it is set by the enemy's reach
// rather than by a constant.
const float DEF_STEP    = 160.f;
const int   DEF_STEPS   = 6;
const float DEF_SPACING = 500.f;
const int   DEF_PERIOD  = 30 * SECOND;

AIFloat3 gConDefPos;
bool gConDefPlaced = false;
int  gNextConDef = 0;

// AA/HeavyAA/Pulsar/ContestDefence/EcoFusion all gate off while
// aiEconomyMgr.isEnergyStalling, so all of them can refuse to fire at once
// while metal piles up unspent. This last-resort fallback bypasses that gate
// deliberately -- spending stalling energy on cheap ground defence beats
// letting metal overflow doing nothing.
const int METAL_FULL_DEF_PERIOD = 30 * SECOND;
int gNextMetalFullDef = 0;

// How much defence has to already stand here before we stop adding to it.
// gConDefPos alone is not that bound -- it remembers only the ONE most recent
// tower, so it cannot see a porcupine cluster build_chain already put here.
// Military::FenceCountNear reads the register of every finished defence we own,
// whatever placed it.
const float DIG_AREA      = 700.f;
const uint  DIG_MAX_FENCE = 2;
// FENCE only fires on FINISHED, so without this a burst of orders would all see
// an empty area and each add another tower. Expires on its own: a task can be
// dropped and there is no completion hook to clear it against.
const int   DIG_ORDER_TTL = 90 * SECOND;
array<AIFloat3> gDigOrderPos;
array<int>      gDigOrderAt;

// Finished defences plus still-outstanding orders within radius. FENCE only
// fires on FINISHED, so the order list is what stops a burst of requests each
// seeing the same empty ground.
uint DefenceWithin(const AIFloat3& in pos, float radius)
{
	uint n = Military::FenceCountNear(pos, radius);
	for (int i = int(gDigOrderAt.length()) - 1; i >= 0; --i) {
		if (ai.frame - gDigOrderAt[i] > DIG_ORDER_TTL) {
			gDigOrderAt.removeAt(i);
			gDigOrderPos.removeAt(i);
		} else if (gDigOrderPos[i].distance2D(pos) <= radius) {
			++n;
		}
	}
	return n;
}

uint DefenceAround(const AIFloat3& in pos)
{
	return DefenceWithin(pos, DIG_AREA);
}

const int   TROUBLE_HITS    = 3;
// No ceiling: what bounds a fence is how often this position has actually been
// shot at, which the hit count below already expresses.
const uint DIG_FENCE_PER_TROUBLE = 1;

// build_chain.json attaches a jammer to MULTIPLE separate parent hubs
// independently, each firing at a fixed offset from its own parent with
// nothing checking whether a jammer already stands nearby from a DIFFERENT
// parent's hub -- so several fusions near each other (normal) produce several
// jammers stacked near each other too. SiteBuildName() has no "jammer" kind
// (falls through its whitelist as ""), so the existing con-veto/threat-check
// block never sees them. Tracked here the same way gDigOrderPos is, by TTL
// rather than a completion hook.
string armjamt("armjamt");
string corjamt("corjamt");
string legjam2("legjam");
string legajam("legajam");
// The long-range triple. All three are named "Long-Range Jamming Tower" in the
// game's own defs and are the ones BaseJammer places; legajam above is Legion's
// and was already listed here without anything ever building it.
string armveil("armveil");
string corshroud("corshroud");
const float JAMMER_AREA     = 900.f;   // jammer coverage is wider than a defence fence
const int   JAMMER_ORDER_TTL = 180 * SECOND;   // jammers are slow to build; outlive DIG_ORDER_TTL
array<AIFloat3> gJammerPos;
array<int>      gJammerAt;

bool IsJammerDef(const CCircuitDef@ def)
{
	if (def is null)
		return false;
	const string name = def.GetName();
	return (name == armjamt) || (name == corjamt) || (name == legjam2) || (name == legajam)
		|| (name == armveil) || (name == corshroud);
}

// Returns true if a jammer already stands (or was recently ordered) within
// JAMMER_AREA of pos -- i.e. a new one here would cluster, not cover new
// ground. Ages out its own tracked orders past JAMMER_ORDER_TTL the same
// way gDigOrderPos does.
// STANDING JAMMERS COUNT, NOT ONLY RECENT ORDERS. The order ledger ages out
// after JAMMER_ORDER_TTL, so a finished jammer stopped blocking its own ground
// three minutes later and the next one could stack on it -- which is how they
// end up in a heap instead of covering the base.
float NearestJammerDist(const AIFloat3& in pos)
{
	float best = -1.f;
	for (int i = int(gJammerAt.length()) - 1; i >= 0; --i) {
		if (ai.frame - gJammerAt[i] > JAMMER_ORDER_TTL) {
			gJammerAt.removeAt(i);
			gJammerPos.removeAt(i);
			continue;
		}
		const float d = gJammerPos[i].distance2D(pos);
		if ((best < 0.f) || (d < best))
			best = d;
	}
	array<string> names = {armjamt, corjamt, legjam2, legajam, armveil, corshroud};
	for (uint k = 0; k < names.length(); ++k) {
		CCircuitDef@ d = ai.GetCircuitDef(names[k]);
		if ((d is null) || (d.count == 0))
			continue;
		array<CCircuitUnit@>@ have = ai.GetOwnUnitsOfDef(d, pos, 0.f);
		if (have is null)
			continue;
		for (uint u = 0; u < have.length(); ++u) {
			if (have[u] is null)
				continue;
			const float dd = have[u].GetPos(ai.frame).distance2D(pos);
			if ((best < 0.f) || (dd < best))
				best = dd;
		}
	}
	return best;
}

bool AreaHasJammer(const AIFloat3& in pos)
{
	const float d = NearestJammerDist(pos);
	return (d >= 0.f) && (d <= JAMMER_AREA);
}

// How much defence an area needs, given how dangerous it has proven to be.
// hits is the count of times the constructor working here has been struck --
// unlike GetBuilderThreatAt (reads zero almost everywhere and crashes off-map),
// this is a real, positional measure: something shot us, here.
//
// Hits are the TRIGGER only, not the AMOUNT: escalation saturates at three
// extra so a single cheap harasser cannot drive the want up indefinitely, and
// the whole result is scaled by the defence category's economic budget (see
// brain/budget.as, targets.as SPEND_DEFENCE), so an area can only keep
// escalating while defence overall is still under its share of our metal.
uint FenceWanted(int hits)
{
	uint want = DIG_MAX_FENCE;
	if (hits >= TROUBLE_HITS * 3)
		want += 3;
	else if (hits >= TROUBLE_HITS * 2)
		want += 2;
	else if (hits >= TROUBLE_HITS)
		want += 1;
	const float budget = Brain::BudgetMult(Brain::DEFENCE);
	const uint scaled = uint(float(want) * budget);
	return (scaled < DIG_MAX_FENCE) ? DIG_MAX_FENCE : scaled;
}

bool AreaNeedsDefence(const AIFloat3& in pos, uint wanted = DIG_MAX_FENCE)
{
	return DefenceAround(pos) < wanted;
}

void NoteDigOrder(const AIFloat3& in pos)
{
	gDigOrderPos.insertLast(pos);
	gDigOrderAt.insertLast(ai.frame);
}

}  // namespace Builder
