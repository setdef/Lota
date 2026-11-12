# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_files"

# Clear the default test task created by Minitest::TestTask if it exists
Rake::Task["test"].clear if Rake::Task.task_defined?("test")

# What each suite runs. test/sanitizers holds the tests that deliberately
# corrupt memory, which only the sanitized build may run; every other test
# runs in test:ruby. test/native and test/lovetest, the translated Lövetest
# tests, run in both, so the window and the renderer run under the
# sanitizers too.
# test/parity holds the parity harness, which runs games in
# the reference love as well as in Lota, so it runs in test:parity, once
# that love is built.
TEST_SUITES = {
  ruby: %w[test/*_test.rb test/native/**/*_test.rb test/lovetest/**/*_test.rb test/tasks/**/*_test.rb],
  native: %w[test/native/**/*_test.rb test/lovetest/**/*_test.rb test/sanitizers/**/*_test.rb],
  parity: %w[test/parity/**/*_test.rb],
}.freeze

# The unit tier: the test files whose every test is a unit test, which
# loads no native extension, starts no process, opens no socket, and never
# sleeps, so it takes milliseconds. rake test:unit runs them with nothing
# built, under test/unit_guard.rb, which fails a test that does any of
# those. Every other test is an integration test: it needs the build, a
# process of its own, or the machine.
UNIT_TESTS = %w[
  test/cli_test.rb
  test/restart_test.rb
  test/translation_examples_test.rb
  test/variant_test.rb
  test/tasks/android_build_test.rb
  test/tasks/api_diff_test.rb
  test/tasks/auto_revert_test.rb
  test/tasks/ios_build_test.rb
  test/tasks/jobs_test.rb
  test/tasks/native_format_pe_test.rb
  test/tasks/phone_notices_test.rb
  test/tasks/rbs_parity_test.rb
  test/tasks/release_plan_test.rb
  test/tasks/test_files_test.rb
  test/tasks/trunk_watch_test.rb
].freeze

# What test:unit loads before its tests.
UNIT_PRELUDE = %(require "unit_guard"; UnitGuard.install)

# The gate runs test:ruby as the shards below, which together hold exactly
# its files, so that it runs them at the same time (tasks/gate.rake). The
# unit tests are a shard, run as test:unit runs them; the generator's
# tests and rake_tasks_test.rb, the slowest, are shards of their own;
# test/tasks/rake_tasks_test.rb also runs the C++ gates and the sanitized
# suite.
RUBY_SHARDS = {
  unit: UNIT_TESTS,
  generator: %w[test/tasks/bindings/**/*_test.rb],
  rake_tasks: %w[test/tasks/rake_tasks_test.rb],
}.then do |shards|
  taken = shards.values.flat_map { |globs| Dir[*globs] }
  shards.merge(
    tasks: (Dir["test/tasks/**/*_test.rb"] - taken).sort,
    native: (Dir[*TEST_SUITES.fetch(:ruby)] - taken - Dir["test/tasks/**/*_test.rb"]).sort
  ).freeze
end

# The gate runs test:parity as two shards, which together hold exactly its
# files, since the harness was the gate's longest check: LÖVE's run of
# Gravity-Wars, which every test of gravity_wars_test.rb shares, took
# about as long in the gate as every other parity test together.
PARITY_SHARDS = {
  gravity_wars: %w[test/parity/gravity_wars_test.rb],
}.then do |shards|
  shards.merge(parity: (Dir[*TEST_SUITES.fetch(:parity)] - shards.values.flat_map { |globs| Dir[*globs] }).sort).freeze
end

# The parity harness's own unit tests, which run neither the reference
# love nor a game and draw nothing, so rake red_before_green checks them
# as it checks test:ruby's (tasks/red_before_green.rake). A test of
# theirs that does run the reference love goes unchecked there
# (RedBeforeGreen::NEEDS_REFERENCE).
PARITY_UNITS = %w[
  test/parity/mismatch_message_test.rb
  test/parity/reference_cache_test.rb
  test/parity/run_test.rb
].freeze

# The pre-push tier (rake prepush, tasks/gate.rake) runs every test of
# test:ruby and test:parity but those PREPUSH_LEAVES_OUT names, as
# "Class" for all of a class's tests or "Class#test" for one, less those
# PREPUSH_KEEPS names, which stay as a smoke test of a class left out. What
# it leaves out is what took more than about a second and a half in the
# gate (doc/contributors/development.md, "Before every push"):
# processes that run a whole game, the parity games, the generator's
# second and third runs over all of LÖVE (the first, which every
# generator test shares, it keeps, in a lane of its own), and the
# sanitized suite, which it runs a part of. The committed bindings are
# checked before anything builds anyway (bindings:check).
PREPUSH_LEAVES_OUT = %w[
  RakeTasksTest#test_the_native_suite_passes_under_the_sanitizers
  LotaRunTest
  RestartRunTest
  PhysicsBindingsTest#test_bodies_never_returns_a_wrapper_the_collector_found_dead
  JoystickEventsTest#test_joysticks_never_returns_a_wrapper_the_collector_found_dead
  NativeGemTest#test_a_warning_stops_the_build
  NativeGemTest#test_a_source_archive_that_is_missing_or_not_the_one_recorded_stops_the_build
  NativeGemTest#test_a_bundled_library_the_record_lacks_stops_the_build
  LicensingTest#test_the_real_bundle_carries_what_its_objects_were_compiled_from
  BenchTest#test_spawn_kills_a_run_that_takes_too_long
  GeneratorTest#test_the_drift_gate_reports_edited_missing_and_stale_files
  GeneratorTest#test_the_committed_bindings_match_the_generator
  ArkanoidTest
  GravityWarsTest
  KleleAtomsTest
  BenchGamesTest
  ReferenceCacheTest#test_a_cached_run_of_the_reference_love_is_what_running_it_again_gives
  DirectoryTest
  RunTest#test_a_slow_run_that_keeps_showing_frames_runs_to_its_end
] + [
  # NativeGemTest checks how the bundle finds what the gem carries as each
  # platform links it, libraries on Linux and frameworks on macOS, and
  # defines only the check for the platform it runs on.
  "NativeGemTest#test_the_bundle_loads_its_#{RUBY_PLATFORM.include?('linux') ? 'libraries' : 'frameworks'}_from_inside_the_gem",
].freeze
PREPUSH_KEEPS = %w[
  LotaRunTest#test_callbacks_run_in_loves_order_and_the_game_exits_with_its_status
  LotaRunTest#test_an_error_in_a_callback_shows_the_error_screen_and_prints_a_backtrace
  RestartRunTest#test_a_restart_runs_the_game_again_in_the_same_process_and_hands_over_its_value
  ArkanoidTest#test_1_01_theballthebricktheplatform_matches_love_frame_by_frame
].freeze

# Minitest's --exclude pattern for the tests the pre-push tier leaves out.
PREPUSH_EXCLUDE = begin
  names = -> (list) { list.map { |name| Regexp.escape(name) + (name.include?("#") ? "" : "#.*") }.join("|") }
  "/\\A(?!(?:#{names.call(PREPUSH_KEEPS)})\\z)(?:#{names.call(PREPUSH_LEAVES_OUT)})\\z/"
end

# The part of the sanitized suite the pre-push tier runs: the deliberate
# memory bugs, which show the sanitizers are on, the tests of how wrappers
# hold and release the engine's objects, and Lövetest's graphics tests,
# which reach most of the renderer.
PREPUSH_SANITIZED = %w[
  test/sanitizers/sanitizer_test.rb
  test/native/memory_test.rb
  test/native/release_queue_test.rb
  test/native/engine_object_test.rb
  test/lovetest/graphics_test.rb
].freeze

# test:ruby includes a test that runs test:native (test/tasks/rake_tasks_test.rb),
# so rake test runs both.
desc "Run all tests, test:native among them"
task test: %w[test:ruby]

namespace :test do
  TestFiles::Task.create(:unit) do |t|
    t.test_globs = UNIT_TESTS
    t.test_prelude = UNIT_PRELUDE
  end
  Rake::Task["test:unit"].clear_comments.comment = "Run the unit tests, which build nothing and take seconds"

  TestFiles::Task.create(:ruby) do |t|
    t.test_globs = TEST_SUITES.fetch(:ruby)
  end
  task ruby: :compile

  namespace :shard do
    RUBY_SHARDS.each do |name, globs|
      TestFiles::Task.create(name) do |t|
        t.test_globs = globs
        t.test_prelude = UNIT_PRELUDE if name == :unit
      end
      task name => :compile unless name == :unit
    end

    PARITY_SHARDS.each do |name, globs|
      TestFiles::Task.create(name) do |t|
        t.test_globs = globs
      end
      task name => %w[compile reference:love]
    end
  end

  TestFiles::Task.create(:parity) do |t|
    t.test_globs = TEST_SUITES.fetch(:parity)
  end
  desc "Run each fixture game in the reference love and in Lota, and compare them frame by frame"
  task parity: %w[compile reference:love]

  desc "Run the native tests against Lota::Native built with ASan and UBSan"
  task native: %w[compile compile:sanitized] do
    sh(*SANITIZED.command(TestFiles.of(TEST_SUITES.fetch(:native)), load_path: %w[lib test]))
  end

  # The pre-push tier's tests, in the gate's shards: the native tests and
  # Lövetest, the tasks' tests, the generator's, the parity harness, and a
  # part of the sanitized suite.
  namespace :prepush do
    {
      native: [RUBY_SHARDS.fetch(:native), %w[compile]],
      tasks: [RUBY_SHARDS.values_at(:tasks, :rake_tasks).flatten, %w[compile]],
      generator: [RUBY_SHARDS.fetch(:generator), %w[compile]],
      parity: [TEST_SUITES.fetch(:parity), %w[compile reference:love]],
    }.each do |name, (globs, prerequisites)|
      TestFiles::Task.create(name) do |t|
        t.test_globs = globs
        t.extra_args = ["--exclude", PREPUSH_EXCLUDE]
      end
      task name => prerequisites
    end

    desc "Run a part of the native tests against Lota::Native built with ASan and UBSan"
    task sanitized: %w[compile compile:sanitized] do
      sh(*SANITIZED.command(TestFiles.of(PREPUSH_SANITIZED), load_path: %w[lib test]))
    end
  end
end
