#!/bin/sh
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)

swift "$root/Scripts/promotion-frame-rate-check.swift" "$root"
"$root/Scripts/run-camera-timing-check.sh"
