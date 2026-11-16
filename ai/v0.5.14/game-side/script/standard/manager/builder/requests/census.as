namespace Requests {

// -- the gate census ---------------------------------------------------------
//
// A gate nothing ever reaches and a gate that is reached and always passes look
// identical from a log of refusals. The Moho serialization was placed on this
// chokepoint while mex upgrades enqueue straight from Market::ExecuteWant, so it
// never saw one request; two games were spent before "moho-pass: 0" said so.
//
// seen    = the gate APPLIED to this request (its class test passed, or control
//           reached the line at all). seen=0 is dead code, and is named as such.
// refused = the gate changed the answer -- null, or a fold onto other work.
//
// It has already earned its place: one 4v4 retired Requests::Allowed and
// Requests::Redirect (ten gates, seen=0, no call sites) and the ungoverned
// early return in Take, which no build type reaching Take can satisfy.
const uint G_BADREQ   = 0;   // no def, or the spot is off the map
const uint G_CANBUILD = 1;   // the asker cannot build this def
const uint G_BACKOFF  = 2;   // this def keeps dying here (Builder::AbortBackoff)
const uint G_FACFORK  = 3;   // a factory request already stands: never a fork
const uint G_BIGE     = 4;   // one expensive reactor at a time, across defs
const uint G_COVER    = 5;   // this ground is already requested
const uint G_FRAME    = 6;   // a half-built frame of ours stands here
const uint G_JOINNEAR = 7;   // a same-def site in reach, folded onto
const uint G_FULL     = 8;   // in-flight is at the income-derived cap
const uint G_COUNT    = 9;

array<int> gGateSeen(G_COUNT, 0);
array<int> gGateRef(G_COUNT, 0);

string GateName(uint g)
{
	if (g == G_BADREQ)   return "take.badreq";
	if (g == G_CANBUILD) return "take.canbuild";
	if (g == G_BACKOFF)  return "take.backoff";
	if (g == G_FACFORK)  return "take.facfork";
	if (g == G_BIGE)     return "take.bigE";
	if (g == G_COVER)    return "take.cover";
	if (g == G_FRAME)    return "take.frame";
	if (g == G_JOINNEAR) return "take.joinnear";
	if (g == G_FULL)     return "take.full";
	return "?";
}

// `Gate(G_X, cond)` counts the visit and the refusal and returns the condition,
// so instrumenting an early return costs no branch of its own.
bool Gate(uint g, bool refuse)
{
	++gGateSeen[g];
	if (refuse)
		++gGateRef[g];
	return refuse;
}

void GateSeen(uint g)
{
	++gGateSeen[g];
}

void GateRef(uint g)
{
	++gGateRef[g];
}

// Dumped once a game-minute, so the LAST line of a match is the game-end
// census. Dead gates are named at the end because that is the finding.
int gNextGateLog = 0;

void GateCensus()
{
	if (ai.frame < gNextGateLog)
		return;
	gNextGateLog = ai.frame + 60 * SECOND;
	string line = "";
	string dead = "";
	for (uint g = 0; g < G_COUNT; ++g) {
		line += " " + GateName(g) + "=" + gGateRef[g] + "/" + gGateSeen[g];
		if (gGateSeen[g] == 0) {
			if (dead.length() > 0)
				dead += ",";
			dead += GateName(g);
		}
	}
	if (dead.length() > 0)
		line += "  DEAD: " + dead;
	AiLog(Factory::T() + "apex: gatecensus refused/seen" + line);
}

}  // namespace Requests
