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
- `LandrixXmlRegex`: the mode `xrmXPath20`, the dialect of XPath 2.0: as
  `xrmXPath` (searching, anchors, `\$`), but with the character classes of
  XML Schema 1.0 (`[0-9-.]` is an error) and without `(?:...)` groups.
  The XPath evaluator uses it in the profile `xppXPath20`; `xrmXPath`
  stays the dialect of Saxon.
- XPath: `TLandrixXmlXPathItemKind` is the one type label of items and
  of the types of casts and parameters; it moved to `LandrixXmlXPath` and
  grows with the supported types (new labels are appended).
  `TLandrixXmlXPathAtomicType` is gone (`xatX` is now `xikX`).
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

### Fixed
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

[Unreleased]: https://github.com/landrix/LandrixXML-for-Pascal/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/landrix/LandrixXML-for-Pascal/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/landrix/LandrixXML-for-Pascal/releases/tag/v0.1.0
