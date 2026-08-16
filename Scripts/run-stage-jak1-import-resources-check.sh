#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
GOALPAD_IMPORT_RESOURCE_CHECK_GAME=jak1 \
  exec "$script_directory/run-stage-import-resources-check.sh" "$@"
