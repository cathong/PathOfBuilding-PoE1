"""Build a private, native Chinese PoE 1 app from the matching English app."""

import argparse
import hashlib
import plistlib
import shutil
import subprocess
import tempfile
from pathlib import Path


HERE = Path(__file__).resolve().parent
SOURCE = HERE.parent / "src"
SOURCE_COMMIT = "3dbca4463c0a59079d9f7f032d8240cf868e09da"
APP_NAME = "Path of Building PoE1 中文"
EXECUTABLE = "Path of Building PoE1 Zh"
TERMS = ("gems.json", "items.json", "passives.json", "uniques.json")
LUA_OVERLAY = (
    "Classes/BuildListControl.lua",
    "Classes/CalcsTab.lua",
    "Classes/CheckBoxControl.lua",
    "Classes/ConfigTab.lua",
    "Classes/GemSelectControl.lua",
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


def package(base_app, port, terms, output):
    info = plistlib.loads((base_app / "Contents/Info.plist").read_bytes())
    if info.get("PoBSourceCommit") != SOURCE_COMMIT:
        raise ValueError(f"The English base app must use PoB source {SOURCE_COMMIT}.")
    if output.exists() or output.suffix != ".app":
        raise ValueError("Specify an unused output path ending in .app.")

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
        src = contents / "Resources/src"
        for relative in LUA_OVERLAY:
            target = src / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(SOURCE / relative, target)
        (src / "mac_entry.lua").write_text(bootstrap)

        glyph_sources = [src / "Locales/zhCN.lua"]
        if terms:
            game = src / "Locales/Game"
            game.mkdir(exist_ok=True)
            for name in (*TERMS, "NOTICE.md", "SOURCE.txt"):
                shutil.copy2(terms / name, game / name)
            glyph_sources.extend(game / name for name in TERMS)
        run("/usr/bin/swiftc", "-O", "-module-cache-path", work / "module-cache",
            "-o", work / "generate", HERE / "generate.swift")
        run("python3", HERE / "codepoints.py", work / "codepoints.txt", *glyph_sources)
        run(work / "generate", work / "codepoints.txt", src / "Locales")
        digest = hashlib.sha256(bootstrap.encode())
        for path in [*(src / name for name in LUA_OVERLAY), *glyph_sources[1:],
                     *sorted((src / "Locales/CJK").iterdir())]:
            digest.update(path.read_bytes())
        bundle_version = f"2.67.2-{SOURCE_COMMIT[:8]}-zh-{digest.hexdigest()[:12]}"

        launcher_path = work / "launcher.cpp"
        launcher_path.write_text(launcher)
        bin_dir = contents / "MacOS"
        (bin_dir / info["CFBundleExecutable"]).unlink()
        exe = bin_dir / EXECUTABLE
        run("/usr/bin/clang++", "-std=c++17", "-O2", "-arch", "arm64", "-mmacosx-version-min=11.0",
            f'-DPOB_BUNDLE_VERSION_STRING="{bundle_version}"',
            '-DPOB_MAC_VERSION_STRING="dev"', '-DPOB_APP_SUPPORT_DIR="PathOfBuildingPoE1Zh-3dbca4463"',
            launcher_path, "-o", exe)
        info.update({
            "CFBundleExecutable": EXECUTABLE,
            "CFBundleIdentifier": "local.cathong.PathOfBuildingPoE1Zh",
            "CFBundleName": APP_NAME,
            "CFBundleDisplayName": APP_NAME,
            "CFBundleLocalizations": ["en", "zh_CN"],
        })
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
    args = parser.parse_args()
    package(args.base_app.resolve(), args.port.resolve(), args.terms and args.terms.resolve(), args.output.resolve())
