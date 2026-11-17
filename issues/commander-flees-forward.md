# The commander's evade step can walk him toward their side

Seen 11-16 in his watch game vs WRDistilled 0.4 (matches/watch-wr04-cc2, 1v1 Comet Catcher, them +25): at 14.0 min
about 20 of their Raiders (3,880 metal) were in our base, our army 0-1,320, `com-ship ... decision=RUN-hopeless`. The
C++ retreat's evade (`RetreatTask.cpp`, `apex: com-evade`) steps him every 5 s to the least-threatened of eight points
400 away, in any direction and on the threat map as it stands. Their army sat between him and home, so the empty ground
was toward their start: fwd 0.28 -> 0.54 -> 0.63, and their faster Raiders followed him there (died 14.7 min).

Against pursuers faster than him the momentary threat 400 away says nothing about escape (his 11-16: "they knew he had
nowhere to go and since they had vehicles they had the speed advantage"). Open: what he should do when no safe place is
reachable is his call (toward our nearest guns or army, hold and fight with the D-gun, or keep the evade but never away
from our side). Contract: `com lost on their half` counts these deaths.
