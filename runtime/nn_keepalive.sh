#!/bin/sh
# Restarts the training driver if it has died (his 10-09: keep training, don't stop).
# Stops when runtime/nn_stop exists.
# runtime/nn/neuro_on: the driver is the policy-net evolution (tools/neuro.py, his 10-10) and the old
# regression trainer stays OFF -- every net is part of the evolved network.
# Started by Start-Process, sh has no /usr/bin on PATH: grep missing read every trainer as dead
# and stacked a new one each pass (10-09: three trainers, MemoryError).
export PATH="/usr/bin:$PATH"
cd /c/Users/apexe/WebstormProjects/bar-ai || exit 1
count() { powershell.exe -NoProfile -ExecutionPolicy Bypass -File runtime/nn_running.ps1 "$1" "$2" | tr -dc '0-9'; }
while [ ! -f runtime/nn_stop ]; do
  # runtime/lean/lean_on: training by held leans in paired games (tools/leanloop.py, 10-29)
  if [ -f runtime/lean/lean_on ] && [ "$(count "tools/leanloop.py" python.exe)" = "0" ]; then
    echo "$(date '+%m-%d %H:%M') restarting leanloop" >> runtime/nn_keepalive.log
    powershell.exe -NoProfile -Command "Start-Process -WindowStyle Hidden -FilePath python -ArgumentList '-u','tools/leanloop.py' -RedirectStandardOutput runtime/lean-loop.log -RedirectStandardError runtime/lean-loop.err"
  fi
  # runtime/pg/pg_on: learning from our own choices (tools/pgloop.py, his 10-28; the random search is stopped)
  if [ -f runtime/pg/pg_on ] && [ "$(count "tools/pgloop.py" python.exe)" = "0" ]; then
    echo "$(date '+%m-%d %H:%M') restarting pgloop" >> runtime/nn_keepalive.log
    powershell.exe -NoProfile -Command "Start-Process -WindowStyle Hidden -FilePath python -ArgumentList '-u','tools/pgloop.py' -RedirectStandardOutput runtime/pg-loop.log -RedirectStandardError runtime/pg-loop.err"
  fi
  # runtime/nn/rand_on: the random search with re-tested winners (tools/randsearch.py, his 10-11)
  if [ -f runtime/nn/rand_on ]; then
    if [ "$(count "tools/randsearch.py" python.exe)" = "0" ] && [ "$(count "tools/neuro.py" python.exe)" = "0" ]; then
      echo "$(date '+%m-%d %H:%M') restarting randsearch" >> runtime/nn_keepalive.log
      powershell.exe -NoProfile -Command "Start-Process -WindowStyle Hidden -FilePath python -ArgumentList '-u','tools/randsearch.py' -RedirectStandardOutput runtime/rand-loop.log -RedirectStandardError runtime/rand-loop.err"
    fi
  elif [ -f runtime/nn/neuro_on ]; then
    if [ "$(count "tools/neuro.py" python.exe)" = "0" ]; then
      echo "$(date '+%m-%d %H:%M') restarting neuro" >> runtime/nn_keepalive.log
      powershell.exe -NoProfile -Command "Start-Process -WindowStyle Hidden -FilePath python -ArgumentList '-u','tools/neuro.py' -RedirectStandardOutput runtime/neuro-loop.log -RedirectStandardError runtime/neuro-loop.err"
    fi
  fi
  sleep 300
done
