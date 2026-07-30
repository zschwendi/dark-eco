#include <cstdint>

#if defined(__arm64__)
extern "C" __attribute__((naked, noinline)) std::uint64_t goalpad_aot_increment(std::uint64_t) {
  __asm__ volatile(
      "add x0, x0, #1\n"
      "ret\n");
}
#elif defined(__x86_64__)
extern "C" __attribute__((naked, noinline)) std::uint64_t goalpad_aot_increment(std::uint64_t) {
  __asm__ volatile(
      "leaq 1(%rdi), %rax\n"
      "retq\n");
}
#else
#error Unsupported architecture
#endif
