#!/usr/bin/env python3
"""Benchmark: the times of fixed scenarios against the times stored for
this machine.

  python tools/bench.py [--build build/fpc322-win64] [--repeat 3]
                        [--only perf,xpath,regex,xslt,kosit] [--update]

Scenarios (each run --repeat times, the fastest run counts):

  perf   tests/LandrixXmlPerf.dpr on a generated document of --size MB:
         streaming writer (write), pull reader (read), DOM load and save
         (the program's own time per phase; write is the writer making
         the document)
  xpath  fixed XPath expressions (profile saxon) on a generated document
         with the QT3 helper (tests/LandrixXmlQt3.dpr)
  regex  regular expressions with category and block escapes and class
         subtraction over 55,000 code points (what makes the regex-classes
         cases of the W3C XSLT suite slow), QT3 helper
  xslt   a generated stylesheet (keys, grouping, sorting, numbering,
         recursion, formatting) on the same document with the helper of
         the cross-check (tests/LandrixXmlXsltRun.dpr)
  kosit  tools/run-kosit-suite.py with tests/LandrixXmlKosit.dpr (skipped
         when the KoSIT suite is not downloaded in tests/data/kosit-suite)

Build the helpers first, e.g. ./tools/build.ps1 fpc322-win64 -Program
tests/LandrixXmlPerf.dpr -NoRun (and LandrixXmlQt3, LandrixXmlXsltRun,
LandrixXmlKosit). A scenario that cannot run (helper or KoSIT suite
missing; leave it out with --only) or fails (an error in an expression,
another exit code) fails the run.

The stored times are per machine and per build folder, in
build/bench/times-HOST.json (git-ignored; --times FILE for another
place), each scenario with a fingerprint of its workload (expressions,
stylesheet, document size): a changed workload starts its times anew. A
measurement more than 20 % (and 0.05 s) slower than the stored time fails
the run (exit code 1). The first run of a measurement and
--update store the times of this run (--update also after an intended
change or a faster version; never to hide an unexplained slowdown). Run
it on an otherwise idle machine: tools/x86-suites.ps1 bench runs it on
the x86 machine.
"""

import argparse
import hashlib
import json
import os
import re
import socket
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = os.path.join(ROOT, "build", "bench")
SLOWER = 1.20
FLOOR = 0.05
SCENARIOS = ("perf", "xpath", "regex", "xslt", "kosit")


def esc(s):
    """A job file value: control characters and the backslash as \\xHH."""
    out = []
    for ch in s:
        if ord(ch) < 32 or ch == chr(92):
            out.append(chr(92) + "x%02X" % ord(ch))
        else:
            out.append(ch)
    return "".join(out)


ITEMS = 20000


def document(path, items=ITEMS):
    """The document of the xpath and xslt scenarios: ITEMS items in 50
    groups, with names, prices and tags."""
    parts = ['<items>']
    for n in range(1, items + 1):
        parts.append('<item id="i%d" group="g%d" price="%.2f"><name>Name %d</name><tags><t>a</t><t>b%d</t></tags>'
                     '</item>' % (n, n % 50, n * 1.37, n, n % 7))
    parts.append('</items>')
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(parts) + "\n")


XPATH = [
    "count(//item[@group = 'g7'])",
    "sum(//item/@price)",
    "count(distinct-values(//item/@group))",
    "string-length(string-join(//name, ','))",
    "count(//item[name = //item[@id = 'i500']/name])",
    "count(//t[. = 'b3']/ancestor::item)",
    "sum(for $g in distinct-values(//item/@group) return count(//item[@group = $g]))",
    "count(//item[position() mod 3 = 0][last()])",
    "sum(for $i in //item return xs:decimal($i/@price) * 2)",
    "format-number(sum(//item/@price), '#,##0.00')",
    "count(//item[matches(name, '^Name 1[0-9]*5$')])",
    "string-length(string-join(for $i in 1 to 2000 return format-date(xs:date('2026-01-01') + "
    "xs:dayTimeDuration('P1D') * $i, '[Y0001]-[M01]-[D01]'), ' '))",
    "count(tokenize(string-join(//name, ' '), '" + chr(92) + "s+'))",
    "string-length(replace(string-join(//name, ','), 'Name (" + chr(92) + "d+)', '$1'))",
    "count(//item except //item[@group = 'g1'])",
    "count((//item | //t)/..)",
    "every $i in //item satisfies $i/@price >= 0",
    "count(reverse(//item)[@price > 100])",
    "string-length(string-join(for $i in //item[position() le 5000] return upper-case($i/name), ''))",
    "count(//item[some $t in tags/t satisfies $t = 'b5'])",
]

BS = chr(92)
REGEX = [
    "count((32 to 55000)[matches(codepoints-to-string(.), '" + BS + "p{L}')])",
    "count((32 to 55000)[matches(codepoints-to-string(.), '[" + BS + "p{L}-[" + BS + "p{Lu}]]')])",
    "count((32 to 55000)[matches(codepoints-to-string(.), '" + BS + "p{IsBasicLatin}|" + BS + "p{Nd}')])",
    "count((32 to 55000)[matches(codepoints-to-string(.), '[" + BS + "w-[" + BS + "d]]')])",
    "count((32 to 55000)[matches(codepoints-to-string(.), '" + BS + "P{IsCJKUnifiedIdeographs}')])",
]

STYLESHEET = """<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
  <xsl:output indent="yes"/>
  <xsl:key name="by-group" match="item" use="@group"/>
  <xsl:function name="f:fib" as="xs:integer">
    <xsl:param name="n" as="xs:integer"/>
    <xsl:sequence select="if ($n lt 2) then $n else f:fib($n - 1) + f:fib($n - 2)"/>
  </xsl:function>
  <xsl:template match="/">
    <report fib="{f:fib(20)}">
      <xsl:for-each-group select="items/item" group-by="@group">
        <xsl:sort select="current-grouping-key()"/>
        <group key="{current-grouping-key()}" count="{count(key('by-group', current-grouping-key()))}"
            total="{format-number(sum(current-group()/@price), '#,##0.00')}">
          <xsl:apply-templates select="current-group()[position() le 100]">
            <xsl:sort select="xs:decimal(@price)" order="descending"/>
          </xsl:apply-templates>
        </group>
      </xsl:for-each-group>
      <xsl:call-template name="count-down"><xsl:with-param name="n" select="300"/></xsl:call-template>
    </report>
  </xsl:template>
  <xsl:template match="item">
    <row n="{position()}" id="{@id}">
      <xsl:number count="item" format="i"/>
      <xsl:value-of select="upper-case(name), tags/t" separator="|"/>
    </row>
  </xsl:template>
  <xsl:template name="count-down">
    <xsl:param name="n" as="xs:integer"/>
    <xsl:if test="$n gt 0">
      <d n="{$n}"><xsl:call-template name="count-down"><xsl:with-param name="n" select="$n - 1"/></xsl:call-template></d>
    </xsl:if>
  </xsl:template>
</xsl:stylesheet>
"""


def workload(scenario, size):
    """A fingerprint of what a scenario measures: stored times of another
    workload are not compared."""
    text = {"perf": str(size), "xpath": repr(XPATH), "regex": repr(REGEX), "xslt": STYLESHEET,
            "kosit": ""}[scenario] + "|" + repr(ITEMS)
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]


class Failed(Exception):
    pass


def helper(build, name):
    exe = os.path.join(build, name + (".exe" if os.name == "nt" else ""))
    return exe if os.path.isfile(exe) else None


def run_perf(build, size):
    exe = helper(build, "LandrixXmlPerf")
    if not exe:
        return None
    times = {}
    for phase, wanted in (("reader", ("write", "read")), ("dom", ("load", "save"))):
        p = subprocess.run([exe, str(size), phase], capture_output=True, text=True, timeout=1800)
        if p.returncode != 0:
            raise Failed("LandrixXmlPerf %s: exit code %d %s" % (phase, p.returncode, p.stdout[-500:]))
        for line in p.stdout.splitlines():
            m = re.match(r"(\w+) \(.*?\): (?:.* in )?(\d+) ms", line.strip())
            if m and m.group(1) in wanted:
                times["perf-" + m.group(1)] = int(m.group(2)) / 1000.0
        for w in wanted:
            if "perf-" + w not in times:
                raise Failed("LandrixXmlPerf %s: no time for %s in %r" % (phase, w, p.stdout[-500:]))
    return times


def run_qt3(build, name, exprs, doc):
    exe = helper(build, "LandrixXmlQt3")
    if not exe:
        return None
    job = os.path.join(WORK, name + "-job.txt")
    res = os.path.join(WORK, name + "-results.txt")
    lines = []
    for i, e in enumerate(exprs):
        lines += ["case c%d" % i, "source " + esc(doc), "profile saxon", "expr " + esc(e), "run"]
    with open(job, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    if os.path.exists(res):
        os.remove(res)
    start = time.perf_counter()
    p = subprocess.run([exe, job, res, "0"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=1800)
    took = time.perf_counter() - start
    if p.returncode != 0 or not os.path.exists(res):
        raise Failed("LandrixXmlQt3 (%s): exit code %d" % (name, p.returncode))
    # every expression must give a value: an error would be fast
    done, cur, first = 0, None, None
    with open(res, encoding="utf-8", errors="replace") as f:
        for line in f.read().split("\n"):
            if line.startswith("case "):
                cur, first = int(line[6:]), None
            elif line.startswith("R ") and first is None:
                first = line[2:]
            elif line == "done" and cur is not None:
                if not first or not first.startswith("count "):
                    raise Failed("%s: %s gave %s" % (name, exprs[cur], first))
                done += 1
    if done != len(exprs):
        raise Failed("%s: %d of %d expressions done" % (name, done, len(exprs)))
    return {name: took}


def run_xslt(build, doc):
    exe = helper(build, "LandrixXmlXsltRun")
    if not exe:
        return None
    sheet = os.path.join(WORK, "bench.xsl")
    with open(sheet, "w", encoding="utf-8", newline="\n") as f:
        f.write(STYLESHEET)
    out = os.path.join(WORK, "xslt-out.xml")
    start = time.perf_counter()
    p = subprocess.run([exe, sheet, doc, out], capture_output=True, text=True, timeout=1800)
    took = time.perf_counter() - start
    if p.returncode != 0:
        raise Failed("LandrixXmlXsltRun: exit code %d %s" % (p.returncode, (p.stdout + p.stderr)[-500:]))
    return {"xslt": took}


def run_kosit(build):
    exe = helper(build, "LandrixXmlKosit")
    if not exe or not os.path.isdir(os.path.join(ROOT, "tests", "data", "kosit-suite")):
        return None
    start = time.perf_counter()
    p = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "run-kosit-suite.py"), "--exe", exe],
                       capture_output=True, text=True, timeout=3600)
    took = time.perf_counter() - start
    if p.returncode != 0:
        raise Failed("run-kosit-suite.py: exit code %d %s" % (p.returncode, (p.stdout + p.stderr)[-800:]))
    return {"kosit": took}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--build", default=os.path.join("build", "fpc322-win64"))
    ap.add_argument("--repeat", type=int, default=3)
    ap.add_argument("--size", type=int, default=20, help="MB of the perf document")
    ap.add_argument("--only", default=",".join(SCENARIOS))
    ap.add_argument("--times")
    ap.add_argument("--update", action="store_true")
    args = ap.parse_args()
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    build = os.path.abspath(args.build)
    only = [s.strip() for s in args.only.split(",") if s.strip()]
    for s in only:
        if s not in SCENARIOS:
            sys.exit("unknown scenario %s (known: %s)" % (s, ", ".join(SCENARIOS)))
    os.makedirs(WORK, exist_ok=True)
    times_file = os.path.abspath(args.times or os.path.join(WORK, "times-%s.json" % socket.gethostname().lower()))
    key = os.path.basename(build.rstrip("/" + chr(92)))
    stored = {}
    if os.path.isfile(times_file):
        with open(times_file, encoding="utf-8") as f:
            stored = json.load(f)
    base = stored.get(key, {})
    marks = base.setdefault("workload", {})
    changed = []
    for s in only:
        fp = workload(s, args.size)
        if marks.get(s) != fp:
            # other expressions or another size: these times do not count
            for k in [k for k in base if k != "workload" and k.split("-")[0] == s]:
                del base[k]
            if s in marks:
                changed.append(s)
            marks[s] = fp
    doc = os.path.join(WORK, "bench.xml")
    document(doc)

    best, skipped = {}, []
    try:
        for s in only:
            for _ in range(max(1, args.repeat)):
                if s == "perf":
                    got = run_perf(build, args.size)
                elif s == "xpath":
                    got = run_qt3(build, "xpath", XPATH, doc)
                elif s == "regex":
                    got = run_qt3(build, "regex", REGEX, doc)
                elif s == "xslt":
                    got = run_xslt(build, doc)
                else:
                    got = run_kosit(build)
                if got is None:
                    skipped.append(s)
                    break
                for k, v in got.items():
                    best[k] = min(v, best.get(k, v))
            print("%s %s" % (s, "skipped" if s in skipped else "done"), flush=True)
    except (Failed, subprocess.TimeoutExpired) as e:
        print("FAILED: %s" % e)
        return 1

    slower, new = [], []
    print("%-14s %9s %9s" % ("measurement", "now (s)", "stored"))
    for k in sorted(best):
        b = base.get(k)
        mark = ""
        if b is None:
            new.append(k)
            mark = "new"
        elif best[k] > b * SLOWER and best[k] - b > FLOOR:
            slower.append(k)
            mark = "SLOWER %+.0f %%" % ((best[k] / b - 1) * 100) if b > 0 else "SLOWER"
        elif b > 0 and best[k] < b / SLOWER and b - best[k] > FLOOR:
            mark = "faster %+.0f %% (--update keeps it)" % ((best[k] / b - 1) * 100)
        print("%-14s %9.3f %9s %s" % (k, best[k], "%.3f" % b if b is not None else "-", mark))
    for s in skipped:
        print("%-14s skipped (helper or suite missing)" % s)
    for s in changed:
        print("%-14s workload changed: times stored anew" % s)
    if args.update or new:
        for k in best:
            if args.update or k in new:
                base[k] = round(best[k], 3)
        stored[key] = base
        with open(times_file, "w", encoding="utf-8", newline="\n") as f:
            json.dump(stored, f, indent=1, sort_keys=True)
            f.write("\n")
        print("stored in " + times_file)
    problems = []
    if slower and not args.update:
        problems.append("more than %d %% slower: %s" % (round((SLOWER - 1) * 100), ", ".join(slower)))
    if skipped:
        problems.append("not run: %s (helper or suite missing; --only leaves a scenario out)" % ", ".join(skipped))
    if problems:
        print("FAILED: " + "; ".join(problems))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
