# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "minitest/test_task"

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

# The gate runs test:ruby as the shards below, which together hold exactly
# its files, so that it runs them at the same time (tasks/gate.rake). The
# generator's tests and rake_tasks_test.rb, the slowest, are shards of
# their own; test/tasks/rake_tasks_test.rb also runs the C++ gates and the
# sanitized suite.
RUBY_SHARDS = {
  generator: %w[test/tasks/bindings/**/*_test.rb],
  rake_tasks: %w[test/tasks/rake_tasks_test.rb],
}.then do |shards|
  taken = shards.values.flat_map { |globs| Dir[*globs] }
  shards.merge(
    tasks: (Dir["test/tasks/**/*_test.rb"] - taken).sort,
    native: (Dir[*TEST_SUITES.fetch(:ruby)] - taken - Dir["test/tasks/**/*_test.rb"]).sort
  ).freeze
end

# The pre-push tier (rake prepush, tasks/gate.rake) runs every test of
# test:ruby and test:parity but those PREPUSH_LEAVES_OUT names, as
# "Class" for all of a class's tests or "Class#test" for one, less those
# PREPUSH_KEEPS names, which stay as a smoke test of a class left out. What
# it leaves out is what took more than about a second and a half on the
# gate runner (doc/contributors/development.md, The pre-push tier):
# processes that run a whole game, the parity games, the generator's runs
# over all of LÖVE, and the sanitized suite, which it runs a part of.
PREPUSH_LEAVES_OUT = %w[
  RakeTasksTest#test_the_native_suite_passes_under_the_sanitizers
  LotaRunTest
  RestartRunTest
  PhysicsBindingsTest#test_bodies_never_returns_a_wrapper_the_collector_found_dead
  JoystickEventsTest#test_joysticks_never_returns_a_wrapper_the_collector_found_dead
  NativeGemTest#test_the_bundle_loads_its_libraries_from_inside_the_gem
  NativeGemTest#test_a_warning_stops_the_build
  NativeGemTest#test_a_source_archive_that_is_missing_or_not_the_one_recorded_stops_the_build
  NativeGemTest#test_a_bundled_library_the_record_lacks_stops_the_build
  LicensingTest#test_the_real_bundle_carries_what_its_objects_were_compiled_from
  BenchTest#test_spawn_kills_a_run_that_takes_too_long
  GeneratorTest#test_the_name_table_is_written_as_a_shareable_ruby_hash
  GeneratorTest#test_the_drift_gate_reports_edited_missing_and_stale_files
  GeneratorTest#test_arguments_beyond_the_bound_form_are_pruned
  GeneratorTest#test_the_committed_bindings_match_the_generator
  ParserTest#test_headers_give_return_types_through_bases_and_typedefs
  ArkanoidTest
  GravityWarsTest
  KleleAtomsTest
  BenchGamesTest
  ReferenceCacheTest#test_a_cached_run_of_the_reference_love_is_what_running_it_again_gives
  DirectoryTest
  RunTest#test_a_slow_run_that_keeps_showing_frames_runs_to_its_end
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
  Minitest::TestTask.create(:ruby) do |t|
    t.test_globs = TEST_SUITES.fetch(:ruby)
  end
  task ruby: :compile

  namespace :shard do
    RUBY_SHARDS.each do |name, globs|
      Minitest::TestTask.create(name) do |t|
        t.test_globs = globs
      end
      task name => :compile
    end
  end

  Minitest::TestTask.create(:parity) do |t|
    t.test_globs = TEST_SUITES.fetch(:parity)
  end
  desc "Run each fixture game in the reference love and in Lota, and compare them frame by frame"
  task parity: %w[compile reference:love]

  desc "Run the native tests against Lota::Native built with ASan and UBSan"
  task native: %w[compile compile:sanitized] do
    sh(*SANITIZED.command(Dir[*TEST_SUITES.fetch(:native)].sort, load_path: %w[lib test]))
  end

  # The pre-push tier's tests, in the gate's shards: the native tests and
  # Lövetest, the tasks' tests with the generator's, the parity harness,
  # and a part of the sanitized suite.
  namespace :prepush do
    {
      native: [RUBY_SHARDS.fetch(:native), %w[compile]],
      tasks: [RUBY_SHARDS.values_at(:tasks, :generator, :rake_tasks).flatten, %w[compile]],
      parity: [TEST_SUITES.fetch(:parity), %w[compile reference:love]],
    }.each do |name, (globs, prerequisites)|
      Minitest::TestTask.create(name) do |t|
        t.test_globs = globs
        t.extra_args = ["--exclude", PREPUSH_EXCLUDE]
      end
      task name => prerequisites
    end

    desc "Run a part of the native tests against Lota::Native built with ASan and UBSan"
    task sanitized: %w[compile compile:sanitized] do
      sh(*SANITIZED.command(PREPUSH_SANITIZED, load_path: %w[lib test]))
    end
  end
end
