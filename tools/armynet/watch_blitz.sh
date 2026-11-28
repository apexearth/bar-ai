#!/bin/bash
# A windowed watch game with the Battle Blitz full-set tweaks (gameconfigforbar/barbattleblitz at 66da6339,
# base64-tweaks-for-game-setup/full-set-variant): our AI with the army model on the DLL bridge (team 0), against
# BARb hard (team 1), both +50.
#   bash tools/armynet/watch_blitz.sh [model.pt] [map] [speed]
cd "$(dirname "$0")/../.."
MODEL=${1:-runtime/armynet/enemy1/model-010000.pt}
MAP=${2:-Comet Catcher Remake 1.8}
SPEED=${3:-4}
export BARAI_LANE=armynet
T=$(pwd -W 2>/dev/null || pwd)/runtime/battleblitz/66da6339
REF=66da63397461f35fae555b4862990d5085d3f9bc
URL=https://gitlab.com/gameconfigforbar/barbattleblitz/-/raw/$REF/base64-tweaks-for-game-setup/full-set-variant
# the tweak files are lobby commands, "!bset <key> <base64>"; one plain value file per key
for f in tweakdefs tweakunits tweakunits1 tweakunits2 tweakunits3 tweakunits4 tweakunits5 tweakunits6 tweakunits7 \
         tweakunits8 tweakunits9; do
    if ! grep -q '^!bset' "$T/$f.lua" 2>/dev/null; then
        curl -s -o "$T/$f.lua" "$URL/$f.lua"
        grep -q '^!bset' "$T/$f.lua" || { echo "could not fetch $f.lua (GitLab rate limit?): try again in a minute"; exit 1; }
    fi
    awk '{print $3}' "$T/$f.lua" | tr -d '\r\n' > "$T/$f.b64"
done
MO=()
for f in tweakdefs tweakunits tweakunits1 tweakunits2 tweakunits3 tweakunits4 tweakunits5 tweakunits6 tweakunits7 \
         tweakunits8 tweakunits9; do
    MO+=(--modoption "$f=@$T/$f.b64")
done
AIDIR=matches/_engine-armynet/AI/Skirmish/Apexarmynet/lane-armynet
KEEP=armawac,armfav,armflea,armpeep,armpt,armsh,armspy,corawac,corfav,corfink,corpt,corsh,corspy
OUT=matches/watch-blitz-$(date +%Y%m%d-%H%M%S)
t0=$(date +%s)
python tools/run_match.py --a Apexarmynet:lane-armynet --b BARb:stable:hard --map "$MAP" --minutes 60 --seed 1 \
    --watch --speed "$SPEED" --handicap 50,50 --ai-option armynet=1 --ai-option apex_verbose=1 "${MO[@]}" \
    --out "$OUT" > "$OUT.log" 2>&1 &
mpid=$!
dir=$AIDIR/armynet-t0
until [ -f "$dir/armynet_static.txt" ] && [ "$(stat -c %Y "$dir/armynet_static.txt")" -ge "$t0" ]; do
    kill -0 $mpid 2>/dev/null || { echo "the game ended before the bridge started: see $OUT.log"; exit 1; }
    sleep 1
done
python -u tools/armynet/serve.py --dir "$dir" --model "$MODEL" --keep $KEEP \
    --forces --learned --rally --arc --fbias -0.19 > "$OUT-serve.log" 2>&1 &
spid=$!
echo "watching: model $MODEL on team 0 vs BARb hard, $MAP, speed $SPEED; log $OUT.log"
wait $mpid
kill $spid 2>/dev/null
echo "done: $OUT"
