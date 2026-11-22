# Changelog

All notable changes to this project are documented here: the changes
since the last release in this file, each release in a file of its own
under [docs/changelog](docs/changelog) (moved there when it is released).
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Schematron: `TLandrixXmlSchematronValidator.MaxResults` (default 1000,
  0 = no limit) and `Truncated`, as `MaxErrors` of the XML Schema
  validator: a document that fails a rule on every node can no longer
  make the results grow without bound (each result keeps its message and
  location). A truncated validation returns `False`, and the SVRL says
  so in a comment. Set `MaxResults := 0` for the complete report Saxon
  and the KoSIT validator give.

- XPath profile `xppSaxon`: the `let` expression of XPath 3.0
  (`let $a := E, $b := E return E`). As in Saxon, a binding is evaluated
  when its variable is first read, so one the result does not use raises
  no dynamic error. QT3 (Saxon profile): 259 more cases pass.
- The slots of `for` and `let` are emptied when the expression is done,
  so their values do not stay in memory until the evaluator is freed.
- XPath profile `xppSaxon`: the XPath 3.0 functions `format-number`
  (default decimal format; a decimal format name is FODF1280),
  `format-dateTime`, `format-date` and `format-time`, formatted as the
  XSLT processor formats them (Saxon HE, English). In `xppXPath20` they
  stay unknown (XPST0017); XSLT keeps its own (xsl:decimal-format).
  QT3 (Saxon profile): 317 more cases pass.

### Changed

- XML Schema patterns: the character classes are those of Xerces in the
  Java runtime (the validator of the KoSIT tools), no longer Saxon's:
  `.` does not match U+2028 and U+2029, `\p{..}` and `\w` take the general
  categories of Unicode 15.0 for the Basic Multilingual Plane only (a
  character above U+FFFF is only in `Cn`), `\d` the digits of Unicode 3.1,
  `\i` and `\c` the name characters of XML 1.0 Fourth Edition (with the
  ranges Xerces adds to `\i`), and `\p{Cs}` is allowed. Checked against the
  classes Xerces gives for every code point
  (`tests/data/regex/xsd-classes.txt`, new generator
  `tools/gen-regex-xsd-classes.py`); listed as Xerces
  deviations in the README. The XPath functions keep Saxon's classes.
  W3C XML Schema suite: ten cases that expect the name characters of the
  Fifth Edition now fail as with Xerces.
- XSLT: the prefixes `xs` and `fn` are bound in a stylesheet's
  expressions, sequence types and `use-when` only where the stylesheet
  declares them, as XSLT 2.0 and Saxon say (`XPST0081` otherwise; before
  they were always bound). A stylesheet Saxon runs is not affected. W3C
  XSLT suite, with the pattern checks under Fixed: six more cases pass.
- XPath: `TLandrixXmlXPathStaticContext.AddNamespace` with an empty
  namespace URI undeclares the prefix (also `xs` and `fn`); before the
  prefix stood for no namespace.
- DOM: `TLandrixXmlDocument.Clear`, and with it every `LoadFrom...`,
  starts a new name table. A document object reused for many inputs no
  longer keeps the names of all of them. The `Names` object, a
  `TLandrixXmlName` or an `ExpandedId` taken from it is valid until the
  next `Clear` or load.
- The picture formatting unit is now `LandrixXmlXPathFormat` (was
  `LandrixXmlXsltFormat`, internal) and is shared by the XPath evaluator
  and the XSLT processor; its "not supported" messages no longer start
  with "XSLT:".

- `tools/check-suite-updates.py` reports whether the pinned test suites
  and reference packages (QT3, the W3C XSLT and XML Schema suites, the
  XML conformance archive, the KoSIT suite and configurations, the
  XRechnung visualization and Schematron, EN16931, Peppol BIS, the
  ZUGFeRD configuration) have newer versions upstream; it changes
  nothing.

- `tools/run-qt3.py --profile saxon` runs the QT3 cases of an XPath 3.1
  processor (spec XP20+, XP30+, XP31 or XP31+) instead of the XPath 2.0
  ones, the first step towards XPath 3.1 in that profile: 19,090
  applicable cases, 16,560 pass (1,476 XPath 3.0/3.1 cases pass already
  and 447 raise an error where one is expected, but with another code;
  25 cases of XPath 2.0 only drop out). The XPath 2.0 profile is
  unchanged.

### Fixed

- XML Schema: `xsi:noNamespaceSchemaLocation` is checked as an
  `xs:anyURI` and `xsi:schemaLocation` as a list of them
  (`cvc-datatype-valid.1.2.1` and `cvc-attribute.3` for a value that is
  not one, as Xerces), and an identity constraint field that selects one
  of them now gets that typed value; before, such a field had no value,
  so duplicates went unnoticed.
- XML Schema: `xs:gDay`, `xs:gMonthDay` and `xs:gMonth` values with a time
  zone compare as Xerces compares them (enumeration, the bounds,
  identity constraints): when both have a time zone, only the type's own
  fields count after the move to UTC, so `---01+14:00` equals
  `---31-10:00` and `--01-01+14:00` is after `--06-01Z`; against a value
  without time zone the rules of Xerces' compareDates apply (see the
  README). Checked against Xerces in 400 random cases; new
  cases in `tests/data/xsdtypes` and `tests/data/xsdvalidator`. Listed as
  a Xerces deviation in the README.
- XSLT patterns with a union: a node the first branch failed on (a
  dynamic error in its predicate) no longer matches a later branch also
  in a second tree (`document()`, a tree parameter), as it did not in
  the source document; this holds for nested unions too.
- `TLandrixXmlXPathEvaluator.Evaluate`: a result now knows the trees a
  host function added with `AddTree` while the expression ran (before,
  reading such a node from the result looked in the wrong tree).
- XSLT patterns: the component functions of dates, times and durations
  (`day-from-date()`, `hours-from-time()`, `years-from-duration()` and
  the others, not the time zone ones) count as numbers in a predicate
  after one that failed on an earlier sibling, so that predicate no
  longer matches a node at a shifted position (Saxon matches none:
  `a[xs:integer(@k) gt 0][day-from-date(xs:date(@d))]`).
- XPath speed with many siblings: a step whose first predicate is a
  number (`preceding-sibling::*[1]`, `following::x[2]`, a pattern
  `match="i[1]"`) stops at that node instead of building the whole axis
  for every context (`preceding-sibling` now walks backwards), and a
  path step without predicates on a sibling or descendant axis skips
  the contexts whose nodes another context already gives
  (`/r/item/following-sibling::item`); duplicates are removed while a
  step collects its nodes, so its memory no longer grows with the square
  of the siblings. With 4,000 siblings `match="i[1]"` took 36 s and
  `preceding-sibling::*[1]` 19 s; both now take a fraction of a second,
  also with 20,000. The same for `[position() = k]`, `[position() < k]`
  and `[position() <= k]`; `[last()]` (and `[position() = last()]`) on a
  child or sibling axis looks for the last node from the far end, and a
  path step over `following` or `preceding` without predicates skips
  the contexts another one covers.
- Stack budget (`MaxStackBytes`) where it was missing: matching a
  pattern (`MatchesPattern`, one level per step, with its predicates)
  counts from the start of the match as an evaluation does, and the XSLT
  processor hands its budget to the XPath evaluator, so a deep
  expression in a stylesheet is measured against the whole run (before,
  the evaluator inside XSLT had no budget). A limit stays `xecLimit`
  when XSLT and Schematron report the XPath error, and an XPath error
  outside an instruction (a parameter value) reaches the caller as
  `ELandrixXmlXsltError`. New for the XSLT units:
  `TLandrixXmlXPathEvaluator.StackBase` (not part of the documented API
  yet).
- XSLT patterns are checked step by step as Saxon checks them (the rules
  of XSLT 3.0): a number, a string, a function call after the start, a
  variable after the start or a step on another axis than child,
  attribute, self, descendant or descendant-or-self (`a/..`,
  `name/1223`, `a/string()`), as are `.` at the start other than as the
  whole pattern (`./b`, `a | .`; `a/.` stays), `/` after a step (`a/(/b)`) and an argument of
  `id()` or `key()` that is no literal or variable (`id(@id)`): all
  `XTSE0340`. Before they compiled, and some matched (`a/..` the parent
  of an `a`).
- `xml:id` as Saxon treats it: XPath trees trim the white space around
  its value when a document is loaded, so `@xml:id = 'a'` holds for
  `xml:id=" a "` (the spaces inside are kept; XDM would collapse them,
  Saxon does not), and an `xml:id` attribute an XSLT stylesheet
  constructs has its white space collapsed (XSLT 2.0 11.3); a copied one
  keeps its value. QT3 (Saxon profile): fn-doc-37 passes.
- XSLT static errors as Saxon reports them: an attribute an XSLT element
  does not define (`XTSE0090`; before only for some elements, now for the
  elements of XSLT 2.0 and their XSLT 3.0 attributes; a shadow attribute
  such as `_select` is unsupported) or an
  unknown `xsl:` attribute of a literal result element (`XTSE0805`), an
  undeclared prefix in `exclude-result-prefixes` (`XTSE0808`, `#default`
  without a default namespace `XTSE0809`, `#all` with another prefix
  `XTSE0020`) and `current-group()` or `current-grouping-key()` in a
  pattern (`XTSE1060`, `XTSE1070`). Forwards compatible processing still
  ignores unknown attributes. W3C XSLT suite: 31 cases pass that failed
  before and one fails that passed; for-each-group-002a now reports
  `XTSE0090` for its `bind-group` attribute first, as Saxon does,
  instead of the `XPST0008` the suite expects.
- README: the XSLT cases that follow the specification instead of
  Saxon are listed in one place ("XSLT: the specification, not
  Saxon"), each with a mark in the source code that
  `tools/check-forbidden.py` checks against the list, as for the Xerces
  deviations.
- XSLT: names (templates, variables, parameters, keys, modes and the
  other declarations) are checked with the XML name characters: a name
  with a character that is no name character (a no-break space, a
  digit at the start) is XTSE0020 as with Saxon; before, any non-ASCII
  byte passed and declaration names were not checked at all. W3C XSLT
  suite: 5 more cases pass (error-0020e to -0020h, function-2102).
- XSLT on Delphi 6-2007: names of templates, modes, global variables,
  keys, decimal formats, attribute sets, character maps, named outputs
  and namespace aliases that the system code page cannot represent no
  longer merge (they were converted with '?' for such characters, so
  two Cyrillic template names were reported as declared twice). New in
  `LandrixXmlBase`: `LandrixXmlKeyToUtf8`, the inverse of
  `LandrixXmlUtf8ToKey`.
- XSLT: stripping white space from the source, copying a tree and
  serializing a result check the stack, so a tree built through the API
  without a depth limit raises FOER0000 (`xecLimit`) instead of
  overflowing it (copies within `MaxStackBytes` or, without a budget,
  10,000 levels; serializing within `LandrixXmlDefaultMaxStackBytes`, 4 MB
  where that is 0).
- XPath: deeply nested expressions raise FOER0000 (`xecLimit`) instead
  of overflowing the stack. The parser stops at 3000 levels or 256 KB of
  stack (about 125 levels of parentheses with Delphi 6, where 500 levels
  crashed the program) and at an expression tree deeper than 1000 levels
  (a long chain such as `1+1+...`), the evaluator applies `MaxStackBytes`
  from the start of the evaluation, and a chain of more than 3000 variables evaluated
  within each other (`let $b := $a, $c := $b, ...`) is a limit too.
- XML Schema: `TLandrixXmlXsdSchemaSet.Files` lists two documents whose
  names differ only in case as two files on case-sensitive systems
  (Linux); the list compared the names without case before.
- XML Schema: compiling a content model no longer gives every leaf a
  bit set over all leaves (65,536 leaves in one model took 512 MB);
  only groups keep one.
- Double parsing on 32-bit x86: the exact path loads the x87 control
  word directly instead of through Set8087CW, which writes the global
  Default8087CW; on Delphi Win32 two threads parsing at once could swap
  their control words (Set8087CW loads the word back from the global).
- Smaller fixes from the review: an xs:decimal whose fraction has more
  than a million digits is accepted when the digits beyond the limit are
  trailing zeros (`1.5` followed by a million zeros is 1.5);
  `TLandrixXmlXsdSimpleType.CreateUnion` raises `xecInvalidArgument`
  for an empty member list, as the loader rejects `<xs:union/>`; a typed
  XSLT variable whose conversion fails with a non-XPath exception is
  evaluated again instead of being reported as circular; unresolved
  IDREFs after the one that truncates the result at `MaxErrors` are no
  longer formatted. The README lists the
  UTF-16 counting of the length facets as a Xerces deviation.
- Test tools, from the review: a missing baseline fails the QT3, XSLT
  and XSTS runners; `--update-baseline` refuses with `--filter`, on
  harness errors and on regressions (unless `--force-baseline`); a
  baseline case missing from the suite and a `--filter` without matches
  fail; helper exit codes and timeouts count; the W3C XML conformance
  run checks the catalog hash and the test count, and its deviation
  categories no longer excuse errors in the document body or every
  encoding error; the fuzzer reports a crash that needs a sequence of
  files and sorts its seeds; check-forbidden.py finds constructs split
  over lines.
- Schematron compilers (library and tools/sch-compile.py) agree on more
  input: `sch:active` without `pattern` activates no pattern, `sch:ns`
  without prefix or uri and `sch:let` without name (in the schema, a
  pattern or a rule) are errors in both,
  tools/sch-compile.py rejects `xsl:otherwise` before `xsl:when` and
  keeps a carriage return of a message as a reference. Generator tools
  fail with a clear message instead of a traceback or silent data, clean
  up their temporary folders and `--check` exits non-zero on
  differences; `LandrixXmlCaseData.inc` has the license header.
- Documentation from the review: the XSLT resolver note names both
  resolvers and `unparsed-text()`, method text reports SERE0008, unit
  headers of the XPath parser, the XML Schema loader and validator and
  the Schematron unit describe what the code does; the list of
  downloaded test suites is complete.
- Compiler and platform differences from the review: the Schematron
  compiler strips the byte order mark of a `document()` file also on
  Delphi 2009+ and takes a drive letter as absolute only on Windows;
  `LandrixXmlFormatDouble` rejects 1e23 on every compiler (x87 accepted
  it); a template priority of more than 255
  characters is read by the library's parser (FPC refused it, x87 could
  overflow); `unparsed-text()` reads a resolver stream in blocks without
  Size or Seek (a stream that cannot seek failed, more than 2 GB were
  cut, a failed read ended the text); the string
  value of an XPath tree node and the serializer buffer check their
  lengths without Integer overflow; `LandrixXmlNormalizeUtf8` and
  `LandrixXmlIsNormalizedUtf8` refuse a string of MaxInt bytes or more
  (xecLimit).
- XPath tree and formatting, edges from the review: `format-date` gives
  the right weekday, day of the year and ISO week for years in the
  millions (the day count overflowed) and an error with code for a year
  beyond Integer; the width modifier is read after the last comma, on
  bytes; `LoadFromFile` and `LoadFromUtf8` of `TLandrixXmlXPathTree`
  leave an empty tree when they fail (a missing file kept the old tree
  and its base URI).
- XPath parser, edges from the review: `.5div 2` is a syntax error like
  `1.5div 2`; a wildcard as cast target (`1 cast as xs:*`) or before "("
  (`a/*(1)`) is XPST0003; the namespace axis is XPST0010 (not
  supported); a numeric literal beyond the decimal limits is FOAR0002
  instead of an error without code. A variable whose prefix is not bound
  is not found under the empty namespace.
- XSLT compiler, static checks from the review (as Saxon): the mode list
  of a template is checked (XTSE0550 for `#all` with another mode, a mode
  twice, `#current` or a name that is no QName; W3C XSLT suite: six more
  cases pass); an empty `match` is XTSE0340; an included or
  imported module without `version` is XTSE0010; a user-defined data
  element at the top level is ignored with its content; two global
  variables or named templates of the same precedence are an error only
  if no declaration of higher precedence overrides them; a comment in a
  match pattern no longer changes its default priority; `key()` in a
  pattern on a tree without document node means no match (XTDE1270 was
  raised).
- XSLT serialization, edges from the review: characters the encoding
  lacks, escaped URIs and mapped characters are written in linear time
  (a long text in US-ASCII took minutes); in HTML `script` and `style` a
  character the encoding lacks is a character reference, as in Saxon,
  not SERE0008 (also for the strings of a character map in HTML); a C0 control
  character (from a parameter) is a character reference, as in Saxon;
  `undeclare-prefixes="yes"` with XML 1.0 raises SEPM0010 and
  `standalone` without an XML declaration SEPM0009; the declaration names
  the encoding `utf8` UTF-8; the HTML indentation counts characters after
  normalization; namespace declarations are sorted in UTF-16 order on
  every compiler and the output method is chosen on the bytes of the root name, the
  same on every compiler.
- Schematron, edges from the review: `sch:value-of` merges adjacent
  text nodes as `xsl:value-of` does (`*/text()` over `<a>foo</a><b>bar</b>`
  gives `foobar`, not `foo bar`); `svrl:suppressed-rule` carries the id,
  role and flag of its rule, as in SchXslt; a rule context with the
  keyword `union` is rejected as unsupported (its right branch was not
  matched at any depth); a tree without nodes is an argument error.
- XML Schema loader, edge cases from the review: an attribute group
  referenced twice (directly or through other groups) no longer counts
  as a duplicate attribute (ct-props-correct.4); a repeated namespace in
  a wildcard list no longer drops a namespace of the base in an
  extension; an attribute group with two ID attributes is rejected
  (ag-props-correct.3), also when no type uses it; the occurrence ranges
  of a restriction no longer overflow Int64 with deeply nested large
  bounds; an included document with `targetNamespace=""` is a chameleon,
  as in Xerces.
- XML Schema content models, edge cases from the review: a count of
  High(Integer) (also any larger bound, which the loader limits to it)
  no longer counts as fixed in Unique Particle Attribution, so
  `minOccurs="2147483647" maxOccurs="2147483648"` before the same
  element is reported as ambiguous. A repeated group with a
  large minOccurs around a repeated element stops with `xecLimit`
  instead of taking cubic time, and the Unique Particle Attribution
  automaton stops after about a second of work (the model is then taken
  as unambiguous, as for the existing size limits; see Limitations).
  After the first content error the following children are looked up
  by name instead of comparing every particle. A wildcard counted over
  the whole content (as Xerces does) is now listed among the Xerces
  deviations.
- XPath general comparison: an xs:untypedAtomic beside an xs:anyURI is
  cast to xs:anyURI first, so its white space is collapsed
  (`xs:untypedAtomic(' urn:a ') = xs:anyURI('urn:a')` is true, as in
  Saxon); it was compared as written. This also holds for an attribute
  compared directly (`@u = xs:anyURI('urn:a')`), which Saxon compares
  as written.
- XPath functions, edge cases from the review: `fn:sum` checks its zero
  argument also for a non-empty input, and a literal `()` as precision
  of `fn:round` or `fn:round-half-to-even` is XPTY0004 also for an empty
  number (as Saxon). In the XPath 2.0 profile `fn:sum` and `fn:avg`
  promote all values to their common type before adding (two large
  floats next to a double no longer overflow to INF). In XPath 1.0
  compatibility mode a literal `()` stays empty for an optional string
  argument and is a type error for a required one, as in Saxon.
  Resolving a URI removes dot segments in linear time (a long relative
  `xml:base` took seconds).
- Values, edge cases from the review: `LandrixXmlParseDouble` kept the
  powers of ten it had moved into the mantissa when it fell back to the
  RTL, so an integer of 39 to about 54 digits came out too small (1
  followed by 38 zeros gave 1e23); on x87 its exact path now rounds to
  nearest whatever the caller set. Decimal division checks the exponent of
  the result instead of the intermediate scale, and `mod` computes the
  remainder directly, so an intermediate value beyond the exponent limit
  no longer raises FOAR0002 when the result is representable.
- XSLT runtime, edge cases from the review (results as Saxon HE 12):
  doc(), document() and unparsed-text() treat a resource the resolver finds
  but cannot open (a locked file) as not available (`doc-available()` is
  false, `doc()` FODC0002) instead of letting a stream error through;
  `document()` returns its documents
  in document order; `key()` sorts its matches in O(n log n) (it was an
  insertion sort, quadratic for many values in random order); the name of
  `xsl:element` and `xsl:attribute` may have white space around it;
  `xsl:message terminate` is trimmed, takes true/false/1/0 and is XTDE0030
  before the content runs (XTSE0020 when fixed) for other values;
  `grouping-size` takes a plus sign; `xsl:for-each-group` compares two
  integers or decimals exactly (an xs:double with them as before), so
  distinct integers beyond 2^53 no longer share a group, and durations of
  different types are equal keys (also in `key()`); `generate-id()` of a parentless attribute no longer
  reads outside the tree (a range error in checked builds) and keeps its
  numbering per tree; a key's use expression has no current group
  (XTDE1061); one tree passed for two parameters has one identity; the
  implicit principal result of `TransformToTree` gets the base output URI;
  an empty string or text node besides `xsl:result-document` is XTDE1490.
- DOM, edge cases from the review: `DeclareNamespace` (and
  `SetAttributeNsUtf8`) rejects a declaration that would change the
  namespace of a descendant that takes the prefix from outside (and, as
  for prefixes before, the default namespace of the element itself);
  `SetAttributeNsUtf8` with the local name `xmlns` and no namespace is
  rejected (it was written as a namespace declaration); the document type declaration cannot be moved
  after the root element (it failed only when saving); moving an element
  without namespace that declares a default namespace itself no longer
  raises, and elements without namespace moved below a late default
  namespace get no `xmlns=""`.
- XSLT: `xsl:number level="single"` with `count` and `from` gives a
  number only when the counted node or one of its ancestors matches
  `from`, as Saxon (the specification lets the root stand in for it,
  which numbered such nodes before; without `count` Saxon does that too).
- XML Schema validator: the fields of a composite identity constraint
  (key, unique, keyref with several fields) are compared one by one. Before,
  a TAB in a string field could make two different tuples equal, so a
  keyref without a key passed and two different keys counted as duplicates.
- XML Schema validator: an element with very many differently named
  children no longer makes validation quadratic (80,000 names: 59 s, now
  0.3 s). The sibling positions for error paths are counted in a hash
  table.
- `LandrixXmlBase`: `LandrixXmlHashSalt` and `LandrixXmlHashFinish` for hash
  tables keyed by names from untrusted documents; the salt is chosen per
  process, so colliding names cannot be prepared in advance.
- XPath tree: many adjacent CDATA sections or text pieces are joined in
  linear time (16 MB in 16,000 pieces on FPC: 195 s, now 2 s), and the
  location paths of Schematron results no longer cost the number of
  distinct names per parent (40,000 parents with their own names: 25 s,
  now 0.7 s). New `TLandrixXmlXPathTree.ValueLength`.
- Reader and writer: thousands of namespace declarations in scope no
  longer make every element slow (prefixes are looked up in a table), a
  long namespace URI is not hashed again for every prefixed attribute,
  and the attribute duplicate checks use the salted hash, so prepared
  colliding names no longer make them quadratic (16,384 colliding
  attributes through reader, writer and DOM: 64 s, now 0.6 s).
- DOM and XPath tree: each namespace URI is kept once per document instead
  of once per distinct name, and the name tables use the salted hash
  (32,768 colliding names: 4.5 minutes, now 1.2 s).
- DOM: moving a subtree that was edited while detached could put a missing
  declaration on the subtree's root, where it changed the namespace of
  another element (e.g. `xmlns=""` taking the root out of its default
  namespace) or was shadowed by a declaration inside. Such a declaration
  now goes to the element that needs it.
- `xs:decimal`: multiplication and long division of huge values from a
  document are limited by the new `LandrixXmlDecimalMaxDigitProduct`
  (FOAR0002 beyond 20,000 × 20,000 digits; two values of 200,000 digits
  took 31 s), and rounding, casts to integer and the minute carry of
  `xs:duration` divide by powers of ten in linear time.
- XSLT: the default resolver kept only the path of a `file:` URI with a
  host (`file://server/share/x.xsl`, the base URI of a stylesheet on a
  network share) and could open `\share\x.xsl` on the current drive. Such
  a URI is now not read by the default resolver (no local file, and no
  network connection a URI from a document could trigger); an
  application resolver can map it.
- XSLT: the document cache of `doc()`/`document()` and the check for two
  `xsl:result-document` with the same URI no longer merge URIs that
  differ only in characters outside the system code page (Delphi 6-2007,
  FPC on Windows).
- XSLT on Delphi 6-2007 and on FPC under Windows: `xsl:key` and
  `xsl:for-each-group` merged key values with characters outside the
  system code page (e.g. Cyrillic keys all became `??`). New
  `LandrixXmlUtf8ToKey` gives lossless keys for lookups.
- Reader, DOM, XPath tree, writer and XML Schema validator: a long
  namespace URI inherited by many elements is no longer hashed and copied
  again for every element. The reader keeps one string per URI and
  document, and the name tables find it by its address (one 200 KB URI,
  40,000 elements: XPath tree 30 s, now 0.09 s).
- Reader: after a start tag failed (for example on a duplicate
  attribute), `AttributeNamespaceUriUtf8` could report the namespace of an
  attribute of an earlier element.
- Reader: `ReadElementText` joins many text pieces (split by comments,
  PIs or CDATA sections) in linear time, and asking for `Line` of the end
  token of `<x/>` after `TokenEndLine` continues from the previous
  position checkpoint instead of counting lines from the start of the
  document for every such element.
- Writer: `DocumentType` accepts content that starts with the internal
  subset (`<!DOCTYPE a[...]>`, as the reader reports it), so such a
  document can be saved after loading; comments in the subset with `--`
  and processing instructions with the target `xml` are refused.
- Writer: a failed call that had closed the open start tag of the parent
  (for example `ElementNs` with an invalid value) left that tag's
  attributes overwritten, so a duplicate attribute could be written
  after it; `AttributeNs` with no prefix and the local name `xmlns` is
  refused instead of writing a default namespace declaration;
  `Base64FromStream` raises on a read error of the stream instead of
  treating it as the end.
- Input: `LoadFromStream` raises on a read error of the stream instead of
  treating it as the end of the document, refuses a stream whose size
  is known to exceed the buffer limit before buffering it, and accepts
  inputs just below the limit; a failed `LoadFromBuffer` leaves the input
  empty like every other failed load.
- `LandrixXmlBase64Encode` and `LandrixXmlBase64Decode` work when the
  input lies in the destination buffer itself (the buffer could move or
  the output overwrite unread input); decoding beyond the buffer limit
  raises `xecLimit`. On 64-bit FPC, strings longer than the buffer limit
  raise `xecLimit` in the UTF-8 checks and conversions instead of being
  cut to a wrapped length.
- XSLT: copying elements with very many attributes or namespace
  declarations no longer costs time quadratic in their number for the
  duplicate check of attributes, the in-scope namespaces and the sorting
  of declarations in the output. New
  `TLandrixXmlXPathTree.InScopeNamespacesUtf8` returns the in-scope
  prefixes with their URIs in one pass.
- XPath: `/` with an atomic context item raises XPTY0020 (was XPDY0002);
  in XPath 1.0 compatibility mode of the XPath 2.0 profile an error in
  the left operand of `and` and `or` is raised (XPath 2.0, 3.6) instead
  of being decided away by the right operand (the Saxon profile keeps
  Saxon's behaviour); the comment of `ClearCache` says that variables
  keep their values and are bound again; an error from MaxDepth or
  MaxStackBytes is no longer kept as the value of a lazy variable (it
  depends on where the variable is first read); binding slot -1 (an
  unknown variable) raises `xecInvalidArgument` instead of writing
  outside the globals; the compiled regular expressions are found by
  hash and kept up to 1024 per evaluator (patterns can come from a
  document).
- XPath: `fn:replace` reported the step limit of a back-reference search
  as FORX0004 (an error in the replacement string), which an XSLT match
  pattern then treated as no match; it is now the limit error.
  `xsl:analyze-string` checks the size of its match table.
- XML Schema validator: `ValidateReader` treats white space written as
  character references (`&#32;`) in element-only content as white space,
  as `ValidateDocument` and Xerces do; after `MaxErrors` the rest of the
  document is still read, so a syntax error the reader finds after the
  last collected error still raises; `ValidateDocument` of a document
  without a root element raises `xecInvalidArgument` instead of an
  access violation.
- XML Schema: `xs:anyURI` refuses a port above 65535 on a bracketed IPv6
  host, as Xerces does; seconds with more than 1,000,000 fraction digits
  make a date or time invalid instead of raising an exception; a
  `whiteSpace` facet value with white space around it (` collapse `) is
  accepted; dates near the ends of the year range no longer raise an
  overflow in builds with overflow checks.
- XML Schema: comparing dates and times across the start of year 1 counted
  a year 0, which XML Schema 1.0 does not have
  (`-0001-12-31T23:00:00-01:00` and `0001-01-01T00:00:00Z` are the same
  instant).
- XML Schema validator: after a reference to an external or undeclared
  parameter entity in the internal subset, later entity declarations no
  longer count for `xs:ENTITY` values unless the document is
  `standalone="yes"` (XML 1.0, 5.1).

## Releases

- [0.5.0](docs/changelog/0.5.0.md) - 2026-11-17
- [0.4.0](docs/changelog/0.4.0.md) - 2026-11-12
- [0.3.0](docs/changelog/0.3.0.md) - 2026-11-10
- [0.2.0](docs/changelog/0.2.0.md) - 2026-10-15
- [0.1.0](docs/changelog/0.1.0.md) - 2026-10-15

[Unreleased]: https://github.com/landrix/LandrixXML-for-Pascal/compare/v0.5.0...HEAD
