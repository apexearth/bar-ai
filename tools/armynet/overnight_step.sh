#!/usr/bin/env bash
# The 11-19 overnight run at STEP-frame decisions (his: "under 500 milliseconds", "complete movement learnings from
# players, and use NO BARb fight logic"). Run from the repo root once his game is over:
#     bash tools/armynet/overnight_step.sh
# 1. deploy the gadget (state and hits every 10 frames)
# 2. queue every once-a-second recording for re-recording (kept as orders.1hz.txt.gz) and start the recorder
#    (low-priority engines; it stops a replay when his game starts)
# 3. rebuild every dataset (STEP decisions, stays, economy values, enemy kills only, income column)
# 4. the campaign: training from the movement-input model, 2 headless games per 10k steps at 4x (serve keeps up)
set -u
cd "$(dirname "$0")/../.."
python tools/deploy_ai.py gadgets | grep -i armynet
python tools/armynet/requeue_rate.py
nohup python -u tools/public_replays.py follow --workers 3 >> G:/bar-ai-archive/public-replays/follow.log 2>&1 &
python -u tools/replay_dataset.py "G:/bar-ai-archive/public-replays/recordings" --force --jobs 6 > G:/bar-ai-archive/rebuild-step.log 2>&1
python -u tools/replay_dataset.py "G:/bar-ai-archive/replay-orders" --force --jobs 6 >> G:/bar-ai-archive/rebuild-step.log 2>&1
echo "rebuilt $(grep -c ' decisions ' G:/bar-ai-archive/rebuild-step.log), failed $(grep -c FAILED G:/bar-ai-archive/rebuild-step.log)"
python -u tools/armynet/campaign.py --every 10000 --workers 4 --headless 2 --mirror --late --rounds --minutes 40 \
    --speed 4 --init runtime/armynet/move-init.pt --start-step 20000 > runtime/armynet/campaign-launch.log 2>&1
