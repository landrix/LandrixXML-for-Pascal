#!/usr/bin/env python3
"""Report whether the pinned test suites, reference packages and
oracles have newer versions upstream. Nothing is downloaded or changed; moving a pin
is a decision (new pin and SHA-256 in the script, rerun of the suite,
new baseline).

  python tools/check-suite-updates.py [--verbose]

The pins are read from the scripts that use them:
  commits   run-qt3.py (w3c/qt3tests), run-xslt-tests.py (w3c/xslt30-test),
            run-xsts.py (w3c/xsdtests), xslt-crosscheck.py (Peppol examples)
  releases  GitHub release downloads in run-kosit-suite.py,
            xslt-crosscheck.py and gen-schematron-rules.py
  other     the W3C XML conformance archive (run-xmlconf.py), the
            XRechnung Schematron package (gen-schematron-rules.py) and
            the SHA-256 of xml.xsd and xlink.xsd (run-xsts.py)
  oracles   Saxon HE and the KoSIT validator (tests/data/saxon-oracle.txt,
            Maven Central and GitHub releases), the Java runtime of the
            Xerces reference data (tests/data/xerces-oracle.txt, newer
            updates of its feature release and a newer LTS release from
            the Adoptium API) and Free Pascal (the newest release
            tools/build.ps1 builds with, release tags on GitLab)
For a commit pin it prints how many commits the default branch is ahead
and the changed files; for a release, the newer releases with the same
tag prefix (v2026-08-31 is compared with v2027-..., validation-1.3.16
with validation-1.3.16.1; tags with letters after the prefix, such as
rc1, do not count). The Unicode data versions are fixed by the
specifications and are not checked. A newer oracle is reported only:
moving to it regenerates the reference data (tools/saxonjar.py with
LANDRIX_OTHER_SAXON=1, tools/check-xerces-drift.py for a JDK).
GitHub allows 60 requests an hour without a token; GITHUB_TOKEN or
GH_TOKEN in the environment raises that.
Exit code 0 if everything is current, 1 if something is newer, 2 if a
check failed.
"""
import argparse
import hashlib
import json
import os
import re
import sys
import urllib.error
import urllib.request
from xml.etree import ElementTree

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOLS = os.path.join(ROOT, "tools")
AGENT = "landrixxml-suite-check"

COMMIT_PINS = [
    # (script, regular expression with the commit as group 1, repository)
    ("run-qt3.py", r'^COMMIT = "([0-9a-f]{40})"', "w3c/qt3tests"),
    ("run-xslt-tests.py", r'^COMMIT = "([0-9a-f]{40})"', "w3c/xslt30-test"),
    ("run-xsts.py", r'^COMMIT = "([0-9a-f]{40})"', "w3c/xsdtests"),
    ("xslt-crosscheck.py", r'OpenPEPPOL/peppol-bis-invoice-3/"\s*"([0-9a-f]{40})/', "OpenPEPPOL/peppol-bis-invoice-3"),
]
RELEASE_SCRIPTS = ["run-kosit-suite.py", "xslt-crosscheck.py", "gen-schematron-rules.py"]
RELEASE_URL = re.compile(r'https://github\.com/([\w.-]+/[\w.-]+)/releases/download/(?:"\s*")?([^/"]+)/')
XMLCONF_PAGE = "https://www.w3.org/XML/Test/"
KOSIT_MAVEN = "https://projekte.kosit.org/api/v4/projects/356/packages/maven/de/xeinkauf/%s/maven-metadata.xml"
SAXON_ORACLE = os.path.join(ROOT, "tests", "data", "saxon-oracle.txt")
XERCES_ORACLE = os.path.join(ROOT, "tests", "data", "xerces-oracle.txt")
SAXON_MAVEN = "https://repo1.maven.org/maven2/net/sf/saxon/Saxon-HE/maven-metadata.xml"
ADOPTIUM = "https://api.adoptium.net/v3/"
FPC_TAGS = "https://gitlab.com/api/v4/projects/freepascal.org%2Ffpc%2Fsource/repository/tags?search=release_&per_page=100"


def source(script):
    with open(os.path.join(TOOLS, script), encoding="utf-8") as f:
        return f.read()


def fetch(url, accept="application/vnd.github+json"):
    request = urllib.request.Request(url, headers={"User-Agent": AGENT, "Accept": accept})
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if token and url.startswith("https://api.github.com/"):
        request.add_header("Authorization", "Bearer " + token)
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()


def github(path):
    return json.loads(fetch("https://api.github.com/" + path).decode("utf-8"))


def check_commit(script, pattern, repo, verbose):
    m = re.search(pattern, source(script), re.M)
    if not m:
        return "error", "%s: no pinned commit found in tools/%s" % (repo, script)
    pin = m.group(1)
    branch = github("repos/%s" % repo)["default_branch"]
    compare = github("repos/%s/compare/%s...%s" % (repo, pin, branch))
    ahead = compare.get("ahead_by", 0)
    if ahead == 0 and compare.get("behind_by", 0) == 0:
        return "current", "%s %s (%s): current" % (repo, pin[:7], script)
    if compare.get("behind_by", 0) > 0:
        # the history was rewritten: the pin is no longer on the branch
        return "newer", "%s %s (%s): %s has diverged (%d ahead, %d behind)" % (
            repo, pin[:7], script, branch, ahead, compare["behind_by"])
    head = github("repos/%s/commits/%s" % (repo, branch))["sha"]
    # GitHub lists at most 300 files of a comparison
    files = compare.get("files", [])
    lines = ["%s %s (%s): %s is %d commit(s) ahead (%s), %s file(s) changed"
             % (repo, pin[:7], script, branch, ahead, head[:7],
                len(files) if len(files) < 300 else "300 or more")]
    for f in files if verbose else files[:10]:
        lines.append("    %s %s" % (f.get("status", "?"), f["filename"]))
    if not verbose and len(files) > 10:
        lines.append("    ... (--verbose lists them, up to 300)")
    return "newer", "\n".join(lines)


def prefix_of(tag):
    """The tag without its version: "validation-" of "validation-1.3.16"."""
    return re.match(r"^(.*?)\d", tag).group(1)


def is_release_tag(tag, prefix):
    return tag.startswith(prefix) and re.match(r"^[\d.-]+$", tag[len(prefix):]) is not None


def version_key(tag):
    return [int(n) for n in re.findall(r"\d+", tag)]


def check_release(repo, tag, scripts):
    releases = []
    for page in range(1, 11):
        part = github("repos/%s/releases?per_page=100&page=%d" % (repo, page))
        releases.extend(part)
        if len(part) < 100:
            break
    prefix = prefix_of(tag)
    same = [r["tag_name"] for r in releases
            if not r.get("draft") and not r.get("prerelease") and is_release_tag(r["tag_name"], prefix)]
    if tag not in same:
        # an incomplete reply must not look current
        return "error", "%s: the pinned release %s is not listed" % (repo, tag)
    newer = sorted((t for t in same if version_key(t) > version_key(tag)), key=version_key)
    where = ", ".join(scripts)
    if not newer:
        return "current", "%s %s (%s): current" % (repo, tag, where)
    return "newer", "%s %s (%s): newer release(s) %s" % (repo, tag, where, ", ".join(reversed(newer)))


def check_xmlconf():
    m = re.search(r'^URL = "[^"]*xmlts(\d{8})\.tar\.gz"', source("run-xmlconf.py"), re.M)
    if not m:
        return "error", "xmlconf: no pinned archive found in tools/run-xmlconf.py"
    pin = m.group(1)
    page = fetch(XMLCONF_PAGE, "text/html").decode("utf-8", "replace")
    dates = sorted(set(re.findall(r"xmlts(\d{8})\.(?:tar\.gz|zip)", page)))
    if not dates:
        return "error", "xmlconf: no archive named on %s" % XMLCONF_PAGE
    if dates[-1] > pin:
        return "newer", "W3C xmlconf xmlts%s (run-xmlconf.py): newer archive xmlts%s" % (pin, dates[-1])
    return "current", "W3C xmlconf xmlts%s (run-xmlconf.py): current" % pin


def kosit_versions(artifact):
    """The versions of a KoSIT Maven package, [] if it does not exist."""
    try:
        data = fetch(KOSIT_MAVEN % artifact, "application/xml").decode("utf-8")
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return []
        raise
    if "<metadata" not in data:
        raise ValueError("no Maven metadata for " + artifact)
    # releases only: 2.6.1-SNAPSHOT or 2.7.0-rc1 do not count
    return [v for v in re.findall(r"<version>([^<]+)</version>", data) if re.match(r"^[\d.]+$", v)]


def check_kosit_schematron():
    m = re.search(r"packages/maven/de/xeinkauf/xrechnung-([\d.]+)-schematron/\"\s*\"([\d.]+)/",
                  source("gen-schematron-rules.py"))
    if not m:
        return "error", "XRechnung Schematron: no pinned package found in tools/gen-schematron-rules.py"
    standard, version = m.group(1), m.group(2)
    versions = kosit_versions("xrechnung-%s-schematron" % standard)
    if version not in versions:
        return "error", "XRechnung Schematron: the pinned package %s is not listed" % version
    newer = [v for v in versions if version_key(v) > version_key(version)]
    # a new XRechnung version has a package of its own (a few steps ahead,
    # in case one is skipped)
    a, b, c = [int(n) for n in standard.split(".")]
    candidates = ["%d.%d.%d" % (a, b, c + k) for k in range(1, 6)]
    candidates += ["%d.%d.0" % (a, b + k) for k in range(1, 4)]
    candidates += ["%d.0.0" % (a + 1)]
    for nxt in candidates:
        found = kosit_versions("xrechnung-%s-schematron" % nxt)
        if found:
            newer.append("xrechnung-%s-schematron %s" % (nxt, ", ".join(found)))
    where = "XRechnung Schematron xrechnung-%s-schematron %s (gen-schematron-rules.py)" % (standard, version)
    if newer:
        return "newer", "%s: newer %s" % (where, "; ".join(newer))
    return "current", where + ": current"


def check_xsts_schemas():
    pins = re.findall(r'"(https://www\.w3\.org/[^"]+\.xsd)",\s*"([0-9a-f]{64})"', source("run-xsts.py"))
    if len(pins) != 2:
        return "error", "XSTS schemas: expected the pins of xml.xsd and xlink.xsd in tools/run-xsts.py"
    changed = [url for url, digest in pins if hashlib.sha256(fetch(url, "*/*")).hexdigest() != digest]
    if changed:
        return "newer", "XSTS schemas (run-xsts.py): changed at %s" % ", ".join(changed)
    return "current", "XSTS schemas xml.xsd, xlink.xsd (run-xsts.py): current"


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def check_saxon():
    pins = set(re.findall(r"SAXON-J-HE (\d+(?:\.\d+)+)", read(SAXON_ORACLE)))
    if len(pins) != 1:
        return "error", "Saxon HE: expected one Saxon version in tests/data/saxon-oracle.txt"
    pin = pins.pop()
    # parsed, so a cut-off reply fails instead of looking current
    root = ElementTree.fromstring(fetch(SAXON_MAVEN, "application/xml"))
    listed = root.findall("./versioning/versions/version")
    if not listed:
        return "error", "Saxon HE: no version list in the Maven metadata"
    versions = [v.text for v in listed if v.text and re.match(r"^[\d.]+$", v.text)]
    if pin not in versions:
        return "error", "Saxon HE: the pinned version %s is not on Maven Central" % pin
    newer = sorted((v for v in versions if version_key(v) > version_key(pin)), key=version_key)
    where = "Saxon HE %s (saxon-oracle.txt)" % pin
    if not newer:
        return "current", where + ": current"
    return "newer", "%s: newer release(s) %s on Maven Central" % (where, ", ".join(reversed(newer)))


def check_kosit_validator():
    m = re.search(r"\(KoSIT validator (\d+(?:\.\d+)+)\)", read(SAXON_ORACLE))
    if not m:
        return "error", "KoSIT validator: no version found in tests/data/saxon-oracle.txt"
    return check_release("itplr-kosit/validator", "v" + m.group(1), ["saxon-oracle.txt"])


def check_jdk():
    # 21.0.6+7, 21.0.13.1+2 or 25+36: feature, interim, update, patch, build
    m = re.search(r"^runtime (\d+)(?:\.(\d+))?(?:\.(\d+))?(?:\.(\d+))?\+(\d+)", read(XERCES_ORACLE), re.M)
    if not m:
        return "error", "Java runtime: no runtime line found in tests/data/xerces-oracle.txt"
    pin = [int(g or 0) for g in m.groups()]
    feature = pin[0]
    listed = json.loads(fetch(ADOPTIUM + "info/release_versions?release_type=ga&vendor=eclipse&sort_order=DESC"
                              "&page_size=50&version=%%5B%d%%2C%d%%29" % (feature, feature + 1),
                              "application/json").decode("utf-8"))["versions"]
    if not listed or any(v["major"] != feature for v in listed):
        return "error", "Java runtime: no usable list of %d releases from the Adoptium API" % feature
    newer = []
    for v in listed:
        key = [v["major"], v["minor"], v["security"], v.get("patch", 0), v.get("build", 0)]
        if key > pin and v["openjdk_version"] not in newer:
            newer.append(v["openjdk_version"])
    lts = json.loads(fetch(ADOPTIUM + "info/available_releases", "application/json").decode("utf-8"))["most_recent_lts"]
    pinned = m.group(0)[len("runtime "):]
    where = "Java runtime %s (xerces-oracle.txt)" % pinned
    # a newer LTS release is a note only: moving the oracle to it is a
    # decision of its own and would keep every run at exit code 1
    note = "; LTS release %d exists" % lts if lts > feature else ""
    if not newer:
        return "current", where + ": current" + note
    return "newer", "%s: newer update(s) %s%s" % (where, ", ".join(newer[:3]), note)


def check_fpc():
    # the toolchains of the set "all" (fpc324-linux: 3.2.4); releases have
    # an even minor version (3.3.x is the development branch)
    m = re.search(r"'all' = @\(([^)]*)\)", source("build.ps1"))
    built = []
    if m:
        built = [(int(a), int(b), int(c)) for a, b, c in re.findall(r"'fpc(\d)(\d)(\d+)-", m.group(1))]
    built = [v for v in built if v[1] % 2 == 0]
    if not built:
        return "error", "Free Pascal: no release toolchain in the set 'all' of tools/build.ps1"
    pin = max(built)
    releases = set()
    for page in range(1, 11):
        tags = json.loads(fetch(FPC_TAGS + "&page=%d" % page, "application/json").decode("utf-8"))
        for t in tags:
            r = re.match(r"^release_(\d+)_(\d+)_(\d+)$", t["name"])
            if r:
                releases.add(tuple(int(n) for n in r.groups()))
        if len(tags) < 100:
            break
    if pin not in releases:
        return "error", "Free Pascal: the release %d.%d.%d is not among the GitLab tags" % pin
    newer = sorted((v for v in releases if v > pin), reverse=True)
    where = "Free Pascal %d.%d.%d (newest release in build.ps1)" % pin
    if not newer:
        return "current", where + ": current"
    return "newer", "%s: newer release(s) %s" % (where, ", ".join("%d.%d.%d" % v for v in newer))


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--verbose", action="store_true", help="list every changed file")
    args = parser.parse_args()
    # (label, check): the label names a check that fails
    checks = [(r, lambda s=s, p=p, r=r: check_commit(s, p, r, args.verbose)) for s, p, r in COMMIT_PINS]
    releases = {}
    for script in RELEASE_SCRIPTS:
        try:
            found = RELEASE_URL.findall(source(script))
        except OSError as e:
            found = []
            checks.append((script, lambda e=e: ("error", "cannot read: %s" % e)))
        if not found:
            # a script whose release URLs changed form must not drop out
            checks.append((script, lambda s=script: ("error", "no GitHub release download found in tools/" + s)))
        for repo, tag in found:
            releases.setdefault((repo, tag), []).append(script)
    for (repo, tag), scripts in sorted(releases.items()):
        checks.append((repo, lambda r=repo, t=tag, s=scripts: check_release(r, t, s)))
    checks.append(("xmlconf", check_xmlconf))
    checks.append(("XRechnung Schematron", check_kosit_schematron))
    checks.append(("XSTS schemas", check_xsts_schemas))
    checks.append(("Saxon HE", check_saxon))
    checks.append(("KoSIT validator", check_kosit_validator))
    checks.append(("Java runtime", check_jdk))
    checks.append(("Free Pascal", check_fpc))
    worst = 0
    for label, check in checks:
        try:
            state, text = check()
        except Exception as e:  # network, API reply or a missing script: never exit 0 or 1 for it
            state, text = "error", "%s: check failed (%s: %s)" % (label, type(e).__name__, e)
        print(("%-8s" % state) + text)
        worst = max(worst, {"current": 0, "newer": 1, "error": 2}[state])
    return worst


if __name__ == "__main__":
    sys.exit(main())
