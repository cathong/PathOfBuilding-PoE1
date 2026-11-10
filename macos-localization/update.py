"""Prepare a Chinese PoE 1 update in isolation; never replace the installed app."""

import argparse
import hashlib
import json
import plistlib
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

from package import CandidateSource, EXTRA_TERMS, PORT_COMMIT, SOURCE_COMMIT, SUPPORT_DIR, TERMS, package

UPSTREAM = "https://github.com/PathOfBuildingCommunity/PathOfBuilding.git"
DEFAULT_REF = "refs/heads/dev"
INSTALL = Path.home() / "Applications/Path of Building PoE1 中文.app"
GIT = "/usr/bin/git"
COMMIT = re.compile(r"[0-9a-f]{40}")
VERSION = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+")
HERE = Path(__file__).resolve().parent
ARCHIVE_PATHS = ("src", "runtime/lua", "runtime/SimpleGraphic", "manifest.xml",
                 "changelog.txt", "help.txt", "LICENSE.md")


def git(repo, *args, capture=True):
    p = subprocess.run(
        [GIT, "-C", repo, "-c", "core.hooksPath=/dev/null", *args],
        check=True, text=True, stdout=subprocess.PIPE if capture else None,
    )
    return p.stdout.strip() if capture else None


def exact_commit(repo, oid):
    if not isinstance(oid, str) or not COMMIT.fullmatch(oid):
        raise ValueError(f"Expected a full Git commit ID, got {oid!r}")
    return git(repo, "rev-parse", "--verify", f"{oid}^{{commit}}")


def ancestor(repo, older, newer):
    p = subprocess.run(
        [GIT, "-C", repo, "merge-base", "--is-ancestor", older, newer],
        check=False,
    )
    if p.returncode not in (0, 1):
        raise RuntimeError("Could not verify upstream ancestry.")
    return p.returncode == 0


def version_from_manifest(manifest):
    node = ET.parse(manifest).getroot().find("Version")
    version = node.get("number") if node is not None else None
    if not version or not VERSION.fullmatch(version):
        raise ValueError("Cannot read the PoB source version from manifest.xml.")
    if node.get("branch") or node.get("platform"):
        raise ValueError("Expected a source manifest (no branch/platform); refusing to enable the in-app updater.")
    return version


def export_tree(repo, tree, dest):
    dest.mkdir()
    with subprocess.Popen(
        [GIT, "-C", repo, "archive", "--format=tar", tree, *ARCHIVE_PATHS],
        stdout=subprocess.PIPE,
    ) as proc:
        assert proc.stdout is not None
        try:
            subprocess.run(["/usr/bin/tar", "-xf", "-", "-C", dest],
                           stdin=proc.stdout, check=True)
        finally:
            proc.stdout.close()
        if proc.wait() != 0:
            raise RuntimeError("The complete source tree could not be exported.")


def check_port(port):
    if git(port, "rev-parse", "HEAD") != PORT_COMMIT or git(port, "status", "--porcelain"):
        raise ValueError(f"Use a clean PathOfBuilding-Mac mac-v0.1.4 checkout ({PORT_COMMIT}).")


def check_terms(terms):
    if terms is None:
        return None
    for name in (*TERMS, "SOURCE.txt", "NOTICE.md"):
        if not (terms / name).is_file():
            raise ValueError(f"Missing translation source file: {terms / name}")
    extra = tuple(name for name in EXTRA_TERMS if (terms / name).is_file())
    if extra and not (terms / "LICENSE-PobTools.txt").is_file():
        raise ValueError("Extended PobTools dictionaries require LICENSE-PobTools.txt.")
    for name in (*TERMS, *extra):
        obj = json.loads((terms / name).read_bytes())
        if not isinstance(obj, dict) or not isinstance(obj.get("entries"), dict):
            raise ValueError(f"Missing entries object in {terms / name}")
        if not obj["entries"] or not all(isinstance(k, str) and isinstance(v, str)
                                         for k, v in obj["entries"].items()):
            raise ValueError(f"Expected a nonempty English → Chinese string dictionary: {terms / name}")
    return terms


def check_existing(template):
    info = plistlib.loads((template / "Contents/Info.plist").read_bytes())
    if info.get("PoBChinesePreview") or info.get("CFBundleIdentifier") != "local.cathong.PathOfBuildingPoE1Zh":
        raise ValueError("Use the installed Chinese app (or its production backup) as the native runtime template.")
    if info.get("PoBAppSupportDirectory", SUPPORT_DIR) != SUPPORT_DIR:
        raise ValueError("This app does not use the expected existing User directory.")
    subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", template], check=True)
    return info


def prepare(args):
    repo = args.repo.resolve()
    template = args.template_app.resolve()
    info = check_existing(template)
    installed = info["PoBSourceCommit"]
    native_base = info.get("PoBNativeBaseCommit", installed)
    fork_head = git(repo, "rev-parse", "HEAD")
    # Packaging helpers run from disk; source and data are exported from Git.
    if git(repo, "status", "--porcelain", "--", ".", ":(exclude)macos-localization/**"):
        raise ValueError("The Chinese source checkout has uncommitted changes. Commit them or use a clean maintenance checkout.")
    if args.output:
        if args.output.is_symlink():
            raise ValueError("Output must not be a symlink.")
        out = args.output.resolve()
        if out.exists() or out.suffix != ".app" or not out.parent.is_dir():
            raise ValueError("Choose a new .app output under an existing staging directory.")
        if template in out.parents or out == INSTALL.resolve() or INSTALL.resolve() in out.parents:
            raise ValueError("This tool only stages candidates. It cannot write into the installed app.")
        support = Path.home() / "Library/Application Support" / SUPPORT_DIR
        if support in out.parents or support.with_name(SUPPORT_DIR + "-Preview") in out.parents:
            raise ValueError("Do not stage a candidate inside either PoB data directory.")
    else:
        out = None
    with tempfile.TemporaryDirectory(dir=out.parent if out else None, prefix=".pob-zh-update-") as scratch:
        work = Path(scratch)
        checkout = work / "source"
        git(repo, "clone", "--quiet", "--shared", "--no-hardlinks", "--no-checkout", str(repo), str(checkout))
        if args.local_commit:
            target = exact_commit(checkout, args.local_commit)
        else:
            ref = args.ref
            if ref != DEFAULT_REF and not re.fullmatch(r"refs/tags/v[0-9]+\.[0-9]+\.[0-9]+", ref):
                raise ValueError("Use refs/heads/dev or an exact PoB release tag, e.g. refs/tags/v2.67.2.")
            git(checkout, "fetch", "--no-tags", "--no-recurse-submodules", UPSTREAM, ref, capture=False)
            target = git(checkout, "rev-parse", "--verify", "FETCH_HEAD^{commit}")
        installed = exact_commit(checkout, installed)
        native_base = exact_commit(checkout, native_base)
        exact_commit(checkout, SOURCE_COMMIT)
        print(f"Installed upstream: {installed}\nCandidate upstream: {target}\nChinese source: {fork_head}", flush=True)
        if not ancestor(checkout, installed, target):
            raise ValueError("The requested ref is older or diverged from the installed upstream. Stop and review instead of downgrading.")
        if not ancestor(checkout, SOURCE_COMMIT, fork_head):
            raise ValueError("This checkout does not contain the expected Chinese source baseline.")
        if not ancestor(checkout, native_base, target):
            raise ValueError("Cannot establish native runtime ancestry for this candidate.")
        native_changes = git(checkout, "diff", "--name-only", native_base, target, "--",
                             "runtime/", "src/_SimpleGraphic.def.lua",
                             ":(exclude)runtime/lua/**", ":(exclude)runtime/SimpleGraphic/**")
        if native_changes:
            raise ValueError("Upstream native runtime files changed. Validate a matching macOS runtime before packaging:\n" + native_changes)
        if args.check_only:
            print("Upstream unchanged." if installed == target else "New upstream commit found; preview required.")
            return
        port = args.port.resolve()
        check_port(port)
        bundled_terms = template / "Contents/Resources/src/Locales/Game"
        terms = check_terms(None if args.no_terms else args.terms.resolve() if args.terms
                            else bundled_terms if bundled_terms.is_dir() else None)
        git(checkout, "checkout", "--quiet", "--detach", fork_head)
        try:
            git(checkout, "merge", "--no-ff", "--no-commit", target, capture=False)
        except subprocess.CalledProcessError as e:
            files = git(checkout, "diff", "--name-only", "--diff-filter=U")
            raise ValueError("The Chinese changes need a manual merge in a maintenance checkout. No app was produced.\n" + files) from e
        tree = git(checkout, "write-tree")
        manifest = work / "export"
        export_tree(checkout, tree, manifest)
        version = version_from_manifest(manifest / "manifest.xml")
        if (manifest / "src/first.run").exists():
            raise ValueError("A first.run marker would enable the upstream updater. Refusing to package.")
        for file in ("Locales/zhCN.lua", "Modules/Localization.lua", "Modules/MacCjkFont.lua"):
            if not (manifest / "src" / file).is_file():
                raise ValueError(f"Missing localization file in merged source: {file}")
        # Launch must still put the real Builds and Settings in the stable User directory.
        main = (manifest / "src/Modules/Main.lua").read_text()
        if 'GetScriptPath() .. "/../User/"' not in main or "locale.macFont" not in main:
            raise ValueError("The merged source no longer has the known separate User directory. Review manually.")
        package(template, port, terms, out,
                candidate=CandidateSource(manifest, target, tree, version), preview=not args.production)
        print(f"Candidate: {out}\nVersion: {version}\nMerged source tree: {tree}")
        if terms:
            for file in (*TERMS, *EXTRA_TERMS):
                if not (terms / file).is_file():
                    continue
                print(f"Terms SHA-256 {file}: {hashlib.sha256((terms / file).read_bytes()).hexdigest()}")
        print("Installed app and User data were not modified.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=HERE.parent, help="Clean Chinese source checkout")
    parser.add_argument("--template-app", type=Path, default=INSTALL, help="Signed Chinese native runtime template")
    refs = parser.add_mutually_exclusive_group()
    refs.add_argument("--ref", default=DEFAULT_REF, help="Official upstream dev or exact release ref")
    refs.add_argument("--local-commit", help="Use an exact commit already present locally, for offline rebuilds")
    parser.add_argument("--check-only", action="store_true", help="Compare upstream and installed version without packaging")
    parser.add_argument("--port", type=Path, help="Clean PathOfBuilding-Mac mac-v0.1.4 checkout")
    terms = parser.add_mutually_exclusive_group()
    terms.add_argument("--terms", type=Path, help="Validated replacement game terms; default: reuse current bundled terms")
    terms.add_argument("--no-terms", action="store_true", help="Build with UI translation only")
    parser.add_argument("--output", type=Path, help="Unused destination ending in .app")
    parser.add_argument("--production", action="store_true",
                        help="Stage a production bundle with the existing identity and User path. Does not install it.")
    args = parser.parse_args()
    if args.check_only and (args.output or args.production):
        parser.error("--check-only does not create an output")
    if not args.check_only and (not args.port or not args.output):
        parser.error("packaging needs --port and --output")
    try:
        prepare(args)
    except (OSError, KeyError, ValueError, RuntimeError, subprocess.CalledProcessError) as e:
        parser.exit(1, f"PoB update stopped: {e}\n")


if __name__ == "__main__":
    main()
