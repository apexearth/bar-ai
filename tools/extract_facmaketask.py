#!/usr/bin/env python3
"""One-shot: lift the blocks of Factory::AiMakeTask into named rule functions.

Same contract as extract_maketask.py -- every body is a verbatim line slice of
the file as it stood, so the only hand-written text is signatures, trailing
`return null;` and the three `taken = true;` markers.
"""
import os

SRC = 'ai/apex/game-side/script/hard_aggressive/manager/factory/maketask.as'
DIR = os.path.dirname(SRC)

with open(SRC, encoding='utf-8', newline='') as fh:
    raw = fh.read()
eol = '\r\n' if '\r\n' in raw else '\n'
L = raw.replace('\r\n', '\n').split('\n')


def s(a, b):
    return L[a - 1:b]


def fn(sig, lines, tail='\treturn null;'):
    out = [sig, '{'] + lines
    if tail:
        out.append(tail)
    out.append('}')
    return out


def taken(lines):
    """Mark every bare `return null;` as "this is the final answer"."""
    out, hits = [], 0
    for line in lines:
        if line.split('//')[0].strip() == 'return null;':
            tabs = line[:len(line) - len(line.lstrip('\t'))]
            out.append(tabs + 'taken = true;')
            hits += 1
        out.append(line)
    assert hits > 0
    return out


FILES = {
 'rules_recruit': [
    ('// Recruiting floors: things a factory must produce some of, regardless of\n'
     '// what the ratios in factory.json would otherwise pick.', None),
    fn('void FactoryDiag(CCircuitUnit@ unit)', s(5, 16), tail=None),
    fn('IUnitTask@ AssistantWork(CCircuitUnit@ unit)', s(18, 31)),
    fn('IUnitTask@ RezBotFloor(CCircuitUnit@ unit)', s(39, 106)),
    fn('IUnitTask@ BankBuysBuildPower(CCircuitUnit@ unit)', s(108, 146)),
    fn('IUnitTask@ LateRadarPlane(CCircuitUnit@ unit)', s(148, 172)),
    fn('IUnitTask@ LateFighterScreen(CCircuitUnit@ unit)', s(174, 195)),
 ],
 'rules_rush': [
    ('// The tech rush and the two things that replace ordinary army production\n'
     '// while it runs.', None),
    fn('IUnitTask@ RushBuildPower(CCircuitUnit@ unit, bool &out taken)',
       ['\ttaken = false;'] + taken(s(197, 244))),
    fn('void ConBranchLog(CCircuitUnit@ unit)', s(246, 286), tail=None),
    fn('IUnitTask@ ShareAdvancedCon(CCircuitUnit@ unit)', s(371, 389)),
    fn('IUnitTask@ LosingArmyPush(CCircuitUnit@ unit)', s(287, 369)),
 ],
 'rules_ecolead': [
    ('// The eco lead deliberately runs an idle production line; these are the two\n'
     '// exceptions to that.', None),
    fn('IUnitTask@ AirConMinimum(CCircuitUnit@ unit)', s(391, 419)),
    fn('IUnitTask@ EcoLeadLine(CCircuitUnit@ unit, bool &out taken)',
       ['\ttaken = false;'] + taken(s(421, 479))),
 ],
}

for name, parts in FILES.items():
    body = [p[0] if isinstance(p, tuple) else '\n'.join(p) for p in parts]
    out = 'namespace Factory {\n\n' + '\n\n'.join(body) + '\n\n}  // namespace Factory\n'
    with open(os.path.join(DIR, name + '.as'), 'w', encoding='utf-8', newline='') as fh:
        fh.write(out.replace('\n', eol))
    print('%-24s %4d lines' % (name + '.as', out.count('\n')))

PIPELINE = '''namespace Factory {

// What a factory builds next, as an ordered pipeline. The first rule that
// returns a task wins; `taken` means a rule wants the line to stay IDLE, which
// is a deliberate outcome here rather than a failure.
//
// The rules live in rules_*.as; their bodies are unchanged from when they were
// inline in this function.
IUnitTask@ AiMakeTask(CCircuitUnit@ unit)
{
\tFactoryDiag(unit);

\tIUnitTask@ t = AssistantWork(unit);
\tif (t !is null)
\t\treturn t;

\t// Safe to sit first: this answers only for the advanced air plant, so the
\t// ground line's branches below are untouched.
\t@t = Air::MakeFactoryTask(unit);
\tif (t !is null)
\t\treturn t;

\t@t = RezBotFloor(unit);
\tif (t !is null)
\t\treturn t;
\t@t = BankBuysBuildPower(unit);
\tif (t !is null)
\t\treturn t;
\t@t = LateRadarPlane(unit);
\tif (t !is null)
\t\treturn t;
\t@t = LateFighterScreen(unit);
\tif (t !is null)
\t\treturn t;

\tbool idle = false;
\t@t = RushBuildPower(unit, idle);
\tif (idle || (t !is null))
\t\treturn t;

\tConBranchLog(unit);
\t@t = LosingArmyPush(unit);
\tif (t !is null)
\t\treturn t;
\t@t = ShareAdvancedCon(unit);
\tif (t !is null)
\t\treturn t;
\t@t = AirConMinimum(unit);
\tif (t !is null)
\t\treturn t;

\t@t = EcoLeadLine(unit, idle);
\tif (idle || (t !is null))
\t\treturn t;

\t// An air plant that Air:: did not claim above falls through to
\t// DefaultMakeTask like every other factory.
\t//
\t// This used to return null for ANY air factory unless the air role had been
\t// permanently abandoned, on the reasoning that every sanctioned use of an air
\t// plant claims it earlier in this function. That reasoning holds only for the
\t// air lead's plants while it is armed. It is false for the air-slot opener,
\t// which is never the lead (the lead is elected on highest income and the
\t// opener has the worst economy on the team), and it is false for the lead
\t// itself whenever Air:: declines -- quota met, enemy AA too high, not yet
\t// committed. In all of those cases the plant produced NOTHING, permanently.
\t//
\t// apexearth: "our air player made just 1 con and thats it... air lab just
\t// sitting there doing nothing else", then "i bet we have some special flag or
\t// branching path of logic that is breaking our air opening player", then
\t// "Can we not have this whole Air::RoleAbandoned logic in here? I bet that is
\t// the cause of a lot of air labs i see sitting there doing nothing."
\t//
\t// The concern this originally answered -- trickling bombers one at a time
\t// into enemy AA -- is about how bombers are USED, not about starving every
\t// air plant on the team.
\treturn aiFactoryMgr.DefaultMakeTask(unit);
}

}  // namespace Factory
'''

with open(SRC, 'w', encoding='utf-8', newline='') as fh:
    fh.write(PIPELINE.replace('\n', eol))
print('%-24s %4d lines' % ('maketask.as', PIPELINE.count('\n')))
