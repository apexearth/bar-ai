"""The join window has one gate, and every way into a fighter squad goes through it.

    python tools/joinwin_check.py        # exit 1 on any finding

docs/doctrine.md: a squad takes members while it forms and none once it commits. The gate is
IFighterTask::JoinOpen (C++); the join paths that must ask it are ITaskModule::AssignTask, ISquadTask::Merge
and every election that picks a live task. The fix for this exact leak was made in one function at a time
three times (raids, the attack task, bombers) and the next path leaked again, so the paths are checked here:

  C++  - a direct `->AssignTo(` outside TaskModule.cpp (nil/idle tasks and the builder/factory modules
         excepted) skips the gate
       - ITaskModule::AssignTask (both overloads) asks JoinOpen
       - a fighter task's roster grows (`units.insert(`, `->SetTask(this)`) only in MergeFrom or AssignTo
       - Merge is ISquadTask's one non-virtual entry; subclasses override MergeFrom; every `->Merge(` call
         uses the verdict
       - every election over live tasks (`->CanAssignTo(`) in the military asks JoinOpen/IsJoinClosed first
       - JoinOpen and JoinTick are final
       - a fighter task reads the team push through IsFocusFor (a squad launched after the GO is not in it)
  both - each launch without a task (flights, intercepts, the wave's positions, siege pulls, JoinFight...)
         keeps its own window: _SENTINELS
  AS   - a military/air function that returns a stored task handle (a live squad) is called only through
         JwJoinable, and a guard task (TaskF::Guard returns the live one) likewise
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CPP = REPO / "cpp" / "src" / "circuit"
SCRIPT = REPO / "ai" / "Unstable" / "game-side" / "script" / "standard" / "manager"

_ASSIGN_OK_FILES = {"module/TaskModule.cpp", "module/BuilderManager.cpp", "module/FactoryManager.cpp",
                    "module/EconomyManager.cpp"}
_FUNC = re.compile(r"^[A-Za-z][\w:<>*&\s]*?\b(?:\w+)::(~?\w+)\s*\(")


def _code(line: str) -> str:
    return line.split("//", 1)[0]


def _enclosing(lines: list[str], n: int) -> str:
    for k in range(n, -1, -1):
        m = _FUNC.match(lines[k])
        if m:
            return m.group(1)
    return ""


def _body(text: str, signature: str) -> str:
    i = text.find(signature)
    if i < 0:
        return ""
    j = text.find("\n}", i)
    return text[i:j if j > 0 else len(text)]


def check_cpp(root: Path = CPP) -> list[str]:
    errs: list[str] = []
    if not root.is_dir():
        return errs
    rel = lambda p: p.relative_to(root).as_posix()
    for path in sorted(root.rglob("*.cpp")):
        r = rel(path)
        lines = path.read_text(encoding="utf8", errors="replace").splitlines()
        fighter = r.startswith("task/fighter/")
        military = fighter or r == "module/MilitaryManager.cpp"
        for n, raw in enumerate(lines):
            code = _code(raw)
            if "->AssignTo(" in code and r not in _ASSIGN_OK_FILES and "joinwin:" not in raw \
                    and not re.search(r"\b(nilTask|idleTask|GetIdleTask\(\))->AssignTo\(", code):
                errs.append(f"{r}:{n + 1}: direct AssignTo skips the join gate -- use manager->AssignTask")
            if fighter and ("units.insert(" in code or "->SetTask(this)" in code) \
                    and _enclosing(lines, n) not in ("MergeFrom", "AssignTo"):
                errs.append(f"{r}:{n + 1}: a squad's roster grows outside MergeFrom/AssignTo -- "
                            f"go through ISquadTask::Merge or ITaskModule::AssignTask")
            if "->Merge(" in code and not re.search(r"\bif\s*\(.*->Merge\(", code):
                errs.append(f"{r}:{n + 1}: Merge's verdict ignored -- a refused merge must not abort the giver")
            if fighter and re.search(r"->IsFocus\(", code):
                errs.append(f"{r}:{n + 1}: the team push read without its window -- use IsFocusFor(frame, this)")
            if military and re.search(r"\w(->|\.)CanAssignTo\(", code):
                near = "\n".join(_code(x) for x in lines[max(n - 2, 0):n + 1])
                if "JoinOpen(" not in near and "IsJoinClosed(" not in near:
                    errs.append(f"{r}:{n + 1}: an election over live tasks without the join gate -- "
                                f"ask JoinOpen(unit) / IsJoinClosed() first")
    tm = (root / "module" / "TaskModule.cpp")
    if tm.is_file():
        text = tm.read_text(encoding="utf8", errors="replace")
        for sig in ("void ITaskModule::AssignTask(CCircuitUnit* unit, IUnitTask* task)",
                    "IUnitTask* ITaskModule::AssignTask(CCircuitUnit* unit)"):
            if not re.search(r"if \([^\n]*!task->JoinOpen\(unit\)\) \{\s*\n\s*NoteJoinRefused\(task\);",
                             _body(text, sig).replace("\r\n", "\n")):
                errs.append(f"module/TaskModule.cpp: {sig} does not ask JoinOpen")
    for path in sorted((root / "task" / "fighter").glob("*.h")):
        text = "\n".join(_code(x) for x in path.read_text(encoding="utf8", errors="replace").splitlines())
        r = rel(path)
        if r == "task/fighter/SquadTask.h":
            if not re.search(r"^\s*bool\s+Merge\(ISquadTask\*\s*\w*\);", text, re.M):
                errs.append(f"{r}: Merge must be the non-virtual `bool Merge(ISquadTask*)` gate")
        elif re.search(r"\bMerge\(ISquadTask", text):
            errs.append(f"{r}: a subclass declares Merge -- override MergeFrom, the gate is ISquadTask::Merge")
        if r == "task/fighter/FighterTask.h":
            for name in ("JoinOpen", "JoinTick"):
                if not re.search(rf"\b{name}\([^)]*\)[^;]*\bfinal\b", text):
                    errs.append(f"{r}: {name} must be final so no fighter task can bypass it")
    return errs


_AS_FUNC = re.compile(r"^IUnitTask@\s+(\w+)\s*\(")
_AS_STORED = re.compile(r"\breturn\s+@?g\w+(\[[^\]]*\])?\s*;")


def _as_functions(path: Path) -> list[tuple[str, int, int]]:
    lines = path.read_text(encoding="utf8", errors="replace").splitlines()
    out = []
    for n, raw in enumerate(lines):
        m = _AS_FUNC.match(raw)
        if not m:
            continue
        end = n + 1
        while end < len(lines) and lines[end] != "}":
            end += 1
        out.append((m.group(1), n, end))
    return out


def check_script(root: Path = SCRIPT) -> list[str]:
    errs: list[str] = []
    files = [p for d in ("military", "air") if (root / d).is_dir() for p in sorted((root / d).glob("*.as"))]
    if not files:
        return errs
    texts = {p: p.read_text(encoding="utf8", errors="replace").splitlines() for p in files}
    spans: dict[Path, list[tuple[str, int, int]]] = {p: _as_functions(p) for p in files}
    getters: set[str] = set()
    electors = ("JwJoinable", "NoteElect", "AiMakeTask", "MakeTaskInner")
    for p, fs in spans.items():
        for name, a, b in fs:
            if name in electors:
                continue
            body = "\n".join(_code(x) for x in texts[p][a:b + 1])
            if _AS_STORED.search(body) or "TaskF::Guard(" in body:
                getters.add(name)
    grew = True
    while grew:
        grew = False
        for p, fs in spans.items():
            for name, a, b in fs:
                if name in getters or name in electors:
                    continue
                body = "\n".join(_code(x) for x in texts[p][a + 1:b + 1])
                if any(re.search(rf"\breturn\s+[\w:]*\b{g}\(", body) for g in getters):
                    getters.add(name)
                    grew = True
    for p in files:
        rel = p.relative_to(root.parent).as_posix()
        own = {n: (a, b) for n, a, b in spans[p]}
        for n, raw in enumerate(texts[p]):
            code = _code(raw)
            inside = next((name for name, (a, b) in own.items() if a <= n <= b), "")
            if inside in getters or inside == "JwJoinable":
                continue
            for g in getters:
                if re.search(rf"(?<![\w@])(?:\w+::)?{g}\(", code) and not _AS_FUNC.match(raw) \
                        and not re.search(rf"JwJoinable\((?:\w+::)?{g}\(", code):
                    errs.append(f"{rel}:{n + 1}: {g}() hands out a live squad -- wrap it in JwJoinable(.., unit)")
            if "TaskF::Guard(" in code and "JwJoinable(" not in code:
                errs.append(f"{rel}:{n + 1}: TaskF::Guard returns the live guard task -- wrap it in JwJoinable")
    return errs


# Launches without a task (direct move orders) and elections the gate cannot see: each keeps its own window.
_SENTINELS = [
    ("cpp/src/circuit/task/fighter/SupportTask.cpp", r"candy->JoinOpen\(unit\)", "support bots pick only open squads"),
    ("cpp/src/circuit/task/fighter/SquadTask.cpp", r"candidate->IsEngaged\(\)", "no merge into a squad in a fight"),
    ("cpp/src/circuit/task/fighter/BombTask.cpp", r"strike_f", "only the wave is credited with the strike's power"),
    ("ai/Unstable/game-side/script/standard/manager/air/flight.as", r"gFlightSent && Military::GthOn\(\)",
     "the scout flight leaves once per raid"),
    ("ai/Unstable/game-side/script/standard/manager/air/update.as", r"InList\(gInterceptRoster",
     "an intercept flies its launch roster only"),
    ("ai/Unstable/game-side/script/standard/manager/air/update.as", r"PublishTeamValue\(\"strike_f\"",
     "the strike publishes its launch frame"),
    ("ai/Unstable/game-side/script/standard/manager/air/wave.as", r"distance2D\(gatherAt\) > gatherR",
     "a wave launches what stands where it gathers"),
    ("ai/Unstable/game-side/script/standard/manager/air/teamair.as", r"distance2D\(TairRally\(\)\)",
     "team air launches gunships at the rally only"),
    ("ai/Unstable/game-side/script/standard/manager/air/nnair.as", r"NaWingLaunch\(", "a gunship wing out is not joined"),
    ("ai/Unstable/game-side/script/standard/manager/air/cover.as", r"GetOwnUnitsOfDef\(fd, orig, nearR\)",
     "cover takes fighters where its plane starts"),
    ("ai/Unstable/game-side/script/standard/manager/military/nnsiege.as", r"if \(!gSgReady \|\| !GthOn\(\)\)",
     "a siege that marched pulls no one"),
    ("ai/Unstable/game-side/script/standard/manager/military/joinfight.as", r"RfLikelyLate\(travelS\)",
     "a march that arrives after the fight stays"),
    ("ai/Unstable/game-side/script/standard/manager/military/flankguard.as", r"keep\.IsJoinCommitted\(\)",
     "a formed flank group recalls no one"),
    ("ai/Unstable/game-side/script/standard/manager/brain/market/aathreat.as", r"JwLaunched\(",
     "an AA guard does not follow a launched squad"),
    ("ai/Unstable/game-side/script/standard/manager/military/hooks.as", r"GthOn\(\) \? MassPoolTask",
     "late scouts wait in the pool"),
]


def check_sentinels(repo: Path = REPO) -> list[str]:
    errs = []
    for rel, pat, what in _SENTINELS:
        p = repo / rel
        if p.is_file() and not re.search(pat, p.read_text(encoding="utf8", errors="replace")):
            errs.append(f"{rel}: lost its join window ({what})")
    return errs


def check(repo: Path = REPO) -> list[str]:
    return check_cpp(repo / "cpp" / "src" / "circuit") + \
        check_script(repo / "ai" / "Unstable" / "game-side" / "script" / "standard" / "manager") + \
        check_sentinels(repo)


def main() -> int:
    errs = check()
    for e in errs:
        print(e)
    print(f"joinwin: {len(errs)} finding(s)")
    return 1 if errs else 0


if __name__ == "__main__":
    raise SystemExit(main())
