#!/usr/bin/env python3
"""Generate the expected results of the XPath evaluator tests.

Every folder in tests/data/xpath holds a document (d.xml) and cases (c.txt:
lines "ns PREFIX URI" and "expr EXPRESSION", evaluated with the document node
as context item). This script evaluates them with Saxon HE (tools/XPathOracle.java,
with the Saxon classes of the KoSIT validator jar, in the time zone UTC, so
that Saxon's implicit time zone is the evaluator's default) and writes
expected.txt:

  # EXPRESSION
  TYPE VALUE      per atomic item
  node LOCATION   per node (SchXslt's location format)
  error CODE      a static or dynamic error

  javac -cp validator-1.6.3-standalone.jar -d OUT tools/XPathOracle.java
  python tools/gen-xpath-testdata.py --java PATH/java.exe --classes OUT --saxon validator-1.6.3-standalone.jar

The files are committed; rerun this script when a folder changes.
"""

import argparse
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "tests", "data", "xpath")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--java", required=True)
    ap.add_argument("--classes", required=True)
    ap.add_argument("--saxon", required=True)
    args = ap.parse_args()
    cp = os.pathsep.join([args.classes, args.saxon])
    for case in sorted(os.listdir(DATA)):
        folder = os.path.join(DATA, case)
        if not os.path.isfile(os.path.join(folder, "c.txt")):
            continue
        # the implicit time zone UTC, the evaluator's default
        out = subprocess.run([args.java, "-Duser.timezone=UTC", "-cp", cp, "XPathOracle", os.path.join(folder, "d.xml"),
                              os.path.join(folder, "c.txt")], capture_output=True)
        if out.returncode != 0:
            sys.exit("oracle failed for %s:\n%s" % (case, out.stderr.decode("utf-8", "replace")[-2000:]))
        text = out.stdout.decode("utf-8").replace("\r\n", "\n")
        with open(os.path.join(folder, "expected.txt"), "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        print("%s: %d cases" % (case, text.count("\n# ") + (1 if text.startswith("# ") else 0)))


if __name__ == "__main__":
    main()
