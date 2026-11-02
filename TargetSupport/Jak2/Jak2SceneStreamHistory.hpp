#pragma once

#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>

namespace goalpad::jak2 {

// Diagnostic-only, bounded scene/stream/render progression for the Files frame-timing report.
// Pure data so it is testable without the runtime; the bridge fills samples from copies taken on
// the serialized runtime tick and exports only this object's own storage.
inline constexpr std::size_t kSceneStreamSlotCount = 4;
inline constexpr std::size_t kSceneStreamHistoryCapacity = 12;
inline constexpr std::uint64_t kSceneStreamPeriodTicks = 60;

// Copies at most min(N - 1, capacity) bytes and always terminates, so unterminated sources are safe.
template <std::size_t N>
void copy_code_name(char (&out)[N], const char* in, std::size_t capacity) {
  std::size_t length = 0;
  if (in) {
    const std::size_t limit = capacity < N - 1 ? capacity : N - 1;
    while (length < limit && in[length] != '\0') {
      length++;
    }
    std::memcpy(out, in, length);
  }
  out[length] = '\0';
}

struct SceneStreamSlot {
  char name[48];
  std::int32_t id;
  std::uint32_t status;
  std::int32_t position;
  bool active;
  bool playing;
  bool paused;
  bool finished;
  std::uint64_t position_stalls;
};

struct SceneStreamSample {
  std::uint64_t tick;
  bool scene_valid;
  char scene[64];
  std::int64_t scene_elapsed;
  bool frame_valid;
  float frame;
  bool wait_valid;
  std::int32_t wait_gate;
  char art_file_status[16];
  bool render_valid;
  std::uint64_t chains;
  std::uint64_t completed_chains;
  std::uint64_t failed_chains;
  std::uint64_t submissions;
  std::uint64_t presentations;
  std::uint64_t draws;
  std::uint64_t audio_pulls;
  SceneStreamSlot slots[kSceneStreamSlotCount];
};

// Each tick is the first sample whose value differed from the previous sample under the same
// identity and validity. An identity or validity change restarts it at that sample.
struct SceneStreamProgress {
  std::uint64_t scene_changed_tick;
  std::uint64_t frame_changed_tick;
  std::uint64_t elapsed_changed_tick;
  std::uint64_t completed_chains_changed_tick;
  std::uint64_t presentations_changed_tick;
  std::uint64_t audio_pulls_changed_tick;
  std::uint64_t slot_identity_changed_tick[kSceneStreamSlotCount];
  std::uint64_t slot_position_changed_tick[kSceneStreamSlotCount];
};

class SceneStreamHistory {
 public:
  void reset() { *this = SceneStreamHistory(); }

  // Per-tick gate over already-copied runtime metrics only: the first sample, a new session, each
  // crossed period, or a scene identity/validity change.
  bool should_sample(std::uint64_t tick, bool scene_valid, const char* scene,
                     std::size_t capacity) const {
    if (m_count == 0 || tick < m_last.tick) {
      return true;
    }
    if (tick == m_last.tick) {
      return false;
    }
    if (tick / kSceneStreamPeriodTicks > m_last.tick / kSceneStreamPeriodTicks) {
      return true;
    }
    char name[sizeof(m_last.scene)];
    copy_code_name(name, scene_valid ? scene : nullptr, capacity);
    return scene_valid != m_last.scene_valid || std::strcmp(name, m_last.scene) != 0;
  }

  void record(SceneStreamSample sample) {
    if (m_count && sample.tick <= m_last.tick) {
      if (sample.tick == m_last.tick) {
        return;
      }
      reset();
    }
    normalize(&sample);

    const bool first = m_count == 0;
    const std::uint64_t tick = sample.tick;
    auto& p = m_progress;
    const bool same_scene = !first && sample.scene_valid == m_last.scene_valid &&
                            std::strcmp(sample.scene, m_last.scene) == 0;
    if (!same_scene) {
      p.scene_changed_tick = tick;
      p.frame_changed_tick = tick;
      p.elapsed_changed_tick = tick;
    } else {
      // Bitwise comparison; invalid frames are normalized to zero so they never read as motion.
      if (sample.frame_valid != m_last.frame_valid ||
          std::memcmp(&sample.frame, &m_last.frame, sizeof(float)) != 0) {
        p.frame_changed_tick = tick;
      }
      if (sample.scene_elapsed != m_last.scene_elapsed) {
        p.elapsed_changed_tick = tick;
      }
    }

    const bool same_render = !first && sample.render_valid == m_last.render_valid;
    if (!same_render || sample.completed_chains != m_last.completed_chains) {
      p.completed_chains_changed_tick = tick;
    }
    if (!same_render || sample.presentations != m_last.presentations) {
      p.presentations_changed_tick = tick;
    }
    if (first || sample.audio_pulls != m_last.audio_pulls) {
      p.audio_pulls_changed_tick = tick;
    }

    for (std::size_t i = 0; i < kSceneStreamSlotCount; i++) {
      const auto& now = sample.slots[i];
      const auto& before = m_last.slots[i];
      const bool same_stream = !first && now.active == before.active && now.id == before.id &&
                               std::strcmp(now.name, before.name) == 0;
      if (!same_stream) {
        p.slot_identity_changed_tick[i] = tick;
        p.slot_position_changed_tick[i] = tick;
      } else if (now.position != before.position) {
        p.slot_position_changed_tick[i] = tick;
      }
    }

    m_ring[m_next] = sample;
    m_next = (m_next + 1) % kSceneStreamHistoryCapacity;
    if (m_count < kSceneStreamHistoryCapacity) {
      m_count++;
    }
    m_recorded++;
    m_last = sample;
  }

  std::size_t size() const { return m_count; }
  std::uint64_t recorded() const { return m_recorded; }
  // Index 0 is the oldest retained sample.
  const SceneStreamSample& at(std::size_t index) const {
    return m_ring[(m_next + kSceneStreamHistoryCapacity - m_count + index) %
                  kSceneStreamHistoryCapacity];
  }
  const SceneStreamProgress& progress() const { return m_progress; }

 private:
  static void normalize(SceneStreamSample* sample) {
    sample->scene[sizeof(sample->scene) - 1] = '\0';
    sample->art_file_status[sizeof(sample->art_file_status) - 1] = '\0';
    if (!sample->scene_valid) {
      sample->scene[0] = '\0';
      sample->scene_elapsed = 0;
    }
    sample->frame_valid = sample->frame_valid && std::isfinite(sample->frame);
    if (!sample->frame_valid) {
      sample->frame = 0.0f;
    }
    if (!sample->wait_valid) {
      sample->wait_gate = 0;
      sample->art_file_status[0] = '\0';
    }
    if (!sample->render_valid) {
      sample->chains = sample->completed_chains = sample->failed_chains = 0;
      sample->submissions = sample->presentations = sample->draws = 0;
    }
    for (auto& slot : sample->slots) {
      slot.name[sizeof(slot.name) - 1] = '\0';
      if (!slot.active) {
        slot = {};
      }
    }
  }

  std::array<SceneStreamSample, kSceneStreamHistoryCapacity> m_ring{};
  std::size_t m_next = 0;
  std::size_t m_count = 0;
  std::uint64_t m_recorded = 0;
  SceneStreamSample m_last{};
  SceneStreamProgress m_progress{};
};

}  // namespace goalpad::jak2
