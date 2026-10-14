"""Cases for check.py's reserved-word check: python tools/hooks/test_check_reserved.py"""
import os
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import check  # noqa: E402

BAD = [
    "void SgBuildable(float reach, array<int>& out)",
    "void F(int in)",
    "\tconst float out = 1.f;",
    "void G(float& out h, int& out null)",
]
GOOD = [
    "void SgHave(float reach, float& out h, float& out dsum, float& out metal)",
    "void F(const array<float>& in score, float t, array<float>& w)",
    "\tconst AIFloat3 from = unit.GetPos(ai.frame);",
    "\tif ((x is null) || (y !is null)) return;",
    "\treturn null;",
    "\tFoo(a, b, c);",
    "\tif (not done and (a or b)) {",
    "void H(CCircuitUnit@ unit, IUnitTask@ shared)",
]


def errors_for(line):
    with tempfile.TemporaryDirectory() as d:
        root = Path(d) / "script"
        root.mkdir()
        (root / "t.as").write_text(line + "\n", encoding="utf8")
        rep = check.Report()
        check.check_angelscript(root, rep)
        return rep.errors


wrong = [l for l in BAD if not errors_for(l)] + [l for l in GOOD if errors_for(l)]
for l in wrong:
    print("WRONG:", l)
print("ok" if not wrong else "%d wrong" % len(wrong))
sys.exit(1 if wrong else 0)
