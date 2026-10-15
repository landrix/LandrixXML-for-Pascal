#!/usr/bin/env python3
"""Differential fuzzing of LandrixXml against expat.

Takes seed documents, derives randomly damaged variants from them and reads
every variant with the LandrixXmlConformance helper (reader, writer round
trip, DOM round trip) and with Python's expat (namespace processing on).
Reported as failures:
  - anything else than a clean ELandrixXmlError (EXC), a crash or a hang
    of the helper (the culprit is isolated by bisection),
  - writer or DOM round-trip failures (RTFAIL),
  - a variant accepted by one parser and rejected by the other, unless the
    difference is one of the documented deviations (DOCTYPE present,
    encodings outside the supported set, UTF-16 without BOM, version number
    and BOM/declaration checks expat does not make, XML 1.0 fifth-edition
    name characters, nesting depth limit).

Seeds: the W3C suite documents without DOCTYPE that expat accepts
(tests/data/xmlconf-suite, downloaded by run-xmlconf.py) and the committed
files below tests/data. With --local, also tests/data/local; variants with
local data are kept only in the git-ignored build folder, and messages that
may quote names are shortened.

Failing variants are written to build/fuzz-findings/ (git-ignored) with the
seed name and the mutation list; the report prints only names, the
classification and positions.

Usage:
  python tools/fuzz.py [--exe PATH] [--count N] [--seed N] [--local]
Build the helper first, preferably with range and overflow checks, e.g.
  ./tools/build.ps1 fpc331-winarm-checked -Program tests/LandrixXmlConformance.dpr -NoRun
Exit code: 0 if there is nothing unexplained.
"""

import argparse
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile
import time
import xml.parsers.expat

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "tests", "data")
SUITE = os.path.join(DATA, "xmlconf-suite", "xmlconf")
LOCAL = os.path.join(DATA, "local")
FINDINGS = os.path.join(ROOT, "build", "fuzz-findings")
CODES = {0: "None", 1: "General", 2: "InvalidArgument", 3: "InvalidOperation",
         4: "InvalidUnicode", 5: "Encoding", 6: "Syntax", 7: "Namespace",
         8: "InvalidChar", 9: "Limit", 10: "Write", 11: "Conversion", 12: "UnexpectedElement"}
SUPPORTED_ENCODINGS = {"utf-8", "utf8", "utf-16", "utf16", "iso-8859-1", "latin1",
                       "iso_8859-1", "windows-1252", "cp1252", "iso-8859-15",
                       "us-ascii", "ascii"}
MAX_SEED_SIZE = 256 * 1024

# Fragments that tend to reach rarely used paths of a tokenizer
TOKENS = [b"<", b">", b"/>", b"</", b"&", b";", b"&amp;", b"&lt;", b"&#", b"&#x",
          b"&#0;", b"&#x10FFFF;", b"&#x110000;", b"&#xD800;", b"&#65;", b"&#x41;",
          b"<!--", b"-->", b"--", b"<![CDATA[", b"]]>", b"]]", b"<?", b"?>",
          b"<?xml version='1.0'?>", b"<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>",
          b"<?xml version=\"1.0\" encoding=\"UTF-16\"?>", b"<?pi data?>", b"<!DOCTYPE a>",
          b"xmlns=\"\"", b" xmlns:p=\"urn:p\"", b" xmlns:p=\"\"", b" xml:space=\"preserve\"",
          b" xmlns:xml=\"http://www.w3.org/XML/1998/namespace\"", b" a=\"1\"", b" a='1'",
          b" p:a=\"1\"", b"<p:x>", b"</p:x>", b"<a>", b"</a>", b"<a/>", b"=", b"\"", b"'",
          b"\t", b"\r", b"\n", b"\r\n", b" ", b"\x00", b"\x01", b"\x1f", b"\x7f",
          b"\x80", b"\xc0\x80", b"\xc3", b"\xc3\xa4", b"\xe2\x82\xac", b"\xed\xa0\x80",
          b"\xef\xbb\xbf", b"\xef\xbf\xbe", b"\xef\xbf\xbf", b"\xf0\x9f\x98\x80",
          b"\xf4\x90\x80\x80", b"\xff", b"\xfe\xff", b"\xff\xfe", b":", b"::", b"-", b".",
          b"\xc2\xa0", b"\xe2\x80\xa8"]


def expat_ok(data):
    # chr(1) cannot occur in XML 1.0 names or URIs; with " " expat rejects
    # every namespace URI that contains white space
    p = xml.parsers.expat.ParserCreate(namespace_separator=chr(1))
    p.SetParamEntityParsing(xml.parsers.expat.XML_PARAM_ENTITY_PARSING_NEVER)
    try:
        p.Parse(data, True)
        return True, ""
    except xml.parsers.expat.ExpatError as e:
        msg = "line %d, column %d: %s" % (e.lineno, e.offset + 1,
                                          xml.parsers.expat.ErrorString(e.code))
        invalid_token = xml.parsers.expat.errors.codes[xml.parsers.expat.errors.XML_ERROR_INVALID_TOKEN]
        if e.code == invalid_token and new_name_char_at(data, p.ErrorByteIndex):
            msg = "5th edition name char: " + msg
        return False, msg
    except (UnicodeDecodeError, LookupError, ValueError) as e:
        return False, type(e).__name__


def is_name_char5(c):
    """NameChar of XML 1.0 fifth edition (non-ASCII part)."""
    o = ord(c)
    return (o == 0xB7 or 0xC0 <= o <= 0xD6 or 0xD8 <= o <= 0xF6 or 0xF8 <= o <= 0x37D
            or 0x37F <= o <= 0x1FFF or 0x200C <= o <= 0x200D or 0x203F <= o <= 0x2040
            or 0x2070 <= o <= 0x218F or 0x2C00 <= o <= 0x2FEF or 0x3001 <= o <= 0xD7FF
            or 0xF900 <= o <= 0xFDCF or 0xFDF0 <= o <= 0xFFFD or 0x10000 <= o <= 0xEFFFF)


def is_name_start_char5(c):
    """NameStartChar of XML 1.0 fifth edition (non-ASCII part)."""
    o = ord(c)
    return is_name_char5(c) and not (o == 0xB7 or 0x300 <= o <= 0x36F
                                     or 0x203F <= o <= 0x2040)


def new_name_char_at(data, index):
    """True if expat's error position holds a non-ASCII character that the
    fifth edition allows at this place of a name (expat uses the older
    character classes). After a name character any NameChar counts,
    otherwise only a NameStartChar."""
    if index < 0:
        return False
    if data[:2] == b"\xff\xfe":
        enc = "utf-16-le"
    elif data[:2] == b"\xfe\xff":
        enc = "utf-16-be"
    else:
        enc = "utf-8"
        m = XML_DECL_RE.match(data.decode("latin-1"))
        e = ENCODING_RE.search(m.group(1)) if m else None
        if e and e.group(1).lower() in SUPPORTED_ENCODINGS and \
                not e.group(1).lower().startswith("utf"):
            enc = e.group(1).lower()
    chunk = data[index:index + 4]
    for n in range(len(chunk), 0, -1):
        try:
            text = chunk[:n].decode(enc)
        except UnicodeDecodeError:
            continue
        if not text or ord(text[0]) <= 0x7F:
            return False
        before = data[max(0, index - 4):index].decode(enc, "replace")
        prev = before[-1:] or " "
        in_name = prev.isascii() and (prev.isalnum() or prev in "-._:") or \
            (not prev.isascii() and is_name_char5(prev))
        if in_name:
            return is_name_char5(text[0])
        return is_name_start_char5(text[0])
    return False


def collect_seeds(use_local):
    seeds = []
    for base in (SUITE, DATA):
        if not os.path.isdir(base):
            continue
        for dirpath, dirnames, names in os.walk(base):
            if base == DATA:
                dirnames[:] = [d for d in dirnames if d not in ("local", "xmlconf-suite")]
            for n in sorted(names):
                path = os.path.join(dirpath, n)
                if not n.lower().endswith((".xml", ".x81", ".x83", ".x84", ".x86", ".x89")):
                    continue
                seeds.append(path)
    if use_local and os.path.isdir(LOCAL):
        for dirpath, _, names in os.walk(LOCAL):
            for n in sorted(names):
                seeds.append(os.path.join(dirpath, n))
    result = []
    for path in seeds:
        try:
            if os.path.getsize(path) > MAX_SEED_SIZE:
                continue
            with open(path, "rb") as f:
                data = f.read()
        except OSError:
            continue
        if "<!DOCTYPE" in as_text(data):
            continue
        if not expat_ok(data)[0]:
            continue
        result.append((os.path.relpath(path, ROOT), data))
    return result


def mutate(rnd, data, seeds):
    """Returns the damaged data and a short description of the steps."""
    steps = []
    data = bytearray(data)
    for _ in range(rnd.choice((1, 1, 1, 1, 1, 2, 2, 3, 5))):
        n = len(data)
        kind = rnd.randrange(10)
        pos = rnd.randrange(n + 1) if n else 0
        if kind == 0 and n:
            pos = min(pos, n - 1)
            data[pos] ^= 1 << rnd.randrange(8)
            steps.append("flip@%d" % pos)
        elif kind == 1:
            b = rnd.randrange(256)
            data[pos:pos] = bytes([b])
            steps.append("ins%02x@%d" % (b, pos))
        elif kind == 2 and n:
            ln = rnd.randint(1, min(16, n - min(pos, n - 1)))
            pos = min(pos, n - 1)
            del data[pos:pos + ln]
            steps.append("del%d@%d" % (ln, pos))
        elif kind in (3, 4):
            t = rnd.choice(TOKENS)
            data[pos:pos] = t
            steps.append("tok%d@%d" % (TOKENS.index(t), pos))
        elif kind == 5 and n:
            a = rnd.randrange(n)
            ln = rnd.randint(1, min(64, n - a))
            chunk = bytes(data[a:a + ln])
            data[pos:pos] = chunk
            steps.append("dup%d@%d" % (ln, pos))
        elif kind == 6 and n:
            data = data[:pos]
            steps.append("cut@%d" % pos)
        elif kind == 7:
            name, other = rnd.choice(seeds)
            if other:
                a = rnd.randrange(len(other))
                ln = rnd.randint(1, min(256, len(other) - a))
                data[pos:pos] = other[a:a + ln]
                steps.append("splice%d@%d" % (ln, pos))
        elif kind == 8 and n:
            # replace one byte with a boundary value
            pos = min(pos, n - 1)
            b = rnd.choice((0x00, 0x09, 0x0a, 0x0d, 0x20, 0x26, 0x3c, 0x3e, 0x7f, 0x80,
                            0xbf, 0xc0, 0xc2, 0xdf, 0xe0, 0xed, 0xef, 0xf0, 0xf4, 0xf5, 0xff))
            data[pos] = b
            steps.append("set%02x@%d" % (b, pos))
        elif kind == 9 and n:
            # nest: wrap a range in a new element
            a = rnd.randrange(n)
            e = rnd.randrange(a, n + 1)
            data[e:e] = b"</z>"
            data[a:a] = b"<z>"
            steps.append("wrap@%d-%d" % (a, e))
    if rnd.randrange(40) == 0:
        # re-encode as UTF-16 (only when the result is still valid UTF-8)
        try:
            text = bytes(data).decode("utf-8")
            data = bytearray(b"\xff\xfe" + text.encode("utf-16-le"))
            steps.append("utf16")
        except UnicodeDecodeError:
            pass
    return bytes(data), steps


def bom_family(data):
    if data[:3] == b"\xef\xbb\xbf":
        return "utf-8"
    if data[:2] in (b"\xff\xfe", b"\xfe\xff"):
        return "utf-16"
    return None


def as_text(data):
    """Decodes enough of the document to look at its markup."""
    if data[:2] == b"\xff\xfe" or data[:2] == b"<\x00":
        return data.decode("utf-16-le", "replace").lstrip("﻿")
    if data[:2] == b"\xfe\xff" or data[:2] == b"\x00<":
        return data.decode("utf-16-be", "replace").lstrip("﻿")
    return data.decode("latin-1").lstrip("\xef\xbb\xbf")


XML_DECL_RE = re.compile(r"<\?xml(?=[\s?])([^>]*)\?>")
VERSION_RE = re.compile(r"""^\s+version\s*=\s*(?:"1\.[0-9]+"|'1\.[0-9]+')""")
ENCODING_RE = re.compile(r"""encoding\s*=\s*["']([^"']*)["']""")


def deviation(data, code):
    """Documented differences that explain a disagreement with expat. code
    is our error code name ('' when LandrixXml accepted the document)."""
    text = as_text(data)
    if "<!DOCTYPE" in text or "<!doctype" in text:
        return "DOCTYPE"
    if data[:2] in (b"<\x00", b"\x00<") and code == "Encoding":
        # accepted only with an encoding declaration (see the README)
        return "UTF-16 without BOM"
    if code == "InvalidUnicode" and data[:2] in (b"\xff\xfe", b"\xfe\xff"):
        try:
            data.decode("utf-16")
        except UnicodeDecodeError:
            # expat lets some unpaired surrogates in UTF-16 input through
            return "unpaired surrogate in UTF-16"
    m = XML_DECL_RE.match(text)
    if m:
        if not VERSION_RE.match(m.group(1)):
            # expat does not check the version number
            return "XML declaration version"
        e = ENCODING_RE.search(m.group(1))
        if e:
            enc = e.group(1).lower()
            if enc not in SUPPORTED_ENCODINGS:
                return "encoding"
            family = bom_family(data)
            if family and not enc.replace("_", "").replace("-", "").startswith(
                    family.replace("-", "")):
                return "BOM contradicts the declaration"
    return None


def run_helper(exe, files, timeout):
    """Runs the helper on files. Returns {index: fields} or None on a crash or
    a hang (then nothing of the batch is trusted)."""
    with tempfile.NamedTemporaryFile("w", delete=False, suffix=".txt", encoding="utf-8") as lst:
        lst.write("\n".join(files))
        name = lst.name
    try:
        proc = subprocess.run([exe, name], capture_output=True, check=False, timeout=timeout)
    except subprocess.TimeoutExpired:
        return None, "hang"
    finally:
        os.unlink(name)
    results = {}
    for line in proc.stdout.decode("utf-8", "replace").splitlines():
        parts = line.rstrip("\r").split("\t")
        if len(parts) >= 2 and parts[0].isdigit():
            results[int(parts[0])] = parts[1:]
    if proc.returncode != 0 or len(results) != len(files):
        return None, "exit code %d" % proc.returncode
    return results, ""


def run_isolating(exe, files, timeout, crashes):
    """Like run_helper, but bisects a failing batch down to the files that
    crash or hang the helper; those are appended to crashes."""
    results, why = run_helper(exe, files, timeout)
    if results is not None:
        return results
    if len(files) == 1:
        crashes.append((0, why))
        return {}
    half = len(files) // 2
    out = {}
    sub = []
    r = run_isolating(exe, files[:half], timeout, sub)
    out.update(r)
    crashes.extend(sub)
    sub = []
    r = run_isolating(exe, files[half:], timeout, sub)
    for k, v in r.items():
        out[k + half] = v
    crashes.extend((i + half, w) for i, w in sub)
    return out


def main():
    ap = argparse.ArgumentParser()
    default = os.path.join(ROOT, "build", "fpc322-win64" if os.name == "nt" else "fpc322-linux",
                           "LandrixXmlConformance" + (".exe" if os.name == "nt" else ""))
    ap.add_argument("--exe", default=default)
    ap.add_argument("--count", type=int, default=20000)
    ap.add_argument("--seed", type=int, default=None)
    ap.add_argument("--batch", type=int, default=1000)
    ap.add_argument("--timeout", type=int, default=120)
    ap.add_argument("--local", action="store_true")
    args = ap.parse_args()
    exe = os.path.abspath(args.exe)
    seed = args.seed if args.seed is not None else int(time.time())
    rnd = random.Random(seed)
    seeds = collect_seeds(args.local)
    if not seeds:
        print("no seeds found (run tools/run-xmlconf.py once to download the W3C suite)")
        return 1
    print("fuzz: seed %d, %d seed documents, %d variants, helper %s"
          % (seed, len(seeds), args.count, os.path.relpath(exe, ROOT)))
    work = tempfile.mkdtemp(prefix="landrixxml-fuzz-")
    stats = {}
    findings = []
    try:
        done = 0
        while done < args.count:
            n = min(args.batch, args.count - done)
            cases = []
            files = []
            for i in range(n):
                name, data = rnd.choice(seeds)
                mutated, steps = mutate(rnd, data, seeds)
                path = os.path.join(work, "%d.xml" % i)
                with open(path, "wb") as f:
                    f.write(mutated)
                cases.append((name, mutated, steps))
                files.append(path)
            crashes = []
            results = run_isolating(exe, files, args.timeout, crashes)
            crashed = dict(crashes)
            for i, (name, mutated, steps) in enumerate(cases):
                if i in crashed:
                    kind = "FAIL helper crash (%s)" % crashed[i]
                    detail = ""
                else:
                    r = results.get(i, ["MISSING"])
                    ours = r[0] in ("OK", "RTFAIL")
                    ok, msg = expat_ok(mutated)
                    detail = ""
                    if r[0] == "EXC":
                        kind = "FAIL unexpected exception"
                        detail = " ".join(r[1:2])
                    elif r[0] == "RTFAIL":
                        kind = "FAIL round trip"
                        detail = " ".join(r[1:])
                    elif r[0] not in ("OK", "ERR"):
                        kind = "FAIL no result"
                    elif ours == ok:
                        kind = "agree " + ("accepted" if ok else "rejected")
                    else:
                        code = CODES.get(int(r[1]), r[1]) if not ours and r[1].isdigit() else ""
                        dev = deviation(mutated, code)
                        if dev:
                            kind = "deviation " + dev
                        elif not ok and msg.startswith("5th edition"):
                            kind = "deviation name chars (5th edition)"
                        elif code == "Limit":
                            kind = "deviation depth limit"
                        elif ours:
                            kind = "FAIL accepted, expat rejects"
                            detail = "expat " + msg
                        else:
                            kind = "FAIL rejected, expat accepts"
                            detail = "%s line %s column %s" % (code, r[2], r[3])
                stats[kind] = stats.get(kind, 0) + 1
                if args.local and kind == "FAIL round trip":
                    # messages may quote names, and splices can carry local
                    # data into variants of any seed
                    detail = detail.split(":")[0]
                if kind.startswith("FAIL"):
                    findings.append((kind, name, steps, mutated, detail))
            done += n
            print("  %d/%d done, %d failures" % (done, args.count, len(findings)), flush=True)
    finally:
        shutil.rmtree(work, ignore_errors=True)
    print()
    for kind in sorted(stats):
        print("  %-45s %7d" % (kind, stats[kind]))
    if findings:
        os.makedirs(FINDINGS, exist_ok=True)
        print()
        for n, (kind, name, steps, mutated, detail) in enumerate(findings):
            out = os.path.join(FINDINGS, "%d-%d.xml" % (seed, n))
            with open(out, "wb") as f:
                f.write(mutated)
            with open(out + ".txt", "w", encoding="utf-8") as f:
                f.write("%s\n%s\n%s\n%s\n" % (kind, name, " ".join(steps), detail))
            print("%s: %s from %s [%s] %s" % (kind, os.path.relpath(out, ROOT), name,
                                              " ".join(steps), detail))
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
