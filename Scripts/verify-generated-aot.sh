#!/bin/sh
# Verify that a generated whole-game AOT directory is complete and failure-free.

set -eu

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  echo "Usage: $0 GENERATED_AOT_DIRECTORY EXPECTED_OBJECT_COUNT [--manifest-only]" >&2
  exit 2
fi

directory=$1
expected_objects=$2
manifest="$directory/aot_boot_manifest.c"
coverage="$directory/coverage.tsv"
scan_files=true

fail() {
  echo "AOT preflight failed: $*" >&2
  exit 1
}

if [ "$#" -eq 3 ]; then
  [ "$3" = "--manifest-only" ] || fail "unknown option $3"
  scan_files=false
fi

case "$expected_objects" in
  ''|*[!0-9]*) fail "expected object count must be a positive integer" ;;
  0) fail "expected object count must be a positive integer" ;;
esac

[ -d "$directory" ] || fail "missing generated directory $directory"
[ -f "$manifest" ] || fail "missing $manifest"
[ -f "$coverage" ] || fail "missing $coverage; regenerate the AOT output"

if [ "$scan_files" = true ]; then
  expected_files=$((expected_objects + 1))
  c_files=$(find "$directory" -maxdepth 1 -type f -name '*.c' | wc -l | tr -d ' ')
  headers=$(find "$directory" -maxdepth 1 -type f -name '*.h' | wc -l | tr -d ' ')

  [ "$c_files" = "$expected_files" ] || \
    fail "expected $expected_files C files, found $c_files"
  [ "$headers" = "$expected_files" ] || \
    fail "expected $expected_files headers, found $headers"
fi

grep -Fqx "const int goal_aot_boot_file_count = $expected_objects;" "$manifest" || \
  fail "manifest does not declare $expected_objects objects"
grep -Fqx "const goal_aot_boot_entry goal_aot_boot_files[$expected_objects] = {" "$manifest" || \
  fail "manifest table does not contain $expected_objects entries"

temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/goalpad-aot.XXXXXX") || \
  fail "could not create a temporary verification directory"
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM

included_tags="$temporary_directory/included-tags"
entry_tags="$temporary_directory/entry-tags"
sed -n 's/^#include "\([A-Za-z0-9_]*\)_generated\.h"$/\1/p' "$manifest" | \
  sort > "$included_tags"
awk -F '"' '/^[[:space:]]*\{"goal_src\// { print $4 }' "$manifest" | \
  sort > "$entry_tags"

included_count=$(wc -l < "$included_tags" | tr -d ' ')
entry_count=$(wc -l < "$entry_tags" | tr -d ' ')
unique_included_count=$(sort -u "$included_tags" | wc -l | tr -d ' ')
unique_entry_count=$(sort -u "$entry_tags" | wc -l | tr -d ' ')

[ "$included_count" = "$expected_objects" ] || \
  fail "manifest includes $included_count generated headers, expected $expected_objects"
[ "$entry_count" = "$expected_objects" ] || \
  fail "manifest initializes $entry_count entries, expected $expected_objects"
[ "$unique_included_count" = "$expected_objects" ] || \
  fail "manifest contains duplicate generated-header tags"
[ "$unique_entry_count" = "$expected_objects" ] || \
  fail "manifest contains duplicate entry tags"
cmp -s "$included_tags" "$entry_tags" || \
  fail "manifest entry tags do not match its generated-header tags"

if [ "$scan_files" = true ]; then
  c_tags="$temporary_directory/c-tags"
  header_tags="$temporary_directory/header-tags"
  find "$directory" -maxdepth 1 -type f -name '*.c' ! -name 'aot_boot_manifest.c' \
    -exec basename {} .c \; | sort > "$c_tags"
  find "$directory" -maxdepth 1 -type f -name '*_generated.h' \
    -exec basename {} _generated.h \; | sort > "$header_tags"
  cmp -s "$included_tags" "$c_tags" || \
    fail "generated C corpus does not exactly match the manifest tags"
  cmp -s "$included_tags" "$header_tags" || \
    fail "generated header corpus does not exactly match the manifest tags"
fi

coverage_objects=$(awk -F '\t' '$1 == "TOTAL" { print $2; exit }' "$coverage")
emitted_functions=$(awk -F '\t' '$1 == "TOTAL" { print $3; exit }' "$coverage")
total_functions=$(awk -F '\t' '$1 == "TOTAL" { print $4; exit }' "$coverage")
native_functions=$(awk -F '\t' '$1 == "TOTALNATIVE" { print $2; exit }' "$coverage")
file_errors=$(awk -F '\t' '$1 == "FILEERRORS" { print $2; exit }' "$coverage")
function_errors=$(awk -F '\t' '$1 == "FAIL" { count++ } END { print count + 0 }' "$coverage")

case "$emitted_functions:$total_functions:$native_functions" in
  *[!0-9:]*) fail "coverage summary contains a non-numeric function count" ;;
  :*|*::*|*:) fail "coverage summary is missing a function count" ;;
esac

[ "$coverage_objects" = "$expected_objects" ] || \
  fail "coverage contains ${coverage_objects:-no} objects, expected $expected_objects"
[ "$file_errors" = 0 ] || fail "coverage reports ${file_errors:-unknown} source-file errors"
[ "$function_errors" = 0 ] || fail "coverage reports $function_errors unimplemented functions"
[ $((emitted_functions + native_functions)) -eq "$total_functions" ] || \
  fail "coverage is incomplete: $emitted_functions emitted + $native_functions native != $total_functions total"

echo "AOT preflight passed: $expected_objects objects, $emitted_functions emitted functions, $native_functions native functions"
