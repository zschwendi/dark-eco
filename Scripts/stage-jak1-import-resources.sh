#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
GOALPAD_IMPORT_RESOURCE_GAME=jak1 \
GOALPAD_IMPORT_RESOURCE_SCRIPT_NAME=stage-jak1-import-resources.sh \
  exec "$script_directory/stage-import-resources.sh" "$@"
