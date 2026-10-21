#!/usr/bin/env python3
"""Generate the content model test data in tests/data/xsdcontent/cases.txt.

Random content models (nested sequences and choices with occurrence
bounds, elements a to f without namespace) and child sequences close to
valid ones are validated with the XML Schema validator of the Java
runtime (tools/XsdOracle.java); its errors for the root element become the
expected results. Models that the JDK rejects (Unique Particle
Attribution) are skipped.

  javac --release 17 -d OUT tools/XsdOracle.java
  python tools/gen-xsdcontent-testdata.py --java PATH/java.exe --classes OUT

Model notation: S(...) is a sequence, C(...) a choice, a letter an element;
a suffix {min,max} (max u = unbounded) gives bounds other than 1..1.

Line format (TAB separated):
  model  children  results
children are comma separated names; results are '|' separated entries
  position:code:message
where position is the index of the child at which the error is reported
(the number of children = at the end of the root). "jdk-exception" as
results means the JDK's validator threw (it does for a counted maxOccurs
that is exceeded; later Java versions report cvc-complex-type.2.4.d with
"No child element '{a}'", as the library does).

The file is committed; rerun this script only when the set changes.
"""

import argparse
import os
import random
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "tests", "data", "xsdcontent")

NAMES = "abcdef"
BOUNDS = [(1, 1)] * 6 + [(0, 1)] * 3 + [(0, None), (1, None), (0, 2), (1, 3), (2, 3), (2, None), (0, 3), (3, 3)]


def rand_particle(rng, depth):
    if depth >= 3 or (depth > 0 and rng.random() < 0.5):
        return ("e", rng.choice(NAMES), rng.choice(BOUNDS))
    kind = rng.choice("SC")
    children = [rand_particle(rng, depth + 1) for _ in range(rng.randint(1, 3))]
    bounds = (1, 1) if depth == 0 and rng.random() < 0.6 else rng.choice(BOUNDS)
    return (kind, children, bounds)


def bounds_text(b):
    if b == (1, 1):
        return ""
    return "{%d,%s}" % (b[0], "u" if b[1] is None else b[1])


def notation(p):
    if p[0] == "e":
        return p[1] + bounds_text(p[2])
    return p[0] + "(" + " ".join(notation(c) for c in p[1]) + ")" + bounds_text(p[2])


def occurs_attrs(b):
    s = ""
    if b[0] != 1:
        s += ' minOccurs="%d"' % b[0]
    if b[1] != 1:
        s += ' maxOccurs="%s"' % ("unbounded" if b[1] is None else b[1])
    return s


def schema_xml(p):
    def emit(q):
        if q[0] == "e":
            return '<xs:element name="%s"%s/>' % (q[1], occurs_attrs(q[2]))
        tag = "xs:sequence" if q[0] == "S" else "xs:choice"
        return "<%s%s>%s</%s>" % (tag, occurs_attrs(q[2]), "".join(emit(c) for c in q[1]), tag)
    return ('<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"><xs:element name="r">'
            "<xs:complexType>%s</xs:complexType></xs:element></xs:schema>" % emit(p))


def sample(rng, p, out):
    lo, hi = p[2]
    top = lo + rng.randint(0, 2)
    if hi is not None:
        top = min(top, hi)
    for _ in range(top):
        if p[0] == "e":
            out.append(p[1])
        elif p[0] == "S":
            for c in p[1]:
                sample(rng, c, out)
        else:
            sample(rng, rng.choice(p[1]), out)


def mutate(rng, children):
    c = list(children)
    op = rng.randint(0, 4)
    if op == 0 and c:
        del c[rng.randrange(len(c))]
    elif op == 1:
        c.insert(rng.randint(0, len(c)), rng.choice(NAMES))
    elif op == 2 and len(c) > 1:
        i = rng.randrange(len(c) - 1)
        c[i], c[i + 1] = c[i + 1], c[i]
    elif op == 3 and c:
        i = rng.randrange(len(c))
        c.insert(i, c[i])
    return c


def run_model(java, classes, tmp, p, instances):
    xsd = os.path.join(tmp, "s.xsd")
    with open(xsd, "w", encoding="utf-8") as f:
        f.write(schema_xml(p))
    files = []
    for k, children in enumerate(instances):
        name = os.path.join(tmp, "i%d.xml" % k)
        with open(name, "w", encoding="utf-8") as f:
            f.write("<r>" + "".join("<%s/>" % c for c in children) + "</r>")
        files.append(name)
    out = subprocess.run([java, "-cp", classes, "XsdOracle", xsd] + files,
                         capture_output=True, encoding="utf-8")
    if out.returncode == 2:
        return None  # schema rejected (UPA)
    if out.returncode != 0:
        sys.exit("oracle failed:\n" + out.stderr[-2000:])
    results = {f: [] for f in files}
    for line in out.stdout.splitlines():
        name, line_no, col, code, message = line.split("\t", 4)
        if code == "jdk-exception":
            results[name] = None
            continue
        if results[name] is None:
            continue
        # <r> is 3 characters, each child <x/> 4: the column after child k
        # (0-based) is 4k + 8, after </r> it is 4n + 8
        results[name].append("%d:%s:%s" % ((int(col) - 8) // 4, code, message))
    return [results[f] for f in files]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--java", required=True)
    ap.add_argument("--classes", required=True, help="directory with the compiled XsdOracle")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--models", type=int, default=1500)
    ap.add_argument("--out", default=OUT, help="output directory (default tests/data/xsdcontent)")
    args = ap.parse_args()
    rng = random.Random(args.seed)
    rows = []
    kept = 0
    with tempfile.TemporaryDirectory() as tmp:
        for _ in range(args.models):
            p = rand_particle(rng, 0)
            instances = []
            for _ in range(6):
                children = []
                sample(rng, p, children)
                if rng.random() < 0.75:
                    children = mutate(rng, children)
                instances.append(children[:12])
            results = run_model(args.java, args.classes, tmp, p, instances)
            if results is None:
                continue
            kept += 1
            for children, res in zip(instances, results):
                rows.append("\t".join([notation(p), ",".join(children),
                                       "jdk-exception" if res is None else "|".join(res)]))
    os.makedirs(args.out, exist_ok=True)
    with open(os.path.join(args.out, "cases.txt"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(rows) + "\n")
    print("%d models kept, %d cases written" % (kept, len(rows)))


if __name__ == "__main__":
    main()
