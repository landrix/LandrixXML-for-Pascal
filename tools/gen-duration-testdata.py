#!/usr/bin/env python3
"""Generate duration test cases with an independent oracle.

Writes tests/data/xpath-oracle/durations/ (c.txt, d.xml, expected.txt in
the format of tests/data/xpath): random xs:yearMonthDuration and
xs:dayTimeDuration values through casts, the canonical lexical form,
addition, subtraction, multiplication and division by numbers, the
quotient of two durations, comparisons and the component functions. The
expected results are computed here with Python's decimal module from
F&O 2.0 (sections 10 and 17) and the limits the evaluator shares with
Saxon (every number of the lexical form below 2^31, months below 2^31,
whole seconds below 2^63, nine fraction digits; a factor or divisor is
an xs:decimal literal, so no binary rounding is involved):

  months * n and months div n: rounded as fn:round (ties up)
  seconds * n and seconds div n: truncated to nanoseconds
  duration div duration: 20 fraction digits, ties to even

expected.txt holds the results of the XPath 2.0 profile (exact
arithmetic), expected-saxon.txt those of the Saxon profile: Saxon
divides through xs:double, the months of an xs:yearMonthDuration as a
double quotient (then rounded as fn:round), the seconds of an
xs:dayTimeDuration by multiplying them by 1 div the number as an
xs:double (the decimal of its shortest digits, Java's
BigDecimal.valueOf); products with decimals and averages are exact.

  python tools/gen-duration-testdata.py [--seed N] [--count N]
      [--saxon --java PATH/java.exe --classes OUT --jar validator-1.6.3-standalone.jar]

--saxon also evaluates the cases with Saxon (tools/XPathOracle.java) and
prints the cases where Saxon and the model differ, to check the model;
Saxon's known defects (overflow of its day count in the canonical form,
a crash on non-terminating averages, P0M as the string of a zero
xs:duration cast from xs:yearMonthDuration) are not generated.
"""

import argparse
import decimal
import os
import random
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "tests", "data", "xpath-oracle", "durations")

D = decimal.Decimal
decimal.getcontext().prec = 200
MAX31 = 2 ** 31 - 1
MAX63 = 2 ** 63 - 1


class Err(Exception):
    def __init__(self, code):
        Exception.__init__(self, code)
        self.code = code


def fmt_decimal(x):
    """The canonical xs:decimal form: no exponent, no trailing zeros."""
    x = D(x)
    if x == 0:
        return "0"
    s = format(x.normalize(), "f")
    if "." in s:
        s = s.rstrip("0").rstrip(".")
    return s


def canonical(kind, months, seconds):
    if months == 0 and seconds == 0:
        return "P0M" if kind == "xs:yearMonthDuration" else "PT0S"
    neg = months < 0 or seconds < 0
    m, s = abs(months), abs(seconds)
    whole = int(s)
    frac = s - whole
    out = "P"
    if m // 12:
        out += "%dY" % (m // 12)
    if m % 12:
        out += "%dM" % (m % 12)
    if whole // 86400:
        out += "%dD" % (whole // 86400)
    t = ""
    if whole % 86400 // 3600:
        t += "%dH" % (whole % 86400 // 3600)
    if whole % 3600 // 60:
        t += "%dM" % (whole % 3600 // 60)
    if whole % 60 or frac:
        t += fmt_decimal(D(whole % 60) + frac) + "S"
    if t:
        out += "T" + t
    return ("-" if neg else "") + out


def make(kind, months, seconds):
    """A value of kind, FODT0002 beyond the limits."""
    if kind == "xs:dayTimeDuration":
        months = 0
    if kind == "xs:yearMonthDuration":
        seconds = D(0)
    seconds = D(seconds).quantize(D("1e-9"), rounding=decimal.ROUND_DOWN) if seconds else D(0)
    if abs(months) > MAX31 or abs(int(seconds)) > MAX63:
        raise Err("FODT0002")
    return (kind, months, seconds)


def round_half_ceiling(x):
    return int((x + D("0.5")).to_integral_value(rounding=decimal.ROUND_FLOOR))


def truncate9(x):
    return x.quantize(D("1e-9"), rounding=decimal.ROUND_DOWN)


def lexical(rnd, kind):
    """A random lexical form within the limits and its value."""
    neg = rnd.random() < 0.3
    if kind == "xs:yearMonthDuration":
        y = rnd.choice([0, rnd.randint(0, 30), rnd.randint(0, 100000)])
        m = rnd.choice([0, rnd.randint(0, 11), rnd.randint(0, 500)])
        parts = []
        if y or rnd.random() < 0.2:
            parts.append("%dY" % y)
        if m or not parts:
            parts.append("%dM" % m)
        months = y * 12 + m
        text = ("-" if neg else "") + "P" + "".join(parts)
        return text, (-months if neg else months), D(0)
    d = rnd.choice([0, rnd.randint(0, 40), rnd.randint(0, 1000000)])
    h = rnd.choice([0, rnd.randint(0, 23), rnd.randint(0, 100)])
    mi = rnd.choice([0, rnd.randint(0, 59), rnd.randint(0, 1000)])
    digits = rnd.choice([0, 0, 1, 3, 9])
    sec = D(rnd.randint(0, 59))
    if rnd.random() < 0.2:
        sec = D(rnd.randint(0, 100000))
    if digits:
        sec += D(rnd.randint(0, 10 ** digits - 1)) / D(10 ** digits)
    text = "P"
    if d or rnd.random() < 0.1:
        text += "%dD" % d
    t = ""
    if h:
        t += "%dH" % h
    if mi:
        t += "%dM" % mi
    if sec or (not t and text == "P"):
        if digits:
            t += "%s.%0*dS" % (int(sec), digits, int((sec - int(sec)) * 10 ** digits))
        else:
            t += "%dS" % int(sec)
    if t:
        text += "T" + t
    seconds = D(d * 86400 + h * 3600 + mi * 60) + sec
    return ("-" if neg else "") + text, D(0), (-seconds if neg else seconds)


def number(rnd):
    """A random xs:integer or xs:decimal literal and its value."""
    if rnd.random() < 0.4:
        v = rnd.randint(-20, 20)
        return str(v), D(v), "integer"
    digits = rnd.randint(1, 4)
    v = D(rnd.randint(-99999, 99999)) / D(10 ** digits)
    s = fmt_decimal(v)
    if "." not in s:
        s += ".0"
    return s, v, "decimal"


def ctor(kind, text):
    return "%s('%s')" % (kind, text)


def shortest(x):
    """The decimal of the shortest digits of the double nearest to x."""
    return D(repr(float(x)))


def cases(seed, count):
    rnd = random.Random(seed)
    out = []
    kinds = ["xs:yearMonthDuration", "xs:dayTimeDuration"]

    def value(kind):
        text, m, s = lexical(rnd, kind)
        return ctor(kind, text), make(kind, m, s)

    def result(fn):
        try:
            return fn()
        except Err as e:
            return "error " + e.code

    def put(expr, fn, saxon=None):
        r = result(fn)
        out.append((expr, r, result(saxon) if saxon else r))

    def show(v):
        return "%s %s" % (v[0], canonical(*v))

    for _ in range(count):
        kind = rnd.choice(kinds)
        op = rnd.randrange(9)
        ea, a = value(kind)
        if op == 0:
            put(ea, lambda: show(a))
            text, m, s = lexical(rnd, kind)
            put(ctor("xs:duration", text), lambda: show(make("xs:duration", m, s)))
        elif op == 1:
            eb, b = value(kind)
            put("%s + %s" % (ea, eb), lambda: show(make(kind, a[1] + b[1], a[2] + b[2])))
            put("%s - %s" % (ea, eb), lambda: show(make(kind, a[1] - b[1], a[2] - b[2])))
        elif op in (2, 3):
            lit, n, _ = number(rnd)
            if kind == "xs:yearMonthDuration":
                put("%s * %s" % (ea, lit), lambda: show(make(kind, round_half_ceiling(a[1] * n), 0)))
                if n != 0:
                    put("%s div %s" % (ea, lit), lambda: show(make(kind, round_half_ceiling(D(a[1]) / n), 0)),
                        lambda: show(make(kind, round_half_ceiling(D(float(a[1]) / float(n))), 0)))
                else:
                    put("%s div %s" % (ea, lit), lambda: (_ for _ in ()).throw(Err("FODT0002")))
            else:
                put("%s * %s" % (lit, ea), lambda: show(make(kind, 0, truncate9(a[2] * n))))
                if n != 0:
                    put("%s div %s" % (ea, lit), lambda: show(make(kind, 0, truncate9(a[2] / n))),
                        lambda: show(make(kind, 0, truncate9(a[2] * shortest(1.0 / float(n))))))
        elif op == 4:
            eb, b = value(kind)
            x, y = (D(a[1]), D(b[1])) if kind == "xs:yearMonthDuration" else (a[2], b[2])
            if y == 0:
                put("%s div %s" % (ea, eb), lambda: (_ for _ in ()).throw(Err("FOAR0001")))
            else:
                q = (x / y).quantize(D("1e-20"), rounding=decimal.ROUND_HALF_EVEN)
                put("%s div %s" % (ea, eb), lambda: "xs:decimal " + fmt_decimal(q))
        elif op == 5:
            eb, b = value(kind)
            key = 1 if kind == "xs:yearMonthDuration" else 2
            for o, f in (("lt", lambda p, q: p < q), ("eq", lambda p, q: p == q), ("ge", lambda p, q: p >= q)):
                put("%s %s %s" % (ea, o, eb), lambda f=f: "xs:boolean " + ("true" if f(a[key], b[key]) else "false"))
        elif op == 6:
            m, s = abs(a[1]), abs(a[2])
            sign = -1 if a[1] < 0 or a[2] < 0 else 1
            whole = int(s)
            comps = [("years", m // 12), ("months", m % 12), ("days", whole // 86400),
                     ("hours", whole % 86400 // 3600), ("minutes", whole % 3600 // 60)]
            fname, v = rnd.choice(comps)
            put("%s-from-duration(%s)" % (fname, ea), lambda: "xs:integer %d" % (sign * v))
            put("seconds-from-duration(%s)" % ea,
                lambda: "xs:decimal " + fmt_decimal(sign * (D(whole % 60) + s - whole)))
        elif op == 7:
            if a[1] != 0 or a[2] != 0:
                put("string(xs:duration(%s))" % ea, lambda: "xs:string " + canonical("xs:duration", a[1], a[2]))
            other = kinds[1 - kinds.index(kind)]
            put("%s(%s)" % (other, ea), lambda: show(make(other, a[1], a[2])))
        else:
            vals = [value(kind) for _ in range(rnd.randint(1, 4))]
            seq = "(" + ", ".join(e for e, _ in vals) + ")"
            key = 1 if kind == "xs:yearMonthDuration" else 2
            total = result(lambda: make(kind, sum(v[1] for _, v in vals), sum((v[2] for _, v in vals), D(0))))
            if isinstance(total, str):
                put("sum(%s)" % seq, lambda: (_ for _ in ()).throw(Err("FODT0002")))
                continue
            put("sum(%s)" % seq, lambda: show(total))
            put("max(%s)" % seq, lambda: show(max((v for _, v in vals), key=lambda v: v[key])))
            if kind == "xs:yearMonthDuration":
                avg = lambda: show(make(kind, round_half_ceiling(D(total[1]) / len(vals)), 0))
            else:
                # Saxon fails on averages that do not terminate; keep exact ones
                q = total[2] / len(vals)
                if truncate9(q) != q:
                    continue
                avg = lambda: show(make(kind, 0, q))
            put("avg(%s)" % seq, avg)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--count", type=int, default=400)
    ap.add_argument("--saxon", action="store_true")
    ap.add_argument("--java")
    ap.add_argument("--classes")
    ap.add_argument("--jar")
    args = ap.parse_args()
    data = cases(args.seed, args.count)
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "d.xml"), "w", encoding="utf-8", newline="\n") as f:
        f.write("<r/>\n")
    with open(os.path.join(OUT, "c.txt"), "w", encoding="utf-8", newline="\n") as f:
        for expr, _, _ in data:
            f.write("expr " + expr + "\n")
    for name, column in (("expected.txt", 1), ("expected-saxon.txt", 2)):
        with open(os.path.join(OUT, name), "w", encoding="utf-8", newline="\n") as f:
            for row in data:
                f.write("# " + row[0] + "\n" + row[column] + "\n")
    print("%d cases" % len(data))
    if args.saxon:
        cp = os.pathsep.join([args.classes, args.jar])
        r = subprocess.run([args.java, "-cp", cp, "XPathOracle", os.path.join(OUT, "d.xml"),
                            os.path.join(OUT, "c.txt")], capture_output=True)
        if r.returncode != 0:
            sys.exit(r.stderr.decode("utf-8", "replace")[-2000:])
        saxon = {}
        expr = None
        for line in r.stdout.decode("utf-8").replace("\r\n", "\n").split("\n"):
            if line.startswith("# "):
                expr = line[2:]
                saxon[expr] = []
            elif line and expr is not None:
                saxon[expr].append(line)
        differ = 0
        for expr, _, result in data:
            if saxon.get(expr) != [result]:
                differ += 1
                print("differs: %s\n  model: %s\n  saxon: %s" % (expr, result, saxon.get(expr)))
        print("%d of %d cases differ from Saxon" % (differ, len(data)))


if __name__ == "__main__":
    main()
