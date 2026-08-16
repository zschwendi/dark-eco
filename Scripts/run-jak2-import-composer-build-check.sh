#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
GOALPAD_IMPORT_COMPOSER_CHECK_GAME=jak2 \
  exec "$script_directory/run-jak1-import-composer-build-check.sh" "$@"
