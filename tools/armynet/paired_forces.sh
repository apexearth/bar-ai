#!/usr/bin/env bash
# Paired test of force orders (his 11-20: order groups the way players click them; long range behind the line):
# each seed played per-unit, with --forces, and with --forces --layer, same checkpoint, three engines at a time.
#     bash tools/armynet/paired_forces.sh <model.pt> <first seed> <n seeds> <out log>
set -u
cd "$(dirname "$0")/../.."
model=$1; first=$2; n=$3; log=$4
for ((s = first; s < first + n; s++)); do
    python -u tools/armynet/watch.py --model "$model" --rounds --speed 4 --seed $s --minutes 20 --headless \
        > "runtime/armynet/pf-unit-$s.log" 2>&1 &
    sleep 3
    python -u tools/armynet/watch.py --model "$model" --rounds --forces --speed 4 --seed $s --minutes 20 --headless \
        > "runtime/armynet/pf-force-$s.log" 2>&1 &
    sleep 3
    python -u tools/armynet/watch.py --model "$model" --rounds --forces --layer --speed 4 --seed $s --minutes 20 \
        --headless > "runtime/armynet/pf-layer-$s.log" 2>&1 &
    wait
    for arm in unit force layer; do
        echo "seed $s $arm $(grep -o 'matches.armynet-watch-[0-9-]*' runtime/armynet/pf-$arm-$s.log | head -1)" >> "$log"
    done
done
