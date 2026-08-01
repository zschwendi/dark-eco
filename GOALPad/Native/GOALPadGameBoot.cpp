#include "GOALPadGameBoot.hpp"

#include "GOALPadEngineSeams.h"

#include <chrono>
#include <climits>
#include <cstring>
#include <exception>
#include <os/log.h>
#include <sys/stat.h>

#if GOALPAD_HAVE_GAME_BOOT
#include "common/listener_common.h"
#include "common/symbols.h"

#include "game/kernel/common/kernel_types.h"
#include "game/kernel/common/klink.h"
#include "game/kernel/common/kprint.h"
#include "game/kernel/common/kscheme.h"
#include "game/kernel/core/aot_loader.h"
#include "game/kernel/core/dgo_loader.h"
#include "game/kernel/core/dma_capture.h"
#include "game/kernel/jak1/klisten.h"
#include "game/kernel/jak1/kscheme.h"
#include "game/runtime.h"
#include "game/sce/sif_ee.h"

extern "C" {
#include "aot_boot_manifest.h"
}
#endif

namespace {

os_log_t boot_log() {
  static os_log_t log = os_log_create("com.zephyrstudiosllc.GOALPad", "Engine");
  return log;
}

#if GOALPAD_HAVE_GAME_BOOT

bool g_booted = false;
std::uint64_t g_frames = 0;
Ptr<jak1::Symbol> g_dispatcher;

/*! Everything GOAL printed since the last drain, into the app's log. */
void drain_goal_print_buffer() {
  const char* printed = Ptr<char>(PrintBufArea.offset + sizeof(ListenerMessageHeader)).c();
  if (printed[0]) {
    os_log_info(boot_log(), "GOAL: %{public}s", printed);
    clear_print();
  }
}

/*! The DGO object name for a GOAL source: its base name without the extension. */
std::string object_name_of(const char* source) {
  std::string path = source;
  const auto slash = path.find_last_of('/');
  if (slash != std::string::npos) {
    path = path.substr(slash + 1);
  }
  const auto dot = path.find_last_of('.');
  if (dot != std::string::npos) {
    path = path.substr(0, dot);
  }
  return path;
}

/*! Tell the DGO loader which native translation unit stands in for each object it will meet. */
void register_aot_objects() {
  for (int i = 0; i < goal_aot_boot_file_count; i++) {
    const auto& entry = goal_aot_boot_files[i];
    goal_aot_object_file file = {entry.tag,      entry.statics,         *entry.static_count,
                                 entry.functions, *entry.function_count, entry.link};
    goal_aot_register_object(object_name_of(entry.source).c_str(), &file);
  }
}

/*!
 * GAME.CGO is the release build's union of ENGINE.CGO, ART.CGO and COMMON.CGO, which do not exist
 * as files on the disc. The C kernel records that by putting their names in `*kernel-packages*`
 * after loading GAME.CGO (jak1::InitMachineScheme), so `alloc-levels!` finds them already loaded
 * and asks for nothing. Without it the level system tries to load ART.CGO and fails.
 */
void record_packages_in_game_cgo() {
  using namespace jak1_symbols;
  for (const char* package : {"engine", "art", "common"}) {
    jak1::kernel_packages->value =
        jak1::new_pair(s7.offset + FIX_SYM_GLOBAL_HEAP, *((s7 + FIX_SYM_PAIR_TYPE).cast<u32>()),
                       jak1::make_string_from_c(package), jak1::kernel_packages->value);
  }
}

/*!
 * The few machine-layer functions the app can answer for itself.
 *
 * `game/kernel/core/` deliberately has no machine layer: `goal_kernel_core_stub_machine_layer`
 * puts a stub in each of its 117 symbols that names itself once and returns 0. For a predicate
 * that is wrong rather than merely absent - GOAL's `#f` is `s7`, not 0, so a stub answers "yes" to
 * every question - and the PC settings loader believes it: it opens a settings file that is not
 * there, `file-stream-open` hands it 0 back, and the next field read faults in the guard page.
 *
 * The app is the host, so the app answers. Only what it can answer honestly is here.
 */
u64 goal_false() {
  return s7.offset;
}

u64 goal_bool(bool value) {
  return value ? s7.offset + jak1_symbols::FIX_SYM_TRUE : s7.offset;
}

/*! Does this file exist? Every name is resolved under the player's data directory, which is the
 *  only place the app can read. */
u64 app_pc_filepath_exists(u32 filepath) {
  const char* name = Ptr<String>(filepath).c()->data();
  char resolved[PATH_MAX] = {};
  if (goal_kernel_core_resolve_data_path(name, resolved, sizeof(resolved)) !=
      GOAL_KERNEL_CORE_OK) {
    return goal_false();
  }
  struct stat info = {};
  return goal_bool(stat(resolved, &info) == 0);
}

/*
 * `file-stream-*`, copied from game/kernel/{common,jak1}/kmachine.cpp for the same reason pad.cpp
 * copies `CPadOpen`: those translation units are the desktop machine layer and are not in this
 * library. The file calls underneath them are `ee::sceOpen` and friends in
 * game/kernel/core/desktop_seams.cpp, which resolve every name under the configured data
 * directory.
 *
 * A stub is not good enough here. `(method new file-stream)` returns whatever `file-stream-open`
 * returns, so a stub hands GOAL a null stream and the very next field read - `file-stream-valid?`
 * - faults in the guard page. Upstream always returns the stream and records the failure in it,
 * which is what lets `pc-settings` say "could not be loaded, using defaults" instead of crashing.
 */
u64 app_file_stream_open(u64 fs, u64 name, u64 mode) {
  auto* stream = Ptr<FileStream>(fs).c();
  stream->mode = mode;
  stream->name = name;
  stream->flags = 0;
  const bool reading = std::strcmp(jak1::info(Ptr<jak1::Symbol>(mode))->str->data(), "read") == 0;
  stream->file = reading ? ee::sceOpen(Ptr<String>(name)->data(), SCE_RDONLY)
                         : ee::sceOpen(Ptr<String>(name)->data(), SCE_TRUNC | SCE_CREAT | SCE_WRONLY);
  return fs;
}

u64 app_file_stream_close(u64 fs) {
  auto* stream = Ptr<FileStream>(fs).c();
  if ((stream->flags ^ 1) & 1) {
    ee::sceClose(stream->file);
    stream->file = -1;
  }
  stream->flags = 0;
  return fs;
}

s32 app_file_stream_length(u64 fs) {
  auto* stream = Ptr<FileStream>(fs).c();
  if ((stream->flags ^ 1) & 1) {
    const auto end = ee::sceLseek(stream->file, 0, SCE_SEEK_END);
    const auto reset = ee::sceLseek(stream->file, 0, SCE_SEEK_SET);
    if (end < 0 || reset < 0) {
      stream->flags |= 1;
    }
    return end;
  }
  return 0;
}

s32 app_file_stream_seek(u64 fs, s32 offset, s32 where) {
  auto* stream = Ptr<FileStream>(fs).c();
  if ((stream->flags ^ 1) & 1) {
    const s32 result = ee::sceLseek(stream->file, offset, where);
    if (result < 0) {
      stream->flags |= 1;
    }
    return result;
  }
  return -1;
}

s32 app_file_stream_read(u64 fs, u64 buffer, s32 size) {
  auto* stream = Ptr<FileStream>(fs).c();
  if ((stream->flags ^ 1) & 1) {
    const s32 result = ee::sceRead(stream->file, Ptr<u8>(buffer).c(), size);
    if (result < 0) {
      stream->flags |= 1;
    }
    return result;
  }
  return -1;
}

s32 app_file_stream_write(u64 fs, u64 buffer, s32 size) {
  auto* stream = Ptr<FileStream>(fs).c();
  if ((stream->flags ^ 1) & 1) {
    const s32 result = ee::sceWrite(stream->file, Ptr<u8>(buffer).c(), size);
    if (result < 0) {
      stream->flags |= 1;
    }
    return result;
  }
  return -1;
}

void install_app_machine_functions() {
  jak1::make_function_symbol_from_c("pc-filepath-exists?", (void*)app_pc_filepath_exists);
  // The app writes nothing outside its own container, so it does not make directories for GOAL.
  jak1::make_function_symbol_from_c("pc-mkdir-file-path", (void*)goal_false);

  jak1::make_function_symbol_from_c("file-stream-open", (void*)app_file_stream_open);
  jak1::make_function_symbol_from_c("file-stream-close", (void*)app_file_stream_close);
  jak1::make_function_symbol_from_c("file-stream-length", (void*)app_file_stream_length);
  jak1::make_function_symbol_from_c("file-stream-seek", (void*)app_file_stream_seek);
  jak1::make_function_symbol_from_c("file-stream-read", (void*)app_file_stream_read);
  jak1::make_function_symbol_from_c("file-stream-write", (void*)app_file_stream_write);
}

goalpad::BootStatus failure(std::string message) {
  goalpad::BootStatus status;
  status.message = std::move(message);
  os_log_error(boot_log(), "Boot failed: %{public}s", status.message.c_str());
  return status;
}

#endif  // GOALPAD_HAVE_GAME_BOOT

}  // namespace

namespace goalpad {

#if GOALPAD_HAVE_GAME_BOOT

BootStatus boot_game() noexcept {
  try {
    const auto started = std::chrono::steady_clock::now();
    BootStatus status;

    if (!goal_kernel_core_is_initialized()) {
      return failure("The GOAL kernel is not running.");
    }
    if (g_booted) {
      return failure("The game is already booted.");
    }

    register_aot_objects();

    const u32 boot_flags = LINK_FLAG_OUTPUT_LOAD | LINK_FLAG_EXECUTE | LINK_FLAG_PRINT_LOGIN;
    goal_dgo_load_stats stats = {};

    // InitHeapAndSymbol: the GOAL kernel.
    if (goal_dgo_load("KERNEL", boot_flags, 0x400000, &stats) != GOAL_KERNEL_CORE_OK) {
      drain_goal_print_buffer();
      return failure(std::string("KERNEL.CGO: ") + goal_dgo_last_error());
    }
    drain_goal_print_buffer();
    status.kernel_objects = stats.objects;

    goal_kernel_core_lookup("*kernel-version*", nullptr, &status.kernel_version);
    if (!status.kernel_version) {
      return failure("The GOAL kernel did not set *kernel-version*.");
    }

    // InitListener, then the machine layer. Almost none of it is here; the stubs name themselves
    // the first time GOAL calls one. The pad, the loader RPCs and the sound RPC are real and
    // replace their stubs.
    jak1::InitListener();
    goal_kernel_core_stub_machine_layer(0);
    install_app_machine_functions();
    // Before GAME.CGO: pad.gc's top level builds `*cpad-list*`, which calls `cpad-open`.
    if (goal_pad_install() != GOAL_KERNEL_CORE_OK) {
      return failure("Could not install the controller seam.");
    }
    goal_dgo_install_goal_loader();
    goal_gfx_dma_install();
    // gsound.gc's top level loads the common sound banks while GAME.CGO is still being read, so
    // 989snd has to be answering the sound RPC before that load starts.
    if (goal_sound_install() == GOAL_KERNEL_CORE_OK) {
      status.sound_installed = true;
      status.sound_sample_rate = goal_sound_sample_rate();
    } else {
      os_log_error(boot_log(), "989snd did not start: %{public}s", goal_sound_last_error());
    }

    jak1::intern_from_c("*kernel-boot-message*")->value =
        jak1::intern_from_c(DebugBootMessage).offset;
    jak1::intern_from_c("*kernel-boot-mode*")->value = jak1::intern_from_c("boot").offset;
    jak1::intern_from_c("*kernel-boot-level*")->value = jak1::intern_from_c(DebugBootLevel).offset;

    // InitMachineScheme's DiskBoot path: the engine and the game.
    if (goal_dgo_load("GAME", boot_flags, 0x400000, &stats) != GOAL_KERNEL_CORE_OK) {
      drain_goal_print_buffer();
      return failure(std::string("GAME.CGO stopped after ") + std::to_string(stats.objects) +
                     " objects: " + goal_dgo_last_error());
    }
    drain_goal_print_buffer();
    status.game_objects = stats.objects;
    status.code_objects = stats.code_objects;
    status.data_objects = stats.data_objects;
    record_packages_in_game_cgo();

    // The last thing InitMachineScheme does. `play` allocates the level heaps and drives the whole
    // title-level load itself, through GOAL's own loader.
    jak1::call_goal_function_by_name("play");
    drain_goal_print_buffer();
    status.played = true;

    g_dispatcher = jak1::find_symbol_from_c("kernel-dispatcher");
    if (!g_dispatcher.offset || !g_dispatcher->value) {
      return failure("kernel-dispatcher holds nothing.");
    }

    goal_kernel_core_state state = {};
    goal_kernel_core_get_state(&state);
    status.global_heap_used_bytes = state.global_heap_used_bytes;
    status.symbol_count = state.symbol_count;

    g_booted = true;
    g_frames = 0;
    status.booted = true;
    status.seconds =
        std::chrono::duration<double>(std::chrono::steady_clock::now() - started).count();
    status.message = "Jak 1 booted: " + std::to_string(status.kernel_objects) +
                     " objects from KERNEL.CGO and " + std::to_string(status.game_objects) +
                     " from GAME.CGO (" + std::to_string(status.code_objects) + " code, " +
                     std::to_string(status.data_objects) + " data).";
    os_log(boot_log(), "%{public}s Heap %u bytes, %d symbols, %.1f s.", status.message.c_str(),
           status.global_heap_used_bytes, status.symbol_count, status.seconds);
    return status;
  } catch (const std::exception& e) {
    return failure(std::string("boot threw: ") + e.what());
  } catch (...) {
    return failure("boot threw an unknown exception");
  }
}

bool run_frame() noexcept {
  if (!g_booted) {
    return false;
  }
  call_goal_on_stack(Ptr<Function>(g_dispatcher->value), goal_kernel_stack_top(), s7.offset,
                     g_ee_main_mem);
  drain_goal_print_buffer();
  // The overlord's vblank work: the music fade, and the `sound-iop-info` block written back to the
  // EE. A frame of the game is a frame of sound.
  goal_sound_frame();
  g_frames++;
  return true;
}

FrameChainStats frame_chain_stats() noexcept {
  goal_gfx_dma_stats stats = {};
  goal_gfx_dma_get_stats(&stats);
  FrameChainStats out;
  out.chains = stats.chains;
  out.last_payload_bytes = stats.last_payload_bytes;
  out.largest_payload_bytes = stats.largest_payload_bytes;
  out.last_texture_uploads = stats.last_texture_uploads;
  return out;
}

void reset_game() noexcept {
  g_booted = false;
  g_frames = 0;
  g_dispatcher = Ptr<jak1::Symbol>();
}

std::uint64_t frames_run() noexcept {
  return g_frames;
}

bool game_is_booted() noexcept {
  return g_booted;
}

#else  // GOALPAD_HAVE_GAME_BOOT

BootStatus boot_game() noexcept {
  BootStatus status;
  status.message =
      "This build has no ahead-of-time Jak 1 code. Run Scripts/generate-jak1-aot.sh and build "
      "again.";
  os_log_error(boot_log(), "%{public}s", status.message.c_str());
  return status;
}

bool run_frame() noexcept {
  return false;
}

FrameChainStats frame_chain_stats() noexcept {
  return {};
}

void reset_game() noexcept {}

std::uint64_t frames_run() noexcept {
  return 0;
}

bool game_is_booted() noexcept {
  return false;
}

#endif  // GOALPAD_HAVE_GAME_BOOT

}  // namespace goalpad
