# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require "rake"

# Loads the repository's Rakefile and runs the engine and C++ tasks that
# finish in seconds against the real tree. The engine build itself is too
# slow for the unit suite; the default task runs it.
class RakeTasksTest < Minitest::Test
  include TreeHelper

  # The Rakefile defines constants, so it loads once per process. Its
  # tasks land in whichever application is current as it loads, and Rake
  # changes into the Rakefile's directory.
  def self.application
    @application ||= Rake::Application.new.tap do |application|
      Rake.application = application
      application.init("rake", ["--rakefile", File.join(ROOT, "Rakefile")])
      application.load_rakefile
    end
  end

  def setup
    @previous = Rake.application
    Rake.application = self.class.application
  end

  def teardown
    Rake.application = @previous
  end

  # Runs a task again, even if it ran before, and returns its stdout.
  def invoke(name)
    task = Rake::Task[name].tap(&:reenable)
    out, = capture_io { task.invoke }
    out
  end

  def prerequisites(name)
    Rake::Task[name].prerequisites
  end

  def test_default_task_builds_the_engine_and_runs_every_cpp_gate
    assert_includes prerequisites("default"), "engine"
    assert_includes prerequisites("default"), "cpp"
    assert_equal %w[cpp:format cpp:no_nolint cpp:tidy], prerequisites("cpp")
  end

  def test_engine_checks_its_source_list_and_generated_bindings_before_building
    assert_equal %w[engine:sources:check bindings:check engine:configure], prerequisites("engine")
    assert_equal %w[engine:configure], prerequisites("cpp:tidy")
  end

  # The precompiled gem installs in seconds, so the gate installs it and
  # runs a game from it, as CI does on a fresh runner.
  def test_default_task_checks_both_packages_last
    assert_equal %w[package:check package:install], prerequisites("default").last(2)
  end

  # The parity harness runs in the gate, against the reference love built
  # from vendor/love and Lota compiled from this tree.
  def test_default_task_runs_the_parity_harness_after_compiling
    default = prerequisites("default")

    assert_includes default, "test:parity"
    assert_operator default.index("compile"), :<, default.index("test:parity")
    assert_equal %w[compile reference:love], prerequisites("test:parity")
  end

  def test_the_reference_love_builds_from_vendor_love_into_tmp
    assert_equal File.join(ROOT, "tmp/reference/src/love-macos/love.app/Contents/MacOS/love"),
      REFERENCE_LOVE.executable
  end

  def test_default_task_compiles_before_it_tests
    default = prerequisites("default")

    assert_operator default.index("compile"), :<, default.index("test")
    assert_equal %w[test:ruby], prerequisites("test")
  end

  # The engine tree is configured only through extconf.rb, which
  # rake-compiler reruns when extconf.rb changes.
  def test_configuring_the_engine_runs_extconf
    assert_equal [NATIVE_MAKEFILE], prerequisites("engine:configure")
    assert_includes prerequisites(NATIVE_MAKEFILE), "ext/lota/extconf.rb"
    assert_equal "tmp/#{RUBY_PLATFORM}/lota/native/#{RUBY_VERSION}/Makefile", NATIVE_MAKEFILE
  end

  def test_compile_always_lets_cmake_decide_what_to_rebuild
    bundle = Rake::Task["tmp/#{RUBY_PLATFORM}/lota/native/#{RUBY_VERSION}/lota/native.#{RbConfig::CONFIG['DLEXT']}"]

    assert_includes bundle.prerequisites, "compile:cmake"
    assert_predicate bundle, :needed?
  end

  # CI's delivery job runs on a runner with the gem the gate job built and
  # no engine build, so delivering builds nothing.
  def test_delivering_a_built_gem_builds_nothing
    assert_empty prerequisites("package:deliver")
  end

  # Plan 001's "Done when": the installed gem runs Lövetest's translated
  # love.test.graphics.clear, among the rest, and every test it runs passes.
  def test_delivery_runs_lovetest_from_the_installed_gem
    lovetest = packages.first.games.find { |game| game.folder == "test/lovetest/game" }

    assert_equal ["minitest"], lovetest.gems
    assert_equal 0, lovetest.status
    assert_match lovetest.output, "love.conf\n........\n8 runs, 2065 assertions, 0 failures, 0 errors, 0 skips\n"
    refute_match lovetest.output, "love.conf\n0 runs, 0 assertions, 0 failures, 0 errors, 0 skips\n"
    refute_match lovetest.output, "love.conf\n1 runs, 3 assertions, 1 failures, 0 errors, 0 skips\n"
  end

  def test_the_lint_gate_checks_the_workflows
    assert_includes prerequisites("lint:all"), "workflows"
  end

  # actionlint passes without shellcheck, so the task refuses to run
  # without it.
  def test_checking_the_workflows_needs_shellcheck
    path = ENV.fetch("PATH")
    ENV["PATH"] = File.join(ROOT, "no-such-directory")
    _, err = capture_io { assert_raises(SystemExit) { Rake::Task["lint:workflows"].tap(&:reenable).invoke } }

    assert_includes err, "lint:workflows needs shellcheck on PATH"
  ensure
    ENV["PATH"] = path
  end

  def test_what_loads_the_extension_compiles_it_first
    %w[test:ruby rbs:parity package:check package:install package:native].each do |name|
      assert_includes prerequisites(name), "compile", name
    end
    assert_equal %w[compile compile:sanitized], prerequisites("test:native")
    assert_equal ["#{SANITIZED_EXT}/Makefile"], prerequisites("compile:sanitized")
  end

  # Every test runs somewhere, and the deliberate memory bugs only where
  # the sanitizers catch them.
  def test_every_test_file_belongs_to_a_suite
    Dir.chdir(ROOT) do
      ruby = Dir[*TEST_SUITES.fetch(:ruby)]
      native = Dir[*TEST_SUITES.fetch(:native)]
      parity = Dir[*TEST_SUITES.fetch(:parity)]

      assert_empty Dir["test/**/*_test.rb"] - ruby - native - parity
      assert_includes parity, "test/parity/arkanoid_test.rb"
      assert_empty ruby & parity
      assert_empty ruby.grep(%r{\Atest/sanitizers/})
      refute_empty native.grep(%r{\Atest/sanitizers/})
      assert_includes ruby, "test/native/memory_test.rb"
      assert_includes native, "test/native/memory_test.rb"
    end
  end

  # The native suite starts every process with posix_spawn, through
  # NativeHelper#capture2e: under rake test:native, a forked child can die
  # before it runs the command (LotaNativeTest.spawn).
  def test_no_native_suite_file_forks
    forks = /\bOpen3\b|\bIO\.popen\b|\bProcess\.spawn\b|(?<![.\w])(?:spawn|system|fork)\b|`|%x/
    Dir.chdir(ROOT) do
      files = Dir[*TEST_SUITES.fetch(:native), "test/native/native_helper.rb"]
      forking = files.select { |path| File.readlines(path).grep_v(/\A\s*#/).join.match?(forks) }

      refute_empty files
      assert_empty forking
    end
  end

  # rake test runs the sanitized suite through this test, so every line of
  # test:native runs in the gate.
  def test_the_native_suite_passes_under_the_sanitizers
    task = Rake::Task["test:native"].tap(&:reenable)
    failure = nil
    out, err = capture_subprocess_io do
      task.invoke
    rescue RuntimeError => e
      failure = e
    end

    assert_nil failure, "#{failure&.message}\n#{out}"
    assert_match(/^\d+ runs, \d+ assertions, 0 failures, 0 errors, 0 skips$/, out)
    assert_includes err, "DYLD_INSERT_LIBRARIES="
  end

  def test_engine_source_list_matches_vendor_love
    assert_includes invoke("engine:sources:check"), "✅ ext/lota/engine/sources_macos.cmake matches vendor/love"
  end

  def test_regenerating_the_engine_source_list_changes_nothing
    list = File.join(ROOT, "ext/lota/engine/sources_macos.cmake")
    committed = File.read(list)

    assert_includes invoke("engine:sources"), "✅ Wrote ext/lota/engine/sources_macos.cmake"
    assert_equal committed, File.read(list)
  ensure
    File.write(list, committed) if committed
  end

  def test_engine_source_check_aborts_with_the_difference
    list = File.join(ROOT, "ext/lota/engine/sources_macos.cmake")
    committed = File.read(list)
    File.write(list, committed.sub("\t${ENGINE_SOURCE_DIR}/src/common/Data.cpp\n", ""))

    task = Rake::Task["engine:sources:check"].tap(&:reenable)
    _, err = capture_io { assert_raises(SystemExit) { task.invoke } }
    assert_includes err, "❌ ext/lota/engine/sources_macos.cmake does not match vendor/love:\n" \
      "  + \t${ENGINE_SOURCE_DIR}/src/common/Data.cpp\n"
    assert_includes err, "run `bundle exec rake engine:sources` to regenerate it"
  ensure
    File.write(list, committed) if committed
  end

  def test_cpp_gates_pass_on_the_repository
    assert_match(/✅ cpp:format: \d+ files, no problems/, invoke("cpp:format"))
    assert_includes invoke("cpp:no_nolint"), "✅ No unapproved NOLINT in C++ files found"
    assert_match(/✅ cpp:tidy: \d+ files, no problems/, invoke("cpp:tidy"))
  end

  def test_format_fix_leaves_the_repository_formatted
    assert_match(/✅ cpp:format:fix: \d+ files, no problems/, invoke("cpp:format:fix"))
  end

  def test_a_failed_cpp_gate_aborts_with_its_problems
    result = CppGates::Result.new(checked: 1, problems: ["ext/bad.cpp:1: error"])

    _, err = capture_io do
      error = assert_raises(SystemExit) { cpp_gate!("cpp:probe", result) }
      refute_predicate error, :success?
    end
    assert_includes err, "❌ cpp:probe failed:\next/bad.cpp:1: error"
  end
end
