"""Every team-role gate, and whether a solo game can still reach the behaviour.

apexearth: "the entire eco pathway of code needs to be disabled. Same goes for
tech role related stuff. We need to be smart about this."

Disabling a ROLE is not the same as disabling a PATHWAY: the fusion rule asked
EcoLeadActive() as its only gate, so switching the role off solo meant nobody
ever built a reactor. This lists every call site so each one is a deliberate
choice rather than a discovery three bugs later.
"""
import re, pathlib

ROLE = re.compile(r"(EcoLeadActive|IsDesignatedLead|IsTechLead|RushLeadTeamId|LeadIsDesignated)\(\)")
root = pathlib.Path("ai/Unstable/game-side/script/standard/manager")
rows = []
for f in sorted(root.rglob("*.as")):
    for i, line in enumerate(f.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
        code = line.split("//")[0]
        m = ROLE.search(code)
        if not m:
            continue
        # A gate is "solo-safe" when the role is not the only thing standing
        # between the code and running: an OR with a non-role condition, or a
        # negation paired with TeamPlay().
        solo_ok = ("||" in code) or ("TeamPlay()" in code) or ("&&" in code and "!" in code.split(m.group(0))[0][-3:])
        rows.append((str(f.relative_to(root)), i, m.group(1), "reachable" if solo_ok else "ROLE-ONLY", code.strip()[:70]))

print(f"{'file':34s} {'line':>5s} {'role':18s} {'solo':10s} code")
for f, i, role, ok, code in rows:
    print(f"{f:34s} {i:5d} {role:18s} {ok:10s} {code}")
n = sum(1 for r in rows if r[3] == "ROLE-ONLY")
print(f"\n{len(rows)} gates, {n} reachable only when the role exists")
