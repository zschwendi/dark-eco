#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
swift "$root/Scripts/portrait-library-check.swift" "$root"
