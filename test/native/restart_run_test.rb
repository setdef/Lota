# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"
require "desktop_input_lock"
require "rbconfig"
require "tmpdir"

# A game that restarts, end to end (Lota::Restart): each test runs the lota
# executable on test/games/restart in a Ruby of its own, which opens a real
# window or not, and reads the log the game's runs append to. LÖVE restarts
# in the same process (src/love.cpp, main); Lota replaces the process with
# itself, so the pid stays the same and a new Ruby, with a new Lota, runs.
# On Windows, where Ruby's exec starts a new process instead
# (Lota::Restart), each run has a pid of its own.
# The game opens no window unless a test says so, as nothing a restart
# carries depends on one, and a process that opened a window can make
# each restart wait seconds on a busy Mac (Lota::Restart). Those tests
# hold no desktop input lock (the desktop_input_lock gem). The one that
# opens windows holds it, silently, though the windows stay in the
# background (test/test_helper.rb) and it neither moves the pointer nor
# takes the focus, so it never waits on a person or another check's focus.
class RestartRunTest < Minitest::Test
  include NativeHelper

  GAME = File.join(ROOT, "test/games/restart")

  def setup
    super
    @directory = Dir.mktmpdir("lota-restart-test")
    @log = File.join(@directory, "log")
  end

  def teardown
    FileUtils.remove_entry(@directory)
    super
  end

  # Runs <tt>lota run</tt> on the game with +arguments+ and returns its
  # output and Process::Status. The load path travels in RUBYOPT, which a
  # restarted process inherits, as Ruby's own flags are not repeated but
  # for -w.
  def lota_run(*, environment: {})
    capture2e(run_environment.merge(environment), RbConfig.ruby, "-w", File.join(ROOT, "exe/lota"), "run", GAME, *)
  end

  # The environment every run here starts with: the load path, in
  # RUBYOPT, and the log.
  def run_environment
    native = File.dirname(File.dirname(loaded("lota/native")))
    native_test = File.dirname(loaded("lota_native_test"))
    load_path = [native, File.join(ROOT, "lib"), native_test].uniq.map { |path| "-I#{path}" }.join(" ")
    { "RUBYOPT" => load_path, "LOTA_RESTART_LOG" => @log }
  end

  # The lines of the log: [kind, fields] for each, with the fields as a
  # Hash of String to the text after the equals sign.
  def log(only: %w[load at_exit])
    File.readlines(@log, chomp: true).filter_map do |line|
      kind, rest = line.split(" ", 2)
      [kind, rest.scan(/(\w+)=(.*?)(?= \w+=|\z)/).to_h] if only.nil? || only.include?(kind)
    end
  end

  def test_a_restart_runs_the_game_again_in_the_same_process_and_hands_over_its_value
    output, status = lota_run("string")

    assert_equal 3, status.exitstatus, output
    kinds = log.map(&:first)

    assert_equal %w[load at_exit load at_exit], kinds, "the first run ended before the second began"
    first, first_exit, second, second_exit = log.map(&:last)

    assert_equal first["pid"], second["pid"], "exec keeps the process"
    assert_equal [first["pid"]] * 2, [first_exit["pid"], second_exit["pid"]]
    assert_equal "nil", first["restart"]
    assert_equal "\"café\\nline\"", second["restart"]
    assert_equal %w[false false], [first["variable"], second["variable"]], "the value is read once and removed"
    assert_equal [%(["string"])] * 2, [first["arguments"], second["arguments"]], "the same arguments"
    assert_equal %w[true true], [first["verbose"], second["verbose"]], "-w is kept"
  end

  # Asserts that the runs whose process ids are +pids+ replaced each
  # other as exec does: in the same process on macOS and Linux, and each in
  # a process of its own on Windows, where Ruby's exec starts the command
  # as a new process and waits for it (Lota::Restart), as
  # .github/windows_checks.rb's restart check shows.
  def assert_exec_replaced_the_process(pids)
    if Gem.win_platform?
      assert_equal pids.uniq, pids, "on Windows each run is a process of its own"
    else
      assert_equal [pids.first] * pids.size, pids, "exec keeps the process"
    end
  end

  # One lota run restarts once for each kind, each restart with the next
  # kind's value, so each crosses an exec of its own.
  def test_every_kind_of_value_arrives_as_the_event_queue_carries_it
    expected = {
      "nil" => "nil",
      "none" => "nil",
      "true" => "true",
      "false" => "false",
      "number" => "2.5",
      "integer" => "7.0",
      "symbol" => '"name"',
      "empty" => '""',
      "extra" => '"first"',
      "binary" => '"\xFF\u0000"',
      "table" => '[1.0, {"name" => "ada"}]',
    }
    output, status = lota_run("chain", *expected.keys)

    assert_equal 3, status.exitstatus, output
    loads = log.filter_map { |kind, fields| fields if kind == "load" }

    assert_equal expected.size + 1, loads.size, output
    assert_equal ["nil", *expected.values], loads.map { |fields| fields["restart"] }
    assert_exec_replaced_the_process(loads.map { |fields| fields["pid"] })
  end

  # The only test with windows: the first run closes its window before the
  # process is replaced, and the second opens a window of its own.
  def test_a_restart_closes_the_window_and_the_new_run_opens_its_own
    output, status = DesktopInputLock.hold(speak: false) do
      lota_run("string", environment: { "LOTA_RESTART_WINDOW" => "1" })
    end

    assert_equal 3, status.exitstatus, output
    kinds = log(only: nil).map(&:first)

    assert_equal %w[load window at_exit close closed load window at_exit], kinds, output
    _, opened, _, was_open, closed, _, reopened, = log(only: nil).map(&:last)

    assert_equal "true", opened["shown"], "the first run had a window"
    assert_equal "true", was_open["was_shown"], "the window was still open when Lota closed it"
    assert_equal "false", closed["shown"], "and closed before the process was replaced"
    assert_equal "true", reopened["shown"], "the second run opens a window of its own"
    assert_exec_replaced_the_process(log(only: %w[load]).map { |_, fields| fields["pid"] })
  end

  def test_a_game_that_quits_does_not_start_again
    output, status = lota_run("never")

    assert_predicate status, :success?, output
    assert_equal %w[load at_exit], log.map(&:first)
  end

  def test_the_value_a_game_starts_with_is_read_once_whoever_wrote_it
    text = Lota::Restart.__send__(:encode, "hello")
    _, status = lota_run("never", environment: { "LOTA_RESTART_VALUE" => text })

    assert_predicate status, :success?
    assert_equal ['"hello"', "false"], log.first.last.values_at("restart", "variable")

    FileUtils.rm_f(@log)
    lota_run("never", environment: { "LOTA_RESTART_VALUE" => "eval:exit!(9)" })

    assert_equal ["nil", "false"], log.first.last.values_at("restart", "variable")
  end

  # bundle exec loads a Ruby program in its own process, so Ruby's
  # Process.argv0 is bundle, while $0 is the program (Bundler::CLI::Exec,
  # kernel_load). The program here stands for the wrapper RubyGems
  # installs as lota, with the .bat beside it that Windows runs, whose
  # first line Bundler reads to know it runs Ruby.
  def test_a_restart_under_bundle_exec_runs_the_game_again_and_not_bundle
    wrapper = File.join(@directory, "lota")
    File.write(wrapper, "#!/usr/bin/env ruby\nload #{File.join(ROOT, 'exe/lota').inspect}\n")
    File.chmod(0o755, wrapper)
    File.write("#{wrapper}.bat", "@\"ruby.exe\" \"%~dpn0\" %*\r\n")
    bundle = Gem.bin_path("bundler", "bundle")
    output, status = capture2e(run_environment.merge("BUNDLE_GEMFILE" => File.join(ROOT, "Gemfile")),
      RbConfig.ruby, bundle, "exec", wrapper, "run", GAME, "string")

    assert_equal 3, status.exitstatus, output
    assert_equal %w[load at_exit load at_exit], log.map(&:first), output
    first, _, second, = log.map(&:last)

    assert_equal "\"café\\nline\"", second["restart"]
    assert_equal [%(["string"])] * 2, [first["arguments"], second["arguments"]], "the same arguments"
  end

  # The entry script lota fuse writes (Lota::Fuse), run by Ruby itself
  # rather than by Fledge's launcher, as a developer may run it: the
  # program the process runs is Ruby's, so the game starts again through
  # Ruby and the script, with the arguments it was given.
  def test_a_fused_game_run_by_ruby_restarts_through_ruby_and_its_script
    FileUtils.mkdir_p(File.join(@directory, "game"))
    FileUtils.cp_r(GAME, File.join(@directory, "game", "restart"))
    entry = File.join(@directory, "main.rb")
    File.write(entry, <<~RUBY)
      require "lota"
      exit Lota::Boot.new(File.join(__dir__, "game", "restart"), ARGV, fused: true).call
    RUBY
    output, status = capture2e(run_environment, RbConfig.ruby, entry, "string")

    assert_equal 3, status.exitstatus, output
    assert_equal %w[load at_exit load at_exit], log.map(&:first), output
    first, _, second, = log.map(&:last)

    assert_equal "\"café\\nline\"", second["restart"]
    assert_equal [%(["string"])] * 2, [first["arguments"], second["arguments"]], "the same arguments"
    assert_exec_replaced_the_process([first["pid"], second["pid"]])
  end

  def test_nothing_is_left_to_restart_when_the_game_is_not_run_by_lota_run
    code = <<~RUBY
      require "lota"
      Lota::Restart.__send__(:take)
      p Lota.restart
    RUBY
    native = File.dirname(File.dirname(loaded("lota/native")))
    output, status = capture2e({ "LOTA_RESTART_VALUE" => Lota::Restart.__send__(:encode, 4) }, RbConfig.ruby,
      "-I#{native}", "-I#{File.join(ROOT, 'lib')}", "-e", code)

    assert_predicate status, :success?, output
    assert_equal "4.0\n", output
  end
end
