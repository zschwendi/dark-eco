#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
GOALPAD_IMPORT_COMPOSER_GAME=jak2 \
  exec "$script_directory/build-jak1-import-composer-apple.sh" "$@"
