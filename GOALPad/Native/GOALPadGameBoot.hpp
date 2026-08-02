#pragma once

#include <array>
#include <cstdint>
#include <string>

namespace goalpad {

/*! What the boot did, read out of the live kernel. */
struct BootStatus {
  bool booted = false;
  std::string message;

  int kernel_objects = 0;
  int game_objects = 0;
  int code_objects = 0;
  int data_objects = 0;
  std::uint32_t kernel_version = 0;
  std::uint32_t global_heap_used_bytes = 0;
  std::int32_t symbol_count = 0;

  bool sound_installed = false;
  int sound_sample_rate = 0;

  /*! Whether the Metal renderer answered the machine layer's graphics functions. When it did not,
   *  the frame's DMA chain is only measured and nothing is drawn. */
  bool renderer_installed = false;

  bool played = false;
  double seconds = 0;
};

/*!
 * Boot Jak 1 the way the game boots: KERNEL.CGO, then the machine layer this port has - the pad,
 * the DGO and STR RPCs, the sound RPC - then GAME.CGO, then the engine's own `play`. Every object
 * file's code comes from the ahead-of-time C the app was built with; every object file's data comes
 * off the player's own disc image.
 *
 * The kernel must already be up (`start_kernel`) and pointed at the data directory. Takes seconds,
 * so call it off the main thread; nothing else may touch the kernel while it runs. Never throws.
 */
BootStatus boot_game() noexcept;

/*!
 * Run one frame of the game: the GOAL kernel's own `kernel-dispatcher`, which runs every process
 * and state, and then the overlord's vblank work, which is what moves the music along. This is
 * `KernelCheckAndDispatch`'s loop body without the listener half.
 *
 * False if the game is not booted. Never throws.
 */
bool run_frame(double target_presentation_time) noexcept;

/*! Drop display-link history so the first frame after a lifecycle pause starts at ratio 1. */
void reset_frame_timing() noexcept;

/*! The camera state that the current dispatcher frame will copy into its background packets. */
struct CameraFrameIdentity {
  std::uint64_t engine_frame_id = 0;
  bool camera_valid = false;
  std::array<std::uint8_t, 80> camera = {};
};
CameraFrameIdentity current_camera_frame_identity() noexcept;

std::uint64_t frames_run() noexcept;
bool game_is_booted() noexcept;

/*! Forget the boot. The heap goes away with the kernel; this only drops what this file caches. */
void reset_game() noexcept;

/*! The DMA payload the last frame's chain carried, and the largest any frame has carried. Zero
 *  until a frame has built a chain. This is the measurement seam, not a renderer. */
struct FrameChainStats {
  int chains = 0;
  std::uint32_t last_payload_bytes = 0;
  std::uint32_t largest_payload_bytes = 0;
  int last_texture_uploads = 0;
};
FrameChainStats frame_chain_stats() noexcept;

}  // namespace goalpad
