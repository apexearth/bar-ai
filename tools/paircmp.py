"""Paired comparison of two openloop batches, seed by seed.

    python tools/paircmp.py <control-dir> <treatment-dir> [--minute 4]

run_tournament walks the same seeds in the same order for every batch, so the
same seed is the same map, the same start boxes and the same BARb. Comparing
the MEANS of two batches throws that away and leaves a +-0.5 mex noise floor
at 32 games; comparing each seed against itself cancels it, and the sign test
over the pairs says whether the difference is real at a much smaller n.
"""
import collections
import glob
import json
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import openloop


def by_seed(T, minute):
    out = {}
    for M in sorted(glob.glob(os.path.join(T, 'matches', 't*'))):
        rj = os.path.join(M, 'result.json')
        if not os.path.exists(rj):
            continue
        seed = json.load(open(rj)).get('seed')
        script = open(os.path.join(M, 'script.txt')).read()
        left = re.search(r'\[AI0\](.*?)\[AI1\]', script, re.S).group(1)
        key = (seed, 'Apex' in left)   # seed AND which box we played
        s = openloop.one(M)
        us, them = s[(minute, 'us')], s[(minute, 'them')]
        out[key] = dict(mex=us['mex'] - them['mex'], mine=us['mex'],
                        theirs=them['mex'], lost=us['lost'] - them['lost'],
                        army=us['army'] - them['army'], guarded=us['guarded'])
    return out


def main():
    minute = 4
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    if '--minute' in sys.argv:
        minute = int(sys.argv[sys.argv.index('--minute') + 1])
    ctl, trt = by_seed(args[0], minute), by_seed(args[1], minute)
    keys = sorted(set(ctl) & set(trt))
    if not keys:
        print('no shared seeds')
        return
    print('paired on %d seeds, at minute %d  (control %s -> treatment %s)'
          % (len(keys), minute, os.path.basename(os.path.normpath(args[0])),
             os.path.basename(os.path.normpath(args[1]))))
    for field in ('mex', 'mine', 'theirs', 'lost', 'army', 'guarded'):
        d = [trt[k][field] - ctl[k][field] for k in keys]
        mean = sum(d) / len(d)
        better = sum(1 for x in d if x > 0)
        worse = sum(1 for x in d if x < 0)
        sd = math.sqrt(sum((x - mean) ** 2 for x in d) / max(len(d) - 1, 1))
        se = sd / math.sqrt(len(d)) if len(d) > 1 else 0.0
        flag = ''
        if se > 0 and abs(mean) > 2 * se:
            flag = '  <- outside 2 standard errors'
        print('  %-8s %+7.2f  (better %2d / worse %2d / same %2d, se %.2f)%s'
              % (field, mean, better, worse, len(d) - better - worse, se, flag))


if __name__ == '__main__':
    main()
