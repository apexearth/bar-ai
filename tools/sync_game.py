"""Make the test game tree (data/games/BAR.sdd) the exact game his multiplayer runs.

His 2026-10-12: tests must run the same game version as his multiplayer. They ran a 2025-11 snapshot of
BAR.sdd while his lobby games ran the rapid package byar:test (test-31578-8247b61): the Phoenix differed
(noautofire, flight model) and so could every unit.

    python tools/sync_game.py                 # byar:test, the tag his lobby resolves
    python tools/sync_game.py --tag byar:stable
    python tools/sync_game.py --dry-run

Steps: read the tag's package md5 from rapid's versions.gz; unpack the package's .sdp file list from the
pool (pool/<md5[:2]>/<md5[2:]>.gz, every file checked against its md5) into BAR.sdd.new; keep modinfo's
version as '$VERSION' (the harness's dev name -- the same name as the rapid archive would be two archives
with one name); carry luarules/configs/Apex* over from the old tree; move the old tree to
data/games-old/BAR-<date>.sdd; rename. Afterwards run, in order:
    python tools/deploy_ai.py gadgets
    python tools/deploy_ai.py patches
    python tools/deploy_ai.py deploy Unstable      (in each lane that has a deployed variant)
"""
import argparse, gzip, hashlib, os, re, shutil, struct, sys, time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bar_env


def _writable_retry(func, path, _exc):
    os.chmod(path, 0o666)
    func(path)


def tag_md5(data, tag):
    for vf in (data / "rapid").glob("*/byar/versions.gz"):
        for ln in gzip.open(vf, "rt", encoding="utf-8", errors="replace"):
            parts = ln.strip().split(",")
            if parts and parts[0] == tag:
                return parts[1], parts[3]
    raise SystemExit("tag %s not found in rapid versions.gz" % tag)


def sdp_files(sdp):
    raw = gzip.open(sdp, "rb").read()
    i, out = 0, []
    while i < len(raw):
        n = raw[i]
        name = raw[i + 1:i + 1 + n].decode("utf-8")
        i += 1 + n
        md5 = raw[i:i + 16].hex()
        i += 16 + 4                       # md5, crc32
        size = struct.unpack(">I", raw[i:i + 4])[0]
        i += 4
        out.append((name, md5, size))
    return out


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", default="byar:test")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args(argv)
    env = bar_env.load()
    data = Path(env.data)
    md5, label = tag_md5(data, a.tag)
    sdp = data / "packages" / (md5 + ".sdp")
    if not sdp.exists():
        raise SystemExit("package %s (%s) is not downloaded: open the lobby once on that version" % (label, md5))
    files = sdp_files(sdp)
    print("%s = %s: %d files, %.0f MB" % (a.tag, label, len(files), sum(f[2] for f in files) / 1e6))
    old = Path(env.game_sdd)
    new = old.with_name(old.name + ".new")
    if a.dry_run:
        return 0
    if new.exists():
        shutil.rmtree(new)
    bad = 0
    for name, fmd5, size in files:
        src = data / "pool" / fmd5[:2] / (fmd5[2:] + ".gz")
        body = gzip.open(src, "rb").read()
        if hashlib.md5(body).hexdigest() != fmd5:
            bad += 1
            print("md5 mismatch: %s" % name)
            continue
        dst = new / name
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(body)
    if bad:
        raise SystemExit("%d files failed their md5; old tree left in place" % bad)
    mi = new / "modinfo.lua"
    txt = mi.read_text(encoding="utf-8")
    txt2 = re.sub(r"version\s*=\s*['\"][^'\"]*['\"]", "version = '$VERSION'", txt, count=1)
    mi.write_text(txt2, encoding="utf-8")
    print("modinfo version: %s -> $VERSION" % re.search(r"version\s*=\s*['\"]([^'\"]*)", txt).group(1))
    kept = 0
    for d in (old / "luarules" / "configs").glob("Apex*"):
        shutil.copytree(d, new / "luarules" / "configs" / d.name, dirs_exist_ok=True)
        kept += 1
    (new / "SYNCED_FROM.txt").write_text("%s %s (%s) %s\n" % (a.tag, label, md5, time.strftime("%Y-%m-%d %H:%M")),
                                          encoding="utf-8")
    keep = data / "games-old" / ("BAR-%s.sdd" % time.strftime("%Y%m%d-%H%M"))
    keep.parent.mkdir(exist_ok=True)
    try:
        old.rename(keep)
    except OSError:
        # a file held open blocks the rename: copy, then delete the old tree -- its .git packs are
        # read-only, which made the first run's rmtree stop half way (10-12)
        shutil.copytree(old, keep, dirs_exist_ok=True)
        shutil.rmtree(old, onerror=_writable_retry)
    new.rename(old)
    print("Apex configs carried: %d; old tree -> %s" % (kept, keep))
    print("now: deploy_ai.py gadgets; deploy_ai.py patches; deploy_ai.py deploy <variant> in each lane")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
