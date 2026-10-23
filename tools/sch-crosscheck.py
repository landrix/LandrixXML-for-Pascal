#!/usr/bin/env python3
"""Compare a rule file of tools/sch-compile.py with the XSLT the KoSIT validator
runs (compiled by SchXslt 1.10): the namespace bindings, the global variables,
the functions (the XSLT ones translated as sch-compile.py does), and per
pattern the rules in priority order with their context (the fired-rule text
and the template match), lets, and per assert or report the id, flag, role,
test (the reported text and the executed xsl:if) and message.

  python tools/sch-crosscheck.py RULES.xml KOSIT.xsl [--allow ID ...]

Prints every difference and exits with 1 if there is one that --allow does not
name (by assert id). What KoSIT executes is the reference: a difference means
the rule file must follow the XSLT (or the case is documented and allowed).
"""

import argparse
import importlib.util
import os
import sys
import xml.etree.ElementTree as ET

_spec = importlib.util.spec_from_file_location(
    "sch_compile", os.path.join(os.path.dirname(os.path.abspath(__file__)), "sch-compile.py"))
sch_compile = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(sch_compile)

XSL = "{http://www.w3.org/1999/XSL/Transform}"
SVRL = "{http://purl.oclc.org/dsdl/svrl}"
SCHXSLT = "{https://doi.org/10.5281/zenodo.1495494}"
RULES = "{urn:landrix:schematron-rules}"
XML_SPACE = "{http://www.w3.org/XML/1998/namespace}space"


# XML white space; NBSP and other Unicode spaces are text
WS = " " + chr(9) + chr(10) + chr(13)


def collapse(s):
    """Collapse white space runs to one space and trim, except inside XPath
    comments and string literals ('..' or "..", the quote doubled inside), whose content
    is kept exactly."""
    s = s or ""
    out = []
    i, n = 0, len(s)
    while i < n:
        ch = s[i]
        if s.startswith("(:", i):
            # a comment, nested ones too, as it is (quotes inside are no strings)
            depth, j = 0, i
            while j < n:
                if s.startswith("(:", j):
                    depth += 1
                    j += 2
                elif s.startswith(":)", j):
                    depth -= 1
                    j += 2
                    if depth == 0:
                        break
                else:
                    j += 1
            out.append(s[i:j])
            i = j
        elif ch in "'\"":
            j = i + 1
            while j < n:
                if s[j] == ch:
                    if j + 1 < n and s[j + 1] == ch:
                        j += 2
                        continue
                    break
                j += 1
            out.append(s[i:j + 1])
            i = j + 1
        elif ch in WS:
            while i < n and s[i] in WS:
                i += 1
            out.append(" ")
        else:
            out.append(ch)
            i += 1
    return "".join(out).strip(WS)


def squeeze(s):
    """White space runs to one space, keeping a space at either end."""
    words = collapse_text(s)
    if not words:
        return " " if s else ""
    return (" " if s[0] in WS else "") + words + (" " if s[-1] in WS else "")


def collapse_text(s):
    """XML white space runs to one space, trimmed (no string literals)."""
    return " ".join(w for w in "".join(" " if ch in WS else ch for ch in s).split(" ") if w)


def message_parts(el, xslt):
    """The message as a list of ("text", s) / ("value-of", select) / ("name", path)."""
    parts = []

    def add(kind, value):
        if kind == "text" and parts and parts[-1][0] == "text":
            parts[-1] = ("text", parts[-1][1] + value)
        else:
            parts.append((kind, value))
    def literal(e, text, preserve):
        """Text as the XSLT processor sees it: white space only text is stripped
        from a stylesheet except inside xsl:text. In a rule file only the
        part elements count, not the formatting around them."""
        if not xslt or not text:
            return
        if text.strip(WS) or preserve or e.tag == XSL + "text":
            add("text", text)

    def content(e, preserve):
        space = e.get(XML_SPACE)
        if space is not None:
            preserve = space == "preserve"
        literal(e, e.text, preserve)
        for c in e:
            if xslt and c.tag == XSL + "value-of":
                sel = collapse(c.get("select"))
                if sel.startswith("name(") and sel.endswith(")"):
                    inner = sel[5:-1]
                    add("name", "" if inner == "." else inner)
                else:
                    add("value-of", sel)
            elif not xslt and c.tag == RULES + "text":
                add("text", c.text or "")
            elif not xslt and c.tag == RULES + "value-of":
                add("value-of", collapse(c.get("select")))
            elif not xslt and c.tag == RULES + "name":
                add("name", c.get("path") or "")
            else:
                content(c, preserve)
            literal(e, c.tail, preserve)
    content(el, False)
    # white space runs become one space but stay at the borders of dynamic
    # parts (they separate text from a value); only the whole message is trimmed
    out = [("text", squeeze(v)) if k == "text" else (k, v) for k, v in parts]
    if out and out[0][0] == "text":
        out[0] = ("text", out[0][1].lstrip(WS))
    if out and out[-1][0] == "text":
        out[-1] = ("text", out[-1][1].rstrip(WS))
    return [(k, v) for k, v in out if not (k == "text" and not v)]


def executed(test, negated):
    """The test an xsl:if executes; for an assert SchXslt writes not(TEST), and
    the test inside keeps its own surrounding white space."""
    test = collapse(test)
    if negated:
        if not (test.startswith("not(") and test.endswith(")")):
            return "?" + test
        test = collapse(test[4:-1])
    return test


def top_namespaces(path):
    """The namespace declarations of the document element."""
    ns = {}
    for event, item in ET.iterparse(path, events=("start-ns", "start")):
        if event == "start":
            break
        ns[item[0]] = item[1]
    return ns


def xslt_functions(root, path):
    """The xsl:function elements, translated by sch-compile.py."""
    comp = sch_compile.Compiler(path)
    doc = (root, path, {})
    for f in root.findall(XSL + "function"):
        if not f.get("name").startswith("schxslt"):
            comp.function(f, doc)
    return comp.functions


def function_key(f):
    return (f["name"], f["as"], f["params"], f["variables"], f["result"])


def from_xslt(path):
    root = ET.parse(path).getroot()
    # message_parts sees xml:space only from svrl:text down
    inside = sum(1 for t in root.iter(SVRL + "text") for e in t.iter() if e.get(XML_SPACE) is not None)
    if inside != sum(1 for e in root.iter() if e.get(XML_SPACE) is not None):
        sys.exit("%s: xml:space outside svrl:text is not supported" % path)
    patterns = {}
    globals_ = {}
    for p in root.findall(XSL + "param") + root.findall(XSL + "variable"):
        if not p.get("name").startswith("schxslt"):
            globals_[p.get("name")] = collapse(p.get("select"))
    for t in root.findall(XSL + "template"):
        mode = t.get("mode")
        if not t.get("match") or not mode or mode.startswith("schxslt") or t.get("priority") is None:
            continue
        otherwise = t.find(XSL + "choose/" + XSL + "otherwise")
        if otherwise is None:
            continue
        rule = otherwise.find(SCHXSLT + "rule")
        fired = rule.find(SVRL + "fired-rule")
        ctx = None
        for a in fired.findall(XSL + "attribute"):
            if a.get("name") == "context":
                ctx = collapse(a.text)
        lets = [(v.get("name"), collapse(v.get("select"))) for v in t.findall(XSL + "variable")]
        checks = []
        for i in rule.findall(XSL + "if"):
            fa = i.find(SVRL + "failed-assert")
            sr = i.find(SVRL + "successful-report")
            el = fa if fa is not None else sr
            if el is None:
                continue
            test = None
            for a in el.findall(XSL + "attribute"):
                if a.get("name") == "test":
                    test = collapse(a.text)
            text = el.find(SVRL + "text")
            checks.append({"kind": "assert" if fa is not None else "report", "id": el.get("id") or "",
                           "flag": el.get("flag") or "", "role": el.get("role") or "", "test": test,
                           "executed": executed(i.get("test"), fa is not None),
                           "parts": message_parts(text, True) if text is not None else []})
        # all patterns share one mode; the rule names its pattern
        patterns.setdefault(rule.get("pattern"), []).append(
            (int(t.get("priority")), (ctx, collapse(t.get("match"))), lets, checks))
    out = []
    for pid in sorted(patterns, key=lambda k: -max(r[0] for r in patterns[k])):
        out.append([r[1:] for r in sorted(patterns[pid], key=lambda r: -r[0])])
    return out, globals_, top_namespaces(path), xslt_functions(root, path)


def from_rules(path):
    root = ET.parse(path).getroot()
    out = []
    globals_ = {l.get("name"): collapse(l.get("value")) for l in root.findall(RULES + "let")}
    ns = [(n.get("prefix"), n.get("uri")) for n in root.findall(RULES + "ns")]
    functions = []
    for f in root.findall(RULES + "function"):
        functions.append({
            "name": f.get("name"), "as": f.get("as") or "",
            "params": [(p.get("name"), p.get("as") or "") for p in f.findall(RULES + "param")],
            "variables": [(v.get("name"), v.get("as") or "", collapse(v.get("value")))
                          for v in f.findall(RULES + "variable")],
            "result": collapse(f.find(RULES + "result").get("value"))})
    for p in root.findall(RULES + "pattern"):
        rules = []
        for r in p.findall(RULES + "rule"):
            lets = [(l.get("name"), collapse(l.get("value"))) for l in r.findall(RULES + "let")]
            checks = []
            for c in r:
                if c.tag in (RULES + "assert", RULES + "report"):
                    kind = c.tag[len(RULES):]
                    test = collapse(c.get("test"))
                    checks.append({"kind": kind, "id": c.get("id"), "flag": c.get("flag"),
                                   "role": c.get("role") or "",
                                   "test": test,
                                   "executed": test,
                                   "parts": message_parts(c, False)})
            ctx = collapse(r.get("context"))
            rules.append(((ctx, ctx), lets, checks))
        # a pattern without rules has no template in the XSLT
        if rules:
            out.append(rules)
    return out, globals_, ns, functions


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rules")
    ap.add_argument("xslt")
    ap.add_argument("--allow", nargs="*", default=[])
    args = ap.parse_args()
    mine, mine_globals, mine_ns, mine_functions = from_rules(args.rules)
    kosit, kosit_globals, kosit_ns, kosit_functions = from_xslt(args.xslt)
    problems = []
    allowed = []

    def report(ident, msg):
        (allowed if ident in args.allow else problems).append("%s: %s" % (ident or "-", msg))

    if len(mine) != len(kosit):
        report("", "%d patterns, KoSIT %d" % (len(mine), len(kosit)))
    for prefix, uri in mine_ns:
        if kosit_ns.get(prefix) != uri:
            report("", "namespace %s is %s, KoSIT %s" % (prefix, uri, kosit_ns.get(prefix)))
    mf = sorted(function_key(f) for f in mine_functions)
    kf = sorted(function_key(f) for f in kosit_functions)
    for f in mf:
        if f not in kf:
            report("", "function %s differs from or is missing in KoSIT:\n    %r" % (f[0], f))
    for f in kf:
        if f not in mf:
            report("", "KoSIT function %s differs from or is missing in the rules:\n    %r" % (f[0], f))
    for name in sorted(set(mine_globals) | set(kosit_globals)):
        if mine_globals.get(name) != kosit_globals.get(name):
            report("$" + name, "global variable differs:\n    rules: %s\n    kosit: %s" % (
                mine_globals.get(name), kosit_globals.get(name)))
    for pi, (mp, kp) in enumerate(zip(mine, kosit)):
        if len(mp) != len(kp):
            report("", "pattern %d: %d rules, KoSIT %d" % (pi + 1, len(mp), len(kp)))
        for ri, (mr, kr) in enumerate(zip(mp, kp)):
            where = "pattern %d rule %d" % (pi + 1, ri + 1)
            if mr[0] != kr[0]:
                report("", "%s context %r, KoSIT %r (fired-rule, match)" % (where, mr[0][0], kr[0]))
            if mr[1] != kr[1]:
                report("", "%s lets differ: %r / %r" % (where, mr[1], kr[1]))
            if len(mr[2]) != len(kr[2]):
                report("", "%s: %d checks, KoSIT %d" % (where, len(mr[2]), len(kr[2])))
            for mc, kc in zip(mr[2], kr[2]):
                for key in ("kind", "id", "flag", "role", "test", "executed", "parts"):
                    if mc[key] != kc[key]:
                        report(mc["id"] or kc["id"], "%s %s differs:\n    rules: %s\n    kosit: %s" % (
                            where, key, mc[key], kc[key]))
    for p in problems:
        print("DIFF " + p)
    for p in allowed:
        print("allowed " + p)
    total = sum(len(r[2]) for p in mine for r in p)
    print("%d checks compared, %d differences, %d allowed" % (total, len(problems), len(allowed)))
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
