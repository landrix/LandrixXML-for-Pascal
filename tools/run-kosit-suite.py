#!/usr/bin/env python3
"""Run the KoSIT XRechnung test suite against LandrixXml (engine conformance).

Downloads the test suite and the matching KoSIT validator configuration
(pinned releases, checked by SHA-256) into tests/data/kosit-suite/
(git-ignored; the schemas are not committed), lets the helper
tests/LandrixXmlKosit.dpr validate every instance with the XML schema and
the rule files (tests/data/schematron/rules) of the scenario the KoSIT
validator chose for it, and compares the results with the committed
reference tests/data/schematron/expected-kosit-suite.txt.

The reference, per instance: the scenario and the XML schema verdict with
the error codes and positions from the KoSIT validator's report, and per
Schematron step the fired rules, failed asserts and successful reports
from the SVRL of the configuration's XSLT run with Saxon HE (as
tools/gen-schematron-testdata.py does). The full KoSIT pipeline (report,
assessment, custom levels) is not compared here.

Usage:
  python tools/run-kosit-suite.py [--exe PATH] [--verbose]
  python tools/run-kosit-suite.py --generate --java PATH/java.exe
      --jar validator-1.6.3-standalone.jar
Build the helper first, e.g.
  ./tools/build.ps1 fpc322-win64 -Program tests/LandrixXmlKosit.dpr -NoRun
--generate checks first that the rule files match the configuration's
XSLT (tools/sch-crosscheck.py), then rewrites the reference.
Exit code: 0 if every instance gives the reference's result.
Results: build/kosit/results.txt.
"""

import argparse
import concurrent.futures
import difflib
import hashlib
import importlib.util
import io
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "tests", "data", "kosit-suite")
EXPECTED = os.path.join(ROOT, "tests", "data", "schematron", "expected-kosit-suite.txt")
RULES = os.path.join(ROOT, "tests", "data", "schematron", "rules")
WORK = os.path.join(ROOT, "build", "kosit")

PACKAGES = {
    "testsuite": ("https://github.com/itplr-kosit/xrechnung-testsuite/releases/download/v2026-08-31/"
                  "xrechnung-3.0.2-testsuite-2026-08-31.zip",
                  "1e81ef7563e0fa04c0e0b0631318a7e0843a3c0beb57d83ef95ac0c4a095e3d7"),
    "configuration": ("https://github.com/itplr-kosit/validator-configuration-xrechnung/releases/download/"
                      "v2026-08-31/xrechnung-3.0.2-validator-configuration-2026-08-31.zip",
                      "2530cd107c414511c5d0462ec10f886910395abfca820db82e83d70bf01221a8"),
}
INSTANCES = os.path.join(DATA, "testsuite", "instances")
CONFIG = os.path.join(DATA, "configuration")

# the configuration's XSLT and the rule file compiled from the same source
RULE_FILES = {
    "EN16931-UBL-validation.xsl": "en16931-ubl",
    "EN16931-CII-validation.xsl": "en16931-cii",
    "XRechnung-UBL-validation.xsl": "xrechnung-ubl",
    "XRechnung-CII-validation.xsl": "xrechnung-cii",
}
# assert ids where the rule file deliberately differs from the XSLT text
# (see tests/data/schematron/NOTICE.md)
CROSSCHECK_ALLOW = ["CII-SR-282"]

SCN = "{http://www.xoev.de/de/validator/framework/1/scenarios}"
REP = "{http://www.xoev.de/de/validator/varl/1}"


def fetch():
    for name, (url, digest) in PACKAGES.items():
        target = os.path.join(DATA, name)
        stamp = os.path.join(target, ".sha256")
        if os.path.exists(stamp) and open(stamp).read().strip() == digest:
            continue
        print("downloading", url)
        data = urllib.request.urlopen(url, timeout=120).read()
        got = hashlib.sha256(data).hexdigest()
        if got != digest:
            sys.exit("%s has SHA-256 %s, expected %s" % (url, got, digest))
        if os.path.exists(target):
            shutil.rmtree(target)
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            for member in z.namelist():
                path = os.path.normpath(member)
                if path.startswith("..") or os.path.isabs(path) or ":" in member:
                    sys.exit("unexpected archive member: " + member)
            z.extractall(target)
        with open(stamp, "w") as f:
            f.write(digest + "\n")


def instances():
    """The instance files as paths relative to INSTANCES with "/", sorted."""
    result = []
    for folder, _, files in os.walk(INSTANCES):
        for f in files:
            if f.endswith(".xml"):
                result.append(os.path.relpath(os.path.join(folder, f), INSTANCES).replace(os.sep, "/"))
    return sorted(result)


def scenarios():
    """scenario name -> (XML schema location, [XSLT locations])"""
    result = {}
    root = ET.parse(os.path.join(CONFIG, "scenarios.xml")).getroot()
    for s in root.iter(SCN + "scenario"):
        xsd = [loc.text for v in s.findall(SCN + "validateWithXmlSchema") for loc in v.iter(SCN + "location")]
        xsl = [loc.text for v in s.findall(SCN + "validateWithSchematron") for loc in v.iter(SCN + "location")]
        result[s.find(SCN + "name").text] = (xsd[0] if xsd else None, xsl)
    return result


def rule_name(location):
    name = RULE_FILES.get(location.rsplit("/", 1)[-1])
    if name is None:
        sys.exit("no rule file for " + location)
    return name


def read_blocks(path):
    """## NAME -> the lines of the block after it"""
    blocks, name = {}, None
    with open(path, encoding="utf-8") as f:
        for line in f.read().splitlines():
            if line.startswith("## "):
                name = line[3:]
                blocks[name] = []
            elif name is not None:
                blocks[name].append(line)
    return blocks


# ---------------------------------------------------------------- reference

def kosit_reports(java, jar, docs):
    """name -> (scenario or None, [XML schema lines]) from the KoSIT validator"""
    if len(set(os.path.basename(d) for d in docs)) != len(docs):
        sys.exit("instance file names are not unique; the KoSIT reports would overwrite each other")
    result = {}
    with tempfile.TemporaryDirectory() as out:
        empty = os.path.join(out, "stdin.txt")
        open(empty, "w").close()
        cmd = [java, "-jar", jar, "-s", os.path.join(CONFIG, "scenarios.xml"), "-r", CONFIG, "-o", out]
        cmd += [os.path.join(INSTANCES, d) for d in docs]
        # the validator reads stdin when it is not a file
        with open(empty) as stdin:
            subprocess.run(cmd, stdin=stdin, capture_output=True)
        for d in docs:
            report = os.path.join(out, os.path.splitext(os.path.basename(d))[0] + "-report.xml")
            if not os.path.exists(report):
                sys.exit("no KoSIT report for " + d)
            root = ET.parse(report).getroot()
            name = root.find(REP + "scenarioMatched/" + SCN + "scenario/" + SCN + "name")
            lines = []
            for step in root.iter(REP + "validationStepResult"):
                if step.get("id") != "val-xsd":
                    continue
                lines.append("xsd " + ("valid" if step.get("valid") == "true" else "invalid"))
                for m in step.findall(REP + "message"):
                    lines.append("xsd-error %s %s:%s" % (m.get("code"), m.get("lineNumber"), m.get("columnNumber")))
            result[d] = (name.text if name is not None else None, lines)
    return result


def generate(java, jar):
    here = os.path.dirname(os.path.abspath(__file__))
    spec = importlib.util.spec_from_file_location("gen", os.path.join(here, "gen-schematron-testdata.py"))
    gen = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gen)
    scn = scenarios()
    for xsl in sorted(set(x for _, xsls in scn.values() for x in xsls)):
        r = subprocess.run([sys.executable, os.path.join(here, "sch-crosscheck.py"),
                            os.path.join(RULES, rule_name(xsl) + ".xml"), os.path.join(CONFIG, xsl),
                            "--allow"] + CROSSCHECK_ALLOW, capture_output=True, text=True)
        if r.returncode != 0:
            sys.exit("the rule file %s differs from %s:%s%s" % (rule_name(xsl), xsl, os.linesep, r.stdout))
    docs = instances()
    reports = kosit_reports(java, jar, docs)
    jobs = []
    for d in docs:
        name = reports[d][0]
        if name is not None:
            jobs.extend((d, xsl) for xsl in scn[name][1])

    def svrl(job):
        return job, gen.run(java, jar, os.path.join(CONFIG, job[1]), os.path.join(INSTANCES, job[0]))

    results = {}
    with concurrent.futures.ThreadPoolExecutor(8) as ex:
        for job, lines in ex.map(svrl, jobs):
            # a failure without a Saxon error code (JVM, I/O) is no result
            if "saxon-error unknown" in lines:
                sys.exit("Saxon failed without an error code on %s with %s" % job)
            results[job] = lines
    out = []
    for d in docs:
        name, xsd = reports[d]
        out.append("## " + d)
        out.append("scenario " + (name or "-"))
        if name is None:
            continue
        out.extend(xsd)
        for xsl in scn[name][1]:
            out.append("### " + rule_name(xsl))
            out.extend(results[(d, xsl)])
    with open(EXPECTED, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out) + "\n")
    print("%d instances, %d without a scenario" % (len(docs), sum(1 for d in docs if reports[d][0] is None)))


# ---------------------------------------------------------------- comparison

def ours(block):
    """the reference block in the helper's form: no scenario line, and a
    Saxon dynamic error as "saxon-error" (compared separately)"""
    return [line for line in block if not line.startswith("scenario ")]


def same(want, got):
    if got is None:
        return False
    if want == got:
        return True
    # Saxon stopped with a dynamic error: the step must report one too
    if not any(line.startswith("saxon-error ") for line in want):
        return False
    def steps(lines):
        result, current = {}, None
        for line in lines:
            if line.startswith("### "):
                current = line[4:]
                result[current] = []
            elif current is None:
                result.setdefault("", []).append(line)
            else:
                result[current].append(line)
        return result
    w, g = steps(want), steps(got)
    if set(w) != set(g):
        return False
    for step in w:
        if any(line.startswith("saxon-error ") for line in w[step]):
            if not any(line.startswith("dynamic-error ") for line in g[step]):
                return False
        elif w[step] != g[step]:
            return False
    return True


def compare(exe, verbose):
    exe = os.path.abspath(exe)
    if not os.path.exists(exe):
        sys.exit("missing helper %s (build tests/LandrixXmlKosit.dpr first)" % exe)
    if not os.path.exists(EXPECTED):
        sys.exit("missing " + EXPECTED)
    expected = read_blocks(EXPECTED)
    docs = instances()
    if sorted(expected) != docs:
        sys.exit("the instances differ from the reference (%d here, %d there)" % (len(docs), len(expected)))
    scn = scenarios()
    os.makedirs(WORK, exist_ok=True)
    job = os.path.join(WORK, "job.txt")
    results = os.path.join(WORK, "results.txt")
    skipped = 0
    with open(job, "w", encoding="utf-8", newline="\n") as f:
        for d in docs:
            name = expected[d][0][len("scenario "):] if expected[d] else "-"
            if name == "-":
                skipped += 1
                continue
            xsd, xsls = scn[name]
            f.write("doc %s\nfile %s\n" % (d, os.path.join(INSTANCES, d)))
            if xsd:
                f.write("xsd %s\n" % os.path.join(CONFIG, xsd))
            for xsl in xsls:
                f.write("rules %s %s\n" % (rule_name(xsl), os.path.join(RULES, rule_name(xsl) + ".xml")))
            f.write("run\n")
    r = subprocess.run([exe, job, results])
    if r.returncode != 0:
        sys.exit("the helper failed with exit code %d" % r.returncode)
    got = read_blocks(results)
    differ = []
    for d in docs:
        if expected[d] and expected[d][0] == "scenario -":
            continue
        want = ours(expected[d])
        if not same(want, got.get(d)):
            differ.append(d)
            if verbose or len(differ) <= 5:
                print("== " + d)
                for line in difflib.unified_diff(want, got.get(d) or ["(no result)"], "reference", "here", n=0,
                                                 lineterm=""):
                    print("  " + line)
    checked = len(docs) - skipped
    if skipped:
        print("%d instances without a scenario in the reference" % skipped)
    print("%d instances, %d checked, %d equal, %d differ" % (len(docs), checked, checked - len(differ), len(differ)))
    return 1 if differ or skipped else 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--exe", default=os.path.join(ROOT, "build", "fpc322-win64", "LandrixXmlKosit.exe"))
    ap.add_argument("--verbose", action="store_true")
    ap.add_argument("--generate", action="store_true")
    ap.add_argument("--java")
    ap.add_argument("--jar")
    args = ap.parse_args()
    fetch()
    if args.generate:
        if not args.java or not args.jar:
            sys.exit("--generate needs --java and --jar")
        generate(args.java, args.jar)
        return 0
    return compare(args.exe, args.verbose)


if __name__ == "__main__":
    sys.exit(main())
