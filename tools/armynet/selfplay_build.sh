#!/bin/bash
# Self-play games -> training files: each kept replay of a head-to-head batch is played back by replay_orders.py (the
# orders, sight and outcomes of both sides) and turned into an .npz by replay_dataset.py with BARAI_ALL_TEAMS=1, so
# both of our AI sides learn. The files go under runtime/armynet/own-games/<set>/, where data.py treats them as own
# games (every side, with the usual ratings). One playback at a time; skips games already built.
#   bash tools/armynet/selfplay_build.sh <set> <match dir>...
cd "$(dirname "$0")/../.."
SET=$1; shift
ROOT=runtime/armynet/own-games/$SET
mkdir -p "$ROOT"
for m in "$@"; do
    name=$(basename "$m")
    demo=$(ls "$m"/*.sdfz 2>/dev/null | head -1)
    [ -z "$demo" ] && { echo "$name: no replay"; continue; }
    [ -f "$ROOT/$name/$name.npz" ] && { echo "$name: built"; continue; }
    while tasklist | grep -qi "^spring.exe"; do sleep 60; done
    rec=matches/rec-$name
    python tools/replay_orders.py one "$demo" "$rec" > "$rec.log" 2>&1
    if [ ! -f "$rec/orders.txt.gz" ]; then echo "$name: no orders ($rec.log)"; continue; fi
    mkdir -p "$ROOT/$name"
    BARAI_ALL_TEAMS=1 python tools/replay_dataset.py "$rec/orders.txt.gz" --out "$ROOT/$name" > "$ROOT/$name/build.log" 2>&1
    n=$(ls "$ROOT/$name"/*.npz 2>/dev/null | wc -l)
    [ "$n" -gt 0 ] && mv "$ROOT/$name"/*.npz "$ROOT/$name/$name.npz" 2>/dev/null
    echo "$name: npz=$n"
done
echo done
