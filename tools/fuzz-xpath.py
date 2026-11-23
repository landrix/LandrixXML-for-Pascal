#!/usr/bin/env python3
"""Differential XPath fuzzer: the evaluator against Saxon HE.

Generates random, valid XPath expressions from the constructs the Saxon
profile supports (numbers, strings, booleans, sequences, paths, the common
functions, casts, for/some/every/if, let, "!" and "||"), evaluates them on a
small fixed document with the QT3 helper (tests/LandrixXmlQt3.dpr, profile
saxon) and with Saxon HE (tools/XPathOracle.java, the Saxon classes of the
KoSIT validator jar, checked against tests/data/saxon-oracle.txt), and
compares the results: the items (type and string value; nodes by kind,
name and string value) or the error code.

  python tools/fuzz-xpath.py --exe build/fpc322-win64/LandrixXmlQt3.exe
      --java D:/Bin/jdk-21.0.6+7/bin/java.exe
      --jar .../validator-1.6.3-standalone.jar [--count 5000] [--seed N]

Build the helper first (./tools/build.ps1 fpc322-win64 -Program
tests/LandrixXmlQt3.dpr -NoRun). javac next to --java compiles the oracle
into build/fuzz-xpath/classes. Only the Saxon profile: the oracle runs
XPath 3.1.

Each difference gets a class: crash (the helper died, gave no result or
raised another exception than an XPath error), value (both sides have a
value), ours-error and saxon-error (only one side raises an error: XPath
lets an implementation skip an error whose value it does not need, and
Saxon raises type errors from static types; a spurious error of the
evaluator would show as ours-error), code (both raise, other codes: which
error comes first), saxon-internal (Saxon failed with a Java exception:
the expression is not compared). tests/data/xpath/fuzz-known.txt lists
known differences: "CATEGORY REGEX", optionally a tab and a regex for the
results "OURS || SAXON", "=same items" (the same items in another order)
or "=types A B" (the same items, but some of type A here and B in Saxon
with the same value). Every difference goes to build/fuzz-xpath/findings.txt (class or
known category, expression, both results). The run fails (exit code 1) on
a crash or a value difference not in the list, when more than 1 % of the
expressions are ours-error or saxon-internal, when fewer than 97 % are
equal, or when the helper ends with another exit code than 0; code and
saxon-error are only listed.
"""

import argparse
import os
import random
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import saxonjar  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = os.path.join(ROOT, "build", "fuzz-xpath")
KNOWN = os.path.join(ROOT, "tests", "data", "xpath", "fuzz-known.txt")

DOCUMENT = (
    '<r xmlns:p="urn:p" id="r1">'
    '<a n="1" s="x y">10</a>'
    '<a n="2">-2.5</a>'
    '<a n="3" s="">abc</a>'
    '<b>text <c>in</c> tail</b>'
    '<p:d k="3" p:k="4"/>'
    '<!--note--><?pi data?>'
    '<e/>'
    '<f>2024-01-31</f>'
    '<g>  white  space  </g>'
    '</r>')

ESC_RE = re.compile(re.escape(chr(92)) + "x([0-9A-Fa-f]{2})")


def esc(s, spaces=False):
    out = []
    for ch in s:
        if ord(ch) < 32 or ch == chr(92) or (spaces and ch == " "):
            out.append(chr(92) + "x%02X" % ord(ch))
        else:
            out.append(ch)
    return "".join(out)


def unesc(s):
    return ESC_RE.sub(lambda m: chr(int(m.group(1), 16)), s)


# --- the generator ------------------------------------------------------------

class Gen:
    """Random expressions of a wanted kind: num, int, str, bool, seq (atomic
    values), nodes. Depth bounds the nesting; variables in scope are kept
    with their kind."""

    def __init__(self, rnd):
        self.r = rnd
        self.vars = []
        self.next_var = 0

    def pick(self, seq):
        return self.r.choice(seq)

    def position(self, whole=False, finite=False):
        """A position or length for substring() and subsequence(): small
        values only (Saxon converts a large one to a Java int, which wraps;
        see the end of tests/data/xpath/fuzz-known.txt); whole: no fraction
        (the start of substring(), where Saxon fails on one); finite: no
        infinity (the length of substring(), where Saxon fails on it)."""
        pool = ["-1", "0", "1", "2", "3", "1e1", "-0e0", "xs:double('NaN')", "count(//a)",
                "string-length('abc')", "number(//a[1])", "@n", "round(2.5)"]
        if not whole:
            pool += ["-0.5", "0.5", "1.5", "2.5", "xs:float(1.5)"]
        if not finite:
            pool += ["xs:double('INF')", "-xs:double('INF')"]
        return self.pick(pool)

    def var_of(self, kind):
        vs = [n for n, k in self.vars if k == kind]
        return "$" + self.pick(vs) if vs else None

    def gen(self, kind, depth):
        if depth <= 0 or self.r.random() < 0.25:
            return self.leaf(kind)
        return getattr(self, "g_" + kind)(depth - 1)

    def leaf(self, kind):
        v = self.var_of(kind)
        if v and self.r.random() < 0.4:
            return v
        if kind == "int":
            return self.pick(["0", "1", "2", "3", "-1", "7", "10", "100", "12345678901",
                              "count(//a)", "string-length('abc')"])
        if kind == "num":
            return self.pick(["0", "1", "-3", "2.5", "-0.5", "1e3", "1.5e-2", "0.1", "3.0", "xs:double('NaN')",
                              "xs:double('INF')", "-0e0", "xs:float(1.5)", "number(//a[1])", "@n", "sum(//a/@n)"])
        if kind == "str":
            return self.pick(["''", "'a'", "'abc'", "'Hello World'", "' x  y '", "'10'", "'-2.5'", "'2024-01-31'",
                              "string(//a[1])", "string(/r/b)", "name(/*)", "'&amp;'", "'\u00e4\u00df'",
                              "'\U0001F600x'", "string(//@s)"])
        if kind == "bool":
            return self.pick(["true()", "false()", "exists(//a)", "empty(//z)", "boolean(//e)"])
        if kind == "seq":
            return self.pick(["()", "(1, 2, 3)", "('a', 'b', 'a')", "(1, 'a', 2.5)", "1 to 5", "//a/@n",
                              "data(//a)", "(3, 1, 2)", "(1.5, 2, 1e0)", "tokenize('a b c', ' ')"])
        if kind == "nodes":
            return self.pick(["//a", "/r/*", "//@*", "//text()", "/r/node()", "//b//node()", "/r", "/",
                              "//*", "//a[2]", "/r/a/@n", "//comment()", "//processing-instruction()",
                              "//c", "//*[@k]", "/r/e"])
        raise ValueError(kind)

    def bind(self, kind):
        name = "v%d" % self.next_var
        self.next_var += 1
        self.vars.append((name, kind))
        return name

    def unbind(self):
        self.vars.pop()

    def scoped(self, kind, depth, body_kind):
        """for/let/some/every: a binding of kind and a body of body_kind."""
        src = self.gen("seq" if kind != "nodes" else "nodes", depth)
        name = self.bind("num" if kind == "num" else kind)
        try:
            body = self.gen(body_kind, depth)
        finally:
            self.unbind()
        return name, src, body

    def g_int(self, d):
        c = self.r.randrange(9)
        a, b = self.gen("int", d), self.gen("int", d)
        if c == 0:
            return "(%s %s %s)" % (a, self.pick(["+", "-", "*"]), b)
        if c == 1:
            return "(%s %s %s)" % (a, self.pick(["idiv", "mod"]), b)
        if c == 2:
            return "count(%s)" % self.gen(self.pick(["seq", "nodes"]), d)
        if c == 3:
            return "string-length(%s)" % self.gen("str", d)
        if c == 4:
            return "xs:integer(%s)" % self.gen(self.pick(["num", "str", "int"]), d)
        if c == 5:
            return "-%s" % a
        if c == 6:
            return "abs(%s)" % a
        if c == 7:
            return "(index-of(%s, %s)[1], 0)[1]" % (self.gen("seq", d), self.gen("int", d))
        return "%s(%s)" % (self.pick(["floor", "ceiling", "round"]), a)

    def g_num(self, d):
        c = self.r.randrange(12)
        a, b = self.gen("num", d), self.gen(self.pick(["num", "int"]), d)
        if c == 0:
            return "(%s %s %s)" % (a, self.pick(["+", "-", "*", "div"]), b)
        if c == 1:
            return "(%s mod %s)" % (a, b)
        if c == 2:
            return "%s(%s)" % (self.pick(["round", "floor", "ceiling", "abs"]), a)
        if c == 3:
            return "round-half-to-even(%s, %s)" % (a, self.pick(["0", "1", "2", "-1"]))
        if c == 4:
            return "number(%s)" % self.gen(self.pick(["str", "nodes", "int"]), d)
        if c == 5:
            return "%s(%s)" % (self.pick(["sum", "avg", "max", "min"]),
                               self.pick(["(1, 2.5, 3)", "(1e0, 2)", "//a/@n", "()", "(xs:float(1), 2)",
                                          "for $x in 1 to 3 return $x * 1.5"]))
        if c == 6:
            return "xs:%s(%s)" % (self.pick(["decimal", "double", "float"]),
                                  self.gen(self.pick(["num", "int", "str"]), d))
        if c == 7:
            return "-%s" % a
        if c == 8:
            return "round(%s, %s)" % (a, self.pick(["0", "1", "2", "-1"]))
        if c == 9:
            return "(if (%s) then %s else %s)" % (self.gen("bool", d), a, b)
        if c == 10:
            value = self.gen("num", d)
            name = self.bind("num")
            try:
                body = self.gen("num", d)
            finally:
                self.unbind()
            return "(let $%s := %s return %s)" % (name, value, body)
        return self.gen("int", d)

    def g_str(self, d):
        c = self.r.randrange(16)
        a = self.gen("str", d)
        if c == 0:
            return "concat(%s, %s)" % (a, self.gen(self.pick(["str", "num", "int"]), d))
        if c == 1:
            return "substring(%s, %s)" % (a, self.position(True, True))
        if c == 2:
            return "substring(%s, %s, %s)" % (a, self.position(True, True), self.position(False, True))
        if c == 3:
            return "%s(%s)" % (self.pick(["upper-case", "lower-case", "normalize-space", "string"]), a)
        if c == 4:
            return "translate(%s, %s, %s)" % (a, self.pick(["'abc'", "'a '", "''"]), self.pick(["'ABC'", "'x'", "''"]))
        if c == 5:
            return "string-join(%s, %s)" % (self.gen("seq", d), self.pick(["''", "', '", "'-'"]))
        if c == 6:
            return "%s(%s, %s)" % (self.pick(["substring-before", "substring-after"]), a, self.gen("str", d))
        if c == 7:
            return "replace(%s, %s, %s)" % (a, self.pick(["'a'", "'[a-c]+'", "'\\s+'", "'(b)(c)'", "'^'", "'.$'"]),
                                            self.pick(["''", "'X'", "'$1'", "'[$0]'"]))
        if c == 8:
            return "string(%s)" % self.gen(self.pick(["num", "int", "bool"]), d)
        if c == 9:
            return "%s(%s)" % (self.pick(["name", "local-name", "namespace-uri", "string"]),
                               "(" + self.gen("nodes", d) + ")[1]")
        if c == 10:
            return "(%s || %s)" % (a, self.gen(self.pick(["str", "int"]), d))
        if c == 11:
            return "codepoints-to-string(%s)" % self.pick(["(65, 66)", "()", "string-to-codepoints('ab')",
                                                          "(128512, 97)"])
        if c == 12:
            return "xs:string(%s)" % self.gen(self.pick(["num", "int", "bool", "str"]), d)
        if c == 13:
            return "(if (%s) then %s else %s)" % (self.gen("bool", d), a, self.gen("str", d))
        if c == 14:
            return "normalize-unicode(%s)" % a
        return "string((%s)[1])" % self.gen("seq", d)

    def g_bool(self, d):
        c = self.r.randrange(14)
        if c == 0:
            k = self.pick(["num", "int", "str"])
            return "(%s %s %s)" % (self.gen(k, d), self.pick(["=", "!=", "<", "<=", ">", ">="]), self.gen(k, d))
        if c == 1:
            k = self.pick(["num", "int", "str"])
            return "(%s %s %s)" % (self.gen(k, d), self.pick(["eq", "ne", "lt", "le", "gt", "ge"]), self.gen(k, d))
        if c == 2:
            return "(%s %s %s)" % (self.gen("bool", d), self.pick(["and", "or"]), self.gen("bool", d))
        if c == 3:
            return "not(%s)" % self.gen("bool", d)
        if c == 4:
            return "%s(%s, %s)" % (self.pick(["contains", "starts-with", "ends-with"]), self.gen("str", d),
                                   self.gen("str", d))
        if c == 5:
            return "matches(%s, %s)" % (self.gen("str", d), self.pick(["'a'", "'^\\d+$'", "'[a-z]'", "'b.c'",
                                                                        "'(?:x)?'"]))
        if c == 6:
            return "%s(%s)" % (self.pick(["empty", "exists", "boolean"]), self.gen(self.pick(["seq", "nodes"]), d))
        if c == 7:
            return "(%s instance of %s)" % (self.gen(self.pick(["num", "int", "str", "seq"]), d),
                                            self.pick(["xs:integer", "xs:decimal", "xs:double", "xs:string",
                                                       "xs:anyAtomicType*", "item()+", "xs:integer?",
                                                       "node()*", "empty-sequence()"]))
        if c == 8:
            return "(%s castable as %s)" % (self.gen(self.pick(["str", "num", "int"]), d),
                                            self.pick(["xs:integer", "xs:decimal", "xs:double", "xs:date",
                                                       "xs:boolean", "xs:string"]))
        if c == 9:
            name, src, body = self.scoped("seq", d, "bool")
            return "(%s $%s in %s satisfies %s)" % (self.pick(["some", "every"]), name, src, body)
        if c == 10:
            return "(%s = %s)" % (self.gen(self.pick(["seq", "nodes"]), d), self.gen(self.pick(["seq", "str", "int"]), d))
        if c == 11:
            return "deep-equal(%s, %s)" % (self.gen("seq", d), self.gen("seq", d))
        if c == 12:
            return "((%s)[1] %s (%s)[1])" % (self.gen("nodes", d), self.pick(["is", "<<", ">>"]),
                                         self.gen("nodes", d))
        return "boolean(%s)" % self.gen(self.pick(["str", "num", "int"]), d)

    def g_seq(self, d):
        c = self.r.randrange(13)
        if c == 0:
            return "(%s, %s)" % (self.gen(self.pick(["num", "int", "str"]), d), self.gen(self.pick(["seq", "int"]), d))
        if c == 1:
            return "(%s to %s)" % (self.pick(["1", "0", "-2", "3"]), self.pick(["4", "1", "0", "6"]))
        if c == 2:
            return "%s(%s)" % (self.pick(["reverse", "distinct-values", "data"]), self.gen("seq", d))
        if c == 3:
            return "subsequence(%s, %s, %s)" % (self.gen("seq", d), self.position(), self.position())
        if c == 4:
            name, src, body = self.scoped("seq", d, self.pick(["num", "str", "int"]))
            return "(for $%s in %s return %s)" % (name, src, body)
        if c == 5:
            return "(%s)[%s]" % (self.gen("seq", d), self.pick(["1", "last()", "position() > 1", ". > 1",
                                                                 "position() mod 2 = 0", "2.0"]))
        if c == 6:
            return "tokenize(%s, %s)" % (self.gen("str", d), self.pick(["' '", "','", "'\\s+'", "'a'"]))
        if c == 7:
            return "remove(%s, %s)" % (self.gen("seq", d), self.pick(["-1", "0", "1", "2", "3", "5", "count(//a)"]))
        if c == 8:
            return "insert-before(%s, %s, %s)" % (self.gen("seq", d), self.pick(["-1", "0", "1", "2", "3", "5", "count(//a)"]), self.gen("str", d))
        if c == 9:
            return "(%s ! %s)" % (self.gen("seq", d), self.pick(["string(.)", ". * 2", "string-length(string(.))",
                                                                "position()"]))
        if c == 10:
            return "index-of(%s, %s)" % (self.gen("seq", d), self.gen(self.pick(["int", "str"]), d))
        if c == 11:
            return "(if (%s) then %s else %s)" % (self.gen("bool", d), self.gen("seq", d), self.gen("seq", d))
        return "string-to-codepoints(%s)" % self.gen("str", d)

    def g_nodes(self, d):
        c = self.r.randrange(10)
        a = self.gen("nodes", d)
        if c == 0:
            return "(%s %s %s)" % (a, self.pick(["|", "union", "intersect", "except"]), self.gen("nodes", d))
        if c == 1:
            return "(%s)[%s]" % (a, self.pick(["1", "last()", "position() = 2", "@n", "text()", "not(*)",
                                               "@n > 1", "position() < 3"]))
        if c == 2:
            return "(%s)/%s" % (a, self.pick(["*", "@*", "node()", "..", "text()", "ancestor::*",
                                              "following-sibling::*[1]", "preceding-sibling::node()",
                                              "descendant-or-self::*", "self::a", "ancestor-or-self::node()"]))
        if c == 3:
            return "//a[%s]" % self.gen("bool", d)
        if c == 4:
            return "/r/*[%s]" % self.pick(["position() = last()", "@n = 2", "self::b or self::e", "string() = ''",
                                          "@*", "number(.) > 0"])
        if c == 5:
            name, src, body = self.scoped("nodes", d, "nodes")
            return "(for $%s in %s return $%s)" % (name, src, name)
        if c == 6:
            return "(%s)[%s]" % (a, self.gen("int", d))
        if c == 7:
            return "root((%s)[1])" % a
        if c == 8:
            return "(if (%s) then %s else %s)" % (self.gen("bool", d), a, self.gen("nodes", d))
        return a


def expression(rnd):
    g = Gen(rnd)
    kind = rnd.choice(["num", "int", "str", "bool", "seq", "nodes", "num", "str", "bool"])
    return g.gen(kind, rnd.choice([1, 2, 3, 3, 4]))


# --- running both sides -------------------------------------------------------

def run_ours(exe, exprs, doc):
    """The helper's result lines per expression ("count N" first, or "error
    CODE ..."/"exception ..."), ["crash"] for a case that did not end, and
    the exit codes of the helper runs that did not crash."""
    job = os.path.join(WORK, "job.txt")
    res = os.path.join(WORK, "ours.txt")
    lines = []
    for i, e in enumerate(exprs):
        lines += ["case c%d" % i, "source " + esc(doc), "profile saxon", "expr " + esc(e), "run"]
    with open(job, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    results = [None] * len(exprs)
    codes = []
    first = 0
    while first < len(exprs):
        # never read the results of an earlier run
        if os.path.exists(res):
            os.remove(res)
        code = None
        try:
            code = subprocess.run([exe, job, res, str(first)], stdout=subprocess.DEVNULL,
                                  stderr=subprocess.DEVNULL, timeout=300).returncode
        except subprocess.TimeoutExpired:
            pass
        cur, buf = None, []
        if os.path.exists(res):
            with open(res, encoding="utf-8", errors="replace") as f:
                for line in f.read().split("\n"):
                    if line.startswith("case "):
                        cur = int(line[6:])
                        buf = []
                    elif line == "done" and cur is not None:
                        # a case without its value or error (a setup error)
                        # is no result
                        ok = buf and (buf[0].startswith(("count ", "error ", "exception ")))
                        results[cur] = buf if ok else ["crash"]
                        cur = None
                    elif cur is not None and line.startswith("R "):
                        buf.append(line[2:])
                    elif cur is not None and line.startswith("setup error"):
                        buf.append("exception setup " + line)
        # a crash: the case after the last one done failed
        nxt = first
        while nxt < len(exprs) and results[nxt] is not None:
            nxt += 1
        if nxt >= len(exprs):
            codes.append(code)
            break
        results[nxt] = ["crash"]
        first = nxt + 1
    return results, codes


def norm_ours(lines):
    if lines == ["crash"]:
        return ["crash"]
    out = []
    for l in lines:
        if l.startswith("count "):
            continue
        if l.startswith("error "):
            out.append("error " + l.split(" ")[1])
        elif l.startswith("exception "):
            out.append("exception " + l.split(" ")[1])
        else:
            out.append(unesc(l))
    return out


def run_saxon(args, classes, exprs, doc):
    cases = os.path.join(WORK, "cases.txt")
    with open(cases, "w", encoding="utf-8", newline="\n") as f:
        f.write("nodes value\n")
        for e in exprs:
            f.write("expr " + e + "\n")
    cp = os.pathsep.join([args.jar, classes])
    # the implicit time zone UTC, the evaluator's default; exit code 1 only
    # means a Java exception in an expression ("error internal")
    try:
        p = subprocess.run([args.java, "-Duser.timezone=UTC", "-cp", cp, "XPathOracle", doc, cases],
                           capture_output=True, timeout=1800)
    except subprocess.TimeoutExpired:
        sys.exit("oracle: no answer within 30 minutes")
    text = p.stdout.decode("utf-8").replace("\r\n", "\n")
    results, cur = [], None
    for line in text.split("\n"):
        if line.startswith("# "):
            cur = []
            results.append(cur)
        elif cur is not None and line:
            cur.append(line)
    # exit code 1 only with an "error internal" (another uncaught Java
    # error also ends with 1, perhaps after the last expression's "# " line)
    internal = any(r == ["error internal"] for r in results)
    if p.returncode not in (0, 1) or (p.returncode == 1 and not internal) or len(results) != len(exprs):
        sys.exit("oracle: exit code %d, %d results for %d expressions\n%s" % (
            p.returncode, len(results), len(exprs), p.stderr.decode("utf-8", "replace")[-2000:]))
    return [[unesc(l) for l in r] for r in results]


def load_known():
    """The known differences: (category, expression regex, results regex,
    None, or "same items" for a rule that only allows another order)."""
    known = []
    if os.path.isfile(KNOWN):
        with open(KNOWN, encoding="utf-8") as f:
            for line in f:
                line = line.rstrip("\r\n")
                if not line.strip() or line.startswith("#"):
                    continue
                cat, rest = line.split(" ", 1)
                parts = rest.split(chr(9))
                rr = None
                if len(parts) > 1:
                    if parts[1] == "=same items":
                        rr = SAME_ITEMS
                    elif parts[1].startswith("=types "):
                        rr = tuple(parts[1].split(" ")[1:3])
                    else:
                        rr = re.compile(parts[1])
                known.append((cat, re.compile(parts[0]), rr))
    return known


SAME_ITEMS = "same items"


def same_but_types(ours, saxon, a, b):
    """The same items, but at least one that is of type a here and b in
    Saxon with the same value."""
    if len(ours) != len(saxon):
        return False
    swapped = False
    for o, s in zip(ours, saxon):
        if o == s:
            continue
        if o.startswith(a + " ") and s.startswith(b + " ") and o[len(a):] == s[len(b):]:
            swapped = True
            continue
        return False
    return swapped


def known_category(known, expr, ours, saxon):
    both = " | ".join(ours) + " || " + " | ".join(saxon)
    for cat, rx, rr in known:
        if not rx.search(expr):
            continue
        if rr is None:
            return cat
        if rr == SAME_ITEMS:
            if sorted(ours) == sorted(saxon):
                return cat
        elif isinstance(rr, tuple):
            if same_but_types(ours, saxon, rr[0], rr[1]):
                return cat
        elif rr.search(both):
            return cat
    return None


def kind_of(ours, saxon):
    """The class of a difference: crash (the helper died, gave no result or
    raised another exception than an XPath error), saxon-internal (Saxon
    failed with a Java exception: not compared), value (both have a value),
    code (both an error, other codes: which error comes first),
    ours-error / saxon-error (only one side an error: XPath lets an
    implementation skip an error whose value it does not need, and Saxon
    raises type errors from static types; a spurious error of the evaluator
    would land in ours-error)."""
    if ours == ["crash"] or any(l.startswith("exception ") for l in ours):
        return "crash"
    if saxon == ["error internal"]:
        return "saxon-internal"
    oe = len(ours) == 1 and ours[0].startswith("error ")
    se = len(saxon) == 1 and saxon[0].startswith("error ")
    if oe and se:
        return "code"
    if oe:
        return "ours-error"
    if se:
        return "saxon-error"
    return "value"


KINDS = ("crash", "value", "ours-error", "code", "saxon-error", "saxon-internal")
FAILING = ("crash", "value")
# shares of all expressions above which a run fails: errors only the
# evaluator raises (0.24 % with seeds 20 and 21) and expressions Saxon
# cannot compare (0.06 %); and the share that must be equal (99.5 %)
MAX_OURS_ERROR = 0.01
MAX_SAXON_INTERNAL = 0.01
MIN_EQUAL = 0.97


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--exe", required=True)
    ap.add_argument("--java", required=True)
    ap.add_argument("--jar", required=True)
    ap.add_argument("--count", type=int, default=5000)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--batch", type=int, default=1000)
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    args.exe = os.path.abspath(args.exe)
    saxonjar.check(args.jar)
    os.makedirs(WORK, exist_ok=True)
    classes = os.path.join(WORK, "classes")
    javac = os.path.join(os.path.dirname(args.java), "javac" + (".exe" if args.java.endswith(".exe") else ""))
    src = os.path.join(ROOT, "tools", "XPathOracle.java")
    stamp = os.path.join(classes, "XPathOracle.class")
    if not os.path.isfile(stamp) or os.path.getmtime(stamp) < os.path.getmtime(src):
        os.makedirs(classes, exist_ok=True)
        subprocess.run([javac, "-cp", args.jar, "-d", classes, src], check=True)
    doc = os.path.join(WORK, "doc.xml")
    with open(doc, "w", encoding="utf-8", newline="\n") as f:
        f.write(DOCUMENT)
    known = load_known()
    rnd = random.Random(args.seed)
    exprs, seen = [], set()
    while len(exprs) < args.count:
        e = expression(rnd)
        if e not in seen:
            seen.add(e)
            exprs.append(e)
    by_kind, explained, same, bad_exit = {}, {}, 0, []
    for start in range(0, len(exprs), args.batch):
        part = exprs[start:start + args.batch]
        raw, codes = run_ours(args.exe, part, doc)
        bad_exit += [c for c in codes if c != 0]
        ours = [norm_ours(r or ["crash"]) for r in raw]
        sax = run_saxon(args, classes, part, doc)
        for e, o, s in zip(part, ours, sax):
            if o == s:
                same += 1
                continue
            kind = kind_of(o, s)
            cat = None
            if kind not in ("crash", "saxon-internal"):
                cat = known_category(known, e, o, s)
            if cat:
                explained.setdefault(cat, []).append((e, o, s))
            else:
                by_kind.setdefault(kind, []).append((e, o, s))
        print("%d / %d expressions" % (min(start + args.batch, len(exprs)), len(exprs)), flush=True)
    out = os.path.join(WORK, "findings.txt")
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write("seed %d, %d expressions\n" % (args.seed, len(exprs)))
        groups = [(k, by_kind.get(k, [])) for k in KINDS] + [("known " + c, l) for c, l in sorted(explained.items())]
        for kind, items in groups:
            for e, o, s in items:
                f.write("\n%s: %s\n  ours:  %s\n  saxon: %s\n" % (kind, e, " | ".join(o) or "()",
                                                                 " | ".join(s) or "()"))
    n = len(exprs)
    count = dict((k, len(by_kind.get(k, []))) for k in KINDS)
    print("%d equal; known: %s" % (same, ", ".join("%s %d" % (c, len(l)) for c, l in sorted(explained.items()))
                                   or "none"))
    print("differences: " + ", ".join("%s %d" % (k, count[k]) for k in KINDS))
    print("details: " + out)
    problems = []
    if count["crash"] or count["value"]:
        problems.append("%d crash, %d value" % (count["crash"], count["value"]))
    if count["ours-error"] > MAX_OURS_ERROR * n:
        problems.append("errors only the evaluator raises: %d (more than %g %%)" % (count["ours-error"],
                                                                                   MAX_OURS_ERROR * 100))
    if count["saxon-internal"] > MAX_SAXON_INTERNAL * n:
        problems.append("expressions Saxon cannot evaluate: %d (more than %g %%)" % (count["saxon-internal"],
                                                                                    MAX_SAXON_INTERNAL * 100))
    if same < MIN_EQUAL * n:
        problems.append("only %d equal (less than %g %%)" % (same, MIN_EQUAL * 100))
    if bad_exit:
        problems.append("the helper ended with exit code %s" % ", ".join(str(c) for c in sorted(set(
            str(x) for x in bad_exit))))
    if args.verbose:
        for k in FAILING:
            for e, o, s in by_kind.get(k, [])[:20]:
                print(k + ":", e, "\n  ours: ", " | ".join(o), "\n  saxon:", " | ".join(s))
    if problems:
        print("FAILED: " + "; ".join(problems))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
