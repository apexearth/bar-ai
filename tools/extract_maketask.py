#!/usr/bin/env python3
"""One-shot: lift the blocks of Builder::AiMakeTask into named rule functions.

Every function body below is a VERBATIM line slice of the current
builder/maketask.as, so the only hand-written text is the signatures, the
trailing `return null;` and the two `taken = true;` markers in ScreenOffer.
Run once; the result is committed and this script is only kept as the record of
which lines went where.
"""
import os

SRC = 'ai/Unstable/game-side/script/standard/manager/builder/maketask.as'
DIR = os.path.dirname(SRC)

with open(SRC, encoding='utf-8', newline='') as fh:
    raw = fh.read()
eol = '\r\n' if '\r\n' in raw else '\n'
L = raw.replace('\r\n', '\n').split('\n')          # L[i] is source line i+1


def s(a, b):
    """Lines a..b inclusive, 1-based."""
    return L[a - 1:b]


def fn(sig, lines, tail='\treturn null;'):
    out = [sig, '{'] + lines
    if tail:
        out.append(tail)
    out.append('}')
    return out


FILES = {
 'rules_rezzer': [
    ('// Rez bots: the three places their needs differ from an ordinary '
     'constructor,\n// plus the reclaim pre-empt that runs after everything else '
     'has declined.', None),
    fn('IUnitTask@ RezzerFlee(CCircuitUnit@ unit)', s(23, 59)),
    fn('IUnitTask@ RezzerFrontSalvage(CCircuitUnit@ unit)', s(61, 80)),
    fn('IUnitTask@ RezzerEatCorpse(CCircuitUnit@ unit)', s(82, 90)),
    fn('IUnitTask@ RezzerPreemptReclaim(CCircuitUnit@ unit, bool isComm, IUnitTask@ task)',
       s(951, 989), tail=None),
 ],
 'rules_hold': [
    ('// Work already in progress, and the two reasons to drop it.', None),
    fn('IUnitTask@ HoldDefenceInProgress(CCircuitUnit@ unit, bool isComm)', s(103, 130)),
    fn('IUnitTask@ AbandonUnsafeSite(CCircuitUnit@ unit, bool isComm)', s(335, 386)),
    fn('IUnitTask@ HoldWorkInProgress(CCircuitUnit@ unit, bool isComm)', s(388, 411)),
 ],
 'rules_commander': [
    ('// Everything AiMakeTask does differently for the commander: its own safety\n'
     '// rules before work is chosen, and its own vetoes over what work is offered.', None),
    fn('IUnitTask@ CommanderTask(CCircuitUnit@ unit, bool isComm)', s(131, 334)),
    fn('IUnitTask@ CommanderMexGuard(CCircuitUnit@ unit, bool isComm)', s(414, 425)),
    fn('IUnitTask@ VetoCommanderReclaim(CCircuitUnit@ unit, bool isComm, IUnitTask@ task)',
       s(639, 657), tail='\treturn task;'),
    fn('IUnitTask@ VetoCommanderHold(CCircuitUnit@ unit, bool isComm, IUnitTask@ task)',
       s(659, 684), tail='\treturn task;'),
 ],
 'rules_optional': [
    ('// The optional cluster: everything a constructor may do INSTEAD of whatever\n'
     '// DefaultMakeTask would offer it. Runs ahead of expansion, so every rule in\n'
     '// here spends constructor time -- see CHANGES.md 2026-08-01.', None),
    fn('IUnitTask@ OptionalWork(CCircuitUnit@ unit, bool isComm)', s(427, 598)),
 ],
 'rules_offer': [
    ('// Screening what DefaultMakeTask hands back.', None),
    fn('IUnitTask@ ExpansionAlwaysWins(IUnitTask@ task)', s(611, 637)),
    fn('IUnitTask@ VetoCrisisAssist(IUnitTask@ task)', s(686, 711), tail='\treturn task;'),
    ('// `taken` means the returned handle is the final answer; otherwise it is the\n'
     '// offer to carry on with, which may be null.', None),
    fn('IUnitTask@ ScreenOffer(CCircuitUnit@ unit, bool isComm, IUnitTask@ task, bool &out taken)',
       ['\ttaken = false;'] + s(713, 825), tail='\treturn task;'),
 ],
 'rules_scavenge': [
    ('// Metal on the ground, and the two last-resort jobs for a constructor that\n'
     '// everything above declined.', None),
    fn('IUnitTask@ ScavengeWrecks(CCircuitUnit@ unit, bool isComm, bool isAdvCon)', s(826, 913)),
    fn('IUnitTask@ MetalFullFallback(CCircuitUnit@ unit, bool isComm)', s(918, 940)),
    fn('IUnitTask@ TidyObsolete(CCircuitUnit@ unit, bool isComm)', s(942, 949)),
 ],
}

# The two early returns inside ScreenOffer become "this is the final answer".
screen = FILES['rules_offer'][-1]
assert sum(1 for l in screen if l.strip().startswith('return ')) == 3, \
    [l for l in screen if l.strip().startswith('return ')]
hits = 0
for i, line in enumerate(screen):
    if line in ('\t\t\t\t\t\treturn other;', '\t\t\t\t\treturn post;'):
        tabs = '\t' * (len(line) - len(line.lstrip('\t')))
        guard = screen[i - 1]
        assert guard.strip().startswith('if (') and guard.endswith('!is null)'), guard
        screen[i - 1] = guard + ' {'
        screen[i] = (tabs + 'taken = true;\n' + line + '\n'
                     + tabs[:-1] + '}')
        hits += 1
assert hits == 2, hits

for name, parts in FILES.items():
    body = []
    for p in parts:
        if isinstance(p, tuple):
            body.append(p[0])
        else:
            body.append('\n'.join(p))
    out = 'namespace Builder {\n\n' + '\n\n'.join(body) + '\n\n}  // namespace Builder\n'
    path = os.path.join(DIR, name + '.as')
    with open(path, 'w', encoding='utf-8', newline='') as fh:
        fh.write(out.replace('\n', eol))
    print('%-24s %4d lines' % (name + '.as', out.count('\n')))
