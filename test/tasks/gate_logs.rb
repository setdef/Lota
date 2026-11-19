# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# A failed gate job's log, as GitHub's logs API returns it, for the tests
# of what TrunkWatch and AutoRevert make of a hung GPU. It is recorded
# from the macOS Gate job of full run 43676695527 on 2026-11-15 and
# trimmed: the runner's GPU hung under the reference love, which drew
# black frames to the end, so the parity test found Lota's frame
# different, and the Metal watch of each engine reported the hang. Each
# part can be swapped for another, to make the log of a failure that is
# the code's.
module GateLogs
  STAMP = "2026-11-15T04:48:08.7092150Z"

  # What the reference love's Metal watch reported: two command buffers
  # the GPU hung on, then one Metal ignored after the hang, then the
  # count.
  REFERENCE_HUNG = [
    "lota-metal-watch: a committed command buffer ended with status 5 (error), error: Error Domain=MTLCommandBufferErrorDomain " \
      'Code=2 "Caused GPU Hang Error (00000003:kIOGPUCommandBufferCallbackErrorHang)"',
    "lota-metal-watch: a command buffer waited on ended with status 5 (error), error: Error Domain=MTLCommandBufferErrorDomain " \
      'Code=2 "Caused GPU Hang Error (00000003:kIOGPUCommandBufferCallbackErrorHang)"',
    "lota-metal-watch: a committed command buffer ended with status 5 (error), error: Error Domain=MTLCommandBufferErrorDomain " \
      'Code=4 "Ignored (for causing prior/excessive GPU errors) (00000004:kIOGPUCommandBufferCallbackErrorSubmissionsIgnored)"',
    "lota-metal-watch: 2519 command buffers committed, 2258 completed, 261 failed; 2519 waited on, 261 of them not completed",
  ].freeze

  # What a Metal watch reports when every command buffer completed.
  CLEAN = ["lota-metal-watch: 2519 command buffers committed, 2519 completed, 0 failed; 2519 waited on, 0 of them not completed"].freeze

  # What Lota's Metal watch reported in the same run: one command buffer
  # the GPU hung on.
  LOTA_HUNG = [
    "lota-metal-watch: a committed command buffer ended with status 5 (error), error: Error Domain=MTLCommandBufferErrorDomain " \
      'Code=2 "Caused GPU Hang Error (00000003:kIOGPUCommandBufferCallbackErrorHang)"',
    "lota-metal-watch: 2519 command buffers committed, 2518 completed, 1 failed; 2519 waited on, 1 of them not completed",
  ].freeze

  # The parity test's failure, given what each engine's Metal watch
  # reported, numbered +number+.
  def self.failure(reference: REFERENCE_HUNG, lota: LOTA_HUNG, number: 1)
    [
      "  #{number}) Failure:",
      "GravityWarsTest#test_the_translation_matches_love_frame_by_frame [test/parity/gravity_wars_test.rb:108]:",
      'first differing frame: {"frame" => 2261, "message" => "compare image pixel (1.0,1.0,1.0,1.0) at 1,1, matching = a, ' \
        'not matching = rgb (frame 2261)", "difference" => "LÖVE\'s frame has (0,0,0,255) there; 62859 of 800000 pixels differ"}',
      "The reference love printed, last 40 of 43 lines:",
      "randomizing planets attempt",
      "New Game Started",
      "The reference love's Metal watch reported:",
      *reference,
      "Lota printed, last 40 of 43 lines:",
      "randomizing planets attempt",
      "New Game Started",
      "Lota's Metal watch reported:",
      *lota,
    ]
  end

  # A minitest failure that is no parity test's, numbered +number+.
  def self.assertion(number: 2)
    [
      "  #{number}) Failure:",
      "GravityWarsTest#test_love_runs_the_game_through_a_hit_and_a_new_game [test/parity/gravity_wars_test.rb:60]:",
      "Expected false to be truthy.",
]
  end

  # The gate check test:shard:gravity_wars, which failed with +failures+,
  # as minitest counted +failed+ of them.
  def self.shard(failures: failure, failed: 1)
    [
      "❌ gate: test:shard:gravity_wars (514 s)",
      "Run options: --verbose --seed 22058",
      "# Running:",
      "GravityWarsTest#test_the_translation_matches_love_frame_by_frame = 419.94 s = F",
      "GravityWarsTest#test_love_runs_the_game_through_a_hit_and_a_new_game = 0.01 s = .",
      "Finished in 419.952225s, 0.0048 runs/s, 0.0238 assertions/s.",
      *failures,
      "2 runs, 10 assertions, #{failed} failures, 0 errors, 0 skips",
      "rake aborted!",
      "Command failed with status (1): [TEST= TESTOPTS= N= I= X= E= FILTER= ruby -Ilib:test:. -w -e require \"minitest/autorun\"]",
      "Tasks: TOP => test:shard:gravity_wars",
      "(See full trace by running task with --trace)",
    ]
  end

  # A check that passed.
  PASSED = ["✅ gate: test:shard:parity (584 s)", "ArkanoidTest#test_1_05_resolvingcollisions_matches_love_frame_by_frame = 31.81 s = ."].freeze

  # The gate's table of timings, with each lane check's verdict in
  # +verdicts+.
  def self.timings(verdicts = { "test:shard:gravity_wars" => "FAILED", "test:shard:parity" => "passed" })
    [
      "gate timings",
      format("  %-48s %6.0f s", "engine (first, in order)", 42),
      *verdicts.map { |name, verdict| format("  %-48s %6.0f s  %s", name, 514, verdict) },
      format("  %-48s %6.0f s  (the checks one after another: %.0f s)", "total", 1201, 3994),
]
  end

  # The job's log, from the gate's report in +sections+ and its +table+:
  # every line stamped, and the step's exit status after them.
  def self.log(sections: [shard, PASSED], table: timings)
    lines = ["Run bundle exec rake", *sections.flatten, *table, "##[error]Process completed with exit code 1."]
    lines.map { |line| "#{STAMP} #{line}\n" }.join
  end

  # The recorded log itself.
  HUNG = log
end
