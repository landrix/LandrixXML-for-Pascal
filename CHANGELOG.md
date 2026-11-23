# Changelog

All notable changes to this project are documented here: the changes
since the last release in this file, each release in a file of its own
under [docs/changelog](docs/changelog) (moved there when it is released).
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Changed

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

## Releases

- [0.5.1](docs/changelog/0.5.1.md) - 2026-11-23
- [0.5.0](docs/changelog/0.5.0.md) - 2026-11-17
- [0.4.0](docs/changelog/0.4.0.md) - 2026-11-12
- [0.3.0](docs/changelog/0.3.0.md) - 2026-11-10
- [0.2.0](docs/changelog/0.2.0.md) - 2026-10-15
- [0.1.0](docs/changelog/0.1.0.md) - 2026-10-15

[Unreleased]: https://github.com/landrix/LandrixXML-for-Pascal/compare/v0.5.1...HEAD
