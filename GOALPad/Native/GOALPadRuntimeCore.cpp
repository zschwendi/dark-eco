#include "GOALPadRuntimeCore.hpp"

#include <array>
#include <cstring>

extern "C" std::uint64_t goalpad_aot_constant_42();

namespace {

bool has_expected_opengoal_arm64_code() {
#if defined(__arm64__)
  constexpr std::array<unsigned char, 8> expected = {
      0x40, 0x05, 0x80, 0xd2, 0xc0, 0x03, 0x5f, 0xd6,
  };
  std::array<unsigned char, expected.size()> actual{};
  std::memcpy(actual.data(), reinterpret_cast<const void*>(&goalpad_aot_constant_42), actual.size());
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
  RuntimeStatus status;
  status.architecture = architecture_name();
  status.storage_path = std::move(storage_path);
  status.workload_result = goalpad_aot_constant_42();
  status.workload_verified =
      status.workload_result == 42 && has_expected_opengoal_arm64_code();
  status.message = status.workload_verified
                       ? "Signed ARM64 OpenGOAL AOT workload verified"
                       : "Signed ARM64 OpenGOAL AOT workload verification failed";
  return status;
}

}  // namespace goalpad
