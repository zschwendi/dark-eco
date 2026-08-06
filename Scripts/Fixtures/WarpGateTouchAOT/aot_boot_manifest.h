#pragma once

#include "goalc/aot/goal_c_runtime.h"

typedef struct {
  const char* source;
  const char* tag;
  const goal_static_desc* statics;
  const int* static_count;
  const void* const* functions;
  const int* function_count;
  void (*link)(void);
} goal_aot_boot_entry;

extern const goal_aot_boot_entry goal_aot_boot_files[];
extern const int goal_aot_boot_file_count;
