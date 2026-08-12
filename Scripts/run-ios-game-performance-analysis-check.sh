#!/bin/sh
set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
python3 "$script_directory/ios-game-performance-analysis-check.py"
