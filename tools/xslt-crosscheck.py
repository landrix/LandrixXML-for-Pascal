#!/usr/bin/env python3
"""Cross-check the XSLT processor with Saxon HE on the KoSIT report.

For every instance of the KoSIT XRechnung test suite (downloaded by
tools/run-kosit-suite.py into tests/data/kosit-suite/, pinned by SHA-256)
the KoSIT validator writes the input of its report stylesheet
(--serialize-report-input); then Saxon HE (the validator jar) and the
helper tests/LandrixXmlXsltRun.dpr run the report stylesheet of the
configuration (resources/xrechnung-report.xsl, which imports
default-report.xsl) on it, with the instance as parameter input-document.
The two outputs must be equal byte for byte.

The report inputs hold a time stamp and the instance's path, so nothing
of this is committed; the check needs Java and the validator jar.

Usage:
  python tools/xslt-crosscheck.py --java PATH/java.exe
      --jar validator-1.6.3-standalone.jar [--exe PATH] [--filter TEXT]
      [--keep-reference] [--verbose]
Build the helper first, e.g.
  ./tools/build.ps1 fpc322-win64 -Program tests/LandrixXmlXsltRun.dpr -NoRun
--keep-reference reuses report inputs and Saxon outputs from an earlier
run (build/xslt-crosscheck/; only valid while the suite, the stylesheets
and the jar are the same; a run without it removes them first). Exit
code: 0 if every report is equal, 1 otherwise or if nothing was checked.
"""

import argparse
import concurrent.futures
import importlib.util
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = os.path.join(ROOT, "build", "xslt-crosscheck")
# seconds: the validator for all documents, one Saxon or helper run
VALIDATOR_TIMEOUT = 1800
RUN_TIMEOUT = 300


def kosit_module():
    spec = importlib.util.spec_from_file_location(
        "kosit", os.path.join(ROOT, "tools", "run-kosit-suite.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def default_exe():
    name = "LandrixXmlXsltRun.exe" if os.name == "nt" else "LandrixXmlXsltRun"
    return os.path.join(ROOT, "build", "fpc322-win64", name)


def outputs(doc):
    """The report input, Saxon's and the helper's output for a document."""
    base = os.path.join(WORK, os.path.splitext(os.path.basename(doc))[0])
    return base + "-reportInput.xml", base + ".saxon.xml", base + ".ours.xml"


def report_inputs(java, jar, kosit, docs):
    """Lets the validator write the report input of each document (the
    files of an earlier run removed first)."""
    for doc in docs:
        for path in outputs(doc):
            if os.path.exists(path):
                os.remove(path)
    empty = os.path.join(WORK, "stdin.txt")
    open(empty, "w").close()
    cmd = [java, "-jar", jar, "-s", os.path.join(kosit.CONFIG, "scenarios.xml"), "-r", kosit.CONFIG,
           "-o", WORK, "--serialize-report-input"] + docs
    # the validator reads stdin when it is not a file; the report input
    # goes to the current directory. Its exit code counts rejected
    # documents, so only a missing report input is an error.
    with open(empty) as stdin:
        run = subprocess.run(cmd, stdin=stdin, capture_output=True, cwd=WORK, timeout=VALIDATOR_TIMEOUT)
    if not any(os.path.exists(outputs(doc)[0]) for doc in docs):
        sys.exit("the validator wrote no report input:\n" +
                 (run.stdout + run.stderr).decode("utf-8", "replace")[-2000:])


def check(args, kosit, report, doc):
    base = os.path.splitext(os.path.basename(doc))[0]
    source, saxon, ours = outputs(doc)
    if not os.path.exists(source):
        return base, "no report input from the validator"
    if not (args.keep_reference and os.path.exists(saxon)):
        # written under another name first, so that an interrupted run
        # leaves no output that --keep-reference would take
        partial = saxon + ".part"
        try:
            run = subprocess.run([args.java, "-cp", args.jar, "net.sf.saxon.Transform", "-s:" + source,
                                  "-xsl:" + report, "+input-document=" + doc, "-o:" + partial],
                                 stdin=subprocess.DEVNULL, capture_output=True, timeout=RUN_TIMEOUT)
        except subprocess.TimeoutExpired:
            return base, "Saxon timed out"
        if run.returncode != 0:
            return base, "Saxon failed: " + run.stderr.decode("utf-8", "replace").strip()[:300]
        os.replace(partial, saxon)
    if os.path.exists(ours):
        os.remove(ours)
    try:
        run = subprocess.run([args.exe, report, source, ours, "-d", "input-document=" + doc],
                             stdin=subprocess.DEVNULL, capture_output=True, timeout=RUN_TIMEOUT)
    except subprocess.TimeoutExpired:
        return base, "timed out"
    if run.returncode != 0:
        return base, "failed: " + run.stdout.decode("utf-8", "replace").strip()[:300]
    with open(saxon, "rb") as f:
        want = f.read()
    with open(ours, "rb") as f:
        got = f.read()
    if want == got:
        return base, "equal"
    i = 0
    while i < min(len(want), len(got)) and want[i] == got[i]:
        i += 1
    return base, "differs at byte %d" % i


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--java", required=True)
    ap.add_argument("--jar", required=True)
    ap.add_argument("--exe", default=default_exe())
    ap.add_argument("--filter", default="")
    ap.add_argument("--keep-reference", action="store_true")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()
    args.exe = os.path.abspath(args.exe)
    # the validator runs in WORK: paths given relative to the current directory
    args.jar = os.path.abspath(args.jar)
    if os.path.exists(args.java):
        args.java = os.path.abspath(args.java)
    if not os.path.exists(args.exe):
        sys.exit("helper not found: %s (build tests/LandrixXmlXsltRun.dpr)" % args.exe)
    kosit = kosit_module()
    kosit.fetch()
    report = os.path.join(kosit.CONFIG, "resources", "xrechnung-report.xsl")
    docs = [os.path.join(kosit.INSTANCES, d) for d in kosit.instances() if args.filter in d]
    if not docs:
        sys.exit("no instance matches the filter " + repr(args.filter))
    names = [os.path.basename(d) for d in docs]
    if len(set(names)) != len(names):
        sys.exit("instance file names are not unique; the report inputs would overwrite each other")
    os.makedirs(WORK, exist_ok=True)
    start = time.time()
    if not args.keep_reference:
        report_inputs(args.java, args.jar, kosit, docs)
    with concurrent.futures.ThreadPoolExecutor(max(1, (os.cpu_count() or 2) - 1)) as pool:
        results = list(pool.map(lambda d: check(args, kosit, report, d), docs))
    bad = [r for r in results if r[1] != "equal"]
    for name, verdict in results:
        if verdict != "equal" or args.verbose:
            print("%s: %s" % (name, verdict))
    print("%d instances, %d equal, %d not (%d s)" % (len(results), len(results) - len(bad), len(bad),
                                                   round(time.time() - start)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
