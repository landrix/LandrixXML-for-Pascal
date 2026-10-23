# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
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
  (`xecUnsupported`), invalid schemas raise the new code `xecSchema`;
  `xsi:type` and `xsi:nil` in documents are reported as unsupported.
  Elements without a declaration are assessed laxly with `anyType`;
  identity constraints follow Xerces' value tables and XPath matching,
  a keyref outside the scope of its key is reported as
  `KeyRefOutOfScope`. `tools/gen-xsdvalidator-testdata.py` generates the
  test cases, `tests/data/xsdvalidator/edge` holds one small case per rule.
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

### Fixed
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

[Unreleased]: https://github.com/landrix/LandrixXML-for-Pascal/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/landrix/LandrixXML-for-Pascal/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/landrix/LandrixXML-for-Pascal/releases/tag/v0.1.0
