#!/usr/bin/env bash
# Paired arms on one checkpoint: every seed played by every arm, at most $JOBS engines at once (the recorder holds one).
#     bash tools/armynet/paired_arms.sh <model.pt> <first seed> <n seeds> <out log> "unit:" "force:--forces" ...
# Each arm is name:flags (an arm's own --model wins: watch.py reads the first); the log gets "seed <s> <arm> <match dir>" lines for paired_summary.py.
set -u
cd "$(dirname "$0")/../.."
model=$1; first=$2; n=$3; log=$4; shift 4
JOBS=${JOBS:-3}
run() {
    local s=$1 name=$2 flags=$3 out="runtime/armynet/pa-$2-$1.log"
    python -u tools/armynet/watch.py $flags --model "$model" --rounds --speed 4 --seed "$s" --minutes 20 --headless \
        > "$out" 2>&1
    echo "seed $s $name $(grep -o 'matches.armynet-watch-[0-9-]*' "$out" | head -1)" >> "$log"
}
for ((s = first; s < first + n; s++)); do
    for arm in "$@"; do
        while (( $(jobs -rp | wc -l) >= JOBS )); do wait -n; done
        run "$s" "${arm%%:*}" "${arm#*:}" &
        sleep 5
    done
done
wait
