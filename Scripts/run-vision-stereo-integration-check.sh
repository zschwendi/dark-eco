#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/goalpad-vision-stereo-integration.XXXXXX")
trap 'rm -rf "$temporary"' EXIT HUP INT TERM

swiftc "$root/Scripts/vision-stereo-integration-check.swift" \
  -o "$temporary/vision-stereo-integration-check"
"$temporary/vision-stereo-integration-check" "$root"
