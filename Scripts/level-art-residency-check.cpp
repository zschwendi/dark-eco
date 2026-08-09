#include "GOALPad/Native/GOALPadLevelArtResidency.hpp"

#include <algorithm>
#include <cstdio>
#include <string>
#include <vector>

namespace {

using goalpad::level_art_residency::Entry;
using goalpad::level_art_residency::pressure_evictions;

int failures = 0;

void check(bool condition, const char* description) {
  if (condition) {
    std::printf("ok   %s\n", description);
  } else {
    std::printf("FAIL %s\n", description);
    ++failures;
  }
}

bool contains(const std::vector<Entry>& loaded, const std::string& name, bool ok) {
  return std::any_of(loaded.begin(), loaded.end(),
                     [&](const auto& entry) { return entry.name == name && entry.ok == ok; });
}

std::vector<Entry> apply_request(std::vector<Entry> loaded, const std::vector<std::string>& wanted,
                                 std::size_t resident_limit, bool evict_before_load) {
  if (evict_before_load) {
    for (const auto& victim : pressure_evictions(loaded, wanted, resident_limit)) {
      loaded.erase(std::remove_if(loaded.begin(), loaded.end(),
                                  [&](const auto& entry) { return entry.name == victim; }),
                   loaded.end());
    }
  }

  for (const auto& name : wanted) {
    if (std::any_of(loaded.begin(), loaded.end(),
                    [&](const auto& entry) { return entry.name == name; })) {
      continue;
    }
    const auto resident_count =
        std::count_if(loaded.begin(), loaded.end(), [](const auto& entry) { return entry.ok; });
    loaded.push_back({name, static_cast<std::size_t>(resident_count) < resident_limit, 0});
  }
  return loaded;
}

}  // namespace

int main() {
  const std::vector<Entry> full_session = {
      {"oldest", true, 120}, {"recent", true, 10}, {"source", true, 0}};
  const std::vector<std::string> travel = {"source", "destination"};

  const auto legacy = apply_request(full_session, travel, 3, false);
  check(contains(legacy, "destination", false),
        "loading before eviction memoizes a failed destination at the resident "
        "limit");

  const auto planned = pressure_evictions(full_session, travel, 3);
  check(planned == std::vector<std::string>{"oldest"},
        "pressure planning removes the oldest unwanted level before travel");

  const auto reconciled = apply_request(full_session, travel, 3, true);
  check(!contains(reconciled, "oldest", true) && contains(reconciled, "destination", true),
        "preflight eviction leaves capacity for first-attempt destination art");
  check(contains(reconciled, "source", true) && contains(reconciled, "recent", true),
        "preflight eviction preserves wanted and younger cached art");

  const std::vector<Entry> below_limit = {{"source", true, 0}, {"cached", true, 60}};
  check(pressure_evictions(below_limit, travel, 3).empty(),
        "one free resident slot preserves the grace cache");

  const std::vector<Entry> failed_cache = {
      {"oldest", true, 120}, {"source", true, 0}, {"destination", false, 0}};
  check(pressure_evictions(failed_cache, travel, 3).empty(),
        "failed entries do not consume resident capacity");

  const std::vector<Entry> all_wanted = {{"a", true, 0}, {"b", true, 0}, {"c", true, 0}};
  check(pressure_evictions(all_wanted, {"a", "b", "c", "d"}, 3).empty(),
        "pressure planning never evicts wanted art when no safe victim exists");

  const std::vector<Entry> two_old = {
      {"oldest", true, 120}, {"older", true, 80}, {"source", true, 0}};
  check(pressure_evictions(two_old, {"source", "destination-a", "destination-b"}, 3) ==
            std::vector<std::string>({"oldest", "older"}),
        "pressure planning releases enough unwanted levels for every missing "
        "destination");

  if (failures) {
    std::printf("%d level-art residency checks failed\n", failures);
    return 1;
  }
  std::printf("all level-art residency checks passed\n");
  return 0;
}
