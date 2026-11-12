"""Build a private, native Chinese PoE 1 app from the matching English app."""

import argparse
import hashlib
import plistlib
import shutil
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path


HERE = Path(__file__).resolve().parent
SOURCE = HERE.parent / "src"
SOURCE_COMMIT = "3dbca4463c0a59079d9f7f032d8240cf868e09da"
APP_NAME = "Path of Building PoE1 中文"
EXECUTABLE = "Path of Building PoE1 Zh"
APP_ID = "local.cathong.PathOfBuildingPoE1Zh"
SUPPORT_DIR = "PathOfBuildingPoE1Zh-3dbca4463"  # Stable; holds the existing User directory.
PORT_COMMIT = "41df69eddb82a6fa2cdcf02c790082e651548ec6"


@dataclass(frozen=True)
class CandidateSource:
    root: Path
    upstream_commit: str
    source_tree: str
    version: str

TERMS = ("gems.json", "items.json", "passives.json", "uniques.json")
EXTRA_TERMS = (
    "ui.json", "stats.json", "tags.json", "monsters.json",
    "tree_names.json", "tree_effects.json", "gem_descriptions.json", "game_stats_extra.json",
)
LUA_OVERLAY = (
    "Classes/BuildListControl.lua",
    "Classes/PathControl.lua",
    "Classes/ListControl.lua",
    "Classes/EditControl.lua",
    "Classes/DropDownControl.lua",
    "Classes/ButtonControl.lua",
    "Classes/CalcsTab.lua",
    "Classes/CheckBoxControl.lua",
    "Classes/ConfigTab.lua",
    "Classes/GemSelectControl.lua",
    "Classes/GemTooltip.lua",
    "Classes/ImportTab.lua",
    "Classes/ItemsTab.lua",
    "Classes/NotesTab.lua",
    "Classes/PartyTab.lua",
    "Classes/PassiveTreeView.lua",
    "Classes/SkillsTab.lua",
    "Classes/TreeTab.lua",
    "Locales/zhCN.lua",
    "Modules/Build.lua",
    "Modules/BuildList.lua",
    "Modules/Localization.lua",
    "Modules/MacCjkFont.lua",
    "Modules/Main.lua",
)


def run(*args):
    subprocess.run(args, check=True)


def package(base_app, port, terms, output, *, candidate=None, preview=False):
    info = plistlib.loads((base_app / "Contents/Info.plist").read_bytes())
    if candidate is None and info.get("PoBSourceCommit") != SOURCE_COMMIT:
        raise ValueError(f"The English base app must use PoB source {SOURCE_COMMIT}. Use update.py for newer sources.")
    if output.exists() or output.is_symlink() or output.suffix != ".app":
        raise ValueError("Specify an unused output path ending in .app.")
    if base_app == output or base_app in output.parents:
        raise ValueError("The candidate cannot be placed inside the runtime template.")
    revision = candidate.upstream_commit if candidate else SOURCE_COMMIT
    version = candidate.version if candidate else info["CFBundleShortVersionString"]
    support_dir = SUPPORT_DIR + ("-Preview" if preview else "")
    app_name = APP_NAME + (" 预览" if preview else "")

    bootstrap = (port / "macos/mac_entry.lua").read_text()
    anchor = 'dofile("Launch.lua")'
    if bootstrap.count(anchor) != 1:
        raise ValueError("The port bootstrap does not match this PoB version.")
    bootstrap = bootstrap.replace(anchor, '''local locale = require("Modules.Localization")
locale.macFont = require("Modules.MacCjkFont")
locale.SetLanguage("zh-CN")

''' + anchor)

    launcher = (port / "macos/launcher.cpp").read_text()
    anchor = "        // Publish the App Support root to SimpleGraphic so it can redirect\n"
    if launcher.count(anchor) != 1:
        raise ValueError("The port launcher does not match this PoB version.")
    launcher = launcher.replace(anchor, '''        for (const char* filename : {"changelog.txt", "help.txt", "LICENSE.md"}) {
            std::error_code error;
            fs::copy_file(bundleResourcesPath / filename, *appSupport / filename,
                          fs::copy_options::overwrite_existing, error);
            if (error) {
                std::fprintf(stderr, "Unable to copy %s: %s\\n", filename, error.message().c_str());
                return 1;
            }
        }

''' + anchor)

    # Stage and sign before making the output app visible.
    with tempfile.TemporaryDirectory(dir=output.parent, prefix=".pob-zh-") as temporary:
        work = Path(temporary)
        app = work / output.name
        run("/bin/cp", "-cR", base_app, app)
        contents = app / "Contents"
        resources = contents / "Resources"
        src = resources / "src"
        if candidate:
            # Use the merged Git tree in its entirety. Never overlay old full
            # Lua files on a new upstream checkout or copy the live cache.
            for relative, name in (("src", "src"), ("runtime/lua", "lua"),
                                   ("runtime/SimpleGraphic", "SimpleGraphic")):
                dest = resources / name
                shutil.rmtree(dest)
                shutil.move(candidate.root / relative, dest)
            for name in ("changelog.txt", "help.txt", "LICENSE.md"):
                shutil.copy2(candidate.root / name, resources / name)
            shutil.copy2(candidate.root / "manifest.xml", src / "manifest.xml")
        else:
            for relative in LUA_OVERLAY:
                target = src / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(SOURCE / relative, target)
        (src / "mac_entry.lua").write_text(bootstrap)

        glyph_sources = [src / "Locales/zhCN.lua"]
        glyph_sources.extend(sorted((src / "Locales/Atlas").glob("*.json")))
        game = src / "Locales/Game"
        if game.exists():
            shutil.rmtree(game)
        if terms:
            game.mkdir()
            extra = tuple(name for name in EXTRA_TERMS if (terms / name).is_file())
            notices = ("NOTICE.md", "SOURCE.txt")
            if extra:
                notices += ("LICENSE-PobTools.txt",)
            for name in (*TERMS, *extra, *notices):
                shutil.copy2(terms / name, game / name)
            glyph_sources.extend(game / name for name in (*TERMS, *extra))
        run("/usr/bin/swiftc", "-O", "-module-cache-path", work / "module-cache",
            "-o", work / "generate", HERE / "generate.swift")
        run("python3", HERE / "codepoints.py", work / "codepoints.txt", *glyph_sources)
        run(work / "generate", work / "codepoints.txt", src / "Locales")
        digest = hashlib.sha256(bootstrap.encode())
        for path in [*(src / name for name in LUA_OVERLAY), *glyph_sources[1:],
                     *sorted((src / "Locales/CJK").iterdir())]:
            digest.update(path.read_bytes())
        if candidate:
            digest.update(candidate.source_tree.encode())
        bundle_version = f"{version}-{revision[:8]}-zh-{digest.hexdigest()[:12]}"

        launcher_path = work / "launcher.cpp"
        launcher_path.write_text(launcher)
        bin_dir = contents / "MacOS"
        (bin_dir / info["CFBundleExecutable"]).unlink()
        exe = bin_dir / EXECUTABLE
        run("/usr/bin/clang++", "-std=c++17", "-O2", "-arch", "arm64", "-mmacosx-version-min=11.0",
            f'-DPOB_BUNDLE_VERSION_STRING="{bundle_version}"',
            '-DPOB_MAC_VERSION_STRING="dev"', f'-DPOB_APP_SUPPORT_DIR="{support_dir}"',
            launcher_path, "-o", exe)
        info.update({
            "CFBundleExecutable": EXECUTABLE,
            "CFBundleIdentifier": APP_ID + (".preview" if preview else ""),
            "CFBundleName": app_name,
            "CFBundleDisplayName": app_name,
            "CFBundleLocalizations": ["en", "zh_CN"],
            "CFBundleShortVersionString": version,
            "CFBundleVersion": version,
            "PoBSourceCommit": revision,
            "PoBNativeBaseCommit": info.get("PoBNativeBaseCommit", info["PoBSourceCommit"]),
            "PoBAppSupportDirectory": support_dir,
            "PoBChinesePreview": preview,
        })
        if candidate:
            info["PoBMergedSourceTree"] = candidate.source_tree
            info["PoBMacPortCommit"] = PORT_COMMIT
        (contents / "Info.plist").write_bytes(plistlib.dumps(info))
        run("/usr/bin/codesign", "--force", "--options", "runtime", "--timestamp=none",
            "--entitlements", port / "macos/entitlements.plist", "--sign", "-", app)
        run("/usr/bin/codesign", "--verify", "--deep", "--strict", app)
        app.rename(output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-app", required=True, type=Path)
    parser.add_argument("--port", required=True, type=Path, help="PathOfBuilding-Mac source checkout")
    parser.add_argument("--terms", type=Path, help="Optional directory with the four local game dictionaries and notices")
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--preview", action="store_true", help="Use the separate preview app identity and settings")
    args = parser.parse_args()
    package(args.base_app.resolve(), args.port.resolve(), args.terms and args.terms.resolve(),
            args.output.resolve(), preview=args.preview)
