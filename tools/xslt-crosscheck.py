#!/usr/bin/env python3
"""Cross-check the XSLT processor with Saxon HE on the KoSIT stylesheets.

For every document of a KoSIT validator configuration the transformations
below run with Saxon HE (the validator jar) and with the helper
tests/LandrixXmlXsltRun.dpr; their outputs must be equal byte for byte:

  report   the KoSIT validator writes the input of its report stylesheet
           (--serialize-report-input); the report stylesheet it chose (the
           scenario's resources/xrechnung-report.xsl, which imports the
           configuration's default-report.xsl, or the noScenarioReport of
           scenarios.xml) runs on it, with the document as parameter
           input-document (the empty sequence for a document that is not
           well-formed, as the validator passes it)
  xr       (configuration xrechnung) the XRechnung visualization (pinned
           release, downloaded into tests/data/kosit-suite/visualization/)
           turns the document into XR XML (ubl-invoice-xr.xsl,
           ubl-creditnote-xr.xsl, cii-xr.xsl)
  html     (configuration xrechnung) xrechnung-html.xsl turns Saxon's XR
           XML into HTML

The configurations and their documents (all pinned by SHA-256):

  xrechnung  validator-configuration-xrechnung 2026-08-31 and the KoSIT
             XRechnung test suite (both from tools/run-kosit-suite.py)
  bis        validator-configuration-bis 3.0.21 and the examples of
             peppol-bis-invoice-3 (the commit of the Peppol rules)
  zugferd    validator-configuration-zugferd 2.5.2 and the CII instances
             of the KoSIT test suite with the XRechnung profile replaced by
             ZUGFeRD's EN16931 (Comfort) and Extended profiles in turn
             (zf-*.xml; with the XRechnung profile no ZUGFeRD scenario
             matches); with --local also the ZUGFeRD files of
             tests/data/local/zugferd (only names and verdicts are printed,
             no messages)

Each configuration also gets three documents made from one of its own:
err-schema (an unknown element: a schema error), err-wellformed (cut in
half: a processing error, input-document is empty) and err-noscenario (no
scenario matches: the noScenarioReport).

The report inputs hold a time stamp and the document's path, so nothing
of this is committed; the check needs Java and the validator jar.

Usage:
  python tools/xslt-crosscheck.py --java PATH/java.exe
      --jar validator-1.6.3-standalone.jar [--config NAME|all] [--local]
      [--exe PATH] [--filter TEXT] [--only report|xr|html]
      [--keep-reference] [--jobs N] [--verbose]
Build the helper first, e.g.
  ./tools/build.ps1 fpc322-win64 -Program tests/LandrixXmlXsltRun.dpr -NoRun
--config defaults to xrechnung. --keep-reference reuses report inputs and
Saxon outputs from an earlier run (build/xslt-crosscheck/<config>/; only
valid while the documents, the stylesheets and the jar are the same; a
run without it removes them first). --jobs: parallel runs (default the
number of processors less one; each Saxon run is a Java process of its
own, fewer help when memory is short). Exit code: 0 if every output is
equal, 1 otherwise or if nothing was checked.
"""

import argparse
import concurrent.futures
import hashlib
import importlib.util
import io
import os
import re
import xml.etree.ElementTree as ET
import shutil
import subprocess
import sys
import time
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = os.path.join(ROOT, "build", "xslt-crosscheck")
LOCAL = os.path.join(ROOT, "tests", "data", "local")
VISUALIZATION = ("https://github.com/itplr-kosit/xrechnung-visualization/releases/download/v2026-01-31/"
                 "xrechnung-3.0.2-visualization-2026-01-31.zip",
                 "af9f0be80db3035d9beaeee4c066bdc7a3ccbec2e25a428c460c25b9f894b383")
# the configurations besides xrechnung (that one comes with the KoSIT suite)
CONFIGS = {
    "bis": ("https://github.com/itplr-kosit/validator-configuration-bis/releases/download/release-3.0.21/"
            "validation-configuration-bis-3.0.21.zip",
            "399395de5f6240a76ccc5751e4ee9dd329e37f5f7cfe4ee5c93188294ce8cd68"),
    "zugferd": ("https://github.com/LandrixSoftware/validator-configuration-zugferd/releases/download/"
                "validation-configuration-zugferd-2.5.2/validation-configuration-zugferd-2.5.2-2026-10-15.zip",
                "43487e76edad8b7276da8266f0b1473b597be23554d1ab7fb1c828a03036eafa"),
}
CONFIG_NAMES = ("xrechnung", "bis", "zugferd")
PEPPOL = ("https://raw.githubusercontent.com/OpenPEPPOL/peppol-bis-invoice-3/"
          "806866bd2bd91d7e9623b68f08164e8fbe9e67a0/rules/examples/")
PEPPOL_EXAMPLES = [
    ("Allowance-example.xml", "aa3df18eb8c634624637eb229891d989c5cfb7cd0d08894ff8e58c58f247ea5b"),
    ("Vat-category-S.xml", "59f96ae9a77ed3eda4ac17f499994fbd1b050432edf3bb8c117d7f3bca8d5f95"),
    ("base-creditnote-correction.xml", "08e0ad82e0dbe7e16d7533c01761843343a56954ea24881d0f7f1cce06f8879e"),
    ("base-example.xml", "1b7cc3ff1834c8963f2c93f30f171b58002cbf0b2c52dc8765e7e83aebb9f7c9"),
    ("base-example_profile02.xml", "97e9dd5fc1747a9a2447b38bae8d1de3317d2636714369bdd99ba7dd1fb0ee1a"),
    ("base-negative-inv-correction.xml", "000781ee8cb7794a140bb1308f7f7a2c9ded3623571b4297aef38423971ab5a4"),
    ("sales-order-example.xml", "cdb84e4ce1a770f6e4a8949dcbe37493bc37aeded5232b592a1a48feb221a504"),
    ("vat-category-E.xml", "4f2f20de65a8c088bba6c43177c75b5066bf30f54b996bc1729a82097a6591db"),
    ("vat-category-O.xml", "212c4eede960a775f8e79dca6cd6430e6f8c105560fbfdeaa03d5e6587eaa1ec"),
    ("vat-category-Z.xml", "fed3f3f393591e1c628f2da4a3aa77e8c66e4ed8ed4368e18837782beab60daa"),
]
SCN = "{http://www.xoev.de/de/validator/framework/1/scenarios}"
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


def fetch_zip(kosit, url, digest, target):
    """A pinned archive unpacked into target (skipped when its stamp matches)."""
    stamp = os.path.join(target, ".sha256")
    if os.path.exists(stamp) and open(stamp).read().strip() == digest:
        return
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


def fetch_visualization(kosit):
    """The visualization package; its xsl folder."""
    target = os.path.join(kosit.DATA, "visualization")
    fetch_zip(kosit, VISUALIZATION[0], VISUALIZATION[1], target)
    return os.path.join(target, "xsl")


def fetch_config(kosit, name):
    """The folder of a configuration (the one with scenarios.xml)."""
    if name == "xrechnung":
        return kosit.CONFIG
    url, digest = CONFIGS[name]
    target = os.path.join(kosit.DATA, "configuration-" + name)
    fetch_zip(kosit, url, digest, target)
    for folder, _, files in os.walk(target):
        if "scenarios.xml" in files:
            return folder
    sys.exit("no scenarios.xml in " + url)


def fetch_peppol(kosit):
    """The Peppol examples, each checked by SHA-256."""
    target = os.path.join(kosit.DATA, "peppol-examples")
    os.makedirs(target, exist_ok=True)
    result = []
    for name, digest in PEPPOL_EXAMPLES:
        path = os.path.join(target, name)
        if not (os.path.exists(path) and hashlib.sha256(open(path, "rb").read()).hexdigest() == digest):
            data = kosit.read_url(PEPPOL + name)
            got = hashlib.sha256(data).hexdigest()
            if got != digest:
                sys.exit("%s has SHA-256 %s, expected %s" % (PEPPOL + name, got, digest))
            with open(path, "wb") as f:
                f.write(data)
        result.append(path)
    return result


def default_exe():
    name = "LandrixXmlXsltRun.exe" if os.name == "nt" else "LandrixXmlXsltRun"
    return os.path.join(ROOT, "build", "fpc322-win64", name)


def root_name(doc):
    """The local name of the root element (None if the document breaks
    before it)."""
    try:
        for _, element in ET.iterparse(doc, events=("start",)):
            return element.tag.rsplit("}", 1)[-1]
    except ET.ParseError:
        return None
    return None


def well_formed(doc):
    try:
        ET.parse(doc)
        return True
    except ET.ParseError:
        return False


def error_documents(base, folder):
    """err-schema, err-wellformed and err-noscenario made from base."""
    os.makedirs(folder, exist_ok=True)
    with open(base, encoding="utf-8") as f:
        text = f.read()
    # the start tag of the root element: the first "<" that does not open
    # a declaration, comment or processing instruction
    start = 0
    while True:
        start = text.index("<", start)
        if text[start + 1] not in "?!":
            break
        start += 1
    end = text.index(">", start) + 1
    made = {
        "err-schema.xml": text[:end] + "<Unknown>x</Unknown>" + text[end:],
        "err-wellformed.xml": text[:len(text) // 2],
        "err-noscenario.xml": '<?xml version="1.0" encoding="UTF-8"?><other xmlns="urn:example:none"><a/></other>',
    }
    result = []
    for name, content in made.items():
        path = os.path.join(folder, name)
        with open(path, "w", encoding="utf-8", newline="") as f:
            f.write(content)
        result.append(path)
    return result


# the profiles (ram:GuidelineSpecifiedDocumentContextParameter/ram:ID) that
# select a scenario of the ZUGFeRD configuration
GUIDELINE = re.compile(r"(<(?:\w+:)?GuidelineSpecifiedDocumentContextParameter>\s*<(?:\w+:)?ID>)[^<]*(<)")
ZUGFERD_PROFILES = ("urn:cen.eu:en16931:2017",
                    "urn:cen.eu:en16931:2017#conformant#urn:factur-x.eu:1p0:extended")


def zugferd_variants(docs, folder):
    """The CII invoices with a ZUGFeRD profile (Comfort and Extended in turn)."""
    os.makedirs(folder, exist_ok=True)
    result = []
    for i, doc in enumerate(docs):
        with open(doc, encoding="utf-8", newline="") as f:
            text = f.read()
        text, n = GUIDELINE.subn(lambda m: m.group(1) + ZUGFERD_PROFILES[i % 2] + m.group(2), text)
        if n != 1:
            sys.exit("%s: expected one GuidelineSpecifiedDocumentContextParameter" % doc)
        path = os.path.join(folder, "zf-" + os.path.basename(doc))
        with open(path, "w", encoding="utf-8", newline="") as f:
            f.write(text)
        result.append(path)
    return result


def documents(kosit, name, args, work):
    """The documents of a configuration (with the error documents last)."""
    if name == "xrechnung":
        docs = [os.path.join(kosit.INSTANCES, d) for d in kosit.instances()]
    elif name == "bis":
        docs = fetch_peppol(kosit)
    else:
        docs = [os.path.join(kosit.INSTANCES, d) for d in kosit.instances()]
        docs = [d for d in docs if root_name(d) == "CrossIndustryInvoice"]
        docs = zugferd_variants(docs, os.path.join(work, "variants"))
        if args.local:
            folder = os.path.join(LOCAL, "zugferd")
            if os.path.isdir(folder):
                docs += [os.path.join(folder, f) for f in sorted(os.listdir(folder)) if f.endswith(".xml")]
    base = next(d for d in docs if root_name(d) in ("Invoice", "CrossIndustryInvoice") and well_formed(d))
    docs += error_documents(base, os.path.join(work, "errors"))
    return [d for d in docs if args.filter in os.path.basename(d)]


def files(work, doc, stage):
    """The source, Saxon's and the helper's output of a stage."""
    base = os.path.join(work, os.path.splitext(os.path.basename(doc))[0])
    ext = {"report": "xml", "xr": "xr.xml", "html": "html"}[stage]
    source = {"report": base + "-reportInput.xml", "xr": doc, "html": base + ".saxon.xr.xml"}[stage]
    return source, base + ".saxon." + ext, base + ".ours." + ext


def report_inputs(java, jar, config, work, docs):
    """Lets the validator write the report input of each document."""
    empty = os.path.join(work, "stdin.txt")
    open(empty, "w").close()
    cmd = [java, "-jar", jar, "-s", os.path.join(config, "scenarios.xml"), "-r", config,
           "-o", work, "--serialize-report-input"] + docs
    # the validator reads stdin when it is not a file; the report input
    # goes to the current directory. Its exit code counts rejected
    # documents, so only a missing report input is an error.
    with open(empty) as stdin:
        run = subprocess.run(cmd, stdin=stdin, capture_output=True, cwd=work, timeout=VALIDATOR_TIMEOUT)
    if not any(os.path.exists(files(work, doc, "report")[0]) for doc in docs):
        sys.exit("the validator wrote no report input:\n" +
                 (run.stdout + run.stderr).decode("utf-8", "replace")[-2000:])


def report_sheet(config, report_input):
    """The report stylesheet the validator chose: the scenario's
    createReport, else the noScenarioReport of the configuration."""
    for el in ET.parse(report_input).getroot().iter():
        if el.tag == SCN + "createReport":
            loc = el.find(SCN + "resource/" + SCN + "location")
            if loc is not None:
                return os.path.join(config, loc.text.strip())
    root = ET.parse(os.path.join(config, "scenarios.xml")).getroot()
    loc = root.find(SCN + "noScenarioReport/" + SCN + "resource/" + SCN + "location")
    return os.path.join(config, loc.text.strip())


def visualization_sheet(xsl, doc):
    """The stylesheet for the instance's root element."""
    name = {"Invoice": "ubl-invoice-xr.xsl", "CreditNote": "ubl-creditnote-xr.xsl",
            "CrossIndustryInvoice": "cii-xr.xsl"}.get(root_name(doc))
    return os.path.join(xsl, name) if name else None


def compare(args, sheet, paths, params):
    """params: (kind, name, value), kind "d" (a document) or "x" (XPath)."""
    source, saxon, ours = paths
    if not os.path.exists(source):
        return "no input"
    if not (args.keep_reference and os.path.exists(saxon)):
        # written under another name first, so that an interrupted run
        # leaves no output that --keep-reference would take
        partial = saxon + ".part"
        cmd = [args.java, "-cp", args.jar, "net.sf.saxon.Transform", "-s:" + source, "-xsl:" + sheet,
               "-o:" + partial] + [("+" if k == "d" else "?") + "%s=%s" % (n, v) for k, n, v in params]
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
    for k, n, v in params:
        cmd += ["-" + k, "%s=%s" % (n, v)]
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


def check(args, name, config, work, xsl, doc):
    """The verdicts of the stages for one document."""
    result = []
    if "report" in args.stages:
        paths = files(work, doc, "report")
        if not os.path.exists(paths[0]):
            result.append(("report", "no input"))
        else:
            if well_formed(doc):
                param = ("d", "input-document", doc)
            else:
                param = ("x", "input-document", "()")
            result.append(("report", compare(args, report_sheet(config, paths[0]), paths, [param])))
    if name != "xrechnung" or os.path.basename(doc).startswith("err-"):
        return result
    if "xr" in args.stages or "html" in args.stages:
        sheet = visualization_sheet(xsl, doc)
        if sheet is None:
            result.append(("xr", "no visualization for the root element"))
            return result
        verdict = compare(args, sheet, files(work, doc, "xr"), [])
        if "xr" in args.stages:
            result.append(("xr", verdict))
        if "html" in args.stages:
            if os.path.exists(files(work, doc, "html")[0]):
                result.append(("html", compare(args, os.path.join(xsl, "xrechnung-html.xsl"),
                                               files(work, doc, "html"), [])))
            else:
                result.append(("html", "no XR XML from Saxon"))
    return result


def run_config(args, kosit, xsl, name):
    """Checks one configuration; the number of outputs that are not equal."""
    config = fetch_config(kosit, name)
    work = os.path.join(WORK, name)
    os.makedirs(work, exist_ok=True)
    docs = documents(kosit, name, args, work)
    if not docs:
        print("%s: no document matches the filter %r" % (name, args.filter))
        return 0, 0
    names = [os.path.splitext(os.path.basename(d))[0] for d in docs]
    if len(set(names)) != len(names):
        sys.exit("%s: document file names are not unique; the outputs would overwrite each other" % name)
    if not args.keep_reference:
        for doc in docs:
            for stage in STAGES:
                for path in files(work, doc, stage)[1:]:
                    if os.path.exists(path):
                        os.remove(path)
            if "report" in args.stages and os.path.exists(files(work, doc, "report")[0]):
                os.remove(files(work, doc, "report")[0])
        if "report" in args.stages:
            report_inputs(args.java, args.jar, config, work, docs)
    with concurrent.futures.ThreadPoolExecutor(args.jobs) as pool:
        results = list(pool.map(lambda d: check(args, name, config, work, xsl, d), docs))
    failed = 0
    for doc, verdicts in zip(docs, results):
        for stage, verdict in verdicts:
            if verdict != "equal":
                failed += 1
                if doc.startswith(LOCAL):
                    # a message may quote the file: the kind of failure only
                    verdict = verdict.split(":")[0]
            if verdict != "equal" or args.verbose:
                print("%s %s %s: %s" % (name, os.path.basename(doc), stage, verdict))
    for stage in args.stages:
        n = sum(1 for verdicts in results for s, _ in verdicts if s == stage)
        if n:
            equal = sum(1 for verdicts in results for s, v in verdicts if s == stage and v == "equal")
            print("%s %s: %d documents, %d equal, %d not" % (name, stage, n, equal, n - equal))
    return failed, sum(len(v) for v in results)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--java", required=True)
    ap.add_argument("--jar", required=True)
    ap.add_argument("--config", choices=CONFIG_NAMES + ("all",), default="xrechnung")
    ap.add_argument("--local", action="store_true")
    ap.add_argument("--exe", default=default_exe())
    ap.add_argument("--filter", default="")
    ap.add_argument("--only", choices=STAGES)
    ap.add_argument("--keep-reference", action="store_true")
    ap.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 2) - 1))
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()
    args.stages = (args.only,) if args.only else STAGES
    if args.jobs < 1:
        sys.exit("--jobs must be at least 1")
    args.exe = os.path.abspath(args.exe)
    # the validator runs in the work folder: paths given relative to the
    # current directory
    args.jar = os.path.abspath(args.jar)
    if os.path.exists(args.java):
        args.java = os.path.abspath(args.java)
    if not os.path.exists(args.exe):
        sys.exit("helper not found: %s (build tests/LandrixXmlXsltRun.dpr)" % args.exe)
    kosit = kosit_module()
    kosit.fetch()
    xsl = fetch_visualization(kosit)
    start = time.time()
    failed = checked = 0
    for name in (CONFIG_NAMES if args.config == "all" else (args.config,)):
        f, n = run_config(args, kosit, xsl, name)
        failed += f
        checked += n
    print("%d s" % round(time.time() - start))
    return 1 if failed or not checked else 0


if __name__ == "__main__":
    sys.exit(main())
