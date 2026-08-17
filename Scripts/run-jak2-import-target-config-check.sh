#!/bin/sh
# Source-level contract for the isolated Eco Jak II Dev import-composer phases, settings, and launch configuration.

set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
python3 - "$root" <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
project = (root / "GOALPad.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
debug = (root / "Configuration/Jak2Dev-Debug.xcconfig").read_text(encoding="utf-8")
release = (root / "Configuration/Jak2Dev-Release.xcconfig").read_text(encoding="utf-8")
scheme = (root / "GOALPad.xcodeproj/xcshareddata/xcschemes/Eco Jak II Dev.xcscheme").read_text(
    encoding="utf-8")
jak1_debug = (root / "Configuration/GOALPad-Importer-Debug.xcconfig").read_text(encoding="utf-8")
jak1_release = (root / "Configuration/GOALPad-Importer-Release.xcconfig").read_text(encoding="utf-8")

def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)

def target_block(identifier: str) -> str:
    match = re.search(rf"\t\t{identifier} /\*.*?\n\t\t\}};", project, re.DOTALL)
    require(match is not None, f"missing native target {identifier}")
    return match.group(0)

def object_block(identifier: str) -> str:
    match = re.search(rf"\t\t{identifier} /\*[^*]+\*/ = \{{.*?\n\t\t\}};", project, re.DOTALL)
    require(match is not None, f"missing project object {identifier}")
    return match.group(0)

jak2_target = target_block("A74000000000000000000001")
jak2_phase_names = re.findall(r"/\* ([^*]+) \*/", re.search(
    r"buildPhases = \((.*?)\n\t\t\t\);", jak2_target, re.DOTALL
).group(1))
require(jak2_phase_names == [
    "Verify Jak II AOT",
    "Build Jak II native runtime",
    "Build Jak II import composer",
    "Sources",
    "Frameworks",
    "Embed Frameworks",
    "Resources",
    "Stage Jak II importer resources",
], f"unexpected Eco Jak II Dev phase order: {jak2_phase_names}")

jak2_runtime_target = target_block("F10200000000000000000002")
jak2_runtime_phase_names = re.findall(r"/\* ([^*]+) \*/", re.search(
    r"buildPhases = \((.*?)\n\t\t\t\);", jak2_runtime_target, re.DOTALL
).group(1))
require(jak2_runtime_phase_names == [
    "Verify Jak II AOT",
    "Build Jak II native runtime",
    "Build Jak II import composer",
    "Sources",
    "Frameworks",
    "Headers",
], f"unexpected GOALPadJak2Runtime phase order: {jak2_runtime_phase_names}")

jak1_target = target_block("92C2B201301C0D2F0025E4D5")
jak1_phase_names = re.findall(r"/\* ([^*]+) \*/", re.search(
    r"buildPhases = \((.*?)\n\t\t\t\);", jak1_target, re.DOTALL
).group(1))
require(jak1_phase_names == [
    "Verify generated AOT",
    "Compile Metal shaders",
    "Build Jak 1 import composer",
    "Sources",
    "Frameworks",
    "Embed Frameworks",
    "Resources",
    "Stage Jak 1 importer resources",
    "Stage Jak II importer resources",
], f"the GOALPad/Jak 1 target phase block changed: {jak1_phase_names}")
require("Build Jak II" not in jak1_target and "Verify Jak II" not in jak1_target
        and "GOALPAD_JAK2" not in jak1_target,
        "Jak II compile or archive-build wiring entered the GOALPad/Jak 1 target")

for marker in (
    "A74200000000000000000001 /* GOALPadJak2Runtime.framework in Frameworks */",
    "A74200000000000000000002 /* GOALPadJak2Runtime.framework in Embed Frameworks */ = {isa = PBXBuildFile; fileRef = F10600000000000000000002 /* GOALPadJak2Runtime.framework */; platformFilter = ios; settings = {ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy, ); }; };",
    "A74200000000000000000003 /* Embed Frameworks */ = {",
    "A74200000000000000000004 /* PBXTargetDependency */ = {",
    "A74100000000000000000001 /* Build Jak II import composer */ = {",
    '"$(SRCROOT)/Scripts/build-jak2-import-composer-apple.sh"',
    '"$(GOALPAD_JAK2_IMPORT_ARCHIVE)"',
    '"$(GOALPAD_JAK2_SOURCE_OBJECT_PACK_VERIFIER)"',
    "A74100000000000000000002 /* Stage Jak II importer resources */ = {",
    '"$(SRCROOT)/Scripts/stage-jak2-import-composer-resources.sh"',
    '"$(SRCROOT)/Scripts/stage-jak2-import-resources.sh"',
    '"$(GOALPAD_JAK2_PROJECT_RESOURCES)"',
    '"$(GOALPAD_JAK2_SOURCE_OBJECT_PACK_RESOURCES)"',
    "F11200000000000000000004 /* Stage Jak II importer resources */ = {",
    "F10100000000000000000004 /* GOALPadJak2Runtime.framework in Embed Frameworks */",
):
    require(marker in project, f"missing project contract: {marker}")

jak2_frameworks = object_block("A74000000000000000000005")
jak2_embed_frameworks = object_block("A74200000000000000000003")
jak2_runtime_dependency = object_block("A74200000000000000000004")
require("A74200000000000000000001 /* GOALPadJak2Runtime.framework in Frameworks */" in jak2_frameworks,
        "Eco Jak II Dev must link the Jak II runtime framework")
require("A74200000000000000000003 /* Embed Frameworks */" in jak2_target
        and "A74200000000000000000002 /* GOALPadJak2Runtime.framework in Embed Frameworks */" in jak2_embed_frameworks,
        "Eco Jak II Dev must embed the Jak II runtime framework")
require("A74200000000000000000004 /* PBXTargetDependency */" in jak2_target
        and "target = F10200000000000000000002 /* GOALPadJak2Runtime */;" in jak2_runtime_dependency,
        "Eco Jak II Dev must build the Jak II runtime framework before linking")

for marker in (
    "GOALPAD_HAS_JAK1_IMPORT_COMPOSER = 0",
    "GOALPAD_HAS_JAK2_IMPORT_COMPOSER = 0",
    "GOALPAD_JAK2_SOURCE_OBJECT_PACK_ROOT = $(SRCROOT)/build/jak2-source-object-pack",
    "GOALPAD_JAK2_IMPORT_BUILD_ROOT = $(DERIVED_FILE_DIR)/Jak2ImportComposer",
    "GOALPAD_JAK2_IMPORT_ARCHIVE = $(DERIVED_FILE_DIR)/Jak2ImportComposer/$(PLATFORM_NAME)/jak2-import-composer-apple/libjak2-import-composer-apple.a",
    "GOALPAD_JAK2_PROJECT_RESOURCES = $(GOALPAD_APP_RESOURCE_DESTINATION)/Jak2ProjectResources",
    "GOALPAD_JAK2_SOURCE_OBJECT_PACK_RESOURCES = $(GOALPAD_APP_RESOURCE_DESTINATION)/Jak2SourceObjectPack",
    "GOALPAD_HAS_JAK1_IMPORT_COMPOSER=$(GOALPAD_HAS_JAK1_IMPORT_COMPOSER)",
    "GOALPAD_HAS_JAK2_IMPORT_COMPOSER=$(GOALPAD_HAS_JAK2_IMPORT_COMPOSER)",
):
    require(marker in debug, f"missing Jak II Debug setting: {marker}")

for marker in (
    '#include "Jak2Dev-Debug.xcconfig"',
    "GOALPAD_HAS_JAK2_IMPORT_COMPOSER = 0",
    "GOALPAD_HAS_JAK2_IMPORT_COMPOSER[sdk=iphoneos*] = 1",
    "GOALPAD_HAS_JAK2_IMPORT_COMPOSER[sdk=iphonesimulator*] = 1",
    'OTHER_LDFLAGS[sdk=iphoneos*] = $(inherited) "$(GOALPAD_JAK2_IMPORT_ARCHIVE)"',
    'OTHER_LDFLAGS[sdk=iphonesimulator*] = $(inherited) "$(GOALPAD_JAK2_IMPORT_ARCHIVE)"',
):
    require(marker in release, f"missing Jak II Release setting: {marker}")

require(re.search(r'<LaunchAction\s+buildConfiguration = "Release"', scheme) is not None,
        "Eco Jak II Dev LaunchAction must use Release so raw-media preparation is available")

require('#include "Jak2Packaging.xcconfig"' in jak1_debug
        and '#include "Jak2Packaging.xcconfig"' in jak1_release,
        "the GOALPad target must receive only the shared Jak II resource paths")
require("GOALPAD_HAS_JAK2_IMPORT_COMPOSER" not in jak1_debug
        and "GOALPAD_HAS_JAK2_IMPORT_COMPOSER" not in jak1_release,
        "the GOALPad target must not compile the Jak II composer")

print("Jak II import target/config source checks passed")
PY
