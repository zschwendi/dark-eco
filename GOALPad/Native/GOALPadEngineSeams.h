#pragma once

/*!
 * @file GOALPadEngineSeams.h
 * Which of the engine's host seams the pinned OpenGOAL checkout actually provides.
 *
 * The app shell is written against three narrow C seams in `game/kernel/core/`: the data
 * directory, the controller, and the audio pull. They live on OpenGOAL branches that are not part
 * of the pinned submodule yet. Each one is detected by the presence of its header, so the shell
 * builds and runs today, says plainly on screen which seams are missing, and starts using them
 * with no source change once the pin carries them.
 *
 * This is the only file that knows about the split. Everything else asks the flags below.
 */

#include "game/kernel/core/kernel_core.h"

/* `goal_kernel_core_set_data_directory` and `goal_kernel_core_resolve_data_path` are declared in
 * kernel_core.h, which always exists, so they cannot be probed directly. The DGO loader is the
 * thing that reads out of that directory and arrived with it. */
#if __has_include("game/kernel/core/dgo_loader.h")
#define GOALPAD_HAVE_DATA_SEAM 1
#else
#define GOALPAD_HAVE_DATA_SEAM 0
#endif

#if __has_include("game/kernel/core/pad.h")
#define GOALPAD_HAVE_PAD_SEAM 1
#include "game/kernel/core/pad.h"
#else
#define GOALPAD_HAVE_PAD_SEAM 0
#endif

#if __has_include("game/kernel/core/sound_rpc.h")
#define GOALPAD_HAVE_SOUND_SEAM 1
#include "game/kernel/core/sound_rpc.h"
#else
#define GOALPAD_HAVE_SOUND_SEAM 0
#endif

/* Jak 1's own GOAL code, compiled ahead of time to C on the host and built into this app. It is
 * generated rather than committed - Scripts/generate-jak1-aot.sh - so a checkout that has not run
 * that script still builds, and says on screen that it cannot boot the game. */
#if GOALPAD_HAVE_DATA_SEAM && GOALPAD_HAVE_PAD_SEAM && GOALPAD_HAVE_SOUND_SEAM && \
    __has_include("aot_boot_manifest.h")
#define GOALPAD_HAVE_GAME_BOOT 1
#else
#define GOALPAD_HAVE_GAME_BOOT 0
#endif
