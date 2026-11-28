import re
import sys

for m in sys.argv[1:]:
    b = {}
    for line in open("matches/watch-armynet-engine-%s/serve.log" % m, encoding="utf-8", errors="replace"):
        r = re.match(r"frame (\d+) units (\d+) new orders (\d+) mean p ([\d.]+)", line)
        if r:
            k = min(int(r.group(1)) // 1800 // 5 * 5, 30)
            s = b.setdefault(k, [0, 0.0, 0, 0])
            s[0] += 1
            s[1] += float(r.group(4))
            s[2] += int(r.group(3))
            s[3] += int(r.group(2))
    print(m, "  ".join("%d-min p %.3f orders/line %.1f units %.0f" % (k, s[1] / s[0], s[2] / s[0], s[3] / s[0])
                        for k, s in sorted(b.items())))
