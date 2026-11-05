"""Does the price's risk match what was lost? (todo/learn-from-each-decision.md, step 1)

    python tools/ledger_calib.py runtime/ledger/<run>.jsonl

The decision's `risk` is ExpectedLossAt: metal x hazard per second x the share of the threat uncovered -- a loss RATE.
Over the seconds a job was exposed (decision -> finished, or -> the frame died, or -> its builder was killed), the
market expects rate/metal x seconds failures; the ledger counts the failures that happened. Observed over expected,
per job type and band of the rate, then split by context the price may not see. Jobs dropped with nobody killed have
no known exposure and are left out; so are jobs founded by an assist or reclaim decision.
"""
import json
import re
import sys
from collections import defaultdict

CLASSES = [("mex", r"mex$"), ("moho", r"moho$"), ("energy", r"(solar|advsol|win|fus|afus|geo|tide)$"),
           ("converter", r"(makr|mmkr)$"), ("nano", r"nanotc"), ("plant", r"(lab|vp|ap|hp|sy|gant|shltx|alab|avp|aap)$"),
           ("tower", r"(llt|hllt|hlt|lht|mg|guard|pun|toast|doom|vipe|maw|bastion|cluster|lupara|tl|dl)$"),
           ("aa", r"(rl|madsam|flak|erad|cir)$"), ("radar", r"(rad|eyes|arad)$")]
BUILD_KINDS = {"mex", "mexup", "energy", "protect", "nano", "plant", "convert", "sense", "airdef", "tech", "geo", "super"}
BANDS = [1e-4, 3e-4, 1e-3, 3e-3, 1e-2]


def cls(d):
    for k, rx in CLASSES:
        if re.search(rx, d[3:] if len(d) > 3 else d):
            return k
    return None


def band(q):
    return sum(q > b for b in BANDS)


def band_name(i):
    if i == 0:
        return "<=%g/s" % BANDS[0]
    if i == len(BANDS):
        return ">%g/s" % BANDS[-1]
    return "%g-%g" % (BANDS[i - 1], BANDS[i])


def exposure(r, d):
    """seconds the job was at risk, and whether it failed"""
    if r.get("builderDied") and d.get("diedAfterS") is not None:
        return float(d["diedAfterS"]), True
    if r.get("frameLost"):
        return (r["frame"] - d["frame"]) / 30.0, True
    if r.get("neverPlaced"):
        # a dropped job is at risk for as long as it was open; one the game's end cut off is left out. Leaving out
        # every dropped job but the ones whose builder died selected the label on its outcome (11-04 review).
        if r.get("censored") or r.get("droppedAfterS") is None:
            return None, False
        return float(r["droppedAfterS"]), False
    return (r["finished"] - d["frame"]) / 30.0, False


def main(path):
    acc = defaultdict(lambda: [0, 0.0, 0, 0.0])        # jobs, expected failures, failures, exposed seconds
    ctx = defaultdict(lambda: [0, 0.0, 0])             # (class, context) -> jobs, expected, failures
    with open(path, encoding="utf-8") as fh:
        names = json.loads(fh.readline())["schema"]
        si = {n: i for i, n in enumerate(names["state"])}
        for ln in fh:
            r = json.loads(ln)
            d = r.get("decision") or {}
            o = d.get("opt")
            if not o or "state" not in d or d.get("kind") not in BUILD_KINDS:
                continue
            k = cls(r["def"])
            cost = float(r.get("cost") or 0.0)
            if k is None or cost < 1.0:
                continue
            secs, failed = exposure(r, d)
            if secs is None or secs < 0:
                continue
            rate = max(0.0, float(o["risk"])) / max(1.0, float(o["m"]))
            expect = min(1.0, rate * secs)
            a = acc[(k, band(rate))]
            a[0] += 1
            a[1] += expect
            a[2] += failed
            a[3] += secs
            s = d["state"]
            for c in (("army behind" if s[si["army"]] < s[si["foeArmy"]] else "army ahead"),
                      ("losing" if s[si["losing"]] > 0.5 else "not losing"),
                      ("forward" if float(o["fwd"]) > 0.2 else "home")):
                cc = ctx[(k, c)]
                cc[0] += 1
                cc[1] += expect
                cc[2] += failed
    print("job        risk rate band    jobs  mean exposed s  expected fail  observed fail  observed/expected")
    for k, _ in CLASSES:
        for b in range(len(BANDS) + 1):
            n, e, f, s = acc[(k, b)]
            if n < 100:
                continue
            print("%-10s %-15s %7d  %14.0f  %12.1f%%  %12.1f%%  %10.1fx" % (
                k, band_name(b), n, s / n, 100 * e / n, 100 * f / n, (f / n) / max(1e-6, e / n)))
    print("\nobserved/expected by context, all bands (1.0x = the price saw it)")
    for k, _ in CLASSES:
        parts = []
        for c in ("army ahead", "army behind", "not losing", "losing", "home", "forward"):
            n, e, f = ctx[(k, c)]
            if n >= 100:
                parts.append("%s %.0f%%/%.0f%% %.1fx" % (c, 100 * f / n, 100 * e / n, f / max(1e-6, e)))
        print("%-10s %s" % (k, " | ".join(parts)))


if __name__ == "__main__":
    main(sys.argv[1])
