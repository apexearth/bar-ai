#!/bin/bash
# A candidate army model head-to-head against the played one (his rule: a model change counts only against what he
# plays). As model_vs_rules.sh (Red Comet 1v1, both +50, 40 min, speed 4, same faction both sides, candidate side by
# seed parity, replays kept and built), but both teams are the model: the candidate serves with its flags and
# BARAI_ABSENT=$CAND_ABSENT, the played model with its own. The run log names the candidate's team as "model", so
# objectives_army.py --side model reads the candidate and --side rules the played model.
#   LANE=armynet CAND_ABSENT=1 bash tools/armynet/model_vs_model.sh <set> <s0> <s1> "<cand.pt>" "<cand flags>" "<played.pt>" "<played flags>"
cd "$(dirname "$0")/../.."
LANE=${LANE:-armynet}
export BARAI_LANE=$LANE
SET=$1; S0=$2; S1=$3; MODEL=$4; FLAGS=$5; PMODEL=$6; PFLAGS=$7
CAND_ABSENT=${CAND_ABSENT:-0}
LOG=runtime/armynet/mvr-$SET.log
AIDIR=matches/_engine-$LANE/AI/Skirmish/Apex$LANE/lane-$LANE
KEEP=armawac,armfav,armflea,armpeep,armpt,armsh,armspy,corawac,corfav,corfink,corpt,corsh,corspy
outs=()
for ((s = S0; s <= S1; s++)); do
    while tasklist | grep -qi "^spring.exe"; do sleep 60; done   # his game: no headless engines while he plays
    if (( (s / 2) % 2 == 0 )); then FAC=Armada; else FAC=Cortex; fi
    if (( s % 2 == 0 )); then MT=0; else MT=1; fi
    PT=$((1 - MT))
    out=matches/mvr-$SET-s$s
    t0=$(date +%s)
    python tools/run_match.py --a Apex$LANE:lane-$LANE --b Apex$LANE:lane-$LANE --map "Red Comet Remake 1.8" \
        --minutes 40 --seed $s --speed 4 --handicap 50,50 --sides "$FAC,$FAC" --ai-option armynet=1 \
        --ai-option-b armynet=1 --replay --out $out > $out.log 2>&1 &
    mpid=$!
    for t in $MT $PT; do
        until [ -f "$AIDIR/armynet-t$t/armynet_static.txt" ] && [ "$(stat -c %Y "$AIDIR/armynet-t$t/armynet_static.txt")" -ge "$t0" ]; do
            kill -0 $mpid 2>/dev/null || break
            sleep 1
        done
    done
    BARAI_ABSENT=$CAND_ABSENT python -u tools/armynet/serve.py --dir "$AIDIR/armynet-t$MT" --model "$MODEL" --keep $KEEP \
        $FLAGS > runtime/armynet/mvr-$SET-s$s.log 2>&1 &
    sp=$!
    BARAI_ABSENT=0 python -u tools/armynet/serve.py --dir "$AIDIR/armynet-t$PT" --model "$PMODEL" --keep $KEEP \
        $PFLAGS > runtime/armynet/mvr-$SET-s$s-played.log 2>&1 &
    sp2=$!
    wait $mpid
    kill $sp $sp2 2>/dev/null
    echo "seed $s model t$MT faction $FAC $out" >> $LOG
    outs+=("$out")
done
bash tools/armynet/selfplay_build.sh $SET "${outs[@]}"
