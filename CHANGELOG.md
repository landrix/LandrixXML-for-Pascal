# Changelog

All notable changes to this project are documented in this file.
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

- DOM: `TLandrixXmlDocument.Clear`, and with it every `LoadFrom...`,
  starts a new name table. A document object reused for many inputs no
  longer keeps the names of all of them. The `Names` object, a
  `TLandrixXmlName` or an `ExpandedId` taken from it is valid until the
  next `Clear` or load.
- The picture formatting unit is now `LandrixXmlXPathFormat` (was
  `LandrixXmlXsltFormat`, internal) and is shared by the XPath evaluator
  and the XSLT processor; its "not supported" messages no longer start
  with "XSLT:".

- `tools/run-qt3.py --profile saxon` runs the QT3 cases of an XPath 3.1
  processor (spec XP20+, XP30+, XP31 or XP31+) instead of the XPath 2.0
  ones, the first step towards XPath 3.1 in that profile: 19,090
  applicable cases, 16,560 pass (1,476 XPath 3.0/3.1 cases pass already
  and 447 raise an error where one is expected, but with another code;
  25 cases of XPath 2.0 only drop out). The XPath 2.0 profile is
  unchanged.

### Fixed

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

## [0.5.0] - 2026-11-17

An XSLT 2.0 processor (`LandrixXmlXslt`, optional) that runs the KoSIT
report stylesheets and the XRechnung visualization with the output
Saxon HE writes, byte for byte; XPath 1.0 compatibility mode, SVRL into
an open writer with the message text as the rule file has it, and a
stack budget for deep recursion. The documented API only gains
additions.

### Added

- XSLT (`LandrixXmlXslt`, optional): a subset of XSLT 2.0 run as Saxon
  HE runs it, with `TLandrixXmlXsltStylesheet` (compiled once,
  immutable), `TLandrixXmlXsltTransformer` (parameters as strings, trees
  or XPath values, initial mode and template, output properties,
  messages), `TLandrixXmlXsltResolver` (imports and documents from files
  or a catalog, no network) and `ELandrixXmlXsltError` (an
  `ELandrixXmlXPathError` with the W3C code, the module and the line).
  See the README for the supported instructions; the KoSIT report
  stylesheet and the XRechnung visualization (XR XML and HTML) give the
  output Saxon gives, byte for byte.
  `TLandrixXmlErrorCode` gains `xecXslt`.
- XSLT: `system-property()`, `function-available()` and
  `element-available()`; a name given with a prefix is resolved with the
  namespaces of the calling expression.
- XSLT: output in US-ASCII and ISO-8859-1. A character the encoding does
  not have is a hexadecimal character reference in text and attribute
  values and `SERE0008` elsewhere (comments, names, method text), as in
  Saxon.
- XSLT: `xsl:strip-space` and `xsl:preserve-space`.
- XSLT: `use-when` and `xsl:use-when` (conditional inclusion).
- XSLT: `xsl:sort` (in `xsl:for-each`, `xsl:apply-templates` and
  `xsl:for-each-group`), `xsl:perform-sort`, `xsl:analyze-string` and
  `regex-group()`.
- XSLT: `xsl:next-match` and `xsl:apply-imports` (with `xsl:with-param`).
- XSLT: `xsl:attribute-set` and `use-attribute-sets` (on literal result
  elements, `xsl:element` and `xsl:copy`).
- XSLT: `xsl:character-map` and `use-character-maps` (on `xsl:output`
  and `xsl:result-document`), applied by the xml, html, xhtml and text
  output methods as in Saxon.
- XSLT: `xsl:namespace`. An excluded namespace that a literal result
  element or its attribute uses is no longer a namespace node of its own:
  the namespace fixup declares it, as in Saxon. The fixup keeps an
  attribute's own prefix where nothing on the element binds it otherwise
  and names new prefixes as Saxon does. `exclude-result-prefixes` now
  excludes the namespace URIs bound where it is, not every later binding
  of the same prefix.
- XSLT: `xsl:namespace-alias` (literal result elements, their attributes
  and namespace nodes; an aliased or alias result namespace is copied
  even when excluded).
- XSLT: simplified stylesheets (a literal result element with
  `xsl:version` as a stylesheet module).
- XSLT: `xpath-default-namespace` and `xsl:xpath-default-namespace`.
- XSLT: `xml:base` in a stylesheet: the static base URI of the
  instructions below it (`static-base-uri()`, `resolve-uri()`, `doc()`,
  `document()`, `unparsed-text()`), the `href` of `xsl:include` and
  `xsl:import`, and the base URI of the temporary trees an instruction
  makes and of nodes made or copied at the top of a sequence, as Saxon
  gives them.
- XSLT: `xsl:key` with a sequence constructor instead of `use`, and key
  names with a prefix (`key()` resolves it with the namespaces of the
  calling expression).
- XSLT: English words and ordinals as Saxon HE writes them, in
  `xsl:number` (`format="w"`, `"W"`, `"Ww"`, `ordinal`) and in the
  pictures of `format-date()` and its relatives (`[Dwo]`, `[D1o]`, also
  letters `[Da]`). `xsl:number` accepts `lang` (an invalid language code
  is `XTDE0030`; the numbers stay English, as in Saxon HE) and
  `letter-value`. A year cut to a maximum width is its last digits as a
  number, as in Saxon (`[Y1,*-3]` of 2013 is `13`, no longer `013`).
- XSLT: `[xsl:]expand-text` (XSLT 3.0 text value templates, as Saxon
  also runs them in a stylesheet with `version="2.0"`): text in a sequence
  constructor and in `xsl:text` with expressions in braces (`{{` and `}}`
  for braces, empty braces for the empty sequence); `XTSE0350`,
  `XTSE0370` and `XTSE0020` as for attribute value templates.
- XSLT: `copy-namespaces="no"` on `xsl:copy` and `xsl:copy-of`: a copy
  has the namespaces its names need; below the top of a deep copy an
  element has those and the ones of the place the copy goes to, as
  Saxon writes them (also `xmlns=""` or a declaration repeated).
  `true`/`1`/`false`/`0` are accepted as in Saxon; another value is
  `XTSE0020`.
- XSLT: the output property `byte-order-mark` for every output method:
  as in Saxon the byte order mark is written for UTF-8 only (none for
  US-ASCII or ISO-8859-1); `TransformToUtf8` and `SerializeToUtf8` begin
  with it when the encoding asked for is UTF-8.
- XSLT: `disable-output-escaping` on `xsl:text` and `xsl:value-of`, as
  in Saxon: text written to the final result tree (also by
  `xsl:result-document`) is serialized without escaping; the character
  map, normalization and character references for characters the
  encoding lacks still apply, and a CDATA section ends before it. A text
  node a function or a template with `as` returns stays raw when it is
  added to the result (not when it is copied with `xsl:copy-of`). It is
  ignored in temporary trees, attributes and comments, and when the
  result is returned as a tree; where Saxon keeps it in a node built in
  a sequence or in a temporary tree it is `xecUnsupported` at run time.
  Besides yes and no, `true`, `1`, `false` and `0` are accepted as in
  Saxon; another value is `XTSE0020`.
- XSLT: a collation URI that is not known as a collation is the error
  of the specification: `XTDE1035` (`xsl:sort`), `XTDE1110`
  (`xsl:for-each-group`; `FOCH0002` for a computed one, as in Saxon),
  `XTSE1210` (`xsl:key`), `XTSE0125` (`default-collation` without a known
  collation). `default-collation` takes the first known collation of its
  list, and the collation of `xsl:for-each-group` may be an attribute
  value template. UCA, Saxon and `html-ascii-case-insensitive`
  collations remain unsupported.
- XSLT: the output property `normalization-form` (NFC, NFD, NFKC, NFKD,
  none) for every output method: text, attribute values and CDATA
  sections are normalized, names and comments are not; as in Saxon the
  character map comes first and its strings are not normalized. Another
  value (also `fully-normalized`) is `SESU0011` when the result is
  serialized.
- XSLT: forwards compatible processing for a version above 3.0, as in
  Saxon: unknown declarations are ignored with their content, an unknown
  instruction runs its `xsl:fallback` (`XTSE0010` without one), unknown
  attributes of XSLT elements are ignored. A version that is no decimal
  is `XTSE0110` (one below 2.0: backwards compatible processing, below).
- XSLT: `extension-element-prefixes` (also on `xsl:template` and other
  XSLT elements, and as `xsl:extension-element-prefixes` on literal
  result elements). No extension instruction is known: an element in an
  extension namespace runs its `xsl:fallback` children, or raises
  `XTDE1450` when it is evaluated without one; the extension namespaces
  are not copied to literal result elements. As in Saxon, `#default`
  means no namespace.
- XSLT: `doctype-system` and `doctype-public` (xml and xhtml: with a
  system identifier; html: either, the name `html`), written as Saxon
  writes them before the first element; with `doctype-system` or
  `standalone` a second element or text at the top is `SEPM0004`; a
  public identifier with a character other than the XML PubidChar (or a
  tab), or a system identifier with both quote characters, is
  `XTSE0020`.
- XSLT: `cdata-section-elements` on `xsl:output` (the union of every
  definition) and `xsl:result-document` (added to the format's), for the
  xml and xhtml methods. The text of those elements is written in CDATA
  sections as Saxon writes them: `]]>` split, a character the encoding
  does not have as a character reference between sections, no character
  map. The output property holds the Clark names.
- XSLT: `document()` with a second argument (the base URI of that node for
  every relative URI; `XPTY0004` for no single node, `XTDE1162` without a
  base URI).
- XPath: `TLandrixXmlXPathStaticContext.DefaultElementNamespace` (the
  default element/type namespace, '' unless set), also readable on the
  compiled expression.
- XSLT: the output method xhtml, as Saxon writes it (also the default
  method for an `html` root element in the XHTML namespace).
- XSLT: tunnel parameters (`tunnel="yes"` on `xsl:with-param` and
  template parameters). An initial template with a required parameter is
  `XTDE0060`, as in XSLT 2.0.
- XSLT: `xsl:result-document` and named `xsl:output` definitions.
  Secondary results are collected by the transformer
  (`ResultDocumentCount`, `ResultDocuments`, `FindResultDocument`,
  `TLandrixXmlXsltResultDocument`), `href` resolves against the new
  `BaseOutputUri`; nothing is written to disk.
- `tools/run-xslt-tests.py` runs the XSLT 1.0 and 2.0 cases of the W3C
  XSLT test suite against a baseline (`tests/data/xslt-baseline.txt`).
- XPath: the string concatenation operator `||` (XPath 3.0) in the
  `xppSaxon` profile, as Saxon accepts it in stylesheets that declare
  XSLT 2.0; `a || b || c` is `concat(a, b, c)`. The `xppXPath20` profile
  rejects it with XPST0003.
- XPath: XPath 1.0 compatibility mode
  (`TLandrixXmlXPathStaticContext.XPath10Compatible`, default `False`,
  kept by each expression): function arguments take the first item and
  are converted with `fn:string` or `fn:number`, arithmetic works on the
  first items as `xs:double` (NaN for an empty operand), and general
  comparisons follow XPath 1.0, all as in Saxon. Arguments of user
  functions follow the caller's mode.
- XSLT: backwards compatible processing. A stylesheet or element with a
  version below 2.0 (an XSLT 1.0 stylesheet) is no longer rejected: its
  expressions run in XPath 1.0 compatibility mode, `xsl:value-of`,
  attribute value templates, `xsl:number` and sort keys take the first
  item, `key()` compares strings, an undeclared parameter is ignored and
  function arguments are converted as in XPath 1.0, as Saxon does.
  `system-property('xsl:supports-backwards-compatibility')` is `yes`.
- `tools/xslt-crosscheck.py --config bis|zugferd|all` also checks the
  report stylesheets of the Peppol BIS and ZUGFeRD configurations of the
  KoSIT validator (each with its own `default-report.xsl`), and every
  configuration with a schema error, a document that is not well-formed
  and one no scenario matches.
- Schematron: `SaveSvrlToWriter` writes the SVRL element into an open
  writer (`SaveSvrlToStream` calls it, its output is unchanged);
  `RawMessage` on the results is the message with the white space of the
  rule file, and `SvrlPreserveWhitespace` writes it into `svrl:text` as
  SchXslt and the KoSIT validator do.
- XPath and XSLT: `MaxStackBytes` on `TLandrixXmlXPathEvaluator` and
  `TLandrixXmlXsltTransformer`, a budget for the stack nested user
  functions and templates may use; beyond it the run stops with
  `FOER0000` (`xecLimit`) instead of overflowing the stack. The default,
  `LandrixXmlDefaultMaxStackBytes`, is 3/4 of the program's stack size on
  Windows and 0 (no budget) elsewhere.

### Changed

- Schematron: text in an assert or report that is only white space
  (between two `sch:value-of`, for example) is left out by the compiler
  and `tools/sch-compile.py`, as the XSLT processor strips it from the
  stylesheet SchXslt generates.
- XPath: a call of a user function no longer goes through the frame of
  the built-in functions; a level of the stylesheet recursion of the W3C
  case function-0701 takes 2.4 KB of stack instead of 8.4 KB with Delphi
  Win64, where it overflowed the 1 MB stack.
- XSLT: the XML output writes U+007F to U+009F and U+2028 as character
  references, as Saxon does.
- XSLT: an XPath comment inside the braces of an attribute value
  template may contain braces.
- XSLT: white space in the stylesheet is stripped after comments and
  processing instructions are removed (text around a comment is one text
  node), and white space before `xsl:param` and `xsl:sort` is stripped
  even under `xml:space="preserve"`.
- XPath: `distinct-values()` finds repeated strings through a hash table:
  120,000 values with 60,000 distinct strings took more than ten
  minutes, now about two seconds.

### Fixed

- XSLT: `exclude-result-prefixes` on XSLT elements other than
  `xsl:stylesheet` (for example `xsl:template`) was ignored.

## [0.4.0] - 2026-11-12

Exact normalization check, faster XPath and XML Schema validation, a fix
for nested repetitions in content models and two portability fixes. The
documented API only gains additions.

### Added

- `LandrixXmlNormalize`: `LandrixXmlIsNormalizedUtf8` and
  `LandrixXmlIsNormalizedCodePoints` tell exactly whether a text is in a
  normalization form (the Unicode quick check, and a normalization only
  when it answers "maybe"). The code point variant rejects values that
  are not Unicode scalar values with `xecInvalidUnicode`. The constant
  `LandrixXmlNormalizeUnicodeVersion` names the Unicode version of the
  normalization data (15.0.0); characters assigned later pass through
  unchanged. Every line of the Unicode file NormalizationTest.txt also
  checks the new functions.

### Changed

- `LandrixXmlDouble`: integers below 10^15 (below 10^7 for xs:float) are
  converted to a double directly instead of through a big-integer
  division; the result is the same. An XPath comparison such as
  `cl[@id = 15]`, which converts every `@id` and the integer this way,
  is about five times faster.
- `LandrixXmlXPathEval`: a child step `name[@attribute = value]` whose
  value does not depend on the focus (a literal, a variable, a path from
  `document()`) finds its matches through an index of the children by
  that attribute, built on first use per parent with at least 16 such
  children, if the values are strings or untypedAtomic. The Factur-X
  code list checks (`.../cl[@id=N]/enumeration[@value=$v]`) no longer
  scan the list. Together with the faster integer conversion the
  Factur-X 1.09.2 EXTENDED rules take about 40 % of the time before.
- XML Schema validation is faster on large documents, with the same
  results: the content model finds the particles that can take a child
  through a name table and bit sets instead of comparing names; values,
  identity constraint keys, error paths and type names are built only
  where they are used; white space normalization returns the value
  itself when nothing changes; text the validator does not look at is
  no longer copied. A 50 MB GAEB DA XML 3.3 file (X83) takes about two
  thirds of the time before.
- `LandrixXmlXsdValidator`: the record `TLandrixXmlXsdFrame`, documented as
  internal, has `PathIndex` instead of `PathStep`.

### Fixed

- XML Schema content models: of the configurations a child leaves, those
  another one covers (same position, counts no higher and already at
  their lower bounds) are dropped. Nested repetitions such as
  `(a+){1,100000000}` in a repeated choice no longer stop with `xecLimit`
  "Content model too ambiguous to check" after a minute; the three XSTS
  tests `particlesZ036_b1`, `_b2` and `_c` pass, and the whole XSTS run
  takes 45 seconds instead of 4.5 minutes.
- `LandrixXmlNormalize`: an input or a result of more than `MaxInt` code
  points raises `xecLimit` instead of overflowing the Integer
  arithmetic (64-bit only).
- `LandrixXmlDom`: copies names without `Move`. FPC 3.2.4 on aarch64-darwin
  reported note 6058 ("Move ... marked as inline is not inlined") there in
  the builds of some consuming projects, despite `{$WARN 6058 OFF}`.

## [0.3.0] - 2026-11-10

Native XML Schema and Schematron validation, as optional units: the
reader, writer, DOM and conversion units of 0.2.0 do not depend on them
and are unchanged in their API.

- XML Schema 1.0 validation (`LandrixXmlXsdTypes`, `LandrixXmlXsdContent`,
  `LandrixXmlXsdSchema`, `LandrixXmlXsdSchemaLoader`,
  `LandrixXmlXsdValidator`) with the verdicts, error codes, messages and
  order of Xerces in the Java runtime (the validator behind KoSIT and
  Mustang); the deliberate differences from the specification are listed
  in the README. W3C XML Schema Test Suite: 39,225 of 39,336 applicable
  tests pass.
- XPath 2.0 (`LandrixXmlXPathTree`, `LandrixXmlXPath`,
  `LandrixXmlXPathEval`) in two profiles, the specification and Saxon HE,
  and Schematron (`LandrixXmlSchematron`, `LandrixXmlSchematronCompiler`)
  with SVRL output: EN16931, XRechnung, Peppol BIS and Factur-X give the
  same results as the KoSIT validator with Saxon (KoSIT test suite: 86 of
  86 equal).
- Building blocks: exact decimal arithmetic (`LandrixXmlDecimal`),
  `xs:double`/`xs:float` in software (`LandrixXmlDouble`), XSD and XPath
  regular expressions (`LandrixXmlRegex`), Unicode categories and
  normalization (`LandrixXmlUnicode`, `LandrixXmlNormalize`), SHA-256
  (`LandrixXmlSha256`).

The details follow.

### Added
- Examples for XML Schema validation and XPath queries in
  `examples/LandrixXmlExamples.dpr` and the README; `SECURITY.md`.
- `THIRD-PARTY-NOTICES.md` with `LICENSES/Unicode-3.0.txt` and
  `LICENSES/Apache-2.0.txt`: the sources of the generated tables (Unicode
  Character Database, XML 1.0 character classes, Saxon case mappings), the
  Apache Xerces material of the XML Schema validation, and a pointer to the
  notices of the test data.
- `TLandrixXmlReader.TokenEndLine` and `TokenEndColumn`: the position right
  after the current token, where XML Schema validators report errors.
- `LandrixXmlDecimal`: exact decimal arithmetic for `xs:decimal` and
  `xs:integer` with arbitrary precision (add, subtract, multiply, divide,
  `idiv`, `mod`, comparison, rounding modes, Int64 conversion, the digit
  counts of the `totalDigits`/`fractionDigits` facets). Division follows
  Saxon, the XSLT engine of the KoSIT validator, so that sum checks give
  the same results. First building block of the planned XSD and
  Schematron validation; the existing units do not depend on it.
- `LandrixXmlDecimalMultiplyPow10`: exact multiplication by a power of ten.
- `LandrixXmlDouble`: `xs:double` computed in software on the IEEE 754 bit
  pattern (`TLandrixXmlDouble`): arithmetic, `mod`, comparison, rounding,
  parsing with correct rounding, exact conversion to and from `xs:decimal`,
  and the XPath string value with the digits Saxon writes. Results are the
  same on every compiler and CPU and never raise floating-point exceptions.
- `tools/gen-double-testdata.py`: generates the double test cases and
  optionally checks them against Saxon.
- `LandrixXmlRegex`: regular expressions in the XML Schema and XPath
  dialects (`Matches`, `Replace`, `Tokenize`), matched by a Pike VM in
  time linear in the input per match, so untrusted input cannot cause
  catastrophic backtracking. Hyphens in character classes follow XML
  Schema 1.0 in XSD mode (as Xerces) and 1.1 in XPath mode (as Saxon).
  Programs are limited to about 100000 instructions and a nesting depth of 1000
  (`xecLimit`, raised before anything oversized is built).
  Unsupported constructs (flags, back-references, reluctant quantifiers,
  block escapes) raise the new error code `xecUnsupported`, invalid
  patterns the new code `xecRegex`.
- `LandrixXmlUnicode`: Unicode 6.2.0 general categories (the version
  Saxon uses for regular expressions) and code point conversion;
  `tools/gen-unicode-tables.py` generates the table.
- `tools/gen-regex-testdata.py`: regular expression test cases with
  results from Saxon.
- `LandrixXmlXsdTypes`: XML Schema 1.0 simple types (the built-in types,
  restriction with facets, unions) with the same checks, order and
  `cvc-...` codes as the XML Schema validator of the Java runtime used by
  the KoSIT validator.
- `LandrixXmlXsdContent`: content models of complex types (nested
  sequences and choices with occurrence bounds, element and wildcard
  particles), checked child by child with the error codes, expected lists,
  positions and recovery of the XML Schema validator of the Java runtime
  (including its three ways of checking occurrence bounds);
  `tools/gen-xsdcontent-testdata.py` generates test cases with that
  validator. `XsdOracle` now reports a runtime exception of the JDK's
  validator as `jdk-exception` and goes on with the next document.
- `TLandrixXmlUtf8Array` moved from `LandrixXmlRegex` to `LandrixXmlBase`.
- `LandrixXmlXsdSchema`, `LandrixXmlXsdSchemaLoader`, `LandrixXmlXsdValidator`:
  an XML Schema 1.0 validator. Schemas are loaded at run time (include,
  import, redefine also of schemas without target namespace, groups,
  attribute groups, derivation, wildcards, identity constraints) into an
  immutable set that validators in several threads can share. Documents
  are validated while they are read or as a loaded DOM, with the errors,
  messages, order and recovery of the validator of the Java runtime;
  positions as Xerces reports them when reading, paths such as
  `/Invoice/cac:InvoiceLine[2]/cbc:ID[1]` and the schema file and line of
  each error. Unsupported constructs are rejected at load time
  (`xecUnsupported`), invalid schemas raise the new code `xecSchema`.
  Each schema document is checked against the rules of the schema for
  schemas (the attributes of each schema element and their value types,
  its children and their order, no character data outside annotations,
  no id twice); invalid schemas raise the new
  `ELandrixXmlXsdSchemaError` (a `ELandrixXmlError` with `Code` xecSchema)
  with `ConstraintCode` (the code Xerces reports, e.g.
  `s4s-att-not-allowed`), `SchemaFile` and the position in `Line` and
  `Column`.
  The facets of a simple type are checked against each other and against
  the base type as Xerces checks them (for example minLength not above
  maxLength, bounds in order, lengths and digits not wider than the base
  type's, a facet given twice); `fixed` on facets is honoured
  (`AddFacet` has a new parameter `Fixed`, default False). No facets on
  `xs:anySimpleType` itself, as in Xerces.
  Content models are checked for Unique Particle Attribution as Xerces
  checks them (`cos-nonambig`; on its rewritten model, with the same
  verdicts on 1,200 random models in `tests/data/xsdcontent/upa.txt`);
  `TLandrixXmlXsdContentModel.FindAmbiguity` gives the two competing
  particles.
  Element and attribute declarations are checked as Xerces checks them:
  default and fixed values must be valid for the type (also in their
  canonical form; for elements with complex types only simple or
  emptiable mixed content allows one), not on ID types, a default only
  with `use="optional"`, a use of a declaration with a fixed value only
  with the same fixed value, no attribute named `xmlns` or in the xsi
  namespace, and elements of the same name in one content model have the
  same type (`cos-element-consistent`). New
  `TLandrixXmlXsdSimpleType.IsIdType`.
  Type derivations are checked as Xerces checks them, except the
  restriction of particles: `final` and `finalDefault` of complex and
  simple types (also for list item and union member types), no
  restriction of `xs:anySimpleType` itself, the base of simple content,
  the content types of extensions and mixed restrictions, a local simple
  type of a simple content restriction derived from the base's, at most
  one attribute of an ID type, and the attributes and attribute wildcard
  of a restriction against those of the base (required, type, fixed
  value, wildcard subset and processContents). New
  `TLandrixXmlXsdSimpleType.MemberCount` and `Members`.
  References and directives are checked as Xerces checks them: a
  document refers only to its own target namespace, the built-in types
  and the namespaces it imports itself (`src-resolve.4`), does not import
  its own namespace (`src-import.1`), has no two global components of the
  same name (`sch-props-correct.2`, also a component redefined twice),
  and a redefinition refers to the redefined component as Xerces requires
  (`src-redefine.5` to `.7`; an attribute group without a reference to
  itself must restrict the original).
  The particles of a restriction are checked against those of the base
  as Xerces checks them (`rcase-*`, `cos-particle-restrict`,
  `derivation-ok-restriction.5.3.2` and `.5.4.2`, with Xerces' removal of
  pointless groups and its effective ranges), also a group redefined
  without a reference to itself against the original
  (`src-redefine.6.2.2`). The content models are now checked when every
  type is complete, in Xerces' order (consistent elements, restriction,
  Unique Particle Attribution).
  A restriction of a union may have `pattern` and `enumeration` facets,
  validated as Xerces does: the patterns on the value with collapsed
  white space, then the member types in order, then the enumeration
  against the value of the member type that accepted it (before,
  `AddFacet` raised `xecUnsupported` for them; a facet on a type made by
  `CreateUnion` itself now raises `xecInvalidOperation`).
  The built-in type `xs:QName` is supported: prefixes resolve in the
  namespace context of the value (the document's for element and
  attribute values, the schema's for enumeration, default and fixed
  values), an undeclared prefix is reported as `UndeclaredPrefix`, two
  QNames are equal by namespace and local name, and the length facets do
  not apply (as Xerces). New `TLandrixXmlXsdNamespaceContext`, overloads
  `TLandrixXmlXsdSimpleType.Validate` and `AddFacet` with a context,
  `xspQName`, the fields `NamespaceUri` and `LocalName` of
  `TLandrixXmlXsdValue` and `TLandrixXmlXsdAtomicValue`, and
  `ConstraintActual` (the value the loader validated) on element and
  attribute declarations and attribute uses; the validator compares fixed
  values with it. `tools/XsdOracle.java` takes any leading Xerces key of
  a message as its code.
  `xsi:type` and `xsi:nil` in documents are validated as Xerces does:
  the type named by
  `xsi:type` replaces the declared one and must derive from it without
  the derivations the declaration and its type block (cvc-elt.4); with
  `xsi:type` an element without declaration is validated with that type
  instead of laxly; a default value must also be valid for the type
  (cvc-elt.5.1.1); `xsi:nil="true"` on a nillable element requires empty
  content and skips its value and content checks (cvc-elt.3); both
  attributes are validated as QName and boolean. A key field matching an
  element of a nillable declaration is an error, as in Xerces
  (cvc-identity-constraint.4.2.3). An `xsi:type` naming `xs:ENTITY` or
  `xs:ENTITIES` is reported as unsupported.
  The derivation data is public: `TLandrixXmlXsdDerivation` moved to
  `LandrixXmlXsdTypes` and gained `xdList`, `xdUnion` and
  `xdSubstitution`, with the set `TLandrixXmlXsdDerivations`;
  `TLandrixXmlXsdSimpleType.Final` and `DerivationOk`,
  `TLandrixXmlXsdComplexType.Final` and `Block`,
  `TLandrixXmlXsdElementDecl.Nillable` and `Block`, and
  `TLandrixXmlXsdSchemaSet.TypeDerivationOk`. The `block` attribute of
  complex types is read.
  `xs:all` is supported as Xerces does: its elements in any order, each
  at most once, the expected list naming those not yet present, an
  optional group that may stay empty; the schema constraints
  cos-all-limited (an all group only as the whole content model, its
  elements and references to it occurring at most once, no extension
  adding particles to an all group or an all group to particles), Unique
  Particle Attribution and the restriction rules with all groups
  (rcase-Recurse, rcase-RecurseUnordered, rcase-NSRecurseCheckCardinality).
  New particle kind `xpkAll` in `LandrixXmlXsdContent`; an element in an
  all group may carry any occurrence bounds for the schema-for-schemas
  check, as in Xerces, and is rejected by cos-all-limited.2 instead.
  `tools/gen-xsdcontent-testdata.py --all` generates the all group cases
  in `tests/data/xsdcontent/all.txt`. A reference to a type, element,
  group, attribute or attribute group that does not exist is reported
  with the code `src-resolve`, as in Xerces (the code was empty).
  Substitution groups and abstract elements are supported as Xerces
  does: a member takes the place of its head in a content model (also in
  all groups) and is validated with its own declaration, unless the head
  blocks substitution or the derivation of the member's type is blocked
  by the head's `block` or a type's `block`; an element without a type
  takes that of its head; an abstract element in a document is reported
  (cvc-elt.2). The loader checks e-props-correct.4 (the member's type
  derived from the head's, within the head's `final`) and .6 (circular
  substitution groups), Unique Particle Attribution and
  cos-element-consistent with the members, and treats a head with members
  as a choice of them in restrictions, as Xerces does. New in the API:
  `TLandrixXmlXsdElementDecl.SubstitutionGroup`, `Abstract` and `Final`;
  `TLandrixXmlXsdParticle.AddSubstitute`, `SubstituteCount` and
  `MatchingDecl`. `tools/gen-xsdcontent-testdata.py --subst` generates the
  content model cases with substitution groups in
  `tests/data/xsdcontent/subst.txt`.
  `xs:duration` is supported as Xerces does (new primitive
  `xspDuration`; the value's fields in `DateTime`, negative for a
  negative duration): its lexical form with Xerces' limits, the order over
  the four reference dates of XML Schema 1.0 with Xerces' arithmetic (P1D
  equals PT24H, P1M and P30D are incomparable), the canonical form
  P1Y0M0DT0H0M0S in messages, enumeration, range facets, fixed values and
  identity constraints. Fixed: a type that sets one of maxInclusive and
  maxExclusive (or minInclusive and minExclusive) no longer also checks
  the other one inherited from its base, as in Xerces.
  Notation declarations and `xs:NOTATION` are supported as Xerces does
  (new primitive `xspNotation`, a value resolved like a QName): a
  notation needs a public or a system identifier (PublicSystemOnNotation),
  the enumeration of a NOTATION type must name declared notations
  (src-resolve), and an element or attribute declaration of an atomic
  NOTATION type needs an enumeration (enumeration-required-notation).
  Length facets do not apply, as for QName; messages name the validator
  'QName', as Xerces does.
  `xs:ENTITY` and `xs:ENTITIES` are supported as Xerces does: an NCName
  that names an unparsed entity declared in the internal subset of the
  document's DOCTYPE (`<!ENTITY name SYSTEM "uri" NDATA notation>`, also
  through internal parameter entities), else
  UndeclaredEntity; ENTITIES is a list of them with at least one item.
  The internal subset is read when the first ENTITY value is checked;
  a parameter entity of the DOCTYPE that refers to itself raises
  `xecSyntax`, one that nests deeper than 64 levels or expands to more
  than 1 MiB `xecLimit`.
  A value that fails the ID or ENTITY rules is still the value of
  identity constraints, as in Xerces. A type name of the XML Schema
  namespace that is no built-in type is src-resolve.4.2 (src-resolve if
  the namespace is imported), as in Xerces, instead of unsupported.
  The XPath expressions of selectors and fields are parsed as Xerces
  does (its scanner and the subset of XML Schema 1.0, 3.11.6, white space
  between tokens allowed): an expression outside the subset is
  c-general-xpath instead of unsupported, an undeclared prefix
  c-general-xpath-ns, a selector that ends at an attribute
  c-selector-xpath and a field with an attribute step before its end
  c-fields-xpaths.
  The extension of `xs:anyType` is supported as Xerces does: the type
  has anyType's content (any element, laxly assessed, mixed) followed by
  its own particle, and the union of its attribute wildcard with
  anyType's.
  List types (`xs:list`, the built-in `NMTOKENS` and `IDREFS`) are
  validated as Xerces does: patterns on the whole value, then each item,
  then the length facets (counting items) and enumeration; IDs and IDREFs
  in lists count, list values work in identity constraints and fixed
  values. `TLandrixXmlXsdSimpleType.CreateList`, `ItemType`, the variety
  `xsvList` and the list items of `TLandrixXmlXsdValue` (`Variety`,
  `Items` of the new `TLandrixXmlXsdAtomicValue`) give access to them.
  An include, import or redefine whose document cannot be found is
  skipped as XML Schema 1.0 allows and listed in the schema set's
  `Warnings`.
  Elements without a declaration are assessed laxly with `anyType`;
  identity constraints follow Xerces' value tables and XPath matching,
  a keyref outside the scope of its key is reported as
  `KeyRefOutOfScope`. `tools/gen-xsdvalidator-testdata.py` generates the
  test cases, `tests/data/xsdvalidator/edge` holds one small case per rule.
- `tools/check-xerces-drift.py`: reruns every generator that asks the Java
  runtime's XML Schema validator with another JDK and reports the files
  that come out differently; `tests/data/xerces-oracle.txt` records the
  runtime of the committed data. The schema rule tests moved to
  `tests/data/xsdschema/rules.txt`, checked against the JDK by
  `tools/check-xsdrules.py`.
- `LandrixXmlXPathTree`: a read-only tree of a document in the XPath data
  model, built from the pull reader or from a DOM: nodes in document order
  in flat arrays, attributes as nodes, text and CDATA merged, numbered
  expanded names, string values and the locations SchXslt writes.
- `LandrixXmlXPath`: XPath 2.0 lexer, parser and syntax tree for the part of
  the language the EN16931, XRechnung, Peppol and Factur-X rules use, with
  a static context (namespaces, variables, user functions); unsupported
  constructs are static errors. `ELandrixXmlXPathError` carries the W3C
  error code; new error code `xecXPath`.
- `LandrixXmlXPathEval`: evaluates the compiled expressions on the tree as
  Saxon HE does without a schema (untypedAtomic rules, Saxon's decimal
  division, software doubles, code point strings, Java's case mapping in
  `fn:upper-case`), tolerant of errors where Saxon is (`and`, `or`, lazy
  variables), with global, frame and local variables and typed user
  functions. `tools/XPathOracle.java` and `tools/gen-xpath-testdata.py`
  check it against Saxon; `tools/gen-xpath-case-tables.py` generates the
  case mappings from Saxon.
- `LandrixXmlSchematron`: Schematron validation with rule files compiled
  from ISO Schematron (`tools/sch-compile.py`), run as the KoSIT validator's
  SchXslt XSLT does (first rule per pattern in document order, lets,
  global variables, XSLT functions), with results (id, flag, location,
  message, line, DOM node), dynamic errors as results and an option to
  stop like Saxon. `tools/sch-crosscheck.py` compares a rule file with the
  KoSIT XSLT; `tools/gen-schematron-rules.py` and
  `tools/gen-schematron-testdata.py` build the EN16931 1.3.16 and
  XRechnung 3.0.2 test rule sets and their expected results.
- `LandrixXmlSchematronCompiler`: compiles ISO Schematron files (the subset
  the EN16931, XRechnung and Peppol rules use) into the rule file format
  in Pascal, without Python; `TLandrixXmlSchematronRules.LoadFromSchematronFile`
  loads a `.sch` directly, `LoadFromDocument` a rule file already parsed.
  `AddOverride` replaces a test where a validator runs another one than
  the source has, checking the source's test. The output equals that of
  `tools/sch-compile.py` on the committed sources (`tests/data/schematron/sources`).
- `LandrixXmlSha256`: SHA-256 (`LandrixXmlSha256Hex`), the source fingerprint
  of compiled rules.
- `TLandrixXmlXPathEvaluator` keeps the value of subexpressions that depend
  neither on the focus nor on `current()` nor on non-global variables
  (absolute paths, `count(//x)`), and evaluates `//x` without building the
  sequence of all nodes when the predicates do not depend on the position.
  The EN16931 rules on an invoice with 1000 lines run in about 3 s instead
  of 16 s (UBL) and 76 s (CII). `ClearCache` drops the kept values;
  `TLandrixXmlXPathExpression.Serial` tells expressions apart.
  `tests/LandrixXmlSchematronPerf.dpr` measures and profiles a rule set.
- `TLandrixXmlXPathEvaluator.EvaluatePattern`: a path evaluated as an XSLT
  match pattern, where a dynamic error in a predicate of a step only means
  that the item does not match (XSLT 3.0, 5.5.4). Schematron rule contexts
  use it, so a node whose context predicate fails (e.g. `normalize-space()`
  on two elements) goes on to the next rule of the pattern instead of
  giving a dynamic error, as in the KoSIT validator. Found with the Peppol
  BIS 3.0.21 rules.
- The Schematron compiler (and `tools/sch-compile.py`) rejects every
  attribute of a Schematron or XSLT element it does not implement, such
  as `severity`, `visit-each` and `schematronEdition` of Schematron 2025,
  the Schematron 2025 elements `group`, `library` and `rules`, `sch:param`,
  and `xml:space="preserve"` and `xml:base` (which would change white
  space in XSLT functions or include paths), with file and line, instead
  of ignoring them. Documentation (other namespaces, `sch:p`,
  `sch:title`) is not checked.
- `document()` for Schematron rules that read code lists (Factur-X): the
  compiler embeds every file a `document('...')` names (a string literal,
  relative to the Schematron file) with its SHA-256 in the rule file
  (format 2); the rules load it once as a tree of its own, so validation
  reads no files. `TLandrixXmlXPathEvaluator.AddDocument` gives
  `document()` such a tree in general: the nodes of all trees are numbered
  in one space, and `/` and `root()` give the root of the node's own tree.
  The Factur-X 1.09.2 rules (all five profiles) give the same results as
  Saxon with the shipped XSLT on the test invoices.
- SVRL output: `TLandrixXmlSchematronValidator.SaveSvrlToStream` and
  `SaveSvrlToFile` write the last validation in the layout of SchXslt (as
  the KoSIT validator reports EN16931 and XRechnung): per pattern the
  active pattern, the fired rules with their failed asserts and successful
  reports, and the rules a preceding rule of the pattern suppressed;
  `DocumentUri` names the document (`ValidateFile` sets it). On the test
  invoices the SVRL equals SchXslt's apart from its metadata. Rule files now
  also list patterns without rules, which SVRL reports as active.
- `LandrixXmlRegex`: the mode `xrmXPath20`, the dialect of XPath 2.0: as
  `xrmXPath` (searching, anchors, `\$`), but with the character classes of
  XML Schema 1.0 (`[0-9-.]` is an error) and without `(?:...)` groups.
  The XPath evaluator uses it in the profile `xppXPath20`; `xrmXPath`
  stays the dialect of Saxon.
- XPath: `TLandrixXmlXPathItemKind` is the one type label of items and
  of the types of casts and parameters; it moved to `LandrixXmlXPath` and
  grows with the supported types (new labels are appended).
  `TLandrixXmlXPathAtomicType` is gone (`xatX` is now `xikX`).
- `LandrixXmlNormalize`: Unicode normalization NFC, NFD, NFKC and NFKD
  (`LandrixXmlNormalizeUtf8`, `LandrixXmlNormalizeCodePoints`) with the
  data of Unicode 15.0.0, the version of JDK 21 that Saxon uses; text
  that is already normalized is detected by the Unicode quick check and
  returned unchanged. `tools/gen-normalize-tables.py` generates the
  tables, `tools/fetch-unicode-tests.py` downloads the Unicode
  conformance file NormalizationTest.txt, which the test runner then
  checks completely.
- Regular expressions: block escapes (`\p{IsBasicLatin}`, `\P{IsGreek}`
  and so on). The XPath dialects know the blocks as Saxon does (up to
  Unicode 6.0, old names kept, spaces, underscores, tabs and line ends
  after `Is` ignored), the XML Schema dialect those of the Java runtime's
  Xerces (Unicode 3.1; also the plain name such as `Basic Latin`). An unknown
  block name makes the pattern invalid. `source/LandrixXmlBlockData.inc`
  is generated by `tools/gen-regex-blocks.py` from the behaviour of both
  engines (oracle `tools/XercesRegexOracle.java`). Nothing in the regular
  expressions is unsupported any more. QT3: 2 more cases pass.
- `tools/run-qt3.py`: `assert-xml` is checked. The helper writes the
  subtrees of the result nodes, the driver parses the expected XML with
  expat and compares both exactly as the XML serialization of the result
  (names with prefixes, attributes as a set, text, comments and processing
  instructions; namespace declarations are not compared). QT3: the 120
  cases with `assert-xml` are now judged and all pass (15,063 in the XPath
  2.0 profile, 15,040 in the Saxon profile).
- XPath: `nilled` and `static-base-uri`. The tree has no type
  annotations, so an element is never nilled (also with `xsi:nil="true"`,
  as for untyped elements in Saxon); other nodes give the empty sequence.
  The static context has no base URI, so `static-base-uri()` is empty.
  QT3: 6 more cases pass in both profiles.
- XPath: `base-uri` and `TLandrixXmlXPathTree.BaseUri`, the base URI of
  the document node. `LoadFromFile` sets it to the file URI as Saxon
  gives it (`file:/D:/x/y.xml`), the other loads leave it empty, and a
  caller may set it after loading. An element's `xml:base` is resolved
  against the base URI of its parent (RFC 3986, as `resolve-uri`); as in
  Saxon, a value that is no valid URI reference is taken with its white
  space collapsed (and resolves nothing below it), and an absolute one
  and a relative one under an invalid or opaque base are taken as they
  are. The Schematron validator's SVRL `documents` attribute
  now comes from the tree's `BaseUri` (same value). QT3: 3 more cases
  pass in both profiles.
- XPath: kind tests with a name or type in path steps
  (`//element(a)`, `attribute(x, xs:untypedAtomic)`,
  `document-node(element(r))`), checked as in sequence types; an
  abbreviated step with `attribute()` uses the attribute axis, as the
  specification says (before, it was the child axis and selected
  nothing). `schema-element()` and `schema-attribute()` raise XPST0008
  (no schema) after their name is checked, an unbound prefix XPST0081.
  QT3: 11 more cases pass in both profiles.
- XPath: `collection`. No collections are available, so it raises
  FODC0002 (also without an argument, as there is no default collection)
  and FODC0004 for an invalid URI, the codes Saxon gives for a
  collection that does not exist. QT3: 9 more cases pass in both profiles.
- XPath: `id` and `idref`. The tree has no DTD or schema types, so the
  IDs are the `xml:id` attributes (white space collapsed; the first
  element per ID in document order) and there are no IDREF attributes:
  `idref` is always empty, but checks its arguments as `id` does. QT3: 25
  more cases pass in both profiles.
- XPath: the evaluator's own document has a document URI, the tree's
  `BaseUri` (`LoadFromFile`: the file URI); `doc`, `doc-available` and
  `document` find the document by it, as Saxon finds a loaded document.
  `xs:NOTATION` is accepted in sequence types (`instance of`, `treat as`);
  no value has this abstract type. The QT3 driver checks an `assert-type`
  it cannot read itself with `instance of` in the helper. QT3: 8 more
  cases pass in both profiles.
- `tools/run-xsts.py` and `tests/LandrixXmlXsts.dpr`: the W3C XML Schema
  Test Suite (pinned revision, downloaded on first use) against the XML
  Schema loader and validator, with a baseline of the passing tests that
  the CI checks: 39,225 of 39,336 applicable XSD 1.0 tests pass, none
  uses constructs that are not supported.
- The places where the XML Schema validator follows Xerces instead of the
  specification on purpose are tagged `Xerces deviation:` with the test
  names of the README list; `tools/check-forbidden.py` checks that tags
  and list match.
- Regular expressions: back-references (`\1` and so on) in the XPath
  dialects. A pattern with a back-reference runs on a backtracking
  matcher limited to 10,000,000 steps per call (`xecLimit` beyond, never
  a silent mismatch); every other pattern keeps the linear-time matcher.
  Invalid references (a group that does not exist or is not closed yet,
  a reference inside a character class) raise `xecRegex`, FORX0002 in
  XPath. QT3: 29 more cases pass in both profiles.
- Regular expressions: the flag `i` with Saxon's case variants
  (`source/LandrixXmlCaseVariantsData.inc`, generated by
  `tools/gen-regex-case-variants.py` from Saxon's behaviour); a character
  or range gets its variants before negation and subtraction, categories
  and multi-character escapes are unchanged; in the Saxon dialect, as
  Saxon, a character directly before `-]`, `-[` or `--[` gets none. Saxon's
  variants differ from a literal reading of F&O 2.0 for six pairs
  (U+0049/U+0130 and U+0069/U+0130 are variants, U+00DF/U+1E9E,
  U+0390/U+1FD3, U+03B0/U+1FE3 and U+FB05/U+FB06 are not); both profiles
  use Saxon's. QT3: 16 more cases pass in both profiles.
- Regular expressions: the flags `s`, `m`, `x` and (Saxon dialect only)
  `q`, and reluctant quantifiers (`*?`, `+?`, `??`, counted ones), all
  in the linear-time matcher; `m` follows Saxon (no line start after a
  final line feed). `LandrixXmlRegexFlagsValid` checks flags per dialect;
  invalid flags raise `xecRegex`. A single character counted 2147483647
  or more times never matches (as Saxon finds); quantifier bounds are
  compared exactly, also with leading zeros. XPath: invalid flags raise FORX0001,
  limits of the implementation FOER0000 instead of FORX0002. QT3: 42
  more cases pass in both profiles.
- XPath: `normalize-unicode` with the four forms (FULLY-NORMALIZED and
  other names raise FOCH0003; the form name is trimmed and compared
  ignoring ASCII case, so unlike Saxon the Kelvin sign U+212A does not
  stand for K). QT3: 45 more cases pass in both profiles.
- XPath: `lang` (case ignored as Unicode's caseless match in XPath 2.0,
  character by character as Java's `equalsIgnoreCase` in the Saxon profile),
  `trace` (returns its value; nothing is written), `doc`,
  `doc-available` and `document-uri` for the documents added with
  `TLandrixXmlXPathEvaluator.AddDocument` (the evaluator's own document
  has no URI); `AddDocument` now forgets kept values and evaluated lazy
  variables. QT3: 90 more cases pass (89 in the Saxon profile).
- XPath: `encode-for-uri`, `iri-to-uri`, `escape-html-uri` and
  `resolve-uri` (RFC 3986; a base must be an absolute hierarchical URI
  without a fragment, FORG0002 otherwise; there is no static base URI, so
  the one-argument form resolves only absolute references). QT3: 146
  more cases pass in both profiles.
- XPath: `remove`, `insert-before`, `unordered` (keeps the order) and
  `error` (the local name of the QName as the error code, FOER0000
  without one; in a Schematron rule context an error means no match).
  QT3: 326 more cases pass (325 in the Saxon profile).
- XPath: `deep-equal` (comments and processing instructions skipped,
  attributes in any order, NaN equal to NaN), `compare`,
  `codepoint-equal`, `default-collation`, and the collation argument of
  `contains`, `starts-with`, `ends-with`, `substring-before`,
  `substring-after`, `distinct-values`, `index-of`, `min` and `max`: the
  code point collation is the only one, another gives FOCH0002. QT3: 355
  more cases pass in both profiles.
- XPath: `resolve-QName`, `namespace-uri-for-prefix` and
  `in-scope-prefixes` (sorted, `xml` last, as Saxon; the prefixes are
  `xs:NCName` in XPath 2.0, `xs:string` in the Saxon profile). The XPath
  tree keeps the namespace declarations of elements:
  `TLandrixXmlXPathTree.LookupNamespace` and `InScopePrefixesUtf8` give
  the namespaces in scope of an element (`xml` always bound, `xmlns`
  never; a prefix of an element or attribute name whose declaration a DOM
  has lost still counts).
- XPath: `xs:QName`: the constructor function and casts (prefixes
  resolved with the static namespaces, FONS0004 if unbound), `QName`,
  `prefix-from-QName`, `local-name-from-QName`,
  `namespace-uri-from-QName`, `node-name`, `eq` and `ne` on the namespace
  URI and local name, `distinct-values` and `index-of`. XPath 2.0 casts
  only a string literal to `xs:QName` (XPTY0004, `castable as` gives
  false); the Saxon profile casts any string or `xs:untypedAtomic`, as
  Saxon (XPath 3.1) does, and allows `node-name()` without an argument.
  `TLandrixXmlXPathExpression.LookupNamespace` gives the namespaces the
  expression was compiled with. QT3: 238 more cases pass (13,882 in the
  XPath 2.0 profile, 13,861 in the Saxon profile).
- XPath: `xs:hexBinary` and `xs:base64Binary`: constructor functions,
  casts from strings, between the two types and to strings, the
  canonical lexical form (hex digits in upper case, base64 without
  spaces), `eq` and `ne` on the octets, `distinct-values` and `index-of`.
  XPath 2.0 has no order on them (XPTY0004, FORG0006 in `min` and `max`);
  the Saxon profile orders them octet by octet as Saxon (XPath 3.1) does.
  QT3: 521 more cases pass (13,644 in the XPath 2.0 profile, 13,629 in
  the Saxon profile).
- XPath: the Gregorian types `xs:gYearMonth`, `xs:gYear`,
  `xs:gMonthDay`, `xs:gDay` and `xs:gMonth`: constructor functions, casts
  from strings, `xs:date` and `xs:dateTime` (the time zone is kept) and to
  strings, the canonical lexical form, `eq` and `ne` on the starting
  instants (F&O 2.0 10.4.13 to 10.4.17, with the implicit time zone),
  `distinct-values` and `index-of`. They have no order (XPTY0004, FORG0006
  in `min` and `max`). As for dates, the lexical forms are those of XML
  Schema 1.0 (no year 0000) and `--MM--` is no `xs:gMonth`. QT3: 1,111 more
  cases pass (13,123 in the XPath 2.0 profile, 13,108 in the Saxon
  profile).
- XPath: `xs:float` values: the constructor function, casts from and to
  the other types, the promotions (integers and decimals to `xs:float`
  next to a float, `xs:float` to `xs:double`), arithmetic in single
  precision, comparisons, `abs`, `round`, `round-half-to-even`, `floor`,
  `ceiling`, `sum`, `avg`, `min`, `max` and the string value as Saxon
  writes floats. XPath 2.0 rounds a string or a decimal to the nearest
  float once; the Saxon profile goes through a double first and accepts
  `+INF`, as Saxon does. QT3: 857 more cases pass (12,012 in the XPath
  2.0 profile, 11,997 in the Saxon profile).
- `LandrixXmlDouble`: `xs:float` (IEEE 754 binary32) as a
  `TLandrixXmlDouble` restricted to binary32 values:
  `LandrixXmlDoubleRoundToFloat`, `LandrixXmlDoubleIsFloat`,
  `LandrixXmlDoubleTryParseFloat` / `LandrixXmlDoubleParseFloat` and
  `LandrixXmlDoubleFloatFromDecimal` (rounded once to the nearest float,
  never through a double) and `LandrixXmlDoubleFormatFloat` (the XPath
  string value with the digits Saxon writes for floats). The XML Schema
  validator uses them for `xs:float`. `tools/gen-float-testdata.py`
  generates 5,811 cases with an independent oracle (exact fractions); the
  string values and Saxon's own reading of `xs:float` literals (through a
  double) match Saxon on every compared case.
- XPath: date and time arithmetic (F&O 2.0 10.4 to 10.8): `xs:date`,
  `xs:dateTime` and `xs:time` minus each other, plus and minus durations,
  comparisons of values with and without time zone, casts between the
  three types, the 15 component functions (`year-from-dateTime` ...,
  `timezone-from-time`), `adjust-dateTime-to-timezone`,
  `adjust-date-to-timezone`, `adjust-time-to-timezone`, `fn:dateTime`,
  `current-dateTime`, `current-date`, `current-time` and
  `implicit-timezone`. Years beyond 2^31 - 1 give FODT0001. Years are
  counted as the date parser (and Xerces) reads XML Schema 1.0: no year
  0, the leap year rule on the signed year (-0004 is a leap year, -0001
  is not), the years before 1 backwards from 0001-01-01.
- `TLandrixXmlXPathEvaluator.ImplicitTimeZone` and
  `TLandrixXmlSchematronValidator.ImplicitTimeZone` (minutes east of UTC,
  default 0 = UTC) and `CurrentDateTime` / `ClearCurrentDateTime` on both:
  the dynamic context of the date functions. Without a set value the
  clock (`Now`) is read at the first use and kept for the evaluator's
  lifetime (one Schematron validation).
- `tools/gen-date-testdata.py`: 760 generated date and time cases with an
  independent oracle (Python's calendar and `decimal`) for both
  profiles; its Saxon variant matches Saxon on every case. The Saxon
  profile rounds `seconds-from-dateTime`/`-time` to microseconds and
  reports FODT0001 for a too large year before checking the rest, as
  Saxon does. QT3: 1,234 more cases pass (11,155 in the XPath 2.0 profile,
  11,142 in the Saxon profile); no QT3 case of the date, time and
  duration test sets fails.
- XPath: `xs:duration`, `xs:yearMonthDuration` and `xs:dayTimeDuration`
  with constructor functions, casts, the canonical lexical form,
  comparisons (`eq` and `ne` on any durations, the order on the two
  subtypes), addition, subtraction, multiplication and division by
  numbers, the quotient of two durations (`xs:decimal`), `sum`, `avg`,
  `min`, `max` and the six component functions (`years-from-duration`
  ...). The limits are Saxon's: every number of the lexical form below
  2^31, the months below 2^31, the whole seconds below 2^63, nine fraction
  digits (a tenth is dropped, more give FODT0002). XPath 2.0 computes
  exactly (an `xs:double` operand as its shortest digits); the Saxon
  profile divides durations and multiplies months by an `xs:double`
  through `xs:double` as Saxon does, reports FORG0001 for too many months
  and XPTY0004 for a sum of different duration types.
  `tools/gen-duration-testdata.py` generates 840 cases with an
  independent oracle (Python's `decimal`) for both profiles; its Saxon
  variant matches Saxon on every case. QT3: 1,245 more cases pass (9,921
  in the XPath 2.0 profile, 9,908 in the Saxon profile).
- XPath: the types derived from `xs:string` (`xs:normalizedString`,
  `xs:token`, `xs:language`, `xs:NMTOKEN`, `xs:Name`, `xs:NCName`, `xs:ID`,
  `xs:IDREF`, `xs:ENTITY`) with constructor functions and casts (white
  space of the type, then the lexical check with the name characters of
  XML 1.0 fifth edition, FORG0001); they behave as strings and take part
  in derivation. QT3: 132 more cases pass (8,676 in the XPath 2.0 profile,
  8,663 in the Saxon profile).
- XPath: the types derived from `xs:integer` (`xs:long`, `xs:int`,
  `xs:short`, `xs:byte`, the unsigned and the signed-range types) with
  their constructor functions, casts with range checks (FORG0001),
  derivation in `instance of` and in the function conversion rules;
  arithmetic gives `xs:integer`. In the Saxon profile `floor`, `ceiling`,
  `round`, `round-half-to-even` and `abs` return such an argument as it is
  in the cases where Saxon does (listed in the evaluator), XPath 2.0 gives
  an `xs:integer`. QT3: 2,031 more
  cases pass (8,544 in the XPath 2.0 profile, 8,531 in the Saxon
  profile); the test driver knows the derived types.
- XPath: `instance of` and `treat as` (XPDY0050) with all XPath 2.0
  sequence types; `xs:integer` is an instance of `xs:decimal`, without the
  promotions of the function conversion rules. QT3: 326 more cases pass
  (6,513 in the XPath 2.0 profile, 6,500 in the Saxon profile).
- `LandrixXmlXPathParseSequenceType` and `LandrixXmlXPathSequenceTypeName`:
  XPath 2.0 sequence types (`xs:decimal?`, `element(a)*`,
  `document-node(element(*, xs:untyped))`, `empty-sequence()`, ...) with
  prefixes from a static context. `TLandrixXmlXPathSequenceType` moved to
  `LandrixXmlXPath` and describes kind tests with names and type names
  (`KindTest`, `NamespaceUri`, `LocalName`, `ContentType`, `Nilled`,
  `ElementTest`; `xtkEmpty`). Schematron reads `as` with it: prefixes are
  resolved through the rule file's namespaces, `element(a)` and the other
  kind tests are checked (they were all taken as `node()`), and type
  errors are XPath errors (`xecXPath`). A type with `Declared = False` is
  not checked at all (function definitions built in code without types
  had their results checked as exactly one item).
- XPath: a compact item record (`TLandrixXmlXPathItem`: kind, node, an
  Int64 for doubles, booleans and integers, text, and a shared immutable
  `ILandrixXmlXPathValue` for decimals, large integers and dates) instead
  of one field per value type. Validation with the EN16931 rules is about
  a third faster; `EvaluateSequence` no longer copies digits.
- XPath: node comparisons (`is`, `<<`, `>>`), `intersect` and `except`, and
  the `following` axis. A path step without a context item raises
  XPDY0002 (was XPTY0020, which is for an atomic context item).
- `TLandrixXmlXPathStaticContext.Profile` (`TLandrixXmlXPathProfile`):
  `xppXPath20`, the default, follows XPath 2.0 and XML Schema 1.0;
  `xppSaxon` behaves as Saxon HE 12 in the KoSIT validator, as the
  evaluator did so far (XPath 3.1 rules: `round` and `string-join` with
  other arities, `string-join` on any atomic values, `+INF`, no check of
  `xs:anyURI`, Java's conversion of large doubles to integers). Every
  compiled expression keeps its profile (`Profile`); the Schematron units
  use `xppSaxon`. `tools/run-qt3.py --profile saxon` has its own baseline.
- `tools/run-kosit-suite.py` and `tests/LandrixXmlKosit.dpr`: the KoSIT
  XRechnung test suite (release 2026-08-31, downloaded with the matching
  validator configuration) through the XML schema validator and the
  EN16931/XRechnung rule files, compared with the KoSIT validator (schema
  verdict, error codes and positions) and with Saxon running the
  configuration's XSLT (fired rules, asserts, reports, messages,
  locations); reference in `tests/data/schematron/expected-kosit-suite.txt`,
  checked by the CI. All 86 invoices give the same results (all are
  schema-valid, so schema errors are not exercised).
- `tools/run-qt3.py` and `tests/LandrixXmlQt3.dpr`: the W3C XPath/XQuery
  test suite QT3 (XPath 2.0 cases, pinned revision) against the
  evaluator. Assertions are checked from the typed results outside the
  engine; the passing cases are a baseline (`tests/data/qt3-baseline.txt`)
  that the CI checks. First run: 6,004 of 15,144 applicable cases pass (6,016 in the XPath 2.0
  profile).
- README: Schematron validation with the four outcomes (valid, invalid,
  incomplete, not well-formed) and sharing rules between threads; the
  example is part of `examples/LandrixXmlExamples.dpr`.
- `tools/gen-schematron-testdata.py` collapses only XML white space in
  messages (a no-break space is text, as in the library).
- `TLandrixXmlXsdSimpleType.AnonymousName` and the public `DisplayName`;
  `LandrixXmlXsdValueText` and `LandrixXmlXsdValueKey`. Messages quote
  values whole, show values in Xerces' canonical form (decimals, float and
  double as `1.5E3`, dates and times moved to UTC, hexBinary in upper
  case) and normalize white space as Xerces does.
- `tools/XsdOracle.java` and `tools/gen-xsdtypes-testdata.py`: test oracle
  and test data generator for simple types; `tools/gen-xml10-name-tables.py`
  generates the XML 1.0 Fourth Edition name character classes Xerces uses
  for Name, NCName, ID and IDREF.
- New error code `xecArithmetic` (division by zero, exponent out of range).
- `tools/gen-decimal-testdata.py`: generates the decimal test cases and
  optionally checks them against Saxon.
- `TLandrixXmlXsdSimpleType.Validate` with `out HasValue`: whether Value
  holds a value after a failed check, as Xerces computes one before a
  facet fails (see the method's comment for lists and unions).

### Changed
- XPath evaluation needs less time per expression node: the evaluator
  dispatches each node kind to a method of its own, so a call no longer
  initialises and finalises the temporaries of all other kinds, and a
  general comparison of two string-like values skips the conversion
  step. The most frequent functions of the rule sets (not, true, false,
  boolean, count, exists, empty, string, string-length,
  normalize-space, upper-case, lower-case) no longer set up the frame
  of all other functions. The Factur-X 1.09.2 EXTENDED rules take about
  half the time on the 22 local EXTENDED documents, the EN16931 UBL
  rules on a public example 33 instead of 63 ms (Free Pascal, ARM64);
  results are unchanged.

### Fixed
- XML Schema: an import of a namespace that a document loaded or being
  loaded already has, or that the same document imported before (even
  without loading anything), is skipped, whatever its location, as in Xerces
  (without honour-all-schemaLocations, the setting of the KoSIT
  validator); before, every location was loaded, so a schema could load
  that Xerces rejects and the other way round (also src-import.1.2 for
  a document included chameleon-style and reached again through such an
  import).
- XML Schema: an attribute matched by an attribute wildcard whose type is
  a list of ID items or a union with an ID member type counts as a wild ID
  (cvc-complex-type.5.1, 5.2), as in Xerces.
- XML Schema: the errors of the schema for schemas carry the code Xerces
  reports for the schema element they occur in: s4s-elt-invalid-content.1
  (or .2 for missing content) in xs:schema and the parts of a complex
  type, s4s-elt-must-match.1 (or .2) elsewhere, src-annotation in
  xs:annotation; xs:list, xs:union and the xs:restriction of a simple type
  report src-simple-type.2.a, 2.b, 3.a, 3.b and
  src-union-memberTypes-or-simpleTypes before the rest of their content,
  as Xerces does. A duplicate attribute is ct-props-correct.4 in a complex
  type and ag-props-correct.2 in an attribute group (was without a code),
  also for a duplicate inside a referenced attribute group; a prohibited
  attribute use is never a duplicate, as in Xerces (a complex type with a
  prohibited and a normal use of the same attribute was rejected).
  Character data in a schema element is reported before any other error
  of the schema document, as Xerces reports it while reading it.
- XML Schema: fixed values of an attribute use and its declaration, and
  of a restriction and its base, compare as Xerces does, also date and
  time values of different types (a fixed 2026-11-04 of a union of
  xs:date and xs:dateTime may be restricted to 2026-11-04T00:00:00).
- XML Schema: two identity constraints of the same name (in one target
  namespace) are sch-props-correct.2, as in Xerces, instead of an error
  without a constraint code.
- XML Schema identity constraints use the value of a field whose value
  failed a facet other than pattern (also through a list item or a union
  member), as Xerces does, so two equal invalid values are also a
  duplicate.
- XML Schema (found with the W3C XML Schema Test Suite, checked against
  Xerces): `use="prohibited"` in an attribute group is ignored, as XML
  Schema 1.0 drops prohibited attribute uses from attribute groups (it
  removed an attribute of the base type); two attributes of an ID type
  matched by an attribute wildcard, or one besides an ID attribute use, are
  reported (`cvc-complex-type.5.1`, `5.2`); identity-constraint paths may
  have white space before `::` (`child ::x`); a group that refers to
  itself inside an element declaration of its own is no longer a circular
  reference; a complex-content extension without particles of a type with
  simple content keeps that simple content (it was rejected).
- XML Schema: a complex type derived from a type whose content contains
  the element that holds it (a local element whose anonymous type restricts
  or extends the enclosing type, or a referenced element whose type does)
  is no longer a circular derivation. As in Xerces, the types of the
  element declarations met while a complex type is built are built once
  it is complete. A circular derivation now reports Xerces' codes
  `ct-props-correct.3` (complex types) and `st-props-correct.2` (simple
  types).
- XML Schema: an include or a redefine of nothing but annotations whose
  document cannot be found (a missing file, an http location, a catalog
  entry naming a missing file) is skipped as XML Schema 1.0 allows and as
  Xerces does, instead of failing; a redefine that redefines components
  still has to resolve. Skipped documents are listed in the new
  `TLandrixXmlXsdSchemaSet.Warnings` and named when a reference into them
  fails. The same schema document under a differently cased file name is
  one document on Windows and macOS (it was loaded twice and gave
  duplicate declarations). `xs:include` and `xs:import` may contain one
  `xs:annotation` and nothing else.
- XML Schema: IDREFs without an ID are reported once each and in the
  order Xerces reports them (it collects them in a hash set), not once
  per reference.
- XML Schema: `minOccurs` and `maxOccurs` are read as
  `xs:nonNegativeInteger` of any size (sign, leading zeros); a bound
  beyond the Integer range is out of reach. Before, a value beyond the
  Integer range was rejected by Delphi and taken differently by Free
  Pascal, and hexadecimal values such as `$10` were accepted.
- XPath: a precision beyond the Integer range in `round` and
  `round-half-to-even` keeps every digit or none, as a large one in the
  range does; before, it raised FOAR0002. A decimal is rounded at a
  precision below -100,000 as at any other (0 if the value is below half
  the unit); before, such a precision was taken as
  -100,000, which kept the value of a decimal with more digits.
  `LandrixXmlDecimalRound` accepts any precision: below -1,000,000 it
  raised `xecArithmetic` even for a result of 0; now only a result other
  than 0 whose exponent is out of range does.
- XPath: `min` and `max` report a type error or a failed conversion of
  any value even if an earlier value is NaN; before, the first NaN was
  returned at once.
- XPath: names with characters from U+0080 on must consist of the name
  characters of XML 1.0 fifth edition, as in the reader (XPST0003); before,
  every such byte counted as a name character (U+00B7 at the start, U+00D7).
- `TLandrixXmlXPathTree.StringValueUtf8` no longer makes the tree's text
  strings unique (a write), so validators in several threads can share
  rules with embedded documents (`document()`).
- The CI installs the FCL units of Free Pascal (`Contnrs`).
- Delphi 13 macOS ARM64: no more W1072 warnings where `TStream.Read`
  returns a 64-bit `Longint`.
- Free Pascal on macOS AArch64: no more note about `Move` not being inlined
  in `ElementPath`, which appeared depending on the order units are
  compiled in.

## [0.2.0] - 2026-10-15

### Added
- `TLandrixXmlReader.ReadElementText` (`Utf8`, `W` and native variants):
  reads the text content of a simple element up to its end tag. Text and
  CDATA are joined, comments and processing instructions are ignored. A
  child element raises the new error code `xecUnexpectedElement`; the
  reader stays usable and stands on the child's start tag.
- `TLandrixXmlReader.ElementPath` (`Utf8`, `W` and native variants): the
  path of the current element with qualified names and without indices,
  e.g. `/Invoice/cac:InvoiceLine/cbc:ID`; also available after an error,
  for the element in which it occurred.
- `tools/fuzz.py`: differential fuzzing against expat.

### Changed
- DOM nodes are smaller: text, CDATA and comment nodes take 56 instead of
  112 bytes on Delphi 13 Win64 (48 instead of 104 on Free Pascal Win64),
  elements 88 instead of 112 (80 instead of 104). A loaded indented
  document needs about a third less memory. The public API is unchanged;
  internally, elements, the document, PIs and the DOCTYPE are instances of
  the new descendant `TLandrixXmlContainerNode`, which
  `TLandrixXmlDocument` now derives from, and `TLandrixXmlNode.CreateNode`
  raises `xecInvalidArgument` when class and node type do not fit.

## [0.1.0] - 2026-10-15

First release.

### Added
- `LandrixXml.inc`: central compiler switches for Delphi 6 to Delphi 13 and
  Free Pascal.
- `LandrixXmlBase`: string types `TLandrixXmlUtf8` and `TLandrixXmlWide`,
  strict UTF-8/UTF-16 coding including surrogate pairs, conversions between
  UTF-8, UTF-16 and the native `string`, `ELandrixXmlError` with error code
  and position, and the growable byte buffer `TLandrixXmlBuffer`.
- Dependency-free console test runner (`tests/LandrixXmlTests.dpr`).
- `tools/check-forbidden.py`: checks sources for language features and units
  that Delphi 6 does not support.
- `tools/build.ps1`: builds and runs the tests with all local toolchains.
- GitHub Actions CI with Free Pascal on Linux.
- `LandrixXmlEncoding`: `TLandrixXmlInput` detects the input encoding (byte
  order mark, XML declaration) and normalizes UTF-8, UTF-16 LE/BE,
  ISO-8859-1, Windows-1252, ISO-8859-15 and US-ASCII to UTF-8. Strict by
  default; opt-in repair via `FallbackEncoding` and `Latin1AsWindows1252`.
  Error positions refer to the original bytes. Shared XML declaration
  scanner `LandrixXmlScanDeclaration`.
- `TLandrixXmlBuffer.Extend`.
- Encoding test files generated with Python's codecs as an independent
  oracle (`tools/gen-encoding-testdata.py`).
- `LandrixXmlReader`: pull reader `TLandrixXmlReader` for well-formed XML 1.0
  with namespaces (zero-copy spans plus UTF-8, wide and native accessors,
  `Skip`, lazy line/column, `MaxDepth`), push adapter `TLandrixXmlHandler`.
  DOCTYPE is skipped and reported; DTD entities are not expanded.
- `LandrixXmlWriter`: streaming writer `TLandrixXmlWriter` (UTF-8 output to
  memory, a stream or a file). Automatic XML declaration, optional BOM,
  lexical namespaces with scope checks plus `...Ns` methods that declare
  prefixes automatically, escaping that survives a read-back unchanged,
  errors for characters and constructs that XML 1.0 cannot represent,
  atomic calls (a rejected call changes nothing), optional indentation that
  never touches mixed content, base64 output from buffers and streams.
- `LandrixXmlBase`: XML name checks, FNV-1a hash and base64 encoder shared
  by reader and writer; the namespace constants moved here from the reader.
- The W3C conformance run also copies every accepted document through the
  writer and checks that it reads back identically.
- `LandrixXmlConvert`: locale-independent conversion of xs:decimal
  (Currency exact via its scaled integer, Double correctly rounded up to 15
  significant digits), xs:long/xs:int, xs:boolean, xs:date, xs:dateTime,
  xs:time (parts record with time zone, or TDateTime as written) and the
  CII date formats 102 and 610. Rounding is half away from zero.
- `LandrixXmlBase`: strict base64 decoder into a buffer or a stream, and
  the error code `xecConversion`.
- Conversion test data generated with Python's decimal and struct modules
  as an independent oracle (`tools/gen-convert-testdata.py`).
- `LandrixXmlDom`: document object model `TLandrixXmlDocument` /
  `TLandrixXmlNode` built from the pull reader and saved through the
  streaming writer. Interned names, search by namespace and local name
  (or local name only), mixed content, line and column per node, optional
  dropping of white space between elements, comments and PIs, building
  and moving nodes with namespace handling, subtrees taken over from a
  reader, freeing and saving without recursion.
- The W3C conformance run also loads, saves and reloads every accepted
  document through the DOM.
- README with examples, string strategy, limitations and measurements;
  the examples are compiled and run as `examples/LandrixXmlExamples.dpr`
  (also in CI).
- Performance measurement `tests/LandrixXmlPerf.dpr` with
  `tools/perf.ps1` (times and peak memory for reader and DOM).
- The DOM shares identical white-space text values while loading, which
  lowers the memory of indented documents.
- Real-world test: files placed in the git-ignored `tests/data/local`
  (XRechnung, ZUGFeRD, GAEB) are round-tripped through the DOM, damaged
  copies must be rejected cleanly, and `tools/check-local.py` cross-checks
  the classification with expat.

[Unreleased]: https://github.com/landrix/LandrixXML-for-Pascal/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/landrix/LandrixXML-for-Pascal/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/landrix/LandrixXML-for-Pascal/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/landrix/LandrixXML-for-Pascal/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/landrix/LandrixXML-for-Pascal/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/landrix/LandrixXML-for-Pascal/releases/tag/v0.1.0
