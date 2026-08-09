#!/usr/bin/env bash
# Run one arena configuration in both orientations and print the
# slot-bias-cancelled edge for the subject AI.
#
# Self-play controls showed a persistent ~1 unit advantage to ally 1 that
# survives swapping spawn positions, so it is tied to the team slot. Running
# both orientations and averaging removes it without needing to explain it.
#
#   tools/arena_ab.sh <tag> [extra run_match args...]
#
# Environment overrides: ARENA_MAP ARENA_MINUTES ARENA_SEED ARENA_DEF
#                        ARENA_SEP ARENA_ROUND ARENA_SUBJECT ARENA_OPPONENT
#
# Spawn separation must be inside the unit's weapon range or the sides never
# engage and every round is a draw.
set -u
cd "$(dirname "$0")/.."

TAG="$1"; shift

SUBJECT="${ARENA_SUBJECT:-Apex:apex:hard_aggressive}"
OPPONENT="${ARENA_OPPONENT:-BARb:stable:hard}"

common=(--map "${ARENA_MAP:-Altair_Crossing_V4.1}"
        --per-side 1 --sides Armada,Armada
        --minutes "${ARENA_MINUTES:-20}" --seed "${ARENA_SEED:-7}"
        --modoption dev_arena=1
        --modoption "dev_arena_def=${ARENA_DEF:-armpw}"
        --modoption "dev_arena_sep=${ARENA_SEP:-240}"
        --modoption "dev_arena_round=${ARENA_ROUND:-1200}")

python -u tools/run_match.py --a "$SUBJECT" --b "$OPPONENT" "${common[@]}" "$@" \
    --out "matches/arena-$TAG-fwd" >/dev/null 2>&1
python -u tools/run_match.py --a "$OPPONENT" --b "$SUBJECT" "${common[@]}" "$@" \
    --out "matches/arena-$TAG-rev" >/dev/null 2>&1

echo "--- $TAG ${*:-} (def=${ARENA_DEF:-armpw} sep=${ARENA_SEP:-240} map=${ARENA_MAP:-Altair_Crossing_V4.1}) ---"
python tools/arena.py --pair "matches/arena-$TAG-fwd" "matches/arena-$TAG-rev"
