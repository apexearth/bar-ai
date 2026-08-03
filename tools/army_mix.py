"""Side-by-side unit composition: what we build against what the enemy builds.

Reads the `top=` field of [BARAI_STATS], which lists each player's largest metal
sinks at each 2-minute sample. That is a SAMPLE of the biggest spends, not a
complete inventory -- a unit that never enters a player's top few never appears
here at all, so absence in this table is not proof a unit was never built. Cheap
units (an air constructor is 115 metal) are systematically invisible.

Metal is summed as "peak seen": for each player and unit the largest value ever
reported, since the field is cumulative spend per unit type.

    python tools/army_mix.py <match-or-tournament-dir> [more dirs...]
"""
import collections
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import bar_env  # noqa: E402
import unitdef  # noqa: E402  -- for display names


def _logs(root: pathlib.Path):
    if (root / "infolog.txt").exists():
        yield root / "infolog.txt"
        return
    yield from sorted(root.rglob("infolog.txt"))


def collect(root: pathlib.Path):
    """-> {side: {unit: metal}}, {side: set(team)}"""
    peak = collections.defaultdict(lambda: collections.defaultdict(float))
    teams = collections.defaultdict(set)
    for log in _logs(root):
        seen = collections.defaultdict(float)  # (side, team, unit) -> metal
        txt = log.read_text("utf-8", errors="replace")
        for m in re.finditer(r"BARAI_STATS\] (.*)", txt):
            d = {}
            for tok in m.group(1).split():
                k, _, v = tok.partition("=")
                d[k] = v
            if "ally" not in d or "top" not in d:
                continue
            side = "apex" if d["ally"] == "0" else "stable"
            teams[side].add((log.parent.name, d.get("team")))
            for entry in d["top"].split(","):
                name, _, cost = entry.partition(":")
                if not cost:
                    continue
                key = (side, d.get("team"), log.parent.name, name)
                seen[key] = max(seen[key], float(cost))
        for (side, _team, _run, name), metal in seen.items():
            peak[side][name] += metal
    return peak, teams


def main() -> int:
    roots = [pathlib.Path(a) for a in sys.argv[1:]]
    if not roots:
        print(__doc__)
        return 2

    peak = collections.defaultdict(lambda: collections.defaultdict(float))
    games = 0
    for root in roots:
        p, _t = collect(root)
        games += len(list(_logs(root)))
        for side, units in p.items():
            for name, metal in units.items():
                peak[side][name] += metal

    if not peak:
        print("no [BARAI_STATS] top= data found")
        return 1

    names = set(peak["apex"]) | set(peak["stable"])
    tot = {s: sum(peak[s].values()) or 1.0 for s in ("apex", "stable")}

    game_tree = unitdef.trees(bar_env.load())[0]
    disp_names = game_tree.lang().get("names", {})

    rows = []
    for u in names:
        a, s = peak["apex"].get(u, 0.0), peak["stable"].get(u, 0.0)
        rows.append((a + s, u, disp_names.get(u, ""), a, s))
    rows.sort(reverse=True)

    print(f"{games} game log(s).  Metal by unit, and each side's share of its own total.")
    print("Source is the top-sinks sample: cheap units are systematically absent.\n")
    print(f"{'unit':<16}{'name':<22}{'apex':>10}{'%':>7}{'stable':>10}{'%':>7}  ratio")
    print("-" * 82)
    for _k, u, disp, a, s in rows[:34]:
        ra = a / tot["apex"] * 100
        rs = s / tot["stable"] * 100
        ratio = (a / s) if s else float("inf")
        flag = ""
        if s > 0 and a == 0:
            flag = "  <-- WE BUILD NONE"
        elif ratio != float("inf") and ratio < 0.34 and rs > 2.0:
            flag = "  <-- far behind"
        rtxt = "   inf" if ratio == float("inf") else f"{ratio:>6.2f}"
        print(f"{u:<16}{disp[:21]:<22}{a:>10.0f}{ra:>6.1f}%{s:>10.0f}{rs:>6.1f}%{rtxt}{flag}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
