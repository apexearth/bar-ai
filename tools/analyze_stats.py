"""Read a tournament's telemetry over time: where and when a match went wrong.

    python tools/analyze_stats.py coh-deep            # summary + timeline
    python tools/analyze_stats.py coh-deep --chart    # also writes timeline.svg
    python tools/analyze_stats.py 20260806-192247-...  # a single match under matches/

A win rate is one bit per match. These counters are continuous, paired (both
sides observed in the same game) and sampled every 2 game-minutes, so a handful
of matches can show not just *whether* a change helped but *when* the game
turned -- which is the part you can act on.

Metric choices, deliberately not simplified:
  real-value K/D  metal value of units killed / lost, counting only units at or
                  above the spam threshold. Raw unit counts would score ten dead
                  Fleas like a dead Titan and reward the wrong behaviour.
  eco             metalProduced, plus excess as a waste fraction.
  damage received is recorded but weighted lightly: a high figure can mean
                  tanking behind con-turret repair, which is good play.
"""

from __future__ import annotations

import argparse
import json
import math
import pathlib
import statistics

from bar_env import REPO


def side(sample_rows: list[dict], ally: int) -> dict:
    """Sum one ally team's counters (handles 4v4 as well as 1v1)."""
    acc: dict[str, float] = {}
    for t in sample_rows:
        if int(t.get("ally", -1)) != ally:
            continue
        for k, v in t.items():
            if isinstance(v, float) and k not in ("team", "ally", "spamCost", "frame"):
                acc[k] = acc.get(k, 0.0) + v
    return acc


def ally_of(match: dict, spec: str) -> int:
    """Which ally team a given variant occupied in THIS match.

    The tournament swaps sides every other game, so ally index 0 is not a stable
    identity -- keying the timeline on it silently interleaves the two variants.
    """
    for i, t in enumerate(match.get("teams", [])):
        if t.get("spec") == spec:
            return i
    return 0


def timeline(stats: list[dict], ally_a: int, ally_b: int) -> list[tuple[float, dict, dict]]:
    """Group samples by frame -> (game minutes, variantA, variantB)."""
    by_frame: dict[float, list[dict]] = {}
    for row in stats:
        by_frame.setdefault(row.get("frame", 0.0), []).append(row)
    return [(f / (30 * 60), side(by_frame[f], ally_a), side(by_frame[f], ally_b))
            for f in sorted(by_frame)]


def kd(s: dict) -> float:
    return s.get("mKillReal", 0.0) / max(s.get("mLostReal", 0.0), 1.0)


def write_chart(path: pathlib.Path, series, a_name: str, b_name: str) -> None:
    """Two stacked panels: metal produced, and real-value K/D, over game time."""
    W, H, PAD = 900, 520, 60
    panel = (H - 3 * PAD) / 2
    xs = [s[0] for s in series]
    xmax = max(xs) or 1

    def sx(m: float) -> float:
        return PAD + (m / xmax) * (W - 2 * PAD)

    def poly(vals, y0, vmax) -> str:
        pts = []
        for m, v in zip(xs, vals):
            y = y0 + panel - (v / vmax if vmax else 0) * panel
            pts.append(f"{sx(m):.1f},{y:.1f}")
        return " ".join(pts)

    metal_max = max(max(s[1] for s in series), max(s[2] for s in series)) or 1
    kd_max = max(max(s[3] for s in series), max(s[4] for s in series), 1.0)
    A, B = "#3b82f6", "#ef4444"

    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
        f'<rect width="{W}" height="{H}" fill="#0b0f14"/>',
        f'<text x="{PAD}" y="26" fill="#3b82f6" font-family="monospace" font-size="14">A = {a_name}</text>',
        f'<text x="{PAD+380}" y="26" fill="#ef4444" font-family="monospace" font-size="14">B = {b_name}</text>',
    ]
    for idx, (title, ia, ib, vmax) in enumerate(
            [("metal produced (cumulative)", 1, 2, metal_max),
             ("real-value K/D  (dashed = even trading)", 3, 4, kd_max)]):
        y0 = PAD + idx * (panel + PAD)
        parts += [
            f'<text x="{PAD}" y="{y0-8}" fill="#9ca3af" font-family="monospace" font-size="12">{title}</text>',
            f'<rect x="{PAD}" y="{y0}" width="{W-2*PAD}" height="{panel}" fill="none" stroke="#1f2937"/>',
        ]
        if idx == 1:
            y1 = y0 + panel - (1.0 / vmax) * panel
            parts.append(f'<line x1="{PAD}" y1="{y1:.1f}" x2="{W-PAD}" y2="{y1:.1f}" '
                         f'stroke="#374151" stroke-dasharray="4 4"/>')
        parts += [
            f'<polyline points="{poly([s[ia] for s in series], y0, vmax)}" fill="none" stroke="{A}" stroke-width="2"/>',
            f'<polyline points="{poly([s[ib] for s in series], y0, vmax)}" fill="none" stroke="{B}" stroke-width="2"/>',
            f'<text x="{W-PAD}" y="{y0+12}" fill="#6b7280" font-family="monospace" '
            f'font-size="11" text-anchor="end">max {vmax:,.1f}</text>',
        ]
    for m in xs[::max(1, len(xs) // 8)]:
        parts.append(f'<text x="{sx(m):.0f}" y="{H-18}" fill="#6b7280" font-family="monospace" '
                     f'font-size="11" text-anchor="middle">{m:.0f}m</text>')
    parts.append("</svg>")
    path.write_text("\n".join(parts), encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("run", nargs="?", default="")
    ap.add_argument("--chart", action="store_true")
    args = ap.parse_args()

    # A tournament's ledger.jsonl and a single match's result.json share the
    # exact same row shape (engine/map/game/seed/teams/result/stats) -- a
    # ledger is literally one result.json per line. So a single match under
    # matches/ works here too, as a one-row "tournament": this is the tool
    # that got hand-reimplemented ad hoc, in-conversation, more than once in
    # one session because it only ever looked under tournaments/.
    runs = sorted(p for p in (REPO / "tournaments").glob(f"*{args.run}*")
                  if (p / "ledger.jsonl").exists())
    single_match = None
    if not runs:
        matches = sorted(p for p in (REPO / "matches").glob(f"*{args.run}*")
                         if (p / "result.json").exists())
        if matches:
            single_match = matches[-1]
    if not runs and single_match is None:
        raise SystemExit("no matching run (checked tournaments/ and matches/)")

    if single_match is not None:
        run = single_match
        rows = [json.loads((run / "result.json").read_text("utf-8"))]
        cfg = {}
    else:
        run = runs[-1]
        rows = [json.loads(l) for l in (run / "ledger.jsonl").read_text("utf-8").splitlines() if l.strip()]
        cfg = json.loads((run / "config.json").read_text("utf-8")) if (run / "config.json").exists() else {}
    rows = [r for r in rows if r.get("stats")]
    if not rows:
        raise SystemExit(f"{run.name}: no telemetry -- is the dev_stats gadget installed?")

    specs = sorted({t["spec"] for r in rows for t in r["teams"]})
    ordered = [s.split(":")[1] for s in cfg.get("ais", [])] if cfg.get("ais") else []
    a_name = next((s for s in specs if ordered and ordered[0] in s), specs[0])
    b_name = next((s for s in specs if s != a_name), specs[-1])
    print(f"run {run.name}   {len(rows)} matches with telemetry")
    print(f"  A = {a_name}")
    print(f"  B = {b_name}\n")

    print(f"  {'#':>2} {'win':<4} {'len':>5}  {'A K/D':>6} {'B K/D':>6}  "
          f"{'A metal':>8} {'B metal':>8}  {'A waste':>7}")
    logratios = []
    for i, r in enumerate(rows, 1):
        tl = timeline(r["stats"], ally_of(r, a_name), ally_of(r, b_name))
        # The very last sample is often a shutdown dump after a team is gone, so
        # it reports only the survivor. Take the last frame where both sides
        # still reported.
        tl = [x for x in tl if x[1] and x[2]]
        if not tl:
            continue
        _, a, b = tl[-1]
        w = (r["result"].get("winner_specs") or ["-"])[0]
        who = "A" if a_name in w else ("B" if b_name in w else "-")
        waste = a.get("metalExcess", 0) / max(a.get("metalProduced", 1), 1)
        print(f"  {i:>2} {who:<4} {r['result']['game_minutes']:>5.1f}  "
              f"{kd(a):>6.2f} {kd(b):>6.2f}  {a.get('metalProduced',0):>8.0f} "
              f"{b.get('metalProduced',0):>8.0f}  {100*waste:>6.1f}%")
        logratios.append(math.log((kd(a) + 0.05) / (kd(b) + 0.05)))

    if len(logratios) > 1:
        mean = statistics.fmean(logratios)
        se = statistics.stdev(logratios) / math.sqrt(len(logratios))
        print(f"\n  paired log-ratio of real K/D: mean {mean:+.3f}  "
              f"t={mean/se if se else 0:+.2f}   ({'A' if mean > 0 else 'B'} trades better)")

    buckets: dict[int, list[tuple[dict, dict]]] = {}
    for r in rows:
        for mins, a, b in timeline(r["stats"], ally_of(r, a_name), ally_of(r, b_name)):
            if not a or not b:
                continue
            buckets.setdefault(int(mins // 2) * 2, []).append((a, b))

    print(f"\n  timeline (mean across matches still alive at each point)")
    print(f"  {'min':>4}  {'A metal':>8} {'B metal':>8}   {'A K/D':>6} {'B K/D':>6}   "
          f"{'A lostReal':>10} {'B lostReal':>10}")
    series = []
    for m in sorted(buckets):
        pairs = buckets[m]
        if len(pairs) < max(2, len(rows) // 3):
            continue
        am = statistics.fmean(a.get("metalProduced", 0) for a, _ in pairs)
        bm = statistics.fmean(b.get("metalProduced", 0) for _, b in pairs)
        ak = statistics.fmean(kd(a) for a, _ in pairs)
        bk = statistics.fmean(kd(b) for _, b in pairs)
        al = statistics.fmean(a.get("mLostReal", 0) for a, _ in pairs)
        bl = statistics.fmean(b.get("mLostReal", 0) for _, b in pairs)
        series.append((m, am, bm, ak, bk, al, bl))
        print(f"  {m:>4}  {am:>8.0f} {bm:>8.0f}   {ak:>6.2f} {bk:>6.2f}   {al:>10.0f} {bl:>10.0f}")

    if args.chart and series:
        write_chart(run / "timeline.svg", series, a_name, b_name)
        print(f"\n  chart: {run / 'timeline.svg'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
