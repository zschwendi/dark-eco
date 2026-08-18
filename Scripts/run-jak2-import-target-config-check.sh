#!/bin/sh
# Source-level contract for Dark Eco's single-app Jak II runtime and import wiring.

set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
python3 - "$root" <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
project = (root / "GOALPad.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
jak1_debug = (root / "Configuration/GOALPad-Importer-Debug.xcconfig").read_text(encoding="utf-8")
jak1_release = (root / "Configuration/GOALPad-Importer-Release.xcconfig").read_text(encoding="utf-8")

def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)

def target_block(identifier: str) -> str:
    match = re.search(rf"\t\t{identifier} /\*.*?\n\t\t\}};", project, re.DOTALL)
    require(match is not None, f"missing native target {identifier}")
    return match.group(0)

for obsolete in (
    "Eco Jak II Dev",
    "EcoJak2Dev.app",
    "Jak2Dev-Debug.xcconfig",
    "Jak2Dev-Release.xcconfig",
    "com.zephyrstudiosllc.eco.jak2dev",
):
    require(obsolete not in project, f"obsolete standalone product remains in project: {obsolete}")

for obsolete_path in (
    root / "Configuration/Jak2Dev-Debug.xcconfig",
    root / "Configuration/Jak2Dev-Release.xcconfig",
    root / "GOALPad.xcodeproj/xcshareddata/xcschemes/Eco Jak II Dev.xcscheme",
):
    require(not obsolete_path.exists(), f"obsolete standalone file remains: {obsolete_path}")

runtime_target = target_block("F10200000000000000000002")
runtime_phases = re.findall(r"/\* ([^*]+) \*/", re.search(
    r"buildPhases = \((.*?)\n\t\t\t\);", runtime_target, re.DOTALL
).group(1))
require(runtime_phases == [
    "Verify Jak II AOT",
    "Build Jak II native runtime",
    "Build Jak II import composer",
    "Sources",
    "Frameworks",
    "Headers",
], f"unexpected GOALPadJak2Runtime phase order: {runtime_phases}")

app_target = target_block("92C2B201301C0D2F0025E4D5")
app_phases = re.findall(r"/\* ([^*]+) \*/", re.search(
    r"buildPhases = \((.*?)\n\t\t\t\);", app_target, re.DOTALL
).group(1))
require(app_phases == [
    "Verify generated AOT",
    "Compile Metal shaders",
    "Build Jak 1 import composer",
    "Sources",
    "Frameworks",
    "Embed Frameworks",
    "Resources",
    "Stage Jak 1 importer resources",
    "Stage Jak II importer resources",
], f"unexpected Dark Eco phase order: {app_phases}")
require("Build Jak II" not in app_target and "Verify Jak II" not in app_target,
        "Dark Eco must consume Jak II through its embedded runtime framework")
require("F10800000000000000000002 /* PBXTargetDependency */" in app_target,
        "Dark Eco must depend on GOALPadJak2Runtime")

for marker in (
    "F10100000000000000000002 /* GOALPadJak2Runtime.framework in Frameworks */",
    "F10100000000000000000004 /* GOALPadJak2Runtime.framework in Embed Frameworks */",
    "F11200000000000000000004 /* Stage Jak II importer resources */ = {",
    '"$(SRCROOT)/Scripts/stage-jak2-import-composer-resources.sh"',
    '"$(GOALPAD_JAK2_PROJECT_RESOURCES)"',
    '"$(GOALPAD_JAK2_SOURCE_OBJECT_PACK_RESOURCES)"',
):
    require(marker in project, f"missing unified-product contract: {marker}")

require('#include "Jak2Packaging.xcconfig"' in jak1_debug
        and '#include "Jak2Packaging.xcconfig"' in jak1_release,
        "Dark Eco must receive the shared Jak II packaging paths")
require("GOALPAD_HAS_JAK2_IMPORT_COMPOSER" not in jak1_debug
        and "GOALPAD_HAS_JAK2_IMPORT_COMPOSER" not in jak1_release,
        "Dark Eco must not compile the Jak II composer into the app target")

native_target_ids = re.findall(r"\t\t([A-F0-9]{24}) /\*.*?\*/ = \{\n\t\t\tisa = PBXNativeTarget;",
                               project)
require(native_target_ids == ["F10200000000000000000002", "92C2B201301C0D2F0025E4D5"],
        f"unexpected native target set: {native_target_ids}")

print("Dark Eco unified Jak II target/config source checks passed")
PY
