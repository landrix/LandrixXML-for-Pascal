"""The Saxon jars the committed reference data comes from.

tests/data/saxon-oracle.txt lists them by SHA-256. Every tool that runs
Saxon to write or compare reference data calls check() with the jar it was
given and stops if the jar is not listed, so that data from another Saxon
version is never committed by accident. To move to a new Saxon on purpose,
set LANDRIX_OTHER_SAXON=1 (the tools then only warn), regenerate and
compare the data, and add the jar to the list with the regenerated files.
"""

import hashlib
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIST = os.path.join(ROOT, "tests", "data", "saxon-oracle.txt")
OVERRIDE = "LANDRIX_OTHER_SAXON"


def pinned():
    """SHA-256 (lower case) -> description of every listed jar."""
    jars = {}
    with open(LIST, encoding="ascii") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            fields = line.split(None, 2)
            if len(fields) < 2:
                raise ValueError("%s: bad line %r" % (LIST, line))
            jars[fields[0].lower()] = " ".join(fields[1:])
    return jars


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def check(path):
    """Stops the tool unless path (a jar with Saxon, or None for none) is
    one of the pinned jars; with LANDRIX_OTHER_SAXON=1 it only warns."""
    if path is None:
        return
    if not os.path.isfile(path):
        sys.exit("Saxon jar not found: %s" % path)
    digest = sha256(path)
    jars = pinned()
    if digest in jars:
        return
    msg = ("%s (sha256 %s) is not one of the Saxon jars the reference data comes from "
           "(tests/data/saxon-oracle.txt: %s)" % (path, digest, "; ".join(sorted(jars.values()))))
    if os.environ.get(OVERRIDE) == "1":
        print("warning: " + msg, file=sys.stderr)
        return
    sys.exit(msg + "; set %s=1 to use it anyway (moving to a new Saxon)" % OVERRIDE)
