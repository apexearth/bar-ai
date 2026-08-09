namespace Builder {

// Contest the mex rather than sit on it. apexearth: "build defenses a safe
// distance from the mex we desire to control. That is usually what I would do."
// The standoff walks back toward our own start until the threat map reads clear,
// so it is set by the enemy's reach rather than by a constant.
const float DEF_STEP    = 160.f;
const int   DEF_STEPS   = 6;
const float DEF_SPACING = 500.f;
const int   DEF_PERIOD  = 30 * SECOND;

AIFloat3 gConDefPos;
bool gConDefPlaced = false;
int  gNextConDef = 0;

// apexearth: "its terrible if they just get full of metal and stop doing
// anything." AA/HeavyAA/Pulsar/ContestDefence/EcoFusion all gate off while
// aiEconomyMgr.isEnergyStalling, so a team can end up with every one of
// those rules simultaneously refusing to fire while metal keeps piling up
// with nowhere to go -- a fully idle unit sitting on a capped bank. Metal
// overflowing and doing nothing is strictly worse than spending some of a
// stalling energy reserve on cheap ground defense, so the last-resort
// fallback at the end of AiMakeTask bypasses that gate deliberately.
const int METAL_FULL_DEF_PERIOD = 30 * SECOND;
int gNextMetalFullDef = 0;

// How much defence has to already stand here before we stop adding to it.
//
// apexearth, asking for the dig-in behaviour back: "Last time it seemed
// unbounded so this time only do it if there seems to be a lack of defenses in
// the area already." The unbounded version was one of twelve spending rules that
// together cut metal production 4.3x -- every one of them confirmed firing, and
// the dig-in fortresses were among the most expensive.
//
// gConDefPos is not that bound: it remembers only the ONE most recent tower, so
// it cannot see a porcupine cluster build_chain already put here.
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

uint DefenceAround(const AIFloat3& in pos)
{
	uint n = Military::FenceCountNear(pos, DIG_AREA);
	for (int i = int(gDigOrderAt.length()) - 1; i >= 0; --i) {
		if (ai.frame - gDigOrderAt[i] > DIG_ORDER_TTL) {
			gDigOrderAt.removeAt(i);
			gDigOrderPos.removeAt(i);
		} else if (gDigOrderPos[i].distance2D(pos) <= DIG_AREA) {
			++n;
		}
	}
	return n;
}

const int   TROUBLE_HITS    = 3;
// Never stack more than this in one 700-elmo area, however hot it gets.
const uint DIG_FENCE_CAP = 5;

// apexearth: "Areas should have a general limit to how much they'll build
// there, especially on things like jammers... I often see many jammers all
// close together." Traced: build_chain.json attaches a jammer to MULTIPLE
// separate parent hubs independently (e.g. armjamt on three different hook
// triggers), each firing once per matching parent instance finishing, at a
// fixed offset from THAT parent -- with nothing checking whether a jammer
// already stands nearby from a DIFFERENT parent's hub. Three fusions built
// near each other (normal) produce three jammers near each other too.
//
// SiteBuildName() has no "jammer" kind at all (jammers fall through its
// whitelist as ""), so the existing con-veto/threat-check block never sees
// them. Same pattern as DefenceAround/gDigOrderPos above (no completion
// hook to clear an order against, so track by TTL instead), scoped to the
// four jammer defs actually seen in build_chain.json this session.
string armjamt("armjamt");
string corjamt("corjamt");
string legjam2("legjam");
string legajam("legajam");
const float JAMMER_AREA     = 900.f;   // jammer coverage is wider than a defence fence
const int   JAMMER_ORDER_TTL = 180 * SECOND;   // jammers are slow to build; outlive DIG_ORDER_TTL
array<AIFloat3> gJammerPos;
array<int>      gJammerAt;

bool IsJammerDef(const CCircuitDef@ def)
{
	if (def is null)
		return false;
	const string name = def.GetName();
	return (name == armjamt) || (name == corjamt) || (name == legjam2) || (name == legajam);
}

// Returns true if a jammer already stands (or was recently ordered) within
// JAMMER_AREA of pos -- i.e. a new one here would cluster, not cover new
// ground. Ages out its own tracked orders past JAMMER_ORDER_TTL the same
// way gDigOrderPos does.
bool AreaHasJammer(const AIFloat3& in pos)
{
	for (int i = int(gJammerAt.length()) - 1; i >= 0; --i) {
		if (ai.frame - gJammerAt[i] > JAMMER_ORDER_TTL) {
			gJammerAt.removeAt(i);
			gJammerPos.removeAt(i);
		} else if (gJammerPos[i].distance2D(pos) <= JAMMER_AREA) {
			return true;
		}
	}
	return false;
}

// How much defence an area needs, given how dangerous it has proven to be.
//
// apexearth: "This area is dangerous, and therefore, I should defend it better
// than it already is defended." DIG_MAX_FENCE was a flat 2 -- the same bar for a
// quiet back mex and a spot the enemy army is walking through.
//
// hits is the count of times the constructor working here has been struck. It is
// already tracked per constructor for the dig-in trigger, and unlike
// GetBuilderThreatAt -- which reads zero 97% of the time and crashes off-map --
// it is a real, positional measure of danger: something shot us, here.
uint FenceWanted(int hits)
{
	uint want = DIG_MAX_FENCE;
	if (hits >= TROUBLE_HITS * 3)
		want += 3;
	else if (hits >= TROUBLE_HITS * 2)
		want += 2;
	else if (hits >= TROUBLE_HITS)
		want += 1;
	return (want > DIG_FENCE_CAP) ? DIG_FENCE_CAP : want;
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
