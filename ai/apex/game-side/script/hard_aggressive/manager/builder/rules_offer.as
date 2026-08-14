namespace Builder {

// Screening what DefaultMakeTask hands back.
//
// ExpansionAlwaysWins used to live here: an early, unconditional take of any
// MEX/MEXUP/GEO/GEOUP offer, ahead of energy, defence and Brain::Decide's
// ranked wants. Removed 2026-08-14 -- apexearth: "ExpansionAlwaysWins was
// always supposed to be a 'last resort' task when there's nothing better to
// do," which is the opposite of where it sat. brain.as's MexWant already
// ranks mex on real economic value inside Brain::Decide, and
// `if (task !is null) return task;` in maketask.as's MakeTaskInner already
// returns any leftover engine offer -- mex included -- once nothing else
// claimed the builder. That is the whole of "last resort"; no replacement
// function was needed. Measured live, 8v8: mex offers had outnumbered every
// other type 493:46 with the early return in place.

// THE ENGINE WAS ALREADY SENDING SOMEBODY AND WE KEPT SAYING NO.
//
// CBuilderManager's own elector (MakeBuilderTask) walks the queued tasks and
// hands back the one it has chosen a builder for. When that is the Brain's
// front tower, every rule below gets to answer instead -- Brain::Decide most
// of all, which cheerfully orders ANOTHER front tower -- and the offer is
// thrown away. It is only honoured at the very bottom of AiMakeTask, by which
// point nothing is left.
//
// Measured: the front orders are not aborted and are not unreachable, they are
// alive and unstaffed -- 48-105 queued with no worker against 1-18 aborted, per
// player per game. Neither Priority::NOW (which the elector documents as
// "disregard safety") nor holding the task through the walk changed that, because
// the refusal is ours.
//
// A STOP, not a spend: it enqueues nothing and can only decline to discard work
// already ordered and already staffed.
IUnitTask@ FrontDefenceOffer(IUnitTask@ task)
{
	// Default OFF: measured neutral (defences 10.3 -> 9.1 per player, still 0-1%
	// forward), because the refusal it addresses is not the binding one -- see
	// IBuilderTask::FindBuildSite. Kept, and off, until the site search allows a
	// threatened cell at all; on its own it only shuffles which offer is declined.
	if (ai.GetTunable("apex_take_front_offer", 0.f) <= 0.f)
		return null;
	if ((task is null) || (task.GetType() != Task::Type::BUILDER))
		return null;
	if (task.GetBuildType() != int(Task::BuildType::DEFENCE))
		return null;
	const AIFloat3 at = task.GetBuildPos();
	if (!OnMap(at))
		return null;
	if (!Military::OnBorder(at) && !Military::NearFront(at))
		return null;
	return task;
}

IUnitTask@ VetoCrisisAssist(IUnitTask@ task)
{
	// apexearth: "have our units never assist another unit build something if
	// we are out of a resource (<5%). This should help encourage getting
	// mexes." Only about JOINING someone else's build -- task.GetUnits() is
	// the set of units already on it, so an empty list means this unit would
	// be starting fresh, not assisting, and is left alone. Mex/mex-upgrade
	// tasks are exempt: assisting one of those is exactly the behavior a
	// resource crunch should produce more of, not less.
	// A fresh-context agent flagged this (added in 6214df3, smoke-tested
	// only at the time) as a possible contributor to Cortex's drop from a
	// documented 96.3% peak (2a9613e) to 68.8%. Tested directly: disabling
	// this AND the factory-cap exemption above for a 16-game Cortex mirror
	// (same seeds as the 68.8% baseline) gave 62.5% -- no recovery.
	// Hypothesis rejected by data; restored.
	if ((task !is null) && (task.GetType() == Task::Type::BUILDER)
		&& (task.GetBuildType() != Task::BuildType::MEX)
		&& (task.GetBuildType() != Task::BuildType::MEXUP)
		&& (task.GetUnits().length() > 0))
	{
		const bool metalCrit = (aiEconomyMgr.metal.storage > 0.f)
				&& (aiEconomyMgr.metal.current < aiEconomyMgr.metal.storage * RESOURCE_CRISIS_FRAC);
		const bool energyCrit = (aiEconomyMgr.energy.storage > 0.f)
				&& (aiEconomyMgr.energy.current < aiEconomyMgr.energy.storage * RESOURCE_CRISIS_FRAC);
		if (metalCrit || energyCrit) {
			@task = null;
		}
	}
	return task;
}

// `taken` means the returned handle is the final answer; otherwise it is the
// offer to carry on with, which may be null.

IUnitTask@ ScreenOffer(CCircuitUnit@ unit, bool isComm, IUnitTask@ task, bool &out taken)
{
	taken = false;
	// Refusing to accept the job in the first place. Reached from CIdleTask, where
	// returning null simply leaves the unit idle until the next idle sweep.
	if (!isComm) {
		// Jammer area-clustering veto (see AreaHasJammer's own comment). Checked
		// before SiteBuildName's whitelist, since jammers fall outside it (kind
		// would be "" and none of the checks below would ever see this task).
		// GetBuildPos() is only valid for BUILDER-type tasks -- SiteBuildName
		// guards this same way; missing it here crashed the native DLL at
		// ~1.2 minutes in every game of an 8-game batch (armada-bisect-
		// outrange-revert-8) the first time this path was actually exercised.
		if ((task !is null) && (task.GetType() == Task::Type::BUILDER) && IsJammerDef(task.buildDef)) {
			const AIFloat3 jsite = task.GetBuildPos();
			if (AreaHasJammer(jsite)) {
				++gConRefused;
				LogConVeto(unit, "refuse", "jammer-cluster", 0.f);
				@task = null;
			} else {
				gJammerPos.insertLast(jsite);
				gJammerAt.insertLast(ai.frame);
			}
		}
		string kind = SiteBuildName(task);
		// Cap redundant same-type factories. tools/combat_events.py (built this
		// session) caught what the earlier bot-lab-request-cooldown fix
		// (BOTLAB_REQUEST_COOLDOWN) missed: that fix only gates the ONE script
		// branch that asks for a bot lab when we have none, but corlab kept
		// getting placed again and again well after the first one existed --
		// 8, even 10 placements inside a few minutes for a single
		// healthy-economy player, gaps as short as 6 seconds apart. Nothing
		// that fast is a rebuild-after-loss; this can only be the stock
		// engine's own DefaultMakeTask independently offering the same
		// factory type to every idle constructor, with nothing on the script
		// side capping how many of one type we actually want. CCircuitDef is
		// owned per CCircuitAI instance (see Air.as's own note on this), so
		// .count here is THIS player's own standing+in-progress count, not
		// the team's.
		// apexearth's T2 rush stalling at 18m traced (fresh-context agent
		// review, 2026-08-06) to exactly this cap: a constructor legitimately
		// pulled off the advanced-lab build by real threat (con-veto abandon,
		// threat=12) tried to resume the SAME single in-progress build once
		// safe, and this cap refused it every time as if it were requesting
		// a brand new redundant factory -- rerouting to factory-cap-fallback-
		// mex instead of finishing the T2 lab, repeatedly, well past the
		// factory-cap threat window's own frame. task.GetUnits() is the set
		// of units ALREADY on this task; a nonzero count means this is a
		// build already underway, not a new request, and can't be redundant
		// by definition -- exempt it from both the count cap and the spacing
		// cooldown, which exist only to stop DefaultMakeTask independently
		// offering a brand new factory to every idle constructor.
		//
		// A different fresh-context agent later flagged this exemption as a
		// possible contributor to Cortex's drop from a documented 96.3% peak
		// (2a9613e) to 68.8%. Tested directly: reverting this AND the
		// resource-crisis block below to a 16-game Cortex mirror (same
		// seeds as the 68.8% baseline) gave 62.5% -- no recovery, slightly
		// worse if anything. Hypothesis rejected by data; restored.
		if ((kind == "factory") && (task !is null) && (task.GetUnits().length() == 0)) {
			const CCircuitDef@ wantFac = task.buildDef;
			if (wantFac !is null) {
				const int id = wantFac.id;
				const bool tracked = (id >= 0) && (uint(id) < gNextFactoryRequest.length());
				const bool tooSoon = tracked && (ai.frame < gNextFactoryRequest[id]);
				if ((wantFac.count >= FactoryTypeCap()) || tooSoon) {
					++gConRefused;
					LogConVeto(unit, "refuse", "factory-cap", float(wantFac.count));
					// Previously just @task = null here, which (per CIdleTask's own
					// contract, see the function-level comment above) leaves the
					// unit fully idle until the next idle sweep. Redirect to
					// expansion first -- see FallbackMex's own comment for the
					// traced mechanism and evidence.
					IUnitTask@ fallback = FallbackMex(unit);
					@task = fallback;
					if (fallback !is null)
						kind = "mex";
				} else if (tracked) {
					gNextFactoryRequest[id] = ai.frame + FACTORY_REQUEST_SPACING;
				}
			}
		}
		if ((task !is null) && (kind != "")) {
			const AIFloat3 site = task.GetBuildPos();
			float heat = ThreatFor(unit, site);
			if (kind == "mex")
				heat = MexHeat(site, heat);
			if (heat > CON_THREAT_VETO) {
				++gConRefused;
				LogConVeto(unit, "refuse", kind, heat);
				// CIdleTask assigns whatever comes back, so unlike the abandon
				// path above this one can hand over a task the engine already
				// holds -- a mex the same constructor reads as cold.
				if (kind == "mex") {
					IUnitTask@ other = SaferMex(unit, task);
					if (other !is null) {
						taken = true;
						return other;
					}
				}
				IUnitTask@ post = ContestDefence(unit, kind, heat, task.GetBuildPos());
				if (post !is null) {
					taken = true;
					return post;
				}
				// ConStrike (which can trigger Fortify/dig-in once TROUBLE_HITS is
				// reached) previously fired unconditionally on every refusal, even
				// when SaferMex/ContestDefence immediately found a working
				// alternative one line later -- three routine successful reroutes
				// (business as usual, not persistent blocking) could trip the same
				// threshold as three genuine repeated failures. apexearth, watching
				// a game: "i see us making too many t1.5 defenses and advanced
				// energy converters before we've even captured all our backline
				// mexes." Moved to only the true-failure path, where no alternative
				// was found at all.
				ConStrike(unit);
				@task = null;
			}
		}
	}
	return task;
}

}  // namespace Builder
