#!/usr/bin/env python3
"""Check whether a Java runtime's XML Schema validator (Xerces, the one
the KoSIT validator uses) still gives the results the committed test data
was generated with. Run it with every new JDK and whenever the KoSIT or
Mustang validators move to another Java version:
  python tools/check-xerces-drift.py --jdk PATH-TO-JDK
      [--kosit-jar validator-1.6.3-standalone.jar]
      [--saxon validator-1.6.3-standalone.jar --blocks DIR]
In a temporary git worktree of HEAD (the working tree is not touched) it
compiles tools/XsdOracle.java with that JDK, reruns the generators that
ask the JDK (xsdtypes, xsdvalidator, xsdcontent with the UPA models),
checks tests/data/xsdschema/rules.txt (tools/check-xsdrules.py) and, if
given, regenerates the KoSIT reference and the regex block table; then it
reports every file that came out differently. --in-place runs in the
working tree instead (the generators overwrite the files there; restore
them with git checkout; files changed before the run only count if the
run changes them again). tests/data/xerces-oracle.txt records the runtime
the committed data comes from; --record writes it for the given JDK
(only after a run without differences).
Exit code 0 if nothing differs.
"""
import argparse
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RECORD = os.path.join("tests", "data", "xerces-oracle.txt")
EXE = ".exe" if os.name == "nt" else ""


def runtime(java):
    p = subprocess.run([java, "-XshowSettings:properties", "-version"], capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    props = {}
    for line in p.stderr.splitlines():
        line = line.strip()
        if " = " in line:
            key, value = line.split(" = ", 1)
            props[key] = value
    return "%s (%s)" % (props.get("java.runtime.version", "?"), props.get("java.vendor", "?"))


def recorded():
    path = os.path.join(ROOT, RECORD)
    if not os.path.exists(path):
        return None
    with open(path, encoding="ascii") as f:
        for line in f:
            if line.startswith("runtime "):
                return line[len("runtime "):].strip()
    return None


def snapshot(tree):
    """The files that differ from HEAD (also new ones, not ignored ones), with
    a hash of their content (None for a deleted file)."""
    out = subprocess.run(["git", "-C", tree, "status", "--porcelain", "-z", "--untracked-files=all"],
                         capture_output=True, check=True).stdout.decode("utf-8")
    result = {}
    entries = out.split("\0")
    i = 0
    while i < len(entries):
        entry = entries[i]
        i += 1
        if len(entry) < 4:
            continue
        if entry[0] in "RC":
            i += 1  # the original path of a rename or copy follows
        path = entry[3:]
        full = os.path.join(tree, path)
        if os.path.exists(full):
            with open(full, "rb") as f:
                result[path] = hashlib.sha256(f.read()).hexdigest()
        else:
            result[path] = None
    return result


def run(step, cmd, cwd):
    print("-- " + step, flush=True)
    p = subprocess.run(cmd, cwd=cwd)
    if p.returncode != 0:
        print("   failed with exit code %d" % p.returncode)
    return p.returncode == 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--jdk", required=True, help="JDK folder (with bin/java and bin/javac)")
    ap.add_argument("--kosit-jar", help="KoSIT validator jar: also regenerate the KoSIT reference")
    ap.add_argument("--saxon", help="jar with Saxon HE for the regex block table (with --blocks)")
    ap.add_argument("--blocks", help="folder with the Unicode Blocks files (see gen-regex-blocks.py)")
    ap.add_argument("--in-place", action="store_true", help="run in the working tree instead of a worktree")
    ap.add_argument("--record", action="store_true", help="write tests/data/xerces-oracle.txt for this JDK")
    args = ap.parse_args()
    # the steps run in another folder: absolute paths
    for name in ("jdk", "kosit_jar", "saxon", "blocks"):
        if getattr(args, name):
            setattr(args, name, os.path.abspath(getattr(args, name)))
    java = os.path.join(args.jdk, "bin", "java" + EXE)
    javac = os.path.join(args.jdk, "bin", "javac" + EXE)
    current = runtime(java)
    before = recorded()
    print("runtime of the committed data: %s" % (before or "not recorded"))
    print("runtime checked now:           %s" % current)
    tmp = tempfile.mkdtemp(prefix="xerces-drift-")
    tree = ROOT if args.in_place else os.path.join(tmp, "tree")
    ok = True
    try:
        if not args.in_place:
            subprocess.run(["git", "-C", ROOT, "worktree", "add", "--detach", "--quiet", tree, "HEAD"], check=True)
        before_run = snapshot(tree)
        classes = os.path.join(tmp, "classes")
        subprocess.run([javac, "--release", "17", "-d", classes, os.path.join(tree, "tools", "XsdOracle.java")],
                       check=True)
        oracle = ["--java", java, "--classes", classes]
        py = sys.executable
        ok &= run("simple types", [py, "tools/gen-xsdtypes-testdata.py"] + oracle, tree)
        ok &= run("validator cases", [py, "tools/gen-xsdvalidator-testdata.py"] + oracle, tree)
        ok &= run("content models", [py, "tools/gen-xsdcontent-testdata.py"] + oracle, tree)
        ok &= run("Unique Particle Attribution", [py, "tools/gen-xsdcontent-testdata.py", "--upa", "1200"] + oracle,
                  tree)
        ok &= run("schema rules", [py, "tools/check-xsdrules.py"] + oracle, tree)
        if args.kosit_jar:
            ok &= run("KoSIT reference", [py, "tools/run-kosit-suite.py", "--generate", "--java", java,
                                          "--jar", args.kosit_jar], tree)
        if args.saxon and args.blocks:
            ok &= run("regex block table", [py, "tools/gen-regex-blocks.py", "--java", java, "--javac", javac,
                                            "--saxon", args.saxon, "--blocks", args.blocks], tree)
        after_run = snapshot(tree)
        # a path missing from a snapshot equals HEAD
        changed = sorted(path for path in set(before_run) | set(after_run)
                         if before_run.get(path, "HEAD") != after_run.get(path, "HEAD"))
        if changed:
            ok = False
            print("-- files the generators changed:")
            for path in changed:
                print("   " + path)
        print("no differences" if ok else "DIFFERENCES: the JDK's results changed (or a step failed)")
        if args.record:
            if not ok:
                print("not recorded: there are differences")
            else:
                with open(os.path.join(ROOT, RECORD), "w", encoding="ascii", newline="\n") as f:
                    f.write("# The Java runtime whose XML Schema validator (Xerces) produced the\n"
                            "# committed reference data; checked with tools/check-xerces-drift.py.\n"
                            "runtime %s\n" % current)
                print("recorded %s in %s" % (current, RECORD))
    finally:
        if not args.in_place:
            subprocess.run(["git", "-C", ROOT, "worktree", "remove", "--force", tree])
        shutil.rmtree(tmp, ignore_errors=True)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
