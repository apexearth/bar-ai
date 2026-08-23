// Watch-game overlays. Each is its own toggle so a session can turn on only the
// question being asked -- the server drops map-draw commands once 25 arrive
// inside 50ms (see DRAW_PER_TICK), so every overlay at once loses most of them.
//
// All of these draw LINES. A point is a ping: it alerts and flashes the minimap,
// which is unreadable at this density. Allies and spectators see these, so every
// toggle is off by default and the harness opts in per run.

namespace Front {

// A cross centred on `at`, so a single position reads as a mark rather than a
// stray line end.
void EnqueueCross(const AIFloat3& in at, float r)
{
	if (!OnMap(at))
		return;
	AIFloat3 a = at; a.x -= r; a.z -= r;
	AIFloat3 b = at; b.x += r; b.z += r;
	AIFloat3 c = at; c.x -= r; c.z += r;
	AIFloat3 d = at; d.x += r; d.z -= r;
	if (OnMap(a) && OnMap(b)) Enqueue(a, b);
	if (OnMap(c) && OnMap(d)) Enqueue(c, d);
}

// (DrawMexClaims died with the mex task ledger in the overhaul kill.)

int gNextLaneDraw = 0;
array<AIFloat3> gLaneDrawn;

// WHERE THE ARMY IS TOLD TO STAND, and where the medics hold behind it. The
// lane is the staging anchor every squad reads; the second cross is the medic
// station (apex_medic_setback back from it), so "the medics are standing in the
// fight" is a thing you can see rather than deduce from losses.
void DrawLane()
{
	if (ai.GetTunable("apex_draw_lane", TUNE_DRAW_LANE) <= 0.f)
		return;
	if (ai.frame < gNextLaneDraw)
		return;
	gNextLaneDraw = ai.frame + 10 * SECOND;
	for (uint i = 0; i < gLaneDrawn.length(); ++i)
		Enqueue(gLaneDrawn[i], gLaneDrawn[i]);
	gLaneDrawn.resize(0);

	const AIFloat3 lane = Military::LanePos();
	if (!OnMap(lane) || (lane.SqLength2D() < 1.f))
		return;
	EnqueueCross(lane, 260.f);
	gLaneDrawn.insertLast(lane);

	const float setback = ai.GetTunable("apex_medic_setback", TUNE_MEDIC_SETBACK);
	if ((setback > 0.f) && Builder::gHomeSet) {
		AIFloat3 toHome = Builder::gHomePos - lane;
		const float len = sqrt(toHome.SqLength2D());
		if (len > 1.f) {
			const AIFloat3 back = lane + toHome * (setback / len);
			if (OnMap(back)) {
				EnqueueCross(back, 160.f);
				Enqueue(lane, back);   // the step the wounded are meant to take
				gLaneDrawn.insertLast(back);
			}
		}
	}
}

// (DrawMexExposure died with the mex-guard rules in the overhaul kill.)

int gNextHealDraw = 0;

// A PING, not a line: apexearth asked for "a ping spot for where units would go
// to heal", and one labelled marker is exactly what a ping is good for -- it is
// only unreadable at density. This is the SAME point CRetreatTask computes
// (front + apex_retreat_behind toward home), so if the ping sits somewhere
// stupid, that is where the wounded are being sent.
void DrawHealPost()
{
	if (ai.GetTunable("apex_draw_heal", TUNE_DRAW_HEAL) <= 0.f)
		return;
	if (ai.frame < gNextHealDraw)
		return;
	gNextHealDraw = ai.frame + 30 * SECOND;

	const float behind = ai.GetTunable("apex_retreat_behind", 0.f);
	const AIFloat3 lane = Military::LanePos();   // == circuit->GetFrontPos()
	if ((behind <= 0.f) || !OnMap(lane) || (lane.SqLength2D() < 1.f) || !Builder::gHomeSet)
		return;
	AIFloat3 toHome = Builder::gHomePos - lane;
	const float len = sqrt(toHome.SqLength2D());
	if (len <= 1.f)
		return;
	const AIFloat3 post = lane + toHome * (behind / len);
	if (!OnMap(post))
		return;
	ai.DrawPoint(post, "heal post");
}

void DrawDiagnostics()
{
	DrawLane();
	DrawHealPost();
}

}  // namespace Front
