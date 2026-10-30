#!/usr/bin/env python3
"""Package an audited, complete Dark Eco visionOS app for user re-signing.

This never builds, installs, uploads, edits the input app, or uses a signing key.
The output uses ad-hoc signatures with no developer/iCloud entitlements.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
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


def audit_app(app, receipt):
    require(app.is_dir() and app.suffix == ".app", "Input must be an .app directory")
    require(not app.is_symlink(), "Input must not be a symlink")
    allowed = {"Assets.car", "Dark Eco", "Frameworks", "Info.plist", "PkgInfo",
               "Jak1SourceObjectPack", "Jak2SourceObjectPack", "Jak2ProjectResources",
               "OpenGOALProjectResources", "PLzmaSDK_PLzmaSDK.bundle",
               "PrivacyInfo.xcprivacy", "VisionStereoWindow.reality", "_CodeSignature",
               "default.metallib", "embedded.mobileprovision"}
    require(set(p.name for p in app.iterdir()) <= allowed,
            "Unexpected top-level content: review it before releasing")
    for p in app.rglob("*"):
        require(not p.is_symlink(), "Symlinks require a separate bundle audit")
        require(p.suffix.lower() not in {".iso", ".dgo", ".cgo", ".fr3", ".vag",
                                         ".str", ".p12", ".pfx", ".key"},
                "Retail payload or private signing file found")
    info = plistlib.loads((app / "Info.plist").read_bytes())
    require(info["CFBundleSupportedPlatforms"] == ["XROS"], "A device visionOS app is required")
    require(info["CFBundleExecutable"] == "Dark Eco", "Unexpected app executable")
    require(info["CFBundleVersion"] == receipt["build"], "Build number differs from receipt")
    require(sha256(app / "Dark Eco") == receipt["input_executable_sha256"],
            "Input executable differs from audited build")
    framework = app / "Frameworks/GOALPadJak2Runtime.framework"
    require(sha256(framework / "GOALPadJak2Runtime") == receipt["input_framework_sha256"],
            "Embedded Jak II runtime differs from audited build")
    for binary in [app / "Dark Eco", framework / "GOALPadJak2Runtime"]:
        require("platform VISIONOS" in run("xcrun", "vtool", "-show-build", str(binary)).stdout,
                "Native code is not built for physical visionOS")
    for game, count in [("Jak1", 518), ("Jak2", 840)]:
        pack = app / (game + "SourceObjectPack")
        manifest = pack / "object_pack_manifest.tsv"
        require(sha256(manifest) == receipt["source_pack_manifests_sha256"][game],
                "Source pack manifest differs from audited build")
        rows = [line.split("\t") for line in manifest.read_text().splitlines()[4:]]
        require(len(rows) == count, "Incomplete source object pack")
        expected = {"object_pack_manifest.tsv"}
        for source, tag, filename, size, xxhash in rows:
            require(Path(filename).name == filename, "Unsafe source object filename")
            require((pack / filename).stat().st_size == int(size), "Incomplete source object")
            expected.add(filename)
        require(set(p.name for p in pack.iterdir()) == expected, "Unexpected source pack file")
    run("codesign", "--verify", "--deep", "--strict", str(app))
    return info


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--receipt", type=Path, required=True,
                        help="Sanitized audit receipt matching the original signed app")
    parser.add_argument("--licenses", type=Path, required=True,
                        help="Reviewed upstream notices directory to include in the app")
    parser.add_argument("--output", type=Path, required=True,
                        help="New output directory (must not already exist)")
    args = parser.parse_args()
    require(not args.output.exists(), "Output exists; choose a new directory")
    require(not args.output.resolve().is_relative_to(args.app.resolve()),
            "Output must be outside the input app")
    require(not args.output.resolve().is_relative_to(args.licenses.resolve()),
            "Output must be outside the license directory")
    receipt = json.loads(args.receipt.read_text())
    require(re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", receipt["package_build"]),
            "Invalid package build number")
    info = audit_app(args.app, receipt)
    original = inventory(args.app)
    require(hashlib.sha256(json.dumps(original, sort_keys=True).encode()).hexdigest()
            == receipt["input_bundle_manifest_sha256"],
            "Input bundle content differs from the audited artifact")
    require(args.licenses.is_dir(), "License directory is required")
    require(not args.licenses.is_symlink(), "License directory must not be a symlink")
    notices = list(args.licenses.rglob("*"))
    require(any(p.is_file() for p in notices), "License directory is empty")
    require(all(not p.is_symlink() for p in notices), "License symlinks are not accepted")
    args.output.mkdir(parents=True)
    with tempfile.TemporaryDirectory(prefix="dark-eco-package-") as staging:
        stage = Path(staging)
        payload = stage / "Payload"
        payload.mkdir()
        app = payload / args.app.name
        shutil.copytree(args.app, app)
        framework = app / "Frameworks/GOALPadJak2Runtime.framework"
        for bundle in [framework, app]:
            run("codesign", "--remove-signature", str(bundle))
            profile = bundle / "embedded.mobileprovision"
            if profile.exists():
                profile.unlink()
            signatures = bundle / "_CodeSignature"
            if signatures.exists():
                shutil.rmtree(signatures)
        packaged_info = dict(info)
        packaged_info["CFBundleVersion"] = receipt["package_build"]
        (app / "Info.plist").write_bytes(plistlib.dumps(packaged_info, fmt=plistlib.FMT_BINARY))
        shutil.copytree(args.licenses, app / "ThirdPartyNotices")
        (app / "IPA-PROVENANCE.json").write_text(json.dumps(receipt, indent=2) + "\n")
        empty = stage / "empty-entitlements.plist"
        empty.write_bytes(plistlib.dumps({}))
        for bundle in [framework, app]:
            run("codesign", "--force", "--sign", "-", "--timestamp=none",
                "--entitlements", str(empty), str(bundle))
        run("codesign", "--verify", "--deep", "--strict", str(app))
        for bundle in [framework, app]:
            entitlements = run("codesign", "-d", "--entitlements", "-", "--xml", str(bundle)).stdout
            require(not entitlements.strip() or plistlib.loads(entitlements.encode()) == {},
                    "Output unexpectedly retains signing entitlements")
        require(not list(app.rglob("*.mobileprovision")), "Output retains a provisioning profile")
        output_inventory = inventory(app)
        changed = {"Dark Eco", "Info.plist", "Frameworks/GOALPadJak2Runtime.framework/GOALPadJak2Runtime",
                   "embedded.mobileprovision", "_CodeSignature/CodeResources",
                   "Frameworks/GOALPadJak2Runtime.framework/_CodeSignature/CodeResources"}
        after = {entry["path"]: entry for entry in output_inventory}
        for entry in original:
            if entry["path"] not in changed:
                require(after.get(entry["path"]) == entry, "Packaging changed a runtime/resource file")
        ipa = args.output / f"DarkEco-visionOS-2.0-build{receipt['package_build']}-preview.ipa"
        with zipfile.ZipFile(ipa, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
            for path in sorted(payload.rglob("*")):
                archive.write(path, str(path.relative_to(stage)))
        with zipfile.ZipFile(ipa) as archive:
            require(archive.testzip() is None, "IPA ZIP verification failed")
        report = {"ipa": ipa.name, "ipa_bytes": ipa.stat().st_size, "ipa_sha256": sha256(ipa),
                  "version": info["CFBundleShortVersionString"], "build": receipt["package_build"],
                  "original_build": info["CFBundleVersion"],
                  "minimum_visionos": info["MinimumOSVersion"],
                  "bundle_identifier": info["CFBundleIdentifier"],
                  "signing": "ad-hoc, empty entitlements; user must re-sign",
                  "icloud": "not entitled; local saves and manual export/import only",
                  "physical_sideload_test": "not performed", "provenance": receipt,
                  "files": output_inventory}
        (args.output / "PACKAGE-MANIFEST.json").write_text(json.dumps(report, indent=2) + "\n")
        (args.output / "SHA256SUMS").write_text(f"{sha256(ipa)}  {ipa.name}\n")
    require(inventory(args.app) == original, "Original app unexpectedly changed")
    print(json.dumps({k: v for k, v in report.items() if k not in {"files", "provenance"}}, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"Packaging stopped: {error}") from error
