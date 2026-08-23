namespace Builder {

// KILL PHASE (docs/20-brain-overhaul.md): the hooks keep only senses and the
// Requests plumbing's bookkeeping. All spend-side ledgers died with their
// rules.

// Per-unit task history ring, read by the death log in main.as.
array<int>    gHistId;
array<string> gHistBuf;

int HistSlot(int id)
{
	for (uint i = 0; i < gHistId.length(); ++i) {
		if (gHistId[i] == id)
			return int(i);
	}
	return -1;
}

string TakeHistFor(int id)
{
	const int s = HistSlot(id);
	if (s < 0)
		return "";
	const string hist = gHistBuf[s];
	gHistId.removeAt(uint(s));
	gHistBuf.removeAt(uint(s));
	return hist;
}

void AiTaskAdded(IUnitTask@ task)
{
	if (task.GetType() != Task::Type::BUILDER)
		return;
	Requests::Register(task);
}

void AiTaskRemoved(IUnitTask@ task, bool done)
{
	if (task.GetType() != Task::Type::BUILDER)
		return;
	Requests::Forget(task);
}

// Fusion ledger: a sense read by requests dedup, LateGame and the role
// objective. Names, not a cost band.
array<CCircuitUnit@> gFusions;

bool IsFusion(const CCircuitDef@ cdef)
{
	if (cdef is null)
		return false;
	const string n = cdef.GetName();
	return (n == "armfus") || (n == "corfus") || (n == "legfus")
		|| (n == "armafus") || (n == "corafus") || (n == "legafus");
}

// The commander handle and home position: the anchor every front-fraction and
// rear-of-base read derives from (sitesafety.as, military).
// CCircuitUnit is registered NOCOUNT -- a stored handle is not nulled when the
// engine destroys the unit, so removal MUST clear it.
CCircuitUnit@ gComm = null;
AIFloat3 gHomePos;
bool gHomeSet = false;

void AiUnitAdded(CCircuitUnit@ unit, Unit::UseAs usage)
{
	Brain::NoteSpend(unit, usage);
	if (IsFusion(unit.circuitDef))
		gFusions.insertLast(unit);
	if (unit.circuitDef.IsRoleAny(Unit::Role::COMM.mask) && (gComm is null)) {
		@gComm = unit;
		gHomePos = unit.GetPos(ai.frame);
		gHomeSet = true;
	}
	// A constructor sealed into a pocket is the same failure as a walled-in
	// squad. See military/unblock.as.
	if ((usage == Unit::UseAs::BUILDER) || (usage == Unit::UseAs::REZZER))
		Military::NotePenned(unit);
	if (usage == Unit::UseAs::REZZER) {
		const int rid = unit.circuitDef.id;
		if ((rid >= 0) && (uint(rid) < gRezzerDefs.length()) && !gRezzerDefs[rid]) {
			gRezzerDefs[rid] = true;
			gRezzerIds.insertLast(rid);
		}
	}
}

void AiUnitRemoved(CCircuitUnit@ unit, Unit::UseAs usage)
{
	if ((usage == Unit::UseAs::BUILDER) || (usage == Unit::UseAs::REZZER))
		Military::ForgetPenned(unit.id);
	for (uint i = 0; i < gFusions.length(); ++i) {
		if (gFusions[i] is unit) {
			gFusions.removeAt(i);
			break;
		}
	}
	if (gComm is unit) {
		AiLog(Factory::T() + "apex: COMMANDER LOST frame=" + ai.frame
			+ " hp=" + formatFloat(unit.GetHealthPercent() * 100.f, "", 0, 0));
		@gComm = null;
	}
}

void AiLoad(IStream& istream)
{
}

void AiSave(OStream& ostream)
{
}

}  // namespace Builder
