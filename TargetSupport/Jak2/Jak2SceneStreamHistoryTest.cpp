#include <cmath>
#include <cstdio>
#include <cstring>
#include <limits>

#include "Jak2SceneStreamHistory.hpp"

namespace {

using goalpad::jak2::kSceneStreamHistoryCapacity;
using goalpad::jak2::kSceneStreamPeriodTicks;
using goalpad::jak2::SceneStreamHistory;
using goalpad::jak2::SceneStreamSample;

int g_failures = 0;

void check(bool condition, const char* message) {
  if (!condition) {
    std::fprintf(stderr, "FAIL: %s\n", message);
    g_failures++;
  }
}

SceneStreamSample make_sample(std::uint64_t tick, const char* scene, float frame) {
  SceneStreamSample sample = {};
  sample.tick = tick;
  sample.scene_valid = scene != nullptr;
  goalpad::jak2::copy_code_name(sample.scene, scene, 64);
  sample.scene_elapsed = static_cast<std::int64_t>(tick) * 5;
  sample.frame_valid = true;
  sample.frame = frame;
  sample.wait_valid = true;
  sample.wait_gate = 0;
  sample.render_valid = true;
  sample.chains = sample.completed_chains = sample.submissions = sample.presentations = tick;
  sample.draws = tick * 10;
  sample.audio_pulls = tick;
  // Slot 0: scene stream; slot 1: unrelated music stream.
  sample.slots[0].active = true;
  sample.slots[0].id = 0x10002;
  goalpad::jak2::copy_code_name(sample.slots[0].name, "scenea", 48);
  sample.slots[0].position = static_cast<std::int32_t>(tick);
  sample.slots[0].playing = true;
  sample.slots[1].active = true;
  sample.slots[1].id = 0x20001;
  goalpad::jak2::copy_code_name(sample.slots[1].name, "musica", 48);
  sample.slots[1].position = static_cast<std::int32_t>(tick) * 2;
  sample.slots[1].playing = true;
  return sample;
}

}  // namespace

int main() {
  SceneStreamHistory history;
  check(history.size() == 0 && history.recorded() == 0, "a new history is empty");
  check(history.should_sample(1, true, "scene-a", 64), "the first tick is sampled");

  history.record(make_sample(1, "scene-a", 1.0f));
  const auto& first = history.progress();
  check(first.scene_changed_tick == 1 && first.frame_changed_tick == 1 &&
            first.completed_chains_changed_tick == 1 && first.slot_identity_changed_tick[0] == 1 &&
            first.slot_position_changed_tick[3] == 1,
        "the first sample starts every change tick, including inactive slots");

  check(!history.should_sample(1, true, "scene-a", 64), "a repeated tick is not sampled");
  check(!history.should_sample(30, true, "scene-a", 64), "same scene inside a period is gated");
  check(history.should_sample(30, true, "scene-b", 64), "a scene identity change is sampled");
  check(history.should_sample(30, false, "scene-a", 64), "a scene validity change is sampled");
  check(history.should_sample(kSceneStreamPeriodTicks, true, "scene-a", 64),
        "a crossed period is sampled");

  // Scene playhead stalls while its stream, the music stream and rendering advance.
  auto stalled = make_sample(60, "scene-a", 1.0f);
  stalled.slots[0].position = 1;
  history.record(stalled);
  auto stalled_again = make_sample(120, "scene-a", 1.0f);
  stalled_again.slots[0].position = 1;
  history.record(stalled_again);
  const auto& stall = history.progress();
  check(stall.frame_changed_tick == 1, "an unchanged frame under the same scene keeps its onset");
  check(stall.elapsed_changed_tick == 120, "advancing elapsed time is tracked separately");
  check(stall.slot_position_changed_tick[0] == 1, "the stalled scene stream keeps its onset");
  check(stall.slot_position_changed_tick[1] == 120,
        "an advancing unrelated stream does not mask the stalled slot");
  check(stall.completed_chains_changed_tick == 120 && stall.presentations_changed_tick == 120,
        "render counters are tracked independently of the scene playhead");

  // Non-finite frames normalize to invalid and never count as motion.
  history.record(make_sample(180, "scene-a", std::numeric_limits<float>::quiet_NaN()));
  check(!history.at(history.size() - 1).frame_valid && history.at(history.size() - 1).frame == 0.0f,
        "a NaN frame is stored as invalid zero");
  check(history.progress().frame_changed_tick == 180, "a validity flip counts as a change");
  history.record(make_sample(240, "scene-a", std::numeric_limits<float>::infinity()));
  check(history.progress().frame_changed_tick == 180, "repeated invalid frames are not motion");

  // Identity changes restart scene and slot onsets.
  auto next_scene = make_sample(250, "scene-b", 1.0f);
  next_scene.slots[0].id = 0x10003;
  history.record(next_scene);
  const auto& changed = history.progress();
  check(changed.scene_changed_tick == 250 && changed.frame_changed_tick == 250,
        "a scene identity change restarts the playhead onset");
  check(changed.slot_identity_changed_tick[0] == 250 &&
            changed.slot_position_changed_tick[0] == 250 &&
            changed.slot_identity_changed_tick[1] == 1,
        "a slot id change restarts only that slot");

  // Invalid inputs are cleared rather than reported as stale values.
  auto invalid = make_sample(300, "scene-b", 2.0f);
  invalid.scene_valid = false;
  invalid.render_valid = false;
  invalid.wait_valid = false;
  invalid.wait_gate = 7;
  invalid.slots[2].active = false;
  invalid.slots[2].id = 99;
  history.record(invalid);
  const auto& stored = history.at(history.size() - 1);
  check(stored.scene[0] == '\0' && stored.scene_elapsed == 0, "an invalid scene is cleared");
  check(stored.completed_chains == 0 && stored.presentations == 0,
        "failed Metal reads are zeroed");
  check(stored.wait_gate == 0 && stored.slots[2].id == 0, "invalid wait and inactive slot cleared");
  check(history.progress().scene_changed_tick == 300 &&
            history.progress().completed_chains_changed_tick == 300,
        "validity flips restart scene and render onsets");

  // Stored samples are copies; later mutation of the caller's input cannot change the export.
  auto source = make_sample(360, "scene-c", 3.0f);
  history.record(source);
  source.slots[0].position = -1;
  goalpad::jak2::copy_code_name(source.scene, "mutated", 64);
  check(history.at(history.size() - 1).slots[0].position == 360 &&
            std::strcmp(history.at(history.size() - 1).scene, "scene-c") == 0,
        "the history owns its samples");

  // Bounded ring keeps the newest samples in order.
  history.reset();
  for (std::uint64_t i = 1; i <= 20; i++) {
    history.record(make_sample(i * kSceneStreamPeriodTicks, "scene-a", static_cast<float>(i)));
  }
  check(history.size() == kSceneStreamHistoryCapacity && history.recorded() == 20,
        "the ring is bounded and counts every record");
  check(history.at(0).tick == (20 - kSceneStreamHistoryCapacity + 1) * kSceneStreamPeriodTicks &&
            history.at(kSceneStreamHistoryCapacity - 1).tick == 20 * kSceneStreamPeriodTicks,
        "the ring is ordered oldest to newest");

  // A tick regression (new session without reset) starts fresh; duplicates are ignored.
  history.record(make_sample(5, "scene-a", 1.0f));
  check(history.size() == 1 && history.recorded() == 1 && history.progress().scene_changed_tick == 5,
        "a tick regression resets the history");
  history.record(make_sample(5, "scene-z", 9.0f));
  check(history.size() == 1 && std::strcmp(history.at(0).scene, "scene-a") == 0,
        "a duplicate tick is ignored");

  history.reset();
  check(history.size() == 0 && history.recorded() == 0 && history.progress().scene_changed_tick == 0,
        "reset clears samples and progress");

  // Bounded copies of unterminated sources.
  char unterminated[4] = {'a', 'b', 'c', 'd'};
  char out[3];
  goalpad::jak2::copy_code_name(out, unterminated, sizeof(unterminated));
  check(std::strcmp(out, "ab") == 0, "code names are bounded and terminated");
  char wide[8];
  goalpad::jak2::copy_code_name(wide, unterminated, sizeof(unterminated));
  check(std::strcmp(wide, "abcd") == 0, "the source capacity bounds the read");

  if (g_failures) {
    std::fprintf(stderr, "%d Jak II scene/stream history check(s) failed\n", g_failures);
    return 1;
  }
  std::printf("Jak II scene/stream history checks passed\n");
  return 0;
}
