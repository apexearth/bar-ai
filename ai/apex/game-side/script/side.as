// Faction dispatch. Nearly every def this AI names by hand comes as an
// Armada/Cortex/Legion triple, and the five-line if-chain that picks one was
// written out about twenty times across the managers.
//
// ai.GetSideName() is the only faction test available to the script; the masks
// in Side:: belong to the init module, which is compiled separately.

CCircuitDef@ SideDef3(const string& in arm, const string& in cor, const string& in leg)
{
	const string side = ai.GetSideName();
	if (side == "cortex")
		return ai.GetCircuitDef(cor);
	if (side == "legion")
		return ai.GetCircuitDef(leg);
	return ai.GetCircuitDef(arm);
}

// Same choice, when the caller needs the NAME rather than the def.
string SideName3(const string& in arm, const string& in cor, const string& in leg)
{
	const string side = ai.GetSideName();
	if (side == "cortex")
		return cor;
	if (side == "legion")
		return leg;
	return arm;
}
