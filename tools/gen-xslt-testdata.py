#!/usr/bin/env python3
"""Generate the expected results of the XSLT tests with Saxon HE.

Every NAME.xsl in tests/data/xslt (not starting with "_": those are modules
the cases import or include) is a case: Saxon runs it on NAME.xml (or on
<doc/> if there is none) with the classes of the KoSIT validator jar and
writes the output to NAME.out, or the error code to NAME.err. The time zone
is UTC, as the processor's default implicit time zone.

  python tools/gen-xslt-testdata.py --java PATH/java.exe --saxon validator-1.6.3-standalone.jar

The files are committed; rerun this script when a case changes.
"""

import argparse
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "tests", "data", "xslt")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--java", required=True)
    ap.add_argument("--saxon", required=True)
    args = ap.parse_args()
    empty = os.path.join(tempfile.mkdtemp(), "doc.xml")
    with open(empty, "w", encoding="utf-8") as f:
        f.write("<doc/>")
    for name in sorted(os.listdir(DATA)):
        if not name.endswith(".xsl") or name.startswith("_"):
            continue
        case = name[:-4]
        source = os.path.join(DATA, case + ".xml")
        if not os.path.isfile(source):
            source = empty
        out_file = os.path.join(DATA, case + ".out")
        err_file = os.path.join(DATA, case + ".err")
        for f in (out_file, err_file):
            if os.path.exists(f):
                os.remove(f)
        tmp = os.path.join(tempfile.mkdtemp(), "out")
        run = subprocess.run([args.java, "-Duser.timezone=UTC", "-cp", args.saxon, "net.sf.saxon.Transform",
                              "-s:" + source, "-xsl:" + os.path.join(DATA, name), "-o:" + tmp],
                             capture_output=True)
        if run.returncode == 0:
            with open(tmp, "rb") as f:
                data = f.read()
            with open(out_file, "wb") as f:
                f.write(data)
            print("%s: %d bytes" % (case, len(data)))
            continue
        text = run.stderr.decode("utf-8", "replace")
        # the first error code (not a warning such as SXWN9027)
        codes = [c for c in re.findall(r"\b([A-Z]{4}[0-9]{4})\b", text) if not c.startswith("SXWN")]
        if not codes:
            sys.exit("%s failed without an error code:\n%s" % (case, text[-2000:]))
        with open(err_file, "w", encoding="utf-8", newline="\n") as f:
            f.write(codes[0] + "\n")
        print("%s: error %s" % (case, codes[0]))


if __name__ == "__main__":
    main()
