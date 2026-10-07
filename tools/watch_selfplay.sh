#!/bin/sh
# His watched self-play (2026-10-06): our AI vs itself, same faction both
# sides, one side picked at random as the discovery explorer, at 20x.
#   sh tools/watch_selfplay.sh ["Map Name"] [faction]
# The explorer's team number is written to runtime/watch-explorer.txt.
cd "$(dirname "$0")/.." || exit 1
MAP=${1:-"Carrot Mountains v2.0"}
SIDE=${2:-$(python -c "import random;print(random.choice(['armada','cortex','legion']))")}
EX=$(python -c "import random;print(random.randint(0,1))")
echo "$EX" > runtime/watch-explorer.txt
echo "map: $MAP  faction: $SIDE  (explorer team in runtime/watch-explorer.txt)"
python -u tools/run_match.py --a Apexnnlog:lane-nnlog:standard --b Apexnnlog:lane-nnlog:standard \
  --map "$MAP" --watch --sides "$SIDE,$SIDE" --minutes 60 --speed 20 --max-speed 20 \
  --modoption apex_nn_blend=1 --modoption apex_nn_explore_team=$EX
