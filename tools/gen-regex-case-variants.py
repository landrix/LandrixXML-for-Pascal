#!/usr/bin/env python3
"""Generate source/LandrixXmlCaseVariantsData.inc: the case variants that
Saxon HE applies to the regular expression flag i, asked from Saxon itself.

  python tools/gen-regex-case-variants.py --java PATH/java.exe --saxon validator-1.6.3-standalone.jar [--check casevariants.xml]

Candidates: every code point is grouped with the code points that share
the first character of its upper, lower, title or folded case (Python's
Unicode data); for every ordered pair (d, c) of a group Saxon evaluates
matches(c, d, 'iq'), i.e. whether the pattern character d matches the
input character c without regard to case. The table lists, per pattern
character, the other characters it matches. With --check the result is
compared with a copy of Saxon's casevariants.xml (only as a check; the
file is not used for the table).

The jar is the KoSIT validator, which contains Saxon HE.
"""

import argparse
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "source", "LandrixXmlCaseVariantsData.inc")


def xml_char(cp):
    return cp in (9, 10, 13) or 0x20 <= cp <= 0xD7FF or 0xE000 <= cp <= 0xFFFD or 0x10000 <= cp <= 0x10FFFF


def candidate_groups():
    parent = {}

    def find(x):
        while parent.get(x, x) != x:
            x = parent[x]
        return x

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[max(ra, rb)] = min(ra, rb)

    for cp in range(0x110000):
        if not xml_char(cp):
            continue
        c = chr(cp)
        for mapped in (c.upper(), c.lower(), c.title(), c.casefold()):
            if mapped and mapped != c and xml_char(ord(mapped[0])):
                union(cp, ord(mapped[0]))
    groups = {}
    for cp in parent:
        groups.setdefault(find(cp), set()).add(cp)
    for g in groups.values():
        g.add(find(next(iter(g))))
    return [sorted(g) for g in groups.values() if len(g) > 1]


QUERY = """let $pairs := (%s)
return string-join(
  for $i in 1 to count($pairs) idiv 2
  let $d := $pairs[2 * $i - 1]
  let $c := $pairs[2 * $i]
  return if (matches(codepoints-to-string($c), codepoints-to-string($d), 'iq'))
    then concat($d, ' ', $c) else (),
  '&#10;')"""


def wrap(items):
    lines = []
    line = "   "
    for i, it in enumerate(items):
        piece = " " + it + ("," if i < len(items) - 1 else "")
        if len(line) + len(piece) > 100:
            lines.append(line)
            line = "   "
        line += piece
    lines.append(line)
    return "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--java", required=True)
    ap.add_argument("--saxon", required=True)
    ap.add_argument("--check")
    args = ap.parse_args()
    pairs = []
    for g in candidate_groups():
        for d in g:
            for c in g:
                if c != d:
                    pairs += [d, c]
    with tempfile.TemporaryDirectory() as tmp:
        q = os.path.join(tmp, "variants.xq")
        with open(q, "w", encoding="ascii") as f:
            f.write(QUERY % ", ".join(str(p) for p in pairs))
        out = subprocess.run([args.java, "-cp", args.saxon, "net.sf.saxon.Query", "-q:" + q, "!method=text"],
                             check=True, capture_output=True, encoding="ascii").stdout
        ver = subprocess.run([args.java, "-cp", args.saxon, "net.sf.saxon.Query", "-qs:1", "-t"],
                             capture_output=True, encoding="utf-8", errors="replace").stderr
    version = "Saxon"
    for line in ver.splitlines():
        if line.startswith("Saxon"):
            version = line.split(" from ")[0].strip()
            break
    variants = {}
    for line in out.splitlines():
        if line.strip():
            d, c = [int(x) for x in line.split()]
            variants.setdefault(d, []).append(c)
    if args.check:
        with open(args.check, encoding="utf-8") as f:
            text = f.read()
        theirs = {}
        for n, v in re.findall(r'<c n="([0-9A-F]+)" v="([0-9A-F,]+)"/>', text):
            theirs[int(n, 16)] = sorted(int(x, 16) for x in v.split(","))
        ours = {k: sorted(v) for k, v in variants.items()}
        diff = sorted(set(theirs) ^ set(ours)) + sorted(k for k in set(theirs) & set(ours) if theirs[k] != ours[k])
        print("check: %d keys in the file, %d here, %d differences%s" % (
            len(theirs), len(ours), len(diff), (": " + " ".join("U+%04X" % k for k in diff[:20])) if diff else ""))
    keys = sorted(variants)
    pool, starts = [], []
    for k in keys:
        starts.append(len(pool))
        pool += sorted(variants[k])
    starts.append(len(pool))
    with open(OUT, "w", encoding="ascii", newline="\r\n") as f:
        f.write("{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.\n\n"
                "  Copyright (c) 2026 Landrix Software\n"
                "  Licensed under the MIT License. See the LICENSE file in the project root\n"
                "  or https://opensource.org/licenses/MIT for the full license text.\n\n"
                "  GENERATED by tools/gen-regex-case-variants.py from the behaviour of\n"
                "  %s (the regular expression flag i); do not edit.\n"
                "  The pattern character CaseVariantKeys[I] also matches the characters\n"
                "  CaseVariantPool[CaseVariantStarts[I] .. CaseVariantStarts[I + 1] - 1]. }\n\n" % version)
        f.write("const\n")
        f.write("  CaseVariantCount = %d;\n" % len(keys))
        f.write("  CaseVariantKeys: array[0..CaseVariantCount - 1] of Integer = (\n")
        f.write(wrap(["$%X" % k for k in keys]))
        f.write("  );\n")
        f.write("  CaseVariantStarts: array[0..CaseVariantCount] of Integer = (\n")
        f.write(wrap([str(s) for s in starts]))
        f.write("  );\n")
        f.write("  CaseVariantPool: array[0..%d] of Integer = (\n" % (len(pool) - 1))
        f.write(wrap(["$%X" % p for p in pool]))
        f.write("  );\n")
    print("%s: %d characters, %d variants (%s)" % (OUT, len(keys), len(pool), version))


if __name__ == "__main__":
    main()
