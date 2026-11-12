# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../lovetest/unseen_desktop"
require_relative "../lovetest/lovetest_skips"
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

  # Runs a task again, even if it ran before, and returns its stdout. A
  # task that aborts, as a failed gate does, fails the test with what it
  # printed: abort raises SystemExit, which Minitest lets through to end
  # the whole run, and capture_io would keep the message it printed.
  def invoke(name)
    task = Rake::Task[name].tap(&:reenable)
    exited = nil
    out, err = capture_io do
      task.invoke
    rescue SystemExit => e
      exited = e
    end
    flunk "rake #{name} exited with status #{exited.status}:\n#{out}#{err}" if exited
    out
  end

  def prerequisites(name)
    Rake::Task[name].prerequisites
  end

  # What a sanitized run printed to stderr, where ASan's and UBSan's
  # reports go, and Ruby's [BUG] report when the report's abort reaches
  # Ruby's signal handler, less the memory map that report ends with, a
  # line for each of thousands of regions.
  def reported(err) = err.lines.grep_v(/\A\h+-\h+ [-r][-w][-x]/).join

  # rake bench opens a window for each of dozens of runs, so the gate
  # never runs it; it builds what it runs, Lota and the reference love.
  # What the gate runs, as default runs it (tasks/gate.rake): what it
  # prepares, in order, then the tasks of each check, lane by lane.
  def gate_tasks = GATE_PREPARE + GATE_LANES.flatten.flat_map(&:tasks)

  # CMake's generators run as many jobs as they like, Ninja one more than
  # the cores, whatever else shares them, so loading the tasks tells
  # CMake's builds how many to run (tasks/jobs.rake). It loads them in a
  # process of its own, since this one's rake set the variable already.
  def test_cmakes_builds_run_as_many_jobs_as_lota_jobs_says
    script = <<~RUBY
      require "rake"
      Rake.application.init("rake", ["--rakefile", #{File.join(ROOT, 'Rakefile').inspect}])
      Rake.application.load_rakefile
      print "CMAKE=" + ENV.fetch("CMAKE_BUILD_PARALLEL_LEVEL", "unset")
    RUBY
    environment = { "LOTA_JOBS" => "3", "CMAKE_BUILD_PARALLEL_LEVEL" => nil }
    output, error, status = Open3.capture3(environment, RbConfig.ruby, "-e", script, chdir: ROOT)

    assert_predicate status, :success?, error
    assert_equal "3", output[/CMAKE=(\S*)/, 1], output
  end

  # A contributor asks it before choosing to run the Windows checks.
  def test_windows_affected_takes_a_range_of_commits
    assert_equal %i[range], Rake::Task["windows:affected"].arg_names
  end

  def test_default_task_is_the_gate
    assert_equal %w[gate], prerequisites("default")
  end

  # A new checkout on a headless machine has fetched nothing yet.
  def test_the_gate_fetches_what_vendor_sources_lacks_before_it_builds
    assert_equal "sources:fetch", GATE_PREPARE.first
  end

  def test_bench_is_not_part_of_the_gate_and_builds_both_engines
    assert_equal %w[compile reference:love], prerequisites("bench")
    refute_includes gate_tasks, "bench"
  end

  def test_default_task_builds_the_engine_and_runs_every_cpp_gate
    assert_includes gate_tasks, "engine"
    assert_includes gate_tasks, "cpp"
    assert_equal %w[cpp:format cpp:no_nolint cpp:tidy], prerequisites("cpp")
  end

  def test_engine_checks_its_source_list_and_generated_bindings_before_building
    assert_equal %w[dependencies engine:sources:check bindings:check engine:configure], prerequisites("engine")
    assert_equal %w[engine:configure], prerequisites("cpp:tidy")
  end

  # On Linux the engine links what love-appimage-source's Makefile builds
  # (tasks/linux_build.rb), again whenever the Makefile or the recipe
  # changes, and each configure waits for it; on macOS the dependencies
  # come built, from vendor/love-apple-dependencies.
  def test_on_linux_the_dependencies_build_before_the_engine_is_configured
    stamp = File.join(ROOT, "tmp/dependencies/dependencies.stamp")
    if ENGINE_PLATFORM == "linux"
      assert_equal [stamp], prerequisites("dependencies")
      assert_equal [File.join(ROOT, "vendor/love-appimage-source/Makefile"), "tasks/linux_build.rb"],
        prerequisites(stamp)
      assert_includes prerequisites(NATIVE_MAKEFILE), stamp
      assert_includes prerequisites("#{SANITIZED_EXT}/Makefile"), stamp
    else
      assert_empty prerequisites("dependencies")
      refute Rake::Task.task_defined?(stamp)
    end
  end

  # The precompiled gem installs in seconds, so the gate installs it and
  # runs a game from it, as CI does on a fresh runner.
  def test_default_task_checks_both_packages_last
    windowed = GATE_LANES.find { |lane| lane.any? { |check| check.tasks.include?("package:check") } }

    assert_equal %w[package:check package:install], windowed.last(2).flat_map(&:tasks)
  end

  # The parity harness runs in the gate, as its shards, against the
  # reference love built from vendor/love and Lota compiled from this tree,
  # and the shards hold exactly its files, each once.
  def test_default_task_runs_the_parity_harness_after_compiling
    shards = PARITY_SHARDS.values.flat_map { |globs| Dir.chdir(ROOT) { Dir[*globs] } }

    assert_equal Dir.chdir(ROOT) { Dir[*TEST_SUITES.fetch(:parity)] }.sort, shards.sort
    assert_equal shards.uniq, shards
    PARITY_SHARDS.each_key do |name|
      assert_includes gate_tasks, "test:shard:#{name}"
      assert_operator gate_tasks.index("compile"), :<, gate_tasks.index("test:shard:#{name}")
      assert_equal %w[compile reference:love], prerequisites("test:shard:#{name}")
    end
    assert_equal %w[compile reference:love], prerequisites("test:parity")
  end

  def test_the_reference_love_builds_from_vendor_love_into_tmp
    assert_equal File.join(ROOT, "tmp/reference/src/love-macos/love.app/Contents/MacOS/love"),
      REFERENCE_LOVE.executable
    assert_equal File.join(ROOT, "tmp/dependencies/installdir/bin/love"), LINUX_BUILD.executable
  end

  # Every shard, test:ruby's and test:parity's, compiles first, but the
  # unit tests', which need nothing built.
  def test_default_task_compiles_before_it_tests
    shards = gate_tasks.grep(/\Atest:shard:/) - %w[test:shard:unit]

    assert_includes gate_tasks, "test:shard:unit"
    assert_includes shards, "test:shard:gravity_wars"
    shards.each { |shard| assert_operator gate_tasks.index("compile"), :<, gate_tasks.index(shard) }
    shards.each { |shard| assert_equal "compile", prerequisites(shard).first, shard }
    assert_equal %w[test:ruby], prerequisites("test")
  end

  # The gate runs test:ruby as shards, so the shards must hold exactly the
  # files test:ruby does, each once.
  def test_the_shards_hold_exactly_the_files_of_test_ruby
    shards = RUBY_SHARDS.values.flat_map { |globs| Dir[*globs] }

    assert_equal Dir[*TEST_SUITES.fetch(:ruby)].sort, shards.sort
    assert_equal shards.uniq, shards
    names = (RUBY_SHARDS.keys + PARITY_SHARDS.keys).map { |name| "test:shard:#{name}" }
    assert_equal names.sort, gate_tasks.grep(/\Atest:shard:/).sort
  end

  # The checks that open windows, which on Linux need a display of their
  # lane's own.
  WINDOWED = %w[
    test:shard:rake_tasks
    package:check
    package:install
    test:shard:native
    test:shard:gravity_wars
    test:shard:parity
    test:prepush:sanitized
    test:prepush:native
    test:prepush:parity
  ].freeze

  # The displays CI's Linux gate starts, one for each lane that opens
  # windows, in order.
  def ci_displays
    File.read(File.join(ROOT, ".github/workflows/ci.yml"))[/^\s*LOTA_GATE_DISPLAYS: "([^"]*)"/, 1].split
  end

  # Every lane whose checks open windows, in the gate and the pre-push
  # tier, comes before the lanes CI starts no display for, and no check of
  # the lanes after them opens any.
  def test_only_the_lanes_with_a_display_open_windows
    [GATE_LANES, PREPUSH_LANES].each do |lanes|
      windowed = lanes.map { |lane| lane.flat_map(&:tasks).intersect?(WINDOWED) }

      assert_operator windowed.count(true), :<=, ci_displays.size, lanes.inspect
      assert_equal windowed.sort_by { |open| open ? 0 : 1 }, windowed, lanes.inspect
    end
  end

  # The pre-push tier runs a part of every kind of check the gate runs, its
  # lanes that open windows first.
  def test_prepush_runs_the_fast_checks_and_a_part_of_the_slow_ones
    lanes = [
      %w[test:prepush:sanitized package:check],
      %w[test:prepush:native],
      %w[test:prepush:parity],
      %w[test:shard:unit test:prepush:tasks],
      %w[test:prepush:generator],
      %w[cpp:format cpp:no_nolint lint steep],
    ]

    assert_equal lanes, PREPUSH_LANES.map { |lane| lane.flat_map(&:tasks) }
    lanes.flatten.each { |name| assert Rake::Task.task_defined?(name), name }
    assert_equal %w[compile reference:love], prerequisites("test:prepush:parity")
    assert_equal %w[compile compile:sanitized], prerequisites("test:prepush:sanitized")
    assert_empty PREPUSH_SANITIZED - Dir.chdir(ROOT) { Dir[*TEST_SUITES.fetch(:native)] }
  end

  # The tests pre-push leaves out are named, so a test renamed or removed
  # must leave its name behind here, or the slow test it was would come
  # back into the tier unnoticed: every name is a test Minitest would run.
  def test_every_test_prepush_leaves_out_or_keeps_is_one_minitest_runs
    files = Dir.chdir(ROOT) { Dir[*TEST_SUITES.values_at(:ruby, :parity).flatten].map { |path| File.expand_path(path) } }
    lister = <<~RUBY
      require "minitest"
      def Minitest.autorun = nil
      ARGV.each { |path| require path }
      Minitest.seed = 0
      Minitest::Runnable.runnables.each { |runnable| runnable.runnable_methods.each { |name| puts "\#{runnable}#\#{name}" } }
    RUBY
    output, status = Open3.capture2e(RbConfig.ruby, "-I#{File.join(ROOT, 'lib')}", "-I#{File.join(ROOT, 'test')}",
      "-e", lister, *files, chdir: ROOT)
    assert status.success?, output
    tests = output.lines(chomp: true)

    (PREPUSH_LEAVES_OUT + PREPUSH_KEEPS).each do |name|
      if name.include?("#")
        assert_includes tests, name
      else
        assert tests.any? { |test| test.start_with?("#{name}#") }, "no tests of #{name}"
      end
    end
  end

  # The pattern leaves out a test it names, every test of a class it
  # names but those it keeps, and nothing else.
  def test_prepush_excludes_the_slow_tests_and_keeps_the_rest
    pattern = Regexp.new(PREPUSH_EXCLUDE[%r{\A/(.*)/\z}, 1])

    assert_match pattern, "RakeTasksTest#test_the_native_suite_passes_under_the_sanitizers"
    assert_match pattern, "GravityWarsTest#test_the_translation_matches_love_frame_by_frame"
    refute_match pattern, "ArkanoidTest#test_1_01_theballthebricktheplatform_matches_love_frame_by_frame"
    refute_match pattern, "RakeTasksTest#test_default_task_is_the_gate"
    refute_match pattern, "test_the_native_suite_passes_under_the_sanitizers"
  end

  # red_before_green checks the parity harness's unit tests with
  # test:ruby's, but neither its games nor the sanitized suite, which
  # need the reference love or the sanitized build.
  def test_red_before_green_checks_the_parity_units_but_not_the_games
    suites = Dir.chdir(ROOT) { Dir[*red_before_green_suites] }

    assert_includes suites, "test/parity/run_test.rb"
    assert_includes suites, "test/parity/mismatch_message_test.rb"
    assert_includes suites, "test/tasks/red_before_green_test.rb"
    refute_includes suites, "test/parity/gravity_wars_test.rb"
    refute_includes suites, "test/sanitizers/sanitizer_test.rb"
    assert_empty PARITY_UNITS - Dir.chdir(ROOT) { Dir[*TEST_SUITES.fetch(:parity)] }
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

  # The installed gem runs Lövetest's translated
  # love.test.graphics.clear, among the rest, and every test it runs passes.
  def test_delivery_runs_lovetest_from_the_installed_gem
    lovetest = packages.first.games.find { |game| game.folder == "test/lovetest/game" }

    assert_equal ["minitest"], lovetest.gems
    assert_equal 0, lovetest.status
    skips = UnseenDesktop.skips(LovetestSkips.expected)
    assert_match lovetest.output, "love.conf\n.......S\n8 runs, 2065 assertions, 0 failures, 0 errors, #{skips} skips\n"
    refute_match lovetest.output, "love.conf\n........\n8 runs, 2065 assertions, 0 failures, 0 errors, 0 skips\n"
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

  # The unit tests build nothing, and run under the guard that keeps them
  # unit tests (test/unit_guard.rb), as the gate's shard of them does.
  def test_the_unit_tier_builds_nothing_and_runs_under_its_guard
    %w[test:unit test:shard:unit].each { |name| assert_empty prerequisites(name), name }
    units = ObjectSpace.each_object(Minitest::TestTask).select { |task| task.name == :unit }

    assert_equal 2, units.size
    units.each { |task| assert_includes task.make_test_cmd, UNIT_PRELUDE }
    assert_equal UNIT_TESTS, RUBY_SHARDS.fetch(:unit)
  end

  # Every test task reads TEST as it runs, as Rake's own TestTask does and
  # Minitest's does not (tasks/test_files.rb).
  def test_every_test_task_runs_the_files_test_names
    tasks = ObjectSpace.each_object(Minitest::TestTask).to_a

    refute_empty tasks
    assert_empty tasks.reject { |task| task.is_a?(TestFiles::Task) }.map(&:name)
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
  # before it runs the command (LotaNativeTest.spawn). On Windows, where
  # Ruby never forks, Process.spawn starts it, in windows_support.rb,
  # which only Windows loads.
  def test_no_native_suite_file_forks
    forks = %r{\bOpen3\b|\bIO\.popen\b|\bProcess\.spawn\b|(?<![./\w])(?:spawn|system|fork)\b|`|%x}
    Dir.chdir(ROOT) do
      files = Dir[*TEST_SUITES.fetch(:native), "test/native/native_helper.rb"]
      forking = files.select { |path| File.readlines(path).grep_v(/\A\s*#/).join.match?(forks) }

      refute_empty files
      assert_empty forking
    end
  end

  # rake test runs the sanitized suite through this test, so every line of
  # test:native runs in the gate. Its skips, counted from the tests
  # (test/lovetest/lovetest_skips.rb), are Lövetest's discard,
  # requestAttention, showMessageBox, openURL, vibrate, pump, and wait
  # tests, which Lövetest skips everywhere (test/lovetest/tests/graphics.rb,
  # window.rb, system.rb, and event.rb), its getSource, setSource, and
  # RecordingDevice tests, the last of which skips where OpenAL Soft plays
  # into the wave writer, as the suite's does everywhere
  # (test/lovetest/tests/filesystem.rb and audio.rb), and, on a GitHub
  # runner on Linux, the window tests xvfb cannot pass (window.rb). Off Linux, the
  # sanitizers' own LeakSanitizer test skips, as LeakSanitizer runs at exit
  # on Linux only (test/sanitizers/sanitizer_test.rb). Lövetest's
  # isEnabled, getName, and getData sensor tests skip too where the machine
  # has neither an accelerometer nor a gyroscope
  # (test/lovetest/tests/sensor.rb), which this asks the machine, opening
  # the sensor module as the suite will.
  def test_the_native_suite_passes_under_the_sanitizers
    task = Rake::Task["test:native"].tap(&:reenable)
    failure = nil
    out, err = capture_subprocess_io do
      task.invoke
    rescue RuntimeError => e
      failure = e
    end

    assert_nil failure, "#{failure&.message}\n#{out}\n#{reported(err)}"
    Lota::Native::Sensor.open
    sensorless = %i[accelerometer gyroscope].none? { |sensor_type| Lota::Sensor.sensor?(sensor_type) }
    skips = UnseenDesktop.skips(LovetestSkips.expected + (TestHome::LINUX ? 0 : 1) + (sensorless ? 3 : 0))
    assert_match(/^\d+ runs, \d+ assertions, 0 failures, 0 errors, #{skips} skips$/, out)
    assert_includes err, "#{SanitizedBuild::PRELOADS.fetch(ENGINE_PLATFORM)}="
  end

  def test_engine_source_list_matches_vendor_love
    assert_includes invoke("engine:sources:check"), "✅ #{ENGINE_SOURCES_FILE} matches vendor/love"
  end

  # Each test writes its lists in a folder of its own, never the
  # checkout's: the gate's other lanes configure CMake from the checkout's
  # list as these run, and one that read it while a test had changed it
  # built an engine without the file the test left out.
  def test_regenerating_the_engine_source_lists_changes_nothing
    Dir.mktmpdir do |dir|
      ENGINE_SOURCE_LISTS.each do |file, sources|
        list = File.join(dir, file)
        sources.write(list)

        assert_equal File.read(File.join(ROOT, file)), File.read(list), "#{file} regenerates differently"
      end
    end
  end

  def test_engine_source_check_aborts_with_the_difference
    Dir.mktmpdir do |dir|
      list = File.join(dir, ENGINE_SOURCES_FILE)
      FileUtils.mkdir_p(File.dirname(list))
      committed = File.read(File.join(ROOT, ENGINE_SOURCES_FILE))
      File.write(list, committed.sub("\t${ENGINE_SOURCE_DIR}/src/common/Data.cpp\n", ""))

      _, err = capture_io { assert_raises(SystemExit) { EngineSources.check(list => ENGINE_SOURCES) } }
      assert_includes err, "❌ #{list} does not match vendor/love:\n" \
        "  + \t${ENGINE_SOURCE_DIR}/src/common/Data.cpp\n"
      assert_includes err, "run `bundle exec rake engine:sources` to regenerate it"
    end
  end

  # The gate's cpp check runs cpp:format, cpp:no_nolint, and cpp:tidy on
  # the repository (test_default_task_builds_the_engine_and_runs_every_cpp_gate),
  # so the tests do not run them on it again: they prove each task checks
  # every C++ file under ext with Lota's own settings, and fails the gate
  # on a file it finds a problem in. test/tasks/cpp_gates_test.rb proves
  # each check, with those settings, finds the problems it is for.
  def test_the_cpp_gates_check_every_file_under_ext_with_lotas_settings
    format = cpp_format
    tidy = cpp_tidy

    assert_equal CPP_FILES.all, format.files
    assert_includes format.files, File.join(ROOT, "ext/lota/native/binding.hpp")
    assert_equal File.join(ROOT, "ext/.clang-format"), format.style
    assert_equal CPP_FILES.sources, tidy.files
    assert_includes tidy.files, File.join(ROOT, "ext/lota/native_test/native_test.cpp")
    assert_equal File.join(ROOT, "ext/.clang-tidy"), tidy.config
    assert_equal File.expand_path(ENGINE.compile_commands), tidy.compile_commands
    assert_equal File.join(ROOT, "ext"), tidy.headers
  end

  def test_a_cpp_gate_task_fails_the_gate_on_a_file_with_a_problem
    in_tree do |root|
      system("git", "init", "--quiet", root, exception: true)
      write(root, "ext/bad.cpp", "int  main( ){return 0;}\n")
      system("git", "-C", root, "add", "ext/bad.cpp", exception: true)

      _, err = capture_io do
        error = assert_raises(SystemExit) { cpp_gate!("cpp:format", cpp_format(CppGates::Files.new(root:)).check) }
        refute_predicate error, :success?
      end
      assert_includes err, "❌ cpp:format failed:\n"
      assert_includes err, "bad.cpp"
    end
  end

  def test_a_task_that_aborts_fails_the_test_with_what_it_printed
    Rake::Task.define_task("rake_tasks_test:abort") do
      puts "checked 1 file"
      abort "❌ rake_tasks_test:abort failed:\next/bad.cpp:1: error"
    end

    failure = assert_raises(Minitest::Assertion) { invoke("rake_tasks_test:abort") }
    assert_includes failure.message, "rake rake_tasks_test:abort exited with status 1:\nchecked 1 file\n"
    assert_includes failure.message, "❌ rake_tasks_test:abort failed:\next/bad.cpp:1: error"
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
