namespace Military {

// A ROLLING BOMB IS ONE DELIVERY OF ONE EXPLOSION, NOT A LINE UNIT (apexearth
// 2026-09-22: "make sure that rolling bombs don't group up into squads and
// make sure they just head straight for enemies. They should try to avoid
// being near allies so when they blow up they don't hurt allies").
//
// Named, not inferred. The property that defines these -- the weapon IS the
// unit's own death -- is not on any engine field the script can read, and the
// attributes that look like it are not unique: `melee` in behaviour.json also
// carries Warrior, Zeus, Banisher, Bantha, Pyro, Korgoth and Juggernaut, so
// keying on it would have disbanded half the assault line. All three are
// roled `raider` in behaviour.json, which is what routed them into raid packs
// and, once T2 stood, into the massing pool.
bool IsRollingBomb(const CCircuitDef@ cdef)
{
	if (cdef is null)
		return false;
	const string n = cdef.GetName();
	// Armada and Cortex only: this build's unit table has no Legion bomb.
	// The scavenger variant must be named too -- it inherited nothing from
	// armvader and so both grouped and retreated, which for a nuclear bomb
	// means detonating in our own base (apexearth 2026-09-23).
	return (n == "armvader")      // Tumbleweed, Amphibious Rolling Bomb
		|| (n == "armvadert4")    // Epic Tumbleweed, the NUCLEAR one
		|| (n == "corroach")      // Bedbug, Amphibious Crawling Bomb
		|| (n == "corsktl");      // Skuttle, Advanced Amphibious Crawling Bomb
}

}
