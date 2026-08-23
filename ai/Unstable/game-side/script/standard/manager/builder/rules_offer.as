namespace Builder {

// Screening what DefaultMakeTask hands back.
//
// mexup/geo/geoup offers are not taken unconditionally here: brain.as's
// MexUpgradeWant ranks them on economic value inside Brain::Decide, and
// `if (task !is null) return task;` in maketask.as's MakeTaskInner already
// returns any leftover engine offer once nothing else claimed the builder.
// That is the whole of "last resort". A bare MEX offer is the exception --
// see MexOffer below.

// THE ENGINE WAS ALREADY SENDING SOMEBODY AND WE KEPT SAYING NO.
//
// CBuilderManager's own elector (MakeBuilderTask) walks the queued tasks and
// hands back the one it has chosen a builder for. When that is the Brain's
// front tower, every rule below gets to answer instead -- Brain::Decide most
// of all, which cheerfully orders ANOTHER front tower -- and the offer is
// thrown away, honoured only at the very bottom of AiMakeTask, by which point
// nothing is left.
//
// A STOP, not a spend: it enqueues nothing and can only decline to discard work
// already ordered and already staffed.
// A MEX THE ENGINE ALREADY ELECTED A BUILDER FOR OUTRANKS ANY OPTIONAL WANT.
//
// FindOpenMexSpot -- the only mex search a script can run -- deliberately
// excludes ally-zone spots (EconomyManager.cpp's predicate:
// `!terrainMgr->IsZoneAlly(p)`; it exists for frontier reroutes, not home
// territory), so MexWant in brain.as never proposes, and can never win, a
// home mex. DefaultMakeTask's own native mex-task creation still covers home
// spots, but only on its own scan cadence, not synchronously with a builder's
// next election. In the gap, an idle builder standing right next to an
// unclaimed home mex was seen to sit idle and then walk off to an optional
// want (gantry, nano, ...) instead, because those wants don't depend on
// FindOpenMexSpot and can fire the moment the builder goes idle. Once the
// engine's own scan DOES offer that mex, take it before anything optional
// gets a turn.
IUnitTask@ MexOffer(IUnitTask@ task, CCircuitUnit@ unit)
{
	if (ai.GetTunable("apex_take_mex_offer", TUNE_TAKE_MEX_OFFER) <= 0.f)
		return null;
	if ((task is null) || (task.GetType() != Task::Type::BUILDER))
		return null;
	if (task.GetBuildType() != int(Task::BuildType::MEX))
		return null;
	const AIFloat3 at = task.GetBuildPos();
	if (OnMap(at) && (ThreatFor(unit, at) > CON_THREAT_VETO))
		return null;
	return task;
}

IUnitTask@ FrontDefenceOffer(IUnitTask@ task)
{
	// Default OFF: the refusal this addresses is not the binding one -- see
	// IBuilderTask::FindBuildSite. Kept off until the site search allows a
	// threatened cell at all; on its own it only shuffles which offer is declined.
	if (ai.GetTunable("apex_take_front_offer", TUNE_TAKE_FRONT_OFFER) <= 0.f)
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
	// Only about JOINING someone else's build -- task.GetUnits() is the set of
	// units already on it, so an empty list means this unit would be starting
	// fresh, not assisting, and is left alone. Mex/mex-upgrade tasks are
	// exempt: assisting one of those is exactly the behavior a resource crunch
	// should produce more of, not less.
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
		// Cap redundant same-type factories: DefaultMakeTask independently offers
		// the same factory type to every idle constructor with nothing on the
		// script side capping how many we actually want. CCircuitDef is owned
		// per CCircuitAI instance, so .count is THIS player's own
		// standing+in-progress count, not the team's.
		//
		// task.GetUnits() is the set of units ALREADY on this task; a nonzero
		// count means this is a build already underway, not a new request, and
		// can't be redundant by definition -- exempt it from both the count cap
		// and the spacing cooldown. Without this exemption a constructor pulled
		// off an in-progress factory by real threat and returning once safe
		// gets refused as if requesting a new one, and reroutes to expansion
		// instead of finishing the build.
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
				// reached) only runs on the true-failure path, once SaferMex/
				// ContestDefence have both declined -- otherwise routine successful
				// reroutes would trip the same threshold as repeated real failures.
				ConStrike(unit);
				@task = null;
			}
		}
	}
	return task;
}

}  // namespace Builder
