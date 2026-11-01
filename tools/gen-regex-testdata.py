#!/usr/bin/env python3
"""Generate the regular expression test data in tests/data/regex/cases.txt.

The expected results come from Saxon HE 12, the engine of the KoSIT
validator (Python's re module speaks another dialect), so this script needs
Java and the Saxon jar:

  python tools/gen-regex-testdata.py --java PATH/java.exe --saxon PATH/saxon-he-12.9.jar

The patterns are all patterns of the target schemas and rule sets (XSD
pattern facets of GAEB, matches/replace/tokenize of EN16931, XRechnung,
Peppol BIS, Factur-X) plus constructed edge cases; the inputs are random
strings over an alphabet that fits each pattern, plus fixed ones.

XSD patterns are checked as matches($s, '^(?:pattern)$') in XPath, which is
equivalent for patterns without ^, $, \\$ and hyphens inside character
classes (true for every XSD pattern here): XPath follows the hyphen rules
of XML Schema 1.1, XSD mode those of 1.0 as Xerces, which the unit tests
check separately.

Line format (TAB separated); a field that is not printable ASCII is written
as "hex:" followed by its UTF-8 bytes in hex:
  xsd       pattern  input   true|false|error
  matches   pattern  input   true|false|error
  replace   pattern  input   replacement  result|error
  tokenize  pattern  input   count  token1 ... | error
"unsupported" marks patterns that Saxon accepts but this library rejects
on purpose (back-references, block escapes).

The file is committed; rerun this script only when the set changes.
"""

import argparse
import os
import random
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "tests", "data", "regex")

BS = chr(92)

XSD_PATTERNS = [
    "[a-zA-Z0-9]*", "[0-9]{0,17}", "(_|[0-9]|[A-Z]|[a-z]){1,14}", "(_|[0-9]|[A-Z]|[a-z]){1,1}",
    " {2,2} {9,9}.{69,69}", BS + "d+(" + BS + "." + BS + "d+)*", "[A-Z]{2}[0-9]{2}[A-Z0-9]{1,30}",
    # constructed
    "[a-z-[aeiou]]+", "[^a-z]*", BS + "i" + BS + "c*", "[" + BS + "p{Lu}" + BS + "d]+", BS + "w+",
    "a|ab|abc", "(a|b)*c", "x{2,4}", "[-a]+", "[a-]+", "[+" + BS + "-]?[0-9]+", ".*", BS + "S+",
]

XPATH_PATTERNS = [
    "(^|" + BS + "r?" + BS + "n)#(SKONTO)#TAGE=([0-9]+#PROZENT=[0-9]+" + BS + ".[0-9]{2})(#BASISBETRAG=-?[0-9]+" + BS + ".[0-9]{2})?#$",
    "#(SKONTO|VERZUG)#TAGE=([0-9]+#PROZENT=[0-9]+" + BS + ".[0-9]{2})(#BASISBETRAG=-?[0-9]+" + BS + ".[0-9]{2})?#$",
    ".*([0-9].*){3,}.*",
    "^[^@" + BS + "s]+@([^@." + BS + "s]+" + BS + ".)+[^@." + BS + "s]+$",
    "^([a-zA-Z])([a-zA-Z0-9+.-])+:.*",
    "^[A-Z]{2}[0-9]{2}[a-zA-Z0-9]{0,30}$",
    "^" + BS + "d+$", "^" + BS + "d{8}$", "^" + BS + "d{4}-" + BS + "d{2}-" + BS + "d{2}$", "^" + BS + "s*" + BS + "n",
    "^" + BS + "s*(" + BS + "d{4})(1[0-2]|0[1-9]){1}(3[01]|[12][0-9]|0[1-9]){1}" + BS + "s*$",
    "^" + BS + "s*(" + BS + "d{4})(1[0-2]|0[1-9])(3[01]|[12][0-9]|0[1-9])([01][0-9]|2[0-3])[0-5][0-9]" + BS + "s*$",
    "^(0?[1-9]|[12][0-9]|3[01])[-" + BS + BS + "/ ]?(0?[1-9]|1[0-2])[-" + BS + BS + "/ ]?(19|20)[0-9]{2}",
    "^[0-9]+$", "^[0-9]{10}$", "^[0-9]{7,8}$", "^NL[0-9]{9}B[0-9]{2}$", "^[A-Z0-9]{11,16}$", "^[0-9]{9}MVA$",
    "^[1-9]([0-9]*)",
    "^[a-zA-Z0-9!#" + BS + "$%&\"*+/=?^_`{|}~-]+(" + BS + ".[a-zA-Z0-9!#" + BS + "$%&\"*+/=?^_`{|}~-]+)*@([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?" + BS + ".)+[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$",
    # constructed
    "a|ab", "(a|ab)(c|bcd)", "(a*)*b", "(a|b)*?c", "x*", "", "^", "$", "a{0}", "(?:ab)+", "[" + BS + "s" + BS + "S]",
    BS + "p{Nd}", BS + "P{L}+", BS + "p{IsBasicLatin}", "(a)" + BS + "1", "a{3,2}", "[z-a]", "(", ")", "a**", "[]",
    "[a-[b]", "{", BS + "q", "é+", ".", "[^" + BS + "n]+", "((a)|b)+", "(a)|(b)",
    # hyphens in character classes (XML Schema 1.1 rules in XPath)
    "[a-z-0-9]+", "[" + BS + "d-z]+", "[--z]", "[a-z--[x]]+", "[a--[x]]+", "[" + BS + "w-.]+",
    "[A-Za-z0-9-_]+", "[--]+", "[--[a]]+", "[!--]", "[" + BS + "d--z]", "[a-k-z]+", "[a--]",
    "[-]", "[" + BS + "d--]", "[a-z--]", "[a-z-]", "[" + BS + "d-]", "[--a]", "[a-z---[x]]", "[a---[x]]",
    "[^--]", "[a-z-[-]]", "[--[-]]",
    # escapes that are errors
    BS + "p{Cs}", BS + "p{Is}", BS + "0",
]

# Valid for Saxon, deliberately not supported here: the expected result is
# "unsupported" (ELandrixXmlError with xecUnsupported).
UNSUPPORTED = {BS + "p{IsBasicLatin}", "(a)" + BS + "1"}

REPLACE_CASES = [
    ("([" + BS + "s])", ""), ("([ " + BS + "n" + BS + "r" + BS + "t" + BS + "s])", ""), ("(b)(c)", "[$2$1$0]"),
    ("a", BS + "$x" + BS + BS), ("a", "$"), ("a", BS + "x"), ("a|ab", "X"), ("a{1,2}", "X"),
    ("(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)(k)", "$10-$11-$12"), ("(x)?y", "[$1]"), ("x*", "-"), ("(a)", "$2"),
    ("[0-9]+", "#"), (BS + "s+", " "), ("(a)", "$01"), ("(a)", "$00"),
    ("(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)(k)", "$010|$100|$05"),
]

TOKENIZE_PATTERNS = ["#.+#", "(" + BS + "r?" + BS + "n)", BS + "s", "-", "/", BS + "|", ",", BS + "s+", "x*"]

ALPHABET = list("0123456789abcxyzABCXYZ#=.@-+/:_ ,|") + ["\n", "\r", "\t", "é", "٣", "½",
                                                         "·", "̀", "⁰", "\U0001F600"]


def random_input(rng, pattern):
    n = rng.choice([0, 1, 2, 3, 5, 8, 12, 20, 40, 90])
    chars = ALPHABET
    if "SKONTO" in pattern or "VERZUG" in pattern:
        pieces = ["#SKONTO#", "#VERZUG#", "TAGE=", "14", "#PROZENT=", "2.00", "3.5", "#BASISBETRAG=",
                  "-120.00", "#", "\n", "\r\n", "x"]
        return "".join(rng.choice(pieces) for _ in range(rng.randint(0, 8)))
    return "".join(rng.choice(chars) for _ in range(n))


FIXED_INPUTS = ["", "a", "ab", "abc", "aaa", "b", "c", "12345678", "20261021", "2026-10-21", "DE89370400440532013000",
                "info@landrix.de", "a.b@c.d", "http://x", "+49 30 1234", "NL123456789B01", "123456789MVA",
                "#SKONTO#TAGE=14#PROZENT=2.00#\n", "#SKONTO#TAGE=14#PROZENT=2.00#BASISBETRAG=-120.00#",
                "x\n#SKONTO#TAGE=7#PROZENT=3.00#", "  20261021  ", "202610211230", "31/12/2026", "٣٤",
                "éé", "ABCDEFGHIJKLMNOP"]


def xq_string(s):
    out = []
    for ch in s:
        if ch == '"':
            out.append('""')
        elif ch == "&":
            out.append("&amp;")
        elif ord(ch) < 32 or ord(ch) > 126:
            out.append("&#%d;" % ord(ch))
        else:
            out.append(ch)
    return '"' + "".join(out) + '"'


def field(s):
    if all(32 <= ord(c) <= 126 for c in s) and not s.startswith("hex:"):
        return s
    return "hex:" + s.encode("utf-8").hex().upper()


def build(seed):
    rng = random.Random(seed)
    cases = []  # (kind, pattern, input, extra, saxon expression)
    for p in XSD_PATTERNS:
        inputs = FIXED_INPUTS + [random_input(rng, p) for _ in range(25)]
        for s in inputs:
            expr = ("try { string(matches(%s, %s)) } catch * { 'error' }"
                    % (xq_string(s), xq_string("^(?:" + p + ")$")))
            cases.append(("xsd", p, s, None, expr))
    for p in XPATH_PATTERNS:
        inputs = FIXED_INPUTS + [random_input(rng, p) for _ in range(25)]
        for s in inputs:
            expr = "try { string(matches(%s, %s)) } catch * { 'error' }" % (xq_string(s), xq_string(p))
            cases.append(("matches", p, s, None, expr))
    for p, rep in REPLACE_CASES:
        for s in FIXED_INPUTS + [random_input(rng, p) for _ in range(10)]:
            expr = ("try { replace(%s, %s, %s) } catch * { 'error' }"
                    % (xq_string(s), xq_string(p), xq_string(rep)))
            cases.append(("replace", p, s, rep, expr))
    for p in TOKENIZE_PATTERNS:
        for s in FIXED_INPUTS + [random_input(rng, p) for _ in range(10)]:
            expr = ("try { let $t := tokenize(%s, %s) return string-join((string(count($t)), "
                    "for $x in $t return string-join(for $c in string-to-codepoints($x) return string($c), ' ')), '&#9;') }"
                    " catch * { 'error' }" % (xq_string(s), xq_string(p)))
            cases.append(("tokenize", p, s, None, expr))
    return cases


def run_saxon(cases, java, saxon):
    lines = ["declare option saxon:output 'method=text';", "string-join(("]
    lines.append(",\n".join(c[4] for c in cases))
    lines.append("), '&#10;')")
    with tempfile.NamedTemporaryFile("w", suffix=".xq", delete=False, encoding="utf-8") as f:
        f.write("\n".join(lines))
        query = f.name
    try:
        out = subprocess.run([java, "-cp", saxon, "net.sf.saxon.Query", "-q:" + query],
                             capture_output=True, encoding="utf-8")
    finally:
        os.unlink(query)
    if out.returncode != 0:
        sys.exit("Saxon failed:\n" + out.stderr[-3000:])
    got = out.stdout.split("\n")
    if got and got[-1] == "":
        got.pop()
    return got


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--java", required=True)
    ap.add_argument("--saxon", required=True)
    ap.add_argument("--seed", type=int, default=1)
    args = ap.parse_args()
    cases = build(args.seed)
    # results may contain line breaks (replace); evaluate one per line by
    # encoding the replace results as code points too
    for i, c in enumerate(cases):
        if c[0] == "replace":
            cases[i] = c[:4] + ("try { string-join(for $c in string-to-codepoints(replace(%s, %s, %s)) "
                                "return string($c), ' ') } catch * { 'error' }"
                                % (xq_string(c[2]), xq_string(c[1]), xq_string(c[3])),)
    got = run_saxon(cases, args.java, args.saxon)
    if len(got) != len(cases):
        sys.exit("Saxon returned %d lines for %d cases" % (len(got), len(cases)))
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "cases.txt"), "w", encoding="ascii", newline="\n") as f:
        for (kind, p, s, extra, _), result in zip(cases, got):
            if kind == "replace" and result != "error":
                result = field("".join(chr(int(x)) for x in result.split()) if result else "")
            elif kind == "tokenize" and result != "error":
                parts = result.split("\t")
                result = "\t".join([parts[0]] + [field("".join(chr(int(x)) for x in t.split())) for t in parts[1:]])
            if p in UNSUPPORTED:
                result = "unsupported"
            row = [kind, field(p), field(s)]
            if kind == "replace":
                row.append(field(extra))
            row.append(result)
            f.write("\t".join(row) + "\n")
    print("%d cases written" % len(cases))


if __name__ == "__main__":
    main()
