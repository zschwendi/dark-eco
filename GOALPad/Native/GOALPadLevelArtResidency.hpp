#pragma once

#include <algorithm>
#include <cstddef>
#include <string>
#include <vector>

namespace goalpad::level_art_residency {

struct Entry {
  std::string name;
  bool ok = false;              // Failed loads stay listed until a bounded retry is safe.
  int frames_since_wanted = 0;  // Zero while __pc-set-levels still names the level.
};

inline bool is_wanted(const std::vector<std::string>& wanted, const std::string& name) {
  return std::find(wanted.begin(), wanted.end(), name) != wanted.end();
}

inline std::vector<std::string> pressure_evictions(const std::vector<Entry>& loaded,
                                                   const std::vector<std::string>& wanted,
                                                   std::size_t resident_limit) {
  std::size_t resident_count = 0;
  for (const auto& entry : loaded) {
    resident_count += entry.ok ? 1 : 0;
  }

  std::size_t missing_wanted_count = 0;
  for (std::size_t wanted_index = 0; wanted_index < wanted.size(); ++wanted_index) {
    if (std::find(wanted.begin(), wanted.begin() + wanted_index, wanted[wanted_index]) !=
        wanted.begin() + wanted_index) {
      continue;
    }
    const bool resident = std::any_of(loaded.begin(), loaded.end(), [&](const auto& entry) {
      return entry.ok && entry.name == wanted[wanted_index];
    });
    missing_wanted_count += resident ? 0 : 1;
  }

  std::vector<std::string> victims;
  while (resident_count + missing_wanted_count > resident_limit) {
    const Entry* oldest = nullptr;
    for (const auto& entry : loaded) {
      if (!entry.ok || is_wanted(wanted, entry.name) ||
          std::find(victims.begin(), victims.end(), entry.name) != victims.end()) {
        continue;
      }
      if (!oldest || entry.frames_since_wanted > oldest->frames_since_wanted) {
        oldest = &entry;
      }
    }
    if (!oldest) {
      break;
    }
    victims.push_back(oldest->name);
    --resident_count;
  }
  return victims;
}

}  // namespace goalpad::level_art_residency
