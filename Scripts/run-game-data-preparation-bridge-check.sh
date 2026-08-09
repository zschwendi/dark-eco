#!/bin/sh
# Compile the shared Objective-C++ bridge against exact synthetic Jak 1 and Jak II composer APIs.

set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/goalpad-preparation-bridge.XXXXXX")
trap 'rm -rf "$temporary_root"' EXIT HUP INT TERM
include_root=$temporary_root/include
mkdir -p "$include_root/decompiler/extractor"

cat >"$include_root/decompiler/extractor/jak1_import_composer.h" <<'HEADER'
#pragma once
#include <cstdint>
#include <filesystem>
#include <functional>
#include <optional>
#include <string>
#include <utility>
namespace jak1_import_composer {
struct Request {
  std::filesystem::path iso_path;
  std::filesystem::path source_object_pack_root;
  std::filesystem::path project_resource_root;
  std::filesystem::path candidate_root;
};
enum class Phase {
  validating_source_pack,
  extracting_iso,
  cataloging_retail,
  generating_data,
  preparing_fr3,
  generating_recipe,
  materializing_output,
  finalizing_candidate,
};
struct Progress {
  Phase phase = Phase::validating_source_pack;
  std::uint64_t completed = 0;
  std::uint64_t total = 0;
  std::uint64_t bytes_completed = 0;
  std::string current_item;
};
struct Options {
  std::function<bool()> should_cancel;
  std::function<void(const Progress&)> on_progress;
};
enum class ErrorCode {
  invalid_argument,
  cancelled,
  callback_failed,
  source_pack_failed,
  iso_open_failed,
  iso_validation_failed,
  unsupported_revision,
  graph_failed,
  retail_catalog_failed,
  generated_data_failed,
  fr3_failed,
  recipe_failed,
  candidate_create_failed,
  work_write_failed,
  insufficient_storage,
  materialization_failed,
  candidate_finalize_failed,
  candidate_cleanup_failed,
  allocation_failed,
  unexpected_failure,
};
struct Error {
  ErrorCode code = ErrorCode::invalid_argument;
  std::string message;
  std::optional<std::string> cleanup_error;
};
template <typename T> class Result {
 public:
  explicit operator bool() const;
  T take_value();
  const Error& error() const;
};
struct Summary {
  std::uint32_t archives_written = 0;
  std::uint32_t objects_written = 0;
  std::uint32_t flat_files_written = 0;
  std::uint32_t fr3_files_written = 0;
  std::uint64_t output_bytes = 0;
};
Result<Summary> compose(const Request&, const Options& = {});
}
HEADER

cat >"$include_root/decompiler/extractor/jak2_import_composer.h" <<'HEADER'
#pragma once
#include <cstdint>
#include <filesystem>
#include <functional>
#include <optional>
#include <string>
#include <utility>
namespace jak2_import_composer {
struct Request {
  std::filesystem::path iso_path;
  std::filesystem::path source_object_pack_root;
  std::filesystem::path project_resource_root;
  std::filesystem::path candidate_root;
};
enum class Phase {
  validating_source_pack,
  validating_project_resources,
  extracting_iso,
  generating_data,
  preparing_fr3,
  generating_recipe,
  materializing_output,
  finalizing_candidate,
};
struct Progress {
  Phase phase = Phase::validating_source_pack;
  std::uint64_t completed = 0;
  std::uint64_t total = 0;
  std::uint64_t bytes_completed = 0;
  std::string current_item;
};
struct Options {
  std::function<bool()> should_cancel;
  std::function<void(const Progress&)> on_progress;
};
enum class ErrorCode {
  invalid_argument,
  cancelled,
  callback_failed,
  source_pack_failed,
  project_resources_failed,
  iso_open_failed,
  iso_validation_failed,
  unsupported_revision,
  graph_failed,
  generated_data_failed,
  fr3_failed,
  recipe_failed,
  candidate_create_failed,
  work_write_failed,
  insufficient_storage,
  materialization_failed,
  candidate_finalize_failed,
  candidate_cleanup_failed,
  allocation_failed,
  unexpected_failure,
};
struct Error {
  ErrorCode code = ErrorCode::invalid_argument;
  std::string message;
  std::optional<std::filesystem::path> preserved_candidate_root;
  std::optional<std::string> cleanup_error;
};
template <typename T> class Result {
 public:
  explicit operator bool() const;
  T take_value();
  const Error& error() const;
};
struct Summary {
  std::uint32_t archives_written = 0;
  std::uint32_t objects_written = 0;
  std::uint32_t flat_files_written = 0;
  std::uint32_t fr3_files_written = 0;
  std::uint64_t output_bytes = 0;
};
Result<Summary> compose(const Request&, const Options& = {});
}
HEADER

cat >"$temporary_root/public-enum-contract.mm" <<'SOURCE'
#import "GOALPadGameDataPreparationBridge.h"
static_assert(GOALPadGameDataPreparationErrorAlreadyStarted == 21);
static_assert(GOALPadGameDataPreparationErrorProjectResourcesFailed == 22);
static_assert(GOALPadGameDataPreparationPhaseFinalizingCandidate == 8);
static_assert(GOALPadGameDataPreparationPhaseValidatingProjectResources == 9);
SOURCE

sdk=$(xcrun --sdk macosx --show-sdk-path)
compiler=$(xcrun --sdk macosx --find clang++)
set -- "$compiler" -isysroot "$sdk" -std=c++20 -fblocks -fsyntax-only \
  -Wall -Wextra -Wswitch-enum -Werror -x objective-c++ \
  -I "$include_root" -I "$root/GOALPad/Native"

"$@" "$temporary_root/public-enum-contract.mm"
"$@" -DGOALPAD_HAS_JAK1_IMPORT_COMPOSER=1 \
  -DGOALPAD_HAS_JAK2_IMPORT_COMPOSER=0 \
  "$root/GOALPad/Native/GOALPadGameDataPreparationBridge.mm"
"$@" -DGOALPAD_HAS_JAK1_IMPORT_COMPOSER=0 \
  -DGOALPAD_HAS_JAK2_IMPORT_COMPOSER=1 \
  "$root/GOALPad/Native/GOALPadGameDataPreparationBridge.mm"

if "$@" -DGOALPAD_HAS_JAK1_IMPORT_COMPOSER=1 \
  -DGOALPAD_HAS_JAK2_IMPORT_COMPOSER=1 \
  "$root/GOALPad/Native/GOALPadGameDataPreparationBridge.mm" \
  >"$temporary_root/mutual.out" 2>"$temporary_root/mutual.err"; then
  echo "the bridge compiled with both import composers enabled" >&2
  exit 1
fi
grep -F "GOALPad must select exactly one import composer" "$temporary_root/mutual.err" >/dev/null

echo "game-data preparation bridge syntax checks passed"
