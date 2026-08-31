"""Static scope and include-order checks for the AngelScript variant.

There is no offline AngelScript compiler here, and a compile error disables the
whole variant while the match still reports a normal result -- so the failure is
silent twice over. This module does the part that is achievable without a
parser, aimed at the three errors that have actually shipped:

  order   a global INITIALIZER reading a global, const or type that the shim
          includes later -- qualified (`Late::BASE`) or not. `No matching
          symbol`, and the whole variant is disabled.
  scope   a local read outside the block it was declared in. `bestIsWall` was
          referenced ~90 lines below its enclosing `if`, in a 2,122-line file.

The include order is taken from the shims: CScriptBuilder adds a section, THEN
walks that section's own includes depth-first in listed order, skipping any file
already added. `resolve_order()` reproduces that walk exactly.

CLAUDE.md's rule -- "globals, consts and types must be declared before the line
that reads them" -- is broader than the compiler's. AngelScript parses every
section and registers every type and global before compiling one function, so
bodies and parameter types see the whole module in any order; this tree relies
on that in both directions and runs. Only a global's initializer expression is
compiled in declaration order, so that is the only thing `order` reports.

The reference scan is deliberately conservative: a name is reported only when it
is KNOWN to be declared somewhere, so an unrecognised identifier (every engine
binding) is ignored rather than guessed at.

    python tools/as_scope.py                      # the Unstable variant
    python tools/as_scope.py ai/X/game-side/script/standard/main.as
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

# --- comment / string stripping --------------------------------------------
#
# Line structure must survive so offsets still map to line numbers, so every
# removed character is replaced by a space and every newline is kept.

_TOKEN = re.compile(r"//|/\*|\"|'")


def strip_code(text: str, strings: bool = True) -> str:
    """Blank comments (and, by default, string literals) keeping line structure.

    `strings=False` for the include scan -- an #include's path IS a string
    literal, so blanking it hides every file but the root."""
    out = list(text)
    i, n = 0, len(text)
    while i < n:
        m = _TOKEN.search(text, i)
        if not m:
            break
        i = m.start()
        tok = m.group(0)
        if tok == "//":
            j = text.find("\n", i)
            j = n if j < 0 else j
        elif tok == "/*":
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
        else:  # a string or char literal
            j = i + 1
            while j < n and text[j] != tok[0]:
                j += 2 if text[j] == "\\" else 1
            j = min(j + 1, n)
            if not strings:
                i = j
                continue
        for k in range(i, j):
            if out[k] != "\n":
                out[k] = " "
        i = j
    return "".join(out)


# --- include order ----------------------------------------------------------


_INCLUDE = re.compile(r'^\s*#include\s+"([^"]+)"', re.M)


def resolve_order(root: Path) -> list[Path]:
    """CScriptBuilder's walk: add the section, then its includes, depth-first."""
    order: list[Path] = []
    seen: set[Path] = set()

    def walk(path: Path) -> None:
        path = path.resolve()
        if path in seen or not path.exists():
            return
        seen.add(path)
        order.append(path)
        text = path.read_text(encoding="utf-8", errors="replace")
        for rel in _INCLUDE.findall(strip_code(text, strings=False)):
            walk((path.parent / rel))

    walk(root)
    return order


# --- declaration scanning ---------------------------------------------------

RESERVED = {
    "and", "abstract", "auto", "bool", "break", "case", "cast", "catch",
    "class", "const", "continue", "default", "do", "double", "else", "enum",
    "explicit", "external", "false", "final", "float", "for", "from", "funcdef",
    "function", "get", "if", "import", "in", "inout", "int", "int8", "int16",
    "int32", "int64", "interface", "is", "mixin", "namespace", "not", "null",
    "or", "out", "override", "private", "property", "protected", "return",
    "set", "shared", "super", "switch", "this", "true", "try", "typedef",
    "uint", "uint8", "uint16", "uint32", "uint64", "void", "while", "xor",
}

# A declaration statement: an optional `const`, a type, an optional handle `@`,
# a name, then `=` / `;` / `,`. Anchored, so a call or a comparison never
# matches.
_DECL = re.compile(
    r"^(?:const\s+)?"
    r"(?P<type>(?:[A-Za-z_][A-Za-z0-9_]*::)*[A-Za-z_][A-Za-z0-9_]*"
    r"(?:\s*<[^<>]*(?:<[^<>]*>)?[^<>]*>)?)"
    r"(?:\s*@)?\s+"
    # `(` is the constructor form `AIFloat3 mid(x, y, z);` -- a plain call has
    # only ONE identifier before the paren, so two never matches one.
    r"(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*(?:=(?!=)|;|,|\(|$)"
)

_NAMESPACE = re.compile(r"(?:^|\s)namespace\s+([A-Za-z_][A-Za-z0-9_:]*)\s*$")
_TYPEDECL = re.compile(
    r"(?:^|\s)(?:shared\s+|abstract\s+|final\s+)*"
    r"(class|interface|enum)\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?::[^{]*)?$")
# `Type Name(args)` / `Type@ Name(args) const` -- what opens a function body.
_FUNC = re.compile(
    r"(?:^|[\s;}])(?:private\s+|shared\s+)*"
    r"(?:const\s+)?(?:[A-Za-z_][A-Za-z0-9_:]*(?:\s*<[^<>]*>)?\s*@?(?:\s*&)?\s+)?"
    r"(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*\((?P<args>[^()]*(?:\([^()]*\)[^()]*)*)\)"
    r"\s*(?:const\s*)?$")
_FUNCDEF = re.compile(r"(?:^|\s)funcdef\s+.*?([A-Za-z_][A-Za-z0-9_]*)\s*\(")

# `Ns::name`, and the identifier scanner used for references.
_IDENT = re.compile(r"(?<![\w.])((?:[A-Za-z_][A-Za-z0-9_]*::)*)([A-Za-z_][A-Za-z0-9_]*)")


class Frame:
    __slots__ = ("kind", "name", "start", "locals")

    def __init__(self, kind: str, name: str, start: int) -> None:
        self.kind = kind          # ns | type | func | block
        self.name = name
        self.start = start
        self.locals: dict[str, list[tuple[int, int]]] = {}


class FileScan:
    """One file's declarations, plus the local-scope ranges inside each body."""

    def __init__(self, path: Path, index: int) -> None:
        self.path = path
        self.index = index
        self.text = strip_code(path.read_text(encoding="utf-8", errors="replace"))
        # (namespace, name) -> offset, for globals / consts / types / enums.
        self.globals: dict[tuple[str, str], int] = {}
        self.funcs: set[str] = set()
        self.namespaces: set[str] = set()
        # [(func-name, func-start, func-end, {name: [(from, to), ...]})]
        self.bodies: list[tuple[str, int, int, dict[str, list[tuple[int, int]]]]] = []
        # (from, to) for every GLOBAL initializer expression -- the only place
        # declaration order is a hard error. See analyse().
        self.init_spans: list[tuple[int, int]] = []
        self._scan()

    def line(self, off: int) -> int:
        return self.text.count("\n", 0, off) + 1

    # -- the scanner ---------------------------------------------------------

    def _scan(self) -> None:
        text = self.text
        stack: list[Frame] = []
        pending_start = 0
        paren = 0
        i, n = 0, len(text)

        def ns_path() -> str:
            return "::".join(f.name for f in stack if f.kind == "ns")

        def in_body() -> bool:
            return any(f.kind == "func" for f in stack)

        def record_decl(stmt: str, off: int, end: int) -> None:
            m = _DECL.match(stmt.strip())
            if not m or m.group("type") in RESERVED - {"const"} \
                    and m.group("type") not in _TYPE_WORDS:
                return
            if m.group("name") in RESERVED:
                return
            names = [m.group("name")]
            # `float a = 1, b = 2;` -- the tail after each comma at depth 0.
            tail = stmt.strip()[m.end():]
            if tail.startswith("="):
                tail = _split_top(tail)
            for extra in _extra_names(tail):
                names.append(extra)
            if in_body():
                frame = stack[-1]
                for nm in names:
                    frame.locals.setdefault(nm, []).append((off, -1))
            elif stack and stack[-1].kind == "type":
                pass  # a class member; reached through an instance, not by name
            else:
                seg0 = self.text[off:end]
                for nm in names:
                    at = seg0.find(nm)
                    self.globals.setdefault((ns_path(), nm),
                                            off + (at if at >= 0 else 0))
                seg = self.text[off:end]
                k = _init_at(seg)
                if k >= 0:
                    self.init_spans.append((off + k, end))

        while i < n:
            c = text[i]
            if c == "(":
                paren += 1
                i += 1
                continue
            if c == ")":
                paren = max(0, paren - 1)
                i += 1
                continue
            if paren:
                i += 1
                continue
            if c == "{":
                head = text[pending_start:i]
                flat = " ".join(head.split())
                m = _NAMESPACE.search(flat)
                if m:
                    for part in m.group(1).split("::"):
                        stack.append(Frame("ns", part, i))
                        self.namespaces.add(part)
                    # one closing brace for the whole `namespace A::B` header
                    for _ in range(len(m.group(1).split("::")) - 1):
                        stack[-1].kind = "ns"
                    self._nswidth = len(m.group(1).split("::"))
                    stack[-1].name = m.group(1).split("::")[-1]
                    # collapse: keep one frame, remember how many to pop
                    extra = len(m.group(1).split("::")) - 1
                    for _ in range(extra):
                        stack.pop(-2)
                    stack[-1].name = m.group(1)
                else:
                    mt = _TYPEDECL.search(flat)
                    if mt:
                        stack.append(Frame("type", mt.group(2), i))
                        if not in_body():
                            self.globals.setdefault((ns_path(), mt.group(2)), i)
                    else:
                        mf = None if in_body() else _FUNC.search(flat)
                        if mf and mf.group("name") not in RESERVED:
                            f = Frame("func", mf.group("name"), i)
                            self.funcs.add(mf.group("name"))
                            for pname in _params(mf.group("args")):
                                f.locals.setdefault(pname, []).append((i, -1))
                            stack.append(f)
                        else:
                            f = Frame("block", "", i)
                            # `for (uint k = 0; ...)` declares into this block,
                            # and the header that reads k sits BEFORE the brace
                            if in_body():
                                for pname in _for_decls(flat):
                                    f.locals.setdefault(pname, []).append(
                                        (pending_start, -1))
                            stack.append(f)
                pending_start = i + 1
                i += 1
                continue
            if c == "}":
                if stack:
                    f = stack.pop()
                    if f.kind in ("func", "block"):
                        for nm, spans in f.locals.items():
                            f.locals[nm] = [(a, i if b < 0 else b) for a, b in spans]
                    if f.kind == "block" and stack and stack[-1].kind in ("func", "block"):
                        # a block's locals die with it, but must still be known
                        # to the enclosing function's reference pass
                        host = stack[-1]
                        for nm, spans in f.locals.items():
                            host.locals.setdefault("\0" + nm, []).extend(spans)
                    if f.kind == "func":
                        merged: dict[str, list[tuple[int, int]]] = {}
                        for nm, spans in f.locals.items():
                            merged.setdefault(nm.lstrip("\0"), []).extend(spans)
                        self.bodies.append((f.name, f.start, i, merged))
                    elif f.kind == "block" and stack and stack[-1].kind == "func":
                        pass
                pending_start = i + 1
                i += 1
                continue
            if c == ";":
                stmt = text[pending_start:i]
                flat = " ".join(stmt.split())
                # A BRACE-LESS `for (uint i = 0; ...) body;` opens no frame, so
                # its counter would look undeclared -- and the next braced loop
                # reusing the name would get the blame.
                if in_body():
                    for pname in _for_decls(flat):
                        stack[-1].locals.setdefault(pname, []).append(
                            (pending_start, i))
                mfd = _FUNCDEF.search(flat)
                if mfd:
                    self.globals.setdefault((ns_path(), mfd.group(1)), pending_start)
                elif flat and not flat.startswith("#"):
                    record_decl(flat, pending_start, i)
                pending_start = i + 1
                i += 1
                continue
            i += 1

        # close anything an unbalanced file left open
        for f in stack:
            if f.kind == "func":
                merged = {}
                for nm, spans in f.locals.items():
                    merged.setdefault(nm.lstrip("\0"), []).extend(
                        [(a, n if b < 0 else b) for a, b in spans])
                self.bodies.append((f.name, f.start, n, merged))


_TYPE_WORDS = {
    "bool", "int", "int8", "int16", "int32", "int64", "uint", "uint8",
    "uint16", "uint32", "uint64", "float", "double", "void", "array",
    "string", "dictionary", "const",
}


def _init_at(seg: str) -> int:
    """Offset of a declaration's initializer inside its own statement text."""
    depth = 0
    for k, ch in enumerate(seg):
        if ch in "([<":
            if ch == "(" and depth == 0:
                return k          # `AIFloat3 gMid(x, y, z);`
            depth += 1
        elif ch in ")]>":
            depth -= 1
        elif ch == "=" and depth == 0 and seg[k:k + 2] != "==" \
                and (k == 0 or seg[k - 1] not in "=!<>"):
            return k + 1
    return -1


def _split_top(tail: str) -> str:
    """Everything after the initializer expression's top-level commas."""
    depth = 0
    for k, ch in enumerate(tail):
        if ch in "([{<":
            depth += 1
        elif ch in ")]}>":
            depth -= 1
        elif ch == "," and depth == 0:
            return tail[k:]
    return ""


def _extra_names(tail: str):
    for part in tail.split(","):
        part = part.strip()
        m = re.match(r"^@?\s*([A-Za-z_][A-Za-z0-9_]*)\s*(?:=|$)", part)
        if m and m.group(1) not in RESERVED:
            yield m.group(1)


def _params(args: str):
    for part in _top_commas(args):
        part = part.strip()
        if not part:
            continue
        m = re.match(
            r"^(?:const\s+)?[A-Za-z_][A-Za-z0-9_:]*(?:\s*<[^<>]*>)?\s*[@&]*"
            r"(?:\s*(?:in|out|inout))?\s*[@&]*\s*([A-Za-z_][A-Za-z0-9_]*)", part)
        if m and m.group(1) not in RESERVED:
            yield m.group(1)


def _top_commas(s: str):
    depth, last = 0, 0
    for k, ch in enumerate(s):
        if ch in "([{<":
            depth += 1
        elif ch in ")]}>":
            depth -= 1
        elif ch == "," and depth == 0:
            yield s[last:k]
            last = k + 1
    yield s[last:]


def _for_decls(flat: str):
    """The counter(s) a `for (...)` header declares, wherever the header sits."""
    k = -1
    for m in re.finditer(r"\bfor\s*\(", flat):
        k = m.end() - 1
        break
    if k < 0:
        return
    depth, close = 0, -1
    for j in range(k, len(flat)):
        if flat[j] == "(":
            depth += 1
        elif flat[j] == ")":
            depth -= 1
            if depth == 0:
                close = j
                break
    if close < 0:
        return
    init = flat[k + 1:close].split(";", 1)[0]
    for part in init.split(","):
        d = _DECL.match(part.strip() + ";")
        if d and d.group("name") not in RESERVED:
            yield d.group("name")


# --- the checks -------------------------------------------------------------


def analyse(root: Path):
    order = resolve_order(root)
    scans = [FileScan(p, i) for i, p in enumerate(order)]

    # every symbol the module knows, and the file index that declares it
    decl_at: dict[tuple[str, str], tuple[int, int]] = {}
    for s in scans:
        for key, off in s.globals.items():
            decl_at.setdefault(key, (s.index, off))
    all_funcs: set[str] = set()
    all_ns: set[str] = set()
    for s in scans:
        all_funcs |= s.funcs
        all_ns |= s.namespaces
    bare_names = {name for (_, name) in decl_at}

    findings: list[tuple[str, Path, int, str]] = []

    # -- 1 + 3: a symbol read before the file that declares it ---------------
    for s in scans:
        # ONLY a global's initializer expression is order-sensitive, and this
        # is narrower than CLAUDE.md states. AngelScript parses every section
        # and registers every type and global before it compiles a single
        # function, so a body -- and a signature's parameter types -- see the
        # whole module whatever the shim order. The tree proves both halves and
        # runs: market/want_super.as reads Base::gAnchor from a namespace
        # main.as includes four lines later, and builder/requests.as takes a
        # `Task::BuildType` parameter with task.as seven includes behind it.
        # Global initializers are compiled in declaration order, and that one
        # is a real `No matching symbol`.
        for a, b in s.init_spans:
          for m in _IDENT.finditer(s.text, a, b):
            qual, name = m.group(1), m.group(2)
            if name in RESERVED or name in all_funcs:
                continue
            if qual:
                key = (qual.rstrip(":"), name)
            else:
                # unqualified: only decidable when exactly one namespace
                # declares the name, which is the overwhelming majority.
                cands = [k for k in decl_at if k[1] == name]
                if len(cands) != 1:
                    continue
                key = cands[0]
                if key[0] and key[0] not in _enclosing_ns(s, m.start()):
                    continue
            hit = decl_at.get(key)
            if hit is None:
                continue
            di, doff = hit
            if di > s.index:
                findings.append((
                    "order", s.path, s.line(m.start()),
                    f"reads {'::'.join(x for x in key if x)} but "
                    f"{scans[di].path.name}:{scans[di].line(doff)} declares it, and "
                    f"the shim includes that file LATER -- "
                    f"`No matching symbol` disables the whole variant"))
            elif di == s.index and doff > m.start() and not _same_stmt(s, doff, m.start()):
                findings.append((
                    "order", s.path, s.line(m.start()),
                    f"reads {name} at line {s.line(m.start())} but it is declared "
                    f"below, at line {s.line(doff)}"))

    # -- 2: a local read outside the block that declares it ------------------
    for s in scans:
        for fname, fstart, fend, locs in s.bodies:
            if not locs:
                continue
            body = s.text[fstart:fend]
            for m in _IDENT.finditer(body):
                if m.group(1):
                    continue
                name = m.group(2)
                spans = locs.get(name)
                if not spans:
                    continue
                off = fstart + m.start()
                if any(a <= off <= b for a, b in spans):
                    continue
                if name in bare_names or name in all_funcs or name in all_ns:
                    continue
                findings.append((
                    "scope", s.path, s.line(off),
                    f"`{name}` in {fname}() is read outside the block that "
                    f"declares it (line "
                    f"{s.line(min(a for a, _ in spans))}) -- "
                    f"`No matching symbol '{name}'`"))

    dedup, out = set(), []
    for f in findings:
        key = (f[0], f[1], f[2], f[3][:48])
        if key not in dedup:
            dedup.add(key)
            out.append(f)
    return order, out


def _same_stmt(s: FileScan, a: int, b: int) -> bool:
    """A self-referencing initializer (`int i = i` never happens; `for(i=0;i<n`
    does) -- treat a hit on the same line as the declaration as the declaration
    itself."""
    return s.line(a) == s.line(b)


def _enclosing_ns(s: FileScan, off: int) -> set[str]:
    """Namespaces open at `off`, cheaply: every `namespace X {` before it whose
    brace has not closed. Good enough -- files here open one namespace."""
    out, depth = set(), 0
    stack: list[tuple[str, int]] = []
    for m in re.finditer(r"namespace\s+([A-Za-z_][A-Za-z0-9_:]*)\s*\{|[{}]", s.text[:off]):
        tok = m.group(0)
        if tok.startswith("namespace"):
            stack.append((m.group(1), depth))
            depth += 1
        elif tok == "{":
            depth += 1
        else:
            depth -= 1
            while stack and stack[-1][1] >= depth:
                stack.pop()
    for name, _ in stack:
        out.add(name)
        out.update(name.split("::"))
    return out or {""}


def default_root() -> Path:
    repo = Path(__file__).resolve().parent.parent
    return repo / "ai" / "Unstable" / "game-side" / "script" / "standard" / "main.as"


def main() -> int:
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else default_root()
    order, findings = analyse(root)
    print(f"{root.name}: {len(order)} files in include order")
    for kind, path, line, msg in findings:
        print(f"  {kind:6} {path.name}:{line}: {msg}")
    print(f"{len(findings)} finding(s)")
    return 1 if findings else 0


if __name__ == "__main__":
    raise SystemExit(main())
