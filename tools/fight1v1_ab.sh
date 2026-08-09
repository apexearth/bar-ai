#!/usr/bin/env bash
# Run one arm of a combat A/B over N 1v1 games and score the army trade.
#
#   tools/fight1v1_ab.sh <tag> [--modoption apex_x=y ...]
#
# 1v1 on a small map is the configuration where the economy is at parity, so the
# army trade is the thing that differs. Seeds are fixed and shared across arms;
# the DLL is multithreaded so a seed does not reproduce exactly, which is why
# this runs a batch rather than a single game.
set -u
cd "$(dirname "$0")/.."

TAG="$1"; shift
SEEDS="${FIGHT_SEEDS:-1 2 3 4 5 6 7 8}"
MAP="${FIGHT_MAP:-Altair_Crossing_V4.1}"
MINUTES="${FIGHT_MINUTES:-20}"

for s in $SEEDS; do
    python -u tools/run_match.py \
        --a Apex:apex:hard_aggressive --b BARb:stable:hard \
        --map "$MAP" --per-side 1 --minutes "$MINUTES" --seed "$s" "$@" \
        --out "matches/f1v1-$TAG-$s" >/dev/null 2>&1
done

echo "=== $TAG ${*:-baseline} ==="
python tools/fight1v1.py matches/f1v1-"$TAG"-* | tail -8
grep -l "winners  \['Apex" matches/f1v1-"$TAG"-*/result.json 2>/dev/null | wc -l | \
    xargs -I{} echo "  wins (by result.json): {}"
