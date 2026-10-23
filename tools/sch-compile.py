#!/usr/bin/env python3
"""Compile a Schematron file (ISO Schematron, queryBinding xslt2) into the rule
file LandrixXmlSchematron loads.

  python tools/sch-compile.py SCHEMA.sch OUT.xml [--url URL] [--title TEXT]
                                [--override ID=TEST ...]

--override replaces the test of an assert or report, for the cases where the
upstream source and the XSLT the KoSIT validator runs differ (what KoSIT runs
is the reference, tools/sch-crosscheck.py finds the cases); the rule file
marks such a check with original="..." (the test of the source).

Handled: sch:include (whole documents), sch:ns, sch:let (in the schema and in
patterns: global; in rules: per rule), sch:pattern, sch:rule (context, id,
abstract rules are rejected), sch:assert and sch:report (id, flag, role, test,
message text with sch:name and sch:value-of), sch:phase (the phases must
name a default phase that activates every pattern with a rule, else the
file is rejected; without a default phase all patterns run, as in SchXslt), and the subset
of XSLT functions the XRechnung and Peppol rules use: xsl:function with
xsl:param, xsl:variable (select, text content or one xsl:sequence child) and
one result, either xsl:sequence or xsl:choose with xsl:when/xsl:otherwise around
xsl:sequence. Variables inside a choose branch become function variables (they
are evaluated lazily, so this does not change the result); their names must be
unique within the function. This tool does not check that a lifted variable is
used only inside its branch (it has no XPath parser); the Pascal compiler does.

Anything else (abstract patterns, sch:extends, sch:diagnostics, sch:properties,
sch:param, the Schematron 2025 elements group, library and rules, the
attributes diagnostics, properties and subject of checks, documents of
patterns, "as" of lets, other XSLT elements, elements without a namespace,
one prefix bound to two namespaces, every attribute of a Schematron or XSLT
element not in ALLOWED, xml:space="preserve", xml:base) is rejected
with file and line, never dropped; elements of other namespaces
(documentation) are ignored.
source/LandrixXmlSchematronCompiler.pas does the same in Pascal; the tests
compare both on tests/data/schematron/sources. sch:include is replaced by the included element where it stands
(recursively; cycles are rejected). The expressions are copied as written
(white space outside string literals collapsed); the XPath parser checks them
when the rule file is loaded.

Output: one XML document

  <rules xmlns="urn:landrix:schematron-rules" format="1" source=".." sha256=".."
         title=".." [url=".."]>
    <ns prefix=".." uri=".."/>
    <let name=".." value=".." line=".."/>                       global
    <function name=".." as=".." line="..">
      <param name=".." as=".."/> <variable name=".." as=".." value=".."/>
      <result value=".."/>
    </function>
    <pattern id="..">
      <rule context=".." id=".." line="..">
        <let name=".." value=".."/>
        <assert|report id=".." flag=".." role=".." test=".." line="..">
          <text>..</text> <value-of select=".."/> <name path=".."/>
        </assert>
      </rule>
    </pattern>
  </rules>
"""

import argparse
import hashlib
import os
import sys
import xml.etree.ElementTree as ET
from xml.sax.saxutils import quoteattr, escape

SCH = "http://purl.oclc.org/dsdl/schematron"
XSL = "http://www.w3.org/1999/XSL/Transform"
XML_SPACE = "{http://www.w3.org/XML/1998/namespace}space"
XML_BASE = "{http://www.w3.org/XML/1998/namespace}base"
OUT_NS = "urn:landrix:schematron-rules"


class CompileError(Exception):
    pass


# The attributes (without namespace) a Schematron or XSLT element may have
# here; elements not listed are not checked (rejected or ignored as a whole).
# Some are allowed only to reject them with a better message where the
# element is compiled; icon, see and fpi are documentation. As
# AllowedAttributes in LandrixXmlSchematronCompiler.
DOC_ATTRS = {"icon", "see", "fpi"}
ALLOWED = {
    (SCH, "schema"): {"queryBinding", "schemaVersion", "defaultPhase", "id"} | DOC_ATTRS,
    (SCH, "ns"): {"prefix", "uri"},
    (SCH, "let"): {"name", "value", "as"},
    (SCH, "pattern"): {"id", "abstract", "is-a", "documents"} | DOC_ATTRS,
    (SCH, "rule"): {"context", "id", "flag", "role", "abstract", "subject"} | DOC_ATTRS,
    (SCH, "assert"): {"test", "id", "flag", "role", "diagnostics", "properties", "subject"} | DOC_ATTRS,
    (SCH, "report"): {"test", "id", "flag", "role", "diagnostics", "properties", "subject"} | DOC_ATTRS,
    (SCH, "name"): {"path"},
    (SCH, "value-of"): {"select"},
    (SCH, "emph"): set(),
    (SCH, "dir"): {"value"},
    (SCH, "span"): {"class"},
    (SCH, "phase"): {"id"} | DOC_ATTRS,
    (SCH, "active"): {"pattern"},
    (SCH, "include"): {"href"},
    (XSL, "function"): {"name", "as"},
    (XSL, "param"): {"name", "as", "select"},
    (XSL, "variable"): {"name", "as", "select"},
    (XSL, "sequence"): {"select"},
    (XSL, "choose"): set(),
    (XSL, "when"): {"test"},
    (XSL, "otherwise"): set(),
}


def tag(el):
    if el.tag.startswith("{"):
        ns, local = el.tag[1:].split("}", 1)
        return ns, local
    return "", el.tag


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


class LineParser:
    """ElementTree elements with the line of their start tag (expat, namespaces resolved)."""

    @staticmethod
    def parse(path):
        import xml.parsers.expat
        lines = {}
        builder = ET.TreeBuilder()
        parser = xml.parsers.expat.ParserCreate(namespace_separator="}")

        def name(n):
            return "{" + n if "}" in n else n

        def start(n, attrs):
            el = builder.start(name(n), {name(k): v for k, v in attrs.items()})
            lines[id(el)] = parser.CurrentLineNumber

        parser.StartElementHandler = start
        parser.EndElementHandler = lambda n: builder.end(name(n))
        parser.CharacterDataHandler = builder.data
        parser.buffer_text = True
        parser.ordered_attributes = False
        with open(path, "rb") as f:
            parser.Parse(f.read(), True)
        return builder.close(), lines


class Compiler:
    def __init__(self, path):
        self.path = path
        self.docs = []           # (root, path, lines)
        self.ns = []
        self.globals = []
        self.functions = []
        self.patterns = []
        self.global_names = set()

    def where(self, el, doc):
        root, path, lines = doc
        return "%s:%s" % (os.path.basename(path), lines.get(id(el), "?"))

    def fail(self, msg, el=None, doc=None):
        if el is not None:
            raise CompileError("%s: %s" % (self.where(el, doc), msg))
        raise CompileError(msg)

    def load(self, path):
        root, lines = LineParser.parse(path)
        doc = (root, path, lines)
        self.docs.append(doc)
        self.check_attributes(root, doc)
        return doc

    def check_attributes(self, el, doc):
        """Every attribute without namespace that a Schematron or XSLT element
        may not have is rejected (attributes of other namespaces are allowed).
        Documentation (sch:title, sch:p, other namespaces) is not looked into.
        xml:space="preserve" (white space text content in XSLT, also through
        sch:include) and xml:base (other include paths) are not supported."""
        if not isinstance(el.tag, str):
            return
        ns, local = tag(el)
        if ns not in (SCH, XSL) or (ns, local) in ((SCH, "title"), (SCH, "p")):
            return
        if el.get(XML_SPACE) == "preserve":
            self.fail('xml:space="preserve" is not supported', el, doc)
        if el.get(XML_BASE) is not None:
            self.fail("xml:base is not supported", el, doc)
        allowed = ALLOWED.get((ns, local))
        if allowed is not None:
            for a in el.attrib:
                if not a.startswith("{") and a not in allowed:
                    self.fail("the attribute %s of %s:%s is not supported"
                              % (a, "sch" if ns == SCH else "xsl", local), el, doc)
        for c in el:
            self.check_attributes(c, doc)

    def include(self, el, doc):
        """The root of the document an sch:include names, loaded; a cycle is an error."""
        href = el.get("href")
        if not href or "#" in href:
            self.fail("sch:include needs a plain href", el, doc)
        path = os.path.normcase(os.path.abspath(os.path.join(os.path.dirname(doc[1]), href)))
        if path in self.including:
            self.fail("sch:include of %s is circular" % href, el, doc)
        return self.load(path), path

    def compile(self):
        self.including = [os.path.normcase(os.path.abspath(self.path))]
        self.load(self.path)
        main = self.docs[0][0]
        if tag(main) != (SCH, "schema"):
            raise CompileError("not a Schematron schema: " + self.path)
        qb = main.get("queryBinding", "xslt")
        if qb not in ("xslt2", "xslt3"):
            raise CompileError("queryBinding %r is not supported" % qb)
        self.walk(main, self.docs[0])
        self.check_phases()

    def walk(self, el, doc, top=True):
        ns, local = tag(el)
        if ns == SCH:
            if local in ("schema",):
                for c in el:
                    self.walk(c, doc)
            elif local == "include":
                inc, path = self.include(el, doc)
                if tag(inc[0]) == (SCH, "schema"):
                    self.fail("sch:include of a whole schema is not supported", el, doc)
                self.including.append(path)
                self.walk(inc[0], inc)
                self.including.pop()
            elif local in ("title", "p", "phase", "active"):
                pass
            elif local == "ns":
                for prefix, uri in self.ns:
                    if prefix == el.get("prefix") and uri != el.get("uri"):
                        self.fail("the prefix %s is bound to two namespaces" % prefix, el, doc)
                self.ns.append((el.get("prefix"), el.get("uri")))
            elif local == "let":
                self.add_global(el, doc)
            elif local == "pattern":
                self.pattern(el, doc)
            elif local in ("diagnostics", "properties", "extends", "param"):
                self.fail("sch:%s is not supported" % local, el, doc)
            elif local in ("group", "library", "rules"):
                self.fail("sch:%s (Schematron 2025) is not supported" % local, el, doc)
            else:
                self.fail("unexpected sch:%s" % local, el, doc)
        elif ns == XSL:
            if local == "function":
                self.function(el, doc)
            else:
                self.fail("xsl:%s outside a function is not supported" % local, el, doc)
        elif ns == "":
            self.fail("element %s without namespace" % local, el, doc)
        else:
            # foreign elements (documentation) are ignored as Schematron allows
            pass

    def add_global(self, el, doc):
        name = el.get("name")
        if name in self.global_names:
            self.fail("global variable $%s is defined twice" % name, el, doc)
        if el.get("value") is None:
            self.fail("a let without value is not supported", el, doc)
        if el.get("as") is not None:
            self.fail("a let with \"as\" is not supported", el, doc)
        self.global_names.add(name)
        self.globals.append((name, collapse(el.get("value")), self.where(el, doc)))

    def pattern(self, el, doc):
        if el.get("abstract") == "true" or el.get("is-a"):
            self.fail("abstract patterns are not supported (compile the preprocessed file)", el, doc)
        if el.get("documents") is not None:
            self.fail("patterns on other documents are not supported", el, doc)
        rules = []

        def member(c, doc):
            ns, local = tag(c)
            if (ns, local) == (SCH, "let"):
                self.add_global(c, doc)
            elif (ns, local) == (SCH, "rule"):
                rules.append(self.rule(c, doc))
            elif (ns, local) == (SCH, "include"):
                inc, path = self.include(c, doc)
                self.including.append(path)
                member(inc[0], inc)
                self.including.pop()
            elif (ns, local) in ((SCH, "title"), (SCH, "p")):
                pass
            elif ns == SCH:
                self.fail("unexpected sch:%s in a pattern" % local, c, doc)
            elif ns == XSL:
                self.fail("xsl:%s in a pattern is not supported" % local, c, doc)
            elif ns == "":
                self.fail("element %s without namespace" % local, c, doc)
        for c in el:
            member(c, doc)
        self.patterns.append((el.get("id") or "", rules))

    def rule(self, el, doc):
        if el.get("abstract") == "true":
            self.fail("abstract rules are not supported", el, doc)
        if el.get("context") is None:
            self.fail("a rule without context", el, doc)
        if el.get("subject") is not None:
            self.fail("the subject of a rule is not supported", el, doc)
        lets, checks = [], []
        names = set()
        for c in el:
            ns, local = tag(c)
            if (ns, local) == (SCH, "let"):
                if c.get("value") is None:
                    self.fail("a let without value is not supported", c, doc)
                if c.get("as") is not None:
                    self.fail("a let with \"as\" is not supported", c, doc)
                if c.get("name") in names:
                    self.fail("rule variable $%s is defined twice" % c.get("name"), c, doc)
                names.add(c.get("name"))
                lets.append((c.get("name"), collapse(c.get("value"))))
            elif (ns, local) in ((SCH, "assert"), (SCH, "report")):
                checks.append(self.check(c, local, doc))
            elif (ns, local) == (SCH, "extends"):
                self.fail("sch:extends is not supported", c, doc)
            elif ns == SCH:
                self.fail("unexpected sch:%s in a rule" % local, c, doc)
            elif ns == XSL:
                self.fail("xsl:%s in a rule is not supported" % local, c, doc)
            elif ns == "":
                self.fail("element %s without namespace" % local, c, doc)
        return {"context": collapse(el.get("context")), "id": el.get("id") or "", "line": self.where(el, doc),
                "lets": lets, "checks": checks}

    def check(self, el, kind, doc):
        if el.get("test") is None:
            self.fail("sch:%s without test" % kind, el, doc)
        if el.get("diagnostics") is not None:
            self.fail("diagnostics are not supported", el, doc)
        if el.get("properties") is not None:
            self.fail("properties are not supported", el, doc)
        if el.get("subject") is not None:
            self.fail("the subject of a check is not supported", el, doc)
        parts = []

        def content(e):
            """Text, sch:name and sch:value-of; emph, dir and span only add their content."""
            if e.text:
                parts.append(("text", e.text))
            for c in e:
                ns, local = tag(c)
                if (ns, local) == (SCH, "name"):
                    parts.append(("name", c.get("path") or ""))
                elif (ns, local) == (SCH, "value-of"):
                    parts.append(("value-of", collapse(c.get("select"))))
                elif (ns, local) in ((SCH, "emph"), (SCH, "dir"), (SCH, "span")):
                    content(c)
                else:
                    self.fail("%s inside sch:%s is not supported" % (local, kind), c, doc)
                if c.tail:
                    parts.append(("text", c.tail))
        content(el)
        return {"kind": kind, "id": el.get("id") or "", "flag": el.get("flag") or "", "role": el.get("role") or "",
                "test": collapse(el.get("test")), "line": self.where(el, doc), "parts": parts}

    def function(self, el, doc):
        name = el.get("name")
        params, variables = [], []
        result = None
        names = set()
        def check_no_text(owner):
            """No text where XSLT would put it into the result."""
            if (owner.text or "").strip(WS) or any((c.tail or "").strip(WS) for c in owner):
                self.fail("text in %s is not supported" % owner.tag.split("}")[-1], owner, doc)

        def variable(v):
            vname = v.get("name")
            if vname in names:
                self.fail("variable $%s is defined twice in %s" % (vname, name), v, doc)
            names.add(vname)
            if v.get("select") is not None:
                if len(v) or (v.text or "").strip(WS):
                    self.fail("xsl:variable with select and content", v, doc)
                value = collapse(v.get("select"))
            elif len(v) == 1 and tag(v[0]) == (XSL, "sequence") and v[0].get("select") is not None:
                # without as the content would build a document node
                if not v.get("as"):
                    self.fail("xsl:variable with an xsl:sequence child needs as", v, doc)
                if len(v[0]) or (v[0].text or "").strip(WS):
                    self.fail("xsl:sequence needs select and no content", v[0], doc)
                if (v.text or "").strip(WS) or (v[0].tail or "").strip(WS):
                    self.fail("xsl:variable with text around xsl:sequence", v, doc)
                value = collapse(v[0].get("select"))
            elif len(v) == 0:
                # text content: a document node with that text; atomized it is untypedAtomic
                if not (v.text or "").strip(WS):
                    self.fail("xsl:variable without select and content is not supported", v, doc)
                value = "xs:untypedAtomic(%s)" % string_literal(v.text)
                if v.get("as"):
                    self.fail("xsl:variable with text content and as is not supported", v, doc)
            else:
                self.fail("this form of xsl:variable is not supported", v, doc)
            variables.append((vname, v.get("as") or "", value))

        def body(elements, where):
            """The result expression of a sequence of variables and one result instruction."""
            res = None
            for c in elements:
                ns, local = tag(c)
                if (ns, local) == (XSL, "variable"):
                    if res is not None:
                        self.fail("xsl:variable after the result", c, doc)
                    variable(c)
                elif (ns, local) == (XSL, "sequence"):
                    if res is not None:
                        self.fail("more than one result instruction", c, doc)
                    if c.get("select") is None or len(c) or (c.text or "").strip(WS):
                        self.fail("xsl:sequence needs select and no content", c, doc)
                    res = "(" + collapse(c.get("select")) + ")"
                elif (ns, local) == (XSL, "choose"):
                    if res is not None:
                        self.fail("more than one result instruction", c, doc)
                    res = choose(c)
                else:
                    self.fail("xsl:%s is not supported in a function" % local, c, doc)
            if res is None:
                self.fail("no result in " + where, where_el, doc)
            return res

        def choose(c):
            whens = [w for w in c if tag(w) == (XSL, "when")]
            others = [w for w in c if tag(w) == (XSL, "otherwise")]
            if len(whens) + len(others) != len(c) or len(others) > 1 or not whens:
                self.fail("unsupported xsl:choose", c, doc)
            check_no_text(c)
            for b in whens + others:
                check_no_text(b)
            expr = body(list(others[0]), "xsl:otherwise") if others else "()"
            for w in reversed(whens):
                expr = "(if (%s) then %s else %s)" % (collapse(w.get("test")), body(list(w), "xsl:when"), expr)
            return expr

        where_el = el
        rest = []
        for c in el:
            if tag(c) == (XSL, "param"):
                if rest:
                    self.fail("xsl:param after other instructions", c, doc)
                if c.get("select") is not None or len(c) or (c.text or "").strip(WS):
                    self.fail("default values of parameters are not supported", c, doc)
                if c.get("name") in names:
                    self.fail("parameter $%s is defined twice" % c.get("name"), c, doc)
                names.add(c.get("name"))
                params.append((c.get("name"), c.get("as") or ""))
            else:
                rest.append(c)
        check_no_text(el)
        result = body(rest, "function " + name)
        for f in self.functions:
            if f["name"] == name and len(f["params"]) == len(params):
                self.fail("function %s#%d is defined twice" % (name, len(params)), el, doc)
        self.functions.append({"name": name, "as": el.get("as") or "", "line": self.where(el, doc),
                               "params": params, "variables": variables, "result": result})

    def check_phases(self):
        """SchXslt runs all patterns unless the schema names a default phase; such a
        phase must activate every pattern with a rule."""
        main = self.docs[0][0]
        default = main.get("defaultPhase")
        if not default or default == "#ALL":
            return
        for root, path, lines in self.docs:
            for ph in root.iter("{%s}phase" % SCH):
                if ph.get("id") != default:
                    continue
                active = {a.get("pattern") for a in ph.iter("{%s}active" % SCH)}
                for pid, rules in self.patterns:
                    if rules and pid not in active:
                        raise CompileError("%s: the default phase %s does not activate pattern %s; phases are not "
                                           "supported" % (self.where(ph, (root, path, lines)), default, pid))
                return
        raise CompileError("the default phase %s is not defined" % default)

    def override(self, items):
        for item in items:
            if "=" not in item:
                raise CompileError("--override needs ID=TEST: " + item)
            ident, test = item.split("=", 1)
            found = [c for _, rules in self.patterns for r in rules for c in r["checks"] if c["id"] == ident]
            if len(found) != 1:
                raise CompileError("--override %s: %d checks have this id" % (ident, len(found)))
            found[0]["original"] = found[0]["test"]
            found[0]["test"] = collapse(test)

    def write(self, out, url, title):
        raw = open(self.path, "rb").read()
        sha = hashlib.sha256(raw).hexdigest()
        main = self.docs[0][0]
        if title is None:
            t = main.find("{%s}title" % SCH)
            title = collapse("".join(t.itertext())) if t is not None else ""
        a = lambda v: quoteattr(v)
        lines = ['<?xml version="1.0" encoding="UTF-8"?>',
                 '<rules xmlns="%s" format="1" source=%s sha256="%s" title=%s%s>' % (
                     OUT_NS, a(os.path.basename(self.path)), sha, a(title), (" url=" + a(url)) if url else "")]
        seen = set()
        for p, u in self.ns:
            if p in seen:
                continue
            seen.add(p)
            lines.append("  <ns prefix=%s uri=%s/>" % (a(p), a(u)))
        for n, v, w in self.globals:
            lines.append("  <let name=%s value=%s line=%s/>" % (a(n), a(v), a(w)))
        for f in self.functions:
            lines.append("  <function name=%s as=%s line=%s>" % (a(f["name"]), a(f["as"]), a(f["line"])))
            for n, t in f["params"]:
                lines.append("    <param name=%s as=%s/>" % (a(n), a(t)))
            for n, t, v in f["variables"]:
                lines.append("    <variable name=%s as=%s value=%s/>" % (a(n), a(t), a(v)))
            lines.append("    <result value=%s/>" % a(f["result"]))
            lines.append("  </function>")
        for pid, rules in self.patterns:
            if not rules:
                continue
            lines.append("  <pattern id=%s>" % a(pid))
            for r in rules:
                lines.append("    <rule context=%s id=%s line=%s>" % (a(r["context"]), a(r["id"]), a(r["line"])))
                for n, v in r["lets"]:
                    lines.append("      <let name=%s value=%s/>" % (a(n), a(v)))
                for c in r["checks"]:
                    msg = "".join(part_xml(k, v) for k, v in c["parts"])
                    orig = (" original=" + a(c["original"])) if "original" in c else ""
                    lines.append("      <%s id=%s flag=%s role=%s test=%s line=%s%s>%s</%s>" % (
                        c["kind"], a(c["id"]), a(c["flag"]), a(c["role"]), a(c["test"]), a(c["line"]), orig, msg,
                        c["kind"]))
                lines.append("    </rule>")
            lines.append("  </pattern>")
        lines.append("</rules>")
        with open(out, "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(lines) + "\n")


def part_xml(kind, value):
    if kind == "text":
        return "<text>%s</text>" % escape(value)
    if kind == "name":
        return "<name path=%s/>" % quoteattr(value)
    return "<value-of select=%s/>" % quoteattr(value)


def string_literal(s):
    return "'" + s.replace("'", "''") + "'"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("schema")
    ap.add_argument("out")
    ap.add_argument("--url")
    ap.add_argument("--title")
    ap.add_argument("--override", nargs="*", default=[])
    args = ap.parse_args()
    c = Compiler(args.schema)
    try:
        c.compile()
        c.override(args.override)
    except CompileError as e:
        sys.exit("sch-compile: " + str(e))
    c.write(args.out, args.url, args.title)
    n = sum(len(r) for _, r in c.patterns)
    k = sum(len(x["checks"]) for _, r in c.patterns for x in r)
    print("%s: %d patterns, %d rules, %d asserts/reports, %d globals, %d functions" % (
        args.out, len([p for p in c.patterns if p[1]]), n, k, len(c.globals), len(c.functions)))


if __name__ == "__main__":
    main()
