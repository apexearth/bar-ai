#!/usr/bin/env bash
# Run one arm of a combat A/B over N 1v1 games and score the army trade.
#
#   tools/fight1v1_ab.sh <tag> [--modoption apex_x=y ...]
#
# 1v1 on a small map is the configuration where the economy is at parity, so the
# army trade is the thing that differs. Seeds are fixed and shared across arms;
# the DLL is multithreaded so a seed does not reproduce exactly, which is why
# this runs a batch rather than a single game.
#
# EVERY match shares one engine write dir by default, and run_match copies
# infolog.txt out of it at the end -- so two matches running at once land each
# other's logs in each other's output folders. That silently crossed the arms of
# a mirrored A/B here: the control logged a rule only the treatment enabled, and
# the treatment published no tunables at all. Each match gets its own below, so a
# watched game or a second batch running alongside can no longer corrupt a run.
#
# Environment overrides: FIGHT_SEEDS FIGHT_MAP FIGHT_MINUTES FIGHT_SIDES
#                        FIGHT_WRITE_ROOT
set -u
cd "$(dirname "$0")/.."

TAG="$1"; shift
SEEDS="${FIGHT_SEEDS:-1 2 3 4 5 6 7 8}"
MAP="${FIGHT_MAP:-Altair_Crossing_V4.1}"
MINUTES="${FIGHT_MINUTES:-20}"
# run_match assigns factions by POSITION (SIDES[i % len]), not by seed, so
# without this every game in every batch was apex-Armada vs stock-Cortex and no
# amount of reseeding varied it. apexearth: "do you keep playing the same seed?
# we are always being ARM bots vs cortex vehicles". Mirror by default; set
# FIGHT_SIDES to check a result carries to another faction.
SIDES="${FIGHT_SIDES:-Armada,Armada}"
WD_ROOT="${FIGHT_WRITE_ROOT:-$PWD/matches/.wd}"
# The deployed variant moved to Apex:Unstable:standard; the old
# Apex:Unstable:standard spec resolves to NO installed AI and scores zero
# silently (the unknown-skirmish-AI trap).
SPEC_A="${FIGHT_SPEC_A:-Apex:Unstable:standard}"

for s in $SEEDS; do
    python -u tools/run_match.py \
        --a "$SPEC_A" --b BARb:stable:hard \
        --map "$MAP" --per-side 1 --minutes "$MINUTES" --seed "$s" \
        --sides "$SIDES" "$@" \
        --write-dir "$WD_ROOT/$TAG-$s" \
        --out "matches/f1v1-$TAG-$s" >/dev/null 2>&1
done

echo "=== $TAG ${*:-baseline} ==="
python tools/fight1v1.py matches/f1v1-"$TAG"-* | tail -8
grep -l "winners  \['Apex" matches/f1v1-"$TAG"-*/result.json 2>/dev/null | wc -l | \
    xargs -I{} echo "  wins (by result.json): {}"
