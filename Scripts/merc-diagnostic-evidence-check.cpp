#include "GOALPad/Native/GOALPadMercDiagnosticEvidence.hpp"

#include <cstdio>

namespace {

int failures = 0;

void check(bool condition, const char* description) {
  std::printf("%s %s\n", condition ? "ok  " : "FAIL", description);
  failures += condition ? 0 : 1;
}

}  // namespace

int main() {
  using namespace goalpad::merc_diagnostic_evidence;

  check(issue_mask({}) == 0, "a healthy Merc observation has no evidence bits");
  check(issue_mask({.affected_vertices = 1}) == AFFECTED_SKIN,
        "weighted collapse is evidence");
  check(issue_mask({.invalid_basis_groups = 1}) == INVALID_PROFILE &&
            issue_mask({.profile_tuple_mismatches = 1}) == INVALID_PROFILE,
        "invalid bases and tuple mismatches share the invalid-profile category");
  check(issue_mask({.repeated_packets_conflicting_palette = 1}) ==
                PACKET_PALETTE_CONFLICT &&
            issue_mask({.repeated_base_draws_conflicting_palette = 1}) ==
                BASE_DRAW_PALETTE_CONFLICT,
        "packet and base-draw palette conflicts are distinct evidence");
  check(issue_mask({.bound_palette_hash_mismatches = 1}) == BOUND_PALETTE_MISMATCH,
        "bound palette mismatches are evidence");
  check(issue_mask({.profile_capacity_drops = 1}) == CAPACITY_DROP &&
            issue_mask({.trace_capacity_drops = 1}) == CAPACITY_DROP,
        "profile and tracker capacity drops are evidence");
  check(should_update_retained_snapshot(false, 0),
        "healthy frames update the baseline before evidence exists");
  check(!should_update_retained_snapshot(true, 0),
        "a clean frame cannot erase an already retained evidence snapshot");
  check(should_update_retained_snapshot(true, PACKET_PALETTE_CONFLICT),
        "later evidence refreshes the retained raw snapshot");

  EpisodeTracker tracker;
  tracker.begin_frame();
  check(tracker.observe(CAPACITY_DROP) == CAPACITY_DROP,
        "the first issue category starts an evidence episode");
  check(tracker.observe(AFFECTED_SKIN | CAPACITY_DROP) == AFFECTED_SKIN,
        "a new issue category triggers even while another category persists");
  check(tracker.observe(AFFECTED_SKIN) == 0,
        "a repeated category in the same frame does not trigger twice");
  tracker.end_frame();
  tracker.begin_frame();
  check(tracker.observe(AFFECTED_SKIN | CAPACITY_DROP) == 0,
        "consecutive frames with the same categories do not trigger again");
  check(tracker.observe(PACKET_PALETTE_CONFLICT) == PACKET_PALETTE_CONFLICT,
        "a new category can trigger during a persistent multi-frame issue");
  tracker.end_frame();
  tracker.begin_frame();
  tracker.end_frame();
  tracker.begin_frame();
  check(tracker.observe(CAPACITY_DROP) == CAPACITY_DROP,
        "the same category can recur after a clean frame");

  return failures == 0 ? 0 : 1;
}
