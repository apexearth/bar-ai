# Air in long games: waves short and unescorted, no fighters against massed air (his 11-05)

His report from games with people: a well-defended base still falls to a big air raid, and he loves it when it
happens; ours rarely do. Humans build a lot of AA; our waves arrive spread out and too small; bombers go in without
fighters and die to theirs; 20-30 heavy bombers hit us and we have almost no fighters.

## Measured 11-05 (`tools/airstory.py`, 25 loop games that ran 40-60 min, vs BARb hard/aggressive and v0.5.05)

Per game per 10 minutes, all our seats together:

| min | air share of what we build | theirs | strikes | bombers/strike | no fighter escort | waves short of the bombers their target needs | wave survival |
|---|---|---|---|---|---|---|---|
| 10-20 | 13% | 8% | 9.0 | 6 | 42% | 52% | 0.12 |
| 20-30 | 23% | 10% | 7.9 | 7 | 35% | 40% | 0.17 |
| 30-40 | 27% | 10% | 5.5 | 12 | 36% | 43% | 0.31 |
| 40-50 | 27% | 14% | 3.0 | 32 | 45% | 55% | 0.33 |
| 50-60 (7 games) | 26% | 14% | 5.9 | 24 | 37% | 42% | 0.10 |

- We do not stop building air against these AIs: a quarter of all we build after minute 20. Waves grow (6 -> 32
  bombers) but 4 in 10 have no fighter with them and about half are smaller than their own target needs; 7-9 in
  10 bombers do not come home.
- Massed enemy air with no fighters: c05-g1120 (4v4 vs v0.5.05) -- their side built 693 Phoenix heavy bombers;
  ours 12 fighters all game. Our fighter decision priced fighters at gain 3,527 (near its highest) with 0 ordered,
  0 held and no AA building on offer (`aa=[]`). Our 9 air plants died between minutes 8 and 24.5; none stood
  after, so the want had no plant to fill it. c05-g1124: 1,211 fighters built, 77-100 alive to minute 50, 0 at
  50-60 while their bombers and gunships alive rose to 207. c05-g1138 (8v8): theirs 125 -> 193 alive, ours 0.
- BARb makes little air (10-14% of its build), so most loop games never test the massed-air case; the games
  against our release do.
- Not yet measured: how spread out a wave ARRIVES (todo/air-arrives-together.md), and anything against humans
  (these are AI opponents; his online logs carry the same lines).

## Instrument fix

`tools/airaudit.py` read our side from result.json, which lists one entry per side: it counted only our first
seat in team games (1 of 8 in an 8v8) and both sides against an Apex release. It reads every player from
script.txt now.

## Next

Why a lost air plant is not rebuilt while the fighter want is near its peak (c05-g1120); then escorts, then wave
size against what the target needs. Related todos: offensive-air-escalate, air-arrives-together, aa-answers-big-air,
ultra-late-air, strike-their-aa.
