#pragma once

#include <cstdint>
#include <string>

namespace goalpad {

struct RuntimeStatus {
  std::string architecture;
  std::string storage_path;
  std::uint64_t workload_result = 0;
  bool workload_verified = false;
  std::string message;
};

RuntimeStatus initialize_runtime(std::string storage_path);

}  // namespace goalpad
