#!/bin/sh
# Run deterministic Fit to Screen portrait geometry and iOS surface-framing checks.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
swift "$root/Scripts/presentation-layout-check.swift" "$root"
