#include "GOALPadRuntimeCore.hpp"

#include <array>
#include <cstring>

extern "C" std::uint64_t goalpad_aot_increment(std::uint64_t value);

namespace {

bool has_expected_arm64_code() {
#if defined(__arm64__)
  constexpr std::array<unsigned char, 8> expected = {
      0x00, 0x04, 0x00, 0x91, 0xc0, 0x03, 0x5f, 0xd6,
  };
  std::array<unsigned char, expected.size()> actual{};
  std::memcpy(actual.data(), reinterpret_cast<const void*>(&goalpad_aot_increment), actual.size());
  return actual == expected;
#else
  return false;
#endif
}

std::string architecture_name() {
#if defined(__arm64__)
  return "arm64";
#elif defined(__x86_64__)
  return "x86_64";
#else
  return "unsupported";
#endif
}

}  // namespace

namespace goalpad {

RuntimeStatus initialize_runtime(std::string storage_path) {
  constexpr std::uint64_t input = 41;

  RuntimeStatus status;
  status.architecture = architecture_name();
  status.storage_path = std::move(storage_path);
  status.workload_result = goalpad_aot_increment(input);
  status.workload_verified = status.workload_result == input + 1 && has_expected_arm64_code();
  status.message = status.workload_verified
                       ? "Signed ARM64 AOT workload verified"
                       : "Signed ARM64 AOT workload verification failed";
  return status;
}

}  // namespace goalpad
