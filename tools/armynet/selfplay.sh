#!/bin/bash
# Head-to-head / self-play games: two army-model versions command the two sides of one game (Red Comet 1v1, both +50,
# same AI on both sides, versions swapped by seed parity), replays kept for the own-games set. One game at a time per
# lane, because a lane's two bridge folders (armynet-t0, armynet-t1) live in its AI folder; run two lanes for two at once.
#   LANE=armynet bash tools/armynet/selfplay.sh <tag> <seed_from> <seed_to> "<nameX>|<modelX>|<flagsX>" "<nameY>|<modelY>|<flagsY>"
# Ladder lines go to runtime/armynet/h2h-<tag>.log ("seed <s> t0 <name> t1 <name> <match dir>"), read by h2h_report.py.
cd "$(dirname "$0")/../.."
LANE=${LANE:-armynet}
export BARAI_LANE=$LANE
TAG=$1; S0=$2; S1=$3; X=$4; Y=$5
LOG=runtime/armynet/h2h-$TAG.log
AIDIR=matches/_engine-$LANE/AI/Skirmish/Apex$LANE/lane-$LANE
KEEP=armawac,armfav,armflea,armpeep,armpt,armsh,armspy,corawac,corfav,corfink,corpt,corsh,corspy
serve_side() {  # name|model|flags  team  t0  out
    local spec=$1 team=$2 t0=$3 out=$4
    local rest=${spec#*|}; local model=${rest%%|*}; local flags=${rest#*|}
    local dir=$AIDIR/armynet-t$team
    until [ -f "$dir/armynet_static.txt" ] && [ "$(stat -c %Y "$dir/armynet_static.txt")" -ge "$t0" ]; do sleep 1; done
    python -u tools/armynet/serve.py --dir "$dir" --model "$model" --keep $KEEP $flags > "$out" 2>&1 &
    echo $!
}
for ((s = S0; s <= S1; s++)); do
    while tasklist | grep -qi "^spring.exe"; do sleep 60; done   # his game: no headless engines while he plays
    if (( s % 2 == 0 )); then A=$X; B=$Y; else A=$Y; B=$X; fi
    # the same faction on both sides, alternating every two seeds so each version plays both factions on both sides
    # (11-26: with Armada always at t0, t0 won 42 of 65 games)
    if (( (s / 2) % 2 == 0 )); then FAC=Armada; else FAC=Cortex; fi
    out=matches/h2h-$TAG-s$s
    t0=$(date +%s)
    python tools/run_match.py --a Apex$LANE:lane-$LANE --b Apex$LANE:lane-$LANE --map "Red Comet Remake 1.8" \
        --minutes 40 --seed $s --speed 4 --handicap 50,50 --sides "$FAC,$FAC" --ai-option armynet=1 --ai-option-b armynet=1 \
        --replay --out $out > $out.log 2>&1 &
    mpid=$!
    pa=$(serve_side "$A" 0 $t0 runtime/armynet/h2h-$TAG-s$s-t0.log)
    pb=$(serve_side "$B" 1 $t0 runtime/armynet/h2h-$TAG-s$s-t1.log)
    wait $mpid
    kill $pa $pb 2>/dev/null
    echo "seed $s t0 ${A%%|*} t1 ${B%%|*} $out" >> $LOG
done
echo done
