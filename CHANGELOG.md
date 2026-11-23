# Changelog

All notable changes to this project are documented here: the changes
since the last release in this file, each release in a file of its own
under [docs/changelog](docs/changelog) (moved there when it is released).
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Changed

- `tools/x86-suites.ps1` runs the test suites (QT3 in both profiles, the
  W3C XSLT suite, XSTS, KoSIT, the W3C XML conformance suite) on the x86
  machine, all at once, and brings their per-case results (per set too
  for QT3 and XSLT; the console output of each suite) and, with
  `-UpdateBaseline`, the baselines of the suites that passed back; the
  helpers are built here. There only the downloaded suites last between
  calls, everything else is sent anew. All six suites take about 2
  minutes instead of more than 15 one after the other on the development
  machine.
- `tools/build.ps1` runs the toolchains in parallel, each in a child
  process (`-Jobs`, default processor count minus 2; output in
  `build/<toolchain>/worker.log`), and runs the test runners of the Windows
  toolchains on the x86 machine (SSH alias `ai-rtx5090`) all at once as soon
  as they are built, natively instead of in the x86 emulator of the ARM
  development machine (not `fpc331-winarm`, which runs natively here);
  `-Here` runs them locally, and they run locally with a warning when the
  machine does not answer. With the toolchain `x86` in the list (the x87
  check of `all`) the machine stays required. The development set takes
  about 2.5 instead of 14 minutes.
- `tools/run-qt3.py` and `tools/run-xslt-tests.py` report each test set:
  pass / applicable, rate and the change to the baseline go into
  `build/qt3/sets-PROFILE.txt` and `build/xslt-tests/sets.txt`; a set in
  which a passing case of the baseline no longer passes is printed as
  `SET DOWN` even when the set or the run as a whole has more passing
  cases, and `--sets [N]` lists the sets with the most cases that do not
  pass (shared module `tools/suitesets.py`).
- `tools/check-suite-updates.py` also reports newer versions of the
  oracles the reference data comes from: Saxon HE (Maven Central) and the
  KoSIT validator (GitHub releases) of `tests/data/saxon-oracle.txt`, the
  Java runtime of `tests/data/xerces-oracle.txt` (updates of its feature
  release and a newer LTS release, Adoptium API) and Free Pascal (the
  newest release `tools/build.ps1` builds with, release tags on GitLab).
  As for the suites, a newer version is only reported; a newer Java LTS
  release is a note that does not change the exit code. A release check
  whose reply does not list the pinned release now fails instead of
  reporting "current".

### Fixed

- XSLT static errors the compiler did not report, now as Saxon does: a
  `select` attribute together with content on `xsl:variable`,
  `xsl:param`, `xsl:with-param` (XTSE0620), `xsl:value-of` (XTSE0870),
  `xsl:attribute` (XTSE0840), `xsl:comment` (XTSE0940),
  `xsl:processing-instruction` (XTSE0880), `xsl:sequence` (XTSE3185;
  `xsl:fallback` stays allowed) and `xsl:copy-of` (XTSE0260), whose
  content was silently dropped; `xsl:output` declarations of one import
  precedence with different values for a property (XTSE1560, the last
  one won); a top-level element in no namespace (XTSE0130, skipped);
  content in `xsl:include`, `xsl:import`, `xsl:strip-space`,
  `xsl:preserve-space`, `xsl:output` and `xsl:decimal-format` (XTSE0260); a named template, variable, parameter,
  key, attribute set, character map, output definition or `xsl:with-param`
  in a reserved namespace (XTSE0080; `xsl:initial-template` stays
  allowed); `priority` without `match` (XTSE0500).
- XSLT error codes as Saxon gives them: a module that imports itself
  XTSE0210 (was XTSE0180); a variable whose value does not match its
  `as` type XTTE0570, also a global one and when the conversion fails
  (was XPTY0004 or FORG0001), also the content default of a parameter;
  the `select` default of a parameter XTTE0600 (also of an `xsl:iterate`
  parameter, whose content gives XTTE0570); `xsl:with-param` with its own
  `as` XTTE0590 for `select`, XTTE0570 for content; a global variable with
  `as` and no value XTTE0570; a
  parameter without a default whose type needs a value XTDE0700 (both
  XPTY0004 before); the result of a template with `as` XTTE0505;
  `current()` without a current item inside an expression in a
  stylesheet function XTDE1360 (XPDY0002 stays for a global without a
  source); `xsl:apply-templates`
  without `select` on an atomic context item XTTE0510 (was XPTY0020); a
  global parameter whose default does not match its type XTTE0590, one
  without a default whose type needs a value XTDE0700.
  XTSE3520 of an `xsl:iterate` parameter now points at the parameter.
- The default priority of the XSLT 3.0 pattern `.` is -1 and of `.[...]`
  +1 (both were 0.5, so `match="."` won over `match="/"` and element
  names).
- A match pattern evaluated while another one is (a stylesheet function in
  a predicate that applies templates) reset the other's record of the
  nodes its union branches failed on, so its result depended on whether
  the function matched templates.
- An error stored for a variable kept its library error code only on the
  first read: later reads raised `xecXPath` (an unsupported construct
  became an ordinary XPath error).

## Releases

- [0.5.1](docs/changelog/0.5.1.md) - 2026-11-23
- [0.5.0](docs/changelog/0.5.0.md) - 2026-11-17
- [0.4.0](docs/changelog/0.4.0.md) - 2026-11-12
- [0.3.0](docs/changelog/0.3.0.md) - 2026-11-10
- [0.2.0](docs/changelog/0.2.0.md) - 2026-10-15
- [0.1.0](docs/changelog/0.1.0.md) - 2026-10-15

[Unreleased]: https://github.com/landrix/LandrixXML-for-Pascal/compare/v0.5.1...HEAD
