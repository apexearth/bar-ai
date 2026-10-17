"""One owner for a squad-owned unit (apex_squads, docs/army.md): nothing but its Squad orders it.

    python tools/squad_check.py        # exit 1 on any finding

Script: an order reaches an owned unit only through Military::SqIssue, the one function that opens the C++ order
window (ai.SetSquadOrders); CmdFightTo and the window exist nowhere else; ownership is taken only in army.as; a
squad's roster grows only through SqJoin (the join window); the election claims the unit before any other branch.
C++: the order bindings refuse an owned unit outside the window, ITaskModule::AssignTask refuses it any task, the
idle task neither re-asks nor retreats it, the move-failed nudge skips it.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SCRIPT = REPO / "ai" / "Unstable" / "game-side" / "script" / "standard"
CPP = REPO / "cpp" / "src" / "circuit"
ARMY = "manager/military/army/"
_AS_FUNC = re.compile(r"^[A-Za-z][\w:<>@&\s]*?\b(\w+)\s*\([^;]*$")


def _code(line: str) -> str:
    return line.split("//", 1)[0]


def _functions(text: str) -> list[tuple[str, int, int]]:
    """(name, first line, last line) of each top-level function body, by brace depth."""
    out = []
    lines = text.split("\n")
    depth = 0
    name, start = "", -1
    ns_depth = 0
    for n, raw in enumerate(lines):
        code = _code(raw)
        if code.startswith("namespace "):
            ns_depth += code.count("{")
            depth += code.count("{") - code.count("}")
            continue
        if depth == ns_depth and not raw.startswith((" ", "\t")):
            m = _AS_FUNC.match(code)
            if m and not code.rstrip().endswith(";"):
                name, start = m.group(1), n
        depth += code.count("{") - code.count("}")
        if start >= 0 and depth == ns_depth and "}" in code:
            out.append((name, start, n))
            name, start = "", -1
    return out


def _owner(funcs: list[tuple[str, int, int]], n: int) -> str:
    return next((f for f, a, b in funcs if a <= n <= b), "")


def check_script(root: Path = SCRIPT) -> list[str]:
    errs: list[str] = []
    for p in sorted(root.rglob("*.as")):
        rel = p.relative_to(root).as_posix()
        text = p.read_text(encoding="utf8", errors="replace")
        funcs = _functions(text)
        in_army = rel.startswith(ARMY)
        for n, raw in enumerate(text.split("\n")):
            code = _code(raw)
            where = f"{rel}:{n + 1}"
            fn = _owner(funcs, n)
            if "SetSquadOrders(" in code and not (rel == ARMY + "squad.as" and fn == "SqIssue"):
                errs.append(f"{where}: the squad order window opens only in SqIssue")
            if "CmdFightTo(" in code and not (rel == ARMY + "squad.as" and fn == "SqIssue"):
                errs.append(f"{where}: CmdFightTo is the squads' order; issue it through SqIssue")
            if "SetSquadOwned(" in code and rel != ARMY + "army.as":
                errs.append(f"{where}: ownership is taken only in army.as")
            if in_army and re.search(r"\.(Cmd\w+|SetMoveState|SetFireState|SelfDestruct)\(", code) and fn != "SqIssue":
                errs.append(f"{where}: an order to an owned unit outside SqIssue")
            if in_army and re.search(r"\.u\.insertLast\(", code) and fn != "SqJoin":
                errs.append(f"{where}: a squad's roster grows only through SqJoin (the join window)")
    hooks = (root / "manager" / "military" / "hooks.as").read_text(encoding="utf8", errors="replace")
    i = hooks.find("IUnitTask@ MakeTaskInner(CCircuitUnit@ unit)")
    body = hooks[i:hooks.find("\n}", i)] if i >= 0 else ""
    a, b = body.find("SqClaim(unit)"), body.find("return")
    if a < 0 or (0 <= b < a):
        errs.append("manager/military/hooks.as: MakeTaskInner must claim a squad unit (SqClaim) before any other branch")
    return errs


def _body(text: str, signature: str) -> str:
    i = text.find(signature)
    if i < 0:
        return ""
    j = text.find("\n}", i)
    return text[i:j if j > 0 else len(text)]


_CPP_NEEDS = [
    ("script/InitScript.cpp", "static bool StockDropUnit(", ["IsSquadOwned()", "IsSquadOrders()"]),
    ("module/TaskModule.cpp", "void ITaskModule::AssignTask(CCircuitUnit* unit, IUnitTask* task)", ["IsSquadOwned()"]),
    ("module/TaskModule.cpp", "IUnitTask* ITaskModule::AssignTask(CCircuitUnit* unit)", ["IsSquadOwned()"]),
    ("task/IdleTask.cpp", "void CIdleTask::Update()", ["IsSquadOwned()"]),
    ("task/IdleTask.cpp", "void CIdleTask::OnUnitDamaged(", ["IsSquadOwned()"]),
    ("task/UnitTask.cpp", "void IUnitTask::OnUnitMoveFailed(", ["IsSquadOwned()"]),
]


def check_cpp(root: Path = CPP) -> list[str]:
    errs: list[str] = []
    for rel, sig, needs in _CPP_NEEDS:
        p = root / rel
        body = _body(p.read_text(encoding="utf8", errors="replace"), sig) if p.is_file() else ""
        if not body:
            errs.append(f"cpp {rel}: {sig} not found")
            continue
        for tok in needs:
            if tok not in body:
                errs.append(f"cpp {rel}: {sig} lost its squad-owner guard ({tok})")
    for p in sorted(root.rglob("*.cpp")):
        rel = p.relative_to(root).as_posix()
        for n, raw in enumerate(p.read_text(encoding="utf8", errors="replace").split("\n")):
            code = _code(raw)
            if "SetSquadOrders(" in code and rel != "script/InitScript.cpp":
                errs.append(f"cpp {rel}:{n + 1}: only the script's SqIssue opens the squad order window")
            if "SetSquadOwned(" in code and rel != "script/InitScript.cpp":
                errs.append(f"cpp {rel}:{n + 1}: only the script's Army takes a unit")
    return errs


def check(repo: Path = REPO) -> list[str]:
    return check_script(repo / "ai" / "Unstable" / "game-side" / "script" / "standard") + \
        check_cpp(repo / "cpp" / "src" / "circuit")


def main() -> int:
    errs = check()
    for e in errs:
        print(e)
    print(f"squad owner: {len(errs)} finding(s)")
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main())
