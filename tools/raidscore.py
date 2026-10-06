"""Raid ledger per 1v1 game: whose economy the other side's units killed.

    python tools/raidscore.py <match-dir|tournament-dir> [...] [--to MIN]

From the gadget's [BARAI_DEATH] lines (ground truth, offline only): finished
extractors and constructors killed, per side, split by killer (mobile unit vs
static gun). From the AI's own `apex: nnraid-stat` line: decisions, GO picks,
launches, raiders pulled, what the priced raid pack killed and lost.
1v1 only: the Apex side is the result.json team whose shortName starts Apex.
"""
import glob
import json
import os
import re
import sys

DEATH = re.compile(r"\[BARAI_DEATH\] frame=(\d+) team=(\d+) unit=(\w+) cost=(\d+) .*?built=(\d) mob=(\d) atkteam=(-?\d+) atk=(\S+)")
STAT = re.compile(r"apex: nnraid-stat t=(\d+) (.*)")
REC = re.compile(r"apex: nnraid t=(\d+) .*?rule=(\w+) .*chosen=(\d)")
CON = re.compile(r"^(arm|cor|leg)(ck|cv|ca|ch|cs|ack|acv|aca|acsub|fark|consul|beaver|muskrat|fast|otter)$")
STATIC = re.compile(r"(llt|hlt|beamer|claw|maw|^(arm|cor|leg)rl$|guard|punisher|toxic|lrpc|ambush|viper|gate|dl$|tl$|bombard|annihilator|doomsday|flak|madsam|cir$|cerberus|pit$|jamt)")


def is_eco(name):
    return ('mex' in name) or ('moho' in name) or bool(CON.match(name))


def dirs(args):
    out = []
    for a in args:
        if os.path.exists(os.path.join(a, 'infolog.txt')):
            out.append(a)
        else:
            out += sorted(os.path.dirname(p) for p in glob.glob(os.path.join(a, '*', 'infolog.txt')))
    return out


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    to = None
    if '--to' in sys.argv:
        to = float(sys.argv[sys.argv.index('--to') + 1])
    tot = {'ourEcoN': 0, 'ourEcoM': 0, 'theirEcoN': 0, 'theirEcoM': 0, 'win': 0, 'n': 0}
    print(f"{'game':48s} {'res':4s} {'weKill n/m (mob)':>18s} {'theyKill n/m (mob)':>19s}  ai: dec go launch pull | packKill eco | packLost")
    for d in dirs(args):
        try:
            res = json.load(open(os.path.join(d, 'result.json')))
        except Exception:
            continue
        apex = [t['team'] for t in res.get('teams', []) if str(t.get('shortName', '')).startswith('Apex')]
        if len(apex) != 1 or len(res.get('teams', [])) != 2:
            continue
        us = apex[0]
        win = us in (res.get('result') or {}).get('winners', [])
        statics = set()
        deaths = []
        stat = {}
        recs = {'GO': 0, 'WAIT': 0}
        for ln in open(os.path.join(d, 'infolog.txt'), errors='replace'):
            m = DEATH.search(ln)
            if m:
                f, team, unit, cost, built, mob, at, atk = m.groups()
                if mob == '0':
                    statics.add(unit)
                deaths.append((int(f), int(team), unit, int(cost), built == '1', int(at), atk))
                continue
            m = STAT.search(ln)
            if m and int(m.group(1)) == us:
                stat = dict(kv.split('=', 1) for kv in m.group(2).split() if '=' in kv)
                continue
            m = REC.search(ln)
            if m and int(m.group(1)) == us:
                recs['GO' if m.group(3) == '1' else 'WAIT'] += 1
        row = {'oN': 0, 'oM': 0, 'oMob': 0, 'tN': 0, 'tM': 0, 'tMob': 0}
        for f, team, unit, cost, built, at, atk in deaths:
            if to is not None and f > to * 1800:
                continue
            if not built or not is_eco(unit) or at < 0 or at == team:
                continue
            mob = (atk not in statics) and not STATIC.search(atk)
            if team != us and at == us:
                row['oN'] += 1; row['oM'] += cost; row['oMob'] += mob
            elif team == us and at != us:
                row['tN'] += 1; row['tM'] += cost; row['tMob'] += mob
        tot['ourEcoN'] += row['oN']; tot['ourEcoM'] += row['oM']
        tot['theirEcoN'] += row['tN']; tot['theirEcoM'] += row['tM']
        tot['win'] += win; tot['n'] += 1
        opp = [t for t in res['teams'] if t['team'] != us][0]
        name = os.path.basename(os.path.normpath(d))[:15] + ' ' + res.get('map', '')[:20] + ' ' + str(opp.get('profile', ''))[:12]
        print(f"{name:48s} {'WIN' if win else 'loss':4s} {row['oN']:>5d}/{row['oM']:>5d} ({row['oMob']:>2d}) {row['tN']:>6d}/{row['tM']:>5d} ({row['tMob']:>2d})"
              f"  {stat.get('dec', '-')} {stat.get('go', '-')} {stat.get('launched', '-')} {stat.get('pulled', '-')}"
              f" | {stat.get('killM', '-')} {stat.get('ecoKillM', '-')}/{stat.get('ecoKillN', '-')} | {stat.get('lostM', '-')}/{stat.get('lostN', '-')}"
              f"  rec GO/WAIT={recs['GO']}/{recs['WAIT']}")
    if tot['n']:
        print(f"TOTAL {tot['n']} games, {tot['win']} wins: we killed {tot['ourEcoN']} eco ({tot['ourEcoM']} m), they killed {tot['theirEcoN']} ({tot['theirEcoM']} m)")


if __name__ == '__main__':
    main()
