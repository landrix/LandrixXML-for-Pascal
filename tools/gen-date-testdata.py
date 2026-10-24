#!/usr/bin/env python3
"""Generate date and time test cases with an independent oracle.

Writes tests/data/xpath-oracle/dates/ (c.txt, d.xml, expected.txt in the
format of tests/data/xpath): random xs:date, xs:dateTime and xs:time
values (years 1 to 9999, fractions up to nine digits, time zones or
none) through additions and subtractions of durations, differences,
comparisons, the time zone adjustments, casts between the three types
and the component functions. The expected results are computed here from
F&O 2.0 (sections 10.4 to 10.8): the calendar is Python's proleptic
Gregorian date.toordinal, the seconds are exact decimals; a value
without a time zone is in the implicit time zone, UTC (the evaluator's
default). expected.txt holds the results of the XPath 2.0 profile,
expected-saxon.txt those of the Saxon profile, which differ in one point:
Saxon rounds the result of seconds-from-dateTime and seconds-from-time
to microseconds (ties up, so 59.9999996 gives 60). Saxon's text of an
xs:time moved by a duration of millions of days is garbage; such cases
are not generated.

  python tools/gen-date-testdata.py [--seed N] [--count N]
      [--saxon --java PATH/java.exe --classes OUT --jar validator-1.6.3-standalone.jar]

--saxon also evaluates the cases with Saxon (tools/XPathOracle.java, in
the time zone UTC) and prints the cases where Saxon and the model differ.
"""

import argparse
import datetime
import decimal
import os
import random
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "tests", "data", "xpath-oracle", "dates")

D = decimal.Decimal
decimal.getcontext().prec = 60
EPOCH = datetime.date(1970, 1, 1).toordinal()


class Err(Exception):
    def __init__(self, code):
        Exception.__init__(self, code)
        self.code = code


def fmt_decimal(x):
    x = D(x)
    if x == 0:
        return "0"
    s = format(x.normalize(), "f")
    if "." in s:
        s = s.rstrip("0").rstrip(".")
    return s


def zone_text(tz):
    if tz is None:
        return ""
    if tz == 0:
        return "Z"
    sign = "-" if tz < 0 else "+"
    return "%s%02d:%02d" % (sign, abs(tz) // 60, abs(tz) % 60)


def sec_text(s):
    t = fmt_decimal(s)
    if s < 10:
        t = "0" + t
    return t


class Value:
    """kind: date, dateTime, time; y, m, d, hh, mi, sec (Decimal), tz
    (minutes or None)"""

    def __init__(self, kind, y, m, d, hh, mi, sec, tz):
        self.kind, self.y, self.m, self.d, self.hh, self.mi, self.sec, self.tz = kind, y, m, d, hh, mi, sec, tz

    def text(self):
        parts = []
        if self.kind != "time":
            parts.append("%04d-%02d-%02d" % (self.y, self.m, self.d))
        if self.kind == "dateTime":
            parts.append("T")
        if self.kind != "date":
            parts.append("%02d:%02d:%s" % (self.hh, self.mi, sec_text(self.sec)))
        return "".join(parts) + zone_text(self.tz)

    def typed(self):
        return "xs:%s %s" % (self.kind, self.text())

    def expr(self):
        return "xs:%s('%s')" % (self.kind, self.text())

    def local(self):
        """seconds since 1970-01-01T00:00:00 on its own clock"""
        if self.kind == "time":
            days = datetime.date(1972, 12, 31).toordinal() - EPOCH
        else:
            days = datetime.date(self.y, self.m, self.d).toordinal() - EPOCH
        if self.kind == "date":
            return D(days * 86400)
        return D(days * 86400 + self.hh * 3600 + self.mi * 60) + self.sec

    def utc(self):
        return self.local() - D((self.tz or 0) * 60)


def from_local(kind, seconds, tz):
    whole = int(seconds.to_integral_value(rounding=decimal.ROUND_FLOOR))
    days, inday = divmod(whole, 86400)
    if kind == "time":
        y, m, d = 1972, 12, 31
    else:
        ordinal = days + EPOCH
        if ordinal < 1 or ordinal > datetime.date(9999, 12, 31).toordinal():
            raise Err("range")
        dt = datetime.date.fromordinal(ordinal)
        y, m, d = dt.year, dt.month, dt.day
    if kind == "date":
        return Value(kind, y, m, d, 0, 0, D(0), tz)
    return Value(kind, y, m, d, inday // 3600, inday % 3600 // 60, D(inday % 60) + (seconds - whole), tz)


def days_in_month(y, m):
    if m == 12:
        return 31
    return (datetime.date(y, m + 1, 1) - datetime.date(y, m, 1)).days


def add_months(v, months):
    total = v.y * 12 + (v.m - 1) + months
    y, m = divmod(total, 12)
    m += 1
    if y < 1 or y > 9999:
        raise Err("range")
    return Value(v.kind, y, m, min(v.d, days_in_month(y, m)), v.hh, v.mi, v.sec, v.tz)


def dtd_text(seconds):
    """the canonical xs:dayTimeDuration"""
    if seconds == 0:
        return "PT0S"
    neg = seconds < 0
    s = abs(seconds)
    whole = int(s)
    frac = s - whole
    out = "P"
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


def ymd_text(months):
    if months == 0:
        return "P0M"
    neg = months < 0
    m = abs(months)
    out = "P"
    if m // 12:
        out += "%dY" % (m // 12)
    if m % 12:
        out += "%dM" % (m % 12)
    return ("-" if neg else "") + out


def random_value(rnd, kind):
    y = rnd.choice([rnd.randint(1, 9999), rnd.randint(1900, 2100), rnd.randint(1, 50), rnd.randint(9950, 9999)])
    m = rnd.randint(1, 12)
    d = rnd.choice([rnd.randint(1, days_in_month(y, m)), days_in_month(y, m)])
    hh, mi = rnd.randint(0, 23), rnd.randint(0, 59)
    digits = rnd.choice([0, 0, 1, 3, 9])
    sec = D(rnd.randint(0, 59))
    if digits:
        sec += D(rnd.randint(0, 10 ** digits - 1)) / D(10 ** digits)
    tz = rnd.choice([None, None, 0, rnd.randint(-14, 14) * 60, rnd.randint(-840, 840) // 15 * 15])
    if kind == "date":
        hh, mi, sec = 0, 0, D(0)
    return Value(kind, y, m, d, hh, mi, sec, tz)


def random_dtd(rnd, small=False):
    seconds = D(rnd.choice([rnd.randint(0, 86400 * 400), rnd.randint(0, 100000),
                            rnd.randint(0, 86400 * (400 if small else 3000000))]))
    if rnd.random() < 0.5:
        seconds += D(rnd.randint(0, 999999999)) / D(10 ** 9)
    if rnd.random() < 0.4:
        seconds = -seconds
    return seconds


def cases(seed, count):
    rnd = random.Random(seed)
    out = []

    def result(fn):
        try:
            return fn()
        except Err as e:
            return "error " + e.code

    def put(expr, fn, saxon=None):
        r = result(fn)
        if r == "error range":
            return
        out.append((expr, r, result(saxon) if saxon else r))

    for _ in range(count):
        kind = rnd.choice(["date", "dateTime", "time"])
        a = random_value(rnd, kind)
        op = rnd.randrange(8)
        if op == 0 and kind != "time":
            months = rnd.choice([rnd.randint(-30, 30), rnd.randint(-50000, 50000)])
            put("%s + xs:yearMonthDuration('%s')" % (a.expr(), ymd_text(months)), lambda: add_months(a, months).typed())
            put("%s - xs:yearMonthDuration('%s')" % (a.expr(), ymd_text(months)), lambda: add_months(a, -months).typed())
        elif op in (0, 1):
            s = random_dtd(rnd, kind == "time")
            put("%s + xs:dayTimeDuration('%s')" % (a.expr(), dtd_text(s)),
                lambda: from_local(a.kind, a.local() + s, a.tz).typed())
            put("xs:dayTimeDuration('%s') + %s" % (dtd_text(s), a.expr()),
                lambda: from_local(a.kind, a.local() + s, a.tz).typed())
            put("%s - xs:dayTimeDuration('%s')" % (a.expr(), dtd_text(s)),
                lambda: from_local(a.kind, a.local() - s, a.tz).typed())
        elif op == 2:
            b = random_value(rnd, kind)
            put("%s - %s" % (a.expr(), b.expr()), lambda: "xs:dayTimeDuration " + dtd_text(a.utc() - b.utc()))
        elif op == 3:
            b = random_value(rnd, kind) if rnd.random() < 0.7 else from_local(kind, a.local(), rnd.choice([None, 0, 60]))
            for o, f in (("lt", lambda p, q: p < q), ("eq", lambda p, q: p == q), ("ge", lambda p, q: p >= q)):
                put("%s %s %s" % (a.expr(), o, b.expr()), lambda f=f: "xs:boolean " + ("true" if f(a.utc(), b.utc()) else "false"))
        elif op == 4:
            tz = rnd.choice([None, 0, rnd.randint(-14, 14) * 60, rnd.randint(-840, 840)])
            if tz is None:
                arg = "()"
            else:
                arg = "xs:dayTimeDuration('%s')" % dtd_text(D(tz * 60))
            name = {"date": "adjust-date-to-timezone", "dateTime": "adjust-dateTime-to-timezone",
                    "time": "adjust-time-to-timezone"}[kind]

            def adjust():
                if a.tz is None or tz is None:
                    return Value(a.kind, a.y, a.m, a.d, a.hh, a.mi, a.sec, tz).typed()
                return from_local(a.kind, a.local() + D((tz - a.tz) * 60), tz).typed()
            put("%s(%s, %s)" % (name, a.expr(), arg), adjust)
        elif op == 5 and kind == "dateTime":
            put("xs:date(%s)" % a.expr(), lambda: Value("date", a.y, a.m, a.d, 0, 0, D(0), a.tz).typed())
            put("xs:time(%s)" % a.expr(), lambda: Value("time", 1972, 12, 31, a.hh, a.mi, a.sec, a.tz).typed())
            put("xs:dateTime(xs:date(%s))" % a.expr(), lambda: Value("dateTime", a.y, a.m, a.d, 0, 0, D(0), a.tz).typed())
        elif op == 6:
            comps = {"date": [("year-from-date", a.y), ("month-from-date", a.m), ("day-from-date", a.d)],
                     "dateTime": [("year-from-dateTime", a.y), ("month-from-dateTime", a.m),
                                  ("day-from-dateTime", a.d), ("hours-from-dateTime", a.hh),
                                  ("minutes-from-dateTime", a.mi)],
                     "time": [("hours-from-time", a.hh), ("minutes-from-time", a.mi)]}[kind]
            fname, v = rnd.choice(comps)
            put("%s(%s)" % (fname, a.expr()), lambda: "xs:integer %d" % v)
            if kind != "date":
                put("seconds-from-%s(%s)" % (kind, a.expr()), lambda: "xs:decimal " + fmt_decimal(a.sec),
                    lambda: "xs:decimal " + fmt_decimal(a.sec.quantize(D("1e-6"), rounding=decimal.ROUND_HALF_UP)))
            if a.tz is not None:
                put("timezone-from-%s(%s)" % (kind, a.expr()), lambda: "xs:dayTimeDuration " + dtd_text(D(a.tz * 60)))
        else:
            put("string(%s)" % a.expr(), lambda: "xs:string " + a.text())
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
        r = subprocess.run([args.java, "-Duser.timezone=UTC", "-cp", cp, "XPathOracle", os.path.join(OUT, "d.xml"),
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
