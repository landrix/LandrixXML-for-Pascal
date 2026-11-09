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

With --upa N it writes tests/data/xsdcontent/upa.txt instead: N random
models over fewer names, also with ##any wildcards ("*" in the notation),
and the verdict of the JDK's Unique Particle Attribution check, one line
per model:
  model  verdict
verdict is "ok" or "cos-nonambig:X|Y" with the two particles Xerces names
(a name or WC[##any]). Models rejected for another reason are skipped.

With --all N it writes tests/data/xsdcontent/all.txt instead, in the
format of cases.txt: N random all groups (A(...), elements a to f that
occur at most once, the group itself optional or not) and child sequences
in any order, with missing, repeated and unknown elements.

The files are committed; rerun this script only when the set changes.
"""

import argparse
import os
import random
import re
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
    if p[0] == "w":
        return "*" + bounds_text(p[2])
    return p[0] + "(" + " ".join(notation(c) for c in p[1]) + ")" + bounds_text(p[2])


TAGS = {"S": "xs:sequence", "C": "xs:choice", "A": "xs:all"}


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
        if q[0] == "w":
            return '<xs:any processContents="skip"%s/>' % occurs_attrs(q[2])
        tag = TAGS[q[0]]
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


UPA_NAMES = "abc"


def rand_upa_particle(rng, depth):
    if depth >= 3 or (depth > 0 and rng.random() < 0.5):
        if rng.random() < 0.1:
            return ("w", None, rng.choice(BOUNDS))
        return ("e", rng.choice(UPA_NAMES), rng.choice(BOUNDS))
    kind = rng.choice("SC")
    children = [rand_upa_particle(rng, depth + 1) for _ in range(rng.randint(1, 3))]
    bounds = (1, 1) if depth == 0 and rng.random() < 0.6 else rng.choice(BOUNDS)
    return (kind, children, bounds)


def upa_verdict(java, classes, tmp, p):
    xsd = os.path.join(tmp, "s.xsd")
    with open(xsd, "w", encoding="utf-8") as f:
        f.write(schema_xml(p))
    doc = os.path.join(tmp, "d.xml")
    with open(doc, "w", encoding="utf-8") as f:
        f.write("<r/>")
    out = subprocess.run([java, "-cp", classes, "XsdOracle", xsd, doc],
                         capture_output=True, encoding="utf-8")
    if out.returncode == 0:
        return "ok"
    m = re.search(r"cos-nonambig: (.*?) and (.*?) \(or elements", out.stderr)
    if out.returncode == 2 and m:
        return "cos-nonambig:%s|%s" % (m.group(1), m.group(2))
    return None


def main_upa(args):
    rng = random.Random(args.seed + 1000)
    rows = []
    seen = set()
    with tempfile.TemporaryDirectory() as tmp:
        while len(rows) < args.upa:
            p = rand_upa_particle(rng, 0)
            text = notation(p)
            if text in seen:
                continue
            seen.add(text)
            verdict = upa_verdict(args.java, args.classes, tmp, p)
            if verdict is not None:
                rows.append(text + "\t" + verdict)
    os.makedirs(args.out, exist_ok=True)
    with open(os.path.join(args.out, "upa.txt"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(rows) + "\n")
    print("%d models, %d ambiguous" % (len(rows), sum(1 for r in rows if "\tcos-" in r)))


def main_all(args):
    rng = random.Random(args.seed + 2000)
    rows = []
    kept = 0
    with tempfile.TemporaryDirectory() as tmp:
        for _ in range(args.all):
            names = rng.sample(NAMES, rng.randint(1, 5))
            children = [("e", n, rng.choice([(1, 1), (1, 1), (0, 1)])) for n in names]
            p = ("A", children, rng.choice([(1, 1), (1, 1), (0, 1)]))
            instances = []
            for _ in range(8):
                present = [c[1] for c in children if c[2][0] == 1 or rng.random() < 0.5]
                rng.shuffle(present)
                if p[2][0] == 0 and rng.random() < 0.2:
                    present = []
                if rng.random() < 0.6:
                    present = mutate(rng, present)
                instances.append(present[:12])
            results = run_model(args.java, args.classes, tmp, p, instances)
            if results is None:
                continue
            kept += 1
            for kids, res in zip(instances, results):
                rows.append("\t".join([notation(p), ",".join(kids), "|".join(res)]))
    os.makedirs(args.out, exist_ok=True)
    with open(os.path.join(args.out, "all.txt"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(rows) + "\n")
    print("%d models kept, %d cases written" % (kept, len(rows)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--java", required=True)
    ap.add_argument("--classes", required=True, help="directory with the compiled XsdOracle")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--models", type=int, default=1500)
    ap.add_argument("--out", default=OUT, help="output directory (default tests/data/xsdcontent)")
    ap.add_argument("--upa", type=int, default=0, help="write upa.txt with this many models")
    ap.add_argument("--all", type=int, default=0, help="write all.txt with this many all groups")
    args = ap.parse_args()
    if args.upa:
        main_upa(args)
        return
    if args.all:
        main_all(args)
        return
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
