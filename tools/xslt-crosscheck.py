#!/usr/bin/env python3
"""Cross-check the XSLT processor with Saxon HE on the KoSIT stylesheets.

For every instance of the KoSIT XRechnung test suite (downloaded by
tools/run-kosit-suite.py into tests/data/kosit-suite/, pinned by SHA-256)
three transformations run with Saxon HE (the validator jar) and with the
helper tests/LandrixXmlXsltRun.dpr; their outputs must be equal byte for
byte:

  report   the KoSIT validator writes the input of its report stylesheet
           (--serialize-report-input); resources/xrechnung-report.xsl of
           the configuration runs on it, with the instance as parameter
           input-document
  xr       the XRechnung visualization (pinned release, downloaded into
           tests/data/kosit-suite/visualization/) turns the instance into
           XR XML (ubl-invoice-xr.xsl, ubl-creditnote-xr.xsl, cii-xr.xsl)
  html     xrechnung-html.xsl turns Saxon's XR XML into HTML

The report inputs hold a time stamp and the instance's path, so nothing
of this is committed; the check needs Java and the validator jar.

Usage:
  python tools/xslt-crosscheck.py --java PATH/java.exe
      --jar validator-1.6.3-standalone.jar [--exe PATH] [--filter TEXT]
      [--only report|xr|html] [--keep-reference] [--verbose]
Build the helper first, e.g.
  ./tools/build.ps1 fpc322-win64 -Program tests/LandrixXmlXsltRun.dpr -NoRun
--keep-reference reuses report inputs and Saxon outputs from an earlier
run (build/xslt-crosscheck/; only valid while the suite, the stylesheets
and the jar are the same; a run without it removes them first). Exit
code: 0 if every output is equal, 1 otherwise or if nothing was checked.
"""

import argparse
import concurrent.futures
import hashlib
import importlib.util
import io
import os
import xml.etree.ElementTree as ET
import shutil
import subprocess
import sys
import time
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = os.path.join(ROOT, "build", "xslt-crosscheck")
VISUALIZATION = ("https://github.com/itplr-kosit/xrechnung-visualization/releases/download/v2026-01-31/"
                 "xrechnung-3.0.2-visualization-2026-01-31.zip",
                 "af9f0be80db3035d9beaeee4c066bdc7a3ccbec2e25a428c460c25b9f894b383")
# seconds: the validator for all documents, one Saxon or helper run
VALIDATOR_TIMEOUT = 1800
RUN_TIMEOUT = 300
STAGES = ("report", "xr", "html")


def kosit_module():
    spec = importlib.util.spec_from_file_location(
        "kosit", os.path.join(ROOT, "tools", "run-kosit-suite.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def fetch_visualization(kosit):
    """The visualization package (pinned by SHA-256); its xsl folder."""
    target = os.path.join(kosit.DATA, "visualization")
    url, digest = VISUALIZATION
    stamp = os.path.join(target, ".sha256")
    if not (os.path.exists(stamp) and open(stamp).read().strip() == digest):
        print("downloading", url)
        data = kosit.read_url(url)
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
    return os.path.join(target, "xsl")


def default_exe():
    name = "LandrixXmlXsltRun.exe" if os.name == "nt" else "LandrixXmlXsltRun"
    return os.path.join(ROOT, "build", "fpc322-win64", name)


def files(doc, stage):
    """The source, Saxon's and the helper's output of a stage."""
    base = os.path.join(WORK, os.path.splitext(os.path.basename(doc))[0])
    ext = {"report": "xml", "xr": "xr.xml", "html": "html"}[stage]
    source = {"report": base + "-reportInput.xml", "xr": doc, "html": base + ".saxon.xr.xml"}[stage]
    if stage == "report":
        return source, base + ".saxon.xml", base + ".ours.xml"
    return source, base + ".saxon." + ext, base + ".ours." + ext


def report_inputs(java, jar, kosit, docs):
    """Lets the validator write the report input of each document."""
    empty = os.path.join(WORK, "stdin.txt")
    open(empty, "w").close()
    cmd = [java, "-jar", jar, "-s", os.path.join(kosit.CONFIG, "scenarios.xml"), "-r", kosit.CONFIG,
           "-o", WORK, "--serialize-report-input"] + docs
    # the validator reads stdin when it is not a file; the report input
    # goes to the current directory. Its exit code counts rejected
    # documents, so only a missing report input is an error.
    with open(empty) as stdin:
        run = subprocess.run(cmd, stdin=stdin, capture_output=True, cwd=WORK, timeout=VALIDATOR_TIMEOUT)
    if not any(os.path.exists(files(doc, "report")[0]) for doc in docs):
        sys.exit("the validator wrote no report input:\n" +
                 (run.stdout + run.stderr).decode("utf-8", "replace")[-2000:])


def visualization_sheet(xsl, doc):
    """The stylesheet for the instance's root element."""
    for _, element in ET.iterparse(doc, events=("start",)):
        local = element.tag.rsplit("}", 1)[-1]
        break
    else:
        return None
    name = {"Invoice": "ubl-invoice-xr.xsl", "CreditNote": "ubl-creditnote-xr.xsl",
            "CrossIndustryInvoice": "cii-xr.xsl"}.get(local)
    return os.path.join(xsl, name) if name else None


def compare(args, sheet, doc, stage, params):
    source, saxon, ours = files(doc, stage)
    if not os.path.exists(source):
        return "no input"
    if not (args.keep_reference and os.path.exists(saxon)):
        # written under another name first, so that an interrupted run
        # leaves no output that --keep-reference would take
        partial = saxon + ".part"
        cmd = [args.java, "-cp", args.jar, "net.sf.saxon.Transform", "-s:" + source, "-xsl:" + sheet,
               "-o:" + partial] + ["+%s=%s" % p for p in params]
        try:
            run = subprocess.run(cmd, stdin=subprocess.DEVNULL, capture_output=True, timeout=RUN_TIMEOUT)
        except subprocess.TimeoutExpired:
            return "Saxon timed out"
        if run.returncode != 0:
            return "Saxon failed: " + run.stderr.decode("utf-8", "replace").strip()[:300]
        os.replace(partial, saxon)
    if os.path.exists(ours):
        os.remove(ours)
    cmd = [args.exe, sheet, source, ours]
    for p in params:
        cmd += ["-d", "%s=%s" % p]
    try:
        run = subprocess.run(cmd, stdin=subprocess.DEVNULL, capture_output=True, timeout=RUN_TIMEOUT)
    except subprocess.TimeoutExpired:
        return "timed out"
    if run.returncode != 0:
        return "failed: " + run.stdout.decode("utf-8", "replace").strip()[:300]
    with open(saxon, "rb") as f:
        want = f.read()
    with open(ours, "rb") as f:
        got = f.read()
    if want == got:
        return "equal"
    i = 0
    while i < min(len(want), len(got)) and want[i] == got[i]:
        i += 1
    return "differs at byte %d" % i


def check(args, report, xsl, doc):
    """The verdicts of the stages for one document."""
    result = []
    if "report" in args.stages:
        result.append(("report", compare(args, report, doc, "report", [("input-document", doc)])))
    if "xr" in args.stages or "html" in args.stages:
        sheet = visualization_sheet(xsl, doc)
        if sheet is None:
            result.append(("xr", "no visualization for the root element"))
            return result
        verdict = compare(args, sheet, doc, "xr", [])
        if "xr" in args.stages:
            result.append(("xr", verdict))
        if "html" in args.stages:
            if os.path.exists(files(doc, "html")[0]):
                result.append(("html", compare(args, os.path.join(xsl, "xrechnung-html.xsl"), doc, "html", [])))
            else:
                result.append(("html", "no XR XML from Saxon"))
    return result


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--java", required=True)
    ap.add_argument("--jar", required=True)
    ap.add_argument("--exe", default=default_exe())
    ap.add_argument("--filter", default="")
    ap.add_argument("--only", choices=STAGES)
    ap.add_argument("--keep-reference", action="store_true")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()
    args.stages = (args.only,) if args.only else STAGES
    args.exe = os.path.abspath(args.exe)
    # the validator runs in WORK: paths given relative to the current directory
    args.jar = os.path.abspath(args.jar)
    if os.path.exists(args.java):
        args.java = os.path.abspath(args.java)
    if not os.path.exists(args.exe):
        sys.exit("helper not found: %s (build tests/LandrixXmlXsltRun.dpr)" % args.exe)
    kosit = kosit_module()
    kosit.fetch()
    xsl = fetch_visualization(kosit)
    report = os.path.join(kosit.CONFIG, "resources", "xrechnung-report.xsl")
    docs = [os.path.join(kosit.INSTANCES, d) for d in kosit.instances() if args.filter in d]
    if not docs:
        sys.exit("no instance matches the filter " + repr(args.filter))
    names = [os.path.splitext(os.path.basename(d))[0] for d in docs]
    if len(set(names)) != len(names):
        sys.exit("instance file names are not unique; the outputs would overwrite each other")
    os.makedirs(WORK, exist_ok=True)
    start = time.time()
    if not args.keep_reference:
        # the outputs of the stages run (html needs Saxon's XR XML)
        for doc in docs:
            for stage in args.stages:
                for path in files(doc, stage)[1:]:
                    if os.path.exists(path):
                        os.remove(path)
            if "html" in args.stages and "xr" not in args.stages:
                for path in files(doc, "xr")[1:]:
                    if os.path.exists(path):
                        os.remove(path)
            if "report" in args.stages and os.path.exists(files(doc, "report")[0]):
                os.remove(files(doc, "report")[0])
        if "report" in args.stages:
            report_inputs(args.java, args.jar, kosit, docs)
    with concurrent.futures.ThreadPoolExecutor(max(1, (os.cpu_count() or 2) - 1)) as pool:
        results = list(pool.map(lambda d: check(args, report, xsl, d), docs))
    failed = 0
    for doc, verdicts in zip(docs, results):
        for stage, verdict in verdicts:
            if verdict != "equal":
                failed += 1
            if verdict != "equal" or args.verbose:
                print("%s %s: %s" % (os.path.basename(doc), stage, verdict))
    for stage in args.stages:
        n = sum(1 for verdicts in results for s, _ in verdicts if s == stage)
        equal = sum(1 for verdicts in results for s, v in verdicts if s == stage and v == "equal")
        print("%s: %d instances, %d equal, %d not" % (stage, n, equal, n - equal))
    print("%d s" % round(time.time() - start))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
