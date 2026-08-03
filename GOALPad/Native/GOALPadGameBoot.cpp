#include "GOALPadGameBoot.hpp"

#include "GOALPadDisplayClock.hpp"
#include "GOALPadEngineSeams.h"
#include "GOALPadMetalHost.hpp"

#include <chrono>
#include <climits>
#include <cstring>
#include <exception>
#include <os/log.h>
#include <sys/stat.h>
#include <TargetConditionals.h>

#if GOALPAD_HAVE_GAME_BOOT
#include "common/listener_common.h"
#include "common/goal_constants.h"
#include "common/symbols.h"

#include "game/kernel/common/kernel_types.h"
#include "game/kernel/common/klink.h"
#include "game/kernel/common/kprint.h"
#include "game/kernel/common/kscheme.h"
#include "game/kernel/core/aot_loader.h"
#include "game/kernel/core/dgo_loader.h"
#include "game/kernel/core/dma_capture.h"
#include "game/kernel/core/kernel_game.h"
#include "game/graphics/pipelines/metal/metal_camera_trace.h"
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
  static os_log_t log = os_log_create("com.zephyrstudiosllc.eco", "Engine");
  return log;
}

#if GOALPAD_HAVE_GAME_BOOT

bool g_booted = false;
std::uint64_t g_frames = 0;
Ptr<jak1::Symbol> g_dispatcher;
int32_t* g_math_camera = nullptr;
int32_t* g_camera_master = nullptr;
int32_t* g_camera_combiner = nullptr;
std::uint32_t g_camera_master_type = 0;
std::uint32_t g_camera_slave_type = 0;
std::uint32_t g_camera_combiner_type = 0;
#if TARGET_OS_IOS || TARGET_OS_VISION
int32_t* g_timer_reset_value = nullptr;
int32_t* g_host_display_time_ratio = nullptr;
goalpad::DisplayClock g_display_clock;
#endif

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

goalpad::camera_correction_trace::FrameSnapshot current_camera_correction_snapshot() {
  using namespace goalpad::camera_correction_trace;

  FrameSnapshot out;
  out.engine_frame_id = g_frames + 1;
#if TARGET_OS_IOS || TARGET_OS_VISION
  if (g_host_display_time_ratio) {
    static_assert(sizeof(out.display_time_ratio) == sizeof(*g_host_display_time_ratio));
    std::memcpy(&out.display_time_ratio, g_host_display_time_ratio,
                sizeof(out.display_time_ratio));
  }
#endif
  if (!g_camera_master || !g_ee_main_mem) {
    return out;
  }

  std::size_t master_bytes = 0;
  const auto master_offset = static_cast<std::uint32_t>(*g_camera_master);
  const void* master_object = checked_goal_object(
      g_ee_main_mem, EE_MAIN_MEM_SIZE, EE_MAIN_MEM_LOW_PROTECT, master_offset,
      g_camera_master_type, jak1_layout::kMasterRequiredObjectBytes, &master_bytes);
  MasterSnapshot master;
  if (!master_object ||
      !try_read_jak1_master(master_object, master_bytes, s7.offset, &master)) {
    return out;
  }

  out.valid = true;
  out.num_slaves = master.num_slaves;
  out.being_attacked = master.being_attacked;
  out.target_position = master.target_position;
  out.adjusted_target_position = master.adjusted_target_position;
  for (std::size_t slot = 0; slot < out.slaves.size(); ++slot) {
    if (slot >= static_cast<std::size_t>(master.num_slaves)) {
      continue;
    }
    std::uint32_t slave_offset = 0;
    if (!resolve_goal_ppointer(g_ee_main_mem, EE_MAIN_MEM_SIZE, EE_MAIN_MEM_LOW_PROTECT,
                               s7.offset, master.slave_offsets[slot], &slave_offset)) {
      continue;
    }
    std::size_t slave_bytes = 0;
    const void* slave_object = checked_goal_object(
        g_ee_main_mem, EE_MAIN_MEM_SIZE, EE_MAIN_MEM_LOW_PROTECT, slave_offset,
        g_camera_slave_type,
        jak1_layout::kSlaveRequiredObjectBytes, &slave_bytes);
    if (slave_object) {
      try_read_jak1_slave(slave_object, slave_bytes, &out.slaves[slot]);
    }
  }

  if (g_camera_combiner) {
    std::size_t combiner_bytes = 0;
    const auto combiner_offset = static_cast<std::uint32_t>(*g_camera_combiner);
    const void* combiner_object = checked_goal_object(
        g_ee_main_mem, EE_MAIN_MEM_SIZE, EE_MAIN_MEM_LOW_PROTECT, combiner_offset,
        g_camera_combiner_type, jak1_layout::kCombinerRequiredObjectBytes,
        &combiner_bytes);
    if (combiner_object) {
      try_read_jak1_combiner(combiner_object, combiner_bytes, &out.combiner);
    }
  }
  return out;
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
    // The renderer, in place of the machine layer's graphics stubs. It has to be answering before
    // GAME.CGO is read: the game uploads texture pages while it loads, and a page that arrives
    // with no pool behind it is a texture missing for the rest of the session.
    std::string renderer_error;
    if (goalpad::metal_host_start(&renderer_error) && goalpad::metal_host_install_seam()) {
      status.renderer_installed = true;
      char fr3[PATH_MAX] = {};
      if (goal_kernel_core_resolve_data_path("fr3", fr3, sizeof(fr3)) == GOAL_KERNEL_CORE_OK) {
        goalpad::metal_host_set_level_art_directory(fr3);
      }
    } else {
      os_log_error(boot_log(), "The Metal renderer did not start: %{public}s",
                   renderer_error.c_str());
      // Nothing will be drawn, but a frame still builds a chain, so measure it rather than
      // silently dropping it.
      goal_gfx_dma_install();
    }
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

#if TARGET_OS_IOS || TARGET_OS_VISION
    // The AOT new-bones path flattened Jak on physical iPad, while the existing MIPS2C producer
    // preserved the correct volumetric pose. Keep this iOS and visionOS compatibility fallback at
    // the producer boundary until new-bones reaches physical-device parity; rendering and game
    // data stay shared.
    goal_game_set_symbol_value("*use-new-bones*", goal_game_false_offset());
    os_log(boot_log(), "Using the MIPS2C bones matrix producer for iOS/visionOS compatibility.");
#endif

    // The last thing InitMachineScheme does. `play` allocates the level heaps and drives the whole
    // title-level load itself, through GOAL's own loader.
    jak1::call_goal_function_by_name("play");
    drain_goal_print_buffer();
    status.played = true;

    uint32_t math_camera = 0;
    if (goal_game_find_symbol("*math-camera*", &math_camera)) {
      g_math_camera = goal_game_symbol_slot("*math-camera*");
    } else {
      os_log_error(boot_log(), "GAME.CGO did not define *math-camera*; camera trace unavailable.");
    }

    const bool camera_diagnostic_symbols =
        goal_game_find_symbol("*camera*", nullptr) &&
        goal_game_find_symbol("*camera-combiner*", nullptr) &&
        goal_game_find_symbol("camera-master", &g_camera_master_type) &&
        goal_game_find_symbol("camera-slave", &g_camera_slave_type) &&
        goal_game_find_symbol("camera-combiner", &g_camera_combiner_type) &&
        g_camera_master_type && g_camera_slave_type && g_camera_combiner_type;
    if (camera_diagnostic_symbols) {
      g_camera_master = goal_game_symbol_slot("*camera*");
      g_camera_combiner = goal_game_symbol_slot("*camera-combiner*");
    } else {
      g_camera_master_type = 0;
      g_camera_slave_type = 0;
      g_camera_combiner_type = 0;
      os_log_error(boot_log(),
                   "GAME.CGO camera process types are unavailable; constrained-camera trace "
                   "disabled.");
    }

#if TARGET_OS_IOS || TARGET_OS_VISION
    uint32_t timer_reset_value = 0;
    if (!goal_game_find_symbol("*timer-reset-value*", &timer_reset_value)) {
      return failure("GAME.CGO did not define *timer-reset-value*.");
    }
    g_timer_reset_value = goal_game_symbol_slot("*timer-reset-value*");

    uint32_t host_display_time_ratio = 0;
    if (!goal_game_find_symbol("*host-display-time-ratio*", &host_display_time_ratio)) {
      return failure("GAME.CGO did not define *host-display-time-ratio*.");
    }
    g_host_display_time_ratio = goal_game_symbol_slot("*host-display-time-ratio*");
    g_display_clock.reset();
#endif

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

bool run_frame(double target_presentation_time) noexcept {
  if (!g_booted) {
    return false;
  }
#if TARGET_OS_IOS || TARGET_OS_VISION
  // `display-frame-start` consumes this value at the same boundary as its upstream timer result,
  // before the next frame's process and camera updates. CADisplayLink's target timestamp measures
  // display cadence; callback workload does not move the ratio onto the wrong game frame.
  const float display_time_ratio =
      static_cast<float>(g_display_clock.advance(target_presentation_time));
  int32_t display_time_ratio_bits = 0;
  static_assert(sizeof(display_time_ratio_bits) == sizeof(display_time_ratio));
  std::memcpy(&display_time_ratio_bits, &display_time_ratio, sizeof(display_time_ratio_bits));
  *g_host_display_time_ratio = display_time_ratio_bits;

  // CADisplayLink already owns the wait between game frames. Exclude that outside wait from
  // GOAL's timer. It remains a valid fallback if the host ratio is disabled in GOAL.
  const auto ee_ticks = jak1::call_goal_function_by_name("__read-ee-timer");
  *g_timer_reset_value = static_cast<int32_t>(static_cast<uint32_t>(ee_ticks >> 9));
#else
  (void)target_presentation_time;
#endif
  call_goal_on_stack(Ptr<Function>(g_dispatcher->value), goal_kernel_stack_top(), s7.offset,
                     g_ee_main_mem);
  drain_goal_print_buffer();
  // The overlord's vblank work: the music fade, and the `sound-iop-info` block written back to the
  // EE. A frame of the game is a frame of sound.
  goal_sound_frame();
  g_frames++;
  return true;
}

void reset_frame_timing() noexcept {
#if TARGET_OS_IOS || TARGET_OS_VISION
  g_display_clock.reset();
#endif
}

CameraFrameIdentity current_camera_frame_identity() noexcept {
  CameraFrameIdentity out;
  out.engine_frame_id = g_frames + 1;
  out.camera_correction = current_camera_correction_snapshot();
  if (!g_math_camera || !g_ee_main_mem) {
    return out;
  }

  // Snapshot at __send-gfx-dma-chain, after the producer ran and before the next dispatcher frame
  // can rewrite *math-camera*. The helper uses the asserted Jak 1 object layout and serializes the
  // same 15 qwords as add-pc-tfrag3-data.
  const uint32_t camera = static_cast<uint32_t>(*g_math_camera);
  if (camera < static_cast<uint32_t>(EE_MAIN_MEM_LOW_PROTECT) ||
      camera >= static_cast<uint32_t>(EE_MAIN_MEM_SIZE)) {
    return out;
  }

  metal_camera_trace::RenderSnapshot render_camera;
  static_assert(sizeof(out.render_camera) == metal_camera_trace::kRenderSnapshotBytes);
  static_assert(sizeof(out.camera) == metal_camera_trace::kSnapshotBytes);
  if (!metal_camera_trace::try_make_jak1_live_render_snapshot(
          g_ee_main_mem + camera, static_cast<std::size_t>(EE_MAIN_MEM_SIZE - camera),
          &render_camera)) {
    return out;
  }
  std::memcpy(out.render_camera.data(), render_camera.bytes.data(), out.render_camera.size());
  out.render_camera_valid = true;

  constexpr std::size_t kCameraTempBytes = 64;
  constexpr std::size_t kTranslationQword = 6;
  constexpr std::size_t kQwordBytes = 16;
  std::memcpy(out.camera.data(), render_camera.bytes.data(), kCameraTempBytes);
  std::memcpy(out.camera.data() + kCameraTempBytes,
              render_camera.bytes.data() + kTranslationQword * kQwordBytes, kQwordBytes);
  out.camera_valid = true;
  return out;
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
  g_math_camera = nullptr;
  g_camera_master = nullptr;
  g_camera_combiner = nullptr;
  g_camera_master_type = 0;
  g_camera_slave_type = 0;
  g_camera_combiner_type = 0;
  reset_frame_timing();
#if TARGET_OS_IOS || TARGET_OS_VISION
  g_timer_reset_value = nullptr;
  g_host_display_time_ratio = nullptr;
#endif
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

bool run_frame(double target_presentation_time) noexcept {
  (void)target_presentation_time;
  return false;
}

void reset_frame_timing() noexcept {}

CameraFrameIdentity current_camera_frame_identity() noexcept {
  return {};
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
