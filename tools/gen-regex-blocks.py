#!/usr/bin/env python3
"""Generate source/LandrixXmlBlockData.inc: the Unicode block escapes
\\p{IsX} of the regular expressions, as Saxon HE (XPath modes) and the
Java runtime's Xerces (XML Schema mode) accept them, asked from the two
engines themselves.

  python tools/gen-regex-blocks.py --java PATH/java.exe --javac PATH/javac.exe
      --saxon validator-1.6.3-standalone.jar --blocks DIR [--check unicodeBlocks.xml]

DIR holds the Unicode files Blocks.txt of the versions 3.1 to 6.0 (any
file names; Saxon's table ends with Unicode 6.0, Xerces' with 3.1):

  https://www.unicode.org/Public/3.1-Update/Blocks-4.txt
  https://www.unicode.org/Public/3.2-Update/Blocks-3.2.0.txt
  https://www.unicode.org/Public/4.0-Update/Blocks-4.0.0.txt
  https://www.unicode.org/Public/4.0-Update1/Blocks-4.0.1.txt
  https://www.unicode.org/Public/<v>/ucd/Blocks.txt for 4.1.0 5.0.0 5.1.0 5.2.0 6.0.0

They only supply candidates: every block name (spaces removed, "Is"
prepended, and as written, which Xerces accepts too) and every range
boundary of any version. For each engine the
script asks which candidate names are valid and, for every valid name,
which intervals between the boundaries it matches; an interval whose
first and last character disagree is split until every interval is
uniform. Surrogates and the other characters an engine cannot be asked
about (Saxon: non-XML characters) are left out; they never occur in the
input. With --check the XPath table is compared (on XML characters) with a copy of Saxon's
unicodeBlocks.xml (only as a check; the file is not used for the table).
"""

import argparse
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "source", "LandrixXmlBlockData.inc")
BS = chr(92)


def xml_char(cp):
    return cp in (9, 10, 13) or 0x20 <= cp <= 0xD7FF or 0xE000 <= cp <= 0xFFFD or 0x10000 <= cp <= 0x10FFFF


def read_candidates(folder):
    names, bounds = set(), {0, 0x110000, 0xD800, 0xE000}
    for fn in sorted(os.listdir(folder)):
        with open(os.path.join(folder, fn), encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.split("#")[0].strip()
                m = re.match(r"([0-9A-F]+)\.\.([0-9A-F]+)\s*;\s*(.+)$", line)
                if m:
                    lo, hi = int(m.group(1), 16), int(m.group(2), 16)
                    names.add("Is" + m.group(3).strip().replace(" ", ""))
                    # Xerces also takes the plain name, with its spaces
                    names.add(m.group(3).strip())
                    bounds.update((lo, hi + 1))
    return sorted(names), sorted(bounds)


def representatives(lo, hi, valid):
    """The first and last character of [lo, hi] the engine can be asked about."""
    a = lo
    while a <= hi and not valid(a):
        a += 1
    b = hi
    while b >= a and not valid(b):
        b -= 1
    return (a, b) if a <= hi else None


class Saxon:
    def __init__(self, java, jar):
        self.java, self.jar = java, jar
        self.valid_char = xml_char

    def ask(self, names, points):
        query = ("declare variable $names := (%s);\n"
                 "declare variable $points := (%s);\n"
                 "string-join(for $n in $names return\n"
                 "  try { let $m := for $p in $points return\n"
                 "          if (matches(codepoints-to-string($p), concat('^" + BS + "p{', $n, '}$'))) then $p else ()\n"
                 "        return concat($n, ' ', string-join(for $p in $m return string($p), ' ')) }\n"
                 "  catch * { concat('!', $n) }, '&#10;')") % (
            ", ".join("'%s'" % n for n in names), ", ".join(str(p) for p in points))
        with tempfile.TemporaryDirectory() as tmp:
            q = os.path.join(tmp, "blocks.xq")
            with open(q, "w", encoding="ascii") as f:
                f.write(query)
            out = subprocess.run([self.java, "-cp", self.jar, "net.sf.saxon.Query", "-q:" + q, "!method=text"],
                                 check=True, capture_output=True, encoding="ascii").stdout
        return parse_answers(out)


class Xerces:
    EXPORT = "java.xml/com.sun.org.apache.xerces.internal.impl.xpath.regex=ALL-UNNAMED"

    def __init__(self, java, javac, tmp):
        self.java = java
        self.cls = os.path.join(tmp, "cls")
        subprocess.run([javac, "--add-exports", self.EXPORT, "-d", self.cls,
                        os.path.join(ROOT, "tools", "XercesRegexOracle.java")], check=True)
        self.valid_char = lambda cp: not (0xD800 <= cp <= 0xDFFF)

    def ask(self, names, points):
        lines = []
        for n in names:
            lines.append("valid\t" + BS + "p{" + n + "}")
            for p in points:
                lines.append("match\t" + BS + "p{" + n + "}\t" + str(p))
        out = subprocess.run([self.java, "--add-exports", self.EXPORT, "-cp", self.cls, "XercesRegexOracle"],
                             input="\n".join(lines) + "\n", check=True, capture_output=True,
                             encoding="utf-8").stdout.split("\n")
        result, i = {}, 0
        for n in names:
            valid = out[i] == "1"
            i += 1
            matched = set()
            for p in points:
                if out[i] == "1":
                    matched.add(p)
                i += 1
            result[n] = matched if valid else None
        return result


def parse_answers(out):
    result = {}
    for line in out.splitlines():
        if not line:
            continue
        if line.startswith("!"):
            result[line[1:]] = None
        else:
            parts = line.split()
            result[parts[0]] = set(int(p) for p in parts[1:])
    return result


def table(engine, names, bounds):
    """name -> sorted list of (lo, hi) for the valid names."""
    intervals = [(bounds[i], bounds[i + 1] - 1) for i in range(len(bounds) - 1)
                 if not (bounds[i] >= 0xD800 and bounds[i + 1] - 1 <= 0xDFFF)]
    valid = None
    while True:
        reps = {}
        for iv in intervals:
            r = representatives(iv[0], iv[1], engine.valid_char)
            if r:
                reps[iv] = r
        points = sorted(set(p for r in reps.values() for p in r))
        answers = engine.ask(names if valid is None else valid, points)
        if valid is None:
            valid = [n for n in names if answers.get(n) is not None]
        split = []
        for iv, (a, b) in reps.items():
            if any((a in answers[n]) != (b in answers[n]) for n in valid):
                split.append(iv)
        if not split:
            break
        for iv in split:
            mid = (iv[0] + iv[1]) // 2
            intervals.remove(iv)
            intervals += [(iv[0], mid), (mid + 1, iv[1])]
        intervals.sort()
        print("  %d intervals split" % len(split))
    result = {}
    for n in valid:
        ranges = []
        for iv in sorted(reps):
            if reps[iv][0] in answers[n]:
                if ranges and ranges[-1][1] + 1 == iv[0]:
                    ranges[-1] = (ranges[-1][0], iv[1])
                else:
                    ranges.append(iv)
        result[n] = ranges
    return result


def pascal(prefix, tab):
    names = sorted(tab)
    los, his, first = [], [], []
    for n in names:
        first.append(len(los))
        for lo, hi in tab[n]:
            los.append(lo)
            his.append(hi)
    first.append(len(los))
    out = ["  %sBlockCount = %d;" % (prefix, len(names)),
           "  %sBlockNames: array[0..%sBlockCount - 1] of string = (" % (prefix, prefix)]
    out += wrap(["'%s'" % n for n in names])
    out += ["  );", "  { the ranges of block I: %sBlockLo/Hi[%sBlockFirst[I] .. %sBlockFirst[I + 1] - 1] }"
            % (prefix, prefix, prefix),
            "  %sBlockFirst: array[0..%sBlockCount] of Integer = (" % (prefix, prefix)]
    out += wrap([str(x) for x in first])
    out += ["  );", "  %sBlockLo: array[0..%d] of Integer = (" % (prefix, len(los) - 1)]
    out += wrap(["$%X" % x for x in los])
    out += ["  );", "  %sBlockHi: array[0..%d] of Integer = (" % (prefix, len(his) - 1)]
    out += wrap(["$%X" % x for x in his])
    out += ["  );"]
    return out


def wrap(items):
    lines, line = [], "   "
    for i, it in enumerate(items):
        piece = " " + it + ("," if i < len(items) - 1 else "")
        if len(line) + len(piece) > 100:
            lines.append(line)
            line = "   "
        line += piece
    lines.append(line)
    return lines


def check(tab, path):
    with open(path, encoding="utf-8") as f:
        text = f.read()
    theirs = {}
    for name, body in re.findall(r'<block name="([^"]*)"[^>]*>(.*?)</block>', text, re.S):
        ranges = [(int(a, 16), int(b, 16)) for a, b in re.findall(r'from="#x([0-9A-F]+)" to="#x([0-9A-F]+)"', body)]
        cps = set()
        for a, b in ranges:
            cps.update(c for c in range(a, b + 1) if xml_char(c))
        theirs["Is" + name.replace(" ", "")] = cps
    ours = {}
    for n, ranges in tab.items():
        cps = set()
        for a, b in ranges:
            cps.update(c for c in range(a, b + 1) if xml_char(c))
        ours[n] = cps
    diff = sorted(n for n in set(theirs) | set(ours) if theirs.get(n) != ours.get(n))
    print("check: %d blocks in the file, %d here, %d differ%s" % (len(theirs), len(ours), len(diff),
                                                                (": " + " ".join(diff[:10])) if diff else ""))


def version_of(java, jar):
    ver = subprocess.run([java, "-cp", jar, "net.sf.saxon.Query", "-qs:1", "-t"],
                         capture_output=True, encoding="utf-8", errors="replace").stderr
    for line in ver.splitlines():
        if line.startswith("Saxon"):
            return line.split(" from ")[0].strip()
    return "Saxon"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--java", required=True)
    ap.add_argument("--javac", required=True)
    ap.add_argument("--saxon", required=True)
    ap.add_argument("--blocks", required=True)
    ap.add_argument("--check")
    args = ap.parse_args()
    names, bounds = read_candidates(args.blocks)
    print("%d candidate names, %d boundaries" % (len(names), len(bounds)))
    print("Saxon:")
    xpath = table(Saxon(args.java, args.saxon), names, bounds)
    with tempfile.TemporaryDirectory() as tmp:
        print("Xerces:")
        xsd = table(Xerces(args.java, args.javac, tmp), names, bounds)
    if args.check:
        check(xpath, args.check)
    jver = subprocess.run([args.java, "-version"], capture_output=True, encoding="utf-8",
                          errors="replace").stderr.splitlines()[0]
    lines = ["{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.", "",
             "  Copyright (c) 2026 Landrix Software",
             "  Licensed under the MIT License. See the LICENSE file in the project root",
             "  or https://opensource.org/licenses/MIT for the full license text.", "",
             "  GENERATED by tools/gen-regex-blocks.py - do not edit.", "",
             "  The block escapes of the regular expressions (backslash, p or P, Is",
             "  and a block name in braces): XPath as %s accepts them," % version_of(args.java, args.saxon),
             "  XML Schema as the Xerces of the Java runtime",
             "  (%s)." % jver.strip().replace('"', ''),
             "  Names sorted (ordinal); surrogates are left out, and Saxon is not asked",
             "  about non-XML characters. Block names and candidate boundaries from",
             "  the Unicode files Blocks.txt 3.1 to 6.0, Copyright (c) 1991-2010",
             "  Unicode, Inc., distributed under the Unicode terms of use",
             "  (https://www.unicode.org/copyright.html). }", "", "const"]
    lines += pascal("XPath", xpath)
    lines += pascal("Xsd", xsd)
    with open(OUT, "w", encoding="ascii", newline="\r\n") as f:
        f.write("\n".join(lines) + "\n")
    print("%s: %d XPath blocks, %d XSD blocks" % (OUT, len(xpath), len(xsd)))


if __name__ == "__main__":
    main()
