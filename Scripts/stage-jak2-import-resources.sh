#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
GOALPAD_IMPORT_RESOURCE_GAME=jak2 \
GOALPAD_IMPORT_RESOURCE_SCRIPT_NAME=stage-jak2-import-resources.sh \
  exec "$script_directory/stage-import-resources.sh" "$@"
