#!/bin/bash
# The army model against our own rules army (todo/armynet-objectives.md: candidates are judged against the rules army,
# never another model). Red Comet 1v1, both +50, 40 min, speed 4, the same faction on both sides (alternating every two
# seeds); the model side alternates t0/t1 by seed parity; replays kept, then built into runtime/armynet/own-games/<set>
# for tools/armynet/objectives_army.py. One game at a time per lane (the bridge folders live in the lane's AI folder).
#   LANE=armynet bash tools/armynet/model_vs_rules.sh <set> <seed_from> <seed_to> "<model.pt>" "<serve flags>"
cd "$(dirname "$0")/../.."
LANE=${LANE:-armynet}
export BARAI_LANE=$LANE
SET=$1; S0=$2; S1=$3; MODEL=$4; FLAGS=$5
LOG=runtime/armynet/mvr-$SET.log
AIDIR=matches/_engine-$LANE/AI/Skirmish/Apex$LANE/lane-$LANE
KEEP=armawac,armfav,armflea,armpeep,armpt,armsh,armspy,corawac,corfav,corfink,corpt,corsh,corspy
outs=()
for ((s = S0; s <= S1; s++)); do
    while tasklist | grep -qi "^spring.exe"; do sleep 60; done   # his game: no headless engines while he plays
    if (( (s / 2) % 2 == 0 )); then FAC=Armada; else FAC=Cortex; fi
    if (( s % 2 == 0 )); then MT=0; OA="armynet=1"; OB="armynet=0"; else MT=1; OA="armynet=0"; OB="armynet=1"; fi
    out=matches/mvr-$SET-s$s
    t0=$(date +%s)
    python tools/run_match.py --a Apex$LANE:lane-$LANE --b Apex$LANE:lane-$LANE --map "Red Comet Remake 1.8" \
        --minutes 40 --seed $s --speed 4 --handicap 50,50 --sides "$FAC,$FAC" --ai-option $OA --ai-option-b $OB \
        --replay --out $out > $out.log 2>&1 &
    mpid=$!
    dir=$AIDIR/armynet-t$MT
    until [ -f "$dir/armynet_static.txt" ] && [ "$(stat -c %Y "$dir/armynet_static.txt")" -ge "$t0" ]; do
        kill -0 $mpid 2>/dev/null || break
        sleep 1
    done
    python -u tools/armynet/serve.py --dir "$dir" --model "$MODEL" --keep $KEEP $FLAGS > runtime/armynet/mvr-$SET-s$s.log 2>&1 &
    sp=$!
    wait $mpid
    kill $sp 2>/dev/null
    echo "seed $s model t$MT faction $FAC $out" >> $LOG
    outs+=("$out")
done
bash tools/armynet/selfplay_build.sh $SET "${outs[@]}"
