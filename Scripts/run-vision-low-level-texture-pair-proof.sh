#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/goalpad-low-level-texture-pair.XXXXXX")
trap 'rm -rf "$temporary"' EXIT HUP INT TERM
source_file="$root/Scripts/vision-low-level-texture-pair-proof.swift"

for forbidden in \
  DrawableQueue \
  presentOnSceneUpdate \
  CADisplayLink
do
  if rg -Fq "$forbidden" "$source_file"; then
    echo "LowLevelTexture proof must not use $forbidden" >&2
    exit 1
  fi
done

test "$(rg -c 'replace\(using: commandBuffer\)' "$source_file")" -eq 2
rg -Fq 'leftTexture.replace(using: commandBuffer)' "$source_file"
rg -Fq 'rightTexture.replace(using: commandBuffer)' "$source_file"
rg -Fq 'frameCount = 512' "$source_file"

macos_sdk=$(xcrun --sdk macosx --show-sdk-path)
swiftc -parse-as-library \
  -sdk "$macos_sdk" \
  -target arm64-apple-macosx26.5 \
  -module-cache-path "$temporary/macos-module-cache" \
  -swift-version 5 \
  -warnings-as-errors \
  "$source_file" \
  -o "$temporary/vision-low-level-texture-pair-proof"
"$temporary/vision-low-level-texture-pair-proof"

xros_sdk=$(xcrun --sdk xros --show-sdk-path)
swiftc -typecheck \
  -parse-as-library \
  -sdk "$xros_sdk" \
  -target arm64-apple-xros26.5 \
  -module-cache-path "$temporary/xros-module-cache" \
  -module-name GOALPadLowLevelTexturePairProof \
  -swift-version 5 \
  -warnings-as-errors \
  "$source_file"

echo "LowLevelTexture paired-update xros source typecheck passed"
