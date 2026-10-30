#!/usr/bin/env python3
"""Package an audited native Apple Silicon Dark Eco app without a signing key."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import zipfile


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True)


def inventory(root):
    return [{"path": str(p.relative_to(root)), "bytes": p.stat().st_size,
             "sha256": sha256(p)} for p in sorted(root.rglob("*")) if p.is_file()]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--receipt", type=Path, required=True)
    parser.add_argument("--licenses", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    require(not args.output.exists(), "Output exists; choose a new directory")
    require(args.app.is_dir() and args.app.suffix == ".app", "Input must be an app bundle")
    require(not args.output.resolve().is_relative_to(args.app.resolve()),
            "Output must be outside the input app")
    require(not args.output.resolve().is_relative_to(args.licenses.resolve()),
            "Output must be outside the license directory")
    receipt = json.loads(args.receipt.read_text())
    require(receipt["platform"] == "macOS", "Expected a native macOS receipt")
    require(not args.app.is_symlink(), "App symlinks require a separate audit")
    for path in args.app.rglob("*"):
        require(not path.is_symlink(), "Bundle symlinks require a separate audit")
        require(path.suffix.lower() not in {".iso", ".dgo", ".cgo", ".fr3", ".vag", ".str",
                                            ".p12", ".pfx", ".pem", ".key",
                                            ".mobileprovision", ".provisionprofile"},
                "Retail payload or private signing material found")
    require({p.name for p in args.app.iterdir()} == {"Contents"}, "Unexpected app root content")
    contents = args.app / "Contents"
    require({p.name for p in contents.iterdir()} <=
            {"Info.plist", "PkgInfo", "MacOS", "Resources", "Frameworks", "_CodeSignature"},
            "Unexpected bundle content")
    info = plistlib.loads((contents / "Info.plist").read_bytes())
    require(info["CFBundleSupportedPlatforms"] == ["MacOSX"], "Expected native macOS app")
    require(info["CFBundleExecutable"] == "Dark Eco", "Unexpected executable")
    require(info["CFBundleVersion"] == receipt["package_build"], "Build differs from receipt")
    require(info["CFBundleShortVersionString"] == receipt["version"], "Version differs from receipt")
    require(info["LSMinimumSystemVersion"] == receipt["minimum_os"], "Minimum OS differs from receipt")
    executable = contents / "MacOS/Dark Eco"
    require(sha256(executable) == receipt["input_executable_sha256"], "Executable differs from audit")
    require(run("lipo", "-archs", str(executable)).stdout.strip() == "arm64",
            "Expected Apple Silicon arm64 executable")
    require("platform MACOS\n" in run("xcrun", "vtool", "-show-build", str(executable)).stdout,
            "Expected native Mac code, not Catalyst or simulator code")
    require(not list(args.app.rglob("GOALPadJak2Runtime.framework")),
            "This audited Mac package supports Jak 1 only")
    pack = contents / "Resources/Jak1SourceObjectPack"
    require(sha256(pack / "object_pack_manifest.tsv") == receipt["source_pack_manifest_sha256"],
            "Source pack differs from audit")
    rows = (pack / "object_pack_manifest.tsv").read_text().splitlines()[4:]
    require(len(rows) == 518, "Incomplete Jak 1 source pack")
    expected = {"object_pack_manifest.tsv"}
    for row in rows:
        _, _, name, size, _ = row.split("\t")
        require(Path(name).name == name, "Unsafe source object name")
        require((pack / name).stat().st_size == int(size), "Incomplete source object")
        expected.add(name)
    require({p.name for p in pack.iterdir()} == expected, "Unexpected source pack file")
    original = inventory(args.app)
    require(hashlib.sha256(json.dumps(original, sort_keys=True).encode()).hexdigest()
            == receipt["input_bundle_manifest_sha256"], "Bundle differs from audit")
    require(args.licenses.is_dir() and not args.licenses.is_symlink(), "License directory is required")
    notices = list(args.licenses.rglob("*"))
    require(any(p.is_file() for p in notices) and all(not p.is_symlink() for p in notices),
            "Expected regular license files")
    entitlements = {"com.apple.security.app-sandbox": True,
                    "com.apple.security.files.user-selected.read-only": True}
    args.output.mkdir(parents=True)
    with tempfile.TemporaryDirectory(prefix="dark-eco-mac-package-") as temporary:
        stage = Path(temporary)
        app = stage / args.app.name
        shutil.copytree(args.app, app)
        resources = app / "Contents/Resources"
        shutil.copytree(args.licenses, resources / "ThirdPartyNotices")
        (resources / "RELEASE-PROVENANCE.json").write_text(json.dumps(receipt, indent=2) + "\n")
        signing = stage / "mac-entitlements.plist"
        signing.write_bytes(plistlib.dumps(entitlements))
        run("codesign", "--force", "--sign", "-", "--timestamp=none", "--options", "runtime",
            "--entitlements", str(signing), str(app))
        run("codesign", "--verify", "--deep", "--strict", str(app))
        actual = run("codesign", "-d", "--entitlements", "-", "--xml", str(app)).stdout
        require(plistlib.loads(actual.encode()) == entitlements, "Unexpected output capabilities")
        files = inventory(app)
        after = {entry["path"]: entry for entry in files}
        for entry in original:
            if entry["path"] not in {"Contents/MacOS/Dark Eco", "Contents/_CodeSignature/CodeResources"}:
                require(after.get(entry["path"]) == entry, "Packaging changed runtime/resources")
        archive = args.output / f"DarkEco-macOS-arm64-2.0-build{receipt['package_build']}-preview.zip"
        with zipfile.ZipFile(archive, "x", compression=zipfile.ZIP_DEFLATED,
                             compresslevel=6, strict_timestamps=False) as zipped:
            for path in sorted(app.rglob("*")):
                zipped.write(path, str(path.relative_to(stage)))
        with zipfile.ZipFile(archive) as zipped:
            require(zipped.testzip() is None, "Archive verification failed")
        report = {"archive": archive.name, "archive_bytes": archive.stat().st_size,
                  "archive_sha256": sha256(archive), "platform": "macOS", "architecture": "arm64",
                  "version": info["CFBundleShortVersionString"], "build": receipt["package_build"],
                  "minimum_os": info["LSMinimumSystemVersion"], "games": ["Jak 1"],
                  "entitlements": entitlements, "signing": "ad-hoc hardened runtime; not notarized",
                  "fresh_user_launch_and_gameplay": "not performed", "provenance": receipt,
                  "files": files}
        (args.output / "PACKAGE-MANIFEST.json").write_text(json.dumps(report, indent=2) + "\n")
        (args.output / "SHA256SUMS").write_text(f"{sha256(archive)}  {archive.name}\n")
    require(inventory(args.app) == original, "Original build unexpectedly changed")
    print(json.dumps({k: v for k, v in report.items() if k not in {"files", "provenance"}}, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"Packaging stopped: {error}") from error
