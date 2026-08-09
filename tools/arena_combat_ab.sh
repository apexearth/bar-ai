#!/usr/bin/env bash
# Which of our combat changes costs us the close-range fight?
#
# Run this with BAR CLOSED -- it deploys, which cannot replace a loaded
# SkirmishAI.dll. Takes about ten minutes.
#
# Baseline, measured 2026-08-09 over 126 rounds on two maps: apex loses a
# mirrored equal-army 2v2 Pawn fight by 0.46 units per round, ~25% of the force,
# while being exactly even with a 475-range Rocketeer. Each arm below switches
# off one suspect via a rules param; an arm that moves the edge toward zero is
# the culprit. Arms are independent, so run them all and read the column.
set -eu
cd "$(dirname "$0")/.."

python tools/deploy_ai.py deploy apex
python tools/deploy_ai.py gadgets

# 2v2 Pawn is the most sensitive configuration found: largest deficit per unit
# and ~60 rounds per 25-second match.
run() { bash tools/arena_ab.sh "$@" --modoption dev_arena_count=2; }

run ab-baseline
run ab-noorbit    --modoption apex_orbit_rate=0
run ab-nospacing  --modoption apex_squad_spacing=0
run ab-close70    --modoption apex_range_mod=0.70
run ab-close50    --modoption apex_range_mod=0.50

echo
echo "Read SUBJECT EDGE per arm. Baseline should reproduce about -0.46."
echo "Confirm any winner with a long-range unit before shipping it:"
echo "  ARENA_DEF=armrock ARENA_SEP=380 bash tools/arena_ab.sh check <winning modoption>"
